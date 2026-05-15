import AVFoundation
import Cocoa
import CoreImage
import QuartzCore
import ScreenCaptureKit

private let previewHint = "按 ESC 退出预览"

private func clamp(_ value: Double, _ lower: Double = 0.0, _ upper: Double = 1.0) -> Double {
    min(max(value, lower), upper)
}

private func easeOutQuart(_ value: Double) -> Double {
    1.0 - pow(1.0 - clamp(value), 4.0)
}

private func progress(_ time: Double, start: Double, duration: Double) -> Double {
    guard duration > 0 else { return time >= start ? 1 : 0 }
    return clamp((time - start) / duration)
}

private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    let x = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return x * x * (3 - 2 * x)
}

private final class VideoFrameSource {
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private var lastPixelBuffer: CVPixelBuffer?

    let url: URL

    init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
    }

    func play() {
        player.playImmediately(atRate: 1.0)
    }

    var currentTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    func currentPixelBuffer() -> CVPixelBuffer? {
        let itemTime = player.currentTime()
        if let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            lastPixelBuffer = pixelBuffer
            return pixelBuffer
        }
        return lastPixelBuffer
    }
}

private final class ChromaKeyRenderer {
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpaceCreateDeviceRGB(),
    ])
    private let cubeDimension = 64
    private lazy var chromaCubeData: Data = makeChromaCubeData(size: cubeDimension)
    private lazy var blackCubeData: Data = makeBlackCubeData(size: cubeDimension)

    func rawImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return context.createCGImage(image, from: image.extent)
    }

    func keyedImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return keyedImage(from: image)
    }

    func blackKeyedImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return applyColorCube(to: image, data: blackCubeData)
    }

    func keyedImage(from image: NSImage) -> CGImage? {
        guard let ciImage = ciImage(from: image) else { return nil }
        return keyedImage(from: ciImage)
    }

    private func keyedImage(from image: CIImage) -> CGImage? {
        applyColorCube(to: image, data: chromaCubeData)
    }

    private func applyColorCube(to image: CIImage, data: Data) -> CGImage? {
        guard let filter = CIFilter(name: "CIColorCube") else {
            return context.createCGImage(image, from: image.extent)
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(cubeDimension, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        guard let output = filter.outputImage else {
            return context.createCGImage(image, from: image.extent)
        }
        return context.createCGImage(output, from: image.extent)
    }

    private func ciImage(from image: NSImage) -> CIImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        return CIImage(cgImage: cgImage)
    }

    private func makeChromaCubeData(size: Int) -> Data {
        var cube = [Float]()
        cube.reserveCapacity(size * size * size * 4)

        for blueIndex in 0..<size {
            let blue = Float(blueIndex) / Float(size - 1)
            for greenIndex in 0..<size {
                let green = Float(greenIndex) / Float(size - 1)
                for redIndex in 0..<size {
                    let red = Float(redIndex) / Float(size - 1)
                    let maxRedBlue = max(red, blue)
                    let minRedBlue = min(red, blue)
                    let distanceToPureGreen = sqrt(red * red + (green - 1.0) * (green - 1.0) + blue * blue)
                    let greenDominance = green - maxRedBlue
                    let relativeDominance = greenDominance / max(green, 0.001)

                    let pureGreenKey = 1.0 - smoothstep(0.08, 0.24, distanceToPureGreen)
                    let screenGreenKey = smoothstep(0.045, 0.18, greenDominance)
                        * smoothstep(0.12, 0.34, relativeDominance)
                        * smoothstep(0.13, 0.28, green)
                    let shadowGreenKey = smoothstep(0.025, 0.12, greenDominance)
                        * smoothstep(0.10, 0.26, relativeDominance)
                        * smoothstep(0.08, 0.22, green)
                    let keyStrength = min(max(pureGreenKey, max(screenGreenKey, shadowGreenKey)), 1.0)
                    var alpha = 1.0 - keyStrength

                    // Harden the matte for this compressed test video. The generated source has green
                    // shadows and block artifacts, so a very soft alpha leaves gray/green boxes behind.
                    if alpha < 0.24 {
                        alpha = 0.0
                    } else if alpha > 0.66 {
                        alpha = 1.0
                    } else {
                        alpha = smoothstep(0.24, 0.66, alpha)
                    }

                    let outRed = red
                    var outGreen = green
                    let outBlue = blue
                    let spill = smoothstep(0.0, 0.18, greenDominance)
                        * smoothstep(0.08, 0.24, relativeDominance)
                        * smoothstep(0.10, 0.28, green)
                    let neutralGreen = maxRedBlue * 0.72 + minRedBlue * 0.18 + 0.04
                    outGreen = min(outGreen, green + (neutralGreen - green) * spill)

                    cube.append(outRed)
                    cube.append(outGreen)
                    cube.append(outBlue)
                    cube.append(alpha)
                }
            }
        }

        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func makeBlackCubeData(size: Int) -> Data {
        var cube = [Float]()
        cube.reserveCapacity(size * size * size * 4)

        for blueIndex in 0..<size {
            let blue = Float(blueIndex) / Float(size - 1)
            for greenIndex in 0..<size {
                let green = Float(greenIndex) / Float(size - 1)
                for redIndex in 0..<size {
                    let red = Float(redIndex) / Float(size - 1)
                    let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
                    var alpha = smoothstep(0.060, 0.135, luminance)

                    if alpha < 0.08 {
                        alpha = 0.0
                    } else if alpha > 0.74 {
                        alpha = 1.0
                    } else {
                        alpha = smoothstep(0.08, 0.74, alpha)
                    }

                    cube.append(red)
                    cube.append(green)
                    cube.append(blue)
                    cube.append(alpha)
                }
            }
        }

        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

private final class CatVideoBedtimePreviewView: NSView {
    private let desktopImage: NSImage?
    private let video: VideoFrameSource?
    private let usesStaticImage: Bool
    private let usesAlphaVideo: Bool
    private let usesBlackKeyVideo: Bool
    private let assetScale: CGFloat
    private let assetCenterX: CGFloat
    private let assetBottom: CGFloat
    private let lightsOutAt: Double
    private let lightsOutDuration: Double
    private let renderer = ChromaKeyRenderer()
    private var displayTimer: Timer?
    private var lastRawImage: CGImage?
    private var lastKeyedImage: CGImage?
    private var staticKeyedImage: CGImage?

    init(
        frame frameRect: NSRect,
        desktopImage: NSImage?,
        imageURL: URL?,
        videoURL: URL?,
        usesAlphaVideo: Bool,
        usesBlackKeyVideo: Bool,
        assetScale: CGFloat,
        assetCenterX: CGFloat,
        assetBottom: CGFloat,
        lightsOutAt: Double,
        lightsOutDuration: Double
    ) {
        let imageMode = imageURL != nil
        self.desktopImage = desktopImage
        self.video = imageMode ? nil : videoURL.map(VideoFrameSource.init(url:))
        self.usesStaticImage = imageMode
        self.usesAlphaVideo = usesAlphaVideo
        self.usesBlackKeyVideo = usesBlackKeyVideo
        self.assetScale = assetScale
        self.assetCenterX = assetCenterX
        self.assetBottom = assetBottom
        self.lightsOutAt = lightsOutAt
        self.lightsOutDuration = lightsOutDuration
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            staticKeyedImage = renderer.keyedImage(from: image)
        }
        startDisplayTimer()
        video?.play()
    }

    required init?(coder: NSCoder) {
        fatalError("CatVideoBedtimePreview does not support Interface Builder.")
    }

    deinit {
        displayTimer?.invalidate()
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            NSApp.terminate(nil)
            return
        }
        super.keyDown(with: event)
    }

    private func startDisplayTimer() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if usesStaticImage {
            drawDesktop()
            if let staticKeyedImage {
                draw(cgImage: staticKeyedImage, alpha: 1.0)
            } else {
                drawMissingAssetCard("没有读到 PNG 素材")
            }
            drawPreviewHint(alpha: 0.28)
            return
        }

        if usesAlphaVideo {
            let videoTime = video?.currentTime ?? 0
            drawDesktop()
            drawLightsOutOverlay(time: videoTime)
            drawAlphaVideo(alpha: 1.0)
            // After lights go dark, fade in the lock screen text
            let textAlpha = easeOutQuart(progress(videoTime, start: lightsOutAt + lightsOutDuration + 1.0, duration: 1.2))
            drawLockText(alpha: CGFloat(textAlpha))
            drawPreviewHint(alpha: 0.28)
            return
        }

        let videoTime = video?.currentTime ?? 0
        let blackout = easeOutQuart(progress(videoTime, start: 5.72, duration: 0.46))
        let finalText = easeOutQuart(progress(videoTime, start: 8.72, duration: 0.70))

        drawDesktop()
        if usesBlackKeyVideo {
            drawBlackKeyedVideo(alpha: CGFloat(1.0 - blackout))
        } else {
            drawKeyedVideo(alpha: CGFloat(1.0 - blackout))
        }
        fillRect(bounds, color: NSColor.black.withAlphaComponent(CGFloat(blackout)))
        drawRawNightVideo(alpha: CGFloat(blackout))
        drawLockText(alpha: CGFloat(finalText))
        drawPreviewHint(alpha: 0.28)
    }

    private func drawDesktop() {
        if let desktopImage {
            desktopImage.draw(in: bounds,
                              from: NSRect(origin: .zero, size: desktopImage.size),
                              operation: .sourceOver,
                              fraction: 1.0,
                              respectFlipped: true,
                              hints: [.interpolation: NSImageInterpolation.high])
            fillRect(bounds, color: NSColor.black.withAlphaComponent(0.10))
            return
        }

        let fallback = NSGradient(colors: [
            NSColor(srgbRed: 0.16, green: 0.22, blue: 0.30, alpha: 1),
            NSColor(srgbRed: 0.34, green: 0.48, blue: 0.56, alpha: 1),
            NSColor(srgbRed: 0.78, green: 0.62, blue: 0.39, alpha: 1),
        ])!
        fallback.draw(in: bounds, angle: 24)
    }

    private func drawLightsOutOverlay(time: Double) {
        guard lightsOutAt >= 0 else { return }
        let alpha = CGFloat(easeOutQuart(progress(time, start: lightsOutAt, duration: lightsOutDuration)))
        guard alpha > 0.01 else { return }
        fillRect(bounds, color: NSColor.black.withAlphaComponent(alpha))
    }

    private func drawKeyedVideo(alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        guard let pixelBuffer = video?.currentPixelBuffer() else {
            drawMissingAssetCard("没有读到视频帧")
            return
        }
        if let keyed = renderer.keyedImage(from: pixelBuffer) {
            lastKeyedImage = keyed
        }
        guard let image = lastKeyedImage else { return }
        draw(cgImage: image, alpha: alpha)
    }

    private func drawBlackKeyedVideo(alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        guard let pixelBuffer = video?.currentPixelBuffer() else { return }
        if let keyed = renderer.blackKeyedImage(from: pixelBuffer) {
            lastKeyedImage = keyed
        }
        guard let image = lastKeyedImage else { return }
        draw(cgImage: image, alpha: alpha)
    }

    private func drawAlphaVideo(alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        guard let pixelBuffer = video?.currentPixelBuffer() else { return }
        if let raw = renderer.rawImage(from: pixelBuffer) {
            lastRawImage = raw
        }
        guard let image = lastRawImage else { return }
        draw(cgImage: image, alpha: alpha)
    }

    private func drawRawNightVideo(alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        guard let pixelBuffer = video?.currentPixelBuffer() else { return }
        if let raw = renderer.rawImage(from: pixelBuffer) {
            lastRawImage = raw
        }
        guard let image = lastRawImage else { return }
        draw(cgImage: image, alpha: alpha)
    }

    private func draw(cgImage: CGImage, alpha: CGFloat) {
        let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
        let target = assetRect(for: imageSize)
        let image = NSImage(cgImage: cgImage, size: imageSize)
        image.draw(in: target,
                   from: NSRect(origin: .zero, size: imageSize),
                   operation: .sourceOver,
                   fraction: alpha,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }

    private func assetRect(for imageSize: NSSize) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let targetWidth = bounds.width * min(max(assetScale, 0.12), 1.20)
        let targetHeight = targetWidth * imageSize.height / imageSize.width
        let centerX = bounds.minX + bounds.width * min(max(assetCenterX, -0.20), 1.20)
        let y = bounds.minY + bounds.height * min(max(assetBottom, -0.25), 0.80)
        return NSRect(x: centerX - targetWidth / 2,
                      y: y,
                      width: targetWidth,
                      height: targetHeight)
    }

    private func drawMissingAssetCard(_ message: String) {
        let card = NSRect(x: bounds.midX - 210, y: bounds.midY - 44, width: 420, height: 88)
        fillRounded(card, radius: 12, color: NSColor.black.withAlphaComponent(0.62))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86),
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: message, attributes: attrs)
            .draw(in: card.insetBy(dx: 18, dy: 30))
    }

    private func drawLockText(alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        let leftPS = NSMutableParagraphStyle()
        leftPS.alignment = .left

        let margin: CGFloat = bounds.width * 0.05
        let textWidth: CGFloat = bounds.width * 0.5

        // ── Clock (top-left, large) ──
        let fontSize: CGFloat = min(108, bounds.width * 0.115)
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .thin),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.88 * alpha),
            .paragraphStyle: leftPS,
        ]
        let clockY = bounds.height * 0.82
        NSAttributedString(string: currentTimeString(), attributes: timeAttrs)
            .draw(in: NSRect(x: margin, y: clockY, width: textWidth, height: fontSize * 1.3))

        // ── Quote ──
        let quoteAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.65 * alpha),
            .kern: 2.0,
            .paragraphStyle: leftPS,
        ]
        NSAttributedString(string: "嘘🤫，猫猫睡了，安静", attributes: quoteAttrs)
            .draw(in: NSRect(x: margin, y: clockY - 40, width: textWidth, height: 36))

        // ── Wakeup info ──
        let configPath = NSHomeDirectory() + "/.timetosleep/config.json"
        var wakeupStr = "07:00"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let w = json["wakeup"] as? String { wakeupStr = w }
        let wakeHour = Int(wakeupStr.split(separator: ":").first ?? "7") ?? 7

        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .light),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.38 * alpha),
            .kern: 1.5,
            .paragraphStyle: leftPS,
        ]
        NSAttributedString(string: "猫猫\(wakeHour)点起床", attributes: infoAttrs)
            .draw(in: NSRect(x: margin, y: clockY - 72, width: textWidth, height: 28))
    }

    private func drawPreviewHint(alpha: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: previewHint, attributes: attrs)
            .draw(in: NSRect(x: bounds.minX, y: bounds.minY + 26, width: bounds.width, height: 22))
    }

    private func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

