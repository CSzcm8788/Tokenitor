import Foundation

/// 针对“未公开 / 易变”接口的宽容 JSON 工具。
/// 这些端点字段名可能随时变化，所以不用 Codable，而是递归扫描。
enum JSON {

    /// 把任意值转成 Double（支持 NSNumber / String）。
    static func double(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// 解析 ISO8601 时间戳（带或不带毫秒），也兼容 epoch 秒。
    static func date(_ any: Any?) -> Date? {
        if let n = any as? NSNumber {
            // 可能是 epoch 秒或毫秒
            let v = n.doubleValue
            if v > 1_000_000_000_000 { return Date(timeIntervalSince1970: v / 1000) }
            if v > 1_000_000_000 { return Date(timeIntervalSince1970: v) }
            return nil
        }
        guard let s = any as? String else { return nil }
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFull.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        return nil
    }

    /// 在嵌套结构里按一组候选键查找第一个匹配的值。
    static func firstValue(in obj: Any?, keys: [String]) -> Any? {
        guard let dict = obj as? [String: Any] else { return nil }
        for k in dict.keys {
            let lower = k.lowercased()
            for cand in keys where lower == cand.lowercased() {
                return dict[k]
            }
        }
        return nil
    }

    /// 递归查找所有“看起来像用量窗口”的对象：含有 used/utilization 百分比字段。
    /// 返回 (字段所属键名, 该对象字典)。
    static func findWindowObjects(_ obj: Any?, parentKey: String = "") -> [(key: String, dict: [String: Any])] {
        var out: [(String, [String: Any])] = []
        if let dict = obj as? [String: Any] {
            if extractPercent(dict) != nil {
                out.append((parentKey, dict))
            }
            for (k, v) in dict {
                out.append(contentsOf: findWindowObjects(v, parentKey: k))
            }
        } else if let arr = obj as? [Any] {
            for v in arr {
                out.append(contentsOf: findWindowObjects(v, parentKey: parentKey))
            }
        }
        return out
    }

    /// 从一个窗口对象里取“已用百分比”。
    static func extractPercent(_ dict: [String: Any]) -> Double? {
        let keys = ["used_percent", "usedPercent", "utilization",
                    "percent_used", "percentUsed", "usage_percent", "percent"]
        if let v = firstValue(in: dict, keys: keys), let d = double(v) {
            return d
        }
        return nil
    }

    /// 从一个窗口对象里取重置时间。
    static func extractReset(_ dict: [String: Any], now: Date = Date()) -> Date? {
        // 直接是时间戳
        if let v = firstValue(in: dict, keys: ["resets_at", "resetsAt", "reset_at", "resetAt", "reset_time"]),
           let d = date(v) {
            return d
        }
        // 相对秒数
        if let v = firstValue(in: dict, keys: ["resets_in_seconds", "resetsInSeconds", "reset_in_seconds", "seconds_until_reset"]),
           let s = double(v) {
            return now.addingTimeInterval(s)
        }
        // 相对分钟
        if let v = firstValue(in: dict, keys: ["resets_in_minutes", "minutes_until_reset"]),
           let m = double(v) {
            return now.addingTimeInterval(m * 60)
        }
        return nil
    }
}
