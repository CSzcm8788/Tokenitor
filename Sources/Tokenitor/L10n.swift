import Foundation

/// 轻量本地化：启动时按「设置 → 语言」决定中 / 英，切换后重启生效（与语言页说明一致）。
/// 不走 Localizable.strings（SPM 可执行目标的资源管线繁琐、且键名间接层影响可读性），
/// 界面文案一律就地成对写：`L("中文", "English")`——上下文零查找，翻译漏项一眼可见。
enum L10n {
    /// true = 英文界面。"system" 时跟随系统首选语言（首选非中文即英文）。
    static let isEnglish: Bool = {
        switch Settings.shared.language {
        case "en": return true
        case "zh": return false
        default:   return Locale.preferredLanguages.first?.hasPrefix("zh") != true
        }
    }()
}

/// 取当前界面语言的文案。
@inline(__always)
func L(_ zh: String, _ en: String) -> String { L10n.isEnglish ? en : zh }
