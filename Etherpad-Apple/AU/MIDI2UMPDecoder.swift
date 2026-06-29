import Foundation

/// One normalized MIDI message, shared by the MIDI 1.0 and MIDI 2.0 paths.
enum MIDI2Message: Equatable {
    case noteOn(note: UInt8, velocity16: UInt16)
    case noteOff(note: UInt8, velocity16: UInt16)
    case controlChange(index: UInt8, value32: UInt32)
    case channelPitchBend(value32: UInt32)
    case perNotePitchBend(note: UInt8, value32: UInt32)
    case perNoteController(note: UInt8, index: UInt8, value32: UInt32)
    case channelPressure(value32: UInt32)
    case polyPressure(note: UInt8, value32: UInt32)
}

/// Stateless UMP Channel-Voice-2 decoder. Pure: no engine, no allocation.
enum MIDI2UMPDecoder {

    /// UMP word count for a top-nibble message type, used to stride packed words.
    static func wordCount(forMessageType nibble: UInt8) -> Int {
        switch nibble {
        case 0x0, 0x1, 0x2: return 1   // Utility, System, MIDI 1.0 CV
        case 0x3, 0x4:      return 2   // SysEx (7-bit), MIDI 2.0 CV
        case 0x5, 0xD, 0xF: return 4   // Data128, FlexData, Stream
        default:            return 1
        }
    }

    /// Decode one MIDI 2.0 Channel Voice message from its two words.
    static func decodeChannelVoice2(word0: UInt32, word1: UInt32) -> MIDI2Message? {
        guard UInt8(word0 >> 28 & 0xF) == 0x4 else { return nil }
        let status = UInt8(word0 >> 20 & 0xF)
        let index = UInt16(word0 & 0xFFFF)
        let note = UInt8(index >> 8 & 0x7F)
        let lowIndex = UInt8(index & 0xFF)

        switch status {
        case 0x9: return .noteOn(note: note, velocity16: UInt16(word1 >> 16 & 0xFFFF))
        case 0x8: return .noteOff(note: note, velocity16: UInt16(word1 >> 16 & 0xFFFF))
        case 0xB: return .controlChange(index: note, value32: word1)
        case 0xE: return .channelPitchBend(value32: word1)
        case 0x6: return .perNotePitchBend(note: note, value32: word1)
        case 0x0: return .perNoteController(note: note, index: lowIndex, value32: word1)
        case 0xD: return .channelPressure(value32: word1)
        case 0xA: return .polyPressure(note: note, value32: word1)
        default:  return nil
        }
    }

    /// Decode one MIDI 1.0 Channel Voice message carried in a single type-0x2 UMP word.
    /// CoreMIDI may deliver MIDI 1.0 input this way; up-converts to the shared 2.0 form
    /// so the engine path stays identical. word: [mt:4=2][grp:4][status:4][ch:4][d1:8][d2:8].
    static func decodeChannelVoice1(word0: UInt32) -> MIDI2Message? {
        guard UInt8(word0 >> 28 & 0xF) == 0x2 else { return nil }
        let status = UInt8(word0 >> 20 & 0xF)
        let data1 = UInt8(word0 >> 8 & 0x7F)
        let data2 = UInt8(word0 & 0x7F)

        switch status {
        case 0x9 where data2 > 0: return .noteOn(note: data1, velocity16: MIDI1Upscale.to16(data2))
        case 0x8, 0x9:            return .noteOff(note: data1, velocity16: 0)
        case 0xB:                 return .controlChange(index: data1, value32: MIDI1Upscale.to32(data2))
        case 0xE:
            let combined = UInt16(data2) << 7 | UInt16(data1)   // 14-bit
            return .channelPitchBend(value32: MIDI1Upscale.to32(from14: combined))
        case 0xD:                 return .channelPressure(value32: MIDI1Upscale.to32(data1))
        case 0xA:                 return .polyPressure(note: data1, value32: MIDI1Upscale.to32(data2))
        default:                  return nil
        }
    }
}

/// Normalization from MIDI 2.0 fixed-width ints to engine floats.
enum MIDI2Scale {
    static func velocity(_ v: UInt16) -> Float { Float(v) / 65535.0 }
    static func unipolar(_ v: UInt32) -> Float { Float(v) / 4294967295.0 }
    static func bipolar(_ v: UInt32) -> Float {
        let center: UInt32 = 0x80000000
        if v >= center { return Float(v - center) / Float(0x7FFFFFFF) }
        return -Float(center - v) / Float(center)
    }
}

/// MIDI 1.0 → MIDI 2.0 up-conversion via bit-replication (MIDI 2.0 spec M2-115),
/// so a full-scale 7-/14-bit input maps to a full-scale high-res value (127 → 0xFFFF,
/// not 0xFE00). Plain left-shift would lose the low bits and drop e.g. CC64 to 63.
enum MIDI1Upscale {
    /// 7-bit (0…127) → 16-bit, bit-replicated.
    static func to16(_ v7: UInt8) -> UInt16 {
        let v = UInt16(v7 & 0x7F)
        return (v << 9) | (v << 2) | (v >> 5)
    }

    /// 7-bit (0…127) → 32-bit, bit-replicated.
    static func to32(_ v7: UInt8) -> UInt32 {
        let v = UInt32(v7 & 0x7F)
        return (v << 25) | (v << 18) | (v << 11) | (v << 4) | (v >> 3)
    }

    /// 14-bit (0…0x3FFF) → 32-bit, bit-replicated.
    static func to32(from14 v14: UInt16) -> UInt32 {
        let v = UInt32(v14 & 0x3FFF)
        return (v << 18) | (v << 4) | (v >> 10)
    }
}
