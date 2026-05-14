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

// MARK: - Streak Achievement

enum StreakAnimationStyle: String {
    case glow
    case orbit
    case seal

    static func load() -> StreakAnimationStyle {
        let raw = ProcessInfo.processInfo.environment["ZZZ_STREAK_STYLE"]?.lowercased() ?? ""
        return StreakAnimationStyle(rawValue: raw) ?? .glow
    }
}

private func nightColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
    NSColor(red: red, green: green, blue: blue, alpha: alpha)
}

private func easeOutExpo() -> CAMediaTimingFunction {
    CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
}

private func circlePath(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    path.addEllipse(in: rect)
    return path
}

private func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
    return path
}

class StreakAchievementView: NSView {
    let stats: SleepStats
    let style: StreakAnimationStyle
    let reduceMotion: Bool

    private var numberLabel: NSTextField!
    private var eyebrowLabel: NSTextField!
    private var unitLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var countTimer: Timer?

    private var displayedNumber: Int {
        if stats.streak > 0 { return stats.streak }
        if stats.totalCompleted > 0 { return stats.totalCompleted }
        return 0
    }

    private var eyebrowText: String {
        if stats.streak > 0 { return "连续早睡" }
        if stats.totalCompleted > 0 { return "累计早睡" }
        return "新的开始"
    }

    private var unitText: String {
        if stats.streak > 0 { return "天" }
        if stats.totalCompleted > 0 { return "天" }
        return "晚"
    }

    private var subtitleText: String {
        if stats.streak > 0 { return "你已经守住了 \(stats.streak) 个夜晚" }
        if stats.totalCompleted > 0 { return "已经完成 \(stats.totalCompleted) 次早睡" }
        return "今晚把第一个夜晚交给睡眠"
    }

    init(frame: NSRect, stats: SleepStats, style: StreakAnimationStyle) {
        self.stats = stats
        self.style = style
        self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        countTimer?.invalidate()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        switch style {
        case .glow:
            setupGlow()
        case .orbit:
            setupOrbit()
        case .seal:
            setupSeal()
        }

        setupLabels()

        if !reduceMotion {
            runEntrance()
        }
    }

    private func setupLabels() {
        let centerX = bounds.midX

        eyebrowLabel = makeLabel(
            text: eyebrowText,
            frame: NSRect(x: centerX - 120, y: 120, width: 240, height: 24),
            font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            color: NSColor(white: 1.0, alpha: 0.54),
            kern: 2.2
        )
        addSubview(eyebrowLabel)

        numberLabel = makeLabel(
            text: "\(displayedNumber)",
            frame: NSRect(x: centerX - 96, y: 46, width: 150, height: 74),
            font: NSFont.monospacedDigitSystemFont(ofSize: 68, weight: .semibold),
            color: NSColor(white: 1.0, alpha: 0.94),
            kern: 0.0
        )
        addSubview(numberLabel)

        unitLabel = makeLabel(
            text: unitText,
            frame: NSRect(x: centerX + 52, y: 58, width: 72, height: 38),
            font: NSFont.systemFont(ofSize: 25, weight: .medium),
            color: NSColor(white: 1.0, alpha: 0.62),
            kern: 1.0,
            alignment: .left
        )
        addSubview(unitLabel)

        subtitleLabel = makeLabel(
            text: subtitleText,
            frame: NSRect(x: centerX - 210, y: 18, width: 420, height: 24),
            font: NSFont.systemFont(ofSize: 15, weight: .regular),
            color: NSColor(white: 1.0, alpha: 0.44),
            kern: 0.8
        )
        addSubview(subtitleLabel)

        if style == .seal {
            numberLabel.frame = NSRect(x: centerX - 108, y: 50, width: 146, height: 68)
            unitLabel.frame = NSRect(x: centerX + 38, y: 60, width: 86, height: 34)
            unitLabel.stringValue = stats.streak > 0 ? "晚" : unitText
            subtitleLabel.stringValue = stats.streak > 0 ? "今晚继续兑现这份契约" : subtitleText
        }

        if style == .orbit && displayedNumber > 0 && !reduceMotion {
            numberLabel.stringValue = "\(max(0, displayedNumber - min(displayedNumber, 8)))"
        }
    }

