import Foundation

/// 社区定价表（LiteLLM `model_prices_and_context_window.json`，MIT）——**发版时**由
/// `sync-pricing.sh` 与上游比对更新、打包进 app（`Pricing/model_prices.json`），运行时不联网。
///
/// 内存纪律：1.5MB 原始 JSON **不常驻**——首次查询时懒解析一次（autoreleasepool 包裹，
/// 瞬时峰值随即回收），只保留紧凑 `[规范化模型名: ModelPrice]` 字典（约 3000 条 / ~350KB）。
/// 同名冲突按「裸名 > 一方前缀 > 云转售（azure/bedrock/…）」择优，价格单位统一换算为 $/百万 token。
enum PricingTable {

    /// 紧凑常驻表（懒加载，static let 保证线程安全的一次初始化）。
    static let shared: [String: ModelPrice] = {
        guard let url = Bundle.main.url(forResource: "model_prices", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return build(from: data)
    }()

    /// 快照元信息里的更新日期（说明页「截至 YYYY-MM-DD」用）；读不到返回 nil。
    static let snapshotDate: String? = {
        guard let url = Bundle.main.url(forResource: "model_prices_meta", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return obj["updated"] as? String
    }()

    /// 解析 + 紧凑化（internal 供单元测试直接喂 fixture）。
    static func build(from data: Data) -> [String: ModelPrice] {
        var out: [String: ModelPrice] = [:]
        var score: [String: Int] = [:]   // 记录已收录条目的来源优先级
        autoreleasepool {
            guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            for (rawKey, value) in root {
                guard let v = value as? [String: Any],
                      let inC = costPerToken(v["input_cost_per_token"]),
                      let outC = costPerToken(v["output_cost_per_token"]) else { continue }
                let crC = costPerToken(v["cache_read_input_token_cost"]) ?? 0
                let cwC = costPerToken(v["cache_creation_input_token_cost"]) ?? 0
                let M = 1_000_000.0
                let price = ModelPrice(input: inC * M, output: outC * M,
                                       cacheRead: crC * M, cacheWrite: cwC * M)
                let key = normalize(rawKey)
                guard !key.isEmpty else { continue }
                let s = sourceScore(rawKey)
                if s > score[key, default: -1] {
                    out[key] = price
                    score[key] = s
                }
            }
        }
        return out
    }

    private static func costPerToken(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    /// 规范化：小写、去 `provider/` 路径前缀、去 `anthropic.` 式点前缀、去 bedrock `:0` 版本尾巴。
    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        if let slash = s.lastIndex(of: "/") { s = String(s[s.index(after: slash)...]) }
        for p in ["anthropic.", "openai.", "google.", "meta.", "mistral.", "deepseek.", "xai."] {
            if s.hasPrefix(p) { s.removeFirst(p.count); break }
        }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }   // bedrock "…-v1:0"
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 同名冲突择优：裸名（官方直连价）> 一方 provider 前缀 > 云转售渠道（azure/deepinfra/…）。
    static func sourceScore(_ rawKey: String) -> Int {
        let k = rawKey.lowercased()
        if let slash = k.firstIndex(of: "/") {
            let vendor = String(k[..<slash])
            return ["anthropic", "openai", "gemini", "deepseek", "xai", "vertex_ai"].contains(vendor) ? 2 : 1
        }
        // 无路径前缀：区分「anthropic.claude-…」点前缀（bedrock 直供）与真正的裸名（gpt-5.5 自身含点，不能按含点判断）
        for p in ["anthropic.", "openai.", "google.", "meta.", "mistral.", "deepseek.", "xai."] where k.hasPrefix(p) {
            return 2
        }
        return 3
    }
}
