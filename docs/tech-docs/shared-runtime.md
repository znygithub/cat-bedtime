# 共享运行时数据

目录：`~/.timetosleep/`（launchd label 仍为 `timetosleep`）。

## 文件契约

| 文件 | 生产者 | 消费者 | 说明 |
| --- | --- | --- | --- |
| `config.json` | App / CLI | 全部 | 见下表 |
| `stats.json` | App / CLI / daemon | App / CLI | `installed_at`、`records[]` |
| `onboarding_install_id` | App | App | 本安装是否完成 App onboarding |
| `skip_tonight` | App / CLI | daemon | `YYYY-MM-DD` + 原因 |
| `postpone_tonight` | App / CLI / T-1 Toast | daemon / schedule | `YYYY-MM-DD`、`HH:mm`、原因 |
| `com.timetosleep.daemon.plist` | App / CLI | launchd | 每日 wind-down 触发 |
| `daemon.log` | launchd | 维护者 | stdout/stderr |

## config.json

| 字段 | 说明 |
| --- | --- |
| `bedtime`, `wakeup` | `HH:mm` |
| `days` | ISO weekday 字符串数组 `"1"`–`"7"` |
| `winddown_minutes` | 默认 **5**；CLI 可设 5–120，决定 launchd 触发时刻 |
| `activated_at`, `version` | 可选元数据 |

示例：

```json
{
  "bedtime": "23:00",
  "wakeup": "07:00",
  "days": ["1", "2", "3", "4", "5"],
  "winddown_minutes": 5,
  "activated_at": "2026-05-21T00:00:00Z",
  "version": "1.0.0"
}
```

## 锁屏窗口

`lib/config.sh`：`lock_duration_allowed_for_times` → `0 < minutes < 900`。

校验：init、config bedtime/wakeup、schedule_install、App 保存、daemon 启动。

## 有效 bedtime

`effective_bedtime()` / `effectiveBedtimeTonight()`：若今日 `postpone_tonight` 有效则用其中 `HH:mm`，否则 `config.bedtime`。

过期 `postpone_tonight` 会在 App 刷新或 daemon 启动时删除。
