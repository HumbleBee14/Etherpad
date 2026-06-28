# Notices and Attributions

Etherpad builds on the work of others. This file credits those works and their
licenses.

## Original concept — EtherSurface

Etherpad is a modern rewrite inspired by **EtherSurface**, created by
[**Paul Batchelor**](https://paulbatchelor.github.io/about/) in 2014, originally released under the GNU General Public
License v3. The synth definition (`etherpad.csd`) derives from Paul's original
work and is used here **with his explicit permission to rewrite and redistribute**, including distribution through the Apple App Store and Google Play.

- Original author: [Paul Batchelor](https://paulbatchelor.github.io/about/)
- Original `etherpad.csd` borrows from the Csound Android "MultiTouchXY" example
  by Steven Yi and Victor Lazzarini (2011).

With thanks to Paul for EtherSurface and for permission to carry the idea forward on Apple and Android.

### Source Code

The Etherpad **application sources** (Swift / UIKit / AppKit on Apple platforms;
Kotlin / Jetpack Compose on Android) are **new implementations** by
**[Dinesh](https://dineshy.com) (HumbleBee)** — including iOS, iPadOS, macOS,
and the iPad AUv3 extension, plus the Android app in Kotlin, building on Paul's original app with new platforms and features.

## Sound engine — Csound

Audio synthesis is powered by **Csound**, licensed under the
**GNU Lesser General Public License v2.1 (LGPL-2.1)**.

- Project: https://www.csound.com
- Authors: Barry Vercoe, Victor Lazzarini, and the Csound community
- License: https://github.com/csound/csound/blob/master/COPYING

The Csound libraries are dynamically linked / loaded and are redistributed in
their unmodified form under the terms of the LGPL-2.1.



