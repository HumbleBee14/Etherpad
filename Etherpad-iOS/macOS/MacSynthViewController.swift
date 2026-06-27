import AppKit
import CoreGraphics

// macOS synth screen: toolbar controls + surface + Multitouch mode.
// Fully independent of iOS (own engine, own surface, own tables).
final class MacSynthViewController: NSViewController, MacTouchDelegate {

    private let engine = MacCsoundEngine()
    private let surface = MacSurfaceView()

    private var selectedSize = 8
    private var multitouchOn = false
    private var multitouchButton: NSButton!
    private let banner = NSTextField(labelWithString: "Multitouch ON — 1–5 open menus · Esc to exit")

    // Popups kept so number keys (1–5) can open them during Multitouch mode.
    private var scalePopup: NSPopUpButton!
    private var keyPopup: NSPopUpButton!
    private var octavePopup: NSPopUpButton!
    private var sizePopup: NSPopUpButton!
    private var soundPopup: NSPopUpButton!

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 790))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // --- Control bar ---
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.alignment = .centerY
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        bar.translatesAutoresizingMaskIntoConstraints = false

        scalePopup = makeScalePopup()
        keyPopup = makeKeyPopup()
        octavePopup = makeOctavePopup()
        sizePopup = makeSizePopup()
        soundPopup = makeSoundPopup()
        bar.addArrangedSubview(labeled("1 Scale", scalePopup))
        bar.addArrangedSubview(labeled("2 Key", keyPopup))
        bar.addArrangedSubview(labeled("3 Octave", octavePopup))
        bar.addArrangedSubview(labeled("4 Size", sizePopup))
        bar.addArrangedSubview(labeled("5 Sound", soundPopup))

        multitouchButton = NSButton(title: "Multitouch", target: self,
                                    action: #selector(toggleMultitouch))
        bar.addArrangedSubview(multitouchButton)

        let about = NSButton(title: "About", target: self, action: #selector(showAbout))
        bar.addArrangedSubview(about)

        // --- Surface ---
        surface.delegate = self
        surface.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(bar)
        view.addSubview(surface)

        // --- Banner (hidden until Multitouch mode) ---
        banner.textColor = .white
        banner.backgroundColor = NSColor(white: 0, alpha: 0.6)
        banner.drawsBackground = true
        banner.alignment = .center
        banner.font = .systemFont(ofSize: 15, weight: .semibold)
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 6
        banner.isHidden = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 40),

            surface.topAnchor.constraint(equalTo: bar.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            banner.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            banner.topAnchor.constraint(equalTo: surface.topAnchor, constant: 16),
            banner.widthAnchor.constraint(equalToConstant: 300),
            banner.heightAnchor.constraint(equalToConstant: 34),
        ])

        engine.start()
        surface.numberOfNotes = Double(selectedSize)
        engine.setSize(selectedSize)

        // Exit Multitouch safely if the window/app loses focus.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResigned),
            name: NSWindow.didResignKeyNotification, object: nil)
    }

    deinit {
        // Guarantee the cursor is never left hidden/detached.
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        CGDisplayShowCursor(CGMainDisplayID())
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Touch delegate -> engine
    func touchBegan(slot: Int, x: Float, y: Float) { engine.noteOn(slot: slot, x: x, y: y) }
    func touchMoved(slot: Int, x: Float, y: Float) { engine.updatePosition(slot: slot, x: x, y: y) }
    func touchEnded(slot: Int) { engine.noteOff(slot: slot) }

    // MARK: - Multitouch mode
    @objc func toggleMultitouch() { setMultitouch(!multitouchOn) }

    func setMultitouch(_ on: Bool) {
        guard on != multitouchOn else { return }
        multitouchOn = on
        surface.multitouchActive = on
        multitouchButton.title = on ? "Exit Multitouch" : "Multitouch"
        engine.allNotesOff()

        if on {
            showBannerBriefly()
            view.window?.makeFirstResponder(surface)
            CGAssociateMouseAndMouseCursorPosition(boolean_t(0))   // detach pointer
            CGDisplayHideCursor(CGMainDisplayID())
        } else {
            banner.isHidden = true
            bannerHideWork?.cancel()
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))   // reattach
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }

    private var bannerHideWork: DispatchWorkItem?
    private func showBannerBriefly() {
        bannerHideWork?.cancel()
        banner.isHidden = false
        let work = DispatchWorkItem { [weak self] in self?.banner.isHidden = true }
        bannerHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    // While in Multitouch mode the cursor is detached, so menus are opened with
    // number keys 1–5 (then native arrow keys navigate / Return selects / Esc closes
    // the popup). Esc with no popup open exits Multitouch mode.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {       // Esc
            if multitouchOn { setMultitouch(false); return }
        }
        if multitouchOn, let chars = event.charactersIgnoringModifiers,
           let popup = popupForNumberKey(chars) {
            // Refresh the banner so the user sees the hint while interacting.
            showBannerBriefly()
            popup.performClick(nil)    // opens the menu with keyboard focus
            return
        }
        super.keyDown(with: event)
    }
    override var acceptsFirstResponder: Bool { true }

    private func popupForNumberKey(_ chars: String) -> NSPopUpButton? {
        switch chars {
        case "1": return scalePopup
        case "2": return keyPopup
        case "3": return octavePopup
        case "4": return sizePopup
        case "5": return soundPopup
        default:  return nil
        }
    }

    @objc private func windowResigned() {
        setMultitouch(false)
        engine.allNotesOff()
        surface.cancelAllTouches()
    }

    // Called by the app on terminate for a clean shutdown.
    func shutdown() {
        setMultitouch(false)
        engine.allNotesOff()
        engine.stop()
    }

    // MARK: - Controls
    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let stack = NSStackView(views: [makeLabel(title), control])
        stack.orientation = .horizontal
        stack.spacing = 4
        return stack
    }
    private func makeLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func makeScalePopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: MacSynthTables.scaleOptions.map { $0.name })
        pop.target = self; pop.action = #selector(scaleChanged(_:))
        return pop
    }
    @objc private func scaleChanged(_ s: NSPopUpButton) {
        engine.setScale(MacSynthTables.scaleOptions[s.indexOfSelectedItem].steps)
    }

    private func makeKeyPopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: MacSynthTables.keyNames)
        pop.target = self; pop.action = #selector(keyChanged(_:))
        return pop
    }
    @objc private func keyChanged(_ s: NSPopUpButton) { engine.setKey(s.indexOfSelectedItem) }

    private func makeOctavePopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: MacSynthTables.octaveLabels)
        pop.selectItem(at: 2)              // "0" -> Csound value 4 (default)
        pop.target = self; pop.action = #selector(octaveChanged(_:))
        return pop
    }
    @objc private func octaveChanged(_ s: NSPopUpButton) {
        engine.setOctave(MacSynthTables.octaveValues[s.indexOfSelectedItem])
    }

    private func makeSizePopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: (4...14).map(String.init))
        pop.selectItem(withTitle: "8")
        pop.target = self; pop.action = #selector(sizeChanged(_:))
        return pop
    }
    @objc private func sizeChanged(_ s: NSPopUpButton) {
        let n = Int(s.titleOfSelectedItem ?? "8") ?? 8
        selectedSize = n
        engine.setSize(n)
        surface.numberOfNotes = Double(n)
    }

    private func makeSoundPopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: MacSynthTables.soundNames)
        pop.target = self; pop.action = #selector(soundChanged(_:))
        return pop
    }
    @objc private func soundChanged(_ s: NSPopUpButton) { engine.setSound(s.indexOfSelectedItem) }

    @objc private func showAbout() { presentAbout() }
    @objc func showAboutMenu() { presentAbout() }   // reachable from the app menu
    private func presentAbout() {
        let a = NSAlert()
        a.messageText = "Etherpad"
        a.informativeText = "Multi-touch synthesizer.\n\nNormal mode: click-drag to play one voice.\nMultitouch mode (⌘M): the whole trackpad plays up to 10 voices. Press Esc to exit."
        a.runModal()
    }
}
