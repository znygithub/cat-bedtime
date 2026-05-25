# 技术债跟踪

| 项 | 说明 | 优先级 |
| --- | --- | --- |
| `wind_down` 硬编码 `total_min=5` | 与 `config.winddown_minutes` 仅 launchd 触发相关；产品/UI 是否暴露 winddown 待决 | 中 |
| `--notify-l10n` 保留但未用于睡前 | 可考虑 deprecate 或仅测试文档 | 低 |
| 旧配置 `winddown_minutes=15` | App 启动时迁移为 5（见 `CatBedtimeApp.swift`） | 低 |

完成项移入 `completed/`。
