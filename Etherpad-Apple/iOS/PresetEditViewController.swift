import UIKit

/// Compact glass edit popup for a preset, pinned just above the keyboard.
/// Name field + Delete (left) / Save (right).
final class PresetEditViewController: UIViewController, UITextFieldDelegate {

    private let preset: Preset
    private let onSave: (String) -> Void

    private let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let field = UITextField()

    init(preset: Preset, onSave: @escaping (String) -> Void) {
        self.preset = preset
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        view.addGestureRecognizer(dismissTap)

        card.clipsToBounds = true
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        field.text = preset.name
        field.textColor = UIColor(white: 0.96, alpha: 1)
        field.font = .systemFont(ofSize: 16)
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = .words
        field.borderStyle = .roundedRect
        field.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        field.returnKeyType = .done
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(UIColor(white: 0.96, alpha: 1), for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancel.addTarget(self, action: #selector(backdropTapped), for: .touchUpInside)

        let save = UIButton(type: .system)
        save.setTitle("Save", for: .normal)
        save.setTitleColor(Theme.current.accent, for: .normal)
        save.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [cancel, save])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually

        let content = UIStackView(arrangedSubviews: [field, buttons])
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(content)

        let width = card.widthAnchor.constraint(equalToConstant: 360)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            width,
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            content.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),
            field.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        field.becomeFirstResponder()
    }

    @objc private func backdropTapped() { dismiss(animated: true) }

    @objc private func saveTapped() { commitSave() }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commitSave()
        return true
    }

    private func commitSave() {
        let raw = field.text ?? ""
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(PresetStore.maxNameLength))
        onSave(trimmed.isEmpty ? preset.name : trimmed)
        dismiss(animated: true)
    }
}
