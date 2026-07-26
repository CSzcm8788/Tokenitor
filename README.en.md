# Tokenitor · AI Usage Tracker

[中文](README.md) · **English**

A native macOS menu-bar app that shows the **remaining quota** of your AI coding tools at a glance and sends a system notification when any of them runs low. It also has a separate **Token usage** page that reads your local session files and leads with **estimated cost** — KPI tiles (cost / tokens / requests), a grouped input-cache-output trend chart with axis ticks, a per-model table combining tokens and cost, and a cache-savings insight line. Subscription tiers (Claude Max/Pro, Codex Plus/Pro, Copilot Pro/Business) show as chips **only when the locally readable value maps to a real tier** — unknown or account-type values are never shown.

Supported today: **Claude**, **Codex**, **Gemini CLI**, **Grok (Grok Build)**, **GitHub Copilot**. Each AI is identified by its **name only** — no third-party brand logos. Only the tools you actually use (installed / logged in) are shown; the rest are hidden automatically.

<p align="center">
  <img src="docs/demo.gif" width="640" alt="10-second tour (3.5x)">
</p>

<p align="center">
  <img src="docs/SCR-usage.png" width="360" alt="Usage dashboard">
</p>

## What it does

Tokenitor lives in the **menu bar**. Left-click opens a compact usage popover; right-click shows a small menu. Clicking an item opens the **full window** — a standard macOS `NavigationSplitView` (the same layout as System Settings) with a sidebar (Overview / Token / Language / Appearance / Settings / About / Help) and a grouped `Form` settings page; you can also open it from the Dock icon. Each AI is a card labeled with its **name only** (no logos), a colored progress bar, remaining %, and a reset countdown. Light/dark follows the system or can be switched manually. Hovering the notch shows a compact panel. Standard macOS menus are in place — View (Overview ⌘1 / Token Usage ⌘2 / Refresh ⌘R), Window (⌘M/⌘W), and Help (guide, GitHub, check for updates). There is no refresh button in the toolbar: refreshing is fully automatic (see "How refreshing works").

## Three-minute start

