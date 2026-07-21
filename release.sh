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

# 0) 发布前置检查：保证「这个 DMG 一定来自这次提交」
echo "==> 发布前置检查…"

# a. 工作区必须干净（dist/ 与 .build/ 是产物，不计入）
DIRTY="$(git status --porcelain -- . ':!dist' ':!.build' 2>/dev/null || true)"
if [ -n "${DIRTY}" ]; then
  echo "✗ 工作区有未提交改动，发布产物将无法追溯到某次提交。请先提交："
  echo "${DIRTY}" | sed 's/^/    /'
  exit 1
fi

# b. 版本号两处一致（build.sh 的 VERSION 与 Branding.swift 的兜底值）
VER_BUILD="$(sed -nE 's/^VERSION="([^"]+)".*/\1/p' build.sh | head -1)"
VER_BRAND="$(sed -nE 's/.*\?\? "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' Sources/Tokenitor/Branding.swift | head -1)"
if [ "${VER_BUILD}" != "${VER_BRAND}" ]; then
  echo "✗ 版本号不一致：build.sh=${VER_BUILD} vs Branding.swift=${VER_BRAND}"; exit 1
fi
echo "  版本 ${VER_BUILD}（两处一致）"

# c. 若 v<版本> 标签已存在，必须指向当前 HEAD（防止用旧代码重发同一版本）
HEAD_SHA="$(git rev-parse HEAD)"
if git rev-parse "v${VER_BUILD}" >/dev/null 2>&1; then
  TAG_SHA="$(git rev-parse "v${VER_BUILD}^{commit}")"
  if [ "${TAG_SHA}" != "${HEAD_SHA}" ]; then
    echo "✗ 标签 v${VER_BUILD} 指向 ${TAG_SHA:0:8}，与 HEAD ${HEAD_SHA:0:8} 不符"; exit 1
  fi
fi

# d. HEAD 必须已推送到远端（Release 页要能对上源码）
if git rev-parse '@{u}' >/dev/null 2>&1; then
  if [ "$(git rev-parse '@{u}')" != "${HEAD_SHA}" ]; then
    echo "✗ HEAD 尚未推送到远端，请先 git push"; exit 1
  fi
fi

# e. 测试必须全绿
echo "==> 运行测试…"
# 直接取 swift test 的退出码（不经管道，避免退出状态被 tail 之类掩盖）；
# 只在失败时打印尾部日志，成功时打印 XCTest 的用例数汇总行。
if ! TEST_OUT="$(swift test 2>&1)"; then
  echo "✗ 测试未通过，中止发布"
  echo "${TEST_OUT}" | tail -25
  exit 1
fi
echo "${TEST_OUT}" | grep -E "Executed [0-9]+ tests" | tail -1 | sed 's/^[[:space:]]*/  /

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

# 1.5) 对照 LiteLLM 社区定价：一致跳过；不一致则更新快照并要求先提交（保证 DMG 与仓库一致）
echo "==> 对照社区定价快照…"
bash sync-pricing.sh || echo "  (网络不可用，沿用现有快照)"
if ! git diff --quiet -- Pricing/ 2>/dev/null; then
  echo "✗ 定价快照刚被更新但未提交——请先提交 Pricing/ 再发版"; exit 1
fi

# 2) 构建（用现有 build.sh 产出 .app）。先用 ad-hoc 出包，下面再用 Developer ID 重签。
echo "==> 构建…"
CODESIGN_ID="-" bash build.sh >/dev/null

# 产物溯源：build.sh 把构建时的 git commit 写进 Info.plist，这里核对它就是本次 HEAD
BUILT_SHA="$(/usr/libexec/PlistBuddy -c "Print :TokenitorSourceCommit" "${APP}/Contents/Info.plist" 2>/dev/null || echo "")"
if [ "${BUILT_SHA}" != "${HEAD_SHA}" ]; then
  echo "✗ 产物记录的源码 commit (${BUILT_SHA:0:8}) 与 HEAD (${HEAD_SHA:0:8}) 不符"; exit 1
fi
echo "  产物溯源 OK：source commit ${HEAD_SHA:0:8}"

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
