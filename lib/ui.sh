#!/usr/bin/env bash
# Cat Bedtime terminal UI toolkit

# ── Colors & Styles ──────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'
RESET='\033[0m'

# Palette — adapts to light and dark terminal backgrounds.
_ui_bg_is_light_from_ansi() {
  local bg="$1"
  [[ "$bg" =~ ^[0-9]+$ ]] || return 1

  if (( bg < 16 )); then
    case "$bg" in
      7|10|11|14|15) return 0 ;;
      *) return 1 ;;
    esac
  fi

  if (( bg >= 232 && bg <= 255 )); then
    (( bg >= 244 ))
    return
  fi

  if (( bg >= 16 && bg <= 231 )); then
    local idx=$(( bg - 16 ))
    local r=$(( idx / 36 ))
    local g=$(( (idx % 36) / 6 ))
    local b=$(( idx % 6 ))
    local -a levels=(0 95 135 175 215 255)
    local rv=${levels[$r]} gv=${levels[$g]} bv=${levels[$b]}
    local brightness=$(( (rv * 299 + gv * 587 + bv * 114) / 1000 ))
    (( brightness >= 160 ))
    return
  fi

  return 1
}

_ui_bg_is_light_from_terminal_app() {
  [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ] || return 1
  command -v osascript >/dev/null 2>&1 || return 1
  local rgb
  rgb=$(osascript 2>/dev/null <<'APPLESCRIPT'
tell application "Terminal"
  if (count of windows) is 0 then error "no terminal window"
  set c to background color of selected tab of front window
  return (item 1 of c as text) & "," & (item 2 of c as text) & "," & (item 3 of c as text)
end tell
APPLESCRIPT
  ) || return 1
  [[ "$rgb" =~ ^([0-9]+),([0-9]+),([0-9]+)$ ]] || return 1
  local r=${BASH_REMATCH[1]} g=${BASH_REMATCH[2]} b=${BASH_REMATCH[3]}
  local brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
  (( brightness >= 32768 ))
}

_ui_bg_is_light() {
  case "${CAT_BEDTIME_THEME:-}" in
    light) return 0 ;;
    dark) return 1 ;;
  esac

  if [ -n "${COLORFGBG:-}" ]; then
    _ui_bg_is_light_from_ansi "${COLORFGBG##*;}" && return 0
    return 1
  fi

  _ui_bg_is_light_from_terminal_app
}

if _ui_bg_is_light; then
  C_PURPLE='\033[38;5;90m'
  C_BLUE='\033[38;5;25m'
  C_CYAN='\033[38;5;31m'
  C_GREEN='\033[38;5;28m'
  C_YELLOW='\033[38;5;130m'
  C_ORANGE='\033[38;5;166m'
  C_RED='\033[38;5;124m'
  C_GRAY='\033[38;5;240m'
  C_WHITE='\033[38;5;232m'
  C_DARK='\033[38;5;245m'
else
  C_PURPLE='\033[38;5;141m'
  C_BLUE='\033[38;5;111m'
  C_CYAN='\033[38;5;116m'
  C_GREEN='\033[38;5;114m'
  C_YELLOW='\033[38;5;222m'
  C_ORANGE='\033[38;5;216m'
  C_RED='\033[38;5;167m'
  C_GRAY='\033[38;5;245m'
  C_WHITE='\033[38;5;255m'
  C_DARK='\033[38;5;238m'
fi

# ── Basic output ─────────────────────────────────────────────────
ui_print() { printf "%b\n" "$*"; }
ui_print_n() { printf "%b" "$*"; }

# Wrap an ANSI escape for readline prompt (so readline knows it's non-printing)
_rl() { printf '\001%b\002' "$1"; }

ui_blank() { echo; }

ui_header() {
  local text="$1"
  ui_blank
  ui_print "  ${BOLD}${C_PURPLE}$text${RESET}"
  ui_blank
}

ui_step() {
  local text="$1"
  ui_print "  ${C_CYAN}›${RESET} $text"
}

ui_success() {
  local text="$1"
  ui_print "  ${C_GREEN}✓${RESET} $text"
}

ui_warn() {
  local text="$1"
  ui_print "  ${C_YELLOW}!${RESET} $text"
}

ui_error() {
  local text="$1"
  ui_print "  ${C_RED}✗${RESET} $text"
}

