# App 交互与 CLI 日常

## Dashboard（App）

展示：今晚启用日、有效 bedtime（含晚点）、wakeup、请假/晚点状态。

可修改：**bedtime、wakeup、启用日**（保存前校验锁屏窗 `< 15h`，刷新 launchd）。

**不可在 App 内修改** `winddown_minutes`（固定默认 5；仅 CLI 可改）。旧值 15 会在 App 启动时自动迁移为 5。

### 窗口行为

- **隐藏窗口**（左上角红叉、黄键、`⌘W`、菜单「隐藏窗口」）：窗口收起到 Dock，**不弹确认**；App 与 launchd 后台定时任务继续运行
- **退出 App**（`⌘Q`、菜单「退出」）：弹出确认；确认后暂停 launchd 并退出
- 再次点击 Dock 图标：恢复窗口

### 晚点再来

- 可选 **15 / 30 分钟**或自定义分钟数 + 原因
- 写入 `postpone_tonight`，刷新 launchd 到新的有效 bedtime
- 延后后须仍满足 `canUseBedtime`（锁屏窗 `< 15h`），否则提示 `delay.lock_too_long`
- 成功后可选发一条 App 通知（`notify.delay.*`）

### 今晚请假

原因必填 → `skip_tonight`。

## CLI 命令

| 命令 | 说明 |
| --- | --- |
| `zzz` | 今晚状态（ETA、晚点、请假、启用日） |
| `zzz status` | 同上 + 统计摘要（完成率等） |
| `zzz init` | 领养（默认 winddown=5） |
| `zzz config` | 查看配置 |
| `zzz config bedtime\|wakeup HH:mm` | 改时间（校验 `< 15h`） |
| `zzz config winddown N` | **5–120**，改 launchd 触发时刻（不影响 daemon 内 T-5/T-1 编排） |
| `zzz tonight off` | 今晚请假 |
| `zzz log` | 最近 20 条记录 |
| `zzz test [秒]` | overlay 测试（1–120，结束 kill） |
| `zzz uninstall` | 确认句后移除 launchd 与 `~/.timetosleep` |
| `zzz help` | 帮助 |

## App 命令行（daemon 调用）

| 参数 | 说明 |
| --- | --- |
| `--toast-bedtime-warning <min> [--allow-postpone]` | 睡前强制 Toast |
| `--toast-locksoon` | T-1min，不可推迟 |
| `--notify` / `--notify-l10n` | 保留；daemon 睡前不调用 |

T-1 Toast「推迟 5 分钟」：`setTonightBedtime(..., reschedule: false)` + exit **2**（每晚 daemon 流程内一次）。

Dashboard「晚点再来」与 Toast 推迟共用 `postpone_tonight` 文件格式。

## 共享状态

- `effective_bedtime` / `effectiveBedtimeTonight()`：优先今晚 `postpone_tonight`
- 过期 `postpone_tonight` / `skip_tonight` 须清理并恢复 launchd

## 验收

- App 改配置后 CLI `zzz config` 可读；反之亦然
- 请假后 daemon 记录 skipped 并退出
- 晚点后 daemon 与 launchd 使用新 bedtime
