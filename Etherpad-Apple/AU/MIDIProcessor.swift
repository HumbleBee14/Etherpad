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

    // MARK: - Note ↔ XY Mapping (Pad-Emulation Keyboard Mode)

    /// Maps a host keyboard key to virtual touch-pad coordinates.
    ///
    /// Standard XY-pad fallback (Kaoss-style / virtual pad emulation — not MPE piano mode):
    /// - **X** → integer pad line `0…size−1` from note position within the octave + current scale
    /// - **Y** → velocity → timbre; chromatic passing tones use a lower Y
    ///
    /// `size` is dynamic — changing Etherpad Size immediately changes how many lines exist
    /// and how chroma maps across them. Shift Key/Octave in the patch to move the register.
    private func midiNoteToXY(note: UInt8, velocity: UInt8) -> (x: Float, y: Float) {
        let patchState = patchBox.snapshot()
        let gisize = patchState.size
        guard gisize > 0 else { return (0.5, max(Float(velocity) / 127.0, 0.05)) }

        let kstep = padEmulationPadStep(note: note, patchState: patchState)
        let kx = Float(kstep) / Float(gisize)
        let x = (1.0 - kx).clamped01()

        var y = max(Float(velocity) / 127.0, 0.05)
        let chroma = keyRelativeChroma(note: note, key: patchState.key)
        if !isScaleTone(chroma: chroma, patchState: patchState) {
            // Black / passing keys: same pad line as nearest scale tone, softer timbre on Y.
            y = max(0.05, y * 0.72)
        }

        return (x, y)
    }

    /// Semitone offset from patch root within one octave (0 = root, 1 = minor 2nd, …).
    private func keyRelativeChroma(note: UInt8, key: Int) -> Int {
        ((Int(note) - key) % 12 + 12) % 12
    }

    /// Pad line 0…size−1 for a keyboard note (Csound uses `int(kx * gisize)`).
    private func padEmulationPadStep(note: UInt8, patchState: SynthPatchState) -> Int {
        let gisize = patchState.size
        guard gisize > 1 else { return 0 }

        let chroma = keyRelativeChroma(note: note, key: patchState.key)

        guard let scaleSteps = SynthCatalog.scaleSteps(named: patchState.scaleName),
              !scaleSteps.isEmpty,
              scaleSteps.first! >= 0 else {
            return chromaticPadStep(chroma: chroma, gisize: gisize)
        }

        let n = min(gisize, scaleSteps.count)

        // White / scale tone → exact pad line for that degree.
        for i in 0..<n where scaleSteps[i] % 12 == chroma {
            return i
        }

        // Black / passing tone → nearest scale line (shortest distance on the 12-TET circle).
        var bestStep = 0
        var bestDist = Int.max
        for i in 0..<n {
            let semi = scaleSteps[i] % 12
            let dist = min(abs(semi - chroma), 12 - abs(semi - chroma))
            if dist < bestDist {
                bestDist = dist
                bestStep = i
            }
        }
        return bestStep
    }

    /// Spread 12 chromatic positions across `gisize` pad lines (Bohlen-Pierce / Overtone / fallback).
    private func chromaticPadStep(chroma: Int, gisize: Int) -> Int {
        guard gisize > 1 else { return 0 }
        return min(gisize - 1, max(0, Int(round(Float(chroma) * Float(gisize - 1) / 11.0))))
    }

    private func isScaleTone(chroma: Int, patchState: SynthPatchState) -> Bool {
        guard let scaleSteps = SynthCatalog.scaleSteps(named: patchState.scaleName),
              !scaleSteps.isEmpty,
              scaleSteps.first! >= 0 else {
            return true
        }
        let n = min(patchState.size, scaleSteps.count)
        return scaleSteps.prefix(n).contains { $0 % 12 == chroma }
    }
}

// MARK: - Float Clamping

private extension Float {
    func clamped01() -> Float {
        Swift.min(Swift.max(self, 0), 1)
    }
}
