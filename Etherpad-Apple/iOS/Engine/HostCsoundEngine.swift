import Foundation
import AVFoundation
import AudioToolbox
import os

/// Host-driven Csound backend for AUv3. Implements `HostAudioEngine`; standalone app uses `CsoundEngine` instead.
///
/// Thread safety:
/// - `cs` lifetime is guarded by `audioLock` during render vs stop.
/// - Patch state lives in `RealtimePatchState` (safe reads from parameter + MIDI threads).
/// - Csound `csoundEventString` is internally thread-safe (Csound 6+); float channel writes are atomic on ARM64.
final class HostCsoundEngine: HostAudioEngine {

    enum Error: Swift.Error {
        case csdNotFound
        case createFailed
        case compileFailed(Int32)
        case startFailed(Int32)
    }

    /// Called when patch parameters change. May fire off the main thread — observers must dispatch UI work.
    var onPatchStateChanged: ((SynthPatchState) -> Void)?

    private struct AudioCore {
        /// Csound instance stored as bit pattern — `UInt` is Sendable across `withLock` closures.
        var csBits: UInt = 0
        var isRunning = false
        var ksmps = 0
        var nchnls = 0
        var sampleRate: Double = 44100
    }

    private static func csoundPtr(from bits: UInt) -> OpaquePointer? {
        bits == 0 ? nil : OpaquePointer(bitPattern: bits)
    }

    private let audioLock = OSAllocatedUnfairLock(initialState: AudioCore())
    private let patchBox = RealtimePatchState()

    /// Retained until Csound starts so pre-render menu changes are not lost.
    private var pendingPatch = SynthPatchState.factoryDefault

    private var xPtrs = [UnsafeMutablePointer<Float>?](
        repeating: nil, count: SynthVoiceLayout.maxTouches)
    private var yPtrs = [UnsafeMutablePointer<Float>?](
        repeating: nil, count: SynthVoiceLayout.maxTouches)

    private let noteOnScores:  [String]
    private let noteOffScores: [String]

    var isRunning: Bool { audioLock.withLock { $0.isRunning } }

    var currentPatchState: SynthPatchState { patchBox.snapshot() }

    /// Csound k-period latency at the host's sample rate.
    var reportedLatency: TimeInterval {
        audioLock.withLock { core in
            guard core.isRunning, core.sampleRate > 0 else { return 0 }
            return TimeInterval(core.ksmps) / core.sampleRate
        }
    }

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
            csoundDestroy(c)
            throw Error.compileFailed(compileResult)
        }

        let startResult = csoundStart(c)
        guard startResult == 0 else {
            csoundDestroy(c)
            throw Error.startFailed(startResult)
        }

        let ksmps = Int(csoundGetKsmps(c))
        let nchnls = Int(csoundGetChannels(c, 0))
        bindChannels(c)

        let csBits = UInt(bitPattern: c)
        audioLock.withLock { core in
            core.csBits = csBits
            core.ksmps = ksmps
            core.nchnls = nchnls
            core.sampleRate = sampleRate
            core.isRunning = true
        }

        pendingPatch.apply(to: self)
        patchBox.value = pendingPatch
    }

    func applyPatchState(_ patch: SynthPatchState) {
        pendingPatch = patch
        patchBox.value = patch
        if isRunning { patch.apply(to: self) }
    }

    func stopHost() {
        let csBits = audioLock.withLock { core -> UInt in
            guard core.isRunning else { return 0 }
            core.isRunning = false
            let bits = core.csBits
            core.csBits = 0
            return bits
        }
        if let c = Self.csoundPtr(from: csBits) { csoundDestroy(c) }
        for i in 0..<SynthVoiceLayout.maxTouches { xPtrs[i] = nil; yPtrs[i] = nil }
    }

    func render(into bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) -> OSStatus {
        let snapshot = audioLock.withLock { core -> (UInt, Int, Int)? in
            guard core.isRunning, core.csBits != 0 else { return nil }
            return (core.csBits, core.ksmps, core.nchnls)
        }
        guard let (csBits, ks, nch) = snapshot, let cs = Self.csoundPtr(from: csBits) else { return noErr }

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        var framesFilled = 0
        let total = Int(frameCount)

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
        let csBits = audioLock.withLock { core -> UInt in
            guard core.isRunning, core.csBits != 0 else { return 0 }
            return core.csBits
        }
        guard let cs = Self.csoundPtr(from: csBits) else { return }
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
        patchBox.mutate { $0.size = size }
        pendingPatch.size = size
        guard isRunning else { return }
        sendScore(SynthScore.size(size))
        notifyPatchChanged()
    }

    func setKey(_ key: Int) {
        patchBox.mutate { $0.key = key }
        pendingPatch.key = key
        guard isRunning else { return }
        sendScore(SynthScore.key(key))
        notifyPatchChanged()
    }

    func setOctave(_ oct: Int) {
        patchBox.mutate { $0.octave = oct }
        pendingPatch.octave = oct
        guard isRunning else { return }
        sendScore(SynthScore.octave(oct))
        notifyPatchChanged()
    }

    func setSound(_ sound: Int) {
        patchBox.mutate { $0.sound = sound }
        pendingPatch.sound = sound
        guard isRunning else { return }
        sendScore(SynthScore.sound(sound))
        notifyPatchChanged()
    }

    func setScale(_ steps: [Int]) {
        if let match = SynthCatalog.scaleOptions.first(where: { $0.steps == steps }) {
            patchBox.mutate { $0.scaleName = match.name }
            pendingPatch.scaleName = match.name
        }
        guard isRunning else { return }
        guard let score = SynthScore.scale(steps) else { return }
        sendScore(score)
        notifyPatchChanged()
    }

    private func notifyPatchChanged() {
        onPatchStateChanged?(patchBox.snapshot())
    }

    // MARK: - AU Parameter Bridge

    func applyParameterChange(_ address: UInt64, value: Float) {
        switch address {
        case 0: // scale
            let index = Int(value)
            guard index < SynthCatalog.scaleOptions.count else { return }
            setScale(SynthCatalog.scaleOptions[index].steps)
        case 1: // key
            setKey(Int(value))
        case 2: // sound
            setSound(Int(value))
        case 3: // octave
            let index = Int(value)
            guard index < SynthCatalog.octaveValues.count else { return }
            setOctave(SynthCatalog.octaveValues[index])
        case 4: // size
            setSize(SynthCatalog.sizeValue(forIndex: Int(value)))
        default:
            break
        }
    }

    func parameterValue(for address: UInt64) -> Float {
        let patch = patchBox.snapshot()
        switch address {
        case 0: // scale
            let index = SynthCatalog.scaleOptions.firstIndex(where: { $0.name == patch.scaleName }) ?? 0
            return Float(index)
        case 1: // key
            return Float(patch.key)
        case 2: // sound
            return Float(patch.sound)
        case 3: // octave
            let index = SynthCatalog.octaveValues.firstIndex(of: patch.octave) ?? 2
            return Float(index)
        case 4: // size
            return Float(SynthCatalog.sizeIndex(for: patch.size))
        default:
            return 0
        }
    }
}
