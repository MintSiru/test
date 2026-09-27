#!/usr/bin/env bash
# Godot 헤드리스 테스트 실행. 사용법: GODOT=/path/to/godot tests/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# 새 class_name 등록을 위해 먼저 임포트(에디터 스캔)
timeout 180 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
status=0
# 1) 모든 스크립트 파스 검사 (autoload 이름 Game 은 검사 모드에서 인식되지 않으므로 제외)
echo "== 스크립트 파스 검사"
for f in $(find scripts tests -name "*.gd"); do
  errs=$(timeout 60 "$GODOT" --headless --path . --check-only --script "$f" 2>&1 | grep "SCRIPT ERROR" | grep -v "Identifier not found: Game" | grep -v "Failed to compile depended scripts" || true)
  if [ -n "$errs" ]; then echo "$f: $errs"; status=1; fi
done
[ $status -eq 0 ] && echo "  파스 검사 OK"
for t in tests/test_balance.gd tests/test_season.gd; do
  echo "== $t"
  out=$(timeout 900 "$GODOT" --headless --path . -s "$t" 2>&1) || status=1
  echo "$out" | grep -v "^Godot Engine" | tail -12
  echo "$out" | grep -q "SCRIPT ERROR" && status=1
done
exit $status
