import XCTest
@testable import Tokenitor

/// 档位「可信才显示」映射：错误的档位胶囊比没有更糟，白名单之外一律 nil。
final class PlanTierTests: XCTestCase {

    func testClaudeMapping() {
        XCTAssertEqual(PlanTier.claude("max"), "Max")
        XCTAssertEqual(PlanTier.claude("Pro"), "Pro")
        XCTAssertEqual(PlanTier.claude("enterprise"), "Enterprise")
        XCTAssertNil(PlanTier.claude("free"), "free 不显示")
        XCTAssertNil(PlanTier.claude(nil))
        XCTAssertNil(PlanTier.claude("something_new"))
    }

    func testCodexMapping() {
        XCTAssertEqual(PlanTier.codex("plus"), "Plus")
        XCTAssertEqual(PlanTier.codex("PRO"), "Pro")
        XCTAssertNil(PlanTier.codex("free"), "free claim 可能陈旧、与实际配额矛盾 → 不显示")
        XCTAssertNil(PlanTier.codex(nil))
    }

    func testCopilotMapping() {
        XCTAssertNil(PlanTier.copilot("individual"), "individual 是账户类型不是档位")
        XCTAssertEqual(PlanTier.copilot("copilot_pro"), "Pro")
        XCTAssertEqual(PlanTier.copilot("pro_plus"), "Pro+")
        XCTAssertEqual(PlanTier.copilot("business"), "Business")
        XCTAssertEqual(PlanTier.copilot("free"), "Free")
        XCTAssertNil(PlanTier.copilot(nil))
    }

    func testJWTPayloadDecode() {
        // header.payload.signature，payload = {"https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}
        let payload = ["https://api.openai.com/auth": ["chatgpt_plan_type": "plus"]]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "eyJhbGciOiJSUzI1NiJ9.\(b64).sig"
        let claims = PlanTier.decodeJWTPayload(jwt)
        let auth = claims?["https://api.openai.com/auth"] as? [String: Any]
        XCTAssertEqual(auth?["chatgpt_plan_type"] as? String, "plus")
        XCTAssertNil(PlanTier.decodeJWTPayload("not-a-jwt"))
    }

    func testCacheSavings() {
        // sonnet：input $3/M、cacheRead $0.30/M → 每 M 缓存读省 $2.70
        let m = ModelTokens(model: "claude-sonnet-5",
                            counts: TokenCounts(input: 0, output: 0, cacheRead: 2_000_000, cacheWrite: 0),
                            cost: 0)
        XCTAssertEqual(Pricing.cacheSavings([m]), 5.4, accuracy: 0.001)
        // 无定价模型不计入
        let unknown = ModelTokens(model: "mystery", counts: TokenCounts(input: 0, output: 0, cacheRead: 1_000_000, cacheWrite: 0), cost: 0)
        XCTAssertEqual(Pricing.cacheSavings([unknown]), 0)
    }
}
