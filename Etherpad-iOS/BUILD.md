# Building Etherpad for iOS

> Walkthrough from a clean clone of the repo to a `.app` running on an
> iPhone or iPad. Last verified end-to-end on **2026-05-22** with
> Xcode 16.5 (iPhoneOS 26.5 SDK), iPhone 17, Csound iOS 7.0.0-beta.16.

The repo ships with the Csound iOS xcframeworks committed (~12 MB), so
you don't need to download anything separately. Clone, open, run.

---

## Prerequisites

| Tool                  | Version | How                                                       |
|-----------------------|---------|-----------------------------------------------------------|
| **Xcode**             | 15.0+   | Mac App Store                                             |
| **macOS**             | 13+     | required by recent Xcode                                  |
| **An iPhone or iPad** | iOS 15+ | physical device (simulator works for build, not signing)  |
| **Apple ID**          | any     | free tier installs to your device for 7 days; paid Developer Program ($99/yr) lasts a year and unlocks TestFlight |

You do **not** need: XcodeGen, CMake, Homebrew, the Csound source repo.

---

## Step 1 — Clone

```sh
git clone https://github.com/HumbleBee14/Etherpad.git
cd Etherpad
```

---

## Step 2 — Open in Xcode

```sh
open Etherpad-iOS/Etherpad.xcodeproj
```

Both `CsoundiOS.xcframework` and `libSndfileiOS.xcframework` are already
referenced by the project. The patched `CsoundObj.h/.m` and
`CsoundMIDI.h/.m` shim sources live in `Etherpad-iOS/Headers/` and are
already on the compile sources list.

---

## Step 3 — Configure code signing

1. Etherpad target → **Signing & Capabilities** tab.
2. Check **"Automatically manage signing"**.
3. Pick your Apple ID under **Team**.
4. If you get "Bundle identifier is taken", change **Bundle Identifier**
   from `com.humblebee.etherpad` to something unique like
   `com.<yourname>.etherpad`.

---

## Step 4 — Pick your device and run

1. Plug iPhone/iPad in via USB. Trust the computer if prompted.
2. On the device: **Settings → Privacy & Security → Developer Mode → On**
   (you may need to restart the device once).
3. In Xcode's top toolbar, click the device picker → select your device
   under "iOS Device".
4. Press **⌘R**.
5. First-time only: the app will install but fail to launch with
   "Untrusted Developer". On the device,
   **Settings → General → VPN & Device Management → [your Apple ID] → Trust**.
   Then press ⌘R again.

Touching the screen plays notes. If it doesn't, see Troubleshooting.

---

## CLI builds (optional)

You can build from the command line without opening Xcode:

```sh
cd Etherpad-iOS
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
    -project Etherpad.xcodeproj \
    -scheme Etherpad \
    -destination 'generic/platform=iOS' \
    -configuration Debug \
    build
```

Useful for CI. `xcodebuild` cannot deploy to a device — for that you
still need Xcode + a USB-connected phone.

---

## Updating the Csound framework

If you ever need to update Csound iOS (e.g. to a new beta):

1. Download the new `csound-ios-X.Y.Z.zip` from
   <https://github.com/csound/csound/releases>.
2. Unzip and replace `Etherpad-iOS/CsoundiOS.xcframework` and
   `Etherpad-iOS/libSndfileiOS.xcframework` in the repo.
3. Check whether the `CsoundObj.h/.m` shim in `Etherpad-iOS/Headers/`
   still compiles against the new headers. The currently shipped copies
   are patched for Csound 7:
   - `CsoundObj.h` — removed `csoundGetOutputBufferSize` forward decl.
   - `CsoundObj.m` — uses `csoundGetKsmps` + a `.playback` audio-session fix.
4. Rebuild and commit.

---

## Troubleshooting

### Symptom: silent, no errors, yellow circles draw fine
Stub `CsoundObj` is being used instead of the real one.
- Confirm `Etherpad-iOS/CsoundiOS.xcframework/` exists on disk (it
  should, after a clean clone).
- Xcode → target → General → Embedded Content lists both frameworks
  with **"Embed & Sign"**.
- If console shows `[CsoundObj STUB] ...` per touch: clean build folder
  (**⇧⌘K**) and rebuild.

### Symptom: crash on launch with `dyld: Library not loaded`
Frameworks linked but not embedded. Xcode → target → General → Embedded
Content → set both to **"Embed & Sign"**.

### Symptom: `EXC_BAD_ACCESS` in `csoundGetChannelPtr`
Pull latest `main` — current `CsoundEngine.swift` waits for
`csoundObjStarted:` before binding channels.

### Symptom: linker error `Undefined symbol: _vDSP_*`
`Accelerate.framework` not linked. Target → Build Settings → search
`OTHER_LDFLAGS` → set to `-lc++ -framework Accelerate`.

### Symptom: build fails with "no signing certificate"
Step 3 not done.

### Symptom: app installs but "Untrusted Developer" on launch
First-time only — trust your developer profile on the device. See Step 4.
