import AVFoundation
import Cocoa
import CoreText
import QuartzCore

// MARK: - Helpers

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

private func fillRect(_ rect: NSRect, color: NSColor) {
    color.setFill()
    rect.fill()
}

private func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

// MARK: - Config

struct SleepConfig {
    let wakeupTime: String
    let bedtime: String
    let activeDays: Set<Int>

    static func load() -> SleepConfig {
        let configPath = NSHomeDirectory() + "/.timetosleep/config.json"
        var wakeup = "07:00"
        var bedtime = "23:00"
        var days: Set<Int> = [1, 2, 3, 4, 5]

        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let w = json["wakeup"] as? String { wakeup = w }
            if let b = json["bedtime"] as? String { bedtime = b }
            if let d = json["days"] as? [Any] {
                days = Set(d.compactMap { item -> Int? in
                    if let s = item as? String { return Int(s) }
                    if let n = item as? Int { return n }
                    return nil
                })
            }
        }

        let postponePath = NSHomeDirectory() + "/.timetosleep/postpone_tonight"
        if let content = try? String(contentsOf: URL(fileURLWithPath: postponePath), encoding: .utf8) {
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count >= 2 {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                let today = fmt.string(from: Date())
                if lines[0] == today, !lines[1].isEmpty {
                    bedtime = lines[1]
                }
            }
        }

        return SleepConfig(wakeupTime: wakeup, bedtime: bedtime, activeDays: days)
    }
}

// MARK: - Lock window math (aligned with daemon)

enum LockWindowMath {
    static func parseHHMM(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    static func isInLockdownWindow(config: SleepConfig, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let bedMin = parseHHMM(config.bedtime) ?? 1380
        let wakeMin = parseHHMM(config.wakeupTime) ?? 420
        if bedMin > wakeMin {
            return nowMin >= bedMin || nowMin < wakeMin
        }
        return nowMin >= bedMin && nowMin < wakeMin
    }

    static func isoWeekday(for date: Date) -> Int {
        let cal = Calendar.current
        let w = cal.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }

    static func activeWeekdayForLockWindow(config: SleepConfig, now: Date = Date()) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let bedMin = parseHHMM(config.bedtime) ?? 1380
        let wakeMin = parseHHMM(config.wakeupTime) ?? 420
        if bedMin > wakeMin && nowMin < wakeMin,
           let previousDay = cal.date(byAdding: .day, value: -1, to: now) {
            return isoWeekday(for: previousDay)
        }
        return isoWeekday(for: now)
    }

    static func canEmergencyExit(config: SleepConfig, now: Date = Date()) -> Bool {
        if !isInLockdownWindow(config: config, now: now) { return true }
        if !config.activeDays.contains(activeWeekdayForLockWindow(config: config, now: now)) { return true }
        return false
    }

    static func minutesUntilWakeup(config: SleepConfig, now: Date = Date()) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let wakeMin = parseHHMM(config.wakeupTime) ?? 420
        var diff = wakeMin - nowMin
        if diff <= 0 { diff += 1440 }
        return diff
    }
}

// MARK: - Cat video playback

/// Breathing loop: intro plays forward once, then ping-pong [loopStart … end] until unlock.
enum CatVideoPlayback {
    /// 12分20秒 on the source timeline → 0:12.20 for this clip.
    static let breathingLoopStart: Double = 12.20
    static let endEpsilon: Double = 0.04
    static let boundaryEpsilon: Double = 0.06
}

// MARK: - Cat video asset

enum CatAnimationAsset {
    static func locate() -> URL? {
        let home = NSHomeDirectory()
        let executablePath = CommandLine.arguments[0] as NSString
        let resourcesPath = executablePath.deletingLastPathComponent + "/.."
        let candidates = [
            (resourcesPath as NSString).appendingPathComponent("assets/cat-bedtime.mov"),
            (resourcesPath as NSString).appendingPathComponent("assets/cat-bedtime.mp4"),
            "\(home)/.timetosleep/assets/cat-bedtime.mov",
            "\(home)/.timetosleep/assets/cat-bedtime.mp4",
        ]

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}

private final class VideoFrameSource {
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private let durationSeconds: Double?
    private let loopStart: Double
    private let loopEnd: Double
    private var lastPixelBuffer: CVPixelBuffer?
    private var breathingMode = false
    private var playingForward = true
    private var timeObserver: Any?

    init(url: URL) {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        durationSeconds = duration.isFinite && duration > 0 ? duration : nil

        let rawDuration = durationSeconds ?? 0
        let configuredStart = CatVideoPlayback.breathingLoopStart
        loopStart = min(max(0, configuredStart), max(0, rawDuration - 0.15))
        loopEnd = max(loopStart + 0.10, rawDuration - CatVideoPlayback.endEpsilon)

        let item = AVPlayerItem(asset: asset)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.playImmediately(atRate: 1.0)
        installBreathingLoopObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    var duration: Double? {
        durationSeconds
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

    private func installBreathingLoopObserver() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateBreathingLoop(at: time.seconds)
        }
    }

