package com.humblebee.etherpad.recording

import android.content.Context

internal object RecordingSettings {
    private const val PREFS = "EtherpadPrefs"
    private const val KEY = "EtherpadRecordingEnabled"

    fun isEnabled(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, false)

    fun setEnabled(ctx: Context, enabled: Boolean) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY, enabled).apply()
    }
}
