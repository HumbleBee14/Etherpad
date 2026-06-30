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
import androidx.compose.runtime.rememberCoroutineScope
import com.humblebee.etherpad.engine.Synth
import com.humblebee.etherpad.recording.Recorder
import com.humblebee.etherpad.recording.RecordingSettings

@Composable
internal fun EtherpadApp(synth: Synth) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val touchState = remember { TouchState() }
    val config = rememberSynthConfigState(synth, touchState)
    val recorder = remember { Recorder(ctx, synth, scope) }
    var effects by remember { mutableStateOf(loadVisualEffects(ctx)) }
    var theme by remember { mutableStateOf(ThemeStore.load(ctx)) }
    var recordingEnabled by remember { mutableStateOf(RecordingSettings.isEnabled(ctx)) }
    var showSettings by remember { mutableStateOf(false) }

    MaterialTheme(colorScheme = darkColorScheme(background = theme.background)) {
        Surface(modifier = Modifier.fillMaxSize(), color = theme.background) {
            Box(modifier = Modifier.fillMaxSize()) {
                // Surface fills the screen; the menu bar overlays its top edge
                // so the bar's translucent background reveals the columns behind it.
                TouchSurface(synth, touchState, effects, theme, modifier = Modifier.fillMaxSize())
                TopMenuBar(
                    config = config,
                    theme = theme,
                    recordVisible = recordingEnabled,
                    isRecording = recorder.isRecording,
                    onRecordToggle = recorder::toggle,
                    onAboutClick = { showSettings = true },
                )
            }
            if (showSettings) {
                SettingsSheet(
                    initialEffects = effects,
                    theme = theme,
                    onDismiss = { showSettings = false },
                    onEffectsChanged = { effects = it },
                    onThemeChanged = { theme = it; ThemeStore.save(ctx, it) },
                    onRecordingEnabledChanged = { recordingEnabled = it },
                )
            }
        }
    }
}
