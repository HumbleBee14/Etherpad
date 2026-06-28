# Building Etherpad for iOS and macOS

> Walkthrough from a clean clone to a running app. Csound frameworks are
> vendored in `Frameworks/` — no separate download step.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| **Xcode** | 15.0+ | Mac App Store |
| **macOS** | 13+ | Host for Xcode and the macOS app |
| **iPhone or iPad** | iOS 17+ | Optional; Simulator works without signing |

You do **not** need: XcodeGen, CMake, Homebrew, or the Csound source repo.

---

## Step 1 — Clone

```sh
git clone https://github.com/HumbleBee14/Etherpad.git
cd Etherpad
```

---

## Step 2 — Open in Xcode

```sh
open Etherpad-Apple/Etherpad.xcodeproj
```

Pick a scheme from the toolbar:

- **Etherpad-iOS** — iPhone / iPad (embeds the AU extension)
- **Etherpad-AU** — AUv3 extension only (CI / extension debugging)
- **Etherpad-macOS** — Mac

Frameworks under `Frameworks/` are already linked. iOS shim sources live in
`iOS/Headers/`.

---

## iOS — signing and run

1. **Etherpad-iOS** target → **Signing & Capabilities** → enable automatic signing, pick your Team.
2. Select a Simulator or a connected device.
3. **⌘R**.

First device install may require trusting the developer profile under
**Settings → General → VPN & Device Management**.

---

## macOS — run

1. **Etherpad-macOS** target → **Signing & Capabilities** (automatic signing is fine for local runs).
2. Scheme **Etherpad-macOS**, destination **My Mac**.
3. **⌘R**.

Normal mode: click-drag to play one voice. **⌥M** enters Multitouch trackpad
mode; **Esc** exits.

---

## iPad AUv3 — GarageBand / AUM

1. Build and run **Etherpad-iOS** on an iPad (or install via TestFlight).
2. In **GarageBand** (or **AUM**), add an instrument track and browse AU instruments.
3. Select **HumbleBee: Etherpad** — the full touch pad and patch toolbar appear in the plugin UI.

The extension is embedded in the main app; hosts discover it after Etherpad is installed once.
Shared synth logic lives in `iOS/Shared/`; the AU uses `HostCsoundEngine` for host-pull audio.

---

## CLI builds

```sh
cd Etherpad-Apple

# iOS (Simulator)
xcodebuild -project Etherpad.xcodeproj -scheme Etherpad-iOS \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

# AU extension (Simulator)
xcodebuild -project Etherpad.xcodeproj -scheme Etherpad-AU \
  -sdk iphonesimulator -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

# macOS
xcodebuild -project Etherpad.xcodeproj -scheme Etherpad-macOS \
  -destination 'platform=macOS' -configuration Release build
```

---

## Updating Csound

**iOS:** replace `Frameworks/CsoundiOS.xcframework` and
`Frameworks/libSndfileiOS.xcframework` from a
[csound release](https://github.com/csound/csound/releases). Re-check
`iOS/Headers/CsoundObj.{h,m}` against the new headers.

**macOS:** replace `Frameworks/CsoundLib64.framework` from the official macOS
DMG. Re-run the macOS target if embed/sign settings change.

---

## Troubleshooting (iOS)

### Silent output, circles draw fine
- Confirm `Frameworks/CsoundiOS.xcframework/` exists after clone.
- Both iOS xcframeworks must be **Embed & Sign** on the Etherpad-iOS target.
- Clean build folder (**⇧⌘K**) if console shows `[CsoundObj STUB]`.

### `dyld: Library not loaded`
Frameworks linked but not embedded — set **Embed & Sign** on both xcframeworks.

### `Undefined symbol: _vDSP_*`
Add `-framework Accelerate` to **Other Linker Flags** (should already be set).

---

## macOS target setup (maintainers)

To regenerate the macOS target after adding Swift files or an Xcode upgrade:

```sh
cd Etherpad-Apple/macOS/project-setup
bundle install
bundle exec ruby setup_macos_target.rb
```

This script only touches the **Etherpad-macOS** target.
