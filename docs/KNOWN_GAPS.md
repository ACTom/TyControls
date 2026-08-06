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

- **Word order.** `TTyPainter.DrawText` — the chokepoint every caption, label,
  button, list row, tab header, menu item and status panel in this library draws
  through — routes any string containing a right-to-left codepoint through
  BGRABitmap's `TBidiTextLayout`, which implements the Unicode bidirectional
  algorithm (UAX #9). The paragraph's base direction is resolved from its
  **first strong character**, so a caption that begins in Arabic and ends in
  Latin (`"<arabic phrase> Acme"`) now puts the two halves the way a native
  reader expects them.

  **Grid cells are the one exception, and they are a second implementation.**
  `TTyCustomGrid.DrawCellText` does not call the painter at all — it lays text
  into its own cached bitmap, which is what lets a very large table scroll. This
  list used to name grid cells as going through `DrawText`; that was simply
  wrong, and being wrong is why the grid kept the original defect for a release
  after the painter was fixed. Cell text, the row-number gutter, footer totals,
  filter text, wrapped header captions and button-cell captions all go through
  that one function, and every one of them showed `"<arabic phrase> Acme 3.0"`
  with its halves swapped while the label beside the grid showed it correctly.
  It now applies the same gate (`TyTextHasRTL`) and the same `TBidiTextLayout`,
  inside the cache-miss branch so a repeated string is laid out once rather than
  once per frame. `tests/test.grid.bidi.pas` pins both the ordering and that
  Latin and CJK never reach the layout at all — the latter has to be **counted**,
  because a bidi layout reproduces a plain text call pixel-for-pixel on
  single-run text and so pixels alone cannot see the difference.

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

- **Layout mirroring, for a form's worth of controls, its menus and its bars.** Set
  `BiDiMode := bdRightToLeft` from code (see the caveat below about it not being
  *published*) and the following now lay themselves out right-to-left. This is
  phases 0, 1, 2, 3 and 4 of `plans/2026-08-04-rtl-mirroring-scope.md`, plus §3.8,
  §3.12 and §3.14; the rest of that document is not built.

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
  | `TTyScrollBox`, `TTyScrollPanel` | the vertical bar docks to the **left** edge; the viewport, the horizontal bar and the child layout origin all start after it; the auto-pan edge bands follow |
  | `TTyListBox` and its plain descendants | the scroll bar docks to the **left**, the rows give up that side instead of the right, and the row text reads to the right edge |
  | `TTyCheckListBox` | the toggle column moves with the row: the check box is drawn at the trailing end and the zone that toggles it moves with it |
  | `TTyColorListBox` | the colour swatch moves to the right end of the row, the name to its left |
  | `TTyScrollBar` (horizontal) | **opt-in via `MirrorHorizontal`, not `BiDiMode`** — see below |
  | `TTyStatusBar` | panels tile from the right, separators sit on each panel's leading edge, and the **size grip moves to the bottom-left** — including the `HTBOTTOMLEFT` edge code it hands the OS |
  | `TTyControlBar` | the gripper column moves to each band's right; children fill leftwards and wrap on the same overflow |
  | `TTyCoolBar` | every band's own gripper moves to its right; a resize drag grows the band **leftwards**; a vertical rebar reverses its column order (its grippers stay above their bands) |
  | `TTyMenuBar` | top cells pack from the right; `RightJustify` groups pack against the left |
  | `TTyPopupMenu` (and `TTyImagesMenu` / `TTyMenuEx`) | the check/icon slot moves right, the shortcut and submenu arrow move left, the arrow turns round, the banner strip changes ends, dropdowns hang from the anchor's right, submenus cascade left, and **←/→ swap** (← opens a submenu, → returns to the parent) |
  | `TTyHeaderControl` | the whole strip: section 0 sits against the right edge, captions align right, the sort triangle and the divider move to each cell's other side, and the **hit test and the resize drag follow** — a click on the leftmost cell sorts the *last* section, and a divider is widened by dragging it left |
  | `TTyCustomTabStrip` and everything on it — `TTyPageControl`, `TTyTabSet` | the whole tab band: tab 0 is the **rightmost** and the strip packs leftwards; the close × moves to each header's left edge; the two overflow arrows swap ends and turn round; scrolling forward slides the band **right**; `←`/`→` follow the eye. The page **body** does not move (there are no left/right-edge tabs to mirror), and a page's own children are not mirrored |
  | `TTyCustomGrid`, `TTyDrawGrid`, `TTyStringGrid` | the whole column axis: column 0 sits against the **right** edge and the columns pack leftwards; the row-header gutter and its row numbers move to the right; frozen columns pin to the right and a `FixedColsRight` band moves to the left; the horizontal bar's `Position = Min` is the right end; a resize grip is a column's **left** edge and dragging it left widens the column; header captions, cell text, the sort triangle, the filter funnel, the tree chevron and its indent, rating stars, the ellipsis button, the comment mark, the pick-list arrow, the progress fill and the fill handle all change ends; `←`/`→` follow the eye while `Home`/`End` stay logical. **Every hit test follows the paint out of the same function**, so a click lands in the cell that was drawn under it. See `docs/controls/grid.md` for what does *not* move |

  **The vertical scroll bar moving to the left edge is the loudest signal a
  window gives that it reads right-to-left**, which is why the scrolling
  containers were done ahead of cheaper items.

  **A horizontal `TTyScrollBar` mirrors only when its host asks it to.** Setting
  `MirrorHorizontal := True` puts `Min` at the **right** end of the track, so a
  rising `Position` walks the thumb leftwards, the left-hand end button and the
  track left of the thumb step *up*, and ←/→ follow the thumb (`Home`/`End` stay
  logical). The painted bar is unchanged — reflecting a left arrow at one end and
  a right arrow at the other gives back the same picture, which is why a mirrored
  Windows scroll bar looks identical. It is deliberately **not** wired to
  `BiDiMode`: `TTyGrid`, `TTyListView`, `TTyMemo` and `TTyTreeView` each embed one
  and none of them mirrors its *content* yet, so a bar that read `BiDiMode` would
  put the thumb at the wrong end of the document it scrolls. `TTyScrollBox` leaves
  it off for the same reason — the children inside a box are still laid out
  left-to-right (see below), so the content's origin really is the left edge.

  The mechanism is one flag on `TTyPainter`, set at `BeginPaint`, that resolves
  every alignment the caller passes from a *reading-order* one to a physical one
  through LCL's `BidiFlipAlignment`. A control opts in by passing
  `IsRightToLeft`; everything that has not opted in is bit-for-bit unchanged.
  `grep -n "BeginPaint(.*IsRightToLeft" source/` is the authoritative list.

  The menus and bars needed a second mechanism as well, because unlike the phase-1
  batch they **hit-test internally** — a menu bar answers "which top did I click",
  a status bar "which panel is this" and "is this the size grip", a cool bar "is
  this a band's gripper". Each of those answers now comes out of the same function
  that places the thing it is answering about (`TyStatusPanelRects`,
  `TyStatusGripRect`, `TTyMenuBar.TopLeft`, `TTyCoolBar.BandRectFor`), so mirroring
  the paint without the hit test would take a deliberate second copy first.
  `tests/test.rtl.bars.pas` asserts both halves of each.

  A **menu takes its direction from its host**, not from itself: a `TPopupMenu` is
  a component with no `BiDiMode`, and the popup window is a `TForm.CreateNew` of
  ours that inherits nothing. `TTyMenuBar` hands its own `IsRightToLeft` down;
  `TTyPopupMenu` reads the control the menu was raised on (LCL records it in
  `PopupComponent`), falling back to `Owner`. The direction then propagates the
  whole way down a submenu cascade.

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
  - list-view **columns** keep their left-to-right order, and so do toolbar
    buttons, breadcrumb segments and pagination items;
  - a tree view's expander stays on the **left**, and indentation still grows
    rightwards;
  - an edit or memo keeps its text block, caret and selection anchored to the
    **left** — the *reordering* inside a line is right (see the entry on
    bidirectional carets below), but the block itself does not move to the right
    edge and the scroll bar does not change sides;
  - a `TTyDropDownButton` keeps its arrow zone on the **right**, a
    `TTyButtonGroup` keeps its segments in left-to-right order, and `TTyRibbon`
    keeps its whole tab band left-to-right even though it *is* a
    `TTyCustomTabStrip` — all three deliberately, because each reads a click's x
    back through a hit test its paint would have moved away from, and that is the
    "drawn on the right, answers on the left" defect this library has already
    shipped three times. The ribbon declines in one line
    (`TTyRibbon.HeaderRightToLeft`); its File tab, collapse chevron, KeyTip chips
    and two `X >= HeaderLeftInset` gestures all have to move in the same commit
    that deletes it. All three are pinned by `tests/test.rtl.pas`
    (`TRtlExclusionTest`), which asserts paint and hit test still agree, so
    mirroring either one alone turns red.

  Two things inside a mirrored grid also decline, for the same reason and pinned
  the same way. Its **vertical scroll bar stays on the right edge**: the grid
  paints into a viewport whose origin is x=0 and mirrors by reflecting that band
  onto itself, and docking the bar on the left would move the origin, putting the
  same added constant in front of about fifteen full-width band expressions —
  fifteen more chances to mirror fourteen. The scoping document ranks a bar on the
  wrong side as the most visible and therefore the safest omission (§5 item 7).
  Its **column-filter drop-down** does not mirror its rows either: that list pins
  a per-value count column to the row's right while the check box it inherits sits
  at the row's reading start, so mirroring would stack the two on the same side.

  The collapsed **tree and group chevrons do turn round** — that used to be listed
  here as the one glyph whose stroke stayed put while its box changed ends, and it
  no longer is. `tgChevronLeft` now exists beside `tgChevronRight`
  (`tyControls.Painter.pas`), and both of the grid's collapsed chevrons ask for it
  through one `TTyCustomGrid.DrawToggleGlyph`, so they cannot diverge again. What
  remains is smaller and worth naming: the kind→token map behind the *derived*
  `TyDrawGlyph` overload (`TyGlyphKindToken`, `tyControls.Base.pas:1140`) has no
  `--glyph-chevron-left` row, so the grid passes that token explicitly — the same
  thing `TTyCheckBox` and `TTyCheckComboBox` already do for `--glyph-check`. A
  theme can replace the mirrored chevron today (`tests/test.rtl.pas`,
  `TheMirroredCollapsedChevronIsThemeReplaceableLikeEveryOtherGlyph`); a *future*
  caller that reaches for the short overload would silently get no override until
  that one row is added.

  Two directional glyphs still have no mirror partner, deliberately.
  **`tgDialogLauncher`** points into the bottom-right corner and would want a
  bottom-left twin, but its only caller is `TTyRibbon`, which declines to mirror
  at all (above) — a partner with no caller is a shape nobody has ever looked at.
  **Scroll-bar and spin arrows are not partnered because they do not need to be**:
  an arrow at each end of a track reflects onto itself, so a mirrored bar is the
  same picture (`tyControls.ScrollBar.pas:617`), and up/down is an axis the reading
  direction does not touch. The same goes for the sort indicator and every
  expander's down-chevron.

  A right-to-left UI built on this release gets its forms — labels, check boxes,
  radio groups, buttons, panels — its tabbed containers **and its grids** the right
  way round, and its trees, list views, edits and date pickers the wrong way round.

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

- **`TTyMemo`'s caret is now visual too, so the "draws right, selects wrong" gap
  is closed.** This entry used to say the multi-line editor drew right-to-left
  text correctly but answered every caret question from a cumulative sum of
  codepoint widths taken in string order. It no longer does. `TTyMemo` builds a
  bidirectional run table **per visual row** — a row, not a line, because
  `RenderTo` draws each row as its own string and the reordering a caret must
  agree with is the row's — and answers from it: the drawn caret, the click and
  drag hit test, the `Left`/`Right` arrows, the up/down arrows' remembered
  position, and the horizontal scroll. Clicking a glyph puts the caret on that
  glyph, the arrows move one glyph the way the key points, and a drag reports the
  range between the two positions it actually touched.

  Two consequences worth knowing rather than discovering:

  - a selection that crosses a direction boundary is painted as **more than one
    band**, because a contiguous *logical* range is not a contiguous *visual* one.
    Sweeping the pointer across mixed text can therefore highlight glyphs it did
    not pass over and skip glyphs it did — that is the range between the two
    endpoints, and it is what every other editor does;
  - `Home` and `End` remain **logical** ends, so on a right-to-left line `Home`
    puts the caret at the right of the ink. Only `Left`/`Right` are visual.

  What is still **not** done is the mirroring half, exactly as for `TTyEdit`: the
  memo's own scroll bar, margins and alignment do not flip, and the trailing
  strip that marks a selected line break is drawn at the row's right edge in
  either direction. Guards live in `tests/test.memo.bidi.pas`.

  Neither control calls `TTyPainter.TextCaretX` / `TextCharIndexAtX`, and the
  reason is worth recording: those lay out on the painter's `FBmp`, which exists
  only between `BeginPaint` and `EndPaint`, while a caret is queried from mouse
  handlers, key handlers and the blink timer; and `TextCaretX` answers with
  `TBidiTextLayout.GetCaret`, which resolves a direction boundary towards the run
  that *ends* there and discards the other position — so the far end of an
  embedded run is unreachable through it. Each control therefore lays its own
  line (or row) out and caches the result, and both duplications are pinned:
  `test.edit.bidi.EditCaretAgreesWithThePainterForUnambiguousIndices` and
  `test.memo.bidi.MemoCaretAgreesWithThePainterForUnambiguousIndices` require the
  control's answer to equal the painter's for every index the painter can
  express, so the two cannot drift apart in silence.

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
