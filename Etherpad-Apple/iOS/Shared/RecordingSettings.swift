import Foundation

final class RecordingSettings {
    private static let key = "EtherpadRecordingEnabled"
    static let didChangeNotification = NSNotification.Name("EtherpadRecordingSettingDidChange")

    // Hard cap on one recording. Raise to extend everywhere.
    static let maxDuration: TimeInterval = 10 * 60

    // Grace after backgrounding before finalizing; returning within it keeps the take.
    static let backgroundGracePeriod: TimeInterval = 10

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}
