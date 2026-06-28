import Foundation
import AudioToolbox

@objc(EtherpadAUFactory)
public final class EtherpadAUFactory: NSObject, AUAudioUnitFactory {

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        try EtherpadAudioUnit(componentDescription: componentDescription, options: [])
    }

    public func beginRequest(with context: NSExtensionContext) {}
}
