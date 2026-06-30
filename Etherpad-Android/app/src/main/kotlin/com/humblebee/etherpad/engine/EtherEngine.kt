package com.humblebee.etherpad.engine

// Lifecycle: load(csdText) → start() → setControlChannel/inputMessage → stop() (closes Oboe; Csound is NOT destroyed, see engine.cpp).
// setControlChannel and inputMessage are thread-safe (Csound's channel/event ring buffers). Audio thread is Oboe-owned and never re-enters Kotlin.
object EtherEngine {
    init { System.loadLibrary("ether_engine") }

    external fun nativeLoad(csdText: String): Boolean
    external fun nativeStart(): Boolean
    external fun nativeStop()
    external fun nativeSetControlChannel(name: String, value: Double)
    external fun nativeInputMessage(score: String)
    external fun nativeGetControlChannel(name: String): Double
    external fun nativeStartRecording(path: String): Boolean
    external fun nativeStopRecording()
}
