import AppKit
import CoreVideo
import QuartzCore

protocol MacTouchDelegate: AnyObject {
    func touchBegan(slot: Int, x: Float, y: Float)
    func touchMoved(slot: Int, x: Float, y: Float)
    func touchEnded(slot: Int)
}

final class MacSurfaceView: NSView {
    weak var delegate: MacTouchDelegate?

    var numberOfNotes: Double = 8.0 {
        didSet { if numberOfNotes != oldValue { needsDisplay = true } }
    }

    private var effects: VisualEffects = .current

    private var activePoints: [Int: CGPoint] = [:]
    let maxSlots = MacCsoundEngine.maxTouches

    private let bgColor     = NSColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)
    private let lineColor   = NSColor(red: 0x50/255, green: 0x72/255, blue: 0xA7/255, alpha: 1)
    private let circleColor = NSColor(red: 233/255, green: 214/255, blue: 107/255, alpha: 0.5)
    private let glowColor   = NSColor(red: 233/255, green: 214/255, blue: 107/255, alpha: 0.07)
    private let baseRadius: CGFloat = 60
    private let lineWidth: CGFloat = 3

    private struct Ripple { var origin: CGPoint; var t: CFTimeInterval }
    private var ripples: [Ripple] = []
    private static let rippleDuration: CFTimeInterval = 0.8
    private static let rippleMaxRadius: CGFloat = 220

    private struct TrailPoint { var p: CGPoint; var t: CFTimeInterval }
    private var trails: [Int: [TrailPoint]] = [:]
    private static let trailDuration: CFTimeInterval = 1.2

    private var displayLink: CVDisplayLink?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    var multitouchActive = false {
        didSet {
            if multitouchActive { startSafetySweep() } else { stopSafetySweep(); cancelAllTouches() }
            needsDisplay = true
        }
    }
    private var touchSlots: [NSObject: Int] = [:]
    private var lastTouchEvent: TimeInterval = 0
    private var safetyTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
        NotificationCenter.default.addObserver(
            self, selector: #selector(effectsChanged),
            name: .visualEffectsChanged, object: nil)
    }

    deinit {
        stopDisplayLink()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func effectsChanged() {
        effects = .current
        updateDisplayLink()
        needsDisplay = true
    }

    private func updateDisplayLink() {
        let needsAnimation = effects.contains(.ripple) || effects.contains(.trail)
        if needsAnimation && displayLink == nil {
            var link: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&link)
            guard let link else { return }
            CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo -> CVReturn in
                let view = Unmanaged<MacSurfaceView>.fromOpaque(userInfo!).takeUnretainedValue()
                DispatchQueue.main.async { view.tick() }
                return kCVReturnSuccess
            }, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(link)
            displayLink = link
        } else if !needsAnimation {
            stopDisplayLink()
        }
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        ripples.removeAll { now - $0.t > Self.rippleDuration }
        for key in trails.keys {
            trails[key]?.removeAll { now - $0.t > Self.trailDuration }
        }
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDisplayLink()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let now = CACurrentMediaTime()

        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(bounds)

        if effects.contains(.columnGlow), numberOfNotes > 0 {
            let cols = CGFloat(numberOfNotes)
            let colW = bounds.width / cols
            ctx.setFillColor(glowColor.cgColor)
            for (_, p) in activePoints {
                let idx = max(0, min(Int(cols) - 1, Int(p.x / colW)))
                let r = CGRect(x: CGFloat(idx) * colW, y: 0, width: colW, height: bounds.height)
                ctx.fill(r)
            }
        }

        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineJoin(.round)
        let noteCount = max(numberOfNotes, 1)
        if Int(noteCount) > 1 {
            for i in 1..<Int(noteCount) {
                let x = bounds.width / CGFloat(noteCount) * CGFloat(i)
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: bounds.height))
            }
            ctx.strokePath()
        }

        if effects.contains(.trail) {
            for (_, pts) in trails {
                for tp in pts {
                    let age = now - tp.t
                    let life = max(0, 1 - age / Self.trailDuration)
                    let alpha = life * 0.35
                    let r: CGFloat = 18 * (0.3 + 0.7 * CGFloat(life))
                    ctx.setFillColor(NSColor(red: 233/255, green: 214/255, blue: 107/255,
                                             alpha: alpha).cgColor)
                    ctx.fillEllipse(in: CGRect(x: tp.p.x - r, y: tp.p.y - r, width: r * 2, height: r * 2))
                }
            }
        }

        if effects.contains(.ripple) {
            for ring in ripples {
                let age = now - ring.t
                let p = CGFloat(age / Self.rippleDuration)
                let radius = Self.rippleMaxRadius * p
                let alpha = max(0, 1 - p) * 0.6
                ctx.setStrokeColor(NSColor(red: 233/255, green: 214/255, blue: 107/255,
                                           alpha: alpha).cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: ring.origin.x - radius,
                                             y: ring.origin.y - radius,
                                             width: radius * 2, height: radius * 2))
            }
        }

        ctx.setFillColor(circleColor.cgColor)
        for (_, p) in activePoints {
            let scale: CGFloat
            if effects.contains(.intensity) {
                let y = p.y / bounds.height
                scale = 0.5 + y * 0.7
            } else {
                scale = 1
            }
            let r = baseRadius * scale
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

    private func normalised(_ p: CGPoint) -> (Float, Float) {
        let x = Float(p.x / max(bounds.width, 1)).clampedUnit()
        let y = Float(p.y / max(bounds.height, 1)).clampedUnit()
        return (x, y)
    }

    private func noteTouch(at slot: Int, point p: CGPoint) {
        if effects.contains(.ripple) {
            ripples.append(Ripple(origin: p, t: CACurrentMediaTime()))
        }
        if effects.contains(.trail) {
            trails[slot] = [TrailPoint(p: p, t: CACurrentMediaTime())]
        }
    }

    private func moveTouch(at slot: Int, point p: CGPoint) {
        if effects.contains(.trail) {
            trails[slot, default: []].append(TrailPoint(p: p, t: CACurrentMediaTime()))
        }
    }

    func cancelAllTouches() {
        for (slot, _) in activePoints { delegate?.touchEnded(slot: slot) }
        activePoints.removeAll()
        touchSlots.removeAll()
        trails.removeAll()
        mouseActive = false
        needsDisplay = true
    }

    // MARK: - Mouse (normal mode)
    private var mouseActive = false

    override func mouseDown(with event: NSEvent) {
        guard !multitouchActive else { return }
        let p = convert(event.locationInWindow, from: nil)
        mouseActive = true
        activePoints[0] = p
        noteTouch(at: 0, point: p)
        let (x, y) = normalised(p)
        delegate?.touchBegan(slot: 0, x: x, y: y)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !multitouchActive, mouseActive else { return }
        let p = convert(event.locationInWindow, from: nil)
        activePoints[0] = p
        moveTouch(at: 0, point: p)
        let (x, y) = normalised(p)
        delegate?.touchMoved(slot: 0, x: x, y: y)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !multitouchActive, mouseActive else { return }
        mouseActive = false
        activePoints[0] = nil
        delegate?.touchEnded(slot: 0)
        needsDisplay = true
    }

    override func magnify(with event: NSEvent)  { if !multitouchActive { super.magnify(with: event) } }
    override func rotate(with event: NSEvent)   { if !multitouchActive { super.rotate(with: event) } }
    override func swipe(with event: NSEvent)    { if !multitouchActive { super.swipe(with: event) } }
    override func scrollWheel(with event: NSEvent) { if !multitouchActive { super.scrollWheel(with: event) } }
    override func smartMagnify(with event: NSEvent) { if !multitouchActive { super.smartMagnify(with: event) } }

    // MARK: - Trackpad multitouch
    private func nextFreeSlot() -> Int? {
        let used = Set(touchSlots.values)
        return (0..<maxSlots).first { !used.contains($0) }
    }

    private func viewPoint(_ t: NSTouch) -> CGPoint {
        CGPoint(x: CGFloat(t.normalizedPosition.x) * bounds.width,
                y: CGFloat(t.normalizedPosition.y) * bounds.height)
    }

    override func touchesBegan(with event: NSEvent) {
        guard multitouchActive else { return }
        lastTouchEvent = event.timestamp
        for t in event.touches(matching: .began, in: self) {
            guard let id = t.identity as? NSObject, touchSlots[id] == nil,
                  let slot = nextFreeSlot() else { continue }
            touchSlots[id] = slot
            let p = viewPoint(t)
            activePoints[slot] = p
            noteTouch(at: slot, point: p)
            delegate?.touchBegan(slot: slot,
                                 x: Float(t.normalizedPosition.x),
                                 y: Float(t.normalizedPosition.y))
        }
        needsDisplay = true
    }

    override func touchesMoved(with event: NSEvent) {
        guard multitouchActive else { return }
        for t in event.touches(matching: .moved, in: self) {
            guard let id = t.identity as? NSObject, let slot = touchSlots[id] else { continue }
            let p = viewPoint(t)
            activePoints[slot] = p
            moveTouch(at: slot, point: p)
            delegate?.touchMoved(slot: slot,
                                 x: Float(t.normalizedPosition.x),
                                 y: Float(t.normalizedPosition.y))
        }
        reconcileActiveTouches(event)
        needsDisplay = true
    }

    override func touchesEnded(with event: NSEvent) {
        for t in event.touches(matching: .ended, in: self) {
            guard let id = t.identity as? NSObject, let slot = touchSlots.removeValue(forKey: id)
            else { continue }
            activePoints[slot] = nil
            delegate?.touchEnded(slot: slot)
        }
        reconcileActiveTouches(event)
        needsDisplay = true
    }

    override func touchesCancelled(with event: NSEvent) {
        cancelAllTouches()
    }

    private func reconcileActiveTouches(_ event: NSEvent) {
        lastTouchEvent = event.timestamp
        let live = Set(event.touches(matching: .touching, in: self).compactMap { $0.identity as? NSObject })
        for (id, slot) in touchSlots where !live.contains(id) {
            touchSlots.removeValue(forKey: id)
            activePoints[slot] = nil
            delegate?.touchEnded(slot: slot)
        }
    }

    private func startSafetySweep() {
        stopSafetySweep()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, !self.touchSlots.isEmpty else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastTouchEvent > 0.3 {
                self.cancelAllTouches()
            }
        }
    }
    private func stopSafetySweep() {
        safetyTimer?.invalidate(); safetyTimer = nil
    }
}

private extension Float {
    func clampedUnit() -> Float { min(max(self, 0), 1) }
}
