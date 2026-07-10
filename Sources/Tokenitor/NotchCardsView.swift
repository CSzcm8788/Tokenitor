import SwiftUI

/// 刘海面板内容：一个统一的玻璃容器，里面是各 AI 的轻量行。
struct NotchCardsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Tokenitor")
                    .font(.sectionTitle)
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
                    if idx > 0 { Divider().opacity(0.4) }
                    providerBlock(snap)
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .glassCard(cornerRadius: 18)
        .padding(6)            // 面板外留一点边，避免贴边
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func providerBlock(_ snap: ProviderSnapshot) -> some View {
        let warn = Settings.shared.warnAt, crit = Settings.shared.critAt
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snap.name).font(.uiCaption)
                // 与仪表 / 弹层统一的胶囊行（状态 / 来源 / 档位 / 服务状态）
                ProviderChipsRow(snap: snap,
                                 serviceIndicator: store.serviceStatus[snap.name],
                                 compact: true)
                Spacer()
            }
            if snap.ok {
                ForEach(Array(snap.windows.enumerated()), id: \.offset) { _, w in
                    let level = UsageLevel.from(remaining: w.remainingPercent, warnAt: warn, critAt: crit)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(levelColor(level)).frame(width: 6, height: 6)
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
                        UsageBar(fraction: w.remainingPercent / 100, color: levelColor(level), height: 5)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: w.remainingPercent)
                    }
                }
            } else if let err = snap.error {
                Text(err).font(.uiCaption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}
