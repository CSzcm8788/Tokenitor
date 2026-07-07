import XCTest
@testable import Tokenitor

/// 增量 jsonl 扫描是 Token 聚合正确性的地基：offset 语义错了统计就会重复或漏计。
final class JSONLScannerTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("jsonl-test-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func write(_ s: String) throws { try Data(s.utf8).write(to: tmp) }
    private func append(_ s: String) throws {
        let fh = try FileHandle(forWritingTo: tmp)
        defer { try? fh.close() }
        try fh.seekToEnd(); try fh.write(contentsOf: Data(s.utf8))
    }
    private func collect(from offset: UInt64, chunkSize: Int = 1 << 20) -> (lines: [String], offset: UInt64) {
        var lines: [String] = []
        let o = JSONLScanner.scan(url: tmp, from: offset, chunkSize: chunkSize) { lines.append(String($0)) }
        return (lines, o)
    }

    func testBasicScanConsumesWholeFile() throws {
        try write("{\"a\":1}\n{\"a\":2}\n{\"a\":3}\n")
        let r = collect(from: 0)
        XCTAssertEqual(r.lines, ["{\"a\":1}", "{\"a\":2}", "{\"a\":3}"])
        XCTAssertEqual(r.offset, UInt64(try Data(contentsOf: tmp).count), "偏移应到文件末尾")
    }

    func testIncrementalAppendOnlyDeliversNewLines() throws {
        try write("{\"a\":1}\n")
        let first = collect(from: 0)
        XCTAssertEqual(first.lines.count, 1)

        try append("{\"a\":2}\n{\"a\":3}\n")
        let second = collect(from: first.offset)
        XCTAssertEqual(second.lines, ["{\"a\":2}", "{\"a\":3}"], "增量扫描只应给出新增行")

        let third = collect(from: second.offset)
        XCTAssertEqual(third.lines, [], "无新增时不回调")
        XCTAssertEqual(third.offset, second.offset)
    }

    func testUnterminatedTailIsNotConsumed() throws {
        try write("{\"a\":1}\n{\"half\":")   // 最后一行没写完（无换行）
        let r = collect(from: 0)
        XCTAssertEqual(r.lines, ["{\"a\":1}"], "半行不应被回调")
        // 补齐这行后，从上次偏移续读能拿到完整行
        try append("2}\n")
        let r2 = collect(from: r.offset)
        XCTAssertEqual(r2.lines, ["{\"half\":2}"])
    }

    func testMultibyteAcrossTinyChunks() throws {
        // 中文多字节 UTF-8 + 8 字节小块：切块不能破坏字符与行
        let lines = ["{\"名\":\"甲\"}", "{\"名\":\"乙乙乙\"}", "{\"名\":\"丙\"}"]
        try write(lines.joined(separator: "\n") + "\n")
        let r = collect(from: 0, chunkSize: 8)
        XCTAssertEqual(r.lines, lines)
    }

    func testTruncatedFileReturnsFileLength() throws {
        try write("{\"a\":1}\n")
        let len = UInt64(try Data(contentsOf: tmp).count)
        let r = collect(from: len + 100)   // 偏移超过文件长度（文件被截断/轮转）
        XCTAssertEqual(r.lines, [])
        XCTAssertEqual(r.offset, len, "应返回文件真实长度供调用方重置状态")
    }
}

/// 单趟提取：usage / timestamp / model 一次递归全拿到。
final class TokenAggregatorExtractTests: XCTestCase {

    func testExtractCollectsAllThree() {
        let obj: [String: Any] = [
            "timestamp": "2026-07-07T08:00:00Z",
            "message": [
                "model": "claude-sonnet-5",
                "usage": ["input_tokens": 100, "output_tokens": 20]
            ] as [String: Any]
        ]
        var info = TokenAggregator.LineInfo()
        TokenAggregator.extract(obj, usageKey: "usage", into: &info)
        XCTAssertEqual(info.timestamp, "2026-07-07T08:00:00Z")
        XCTAssertEqual(info.model, "claude-sonnet-5")
        XCTAssertEqual(info.usages.count, 1)
        XCTAssertEqual(info.usages.first?["input_tokens"] as? Int, 100)
    }

    func testExtractTsFallbackAndArrayNesting() {
        let obj: [String: Any] = [
            "ts": "2026-07-07T09:30:00Z",
            "events": [
                ["last_token_usage": ["input": 5, "output": 7]] as [String: Any],
                ["last_token_usage": ["input": 1, "output": 2]] as [String: Any],
            ]
        ]
        var info = TokenAggregator.LineInfo()
        TokenAggregator.extract(obj, usageKey: "last_token_usage", into: &info)
        XCTAssertEqual(info.timestamp, "2026-07-07T09:30:00Z")
        XCTAssertNil(info.model)
        XCTAssertEqual(info.usages.count, 2, "嵌套数组里的多个 usage 都要收集")
    }
}
