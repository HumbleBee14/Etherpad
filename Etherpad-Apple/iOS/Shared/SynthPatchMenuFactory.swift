import UIKit

/// Builds patch UIMenus from `SynthCatalog` and applies changes through `SynthEngineProtocol`.
/// Shared by standalone iOS and AU plugin UI.
final class SynthPatchMenuFactory {

    private(set) var patch: SynthPatchState
    weak var engine: SynthEngineProtocol?
    var onPatchChanged: ((SynthPatchState) -> Void)?

    init(patch: SynthPatchState = .factoryDefault) {
        self.patch = patch
    }

    func applyPatch(to engine: SynthEngineProtocol) {
        self.engine = engine
        engine.applyPatchState(patch)
    }

    // MARK: - Menus

    func scaleMenu() -> UIMenu {
        UIMenu(title: "Scale", children: SynthCatalog.scaleOptions.map { opt in
            menuAction(title: opt.name, isSelected: opt.name == patch.scaleName, isDefault: opt.isDefault) { [weak self] in
                self?.updateScale(opt.name, steps: opt.steps)
            }
        })
    }

    func keyMenu() -> UIMenu {
        UIMenu(title: "Key", children: SynthCatalog.keyNames.enumerated().map { i, name in
            menuAction(title: name, isSelected: i == patch.key, isDefault: i == SynthCatalog.defaultKey) { [weak self] in
                self?.updateKey(i)
            }
        })
    }

    func octaveMenu() -> UIMenu {
        UIMenu(title: "Octave", children: zip(SynthCatalog.octaveLabels, SynthCatalog.octaveValues).map { label, value in
            menuAction(title: label, isSelected: value == patch.octave, isDefault: value == SynthCatalog.defaultOctave) { [weak self] in
                self?.updateOctave(value)
            }
        })
    }

    func sizeMenu() -> UIMenu {
        UIMenu(title: "Size", children: SynthCatalog.sizeRange.map { n in
            menuAction(title: "\(n)", isSelected: n == patch.size, isDefault: n == SynthCatalog.defaultSize) { [weak self] in
                self?.updateSize(n)
            }
        })
    }

    func soundMenu() -> UIMenu {
        UIMenu(title: "Sound", children: SynthCatalog.soundNames.enumerated().map { i, name in
            menuAction(title: name, isSelected: i == patch.sound, isDefault: i == SynthCatalog.defaultSound) { [weak self] in
                self?.updateSound(i)
            }
        })
    }

    // MARK: - Toolbar titles (for bar button labels)

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

    // MARK: - Patch updates

    private func updateScale(_ name: String, steps: [Int]) {
        patch.scaleName = name
        engine?.setScale(steps)
        notifyPatchChanged()
    }

    private func updateKey(_ key: Int) {
        patch.key = key
        engine?.setKey(key)
        notifyPatchChanged()
    }

    private func updateOctave(_ octave: Int) {
        patch.octave = octave
        engine?.setOctave(octave)
        notifyPatchChanged()
    }

    private func updateSize(_ size: Int) {
        patch.size = size
        engine?.setSize(size)
        notifyPatchChanged()
    }

    private func updateSound(_ sound: Int) {
        patch.sound = sound
        engine?.setSound(sound)
        notifyPatchChanged()
    }

    private func notifyPatchChanged() {
        onPatchChanged?(patch)
    }

    private func menuAction(title: String, isSelected: Bool, isDefault: Bool,
                            handler: @escaping () -> Void) -> UIAction {
        let displayTitle = isDefault ? "• \(title)" : title
        return UIAction(title: displayTitle, state: isSelected ? .on : .off) { _ in handler() }
    }
}
