# Etherpad for Apple platforms

Multi-touch synthesizer for **iPhone, iPad, and Mac**. Drag fingers across
the surface to play — horizontal position picks pitch, vertical position
controls intensity and timbre.

- **iOS / iPadOS** — up to 5 voices on iPhone, 10+ on iPad; UIKit + Csound 7
- **iPad AUv3** — run inside **GarageBand**, **AUM**, or other hosts as **HumbleBee: Etherpad**
- **macOS** — click-drag or trackpad Multitouch mode (⌥M); AppKit + Csound 6.18.1

Both app targets live in one Xcode project (`Etherpad-iOS` and `Etherpad-macOS`
schemes). The iOS app embeds the **Etherpad-AU** extension so hosts can load the
plugin after a normal install. They share the bundle ID and ship as **Etherpad** on
device and in the store.

## Features

- Full-screen multi-touch surface
- 12 scales, 12 keys, 5 octaves, 4–14 notes across the surface
- 5 sound modes: Ether Pad, Distorted Dreams, Xanpalamin, Give it a Tri, Digital Monk
- Delay + reverb effects
- iPad split-screen mode (two independent synths)
- macOS Multitouch trackpad mode (up to 10 voices)

## Building

**Read [BUILD.md](BUILD.md).** All Csound frameworks are vendored under `Frameworks/`

```sh
open Etherpad-Apple/Etherpad.xcodeproj
```

| Scheme | Target | Run on |
|--------|--------|--------|
| **Etherpad-iOS** | iPhone / iPad | Simulator or device |
| **Etherpad-AU** | AUv3 extension only | Build / CI (embedded in iOS app) |
| **Etherpad-macOS** | Mac | My Mac |

Console should print channel binding within a second of launch. Touch (or click-drag on Mac) → sound.

## Project structure

```
Etherpad-Apple/
  BUILD.md
  Etherpad.xcodeproj/
  Frameworks/
    CsoundiOS.xcframework/       iOS Csound 7
    libSndfileiOS.xcframework/   iOS libsndfile
    CsoundLib64.framework/       macOS Csound 6.18.1
  iOS/                           UIKit app (Etherpad-iOS target)
    Shared/                      Synth catalog, patch state, touch routing (app + AU)
  AU/                            Etherpad-AU extension (iPad AUv3 plugin UI + audio unit)
  macOS/                         AppKit app (Etherpad-macOS target)
    project-setup/               Idempotent Xcode target generator (macOS)
```

## Architecture

See [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) for the synth pipeline
(instruments, channels, touch → sound).

See [../docs/IOS_PORT.md](../docs/IOS_PORT.md) for the iOS port strategy notes.

## Credits

- Apple apps by **Dinesh (aka HumbleBee)** — [dineshy.com](https://dineshy.com)
- Sound engine: [Csound](https://www.csounds.com)
- Inspired by Paul Batchelor's 2014 Android app EtherSurface.
