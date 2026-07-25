import Foundation

/// Claude 用量的**本地**数据源：读 `~/.tokenitor/claude-statusline.json`。
///
/// 由来：Claude Code 每轮会把一份 JSON 交给 statusline 脚本的 stdin，其中 `rate_limits`
/// 带 5 小时窗口与 7 天窗口的 `used_percentage` / `resets_at`
///（官方 changelog：「Added `rate_limits` field to statusline scripts …（5-hour and 7-day
/// windows with `used_percentage` and `resets_at`）」）。打包的 `claude-statusline.sh`
/// 把这份 payload 原样落盘，本读取器只读文件。
///
/// 为什么不再首选 `api/oauth/usage`：该端点从未被官方支持，社区就其「持续 429、
/// retry-after: 0 仍然 429」提的多个 issue 都被关成 `not planned`；共识的轮询间隔已被拉到
/// 300–900s。本地这条路**零联网、零 429、零钥匙串弹窗**，也不涉及条款风险。
enum ClaudeStatusline {

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokenitor/claude-statusline.json")
    }

    /// statusline 脚本安装位置（由设置页一键安装，内容来自 App 内打包的同名脚本）。
    static var scriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokenitor/claude-statusline.sh")
    }

    /// Claude Code 的用户级配置（statusLine 就配在这里）。
    static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// 读一次本地用量。返回 nil = 没装桥 / 文件读不动 / 里头没有可用窗口。
    /// `asOf` 取文件修改时间（= Claude Code 最近一次落盘的时刻），供卡片显示「数据 X前」。
    static func read() -> (windows: [UsageWindow], asOf: Date)? {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let windows = parseWindows(obj)
        guard !windows.isEmpty else { return nil }
        let asOf = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return (windows, asOf ?? Date())
    }

    /// 从 payload 里取出用量窗口。internal 供测试。
    ///
    /// 解析刻意写得宽容：`rate_limits` 可能出现在任意层级，键名可能是 snake_case 或
    /// camelCase（我们只从官方 changelog 确认了字段语义，没有正式 schema 承诺）。
    /// 认不出的窗口一律跳过——**宁可少显示，也不猜**。
    static func parseWindows(_ obj: Any) -> [UsageWindow] {
        guard let rl = findRateLimits(obj) else { return [] }
        var out: [UsageWindow] = []
        // 固定顺序：5 小时窗口在前、周窗口在后（与 Codex / 其它源的展示顺序一致）
        for (keys, label) in [(["five_hour", "fiveHour", "5h"], "5h"),
                              (["seven_day", "sevenDay", "7d", "weekly"], "weekly")] {
            guard let w = keys.lazy.compactMap({ rl[$0] as? [String: Any] }).first,
                  let used = JSON.double(JSON.firstValue(in: w, keys: ["used_percentage", "usedPercentage",
                                                                      "used_percent", "utilization"]))
            else { continue }
            out.append(UsageWindow(usedPercent: max(0, min(100, used)),
                                   resetsAt: resetDate(w),
                                   label: label))
        }
        return out
    }

    /// `resets_at` 实测是 Unix 秒；也兼容毫秒与 ISO8601 字符串写法。
    private static func resetDate(_ w: [String: Any]) -> Date? {
        guard let v = JSON.firstValue(in: w, keys: ["resets_at", "resetsAt", "reset_at"]) else { return nil }
        if let s = v as? String { return parseISO(s) }
        guard let n = JSON.double(v) else { return nil }
        // > 1e12 视为毫秒（2001 年之后的秒级时间戳不会超过 1e10）
        return Date(timeIntervalSince1970: n > 1_000_000_000_000 ? n / 1000 : n)
    }

    /// 递归找 `rate_limits` / `rateLimits` 字典（不假设它在顶层）。
    private static func findRateLimits(_ obj: Any) -> [String: Any]? {
        if let d = obj as? [String: Any] {
            for key in ["rate_limits", "rateLimits"] {
                if let rl = d[key] as? [String: Any] { return rl }
            }
            for (_, v) in d {
                if let r = findRateLimits(v) { return r }
            }
        } else if let a = obj as? [Any] {
            for v in a {
                if let r = findRateLimits(v) { return r }
            }
        }
        return nil
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static func parseISO(_ s: String) -> Date? { isoFrac.date(from: s) ?? iso.date(from: s) }

    // MARK: - 一键安装 / 状态

    enum BridgeState {
        case installed                 // 脚本在位且 Claude Code 已指向它
        case notInstalled              // 没装
        case conflict(existing: String) // Claude Code 已有别的 statusLine，不能覆盖
    }

    /// 当前安装状态。`statusLine` 在 Claude Code 里是**独占**的一项，
    /// 已有别人的配置时绝不覆盖——那会让用户的状态栏莫名消失。
    static func state() -> BridgeState {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .notInstalled
        }
        guard let sl = root["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return .notInstalled }
        if cmd.contains("claude-statusline.sh"), FileManager.default.isExecutableFile(atPath: scriptURL.path) {
            return .installed
        }
        return .conflict(existing: cmd)
    }

    /// 安装：把 App 内打包的脚本复制到 `~/.tokenitor/`，并把 Claude Code 的 `statusLine`
    /// 指向它。改配置前先备份；已有别的 statusLine 则拒绝并让用户手动合并。
    /// 返回 nil 表示成功，否则返回给用户看的原因。
    static func install() -> String? {
        let fm = FileManager.default
        if case .conflict(let existing) = state() {
            return L("Claude Code 已配置了别的状态栏命令（\(existing)），不便覆盖。请手动在你的脚本里加一行把 stdin 落到 \(fileURL.path)。",
                     "Claude Code already has a different statusLine command (\(existing)); overwriting it would break your setup. Add a line to your own script that writes stdin to \(fileURL.path).")
        }
        guard let src = Bundle.main.url(forResource: "claude-statusline", withExtension: "sh") else {
            return L("应用内未找到 claude-statusline.sh（构建产物不完整）",
                     "claude-statusline.sh is missing from the app bundle")
        }
        do {
            try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: scriptURL.path) { try fm.removeItem(at: scriptURL) }
            try fm.copyItem(at: src, to: scriptURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            // 读改写 Claude Code 配置：只增 statusLine 一项，其余（如 hooks）原样保留
            var root: [String: Any] = [:]
            if let data = try? Data(contentsOf: claudeSettingsURL),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = obj
                let backup = claudeSettingsURL.deletingLastPathComponent()
                    .appendingPathComponent("settings.json.tokenitor-backup")
                try? data.write(to: backup)
            }
            root["statusLine"] = ["type": "command", "command": scriptURL.path, "padding": 0]
            let out = try JSONSerialization.data(withJSONObject: root,
                                                 options: [.prettyPrinted, .sortedKeys])
            try fm.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try out.write(to: claudeSettingsURL)
            return nil
        } catch {
            return L("安装失败：\(error.localizedDescription)", "Install failed: \(error.localizedDescription)")
        }
    }
}
