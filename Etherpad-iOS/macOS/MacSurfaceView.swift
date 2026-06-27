import AppKit

// macOS surface. Independent of the iOS TouchSurfaceView (UIKit); this is a fresh
// AppKit/Core Graphics implementation. Declares its own delegate protocol so no
// code is shared with iOS.
protocol MacTouchDelegate: AnyObject {
    func touchBegan(slot: Int, x: Float, y: Float)
    func touchMoved(slot: Int, x: Float, y: Float)
    func touchEnded(slot: Int)
}

final class MacSurfaceView: NSView {
    weak var delegate: MacTouchDelegate?

    // The surface is the first responder in Multitouch mode, so key events arrive
    // here. Return true if handled (so we don't beep / pass it on).
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    var numberOfNotes: Double = 8.0 {
        didSet { if numberOfNotes != oldValue { needsDisplay = true } }
    }

    // Active voice positions in VIEW coordinates (AppKit origin = bottom-left).
    private var activePoints: [Int: CGPoint] = [:]   // slot -> point
    let maxSlots = MacCsoundEngine.maxTouches

    private let bgColor     = NSColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)
    private let lineColor   = NSColor(red: 0x50/255, green: 0x72/255, blue: 0xA7/255, alpha: 1)
    private let circleColor = NSColor(red: 233/255, green: 214/255, blue: 107/255, alpha: 0.5)
    private let baseRadius: CGFloat = 60
    private let lineWidth: CGFloat = 3

    override var isFlipped: Bool { false }            // keep AppKit bottom-left origin
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Multitouch (trackpad) state
    var multitouchActive = false {
        didSet {
            if !multitouchActive { cancelAllTouches() }
            needsDisplay = true
        }
    }
    private var touchSlots: [NSObject: Int] = [:]     // NSTouch.identity -> slot

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        // Receive raw trackpad (indirect) multitouch; ignore resting palms/thumbs.
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(bounds)

        // Grid lines (vertical column dividers).
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

        // Active touch circles.
        ctx.setFillColor(circleColor.cgColor)
        for (_, p) in activePoints {
            let r = baseRadius
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

    // Normalize a VIEW point to (x,y) in [0,1], origin bottom-left, NO Y inversion
    // (AppKit and Csound channels both treat up as 1).
    private func normalised(_ p: CGPoint) -> (Float, Float) {
        let x = Float(p.x / max(bounds.width, 1)).clampedUnit()
        let y = Float(p.y / max(bounds.height, 1)).clampedUnit()
        return (x, y)
    }

    func cancelAllTouches() {
        for (slot, _) in activePoints { delegate?.touchEnded(slot: slot) }
        activePoints.removeAll()
        touchSlots.removeAll()
        mouseActive = false
        needsDisplay = true
    }

    // MARK: - Mouse (normal mode: single voice on slot 0)
    private var mouseActive = false

    override func mouseDown(with event: NSEvent) {
        guard !multitouchActive else { return }       // trackpad owns input in MT mode
        let p = convert(event.locationInWindow, from: nil)
        mouseActive = true
        activePoints[0] = p
        let (x, y) = normalised(p)
        delegate?.touchBegan(slot: 0, x: x, y: y)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !multitouchActive, mouseActive else { return }
        let p = convert(event.locationInWindow, from: nil)
        activePoints[0] = p
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

    // MARK: - Swallow gesture events in Multitouch mode
    // macOS turns some multi-finger movement into gesture events (magnify/rotate/
    // swipe/scroll). While in Multitouch mode we consume them here so they do NOT
    // trigger app/system gesture actions and so they don't compete with raw NSTouch
    // note generation. (NOTE: OS-level gestures handled entirely by WindowServer —
    // e.g. 3-finger Mission Control swipe — may still fire; those can only be turned
    // off in System Settings ▸ Trackpad. We suppress everything that reaches the app.)
    override func magnify(with event: NSEvent)  { if !multitouchActive { super.magnify(with: event) } }
    override func rotate(with event: NSEvent)   { if !multitouchActive { super.rotate(with: event) } }
    override func swipe(with event: NSEvent)    { if !multitouchActive { super.swipe(with: event) } }
    override func scrollWheel(with event: NSEvent) { if !multitouchActive { super.scrollWheel(with: event) } }
    override func smartMagnify(with event: NSEvent) { if !multitouchActive { super.smartMagnify(with: event) } }

    // MARK: - Trackpad multitouch (Multitouch mode: up to maxSlots voices)
    private func nextFreeSlot() -> Int? {
        let used = Set(touchSlots.values)
        return (0..<maxSlots).first { !used.contains($0) }
    }

    // NSTouch.normalizedPosition is already 0..1, origin bottom-left → maps directly.
    private func viewPoint(_ t: NSTouch) -> CGPoint {
        CGPoint(x: CGFloat(t.normalizedPosition.x) * bounds.width,
                y: CGFloat(t.normalizedPosition.y) * bounds.height)
    }

    override func touchesBegan(with event: NSEvent) {
        guard multitouchActive else { return }
        for t in event.touches(matching: .began, in: self) {
            guard let id = t.identity as? NSObject, touchSlots[id] == nil,
                  let slot = nextFreeSlot() else { continue }
            touchSlots[id] = slot
            activePoints[slot] = viewPoint(t)
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
            activePoints[slot] = viewPoint(t)
            delegate?.touchMoved(slot: slot,
                                 x: Float(t.normalizedPosition.x),
                                 y: Float(t.normalizedPosition.y))
        }
        needsDisplay = true
    }

    override func touchesEnded(with event: NSEvent) {
        for t in event.touches(matching: .ended, in: self) {
            guard let id = t.identity as? NSObject, let slot = touchSlots.removeValue(forKey: id)
            else { continue }
            activePoints[slot] = nil
            delegate?.touchEnded(slot: slot)
        }
        needsDisplay = true
    }

    override func touchesCancelled(with event: NSEvent) {
        for t in event.touches(matching: .cancelled, in: self) {
            guard let id = t.identity as? NSObject, let slot = touchSlots.removeValue(forKey: id)
            else { continue }
            activePoints[slot] = nil
            delegate?.touchEnded(slot: slot)
        }
        needsDisplay = true
    }
}

private extension Float {
    func clampedUnit() -> Float { min(max(self, 0), 1) }
}
