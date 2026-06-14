# 前端实现（App）

主文件：`src/app/CatBedtimeApp.swift`。Bundle 可执行文件：**`zzz-app`**。

## 窗口

| 模式 | 尺寸 |
| --- | --- |
| Onboarding | 420 × 560 |
| Dashboard | 520 × 600 |

`WindowSizeStore` + `FillHostingView`（`noIntrinsicMetric`）防止 SwiftUI 撑窗。见 [RELIABILITY.md](RELIABILITY.md)。

**AppDelegate 生命周期**（`windowShouldClose` / `hideWindowToAppIcon`）：

| 操作 | 行为 |
| --- | --- |
| 红叉、`⌘W`、黄键、菜单「隐藏窗口」 | `orderOut`，不 terminate |
| `⌘Q`、菜单「退出」 | `confirmQuit` → `pauseScheduleForAppQuit` |
| 点击 Dock 图标 | `showMainWindow` |

## 视图

| 视图 | 职责 |
| --- | --- |
| `WelcomeView` | 领养叙事 |
| `ScheduleConfigView` | 时间、启用日、`ScheduleRules.isAllowedLockDuration` |
| `AgreementView` | 承诺、确认句 |
| `LockPreviewView` | 子进程 overlay 预览 18s |
| Dashboard | 状态、编辑、**DelayPopover**（15/30/自定义晚点）、请假 |

## ConfigManager

- `saveConfig` / `updateConfigAndReschedule` — 写 JSON + launchd（`installSchedule`）
- `postponeTonight` / `setTonightBedtime` — `postpone_tonight` 三行格式
- `refreshTonightPostpone` — 清理过期晚点
- 启动时：`winddown_minutes == 15` → 迁移为 5

## 睡前 Toast（daemon 拉起）

- `ToastCommand.exitIfRequested()` — 先于主 UI
- `BedtimeReminderToastRunner` — `NSPanel`，25s 超时
- T-1 推迟：`ProductDefaults.postponeMinutes`（5）→ `setTonightBedtime(..., reschedule: false)` → **exit 2**

## 通知

- `NotificationCommand` — `--notify` / `--notify-l10n`（daemon 睡前不用）
- Dashboard 手动晚点成功后：`NotificationScheduler.sendImmediateNotification`（`notify.delay.*`）

## CLI UI

`lib/ui.sh` + `lib/i18n.sh`；中文 readline 输入。

设计 token：`Lamp` enum，见 [DESIGN.md](DESIGN.md)。
