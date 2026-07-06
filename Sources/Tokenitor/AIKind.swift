import Foundation

/// 已接入 AI 的「模块化注册表」。
/// 想增删一个 AI，只需在这里加 / 删一个 case，并在 `makeProvider()` 给出它的数据源即可，
/// 设置面板的开关、AppDelegate 的数据源列表都会自动跟着变（无需改 UI）。
enum AIKind: String, CaseIterable, Identifiable {
    case claude  = "Claude"
    case codex   = "Codex"
    case gemini  = "Gemini"
    case copilot = "Copilot"

    var id: String { rawValue }

    /// 设置面板上显示的名字（与 ProviderSnapshot.name / displayName 一致）。
    var title: String { rawValue }

    /// UserDefaults 持久化键，沿用历史键名：claudeEnabled / codexEnabled …
    var defaultsKey: String { rawValue.lowercased() + "Enabled" }

    /// 该 AI 的数据源实例。
    func makeProvider() -> UsageProvider {
        switch self {
        case .claude:  return ClaudeProvider()
        case .codex:   return CodexProvider()
        case .gemini:  return GeminiProvider()
        case .copilot: return CopilotProvider()
        }
    }

    /// 数据源性质（仪表 hero 卡片上的胶囊标签）："本地" 纯本地文件 / "未公开" 非官方端点。
    var sourceTag: String {
        switch self {
        case .claude, .copilot: return "未公开"
        case .codex, .gemini:   return "本地"
        }
    }

    /// 用快照 / displayName 反查模块。
    static func from(name: String) -> AIKind? { AIKind(rawValue: name) }
}
