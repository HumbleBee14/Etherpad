import AudioToolbox

// MARK: - Parameter Addresses

/// Stable AUParameterAddress constants for the Etherpad AUv3 extension.
///
/// Each case maps to a unique `AUParameterAddress` (`UInt64`) that identifies
/// a host-automatable parameter. Values are frozen — **never reorder or renumber**
/// once shipped, or existing host sessions will break.
enum EtherpadParameterAddress: AUParameterAddress, CaseIterable {
    case scale  = 0
    case key    = 1
    case octave = 2
    case size   = 3
    case sound  = 4
}

// MARK: - Parameter Factory

/// Creates and queries the `AUParameterTree` used by `EtherpadAudioUnit`.
///
/// All parameter metadata (ranges, value strings, flags) derives from
/// `SynthCatalog` so the AU and standalone app stay in sync automatically.
struct EtherpadParameterFactory {

    // MARK: Tree Creation

    /// Builds the canonical parameter tree with a single "Etherpad" group.
    ///
    /// - Returns: A fully configured `AUParameterTree` containing five parameters
    ///   (scale, key, octave, size, sound) ready to be assigned to an `AUAudioUnit`.
    static func createParameterTree() -> AUParameterTree {

        // --- Scale (indexed) ------------------------------------------------
        let scaleParam = AUParameterTree.createParameter(
            withIdentifier: "scale",
            name: "Scale",
            address: EtherpadParameterAddress.scale.rawValue,
            min: 0,
            max: AUValue(SynthCatalog.scaleOptions.count - 1),
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: SynthCatalog.scaleOptions.map(\.name),
            dependentParameters: nil
        )

        // --- Key (indexed) --------------------------------------------------
        let keyParam = AUParameterTree.createParameter(
            withIdentifier: "key",
            name: "Key",
            address: EtherpadParameterAddress.key.rawValue,
            min: 0,
            max: 11,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: SynthCatalog.keyNames,
            dependentParameters: nil
        )

        // --- Octave (indexed) -----------------------------------------------
        let octaveParam = AUParameterTree.createParameter(
            withIdentifier: "octave",
            name: "Octave",
            address: EtherpadParameterAddress.octave.rawValue,
            min: 0,
            max: AUValue(SynthCatalog.octaveValues.count - 1),
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: SynthCatalog.octaveLabels,
            dependentParameters: nil
        )

        // --- Size (generic, continuous range) --------------------------------
        let sizeParam = AUParameterTree.createParameter(
            withIdentifier: "size",
            name: "Size",
            address: EtherpadParameterAddress.size.rawValue,
            min: AUValue(SynthCatalog.sizeRange.lowerBound),
            max: AUValue(SynthCatalog.sizeRange.upperBound),
            unit: .generic,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )

        // --- Sound (indexed) ------------------------------------------------
        let soundParam = AUParameterTree.createParameter(
            withIdentifier: "sound",
            name: "Sound",
            address: EtherpadParameterAddress.sound.rawValue,
            min: 0,
            max: AUValue(SynthCatalog.soundNames.count - 1),
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: SynthCatalog.soundNames,
            dependentParameters: nil
        )

        // --- Group & Tree ---------------------------------------------------
        let group = AUParameterTree.createGroup(
            withIdentifier: "etherpad",
            name: "Etherpad",
            children: [scaleParam, keyParam, octaveParam, sizeParam, soundParam]
        )

        return AUParameterTree.createTree(withChildren: [group])
    }

    // MARK: Lookup

    /// Returns the `AUParameter` node for a given address, or `nil` if the tree
    /// does not contain it.
    ///
    /// - Parameters:
    ///   - address: The `EtherpadParameterAddress` to look up.
    ///   - tree: The parameter tree to search.
    /// - Returns: The matching `AUParameter`, or `nil`.
    static func parameter(
        for address: EtherpadParameterAddress,
        in tree: AUParameterTree
    ) -> AUParameter? {
        tree.parameter(withAddress: address.rawValue)
    }
}
