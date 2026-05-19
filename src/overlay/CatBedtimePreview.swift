import Cocoa
import QuartzCore
import ScreenCaptureKit

private let previewHint = "按 ESC 退出预览"

private func clamp(_ value: Double, _ lower: Double = 0.0, _ upper: Double = 1.0) -> Double {
    min(max(value, lower), upper)
}

private func easeInOutCubic(_ value: Double) -> Double {
    let x = clamp(value)
    if x < 0.5 { return 4.0 * x * x * x }
    return 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0
}

private func easeOutQuart(_ value: Double) -> Double {
    1.0 - pow(1.0 - clamp(value), 4.0)
}

private func easeOutQuint(_ value: Double) -> Double {
    1.0 - pow(1.0 - clamp(value), 5.0)
}

private func easeInQuart(_ value: Double) -> Double {
    let x = clamp(value)
    return x * x * x * x
}

private func progress(_ time: Double, start: Double, duration: Double) -> Double {
    guard duration > 0 else { return time >= start ? 1 : 0 }
    return clamp((time - start) / duration)
}

private func mix(_ a: CGFloat, _ b: CGFloat, _ amount: Double) -> CGFloat {
    a + (b - a) * CGFloat(clamp(amount))
}

private func impactPulse(_ time: Double, center: Double, tail: Double) -> Double {
    guard time >= center, time < center + tail else { return 0.0 }
    let x = 1.0 - (time - center) / tail
    return x * x
}

private enum CatMode {
    case walking
    case looking
    case jumping
    case pulling
    case landing
    case climbing
}

private struct SceneLayout {
    let unit: CGFloat
    let floorY: CGFloat
    let bedX: CGFloat
    let ropeX: CGFloat
    let ropeHandleY: CGFloat
}

private final class CatBedtimePreviewView: NSView {
    private let desktopImage: NSImage?
    private var displayTimer: Timer?
    private var startTime = CACurrentMediaTime()
    private let reducedMotion: Bool

