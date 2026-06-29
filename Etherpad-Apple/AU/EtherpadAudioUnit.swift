import AVFAudio
import AudioToolbox

/// Production-grade AUv3 instrument audio unit for Etherpad.
///
/// Provides:
/// - Full `AUParameterTree` with 5 automatable parameters
/// - Comprehensive MIDI input: MIDI 1.0 fully, plus MIDI 2.0 UMP Channel Voice
///   (16-bit velocity, per-note pitch bend, per-note brightness)
/// - MIDI output from touch pad gestures
/// - State persistence via `fullState` for host session save/restore
/// - 10 factory presets
/// - Tail time reporting for reverb/delay tail
///
/// Hosts discover this unit via the Info.plist `AudioComponents` entry
/// (type=aumu, subtype=EthP, manufacturer=HmBe).
@objc(EtherpadAudioUnit)
public final class EtherpadAudioUnit: AUAudioUnit {

    // MARK: - Audio Engine

    /// Host-pull synth kernel — Csound-based sound engine.
    let hostEngine = HostCsoundEngine()

    private var outputBus: AUAudioUnitBus!
    private var _outputBusArray: AUAudioUnitBusArray!
    private let resourceLocator = SynthResourceLocator.auExtension(in: EtherpadAudioUnit.self)

    // MARK: - MIDI

    /// Processes incoming MIDI events from host keyboards and external controllers.
    let midiProcessor = MIDIProcessor()

    /// Converts touch pad gestures to MIDI output events for host routing.
    let midiOutputHandler = MIDIOutputHandler()

    // MARK: - Parameters

    private var _parameterTree: AUParameterTree!

    // MARK: - Presets

    private var _currentPreset: AUAudioUnitPreset?

    /// Prevents `implementorValueObserver` re-entry while pushing engine state to the tree.
    private var isSyncingParameters = false

    /// Originator token for our own gesture writes. Passed as the originator so the
    /// UI-refresh observer skips them — the engine still updates via
    /// `implementorValueObserver`, which then refreshes the UI through `onUIStateChanged`.
    private var uiObserverToken: AUParameterObserverToken?

