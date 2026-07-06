#!/usr/bin/env bash
# Tokenitor 一行命令安装：
#   curl -fsSL https://raw.githubusercontent.com/CSzcm8788/Tokenitor/main/get.sh | bash
# 下载 GitHub Releases 最新的公证 DMG → 安装到「应用程序」→ 启动。
set -euo pipefail

APP_NAME="Tokenitor"
DMG_URL="https://github.com/CSzcm8788/Tokenitor/releases/latest/download/${APP_NAME}.dmg"
DEST="/Applications/${APP_NAME}.app"

TMP="$(mktemp -d)"
MNT=""
cleanup() {
  [ -n "$MNT" ] && hdiutil detach "$MNT" -quiet 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "==> 下载最新版 ${APP_NAME}.dmg…"
curl -fL --progress-bar "$DMG_URL" -o "$TMP/${APP_NAME}.dmg"

echo "==> 挂载并安装到「应用程序」…"
MNT="$(hdiutil attach -nobrowse -readonly "$TMP/${APP_NAME}.dmg" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
sleep 1
if ! rm -rf "$DEST" 2>/dev/null || ! cp -R "$MNT/${APP_NAME}.app" "$DEST" 2>/dev/null; then
  echo "  无权限写入 /Applications，尝试 sudo（可能要输入密码）…"
  sudo rm -rf "$DEST"
  sudo cp -R "$MNT/${APP_NAME}.app" "$DEST"
fi

echo "==> 启动…"
open "$DEST"
echo ""
echo "完成 ✅  ${APP_NAME} 已安装并启动（DMG 已 Apple 公证，无 Gatekeeper 拦截）。"
