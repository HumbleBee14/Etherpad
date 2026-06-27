import Foundation
import AVFoundation
import CoreAudio

// macOS engine: Csound 6.18.1 (CsoundLib64, double) via AVAudioEngine. Separate
// from iOS (Csound 7 float, RemoteIO). Shared only through etherpad.csd.
final class MacCsoundEngine {

    static let maxTouches = 10
    private static let fallbackSampleRate: Double = 48000

    private enum Instr {
        static let size   = 100
        static let key    = 101
        static let octave = 102
        static let scale  = 103
        static let sound  = 104
    }
    private static let ctrlDur = "0.5"

    private var cs: OpaquePointer?
    private let avEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var isRunning = false

    private var ksmps = 0
    private var nchnls = 0
    private var sampleRate: Double = 44100

    // Double, not Float: MYFLT == double in CsoundLib64.
    private var xPtrs = [UnsafeMutablePointer<Double>?](repeating: nil, count: maxTouches)
    private var yPtrs = [UnsafeMutablePointer<Double>?](repeating: nil, count: maxTouches)

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

    /// Bundled Csound looks for Opcodes64 under the embedded framework, not /Library/Frameworks.
    private static func configureBundledOpcodesDir() {
        let dir = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/CsoundLib64.framework/Versions/Current/Resources/Opcodes64", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        csoundSetOpcodedir(dir.path)
    }

    private static func hardwareOutputSampleRate() -> Double {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return fallbackSampleRate }

        var rate = Float64(0)
        var rsize = UInt32(MemoryLayout<Float64>.size)
        var raddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &raddr, 0, nil, &rsize, &rate) == noErr,
              rate > 0 else { return fallbackSampleRate }
        return Double(rate)
    }

    func start() {
        guard !isRunning,
              let path = Bundle.main.path(forResource: "etherpad", ofType: "csd") else {
            print("[Etherpad-mac] etherpad.csd not found in bundle")
            return
        }
        Self.configureBundledOpcodesDir()
        guard let c = csoundCreate(nil) else {
            print("[Etherpad-mac] csoundCreate failed")
            return
        }
        cs = c
        _ = csoundSetOption(c, "-+rtaudio=null")   // host pulls samples; Csound opens no device
        _ = csoundSetOption(c, "-d")

        // Render at the hardware rate so AVAudioEngine never resamples (resampling added noise).
        _ = csoundSetOption(c, "--sample-rate=\(Int(Self.hardwareOutputSampleRate()))")

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

        ksmps = Int(csoundGetKsmps(c))
        nchnls = Int(csoundGetNchnls(c))
        sampleRate = Double(csoundGetSr(c))
        bindChannels(c)
        setupAudio(c)
        isRunning = true
    }

    private func bindChannels(_ c: OpaquePointer) {
        let type = Int32(CSOUND_CONTROL_CHANNEL.rawValue) | Int32(CSOUND_INPUT_CHANNEL.rawValue)
        for i in 0..<Self.maxTouches {
            _ = csoundGetChannelPtr(c, &xPtrs[i], "touch.\(i).x", type)
            _ = csoundGetChannelPtr(c, &yPtrs[i], "touch.\(i).y", type)
        }
    }

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
                if csoundPerformKsmps(cs) != 0 {
                    for buf in abl { memset(buf.mData, 0, Int(buf.mDataByteSize)) }
                    return noErr
                }
                guard let spout = csoundGetSpout(cs) else { break }
                let n = min(ks, total - framesFilled)
                // spout is interleaved double; AVAudioEngine wants non-interleaved Float32.
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
        xPtrs[slot]?.pointee = Double(x)
        yPtrs[slot]?.pointee = Double(y)
    }

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

    private func ctrl(_ instr: Int, _ args: String) {
        sendScore("i\(instr) 0 \(Self.ctrlDur) \(args)")
    }
    func setSize(_ size: Int)   { ctrl(Instr.size, "\(size)") }
    func setKey(_ key: Int)     { ctrl(Instr.key, "\(key)") }
    func setOctave(_ oct: Int)  { ctrl(Instr.octave, "\(oct)") }
    func setSound(_ sound: Int) { ctrl(Instr.sound, "\(sound)") }
    func setScale(_ steps: [Int]) {
        if steps.count == 1 && steps[0] < 0 {
            ctrl(Instr.scale, "\(steps[0])")
        } else if steps.count >= 14 {
            let args = steps.prefix(14).map(String.init).joined(separator: " ")
            ctrl(Instr.scale, args)
        }
    }
}
