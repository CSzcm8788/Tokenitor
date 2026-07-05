import SwiftUI

/// Token 页的周期切换。
enum TokenPeriod: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }

/// 十六进制颜色（Tokenscope 的排名调色板用固定 hex 值，浅/深色模式通用）。
extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Day/Week/Month 分段控件

struct PeriodSegmented: View {
    @Binding var period: TokenPeriod

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TokenPeriod.allCases, id: \.self) { p in
                Text(p.rawValue)
                    .font(.uiCaption)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(period == p ? Color.primary.opacity(0.12) : .clear)
                    )
                    .foregroundStyle(period == p ? Color.primary : Color.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { period = p }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - 涨跌徽标

struct DeltaBadge: View {
    let value: Double   // 百分比，正负均可

    var body: some View {
        let up = value >= 0
        // 用量/成本上涨是「坏事」→ 红；下降是「好事」→ 绿。
        let color = up ? Color(red: 0.88, green: 0.47, blue: 0.37) : GaugeColor.healthy
        Text("\(up ? "▲" : "▼")\(Int(abs(value).rounded()))%")
            .font(.num)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.opacity(up ? 0.16 : 0.14)))
            .foregroundStyle(color)
    }
}

// MARK: - 堆叠柱状图（output 在上，input+cache 在下）

struct TokenBarChart: View {
    let data: [SeriesPoint]
    var height: CGFloat = 84
    @State private var hoverIndex: Int? = nil

    private var maxV: Int { max(data.map { $0.total }.max() ?? 0, 1) }
    private var barSpacing: CGFloat { data.count > 10 ? 2 : 5 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                gridLines
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(data.enumerated()), id: \.offset) { i, d in
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.accentColor.opacity(0.55))
                                .frame(height: barHeight(d.output))
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: barHeight(d.input + d.cache))
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(hoverIndex == nil || hoverIndex == i || d.total == 0 ? 1 : 0.55)
                        .contentShape(Rectangle())
                        .onHover { h in hoverIndex = h ? i : (hoverIndex == i ? nil : hoverIndex) }
                        .help(d.total == 0 ? "No tokens · \(d.full)" : "\(formatTokens(d.total)) tokens · \(d.full)")
                    }
                }
            }
            .frame(height: height)

            HStack(spacing: barSpacing) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                    Text(d.label)
                        .font(.numMicro)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func barHeight(_ v: Int) -> CGFloat {
        guard v > 0 else { return 0 }
        return max(2, CGFloat(v) / CGFloat(maxV) * height)
    }

    private var gridLines: some View {
        GeometryReader { geo in
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { g in
                Path { p in
                    let y = geo.size.height * (1 - g)
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}

// MARK: - 成本环形图（按成本排名取 5 级绿色渐变，与 Tokenscope 一致）

struct CostDonutChart: View {
    let models: [ModelTokens]
    var size: CGFloat = 100
    var thickness: CGFloat = 15
    @State private var hoverIndex: Int? = nil

    private static let palette = ["1f9d63", "34c27e", "6ad0a0", "a7e3c5", "4b5a52"]
    private static let overflow = "79817b"

    private var ranked: [(m: ModelTokens, color: Color)] {
        models.sorted { $0.cost > $1.cost }.enumerated().map { i, m in
            (m, Color(hex: i < Self.palette.count ? Self.palette[i] : Self.overflow))
        }
    }
    private var total: Double { max(models.reduce(0) { $0 + $1.cost }, 1e-9) }
    private var centerAmount: Double {
        if let i = hoverIndex, i < ranked.count { return ranked[i].m.cost }
        return models.reduce(0) { $0 + $1.cost }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                ForEach(Array(ranked.enumerated()), id: \.offset) { i, item in
                    let frac = item.m.cost / total
                    let start = ranked.prefix(i).reduce(0.0) { $0 + $1.m.cost / total }
                    Circle()
                        .trim(from: start, to: min(1, start + frac))
                        .stroke(item.color, style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .opacity(hoverIndex == nil || hoverIndex == i ? 1 : 0.32)
                        .contentShape(Circle())
                        .onHover { h in hoverIndex = h ? i : (hoverIndex == i ? nil : hoverIndex) }
                }
                Text(formatUSDExact(centerAmount))
                    .font(.numTitle)
                    .foregroundStyle(hoverIndex.flatMap { $0 < ranked.count ? ranked[$0].color : nil } ?? Color.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, thickness)
            }
            .frame(width: size, height: size)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(ranked.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(item.color).frame(width: 7, height: 7)
                        Text(item.m.model)
                            .font(.uiCaption).fontWeight(hoverIndex == i ? .semibold : .medium)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(formatUSDExact(item.m.cost))
                            .font(.num)
                            .foregroundStyle(hoverIndex == i ? item.color : Color.secondary)
                    }
                    .opacity(hoverIndex == nil || hoverIndex == i ? 1 : 0.45)
                    .contentShape(Rectangle())
                    .onHover { h in hoverIndex = h ? i : (hoverIndex == i ? nil : hoverIndex) }
                }
            }
        }
    }
}

// MARK: - 迷你曲线图（Requests / Cost trend 小卡片用）

struct TokenSparkline: View {
    let values: [Double]
    var width: CGFloat = 52
    var height: CGFloat = 20

    private var points: [CGPoint] {
        let vs = values.count >= 2 ? values : (values.isEmpty ? [0, 0] : [values[0], values[0]])
        let maxV = vs.max() ?? 0, minV = vs.min() ?? 0
        let range = max(maxV - minV, 1e-9)
        let n = vs.count
        return vs.enumerated().map { i, v in
            CGPoint(x: n > 1 ? CGFloat(i) / CGFloat(n - 1) * width : width / 2,
                    y: height - CGFloat((v - minV) / range) * height)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.32), Color.accentColor.opacity(0)],
                            startPoint: .top, endPoint: .bottom)
                .mask(areaPath)
            linePath.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }

    private var linePath: Path {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: first)
            for pt in points.dropFirst() { p.addLine(to: pt) }
        }
    }
    private var areaPath: Path {
        Path { p in
            guard let first = points.first, let last = points.last else { return }
            p.move(to: CGPoint(x: first.x, y: height))
            p.addLine(to: first)
            for pt in points.dropFirst() { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: last.x, y: height))
            p.closeSubpath()
        }
    }
}
