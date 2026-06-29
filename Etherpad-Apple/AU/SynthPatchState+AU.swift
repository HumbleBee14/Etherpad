import AudioToolbox

/// AU-specific extensions for `SynthPatchState` parameter tree conversion.
/// This file is only compiled in the AU target (it references `EtherpadParameterAddress`).
extension SynthPatchState {

    /// Convert to `AUParameterTree`-compatible indexed values.
    func toParameterValues() -> [EtherpadParameterAddress: AUValue] {
        let scaleIndex = SynthCatalog.scaleOptions.firstIndex(where: { $0.name == scaleName }) ?? 0
        let defaultOctaveIndex = SynthCatalog.octaveValues.firstIndex(of: SynthCatalog.defaultOctave) ?? 0
        let octaveIndex = SynthCatalog.octaveValues.firstIndex(of: octave) ?? defaultOctaveIndex
        return [
            .scale: AUValue(scaleIndex),
            .key: AUValue(key),
            .octave: AUValue(octaveIndex),
            .size: AUValue(SynthCatalog.sizeIndex(for: size)),
            .sound: AUValue(sound)
        ]
    }

    /// Create from `AUParameter` indexed values.
    static func fromParameterValues(
        scaleIndex: Int, key: Int, octaveIndex: Int, sizeIndex: Int, sound: Int
    ) -> SynthPatchState {
        let scaleName = scaleIndex < SynthCatalog.scaleOptions.count
            ? SynthCatalog.scaleOptions[scaleIndex].name
            : SynthCatalog.defaultScaleName
        let octave = octaveIndex < SynthCatalog.octaveValues.count
            ? SynthCatalog.octaveValues[octaveIndex]
            : SynthCatalog.defaultOctave
        return SynthPatchState(
            scaleName: scaleName,
            key: max(0, min(11, key)),
            octave: octave,
            size: SynthCatalog.sizeValue(forIndex: sizeIndex),
            sound: max(0, min(SynthCatalog.soundNames.count - 1, sound))
        )
    }
}
