import SwiftUI

/// 刘海面板内容：一个统一的玻璃容器，里面是各 AI 的轻量行。
struct NotchCardsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {   // AI 块间距放宽一档，避免拥挤
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Tokenitor")
                    .font(.pageTitle)
                    .foregroundStyle(.primary)
                Spacer()
                if let t = store.lastUpdate {
                    Text(L("更新于 ", "Updated ") + formatUpdatedAgo(t))
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.snapshots.isEmpty {
                Text(L("暂无数据（点 Dock 图标打开主窗口）",
                       "No data yet (click the Dock icon to open the main window)"))
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.snapshots.enumerated()), id: \.element.name) { idx, snap in
                    // AI 之间的分隔线：系统 Divider 在深色玻璃上过淡（难以分清相邻 AI），
                    // 改用显式 primary 低透明度细线，深浅两种外观下都清晰但不抢眼。
                    if idx > 0 {
                        Rectangle().fill(Color.primary.opacity(0.16)).frame(height: 1)
                            .padding(.vertical, 1)
                    }
                    providerBlock(snap)
                }
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)   // 300 → 360：此前整体偏小，胶囊多时更显局促
        .glassCard(cornerRadius: 18)
        .padding(6)            // 面板外留一点边，避免贴边
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func providerBlock(_ snap: ProviderSnapshot) -> some View {
        let warn = Settings.shared.warnAt, crit = Settings.shared.critAt
        VStack(alignment: .leading, spacing: 4) {
            // 与仪表 / 弹层完全同源的两行卡片头（名字独占一行 + 胶囊行 + 细分隔线）
            ProviderCardHeader(snap: snap,
                               serviceStatus: store.serviceStatus[snap.name])
            if snap.ok {
                ForEach(Array(snap.windows.enumerated()), id: \.offset) { _, w in
                    let level = UsageLevel.from(remaining: w.remainingPercent, warnAt: warn, critAt: crit)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle().fill(levelColor(level)).frame(width: 7, height: 7)
                            Text(w.label)
                                .font(.num)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(L("剩 \(Int(w.remainingPercent.rounded()))%",
                                   "\(Int(w.remainingPercent.rounded()))% left"))
                                .font(.num)
                            let cd = formatCountdown(to: w.resetsAt)
                            if !cd.isEmpty {
                                Text("↻\(cd)").font(.uiCaption).foregroundStyle(.tertiary)
                            }
                        }
                        // 细进度条：与主窗口同色同形（统一三态色板）
                        UsageBar(fraction: w.remainingPercent / 100, color: levelColor(level), height: 6, segmented: w.label == "5h")
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: w.remainingPercent)
                    }
                }
            } else if let err = snap.error {
                Text(err).font(.uiCaption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}
