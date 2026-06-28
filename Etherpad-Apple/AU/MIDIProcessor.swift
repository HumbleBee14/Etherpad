import AudioToolbox
import AVFAudio

// MARK: - Float Clamping

private extension Float {
    /// Clamps the value to the given closed range.
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - MIDI Processor

/// Processes incoming MIDI events on the audio render thread and drives
/// voice slots on a `SynthEngineProtocol`.
///
/// This class is designed to be called exclusively from the AU's render block.
/// It manages a fixed pool of `SynthVoiceLayout.maxTouches` polyphonic slots,
/// a sustain pedal, and modulation state for pitch bend, expression, mod wheel,
/// aftertouch, and brightness.
///
/// **Thread safety**: `patchState` is written from the main thread and read from
/// the render thread. The struct is small and `Equatable`/`Codable`, so tearing
/// is functionally harmless (worst case: one render cycle uses a stale scale name).
final class MIDIProcessor {

    // MARK: - Public Properties

    /// The synth engine to drive. Set before the first render call.
    weak var engine: SynthEngineProtocol?

    /// Current patch state. Written from main thread, read from audio thread.
    var patchState: SynthPatchState = .factoryDefault

    // MARK: - Slot Tracking

    /// Maps MIDI note number → voice slot index.
    private var noteToSlot = [UInt8: Int]()

    /// Maps voice slot index → MIDI note number.
    private var slotToNote = [Int: UInt8]()

    // MARK: - Sustain Pedal

    /// Whether the sustain pedal (CC 64) is currently held.
    private var sustainPedalOn = false

    /// Slots whose note-off was deferred because the sustain pedal was down.
    private var sustainedSlots: Set<Int> = []

    // MARK: - Continuous Controllers

    /// Pitch bend value in the range -1…1 (0 = center).
    private var pitchBendValue: Float = 0.0

    /// Mod wheel (CC 1), normalized 0…1.
    private var modWheelValue: Float = 0.0

    /// Expression (CC 11), normalized 0…1, default fully open.
    private var expressionValue: Float = 1.0

    /// Brightness (CC 74), normalized 0…1.
    private var brightnessValue: Float = 0.0

    /// Channel aftertouch, normalized 0…1.
    private var channelAftertouchValue: Float = 0.0

    // MARK: - Render Entry Point

    /// Iterates the linked list of render events and dispatches MIDI messages.
    ///
    /// Call this at the top of every render cycle from `internalRenderBlock`.
    ///
    /// - Parameter head: Pointer to the first `AURenderEvent` in the linked list.
    func processRenderEvents(_ head: UnsafePointer<AURenderEvent>) {
        var event: UnsafePointer<AURenderEvent>? = head
        while let current = event {
            switch current.pointee.head.eventType {
            case .MIDI:
                handleMIDIEvent(current.pointee.MIDI)
            case .midiEventList:
                handleMIDIEventList(current)
            default:
                break
            }
            event = current.pointee.head.next?.assumingMemoryBound(to: AURenderEvent.self)
        }
    }

    /// Releases all active voices and resets controller state.
    func allNotesOff() {
        for (_, slot) in noteToSlot {
            engine?.noteOff(slot: slot)
        }
        noteToSlot.removeAll()
        slotToNote.removeAll()
        sustainedSlots.removeAll()
        sustainPedalOn = false
        pitchBendValue = 0.0
        modWheelValue = 0.0
        expressionValue = 1.0
        brightnessValue = 0.0
        channelAftertouchValue = 0.0
        engine?.allNotesOff()
    }

    // MARK: - MIDI 1.0 Dispatch

    /// Routes a 1–3 byte MIDI message to the appropriate handler.
    private func handleMIDIEvent(_ midi: AUMIDIEvent) {
        let status = midi.data.0 & 0xF0

        switch status {
        case 0x90: // Note On (or Note Off if velocity == 0)
            let note = midi.data.1
            let velocity = midi.data.2
            if velocity > 0 {
                handleNoteOn(note: note, velocity: velocity)
            } else {
                handleNoteOff(note: note)
            }

        case 0x80: // Note Off
            handleNoteOff(note: midi.data.1)

        case 0xE0: // Pitch Bend
            handlePitchBend(lsb: midi.data.1, msb: midi.data.2)

        case 0xB0: // Control Change
            handleCC(controller: midi.data.1, value: midi.data.2)

        case 0xD0: // Channel Aftertouch
            handleChannelAftertouch(pressure: midi.data.1)

        case 0xA0: // Polyphonic Aftertouch
            handlePolyAftertouch(note: midi.data.1, pressure: midi.data.2)

        default:
            break
        }
    }

