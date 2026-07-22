import Foundation

/// 读取 Grok Build（grok CLI）的周共享池配额。
///   数据源：~/.grok/logs/unified.jsonl 里的 `billing: fetched credits config` 事件——
///   CLI 自己定期向 xAI 拉取额度并**落盘到本地日志**，我们只读文件、零联网、不碰任何端点。
///   事件带 `creditUsagePercent`（周池已用 %）、`currentPeriod.end`（精确重置时间）、
///   `subscriptionTier`（如 "X Premium"）。
/// 口径说明：xAI 2026-06 起付费档为全产品（Chat/Imagine/Build/API）共享周池，
///   此百分比即该共享池整体用量。
final class GrokProvider: UsageProvider {
    let displayName = "Grok"
    var enabled: Bool { Settings.shared.isEnabled(.grok) }

    private let logURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/logs/unified.jsonl")
    }()
    /// 只读日志尾部这么多字节找最近一次 billing 事件（日志会持续增长，事件约 40 分钟一条）。
    private static let tailBytes: UInt64 = 512 * 1024

    func fetch(completion: @escaping (ProviderSnapshot) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(self.read())
        }
    }

    private func read() -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return .absent(displayName)   // 未装 Grok Build → 隐藏
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? UInt64 ?? 0
        let from = size > Self.tailBytes ? size - Self.tailBytes : 0

        var latest: (used: Double, resetsAt: Date?, tier: String?, ts: Date?)? = nil
        JSONLScanner.scan(url: logURL, from: from) { line in
            guard line.contains("creditUsagePercent") else { return }
            autoreleasepool {
                if let hit = Self.parseBillingLine(line) { latest = hit }
            }
        }
        guard let latest else { return .absent(displayName) }   // 装了但从未跑出 billing 事件

        let w = UsageWindow(usedPercent: latest.used, resetsAt: latest.resetsAt, label: "weekly")
        return ProviderSnapshot(name: displayName, windows: [w], ok: true, error: nil,
                                plan: PlanTier.grok(latest.tier),
                                dataAsOf: latest.ts)
    }

    /// 解析单行 billing 事件；internal 供测试（正常事件 / 含关键字的垃圾行 / 字段缺失）。
    static func parseBillingLine(_ line: Substring) -> (Double, Date?, String?, Date?)? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ctx = obj["ctx"] as? [String: Any],
              let config = ctx["config"] as? [String: Any],
              let used = JSON.double(config["creditUsagePercent"]) else { return nil }
        var resetsAt: Date? = nil
        if let period = config["currentPeriod"] as? [String: Any],
           let end = period["end"] as? String {
            resetsAt = parseISO(end)
        }
        let tier = ctx["subscriptionTier"] as? String
        let ts = (obj["ts"] as? String).flatMap(parseISO)
        return (max(0, min(100, used)), resetsAt, tier, ts)
    }

    /// ISO8601（兼容小数秒与 +00:00 时区写法）。
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    static func parseISO(_ s: String) -> Date? { isoFrac.date(from: s) ?? iso.date(from: s) }
}
