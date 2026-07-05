# Tokenitor · AI Usage Tracker

**中文** · [English](README.en.md)

一个原生 macOS 应用，实时显示主流 AI 工具的剩余用量并在用量偏低时弹系统通知告警。
当前支持 4 个：**Claude**、**Codex**、**Gemini CLI**、**GitHub Copilot**。各 AI 只用**名称文字**标识，不含任何第三方品牌 logo。
只显示你当前正在使用（已安装/登录）的 AI，其余自动隐藏。

界面：**菜单栏优先的原生应用**。常驻**菜单栏**，左键弹出用量速览、右键精简菜单；点速览里的项打开**完整窗口**——macOS `NavigationSplitView` 侧边栏（仪表 / Token / 语言 / 外观 / 设置 / 关于 / 说明）+ `Form(.grouped)` 设置页。每个 AI 一块玻璃卡片：**名称文字**（不含任何品牌 logo）+ 彩色进度条 + 剩余% + 重置倒计时；鼠标移到刘海弹出紧凑面板。关窗不退出、后台继续读取，Cmd+Q 退出；深浅色跟随系统或手动切换。首次启动需同意免责声明。

<p align="center">
  <img src="docs/SCR-usage.png" width="360" alt="用量主页">
</p>

```
菜单栏:  🔴 CDX 8%

下拉菜单:
  Claude
    🟢 5h           ▓▓▓▓░░ 剩 64%   ↻ 2h31m
    🟡 weekly       ▓▓░░░░ 剩 38%   ↻ thu 13h
    🟢 weekly Sonnet ▓▓▓▓▓░ 剩 80%  ↻ thu 13h
  Codex
    🔴 5h           ░░░░░░ 剩 8%    ↻ 1h05m
    🟡 weekly       ▓▓░░░░ 剩 41%   ↻ mon 09h
  更新于 14:32:07
  立即刷新
  设置 ▸
  退出
```

## 数据从哪来

| 工具 | 来源 | 说明 |
|------|------|------|
| Claude | `https://api.anthropic.com/api/oauth/usage` | 社区发现的**未公开** OAuth 端点，返回 5h / 周（含 Sonnet 单独配额）的已用百分比和重置时间。这是**账号级共享用量**，所以一份数据同时覆盖 **Claude 桌面 App、网页、Claude Code** 的消耗。token 先读 `~/.claude/.credentials.json`，读不到再从 **macOS 钥匙串**取（新版 Claude Code 与桌面 App 常存这里，首次会弹「允许访问钥匙串」，点「始终允许」即可）。**⚠️ 高级·默认关闭**：该接口用订阅凭证访问，按 Anthropic 条款仅限 Claude Code / Claude.ai 使用，第三方使用可能违反条款、致账号受限；故默认关闭，需在设置中确认风险后开启。请求以诚实的 `User-Agent: Tokenitor/<版本>` 发出、**不伪装官方客户端**；因此更容易被该端点限流（429），限流时走磁盘缓存兜底、优雅降级。 |
| Codex | `~/.codex/sessions/**/*.jsonl` | 解析最近会话文件里 `token_count` 事件中的 `rate_limits`（primary=5h，secondary=周）。完全本地读取，不联网。 |
| Gemini CLI | `~/.gemini/tmp/<user>/logs.json`、`chats/*.jsonl` | 统计今天的用户请求数，对约 1000 次/天估算（**本地估算**，仅本机 CLI），本地 0 点重置。**注**：2026-06-18 起 Google 已对个人账号停服旧版 Gemini CLI（迁移到 Antigravity CLI `agy`）；近 36h 无活动会自动隐藏，避免显示过期数据。 |
| GitHub Copilot | `https://api.github.com/copilot_internal/user` | 用 `~/.config/github-copilot/` 里的登录 token（gho_）请求 GitHub 内置端点，取 `quota_snapshots.premium_interactions` 的每月高级用量剩余%，每月 1 号 UTC 重置。个人 Pro 可直接用该 token 访问。属**非官方内部端点**，默认关闭、需手动开启，失效时优雅降级。 |

