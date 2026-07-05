import AppKit
import SwiftUI
import Combine

/// 刘海悬停面板：鼠标移到屏幕顶部刘海区域时，在其正下方弹出紧凑玻璃卡片，移开自动收起。
/// 几何/悬停逻辑沿用；内容用 NSHostingView 承载 SwiftUI 的 NotchCardsView（随 store 自动更新）。
final class NotchController {
    private let panel: NSPanel
    private let store: UsageStore
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    init(store: UsageStore) {
        self.store = store
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: NotchCardsView(store: store))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    /// 按设置开/关刘海面板。
    func setEnabled(_ on: Bool) { on ? start() : stop() }

    /// 关闭：撤掉鼠标监听/轮询、收起面板（设置里关掉「刘海面板」时调用）。
    func stop() {
        guard started else { return }
        started = false
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        pollTimer?.invalidate(); pollTimer = nil
        cancellables.removeAll()
        panel.orderOut(nil)
        log("NotchController stopped")
    }

    func start() {
        guard !started else { return }
        started = true
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.evaluate() }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { handler($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { ev in handler(ev); return ev }
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.evaluate() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t

        // 数据实时变化时，若面板正开着，立即按新内容重新测高/定位（增删 AI 后高度跟着变）
        store.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                self.resizeAndReposition()
            }
            .store(in: &cancellables)

        log("NotchController started")
    }

    // MARK: - 悬停判定与定位

    private func topScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    }

    private func notchRect(on screen: NSScreen) -> NSRect {
        let f = screen.frame
        let menuBarH = max(24, f.maxY - screen.visibleFrame.maxY)
        var notchW: CGFloat = 200
        if #available(macOS 12.0, *),
           let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let w = f.width - l.width - r.width
            if w > 40 { notchW = w }
        }
        return NSRect(x: f.midX - notchW / 2, y: f.maxY - menuBarH - 4, width: notchW, height: menuBarH + 4)
    }

    private func evaluate() {
        guard let screen = topScreen() else { return }
        let p = NSEvent.mouseLocation
        let inNotch = notchRect(on: screen).contains(p)
        let inPanel = panel.isVisible && panel.frame.insetBy(dx: -10, dy: -10).contains(p)
        if inNotch || inPanel {
            showNow(on: screen)
        } else {
            hideNow()
        }
    }

    private func showNow(on screen: NSScreen) {
        guard !panel.isVisible else { return }
        resizeAndReposition(on: screen)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func hideNow() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func resizeAndReposition(on screen: NSScreen? = nil) {
        guard let scr = screen ?? topScreen(), let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let fit = content.fittingSize
        let w = max(280, fit.width)
        let h = max(60, fit.height)
        let menuBarH = max(24, scr.frame.maxY - scr.visibleFrame.maxY)
        let x = scr.frame.midX - w / 2
        let y = scr.frame.maxY - menuBarH - h
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }
}
