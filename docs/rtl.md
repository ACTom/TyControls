# TyControls — 双向文本与右到左布局

> English readers: this document is written in the same mixed register as the rest of
> `docs/` — headings and code in English, prose in Chinese, matching its neighbours.

本文件描述**当前真实状态**,不是路线图。每一条"能用"的都有守卫钉着;每一条"还不能用"的
都是有意的边界,不是遗漏。逐控件的细节在各自的 `docs/controls/*.md` 里,本文件只讲跨控件的部分。

镜像工作的分档与剩余代价见 [`plans/2026-08-04-rtl-mirroring-scope.md`](../plans/2026-08-04-rtl-mirroring-scope.md);
想亲眼看的话跑 [`examples/rtl`](../examples/rtl/) —— 那个 example 存在的理由就是
**测试在结构上够不到的那些东西**(GTK/Cocoa 上的字形整形、size grip 交给 OS 的边码、
子菜单级联方向、LCL 对齐引擎、各 widgetset 的输入法)。

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
  phases 0, 1, 2, 3 and 4 of `plans/2026-08-04-rtl-mirroring-scope.md`, plus §3.7,
  §3.8, §3.9, §3.12, §3.14 and §3.15; the rest of that document is not built.

  **`TTyTitleBar` is in the table but not in that document**, which never mentions
  the window chrome — as a phase, as a cost, or as an exclusion. It was simply not in
  the surveyed set, which is how an application ended up mirroring everything inside
  its window and nothing around it.

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
  | `TTyTitleBar` (and the `TTyForm` chrome around it) | the whole window frame: the caption moves to the **right**, the caption-button cluster to the **left**, and the cluster **reverses** — Close takes the window corner, then Maximize, then Minimize, so the sequence still reads minimize / maximize / close in the direction the window reads. The strip the buttons reserve and the content zone a host's own children get change ends with them. See below for the two things that deliberately do not move |
  | `TTyStatusBar` | panels tile from the right, separators sit on each panel's leading edge, and the **size grip moves to the bottom-left** — including the `HTBOTTOMLEFT` edge code it hands the OS |
  | `TTyControlBar` | the gripper column moves to each band's right; children fill leftwards and wrap on the same overflow |
  | `TTyCoolBar` | every band's own gripper moves to its right; a resize drag grows the band **leftwards**; a vertical rebar reverses its column order (its grippers stay above their bands) |
  | `TTyMenuBar` | top cells pack from the right; `RightJustify` groups pack against the left |
  | `TTyPopupMenu` (and `TTyImagesMenu` / `TTyMenuEx`) | the check/icon slot moves right, the shortcut and submenu arrow move left, the arrow turns round, the banner strip changes ends, dropdowns hang from the anchor's right, submenus cascade left, and **←/→ swap** (← opens a submenu, → returns to the parent) |
  | `TTyHeaderControl` | the whole strip: section 0 sits against the right edge, captions align right, the sort triangle and the divider move to each cell's other side, and the **hit test and the resize drag follow** — a click on the leftmost cell sorts the *last* section, and a divider is widened by dragging it left |
  | `TTyCustomTabStrip` and everything on it — `TTyPageControl`, `TTyTabSet` | the whole tab band: tab 0 is the **rightmost** and the strip packs leftwards; the close × and the tab icon move to each header's other edge; the two overflow arrows swap ends and turn round; scrolling forward slides the band **right**; `←`/`→` follow the eye. With `TabPosition = tpLeft`/`tpRight` the mirror is a **change of edge, not of order**: the reflection is applied to the screen's x axis, which for a side band is the band's *minor* axis — so a `tpLeft` band moves bodily to the **right** edge (and the page body's inset moves with it), the close × and icon swap ends within each row, but the rows keep their top-to-bottom order and `↑`/`↓` keep their meaning. Reflecting x cannot reorder a run that goes down the page — the same rule that keeps `Home`/`End` logical. A page's own children are not mirrored |
  | `TTyCustomGrid`, `TTyDrawGrid`, `TTyStringGrid` | the whole column axis: column 0 sits against the **right** edge and the columns pack leftwards; the row-header gutter and its row numbers move to the right; frozen columns pin to the right and a `FixedColsRight` band moves to the left; the horizontal bar's `Position = Min` is the right end; a resize grip is a column's **left** edge and dragging it left widens the column; header captions, cell text, the sort triangle, the filter funnel, the tree chevron and its indent, rating stars, the ellipsis button, the comment mark, the pick-list arrow, the progress fill and the fill handle all change ends; `←`/`→` follow the eye while `Home`/`End` stay logical. **Every hit test follows the paint out of the same function**, so a click lands in the cell that was drawn under it. See `docs/controls/grid.md` for what does *not* move |
  | `TTyListView` and `TTyShellListView` | in report mode the whole column axis: column 0 sits against the **right** edge, the header cells and the grid rules follow it, a resize grip is a column's **left** edge and dragging it left widens the column, the sort triangle and any column icon move to each cell's reading start, and the row's check box and icon move with them while the caption steps aside. In the four flow styles (icon, small icon, tile, list) the cells tile from the **right**, and a `lvsList` column packs its first track against the right edge; grouped layouts reflect with them. Marquee selection follows the cells. `←`/`→` follow the eye — `→` steps to the item drawn to its right, i.e. the *earlier* one — while `Home`/`End`/`PageUp`/`PageDown` stay logical |
  | `TTyTreeView` and `TTyShellTreeView` | the column axis exactly as the list view's, plus the chrome inside the main cell: the indent grows **leftwards** from the cell's right edge, and the expander, check box, icon and caption follow it in that order. The **connecting tree lines move with the indent** — ancestor guides, the elbow and its stub all come out of one function, because a tree whose nodes mirror and whose lines do not is worse than one that does neither. The inline editor lands on the caption rather than across the chrome. `←`/`→` **swap**: `←` expands a node and `→` collapses it, because the children are drawn towards the left |
  | `TTyDateTimePicker` | the whole field: the button column (chevron or spin arrows) takes the **left** edge, the text box takes what is left, the check box moves to the text box's reading start at its **right**, and the drop-down calendar hangs from the anchor's right. The spin halves do **not** turn over — up/down is an axis the reading direction does not reach. `←`/`→` **swap**, because they step between *fields* (year → month → day) and not between characters; `Home`/`End` stay logical. All four slot groups and both hit tests come out of one `TyDateTimeRects` record, reflected once at the end, so the paint and the click cannot take different sides. The digits themselves are not reordered — see below |

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
  `BiDiMode`: a bar must never mirror ahead of the content it scrolls, so each host
  sets it *for* its own bar once that content mirrors. `TTyGrid`, `TTyListView` and
  `TTyTreeView` now do; `TTyMemo` does not, because its text block still does not
  move. `TTyScrollBox` leaves it off for the same reason — the children inside a box
  are still laid out left-to-right (see below), so the content's origin really is the
  left edge.

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

  **The window chrome is the same shape again, and it is the first thing a viewer
  sees.** A right-to-left application used to get its whole client area mirrored and
  its frame left alone. `TTyTitleBar` now follows, through `TyCaptionLayoutFor` — one
  pure function returning the three button boxes, the strip they reserve and the
  content zone in one record, mirrored by a single reflection over all of them
  (`BidiFlipRect`, the same lever `TyStatusPanelRects` uses). It had to be one
  function because the bar held **two** independent claims about which side the
  buttons are on: `LayoutButtons` packed them from `ClientWidth` leftwards, while
  `RightInset` restated the same cluster as a width that `AdjustClientRect` and
  `CaptionSpan` subtracted from the right. The buttons themselves need no separate
  hit test — they are windowed children, so LCL routes every click, hover and press
  by the very bounds `LayoutButtons` writes. `tests/test.rtl.chrome.pas` sweeps every
  device x across the bar and requires the routing to name the button the layout drew
  there, in both directions.

  **Why the cluster reverses rather than sliding across as a block.** Windows mirrors
  the entire non-client area of a right-to-left window (`WS_EX_LAYOUTRTL`), which puts
  Close in the window corner, then Maximize, then Minimize. Read in the direction the
  window reads, that is still minimize → maximize → close: the same sequence, read the
  other way. A block move without the reversal would put *Minimize* in the corner and
  Close in the middle, an order no platform has.

  `RightInset` keeps its name although it now measures a strip at the **left** edge of
  a mirrored bar. Renaming a public member is a breaking change for a gain the
  documentation can give instead — the same call §6.3 of the scoping document makes
  for `Divider.LeftIndent` and `Columns[].Left`.

  A **menu takes its direction from its host**, not from itself: a `TPopupMenu` is
  a component with no `BiDiMode`, and the popup window is a `TForm.CreateNew` of
  ours that inherits nothing. `TTyMenuBar` hands its own `IsRightToLeft` down;
  `TTyPopupMenu` reads the control the menu was raised on (LCL records it in
  `PopupComponent`), falling back to `Owner`. The direction then propagates the
  whole way down a submenu cascade.

  **A shared drop-down takes its alignment edge from its host.** `TyPopupRect` grew an
  `ARightToLeft` argument that moves which edge of the popup meets the anchor — right
  to right instead of left to left — and `TTyDropdownPopup.Popup` passes it through and
  remembers it, so a later in-place `Resize` re-anchors to the same edge. It defaults to
  the unmirrored edge, so every other caller (the combo boxes, the autocomplete lists)
  is byte-identical; `TTyDateTimePicker` is the first host that asks for it. The
  vertical flip-above branch is untouched, because up/down is a different axis.

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
  - toolbar buttons, breadcrumb segments and pagination items keep their
    left-to-right order;
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

  **`TTyListView` and `TTyTreeView` keep their vertical bars on the right for
  exactly the grid's reason**, and are pinned the same way: each reflects about the
  band it paints into (the list view's viewport, the tree's content rect), and that
  band already stops short of the bar's gutter. Moving the bar means moving the axis,
  so `TRtlExclusionTest` asserts the bar's edge and the axis together — whoever moves
  one has to move the other in the same commit. Both controls' **descendants**,
  `TTyShellListView` and `TTyShellTreeView`, mirror with their bases rather than
  opting out, because neither derives an x of its own: they replace data accessors
  (`GetItemCount`/`GetItemText`/… and `DoGetText`/`DoInitNode`/…) and, on the shell
  list, a column-*width* distribution, which is direction-free. That is the question
  to ask of any new descendant, and `BothShellDescendantsMirrorBecauseNeitherDerivesAnXOfItsOwn`
  is where the answer is recorded.

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

  **The native window edge codes do not mirror, and that is not an omission.**
  `HTBOTTOMLEFT` and `HTBOTTOMRIGHT` name real window corners: a window's bottom-left
  corner is its bottom-left corner in either reading direction, and a right-to-left
  window that resized from the mirror image of the corner the pointer grabbed would be
  unusable. `TyNcHitTest` / `TyResolveNcHit` therefore take no direction argument at
  all, exactly as `TTyStatusBar.ResizeHitAt` already decided for the plain bottom-edge
  strip beside its size grip. Pinned by `tests/test.rtl.chrome.pas`
  (`NativeWindowEdgeCodesAreNotMirrored`).

  The caption band those functions hand the OS is likewise **x-independent** — a
  height, not a set of button boxes; the whole top strip answers `HTCAPTION`. The
  caption buttons are windowed children the OS routes to by their own HWNDs, so a
  caption button's x has never been reported to the OS and mirroring the cluster needs
  no second copy of its geometry kept in step. `TheCaptionBandHandedToTheOsIsXIndependent`
  pins that, so a later commit tempted to teach the mapper about the buttons has to
  face the decision rather than walk past it.

  **The restore glyph does not turn round.** `cbkRestore` draws two overlapping
  rectangles with the back one to the top-**right** (`tyControls.Painter.pas`,
  `tgRestore`), and a mirrored window on Windows would put it top-left. There is no
  `tgRestoreLeft` to ask for. This is a glyph, not a geometry: the paint and the hit
  test cannot come apart over it, because the glyph is centred in a box whose position
  both halves take from `TyCaptionLayoutFor`. Closing it means adding one glyph kind
  beside `tgChevronLeft`, in the same shape that one was added.

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
  radio groups, buttons, panels — its tabbed containers, its grids, its list views,
  its trees, **its date pickers and its window frame** the right way round. Its text
  editors read and select correctly but do not mirror their own layout (the scroll
  bar stays on the right).

  **The date picker's own string is not reordered, and that is the boundary rather
  than an omission.** A date is digits and separators, which are left-to-right runs
  in any paragraph, so a mirrored picker draws `15 September 2026` in that order and
  only the *boxes* move — which is what a native mirrored picker does too. Put a
  right-to-left literal or month name in the format and the painter routes the string
  through `TBidiTextLayout`, which reorders the runs, while the picker measures field
  positions by **prefix width**, which does not. The consequence is worth stating
  precisely: the highlight and the hit test still agree with **each other** in either
  direction — they read one origin and one measurement, and
  `tests/test.rtl.pas` (`BidiTextDoesNotSplitThePaintFromTheHitTest`) requires it —
  but neither follows the reordered glyphs. That is the segment-order-under-bidi
  item; it is unchanged by mirroring, it was equally true left-to-right before, and
  closing it means giving the picker a run table per field the way `TTyEdit` and
  `TTyMemo` have one per line and per visual row.

- **Containers do not mirror their children's `Align`/`Anchors` layout**, and this
  is not a gap to be closed. LCL's own align engine has no BiDi branch outside the
  `ChildSizing` *table* path (`wincontrol.inc:1551`, which `TTyPanel` republishes
  and therefore gets for free), so mirroring ours would make a ty container behave
  differently from every native container beside it and misplace any ported
  `.lfm`. `Home`/`End`/`PageUp`/`PageDown` are likewise never flipped: they are
  logical ends, not visual ones.

  **A title bar is a container too**, and this is where a viewer meets the rule
  first: a theme picker or menu bar a host has anchored into the bar keeps the side
  it was anchored to. What the bar *does* do is keep the caption clear of it — the
  caption takes the widest contiguous gap those children leave inside the mirrored
  content zone, so it is never drawn underneath them and never underneath the
  caption buttons. `examples/rtl` shows exactly this: flip the direction and the
  window's buttons change corner while the two controls in its title bar stay
  anchored where the `.lfm` put them.

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
