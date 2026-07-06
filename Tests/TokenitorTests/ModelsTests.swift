import XCTest
@testable import Tokenitor

final class ModelsTests: XCTestCase {

    // MARK: - formatCountdown 边界

    func testCountdownPastAndNil() {
        let now = Date()
        XCTAssertEqual(formatCountdown(to: nil, now: now, english: false), "")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(-10), now: now, english: false), "现在")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(-10), now: now, english: true), "now")
    }

    func testCountdownMinutesHoursDays() {
        let now = Date()
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(5 * 60), now: now, english: false), "5分钟")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(2 * 3600 + 30 * 60), now: now, english: false), "2小时30分")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(2 * 3600), now: now, english: false), "2小时")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(3 * 86400), now: now, english: false), "3天")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(6 * 86400 + 23 * 3600), now: now, english: false), "6天23小时")
    }

    func testCountdownEnglish() {
        let now = Date()
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(5 * 60), now: now, english: true), "5m")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(2 * 3600 + 30 * 60), now: now, english: true), "2h 30m")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(6 * 86400 + 23 * 3600), now: now, english: true), "6d 23h")
        let far = formatCountdown(to: now.addingTimeInterval(10 * 86400), now: now, english: true)
        XCTAssertFalse(far.contains("月"), "英文远期应为 MMM d，实际: \(far)")
    }

    func testCountdownFarFutureShowsDate() {
        let now = Date()
        let out = formatCountdown(to: now.addingTimeInterval(10 * 86400), now: now, english: false)
        XCTAssertTrue(out.contains("月") && out.contains("日"), "≥9 天应显示 M月d日，实际: \(out)")
    }

    // MARK: - formatUpdatedAgo（卡片标题下的「更新于」相对时间）

    func testUpdatedAgo() {
        let now = Date()
        XCTAssertEqual(formatUpdatedAgo(now.addingTimeInterval(-5), now: now, english: false), "刚刚")
        XCTAssertEqual(formatUpdatedAgo(now.addingTimeInterval(-90), now: now, english: false), "1分钟前")
        XCTAssertEqual(formatUpdatedAgo(now.addingTimeInterval(-2 * 3600), now: now, english: false), "2小时前")
        XCTAssertTrue(formatUpdatedAgo(now.addingTimeInterval(-3 * 86400), now: now, english: false).contains("月"),
                      "超过一天应显示日期")
        XCTAssertEqual(formatUpdatedAgo(now.addingTimeInterval(-5), now: now, english: true), "just now")
        XCTAssertEqual(formatUpdatedAgo(now.addingTimeInterval(-90), now: now, english: true), "1m ago")
    }

    // MARK: - UsageLevel 档位

    func testUsageLevelThresholds() {
        XCTAssertEqual(UsageLevel.from(remaining: 80, warnAt: 50, critAt: 20), .healthy)
        XCTAssertEqual(UsageLevel.from(remaining: 50, warnAt: 50, critAt: 20), .warning)
        XCTAssertEqual(UsageLevel.from(remaining: 20, warnAt: 50, critAt: 20), .critical)
        XCTAssertEqual(UsageLevel.from(remaining: 0, warnAt: 50, critAt: 20), .critical)
    }

    func testRemainingPercentClamps() {
        XCTAssertEqual(UsageWindow(usedPercent: 130, resetsAt: nil, label: "5h").remainingPercent, 0)
        XCTAssertEqual(UsageWindow(usedPercent: -5, resetsAt: nil, label: "5h").remainingPercent, 100)
    }

    // MARK: - 服务状态：取最严重指示级别

    func testStatusMonitorWorst() {
        XCTAssertNil(StatusMonitor.worst(of: [:]))
        XCTAssertNil(StatusMonitor.worst(of: ["Claude": "none", "Codex": "none"]))
        XCTAssertEqual(StatusMonitor.worst(of: ["Claude": "none", "Codex": "minor"]), "minor")
        XCTAssertEqual(StatusMonitor.worst(of: ["Claude": "critical", "Codex": "minor"]), "critical")
        XCTAssertEqual(StatusMonitor.worst(of: ["Copilot": "major", "Codex": "minor"]), "major")
    }

    // MARK: - 快照默认值（isStale 新字段不改变既有构造行为）

    func testSnapshotDefaultsNotStale() {
        XCTAssertFalse(ProviderSnapshot.failed("X", "err").isStale)
        XCTAssertFalse(ProviderSnapshot.absent("X").isStale)
        XCTAssertTrue(ProviderSnapshot.absent("X").hidden)
    }
}
