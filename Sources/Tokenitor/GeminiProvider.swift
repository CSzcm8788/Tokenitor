import Foundation

/// 读取 Gemini CLI 的「今日用量」。
/// 口径：个人 Google 账号免费档约 1000 次请求/天（按天重置）。
/// 数据来源：~/.gemini/tmp/<user>/logs.json（数组，含 {type:"user", timestamp}）
///          及 chats/session-*.jsonl 里的用户轮次。统计今天的用户请求数估算用量。
/// 说明：这是本机 CLI 的本地估算，不含网页/其它端的服务端总账。
/// ⚠️ 2026-06-18 起 Google 已对个人账号停服旧版 Gemini CLI（迁移到 Antigravity CLI `agy`），
///    个人账号的 ~/.gemini 日志将不再增长。为避免显示过期的 0%，这里加了「活跃度」判定：
///    最近一段时间没有新活动就视为「未在使用」自动隐藏（企业版仍在用则照常显示）。
final class GeminiProvider: UsageProvider {
    let displayName = "Gemini"
    var enabled: Bool { Settings.shared.geminiEnabled }

    private let geminiDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini")
    }()
    /// 每日额度（估算分母）：官方额度按账号类型/时段在 250–2000 之间浮动且本地不可读，
    /// 故取用户在设置里选定的值（默认 1000），并在界面上明确标注是本地估算。
    private var dailyLimit: Double { Settings.shared.geminiDailyLimit }
    private let staleAfter: TimeInterval = 36 * 3600   // 超过 36h 无活动 → 视为未在使用

    func fetch(completion: @escaping (ProviderSnapshot) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            // 未安装/未用过 → 隐藏
            guard FileManager.default.fileExists(atPath: self.geminiDir.path) else {
                completion(.absent(self.displayName)); return
            }
            // 近期无任何活动（含旧版 CLI 已停服的情况）→ 隐藏，避免显示过期数据
            guard self.recentlyActive() else {
                completion(.absent(self.displayName)); return
            }
            let used = self.todayRequestCount()
            let pct = max(0, min(100, used / max(1, self.dailyLimit) * 100))
            let w = UsageWindow(usedPercent: pct, resetsAt: self.nextLocalMidnight(), label: "daily")
            let limit = self.dailyLimit
            completion(ProviderSnapshot(name: self.displayName, windows: [w], ok: true,
                                        error: nil,
                                        note: L("今日约 \(Int(used))/\(Int(limit)) 次 · 本地估算（额度可在设置调整）",
                                                "~\(Int(used))/\(Int(limit)) requests today · local estimate (limit adjustable in Settings)")))
        }
    }

    /// ~/.gemini/tmp 树里是否存在 staleAfter 内被修改过的文件（判断 CLI 是否还在被使用）。
    private func recentlyActive() -> Bool {
        let fm = FileManager.default
        let tmp = geminiDir.appendingPathComponent("tmp")
        guard let en = fm.enumerator(at: tmp,
                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles]) else { return false }
        let cutoff = Date().addingTimeInterval(-staleAfter)
        for case let url as URL in en {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mod, mod >= cutoff { return true }
        }
        return false
    }

    /// 统计今天（本地日）的用户请求数：扫描 logs.json + 各 session jsonl，
    /// 取 type/role=="user" 且时间戳为今天的条目，用时间戳去重。
    /// 统计今天（本地日）的用户请求数。
    /// **同一项目目录内以 `logs.json` 为准**，只有它缺失或今日无记录时才回退扫 `chats/*.jsonl`：
    /// 两个来源记的是同一批提问，但时间戳相差数秒（实测约 4s），按时间戳去重根本对不上，
    /// 合并计数会让用量成倍虚高（实测 2 次提问被数成 4 次）。
    private func todayRequestCount() -> Double {
        let fm = FileManager.default
        let tmp = geminiDir.appendingPathComponent("tmp")
        guard let userDirs = try? fm.contentsOfDirectory(at: tmp,
                                                          includingPropertiesForKeys: nil) else { return 0 }
        return Double(Self.countToday(userDirs: userDirs,
                                      todayStart: Calendar.current.startOfDay(for: Date())))
    }

    /// 计数主体（internal 供测试直接喂临时目录，覆盖「双源同一提问」的去重场景）。
    static func countToday(userDirs: [URL], todayStart: Date) -> Int {
        let fm = FileManager.default
        var seen = Set<String>()

        for ud in userDirs {
            var perDir = Set<String>()

            // 主源：logs.json（CLI 记录的用户提问流水）
            let logs = ud.appendingPathComponent("logs.json")
            if let data = try? Data(contentsOf: logs),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                collectUserEvents(arr, todayStart: todayStart, into: &perDir)
            }

            // 回退：logs.json 缺失或今日无记录时才扫会话文件（新版 CLI 可能不再写 logs.json）
            if perDir.isEmpty {
                let chats = ud.appendingPathComponent("chats")
                if let files = try? fm.contentsOfDirectory(at: chats, includingPropertiesForKeys: nil) {
                    for f in files where f.pathExtension == "jsonl" {
                        guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
                        for line in text.split(separator: "\n") {
                            guard let d = line.data(using: .utf8),
                                  let o = try? JSONSerialization.jsonObject(with: d) else { continue }
                            collectUserEvents([o], todayStart: todayStart, into: &perDir)
                        }
                    }
                }
            }
            seen.formUnion(perDir)
        }
        return seen.count
    }

    static func collectUserEvents(_ items: [Any], todayStart: Date, into seen: inout Set<String>) {
        for case let o as [String: Any] in items {
            let kind = (o["type"] as? String) ?? (o["role"] as? String) ?? ""
            guard kind == "user" else { continue }
            guard !isBootstrapMessage(o) else { continue }   // CLI 自动注入的上下文不是用户请求
            guard let tsStr = o["timestamp"] as? String,
                  let ts = Self.parseISO(tsStr) else { continue }
            guard ts >= todayStart else { continue }     // 仅今天
            seen.insert(tsStr)                            // 用时间戳去重（同源跨文件同条只算一次）
        }
    }

    /// CLI 会话开头自动注入的 `<session_context>` 上下文消息：类型是 user，但不是用户发起的请求。
    static func isBootstrapMessage(_ o: [String: Any]) -> Bool {
        var text = o["message"] as? String ?? ""
        if text.isEmpty, let parts = o["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        if text.isEmpty, let c = o["content"] as? String { text = c }
        return text.hasPrefix("<session_context>")
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static func parseISO(_ s: String) -> Date? {
        isoFrac.date(from: s) ?? iso.date(from: s)
    }

    private func nextLocalMidnight() -> Date? {
        Calendar.current.nextDate(after: Date(),
                                  matching: DateComponents(hour: 0, minute: 0),
                                  matchingPolicy: .nextTime)
    }
}
