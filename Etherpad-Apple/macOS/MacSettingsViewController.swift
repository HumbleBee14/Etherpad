import AppKit

final class MacSettingsViewController: NSViewController {

    private let bgColor     = NSColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)
    private let textColor   = NSColor(red: 0x50/255, green: 0x72/255, blue: 0xa7/255, alpha: 1)
    private let linkColor   = NSColor(red: 0xe9/255, green: 0xd6/255, blue: 0x6b/255, alpha: 1)
    private let subtleColor = NSColor(white: 1.0, alpha: 0.55)

    private let contentWidth: CGFloat = 460
    private let sideInset: CGFloat = 20
    private var innerWidth: CGFloat { contentWidth - sideInset * 2 }

    private var effectContainer: NSStackView!
    private var visMasterToggle: NSSwitch!
    private var chips: [(NSButton, VisualEffects)] = []
    private var escMonitor: Any?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = bgColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 24, left: sideInset, bottom: 24, right: sideInset)
        view.addSubview(stack)

        let title = makeLabel("Settings", size: 22, weight: .bold)
        title.alignment = .center
        stack.addArrangedSubview(title)

        let tagline = makeLabel("Multi-touch synthesizer for Mac", size: 13, weight: .regular)
        tagline.alignment = .center
        tagline.textColor = textColor
        stack.setCustomSpacing(20, after: title)
        stack.addArrangedSubview(tagline)

        stack.addArrangedSubview(makeVisualizationsHeader())

        effectContainer = makeEffectContainer()
        effectContainer.isHidden = visMasterToggle.state == .off
        stack.addArrangedSubview(effectContainer)

        stack.addArrangedSubview(makeDeveloperLink())
        stack.addArrangedSubview(makeCreditsLabel())
        stack.addArrangedSubview(makeTipsBox())

        for sub in stack.arrangedSubviews {
            sub.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
        }

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: contentWidth),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }

        window.title = "Settings"
        // Fixed-size popup: no resize, no zoom/minimize.
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false

        // Shrink the window to exactly fit the content (no wasted space).
        window.setContentSize(NSSize(width: contentWidth, height: view.fittingSize.height))
        window.center()

        // Esc closes.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.closeSettings(); return nil }
            return event
        }
        // Clicking outside (window loses focus) closes.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResignedKey),
            name: NSWindow.didResignKeyNotification, object: window)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor); escMonitor = nil }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowResignedKey() {
        closeSettings()
    }

    @objc private func closeSettings() {
        guard presentingViewController != nil else { return }
        presentingViewController?.dismiss(self)
    }

    override func cancelOperation(_ sender: Any?) {
        closeSettings()
    }

    // MARK: - Visualizations

    private func makeVisualizationsHeader() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = makeLabel("Visualizations", size: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        visMasterToggle = NSSwitch()
        visMasterToggle.target = self
        visMasterToggle.action = #selector(visualizationsMasterToggled(_:))
        visMasterToggle.state = VisualEffects.current.isEmpty ? .off : .on
        visMasterToggle.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(visMasterToggle)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            visMasterToggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            visMasterToggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 24),
        ])
        return row
    }

    private func makeEffectContainer() -> NSStackView {
        chips.removeAll()
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 10
        container.alignment = .leading
        container.translatesAutoresizingMaskIntoConstraints = false

        let pairs = stride(from: 0, to: VisualEffects.all.count, by: 2).map {
            Array(VisualEffects.all[$0..<min($0 + 2, VisualEffects.all.count)])
        }
        for pair in pairs {
            let rowChips = pair.map { effect -> NSButton in
                let chip = makeChip(label: effect.label, effect: effect)
                chips.append((chip, effect))
                return chip
            }
            let row = NSStackView(views: rowChips)
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            row.translatesAutoresizingMaskIntoConstraints = false
            container.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
        }
        return container
    }

    private func makeChip(label: String, effect: VisualEffects) -> NSButton {
        let btn = NSButton(title: label, target: self, action: #selector(toggleEffect(_:)))
        btn.setButtonType(.toggle)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.tag = effect.rawValue
        btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
        applyChipStyle(btn, isOn: isChipOn(effect))
        return btn
    }

    private func applyChipStyle(_ btn: NSButton, isOn: Bool) {
        btn.state = isOn ? .on : .off
        if isOn {
            btn.layer?.backgroundColor = linkColor.cgColor
            btn.contentTintColor = bgColor
        } else {
            btn.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
            btn.contentTintColor = textColor
        }
    }

    private func isChipOn(_ effect: VisualEffects) -> Bool {
        effect.rawValue == 0 ? VisualEffects.current.isEmpty
                             : VisualEffects.current.contains(effect)
    }

    @objc private func toggleEffect(_ sender: NSButton) {
        guard let effect = VisualEffects.all.first(where: { $0.rawValue == sender.tag }) else { return }
        var cur = VisualEffects.current
        if cur.contains(effect) { cur.remove(effect) } else { cur.insert(effect) }
        VisualEffects.current = cur
        refreshChips()
    }

    @objc private func visualizationsMasterToggled(_ sender: NSSwitch) {
        if sender.state == .on {
            if VisualEffects.current.isEmpty {
                VisualEffects.current = [.ripple]
                refreshChips()
            }
        } else {
            VisualEffects.current = .none
            refreshChips()
        }
        effectContainer.isHidden = sender.state == .off
    }

    private func refreshChips() {
        for (btn, effect) in chips {
            applyChipStyle(btn, isOn: isChipOn(effect))
        }
        visMasterToggle.state = VisualEffects.current.isEmpty ? .off : .on
    }

    // MARK: - Credits

    private static let developerURL = URL(string: "https://dineshy.com")!

    private func makeDeveloperLink() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 0
        row.alignment = .centerY

        let prefix = makeLabel("Developer: ", size: 14, weight: .regular)
        prefix.textColor = textColor

        let link = NSButton(title: "Dinesh", target: self, action: #selector(openDeveloperSite))
        link.bezelStyle = .inline
        link.isBordered = false
        link.font = .systemFont(ofSize: 14)
        link.contentTintColor = linkColor
        link.attributedTitle = NSAttributedString(string: "Dinesh", attributes: [
            .foregroundColor: linkColor,
            .cursor: NSCursor.pointingHand,
        ])

        row.addArrangedSubview(prefix)
        row.addArrangedSubview(link)
        return row
    }

    @objc private func openDeveloperSite() {
        NSWorkspace.shared.open(Self.developerURL)
    }

    private func makeCreditsLabel() -> NSTextField {
        let l = makeLabel("Credits: Inspired by Paul Batchelor's EtherSurface app.",
                          size: 12, weight: .regular)
        l.font = NSFontManager.shared.convert(l.font!, toHaveTrait: .italicFontMask)
        l.textColor = subtleColor
        l.alignment = .left
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 0
        l.preferredMaxLayoutWidth = innerWidth
        return l
    }

    // MARK: - Tips (bottom)

    private func makeTipsBox() -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = NSColor(white: 1, alpha: 0.05)
        box.borderColor = NSColor(white: 1, alpha: 0.12)
        box.cornerRadius = 8
        box.titlePosition = .noTitle
        box.contentViewMargins = NSSize(width: 14, height: 12)
        box.translatesAutoresizingMaskIntoConstraints = false

        let lineStack = NSStackView()
        lineStack.orientation = .vertical
        lineStack.alignment = .leading
        lineStack.spacing = 8
        lineStack.translatesAutoresizingMaskIntoConstraints = false

        let shortcut = makeTipLine("Press ⌥M for touchpad mode (Esc to exit).")
        let gestures = makeTipLine(
            "For smooth multi-finger play, turn off gestures (Mission Control & App Exposé) in "
            + "System Settings ▸ Trackpad ▸ More Gestures.")
        lineStack.addArrangedSubview(shortcut)
        lineStack.addArrangedSubview(gestures)

        box.contentView?.addSubview(lineStack)
        if let cv = box.contentView {
            NSLayoutConstraint.activate([
                lineStack.topAnchor.constraint(equalTo: cv.topAnchor),
                lineStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
                lineStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                lineStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            ])
        }
        return box
    }

    private func makeTipLine(_ text: String) -> NSTextField {
        let l = makeLabel(text, size: 12, weight: .regular)
        l.textColor = subtleColor
        l.alignment = .left
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 0
        l.preferredMaxLayoutWidth = innerWidth - 28
        return l
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = textColor
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }
}
