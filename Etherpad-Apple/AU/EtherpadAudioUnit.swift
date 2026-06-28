import AVFAudio
import AudioToolbox

@objc(EtherpadAudioUnit)
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
        hostEngine.allNotesOff()
        hostEngine.stopHost()
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let engine = hostEngine
        return { _, _, frameCount, _, outputData, eventList, _ in
            if let eventList {
                Self.processMIDIEvents(eventList, engine: engine)
            }
            return engine.render(into: outputData, frameCount: frameCount)
        }
    }

    /// Host keyboards (GarageBand, AUM) send note events through the render callback event list.
    private static func processMIDIEvents(_ head: UnsafePointer<AURenderEvent>, engine: HostCsoundEngine) {
        var event: UnsafePointer<AURenderEvent>? = head
        while let current = event {
            if current.pointee.head.eventType == .MIDI {
                handleMIDIMessage(current.pointee.MIDI, engine: engine)
            }
            guard let next = current.pointee.head.next else { break }
            event = UnsafePointer(next)
        }
    }

    private static func handleMIDIMessage(_ midi: AUMIDIEvent, engine: HostCsoundEngine) {
        let status = midi.data.0 & 0xF0
        let note = midi.data.1
        let velocity = midi.data.2
        switch status {
        case 0x90 where velocity > 0:
            let slot = Int(note) % SynthVoiceLayout.maxTouches
            let x = Float(note % 12) / 11.0
            let y = max(Float(velocity) / 127.0, 0.05)
            engine.noteOn(slot: slot, x: x, y: y)
        case 0x80, 0x90:
            let slot = Int(note) % SynthVoiceLayout.maxTouches
            engine.noteOff(slot: slot)
        default:
            break
        }
    }
}
