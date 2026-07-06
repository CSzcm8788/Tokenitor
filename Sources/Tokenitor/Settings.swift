import Foundation

/// 用户设置，持久化在 UserDefaults。
final class Settings {
    static let shared = Settings()

    private let d = UserDefaults.standard

    // 阈值：剩余百分比低于这些值时变色 / 告警
    var warnAt: Double {
        get { d.object(forKey: "warnAt") as? Double ?? 50 }
        set { d.set(newValue, forKey: "warnAt") }
    }
    var critAt: Double {
        get { d.object(forKey: "critAt") as? Double ?? 20 }
        set { d.set(newValue, forKey: "critAt") }
    }

    // 刷新间隔（秒）
    var refreshInterval: Double {
        get { max(15, d.object(forKey: "refreshInterval") as? Double ?? 60) }
        set { d.set(newValue, forKey: "refreshInterval") }
    }

    // 工具开关
    // 注意：Claude 走 Anthropic 未公开接口、属高级·自担风险功能，默认关闭（需用户在设置里确认风险后开启）。
    var claudeEnabled: Bool {
        get { d.object(forKey: "claudeEnabled") as? Bool ?? false }
        set { d.set(newValue, forKey: "claudeEnabled") }
    }
    // 是否已确认 Claude 用量读取的风险（开启前弹窗确认，确认后记住）
    var claudeRiskAccepted: Bool {
        get { d.object(forKey: "claudeRiskAccepted") as? Bool ?? false }
        set { d.set(newValue, forKey: "claudeRiskAccepted") }
    }
    var codexEnabled: Bool {
        get { d.object(forKey: "codexEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "codexEnabled") }
    }
    var geminiEnabled: Bool {
        get { d.object(forKey: "geminiEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "geminiEnabled") }
    }
    // Copilot 走 GitHub 内部端点（copilot_internal/user）→ 高级·默认关。
    var copilotEnabled: Bool {
        get { d.object(forKey: "copilotEnabled") as? Bool ?? false }
        set { d.set(newValue, forKey: "copilotEnabled") }
    }

    // 模块化开关读写：按 AIKind 统一存取（键名与上面各属性一致）
    // 默认值：走非官方/未公开端点的两家（Claude / Copilot）默认关（高级·自担风险），
    // 纯本地零联网的（Codex / Gemini）默认开。
    private func defaultEnabled(_ kind: AIKind) -> Bool {
        switch kind {
        case .claude, .copilot: return false
        case .codex, .gemini:   return true
        }
    }
    func isEnabled(_ kind: AIKind) -> Bool {
        d.object(forKey: kind.defaultsKey) as? Bool ?? defaultEnabled(kind)
    }
    func setEnabled(_ kind: AIKind, _ on: Bool) {
        d.set(on, forKey: kind.defaultsKey)
    }

    // 是否已同意免责声明（首次启动弹窗）
    var disclaimerAccepted: Bool {
        get { d.object(forKey: "disclaimerAccepted") as? Bool ?? false }
        set { d.set(newValue, forKey: "disclaimerAccepted") }
    }

    // 通知开关
    var notificationsEnabled: Bool {
        get { d.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "notificationsEnabled") }
    }

    // 刘海悬停面板开关（关掉则不监听、不弹刘海面板）
    var notchEnabled: Bool {
        get { d.object(forKey: "notchEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "notchEnabled") }
    }

    // 界面语言：跟随系统 / 中文 / English（"system" / "zh" / "en"）
    var language: String {
        get { d.object(forKey: "language") as? String ?? "system" }
        set { d.set(newValue, forKey: "language") }
    }

    // 外观：跟随系统 / 浅色 / 深色（"system" / "light" / "dark"）
    var appearance: String {
        get { d.object(forKey: "appearance") as? String ?? "system" }
        set { d.set(newValue, forKey: "appearance") }
    }

    // 菜单栏标题里是否显示工具名前缀
    var compactTitle: Bool {
        get { d.object(forKey: "compactTitle") as? Bool ?? false }
        set { d.set(newValue, forKey: "compactTitle") }
    }

    // 厂商服务状态监控（各家公开 status page，5 分钟轮询；胶囊 + 菜单栏指示点）
    var statusMonitorEnabled: Bool {
        get { d.object(forKey: "statusMonitorEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "statusMonitorEnabled") }
    }

    // 写调试转储（原始 JSON）到 ~/.tokenitor/debug/
    var debugDump: Bool {
        get { d.object(forKey: "debugDump") as? Bool ?? false }
        set { d.set(newValue, forKey: "debugDump") }
    }
}
