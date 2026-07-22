import AppKit

/// 免责声明：首次启动弹一次，需用户同意；不同意则退出。文本随界面语言（L10n）。
enum Disclaimer {
    static var text: String {
        L("""
    Tokenitor（以下简称"本应用"）是由独立开发者开发的 macOS 工具，与以下任何公司均无关联、合作、赞助或官方关系：

    • Anthropic Inc. 及其产品 Claude
    • OpenAI 及其产品 Codex / ChatGPT
    • Google LLC 及其产品 Gemini
    • GitHub, Inc. / Microsoft Corporation 及其产品 GitHub Copilot
    • xAI Corp. 及其产品 Grok

    本应用不内置、不展示任何 AI 服务商的 Logo 图片，仅以各服务的名称作指示性标识以区分第三方 AI 服务；相关名称/商标的知识产权归各公司所有。

    数据来源说明：
    本应用只读取本机上属于你自己的数据与登录凭证，只读不改、不上传。其中 Codex / Gemini 为纯本地文件读取；Claude / Copilot 两项经由社区通用接口（官方未文档化）以你本人的凭证读取你本人的用量——它们默认关闭，开启前会单独提示相应风险。此类接口可能不符合对应服务的条款、且随时可能变更或失效。用量数据的准确性取决于原始服务返回的信息及本地记录。

    本应用不代表上述任何公司的官方立场、观点或产品推荐。使用本应用产生的任何后果由用户自行承担。

    开发者不对用量数据的实时性、准确性或完整性作出任何明示或暗示的保证。

    继续使用本应用即表示您已充分阅读、理解并同意以上所有条款。
    """, """
    Tokenitor ("this app") is a macOS tool by an independent developer, with no affiliation, partnership, sponsorship, or official relationship with any of the following companies:

    • Anthropic Inc. and its product Claude
    • OpenAI and its products Codex / ChatGPT
    • Google LLC and its product Gemini
    • GitHub, Inc. / Microsoft Corporation and their product GitHub Copilot
    • xAI Corp. and its product Grok

    This app does not bundle or display any AI vendor's logo; services are identified by name only, as nominative references. All names and trademarks belong to their respective owners.

    Data sources:
    This app reads only your own local data and credentials, read-only, and uploads nothing. Codex / Gemini are read purely from local files; Claude / Copilot are read through community APIs (not officially documented) using your own credentials to fetch your own usage — both are off by default and prompt you with their specific risks before being enabled. Such endpoints may conflict with the respective service terms and may change or break at any time. Accuracy depends on what the original services return and on local records.

    This app does not represent any official position, view, or endorsement of the companies above. You use this app at your own risk.

    The developer makes no express or implied warranty as to the timeliness, accuracy, or completeness of usage data.

    By continuing to use this app you confirm you have read, understood, and agreed to all the terms above.
    """)
    }

    /// 若尚未同意，弹出模态声明；同意则记录，拒绝则退出 App。
    static func presentIfNeeded() {
        guard !Settings.shared.disclaimerAccepted else { return }

        let alert = NSAlert()
        alert.messageText = L("Tokenitor · 重要声明与免责条款", "Tokenitor · Notice & Disclaimer")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("同意并继续", "Agree & Continue"))
        alert.addButton(withTitle: L("退出", "Quit"))

        // 可滚动的正文
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.font = .systemFont(ofSize: 12)
        tv.string = text
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = tv
        alert.accessoryView = scroll

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Settings.shared.disclaimerAccepted = true
        } else {
            NSApp.terminate(nil)
        }
    }
}
