package com.humblebee.etherpad.ui

import android.content.Context
import androidx.compose.ui.graphics.Color

// Accent-derived palette: all tinted visuals come from `accent`.
internal data class EtherTheme(
    val id: String,
    val name: String,
    val background: Color,
    val line: Color,
    val accent: Color,
) {
    val circleColor: Color get() = accent.copy(alpha = 0.5f)
    val glowColor: Color get() = accent.copy(alpha = 0.07f)
    val topBar: Color get() = Color(0xFF545454)
    val dropdownSurface: Color get() = lighten(background, 0.10f)

    fun accent(alpha: Float): Color = accent.copy(alpha = alpha)

    companion object {
        val slate = EtherTheme("slate", "Slate",
            Color(0xFF3B444B), Color(0xFF5072A7), Color(0xFFE9D66B))
        val midnight = EtherTheme("midnight", "Midnight",
            Color(0xFF141624), Color(0xFF3D5A80), Color(0xFFC77DFF))
        val ember = EtherTheme("ember", "Ember",
            Color(0xFF241512), Color(0xFF7A422F), Color(0xFFFF8C42))
        val forest = EtherTheme("forest", "Forest",
            Color(0xFF12221B), Color(0xFF2F6B4F), Color(0xFF9BE564))
        val sakura = EtherTheme("sakura", "Sakura",
            Color(0xFF2A1D24), Color(0xFF7A4F63), Color(0xFFFF9EC4))
        val obsidian = EtherTheme("obsidian", "Obsidian",
            Color(0xFF0C0D10), Color(0xFF333A45), Color(0xFF5AD1E6))

        val all = listOf(slate, midnight, ember, forest, sakura, obsidian)
        val default = slate
    }
}

private fun lighten(c: Color, amount: Float): Color = Color(
    red = c.red + (1f - c.red) * amount,
    green = c.green + (1f - c.green) * amount,
    blue = c.blue + (1f - c.blue) * amount,
    alpha = 1f,
)

internal object ThemeStore {
    private const val PREFS = "EtherpadPrefs"
    private const val KEY = "EtherpadTheme"

    fun load(ctx: Context): EtherTheme {
        val id = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        return EtherTheme.all.firstOrNull { it.id == id } ?: EtherTheme.default
    }

    fun save(ctx: Context, theme: EtherTheme) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, theme.id).apply()
    }
}
