# 技术文档索引

先读 [ARCHITECTURE.md](../../ARCHITECTURE.md)、[core-beliefs.md](../core-beliefs.md)。

## 文档

| 文档 | 内容 |
| --- | --- |
| [shared-runtime.md](shared-runtime.md) | `~/.timetosleep/` 数据契约 |
| [daemon-and-schedule.md](daemon-and-schedule.md) | daemon 阶段、Toast、launchd catch-up、Focus |
| [overlay.md](overlay.md) | 锁屏 UI、预览参数、ESC |

## 关键代码

| 领域 | 路径 |
| --- | --- |
| App | `src/app/CatBedtimeApp.swift`（可执行 `zzz-app`） |
| CLI | `bin/zzz`、`src/cli/init.sh` |
| 库 | `lib/config.sh`、`lib/schedule.sh`、`lib/stats.sh`、`lib/ui.sh`、`lib/i18n.sh` |
| daemon | `src/cli/daemon.sh` |
| overlay | `src/overlay/LockScreen.swift` |
| i18n | `locales/messages.json`、`lib/i18n.py`、`src/shared/L10n.swift` |
| 测试 | `tests/test-*.sh` |

## 规则摘要

- 单套 daemon + overlay；App 不预排程提醒
- 睡前 Toast：`--toast-bedtime-warning`（非 Notification Center）
- 锁屏窗 `< 15h`
- `winddown_minutes` ≠ daemon 内 T-5/T-1 编排（后者固定 5min）
