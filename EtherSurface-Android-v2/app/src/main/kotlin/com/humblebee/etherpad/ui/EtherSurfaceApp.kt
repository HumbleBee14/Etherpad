package com.humblebee.etherpad.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.humblebee.etherpad.engine.Synth

/**
 * Top-level composable. Wraps the touch surface and menu bar in a Material 3
 * dark colour scheme that uses the EtherSurface slate palette.
 *
 * No state of its own — every piece of state lives in either the [Synth]
 * (engine-side) or the child composables ([TouchState] for visible finger
 * positions and live note count; [TopMenuBar]'s `remember` blocks for the
 * selected indices).
 */
@Composable
internal fun EtherSurfaceApp(synth: Synth) {
    val touchState = remember { TouchState() }
    MaterialTheme(colorScheme = darkColorScheme(background = EtherColors.Background)) {
        Surface(modifier = Modifier.fillMaxSize(), color = EtherColors.Background) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .windowInsetsPadding(WindowInsets.systemBars),
            ) {
                TopMenuBar(synth, touchState)
                TouchSurface(synth, touchState, modifier = Modifier.fillMaxSize())
            }
        }
    }
}
