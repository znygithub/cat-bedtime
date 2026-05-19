# 历史踩坑与回归风险

这些记录保留给后续维护者。它们不是待办事项，而是已经修过、以后容易被改坏的地方

## 1. macOS bash 3.2 + 中文退格删不动

macOS 自带 bash 3.2，内核行规程不支持 `iutf8`（Linux 专属）。`read -r` 走 canonical 模式，退格按字节删而非按字符删——中文 UTF-8 一个字三字节，删几下就卡死了

**解法：** `read -e -r` 启用 readline，readline 自己处理 UTF-8，不依赖内核

## 2. read -e 退格会吃掉 prompt

用 `printf` 先打印带颜色的 prompt 再 `read -e`，readline 不知道 prompt 的存在，退格会把 `›` 都删掉

**解法：** 用 `read -e -r -p "$prompt"` 把 prompt 交给 readline 管理，ANSI 转义码用 `\001`..`\002` 包裹告诉 readline 这些是不可见字符：

```bash
_rl() { printf '\001%b\002' "$1"; }
local prompt="  $(_rl '\033[38;5;245m')›$(_rl '\033[0m') "
read -e -r -p "$prompt" answer
```

## 3. set -e 下子命令返回非零直接退出

`_parse_time` 解析失败 `return 1`，外层 `parsed=$(_parse_time "$input")` 拿到非零退出码，`set -e` 直接杀掉整个脚本——`while true` 重试循环根本走不到

**解法：** `parsed=$(_parse_time "$input") || true`

## 4. 锁屏靠字符串匹配起床时间，Mac 睡眠一觉就永远解不开

`LockScreen.swift` 里最早的 `checkWakeTime()` 用 `DateFormatter("HH:mm")` 把当前时间转成字符串，跟 `config.wakeupTime` 精确比对，匹配上才 `exit(0)`

问题是 Timer 只在进程实际运行时才跑。Mac 深度睡眠时 Timer 全部挂起——如果 07:00 那整整一分钟 Mac 都在睡，醒来时钟已经过了 07:00，字符串再也不可能等于 "07:00"，overlay 就**永远不退出**。daemon.sh 外层是 `wait $OVERLAY_PID`，连带整条唤醒流水线一起卡死

日志表现：当晚的 `Launching overlay` 之后，第二天早上**没有** `Wake time reached` 这行。用户一打开电脑就是黑屏锁死

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

原来 `src/overlay/build.sh` 直接 `swiftc -o` 一次，在 Apple Silicon 上就只出 arm64，而仓库承诺的是 universal 二进制（`ARCHITECTURE.md` 里"预编译通用二进制 arm64 + x86_64"）。Intel Mac 拿到的话直接跑不起来

**解法：** 分别用 `-target arm64-apple-macos11` / `-target x86_64-apple-macos11` 编出两份，再 `lipo -create` 合成 fat binary

## 6. install.sh 结束后用户不知道下一步

装完只打印"请运行 `zzz init`"，用户（或 AI）跑完安装脚本后什么也没弹出来，不知道接下来该干嘛

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

**现象①** 设定 23:00 睡、07:00 起，却在非锁机时段（如 21:00）被锁，或唤醒后锁在奇怪的时间。合盖后 `sleep N` 随进程挂起，唤醒后剩下的 `sleep` 仍按「冻结前」的剩余秒数跑完，墙钟与阶段时间错位

**解法①** `sleep_until` 改为短间隔轮询并每次用 `minutes_until` 看墙钟；`wind_down` 用阶段绝对时刻；若醒在「起床～风睡前」白天区则 `_overslept` 中止、不锁。见 `src/daemon.sh` 与 `tests/test-overslept-detection.sh`

**现象②** `wind_down` 里部分字符串用了 Unicode 弯引号（U+201C/U+201D），bash 不认，`bash -n` 报错，该段逻辑无法执行

**解法②** 全部改为 ASCII `"`。`tests/test-lockdown-window-and-syntax.sh` 里用 `bash -n` + 23:00～07:00 锁窗（含 21:00 不应锁）做回归

## 8. 偶发锁死时无后门

**需求** 若再出现逻辑/时间异常导致误锁，需要一条不破坏「契约时段内绝对锁死」的逃生口

**解法** 全屏层 `LockScreen.swift`：在约 0.45s 内连按两下 ESC → 重新读取 `config.json` 与当前系统时间；仅当**不在**锁机窗或**今天不是契约日**时可 `exit(0)`，否则忽略。Timer 仍按原逻辑到点自动退出

**补充** 到点退出的 `checkWakeTime` 必须检测「**刚才还在锁机窗 → 本秒已出窗**」再 `exit`；若误写成「只要当前不在锁机窗就 exit」，白天手动 `open` 测锁屏会约 1s 内被关，还容易被误以为「点一下屏就没了」

**补充2** 双击 ESC 不能只靠 local monitor。`NSApplication.ActivationPolicy.prohibited` + 普通 borderless window 可能拿不到键盘焦点，ESC 根本进不来。窗口需可成为 key/main window，content view 需接受 first responder，并用 `.accessory` 后主动 `activate`

## 9. launchd 首次安装时 `bootout` 失败会吞掉后续 `bootstrap`

`bin/zzz` 使用 `set -e`。`lib/schedule.sh` 在安装 / 更新任务时会先执行 `launchctl bootout` 再 `launchctl bootstrap`

