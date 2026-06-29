# Etherpad AUv3 — MIDI & automation notes

Reference for the iPad AUv3 plugin's host integration: what it sends, what it
records, and known host limitations.

## What the plugin exposes

- **Instrument** — component type `aumu` (software instrument). Plays sound in
  response to host MIDI input and its own touch surface.
- **MIDI output** — advertised as `["Etherpad Touch"]` (`midiOutputNames`). Touch
  gestures are emitted as MIDI on the render thread via `AUMIDIOutputEventBlock`:
  - Note On / Note Off per touch (velocity from vertical position, never 0).
  - CC 74 (brightness) per touch-move.
- **5 automatable parameters** — Scale, Key, Sound, Octave, Size. All `unit:
  .indexed` with value strings, so host automation lanes show names ("Major"),
  not raw numbers. Menu changes emit recordable `.touch`/`.value`/`.release`
  gestures stamped with the real host time.

## MIDI 2.0 (UMP)

The plugin opts into the MIDI 2.0 protocol (`audioUnitMIDIProtocol = ._2_0`), so a
UMP-capable host delivers native MIDI 2.0; MIDI 1.0 hosts are translated by CoreMIDI.
Supported MIDI 2.0 Channel Voice messages:

- Note On / Off with 16-bit velocity
- Control Change, Channel Pressure, Poly Pressure (32-bit, normalized)
- Channel Pitch Bend (32-bit, center 0x80000000)
- **Per-note Pitch Bend** — each touched note bends independently
- **Per-note Brightness** (Registered Per-Note Controller index 74) — per-note timbre

Per-note values are additive on top of the channel-wide values (MPE-style): a global
pitch wheel bends every note; a per-note bend adds individual expression on top. Both
protocols flow through one internal path, so behaviour is identical apart from
resolution and per-note independence.

## Recording a touch-surface performance in a host

**The plugin plays live and emits correct MIDI — but a host will not record an
instrument's own MIDI output back onto its own track.** This is standard AUv3 /
host behaviour, not specific to Etherpad: a host records its *input* to a track,
not an instrument's *output*. Playing the host's on-screen keyboard records;
playing the plugin's own surface does not — on the same track.

This affects every playable-surface AUv3 instrument the same way. To capture a
surface performance you route the plugin's MIDI output to a second track (or a
MIDI-recorder), depending on the host.

### Logic Pro (iPad & Mac) — two-track routing

1. Load Etherpad on **Track 1**.
2. Create a second software-instrument **Track 2**.
3. On Track 2, set **Internal MIDI In → Instrument Output → Track 1 (Etherpad)**.
4. Record-enable **Track 2** and record.
5. Play Etherpad's surface on Track 1 → the performance is captured as a MIDI
   region on Track 2.

(Logic ref: *Route MIDI internally between software instruments*.)

### AUM

AUM has no built-in MIDI recorder (it records audio only). Route Etherpad's MIDI
output through the AUM MIDI matrix into a MIDI-recorder plugin (e.g. Atom Piano
Roll 2, Helium) loaded in the same session.

### Other hosts

- **Drambo** (≥ 2.20) and **Loopy Pro** record AUv3 MIDI output directly.
- Hosts without internal MIDI recording use an external loopback (RouteMIDI,
  MIDI Tools Route, StreamByter).

## Parameter automation (menus)

Menu changes (Scale/Key/Sound/Octave/Size) are recordable as automation. In
Logic, arm the track's automation mode (Latch/Touch), then changing a menu writes
to that parameter's automation lane; playback in Read mode drives the UI + sound.

## Not a plugin limitation

The same-track recording restriction cannot be removed from the plugin — it is a
host architecture fact. Etherpad already does its part correctly (registers a
named MIDI output, emits paired note-on/note-off with non-zero velocity and
sample-accurate timestamps), which is what lets the routing workflows above work.
