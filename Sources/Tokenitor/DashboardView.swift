import SwiftUI
import AppKit

/// 主窗口：Apple 原生 `NavigationSplitView`（同 macOS 系统设置）——左边栏列表 + 右侧详情。
/// 工具栏只留系统的边栏折叠/前进后退；刷新在「用量」详情页内。
struct DashboardView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        NavigationSplitView {
            sidebarList
            .navigationSplitViewColumnWidth(min: 156, ideal: 172, max: 200)
            .navigationTitle("Tokenitor")
        } detail: {
            detail
                // 工具栏（标题栏）用**玻璃材质**而非不透明底：既遮挡滚动到底下的内容
                //（修复卡片盖住标题/按钮的错乱），又保留动态玻璃的通透感。
                .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbar {
                    // 刷新的标准归宿：窗口工具栏右上角（Mail/App Store 同款）；
                    // 进行中显示原生小菊花——用户第一次能「看到」正在刷新。
                    ToolbarItem(placement: .primaryAction) {
                        Button { store.onRefresh() } label: {
                            if store.isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .help(L("刷新（⌘R）", "Refresh (⌘R)"))
                        .disabled(store.isRefreshing)
                    }
                }
                .background(VisualEffectView(material: .popover, blending: .behindWindow).ignoresSafeArea())
        }
    }

    /// 边栏列表；固定两栏布局不需要「折叠边栏」按钮，macOS 14+ 直接移除。
    @ViewBuilder
    private var sidebarList: some View {
        if #available(macOS 14.0, *) {
            sidebarContent.toolbar(removing: .sidebarToggle)
        } else {
            sidebarContent
        }
    }

    /// 边栏选中项：普通页面，或 Token 下的某个工具子项。
    enum SidebarSel: Hashable {
        case page(AppPage)
        case tool(String)
    }

    private var sidebarContent: some View {
        List(selection: sidebarSelection) {
                // 分组式导航（概览 / 通用 / 其他）+ 单色 SF Symbols 图标：
                // 遵循 macOS 侧边栏惯例（Finder/Mail 风格，图标随系统强调色/选中态自动着色）。
                Section(L("概览", "Overview")) {
                    sidebarItem(L("仪表", "Dashboard"), "gauge.medium", .usage)
                    sidebarItem("Token", "chart.bar.xaxis", .tokens)
                    // Token 的工具切换收进边栏（Finder 源列表式子项），不再占详情页顶部
                    ForEach(store.tokenStats) { stat in
                        Label {
                            Text(stat.tool)
                        } icon: {
                            Image(systemName: "circlebadge.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 14)
                        .tag(SidebarSel.tool(stat.tool))
                    }
                }
                Section(L("通用", "General")) {
                    sidebarItem(L("语言", "Language"), "globe", .language)
                    sidebarItem(L("外观", "Appearance"), "circle.lefthalf.filled", .appearance)
                    sidebarItem(L("设置", "Settings"), "gearshape", .settings)
                }
                Section(L("其他", "Other")) {
                    sidebarItem(L("关于", "About"), "info.circle", .about)
                    sidebarItem(L("说明", "Guide"), "questionmark.circle", .help)
                }
        }
    }

    /// 边栏选中项 ↔ store.page / store.tokenTool 映射。
    private var sidebarSelection: Binding<SidebarSel?> {
        Binding(
            get: {
                switch store.page {
                case .usage:              return .page(.usage)
                case .tokens, .tokenInfo:
                    if let t = store.tokenTool { return .tool(t) }
                    return .page(.tokens)
                case .language:           return .page(.language)
                case .appearance:         return .page(.appearance)
                case .settings:           return .page(.settings)
                case .about:              return .page(.about)
                case .help:               return .page(.help)
                }
            },
            set: { sel in
                switch sel {
                case .page(let p):
                    store.page = p
                    if p == .tokens { store.tokenTool = nil }   // 点「Token」本身 → 默认第一个工具
                case .tool(let t):
                    store.tokenTool = t
                    store.page = .tokens
                case nil:
                    store.page = .usage
                }
            })
    }

    /// 边栏行：单色 SF Symbol + 名称（着色交给系统：强调色 / 选中态自动适配）。
    private func sidebarItem(_ title: String, _ icon: String, _ page: AppPage) -> some View {
        Label(title, systemImage: icon)
            .tag(SidebarSel.page(page))
    }

    @ViewBuilder
    private var detail: some View {
        switch store.page {
        case .usage:
            usageDetail
        case .tokens, .tokenInfo:
            tokenDetail
        case .language:
            LanguageDetail(store: store).navigationTitle(L("语言", "Language"))
        case .appearance:
            AppearanceDetail().navigationTitle(L("外观", "Appearance"))
        case .settings:
            SettingsView(store: store, inPopover: false).navigationTitle(L("设置", "Settings"))
        case .about:
            AboutDetail(store: store).navigationTitle(L("关于", "About"))
        case .help:
            HelpView().navigationTitle(L("说明", "Guide"))
        }
    }

    // MARK: - 用量详情（刷新按钮在页内）

    private var usageDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.snapshots.isEmpty {
                    Text(L("正在获取用量…", "Fetching usage…")).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(store.snapshots, id: \.name) { snap in
                        AIMonitorPanel(snap: snap,
                                       warnAt: Settings.shared.warnAt,
                                       critAt: Settings.shared.critAt,
                                       updatedAt: store.lastUpdate,
                                       hero: true,   // 主窗口用 hero 卡：胶囊行 + 统计瓦片 + 用量条
                                       serviceStatus: store.serviceStatus[snap.name])
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(L("用量", "Usage"))
    }

    // MARK: - Token 详情（「说明」折叠在底部）

    // 原来 Token 页底部的「说明」折叠（成本口径 / Claude 无本地数据）已并入侧边栏「说明」页
    // 的「Token 用量页」卡片（见 Help.swift），此处不再重复。
    private var tokenDetail: some View {
        ScrollView {
            TokenView(store: store, inPopover: false)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(L("Token 用量", "Token Usage"))
    }

}

/// 「关于」详情：作者社交图标（不展示裸链接）/ 数据文件夹 / 版本更新简要 / 版本号。
struct AboutDetail: View {
    @ObservedObject var store: UsageStore

    /// 版本更新简要（一版一行，只展示最近三条；完整日志见 GitHub README）。
    private static let releaseNotes: [(version: String, note: String)] = [
        ("1.4.3", L("服务状态改组件级：无关组件不再误报「服务降级」· Codex 档位读本地 plan_type", "Component-level status (no more false degraded) · Codex plan from local plan_type")),
        ("1.4.2", L("标准菜单四件套（视图⌘1⌘2/窗口⌘M⌘W/帮助）· 工具栏刷新带进行中状态", "Standard menus (View/Window/Help) · toolbar refresh with spinner")),
        ("1.4.1", L("三端胶囊统一（弹层/刘海同仪表）· 弹层功能区原生菜单化", "Unified chips across all surfaces · native-menu popover actions")),
        ("1.4.0", L("Token 页重构：成本优先 KPI · 分组趋势图 · 模型合并表 · 订阅档位胶囊", "Token page redesign: cost-first KPIs · grouped trend · merged model table · plan chips")),
        ("1.3.1", L("Token 聚合增量解析：消除周期性内存峰值与 CPU 尖刺", "Incremental token parsing: no more periodic memory/CPU spikes")),
        ("1.3.0", L("英文界面（全量文案，默认跟随系统语言）", "Full English localization (follows system language by default)")),
        ("1.2.2", L("渐进渲染（先到先显示）· 设置页重组 · 官方社交图形标", "Progressive rendering · Settings regroup · Official social marks")),
        ("1.2.1", L("外观预览缩略图 · 悬停反馈 · Token 工具入边栏 · 说明页降噪", "Appearance previews · Hover feedback · Token tools in sidebar")),
        ("1.2.0", L("服务状态监控 · 套餐胶囊 · 中文倒计时 · Homebrew 分发", "Service status monitor · Plan chip · Homebrew")),
        ("1.1.0", L("仪表重设计：分组侧边栏 + hero 卡片", "Dashboard redesign: grouped sidebar + hero cards")),
        ("1.0.1", L("安全与稳定性修复（凭证只读、刷新看门狗等）", "Security & stability fixes")),
        ("1.0.0", L("首个正式版", "First release")),
    ]

    var body: some View {
        Form {
            Section(L("更新简要", "What\u{2019}s New")) {
                ForEach(Self.releaseNotes.prefix(3), id: \.version) { item in
                    LabeledContent(item.version) {
                        Text(item.note).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent(L("版本", "Version"), value: "Tokenitor v\(appVersion)")
                // 社交入口：版本下方、右下角。官方图形标（GitHub Mark / X logo / 纸飞机），
                // 指示性使用（链接到本项目/作者页面），单色随主题着色。
                HStack(spacing: 12) {
                    Spacer()
                    socialButton(help: L("GitHub · 项目主页", "GitHub · Project"),
                                 url: "https://github.com/CSzcm8788/Tokenitor") {
                        BrandIcon.github.fill(style: FillStyle(eoFill: true))
                            .frame(width: 16, height: 16)
                    }
                    socialButton(help: L("X · 作者主页", "X · Author"),
                                 url: "https://x.com/yukabiubiu") {
                        BrandIcon.x.fill(style: FillStyle(eoFill: true))
                            .frame(width: 14, height: 14)
                    }
                    socialButton(help: L("Telegram · 联系作者", "Telegram · Contact"),
                                 url: "https://t.me/yukabiubiu") {
                        Image(systemName: "paperplane")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// 圆形社交图标按钮（悬停放大 + 手型光标）。
    private func socialButton<Icon: View>(help: String, url: String,
                                          @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            icon()
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pressableHover(scale: 1.08)
        .help(help)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

/// 「语言」详情：界面语言选择。English 本地化逐步完善中（切换后需重启生效）。
struct LanguageDetail: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { Settings.shared.language },
                    set: { Settings.shared.language = $0; LanguageManager.apply() })) {
                    Text(L("跟随系统", "System")).tag("system")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                } label: { Label(L("界面语言", "Interface Language"), systemImage: "globe") }
                .pickerStyle(.menu)
            } footer: {
                Text(L("切换语言需重启应用生效。", "Relaunch the app to apply the language change."))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// 「外观」详情：浅色 / 深色 / 跟随系统 —— 可点选的窗口缩略图预览（同「系统设置 → 外观」）。
struct AppearanceDetail: View {
    @State private var selection = Settings.shared.appearance

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 22) {
                    thumb(L("浅色", "Light"), key: "light")
                    thumb(L("深色", "Dark"), key: "dark")
                    thumb(L("跟随系统", "Auto"), key: "system")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            } footer: {
                Text(L("「跟随系统」随 macOS 的日夜外观自动切换。", "\u{201C}Auto\u{201D} follows the macOS system appearance."))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// 一个可点选的外观缩略图：迷你窗口预览 + 选中描边 + 名称。
    private func thumb(_ title: String, key: String) -> some View {
        let selected = selection == key
        return VStack(spacing: 7) {
            preview(for: key)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(selected ? Color.accentColor : Color.primary.opacity(0.15),
                                lineWidth: selected ? 2.5 : 0.5)
                )
            Text(title)
                .font(.uiCaption)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .fontWeight(selected ? .semibold : .regular)
        }
        .contentShape(Rectangle())
        .pressableHover(scale: 1.03)
        .onTapGesture {
            selection = key
            Settings.shared.appearance = key
            AppearanceMode.apply()
        }
    }

    @ViewBuilder
    private func preview(for key: String) -> some View {
        switch key {
        case "light": miniWindow(dark: false)
        case "dark":  miniWindow(dark: true)
        default:      // 跟随系统：左浅右深各一半
            ZStack {
                miniWindow(dark: false)
                miniWindow(dark: true)
                    .mask(HStack(spacing: 0) { Color.clear; Color.black })
            }
        }
    }

    /// 迷你窗口 mockup：红黄绿三点 + 两根内容条。
    private func miniWindow(dark: Bool) -> some View {
        let bar = dark ? Color(white: 0.42) : Color(white: 0.78)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3.5) {
                Circle().fill(Color(red: 1.00, green: 0.38, blue: 0.35)).frame(width: 6, height: 6)
                Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.20)).frame(width: 6, height: 6)
                Circle().fill(Color(red: 0.22, green: 0.80, blue: 0.35)).frame(width: 6, height: 6)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 2).fill(bar).frame(height: 7)
            RoundedRectangle(cornerRadius: 2).fill(bar.opacity(0.6)).frame(height: 7)
                .padding(.trailing, 22)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 104, height: 68)
        .background(dark ? Color(white: 0.15) : .white)
    }
}

/// 菜单栏弹窗 = 用量速览：按内容自适应高度，点 Token/设置 打开完整主窗口，刷新在原地。
struct PopoverGlanceView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Tokenitor").font(.headline)
                if let t = store.lastUpdate {
                    Text(L("更新于 ", "Updated ") + formatUpdatedAgo(t))   // 面板级统一显示，卡片下不再挂小字
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if store.snapshots.isEmpty {
                Text(L("正在获取用量…", "Fetching usage…")).font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(store.snapshots, id: \.name) { snap in
                    AIMonitorPanel(snap: snap, warnAt: Settings.shared.warnAt, critAt: Settings.shared.critAt,
                                   serviceStatus: store.serviceStatus[snap.name])
                }
            }

            // 功能区：原生菜单样式（文字行 + 右侧快捷键 + 分隔线 + 悬停高亮），替代此前的图标按钮
            VStack(alignment: .leading, spacing: 1) {
                Divider().opacity(0.4).padding(.vertical, 3)
                MenuRow(title: L("Token 用量", "Token Usage")) { store.onOpenWindow(.tokens) }
                MenuRow(title: L("设置…", "Settings…"), shortcut: "⌘,") { store.onOpenWindow(.settings) }
                MenuRow(title: L("刷新", "Refresh"), shortcut: "⌘R") { store.onRefresh() }
                Divider().opacity(0.4).padding(.vertical, 3)
                MenuRow(title: L("使用说明", "Guide")) { store.onShowHelp() }
                MenuRow(title: L("退出 Tokenitor", "Quit Tokenitor"), shortcut: "⌘Q") { store.onQuit() }
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(VisualEffectView(material: .popover, blending: .behindWindow).ignoresSafeArea())
    }
}

/// 原生菜单样式的行（同 macOS 应用菜单：悬停整行强调色高亮、白字，右侧快捷键提示）。
private struct MenuRow: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.uiBody)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.uiCaption)
                        .foregroundStyle(hovering ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Color.accentColor : .clear))
            .foregroundStyle(hovering ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
