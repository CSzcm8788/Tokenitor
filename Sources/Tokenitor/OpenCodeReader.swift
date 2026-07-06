import Foundation

/// 从 OpenCode 的本地 SQLite 库聚合「今日 token 用量」。
/// 库位置：~/.local/share/opencode/opencode.db（新版；老版为 storage/ 下 JSON，本机已迁库）。
/// message 表的 data 列是序列化的消息 JSON：assistant 消息含
///   tokens{input,output,reasoning,cache{read,write}}、cost(美元，OpenCode 自己算好)、time.created(毫秒)、modelID。
/// 成本直接采用 OpenCode 存好的 cost（连定价表里没有的模型如 DeepSeek 也准），不再自行估算。
enum OpenCodeReader {

    static func today() -> TokenStat? {
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db").path
        guard FileManager.default.fileExists(atPath: db) else { return nil }

        let startMs = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000
        // 在 SQL 层就过滤到「今日的 assistant 消息」：重度用户的 message 表可达数十万行，
        // 全表拉进内存再过滤是主要的性能热点。json_extract 不可用（老库）时退回全表扫描，
        // 下面的 Swift 侧过滤仍在，结果一致。
        let filtered = """
            SELECT data FROM message \
            WHERE json_extract(data,'$.role') = 'assistant' \
              AND (json_extract(data,'$.time.created') IS NULL \
                   OR json_extract(data,'$.time.created') >= \(Int64(startMs)))
            """
        guard let rows = queryJSON(db: db, sql: filtered)
                      ?? queryJSON(db: db, sql: "SELECT data FROM message") else { return nil }
        var byModel: [String: TokenCounts] = [:]
        var costByModel: [String: Double] = [:]
        var requests = 0
        var sessionIDs = Set<String>()
        var sampled = false

        for row in rows {
            autoreleasepool {   // 每行解析完及时归还临时对象（不改变结果）
                guard let dataStr = row["data"] as? String,
                      let blob = dataStr.data(using: .utf8),
                      let o = (try? JSONSerialization.jsonObject(with: blob)) as? [String: Any],
                      (o["role"] as? String) == "assistant" else { return }

                // 今日过滤：time.created（毫秒时间戳）；无时间戳则保留
                if let time = o["time"] as? [String: Any], let created = num(time["created"]), created < startMs {
                    return
                }

                let model = (o["modelID"] as? String) ?? "opencode"
                let t = o["tokens"] as? [String: Any] ?? [:]
                let cache = t["cache"] as? [String: Any] ?? [:]
                let c = TokenCounts(input: int(t["input"]),
                                    output: int(t["output"]) + int(t["reasoning"]),
                                    cacheRead: int(cache["read"]),
                                    cacheWrite: int(cache["write"]))
                if !c.isZero {
                    byModel[model, default: TokenCounts()] += c
                    requests += 1
                }
                if let cost = num(o["cost"]), cost > 0 { costByModel[model, default: 0] += cost }
                for key in ["sessionID", "sessionId", "session_id"] {
                    if let sid = o[key] as? String { sessionIDs.insert(sid); break }
                }

                if Settings.shared.debugDump && !sampled {
                    DebugLog.dumpJSON("token-opencode-sample", ["model": model, "tokens": t, "cost": o["cost"] ?? 0])
                    sampled = true
                }
            }
        }

        let models = byModel.filter { !$0.value.isZero }
        guard !models.isEmpty else { return nil }
        var total = TokenCounts(); var totalCost = 0.0; var list: [ModelTokens] = []
        for (m, c) in models {
            let cost = costByModel[m] ?? 0
            total += c; totalCost += cost
            list.append(ModelTokens(model: m, counts: c, cost: cost))
        }
        list.sort { $0.counts.total > $1.counts.total }

        var stat = TokenStat(tool: "OpenCode", today: total, todayCost: totalCost, byModel: list,
                              requests: requests, sessions: sessionIDs.count)
        // OpenCode 没有按小时的明细，Day 视图直接用今日总量当单柱展示。
        var day = PeriodReport()
        day.totalTokens = total.total
        day.inputTokens = total.input
        day.outputTokens = total.output
        day.cacheTokens = total.cacheRead + total.cacheWrite
        day.cost = totalCost
        day.requests = requests
        day.sessions = sessionIDs.count
        day.models = list
        day.series = [SeriesPoint(label: "今日", full: "今日", input: total.input,
                                   cache: total.cacheRead + total.cacheWrite, output: total.output)]
        stat.day = day
        return stat
    }

    // MARK: - 工具

    private static func int(_ v: Any?) -> Int {
        if let n = v as? Int { return n }
        if let n = v as? Double { return Int(n) }
        return 0
    }
    private static func num(_ v: Any?) -> Double? {
        if let n = v as? Double { return n }
        if let n = v as? Int { return Double(n) }
        return nil
    }

    /// 用系统 sqlite3 以 -json 模式查询（data 列含特殊字符，-json 输出可安全解析）。
    private static func queryJSON(db: String, sql: String) -> [[String: Any]]? {
        let task = Process()
        task.launchPath = "/usr/bin/sqlite3"
        task.arguments = ["-readonly", "-json", db, sql]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, !out.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: out)) as? [[String: Any]]
    }
}
