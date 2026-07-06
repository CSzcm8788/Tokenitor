import XCTest
@testable import Tokenitor

final class PricingTests: XCTestCase {

    func testKnownModelCost() {
        // sonnet：input $3/M、output $15/M
        let c = TokenCounts(input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(Pricing.cost(c, model: "claude-sonnet-5"), 18.0, accuracy: 0.0001)
    }

    func testUnknownModelCostsZero() {
        let c = TokenCounts(input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(Pricing.cost(c, model: "some-unknown-model"), 0)
    }

    func testSubstringMatchPrefersMoreSpecificEntry() {
        // "gpt-5-mini" 必须命中 mini 档而不是 "gpt-5" 档（表内顺序敏感，防止有人重排）
        let c = TokenCounts(input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(Pricing.cost(c, model: "gpt-5-mini"), 0.25, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(c, model: "gpt-5"), 1.25, accuracy: 0.0001)
    }

    func testTokenCountsArithmetic() {
        var a = TokenCounts(input: 1, output: 2, cacheRead: 3, cacheWrite: 4)
        a += TokenCounts(input: 10, output: 20, cacheRead: 30, cacheWrite: 40)
        XCTAssertEqual(a.total, 110)
        XCTAssertFalse(a.isZero)
        XCTAssertTrue(TokenCounts().isZero)
    }
}
