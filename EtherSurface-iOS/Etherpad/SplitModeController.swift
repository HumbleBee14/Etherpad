import UIKit

final class SplitModeController {
    private static let key = "EtherpadSplitModeEnabled"
    static let didChangeNotification = NSNotification.Name("EtherpadSplitModeDidChange")

    static var isEnabled: Bool {
        get {
            // Only meaningful on iPad; always false on iPhone.
            guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
            if UserDefaults.standard.object(forKey: key) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}
