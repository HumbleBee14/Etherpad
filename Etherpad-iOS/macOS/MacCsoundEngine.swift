import Foundation
import AVFoundation
import CoreAudio

// =============================================================================
//  MACOS AUDIO ENGINE — INTENTIONALLY DIFFERENT FROM iOS. Read before editing.
// -----------------------------------------------------------------------------
//  This is NOT a port of the iOS CsoundEngine/CsoundObj. It is a separate,
//  macOS-only engine, on purpose:
//
//   • iOS (Etherpad/Engine/CsoundEngine.swift + Headers/CsoundObj.m):
//       - Csound 7, FLOAT build (MYFLT = float) -> channel ptrs are Float
//       - Audio output via kAudioUnitSubType_RemoteIO + AVAudioSession (iOS-only)
//       - Score events via CsoundObj.sendScore
//
//   • macOS (this file):
//       - Csound 6.18.1, DOUBLE build (MYFLT = double) -> channel ptrs are Double
//       - Audio output via AVAudioEngine + AVAudioSourceNode (native macOS)
//       - Score events via csoundInputMessage (Csound 6 C API)
//       - spout samples are Double; converted to Float32 for AVAudioEngine
//       - csoundCreate is SINGLE-arg in Csound 6 (two-arg in 7)
//
//  WHY THE DIFFERENCE: macOS ships stable Csound 6.18.1 (CsoundLib64, double);
//  Csound 7 for macOS is beta-only. The two platforms share ONLY etherpad.csd
//  (opcodes 6/7-compatible), so the generated SOUND is identical — only the host
//  plumbing and numeric precision differ.
//
//  IF YOU HIT A PERFORMANCE / QUALITY / PITCH MISMATCH vs iOS, suspects in order:
//   1. Precision: Double channel ptrs here because MYFLT==double. A float macOS
//      build would need Float ptrs + drop the Double->Float conversion below.
//   2. Score API: Csound 6 = csoundInputMessage(); Csound 7 renamed it.
//   3. csoundCreate arity: 6 = csoundCreate(hostData); 7 takes two args.
//   4. ksmps / sample rate: read live from the CSD; never hardcode.
// =============================================================================

final class MacCsoundEngine {

    static let maxTouches = 10

    private var cs: OpaquePointer?            // CSOUND*
    private let avEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var isRunning = false

    private var ksmps = 0
    private var nchnls = 0
    private var sampleRate: Double = 44100

    // DOUBLE because macOS Csound 6.18.1 is CsoundLib64 (MYFLT == double).
    // iOS uses Float here — see the header note above.
    private var xPtrs = [UnsafeMutablePointer<Double>?](repeating: nil, count: maxTouches)
    private var yPtrs = [UnsafeMutablePointer<Double>?](repeating: nil, count: maxTouches)

    // Pre-built scores (no allocation on the touch path).
    private let noteOnScores:  [String]
    private let noteOffScores: [String]

    init() {
        var on = [String](); var off = [String]()
        for i in 0..<Self.maxTouches {
            on.append("i1.\(i) 0 -2 \(i)")
            off.append("i-1.\(i) 0 0 \(i)")
        }
        noteOnScores = on; noteOffScores = off
    }

    // Default output device's nominal sample rate (e.g. 48000 on modern MacBooks).
    // Falls back to 48000 if the query fails. Used to make Csound render at the
    // hardware rate so AVAudioEngine does not resample.
    private static func hardwareOutputSampleRate() -> Double {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return 48000 }

