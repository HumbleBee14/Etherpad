import UIKit
import AVFoundation

final class EtherpadViewController: UIViewController, TouchSurfaceDelegate {

    // Kept so we can rebuild menus on selection change — UIMenu is immutable.
    private let engine  = CsoundEngine()
    private let surface = TouchSurfaceView()

    private var scaleBtn:  UIBarButtonItem!
    private var keyBtn:    UIBarButtonItem!
    private var octBtn:    UIBarButtonItem!
    private var sizeBtn:   UIBarButtonItem!
    private var soundBtn:  UIBarButtonItem!

    private var selectedScale:  String = SynthCatalog.defaultScaleName
    private var selectedKey:    Int    = SynthCatalog.defaultKey
    private var selectedOctave: Int    = SynthCatalog.defaultOctave
    private var selectedSize:   Int    = SynthCatalog.defaultSize
    private var selectedSound:  Int    = SynthCatalog.defaultSound

    override func viewDidLoad() {
        super.viewDidLoad()

        // Audio session is configured by SplitSynthViewController on iPad; configure here for iPhone entry point.
        if UIDevice.current.userInterfaceIdiom == .phone {
            configureAudioSession()
        }

        surface.delegate = self
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        configureToolbar()
        engine.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // Edge touches belong to the synth, not the system swipe-up gestures.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    deinit {
        NotificationCenter.default.removeObserver(self)
        engine.allNotesOff()
        engine.stop()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)  // ~5 ms
            try session.setActive(true)
        } catch {
            print("[Etherpad] Audio session setup failed: \(error)")
        }
    }

    @objc private func appWillResignActive() {
        surface.cancelAllTouches()
        engine.allNotesOff()
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        if type == .began {
            surface.cancelAllTouches()
            engine.allNotesOff()
        }
        // On .ended, AVAudioSession resumes automatically for .playback category.
    }

    func touchBegan(slot: Int, x: Float, y: Float) {
        engine.noteOn(slot: slot, x: x, y: y)
    }

    func touchMoved(slot: Int, x: Float, y: Float) {
        engine.updatePosition(slot: slot, x: x, y: y)
    }

    func touchEnded(slot: Int) {
        engine.noteOff(slot: slot)
    }

    private func configureToolbar() {
        let toolbar = UIToolbar()
        toolbar.barStyle = .black
        toolbar.isTranslucent = false
        toolbar.barTintColor = UIColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)
        toolbar.tintColor = .white
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        scaleBtn  = UIBarButtonItem(title: "Scale",  menu: buildScaleMenu())
        keyBtn    = UIBarButtonItem(title: "Key",    menu: buildKeyMenu())
        octBtn    = UIBarButtonItem(title: "Octave", menu: buildOctaveMenu())
        sizeBtn   = UIBarButtonItem(title: "Size",   menu: buildSizeMenu())
        soundBtn  = UIBarButtonItem(title: "Sound",  menu: buildSoundMenu())
        let aboutBtn = UIBarButtonItem(title: "About", style: .plain, target: self,
                                       action: #selector(showAbout))

        toolbar.items = [scaleBtn, flex, keyBtn, flex, octBtn, flex, sizeBtn, flex, soundBtn, flex, aboutBtn]
    }

    // Leading bullet marks the CSD's default value — UIMenu rows don't support attributed underlines.
    private func makeAction(title: String, isSelected: Bool, isDefault: Bool = false,
                            handler: @escaping () -> Void) -> UIAction {
        let displayTitle = isDefault ? "• \(title)" : title
        return UIAction(title: displayTitle, state: isSelected ? .on : .off) { _ in handler() }
    }

    private struct ScaleOption {
        let name: String
        let steps: [Int]
    }

    private var scaleOptions: [ScaleOption] {
        SynthCatalog.scaleOptions.map { ScaleOption(name: $0.name, steps: $0.steps) }
    }

    private func buildScaleMenu() -> UIMenu {
        let actions = scaleOptions.map { opt in
            makeAction(title: opt.name,
                       isSelected: opt.name == selectedScale,
                       isDefault: opt.name == SynthCatalog.defaultScaleName) { [weak self] in
                guard let self = self else { return }
                self.selectedScale = opt.name
                self.engine.setScale(opt.steps)
                self.scaleBtn.title = "Scale: \(opt.name)"
                self.scaleBtn.menu = self.buildScaleMenu()
            }
        }
        return UIMenu(title: "Scale", children: actions)
    }

    private let keyNames = SynthCatalog.keyNames

    private func buildKeyMenu() -> UIMenu {
        let actions = keyNames.enumerated().map { i, name in
            makeAction(title: name, isSelected: i == selectedKey, isDefault: i == SynthCatalog.defaultKey) { [weak self] in
                guard let self = self else { return }
                self.selectedKey = i
                self.engine.setKey(i)
                self.keyBtn.title = "Key: \(name)"
                self.keyBtn.menu = self.buildKeyMenu()
            }
        }
        return UIMenu(title: "Key", children: actions)
    }

    private let octaveLabels = SynthCatalog.octaveLabels
    private let octaveValues = SynthCatalog.octaveValues

    private func buildOctaveMenu() -> UIMenu {
        let actions = zip(octaveLabels, octaveValues).map { label, val in
            makeAction(title: label, isSelected: val == selectedOctave, isDefault: val == SynthCatalog.defaultOctave) { [weak self] in
                guard let self = self else { return }
                self.selectedOctave = val
                self.engine.setOctave(val)
                self.octBtn.title = "Octave: \(label)"
                self.octBtn.menu = self.buildOctaveMenu()
            }
        }
        return UIMenu(title: "Octave", children: actions)
    }

    private func buildSizeMenu() -> UIMenu {
        let actions = SynthCatalog.sizeRange.map { n in
            makeAction(title: "\(n)", isSelected: n == selectedSize, isDefault: n == SynthCatalog.defaultSize) { [weak self] in
                guard let self = self else { return }
                self.selectedSize = n
                self.engine.setSize(n)
                self.surface.numberOfNotes = Double(n)
                self.sizeBtn.title = "Size: \(n)"
                self.sizeBtn.menu = self.buildSizeMenu()
            }
        }
        return UIMenu(title: "Size", children: actions)
    }

    private let soundNames = SynthCatalog.soundNames

    private func buildSoundMenu() -> UIMenu {
        let actions = soundNames.enumerated().map { i, name in
            makeAction(title: name, isSelected: i == selectedSound, isDefault: i == SynthCatalog.defaultSound) { [weak self] in
                guard let self = self else { return }
                self.selectedSound = i
                self.engine.setSound(i)
                self.soundBtn.title = "Sound: \(name)"
                self.soundBtn.menu = self.buildSoundMenu()
            }
        }
        return UIMenu(title: "Sound", children: actions)
    }

    @objc private func showAbout() {
        let aboutVC = AboutViewController()
        aboutVC.modalPresentationStyle = .pageSheet
        present(aboutVC, animated: true)
    }
}
