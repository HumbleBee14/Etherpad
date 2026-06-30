package com.humblebee.etherpad.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.humblebee.etherpad.BuildConfig
import com.humblebee.etherpad.R
import com.humblebee.etherpad.recording.RecordingSettings

@Composable
internal fun SettingsSheet(
    initialEffects: Set<VisualEffect>,
    theme: EtherTheme,
    onDismiss: () -> Unit,
    onEffectsChanged: (Set<VisualEffect>) -> Unit,
    onThemeChanged: (EtherTheme) -> Unit,
    onRecordingEnabledChanged: (Boolean) -> Unit,
) {
    val ctx = LocalContext.current
    var effects by remember { mutableStateOf(initialEffects) }
    var visualsEnabled by remember { mutableStateOf(initialEffects.isNotEmpty()) }
    var recordingEnabled by remember { mutableStateOf(RecordingSettings.isEnabled(ctx)) }

    val accent = theme.accent
    val heading = Color.White
    val subtle = Color.White.copy(alpha = 0.6f)

    val config = LocalConfiguration.current
    val maxHeight = (config.screenHeightDp * 0.92f).dp

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = theme.dropdownSurface,
            modifier = Modifier.width(420.dp),
        ) {
            Column(
                modifier = Modifier
                    .heightIn(max = maxHeight)
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Header(version = BuildConfig.VERSION_NAME)

                SectionLabel("Theme", heading)
                ThemeRow(selected = theme, accent = accent, onSelect = onThemeChanged)

                SectionHeaderWithToggle("Visualizations", visualsEnabled, heading, accent) { on ->
                    visualsEnabled = on
                    val next = if (on) (effects.ifEmpty { setOf(VisualEffect.Ripple) }) else emptySet()
                    effects = next
                    saveVisualEffects(ctx, next)
                    onEffectsChanged(next)
                }
                if (visualsEnabled) {
                    VisualEffectRow(effects, accent) { effect ->
                        val next = if (effect in effects) effects - effect else effects + effect
                        effects = next
                        saveVisualEffects(ctx, next)
                        onEffectsChanged(next)
                    }
                }

                Column {
                    SectionHeaderWithToggle("Recording", recordingEnabled, heading, accent) { on ->
                        recordingEnabled = on
                        RecordingSettings.setEnabled(ctx, on)
                        onRecordingEnabledChanged(on)
                    }
                    Text("Recordings save to Music/Etherpad.", color = subtle, fontSize = 13.sp)
                }

                FadingDivider()
                AboutBlock(heading = heading, accent = accent, subtle = subtle)
            }
        }
    }
}

@Composable
private fun Header(version: String) {
    Row(
        verticalAlignment = Alignment.Top,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Image(
            painter = painterResource(id = R.drawable.logo_shadow),
            contentDescription = null,
            modifier = Modifier.size(40.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text("Etherpad", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Text("A multi-touch synth for Android",
                color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
        }
        Text("v$version", color = Color.White.copy(alpha = 0.4f), fontSize = 11.sp)
    }
}

@Composable
private fun FadingDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .height(1.dp)
            .background(
                Brush.horizontalGradient(
                    listOf(Color.Transparent, Color.White.copy(alpha = 0.18f), Color.Transparent),
                ),
            ),
    )
}

@Composable
private fun SectionLabel(text: String, color: Color) {
    Text(text, color = color, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(top = 4.dp))
}

@Composable
private fun ThemeRow(selected: EtherTheme, accent: Color, onSelect: (EtherTheme) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        EtherTheme.all.forEach { t ->
            val isSel = t.id == selected.id
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(t.background)
                    .border(
                        width = if (isSel) 2.dp else 1.dp,
                        color = if (isSel) accent else Color.White.copy(alpha = 0.2f),
                        shape = CircleShape,
                    )
                    .clickable { onSelect(t) },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(14.dp).clip(CircleShape).background(t.accent))
            }
        }
    }
}

@Composable
private fun SectionHeaderWithToggle(
    title: String,
    checked: Boolean,
    color: Color,
    accent: Color,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(title, color = color, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.Black.copy(alpha = 0.85f),
                checkedTrackColor = accent,
                checkedBorderColor = accent,
                uncheckedThumbColor = Color.White.copy(alpha = 0.9f),
                uncheckedTrackColor = Color.White.copy(alpha = 0.12f),
                uncheckedBorderColor = Color.White.copy(alpha = 0.3f),
            ),
        )
    }
}

@Composable
private fun VisualEffectRow(
    selected: Set<VisualEffect>,
    accent: Color,
    onToggle: (VisualEffect) -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        VisualEffect.all.forEach { effect ->
            EffectIcon(effect, effect in selected, accent) { onToggle(effect) }
        }
    }
}

@Composable
private fun EffectIcon(
    effect: VisualEffect,
    isOn: Boolean,
    accent: Color,
    onClick: () -> Unit,
) {
    val bg = if (isOn) accent else Color.White.copy(alpha = 0.06f)
    val fg = if (isOn) Color.Black.copy(alpha = 0.8f) else Color.White.copy(alpha = 0.7f)
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(effect.icon, contentDescription = effect.label, tint = fg,
            modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun AboutBlock(heading: Color, accent: Color, subtle: Color) {
    val ctx = LocalContext.current
    val devText = buildAnnotatedString {
        withStyle(SpanStyle(color = heading)) { append("Developer: ") }
        withStyle(SpanStyle(color = accent, fontWeight = FontWeight.SemiBold)) { append("Dinesh Y") }
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = devText,
            fontSize = 14.sp,
            modifier = Modifier.clickable {
                ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://dineshy.com")))
            },
        )
        Text(
            "Credits: Inspired by Paul Batchelor's EtherSurface app.",
            color = subtle, fontSize = 13.sp, fontStyle = FontStyle.Italic,
        )
    }
}
