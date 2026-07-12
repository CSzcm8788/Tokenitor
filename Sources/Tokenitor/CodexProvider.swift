import Foundation

/// 解析 OpenAI Codex CLI 的本地会话文件，提取 5 小时窗口与周窗口用量。
///   位置: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
/// 每行是一个事件，token_count 事件里带 rate_limits：
///   { "rate_limits": { "primary": {used_percent, window_minutes, resets_at}, "secondary": {...},
///     "plan_type": "plus", ... } }
///
/// **增量读取**（v1.4.6）：每文件记住「扫描偏移 + 最后一次 rate_limits 及其事件时间」，
/// 每轮只扫新增字节。此前只看末尾 512KB——Codex 单行事件可达 3.5MB（长任务工具输出整段一行），
/// 巨行击穿窗口时读不到 rate_limits、回退到旧会话文件，造成「用量不准 + 十几分钟滞后」。
/// 增量流按完整行消费，巨行永远切不断；旧文件回退仅在最新文件从未出现过 rate_limits 时才发生。
final class CodexProvider: UsageProvider {
    let displayName = "Codex"
    var enabled: Bool { Settings.shared.codexEnabled }

    private let sessionsDir: URL

    /// 默认读 ~/.codex/sessions；目录可注入，单元测试用临时目录端到端验证增量语义。
    init(sessionsDir: URL? = nil) {
        self.sessionsDir = sessionsDir
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// 单文件增量状态。仅在下方专用串行队列上访问。
    private struct FileState {
        var offset: UInt64 = 0
        var lastRL: [String: Any]? = nil   // 最后一次 rate_limits 字典
        var lastTs: Date? = nil            // 该事件自身的时间戳（数据时间）
        var didWiden = false               // 首轮尾窗未命中时的一次性扩窗标记
    }
    private var states: [String: FileState] = [:]
    private let queue = DispatchQueue(label: "tokenitor.codex", qos: .utility)

    /// 首轮从尾部 4MB 起步（容纳实测 3.5MB 的单行巨事件 + 余量）；未命中再一次性扩到 32MB。
    private static let initialTail: UInt64 = 4 * 1024 * 1024
    private static let widenTail: UInt64 = 32 * 1024 * 1024

    func fetch(completion: @escaping (ProviderSnapshot) -> Void) {
        queue.async {
            completion(self.fetchOnQueue())
        }
    }

    private func fetchOnQueue() -> ProviderSnapshot {
        let fm = FileManager.default
        // 未安装/无近期会话 → 视为“未在使用”，界面隐藏
        guard fm.fileExists(atPath: sessionsDir.path) else { states.removeAll(); return .absent(displayName) }
        let files = recentSessionFiles(limit: 12)
        if files.isEmpty { states.removeAll(); return .absent(displayName) }

        // 移出窗口的文件释放状态
        let live = Set(files.map(\.path))
        states = states.filter { live.contains($0.key) }

        for f in files { advance(f) }   // 增量推进（稳态下只有活跃文件有新增字节）

        // 取「事件时间最新」的 rate_limits（天然优先活跃会话；旧文件只在新文件从无事件时兜底）
        let best = states.values
            .compactMap { s in s.lastRL.map { (ts: s.lastTs ?? .distantPast, rl: $0) } }
            .max { $0.ts < $1.ts }
        guard let best else { return .absent(displayName) }   // 有会话但还没出现过 rate_limits

        let windows = parse(best.rl)
        guard !windows.isEmpty else { return .absent(displayName) }
        // 档位主源：rate_limits.plan_type（与实际配额同源）；读不到退回 auth.json 的 JWT claim
        let plan = PlanTier.codex(best.rl["plan_type"] as? String)
            ?? PlanTier.codexPlanFromAuthFile()
        return ProviderSnapshot(name: displayName, windows: windows, ok: true, error: nil,
                                plan: plan,
                                dataAsOf: best.ts == .distantPast ? nil : best.ts)
    }

    /// 把单个文件的解析推进到末尾；首见文件从尾部 initialTail 起步，未命中一次性扩窗重扫。
    private func advance(_ url: URL) {
        let size = fileSize(url) ?? 0
        var st = states[url.path] ?? FileState(offset: size > Self.initialTail ? size - Self.initialTail : 0)
        if size < st.offset { st = FileState(offset: 0) }   // 截断/轮转 → 全量重来

        st.offset = scanForRateLimits(url: url, from: st.offset, into: &st)

        // 首轮尾窗（4MB）没找到且文件更大 → 扩到 32MB 再扫一次（只此一次，避免反复读大文件）
        if st.lastRL == nil, !st.didWiden {
            st.didWiden = true
            let initialStart = size > Self.initialTail ? size - Self.initialTail : 0
            let widerStart = size > Self.widenTail ? size - Self.widenTail : 0
            if widerStart < initialStart {
                _ = scanForRateLimits(url: url, from: widerStart, into: &st)
            }
        }
        states[url.path] = st
    }

    /// 流式扫描 [from, EOF)，更新 st 的 lastRL/lastTs；返回新偏移。
    /// `contains("rate_limits")` 预筛让 3.5MB 的工具输出巨行直接跳过 JSON 解析（CPU/内存零负担）。
    private func scanForRateLimits(url: URL, from: UInt64, into st: inout FileState) -> UInt64 {
        var found: ([String: Any], Date?)? = nil
        let newOffset = JSONLScanner.scan(url: url, from: from) { line in
            guard line.contains("rate_limits") else { return }
            autoreleasepool {
                if let hit = Self.parseRateLimitsLine(line) { found = hit }
            }
        }
        if let (rl, ts) = found {
            st.lastRL = rl
            st.lastTs = ts ?? Date()
        }
        return newOffset
    }

    /// 解析单行：返回 (rate_limits 字典, 该行事件时间戳)；不含 rate_limits 的行返回 nil。
    /// internal 供单元测试直接验证（巨行截断垃圾、正常事件行等场景）。
    static func parseRateLimitsLine(_ line: Substring) -> ([String: Any], Date?)? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let rl = findRateLimits(obj) else { return nil }
        let dict = obj as? [String: Any]
        let ts = (dict?["timestamp"] as? String) ?? (dict?["ts"] as? String)
        return (rl, ts.flatMap(parseISO))
    }

