// SplitModeController.swift — manages split-screen dual-synth mode on iPad
//
// Persists split mode on/off state to UserDefaults and posts notifications
// when the state changes. Used by SceneDelegate (route decision) and
// AboutViewController (toggle UI).

import UIKit

final class SplitModeController {
    private static let key = "EtherpadSplitModeEnabled"
    static let didChangeNotification = NSNotification.Name("EtherpadSplitModeDidChange")

    // Default: split mode OFF (single synth) on first launch
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}
