# How `etherpad.csd` Works — A Beginner's Guide to the Etherpad Sound Engine

Through this document, I am trying to understand and explain the file that actually *makes the sound* in Etherpad: `etherpad.csd`. We'll try to understand what every part does, why it's there, and have enough knowledge to build our own simple synth.

---

## Part 1 — What is Csound, and what is a `.csd` file?

**Csound** is a programming language for making sound. You describe *how* to generate audio in text, and Csound turns that text into actual sound coming out of your speakers in real time.

A **`.csd` file** ("Csound Document") is a single text file holding everything Csound needs. It's structured like an HTML page, with tagged sections:

```
<CsoundSynthesizer>      ← the whole document
  <CsOptions>  ...  </CsOptions>       ← command-line settings (where audio goes, buffer sizes)
  <CsInstruments>  ...  </CsInstruments> ← the "orchestra": definitions of how to make sound
  <CsScore>  ...  </CsScore>           ← the "score": what to play and when
</CsoundSynthesizer>
```

The two big ideas, borrowed from a real orchestra:

- **Orchestra** (`<CsInstruments>`) = the *musicians and their instruments* — recipes for making sound. Nothing happens until something tells them to play.
- **Score** (`<CsScore>`) = the *sheet music* — instructions saying "play instrument X, starting now, for this long."

In Etherpad there's a twist: the score is almost empty, because the **app itself** (Swift on Apple, Java/Kotlin on Android) acts as the conductor — it sends play/stop commands live as your fingers move. More on that in Part 6.

---

## Part 2 — The settings at the top (`<CsOptions>` and the header)

### CsOptions
```
-o dac -d -b512 -B2048
```
- `-o dac` — send audio to the **dac** (digital-to-analog converter), i.e. your speakers/headphones, in real time. (If this were `-o sound.wav` it would write a file instead.)
- `-d` — "daemon"/quiet mode: don't pop up Csound's graphical displays.
- `-b512` / `-B2048` — audio buffer sizes (software and hardware). Bigger = more stable but more latency (delay between touch and sound); smaller = snappier but riskier. These are a safe middle ground.

### The header constants
```
nchnls = 2      ; number of output channels → 2 = stereo (Left + Right)
0dbfs  = 1      ; "0 dB full scale" = 1.0 → the loudest a sample can be is 1.0
ksmps  = 32     ; how many audio samples per "control block" (explained below)
sr     = 44100  ; sample rate: 44,100 audio samples per second (CD quality)
```

**This is the single most important concept to understand:** Csound works at **three speeds**, and every variable name tells you which speed it runs at.

| Rate | Prefix | How often it updates | Used for |
|------|--------|---------------------|----------|
| **i-rate** (init) | `i...` | **Once**, when a note starts | Fixed setup values (a starting frequency, a table number) |
| **k-rate** (control) | `k...` | Every `ksmps` samples (here, every 32 samples) | Things that change *over time but slowly*: volume envelopes, knob movements, your finger position |
| **a-rate** (audio) | `a...` | **Every single sample** (44,100×/sec) | The actual sound waveform |

The relationship: `sr = kr × ksmps`. With `sr=44100` and `ksmps=32`, the control rate `kr` is about **1378 updates/second** — fast enough to feel instant for finger movement, but 32× cheaper than computing it per-sample. This split is *why* Csound can run smoothly on a phone: it only does the expensive per-sample math (`a` variables) where it truly matters.

