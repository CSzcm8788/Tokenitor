import SwiftUI

/// Token 页的周期切换。
enum TokenPeriod: String, CaseIterable {
    case day, week, month

    var label: String {
        switch self {
        case .day:   return L("日", "Day")
        case .week:  return L("周", "Week")
        case .month: return L("月", "Month")
        }
    }
}

/// 十六进制颜色（浅/深色模式通用的固定色值用）。
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
                Text(p.label)
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

// MARK: - 涨跌徽标（中性灰：用量涨跌是事实不是警报，红色留给配额告警）

struct DeltaBadge: View {
    let value: Double   // 百分比，正负均可

    var body: some View {
        Text("\(value >= 0 ? "▲" : "▼")\(Int(abs(value).rounded()))%")
            .font(.num)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.07)))
            .foregroundStyle(.secondary)
    }
}

// MARK: - 分组柱状图：每个时间点三根细柱（输入 / 缓存 / 输出）

/// 横向刻度线 0 / ½ / 顶（左侧标注量级），高亮组全亮、其余降透明度；
/// 输出量级通常远小于输入，给 2px 最小可见高度保底。
struct GroupedTokenChart: View {
    let data: [SeriesPoint]
    /// 高亮哪一组（周/月视图 = 最后一组「今天/本周」；日视图 = 当前小时段）。
    var highlightIndex: Int? = nil
    var height: CGFloat = 96
    @State private var hoverIndex: Int? = nil

    static let inputColor = Color.accentColor
    static let cacheColor = Color.accentColor.opacity(0.35)
    static let outputColor = Color(hex: "2E6BC7")   // 深蓝，浅/深色模式都可辨

    private var maxV: Int {
        max(data.flatMap { [$0.input, $0.cache, $0.output] }.max() ?? 0, 1)
    }
    private var groupSpacing: CGFloat { data.count > 10 ? 4 : 10 }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                axis
                ZStack {
                    gridLines
                    HStack(alignment: .bottom, spacing: groupSpacing) {
                        ForEach(Array(data.enumerated()), id: \.offset) { i, d in
                            group(d, index: i)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: height)
            }
            HStack(spacing: groupSpacing) {
                Color.clear.frame(width: axisWidth, height: 1)
                ForEach(Array(data.enumerated()), id: \.offset) { i, d in
                    Text(d.label)
                        .font(.numMicro)
                        .fontWeight(i == highlightIndex ? .semibold : .medium)
                        .foregroundStyle(i == highlightIndex ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private let axisWidth: CGFloat = 34

    /// 左侧刻度标注：顶 / 中 / 0，与三条网格线对齐。
    private var axis: some View {
        VStack(spacing: 0) {
            Text(formatTokens(maxV)).frame(maxHeight: 0, alignment: .top)
            Spacer()
            Text(formatTokens(maxV / 2))
            Spacer()
            Text("0").frame(maxHeight: 0, alignment: .bottom)
        }
        .font(.numMicro)
        .foregroundStyle(.tertiary)
        .frame(width: axisWidth, height: height, alignment: .trailing)
        .multilineTextAlignment(.trailing)
    }

    private var gridLines: some View {
        GeometryReader { geo in
            ForEach([0.0, 0.5, 1.0], id: \.self) { g in
                Path { p in
                    let y = geo.size.height * (1 - g)
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(Color.primary.opacity(g == 0 ? 0.14 : 0.06),
                        style: StrokeStyle(lineWidth: 1, dash: g == 0 ? [] : [3, 3]))
            }
        }
    }

    private func group(_ d: SeriesPoint, index i: Int) -> some View {
        let active = i == highlightIndex || hoverIndex == i
        return HStack(alignment: .bottom, spacing: 2) {
            bar(d.input, Self.inputColor)
            bar(d.cache, Self.cacheColor)
            bar(d.output, Self.outputColor)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .opacity(active || d.total == 0 ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { h in hoverIndex = h ? i : (hoverIndex == i ? nil : hoverIndex) }
        .help(d.total == 0
              ? L("\(d.full) · 无数据", "\(d.full) · no data")
              : L("\(d.full)：输入 \(formatTokens(d.input)) · 缓存 \(formatTokens(d.cache)) · 输出 \(formatTokens(d.output))",
                  "\(d.full): in \(formatTokens(d.input)) · cache \(formatTokens(d.cache)) · out \(formatTokens(d.output))"))
    }

    private func bar(_ v: Int, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: v > 0 ? max(2, CGFloat(v) / CGFloat(maxV) * height) : 0)
    }
}
