import XCTest
@testable import Tokenitor

/// v1.5.2 加固：这些用例守的都是「显示错数据比不显示更危险」的边界。
final class CopilotParseTests: XCTestCase {

    func testPercentRemainingIsPrimary() {
        XCTAssertEqual(CopilotProvider.usedPercent(from: ["percent_remaining": 30.0]), 70.0)
    }

    func testFallsBackToPercentUsed() {
        XCTAssertEqual(CopilotProvider.usedPercent(from: ["percent_used": 25.0]), 25.0)
    }

    /// 核心回归：字段全缺时**必须**返回 nil，绝不能兜底成「已用 0% / 剩余 100%」。
    func testMissingFieldsReturnNilNotFullQuota() {
        XCTAssertNil(CopilotProvider.usedPercent(from: [:]))
        XCTAssertNil(CopilotProvider.usedPercent(from: ["quota_id": "premium", "unlimited": false]))
    }

    func testOutOfRangeValuesAreClamped() {
        XCTAssertEqual(CopilotProvider.usedPercent(from: ["percent_remaining": 140.0]), 0.0)
        XCTAssertEqual(CopilotProvider.usedPercent(from: ["percent_remaining": -20.0]), 100.0)
    }

    /// 字符串数字（接口偶尔返回字符串）也应被接受。
    func testStringNumbersAccepted() {
        XCTAssertEqual(CopilotProvider.usedPercent(from: ["percent_remaining": "40"]), 60.0)
    }
}

final class ThresholdTests: XCTestCase {

    func testWarnAlwaysAboveCrit() {
        // 把「低用量」压到紧急线以下 → 紧急线被顶下去，保持 warn > crit
        let (w, c) = Settings.resolveThresholds(settingWarn: 10, currentCrit: 20)
        XCTAssertEqual(w, 10); XCTAssertEqual(c, 9)
        XCTAssertGreaterThan(w, c)
    }

    func testCritAlwaysBelowWarn() {
        let (w, c) = Settings.resolveThresholds(settingCrit: 60, currentWarn: 50)
        XCTAssertEqual(c, 60); XCTAssertEqual(w, 61)
        XCTAssertGreaterThan(w, c)
    }

    func testNormalValuesUntouched() {
        let (w, c) = Settings.resolveThresholds(settingWarn: 50, currentCrit: 20)
        XCTAssertEqual(w, 50); XCTAssertEqual(c, 20)
    }

    func testRangeClamping() {
        XCTAssertEqual(Settings.clampWarn(999), 100)
        XCTAssertEqual(Settings.clampWarn(-5), 1)
        XCTAssertEqual(Settings.clampCrit(999), 99)
        XCTAssertEqual(Settings.clampCrit(-5), 0)
    }
}

final class AlertEngineTests: XCTestCase {

    func testFiresOnceThenStaysQuiet() {
        var state = 0
        var r = AlertEngine.decide(remaining: 40, warn: 50, crit: 20, previouslyFired: state)
        XCTAssertEqual(r.fire, 1); state = r.newState
        r = AlertEngine.decide(remaining: 35, warn: 50, crit: 20, previouslyFired: state)
        XCTAssertNil(r.fire, "同一档内不应重复打扰"); state = r.newState
    }

    func testEscalatesFromWarnToCritical() {
        let r = AlertEngine.decide(remaining: 15, warn: 50, crit: 20, previouslyFired: 1)
        XCTAssertEqual(r.fire, 2); XCTAssertEqual(r.newState, 2)
    }

    func testRecoveryRearms() {
        let recovered = AlertEngine.decide(remaining: 80, warn: 50, crit: 20, previouslyFired: 2)
        XCTAssertNil(recovered.fire)
        XCTAssertEqual(recovered.newState, 0, "回升后应重置")
        let again = AlertEngine.decide(remaining: 40, warn: 50, crit: 20, previouslyFired: recovered.newState)
        XCTAssertEqual(again.fire, 1, "重置后应可再次触发")
    }

    /// 限流/断网时展示的缓存旧数据不得触发告警。
    func testStaleAndFailedSnapshotsAreNotAlertable() {
        let fresh = ProviderSnapshot(name: "X", windows: [], ok: true, error: nil)
        let stale = ProviderSnapshot(name: "X", windows: [], ok: true, error: nil, isStale: true)
        XCTAssertTrue(AlertEngine.alertable(fresh))
        XCTAssertFalse(AlertEngine.alertable(stale))
        XCTAssertFalse(AlertEngine.alertable(.failed("X", "boom")))
    }
}

final class CLIOutputTests: XCTestCase {

