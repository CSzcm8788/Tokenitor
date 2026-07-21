import AppKit

/// 开启「走社区通用接口」的数据源前的自担风险确认。
/// Claude / Copilot 都用你本人的登录凭证访问官方未文档化的接口，可能不符合各自条款；
/// 故两者默认关闭，**首次开启各弹一次确认**（确认后记住，不再重复打扰）。
/// 纯本地读取的 Codex / Gemini 不涉及此问题，不拦截。
enum RiskGate {
    /// 该数据源是否需要风险确认（走社区接口的才需要）。
    static func requiresConfirmation(_ kind: AIKind) -> Bool {
        switch kind {
        case .claude, .copilot: return true
        case .codex, .gemini:   return false
        }
    }

    /// 已确认过或无需确认 → 直接放行；否则弹窗，用户确认才返回 true。
    @discardableResult
    static func confirmEnableIfNeeded(_ kind: AIKind) -> Bool {
        guard requiresConfirmation(kind) else { return true }
        if Settings.shared.riskAccepted(kind) { return true }

        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = messageText(kind)
        a.informativeText = informativeText(kind)
        a.addButton(withTitle: L("我已了解风险，开启", "I understand the risk — enable"))
        a.addButton(withTitle: L("取消", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            Settings.shared.setRiskAccepted(kind, true)
            return true
        }
        return false
    }

    private static func messageText(_ kind: AIKind) -> String {
        switch kind {
        case .claude:  return L("开启 Claude 用量读取？", "Enable Claude usage reading?")
        case .copilot: return L("开启 Copilot 用量读取？", "Enable Copilot usage reading?")
        default:       return ""
        }
    }

    private static func informativeText(_ kind: AIKind) -> String {
        switch kind {
        case .claude:
            return L("""
            此功能通过 Anthropic 官方未文档化的接口、使用你订阅账号的本地登录凭证来读取用量。

            请注意：按 Anthropic 条款，订阅（Free / Pro / Max）的登录凭证仅可用于 Claude Code 与 Claude.ai。在第三方工具中使用可能违反其条款，并可能导致账号受限或封禁。

            是否在了解并自行承担风险的前提下开启？
            """, """
            This feature reads usage via an Anthropic endpoint that is not officially documented, using your local subscription credentials.

            Per Anthropic's terms, subscription (Free / Pro / Max) credentials are intended for Claude Code and Claude.ai only. Third-party use may violate those terms and could lead to account restrictions.

            Enable at your own risk?
            """)
        case .copilot:
            return L("""
            此功能通过 GitHub 官方未文档化的内部接口（编辑器插件同款）、使用你本机 Copilot 登录凭证（或本应用的 device flow 授权）来读取你本人的高级额度用量。

            请注意：该接口未公开、无稳定性承诺，第三方使用可能不符合 GitHub 的服务条款，并可能导致账号受限。

            是否在了解并自行承担风险的前提下开启？
            """, """
            This feature reads your own premium-quota usage via a GitHub internal endpoint that is not officially documented (the one editor plugins use), using your local Copilot credentials (or this app's device-flow authorization).

            That endpoint is undocumented with no stability guarantees; third-party use may conflict with GitHub's terms and could lead to account restrictions.

            Enable at your own risk?
            """)
        default:
            return ""
        }
    }
}
