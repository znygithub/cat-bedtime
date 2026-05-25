# 安全说明

Cat Bedtime 是**本地单机**工具，无账号、无后端、无远程控制。

## 数据位置

- 用户配置与记录：`~/.timetosleep/`
- launchd：`~/Library/LaunchAgents/com.timetosleep.daemon.plist`
- 日志：`~/.timetosleep/daemon.log`

数据不离开本机（除非用户自行备份目录）。

## 权限与能力

| 能力 | 用途 |
| --- | --- |
| 全屏 overlay | 锁屏约束 |
| 亮度 / 音量 | wind-down 与恢复 |
| 通知（可选） | 保留 `--notify` 入口；睡前主路径为 Toast |
| AppleScript alert | 无 App bundle 时的 Toast 兜底 |

## 约束边界

- 正式锁屏时段内不提供「一键解锁」；异常逃生见 [tech-docs/overlay.md](tech-docs/overlay.md)
- 不拦截系统级重启 / 强制关机（三连 ESC 提示重启电脑）

## 发布

维护者本地签名与公证；用户从 GitHub Releases 下载。见 [references/release-process.md](references/release-process.md)。

## 非目标

- 不收集遥测
- 不存储密码或密钥于仓库
- 不做网络 API 调用（产品功能层面）
