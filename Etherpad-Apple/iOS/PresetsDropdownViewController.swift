import UIKit

/// Compact dropdown of presets, presented as a popover under the toolbar slider icon.
/// Tap a row to load; long-press a row to edit (rename / delete).
final class PresetsDropdownViewController: UITableViewController {

    private let currentPatch: () -> SynthPatchState
    private let onLoad: (Preset) -> Void
    private var presets: [Preset] = PresetStore.presets

    private let rowHeight: CGFloat = 52
    private let saveRowHeight: CGFloat = 44
    private let popoverWidth: CGFloat = 280
    private let maxVisiblePresetRows = 6

    init(currentPatch: @escaping () -> SynthPatchState, onLoad: @escaping (Preset) -> Void) {
        self.currentPatch = currentPatch
        self.onLoad = onLoad
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        tableView.backgroundColor = .clear
        tableView.backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.tableFooterView = UIView()

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(lp)

        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: PresetStore.didChangeNotification, object: nil)

        updatePreferredSize()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func storeChanged() {
        presets = PresetStore.presets
        tableView.reloadData()
        updatePreferredSize()
    }

    private func updatePreferredSize() {
        let visible = min(presets.count, maxVisiblePresetRows)
        let height = saveRowHeight + CGFloat(visible) * rowHeight
            + (presets.isEmpty ? rowHeight : 0)
        preferredContentSize = CGSize(width: popoverWidth, height: height)
    }

    // MARK: - Sections: 0 = Save row, 1 = presets

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int {
        if s == 0 { return 1 }
        return presets.isEmpty ? 1 : presets.count
    }

    override func tableView(_ t: UITableView, heightForRowAt ip: IndexPath) -> CGFloat {
        ip.section == 0 ? saveRowHeight : rowHeight
    }

    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        if ip.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = .clear
            cell.textLabel?.text = "Save current…"
            cell.textLabel?.textColor = Theme.current.accent
            cell.textLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            cell.imageView?.image = UIImage(systemName: "plus")
            cell.imageView?.tintColor = Theme.current.accent
            return cell
        }

        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = .clear

        if presets.isEmpty {
            cell.textLabel?.text = "No presets yet"
            cell.textLabel?.textColor = UIColor(white: 1.0, alpha: 0.55)
            cell.textLabel?.font = .systemFont(ofSize: 14)
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .none
            return cell
        }

        let preset = presets[ip.row]
        let isCurrent = preset.patch == currentPatch()
        cell.textLabel?.text = preset.name
        cell.textLabel?.textColor = isCurrent ? Theme.current.accent : UIColor(white: 0.96, alpha: 1)
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cell.textLabel?.numberOfLines = 1
        cell.textLabel?.lineBreakMode = .byTruncatingTail

        cell.detailTextLabel?.text = Preset.summary(for: preset.patch)
        cell.detailTextLabel?.textColor = UIColor(white: 1.0, alpha: 0.55)
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.detailTextLabel?.numberOfLines = 1
        cell.detailTextLabel?.lineBreakMode = .byTruncatingTail
        return cell
    }

    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        if ip.section == 0 {
            promptSave()
            return
        }
        guard !presets.isEmpty else { return }
        onLoad(presets[ip.row])
        dismiss(animated: true)
    }

    // MARK: - Long press to edit

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, !presets.isEmpty else { return }
        let point = g.location(in: tableView)
        guard let ip = tableView.indexPathForRow(at: point), ip.section == 1 else { return }
        presentEditPopup(for: presets[ip.row])
    }

    // MARK: - Prompts

    private func promptSave() {
        guard !PresetStore.isFull else {
            let alert = UIAlertController(title: "Preset limit reached",
                                          message: "Delete a preset to save a new one.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let patch = currentPatch()
        let suggested = Preset.suggestedName(for: patch, maxLength: PresetStore.maxNameLength)
        let alert = UIAlertController(title: "Save Preset", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = suggested
            tf.clearButtonMode = .whileEditing
            tf.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let name = Self.trimmed(alert.textFields?.first?.text)
            PresetStore.add(Preset(name: name.isEmpty ? suggested : name, patch: patch))
        })
        present(alert, animated: true)
    }

    private func presentEditPopup(for preset: Preset) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = preset.name
            tf.clearButtonMode = .whileEditing
            tf.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            PresetStore.delete(id: preset.id)
        })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let name = Self.trimmed(alert.textFields?.first?.text)
            PresetStore.rename(id: preset.id, to: name.isEmpty ? preset.name : name)
        })
        present(alert, animated: true)
    }

    private static func trimmed(_ raw: String?) -> String {
        String((raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(PresetStore.maxNameLength))
    }
}
