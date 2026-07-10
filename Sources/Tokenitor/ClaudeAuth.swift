import Foundation
import Security

/// 管理 Claude 订阅 OAuth 凭证：读取、自动续期（refresh token）、持久化。
/// 续期后的新凭证存进 **macOS 钥匙串**（加密、访问受控），不再明文落盘；旧版明文缓存
/// ~/.tokenitor/claude-creds.json 会在首次读取时自动迁移进钥匙串并删除。
///
/// 凭证分两条线，续期策略不同：
///  · **自己的线**（Tokenitor 钥匙串条目 / 旧版明文缓存）：可以用 refresh token 续期。
///  · **Claude Code 的线**（~/.claude/.credentials.json 与其钥匙串条目）：**只读、绝不续期**。
///    否则服务端轮换 refresh token 后，新 token 只在我们手里，Claude Code 存的那份随即失效，
///    等于把用户的 Claude Code 登出——这是历史版本的真实事故来源。
final class ClaudeAuth {

    struct Creds {
        var access: String
        var refresh: String?
        var expiresAt: Date?
        /// 凭证 JSON 里的订阅档位（subscriptionType，如 pro/max），仅展示用。
        var subscriptionType: String?
        /// true = Tokenitor 自己的 token 线（可续期）；false = 读取自 Claude Code（只读）。
        var ownedByTokenitor = false
    }

    /// 最近一次 loadCreds 读到的订阅档位（已过可信映射；nil = 不显示）。
    private(set) var currentPlan: String?

    // Claude Code 公开 OAuth 客户端 ID（社区通用值）。
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    // 续期端点：platform.claude.com 实测有效（返回标准 OAuth 响应）；其余作兜底。
    private let tokenURLs = [
        "https://platform.claude.com/v1/oauth/token",
        "https://console.anthropic.com/v1/oauth/token"
    ].compactMap { URL(string: $0) }

