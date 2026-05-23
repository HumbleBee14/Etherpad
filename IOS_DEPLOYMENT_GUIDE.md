# iOS App Store Deployment Guide

## 1. GitHub Secrets Setup

Add these secrets to your GitHub repository: `Settings → Secrets and variables → Actions`

### Required Secrets

**`APPLE_ID`**
- Your Apple ID email (e.g., `your-email@apple.com`)
- This is the account associated with your Apple Developer Account

**`APPLE_ID_PASSWORD`**
- App-specific password (NOT your main Apple ID password)
- Generate at: https://appleid.apple.com → Security → App-specific passwords
- Create one with name like "GitHub Actions"

**`APPLE_TEAM_ID`**
- Your Apple Team ID (10-character code)
- Find it at: https://developer.apple.com/account → Membership
- It looks like: `XXXXXXXXXX`

**`SIGNING_CERTIFICATE_P12_BASE64`** (optional, for manual signing)
- If automatic signing fails, export your Apple Distribution certificate as `.p12`
- Encode as base64 and add as a secret
- `base64 -i certificate.p12 > cert.b64`

**`SIGNING_CERTIFICATE_PASSWORD`** (optional)
- Password for the `.p12` file (if using manual signing)

---

## 2. Configure App in Apple Developer Account

### Create App ID
1. Go to https://developer.apple.com/account/resources/identifiers
2. Click "+" → App IDs
3. Select "App"
4. Name: "Etherpad"
5. Bundle ID: `com.humblebee.etherpad` (must match your Xcode project)
6. Capabilities: Audio (already in your Info.plist)
7. Click "Register"

### Create Provisioning Profile
1. Go to Provisioning Profiles
2. Click "+"
3. Select "App Store"
4. Select your App ID (`com.humblebee.etherpad`)
5. Select your Apple Distribution certificate
6. Name: "Etherpad App Store"
7. Download and open in Xcode (Xcode will import automatically)

### Create App Store Listing
1. Go to https://appstoreconnect.apple.com
2. Click "My Apps" → "+"
3. Select "New App"
   - Platform: iOS
   - Name: "Etherpad"
   - Primary Language: English
   - Bundle ID: `com.humblebee.etherpad`
   - SKU: `com.humblebee.etherpad.app` (any unique value)
   - User Access: None (yours alone)
4. Click "Create"

---

## 3. Fill App Store Metadata

In App Store Connect, fill in **all** required sections:

### Information Tab
- **App Category**: Music or Utilities
- **Subtitle** (optional): "Interactive touch synthesis"
- **Description**: 
  ```
  Etherpad is an interactive music synthesis app powered by Csound. 
  Touch the surface to create evolving soundscapes with visual feedback. 
  Use effects, change instruments, and explore generative music creation.
  ```

### Pricing & Availability
- **Pricing Tier**: Free
- **Availability**: All countries/regions (or select specific ones)

### App Privacy
- Go to "Privacy" section
- Click "Manage privacy practices"
- Answer privacy questions (you likely don't collect data):
  - Health & Fitness: No
  - Contacts: No
  - User ID: No
  - etc.

---

## 4. Screenshots & Artwork

### App Icon (1024×1024)
- Already in your project: `Assets.xcassets` → AppIcon
- Verify: 1024×1024 PNG with no transparency borders

### Screenshots Required
For each device size (generate from simulator):

**iPhone (5.5" displays)**
- 1242×2208 or 1284×2778 pixels
- Show: Main touch surface, effects menu, about screen
- Create at least 2-3 screenshots per device type

**iPad (12.9" displays)**
- 2048×2732 pixels
- Show landscape orientation (your app's main mode)

**How to Generate:**
```bash
# Run app in simulator
open -a Simulator

# Take screenshots in Xcode: Device → Screenshot
# Or press Cmd+S in the simulator

# Crop to exact sizes in Preview or ImageMagick
convert screenshot.png -resize 1242x2208 screenshot-iphone.png
```

---

## 5. GitHub Actions Workflow

### Trigger the Build

**Option A: Push to main (automatic)**
```bash
git add .
git commit -m "Prepare for App Store submission"
git push origin main
```
Workflow runs automatically when iOS folder changes.

**Option B: Manual trigger**
1. Go to GitHub → Actions → "iOS Build & Release"
2. Click "Run workflow"
3. Choose branch: `main`
4. Click "Run workflow"

### Monitor Build

1. Go to GitHub → Actions tab
2. Click the running workflow
3. Watch logs in real-time
4. When complete: Click job → Download artifacts

---

## 6. Upload to App Store Connect

### Using Xcode
1. Download the `Etherpad.ipa` artifact from GitHub Actions
2. Open Xcode
3. Go to Window → Organizer
4. Select your app in the left sidebar
5. Click "Upload App"
6. Select the IPA file
7. Follow prompts to upload

### Using Transporter App
1. Download Transporter from Mac App Store
2. Download the IPA artifact
3. Open Transporter
4. Drag & drop the IPA
5. Click "Deliver"
6. Verify and submit

---

## 7. Submit for Review

In App Store Connect:

1. Go to your app → Pricing & Availability
2. Verify all metadata is complete
3. Go to "Version Information"
4. Check all required fields have green checkmarks
5. Scroll to bottom → Click "Submit for Review"
6. Answer questionnaire:
   - Does your app use cryptography? No
   - Does your app allow users to create accounts? No
   - Does your app contain unfiltered internet access? No
   - etc.
7. Confirm and submit

**Review typically takes 24-48 hours.**

---

## 8. After Approval

Once approved:
- App appears in App Store automatically
- Users can download for free
- You can update anytime (submit new version)

---

## Troubleshooting

### "Failed to create archive"
- Check provisioning profile is installed
- Verify bundle ID matches App ID
- Run: `xcodebuild -scheme Etherpad -showBuildSettings | grep PRODUCT_BUNDLE_IDENTIFIER`

### "No provisioning profiles found"
- Run workflow with `workflow_dispatch` (manual trigger)
- Xcode will prompt to create/select provisioning profile
- Commit the `.pbxproj` changes

### "Code signing failed"
- Verify APPLE_TEAM_ID in GitHub secrets
- Check certificate is "Apple Distribution" (not "Apple Development")
- Regenerate App-Specific Password if it's been a while

### "Invalid export plist"
- Ensure `exportOptions.plist` is in `EtherSurface-iOS/` directory
- Update `TEAM_ID` in the file to match your actual team ID

---

## Files Reference

- **Workflow**: `.github/workflows/ios-build-release.yml`
- **Export Config**: `EtherSurface-iOS/exportOptions.plist`
- **Build Output**: `EtherSurface-iOS/build/` (after workflow runs)
- **Version Info**: `EtherSurface-iOS/Etherpad/Info.plist`
  - `CFBundleShortVersionString`: User-facing version (1.0, 1.1, etc.)
  - `CFBundleVersion`: Build number (1, 2, 3, etc.)

---

## Quick Version Bump Before Next Release

When ready to release an update:

1. Edit `EtherSurface-iOS/Etherpad/Info.plist`:
   ```xml
   <key>CFBundleShortVersionString</key>
   <string>1.1</string>  <!-- e.g., 1.0 → 1.1 -->
   <key>CFBundleVersion</key>
   <string>2</string>    <!-- increment by 1 -->
   ```

2. Commit and push:
   ```bash
   git add EtherSurface-iOS/Etherpad/Info.plist
   git commit -m "Bump version to 1.1 (build 2)"
   git push origin main
   ```

3. Workflow runs automatically
4. Download IPA and upload to App Store Connect as new version
