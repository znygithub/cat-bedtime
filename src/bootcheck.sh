#!/usr/bin/env bash
# Cat Bedtime boot check — runs at login, locks screen if within bedtime~wakeup window

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/lib/config.sh"

LOG_TAG="[zzz-bootcheck]"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_TAG $*" >> "$ZZZ_DIR/daemon.log"; }

if ! config_exists; then
  log "No config found, exiting."
  exit 0
fi

BEDTIME=$(config_get "bedtime")
WAKEUP=$(config_get "wakeup")

if [ -z "$BEDTIME" ] || [ -z "$WAKEUP" ]; then
  log "Incomplete config, exiting."
  exit 0
fi

now_min=$(now_minutes)
bed_min=$(time_to_minutes "$BEDTIME")
wake_min=$(time_to_minutes "$WAKEUP")

in_lockdown=false

if (( bed_min > wake_min )); then
  # Normal case: bedtime 23:00, wakeup 07:00
  # Lockdown window: 23:00~23:59 and 00:00~07:00
  if (( now_min >= bed_min || now_min < wake_min )); then
    in_lockdown=true
  fi
else
  # Edge case: bedtime 01:00, wakeup 08:00
  if (( now_min >= bed_min && now_min < wake_min )); then
    in_lockdown=true
  fi
fi

if [ "$in_lockdown" = true ]; then
  lock_date=$(date +%Y-%m-%d)
  lock_weekday=$(date +%u)
  if (( bed_min > wake_min && now_min < wake_min )); then
    lock_date=$(date -v-1d +%Y-%m-%d)
    lock_weekday=$(date -v-1d +%u)
  fi

  if ! config_get_array "days" | grep -q "^${lock_weekday}$"; then
    log "Lock window belongs to inactive weekday ($lock_weekday), exiting."
    exit 0
  fi

  SKIP_FILE="$ZZZ_DIR/skip_tonight"
  if [ -f "$SKIP_FILE" ]; then
    skip_date=$(head -n 1 "$SKIP_FILE" 2>/dev/null || true)
    if [ "$skip_date" = "$lock_date" ]; then
      log "Tonight is skipped, exiting."
      exit 0
    fi
  fi

  log "Currently in lockdown window ($BEDTIME ~ $WAKEUP). Launching overlay."

  OVERLAY_BIN="$HOME/.timetosleep/bin/zzz-overlay"
  [ ! -x "$OVERLAY_BIN" ] && OVERLAY_BIN="$ROOT_DIR/bin/zzz-overlay"

  if [ -x "$OVERLAY_BIN" ]; then
    source "$SCRIPT_DIR/media.sh"
    media_pause_all
    media_mute

    # Keep overlay alive until wake time
    while true; do
      "$OVERLAY_BIN" &
      OVERLAY_PID=$!
      log "Overlay PID: $OVERLAY_PID"
      wait $OVERLAY_PID 2>/dev/null

      cur=$(now_minutes)
      if (( bed_min > wake_min )); then
        if (( cur >= wake_min && cur < bed_min )); then
          log "Wake time reached, exiting."
          break
        fi
      else
        if (( cur >= wake_min || cur < bed_min )); then
          log "Wake time reached, exiting."
          break
        fi
      fi

      log "Overlay exited, relaunching in 2s..."
      sleep 2
    done

    source "$SCRIPT_DIR/brightness.sh"
    brightness_restore
    media_restore_volume
  else
    log "WARNING: Overlay binary not found."
  fi
else
  log "Not in lockdown window (now=$now_min, bed=$bed_min, wake=$wake_min). Exiting."
fi
