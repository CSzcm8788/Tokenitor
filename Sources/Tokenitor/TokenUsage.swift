import Foundation

/// 一组 token 计数（input / output / 缓存读写）。
struct TokenCounts: Equatable, Codable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var total: Int { input + output + cacheRead + cacheWrite }
    var isZero: Bool { total == 0 }

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, output: a.output + b.output,
                    cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
    }
    static func += (a: inout TokenCounts, b: TokenCounts) { a = a + b }
}

/// 单个模型的聚合。
struct ModelTokens: Identifiable, Equatable, Codable {
    let model: String
    var counts: TokenCounts
    var cost: Double           // 估算美元（查不到定价为 0）
    var id: String { model }
}

/// 柱状图上的一根柱子（一天 / 一小时段 / 一周）。
struct SeriesPoint: Identifiable, Equatable, Codable {
    let label: String     // 轴上短标签，如 "Mon"、"0-4"、"W1"
    let full: String      // 悬浮提示用的完整标签
    var input: Int
    var cache: Int
    var output: Int
    var total: Int { input + cache + output }
    var id: String { label + full }
}

/// 单个周期（Day/Week/Month）的完整汇总，对应 Tokenscope 的 PeriodReport。
struct PeriodReport: Equatable, Codable {
    var totalTokens = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheTokens = 0
    var cost: Double = 0
    var deltaTokens: Double = 0   // 相对上一同长度周期的涨跌百分比
    var deltaCost: Double = 0
    /// 上一同长度周期是否有数据；没有时环比无意义，UI 显示「—」而非误导性的 100%。
    var hasPrior: Bool = false
    var requests = 0
    var sessions = 0
    var series: [SeriesPoint] = []
    var models: [ModelTokens] = []
    var reqTrend: [Double] = []
    var costTrend: [Double] = []
}

/// 单个工具（Claude / Codex / OpenCode）的 token 汇总；`day/week/month` 供页面周期切换用。
struct TokenStat: Identifiable, Equatable {
    let tool: String
    var today: TokenCounts
    var todayCost: Double
    var byModel: [ModelTokens]
    var requests: Int = 0
    var sessions: Int = 0
    var day: PeriodReport = PeriodReport()
    var week: PeriodReport = PeriodReport()
    var month: PeriodReport = PeriodReport()
    var id: String { tool }
}

/// 模型定价表（美元 / 每百万 token）。订阅用户为「等值花费」估算，非实际账单。
/// 价格随官方调整，需要时更新此表；查不到的模型成本显示为 0 / 「—」。
struct ModelPrice { let input, output, cacheRead, cacheWrite: Double }

enum Pricing {
    /// 定价表数据截至日期（更新价格时同步改这里；说明页展示给用户）。
    static let asOf = "2026-07"

    /// 关键字 → 价格（按子串匹配，越具体放越前）。
    private static let table: [(key: String, price: ModelPrice)] = [
        ("opus",          ModelPrice(input: 15,   output: 75, cacheRead: 1.50,  cacheWrite: 18.75)),
        ("sonnet",        ModelPrice(input: 3,    output: 15, cacheRead: 0.30,  cacheWrite: 3.75)),
        ("haiku",         ModelPrice(input: 0.80, output: 4,  cacheRead: 0.08,  cacheWrite: 1.0)),
        ("gpt-5-mini",    ModelPrice(input: 0.25, output: 2,  cacheRead: 0.025, cacheWrite: 0)),
        ("gpt-5-nano",    ModelPrice(input: 0.05, output: 0.4,cacheRead: 0.005, cacheWrite: 0)),
        ("gpt-5",         ModelPrice(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 0)),
        ("codex",         ModelPrice(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 0)),
        ("o3",            ModelPrice(input: 2,    output: 8,  cacheRead: 0.50,  cacheWrite: 0)),
    ]

    static func price(for model: String) -> ModelPrice? {
        let m = model.lowercased()
        return table.first(where: { m.contains($0.key) })?.price
    }

    /// 按定价表估算成本（美元）。查不到返回 0。
    static func cost(_ c: TokenCounts, model: String) -> Double {
        guard let p = price(for: model) else { return 0 }
        let M = 1_000_000.0
        return Double(c.input) / M * p.input
             + Double(c.output) / M * p.output
             + Double(c.cacheRead) / M * p.cacheRead
             + Double(c.cacheWrite) / M * p.cacheWrite
    }

    /// 缓存读相对「全价输入」省下的钱（只统计有定价的模型）——Token 页的洞察条用。
    static func cacheSavings(_ models: [ModelTokens]) -> Double {
        models.reduce(0) { acc, m in
            guard let p = price(for: m.model) else { return acc }
            return acc + Double(m.counts.cacheRead) / 1_000_000 * max(0, p.input - p.cacheRead)
        }
    }
}

/// 大数字友好显示：1234 → 1.2K，1_200_000 → 1.2M。
func formatTokens(_ n: Int) -> String {
    let d = Double(n)
    if d >= 1_000_000 { return String(format: "%.2fM", d / 1_000_000) }
    if d >= 1_000     { return String(format: "%.1fK", d / 1_000) }
    return "\(n)"
}

func formatUSD(_ v: Double) -> String {
    if v <= 0 { return "—" }
    if v < 0.01 { return "<$0.01" }
    return String(format: "$%.2f", v)
}

/// 环形图中心 / 图例用：0 也显示 $0.00（不返回「—」）。
func formatUSDExact(_ v: Double) -> String { String(format: "$%.2f", max(0, v)) }

/// 千分位整数（Requests 等计数用）。
func formatInt(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
