#!/usr/bin/env bash
# Lockdown window math (must match bootcheck.sh) + daemon syntax check.
# Regression: 21:00 with bed 23:00~wake 07:00 must NOT be in lockdown.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== bash -n (syntax) ==="
for f in src/daemon.sh src/bootcheck.sh; do
  if ! bash -n "$f"; then
    echo "FAIL: bash -n $f" >&2
    exit 1
  fi
  echo "  OK: $f"
done

# Same predicate as bootcheck.sh.
in_lockdown() {
  local now=$1 bed=$2 wake=$3
  if (( bed > wake )); then
    (( now >= bed || now < wake ))
  else
    (( now >= bed && now < wake ))
  fi
}

previous_weekday() {
  local weekday=$1
  if (( weekday == 1 )); then echo 7; else echo $((weekday - 1)); fi
}

lock_weekday() {
  local now=$1 bed=$2 wake=$3 current_weekday=$4
  if (( bed > wake && now < wake )); then
    previous_weekday "$current_weekday"
  else
    echo "$current_weekday"
  fi
}

active_lockdown() {
  local now=$1 bed=$2 wake=$3 current_weekday=$4 active_days=$5
  local weekday
  if ! in_lockdown "$now" "$bed" "$wake"; then
    return 1
  fi
  weekday=$(lock_weekday "$now" "$bed" "$wake" "$current_weekday")
  printf '%s\n' "$active_days" | grep -q "^${weekday}$"
}

pass=0
fail=0
check() {
  local now=$1 bed=$2 wake=$3 expect=$4 label=$5
  local result
  if in_lockdown "$now" "$bed" "$wake"; then result=true; else result=false; fi
  if [[ $result == "$expect" ]]; then
    echo "  OK: $label (now=$now min -> lockdown=$result)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label — expected lockdown=$expect, got $result" >&2
    fail=$((fail + 1))
  fi
}

check_active() {
  local now=$1 bed=$2 wake=$3 current_weekday=$4 active_days=$5 expect=$6 label=$7
  local result
  if active_lockdown "$now" "$bed" "$wake" "$current_weekday" "$active_days"; then result=true; else result=false; fi
  if [[ $result == "$expect" ]]; then
    echo "  OK: $label (now=$now min, weekday=$current_weekday -> active_lockdown=$result)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label — expected active_lockdown=$expect, got $result" >&2
    fail=$((fail + 1))
  fi
}

# bed=23:00=1380, wake=07:00=420
B=1380
W=420
echo ""
echo "=== Lock window (bed 23:00, wake 07:00), same as bootcheck ==="
check $((21 * 60)) "$B" "$W" false "21:00 晚上九点 — 不应锁屏 (user regression)"
check $((22 * 60 + 29)) "$B" "$W" false "22:29 — 风睡前不应锁 (bootcheck)"
check 1350 "$B" "$W" false "22:30 — wind-down 开始仍不应锁 (bootcheck 仅看 bed~wake)"
check 1380 "$B" "$W" true  "23:00 就寝 — 应锁"
check 0 "$B" "$W"         true  "00:00 — 应锁"
check 180 "$B" "$W"        true  "03:00 — 应锁"
check 419 "$B" "$W"        true  "06:59 — 应锁"
check 420 "$B" "$W"        false "07:00 起床 — 不应锁"
check 480 "$B" "$W"        false "08:00 — 不应锁"

# Same-day lock window: bed=01:00=60, wake=08:00=480
B=60
W=480
echo ""
echo "=== Lock window (bed 01:00, wake 08:00), same as bootcheck ==="
check 0 "$B" "$W"          false "00:00 — 不应锁"
check 59 "$B" "$W"         false "00:59 — 不应锁"
check 60 "$B" "$W"         true  "01:00 就寝 — 应锁"
check 240 "$B" "$W"        true  "04:00 — 应锁"
check 479 "$B" "$W"        true  "07:59 — 应锁"
check 480 "$B" "$W"        false "08:00 起床 — 不应锁"
check 720 "$B" "$W"        false "12:00 — 不应锁"
check 1380 "$B" "$W"       false "23:00 — 不应锁"

echo ""
echo "=== Active weekday for overnight windows ==="
# current_weekday: 5=Fri, 6=Sat. 00:45 Saturday belongs to Friday night's lock window.
B=1380
W=420
check_active 45 "$B" "$W" 6 "5" true  "周六 00:45，周五启用 — 应继续锁"
check_active 45 "$B" "$W" 6 "6" false "周六 00:45，仅周六启用 — 不应锁"
check_active 1410 "$B" "$W" 5 "5" true "周五 23:30，周五启用 — 应锁"
check_active 1260 "$B" "$W" 5 "5" false "周五 21:00，周五启用但未到锁屏窗 — 不应锁"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
