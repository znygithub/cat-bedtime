import Cocoa

// MARK: - Daily quotes (cat voice)

let quotes: [String] = [
    "嘘……猫猫已经睡着了",
    "别看屏幕了，闭上眼",
    "猫猫帮你占住了电脑，去睡吧",
    "你的床比屏幕舒服多了，\n相信猫猫",
    "猫猫替你守着，\n什么都不会错过的",
    "安心睡，猫猫在这呢",
    "猫猫打了个呼噜，\n意思是：你也该睡了",
    "电脑被猫占了，\n明天再说吧",
    "猫猫睡得很香，\n你也可以的",
    "今晚的事情都处理完了，\n因为猫猫说的",
]

func todayQuote() -> String {
    let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
    return quotes[day % quotes.count]
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
        var days: Set<Int> = [1,2,3,4,5]

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
        return SleepConfig(wakeupTime: wakeup, bedtime: bedtime, activeDays: days)
    }
}

// MARK: - Lock window math (aligned with bootcheck.sh / daemon)

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

    static func canEmergencyExit(config: SleepConfig, now: Date = Date()) -> Bool {
        if !isInLockdownWindow(config: config, now: now) { return true }
        if !config.activeDays.contains(isoWeekday(for: now)) { return true }
        return false
    }

    /// Minutes remaining until wakeup time.
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

// MARK: - Stats (kept for future pet-growth, not displayed as streak)

struct SleepStats {
    let streak: Int
    let totalCompleted: Int

