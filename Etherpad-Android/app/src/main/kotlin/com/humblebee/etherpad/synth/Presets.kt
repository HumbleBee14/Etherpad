package com.humblebee.etherpad.synth

internal object Presets {

    // Matches the .csd's touch.<0..9>.x|y channel definitions.
    const val MAX_TOUCHES = 10

    // Engine value = index + 4 (range 4..14).
    val SizeLabels = arrayOf("4","5","6","7","8","9","10","11","12","13","14")
    const val DefaultSizeIdx = 4

    val KeyLabels = arrayOf("C","C#","D","D#","E","F","F#","G","G#","A","A#","B")
    const val DefaultKeyIdx = 0

    val OctaveLabels = arrayOf("2","1","0","-1","-2")
    // Engine octave values matching the labels in the same order.
    val OctaveValues = intArrayOf(6, 5, 4, 3, 2)
    const val DefaultOctaveIdx = 2

    val SoundLabels = arrayOf(
        "Ether Pad", "Distorted Dreams", "Xanpalamin", "Give It a Tri", "Digital Monk",
    )
    const val DefaultSoundIdx = 0

    // Order matches ScaleSteps row order.
    val ScaleLabels = arrayOf(
        "Default", "Major", "Minor", "Pentatonic", "Flamenco",
        "Blues", "Chromatic", "Whole-Tone", "Octatonic", "Bohlen-Pierce",
        "Overtone Series Low", "Overtone Series High",
    )
    const val DefaultScaleIdx = 0

    // Single negative value = sentinel selecting an instr 1 code path: -1 Bohlen-Pierce,
    // -2 Overtone Low, -3 Overtone High. Other rows are 14 ET semitone steps.
    val ScaleSteps = arrayOf(
        intArrayOf( 0, 2, 4, 7, 9,11,12,14,16,19,21,24,26,28),  // Default
        intArrayOf( 0, 2, 4, 5, 7, 9,11,12,14,16,17,19,21,23),  // Major
        intArrayOf( 0, 2, 3, 5, 7, 8,11,12,14,15,17,19,20,23),  // Minor
        intArrayOf( 0, 2, 4, 7, 9,12,14,16,19,21,24,26,28,30),  // Pentatonic
        intArrayOf( 0, 1, 4, 5, 7, 8,11,12,13,16,17,19,21,22),  // Flamenco
        intArrayOf( 0, 3, 5, 6, 7,10,12,15,17,18,19,22,24,27),  // Blues
        intArrayOf( 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13),  // Chromatic
        intArrayOf( 0, 2, 4, 6, 8,10,12,14,16,18,20,22,24,26),  // Whole-Tone
        intArrayOf( 0, 1, 3, 4, 6, 7, 9,10,12,13,15,16,18,19),  // Octatonic
        intArrayOf(-1),  // Bohlen-Pierce
        intArrayOf(-2),  // Overtone Series Low
        intArrayOf(-3),  // Overtone Series High
    )
}
