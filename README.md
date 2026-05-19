# Cat Bedtime · 猫猫困了

> 到点了，电脑借给猫猫睡觉。

[English](README_EN.md)

**猫猫困了**（Cat Bedtime）是 macOS 上的睡前锁屏工具：你设定猫猫每天几点来、几点走；到点后它会占住屏幕睡觉，提醒你真的该离开电脑了。

---

## 为什么做这个

- 深夜还想「再看一眼」——关机会有负罪感，但猫猫要睡觉就自然多了
- 需要**到点真的锁得住**（全屏、多显示器、进程被杀也会拉起）
- 想要**温柔提醒**（通知、降亮度/音量），而不是突然黑屏

更完整的产品说明见 [PRODUCT_GOALS.md](PRODUCT_GOALS.md)。

---

## 下载安装（二选一）

在 **[GitHub Releases](https://github.com/znygithub/cat-bedtime/releases)** 下载最新版（需 macOS 12+）。

| 我想要 | 下载文件 | 适合谁 |
| --- | --- | --- |
| **图形界面 App** | `Cat-Bedtime-macOS.dmg` | 不想用终端，拖进「应用程序」即可 |
| **命令行 CLI** | `cat-bedtime-cli-macos.tar.gz` | 习惯用 `zzz` 命令管理日程 |

> 若 Releases 里还没有附件，说明尚未发布；可暂时用下方「从源码安装」，或联系维护者。

### App 版（推荐大多数用户）

1. 下载并打开 `Cat-Bedtime-macOS.dmg`
2. 将 **Cat Bedtime.app** 拖到 **应用程序**
3. 首次打开，按引导完成「猫猫领养」（睡觉时间、起床时间、每周哪几天来）
4. 若系统提示无法打开：系统设置 → 隐私与安全性 → 仍要打开

### CLI 版

1. 下载并解压 `cat-bedtime-cli-macos.tar.gz`
2. 在终端执行：

```bash
cd cat-bedtime-cli
bash install.sh
```

3. 安装脚本会自动打开终端并运行 `zzz init`，按提示完成领养
4. 之后用 `zzz` 查看今晚状态

**系统要求**：macOS；CLI 版需要系统自带 `python3`。无需 Xcode。

App 与 CLI **共用** `~/.timetosleep/` 配置目录（兼容早期安装名）。请**只选一种**日常使用；若两版都装过，**最后一次**完成领养的版本会注册定时任务。

---

## 它做什么

- **猫猫领养**：设置睡觉/起床时间、每周来住的日子、提前多久提醒
- **睡前提醒**：通知、逐步降低亮度与音量
- **强制锁屏**：到点全屏覆盖、暂停媒体；覆盖层异常退出会重新拉起
- **到点恢复**：起床时间后解锁，恢复亮度与音量
- **请假**：`zzz tonight off` 或 App 内「晚点再来」（需说明原因）

---

## 常用命令（CLI 版）

```bash
zzz                         # 今晚猫猫状态
zzz init                    # 领养 / 重新设置
zzz status                  # 到访记录
zzz config                  # 查看日程
zzz config bedtime 23:30    # 改睡觉时间
zzz config wakeup 07:30     # 改起床时间
zzz tonight off             # 今晚不来
zzz test 10                 # 测试锁屏 10 秒
zzz uninstall               # 卸载
```

---

## 从源码安装（开发者）

```bash
git clone https://github.com/znygithub/cat-bedtime.git
cd cat-bedtime
bash install.sh          # CLI
# 或
bash src/app/build.sh    # 本地编译 App → bin/Cat Bedtime.app
```

锁屏猫猫动画素材 `assets/cat-bedtime.mov` 体积较大，发布包内已包含；纯源码克隆若缺少该文件，锁屏会提示缺少素材。

---

## 文档

| 文档 | 说明 |
| --- | --- |
| [PRODUCT_GOALS.md](PRODUCT_GOALS.md) | 产品定位与体验原则 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 架构与模块 |
| [RELEASE.md](RELEASE.md) | 维护者：打包、签名、公证 |
| [PITFALLS.md](PITFALLS.md) | 历史踩坑与回归注意 |

---

## 许可

[MIT](LICENSE)
