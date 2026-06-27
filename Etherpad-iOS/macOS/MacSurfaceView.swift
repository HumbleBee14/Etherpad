import AppKit

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

    private var activePoints: [Int: CGPoint] = [:]
    let maxSlots = MacCsoundEngine.maxTouches

    private let bgColor     = NSColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)
    private let lineColor   = NSColor(red: 0x50/255, green: 0x72/255, blue: 0xA7/255, alpha: 1)
    private let circleColor = NSColor(red: 233/255, green: 214/255, blue: 107/255, alpha: 0.5)
    private let baseRadius: CGFloat = 60
    private let lineWidth: CGFloat = 3

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    var multitouchActive = false {
        didSet {
            if !multitouchActive { cancelAllTouches() }
            needsDisplay = true
        }
    }
    private var touchSlots: [NSObject: Int] = [:]

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
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(bounds)

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

        ctx.setFillColor(circleColor.cgColor)
        for (_, p) in activePoints {
            let r = baseRadius
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

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

    // MARK: - Mouse (normal mode, single voice on slot 0)
    private var mouseActive = false

    override func mouseDown(with event: NSEvent) {
        guard !multitouchActive else { return }
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

    // Swallow gesture events while in Multitouch mode so they don't fire app/system
    // actions. OS-level gestures (e.g. Mission Control) are handled by WindowServer
    // first and can only be disabled in System Settings ▸ Trackpad.
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