        var rate = Float64(0)
        var rsize = UInt32(MemoryLayout<Float64>.size)
        var raddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &raddr, 0, nil, &rsize, &rate) == noErr,
              rate > 0 else { return 48000 }
        return Double(rate)
    }

    func start() {
        guard !isRunning,
              let path = Bundle.main.path(forResource: "etherpad", ofType: "csd") else {
            print("[Etherpad-mac] etherpad.csd not found in bundle")
            return
        }
        guard let c = csoundCreate(nil) else {     // Csound 6: single arg
            print("[Etherpad-mac] csoundCreate failed")
            return
        }
        cs = c
        // Mirror the proven iOS sequence: compile the CSD as-is (its <CsOptions>
        // has `-o dac`, but like iOS we never let Csound drive the device — the
        // AVAudioSourceNode render block is the ONLY caller of csoundPerformKsmps,
        // pulling samples from spout). We override the real-time audio module to a
        // null/dummy so Csound does not try to open a device itself.
        _ = csoundSetOption(c, "-+rtaudio=null")
        _ = csoundSetOption(c, "-d")               // no display windows

        // Match Csound's render rate to the hardware output rate to avoid AVAudioEngine
        // resampling (a 44100->48000 mismatch produced audible background noise). The
        // CSD declares sr=44100; override it to the device rate so there is NO resample.
        let hwRate = Self.hardwareOutputSampleRate()
        _ = csoundSetOption(c, "--sample-rate=\(Int(hwRate))")

        // csoundCompile wants `const char **`. strdup gives mutable char*, so map
        // to UnsafePointer<CChar>? for the bridged signature.
        let dupd = [strdup("csound"), strdup(path)]
        defer { dupd.forEach { free($0) } }
        var argv: [UnsafePointer<CChar>?] = dupd.map { UnsafePointer($0) }
        let compileResult = argv.withUnsafeMutableBufferPointer { buf -> Int32 in
            csoundCompile(c, Int32(buf.count), buf.baseAddress)
        }
        guard compileResult == 0 else {
            print("[Etherpad-mac] csoundCompile failed (\(compileResult))")
            csoundDestroy(c); cs = nil; return
        }
        // csoundCompile() already starts Csound in 6.x when given a full CSD; calling
        // csoundStart again logs "already started". Bind + render directly; the render
        // block drives performKsmps. (No explicit csoundStart here.)

        ksmps = Int(csoundGetKsmps(c))
        nchnls = Int(csoundGetNchnls(c))
        sampleRate = Double(csoundGetSr(c))
        bindChannels(c)
        setupAudio(c)
        isRunning = true
        print("[Etherpad-mac] started: sr=\(sampleRate) ksmps=\(ksmps) nchnls=\(nchnls)")
    }

    private func bindChannels(_ c: OpaquePointer) {
        // Header: csoundGetChannelPtr(CSOUND*, MYFLT **p, name, type) → bridged as
        // UnsafeMutablePointer<UnsafeMutablePointer<Double>?>?, so pass &xPtrs[i].
        let type = Int32(CSOUND_CONTROL_CHANNEL.rawValue) | Int32(CSOUND_INPUT_CHANNEL.rawValue)
        for i in 0..<Self.maxTouches {
            _ = csoundGetChannelPtr(c, &xPtrs[i], "touch.\(i).x", type)
            _ = csoundGetChannelPtr(c, &yPtrs[i], "touch.\(i).y", type)
        }
        let bound = xPtrs.compactMap { $0 }.count
        print("[Etherpad-mac] channels bound: \(bound)/\(Self.maxTouches)")
    }

    // AVAudioSourceNode pulls ksmps blocks from Csound's spout.
    private func setupAudio(_ c: OpaquePointer) {
        let channels = AVAudioChannelCount(max(nchnls, 1))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: channels) else {
            print("[Etherpad-mac] could not make AVAudioFormat"); return
        }
        let ks = ksmps
        let nch = nchnls

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self, let cs = self.cs else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            var framesFilled = 0
            let total = Int(frameCount)
            while framesFilled < total {
                if csoundPerformKsmps(cs) != 0 {       // finished/error → silence
                    for buf in abl { memset(buf.mData, 0, Int(buf.mDataByteSize)) }
                    return noErr
                }
                guard let spout = csoundGetSpout(cs) else { break }  // MYFLT* (Double)
                let n = min(ks, total - framesFilled)
                // spout interleaved [f0_ch0, f0_ch1, ...]; AVAudioEngine wants
                // Float32 per non-interleaved channel buffer → convert Double->Float.
                for ch in 0..<nch where ch < abl.count {
                    let out = abl[ch].mData!.assumingMemoryBound(to: Float.self)
                    for f in 0..<n {
                        out[framesFilled + f] = Float(spout[f * nch + ch])
                    }
                }
                framesFilled += n
            }
            return noErr
        }
        sourceNode = node
        avEngine.attach(node)
        avEngine.connect(node, to: avEngine.mainMixerNode, format: format)
        do { try avEngine.start() }
        catch { print("[Etherpad-mac] AVAudioEngine start failed: \(error)") }
    }

    func stop() {
        guard isRunning else { return }
        avEngine.stop()
        if let n = sourceNode { avEngine.detach(n) }
        sourceNode = nil
        if let c = cs { csoundDestroy(c) }
        cs = nil
        for i in 0..<Self.maxTouches { xPtrs[i] = nil; yPtrs[i] = nil }
        isRunning = false
    }

    private func writeChannel(slot: Int, x: Float, y: Float) {
        xPtrs[slot]?.pointee = Double(x)     // engine API is Float; channel is Double
        yPtrs[slot]?.pointee = Double(y)
    }

    // Score events use csoundInputMessage (Csound 6 C API). iOS/Csound 7 = csoundEventString.
    private func sendScore(_ s: String) { csoundInputMessage(cs, s) }

    func noteOn(slot: Int, x: Float, y: Float) {
        guard isRunning, (0..<Self.maxTouches).contains(slot) else { return }
        writeChannel(slot: slot, x: x, y: y)
        sendScore(noteOnScores[slot])
    }
    func updatePosition(slot: Int, x: Float, y: Float) {
        guard isRunning, (0..<Self.maxTouches).contains(slot) else { return }
        writeChannel(slot: slot, x: x, y: y)
    }
    func noteOff(slot: Int) {
        guard isRunning, (0..<Self.maxTouches).contains(slot) else { return }
        sendScore(noteOffScores[slot])
    }
    func allNotesOff() { for i in 0..<Self.maxTouches { noteOff(slot: i) } }

    func setSize(_ size: Int)   { sendScore("i100 0 0.5 \(size)") }
    func setKey(_ key: Int)     { sendScore("i101 0 0.5 \(key)") }
    func setOctave(_ oct: Int)  { sendScore("i102 0 0.5 \(oct)") }
    func setSound(_ sound: Int) { sendScore("i104 0 0.5 \(sound)") }
    func setScale(_ steps: [Int]) {
        if steps.count == 1 && steps[0] < 0 {
            sendScore("i103 0 0.5 \(steps[0])")
        } else if steps.count >= 14 {
            let args = steps.prefix(14).map(String.init).joined(separator: " ")
            sendScore("i103 0 0.5 \(args)")
        }
    }
}
