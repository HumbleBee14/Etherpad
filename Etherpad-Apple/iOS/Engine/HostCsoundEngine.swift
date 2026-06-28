import Foundation
import AVFoundation
import AudioToolbox

/// Host-driven Csound backend for AUv3. Implements `HostAudioEngine`; standalone app uses `CsoundEngine` instead.
final class HostCsoundEngine: HostAudioEngine {

    enum Error: Swift.Error {
        case csdNotFound
        case createFailed
        case compileFailed(Int32)
        case startFailed(Int32)
    }

    private var cs: OpaquePointer?
    private var isRunning = false
    private var ksmps = 0
    private var nchnls = 0
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
    }

    func applyPatchState(_ patch: SynthPatchState) {
        pendingPatch = patch
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
        guard isRunning else { return }
        sendScore(SynthScore.size(size))
    }

    func setKey(_ key: Int) {
        pendingPatch.key = key
        guard isRunning else { return }
        sendScore(SynthScore.key(key))
    }

    func setOctave(_ oct: Int) {
        pendingPatch.octave = oct
        guard isRunning else { return }
        sendScore(SynthScore.octave(oct))
    }

    func setSound(_ sound: Int) {
        pendingPatch.sound = sound
        guard isRunning else { return }
        sendScore(SynthScore.sound(sound))
    }

    func setScale(_ steps: [Int]) {
        if let match = SynthCatalog.scaleOptions.first(where: { $0.steps == steps }) {
            pendingPatch.scaleName = match.name
        }
        guard isRunning else { return }
        guard let score = SynthScore.scale(steps) else { return }
        sendScore(score)
    }
}
