import Foundation

/// 从本地会话文件聚合 Codex / Claude 的「今日 token 用量」并按模型估算成本，
/// 顺带统计今日请求数/会话数、按小时分桶的柱状图数据（Token 页 Day 视图）。
///
/// **增量解析**：进程内记住每个文件的字节偏移与今日累计贡献（`FileAgg`），
/// 每轮 tick 只解析上次之后新增的行——稳态时输入从 48h 全量（可达几十 MB）降到 KB 级，
/// 消除周期性内存峰值与 CPU 尖刺。日切 / 文件被截断 / 移出 48h 窗口时自动重置对应状态。
/// 解析做得很宽容（字段名兼容多种写法），数字不对时可开「调试转储」核对原始结构。
///
/// ⚠️ 增量状态是普通静态变量：`aggregate()` 只能在 AppDelegate 的 `tokenQueue`
///    串行队列上调用（现状如此），不要从别处并发调。
enum TokenAggregator {

    static func aggregate() -> [TokenStat] {
        var out: [TokenStat] = []
        if let c = codexToday() { out.append(c) }
        if let cl = claudeToday() { out.append(cl) }
        if let oc = OpenCodeReader.today() { out.append(oc) }   // OpenCode：读 opencode.db（含 cost）
        return out
    }

    // MARK: - 单行提取结果（一趟递归同时拿到三样，供单元测试直接验证）

    struct LineInfo {
        var usages: [[String: Any]] = []   // 键名为 usageKey 的字典们
        var timestamp: String?             // 首个 timestamp / ts 字符串
        var model: String?                 // 首个非空 model 字符串
    }

    /// 一趟递归收集 usage 字典、时间戳与模型名（此前是 3–4 趟独立递归，临时对象减半以上）。
    static func extract(_ obj: Any, usageKey: String, into info: inout LineInfo) {
        if let d = obj as? [String: Any] {
            if let u = d[usageKey] as? [String: Any] { info.usages.append(u) }
            if info.timestamp == nil {
                if let s = d["timestamp"] as? String { info.timestamp = s }
                else if let s = d["ts"] as? String { info.timestamp = s }
            }
            if info.model == nil, let m = d["model"] as? String, !m.isEmpty { info.model = m }
            for (_, v) in d { extract(v, usageKey: usageKey, into: &info) }
        } else if let a = obj as? [Any] {
            for v in a { extract(v, usageKey: usageKey, into: &info) }
        }
    }

    // MARK: - 增量状态（仅 tokenQueue 串行访问；进程内缓存，重启后首轮全量重建）

    /// 单文件的解析进度 + 它对「今日」的累计贡献。
    private struct FileAgg {
        var offset: UInt64 = 0
        var fileModel: String?                       // Codex：整会话一个模型
        var byModel: [String: TokenCounts] = [:]     // Claude：模型逐行
        var counts = TokenCounts()                   // Codex：文件级累计
        var hourly = [TokenCounts](repeating: TokenCounts(), count: TokenAggregator.hourBuckets)
        var requests = 0
    }

    private struct ToolState {
        var dayKey = ""
        var files: [String: FileAgg] = [:]
    }

    private static var codexState = ToolState()
    private static var claudeState = ToolState()

    // MARK: - Codex（~/.codex/sessions/**/*.jsonl，token_count 事件里的 last_token_usage 为每轮增量）

    private static func codexToday() -> TokenStat? {
        guard let files = recentFiles(in: home(".codex/sessions")) else {
            codexState.files.removeAll()
            return nil
        }
        advance(&codexState, files: files, usageKey: "last_token_usage",
                modelPerLine: false, sampleName: "token-codex-sample")

        var byModel: [String: TokenCounts] = [:]
        var hourly = [TokenCounts](repeating: TokenCounts(), count: hourBuckets)
        var requests = 0, sessions = 0
        for agg in codexState.files.values where agg.requests > 0 {
            byModel[agg.fileModel ?? "gpt-5-codex", default: TokenCounts()] += agg.counts
            for i in 0..<hourBuckets { hourly[i] += agg.hourly[i] }
            requests += agg.requests
            sessions += 1
        }
        return stat(tool: "Codex", byModel: byModel, hourly: hourly, requests: requests, sessions: sessions)
    }

