#!/usr/bin/env bash
# 一键：构建 → 安装到「应用程序」→ 启动。（开机自启改由 app 设置页的开关控制）
# 用法：bash install.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Tokenitor"
SRC_APP="dist/${APP_NAME}.app"
DEST_APP="/Applications/${APP_NAME}.app"

echo "==> [1/4] 关闭正在运行的旧实例…"
# 先请它优雅退出；pkill 用 -x 精确匹配进程名（-f 匹配整条命令行，
# 会误杀任何参数里带 Tokenitor 的进程，比如正在编辑本仓库文件的编辑器）
osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 1

echo "==> [2/4] 构建…"
bash build.sh

if [ ! -d "${SRC_APP}" ]; then
    echo "✗ 构建产物不存在：${SRC_APP}"; exit 1
fi

echo "==> [3/4] 安装到「应用程序」…"
rm -rf "${DEST_APP}"
if cp -R "${SRC_APP}" "${DEST_APP}" 2>/dev/null; then
    echo "  已安装到 ${DEST_APP}"
else
    echo "  无权限写入 /Applications，尝试 sudo（可能要输入密码）…"
    sudo rm -rf "${DEST_APP}"
    sudo cp -R "${SRC_APP}" "${DEST_APP}"
fi

# 重新 ad-hoc 签名，避免拷贝后签名失效导致通知/钥匙串异常
codesign --force --deep --sign - "${DEST_APP}" 2>/dev/null || true

echo "==> [4/4] 启动…"
open "${DEST_APP}"

echo ""
echo "完成 ✅"
echo "  · 应用已装到「应用程序」并启动"
echo "  · 图标在屏幕右上角菜单栏（带刘海的机型可用 Ice 把隐藏图标拖出来）"
echo "  · 开机自启：在设置页打开「开机自启」开关（免密、系统原生登录项）"
echo "  · 首次刷新 Claude 数据可能弹「允许访问钥匙串」：这是在读取 Claude Code 的登录凭证。"
echo "    建议点「允许」（每次询问）；「始终允许」会永久放行，不推荐"
echo ""
echo "卸载：bash uninstall.sh"
