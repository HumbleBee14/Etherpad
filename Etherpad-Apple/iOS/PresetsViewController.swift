import UIKit

final class PresetsViewController: UITableViewController {

    private let currentPatch: () -> SynthPatchState
    private let onLoad: (Preset) -> Void
    private var presets: [Preset] = PresetStore.presets

    init(currentPatch: @escaping () -> SynthPatchState, onLoad: @escaping (Preset) -> Void) {
        self.currentPatch = currentPatch
        self.onLoad = onLoad
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Presets"
        let theme = Theme.current
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.tableFooterView = UIView()

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismissSheet))
        refreshAddButton()

        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: PresetStore.didChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func dismissSheet() { dismiss(animated: true) }

    @objc private func storeChanged() {
        presets = PresetStore.presets
        refreshAddButton()
        tableView.reloadData()
    }

    private func refreshAddButton() {
        if PresetStore.isFull {
            let item = UIBarButtonItem(title: "Max limit reached", style: .plain, target: nil, action: nil)
            item.isEnabled = false
            navigationItem.rightBarButtonItem = item
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .add, target: self, action: #selector(savePressed))
        }
    }

    // MARK: - Save / rename prompt

    @objc private func savePressed() {
        let patch = currentPatch()
        let suggested = Preset.suggestedName(for: patch, maxLength: PresetStore.maxNameLength)
        promptName(title: "Save Preset", initial: suggested) { name in
            let final = name.isEmpty ? suggested : name
            PresetStore.add(Preset(name: final, patch: patch))
        }
    }

    private func promptRename(_ preset: Preset) {
        promptName(title: "Rename Preset", initial: preset.name) { name in
            let final = name.isEmpty ? preset.name : name
            PresetStore.rename(id: preset.id, to: final)
        }
    }

    private func promptName(title: String, initial: String, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = initial
            tf.clearButtonMode = .whileEditing
            tf.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let raw = alert.textFields?.first?.text ?? ""
            let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(PresetStore.maxNameLength))
            completion(trimmed)
        })
        present(alert, animated: true)
    }

    // MARK: - Table

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int {
        presets.isEmpty ? 1 : presets.count
    }

    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = UIColor(white: 0.96, alpha: 1)
        cell.detailTextLabel?.textColor = UIColor(white: 1.0, alpha: 0.55)

        if presets.isEmpty {
            cell.textLabel?.text = "No presets yet"
            cell.detailTextLabel?.text = "Tap + to save this sound"
            cell.selectionStyle = .none
            return cell
        }
        let preset = presets[ip.row]
        cell.textLabel?.text = preset.name
        cell.detailTextLabel?.text = Preset.summary(for: preset.patch)
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        guard !presets.isEmpty else { return }
        onLoad(presets[ip.row])
        dismiss(animated: true)
    }

    override func tableView(_ t: UITableView,
                            trailingSwipeActionsConfigurationForRowAt ip: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard !presets.isEmpty else { return nil }
        let preset = presets[ip.row]

        let del = UIContextualAction(style: .destructive, title: nil) { _, _, done in
            PresetStore.delete(id: preset.id)
            done(true)
        }
        del.image = UIImage(systemName: "trash")

        let rename = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, done in
            self?.promptRename(preset)
            done(true)
        }
        rename.image = UIImage(systemName: "pencil")

        return UISwipeActionsConfiguration(actions: [rename, del])
    }
}
