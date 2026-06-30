import AppKit

/// A single preset row. Three visual states share one view:
///   • normal       — name + summary; edit/delete icons fade in on hover; click loads.
///   • editing      — name becomes an inline text field (Return commits, Esc cancels).
///   • confirming   — right side swaps to "Delete?  ✓  ✕".
/// All actions are reported through closures; the controller owns the model.
final class PresetRowView: NSView, NSTextFieldDelegate {

    var accent: NSColor = .systemTeal

    var onLoad:   (() -> Void)?
    var onEdit:   (() -> Void)?
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onDelete: (() -> Void)?

    private enum State { case normal, editing, confirming }
    private var state: State = .normal

    private let activeBar = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let nameField = NSTextField(string: "")

    private let editButton = MacIconButton(symbol: "pencil", tooltip: "Rename")
    private let deleteButton = MacIconButton(symbol: "trash", tooltip: "Delete")
    private let confirmDelete = NSButton()
    private let cancelDelete = NSButton()

    private var actionStack: NSStackView!
    private var trackingArea: NSTrackingArea?
    private var isActiveRow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        buildSubviews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildSubviews() {
        activeBar.wantsLayer = true
        activeBar.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [nameLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        nameField.font = .systemFont(ofSize: 13, weight: .semibold)
        nameField.delegate = self
        nameField.isHidden = true
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.cell?.usesSingleLineMode = true
        nameField.cell?.wraps = false

        editButton.onClick = { [weak self] in self?.onEdit?() }
        deleteButton.onClick = { [weak self] in self?.enterConfirmState() }

        styleDeleteConfirm(confirmDelete, symbol: "checkmark", tint: .systemRed,
                           action: #selector(confirmTapped))
        styleDeleteConfirm(cancelDelete, symbol: "xmark", tint: .secondaryLabelColor,
                           action: #selector(cancelTapped))

        actionStack = NSStackView(views: [editButton, deleteButton, confirmDelete, cancelDelete])
        actionStack.orientation = .horizontal
        actionStack.spacing = 6
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.alphaValue = 0   // hidden until hover

        addSubview(activeBar)
        addSubview(textStack)
        addSubview(nameField)
        addSubview(actionStack)

        NSLayoutConstraint.activate([
            activeBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            activeBar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            activeBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            activeBar.widthAnchor.constraint(equalToConstant: 3),

            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionStack.leadingAnchor, constant: -8),

            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            actionStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func styleDeleteConfirm(_ btn: NSButton, symbol: String, tint: NSColor, action: Selector) {
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        btn.imagePosition = .imageOnly
        btn.bezelStyle = .accessoryBar
        btn.isBordered = false
        btn.contentTintColor = tint
        btn.target = self
        btn.action = action
        btn.isHidden = true
        btn.setContentHuggingPriority(.required, for: .horizontal)
    }

    // MARK: - Configure

    func configure(name: String, detail: String, active: Bool, editing: Bool) {
        nameLabel.stringValue = name
        detailLabel.stringValue = detail
        nameField.stringValue = name
        isActiveRow = active
        nameLabel.textColor = active ? accent : .labelColor
        activeBar.layer?.backgroundColor = active ? accent.cgColor : NSColor.clear.cgColor
        setState(editing ? .editing : .normal)
    }

    func focusEditor() {
        window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectedRange = NSRange(location: 0, length: nameField.stringValue.count)
    }

    // MARK: - State machine

    private func setState(_ newState: State) {
        state = newState
        let editing = newState == .editing
        let confirming = newState == .confirming

        nameField.isHidden = !editing
        nameLabel.isHidden = editing
        detailLabel.isHidden = editing

        editButton.isHidden = confirming
        deleteButton.isHidden = confirming
        confirmDelete.isHidden = !confirming
        cancelDelete.isHidden = !confirming

        if confirming { actionStack.animator().alphaValue = 1 }
        if editing { actionStack.alphaValue = 0 }
    }

    private func enterConfirmState() {
        setState(.confirming)
    }

    @objc private func confirmTapped() { onDelete?() }
    @objc private func cancelTapped() {
        setState(.normal)
        updateHoverActions(visible: isMouseInside)
    }

    /// Sole commit path: Return/Tab/blur all end editing here; Esc reports cancel.
    /// State flips out of `.editing` first so a second end-editing event can't re-fire.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard state == .editing else { return }
        state = .normal
        let movement = (obj.userInfo?["NSTextMovement"] as? Int) ?? 0
        if movement == NSTextMovement.cancel.rawValue {
            onCancel?()
        } else {
            onCommit?(nameField.stringValue)
        }
    }

    // MARK: - Hover + click

    private var isMouseInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        if state == .normal {
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
            updateHoverActions(visible: true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        layer?.backgroundColor = NSColor.clear.cgColor
        if state == .normal { updateHoverActions(visible: false) }
    }

    private func updateHoverActions(visible: Bool) {
        actionStack.animator().alphaValue = visible ? 1 : 0
    }

    override func mouseDown(with event: NSEvent) {
        guard state == .normal else { super.mouseDown(with: event); return }
        // Clicks on the action buttons are handled by the buttons themselves.
        let p = convert(event.locationInWindow, from: nil)
        if actionStack.frame.contains(p) { super.mouseDown(with: event); return }
        onLoad?()
    }
}

/// Borderless SF Symbol button with subtle hover tint, sized for inline row actions.
final class MacIconButton: NSButton {
    var onClick: (() -> Void)?

    init(symbol: String, tooltip: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        imagePosition = .imageOnly
        bezelStyle = .accessoryBar
        isBordered = false
        contentTintColor = .secondaryLabelColor
        toolTip = tooltip
        target = self
        action = #selector(fire)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { onClick?() }
}
