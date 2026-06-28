import AudioToolbox
import AVFAudio

/// Comprehensive, realtime MIDI processor for the Etherpad AUv3 render thread.
///
/// Handles Note On/Off, Pitch Bend, CC (Mod Wheel, Expression, Sustain, Brightness,
/// All Notes Off), Channel/Poly Aftertouch, and MIDI 2.0 UMP events.
///
/// The processor maintains its own note→slot tracking and sustain pedal state.
/// It reads `patchState` to map MIDI notes to correct XY coordinates for the
/// current scale, key, and octave configuration.
final class MIDIProcessor {

    // MARK: - Dependencies

    /// The synth engine to drive. Set before render resources are allocated.
    weak var engine: SynthEngineProtocol?

    /// Current patch state — written from main thread, read from audio thread.
    /// Csound handles its own thread safety for the values that flow through.
    var patchState: SynthPatchState = .factoryDefault

    // MARK: - Note Tracking

    /// Maps MIDI note number → voice slot (fixed-size for realtime safety).
    private var noteToSlot: [Int?] = Array(repeating: nil, count: 128)

    /// Maps voice slot → MIDI note number.
    private var slotToNote: [UInt8?] = Array(repeating: nil, count: SynthVoiceLayout.maxTouches)

    /// Maps voice slot → current Y value (for modulation).
    private var slotBaseY: [Float] = Array(repeating: 0, count: SynthVoiceLayout.maxTouches)

    // MARK: - Controller State

    private var sustainPedalOn = false
    private var sustainedSlots: Set<Int> = []
    private var modWheelValue: Float = 0      // CC1, 0…1
    private var expressionValue: Float = 1.0   // CC11, 0…1
    private var brightnessValue: Float = 0     // CC74, 0…1
    private var channelAftertouchValue: Float = 0  // 0…1
    private var pitchBendValue: Float = 0      // -1…+1

    // MARK: - Public API

    /// Process all render events in the `AURenderEvent` linked list.
    /// Called from the audio render thread.
    func processRenderEvents(_ head: UnsafePointer<AURenderEvent>) {
        var event: UnsafePointer<AURenderEvent>? = head
        while let current = event {
            switch current.pointee.head.eventType {
            case .MIDI:
                handleMIDI(current.pointee.MIDI)
            case .midiEventList:
                handleMIDIEventList(current)
            default:
                break
            }
            if let next = current.pointee.head.next {
                event = UnsafePointer(next)
            } else {
                break
            }
        }
    }

    /// Release all active MIDI-triggered voices.
    func allNotesOff() {
        for slot in 0..<SynthVoiceLayout.maxTouches {
            if slotToNote[slot] != nil {
                engine?.noteOff(slot: slot)
                if let note = slotToNote[slot] {
                    noteToSlot[Int(note)] = nil
                }
                slotToNote[slot] = nil
            }
        }
        sustainedSlots.removeAll()
        sustainPedalOn = false
        pitchBendValue = 0
        modWheelValue = 0
        expressionValue = 1.0
        brightnessValue = 0
        channelAftertouchValue = 0
    }

    // MARK: - MIDI Message Dispatch

    private func handleMIDI(_ event: AUMIDIEvent) {
        let status = event.data.0 & 0xF0
        let data1 = event.data.1
        let data2 = event.data.2

        switch status {
        case 0x90 where data2 > 0:
            noteOn(note: data1, velocity: data2)
        case 0x80, 0x90:
            noteOff(note: data1)
        case 0xB0:
            controlChange(cc: data1, value: data2)
        case 0xE0:
            pitchBend(lsb: data1, msb: data2)
        case 0xD0:
            channelAftertouch(value: data1)
        case 0xA0:
            polyAftertouch(note: data1, value: data2)
        default:
            break
        }
    }

