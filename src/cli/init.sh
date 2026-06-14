#!/usr/bin/env bash
# Cat Bedtime onboarding — zzz init

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/lib/i18n.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/stats.sh"

run_init() {
  clear 2>/dev/null || true

  ui_moon

  ui_box "$(printf '%b\n' \
    "${BOLD}$(msg welcome.title)${RESET}" \
    "" \
    "$(msg init.welcome.line1)" \
    "$(msg init.welcome.line2)" \
    "" \
    "$(msg init.welcome.line3)" \
    "$(msg init.welcome.line4)")"

  sleep 1

  local bedtime
  ui_dim "$(msg config.bedtime.hint)"
  ui_input_time "$(msg init.bedtime.prompt)" bedtime "23:00"

  local wakeup
  ui_input_time "$(msg init.wakeup.prompt)" wakeup "07:00"

  if ! lock_duration_allowed_for_times "$bedtime" "$wakeup"; then
    ui_blank
    ui_error "$(msg config.error.lock_duration)"
    ui_dim "$(msg init.retry)"
    ui_blank
    return 1
  fi

  local days_csv
  ui_multiselect "$(msg init.days.prompt)" days_csv \
    "$(msg day.full.1):1:selected" \
    "$(msg day.full.2):2:selected" \
    "$(msg day.full.3):3:selected" \
    "$(msg day.full.4):4:selected" \
    "$(msg day.full.5):5:selected" \
    "$(msg day.full.6):6" \
    "$(msg day.full.7):7"
  ui_dim "$(msg init.days.hint)"

  local winddown=5

  ui_blank

  local days_display=""
  local day_names=("" "$(msg day.full.1)" "$(msg day.full.2)" "$(msg day.full.3)" "$(msg day.full.4)" "$(msg day.full.5)" "$(msg day.full.6)" "$(msg day.full.7)")
  IFS=',' read -ra day_arr <<< "$days_csv"
  for d in "${day_arr[@]}"; do
    [ -n "$days_display" ] && days_display+="$(msg days.list_sep)"
    days_display+="${day_names[$d]}"
  done

  local pledge_phrase
  pledge_phrase="$(msg pledge.required_phrase)"

  ui_box "$(printf '%b\n' \
    "${BOLD}${C_PURPLE}$(msg init.contract.title)${RESET}" \
    "" \
    "$(msg init.contract.sleep "$bedtime" "$wakeup")" \
    "$(msg init.contract.days "$days_display")" \
    "$(msg init.contract.remind "5" "1")" \
    "" \
    "  ${C_RED}${pledge_phrase}${RESET}")"

  ui_blank

  if ! ui_type_confirm "$(msg init.pledge_prompt)" "$pledge_phrase"; then
    ui_blank
    ui_error "$(msg init.cancelled)"
    ui_dim "$(msg init.retry)"
    ui_blank
    return 1
  fi

  ui_blank
  ui_success "$(msg agreement.confirmed)"

  config_ensure_dir

  local days_json="["
  local first=true
  IFS=',' read -ra day_arr <<< "$days_csv"
  for d in "${day_arr[@]}"; do
    $first || days_json+=","
    days_json+="\"$d\""
    first=false
  done
  days_json+="]"

  cat > "$ZZZ_CONFIG" << ENDJSON
{
  "bedtime": "$bedtime",
  "wakeup": "$wakeup",
  "days": $days_json,
  "winddown_minutes": $winddown,
  "activated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "1.0.0"
}
ENDJSON

  stats_ensure

  source "$ROOT_DIR/lib/schedule.sh"
  schedule_install
  ui_success "$(msg init.schedule_ok)"

  ui_blank
  ui_box "$(printf '%b\n' \
    "${C_GREEN}${BOLD}$(msg init.done.title)${RESET}" \
    "" \
    "$(msg init.done.line1)" \
    "$(msg init.done.line2 "$bedtime")" \
    "$(msg init.done.line3 "5" "1")" \
    "" \
    "${DIM}$(msg init.done.hint)${RESET}")"
  ui_blank
}

run_init
