#!/usr/bin/env bash
# Cat Bedtime media controller — pause/resume, volume control

media_pause_all() {
  # Spotify
  osascript -e 'tell application "System Events" to if exists (process "Spotify") then tell application "Spotify" to pause' 2>/dev/null

  # Apple Music
  osascript -e 'tell application "System Events" to if exists (process "Music") then tell application "Music" to pause' 2>/dev/null

  # Generic: pause any media via media key
  osascript -e '
    tell application "System Events"
      -- Send media pause key
      key code 16 using {command down, option down}
    end tell
  ' 2>/dev/null

  # Pause Chrome/Safari/Arc video (send space to pause if focused)
  for browser in "Google Chrome" "Safari" "Arc"; do
    osascript -e "
      tell application \"System Events\"
        if exists (process \"$browser\") then
          tell application \"$browser\" to set miniaturized of every window to true
        end if
      end tell
    " 2>/dev/null
  done
}

# Gradually reduce system volume
# Usage: media_fade_volume 50   (fade to 50%)
media_fade_volume() {
  local target="${1:-0}"
  local current
  current=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
  [ -z "$current" ] && return

  if (( current > target )); then
    local step=$(( (current - target) / 5 ))
    (( step < 1 )) && step=1
    local vol=$current
    while (( vol > target )); do
      (( vol -= step ))
      (( vol < target )) && vol=$target
      osascript -e "set volume output volume $vol" 2>/dev/null
      sleep 1
    done
  fi
}

# Save current volume for restore later
media_save_volume() {
  local vol
  vol=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
  echo "$vol" > "$HOME/.timetosleep/saved_volume"
}

# Restore volume from saved value
media_restore_volume() {
  local saved="$HOME/.timetosleep/saved_volume"
  if [ -f "$saved" ]; then
    local vol
    vol=$(cat "$saved")
    if [ -n "$vol" ] && (( vol > 0 )); then
      osascript -e "set volume output volume $vol" 2>/dev/null
    fi
    rm -f "$saved"
  fi
}

# Mute
media_mute() {
  osascript -e "set volume output volume 0" 2>/dev/null
}