    private func setupGlow() {
        let center = CGPoint(x: bounds.midX, y: 80)

        let halo = CAGradientLayer()
        halo.frame = CGRect(x: center.x - 150, y: center.y - 150, width: 300, height: 300)
        halo.type = .radial
        halo.colors = [
            nightColor(red: 0.94, green: 0.76, blue: 0.42, alpha: 0.26).cgColor,
            nightColor(red: 0.45, green: 0.56, blue: 0.76, alpha: 0.06).cgColor,
            NSColor.clear.cgColor
        ]
        halo.locations = [0.0, 0.48, 1.0]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer?.addSublayer(halo)

        let ringRect = CGRect(x: center.x - 68, y: center.y - 68, width: 136, height: 136)
        let ring = CAShapeLayer()
        ring.path = circlePath(ringRect)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = nightColor(red: 0.98, green: 0.79, blue: 0.38, alpha: 0.78).cgColor
        ring.lineWidth = 1.8
        ring.lineCap = .round
        ring.strokeEnd = 1.0
        layer?.addSublayer(ring)

        let innerRing = CAShapeLayer()
        innerRing.path = circlePath(ringRect.insetBy(dx: 15, dy: 15))
        innerRing.fillColor = NSColor.clear.cgColor
        innerRing.strokeColor = nightColor(red: 0.74, green: 0.82, blue: 0.96, alpha: 0.22).cgColor
        innerRing.lineWidth = 1.0
        innerRing.lineDashPattern = [3, 9]
        layer?.addSublayer(innerRing)

        if !reduceMotion {
            ring.add(strokeAnimation(duration: 0.88, delay: 0.12), forKey: "stroke-in")
            halo.add(fadeScaleAnimation(duration: 0.9, delay: 0.0, fromScale: 0.82), forKey: "halo-in")
            innerRing.add(fadeAnimation(duration: 0.7, delay: 0.35, from: 0.0), forKey: "inner-in")
        }
    }

    private func setupOrbit() {
        let center = CGPoint(x: bounds.midX, y: 80)
        let orbitGroup = CALayer()
        orbitGroup.frame = bounds
        layer?.addSublayer(orbitGroup)

        let orbit = CAShapeLayer()
        orbit.path = circlePath(CGRect(x: center.x - 82, y: center.y - 82, width: 164, height: 164))
        orbit.fillColor = NSColor.clear.cgColor
        orbit.strokeColor = nightColor(red: 0.56, green: 0.79, blue: 0.72, alpha: 0.36).cgColor
        orbit.lineWidth = 1.1
        orbit.lineDashPattern = [5, 12]
        orbitGroup.addSublayer(orbit)

        let dotColors = [
            nightColor(red: 0.99, green: 0.72, blue: 0.42, alpha: 0.95),
            nightColor(red: 0.60, green: 0.86, blue: 0.76, alpha: 0.80),
            nightColor(red: 0.86, green: 0.88, blue: 0.96, alpha: 0.72)
        ]
        for i in 0..<7 {
            let angle = CGFloat(i) * CGFloat.pi * 2 / 7
            let radius: CGFloat = i % 2 == 0 ? 82 : 66
            let size: CGFloat = i == 0 ? 7 : 4
            let x = center.x + cos(angle) * radius - size / 2
            let y = center.y + sin(angle) * radius - size / 2
            let dot = CAShapeLayer()
            dot.path = circlePath(CGRect(x: x, y: y, width: size, height: size))
            dot.fillColor = dotColors[i % dotColors.count].cgColor
            orbitGroup.addSublayer(dot)
        }

        let core = CAGradientLayer()
        core.frame = CGRect(x: center.x - 92, y: center.y - 92, width: 184, height: 184)
        core.type = .radial
        core.colors = [
            nightColor(red: 0.36, green: 0.52, blue: 0.51, alpha: 0.20).cgColor,
            NSColor.clear.cgColor
        ]
        core.startPoint = CGPoint(x: 0.5, y: 0.5)
        core.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer?.insertSublayer(core, below: orbitGroup)

        if !reduceMotion {
            orbit.add(strokeAnimation(duration: 0.7, delay: 0.08), forKey: "orbit-stroke")
            orbitGroup.add(rotationAnimation(duration: 7.5), forKey: "slow-orbit")
            orbitGroup.add(fadeScaleAnimation(duration: 0.75, delay: 0.0, fromScale: 0.88), forKey: "orbit-in")
        }
    }

