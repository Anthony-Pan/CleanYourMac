#!/usr/bin/env bash
#
# Build a polished drag-to-install DMG: brand background, Applications symlink,
# fixed icon layout, custom volume icon.
#
# Usage: make_dmg.sh <path/to/CleanYourMac.app> <version> <out.dmg>
#
# Finder layout comes from dmg_template.DS_Store. The template bakes in the
# volume name "CleanYourMac" and the background path .background/background.png —
# regenerate it (delete the file and re-run in a logged-in session) if either
# changes. When the template is missing, the layout is set once via Finder
# scripting and the resulting .DS_Store is saved back next to this script —
# commit it so later builds are deterministic and headless.

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

# A pre-existing volume with our name would shadow the styling path (which
# addresses the disk by name) and shift new mounts to "CleanYourMac 1".
if [[ -d "/Volumes/$VOLNAME" ]]; then
    hdiutil detach "/Volumes/$VOLNAME" -quiet || {
        echo "ERROR: a volume named '$VOLNAME' is mounted and busy — eject it and retry" >&2
        exit 1
    }
fi

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
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null

# Finder and Spotlight routinely hold fresh volumes busy for a few seconds.
detach_retry() {
    local mnt="$1" i
    for i in 1 2 3 4 5; do
        if hdiutil detach "$mnt" -quiet 2>/dev/null; then return 0; fi
        sleep 2
    done
    hdiutil detach "$mnt" -force -quiet
}

if [[ -f "$TEMPLATE" ]]; then
    # Headless path: private mountpoint, invisible to Finder/Spotlight.
    MOUNT="$DIST/dmg-mnt"
    rm -rf "$MOUNT"
    mkdir -p "$MOUNT"
    hdiutil attach "$RW" -nobrowse -mountpoint "$MOUNT" >/dev/null
else
    # First-run styling path: Finder scripting needs a browsable disk.
    MOUNT="/Volumes/$VOLNAME"
    hdiutil attach "$RW" >/dev/null
fi
trap 'detach_retry "$MOUNT" 2>/dev/null || true' EXIT

if [[ ! -f "$TEMPLATE" ]]; then
    echo "==> Styling Finder window (first run — saving reusable template)"
    # Window bounds are content 660x400 + 28pt title bar, matching the
    # background image exactly.
    osascript <<OSA
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
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
    # Finder flushes .DS_Store asynchronously — poll instead of a fixed sleep.
    DS_OK=""
    for _ in $(seq 30); do
        sync
        if [[ -f "$MOUNT/.DS_Store" ]]; then DS_OK=1; break; fi
        sleep 1
    done
    if [[ -z "$DS_OK" ]]; then
        echo "ERROR: Finder never wrote .DS_Store — refusing to ship an unstyled DMG" >&2
        exit 1
    fi
    sleep 1
    cp "$MOUNT/.DS_Store" "$TEMPLATE"
    echo "    Saved layout template: $TEMPLATE (commit this file)"
fi

# Flag the volume root so Finder uses .VolumeIcon.icns.
SETFILE="$(xcrun -f SetFile 2>/dev/null || true)"
if [[ -n "$SETFILE" && -f "$MOUNT/.VolumeIcon.icns" ]]; then
    "$SETFILE" -a C "$MOUNT" || echo "WARNING: SetFile failed — no custom volume icon" >&2
elif [[ -f "$MOUNT/.VolumeIcon.icns" ]]; then
    echo "WARNING: SetFile not found (needs Xcode CLT) — no custom volume icon" >&2
fi

sync
detach_retry "$MOUNT"

echo "==> Compressing"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
trap - EXIT
rm -f "$RW"
rm -rf "$STAGE" "$DIST/dmg-mnt"

echo "✅ DMG: $OUT"
