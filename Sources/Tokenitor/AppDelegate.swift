import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController!
    private var window: NSWindow!
    private let store = UsageStore()
    private lazy var notch = NotchController(store: store)
    private let alertEngine = AlertEngine()
    private var timer: Timer?
    private var tokenTick: Timer?                 // 轻量历史 tick（低频，只落盘/预热，防趋势缺口）
    private var pageObserver: AnyCancellable?     // 进入 Token 页时立即刷新一次
    private var isFetching = false
    private var pendingRefresh = false

    // 数据源由模块化注册表生成（增删 AI 只改 AIKind）
    private let providers: [UsageProvider] = AIKind.allCases.map { $0.makeProvider() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        log("applicationWillFinishLaunching")
        // 单实例保护：已有同 bundle 的实例在跑就退出本次，避免重复通知
        if let bid = Bundle.main.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            if running.count > 1 {
                log("已有实例在运行，退出本次启动")
                exit(0)
            }
        }
        NSApp.setActivationPolicy(.regular) // 普通应用：Dock 显示图标 + 窗口
        setupMainMenu()
        setupStatusController() // 同时保留菜单栏图标
    }

    /// 普通应用需要主菜单，否则 Cmd+Q / Cmd+H 等不工作。
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let name = "Tokenitor"
        appMenu.addItem(withTitle: "关于 \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "使用说明", action: #selector(showHelp), keyEquivalent: "?").target = self
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "刷新", action: #selector(menuRefresh), keyEquivalent: "r").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func menuRefresh() { refresh() }

    /// 一键重登 Claude：在 Terminal 里运行打包的脚本，完成订阅 /login 并清掉失效缓存。
    @objc private func reloginClaude() {
        guard let url = Bundle.main.url(forResource: "relogin-claude", withExtension: "sh") else {
            log("relogin-claude.sh 未找到")
            return
        }
        let path = url.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"bash '\(path)'\"\nend tell"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }

    // 设置改为「主窗口内切换」：不再单独开窗口
    @objc private func showSettings() {
        store.page = .settings
        showWindow()
    }

    private var helpWindow: NSWindow?
    @objc private func showHelp() {
        if helpWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Tokenitor · 使用说明"
            w.contentViewController = HelpViewController()
            w.center()
            w.isReleasedWhenClosed = false
            helpWindow = w
        }
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("applicationDidFinishLaunching")
        Disclaimer.presentIfNeeded()   // 首次启动：免责声明（不同意则退出）
        // SwiftUI 展示层的动作回调
        store.onRefresh = { [weak self] in self?.refresh() }
        store.onShowHelp = { [weak self] in self?.showHelp() }
        store.onShowSettings = { [weak self] in self?.showSettings() }
        store.onTestNotify = { Notifier.shared.test() }
        store.onSettingsChanged = { [weak self] in self?.settingsChanged() }
        store.onReloginClaude = { [weak self] in self?.reloginClaude() }
        store.onLoginCopilot = { [weak self] in self?.loginCopilot() }
        store.onMainHeight = { [weak self] h in self?.fitMainWindow(contentHeight: h) }   // 自动贴合（用户拖动后失效）
        store.onOpenWindow = { [weak self] page in                                        // 弹窗速览 → 打开完整窗口跳到该页
            guard let self else { return }
            self.statusController?.closePopover()
            self.store.page = page
            self.showWindow()
        }
        LanguageManager.apply()  // 启动应用语言设置（AppleLanguages 覆盖，下次启动生效）
        AppearanceMode.apply()   // 启动应用外观设置（跟随系统 / 浅色 / 深色）

        setupStatusController()
        // 启动只待在菜单栏：主窗口不在启动时自动创建/弹出，改为点 Dock 图标（applicationShouldHandleReopen）
        // 或菜单「设置…」时按需打开。这样菜单栏弹层完全独立，开机自启也不会弹窗、不抢焦点。
        if Settings.shared.notchEnabled { notch.start() }
        Notifier.shared.requestAuthorization()
        restartTimer()
        refresh()

        // Token 聚合按需化：启动先落盘一次历史 + 预热；之后仅在查看 Token 页时随主刷新更新 UI（见 refresh），
        // 另有低频 tick 始终落盘历史（见 startTokenTick），避免"没打开 Token 页的日子"趋势缺点。
        refreshTokens()
        pageObserver = store.$page.sink { [weak self] page in
            if page == .tokens { self?.refreshTokens() }   // 进入 Token 页立即刷新一次
        }
        startTokenTick()
    }

    private func setupWindow() {
        guard window == nil else { return }

        // 主窗口 = 标准 macOS 窗口，托管原生 NavigationStack（DashboardView）。
        // 标题、返回按钮、工具栏按钮（Token/设置/刷新/说明）全部由 NavigationStack 的 .toolbar 提供；
        // 窗口按内容自适应大小（sizingOptions = .preferredContentSize）。
        let hc = NSHostingController(rootView: DashboardView(store: store))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),   // 边栏 + 详情，系统设置量级
            styleMask: [.titled, .closable, .miniaturizable, .resizable],   // 可缩放
            backing: .buffered, defer: false)
        window.title = "Tokenitor"
        window.isOpaque = false                         // 半透明：配合 SwiftUI 里的玻璃材质
        window.backgroundColor = .clear
        window.contentViewController = hc
        window.contentMinSize = NSSize(width: 520, height: 400)
        window.delegate = self                          // 关窗时把页面重置回用量页（windowWillClose）
        window.setFrameAutosaveName("TokenitorSplitWindow")           // 记住尺寸/位置（换名，避免沿用旧窄窗尺寸）
        if !window.setFrameUsingName("TokenitorSplitWindow") { window.center() }
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        log("window created")
    }

    // 点 Dock 图标重新显示窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        setupWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Copilot GitHub OAuth Device Flow 授权：弹码 + 开浏览器 → 后台轮询 → 成功存钥匙串并开启 Copilot。
    private func loginCopilot() {
        CopilotAuth.shared.beginDeviceFlow(
            onCode: { userCode, verifyURL in
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    if let u = URL(string: verifyURL) { NSWorkspace.shared.open(u) }
                    let a = NSAlert()
                    a.messageText = "授权 Copilot"
                    a.informativeText = "验证码：\(userCode)（已复制到剪贴板）\n\n浏览器已打开 GitHub 授权页，粘贴验证码并点 Authorize。\n授权成功后本应用会自动完成——期间请勿退出。"
                    a.addButton(withTitle: "好")
                    a.runModal()
                }
            },
            completion: { [weak self] ok, msg in
                DispatchQueue.main.async {
                    let a = NSAlert()
                    a.messageText = ok ? "Copilot 授权成功" : "Copilot 授权失败"
                    if let msg { a.informativeText = msg }
                    a.addButton(withTitle: "好")
                    a.runModal()
                    if ok {
                        Settings.shared.copilotEnabled = true   // 授权成功即开启 Copilot
                        self?.settingsChanged()
                        self?.refresh()
                    }
                }
            })
    }

    // 关窗不退出（仍在后台 + 菜单栏运行），Cmd+Q 才退出
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusController() {
        guard statusController == nil else { return }
        log("creating StatusBarController…")
        statusController = StatusBarController(store: store)
        statusController.onRefreshNow = { [weak self] in self?.refresh() }
        statusController.onQuit = { NSApp.terminate(nil) }
        statusController.onShowHelp = { [weak self] in self?.showHelp() }
        log("StatusBarController created")
    }

    /// 自动贴合阶段：让窗口高度紧贴内容（顶边不动、不超出屏幕）。用户手动拖动过后（store.fillHeight=true）不再生效。
    private func fitMainWindow(contentHeight: CGFloat) {
        guard !store.fillHeight, let w = window, contentHeight > 1 else { return }
        let vis = (w.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // fullSizeContentView：SwiftUI 内容（含自绘 header）铺满整窗，窗口总高 = 内容高，无额外 chrome。
        let target = min(max(contentHeight, 160), vis.height - 24)
        var f = w.frame
        if abs(target - f.height) < 1 { return }
        let top = f.maxY
        f.size.height = target
        f.origin.y = top - target
        if f.origin.y < vis.minY + 12 { f.origin.y = vis.minY + 12 }
        w.setFrame(f, display: true, animate: false)
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = Settings.shared.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// 轻量历史 tick：每 10 分钟聚合一次，仅为落盘每日历史 + 预热 Token 页（与是否查看无关）。
    /// 高频 UI 刷新只在查看 Token 页时进行（见 refresh），从而不再每 60s 都在后台大块解析。
    private func startTokenTick() {
        tokenTick?.invalidate()
        tokenTick = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.refreshTokens()
        }
    }

    /// 设置变更（勾选/取消某个 AI、改阈值或间隔）的统一入口：
    /// 1) 立即把已关闭的 AI 从当前快照剔除 —— 刘海面板与主窗口共享同一个 store，瞬时同步隐藏；
    /// 2) 重启定时器（间隔可能变了）；
    /// 3) 立刻发起一次刷新，去拉取新开启的 AI / 更新数据。
    private func settingsChanged() {
        let visible = store.snapshots.filter { snap in
            AIKind.from(name: snap.name).map { Settings.shared.isEnabled($0) } ?? true
        }
        if visible.count != store.snapshots.count {
            store.setSnapshots(visible)        // 不改“更新于”时间，仅瞬时增删
            statusController.render(visible)
        }
        restartTimer()
        notch.setEnabled(Settings.shared.notchEnabled)   // 刘海面板开关即时生效
        refresh()
    }

    private let tokenQueue = DispatchQueue(label: "tokenitor.tokens")  // 串行：聚合 + 历史落盘不并发

    /// 后台聚合本地 token 用量（Codex/Claude/OpenCode），落盘每日历史，补齐 Week/Month 周期汇总
    /// 与 Day 周期的环比涨跌，更新 Token 页。
    private func refreshTokens() {
        tokenQueue.async {
            autoreleasepool {   // 及时归还本轮 JSON 解析的大量临时对象，降低堆峰值与碎片
                var stats = TokenAggregator.aggregate()
                TokenHistory.shared.record(stats)
                for i in stats.indices {
                    let tool = stats[i].tool
                    stats[i].week = TokenHistory.shared.report(tool: tool, days: 7)
                    stats[i].month = TokenHistory.shared.report(tool: tool, days: 30)
                    // Day 的柱状图/明细已由 TokenAggregator 用今天的实时数据填好，这里只补涨跌（跟昨天比）。
                    let dayVsYesterday = TokenHistory.shared.report(tool: tool, days: 1)
                    stats[i].day.deltaTokens = dayVsYesterday.deltaTokens
                    stats[i].day.deltaCost = dayVsYesterday.deltaCost
                }
                DispatchQueue.main.async { self.store.updateTokens(stats) }
            }
        }
    }

    private func refresh() {
        if store.page == .tokens { refreshTokens() }   // 仅在查看 Token 页时随主刷新更新 token UI（其余靠低频 tick）
        // 正在抓取时不并发；记一个挂起标记，本轮结束后自动再抓一次（确保新开启的 AI 立即出现）
        if isFetching { pendingRefresh = true; return }
        isFetching = true
        pendingRefresh = false

        let active = providers.filter { $0.enabled }
        if active.isEmpty {
            DispatchQueue.main.async {
                self.statusController.render([])
                self.store.update([])
                self.finishFetch()
            }
            return
        }

        let group = DispatchGroup()
        var results: [String: ProviderSnapshot] = [:]
        let lock = NSLock()

        for p in active {
            group.enter()
            p.fetch { snap in
                lock.lock(); results[p.displayName] = snap; lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // 按 providers 原始顺序排列；只显示“正在使用”的 AI，未读取到的(hidden)过滤掉
            let ordered = active.compactMap { results[$0.displayName] }.filter { !$0.hidden }
            self.statusController.render(ordered)
            self.store.update(ordered)
            self.alertEngine.evaluate(ordered)
            self.finishFetch()
        }
    }

    /// 收尾：解除抓取锁；若期间有挂起的刷新请求，立刻再抓一次。
    private func finishFetch() {
        isFetching = false
        if pendingRefresh {
            pendingRefresh = false
            refresh()
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    /// 用户开始手动拖动窗口边缘：切到「填充窗口宽 + 顶对齐」并停止自动贴合，尺寸完全交给用户。
    func windowWillStartLiveResize(_ notification: Notification) {
        if !store.fillHeight { store.fillHeight = true }
    }

    /// 关窗后把页面重置回用量页：避免主窗口关着却仍停在 Token 页、让后台按 Token 页高频聚合。
    func windowWillClose(_ notification: Notification) {
        if store.page != .usage { store.page = .usage }
    }
}
