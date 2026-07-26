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
            VStack(alignment: .leading, spacing: 18) {
                hero

                // ⓪ 快速入门：三步上手，给第一次打开的用户看；技术细节在下面各卡片。
                card("sparkles", L("快速入门", "Quick Start")) {
                    bullet(L("**1 · 零配置起步**：Codex / Gemini / Grok 的用量来自本机文件，安装后自动显示；未使用的 AI 不会出现。", "**1 · Zero-config start**: Codex / Gemini / Grok usage comes from local files and appears automatically after install; tools you don\u{2019}t use never show up."))
                    bullet(L("**2 · 启用 Claude / Copilot（可选）**：二者经由社区通用接口（官方未文档化）读取，默认关闭；在「设置」中打开开关并完成一次授权即可显示。", "**2 · Enable Claude / Copilot (optional)**: both read via community APIs (not officially documented) and are off by default; turn on the toggle in Settings and authorize once."))
                    bullet(L("**3 · 读懂卡片**：进度条表示剩余配额，5 小时窗口带 20% / 50% 两道刻度；绿 / 黄 / 红 对应 充足 / 偏低 / 紧急；`LIVE` / `缓存` / `离线` 表示数据新鲜度；↻ 后为重置倒计时。", "**3 · Reading a card**: bars show remaining quota — the 5-hour window carries tick marks at 20% and 50%; green / amber / red mean healthy / low / critical; `LIVE` / `Cached` / `Offline` indicate data freshness; ↻ precedes the reset countdown."))
                    note(L("左键菜单栏图标即可速览；点刘海面板任意位置打开完整主窗口。关闭主窗口不会退出应用（后台继续监测），退出请用 ⌘Q。", "Left-click the menu-bar icon for a glance; click anywhere on the notch panel to open the full window. Closing the main window doesn\u{2019}t quit the app (monitoring continues in the background) — quit with ⌘Q."))
                    note(L("**刷新是自动的**：按设置的间隔定时刷（默认 120s），打开主窗口或菜单栏弹层时若数据偏旧会补刷一次，系统唤醒后也会立即补刷。需要立刻刷新时用 ⌘R、弹层里的「刷新」，或右键菜单栏图标选「立即刷新」。", "**Refreshing is automatic**: on your chosen interval (120s by default), plus a top-up when you open the main window or the menu-bar popover with stale data, and immediately after the system wakes. To refresh right now: ⌘R, \u{201C}Refresh\u{201D} in the popover, or right-click the menu-bar icon."))
                }

                // ① 用量页（配额 %）的数据源：端点/路径 · 官方性 · 默认开关。
                card("network", L("数据来源 · 用量页（配额 %）", "Data Sources · Usage Page (quota %)")) {
                    note(L("**先看清「覆盖范围」**：各家百分比统计的东西不同——有的是整个账号（含网页/桌面端），有的只是本机 CLI 估算，Grok 更是跨产品共享池。每行末尾都注明了口径，卡片上把鼠标停在 AI 名上也能看到。",
                           "**Mind the coverage first**: each vendor\u{2019}s percentage measures something different — some cover the whole account (including web/desktop), one is a local CLI estimate, and Grok\u{2019}s is a cross-product shared pool. Each row states its scope; hovering an AI name on a card shows the same note."))
                    providerRow("Codex", "~/.codex/sessions/**/*.jsonl",
                                [(L("本地", "Local"), .ok)],
                                L("增量解析 `rate_limits`（5h/周窗口按 window_minutes 自动识别，兼容新版仅周窗口），不联网；有「限额重置额度」余额时显示胶囊；数据滞后超 3 分钟显示「数据 X分钟前」。", "Incrementally parses `rate_limits` (5h/weekly windows auto-detected via window_minutes, incl. the new weekly-only schema), no network; a Resets chip appears when reset credits are available; \u{201C}Data Xm ago\u{201D} shows when the event lags >3 min.") + "\n" + AIKind.codex.coverage)
                    rowDivider
                    providerRow("Gemini", "~/.gemini/tmp/<user>/logs.json",
                                [(L("本地估算", "Local estimate"), .ok)],
                                L("今日请求数 ÷ 每日额度的**本地估算**，0 点重置；以 `logs.json` 为准计数（会话文件仅在它缺失时兜底，避免同一批提问被数两遍）。官方额度按账号类型浮动（约 250–2000/天）且本地读不到，分母可在设置里调整（默认 1000）。个人账号的旧版 Gemini CLI 已于 2026-06 迁移至 Antigravity CLI，本项仅在检测到 `~/.gemini` 近期活动时显示。", "A **local estimate**: today\u{2019}s request count ÷ your daily limit, resetting at local midnight; counted from `logs.json` (session files are only a fallback, so the same prompts aren\u{2019}t counted twice). The official limit varies by account type (~250–2000/day) and isn\u{2019}t readable locally, so the divisor is adjustable in Settings (default 1000). Personal accounts moved from the legacy Gemini CLI to Antigravity CLI in June 2026; this card only appears when `~/.gemini` shows recent activity.") + "\n" + AIKind.gemini.coverage)
                    rowDivider
                    providerRow("Grok", "~/.grok/logs/unified.jsonl",
                                [(L("本地", "Local"), .ok)],
                                L("读 Grok Build 自己拉取并落盘的 billing 事件：周共享池已用 %、精确重置时间、订阅档位——零联网、不碰任何端点。注意口径：xAI 付费档为全产品（Chat/Imagine/Build/API）**共享**周池，此百分比即整体用量。", "Reads the billing events Grok Build itself fetches and writes locally: weekly shared-pool used %, exact reset time, subscription tier — zero network, no endpoints touched. Note the semantics: paid xAI tiers share **one** weekly pool across all products (Chat/Imagine/Build/API); this percentage is that overall usage.") + "\n" + AIKind.grok.coverage)
                    rowDivider
                    providerRow("Claude", "~/.tokenitor/claude-statusline.json · ~/Library/Application Support/Claude/plan-usage-history.json",
                                [(L("本地优先", "Local first"), .ok), (L("默认关", "Off by default"), .mut)],
                                L("**本地优先，两条本地源覆盖两种用法**：① **终端 Claude Code** —— 每轮把 `rate_limits`（5 小时 / 7 天窗口，含重置时间）交给 statusline 脚本，脚本落盘、本应用只读；在「设置 → 快捷操作」一键启用（需重启 Claude Code）。状态栏是终端 TUI 的组件，桌面 App 不渲染它，故桌面会话不产生这份数据。② **Claude 桌面 App** —— 桌面 App 自己每约 5 分钟拉一次账号用量并把采样追加到 `plan-usage-history.json`（字段为缩写 `fh`/`sd`/`xu`，值为已用 %；**该源没有重置时间**，倒计时只能沿用上次读到、且此刻仍在未来的那个时间点，过期即不再显示——不外推）。两者都是零联网、零限流、不弹钥匙串的纯本地读取。都读不到时才回落社区接口 `api/oauth/usage`：凭证只读、**不代它续期**、诚实 UA，且该端点被官方判为 not planned 且限流极猛，故最短 600s 才调一次。再失败则显示 24 小时内的缓存（`缓存` 胶囊），超期如实报错。来源胶囊按**本次实际取数路径**显示（本地 / 社区 / 缓存），不按配置猜。", "**Local first, with a local source for each way you use Claude**: ① **terminal Claude Code** hands `rate_limits` (5-hour / 7-day windows, incl. reset times) to a statusline script each turn, which writes a file this app reads; enable it in Settings → Quick Actions (restart Claude Code afterwards). The status line is a terminal-TUI component, so the desktop app never renders it and desktop sessions produce no such data. ② the **Claude desktop app** itself polls your account usage about every 5 minutes and appends samples to `plan-usage-history.json` (abbreviated keys `fh`/`sd`/`xu`, values are *used* %; **this source has no reset time**, so a countdown only shows while the last known one is still in the future — never extrapolated). Both are zero-network, rate-limit-free, no-Keychain local reads. Only when neither is available does it fall back to the community `api/oauth/usage` endpoint: credentials read-only, **never refreshed by us**, honest UA — and since Anthropic marked that endpoint not planned and it rate-limits hard, it is called at most once per 600s. Failing that, cached data under 24h is shown with a `Cached` chip; older than that it reports an honest error. The source chip reflects **which path actually produced this reading** (Local / Community / Cache), not what is configured."))
                    note(L("服务状态监控（可在设置关闭）：每 5 分钟轮询各厂商公开状态页，**组件级**判定——只看与该 AI 相关的组件（如 Codex API / Claude Code / Copilot），无关组件（如 FedRAMP）不会误报；异常时卡片显示「服务降级 / 中断」胶囊（悬停看具体组件）、菜单栏图标加指示点。", "Service status monitor (can be disabled in Settings): polls each vendor\u{2019}s public status page every 5 minutes at the **component level** — only components relevant to that AI (Codex API / Claude Code / Copilot) count, so unrelated ones (e.g. FedRAMP) can\u{2019}t cause false alarms; on incidents the card shows a Degraded / Outage chip (hover for details) and the menu-bar icon gets a dot."))
                    note(L("通知告警：某窗口剩余量跌破「低用量 / 紧急」阈值时各通知一次，回升后重置、可再次触发；限流时展示的缓存旧数据不触发告警。可在设置里**临时静音 1/4/8 小时**，到期自动恢复。低电量模式下刷新间隔自动 ×4 省电。", "Alerts: one notification when a window drops below the low / critical threshold, re-armed after recovery; stale cached data never triggers alerts. Snooze for 1/4/8 hours in Settings (auto-resumes); in Low Power Mode the refresh interval is automatically 4× longer."))
                }

                // ② Token 页（本地成本），与配额独立。原 Token 页折叠「说明」并入此处。
                card("chart.bar", L("数据来源 · Token 页（本地成本，与配额独立）", "Data Sources · Token Page (local cost, independent of quota)")) {
                    bullet(L("**来源**：`~/.claude/projects`、`~/.codex/sessions`、`~/.gemini/tmp`、`~/.grok/logs`、`opencode.db`；取每条消息的 token 数与模型名。各家口径已归一：谁的输入含缓存就扣除、谁的推理独立就并入输出，映射有测试守护。", "**Sources**: `~/.claude/projects`, `~/.codex/sessions`, `~/.gemini/tmp`, `~/.grok/logs`, `opencode.db` — token counts and model names per message. Vendor semantics are normalized (cache subtracted where input includes it; standalone reasoning folded into output), guarded by tests."))
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
                    bullet(L("**Claude** — 订阅账号 `/login` 一次（接第三方 API 时先移开 `~/.claude/settings.json`）。若卡片显示「钥匙串未授权」：新版 Claude Code 把凭证存在钥匙串、且只授权了自己，本应用读取会弹「允许访问钥匙串」——请点**「始终允许」**（只点「允许」的话每个新进程都要再点一次，后台刷新时无人点击就会读取失败）。", "**Claude** — run `/login` once with your subscription account (move `~/.claude/settings.json` aside first if you use a third-party API). If the card says keychain access wasn\u{2019}t granted: recent Claude Code versions keep credentials in the Keychain authorized only to themselves, so reading them prompts \u{201C}allow access to your keychain\u{201D} — choose **Always Allow** (with plain \u{201C}Allow\u{201D}, every new process asks again, and background refreshes fail with nobody there to click)."))
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
        // 不在此重复画「Tokenitor / 说明」大标题：侧栏详情已有 navigationTitle「说明」，
        // 独立说明窗也有窗口标题；再画一层会顶进透明标题栏、与导航标题叠字（见 UI 回归）。
        VStack(alignment: .leading, spacing: 3) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private var rowDivider: some View { Divider().opacity(0.4) }

    // MARK: 数据源行

    private func providerRow(_ name: String, _ endpoint: String,
                             _ tags: [(String, TagKind)], _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(name).font(.uiBody).fontWeight(.medium)
                ForEach(tags, id: \.0) { tagPill($0.0, $0.1) }
                Spacer(minLength: 0)
            }
            codeChip(endpoint)
            Text(markdown(sub)).font(.uiCaption).foregroundStyle(.secondary)
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func codeChip(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
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
            .lineSpacing(3.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
    }

    /// 一条要点：圆点 + 悬挂缩进的正文。行距放宽到 4pt——本页多为长句，
    /// 密排时最难读；留白比字号更能决定「清爽」。
    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 8)
            Text(markdown(s)).font(.uiBody).foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
    }

    /// 解析行内 markdown：`` `code` `` 段落套等宽 + 淡底高亮，**加粗**保留。
    private func markdown(_ s: String) -> AttributedString {
        var a = (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        let codeRanges = a.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map { $0.range }
        for r in codeRanges {
            a[r].font = .system(size: 12, design: .monospaced)
            a[r].backgroundColor = Color.primary.opacity(0.06)
        }
        return a
    }
}
