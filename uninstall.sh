#!/usr/bin/env bash
# 卸载：退出、移除登录项、删除「应用程序」里的 App。
set -euo pipefail
APP_NAME="Tokenitor"
DEST_APP="/Applications/${APP_NAME}.app"

echo "==> 退出运行实例…"
pkill -f "${APP_NAME}" 2>/dev/null || true

echo "==> 移除登录项…"
osascript -e "tell application \"System Events\" to delete (every login item whose name is \"${APP_NAME}\")" 2>/dev/null || true

echo "==> 删除 App…"
if [ -d "${DEST_APP}" ]; then
    rm -rf "${DEST_APP}" 2>/dev/null || sudo rm -rf "${DEST_APP}"
    echo "  已删除 ${DEST_APP}"
else
    echo "  /Applications 下未找到，跳过"
fi

echo "（可选）清理设置与日志：rm -rf ~/.tokenitor ; defaults delete com.tokenitor.app 2>/dev/null"
echo "完成 ✅"
