package com.humblebee.etherpad.synth

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

// SharedPreferences-backed preset persistence. Stored as a JSON array string
// (org.json — no extra dependency). Cap matches iOS.
internal object PresetStore {
    const val MAX_PRESETS = 10
    const val MAX_NAME_LENGTH = 32

    private const val PREFS = "EtherpadPrefs"
    private const val KEY = "EtherpadPresets"

    fun load(ctx: Context): List<Preset> {
        val raw = prefs(ctx).getString(KEY, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { fromJson(arr.getJSONObject(it)) }
        }.getOrDefault(emptyList())
    }

    fun isFull(ctx: Context): Boolean = load(ctx).size >= MAX_PRESETS

    fun add(ctx: Context, preset: Preset): Boolean {
        val current = load(ctx)
        if (current.size >= MAX_PRESETS) return false
        save(ctx, current + preset)
        return true
    }

    fun delete(ctx: Context, id: String) {
        save(ctx, load(ctx).filterNot { it.id == id })
    }

    fun rename(ctx: Context, id: String, name: String) {
        save(ctx, load(ctx).map {
            if (it.id == id) it.copy(name = name.take(MAX_NAME_LENGTH)) else it
        })
    }

    private fun save(ctx: Context, presets: List<Preset>) {
        val arr = JSONArray().apply { presets.forEach { put(toJson(it)) } }
        prefs(ctx).edit().putString(KEY, arr.toString()).apply()
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun toJson(p: Preset) = JSONObject().apply {
        put("id", p.id)
        put("name", p.name)
        put("scale", p.scale)
        put("key", p.key)
        put("octave", p.octave)
        put("size", p.size)
        put("sound", p.sound)
    }

    private fun fromJson(o: JSONObject) = Preset(
        id = o.getString("id"),
        name = o.getString("name"),
        scale = o.getInt("scale"),
        key = o.getInt("key"),
        octave = o.getInt("octave"),
        size = o.getInt("size"),
        sound = o.getInt("sound"),
    )
}
