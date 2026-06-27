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

    private var controlBar: NSView!
    private var immersiveButton: NSButton!
    private var immersiveMode = false
    private var barShown = true
    private var barHideWork: DispatchWorkItem?
    /// Distance from the top edge within which mouse movement reveals the hidden bar.
    private let revealZoneHeight: CGFloat = 56

    private var scalePopup: NSPopUpButton!
    private var keyPopup: NSPopUpButton!
    private var octavePopup: NSPopUpButton!
    private var sizePopup: NSPopUpButton!
    private var soundPopup: NSPopUpButton!

    /// CSD defaults — leading bullet in menus marks these (matches iOS).
    private enum DefaultIndex {
        static let scale = 0
        static let key = 0
        static let octave = 2   // label "0", value 4
        static let size = 4     // "8" in 4…14
        static let sound = 0
    }

    override func loadView() {
        let container = ImmersiveContainerView(frame: NSRect(x: 0, y: 0, width: 1200, height: 790))
        container.onMouseMoved = { [weak self] point in self?.handleMouseMoved(point) }
        view = container
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

        let popups: [(String, NSPopUpButton)] = [
            ("Scale", scalePopup),
            ("Key", keyPopup),
            ("Octave", octavePopup),
            ("Size", sizePopup),
            ("Sound", soundPopup),
        ]
        for (i, item) in popups.enumerated() {
            bar.addArrangedSubview(labeled(item.0, item.1))
            if i < popups.count - 1 { bar.addArrangedSubview(barSeparator()) }
        }

        bar.addArrangedSubview(barSeparator())
        multitouchButton = NSButton(title: "Multitouch (⌥M)", target: self,
                                    action: #selector(toggleMultitouch))
        multitouchButton.toolTip = "Toggle touchpad mode (⌥M)"
        bar.addArrangedSubview(multitouchButton)

        let barSpacer = NSView()
        barSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        barSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(barSpacer)

        let immersiveImg = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                   accessibilityDescription: "Immersive mode")!
        immersiveButton = NSButton(image: immersiveImg, target: self, action: #selector(toggleImmersive))
        immersiveButton.imagePosition = .imageOnly
        immersiveButton.bezelStyle = .accessoryBar
        immersiveButton.toolTip = "Immersive mode — hide controls (⌥H)"
        bar.addArrangedSubview(immersiveButton)

        let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!
        let settings = NSButton(image: gear, target: self, action: #selector(showSettings))
        settings.imagePosition = .imageOnly
        settings.bezelStyle = .accessoryBar
        settings.toolTip = "Settings"
        bar.addArrangedSubview(settings)

        surface.delegate = self
        surface.translatesAutoresizingMaskIntoConstraints = false

        controlBar = makeGlassBar(content: bar)
        view.addSubview(surface)
        view.addSubview(controlBar)

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
            controlBar.topAnchor.constraint(equalTo: view.topAnchor),
            controlBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: 40),

            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bannerBlur.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            bannerBlur.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: 18),
            bannerBlur.heightAnchor.constraint(equalToConstant: 40),

            bannerLabel.leadingAnchor.constraint(equalTo: bannerBlur.leadingAnchor, constant: 20),
            bannerLabel.trailingAnchor.constraint(equalTo: bannerBlur.trailingAnchor, constant: -20),
            bannerLabel.centerYAnchor.constraint(equalTo: bannerBlur.centerYAnchor),
        ])

        engine.start()
        restoreSettings()
    }

    private enum Key {
        static let scale = "scaleIndex", key = "keyIndex", octave = "octaveIndex"
        static let size = "sizeIndex", sound = "soundIndex"
    }

    private func savedIndex(_ k: String, default def: Int, count: Int) -> Int {
        let d = UserDefaults.standard
        guard d.object(forKey: k) != nil else { return def }
        let i = d.integer(forKey: k)
        return (0..<count).contains(i) ? i : def
    }

    private func restoreSettings() {
        scalePopup.selectItem(at: savedIndex(Key.scale, default: 0, count: scalePopup.numberOfItems))
        keyPopup.selectItem(at: savedIndex(Key.key, default: 0, count: keyPopup.numberOfItems))
        octavePopup.selectItem(at: savedIndex(Key.octave, default: 2, count: octavePopup.numberOfItems))
        sizePopup.selectItem(at: savedIndex(Key.size, default: 4, count: sizePopup.numberOfItems))
        soundPopup.selectItem(at: savedIndex(Key.sound, default: 0, count: soundPopup.numberOfItems))
        scaleChanged(scalePopup); keyChanged(keyPopup); octaveChanged(octavePopup)
        sizeChanged(sizePopup);  soundChanged(soundPopup)
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
        multitouchButton.title = on ? "Exit Multitouch (Esc)" : "Multitouch (⌥M)"
        engine.allNotesOff()

        if on {
            bannerLabel.stringValue = "Multitouch Mode On — Press Esc to Exit"
            showBannerBriefly()
            // Indirect trackpad touches route to the view under the (frozen) cursor.
            // Park the cursor over the synth before decoupling so touches land there
            // no matter where it was when multitouch was toggled (button, menu, etc.).
            warpCursorToSurfaceCenter()
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

    private func warpCursorToSurfaceCenter() {
        guard let window = view.window,
              let mainScreen = NSScreen.screens.first else { return }
        let center = CGPoint(x: surface.bounds.midX, y: surface.bounds.midY)
        let windowPoint = surface.convert(center, to: nil)
        // Cocoa screen coords (bottom-left origin) → CoreGraphics global (top-left origin).
        let cocoa = window.convertPoint(toScreen: windowPoint)
        let cgPoint = CGPoint(x: cocoa.x, y: mainScreen.frame.maxY - cocoa.y)
        CGWarpMouseCursorPosition(cgPoint)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))   // flush warp before re-freezing
    }

    // Monitor intercepts keys before the responder chain; otherwise number keys reach
    // the popups and drop out of Multitouch mode.
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

    // MARK: - Immersive mode
    // Auto-hides the control bar for distraction-free play; reveals it when the
    // cursor nears the top edge, then re-hides after a short idle period.
    @objc func toggleImmersive() { setImmersive(!immersiveMode) }

    func setImmersive(_ on: Bool) {
        guard on != immersiveMode else { return }
        immersiveMode = on
        let symbol = on ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
        immersiveButton.image = NSImage(systemSymbolName: symbol,
                                        accessibilityDescription: "Immersive mode")
        immersiveButton.toolTip = on ? "Exit immersive mode (⌥H)"
                                     : "Immersive mode — hide controls (⌥H)"
        if on {
            scheduleBarAutoHide()
        } else {
            barHideWork?.cancel(); barHideWork = nil
            setBarVisible(true, animated: true)
        }
    }

    private func handleMouseMoved(_ point: NSPoint) {
        guard immersiveMode else { return }
        if view.bounds.maxY - point.y <= revealZoneHeight {
            setBarVisible(true, animated: true)
        }
        scheduleBarAutoHide()
    }

    private func scheduleBarAutoHide() {
        barHideWork?.cancel()
        guard immersiveMode else { return }
        let work = DispatchWorkItem { [weak self] in self?.autoHideBarIfAppropriate() }
        barHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func autoHideBarIfAppropriate() {
        guard immersiveMode else { return }
        // Keep the bar up while the cursor is parked in the top reveal zone.
        if let p = currentPointInView(), view.bounds.maxY - p.y <= revealZoneHeight {
            scheduleBarAutoHide()
            return
        }
        setBarVisible(false, animated: true)
    }

    private func currentPointInView() -> NSPoint? {
        guard let window = view.window else { return nil }
        let winPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return view.convert(winPoint, from: nil)
    }

    private func setBarVisible(_ visible: Bool, animated: Bool) {
        guard barShown != visible else { return }
        barShown = visible
        if visible { controlBar.isHidden = false }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = animated ? 0.22 : 0
            controlBar.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            if !self.barShown { self.controlBar.isHidden = true }
        })
    }

    // MARK: - Controls
    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let stack = NSStackView(views: [makeLabel(title), control])
        stack.orientation = .horizontal
        stack.spacing = 4
        return stack
    }

    private func barSeparator() -> NSView {
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 18),
        ])
        return line
    }

    /// Liquid glass on macOS 26+; frosted header vibrancy on earlier releases.
    private func makeGlassBar(content: NSView) -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.cornerRadius = 0
            glass.contentView = host
            return glass
        }

        let effect = NSVisualEffectView()
        effect.material = .headerView
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    private func makeLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    // Marks the CSD default by making that menu item bold (matches iOS' default hint).
    private func populatePopup(_ pop: NSPopUpButton, titles: [String], defaultIndex: Int) {
        pop.removeAllItems()
        for (i, title) in titles.enumerated() {
            pop.addItem(withTitle: title)
            if i == defaultIndex, let item = pop.item(at: i) {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
            }
        }
    }

    private func makeScalePopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        populatePopup(pop, titles: MacSynthTables.scaleOptions.map(\.name),
                      defaultIndex: DefaultIndex.scale)
        pop.target = self; pop.action = #selector(scaleChanged(_:))
        return pop
    }
    @objc private func scaleChanged(_ s: NSPopUpButton) {
        engine.setScale(MacSynthTables.scaleOptions[s.indexOfSelectedItem].steps)
        UserDefaults.standard.set(s.indexOfSelectedItem, forKey: Key.scale)
    }

    private func makeKeyPopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        populatePopup(pop, titles: MacSynthTables.keyNames, defaultIndex: DefaultIndex.key)
        pop.target = self; pop.action = #selector(keyChanged(_:))
        return pop
    }
    @objc private func keyChanged(_ s: NSPopUpButton) {
        engine.setKey(s.indexOfSelectedItem)
        UserDefaults.standard.set(s.indexOfSelectedItem, forKey: Key.key)
    }

    private func makeOctavePopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        populatePopup(pop, titles: MacSynthTables.octaveLabels, defaultIndex: DefaultIndex.octave)
        pop.selectItem(at: DefaultIndex.octave)
        pop.target = self; pop.action = #selector(octaveChanged(_:))
        return pop
    }
    @objc private func octaveChanged(_ s: NSPopUpButton) {
        engine.setOctave(MacSynthTables.octaveValues[s.indexOfSelectedItem])
        UserDefaults.standard.set(s.indexOfSelectedItem, forKey: Key.octave)
    }

    private func makeSizePopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        let titles = (4...14).map(String.init)
        populatePopup(pop, titles: titles, defaultIndex: DefaultIndex.size)
        pop.selectItem(at: DefaultIndex.size)
        pop.target = self; pop.action = #selector(sizeChanged(_:))
        return pop
    }
    @objc private func sizeChanged(_ s: NSPopUpButton) {
        let n = Int(s.titleOfSelectedItem ?? "8") ?? 8
        selectedSize = n
        engine.setSize(n)
        surface.numberOfNotes = Double(n)
        UserDefaults.standard.set(s.indexOfSelectedItem, forKey: Key.size)
    }

    private func makeSoundPopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        populatePopup(pop, titles: MacSynthTables.soundNames, defaultIndex: DefaultIndex.sound)
        pop.target = self; pop.action = #selector(soundChanged(_:))
        return pop
    }
    @objc private func soundChanged(_ s: NSPopUpButton) {
        engine.setSound(s.indexOfSelectedItem)
        UserDefaults.standard.set(s.indexOfSelectedItem, forKey: Key.sound)
    }

    @objc private func showSettings() { presentSettings() }
    @objc func showSettingsMenu() { presentSettings() }
    private func presentSettings() {
        let settings = MacSettingsViewController()
        presentAsModalWindow(settings)
    }
}

/// Container that reports mouse movement so the controller can reveal/hide the
/// control bar in immersive mode.
private final class ImmersiveContainerView: NSView {
    var onMouseMoved: ((NSPoint) -> Void)?
    private var moveTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = moveTracking { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        moveTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }
}
