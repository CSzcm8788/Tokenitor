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
