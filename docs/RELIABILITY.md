# 历史踩坑与回归风险

已修过、以后容易被改坏的地方。不是待办清单。

## 1. macOS bash 3.2 + 中文退格

**解法：** `read -e -r -p`，ANSI 用 `\001...\002` 包裹。见 `lib/ui.sh`。

## 2. set -e 下子命令非零直接退出

**解法：** `parsed=$(_parse_time "$input") || true`

## 3. 锁屏靠字符串匹配起床时间

Mac 深度睡眠会挂起 Timer，错过 wakeup 分钟后永不退出。

**解法：** 判断「是否已进入白天窗口」，跨午夜统一逻辑。见 `LockScreen.swift`、`test-overslept-detection.sh`。

## 4. build.sh 只出本机架构

**解法：** arm64 + x86_64 分别编译后 `lipo`。

## 5. 合盖休眠让 sleep 失真

**解法：** `sleep_until` 短轮询墙钟；`_overslept` 中止误锁。`wind_down` 用 ASCII 引号，不用弯引号。

## 6. 双击 ESC 与键盘焦点

**解法：** 窗口可成为 key window；content view 接受 first responder。锁屏内 ESC 改为内联提示，非正式退出。

## 7. launchd bootout + set -e

首次安装 bootout 失败会吞掉 bootstrap。

**解法：** `launchctl bootout ... || true`

## 8. Notification Center 不可靠（睡前提醒）

横幅在勿扰、未授权、后台脚本场景下常不可见；`osascript display notification` 还可能显示坏图标。

**当前解法（2025+）：** 睡前 **T-5 / T-1 强制 App Toast**（`--toast-bedtime-warning`），不依赖 Notification Center。无 App 时用 `display alert` 兜底。**不要**在 `wind_down()` 里恢复 `notify.winddown` / `notify.locksoon`。

回归：`tests/test-locksoon-toast.sh`。

## 9. SwiftUI 窗口被 NSHostingView 撑高

**解法：** 显式窗口尺寸 + `FillHostingView` + 页面 topLeading 对齐。onboarding 约 420×588，dashboard 约 520×628。

## 10. App 侧每周预排程提醒

会与 daemon 重复，绕过 `skip_tonight` / `postpone_tonight`。

**解法：** daemon 是唯一提醒时机来源。

## 11. overlay 白天手动测试立刻退出

`checkWakeTime` 须检测「刚出锁屏窗」边界，不能「当前不在锁屏窗就 exit」。

## 12. 锁屏窗口过长

bedtime 与 wakeup 差 ≥ 15h 会导致不合理锁定时长。

**解法：** `MAX_LOCK_MINUTES=900`，init / config / schedule / daemon / App 统一校验。回归：`tests/test-lock-duration-limit.sh`。

## 13. T-1 Toast 推迟与 daemon 不同步

用户点推迟后 daemon 须 `BEDTIME=$(effective_bedtime)` 并再跑不可推迟的 T-1。

**解法：** App exit 2；写 `postpone_tonight`。回归：`test-locksoon-toast.sh`。

## 14. winddown_minutes 与 Toast 编排脱节

CLI 可把 `winddown_minutes` 设为 5–120（仅影响 launchd 何时启动 daemon），但 `wind_down()` 内 Toast 仍按固定 **5 分钟**编排（T-5 / T-1）。改 winddown 时不要假设提醒会同比提前。
