# Cat Bedtime 架构

本文档描述当前代码现状。产品已经从早期的 TimeToSleep 契约叙事转为猫猫睡觉叙事，但运行时目录和 launchd label 仍保留 `timetosleep`，用于兼容已有安装。

## 目录结构

```text
cat-bedtime/
├── bin/
│   ├── zzz                 # CLI 入口
│   └── zzz-overlay         # 预编译 Swift 全屏覆盖层
├── lib/
│   ├── config.sh           # 配置读写与时间工具
│   ├── schedule.sh         # launchd agent 安装 / 更新 / 卸载
│   ├── stats.sh            # 猫猫来访记录和连续记录计算
│   └── ui.sh               # 终端 UI 组件
├── src/
│   ├── init.sh             # zzz init 领养流程
│   ├── daemon.sh           # 睡前提醒 → 锁屏 → 唤醒恢复
│   ├── bootcheck.sh        # 登录时锁屏窗口自检
│   ├── media.sh            # 暂停媒体、保存 / 恢复音量
│   ├── brightness.sh       # 保存 / 恢复 / 渐变亮度
│   └── overlay/
│       ├── LockScreen.swift              # 正式视频猫猫锁屏覆盖层
│       ├── build.sh                      # 编译正式覆盖层
│       ├── CatBedtimePreview.swift       # 手绘猫猫动效预览
│       ├── build-cat-bedtime-preview.sh  # 手绘预览编译脚本
│       ├── CatVideoBedtimePreview.swift  # 视频合成预览
│       └── build-cat-video-preview.sh    # 视频预览编译脚本
├── tests/                  # Bash 回归测试
├── install.sh              # 安装脚本
├── README.md               # 中文产品说明
├── README_EN.md            # 英文产品说明
└── PITFALLS.md             # 历史踩坑与回归风险
```

## 运行时数据

安装后数据存储在 `~/.timetosleep/`：

```text
~/.timetosleep/
├── bin/                    # 安装后的 zzz 和 zzz-overlay
├── lib/                    # 安装后的库脚本
├── src/                    # 安装后的运行脚本
├── assets/                 # 猫猫锁屏视频素材
├── config.json             # 猫猫日程配置
├── stats.json              # 到访 / 请假记录
├── saved_brightness        # 锁屏前亮度备份
├── saved_volume            # 锁屏前音量备份
├── skip_tonight            # 今晚请假标记
└── daemon.log              # daemon / bootcheck 日志
```

## 核心流程

### 1. 安装

`install.sh` 做四件事：

1. 检查 macOS 和 `python3`。
2. 复制 `bin/`、`lib/`、`src/` 到 `~/.timetosleep/`。
3. 创建 `zzz` 命令链接或写入 shell PATH。
4. 打开一个 Terminal 窗口运行 `zzz init`。

正式安装不需要 Xcode；仓库内的 `bin/zzz-overlay` 已经是预编译二进制。

### 2. 领养设置

`zzz init` 会执行 `src/init.sh`：

1. 展示猫猫领养说明。
2. 收集猫猫睡觉时间、离开时间、来住日子和提前提醒时间。
3. 要求用户输入确认句。
4. 写入 `config.json`，初始化 `stats.json`。
5. 调用 `lib/schedule.sh` 注册 launchd agent。

### 3. 每晚流程

`com.timetosleep.daemon` 在 `bedtime - winddown_minutes` 触发 `src/daemon.sh`。

流程：

1. 读取配置，检查今天是否启用。
2. 如果存在有效 `skip_tonight`，记录为请假并退出。
3. 保存当前亮度和音量。
4. 根据真实墙钟分阶段发送提醒、降低亮度和音量。
5. 到睡觉时间后暂停媒体、静音、降低亮度并启动 `zzz-overlay`。
6. 如果覆盖层意外退出且仍在锁屏时段，2 秒后重新启动。
7. 起床时间后恢复亮度和音量，记录 `completed`。

`daemon.sh` 的等待逻辑按墙钟轮询，不依赖一次长 `sleep`，避免 Mac 合盖休眠后时间错位。

### 4. 登录自检

