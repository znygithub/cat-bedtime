#!/usr/bin/env bash
# Cat Bedtime onboarding — zzz init

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/stats.sh"

run_init() {
  clear 2>/dev/null || true

  ui_moon

  ui_box "$(printf '%b\n' \
    "${BOLD}你打算领养这只小猫吗？${RESET}" \
    "" \
    "每天到了约定时间，" \
    "它都会住进你的电脑" \
    "" \
    "为了保证它的睡眠，" \
    "你就不能使用电脑了哦")"

  sleep 1

  # ── bedtime ──
  local bedtime
  ui_dim "千万不要太晚哦，猫猫也需要一个好睡眠"
  ui_input_time "猫猫几点才能睡觉？" bedtime "23:00"

  # ── wakeup ──
  local wakeup
  ui_input_time "猫猫早上几点走？" wakeup "07:00"

  # ── active days ──
  local days_csv
  ui_multiselect "猫猫每周几可以来睡觉？" days_csv \
    "周一:1:selected" \
    "周二:2:selected" \
    "周三:3:selected" \
    "周四:4:selected" \
    "周五:5:selected" \
    "周六:6" \
    "周日:7"
  ui_dim "其他日子猫猫自己在外面浪"

  # ── wind-down ──
  # Two fixed reminders before bedtime: T-15min ("猫猫开始打哈欠了") and
  # T-1min ("它要去拉灯绳了"). The 15-minute lead also drives when launchd
  # wakes the daemon — keep this in sync with daemon.sh's wind_down().
  local winddown=15

  # ── show contract ──
  ui_blank

  local days_display=""
  local day_names=("" "周一" "周二" "周三" "周四" "周五" "周六" "周日")
  IFS=',' read -ra day_arr <<< "$days_csv"
  for d in "${day_arr[@]}"; do
    [ -n "$days_display" ] && days_display+="、"
    days_display+="${day_names[$d]}"
  done

  ui_box "$(printf '%b\n' \
    "${BOLD}${C_PURPLE}领养协议${RESET}" \
    "" \
    "  猫猫睡觉：${BOLD}$bedtime${RESET}    猫猫离开：${BOLD}$wakeup${RESET}" \
    "  来睡日子：${BOLD}$days_display${RESET}" \
    "  睡前 ${BOLD}15${RESET} 分钟和 ${BOLD}1${RESET} 分钟会提醒你" \
    "" \
    "  ${C_RED}我愿意遵守承诺让猫猫好好休息${RESET}")"

  ui_blank

  # ── activation phrase (type-to-confirm) ──
  if ! ui_type_confirm "最后一步：请键入下面这句完成领养协议：" "我愿意遵守承诺让猫猫好好休息"; then
    ui_blank
    ui_error "未正确输入，设置已取消"
    ui_dim "想好了再来：zzz init"
    ui_blank
    return 1
  fi

  ui_blank
  ui_success "已确认！"

  # ── save config ──
  config_ensure_dir

  # convert days_csv to JSON array
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

  # init stats
  stats_ensure

  # ── setup schedule ──
  source "$ROOT_DIR/lib/schedule.sh"
  schedule_install
  ui_success "定时任务已激活"

  ui_blank
  ui_box "$(printf '%b\n' \
    "${C_GREEN}${BOLD}领养完成！${RESET}" \
    "" \
    "猫猫已经记住你家地址了" \
    "今晚 ${BOLD}$bedtime${RESET}，它会住进你的电脑睡觉" \
    "睡前 ${BOLD}15${RESET} 分钟和 ${BOLD}1${RESET} 分钟会提醒你" \
    "" \
    "${DIM}输入 zzz 查看今晚状态${RESET}")"
  ui_blank
}

run_init