    /// 取最近修改、且在 8 天内的 .jsonl 会话文件，按修改时间倒序。
    private func recentSessionFiles(limit: Int) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: sessionsDir,
                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        let cutoff = Date().addingTimeInterval(-8 * 24 * 3600)
        var items: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let mod = vals?.contentModificationDate ?? .distantPast
            if mod >= cutoff { items.append((url, mod)) }
        }
        return items.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    private func fileSize(_ url: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64
    }

    /// 递归查找名为 rate_limits / rateLimits 的字典。
    private static func findRateLimits(_ obj: Any) -> [String: Any]? {
        if let dict = obj as? [String: Any] {
            for key in ["rate_limits", "rateLimits"] {
                if let rl = dict[key] as? [String: Any] { return rl }
            }
            for (_, v) in dict {
                if let r = findRateLimits(v) { return r }
            }
        } else if let arr = obj as? [Any] {
            for v in arr {
                if let r = findRateLimits(v) { return r }
            }
        }
        return nil
    }

    /// 把 rate_limits 里的 primary/secondary 转成窗口。
    private func parse(_ rl: [String: Any]) -> [UsageWindow] {
        var out: [UsageWindow] = []

        func makeWindow(_ obj: Any?, fallbackLabel: String) -> UsageWindow? {
            guard let dict = obj as? [String: Any],
                  let used = JSON.extractPercent(dict) else { return nil }
            let reset = JSON.extractReset(dict)
            // 用 window_minutes 判定是 5h 还是周
            var label = fallbackLabel
            if let mins = JSON.double(JSON.firstValue(in: dict, keys: ["window_minutes", "windowMinutes"])) {
                label = mins <= 360 ? "5h" : "weekly"
            }
            return UsageWindow(usedPercent: used, resetsAt: reset, label: label)
        }

        if let w = makeWindow(rl["primary"], fallbackLabel: "5h") { out.append(w) }
        if let w = makeWindow(rl["secondary"], fallbackLabel: "weekly") { out.append(w) }

        // 兜底：若没有 primary/secondary，扫描所有窗口对象
        if out.isEmpty {
            for (key, dict) in JSON.findWindowObjects(rl) {
                guard let used = JSON.extractPercent(dict) else { continue }
                out.append(UsageWindow(usedPercent: used,
                                       resetsAt: JSON.extractReset(dict),
                                       label: key.isEmpty ? "usage" : key))
            }
        }
        return out
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static func parseISO(_ s: String) -> Date? { isoFrac.date(from: s) ?? iso.date(from: s) }
}
