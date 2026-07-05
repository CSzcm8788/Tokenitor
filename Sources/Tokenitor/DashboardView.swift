import SwiftUI
import AppKit

/// 主窗口：Apple 原生 `NavigationSplitView`（同 macOS 系统设置）——左边栏列表 + 右侧详情。
/// 工具栏只留系统的边栏折叠/前进后退；刷新在「用量」详情页内。
struct DashboardView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                sidebarItem("仪表", "speedometer", .teal, .usage)
                sidebarItem("Token", "chart.line.uptrend.xyaxis", .green, .tokens)
                sidebarItem("语言", "globe", .blue, .language)
                sidebarItem("外观", "circle.lefthalf.filled", .orange, .appearance)
                sidebarItem("设置", "gearshape", .gray, .settings)
                sidebarItem("关于", "info.circle", .indigo, .about)
                sidebarItem("说明", "questionmark.circle", .pink, .help)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            .navigationTitle("Tokenitor")
        } detail: {
            detail
                .background(VisualEffectView(material: .popover, blending: .behindWindow).ignoresSafeArea())
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

    /// 系统设置风格的边栏行：彩色圆角图标块 + 名称。
    private func sidebarItem(_ title: String, _ icon: String, _ color: Color, _ page: AppPage) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color))
        }
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
                                       critAt: Settings.shared.critAt)
                    }
                }
                HStack {
                    if let t = store.lastUpdate {
                        Text("更新于 \(timeString(t))").font(.uiCaption).foregroundStyle(.secondary)
                    }
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

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
}

/// 「关于」详情：GitHub / 数据文件夹 / 使用说明，版本在最下方。
struct AboutDetail: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section {
                Link(destination: URL(string: "https://github.com/CSzcm8788/Tokenitor")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button { openDataFolder() } label: { Label("数据文件夹", systemImage: "folder") }
            }
            Section {
                LabeledContent("版本", value: "Tokenitor v\(appVersion)")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
            HStack(spacing: 6) {
                Text("Tokenitor").font(.headline)
                Spacer()
                glanceButton("chart.line.uptrend.xyaxis", "Token 用量") { store.onOpenWindow(.tokens) }
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
            if let t = store.lastUpdate {
                Text("更新于 \(timeString(t))").font(.caption).foregroundStyle(.secondary)
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

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
}
