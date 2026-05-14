# 猫猫关灯锁屏动画实践记录

本文记录这轮「猫猫走出来、拉灯绳、屏幕熄灭、上床睡觉」锁屏动画实验里的技术经验。目标不是定稿方案，而是把已经踩过的坑和可复用的判断方法同时留在当前实验分支和 `version_funny` worktree 里，方便后续继续做更有趣的版本。

## 目标效果

这轮视觉创意是：

- 小猫从屏幕右下角走出来。
- 它拖着小床或走向床边。
- 它跳起来拉下灯绳。
- 第 4 秒左右模拟关灯，真实桌面淡成黑色。
- 透明猫猫视频继续播放，猫猫上床睡觉。
- 最后再进入锁屏文案状态。

核心思路是：**真实桌面、关灯黑场、锁屏文案由代码控制；猫猫动作由视频素材负责。**

## 当前最推荐的素材格式

最推荐：

```text
Apple ProRes 4444 .mov
1920x1080
24fps 或 30fps
真实 alpha 透明通道
```

可接受：

```text
透明 PNG 序列
cat_000.png, cat_001.png, ...
```

不推荐：

```text
H.264 / MP4 绿幕
白底视频
黑底假透明视频
```

原因：

- 绿幕会产生绿边，尤其猫毛、床边、灯绳这些细节会被颜色污染。
- H.264 / MP4 常见 4:2:0 色度采样会把背景色糊进角色边缘。
- 白底会伤害浅色猫毛、枕头、灯罩等亮部细节。
- 黑底视频如果没有真实 alpha，黑色会作为画面内容一起盖住桌面。

## 关键判断：ProRes 4444 不等于真的透明

这轮发现一个重要坑：文件显示为 `Apple ProRes 4444`、像素格式显示为 `yuva444p12le`，也不一定代表素材真的透明。

需要检查 alpha 通道内容：

```bash
ffprobe -hide_banner -show_streams '/path/to/cat.mov'

ffmpeg -hide_banner -y \
  -ss 2 \
  -i '/path/to/cat.mov' \
  -vf alphaextract \
  -frames:v 1 \
  /tmp/cat-alpha.png
```

正确的 alpha 图应该是：

- 背景区域为黑色。
- 猫、床、道具为白色。
- 边缘有少量灰色抗锯齿。

错误的 alpha 图：

- 整张全白：说明整帧都是不透明，黑底也被写进素材了。
- 整张全黑：说明主体也没有 alpha。
- 灰成一片：说明导出过程可能统一写了半透明，不适合直接叠加。

本轮验证过：

- `/Users/neil_lixiang/Downloads/5月13日(1).mov` 是 ProRes 4444，但 alpha 基本全白，属于假透明。
- `/Users/neil_lixiang/Downloads/5月14日 (2)(1).mov` 的 alpha 图背景黑、主体白，是真透明。

## 为什么绿幕会有边边

绿幕边缘问题不是简单调阈值能完全解决的。主要原因：

- 角色边缘被视频压缩混进绿色。
- 猫毛半透明，天然会吃背景色。
- 绿幕背景如果有阴影、渐变或地面接触阴影，会让 matte 很脏。
- H.264 颜色采样会把绿色扩散到前景像素。

如果必须用绿幕，prompt/导出要求要强调：

```text
solid pure chroma green background #00FF00,
no floor shadow,
no contact shadow,
no ambient green reflection,
no green spill on fur,
high bitrate or lossless export
```

但实践结论是：**能导出真透明 ProRes 4444，就不要走绿幕。**

## 视频尺寸与屏幕尺寸

素材不需要为每台电脑生成不同尺寸。

推荐统一生成：

```text
1920x1080
16:9
24fps 或 30fps
```

代码把素材当作“角色层”，根据当前屏幕尺寸自动缩放和定位。调节参数比重新生成素材更划算：

```bash
--scale 0.80
--x 0.50
--bottom 0.02
```

含义：

- `--scale`：素材层宽度占屏幕宽度的比例。
- `--x`：素材中心点在屏幕宽度中的位置，`0.50` 为居中。
- `--bottom`：素材底部距离屏幕底部的比例。

实践体感：

- `0.56` 偏小，像桌面上的小贴纸。
- `0.72` 比较平衡。
- `0.80` 更像“猫猫是主角”，适合这版趣味锁屏。

## 当前预览命令

透明视频素材：

```bash
cd /Users/neil_lixiang/TimeToSleep
src/overlay/build-cat-video-preview.sh \
  --alpha \
  --video '/Users/neil_lixiang/Downloads/5月14日 (2)(2).mov' \
  --scale 0.80
```

