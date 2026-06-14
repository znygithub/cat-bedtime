#!/usr/bin/env bash
# Regression: opening the App after bedtime asks first, instead of letting
# launchd RunAtLoad lock immediately. A 15-minute delay must re-enter the
# normal daemon T-5/T-1 flow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SWIFT="$ROOT/src/app/CatBedtimeApp.swift"
DAEMON="$ROOT/src/cli/daemon.sh"

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

check_absent() {
  local file="$1" pattern="$2" label="$3"
  if grep -Fq -- "$pattern" "$file"; then
    echo "  FAIL: $label (unexpected: $pattern)" >&2
    fail=$((fail + 1))
  else
    echo "  OK: $label"
    pass=$((pass + 1))
  fi
}

echo "=== immediate lock choice ==="
check_grep "$APP_SWIFT" 'private enum LockChoicePopup' 'overdue choice uses dedicated popup'
check_grep "$APP_SWIFT" 'struct LockChoicePanelView' 'overdue popup uses app toast styling'
check_grep "$APP_SWIFT" 'NSPanel(' 'overdue choice is a compact floating panel'
check_absent "$APP_SWIFT" 'lock_choice.preview_note' 'preview-only helper copy is removed'
check_grep "$APP_SWIFT" '--preview-lock-choice' 'preview command shows lock choice popup'
check_grep "$APP_SWIFT" 'if shouldAskLockDecisionNow' 'app launch does not restore schedule before asking'
check_grep "$APP_SWIFT" 'mgr.activateOnboarding(installSchedule: !needsLockChoice)' 'onboarding avoids immediate launchd lock'
check_grep "$APP_SWIFT" 'postponeTonightFromNow(' '15-minute option uses from-now delay helper'
check_grep "$APP_SWIFT" 'ProductDefaults.immediateDelayMinutes' '15-minute delay uses product default'
check_grep "$APP_SWIFT" 'skipTonightFromLockChoice' 'tomorrow option skips tonight'
check_grep "$APP_SWIFT" 'lock_choice.tomorrow' 'tomorrow option is wired'
check_grep "$APP_SWIFT" 'writeForceTonight(reason:' 'choice writes forced tonight marker'
check_grep "$DAEMON" 'is_forced_tonight' 'daemon honors forced lock choice'

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
