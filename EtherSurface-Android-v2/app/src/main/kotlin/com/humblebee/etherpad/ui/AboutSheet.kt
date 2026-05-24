package com.humblebee.etherpad.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.humblebee.etherpad.R

/**
 * About bottom sheet. Material 3 [ModalBottomSheet] so it floats over the
 * playing surface as a popup — dismissed by drag-down, scrim tap, or back
 * press. Content layout mirrors the original 2014 Android About dialog:
 *   title → tagline → developer credit → site link → "Visualizations" header
 *   → chips → original-author credit → logo.
 *
 * The iOS-only "pin the app for live performance" tip is intentionally
 * omitted — Android doesn't have the same edge-gesture interception that
 * made it necessary on iOS.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AboutSheet(
    initialEffects: Set<VisualEffect>,
    onDismiss: () -> Unit,
    onEffectsChanged: (Set<VisualEffect>) -> Unit,
) {
    val ctx = LocalContext.current
    var effects by remember { mutableStateOf(initialEffects) }

    val bg       = Color(0xFF3B444B)
    val textCol  = Color(0xFF5072A7)
    val linkCol  = Color(0xFFE9D66B)
    val subtle   = Color.White.copy(alpha = 0.55f)

    val sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = bg,
        dragHandle = null,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Etherpad", color = textCol, fontSize = 28.sp, fontWeight = FontWeight.Bold)

            Text(
                text = "A multi-touch synth for Android",
                color = textCol,
                fontSize = 14.sp,
            )

            Spacer(Modifier.height(4.dp))

            Text(
                text = "Android app by Dinesh",
                color = textCol,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )

            val linkText = buildAnnotatedString {
                withStyle(SpanStyle(color = linkCol)) { append("dineshy.com") }
            }
            Text(
                text = linkText,
                fontSize = 14.sp,
                modifier = Modifier.clickable {
                    ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://dineshy.com")))
                },
            )

            Spacer(Modifier.height(8.dp))

            Text(
                text = "Visualizations",
                color = textCol,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )

            VisualEffectGrid(
                selected = effects,
                onToggle = { effect ->
                    val next = when {
                        effect == null -> emptySet()
                        effect in effects -> effects - effect
                        else -> effects + effect
                    }
                    effects = next
                    saveVisualEffects(ctx, next)
                    onEffectsChanged(next)
                },
                textColor = textCol,
            )

            Spacer(Modifier.height(8.dp))

            Text(
                text = "Inspired by the original EtherSurface by Paul Batchelor.",
                color = subtle,
                fontSize = 12.sp,
                fontStyle = FontStyle.Italic,
            )

            Image(
                painter = painterResource(id = R.drawable.logo_shadow),
                contentDescription = null,
                modifier = Modifier.size(96.dp),
            )
        }
    }
}

/**
 * 3-column chip grid: "None" + 4 effect chips. Tapping "None" clears all
 * effects; tapping any individual effect toggles its membership. The on/off
 * state is shown by a leading ☑ or ☐ glyph.
 */
@Composable
private fun VisualEffectGrid(
    selected: Set<VisualEffect>,
    onToggle: (VisualEffect?) -> Unit,
    textColor: Color,
) {
    val items: List<Pair<String, VisualEffect?>> =
        listOf("None" to null) + VisualEffect.all.map { it.label to it }

    val chunks = items.chunked(3)

    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        chunks.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { (label, effect) ->
                    val isOn = if (effect == null) selected.isEmpty() else effect in selected
                    Chip(label = label, isOn = isOn, textColor = textColor) { onToggle(effect) }
                }
            }
        }
    }
}

@Composable
private fun Chip(label: String, isOn: Boolean, textColor: Color, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Color.White.copy(alpha = 0.06f))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Text(
            text = if (isOn) "☑ " else "☐ ",
            color = textColor,
            fontSize = 20.sp,
        )
        Text(label, color = textColor, fontSize = 13.sp)
    }
}
