import UIKit
import AVFoundation

final class SplitSynthViewController: UIViewController {

    private var leftPanel:  SynthPanelViewController?
    private var rightPanel: SynthPanelViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        configureAudioSession()

        if UIDevice.current.userInterfaceIdiom != .pad {
            fatalError("SplitSynthViewController is iPad-only")
        }

        rebuildLayout()

        NotificationCenter.default.addObserver(
            self, selector: #selector(splitModeDidChange),
            name: SplitModeController.didChangeNotification, object: nil)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    @objc private func splitModeDidChange() {
        rebuildLayout()
    }

    private func rebuildLayout() {
        leftPanel?.removeFromParent()
        rightPanel?.removeFromParent()
        leftPanel?.view.removeFromSuperview()
        rightPanel?.view.removeFromSuperview()

        view.subviews.forEach { $0.removeFromSuperview() }

        if SplitModeController.isEnabled {
            layoutSplitMode()
        } else {
            layoutSingleMode()
        }
    }

    private func layoutSplitMode() {
        let left = SynthPanelViewController()
        let right = SynthPanelViewController()

        leftPanel = left
        rightPanel = right

        addChild(left)
        addChild(right)

        left.view.translatesAutoresizingMaskIntoConstraints = false
        right.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(left.view)
        view.addSubview(right.view)

        NSLayoutConstraint.activate([
            left.view.topAnchor.constraint(equalTo: view.topAnchor),
            left.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            left.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            left.view.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),

            right.view.topAnchor.constraint(equalTo: view.topAnchor),
            right.view.leadingAnchor.constraint(equalTo: left.view.trailingAnchor),
            right.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            right.view.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
        ])

        left.didMove(toParent: self)
        right.didMove(toParent: self)

        let divider = UIView()
        divider.backgroundColor = UIColor(red: 0x50/255, green: 0x72/255, blue: 0xA7/255, alpha: 0.5)
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 2),
        ])

        let infoBtn = UIButton(type: .infoLight)
        infoBtn.translatesAutoresizingMaskIntoConstraints = false
        infoBtn.addTarget(self, action: #selector(showAbout), for: .touchUpInside)
        view.addSubview(infoBtn)
        NSLayoutConstraint.activate([
            infoBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])

        print("[Etherpad] Split mode: 2 synths side-by-side")
    }

    private func layoutSingleMode() {
        let panel = SynthPanelViewController()
        leftPanel = panel
        rightPanel = nil

        addChild(panel)
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel.view)

        NSLayoutConstraint.activate([
            panel.view.topAnchor.constraint(equalTo: view.topAnchor),
            panel.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        panel.didMove(toParent: self)

        print("[Etherpad] Single mode: 1 synth full-screen")
    }

    @objc private func showAbout() {
        let aboutVC = AboutViewController()
        aboutVC.modalPresentationStyle = .pageSheet
        present(aboutVC, animated: true)
    }
}