private final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct ScreenTarget {
    let screen: NSScreen
    let frame: NSRect
}

private final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [PreviewWindow] = []
    var windowed = false
    var autoQuitDelay: TimeInterval?
    var imageURL: URL?
    var videoURL: URL?
    var usesAlphaVideo = false
    var usesBlackKeyVideo = false
    var assetScale: CGFloat = 0.72
    var assetCenterX: CGFloat = 0.50
    var assetBottom: CGFloat = 0.02
    var lightsOutAt: Double = 4.0
    var lightsOutDuration: Double = 0.38

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        guard let screen = NSScreen.main else { return }

        let targets: [ScreenTarget]
        let style: NSWindow.StyleMask
        if windowed {
            let width = min(screen.visibleFrame.width * 0.84, 1180)
            let height = min(screen.visibleFrame.height * 0.82, 760)
            let frame = NSRect(x: screen.visibleFrame.midX - width / 2,
                               y: screen.visibleFrame.midY - height / 2,
                               width: width,
                               height: height)
            targets = [ScreenTarget(screen: screen, frame: frame)]
            style = [.titled, .closable, .miniaturizable]
        } else {
            targets = NSScreen.screens.map { ScreenTarget(screen: $0, frame: $0.frame) }
            style = [.borderless]
        }

        captureDesktopSnapshots(for: targets) { [weak self] snapshots in
            self?.showPreviewWindows(targets: targets, style: style, snapshots: snapshots)
        }
    }

    private func showPreviewWindows(targets: [ScreenTarget], style: NSWindow.StyleMask, snapshots: [NSImage?]) {
        for (index, target) in targets.enumerated() {
            let previewWindow = PreviewWindow(contentRect: target.frame, styleMask: style, backing: .buffered, defer: false)
            previewWindow.title = "Cat Bedtime Video Preview"
            previewWindow.isOpaque = true
            previewWindow.backgroundColor = .black
            previewWindow.level = windowed ? .normal : .screenSaver
            previewWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            previewWindow.isReleasedWhenClosed = false
            previewWindow.hidesOnDeactivate = false
            previewWindow.canHide = false

            let localFrame = NSRect(origin: .zero, size: target.frame.size)
            let view = CatVideoBedtimePreviewView(frame: localFrame,
                                                  desktopImage: snapshots[index],
                                                  imageURL: imageURL,
                                                  videoURL: videoURL,
                                                  usesAlphaVideo: usesAlphaVideo,
                                                  usesBlackKeyVideo: usesBlackKeyVideo,
                                                  assetScale: assetScale,
                                                  assetCenterX: assetCenterX,
                                                  assetBottom: assetBottom,
                                                  lightsOutAt: lightsOutAt,
                                                  lightsOutDuration: lightsOutDuration)
            view.autoresizingMask = [.width, .height]
            previewWindow.contentView = view
            previewWindow.makeKeyAndOrderFront(nil)
            previewWindow.makeFirstResponder(view)
            windows.append(previewWindow)
        }
        NSApp.activate(ignoringOtherApps: true)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }

        if let autoQuitDelay {
            Timer.scheduledTimer(withTimeInterval: autoQuitDelay, repeats: false) { _ in
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private func captureDesktopSnapshots(for targets: [ScreenTarget], completion: @escaping ([NSImage?]) -> Void) {
    guard !targets.isEmpty else {
        completion([])
        return
    }

    var snapshots = Array<NSImage?>(repeating: nil, count: targets.count)
    let group = DispatchGroup()

    for (index, target) in targets.enumerated() {
        group.enter()
        desktopSnapshot(for: target.screen, displaySize: target.frame.size) { image in
            snapshots[index] = image
            group.leave()
        }
    }

    group.notify(queue: .main) {
        completion(snapshots)
    }
}

private func desktopSnapshot(for screen: NSScreen, displaySize: NSSize, completion: @escaping (NSImage?) -> Void) {
    guard let displayID = screenDisplayID(screen) else {
        fallbackDesktopSnapshot(for: screen, displaySize: displaySize, completion: completion)
        return
    }

    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
        guard let display = content?.displays.first(where: { $0.displayID == displayID }) else {
            fallbackDesktopSnapshot(for: screen, displaySize: displaySize, completion: completion)
            return
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let configuration = SCStreamConfiguration()
        let scale = max(screen.backingScaleFactor, 1.0)
        configuration.width = max(1, Int(displaySize.width * scale))
        configuration.height = max(1, Int(displaySize.height * scale))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false

        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { cgImage, _ in
            guard let cgImage else {
                fallbackDesktopSnapshot(for: screen, displaySize: displaySize, completion: completion)
                return
            }

            let image = NSImage(cgImage: cgImage, size: displaySize)
            DispatchQueue.main.async { completion(image) }
        }
    }
}

private func fallbackDesktopSnapshot(for screen: NSScreen, displaySize: NSSize, completion: @escaping (NSImage?) -> Void) {
    if #available(macOS 15.2, *) {
        SCScreenshotManager.captureImage(in: screen.frame) { cgImage, _ in
            guard let cgImage else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let image = NSImage(cgImage: cgImage, size: displaySize)
            DispatchQueue.main.async { completion(image) }
        }
    } else {
        DispatchQueue.main.async { completion(nil) }
    }
}

private func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let number = screen.deviceDescription[key] as? NSNumber else {
        return nil
    }
    return CGDirectDisplayID(number.uint32Value)
}

