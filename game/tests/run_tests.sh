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
# 2) 테스트 실행. 스크립트 오류가 나면 테스트가 끝나지 않고 멈춘 것처럼 보이므로,
#    출력에 SCRIPT ERROR 가 보이면 바로 중단하고 오류를 보여 준다.
for t in tests/test_balance.gd tests/test_season.gd tests/test_save.gd; do
  echo "== $t"
  log=$(mktemp)
  timeout 900 "$GODOT" --headless --path . -s "$t" > "$log" 2>&1 &
  pid=$!
  while kill -0 $pid 2>/dev/null; do
    if grep -q "SCRIPT ERROR" "$log"; then
      sleep 1
      kill $pid 2>/dev/null || true
      echo "  !! 스크립트 오류로 중단"
      break
    fi
    sleep 1
  done
  wait $pid || status=1
  grep -v "^Godot Engine" "$log" | tail -12
  grep -q "SCRIPT ERROR" "$log" && status=1
  rm -f "$log"
done
exit $status
