import SwiftUI

/// 单个 AI 的玻璃卡片，三种形态：
///  · hero     —— 主窗口仪表页：标题 + 状态/来源/更新时间胶囊 + 大数字统计瓦片 + 用量条
///  · detailed —— 菜单栏弹层：标题 + 更新时间副标题 + 用量条（紧凑速览）
///  · compact  —— 刘海面板：极简
struct AIMonitorPanel: View {
    let snap: ProviderSnapshot
    var compact: Bool = false
    var warnAt: Double
    var critAt: Double
    /// 数据的刷新时间：hero 显示为胶囊，detailed 显示在标题下方。
    var updatedAt: Date? = nil
    /// 主窗口仪表页的大卡片形态（统计瓦片 + 胶囊行）。
    var hero: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : (hero ? 12 : 10)) {
            if hero { heroHeader } else { plainHeader }

            if let note = snap.note, !note.isEmpty, !compact {
                Text(note)
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if snap.ok {
                if hero && !snap.windows.isEmpty {
                    statTiles
                    Text("用量")
                        .font(.uiLabel)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
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

    // MARK: - 头部

    /// detailed / compact：标题 +（detailed）更新时间副标题。
    private var plainHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snap.name)
                .font(compact ? .uiCaption : .sectionTitle)
            if let t = updatedAt, !compact {
                Text("更新于 \(formatUpdatedAgo(t))")
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// hero：大标题 + 状态 / 来源 / 更新时间胶囊行。
    private var heroHeader: some View {
        HStack(spacing: 8) {
            Text(snap.name).font(.pageTitle)
            statusChip
            if let kind = AIKind.from(name: snap.name) {
                chip(kind.sourceTag, fg: .secondary, bg: Color.primary.opacity(0.06))
            }
            Spacer(minLength: 0)
            if let t = updatedAt {
                chip("更新于 \(formatUpdatedAgo(t))", fg: .secondary, bg: Color.primary.opacity(0.06))
            }
        }
    }

    /// 状态胶囊：LIVE（实时）/ 缓存（限流等展示旧数据）/ 离线（读取失败）。
    @ViewBuilder
    private var statusChip: some View {
        if snap.ok && !snap.isStale {
            chip("LIVE", fg: GaugeColor.healthy, bg: GaugeColor.healthy.opacity(0.16))
        } else if snap.isStale {
            chip("缓存", fg: GaugeColor.warning, bg: GaugeColor.warning.opacity(0.16))
        } else {
            chip("离线", fg: GaugeColor.critical, bg: GaugeColor.critical.opacity(0.14))
        }
    }

    private func chip(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(Capsule().fill(bg))
    }

    // MARK: - 统计瓦片（每个窗口一块：标签 + 大数字剩余% + 重置倒计时）

    private var statTiles: some View {
        HStack(spacing: 10) {
            ForEach(Array(snap.windows.enumerated()), id: \.offset) { _, w in
                statTile(w)
            }
        }
    }

    private func statTile(_ w: UsageWindow) -> some View {
        let level = UsageLevel.from(remaining: w.remainingPercent, warnAt: warnAt, critAt: critAt)
        let cd = formatCountdown(to: w.resetsAt)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(w.label.uppercased()) 剩余")
                .font(.uiLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(Int(w.remainingPercent.rounded()))%")
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(levelColor(level))
            Text(cd.isEmpty ? "—" : "↻ \(cd) 后重置")
                .font(.uiCaption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    // MARK: - 用量条

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
