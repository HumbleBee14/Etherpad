# Etherpad — Architecture Deep Dive

This document explains how a finger touching the screen becomes sound in Etherpad. It is written for someone who has never seen Csound before but is comfortable with the idea of an audio buffer, a callback, and a JNI bridge. It describes the Android app in detail and then notes where the iOS app differs.

---

## 1. What Etherpad is, musically

Etherpad is a multi-touch theremin/pad. The screen is divided horizontally into a small number of pitch columns (4 to 14, chosen by the user). There are no discrete keys: a finger placed in a column is a continuously-pitched voice, and sliding the finger left/right glides between pitches inside the currently selected scale. The vertical axis is intensity — low Y is quiet/dark, high Y is loud/bright and adds vibrato and timbre depth.

Up to ten fingers can play simultaneously. Each finger occupies one polyphony slot in Csound; that slot is alive for as long as the finger is down. Lifting the finger ends the voice with the instrument's release envelope.

The top menu chooses:

| Control  | What it does                                                                 |
|----------|------------------------------------------------------------------------------|
| Octave   | Base octave (engine values 2..6, default 4)                                  |
| Scale    | One of 10 scales: Default, Major, Minor, Pentatonic, Flamenco, Blues, Chromatic, Whole-Tone, Octatonic, Bohlen-Pierce |
| Key      | Chromatic root (C..B)                                                        |
| Size     | Number of pitch columns across the screen (4..14, default 8)                 |
| Sound    | One of 5 voice modes: Ether Pad, Distorted Dreams, Xanpalamin, Give It a Tri, Digital Monk |

All five sound modes share the same Csound instrument (`instr 1`) — the mode index is a global variable (`gisound`) that selects a branch inside that instrument. See [Presets.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/synth/Presets.kt) for the full label/value tables and [etherpad.csd](../Etherpad-Android/app/src/main/res/raw/etherpad.csd) for the branches.

---

## 2. The pipeline at a glance

```
   finger on glass
        │
        ▼
   ┌─────────────────────────┐
   │ TouchSurface (Compose)  │   pointer events, slot allocation,
   │  ui/TouchSurface.kt     │   normalised [0,1] coordinates
   └─────────────┬───────────┘
                 │   synth.touchDown/Move/Up(slot, x, y)
                 ▼
   ┌─────────────────────────┐
   │ Synth facade            │   formats Csound score strings
   │  engine/Synth.kt        │   ("i1.4 0 -2 4", channel writes)
   └─────────────┬───────────┘
                 │   EtherEngine.native*
                 ▼
   ┌─────────────────────────┐
   │ JNI bridge              │   thin Kotlin -> C++ shim
   │  engine/EtherEngine.kt  │
   └─────────────┬───────────┘
                 │   csoundInputMessage / csoundSetControlChannel
                 ▼
   ┌─────────────────────────┐
   │ Native engine (C++)     │   owns Csound + Oboe; pulls
   │  cpp/engine.cpp         │   csoundPerformKsmps from
   └─────────────┬───────────┘   the audio callback
                 │   float PCM
                 ▼
   ┌─────────────────────────┐
   │ Oboe / AAudio           │   low-latency speaker output
   └─────────────────────────┘
```

Five layers. One Csound instance per process, one Oboe stream per process, one render loop driven from inside the Oboe callback itself.

---

## 3. The touch surface

The drawing surface is a Compose `Canvas` (see [TouchSurface.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/ui/TouchSurface.kt)). Its `pointerInput` block runs an `awaitPointerEventScope` loop and walks every `PointerInputChange` in each event.

Slot allocation is tiny and explicit. Each Compose `PointerId` (a `Long`) is mapped to an integer slot in `[0, Presets.MAX_TOUCHES)` — i.e. `0..9`:

```kotlin
if (!wasDown && isDown) {
    val slot = (0 until Presets.MAX_TOUCHES).firstOrNull { s ->
        slots.values.none { it == s }
    }
    if (slot != null) {
        slots[id] = slot
        synth.touchDown(slot, x, y)
        ...
```

Coordinates are normalised before they leave the UI layer:

- `x = pointer.x / width` in `[0, 1]`
- `y = 1 - pointer.y / height` in `[0, 1]` — so Y=0 is the bottom of the screen (quiet), Y=1 is the top (loud). This matches the way `instr 1` uses `ky` directly as an amplitude/timbre multiplier.

Touch-down, touch-move, and touch-up all go through the `Synth` facade with the slot and `(x, y)`.

