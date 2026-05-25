# 配置与状态 schema（生成说明）

本项目**无关系型数据库**。持久化以 `~/.timetosleep/` 下 JSON 与文本文件为主。以下为当前契约摘要；权威实现见 `lib/config.sh` 与 [tech-docs/shared-runtime.md](../tech-docs/shared-runtime.md)。

## config.json

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `bedtime` | string `HH:mm` | 睡觉时间 |
| `wakeup` | string `HH:mm` | 起床时间 |
| `days` | string[] | ISO  weekday `"1"`–`"7"` |
| `winddown_minutes` | number | 默认 5；launchd 提前量 |
| `activated_at` | string ISO8601 | 可选 |
| `version` | string | 可选 |

**约束：** `0 < (wakeup - bedtime 跨午夜分钟) < 900`

## stats.json

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `installed_at` | string | 安装时间 |
| `records` | array | 完成 / 跳过记录 |

## skip_tonight

```text
YYYY-MM-DD
原因文本
```

## postpone_tonight

```text
YYYY-MM-DD
HH:mm
原因文本
```

## onboarding_install_id

单行 UUID 或安装标识，App 专用。
