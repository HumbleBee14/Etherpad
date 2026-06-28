import Foundation

/// Patch parameters that map to Csound instr 100–104. Hosts and UI read/write this struct;
/// engines receive values via `apply(to:)`.
struct SynthPatchState: Equatable, Codable {
    var scaleName: String
    var key: Int
    var octave: Int
    var size: Int
    var sound: Int

    static let factoryDefault = SynthPatchState(
        scaleName: SynthCatalog.defaultScaleName,
        key: SynthCatalog.defaultKey,
        octave: SynthCatalog.defaultOctave,
        size: SynthCatalog.defaultSize,
        sound: SynthCatalog.defaultSound
    )

    func apply(to engine: SynthEngineProtocol) {
        engine.setSize(size)
        engine.setKey(key)
        engine.setOctave(octave)
        engine.setSound(sound)
        if let steps = SynthCatalog.scaleSteps(named: scaleName) {
            engine.setScale(steps)
        }
    }
}
