import Foundation

enum PresetStore {
    static let maxPresets = 10
    static let maxNameLength = 32
    static let didChangeNotification = NSNotification.Name("EtherpadPresetsDidChange")

    private static let key = "EtherpadPresets"

    static var presets: [Preset] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Preset].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static var isFull: Bool { presets.count >= maxPresets }

    @discardableResult
    static func add(_ preset: Preset) -> Bool {
        guard !isFull else { return false }
        presets.append(preset)
        return true
    }

    static func delete(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    static func rename(id: UUID, to name: String) {
        var current = presets
        guard let i = current.firstIndex(where: { $0.id == id }) else { return }
        current[i].name = String(name.prefix(maxNameLength))
        presets = current
    }
}