    // 旧版明文缓存路径（仅用于一次性迁移到钥匙串后删除）。
    private var legacyCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokenitor/claude-creds.json")
    }
    // 本应用自己的钥匙串条目（与 Claude Code 的条目区分开）。
    private let kcService = "com.tokenitor.app"
    private let kcAccount = "claude-oauth-creds"
    private let claudeFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }()

    // 已确认失效（invalid_grant）的 refresh token：本次运行内不再重试，
    // 避免"清缓存 → 下轮又读回同一个死 token → 再续期失败"的无退避循环打爆 token 端点。
    private let deadLock = NSLock()
    private var deadRefreshTokens = Set<String>()

    private func isDead(_ rt: String) -> Bool {
        deadLock.lock(); defer { deadLock.unlock() }
        return deadRefreshTokens.contains(rt)
    }
    private func markDead(_ rt: String) {
        deadLock.lock(); defer { deadLock.unlock() }
        deadRefreshTokens.insert(rt)
    }

    /// 拿到一个可用的 access token（必要时自动续期——仅限自己的 token 线）。
    /// 回调：(token, errorMessage)。token 为 nil 时给出原因。
    func accessToken(forceRefresh: Bool = false, completion: @escaping (String?, String?) -> Void) {
        if forceRefresh { invalidateReadCache() }   // 疑似过期：别家条目缓存作废，重读拿最新
        guard let creds = loadCreds() else {
            completion(nil, L("未找到 Claude 订阅凭证（请用订阅账号 /login 一次）", "No Claude subscription credentials found (run /login once with your subscription account)"))
            return
        }
        let nearExpiry = creds.expiresAt.map { $0.timeIntervalSinceNow < 300 } ?? false  // 提前 5 分钟续
        if !forceRefresh && !nearExpiry {
            completion(creds.access, nil)
            return
        }
        // Claude Code 的凭证只读：过期也不代它续期（见类头注释），提示用户让 Claude Code 自己续。
        guard creds.ownedByTokenitor else {
            if forceRefresh {
                completion(nil, L("订阅 token 已过期。请在 Claude Code 里任意执行一次请求让它自动续期，再回来点刷新", "Subscription token expired. Run any request in Claude Code so it refreshes itself, then hit Refresh here"))
            } else {
                completion(creds.access, nil)  // 临近过期但可能仍可用，先试
            }
            return
        }
        guard let rt = creds.refresh, !isDead(rt) else {
            // 没有 refresh token / token 已确认失效：只能先用现有 access（可能已过期）
            if forceRefresh {
                completion(nil, L("订阅登录已失效，请重新用订阅账号 /login", "Subscription login invalid; run /login again with your subscription account"))
            } else {
                completion(creds.access, nil)
            }
            return
        }
        refresh(using: rt) { newCreds, err in
            if var nc = newCreds {
                nc.ownedByTokenitor = true
                self.save(nc)
                completion(nc.access, nil)
            } else {
                // refresh token 失效：记入黑名单不再重试，并清掉本地缓存凭证
                if err == "invalid_grant" {
                    self.markDead(rt)
                    self.purgeCache()
                    completion(nil, L("订阅登录已失效，请重新用订阅账号 /login", "Subscription login invalid; run /login again with your subscription account"))
                } else {
                    completion(creds.access, err)  // 暂态失败：退回旧 token
                }
            }
        }
    }

    /// 删除本地凭证缓存（refresh 失效时），使下次从 Claude Code 钥匙串重新读取。
    private func purgeCache() {
        keychainDelete()
        try? FileManager.default.removeItem(at: legacyCacheURL)
        log("Claude 凭证缓存已清除（refresh 失效）")
    }

    // MARK: - 续期

    /// 一次续期尝试：端点 × 请求体格式（form / json）。
    private struct Attempt { let url: URL; let form: Bool }

    private func refresh(using refreshToken: String, completion: @escaping (Creds?, String?) -> Void) {
        // 每个端点先试标准 form-urlencoded（RFC 6749），再试 JSON 兜底
        var attempts: [Attempt] = []
        for url in tokenURLs { attempts.append(Attempt(url: url, form: true)); attempts.append(Attempt(url: url, form: false)) }
        tryAttempt(attempts, 0, refreshToken: refreshToken, completion: completion)
    }

    private func tryAttempt(_ attempts: [Attempt], _ i: Int, refreshToken: String,
                            completion: @escaping (Creds?, String?) -> Void) {
        guard i < attempts.count else {
            completion(nil, L("自动续期失败，请重新用订阅账号 /login", "Auto-refresh failed; run /login again with your subscription account"))
            return
        }
        let a = attempts[i]
        var req = URLRequest(url: a.url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")   // 诚实 UA，不伪装官方 CLI
        if a.form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
            let rt = refreshToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? refreshToken
            req.httpBody = "grant_type=refresh_token&refresh_token=\(rt)&client_id=\(clientID)".data(using: .utf8)
        } else {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID
            ])
        }

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if let data = data { DebugLog.dump("claude-refresh-\(a.form ? "form" : "json")-\(code)", data) }

            guard code == 200,
                  let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = JSON.firstValue(in: root, keys: ["access_token", "accessToken"]) as? String
            else {
                // refresh token 已失效（被轮换/吊销）→ 无需再试其它端点，直接报失效
                let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                if body.contains("invalid_grant") {
                    completion(nil, "invalid_grant")
                    return
                }
                self.tryAttempt(attempts, i + 1, refreshToken: refreshToken, completion: completion)
                return
            }
            let newRefresh = (JSON.firstValue(in: root, keys: ["refresh_token", "refreshToken"]) as? String) ?? refreshToken
            var expires: Date? = nil
            if let secs = JSON.double(JSON.firstValue(in: root, keys: ["expires_in", "expiresIn"])) {
                expires = Date().addingTimeInterval(secs)
            } else {
                expires = JSON.date(JSON.firstValue(in: root, keys: ["expires_at", "expiresAt"]))
            }
            log("Claude 续期成功（\(a.form ? "form" : "json")）")
            completion(Creds(access: token, refresh: newRefresh, expiresAt: expires,
                             ownedByTokenitor: true), nil)
        }.resume()
    }

    // MARK: - 读取（自己的钥匙串 → 旧版明文缓存 → Claude Code 文件/钥匙串）

    private func loadCreds() -> Creds? {
        // 汇集所有来源，挑过期时间最新的那份（自愈：重新登录后会自动采用更新的凭证）。
        // 注意：Claude Code 的凭证只读取、不回写进自己的钥匙串——保持两条 token 线彼此独立。
        var candidates: [Creds] = []
        // 1) 我们自己的钥匙串条目（可续期）
        if let data = keychainLoad(), var c = parse(data) {
            c.ownedByTokenitor = true
            candidates.append(c)
        }
        // 2) 旧版明文缓存（当年由 Tokenitor 续期后写下 → 属自己的线）：迁移进钥匙串后删除
        if let data = try? Data(contentsOf: legacyCacheURL), var c = parse(data) {
            c.ownedByTokenitor = true
            save(c)
            try? FileManager.default.removeItem(at: legacyCacheURL)
            candidates.append(c)
        }
        // 3) Claude Code 自己的凭证（文件 + 钥匙串），只读、不改、不续期
        if let data = try? Data(contentsOf: claudeFileURL), let c = parse(data) { candidates.append(c) }
        for service in ["Claude Code-credentials", "Claude Code", "Claude"] {
            if let data = readKeychain(service: service), let c = parse(data) { candidates.append(c) }
        }
        guard !candidates.isEmpty else { return nil }
        let best = candidates.max { a, b in
            (a.expiresAt ?? .distantPast) < (b.expiresAt ?? .distantPast)
        }
        // 档位仅展示用：取任一来源里能读到的 subscriptionType（过可信映射，读不到就不显示）
        currentPlan = PlanTier.claude(best?.subscriptionType
            ?? candidates.compactMap(\.subscriptionType).first)
        return best
    }

    /// 解析凭证 JSON（兼容 {claudeAiOauth:{...}} 与扁平结构）。
    private func parse(_ data: Data) -> Creds? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let container = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let access = JSON.firstValue(in: container, keys: ["accessToken", "access_token", "token"]) as? String else {
            return nil
        }
        let refresh = JSON.firstValue(in: container, keys: ["refreshToken", "refresh_token"]) as? String
        var expires: Date? = nil
        if let v = JSON.firstValue(in: container, keys: ["expiresAt", "expires_at"]) {
            expires = JSON.date(v)
        }
        let sub = JSON.firstValue(in: container, keys: ["subscriptionType", "subscription_type"]) as? String
        return Creds(access: access, refresh: refresh, expiresAt: expires, subscriptionType: sub)
    }

    /// 写回凭证到钥匙串（加密、访问受控），不再明文落盘。
    private func save(_ c: Creds) {
        var obj: [String: Any] = ["accessToken": c.access]
        if let r = c.refresh { obj["refreshToken"] = r }
        if let e = c.expiresAt { obj["expiresAt"] = Int(e.timeIntervalSince1970 * 1000) }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        keychainSave(data)
    }

    // MARK: - 本应用自己的钥匙串条目（Security framework：加密存储，避免明文落盘与命令行参数暴露）

    private func keychainBaseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: kcService,
         kSecAttrAccount as String: kcAccount]
    }

    // 自己条目的读缓存（进程内）：本条目只由本类写入，故缓存读结果完全安全，
    // 消除每次刷新都 SecItemCopyMatching → 反复弹「允许访问钥匙串」（尤其 ad-hoc 签名时）。
    private var ownDataLoaded = false
    private var ownDataCache: Data?

    private func keychainSave(_ data: Data) {
        let status = SecItemUpdate(keychainBaseQuery() as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = keychainBaseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
        ownDataCache = data; ownDataLoaded = true   // 刚写入的即最新值，下次读直接命中缓存
    }

    private func keychainLoad() -> Data? {
        if ownDataLoaded { return ownDataCache }   // 命中进程内缓存，不再打钥匙串
        var q = keychainBaseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let data = SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
        ownDataCache = data; ownDataLoaded = true
        return data
    }

    private func keychainDelete() {
        SecItemDelete(keychainBaseQuery() as CFDictionary)
        ownDataCache = nil; ownDataLoaded = true
    }

    // 读别家（Claude Code）条目的进程内缓存：service → 结果（含"读过但为空"）。
    // 别家条目可能被 Claude Code 在外部续期，故 forceRefresh 时主动失效（见 accessToken）；
    // 稳态下不再每 60 秒重复读三个 service、反复弹授权框。
    private var readCache: [String: Data?] = [:]

    /// forceRefresh（token 疑似过期）时清掉别家条目缓存，下一轮 loadCreds 重读拿最新 token。
    private func invalidateReadCache() { readCache.removeAll() }

    /// 读取其它应用（Claude Code）的钥匙串条目 —— 用 Security API 而非起 `/usr/bin/security` 子进程：
    /// 授权弹窗的请求方是 Tokenitor 本体，用户点「始终允许」也只放行本应用的签名身份；
    /// 走 `security` 命令行则会把系统二进制加进条目 ACL，此后任何进程都能借它静默读走凭证。
    private func readKeychain(service: String) -> Data? {
        if let cached = readCache[service] { return cached }   // 命中缓存（含空结果）
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let result: Data?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, !data.isEmpty {
            // 钥匙串里可能是 JSON，也可能是裸 token
            let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            result = s.hasPrefix("{") ? data : ("{\"accessToken\":\"" + s + "\"}").data(using: .utf8)
        } else {
            result = nil
        }
        readCache[service] = result
        return result
    }
}
