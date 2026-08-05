# TyControls — Known Gaps (v1 / v1.1)

These behaviors are intentionally NOT implemented or are tracked for a future
Tier-2 native enhancement layer.

## Form chrome (TTyForm) native window behavior

Custom window chrome is now obtained by descending from **`TTyForm = class(TForm)`**
(the controller `TTyFormChrome` was removed; see
[controls/ttyform.md](controls/ttyform.md)). `TTyForm` is born borderless
(`BorderStyle := bsNone`) and delegates window behavior (drag-move, edge-resize,
custom maximize/restore, DPI rescale) to a form-agnostic `TTyChromeEngine`. The
native behaviors below are tracked here with their current status — the ones
still marked as gaps belong to a future Tier-2 native enhancement layer.

- Windows Aero Snap (edge tiling + snap-to-top maximize): **implemented** on the
  Win32 widgetset. A title-bar drag is handed to the OS as a native caption move
  (`WM_NCLBUTTONDOWN`/`HTCAPTION`), and `tyControls.Win32WS` gives the borderless
  window the styles the shell requires before it will offer snapping at all — a
  resizable top-level `TTyForm` trades LCL's `WS_POPUP` for `WS_CAPTION`
  (`WS_THICKFRAME` + `WS_MAXIMIZEBOX` were already asserted). Nothing native is
  drawn: `WM_NCCALCSIZE` still collapses the whole non-client area. So dragging
  to a side/corner tiles the window, dragging to the top **maximizes** it, and
  the resulting state is adopted by the chrome (`TTyForm.Resizing` →
  `TTyChromeEngine.SyncNativeMaximized`: square corners, restore glyph, and a
  restore that goes back through the OS's own restore rect). Dragging a
  maximized window tears it loose — it restores under the pointer and the drag
  continues, as on any native title bar. Exceptions: Vista/Win7 keep their
  thick frosted Aero top frame and stay `WS_POPUP` (a caption style there would
  paint a real OS title bar above ours), and a fixed (`Resizable := False`) or
  rolled-up window is not snappable by design. GTK/Qt/Cocoa rely on the
  widgetset's own system-move (`TyQt/TyGtkStartSystemMove`), so tiling there is
  whatever the window manager offers. **Pending real-machine verification** of
  the snap zones/animations (no window manager in the headless test rig); the
  pure hit-test and restore-geometry logic is unit-tested.
- Borderless-window rounded corners + native drop shadow: **implemented** in
  `tyControls.WindowEffects` (`TyApplyWindowEffects`), applied by `TTyForm` on
  show/theme/maximize. ON by default; opt out via `TyForm { border-radius: 0;
  window-shadow: false; }`. Per-platform: Win11 = anti-aliased DWM corners + free
  shadow; Win Vista–10 = square + `DwmExtendFrameIntoClientArea` shadow; XP =
  square, no shadow; macOS = `CALayer.cornerRadius` + `NSWindow.setHasShadow`.
  `dwmapi.dll` is loaded dynamically (`GetProcAddress`) so the binary still
  launches on Win7/XP. The pure logic (token parse, radius→enum, default-on) is
  unit-tested headlessly. **Pending real-machine visual verification** — the
  actual rendered corners/shadow on Win11, Win10 and macOS still need a human to
  eyeball (no headless GPU/compositor). Risk: the Win Vista–10 native shadow on a
  pure `WS_POPUP` (bsNone) window may need a `WM_NCCALCSIZE`/style tweak to appear;
  if it does not, fall back to no native shadow on pre-Win11. Linux is a documented
  widgetset-aware extension point (not implemented).
- macOS traffic-light (red/yellow/green) caption buttons are not emulated;
  TyControls draws its own close/min/max glyphs (`TTyCaptionButton`) instead.
  macOS users do not get platform-standard window controls. A visual approximation
  using `ShowGlyphOnHoverOnly` is documented in
  [docs/recipes-traffic-lights.md](recipes-traffic-lights.md).
- Cross-monitor DPI switching: **metrics rescale on monitor-PPI change** (v1.1).
  The chrome engine handles the form's `ChangeBounds`; when the form's monitor
  PPI changes, the title bar height and button width are rescaled via
  `TyRescaleChromeMetric` (MulDiv with half-up rounding). The pure function and
  the rescale path are unit-tested. Multi-monitor manual validation pending
  (only one physical monitor available in the build environment).

## Controls

- `TTyCheckBox` / `TTyRadioButton` `opacity` and `shadow`: **resolved in v1.1**.
  The rendering path now routes through `DrawFrame` which applies both
  properties; they are fully effective for all typeKeys including checkbox and
  radiobutton.
- `TTyMemo` editing core + selection (v1.11), deferred features: the multi-line
  editor ships a reliable per-codepoint editing core (Enter/Backspace/Delete with
  cross-line merge, 2-D arrow + Home/End navigation, vertical scrollbar/wheel) and
  — as of **v1.11** — a full 2-D **text selection** layer mirroring `TTyEdit`:
  selection anchor (`Shift`+arrows/Home/End extend, mouse-drag highlight, per-line
  selection band, `SelText`/`SelectAll`/`CollapseSelection`), **range clipboard**
  (`Ctrl/Cmd+A/C/X/V`; paste splits on CR/LF into multiple lines; copy/cut via the
  same virtual `ReadClipboardText`/`WriteClipboardText` hooks as `TTyEdit`), and
  **word navigation** (`Ctrl/Alt+Left/Right` move by word, crossing line
  boundaries; `Ctrl/Alt+Backspace/Delete` delete the adjacent word and fall back to
  the cross-line merge at a line edge). As of **v1.12** both text controls also
  ship snapshot-based **undo/redo** (`Ctrl/Cmd+Z` undo; `Ctrl/Cmd+Y` or
  `Ctrl/Cmd+Shift+Z` redo) with a bounded (~200-step) history and typing
  coalescing — `TTyEdit` additionally gained an `OnChange` event, which (like
  `TTyMemo.OnChange`) fires on undo/redo. The three items this entry used to list
  as deferred have all since shipped, and the text saying otherwise outlived the
  implementations by several releases — recorded here so the next reader knows the
  old wording was wrong rather than describing another version:
  - **Word-wrap**: `WordWrap` (default `False`) reflows a long logical line into
    several visual rows at word boundaries.
  - **Horizontal scroll**: with `WordWrap = False` a long line scrolls sideways —
    a real embedded horizontal scrollbar plus a `ScrollX` offset the caret drags
    along. All four horizontal `ScrollBars` values are honoured.
  - **Caret blink**: a `TTimer`-driven blink (~530 ms), created lazily once the
    handle exists, so the caret stays static headless and in the designer.
  See [controls/memo.md](controls/memo.md) §10 and §11 (undo/redo) for the
  per-control writeup.
- **Drop shadows / elevation on embedded controls — deliberately deferred.**
  Batch⑤+⑥ shipped per-control motion (cursors, hover-fade, knob-slide, eased
  progress/scrollbar/trackbar position, tab-header cross-fade) but intentionally
  did NOT add Material-style drop shadows or elevation to the controls. LCL clips
  an embedded `TControl`'s painting to its own bounds, so a shadow drawn inside a
  control's `Paint` cannot bleed past its edges into the parent — a faithful
  elevation effect would require painting on the parent surface (or a separate
  overlay window), which is out of scope for this batch. Deferred to a future
  Tier-2 enhancement layer.

## Bidirectional (right-to-left) text

Arabic, Hebrew, Persian, Urdu and the other right-to-left scripts are supported
**at the text layer, and at the layout layer for form controls only**. Read the
two lists below before shipping a UI in one of those languages: what works is
real, and what does not is not cosmetic.

Two independent questions live in this section, and keeping them apart is what
makes the rest of it readable:

- **"Which way does this *sentence* read?"** — answered from the string, by
  scanning it for right-to-left codepoints. Governs word order and letter
  shaping. Always on, for every control, no configuration.
- **"Which way does this *form* read?"** — answered from the control's
  `BiDiMode`. Governs which side boxes sit on. Off by default, and implemented
  for the controls listed below and no others.

An Arabic caption on a left-to-right form gets its words in the right order and
does **not** move to the right edge. That is correct, and it is asserted by
`tests/test.bidi.pas`.

### What works

- **Word order.** `TTyPainter.DrawText` — the single chokepoint every caption,
  label, button, list row, tab header, menu item, grid cell and status panel in
  this library draws through — routes any string containing a right-to-left
  codepoint through BGRABitmap's `TBidiTextLayout`, which implements the Unicode
  bidirectional algorithm (UAX #9). The paragraph's base direction is resolved
  from its **first strong character**, so a caption that begins in Arabic and
  ends in Latin (`"<arabic phrase> Acme"`) now puts the two halves the way a
  native reader expects them.

  Before this change the painter handed the whole caption to one text call, which
  is always laid out with an implicit **left-to-right** paragraph base — so that
  same caption came out with the Arabic on the left and the Latin tail on the
  right, i.e. the picture for a different sentence. Within a single run the order
  was already correct, because the underlying text engine (GDI on Windows, Pango
  on GTK, CoreText on macOS) reverses right-to-left runs itself; what no single
  text call does is choose whose paragraph it is.

- **Letter shaping.** Arabic letters change form according to their neighbours
  (initial / medial / final / isolated). That substitution is done by the
  platform's text engine inside each run, and it is verified rather than assumed:
  `tests/test.bidi.pas` asserts that BEH followed by TEH renders **pixel-identical**
  to the pre-composed presentation forms `U+FE91 U+FE96`, and visibly different
  from the two isolated forms `U+FE8F U+FE95`. Measured on Windows: 31 px wide
  joined, 46 px isolated.

- **Numbers inside right-to-left text** run left-to-right, as the algorithm
  requires, without the caller doing anything.

- **Mnemonic underlines** (`Alt` access keys) land under the character they
  belong to, not at the byte offset's distance from the left edge.

- **Editing a single-line field.** `TTyEdit` — and with it every control that
  descends from it, none of which overrides the caret or the paint path:
  `TTyNumericEdit`, `TTyCurrencyEdit`, `TTyCalcEdit`, `TTyTrackEdit`,
  `TTyMaskEdit`, `TTyURLEdit`, `TTyComboEdit` and `TTyValueEdit` — puts its
  caret, its click target, its selection highlight and its `Left`/`Right` arrow
  keys on the **glyphs**, not on the string order:

  - clicking a glyph puts the caret against that glyph, including on the far
    side of an embedded run;
  - a selection that crosses a direction boundary paints **one band per run**,
    so the highlight covers the glyphs the range names and nothing between them;
  - `Left` and `Right` move the caret one glyph **in the direction pressed**,
    crossing between runs in screen order — which for a right-to-left run means
    stepping backwards through the codepoints;
  - `Home` and `End` stay **logical** (first and last codepoint, wherever those
    are drawn), as do `Ctrl`+arrow word jumps, because a word is a run of
    codepoints and not of glyphs.

  Where an embedded run meets the text around it, one codepoint index has **two**
  screen positions — the two ends of that run — and the Unicode algorithm does
  not choose between them. `TTyEdit` remembers which one the last caret movement
  implied, so both are reachable: typing and a rightward walk leave the caret
  against the character before it, a click leaves it against the run the user
  aimed at. `tests/test.edit.bidi.pas` guards all of it.

- **Cost to everyone else: none measurable.** Latin and CJK text never reaches
  the bidirectional layout. A byte scan (`TyTextHasRTL`, 24–32 ns for a typical
  caption against a 1.5–11 ms draw) decides, and the legacy path it protects
  produces byte-identical output to before — asserted in pixels, not assumed.
  On the *caret* path the same scan runs once per text change rather than per
  query, so a left-to-right field pays one Boolean test: measured at ≤ 0.2 µs
  against a ~23 µs caret query, i.e. inside the run-to-run noise. The layout it
  guards costs ~3.3 ms to build.

- **Layout mirroring, for a form's worth of controls.** Set
  `BiDiMode := bdRightToLeft` from code (see the caveat below about it not being
  *published*) and the following now lay themselves out right-to-left. This is
  phases 0 and 1 of `plans/2026-08-04-rtl-mirroring-scope.md`; the rest of that
  document is not built.

  | Control | What moves |
  |---|---|
  | `TTyLabel` | the caption: `taLeftJustify` resolves to the right edge |
  | `TTyPanel` | the caption (its *children* are not mirrored — see below) |
  | `TTyDivider` | the caption and the rule swap ends; `LeftIndent` counts from the right |
  | `TTyCheckBox`, `TTyRadioButton` | the indicator moves to the right, the caption re-hugs it |
  | `TTyGroupBox` | the caption band moves to the other end of the top border |
  | `TTyCheckGroup`, `TTyRadioGroup` | the columns fill from the right; each hosted box flips its own indicator; the ←/→ keys follow the columns |
  | `TTyButton` and descendants | the caption (a `taCenter` caption — the default — does not move) |
  | `TTyGlyphButton`, `TTySpeedButton`, `TTyGlyphContainerButton` | the icon slot swaps sides (`glLeft` ↔ `glRight`; `glTop`/`glBottom` unaffected) |
  | `TTyColorButton` | the colour swatch moves to the right, the caption to its left |
  | the numeric badge on any button | `BadgePosition` flips horizontally: `bpBottomRight` (the default) becomes bottom-**left** |

  The mechanism is one flag on `TTyPainter`, set at `BeginPaint`, that resolves
  every alignment the caller passes from a *reading-order* one to a physical one
  through LCL's `BidiFlipAlignment`. A control opts in by passing
  `IsRightToLeft`; everything that has not opted in is bit-for-bit unchanged.
  `grep -n "BeginPaint(.*IsRightToLeft" source/` is the authoritative list.

  **`Alignment` is overridden, not defaulted.** A caption the author explicitly
  set to `taLeftJustify` sits on the **right** in a right-to-left form, and a
  check box whose `Alignment` was set to put the indicator on the right gets it on
  the **left**. This matches LCL (`grids.pas:4006` flips a column's own alignment
  at paint time; `checklst.pas:199` flips the check side unconditionally), and the
  alternative — "flip only the default the author did not write" — is not
  expressible: `TAlignment` has no *unset* member. The stored property is never
  rewritten; only the value used for one frame is.

### What does NOT work

- **Most controls are still laid out left-to-right.** Everything not in the table
  above ignores `BiDiMode` entirely — it does not half-mirror, it does not move at
  all:

  - a scroll bar stays on the **right** edge of its container;
  - grid and list-view **columns** keep their left-to-right order, and so do
    tab headers, toolbar buttons, breadcrumb segments and pagination items;
  - a tree view's expander stays on the **left**, and indentation still grows
    rightwards;
  - an edit or memo keeps its text, caret and selection anchored to the left;
  - a `TTyDropDownButton` keeps its arrow zone on the **right**, and a
    `TTyButtonGroup` keeps its segments in left-to-right order — deliberately,
    because both read a click's x back through a hit test, and mirroring the paint
    without the hit test is the "drawn on the right, answers on the left" defect
    this library has already shipped three times. Pinned by
    `tests/test.rtl.pas` (`TRtlExclusionTest`), which asserts paint and hit test
    still agree, so mirroring either one alone turns red.

  A right-to-left UI built on this release gets its forms — labels, check boxes,
  radio groups, buttons, panels — the right way round, and its data views the
  wrong way round.

- **Containers do not mirror their children's `Align`/`Anchors` layout**, and this
  is not a gap to be closed. LCL's own align engine has no BiDi branch outside the
  `ChildSizing` *table* path (`wincontrol.inc:1551`, which `TTyPanel` republishes
  and therefore gets for free), so mirroring ours would make a ty container behave
  differently from every native container beside it and misplace any ported
  `.lfm`. `Home`/`End`/`PageUp`/`PageDown` are likewise never flipped: they are
  logical ends, not visual ones.

- **`BiDiMode` is not published** on any control, and must not be yet, because the
  controls above are the minority — the Object Inspector would be offering a
  property most of the library ignores. Setting it from code works.
  `tests/test.parity.pas` (`LyingPropertiesStayUnpublished`) pins this.

- **`TTyMemo` still walks the string in logical order.** The multi-line editor
  *draws* right-to-left text correctly, but its caret and its click-to-position
  use a cumulative sum of codepoint widths taken in string order
  (`CaretToVisual` / `VisualToCaret`, built on the same per-line width cache).
  That model is simply untrue for bidirectional text — in a mixed string the
  caret between two logically adjacent codepoints can be at two different places
  on screen. **So an Arabic paragraph in a memo draws right and selects wrong**:
  clicking a glyph can put the caret somewhere else, arrow keys jump across the
  run, and a drag-selection can highlight a range that does not correspond to the
  glyphs under the pointer. A control that draws right and selects wrong is in
  some ways worse than one that draws wrong, because the drawing is what a
  reviewer checks.

  `TTyEdit` was fixed and `TTyMemo` was not, deliberately rather than for lack of
  time: the memo's caret is a two-dimensional `(line, column)` model over *visual
  rows*, which under word wrap are segments of a logical line. Adopting the run
  table means building one per visual row and threading it through row
  resolution, per-row selection bands, the up/down arrows' remembered column, and
  the horizontal scroll — a materially larger job than the single-line case, and
  one where a half-wired result would be worse than an untouched one. What it
  needs is in `docs/controls/memo.md`.

  Neither control calls `TTyPainter.TextCaretX` / `TextCharIndexAtX`, and the
  reason is worth recording: those lay out on the painter's `FBmp`, which exists
  only between `BeginPaint` and `EndPaint`, while a caret is queried from mouse
  handlers, key handlers and the blink timer; and `TextCaretX` answers with
  `TBidiTextLayout.GetCaret`, which resolves a direction boundary towards the run
  that *ends* there and discards the other position — so the far end of an
  embedded run is unreachable through it. `TTyEdit` therefore lays the line out
  itself and caches the result, and
  `test.edit.bidi.EditCaretAgreesWithThePainterForUnambiguousIndices` pins its
  answer against the painter's for every index the painter can express.

- **A wrapped paragraph resolves its direction per line, not per paragraph.**
  Word wrap (`TyWrapTextCJK`) breaks on spaces and on CJK codepoints, so Arabic
  wraps correctly — but each resulting line then picks its own base direction
  from its own first strong character. UAX #9 says a wrapped line should inherit
  the *paragraph's* base direction. So a wrapped right-to-left paragraph whose
  second line happens to begin with a Latin word gets a left-to-right base for
  that line alone. Single-line captions — which is nearly everything in this
  library — are unaffected.

- **Vertical scripts** (Mongolian, traditional vertical CJK) are not supported at
  all, in any form.

## Design-time rendering

- Controls dropped onto a form render with the **built-in default skin** in the
  Lazarus designer (zero-config, visible without running).
- Window chrome is **no longer runtime-only**. A `TTyForm` reserves its content
  area at design time: the title bar occupies the top band and the content panel
  fills the area below it, so controls you drop into the content panel sit in
  their final positions in the designer — **layout is WYSIWYG**. What remains a
  design-time gap is that the title-bar **skin renders unthemed** in the
  designer: the designer has no runtime theme context, so the self-drawn title
  bar shows the built-in default appearance rather than your loaded `.tycss`
  theme — exactly like every other tyControl. This is expected, not a bug.

## Style engine

- Nine-slice `url()` asset paths must not contain spaces. The style lexer splits
  dotted tokens; spaces are stripped when the filename is reconstructed, so a
  path like `my assets/bg.png` will be silently misread. Keep asset filenames
  and directory names space-free.
- A `shadow:` value's color must be a single token — a bare hex value
  (`#0000002E`), a CSS custom property (`var(--x)`), or a bare variable name
  (`--x`). A comma-bearing color function such as `alpha(c, a)` or `mix(...)`
  cannot be used in `shadow` because the value is space-split into
  offset / blur / color; use hex-alpha notation instead (e.g. `#0000002E`).

## Package / build

- The demo project builds against the source path (`../../source`) because
  the unregistered package link is not auto-injected by `lazbuild`. A real
  consumer should install `tycontrols.lpk` via the Lazarus IDE package manager,
  which registers the package and injects it automatically.