1. **Install**: [download the DMG](https://github.com/CSzcm8788/Tokenitor/releases/latest) and drag it into Applications, or one-line `curl -fsSL https://raw.githubusercontent.com/CSzcm8788/Tokenitor/main/get.sh | bash`.
2. **Look**: a ◔ icon appears in the menu bar — left-click for the glance popover. Codex / Gemini / Grok cards **show up automatically** (fully local, zero config); for Claude / Copilot, flip the toggle in Settings and authorize once (community APIs, off by default).
3. **Read**: bars show remaining quota — the 5-hour window carries tick marks at 20%/50% · green/amber/red = healthy/low/critical · `LIVE`/`Cached`/`Offline` = data freshness · ↻ = reset countdown. A system notification fires when remaining drops below your threshold.

Odd readings or a dead endpoint? [Open an issue](https://github.com/CSzcm8788/Tokenitor/issues/new/choose) — the template walks you through the key info.

## Where the data comes from

| Tool | Source | Notes |
|------|--------|-------|
| Claude | `~/.tokenitor/claude-statusline.json` (Code, local) · `~/Library/Application Support/Claude/plan-usage-history.json` (desktop app, local) · `api.anthropic.com/api/oauth/usage` (fallback) | **Local first, with a local source for each way you use Claude**: ① terminal Claude Code hands `rate_limits` (5-hour / 7-day windows, incl. `resets_at`) to a statusline script each turn, which writes a file this app reads; ② the **Claude desktop app** itself polls your account usage about every 5 minutes and appends samples to `plan-usage-history.json` (abbreviated keys `fh`/`sd`/`xu` = five_hour / seven_day / extra_usage, values are *used* %; **this source has no reset time**, so a countdown only appears while the one last read from statusline / the endpoint is *still in the future* — once a window rolls over that timestamp is in the past and the countdown simply disappears; nothing is ever extrapolated). Both are **zero-network, rate-limit-free, no Keychain prompt** local reads. Only when neither is available does it fall back to the community endpoint: token read-only (**never refreshed by us**), honest UA; Anthropic marked that endpoint `not planned` and it rate-limits hard (community consensus polls every 300–900s), so it is called at most once per **600s**. Failing that, cached data under 24h is shown with a `Cached` chip; older than that it reports an honest error. The source chip reflects **which path actually produced this reading** (Local / Community / Cache), not what is configured. **⚠️ Advanced — off by default.** |
| Codex | `~/.codex/sessions/**/*.jsonl` | Parses `rate_limits` from recent session files (primary = 5h, secondary = weekly). Fully local, no network. |
| Gemini CLI | `~/.gemini/tmp/<user>/logs.json` | A **local estimate** from today’s request count (this Mac’s CLI only), counted from `logs.json` with session files as fallback only, resetting at local midnight. The official daily limit varies by account type (~250–2000) and isn’t readable locally, so the divisor is **adjustable in Settings** (default 1000) and labelled as an estimate. Note: since June 2026 Google moved personal accounts from the legacy Gemini CLI to Antigravity CLI (`agy`), whose usage isn’t written to `~/.gemini`; this card only appears when local activity is seen in the last 36h. |
| Grok | `~/.grok/logs/unified.jsonl` | Reads the billing events Grok Build (grok CLI) itself fetches periodically and **writes to its local log**: weekly shared-pool used %, exact reset time, and subscription tier (e.g. X Premium). **Fully local, zero network.** Note the semantics: paid xAI tiers share one weekly pool across all products (Chat/Imagine/Build/API); this percentage is that overall usage. |
| GitHub Copilot | `https://api.github.com/copilot_internal/user` | Uses the `gho_` login token in `~/.config/github-copilot/` to request GitHub's built-in endpoint and read `quota_snapshots.premium_interactions` (monthly premium usage remaining %, resets on the 1st UTC). Individual Pro can use the token directly. **Non-official internal endpoint**, off by default (opt-in); degrades gracefully if it changes. |

> ⚠️ Claude / Copilot use non-official endpoints (off by default, opt-in) that may change or break at any time. When that happens the row shows a gray status and degrades gracefully (the fully-local Codex / Gemini are unaffected). Turn on **Settings → Debug dump** to write raw JSON to `~/.tokenitor/debug/` for troubleshooting.

## Download & install

**Download (recommended):** grab `Tokenitor.dmg` from [Releases](https://github.com/CSzcm8788/Tokenitor/releases/latest), open it, drag Tokenitor into Applications, and double-click to run (notarized by Apple — no Gatekeeper prompt). Requires **macOS 13 (Ventura) or later**.

**Homebrew:**

```bash
brew install --cask CSzcm8788/tap/tokenitor
```

**Build from source:** requires macOS 13+ and the Xcode command-line tools (`xcode-select --install`; **no need to open Xcode**).

```bash
cd Tokenitor
bash install.sh          # build + install to /Applications + launch
```

Uninstall: `bash uninstall.sh`. Build only: `bash build.sh && open dist/Tokenitor.app`. First launch may be blocked by Gatekeeper — right-click → Open.

Run the unit tests with `swift test` (redaction, tolerant JSON parsing, formatting, pricing); CI runs build + tests on every push.

Enable **Launch at login** from the in-app Settings (native login item via `SMAppService`).

## Command line (CLI)

The same app doubles as a read-only CLI: prints current quotas once and exits — for scripts, tmux status bars, and automation (identical data pipeline as the GUI).

```bash
/Applications/Tokenitor.app/Contents/MacOS/Tokenitor --cli          # human-readable
/Applications/Tokenitor.app/Contents/MacOS/Tokenitor --cli --json   # stable-keyed JSON

# optional short command
sudo ln -s "/Applications/Tokenitor.app/Contents/MacOS/Tokenitor" /usr/local/bin/tokenitor
tokenitor --cli
```

> Note: Claude / Copilot read Keychain credentials in CLI mode too — the first terminal call may show an "allow Keychain access" prompt; without it only local sources (Codex / Gemini) are printed.

## How refreshing works

Refreshing is **fully automatic** — there is no manual refresh button in the UI:

- **On a timer**: your chosen interval (120s by default, 15s minimum). The timer runs in `.common` mode with a 5s tolerance and App Nap is disabled, so 120s really is 120s while the app sits in the background.
- **Fresh on open**: opening the main window or the menu-bar popover tops up the data if it's older than 30s (the threshold keeps repeated open/close from firing duplicate requests).
- **After system wake**: `Timer` never fires while the Mac sleeps, so on wake the app re-aligns the cadence and refreshes immediately — no "still last night's numbers" after an overnight sleep.
- **Low Power Mode**: the interval is automatically 4× longer; it returns to normal when you plug back in.
- **To refresh right now**: **⌘R**, "Refresh" in the popover, or right-click the menu-bar icon → "Refresh Now". All three clear any rate-limit backoff and retry everything.

Claude prefers a **local** source (see the data table) and only calls the network when that bridge isn’t installed, in which case it is throttled to once per 600s. Cloud sources (Claude / Copilot) back off for 10 minutes after 3 consecutive failures or rate limits, showing the previous result with a `Cached` / `Offline` chip; a manual refresh breaks the backoff immediately.

## Token usage page

The sidebar’s **Token** item (or **⌘2**) opens a separate **Token usage** page: today's token spend per tool, split by model, estimated equivalent cost, and a 7-day trend (persisted to `~/.tokenitor/token-history.json`). Purely local, no network.

| Tool | Source |
|------|--------|
| Codex | `~/.codex/sessions/**/*.jsonl` — per-turn `last_token_usage`, split by model |
| Claude Code | `~/.claude/projects/**/*.jsonl` — `message.usage` per assistant message. **Only the Claude Code terminal** writes tokens locally; the Claude desktop app / web do not. |
| Gemini | `~/.gemini/tmp/**/chats/*.jsonl` — per-message `tokens` (`input` includes `cached`, so cache is subtracted; `thoughts` is separate from `output` and folded into it) |
| Grok | `~/.grok/logs/unified.jsonl` — `shell.turn.inference_done` events (`prompt_tokens` includes `cached_prompt_tokens`, so cache is subtracted); model from the CLI's own model catalog |
| OpenCode | `~/.local/share/opencode/opencode.db` — `tokens` + `cost` from the `message` table (uses OpenCode's own cost, accurate even for models outside the price table) |

> Cost is an estimated "equivalent spend" from the **LiteLLM community price table** (MIT, 2,900+ models, bundled as a snapshot and synced with upstream at release time — never at runtime), not your actual subscription bill; models without pricing show "—".

**The Usage page and Token page are two independent data sources.** The Settings toggles only control the Usage page (quota %); the Token page ignores them and simply scans whatever local token files exist.

## Settings (switched inside the main window)

<p align="center">
  <img src="docs/SCR-settings.png" width="420" alt="Settings">
</p>

- **AI services** (Claude / Codex / Gemini / Grok / Copilot): the two that go through community APIs (Claude / Copilot) are **off by default** and each ask for a one-time risk confirmation.
- **Alerts**: notification toggle, low / critical thresholds (the two can never be inverted — changing one pushes the other), and **Snooze** for 1 / 4 / 8 hours (auto-resumes).
- **General**: daily-limit estimate (Gemini), refresh interval, launch at login, menu-bar panel, status monitor, debug logs. In **Low Power Mode** the refresh interval is automatically 4× longer.
- **Quick actions**: send a test notification / open the data folder / authorize Copilot / authorize Claude.

Every row label is icon-free and uniformly sized so the left edge lines up; scope notes (e.g. "thresholds are percentages of remaining quota") live in the group subtitles.

Threshold colors are shared by every surface: 🟢 healthy ／ 🟡 below the low threshold ／ 🔴 below the critical threshold.

## Notch hover panel

Move the pointer to the **notch area** at the top of the screen and a compact translucent panel drops down beneath it, showing each AI's remaining percentage and reset countdown; move away and it hides. **Click anywhere on the panel** to open the full main window. Machines without a notch trigger it by hovering the top center.

Sizing follows the content automatically, and the panel stays horizontally centered under the notch.

## Branding

The app **bundles and displays no third-party brand logos** — each AI is identified by its **name only**. This eliminates the trademark-distribution risk of shipping brand images at the root.

## Privacy

Everything is processed locally. Credentials are used only to talk directly to each vendor's official domain; local session files are read-only. Nothing is uploaded to any third party. See [PRIVACY.md](PRIVACY.md) for exactly what is stored, where, and for how long.

## License

[MIT](LICENSE) © 2026 CSzcm8788. Free to use / modify / distribute (including commercially); keep the copyright notice. Provided "as is" without warranty.

## Disclaimer

Tokenitor is an independent project with **no affiliation, partnership, or official relationship** with Anthropic / OpenAI / Google / GitHub·Microsoft or their products (Claude, Codex, Gemini, Copilot). It uses each service's **name only** as a nominative identifier and bundles no third-party logo images; names/trademarks belong to their respective owners. Reads local data only; makes no guarantee of accuracy; use at your own risk. Full terms in [DISCLAIMER.md](DISCLAIMER.md).
