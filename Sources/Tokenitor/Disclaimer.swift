import AppKit

/// 免责声明：首次启动弹一次，需用户同意；不同意则退出。
enum Disclaimer {
    static let text = """
    Tokenitor（以下简称"本应用"）是由独立开发者开发的 macOS 工具，与以下任何公司均无关联、合作、赞助或官方关系：

    • Anthropic Inc. 及其产品 Claude
    • OpenAI 及其产品 Codex / ChatGPT
    • Google LLC 及其产品 Gemini
    • GitHub, Inc. / Microsoft Corporation 及其产品 GitHub Copilot

    本应用不内置、不展示任何第三方 Logo 图片，仅以各服务的名称作指示性标识以区分第三方 AI 服务；相关名称/商标的知识产权归各公司所有。

    数据来源说明：
    本应用仅通过用户授权的方式读取本地数据，不访问任何服务的私有接口或进行未经授权的数据抓取。用量数据的准确性取决于原始服务的公开信息及本地记录。

    本应用不代表上述任何公司的官方立场、观点或产品推荐。使用本应用产生的任何后果由用户自行承担。

    开发者不对用量数据的实时性、准确性或完整性作出任何明示或暗示的保证。

    继续使用本应用即表示您已充分阅读、理解并同意以上所有条款。
    """

    /// 若尚未同意，弹出模态声明；同意则记录，拒绝则退出 App。
    static func presentIfNeeded() {
        guard !Settings.shared.disclaimerAccepted else { return }

        let alert = NSAlert()
        alert.messageText = "Tokenitor · 重要声明与免责条款"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "同意并继续")
        alert.addButton(withTitle: "退出")

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
