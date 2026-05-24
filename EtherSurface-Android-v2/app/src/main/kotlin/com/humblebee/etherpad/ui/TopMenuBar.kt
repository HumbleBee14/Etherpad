package com.humblebee.etherpad.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.humblebee.etherpad.engine.Synth
import com.humblebee.etherpad.synth.Presets

/**
 * Top action bar with five parameter buttons. Each button opens a single-
 * choice [ChoiceDialog] populated from [Presets]; the current selection is
 * shown by the dialog's radio button (mirrors the iOS UIMenu checkmark).
 *
 * Selection state lives entirely in this composable's local `remember`
 * blocks — no need for a ViewModel because the engine itself is the
 * source of truth for everything except the UI's current pick.
 */
@Composable
internal fun TopMenuBar(synth: Synth, touchState: TouchState) {
    // Defaults mirror the .csd's instr 100/101/102/103/104 init values.
    var sizeIdx   by remember { mutableIntStateOf(Presets.DefaultSizeIdx) }
    var keyIdx    by remember { mutableIntStateOf(Presets.DefaultKeyIdx) }
    var octaveIdx by remember { mutableIntStateOf(Presets.DefaultOctaveIdx) }
    var soundIdx  by remember { mutableIntStateOf(Presets.DefaultSoundIdx) }
    var scaleIdx  by remember { mutableIntStateOf(Presets.DefaultScaleIdx) }

    var openMenu by remember { mutableStateOf<String?>(null) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(40.dp)
            .background(EtherColors.TopBar)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        MenuButton("Octave") { openMenu = "octave" }
        Spacer(Modifier.padding(start = 20.dp))
        MenuButton("Scale")  { openMenu = "scale" }
        Spacer(Modifier.padding(start = 20.dp))
        MenuButton("Key")    { openMenu = "key" }
        Spacer(Modifier.padding(start = 20.dp))
        MenuButton("Size")   { openMenu = "size" }
        Spacer(Modifier.padding(start = 20.dp))
        MenuButton("Sound")  { openMenu = "sound" }
    }

    when (openMenu) {
        "octave" -> ChoiceDialog("Octave", Presets.OctaveLabels, octaveIdx,
            onDismiss = { openMenu = null }) { idx ->
            octaveIdx = idx
            synth.setOctave(Presets.OctaveValues[idx])
            openMenu = null
        }
        "scale" -> ChoiceDialog("Scale", Presets.ScaleLabels, scaleIdx,
            onDismiss = { openMenu = null }) { idx ->
            scaleIdx = idx
            synth.setScale(Presets.ScaleSteps[idx])
            openMenu = null
        }
        "key" -> ChoiceDialog("Key", Presets.KeyLabels, keyIdx,
            onDismiss = { openMenu = null }) { idx ->
            keyIdx = idx
            synth.setKey(idx)
            openMenu = null
        }
        "size" -> ChoiceDialog("Size", Presets.SizeLabels, sizeIdx,
            onDismiss = { openMenu = null }) { idx ->
            sizeIdx = idx
            val n = idx + 4
            touchState.numberOfNotes.intValue = n
            synth.setSize(n)
            openMenu = null
        }
        "sound" -> ChoiceDialog("Sound", Presets.SoundLabels, soundIdx,
            onDismiss = { openMenu = null }) { idx ->
            soundIdx = idx
            synth.setSound(idx)
            openMenu = null
        }
    }
}

/** Single top-bar entry. Plain text button on the dark grey background; the
 *  click opens its matching dialog. */
@Composable
private fun MenuButton(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(Color.Transparent),
        contentAlignment = Alignment.Center,
    ) {
        TextButton(onClick = onClick) {
            Text(
                text = label,
                color = EtherColors.TopBarText,
                style = MaterialTheme.typography.titleMedium,
            )
        }
    }
}
