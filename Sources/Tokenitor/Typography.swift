import SwiftUI

/// 全 app 统一字体阶梯（唯一来源）。
/// 原则：文字一律 **SF Pro**、数字一律 **SF Mono（等宽）**；固定字号（紧凑仪表盘，不随动态字体缩放）。
/// 想全局调字体/字号，只改这里即可。完整说明与"旧→新"映射见仓库根目录 `TYPOGRAPHY.md`。
///
/// 注：SF Symbol 图标的 `.font(.system(size:))` 属"图标尺寸"、不是排版字体，故不纳入此阶梯。
extension Font {

    // MARK: 文字（SF Pro）

    /// 页面标题：Token usage / 设置 / Tokenitor
    static let pageTitle    = Font.system(size: 17, weight: .semibold)
    /// 工具名（Codex）、卡片/分区标题
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    /// 全大写小标签：TOTAL TOKENS / TOKENS BY MODEL 等
    static let uiLabel      = Font.system(size: 10, weight: .semibold)
    /// 正文 / 说明（说明页、免责、Help 正文）
    static let uiBody       = Font.system(size: 13, weight: .regular)
    /// 次要说明 / 更新时间 / 副标题
    static let uiCaption    = Font.system(size: 11, weight: .regular)
    /// 极小注解 / 坐标轴文字标签
    static let uiMicro      = Font.system(size: 9,  weight: .medium)

    // MARK: 数字（SF Mono，等宽）

    /// 大数字：TOTAL TOKENS 124.31M
    static let numHero  = Font.system(size: 26, weight: .semibold, design: .monospaced)
    /// 成本 / 关键值：$89.96、449
    static let numTitle = Font.system(size: 16, weight: .semibold, design: .monospaced)
    /// 常规数据 / 百分比 / 模型数值 / 剩余%
    static let num      = Font.system(size: 11, weight: .medium,   design: .monospaced)
    /// 图表轴数字 / 极小数值
    static let numMicro = Font.system(size: 9,  weight: .medium,   design: .monospaced)
}
