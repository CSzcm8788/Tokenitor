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

/// Claude 本地桥：statusline payload 的解析。字段语义来自官方 changelog
///（`rate_limits` + 5-hour/7-day 窗口 + `used_percentage` / `resets_at`）；
/// 解析刻意宽容（键名大小写风格、秒/毫秒/ISO 时间戳），认不出的窗口一律跳过而不猜。
final class ClaudeStatuslineTests: XCTestCase {

    private func payload(_ name: String) throws -> Any {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        return try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
    }

    func testParsesBothWindowsFromFixture() throws {
        let ws = ClaudeStatusline.parseWindows(try payload("claude-statusline.json"))
        XCTAssertEqual(ws.count, 2)
        XCTAssertEqual(ws[0].label, "5h", "5 小时窗口必须排在前（与其它源展示顺序一致）")
        XCTAssertEqual(ws[0].usedPercent, 51)
        XCTAssertEqual(ws[0].remainingPercent, 49)
        XCTAssertEqual(ws[1].label, "weekly")
        XCTAssertEqual(ws[1].usedPercent, 25)
        XCTAssertNotNil(ws[0].resetsAt)
    }

    /// camelCase 变体也要认（没有正式 schema 承诺，不能只赌一种写法）。
    func testAcceptsCamelCaseVariant() throws {
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(#"""
        {"rateLimits":{"fiveHour":{"usedPercentage":80,"resetsAt":1746920100}}}
        """#.utf8)))
        let ws = ClaudeStatusline.parseWindows(obj)
        XCTAssertEqual(ws.count, 1)
        XCTAssertEqual(ws[0].usedPercent, 80)
    }

    /// 毫秒时间戳与 ISO 字符串都要能解析。
    func testResetTimestampForms() throws {
        for raw in [#"{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":1746920100000}}}"#,
                    #"{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":"2026-05-11T00:15:00Z"}}}"#] {
            let ws = ClaudeStatusline.parseWindows(try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8))))
            XCTAssertEqual(ws.count, 1)
            let d = try XCTUnwrap(ws[0].resetsAt, "毫秒/ISO 都应解析出时间：\(raw)")
            XCTAssertGreaterThan(d, Date(timeIntervalSince1970: 1_700_000_000))
            XCTAssertLessThan(d, Date(timeIntervalSince1970: 2_000_000_000), "毫秒未被当成秒（否则会落到公元 57000 年）")
        }
    }

    /// 没有 rate_limits、或窗口里没有百分比 → 返回空，交由 provider 降级到端点。
    func testMissingDataYieldsNoWindows() throws {
        for raw in [#"{"model":{"id":"x"}}"#,
                    #"{"rate_limits":{}}"#,
                    #"{"rate_limits":{"five_hour":{"resets_at":1746920100}}}"#] {
            let ws = ClaudeStatusline.parseWindows(try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8))))
            XCTAssertTrue(ws.isEmpty, "缺百分比时不能凭空造窗口：\(raw)")
        }
    }

    /// 百分比越界要夹紧（防止界面出现负剩余或 >100%）。
    func testPercentClamped() throws {
        let ws = ClaudeStatusline.parseWindows(try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(
            #"{"rate_limits":{"five_hour":{"used_percentage":150},"seven_day":{"used_percentage":-5}}}"#.utf8))))
        XCTAssertEqual(ws[0].usedPercent, 100)
        XCTAssertEqual(ws[1].usedPercent, 0)
    }
}

/// Claude 桌面 App 的本地用量历史（`plan-usage-history.json`）。
/// 字段是缩写（`u.fh`/`u.sd`/`u.xu`）且**没有** resets_at——这两点决定了解析口径：
/// 缩写要映射成人能看懂的窗口名，重置时间要留空而不是编一个。
final class ClaudeDesktopUsageTests: XCTestCase {

    private func payload() throws -> Any {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/claude-plan-usage-history.json",
                                                 withExtension: nil))
        return try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
    }

    /// 取**最新**样本（不是第一个），映射缩写，且不带重置时间。
    func testParsesLatestSample() throws {
        let r = try XCTUnwrap(ClaudeDesktopUsage.parseLatest(try payload()))
        XCTAssertFalse(r.windows.isEmpty)
        XCTAssertEqual(r.windows[0].label, "5h", "fh 映射为 5h 且排在最前")
        XCTAssertTrue(r.windows.contains { $0.label == "weekly" }, "sd 映射为 weekly")
        for w in r.windows {
            XCTAssertNil(w.resetsAt, "该源没有 resets_at，不能臆造重置时间")
        }
        // 采样时间必须是毫秒转秒后的合理时刻（不能落到 1970 或公元 57000 年）
        XCTAssertGreaterThan(r.asOf, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertLessThan(r.asOf, Date(timeIntervalSince1970: 2_000_000_000))
    }

    /// 值是「已用 %」：fh=100 意味着 5 小时窗口**剩 0%**，不能反过来。
    func testUsedPercentSemantics() throws {
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(
            #"{"version":2,"samples":[{"t":1785000000000,"u":{"fh":100,"sd":27}}]}"#.utf8)))
        let r = try XCTUnwrap(ClaudeDesktopUsage.parseLatest(obj))
        XCTAssertEqual(r.windows[0].remainingPercent, 0)
        XCTAssertEqual(r.windows[1].remainingPercent, 73)
    }

    /// extra_usage（xu）只在有额外额度时出现——出现就显示，不出现不能凭空造。
    func testExtraUsageOptional() throws {
        let withXu = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(
            #"{"samples":[{"t":1785000000000,"u":{"fh":10,"sd":20,"xu":94.91}}]}"#.utf8)))
        XCTAssertTrue(try XCTUnwrap(ClaudeDesktopUsage.parseLatest(withXu)).windows
            .contains { $0.label == "extra_usage" })
        let without = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(
            #"{"samples":[{"t":1785000000000,"u":{"fh":10,"sd":20}}]}"#.utf8)))
        XCTAssertFalse(try XCTUnwrap(ClaudeDesktopUsage.parseLatest(without)).windows
            .contains { $0.label == "extra_usage" })
    }

    /// 未知缩写（如 cw / oa）语义不明 → 跳过，不显示看不懂的窗口。
    func testUnknownAbbreviationsSkipped() throws {
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(
            #"{"samples":[{"t":1785000000000,"u":{"fh":10,"cw":50,"oa":60}}]}"#.utf8)))
        let r = try XCTUnwrap(ClaudeDesktopUsage.parseLatest(obj))
        XCTAssertEqual(r.windows.count, 1, "只认识 fh，其余跳过")
    }

    /// 空 samples / 无 u / 结构不符 → nil，交由 provider 继续降级。
    func testEmptyOrMalformedYieldsNil() throws {
        for raw in [#"{"version":2,"samples":[]}"#,
                    #"{"samples":[{"t":1785000000000}]}"#,
                    #"{"samples":[{"u":{"fh":10}}]}"#,
                    #"{"foo":"bar"}"#] {
            let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)))
            XCTAssertNil(ClaudeDesktopUsage.parseLatest(obj), "不该硬凑出数据：\(raw)")
        }
    }
}

/// 桌面用量历史没有 `resets_at`，倒计时只能沿用缓存里仍在未来的那个。
/// 这里守的边界是：**要么给真值，要么不给**——绝不外推出一个新的重置时间。
final class ClaudeResetCarryForwardTests: XCTestCase {

    private let future = Date().addingTimeInterval(3600)
    private let past = Date().addingTimeInterval(-3600)

    /// 缓存里同名窗口的重置时间仍在未来 → 窗口没翻滚，那个时间点还是真值，沿用。
    func testAdoptsStillFutureResetFromCache() {
        let fresh = [UsageWindow(usedPercent: 40, resetsAt: nil, label: "5h")]
        let cached = [UsageWindow(usedPercent: 90, resetsAt: future, label: "5h")]
        let out = ClaudeProvider.carryForwardResets(fresh, from: cached)
        XCTAssertEqual(out[0].resetsAt, future)
        XCTAssertEqual(out[0].usedPercent, 40, "百分比必须仍来自新数据，不能被缓存带回去")
    }

    /// 缓存里的重置时间已过去 → 窗口已翻滚，新的重置时间我们不知道，就**不显示**。
    func testDropsExpiredResetInsteadOfExtrapolating() {
        let fresh = [UsageWindow(usedPercent: 10, resetsAt: nil, label: "5h")]
        let cached = [UsageWindow(usedPercent: 90, resetsAt: past, label: "5h")]
        XCTAssertNil(ClaudeProvider.carryForwardResets(fresh, from: cached)[0].resetsAt)
    }

    /// 只按 label 对齐；缓存里没有这个窗口就保持为空。
    func testOnlyMatchesSameLabel() {
        let fresh = [UsageWindow(usedPercent: 10, resetsAt: nil, label: "extra_usage")]
        let cached = [UsageWindow(usedPercent: 90, resetsAt: future, label: "5h")]
        XCTAssertNil(ClaudeProvider.carryForwardResets(fresh, from: cached)[0].resetsAt)
    }

    /// 新数据自己带了重置时间（statusline / 端点路径）→ 不被缓存覆盖。
    func testNeverOverwritesAFreshReset() {
        let own = Date().addingTimeInterval(7200)
        let fresh = [UsageWindow(usedPercent: 10, resetsAt: own, label: "5h")]
        let cached = [UsageWindow(usedPercent: 90, resetsAt: future, label: "5h")]
        XCTAssertEqual(ClaudeProvider.carryForwardResets(fresh, from: cached)[0].resetsAt, own)
    }

    func testEmptyCacheIsNoOp() {
        let fresh = [UsageWindow(usedPercent: 10, resetsAt: nil, label: "weekly")]
        XCTAssertNil(ClaudeProvider.carryForwardResets(fresh, from: [])[0].resetsAt)
    }
}
