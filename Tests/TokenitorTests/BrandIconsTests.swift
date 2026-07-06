import XCTest
import SwiftUI
@testable import Tokenitor

/// SVG path 解析器与内嵌图形标的回归测试。
final class BrandIconsTests: XCTestCase {

    func testTokenizeCompressedNumbers() {
        // "-.015-2.04" 与 ".6.113" 这类压缩写法必须拆成独立数字
        let tokens = SVGPathShape.tokenize("M-.015-2.04c.6.113.82-.258.82-.577Z")
        var nums: [CGFloat] = []
        var cmds: [Character] = []
        for t in tokens {
            switch t {
            case .num(let v): nums.append(v)
            case .cmd(let c): cmds.append(c)
            }
        }
        XCTAssertEqual(cmds, ["M", "c", "Z"])
        XCTAssertEqual(nums.count, 8)
        XCTAssertEqual(Double(nums[0]), -0.015, accuracy: 0.0001)
        XCTAssertEqual(Double(nums[2]), 0.6, accuracy: 0.0001)
        XCTAssertEqual(Double(nums[3]), 0.113, accuracy: 0.0001)
    }

    func testGitHubMarkParsesWithinViewBox() {
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        let path = BrandIcon.github.path(in: rect)
        XCTAssertFalse(path.isEmpty, "GitHub mark 解析结果不应为空")
        let b = path.boundingRect
        XCTAssertTrue(b.minX >= -0.5 && b.minY >= -0.5 && b.maxX <= 24.5 && b.maxY <= 24.5,
                      "路径应落在 viewBox 内，实际 \(b)")
        XCTAssertGreaterThan(b.width, 20, "猫标应基本铺满 viewBox 宽度")
    }

    func testXLogoParsesWithTwoSubpaths() {
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        let path = BrandIcon.x.path(in: rect)
        XCTAssertFalse(path.isEmpty)
        let b = path.boundingRect
        XCTAssertTrue(b.maxX <= 24.5 && b.maxY <= 24.5, "路径应落在 viewBox 内，实际 \(b)")
        // 外轮廓 + 内部镂空 = 两个子路径（用 move 次数近似判断）
        var moves = 0
        path.forEach { if case .move = $0 { moves += 1 } }
        XCTAssertEqual(moves, 2)
    }
}
