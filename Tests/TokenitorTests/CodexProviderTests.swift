import XCTest
@testable import Tokenitor

/// Codex 增量读取的行解析：巨行截断垃圾、正常事件、无 rate_limits 行。
final class CodexProviderTests: XCTestCase {

    func testParseNormalRateLimitsLine() {
        let line: Substring = """
        {"timestamp":"2026-07-12T04:30:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":41.0,"window_minutes":300,"resets_at":1783694799},"plan_type":"plus"}}}
        """
        let hit = CodexProvider.parseRateLimitsLine(line)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.0["plan_type"] as? String, "plus")
        XCTAssertNotNil(hit?.1, "应取到该行自身的事件时间戳")
    }

    func testParseGarbagePartialLine() {
        // 模拟从巨行中间起读产生的截断垃圾（含关键字但不是合法 JSON）
        let line: Substring = "utput text ... rate_limits ... broken json"
        XCTAssertNil(CodexProvider.parseRateLimitsLine(line))
    }

    /// 端到端增量语义：首轮读到事件 A；追加巨行 + 事件 B 后，第二轮必须跟上 B（偏移推进不丢新事件）。
    func testIncrementalPicksUpNewEventAfterGiantLine() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenitor-codex-\(UUID().uuidString)/2026/07/12", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("rollout-test.jsonl")

        func event(_ used: Double, ts: String) -> String {
            "{\"timestamp\":\"\(ts)\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"primary\":{\"used_percent\":\(used),\"window_minutes\":300},\"secondary\":{\"used_percent\":10.0,\"window_minutes\":10080},\"plan_type\":\"plus\"}}}\n"
        }
        try event(40.0, ts: "2026-07-12T05:00:00Z").write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(sessionsDir: dir.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent())

        func fetchSync() -> ProviderSnapshot {
            let exp = expectation(description: "fetch")
            var snap: ProviderSnapshot!
            provider.fetch { snap = $0; exp.fulfill() }
            wait(for: [exp], timeout: 5)
            return snap
        }

        let first = fetchSync()
        XCTAssertEqual(first.windows.first?.usedPercent, 40.0)

        // 追加一条 2MB 的无关巨行（模拟长任务工具输出）+ 新事件 B
        let giant = "{\"type\":\"message\",\"content\":\"" + String(repeating: "x", count: 2_000_000) + "\"}\n"
        let h = try FileHandle(forWritingTo: file)
        h.seekToEndOfFile()
        h.write(giant.data(using: .utf8)!)
        h.write(event(60.0, ts: "2026-07-12T05:10:00Z").data(using: .utf8)!)
        try h.close()

        let second = fetchSync()
        XCTAssertEqual(second.windows.first?.usedPercent, 60.0, "第二轮增量读取必须吃到巨行之后的新事件")
        XCTAssertNotNil(second.dataAsOf)
    }

    func testParseCredits() {
        // 官方 balance 是字符串；余额 0 → nil（胶囊隐藏）
        let (n1, u1) = CodexProvider.parseCredits(["has_credits": true, "unlimited": false, "balance": "4"])
        XCTAssertEqual(n1, 4); XCTAssertFalse(u1)
        let (n2, _) = CodexProvider.parseCredits(["has_credits": false, "unlimited": false, "balance": "0"])
        XCTAssertNil(n2)
        let (n3, u3) = CodexProvider.parseCredits(["unlimited": true, "balance": "0"])
        XCTAssertNil(n3); XCTAssertTrue(u3)
        let (n4, u4) = CodexProvider.parseCredits(nil)
        XCTAssertNil(n4); XCTAssertFalse(u4)
    }

    func testParseLineWithoutRateLimits() {
        let line: Substring = #"{"timestamp":"2026-07-12T04:30:00Z","type":"message","content":"hello"}"#
        XCTAssertNil(CodexProvider.parseRateLimitsLine(line))
    }
}
