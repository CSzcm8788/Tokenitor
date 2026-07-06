import AppKit
import SwiftUI

/// 「说明」页（侧边栏详情 + 独立窗口共用）：分区卡片，端点/路径以等宽 code 片段高亮，
/// 状态用胶囊标签（本地 / 未公开 / 默认关）。这里是 app 内各项说明的**唯一出处**——
/// 卡片正常状态不再挂描述文字，全部汇总到这里；改口径只改这里。
final class HelpViewController: NSViewController {
    override func loadView() {
        let host = NSHostingView(rootView: HelpView())
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 700)
        view = host
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero

                // ① 用量页（配额 %）的数据源：端点/路径 · 官方性 · 默认开关。
                card("network", "数据来源 · 用量页（配额 %）") {
                    providerRow("Codex", "~/.codex/sessions/**/*.jsonl",
                                [("本地", .ok)],
                                "解析 `rate_limits`（primary=5h、secondary=周），不联网。")
                    rowDivider
                    providerRow("Gemini", "~/.gemini/tmp/<user>/logs.json",
                                [("本地估算", .ok)],
                                "今日请求数，对约 1000/天估算，0 点重置。")
                    rowDivider
                    providerRow("Claude", "api.anthropic.com/api/oauth/usage",
                                [("未公开", .warn), ("默认关", .mut)],
                                "5h / 周（含 Sonnet）· 凭证只读 `~/.claude/.credentials.json` 或钥匙串（**不代它续期**，过期时请在 Claude Code 里任意请求一次）· 诚实 UA · 限流走缓存。")
                    rowDivider
                    providerRow("Copilot", "api.github.com/copilot_internal/user",
                                [("内部", .warn), ("默认关", .mut)],
                                "月度 premium 剩余 %，UTC 1 号重置 · 授权走 GitHub device flow，或本机 `~/.config/github-copilot`。")
                    note("只显示你在用（已安装 / 登录）的 AI，其余自动隐藏。")
                    note("服务状态监控（可在设置关闭）：每 5 分钟轮询各厂商公开状态页（`status.claude.com` / `status.openai.com` / `githubstatus.com`），异常时卡片显示「服务降级 / 中断」胶囊、菜单栏图标加指示点。配额低 ≠ 服务挂了，两者互补。")
                }

                // ② Token 页（本地成本），与配额独立。原 Token 页折叠「说明」并入此处。
                card("chart.bar", "数据来源 · Token 页（本地成本，与配额独立）") {
                    bullet("**来源**：`~/.claude/projects`、`~/.codex/sessions`、`opencode.db`；取每条消息的 token 数与模型名。")
                    bullet("**成本**：定价表（截至 \(Pricing.asOf)）估「等值花费」（非账单）；无定价显「—」、不计入。")
                    bullet("**Claude**：仅 Claude Code 终端写本地；Mac App / 网页不写，故此页无 Claude。")
                }

                // ③ 合规姿态。
                card("checkmark.shield", "合规") {
                    bullet("Claude / Copilot 走未公开端点，可能不符其服务条款；默认关闭、开启前提示、自担风险。")
                    bullet("仅以本人凭证读本人用量，只读不改；诚实标识 UA，不伪装官方客户端。")
                    bullet("端点失效即降级（缓存），不影响本地的 Codex / Gemini。")
                }

                // ④ 凭证存储与隐私。
                card("lock.shield", "凭证与隐私") {
                    bullet("凭证仅直连各服务官方域名；无自有服务器，零上传。")
                    bullet("授权 token 存 macOS 钥匙串（加密）；Claude Code 的凭证**只读**——绝不代它续期或改写，不影响它的登录态。")
                    bullet("首次读取时的「允许访问钥匙串」弹窗请求方是 Tokenitor 本体；建议点「允许」（每次询问）。")
                    bullet("调试转储写 `~/.tokenitor/debug/`，已脱敏，超 3 天自动清。")
                    bullet("不读对话内容，仅取用量数字与模型名。")
                }

                // ⑤ 各工具没数据时的校准。
                card("wrench.and.screwdriver", "校准") {
                    bullet("**Claude** — 订阅账号 `/login` 一次（接第三方 API 时先移开 `~/.claude/settings.json`）。")
                    bullet("**Copilot** — 设置 → 授权（device flow），或本机 Copilot 插件已登录。")
                    bullet("**Gemini** — 装好、登录、用一次即出。")
                }

                // ⑥ 声明与免责。
                card("exclamationmark.shield", "声明") {
                    bullet("独立作品，与 Anthropic / OpenAI / Google / GitHub·Microsoft 无关联、合作或官方关系。")
                    bullet("仅以各服务名称作指示性标识，不含任何第三方 logo；名称 / 商标归各公司。")
                    bullet("不保证用量数据的实时性、准确性或完整性。")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 顶部

    private var hero: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Tokenitor").font(.pageTitle)
                Text("菜单栏 AI 用量速览 · 剩余配额 + 今日 token 成本 · 纯本地")
                    .font(.uiCaption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    legend(GaugeColor.healthy, "充足")
                    legend(GaugeColor.warning, "偏低")
                    legend(GaugeColor.critical, "紧急")
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.uiCaption).foregroundStyle(.secondary)
        }
    }

    // MARK: 分区卡片

    private func card<Content: View>(_ icon: String, _ title: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .regular)).foregroundStyle(.secondary)
                Text(title).font(.sectionTitle)
            }
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private var rowDivider: some View { Divider().opacity(0.4) }

    // MARK: 数据源行

    private func providerRow(_ name: String, _ endpoint: String,
                             _ tags: [(String, TagKind)], _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name).font(.uiBody).fontWeight(.medium)
                ForEach(tags, id: \.0) { tagPill($0.0, $0.1) }
                Spacer(minLength: 0)
            }
            codeChip(endpoint)
            Text(markdown(sub)).font(.uiCaption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func codeChip(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
            .fixedSize(horizontal: false, vertical: true)
    }

    private enum TagKind { case ok, warn, mut }

    private func tagPill(_ text: String, _ kind: TagKind) -> some View {
        let (fg, bg): (Color, Color)
        switch kind {
        case .ok:   (fg, bg) = (GaugeColor.healthy, GaugeColor.healthy.opacity(0.16))
        case .warn: (fg, bg) = (GaugeColor.warning, GaugeColor.warning.opacity(0.16))
        case .mut:  (fg, bg) = (.secondary, Color.primary.opacity(0.06))
        }
        return Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(Capsule().fill(bg))
    }

    // MARK: 文本构件

    private func note(_ t: String) -> some View {
        Text(t).font(.uiCaption).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(Color.accentColor.opacity(0.7)).frame(width: 4, height: 4).padding(.top, 7)
            Text(markdown(s)).font(.uiBody).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 解析行内 markdown：`` `code` `` 段落套等宽 + 淡底高亮，**加粗**保留。
    private func markdown(_ s: String) -> AttributedString {
        var a = (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        let codeRanges = a.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map { $0.range }
        for r in codeRanges {
            a[r].font = .system(size: 12, design: .monospaced)
            a[r].backgroundColor = Color.primary.opacity(0.08)
        }
        return a
    }
}
