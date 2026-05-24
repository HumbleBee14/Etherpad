package com.humblebee.etherpad.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Material 3 single-choice picker. The active option is shown with a filled
 * radio button (mirroring iOS's UIMenu checkmark behaviour). Tapping any
 * row immediately commits the new selection and dismisses the dialog.
 *
 * Used by every menu in the top action bar (Octave / Scale / Key / Size /
 * Sound) — see [TopMenuBar].
 */
@Composable
internal fun ChoiceDialog(
    title: String,
    options: Array<String>,
    selected: Int,
    onDismiss: () -> Unit,
    onPick: (Int) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                options.forEachIndexed { idx, label ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                    ) {
                        RadioButton(
                            selected = idx == selected,
                            onClick = { onPick(idx) },
                        )
                        Text(
                            text = label,
                            modifier = Modifier
                                .padding(start = 8.dp)
                                .fillMaxWidth(),
                        )
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}