**One more prefix:** `g` means **global** — a variable shared across all instruments (e.g. `gaMainL`, `gisize`). Without `g`, a variable is *local* — private to one note. So:
- `gaMainL` = **g**lobal **a**udio variable (the main left output bus)
- `kx` = local **k**-rate variable (this note's X position)
- `gisize` = **g**lobal **i**-rate variable (the pad's size setting)

---

## Part 3 — Function tables: pre-computed shapes

Before the instruments, the file builds a set of **function tables** (a.k.a. "f-tables"). A function table is just **an array of numbers describing a shape** — most often *one cycle of a waveform*, or an envelope curve. Computing a sine wave from scratch every sample would be wasteful, so instead you compute it *once* into a table and then just read from it. Reading a table over and over at different speeds = different pitches. This is called **table-lookup oscillation**, the heart of most digital synths.

You create one with `ftgen`:
```
gisine ftgen 0, 0, 4096, 10, 1
```
Reading left to right: store in variable `gisine`; `0` = auto-assign a table number; `0` = load immediately; `4096` = table has 4096 points (higher = smoother); `10` = use **GEN routine 10**; `1` = the routine's argument.

**GEN routines** are recipes for filling a table. The ones used here:

| GEN | What it makes | Example in this file |
|-----|---------------|----------------------|
| **GEN10** | A waveform from a sum of **sine** harmonics. Each number = strength of that harmonic. | `gisine ... 10, 1` → just the 1st harmonic = a pure sine. `giadd ... 10, 1,1,1,1` → first four harmonics equal = a brighter, organ-ish tone. |
| **GEN11** | A set of **cosine** harmonics. | `gicosine ... 11, 1` |
| **GEN02** | Store **raw numbers** verbatim (no curve math). | `giscale ... -2, 0,2,4,7,9,...` → the musical scale steps (see below). The `-2` negative GEN number means "don't rescale my values." |
| **GEN05** | An **exponential** curve between points. | `gienv ... 5, 1, 1024, 0.0001` → a curve from 1 down to nearly 0 = a natural-sounding fade. |
| **GEN09** | Sine partials with control over phase/amplitude. | `gisig ... 9, .5,1,270` (a sigmoid shape) |
| **GEN12** | A specialist curve that keeps **FM synthesis** at a steady volume as it changes (used by the "palamin" sound). Not a waveform you hear directly. | `gipalamin ... -12, 20.0` |
| **GEN19** | Like GEN9 but with a DC offset term. | inside the `vowel` effect |

The **scale table** is worth a special look:
```
giscale ftgen 0, 0, 14, -2, 0, 2, 4, 7, 9, 11, 12, 14, 16, 19, 21, 24, 26, 28
```
These numbers (`0, 2, 4, 7, 9...`) are **semitone offsets** — a musical scale. `0`=root, `2`=whole step up, `4`=major third, `7`=perfect fifth, etc. When your finger slides across the pad, the code reads this table to decide which note to snap to. That's how the synth stays "in tune" / in key.

---

## Part 4 — How one note is made: `instr 1`

`instr 1` is **the voice** — the recipe that turns one finger-touch into one note. Everything between `instr 1` and its `endin` is the code for a single note.

The journey from finger → sound, step by step:

### 4a. Read where the finger is
```
i_instanceNum = p4
S_xName sprintf "touch.%d.x", i_instanceNum
kx chnget S_xName
ky chnget S_yName
```
- `p4` is the **4th parameter** passed in when this note was triggered — here, the **slot number** (0–9). Etherpad supports up to 10 fingers, so each gets a slot.
- `sprintf` builds a channel name like `"touch.0.x"`.
- `chnget` **reads a named channel** — a value the app is writing in from outside. So `kx` and `ky` are literally your fingertip's X and Y position (0.0 to 1.0), updated live. (See Part 6 for how the app writes them.)

### 4b. Smooth the movement
```
kx port kx, 0.01
ky port ky, 0.01
```
`port` (portamento) **smooths** a value so it glides instead of jumping. Without it, dragging your finger would produce zipper-like steps (audible clicking). `0.01` is the *half-time* in seconds — how long to cover half the distance to each new target, so it glides quickly but never snaps. This is why Etherpad feels fluid.

### 4c. Turn position into pitch
This is the big `if / elseif` block (lines 146–181). Depending on `giscale_type` (set by the UI), X position maps to a frequency in one of four tuning systems:
- **Bohlen-Pierce** (an exotic non-octave scale), **Overtone Series** (×2), **Overtone Series** (×3), or **Equal Temperament** (normal piano tuning, the `else` branch).

The normal (piano) path:
```
kmidi scale kx, 0, gisize     ; map finger X (0–1) onto 0…gisize steps
kmidi = int(kmidi)            ; snap to a whole step (so you're always in tune)
knote tablei kmidi, giscale   ; look that step up in the scale table → semitone offset
knote = knote + gikey + kvib + 12*(gioct+1)  ; add the key, vibrato, and octave
kcps = cpsmidinn(knote)       ; convert MIDI note number → frequency in Hz
```
- `scale` remaps a 0–1 range onto another range. (Beginner footgun: its arguments are **max before min**, the reverse of what you'd expect.)
- `tablei` reads the scale table *with interpolation*.
- `cpsmidinn` converts a MIDI note number (e.g. 60 = middle C) into **cps** = **c**ycles **p**er **s**econd = Hz. This is the actual pitch the oscillator will play.
- `kvib` (a few lines up) is a gentle `oscili`-driven vibrato added to the note.

The result: **`kcps` = the frequency to play**, in Hz.

### 4d. Make the actual waveform — the 5 "sounds"
Now another `if/elseif` block (lines 186–247) picks the **timbre** based on `gisound` (0–4). Each branch builds an `a`-rate (audio) signal at frequency `kcps`. Examples:

- **Sound 0** — `foscili` (FM synthesis: one sine modulates another → bell/electric-piano tones) wrapped in a slow `linsegr` envelope.
- **Sound 1** — `vco2` (a band-limited sawtooth, like a classic analog synth) through `lpf18` (a resonant low-pass filter).
- **Sound 2** — a complex FM patch ("palamin") with extra shimmer.
- **Sound 3** — a triangle wave (`vco2 ... 12`).
- **Sound 4** — a sawtooth through a `vowel` filter (makes it sound like it's saying "ah/ee/oo").

The envelope opcode you'll see everywhere is **`linsegr`** — a line-segment envelope **with a release**. The trailing `r` is critical: it defines what happens *after note-off*, so the sound fades out smoothly instead of cutting dead. (`linseg` without the `r` has no note-off behavior.) `ktimb expcurve ky, 4` turns finger-Y into a brightness/timbre control.

### 4e. Send the note into the shared buses
```
gaMainL = gaMainL + a1     ; add this note to the main mix (left)
gaMainR = gaMainR + a2     ; ... and right
gadelL  = gadelL  + ...    ; also send some to the delay
gaL     = gaL     + ...    ; ... and some to the reverb
```
The note doesn't go straight to the speakers. It **adds itself into global "buses."** Ten fingers = ten copies of `instr 1` all adding into the same `gaMainL`. This is the key architectural pattern — explained next.

---

## Part 5 — The global bus architecture (the part that's fragile)

Etherpad's whole engine is built on **global accumulator buses**: shared variables that get *filled* by voices and effects, then *read and emptied* once per cycle.

The buses:
- `gaMainL` / `gaMainR` — the final stereo mix that goes to the speakers.
- `gaL` / `gaR` — the **reverb send** (signal destined for reverb).
- `gadelL` / `gadelR` — the **delay send**.

The always-on instruments that service them:

### `instr 888` — Delay (echo)
```
adelL delay gadelL + adelL*0.7, .8    ; 0.8s echo, fed back at 70% → repeating echoes
adelL butlp adelL, 6000               ; soften each echo with a low-pass filter
gaMainL = gaMainL + adelL             ; add echoes into the main mix
clear gadelL, gadelR                  ; empty the delay send for the next cycle
```
The `+ adelL*0.7` feeds the output back into itself → that's what makes an echo *repeat and fade*, instead of happening once.

### `instr 999` — Reverb (space/room)
```
aL, aR reverbsc gaL, gaR, 0.985, 10000  ; lush reverb; 0.985 = long tail
gaMainL = gaMainL + aL
clear gaL, gaR
```
`reverbsc` is a high-quality stereo reverb. The `0.985` "feedback" makes a long, ambient **tail** — the sound that keeps ringing after you lift your finger.

### `instr Mixer` — the only thing that reaches the speakers
```
aL clip gaMainL, 1, 1    ; prevent distortion: soft-limit (smoothly cap) to ±1.0
aR clip gaMainR, 1, 1
outs aL, aR              ; ← THE ONLY 'outs' IN THE FILE: send to speakers
clear gaMainL, gaMainR   ; wipe the bus clean for the next cycle
```
`outs` is "output stereo." `clip` *softly* caps things so they can't get louder than `0dbfs` (1.0), which would distort. And critically, the Mixer **`clear`s** the main bus every cycle — otherwise the sound would accumulate forever and explode.

### Why this is fragile (the `i3` lesson)
Every cycle, Csound runs instruments **in numerical order**: 1, 2, 3 … 888, 999, Mixer. The global buses must **already exist** (be initialized) before any instrument reads them — if an instrument touches a global that hasn't been set up, Csound **aborts the entire orchestra → total silence** (not a partial glitch).

This is why the score line `i3 0 $INF` looks like dead code (there's no `instr 3` defined!) but **removing it kills all audio.** It's load-bearing for the start-up/initialization order of the engine. **Lesson: in Csound, "instrument not defined" does NOT mean "does nothing," and the only reliable test of any change here is — does the audio still play?**

---

## Part 6 — How the app talks to Csound (the software bus)

Csound runs *inside* the Etherpad app. They communicate through **named channels** — a shared mailbox.

- **App → Csound (your finger):** the app writes your touch position to channels named `touch.0.x`, `touch.0.y`, `touch.1.x`, … The orchestra reads them with `chnget` (Part 4a). On the Apple side this is done with a cached raw pointer for speed; conceptually it's the same as `chnset` from outside.
- **App → Csound (start/stop a note):** when you touch down, the app sends a **score event** — effectively `i 1 0 -1 <slot>` ("start instrument 1, slot N, hold indefinitely"). On lift, it sends a matching note-off. This is the app acting as the live conductor.
- **App → Csound (settings):** when you change Key/Octave/Scale/Size/Sound in the UI, the app fires the setter instruments — `i100`…`i104` — which set the globals `gisize`, `gikey`, `gioct`, `giscale_type`, `gisound`.

### The score section
```
i888 0 $INF        ; run the delay forever
i999 0 $INF        ; run the reverb forever
i"Mixer" 0 $INF    ; run the mixer forever
i100 0 0.5 8       ; set initial size = 8
i101 0 4 0         ; set initial key
i3 0 $INF          ; (load-bearing init — do not remove; see Part 5)
```
`$INF` is **not** a built-in Csound word — it's a **macro this file defines itself** at the top of the score: `#define INF # 360000 #`. So `$INF` just expands to the number `360000` (100 hours), i.e. "run essentially forever." (`#define NAME # value #` is Csound's macro syntax; `$NAME` inserts it.) The real Csound idiom for an open-ended note is a **negative duration** (`p3 = -1`) or the `ihold` opcode — this file uses the big-number macro instead, which works the same in practice. The effects and mixer must stay alive the entire session, so they're started at time 0 for `$INF`.

The `i` statement format is: `i <instrument> <start-time> <duration> <p4> <p5> …`. So `i100 0 0.5 8` = "instrument 100, start at 0s, last 0.5s, with p4=8."

---

## Part 7 — The full signal flow, in one picture

```
   Your fingers (touch.N.x / touch.N.y channels)
            │
            ▼
   ┌──────────────────┐   up to 10 copies, one per finger
   │   instr 1 (voice)│   position → pitch → waveform → envelope
   └──────────────────┘
            │  adds into buses
            ├───────────────► gaL / gaR  ──► instr 999 (reverb) ──┐
            ├───────────────► gadelL/R   ──► instr 888 (delay)  ──┤
            └───────────────► gaMainL/R  ◄────────────────────────┘
                                  │   (effects add their wet signal back in)
                                  ▼
                          instr Mixer:  clip → outs → 🔊  → clear
                                  │
                                  ▼
                            your speakers
```

Read it as: **fingers fill the voice; the voice fills the buses; the effects enrich the buses; the Mixer plays the buses and wipes them clean — 1,378 times a second.**

---

## Part 8 — The same ideas, in everyday terms

If the abstract parts still feel slippery, here's each one mapped to something you've already seen or touched. These aren't loose metaphors — in most cases the digital version is doing *literally the same thing* as the physical one.

### A function table is a music box cylinder 🎵
A wind-up music box has a metal cylinder with bumps on it. As it spins, the bumps pluck the comb's teeth — and **the faster it spins, the higher the pitch.** A function table is that cylinder, but made of numbers: one full turn = one cycle of the waveform. The oscillator (`oscili`) "spins" through the table over and over, and how fast it spins sets the note. Spin the *same* bumps faster → higher note. That's table-lookup synthesis in one image.

```
   Music box cylinder              Csound function table (giSine)
   ┌───────────────┐               [0.0, 0.38, 0.71, 0.92, 1.0, 0.92, ... ]
   │ ▪  ▪▪  ▪   ▪▪ │  spin →           └──── oscili reads these in a loop ────┘
   └───────────────┘                    faster loop = higher pitch
     faster spin = higher note
```

### The three rates (i / k / a) are a car's dashboard ⏱️
Imagine driving:
- **i-rate** = things set **once when you start the trip** — your destination, the radio preset. (A note's starting frequency, which table to use.)
- **k-rate** = the **speedometer needle** — it updates many times a second, smoothly, because the speed *changes* but you don't need every microscopic value. (Your finger position, a volume envelope.)
- **a-rate** = the **actual spinning of the wheels** — the fastest-moving thing, the real motion underneath. (The audio waveform itself, 44,100 times/sec.)

You wouldn't recompute your destination every wheel-rotation — that's the whole point of splitting the rates. Csound does the cheap stuff (k) often enough to *feel* smooth, and saves the expensive per-sample stuff (a) for the sound itself.

### The global buses are a recording-studio mixing desk 🎛️
This is the closest real-world match. In a studio, every microphone has its own channel, but they all feed a few shared **buses**, and there are **aux sends** that split a copy of the signal off to a reverb unit and bring the wet result back. Etherpad does *exactly* this:

```
  STUDIO MIXING DESK                         ETHERPAD ENGINE
  ──────────────────                         ───────────────
  Mic 1 ─┐                                   Finger 1 (instr 1) ─┐
  Mic 2 ─┤                                   Finger 2 (instr 1) ─┤
  Mic 3 ─┼─► MAIN BUS ─► speakers            Finger 3 (instr 1) ─┼─► gaMainL/R ─► outs ─► 🔊
         │                                                       │
         └─► AUX SEND ─► reverb unit ─┐      (a little of each)  └─► gaL/gaR ─► reverbsc ─┐
                  reverb returns ─────┘            reverb returns back into gaMainL/R ────┘
```

- Each **finger** = a **microphone channel** (one voice).
- `gaMainL/R` = the **main mix bus** that goes to the speakers.
- `gaL/gaR` and `gadelL/gadelR` = **aux sends** — a copy peeled off and sent to the reverb (`instr 999`) and delay (`instr 888`), which return their processed sound back into the main bus.
- `instr Mixer` = the **master fader** — the one place everything leaves the desk and reaches your ears.

And the `clear` every cycle? That's the engineer **resetting the meters to zero** before the next moment of music, so levels don't pile up and redline.

### Reverb is a bouncing ball in a room 🏀
Clap once in a cathedral and you hear the clap, then a wash of echoes that fade as the sound bounces off walls and loses energy each bounce. `reverbsc` simulates exactly that — many tiny echoes blended together. The **"tail"** is how long the ball keeps bouncing before it stops: a small room = a quick fade, a cathedral = a long, slow fade. The `0.985` feedback setting is "how bouncy the walls are."

### Delay (echo) is shouting across a canyon 🏔️
Shout "hello" at a cliff and it comes back: *hello … hello … hello …*, each repeat quieter. A delay line stores your sound and replays it after a set time; **feeding a fraction of the output back into itself** is what makes it repeat and fade instead of echoing just once. That `* 0.7` in the delay code = the canyon returning 70% of the energy each bounce.

### Named channels are a restaurant order ticket 🍽️
The app (your finger) and Csound (the kitchen) never talk directly — they pass **tickets** through a window. The app writes "table 3 wants position 0.42" onto a ticket labeled `touch.3.x`; the kitchen (`chnget`) reads that ticket whenever it's ready. Neither has to wait for the other — that's why a smooth 60-fps finger drag and the audio engine can run at different speeds without tripping over each other.

---

## Part 9 — Build your own tiny synth (a starting point)

Here's a minimal, self-contained `.csd` using the same ideas, so you can experiment. Save it as `mysynth.csd` and run with `csound mysynth.csd`.

```csound
<CsoundSynthesizer>
<CsOptions>
-o dac -d
</CsOptions>
<CsInstruments>
sr     = 44100
ksmps  = 32
nchnls = 2
0dbfs  = 1

gisine ftgen 0, 0, 4096, 10, 1     ; one-cycle sine table

instr 1
  ifreq = p4                       ; p4 = frequency, passed from the score
  aenv  linsegr 0, 0.05, 0.3, 0.2, 0   ; attack→sustain→(release on note-off)
  asig  oscili aenv, ifreq, gisine ; read the sine table at ifreq Hz
  outs  asig, asig                 ; play it in both speakers
endin
</CsInstruments>
<CsScore>
i 1 0 1 261.6     ; middle C for 1 second
i 1 1 1 329.6     ; E
i 1 2 1 392.0     ; G
</CsScore>
</CsoundSynthesizer>
```

What to try next, building toward Etherpad's design:
1. Replace `oscili` with `vco2 aenv, ifreq` for a richer sawtooth.
2. Add a filter: `asig lpf18 asig, 2000, 0.7, 0.3`.
3. Add a global reverb bus: have `instr 1` do `gaRev = gaRev + asig*0.2`, then add an always-on `instr 99` running `reverbsc` on `gaRev`, and a mixer that `outs` and `clear`s. Keep the effect/mixer alive with a long-duration score line like Etherpad does, or with the modern `alwayson "99"` opcode. Now you've rebuilt Etherpad's architecture in miniature.
4. Use `chnget` instead of `p4` and feed it from a host app — and you've built a live instrument.

---

## Quick reference — opcodes used in this file

| Opcode | Plain-English meaning |
|--------|----------------------|
| `oscili` / `oscils` | Oscillator: read a table in a loop to make a tone (`i`=interpolating, `s`=simple fixed) |
| `foscili` | FM oscillator (one sine modulates another → bell/EP tones) |
| `vco2` | Band-limited analog-style oscillator (saw/square/triangle, no aliasing) |
| `lpf18` | Resonant low-pass filter modeled on the classic Moog ladder (adds analog character; high resonance can self-oscillate) |
| `butlp` / `butbp` | Butterworth low-pass / band-pass filters (smooth, clean, non-resonant; aliases of `butterlp` / `butterbp`) |
| `balance` | Match one signal's loudness (RMS) to a reference — used after a filter to restore the original level |
| `reverbsc` | High-quality stereo reverb (Costello feedback-delay-network design) |
| `delay` | Time-delay line (echo); feed output back for repeats |
| `oscili` for vibrato (`kvib`) | A slow oscillator used to wobble pitch |
| `linsegr` | Envelope of straight-line segments **with a release** (handles note-off) |
| `expcurve` | Map 0–1 onto an exponential curve (natural-feeling controls) |
| `port` | Portamento — smooth/glide a changing value |
| `scale` | Remap a value from one range to another |
| `int` | Round down to a whole number (used to snap to scale steps) |
| `cpsmidinn` | MIDI note number → frequency (Hz) |
| `cpspch` / `octpch` / `cpsoct` | Convert between Csound's pitch notations and Hz |
| `table` / `tablei` | Read a value from a function table (`i` = interpolated) |
| `ftgen` / `ftgentmp` / `ftfree` | Create / create-temporary / free a function table |
| `chnget` / `chnset` | Read / write a named channel (the app↔Csound bridge) |
| `sprintf` | Build a text string (used to make channel names like `touch.3.x`) |
| `randomi` | Random values, interpolated over time |
| `pan2` | Spread a mono signal across stereo (left/right placement) |
| `clip` | Hard-limit a signal so it can't exceed full scale (anti-distortion) |
| `clear` | Zero out a global variable (reset a bus each cycle) |
| `outs` | Send a stereo signal to the speakers |
| `init` | Set a value once, at note start |
| `db` | Convert decibels to a linear amplitude |

---

*Etherpad's engine descends from the Csound `MultiTouchXY` example by Steven Yi and Victor Lazzarini (2011), built on by Paul Batchelor (2014). It's a beautiful, compact example of live, multi-touch, polyphonic synthesis — and now you know how it works.*
