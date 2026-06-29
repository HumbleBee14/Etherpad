import AudioToolbox

/// Stable parameter addresses for the Etherpad AUv3 instrument.
/// These addresses are the host↔AU contract — never change published addresses.
enum EtherpadParameterAddress: AUParameterAddress, CaseIterable {
    case scale  = 0
    case key    = 1
    case sound  = 2
    case octave = 3
    case size   = 4
}

// MARK: - Parameter Tree Factory

/// Creates and configures the `AUParameterTree` for Etherpad's 5 synth parameters.
/// All parameters are readable and writable so hosts can automate them.
enum EtherpadParameterFactory {

    /// Create the full parameter tree with all Etherpad parameters.
    static func createParameterTree() -> AUParameterTree {
        let flags: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable]

        let scale = AUParameterTree.createParameter(
            withIdentifier: "scale", name: "Scale",
            address: EtherpadParameterAddress.scale.rawValue,
            min: 0, max: AUValue(SynthCatalog.scaleOptions.count - 1),
            unit: .indexed, unitName: nil, flags: flags,
            valueStrings: SynthCatalog.scaleOptions.map(\.name),
            dependentParameters: nil
        )

        let key = AUParameterTree.createParameter(
            withIdentifier: "key", name: "Key",
            address: EtherpadParameterAddress.key.rawValue,
            min: 0, max: AUValue(SynthCatalog.keyNames.count - 1),
            unit: .indexed, unitName: nil, flags: flags,
            valueStrings: SynthCatalog.keyNames,
            dependentParameters: nil
        )

        let sound = AUParameterTree.createParameter(
            withIdentifier: "sound", name: "Sound",
            address: EtherpadParameterAddress.sound.rawValue,
            min: 0, max: AUValue(SynthCatalog.soundNames.count - 1),
            unit: .indexed, unitName: nil, flags: flags,
            valueStrings: SynthCatalog.soundNames,
            dependentParameters: nil
        )

        let octave = AUParameterTree.createParameter(
            withIdentifier: "octave", name: "Octave",
            address: EtherpadParameterAddress.octave.rawValue,
            min: 0, max: AUValue(SynthCatalog.octaveValues.count - 1),
            unit: .indexed, unitName: nil, flags: flags,
            valueStrings: SynthCatalog.octaveLabels,
            dependentParameters: nil
        )

        let size = AUParameterTree.createParameter(
            withIdentifier: "size", name: "Size",
            address: EtherpadParameterAddress.size.rawValue,
            min: 0, max: AUValue(SynthCatalog.sizeLabels.count - 1),
            unit: .indexed, unitName: nil, flags: flags,
            valueStrings: SynthCatalog.sizeLabels,
            dependentParameters: nil
        )

        return AUParameterTree.createTree(withChildren: [scale, key, sound, octave, size])
    }

    /// Look up a parameter by its address in the tree.
    static func parameter(for address: EtherpadParameterAddress,
                          in tree: AUParameterTree) -> AUParameter? {
        tree.parameter(withAddress: address.rawValue)
    }
}
