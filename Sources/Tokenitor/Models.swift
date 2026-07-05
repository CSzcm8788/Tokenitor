import Foundation

/// 一个用量窗口（如 Claude 的 5 小时窗口、周窗口，或 Codex 的 primary/secondary）。
struct UsageWindow {
    /// 已使用百分比 0...100
    var usedPercent: Double
    /// 该窗口重置的时间点（可能为 nil）
    var resetsAt: Date?
    /// 窗口跨度的可读标签，如 "5h"、"weekly"
    var label: String

    /// 剩余百分比 0...100
    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

/// 单个工具（Claude / Codex）的一次采样快照。
struct ProviderSnapshot {
    /// 工具名，如 "Claude"、"Codex"
    var name: String
    /// 该工具下的各窗口（按显示顺序）
    var windows: [UsageWindow]
    /// 采集是否成功；失败时给出原因，UI 里显示灰色状态
    var ok: Bool
    var error: String?
    /// 可选说明文字，显示在该工具标题下方（如“账号共享用量”）
    var note: String? = nil
    /// 是否在 UI 中隐藏（未安装/未登录/未使用 → 界面不显示这一栏）
    var hidden: Bool = false

    static func failed(_ name: String, _ message: String) -> ProviderSnapshot {
        ProviderSnapshot(name: name, windows: [], ok: false, error: message)
    }

    /// 该工具未读取到（未在使用）——界面不显示。
    static func absent(_ name: String) -> ProviderSnapshot {
        ProviderSnapshot(name: name, windows: [], ok: false, error: nil, hidden: true)
    }
}

/// 提供数据的统一接口。
protocol UsageProvider {
    var displayName: String { get }
    /// 是否在设置里被启用
    var enabled: Bool { get }
    /// 异步抓取一次快照（completion 在任意线程回调）
    func fetch(completion: @escaping (ProviderSnapshot) -> Void)
}

/// 颜色档位：根据剩余百分比决定状态色。
enum UsageLevel {
    case healthy   // 剩余充足
    case warning   // 偏低
    case critical  // 极低

    /// remaining: 剩余百分比 0...100
    static func from(remaining: Double, warnAt: Double, critAt: Double) -> UsageLevel {
        if remaining <= critAt { return .critical }
        if remaining <= warnAt { return .warning }
        return .healthy
    }

    var dot: String {
        switch self {
        case .healthy:  return "🟢"
        case .warning:  return "🟡"
        case .critical: return "🔴"
        }
    }
}

/// 把重置时间格式化为 "2h30m" / "thu 13h" 之类的倒计时文案。
func formatCountdown(to date: Date?, now: Date = Date()) -> String {
    guard let date = date else { return "" }
    let secs = Int(date.timeIntervalSince(now))
    if secs <= 0 { return "now" }
    if secs >= 9 * 86400 {          // 远期（如月度重置）显示日期 M/d
        let df = DateFormatter(); df.dateFormat = "M/d"
        return df.string(from: date)
    }
    let h = secs / 3600
    let m = (secs % 3600) / 60
    if h >= 24 {
        let df = DateFormatter()
        df.dateFormat = "EEE HH'h'"
        df.locale = Locale(identifier: "en_US")
        return df.string(from: date).lowercased()
    }
    if h > 0 { return "\(h)h\(String(format: "%02d", m))m" }
    return "\(m)m"
}
