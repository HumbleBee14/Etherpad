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