    init(frame frameRect: NSRect, desktopImage: NSImage?) {
        self.desktopImage = desktopImage
        self.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        startDisplayTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("CatBedtimePreview does not support Interface Builder.")
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

    private var elapsed: Double {
        if reducedMotion { return 8.2 }
        return CACurrentMediaTime() - startTime
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let time = elapsed
        let layout = sceneLayout()
        let darkness = blackoutAmount(time)
        let lamp = lampAmount(time)

        drawDesktop(time: time)
        drawPullCord(layout: layout, time: time, alpha: CGFloat(1.0 - darkness))
        drawBlackoutOverlay(amount: darkness, time: time)
        drawLampGlow(layout: layout, amount: lamp)
        drawBedAndProps(layout: layout, time: time, lamp: lamp)
        drawFinalLockScreen(time: time)
        drawPreviewHint(alpha: 0.28)
    }

    private func sceneLayout() -> SceneLayout {
        let unit = min(max(bounds.height * 0.086, 54), 92)
        let floorY = bounds.minY + max(bounds.height * 0.115, unit * 1.08)
        return SceneLayout(
            unit: unit,
            floorY: floorY,
            bedX: bounds.minX + bounds.width * 0.47,
            ropeX: bounds.minX + bounds.width * 0.75,
            ropeHandleY: floorY + unit * 3.05
        )
    }

    private func blackoutAmount(_ time: Double) -> Double {
        easeOutQuart(progress(time, start: 5.10, duration: 0.42))
    }

    private func lampAmount(_ time: Double) -> Double {
        easeOutQuart(progress(time, start: 6.05, duration: 0.58))
    }

    private func drawDesktop(time: Double) {
        if let desktopImage {
            desktopImage.draw(in: bounds,
                              from: NSRect(origin: .zero, size: desktopImage.size),
                              operation: .sourceOver,
                              fraction: 1.0,
                              respectFlipped: true,
                              hints: [.interpolation: NSImageInterpolation.high])
        } else {
            let fallback = NSGradient(colors: [
                NSColor(srgbRed: 0.18, green: 0.24, blue: 0.31, alpha: 1),
                NSColor(srgbRed: 0.35, green: 0.50, blue: 0.56, alpha: 1),
                NSColor(srgbRed: 0.78, green: 0.62, blue: 0.39, alpha: 1),
            ])!
            fallback.draw(in: bounds, angle: 24)
        }

        let calm = CGFloat(easeOutQuart(progress(time, start: 4.92, duration: 0.55)))
        fillRect(bounds, color: NSColor.black.withAlphaComponent(0.08 + 0.20 * calm))
    }

    private func drawBlackoutOverlay(amount: Double, time: Double) {
        let pulse = CGFloat(impactPulse(time, center: 5.08, tail: 0.35))
        let alpha = CGFloat(amount)
        fillRect(bounds, color: NSColor.black.withAlphaComponent(alpha))

        if pulse > 0.01 {
            fillRect(bounds, color: NSColor.white.withAlphaComponent(0.10 * pulse))
        }
    }

    private func drawPullCord(layout: SceneLayout, time: Double, alpha: CGFloat) {
        guard alpha > 0.01 else { return }

        let enter = easeOutQuart(progress(time, start: 3.08, duration: 0.55))
        let pull = pullAmount(time)
        let wobble = CGFloat(sin(max(0, time - 5.05) * 26.0)) * layout.unit * 0.08 * CGFloat(impactPulse(time, center: 5.08, tail: 0.70))
        let handleY = layout.ropeHandleY - layout.unit * 0.64 * pull
        let x = layout.ropeX + wobble
        let visibleAlpha = alpha * CGFloat(enter)
        guard visibleAlpha > 0.01 else { return }

        let side = NSRect(x: x + layout.unit * 0.42,
                          y: bounds.midY - layout.unit * 2.9,
                          width: layout.unit * 0.28,
                          height: layout.unit * 5.8)
        fillRounded(side, radius: side.width * 0.45, color: NSColor.black.withAlphaComponent(0.18 * visibleAlpha))
        fillRounded(side.insetBy(dx: side.width * 0.28, dy: side.width * 0.5),
                    radius: side.width * 0.24,
                    color: NSColor.white.withAlphaComponent(0.13 * visibleAlpha))

        strokeLine(from: CGPoint(x: x, y: bounds.maxY + 8),
                   to: CGPoint(x: x, y: handleY),
                   color: NSColor(srgbRed: 0.92, green: 0.82, blue: 0.66, alpha: 0.92 * visibleAlpha),
                   width: 3.2,
                   lineCap: .round)

        let knobRect = NSRect(x: x - layout.unit * 0.21,
                              y: handleY - layout.unit * 0.21,
                              width: layout.unit * 0.42,
                              height: layout.unit * 0.42)
        fillEllipse(knobRect.offsetBy(dx: layout.unit * 0.035, dy: -layout.unit * 0.035),
                    color: NSColor.black.withAlphaComponent(0.18 * visibleAlpha))
        fillEllipse(knobRect, color: NSColor(srgbRed: 0.95, green: 0.72, blue: 0.43, alpha: 0.96 * visibleAlpha))
        strokeEllipse(knobRect, color: NSColor.black.withAlphaComponent(0.36 * visibleAlpha), width: 1.5)

        let snap = CGFloat(impactPulse(time, center: 5.08, tail: 0.38))
        if snap > 0.01 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: layout.unit * 0.34, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.82 * snap),
                .paragraphStyle: paragraph,
            ]
            NSAttributedString(string: "啪", attributes: attrs)
                .draw(in: NSRect(x: x - layout.unit * 0.8,
                                 y: handleY + layout.unit * 0.36 + snap * layout.unit * 0.18,
                                 width: layout.unit * 1.6,
                                 height: layout.unit * 0.55))
        }
    }

    private func pullAmount(_ time: Double) -> CGFloat {
        let grab = easeInOutCubic(progress(time, start: 4.60, duration: 0.34))
        let release = 1.0 - easeOutQuart(progress(time, start: 5.18, duration: 0.34))
        return CGFloat(grab * release)
    }

    private func drawLampGlow(layout: SceneLayout, amount: Double) {
        let alpha = CGFloat(amount)
        guard alpha > 0.01 else { return }

        let center = CGPoint(x: layout.bedX - layout.unit * 0.68, y: layout.floorY + layout.unit * 1.62)
        let glowRect = NSRect(x: center.x - layout.unit * 3.8,
                              y: center.y - layout.unit * 2.5,
                              width: layout.unit * 7.6,
                              height: layout.unit * 5.2)
        let glow = NSGradient(colors: [
            NSColor(srgbRed: 1.0, green: 0.78, blue: 0.38, alpha: 0.42 * alpha),
            NSColor(srgbRed: 0.95, green: 0.48, blue: 0.24, alpha: 0.14 * alpha),
            NSColor.clear,
        ])!
        glow.draw(in: glowRect, relativeCenterPosition: NSPoint(x: -0.18, y: 0.16))

        let cone = NSBezierPath()
        cone.move(to: NSPoint(x: center.x, y: center.y))
        cone.line(to: NSPoint(x: layout.bedX - layout.unit * 2.65, y: layout.floorY - layout.unit * 0.24))
        cone.line(to: NSPoint(x: layout.bedX + layout.unit * 2.55, y: layout.floorY - layout.unit * 0.20))
        cone.close()
        NSColor(srgbRed: 1.0, green: 0.78, blue: 0.44, alpha: 0.11 * alpha).setFill()
        cone.fill()

        drawBedsideLamp(center: center, unit: layout.unit, alpha: alpha)
    }

    private func drawBedAndProps(layout: SceneLayout, time: Double, lamp: Double) {
        let dark = blackoutAmount(time)
        let bedCenter = CGPoint(x: bedX(time: time, layout: layout), y: layout.floorY)
        let occupied = time > 6.78 || reducedMotion
        let sceneAlpha = CGFloat(max(1.0 - dark, lamp))

        drawDraggedRope(layout: layout, time: time, bedCenter: bedCenter, alpha: sceneAlpha * CGFloat(1.0 - dark))
        drawBed(center: bedCenter,
                unit: layout.unit,
                time: time,
                litAmount: CGFloat(lamp),
                occupied: occupied,
                alpha: sceneAlpha)

        if !occupied {
            let cat = catState(time: time, layout: layout)
            drawCat(anchor: cat.anchor,
                    unit: layout.unit,
                    time: time,
                    facing: cat.facing,
                    mode: cat.mode,
                    carriesPillow: cat.carriesPillow,
                    alpha: sceneAlpha)
        }
    }

    private func bedX(time: Double, layout: SceneLayout) -> CGFloat {
        if reducedMotion { return layout.bedX }
        let entry = easeOutQuint(progress(time, start: 0.14, duration: 2.42))
        let dragged = mix(bounds.maxX + layout.unit * 2.55, layout.bedX + layout.unit * 1.05, entry)
        let settle = easeInOutCubic(progress(time, start: 3.62, duration: 1.15))
        let final = mix(dragged, layout.bedX, settle)
        let bump = CGFloat(sin(time * 13.0)) * layout.unit * 0.018 * CGFloat(1.0 - progress(time, start: 4.60, duration: 0.70))
        return final + bump
    }

    private func catState(time: Double, layout: SceneLayout) -> (anchor: CGPoint, facing: CGFloat, mode: CatMode, carriesPillow: Bool) {
        if reducedMotion {
            return (CGPoint(x: layout.bedX + layout.unit * 0.2, y: layout.floorY), -1, .climbing, false)
        }

        let firstWalk = easeInOutCubic(progress(time, start: 0.12, duration: 2.30))
        let startX = bounds.maxX + layout.unit * 1.25
        let pauseX = bounds.minX + bounds.width * 0.49
        var x = mix(startX, pauseX, firstWalk)
        var y = layout.floorY
        var facing: CGFloat = -1
        var mode: CatMode = .walking
        var carriesPillow = true

        if time >= 2.42 && time < 3.28 {
            x = pauseX
            mode = .looking
        } else if time >= 3.28 && time < 4.26 {
            let toSwitch = easeInOutCubic(progress(time, start: 3.28, duration: 0.98))
            x = mix(pauseX, layout.ropeX - layout.unit * 0.28, toSwitch)
            facing = 1
            mode = .walking
        } else if time >= 4.26 && time < 4.78 {
            let jump = easeOutQuart(progress(time, start: 4.26, duration: 0.52))
            x = mix(layout.ropeX - layout.unit * 0.28, layout.ropeX - layout.unit * 0.10, jump)
            y = mix(layout.floorY, layout.ropeHandleY - layout.unit * 1.18, jump)
            facing = 1
            mode = .jumping
        } else if time >= 4.78 && time < 5.30 {
            x = layout.ropeX - layout.unit * 0.10
            y = layout.ropeHandleY - layout.unit * 1.18 - layout.unit * 0.62 * pullAmount(time)
            facing = 1
            mode = .pulling
        } else if time >= 5.30 && time < 5.78 {
            let land = easeInQuart(progress(time, start: 5.30, duration: 0.48))
            x = mix(layout.ropeX - layout.unit * 0.10, layout.ropeX - layout.unit * 0.34, land)
            y = mix(layout.ropeHandleY - layout.unit * 1.22, layout.floorY, land)
            facing = -1
            mode = .landing
            carriesPillow = false
        } else if time >= 5.78 {
            let climb = easeInOutCubic(progress(time, start: 5.78, duration: 0.86))
            x = mix(layout.ropeX - layout.unit * 0.34, layout.bedX + layout.unit * 0.34, climb)
            y = mix(layout.floorY, layout.floorY + layout.unit * 0.30, climb)
            facing = -1
            mode = .climbing
            carriesPillow = false
        }

        return (CGPoint(x: x, y: y), facing, mode, carriesPillow)
    }

    private func drawDraggedRope(layout: SceneLayout, time: Double, bedCenter: CGPoint, alpha: CGFloat) {
        guard alpha > 0.01, time < 5.20 else { return }
        let cat = catState(time: time, layout: layout)
        let slack = sin(time * 5.0) * Double(layout.unit) * 0.07
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cat.anchor.x + cat.facing * layout.unit * 0.56, y: cat.anchor.y + layout.unit * 0.32))
        path.curve(to: NSPoint(x: bedCenter.x - layout.unit * 1.42, y: bedCenter.y + layout.unit * 0.32),
                   controlPoint1: NSPoint(x: cat.anchor.x + layout.unit * 0.52, y: cat.anchor.y + layout.unit * 0.16 + CGFloat(slack)),
                   controlPoint2: NSPoint(x: bedCenter.x - layout.unit * 1.95, y: bedCenter.y + layout.unit * 0.16 - CGFloat(slack)))
        NSColor(srgbRed: 0.64, green: 0.45, blue: 0.28, alpha: 0.70 * alpha).setStroke()
        path.lineWidth = 2.2
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawBed(center: CGPoint, unit: CGFloat, time: Double, litAmount: CGFloat, occupied: Bool, alpha: CGFloat) {
        guard alpha > 0.01 else { return }

        let bed = NSRect(x: center.x - unit * 1.62,
                         y: center.y - unit * 0.28,
                         width: unit * 3.24,
                         height: unit * 1.06)
        let shadowAlpha = min(alpha, 0.32 + litAmount * 0.40)
        fillEllipse(NSRect(x: bed.minX + unit * 0.14,
                           y: center.y - unit * 0.45,
                           width: bed.width * 0.92,
                           height: unit * 0.30),
                    color: NSColor.black.withAlphaComponent(0.24 * shadowAlpha))

        fillRounded(NSRect(x: bed.minX + unit * 0.15, y: bed.minY, width: bed.width * 0.90, height: unit * 0.36),
                    radius: unit * 0.14,
                    color: NSColor(srgbRed: 0.47, green: 0.26, blue: 0.16, alpha: 0.96 * alpha))
        fillRounded(NSRect(x: bed.minX, y: bed.minY + unit * 0.22, width: bed.width, height: unit * 0.52),
                    radius: unit * 0.16,
                    color: NSColor(srgbRed: 0.74, green: 0.48, blue: 0.31, alpha: 0.97 * alpha))
        fillRounded(NSRect(x: bed.minX + unit * 0.20, y: bed.minY + unit * 0.48, width: bed.width * 0.62, height: unit * 0.44),
                    radius: unit * 0.16,
                    color: NSColor(srgbRed: 0.98, green: 0.84, blue: 0.57, alpha: 0.98 * alpha))

        let pillowRect = NSRect(x: bed.minX + unit * 0.22, y: bed.minY + unit * 0.57, width: unit * 0.82, height: unit * 0.42)
        fillRounded(pillowRect,
                    radius: unit * 0.16,
                    color: NSColor(srgbRed: 0.95, green: 0.91, blue: 0.78, alpha: 0.98 * alpha))
        strokeRounded(pillowRect,
                      radius: unit * 0.16,
                      color: NSColor.black.withAlphaComponent(0.15 * alpha),
                      width: 1.0)

        let blanketLift = occupied ? unit * 0.13 : 0
        let blanket = NSRect(x: bed.minX + unit * 0.92,
                             y: bed.minY + unit * 0.46,
                             width: unit * 2.05,
                             height: unit * 0.55 + blanketLift)
        fillRounded(blanket,
                    radius: unit * 0.18,
                    color: NSColor(srgbRed: 0.36, green: 0.57, blue: 0.64, alpha: 0.97 * alpha))
        strokeRounded(blanket,
                      radius: unit * 0.18,
                      color: NSColor.white.withAlphaComponent(0.12 * alpha),
                      width: 1.0)

        if occupied {
            drawSleepingCatInBed(bed: bed, unit: unit, time: time, alpha: alpha)
        } else {
            fillEllipse(NSRect(x: bed.minX + unit * 0.42, y: bed.minY - unit * 0.10, width: unit * 0.22, height: unit * 0.22),
                        color: NSColor.black.withAlphaComponent(0.35 * alpha))
            fillEllipse(NSRect(x: bed.maxX - unit * 0.64, y: bed.minY - unit * 0.10, width: unit * 0.22, height: unit * 0.22),
                        color: NSColor.black.withAlphaComponent(0.35 * alpha))
        }
    }

    private func drawSleepingCatInBed(bed: NSRect, unit: CGFloat, time: Double, alpha: CGFloat) {
        let breathe = CGFloat(sin(time * 2.1)) * unit * 0.018
        let fur = NSColor(srgbRed: 0.94, green: 0.62, blue: 0.34, alpha: 1.0 * alpha)
        let outline = NSColor.black.withAlphaComponent(0.28 * alpha)

        drawTriangle(points: [
            NSPoint(x: bed.minX + unit * 1.16, y: bed.minY + unit * 1.01 + breathe),
            NSPoint(x: bed.minX + unit * 1.31, y: bed.minY + unit * 1.37 + breathe),
            NSPoint(x: bed.minX + unit * 1.48, y: bed.minY + unit * 1.02 + breathe),
        ], fill: fur, outline: outline)
        drawTriangle(points: [
            NSPoint(x: bed.minX + unit * 1.56, y: bed.minY + unit * 1.02 + breathe),
            NSPoint(x: bed.minX + unit * 1.76, y: bed.minY + unit * 1.34 + breathe),
            NSPoint(x: bed.minX + unit * 1.86, y: bed.minY + unit * 0.98 + breathe),
        ], fill: fur, outline: outline)

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bed.maxX - unit * 0.22, y: bed.minY + unit * 0.77 + breathe))
        tail.curve(to: NSPoint(x: bed.maxX + unit * 0.24, y: bed.minY + unit * 0.97 + breathe),
                   controlPoint1: NSPoint(x: bed.maxX + unit * 0.04, y: bed.minY + unit * 0.70),
                   controlPoint2: NSPoint(x: bed.maxX + unit * 0.36, y: bed.minY + unit * 0.72))
        tail.curve(to: NSPoint(x: bed.maxX - unit * 0.04, y: bed.minY + unit * 1.12 + breathe),
                   controlPoint1: NSPoint(x: bed.maxX + unit * 0.18, y: bed.minY + unit * 1.20),
                   controlPoint2: NSPoint(x: bed.maxX + unit * 0.06, y: bed.minY + unit * 1.18))
        fur.setStroke()
        tail.lineWidth = unit * 0.16
        tail.lineCapStyle = .round
        tail.stroke()
        outline.setStroke()
        tail.lineWidth = 1.2
        tail.stroke()
    }

    private func drawBedsideLamp(center: CGPoint, unit: CGFloat, alpha: CGFloat) {
        strokeLine(from: CGPoint(x: center.x, y: center.y - unit * 0.85),
                   to: CGPoint(x: center.x, y: center.y - unit * 0.18),
                   color: NSColor(srgbRed: 0.71, green: 0.48, blue: 0.27, alpha: 0.92 * alpha),
                   width: 3.0,
                   lineCap: .round)
        fillRounded(NSRect(x: center.x - unit * 0.34, y: center.y - unit * 0.95, width: unit * 0.68, height: unit * 0.14),
                    radius: unit * 0.06,
                    color: NSColor(srgbRed: 0.50, green: 0.31, blue: 0.20, alpha: 0.95 * alpha))

        let shade = NSBezierPath()
        shade.move(to: NSPoint(x: center.x - unit * 0.44, y: center.y - unit * 0.10))
        shade.line(to: NSPoint(x: center.x + unit * 0.44, y: center.y - unit * 0.10))
        shade.line(to: NSPoint(x: center.x + unit * 0.29, y: center.y + unit * 0.36))
        shade.line(to: NSPoint(x: center.x - unit * 0.29, y: center.y + unit * 0.36))
        shade.close()
        NSColor(srgbRed: 1.0, green: 0.72, blue: 0.36, alpha: 0.96 * alpha).setFill()
        shade.fill()
        NSColor.black.withAlphaComponent(0.18 * alpha).setStroke()
        shade.lineWidth = 1.2
        shade.stroke()
    }

    private func drawCat(anchor: CGPoint, unit: CGFloat, time: Double, facing: CGFloat, mode: CatMode, carriesPillow: Bool, alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        let walkCycle = CGFloat(sin(time * 11.0))
        let bob = mode == .walking ? abs(walkCycle) * unit * 0.045 : CGFloat(sin(time * 3.0)) * unit * 0.012
        let tilt: CGFloat
        switch mode {
        case .walking:
            tilt = walkCycle * 3.8
        case .looking:
            tilt = -7.0
        case .jumping:
            tilt = 8.0
        case .pulling:
            tilt = 3.0 + pullAmount(time) * 7.0
        case .landing:
            tilt = -6.0
        case .climbing:
            tilt = -12.0
        }

        withLocalTransform(center: CGPoint(x: anchor.x, y: anchor.y + bob),
                           angle: Double(tilt),
                           scaleX: facing,
                           scaleY: 1.0) {
            drawCatShape(unit: unit, time: time, mode: mode, carriesPillow: carriesPillow, alpha: alpha)
        }
    }

    private func drawCatShape(unit: CGFloat, time: Double, mode: CatMode, carriesPillow: Bool, alpha: CGFloat) {
        let fur = NSColor(srgbRed: 0.95, green: 0.63, blue: 0.34, alpha: 1.0 * alpha)
        let furLight = NSColor(srgbRed: 1.0, green: 0.79, blue: 0.52, alpha: 1.0 * alpha)
        let stripe = NSColor(srgbRed: 0.62, green: 0.31, blue: 0.16, alpha: 0.42 * alpha)
        let outline = NSColor.black.withAlphaComponent(0.44 * alpha)
        let paw = NSColor(srgbRed: 0.99, green: 0.82, blue: 0.63, alpha: 1.0 * alpha)
        let blink = mode == .looking ? 0.72 : max(impactPulse(time, center: 2.72, tail: 0.16), impactPulse(time, center: 7.18, tail: 0.18))

        let stretch = mode == .jumping || mode == .pulling ? unit * 0.15 : 0
        let body = NSRect(x: -unit * 0.52, y: unit * 0.36, width: unit * 1.05, height: unit * 0.74 + stretch)
        let head = NSRect(x: -unit * 0.45, y: unit * 0.95 + stretch * 0.34, width: unit * 0.90, height: unit * 0.82)

        if carriesPillow {
            let pillow = NSRect(x: -unit * 0.56, y: unit * 0.80, width: unit * 0.74, height: unit * 0.34)
            fillRounded(pillow.offsetBy(dx: -unit * 0.06, dy: -unit * 0.04),
                        radius: unit * 0.12,
                        color: NSColor.black.withAlphaComponent(0.14 * alpha))
            fillRounded(pillow,
                        radius: unit * 0.13,
                        color: NSColor(srgbRed: 0.92, green: 0.88, blue: 0.74, alpha: 0.98 * alpha))
            strokeRounded(pillow, radius: unit * 0.13, color: outline.withAlphaComponent(0.38), width: 1.0)
        }

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: unit * 0.42, y: unit * 0.78))
        tail.curve(to: NSPoint(x: unit * 0.98, y: unit * 1.18 + CGFloat(sin(time * 4.0)) * unit * 0.06),
                   controlPoint1: NSPoint(x: unit * 0.88, y: unit * 0.74),
                   controlPoint2: NSPoint(x: unit * 1.12, y: unit * 0.90))
        fur.setStroke()
        tail.lineWidth = unit * 0.15
        tail.lineCapStyle = .round
        tail.stroke()
        outline.setStroke()
        tail.lineWidth = 1.2
        tail.stroke()

        fillEllipse(body, color: fur)
        strokeEllipse(body, color: outline, width: 1.4)
        drawStripeMarks(unit: unit, color: stripe)

        drawTriangle(points: [
            NSPoint(x: -unit * 0.35, y: head.maxY - unit * 0.12),
            NSPoint(x: -unit * 0.52, y: head.maxY + unit * 0.34),
            NSPoint(x: -unit * 0.10, y: head.maxY + unit * 0.12),
        ], fill: fur, outline: outline)
        drawTriangle(points: [
            NSPoint(x: unit * 0.10, y: head.maxY + unit * 0.12),
            NSPoint(x: unit * 0.52, y: head.maxY + unit * 0.34),
            NSPoint(x: unit * 0.35, y: head.maxY - unit * 0.12),
        ], fill: fur, outline: outline)

        fillEllipse(head, color: furLight)
        strokeEllipse(head, color: outline, width: 1.4)

        let eyeY = head.midY + unit * 0.10
        let eyeShift = mode == .looking ? -unit * 0.045 : (mode == .pulling ? unit * 0.035 : 0)
        drawEye(center: CGPoint(x: -unit * 0.18 + eyeShift, y: eyeY), unit: unit, blink: blink, alpha: alpha)
        drawEye(center: CGPoint(x: unit * 0.18 + eyeShift, y: eyeY), unit: unit, blink: blink, alpha: alpha)

        drawTriangle(points: [
            NSPoint(x: -unit * 0.05, y: head.midY - unit * 0.02),
            NSPoint(x: unit * 0.05, y: head.midY - unit * 0.02),
            NSPoint(x: 0, y: head.midY - unit * 0.10),
        ], fill: NSColor(srgbRed: 0.36, green: 0.18, blue: 0.16, alpha: 0.72 * alpha), outline: nil)

        drawWhiskers(unit: unit, alpha: alpha)
        drawLegs(unit: unit, time: time, mode: mode, paw: paw, outline: outline, alpha: alpha)
        drawArms(unit: unit, time: time, mode: mode, paw: paw, outline: outline, alpha: alpha)

        if mode == .looking {
            drawAnnoyedMarks(unit: unit, alpha: alpha)
        }
    }

    private func drawEye(center: CGPoint, unit: CGFloat, blink: Double, alpha: CGFloat) {
        let height = max(unit * 0.025, unit * 0.12 * CGFloat(1.0 - blink))
        if height <= unit * 0.032 {
            strokeLine(from: CGPoint(x: center.x - unit * 0.08, y: center.y),
                       to: CGPoint(x: center.x + unit * 0.08, y: center.y),
                       color: NSColor.black.withAlphaComponent(0.72 * alpha),
                       width: 1.7,
                       lineCap: .round)
            return
        }
        fillEllipse(NSRect(x: center.x - unit * 0.045, y: center.y - height / 2, width: unit * 0.09, height: height),
                    color: NSColor.black.withAlphaComponent(0.76 * alpha))
    }

    private func drawLegs(unit: CGFloat, time: Double, mode: CatMode, paw: NSColor, outline: NSColor, alpha: CGFloat) {
        let step = mode == .walking ? CGFloat(sin(time * 11.0)) : 0
        let crouch = mode == .landing ? unit * 0.10 : 0
        let left = NSRect(x: -unit * 0.40 + step * unit * 0.05,
                          y: unit * 0.02 - crouch,
                          width: unit * 0.34,
                          height: unit * 0.20)
        let right = NSRect(x: unit * 0.06 - step * unit * 0.05,
                           y: unit * 0.02 - crouch,
                           width: unit * 0.34,
                           height: unit * 0.20)
        fillRounded(left, radius: unit * 0.08, color: paw)
        fillRounded(right, radius: unit * 0.08, color: paw)
        strokeRounded(left, radius: unit * 0.08, color: outline, width: 1.0)
        strokeRounded(right, radius: unit * 0.08, color: outline, width: 1.0)
    }

    private func drawArms(unit: CGFloat, time: Double, mode: CatMode, paw: NSColor, outline: NSColor, alpha: CGFloat) {
        let reach = mode == .jumping || mode == .pulling
        if reach {
            strokeLine(from: CGPoint(x: -unit * 0.20, y: unit * 1.17),
                       to: CGPoint(x: -unit * 0.12, y: unit * 1.98),
                       color: paw,
                       width: unit * 0.10,
                       lineCap: .round)
            strokeLine(from: CGPoint(x: unit * 0.20, y: unit * 1.17),
                       to: CGPoint(x: unit * 0.12, y: unit * 1.98),
                       color: paw,
                       width: unit * 0.10,
                       lineCap: .round)
            strokeLine(from: CGPoint(x: -unit * 0.12, y: unit * 1.98),
                       to: CGPoint(x: unit * 0.12, y: unit * 1.98),
                       color: outline.withAlphaComponent(0.55 * alpha),
                       width: 1.0,
                       lineCap: .round)
            return
        }

        let swing = mode == .walking ? CGFloat(sin(time * 11.0 + .pi)) * unit * 0.06 : 0
        fillRounded(NSRect(x: -unit * 0.52, y: unit * 0.54 + swing, width: unit * 0.25, height: unit * 0.18),
                    radius: unit * 0.08,
                    color: paw)
        fillRounded(NSRect(x: unit * 0.27, y: unit * 0.54 - swing, width: unit * 0.25, height: unit * 0.18),
                    radius: unit * 0.08,
                    color: paw)
    }

    private func drawStripeMarks(unit: CGFloat, color: NSColor) {
        for x in [-0.20, 0.0, 0.20] {
            strokeLine(from: CGPoint(x: unit * CGFloat(x), y: unit * 1.05),
                       to: CGPoint(x: unit * CGFloat(x) * 0.7, y: unit * 0.84),
                       color: color,
                       width: 1.6,
                       lineCap: .round)
        }
    }

    private func drawWhiskers(unit: CGFloat, alpha: CGFloat) {
        let color = NSColor.black.withAlphaComponent(0.34 * alpha)
        for row in [-0.08, -0.18] {
            strokeLine(from: CGPoint(x: -unit * 0.12, y: unit * (0.96 + CGFloat(row))),
                       to: CGPoint(x: -unit * 0.52, y: unit * (0.99 + CGFloat(row) * 1.15)),
                       color: color,
                       width: 1.0,
                       lineCap: .round)
            strokeLine(from: CGPoint(x: unit * 0.12, y: unit * (0.96 + CGFloat(row))),
                       to: CGPoint(x: unit * 0.52, y: unit * (0.99 + CGFloat(row) * 1.15)),
                       color: color,
                       width: 1.0,
                       lineCap: .round)
        }
    }

    private func drawAnnoyedMarks(unit: CGFloat, alpha: CGFloat) {
        let color = NSColor(srgbRed: 1.0, green: 0.72, blue: 0.28, alpha: 0.74 * alpha)
        strokeZigzag(from: CGPoint(x: -unit * 0.70, y: unit * 2.02),
                     to: CGPoint(x: -unit * 0.28, y: unit * 2.22),
                     color: color,
                     width: 2.0)
        strokeZigzag(from: CGPoint(x: unit * 0.32, y: unit * 2.20),
                     to: CGPoint(x: unit * 0.72, y: unit * 2.06),
                     color: color,
                     width: 2.0)
    }

    private func drawFinalLockScreen(time: Double) {
        let alpha = CGFloat(easeOutQuart(progress(time, start: 7.28, duration: 0.78)))
        guard alpha > 0.01 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: min(106, bounds.width * 0.12), weight: .light),
            .foregroundColor: NSColor(srgbRed: 0.96, green: 0.88, blue: 0.70, alpha: 0.92 * alpha),
            .kern: 2.0,
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: currentTimeString(), attributes: timeAttrs)
            .draw(in: NSRect(x: bounds.minX, y: bounds.midY + bounds.height * 0.14, width: bounds.width, height: 130))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(26, bounds.width * 0.025), weight: .medium),
            .foregroundColor: NSColor(srgbRed: 1.0, green: 0.81, blue: 0.50, alpha: 0.86 * alpha),
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: "猫猫睡着了。电脑被它占用了", attributes: titleAttrs)
            .draw(in: NSRect(x: bounds.minX + bounds.width * 0.12,
                             y: bounds.midY + bounds.height * 0.07,
                             width: bounds.width * 0.76,
                             height: 42))
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

    private func withLocalTransform(center: CGPoint, angle: Double, scaleX: CGFloat, scaleY: CGFloat, draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: CGFloat(angle) * .pi / 180)
            context.scaleBy(x: scaleX, y: scaleY)
        }
        draw()
        NSGraphicsContext.restoreGraphicsState()
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
            previewWindow.title = "Cat Bedtime Preview"
            previewWindow.isOpaque = true
            previewWindow.backgroundColor = .black
            previewWindow.level = windowed ? .normal : .screenSaver
            previewWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            previewWindow.isReleasedWhenClosed = false
            previewWindow.hidesOnDeactivate = false
            previewWindow.canHide = false

            let localFrame = NSRect(origin: .zero, size: target.frame.size)
            let view = CatBedtimePreviewView(frame: localFrame, desktopImage: snapshots[index])
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