    private func updateBreathingLoop(at rawTime: Double) {
        guard rawTime.isFinite else { return }
        let epsilon = CatVideoPlayback.boundaryEpsilon

        if !breathingMode {
            if rawTime >= loopStart - epsilon {
                breathingMode = true
                playingForward = true
                if rawTime >= loopEnd - epsilon {
                    playingForward = false
                    seekToLoopBoundary(loopEnd, rate: -1.0)
                }
            }
            return
        }

        if playingForward {
            if rawTime >= loopEnd - epsilon {
                playingForward = false
                seekToLoopBoundary(loopEnd, rate: -1.0)
            }
        } else if rawTime <= loopStart + epsilon {
            playingForward = true
            seekToLoopBoundary(loopStart, rate: 1.0)
        }
    }

    private func seekToLoopBoundary(_ seconds: Double, rate: Float) {
        let clamped = min(max(seconds, loopStart), loopEnd)
        player.pause()
        player.seek(to: mediaTime(clamped), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished else { return }
            self.player.playImmediately(atRate: rate)
        }
    }

    private func mediaTime(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}

private final class VideoRenderer {
    func alphaImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        let data = Data(bytes: baseAddress, count: bytesPerRow * height)

        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow,
                       space: colorSpace,
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}

private final class LockAnimationTimeline {
    static let shared = LockAnimationTimeline()

    private let startedAt = CACurrentMediaTime()

    var elapsed: Double {
        max(0, CACurrentMediaTime() - startedAt)
    }

    /// Wall-clock time for lock UI overlays (lights out, text fade-in).
    func uiTime() -> Double {
        elapsed
    }
}

// MARK: - Lock Window Controller

class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class LockWindowController {
    let config: SleepConfig
    var windows: [NSWindow] = []
    var clockTimer: Timer?
    private var previousInLockdown: Bool?

    init(config: SleepConfig) {
        self.config = config
    }

    func activate() {
        for screen in NSScreen.screens {
            windows.append(createLockWindow(for: screen))
        }
        startClockUpdate()
        setupKeepAlive()
        monitorScreenChanges()
    }

    private func createLockWindow(for screen: NSScreen) -> NSWindow {
        let window = LockWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.ignoresMouseEvents = false
        window.setFrame(screen.frame, display: true)

        let localFrame = NSRect(origin: .zero, size: screen.frame.size)
        window.contentView = CatLockScreenView(frame: localFrame, config: config)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        return window
    }

    private func monitorScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildWindows() }
    }

    private func rebuildWindows() {
        for w in windows { w.close() }
        windows.removeAll()
        for screen in NSScreen.screens { windows.append(createLockWindow(for: screen)) }
    }