ui_dim() {
  ui_print "  ${DIM}${C_GRAY}$1${RESET}"
}

# ── Box drawing ──────────────────────────────────────────────────
ui_box() {
  local -a lines=()
  local max_len=0

  while IFS= read -r line; do
    lines+=("$line")
    local stripped
    stripped=$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#stripped}
    (( len > max_len )) && max_len=$len
  done <<< "$1"

  local width=$(( max_len + 4 ))
  local bar
  bar=$(printf '─%.0s' $(seq 1 $((width - 2))))

  ui_print "  ${C_DARK}╭${bar}╮${RESET}"
  for line in "${lines[@]}"; do
    local stripped
    stripped=$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')
    local visible_len=${#stripped}
    local pad=$(( max_len - visible_len ))
    local padding
    padding=$(printf ' %.0s' $(seq 1 $pad) 2>/dev/null)
    ui_print "  ${C_DARK}│${RESET}  ${line}${padding}  ${C_DARK}│${RESET}"
  done
  ui_print "  ${C_DARK}╰${bar}╯${RESET}"
}

# ── Interactive inputs ───────────────────────────────────────────

# Ask for text input
# Usage: ui_input "prompt" variable_name [default]
ui_input() {
  local prompt="$1" var_name="$2" default="$3"

  ui_blank
  local prompt_plain="  ${C_PURPLE}?${RESET} ${BOLD}$prompt${RESET}"
  [ -n "$default" ] && prompt_plain+=" ${DIM}($default)${RESET}"
  prompt_plain+=" ${C_GRAY}›${RESET} "

  local answer
  if [ -t 0 ]; then
    local _rp="  $(_rl "$C_PURPLE")?$(_rl "$RESET") $(_rl "$BOLD")$prompt$(_rl "$RESET")"
    [ -n "$default" ] && _rp+=" $(_rl "$DIM")($default)$(_rl "$RESET")"
    _rp+=" $(_rl "$C_GRAY")›$(_rl "$RESET") "
    read -e -r -p "$_rp" answer || answer=""
  else
    ui_print_n "$prompt_plain"
    read -r answer || answer=""
  fi
  [ -z "$answer" ] && answer="$default"
  eval "$var_name='$answer'"
}

# Parse flexible time input into HH:MM
# Accepts: 23, 23:00, 2300, 23点, 23点30, 23点半, 11pm, 7:30am,
#          六点, 六点半, 十一点, 二十三点三十, etc.
_parse_time() {
  local raw="$1"
  # strip whitespace
  raw=$(echo "$raw" | tr -d ' ')

  # Convert Chinese number words to digits: 六点半 → 6点半, 二十三 → 23
  if [[ "$raw" =~ [零一二两三四五六七八九十] ]]; then
    raw=$(python3 -c "
import re, sys
s = sys.argv[1]
cn = {'零':0,'一':1,'二':2,'两':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9}
def to_num(t):
    if '十' in t:
        p = t.split('十', 1)
        tens = cn.get(p[0], 1) if p[0] else 1
        ones = cn.get(p[1], 0) if p[1] else 0
        return str(tens * 10 + ones)
    return str(cn[t]) if t in cn else t
print(re.sub(r'[零一二两三四五六七八九十]+', lambda m: to_num(m.group()), s))
" "$raw" 2>/dev/null) || true
  fi

  local h="" m=""

  # "23:00" or "7:30"
  if [[ "$raw" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
    h="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"
  # "2300"
  elif [[ "$raw" =~ ^([0-9]{2})([0-9]{2})$ ]] && (( ${raw:0:2} <= 23 )); then
    h="${raw:0:2}"; m="${raw:2:2}"
  # "23点半" or "23点30" or "23点"
  elif [[ "$raw" =~ ^([0-9]{1,2})(点|时)半$ ]]; then
    h="${BASH_REMATCH[1]}"; m="30"
  elif [[ "$raw" =~ ^([0-9]{1,2})(点|时)([0-9]{1,2})(分)?$ ]]; then
    h="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[3]}"
  elif [[ "$raw" =~ ^([0-9]{1,2})(点|时)$ ]]; then
    h="${BASH_REMATCH[1]}"; m="0"
  # bare number "23" or "7"
  elif [[ "$raw" =~ ^([0-9]{1,2})$ ]]; then
    h="${BASH_REMATCH[1]}"; m="0"
  # "11pm" / "7am" / "11:30pm"
  elif [[ "$raw" =~ ^([0-9]{1,2})(:([0-9]{2}))?[[:space:]]*(am|pm|AM|PM)$ ]]; then
    h="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[3]:-0}"
    local ampm="${BASH_REMATCH[4]}"
    if [[ "$ampm" =~ ^[pP] ]] && (( 10#$h < 12 )); then (( h = 10#$h + 12 )); fi
    if [[ "$ampm" =~ ^[aA] ]] && (( 10#$h == 12 )); then h=0; fi
  else
    echo ""; return 1
  fi

  # validate
  if (( 10#$h >= 0 && 10#$h <= 23 && 10#$m >= 0 && 10#$m <= 59 )); then
    printf "%02d:%02d" "$((10#$h))" "$((10#$m))"
    return 0
  fi
  echo ""; return 1
}

# Ask for time input (flexible format)
# Usage: ui_input_time "prompt" variable_name [default]
ui_input_time() {
  local prompt="$1" var_name="$2" default="$3"
  while true; do
    ui_input "$prompt" _time_val "$default"
    local parsed
    parsed=$(_parse_time "$_time_val") || true
    if [ -n "$parsed" ]; then
      ui_print "  ${C_GREEN}✓${RESET} ${DIM}${parsed}${RESET}"
      eval "$var_name='$parsed'"
      return 0
    fi
    ui_error "没听懂这个时间，试试这些写法：23、23:00、23点、23点半、11pm"
  done
}

# Multi-select with checkboxes
# Usage: ui_multiselect "prompt" result_var "label1:val1" "label2:val2" ...
# Pre-select by appending :selected → "label:val:selected"
ui_multiselect() {
  local prompt="$1" var_name="$2"
  shift 2
  local -a labels=() values=() selected=()

  for item in "$@"; do
    local label="${item%%:*}"
    local rest="${item#*:}"
    local val="${rest%%:*}"
    local sel="${rest#*:}"
    labels+=("$label")
    values+=("$val")
    if [ "$sel" = "selected" ]; then
      selected+=(1)
    else
      selected+=(0)
    fi
  done

  local count=${#labels[@]}
  local cursor=0

  ui_blank
  ui_print "  ${C_PURPLE}?${RESET} ${BOLD}$prompt${RESET}  ${DIM}(空格切换, 回车确认)${RESET}"

  # save cursor position
  tput sc 2>/dev/null || true

  _ms_draw() {
    tput rc 2>/dev/null || true
    for (( i=0; i<count; i++ )); do
      local check=" "
      [ "${selected[$i]}" = "1" ] && check="${C_GREEN}✓${RESET}"
      local pointer="  "
      local style=""
      if [ $i -eq $cursor ]; then
        pointer="${C_CYAN}❯${RESET} "
        style="${BOLD}"
      fi
      ui_print "  ${pointer}[${check}] ${style}${labels[$i]}${RESET}"
    done
  }

  # initial draw
  for (( i=0; i<count; i++ )); do echo; done
  tput sc 2>/dev/null || true
  tput cuu $count 2>/dev/null || true
  tput sc 2>/dev/null || true
  _ms_draw

  while true; do
    local key
    IFS= read -rsn1 key || key=""
    case "$key" in
      $'\x1b')
        read -rsn2 rest || rest=""
        case "$rest" in
          '[A') (( cursor > 0 )) && (( cursor-- )) ;;  # up
          '[B') (( cursor < count-1 )) && (( cursor++ )) ;;  # down
        esac
        ;;
      ' ')
        if [ "${selected[$cursor]}" = "1" ]; then
          selected[$cursor]=0
        else
          selected[$cursor]=1
        fi
        ;;
      '')
        break
        ;;
    esac
    _ms_draw
  done

  # collect selected values
  local result=()
  local display=()
  for (( i=0; i<count; i++ )); do
    if [ "${selected[$i]}" = "1" ]; then
      result+=("${values[$i]}")
      display+=("${labels[$i]}")
    fi
  done

  eval "$var_name='$(IFS=,; echo "${result[*]}")'"

  # show summary
  local summary
  summary=$(IFS=、; echo "${display[*]}")
  ui_print "  ${C_GREEN}✓${RESET} ${DIM}已选：${summary}${RESET}"
}

# Single select
# Usage: ui_select "prompt" result_var "label1:val1" "label2:val2" ...
ui_select() {
  local prompt="$1" var_name="$2"
  shift 2
  local -a labels=() values=()

  for item in "$@"; do
    labels+=("${item%%:*}")
    values+=("${item#*:}")
  done

  local count=${#labels[@]}
  local cursor=0

  ui_blank
  ui_print "  ${C_PURPLE}?${RESET} ${BOLD}$prompt${RESET}  ${DIM}(↑↓选择, 回车确认)${RESET}"

  for (( i=0; i<count; i++ )); do echo; done
  tput sc 2>/dev/null || true
  tput cuu $count 2>/dev/null || true
  tput sc 2>/dev/null || true

  _ss_draw() {
    tput rc 2>/dev/null || true
    for (( i=0; i<count; i++ )); do
      if [ $i -eq $cursor ]; then
        ui_print "  ${C_CYAN}❯${RESET} ${BOLD}${labels[$i]}${RESET}"
      else
        ui_print "    ${DIM}${labels[$i]}${RESET}"
      fi
    done
  }

  _ss_draw

  while true; do
    local key
    IFS= read -rsn1 key || key=""
    case "$key" in
      $'\x1b')
        read -rsn2 rest || rest=""
        case "$rest" in
          '[A') (( cursor > 0 )) && (( cursor-- )) ;;
          '[B') (( cursor < count-1 )) && (( cursor++ )) ;;
        esac
        ;;
      '') break ;;
    esac
    _ss_draw
  done

  eval "$var_name='${values[$cursor]}'"
  ui_print "  ${C_GREEN}✓${RESET} ${DIM}已选：${labels[$cursor]}${RESET}"
}

# Confirm (y/N)
ui_confirm() {
  local prompt="$1" default="${2:-n}"
  local hint="y/N"
  [ "$default" = "y" ] && hint="Y/n"

  ui_print_n "  ${C_PURPLE}?${RESET} ${BOLD}$prompt${RESET} ${DIM}($hint)${RESET} ${C_GRAY}›${RESET} "
  local answer
  read -rn1 answer || answer=""
  echo
  [ -z "$answer" ] && answer="$default"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# Type-to-confirm: user must type exact phrase (retries up to 3 times)
# Strips extra whitespace before comparing
ui_type_confirm() {
  local prompt="$1" phrase="$2"
  local max_tries=3

  for (( try=1; try<=max_tries; try++ )); do
    ui_blank
    if (( try == 1 )); then
      ui_print "  ${BOLD}$prompt${RESET}"
    else
      ui_print "  ${C_YELLOW}再试一次（第 ${try}/${max_tries} 次）${RESET}"
    fi
    ui_print "  ${DIM}请输入：${RESET}${C_YELLOW}$phrase${RESET}"
    ui_blank
    local answer
    if [ -t 0 ]; then
      local _rp="  $(_rl "$C_GRAY")›$(_rl "$RESET") "
      read -e -r -p "$_rp" answer || answer=""
    else
      ui_print_n "  ${C_GRAY}›${RESET} "
      read -r answer || answer=""
    fi
    # normalize: collapse all whitespace
    local norm_answer norm_phrase
    norm_answer=$(echo "$answer" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
    norm_phrase=$(echo "$phrase" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
    if [ "$norm_answer" = "$norm_phrase" ]; then
      return 0
    fi
    if (( try < max_tries )); then
      ui_error "输入不匹配，请完整输入上面的确认文字"
    fi
  done
  return 1
}

# ── Progress / animation ─────────────────────────────────────────
ui_countdown() {
  local seconds="$1" msg="$2"
  for (( i=seconds; i>0; i-- )); do
    printf "\r  ${C_YELLOW}%s${RESET} %d..." "$msg" "$i"
    sleep 1
  done
  printf "\r  ${C_GREEN}✓${RESET} %-40s\n" "$msg"
}

# Cat ASCII art
ui_moon() {
  ui_print "${C_YELLOW}"
  ui_print "       /\\_/\\"
  ui_print "      ( o.o )"
  ui_print "       > ^ <"
  ui_print ""
  ui_print "    ${BOLD}C a t  B e d t i m e${RESET}"
  ui_print ""
}
