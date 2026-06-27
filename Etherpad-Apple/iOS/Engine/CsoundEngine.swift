import Foundation

final class CsoundEngine {

    static let maxTouches = 10

    private(set) var csound: CsoundObj?
    private var isRunning = false
    private var listenerBridge: CsoundListenerBridge?

    // Bound after csoundObjStarted: fires.
    private var xChannelPtrs: [UnsafeMutablePointer<Float>?] = Array(repeating: nil, count: maxTouches)
    private var yChannelPtrs: [UnsafeMutablePointer<Float>?] = Array(repeating: nil, count: maxTouches)

    // Pre-built so the touch loop never allocates.
    private let noteOnScores:  [String]
    private let noteOffScores: [String]
    fileprivate let xChannelNames: [String]
    fileprivate let yChannelNames: [String]

    init() {
        var onScores  = [String]()
        var offScores = [String]()
        var xNames    = [String]()
        var yNames    = [String]()
        for i in 0..<Self.maxTouches {
            xNames.append("touch.\(i).x")
            yNames.append("touch.\(i).y")
            onScores.append("i1.\(i) 0 -2 \(i)")
            offScores.append("i-1.\(i) 0 0 \(i)")
        }
        self.xChannelNames = xNames
        self.yChannelNames = yNames
        self.noteOnScores  = onScores
        self.noteOffScores = offScores
    }

    func start() {
        guard !isRunning else { return }

        guard let csdPath = Bundle.main.path(forResource: "etherpad", ofType: "csd") else {
            print("[Etherpad] etherpad.csd not found in bundle")
            return
        }

        let cs = CsoundObj()
        csound = cs

        // Register listener BEFORE play(): csoundObjStarted: is the only safe moment to call
        // getInputChannelPtr — calling earlier crashes (csoundGetChannelPtr derefs uninitialised CSOUND*).
        let bridge = CsoundListenerBridge(engine: self)
        listenerBridge = bridge
        cs.add(bridge)

        cs.play(csdPath)
        isRunning = true
    }

    // Called on the Csound performance thread once channel pointers are valid.
    fileprivate func bindChannelPointers() {
        guard let cs = csound else { return }
        let kType = controlChannelType(CSOUND_CONTROL_CHANNEL.rawValue)
        var xPtrs = Array<UnsafeMutablePointer<Float>?>(repeating: nil, count: Self.maxTouches)
        var yPtrs = Array<UnsafeMutablePointer<Float>?>(repeating: nil, count: Self.maxTouches)
        for i in 0..<Self.maxTouches {
            xPtrs[i] = cs.getInputChannelPtr(xChannelNames[i], channelType: kType)
            yPtrs[i] = cs.getInputChannelPtr(yChannelNames[i], channelType: kType)
        }
        DispatchQueue.main.async {
            self.xChannelPtrs = xPtrs
            self.yChannelPtrs = yPtrs
            let bound = xPtrs.compactMap { $0 }.count
            print("[Etherpad] Csound channels bound: \(bound)/\(Self.maxTouches)")
        }
    }

    func stop() {
        guard isRunning else { return }
        csound?.stop()
        csound = nil
        listenerBridge = nil
        isRunning = false

        for i in 0..<Self.maxTouches {
            xChannelPtrs[i] = nil
            yChannelPtrs[i] = nil
        }
    }

    func noteOn(slot: Int, x: Float, y: Float) {
        guard isRunning, slot >= 0, slot < Self.maxTouches else { return }
        writeChannel(slot: slot, x: x, y: y)
        csound?.sendScore(noteOnScores[slot])
    }

    func updatePosition(slot: Int, x: Float, y: Float) {
        guard isRunning, slot >= 0, slot < Self.maxTouches else { return }
        writeChannel(slot: slot, x: x, y: y)
    }

    // Silently drops if the engine hasn't finished starting (ready in <100 ms, well before first touch).
    private func writeChannel(slot: Int, x: Float, y: Float) {
        guard let xp = xChannelPtrs[slot], let yp = yChannelPtrs[slot] else { return }
        xp.pointee = x
        yp.pointee = y
    }

    func noteOff(slot: Int) {
        guard isRunning, slot >= 0, slot < Self.maxTouches else { return }
        csound?.sendScore(noteOffScores[slot])
    }

    func allNotesOff() {
        for i in 0..<Self.maxTouches {
            noteOff(slot: i)
        }
    }

    // Mirror instr 100–104 in the CSD.

    func setSize(_ size: Int) {
        csound?.sendScore("i100 0 0.5 \(size)")
    }

    func setKey(_ key: Int) {
        csound?.sendScore("i101 0 0.5 \(key)")
    }

    func setOctave(_ octave: Int) {
        csound?.sendScore("i102 0 0.5 \(octave)")
    }

    func setSound(_ sound: Int) {
        csound?.sendScore("i104 0 0.5 \(sound)")
    }

    // [-1]=Bohlen-Pierce, [-2]=Overtone Low, [-3]=Overtone High, otherwise 14-element ET scale.
    func setScale(_ steps: [Int]) {
        if steps.count == 1 && steps[0] < 0 {
            csound?.sendScore("i103 0 0.5 \(steps[0])")
        } else if steps.count >= 14 {
            let args = steps.prefix(14).map { String($0) }.joined(separator: " ")
            csound?.sendScore("i103 0 0.5 \(args)")
        }
    }
}

// CsoundObjListener is Obj-C, so the listener must inherit from NSObject.
private final class CsoundListenerBridge: NSObject, CsoundObjListener {
    weak var engine: CsoundEngine?
    init(engine: CsoundEngine) { self.engine = engine }

    func csoundObjStarted(_ csoundObj: CsoundObj!) {
        engine?.bindChannelPointers()
    }

    func csoundObjCompleted(_ csoundObj: CsoundObj!) { }
}
