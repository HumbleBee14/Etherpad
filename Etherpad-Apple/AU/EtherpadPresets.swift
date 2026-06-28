import AudioToolbox

// MARK: - Factory Presets

/// Ten curated factory presets for the Etherpad AUv3 instrument.
///
/// Each preset maps to a `SynthPatchState` that fully configures the synth
/// engine's scale, key, octave, size, and sound parameters.
///
/// Preset numbers are frozen — **never reorder or renumber** once shipped,
/// because hosts persist presets by number.
enum EtherpadPresets {

    // MARK: Preset List

    /// The factory presets exposed via `AUAudioUnit.factoryPresets`.
    static let factory: [AUAudioUnitPreset] = (0..<presetDefinitions.count).map { index in
        let preset = AUAudioUnitPreset()
        preset.number = index
        preset.name = presetDefinitions[index].name
        return preset
    }

    // MARK: Patch Lookup

    /// Returns the `SynthPatchState` associated with a factory preset number.
    ///
    /// - Parameter presetNumber: The zero-based preset index (0–9).
    /// - Returns: The corresponding patch state, or `nil` if the number is out of range.
    static func patchState(for presetNumber: Int) -> SynthPatchState? {
        guard presetDefinitions.indices.contains(presetNumber) else { return nil }
        return presetDefinitions[presetNumber].patch
    }

    // MARK: - Internal Definitions

    /// A named pairing of preset metadata and its synth configuration.
    private struct PresetDefinition {
        let name: String
        let patch: SynthPatchState
    }

    /// Master list of preset definitions.
    ///
    /// | #  | Name              | Sound | Scale               | Key | Octave | Size |
    /// |----|-------------------|-------|---------------------|-----|--------|------|
    /// | 0  | Ether Default     | 0     | Default             | 0   | 4      | 8    |
    /// | 1  | Dreamy Blues       | 1     | Blues               | 9   | 4      | 8    |
    /// | 2  | Flamenco Monk     | 4     | Flamenco            | 4   | 4      | 10   |
    /// | 3  | Pentatonic Pad    | 0     | Pentatonic          | 7   | 4      | 8    |
    /// | 4  | Chromatic Dreams  | 1     | Chromatic           | 0   | 4      | 12   |
    /// | 5  | Minor Tri         | 3     | Minor               | 2   | 5      | 8    |
    /// | 6  | Overtone Ether    | 0     | Overtone Series Low | 0   | 3      | 8    |
    /// | 7  | Whole-Tone Xan    | 2     | Whole-Tone          | 6   | 4      | 8    |
    /// | 8  | Major Pad         | 0     | Major               | 0   | 4      | 8    |
    /// | 9  | BP Explorer       | 0     | Bohlen-Pierce       | 0   | 4      | 10   |
    private static let presetDefinitions: [PresetDefinition] = [
        PresetDefinition(
            name: "Ether Default",
            patch: SynthPatchState(scaleName: "Default", key: 0, octave: 4, size: 8, sound: 0)
        ),
        PresetDefinition(
            name: "Dreamy Blues",
            patch: SynthPatchState(scaleName: "Blues", key: 9, octave: 4, size: 8, sound: 1)
        ),
        PresetDefinition(
            name: "Flamenco Monk",
            patch: SynthPatchState(scaleName: "Flamenco", key: 4, octave: 4, size: 10, sound: 4)
        ),
        PresetDefinition(
            name: "Pentatonic Pad",
            patch: SynthPatchState(scaleName: "Pentatonic", key: 7, octave: 4, size: 8, sound: 0)
        ),
        PresetDefinition(
            name: "Chromatic Dreams",
            patch: SynthPatchState(scaleName: "Chromatic", key: 0, octave: 4, size: 12, sound: 1)
        ),
        PresetDefinition(
            name: "Minor Tri",
            patch: SynthPatchState(scaleName: "Minor", key: 2, octave: 5, size: 8, sound: 3)
        ),
        PresetDefinition(
            name: "Overtone Ether",
            patch: SynthPatchState(scaleName: "Overtone Series Low", key: 0, octave: 3, size: 8, sound: 0)
        ),
        PresetDefinition(
            name: "Whole-Tone Xan",
            patch: SynthPatchState(scaleName: "Whole-Tone", key: 6, octave: 4, size: 8, sound: 2)
        ),
        PresetDefinition(
            name: "Major Pad",
            patch: SynthPatchState(scaleName: "Major", key: 0, octave: 4, size: 8, sound: 0)
        ),
        PresetDefinition(
            name: "BP Explorer",
            patch: SynthPatchState(scaleName: "Bohlen-Pierce", key: 0, octave: 4, size: 10, sound: 0)
        ),
    ]
}
