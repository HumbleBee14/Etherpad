package com.humblebee.etherpad.engine

import android.content.res.Resources
import com.humblebee.etherpad.R
import com.humblebee.etherpad.synth.Presets

// Centralises Csound score-message formatting. UI-thread safe (JNI calls feed Csound's lock-free input ring buffer).
internal class Synth(resources: Resources) {

    init {
        val csdText = resources.openRawResource(R.raw.etherpad)
            .bufferedReader().use { it.readText() }
        check(EtherEngine.nativeLoad(csdText)) { "Csound failed to load the .csd" }
        check(EtherEngine.nativeStart())        { "Oboe stream failed to start" }
    }

    // Only the Oboe stream closes; Csound is intentionally kept alive (see engine.cpp).
    fun stop() = EtherEngine.nativeStop()

    // ── touch events ─────────────────────────────────────────────────────

    /** Start a new note on slot [slot] (0..[Presets.MAX_TOUCHES]-1) at the
     *  given normalised coordinates (0..1). */
    fun touchDown(slot: Int, x: Double, y: Double) {
        EtherEngine.nativeSetControlChannel("touch.$slot.x", x)
        EtherEngine.nativeSetControlChannel("touch.$slot.y", y)
        EtherEngine.nativeInputMessage("i1.$slot 0 -2 $slot")
    }

    /** Update the position of an already-active note on slot [slot]. */
    fun touchMove(slot: Int, x: Double, y: Double) {
        EtherEngine.nativeSetControlChannel("touch.$slot.x", x)
        EtherEngine.nativeSetControlChannel("touch.$slot.y", y)
    }

    /** End the note on slot [slot]. */
    fun touchUp(slot: Int) {
        EtherEngine.nativeInputMessage("i-1.$slot 0 0 $slot")
    }

    // ── parameter setters ────────────────────────────────────────────────

    /** Set number of pitch divisions across the surface (4..14). */
    fun setSize(n: Int) {
        EtherEngine.nativeInputMessage("i100 0 0.5 $n")
    }

    /** Set chromatic key (0=C .. 11=B). */
    fun setKey(idx: Int) {
        EtherEngine.nativeInputMessage("i101 0 0.5 $idx")
    }

    /** Set octave by the engine's value (see [Presets.OctaveValues]). */
    fun setOctave(value: Int) {
        EtherEngine.nativeInputMessage("i102 0 0.5 $value")
    }

    /** Switch sound mode (0=Ether Pad, 1=Distorted Dreams, 2=Xanpalamin). */
    fun setSound(idx: Int) {
        EtherEngine.nativeInputMessage("i104 0 0.5 $idx")
    }

    // A single negative value is a sentinel scale path (-1 BP, -2/-3 Overtone); else 14 ET steps.
    fun setScale(steps: IntArray) {
        val msg = if (steps.size == 1 && steps[0] < 0) {
            "i103 0 0.5 ${steps[0]}"
        } else {
            "i103 0 0.5 " + steps.joinToString(" ")
        }
        EtherEngine.nativeInputMessage(msg)
    }

    // ── recording ─────────────────────────────────────────────────────────

    /** Begin writing engine output to a WAV at [path]. Returns false if already
     *  recording or the file can't be opened. */
    fun startRecording(path: String): Boolean = EtherEngine.nativeStartRecording(path)

    fun stopRecording() = EtherEngine.nativeStopRecording()
}
