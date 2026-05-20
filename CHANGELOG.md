# 版本记录 / Changelog

本文件记录每个公开发布版本的变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

下载安装包请前往 [GitHub Releases](https://github.com/znygithub/cat-bedtime/releases)。

---

## [v1.1.0](https://github.com/znygithub/cat-bedtime/releases/tag/v1.1.0) — 2026-05-20

### 新增
- 守护进程启动阶段回归测试（`tests/test-daemon-startup-phase.sh`）
- 锁屏预览模式右上角倒计时徽标
- App 按「本次安装」记录领养完成状态（重装后重新走领养，日常启动进控制台）

### 改进
- **守护进程**：登录/启动（RunAtLoad）时按当前阶段进入风睡前、锁屏或空闲，白天误触发问题修复
- **守护进程**：跨午夜场景下分别校验风睡前与锁屏的「生效星期」
- **守护进程**：风睡前通知显示真实剩余分钟数
- **CLI**：修改起床时间（`zzz config wakeup`）后自动刷新 launchd 任务
- **锁屏**：动画播放与呼吸循环稳定性、布局微调
- **App**：星期切换支持英文缩写与紧凑布局
- **发布**：DMG 安装窗口图标位置与尺寸调整

### 移除
- 锁屏界面 ESC 连按提示文案（`lock.esc_hint`）

### 文档
- README 增加产品演示 GIF
- README 下载链接更新至 v1.1.0

---

## [v1.0.0](https://github.com/znygithub/cat-bedtime/releases/tag/v1.0.0) — 2026-05-19

首个公开发布。

### 新增
- macOS 睡前全屏锁屏（透明猫猫动画，多显示器）
- 风睡前提醒、亮度/音量渐降
- App 版（图形界面领养）与 CLI 版（`zzz` 命令），共用 `~/.timetosleep/` 配置
- 中文简体、繁体、英文、日文、韩文界面
- App 与 CLI 分离发布包（`Cat-Bedtime-macOS.dmg`、`cat-bedtime-cli-macos.tar.gz`）

### 文档
- README 产品说明与设计思路
- `ARCHITECTURE.md` 架构说明

---

[Unreleased]: https://github.com/znygithub/cat-bedtime/compare/v1.1.0...main
