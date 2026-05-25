# 需求文档索引

产品哲学见 [core-beliefs.md](../core-beliefs.md)，架构见 [ARCHITECTURE.md](../ARCHITECTURE.md)。

| 文档 | 范围 |
| --- | --- |
| [new-user-onboarding.md](new-user-onboarding.md) | App 领养、CLI `zzz init` |
| [app-interaction.md](app-interaction.md) | Dashboard、CLI 日常、请假/晚点 |
| [lockscreen.md](lockscreen.md) | 睡前提醒、daemon、overlay、恢复 |

## 跨模块规则

- App 与 CLI 共享 `~/.timetosleep/`
- daemon 是唯一提醒与锁屏执行者
- 锁屏窗 `< 15h`；睡前提醒为 T-5 / T-1 强制 Toast
