# CleanYourMac — Visual Design System

Modeled on CleanMyMac 5's design language (MacPaw, 2024 redesign). Reference
screenshots live at `/tmp/cmm-ref/*.png` during development.

## Core idea

Every module owns a **signature full-bleed gradient stage**. Content floats on
it: centered hero artwork, big white headlines, frosted-glass cards, and one
**large circular action button at the bottom center**. Chrome is minimal — an
icon-only sidebar rail, no window titlebar.

## Module themes (`ModuleTheme` in Theme.swift)

| Module            | Theme     | Stage                       | Accent (button) |
|-------------------|-----------|-----------------------------|-----------------|
| Smart Scan        | `.magenta`| deep purple → magenta glow  | `#CC1FB8`       |
| Uninstaller       | `.indigo` | deep navy → indigo glow     | `#5D49F0`       |
| Large & Old Files | `.teal`   | deep pine → teal glow       | `#0FA893`       |
| Privacy           | `.blue`   | deep navy → azure glow      | `#2374E1`       |

The stage (`ModuleBackground`) is drawn once by `RootView` behind everything —
views never draw their own background.

## Layout patterns

**Idle / start screen** — vertically centered: `HeroBlob` artwork (~200 pt),
module title (34 pt bold white), one-line subtitle (13 pt, `Palette.muted`),
then a `CircleActionButton("Scan")` pinned near the bottom center (~48 pt from
bottom edge).

**Scanning** — `HeroBlob(animating: true)`, big status line ("Scanning…",
"Digging through…"), the current path/location in a small truncated caption
below, `CircleActionButton("Stop", ring: .progress)` at bottom center. If the
operation can't be cancelled, show the same circle as a non-interactive
spinner.

**Results** — small module label top center (12 pt, `Palette.muted`,
tracking 1.2, UPPERCASE not required); centered headline: the number is the
hero ("You have **12.4 GB** to clean up", 30 pt bold white) with a 13 pt muted
subline; content in frosted-glass cards (`.glassCard()`); bottom center: a
selection caption (13 pt, white 0.8) directly above `CircleActionButton
("Clean")`. Destructive actions keep their existing confirmation dialogs —
copy must not change.

**Done** — large white SF-symbol checkmark (56–64 pt), 30 pt bold headline,
muted summary line, `CircleActionButton("Scan Again")`.

## Components (Components.swift)

- `HeroBlob(theme:symbol:animating:)` — flower-blob artwork, the module's 3D
  mascot stand-in.
- `CircleActionButton(title:theme:ring:disabled:action:)` — the 72 pt circular
  primary button; `ring: .halo` (idle ring) or `.progress` (spinning arc).
- `GlassPill(title:systemImage:prominent:action:)` — small capsule button for
  secondary actions ("Review", "Done", back links, filters).
- `TagBadge(text:color:)` — tiny status chip; default color `Palette.warn`.
- `CategoryGridCard` — frosted glass result card with a colored icon tile.
- `ItemRow` — file row for detail lists; pass `.white` as the checkbox color.

## Color rules

- Text: `Palette.ink` (white), `Palette.ink2` (0.82), `Palette.muted` (0.58),
  `Palette.faint` (0.36). Hairlines: `Palette.hair`.
- Checkboxes/selection marks are **white** (`.white` on, `.white.opacity(0.28)`
  off) — never the accent color (contrast on colored stages).
- Warnings ("Running", "review", age chips, notices): `Palette.warn`.
- Never use the legacy members (`Palette.accent`, `.accentLinear`,
  `.champagne`, `.bg`, `StageBackground`, `ReclaimGauge`, `CleanButton`) —
  they exist only until the migration finishes.

## Safety copy is inviolable

All confirmation-dialog copy, safety banners, running-app warnings, and
protected-item notices are part of the product's safety contract. Restyle
their container, never their words.
