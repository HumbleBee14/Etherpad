package com.humblebee.etherpad.ui

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Adjust
import androidx.compose.material.icons.outlined.Album
import androidx.compose.material.icons.outlined.Gesture
import androidx.compose.material.icons.outlined.ViewColumn
import androidx.compose.ui.graphics.vector.ImageVector

// Persisted as a bitmask in SharedPreferences; empty set selects "None".
enum class VisualEffect(val mask: Int, val label: String, val icon: ImageVector) {
    Ripple(1 shl 0, "Ripple", Icons.Outlined.Album),
    Trail(1 shl 1, "Trail", Icons.Outlined.Gesture),
    Intensity(1 shl 2, "Intensity Ring", Icons.Outlined.Adjust),
    ColumnGlow(1 shl 3, "Column Glow", Icons.Outlined.ViewColumn);

    companion object {
        const val PREFS_NAME = "EtherpadPrefs"
        const val PREFS_KEY  = "EtherpadVisualEffects"
        val all: List<VisualEffect> = entries.toList()
    }
}

/** Read the persisted set of active effects. Empty = "None". */
internal fun loadVisualEffects(ctx: Context): Set<VisualEffect> {
    val prefs = ctx.getSharedPreferences(VisualEffect.PREFS_NAME, Context.MODE_PRIVATE)
    val bits = prefs.getInt(VisualEffect.PREFS_KEY, 0)
    return VisualEffect.all.filter { (bits and it.mask) != 0 }.toSet()
}

/** Persist the set of active effects as a bitmask. */
internal fun saveVisualEffects(ctx: Context, effects: Set<VisualEffect>) {
    val bits = effects.fold(0) { acc, e -> acc or e.mask }
    ctx.getSharedPreferences(VisualEffect.PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putInt(VisualEffect.PREFS_KEY, bits)
        .apply()
}
