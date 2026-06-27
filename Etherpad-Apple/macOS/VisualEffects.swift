import Foundation

struct VisualEffects: OptionSet {
    let rawValue: Int
    static let ripple      = VisualEffects(rawValue: 1 << 0)
    static let trail       = VisualEffects(rawValue: 1 << 1)
    static let intensity   = VisualEffects(rawValue: 1 << 2)
    static let columnGlow  = VisualEffects(rawValue: 1 << 3)

    static let none: VisualEffects = []
    static let all: [Self] = [.ripple, .trail, .intensity, .columnGlow]

    var label: String {
        switch self {
        case .ripple:     return "Ripple"
        case .trail:      return "Trail"
        case .intensity:  return "Intensity Ring"
        case .columnGlow: return "Column Glow"
        default:          return ""
        }
    }

    private static let key = "EtherpadVisualEffects"
    static var current: VisualEffects {
        get { VisualEffects(rawValue: UserDefaults.standard.integer(forKey: key)) }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: .visualEffectsChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let visualEffectsChanged = Notification.Name("EtherpadVisualEffectsChanged")
    static let touchHoldChanged = Notification.Name("EtherpadTouchHoldChanged")
}

/// How a held-still trackpad touch is kept alive.
/// - `native`: trust the trackpad's own lift detection (resting touches stay sounding
///   until the finger physically lifts). Best for sustained notes.
/// - `timed`: auto-release a touch after `timeout` of no movement — a safety net in
///   case macOS drops a lift event, at the cost of cutting off long held notes.
enum TouchHoldMode: Int {
    case native = 0
    case timed  = 1
}

enum TouchHoldSettings {
    private static let modeKey    = "EtherpadTouchHoldMode"
    private static let timeoutKey = "EtherpadTouchHoldTimeout"

    static let defaultTimeout: TimeInterval = 6.0
    static let minTimeout: TimeInterval = 0.5
    static let maxTimeout: TimeInterval = 30.0

    static var mode: TouchHoldMode {
        get { TouchHoldMode(rawValue: UserDefaults.standard.integer(forKey: modeKey)) ?? .native }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            notifyChange()
        }
    }

    static var timeout: TimeInterval {
        get {
            guard let v = UserDefaults.standard.object(forKey: timeoutKey) as? Double else {
                return defaultTimeout
            }
            return min(max(v, minTimeout), maxTimeout)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, minTimeout), maxTimeout), forKey: timeoutKey)
            notifyChange()
        }
    }

    private static func notifyChange() {
        NotificationCenter.default.post(name: .touchHoldChanged, object: nil)
    }
}
