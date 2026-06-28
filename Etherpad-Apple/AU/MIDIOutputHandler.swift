import AudioToolbox

// MARK: - MIDI Output Handler

/// Converts touch-surface gestures into outgoing MIDI events, allowing hosts
/// to record or route the Etherpad's performance as standard MIDI data.
///
/// Each active touch slot is assigned a MIDI note based on the current
/// `SynthPatchState` (scale, key, octave, size). Continuous Y-axis movement
/// is transmitted as CC 74 (Brightness / Sound Controller 5).
///
/// **Usage**: Set `midiOutputBlock` from the AUAudioUnit's `outputProvider`
/// and call `touchBegan`, `touchMoved`, `touchEnded` from the touch surface.
final class MIDIOutputHandler {

    // MARK: - Public Properties

    /// The host-provided block for sending MIDI output events.
    /// Set this from `AUAudioUnit.midiOutputEventBlock`.
    var midiOutputBlock: AUMIDIOutputEventBlock?

    /// Current patch state, used to map XY coordinates to MIDI notes.
    var patchState: SynthPatchState = .factoryDefault

    /// Master enable. When `false`, no MIDI events are emitted.
    var isEnabled: Bool = true

    // MARK: - Private State

    /// Maps active voice slot → currently sounding MIDI note number.
    private var activeNotes: [Int: UInt8] = [:]

    // MARK: - Touch Events

    /// Called when a new touch begins on the performance surface.
    ///
    /// Converts the touch position to a MIDI note and sends a Note On message.
    ///
    /// - Parameters:
    ///   - slot: Voice slot index (0 ..< `SynthVoiceLayout.maxTouches`).
    ///   - x: Horizontal position, 0 (right) to 1 (left).
    ///   - y: Vertical position / dynamics, 0 (soft) to 1 (loud).
    func touchBegan(slot: Int, x: Float, y: Float) {
        guard isEnabled else { return }

        let (note, velocity) = xyToMIDINote(x: x, y: y)

        // Release any existing note on this slot (safety).
        if let previousNote = activeNotes[slot] {
            sendNoteOff(note: previousNote)
        }

        activeNotes[slot] = note
        sendNoteOn(note: note, velocity: velocity)
    }

    /// Called when an active touch moves on the performance surface.
    ///
    /// Sends CC 74 (Brightness) derived from the Y-axis position.
    ///
    /// - Parameters:
    ///   - slot: Voice slot index.
    ///   - x: Updated horizontal position.
    ///   - y: Updated vertical position / dynamics.
    func touchMoved(slot: Int, x: Float, y: Float) {
        guard isEnabled, activeNotes[slot] != nil else { return }

        let ccValue = UInt8(max(0, min(127, Int(y * 127))))
        sendCC(controller: 74, value: ccValue)
    }

    /// Called when a touch ends on the performance surface.
    ///
    /// Sends a Note Off for the slot's active note.
    ///
    /// - Parameter slot: Voice slot index.
    func touchEnded(slot: Int) {
        guard isEnabled, let note = activeNotes.removeValue(forKey: slot) else { return }
        sendNoteOff(note: note)
    }

    /// Releases all currently active notes.
    func allNotesOff() {
        for (slot, note) in activeNotes {
            sendNoteOff(note: note)
            activeNotes.removeValue(forKey: slot)
        }
    }

    // MARK: - XY → MIDI Conversion

    /// Converts an (x, y) touch coordinate to a MIDI note number and velocity,
    /// respecting the current patch state's scale, key, octave, and size.
    ///
    /// - Parameters:
    ///   - x: Horizontal position, 0 (right) to 1 (left). Inverted internally
    ///        so that leftward movement goes up the scale.
    ///   - y: Vertical position mapped to velocity (0.0 → 1, 1.0 → 127).
    /// - Returns: A tuple of `(note, velocity)` clamped to valid MIDI range.
    private func xyToMIDINote(x: Float, y: Float) -> (note: UInt8, velocity: UInt8) {
        let kx = 1.0 - x
        let step = Int(kx * Float(patchState.size))
        let baseNote = patchState.key + 12 * (patchState.octave + 1)

        var midiNote: Int
        if let scaleSteps = SynthCatalog.scaleSteps(named: patchState.scaleName),
           scaleSteps.first(where: { $0 >= 0 }) != nil {
            midiNote = baseNote + scaleSteps[min(step, scaleSteps.count - 1)]
        } else {
            midiNote = baseNote + step
        }

        let clampedNote = UInt8(clamping: max(0, min(127, midiNote)))
        let velocity = UInt8(max(1, min(127, Int(y * 127))))
        return (clampedNote, velocity)
    }

    // MARK: - MIDI Message Senders

    /// Sends a MIDI Note On (status 0x90, channel 0).
    private func sendNoteOn(note: UInt8, velocity: UInt8) {
        sendMIDIBytes([0x90, note, velocity])
    }

    /// Sends a MIDI Note Off (status 0x80, channel 0).
    private func sendNoteOff(note: UInt8) {
        sendMIDIBytes([0x80, note, 0x40]) // Release velocity 64
    }

    /// Sends a MIDI Control Change (status 0xB0, channel 0).
    private func sendCC(controller: UInt8, value: UInt8) {
        sendMIDIBytes([0xB0, controller, value])
    }

    /// Transmits raw MIDI bytes through the host-provided output block.
    ///
    /// Uses `withUnsafeMutableBufferPointer` for safe, allocation-free access.
    private func sendMIDIBytes(_ bytes: [UInt8]) {
        guard let block = midiOutputBlock else { return }

        var data = bytes
        data.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = block(AUEventSampleTimeImmediate, 0, buffer.count, baseAddress)
        }
    }
}
