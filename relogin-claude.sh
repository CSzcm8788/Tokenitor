#!/usr/bin/env bash
# Tokenitor 一键重登：用订阅账号重新登录 Claude，拿到新的 OAuth 凭证。
# 会临时屏蔽 DeepSeek/第三方 env 配置，登录完成后自动恢复。
set -u
S="$HOME/.claude/settings.json"

echo "=================================================="
echo "  Tokenitor · 重新登录 Claude 订阅"
echo "=================================================="
echo

# 临时移走会覆盖 OAuth 的 settings.json（含第三方 API key 的 env）
if [ -f "$S" ]; then
  cp "$S" "$S.bak" 2>/dev/null || true
  mv "$S" "$S.off"
  echo "· 已临时移走 ~/.claude/settings.json"
fi

echo "· 接下来在 claude 里输入 /login → 选「Claude 订阅账号」→ 浏览器授权 → /exit"
echo
env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY \
    -u ANTHROPIC_MODEL -u ANTHROPIC_DEFAULT_OPUS_MODEL \
    -u ANTHROPIC_DEFAULT_SONNET_MODEL -u ANTHROPIC_DEFAULT_HAIKU_MODEL claude || true

# 恢复日常配置
if [ -f "$S.off" ]; then
  mv "$S.off" "$S"
  echo "· 已恢复 ~/.claude/settings.json（日常配置还原）"
fi

# 清掉 Tokenitor 失效的本地凭证缓存，强制下次读取这次登录的新 token
rm -f "$HOME/.tokenitor/claude-creds.json"
echo "· 已清除 Tokenitor 旧凭证缓存"
echo
echo "完成 ✅  回到 Tokenitor 点「刷新」即可。按回车关闭本窗口。"
read -r _
