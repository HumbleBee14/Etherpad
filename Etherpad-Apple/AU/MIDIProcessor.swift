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

    // Per-note (MIDI 2.0 / MPE) modulation, additive on top of channel-wide.
    private var perNoteBend: [Float] = Array(repeating: 0, count: SynthVoiceLayout.maxTouches)       // −1…+1
    private var perNoteBrightness: [Float] = Array(repeating: 0, count: SynthVoiceLayout.maxTouches) //  0…1

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

    /// Single engine-facing choke point. Both the MIDI 1.0 and MIDI 2.0 paths feed this.
    private func dispatch(_ msg: MIDI2Message) {
        switch msg {
        case let .noteOn(note, vel16):
            noteOn(note: note, velocity: UInt8(MIDI2Scale.velocity(vel16) * 127))
        case let .noteOff(note, _):
            noteOff(note: note)
        case let .controlChange(index, value32):
            controlChange(cc: index, value: UInt8(MIDI2Scale.unipolar(value32) * 127))
        case let .channelPitchBend(value32):
            pitchBendValue = MIDI2Scale.bipolar(value32)
            updateActiveVoicePositions()
        case let .channelPressure(value32):
            channelAftertouchValue = MIDI2Scale.unipolar(value32)
            updateActiveVoicePositions()
        case let .polyPressure(note, value32):
            polyAftertouch(note: note, value: UInt8(MIDI2Scale.unipolar(value32) * 127))
        case let .perNotePitchBend(note, value32):
            if let slot = noteToSlot[Int(note)] {
                perNoteBend[slot] = MIDI2Scale.bipolar(value32)
                updateActiveVoicePositions()
            }
        case let .perNoteController(note, index, value32):
            if index == 74, let slot = noteToSlot[Int(note)] {
                perNoteBrightness[slot] = MIDI2Scale.unipolar(value32)
                updateActiveVoicePositions()
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
        for i in 0..<SynthVoiceLayout.maxTouches {
            perNoteBend[i] = 0
            perNoteBrightness[i] = 0
        }
    }

    // MARK: - MIDI Message Dispatch

    private func handleMIDI(_ event: AUMIDIEvent) {
        let status = event.data.0 & 0xF0
        let data1 = event.data.1
        let data2 = event.data.2

        switch status {
        case 0x90 where data2 > 0:
            dispatch(.noteOn(note: data1, velocity16: UInt16(data2) << 9))
        case 0x80, 0x90:
            dispatch(.noteOff(note: data1, velocity16: 0))
        case 0xB0:
            dispatch(.controlChange(index: data1, value32: UInt32(data2) << 25))
        case 0xE0:
            let combined = (UInt32(data2) << 7) | UInt32(data1)   // 14-bit
            dispatch(.channelPitchBend(value32: combined << 18))
        case 0xD0:
            dispatch(.channelPressure(value32: UInt32(data1) << 25))
        case 0xA0:
            dispatch(.polyPressure(note: data1, value32: UInt32(data2) << 25))
        default:
            break
        }
    }

    /// Parse a MIDI 2.0 UMP event list (iOS 15+). Walks packed UMP words, strides by
    /// message type, decodes Channel-Voice-2, and feeds the shared dispatcher.
    private func handleMIDIEventList(_ event: UnsafePointer<AURenderEvent>) {
        if #available(iOS 15.0, *) {
            event.withMemoryRebound(to: AUMIDIEventList.self, capacity: 1) { listEvent in
                var list = listEvent.pointee.eventList
                withUnsafeMutablePointer(to: &list.packet) { firstPacket in
                    var packet = firstPacket
                    for _ in 0..<list.numPackets {
                        parseUMPPacket(packet)
                        packet = MIDIEventPacketNext(packet)
                    }
                }
            }
        }
    }

    /// Walk the UMP words of one packet and dispatch each Channel-Voice-2 message.
    @available(iOS 15.0, *)
    private func parseUMPPacket(_ packet: UnsafeMutablePointer<MIDIEventPacket>) {
        let count = Int(packet.pointee.wordCount)
        guard count > 0 else { return }
        withUnsafeMutablePointer(to: &packet.pointee.words) { tuplePtr in
            tuplePtr.withMemoryRebound(to: UInt32.self, capacity: count) { words in
                var i = 0
                while i < count {
                    let word0 = words[i]
                    let mt = UInt8(word0 >> 28 & 0xF)
                    let stride = MIDI2UMPDecoder.wordCount(forMessageType: mt)
                    guard i + stride <= count else { break }
                    if mt == 0x4,
                       let msg = MIDI2UMPDecoder.decodeChannelVoice2(word0: word0, word1: words[i + 1]) {
                        dispatch(msg)
                    }
                    i += stride
                }
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
        perNoteBend[slot] = 0
        perNoteBrightness[slot] = 0
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

    // MARK: - Aftertouch

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
            y += perNoteBrightness[slot] * 0.15
            y = y.clamped01()

            // Modulate X with channel + per-note pitch bend (shift within surface range)
            let (baseX, _) = midiNoteToXY(note: note, velocity: UInt8(baseY * 127))
            let bendOffset = (pitchBendValue + perNoteBend[slot]) * 0.1  // ±10% of surface width
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
    /// Pad-emulation mode (XY-pad standard): each key = virtual finger on the pad.
    /// - **X** → pad line from scale-aware chroma **plus octave offset** vs patch base
    ///   (so C5 and C6 batches differ, not clones). Size sets line count dynamically.
    /// - **Y** → velocity; passing/black keys use lower Y on the same nearest line.
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

    /// Pad line 0…size−1. Within-octave chroma slot + octave offset from patch base.
    private func padEmulationPadStep(note: UInt8, patchState: SynthPatchState) -> Int {
        let gisize = patchState.size
        guard gisize > 1 else { return 0 }

        let withinOctave = chromaPadStep(note: note, patchState: patchState)
        let octaveShift = octaveShiftFromBase(note: note, patchState: patchState)
        return min(gisize - 1, max(0, withinOctave + octaveShift))
    }

    /// Octaves above/below patch Key+Octave base → +1/−1 pad line per 12 semitones.
    private func octaveShiftFromBase(note: UInt8, patchState: SynthPatchState) -> Int {
        let baseNote = patchState.key + 12 * (patchState.octave + 1)
        return (Int(note) - baseNote) / 12
    }

    /// Pad line for chroma within one octave (before octave offset is applied).
    private func chromaPadStep(note: UInt8, patchState: SynthPatchState) -> Int {
        let chroma = keyRelativeChroma(note: note, key: patchState.key)
        let gisize = patchState.size

        guard let scaleSteps = SynthCatalog.scaleSteps(named: patchState.scaleName),
              !scaleSteps.isEmpty,
              scaleSteps.first! >= 0 else {
            return chromaticPadStep(chroma: chroma, gisize: gisize)
        }

        let n = min(gisize, scaleSteps.count)

        for i in 0..<n where scaleSteps[i] % 12 == chroma {
            return i
        }

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