---

## 4. The Synth facade

[Synth.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/engine/Synth.kt) does one thing: turn UI actions into Csound score messages and control-channel writes. Csound's input language is line-based; a line like `i1.4 0 -2 4` means "schedule instrument 1, instance 4, start now, duration -2 (held), p4=4".

| UI action               | What `Synth` sends                                                                 |
|-------------------------|------------------------------------------------------------------------------------|
| `touchDown(slot, x, y)` | `chnset touch.<slot>.x = x`, `chnset touch.<slot>.y = y`, then `i1.<slot> 0 -2 <slot>` |
| `touchMove(slot, x, y)` | `chnset touch.<slot>.x = x`, `chnset touch.<slot>.y = y` (no new note)             |
| `touchUp(slot)`         | `i-1.<slot> 0 0 <slot>` (turnoff for that fractional instance)                     |
| `setSize(n)`            | `i100 0 0.5 <n>`                                                                   |
| `setKey(idx)`           | `i101 0 0.5 <idx>`                                                                 |
| `setOctave(v)`          | `i102 0 0.5 <v>`                                                                   |
| `setScale(steps)`       | `i103 0 0.5 <14 ints>`  (or `i103 0 0.5 -1` for Bohlen-Pierce)                     |
| `setSound(idx)`         | `i104 0 0.5 <idx>`                                                                 |

Two things to notice.

**Fractional instance numbers carry the slot.** `i1.4` is "instr 1, instance 4". Csound treats different fractional p1 values as separate, independently turnoff-able voices of the same instrument. That is exactly the polyphony mechanism we need: ten fingers map to `i1.0` through `i1.9`, and `i-1.<slot>` ends only that one. There is no separate "voice manager" instrument; Csound's fractional-instance bookkeeping is the voice manager.

**Constructor loads the .csd from `res/raw`.** `Synth`'s `init` reads the file as text and calls `EtherEngine.nativeLoad(csdText)` followed by `nativeStart()`. The `.csd` is bundled into the APK like any other resource.

---

## 5. The JNI bridge

[EtherEngine.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/engine/EtherEngine.kt) is six external functions and a `System.loadLibrary("ether_engine")`:

```kotlin
object EtherEngine {
    init { System.loadLibrary("ether_engine") }

    external fun nativeLoad(csdText: String): Boolean
    external fun nativeStart(): Boolean
    external fun nativeStop()
    external fun nativeSetControlChannel(name: String, value: Double)
    external fun nativeInputMessage(score: String)
    external fun nativeGetControlChannel(name: String): Double
}
```

It is a Kotlin `object` (singleton). There is no opaque handle passed across the boundary — the native side keeps a single static engine instance (`gEngine()` in [engine.cpp](../Etherpad-Android/app/src/main/cpp/engine.cpp)), so the Kotlin side does not need to remember which engine to talk to.

These six calls are the entire API surface between the JVM and the audio engine. Everything the UI does — playing notes, changing scale, switching sound mode — flows through one of them.

---

## 6. The native engine

This is the interesting layer. [engine.cpp](../Etherpad-Android/app/src/main/cpp/engine.cpp) is a single ~300-line file. It owns:

- the `CSOUND*` handle (`csoundCreate`, `csoundCompileCsdText`, `csoundStart`),
- the `oboe::AudioStream` (Oboe is Google's low-latency audio library, a thin C++ layer on top of AAudio with a fallback to OpenSL ES),
- and the glue that connects them.

### Loading the synth

`load(csdText)` is straightforward:

```cpp
csound_ = csoundCreate(nullptr);
csoundSetMessageCallback(csound_, csoundMessageCallback);
csoundSetOption(csound_, "-+rtaudio=null");
csoundSetOption(csound_, "--nodisplays");
csoundSetMessageLevel(csound_, 135);
csoundCompileCsdText(csound_, csdText.c_str());
csoundStart(csound_);
```

`-+rtaudio=null` is the key option: it tells Csound *not* to open its own audio output. We will pull samples ourselves. The CSD's `-o dac -b512 -B2048` line is ignored at runtime for the same reason.

After `csoundStart`, the engine reads back sample rate, ksmps, channel count, and 0 dB FS reference from Csound and remembers them:

```cpp
sr_       = csoundGetSr(csound_);      // 44100
ksmps_    = csoundGetKsmps(csound_);   // 32
nchnls_   = csoundGetNchnls(csound_);  // 2
zerodbfs_ = csoundGet0dBFS(csound_);   // 1.0
```

ksmps is Csound's audio block size: every call to `csoundPerformKsmps` advances the synth by 32 samples per channel. At 44.1 kHz that is about 0.73 ms — fine-grained enough that touch updates feel instant.

### Starting the audio stream

`start()` builds an Oboe stream and registers `EtherEngine` itself as the callback:

```cpp
builder.setDirection(oboe::Direction::Output)
       ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
       ->setSharingMode(oboe::SharingMode::Exclusive)
       ->setFormat(oboe::AudioFormat::Float)
       ->setSampleRate(static_cast<int32_t>(sr_))
       ->setChannelCount(nchnls_)
       ->setUsage(oboe::Usage::Media)
       ->setContentType(oboe::ContentType::Music)
       ->setCallback(this);
```

Stereo float PCM at 44.1 kHz, exclusive low-latency mode. The buffer is set to two bursts (`stream_->setBufferSizeInFrames(stream_->getFramesPerBurst() * 2)`) — small enough to keep latency low, large enough to absorb occasional callback jitter.

### The render loop — the central insight

Csound is *pulled*, not pushed. There is no separate "Csound performance thread". Every time Oboe calls `onAudioReady(numFrames)` on the audio thread, the engine renders as many k-periods as needed to fill that callback's buffer:

```cpp
int frameIndex = 0;
while (frameIndex < numFrames) {
    if (spoutCursor_ >= ksmps_) {
        int rc = csoundPerformKsmps(csound_);
        if (rc != 0) {
            // score finished; zero-fill and keep stream alive
            std::memset(out + frameIndex * channels, 0,
                        (numFrames - frameIndex) * channels * sizeof(float));
            return oboe::DataCallbackResult::Continue;
        }
        spoutCursor_ = 0;
    }
    const MYFLT* spout = csoundGetSpout(csound_);
    int copyFrames = std::min(numFrames - frameIndex, ksmps_ - spoutCursor_);
    // interleaved copy into Oboe's buffer, scaled by 1/0dbfs
    ...
}
```

`csoundGetSpout` returns Csound's internal output buffer (interleaved, `ksmps * nchnls` MYFLTs). The engine copies from there into Oboe's float buffer, scaled by `1.0 / zerodbfs`. `spoutCursor_` lets a single k-period buffer span multiple Oboe callbacks if Oboe asks for fewer frames than ksmps — and lets one Oboe burst consume several k-periods if it asks for more.

**Why pull instead of push?** An earlier iteration (using `csnd.CsoundOboe` from the Csound-for-Android scheduler) crashed Csound 6.19 at shutdown with a FORTIFY abort: `pthread_mutex_lock called on a destroyed mutex`. Csound's internal helper threads were being torn down while still holding locks. Driving `csoundPerformKsmps` directly from the audio callback (the same approach iOS uses via `CsoundObj`) sidesteps the scheduler entirely. See the comment block at the top of [engine.cpp](../Etherpad-Android/app/src/main/cpp/engine.cpp) for the full reasoning.

### Touch events crossing threads

Touch updates arrive from the UI thread; the render loop runs on the Oboe audio thread. The crossing is done by Csound itself: `csoundSetControlChannel` and `csoundInputMessage` are documented thread-safe — they push into Csound's internal lock-free ring buffers, which the performance code drains at the top of each k-period.

There is no explicit queue, no mutex, no atomic in [engine.cpp](../Etherpad-Android/app/src/main/cpp/engine.cpp) for the event path. The only mutex is `lifecycle_mutex_`, which serialises `load` / `start` / `stop` against each other.

### Teardown

`stop()` only closes the Oboe stream. It deliberately does *not* call `csoundDestroy` or `csoundCleanup`:

```cpp
// We do NOT call csoundCleanup or csoundDestroy here ... Csound has
// internal threads ... that may still be holding mutexes. Calling
// Destroy races those threads and reproduces the v1 FORTIFY abort.
// Instead we leak the Csound instance for the activity's lifetime;
// it'll be reclaimed when the process exits.
```

So the Oboe stream's lifecycle matches the activity, and the Csound instance lives for the entire process. When the OS kills the process, both go away together.

### Native libraries linked

From [CMakeLists.txt](../Etherpad-Android/app/src/main/cpp/CMakeLists.txt): `oboe::oboe` (via the AAR's prefab package), `csoundandroid` and `sndfile` (pre-built `.so` files from `jniLibs/<abi>/`), plus the standard `log` and `android` system libraries.

---

## 7. The Csound .csd

[etherpad.csd](../Etherpad-Android/app/src/main/res/raw/etherpad.csd) is the actual synth program. It is shared byte-for-byte with iOS — both apps bundle the same file. See [CSD.md](CSD.md) for line-by-line details. A brief tour:

### Voices: instr 1

`instr 1` is the per-touch voice. One running instance per active finger, keyed by fractional p1. Its first move is to read its slot's control channels:

```csound
i_instanceNum = p4
S_xName sprintf "touch.%d.x", i_instanceNum
S_yName sprintf "touch.%d.y", i_instanceNum
kx chnget S_xName
ky chnget S_yName
```

`kx` is mapped through the active scale and `gikey + gioct` to a MIDI note, then converted to cps. `ky` becomes a vibrato amount, an envelope-shaping factor, and (in some sound modes) a filter cutoff control. The big `if (gisound == 0) ... elseif (gisound == 1) ...` block at the bottom branches between the five sound modes.

The note holds because `i1.<slot> 0 -2 <slot>` uses a negative duration ("hold indefinitely"); `i-1.<slot> 0 0 <slot>` then turns it off, and the `linsegr` envelope in each branch handles the release tail.

### Parameter setters: instr 100..104

Short instruments that mutate global variables and return:

| Instr | Sets       | Global       |
|-------|------------|--------------|
| 100   | size       | `gisize`     |
| 101   | key        | `gikey`      |
| 102   | octave     | `gioct`      |
| 103   | scale      | `giscale` ftable (or `giBP` sentinel) |
| 104   | sound mode | `gisound`    |

`instr 103` is the most interesting one: when called with a real scale, it `ftfree`s the old `giscale` ftable and rebuilds it from p4..p17. When called with p4 = -1, it sets the Bohlen-Pierce flag instead and `instr 1` takes a different code path.

### Always-on effects

Three instruments run for the lifetime of the process via the `<CsScore>` block at the bottom of the file:

```csound
i888 0 $INF      ; delay
i999 0 $INF      ; reverb (reverbsc)
i"Mixer" 0 $INF  ; final clip + outs
```

`instr 888` is a feedback delay fed by `gadelL/gadelR`. `instr 999` is a `reverbsc` reverb fed by `gaL/gaR`. `instr Mixer` clips the summed `gaMainL/gaMainR` and sends them to the audio output via `outs`. Without these always-on lines there would be nothing reading the global audio busses.

`$INF` is defined locally as `#define INF # 360000 #` (about 100 hours). Csound 6 expands undefined macros to the empty string, which would silently truncate `i888 0 $INF` to `i888 0` (zero duration). The comment in the `.csd` calls this out as a Csound 5 → 6 footgun.

---

## 8. Lifecycle

| Activity callback | What happens                                                                                |
|-------------------|---------------------------------------------------------------------------------------------|
| `onCreate`        | Construct `Synth`, which reads `res/raw/etherpad.csd` and calls `nativeLoad` + `nativeStart`. Setup Compose UI. |
| `onResume`        | Nothing audio-specific — the Oboe stream is already running.                                |
| `onPause`         | Nothing audio-specific — audio keeps playing. (Etherpad does not pause when backgrounded by default.) |
| `onDestroy`       | `synth.stop()` → `nativeStop()` → Oboe `requestStop` + `close`. Csound is intentionally left alive (see §6 teardown). |

The simplicity here is deliberate. There is no manual thread management, no `MediaSession`, no audio focus dance. Oboe owns the audio thread; Csound owns the synthesis; the activity just plumbs touch events through.

---

## 9. File map

### Android

| File                                                                                                                                  | Job                                                                                  |
|---------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| [MainActivity.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/MainActivity.kt)                                     | Activity lifecycle, immersive insets, constructs `Synth` and the Compose tree         |
| [ui/EtherpadApp.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/ui/EtherpadApp.kt)                                 | Top-level composable: places `TouchSurface`, `TopMenuBar`, and the About dialog       |
| [ui/TopMenuBar.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/ui/TopMenuBar.kt)                                   | Octave / Scale / Key / Size / Sound dropdowns; calls `synth.set*`                     |
| [ui/TouchSurface.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/ui/TouchSurface.kt)                               | Compose Canvas, pointer event loop, slot allocator                                    |
| [ui/AboutSheet.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/ui/AboutSheet.kt)                                   | Settings dialog with visual-effects toggles                                          |
| [ui/VisualEffects.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/ui/VisualEffects.kt)                             | Enum of effects + load/save bitmask to `SharedPreferences`                            |
| [synth/Presets.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/synth/Presets.kt)                                   | Labels, defaults, scale step tables, `MAX_TOUCHES = 10`                              |
| [engine/Synth.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/engine/Synth.kt)                                     | Formats Csound score messages from UI events                                          |
| [engine/EtherEngine.kt](../Etherpad-Android/app/src/main/kotlin/com/humblebee/etherpad/engine/EtherEngine.kt)                         | JNI declarations + `System.loadLibrary`                                              |
| [cpp/engine.cpp](../Etherpad-Android/app/src/main/cpp/engine.cpp)                                                                     | Native engine: owns Csound + Oboe, drives `csoundPerformKsmps` from the audio callback |
| [cpp/CMakeLists.txt](../Etherpad-Android/app/src/main/cpp/CMakeLists.txt)                                                             | Builds `libether_engine.so`, links Oboe / csoundandroid / sndfile                     |
| [res/raw/etherpad.csd](../Etherpad-Android/app/src/main/res/raw/etherpad.csd)                                                         | The synth itself — instruments, scales, effects                                       |

### iOS (key files)

| File                                                                                              | Job                                                              |
|---------------------------------------------------------------------------------------------------|------------------------------------------------------------------|
| [Engine/CsoundEngine.swift](../Etherpad-iOS/Etherpad/Engine/CsoundEngine.swift)                   | Swift wrapper around `CsoundObj`; same score messages as Android |
| [Views/TouchSurfaceView.swift](../Etherpad-iOS/Etherpad/Views/TouchSurfaceView.swift)             | `UIView` multi-touch surface, slot allocator, drawing             |
| [SynthPanelViewController.swift](../Etherpad-iOS/Etherpad/SynthPanelViewController.swift)         | Top menu + visual settings sheet                                  |

---

## 10. iOS comparison

The bottom of the stack is identical. Both apps bundle the same [etherpad.csd](../Etherpad-Android/app/src/main/res/raw/etherpad.csd) (iOS keeps its own copy at `Etherpad-iOS/Etherpad/etherpad.csd`) and send the exact same score messages — note that [CsoundEngine.swift](../Etherpad-iOS/Etherpad/Engine/CsoundEngine.swift) builds `"i1.\(i) 0 -2 \(i)"` and `"i-1.\(i) 0 0 \(i)"` strings, the same shape used by Android's `Synth.touchDown` / `touchUp`.

The top three layers differ:

| Layer            | Android                                                                  | iOS                                                                       |
|------------------|--------------------------------------------------------------------------|---------------------------------------------------------------------------|
| Touch surface    | Jetpack Compose `Canvas`, `pointerInput`                                 | `UIView` with `touchesBegan/Moved/Ended`                                  |
| Synth facade     | `Synth.kt` → JNI                                                         | `CsoundEngine.swift` → `CsoundObj` directly                               |
| Native engine    | Custom C++ in [engine.cpp](../Etherpad-Android/app/src/main/cpp/engine.cpp): owns Csound + Oboe, pulls `csoundPerformKsmps` from the Oboe audio callback | `CsoundiOS.xcframework`'s `CsoundObj.play(csdPath)` — Csound owns the audio I/O via its built-in AudioUnit driver |
| Audio I/O        | Oboe (AAudio / OpenSL ES under the hood)                                 | Core Audio / AudioUnit, driven inside `CsoundObj`                         |
| Touch updates    | `csoundSetControlChannel` from Java via JNI                              | Direct write to a `getInputChannelPtr` `UnsafeMutablePointer<Float>` — bound on the `csoundObjStarted:` callback, then poked from the main thread |
| Effects persist  | `SharedPreferences` bitmask                                              | `UserDefaults` + `NotificationCenter`                                     |

The iOS path is shorter because `CsoundObj` already does what `engine.cpp` does on Android: it sets up a Csound instance, attaches it to the platform's audio output, and drives `csoundPerformKsmps`. On Android there is no equivalent maintained wrapper for the current Csound version, so the engine takes that job in-house — and as a side benefit, owning the audio callback avoids the Csound-for-Android scheduler's lifecycle bugs.

Aside from that, the apps are designed to feel identical: same scales, same five sound modes, same ten-voice polyphony.