首次安装时，`com.timetosleep.daemon` 本来还不存在，`launchctl bootout gui/<uid>/<label>` 会返回非零。若没有显式忽略这个返回值，`set -e` 会让 `zzz init` 提前退出：配置和 plist 可能已经写好，但任务没有真正加载进 launchd

**日志表现：**

- `~/.timetosleep/config.json` 存在
- `~/Library/LaunchAgents/com.timetosleep.daemon.plist` 存在
- `launchctl list | rg com.timetosleep` 查不到任务
- 到 `bedtime - winddown_minutes` 时 `~/.timetosleep/daemon.log` 没有 `Starting wind-down sequence`

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

它在命令层面可能返回成功，daemon 日志也会继续往下走，但用户屏幕上不一定出现横幅

常见原因：

- 通知来源是 `osascript` / Script Editor 一类系统脚本进程，不是明确的 `Cat Bedtime` App
- 系统设置里该来源的通知权限或横幅样式未开启
- 专注模式 / 勿扰 / 系统策略把通知静默
- launchd 后台脚本发出的通知比前台 App 更容易被系统压掉

**当前解法：** 睡前 daemon 的 `notify()` 会先通过 LaunchServices 调用 `open -g -j -n "Cat Bedtime.app" --args --notify ...`，由真正的 App bundle 通过 `UNUserNotificationCenter` 发系统原生通知。这样系统设置里会出现明确的 Cat Bedtime 通知来源，横幅、声音和通知中心展示都归到 App 身上

`--notify` 入口如果发现通知权限尚未请求，会先请求 `.alert` / `.sound` 授权，再投递通知。只要 App bundle 存在，daemon 就不会再回退成 AppleScript alert；否则「未授权」这种可修复状态会直接变成蓝文件夹弹窗。只有在完全找不到 App bundle 时，才回退到 `display alert … as informational`（约 12 秒自动消失）。仍然**特意不发** `osascript display notification`：

- osascript 没有 bundle identity，横幅会显示一个蓝色文件夹默认图标加 `--` 占位应用名，看起来像出了错的弹窗（视觉评审里被点名 "太丑"）
- 横幅本来就常被 DnD / 专注模式压掉，并不可靠（也是这个 pitfall 最初的起因）
- `display alert` 虽然不如原生通知轻，但作为兜底没有坏图标、不带占位应用名，且超时后脚本继续走，wind-down 不会无限阻塞

`notify()` 仍保留 `subtitle` 参数：原生通知会把它作为 notification subtitle；极端兜底时会把它提到 alert message 第一行（再隔一空行接 body）

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

注意：不要在 App 侧另做一套每周固定预排程，否则会和 daemon 的实时提醒重复，也会绕过 `skip_tonight` 这类运行时判断。daemon 仍然是提醒时机的唯一来源，App 只负责用自己的 bundle identity 投递原生通知

## 11. SwiftUI App 窗口被 `NSHostingView` 撑到整屏高

**现象** onboarding 首屏看起来像布局整体往下掉：上半屏空很多，标题、猫图、按钮被挤到下方，按钮甚至跑出窗口底部。用 System Events 查窗口尺寸时可以看到异常值：

```bash
osascript -e 'tell application "System Events" to tell process "Cat Bedtime" to get {position, size} of window 1'
# 例如：498, 38, 420, 1322
```

这里的 `1322` 接近屏幕可用高度，说明不是单个 `Spacer()` 写错，而是 SwiftUI 根内容把 AppKit 窗口撑高了

**踩坑点：**

- `NSWindow(contentRect:)` 只决定初始意图，不保证后续不会被 hosting view 的 ideal size 重新撑开
- 只设置 `contentMinSize` / `contentMaxSize` 也不够；窗口 frame 仍可能被 SwiftUI 布局协商拉到屏幕可用高度
- 根 `ZStack` 默认居中，如果子页面没有 `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`，内容高度又小于窗口时，会出现视觉上的整体下沉
- `ignoresSafeArea()` 更适合全屏 overlay。普通 App 窗口里不要随手用它当背景，否则会让调试方向更混乱

**解法：**

1. 给 SwiftUI 根视图一个显式窗口尺寸状态，根 `ContentView` 用 `.frame(width:height:)` 固定理想尺寸
2. 切换 dashboard / onboarding 尺寸时，同步更新这个尺寸状态，再调整 AppKit 窗口
3. 自定义 `NSHostingView`，让 `intrinsicContentSize` 返回 `noIntrinsicMetric`，避免它用 SwiftUI ideal size 反向撑大窗口
4. 锁窗口时同时设置 `minSize` / `maxSize` 和 `contentMinSize` / `contentMaxSize`，并直接设置 frame size；显示后的下一个 run loop 再兜底应用一次
5. 每个页面自身填满父容器并显式 top-leading 对齐，避免被根 `ZStack` 居中

核心结构：

```swift
class WindowSizeStore: ObservableObject {
    static let shared = WindowSizeStore()
    @Published var size = CGSize(width: 420, height: 560)
}

final class FillHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

ContentView()
    .frame(width: windowSize.size.width, height: windowSize.size.height)
```

**回归检查：**

- 打开 `bin/Cat Bedtime.app` 后，用上面的 `osascript` 查尺寸。onboarding 应接近 `420 x 588`（含标题栏），dashboard 应接近 `520 x 628`
- 截图确认 welcome 页标题、说明、猫图、按钮都在首屏内
- `rg -n 'ignoresSafeArea' src/app/CatBedtimeApp.swift` 不应在普通 App 根背景里命中；全屏 overlay 另算
