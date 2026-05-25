# 质量与测试

## 全量回归

```bash
for t in tests/test-*.sh; do bash "$t"; done
```

| 脚本 | 覆盖 |
| --- | --- |
| `test-lockdown-window-and-syntax.sh` | `bash -n`、跨午夜、白天不误锁 |
| `test-overslept-detection.sh` | 墙钟 stage、`_overslept` |
| `test-locksoon-toast.sh` | T-5/T-1 接线、无 NC 睡前 notify |
| `test-lock-duration-limit.sh` | `< 15h` 边界 |
| `test-daemon-startup-phase.sh` | phase 判定 |
| `test-schedule-catchup.sh` | RunAtLoad kickstart |
| `test-config-numeric-fallback.sh` | 无 jq |
| `test-i18n-lang.sh` | ZZZ_LANG |

## 改动 → 最少测试

| 改动 | 至少 |
| --- | --- |
| daemon / 时间 | 全部 Bash 回归 |
| Toast | `test-locksoon-toast.sh` + 手测 `--toast-bedtime-warning` |
| 配置 / 锁窗 | `test-lock-duration-limit.sh` |
| schedule / launchd | `test-schedule-catchup.sh` |
| overlay | `zzz test 10`、预览 ESC |
| 发布 | [release-process.md](references/release-process.md) |

## 发布前手测

**App：** DMG → onboarding → 预览 → Dashboard 晚点/请假 → Toast 参数手测

**CLI：** `install.sh` → `zzz init` → `zzz status` → `zzz test 10`

**边界：** 跨午夜、14h59/15h 锁窗、无 App bundle 时 alert 兜底、catch-up（登录时已在 wind-down 窗）
