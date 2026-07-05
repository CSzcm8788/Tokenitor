import AppKit

/// 开启 Claude 用量读取前的「自担风险」确认。
/// Claude 用量走 Anthropic 未公开接口、需用订阅登录凭证，按其条款仅可用于 Claude Code / Claude.ai，
/// 第三方使用可能违反条款并致账号受限。故默认关闭，开启前弹窗确认一次（确认后记住，不再重复打扰）。
enum ClaudeRiskGate {
    /// 已确认过 → 直接放行；否则弹窗，用户确认才返回 true。
    @discardableResult
    static func confirmEnableIfNeeded() -> Bool {
        if Settings.shared.claudeRiskAccepted { return true }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "开启 Claude 用量读取？"
        a.informativeText = """
        此功能通过 Anthropic 未公开的接口、使用你订阅账号的本地登录凭证来读取用量。

        请注意：按 Anthropic 条款，订阅（Free / Pro / Max）的登录凭证仅可用于 Claude Code 与 Claude.ai。在第三方工具中使用可能违反其条款，并可能导致账号受限或封禁。

        是否在了解并自行承担风险的前提下开启？
        """
        a.addButton(withTitle: "我已了解风险，开启")
        a.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        let resp = a.runModal()
        if resp == .alertFirstButtonReturn {
            Settings.shared.claudeRiskAccepted = true
            return true
        }
        return false
    }
}
