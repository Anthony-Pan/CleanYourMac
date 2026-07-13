# CleanYourMac (native)

A native macOS cleanup app built around a **safety-first** engine: it only ever
touches an allowlist of reclaimable locations, moves items to the **Trash**
(never permanent `rm`), and re-validates every path before acting.

## Layout

| Target | What it is |
|---|---|
| `CleanCore` | The cleanup engine (SafetyPolicy, Scanner, Cleaner, Categories) plus the uninstaller engine (UninstallPolicy, AppDiscovery, AppUninstaller). Pure logic, fully unit-tested. |
| `CleanUI` | SwiftUI views (sidebar, reclaim gauge, category cards, uninstaller). |
| `CleanYourMacApp` | The app entry point (`@main`). |
| `smartclean` | CLI front end for the engine. |
| `snapshot` | Off-screen renderer for design previews and the app icon. |

## Develop

```bash
swift test                    # run the CleanCore safety tests
swift run CleanYourMacApp     # launch the app (scans your real Mac)
swift run smartclean          # CLI: read-only scan
swift run smartclean --dry-run
swift run smartclean --clean  # move reclaimable items to Trash
swift run smartclean apps          # CLI: list removable apps (read-only)
swift run smartclean apps <name>   # CLI: preview an app's uninstall plan
swift run snapshot            # write a design preview PNG to /tmp
```

Open in Xcode by opening `Package.swift` directly.

## Package a `.app`

```bash
./package.sh                                                   # unsigned bundle in dist/
IDENTITY="Developer ID Application: NAME (TEAMID)" ./package.sh  # + hardened-runtime signature
```

Then notarize (Developer ID required — App Store certs won't work for direct
distribution). `package.sh` prints the exact `notarytool` commands after signing.

Find your identities with:

```bash
security find-identity -v -p codesigning
```

## Safety model

1. **Allowlist** — only declared roots (`~/Library/Caches`, `~/Library/Logs`, Xcode DerivedData, dev caches) are ever scanned.
2. **Protected denylist** — home, `~/Documents`, `~/Desktop`, system dirs are refused even if mis-declared.
3. **Symlink resolution** — a link inside a cleanable dir that points elsewhere is refused.
4. **Minimum depth** — shallow paths like `/` or `/Users/name` are refused.
5. **Re-validation in the Cleaner** — every item is checked again immediately before disposal.
6. **Trash, not delete** — everything is recoverable from the Trash.
7. **Real dry-run** — preview mode touches nothing.

Each rule is covered by a test in `Tests/CleanCoreTests/`.

## Uninstaller

Removes an app together with the leftover files it leaves behind, keyed by the
app's bundle identifier. It reuses the same safety spine (`UninstallPolicy`):

1. **App allowlist** — only `.app` bundles inside `/Applications`, `/Applications/Utilities` and `~/Applications` are removable.
2. **Leftover allowlist** — associated files are only ever removed from a fixed set of `~/Library` subdirectories (Application Support, Caches, Preferences, Containers, Group Containers, Saved Application State, Logs, HTTPStorages, WebKit, Cookies, LaunchAgents, Application Scripts). Nothing under `/Library`, `/private/var` or any root-owned location is touched.
3. **Confidence** — bundle-id matches (e.g. `com.foo.Bar`) are exact and auto-selected; app-name and Group-Container matches are heuristic, flagged for review, and **off by default**.
4. **Never** — Apple / system apps (`com.apple.*`, `/System`), the app's own bundle, whole well-known directories, and anything that resolves (via symlink) outside the allowed roots.
5. **Trash, not delete**, and every path is re-validated immediately before disposal — same as System Junk.
