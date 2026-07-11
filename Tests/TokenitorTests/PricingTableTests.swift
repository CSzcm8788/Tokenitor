import XCTest
@testable import Tokenitor

/// 社区定价表（LiteLLM 快照）的解析 / 规范化 / 择优逻辑。
/// 测试环境没有 app bundle 资源，PricingTable.shared 为空 → Pricing 走旧表兜底，
/// 这里用 fixture 直接喂 build(from:) 验证。
final class PricingTableTests: XCTestCase {

    private let fixture = """
    {
      "claude-fable-5": {"input_cost_per_token": 1e-05, "output_cost_per_token": 5e-05,
                         "cache_read_input_token_cost": 1e-06, "cache_creation_input_token_cost": 1.25e-05},
      "anthropic.claude-fable-5": {"input_cost_per_token": 9e-06, "output_cost_per_token": 4e-05},
      "azure_ai/gpt-5.5": {"input_cost_per_token": 5e-06, "output_cost_per_token": 3e-05,
                           "cache_read_input_token_cost": 5e-07},
      "openai/gpt-5.5": {"input_cost_per_token": 4e-06, "output_cost_per_token": 2.8e-05},
      "deepinfra/deepseek-v4-flash": {"input_cost_per_token": 3e-07, "output_cost_per_token": 1e-06},
      "anthropic.claude-3-5-sonnet-20240620-v1:0": {"input_cost_per_token": 3e-06, "output_cost_per_token": 1.5e-05},
      "no-cost-model": {"litellm_provider": "x"}
    }
    """.data(using: .utf8)!

    func testBuildConvertsToPerMillion() {
        let t = PricingTable.build(from: fixture)
        let fable = t["claude-fable-5"]
        XCTAssertEqual(fable?.input ?? 0, 10, accuracy: 0.001, "1e-05/token → $10/M")
        XCTAssertEqual(fable?.cacheRead ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(fable?.cacheWrite ?? 0, 12.5, accuracy: 0.001)
        XCTAssertNil(t["no-cost-model"], "无成本字段的条目不收录")
    }

    func testBarePreferredOverPrefixed() {
        // 裸名 claude-fable-5（$10/M）应胜过 anthropic. 前缀条目（$9/M）
        let t = PricingTable.build(from: fixture)
        XCTAssertEqual(t["claude-fable-5"]?.input ?? 0, 10, accuracy: 0.001)
    }

    func testVendorPreferredOverReseller() {
        // openai/gpt-5.5（一方，$4/M）应胜过 azure_ai/gpt-5.5（转售，$5/M）
        let t = PricingTable.build(from: fixture)
        XCTAssertEqual(t["gpt-5.5"]?.input ?? 0, 4, accuracy: 0.001)
    }

    func testNormalize() {
        XCTAssertEqual(PricingTable.normalize("azure_ai/GPT-5.5"), "gpt-5.5")
        XCTAssertEqual(PricingTable.normalize("anthropic.claude-fable-5"), "claude-fable-5")
        XCTAssertEqual(PricingTable.normalize("anthropic.claude-3-5-sonnet-20240620-v1:0"),
                       "claude-3-5-sonnet-20240620-v1")
        XCTAssertEqual(PricingTable.normalize("deepseek-v4-flash"), "deepseek-v4-flash")
    }

    func testSourceScore() {
        XCTAssertEqual(PricingTable.sourceScore("gpt-5.5"), 3, "裸名（自身含点）最高优先")
        XCTAssertEqual(PricingTable.sourceScore("anthropic.claude-fable-5"), 2)
        XCTAssertEqual(PricingTable.sourceScore("openai/gpt-5.5"), 2)
        XCTAssertEqual(PricingTable.sourceScore("azure_ai/gpt-5.5"), 1)
        XCTAssertEqual(PricingTable.sourceScore("deepinfra/deepseek-v4-flash"), 1)
    }

    func testLegacyFallbackStillWorks() {
        // 测试环境快照为空：老关键字兜底必须继续生效（sonnet $3/M + $15/M）
        let c = TokenCounts(input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(Pricing.cost(c, model: "claude-sonnet-5"), 18.0, accuracy: 0.0001)
    }
}
