import Foundation

/// 已接入 AI 的「模块化注册表」。
/// 想增删一个 AI，只需在这里加 / 删一个 case，并在 `makeProvider()` 给出它的数据源即可，
/// 设置面板的开关、AppDelegate 的数据源列表都会自动跟着变（无需改 UI）。
enum AIKind: String, CaseIterable, Identifiable {
    case claude  = "Claude"
    case codex   = "Codex"
    case gemini  = "Gemini"
    case grok    = "Grok"
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
        case .grok:    return GrokProvider()
        case .copilot: return CopilotProvider()
        }
    }

    /// 数据源性质（仪表 hero 卡片上的胶囊标签）："本地" 纯本地文件 / "社区" 社区通用接口
    ///（官方未文档化；条款风险在说明页合规卡与开启前弹窗中完整披露）。
    var sourceTag: String {
        switch self {
        case .claude, .copilot:       return L("社区", "Community")
        case .codex, .gemini, .grok:  return L("本地", "Local")
        }
    }

    /// 该源百分比的**覆盖范围**：同样一个「剩余 %」，各家统计的东西完全不同——
    /// 不写清楚极易误读（最典型：Grok 的百分比是整个 X 账号跨产品共享池，不只是 Grok Build）。
    /// 卡片悬停与说明页共用这一份文案，避免两处口径漂移。
    var coverage: String {
        switch self {
        case .claude:
            return L("覆盖范围：**整个 Anthropic 账号**——桌面 App、网页版与 Claude Code 的消耗合并计入；5 小时窗口与周窗口（含 Sonnet / Opus 各自的窗口）。",
                     "Coverage: **your whole Anthropic account** — desktop app, web, and Claude Code usage all count toward it; 5-hour and weekly windows (with separate Sonnet / Opus windows).")
        case .codex:
            return L("覆盖范围：**整个 ChatGPT 账号**的 Codex 配额窗口（本机会话文件里记录的账号级 rate_limits，非仅本机用量）。",
                     "Coverage: the Codex quota windows of **your whole ChatGPT account** (account-level rate_limits recorded in local session files, not just this Mac).")
        case .gemini:
            return L("覆盖范围：**仅本机 CLI 今日的请求数**，除以你在设置里选的每日额度所得的**本地估算**——不含网页/其它设备，也不是官方账单。",
                     "Coverage: **this Mac\u{2019}s CLI requests today only**, divided by the daily limit you pick in Settings — a **local estimate**; excludes web/other devices and is not official billing.")
        case .grok:
            return L("覆盖范围：**整个 X 账号的跨产品周共享池**——Grok Chat、Imagine、Voice、Build 与 API 的消耗合并计入，不只是 Grok Build 一家。",
                     "Coverage: **your entire X account\u{2019}s cross-product weekly pool** — Grok Chat, Imagine, Voice, Build and API all draw from it, not just Grok Build.")
        case .copilot:
            return L("覆盖范围：**整个 GitHub 账号**的月度 premium interactions 额度（UTC 每月 1 号重置）。",
                     "Coverage: your **whole GitHub account\u{2019}s** monthly premium-interactions allowance (resets on the 1st, UTC).")
        }
    }

    /// 用快照 / displayName 反查模块。
    static func from(name: String) -> AIKind? { AIKind(rawValue: name) }
}
