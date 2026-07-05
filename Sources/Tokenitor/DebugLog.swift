import Foundation

/// 把原始响应写到 ~/.tokenitor/debug/，方便接口字段变动时排查。
/// 写入前**脱敏**（抹掉 token / 密钥类字段与串），并**自动清理**超过保留期的旧转储。
enum DebugLog {
    /// 转储保留天数：超过即自动删除。
    private static let retentionDays: Double = 3

    static var dir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".tokenitor/debug", isDirectory: true)
    }

    static func dump(_ name: String, _ data: Data) {
        guard Settings.shared.debugDump else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        prune()
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(name)-\(ts).json")
        try? redact(data).write(to: url)
    }

    static func dump(_ name: String, _ text: String) {
        dump(name, Data(text.utf8))
    }

    /// 把一个 JSON 对象（字典/数组）转储下来，便于核对字段结构。
    static func dumpJSON(_ name: String, _ obj: Any) {
        guard Settings.shared.debugDump else { return }
        let scrubbed = redactJSON(obj)
        if let data = try? JSONSerialization.data(withJSONObject: scrubbed, options: [.prettyPrinted, .sortedKeys]) {
            dump(name, data)
        }
    }

    // MARK: - 脱敏

    /// 敏感字段名（小写匹配）：其值一律替换为占位符。
    private static let secretKeys: Set<String> = [
        "access_token", "refresh_token", "accesstoken", "refreshtoken",
        "id_token", "idtoken", "token", "oauth_token", "oauthtoken",
        "sessionkey", "session_key", "authorization", "cookie",
        "client_secret", "clientsecret", "api_key", "apikey", "secret", "password"
    ]

    private static func redact(_ data: Data) -> Data {
        // 优先按 JSON 递归脱敏；非 JSON 再用正则抹掉 token 样式的串。
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            let scrubbed = redactJSON(obj)
            if let out = try? JSONSerialization.data(withJSONObject: scrubbed, options: [.prettyPrinted, .sortedKeys]) {
                return out
            }
        }
        return Data(redactString(String(decoding: data, as: UTF8.self)).utf8)
    }

    private static func redactJSON(_ any: Any) -> Any {
        if let dict = any as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                if secretKeys.contains(k.lowercased()) {
                    out[k] = "«redacted»"
                } else if let s = v as? String {
                    out[k] = redactString(s)
                } else {
                    out[k] = redactJSON(v)
                }
            }
            return out
        }
        if let arr = any as? [Any] { return arr.map { redactJSON($0) } }
        if let s = any as? String { return redactString(s) }
        return any
    }

    /// 抹掉常见 token 样式：OpenAI/DeepSeek `sk-…`、GitHub `gho_…/ghp_…`、Anthropic `sk-ant-…`、JWT `eyJ….….…`。
    private static func redactString(_ s: String) -> String {
        var out = s
        let patterns = [
            "sk-ant-[A-Za-z0-9_-]{10,}",
            "sk-[A-Za-z0-9_-]{16,}",
            "gh[oprsu]_[A-Za-z0-9]{20,}",
            "eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}"
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p) {
                out = re.stringByReplacingMatches(
                    in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "«redacted»")
            }
        }
        return out
    }

    // MARK: - 清理

    /// 删除超过保留期的旧转储文件。
    private static func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-retentionDays * 86400)
        for f in files {
            let mdate = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let d = mdate, d < cutoff { try? FileManager.default.removeItem(at: f) }
        }
    }
}
