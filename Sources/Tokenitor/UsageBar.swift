import SwiftUI

/// 统一的剩余用量进度条：胶囊轨道 + 胶囊填充，主窗口与刘海面板共用，
/// 保证两处「同色同形」。fraction 为剩余比例（0…1），color 取自三态状态色板。
struct UsageBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
