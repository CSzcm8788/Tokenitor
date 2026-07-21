import AppKit
import SwiftUI

/// 「说明」页（侧边栏详情 + 独立窗口共用）：分区卡片，端点/路径以等宽 code 片段高亮，
/// 状态用胶囊标签（本地 / 社区接口 / 默认关）。这里是 app 内各项说明的**唯一出处**——
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

                // ⓪ 快速入门：三步上手，给第一次打开的用户看；技术细节在下面各卡片。
                card("sparkles", L("快速入门", "Quick Start")) {
                    bullet(L("**1 · 零配置起步**：Codex 与 Gemini 的用量来自本机会话文件，安装后自动显示；未使用的 AI 不会出现。", "**1 · Zero-config start**: Codex and Gemini usage comes from local session files and appears automatically after install; tools you don\u{2019}t use never show up."))
                    bullet(L("**2 · 启用 Claude / Copilot（可选）**：二者经由社区通用接口（官方未文档化）读取，默认关闭；在「设置」中打开开关并完成一次授权即可显示。", "**2 · Enable Claude / Copilot (optional)**: both read via community APIs (not officially documented) and are off by default; turn on the toggle in Settings and authorize once."))
                    bullet(L("**3 · 读懂卡片**：进度条表示剩余配额，5 小时窗口带 20% / 50% 两道刻度；绿 / 黄 / 红 对应 充足 / 偏低 / 紧急；`LIVE` / `缓存` / `离线` 表示数据新鲜度；↻ 后为重置倒计时。", "**3 · Reading a card**: bars show remaining quota — the 5-hour window carries tick marks at 20% and 50%; green / amber / red mean healthy / low / critical; `LIVE` / `Cached` / `Offline` indicate data freshness; ↻ precedes the reset countdown."))
                    note(L("左键菜单栏图标即可速览；点刘海面板任意位置打开完整主窗口。关闭主窗口不会退出应用（后台继续监测），退出请用 ⌘Q。", "Left-click the menu-bar icon for a glance; click anywhere on the notch panel to open the full window. Closing the main window doesn\u{2019}t quit the app (monitoring continues in the background) — quit with ⌘Q."))
                }

                // ① 用量页（配额 %）的数据源：端点/路径 · 官方性 · 默认开关。
                card("network", L("数据来源 · 用量页（配额 %）", "Data Sources · Usage Page (quota %)")) {
                    providerRow("Codex", "~/.codex/sessions/**/*.jsonl",
                                [(L("本地", "Local"), .ok)],
                                L("增量解析 `rate_limits`（5h/周窗口按 window_minutes 自动识别，兼容新版仅周窗口），不联网；有「限额重置额度」余额时显示胶囊；数据滞后超 3 分钟显示「数据 X分钟前」。", "Incrementally parses `rate_limits` (5h/weekly windows auto-detected via window_minutes, incl. the new weekly-only schema), no network; a Resets chip appears when reset credits are available; \u{201C}Data Xm ago\u{201D} shows when the event lags >3 min."))
                    rowDivider
                    providerRow("Gemini", "~/.gemini/tmp/<user>/logs.json",
                                [(L("本地估算", "Local estimate"), .ok)],
                                L("今日请求数 ÷ 每日额度的**本地估算**，0 点重置；以 `logs.json` 为准计数（会话文件仅在它缺失时兜底，避免同一批提问被数两遍）。官方额度按账号类型浮动（约 250–2000/天）且本地读不到，分母可在设置里调整（默认 1000）。个人账号的旧版 Gemini CLI 已于 2026-06 迁移至 Antigravity CLI，本项仅在检测到 `~/.gemini` 近期活动时显示。", "A **local estimate**: today\u{2019}s request count ÷ your daily limit, resetting at local midnight; counted from `logs.json` (session files are only a fallback, so the same prompts aren\u{2019}t counted twice). The official limit varies by account type (~250–2000/day) and isn\u{2019}t readable locally, so the divisor is adjustable in Settings (default 1000). Personal accounts moved from the legacy Gemini CLI to Antigravity CLI in June 2026; this card only appears when `~/.gemini` shows recent activity."))
                    rowDivider
                    providerRow("Claude", "api.anthropic.com/api/oauth/usage",
                                [(L("社区接口", "Community API"), .warn), (L("默认关", "Off by default"), .mut)],
                                L("5h / 周（含 Sonnet）· 凭证只读 `~/.claude/.credentials.json` 或钥匙串（**不代它续期**，过期时请在 Claude Code 里任意请求一次）· 诚实 UA · 限流走缓存（缓存超过 24 小时即不再显示，改报读取失败）· 连续失败自动退避 10 分钟（手动刷新立即重试并清除冷却）。", "5h / weekly windows (incl. Sonnet) · reads Claude Code\u{2019}s credentials **read-only, never refreshes them** (when expired, run any request in Claude Code) · honest UA · falls back to cache when rate-limited (cache older than 24h is dropped and reported as a read failure); backs off for 10 min after repeated failures (manual refresh clears the cooldown and retries immediately)."))
                    rowDivider
                    providerRow("Copilot", "api.github.com/copilot_internal/user",
                                [(L("社区接口", "Community API"), .warn), (L("默认关", "Off by default"), .mut)],
                                L("月度 premium 剩余 %，UTC 1 号重置 · 授权走 GitHub device flow，或本机 `~/.config/github-copilot` · 首次开启需确认风险 · 接口字段缺失时显示读取失败，绝不假装额度是满的。", "Monthly premium remaining %, resets on the 1st (UTC) · authorize via GitHub device flow, or local `~/.config/github-copilot` · risk confirmation on first enable · if the endpoint\u{2019}s fields go missing it reports a read failure rather than pretending the quota is full."))
                    note(L("只显示你在用（已安装 / 登录）的 AI，其余自动隐藏。", "Only tools you actually use (installed / signed in) are shown; the rest hide automatically."))
                    note(L("服务状态监控（可在设置关闭）：每 5 分钟轮询各厂商公开状态页，**组件级**判定——只看与该 AI 相关的组件（如 Codex API / Claude Code / Copilot），无关组件（如 FedRAMP）不会误报；异常时卡片显示「服务降级 / 中断」胶囊（悬停看具体组件）、菜单栏图标加指示点。", "Service status monitor (can be disabled in Settings): polls each vendor\u{2019}s public status page every 5 minutes at the **component level** — only components relevant to that AI (Codex API / Claude Code / Copilot) count, so unrelated ones (e.g. FedRAMP) can\u{2019}t cause false alarms; on incidents the card shows a Degraded / Outage chip (hover for details) and the menu-bar icon gets a dot."))
                    note(L("通知告警：某窗口剩余量跌破「低用量 / 紧急」阈值时各通知一次，回升后重置、可再次触发；限流时展示的缓存旧数据不触发告警。", "Alerts: one notification when a window drops below the low / critical threshold, re-armed after recovery; stale cached data never triggers alerts."))
                }

                // ② Token 页（本地成本），与配额独立。原 Token 页折叠「说明」并入此处。
                card("chart.bar", L("数据来源 · Token 页（本地成本，与配额独立）", "Data Sources · Token Page (local cost, independent of quota)")) {
                    bullet(L("**来源**：`~/.claude/projects`、`~/.codex/sessions`、`opencode.db`；取每条消息的 token 数与模型名。", "**Sources**: `~/.claude/projects`, `~/.codex/sessions`, `opencode.db` — token counts and model names per message."))
                    bullet(L("**成本**：按 **LiteLLM 社区定价表**（2900+ 模型，MIT，截至 \(Pricing.asOf)）估「等值花费」（非账单）——新模型无需等更新即有定价；快照在**发版时**与上游同步，运行时不联网。查不到定价的模型显「—」、不计入。", "**Cost**: equivalent-spend estimate from the **LiteLLM community price table** (2,900+ models, MIT, as of \(Pricing.asOf)) — new models are covered without app changes; the snapshot syncs with upstream **at release time**, never at runtime. Unpriced models show \u{201C}—\u{201D}."))
                    bullet(L("**Claude**：仅 Claude Code 终端写本地；Mac App / 网页不写，故此页无 Claude。", "**Claude**: only the Claude Code terminal writes local files; the Mac app / web do not, so no Claude here."))
                    bullet(L("**缓存节省**：绿色提示条按「缓存读 vs 全价输入」的价差估算省下的钱，只统计有定价的模型。", "**Cache savings**: the green line estimates money saved by cache reads vs full-price input, priced models only."))
                    bullet(L("**订阅档位胶囊**：本地能读到且能对上真实档位名（Claude `subscriptionType`、Codex 会话 `rate_limits.plan_type`（主源，JWT claim 兜底）、Copilot `copilot_plan`）才显示；账户类型（如 individual）或存疑值一律不显示。", "**Plan chips**: shown only when a locally readable value maps to a real tier (Claude `subscriptionType`, Codex session `rate_limits.plan_type` with JWT fallback, Copilot `copilot_plan`); account types (e.g. individual) or dubious values are never shown."))
                }

                // ③ 合规姿态。
                card("checkmark.shield", L("合规", "Compliance")) {
                    bullet(L("Claude / Copilot 走社区通用接口（官方未文档化），可能不符其服务条款；默认关闭、**各自**在开启前弹一次风险确认、自担风险。", "Claude / Copilot use community APIs (not officially documented) that may conflict with their ToS; off by default, **each** shows a risk confirmation before being enabled, at your own risk."))
                    bullet(L("仅以本人凭证读本人用量，只读不改；诚实标识 UA，不伪装官方客户端。", "Reads only your own usage with your own credentials, read-only; honest User-Agent, never impersonates official clients."))
                    bullet(L("端点失效即降级（缓存），不影响本地的 Codex / Gemini。", "If an endpoint breaks it degrades gracefully (cache); local Codex / Gemini are unaffected."))
                }

                // ④ 凭证存储与隐私。
                card("lock.shield", L("凭证与隐私", "Credentials & Privacy")) {
                    bullet(L("凭证仅直连各服务官方域名；无自有服务器，零上传。", "Credentials only talk to each vendor\u{2019}s official domain; no servers of our own, nothing uploaded."))
                    bullet(L("授权 token 存 macOS 钥匙串（加密）；Claude Code 的凭证**只读**——绝不代它续期或改写，不影响它的登录态。", "Tokens live in the macOS Keychain (encrypted); Claude Code\u{2019}s credentials are **read-only** — never refreshed or rewritten, its login is untouched."))
                    bullet(L("首次读取时的「允许访问钥匙串」弹窗请求方是 Tokenitor 本体；建议点「允许」（每次询问）。", "The first Keychain prompt is requested by Tokenitor itself; we recommend \u{201C}Allow\u{201D} (ask every time)."))
                    bullet(L("调试转储写 `~/.tokenitor/debug/`，已脱敏，超 3 天自动清。", "Debug dumps go to `~/.tokenitor/debug/`, redacted, auto-deleted after 3 days."))
                    bullet(L("不读对话内容，仅取用量数字与模型名。", "Never reads conversation content — only usage numbers and model names."))
                }

                // ⑤ 各工具没数据时的校准。
                card("wrench.and.screwdriver", L("校准", "Setup")) {
                    bullet(L("**Claude** — 订阅账号 `/login` 一次（接第三方 API 时先移开 `~/.claude/settings.json`）。", "**Claude** — run `/login` once with your subscription account (move `~/.claude/settings.json` aside first if you use a third-party API)."))
                    bullet(L("**Copilot** — 设置 → 授权（device flow），或本机 Copilot 插件已登录。", "**Copilot** — Settings → Authorize (device flow), or an already signed-in local Copilot plugin."))
                    bullet(L("**Gemini** — 装好、登录、用一次即出。", "**Gemini** — install, sign in, use it once."))
                }

                // ⑥ 声明与免责。
                card("exclamationmark.shield", L("声明", "Disclaimer")) {
                    bullet(L("独立作品，与 Anthropic / OpenAI / Google / GitHub·Microsoft 无关联、合作或官方关系。", "Independent work; no affiliation, partnership, or official relationship with Anthropic / OpenAI / Google / GitHub·Microsoft."))
                    bullet(L("各 **AI 服务**仅以名称文字标识、不使用其 logo；「关于」页社交链接使用 GitHub / X / Telegram 官方图形标，属**指示性使用**（仅链接指向本项目/作者页面）。名称 / 商标归各公司。", "**AI services** are identified by name only, no logos; the About page uses official GitHub / X / Telegram marks as **nominative use** (links to this project / the author only). Names / trademarks belong to their owners."))
                    bullet(L("不保证用量数据的实时性、准确性或完整性。", "No guarantee of timeliness, accuracy, or completeness of usage data."))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 顶部

    private var hero: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Tokenitor").font(.pageTitle)
            Text(L("菜单栏 AI 用量速览 · 剩余配额 + 今日 token 成本 · 纯本地", "Menu-bar AI usage at a glance · remaining quota + today\u{2019}s token cost · fully local"))
                .font(.uiCaption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                legend(GaugeColor.healthy, L("充足", "Healthy"))
                legend(GaugeColor.warning, L("偏低", "Low"))
                legend(GaugeColor.critical, L("紧急", "Critical"))
            }
            .padding(.top, 2)
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
                // 统一规格的分区图标：单色符号 + 24pt 圆角容器（不同 SF Symbol 视觉宽度不一，
                // 用固定容器抹平大小差异，符合系统设置的图标块风格）
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06)))
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

    /// 说明页是阅读场景：标签胶囊统一灰色（彩色在深色模式下过于刺眼；
    /// 三态色只保留给「用量档位」这一个语义，见顶部图例）。
    private func tagPill(_ text: String, _ kind: TagKind) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: 文本构件

    /// 补充说明：与数据源行的副文字同级（caption + secondary），不再用更淡的 tertiary——
    /// 阅读页只保留「正文 / 副文」两级灰度，层级过多会显得深浅不一；同样走 markdown 渲染。
    private func note(_ t: String) -> some View {
        Text(markdown(t)).font(.uiCaption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 7)
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
