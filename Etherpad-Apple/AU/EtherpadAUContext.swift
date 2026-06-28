import Foundation

/// Links the AU factory-created audio unit to the extension view controller.
/// Apple hosts instantiate both separately; this holder avoids hard-wiring the VC to a concrete AU subclass.
enum EtherpadAUContext {
    weak static var audioUnit: EtherpadAudioUnit?
}