    // MARK: - MIDI 2.0 / MIDIEventList

    /// Processes a `MIDIEventList`-based render event (iOS 17+).
    private func handleMIDIEventList(_ event: UnsafePointer<AURenderEvent>) {
        if #available(iOS 17.0, macOS 14.0, *) {
            // AURenderEvent.MIDIEventList contains a MIDIEventList.
            // We iterate its packets using the system-provided API.
            withUnsafePointer(to: event.pointee.MIDIEventList.eventList) { listPtr in
                // MIDIEventList is iterable via MIDIEventPacket on iOS 17+.
                let list = listPtr.pointee
                // Use the protocol-based iteration if available.
                var packet = list.packet  // first packet
                for _ in 0..<list.numPackets {
                    processMIDI2Packet(packet)
                    // Advance to next packet using the wordCount stride.
                    withUnsafePointer(to: packet) { pktPtr in
                        let raw = UnsafeRawPointer(pktPtr)
                        let stride = MemoryLayout<MIDIEventPacket>.offset(of: \.words)! + Int(packet.wordCount) * MemoryLayout<UInt32>.size
                        let nextRaw = raw.advanced(by: stride)
                        packet = nextRaw.assumingMemoryBound(to: MIDIEventPacket.self).pointee
                    }
                }
            }
        }
        // On older OS versions the host should not send MIDIEventList events,
        // but we silently ignore them if it does.
    }

    /// Extracts MIDI 1.0-equivalent data from a MIDI 2.0 universal packet.
    @available(iOS 17.0, macOS 14.0, *)
    private func processMIDI2Packet(_ packet: MIDIEventPacket) {
        guard packet.wordCount >= 1 else { return }

        let word0 = packet.words.0
        let messageType = (word0 >> 28) & 0xF

        switch messageType {
        case 0x2: // MIDI 1.0 Channel Voice (legacy wrapper)
            let status = UInt8((word0 >> 16) & 0xF0)
            let data1 = UInt8((word0 >> 8) & 0x7F)
            let data2 = UInt8(word0 & 0x7F)

            switch status {
            case 0x90:
                data2 > 0 ? handleNoteOn(note: data1, velocity: data2) : handleNoteOff(note: data1)
            case 0x80:
                handleNoteOff(note: data1)
            case 0xB0:
                handleCC(controller: data1, value: data2)
            case 0xE0:
                handlePitchBend(lsb: data1, msb: data2)
            case 0xD0:
                handleChannelAftertouch(pressure: data1)
            case 0xA0:
                handlePolyAftertouch(note: data1, pressure: data2)
            default:
                break
            }

        case 0x4: // MIDI 2.0 Channel Voice
            guard packet.wordCount >= 2 else { return }
            let status = UInt8((word0 >> 16) & 0xF0)
            let word1 = packet.words.1

            switch status {
            case 0x90: // Note On (MIDI 2.0: 32-bit velocity in word1 upper 16 bits)
                let note = UInt8((word0 >> 8) & 0x7F)
                let vel16 = UInt16(word1 >> 16)
                let velocity = UInt8(vel16 >> 9) // scale 16-bit to 7-bit
                velocity > 0 ? handleNoteOn(note: note, velocity: max(1, velocity)) : handleNoteOff(note: note)
            case 0x80: // Note Off
                let note = UInt8((word0 >> 8) & 0x7F)
                handleNoteOff(note: note)
            case 0xB0: // CC
                let cc = UInt8((word0 >> 8) & 0x7F)
                let val32 = word1
                let value = UInt8(val32 >> 25) // scale 32-bit to 7-bit
                handleCC(controller: cc, value: value)
            case 0xE0: // Pitch Bend (32-bit in word1)
                let bend32 = word1
                let bend14 = UInt16(bend32 >> 18) // scale to 14-bit
                handlePitchBend(lsb: UInt8(bend14 & 0x7F), msb: UInt8(bend14 >> 7))
            case 0xD0: // Channel Pressure
                let pressure32 = word1
                let pressure = UInt8(pressure32 >> 25)
                handleChannelAftertouch(pressure: pressure)
            default:
                break
            }

        default:
            break // System, Data, Utility messages — not handled
        }
    }

