#!/usr/bin/env bash
# Cat Bedtime brightness controller

# Get current brightness (0.0 - 1.0)
brightness_get() {
  local val
  # Use the private CoreDisplay framework via python
  val=$(python3 -c "
import ctypes, ctypes.util
CoreDisplay = ctypes.CDLL('/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay')
CoreDisplay.CoreDisplay_Display_GetUserBrightness.restype = ctypes.c_double
CoreDisplay.CoreDisplay_Display_GetUserBrightness.argtypes = [ctypes.c_int]
print(f'{CoreDisplay.CoreDisplay_Display_GetUserBrightness(0):.3f}')
" 2>/dev/null)

  if [ -z "$val" ] || [ "$val" = "0.000" ]; then
    # fallback: try ioreg approach
    val=$(python3 -c "
import subprocess, re
out = subprocess.check_output(['ioreg', '-c', 'AppleBacklightDisplay']).decode()
m = re.search(r'\"brightness\".*?\"value\"=(\d+)', out)
if m:
    print(f'{int(m.group(1))/1048576:.3f}')
else:
    print('1.000')
" 2>/dev/null)
  fi

  echo "${val:-1.000}"
}

# Set brightness (0.0 - 1.0)
brightness_set() {
  local val="$1"
  python3 -c "
import ctypes
CoreDisplay = ctypes.CDLL('/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay')
CoreDisplay.CoreDisplay_Display_SetUserBrightness.argtypes = [ctypes.c_int, ctypes.c_double]
CoreDisplay.CoreDisplay_Display_SetUserBrightness(0, $val)
" 2>/dev/null

  # fallback: AppleScript approach
  if [ $? -ne 0 ]; then
    local pct
    pct=$(python3 -c "print(int($val * 100))")
    osascript -e "
      tell application \"System Preferences\"
        reveal anchor \"displaysDisplayTab\" of pane id \"com.apple.preference.displays\"
      end tell
    " 2>/dev/null
  fi
}

# Save current brightness for later restore
brightness_save() {
  local saved="$HOME/.timetosleep/saved_brightness"
  [ -f "$saved" ] && return
  brightness_get > "$saved"
}

# Restore saved brightness
brightness_restore() {
  local saved="$HOME/.timetosleep/saved_brightness"
  if [ -f "$saved" ]; then
    local val
    val=$(cat "$saved")
    [ -n "$val" ] && brightness_set "$val"
    rm -f "$saved"
  fi
}

# Gradually dim the screen over N seconds
# Usage: brightness_fade_to 0.3 30   (fade to 30% over 30 seconds)
brightness_fade_to() {
  local target="$1" duration="${2:-10}"
  local current
  current=$(brightness_get)
  local steps=$((duration / 2))
  (( steps < 1 )) && steps=1

  python3 -c "
import time, ctypes
CoreDisplay = ctypes.CDLL('/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay')
CoreDisplay.CoreDisplay_Display_SetUserBrightness.argtypes = [ctypes.c_int, ctypes.c_double]
current = $current
target = $target
steps = $steps
diff = target - current
for i in range(1, steps + 1):
    val = current + (diff * i / steps)
    CoreDisplay.CoreDisplay_Display_SetUserBrightness(0, val)
    time.sleep(2)
" 2>/dev/null
}
