import UIKit
import AVFoundation

final class SplitSynthViewController: UIViewController {

    private var leftPanel:  SynthPanelViewController?
    private var rightPanel: SynthPanelViewController?
    private weak var divider: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()

        configureAudioSession()
        rebuildLayout()

        NotificationCenter.default.addObserver(
            self, selector: #selector(splitModeDidChange),
            name: SplitModeController.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: .themeChanged, object: nil)
    }

    @objc private func themeChanged() {
        applyTheme()
    }

    private func applyTheme() {
        let theme = Theme.current
        view.backgroundColor = theme.background
        divider?.backgroundColor = theme.accent(alpha: 0.85)
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
        leftPanel?.willMove(toParent: nil)
        rightPanel?.willMove(toParent: nil)
        leftPanel?.view.removeFromSuperview()
        rightPanel?.view.removeFromSuperview()
        leftPanel?.removeFromParent()
        rightPanel?.removeFromParent()
        leftPanel = nil
        rightPanel = nil

        for sub in view.subviews { sub.removeFromSuperview() }

        if SplitModeController.isEnabled {
            layoutSplitMode()
        } else {
            layoutSingleMode()
        }
    }

    private func layoutSplitMode() {
        let theme = Theme.current
        view.backgroundColor = theme.background

        let left = SynthPanelViewController()
        let right = SynthPanelViewController()
        left.showsAboutButton = false
        right.showsAboutButton = false

        leftPanel = left
        rightPanel = right

        addChild(left)
        addChild(right)

        left.view.translatesAutoresizingMaskIntoConstraints = false
        right.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(left.view)
        view.addSubview(right.view)

        let halfGap: CGFloat = 8

        NSLayoutConstraint.activate([
            left.view.topAnchor.constraint(equalTo: view.topAnchor),
            left.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            left.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            left.view.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -halfGap),

            right.view.topAnchor.constraint(equalTo: view.topAnchor),
            right.view.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: halfGap),
            right.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            right.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        left.didMove(toParent: self)
        right.didMove(toParent: self)

        let divider = UIView()
        divider.backgroundColor = theme.accent(alpha: 0.85)
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)
        self.divider = divider
        NSLayoutConstraint.activate([
            divider.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 3),
        ])
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
    }
}