private func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

private func strokeRounded(_ rect: NSRect, radius: CGFloat, color: NSColor, width: CGFloat) {
    color.setStroke()
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.lineWidth = width
    path.stroke()
}

private func fillRect(_ rect: NSRect, color: NSColor) {
    color.setFill()
    rect.fill()
}

private func fillEllipse(_ rect: NSRect, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

private func strokeEllipse(_ rect: NSRect, color: NSColor, width: CGFloat) {
    color.setStroke()
    let path = NSBezierPath(ovalIn: rect)
    path.lineWidth = width
    path.stroke()
}

private func drawTriangle(points: [NSPoint], fill: NSColor, outline: NSColor?) {
    guard points.count == 3 else { return }
    let path = NSBezierPath()
    path.move(to: points[0])
    path.line(to: points[1])
    path.line(to: points[2])
    path.close()
    fill.setFill()
    path.fill()
    if let outline {
        outline.setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }
}

private func strokeLine(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor,
    width: CGFloat,
    lineCap: NSBezierPath.LineCapStyle = .butt
) {
    color.setStroke()
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    path.lineCapStyle = lineCap
    path.stroke()
}

private func strokeZigzag(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat) {
    color.setStroke()
    let path = NSBezierPath()
    let steps = 5
    path.move(to: start)
    for index in 1...steps {
        let t = CGFloat(index) / CGFloat(steps)
        let x = start.x + (end.x - start.x) * t
        let y = start.y + (end.y - start.y) * t + (index % 2 == 0 ? -1 : 1) * 6.0
        path.line(to: CGPoint(x: x, y: y))
    }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.stroke()
}

private func commandLineDoubleValue(after flag: String) -> Double? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.indices.contains(index + 1) else {
        return nil
    }
    return Double(CommandLine.arguments[index + 1])
}

private let app = NSApplication.shared
private let delegate = PreviewAppDelegate()
delegate.windowed = CommandLine.arguments.contains("--windowed")
delegate.autoQuitDelay = commandLineDoubleValue(after: "--auto-quit")
app.delegate = delegate
app.run()
