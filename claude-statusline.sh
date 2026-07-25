#!/bin/sh
# Tokenitor · Claude 用量本地桥
#
# Claude Code 每轮会把一份 JSON 交给 statusline 脚本的 stdin，其中 `rate_limits` 带
# 5 小时窗口与 7 天窗口的 used_percentage / resets_at（官方 changelog：v1.2.80 起）。
# 这个脚本把它原样落到 ~/.tokenitor/claude-statusline.json，Tokenitor 只读该文件——
# 于是 Claude 用量变成**纯本地读取**：不联网、不打 oauth/usage（该端点被官方判为
# not planned 且持续 429）、不弹钥匙串。
#
# 它同时**必须**打印一行状态栏文本（statusLine 是独占的，若只落盘不打印，你的状态栏会空）。
set -eu
DIR="$HOME/.tokenitor"
OUT="$DIR/claude-statusline.json"
mkdir -p "$DIR"
IN=$(cat)

# 落盘：整份 payload（Tokenitor 只读其中的 rate_limits，其余字段不解析）
printf '%s' "$IN" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"   # 原子替换，避免读到半截文件

# 打印状态栏：模型名 + 两个窗口的剩余百分比（读不到就只显示模型名）
printf '%s' "$IN" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); raise SystemExit
model = (d.get("model") or {}).get("display_name") or (d.get("model") or {}).get("id") or ""
rl = d.get("rate_limits") or {}
parts = []
for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
    w = rl.get(key) or {}
    p = w.get("used_percentage")
    if isinstance(p, (int, float)):
        parts.append(f"{label} {100 - int(p)}%")
print(("  ".join([model] + parts)).strip())
'