private func aspectFitRect(_ size: NSSize, in rect: NSRect) -> NSRect {
    guard size.width > 0, size.height > 0 else { return rect }
    let scale = min(rect.width / size.width, rect.height / size.height)
    let width = size.width * scale
    let height = size.height * scale
    return NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
}

private func fillRect(_ rect: NSRect, color: NSColor) {
    color.setFill()
    rect.fill()
}

private func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

private func commandLineDoubleValue(after flag: String) -> Double? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.indices.contains(index + 1) else {
        return nil
    }
    return Double(CommandLine.arguments[index + 1])
}

private func commandLineStringValue(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.indices.contains(index + 1) else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

private func commandLineCGFloatValue(after flag: String) -> CGFloat? {
    commandLineDoubleValue(after: flag).map { CGFloat($0) }
}

private func defaultVideoURL() -> URL? {
    return nil
}

private let app = NSApplication.shared
private let delegate = PreviewAppDelegate()
delegate.windowed = CommandLine.arguments.contains("--windowed")
delegate.autoQuitDelay = commandLineDoubleValue(after: "--auto-quit")
delegate.imageURL = commandLineStringValue(after: "--image").map { URL(fileURLWithPath: $0) }
delegate.videoURL = commandLineStringValue(after: "--video").map { URL(fileURLWithPath: $0) } ?? defaultVideoURL()
delegate.usesAlphaVideo = CommandLine.arguments.contains("--alpha")
delegate.usesBlackKeyVideo = CommandLine.arguments.contains("--black-key")
    || commandLineStringValue(after: "--key")?.lowercased() == "black"
delegate.assetScale = commandLineCGFloatValue(after: "--scale") ?? delegate.assetScale
delegate.assetCenterX = commandLineCGFloatValue(after: "--x") ?? delegate.assetCenterX
delegate.assetBottom = commandLineCGFloatValue(after: "--bottom") ?? delegate.assetBottom
delegate.lightsOutAt = commandLineDoubleValue(after: "--lights-out-at") ?? delegate.lightsOutAt
delegate.lightsOutDuration = commandLineDoubleValue(after: "--lights-out-duration") ?? delegate.lightsOutDuration
app.delegate = delegate
app.run()
