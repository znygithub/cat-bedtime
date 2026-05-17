# 历史踩坑与回归风险

这些记录保留给后续维护者。它们不是待办事项，而是已经修过、以后容易被改坏的地方。

## 1. macOS bash 3.2 + 中文退格删不动

macOS 自带 bash 3.2，内核行规程不支持 `iutf8`（Linux 专属）。`read -r` 走 canonical 模式，退格按字节删而非按字符删——中文 UTF-8 一个字三字节，删几下就卡死了。

**解法：** `read -e -r` 启用 readline，readline 自己处理 UTF-8，不依赖内核。

## 2. read -e 退格会吃掉 prompt

用 `printf` 先打印带颜色的 prompt 再 `read -e`，readline 不知道 prompt 的存在，退格会把 `›` 都删掉。

**解法：** 用 `read -e -r -p "$prompt"` 把 prompt 交给 readline 管理，ANSI 转义码用 `\001`..`\002` 包裹告诉 readline 这些是不可见字符：

```bash
_rl() { printf '\001%b\002' "$1"; }
local prompt="  $(_rl '\033[38;5;245m')›$(_rl '\033[0m') "
read -e -r -p "$prompt" answer
```

## 3. set -e 下子命令返回非零直接退出

`_parse_time` 解析失败 `return 1`，外层 `parsed=$(_parse_time "$input")` 拿到非零退出码，`set -e` 直接杀掉整个脚本——`while true` 重试循环根本走不到。

**解法：** `parsed=$(_parse_time "$input") || true`

## 4. 锁屏靠字符串匹配起床时间，Mac 睡眠一觉就永远解不开

`LockScreen.swift` 里最早的 `checkWakeTime()` 用 `DateFormatter("HH:mm")` 把当前时间转成字符串，跟 `config.wakeupTime` 精确比对，匹配上才 `exit(0)`。

问题是 Timer 只在进程实际运行时才跑。Mac 深度睡眠时 Timer 全部挂起——如果 07:00 那整整一分钟 Mac 都在睡，醒来时钟已经过了 07:00，字符串再也不可能等于 "07:00"，overlay 就**永远不退出**。daemon.sh 外层是 `wait $OVERLAY_PID`，连带整条唤醒流水线一起卡死。

日志表现：当晚的 `Launching overlay` 之后，第二天早上**没有** `Wake time reached` 这行。用户一打开电脑就是黑屏锁死。

**解法：** 判断"是否已经进入白天窗口"而不是精确匹配时分。使用统一的锁屏窗口逻辑（支持跨午夜），哪怕 Timer 错过 07:00 的整个窗口，醒来后第一次采样就能退出：

```swift
let inAwakeWindow: Bool
if bedMin > wakeMin {
    inAwakeWindow = nowMin >= wakeMin && nowMin < bedMin
} else {
    inAwakeWindow = !(nowMin >= bedMin && nowMin < wakeMin)
}
if inAwakeWindow { exit(0) }
```

## 5. build.sh 只出本机架构，装到别的机器上跑不起来

原来 `src/overlay/build.sh` 直接 `swiftc -o` 一次，在 Apple Silicon 上就只出 arm64，而仓库承诺的是 universal 二进制（`ARCHITECTURE.md` 里"预编译通用二进制 arm64 + x86_64"）。Intel Mac 拿到的话直接跑不起来。

**解法：** 分别用 `-target arm64-apple-macos11` / `-target x86_64-apple-macos11` 编出两份，再 `lipo -create` 合成 fat binary。

## 6. install.sh 结束后用户不知道下一步

装完只打印"请运行 `zzz init`"，用户（或 AI）跑完安装脚本后什么也没弹出来，不知道接下来该干嘛。

**解法：** 安装末尾用 `osascript` 弹一个新 Terminal 窗口跑 `zzz init`，不管谁触发安装都能看到 onboarding：

```bash
osascript -e "
tell application \"Terminal\"
    activate
    do script \"'$INSTALL_DIR/bin/zzz' init\"
end tell
"
```

## 7. 合盖休眠让 `sleep` 失真 + `wind_down` 误用弯引号

**现象①** 设定 23:00 睡、07:00 起，却在非锁机时段（如 21:00）被锁，或唤醒后锁在奇怪的时间。合盖后 `sleep N` 随进程挂起，唤醒后剩下的 `sleep` 仍按「冻结前」的剩余秒数跑完，墙钟与阶段时间错位。

**解法①** `sleep_until` 改为短间隔轮询并每次用 `minutes_until` 看墙钟；`wind_down` 用阶段绝对时刻；若醒在「起床～风睡前」白天区则 `_overslept` 中止、不锁。见 `src/daemon.sh` 与 `tests/test-overslept-detection.sh`。

