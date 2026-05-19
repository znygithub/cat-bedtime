# Cat Bedtime · 猫猫困了

> 到点了，电脑借给猫猫睡觉。

[English](README_EN.md)

**猫猫困了**（Cat Bedtime）是 macOS 上的睡前锁屏工具：你设定猫猫每天几点来、几点走；到点后它会占住屏幕睡觉，提醒你也该睡觉了

---

## 为什么做这个

深夜最难的不是「不知道要睡」，而是很难让自己**主动远离电子产品**：再看一个帖子、再刷一会视频、再给 AI 提一个需求，不知不觉就压缩了自己的睡眠时间，没有保障自己第二天的精力

**猫猫困了**（Cat Bedtime）换了一个更好接受的约束——**不是系统在罚你，而是一只猫真的来你屏幕上睡觉**。看到可爱的猫猫也困了，你也会更愿意把电脑让出来，把时间还给自己

---

## 一些思考

### 用「领养」而不是「设置锁屏」

第一次使用走的是**领养流程**：你填猫猫几点睡、几点走、每周哪几天来，还要签一句「我愿意让猫猫好好休息」。这是在建立一种小小的承诺，我会觉得这比冷冰冰的「启用屏幕锁定」更容易坚持

### 温柔地靠近，再坚决地锁住

到睡前会先**打哈欠、发通知**——给你几分钟收尾，而不是突然黑屏。等真正到点，猫猫才登场接管屏幕。

### 锁屏动画的三幕

制作了一段猫猫睡觉动画，希望能更有趣的实现锁屏效果：

| 画面 | 含义 |
| --- | --- |
| **猫猫拖着床来了** | 到点了，该睡了——它带着床住进了你的屏幕|
| **猫猫拉绳子关灯** | 灯灭了，**锁屏开始**——从现在起这台电脑是猫猫的 |
| **猫猫躺下睡觉** | 猫猫要好好休息；**你也该休息了，别再碰电脑** |

动画播完后，猫猫会一直睡在屏幕上，直到你设定的起床时间。

### 可以请假，但要说明原因

`zzz tonight off` 或 App 里的「晚点再来」——你可以推迟时间，但是需要你跟它说一声为什么今晚例外。

---

## 下载安装（二选一）

在 **[GitHub Releases](https://github.com/znygithub/cat-bedtime/releases)** 下载最新版（需 macOS 12+）。

| 我想要 | 下载文件 | 适合谁 |
| --- | --- | --- |
| **图形界面 App** | `Cat-Bedtime-macOS.dmg` | 不想用终端，拖进「应用程序」即可 |
| **命令行 CLI** | `cat-bedtime-cli-macos.tar.gz` | 习惯用 `zzz` 命令管理日程 |

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

**系统要求**：macOS；CLI 版需要系统自带 `python3`。

App 与 CLI **共用** `~/.timetosleep/` 配置目录（兼容早期安装名）。请**只选一种**日常使用；若两版都装过，**最后一次**完成领养的版本会注册定时任务。

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

## 许可

[MIT](LICENSE)