    // MARK: - Note Handlers

    /// Activates a new voice for the given MIDI note.
    private func handleNoteOn(note: UInt8, velocity: UInt8) {
        // If this note is already sounding, release it first.
        if let existingSlot = noteToSlot[note] {
            engine?.noteOff(slot: existingSlot)
            slotToNote.removeValue(forKey: existingSlot)
            noteToSlot.removeValue(forKey: note)
            sustainedSlots.remove(existingSlot)
        }

        guard let slot = nextFreeSlot() else { return }

        let (x, y) = midiNoteToXY(note: note, velocity: velocity)
        noteToSlot[note] = slot
        slotToNote[slot] = note
        engine?.noteOn(slot: slot, x: x, y: y)
    }

    /// Releases the voice for a MIDI note (or defers if sustain pedal is held).
    private func handleNoteOff(note: UInt8) {
        guard let slot = noteToSlot[note] else { return }

        if sustainPedalOn {
            sustainedSlots.insert(slot)
            return
        }

        engine?.noteOff(slot: slot)
        noteToSlot.removeValue(forKey: note)
        slotToNote.removeValue(forKey: slot)
    }

    // MARK: - Control Change Handlers

    /// Dispatches a MIDI CC to the appropriate handler.
    private func handleCC(controller: UInt8, value: UInt8) {
        let normalized = Float(value) / 127.0

        switch controller {
        case 1:   // Mod Wheel
            modWheelValue = normalized
            modulateActiveVoicesY()

        case 11:  // Expression
            expressionValue = normalized
            modulateActiveVoicesY()

        case 64:  // Sustain Pedal
            handleSustainPedal(value: value)

        case 74:  // Brightness (Sound Controller 5)
            brightnessValue = normalized
            modulateActiveVoicesY()

        case 123: // All Notes Off
            allNotesOff()

        default:
            break
        }
    }

    /// Toggles the sustain pedal and flushes deferred note-offs on release.
    private func handleSustainPedal(value: UInt8) {
        sustainPedalOn = value >= 64

        if !sustainPedalOn {
            // Release all sustained slots.
            for slot in sustainedSlots {
                if let note = slotToNote[slot] {
                    engine?.noteOff(slot: slot)
                    noteToSlot.removeValue(forKey: note)
                    slotToNote.removeValue(forKey: slot)
                }
            }
            sustainedSlots.removeAll()
        }
    }

    // MARK: - Pitch Bend

    /// Processes a 14-bit pitch bend message.
    private func handlePitchBend(lsb: UInt8, msb: UInt8) {
        let raw = (Int(msb) << 7) | Int(lsb)
        // Map 0…16383 to -1…1 (8192 = center).
        pitchBendValue = (Float(raw) - 8192.0) / 8192.0
        modulateActiveVoicesX()
    }

    // MARK: - Aftertouch

    /// Channel aftertouch modulates Y for all active voices.
    private func handleChannelAftertouch(pressure: UInt8) {
        channelAftertouchValue = Float(pressure) / 127.0
        modulateActiveVoicesY()
    }

    /// Polyphonic aftertouch modulates Y for a specific voice.
    private func handlePolyAftertouch(note: UInt8, pressure: UInt8) {
        guard let slot = noteToSlot[note] else { return }
        let baseY = computeBaseY(forSlot: slot)
        let afterY = Float(pressure) / 127.0
        let combinedY = (baseY + afterY * 0.3).clamped(to: 0...1)
        let x = computeCurrentX(forSlot: slot)
        engine?.updatePosition(slot: slot, x: x, y: combinedY)
    }

    // MARK: - Modulation Helpers

