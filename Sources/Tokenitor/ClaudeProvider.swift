import Foundation

/// 通过社区发现的未公开 OAuth 用量端点抓取 Claude（含 Claude Code 与订阅用量）用量。
///   端点: https://api.anthropic.com/api/oauth/usage
///   鉴权: Bearer <accessToken>，token 取自 ~/.claude/.credentials.json
///   头部: anthropic-beta: oauth-2025-04-20
/// 该端点返回 5 小时窗口与 7 天窗口（含 Sonnet 单独配额）的已用百分比与重置时间。
/// 注意：非官方接口，可能随时变化；解析做了宽容处理，失败时优雅降级。
final class ClaudeProvider: UsageProvider {
    let displayName = "Claude"
    // 高级·自担风险：开关开启「且」已确认风险，才真正联网读取。
    var enabled: Bool { Settings.shared.claudeEnabled && Settings.shared.claudeRiskAccepted }

    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let auth = ClaudeAuth()

    // 诚实标识自己，不再伪装成官方 claude-code 客户端（合规取舍）。
    // 该端点会按 User-Agent 分桶限流：诚实 UA 更易被限流（429），此时走磁盘缓存兜底、优雅降级，
    // 不再靠伪装官方客户端去绕过其反滥用限流。默认关闭、需用户在设置里确认风险后开启。
    private static let userAgent = "Tokenitor/1.0.0"

