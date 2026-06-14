# 新用户领养（Onboarding）

## App 流程

欢迎 → 睡觉/起床（默认 23:00 / 07:00）→ 启用日（默认周一至五）→ 承诺摘要 → 确认句 → 写 `config.json` / `stats.json` / `onboarding_install_id` → 请求通知权限（失败不阻断）→ 注册 launchd → **锁屏预览**（18s，`--preview-exit-on-esc`）→ Dashboard。

## CLI 流程

`zzz init`：同上语义；`winddown_minutes` 固定写入 **5**；完成后 `schedule_install`。

## 功能需求

- 未完成当前安装 onboarding → 必须走领养
- 时间 `HH:mm`；锁屏窗 **< 15h** 否则拒绝
- 确认句错误 → 不写配置、不注册 launchd
- `onboarding_install_id` 标记本安装已完成 App onboarding

## 验收

- `config.json`、`stats.json`、launchd plist 存在
- 再次打开同一安装 → Dashboard
- CLI init 后 App 可读配置
