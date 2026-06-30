package com.humblebee.etherpad.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.RadioButtonChecked
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.humblebee.etherpad.synth.Presets

// Each button is wrapped in its own Box so its ChoiceDropdown anchors directly beneath it.
@Composable
internal fun TopMenuBar(
    config: SynthConfigState,
    theme: EtherTheme,
    recordVisible: Boolean,
    isRecording: Boolean,
    onRecordToggle: () -> Unit,
    onAboutClick: () -> Unit,
) {
    var openMenu by remember { mutableStateOf<String?>(null) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(40.dp)
            .background(theme.topBar.copy(alpha = 0.55f))
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DropdownButton(
            label = "Octave",
            expanded = openMenu == "octave",
            options = Presets.OctaveLabels,
            selected = config.octaveIdx,
            defaultIdx = Presets.DefaultOctaveIdx,
            theme = theme,
            onOpen = { openMenu = "octave" },
            onDismiss = { openMenu = null },
            onPick = { config.setOctave(it); openMenu = null },
        )
        Spacer(Modifier.padding(start = 20.dp))
        DropdownButton(
            label = "Scale",
            expanded = openMenu == "scale",
            options = Presets.ScaleLabels,
            selected = config.scaleIdx,
            defaultIdx = Presets.DefaultScaleIdx,
            theme = theme,
            onOpen = { openMenu = "scale" },
            onDismiss = { openMenu = null },
            onPick = { config.setScale(it); openMenu = null },
        )
        Spacer(Modifier.padding(start = 20.dp))
        DropdownButton(
            label = "Key",
            expanded = openMenu == "key",
            options = Presets.KeyLabels,
            selected = config.keyIdx,
            defaultIdx = Presets.DefaultKeyIdx,
            theme = theme,
            onOpen = { openMenu = "key" },
            onDismiss = { openMenu = null },
            onPick = { config.setKey(it); openMenu = null },
        )
        Spacer(Modifier.padding(start = 20.dp))
        DropdownButton(
            label = "Size",
            expanded = openMenu == "size",
            options = Presets.SizeLabels,
            selected = config.sizeIdx,
            defaultIdx = Presets.DefaultSizeIdx,
            theme = theme,
            onOpen = { openMenu = "size" },
            onDismiss = { openMenu = null },
            onPick = { config.setSize(it); openMenu = null },
        )
        Spacer(Modifier.padding(start = 20.dp))
        DropdownButton(
            label = "Sound",
            expanded = openMenu == "sound",
            options = Presets.SoundLabels,
            selected = config.soundIdx,
            defaultIdx = Presets.DefaultSoundIdx,
            theme = theme,
            onOpen = { openMenu = "sound" },
            onDismiss = { openMenu = null },
            onPick = { config.setSound(it); openMenu = null },
        )
        Spacer(Modifier.weight(1f))
        PresetsMenu(
            config = config,
            theme = theme,
            expanded = openMenu == "presets",
            onOpen = { openMenu = "presets" },
            onDismiss = { openMenu = null },
        )
        if (recordVisible) {
            IconButton(onClick = onRecordToggle, modifier = Modifier.size(40.dp)) {
                Icon(
                    imageVector = if (isRecording) Icons.Filled.Stop else Icons.Outlined.RadioButtonChecked,
                    contentDescription = if (isRecording) "Stop recording" else "Record",
                    tint = if (isRecording) Color(0xFFE53935) else Color.White,
                )
            }
        }
        IconButton(
            onClick = onAboutClick,
            modifier = Modifier.size(40.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.Settings,
                contentDescription = "Settings",
                tint = Color.White,
            )
        }
    }
}

@Composable
private fun DropdownButton(
    label: String,
    expanded: Boolean,
    options: Array<String>,
    selected: Int,
    defaultIdx: Int,
    theme: EtherTheme,
    onOpen: () -> Unit,
    onDismiss: () -> Unit,
    onPick: (Int) -> Unit,
) {
    Box {
        MenuButton(label, onClick = onOpen)
        ChoiceDropdown(
            expanded = expanded,
            options = options,
            selected = selected,
            defaultIdx = defaultIdx,
            theme = theme,
            onDismiss = onDismiss,
            onPick = onPick,
        )
    }
}

@Composable
internal fun MenuButton(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(Color.Transparent),
        contentAlignment = Alignment.Center,
    ) {
        TextButton(onClick = onClick) {
            Text(
                text = label,
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
            )
        }
    }
}
