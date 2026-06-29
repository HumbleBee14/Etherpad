import UIKit

/// Color theme for the iOS synth: surface, toolbar, Settings popup, and split divider.
///
/// Adding a theme is a one-liner — append a `Theme` to `all`. Every surface reads
/// from `all`/`current`, so nothing else changes. All accent-tinted visuals (touch
/// circles, ripples, trails, column glow, divider, picker highlights) derive from a
/// single `accent`, so palettes stay internally consistent and a future
/// per-element color picker only has to add fields here.
struct Theme: Equatable {
    let id: String
    let name: String
    let background: UIColor
    let line: UIColor
    let accent: UIColor

    // MARK: Palettes (default first; it must stay the current Slate look)
    static let all: [Theme] = [.slate, .midnight, .ember, .forest, .sakura, .obsidian]
    static let `default`: Theme = .slate

    static let slate = Theme(
        id: "slate", name: "Slate",
        background: rgb(0x3b, 0x44, 0x4b),
        line:       rgb(0x50, 0x72, 0xa7),
        accent:     rgb(0xe9, 0xd6, 0x6b))

    static let midnight = Theme(
        id: "midnight", name: "Midnight",
        background: rgb(0x14, 0x16, 0x24),
        line:       rgb(0x3d, 0x5a, 0x80),
        accent:     rgb(0xc7, 0x7d, 0xff))

    static let ember = Theme(
        id: "ember", name: "Ember",
        background: rgb(0x24, 0x15, 0x12),
        line:       rgb(0x7a, 0x42, 0x2f),
        accent:     rgb(0xff, 0x8c, 0x42))

    static let forest = Theme(
        id: "forest", name: "Forest",
        background: rgb(0x12, 0x22, 0x1b),
        line:       rgb(0x2f, 0x6b, 0x4f),
        accent:     rgb(0x9b, 0xe5, 0x64))

    static let sakura = Theme(
        id: "sakura", name: "Sakura",
        background: rgb(0x2a, 0x1d, 0x24),
        line:       rgb(0x7a, 0x4f, 0x63),
        accent:     rgb(0xff, 0x9e, 0xc4))

    static let obsidian = Theme(
        id: "obsidian", name: "Obsidian",
        background: rgb(0x0c, 0x0d, 0x10),
        line:       rgb(0x33, 0x3a, 0x45),
        accent:     rgb(0x5a, 0xd1, 0xe6))

    // MARK: Derived colors
    /// Filled touch circle under each finger.
    var circleColor: UIColor { accent.withAlphaComponent(0.5) }
    /// Pitch-column glow behind an active touch.
    var glowColor: UIColor { accent.withAlphaComponent(0.07) }
    /// Accent at an arbitrary alpha (ripples, trails).
    func accent(alpha: CGFloat) -> UIColor { accent.withAlphaComponent(alpha) }

    // MARK: Persistence
    private static let key = "EtherpadTheme"
    static var current: Theme {
        get {
            let id = UserDefaults.standard.string(forKey: key)
            return all.first { $0.id == id } ?? .default
        }
        set {
            UserDefaults.standard.set(newValue.id, forKey: key)
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

extension Notification.Name {
    static let themeChanged = Notification.Name("EtherpadThemeChanged")
}
