import AudioToolbox
import os

/// Touch gestures → MIDI out. UI thread enqueues; the render thread drains and is the
/// sole caller of `AUMIDIOutputEventBlock` (Apple requires it on the render thread).
final class MIDIOutputHandler {

    var midiOutputBlock: AUMIDIOutputEventBlock?

    private let patchBox = RealtimePatchState()

    var patchState: SynthPatchState {
        get { patchBox.snapshot() }
        set { patchBox.value = newValue }
    }

    var isEnabled: Bool = true

    // MARK: - Event Queue (UI producer → audio consumer)

    private enum EventKind { case noteOn, noteOff, cc }

    private struct OutEvent {
        let kind: EventKind
        let slot: Int
        let data1: UInt8   // note or cc number
        let data2: UInt8   // velocity or cc value
    }

    private let pending = OSAllocatedUnfairLock(initialState: [OutEvent]())

    private func enqueue(_ event: OutEvent) {
        pending.withLock { $0.append(event) }
    }

    // MARK: - Note Tracking (audio thread only)

    private var activeNotes = [UInt8?](repeating: nil, count: SynthVoiceLayout.maxTouches)
    private var lastBrightness = [Int16](repeating: -1, count: SynthVoiceLayout.maxTouches)

    // MARK: - Touch → MIDI (UI thread: enqueue only)

    func touchBegan(slot: Int, x: Float, y: Float) {
        guard isEnabled, (0..<SynthVoiceLayout.maxTouches).contains(slot) else { return }
        let (note, velocity) = xyToMIDINote(x: x, y: y)
        enqueue(OutEvent(kind: .noteOn, slot: slot, data1: note, data2: velocity))
    }

    func touchMoved(slot: Int, x: Float, y: Float) {
        guard isEnabled, (0..<SynthVoiceLayout.maxTouches).contains(slot) else { return }
        let brightness = UInt8(max(0, min(127, Int(y * 127))))
        enqueue(OutEvent(kind: .cc, slot: slot, data1: 74, data2: brightness))
    }

    // Release paths are not gated by isEnabled, so a note can always be turned off.
    func touchEnded(slot: Int) {
        guard (0..<SynthVoiceLayout.maxTouches).contains(slot) else { return }
        enqueue(OutEvent(kind: .noteOff, slot: slot, data1: 0, data2: 0))
    }

    func allNotesOff() {
        for slot in 0..<SynthVoiceLayout.maxTouches {
            enqueue(OutEvent(kind: .noteOff, slot: slot, data1: 0, data2: 0))
        }
    }

    /// Teardown only: render has stopped so the queue can't drain — send offs directly.
    func flushActiveNotesOffSync() {
        guard let block = midiOutputBlock else { return }
        for slot in 0..<SynthVoiceLayout.maxTouches {
            if let note = activeNotes[slot] {
                send(0x80, note, 0, at: AUEventSampleTimeImmediate, via: block)
                activeNotes[slot] = nil
                lastBrightness[slot] = -1
            }
        }
    }

    // MARK: - Render (audio thread)

    func render(at sampleTime: AUEventSampleTime) {
        // take the producer's buffer, leave it empty: O(1), no audio-thread copy
        let events = pending.withLock { state -> [OutEvent] in
            defer { state = [] }
            return state
        }
        guard !events.isEmpty, let block = midiOutputBlock else { return }

        for event in events {
            let slot = event.slot
            switch event.kind {
            case .noteOn:
                if let old = activeNotes[slot] {
                    send(0x80, old, 0, at: sampleTime, via: block)
                }
                activeNotes[slot] = event.data1
                lastBrightness[slot] = -1
                send(0x90, event.data1, event.data2, at: sampleTime, via: block)

            case .noteOff:
                if let note = activeNotes[slot] {
                    send(0x80, note, 0, at: sampleTime, via: block)
                    activeNotes[slot] = nil
                    lastBrightness[slot] = -1
                }

            case .cc:
                guard activeNotes[slot] != nil, lastBrightness[slot] != Int16(event.data2) else { continue }
                lastBrightness[slot] = Int16(event.data2)
                send(0xB0, event.data1, event.data2, at: sampleTime, via: block)
            }
        }
    }

    // MARK: - XY → MIDI Note Conversion (UI thread)

    private func xyToMIDINote(x: Float, y: Float) -> (note: UInt8, velocity: UInt8) {
        let patchState = patchBox.snapshot()
        // Reverse the CSD mapping: kx = 1 - x, kstep = kx * gisize
        let kx = 1.0 - x
        let step = Int(kx * Float(patchState.size))
        let baseNote = patchState.key + 12 * (patchState.octave + 1)

        var midiNote: Int
        if let scaleSteps = SynthCatalog.scaleSteps(named: patchState.scaleName),
           let first = scaleSteps.first, first >= 0 {
            let clampedStep = min(step, scaleSteps.count - 1)
            midiNote = baseNote + scaleSteps[max(0, clampedStep)]
        } else {
            midiNote = baseNote + step
        }

        let clampedNote = UInt8(clamping: max(0, min(127, midiNote)))
        let velocity = UInt8(max(1, min(127, Int(y * 127))))
        return (clampedNote, velocity)
    }

    // MARK: - MIDI Send (audio thread)

    private func send(_ status: UInt8, _ d1: UInt8, _ d2: UInt8,
                      at sampleTime: AUEventSampleTime, via block: AUMIDIOutputEventBlock) {
        var bytes: (UInt8, UInt8, UInt8) = (status, d1, d2)
        _ = withUnsafeMutablePointer(to: &bytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 3) { raw in
                block(sampleTime, 0, 3, raw)
            }
        }
    }
}