第四秒关灯已经由代码控制。可调：

```bash
--lights-out-at 4.0
--lights-out-duration 0.38
```

例如：

```bash
src/overlay/build-cat-video-preview.sh \
  --alpha \
  --video '/Users/neil_lixiang/Downloads/5月14日 (2)(2).mov' \
  --scale 0.80 \
  --lights-out-at 3.8 \
  --lights-out-duration 0.6
```

黑底假透明素材的临时补救：

```bash
src/overlay/build-cat-video-preview.sh \
  --key black \
  --video '/Users/neil_lixiang/Downloads/5月13日(1).mov' \
  --scale 0.72
```

静态 PNG 绿幕图调比例：

```bash
src/overlay/build-cat-video-preview.sh \
  --image '/Users/neil_lixiang/Downloads/ChatGPT Image 2026年5月13日 23_09_39.png' \
  --scale 0.80
```

## 实现结构

当前实验入口：

```text
/Users/neil_lixiang/TimeToSleep/src/overlay/CatVideoBedtimePreview.swift
/Users/neil_lixiang/TimeToSleep/src/overlay/build-cat-video-preview.sh
```

预览逻辑：

1. 启动时捕获每个屏幕的真实桌面截图。
2. 创建全屏 borderless preview window。
3. 先绘制真实桌面。
4. 如果到达关灯时间，叠加黑色遮罩。
5. 再绘制透明猫猫视频。
6. 底部显示 `ESC` 退出提示。

透明素材模式：

```text
--alpha
```

表示不做绿幕/黑底抠像，直接使用视频自己的 alpha 通道。

## 多显示器经验

外接屏曾出现透明区域下面不是桌面，而是蓝黄渐变 fallback 背景。

原因不是透明失败，而是外接屏截图失败。旧实现用：

```swift
SCScreenshotManager.captureImage(in: screen.frame)
```

在多显示器坐标下容易截不到对应屏幕。

修正思路：

- 从 `NSScreen` 取 `displayID`。
- 用 `SCShareableContent` 找到对应 `SCDisplay`。
- 用 `SCContentFilter(display:excludingWindows:)` 捕获具体 display。

这比直接按矩形截屏更适合多显示器。

## ScreenCaptureKit 崩溃坑

曾出现启动即崩溃，crash report 指向：

```text
SCScreenshotManager captureImageWithFilter:configuration:
SCStream serializeStreamProperties
CGColorSpaceGetModel
```

原因是给 `SCStreamConfiguration.backgroundColor` 赋了一个临时 `NSColor.black.cgColor`。该属性是 `assign` 风格，异步序列化时指针不稳，导致段错误。

解决：

- 不设置 `configuration.backgroundColor`。
- 或者必须设置时，持有一个生命周期稳定的 `CGColor`。

本轮实验直接删除该配置，崩溃消失。

## 关灯效果怎么做

关灯不应该让 AI 视频自己生成整个桌面变暗。更稳的方式是由代码控制：

```swift
let alpha = easeOutQuart(progress(time, start: lightsOutAt, duration: lightsOutDuration))
fillRect(bounds, color: NSColor.black.withAlphaComponent(alpha))
```

这样优点是：

- 能准确在第 4 秒关灯。
- 不依赖视频模型生成屏幕内容。
- 能适配任何电脑、任何桌面、任何显示器。
- 锁屏文案和后续黑场也能继续由代码控制。

## 给 AI 视频模型的导出要求

推荐要求：

```text
Export as Apple ProRes 4444 MOV with real alpha transparency.
Transparent background, no black background, no green background.
The alpha channel must make the background fully transparent and the cat/bed fully opaque.
No text, no watermark, no UI.
1920x1080, 16:9, 30fps, 6 to 8 seconds.
Keep the cat and bed fully inside frame with safe margins.
```

避免：

```text
black background
green screen if transparent alpha is available
white background
H.264 MP4 for final compositing
```

## 当前结论

这条方向技术上可行，而且比“踩屏幕”更柔和、更完整。

最稳组合是：

- 透明 ProRes 4444 视频负责猫猫动作。
- Swift/Cocoa overlay 负责真实桌面截图。
- 代码在第 4 秒淡黑模拟关灯。
- 代码控制最终锁屏文案。
- 素材大小和位置用参数调，而不是反复重新生成。

后续如果要合入真实锁屏流程，应该先把预览参数稳定下来，再把这套合成管线接进正式 `LockScreen.swift`。
