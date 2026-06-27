import AppKit

/// Color theme for the macOS synth surface.
///
/// Adding a theme is a one-liner: append a `MacTheme` to `all`. The surface and
/// the Settings picker read from `all`/`current`, so nothing else needs editing.
/// All accent-tinted visuals (active circles, ripples, trails, column glow) are
/// derived from a single `accent` color to keep palettes consistent.
struct MacTheme: Equatable {
    let id: String
    let name: String
    let background: NSColor
    let line: NSColor
    let accent: NSColor

    // MARK: Palettes (default first; it must stay the current Slate look)
    static let all: [MacTheme] = [.slate, .midnight, .ember, .forest, .sakura, .obsidian]
    static let `default`: MacTheme = .slate

    static let slate = MacTheme(
        id: "slate", name: "Slate",
        background: rgb(0x3b, 0x44, 0x4b),
        line:       rgb(0x50, 0x72, 0xa7),
        accent:     rgb(0xe9, 0xd6, 0x6b))

    static let midnight = MacTheme(
        id: "midnight", name: "Midnight",
        background: rgb(0x14, 0x16, 0x24),
        line:       rgb(0x3d, 0x5a, 0x80),
        accent:     rgb(0xc7, 0x7d, 0xff))

    static let ember = MacTheme(
        id: "ember", name: "Ember",
        background: rgb(0x24, 0x15, 0x12),
        line:       rgb(0x7a, 0x42, 0x2f),
        accent:     rgb(0xff, 0x8c, 0x42))

    static let forest = MacTheme(
        id: "forest", name: "Forest",
        background: rgb(0x12, 0x22, 0x1b),
        line:       rgb(0x2f, 0x6b, 0x4f),
        accent:     rgb(0x9b, 0xe5, 0x64))

    static let sakura = MacTheme(
        id: "sakura", name: "Sakura",
        background: rgb(0x2a, 0x1d, 0x24),
        line:       rgb(0x7a, 0x4f, 0x63),
        accent:     rgb(0xff, 0x9e, 0xc4))

    static let obsidian = MacTheme(
        id: "obsidian", name: "Obsidian",
        background: rgb(0x0c, 0x0d, 0x10),
        line:       rgb(0x33, 0x3a, 0x45),
        accent:     rgb(0x5a, 0xd1, 0xe6))

    // MARK: Derived colors used by the surface
    var circleColor: NSColor { accent.withAlphaComponent(0.5) }
    var glowColor:   NSColor { accent.withAlphaComponent(0.07) }
    func accent(alpha: CGFloat) -> NSColor { accent.withAlphaComponent(alpha) }

    // MARK: Persistence
    private static let key = "EtherpadTheme"
    static var current: MacTheme {
        get {
            let id = UserDefaults.standard.string(forKey: key)
            return all.first { $0.id == id } ?? .default
        }
        set {
            UserDefaults.standard.set(newValue.id, forKey: key)
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

extension Notification.Name {
    static let themeChanged = Notification.Name("EtherpadThemeChanged")
}