    // MARK: - Claude（~/.claude/projects/**/*.jsonl，每条 assistant 消息的 message.usage）

    private static func claudeToday() -> TokenStat? {
        guard let files = recentFiles(in: home(".claude/projects")) else {
            claudeState.files.removeAll()
            return nil
        }
        advance(&claudeState, files: files, usageKey: "usage",
                modelPerLine: true, sampleName: "token-claude-sample")

        var byModel: [String: TokenCounts] = [:]
        var hourly = [TokenCounts](repeating: TokenCounts(), count: hourBuckets)
        var requests = 0, sessions = 0
        for agg in claudeState.files.values where agg.requests > 0 {
            for (m, c) in agg.byModel { byModel[m, default: TokenCounts()] += c }
            for i in 0..<hourBuckets { hourly[i] += agg.hourly[i] }
            requests += agg.requests
            sessions += 1
        }
        return stat(tool: "Claude", byModel: byModel, hourly: hourly, requests: requests, sessions: sessions)
    }

    /// 把一批文件的解析推进到各自的文件末尾（增量：从上次 offset 起只读新增部分）。
    private static func advance(_ state: inout ToolState, files: [URL], usageKey: String,
                                modelPerLine: Bool, sampleName: String) {
        let start = startOfToday()
        let key = dayKey(start)
        if state.dayKey != key {
            // 日切：昨天被计成「今日」的行要清零 → 丢掉全部状态，本轮全量重算
            state = ToolState(dayKey: key)
        }
        // 移出 48h 窗口的文件：其中已不可能有今日行，状态一并释放
        let live = Set(files.map(\.path))
        state.files = state.files.filter { live.contains($0.key) }

        var sampled = false
        for f in files {
            var agg = state.files[f.path] ?? FileAgg()
            if let size = fileSize(f), size < agg.offset { agg = FileAgg() }   // 截断/轮转 → 重来

            let newOffset = JSONLScanner.scan(url: f, from: agg.offset) { line in
                autoreleasepool {   // 每行一个池：单行 JSON 的对象图立即归还，压住内存水位
                    guard let obj = json(line) else { return }
                    var info = LineInfo()
                    extract(obj, usageKey: usageKey, into: &info)
                    // 会话模型先于「今日过滤」捕获：跨零点的文件其 meta 行可能在昨天
                    if agg.fileModel == nil, let m = info.model { agg.fileModel = m }

                    let ts = info.timestamp.flatMap(parseISO)
                    if let ts, ts < start { return }   // 无时间戳视为今天（文件已按近 2 天过滤）

                    var lineHadUsage = false
                    for u in info.usages {
                        guard let c = counts(from: u) else { continue }
                        if modelPerLine {
                            agg.byModel[info.model ?? "claude", default: TokenCounts()] += c
                        } else {
                            agg.counts += c
                        }
                        agg.hourly[hourBucket(ts)] += c
                        lineHadUsage = true
                        if Settings.shared.debugDump && !sampled {
                            DebugLog.dumpJSON(sampleName, u); sampled = true
                        }
                    }
                    if lineHadUsage { agg.requests += 1 }
                }
            }
            agg.offset = newOffset
            state.files[f.path] = agg
        }
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

    /// 时间戳落在的小时分桶（0...hourBuckets-1）；无时间戳按当前小时算。
    private static func hourBucket(_ date: Date?) -> Int {
        let hour = Calendar.current.component(.hour, from: date ?? Date())
        return min(hourBuckets - 1, max(0, hour / (24 / hourBuckets)))
    }

    private static func json(_ line: Substring) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8))
    }

    private static func fileSize(_ url: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64
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

    private static func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static func parseISO(_ s: String) -> Date? { isoFrac.date(from: s) ?? iso.date(from: s) }
}
