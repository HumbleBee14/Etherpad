import UIKit
import AVFoundation

final class SynthPanelViewController: UIViewController {

    var showsAboutButton: Bool = true
    var showsRecordButton: Bool = true

    private let engine = CsoundEngine()
    private let surface = TouchSurfaceView()
    private let touchCoordinator = SynthTouchCoordinator()
    private let menuFactory = SynthPatchMenuFactory()

    private var scaleBtn: UIButton!
    private var keyBtn: UIButton!
    private var octBtn: UIButton!
    private var sizeBtn: UIButton!
    private var soundBtn: UIButton!
    private weak var settingsBtn: UIButton?
    private weak var recordBtn: UIButton?
    private weak var toolbarBar: UIVisualEffectView?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var pendingShareURL: URL?
    private let menuGestureDelegate = AllowSimultaneousMenuGesture()

    override func viewDidLoad() {
        super.viewDidLoad()

        touchCoordinator.engine = engine
        surface.delegate = touchCoordinator
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        // Surface extends behind the translucent toolbar so the blur has content to sample.
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        menuFactory.onPatchChanged = { [weak self] patch in
            self?.surface.numberOfNotes = Double(patch.size)
            self?.refreshMenus()
        }

        configureToolbar()
        engine.start()
        menuFactory.applyPatch(to: engine)
        surface.numberOfNotes = Double(menuFactory.patch.size)

        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(recordingSettingChanged),
            name: RecordingSettings.didChangeNotification, object: nil)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    deinit {
        NotificationCenter.default.removeObserver(self)
        discardRecording()
        if let url = pendingShareURL { try? FileManager.default.removeItem(at: url) }
        engine.allNotesOff()
        engine.stop()
    }

    @objc private func appWillResignActive() {
        surface.cancelAllTouches()
        engine.allNotesOff()
    }

    @objc private func appDidEnterBackground() {
        finalizeAndKeepRecording()
    }

    @objc private func appDidBecomeActive() {
        guard let url = pendingShareURL else { return }
        pendingShareURL = nil
        presentShareSheet(for: url)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        if type == .began {
            surface.cancelAllTouches()
            engine.allNotesOff()
            finalizeAndKeepRecording()
        } else if type == .ended {
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map {
                AVAudioSession.InterruptionOptions(rawValue: $0)
            }
            if options?.contains(.shouldResume) ?? true {
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            if UIApplication.shared.applicationState == .active, let url = pendingShareURL {
                pendingShareURL = nil
                presentShareSheet(for: url)
            }
        }
    }

    private func configureToolbar() {
        view.clipsToBounds = true

        let blurEffect = UIBlurEffect(style: .systemThinMaterialDark)
        let bar = UIVisualEffectView(effect: blurEffect)
        bar.clipsToBounds = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        toolbarBar = bar
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
        ])

        scaleBtn = makeBarButton(title: "Scale", menu: menuFactory.scaleMenu())
        keyBtn = makeBarButton(title: "Key", menu: menuFactory.keyMenu())
        octBtn = makeBarButton(title: "Octave", menu: menuFactory.octaveMenu())
        sizeBtn = makeBarButton(title: "Size", menu: menuFactory.sizeMenu())
        soundBtn = makeBarButton(title: "Sound", menu: menuFactory.soundMenu())

        var buttons: [UIButton] = [scaleBtn, keyBtn, octBtn, sizeBtn, soundBtn]

