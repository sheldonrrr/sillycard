#!/usr/bin/env bash
# 基于 Resources/CardSamples 扫描描述类字段的 HTML/Markdown 捕捉与富文本输出，打印统计与优化结论；若渲染后仍残留成对 **/*** 则测试失败。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -d "$ROOT/Resources/CardSamples" ]]; then
  echo "错误：未找到 Resources/CardSamples" >&2
  exit 1
fi

echo "→ swift test --filter CardStyleCaptureReportTests"
swift test --filter CardStyleCaptureReportTests
