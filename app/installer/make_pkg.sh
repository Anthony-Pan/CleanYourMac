#!/usr/bin/env bash
#
# Build a product archive (.pkg) that installs CleanYourMac.app into /Applications
# with a full installer UI: welcome, license, branded background, conclusion.
#
# Usage: make_pkg.sh <path/to/CleanYourMac.app> <version> <out.pkg>
#
# Env:
#   INSTALLER_IDENTITY  "Developer ID Installer: ..." to sign the product archive.

set -euo pipefail

APP="${1:?usage: make_pkg.sh <app> <version> <out.pkg>}"
VERSION="${2:?usage: make_pkg.sh <app> <version> <out.pkg>}"
OUT="${3:?usage: make_pkg.sh <app> <version> <out.pkg>}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
DIST="$(cd "$(dirname "$OUT")" && pwd)"
OUT="$DIST/$(basename "$OUT")"
IDENTIFIER="com.anthonypan.CleanYourMac"
WORK="$DIST/pkg-work"

rm -rf "$WORK"
mkdir -p "$WORK/root" "$WORK/resources"
# Strip xattrs/ACLs/quarantine so the installed app can never inherit a
# quarantine flag from the build host. (SIP-protected com.apple.provenance
# survives — the kernel re-applies it and pkgbuild archives it as benign
# AppleDouble entries; every locally built pkg has these.)
ditto --noextattr --noacl --noqtn "$APP" "$WORK/root/CleanYourMac.app"

echo "==> Building component package"
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
# Without this, Installer "upgrades" any stray copy of the app it finds
# elsewhere on disk instead of installing into /Applications.
plutil -replace "0.BundleIsRelocatable" -bool NO "$WORK/component.plist"
pkgbuild \
    --root "$WORK/root" \
    --component-plist "$WORK/component.plist" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location /Applications \
    "$WORK/component.pkg" >/dev/null

echo "==> Rendering installer resources"
ICON_MASTER="$DIST/icon_1024.png"
if [[ ! -f "$ICON_MASTER" ]]; then
    echo "ERROR: $ICON_MASTER not found — run package.sh first" >&2
    exit 1
fi
swift "$HERE/render_assets.swift" pkg light "$WORK/resources/background.png" "$ICON_MASTER"
swift "$HERE/render_assets.swift" pkg dark "$WORK/resources/background-dark.png" "$ICON_MASTER"
sed "s/@VERSION@/$VERSION/g" "$HERE/resources/welcome.html" > "$WORK/resources/welcome.html"
# Signed releases don't need the Gatekeeper "Open Anyway" walkthrough.
if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
    sed "s/@VERSION@/$VERSION/g" "$HERE/resources/conclusion.html" \
        | sed '/<!-- adhoc-note-start -->/,/<!-- adhoc-note-end -->/d' \
        > "$WORK/resources/conclusion.html"
else
    sed "s/@VERSION@/$VERSION/g" "$HERE/resources/conclusion.html" > "$WORK/resources/conclusion.html"
fi
cp "$REPO/LICENSE" "$WORK/resources/license.txt"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/CleanYourMacApp" | tr ' ' ',')"

cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>CleanYourMac</title>
    <organization>com.anthonypan</organization>
    <options customize="never" require-scripts="false" hostArchitectures="$ARCHS"/>
    <domains enable_localSystem="true"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <license file="license.txt"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <background file="background.png" mime-type="image/png" alignment="bottomleft" scaling="none"/>
    <background-darkAqua file="background-dark.png" mime-type="image/png" alignment="bottomleft" scaling="none"/>
    <volume-check>
        <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="app"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="app" visible="false" title="CleanYourMac">
        <pkg-ref id="$IDENTIFIER"/>
    </choice>
    <pkg-ref id="$IDENTIFIER" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
XML

echo "==> Building product archive"
rm -f "$OUT"
productbuild \
    --distribution "$WORK/distribution.xml" \
    --resources "$WORK/resources" \
    --package-path "$WORK" \
    ${INSTALLER_IDENTITY:+--sign "$INSTALLER_IDENTITY"} \
    "$OUT" >/dev/null

rm -rf "$WORK"
echo "✅ PKG: $OUT"
if [[ -z "${INSTALLER_IDENTITY:-}" ]]; then
    echo "   (unsigned — set INSTALLER_IDENTITY=\"Developer ID Installer: ...\" to sign)"
fi
