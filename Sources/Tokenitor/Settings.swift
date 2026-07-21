import Foundation

/// 用户设置，持久化在 UserDefaults。
final class Settings {
    static let shared = Settings()

    private let d = UserDefaults.standard

    // 阈值：剩余百分比低于这些值时变色 / 告警。
    // 语义要求 warnAt > critAt（先「偏低」再「紧急」）；倒置会让告警与配色失去意义，
    // 故在 setter 里强制成立——改动哪一个就以哪一个为准，把另一个顶开（纯函数见下，便于测试）。
    var warnAt: Double {
        get { Self.clampWarn(d.object(forKey: "warnAt") as? Double ?? 50) }
        set {
            let (w, c) = Self.resolveThresholds(settingWarn: newValue, currentCrit: critAt)
            d.set(w, forKey: "warnAt"); d.set(c, forKey: "critAt")
        }
    }
    var critAt: Double {
        get { Self.clampCrit(d.object(forKey: "critAt") as? Double ?? 20) }
        set {
            let (w, c) = Self.resolveThresholds(settingCrit: newValue, currentWarn: warnAt)
            d.set(w, forKey: "warnAt"); d.set(c, forKey: "critAt")
        }
    }

    static func clampWarn(_ v: Double) -> Double { min(100, max(1, v)) }
    static func clampCrit(_ v: Double) -> Double { min(99, max(0, v)) }

    /// 用户改「低用量阈值」：紧急阈值必须严格更低，必要时把它顶下去。
    static func resolveThresholds(settingWarn warn: Double, currentCrit crit: Double) -> (Double, Double) {
        let w = clampWarn(warn)
        return (w, min(clampCrit(crit), w - 1))
    }
    /// 用户改「紧急阈值」：低用量阈值必须严格更高，必要时把它顶上去。
    static func resolveThresholds(settingCrit crit: Double, currentWarn warn: Double) -> (Double, Double) {
        let c = clampCrit(crit)
        return (max(clampWarn(warn), c + 1), c)
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
    // 同上，Copilot（同样走社区接口，同样需要首次确认）
    var copilotRiskAccepted: Bool {
        get { d.object(forKey: "copilotRiskAccepted") as? Bool ?? false }
        set { d.set(newValue, forKey: "copilotRiskAccepted") }
    }
    /// 按数据源读写风险确认状态（供 RiskGate 统一调用）。
    func riskAccepted(_ kind: AIKind) -> Bool {
        switch kind {
        case .claude:  return claudeRiskAccepted
        case .copilot: return copilotRiskAccepted
        default:       return true       // 纯本地源无需确认
        }
    }
    func setRiskAccepted(_ kind: AIKind, _ v: Bool) {
        switch kind {
        case .claude:  claudeRiskAccepted = v
        case .copilot: copilotRiskAccepted = v
        default:       break
        }
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

    // Gemini 每日请求额度（本地估算的分母）。官方额度按账号类型/时段在 250–2000 之间浮动
    // 且本地不可读，故给出可选档位、默认 1000，界面明确标注「估算」。
    var geminiDailyLimit: Double {
        get { max(1, d.object(forKey: "geminiDailyLimit") as? Double ?? 1000) }
        set { d.set(max(1, newValue), forKey: "geminiDailyLimit") }
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
