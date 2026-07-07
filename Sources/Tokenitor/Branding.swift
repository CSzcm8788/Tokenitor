import SwiftUI

/// 应用标识（版本号 / User-Agent 的全局唯一来源，避免散落各处发版时漏改）。
enum AppInfo {
    /// 打包运行时从 Info.plist 读；`swift run` 裸跑时兜底。
    static let version: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.4.0"
    /// 诚实标识自己的 User-Agent，不伪装任何官方客户端。
    static let userAgent = "Tokenitor/\(version)"
}

// 第三方品牌 logo / 图标 / 配色已彻底移除（2026-07）：AI 一律只用名称文字标识，
// 不加载任何品牌 PNG、也不用会让人联想到品牌的图标。仅保留下面的「用量三态色板」。

/// 三态状态色板：为「动态玻璃」调校过的三种颜色，主窗口与刘海面板统一使用。
/// 比系统纯 green/yellow/red 略降饱和、提亮，叠在半透明材质上更耐看、对比也够。
enum GaugeColor {
    /// 健康（剩余充足）— 薄荷绿
    static let healthy  = Color(red: 0.22, green: 0.80, blue: 0.55)
    /// 低用量（接近预警）— 琥珀金
    static let warning  = Color(red: 1.00, green: 0.72, blue: 0.22)
    /// 紧急（即将耗尽）— 珊瑚红
    static let critical = Color(red: 1.00, green: 0.39, blue: 0.36)
}

/// 用量档位对应的颜色（全局唯一来源）。
func levelColor(_ level: UsageLevel) -> Color {
    switch level {
    case .healthy:  return GaugeColor.healthy
    case .warning:  return GaugeColor.warning
    case .critical: return GaugeColor.critical
    }
}
