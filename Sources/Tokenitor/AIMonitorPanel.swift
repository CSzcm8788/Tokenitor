import SwiftUI

/// 单个 AI 的玻璃卡片。detailed 用于主窗口，compact 用于刘海。
struct AIMonitorPanel: View {
    let snap: ProviderSnapshot
    var compact: Bool = false
    var warnAt: Double
    var critAt: Double
    /// 数据的刷新时间：非 compact 卡片在标题下方显示「更新于 N分钟前」。
    var updatedAt: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            // 标题行 + 更新时间（相对时间，随每轮刷新重绘）
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.name)
                    .font(compact ? .uiCaption : .sectionTitle)
                if let t = updatedAt, !compact {
                    Text("更新于 \(formatUpdatedAgo(t))")
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                }
            }

            if let note = snap.note, !note.isEmpty, !compact {
                Text(note)
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if snap.ok {
                ForEach(Array(snap.windows.enumerated()), id: \.offset) { _, w in
                    windowRow(w)
                }
            } else if let err = snap.error {
                Text(err)
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: compact ? 12 : 16)
    }

    @ViewBuilder
    private func windowRow(_ w: UsageWindow) -> some View {
        let level = UsageLevel.from(remaining: w.remainingPercent, warnAt: warnAt, critAt: critAt)
        let color = levelColor(level)
        let cd = formatCountdown(to: w.resetsAt)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(w.label)
                    .font(.num)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("剩 \(Int(w.remainingPercent.rounded()))%")
                    .font(.num)
                if !cd.isEmpty {
                    Text("↻\(cd)")
                        .font(.uiCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            UsageBar(fraction: w.remainingPercent / 100, color: color, height: 6)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: w.remainingPercent)
        }
    }
}