        let preset = UIButton(type: .system)
        let presetCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        preset.setImage(UIImage(systemName: "slider.horizontal.3", withConfiguration: presetCfg), for: .normal)
        preset.tintColor = .white
        preset.addTarget(self, action: #selector(showPresets), for: .touchUpInside)
        buttons.append(preset)

        if RecordingSettings.isEnabled && showsRecordButton {
            let rec = UIButton(type: .system)
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            rec.setImage(UIImage(systemName: "record.circle", withConfiguration: cfg), for: .normal)
            rec.tintColor = .white
            rec.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
            recordBtn = rec
            buttons.append(rec)
        }

        if showsAboutButton {
            let gear = UIButton(type: .system)
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            gear.setImage(UIImage(systemName: "gearshape", withConfiguration: cfg), for: .normal)
            gear.tintColor = .white
            gear.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
            settingsBtn = gear
            buttons.append(gear)
        }

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor),
        ])

        // Let toolbar buttons open while fingers are tracking on the surface.
        for btn in buttons {
            btn.gestureRecognizers?.forEach { $0.delegate = menuGestureDelegate }
        }
    }

    private func refreshMenus() {
        scaleBtn.menu = menuFactory.scaleMenu()
        keyBtn.menu = menuFactory.keyMenu()
        octBtn.menu = menuFactory.octaveMenu()
        sizeBtn.menu = menuFactory.sizeMenu()
        soundBtn.menu = menuFactory.soundMenu()
    }

    private func makeBarButton(title: String, menu: UIMenu) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.6
        b.titleLabel?.lineBreakMode = .byClipping
        b.menu = menu
        b.showsMenuAsPrimaryAction = true
        return b
    }

    @objc private func showSettings() {
        let settings = AboutViewController()
        settings.modalPresentationStyle = .popover
        settings.preferredContentSize = CGSize(width: 520, height: 560)
        if let pop = settings.popoverPresentationController {
            pop.sourceView = settingsBtn
            pop.sourceRect = settingsBtn?.bounds ?? .zero
            pop.permittedArrowDirections = .up
            pop.delegate = self
        }
        present(settings, animated: true)
    }

    @objc private func showPresets() {
        let presets = PresetsViewController(
            currentPatch: { [weak self] in self?.menuFactory.patch ?? .factoryDefault },
            onLoad: { [weak self] preset in self?.menuFactory.applyPreset(preset) })
        let nav = UINavigationController(rootViewController: presets)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    // MARK: - Recording

    @objc private func recordingSettingChanged() {
        if engine.isRecording { discardRecording() }
        guard let bar = toolbarBar else { return }
        bar.removeFromSuperview()
        recordBtn = nil
        configureToolbar()
    }

    @objc private func toggleRecording() {
        if engine.isRecording {
            finishRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        sweepStaleRecordings()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(defaultRecordingName()).wav")
        engine.startRecording(to: url)
        guard engine.isRecording else { return }
        recordingURL = url
        updateRecordButton(recording: true)
        recordingTimer = Timer.scheduledTimer(
            withTimeInterval: RecordingSettings.maxDuration, repeats: false) { [weak self] _ in
            self?.finishRecording()
        }
    }

    private func finishRecording() {
        guard let url = stopRecordingKeepingFile() else { return }
        presentShareSheet(for: url)
    }

    private func finalizeAndKeepRecording() {
        guard let url = stopRecordingKeepingFile() else { return }
        if let old = pendingShareURL { try? FileManager.default.removeItem(at: old) }
        pendingShareURL = url
    }

    private func stopRecordingKeepingFile() -> URL? {
        recordingTimer?.invalidate()
        recordingTimer = nil
        guard engine.isRecording else { return nil }
        engine.stopRecording()
        updateRecordButton(recording: false)
        defer { recordingURL = nil }
        return recordingURL
    }

    private func discardRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        guard engine.isRecording else { return }
        engine.stopRecording()
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        updateRecordButton(recording: false)
    }

    private func presentShareSheet(for url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        if let pop = share.popoverPresentationController {
            pop.sourceView = recordBtn ?? view
            pop.sourceRect = recordBtn?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(share, animated: true)
    }

    private func updateRecordButton(recording: Bool) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let name = recording ? "stop.fill" : "record.circle"
        recordBtn?.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
        recordBtn?.tintColor = recording ? .systemRed : .white
    }

    private func defaultRecordingName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Etherpad \(fmt.string(from: Date()))"
    }

    private func sweepStaleRecordings() {
        let tmp = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix("Etherpad ") && url.pathExtension == "wav" {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

extension SynthPanelViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}

final class AllowSimultaneousMenuGesture: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
