# Etherpad — Feature Ideas & Roadmap

A running backlog of features to add to **Etherpad**, focused (for now) on the
**macOS / iOS** experience. Pick items off this list one at a time. Each entry notes why it's valuable and implementation hints so we don't lose the context.

Status legend: `[ ]` planned · `[~]` in progress · `[x]` done

## Cross-platform strategy

New features are intended to ship across **all platforms** (macOS, iOS/iPadOS, Android),
but we **prototype and validate on the macOS desktop app first** — it has the fastest iteration loop. Once a feature feels right on desktop, port it to iOS/iPadOS, then Android (which has known audio/latency limitations). Most of the near-term audio features (record, volume, FX) map cleanly across platforms.

---

## Near-term

### [ ] Master volume + Panic (all-notes-off)
**Why:** Tiny additions, surprisingly useful. Panic instantly silences a stuck note.
**What:** A volume slider in the bar/Settings, and a "Panic" button/shortcut that calls
`allNotesOff()` and resets all voices.
**Hints:** Master volume = scale `avEngine.mainMixerNode.outputVolume` (0…1). Panic can
reuse `engine.allNotesOff()` + `surface.cancelAllTouches()`.

### [ ] Drone / sustain lock
**Why:** Freeze currently-sounding notes into a continuous pad to layer melodies on top.
**What:** A toggle (or hold `Space`) that latches active voices so they keep ringing.
**Hints:** Track held voices in `MacCsoundEngine`; on latch, don't send note-off until
unlatched. Great companion to the new Note Sustain setting.

### [ ] Computer-keyboard (QWERTY) play mode
**Why:** Fun and quick; lets people try the synth without a trackpad.
**What:** Map QWERTY rows to notes (like a piano), play on key down/up.
**Hints:** Add key handling in `MacSynthViewController`; map keys to touch slots/notes.
Watch for conflicts with the multitouch key monitor (number keys, Esc, ⌥R).

### [ ] Mouse / click-drag play mode
**Why:** Lets users play without decoupling the cursor (lower barrier to entry).
**What:** When not in multitouch, allow single-pointer click-drag on the surface to
sound one voice.
**Hints:** Add `mouseDown/mouseDragged/mouseUp` handling in `MacSurfaceView` mapped to
a single touch slot.

---

## 

### [ ] MIDI keyboard / controller support
**Why:** The most "pro" desktop feature — Macs are where real MIDI gear lives.
**Plain English:** MIDI is the standard "language" music gear speaks. With MIDI input,
a user plugs in a MIDI keyboard/pad, presses a key, and Etherpad plays that note.
Knobs/sliders (called CC messages) can be mapped to scale, octave, filter, or volume.
This is independent of AUv3 — a standalone app can accept MIDI directly.
**What:** Play the synth from a connected MIDI keyboard; map mod-wheel/expression to
filter, reverb, or volume.
**Hints:** Use CoreMIDI to receive note-on/off + CC; route into `MacCsoundEngine`.
Much smaller scope than AUv3. On iOS/iPadOS, CoreMIDI works too (USB/Bluetooth MIDI).

### [ ] Reverb / delay / FX rack
**Why:** Dramatically changes the vibe with little code.
**What:** An "Effects" section in Settings with wet/dry, reverb size, delay time/feedback.
**Hints:** Add Csound opcodes (`reverbsc`, `delayr/delayw`) to the instrument; expose
params via `UserDefaults` like the existing settings.

### [ ] Configurable axis mapping
**Why:** Power-user control over expression.
**What:** Choose what X and Y axes control (pitch/scale vs. timbre/filter/volume), with
presets.
**Hints:** Extends the existing scale dropdown UI in `MacSynthViewController`.

### [ ] Visual scale guides / note labels
**Why:** Helps players see where notes land; pairs well with the theme system.
**What:** Optional faint horizontal guides or note names on the surface.
**Hints:** Draw in `MacSurfaceView.draw(_:)` using `theme.line`; gate behind a setting.

### [ ] Custom theme color picker + light mode
**Why:** Personalization on top of the 6 presets.
**What:** A "Custom" theme slot with accent/background pickers; add a light theme.
**Hints:** Extend `MacTheme` with a custom palette persisted to `UserDefaults`.

---

## 

### [ ] Audio Unit (AUv3) plugin version
**Why:** Run Etherpad inside Logic / GarageBand / Ableton / AUM — a major value-add,
especially on **iPad** (the sweet spot for AUv3 musicians). Several users have requested it.
**Plain English:** An AUv3 is a plugin that runs *inside* another music app ("the host").
Etherpad would appear as an instrument you add to a track in GarageBand/Logic; its
touch surface becomes the plugin's UI, so you play on the pad right inside the host and
the sound lands on a host track — recordable, mixable, layered with other instruments.
Notes can be triggered two ways: by the host (its on-screen piano / a MIDI keyboard) and
by our own touch UI.
**What:** Package the engine + surface as an AUv3 instrument extension.
**Hints:** Substantial. The audio engine must render into the host's audio callback
(`internalRenderBlock`) instead of running its own output device — Csound supports this
(render to buffers), but it's real work. Needs an AU extension target + app group to
share the engine/CSD. Prototype the render-into-host path on macOS first, then iPad.

### [ ] Preset system
**Why:** Recall full configurations live.
**What:** Save/recall named presets (scale + theme + FX + sustain) with shortcuts.
**Hints:** Serialize all settings to a Codable struct stored in `UserDefaults`/files.

### [ ] Performance overlay
**Why:** Nice for streaming/recording and debugging.
**What:** Show active voices, CPU, and a subtle note-history readout.
**Hints:** Lightweight overlay view toggled from the menu.

---

## Work in Progress

### [x] Audio recording / export
Record button (toolbar + Mode menu + `⌥R`, works during multitouch play) taps the main
mixer and writes the live output straight to a dated WAV in **~/Downloads** (sandbox
entitlement, no temp file, no dialog), then reveals it in Finder. Implemented in
`MacCsoundEngine.startRecording(to:)/stopRecording()`.

### [x] Immersive / Zen play mode (auto-hiding top bar)
Toggle (toolbar button + Mode menu + `⌥H`) that fades the control bar away after ~2s
of mouse inactivity and reveals it when the cursor nears the top edge — clean,
distraction-free surface for performance and recording.

### [x] Configurable Note Sustain (held-still notes)
Enable resting touches so a stationary finger keeps sounding; Settings toggle for
native lift detection (default) vs. a configurable auto-release timeout.
_Shipped: 2026-06-27 (`e51e61a`)._

### [x] Theme system (6 palettes)
Slate (default), Midnight, Ember, Forest, Sakura, Obsidian — selectable in Settings.

### [x] Multi-touch activation fix
Multitouch works regardless of cursor position when activated from toolbar/menu.
