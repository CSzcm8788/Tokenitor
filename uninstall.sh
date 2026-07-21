#!/usr/bin/env bash
# 卸载：退出、移除登录项、删除「应用程序」里的 App。
set -euo pipefail
APP_NAME="Tokenitor"
DEST_APP="/Applications/${APP_NAME}.app"

echo "==> 退出运行实例…"
# 只按「进程名精确匹配」结束本应用：pkill -f 会匹配命令行里任何含 Tokenitor 的进程
#（例如正在编辑本项目的编辑器、终端里的 grep），误杀风险高。
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
sleep 1
pkill -x "${APP_NAME}" 2>/dev/null || true

echo "==> 移除登录项…"
osascript -e "tell application \"System Events\" to delete (every login item whose name is \"${APP_NAME}\")" 2>/dev/null || true

echo "==> 删除 App…"
if [ -d "${DEST_APP}" ]; then
    rm -rf "${DEST_APP}" 2>/dev/null || sudo rm -rf "${DEST_APP}"
    echo "  已删除 ${DEST_APP}"
else
    echo "  /Applications 下未找到，跳过"
fi

echo "==> 清理钥匙串凭据…"
# 本应用自己写入的条目（Copilot device flow token、Claude 读取缓存等）都在 service=com.tokenitor.app 下；
# 各 AI 工具自己的凭据不属于本应用，绝不触碰。同名条目可能有多条，循环删到没有为止。
while security delete-generic-password -s "com.tokenitor.app" >/dev/null 2>&1; do :; done
echo "  已移除 service=com.tokenitor.app 的条目（其它 App 的凭据未触碰）"

echo "==> 清理设置、缓存与日志…"
rm -rf ~/.tokenitor 2>/dev/null || true
defaults delete com.tokenitor.app 2>/dev/null || true
echo "  已删除 ~/.tokenitor 与偏好设置"

echo "完成 ✅  Tokenitor 及其本地数据已彻底移除。"
