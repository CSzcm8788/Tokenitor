import SwiftUI

/// 统一的剩余用量进度条：胶囊轨道 + 胶囊填充，主窗口 / 弹层 / 刘海面板共用，
/// 保证三处「同色同形」。fraction 为剩余比例（0…1），color 取自三态状态色板。
/// segmented 仅用于 **5 小时窗口**：0–20 / 20–50 / 50–100 三段、段间留刻度缺口，
/// 短周期内「还剩多少档」一眼可读；周/月等长周期窗口保持整条，避免满屏刻度噪声。
struct UsageBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6
    var segmented: Bool = false

    /// 分段边界（剩余比例）：0–20% / 20–50% / 50–100%。
    private static let segments: [(lo: Double, hi: Double)] = [(0, 0.2), (0.2, 0.5), (0.5, 1.0)]

    var body: some View {
        GeometryReader { geo in
            let f = max(0, min(1, fraction))
            if segmented {
                let gap: CGFloat = 2
                let usable = geo.size.width - gap * CGFloat(Self.segments.count - 1)
                HStack(spacing: gap) {
                    ForEach(Array(Self.segments.enumerated()), id: \.offset) { _, seg in
                        let segWidth = max(0, (seg.hi - seg.lo) * usable)
                        let fillFraction = min(max((f - seg.lo) / (seg.hi - seg.lo), 0), 1)
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.12))
                            Capsule(style: .continuous)
                                .fill(color)
                                .frame(width: fillFraction * segWidth)
                        }
                        .frame(width: segWidth)
                    }
                }
            } else {
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: f * geo.size.width)
                }
            }
        }
        .frame(height: height)
    }
}
