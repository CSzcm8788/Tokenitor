#!/usr/bin/env bash
# 一键：构建 → 安装到「应用程序」→ 启动。（开机自启改由 app 设置页的开关控制）
# 用法：bash install.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Tokenitor"
SRC_APP="dist/${APP_NAME}.app"
DEST_APP="/Applications/${APP_NAME}.app"

echo "==> [1/4] 关闭正在运行的旧实例…"
pkill -f "${APP_NAME}" 2>/dev/null || true
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
echo "  · 首次刷新 Claude 数据若弹「允许访问钥匙串」，点「始终允许」"
echo ""
echo "卸载：bash uninstall.sh"
