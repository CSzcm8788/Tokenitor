#!/usr/bin/env bash
# 编译并打包成 Tokenitor.app（菜单栏应用）。
# 需要：macOS + Xcode 命令行工具（含 swift）。无需打开 Xcode。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Tokenitor"
BUNDLE_ID="com.tokenitor.app"
VERSION="1.4.3"
BUILD_NUM="$(date +%Y%m%d%H%M)"   # 每次构建递增的 build 号：让 macOS 注意到图标变化、刷新通知图标缓存
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"

echo "==> 编译 (release)…"
swift build -c release

echo "==> 组装 .app 包…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo "==> 生成应用图标 (AppIcon.icns)…"
ICON_FILE=""
if [ -d "Icon/AppIcon.iconset" ] && command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns "Icon/AppIcon.iconset" -o "${APP_DIR}/Contents/Resources/AppIcon.icns" \
        && ICON_FILE="AppIcon" \
        && echo "  图标已生成"
else
    echo "  跳过（缺 Icon/AppIcon.iconset 或 iconutil）"
fi

# AI 品牌 logo 已彻底移除（2026-07）：应用只用名称文字标识各 AI，不再打包任何第三方商标图片。

# 菜单栏单色 logo（18pt + @2x，模板图，运行时 NSImage(named:"menubar") 加载，自动适配亮/暗）
if [ -d "Icon/menubar" ]; then
    cp Icon/menubar/menubar.png Icon/menubar/menubar@2x.png "${APP_DIR}/Contents/Resources/" 2>/dev/null && echo "  已打包菜单栏 logo" || true
fi

# 一键重登脚本（供 App 内「重新登录 Claude」调用）
if [ -f "relogin-claude.sh" ]; then
    cp relogin-claude.sh "${APP_DIR}/Contents/Resources/relogin-claude.sh"
    chmod +x "${APP_DIR}/Contents/Resources/relogin-claude.sh"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>Tokenitor</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>         <string>${BUILD_NUM}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>        <string>${ICON_FILE}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHumanReadableCopyright</key> <string>Local build</string>
    <key>NSAppleEventsUsageDescription</key> <string>Tokenitor 用它在终端里帮你重新登录 Claude 订阅。</string>
</dict>
</plist>
PLIST

# 签名身份：优先用环境变量 CODESIGN_ID；否则自动查找是否有 "Tokenitor Self"
# 自签名证书（有则用之，原生通知/正确图标），没有则回退 ad-hoc（-）。
SIGN_ID="${CODESIGN_ID:-}"
if [ -z "${SIGN_ID}" ]; then
  # 优先用 Developer ID Application（稳定身份：通知授权/图标不再反复失效）
  DEVID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
  if [ -n "${DEVID}" ]; then
    SIGN_ID="${DEVID}"
  elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Tokenitor Self"; then
    SIGN_ID="Tokenitor Self"
  else
    SIGN_ID="-"
  fi
fi
echo "==> 代码签名（identity: ${SIGN_ID}）…"
codesign --force --deep --sign "${SIGN_ID}" "${APP_DIR}" \
  && echo "  已签名" \
  || echo "  (签名失败可忽略，通知会回退到 osascript)"

# 刷新启动服务 + 通知图标缓存：换图标后，让通知/Dock 显示新图标（usernoted 会自动重启）
echo "==> 刷新图标/通知缓存…"
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "${APP_DIR}" 2>/dev/null || true
killall usernoted 2>/dev/null || true

echo ""
echo "完成 ✅  应用位于: ${APP_DIR}"
echo "运行:   open \"${APP_DIR}\""
echo "或拖到「应用程序」文件夹。首次运行若被 Gatekeeper 拦截，右键→打开。"
