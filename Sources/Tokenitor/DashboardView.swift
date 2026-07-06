import SwiftUI
import AppKit

/// 主窗口：Apple 原生 `NavigationSplitView`（同 macOS 系统设置）——左边栏列表 + 右侧详情。
/// 工具栏只留系统的边栏折叠/前进后退；刷新在「用量」详情页内。
struct DashboardView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        NavigationSplitView {
            sidebarList
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            .navigationTitle("Tokenitor")
        } detail: {
            detail
                // 工具栏（标题栏）始终有材质：内容滚动到它下面时被正常遮挡，
                // 不再出现卡片盖住标题/按钮的错乱（此前透明标题栏 + 玻璃窗口无遮挡）。
                .toolbarBackground(.visible, for: .windowToolbar)
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

    private var sidebarContent: some View {
        List(selection: sidebarSelection) {
                // 分组式导航（概览 / 通用 / 其他）+ 单色 SF Symbols 图标：
                // 遵循 macOS 侧边栏惯例（Finder/Mail 风格，图标随系统强调色/选中态自动着色），
                // 不再用彩色圆角块，全 app 图标语言统一为线性单色。
                Section("概览") {
                    sidebarItem("仪表", "gauge.medium", .usage)
                    sidebarItem("Token", "chart.bar.xaxis", .tokens)
                }
                Section("通用") {
                    sidebarItem("语言", "globe", .language)
                    sidebarItem("外观", "circle.lefthalf.filled", .appearance)
                    sidebarItem("设置", "gearshape", .settings)
                }
                Section("其他") {
                    sidebarItem("关于", "info.circle", .about)
                    sidebarItem("说明", "questionmark.circle", .help)
                }
        }
    }

    /// 边栏选中项 ↔ store.page 映射。
    private var sidebarSelection: Binding<AppPage?> {
        Binding(
            get: {
                switch store.page {
                case .usage:              return .usage
                case .tokens, .tokenInfo: return .tokens
                case .language:           return .language
                case .appearance:         return .appearance
                case .settings:           return .settings
                case .about:              return .about
                case .help:               return .help
                }
            },
            set: { store.page = $0 ?? .usage })
    }

    /// 边栏行：单色 SF Symbol + 名称（着色交给系统：强调色 / 选中态自动适配）。
    private func sidebarItem(_ title: String, _ icon: String, _ page: AppPage) -> some View {
        Label(title, systemImage: icon)
            .tag(page)
    }

    @ViewBuilder
    private var detail: some View {
        switch store.page {
        case .usage:
            usageDetail
        case .tokens, .tokenInfo:
            tokenDetail
        case .language:
            LanguageDetail(store: store).navigationTitle("语言")
        case .appearance:
            AppearanceDetail().navigationTitle("外观")
        case .settings:
            SettingsView(store: store, inPopover: false).navigationTitle("设置")
        case .about:
            AboutDetail(store: store).navigationTitle("关于")
        case .help:
            HelpView().navigationTitle("说明")
        }
    }

    // MARK: - 用量详情（刷新按钮在页内）

    private var usageDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.snapshots.isEmpty {
                    Text("正在获取用量…").foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(store.snapshots, id: \.name) { snap in
                        AIMonitorPanel(snap: snap,
                                       warnAt: Settings.shared.warnAt,
                                       critAt: Settings.shared.critAt,
                                       updatedAt: store.lastUpdate,
                                       hero: true,   // 主窗口用 hero 卡：胶囊行 + 统计瓦片 + 用量条
                                       serviceIndicator: store.serviceStatus[snap.name])
                    }
                }
                HStack {
                    Spacer()
                    Button { store.onRefresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("刷新")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("用量")
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
        .navigationTitle("Token 用量")
    }

}

/// 「关于」详情：作者社交图标（不展示裸链接）/ 数据文件夹 / 版本更新简要 / 版本号。
struct AboutDetail: View {
    @ObservedObject var store: UsageStore

    /// 版本更新简要（一版一行；完整日志见 GitHub README）。
    private static let releaseNotes: [(version: String, note: String)] = [
        ("1.2.0", "服务状态监控 · 套餐胶囊 · 中文倒计时 · Homebrew 分发"),
        ("1.1.0", "仪表重设计：分组侧边栏 + hero 卡片"),
        ("1.0.1", "安全与稳定性修复（凭证只读、刷新看门狗等）"),
        ("1.0.0", "首个正式版"),
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    socialButton(icon: "chevron.left.forwardslash.chevron.right",
                                 help: "GitHub · 项目主页",
                                 url: "https://github.com/CSzcm8788/Tokenitor")
                    socialButton(icon: "paperplane.fill",
                                 help: "Telegram · 联系作者",
                                 url: "https://t.me/yukabiubiu")
                    socialButton(text: "𝕏",
                                 help: "X · 作者主页",
                                 url: "https://x.com/yukabiubiu")
                    Spacer()
                    Button { openDataFolder() } label: { Label("数据文件夹", systemImage: "folder") }
                        .buttonStyle(.bordered)
                }
            }
            Section("更新简要") {
                ForEach(Self.releaseNotes, id: \.version) { item in
                    LabeledContent(item.version) {
                        Text(item.note).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent("版本", value: "Tokenitor v\(appVersion)")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// 圆形社交图标按钮：SF Symbol 或文字符号（不内置第三方品牌图片，与全 app 政策一致）。
    private func socialButton(icon: String? = nil, text: String? = nil,
                              help: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Group {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .medium))
                } else {
                    Text(text ?? "").font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.primary.opacity(0.07)))
            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private func openDataFolder() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tokenitor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
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
                    Text("跟随系统").tag("system")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                } label: { Label("界面语言", systemImage: "globe") }
                .pickerStyle(.menu)
            } footer: {
                Text("切换语言需重启应用生效。English 本地化逐步完善中。")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// 「外观」详情：浅色 / 深色 / 跟随系统（从「设置」移出，成独立侧边栏项，同系统设置）。
struct AppearanceDetail: View {
    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { Settings.shared.appearance },
                    set: { Settings.shared.appearance = $0; AppearanceMode.apply() })) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                } label: {
                    Label("外观", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.inline)
            } footer: {
                Text("选择浅色 / 深色 / 跟随系统外观。")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
                    Text("更新于 \(formatUpdatedAgo(t))")   // 面板级统一显示，卡片下不再挂小字
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                glanceButton("chart.bar.xaxis", "Token 用量") { store.onOpenWindow(.tokens) }
                glanceButton("gearshape", "设置") { store.onOpenWindow(.settings) }
                glanceButton("arrow.clockwise", "刷新") { store.onRefresh() }
            }
            if store.snapshots.isEmpty {
                Text("正在获取用量…").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(store.snapshots, id: \.name) { snap in
                    AIMonitorPanel(snap: snap, warnAt: Settings.shared.warnAt, critAt: Settings.shared.critAt)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(VisualEffectView(material: .popover, blending: .behindWindow).ignoresSafeArea())
    }

    private func glanceButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
