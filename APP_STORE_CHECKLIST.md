# App Store Submission Checklist

## Before You Start
- [ ] Apple Developer Account is active
- [ ] GitHub account is ready
- [ ] You have Xcode installed

---

## Step 1: GitHub Secrets Setup (5 min)

Go to GitHub repo → **Settings → Secrets and variables → Actions**

Add these 3 secrets:

- [ ] `APPLE_ID` = your Apple email
- [ ] `APPLE_ID_PASSWORD` = app-specific password from appleid.apple.com
- [ ] `APPLE_TEAM_ID` = 10-char team ID from developer.apple.com

**How to get app-specific password:**
1. Go to https://appleid.apple.com
2. Sign in
3. Security → App-specific passwords
4. Generate one for "GitHub Actions"
5. Copy the password (one-time display!)

**How to get Team ID:**
1. Go to https://developer.apple.com/account
2. Click "Membership"
3. Find "Team ID" on the right side

---

## Step 2: Create App in Apple Developer (10 min)

### A. Create App ID
1. https://developer.apple.com/account/resources/identifiers
2. Click "+"
3. App IDs → App
4. Name: `Etherpad`
5. Bundle ID: `com.humblebee.etherpad`
6. Capabilities: Check "Audio"
7. Register

- [ ] App ID created: `com.humblebee.etherpad`

### B. Create Provisioning Profile
1. https://developer.apple.com/account/resources/profiles
2. Click "+"
3. Select "App Store"
4. App ID: `com.humblebee.etherpad`
5. Certificate: Select your "Apple Distribution" cert
6. Name: `Etherpad App Store`
7. Download & open in Xcode

- [ ] Provisioning Profile created
- [ ] Profile installed in Xcode

---

## Step 3: Create App Store Listing (5 min)

1. https://appstoreconnect.apple.com
2. Click "My Apps" → "+"
3. **New App**:
   - Platform: iOS
   - Name: `Etherpad`
   - Primary Language: English
   - Bundle ID: `com.humblebee.etherpad` ← Must match!
   - SKU: `com.humblebee.etherpad` (can be anything unique)

- [ ] App created in App Store Connect

---

## Step 4: Fill App Metadata (15 min)

In App Store Connect → Your App:

### Information
- [ ] Category: Music (or Utilities)
- [ ] Description filled in (~160 chars):
  ```
  Etherpad is an interactive music synthesis app powered by Csound. 
  Touch the surface to create evolving soundscapes with visual feedback.
  ```

### Pricing & Availability
- [ ] Pricing Tier: **Free**
- [ ] Regions: All available

### App Privacy
- [ ] Go to "Privacy" tab
- [ ] Click "Manage privacy practices"
- [ ] Answer all questions (likely: No data collected)

---

## Step 5: Add Screenshots (20 min)

Generate from simulator:

**iPhone 6.7" (for all iPhones)**
- [ ] Screenshot 1: Touch surface (main view)
- [ ] Screenshot 2: Effects menu
- [ ] Screenshot 3: About screen
- Size: 1242×2778 PNG

**iPad 12.9" (landscape)**
- [ ] Screenshot 1: Touch surface in landscape
- [ ] Screenshot 2: Effects/controls
- Size: 2048×2732 PNG

**How to capture:**
```bash
# 1. Run simulator
open -a Simulator

# 2. In Xcode, open your app in simulator
# Select simulator device: iPhone 15 Pro Max or iPad

# 3. Take screenshot:
# Simulator → Device → Screenshot
# Or: Cmd+S

# 4. Crop in Preview if needed
# Open Preview → Tools → Adjust Size → 1242x2778
```

---

## Step 6: Trigger Build (2 min)

### Option A: Push changes (automatic)
```bash
cd /Users/humblebee/Documents/GitHub/EtherSurface
git add -A
git commit -m "Prepare iOS app for App Store submission"
git push origin main
```
Workflow runs automatically → Artifacts ready in 10-15 min

### Option B: Manual trigger
1. GitHub → Actions
2. "iOS Build & Release"
3. "Run workflow" → main → "Run workflow"

- [ ] Build triggered
- [ ] Build completed successfully (check Actions tab)

---

## Step 7: Download IPA (2 min)

1. GitHub → Actions → Latest workflow run
2. Scroll down → Artifacts
3. Download: `Etherpad.ipa`
4. Note the size (should be 50-100 MB)

- [ ] IPA downloaded

---

## Step 8: Upload to App Store Connect (5 min)

### Using Xcode (Recommended)
1. Xcode → Window → Organizer
2. Left sidebar → Your app
3. Click "Upload App"
4. Select the IPA you downloaded
5. Follow prompts

### Or Using Transporter (Mac App Store)
1. Download Transporter
2. Drag & drop the IPA
3. Click "Deliver"

- [ ] IPA uploaded to App Store Connect
- [ ] Status shows "Processing" → "Waiting for Review"

---

## Step 9: Submit for Review (2 min)

In App Store Connect:

1. Your app → Version
2. Scroll down → "Submit for Review"
3. Answer questions:
   - Cryptography? No
   - User accounts? No
   - Internet access? No
   - Etc.
4. Confirm and submit

- [ ] App submitted for review

**Review time: 24-48 hours typically**

---

## After Approval ✅

- [ ] App appears in App Store
- [ ] Users can download for free
- [ ] You can update anytime (new version → bump version numbers → repeat steps 6-9)

---

## Version Bumps for Future Updates

When releasing v1.1 or later:

1. Edit `EtherSurface-iOS/Etherpad/Info.plist`:
   ```xml
   <key>CFBundleShortVersionString</key>
   <string>1.1</string>  <!-- Change 1.0 to 1.1 -->
   <key>CFBundleVersion</key>
   <string>2</string>    <!-- Increment: 1 → 2 → 3 ... -->
   ```

2. Push to main → Workflow runs → Download IPA → Upload to App Store Connect as new version

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Build fails: "No provisioning profile" | Regenerate in Apple Developer portal, re-download |
| "Code signing failed" | Verify APPLE_TEAM_ID secret is correct (10 chars, no spaces) |
| IPA upload fails | Make sure bundle ID matches exactly: `com.humblebee.etherpad` |
| Screenshots won't upload | Check exact pixel sizes: 1242×2778 (iPhone), 2048×2732 (iPad) |
| Can't submit for review | All metadata fields must have green checkmarks |

---

## Help Links

- App Store Connect: https://appstoreconnect.apple.com
- Apple Developer Account: https://developer.apple.com/account
- App-specific password: https://appleid.apple.com → Security
- Xcode Organizer guide: [Apple Docs](https://help.apple.com/xcode/mac/current/#/dev8b4250b57)
- Transporter app: Mac App Store
