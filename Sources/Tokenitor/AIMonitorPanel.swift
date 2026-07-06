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
    /// 数据的刷新时间：hero 显示为胶囊（detailed/compact 由面板级统一显示）。
    var updatedAt: Date? = nil
    /// 主窗口仪表页的大卡片形态（统计瓦片 + 胶囊行）。
    var hero: Bool = false
    /// 厂商服务状态（statuspage indicator：minor/major/critical），hero 显示为胶囊。
    var serviceIndicator: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : (hero ? 12 : 10)) {
            if hero { heroHeader } else { plainHeader }

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

    // MARK: - 头部

    /// detailed / compact：纯标题（卡片下不挂小字，更新时间由面板级统一显示）。
    private var plainHeader: some View {
        Text(snap.name)
            .font(compact ? .uiCaption : .sectionTitle)
    }

    /// hero：大标题 + 状态 / 来源 / 套餐 / 服务状态 / 更新时间胶囊行。
    private var heroHeader: some View {
        HStack(spacing: 8) {
            Text(snap.name).font(.pageTitle)
            statusChip
            if let kind = AIKind.from(name: snap.name) {
                chip(kind.sourceTag, fg: .secondary, bg: Color.primary.opacity(0.06))
            }
            if let plan = snap.plan, !plan.isEmpty {
                chip(plan, fg: .secondary, bg: Color.primary.opacity(0.06))
            }
            serviceChip
            Spacer(minLength: 0)
            if let t = updatedAt {
                chip(L("更新于 ", "Updated ") + formatUpdatedAgo(t),
                     fg: .secondary, bg: Color.primary.opacity(0.06))
            }
        }
    }

    /// 厂商服务状态胶囊（来自各家公开 status page；正常时不显示）。
    @ViewBuilder
    private var serviceChip: some View {
        switch serviceIndicator {
        case "minor":
            chip(L("服务降级", "Degraded"), fg: GaugeColor.warning, bg: GaugeColor.warning.opacity(0.16))
        case "major", "critical":
            chip(L("服务中断", "Outage"), fg: GaugeColor.critical, bg: GaugeColor.critical.opacity(0.14))
        default:
            EmptyView()
        }
    }

    /// 状态胶囊：LIVE（实时）/ 缓存（限流等展示旧数据）/ 离线（读取失败）。
    @ViewBuilder
    private var statusChip: some View {
        if snap.ok && !snap.isStale {
            chip("LIVE", fg: GaugeColor.healthy, bg: GaugeColor.healthy.opacity(0.16))
        } else if snap.isStale {
            chip(L("缓存", "Cached"), fg: GaugeColor.warning, bg: GaugeColor.warning.opacity(0.16))
        } else {
            chip(L("离线", "Offline"), fg: GaugeColor.critical, bg: GaugeColor.critical.opacity(0.14))
        }
    }

    private func chip(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .fixedSize()          // 胶囊永不折行（窄卡片上「更新于 …」曾被折成两行）
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(Capsule().fill(bg))
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
                Text(L("剩 \(Int(w.remainingPercent.rounded()))%",
                       "\(Int(w.remainingPercent.rounded()))% left"))
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
