#!/usr/bin/env bash
# Regression: changing bedtime after the wind-down trigger has passed should
# kickstart today's daemon instead of waiting until tomorrow.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/schedule.sh"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
ZZZ_CONFIG="$TMP"

mock_now=0
mock_weekday=1

now_minutes() { echo "$mock_now"; }
today_weekday() { echo "$mock_weekday"; }

write_config() {
  local bedtime="$1" wakeup="$2" winddown="$3" days_json="$4"
  printf '{"bedtime":"%s","wakeup":"%s","winddown_minutes":%s,"days":%s}\n' \
    "$bedtime" "$wakeup" "$winddown" "$days_json" > "$ZZZ_CONFIG"
}

pass=0
fail=0

check() {
  local now="$1" weekday="$2" bedtime="$3" wakeup="$4" winddown="$5" days="$6" expect="$7" label="$8"
  mock_now="$now"
  mock_weekday="$weekday"
  write_config "$bedtime" "$wakeup" "$winddown" "$days"

  local result
  if _should_kickstart_now; then
    result=true
  else
    result=false
  fi

  if [[ "$result" == "$expect" ]]; then
    echo "  OK: $label -> kickstart=$result"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label -> expected $expect, got $result" >&2
    fail=$((fail + 1))
  fi
}

echo "=== schedule catch-up kickstart ==="

# Monday 23:35, bedtime 23:36, winddown started at 23:21.
check 1415 1 "23:36" "07:00" 15 '["1"]' true \
  "saved during same-day wind-down window"

check 1400 1 "23:36" "07:00" 15 '["1"]' false \
  "saved before wind-down window"

# Tuesday 00:30 still belongs to Monday night's 23:36 sleep window.
check 30 2 "23:36" "07:00" 15 '["1"]' true \
  "after midnight uses previous weekday for overnight lock"

check 30 2 "23:36" "07:00" 15 '["2"]' false \
  "after midnight does not count as the new weekday"

# Friday 23:58 belongs to Saturday's 00:10 bedtime when wind-down wraps midnight.
check 1438 5 "00:10" "08:00" 15 '["6"]' true \
  "pre-midnight wind-down uses next weekday for after-midnight bedtime"

check 1438 5 "00:10" "08:00" 15 '["5"]' false \
  "pre-midnight wind-down does not use current weekday for after-midnight bedtime"

check 720 1 "23:36" "07:00" 15 '["1"]' false \
  "daytime does not kickstart"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
