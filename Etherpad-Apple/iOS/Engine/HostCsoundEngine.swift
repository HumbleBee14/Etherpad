import Foundation
import AVFoundation
import AudioToolbox

/// Host-driven Csound backend for AUv3. Implements `HostAudioEngine`; standalone app uses `CsoundEngine` instead.
///
/// Thread safety: Csound’s `csoundEventString` is internally thread-safe (Csound 6+),
/// and single-`Float` channel pointer writes are atomic on ARM64. Parameter changes
/// from the host automation thread go through `applyParameterChange(_:value:)` which
/// calls `sendScore` — safe because Csound serialises event string processing.
final class HostCsoundEngine: HostAudioEngine {

    enum Error: Swift.Error {
        case csdNotFound
        case createFailed
        case compileFailed(Int32)
        case startFailed(Int32)
    }

    /// Called on the main thread whenever a patch parameter changes.
    /// The AU view controller observes this to keep toolbar menus in sync.
    var onPatchStateChanged: ((SynthPatchState) -> Void)?

    private var cs: OpaquePointer?
    private(set) var isRunning = false
    private var ksmps = 0
    private var nchnls = 0
    /// Current patch state — readable from any thread, written from main thread.
    private(set) var currentPatchState = SynthPatchState.factoryDefault
    /// Retained until Csound starts so pre-render menu changes are not lost.
    private var pendingPatch = SynthPatchState.factoryDefault

    private var xPtrs = [UnsafeMutablePointer<Float>?](
        repeating: nil, count: SynthVoiceLayout.maxTouches)
    private var yPtrs = [UnsafeMutablePointer<Float>?](
        repeating: nil, count: SynthVoiceLayout.maxTouches)

    private let noteOnScores:  [String]
    private let noteOffScores: [String]

    init() {
        var on = [String](); var off = [String]()
        for i in 0..<SynthVoiceLayout.maxTouches {
            on.append(SynthScore.noteOn(slot: i))
            off.append(SynthScore.noteOff(slot: i))
        }
        noteOnScores = on
        noteOffScores = off
    }

    func startHost(sampleRate: Double, resources: SynthResourceLocator) throws {
        guard !isRunning else { return }
        guard let path = resources.csdURL?.path else { throw Error.csdNotFound }
        guard let c = csoundCreate(nil, nil) else { throw Error.createFailed }
        cs = c
        csoundSetHostAudioIO(c)
        _ = csoundSetOption(c, "-+rtaudio=null")
        _ = csoundSetOption(c, "-d")
        _ = csoundSetOption(c, "--sample-rate=\(Int(sampleRate))")

        let dupd = [strdup("csound"), strdup(path)]
        defer { dupd.forEach { free($0) } }
        var argv: [UnsafePointer<CChar>?] = dupd.map { UnsafePointer($0) }
        let compileResult = argv.withUnsafeMutableBufferPointer { buf -> Int32 in
            csoundCompile(c, Int32(buf.count), buf.baseAddress)
        }
        guard compileResult == 0 else {
            csoundDestroy(c); cs = nil
            throw Error.compileFailed(compileResult)
        }

        let startResult = csoundStart(c)
        guard startResult == 0 else {
            csoundDestroy(c); cs = nil
            throw Error.startFailed(startResult)
        }

        ksmps = Int(csoundGetKsmps(c))
        nchnls = Int(csoundGetChannels(c, 0))
        bindChannels(c)
        isRunning = true
        pendingPatch.apply(to: self)
        currentPatchState = pendingPatch
    }

    func applyPatchState(_ patch: SynthPatchState) {
        pendingPatch = patch
        currentPatchState = patch
        if isRunning { patch.apply(to: self) }
    }

    func stopHost() {
        guard isRunning else { return }
        if let c = cs { csoundDestroy(c) }
        cs = nil
        for i in 0..<SynthVoiceLayout.maxTouches { xPtrs[i] = nil; yPtrs[i] = nil }
        isRunning = false
    }

    func render(into bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) -> OSStatus {
        guard isRunning, let cs = cs else { return noErr }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        var framesFilled = 0
        let total = Int(frameCount)
        let ks = ksmps
        let nch = nchnls

        while framesFilled < total {
            if csoundPerformKsmps(cs) != 0 {
                for buf in abl { memset(buf.mData, 0, Int(buf.mDataByteSize)) }
                return noErr
            }
            guard let spout = csoundGetSpout(cs) else { break }
            let n = min(ks, total - framesFilled)
            for ch in 0..<nch where ch < abl.count {
                let out = abl[ch].mData!.assumingMemoryBound(to: Float.self)
                for f in 0..<n {
                    out[framesFilled + f] = spout[f * nch + ch]
                }
            }
            framesFilled += n
        }
        return noErr
    }