    /// Handle MIDI 2.0 UMP event list (iOS 17+).
    private func handleMIDIEventList(_ event: UnsafePointer<AURenderEvent>) {
        // MIDI 2.0 UMP: extract the MIDIEventList from the render event.
        // On iOS 17+, we can iterate MIDIEventPackets.
        // For backward compatibility, we parse the legacy MIDI bytes if present.
        // Most hosts still send legacy MIDI events, so this is a forward-looking stub.
        if #available(iOS 17.0, *) {
            event.withMemoryRebound(to: AUMIDIEventList.self, capacity: 1) { listEvent in
                let eventList = listEvent.pointee.eventList
                // MIDIEventList contains MIDIEventPackets with UMP words.
                // Parse the first word to determine message type.
                // For now, hosts primarily send legacy MIDI which arrives as .MIDI events.
                _ = eventList // Future: iterate packets for MIDI 2.0 per-note controllers
            }
        }
    }

    // MARK: - Note On / Off

    private func noteOn(note: UInt8, velocity: UInt8) {
        guard let engine = engine else { return }

        // If this note is already active, release it first
        if let existingSlot = noteToSlot[Int(note)] {
            engine.noteOff(slot: existingSlot)
            slotToNote[existingSlot] = nil
            sustainedSlots.remove(existingSlot)
        }

        guard let slot = nextFreeSlot() else { return }

        let (x, y) = midiNoteToXY(note: note, velocity: velocity)

        noteToSlot[Int(note)] = slot
        slotToNote[slot] = note
        slotBaseY[slot] = y

        engine.noteOn(slot: slot, x: x, y: y)
    }

    private func noteOff(note: UInt8) {
        guard let slot = noteToSlot[Int(note)] else { return }

        if sustainPedalOn {
            sustainedSlots.insert(slot)
            return
        }

        releaseSlot(slot, note: note)
    }

    private func releaseSlot(_ slot: Int, note: UInt8) {
        engine?.noteOff(slot: slot)
        noteToSlot[Int(note)] = nil
        slotToNote[slot] = nil
        sustainedSlots.remove(slot)
    }

    // MARK: - Control Change

    private func controlChange(cc: UInt8, value: UInt8) {
        let normalised = Float(value) / 127.0

        switch cc {
        case 1:  // Mod Wheel
            modWheelValue = normalised
            updateActiveVoicePositions()

        case 11: // Expression
            expressionValue = normalised
            updateActiveVoicePositions()

        case 64: // Sustain Pedal
            if value >= 64 {
                sustainPedalOn = true
            } else {
                sustainPedalOn = false
                flushSustainedNotes()
            }

        case 74: // Brightness / MPE Slide
            brightnessValue = normalised
            updateActiveVoicePositions()

        case 123: // All Notes Off
            allNotesOff()

        case 120: // All Sound Off
            engine?.allNotesOff()
            allNotesOff()

        default:
            break
        }
    }

    // MARK: - Pitch Bend

    private func pitchBend(lsb: UInt8, msb: UInt8) {
        let combined = (Int(msb) << 7) | Int(lsb)
        pitchBendValue = Float(combined - 8192) / 8192.0  // -1…+1
        updateActiveVoicePositions()
    }

    // MARK: - Aftertouch

    private func channelAftertouch(value: UInt8) {
        channelAftertouchValue = Float(value) / 127.0
        updateActiveVoicePositions()
    }

    private func polyAftertouch(note: UInt8, value: UInt8) {
        guard let slot = noteToSlot[Int(note)], let engine = engine else { return }
        let aftertouch = Float(value) / 127.0
        let baseY = slotBaseY[slot]
        let modulatedY = (baseY + aftertouch * 0.3).clamped01()
        // Recalculate x from current note
        let (x, _) = midiNoteToXY(note: note, velocity: UInt8(baseY * 127))
        engine.updatePosition(slot: slot, x: x, y: modulatedY)
    }

    // MARK: - Voice Position Modulation

    /// Update all active MIDI-triggered voice positions based on current controller state.
    private func updateActiveVoicePositions() {
        guard let engine = engine else { return }
        for slot in 0..<SynthVoiceLayout.maxTouches {
            guard let note = slotToNote[slot] else { continue }
            let baseY = slotBaseY[slot]

            // Modulate Y with mod wheel, expression, brightness, and aftertouch
            var y = baseY * expressionValue
            y += modWheelValue * 0.2
            y += brightnessValue * 0.15
            y += channelAftertouchValue * 0.15
            y = y.clamped01()

            // Modulate X with pitch bend (shift within surface range)
            let (baseX, _) = midiNoteToXY(note: note, velocity: UInt8(baseY * 127))
            let bendOffset = pitchBendValue * 0.1  // ±10% of surface width
            let x = (baseX + bendOffset).clamped01()

            engine.updatePosition(slot: slot, x: x, y: y)
        }
    }

    // MARK: - Sustain Pedal

    private func flushSustainedNotes() {
        let slots = sustainedSlots
        sustainedSlots.removeAll()
        for slot in slots {
            guard let note = slotToNote[slot] else { continue }
            releaseSlot(slot, note: note)
        }
    }

    // MARK: - Slot Allocation

    private func nextFreeSlot() -> Int? {
        for i in 0..<SynthVoiceLayout.maxTouches {
            if slotToNote[i] == nil { return i }
        }
        return nil
    }

    // MARK: - Note ↔ XY Mapping

    /// Maps a MIDI note to surface (x, y) coordinates using the current patch state.
    ///
    /// The CSD flips x internally (`kx = 1 - kx`), so we compute x such that
    /// the engine produces the correct pitch for the given MIDI note.
    private func midiNoteToXY(note: UInt8, velocity: UInt8) -> (x: Float, y: Float) {
        let baseNote = patchState.key + 12 * (patchState.octave + 1)
        let targetSemitones = Int(note) - baseNote
        let y = max(Float(velocity) / 127.0, 0.05)

        // For ET scales with positive steps: find closest scale degree
        if let scaleSteps = SynthCatalog.scaleSteps(named: patchState.scaleName),
           let first = scaleSteps.first, first >= 0 {
            let numSteps = min(patchState.size, scaleSteps.count)
            guard numSteps > 0 else { return (0.5, y) }

            var bestStep = 0
            var bestDist = Int.max
            for i in 0..<numSteps {
                let dist = abs(scaleSteps[i] - targetSemitones)
                if dist < bestDist {
                    bestDist = dist
                    bestStep = i
                }
            }

            // CSD: kx = 1 - x_surface, kstep = scale(kx, 0, gisize)
            // So kx = step / gisize, and x_surface = 1 - step / gisize
            let x = 1.0 - Float(bestStep) / Float(max(numSteps, 1))
            return (x.clamped01(), y)
        }

        // For special scales (Bohlen-Pierce, Overtone): linear mapping
        let x = 1.0 - Float(targetSemitones) / Float(max(patchState.size, 1))
        return (x.clamped01(), y)
    }
}

// MARK: - Float Clamping

private extension Float {
    func clamped01() -> Float {
        Swift.min(Swift.max(self, 0), 1)
    }
}
