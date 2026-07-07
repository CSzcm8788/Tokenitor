import SwiftUI

/// 「Token usage」页：任意时刻只显示一个工具的卡片（工具切换在边栏「Token」子项）。
/// 卡片结构（v1.4 重构）：标题胶囊行 → KPI 三卡（成本优先）→ 分组趋势图 → 模型合并表 → 缓存节省。
struct TokenView: View {
    @ObservedObject var store: UsageStore
    var inPopover: Bool = false   // 主窗口头部由自绘 header 提供（见 DashboardView.mainHeaderRow），弹层才画自己的头

    /// 当前工具由边栏子项选择（store.tokenTool）；找不到（如刚关掉/未选过）时回退到第一个。
    private var resolvedSelected: String {
        if let t = store.tokenTool, store.tokenStats.contains(where: { $0.tool == t }) { return t }
        return store.tokenStats.first?.tool ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if inPopover {
                HStack(spacing: 10) {
                    IconButton(systemName: "chevron.left", help: L("返回", "Back")) { store.page = .usage }
                    Text("Token usage").font(.pageTitle)
                    Spacer()
                    IconButton(systemName: "arrow.clockwise", help: L("刷新", "Refresh"), prominent: true) { store.onRefresh() }
                    IconButton(systemName: "questionmark", help: L("说明", "Info")) { store.page = .tokenInfo }
                }
            }

            if store.tokenStats.isEmpty {
                Text(L("今日暂无本地 token 记录。\n用过 Codex 或 Claude Code 后，会从其本地会话文件里读取并汇总。", "No local token records today.\nAfter you use Codex or Claude Code, usage is aggregated from their local session files."))
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else if let stat = store.tokenStats.first(where: { $0.tool == resolvedSelected }) {
                TokenStatCard(stat: stat,
                              plan: store.snapshots.first(where: { $0.name == stat.tool })?.plan,
                              updatedAt: store.tokensUpdate)
            }
        }
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
                    IconButton(systemName: "chevron.left", help: L("返回", "Back")) { store.page = .tokens }
                    Text(L("说明", "Info")).font(.pageTitle)
                    Spacer()
                }
            }

            note(L("成本口径", "Cost basis"), L("成本为按公开定价（截至 \(Pricing.asOf)）估算的「等值花费」，订阅用户非实际账单；查不到定价的模型显示「—」。", "Cost is an equivalent-spend estimate from public pricing (as of \(Pricing.asOf)), not your subscription bill; models without pricing show \u{201C}—\u{201D}."))
            note("Claude", L("仅 Claude Code 终端会把 token 写到本地（~/.claude/projects）；Mac app / 网页不写本地，故 Token 页无 Claude 数据。", "Only the Claude Code terminal writes tokens locally (~/.claude/projects); the Mac app / web do not, so no Claude data here."))

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

/// 单个工具的卡片：成本叙事优先、一个维度只出现一次、颜色只编码一种含义。
private struct TokenStatCard: View {
    let stat: TokenStat
    var plan: String? = nil        // 订阅档位（可信才有值；nil 不显示胶囊）
    var updatedAt: Date? = nil
    @State private var period: TokenPeriod = .week

    private var report: PeriodReport {
        switch period {
        case .day: return stat.day
        case .week: return stat.week
        case .month: return stat.month
        }
    }

