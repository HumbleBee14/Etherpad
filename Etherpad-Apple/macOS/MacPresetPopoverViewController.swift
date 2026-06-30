import AppKit

protocol MacPresetPopoverDelegate: AnyObject {
    /// The currently selected config, used to seed Save and to highlight the active row.
    func currentPreset() -> MacPreset
    func loadPreset(_ preset: MacPreset)
    func resetToDefaults()
}

/// Saved-presets list shown in an NSPopover. Rows reveal edit/delete on hover; rename
/// and delete-confirm happen inline.
final class MacPresetPopoverViewController: NSViewController {

    weak var delegate: MacPresetPopoverDelegate?
    /// Set by the owner that presents this in an NSPopover (a popover content VC has no
    /// presentingViewController, so it can't dismiss itself).
    var onRequestClose: (() -> Void)?

    private let accent = NSColor(red: 0x3d/255, green: 0xd6/255, blue: 0xd6/255, alpha: 1)
    private let width: CGFloat = 340
    private let rowHeight: CGFloat = 54
    private let headerHeight: CGFloat = 40
    private let maxVisibleRows = 6

    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!
    private var saveButton: NSButton!
    private var presets: [MacPreset] = []

    /// id of the row currently in inline rename, if any.
    private var editingID: UUID?

    override func loadView() {
        presets = MacPresetStore.presets

        let container = EndEditingEffectView()
        container.material = .menu
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true

        let header = makeHeader()
        let scroll = makeTable()

        emptyLabel = NSTextField(labelWithString: "No presets yet")
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, separator(), scroll])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        container.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])

        view = container
        refresh()

        NotificationCenter.default.addObserver(
            self, selector: #selector(presetsChanged),
            name: MacPresetStore.didChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Header (Save + Reset)

    private func makeHeader() -> NSView {
        let save = NSButton(title: "  Save current", target: self, action: #selector(saveTapped))
        save.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Save")
        save.imagePosition = .imageLeading
        save.bezelStyle = .accessoryBar
        save.isBordered = false
        save.contentTintColor = accent
        save.font = .systemFont(ofSize: 13, weight: .medium)
        saveButton = save

        let reset = NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise",
                                            accessibilityDescription: "Reset to defaults")!,
                             target: self, action: #selector(resetTapped))
        reset.imagePosition = .imageOnly
        reset.bezelStyle = .accessoryBar
        reset.isBordered = false
        reset.contentTintColor = .secondaryLabelColor
        reset.toolTip = "Reset to factory defaults"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [save, spacer, reset])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    // MARK: - Table

    private func makeTable() -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.selectionHighlightStyle = .none
        table.gridStyleMask = []
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preset"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .light
        scroll.autohidesScrollers = true
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.translatesAutoresizingMaskIntoConstraints = false
        tableView = table
        return scroll
    }

    // MARK: - State

    private var rows: [MacPreset] { presets }

    private func refresh() {
        tableView.reloadData()
        emptyLabel.isHidden = !rows.isEmpty
        let count = min(max(rows.count, 1), maxVisibleRows)
        preferredContentSize = NSSize(width: width, height: headerHeight + 1 + CGFloat(count) * rowHeight)
    }

    @objc private func presetsChanged() {
        // A store mutation can originate from inside controlTextDidEndEditing; defer the
        // reload one tick so the table isn't reloaded mid-end-editing.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.presets = MacPresetStore.presets
            self.refresh()
        }
    }

    // MARK: - Header actions

    /// Saves immediately with the auto-generated name (no Enter step). At the cap, the
    /// button label briefly turns into an error instead of saving.
    @objc private func saveTapped() {
        guard let delegate = delegate else { return }
        guard !MacPresetStore.isFull else { flashSaveError("Max \(MacPresetStore.maxPresets) presets"); return }
        let c = delegate.currentPreset()
        MacPresetStore.add(MacPreset(
            name: MacPreset.suggestedName(scale: c.scale, key: c.key, octave: c.octave,
                                          sound: c.sound, maxLength: MacPresetStore.maxNameLength),
            scale: c.scale, key: c.key, octave: c.octave, size: c.size, sound: c.sound))
    }

    private var saveErrorWork: DispatchWorkItem?
    private func flashSaveError(_ message: String) {
        NSSound.beep()
        saveErrorWork?.cancel()
        saveButton.image = nil
        saveButton.title = message
        saveButton.contentTintColor = .systemRed
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.saveButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Save")
            self.saveButton.imagePosition = .imageLeading
            self.saveButton.title = "  Save current"
            self.saveButton.contentTintColor = self.accent
        }
        saveErrorWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    @objc private func resetTapped() {
        delegate?.resetToDefaults()
        dismissSelf()
    }

    // MARK: - Row actions
    // Rows are resolved by id (not by a captured index) since reloads can reorder.

    private func index(of id: UUID) -> Int? { rows.firstIndex { $0.id == id } }

    private func loadRow(id: UUID) {
        guard editingID == nil, let i = index(of: id) else { return }
        delegate?.loadPreset(rows[i])
        dismissSelf()
    }

    private func beginEditing(id: UUID) {
        guard index(of: id) != nil else { return }
        editingID = id
        refresh()
        DispatchQueue.main.async { [weak self] in self?.focusEditor(id: id) }
    }

    private func focusEditor(id: UUID) {
        guard let i = index(of: id),
              let cell = tableView.view(atColumn: 0, row: i, makeIfNecessary: false) as? PresetRowView
        else { return }
        cell.focusEditor()
    }

    // commit/cancel are invoked from controlTextDidEndEditing, so defer the table reload
    // to the next runloop tick rather than reloading mid-end-editing.
    private func commitEdit(id: UUID, newName: String) {
        editingID = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            MacPresetStore.rename(id: id, to: trimmed)
        } else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }

    private func cancelEdit(id: UUID) {
        editingID = nil
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    private func confirmDelete(id: UUID) {
        MacPresetStore.delete(id: id)
    }

    private func dismissSelf() {
        onRequestClose?()
    }
}

extension MacPresetPopoverViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PresetBackgroundRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let preset = rows[row]
        let isActive = delegate.map { matches(preset, $0.currentPreset()) } ?? false

        let id = preset.id
        let cell = PresetRowView()
        cell.accent = accent
        cell.configure(name: preset.name, detail: preset.summary,
                       active: isActive, editing: id == editingID)
        cell.onLoad     = { [weak self] in self?.loadRow(id: id) }
        cell.onEdit     = { [weak self] in self?.beginEditing(id: id) }
        cell.onCommit   = { [weak self] name in self?.commitEdit(id: id, newName: name) }
        cell.onCancel   = { [weak self] in self?.cancelEdit(id: id) }
        cell.onDelete   = { [weak self] in self?.confirmDelete(id: id) }
        return cell
    }

    private func matches(_ a: MacPreset, _ b: MacPreset) -> Bool {
        a.scale == b.scale && a.key == b.key && a.octave == b.octave
            && a.size == b.size && a.sound == b.sound
    }
}

/// No default blue selection; hover tracking drives the row's own highlight.
private final class PresetBackgroundRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}
}

private final class EndEditingEffectView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder is NSText {
            window?.makeFirstResponder(nil)
        }
        super.mouseDown(with: event)
    }
}
