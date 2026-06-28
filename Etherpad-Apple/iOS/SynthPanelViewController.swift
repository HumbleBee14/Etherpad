import UIKit
import AVFoundation

final class SynthPanelViewController: UIViewController {

    var showsAboutButton: Bool = true
    var trailingAlignedToolbar: Bool = false

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
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    deinit {
        NotificationCenter.default.removeObserver(self)
        engine.allNotesOff()
        engine.stop()
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
    }

    private func configureToolbar() {
        view.clipsToBounds = true

        let effect: UIVisualEffect = {
            if let cls = NSClassFromString("UIGlassEffect") as? NSObject.Type,
               let obj = cls.init() as? UIVisualEffect {
                return obj
            }
            return UIBlurEffect(style: .systemThinMaterial)
        }()
        let bar = UIVisualEffectView(effect: effect)
        bar.clipsToBounds = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
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
}

extension SynthPanelViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}
