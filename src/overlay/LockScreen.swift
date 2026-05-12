import Cocoa

// MARK: - Daily quotes (one per day, not rotating)

let quotes: [String] = [
    "能按时关掉屏幕的人，不会过得太差",
    "能早睡早起的人，\n就是世界上最优秀的人",
    "你做到了大多数人做不到的事：\n关掉电脑",
    "自律的人不是不想玩，\n是知道什么时候该停",
    "睡饱的人，运气不会太差",
    "明天的你会感谢现在的你",
    "还记得上次早睡早起，\n精力充沛的自己么",
    "睡一觉，好主意自己会来找你",
    "深度睡眠发生在入睡后的前几个小时，\n越早睡越赚",
    "睡眠不足时，\n大脑的决策能力和喝醉差不多",
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

// MARK: - Lock window (aligned with bootcheck.sh / daemon)

enum LockWindowMath {
    static func parseHHMM(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    /// `true` when current time falls in the locked night window (same rules as bootcheck.sh).
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

    /// ISO weekday 1 = Mon … 7 = Sun (matches config `days`)
    static func isoWeekday(for date: Date) -> Int {
        let cal = Calendar.current
        let w = cal.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }

    /// Double-ESC escape: allowed if wall clock is outside lock window, or today is not a contract day.
    static func canEmergencyExit(config: SleepConfig, now: Date = Date()) -> Bool {
        if !isInLockdownWindow(config: config, now: now) { return true }
        if !config.activeDays.contains(isoWeekday(for: now)) { return true }
        return false
    }
}

// MARK: - Stats

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
    /// 上一秒是否在锁机窗内。仅当「刚还在锁机窗 → 现在已出窗」时自动退出，避免白天手动打开 layer 时立刻被秒关。
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
        // 用"是否已经越过起床时间"来判断，而不是精确匹配 HH:mm 字符串。
        // 仅当**刚才还在锁机窗、这一秒已出窗**时退出（到点解锁）。若一启动就不在锁机窗（例如白天手测 open），不自动退出，否则易误以为「点一下屏就没了」。
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

// MARK: - Lock Screen View

class LockScreenView: NSView {
    let config: SleepConfig
    let stats: SleepStats
    private var timeLabel: NSTextField!

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

        // Background: #141425 → #0a0a12
        let bg = CAGradientLayer()
        bg.frame = bounds
        bg.colors = [
            NSColor(red: 0.078, green: 0.078, blue: 0.145, alpha: 1.0).cgColor,
            NSColor(red: 0.039, green: 0.039, blue: 0.071, alpha: 1.0).cgColor
        ]
        bg.startPoint = CGPoint(x: 0.5, y: 1.0)
        bg.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer?.addSublayer(bg)

        // Subtle top glow
        let glow = CAGradientLayer()
        glow.frame = NSRect(x: -bounds.width * 0.1, y: bounds.height * 0.4,
                            width: bounds.width * 1.2, height: bounds.height * 0.6)
        glow.type = .radial
        glow.colors = [
            NSColor(red: 0.39, green: 0.39, blue: 0.71, alpha: 0.03).cgColor,
            NSColor.clear.cgColor
        ]
        glow.startPoint = CGPoint(x: 0.5, y: 1.0)
        glow.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer?.addSublayer(glow)

        // ── Center content ──

        let containerHeight: CGFloat = 400
        let container = NSView(frame: NSRect(
            x: bounds.midX - 300, y: bounds.midY - containerHeight / 2 + 30,
            width: 600, height: containerHeight
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(container)

        var y: CGFloat = containerHeight

        // ── Time: weight 300, 96px, rgba(255,255,255,0.88), letter-spacing 4px ──
        y -= 110
        timeLabel = NSTextField(frame: NSRect(x: 0, y: y, width: 600, height: 110))
        timeLabel.isBordered = false
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        timeLabel.backgroundColor = .clear
        timeLabel.alignment = .center
        let timePS = NSMutableParagraphStyle()
        timePS.alignment = .center
        timeLabel.attributedStringValue = NSAttributedString(
            string: currentTimeString(),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .light),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.88),
                .kern: 4.0,
                .paragraphStyle: timePS
            ]
        )
        container.addSubview(timeLabel)

        // ── Streak: 18px, rgba(255,255,255,0.58), letter-spacing 0.8px ──
        y -= 50
        let statText: String
        if stats.streak > 0 {
            statText = "🔥 连续早睡第 \(stats.streak) 天"
        } else if stats.totalCompleted > 0 {
            statText = "累计早睡 \(stats.totalCompleted) 天"
        } else {
            statText = "今晚是新的开始"
        }
        let statLabel = NSTextField(frame: NSRect(x: 0, y: y, width: 600, height: 30))
        statLabel.isBordered = false
        statLabel.isEditable = false
        statLabel.isSelectable = false
        statLabel.backgroundColor = .clear
        statLabel.alignment = .center
        let statPS = NSMutableParagraphStyle()
        statPS.alignment = .center
        statLabel.attributedStringValue = NSAttributedString(
            string: statText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.58),
                .kern: 0.8,
                .paragraphStyle: statPS
            ]
        )
        container.addSubview(statLabel)

        // ── Quote: serif font, 26px, rgba(255,255,255,0.85), generous line-height, letter-spacing 2px ──
        // Brackets 「」 in rgba(255,255,255,0.25)
        let quoteWidth: CGFloat = 560
        let serifFont = NSFont(name: "Songti SC", size: 26)
            ?? NSFont(name: "STSongti-SC-Regular", size: 26)
            ?? NSFont.systemFont(ofSize: 26, weight: .regular)

        let quotePS = NSMutableParagraphStyle()
        quotePS.alignment = .center
        quotePS.lineHeightMultiple = 1.9

        let bracketAttrs: [NSAttributedString.Key: Any] = [
            .font: serifFont,
            .foregroundColor: NSColor(white: 1.0, alpha: 0.25),
            .kern: 2.0,
            .paragraphStyle: quotePS
        ]
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: serifFont,
            .foregroundColor: NSColor(white: 1.0, alpha: 0.85),
            .kern: 2.0,
            .paragraphStyle: quotePS
        ]

        let quoteStr = NSMutableAttributedString()
        quoteStr.append(NSAttributedString(string: "「", attributes: bracketAttrs))
        quoteStr.append(NSAttributedString(string: todayQuote(), attributes: textAttrs))
        quoteStr.append(NSAttributedString(string: "」", attributes: bracketAttrs))

        let measuredQuoteHeight = ceil(quoteStr.boundingRect(
            with: NSSize(width: quoteWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
        let quoteHeight = max(CGFloat(150), measuredQuoteHeight + 28)

        y -= 54
        y -= quoteHeight
        let quoteLabel = NSTextField(frame: NSRect(x: (600 - quoteWidth) / 2, y: y, width: quoteWidth, height: quoteHeight))
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

        // Subtle breathing on quote
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1.0
        breathe.toValue = 0.82
        breathe.duration = 3.0
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        quoteLabel.layer?.add(breathe, forKey: "breathe")

        // ── Bottom: "明早 07:00 解锁" ──

        let bottomLabel = NSTextField(frame: NSRect(x: 0, y: 56, width: bounds.width, height: 20))
        bottomLabel.isBordered = false
        bottomLabel.isEditable = false
        bottomLabel.isSelectable = false
        bottomLabel.backgroundColor = .clear
        bottomLabel.alignment = .center
        let bottomPS = NSMutableParagraphStyle()
        bottomPS.alignment = .center
        bottomLabel.attributedStringValue = NSAttributedString(
            string: "明早 \(config.wakeupTime) 解锁",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.2),
                .kern: 1.0,
                .paragraphStyle: bottomPS
            ]
        )
        bottomLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(bottomLabel)

        let hint = NSTextField(frame: NSRect(x: 0, y: 28, width: bounds.width, height: 18))
        hint.isBordered = false
        hint.isEditable = false
        hint.isSelectable = false
        hint.backgroundColor = .clear
        hint.alignment = .center
        let hintPS = NSMutableParagraphStyle()
        hintPS.alignment = .center
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

    private func makeLabel(text: String, fontSize: CGFloat, color: NSColor, frame: NSRect) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.font = NSFont.systemFont(ofSize: fontSize, weight: .light)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        return label
    }

    func updateTime() {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        timeLabel?.attributedStringValue = NSAttributedString(
            string: currentTimeString(),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .light),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.88),
                .kern: 4.0,
                .paragraphStyle: ps
            ]
        )
    }

    private func currentTimeString() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

// MARK: - App Delegate

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
            // 53 = Escape — 双击：重新读盘 config + 当前时间，仅非锁机时段（或今日非契约日）可退出
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
