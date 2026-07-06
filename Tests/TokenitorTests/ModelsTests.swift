import XCTest
@testable import Tokenitor

final class ModelsTests: XCTestCase {

    // MARK: - formatCountdown 边界

    func testCountdownPastAndNil() {
        let now = Date()
        XCTAssertEqual(formatCountdown(to: nil, now: now), "")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(-10), now: now), "now")
    }

    func testCountdownMinutesAndHours() {
        let now = Date()
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(5 * 60), now: now), "5m")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(2 * 3600 + 30 * 60), now: now), "2h30m")
        XCTAssertEqual(formatCountdown(to: now.addingTimeInterval(3600 + 5 * 60), now: now), "1h05m")
    }

    func testCountdownFarFutureShowsDate() {
        let now = Date()
        let out = formatCountdown(to: now.addingTimeInterval(10 * 86400), now: now)
        XCTAssertTrue(out.contains("/"), "≥9 天应显示 M/d 日期，实际: \(out)")
    }

    // MARK: - formatUpdatedAgo（卡片标题下的「更新于」相对时间）

    func testUpdatedAgo() {
        let now = Date()
        XCTAssertEqual(formatUpdatedAgo(now.addingTimeInterval(-5), now: now), "刚刚")
        XCTAssertEqual(formatUpdatedAgo(now.addingTimeInterval(-90), now: now), "1分钟前")
        XCTAssertEqual(formatUpdatedAgo(now.addingTimeInterval(-2 * 3600), now: now), "2小时前")
        XCTAssertTrue(formatUpdatedAgo(now.addingTimeInterval(-3 * 86400), now: now).contains("/"),
                      "超过一天应显示日期")
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

    // MARK: - 快照默认值（isStale 新字段不改变既有构造行为）

    func testSnapshotDefaultsNotStale() {
        XCTAssertFalse(ProviderSnapshot.failed("X", "err").isStale)
        XCTAssertFalse(ProviderSnapshot.absent("X").isStale)
        XCTAssertTrue(ProviderSnapshot.absent("X").hidden)
    }
}