    private func bindChannels(_ c: OpaquePointer) {
        let type = Int32(CSOUND_CONTROL_CHANNEL.rawValue) | Int32(CSOUND_INPUT_CHANNEL.rawValue)
        for i in 0..<SynthVoiceLayout.maxTouches {
            var xRaw: UnsafeMutableRawPointer?
            var yRaw: UnsafeMutableRawPointer?
            _ = csoundGetChannelPtr(c, &xRaw, "touch.\(i).x", type)
            _ = csoundGetChannelPtr(c, &yRaw, "touch.\(i).y", type)
            xPtrs[i] = xRaw?.assumingMemoryBound(to: Float.self)
            yPtrs[i] = yRaw?.assumingMemoryBound(to: Float.self)
        }
    }

    private func writeChannel(slot: Int, x: Float, y: Float) {
        xPtrs[slot]?.pointee = x
        yPtrs[slot]?.pointee = y
    }

    private func sendScore(_ s: String) {
        guard let cs = cs else { return }
        s.withCString { csoundEventString(cs, $0, 0) }
    }

    func noteOn(slot: Int, x: Float, y: Float) {
        guard isRunning, (0..<SynthVoiceLayout.maxTouches).contains(slot) else { return }
        writeChannel(slot: slot, x: x, y: y)
        sendScore(noteOnScores[slot])
    }

    func updatePosition(slot: Int, x: Float, y: Float) {
        guard isRunning, (0..<SynthVoiceLayout.maxTouches).contains(slot) else { return }
        writeChannel(slot: slot, x: x, y: y)
    }

    func noteOff(slot: Int) {
        guard isRunning, (0..<SynthVoiceLayout.maxTouches).contains(slot) else { return }
        sendScore(noteOffScores[slot])
    }

    func allNotesOff() {
        for i in 0..<SynthVoiceLayout.maxTouches { noteOff(slot: i) }
    }

    func setSize(_ size: Int) {
        pendingPatch.size = size
        currentPatchState.size = size
        guard isRunning else { return }
        sendScore(SynthScore.size(size))
        onPatchStateChanged?(currentPatchState)
    }

    func setKey(_ key: Int) {
        pendingPatch.key = key
        currentPatchState.key = key
        guard isRunning else { return }
        sendScore(SynthScore.key(key))
        onPatchStateChanged?(currentPatchState)
    }

    func setOctave(_ oct: Int) {
        pendingPatch.octave = oct
        currentPatchState.octave = oct
        guard isRunning else { return }
        sendScore(SynthScore.octave(oct))
        onPatchStateChanged?(currentPatchState)
    }

    func setSound(_ sound: Int) {
        pendingPatch.sound = sound
        currentPatchState.sound = sound
        guard isRunning else { return }
        sendScore(SynthScore.sound(sound))
        onPatchStateChanged?(currentPatchState)
    }

    func setScale(_ steps: [Int]) {
        if let match = SynthCatalog.scaleOptions.first(where: { $0.steps == steps }) {
            pendingPatch.scaleName = match.name
            currentPatchState.scaleName = match.name
        }
        guard isRunning else { return }
        guard let score = SynthScore.scale(steps) else { return }
        sendScore(score)
        onPatchStateChanged?(currentPatchState)
    }

    // MARK: - AU Parameter Bridge

    /// Apply a single parameter change from the AU parameter tree.
    /// Called when the host automates a parameter or the user changes it in the AU UI.
    func applyParameterChange(_ address: UInt64, value: Float) {
        switch address {
        case 0: // scale
            let index = Int(value)
            guard index < SynthCatalog.scaleOptions.count else { return }
            let option = SynthCatalog.scaleOptions[index]
            setScale(option.steps)
        case 1: // key
            setKey(Int(value))
        case 2: // octave
            let index = Int(value)
            guard index < SynthCatalog.octaveValues.count else { return }
            setOctave(SynthCatalog.octaveValues[index])
        case 3: // size
            setSize(Int(value))
        case 4: // sound
            setSound(Int(value))
        default:
            break
        }
    }

    /// Read a parameter value for the AU parameter tree.
    func parameterValue(for address: UInt64) -> Float {
        switch address {
        case 0: // scale
            let index = SynthCatalog.scaleOptions.firstIndex(where: { $0.name == currentPatchState.scaleName }) ?? 0
            return Float(index)
        case 1: // key
            return Float(currentPatchState.key)
        case 2: // octave
            let index = SynthCatalog.octaveValues.firstIndex(of: currentPatchState.octave) ?? 2
            return Float(index)
        case 3: // size
            return Float(currentPatchState.size)
        case 4: // sound
            return Float(currentPatchState.sound)
        default:
            return 0
        }
    }
}