    func testJSONShapeIsStable() throws {
        let snap = ProviderSnapshot(
            name: "Codex",
            windows: [UsageWindow(usedPercent: 81, resetsAt: Date(timeIntervalSince1970: 1_780_000_000), label: "weekly")],
            ok: true, error: nil, plan: "Plus",
            dataAsOf: Date(timeIntervalSince1970: 1_779_000_000),
            resetCredits: 4)
        let json = CLIRunner.jsonString([snap])
        let arr = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let d = try XCTUnwrap(arr.first)
        XCTAssertEqual(d["name"] as? String, "Codex")
        XCTAssertEqual(d["status"] as? String, "live")
        XCTAssertEqual(d["plan"] as? String, "Plus")
        XCTAssertEqual(d["reset_credits"] as? Int, 4)
        XCTAssertNotNil(d["data_as_of"])
        let w = try XCTUnwrap((d["windows"] as? [[String: Any]])?.first)
        XCTAssertEqual(w["label"] as? String, "weekly")
        XCTAssertEqual(w["remaining_percent"] as? Int, 19, "输出的是剩余量，不是已用量")
    }

    func testStatusReflectsStaleAndOffline() {
        let stale = ProviderSnapshot(name: "Claude", windows: [], ok: true, error: nil, isStale: true)
        XCTAssertTrue(CLIRunner.jsonString([stale]).contains("\"cached\""))
        XCTAssertTrue(CLIRunner.jsonString([.failed("Claude", "boom")]).contains("\"offline\""))
    }
}

/// Gemini 计数：logs.json 与 chats/*.jsonl 记的是同一批提问但时间戳差几秒，
/// 合并计数会让用量成倍虚高——这里用真实数据形态的 fixture 守住。
final class GeminiCountTests: XCTestCase {

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gemini-test-\(UUID().uuidString)/proj", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("chats"),
                                                withIntermediateDirectories: true)
        return dir
    }

    /// 两个来源都记了同两次提问（时间戳相差 4 秒）→ 必须算 2 次，不是 4 次。
    func testDoesNotDoubleCountAcrossSources() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let day = "2026-07-21"
        try """
        [{"type":"user","message":"你是什么模型","timestamp":"\(day)T13:55:43.751Z"},
         {"type":"user","message":"能自动更新吗","timestamp":"\(day)T13:57:07.284Z"}]
        """.write(to: dir.appendingPathComponent("logs.json"), atomically: true, encoding: .utf8)
        // 会话文件：同两次提问，时间戳晚 4 秒 + CLI 注入的引导消息
        try """
        {"$set":{"messages":[{"type":"user","timestamp":"\(day)T13:52:02.887Z","content":[{"text":"<session_context>\\nThis is the Gemini CLI."}]}]}}
        {"type":"user","timestamp":"\(day)T13:55:47.661Z","content":[{"text":"你是什么模型"}]}
        {"type":"user","timestamp":"\(day)T13:57:10.802Z","content":[{"text":"能自动更新吗"}]}
        """.write(to: dir.appendingPathComponent("chats/session.jsonl"), atomically: true, encoding: .utf8)

        let start = ISO8601DateFormatter().date(from: "\(day)T00:00:00Z")!
        XCTAssertEqual(GeminiProvider.countToday(userDirs: [dir], todayStart: start), 2,
                       "同一批提问不能因两个来源被数两遍")
    }

    /// logs.json 缺失（新版 CLI 可能不再写）→ 回退扫会话文件，且不把引导消息算作请求。
    func testFallsBackToSessionFilesAndSkipsBootstrap() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let day = "2026-07-21"
        try """
        {"type":"user","timestamp":"\(day)T13:52:02.887Z","content":[{"text":"<session_context>\\nThis is the Gemini CLI."}]}
        {"type":"user","timestamp":"\(day)T13:55:47.661Z","content":[{"text":"你是什么模型"}]}
        """.write(to: dir.appendingPathComponent("chats/session.jsonl"), atomically: true, encoding: .utf8)

        let start = ISO8601DateFormatter().date(from: "\(day)T00:00:00Z")!
        XCTAssertEqual(GeminiProvider.countToday(userDirs: [dir], todayStart: start), 1,
                       "引导消息不是用户请求")
    }

    /// 昨天的记录不计入今天。
    func testOnlyCountsToday() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try """
        [{"type":"user","message":"旧的","timestamp":"2026-07-20T10:00:00.000Z"},
         {"type":"user","message":"今天的","timestamp":"2026-07-21T10:00:00.000Z"}]
        """.write(to: dir.appendingPathComponent("logs.json"), atomically: true, encoding: .utf8)
        let start = ISO8601DateFormatter().date(from: "2026-07-21T00:00:00Z")!
        XCTAssertEqual(GeminiProvider.countToday(userDirs: [dir], todayStart: start), 1)
    }
}
