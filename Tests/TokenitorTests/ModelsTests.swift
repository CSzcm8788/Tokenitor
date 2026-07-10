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

    // MARK: - 服务状态：组件级判定

    func testComponentIndicatorMapping() {
        XCTAssertNil(StatusMonitor.indicator(forComponentStatus: "operational"))
        XCTAssertEqual(StatusMonitor.indicator(forComponentStatus: "degraded_performance"), "minor")
        XCTAssertEqual(StatusMonitor.indicator(forComponentStatus: "under_maintenance"), "minor")
        XCTAssertEqual(StatusMonitor.indicator(forComponentStatus: "partial_outage"), "major")
        XCTAssertEqual(StatusMonitor.indicator(forComponentStatus: "major_outage"), "critical")
        XCTAssertNil(StatusMonitor.indicator(forComponentStatus: "something_new"))
    }

    /// 回归用例：FedRAMP（无关组件）降级不得让 Codex 显示「服务降级」——这正是此前长期误报的元凶。
    func testIrrelevantComponentDoesNotPolluteCodex() {
        let comps = [("FedRAMP", "degraded_performance"),
                     ("Codex API", "operational"),
                     ("Responses", "operational"),
                     ("Sites", "major_outage")]
        XCTAssertNil(StatusMonitor.summarize(kind: .codex, components: comps))
    }

    func testRelevantComponentTriggersWithDetail() {
        let comps = [("Codex API", "partial_outage"),
                     ("Responses", "degraded_performance"),
                     ("FedRAMP", "major_outage")]
        let s = StatusMonitor.summarize(kind: .codex, components: comps)
        XCTAssertEqual(s?.indicator, "major", "取相关组件里最差的级别")
        XCTAssertTrue(s?.detail.contains("Codex API") == true)
        XCTAssertFalse(s?.detail.contains("FedRAMP") == true, "无关组件不进明细")
    }

    func testCopilotAndClaudeRelevance() {
        XCTAssertEqual(StatusMonitor.summarize(kind: .copilot,
            components: [("Copilot AI Model Providers", "degraded_performance")])?.indicator, "minor")
        XCTAssertEqual(StatusMonitor.summarize(kind: .claude,
            components: [("Claude Code", "major_outage"), ("Claude Cowork", "major_outage")])?.detail
            .contains("Cowork"), false, "Cowork 不在 Claude 相关组件里")
    }

    func testWorstAcrossProviders() {
        XCTAssertNil(StatusMonitor.worst(of: [:]))
        XCTAssertEqual(StatusMonitor.worst(of: [
            "Codex": ServiceStatus(indicator: "minor", detail: "a"),
            "Claude": ServiceStatus(indicator: "critical", detail: "b"),
        ]), "critical")
    }

    // MARK: - 快照默认值（isStale 新字段不改变既有构造行为）

    func testSnapshotDefaultsNotStale() {
        XCTAssertFalse(ProviderSnapshot.failed("X", "err").isStale)
        XCTAssertFalse(ProviderSnapshot.absent("X").isStale)
        XCTAssertTrue(ProviderSnapshot.absent("X").hidden)
    }
}
