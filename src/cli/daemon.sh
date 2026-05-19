#!/usr/bin/env bash
# Cat Bedtime daemon — orchestrates wind-down → lockdown → wake-up
# Triggered by launchd at (bedtime - winddown_minutes)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/i18n.sh"
source "$ROOT_DIR/lib/stats.sh"
source "$SCRIPT_DIR/media.sh"
source "$SCRIPT_DIR/brightness.sh"

LOG_TAG="[zzz-daemon]"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_TAG $*"; }

# ── Load config ──────────────────────────────────────────────────
BEDTIME=$(config_get "bedtime")
WAKEUP=$(config_get "wakeup")
WINDDOWN=$(config_get "winddown_minutes")
MESSAGE=$(config_get "message")

if [ -z "$BEDTIME" ] || [ -z "$WAKEUP" ]; then
  log "ERROR: Config not found or incomplete. Run 'zzz init' first."
  exit 1
fi

# winddown must be numeric (default 30 if missing / bad config)
if ! [[ "${WINDDOWN:-}" =~ ^[0-9]+$ ]] || (( WINDDOWN < 1 )); then
  log "WARNING: winddown_minutes invalid or empty (${WINDDOWN:-}), using 30"
  WINDDOWN=30
fi

# ── Check for skip ───────────────────────────────────────────────
SKIP_FILE="$ZZZ_DIR/skip_tonight"
if [ -f "$SKIP_FILE" ]; then
  skip_date=$(head -n 1 "$SKIP_FILE" 2>/dev/null || true)
  skip_reason=$(sed -n '2p' "$SKIP_FILE" 2>/dev/null || true)
  today=$(date +%Y-%m-%d)
  if [ "$skip_date" = "$today" ]; then
    log "Tonight is skipped by user request."
    if [ -n "$skip_reason" ]; then
      stats_record "$today" "skipped:$skip_reason"
    else
      stats_record "$today" "skipped"
    fi
    rm -f "$SKIP_FILE"
    exit 0
  fi
  rm -f "$SKIP_FILE"
fi

log "Starting wind-down sequence. Bedtime: $BEDTIME, Wake: $WAKEUP, Winddown: ${WINDDOWN}min"

# ── Resolve paths ────────────────────────────────────────────────
OVERLAY_BIN="$HOME/.timetosleep/bin/zzz-overlay"
[ ! -x "$OVERLAY_BIN" ] && OVERLAY_BIN="$ROOT_DIR/bin/zzz-overlay"