    /// Recalculates and updates X positions for all active voices (pitch bend).
    private func modulateActiveVoicesX() {
        for (note, slot) in noteToSlot {
            let (baseX, _) = midiNoteToXY(note: note, velocity: 100) // velocity irrelevant for X
            let modulatedX = (baseX + pitchBendValue * 0.1).clamped(to: 0...1)
            let y = computeBaseY(forSlot: slot)
            engine?.updatePosition(slot: slot, x: modulatedX, y: y)
        }
    }

    /// Recalculates and updates Y positions for all active voices.
    private func modulateActiveVoicesY() {
        for (note, slot) in noteToSlot {
            let (x, baseY) = midiNoteToXY(note: note, velocity: 100)
            let modulatedX = (x + pitchBendValue * 0.1).clamped(to: 0...1)
            let combinedY = computeModulatedY(baseY: baseY)
            engine?.updatePosition(slot: slot, x: modulatedX, y: combinedY)
        }
    }

    /// Computes the base Y for a slot by re-deriving from note/velocity context.
    ///
    /// Since we don't store the original velocity per-slot, we estimate using
    /// a neutral velocity. This keeps memory overhead minimal on the render thread.
    private func computeBaseY(forSlot slot: Int) -> Float {
        guard let note = slotToNote[slot] else { return 0.5 }
        let (_, y) = midiNoteToXY(note: note, velocity: 100)
        return computeModulatedY(baseY: y)
    }

    /// Computes the current X for a slot.
    private func computeCurrentX(forSlot slot: Int) -> Float {
        guard let note = slotToNote[slot] else { return 0.5 }
        let (baseX, _) = midiNoteToXY(note: note, velocity: 100)
        return (baseX + pitchBendValue * 0.1).clamped(to: 0...1)
    }

    /// Applies all Y-axis modulators (mod wheel, expression, brightness, aftertouch).
    private func computeModulatedY(baseY: Float) -> Float {
        var y = baseY
        y *= expressionValue                                // Expression scales
        y += modWheelValue * 0.2                            // Mod wheel adds vibrato-like Y
        y += brightnessValue * 0.15                         // Brightness nudges Y
        y += channelAftertouchValue * 0.25                  // Aftertouch boosts Y
        return y.clamped(to: 0...1)
    }

    // MARK: - Note ↔ XY Mapping

    /// Converts a MIDI note number and velocity to the (x, y) coordinate space
    /// expected by `SynthEngineProtocol.noteOn(slot:x:y:)`.
    ///
    /// X represents the position along the current scale (1.0 = leftmost/lowest step,
    /// 0.0 = rightmost/highest step). Y represents velocity/dynamics (0.05…1.0).
    ///
    /// When a named scale is active, the note is snapped to the closest scale step.
    /// For chromatic/unknown scales, semitone offset is used directly.
    private func midiNoteToXY(note: UInt8, velocity: UInt8) -> (x: Float, y: Float) {
        let baseNote = patchState.key + 12 * (patchState.octave + 1)
        let targetSemitones = Int(note) - baseNote
        let y = max(Float(velocity) / 127.0, 0.05)

        if let scaleSteps = SynthCatalog.scaleSteps(named: patchState.scaleName),
           scaleSteps.first(where: { $0 >= 0 }) != nil {
            let numSteps = min(patchState.size, scaleSteps.count)
            guard numSteps > 0 else { return (0.5, y) }
            var bestStep = 0
            var bestDist = Int.max
            for i in 0..<numSteps {
                let dist = abs(scaleSteps[i] - targetSemitones)
                if dist < bestDist { bestDist = dist; bestStep = i }
            }
            let x = 1.0 - Float(bestStep) / Float(max(numSteps, 1))
            return (x.clamped(to: 0...1), y)
        }

        // Fallback: linear semitone mapping.
        let x = 1.0 - Float(targetSemitones) / Float(max(patchState.size, 1))
        return (x.clamped(to: 0...1), y)
    }

    // MARK: - Slot Allocation

    /// Finds the next unused voice slot, or `nil` if all are occupied.
    private func nextFreeSlot() -> Int? {
        for i in 0..<SynthVoiceLayout.maxTouches {
            if slotToNote[i] == nil {
                return i
            }
        }
        return nil
    }
}
