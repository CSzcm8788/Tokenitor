import XCTest
@testable import Tokenitor

/// 调试转储脱敏是安全关键路径：一次疏漏就是凭证明文落盘。
final class RedactionTests: XCTestCase {

    func testSecretKeysAreRedactedByName() throws {
        let input: [String: Any] = [
            "access_token": "plain-secret-value",
            "refreshToken": "another-secret",
            "oauth_token": "gho_abcdefghijklmnopqrstuvwxyz123456",
            "used_percent": 42.0,
            "nested": ["api_key": "k-123", "label": "5h"]
        ]
        let out = DebugLog.redactJSON(input) as! [String: Any]
        XCTAssertEqual(out["access_token"] as? String, "«redacted»")
        XCTAssertEqual(out["refreshToken"] as? String, "«redacted»")
        XCTAssertEqual(out["oauth_token"] as? String, "«redacted»")
        XCTAssertEqual(out["used_percent"] as? Double, 42.0, "非敏感字段不得被误伤")
        let nested = out["nested"] as! [String: Any]
        XCTAssertEqual(nested["api_key"] as? String, "«redacted»")
        XCTAssertEqual(nested["label"] as? String, "5h")
    }

    func testTokenPatternsAreRedactedInsideStrings() {
        let cases = [
            "prefix sk-ant-abc123DEF456ghi789 suffix",
            "sk-1234567890abcdef1234 embedded",
            "gho_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345",
            "ghp_abcdefghijklmnopqrst0123456789",
            "jwt eyJhbGciOi.eyJzdWIiOi.SflKxwRJSM"
        ]
        for s in cases {
            let out = DebugLog.redactString(s)
            XCTAssertTrue(out.contains("«redacted»"), "未脱敏: \(s)")
        }
    }

    func testPlainTextSurvivesRedaction() {
        let s = "weekly 窗口剩余 63%，重置于 2h30m 后"
        XCTAssertEqual(DebugLog.redactString(s), s)
    }
}