    static func load(config: SleepConfig) -> SleepStats {
        let statsPath = NSHomeDirectory() + "/.timetosleep/stats.json"
        var records: [[String: String]] = []

        if let data = try? Data(contentsOf: URL(fileURLWithPath: statsPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let recs = json["records"] as? [[String: String]] {
            records = recs
        }

        let completed = records.filter { $0["status"] == "completed" }.count

        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let statusByDate = Dictionary(uniqueKeysWithValues: records.compactMap { r -> (String, String)? in
            guard let d = r["date"], let s = r["status"] else { return nil }
            return (d, s)
        })

        var streak = 0
        var day = cal.date(byAdding: .day, value: -1, to: Date())!
        for _ in 0..<400 {
            let ds = df.string(from: day)
            let weekday = cal.component(.weekday, from: day)
            let isoWeekday = weekday == 1 ? 7 : weekday - 1

            if !config.activeDays.contains(isoWeekday) {
                day = cal.date(byAdding: .day, value: -1, to: day)!
                continue
            }

            let status = statusByDate[ds] ?? ""
            if status == "completed" {
                streak += 1
                day = cal.date(byAdding: .day, value: -1, to: day)!
            } else if status.hasPrefix("skipped") || status.isEmpty {
                day = cal.date(byAdding: .day, value: -1, to: day)!
                continue
            } else {
                break
            }
        }

        return SleepStats(streak: streak, totalCompleted: completed)
    }
}

// MARK: - Lock Window Controller

class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class LockWindowController {
    let config: SleepConfig
    let stats: SleepStats
    var windows: [NSWindow] = []
    var clockTimer: Timer?
    private var previousInLockdown: Bool?

    init(config: SleepConfig, stats: SleepStats) {
        self.config = config
        self.stats = stats
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
        window.isOpaque = true
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.ignoresMouseEvents = false
        window.setFrame(screen.frame, display: true)

        let localFrame = NSRect(origin: .zero, size: screen.frame.size)
        window.contentView = LockScreenView(frame: localFrame, config: config, stats: stats)
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
            self?.updateClock()
            self?.checkWakeTime()
        }
    }

    private func updateClock() {
        for w in windows { (w.contentView as? LockScreenView)?.updateTime() }
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

// (Cat scene removed — the video animation handles the cat visual.
//  LockScreenView below is the text-only final state after lights-out.)

// MARK: - Lock Screen View

class LockScreenView: NSView {
    let config: SleepConfig
    let stats: SleepStats
    private var timeLabel: NSTextField!
    private var countdownLabel: NSTextField!

    init(frame: NSRect, config: SleepConfig, stats: SleepStats) {
        self.config = config
        self.stats = stats
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            EmergencyExitCoordinator.shared.handleEscapeKey()
            return
        }
        super.keyDown(with: event)
    }

    private func setupUI() {
        wantsLayer = true

        // Background: dark cozy gradient
        let bg = CAGradientLayer()
        bg.frame = bounds
        bg.colors = [
            NSColor(red: 0.078, green: 0.078, blue: 0.145, alpha: 1.0).cgColor,
            NSColor(red: 0.039, green: 0.039, blue: 0.071, alpha: 1.0).cgColor
        ]
        bg.startPoint = CGPoint(x: 0.5, y: 1.0)
        bg.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer?.addSublayer(bg)

        // Subtle warm ambient glow
        let glow = CAGradientLayer()
        glow.frame = NSRect(x: -bounds.width * 0.1, y: bounds.height * 0.1,
                            width: bounds.width * 1.2, height: bounds.height * 0.5)
        glow.type = .radial
        glow.colors = [
            NSColor(red: 0.45, green: 0.35, blue: 0.55, alpha: 0.04).cgColor,
            NSColor.clear.cgColor
        ]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer?.addSublayer(glow)

        // ── Vertically centered text-only layout ──
        // No cat drawing — the video animation handles the cat visual.
        // This screen is the steady-state "lights out" view.

        let containerWidth: CGFloat = 720
        let containerHeight: CGFloat = 340
        let container = NSView(frame: NSRect(
            x: bounds.midX - containerWidth / 2, y: bounds.midY - containerHeight / 2 + 20,
            width: containerWidth, height: containerHeight
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(container)

        var y: CGFloat = containerHeight

        // ── Clock ──
        y -= 100
        timeLabel = NSTextField(frame: NSRect(x: 0, y: y, width: containerWidth, height: 100))
        timeLabel.isBordered = false
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        timeLabel.backgroundColor = .clear
        timeLabel.alignment = .center
        setTimeAttributed(timeLabel)
        container.addSubview(timeLabel)

        // ── Quote (cat voice) ──
        let quoteWidth: CGFloat = 560
        let serifFont = NSFont(name: "Songti SC", size: 24)
            ?? NSFont(name: "STSongti-SC-Regular", size: 24)
            ?? NSFont.systemFont(ofSize: 24, weight: .regular)

        let quotePS = NSMutableParagraphStyle()
        quotePS.alignment = .center
        quotePS.lineHeightMultiple = 1.8

        let bracketAttrs: [NSAttributedString.Key: Any] = [
            .font: serifFont,
            .foregroundColor: NSColor(white: 1.0, alpha: 0.18),
            .kern: 2.0,
            .paragraphStyle: quotePS
        ]
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: serifFont,
            .foregroundColor: NSColor(white: 1.0, alpha: 0.72),
            .kern: 2.0,
            .paragraphStyle: quotePS
        ]

        let quoteStr = NSMutableAttributedString()
        quoteStr.append(NSAttributedString(string: "「", attributes: bracketAttrs))
        quoteStr.append(NSAttributedString(string: todayQuote(), attributes: textAttrs))
        quoteStr.append(NSAttributedString(string: "」", attributes: bracketAttrs))

        let measuredH = ceil(quoteStr.boundingRect(
            with: NSSize(width: quoteWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
        let quoteHeight = max(CGFloat(80), measuredH + 24)

        y -= 32
        y -= quoteHeight
        let quoteLabel = NSTextField(frame: NSRect(x: (containerWidth - quoteWidth) / 2, y: y, width: quoteWidth, height: quoteHeight))
        quoteLabel.isBordered = false
        quoteLabel.isEditable = false
        quoteLabel.isSelectable = false
        quoteLabel.backgroundColor = .clear
        quoteLabel.alignment = .center
        quoteLabel.lineBreakMode = .byWordWrapping
        quoteLabel.maximumNumberOfLines = 0
        quoteLabel.cell?.wraps = true
        quoteLabel.cell?.isScrollable = false
        quoteLabel.cell?.usesSingleLineMode = false
        quoteLabel.attributedStringValue = quoteStr
        quoteLabel.wantsLayer = true
        container.addSubview(quoteLabel)

        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1.0
            breathe.toValue = 0.78
            breathe.duration = 3.5
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            quoteLabel.layer?.add(breathe, forKey: "breathe")
        }

        // ── Countdown: "猫猫还有 X 小时 X 分钟醒来" ──
        y -= 36
        countdownLabel = NSTextField(frame: NSRect(x: 0, y: y, width: containerWidth, height: 22))
        countdownLabel.isBordered = false
        countdownLabel.isEditable = false
        countdownLabel.isSelectable = false
        countdownLabel.backgroundColor = .clear
        countdownLabel.alignment = .center
        updateCountdown()
        container.addSubview(countdownLabel)

        // ── Bottom: "猫猫早上 07:00 走" ──
        let bottomPS = NSMutableParagraphStyle()
        bottomPS.alignment = .center

        y -= 28
        let bottomLabel = NSTextField(frame: NSRect(x: 0, y: y, width: containerWidth, height: 20))
        bottomLabel.isBordered = false
        bottomLabel.isEditable = false
        bottomLabel.isSelectable = false
        bottomLabel.backgroundColor = .clear
        bottomLabel.alignment = .center
        bottomLabel.attributedStringValue = NSAttributedString(
            string: "猫猫早上 \(config.wakeupTime) 走",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.20),
                .kern: 1.0,
                .paragraphStyle: bottomPS
            ]
        )
        container.addSubview(bottomLabel)

        // ── ESC hint (fixed to bottom of screen) ──
        let hintPS = NSMutableParagraphStyle()
        hintPS.alignment = .center

        let hint = NSTextField(frame: NSRect(x: 0, y: 28, width: bounds.width, height: 18))
        hint.isBordered = false
        hint.isEditable = false
        hint.isSelectable = false
        hint.backgroundColor = .clear
        hint.alignment = .center
        hint.attributedStringValue = NSAttributedString(
            string: "异常时连按两下 ESC：重新校验时间，非锁机时段可退出",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.12),
                .kern: 0.5,
                .paragraphStyle: hintPS
            ]
        )
        hint.autoresizingMask = [.width, .minYMargin]
        addSubview(hint)
    }

    private func setTimeAttributed(_ label: NSTextField) {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        label.attributedStringValue = NSAttributedString(
            string: currentTimeString(),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 88, weight: .ultraLight),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.85),
                .kern: 6.0,
                .paragraphStyle: ps
            ]
        )
    }

    func updateTime() {
        setTimeAttributed(timeLabel)
        updateCountdown()
    }

    private func updateCountdown() {
        let mins = LockWindowMath.minutesUntilWakeup(config: config)
        let h = mins / 60
        let m = mins % 60

        let text: String
        if h > 0 {
            text = "猫猫还有 \(h) 小时 \(m) 分钟醒来"
        } else {
            text = "猫猫还有 \(m) 分钟醒来"
        }

        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        countdownLabel?.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.28),
                .kern: 1.2,
                .paragraphStyle: ps
            ]
        )
    }

    private func currentTimeString() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date())
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
        let stats = SleepStats.load(config: config)
        controller = LockWindowController(config: config, stats: stats)
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
}

// MARK: - Main

let app = NSApplication.shared
let delegate = LockAppDelegate()
app.delegate = delegate
app.run()
