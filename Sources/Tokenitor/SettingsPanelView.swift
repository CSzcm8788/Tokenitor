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

/// 界面语言：跟随系统 / 中文 / English。通过 AppleLanguages 覆盖，**切换后需重启生效**。
/// （English 字符串本地化正在逐步完善，未译处暂显中文。）
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
    private let intervalOptions = [30, 60, 120, 300]

    var body: some View {
        Form {
            // 各 AI 服务开关 + 通知
            Section {
                ForEach(AIKind.allCases) { kind in
                    aiToggle(kind)
                }
                Toggle(isOn: bind({ Settings.shared.notificationsEnabled },
                                  { Settings.shared.notificationsEnabled = $0; store.onSettingsChanged() })) {
                    Label("通知告警", systemImage: "bell")
                }
            } footer: {
                Text("Claude / Copilot 走非官方端点，默认关闭、需自担风险。")
            }

            // 阈值 / 刷新间隔
            Section {
                Picker("低用量阈值（剩余）",
                       selection: bind({ Int(Settings.shared.warnAt) },
                                       { Settings.shared.warnAt = Double($0); store.onSettingsChanged() })) {
                    ForEach(warnOptions, id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker("紧急阈值（剩余）",
                       selection: bind({ Int(Settings.shared.critAt) },
                                       { Settings.shared.critAt = Double($0); store.onSettingsChanged() })) {
                    ForEach(critOptions, id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker("刷新间隔",
                       selection: bind({ Int(Settings.shared.refreshInterval) },
                                       { Settings.shared.refreshInterval = Double($0); store.onSettingsChanged() })) {
                    ForEach(intervalOptions, id: \.self) { Text("\($0)s").tag($0) }
                }
            }

            // 偏好
            Section {
                Toggle(isOn: bind({ LoginItem.enabled }, { LoginItem.set($0) })) {
                    Label("开机自启", systemImage: "power")
                }
                Toggle(isOn: bind({ Settings.shared.notchEnabled },
                                  { Settings.shared.notchEnabled = $0; store.onSettingsChanged() })) {
                    Label("刘海面板", systemImage: "rectangle.topthird.inset.filled")
                }
                Toggle(isOn: bind({ Settings.shared.statusMonitorEnabled },
                                  { Settings.shared.statusMonitorEnabled = $0; store.onSettingsChanged() })) {
                    Label("服务状态监控", systemImage: "waveform.path.ecg")
                }
                Toggle(isOn: bind({ Settings.shared.debugDump }, { Settings.shared.debugDump = $0 })) {
                    Label("调试转储", systemImage: "ladybug")
                }
            } footer: {
                Text("服务状态监控：每 5 分钟轮询各厂商公开状态页（status.claude.com / status.openai.com / githubstatus.com），异常时卡片显示「服务降级 / 中断」胶囊、菜单栏图标加指示点。")
            }

            // 动作（两个并排）
            Section {
                HStack(spacing: 10) {
                    Button("测试通知") { store.onTestNotify() }
                        .help("发一条测试通知，确认系统通知权限正常")
                    Button("重新登录 Claude") { store.onReloginClaude() }
                        .help("Claude 用量读不出来时，重新走订阅 /login 刷新凭证")
                    Spacer()
                }
                .buttonStyle(.bordered)
                HStack(spacing: 10) {
                    Button("授权 Copilot") { store.onLoginCopilot() }
                        .help("用 GitHub device flow 显式授权，读取 Copilot 高级用量")
                    Spacer()
                }
                .buttonStyle(.bordered)
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // 隐藏 Form 分组的不透明底，露出窗口玻璃材质
    }

    // MARK: - 行

    /// 一个 AI 开关（Claude 走风险确认弹窗）。AI 行不带图标，只用名称（品牌 logo 已移除）。
    private func aiToggle(_ kind: AIKind) -> some View {
        Toggle(isOn: Binding(
            get: { Settings.shared.isEnabled(kind) },
            set: { on in
                if kind == .claude {
                    Settings.shared.setEnabled(.claude, on ? ClaudeRiskGate.confirmEnableIfNeeded() : false)
                } else {
                    Settings.shared.setEnabled(kind, on)
                }
                store.onSettingsChanged()
            })) {
            if kind == .claude {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text("高级 · 自担风险").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(kind.title)
            }
        }
    }

    // MARK: - 绑定辅助

    private func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }
}
