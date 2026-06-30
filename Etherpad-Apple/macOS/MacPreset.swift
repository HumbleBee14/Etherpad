import Foundation

/// macOS presets store the five popup indices directly (the Mac app is index-based,
/// unlike iOS which carries a SynthPatchState). Size is saved but excluded from the
/// suggested name, matching iOS.
struct MacPreset: Codable, Equatable {
    let id: UUID
    var name: String
    var scale: Int
    var key: Int
    var octave: Int
    var size: Int
    var sound: Int

    init(id: UUID = UUID(), name: String,
         scale: Int, key: Int, octave: Int, size: Int, sound: Int) {
        self.id = id
        self.name = name
        self.scale = scale
        self.key = key
        self.octave = octave
        self.size = size
        self.sound = sound
    }

    static func suggestedName(scale: Int, key: Int, octave: Int, sound: Int,
                              maxLength: Int) -> String {
        let s = MacSynthTables.scaleOptions.indices.contains(scale)
            ? String(MacSynthTables.scaleOptions[scale].name.prefix(3)) : "?"
        let k = MacSynthTables.keyNames.indices.contains(key)
            ? String(MacSynthTables.keyNames[key].prefix(2)) : "?"
        let o = MacSynthTables.octaveLabels.indices.contains(octave)
            ? String(MacSynthTables.octaveLabels[octave].prefix(2)) : "?"
        let n = MacSynthTables.soundNames.indices.contains(sound)
            ? String(MacSynthTables.soundNames[sound].prefix(3)) : "?"
        return String("\(s)-\(k)-\(o)-\(n)".prefix(maxLength))
    }

    var summary: String {
        let s = MacSynthTables.scaleOptions.indices.contains(scale)
            ? MacSynthTables.scaleOptions[scale].name : "?"
        let k = MacSynthTables.keyNames.indices.contains(key) ? MacSynthTables.keyNames[key] : "?"
        let o = MacSynthTables.octaveLabels.indices.contains(octave)
            ? MacSynthTables.octaveLabels[octave] : "?"
        let n = MacSynthTables.soundNames.indices.contains(sound)
            ? MacSynthTables.soundNames[sound] : "?"
        return "\(s) · \(k) · \(o) · \(n)"
    }
}
