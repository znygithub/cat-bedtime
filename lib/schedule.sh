#!/usr/bin/env bash
# Cat Bedtime launchd schedule manager

SCRIPT_DIR_SCHED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_SCHED/config.sh"

AGENT_LABEL="com.timetosleep.daemon"
BOOTCHECK_LABEL="com.timetosleep.bootcheck"
PLIST_PATH="$HOME/Library/LaunchAgents/${AGENT_LABEL}.plist"
BOOTCHECK_PLIST="$HOME/Library/LaunchAgents/${BOOTCHECK_LABEL}.plist"

# launchctl load/unload are unreliable on recent macOS; use bootstrap / bootout (user GUI domain)
_launchd_gui() {
  echo "gui/$(id -u)"
}

_script_path() {
  local name="$1"
  local installed="$HOME/.timetosleep/src/${name}"
  local dev="$(cd "$SCRIPT_DIR_SCHED/../src" && pwd)/${name}"
  if [ -f "$installed" ]; then
    echo "$installed"
  else
    echo "$dev"
  fi
}

# Calculate wind-down start time from config
_winddown_start() {
  local bedtime
  bedtime=$(config_get "bedtime")
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

schedule_install() {
  local daemon_path bootcheck_path
  daemon_path=$(_script_path "daemon.sh")
  bootcheck_path=$(_script_path "bootcheck.sh")
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

  # ── Boot check: runs at login, re-locks if in lockdown window ──
  cat > "$BOOTCHECK_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${BOOTCHECK_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${bootcheck_path}</string>
  </array>

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

  # (Re)load both agents
  local gui
  gui=$(_launchd_gui)
  launchctl bootout "$gui/$AGENT_LABEL" 2>/dev/null
  launchctl bootout "$gui/$BOOTCHECK_LABEL" 2>/dev/null
  launchctl bootstrap "$gui" "$PLIST_PATH"
  launchctl bootstrap "$gui" "$BOOTCHECK_PLIST"
}

schedule_uninstall() {
  local gui
  gui=$(_launchd_gui)
  launchctl bootout "$gui/$AGENT_LABEL" 2>/dev/null
  launchctl bootout "$gui/$BOOTCHECK_LABEL" 2>/dev/null
  for p in "$PLIST_PATH" "$BOOTCHECK_PLIST"; do
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
