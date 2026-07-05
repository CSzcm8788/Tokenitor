import AppKit
import SwiftUI

/// 菜单栏图标 + SwiftUI 弹层(popover)。
/// 左键：弹出和主窗口同款的 SwiftUI 面板(用量卡片 + ⚙️ 设置，胶囊开关 / 当前值下拉)。
/// 右键：精简上下文菜单(立即刷新 / 使用说明 / 退出)。
/// 标题：app 图标 + 「剩余%」(取最紧张的窗口，用档位色，不再用代码/emoji)。
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: UsageStore
    private let popover = NSPopover()
    private var snapshots: [ProviderSnapshot] = []

    /// 由 AppDelegate 注入的回调
    var onRefreshNow: (() -> Void)?
    var onQuit: (() -> Void)?
    var onShowHelp: (() -> Void)?

    init(store: UsageStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.isVisible = true

        // 弹层内容：用量速览（PopoverGlanceView，按内容自适应高度）。点 Token/设置打开完整主窗口。
        let host = NSHostingController(rootView: PopoverGlanceView(store: store))
        if #available(macOS 13.0, *) {
            host.sizingOptions = [.preferredContentSize]
        } else {
            popover.contentSize = NSSize(width: 360, height: 560)
        }
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        log("status item ready (popover mode)")
    }

    /// 弹层内容是 SwiftUI、自动跟随 store；菜单栏只保留图标，不显文字。
    func render(_ snaps: [ProviderSnapshot]) {
        snapshots = snaps
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
    }

    // MARK: - 点击：左键弹层 / 右键上下文菜单

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.page = .usage   // 每次打开默认看用量页
            // 只弹弹层、只让弹层窗口拿焦点；不激活整个 app —— 避免把主窗口一起带到最前
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 关闭弹窗（速览里点 Token/设置打开主窗口时调用）。
    func closePopover() { if popover.isShown { popover.performClose(nil) } }

    private func showContextMenu() {
        let menu = NSMenu()
        let r = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r"); r.target = self
        let h = NSMenuItem(title: "使用说明", action: #selector(showHelp), keyEquivalent: ""); h.target = self
        let q = NSMenuItem(title: "退出 Tokenitor", action: #selector(quit), keyEquivalent: "q"); q.target = self
        menu.addItem(r); menu.addItem(h); menu.addItem(.separator()); menu.addItem(q)
        // 临时挂上菜单弹出，弹完即清，保证左键仍是弹层而非此菜单
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// 菜单栏图标：从最终 app 图标抠出的单色 gauge（模板图，纯白/纯黑由系统按亮暗自动适配）。
    private static func menuBarIcon() -> NSImage? {
        if let img = NSImage(named: "menubar") {
            img.isTemplate = true     // 自动适配亮/暗状态栏
            return img
        }
        let img = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Tokenitor")
        img?.isTemplate = true
        return img
    }

    // MARK: - Actions

    @objc private func refreshNow() { onRefreshNow?() }
    @objc private func quit() { onQuit?() }
    @objc private func showHelp() { onShowHelp?() }
}
