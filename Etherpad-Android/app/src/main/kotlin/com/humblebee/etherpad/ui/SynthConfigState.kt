package com.humblebee.etherpad.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.humblebee.etherpad.engine.Synth
import com.humblebee.etherpad.synth.Preset
import com.humblebee.etherpad.synth.Presets

internal class SynthConfigState(
    private val synth: Synth,
    private val touchState: TouchState,
) {
    var scaleIdx  by mutableIntStateOf(Presets.DefaultScaleIdx)
        private set
    var keyIdx    by mutableIntStateOf(Presets.DefaultKeyIdx)
        private set
    var octaveIdx by mutableIntStateOf(Presets.DefaultOctaveIdx)
        private set
    var sizeIdx   by mutableIntStateOf(Presets.DefaultSizeIdx)
        private set
    var soundIdx  by mutableIntStateOf(Presets.DefaultSoundIdx)
        private set

    fun setScale(idx: Int) {
        scaleIdx = idx
        synth.setScale(Presets.ScaleSteps[idx])
    }

    fun setKey(idx: Int) {
        keyIdx = idx
        synth.setKey(idx)
    }

    fun setOctave(idx: Int) {
        octaveIdx = idx
        synth.setOctave(Presets.OctaveValues[idx])
    }

    fun setSize(idx: Int) {
        sizeIdx = idx
        val n = idx + 4
        touchState.numberOfNotes.intValue = n
        synth.setSize(n)
    }

    fun setSound(idx: Int) {
        soundIdx = idx
        synth.setSound(idx)
    }

    fun snapshot(name: String): Preset =
        Preset(name = name, scale = scaleIdx, key = keyIdx,
               octave = octaveIdx, size = sizeIdx, sound = soundIdx)

    fun matches(p: Preset): Boolean =
        p.scale == scaleIdx && p.key == keyIdx && p.octave == octaveIdx &&
        p.size == sizeIdx && p.sound == soundIdx

    fun apply(p: Preset) {
        setScale(p.scale.coerceIn(Presets.ScaleSteps.indices))
        setKey(p.key.coerceIn(Presets.KeyLabels.indices))
        setOctave(p.octave.coerceIn(Presets.OctaveValues.indices))
        setSize(p.size.coerceIn(Presets.SizeLabels.indices))
        setSound(p.sound.coerceIn(Presets.SoundLabels.indices))
    }

    fun resetToDefaults() {
        setScale(Presets.DefaultScaleIdx)
        setKey(Presets.DefaultKeyIdx)
        setOctave(Presets.DefaultOctaveIdx)
        setSize(Presets.DefaultSizeIdx)
        setSound(Presets.DefaultSoundIdx)
    }
}

private fun Int.coerceIn(range: IntRange): Int =
    if (range.isEmpty()) 0 else coerceIn(range.first, range.last)

@Composable
internal fun rememberSynthConfigState(synth: Synth, touchState: TouchState): SynthConfigState =
    remember(synth, touchState) { SynthConfigState(synth, touchState) }
