import Foundation
import AudioToolbox

/// Voice control API implemented by standalone (`CsoundEngine`) and AU (`HostCsoundEngine`) backends.
protocol SynthEngineProtocol: AnyObject {
    func noteOn(slot: Int, x: Float, y: Float)
    func updatePosition(slot: Int, x: Float, y: Float)
    func noteOff(slot: Int)
    func allNotesOff()
    func setSize(_ size: Int)
    func setKey(_ key: Int)
    func setOctave(_ octave: Int)
    func setSound(_ sound: Int)
    func setScale(_ steps: [Int])
}

extension SynthEngineProtocol {
    func applyPatch(_ patch: SynthPatchState) {
        patch.apply(to: self)
    }
}

/// Host-pull audio (AUv3). Standalone uses device I/O instead.
protocol HostAudioEngine: SynthEngineProtocol {
    func startHost(sampleRate: Double, resources: SynthResourceLocator) throws
    func stopHost()
    func render(into bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) -> OSStatus
}

/// Bundle resolution for etherpad.csd — avoids hardcoding `Bundle.main` in engines.
struct SynthResourceLocator {
    let bundle: Bundle

    static func mainApp() -> SynthResourceLocator { SynthResourceLocator(bundle: .main) }

    static func auExtension(in type: AnyClass) -> SynthResourceLocator {
        SynthResourceLocator(bundle: Bundle(for: type))
    }

    var csdURL: URL? {
        bundle.url(forResource: SynthAsset.csdName, withExtension: SynthAsset.csdExtension)
    }
}

enum SynthAsset {
    static let csdName = "etherpad"
    static let csdExtension = "csd"
}
