import Foundation

/// Scales, keys, sounds, and UI labels — shared by standalone app and AU (no hardcoded duplicates).
enum SynthCatalog {

    static let defaultScaleName = "Default"
    static let defaultKey = 0
    static let defaultOctave = 4
    static let defaultSize = 8
    static let defaultSound = 0

    struct ScaleOption: Equatable {
        let name: String
        let steps: [Int]
        var isDefault: Bool { name == defaultScaleName }
    }

    static let scaleOptions: [ScaleOption] = [
        .init(name: "Default", steps: [0, 2, 4, 7, 9, 11, 12, 14, 16, 19, 21, 24, 26, 28]),
        .init(name: "Major", steps: [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23]),
        .init(name: "Minor", steps: [0, 2, 3, 5, 7, 8, 11, 12, 14, 15, 17, 19, 20, 23]),
        .init(name: "Pentatonic", steps: [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 30]),
        .init(name: "Flamenco", steps: [0, 1, 4, 5, 7, 8, 11, 12, 13, 16, 17, 19, 21, 22]),
        .init(name: "Blues", steps: [0, 3, 5, 6, 7, 10, 12, 15, 17, 18, 19, 22, 24, 27]),
        .init(name: "Chromatic", steps: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]),
        .init(name: "Whole-Tone", steps: [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26]),
        .init(name: "Octatonic", steps: [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18, 19, 21]),
        .init(name: "Bohlen-Pierce", steps: [-1]),
        .init(name: "Overtone Series Low", steps: [-2]),
        .init(name: "Overtone Series High", steps: [-3]),
    ]

    static let keyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Display labels 2…-2 map to Csound octave values 6…2.
    static let octaveLabels = ["2", "1", "0", "-1", "-2"]
    static let octaveValues = [6, 5, 4, 3, 2]

    static let soundNames = [
        "Ether Pad", "Distorted Dreams", "Xanpalamin", "Soft Triangle", "Digital Monk",
        "Morphwave", "PWM Pad", "Glass Choir", "FM Bell",
    ]

    static let sizeRange = 4...14

    static let sizeLabels: [String] = sizeRange.map { "\($0)" }

    static func sizeIndex(for value: Int) -> Int {
        max(0, min(sizeLabels.count - 1, value - sizeRange.lowerBound))
    }

    static func sizeValue(forIndex index: Int) -> Int {
        sizeRange.lowerBound + max(0, min(sizeLabels.count - 1, index))
    }

    static func scaleSteps(named name: String) -> [Int]? {
        scaleOptions.first { $0.name == name }?.steps
    }

    static func octaveLabel(forCsoundValue value: Int) -> String {
        if let idx = octaveValues.firstIndex(of: value), idx < octaveLabels.count {
            return octaveLabels[idx]
        }
        return "\(value)"
    }
}
