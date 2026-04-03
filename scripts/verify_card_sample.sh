#!/usr/bin/env bash
# 使用 Resources/CardSamples 中的 PNG 跑核心逻辑回归（无 UI）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -d "$ROOT/Resources/CardSamples" ]]; then
  echo "错误：未找到 Resources/CardSamples（请保留示例卡或运行 swift run EmbedMeo）" >&2
  exit 1
fi

echo "→ swift test（SillycardSampleTests）…"
swift test --filter SillycardSampleTests

echo "→ 完成：全部通过。"
