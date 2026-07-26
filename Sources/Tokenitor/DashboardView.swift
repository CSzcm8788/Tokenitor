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
                // 工具栏里**不放任何按钮**：刷新是自动的（计时器 + 打开窗口/弹层 + 系统唤醒），
                // 需要手动时用 ⌘R / 弹层菜单 / 菜单栏右键。孤零零一个圆钮与整体风格不搭。
                // 也不要给工具栏指定背景材质：1.3.0 曾加 `.toolbarBackground(.ultraThinMaterial)`，
                // 浅色模式下呈纯白、与内容区割裂成两截（遮挡由标题栏自身材质承担）。
                // 「动态玻璃」：behindWindow 混合把桌面模糊透进来（配合 AppDelegate 的半透明
                // 窗口）。ignoresSafeArea 让它铺到标题栏下面，与顶部连成一片、不再有白工具栏。
                .background(VisualEffectView(material: .popover, blending: .behindWindow)
                    .ignoresSafeArea())
        }
    }

    /// 边栏列表；固定两栏布局不需要「折叠边栏」按钮，macOS 14+ 直接移除。
    @ViewBuilder
    private var sidebarList: some View {
        if #available(macOS 14.0, *) {
            sidebarContent.toolbar(removing: .sidebarToggle).background(sidebarTint)
        } else {
            sidebarContent.background(sidebarTint)
        }
    }

    /// 边栏用**和详情区同一种** `.popover` 玻璃，再压一层极淡的黑做暗——「暗边栏 + 亮内容」
    /// 才是系统的方向（实测系统设置浅色：边栏 241 / 内容 247，边栏暗 6 级）。
    /// 此前两侧都只有窗口那一层玻璃，浅色实测 218 vs 217，等于看不出边栏边界。
    ///
    /// 为什么不用系统的 `.sidebar` / `.underWindowBackground` / `.windowBackground`：这三个在
    /// 浅色下都把边栏做得**更亮**（实测 226/217、224/210、255/216），方向和系统相反——根因是
    /// 我们的内容区是 `.popover` 玻璃（216），比普通窗口底色暗得多，而那层是动态玻璃的地基，
    /// 不能为了配色去动它（见 CLAUDE.md §2）。所以只能反过来压暗边栏。
    ///
    /// 0.04 这个值是量出来的：0.11 → 浅色差 18 级（过重），0.04 → 浅色 −9 / 深色 −4，
    /// 与系统的 −6 同量级且两种外观方向一致。改这个数字必须重新量，不要凭感觉调。
    private var sidebarTint: some View {
        ZStack {
            VisualEffectView(material: .popover, blending: .behindWindow)
            Color.black.opacity(0.04)
        }
        .ignoresSafeArea()
    }

    /// 边栏选中项：普通页面，或 Token 下的某个工具子项。
    enum SidebarSel: Hashable {
        case page(AppPage)
        case tool(String)
    }

    private var sidebarContent: some View {
        List(selection: sidebarSelection) {
                // 分组式导航（概览 / 通用 / 其他）+ 统一规格单色 SF Symbols：
                // 固定列宽/字号，选中态交给 List 系统着色（Finder / Mail 侧栏惯例）。
                Section(L("概览", "Overview")) {
                    sidebarItem("Overview", "gauge.medium", .usage)
                    sidebarItem("Token", "chart.bar", .tokens)
                    // Token 的工具切换收进边栏（Finder 源列表式子项），不再占详情页顶部
                    ForEach(store.tokenStats) { stat in
                        Label {
                            Text(stat.tool)
                        } icon: {
                            // 与主项同一列宽，圆点在列内居中——文字左边线与主项对齐。
                            Image(systemName: "circlebadge.fill")
                                .font(.system(size: 6))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.tertiary)
                                .frame(width: Self.sidebarIconSlot, alignment: .center)
                        }
                        .padding(.leading, 16)
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
        // List 默认自己画一层不透明底，会把下面的 sidebarTint 完全盖住（实测加了色看不出变化）；
        // 隐掉它，左右两侧的明度差才出得来。
        .scrollContentBackground(.hidden)
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

    /// 侧栏图标槽宽：各 SF Symbol 视觉宽度不等，钉死后文字左边线才齐。
    private static let sidebarIconSlot: CGFloat = 18

    /// 侧栏图标统一规格（字号 / 字重 / 列宽 / 颜色）。
    /// **必须显式给颜色**：不给的话，SwiftUI 在「浅色 + 窗口活跃」时会自动给 List 里的 Label
    /// 图标上系统强调色（实测像素 #0070F6 蓝），而深色/非活跃时又是灰的——同一份界面两种观感，
    /// 也违背全盘单色化。选中行仍由 List 的选中态整体反白，不受这里影响。
    @ViewBuilder
    private func sidebarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.secondary)
            .frame(width: Self.sidebarIconSlot, alignment: .center)
    }

    /// 边栏行：统一 SF Symbol + 名称。
    private func sidebarItem(_ title: String, _ icon: String, _ page: AppPage) -> some View {
        Label {
            Text(title)
        } icon: {
            sidebarIcon(icon)
        }
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
                    EmptyStateView(hasFetched: store.hasFetched) { store.page = .settings }
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
        ("1.5.6", L("Claude 桌面 App 也走本地：读桌面自写的用量历史 · 来源胶囊按实际路径 · 边栏与详情区分层 · 更正 1.5.5 的错误说法", "Claude desktop app now local too: reads the history it writes itself · source chip reflects the real path · sidebar/detail separation · corrects a false claim in 1.5.5")),
        ("1.5.5", L("Claude 改本地读取（零联网、不再撞限流）· 四级降级链", "Claude now reads locally (no network, no rate limits) · four-tier fallback")),
        ("1.5.4", L("卡片头两行化 · 浅色模式全窗统一 · 设置页 4 字对齐 · 刷新全自动（移除手动按钮）· 应用内检查更新", "Two-row card header · unified light mode · 4-char settings labels · fully automatic refresh · in-app update check")),
        ("1.5.3", L("Grok 接入（第 5 个 AI）· Token 页三新源 · 内存峰值 −78% · Snooze/低电量 · Gemini 翻倍修复", "Grok support (5th AI) · 3 new token sources · −78% peak memory · snooze/low-power · Gemini double-count fix")),
        ("1.5.2", L("加固：声明口径校正 · Copilot 风险确认 · 错误数据不再伪装成正常 · 空状态指引", "Hardening: honest disclaimer · Copilot risk gate · no more fake-healthy data · actionable empty state")),
        ("1.5.1", L("关窗释放视图内存（后台 37MB，重开 46ms 无感）· CLI 补全重置额度/数据时间", "Release view memory on close (37MB resident, 46ms rebuild) · CLI resets/data-age fields")),
        ("1.5.0", L("命令行模式 --cli · 修复弹层悬停延迟 · 刘海点击直达主窗口 · 文档口径统一", "CLI mode (--cli) · fixed popover hover lag · notch panel click-through · unified docs wording")),
        ("1.4.8", L("分段刻度仅保留 5h 窗口 · 说明页灰度统一 · 快速入门措辞打磨", "Tick marks now 5h-window only · unified guide-page grays · quick-start copy polish")),
        ("1.4.7", L("分段式用量条（20/50 刻度）· Codex 重置额度胶囊 · 失败自动退避 · 快速入门", "Segmented bars (20/50 ticks) · Codex reset-credits chip · failure backoff · quick start")),
        ("1.4.6", L("修复 Codex 用量滞后/不准：增量读取免疫巨行 · 数据时间胶囊 · 关闭 App Nap", "Fix Codex lag: incremental reads immune to giant lines · data-age chip · App Nap off")),
        ("1.4.5", L("接入 LiteLLM 社区定价（2900+ 模型）：新模型成本/缓存节省自动覆盖，发版时同步", "LiteLLM community pricing (2900+ models): new-model costs auto-covered, synced at release")),
        ("1.4.4", L("修复频繁弹「允许访问钥匙串」：Copilot / Claude Code 条目加进程内读缓存", "Fix repeated Keychain prompts: in-process read cache for Copilot / Claude Code items")),
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
                    // 不用 LabeledContent：它把内容靠右排，多行文案会变成右对齐的锯齿块。
                    // 版本号一行、说明一行，全部左对齐。
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.version)
                        Text(item.note)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                LabeledContent(L("版本", "Version"), value: "Tokenitor v\(appVersion)")
                // 社交入口：版本下方、右下角。官方图形标（GitHub Mark / X logo / 纸飞机），
                // 指示性使用（链接到本项目/作者页面），单色随主题着色。
                HStack(spacing: 12) {
                    Spacer()
                    CircleGlyphButton(help: L("GitHub · 项目主页", "GitHub · Project")) {
                        if let u = URL(string: "https://github.com/CSzcm8788/Tokenitor") {
                            NSWorkspace.shared.open(u)
                        }
                    } icon: {
                        BrandIcon.github.fill(style: FillStyle(eoFill: true))
                            .frame(width: 16, height: 16)
                    }
                    CircleGlyphButton(help: L("X · 作者主页", "X · Author")) {
                        if let u = URL(string: "https://x.com/yukabiubiu") {
                            NSWorkspace.shared.open(u)
                        }
                    } icon: {
                        BrandIcon.x.fill(style: FillStyle(eoFill: true))
                            .frame(width: 14, height: 14)   // X 标形状偏满，视觉上与 16pt 其它图标等重
                    }
                    CircleGlyphButton(help: L("Telegram · 联系作者", "Telegram · Contact")) {
                        if let u = URL(string: "https://t.me/yukabiubiu") {
                            NSWorkspace.shared.open(u)
                        }
                    } icon: {
                        Image(systemName: "paperplane")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 16, height: 16)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
            } header: {
                sectionTitle(L("语言", "Language"),
                             L("界面语言；未选择时跟随 macOS 系统语言。", "Interface language; follows the macOS system language unless set."))
            } footer: {
                Text(L("切换语言需重启应用生效。", "Relaunch the app to apply the language change."))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// Form section 的标题 + 说明，与设置页 `sectionHeader` 同款——语言 / 外观页此前裸着没标题，
/// 与设置页并排看是两种规格。抽到文件级供两页复用。
@ViewBuilder
func sectionTitle(_ title: String, _ desc: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.sectionTitle).foregroundStyle(.primary)
        Text(desc).font(.uiCaption).foregroundStyle(.secondary)
    }
    .textCase(nil)
    .padding(.bottom, 2)
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
            } header: {
                sectionTitle(L("外观", "Appearance"),
                             L("选择浅色 / 深色，或跟随 macOS 系统外观。", "Pick light or dark, or follow the macOS system appearance."))
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
                EmptyStateView(hasFetched: store.hasFetched, compact: true) {
                    store.onOpenWindow(.settings)
                }
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
        .activeHover { hovering = $0 }   // 弹层可能在 app 未激活时打开，普通 onHover 会滞后
    }
}
