import Foundation

/// 单个 AI 的服务状态结论：指示级别 + 组件明细（胶囊 tooltip 用）。
struct ServiceStatus: Equatable {
    /// minor（降级）/ major（部分中断）/ critical（重大中断）
    var indicator: String
    /// 出问题的相关组件明细，如 "Codex API：部分中断"
    var detail: String
}

/// 厂商服务状态监控：轮询各家**公开** status page 的 `summary.json`（Statuspage v2，无鉴权、只读），
/// 按**组件级**判定——只看与该 AI 相关的组件，取最差状态。
///
/// 为什么不用顶层 indicator：OpenAI 状态页有 30+ 组件（Sora / Ads / FedRAMP…），任何无关组件
/// 出事顶层就变 minor，曾导致 Codex 卡长期误报「服务降级」（实测元凶是 FedRAMP 政府云组件）。
final class StatusMonitor {

    /// AIKind → summary.json 端点（Gemini 无公开 Statuspage，暂不监控）。
    private static let endpoints: [AIKind: URL] = [
        .claude:  URL(string: "https://status.claude.com/api/v2/summary.json")!,
        .codex:   URL(string: "https://status.openai.com/api/v2/summary.json")!,
        .copilot: URL(string: "https://www.githubstatus.com/api/v2/summary.json")!,
    ]

    /// 各 AI 的相关组件（小写包含匹配）；不在表里的组件一律无视。
    private static let relevantKeywords: [AIKind: [String]] = [
        .codex:   ["codex", "responses", "vs code extension"],
        .claude:  ["claude code", "claude api", "claude.ai"],
        .copilot: ["copilot"],
    ]

    /// 结果回调（main 线程）：AI 名 → 服务状态（相关组件全部正常则不含该键）。
    var onChange: (([String: ServiceStatus]) -> Void)?

    private var timer: Timer?

    func start(interval: TimeInterval = 300) {
        stop()
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 30
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        onChange?([:])   // 关闭监控即清掉指示（胶囊/菜单栏点消失）
    }

    private func poll() {
        guard Settings.shared.statusMonitorEnabled else { return }
        let group = DispatchGroup()
        var result: [String: ServiceStatus] = [:]
        let lock = NSLock()
        for (kind, url) in Self.endpoints where Settings.shared.isEnabled(kind) {
            group.enter()
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                guard let data,
                      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let comps = root["components"] as? [[String: Any]] else { return }
                let pairs = comps.compactMap { c -> (String, String)? in
                    guard let name = c["name"] as? String, let st = c["status"] as? String else { return nil }
                    return (name, st)
                }
                if let status = Self.summarize(kind: kind, components: pairs) {
                    lock.lock(); result[kind.title] = status; lock.unlock()
                }
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            self?.onChange?(result)
        }
    }

    // MARK: - 纯函数（单元测试直接验证）

    /// 组件 status → 我们的指示级别；operational / 未知视为正常（nil）。
    static func indicator(forComponentStatus s: String) -> String? {
        switch s {
        case "major_outage":                            return "critical"
        case "partial_outage":                          return "major"
        case "degraded_performance", "under_maintenance": return "minor"
        default:                                        return nil
        }
    }

    /// 汇总某 AI 的相关组件：全正常 → nil；否则给最差指示级别 + 出事组件明细。
    static func summarize(kind: AIKind, components: [(String, String)]) -> ServiceStatus? {
        guard let keywords = relevantKeywords[kind] else { return nil }
        let rank = ["critical": 3, "major": 2, "minor": 1]
        var worst: String? = nil
        var details: [String] = []
        for (name, status) in components {
            let lower = name.lowercased()
            guard keywords.contains(where: { lower.contains($0) }) else { continue }
            guard let ind = indicator(forComponentStatus: status) else { continue }
            if rank[ind, default: 0] > rank[worst ?? "", default: 0] { worst = ind }
            details.append("\(name)：\(statusLabel(status))")
        }
        guard let worst else { return nil }
        return ServiceStatus(indicator: worst, detail: details.joined(separator: "；"))
    }

    private static func statusLabel(_ s: String) -> String {
        switch s {
        case "major_outage":          return L("重大中断", "major outage")
        case "partial_outage":        return L("部分中断", "partial outage")
        case "degraded_performance":  return L("性能下降", "degraded")
        case "under_maintenance":     return L("维护中", "maintenance")
        default:                      return s
        }
    }

    /// 一组状态里最严重的指示级别（critical > major > minor），用于菜单栏指示点。
    static func worst(of statuses: [String: ServiceStatus]) -> String? {
        let rank = ["critical": 3, "major": 2, "minor": 1]
        return statuses.values.map(\.indicator).max { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
    }
}
