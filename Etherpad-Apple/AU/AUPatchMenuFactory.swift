import UIKit
import AudioToolbox

/// Builds patch UIMenus from `SynthCatalog` for the AUv3 plugin.
/// Taps emit a recordable automation gesture (via `onGesture`) instead of calling the engine
/// directly — that is the only behavioural difference from the standalone factory.
/// SYNC NOTE: keep functionally in sync with `iOS/Shared/SynthPatchMenuFactory.swift` — menu
/// contents and option order must match; presentation may diverge.
final class AUPatchMenuFactory {

    private(set) var patch: SynthPatchState

    /// Fired on every tap: the parameter address and the indexed value the host should record.
    var onGesture: ((EtherpadParameterAddress, AUValue) -> Void)?

    /// Fired after `patch` updates, for local UI refresh (titles/menus/size).
    var onPatchChanged: ((SynthPatchState) -> Void)?

    init(patch: SynthPatchState = .factoryDefault) {
        self.patch = patch
    }

    // MARK: - Menus

    func scaleMenu() -> UIMenu {
        UIMenu(title: "Scale", children: SynthCatalog.scaleOptions.enumerated().map { i, opt in
            menuAction(title: opt.name, isSelected: opt.name == patch.scaleName, isDefault: opt.isDefault) { [weak self] in
                self?.selectScale(name: opt.name, index: i)
            }
        })
    }

    func keyMenu() -> UIMenu {
        UIMenu(title: "Key", children: SynthCatalog.keyNames.enumerated().map { i, name in
            menuAction(title: name, isSelected: i == patch.key, isDefault: i == SynthCatalog.defaultKey) { [weak self] in
                self?.selectKey(i)
            }
        })
    }

    func octaveMenu() -> UIMenu {
        UIMenu(title: "Octave", children: zip(SynthCatalog.octaveLabels, SynthCatalog.octaveValues).enumerated().map { i, pair in
            let (label, value) = pair
            return menuAction(title: label, isSelected: value == patch.octave, isDefault: value == SynthCatalog.defaultOctave) { [weak self] in
                self?.selectOctave(value: value, index: i)
            }
        })
    }

    func sizeMenu() -> UIMenu {
        UIMenu(title: "Size", children: SynthCatalog.sizeRange.map { n in
            menuAction(title: "\(n)", isSelected: n == patch.size, isDefault: n == SynthCatalog.defaultSize) { [weak self] in
                self?.selectSize(n)
            }
        })
    }

    func soundMenu() -> UIMenu {
        UIMenu(title: "Sound", children: SynthCatalog.soundNames.enumerated().map { i, name in
            menuAction(title: name, isSelected: i == patch.sound, isDefault: i == SynthCatalog.defaultSound) { [weak self] in
                self?.selectSound(i)
            }
        })
    }

    // MARK: - Toolbar titles

    var scaleTitle: String { "Scale: \(patch.scaleName)" }
    var keyTitle: String {
        let name = patch.key < SynthCatalog.keyNames.count ? SynthCatalog.keyNames[patch.key] : "?"
        return "Key: \(name)"
    }
    var octaveTitle: String { "Octave: \(SynthCatalog.octaveLabel(forCsoundValue: patch.octave))" }
    var sizeTitle: String { "Size: \(patch.size)" }
    var soundTitle: String {
        let name = patch.sound < SynthCatalog.soundNames.count ? SynthCatalog.soundNames[patch.sound] : "?"
        return "Sound: \(name)"
    }

    // MARK: - Selection (emit gesture, then refresh)

    private func selectScale(name: String, index: Int) {
        patch.scaleName = name
        emit(.scale, index)
    }

    private func selectKey(_ key: Int) {
        patch.key = key
        emit(.key, key)
    }

    private func selectOctave(value: Int, index: Int) {
        patch.octave = value
        emit(.octave, index)
    }

    private func selectSize(_ size: Int) {
        patch.size = size
        emit(.size, SynthCatalog.sizeIndex(for: size))
    }

    private func selectSound(_ sound: Int) {
        patch.sound = sound
        emit(.sound, sound)
    }

    /// Update internal patch without firing callbacks (host automation already changed the engine).
    func updatePatchSilently(_ newPatch: SynthPatchState) {
        patch = newPatch
    }

    private func emit(_ address: EtherpadParameterAddress, _ index: Int) {
        onGesture?(address, AUValue(index))
        onPatchChanged?(patch)
    }

    private func menuAction(title: String, isSelected: Bool, isDefault: Bool,
                            handler: @escaping () -> Void) -> UIAction {
        let displayTitle = isDefault ? "• \(title)" : title
        return UIAction(title: displayTitle, state: isSelected ? .on : .off) { _ in handler() }
    }
}
