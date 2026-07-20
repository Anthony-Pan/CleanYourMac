#!/usr/bin/env bash
#
# Package CleanYourMac into a signed .app bundle.
#
# Usage:
#   ./package.sh                                  # build unsigned .app
#   IDENTITY="Developer ID Application: NAME (TEAMID)" ./package.sh   # + codesign
#
# Env overrides: BUNDLE_ID, VERSION, BUILD, IDENTITY
#
# Notarization is intentionally NOT run here (it uploads to Apple and needs your
# credentials). The exact commands are printed at the end for you to run.

set -euo pipefail

APP_NAME="CleanYourMac"
EXECUTABLE="CleanYourMacApp"
BUNDLE_ID="${BUNDLE_ID:-com.anthonypan.CleanYourMac}"
VERSION="${VERSION:-1.1.0}"
BUILD="${BUILD:-1}"
IDENTITY="${IDENTITY:-}"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building release binaries (universal)"
if swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE" &&
   swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64 --product snapshot; then
    BINDIR="$ROOT/.build/apple/Products/Release"
else
    echo "    (universal build failed — falling back to native arch)"
    swift build --package-path "$ROOT" -c release --product "$EXECUTABLE"
    swift build --package-path "$ROOT" -c release --product snapshot
    BINDIR="$ROOT/.build/release"
fi
BIN="$BINDIR/$EXECUTABLE"
SNAP="$BINDIR/snapshot"

echo "==> Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"

ICONSET="$DIST/AppIcon.iconset"
MASTER="$DIST/icon_1024.png"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
if [[ -f "$ROOT/Assets/icon_1024.png" ]]; then
    echo "==> Using custom icon (masked to the macOS icon shape)"
    swift "$ROOT/installer/render_assets.swift" appicon "$ROOT/Assets/icon_1024.png" "$MASTER"
else
    echo "==> Generating app icon"
    "$SNAP" icon "$MASTER"
fi
# iconutil expects these exact names/sizes.
gen() { sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Open source. Files are moved to the Trash, never permanently deleted.</string>
</dict>
</plist>
PLIST

if [[ -n "$IDENTITY" ]]; then
    echo "==> Codesigning with hardened runtime: $IDENTITY"
    codesign --force --options runtime --timestamp \
        --sign "$IDENTITY" "$APP"
    echo "==> Verifying signature"
    codesign --verify --strict --verbose=2 "$APP"
    spctl -a -vvv -t exec "$APP" || echo "  (Gatekeeper will pass only after notarization — expected.)"
else
    echo "==> Ad-hoc signing (no IDENTITY set)"
    codesign --force --sign - "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    echo "    Note: ad-hoc signed. Gatekeeper-friendly distribution needs a Developer ID."
fi

echo ""
echo "✅ Built: $APP"
echo ""
if [[ -n "$IDENTITY" ]]; then
cat <<NOTARIZE
Next: notarize (run these yourself — needs your Apple credentials):

  # one-time: store an app-specific password (from appleid.apple.com) as a profile
  xcrun notarytool store-credentials CYM_NOTARY \\
      --apple-id "YOUR_APPLE_ID" --team-id "YOUR_TEAM_ID"

  ditto -c -k --keepParent "$APP" "$DIST/$APP_NAME.zip"
  xcrun notarytool submit "$DIST/$APP_NAME.zip" --keychain-profile CYM_NOTARY --wait
  xcrun stapler staple "$APP"
NOTARIZE
else
cat <<UNSIGNED
To sign, re-run with your Developer ID:

  IDENTITY="Developer ID Application: Your Name (TEAMID)" ./package.sh

Find your identity string with:
  security find-identity -v -p codesigning
UNSIGNED
fi
