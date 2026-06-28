import AVFAudio
import AudioToolbox

public final class EtherpadAudioUnit: AUAudioUnit {

    /// Host-pull synth kernel — conforms to `HostAudioEngine` for testability and future AU parameter mapping.
    let hostEngine = HostCsoundEngine()

    private var outputBus: AUAudioUnitBus!
    private var _outputBusArray: AUAudioUnitBusArray!
    private let resourceLocator = SynthResourceLocator.auExtension(in: EtherpadAudioUnit.self)

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])

        maximumFramesToRender = 4096
        EtherpadAUContext.audioUnit = self
    }

    deinit {
        if EtherpadAUContext.audioUnit === self {
            EtherpadAUContext.audioUnit = nil
        }
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusArray }

    public override var canProcessInPlace: Bool { false }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let sr = outputBus.format.sampleRate
        try hostEngine.startHost(sampleRate: sr, resources: resourceLocator)
    }

    public override func deallocateRenderResources() {
        hostEngine.stopHost()
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let engine = hostEngine
        return { _, _, frameCount, _, outputData, _, _ in
            return engine.render(into: outputData, frameCount: frameCount)
        }
    }
}
