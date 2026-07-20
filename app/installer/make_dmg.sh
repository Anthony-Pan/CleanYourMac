#!/usr/bin/env bash
#
# Build a polished drag-to-install DMG: brand background, Applications symlink,
# fixed icon layout, custom volume icon.
#
# Usage: make_dmg.sh <path/to/CleanYourMac.app> <version> <out.dmg>
#
# Finder layout comes from dmg_template.DS_Store. If the template is missing,
# the layout is set once via Finder scripting (needs a logged-in session) and
# the resulting .DS_Store is saved back next to this script — commit it so
# later builds are deterministic and headless.

set -euo pipefail

APP="${1:?usage: make_dmg.sh <app> <version> <out.dmg>}"
VERSION="${2:?usage: make_dmg.sh <app> <version> <out.dmg>}"
OUT="${3:?usage: make_dmg.sh <app> <version> <out.dmg>}"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIST="$(cd "$(dirname "$OUT")" && pwd)"
OUT="$DIST/$(basename "$OUT")"
VOLNAME="CleanYourMac"
STAGE="$DIST/dmg-stage"
RW="$DIST/dmg-rw.dmg"
TEMPLATE="$HERE/dmg_template.DS_Store"
MOUNT="/Volumes/$VOLNAME"

echo "==> Rendering DMG background"
swift "$HERE/render_assets.swift" dmg "$DIST/dmg_background.png"

echo "==> Staging DMG contents"
rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
ditto --noextattr --noacl --noqtn "$APP" "$STAGE/CleanYourMac.app"
ln -s /Applications "$STAGE/Applications"
cp "$DIST/dmg_background.png" "$STAGE/.background/background.png"
if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
fi
if [[ -f "$TEMPLATE" ]]; then
    cp "$TEMPLATE" "$STAGE/.DS_Store"
fi

echo "==> Creating writable image"
rm -f "$RW" "$OUT"
if [[ -d "$MOUNT" ]]; then
    hdiutil detach "$MOUNT" -quiet || true
fi
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
hdiutil attach "$RW" >/dev/null
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true' EXIT

if [[ ! -f "$TEMPLATE" ]]; then
    echo "==> Styling Finder window (first run — saving reusable template)"
    osascript <<OSA
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"
        set position of item "CleanYourMac.app" of container window to {165, 205}
        set position of item "Applications" of container window to {495, 205}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
    sync
    sleep 2
    if [[ -f "$MOUNT/.DS_Store" ]]; then
        cp "$MOUNT/.DS_Store" "$TEMPLATE"
        echo "    Saved layout template: $TEMPLATE (commit this file)"
    else
        echo "    WARNING: Finder produced no .DS_Store — DMG will use default layout" >&2
    fi
fi

# Flag the volume root so Finder uses .VolumeIcon.icns.
SETFILE="$(xcrun -f SetFile 2>/dev/null || true)"
if [[ -n "$SETFILE" && -f "$MOUNT/.VolumeIcon.icns" ]]; then
    "$SETFILE" -a C "$MOUNT" || true
fi

sync
hdiutil detach "$MOUNT" -quiet
trap - EXIT

echo "==> Compressing"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"
rm -rf "$STAGE"

echo "✅ DMG: $OUT"
