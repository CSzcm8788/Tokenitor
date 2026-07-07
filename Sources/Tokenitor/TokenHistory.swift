import Foundation

/// 一个工具在某一天的完整快照：按模型拆分的 token 量与成本、请求/会话数。
struct DaySnapshot: Codable, Equatable {
    var byModel: [String: TokenCounts] = [:]
    var costByModel: [String: Double] = [:]
    var requests: Int = 0
    var sessions: Int = 0

    var cost: Double { costByModel.values.reduce(0, +) }
    var total: Int { byModel.values.reduce(0) { $0 + $1.total } }
}

/// 每日各工具的完整用量落盘到 ~/.tokenitor/token-history.json，供 Week/Month 周期汇总与涨跌对比使用。
/// 结构：{ "yyyy-MM-dd": { "Codex": DaySnapshot, "Claude": DaySnapshot } }
/// Day 周期不走这里——粒度到小时的数据由 TokenAggregator 实时给出（见 AppDelegate.refreshTokens）。
final class TokenHistory {
    static let shared = TokenHistory()

    private let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".tokenitor/token-history.json")
    private var data: [String: [String: DaySnapshot]] = [:]
    private var loaded = false
    private let lock = NSLock()
    /// Month 视图（30 天）算涨跌需要再往前多留 30 天做「上一周期」对比，留够 70 天余量。
    private static let retentionDays = 70

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let d = try? Data(contentsOf: url) else { return }
        // 老格式是 [String: [String: Int]]（只有总量）；解码失败就当空历史，不 crash。
        if let obj = try? JSONDecoder().decode([String: [String: DaySnapshot]].self, from: d) {
            data = obj
        }
    }

    /// 记录今天各工具的完整快照（覆盖今天），裁剪到最近 retentionDays 天。
    func record(_ stats: [TokenStat]) {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        let key = Self.dayKey(Date())
        var today = data[key] ?? [:]
        for s in stats {
            var byModel: [String: TokenCounts] = [:]
            var costByModel: [String: Double] = [:]
            for m in s.byModel { byModel[m.model] = m.counts; costByModel[m.model] = m.cost }
            today[s.tool] = DaySnapshot(byModel: byModel, costByModel: costByModel,
                                         requests: s.requests, sessions: s.sessions)
        }
        data[key] = today
        let keys = data.keys.sorted()
        if keys.count > Self.retentionDays {
            for k in keys.prefix(keys.count - Self.retentionDays) { data.removeValue(forKey: k) }
        }
        save()
    }

    /// 某工具最近 days 天的每日快照（缺失日补空快照），最早 → 最近。
    private func snapshots(tool: String, days: Int) -> [(date: Date, snap: DaySnapshot)] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return Self.dates(days: days).map { d in
            (d, data[Self.dayKey(d)]?[tool] ?? DaySnapshot())
        }
    }

    /// 紧邻在当前周期之前、同样长度的周期快照（涨跌对比基准）。
    private func priorSnapshots(tool: String, days: Int) -> [(date: Date, snap: DaySnapshot)] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        let cal = Calendar.current
        guard let anchor = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        return Self.dates(days: days, referenceDate: anchor).map { d in
            (d, data[Self.dayKey(d)]?[tool] ?? DaySnapshot())
        }
    }

    /// 周期汇总：days<=10 按每日出柱，否则按周分桶（Month 视图）。
    func report(tool: String, days: Int) -> PeriodReport {
        Self.rollup(snapshots(tool: tool, days: days),
                    groupByWeek: days > 10,
                    previous: priorSnapshots(tool: tool, days: days))
    }

    // MARK: - roll-up

    private static func rollup(_ pts: [(date: Date, snap: DaySnapshot)], groupByWeek: Bool,
                                previous: [(date: Date, snap: DaySnapshot)]) -> PeriodReport {
        var report = PeriodReport()

        var modelCounts: [String: TokenCounts] = [:]
        var modelCost: [String: Double] = [:]
        for (_, snap) in pts {
            for (m, c) in snap.byModel { modelCounts[m, default: TokenCounts()] += c }
            for (m, c) in snap.costByModel { modelCost[m, default: 0] += c }
            report.requests += snap.requests
            report.sessions += snap.sessions
        }

        var total = TokenCounts()
        var models: [ModelTokens] = []
        for (m, c) in modelCounts where !c.isZero {
            total += c
            models.append(ModelTokens(model: m, counts: c, cost: modelCost[m] ?? 0))
        }
        models.sort { $0.counts.total > $1.counts.total }
        report.models = models
        report.totalTokens = total.total
        report.inputTokens = total.input
        report.outputTokens = total.output
        report.cacheTokens = total.cacheRead + total.cacheWrite
        report.cost = modelCost.values.reduce(0, +)

        if groupByWeek {
            let buckets = weeklyBuckets(pts)
            report.series = buckets.map { $0.point }
            report.reqTrend = buckets.map { Double($0.requests) }
            report.costTrend = buckets.map { $0.cost }
        } else {
            let df = DateFormatter(); df.dateFormat = "EEE"
            let ff = DateFormatter(); ff.dateFormat = "MMM d"
            report.series = pts.map { d, s in
                SeriesPoint(label: df.string(from: d), full: ff.string(from: d),
                            input: s.byModel.values.reduce(0) { $0 + $1.input },
                            cache: s.byModel.values.reduce(0) { $0 + $1.cacheRead + $1.cacheWrite },
                            output: s.byModel.values.reduce(0) { $0 + $1.output })
            }
            report.reqTrend = pts.map { Double($0.snap.requests) }
            report.costTrend = pts.map { $0.snap.cost }
        }

        let prevTotal = previous.reduce(0) { $0 + $1.snap.total }
        let prevCost = previous.reduce(0.0) { $0 + $1.snap.cost }
        report.hasPrior = prevTotal > 0 || prevCost > 0   // 上一周期空 → 环比不展示
        report.deltaTokens = percentDelta(cur: Double(report.totalTokens), prev: Double(prevTotal))
        report.deltaCost = percentDelta(cur: report.cost, prev: prevCost)
        return report
    }

    /// 按 7 天一组分桶（Month 视图），标签 W1..Wn，悬浮提示为日期范围。
    private static func weeklyBuckets(_ pts: [(date: Date, snap: DaySnapshot)]) -> [(point: SeriesPoint, requests: Int, cost: Double)] {
        guard !pts.isEmpty else { return [] }
        let df = DateFormatter(); df.dateFormat = "MMM d"
        var out: [(SeriesPoint, Int, Double)] = []
        var idx = 0, week = 1
        while idx < pts.count {
            let chunk = pts[idx..<min(idx + 7, pts.count)]
            var input = 0, cache = 0, output = 0, requests = 0
            var cost = 0.0
            for (_, s) in chunk {
                for c in s.byModel.values { input += c.input; cache += c.cacheRead + c.cacheWrite; output += c.output }
                requests += s.requests
                cost += s.cost
            }
            let first = chunk.first!.date, last = chunk.last!.date
            out.append((SeriesPoint(label: "W\(week)", full: "\(df.string(from: first)) – \(df.string(from: last))",
                                     input: input, cache: cache, output: output), requests, cost))
            idx += 7; week += 1
        }
        return out
    }

    private static func percentDelta(cur: Double, prev: Double) -> Double {
        guard prev > 0 else { return cur > 0 ? 100 : 0 }
        return ((cur - prev) / prev) * 100
    }

    private func save() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url) }
    }

    /// 最近 days 天的日期序列，最早 → 最近。referenceDate 为 nil 时以「今天」为终点。
    private static func dates(days: Int, referenceDate: Date? = nil) -> [Date] {
        let cal = Calendar.current
        let end = referenceDate ?? Date()
        var out: [Date] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -i, to: end) else { continue }
            out.append(d)
        }
        return out
    }

    private static func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
