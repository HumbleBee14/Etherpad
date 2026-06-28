import AudioToolbox

/// Converts touch pad gestures to MIDI note/CC events for host routing.
///
/// When the user touches the pad inside the AUv3 plugin, this handler
/// generates MIDI Note On/Off and CC messages that hosts like AUM can
/// route to other instruments in the chain.
final class MIDIOutputHandler {

    /// Set by the audio unit from its `midiOutputEventBlock` property.
    var midiOutputBlock: AUMIDIOutputEventBlock?

    /// Current patch state for XY ↔ MIDI note conversion (thread-safe).
    private let patchBox = RealtimePatchState()

    var patchState: SynthPatchState {
        get { patchBox.snapshot() }
        set { patchBox.value = newValue }
    }

    /// Master enable/disable for MIDI output.
    var isEnabled: Bool = true

    /// Tracks active MIDI notes per voice slot.
    private var activeNotes: [Int: UInt8] = [:]

    /// Tracks last sent CC74 per slot to avoid redundant messages.
    private var lastBrightness: [Int: UInt8] = [:]

    // MARK: - Touch Events → MIDI

    /// Call when a touch begins on the pad. Sends MIDI Note On.
    func touchBegan(slot: Int, x: Float, y: Float) {
        guard isEnabled, let block = midiOutputBlock else { return }

        let (note, velocity) = xyToMIDINote(x: x, y: y)
        activeNotes[slot] = note
        lastBrightness[slot] = nil

        sendNoteOn(note: note, velocity: velocity, via: block)
    }

    /// Call when a touch moves on the pad. Sends CC74 (brightness) from Y.
    func touchMoved(slot: Int, x: Float, y: Float) {
        guard isEnabled, let block = midiOutputBlock else { return }
        guard activeNotes[slot] != nil else { return }

        // Send CC74 (Brightness/Timbre) mapped from Y position
        let brightness = UInt8(max(0, min(127, Int(y * 127))))
        if lastBrightness[slot] != brightness {
            lastBrightness[slot] = brightness
            sendCC(cc: 74, value: brightness, via: block)
        }
    }

    /// Call when a touch ends on the pad. Sends MIDI Note Off.
    func touchEnded(slot: Int) {
        guard isEnabled, let block = midiOutputBlock else { return }
        guard let note = activeNotes.removeValue(forKey: slot) else { return }
        lastBrightness[slot] = nil

        sendNoteOff(note: note, via: block)
    }

    /// Release all active MIDI output notes.
    func allNotesOff() {
        guard let block = midiOutputBlock else {
            activeNotes.removeAll()
            lastBrightness.removeAll()
            return
        }

        for (_, note) in activeNotes {
            sendNoteOff(note: note, via: block)
        }
        activeNotes.removeAll()
        lastBrightness.removeAll()
    }

    // MARK: - XY → MIDI Note Conversion

    /// Convert surface (x, y) coordinates to MIDI note and velocity.
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
            // Special scales (Bohlen-Pierce, Overtone): linear approximation
            midiNote = baseNote + step
        }

        let clampedNote = UInt8(clamping: max(0, min(127, midiNote)))
        let velocity = UInt8(max(1, min(127, Int(y * 127))))
        return (clampedNote, velocity)
    }

    // MARK: - MIDI Send Helpers

    private func sendNoteOn(note: UInt8, velocity: UInt8, via block: AUMIDIOutputEventBlock) {
        var data: (UInt8, UInt8, UInt8) = (0x90, note, velocity)
        withUnsafeMutablePointer(to: &data) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 3) { bytes in
                block(AUEventSampleTimeImmediate, 0, 3, bytes)
            }
        }
    }

    private func sendNoteOff(note: UInt8, via block: AUMIDIOutputEventBlock) {
        var data: (UInt8, UInt8, UInt8) = (0x80, note, 0)
        withUnsafeMutablePointer(to: &data) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 3) { bytes in
                block(AUEventSampleTimeImmediate, 0, 3, bytes)
            }
        }
    }

    private func sendCC(cc: UInt8, value: UInt8, via block: AUMIDIOutputEventBlock) {
        var data: (UInt8, UInt8, UInt8) = (0xB0, cc, value)
        withUnsafeMutablePointer(to: &data) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 3) { bytes in
                block(AUEventSampleTimeImmediate, 0, 3, bytes)
            }
        }
    }
}