    private func setupSeal() {
        let centerX = bounds.midX
        let stampRect = CGRect(x: centerX - 132, y: 26, width: 264, height: 112)

        let stampLayer = CAShapeLayer()
        stampLayer.frame = bounds
        stampLayer.path = roundedRectPath(stampRect, radius: 8)
        stampLayer.fillColor = nightColor(red: 0.58, green: 0.18, blue: 0.14, alpha: 0.05).cgColor
        stampLayer.strokeColor = nightColor(red: 0.92, green: 0.45, blue: 0.34, alpha: 0.74).cgColor
        stampLayer.lineWidth = 2.2
        stampLayer.lineJoin = .round
        layer?.addSublayer(stampLayer)

        let inner = CAShapeLayer()
        inner.frame = bounds
        inner.path = roundedRectPath(stampRect.insetBy(dx: 10, dy: 10), radius: 6)
        inner.fillColor = NSColor.clear.cgColor
        inner.strokeColor = nightColor(red: 0.98, green: 0.76, blue: 0.47, alpha: 0.34).cgColor
        inner.lineWidth = 1.0
        inner.lineDashPattern = [7, 6]
        layer?.addSublayer(inner)

        let slash = CAShapeLayer()
        slash.frame = bounds
        let slashPath = CGMutablePath()
        slashPath.move(to: CGPoint(x: centerX - 94, y: 42))
        slashPath.addLine(to: CGPoint(x: centerX + 94, y: 122))
        slash.path = slashPath
        slash.strokeColor = nightColor(red: 0.98, green: 0.76, blue: 0.47, alpha: 0.20).cgColor
        slash.lineWidth = 1.2
        slash.lineCap = .round
        layer?.addSublayer(slash)

        if !reduceMotion {
            stampLayer.add(stampAnimation(duration: 0.5, delay: 0.18), forKey: "stamp-in")
            inner.add(fadeAnimation(duration: 0.35, delay: 0.5, from: 0.0), forKey: "inner-in")
            slash.add(strokeAnimation(duration: 0.42, delay: 0.46), forKey: "slash-in")
        }
    }

    private func runEntrance() {
        animateLabel(eyebrowLabel, delay: 0.24, fromY: -10, fromScale: 0.98)
        animateLabel(numberLabel, delay: 0.34, fromY: -6, fromScale: 0.84)
        animateLabel(unitLabel, delay: 0.44, fromY: -4, fromScale: 0.92)
        animateLabel(subtitleLabel, delay: 0.58, fromY: 8, fromScale: 0.98)

        if style == .orbit && displayedNumber > 0 {
            startCountAnimation()
        }
    }

