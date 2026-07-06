# Ribbon feature-parity design (Phase-3.5)

**Goal:** close the ribbon-mechanic gaps that BusinessSkinForm (`bsRibbon`) and
StyleControls (`scToolPager`/pagers) have and `TTyRibbon` lacks, so the ty-controls
ribbon is "not fewer features" than the two references — reimplemented the ty way
(custom-drawn, theme-token-driven, LCL/FPC), **not copied**.

Scope approved by the user 2026-07-06: **all high + medium** gaps below. Excluded by
roadmap and unchanged here: skin-tooling, DB, RichEdit/rich-text, print, MDI/form-tabs,
SplitView, standalone toggle/activity widgets.

## The hard constraint that shapes every "overlay" feature

Ribbon pages, groups and command buttons are **windowed** `TTyCustomControl`s (real
HWNDs). Anything that must appear *above* them — KeyTip badges, a collapsed-group
popup, the minimized-ribbon flyout — **cannot** be painted on the ribbon's own canvas
(child HWNDs paint over it). Each such feature therefore uses a **borderless popup
window** (a `TTyPopupSurface` helper form), and where Office moves live content into a
flyout we **temporarily re-parent** the real group/page control into the popup and
re-parent it back on close (the LCL-native approach; matches how `TTyRibbonBackstage`
already covers the form).

## Features

### 1. Themed ScreenTips (HIGH) — ALREADY IN THE LIBRARY
The gap analysis missed that `tyControls.Hint` already ships `TTyHintWindow` (a themed
`THintWindow` rendered via `TTyPainter` with the `TyHint` token) and a non-visual
`TTyHint` installer that swaps LCL's app-wide `HintWindowClass` while Active. Dropping a
`TTyHint` makes **every** control's Hint (ribbon commands, QAT, everything) render themed.
So there is **no control work** here — just wire a `TTyHint` into the editor demo (the
buttons already carry `Hint`/`ShowHint` from the icon pass). Multi-line hints already
render line-by-line, covering the title+description shape.

### 2. Backstage icons + content panels (MEDIUM)
`TTyRibbonBackstage` is single-level: a flat `Commands: TStrings` + the right area
just echoes the selected caption. Modern Office rows have **icons** and each command
shows its **own content page**.

- Add `IconFont: TTyIconFont` + `CommandGlyphs: TStrings` (parallel to `Commands`,
  index-matched; empty entry = no icon). Render the glyph left of each row's text
  (row text shifts right when an icon is present). Pure `TyBackstageRowRect` gains an
  icon column; geometry stays headless-tested.
- Content host: expose `ContentRect` (device px, right of the sidebar) and a published
  `OnShowContent(Sender; AIndex; const AContentRect: TRect)` the app uses to place its
  own content control (a themed panel / recent-files list) for the selected command.
  The backstage stops drawing the big caption when a content host is present; it keeps
  drawing it as a headless-safe fallback when the app wires nothing.
- Back-compat: `Commands`/`ItemIndex`/`OnCommandSelect` keep working unchanged.

### 3. Group overflow collapse-to-popup (HIGH)
`TyRibbonOverflowCount` already decides *how many* trailing groups must collapse, but
nothing renders the collapsed button or shows the group's content. Complete it:

- The page lays its groups out (Align=alLeft already). A new pass on the **active
  page** measures the sum of group natural widths vs the page width and calls
  `TyRibbonOverflowCount`; the last N groups are **collapsed**: the real group control
  is hidden and a `TTyRibbonCollapsedGroup` button (caption + down chevron, `TyRibbonGroup`
  token) is shown in its place.
- Clicking a collapsed button opens a `TTyPopupSurface` positioned below it and
  **re-parents the real group control into the popup** (full size), so all the live
  command buttons work; closing (click-away / Escape) re-parents the group back and
  hides the popup.
- Pure helpers: `TyRibbonOverflowCount` (exists) + a new `TyRibbonGroupLayout` that,
  given group widths + avail width + collapsed width, returns each group's x/width and
  collapsed flag — headless-unit-tested.

### 4. Minimized-ribbon tab flyout (MEDIUM)
When `Minimized`, the group band is hidden. Office shows the active page's band in a
**transient flyout** when a tab is clicked, auto-hiding on click-away.

- On a tab click while `Minimized`, open a `TTyPopupSurface` directly below the strip
  and **re-parent the active page** into it (page keeps `alClient` inside the popup);
  on dismiss re-parent the page back under the ribbon. Reuses the same popup helper as
  feature 3.
- A second click on the same tab, Escape, or a click outside dismisses.

### 5. KeyTips — Alt access-key overlay (HIGH)
The signature Office feature both refs have. Press **Alt** → key-tip badges appear on
the File tab, QAT buttons and each ribbon tab; type a letter → activate it; for a tab,
a second level shows badges on that page's group commands; **Esc** backs up a level;
**Alt** again / a click dismisses.

- Pure model `tyControls.KeyTips`: `TyAssignKeyTips(const captions): array of string`
  assigns unique 1-char access keys (prefer the caption's first ASCII letter, else the
  next free A–Z/0–9), headless-unit-tested; and a `TTyKeyTipController` state machine
  (levels: hidden → tabs → commands) that maps a typed char to an action.
- Overlay: `TTyKeyTipOverlay = class(TTyPopupSurface)` draws badge rects (rounded
  `TyButton` chips) at caller-supplied device rects over the ribbon; it is a child-less
  popup so it floats above the windowed tabs/commands.
- Wiring: `TTyRibbon` gains `KeyTips: Boolean` (default True) and hooks the parent
  form's key handling (Alt down/up + a char handler while active). Activating a tab
  key-tip switches the page and descends a level; a command key-tip clicks that button.
  Real-machine verification required for the Alt/focus/overlay interaction.

## Testing & verification
Each feature ships **headless FPCUnit tests for its pure logic** (hint split/extent,
backstage icon geometry, group layout, keytip assignment + state machine). Rendering,
popups, re-parenting, Alt handling and the overlay are **GUI-only** and are verified on
a real machine (consistent with the rest of this codebase — see the window-effects /
dialogs memories). The editor demo (`examples/ribbon`) wires every feature so the user
can exercise them.

## Order (each = build + tests + commit + adversarial review)
1. Themed ScreenTips  →  2. Backstage icons + content  →  3. Group overflow popup
→  4. Minimized flyout  →  5. KeyTips.
Shared prerequisite: the `TTyPopupSurface` borderless-popup helper (used by 3/4/5).
