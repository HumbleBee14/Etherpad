import CoreAudioKit
import UIKit

/// Plugin UI: compact patch toolbar + full-screen touch surface.
public final class EtherpadAUViewController: AUViewController {

    private let surface = TouchSurfaceView()
    private let touchCoordinator = SynthTouchCoordinator()
    private let menuFactory = SynthPatchMenuFactory()
    private var connected = false

    private var scaleBtn: UIBarButtonItem!
    private var keyBtn: UIBarButtonItem!
    private var octBtn: UIBarButtonItem!
    private var sizeBtn: UIBarButtonItem!
    private var soundBtn: UIBarButtonItem!

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)

        configureToolbar()
        touchCoordinator.engine = nil
        surface.delegate = touchCoordinator
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        menuFactory.onPatchChanged = { [weak self] patch in
            self?.surface.numberOfNotes = Double(patch.size)
            self?.refreshToolbarMenus()
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        connectToAudioUnitIfNeeded()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        touchCoordinator.engine?.allNotesOff()
    }

    public override func beginRequest(with context: NSExtensionContext) {
        // Required by NSExtensionRequestHandling on AUViewController principal class.
    }

    private func connectToAudioUnitIfNeeded() {
        guard !connected, let au = EtherpadAUContext.audioUnit else { return }
        connected = true
        touchCoordinator.engine = au.hostEngine
        menuFactory.applyPatch(to: au.hostEngine)
        surface.numberOfNotes = Double(menuFactory.patch.size)
        refreshToolbarMenus()
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
        toolbar.items = [scaleBtn, flex, keyBtn, flex, octBtn, flex, sizeBtn, flex, soundBtn]
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
}
