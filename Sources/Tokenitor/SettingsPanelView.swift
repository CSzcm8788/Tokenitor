import SwiftUI
import AppKit
import ServiceManagement

/// 开机自启（登录项）：macOS 13+ 用 SMAppService 一键开/关；旧系统降级为不可用。
enum LoginItem {
    static var enabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    static func set(_ on: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { NSLog("[login-item] \(error.localizedDescription)") }
    }
}

/// 外观模式：跟随系统 / 浅色 / 深色，应用到整个 app（NSApp.appearance）。
enum AppearanceMode {
    static func apply() {
        switch Settings.shared.appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil   // 跟随系统
        }
    }
}

/// 界面语言：跟随系统 / 中文 / English，**切换后需重启生效**（界面文案由 L10n 决定，
/// 这里的 AppleLanguages 覆盖只影响系统提供的字符串，如标准菜单项）。
enum LanguageManager {
    static func apply() {
        switch Settings.shared.language {
        case "zh": UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case "en": UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        default:   UserDefaults.standard.removeObject(forKey: "AppleLanguages")   // 跟随系统
        }
    }
}

/// 设置面板：Apple 原生 `Form(.grouped)` + 原生 `Toggle` / `Picker` / `Section` footer，
/// 呈现与 macOS「系统设置」一致的分组样式。改动即时同步到刘海面板与主窗口。
/// 需要 macOS 13+（.formStyle(.grouped) / LabeledContent）。
struct SettingsPanelView: View {
    @ObservedObject var store: UsageStore

    private let warnOptions = [80, 70, 60, 50, 40, 30]
    private let critOptions = [50, 40, 30, 20]
    private let geminiLimitOptions = [250, 500, 1000, 2000]
    private let intervalOptions = [30, 60, 120, 300]

