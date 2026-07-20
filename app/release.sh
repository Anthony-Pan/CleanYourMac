#!/usr/bin/env bash
#
# One-shot release builder: .app → styled DMG + installer PKG + checksums.
#
# Usage:
#   ./release.sh                    # defaults below
#   VERSION=1.2.0 ./release.sh
#
# Env overrides: VERSION, BUILD, IDENTITY (app), INSTALLER_IDENTITY (pkg)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${VERSION:-1.1.0}"
BUILD="${BUILD:-$(git -C "$ROOT" rev-list --count HEAD)}"
export VERSION BUILD

"$ROOT/package.sh"

APP="$ROOT/dist/CleanYourMac.app"
DMG="$ROOT/dist/CleanYourMac-$VERSION.dmg"
PKG="$ROOT/dist/CleanYourMac-$VERSION.pkg"

"$ROOT/installer/make_dmg.sh" "$APP" "$VERSION" "$DMG"
"$ROOT/installer/make_pkg.sh" "$APP" "$VERSION" "$PKG"

echo "==> Checksums"
(cd "$ROOT/dist" && shasum -a 256 "$(basename "$DMG")" "$(basename "$PKG")" | tee SHA256SUMS.txt)

echo ""
echo "✅ Release artifacts in $ROOT/dist:"
echo "   $(basename "$DMG")"
echo "   $(basename "$PKG")"
echo "   SHA256SUMS.txt"
