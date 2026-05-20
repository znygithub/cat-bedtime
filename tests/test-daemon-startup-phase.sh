#!/usr/bin/env bash
# Regression: daemon RunAtLoad/catch-up must only do work inside the active
# wind-down or lock window. Daytime starts should exit immediately.
set -euo pipefail

time_in_range() {
  local now_min="$1" start_min="$2" end_min="$3"
  if (( start_min < end_min )); then
    (( now_min >= start_min && now_min < end_min ))
  elif (( start_min > end_min )); then
    (( now_min >= start_min || now_min < end_min ))
  else
    return 1
  fi
}

phase_at() {
  local now_min="$1" bed_min="$2" wake_min="$3" winddown="$4"
  local start_min=$(( bed_min - winddown ))
  (( start_min < 0 )) && (( start_min += 1440 ))

  if time_in_range "$now_min" "$bed_min" "$wake_min"; then
    echo "lockdown"
  elif time_in_range "$now_min" "$start_min" "$bed_min"; then
    echo "winddown"
  else
    echo "idle"
  fi
}

pass=0
fail=0

check_phase() {
  local now="$1" bed="$2" wake="$3" winddown="$4" expect="$5" label="$6"
  local result
  result=$(phase_at "$now" "$bed" "$wake" "$winddown")
  if [[ "$result" == "$expect" ]]; then
    echo "  OK: $label -> $result"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label -> expected $expect, got $result" >&2
    fail=$((fail + 1))
  fi
}

echo "=== daemon startup phase ==="

# bed=23:00, wake=07:00, winddown=15
check_phase 1364 1380 420 15 idle     "22:44 before wind-down"
check_phase 1365 1380 420 15 winddown "22:45 wind-down start"
check_phase 1379 1380 420 15 winddown "22:59 still wind-down"
check_phase 1380 1380 420 15 lockdown "23:00 bedtime"
check_phase 30   1380 420 15 lockdown "00:30 lock catch-up"
check_phase 420  1380 420 15 idle     "07:00 wake"

# bed=00:10, wake=08:00, winddown=15 wraps across midnight.
check_phase 1434 10 480 15 idle     "23:54 before wrapped wind-down"
check_phase 1435 10 480 15 winddown "23:55 wrapped wind-down start"
check_phase 5    10 480 15 winddown "00:05 still wrapped wind-down"
check_phase 10   10 480 15 lockdown "00:10 bedtime"
check_phase 479  10 480 15 lockdown "07:59 still locked"
check_phase 480  10 480 15 idle     "08:00 wake"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
