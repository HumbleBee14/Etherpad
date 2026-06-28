import Foundation

/// Standalone iOS backend — CsoundObj + RemoteIO. AU hosts use `HostCsoundEngine` instead.
final class CsoundEngine: SynthEngineProtocol {

    private(set) var csound: CsoundObj?
    private var isRunning = false
    private var listenerBridge: CsoundListenerBridge?

    private var xChannelPtrs: [UnsafeMutablePointer<Float>?] = Array(
        repeating: nil, count: SynthVoiceLayout.maxTouches)
    private var yChannelPtrs: [UnsafeMutablePointer<Float>?] = Array(
        repeating: nil, count: SynthVoiceLayout.maxTouches)

    private let noteOnScores:  [String]
    private let noteOffScores: [String]
    private let xChannelNames: [String]
    private let yChannelNames: [String]

    init() {
        let names = SynthScore.touchChannelNames()
        xChannelNames = names.x
        yChannelNames = names.y
        var onScores  = [String]()
        var offScores = [String]()
        for i in 0..<SynthVoiceLayout.maxTouches {
            onScores.append(SynthScore.noteOn(slot: i))
            offScores.append(SynthScore.noteOff(slot: i))
        }
        noteOnScores  = onScores
        noteOffScores = offScores
    }

    func start() {
        guard !isRunning else { return }

        guard let csdPath = SynthResourceLocator.mainApp().csdURL?.path else {
            print("[Etherpad] \(SynthAsset.csdName).\(SynthAsset.csdExtension) not found in bundle")
            return
        }

        let cs = CsoundObj()
        csound = cs

        let bridge = CsoundListenerBridge(engine: self)
        listenerBridge = bridge
        cs.add(bridge)

        cs.play(csdPath)
        isRunning = true
    }

    fileprivate func bindChannelPointers() {
        guard let cs = csound else { return }
        let kType = controlChannelType(CSOUND_CONTROL_CHANNEL.rawValue)
        var xPtrs = Array<UnsafeMutablePointer<Float>?>(repeating: nil, count: SynthVoiceLayout.maxTouches)
        var yPtrs = Array<UnsafeMutablePointer<Float>?>(repeating: nil, count: SynthVoiceLayout.maxTouches)
        for i in 0..<SynthVoiceLayout.maxTouches {
            xPtrs[i] = cs.getInputChannelPtr(xChannelNames[i], channelType: kType)
            yPtrs[i] = cs.getInputChannelPtr(yChannelNames[i], channelType: kType)
        }
        DispatchQueue.main.async {
            self.xChannelPtrs = xPtrs
            self.yChannelPtrs = yPtrs
            let bound = xPtrs.compactMap { $0 }.count
            print("[Etherpad] Csound channels bound: \(bound)/\(SynthVoiceLayout.maxTouches)")
        }
    }

    func stop() {
        guard isRunning else { return }
        csound?.stop()
        csound = nil
        listenerBridge = nil
        isRunning = false

        for i in 0..<SynthVoiceLayout.maxTouches {
            xChannelPtrs[i] = nil
            yChannelPtrs[i] = nil
        }
    }

    func noteOn(slot: Int, x: Float, y: Float) {
        guard isRunning, slot >= 0, slot < SynthVoiceLayout.maxTouches else { return }
        writeChannel(slot: slot, x: x, y: y)
        csound?.sendScore(noteOnScores[slot])
    }

    func updatePosition(slot: Int, x: Float, y: Float) {
        guard isRunning, slot >= 0, slot < SynthVoiceLayout.maxTouches else { return }
        writeChannel(slot: slot, x: x, y: y)
    }

    private func writeChannel(slot: Int, x: Float, y: Float) {
        guard let xp = xChannelPtrs[slot], let yp = yChannelPtrs[slot] else { return }
        xp.pointee = x
        yp.pointee = y
    }

    func noteOff(slot: Int) {
        guard isRunning, slot >= 0, slot < SynthVoiceLayout.maxTouches else { return }
        csound?.sendScore(noteOffScores[slot])
    }

    func allNotesOff() {
        for i in 0..<SynthVoiceLayout.maxTouches {
            noteOff(slot: i)
        }
    }

    func setSize(_ size: Int) {
        csound?.sendScore(SynthScore.size(size))
    }

    func setKey(_ key: Int) {
        csound?.sendScore(SynthScore.key(key))
    }

    func setOctave(_ octave: Int) {
        csound?.sendScore(SynthScore.octave(octave))
    }

    func setSound(_ sound: Int) {
        csound?.sendScore(SynthScore.sound(sound))
    }

    func setScale(_ steps: [Int]) {
        guard let score = SynthScore.scale(steps) else { return }
        csound?.sendScore(score)
    }
}

private final class CsoundListenerBridge: NSObject, CsoundObjListener {
    weak var engine: CsoundEngine?
    init(engine: CsoundEngine) { self.engine = engine }

    func csoundObjStarted(_ csoundObj: CsoundObj!) {
        engine?.bindChannelPointers()
    }

    func csoundObjCompleted(_ csoundObj: CsoundObj!) { }
}