    // 缓存上次成功的数据（内存 + 磁盘），限流/暂态/启动时继续展示，避免面板变灰
    private var lastWindows: [UsageWindow] = []
    private var lastOK: Date?
    private var cooldownUntil: Date?   // 429 退避：此时间前不再打网络
    private var cacheLoaded = false
    private var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokenitor/claude-cache.json")
    }

    func fetch(completion: @escaping (ProviderSnapshot) -> Void) {
        ensureCacheLoaded()   // 启动后第一次从磁盘载入上次数据
        // 限流冷却中且有缓存 → 直接给缓存，跳过网络，避免继续撞 429
        if let cd = cooldownUntil, Date() < cd, !lastWindows.isEmpty {
            completion(staleSnapshot(reason: "限流中"))
            return
        }
        auth.accessToken { token, err in
            guard let token = token else {
                // 没有订阅凭证 = 未在使用 Claude 订阅 → 隐藏（有缓存则显示上次）
                if self.lastWindows.isEmpty { completion(.absent(self.displayName)) }
                else { completion(self.staleSnapshot(reason: "凭证读取失败")) }
                return
            }
            self.callUsage(token: token) { status in
                self.handle(status, refreshed: false, completion: completion)
            }
        }
    }

    private func handle(_ status: UsageStatus, refreshed: Bool,
                        completion: @escaping (ProviderSnapshot) -> Void) {
        switch status {
        case .ok(let windows):
            lastWindows = windows; lastOK = Date(); cooldownUntil = nil
            saveCache(windows)
            // 卡片保持干净：不再挂"订阅共享用量 · Mac App / 网页 / Claude Code"描述文字
            //（该说明已在侧边栏「说明」页 → 各 AI 如何接入 → Claude 里）。失效/降级时的 note 仍保留。
            completion(ProviderSnapshot(name: displayName, windows: windows, ok: true,
                                        error: nil, note: nil))
        case .unauthorized:
            if refreshed {
                completion(failOrCached("订阅 token 已失效，请重新用订阅账号 /login"))
            } else {
                // token 过期，强制续期一次再试
                auth.accessToken(forceRefresh: true) { token2, _ in
                    guard let token2 = token2 else {
                        completion(self.failOrCached("订阅 token 已过期且续期失败，请重新用订阅账号 /login（详见 README）"))
                        return
                    }
                    self.callUsage(token: token2) { self.handle($0, refreshed: true, completion: completion) }
                }
            }
        case .rateLimited(let retryAfter):
            // 默认退避 3 分钟 + 随机抖动，降低再次撞 429 的概率
            cooldownUntil = Date().addingTimeInterval((retryAfter ?? 180) + Double.random(in: 0...30))
            completion(failOrCached("接口限流，显示上次数据"))
        case .failed(let msg):
            completion(failOrCached(msg))
        }
    }

    /// 有缓存就显示缓存数据（附带提示），否则报错。
    private func failOrCached(_ msg: String) -> ProviderSnapshot {
        if !lastWindows.isEmpty {
            return ProviderSnapshot(name: displayName, windows: lastWindows, ok: true,
                                    error: nil, note: "（\(msg)）显示上次数据 \(timeStr())")
        }
        return .failed(displayName, msg)
    }

    private func staleSnapshot(reason: String) -> ProviderSnapshot {
        ProviderSnapshot(name: displayName, windows: lastWindows, ok: true,
                         error: nil, note: "\(reason)，显示上次数据 \(timeStr())")
    }

    private func timeStr() -> String {
        guard let t = lastOK else { return "" }
        let df = DateFormatter(); df.dateFormat = "HH:mm"
        return df.string(from: t)
    }

    // MARK: - 磁盘缓存（启动/限流时显示上次数据，而非红色错误）

    private func ensureCacheLoaded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard lastWindows.isEmpty,
              let data = try? Data(contentsOf: cacheURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["windows"] as? [[String: Any]] else { return }
        lastWindows = arr.compactMap { d in
            guard let used = JSON.double(d["used"]), let label = d["label"] as? String else { return nil }
            let reset = JSON.double(d["resetMs"]).map { Date(timeIntervalSince1970: $0 / 1000) }
            return UsageWindow(usedPercent: used, resetsAt: reset, label: label)
        }
        if let savedMs = JSON.double(obj["savedAtMs"]) {
            lastOK = Date(timeIntervalSince1970: savedMs / 1000)
        }
    }

    private func saveCache(_ windows: [UsageWindow]) {
        let arr: [[String: Any]] = windows.map { w in
            var d: [String: Any] = ["used": w.usedPercent, "label": w.label]
            if let r = w.resetsAt { d["resetMs"] = r.timeIntervalSince1970 * 1000 }
            return d
        }
        let obj: [String: Any] = ["windows": arr, "savedAtMs": Date().timeIntervalSince1970 * 1000]
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: cacheURL)
        }
    }

    private enum UsageStatus {
        case ok([UsageWindow])
        case unauthorized
        case rateLimited(TimeInterval?)
        case failed(String)
    }

    private func callUsage(token: String, completion: @escaping (UsageStatus) -> Void) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 12
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")   // 诚实 UA，不伪装官方客户端

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                completion(.failed("网络错误: \(err.localizedDescription)"))
                return
            }
            guard let data = data else { completion(.failed("空响应")); return }
            DebugLog.dump("claude-usage", data)

            if let http = resp as? HTTPURLResponse {
                if http.statusCode == 401 || http.statusCode == 403 {
                    completion(.unauthorized); return
                }
                if http.statusCode == 429 {
                    let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
                    completion(.rateLimited(ra)); return
                }
                if http.statusCode != 200 {
                    completion(.failed("HTTP \(http.statusCode)")); return
                }
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) else {
                completion(.failed("解析失败")); return
            }
            let windows = self.parse(root)
            if windows.isEmpty {
                completion(.failed("未识别到用量字段（接口可能已变动，可开启调试转储排查）"))
            } else {
                completion(.ok(windows))
            }
        }.resume()
    }

    /// 把响应里所有“窗口对象”归类成 5h / 周 / 周(Sonnet)，并去重。
    /// 该端点会在多个字段名下重复给出同一份数据（如 limits 容器里再放一份），
    /// 还有 spend/cost 这类“非用量窗口”，这里统一过滤+去重。
    private func parse(_ root: Any) -> [UsageWindow] {
        let found = JSON.findWindowObjects(root)

        // 用 (取整百分比 + 重置时间分钟) 作为去重签名；同签名只留标签更明确的那条。
        var bySig: [String: UsageWindow] = [:]
        var sigOrder: [String] = []

        for (key, dict) in found {
            guard let used = JSON.extractPercent(dict) else { continue }
            let kl = key.lowercased()
            // 跳过花费/余额类，不是 5h/周限额
            if ["spend", "cost", "balance", "overage", "credit"].contains(where: { kl.contains($0) }) {
                continue
            }
            let reset = JSON.extractReset(dict)
            let label = Self.label(forKey: key, dict: dict)
            let resetMin = reset.map { Int($0.timeIntervalSince1970 / 60) } ?? -1
            let sig = "\(Int(used.rounded()))|\(resetMin)"
            let candidate = UsageWindow(usedPercent: used, resetsAt: reset, label: label)
            if let existing = bySig[sig] {
                if Self.labelScore(label) > Self.labelScore(existing.label) {
                    bySig[sig] = candidate // 同一窗口，保留更明确的标签（5h/weekly 优于 limits）
                }
            } else {
                bySig[sig] = candidate
                sigOrder.append(sig)
            }
        }

        let result = sigOrder.compactMap { bySig[$0] }
        // 排序：5h 在前，周在后；带模型名的排其后
        let order: (UsageWindow) -> Int = { w in
            if w.label.contains("5h") { return 0 }
            if w.label.lowercased().contains("sonnet") || w.label.lowercased().contains("opus") { return 2 }
            return 1
        }
        return result.sorted { order($0) < order($1) }
    }

    /// 标签明确度评分：5h / weekly 最高，带模型的次之，limits/泛化最低。
    private static func labelScore(_ label: String) -> Int {
        let l = label.lowercased()
        var s = 0
        if label.contains("5h") || l.contains("week") { s += 2 }
        if l.contains("opus") || l.contains("sonnet") { s += 1 }
        if l.contains("limit") || l.contains("usage") { s -= 1 }
        return s
    }

    private static func label(forKey key: String, dict: [String: Any]) -> String {
        let k = key.lowercased()
        // 是否为周窗口
        let isWeekly = k.contains("seven") || k.contains("week") || k.contains("7")
        let isFiveHour = k.contains("five") || k.contains("5h") || k.contains("hour") || k.contains("session")
        // 模型标记
        var model = ""
        if k.contains("opus") { model = " Opus" }
        else if k.contains("sonnet") { model = " Sonnet" }

        if isFiveHour && !isWeekly { return "5h\(model)" }
        if isWeekly { return "weekly\(model)" }
        // 用 window_minutes 兜底判断
        if let mins = JSON.double(JSON.firstValue(in: dict, keys: ["window_minutes", "windowMinutes"])) {
            return mins <= 360 ? "5h\(model)" : "weekly\(model)"
        }
        return key.isEmpty ? "usage\(model)" : "\(key)\(model)"
    }
}