    var body: some View {
        // 一个容器、三个区段：KPI｜趋势｜按模型，区段间只用淡色分割线（不再各自加灰底块）。
        VStack(alignment: .leading, spacing: 12) {
            header
            kpiRow
            Divider().opacity(0.4)
            trendSection
            Divider().opacity(0.4)
            modelTable
            savingsLine
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - 标题行：工具名 + 档位/更新时间胶囊 + 周期切换

    private var header: some View {
        HStack(spacing: 8) {
            Text(stat.tool).font(.sectionTitle)
            if let plan, !plan.isEmpty { chip(plan) }
            if let t = updatedAt { chip(L("更新于 ", "Updated ") + formatUpdatedAgo(t)) }
            Spacer(minLength: 8)
            PeriodSegmented(period: $period)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: - KPI 分栏（Apple 式统计行：三列等宽、无各自底色、竖向淡分割线，模板严格对齐）

    private var kpiRow: some View {
        HStack(alignment: .top, spacing: 0) {
            kpiColumn(label: L("预估成本", "Est. cost"),
                      value: formatUSDExact(report.cost),
                      accent: true,
                      delta: report.hasPrior ? report.deltaCost : nil,
                      subLines: costSubLines)
            kpiDivider
            kpiColumn(label: "Tokens",
                      value: formatTokens(report.totalTokens),
                      subLines: [
                        L("输入 \(fmtShort(report.inputTokens)) · 输出 \(fmtShort(report.outputTokens))",
                          "In \(fmtShort(report.inputTokens)) · Out \(fmtShort(report.outputTokens))"),
                        L("缓存 \(fmtShort(report.cacheTokens))（\(cachedPct)%）",
                          "Cache \(fmtShort(report.cacheTokens)) (\(cachedPct)%)"),
                      ])
            kpiDivider
            kpiColumn(label: L("请求", "Requests"),
                      value: formatInt(report.requests),
                      subLines: requestsSubLines)
        }
        .padding(.vertical, 2)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 3)
    }

    private var costSubLines: [String] {
        if report.hasPrior {
            return [L("较\(prevPeriodName)", "vs \(prevPeriodEN)")]
        }
        return [L("较\(prevPeriodName) —", "vs \(prevPeriodEN) —"),
                L("（历史不足）", "(no history)")]
    }

    private var requestsSubLines: [String] {
        var lines = [L("\(report.sessions) 会话", "\(report.sessions) sessions")]
        if period != .day, report.cost > 0 {
            let days = period == .week ? 7.0 : 30.0
            lines.append(L("日均 \(formatUSD(report.cost / days))", "\(formatUSD(report.cost / days))/day"))
        }
        return lines
    }

    private var prevPeriodName: String {
        switch period { case .day: return "昨日"; case .week: return "上周"; case .month: return "上月" }
    }
    private var prevPeriodEN: String {
        switch period { case .day: return "yesterday"; case .week: return "last week"; case .month: return "last month" }
    }

    /// 副文案用一位小数的短格式，保证两行内放得下、不出现「…」截断。
    private func fmtShort(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0fK", d / 1_000) }
        return "\(n)"
    }

    /// 等宽列：标签 / 数值行 / 固定两行高的副文案区——三列高度与基线严格一致。
    private func kpiColumn(label: String, value: String, accent: Bool = false,
                           delta: Double? = nil, subLines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.uiMicro).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.numTitle)
                    .foregroundStyle(accent ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let delta, abs(delta) >= 1 { DeltaBadge(value: delta) }
            }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(subLines, id: \.self) { line in
                    Text(line).font(.numMicro).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(height: 24, alignment: .topLeading)   // 固定副文案区高：列高恒等
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 趋势：分组三柱（输入/缓存/输出），今天高亮

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("趋势", "Trend")).font(.uiLabel).foregroundStyle(.secondary)
                Spacer()
                legendDot(GroupedTokenChart.inputColor, L("输入", "In"))
                legendDot(GroupedTokenChart.cacheColor, L("缓存", "Cache"))
                legendDot(GroupedTokenChart.outputColor, L("输出", "Out"))
            }
            GroupedTokenChart(data: report.series, highlightIndex: highlightIndex)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 7, height: 7)
            Text(label).font(.numMicro).foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
    }

    /// 周/月视图高亮最后一组（今天/本周）；日视图高亮当前所在的小时段。
    private var highlightIndex: Int? {
        guard !report.series.isEmpty else { return nil }
        if period == .day {
            let bucket = Calendar.current.component(.hour, from: Date()) / 4
            return min(bucket, report.series.count - 1)
        }
        return report.series.count - 1
    }

    // MARK: - 按模型（tokens 与成本合并成一张表）

    private var modelTable: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("按模型", "By model")).font(.uiLabel).foregroundStyle(.secondary)
            if report.models.isEmpty {
                Text(L("本周期无数据", "No data in this period")).font(.num).foregroundStyle(.tertiary).padding(.vertical, 2)
            } else {
                let maxV = max(report.models.map { $0.counts.total }.max() ?? 1, 1)
                ForEach(Array(report.models.enumerated()), id: \.offset) { i, m in
                    modelRow(m, max: maxV, color: Self.rankColor(i))
                }
                unpricedNote
            }
        }
    }

    private func modelRow(_ m: ModelTokens, max maxV: Int, color: Color) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 7, height: 7)
            Text(m.model)
                .font(.uiCaption)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(m.counts.total) / CGFloat(maxV))
                    }
            }
            .frame(height: 5)
            Text(formatTokens(m.counts.total))
                .font(.num)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            Text(formatUSD(m.cost))
                .font(.num)
                .frame(width: 52, alignment: .trailing)
        }
        .help("\(m.model) · \(formatTokens(m.counts.total)) tokens · \(formatUSDExact(m.cost))")
    }

    @ViewBuilder
    private var unpricedNote: some View {
        let unpriced = report.models.filter { $0.cost <= 0 }
        if !unpriced.isEmpty {
            Text(L("\(unpriced.count) 个模型没有定价数据（成本未计入）：\(unpriced.map(\.model).joined(separator: ", "))",
                   "\(unpriced.count) model(s) without pricing (cost excluded): \(unpriced.map(\.model).joined(separator: ", "))"))
                .font(.numMicro)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 模型排名色：与趋势图同一蓝系（颜色只编码「token 量」这一种含义）。
    private static let rankPalette = ["378ADD", "85B7EB", "2E6BC7", "B5D4F4", "6E96C4"]
    private static func rankColor(_ i: Int) -> Color {
        Color(hex: i < rankPalette.count ? rankPalette[i] : "8B94A3")
    }

    // MARK: - 缓存节省洞察条（这页最值钱的一行字）

    @ViewBuilder
    private var savingsLine: some View {
        let savings = Pricing.cacheSavings(report.models)
        if savings >= 0.01, report.totalTokens > 0 {
            Text(L("缓存命中 \(cachedPct)% · \(periodName)约节省 \(formatUSD(savings))（按缓存读与全价输入的价差估算）",
                   "Cache hit \(cachedPct)% · saved ~\(formatUSD(savings)) \(periodEN) (cache-read vs full-price input)"))
                .font(.uiCaption)
                .foregroundStyle(GaugeColor.healthy)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GaugeColor.healthy.opacity(0.1)))
        }
    }

    private var cachedPct: Int {
        guard report.totalTokens > 0 else { return 0 }
        return Int((Double(report.cacheTokens) / Double(report.totalTokens) * 100).rounded())
    }
    private var periodName: String {
        switch period { case .day: return "今日"; case .week: return "本周"; case .month: return "本月" }
    }
    private var periodEN: String {
        switch period { case .day: return "today"; case .week: return "this week"; case .month: return "this month" }
    }
}
