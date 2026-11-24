#!/usr/bin/env bash
# Runs every headless test suite once. Usage: tests/run_all.sh [path-to-godot]
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --editor --path . --import --quit >/dev/null 2>&1
status=0
for t in smoke acceptance first_night; do
  echo "== $t"
  out=$("$GODOT" --headless --path . --script "tests/$t.gd" 2>&1)
  code=$?
  printf '%s\n' "$out" | grep -E "^(SMOKE|ACCEPTANCE|FIRST NIGHT)|FAIL|^ok " || true
  [ "$code" -ne 0 ] && status=1
done
exit $status
