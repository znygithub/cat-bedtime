#!/usr/bin/env bash
# Cat Bedtime launchd schedule manager

SCRIPT_DIR_SCHED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_SCHED/config.sh"

AGENT_LABEL="com.timetosleep.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/${AGENT_LABEL}.plist"
LEGACY_BOOTCHECK_LABEL="com.timetosleep.bootcheck"
LEGACY_BOOTCHECK_PLIST="$HOME/Library/LaunchAgents/${LEGACY_BOOTCHECK_LABEL}.plist"

# launchctl load/unload are unreliable on recent macOS; use bootstrap / bootout (user GUI domain)
_launchd_gui() {
  echo "gui/$(id -u)"
}

_script_path() {
  local name="$1"
  local installed="$HOME/.timetosleep/src/cli/${name}"
  local dev="$(cd "$SCRIPT_DIR_SCHED/../src/cli" && pwd)/${name}"
  if [ -f "$installed" ]; then
    echo "$installed"
  else
    echo "$dev"
  fi
}

# Calculate wind-down start time from config
_winddown_start() {
  local bedtime
  bedtime=$(effective_bedtime)
  local winddown
  winddown=$(config_get "winddown_minutes")
  if ! [[ "${winddown:-}" =~ ^[0-9]+$ ]] || (( winddown < 1 )); then
    winddown=30
  fi
  local bed_min
  bed_min=$(time_to_minutes "$bedtime")
  local start_min=$(( bed_min - winddown ))
  # handle wrap-around midnight
  (( start_min < 0 )) && (( start_min += 1440 ))
  minutes_to_time $start_min
}

_time_in_range() {
  local now_min="$1" start_min="$2" end_min="$3"
  if (( start_min < end_min )); then
    (( now_min >= start_min && now_min < end_min ))
  elif (( start_min > end_min )); then
    (( now_min >= start_min || now_min < end_min ))
  else
    return 1
  fi
}

_previous_weekday() {
  local weekday="$1"
  if (( weekday == 1 )); then
    echo 7
  else
    echo $(( weekday - 1 ))
  fi
}

_next_weekday() {
  local weekday="$1"
  if (( weekday == 7 )); then
    echo 1
  else
    echo $(( weekday + 1 ))
  fi
}

_catchup_weekday() {
  local now_min="$1" bed_min="$2" wake_min="$3" start_min="$4" current_weekday="$5"

  if _time_in_range "$now_min" "$start_min" "$bed_min"; then
    if (( start_min > bed_min && now_min >= start_min )); then
      _next_weekday "$current_weekday"
    else
      echo "$current_weekday"
    fi
    return 0
  fi

  if _time_in_range "$now_min" "$bed_min" "$wake_min"; then
    if (( bed_min > wake_min && now_min < wake_min )); then
      _previous_weekday "$current_weekday"
    else
      echo "$current_weekday"
    fi
    return 0
  fi

  return 1
}

_should_kickstart_now() {
  local bedtime wakeup winddown
  bedtime=$(effective_bedtime)
  wakeup=$(config_get "wakeup")
  winddown=$(config_get "winddown_minutes")
  if ! [[ "${winddown:-}" =~ ^[0-9]+$ ]] || (( winddown < 1 )); then
    winddown=30
  fi

  local now_min bed_min wake_min start_min weekday
  now_min=$(now_minutes)
  bed_min=$(time_to_minutes "$bedtime")
  wake_min=$(time_to_minutes "$wakeup")
  start_min=$(( bed_min - winddown ))
  (( start_min < 0 )) && (( start_min += 1440 ))

  weekday=$(_catchup_weekday "$now_min" "$bed_min" "$wake_min" "$start_min" "$(today_weekday)") || return 1
  config_get_array "days" | grep -q "^${weekday}$"
}

schedule_install() {
  local daemon_path
  daemon_path=$(_script_path "daemon.sh")
  local start_time
  start_time=$(_winddown_start)
  local hour="${start_time%%:*}"
  local minute="${start_time##*:}"

  hour=$((10#$hour))
  minute=$((10#$minute))

  mkdir -p "$(dirname "$PLIST_PATH")"

  # ── Nightly daemon: triggers at winddown time ──
  cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${AGENT_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${daemon_path}</string>
  </array>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>${hour}</integer>
    <key>Minute</key>
    <integer>${minute}</integer>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>${ZZZ_DIR}/daemon.log</string>
  <key>StandardErrorPath</key>
  <string>${ZZZ_DIR}/daemon.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
PLIST

  # (Re)load the nightly agent and remove the old login-time lock checker.
  local gui
  gui=$(_launchd_gui)
  launchctl bootout "$gui/$AGENT_LABEL" 2>/dev/null || true
  launchctl bootout "$gui/$LEGACY_BOOTCHECK_LABEL" 2>/dev/null || true
  rm -f "$LEGACY_BOOTCHECK_PLIST"
  launchctl bootstrap "$gui" "$PLIST_PATH"
}

schedule_uninstall() {
  local gui
  gui=$(_launchd_gui)
  launchctl bootout "$gui/$AGENT_LABEL" 2>/dev/null || true
  launchctl bootout "$gui/$LEGACY_BOOTCHECK_LABEL" 2>/dev/null || true
  for p in "$PLIST_PATH" "$LEGACY_BOOTCHECK_PLIST"; do
    [ -f "$p" ] && rm -f "$p"
  done
}

schedule_is_installed() {
  [ -f "$PLIST_PATH" ] && launchctl list "$AGENT_LABEL" &>/dev/null
}

# Reinstall schedule (e.g. after config change)
schedule_update() {
  schedule_install
}
