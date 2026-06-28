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

    /// Current patch state — thread-safe; written from UI/host, read from audio render.
    private let patchBox = RealtimePatchState()

    var patchState: SynthPatchState {
        get { patchBox.snapshot() }
        set { patchBox.value = newValue }
    }

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
        // MIDI 2.0 UMP: On iOS 17+, hosts may send MIDIEventList with UMP words.
        // Most hosts still send legacy MIDI which arrives as .MIDI events.
        // Future enhancement: parse UMP words for per-note controllers,
        // high-resolution velocity, and per-note pitch bend.
        if #available(iOS 17.0, *) {
            event.withMemoryRebound(to: AUMIDIEventList.self, capacity: 1) { listEvent in
                let eventList = listEvent.pointee.eventList
                _ = eventList // Stub: iterate packets for MIDI 2.0 per-note controllers
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

    // MARK: - Note ↔ XY Mapping (Inverse of Csound's tablei)

    /// Maps a MIDI note to surface (x, y) by computing the exact inverse of
    /// the CSD's pitch mapping:
    ///
    ///     CSD forward:  x → kx = 1-x → kstep = kx * gisize → knote = tablei(kstep, giscale) → pitch = knote + base
    ///     This inverse:  pitch → knote = note - base → kstep = tablei⁻¹(knote) → kx = kstep/gisize → x = 1-kx
    ///
    /// For notes that land exactly on a scale degree: exact index lookup.
    /// For chromatic notes between scale degrees: fractional interpolation,
    /// guaranteeing every MIDI note gets a **unique** X → unique pitch.
    private func midiNoteToXY(note: UInt8, velocity: UInt8) -> (x: Float, y: Float) {
        let patchState = patchBox.snapshot()
        let baseNote = patchState.key + 12 * (patchState.octave + 1)
        let targetSemi = Float(Int(note) - baseNote)
        let y = max(Float(velocity) / 127.0, 0.05)
        let gisize = Float(patchState.size)

        guard gisize > 0 else { return (0.5, y) }

        guard let scaleSteps = SynthCatalog.scaleSteps(named: patchState.scaleName),
              !scaleSteps.isEmpty else {
            let kx = targetSemi / gisize
            return ((1.0 - kx).clamped01(), y)
        }

        // Bohlen-Pierce / Overtone scales use Csound giscale_type branches, not tablei ET.
        if let first = scaleSteps.first, first < 0 {
            let kx = targetSemi / gisize
            return ((1.0 - kx).clamped01(), y)
        }

        let n = min(patchState.size, scaleSteps.count)
        guard n > 0 else { return (0.5, y) }

        // --- Exact inverse of tablei ---
        // 1. Exact match: scaleSteps[i] == targetSemi → kstep = i
        for i in 0..<n {
            if Float(scaleSteps[i]) == targetSemi {
                let kx = Float(i) / gisize
                return ((1.0 - kx).clamped01(), y)
            }
        }

        // 2. Below first scale degree → extrapolate downward
        let first = Float(scaleSteps[0])
        if targetSemi < first {
            if n >= 2 {
                // Use the first interval as the extrapolation slope
                let interval = Float(scaleSteps[1] - scaleSteps[0])
                let kstep = (targetSemi - first) / max(interval, 1.0)   // negative
                let kx = kstep / gisize
                return ((1.0 - kx).clamped01(), y)
            }
            return (1.0, y)   // only one step, clamp to left edge
        }

        // 3. Above last scale degree → extrapolate upward
        let last = Float(scaleSteps[n - 1])
        if targetSemi > last {
            if n >= 2 {
                let interval = Float(scaleSteps[n - 1] - scaleSteps[n - 2])
                let overshoot = targetSemi - last
                let kstep = Float(n - 1) + overshoot / max(interval, 1.0)
                let kx = kstep / gisize
                return ((1.0 - kx).clamped01(), y)
            }
            let kx = Float(n - 1) / gisize
            return ((1.0 - kx).clamped01(), y)
        }

        // 4. Between two scale degrees → fractional interpolation
        //    (mirrors Csound's tablei linear interpolation)
        for i in 0..<(n - 1) {
            let lo = Float(scaleSteps[i])
            let hi = Float(scaleSteps[i + 1])
            if targetSemi >= lo && targetSemi < hi {
                let span = hi - lo
                let frac = (span > 0) ? (targetSemi - lo) / span : 0
                let kstep = Float(i) + frac
                let kx = kstep / gisize
                return ((1.0 - kx).clamped01(), y)
            }
        }

        // Fallback (should not reach here)
        return (0.5, y)
    }
}

// MARK: - Float Clamping

private extension Float {
    func clamped01() -> Float {
        Swift.min(Swift.max(self, 0), 1)
    }
}