    private func startCountAnimation() {
        let target = displayedNumber
        let start = max(0, target - min(target, 8))
        var step = 0
        let steps = max(1, min(18, target - start + 10))

        countTimer?.invalidate()
        countTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            step += 1
            let progress = min(1.0, Double(step) / Double(steps))
            let eased = 1.0 - pow(1.0 - progress, 3.0)
            let value = start + Int(round(Double(target - start) * eased))
            self.numberLabel.stringValue = "\(value)"
            if progress >= 1.0 {
                self.numberLabel.stringValue = "\(target)"
                timer.invalidate()
            }
        }
    }

    private func makeLabel(
        text: String,
        frame: NSRect,
        font: NSFont,
        color: NSColor,
        kern: CGFloat,
        alignment: NSTextAlignment = .center
    ) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.backgroundColor = .clear
        label.alignment = alignment
        label.font = font
        label.textColor = color
        label.wantsLayer = true

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: kern,
                .paragraphStyle: paragraph
            ]
        )
        return label
    }

    private func animateLabel(_ label: NSTextField, delay: CFTimeInterval, fromY: CGFloat, fromScale: CGFloat) {
        label.alphaValue = 1.0
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = CATransform3DConcat(
            CATransform3DMakeTranslation(0, fromY, 0),
            CATransform3DMakeScale(fromScale, fromScale, 1.0)
        )
        transform.toValue = CATransform3DIdentity

        let group = CAAnimationGroup()
        group.animations = [opacity, transform]
        group.duration = 0.7
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = easeOutExpo()
        group.fillMode = .backwards
        group.isRemovedOnCompletion = true
        label.layer?.add(group, forKey: "label-in")
    }

    private func fadeAnimation(duration: CFTimeInterval, delay: CFTimeInterval, from: CGFloat) -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = 1.0
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.timingFunction = easeOutExpo()
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        return animation
    }

    private func strokeAnimation(duration: CFTimeInterval, delay: CFTimeInterval) -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0.0
        animation.toValue = 1.0
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.timingFunction = easeOutExpo()
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        return animation
    }

    private func fadeScaleAnimation(duration: CFTimeInterval, delay: CFTimeInterval, fromScale: CGFloat) -> CAAnimation {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = fromScale
        scale.toValue = 1.0

        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = easeOutExpo()
        group.fillMode = .backwards
        group.isRemovedOnCompletion = true
        return group
    }

    private func rotationAnimation(duration: CFTimeInterval) -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0.0
        animation.toValue = CGFloat.pi * 2
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        return animation
    }

    private func stampAnimation(duration: CFTimeInterval, delay: CFTimeInterval) -> CAAnimation {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = CATransform3DConcat(
            CATransform3DMakeRotation(-0.14, 0, 0, 1),
            CATransform3DMakeScale(1.28, 1.28, 1.0)
        )
        transform.toValue = CATransform3DIdentity

        let group = CAAnimationGroup()
        group.animations = [opacity, transform]
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = easeOutExpo()
        group.fillMode = .backwards
        group.isRemovedOnCompletion = true
        return group
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

        let containerWidth: CGFloat = 720
        let containerHeight: CGFloat = 540
        let container = NSView(frame: NSRect(
            x: bounds.midX - containerWidth / 2, y: bounds.midY - containerHeight / 2 + 22,
            width: containerWidth, height: containerHeight
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(container)

        var y: CGFloat = containerHeight

        // ── Time: weight 300, 96px, rgba(255,255,255,0.88), letter-spacing 4px ──
        y -= 110
        timeLabel = NSTextField(frame: NSRect(x: 0, y: y, width: containerWidth, height: 110))
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

        // ── Achievement: streak reward, selected by ZZZ_STREAK_STYLE ──
        y -= 166
        let achievement = StreakAchievementView(
            frame: NSRect(x: 0, y: y, width: containerWidth, height: 156),
            stats: stats,
            style: StreakAnimationStyle.load()
        )
        container.addSubview(achievement)

        // ── Quote: serif font, 26px, rgba(255,255,255,0.85), generous line-height, letter-spacing 2px ──
        // Brackets 「」 in rgba(255,255,255,0.25)
        let quoteWidth: CGFloat = 600
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

        y -= 42
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

        // Subtle breathing on quote
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1.0
            breathe.toValue = 0.82
            breathe.duration = 3.0
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            quoteLabel.layer?.add(breathe, forKey: "breathe")
        }

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
