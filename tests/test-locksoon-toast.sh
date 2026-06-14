#!/usr/bin/env bash
# Regression: bedtime reminders use strong App Toasts, not Notification Center.
# T-5 shows a blocking toast; T-1 shows a toast with one optional +5min defer.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="$ROOT/src/cli/daemon.sh"
APP_SWIFT="$ROOT/src/app/CatBedtimeApp.swift"

pass=0
fail=0

check_grep() {
  local file="$1" pattern="$2" label="$3"
  local extended="${4:-0}"
  if (( extended )); then
    if grep -qE -- "$pattern" "$file"; then
      echo "  OK: $label"
      pass=$((pass + 1))
    else
      echo "  FAIL: $label (missing: $pattern)" >&2
      fail=$((fail + 1))
    fi
  elif grep -Fq -- "$pattern" "$file"; then
    echo "  OK: $label"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label (missing: $pattern)" >&2
    fail=$((fail + 1))
  fi
}

echo "=== bedtime toast wiring ==="
check_grep "$DAEMON" 'toast_bedtime_alert' 'daemon defines toast_bedtime_alert'
check_grep "$DAEMON" '--toast-bedtime-warning' 'daemon invokes toast-bedtime-warning flag'
check_grep "$DAEMON" 'bed_min - 1' 'warn_at uses bedtime minus 1 minute'
check_grep "$DAEMON" 'toast_bedtime_alert "$notify_min" 0' 'wind_down shows T-5 strong toast'
check_grep "$DAEMON" 'm >= 1 && m < 720' 'T-1 boundary includes exactly one minute remaining'
check_grep "$DAEMON" 'toast_bedtime_alert 1 1' 'first T-1 toast allows one defer'
check_grep "$DAEMON" 'toast_bedtime_alert 1 0' 'post-defer T-1 toast disallows defer'
check_grep "$DAEMON" 'BEDTIME=$(effective_bedtime)' 'daemon refreshes postponed bedtime'
if grep -E '^[[:space:]]+notify[[:space:]]+\\' "$DAEMON" | grep -Eq 'notify\.(winddown|locksoon)'; then
  echo "  FAIL: daemon still calls Notification Center for bedtime reminders" >&2
  fail=$((fail + 1))
else
  echo "  OK: daemon does not call Notification Center for bedtime reminders"
  pass=$((pass + 1))
fi

check_grep "$APP_SWIFT" 'toast-locksoon' 'app handles toast-locksoon flag'
check_grep "$APP_SWIFT" 'toast-bedtime-warning' 'app handles toast-bedtime-warning flag'
check_grep "$APP_SWIFT" 'notify.bedtime.postpone_5' 'toast exposes +5min defer copy'

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
