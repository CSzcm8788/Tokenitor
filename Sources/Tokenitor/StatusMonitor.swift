import Foundation

/// 厂商服务状态监控：轮询各家**公开** status page（Atlassian Statuspage v2 JSON，无鉴权、只读），
/// 取 `status.indicator`（none / minor / major / critical）。
/// 展示：仪表 hero 卡片上的「服务降级 / 服务中断」胶囊 + 菜单栏图标的彩色指示点。
/// 配额低 ≠ 服务挂了，两者互补——这能回答"是我额度用完了，还是他们服务出事了"。
final class StatusMonitor {

    /// AIKind → 对应厂商的 status page 端点（Gemini 无公开 Statuspage，暂不监控）。
    private static let endpoints: [AIKind: URL] = [
        .claude:  URL(string: "https://status.claude.com/api/v2/status.json")!,
        .codex:   URL(string: "https://status.openai.com/api/v2/status.json")!,
        .copilot: URL(string: "https://www.githubstatus.com/api/v2/status.json")!,
    ]

    /// 结果回调（main 线程）：AI 名 → indicator。
    var onChange: (([String: String]) -> Void)?

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
        var result: [String: String] = [:]
        let lock = NSLock()
        // 只查已启用 AI 对应的厂商（Codex 虽是本地数据源，但其服务状态 = OpenAI API 状态，同样有用）
        for (kind, url) in Self.endpoints where Settings.shared.isEnabled(kind) {
            group.enter()
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                guard let data,
                      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let status = root["status"] as? [String: Any],
                      let ind = status["indicator"] as? String else { return }
                lock.lock(); result[kind.title] = ind; lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            self?.onChange?(result)
        }
    }

    /// 一组指示级别里最严重的那个（critical > major > minor > none）。
    static func worst(of indicators: [String: String]) -> String? {
        let rank = ["critical": 3, "major": 2, "minor": 1]
        return indicators.values.max { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
            .flatMap { rank[$0] != nil ? $0 : nil }
    }
}
