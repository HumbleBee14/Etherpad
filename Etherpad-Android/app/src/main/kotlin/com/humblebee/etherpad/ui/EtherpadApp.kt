package com.humblebee.etherpad.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.humblebee.etherpad.engine.Synth

@Composable
internal fun EtherpadApp(synth: Synth) {
    val ctx = LocalContext.current
    val touchState = remember { TouchState() }
    var effects by remember { mutableStateOf(loadVisualEffects(ctx)) }
    var showAbout by remember { mutableStateOf(false) }

    MaterialTheme(colorScheme = darkColorScheme(background = EtherColors.Background)) {
        Surface(modifier = Modifier.fillMaxSize(), color = EtherColors.Background) {
            Box(modifier = Modifier.fillMaxSize()) {
                // Surface fills the screen; the menu bar overlays its top edge
                // so the bar's translucent background reveals the columns behind it.
                TouchSurface(synth, touchState, effects, modifier = Modifier.fillMaxSize())
                TopMenuBar(synth, touchState, onAboutClick = { showAbout = true })
            }
            if (showAbout) {
                AboutSheet(
                    initialEffects = effects,
                    onDismiss = { showAbout = false },
                    onEffectsChanged = { effects = it },
                )
            }
        }
    }
}
