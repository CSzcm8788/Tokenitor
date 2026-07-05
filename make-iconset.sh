#!/usr/bin/env bash
# 从一张方形 PNG（建议 1024×1024，黑底/透明都行）生成 macOS 全套 AppIcon.iconset。
# 之后 build.sh 会自动把它打成 AppIcon.icns 并应用为 App 图标。
#
# 用法:
#   bash make-iconset.sh /path/to/logo-1024.png
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "用法: bash make-iconset.sh <源图.png>（建议 1024×1024 方形）"
  exit 1
fi

OUT="Icon/AppIcon.iconset"
rm -rf "$OUT"; mkdir -p "$OUT"

gen() { sips -z "$2" "$2" "$SRC" --out "$OUT/$1" >/dev/null; }
gen icon_16x16.png        16
gen icon_16x16@2x.png     32
gen icon_32x32.png        32
gen icon_32x32@2x.png     64
gen icon_128x128.png      128
gen icon_128x128@2x.png   256
gen icon_256x256.png      256
gen icon_256x256@2x.png   512
gen icon_512x512.png      512
gen icon_512x512@2x.png   1024

echo "✅ 已生成 $OUT（10 个尺寸）"
echo "接着跑：bash build.sh && open dist/Tokenitor.app  —— 新图标即生效。"
