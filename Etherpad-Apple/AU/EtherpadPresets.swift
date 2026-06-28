import AudioToolbox

/// Factory presets for the Etherpad AUv3 instrument.
/// Hosts display these in their preset browser for quick sound selection.
enum EtherpadPresets {

    /// All factory presets, numbered 0–9.
    static let factory: [AUAudioUnitPreset] = {
        let configs: [(number: Int, name: String)] = [
            (0,  "Ether Default"),
            (1,  "Dreamy Blues"),
            (2,  "Flamenco Monk"),
            (3,  "Pentatonic Pad"),
            (4,  "Chromatic Dreams"),
            (5,  "Minor Tri"),
            (6,  "Overtone Ether"),
            (7,  "Whole-Tone Xan"),
            (8,  "Major Pad"),
            (9,  "BP Explorer"),
        ]
        return configs.map { config in
            let preset = AUAudioUnitPreset()
            preset.number = config.number
            preset.name = config.name
            return preset
        }
    }()

    /// Returns the `SynthPatchState` for a factory preset number, or `nil` if invalid.
    static func patchState(for presetNumber: Int) -> SynthPatchState? {
        presetConfigs.first { $0.number == presetNumber }?.patch
    }

    // MARK: - Internal Preset Definitions

    private struct PresetConfig {
        let number: Int
        let patch: SynthPatchState
    }

    private static let presetConfigs: [PresetConfig] = [
        PresetConfig(number: 0, patch: SynthPatchState(
            scaleName: "Default", key: 0, octave: 4, size: 8, sound: 0)),
        PresetConfig(number: 1, patch: SynthPatchState(
            scaleName: "Blues", key: 9, octave: 4, size: 8, sound: 1)),
        PresetConfig(number: 2, patch: SynthPatchState(
            scaleName: "Flamenco", key: 4, octave: 4, size: 10, sound: 4)),
        PresetConfig(number: 3, patch: SynthPatchState(
            scaleName: "Pentatonic", key: 7, octave: 4, size: 8, sound: 0)),
        PresetConfig(number: 4, patch: SynthPatchState(
            scaleName: "Chromatic", key: 0, octave: 4, size: 12, sound: 1)),
        PresetConfig(number: 5, patch: SynthPatchState(
            scaleName: "Minor", key: 2, octave: 5, size: 8, sound: 3)),
        PresetConfig(number: 6, patch: SynthPatchState(
            scaleName: "Overtone Series Low", key: 0, octave: 3, size: 8, sound: 0)),
        PresetConfig(number: 7, patch: SynthPatchState(
            scaleName: "Whole-Tone", key: 6, octave: 4, size: 8, sound: 2)),
        PresetConfig(number: 8, patch: SynthPatchState(
            scaleName: "Major", key: 0, octave: 4, size: 8, sound: 0)),
        PresetConfig(number: 9, patch: SynthPatchState(
            scaleName: "Bohlen-Pierce", key: 0, octave: 4, size: 10, sound: 0)),
    ]
}
