#!/usr/bin/env bash
# Test: _overslept() correctly detects when Mac woke up after bedtime window
# and sleep_until() / wind-down wall-clock targets are computed correctly.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/config.sh"

# ── Mock config ──────────────────────────────────────────────────
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
printf '%s\n' '{"bedtime":"23:00","wakeup":"07:00","winddown_minutes":30,"days":["1","2","3","4","5","6","7"]}' >"$TMP"
ZZZ_CONFIG="$TMP"
BEDTIME="23:00"
WAKEUP="07:00"
WINDDOWN=30

# ── _overslept: testable version (accepts now_min as $1) ─────────
_overslept_at() {
  local now_min="$1" wake_min start_min bed_min
  wake_min=$(time_to_minutes "$WAKEUP")
  bed_min=$(time_to_minutes "$BEDTIME")
  start_min=$(( bed_min - WINDDOWN ))
  (( start_min < 0 )) && (( start_min += 1440 ))
  if (( start_min > wake_min )); then
    (( now_min >= wake_min && now_min < start_min ))
  else
    (( now_min >= wake_min || now_min < start_min ))
  fi
}

# ── Test runner ──────────────────────────────────────────────────
pass=0 fail=0
assert() {
  local time_min=$1 expected=$2 label=$3
  local result
  if _overslept_at "$time_min"; then result="true"; else result="false"; fi
  if [[ "$result" == "$expected" ]]; then
    echo "  OK: $label (now=$time_min -> overslept=$result)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label (now=$time_min -> expected $expected, got $result)" >&2
    fail=$((fail + 1))
  fi
}

echo "=== _overslept (bed=23:00, wake=07:00, winddown=30) ==="
echo "    wind-down start = 22:30, overslept zone = [07:00, 22:30)"
echo ""

# During wind-down (22:30 ~ 23:00) → NOT overslept
assert 1350 "false" "22:30 (wind-down start)"
assert 1370 "false" "22:50 (mid wind-down)"
assert 1378 "false" "22:58 (2 min before bed)"

# During lockdown (23:00 ~ 07:00) → NOT overslept
assert 1380 "false" "23:00 (bedtime)"
assert 1410 "false" "23:30 (mid night)"
assert 0    "false" "00:00 (midnight)"
assert 180  "false" "03:00 (deep night)"
assert 419  "false" "06:59 (just before wake)"

# Daytime (07:00 ~ 22:30) → overslept
assert 420  "true" "07:00 (wakeup)"
assert 480  "true" "08:00 (morning)"
assert 540  "true" "09:00 (late morning)"
assert 720  "true" "12:00 (noon)"
assert 1080 "true" "18:00 (evening)"
assert 1320 "true" "22:00 (2h before wind-down)"
assert 1349 "true" "22:29 (1min before wind-down)"

echo ""

# ── Test wall-clock stage targets ────────────────────────────────
echo "=== Wall-clock stage targets (bed=23:00, winddown=30) ==="
bed_min=$(time_to_minutes "$BEDTIME")
stage2_at=$(( bed_min - WINDDOWN * 2 / 3 ))
(( stage2_at < 0 )) && (( stage2_at += 1440 ))
stage3_at=$(( bed_min - WINDDOWN / 3 ))
(( stage3_at < 0 )) && (( stage3_at += 1440 ))
warn_at=$(( bed_min - 1 ))
  (( warn_at < 0 )) && (( warn_at += 1440 ))

s2_time=$(minutes_to_time $stage2_at)
s3_time=$(minutes_to_time $stage3_at)
w_time=$(minutes_to_time $warn_at)

check_target() {
  local got=$1 expected=$2 label=$3
  if [[ "$got" == "$expected" ]]; then
    echo "  OK: $label = $got"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label = $got (expected $expected)" >&2
    fail=$((fail + 1))
  fi
}

check_target "$s2_time" "22:40" "stage2"
check_target "$s3_time" "22:50" "stage3"
check_target "$w_time"  "22:59" "1-min toast"

echo ""

# ── Edge case: bedtime near midnight (bed=00:30, wake=08:00, winddown=30) ──
echo "=== Edge case: bedtime near midnight (bed=00:30, wake=08:00, winddown=30) ==="
BEDTIME="00:30"
WAKEUP="08:00"
WINDDOWN=30

assert 0    "false" "00:00 (wind-down zone)"
assert 15   "false" "00:15 (wind-down zone)"
assert 30   "false" "00:30 (bedtime)"
assert 120  "false" "02:00 (lockdown)"
assert 479  "false" "07:59 (just before wake)"
assert 480  "true"  "08:00 (wakeup)"
assert 720  "true"  "12:00 (noon)"
assert 1410 "true"  "23:30 (night, before wind-down start)"
assert 1439 "true"  "23:59 (1 min before wind-down start, still daytime)"

bed_min2=$(time_to_minutes "$BEDTIME")
wd_start=$(( bed_min2 - 30 ))
(( wd_start < 0 )) && (( wd_start += 1440 ))
check_target "$(minutes_to_time $wd_start)" "00:00" "wind-down start"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
