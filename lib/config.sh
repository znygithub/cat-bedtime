#!/usr/bin/env bash
# Cat Bedtime config manager — read/write ~/.timetosleep/config.json

ZZZ_DIR="$HOME/.timetosleep"
ZZZ_CONFIG="$ZZZ_DIR/config.json"
ZZZ_STATS="$ZZZ_DIR/stats.json"
MAX_LOCK_MINUTES=900

config_ensure_dir() {
  mkdir -p "$ZZZ_DIR"
}

# ── tiny JSON helpers (no jq dependency) ─────────────────────────

_has_jq() { command -v jq &>/dev/null; }

# Read a top-level string value from config
config_get() {
  local key="$1"
  if [ ! -f "$ZZZ_CONFIG" ]; then
    echo ""
    return 1
  fi
  if _has_jq; then
    jq -r ".$key // empty" "$ZZZ_CONFIG" 2>/dev/null
  else
    # fallback: flat string values, or bare numbers (e.g. winddown_minutes)
    local val
    val=$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$ZZZ_CONFIG" 2>/dev/null \
      | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    if [ -n "$val" ]; then
      echo "$val"
    else
      grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9][0-9]*" "$ZZZ_CONFIG" 2>/dev/null \
        | head -1 | sed 's/.*:[[:space:]]*//'
    fi
  fi
}

# Read a top-level array as newline-separated values
config_get_array() {
  local key="$1"
  if [ ! -f "$ZZZ_CONFIG" ]; then return 1; fi
  if _has_jq; then
    jq -r ".$key[]? // empty" "$ZZZ_CONFIG" 2>/dev/null
  else
    grep -o "\"$key\"[[:space:]]*:[[:space:]]*\[[^]]*\]" "$ZZZ_CONFIG" \
      | grep -o '"[^"]*"' | tail -n+1 | tr -d '"'
  fi
}

# Write the entire config as JSON (receives associative-style args)
config_write() {
  config_ensure_dir
  cat > "$ZZZ_CONFIG"
}

# Update a single key (string value)
config_set() {
  local key="$1" value="$2"
  if [ ! -f "$ZZZ_CONFIG" ]; then
    echo "{}" > "$ZZZ_CONFIG"
  fi
  if _has_jq; then
    local tmp
    tmp=$(jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$ZZZ_CONFIG")
    echo "$tmp" > "$ZZZ_CONFIG"
  else
    # fallback: python one-liner (macOS always has python3)
    python3 -c "
import json, sys
with open('$ZZZ_CONFIG') as f: d = json.load(f)
d['$key'] = '$value'
with open('$ZZZ_CONFIG', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
"
  fi
}

# Update a single key (raw JSON value — for arrays, numbers, bools)
config_set_raw() {
  local key="$1" value="$2"
  if [ ! -f "$ZZZ_CONFIG" ]; then
    echo "{}" > "$ZZZ_CONFIG"
  fi
  if _has_jq; then
    local tmp
    tmp=$(jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$ZZZ_CONFIG")
    echo "$tmp" > "$ZZZ_CONFIG"
  else
    python3 -c "
import json
with open('$ZZZ_CONFIG') as f: d = json.load(f)
d['$key'] = json.loads('$value')
with open('$ZZZ_CONFIG', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
"
  fi
}

config_exists() {
  [ -f "$ZZZ_CONFIG" ]
}

# Time helpers
time_to_minutes() {
  local t="$1"  # HH:MM
  local h="${t%%:*}" m="${t##*:}"
  echo $(( 10#$h * 60 + 10#$m ))
}

minutes_to_time() {
  printf "%02d:%02d" $(( $1 / 60 )) $(( $1 % 60 ))
}

lock_duration_minutes_for_times() {
  local bedtime="$1" wakeup="$2"
  local bed_min wake_min diff
  bed_min=$(time_to_minutes "$bedtime")
  wake_min=$(time_to_minutes "$wakeup")
  diff=$(( wake_min - bed_min ))
  (( diff <= 0 )) && (( diff += 1440 ))
  echo "$diff"
}

lock_duration_allowed_for_times() {
  local duration
  duration=$(lock_duration_minutes_for_times "$1" "$2")
  (( duration > 0 && duration < MAX_LOCK_MINUTES ))
}

now_minutes() {
  local h m
  h=$(date +%H)
  m=$(date +%M)
  echo $(( 10#$h * 60 + 10#$m ))
}

today_weekday() {
  # 1=Mon ... 7=Sun (ISO)
  date +%u
}

is_active_today() {
  local today
  today=$(today_weekday)
  local days
  days=$(config_get_array "days")
  echo "$days" | grep -q "^${today}$"
}

# Tonight's postponed bedtime (if valid for today), else empty.
postpone_tonight_bedtime() {
  local f="$ZZZ_DIR/postpone_tonight"
  [ -f "$f" ] || return 1
  local pdate pbed today
  today=$(date +%Y-%m-%d)
  pdate=$(head -n 1 "$f" 2>/dev/null || true)
  pbed=$(sed -n '2p' "$f" 2>/dev/null || true)
  if [ "$pdate" = "$today" ] && [ -n "$pbed" ]; then
    echo "$pbed"
    return 0
  fi
  if [ -n "$pdate" ] && [ "$pdate" != "$today" ]; then
    rm -f "$f"
  fi
  return 1
}

# Config bedtime, or tonight's postponed time when set.
effective_bedtime() {
  postpone_tonight_bedtime || config_get "bedtime"
}
