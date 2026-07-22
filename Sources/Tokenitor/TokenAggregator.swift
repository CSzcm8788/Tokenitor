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
        if let g = geminiTodayTokens() { out.append(g) }
        if let gr = grokToday() { out.append(gr) }
        if let oc = OpenCodeReader.today() { out.append(oc) }   // OpenCode：读 opencode.db（含 cost）
        return out
    }

    // MARK: - 单行提取结果（一趟递归同时拿到三样，供单元测试直接验证）

    struct LineInfo {
        var usages: [[String: Any]] = []   // 键名为 usageKey 的字典们
        var timestamp: String?             // 首个 timestamp / ts 字符串
        var model: String?                 // 首个非空 model 字符串
    }

    /// 「当前模型」延续解析：本行带 model 就切换 `current`（Codex 的 model 来自
    /// thread_settings_applied 事件、随后的 token_count 事件不带 model，需延续；Claude 每条
    /// 消息都自带 model）；不带 model 的行沿用上次值。跨零点也照常延续。internal 供测试。
    static func resolveModel(_ info: LineInfo, current: inout String?, default def: String) -> String {
        if let m = info.model { current = m }
        return current ?? def
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
        var byModel: [String: TokenCounts] = [:]     // 按模型累计（Claude 同行 / Codex 延续）
        var currentModel: String?                    // 「当前模型」：跨行、跨增量轮延续
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
        // Codex 的 model 由 thread_settings_applied 事件设定、随后的 token_count 事件不带 model，
        // 且一个会话可中途切换模型（如 gpt-5.5 → gpt-5.6-sol）。故按「当前模型」延续归因，
        // 而非整文件取第一个模型（那会把切换后的用量全记到旧模型上）。
        advance(&codexState, files: files, usageKey: "last_token_usage",
                defaultModel: "gpt-5-codex", sampleName: "token-codex-sample")

        return collect(codexState, tool: "Codex")
    }

    // MARK: - Claude（~/.claude/projects/**/*.jsonl，每条 assistant 消息的 message.usage）

    private static func claudeToday() -> TokenStat? {
        guard let files = recentFiles(in: home(".claude/projects")) else {
            claudeState.files.removeAll()
            return nil
        }
        advance(&claudeState, files: files, usageKey: "usage",
                defaultModel: "claude", sampleName: "token-claude-sample")

        return collect(claudeState, tool: "Claude")
    }

    // MARK: - Gemini（~/.gemini/tmp/**/chats/*.jsonl，消息内嵌 tokens{input,output,cached,thoughts}）

    private static var geminiState = ToolState()

    private static func geminiTodayTokens() -> TokenStat? {
        guard let files = recentFiles(in: home(".gemini/tmp")) else {
            geminiState.files.removeAll()
            return nil
        }
        advance(&geminiState, files: files, usageKey: "tokens",
                defaultModel: "gemini", sampleName: "token-gemini-sample",
                mapper: geminiCounts(from:))
        return collect(geminiState, tool: "Gemini")
    }

    // MARK: - Grok（~/.grok/logs/unified.jsonl，shell.turn.inference_done 的 ctx 带 token 四项）

    private static var grokState = ToolState()

    private static func grokToday() -> TokenStat? {
        guard let files = recentFiles(in: home(".grok/logs")) else {
            grokState.files.removeAll()
            return nil
        }
        // 事件不带模型名；当前模型读 models_cache.json 的 current_model_id（Grok Build 单模型目录）
        let model = grokCurrentModel() ?? "grok"
        advance(&grokState, files: files, usageKey: "ctx",
                defaultModel: model, sampleName: "token-grok-sample",
                mapper: grokCounts(from:))
        return collect(grokState, tool: "Grok")
    }

    static func grokCurrentModel() -> String? {
        let url = home(".grok/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let m = obj["current_model_id"] as? String, !m.isEmpty { return m }
        // 兜底：models 字典只有一个键时就是当前模型
        if let models = obj["models"] as? [String: Any], models.count == 1 { return models.keys.first }
        return nil
    }

    /// 汇总一个工具的全部文件状态 → TokenStat（Codex/Claude/Gemini/Grok 同构收口）。
    private static func collect(_ state: ToolState, tool: String) -> TokenStat? {
        var byModel: [String: TokenCounts] = [:]
        var hourly = [TokenCounts](repeating: TokenCounts(), count: hourBuckets)
        var requests = 0, sessions = 0
        for agg in state.files.values where agg.requests > 0 {
            for (m, c) in agg.byModel { byModel[m, default: TokenCounts()] += c }
            for i in 0..<hourBuckets { hourly[i] += agg.hourly[i] }
            requests += agg.requests
            sessions += 1
        }
        return stat(tool: tool, byModel: byModel, hourly: hourly, requests: requests, sessions: sessions)
    }

    /// 把一批文件的解析推进到各自的文件末尾（增量：从上次 offset 起只读新增部分）。
    private static func advance(_ state: inout ToolState, files: [URL], usageKey: String,
                                defaultModel: String, sampleName: String,
                                mapper: ([String: Any]) -> TokenCounts? = TokenAggregator.counts(from:)) {
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
            let firstSight = state.files[f.path] == nil
            var agg = state.files[f.path] ?? FileAgg()
            let size = fileSize(f) ?? 0
            if size < agg.offset { agg = FileAgg() }   // 截断/轮转 → 重来

            // 首次遇到超大文件（如被续写数周、达数百 MB 的 Codex 长会话）：今日的行只可能在
            // 文件末尾，没必要读完整个历史。从尾部预算内起扫——首扫内存峰值与磁盘 I/O 都随之
            // 从「整文件」降到「尾部预算」。落在行中间的首个残行会解析失败被跳过，无副作用；
            // 极端情况下若今日数据超过预算（单会话一天写 >64MB 近乎不可能），最早一段可能少计。
            if firstSight && agg.offset == 0 && size > Self.tailBudget {
                agg.offset = size - Self.tailBudget   // 仅当 size > 预算才回退（防 UInt64 下溢）
            }

            let newOffset = JSONLScanner.scan(url: f, from: agg.offset) { line in
                // 预筛：只有含 token 用量（usageKey）或模型声明（Codex 的 thread_settings_applied）
                // 的行才值得 JSON 解析。Codex 会话里 3.5MB 的工具输出巨行两者都不含——直接跳过，
                // 首扫 526MB 巨型会话时内存峰值从 ~1.2GB 断崖下降（对照配额侧 1.4.6 同款手法）。
                guard line.contains(usageKey) || line.contains("thread_settings") else { return }
                autoreleasepool {   // 每行一个池：单行 JSON 的对象图立即归还，压住内存水位
                    guard let obj = json(line) else { return }
                    var info = LineInfo()
                    extract(obj, usageKey: usageKey, into: &info)
                    let model = resolveModel(info, current: &agg.currentModel, default: defaultModel)

                    let ts = info.timestamp.flatMap(parseISO)
                    if let ts, ts < start { return }   // 无时间戳视为今天（文件已按近 2 天过滤）

                    var lineHadUsage = false
                    for u in info.usages {
                        guard let c = mapper(u) else { continue }
                        agg.byModel[model, default: TokenCounts()] += c
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
    /// 超大文件首扫的尾部起扫预算：文件超过它就只读末尾这么多——今日行必在尾部。
    private static let tailBudget: UInt64 = 64 * 1024 * 1024         // 64MB（覆盖一天极重用量绰绰有余）
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
    private static func intVal(_ d: [String: Any], _ keys: [String]) -> Int {
        for k in keys {
            if let n = d[k] as? Int { return n }
            if let n = d[k] as? Double { return Int(n) }
        }
        return 0
    }

    /// Codex / Claude 的 usage 映射：input 不含缓存（实测 total=input+output 成立），
    /// output 已含 reasoning（此前误把 reasoning_output_tokens 再加一遍 → 输出虚高，已修正）。
    static func counts(from d: [String: Any]) -> TokenCounts? {
        let c = TokenCounts(input: intVal(d, ["input_tokens", "prompt_tokens", "input"]),
                            output: intVal(d, ["output_tokens", "completion_tokens", "output"]),
                            cacheRead: intVal(d, ["cache_read_input_tokens", "cached_input_tokens", "cache_read"]),
                            cacheWrite: intVal(d, ["cache_creation_input_tokens", "cache_write"]))
        return c.isZero ? nil : c
    }

    /// Gemini 的 tokens 映射：`input` **含** cached（需扣除避免重复计入）；`thoughts`（推理）
    /// 独立于 output（实测 total=input+output+thoughts+tool 成立），按输出计价并入 output。
    static func geminiCounts(from d: [String: Any]) -> TokenCounts? {
        let cached = intVal(d, ["cached"])
        let c = TokenCounts(input: max(0, intVal(d, ["input"]) - cached),
                            output: intVal(d, ["output"]) + intVal(d, ["thoughts"]),
                            cacheRead: cached, cacheWrite: 0)
        return c.isZero ? nil : c
    }

    /// Grok 的 ctx 映射：`prompt_tokens` **含** cached_prompt_tokens（扣除）；
    /// completion_tokens 按 OpenAI 风格已含 reasoning_tokens（不再加）。
    static func grokCounts(from d: [String: Any]) -> TokenCounts? {
        let cached = intVal(d, ["cached_prompt_tokens"])
        guard d["prompt_tokens"] != nil || d["completion_tokens"] != nil else { return nil }
        let c = TokenCounts(input: max(0, intVal(d, ["prompt_tokens"]) - cached),
                            output: intVal(d, ["completion_tokens"]),
                            cacheRead: cached, cacheWrite: 0)
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
