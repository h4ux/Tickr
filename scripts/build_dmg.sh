#!/bin/bash
# Builds Tickr.app and packages it into a styled DMG for distribution.
# Usage: ./scripts/build_dmg.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/Tickr.app/Contents"
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

cd "$PROJECT_DIR"

# Eject any leftover volumes
hdiutil detach "/Volumes/Tickr" 2>/dev/null || true

echo "==> Generating app icons..."
swift "$SCRIPT_DIR/generate_icon.swift" "$PROJECT_DIR"

echo "==> Creating .icns file..."
swift "$SCRIPT_DIR/create_icns.swift" "$PROJECT_DIR"
iconutil -c icns "$BUILD_DIR/Tickr.iconset" -o "$BUILD_DIR/Tickr.icns"
rm -rf "$BUILD_DIR/Tickr.iconset"

echo "==> Generating DMG background..."
swift "$SCRIPT_DIR/generate_dmg_background.swift" "$PROJECT_DIR"

echo "==> Compiling Tickr (Release)..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"

swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macos13.0 \
    -O \
    -whole-module-optimization \
    -o "$APP_DIR/MacOS/Tickr" \
    Tickr/TickrApp.swift \
    Tickr/Models/StockData.swift \
    Tickr/Models/AppSettings.swift \
    Tickr/Services/StockService.swift \
    Tickr/Services/AnalyticsService.swift \
    Tickr/Services/SuggestionsService.swift \
    Tickr/Services/UpdateService.swift \
    Tickr/Services/LicenseService.swift \
    Tickr/Services/AdService.swift \
    Tickr/Services/LaunchAtLoginService.swift \
    Tickr/Services/NotificationService.swift \
    Tickr/Services/Secrets.swift \
    Tickr/Views/StatusBarController.swift \
    Tickr/Views/TickerDropdownView.swift \
    Tickr/Views/SettingsView.swift

# Assemble app bundle
cp Tickr/Info.plist "$APP_DIR/Info.plist"
echo -n "APPL????" > "$APP_DIR/PkgInfo"
cp "$BUILD_DIR/Tickr.icns" "$APP_DIR/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_DIR/Info.plist"

codesign --force --deep --sign - "$BUILD_DIR/Tickr.app"
echo "==> App built: $BUILD_DIR/Tickr.app"

echo "==> Creating styled DMG..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_TEMP="$BUILD_DIR/Tickr_temp.dmg"
DMG_OUTPUT="$BUILD_DIR/Tickr.dmg"

rm -rf "$DMG_STAGING" "$DMG_TEMP" "$DMG_OUTPUT"
mkdir -p "$DMG_STAGING/.background"

cp -R "$BUILD_DIR/Tickr.app" "$DMG_STAGING/Tickr.app"
ln -s /Applications "$DMG_STAGING/Applications"
cp "$BUILD_DIR/dmg_background.png" "$DMG_STAGING/.background/background.png"

hdiutil create -srcfolder "$DMG_STAGING" -volname "Tickr" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW "$DMG_TEMP" >/dev/null

DEVICE_LINE=$(hdiutil attach -readwrite -noverify "$DMG_TEMP" | tail -1)
MOUNT_POINT=$(echo "$DEVICE_LINE" | sed 's/.*\(\/Volumes\/.*\)/\1/' | xargs)
VOLUME_NAME=$(basename "$MOUNT_POINT")

# Set Finder window appearance
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 700, 500}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        set position of item "Tickr.app" of container window to {170, 200}
        set position of item "Applications" of container window to {430, 200}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Set volume icon
cp "$BUILD_DIR/Tickr.icns" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT" 2>/dev/null || true

sync
hdiutil detach "$MOUNT_POINT" >/dev/null

# Compress to final DMG
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT" >/dev/null

rm -f "$DMG_TEMP"
rm -rf "$DMG_STAGING"

echo ""
echo "==> DMG created: $DMG_OUTPUT"
echo "    Size: $(du -sh "$DMG_OUTPUT" | cut -f1)"
echo ""
echo "Open the DMG and drag Tickr to Applications to install."
