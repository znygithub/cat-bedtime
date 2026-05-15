#!/usr/bin/env bash
# Cat Bedtime config manager — read/write ~/.timetosleep/config.json

ZZZ_DIR="$HOME/.timetosleep"
ZZZ_CONFIG="$ZZZ_DIR/config.json"
ZZZ_STATS="$ZZZ_DIR/stats.json"

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
