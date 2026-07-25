import XCTest
@testable import Tokenitor

/// Golden fixtures：用各源**真实结构**的脱敏样本跑解析，锁住「字段名 → 我们的口径」这层契约。
/// 厂商改 schema 时，把新样本替换进 Tests/TokenitorTests/Fixtures/ 即可看到具体哪里断了
/// （与发版前「对照社区同类项目核对端点」的例行检查互补）。
final class FixtureTests: XCTestCase {

    /// 读一行 fixture（第 index 行，0 起）。
    private func line(_ name: String, _ index: Int = 0) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil),
                                "缺 fixture: \(name)")
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").filter { !$0.isEmpty }
        return String(lines[index])
    }

    private func usageDict(_ raw: String, key: String) throws -> [String: Any] {
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)))
        var info = TokenAggregator.LineInfo()
        TokenAggregator.extract(obj, usageKey: key, into: &info)
        return try XCTUnwrap(info.usages.first, "fixture 里没找到 \(key)")
    }

    // MARK: - Codex

    /// 真实 rate_limits 事件：周窗口（10080 分钟）+ plan_type + credits 余额 0。
    func testCodexRateLimitsFixture() throws {
        let raw = try line("codex-session.jsonl", 1)
        let hit = try XCTUnwrap(CodexProvider.parseRateLimitsLine(Substring(raw)))
        let rl = hit.0
        XCTAssertEqual(rl["plan_type"] as? String, "plus")
        let primary = try XCTUnwrap(rl["primary"] as? [String: Any])
        XCTAssertEqual(JSON.double(primary["window_minutes"]), 10080, "新版 schema 只发周窗口")
        XCTAssertEqual(JSON.double(primary["used_percent"]), 91.0)
        XCTAssertNotNil(hit.1, "应取到事件自身时间戳")
        // credits 余额为 0 → 不显示胶囊
        let (n, unlimited) = CodexProvider.parseCredits(rl["credits"])
        XCTAssertNil(n); XCTAssertFalse(unlimited)
    }

    /// 模型声明行（thread_settings_applied）：Codex 的 model 由它设定，token 事件不带 model。
    func testCodexModelDeclarationFixture() throws {
        let raw = try line("codex-session.jsonl", 0)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)))
        var info = TokenAggregator.LineInfo()
        TokenAggregator.extract(obj, usageKey: "last_token_usage", into: &info)
        XCTAssertEqual(info.model, "gpt-5.6-sol")
        var current: String? = "gpt-5.5"
        XCTAssertEqual(TokenAggregator.resolveModel(info, current: &current, default: "x"), "gpt-5.6-sol",
                       "声明行应把当前模型切过去")
        // 随后不带 model 的行沿用新值
        var empty = TokenAggregator.LineInfo()
        XCTAssertEqual(TokenAggregator.resolveModel(empty, current: &current, default: "x"), "gpt-5.6-sol")
        _ = empty
    }

    // MARK: - Claude

    /// 真实 usage：cache_read 巨大而 input 极小——input 不含缓存，不能相减。
    func testClaudeUsageFixture() throws {
        let u = try usageDict(try line("claude-session.jsonl"), key: "usage")
        let c = try XCTUnwrap(TokenAggregator.counts(from: u))
        XCTAssertEqual(c.input, 2)
        XCTAssertEqual(c.output, 4364, "output 已含 reasoning，不重复累加")
        XCTAssertEqual(c.cacheWrite, 1806)
        XCTAssertEqual(c.cacheRead, 626540)
    }

    // MARK: - Gemini

    /// 真实 tokens：input 含 cached、thoughts 独立于 output —— 映射后总和须等于官方 total。
    func testGeminiTokensFixture() throws {
        let raw = try line("gemini-session.jsonl")
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        let t = try XCTUnwrap(obj["tokens"] as? [String: Any])
        let c = try XCTUnwrap(TokenAggregator.geminiCounts(from: t))
        let total = try XCTUnwrap(JSON.double(t["total"]))
        XCTAssertEqual(Double(c.total), total, "映射后总和必须与官方 total 一致")
        XCTAssertEqual(c.output, 27 + 334, "thoughts 并入 output（按输出计价）")
        XCTAssertEqual(obj["model"] as? String, "gemini-3.5-flash")
    }

    // MARK: - Grok

    /// 真实 billing 事件：周共享池 + 精确重置 + 档位。
    func testGrokBillingFixture() throws {
        let raw = try line("grok-unified.jsonl", 0)
        let hit = try XCTUnwrap(GrokProvider.parseBillingLine(Substring(raw)))
        XCTAssertEqual(hit.0, 22.0)
        XCTAssertEqual(hit.2, "X Premium")
        XCTAssertEqual(PlanTier.grok(hit.2), "X Premium")
        let resets = try XCTUnwrap(hit.1, "应解析 currentPeriod.end（含小数秒 + +00:00 时区）")
        XCTAssertGreaterThan(resets, Date(timeIntervalSince1970: 1_784_000_000))
    }

    /// 真实 inference_done：prompt 含 cached，须扣除。
    func testGrokInferenceFixture() throws {
        let raw = try line("grok-unified.jsonl", 1)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        let ctx = try XCTUnwrap(obj["ctx"] as? [String: Any])
        let c = try XCTUnwrap(TokenAggregator.grokCounts(from: ctx))
        XCTAssertEqual(c.input, 13617 - 10880)
        XCTAssertEqual(c.cacheRead, 10880)
        XCTAssertEqual(c.output, 52, "completion 已含 reasoning")
    }

    // MARK: - 更新检查

    func testUpdateTagParsing() throws {
        let data = Data(#"{"tag_name":"v1.5.4","name":"Tokenitor 1.5.4"}"#.utf8)
        XCTAssertEqual(UpdateCheck.parseTag(data), "v1.5.4")
        XCTAssertNil(UpdateCheck.parseTag(Data(#"{"message":"Not Found"}"#.utf8)))
    }

    func testUpdateVersionComparison() {
        XCTAssertTrue(UpdateCheck.isNewer("v1.5.4", than: "1.5.3"))
        XCTAssertTrue(UpdateCheck.isNewer("v1.5.10", than: "1.5.9"), "按段比数值，不是字符串比较")
        XCTAssertTrue(UpdateCheck.isNewer("v1.6", than: "1.5.9"))
        XCTAssertFalse(UpdateCheck.isNewer("v1.5.3", than: "1.5.3"))
        XCTAssertFalse(UpdateCheck.isNewer("v1.5.2", than: "1.5.3"))
        XCTAssertFalse(UpdateCheck.isNewer("v1.6.0", than: "1.6"), "补位等价")
    }

    // MARK: - 覆盖范围文案

    /// 五源都必须有覆盖范围说明（新增 AI 时忘写会被这条挡住）。
    func testEveryProviderDeclaresCoverage() {
        for kind in AIKind.allCases {
            XCTAssertFalse(kind.coverage.isEmpty, "\(kind.rawValue) 缺覆盖范围说明")
            XCTAssertTrue(kind.coverage.contains("覆盖范围") || kind.coverage.contains("Coverage"),
                          "\(kind.rawValue) 的说明应以「覆盖范围 / Coverage」开头，两种语言都要有")
        }
    }

    /// 关键口径必须写明，避免最常见的误读：
    /// Grok 是跨产品共享池、Gemini 只是本机估算、Claude/Codex/Copilot 是账号级。
    func testCoverageStatesTheEasilyMisreadScope() {
        XCTAssertTrue(AIKind.grok.coverage.contains("X 账号") || AIKind.grok.coverage.contains("X account"),
                      "Grok 必须说明是整个 X 账号的跨产品池")
        XCTAssertTrue(AIKind.gemini.coverage.contains("本机") || AIKind.gemini.coverage.contains("this Mac"),
                      "Gemini 必须说明只是本机估算")
        XCTAssertTrue(AIKind.claude.coverage.contains("账号") || AIKind.claude.coverage.contains("account"),
                      "Claude 必须说明是账号级共享")
    }
}
