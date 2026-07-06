import SwiftUI

/// 社交平台官方图形标（GitHub Mark / X logo）的矢量渲染。
/// 属**指示性使用**（nominative use）：仅用于链接指向作者/项目在该平台的页面，
/// 不修改图形、不暗示背书——符合各平台品牌指南对链接场景的许可。
/// 单色填充、随系统主题着色，与全 app 图标语言一致；Telegram 用 SF `paperplane` 线性符号。
enum BrandIcon {
    /// GitHub Mark（viewBox 24×24）。
    static let github = SVGPathShape(d: """
        M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 \
        0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 \
        1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 \
        0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 \
        1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 \
        0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297 \
        c0-6.627-5.373-12-12-12
        """, viewBox: 24)

    /// X logo（viewBox 24×24，内部镂空用 even-odd 填充）。
    static let x = SVGPathShape(d: """
        M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154 \
        h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z
        """, viewBox: 24)
}

/// 极简 SVG path 解析器：支持 M/L/H/V/C/S/Z（绝对+相对、隐式命令重复），够用于内嵌图形标。
struct SVGPathShape: Shape {
    let d: String
    let viewBox: CGFloat   // 假定正方形 viewBox，等比缩放进 rect

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        var p = Path()
        var cur = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint? = nil   // S 命令反射用
        var lastCmd: Character = " "

        let tokens = Self.tokenize(d)
        var i = 0
        func nums(_ n: Int) -> [CGFloat]? {
            guard i + n <= tokens.count else { return nil }
            var out: [CGFloat] = []
            for k in 0..<n {
                guard case .num(let v) = tokens[i + k] else { return nil }
                out.append(v)
            }
            i += n
            return out
        }

        while i < tokens.count {
            var cmd: Character
            if case .cmd(let c) = tokens[i] { cmd = c; i += 1 }
            else {
                // 隐式重复：M/m 的重复按 SVG 规范降级为 L/l
                cmd = lastCmd == "M" ? "L" : (lastCmd == "m" ? "l" : lastCmd)
            }
            lastCmd = cmd
            let rel = cmd.isLowercase
            let base = rel ? cur : .zero

            switch Character(cmd.uppercased()) {
            case "M":
                guard let v = nums(2) else { return scaled(p, scale) }
                cur = CGPoint(x: base.x + v[0], y: base.y + v[1])
                subpathStart = cur
                p.move(to: cur)
                lastControl = nil
            case "L":
                guard let v = nums(2) else { return scaled(p, scale) }
                cur = CGPoint(x: base.x + v[0], y: base.y + v[1])
                p.addLine(to: cur)
                lastControl = nil
            case "H":
                guard let v = nums(1) else { return scaled(p, scale) }
                cur = CGPoint(x: (rel ? cur.x : 0) + v[0], y: cur.y)
                p.addLine(to: cur)
                lastControl = nil
            case "V":
                guard let v = nums(1) else { return scaled(p, scale) }
                cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + v[0])
                p.addLine(to: cur)
                lastControl = nil
            case "C":
                guard let v = nums(6) else { return scaled(p, scale) }
                let c1 = CGPoint(x: base.x + v[0], y: base.y + v[1])
                let c2 = CGPoint(x: base.x + v[2], y: base.y + v[3])
                cur = CGPoint(x: base.x + v[4], y: base.y + v[5])
                p.addCurve(to: cur, control1: c1, control2: c2)
                lastControl = c2
            case "S":
                guard let v = nums(4) else { return scaled(p, scale) }
                let c1 = lastControl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: base.x + v[0], y: base.y + v[1])
                cur = CGPoint(x: base.x + v[2], y: base.y + v[3])
                p.addCurve(to: cur, control1: c1, control2: c2)
                lastControl = c2
            case "Z":
                p.closeSubpath()
                cur = subpathStart
                lastControl = nil
            default:
                return scaled(p, scale)   // 未支持的命令：返回已解析部分
            }
        }
        return scaled(p, scale)
    }

    private func scaled(_ p: Path, _ scale: CGFloat) -> Path {
        p.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    // MARK: - 词法

    enum Token { case cmd(Character), num(CGFloat) }

    /// 拆成命令字母与数字（处理 "-.015-2.04"、".6.113" 这类压缩写法）。
    static func tokenize(_ d: String) -> [Token] {
        var out: [Token] = []
        var numBuf = ""
        func flush() {
            if !numBuf.isEmpty { out.append(.num(CGFloat(Double(numBuf) ?? 0))); numBuf = "" }
        }
        for ch in d {
            if ch.isLetter {
                flush()
                out.append(.cmd(ch))
            } else if ch == "-" {
                // 负号开启新数字（除非当前数字为空或以 e 结尾的科学计数，这里不需要）
                flush()
                numBuf = "-"
            } else if ch == "." {
                // 第二个小数点开启新数字（".6.113" → .6 与 .113）
                if numBuf.contains(".") { flush() }
                numBuf.append(ch)
            } else if ch.isNumber {
                numBuf.append(ch)
            } else {
                flush()   // 空白 / 逗号 / 换行
            }
        }
        flush()
        return out
    }
}