    // MARK: - Init

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])

        maximumFramesToRender = 4096

        configureParameterTree()
        configureMIDI()

        // Apply default preset values to parameter tree
        syncParameterTreeFromEngine()
    }

    // MARK: - Parameter Tree Configuration

    private func configureParameterTree() {
        _parameterTree = EtherpadParameterFactory.createParameterTree()

        // When a host (or the AU's own UI) writes a parameter, push it to the engine.
        _parameterTree.implementorValueObserver = { [weak self] param, value in
            guard let self, !self.isSyncingParameters else { return }
            self.hostEngine.applyParameterChange(param.address, value: value)
            self.midiProcessor.patchState = self.hostEngine.currentPatchState
            self.midiOutputHandler.patchState = self.hostEngine.currentPatchState
        }

        // When the host reads a parameter, pull from the engine.
        _parameterTree.implementorValueProvider = { [weak self] param in
            self?.hostEngine.parameterValue(for: param.address) ?? param.value
        }

        // String representation for indexed parameters
        _parameterTree.implementorStringFromValueCallback = { param, valuePtr in
            let value = Int(valuePtr?.pointee ?? param.value)
            switch param.address {
            case EtherpadParameterAddress.scale.rawValue:
                return value < SynthCatalog.scaleOptions.count
                    ? SynthCatalog.scaleOptions[value].name : "?"
            case EtherpadParameterAddress.key.rawValue:
                return value < SynthCatalog.keyNames.count
                    ? SynthCatalog.keyNames[value] : "?"
            case EtherpadParameterAddress.octave.rawValue:
                return value < SynthCatalog.octaveLabels.count
                    ? SynthCatalog.octaveLabels[value] : "?"
            case EtherpadParameterAddress.size.rawValue:
                return value < SynthCatalog.sizeLabels.count
                    ? SynthCatalog.sizeLabels[value] : "?"
            case EtherpadParameterAddress.sound.rawValue:
                return value < SynthCatalog.soundNames.count
                    ? SynthCatalog.soundNames[value] : "?"
            default:
                return "\(Int(valuePtr?.pointee ?? param.value))"
            }
        }

        // UI-refresh observer: keeps the plugin UI in sync when a host writes a parameter
        // while the engine isn't running (no onPatchStateChanged callback yet). Our own
        // gesture writes pass uiObserverToken as originator so they skip this block — they
        // already refresh the UI via implementorValueObserver -> onUIStateChanged.
        uiObserverToken = _parameterTree.token(byAddingParameterObserver: { [weak self] _, _ in
            guard let self else { return }
            let patch = self.hostEngine.currentPatchState
            let notify: () -> Void = { self.onUIStateChanged?(patch) }
            if Thread.isMainThread { notify() } else { DispatchQueue.main.async(execute: notify) }
        })
    }

    /// Write a recordable automation gesture for a discrete menu change.
    /// `.touch`/`.value`/`.release` back-to-back so the host records the change with no drag.
    /// `implementorValueObserver` still fires and updates the engine; the originator token
    /// suppresses only our UI-refresh observer (no feedback loop).
    func recordParameterGesture(address: EtherpadParameterAddress, index: AUValue) {
        guard let param = EtherpadParameterFactory.parameter(for: address, in: _parameterTree) else { return }
        // Stamp the gesture with the real host time; `atHostTime: 0` makes hosts record the
        // change at timeline zero (or drop it) instead of at the playhead.
        let now = mach_absolute_time()
        param.setValue(index, originator: uiObserverToken, atHostTime: now, eventType: .touch)
        param.setValue(index, originator: uiObserverToken, atHostTime: now, eventType: .value)
        param.setValue(index, originator: uiObserverToken, atHostTime: now, eventType: .release)
    }

    /// Push current engine patch state to the parameter tree (e.g., after preset load).
    private func syncParameterTreeFromEngine() {
        isSyncingParameters = true
        defer { isSyncingParameters = false }

        let values = hostEngine.currentPatchState.toParameterValues()
        for (addr, value) in values {
            if let param = EtherpadParameterFactory.parameter(for: addr, in: _parameterTree) {
                param.value = value
            }
        }
    }

    // MARK: - MIDI Configuration

    /// View controller sets this to receive patch state updates for UI refresh.
    /// **Do not** overwrite `hostEngine.onPatchStateChanged` — the AU owns that.
    var onUIStateChanged: ((SynthPatchState) -> Void)?

    private func configureMIDI() {
        midiProcessor.engine = hostEngine

        // When engine patch state changes (from UI menus, host automation, presets),
        // sync MIDI processors and notify VC. The AU owns this callback — VC uses
        // `onUIStateChanged` instead to avoid overwrites.
        hostEngine.onPatchStateChanged = { [weak self] patchState in
            // Patch snapshots must update immediately for the next render quantum.
            self?.midiProcessor.patchState = patchState
            self?.midiOutputHandler.patchState = patchState
            // Parameter tree + UI must stay on the main thread.
            let syncUI = {
                self?.syncParameterTreeFromEngine()
                self?.onUIStateChanged?(patchState)
            }
            if Thread.isMainThread {
                syncUI()
            } else {
                DispatchQueue.main.async(execute: syncUI)
            }
        }
    }

    // MARK: - AUAudioUnit Overrides

    public override var parameterTree: AUParameterTree? {
        get { _parameterTree }
        set { /* Required by API but we manage our own tree */ }
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusArray }

    public override var canProcessInPlace: Bool { false }

    /// Receive native MIDI 2.0 (UMP) when the host supports it; CoreMIDI translates
    /// MIDI 1.0 hosts to this protocol. Without this override the AU gets legacy MIDI.
    public override var audioUnitMIDIProtocol: MIDIProtocolID { ._2_0 }

    /// Reverb + delay tail in the CSD is roughly 2 seconds.
    public override var tailTime: TimeInterval { 2.0 }

    /// Csound k-period latency at the host sample rate.
    public override var latency: TimeInterval {
        hostEngine.reportedLatency
    }

    // MARK: - Render Resources

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let sr = outputBus.format.sampleRate
        try hostEngine.startHost(sampleRate: sr, resources: resourceLocator)

        // Sync MIDI processors with current patch state
        midiProcessor.patchState = hostEngine.currentPatchState
        midiOutputHandler.patchState = hostEngine.currentPatchState
        midiOutputHandler.midiOutputBlock = midiOutputEventBlock
    }

    public override func deallocateRenderResources() {
        midiProcessor.allNotesOff()
        // Rendering has stopped, so the queue can't drain — flush note-offs directly.
        midiOutputHandler.flushActiveNotesOffSync()
        hostEngine.allNotesOff()
        hostEngine.stopHost()
        super.deallocateRenderResources()
    }

    // MARK: - Render Block

    public override var internalRenderBlock: AUInternalRenderBlock {
        let engine = hostEngine
        let midi = midiProcessor
        let midiOut = midiOutputHandler
        return { _, timestamp, frameCount, _, outputData, eventList, _ in
            if let eventList {
                midi.processRenderEvents(eventList)
            }
            midiOut.render(at: AUEventSampleTime(timestamp.pointee.mSampleTime))
            return engine.render(into: outputData, frameCount: frameCount)
        }
    }

    // MARK: - MIDI Output

    /// Advertise MIDI output port so hosts (AUM, etc.) can route touch pad → MIDI.
    public override var midiOutputNames: [String] { ["Etherpad Touch"] }

    // MARK: - State Persistence

    /// All Etherpad patch settings are document-scoped (scale, key, octave, etc.).
    public override var fullStateForDocument: [String: Any]? {
        get { fullState }
        set { fullState = newValue }
    }

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            state[SynthPatchState.stateKey] = hostEngine.currentPatchState.toDictionary()
            if let preset = _currentPreset {
                state[kAUPresetNameKey] = preset.name
                state[kAUPresetNumberKey] = preset.number
            }
            return state
        }
        set {
            super.fullState = newValue
            if let dict = newValue?[SynthPatchState.stateKey] as? [String: Any],
               let patch = SynthPatchState(dictionary: dict) {
                hostEngine.applyPatchState(patch)
                midiProcessor.patchState = patch
                midiOutputHandler.patchState = patch
                syncParameterTreeFromEngine()
            }
            // Restore preset reference
            if let name = newValue?[kAUPresetNameKey] as? String,
               let number = newValue?[kAUPresetNumberKey] as? Int {
                let preset = AUAudioUnitPreset()
                preset.number = number
                preset.name = name
                _currentPreset = preset
            }
        }
    }

    public override var supportsUserPresets: Bool { true }

    // MARK: - Factory Presets

    public override var factoryPresets: [AUAudioUnitPreset]? {
        EtherpadPresets.factory
    }

    public override var currentPreset: AUAudioUnitPreset? {
        get { _currentPreset }
        set {
            guard let preset = newValue else {
                _currentPreset = nil
                return
            }

            if preset.number >= 0 {
                // Factory preset: ignore an out-of-range number rather than show it as selected.
                guard let patch = EtherpadPresets.patchState(for: preset.number) else { return }
                hostEngine.applyPatchState(patch)
                midiProcessor.patchState = patch
                midiOutputHandler.patchState = patch
                syncParameterTreeFromEngine()
            }
            // User presets (number < 0) are restored via fullState by the framework.
            _currentPreset = preset
        }
    }

    // MARK: - Host Overview Parameters

    /// AUM uses the first parameter from this list as the "main knob" on the plugin node.
    public override func parametersForOverview(withCount count: Int) -> [NSNumber] {
        let addresses: [EtherpadParameterAddress] = [.scale, .key, .sound, .octave, .size]
        return Array(addresses.prefix(count)).map { NSNumber(value: $0.rawValue) }
    }
}

// MARK: - Preset Key Constants

private let kAUPresetNameKey = "name"
private let kAUPresetNumberKey = "number"
