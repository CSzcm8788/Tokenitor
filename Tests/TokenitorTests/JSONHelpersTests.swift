import XCTest
@testable import Tokenitor

/// 宽容 JSON 解析是全项目最脆弱的部分（上游字段随时会变），必须有回归防线。
final class JSONHelpersTests: XCTestCase {

    func testDoubleCoercion() {
        XCTAssertEqual(JSON.double(42), 42)
        XCTAssertEqual(JSON.double(42.5), 42.5)
        XCTAssertEqual(JSON.double("13.7"), 13.7)
        XCTAssertNil(JSON.double("not-a-number"))
        XCTAssertNil(JSON.double(nil))
    }

    func testDateFromEpochSecondsAndMillis() {
        let seconds = 1_750_000_000.0
        XCTAssertEqual(JSON.date(NSNumber(value: seconds))?.timeIntervalSince1970, seconds)
        XCTAssertEqual(JSON.date(NSNumber(value: seconds * 1000))?.timeIntervalSince1970, seconds)
    }

    func testDateFromISO8601WithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(JSON.date("2026-07-06T08:00:00Z"))
        XCTAssertNotNil(JSON.date("2026-07-06T08:00:00.123Z"))
        XCTAssertNil(JSON.date("昨天"))
    }

    func testFirstValueIsCaseInsensitive() {
        let obj: [String: Any] = ["AccessToken": "x", "other": 1]
        XCTAssertEqual(JSON.firstValue(in: obj, keys: ["accesstoken"]) as? String, "x")
        XCTAssertNil(JSON.firstValue(in: obj, keys: ["missing"]))
    }

    func testFindWindowObjectsAndExtractPercent() {
        let root: [String: Any] = [
            "five_hour": ["used_percent": 37.5, "resets_in_seconds": 3600],
            "limits": ["seven_day": ["utilization": 80]],
            "spend": ["percent_used": 12]   // 调用方负责按键名过滤 spend
        ]
        let found = JSON.findWindowObjects(root)
        XCTAssertEqual(found.count, 3)
        let fiveHour = found.first { $0.key == "five_hour" }?.dict
        XCTAssertEqual(fiveHour.flatMap { JSON.extractPercent($0) }, 37.5)
    }

    func testExtractResetRelativeSeconds() {
        let now = Date()
        let d = JSON.extractReset(["resets_in_seconds": 120], now: now)
        XCTAssertEqual(d?.timeIntervalSince(now) ?? 0, 120, accuracy: 0.001)
    }

    func testExtractResetAbsoluteTimestamp() {
        let d = JSON.extractReset(["resets_at": "2026-07-06T12:00:00Z"])
        XCTAssertNotNil(d)
    }
}
