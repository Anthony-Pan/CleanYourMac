# CleanYourMac — Visual Design System ("Aurora glass")

Implements the user's Claude Design mockup (`Mac Cleaner UI.dc.html`, project
9bf658c9). Pixel references live at `/tmp/cym-design/mockup.html`, rendered
per-screen to `.playwright-mcp/ref-3a.png` … `ref-3f.png`:
3a idle dashboard · 3b scanning · 3c results grid · 3d cleanup detail with
inspector · 3e uninstaller list · 3f privacy cards.

## Core idea

ONE aurora stage for the whole app: a deep violet base with three soft radial
color pools (indigo top-right, magenta bottom-right, blue bottom-left). On it:
a 210 pt labeled glass sidebar, a 56 pt top bar per screen (title left, status
pill right), translucent white glass cards, and a 70 pt bottom action bar on
list screens. Idle screens center a glossy 3D orb and a 104 pt circular Scan
button. Privacy uses a warmer aurora variant.

## Theme.swift

- `AuroraBackground(variant: .standard | .privacy)` — the full-window stage.
- `Palette` — text tiers ink/ink2/sub/tiny/slab, hairlines, glass fills, the
  blue-purple action gradient (`Palette.action`, #5A8DFF→#9A5BFF), checkbox
  gradient (#8F5BFF→#C04AE0).
- `PillTone` — `.good .warn .blue .red` chip colors.
- `.glassCard(radius:focused:)` — translucent white fill (NO material: white
  0.07 + border white 0.10; materials render black offscreen).

## Components.swift

- `Orb(size:animating:)` — glossy sphere (radial #BCD6FF→#7FA0FF→#8F5BFF→
  #5A3AB8, top-left highlight), halo glow, two satellite spheres (pink, mint).
  Breathing scale while `animating`.
- `CTACircle(title:disabled:action:)` — 104 pt circle, action gradient + gloss,
  halo ring shadow. The idle screens' primary button.
- `GradientButton(title:disabled:action:)` — radius-10 rect, action gradient,
  13 pt semibold. Bottom-bar primary.
- `GhostButton(title:action:)` — white 0.10 fill, inset hairline.
- `StatusPill(text:tone:)` — 11 pt semibold chip (top bar, badges).
- `GlassCheckbox(on:action:)` — 16 pt rounded-square (radius 5); on = checkbox
  gradient + white check; off = 1.5 pt white-0.30 border.
- `TopBar(title:) { trailing }` — 56 pt row: 19 pt bold title, spacer, pills.
- `BottomBar { content }` — 70 pt, fill #140E28 at 0.5, top hairline.
- `StatCard(label:value:detail:)` — glass stat tile (idle dashboard row).
- `TagBadge` stays (tiny inline chip). `CategoryStyle` stays (icon tiles).

## Layout patterns

**Idle** — TopBar(title, pill: phase) then centered: Orb(230) / headline 26 pt
bold white / sub 12.5 pt white-0.55 / CTACircle("Scan") / row of up to three
StatCards (real data only — never invent numbers).

**Busy** — centered: Orb(animating) with live counter overlaid in its center
(byte count 32 pt bold + status line 12 pt white-0.85) / 280 pt indeterminate
progress bar / GhostButton("Stop") when cancellable, else nothing.

**List / results** — TopBar + content in glass rows/cards + BottomBar with
summary caption left ("4 of 5 categories · 3.5 GB selected") and
GhostButton + GradientButton right. Row anatomy: GlassCheckbox / 32 pt icon
tile / name 13.5 semibold + tiny 11 sub-line / trailing size 13 pt
tabular-nums white-0.60. Focused row: border rgba(150,130,255,.55) + soft
purple outer glow.

**Inspector split (Smart Scan results)** — left: category rows; right: 320 pt
glass inspector panel for the focused category (title, description, item list
with checkboxes). Mirrors ref-3d.

**Done** — centered: 64 pt white checkmark symbol / 26 pt bold headline /
muted summary / CTACircle("Scan Again").

## Color rules

- Text: `.white`, white 0.82, white 0.55 (sub), white 0.45 (tiny), white 0.40
  uppercase tracked (slab). Hairline white 0.10.
- Checkbox ON is the purple checkbox gradient with a white check (mockup);
  never accent-colored circles.
- Status pills: good #7BE8A8/15%, warn #FFC37B/15%, blue #AEB8FF/18%,
  red #FF9DAE/16%.
- Legacy (delete once unused): `ModuleTheme`, `ModuleBackground`, `HeroBlob`,
  `CircleActionButton`, `GlassPill`, `Palette.warn/muted/faint/glassGradient`.

## Sidebar (210 pt)

Glass strip (white 0.045 fill, right hairline). 44 pt top clearance for real
traffic lights. Items: 14 pt gradient dot + 12.5 pt label; selected = white
0.13 rounded-8 fill. Order: Smart Scan (dot #6FD3FF→#8F5BFF) · CLEANUP header
· Large & Old Files (#5BE0C8→#1FA88F) · PROTECTION · Privacy (#FF8FD0→#C04AE0)
· APPLICATIONS · Uninstaller (#FFC37B→#FF7A4D). Section headers 9.5 pt bold
white-0.32 tracking 1.3 uppercase. Footer: real disk usage — "Macintosh HD",
5 pt gradient bar (#6FD3FF→#B06CFF), "X GB used of Y GB" from
`URLResourceValues` volume capacities.

## Safety copy is inviolable

All confirmation-dialog copy, safety banners, running-app warnings and
protected-item notices keep their exact wording. Restyle containers only.
Never render fake data: every number on screen comes from a model.
