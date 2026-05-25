#!/usr/bin/env bash
# Regression: quitting the App pauses the launchd schedule so bedtime cannot
# still lock the screen after the user has explicitly exited the App.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SWIFT="$ROOT/src/app/CatBedtimeApp.swift"
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

echo "=== app quit pauses schedule ==="
check_grep "$APP_SWIFT" 'func pauseScheduleForAppQuit()' 'ConfigManager exposes quit pause hook'
check_grep "$APP_SWIFT" 'ConfigManager.shared.pauseScheduleForAppQuit()' 'App termination pauses schedule'
check_grep "$APP_SWIFT" 'removeItem(atPath: plistPath)' 'quit removes launchd plist'
check_grep "$APP_SWIFT" 'func restoreScheduleForAppLaunch()' 'ConfigManager exposes launch restore hook'
check_grep "$APP_SWIFT" 'mgr.restoreScheduleForAppLaunch()' 'App launch restores configured schedule'
check_grep "$MESSAGES" '暂停后台定时任务' 'quit copy explains the pause'

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
