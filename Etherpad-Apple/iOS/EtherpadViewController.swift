import UIKit
import AVFoundation

final class EtherpadViewController: UIViewController {

    private let engine = CsoundEngine()
    private let surface = TouchSurfaceView()
    private let touchCoordinator = SynthTouchCoordinator()
    private let menuFactory = SynthPatchMenuFactory()

    private var scaleBtn:  UIBarButtonItem!
    private var keyBtn:    UIBarButtonItem!
    private var octBtn:    UIBarButtonItem!
    private var sizeBtn:   UIBarButtonItem!
    private var soundBtn:  UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        if UIDevice.current.userInterfaceIdiom == .phone {
            configureAudioSession()
        }

        touchCoordinator.engine = engine
        surface.delegate = touchCoordinator
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        menuFactory.onPatchChanged = { [weak self] patch in
            self?.surface.numberOfNotes = Double(patch.size)
            self?.refreshToolbarMenus()
        }

        configureToolbar()
        engine.start()
        menuFactory.applyPatch(to: engine)
        surface.numberOfNotes = Double(menuFactory.patch.size)

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
            try session.setPreferredIOBufferDuration(0.005)
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
        } else if type == .ended {
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map {
                AVAudioSession.InterruptionOptions(rawValue: $0)
            }
            if options?.contains(.shouldResume) ?? true {
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
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

        scaleBtn = UIBarButtonItem(title: menuFactory.scaleTitle, menu: menuFactory.scaleMenu())
        keyBtn = UIBarButtonItem(title: menuFactory.keyTitle, menu: menuFactory.keyMenu())
        octBtn = UIBarButtonItem(title: menuFactory.octaveTitle, menu: menuFactory.octaveMenu())
        sizeBtn = UIBarButtonItem(title: menuFactory.sizeTitle, menu: menuFactory.sizeMenu())
        soundBtn = UIBarButtonItem(title: menuFactory.soundTitle, menu: menuFactory.soundMenu())
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let aboutBtn = UIBarButtonItem(title: "About", style: .plain, target: self,
                                       action: #selector(showAbout))

        toolbar.items = [scaleBtn, flex, keyBtn, flex, octBtn, flex, sizeBtn, flex, soundBtn, flex, aboutBtn]
    }

    private func refreshToolbarMenus() {
        scaleBtn.title = menuFactory.scaleTitle
        scaleBtn.menu = menuFactory.scaleMenu()
        keyBtn.title = menuFactory.keyTitle
        keyBtn.menu = menuFactory.keyMenu()
        octBtn.title = menuFactory.octaveTitle
        octBtn.menu = menuFactory.octaveMenu()
        sizeBtn.title = menuFactory.sizeTitle
        sizeBtn.menu = menuFactory.sizeMenu()
        soundBtn.title = menuFactory.soundTitle
        soundBtn.menu = menuFactory.soundMenu()
    }

    @objc private func showAbout() {
        let aboutVC = AboutViewController()
        aboutVC.modalPresentationStyle = .pageSheet
        present(aboutVC, animated: true)
    }
}
