import Foundation

/// Claude **桌面 App** 的本地用量历史：读 `~/Library/Application Support/Claude/plan-usage-history.json`。
///
/// 桌面 App 自己每约 5 分钟拉一次账号用量并把采样追加到这个文件（实测 594 个样本、跨 8 天，
/// 桌面 App 未运行时不采样，故相邻间隔最大可达一天）。我们只读文件——零联网、零 429、
/// 不弹钥匙串，和 Codex / Grok 同一套「CLI 自己把数据交出来」的架构。
///
/// 为什么需要它：statusline 桥只在**终端** Claude Code 里产生数据（桌面 App 不渲染 TUI 状态栏），
/// 而 `api/oauth/usage` 被官方判为 not planned 且限流极猛。对只用桌面 App 的人，这个文件是
/// 唯一的本地权威源。
///
/// 字段是缩写（`u.fh` / `u.sd` / `u.xu`），值为**已用百分比** 0–100；**没有** `resets_at`，
/// 所以由此源得到的窗口不带重置倒计时——按项目原则，不臆造时间。
enum ClaudeDesktopUsage {

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    /// 缩写 → 窗口标签。只映射语义明确的键；未知缩写一律忽略——
    /// 显示一个叫「cw」的窗口对用户毫无意义，而且我们无法确认它的口径。
    private static let labels: [(key: String, label: String)] = [
        ("fh", "5h"),            // five_hour：5 小时滚动窗口
        ("sd", "weekly"),        // seven_day：7 天总用量
        ("so", "weekly_opus"),   // seven_day_opus：Opus 周额度（Max 档才有）
        ("xu", "extra_usage"),   // extra_usage：额外额度
    ]

    /// 读最近一次采样。返回 nil = 文件不存在 / 没有样本 / 样本里没有可识别的窗口。
    /// `asOf` 取样本自身的时间戳（不是文件修改时间——文件可能因其它写入被 touch）。
    static func read() -> (windows: [UsageWindow], asOf: Date)? {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parseLatest(obj)
    }

    /// 从整份 history 里取最后一个样本并转成窗口。internal 供测试。
    static func parseLatest(_ obj: Any) -> (windows: [UsageWindow], asOf: Date)? {
        guard let root = obj as? [String: Any],
              let samples = root["samples"] as? [[String: Any]] else { return nil }
        // 一般已按时间递增，但不依赖这个假设——按 t 取最大的那条
        guard let latest = samples.compactMap({ s -> ([String: Any], Double)? in
            guard let t = JSON.double(s["t"]) else { return nil }
            return (s, t)
        }).max(by: { $0.1 < $1.1 }) else { return nil }

        guard let u = latest.0["u"] as? [String: Any] else { return nil }
        var out: [UsageWindow] = []
        for (key, label) in labels {
            guard let used = JSON.double(u[key]) else { continue }
            // resetsAt 故意留空：这个源没有重置时间，不臆造
            out.append(UsageWindow(usedPercent: max(0, min(100, used)), resetsAt: nil, label: label))
        }
        guard !out.isEmpty else { return nil }
        // t 是毫秒时间戳（实测 1785…000 量级）
        return (out, Date(timeIntervalSince1970: latest.1 / 1000))
    }
}
