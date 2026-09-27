#!/usr/bin/env bash
# Godot 헤드리스 테스트 실행. 사용법: GODOT=/path/to/godot tests/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# 새 class_name 등록을 위해 먼저 임포트(에디터 스캔)
timeout 180 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
status=0
for t in tests/test_balance.gd tests/test_season.gd; do
  echo "== $t"
  out=$(timeout 900 "$GODOT" --headless --path . -s "$t" 2>&1) || status=1
  echo "$out" | grep -v "^Godot Engine" | tail -12
  echo "$out" | grep -q "SCRIPT ERROR" && status=1
done
exit $status