    private func startClockUpdate() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkWakeTime()
        }
    }

    private func checkWakeTime() {
        let inLock = LockWindowMath.isInLockdownWindow(config: config, now: Date())
        if let was = previousInLockdown, was, !inLock { exit(0) }
        previousInLockdown = inLock
    }

    private func setupKeepAlive() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let screens = NSScreen.screens
            if screens.count != self.windows.count { self.rebuildWindows(); return }
            for (i, w) in self.windows.enumerated() {
                if i < screens.count { w.setFrame(screens[i].frame, display: false) }
                w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
                w.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - Cat lock screen

class CatLockScreenView: NSView {
    let config: SleepConfig
    private let video: VideoFrameSource?
    private let renderer = VideoRenderer()
    private var displayTimer: Timer?
    private var lastFrame: CGImage?

    private let assetScale: CGFloat = 0.99
    private let assetCenterX: CGFloat = 0.50
    private let assetBottom: CGFloat = 0.02
    private let lightsOutAt: Double = 7.0
    private let lightsOutDuration: Double = 0.38

    init(frame: NSRect, config: SleepConfig) {
        self.config = config
        self.video = CatAnimationAsset.locate().map(VideoFrameSource.init(url:))
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        startDisplayTimer()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayTimer?.invalidate()
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            EmergencyExitCoordinator.shared.handleEscapeKey()
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

    private var elapsed: Double {
        LockAnimationTimeline.shared.elapsed
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if video == nil {
            super.draw(dirtyRect)
        } else {
            clearForTransparentWindow()
        }

        let uiTime = LockAnimationTimeline.shared.uiTime()

        if video == nil {
            drawNightBackground()
        }
        drawLightsOutOverlay(time: uiTime)

        if video == nil {
            drawMissingAssetCard()
        } else {
            drawCatVideo()
        }

        let textAlpha = easeOutQuart(progress(uiTime, start: lightsOutAt + lightsOutDuration + 1.0, duration: 1.2))
        drawLockText(alpha: CGFloat(video == nil ? 1.0 : textAlpha))
        drawEmergencyHint()
    }

    private func clearForTransparentWindow() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.copy)
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(bounds)
        context.restoreGState()
    }

    private func drawNightBackground() {
        let fallback = NSGradient(colors: [
            NSColor(srgbRed: 0.10, green: 0.13, blue: 0.19, alpha: 1),
            NSColor(srgbRed: 0.18, green: 0.22, blue: 0.30, alpha: 1),
            NSColor(srgbRed: 0.34, green: 0.30, blue: 0.38, alpha: 1),
        ])!
        fallback.draw(in: bounds, angle: 24)
        fillRect(bounds, color: NSColor.black.withAlphaComponent(0.12))
    }

    private func drawLightsOutOverlay(time: Double) {
        let alpha = CGFloat(easeOutQuart(progress(time, start: lightsOutAt, duration: lightsOutDuration)))
        guard alpha > 0.01 else { return }
        fillRect(bounds, color: NSColor.black.withAlphaComponent(alpha))
    }

    private func drawCatVideo() {
        guard let pixelBuffer = video?.currentPixelBuffer() else { return }
        if let image = renderer.alphaImage(from: pixelBuffer) {
            lastFrame = image
        }
        guard let frame = lastFrame else { return }

        let imageSize = NSSize(width: frame.width, height: frame.height)
        let target = assetRect(for: imageSize)
        let image = NSImage(cgImage: frame, size: imageSize)
        image.draw(in: target,
                   from: NSRect(origin: .zero, size: imageSize),
                   operation: .sourceOver,
                   fraction: 1.0,
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

    private func drawMissingAssetCard() {
        let card = NSRect(x: bounds.midX - 260, y: bounds.midY - 52, width: 520, height: 104)
        fillRounded(card, radius: 10, color: NSColor.black.withAlphaComponent(0.66))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.84),
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(
            string: L10n.t("lock.missing_asset"),
            attributes: attrs
        ).draw(in: card.insetBy(dx: 20, dy: 26))
    }

    private func drawLockText(alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        let leftPS = NSMutableParagraphStyle()
        leftPS.alignment = .left

        let margin: CGFloat = max(36, bounds.width * 0.05)
        let textWidth: CGFloat = min(bounds.width * 0.52, 720)

        let fontSize: CGFloat = min(108, max(68, bounds.width * 0.115))
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .thin),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.88 * alpha),
            .paragraphStyle: leftPS,
        ]
        let clockY = bounds.height * 0.82
        drawVisuallyLeftAligned(
            NSAttributedString(string: currentTimeString(), attributes: timeAttrs),
            x: margin,
            y: clockY,
            width: textWidth,
            height: fontSize * 1.3
        )

        let quoteAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.65 * alpha),
            .kern: 1.4,
            .paragraphStyle: leftPS,
        ]
        drawVisuallyLeftAligned(
            NSAttributedString(string: L10n.t("lock.quote"), attributes: quoteAttrs),
            x: margin,
            y: clockY - 40,
            width: textWidth,
            height: 36
        )

        let mins = LockWindowMath.minutesUntilWakeup(config: config)
        let h = mins / 60
        let m = mins % 60
        let countdown = L10n.countdownUntilWakeup(hours: h, minutes: m)

        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .light),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.38 * alpha),
            .kern: 1.1,
            .paragraphStyle: leftPS,
        ]
        drawVisuallyLeftAligned(
            NSAttributedString(string: L10n.ts("lock.wakeup_line", config.wakeupTime, countdown), attributes: infoAttrs),
            x: margin,
            y: clockY - 72,
            width: textWidth,
            height: 28
        )
    }

    private func drawVisuallyLeftAligned(_ text: NSAttributedString,
                                         x: CGFloat,
                                         y: CGFloat,
                                         width: CGFloat,
                                         height: CGFloat) {
        let line = CTLineCreateWithAttributedString(text)
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let glyphMinX = glyphBounds.isNull ? 0 : glyphBounds.minX
        text.draw(in: NSRect(x: x - glyphMinX, y: y, width: width, height: height))
    }

    private func drawEmergencyHint() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.14),
            .kern: 0.4,
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(
            string: L10n.t("lock.esc_hint"),
            attributes: attrs
        ).draw(in: NSRect(x: bounds.minX, y: bounds.minY + 26, width: bounds.width, height: 22))
    }

    private func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

// MARK: - Emergency Exit

class EmergencyExitCoordinator {
    static let shared = EmergencyExitCoordinator()
    private var lastEscapeAt: Date = .distantPast
    private let escapeDoubleInterval: TimeInterval = 0.45

    func handleEscapeKey() {
        let now = Date()
        if now.timeIntervalSince(lastEscapeAt) > escapeDoubleInterval {
            lastEscapeAt = now
            return
        }
        lastEscapeAt = .distantPast
        let fresh = SleepConfig.load()
        if LockWindowMath.canEmergencyExit(config: fresh, now: Date()) {
            exit(0)
        }
    }
}

// MARK: - App Delegate

class LockAppDelegate: NSObject, NSApplicationDelegate {
    var controller: LockWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let config = SleepConfig.load()
        controller = LockWindowController(config: config)
        controller?.activate()
        NSApp.activate(ignoringOtherApps: true)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                EmergencyExitCoordinator.shared.handleEscapeKey()
            }
            return nil
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { _ in nil }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - Main

@main
enum LockScreenMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = LockAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
