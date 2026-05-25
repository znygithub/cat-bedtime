# 锁屏与睡前提醒

## 睡前提醒

**方案：** 两级 **强制 App Toast**（`notify.bedtime.*`），不依赖 Notification Center。

| 时机 | daemon 调用 | 说明 |
| --- | --- | --- |
| T-5min | `--toast-bedtime-warning <N>` | 无推迟按钮 |
| T-1min | `--toast-bedtime-warning 1 --allow-postpone` | 可一次性 +5min；文案含「到点后电脑将被占用」 |

中间仅亮度/音量渐变。Toast 失败不阻止 lockdown。无 App 时 `display alert` 兜底。

> `config.winddown_minutes` 只决定 launchd **提前多久启动 daemon**；daemon 内 Toast 时刻仍按睡前 **5 分钟**编排（见 [ARCHITECTURE.md](../../ARCHITECTURE.md)）。

## 正式锁屏

1. 到 bedtime → overlay 全屏（多显示器）
2. 尝试开启 Focus（`Turn On Focus` shortcut）
3. overlay 被杀且在锁屏窗内 → daemon 2s 重启
4. 到 wakeup → overlay 退出 → 恢复亮度音量、关闭 Focus → `completed`

锁屏窗 `< 15h`：init / config / schedule / daemon / App 统一校验。

非启用日 wind-down：可收到 T-5 提醒，**不进入 lockdown**。

## overlay

- 无普通关闭按钮
- ESC：受控逃生（非锁屏窗/非启用日）或内联提示（`lock.escape_rest` / 三连按 `lock.escape_restart`）
- 预览：`--preview-exit-on-esc --preview-duration 18`

## App bundle 资源

`build.sh` 打入：`zzz-overlay`、`src/cli/`（含 daemon.sh）、`lib/`、`assets/`、`locales/messages.json`。

## 验收

- `zzz test 10`
- 跨午夜 23:00–07:00
- 休眠醒来不误锁、overlay 不永久停留
- kill overlay 后 daemon 重启
- T-5/T-1 在无通知权限时仍可见
