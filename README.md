<p align="center">
  <img src="Etherpad-Android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" width="120" alt="Etherpad" />
</p>

<h1 align="center">Etherpad</h1>

<p align="center"><b>An expressive multi-touch synthesizer for iPhone, iPad, Mac, and Android.</b></p>

<p align="center">
  Touch anywhere to make sound — every finger is an independent voice, driven by a professional
  <a href="https://www.csound.com">Csound</a> engine. Slide, hold, lift; the music follows your gesture
  in real time. No setup, no MIDI, no music theory required. Open and play.
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/etherpad/id6772439909"><img src="https://img.shields.io/badge/App_Store-iOS%20%7C%20iPadOS%20%7C%20macOS-0D96F6?logo=apple&logoColor=white" alt="Download on the App Store" /></a>
  <a href="https://play.google.com/store/apps/details?id=com.humblebee.etherpad"><img src="https://img.shields.io/badge/Google_Play-Android-34A853?logo=googleplay&logoColor=white" alt="Get it on Google Play" /></a>
  <a href="NOTICE.md"><img src="https://img.shields.io/badge/license-GPLv3-3DA639" alt="License: GPLv3" /></a>
</p>

## Features

- **Multi-touch synthesis** — every finger plays its own voice
- **5 sound modes** — from lush pads to gritty leads
- **12 musical scales** — Major, Minor, Pentatonic, Blues, Whole-Tone, Chromatic, Octatonic, Bohlen-Pierce, Flamenco, two Overtone Series, and the original Etherpad default
- **Adjustable key, octave, and grid size** (4–14 notes per row)
- **Optional visual effects** — ripples, finger trails, intensity rings, pitch-column glow
- **iPad split-screen mode** — play two independent synths side-by-side on iPad
- **Low-latency audio** — optimized for live performance


## Repository layout

This repo is open source and contains Apple (iOS + macOS) and Android implementations sharing the same `etherpad.csd` synth definition:

- **[Etherpad-Apple](Etherpad-Apple/)** — iPhone, iPad, and native macOS apps. Swift + UIKit/AppKit, separate Csound builds per platform. See [`BUILD.md`](Etherpad-Apple/BUILD.md) for setup.
- **[Etherpad-Android](Etherpad-Android/)** — Android app. Kotlin + Jetpack Compose UI, with a small C++ engine driving Csound through Oboe. See its [README](Etherpad-Android/README.md) for build instructions.

The three apps share the Csound score (`etherpad.csd`) and the same sonic identity but otherwise have nothing in common code-wise — each is idiomatic to its platform.

## Contributing

Contributions and ideas are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Etherpad is inspired by **EtherSurface**, an Android app written by [**Paul Batchelor**](https://paulbatchelor.github.io/about/) in 2014 (Original Creator). [Modernized and Upgraded]

- Sound engine — [Csound](https://www.csound.com) by Barry Vercoe, Victor Lazzarini, et al.

## License & attributions

Application code © Dinesh (HumbleBee). Etherpad is a rewrite of Paul Batchelor's
GPLv3 **EtherSurface**, used with his permission, and is powered by
[Csound](https://www.csound.com) (LGPL-2.1).

See [NOTICE.md](NOTICE.md) for full credits and license details.
