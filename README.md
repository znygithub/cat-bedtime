# Cat Bedtime

> 到点了，电脑借给猫猫睡觉。

一个跑在 macOS 上的睡前锁屏工具。你设置猫猫每天几点来、几点走；时间到了，它会占住屏幕睡觉，你就该离开电脑了。

[English](README_EN.md)

## 它做什么

- **猫猫领养流程**：`zzz init` 会引导你设置猫猫来睡觉的时间、离开的时间、每周来住的日子，以及提前多久提醒。
- **睡前提醒**：到点前逐步发送通知、降低亮度和音量，提醒你收拾工作。
- **强制锁屏**：睡觉时间到后，全屏覆盖所有显示器、暂停媒体、静音；覆盖层被杀掉也会重新拉起。
- **到点恢复**：起床时间后退出锁屏，恢复亮度和音量，并记录猫猫来过。
- **请假机制**：`zzz tonight off` 可以让猫猫今晚不来，需要留一句原因。

## 安装

```bash
git clone https://github.com/znygithub/cat-bedtime.git
cd cat-bedtime
bash install.sh
```

需要 macOS 和系统自带的 `python3`。日常安装不需要 Xcode、`jq` 或其他第三方依赖。

运行时目录仍沿用早期项目名：`~/.timetosleep/`。这是为了兼容已有安装和 launchd 配置。

## 开始使用

```bash
zzz init
```

完成领养设置后，用下面的命令查看状态：

```bash
zzz
```

## 常用命令

```bash
zzz                         # 今晚猫猫状态
zzz init                    # 领养 / 重新设置
zzz status                  # 猫猫到访记录
zzz config                  # 查看猫猫日程
zzz config bedtime 23:30    # 修改猫猫睡觉时间
zzz config wakeup 07:30     # 修改猫猫离开时间
zzz config winddown 30      # 修改提前提醒分钟数
zzz tonight off             # 今晚不让猫猫来睡觉
zzz log                     # 猫猫来访历史
zzz test 10                 # 测试锁屏 10 秒
zzz uninstall               # 卸载
```

## 技术实现

- `bin/zzz` 是 Shell CLI 入口。
- `src/init.sh` 负责猫猫领养设置。
- `src/daemon.sh` 编排睡前提醒、锁屏、唤醒恢复。
- `bin/zzz-overlay` 是预编译 Swift 全屏覆盖层，支持多显示器。
- `launchd` 负责定时触发每晚流程。
- 配置和记录存储在 `~/.timetosleep/config.json` 与 `~/.timetosleep/stats.json`。

产品目标和体验叙事见 [PRODUCT_GOALS.md](PRODUCT_GOALS.md)。开发者可以从 [ARCHITECTURE.md](ARCHITECTURE.md) 了解模块结构；历史踩坑和回归风险保留在 [PITFALLS.md](PITFALLS.md)。

## 许可

MIT
