// SplitSynthViewController.swift — iPad split-screen dual-synth container
//
// On iPad: manages two SynthPanelViewController instances (left/right) with shared About sheet.
// Configures AVAudioSession once. Listens to SplitModeController changes and transitions
// between split layout and single-synth full-screen.
//
// On iPhone: this VC should not be instantiated (SceneDelegate routes to EtherpadViewController instead).

import UIKit
import AVFoundation

final class SplitSynthViewController: UIViewController {

    // MARK: - Child view controllers

    private var leftPanel:  SynthPanelViewController?
    private var rightPanel: SynthPanelViewController?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureAudioSession()

        // On first launch, split mode is OFF — show single synth.
        // When user toggles split mode ON in About, we rebuild the layout.
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

    // MARK: - Audio session

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

    // MARK: - Layout rebuild

    @objc private func splitModeDidChange() {
        rebuildLayout()
    }

    private func rebuildLayout() {
        // Remove old child VCs (but keep toolbar)
        leftPanel?.willMove(toParent: nil)
        rightPanel?.willMove(toParent: nil)
        leftPanel?.view.removeFromSuperview()
        rightPanel?.view.removeFromSuperview()
        leftPanel?.removeFromParent()
        rightPanel?.removeFromParent()
        leftPanel = nil
        rightPanel = nil

        // Remove dividers from previous split layout (anything that isn't a UIToolbar)
        for sub in view.subviews where !(sub is UIToolbar) {
            sub.removeFromSuperview()
        }

        if SplitModeController.isEnabled {
            layoutSplitMode()
        } else {
            layoutSingleMode()
        }

        // Make sure toolbar stays on top
        for sub in view.subviews where sub is UIToolbar {
            view.bringSubviewToFront(sub)
        }
    }

    // Split mode: two panels side-by-side with a visible gap + divider
    private func layoutSplitMode() {
        // Dark gutter color shows through the gap between the two panels
        view.backgroundColor = UIColor(red: 0x1a/255, green: 0x1e/255, blue: 0x22/255, alpha: 1)

        let left = SynthPanelViewController()
        let right = SynthPanelViewController()

        // Hide About from the left panel to save toolbar space in split mode;
        // the right panel still has it and opens the same About sheet.
        left.showsAboutButton = false
        // Right panel's buttons hug the right edge so they don't collide
        // with the left panel's buttons across the center gutter.
        right.trailingAlignedToolbar = true

        leftPanel = left
        rightPanel = right

        addChild(left)
        addChild(right)

        left.view.translatesAutoresizingMaskIntoConstraints = false
        right.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(left.view)
        view.addSubview(right.view)

        // Gutter: total ~16pt gap (8pt on each side of the center)
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

        // Crisp accent divider centered in the gutter
        let divider = UIView()
        divider.backgroundColor = UIColor(red: 0xe9/255, green: 0xd6/255, blue: 0x6b/255, alpha: 0.85)
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 3),
        ])

        print("[Etherpad] Split mode: 2 synths side-by-side")
    }

    // Single mode: one panel full-screen (below toolbar)
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

}
