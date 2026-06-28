import Foundation
import os

/// Patch parameters that map to Csound instr 100–104. Hosts and UI read/write this struct;
/// engines receive values via `apply(to:)`.
struct SynthPatchState: Equatable, Codable {
    var scaleName: String
    var key: Int
    var octave: Int
    var size: Int
    var sound: Int

    init(scaleName: String, key: Int, octave: Int, size: Int, sound: Int) {
        self.scaleName = scaleName
        self.key = key
        self.octave = octave
        self.size = size
        self.sound = sound
    }

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

    // MARK: - AUv3 State Serialization

    /// Key used in `AUAudioUnit.fullState` dictionary.
    static let stateKey = "EtherpadPatchState"

    /// Serialize to a dictionary for AUv3 `fullState` persistence.
    func toDictionary() -> [String: Any] {
        [
            "scaleName": scaleName,
            "key": key,
            "octave": octave,
            "size": size,
            "sound": sound
        ]
    }

    /// Deserialize from a `fullState` dictionary with bounds validation.
    init?(dictionary: [String: Any]) {
        guard let scaleName = dictionary["scaleName"] as? String,
              let key = dictionary["key"] as? Int,
              let octave = dictionary["octave"] as? Int,
              let size = dictionary["size"] as? Int,
              let sound = dictionary["sound"] as? Int
        else { return nil }

        guard SynthCatalog.scaleOptions.contains(where: { $0.name == scaleName }),
              (0..<SynthCatalog.keyNames.count).contains(key),
              SynthCatalog.octaveValues.contains(octave),
              SynthCatalog.sizeRange.contains(size),
              (0..<SynthCatalog.soundNames.count).contains(sound)
        else { return nil }

        self.scaleName = scaleName
        self.key = key
        self.octave = octave
        self.size = size
        self.sound = sound
    }
}

// MARK: - Realtime Thread Safety

/// Lock-protected patch state for cross-thread access (audio render vs UI / host params).
final class RealtimePatchState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: SynthPatchState.factoryDefault)

    var value: SynthPatchState {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }

    func snapshot() -> SynthPatchState { lock.withLock { $0 } }

    func mutate(_ body: (inout SynthPatchState) -> Void) {
        lock.withLock { body(&$0) }
    }
}