# ── Helper: native notification with center-screen alert fallback ──────────
# Args: title, subtitle (may be empty), body lines, primary button label.
# Native notifications are sent through Cat Bedtime.app via LaunchServices so
# macOS attributes the banner to the real app bundle instead of osascript.
# The AppleScript alert remains only as a fallback when no app bundle exists.
find_app_notify_bundle() {
  local candidates=(
    "$HOME/.timetosleep/bin/Cat Bedtime.app"
    "$ROOT_DIR/bin/Cat Bedtime.app"
    "$ROOT_DIR/../.."
  )
  local p
  for p in "${candidates[@]}"; do
    if [ -d "$p" ] && [ -x "$p/Contents/MacOS/zzz-app" ]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

notify_native() {
  local title="$1" subtitle="$2" body="$3" app output status
  app=$(find_app_notify_bundle) || return 127

  output=$(/usr/bin/open -g -j -n "$app" --args --notify "$title" "$subtitle" "$body" 2>&1)
  status=$?
  if (( status != 0 )); then
    log "native notify failed ($status): ${output:-no output}"
    return "$status"
  fi
  log "native notify sent: ${title//$'\n'/ } — ${subtitle:-∅}"
  return 0
}

notify() {
  local title="$1" subtitle="$2" body="$3" button="$4" output status
  notify_native "$title" "$subtitle" "$body"
  status=$?
  if (( status == 0 )); then
    return 0
  fi

  if (( status != 127 )); then
    log "native notify was available but failed; skipping osascript alert fallback"
    return "$status"
  fi

  # NOTE: keep argv passing here. It avoids quoting bugs with CJK text.
  # NOTE: do not pass `--` between `-` and the script's args. macOS osascript
  # treats `--` as a regular argv entry (not an end-of-options separator), so
  # it would land as `item 1 of argv` and shift every following slot by one —
  # the title becomes "--", the button label gets the body text, etc. (Symptom:
  # a centered alert sheet whose blue button reads "收尾这一小段就好" instead
  # of "知道啦".)
  output=$(
    osascript -l AppleScript - "$title" "$subtitle" "$body" "$button" <<'APPLESCRIPT' 2>&1
on run argv
  set dlgTitle to item 1 of argv
  set dlgSub to item 2 of argv
  set dlgBody to item 3 of argv
  set dlgBtn to item 4 of argv
  if dlgSub is "" then
    set alertBody to dlgBody
  else
    set alertBody to dlgSub & linefeed & linefeed & dlgBody
  end if
  display alert dlgTitle message alertBody as informational buttons {dlgBtn} default button dlgBtn giving up after 12
end run
APPLESCRIPT
  )
  status=$?
  if (( status != 0 )); then
    log "notify osascript failed ($status): $output"
  else
    log "notify sent: ${title//$'\n'/ } — ${subtitle:-∅}"
  fi
}

# ── Helper: minutes until a given time (handles midnight wrap) ───
minutes_until() {
  local target_min
  target_min=$(time_to_minutes "$1")
  local now_min
  now_min=$(now_minutes)
  local diff=$(( target_min - now_min ))
  (( diff < 0 )) && (( diff += 1440 ))
  echo $diff
}

# ── Helper: which weekday this wind-down run belongs to ──────────
# If bedtime is just after midnight, wind-down can start on the previous
# calendar day. Active-day checks should use the bedtime date, not the
# notification date.
active_weekday_for_winddown() {
  local now_min bed_min start_min
  now_min=$(now_minutes)
  bed_min=$(time_to_minutes "$BEDTIME")
  start_min=$(( bed_min - WINDDOWN ))
  (( start_min < 0 )) && (( start_min += 1440 ))

  if (( start_min > bed_min && now_min >= start_min )); then
    date -v+1d +%u
  else
    date +%u
  fi
}

is_active_winddown_day() {
  local active_weekday
  active_weekday=$(active_weekday_for_winddown)
  config_get_array "days" | grep -q "^${active_weekday}$"
}

# ── Helper: check if Mac slept through the night ────────────────
# Returns 0 (true) if current time is in daytime (wakeup ~ winddown start),
# meaning the bedtime window has passed and we should not lock.
_overslept() {
  local now_min wake_min start_min bed_min
  now_min=$(now_minutes)
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

# ── Helper: sleep until a given HH:MM (wall-clock aware) ────────
# Polls in short intervals so Mac sleep/wake can't break timing.
# When the Mac wakes from sleep, re-checks wall clock immediately.
sleep_until() {
  local target="$1"
  while true; do
    local mins
    mins=$(minutes_until "$target")
    if (( mins == 0 || mins > 720 )); then
      break
    fi
    if (( mins <= 1 )); then
      sleep 5
    else
      sleep 30
    fi
  done
}

# ── PHASE 1: Wind-down (wall-clock aware) ────────────────────────
# Computes wall-clock targets for each stage instead of using sleep(N),
# so Mac sleep/wake cannot break the timing.
wind_down() {
  local total_min=$WINDDOWN
  log "Wind-down phase starting ($total_min minutes until lockdown)"

  # First reminder: wind-down start (= "提前 N 分钟"，常见为 30 分钟)
  notify \
    "$(msg notify.winddown.title)" \
    "$(msg notify.winddown.subtitle "$total_min")" \
    "$(msg notify.winddown.body)" \
    "$(msg notify.winddown.button)"

  if ! is_active_winddown_day; then
    log "Reminder sent; wind-down belongs to inactive weekday ($(active_weekday_for_winddown)), skipping lockdown."
    return 2
  fi

  # Save current state for later restore
  brightness_save
  media_save_volume

  local bed_min
  bed_min=$(time_to_minutes "$BEDTIME")

  # Wall-clock targets for each stage
  local stage2_at=$(( bed_min - total_min * 2 / 3 ))
  (( stage2_at < 0 )) && (( stage2_at += 1440 ))
  local stage3_at=$(( bed_min - total_min / 3 ))
  (( stage3_at < 0 )) && (( stage3_at += 1440 ))
  local warn_at=$(( bed_min - 1 ))
  (( warn_at < 0 )) && (( warn_at += 1440 ))

  # Stage 1 → wait until stage 2 wall-clock time
  sleep_until "$(minutes_to_time $stage2_at)"
  if _overslept; then
    log "Mac woke after bedtime window; aborting wind-down."
    brightness_restore; media_restore_volume; return 1
  fi

  # Stage 2 and stage 3 used to send popups too, but per product feedback
  # users only get two notifications: T-15min (above) and T-1min (below).
  # Brightness and volume still taper here so the room "matches" the cat's
  # mood — just without interrupting with another modal sheet.
  local remaining
  remaining=$(minutes_until "$BEDTIME")
  log "Wind-down stage 2 (silent): $remaining minutes remaining"
  brightness_fade_to 0.6 10 &

  # Stage 2 → wait until stage 3 wall-clock time
  sleep_until "$(minutes_to_time $stage3_at)"
  if _overslept; then
    log "Mac woke after bedtime window; aborting wind-down."
    brightness_restore; media_restore_volume; return 1
  fi

  remaining=$(minutes_until "$BEDTIME")
  log "Wind-down stage 3 (silent): $remaining minutes remaining"
  media_fade_volume 50 &
  brightness_fade_to 0.3 10 &

  # 1-minute warning before bedtime
  local m
  m=$(minutes_until "$BEDTIME")
  if (( m > 1 && m < 720 )); then
    sleep_until "$(minutes_to_time $warn_at)"
    if _overslept; then
      log "Mac woke after bedtime window; aborting wind-down."
      brightness_restore; media_restore_volume; return 1
    fi
    notify \
      "$(msg notify.locksoon.title)" \
      "$(msg notify.locksoon.subtitle)" \
      "$(msg notify.locksoon.body)" \
      "$(msg notify.locksoon.button)"
  fi

  # Final wait until exact bedtime
  sleep_until "$BEDTIME"
  if _overslept; then
    log "Mac woke after bedtime window; aborting wind-down."
    brightness_restore; media_restore_volume; return 1
  fi
  return 0
}

# ── PHASE 2: Lockdown ───────────────────────────────────────────
lockdown() {
  log "LOCKDOWN activated"
  local today
  today=$(date +%Y-%m-%d)

  # Pause all media
  media_pause_all
  media_mute

  # Set brightness to minimum
  brightness_set 0.05

  # Enable Do Not Disturb (macOS Monterey+)
  shortcuts run "Turn On Focus" 2>/dev/null || true

  # Launch the fullscreen overlay
  if [ -x "$OVERLAY_BIN" ]; then
    log "Launching overlay: $OVERLAY_BIN"

    # Keep overlay alive — if killed, relaunch
    while true; do
      "$OVERLAY_BIN" &
      OVERLAY_PID=$!
      log "Overlay PID: $OVERLAY_PID"
      wait $OVERLAY_PID 2>/dev/null
      overlay_status=$?
      log "Overlay exited with status $overlay_status"

      # Check if it's wake time
      local remaining
      remaining=$(minutes_until "$WAKEUP")
      if (( remaining <= 1 || remaining > 720 )); then
        log "Wake time reached, stopping overlay"
        break
      fi

      log "Overlay exited unexpectedly, relaunching in 2s..."
      sleep 2
    done
  else
    log "WARNING: Overlay binary not found at $OVERLAY_BIN"
    log "Falling back to terminal lockdown"
    # Fallback: just wait
    sleep_until "$WAKEUP"
  fi

  # Record completion
  stats_record "$today" "completed"
}

# ── PHASE 3: Wake up ────────────────────────────────────────────
wake_up() {
  log "Good morning! Restoring system."

  # Restore brightness
  brightness_restore

  # Restore volume
  media_restore_volume

  # Disable Do Not Disturb
  shortcuts run "Turn Off Focus" 2>/dev/null || true

  # No wake-up popup: at this point the overlay has already exited, the user
  # is either still asleep or just opened the lid — neither moment benefits
  # from a modal sheet. Brightness/volume are silently restored above.

  log "Daemon complete."
}

# ── Main sequence ────────────────────────────────────────────────
wind_down
wind_down_status=$?
case "$wind_down_status" in
  0)
    lockdown
    wake_up
    ;;
  2)
    log "Wind-down skipped after reminder because this sleep day is inactive."
    ;;
  *)
    log "Wind-down aborted (Mac slept through bedtime window). Skipping lockdown."
    ;;
esac
