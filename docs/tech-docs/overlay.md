# overlay 锁屏

实现：`src/overlay/LockScreen.swift` → `bin/zzz-overlay`。

## 正式锁屏

- 每个 `NSScreen` 一个 borderless 全屏窗口
- `CGShieldingWindowLevel + 1`；每 2s 重置层级与 frame
- 监听显示器变化并重建
- 素材：`cat-bedtime.mov`（bundle `Resources/assets/` 或 `~/.timetosleep/assets/`）
- 显示当前时间、剩余锁屏时间、猫猫动画（三幕 + 夜灯）

## 退出

- **正常**：进入白天窗口（统一 `LockWindowMath`，非字符串精确匹配 wakeup）
- **预览模式**：`--preview-exit-on-esc` 时任意 ESC 即 `exit(0)`；`--preview-duration N` 超时退出
- **正式锁屏 ESC**：
  - 若 `LockWindowMath.canEmergencyExit`（非锁屏窗或非启用日）→ 立即退出
  - 否则：按 1 次 → 内联 `lock.escape_rest`；1.2s 内连按 3 次 → `lock.escape_restart`（提示重启电脑）

## daemon 监控

overlay 退出且 `minutes_until(wakeup)` 仍处锁屏窗 → 2s 后重启。

## Onboarding 预览

App `LockPreviewView` 启动：

```text
zzz-overlay --preview-exit-on-esc --preview-duration 18
```

不写 `stats.json` completed。

## 构建

`src/overlay/build.sh` — universal binary 时 arm64 + x86_64 后 `lipo`。

## 开发预览（非正式路径）

`CatBedtimePreview.swift`、`CatVideoBedtimePreview.swift` 仅用于动效实验，不进入发布安装流程。
