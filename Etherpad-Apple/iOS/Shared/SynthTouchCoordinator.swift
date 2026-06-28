import Foundation

/// Routes touch surface events to any `SynthEngineProtocol` (standalone or AU).
final class SynthTouchCoordinator: TouchSurfaceDelegate {
    weak var engine: SynthEngineProtocol?

    func touchBegan(slot: Int, x: Float, y: Float) {
        engine?.noteOn(slot: slot, x: x, y: y)
    }

    func touchMoved(slot: Int, x: Float, y: Float) {
        engine?.updatePosition(slot: slot, x: x, y: y)
    }

    func touchEnded(slot: Int) {
        engine?.noteOff(slot: slot)
    }
}
