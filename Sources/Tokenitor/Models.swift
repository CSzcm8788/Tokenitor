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
    /// 可选说明文字（仅用于日志/调试；卡片不再渲染小字，保持风格统一）
    var note: String? = nil
    /// 套餐名（如 Copilot 的 "Individual"），hero 卡片显示为胶囊
    var plan: String? = nil
    /// 是否在 UI 中隐藏（未安装/未登录/未使用 → 界面不显示这一栏）
    var hidden: Bool = false
    /// 是否为过期缓存数据（限流/断网时展示上次成功结果）。UI 照常显示，但告警引擎跳过，
    /// 避免基于几小时前的旧数据推送「即将耗尽」通知。
    var isStale: Bool = false
    /// 数据自身的时间点（如 Codex rate_limits 事件的时间戳）。与「更新于」（读取时间）区分：
    /// 滞后明显时卡片显示「数据 X分钟前」胶囊，不让刚刷新的读取时间制造假新鲜感。
    var dataAsOf: Date? = nil
    /// 限额重置额度剩余次数（Codex rate_limits.credits.balance）。到期明细本地无、不显示；
    /// 余额为 0 或读不到时为 nil（胶囊隐藏）。unlimited 时显示 ∞。
    var resetCredits: Int? = nil
    var resetCreditsUnlimited: Bool = false

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
    /// 清掉数据源自身的退避/冷却（手动刷新时调用）。默认无操作。
    func resetBackoff()
}

extension UsageProvider {
    func resetBackoff() {}
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

/// 「更新于」相对时间：刚刚 / N分钟前（en: just now / 5m ago）；超过一天显示日期。
/// english 参数默认取界面语言，测试可显式传入两种语言分别断言。
func formatUpdatedAgo(_ date: Date, now: Date = Date(),
                      english: Bool = L10n.isEnglish) -> String {
    let secs = Int(now.timeIntervalSince(date))
    if secs < 60 { return english ? "just now" : "刚刚" }
    if secs < 3600 { return english ? "\(secs / 60)m ago" : "\(secs / 60)分钟前" }
    if secs < 86400 { return english ? "\(secs / 3600)h ago" : "\(secs / 3600)小时前" }
    let df = DateFormatter()
    if english { df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MMM d HH:mm" }
    else { df.dateFormat = "M月d日 HH:mm" }
    return df.string(from: date)
}

/// 重置倒计时："2小时30分" / "6天23小时" / "8月1日"（en: "2h 30m" / "6d 23h" / "Aug 1"）。
func formatCountdown(to date: Date?, now: Date = Date(),
                     english: Bool = L10n.isEnglish) -> String {
    guard let date = date else { return "" }
    let secs = Int(date.timeIntervalSince(now))
    if secs <= 0 { return english ? "now" : "现在" }
    if secs >= 9 * 86400 {          // 远期（如月度重置）显示日期
        let df = DateFormatter()
        if english { df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MMM d" }
        else { df.dateFormat = "M月d日" }
        return df.string(from: date)
    }
    let d = secs / 86400
    let h = (secs % 86400) / 3600
    let m = (secs % 3600) / 60
    if english {
        if d >= 1 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }
    if d >= 1 { return h > 0 ? "\(d)天\(h)小时" : "\(d)天" }
    if h > 0 { return m > 0 ? "\(h)小时\(m)分" : "\(h)小时" }
    return "\(m)分钟"
}
