import AppKit
import CoreGraphics

final class MacSynthViewController: NSViewController, MacTouchDelegate {

    private let engine = MacCsoundEngine()
    private let surface = MacSurfaceView()

    private var selectedSize = 8
    private var multitouchOn = false
    private var multitouchButton: NSButton!
    private let bannerBlur = NSVisualEffectView()
    private let bannerLabel = NSTextField(labelWithString: "Multitouch Mode On — Press Esc to Exit")

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

        surface.delegate = self
        surface.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(bar)
        view.addSubview(surface)

        bannerBlur.material = .hudWindow
        bannerBlur.blendingMode = .withinWindow
        bannerBlur.state = .active
        bannerBlur.wantsLayer = true
        bannerBlur.layer?.cornerRadius = 14
        bannerBlur.layer?.cornerCurve = .continuous
        bannerBlur.layer?.borderWidth = 0.5
        bannerBlur.layer?.borderColor = NSColor(white: 1, alpha: 0.15).cgColor
        bannerBlur.layer?.masksToBounds = true
        bannerBlur.isHidden = true
        bannerBlur.translatesAutoresizingMaskIntoConstraints = false

        bannerLabel.textColor = .labelColor
        bannerLabel.alignment = .center
        bannerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false
        bannerBlur.addSubview(bannerLabel)

        view.addSubview(bannerBlur)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 40),

            surface.topAnchor.constraint(equalTo: bar.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bannerBlur.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            bannerBlur.topAnchor.constraint(equalTo: surface.topAnchor, constant: 18),
            bannerBlur.heightAnchor.constraint(equalToConstant: 40),

            bannerLabel.leadingAnchor.constraint(equalTo: bannerBlur.leadingAnchor, constant: 20),
            bannerLabel.trailingAnchor.constraint(equalTo: bannerBlur.trailingAnchor, constant: -20),
            bannerLabel.centerYAnchor.constraint(equalTo: bannerBlur.centerYAnchor),
        ])

        engine.start()
        surface.numberOfNotes = Double(selectedSize)
        engine.setSize(selectedSize)
    }

    deinit {
        removeKeyMonitor()
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        CGDisplayShowCursor(CGMainDisplayID())
        NotificationCenter.default.removeObserver(self)
    }

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
            bannerLabel.stringValue = "Multitouch Mode On — Press Esc to Exit"
            showBannerBriefly()
            view.window?.makeFirstResponder(surface)
            installKeyMonitor()
            CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
            CGDisplayHideCursor(CGMainDisplayID())
        } else {
            bannerLabel.stringValue = "Multitouch Mode Off"
            showBannerBriefly()
            removeKeyMonitor()
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }

    // Local monitor swallows keys before the responder chain so number keys can't
    // drop out of Multitouch mode.
    private var keyMonitor: Any?
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.multitouchOn else { return event }
            if self.handleKey(event) { return nil }
            return event
        }
    }
    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private var bannerHideWork: DispatchWorkItem?
    private func showBannerBriefly() {
        bannerHideWork?.cancel()
        bannerBlur.isHidden = false
        let work = DispatchWorkItem { [weak self] in self?.bannerBlur.isHidden = true }
        bannerHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    // Esc exits; 1–5 open the matching popup; all else swallowed to stay in mode.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard multitouchOn else { return false }
        if event.keyCode == 53 {
            setMultitouch(false)
            return true
        }
        if let chars = event.charactersIgnoringModifiers,
           let popup = popupForNumberKey(chars) {
            // Async so the monitor returns before performClick's modal menu loop.
            DispatchQueue.main.async { popup.performClick(nil) }
            return true
        }
        return true
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


    func shutdown() {
        setMultitouch(false)
        engine.allNotesOff()
        engine.stop()
    }

    func handleAppDeactivation() {
        setMultitouch(false)
        surface.cancelAllTouches()
        engine.allNotesOff()
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
        pop.selectItem(at: 2)
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
    @objc func showAboutMenu() { presentAbout() }
    private func presentAbout() {
        let a = NSAlert()
        a.messageText = "Etherpad"
        a.informativeText = "Multi-touch synthesizer.\n\nNormal mode: click-drag to play one voice.\nMultitouch mode (⌘M): the whole trackpad plays up to 10 voices. Press Esc to exit."
        a.runModal()
    }
}
