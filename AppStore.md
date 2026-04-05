# Publishing Tickr on the Mac App Store

A step-by-step guide to preparing, submitting, and selling Tickr on the Mac App Store.

## Prerequisites

- [ ] Apple Developer Account ($99/year) — [developer.apple.com](https://developer.apple.com/programs/)
- [ ] Xcode installed (latest stable version)
- [ ] Mac with macOS 13.0+ for building
- [ ] App icon (already included in `Tickr/Assets.xcassets/AppIcon.appiconset/`)

## Step 1: Apple Developer Setup

1. **Enroll** in the Apple Developer Program at [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/)
2. **Accept agreements** in [App Store Connect](https://appstoreconnect.apple.com/) → Agreements, Tax, and Banking
3. **Set up banking** — add your bank account and tax information for payments

## Step 2: Certificates & Provisioning

### Create a Developer ID Certificate

1. Open **Xcode → Settings → Accounts** → add your Apple ID
2. Select your team → **Manage Certificates**
3. Click **+** → **Apple Distribution** certificate
4. Also create a **Mac App Distribution** certificate and a **Mac Installer Distribution** certificate

### Create an App ID

1. Go to [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. Click **+** → **App IDs** → **App**
3. Set:
   - Description: `Tickr`
   - Bundle ID: **Explicit** → `com.tickr.app`
   - Capabilities: check **App Sandbox** and **Outgoing Connections (Client)**
4. Click **Continue** → **Register**

### Create a Provisioning Profile

1. Go to [developer.apple.com/account/resources/profiles](https://developer.apple.com/account/resources/profiles/list)
2. Click **+** → **Mac App Store** → **Mac App Distribution**
3. Select App ID: `com.tickr.app`
4. Select your **Apple Distribution** certificate
5. Name it: `Tickr Mac App Store`
6. Download and double-click to install

## Step 3: Prepare the App for App Store

### Update Info.plist

Ensure `Tickr/Info.plist` has these required fields (most are already set):

```xml
<key>CFBundleName</key>
<string>Tickr</string>
<key>CFBundleDisplayName</key>
<string>Tickr</string>
<key>CFBundleIdentifier</key>
<string>com.tickr.app</string>
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
<key>LSMinimumSystemVersion</key>
<string>13.0</string>
<key>LSUIElement</key>
<true/>
```

> **Important:** `CFBundleVersion` must be incremented for every upload to App Store Connect.

### Update Entitlements

`Tickr/Tickr.entitlements` must include:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

The App Sandbox is **required** for Mac App Store distribution.

### Remove Hardcoded Paths

Ensure no debug/test paths remain. The app already stores data in `UserDefaults` (sandboxed container), so no changes needed.

## Step 4: Build with Xcode

The App Store requires builds signed with Xcode — `swiftc` builds cannot be submitted.

1. Open `Tickr.xcodeproj` in Xcode
2. Select the **Tickr** target → **Signing & Capabilities**
3. Set:
   - Team: your Apple Developer team
   - Bundle Identifier: `com.tickr.app`
   - Signing: **Automatically manage signing** (or select your provisioning profile)
4. Ensure the entitlements file is set in **Build Settings → Code Signing Entitlements** → `Tickr/Tickr.entitlements`
5. Set **Build Settings → Code Signing Identity** → `Apple Distribution`

### Archive the App

1. Select **Product → Archive** (or Cmd+Shift+B with Archive scheme)
2. Wait for the build to complete
3. The **Organizer** window opens with your archive

## Step 5: App Store Connect — Create the App

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com/)
2. Click **My Apps** → **+** → **New App**
3. Fill in:
   - Platform: **macOS**
   - Name: `Tickr`
   - Primary Language: English (U.S.)
   - Bundle ID: `com.tickr.app`
   - SKU: `tickr-macos-1` (any unique string)
4. Click **Create**

## Step 6: App Store Listing

### App Information

- **Category:** Finance
- **Secondary Category:** Utilities (optional)
- **Content Rights:** Does not contain third-party content that requires rights
- **Age Rating:** 4+ (no objectionable content)

### Pricing

1. Go to **Pricing and Availability**
2. Set your price tier:
   - **Free** — no charge
   - **Paid** — select a price tier (e.g., Tier 1 = $0.99, Tier 3 = $2.99, Tier 5 = $4.99)
   - **Free with In-App Purchases** — if you plan to add premium features later
3. Select availability (all territories, or specific countries)

### App Store Screenshots

You need screenshots for the Mac App Store listing:

- **Required:** At least one screenshot
- **Sizes:** 1280x800, 1440x900, 2560x1600, or 2880x1800 pixels
- **Recommended:** 3-5 screenshots showing key features

Capture these from the running app:
1. Menu bar ticker
2. Dropdown with stocks and categories
3. Expanded stock with news and earnings
4. Settings window
5. Chart view

> **Tip:** Use Cmd+Shift+4 to capture specific areas, or Cmd+Shift+5 for window capture.

### Description

Suggested App Store description:

```
Tickr puts real-time stock prices in your macOS menu bar.

FEATURES
• Live stock ticker in the menu bar with customizable display
• Organize unlimited stocks into categories
• Interactive charts: 1W, 1M, YTD, 1Y, 5Y
• Latest news headlines for each stock
• Next earnings call dates
• Market cap, volume, 52-week range, sector info
• Color-coded gains (green) and losses (red)
• Configurable refresh intervals (15s to 30min)
• Sort categories by name, price, or performance
• Click any stock to open Yahoo Finance

PRIVACY
• No account required
• No personal data collected
• Optional anonymous analytics (opt-out in Settings)
• Full transparency — see exactly what's tracked

Tickr uses Yahoo Finance for stock data. Prices may be delayed up to 15 minutes depending on the exchange.
```

### Keywords

```
stocks, ticker, menu bar, finance, portfolio, watchlist, market, investing, quotes, NYSE, NASDAQ
```

### Support URL

Set this to your GitHub repo: `https://github.com/h4ux/Tickr`

### Privacy Policy URL

**Required.** Create a simple privacy policy page. You can use your GitHub repo's SECURITY.md:
`https://github.com/h4ux/Tickr/blob/main/SECURITY.md`

Or create a dedicated privacy policy page on GitHub Pages or any static hosting.

## Step 7: Upload the Build

### Option A: Upload from Xcode Organizer

1. In the Organizer (after archiving), select your archive
2. Click **Distribute App**
3. Select **App Store Connect**
4. Select **Upload**
5. Follow the prompts (signing, entitlements check)
6. Wait for upload to complete

### Option B: Upload with `xcrun altool` (command line)

```bash
# Export the archive to a .pkg
xcodebuild -exportArchive \
  -archivePath build/Tickr.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist

# Upload to App Store Connect
xcrun altool --upload-app \
  -f build/export/Tickr.pkg \
  -t macos \
  -u "your-apple-id@email.com" \
  -p "@keychain:AC_PASSWORD"
```

> **Note:** Store your app-specific password in Keychain:
> ```bash
> xcrun altool --store-password-in-keychain-item "AC_PASSWORD" \
>   -u "your-apple-id@email.com" \
>   -p "xxxx-xxxx-xxxx-xxxx"
> ```
> Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com/account/manage) → Security → App-Specific Passwords.

### Option C: Upload with Transporter

1. Download [Transporter](https://apps.apple.com/app/transporter/id1450874784) from the Mac App Store
2. Sign in with your Apple ID
3. Drag the `.pkg` file into Transporter
4. Click **Deliver**

## Step 8: Submit for Review

1. Go to **App Store Connect** → your app → **macOS** version
2. Select the uploaded build
3. Fill in:
   - **What's New:** `Initial release`
   - **Review Notes:** `Tickr is a menu bar stock ticker app. To test: launch the app, it appears in the menu bar. Click to see stocks. Open Settings to add/remove tickers.`
   - **Sign-In Required:** No
4. Click **Submit for Review**

## Step 9: Apple Review

- Review typically takes **24-48 hours** (can be longer)
- Common rejection reasons for menu bar apps:
  - **Guideline 4.0 - Design:** Ensure the app has meaningful functionality beyond a web wrapper
  - **Guideline 2.1 - Performance:** App must work reliably
  - **Guideline 5.1.1 - Data Collection:** Must have a privacy policy if collecting any data
  - **Guideline 2.4.5 - Apple Sites:** Don't scrape Apple services (we use Yahoo/Google, so this is fine)
- If rejected, read the rejection reason carefully, fix the issue, and resubmit

## Step 10: Post-Launch

### Updating the App

1. Increment `CFBundleVersion` in `Info.plist` (e.g., `1` → `2`)
2. Update `CFBundleShortVersionString` for user-facing version (e.g., `1.0.0` → `1.1.0`)
3. Archive and upload the new build
4. Create a new version in App Store Connect
5. Submit for review

### Monitoring

- **App Store Connect → Analytics:** downloads, impressions, conversion rate
- **App Store Connect → Ratings and Reviews:** respond to user reviews
- **PostHog dashboard:** app usage analytics (if configured)

## Checklist Before Submission

- [ ] Apple Developer Account active and agreements signed
- [ ] Bundle ID `com.tickr.app` registered
- [ ] App signed with Apple Distribution certificate
- [ ] App Sandbox enabled with `network.client` entitlement
- [ ] `CFBundleVersion` is unique for this upload
- [ ] No hardcoded API keys in submitted code (`Secrets.swift` uses placeholder for App Store builds)
- [ ] App icon at all required sizes (already in asset catalog)
- [ ] At least 1 screenshot uploaded to App Store Connect
- [ ] Description, keywords, category, and pricing set
- [ ] Privacy policy URL provided
- [ ] Support URL provided
- [ ] Tested on macOS 13.0+ (minimum deployment target)
- [ ] App quits cleanly, no crashes on launch
- [ ] Menu bar item appears and is functional

## Cost Summary

| Item | Cost |
|------|------|
| Apple Developer Program | $99/year |
| Apple's commission on paid apps | 30% (15% for small business < $1M revenue) |
| Free apps | No commission |

## Useful Links

- [App Store Connect](https://appstoreconnect.apple.com/)
- [Apple Developer Portal](https://developer.apple.com/account/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Human Interface Guidelines — Menu Bar Extras](https://developer.apple.com/design/human-interface-guidelines/menu-bar-extras)
- [Small Business Program](https://developer.apple.com/app-store/small-business-program/) (15% commission)
- [App Store Screenshots Specs](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)
