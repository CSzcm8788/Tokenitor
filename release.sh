#!/usr/bin/env bash
# Tokenitor 发布：Developer ID 签名 + Hardened Runtime + 公证 + 盖章 + 出 DMG。
# 前置：已装 Xcode、已生成 Developer ID Application 证书、已用
#       xcrun notarytool store-credentials "Tokenitor-Notary" 存好公证凭证。
#
# 用法：
#   bash release.sh
# 可选环境变量：
#   DEVID_APP="Developer ID Application: 你的名字 (TEAMID)"   # 不填则自动探测
#   NOTARY_PROFILE="Tokenitor-Notary"                          # 公证钥匙串配置名
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Tokenitor"
APP="dist/${APP_NAME}.app"
ENT="Tokenitor.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-Tokenitor-Notary}"

# 1) 自动探测 Developer ID Application 身份
if [ -z "${DEVID_APP:-}" ]; then
  DEVID_APP=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi
if [ -z "${DEVID_APP:-}" ]; then
  echo "✗ 未找到 Developer ID Application 证书。请先在 Xcode → Settings → Accounts 生成。"
  exit 1
fi
echo "==> 签名身份: ${DEVID_APP}"

# 2) 构建（用现有 build.sh 产出 .app）。先用 ad-hoc 出包，下面再用 Developer ID 重签。
echo "==> 构建…"
CODESIGN_ID="-" bash build.sh >/dev/null

# 3) Developer ID 签名 + Hardened Runtime + 时间戳 + entitlements（深度签名）
echo "==> Developer ID 签名 + Hardened Runtime…"
# 先签内部可执行文件，再签 .app 本体
find "$APP/Contents" -type f \( -name "*.dylib" -o -perm -111 \) -not -path "*/MacOS/${APP_NAME}" -print0 2>/dev/null \
  | xargs -0 -I{} codesign --force --options runtime --timestamp --sign "$DEVID_APP" "{}" 2>/dev/null || true
codesign --force --options runtime --timestamp \
  --entitlements "$ENT" --sign "$DEVID_APP" "$APP/Contents/MacOS/${APP_NAME}"
codesign --force --options runtime --timestamp \
  --entitlements "$ENT" --sign "$DEVID_APP" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "  签名校验通过"

# 4) 公证（打 zip 提交，等待结果）
echo "==> 公证（notarytool，等待中，约 1-5 分钟）…"
ditto -c -k --keepParent "$APP" "dist/${APP_NAME}.zip"
xcrun notarytool submit "dist/${APP_NAME}.zip" --keychain-profile "$NOTARY_PROFILE" --wait

# 5) 盖章
echo "==> 盖公证章…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 6) 出 DMG（hdiutil，免额外依赖）
echo "==> 制作 DMG…"
STAGE="dist/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tokenitor" -srcfolder "$STAGE" -ov -format UDZO "dist/${APP_NAME}.dmg" >/dev/null
rm -rf "$STAGE"

# 7) DMG 也签名 + 公证 + 盖章
echo "==> 签名 + 公证 DMG…"
codesign --force --sign "$DEVID_APP" "dist/${APP_NAME}.dmg"
xcrun notarytool submit "dist/${APP_NAME}.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "dist/${APP_NAME}.dmg"

echo ""
echo "完成 ✅  可分发文件: dist/${APP_NAME}.dmg（已签名 + 已公证 + 已盖章）"
echo "别人下载打开不会被 Gatekeeper 拦截。"
