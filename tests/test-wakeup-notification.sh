#!/usr/bin/env bash
# Regression: natural wake-up should use Notification Center and restore
# future schedules after temporary bedtime choices.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="$ROOT/src/cli/daemon.sh"
APP_SWIFT="$ROOT/src/app/CatBedtimeApp.swift"
STATS="$ROOT/lib/stats.sh"
MESSAGES="$ROOT/locales/messages.json"

pass=0
fail=0

check_grep() {
  local file="$1" pattern="$2" label="$3"
  if grep -Fq -- "$pattern" "$file"; then
    echo "  OK: $label"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label (missing: $pattern)" >&2
    fail=$((fail + 1))
  fi
}

echo "=== wake-up notification ==="
check_grep "$DAEMON" 'notify_wakeup_summary' 'daemon has morning notification helper'
check_grep "$DAEMON" 'notify.wakeup.subtitle' 'daemon sends visit count through localized notification'
check_grep "$DAEMON" 'restore_schedule_after_temporary_bedtime' 'daemon restores schedule after temporary bedtime'
check_grep "$DAEMON" 'rm -f "$POSTPONE_FILE" "$FORCE_FILE"' 'daemon clears temporary bedtime markers after wake'
check_grep "$DAEMON" 'hide_running_app' 'daemon hides settings app before overnight overlay'
check_grep "$APP_SWIFT" '--hide-running-app' 'app exposes hide command for daemon'
check_grep "$STATS" 'stats_completed_count()' 'stats exposes completed visit count'
check_grep "$MESSAGES" '猫猫昨晚睡得很好' 'morning notification copy exists'

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
