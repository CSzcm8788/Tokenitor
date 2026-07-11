#!/usr/bin/env bash
# 对照 LiteLLM 社区定价表（MIT 许可）：一致则跳过，不一致则更新打包快照。
# 每次发版前运行（release 流程的前置步骤）；应用运行时不联网拉取。
set -euo pipefail
cd "$(dirname "$0")"

URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
TMP=$(mktemp)
curl -fsSL -m 60 "$URL" -o "$TMP"
python3 -c "import json; d=json.load(open('$TMP')); assert len(d)>1000, '条目异常'"   # 校验 JSON + 基本体量

NEW=$(shasum -a 256 "$TMP" | cut -d' ' -f1)
OLD=$(shasum -a 256 Pricing/model_prices.json 2>/dev/null | cut -d' ' -f1 || echo none)
if [ "$NEW" = "$OLD" ]; then
  echo "定价快照与上游一致（跳过）"
  rm -f "$TMP"; exit 0
fi
mkdir -p Pricing
mv "$TMP" Pricing/model_prices.json
printf '{"updated":"%s","sha256":"%s"}\n' "$(date +%Y-%m-%d)" "$NEW" > Pricing/model_prices_meta.json
echo "定价快照已更新（$(date +%Y-%m-%d)）→ 随本次版本一并提交"
