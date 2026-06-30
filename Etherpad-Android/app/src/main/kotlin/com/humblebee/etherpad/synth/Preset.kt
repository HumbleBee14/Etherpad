package com.humblebee.etherpad.synth

import java.util.UUID

internal data class Preset(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val scale: Int,
    val key: Int,
    val octave: Int,
    val size: Int,
    val sound: Int,
) {
    val summary: String
        get() = "${label(Presets.ScaleLabels, scale)} · ${label(Presets.KeyLabels, key)} · " +
                "${label(Presets.OctaveLabels, octave)} · ${label(Presets.SoundLabels, sound)}"

    companion object {
        fun suggestedName(scale: Int, key: Int, octave: Int, sound: Int, maxLength: Int): String {
            val s = label(Presets.ScaleLabels, scale).take(3)
            val k = label(Presets.KeyLabels, key).take(2)
            val o = label(Presets.OctaveLabels, octave).take(2)
            val n = label(Presets.SoundLabels, sound).take(3)
            return "$s-$k-$o-$n".take(maxLength)
        }
    }
}

private fun label(options: Array<String>, idx: Int): String = options.getOrElse(idx) { "?" }