    var body: some View {
        // 每个分区一个「小标题 + 一句话简介」（同系统设置）；详细口径/风险说明统一在「说明」页，
        // 这里不再放 footer 长文（避免两处重复维护）。
        Form {
            // AI 服务
            Section {
                ForEach(AIKind.allCases) { kind in
                    aiToggle(kind)
                }
            } header: {
                sectionHeader(L("AI 服务", "AI Services"), L("选择要监控用量的工具；走社区接口的（Claude / Copilot）首次开启各弹一次确认。", "Pick the tools to monitor; Claude / Copilot use community APIs and each asks for confirmation on first enable."))
            }

            // 告警
            Section {
                Toggle(isOn: bind({ Settings.shared.notificationsEnabled },
                                  { Settings.shared.notificationsEnabled = $0; store.onSettingsChanged() })) {
                    Label(L("通知告警", "Notifications"), systemImage: "bell")
                }
                Picker(L("低用量阈值（剩余）", "Low threshold (remaining)"),
                       selection: bind({ Int(Settings.shared.warnAt) },
                                       { Settings.shared.warnAt = Double($0); store.onSettingsChanged() })) {
                    ForEach(warnOptions, id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker(L("紧急阈值（剩余）", "Critical threshold (remaining)"),
                       selection: bind({ Int(Settings.shared.critAt) },
                                       { Settings.shared.critAt = Double($0); store.onSettingsChanged() })) {
                    ForEach(critOptions, id: \.self) { Text("\($0)%").tag($0) }
                }
                snoozeRow
            } header: {
                sectionHeader(L("告警", "Alerts"), L("剩余量跌破阈值时发一次系统通知，回升后可再次触发。", "Notifies once when remaining quota drops below a threshold; re-arms after recovery."))
            }

            // 通用
            Section {
                Picker(L("Gemini 每日额度（估算）", "Gemini daily limit (estimate)"),
                       selection: bind({ Int(Settings.shared.geminiDailyLimit) },
                                       { Settings.shared.geminiDailyLimit = Double($0); store.onSettingsChanged() })) {
                    ForEach(geminiLimitOptions, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(L("刷新间隔", "Refresh interval"),
                       selection: bind({ Int(Settings.shared.refreshInterval) },
                                       { Settings.shared.refreshInterval = Double($0); store.onSettingsChanged() })) {
                    ForEach(intervalOptions, id: \.self) { Text("\($0)s").tag($0) }
                }
                Toggle(isOn: bind({ LoginItem.enabled }, { LoginItem.set($0) })) {
                    Label(L("开机自启", "Launch at login"), systemImage: "power")
                }
                Toggle(isOn: bind({ Settings.shared.notchEnabled },
                                  { Settings.shared.notchEnabled = $0; store.onSettingsChanged() })) {
                    Label(L("刘海面板", "Notch panel"), systemImage: "rectangle.topthird.inset.filled")
                }
                Toggle(isOn: bind({ Settings.shared.statusMonitorEnabled },
                                  { Settings.shared.statusMonitorEnabled = $0; store.onSettingsChanged() })) {
                    Label(L("服务状态监控", "Service status monitor"), systemImage: "waveform.path.ecg")
                }
                Toggle(isOn: bind({ Settings.shared.debugDump }, { Settings.shared.debugDump = $0 })) {
                    Label(L("调试转储", "Debug dumps"), systemImage: "ladybug")
                }
            } header: {
                sectionHeader(L("通用", "General"), L("刷新频率与常驻行为；各项含义详见「说明」页。", "Refresh cadence and background behavior; see the Guide page for details."))
            }

            // 动作：测试通知/数据文件夹 一行，两个授权 一行（均带悬停反馈）
            Section {
                HStack(spacing: 10) {
                    Button(L("测试通知", "Test Notification")) { store.onTestNotify() }
                        .help(L("发一条测试通知，确认系统通知权限正常", "Send a test notification to confirm permission"))
                        .pressableHover()
                    Button(L("数据文件夹", "Data Folder")) { Self.openDataFolder() }
                        .help(L("打开 ~/.tokenitor（历史/缓存/日志/调试转储所在目录）", "Open ~/.tokenitor (history / cache / logs / dumps)"))
                        .pressableHover()
                    Spacer()
                }
                .buttonStyle(.bordered)
                HStack(spacing: 10) {
                    Button(L("授权 Copilot", "Authorize Copilot")) { store.onLoginCopilot() }
                        .help(L("用 GitHub device flow 显式授权，读取 Copilot 高级用量", "Authorize via GitHub device flow to read Copilot premium usage"))
                        .pressableHover()
                    Button(L("授权 Claude", "Authorize Claude")) { store.onReloginClaude() }
                        .help(L("在终端里用订阅账号 /login 一次，生成 Tokenitor 可读的凭证", "Run /login once in Terminal with your subscription account"))
                        .pressableHover()
                    Spacer()
                }
                .buttonStyle(.bordered)
            } header: {
                sectionHeader(L("动作", "Actions"), L("通知测试、数据目录与账号授权。", "Notification test, data folder, and account authorization."))
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // 隐藏 Form 分组的不透明底，露出窗口玻璃材质
    }

    // MARK: - 行

    /// 分区头：小标题 + 一句话简介（同「系统设置」的分组头风格）。
    /// 静音行：未静音时给 1/4/8 小时三个快捷键；静音中显示截止时间与取消按钮。
    @ViewBuilder
    private var snoozeRow: some View {
        if Settings.shared.alertsSnoozed {
            HStack {
                Label(L("已静音至 \(snoozeUntilText)", "Snoozed until \(snoozeUntilText)"),
                      systemImage: "moon.zzz")
                Spacer()
                Button(L("取消静音", "Unsnooze")) {
                    Settings.shared.alertsSnoozedUntil = 0; store.onSettingsChanged()
                }
            }
        } else {
            HStack {
                Label(L("暂时静音", "Snooze"), systemImage: "moon.zzz")
                Spacer()
                ForEach([1, 4, 8], id: \.self) { h in
                    Button(L("\(h)小时", "\(h)h")) {
                        Settings.shared.alertsSnoozedUntil =
                            Date().addingTimeInterval(Double(h) * 3600).timeIntervalSince1970
                        store.onSettingsChanged()
                    }
                }
            }
        }
    }

    private var snoozeUntilText: String {
        let df = DateFormatter(); df.dateFormat = "HH:mm"
        return df.string(from: Date(timeIntervalSince1970: Settings.shared.alertsSnoozedUntil))
    }

    private func sectionHeader(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sectionTitle).foregroundStyle(.primary)
            Text(desc).font(.uiCaption).foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }

    /// 一个 AI 开关（走社区接口的 Claude / Copilot 首次开启各弹一次风险确认，行内不再重复标注）。
    /// AI 行不带图标，只用名称（品牌 logo 已移除）。
    private func aiToggle(_ kind: AIKind) -> some View {
        Toggle(isOn: Binding(
            get: { Settings.shared.isEnabled(kind) },
            set: { on in
                Settings.shared.setEnabled(kind, on ? RiskGate.confirmEnableIfNeeded(kind) : false)
                store.onSettingsChanged()
            })) {
            Text(kind.title)
        }
    }

    /// 打开数据目录 ~/.tokenitor（不存在则先创建）。
    private static func openDataFolder() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tokenitor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    // MARK: - 绑定辅助

    private func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }
}
