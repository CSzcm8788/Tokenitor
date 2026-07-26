import SwiftUI

/// 三处界面（仪表 hero / 菜单栏弹层 / 刘海面板）**统一**的胶囊行：
/// 状态（LIVE/缓存/离线）+ 来源（本地/社区）+ 订阅档位 + 厂商服务状态。
/// 同一份快照在任何界面长相一致；改胶囊只改这里。
struct ProviderChipsRow: View {
    let snap: ProviderSnapshot
    var serviceStatus: ServiceStatus? = nil
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            statusChip
            // 优先用快照自报的实际来源；没有才用该 AI 的静态口径
            if let tag = snap.sourceTag ?? AIKind.from(name: snap.name)?.sourceTag {
                Self.chip(tag, fg: .secondary, bg: Color.primary.opacity(0.06), compact: compact)
            }
            if let plan = snap.plan, !plan.isEmpty {
                Self.chip(plan, fg: .secondary, bg: Color.primary.opacity(0.06), compact: compact)
            }
            creditsChip
            dataAgeChip
            serviceChip
        }
    }

    /// 状态胶囊：LIVE（实时）/ 缓存（限流等展示旧数据）/ 离线（读取失败）。
    @ViewBuilder
    private var statusChip: some View {
        if snap.ok && !snap.isStale {
            Self.chip("LIVE", fg: GaugeColor.healthy, bg: GaugeColor.healthy.opacity(0.16), compact: compact)
        } else if snap.isStale {
            Self.chip(L("缓存", "Cached"), fg: GaugeColor.warning, bg: GaugeColor.warning.opacity(0.16), compact: compact)
        } else {
            Self.chip(L("离线", "Offline"), fg: GaugeColor.critical, bg: GaugeColor.critical.opacity(0.14), compact: compact)
        }
    }

    /// 限额重置额度胶囊（Codex credits）：有余额才显示；到期明细本地不可得，只显示次数。
    @ViewBuilder
    private var creditsChip: some View {
        if snap.resetCreditsUnlimited {
            Self.chip(L("重置额度 ∞", "Resets ∞"),
                      fg: .secondary, bg: Color.primary.opacity(0.06), compact: compact)
                .help(L("限额重置额度：无限", "Rate-limit reset credits: unlimited"))
        } else if let n = snap.resetCredits {
            Self.chip(L("重置额度 \(n)", "Resets ×\(n)"),
                      fg: .secondary, bg: Color.primary.opacity(0.06), compact: compact)
                .help(L("限额重置额度剩余 \(n) 次（各笔到期时间官方未写入本地，无法显示）",
                        "\(n) rate-limit reset credits left (per-credit expiry isn't written locally, so it can't be shown)"))
        }
    }

    /// 数据时间胶囊：数据自身时间落后读取时间 3 分钟以上才显示（如 Codex 长任务轮次间隙）。
    @ViewBuilder
    private var dataAgeChip: some View {
        if let t = snap.dataAsOf, Date().timeIntervalSince(t) > 180 {
            Self.chip(L("数据 ", "Data ") + formatUpdatedAgo(t),
                      fg: .secondary, bg: Color.primary.opacity(0.06), compact: compact)
                .help(L("数据来自 Codex 最近一次 rate_limits 事件；长任务执行中不产生新事件属正常",
                        "From the latest Codex rate_limits event; no new events during a long-running turn is normal"))
        }
    }

    /// 厂商服务状态胶囊（组件级结论；正常时不显示，悬停显示出事组件明细）。
    @ViewBuilder
    private var serviceChip: some View {
        switch serviceStatus?.indicator {
        case "minor":
            Self.chip(L("服务降级", "Degraded"), fg: GaugeColor.warning, bg: GaugeColor.warning.opacity(0.16), compact: compact)
                .help(serviceStatus?.detail ?? "")
        case "major", "critical":
            Self.chip(L("服务中断", "Outage"), fg: GaugeColor.critical, bg: GaugeColor.critical.opacity(0.14), compact: compact)
                .help(serviceStatus?.detail ?? "")
        default:
            EmptyView()
        }
    }

    /// 胶囊本体（永不折行）；hero 的「更新于」胶囊也用它保持同款。
    static func chip(_ text: String, fg: Color, bg: Color, compact: Bool = false) -> some View {
        Text(text)
            .font(.system(size: compact ? 9.5 : 10.5, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 6 : 7).padding(.vertical, 1.5)
            .background(Capsule().fill(bg))
    }
}

/// 三端共享的**卡片头**：AI 名独占第一行，胶囊行第二行，下方一条细分隔线与用量条隔开。
/// 此前名字与胶囊挤在同一行——窄刘海（约 312pt）里胶囊多时（如 Grok 的
/// LIVE+本地+X Premium+数据时间）会把 AI 名压成竖排（「G r o k」）。两行版让名字永不被挤，
/// 也让「身份/状态」与「用量数字」在视觉上分层。
struct ProviderCardHeader: View {
    let snap: ProviderSnapshot
    var serviceStatus: ServiceStatus? = nil
    /// 卡片形态：hero（主窗口仪表）/ detailed（菜单栏弹层）/ compact（刘海面板）
    var hero: Bool = false
    var compact: Bool = false
    /// hero 专属：右上角「更新于」相对时间胶囊。
    var updatedAt: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 5) {
            HStack(spacing: 8) {
                Text(snap.name)
                    .font(hero ? .pageTitle : .sectionTitle)
                    .lineLimit(1)
                    .fixedSize()          // 名字优先，绝不被胶囊压缩换行
                    .help(AIKind.from(name: snap.name)?.coverage ?? "")   // 悬停说明该 % 统计了什么
                Spacer(minLength: 0)
                if let t = updatedAt {
                    ProviderChipsRow.chip(L("更新于 ", "Updated ") + formatUpdatedAgo(t),
                                          fg: .secondary, bg: Color.primary.opacity(0.06))
                }
            }
            HStack(spacing: 0) {
                ProviderChipsRow(snap: snap, serviceStatus: serviceStatus, compact: compact)
                Spacer(minLength: 0)
            }
            // 头与用量条之间的细线：比卡间分隔线更淡，只做分层不抢注意力
            Rectangle().fill(Color.primary.opacity(0.09))
                .frame(height: 1)
                .padding(.top, compact ? 1 : 2)
        }
    }
}

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
    /// 厂商服务状态（组件级结论），胶囊 + 悬停明细。
    var serviceStatus: ServiceStatus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : (hero ? 12 : 10)) {
            cardHeader

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

    /// 三端同款两行头（见 ProviderCardHeader）；hero 额外挂「更新于」胶囊。
    private var cardHeader: some View {
        ProviderCardHeader(snap: snap, serviceStatus: serviceStatus,
                           hero: hero, compact: compact,
                           updatedAt: hero ? updatedAt : nil)
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
            UsageBar(fraction: w.remainingPercent / 100, color: color, height: 6, segmented: w.label == "5h")
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: w.remainingPercent)
        }
    }
}
