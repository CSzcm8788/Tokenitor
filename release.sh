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
echo "${TEST_OUT}" | grep -E "Executed [0-9]+ tests" | tail -1 | sed 's/^[[:space:]]*/  /'

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

# 4) 出 DMG（hdiutil，免额外依赖）——先打包，再**只公证这一个**产物
echo "==> 制作 DMG…"
STAGE="dist/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tokenitor" -srcfolder "$STAGE" -ov -format UDZO "dist/${APP_NAME}.dmg" >/dev/null
rm -rf "$STAGE"
codesign --force --sign "$DEVID_APP" "dist/${APP_NAME}.dmg"

# 5) 公证：**一次提交**（DMG 内含已签名的 .app，公证会记录其中每个可执行文件的 cdhash，
#    因此随后可以给 .app 与 DMG 分别盖章，无需再单独公证一次 app.zip）。
#    Apple 建议每账号每天不超过 75 次公证；此前每次发版提交 2 次是无谓的浪费。
MARKER="dist/.notarized-${HEAD_SHA}"
if [ -f "${MARKER}" ] && xcrun stapler validate "dist/${APP_NAME}.dmg" >/dev/null 2>&1; then
  echo "==> 本次提交已公证过且 DMG 已盖章，跳过重复公证"
else
  echo "==> 公证（notarytool，单次提交，通常 1-5 分钟）…"
  SUB_ID="$(xcrun notarytool submit "dist/${APP_NAME}.dmg" --keychain-profile "$NOTARY_PROFILE" \
              --output-format json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  if [ -z "${SUB_ID}" ]; then echo "✗ 提交失败（未拿到 submission id）"; exit 1; fi
  echo "  submission id: ${SUB_ID}"

  # 轮询而不是依赖 --wait 的长连接：notarytool 的等待连接被网络掐断时会报
  # HTTPClientError.connectTimeout，此时任务其实已在 Apple 侧排队——重新提交只会白白
  # 消耗额度。这里改为查状态，连接失败就下一轮再查。
  DEADLINE=$(( $(date +%s) + 3600 ))
  while :; do
    ST="$(xcrun notarytool info "${SUB_ID}" --keychain-profile "$NOTARY_PROFILE" \
            --output-format json 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("status",""))
except Exception: print("")' )"
    case "${ST}" in
      Accepted) echo "  状态: Accepted"; break ;;
      "Invalid"|"Rejected")
        echo "✗ 公证被拒，日志："
        xcrun notarytool log "${SUB_ID}" --keychain-profile "$NOTARY_PROFILE" 2>&1 | head -40
        exit 1 ;;
      *) : ;;   # In Progress / 查询失败 → 继续等
    esac
    if [ "$(date +%s)" -gt "${DEADLINE}" ]; then
      echo "✗ 公证超过 1 小时仍未完成（Apple 侧排队）。任务仍在进行，稍后可用："
      echo "    xcrun notarytool info ${SUB_ID} --keychain-profile ${NOTARY_PROFILE}"
      echo "  完成后重跑 release.sh 即可（会自动跳过重复公证）。"
      exit 1
    fi
    sleep 20
  done
  touch "${MARKER}"
fi

# 6) 盖章：DMG 与 .app 都盖（.app 的票据由上面那次 DMG 公证一并签发，stapler 按 cdhash 取回）
echo "==> 盖公证章…"
xcrun stapler staple "dist/${APP_NAME}.dmg"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
xcrun stapler validate "dist/${APP_NAME}.dmg"

echo ""
echo "完成 ✅  可分发文件: dist/${APP_NAME}.dmg（已签名 + 已公证 + 已盖章）"
echo "别人下载打开不会被 Gatekeeper 拦截。"
