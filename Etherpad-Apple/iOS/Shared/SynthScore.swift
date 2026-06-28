import Foundation

/// Csound score helpers — single source for instr numbers and message shape (mirrors etherpad.csd).
enum SynthScore {
    enum Instr {
        static let size   = 100
        static let key    = 101
        static let octave = 102
        static let scale  = 103
        static let sound  = 104
    }

    static let controlDuration = "0.5"

    static func noteOn(slot: Int) -> String { "i1.\(slot) 0 -2 \(slot)" }
    static func noteOff(slot: Int) -> String { "i-1.\(slot) 0 0 \(slot)" }

    static func control(_ instr: Int, args: String) -> String {
        "i\(instr) 0 \(controlDuration) \(args)"
    }

    static func size(_ value: Int) -> String { control(Instr.size, args: "\(value)") }
    static func key(_ value: Int) -> String { control(Instr.key, args: "\(value)") }
    static func octave(_ value: Int) -> String { control(Instr.octave, args: "\(value)") }
    static func sound(_ value: Int) -> String { control(Instr.sound, args: "\(value)") }

    /// [-1]=Bohlen-Pierce, [-2]=Overtone Low, [-3]=Overtone High, else 14 ET steps.
    static func scale(_ steps: [Int]) -> String? {
        if steps.count == 1, steps[0] < 0 {
            return control(Instr.scale, args: "\(steps[0])")
        }
        if steps.count >= 14 {
            let args = steps.prefix(14).map(String.init).joined(separator: " ")
            return control(Instr.scale, args: args)
        }
        return nil
    }

    static func touchChannelNames(maxSlots: Int = SynthVoiceLayout.maxTouches) -> (x: [String], y: [String]) {
        var x = [String](); var y = [String]()
        for i in 0..<maxSlots {
            x.append("touch.\(i).x")
            y.append("touch.\(i).y")
        }
        return (x, y)
    }
}
