import AudioToolbox
import AVFAudio
import CoreAudioKit
import UIKit

/// AUv3 plugin UI: adaptive full-screen touch surface with translucent overlay toolbar.
///
/// This view controller:
/// - Fills whatever space the host gives it (adaptive layout)
/// - Uses a translucent blur toolbar that overlays the touch surface (maximises touch area)
/// - Synchronises with the `AUParameterTree` bidirectionally
/// - Generates MIDI output from touch pad gestures
/// - Uses `EtherpadAudioUnit.onUIStateChanged` for state observation
///   (never overwrites `hostEngine.onPatchStateChanged` — the AU owns that)
/// - Conforms to `AUAudioUnitFactory` (Apple AUv3 requirement for the principal class)
@objc(EtherpadAUViewController)
public final class EtherpadAUViewController: AUViewController, AUAudioUnitFactory {

    // MARK: - Views

    private let surface = TouchSurfaceView()
    private let touchCoordinator = SynthTouchCoordinator()
    private let menuFactory = SynthPatchMenuFactory()

    // MARK: - AU References

    private weak var audioUnit: EtherpadAudioUnit?
    private var parameterObservationToken: AUParameterObserverToken?

    // MARK: - Toolbar Buttons

    private var scaleBtn: UIButton!
    private var keyBtn: UIButton!
    private var octBtn: UIButton!
    private var sizeBtn: UIButton!
    private var soundBtn: UIButton!

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)

        // Request maximum space from hosts
        preferredContentSize = CGSize(width: 1024, height: 768)

        configureTouchSurface()
        configureOverlayToolbar()

        touchCoordinator.engine = nil
        surface.delegate = self

        menuFactory.onPatchChanged = { [weak self] patch in
            guard let self = self else { return }
            self.surface.numberOfNotes = Double(patch.size)
            self.refreshMenuTitles()
            // Sync MIDI processors immediately when toolbar menus change.
            self.audioUnit?.midiProcessor.patchState = patch
            self.audioUnit?.midiOutputHandler.patchState = patch
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        connectToAudioUnitIfNeeded()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        surface.cancelAllTouches()
        touchCoordinator.engine?.allNotesOff()
        audioUnit?.midiOutputHandler.allNotesOff()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Hosts may resize our view at any time — ensure layout updates
        surface.setNeedsDisplay()
    }

    public override func beginRequest(with context: NSExtensionContext) {
        // Required by NSExtensionRequestHandling on AUViewController principal class.
    }

    // MARK: - AUAudioUnitFactory

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try EtherpadAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = unit
        if isViewLoaded {
            wireEngine(unit)
        }
        return unit
    }

    // MARK: - Engine Wiring

    private func connectToAudioUnitIfNeeded() {
        guard let au = audioUnit else { return }
        if touchCoordinator.engine == nil {
            wireEngine(au)
        }
    }

    private func wireEngine(_ au: EtherpadAudioUnit) {
        // Connect touch coordinator to the synth engine
        touchCoordinator.engine = au.hostEngine
        menuFactory.applyPatch(to: au.hostEngine)
        surface.numberOfNotes = Double(menuFactory.patch.size)
        refreshMenuTitles()

        // Sync initial MIDI processor state
        au.midiProcessor.patchState = menuFactory.patch
        au.midiOutputHandler.patchState = menuFactory.patch

        // Observe AU parameter tree changes (from host automation)
        observeParameterTree(au)

        // Use the AU's UI callback — NOT hostEngine.onPatchStateChanged.
        // The AU owns onPatchStateChanged for authoritative MIDI processor sync.
        au.onUIStateChanged = { [weak self] patchState in
            DispatchQueue.main.async {
                self?.handleEngineStateChange(patchState)
            }
        }
    }

    // MARK: - Parameter Tree Observation

    private func observeParameterTree(_ au: EtherpadAudioUnit) {
        guard let tree = au.parameterTree else { return }

        // Remove previous observation if any
        if let token = parameterObservationToken {
            tree.removeParameterObserver(token)
        }

        // Observe parameter changes from host automation
        parameterObservationToken = tree.token(byAddingParameterObserver: { [weak self] address, value in
            DispatchQueue.main.async {
                self?.handleParameterChange(address: address, value: value)
            }
        })
    }

    /// Handle a parameter change from host automation.
    private func handleParameterChange(address: AUParameterAddress, value: AUValue) {
        guard let au = audioUnit else { return }
        // Rebuild UI from engine state (the AU already synced midiProcessor)
        let enginePatch = au.hostEngine.currentPatchState
        updateMenuFactoryUI(with: enginePatch)
    }

    /// Handle engine-driven patch state changes (from toolbar menus, etc.).
    private func handleEngineStateChange(_ patchState: SynthPatchState) {
        updateMenuFactoryUI(with: patchState)
    }

    /// Update the menu factory and UI to match a new patch state.
    /// Does NOT re-apply to engine or midiProcessor — the AU handles that.
    private func updateMenuFactoryUI(with patchState: SynthPatchState) {
        // Only update if actually changed to avoid infinite loops
        guard menuFactory.patch != patchState else { return }

        menuFactory.updatePatchSilently(patchState)
        surface.numberOfNotes = Double(patchState.size)
        refreshMenuTitles()
    }

    // MARK: - Touch Surface

    private func configureTouchSurface() {
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        // Surface fills the entire view — toolbar overlays it
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Overlay Toolbar

    private func configureOverlayToolbar() {
        view.clipsToBounds = true

        // Translucent blur bar that sits on top of the surface
        let blurEffect = UIBlurEffect(style: .systemThinMaterialDark)
        let bar = UIVisualEffectView(effect: blurEffect)
        bar.clipsToBounds = true
        bar.layer.cornerRadius = 10
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            bar.heightAnchor.constraint(equalToConstant: 40),
        ])

        scaleBtn = makeBarButton(title: menuFactory.scaleTitle, menu: menuFactory.scaleMenu())
        keyBtn = makeBarButton(title: menuFactory.keyTitle, menu: menuFactory.keyMenu())
        octBtn = makeBarButton(title: menuFactory.octaveTitle, menu: menuFactory.octaveMenu())
        sizeBtn = makeBarButton(title: menuFactory.sizeTitle, menu: menuFactory.sizeMenu())
        soundBtn = makeBarButton(title: menuFactory.soundTitle, menu: menuFactory.soundMenu())

        let stack = UIStackView(arrangedSubviews: [scaleBtn, keyBtn, soundBtn, octBtn, sizeBtn])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -4),
        ])
    }

    private func makeBarButton(title: String, menu: UIMenu) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.5
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.menu = menu
        b.showsMenuAsPrimaryAction = true
        return b
    }

    private func refreshMenuTitles() {
        scaleBtn?.setTitle(menuFactory.scaleTitle, for: .normal)
        scaleBtn?.menu = menuFactory.scaleMenu()
        keyBtn?.setTitle(menuFactory.keyTitle, for: .normal)
        keyBtn?.menu = menuFactory.keyMenu()
        octBtn?.setTitle(menuFactory.octaveTitle, for: .normal)
        octBtn?.menu = menuFactory.octaveMenu()
        sizeBtn?.setTitle(menuFactory.sizeTitle, for: .normal)
        sizeBtn?.menu = menuFactory.sizeMenu()
        soundBtn?.setTitle(menuFactory.soundTitle, for: .normal)
        soundBtn?.menu = menuFactory.soundMenu()
    }
}

// MARK: - TouchSurfaceDelegate (MIDI Output Integration)

extension EtherpadAUViewController: TouchSurfaceDelegate {

    public func touchBegan(slot: Int, x: Float, y: Float) {
        touchCoordinator.touchBegan(slot: slot, x: x, y: y)
        audioUnit?.midiOutputHandler.touchBegan(slot: slot, x: x, y: y)
    }

    public func touchMoved(slot: Int, x: Float, y: Float) {
        touchCoordinator.touchMoved(slot: slot, x: x, y: y)
        audioUnit?.midiOutputHandler.touchMoved(slot: slot, x: x, y: y)
    }

    public func touchEnded(slot: Int) {
        touchCoordinator.touchEnded(slot: slot)
        audioUnit?.midiOutputHandler.touchEnded(slot: slot)
    }
}
