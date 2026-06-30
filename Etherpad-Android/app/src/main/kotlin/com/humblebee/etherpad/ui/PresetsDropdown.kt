package com.humblebee.etherpad.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.humblebee.etherpad.synth.Preset
import com.humblebee.etherpad.synth.PresetStore
import kotlinx.coroutines.delay

@Composable
internal fun PresetsMenu(
    config: SynthConfigState,
    theme: EtherTheme,
    expanded: Boolean,
    onOpen: () -> Unit,
    onDismiss: () -> Unit,
) {
    val ctx = LocalContext.current
    val presets = remember { mutableStateListOf<Preset>().apply { addAll(PresetStore.load(ctx)) } }
    var editingId by remember { mutableStateOf<String?>(null) }
    var confirmingId by remember { mutableStateOf<String?>(null) }
    var capFlash by remember { mutableStateOf(false) }

    fun refresh() { presets.clear(); presets.addAll(PresetStore.load(ctx)) }

    if (capFlash) {
        LaunchedEffect(Unit) { delay(2500); capFlash = false }
    }

    Box {
        IconButton(onClick = onOpen, modifier = Modifier.size(40.dp)) {
            Icon(
                imageVector = Icons.Outlined.BookmarkBorder,
                contentDescription = "Presets",
                tint = Color.White,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { editingId = null; confirmingId = null; onDismiss() },
            offset = DpOffset(x = 0.dp, y = 8.dp),
            shape = RoundedCornerShape(10.dp),
            containerColor = theme.dropdownSurface,
            modifier = Modifier.widthIn(min = 240.dp).heightIn(max = 360.dp),
        ) {
            SaveRow(
                flash = capFlash,
                accent = theme.accent,
                onSave = {
                    val name = Preset.suggestedName(
                        config.scaleIdx, config.keyIdx, config.octaveIdx,
                        config.soundIdx, PresetStore.MAX_NAME_LENGTH,
                    )
                    if (PresetStore.add(ctx, config.snapshot(name))) refresh() else capFlash = true
                },
                onReset = { config.resetToDefaults(); onDismiss() },
            )

            if (presets.isNotEmpty()) {
                HorizontalDivider(color = Color.White.copy(alpha = 0.10f))
            }

            presets.forEach { preset ->
                PresetRow(
                    preset = preset,
                    active = config.matches(preset),
                    editing = editingId == preset.id,
                    confirming = confirmingId == preset.id,
                    accent = theme.accent,
                    onLoad = {
                        if (editingId == null && confirmingId == null) {
                            config.apply(preset); onDismiss()
                        }
                    },
                    onBeginEdit = { confirmingId = null; editingId = preset.id },
                    onCommitEdit = { newName ->
                        if (newName.isNotBlank()) PresetStore.rename(ctx, preset.id, newName.trim())
                        editingId = null; refresh()
                    },
                    onBeginDelete = { editingId = null; confirmingId = preset.id },
                    onConfirmDelete = { PresetStore.delete(ctx, preset.id); confirmingId = null; refresh() },
                    onCancelDelete = { confirmingId = null },
                )
            }
        }
    }
}

@Composable
private fun SaveRow(flash: Boolean, accent: Color, onSave: () -> Unit, onReset: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 12.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
    ) {
        if (flash) {
            Text("Limit reached", color = Color(0xFFE57373), fontSize = 14.sp,
                fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        } else {
            IconButton(onClick = onSave, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Outlined.Add, contentDescription = "Save current", tint = accent)
            }
            Spacer(Modifier.width(8.dp))
            Text("Save current", color = Color.White, fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f).clickableNoRipple(onSave))
        }
        RowIcon(Icons.Outlined.Refresh, "Reset to defaults", Color.White.copy(alpha = 0.6f), onReset)
    }
}

@Composable
private fun PresetRow(
    preset: Preset,
    active: Boolean,
    editing: Boolean,
    confirming: Boolean,
    accent: Color,
    onLoad: () -> Unit,
    onBeginEdit: () -> Unit,
    onCommitEdit: (String) -> Unit,
    onBeginDelete: () -> Unit,
    onConfirmDelete: () -> Unit,
    onCancelDelete: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickableNoRipple { if (!editing && !confirming) onLoad() }
            .padding(start = 12.dp, end = 4.dp, top = 2.dp, bottom = 2.dp),
    ) {
        when {
            editing -> InlineNameField(
                initial = preset.name,
                onCommit = onCommitEdit,
                modifier = Modifier.weight(1f),
            )
            else -> Column(Modifier.weight(1f)) {
                Text(
                    preset.name,
                    color = if (active) accent else Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                )
                Text(
                    preset.summary,
                    color = Color.White.copy(alpha = 0.45f),
                    fontSize = 11.sp,
                    maxLines = 1,
                )
            }
        }

        if (confirming) {
            Text("Delete?", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
            RowIcon(Icons.Filled.Check, "Confirm delete", Color(0xFFE57373), onConfirmDelete)
            RowIcon(Icons.Filled.Close, "Cancel", Color.White.copy(alpha = 0.6f), onCancelDelete)
        } else if (!editing) {
            RowIcon(Icons.Outlined.Edit, "Rename", Color.White.copy(alpha = 0.6f), onBeginEdit)
            RowIcon(Icons.Outlined.Delete, "Delete", Color.White.copy(alpha = 0.6f), onBeginDelete)
        }
    }
}

@Composable
private fun InlineNameField(
    initial: String,
    onCommit: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var text by remember { mutableStateOf(initial) }
    val focus = remember { FocusRequester() }
    var hadFocus by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { focus.requestFocus() }

    BasicTextField(
        value = text,
        onValueChange = { if (it.length <= PresetStore.MAX_NAME_LENGTH) text = it },
        singleLine = true,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { onCommit(text) }),
        textStyle = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White),
        cursorBrush = SolidColor(Color.White),
        modifier = modifier
            .focusRequester(focus)
            .onFocusChanged { state ->
                if (hadFocus && !state.isFocused) onCommit(text)
                hadFocus = state.isFocused
            },
    )
}

@Composable
private fun RowIcon(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    desc: String,
    tint: Color,
    onClick: () -> Unit,
) {
    IconButton(onClick = onClick, modifier = Modifier.size(32.dp)) {
        Icon(icon, contentDescription = desc, tint = tint, modifier = Modifier.size(17.dp))
    }
}

@Composable
private fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    return this.clickable(interactionSource = interaction, indication = null, onClick = onClick)
}
