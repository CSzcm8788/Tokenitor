import Foundation

/// 解析 OpenAI Codex CLI 的本地会话文件，提取 5 小时窗口与周窗口用量。
///   位置: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
/// 每行是一个事件，token_count 事件里带 rate_limits：
///   { "rate_limits": { "primary": {used_percent, window_minutes, resets_in_seconds},
///                      "secondary": {...} } }
///   primary 一般是 5 小时窗口，secondary 是周窗口。
/// 同样做宽容解析：在最近修改的会话文件里，从文件尾部往前找最后一个含 rate_limits 的事件。
final class CodexProvider: UsageProvider {
    let displayName = "Codex"
    var enabled: Bool { Settings.shared.codexEnabled }

    private let sessionsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }()

    func fetch(completion: @escaping (ProviderSnapshot) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let snap = self.fetchSync()
            completion(snap)
        }
    }

    private func fetchSync() -> ProviderSnapshot {
        let fm = FileManager.default
        // 未安装/无近期会话 → 视为“未在使用”，界面隐藏
        guard fm.fileExists(atPath: sessionsDir.path) else { return .absent(displayName) }

        let files = recentSessionFiles(limit: 12)
        if files.isEmpty { return .absent(displayName) }

        for file in files {
            guard let text = tailString(of: file, maxBytes: 512 * 1024) else { continue }
            if let rl = lastRateLimits(in: text) {
                let windows = parse(rl)
                if !windows.isEmpty {
                    return ProviderSnapshot(name: displayName, windows: windows, ok: true, error: nil,
                                            plan: PlanTier.codexPlanFromAuthFile())
                }
            }
        }
        return .absent(displayName)   // 有会话但没 rate_limits，暂不显示
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

    /// 读取文件尾部最多 maxBytes 字节，返回字符串（保证从某个换行后开始）。
    private func tailString(of url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        var s = String(decoding: data, as: UTF8.self)
        // 若是从中间截断，丢掉第一段不完整行
        if start > 0, let nl = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: nl)...])
        }
        return s
    }

    /// 从文本（多行 JSON）里，从后往前找第一个含 rate_limits 的对象。
    private func lastRateLimits(in text: String) -> [String: Any]? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let rl = findRateLimits(obj) { return rl }
        }
        return nil
    }

    /// 递归查找名为 rate_limits / rateLimits 的字典。
    private func findRateLimits(_ obj: Any) -> [String: Any]? {
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
}
