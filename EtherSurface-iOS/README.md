# EtherSurface for iOS / iPadOS

A faithful port of the EtherSurface multi-touch synthesizer from Android
to iOS, using the same Csound engine and the **byte-identical**
`etherpad.csd` synth definition.

## Features (matches Android)

- Full-screen multi-touch surface
  - **5** simultaneous fingers on iPhone (iOS hardware limit)
  - **10–11** on iPad
- X axis = pitch (quantized to scale), Y axis = intensity / timbre
- 12 scales: Default, Major, Minor, Pentatonic, Flamenco, Blues,
  Chromatic, Whole-Tone, Octatonic, Bohlen-Pierce, Overtone Series
  (Low/High)
- 12 chromatic keys (C through B)
- 5-octave range
- 4 to 14 notes across the surface
- 5 sound modes: Ether Pad, Distorted Dreams, Xanpalamin, Give it a Tri,
  Digital Monk
- Delay + reverb effects

## Building

**Read [BUILD.md](BUILD.md).** The iOS app depends on the Csound for iOS
framework (~12 MB), which is not committed to git and must be downloaded
and integrated into Xcode by each developer. The doc walks through the
steps in order.

TL;DR for someone who already knows the drill:

1. Download `csound-ios-7.0.0-beta.16.zip` from
   [csound/csound releases](https://github.com/csound/csound/releases)
2. Copy `CsoundiOS.xcframework` and `libSndfileiOS.xcframework` into
   `EtherSurface-iOS/`
3. Open `EtherSurface.xcodeproj`, drag both into the target, set
   **Embed & Sign**
4. Pick your signing team, pick your device, ⌘R

Console should print `[EtherSurface] Csound channels bound: 10/10`
within a second of launch. Touch the screen → sound.

## Project structure

```
EtherSurface-iOS/
  BUILD.md                       Step-by-step build instructions
  EtherSurface.xcodeproj/        The Xcode project (committed)
  Headers/                       Patched CsoundObj.h/.m + CsoundMIDI.h/.m
                                 — Obj-C wrapper sources, tracked in git
  CsoundiOS.xcframework/         (gitignored — download per BUILD.md)
  libSndfileiOS.xcframework/     (gitignored — download per BUILD.md)
  EtherSurface/
    AppDelegate.swift            App entry point
    EtherSurfaceViewController.swift  Main VC: Csound lifecycle, menus,
                                      touch → engine
    EtherSurface-Bridging-Header.h    Imports CsoundObj.h for Swift
    Info.plist                   App configuration
    LaunchScreen.storyboard      Launch screen (solid dark bg)
    Engine/
      CsoundEngine.swift         Wraps CsoundObj — channels, score,
                                 lifecycle, CsoundObjListener bridge
    Views/
      TouchSurfaceView.swift     Full-screen UIView — grid, finger circles,
                                 touch tracking
    Resources/
      etherpad.csd               The synth — identical to Android
    About/
      AboutViewController.swift  WKWebView modal sheet
      about.html                 About page content (from Android assets)
      logo.png, logo_shadow.png
    Assets.xcassets/             App icon
```

## How it maps to the Android version

| Android                        | iOS                                          |
| ------------------------------ | -------------------------------------------- |
| `MainActivity.java`            | `EtherSurfaceViewController.swift`           |
| `MultiTouchView.java`          | `TouchSurfaceView.swift`                     |
| `AboutActivity.java`           | `AboutViewController.swift`                  |
| `CsoundOboe` (csnd.jar)        | `CsoundObj` (Headers/ + CsoundiOS.xcframework) |
| `res/raw/etherpad.csd`         | `Resources/etherpad.csd` (byte-identical)    |
| `res/menu/*.xml` popups        | `UIMenu` on toolbar `UIBarButtonItem`s       |
| `jniLibs/*.so` native libs     | `CsoundiOS.xcframework` universal binary     |
| `SetControlChannel()`          | `getInputChannelPtr()` → write `float*`      |
| `InputMessage()`               | `sendScore()`                                |
| Touch ID tracking (manual)     | `UITouch` identity (free)                    |

## Architecture deep dive

See [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) for the full
walk-through of how the synth works (instruments, channels, the touch
data path). The Android-specific details there apply equally to iOS —
the CSD is the same file.

See [../docs/IOS_PORT.md](../docs/IOS_PORT.md) for the two-path
analysis of porting strategies (this is Path A — Csound port; Path B
would be an AudioKit rewrite).

## License

GPL-3.0 — same as the Android version. See [../gpl-3.0.txt](../gpl-3.0.txt).
