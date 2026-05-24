# Etherpad

An expressive multi-touch synthesizer for iPhone, iPad, and Android. Touch anywhere to make sound — every finger is an independent voice, driven by a professional [Csound](https://www.csound.com) synthesis engine. Slide, hold, lift; the music follows your gesture in real time.

No setup, no MIDI, no music theory required. Open and play.

<p align="center">
  <img src="EtherSurface-Android-v2/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" width="120" alt="Etherpad" />
</p>

## Get the app

- **Google Play (Android)** — *(Under review)* — [PlayStore](https://play.google.com/store/apps/details?id=com.humblebee.etherpad)
- **App Store (iOS / iPadOS)** — *(Under review)*

## Features

- **Multi-touch synthesis** — every finger plays its own voice
- **5 sound modes** — from lush pads to gritty leads
- **12 musical scales** — Major, Minor, Pentatonic, Blues, Whole-Tone, Chromatic, Octatonic, Bohlen-Pierce, Flamenco, two Overtone Series, and the original Etherpad default
- **Adjustable key, octave, and grid size** (4–14 notes per row)
- **Optional visual effects** — ripples, finger trails, intensity rings, pitch-column glow
- **iPad split-screen mode** — play two independent synths side-by-side on iPad
- **Low-latency audio** — optimized for live performance


## Repository layout

This repo is open source and contains three implementations sharing the same `etherpad.csd` synth definition:

- **[EtherSurface-iOS](EtherSurface-iOS/)** — iPhone & iPad app. Swift + UIKit, Csound 6 framework. See [`BUILD.md`](EtherSurface-iOS/BUILD.md) for the Csound framework setup.
- **[EtherSurface-Android](EtherSurface-Android-v2/)** — Android app. Kotlin + Jetpack Compose UI, with a small C++ engine driving Csound through Oboe. See its [README](EtherSurface-Android-v2/README.md) for build instructions.

The three apps share the Csound score (`etherpad.csd`) and the same sonic identity but otherwise have nothing in common code-wise — each is idiomatic to its platform.

## Credits

Etherpad is inspired by **EtherSurface**, an Android app written by [**Paul Batchelor**](https://paulbatchelor.github.io/about/) in 2014.

- Sound engine — [Csound](https://www.csound.com) by Barry Vercoe, Victor Lazzarini, et al.

## License

See [LICENSE](LICENSE) for details.
