# daemon 与 launchd

## launchd

- Label：`com.timetosleep.daemon`
- Plist：`~/Library/LaunchAgents/com.timetosleep.daemon.plist`
- **StartCalendarInterval**：每天 `bedtime - winddown_minutes`（`effective_bedtime` 含今晚晚点）
- **RunAtLoad**：`true` — 登录或安装后若当前已在 wind-down / 锁屏窗且今天为启用日，`_should_kickstart_now` 允许立即跑 daemon（见 `test-schedule-catchup.sh`）
- 非法 `winddown_minutes` 时默认 **5**
- `schedule_install` 前校验锁屏窗 `< 15h`
- 移除遗留 agent：`com.timetosleep.bootcheck`

## daemon 阶段

`current_phase` → `winddown` | `lockdown` | `outside`

| 启动时 phase | 行为 |
| --- | --- |
| winddown | `wind_down` → 成功则 `lockdown` + `wake_up`；返回 2 则只提醒不锁；否则中止 |
| lockdown | 已在锁屏窗：直接 `lockdown` + `wake_up`（先 save 亮度音量） |
| outside | 打日志退出 |

## wind_down 时序

`wind_down()` 内 **`total_min=5` 硬编码**（与 `config.winddown_minutes` 无关）：

| 时刻 | 行为 |
| --- | --- |
| T-5min | `toast_bedtime_alert` → `zzz-app --toast-bedtime-warning <N>` |
| stage 2/3 | 仅亮度 / 音量渐变 |
| T-1min | `toast_bedtime_alert 1 1`（`--allow-postpone`） |
| 用户推迟 | App exit **2** → `postpone_tonight` → `BEDTIME=$(effective_bedtime)` → 再 T-1（不可再推迟） |
| bedtime | 进入 lockdown |

非启用 wind-down 日：T-5 提醒后 `return 2`，**不锁屏**。

## lockdown / wake_up

- `media_pause_all`、`media_mute`、`brightness_set 0.05`
- `shortcuts run "Turn On Focus"`（失败忽略）
- overlay 循环：`wait` 退出后若仍在锁屏窗则 2s 重启
- 出锁屏窗后 `stats_record completed`
- `wake_up`：恢复亮度音量、`Turn Off Focus`（**无**起床弹窗）

## Toast 实现

```bash
toast_bedtime_alert(minutes, allow_postpone)
  → zzz-app --toast-bedtime-warning "$minutes" [--allow-postpone]
  → 无 bundle 时 toast_bedtime_alert_fallback (display alert)
toast_locksoon()  # toast_bedtime_alert 1 0
```

App：`BedtimeReminderToastRunner`（`NSPanel`，25s 自动关闭）。

保留 `notify()` / `notify_native_l10n()`，但 **wind_down 不再调用**。

## 时间逻辑

- `sleep_until()` — 短轮询墙钟（近点 5s，否则 30s）
- `_overslept()` — 醒在白天窗口则中止
- 跨午夜锁屏窗：`bedtime > wakeup` 时用 `now >= bed || now < wake`

## 相关测试

`test-locksoon-toast.sh`、`test-overslept-detection.sh`、`test-daemon-startup-phase.sh`、`test-schedule-catchup.sh`

踩坑见 [RELIABILITY.md](../RELIABILITY.md)。