`com.timetosleep.bootcheck` 在登录时触发 `src/bootcheck.sh`。

它会检查：

- 配置是否存在。
- 当前锁屏窗口对应的睡觉日是否是猫猫来住日。跨午夜时，凌晨部分归属前一天晚上。
- 今晚是否请假。
- 当前时间是否在 `bedtime ~ wakeup` 锁屏窗口内。

如果仍在锁屏窗口内，会启动覆盖层并保持它存活到起床时间。

### 5. 正式锁屏覆盖层

`src/overlay/LockScreen.swift` 是正式锁屏程序，编译产物为 `bin/zzz-overlay`。

当前正式覆盖层做这些事：

- 为每个显示器创建一个全屏 borderless window。
- 使用 `CGShieldingWindowLevel + 1` 保持在大多数窗口之上。
- 每 2 秒重置窗口层级和大小。
- 监听显示器变化并重建窗口。
- 从 `~/.timetosleep/assets/cat-bedtime.mov` 读取透明猫猫视频。
- 渲染猫猫出现、关灯、睡下的正式动画效果。
- 关灯后在左上角显示时间、猫猫文案和醒来倒计时。
- 到起床窗口后自动退出。
- 支持异常逃生：短时间内连按两下 ESC 会重新读取配置；只有当前不在锁屏窗口或今天不是启用日时才退出。

### 6. 预览程序

`CatBedtimePreview.swift` 和 `CatVideoBedtimePreview.swift` 是开发预览。它们会随 `src/` 被复制到安装目录，但没有用户命令入口，也不会参与正式覆盖层。

- 手绘预览用于验证猫猫走动、拉灯、上床睡觉的纯代码动效。
- 视频预览用于验证透明视频 / 绿幕 / 黑底素材与真实桌面截图的合成。

这些文件是可继续实验的素材管线；正式锁屏入口已经在 `LockScreen.swift` 中使用视频猫猫效果。

## launchd

安装后会写入两个用户级 agent：

| Label | 触发方式 | 职责 |
| --- | --- | --- |
| `com.timetosleep.daemon` | 每天 `bedtime - winddown` | 执行睡前提醒和锁屏流程 |
| `com.timetosleep.bootcheck` | 登录时 `RunAtLoad` | 防止重启绕过锁屏窗口 |

Plist 文件位于 `~/Library/LaunchAgents/`。

## 模块依赖

```text
bin/zzz
├── lib/config.sh
├── lib/ui.sh
├── lib/stats.sh
└── lib/schedule.sh       # 仅 config / init / uninstall / 时间变更时加载

src/init.sh
├── lib/ui.sh
├── lib/config.sh
├── lib/stats.sh
└── lib/schedule.sh

src/daemon.sh
├── lib/config.sh
├── lib/stats.sh
├── src/media.sh
├── src/brightness.sh
└── bin/zzz-overlay

src/bootcheck.sh
├── lib/config.sh
├── src/media.sh
├── src/brightness.sh
└── bin/zzz-overlay

bin/zzz-overlay
├── ~/.timetosleep/config.json
└── ~/.timetosleep/stats.json
```

## 测试

当前测试是 Bash 脚本：

```bash
tests/test-lockdown-window-and-syntax.sh
tests/test-overslept-detection.sh
tests/test-config-numeric-fallback.sh
```

它们覆盖：

- `daemon.sh` / `bootcheck.sh` 语法。
- 23:00 到 07:00 这类跨午夜锁屏窗口。
- 合盖休眠后不应在白天误锁。
- `winddown_minutes` 缺失或非法时的默认值。

## 改代码从哪里开始

- 改 CLI 文案或命令：`bin/zzz`
- 改领养流程：`src/init.sh`
- 改提醒、锁屏、唤醒恢复：`src/daemon.sh`
- 改重启后自检：`src/bootcheck.sh`
- 改 launchd plist：`lib/schedule.sh`
- 改正式锁屏 UI：`src/overlay/LockScreen.swift`
- 重新编译正式覆盖层：`src/overlay/build.sh`
- 做猫猫动效实验：`src/overlay/CatBedtimePreview.swift` 或 `src/overlay/CatVideoBedtimePreview.swift`