**现象②** `wind_down` 里部分字符串用了 Unicode 弯引号（U+201C/U+201D），bash 不认，`bash -n` 报错，该段逻辑无法执行。

**解法②** 全部改为 ASCII `"`。`tests/test-lockdown-window-and-syntax.sh` 里用 `bash -n` + 23:00～07:00 锁窗（含 21:00 不应锁）做回归。

## 8. 偶发锁死时无后门

**需求** 若再出现逻辑/时间异常导致误锁，需要一条不破坏「契约时段内绝对锁死」的逃生口。

**解法** 全屏层 `LockScreen.swift`：在约 0.45s 内连按两下 ESC → 重新读取 `config.json` 与当前系统时间；仅当**不在**锁机窗或**今天不是契约日**时可 `exit(0)`，否则忽略。Timer 仍按原逻辑到点自动退出。

**补充** 到点退出的 `checkWakeTime` 必须检测「**刚才还在锁机窗 → 本秒已出窗**」再 `exit`；若误写成「只要当前不在锁机窗就 exit」，白天手动 `open` 测锁屏会约 1s 内被关，还容易被误以为「点一下屏就没了」。

**补充2** 双击 ESC 不能只靠 local monitor。`NSApplication.ActivationPolicy.prohibited` + 普通 borderless window 可能拿不到键盘焦点，ESC 根本进不来。窗口需可成为 key/main window，content view 需接受 first responder，并用 `.accessory` 后主动 `activate`。

## 9. launchd 首次安装时 `bootout` 失败会吞掉后续 `bootstrap`

`bin/zzz` 使用 `set -e`。`lib/schedule.sh` 在安装 / 更新任务时会先执行 `launchctl bootout` 再 `launchctl bootstrap`。

首次安装时，`com.timetosleep.daemon` 本来还不存在，`launchctl bootout gui/<uid>/<label>` 会返回非零。若没有显式忽略这个返回值，`set -e` 会让 `zzz init` 提前退出：配置和 plist 可能已经写好，但任务没有真正加载进 launchd。

**日志表现：**

- `~/.timetosleep/config.json` 存在。
- `~/Library/LaunchAgents/com.timetosleep.daemon.plist` 存在。
- `launchctl list | rg com.timetosleep` 查不到任务。
- 到 `bedtime - winddown_minutes` 时 `~/.timetosleep/daemon.log` 没有 `Starting wind-down sequence`。

**解法：** `bootout` 是「如果存在则卸载」的清理动作，允许失败：

```bash
launchctl bootout "$gui/$AGENT_LABEL" 2>/dev/null || true
launchctl bootstrap "$gui" "$PLIST_PATH"
```

## 10. `osascript display notification` 返回成功但用户看不到通知

睡前提醒最初只用 AppleScript：

```applescript
display notification "猫猫还有 15 分钟就要睡觉了" with title "Cat Bedtime" sound name "default"
```

它在命令层面可能返回成功，daemon 日志也会继续往下走，但用户屏幕上不一定出现横幅。

常见原因：

- 通知来源是 `osascript` / Script Editor 一类系统脚本进程，不是明确的 `Cat Bedtime` App。
- 系统设置里该来源的通知权限或横幅样式未开启。
- 专注模式 / 勿扰 / 系统策略把通知静默。
- launchd 后台脚本发出的通知比前台 App 更容易被系统压掉。

**当前解法：** `notify()` 只用 `display alert … as informational`（约 12 秒自动消失）。**特意不发** `display notification`：

- osascript 没有 bundle identity，横幅会显示一个蓝色文件夹默认图标加 `--` 占位应用名，看起来像出了错的弹窗（视觉评审里被点名 "太丑"）。
- 横幅本来就常被 DnD / 专注模式压掉，并不可靠（也是这个 pitfall 最初的起因）。
- `display alert` 是居中模态 sheet，自带「温柔提醒」气质、不带占位图标、超时后脚本继续走，wind-down 不会无限阻塞。

`notify()` 仍保留 `subtitle` 参数：当非空时，会被提到 alert message 第一行（再隔一空行接 body），让「还有 N 分钟到关灯」这种关键信息天然位于视觉重心。

注意 AppleScript 成功时 stderr/stdout 里仍可能混入人类可读的状态行，不要靠「解析输出」判断是否失败；只看退出码：

```bash
output=$(osascript ... 2>&1)
status=$?
if (( status != 0 )); then
  log "notify osascript failed ($status): $output"
else
  log "notify sent: $title — ${subtitle:-∅}"
fi
```

**长期正确做法：** 做一个真正的 macOS App / helper，由 `Cat Bedtime.app` 申请通知权限，并用 `UNUserNotificationCenter` 发通知。这样系统设置里会出现明确的 Cat Bedtime 通知来源，横幅、声音和通知中心展示都更可控。Shell + `osascript` 只能算运行时兜底方案，不应视作稳定通知系统。
