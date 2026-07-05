import Foundation
import Security

/// 管理 Claude 订阅 OAuth 凭证：读取、自动续期（refresh token）、持久化。
/// 续期后的新凭证存进 **macOS 钥匙串**（加密、访问受控），不再明文落盘；旧版明文缓存
/// ~/.tokenitor/claude-creds.json 会在首次读取时自动迁移进钥匙串并删除。
/// 读取时另会并读 Claude Code 自己的凭证（文件/钥匙串）作为来源，但从不修改它们。
final class ClaudeAuth {

    struct Creds {
        var access: String
        var refresh: String?
        var expiresAt: Date?
    }

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

    /// 拿到一个可用的 access token（必要时自动续期）。
    /// 回调：(token, errorMessage)。token 为 nil 时给出原因。
    func accessToken(forceRefresh: Bool = false, completion: @escaping (String?, String?) -> Void) {
        guard let creds = loadCreds() else {
            completion(nil, "未找到 Claude 订阅凭证（请用订阅账号 /login 一次）")
            return
        }
        let nearExpiry = creds.expiresAt.map { $0.timeIntervalSinceNow < 300 } ?? false  // 提前 5 分钟续
        if !forceRefresh && !nearExpiry {
            completion(creds.access, nil)
            return
        }
        guard let rt = creds.refresh else {
            // 没有 refresh token，只能先用现有 access（可能已过期）
            completion(creds.access, nil)
            return
        }
        refresh(using: rt) { newCreds, err in
            if let nc = newCreds {
                self.save(nc)
                completion(nc.access, nil)
            } else {
                // refresh token 失效：清掉本地缓存凭证，下次从钥匙串读取（重登后的新 token）
                if err == "invalid_grant" {
                    self.purgeCache()
                    completion(nil, "订阅登录已失效，请重新用订阅账号 /login")
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
            completion(nil, "自动续期失败，请重新用订阅账号 /login")
            return
        }
        let a = attempts[i]
        var req = URLRequest(url: a.url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Tokenitor/1.0.0", forHTTPHeaderField: "User-Agent")   // 诚实 UA，不伪装官方 CLI
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
            completion(Creds(access: token, refresh: newRefresh, expiresAt: expires), nil)
        }.resume()
    }

    // MARK: - 读取（缓存 → Claude 文件 → 钥匙串）

    private func loadCreds() -> Creds? {
        // 汇集所有来源，挑过期时间最新的那份（自愈：重新登录后会自动采用更新的凭证）。
        var candidates: [Creds] = []
        // 1) 我们自己的钥匙串条目（首选）
        if let data = keychainLoad(), let c = parse(data) { candidates.append(c) }
        // 2) 旧版明文缓存：仅为迁移而读，读后落钥匙串并删除
        var hadLegacy = false
        if let data = try? Data(contentsOf: legacyCacheURL), let c = parse(data) { candidates.append(c); hadLegacy = true }
        // 3) Claude Code 自己的凭证（文件 + 钥匙串），只读、不改
        if let data = try? Data(contentsOf: claudeFileURL), let c = parse(data) { candidates.append(c) }
        for service in ["Claude Code-credentials", "Claude Code", "Claude"] {
            if let data = readKeychain(service: service), let c = parse(data) { candidates.append(c) }
        }
        guard !candidates.isEmpty else { return nil }
        let best = candidates.max { a, b in
            (a.expiresAt ?? .distantPast) < (b.expiresAt ?? .distantPast)
        }!
        save(best) // 统一落进钥匙串
        if hadLegacy { try? FileManager.default.removeItem(at: legacyCacheURL) }  // 迁移完成，删除明文缓存
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
        return Creds(access: access, refresh: refresh, expiresAt: expires)
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

    private func keychainSave(_ data: Data) {
        let status = SecItemUpdate(keychainBaseQuery() as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = keychainBaseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func keychainLoad() -> Data? {
        var q = keychainBaseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private func keychainDelete() {
        SecItemDelete(keychainBaseQuery() as CFDictionary)
    }

    private func readKeychain(service: String) -> Data? {
        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, !out.isEmpty else { return nil }
        // 钥匙串里可能是 JSON，也可能是裸 token
        let s = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("{") { return out }
        return ("{\"accessToken\":\"" + s + "\"}").data(using: .utf8)
    }
}
