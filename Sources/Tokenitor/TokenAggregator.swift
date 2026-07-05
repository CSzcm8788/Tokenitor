import Foundation

/// 从本地会话文件聚合 Codex / Claude 的「今日 token 用量」并按模型估算成本，
/// 顺带统计今日请求数/会话数、按小时分桶的柱状图数据（Token 页 Day 视图）。
/// 解析做得很宽容（字段名兼容多种写法），数字不对时可开「调试转储」核对原始结构。
enum TokenAggregator {

    static func aggregate() -> [TokenStat] {
        var out: [TokenStat] = []
        if let c = codexToday() { out.append(c) }
        if let cl = claudeToday() { out.append(cl) }
        if let oc = OpenCodeReader.today() { out.append(oc) }   // OpenCode：读 opencode.db（含 cost）
        return out
    }

    // MARK: - Codex（~/.codex/sessions/**/*.jsonl，token_count 事件里的 last_token_usage 为每轮增量）

    private static func codexToday() -> TokenStat? {
        let dir = home(".codex/sessions")
        guard let files = recentFiles(in: dir) else { return nil }
        var byModel: [String: TokenCounts] = [:]
        var hourly = [TokenCounts](repeating: TokenCounts(), count: hourBuckets)
        var requests = 0
        var sessionFiles = Set<String>()
        let start = startOfToday()
        var sampled = false

        for f in files {
            autoreleasepool {   // 每文件处理完及时归还临时对象，压低堆峰值/碎片（不改变结果）
                guard let text = try? String(contentsOf: f, encoding: .utf8) else { return }
                // 该会话的模型（取文件里出现的第一个 model 字段）
                let model = firstString(inLines: text, key: "model") ?? "gpt-5-codex"
                for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let obj = json(line) else { continue }
                    if !lineIsToday(obj, start: start) { continue }

                    var deltas: [[String: Any]] = []
                    collectDicts(obj, key: "last_token_usage", into: &deltas)
                    var lineHadUsage = false
                    for d in deltas {
                        if let c = counts(from: d) {
                            byModel[model, default: TokenCounts()] += c
                            hourly[hourBucket(obj)] += c
                            lineHadUsage = true
                            if Settings.shared.debugDump && !sampled { DebugLog.dumpJSON("token-codex-sample", d); sampled = true }
                        }
                    }
                    if lineHadUsage { requests += 1; sessionFiles.insert(f.path) }
                }
            }
        }
        return stat(tool: "Codex", byModel: byModel, hourly: hourly, requests: requests, sessions: sessionFiles.count)
    }

    // MARK: - Claude（~/.claude/projects/**/*.jsonl，每条 assistant 消息的 message.usage）

    private static func claudeToday() -> TokenStat? {
        let dir = home(".claude/projects")
        guard let files = recentFiles(in: dir) else { return nil }
        var byModel: [String: TokenCounts] = [:]
        var hourly = [TokenCounts](repeating: TokenCounts(), count: hourBuckets)
        var requests = 0
        var sessionFiles = Set<String>()
        let start = startOfToday()
        var sampled = false

        for f in files {
            autoreleasepool {   // 每文件处理完及时归还临时对象，压低堆峰值/碎片（不改变结果）
                guard let text = try? String(contentsOf: f, encoding: .utf8) else { return }
                for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let obj = json(line) else { continue }
                    if !lineIsToday(obj, start: start) { continue }

                    var usages: [[String: Any]] = []
                    collectDicts(obj, key: "usage", into: &usages)
                    let model = firstString(inObject: obj, key: "model") ?? "claude"
                    var lineHadUsage = false
                    for u in usages {
                        if let c = counts(from: u) {
                            byModel[model, default: TokenCounts()] += c
                            hourly[hourBucket(obj)] += c
                            lineHadUsage = true
                            if Settings.shared.debugDump && !sampled { DebugLog.dumpJSON("token-claude-sample", u); sampled = true }
                        }
                    }
                    if lineHadUsage { requests += 1; sessionFiles.insert(f.path) }
                }
            }
        }
        return stat(tool: "Claude", byModel: byModel, hourly: hourly, requests: requests, sessions: sessionFiles.count)
    }

    // MARK: - 组装

    private static let hourBuckets = 6   // 4 小时一档，覆盖全天 24 小时
    private static let hourBucketLabels = ["0-4", "4-8", "8-12", "12-16", "16-20", "20-24"]

    private static func stat(tool: String, byModel: [String: TokenCounts],
                              hourly: [TokenCounts], requests: Int, sessions: Int) -> TokenStat? {
        let models = byModel.filter { !$0.value.isZero }
        guard !models.isEmpty else { return nil }
        var total = TokenCounts()
        var totalCost = 0.0
        var list: [ModelTokens] = []
        for (m, c) in models {
            let cost = Pricing.cost(c, model: m)
            total += c; totalCost += cost
            list.append(ModelTokens(model: m, counts: c, cost: cost))
        }
        list.sort { $0.counts.total > $1.counts.total }

        var out = TokenStat(tool: tool, today: total, todayCost: totalCost, byModel: list,
                             requests: requests, sessions: sessions)

        // Day 周期：直接用今天已聚合的数据 + 按小时分桶的柱状图。
        // Week/Month 由 TokenHistory 在落盘后于 AppDelegate 里补齐（那边能看到跨天历史）。
        var day = PeriodReport()
        day.totalTokens = total.total
        day.inputTokens = total.input
        day.outputTokens = total.output
        day.cacheTokens = total.cacheRead + total.cacheWrite
        day.cost = totalCost
        day.requests = requests
        day.sessions = sessions
        day.models = list
        day.series = hourly.enumerated().map { i, c in
            SeriesPoint(label: hourBucketLabels[i], full: "\(hourBucketLabels[i])点",
                        input: c.input, cache: c.cacheRead + c.cacheWrite, output: c.output)
        }
        out.day = day
        return out
    }

    // MARK: - 宽容解析工具

    /// 兼容多种字段名提取一组 token 计数。
    private static func counts(from d: [String: Any]) -> TokenCounts? {
        func i(_ keys: [String]) -> Int {
            for k in keys {
                if let n = d[k] as? Int { return n }
                if let n = d[k] as? Double { return Int(n) }
            }
            return 0
        }
        let input  = i(["input_tokens", "prompt_tokens", "input"])
        let output = i(["output_tokens", "completion_tokens", "output"]) + i(["reasoning_output_tokens"])
        let cRead  = i(["cache_read_input_tokens", "cached_input_tokens", "cache_read"])
        let cWrite = i(["cache_creation_input_tokens", "cache_write"])
        let c = TokenCounts(input: input, output: output, cacheRead: cRead, cacheWrite: cWrite)
        return c.isZero ? nil : c
    }

    /// 递归收集所有「键名为 key 的字典」。
    private static func collectDicts(_ obj: Any, key: String, into out: inout [[String: Any]]) {
        if let d = obj as? [String: Any] {
            if let v = d[key] as? [String: Any] { out.append(v) }
            for (_, vv) in d { collectDicts(vv, key: key, into: &out) }
        } else if let a = obj as? [Any] {
            for vv in a { collectDicts(vv, key: key, into: &out) }
        }
    }

    private static func firstString(inObject obj: Any, key: String) -> String? {
        if let d = obj as? [String: Any] {
            if let s = d[key] as? String, !s.isEmpty { return s }
            for (_, vv) in d { if let r = firstString(inObject: vv, key: key) { return r } }
        } else if let a = obj as? [Any] {
            for vv in a { if let r = firstString(inObject: vv, key: key) { return r } }
        }
        return nil
    }

    private static func firstString(inLines text: String, key: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(50) {
            if let obj = json(line), let s = firstString(inObject: obj, key: key) { return s }
        }
        return nil
    }

    /// 行是否属于今天：有时间戳就按时间戳判断，无则视为今天（文件已按近 2 天过滤）。
    private static func lineIsToday(_ obj: Any, start: Date) -> Bool {
        guard let ts = firstString(inObject: obj, key: "timestamp") ?? firstString(inObject: obj, key: "ts"),
              let d = parseISO(ts) else { return true }
        return d >= start
    }

    /// 该行时间戳落在的小时分桶（0...hourBuckets-1）；无时间戳按当前小时算。
    private static func hourBucket(_ obj: Any) -> Int {
        let hour: Int
        if let ts = firstString(inObject: obj, key: "timestamp") ?? firstString(inObject: obj, key: "ts"),
           let d = parseISO(ts) {
            hour = Calendar.current.component(.hour, from: d)
        } else {
            hour = Calendar.current.component(.hour, from: Date())
        }
        return min(hourBuckets - 1, max(0, hour / (24 / hourBuckets)))
    }

    private static func json(_ line: Substring) -> Any? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func recentFiles(in dir: URL, withinHours: Double = 48) -> [URL]? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path),
              let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles]) else { return nil }
        let cutoff = Date().addingTimeInterval(-withinHours * 3600)
        var files: [URL] = []
        for case let u as URL in en where u.pathExtension == "jsonl" {
            let mod = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mod >= cutoff { files.append(u) }
        }
        return files.isEmpty ? nil : files
    }

    private static func startOfToday() -> Date { Calendar.current.startOfDay(for: Date()) }
    private static func home(_ p: String) -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(p) }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static func parseISO(_ s: String) -> Date? { isoFrac.date(from: s) ?? iso.date(from: s) }
}
