import Foundation

struct MacScaleOption { let name: String; let steps: [Int] }

enum MacSynthTables {
    static let scaleMajor:   [Int] = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23]
    static let scaleMinor:   [Int] = [0, 2, 3, 5, 7, 8, 11, 12, 14, 15, 17, 19, 20, 23]
    static let scalePent:    [Int] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 30]
    static let scaleBlues:   [Int] = [0, 3, 5, 6, 7, 10, 12, 15, 17, 18, 19, 22, 24, 27]
    static let scaleChrom:   [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    static let scaleWhole:   [Int] = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26]
    static let scaleOct:     [Int] = [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18, 19, 21]
    static let scaleFlam:    [Int] = [0, 1, 4, 5, 7, 8, 11, 12, 13, 16, 17, 19, 21, 22]
    static let scaleDefault: [Int] = [0, 2, 4, 7, 9, 11, 12, 14, 16, 19, 21, 24, 26, 28]
    static let scaleBP:      [Int] = [-1]
    static let scaleOTLow:   [Int] = [-2]
    static let scaleOTHigh:  [Int] = [-3]

    static var scaleOptions: [MacScaleOption] {
        [
            .init(name: "Default",     steps: scaleDefault),
            .init(name: "Major",       steps: scaleMajor),
            .init(name: "Minor",       steps: scaleMinor),
            .init(name: "Pentatonic",  steps: scalePent),
            .init(name: "Flamenco",    steps: scaleFlam),
            .init(name: "Blues",       steps: scaleBlues),
            .init(name: "Chromatic",   steps: scaleChrom),
            .init(name: "Whole-Tone",  steps: scaleWhole),
            .init(name: "Octatonic",   steps: scaleOct),
            .init(name: "Bohlen-Pierce", steps: scaleBP),
            .init(name: "Overtone Series Low",  steps: scaleOTLow),
            .init(name: "Overtone Series High", steps: scaleOTHigh),
        ]
    }
    static let keyNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    static let octaveLabels = ["2","1","0","-1","-2"]
    static let octaveValues = [6, 5, 4, 3, 2]
    static let soundNames = ["Ether Pad","Distorted Dreams","Xanpalamin","Soft Triangle","Digital Monk","Morphwave","PWM Pad","Glass Choir","FM Bell"]
}
