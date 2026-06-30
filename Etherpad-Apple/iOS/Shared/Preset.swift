import Foundation

struct Preset: Codable, Equatable {
    let id: UUID
    var name: String
    var patch: SynthPatchState

    init(id: UUID = UUID(), name: String, patch: SynthPatchState) {
        self.id = id
        self.name = name
        self.patch = patch
    }

    static func suggestedName(for patch: SynthPatchState, maxLength: Int) -> String {
        let scale = String(patch.scaleName.prefix(3))
        let key = patch.key < SynthCatalog.keyNames.count
            ? String(SynthCatalog.keyNames[patch.key].prefix(2)) : "?"
        let octave = String(SynthCatalog.octaveLabel(forCsoundValue: patch.octave).prefix(2))
        let sound = patch.sound < SynthCatalog.soundNames.count
            ? String(SynthCatalog.soundNames[patch.sound].prefix(3)) : "?"
        return String("\(scale)-\(key)-\(octave)-\(sound)".prefix(maxLength))
    }

    static func summary(for patch: SynthPatchState) -> String {
        let key = patch.key < SynthCatalog.keyNames.count ? SynthCatalog.keyNames[patch.key] : "?"
        let octave = SynthCatalog.octaveLabel(forCsoundValue: patch.octave)
        let sound = patch.sound < SynthCatalog.soundNames.count ? SynthCatalog.soundNames[patch.sound] : "?"
        return "\(patch.scaleName) · \(key) · \(octave) · \(sound)"
    }
}
