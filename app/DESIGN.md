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
- `GlassCheckbox(state:action:)` — 16 pt rounded-square (radius 5), tri-state
  `CheckState`: `.on` = checkbox gradient + white check; `.mixed` (partial
  selection) = checkbox gradient + white minus glyph; `.off` = 1.5 pt
  white-0.30 border. `GlassCheckbox(on:action:)` stays as the two-state
  convenience for plain rows.
- `SizeText(_ bytes:emphasized:)` — the one trailing "data number" style:
  13.5 pt semibold white-0.82, monospaced digits; `emphasized` lifts the
  largest row to pure white.
- `RelativeSizeBar(value:max:gradient:height:)` — 3 pt capsule under a row
  name/sub-line showing size relative to the biggest visible row. Real bytes
  only; renders nothing when `max <= 0`, floors at 2 pt when `value > 0`.
- `SizePending(width:)` — 52×12 white-0.08 capsule with a slow opacity pulse,
  the placeholder for a size still being computed. A pending size is ALWAYS
  a shimmer — never a fake "0 B"/"Zero KB".
- `TopBar(title:) { trailing }` — 56 pt row: 19 pt bold title, spacer, pills.
- `BottomBar { content }` — 70 pt, fill #140E28 at 0.5, top hairline.
- `StatCard(label:value:detail:)` — glass stat tile (idle dashboard row).
- `TagBadge` stays (tiny inline chip). `CategoryStyle` stays (icon tiles).

## Layout patterns

**Idle** — TopBar(title, pill: phase) then centered: Orb(230) / headline 26 pt
bold white / sub 12.5 pt white-0.55 / CTACircle("Scan") / row of up to three
StatCards (real data only — never invent numbers).

**Smart Scan (dashboard)** — orchestrates the four module scans concurrently
on the shared models; it owns no results and never cleans. Idle follows the
generic idle pattern. Busy follows the busy pattern with a "FOUND SO FAR"
byte counter (junk + privacy + large-file bytes as they land), SweepBar
fraction = done areas ÷ 4, and one progress row per area (all four scan at
once, so several rows may be active simultaneously). Results: hero found
total (30 pt bold; "All clear" instead of a zero byte count) above a 2×2
grid of module cards — 32 pt icon tile using the module's sidebar-dot
gradient, name, 24 pt bold headline number, 11 pt sub-line (`SizePending`
shimmer while app sizes stream) — each card a button that opens its module
screen, already loaded. BottomBar: "N of 4 areas scanned · X found" +
GhostButton("Rescan") only; the primary clean action intentionally lives in
the module screens with their own confirmations.

**Busy (scanning)** — centered: Orb(animating) with a "JUNK FOUND" slab
caption + 32 pt bold byte counter overlaid in its center / 280 pt determinate
SweepBar (fraction = done categories ÷ total, shimmer sweeps inside the filled
portion) / "Step N of M locations" caption 11 pt tiny / merged status line
12.5 pt sub ("Scanning ~/Library/… · 129 items found", middle-truncated,
≤380 pt) / per-category progress rows (13.5 pt name; green "✓ bytes" when
done; focused glass card while active; 0.5 opacity while waiting) /
GhostButton("Stop") when cancellable, else nothing. The cleaning screen uses
the SweepBar's indeterminate variant (`fraction: nil`) with a live
"Moving N items (X GB) to Trash…" sub-line.

**List / results** — TopBar + content in glass rows/cards + BottomBar with
summary caption left ("4 of 5 categories · 3.5 GB selected") and
GhostButton + GradientButton right. Row anatomy: GlassCheckbox / 32 pt icon
tile / name 13.5 semibold + tiny 11 sub-line + optional `RelativeSizeBar`
under the name / trailing size in `SizeText` (13.5 pt semibold white-0.82,
monospaced digits; `emphasized` white on the largest row — the emphasized
treatment is scoped to System Junk category rows). Nested detail rows
(inspector items, uninstall leftovers) intentionally use the lighter 11–13 pt
sub/tiny sizes so the top-level rows keep the visual weight. Focused row:
border rgba(150,130,255,.55) + soft purple outer glow.

**Inspector split (System Junk results)** — left: category rows; right: 320 pt
glass inspector panel for the focused category (title, description, item list
with checkboxes). Mirrors ref-3d. Required left-column content above the
category rows: the selection summary header (30 pt bold `selectedBytes` hero
number + 12.5 pt sub-line, live as the user toggles) and, below the rows, the
Space-breakdown card (stacked proportion bar, one `CategoryStyle`-gradient
segment per group, plus a legend of real per-group totals).

**Uninstaller** — two-phase discovery: app names + icons appear first
(alphabetical, < 1 s), real bundle sizes stream in afterwards. A not-yet-sized
row shows `SizePending` — never a fake number. A sort Menu (Name / Size) sits
in the TopBar; the default Name order never auto-resorts while sizes stream,
while the user-chosen Size order re-ranks as sizes land (the menu flags it
"Size (still calculating)" until every app is sized). The 70 pt
BottomBar is required: real progress while sizing ("N apps · sizing X of Y…"),
real totals when done. The inspector-split from ref-3e was evaluated and the
inline leftover accordion is retained.

**Large & Old Files** — deviates from the generic list pattern on purpose:
Rescan and the blue count/size pill live in the TopBar, all filter controls sit
in one glass toolbar card, the master "Select all shown" checkbox is tri-state,
and the BottomBar carries the caption + a single GradientButton. Empty
selection reads "Nothing selected yet — review and pick files above." with a
plain disabled "Clean" — never "Clean Zero KB".

**Done** — centered: 64 pt white checkmark symbol / 26 pt bold headline /
muted summary / CTACircle("Scan Again").

## Color rules

- Text: `.white`, white 0.82, white 0.55 (sub), white 0.45 (tiny), white 0.40
  uppercase tracked (slab). Hairline white 0.10.
- Checkbox ON is the purple checkbox gradient with a white check (mockup);
  never accent-colored circles.
- Status pills: good #7BE8A8/15%, warn #FFC37B/15%, blue #AEB8FF/18%,
  red #FF9DAE/16%.
- Pill tone rule: `.blue` for every neutral count/size total; `.warn` reserved
  for genuine cautions (partial scan, skipped items, running apps, safety
  banners); `.good` for completed/safe states. `.red` is used ONLY for the
  Privacy results trace total — clearing traces is inherently a caution
  (sign-outs, lost tabs), so that one total is intentionally not neutral.

## Sidebar (210 pt)

Glass strip (white 0.045 fill, right hairline). 44 pt top clearance for real
traffic lights. Items: 14 pt gradient dot + 12.5 pt label; selected = white
0.13 rounded-8 fill. Order: Smart Scan (dot #6FD3FF→#8F5BFF) · CLEANUP header
· System Junk (#6FA8FF→#3E62D9) · Large & Old Files (#5BE0C8→#1FA88F)
· PROTECTION · Privacy (#FF8FD0→#C04AE0) · APPLICATIONS · Uninstaller
(#FFC37B→#FF7A4D). Section headers 9.5 pt bold
white-0.32 tracking 1.3 uppercase. Footer: real disk usage — "Macintosh HD"
11 pt semibold white-0.78, 5 pt gradient bar (#6FD3FF→#B06CFF), caption
"X GB used of Y GB" 11 pt white-0.55 (sub tier — legible against the aurora)
from `URLResourceValues` volume capacities.

## Safety copy is inviolable

All confirmation-dialog copy, safety banners, running-app warnings and
protected-item notices keep their exact wording. Restyle containers only.
Never render fake data: every number on screen comes from a model.