> ⚠️ Claude / Copilot 用的是非官方端点，默认关闭、需手动开启；可能随时变动或失效，失效时优雅降级（不影响纯本地的 Codex / Gemini）。
> 若接口字段变了，在「设置 → 调试转储原始响应」打开后，原始 JSON 会写到 `~/.tokenitor/debug/`，方便对照调整解析。

## 下载与安装

**直接下载（推荐）**：到 [Releases](https://github.com/CSzcm8788/Tokenitor/releases/latest) 下载 `Tokenitor.dmg`，打开后拖进「应用程序」，双击即可运行（已经 Apple 公证，无 Gatekeeper 拦截）。要求 **macOS 13 (Ventura) 或更高**。

**从源码构建**：需要 macOS 13+ 和 Xcode 命令行工具（`xcode-select --install` 即可，**不用打开 Xcode**）。

### 一键安装（推荐）

构建 + 装到「应用程序」+ 设为开机自启 + 启动，一条命令搞定：

```bash
cd Tokenitor
bash install.sh
```

卸载：`bash uninstall.sh`

### 仅构建

```bash
cd Tokenitor
bash build.sh
open dist/Tokenitor.app
```

编译产物是一个 `.app`，可拖进「应用程序」。首次运行若被 Gatekeeper 拦截，右键 →「打开」。

想直接跑（开发调试）也可以：

```bash
swift run -c release
```

### 开机自启（可选）

系统设置 → 通用 → 登录项 → 添加 `Tokenitor.app`。

## 前置条件

- **Claude**：本机登录过 Claude 桌面 App **或** Claude Code 任一即可（凭证从文件或钥匙串读取）。
  显示的是账号共享用量，桌面 App、网页、Claude Code 的用量都计入其中。
- **Codex**：本机用过 OpenAI Codex CLI（这样 `~/.codex/sessions/` 里才有会话文件）。
  刚装好但还没跑过任务时，会显示「近期会话里没有 rate_limits」，跑一次任务即可。

## 设置（主页内切换）

点主窗口右上角 **⚙️** 或按 **⌘,**，主窗口内容**原地切换**到设置页（同一个窗口，不弹新窗），左上角 **←** 返回用量页。主窗口因此只保留用量卡片、不被拉长。设置页包含：

- **各 AI 服务开关**（Claude / Codex / Gemini / Copilot + 通知告警）——macOS 原生胶囊 Switch，带开/关状态。Claude、Copilot 走非官方端点，**默认关闭**、需手动开启。
- 低用量阈值（默认剩余 **50%**）、紧急阈值（默认剩余 **20%**）、刷新间隔（默认 60s，最低 15s）——三个**等宽**下拉。
- 测试通知 / 重新登录 Claude。

<p align="center">
  <img src="docs/SCR-settings.png" width="360" alt="设置页">
</p>

阈值颜色（主窗口与刘海面板**统一色板**）：🟢 充足 ／ 🟡 低于「低用量阈值」／ 🔴 低于「紧急阈值」。
告警逻辑：某窗口剩余跌破阈值时弹一次通知，回升后重置，避免每次刷新都重复打扰。
切换任一 AI 开关，刘海面板与仪表页的用量卡片**实时同步**增减。

## Token 用量（独立页）

主窗口右上角 **📊** 进入 **Token 用量**页：汇总**今日**各工具的 token 消耗、按模型拆分、估算等值成本，并画**近 7 天趋势**（每日总量落盘 `~/.tokenitor/token-history.json`）。纯本地读取、不联网。

<p align="center">
  <img src="docs/SCR-tokens.png" width="360" alt="Token 用量页">
</p>

| 工具 | 来源 | 说明 |
|------|------|------|
| Codex | `~/.codex/sessions/**/*.jsonl` | `token_count` 事件里 `last_token_usage` 的每轮增量求和，按 `model` 拆分。 |
| Claude Code | `~/.claude/projects/**/*.jsonl` | 每条 assistant 消息的 `message.usage`（input/output/缓存）。**仅 Claude Code 终端**会把 token 写本地；Claude 桌面 App / 网页**不写本地**，故无数据。 |
| OpenCode | `~/.local/share/opencode/opencode.db` | 读 `message` 表 `data` 列中 assistant 消息的 `tokens` 与 `cost`，**直接采用其自带成本**（连定价表外的模型如 DeepSeek 也准）。 |

> 成本为按公开定价估算的「等值花费」，订阅用户非实际账单；查不到定价的模型显示「—」。定价表在 `TokenUsage.swift`，随官方调整时更新。

**用量页 与 Token 页是两套独立数据源**：设置里的**开关只控制「用量页」**（配额 %）；**Token 页不看开关**——它直接扫本地 token 文件，谁写了本地 token 就显示谁。对照：

| AI | 用量页（配额 %） | Token 页（本地 token） |
|------|------|------|
| Codex | ✅ session `rate_limits` | ✅ `~/.codex/sessions` |
| Claude | ✅ OAuth 端点（默认关，需风险确认） | ✅ **仅 Claude Code 终端**；Mac app / 网页无 |
| Gemini | ⚠️ 本地估算（旧版个人账号已停服，多自动隐藏） | ❌ 无 |
| Copilot | ✅ 月度高级用量%（`copilot_internal/user`） | ❌ 无 |
| OpenCode | —（无用量接口，不进用量页） | ✅ `opencode.db`（含 cost） |

Token 页头部的 **?** 进入「说明」子页——成本口径、Claude 无本地数据等说明集中在这里，不挤占主页内容。

## 代码结构

```
Sources/Tokenitor/
  main.swift              入口
  AppDelegate.swift       生命周期、刷新定时器、并发抓取、窗口/重登
  UsageStore.swift        SwiftUI 数据源（ObservableObject）+ 动作回调
  DashboardView.swift     主窗口 NavigationSplitView（边栏 + 详情：仪表/Token/语言/外观/设置/关于/说明）
  SettingsView.swift      独立设置页窗口
  SettingsPanelView.swift 设置内容（开关/下拉/动作，模块化）
  AIKind.swift            AI 模块化注册表（增删 AI 只改这里）
  AIMonitorPanel.swift    单个 AI 玻璃卡片（detailed/compact）
  NotchCardsView.swift    刘海面板 SwiftUI（统一玻璃容器 + 细进度条）
  UsageBar.swift          统一进度条（主窗口/刘海同色同形）
  GlassBackground.swift   Liquid Glass / 毛玻璃降级
  VisualEffectView.swift  半透明材质底（主窗口现用 NSVisualEffectView 作 contentView，见 AppDelegate）
  Help.swift              说明页（数据来源 / 合规 / 隐私 / 校准，技术风格排版）
  StatusBarController.swift 菜单栏弹层（速览面板 + 右键菜单）
  TokenUsage.swift        token 计数 / 定价表 / 数字格式化
  TokenAggregator.swift   Codex / Claude Code 本地会话 token 聚合
  OpenCodeReader.swift    OpenCode（opencode.db）token + cost 读取
  TokenHistory.swift      每日 token 落盘 + 近 N 天序列（趋势图）
  TokenView.swift         Token 用量页（卡片 / 按模型 / 近 7 天趋势）
  ClaudeRiskGate.swift    Claude 开启前风险确认弹窗
  Branding.swift          用量三态色板（GaugeColor / levelColor）
  IconButton.swift        方形悬停高亮图标按钮
  Disclaimer.swift        首启免责声明弹窗
  Models.swift            UsageWindow / 颜色档位 / 倒计时格式化
  Settings.swift          UserDefaults 持久化设置
  ClaudeProvider.swift    Claude OAuth 用量端点 + 磁盘缓存兜底
  ClaudeAuth.swift        Claude 凭证读取 + 续期（form/JSON × 多端点）+ 钥匙串
  CopilotAuth.swift       GitHub Copilot device flow 授权 + 钥匙串 token
  CodexProvider.swift     Codex 会话文件解析
  GeminiProvider.swift    Gemini 今日请求数统计
  CopilotProvider.swift   Copilot 月度高级用量（copilot_internal/user）
  JSONHelpers.swift       宽容 JSON 遍历
  Notifier.swift          系统通知（原生 + osascript 兜底）
  DebugLog.swift / Log.swift 转储与日志
relogin-claude.sh         一键重登脚本（打包进 App 资源）
build.sh / install.sh     编译打包 / 一键安装
DISCLAIMER.md             免责声明
```

## 隐私

所有数据本地处理。Claude token 仅用于直连官方 `api.anthropic.com`；Codex 数据只读本地文件。
Token 用量页只读本地会话文件/数据库（Codex / Claude Code / OpenCode），纯本地统计、不联网。
不上传任何信息到第三方。数据存了什么、在哪、保留多久，见 [PRIVACY.md](PRIVACY.md)。

## 已知限制

- Claude 端点为非官方接口，Anthropic 若调整会导致该部分失效（Codex 不受影响）。
- 仅适用于 **Anthropic 订阅（Pro/Max）登录**：若 Claude Code 走的是 API key 计费（如接第三方/DeepSeek），则没有 5h/周用量可显示，需用订阅账号 `/login` 一次（见下）。
- **Token 自动续期**：access token 几小时过期，App 会用 refresh token 自动续期并存进 **macOS 钥匙串**（加密，条目 `com.tokenitor.app`；旧版明文缓存 `~/.tokenitor/claude-creds.json` 会在首次读取时自动迁移进钥匙串并删除）。但 Anthropic 的续期端点可能被 Cloudflare 拦截外部请求；若续期失败，Claude 栏会提示"请重新 /login"，按下面步骤重登一次即可。

### 用订阅账号登录（生成可读凭证）

若 Claude Code 平时接的是 API key（如 DeepSeek），临时屏蔽配置、用订阅账号登录一次以生成 OAuth 凭证：

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
mv ~/.claude/settings.json ~/.claude/settings.json.off   # 临时移走 env 覆盖
env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY \
    -u ANTHROPIC_MODEL -u ANTHROPIC_DEFAULT_OPUS_MODEL \
    -u ANTHROPIC_DEFAULT_SONNET_MODEL -u ANTHROPIC_DEFAULT_HAIKU_MODEL claude
#   进去后：/login → 选订阅账号 → 浏览器授权 → /exit
mv ~/.claude/settings.json.off ~/.claude/settings.json   # 放回，恢复日常配置
```
- 字段名做了宽容匹配，但极端改版仍可能需要更新解析逻辑（用调试转储排查）。

## 刘海悬停 mini 面板

鼠标移到屏幕顶部**刘海区域**，会在其正下方弹出一个紧凑的半透明面板，显示各 AI 窗口的剩余百分比与重置倒计时；移开自动收起。无刘海的机型则悬停顶部中央触发。

实现：全局监听鼠标移动，判断光标是否落在刘海矩形（用屏幕 `auxiliaryTopLeftArea/RightArea` 推算刘海宽度）或面板范围内。

## Gemini 读取

- **Gemini CLI**（今日请求数）：扫描 `~/.gemini/tmp/<user>/logs.json` 与 `chats/*.jsonl`，统计今天 `type/role == user` 的请求条数（按时间戳去重），对约 1000 次/天估算。属本机 CLI 的**本地估算**。

## 通知与代码签名

通知优先用原生 `UNUserNotificationCenter`（带 Tokenitor 自己的图标，前台也能展示）；**发送前实时查询授权状态**，未授权先请求、授权后才发原生（确保用 App 图标），被拒绝才回退 `osascript`（图标为脚本编辑器）。首次运行请在「系统设置 → 通知 → Tokenitor」**允许通知**。

原生通知 / 正确图标需要**稳定的代码签名身份**（ad-hoc 每次构建身份都变，会导致授权反复失效、图标缓存错乱）。`build.sh` 的签名优先级：环境变量 `CODESIGN_ID` ＞ **Developer ID Application**（自动探测，推荐）＞ 自签名 `Tokenitor Self` ＞ ad-hoc。有 Apple 开发者账号者会自动用 Developer ID，身份稳定。
> 换图标后通知仍显示旧图标：多为系统图标缓存或磁盘上有旧副本——保证只保留一份 App、`lsregister -f` 重注册、必要时清 `iconservices` 缓存即可。

## 窗口与菜单栏

**菜单栏弹层**是主入口：左键弹出面板、右键精简菜单（立即刷新 / 使用说明 / 退出）；弹层**完全独立**——点图标只弹弹层、不激活整个 app、不会把主窗口带到最前。**启动只待在菜单栏**，主窗口不自动弹出（开机自启也不弹窗、不抢焦点）。

**主窗口**为标准 macOS `NavigationSplitView`（「系统设置」同款）：左侧 `List` 边栏（仪表 / Token / 语言 / 外观 / 设置 / 关于 / 说明，每项一枚彩色圆角图标），右侧详情页；工具栏只用系统自带的边栏折叠 / 返回控件，不再自绘顶栏。窗口可自由缩放，默认 660×500、最小 520×400，尺寸自动记忆（`setFrameAutosaveName`）。玻璃质感由 `NSVisualEffectView(.popover, .behindWindow)` 作背景层实现，与菜单栏弹层一致。需要时点 **Dock 图标**、或菜单栏弹层里的项打开。

**设置页**用 `Form { Section }` + `.formStyle(.grouped)`，配原生 `Toggle` / `Picker` / `LabeledContent`，外观与「系统设置」一致。

## 品牌标识

本应用**不内置、不展示任何第三方品牌 logo**——各 AI 一律只用**名称文字**标识。这从根源上规避了商标图片的分发与展示风险。

## 声明与免责

Tokenitor 为独立开发者作品，与 Anthropic / OpenAI / Google / GitHub·Microsoft 等公司及其产品（Claude、Codex、Gemini、Copilot）**无任何关联、合作或官方关系**。应用仅以各服务的**名称**作指示性标识以区分第三方服务，不含任何第三方 logo 图片；相关名称/商标知识产权归各公司所有。仅读取本地数据、不对数据准确性作保证，使用后果自负。首次启动会弹出声明并需同意。完整条款见 [DISCLAIMER.md](DISCLAIMER.md)。

## 许可证

[MIT](LICENSE) © 2026 CSzcm8788。可自由使用 / 修改 / 分发（含商用），需保留版权声明；软件按「原样」提供，不含任何担保。

## 更新日志

### 1.0.0

首个正式版。

- **剩余用量（用量页）**：Claude、Codex、Gemini、GitHub Copilot 的配额 %，纯本地或各厂商用量端点，只显示你在用的。
- **Token 用量页**：读本地会话文件（Claude Code / Codex / OpenCode），汇总今日 token、按模型拆分、按定价表估「等值花费」、近 7 天趋势。纯本地。
- **原生界面**：macOS `NavigationSplitView` 侧边栏（仪表 / Token / 语言 / 外观 / 设置 / 关于 / 说明）+ `Form(.grouped)` 设置页；菜单栏弹窗速览 + 刘海悬停面板；深浅色跟随系统或手动切换。
- **合规**：Claude / Copilot 走各厂商未公开端点，**默认关闭**、诚实标识 UA（不伪装官方客户端）、失效优雅降级、自担风险；Copilot 支持 GitHub device flow 显式授权。不含任何第三方品牌 logo，仅以名称作指示性标识。
- **隐私**：纯本地处理、零上传；凭证存 macOS 钥匙串（加密）；调试转储脱敏、自动清理。详见 [PRIVACY.md](PRIVACY.md)。
