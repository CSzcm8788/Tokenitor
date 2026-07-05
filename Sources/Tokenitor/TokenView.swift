import SwiftUI

/// 独立的「Token usage」页：顶部按工具给一排图标 Tab，任意时刻只显示一个工具的
/// Tokenscope 风格卡片——hero 大数字 + 输入/输出分色条 + 周期柱状图 + 按模型拆分 +
/// 成本环形图 + 请求/成本趋势迷你卡，Day/Week/Month 可切换。
struct TokenView: View {
    @ObservedObject var store: UsageStore
    var inPopover: Bool = false   // 主窗口头部由自绘 header 提供（见 DashboardView.mainHeaderRow），弹层才画自己的头
    @State private var selected: String?

    /// 选中的工具在当前列表里找不到（如刚关掉、或还没选过）时回退到第一个。
    private var resolvedSelected: String {
        if let selected, store.tokenStats.contains(where: { $0.tool == selected }) { return selected }
        return store.tokenStats.first?.tool ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if inPopover {
                HStack(spacing: 10) {
                    IconButton(systemName: "chevron.left", help: "返回") { store.page = .usage }
                    Text("Token usage").font(.pageTitle)
                    Spacer()
                    IconButton(systemName: "arrow.clockwise", help: "刷新", prominent: true) { store.onRefresh() }
                    IconButton(systemName: "questionmark", help: "说明") { store.page = .tokenInfo }
                }
            }

            if store.tokenStats.isEmpty {
                Text("今日暂无本地 token 记录。\n用过 Codex 或 Claude Code 后，会从其本地会话文件里读取并汇总。")
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                toolTabs
                if let stat = store.tokenStats.first(where: { $0.tool == resolvedSelected }) {
                    TokenStatCard(stat: stat)
                }
            }
            // 成本估算 / Claude 无本地数据等说明已移到「说明」子页（点头部 ? 进入），不再挤占本页。

            if let t = store.tokensUpdate {
                Text("更新于 \(timeString(t))")
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 每个有本地 token 数据的工具一个图标，点哪个显示哪个（不再纵向堆叠全部工具）。
    @ViewBuilder
    private var toolTabs: some View {
        if store.tokenStats.count > 1 {
            Picker("工具", selection: Binding(get: { resolvedSelected }, set: { selected = $0 })) {
                ForEach(store.tokenStats) { stat in
                    Text(stat.tool).tag(stat.tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
}

/// Token 页的「说明」子页：把成本估算 / Claude 无本地数据等说明集中到这里，
/// 不再挤占 Token 主页内容。返回导航由 NavigationSplitView / 弹层自带。
struct TokenInfoView: View {
    @ObservedObject var store: UsageStore
    var inPopover: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if inPopover {
                HStack(spacing: 10) {
                    IconButton(systemName: "chevron.left", help: "返回") { store.page = .tokens }
                    Text("说明").font(.pageTitle)
                    Spacer()
                }
            }

            note("成本口径", "成本为按公开定价估算的「等值花费」，订阅用户非实际账单；查不到定价的模型显示「—」。")
            note("Claude", "仅 Claude Code 终端会把 token 写到本地（~/.claude/projects）；Mac app / 网页不写本地，故 Token 页无 Claude 数据。")

            Spacer(minLength: 0)
        }
    }

    private func note(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.sectionTitle).foregroundStyle(.secondary)
            Text(body).font(.uiBody).foregroundStyle(Color.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// Token 页顶部的单个工具图标 Tab，尺寸对齐 IconButton（30×30）。
private struct ToolIconTab: View {
    let name: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.uiCaption)
                .fontWeight(selected ? .semibold : .medium)
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.1 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(name)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

/// 单个工具的 Tokenscope 风格卡片，内部维护自己的 Day/Week/Month 选择。
private struct TokenStatCard: View {
    let stat: TokenStat
    @State private var period: TokenPeriod = .week

    private var report: PeriodReport {
        switch period {
        case .day: return stat.day
        case .week: return stat.week
        case .month: return stat.month
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            hero
            splitBar
            TokenBarChart(data: report.series)

            Divider().opacity(0.4)
            modelsSection

            if !report.models.isEmpty {
                Divider().opacity(0.4)
                costSection
            }

            Divider().opacity(0.4)
            footerStats
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - 卡片头 / hero / 分色条

    private var header: some View {
        HStack(spacing: 8) {
            Text(stat.tool).font(.sectionTitle)
            Spacer()
            Picker("周期", selection: $period) {
                Text("Day").tag(TokenPeriod.day)
                Text("Week").tag(TokenPeriod.week)
                Text("Month").tag(TokenPeriod.month)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOTAL TOKENS").font(.uiLabel).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatTokens(report.totalTokens))
                        .font(.numHero)
                    if abs(report.deltaTokens) >= 1 { DeltaBadge(value: report.deltaTokens) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("EST. COST").font(.uiLabel).foregroundStyle(.secondary)
                Text(formatUSDExact(report.cost))
                    .font(.numTitle)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var splitBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                let denom = max(report.totalTokens, 1)
                let inputFrac = CGFloat(report.inputTokens + report.cacheTokens) / CGFloat(denom)
                HStack(spacing: 0) {
                    Rectangle().fill(Color.accentColor)
                        .frame(width: report.totalTokens > 0 ? max(geo.size.width * inputFrac, 3) : 0)
                    Rectangle().fill(Color.accentColor.opacity(0.55))
                }
            }
            .frame(height: 7)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    Text("Input \(fmtM(report.inputTokens + report.cacheTokens))")
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.accentColor.opacity(0.55)).frame(width: 6, height: 6)
                    Text("Output \(fmtM(report.outputTokens))")
                }
                Text("\(cachedPct)% cached").foregroundStyle(.tertiary)
            }
            .font(.num)
            .foregroundStyle(.secondary)
        }
    }

    private var cachedPct: Int {
        guard report.totalTokens > 0 else { return 0 }
        return Int((Double(report.cacheTokens) / Double(report.totalTokens) * 100).rounded())
    }
    private func fmtM(_ n: Int) -> String { String(format: "%.2fM", Double(n) / 1_000_000) }

    // MARK: - Tokens by model

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOKENS BY MODEL").font(.uiLabel).foregroundStyle(.secondary)
            if report.models.isEmpty {
                Text("本周期无数据").font(.num).foregroundStyle(.tertiary).padding(.vertical, 2)
            } else {
                let maxV = max(report.models.map { $0.counts.total }.max() ?? 1, 1)
                let shares = Self.sharePercents(report.models.map { $0.counts.total })
                ForEach(Array(report.models.enumerated()), id: \.offset) { i, m in
                    modelRow(m, max: maxV, share: shares[i], color: Self.rankColor(i))
                }
            }
        }
    }

    private func modelRow(_ m: ModelTokens, max: Int, share: Double, color: Color) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 7, height: 7)
            Text(m.model)
                .font(.uiCaption)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(m.counts.total) / CGFloat(max))
                    }
            }
            .frame(height: 5)
            Text(formatTokens(m.counts.total))
                .font(.num)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            Text(Self.shareStr(share))
                .font(.num)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Cost by model

    private var costSection: some View {
        let costModels = report.models.filter { $0.cost > 0 }
        let unpriced = report.models.filter { $0.cost <= 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("COST BY MODEL").font(.uiLabel).foregroundStyle(.secondary)
            if costModels.isEmpty {
                Text("—").font(.num).foregroundStyle(.tertiary)
            } else {
                CostDonutChart(models: costModels, size: 100, thickness: 15)
            }
            if !unpriced.isEmpty {
                Text("\(unpriced.count) 个模型没有定价数据（成本未计入）：\(unpriced.map(\.model).joined(separator: ", "))")
                    .font(.numMicro)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Requests / Cost trend

    private var footerStats: some View {
        HStack(spacing: 8) {
            miniStat(label: "REQUESTS", value: formatInt(report.requests),
                     sub: "\(report.sessions) sessions", trend: report.reqTrend)
            miniStat(label: "COST TREND", value: formatUSDExact(report.cost),
                     sub: periodSubLabel, trend: report.costTrend, accent: true)
        }
    }

    private var periodSubLabel: String {
        switch period {
        case .day: return "today"
        case .week: return "this week"
        case .month: return "this month"
        }
    }

    private func miniStat(label: String, value: String, sub: String, trend: [Double], accent: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.uiMicro).foregroundStyle(.secondary)
                Text(value).font(.numTitle)
                    .foregroundStyle(accent ? Color.accentColor : Color.primary)
                Text(sub).font(.numMicro).foregroundStyle(.tertiary)
            }
            Spacer()
            TokenSparkline(values: trend.isEmpty ? [0, 0] : trend)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - 排名取色 / 份额计算（与 Tokenscope 的 DONUT_PALETTE / sharePcts 对齐）

    private static let rankPalette = ["1f9d63", "34c27e", "6ad0a0", "a7e3c5", "4b5a52"]

    private static func rankColor(_ i: Int) -> Color {
        Color(hex: i < rankPalette.count ? rankPalette[i] : "79817b")
    }

    /// 每个值的份额按 1 位小数用最大余数法分配，使总和精确等于 100.0%。
    private static func sharePercents(_ values: [Int]) -> [Double] {
        let total = values.reduce(0, +)
        guard total > 0 else { return values.map { _ in 0 } }
        let units = 1000.0
        let raw = values.map { Double($0) / Double(total) * units }
        var floors = raw.map { $0.rounded(.down) }
        var left = Int((units - floors.reduce(0, +)).rounded())
        let order = raw.indices.sorted { (raw[$0] - floors[$0]) > (raw[$1] - floors[$1]) }
        for i in order {
            guard left > 0 else { break }
            floors[i] += 1
            left -= 1
        }
        return floors.map { $0 / 10 }
    }

    private static func shareStr(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))%" : String(format: "%.1f%%", v)
    }
}
