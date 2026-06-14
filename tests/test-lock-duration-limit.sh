#!/usr/bin/env bash
# Regression: lock windows must stay under 15 hours. Exactly 15h is rejected.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/config.sh"

pass=0
fail=0

check_duration() {
  local bedtime="$1" wakeup="$2" expect="$3" label="$4"
  local result duration
  duration=$(lock_duration_minutes_for_times "$bedtime" "$wakeup")
  if lock_duration_allowed_for_times "$bedtime" "$wakeup"; then
    result=true
  else
    result=false
  fi

  if [[ "$result" == "$expect" ]]; then
    echo "  OK: $label ($bedtime->$wakeup, ${duration}min) -> allowed=$result"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label ($bedtime->$wakeup, ${duration}min) -> expected $expect, got $result" >&2
    fail=$((fail + 1))
  fi
}

echo "=== lock duration limit ==="

check_duration "23:00" "13:59" true  "under 15h is allowed"
check_duration "23:00" "14:00" false "exactly 15h is rejected"
check_duration "23:00" "14:01" false "over 15h is rejected"
check_duration "10:20" "10:30" true  "short same-day demo is allowed"
check_duration "10:50" "10:30" false "postponing past wake creates a next-day unlock"
check_duration "10:30" "10:30" false "same bedtime and wakeup would lock all day"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
