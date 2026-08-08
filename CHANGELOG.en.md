# Changelog

All notable changes to **ty-controls** are documented in this file. The project uses
3-part semantic versions (`MAJOR.MINOR.PATCH`). Every control is fully custom-drawn via
BGRABitmap and themed by lightweight `.tycss` text themes — pixel-identical on Windows,
Linux and macOS.

> 中文版见 [CHANGELOG.md](CHANGELOG.md)。

## [Unreleased]

### Fixed -- the visual round

- **An editable combo box drew TWO frames** and the chevron fell between them. The arrow had not
  moved at all: measured on a screenshot, its ink ends 3px from the outer frame in BOTH styles.
  What differs is that the editable style puts a real edit over the text zone, and that editor
  was painting its own field frame inside the combo's -- so the chevron sat in the strip between
  an inner box and the outer border, 10px of air on its left and 3px on its right.
- **Spin buttons, scroll-bar end arrows and tab-strip scrollers draw a filled TRIANGLE** now,
  not a line arrow. That is the split Windows itself makes: a triangle to STEP or SCROLL (the
  spin theme part is a solid 5x3 triangle, and the native tab control scrolls with that same
  part), a chevron to DISCLOSE. The "icons squeezed against the border" half was the glyph pad,
  which ate 9px per axis and left a 9x5 ink box in an 18x14 button half.
  **Breaking for theme authors only:** a spinner's override token is now
  `--glyph-triangle-up/down`, not `--glyph-arrow-up/down`. No shipped theme sets either, so
  nothing in the tree changes.
- **A menu button's drop mark** is the same chevron the drop-down button, the toolbar and every
  combo-family field draw, instead of its own hand-rolled triangle.
- **The track bar had no groove -- it WAS the groove.** It filled its whole client rect with
  `--surface-track`, which is why it read as a darker slab on every theme and as a neutral grey
  slab on aero, whose surface is blue; and the tick marks, drawn inside that same rect, sat ON
  the track. Now the control paints no background and inherits the surface it sits on, the
  recess is a thin centred band (a new `TyTrackGroove` key), and the ticks get a band of their
  own on whichever side `TickMarks` names. aero also wires `--surface-track` to the `--track`
  colour it already had and used only for the progress bar.
- **Trailing widgets sit in one place now.** A combo box hangs its button zone on the frame,
  while everything built on the edit's trailing-widget seam measured from the PADDED content
  box -- so the same 9px chevron was 3px from the border in a combo box, 7 in a `TTyComboEdit`,
  6 in a spin edit, 10 in a calc edit and 12 on a menu button. One definition now, shared by the
  painter and the hit test (they were two independent copies of the formula).
- **`window-shadow: false` let the Windows Classic caption flash back** over the custom chrome
  whenever the window was deactivated (reported on the forum). Turning the shadow off disables
  DWM non-client rendering for the window, and Windows then falls back to LEGACY non-client
  painting, which does not go through the suppression that was already in place.

### Added — data grid `TTyStringGrid`

- **Three layers**: `TTyCustomGrid` (geometry/painting/theming) → `TTyDrawGrid` (content supplied
  by the host, virtual by construction) → `TTyStringGrid` (sparse storage + editing + organising).
  Migrating from `TStringGrid` costs almost no learning.
- **What you can see**: frozen rows/columns, a million rows without lag (only the visible window is
  painted), a 2-D cursor with rectangular multi-select, variable row heights, click-to-sort,
  per-column value filtering from the header, collapsible group rows, cell merging, a summary
  footer (**over the filtered rows only**), `Ctrl+C/V` interop with Excel, CSV import/export,
  column resize and drag-reorder.
- **Cells can hold things**: checkbox, pick-list, date, colour, progress bar, rating, image —
  display is **orthogonal** to editing (a column can render as a progress bar and still edit as a number).
- Example: [examples/grid](examples/grid/).

- **Spreadsheet-grade keyboard feel**: typing a printable character starts editing
  (and becomes the first character, like Excel), Enter moves down, Tab moves by cell
  and wraps at the end of a row. Previously you had to press F2 or double-click first,
  and Tab threw focus out of the grid entirely.
- **Multi-column sorting**: Shift+click a header to add a secondary key, with rank
  badges in the header. Sort kind is now **per column** (text / numeric / date), and
  blanks can go first or last -- staying put when the direction flips.
- **Typed filters**: contains / equals / starts with / ends with / greater / less...
  Previously "contains" was the only option, so filtering a numeric column for >1000
  was simply impossible. The funnel lights up on columns that are actively filtering.
- **Grouped headers**: a band of titles spanning several columns. Sort and filter
  buttons only appear on the leaf level, so clicking a group title no longer sorts
  some column underneath it.
- **Discrete multi-select** (Ctrl+click) and drag-select; selection aggregates
  (`SelectionSum/Avg/Min/Max`) for the "12 selected, total 3400" status line.
- **Per-cell appearance**: one `OnGetCellStyle` hook covering background, text colour,
  font and both alignments; plus **persistent** `CellColors[c,r]`, per-cell borders
  (four independent pens, for report block rules), zebra striping, and a visible
  distinction between the focused cell and the selection.
- **Word wrap and row heights**: wrapping cell text, drag-to-resize row dividers,
  `AutoFitRow`, and global min/max guards.
- **Column-level declarations**: editor kind, read-only, pick list, allowed characters,
  max length -- **configurable at design time with no event handlers**. Per-cell
  read-only is supported too.
- **Host-supplied editors** via `OnCreateEditLink`, an escape hatch for editing needs
  the grid cannot anticipate.
- **Explicitly hidden rows**, distinct from filtering: a filter is a condition, hiding
  is a fact, and clearing filters no longer un-hides them.
- Bulk row/column operations (insert/remove many, move, swap) and a full event family
  (cell-level mouse, column/row sizing during and after the drag, column move,
  check boxes, clipboard).
- **Undo / redo** (Ctrl+Z / Ctrl+Y): more than the text comes back -- fill colour,
  text colour, read-only, merge spans, row heights, a whole-table clear and a CSV
  import all revert together. **One bulk operation is one press**: pasting a block,
  cutting a block, inserting or removing several rows, colouring a selection,
  auto-fitting every row, clearing all merges. `UndoLimit` defaults to 100 (0 turns
  it off). An oversized record is discarded whole and the stack cleared -- half a
  record restores a table that never existed, which is worse than "this one cannot
  be undone".
- **Sorting can actually move the data**: with `SortMode := gsmData`, clicking a
  header physically permutes the rows the way Excel does (text, per-cell
  attributes, row heights, hidden flags and merge spans all travel together). Display
  order then equals data order, so the "no merging / no row dragging once sorted"
  restrictions lift by themselves. It falls back to the previous behaviour as soon as
  a filter, a grouping or a virtual data source is in play (moving filtered-out rows
  along would corrupt data). Physical sorting **is undoable**.
- **Multi-level grouping**: `GroupByColumns([province, city])` indents by level;
  subtotals are computed per level (a row counts towards all its ancestors); the
  collapsed state is keyed by **path**, so "Springfield" under two different states
  collapses independently. Single-column grouping is the degenerate case of the same
  implementation.
- **Dragging rows with the mouse**: press in the indicator gutter and drag past the
  threshold to reorder (symmetric with dragging column headers). `OnRowMove` can veto;
  the row-height divider wins the gesture; dragging is refused while sorted, grouped
  or with hidden rows -- when display order is not data order, dropping a row at a
  screen position means nothing, since the sort puts it straight back.
- **Layout persistence**: `SaveLayoutToString` / `LoadLayoutFromString` carry column
  widths, order, visibility, sort keys and freeze counts; where to keep the string is
  the host's choice. Loading is **all or nothing** -- the whole string is validated
  before anything is touched, because half a restored layout is harder to diagnose
  than none.
- **Editor details**: the editor widens itself on narrow columns (`MinEditorWidth`,
  without changing the column or crossing the right edge), drop-down width is
  configurable per column (`TTyGridColumn.DropDownWidth`), and `OnGetEditorProp` hands
  the host the actual editor control for a quick font or length tweak -- no need to
  write a whole `OnCreateEditLink` for that.
- **Colouring a selection**: `SetSelectionColor` / `SetSelectionTextColor` apply to the
  whole selection as a single operation (hosts previously had to write the loop
  themselves, and undo then came off one cell at a time).
- **Inline filter row**: a band under the headers with one input per column; type
  and that column filters. Understands `>1000`, `<=5`, `<>east`, `300..600`, and
  `;` between several conditions means **or**. It filters as you type (once you
  stop), Enter applies at once, Escape abandons the edit. It is a band, not a data
  row -- row counts, addressing and export are unaffected.
- **Tree cells**: one column can show hierarchy (indent + a chevron), and
  collapsing folds the children away. **The host supplies the parent/child
  relation** (`OnGetNodeLevel` / `OnGetHasChildren`) -- the control holds no tree,
  so a million-node tree needs no up-front construction inside it.
- **Adding, removing and reordering columns are undoable now**, and the column
  comes back whole: width, title, alignment, editor kind, read-only, pick list,
  and the filter that was on it. Column structure previously could not enter the
  undo stack at all, so any column change simply cleared it.
- **An object slot on every cell**: `Objects[ACol, ARow]` -- "which record is this
  row?" finally has somewhere to live. It travels with its cell: sorting (including
  the physical sort that really moves the data), inserting and deleting rows, moving
  and swapping them -- the object stays on its row. Hosts previously had to keep a
  parallel array keyed by row index and re-align it after every structural change,
  and the symptom of getting that wrong is reading somebody else's record after a
  sort, silently. **The grid does not own these objects** (never frees, copies or
  persists them), and they **do not enter the undo stack** -- restoring one would let
  Ctrl+Z hand back a pointer you may already have freed.
- **A whole row or column as a `TStrings`**: `Grid.Rows[3] := MyList`,
  `Memo.Lines := Grid.Cols[2]`, `Grid.Rows[r].CommaText` -- lines that appear in
  nearly every ported program, and that previously had to be rewritten as per-cell
  loops. What you get is a **live view**: reads and writes land on the cells
  directly. **Assignment never changes the grid's structure** (a shorter list leaves
  the tail alone, a longer one is truncated), matching LCL exactly.

### Fixed -- this round of user and forum reports

- **A click on a radio item moved the dot but not the focus ring** — you had to click twice.
  Two correct rules collided: the group gives TabStop only to the CHECKED item (as LCL does),
  and the base class uses TabStop to decide whether a click takes focus — so the only item a
  click could focus was the one already selected. LCL escapes this because its children are
  native radio buttons and Windows focuses a clicked control regardless of TabStop.
- **Every row in a radio/check group overlapped the one above it.** The pitch came from
  `--row-height` (22) while a hosted item's own minimum height is 25, and LCL clamps every
  SetBounds up to the minimum — so rows overlapped by 3px, and the lower row (a later sibling,
  higher in the z-order) painted over the bottom of the focus ring above it. The last row had
  nothing below it, which is why it alone looked right.
- **Children erased the bottom border of CoolBar / ToolBarEx / ControlBar** — layout used a
  client rect that was not inset by the painted frame.
- **The CoolBar gripper resized the wrong band.** A real rebar gripper moves the BOUNDARY with
  the neighbour to its left; ours resized the dragged band itself. A row's first band has no
  boundary, so the gesture becomes a move, as in LCL.
- **CoolBar bands can be reordered now** — drag past a neighbour to swap, below the last row for
  a row of its own. The code's claim that this was impossible was wrong:
  `TWinControl.SetControlIndex` places a child anywhere in its parent's list, and the packer
  reads that list, so moving the child IS the reorder.
- **Scroll box: flicker while dragging the thumb, and content that did not follow.** The bar's
  position was computed by TWO formulas that disagreed by the border width, so every scroll step
  moved both bars and moved them back, each SetBounds re-entering the align pass — 12 drag steps
  cost 120 align rounds, now 24. Separately, when a viewport exists the content lives in the
  viewport while the scroll-origin hooks sat on the outer box: aligned children inside a viewport
  did not move at all.
- **`goHeaderPushedLook` and `goThumbTracking` now work.** The latter can also be set per axis:
  `Grid.VScrollBar.LiveTracking := False`.
- **Ctrl+X on the grid** — the gesture never existed, only the public method.
- **Grid-panel cells showed the system background under a gradient theme**: `TTyGridCell.Paint`
  was empty AND it borrowed the data grid's theme key, which is transparent by design. It has
  its own key now and inherits the parent's painted background — not a flat fill, which would
  have flattened every gradient.
- **Bevel highlights glowed on dark themes** — the blend pushed 55% toward white in both modes.
- **A split drop-down button showed no divider under the default flat style**, making
  `tbsDropDown` indistinguishable from `tbsButtonDrop` while behaving differently: the rule is
  inked with the border colour, and a flat toolbar puts every tool in the `ghost` variant, whose
  border colour is fully transparent.
- **The drop arrow was drawn one padding away from where it was hit** — at the default padding
  the drawn divider and some six pixels of drawn arrow ran the PRIMARY action. Both now read one
  pure function.
- **`TyForm { window-shadow: false; }` never removed the shadow** — see the previous section.
- **Per-monitor DPI: dragging to a high-DPI screen and back left the layout wrong forever.**
  Six controls write their size floor in device pixels, and LCL scales the same Constraints
  again, so one crossing applies it TWICE: a button went 29 → 175 → **70**. The floor is no
  longer recomputed during the DPI pass and is re-derived once on the settled PPI, so a round
  trip restores the layout exactly. It also cut the synchronous pass by 42%, because the double
  application was double caption MEASURING.
- **42 examples shipped with no manifest at all** — every `.lpi` set `UseXPManifest`, but only 4
  `.lpr` files linked the project resource, so the rest had neither common-controls v6 nor any
  DPI-awareness declaration.

### Added

- **`TTyToolBar.HotImages` / `DisabledImages`** — a different GLYPH on hover/disabled (per-state
  colour has always been the theme's job). Keyed by name, and consulted only when the tool is
  already drawing the bar's own collection and the alternate contains that name.
- **`TTyScrollBar.LiveTracking`** — with it off, dragging the thumb moves only the thumb and the
  position commits on release.
- **`TTyForm.StyleOverride`** — a form can take a runtime CSS snippet over its own chrome, the
  way every other control can.

### Added -- a new control: `TTyFloatSpinEdit`

- **The decimal spin edit**: `Value: Double`, `Decimals`, `Increment` (**may be below 1** -- a
  0.25 step is the point of its existence; a step finer than `Decimals` looks inert, and the
  docs say so). Sibling of the integer `TTySpinEdit`, not its child: it derives from
  `TTyNumericEdit`, so selection / clipboard / undo / IME come along, and thousands grouping
  defaults **off** (as in LCL). On the `TyControls Edits` palette page -- 162 droppable
  controls now.

### Added -- the second and third waves of parity

- **The grid's `Options`**: LCL's ~32 behaviour flags behind one Object Inspector entry.
  21 made the set (9 of them are **views** onto existing named properties -- one state, so the
  designer and code can never disagree), 11 are omitted each with its reason -- the full
  census table is in [docs/controls/grid.md](docs/controls/grid.md).
- **The toolbar finally has a button type system**: `TTyToolButton` with all six styles
  (button / check / drop-down / grouped / separator / divider), `Grouped` grouping adjacent
  buttons, `ImageIndex` stored as `ImageName` (re-ordering the image collection can no longer
  silently swap a button's icon). The bar itself gains `ButtonWidth` (a **floor** -- lowering
  it restores designed widths), `DropDownWidth`, `List` (icon beside caption; our default is
  the opposite of LCL's, because stacked layout collapses captions to zero height here --
  documented), and `OnPaintButton`, a whole-button owner-draw hook.
- **Horizontal scrolling in list boxes**: `ScrollWidth` plus a bottom scroll bar -- an item
  wider than the box can finally be read. The same work opened a **per-row height** seam, which
  is what let the combo box gain `csOwnerDrawVariable` / `csOwnerDrawEditableVariable` +
  `OnMeasureItem`, and **`csSimple`** -- the permanently visible list under the field, no
  popup, no arrow, semantics measured against Win32 item by item.
- **Multi-row tab strips**: `MultiLine` / `RaggedRight` / `RowCount` -- tabs that no longer fit
  fold into rows instead of hiding behind scroll arrows; side bands become multiple columns.
  `ScrollOpposite` is deliberately not built (it collides with drag-reorder; the plan has the
  full reasoning).
- **The dock surface on four containers**: `TTyPanel` / `TTyGroupBox` / `TTyPageControl` /
  `TTyControlBar` all publish `DockSite` and the nine dock members -- verified per site with a
  **real mouse drag**, not just `ManualDock`.
- **Image collections stream into the `.lfm`**: `TTyImageCollection.Images` is a published
  collection of name + PNG (base64 -- diffable and reviewable; **not** LCL's binary
  pseudo-property, which the IDE cannot re-open). Repeating a name = **multi-resolution
  masters**; HiDPI picks the smallest that covers instead of stretching one.
- **Calendar and date-picker month/weekday names follow the app language**: under `--lang=en`
  no more Chinese month names on an English UI. Precedence = explicit override > loaded
  translation > OS locale, and **a program that loads no catalogue keeps today's OS behaviour
  -- zero regression**. Note: an English deployment ships the nearly-empty `tycontrols.en.po`
  (its language sentinel is the switch); the README explains.
- **Value list editor**: `KeyOptions` (editable keys / Insert adds / Ctrl+Delete removes /
  `keyUnique` deduplicates among **siblings**) plus a writable `Keys[]` (LCL's shape:
  programmatic writes skip the uniqueness check).
- **The panel caption's vertical axis**: `TTyPanel.VerticalAlignment` (LCL's type and
  default) -- the caption can sit top or bottom instead of forever colliding with children in
  the middle.

### Fixed

- **`TyForm { window-shadow: false; }` never actually removed the shadow.** The property was read,
  merged and timed correctly all along; it died at the last step: a resizable TTyForm keeps a real
  DWM frame, and a frame's shadow has nothing to do with `DwmExtendFrameIntoClientArea` margins --
  which is exactly what the old code zeroed in order to switch it off. The real switch is
  `DWMWA_NCRENDERING_POLICY`. Two things came with it: turning NC rendering off exposed a ring of
  classic GDI frame on the left, right and bottom (now swallowed, edge resizing unaffected), and
  **fixed-size windows had never had a shadow at all** (the glass extension is inert for them) --
  they do now.
- **`TTyForm.StyleOverride`**: a form can take a runtime CSS snippet over its own chrome, the way
  every other control can -- `Form.StyleOverride := 'window-shadow: false; border-radius: 0;'`
  applies immediately, so nobody needs a whole theme to change one window. It reuses the controls'
  own parse-and-merge machinery (one parser, not a fork); the form's seven separate style
  resolutions now route through it.


- **Toggling dark on aero produced a half-black, half-white window** (the user's screenshot):
  aero defines only 19 typeKeys and everything else falls back to the base layer; its
  `@mode dark` was a verbatim copy of light that never pinned the base mode seeds, so its own
  controls stayed light while the fallbacks went black. **aero now has a real dark-glass
  palette** (the deep blue-black of Win7's dark colorization), and **classic pins "no dark
  mode"** (Win95 has no such thing -- the toggle keeps the whole window as-is). A new guard
  sweeps all 17 themes in both modes: form background and fallback surfaces must agree in
  luminance and body ink must clear 60 luma of contrast, so this class of mixed window cannot
  ship again.
- **On the aero theme, every windowed control drew opaque black corner notches** -- and the
  painter was innocent: a gradient-backed form never sets `Color`, which idles at `clDefault`,
  and that reads as RGB that IS pure black -- exactly what children received when rebuilding
  the parent background. Gradients now slice onto the child's own span.
- **A read-only grid could still be modified three ways**: `ReadOnly` guarded seven editor
  paths and neither **paste, cut, nor the fill handle**. Paste is refused whole, cut degrades
  to copy, the fill handle vanishes; **per-cell / per-column locks now govern filling too**
  (the arithmetic ladder numbers by position across a locked cell). And the grid's clipboard
  set gains **Ctrl+X** alongside Ctrl+C/V.
- **The checkbox's localized truthy word never worked in a real program** -- it was copied
  from its resourcestring during unit initialization, before any catalogue loads. It resolves
  live now; typing the localized word into a Chinese sheet really ticks the box.
- **A toolbar button truncated to "Ne..." in English while the wider Chinese caption fit** --
  `AutoSize` measured with one text engine and the painter ellipsised with another. They share
  one now.
- **The Ribbon's File tab is finally translatable** (its type was wrong, so the form translator
  could not reach it; its default also moves from a hardcoded Chinese literal to English -- a
  property default that followed the locale would make saved `.lfm`s locale-dependent, so the
  default stays a literal and translation goes through the catalogue).
- **All 43 examples' code-composed text is translatable** (~740 entries), whole-window
  consistent under `--lang=en` and zh_CN; the maintenance tools
  `scripts/example-rsj2po.py` / `check-example-po.py` ship with the repo.

### Added -- the walls people hit first when porting from LCL

- **A node object model on the tree**: `Tree.Items.AddChild(nil, 'Root')` compiles and
  runs, along with `Add` / `AddFirst` / `AddChildFirst` / `Insert` / `DeleteItem` /
  `TopLvlItems[]`; a node's caption reads back as `Tree.NodeText[Node]`. At design time
  the `Items` ellipsis in the Object Inspector (or a double-click on the control) opens a
  node editor, and the tree's shape is visible in it. **The virtual mode is untouched**:
  leave `Items` empty and it is the same million-node tree as before, not one byte
  heavier. Filling in both sides (say `Items` AND an `OnGetText` handler) **raises at
  once and names both** -- quietly preferring either one turns into "my event stopped
  firing" or "the nodes I filled in at design time are gone at run time".
- **Tabs on any edge, with icons**: `TabPosition` takes top/bottom/left/right, and
  `Images` + a per-page `ImageIndex` puts a glyph on each tab. Side tabs do **not**
  rotate their captions -- a 28px rail cannot hold a line of text; the band becomes a
  stack of full-width rows sized to the widest caption, which is what modern tab rails
  do.
- **Owner-drawn combo boxes**: `Style` gains `csOwnerDrawFixed` and
  `csOwnerDrawEditableFixed`, with `OnDrawItem` for painting each row (and, for the
  first of those, the closed field). **With no handler attached the themed default still
  paints**, so setting `Style` alone can never blank the control.
- **The mask edit speaks LCL's mask language**, and **the caret can sit in any slot** and
  overwrite it in place -- previously entry was append-only, left to right, and only the
  last character could be deleted.
- **The date picker can say "not filled in"**: `NullInputAllowed` lets the user clear the
  field with Del or Ctrl+N, `NullDate` is LCL's own sentinel (so it round-trips through
  an LCL picker or a shared database column), and `TextForNullDate` decides what an empty
  field shows.
- **`TTyUpDown.Associate`**: bind the spin buttons to an edit. **It reads back** -- type a
  number in the field and the next arrow click steps from *that* number, not from the one
  the buttons were holding.
- **A toolbar can say where the row breaks**: `TyToolbarLayout` takes a per-item "start a
  new row here" flag instead of only wrapping when something no longer fits.

### Changed -- parity with Delphi/Lazarus (**includes breaking changes**)

A pass over every control against the LCL/Delphi control it is named after. **The items
below change the behaviour of existing code -- read before upgrading.**

- **`TTyMemo.SelStart` / `SelLength` now count the full line break.** A newline used to charge
  one codepoint, while the string `Text` returns separates lines with a full CRLF on Windows
  -- so the offsets **named a different string**:
  `Memo.SelStart := Pos(needle, Memo.Text) - 1` landed one character further wrong per
  preceding line, **and was silently correct on line 1, which is where people test it**.
  `SelText` now always equals `UTF8Copy(Text, SelStart + 1, SelLength)`, and an offset landing
  inside a CRLF binds to the end of that line. **If you compensated for the old drift, remove
  the compensation.**
- **`TTyValueListEditor.Values` takes a key, not a row number, and `ValueOf` is gone.** The
  row-indexed accessor is `ValueFromIndex`. `Values['Name'] := 'Bob'` -- the line every ported
  program contains -- used to fail to build, with an error that points nowhere near the real
  cause; and `Values[0]` was valid-but-different code on the two libraries. The two forms are
  deliberately **not** an overload of one name: an Integer/string overload pair is exactly how
  a ported call lands on the wrong member and still compiles. Two more LCL behaviours came
  along: lookup **folds case**, and writing an unknown key **appends a row**.
- **`TTyListView.OnChange`, `OnChanging` and `OnSelectItem` change signature.** Code ported
  from Delphi/Lazarus needs no edit -- these are LCL's own shapes; code written against OURS
  does. `OnChange` was Sender-only and now carries which item and what changed
  (`ctText` / `ctImage` / `ctState`); the new `OnChanging` can **veto** a selection change;
  and `OnSelectItem` carries `ASelected`, so "row 3 was chosen" is finally distinguishable
  from "row 3 was abandoned" -- the latter raised no event at all before. Consequently
  `OnSelectItem` is a state DELTA now: re-selecting an already-selected row is silent, as it
  is on LCL.
- **`TTyToolBar.Images` is retyped `TImageList` -> `TTyImageCollection`.** Every icon in this
  library comes from the name-keyed BGRA collection and nothing renders from an index-keyed
  `TImageList`, so a property of that type could never reach a tool button no matter what a
  host assigned -- which is exactly why it used to do nothing.
- **`TTyEdit.ClearSelection` / `TTyMemo.ClearSelection` now DELETE the selected text.**
  They used to collapse the selection and leave the text; LCL's and Delphi's methods of
  the same name have always deleted it. One name, two opposite meanings -- and the silent
  direction was the dangerous one: code ported from Lazarus asked for a removal, got none,
  and was told nothing. The old behaviour is kept as **`CollapseSelection`**.
- **`TTyShellListView.Refresh` is renamed `UpdateView`.** `Refresh` means "repaint now"
  everywhere else in the LCL and in this library; here it re-read the filesystem, so a
  shell list was the one control where a routine repaint call hit the disk -- and a caller
  who wanted an actual repaint had no way to ask.
- **The shell controls no longer claim seven published event slots.**
  `TTyShellTreeView`'s OnGetText / OnInitNode / OnExpanding / OnGetImageIndex / OnChange
  and `TTyShellListView`'s OnCompare / OnItemActivate were taken by their constructors, so
  assigning any of them silently replaced the shell behaviour. Those behaviours are
  overrides now and the slots belong to the application -- each override calls the base
  last, so an application handler sees the shell's answer and can change it.
  **One exception: `TTyShellListView.OnCompare` is still never called** (the sort override
  does not chain to the base), so a file list's ordering cannot yet be taken over.
- **`Caption` and `Text` are one string on `TTyPanel`, `TTyTabSheet` and `TTyDivider`.**
  Each used to carry a shadow Caption, so writing Caption left `TControl.Text` empty and
  anything reading Text saw ''. `.lfm` files are unaffected.
- **`TTyScrollPanel.AutoScroll` is renamed `AutoPan`** -- on every LCL scrolling container
  AutoScroll means "manage the scrollbars", while ours means "pan near an edge". The new
  name matches the control's own AutoPanTo / AutoPanActive / StopAutoPan.
- **`TTyGauge` no longer publishes `Caption`** -- it never painted one.
- **`TTyRadioGroup` reports selection changes.** Setting `ItemIndex` from code used to be
  silent, so a handler tracking the choice worked when the user clicked and not when the
  app restored a saved value. `OnClick` now fires on selection change (matching
  `TCustomRadioGroup`), and the group is **one tab stop** instead of one per item.
- **`TTyColorButton.OnColorChange` fires on any colour change** (it was dialog-only), and
  `OnClick` now runs BEFORE the picker opens so a handler sees the pre-dialog value.
- **`TTyImage.Proportional` no longer enlarges.** A 16x16 icon on a 200x200 image used to
  be blown up; Proportional alone shrinks only, and enlargement is opt-in via `Stretch`.
- **`TTyImage.Center` and `Transparent` now default to `False`, as on `TImage`.** They
  carried LCL's NAME with the opposite default. LCL does not write a property equal to its
  default into the `.lfm`, so a form converted from `TImage` has **no `Center=` line at
  all** -- and on the old control every unstretched picture silently moved to the middle,
  with nothing in the form file to explain it. **Migration:** forms that relied on the old
  defaults should now say `Center = True` / `Transparent = True` explicitly.
- **`TTyVirtualImageList.Draw` and `TTyGlyphImageList.Draw` take LCL's argument order.**
  They used to be `Draw(ACanvas, AIndex, AX, AY, ASizePx)` -- LCL's method NAME with the
  index and the coordinates TRANSPOSED. Every argument is an Integer, so the natural port
  of `Images.Draw(C, X, Y, Idx)` was to append the size and get `Draw(C, X, Y, Idx, 16)`,
  which **compiled** and drew image number X at (Y, Idx). `Draw` is now LCL's signature
  (the trailing flag is **`AEnabled`**, not `Ghosted` -- negations of one another and both
  Boolean, so the wrong polarity compiles and draws every icon disabled). The
  size-carrying form is **`DrawIndex`**; the 4-Integer `Draw` no longer exists, so an old
  call site fails to COMPILE rather than transposing in silence.
  **Migration:** `Draw(C, i, x, y, sz)` -> `DrawIndex(C, i, x, y, sz)`.
- **`TTySplitter` gains `AutoSnap` (default on)**: dragging past `MinSize` closes the pane.
  MinSize used to be a floor no drag could get under, so no gesture closed a pane at all.
- **`TTySpinEdit`**: `MinValue = MaxValue` means "unbounded" and no longer pins every value.
- **`TTyTrackBar.Frequency` defaults to 1** (ticks visible out of the box) and
  `Orientation` swaps the axis.
- **`TTyHeaderControl.OnSectionResize` fires once, on release**; the continuous one is the
  new `OnSectionTrack`.
- **Data grid: six members whose name now means something else. Read these one by one.**
  - **`VisibleRowCount` is back to LCL's meaning -- how many rows the viewport holds.**
    It used to return the filtered row count, so ported paging arithmetic compiled and
    computed a different number. Our meaning already had two other names,
    `DisplayRowCount` and `FilteredRowCount`.
  - **`ClearRows` / `ClearCols` now DELETE rows and columns**, as they do on LCL. They used
    to blank the CONTENT of a band -- same name, opposite kind. Blanking is now
    `ClearRowContents` / `ClearColContents`. Deliberately **not** an arity-only overload:
    "delete every row" and "blank two rows" must not differ by one argument.
  - **`SaveToStream` / `LoadFromStream` no longer write CSV**; they write a versioned
    container that keeps column widths, attributes and position. CSV sat behind a default
    argument, so a one-argument call from ported code compiled and silently produced a
    format that loses columns. CSV is now `SaveToCSVStream` / `LoadFromCSVStream`, with
    optional title rows.
  - **`Selection` is writable** -- restoring a saved rectangle no longer means replaying it
    as four coordinates.
  - `GridLineStyle` keeps our meaning: the enum types differ, so every ported use is a
    compile error rather than a silent misread.
  - **The new `Objects` / `Cols` / `Rows` collide with descendant members of the same
    name.** Code that derives from `TTyStringGrid` and declares any of those three names
    itself (property, field or method) no longer compiles -- "duplicate identifier".
    It is a **compile-time** error and it points straight at the line, so the fix is a
    rename; still worth a grep before you upgrade.
- **The mask edit's mask language changed (breaking).** It used to be this library's own
  three codes (`#` digit, `L` letter, `C` anything); it is now **LCL / Delphi's**: `0`
  required digit, `9` optional digit, `L`/`l` letter, `A`/`a` alphanumeric, `C`/`c`
  anything, `H` hex, `B` binary, plus the `>` `<` `<>` case regions, the `\` escape, `!`,
  and the trailing `;save literals;blank char` fields. **A `#` in an old mask now
  raises** rather than going quiet. This change is itself the fix for a worse problem: a
  Lazarus `EditMask` string used to be ACCEPTED and mean something else -- `'000-0000'`
  had no editable slot at all in the old language, so the field could never take a
  keystroke, silently.
- **Out-of-range writes raise instead of going quiet.** `TTyCalendar.Date` (outside
  `MinDate` / `MaxDate`), `TTyCheckGroup.Checked[i]` and `TTyRadioGroup.ItemIndex` used to
  clamp silently, read back `False` and write nothing, and silently become `-1`
  respectively. Every one of those outcomes is a **plausible** state, which is precisely
  why an index bug survives one. `.lfm` streaming is exempt (a property order mismatch
  would otherwise stop the whole form from opening); the calendar keeps the clamp under
  the name `SetDateClamped` for callers who want "as close as you can get".
- **`TTyMaskEdit.Text := 'hello world'` goes through the mask** instead of landing intact
  in a `'###-###'` field, where `IsComplete` then said that string was complete.
  An assignment and a Ctrl+V of the same string can no longer disagree (both truncate; the
  control does not pad). Two mask shapes that can only be porting mistakes are now
  rejected outright: a non-empty mask with no editable slot at all (`'000-0000'`), and any
  mask containing `;`, LCL's three-part separator, which would otherwise drop its tail
  unseen.
- **`TTyShellTreeView.SelectPath` is a function now**, and writing an invalid `Directory`
  raises. An invalid path used to do nothing at all -- there was no way to tell "the path
  is wrong" from "the path is right and empty". `SelectPath` returns `Boolean` plus a
  `LastPathError` (four distinguishable reasons) and never raises, because resolving a
  user-typed path is routine; the `Directory` setter raises, because a property write has
  no return channel.
- **`TTyTabStrip.TabHeight`**: `0` still means "no tab band" (a shipped capability the
  examples toggle at runtime) and AUTO moved onto the negatives, matching what a ported
  `TabHeight := -1` did in Lazarus. Fixed along the way: at modern density
  `TabHeight := 28` hit a no-change early-out, so the value shrank and the band did not.
- **`TTyHeader.Images` is retyped to `TTyVirtualImageList`.** It was declared as LCL's
  `TCustomImageList`, which this library's image collection does not descend from -- so
  the only lists assignable to it were exactly the ones no painter can draw. The property
  was unusable by construction, and the grid carried a private second list to work around
  it.
- **The three `TTyHeaderControl` section events take `TTyHeaderControl` as their first
  parameter** instead of `TObject`, and `OnSectionTrack` carries an extra `AState` (grab /
  move / release) -- so "is this width mid-drag or final?" is finally answerable.
- **`TTySpinEdit.OnChange` now fires on every keystroke.** It used to fire only when the
  committed value moved, so a handler doing live validation, enabling an OK button or
  updating a preview heard **nothing** while the user typed -- and a half-typed number may
  never commit at all. The committed-value move is the new `OnValueChange`, fired last so
  the handler sees a settled control. The new firings are a strict superset of the old, so
  no handler loses an event.
- **`TTyCheckComboBox.Objects[]` belongs to the application now.** The checked flag used to
  occupy that slot, so an application object stored there read back as *checked* -- and the
  docs recorded that as a rule. The check and the application's data now share one object
  (LCL's arrangement), so sorting, deleting and clearing cannot desync or leak them.
- **A code write to `TTyDateTimePicker.DateTime` no longer fires `OnChange`.** It used to fire
  unconditionally, so the ordinary "load this record into the form" line re-entered the
  application's own handler: the dirty flag came up on a form nobody had touched, a handler
  that wrote back to the model looped, and **there was no flag to turn it off**. `OnChange`
  now means the user changed it; put `dtpoDoChangeOnSetDateTime` in the new `Options` for the
  old behaviour (that is LCL's arrangement and default too).
- **`TTyCalendar.FirstDayOfWeek` now follows the OS by default.** It was hardcoded to Sunday,
  so every Monday-first locale -- most of Europe and Asia -- shipped with a US week layout,
  and **no value expressed "follow the system"**: you hardcoded `wdMonday` and it went wrong
  again the moment the app was relocalised. Pin `FirstDayOfWeek := wdSunday` if you relied on it.
- **Clicking a greyed spill-over day now selects it and pages to its month.** The click used
  to be dropped on the floor -- the grey day was dead and nothing said why. This is LCL's
  default; put `dsNoMonthChange` in the new `DisplaySettings` to get the refusal back.
- **`Esc` now reverts the whole edit, not just the half-typed digits.** A user who spun the
  month with the arrow keys and pressed `Esc` kept the changed month believing they had
  cancelled -- of all the gestures everyone makes, that is the worst one to have not work.
  The control snapshots its value on focus-in and `Esc` restores it.
- **A two-digit year typed into `TTyDateTimePicker` is expanded.** Typing `26` into a `yyyy`
  format and tabbing away used to store the year 0026 -- wrong data, with nothing on screen
  saying so. It now expands against the new `CenturyFrom` (default 1941). Three and four digit
  input is left alone. Likewise, an hour typed into a 12-hour format stays in the meridiem you
  are looking at (typing `04` at 3 PM gives 16:00; it used to give 4:00 with the field still
  reading "04 PM").
- **Format strings are no longer silently rewritten.** The control used to double every single
  field specifier (`'d/m/yyyy'` became `'dd/mm/yyyy'`), so an explicit format looked ignored --
  and that rewrite was never true for month names, so in `'dd mmmm yyyy'` a click on the year
  selected the month. It now renders what you wrote, and the new `LeadingZeros := False` gives
  the compact `9/7/2026` look.
- **`Space` toggling the checkbox now fires `OnChecked`.** Only the mouse path notified, so the
  keyboard changed the state and told nobody. The notification moved into the property setter,
  so mouse, `Space`, auto-check and a code write all travel the same path (as in LCL).
- **`TTySpinEdit.MaxValue` now defaults to 0 (unbounded), not 100.** That is LCL's default, and
  "the ceiling happens to be 100" is a **data-destroying** one: typing 5000 into a control
  whose range was never configured was silently clamped to 100 on commit, with no diagnostic.
  Every spin edit in the examples sets its range explicitly, so nothing shipped changes; if
  your own form relied on the implicit 100, say it out loud.
- **`TTyUpDown.OnArrowClick` fires after the value settles.** It used to fire first, so a
  handler reading `Position` read the value from **before its own click** -- every "the up
  arrow was pressed, go update something" handler was one step behind.
- **`TTyShellTreeView` re-reads a directory each time it expands** (LCL's
  `ecmRefreshedExpanding`). A directory used to be enumerated exactly once per control
  lifetime, so **anything created afterwards never appeared**. For the old behaviour set
  `ExpandCollapseMode := ecmKeepChildren`.
- **`TTyShellListView.UpdateView` restores the selection by path, not by row.** It used to pin
  the row *index*, so creating a file above the selected one moved the highlight onto a
  different file -- and a file dialog then returned a name the user never picked.
- **`TTyImage.Center` / `Transparent` now default to `False`,** as in LCL. A `.lfm` converted
  from `TImage` carries no `Center=` line, so every unstretched picture was silently
  re-centred. Say `Center = True` explicitly if you want it.
- **Three tree members give LCL's names back their LCL meanings.** Three substitutions.
  - **`GetNodeAt`.** Ours was `GetNodeAt(Y; out ANodeTop)` -- LCL's is `GetNodeAt(X, Y)`.
    **Same name, same arity, both Integer**, so a ported call *bound to ours*: it read the
    caller's X as a scroll offset, returned the wrong node, and clobbered the caller's Y
    through the out parameter. Not theoretical -- renaming it turned **12 assertions in our
    own suite red in one build**. `GetNodeAt(X, Y)` is now LCL's; ours is `GetNodeAtOffset`.
  - **`Selected`.** Ours was an indexed Boolean; LCL's is *the current node*, so
    `if Tree.Selected <> nil` could not compile. `Selected` is now the node; the indexed
    form is `NodeSelected[]`.
  - **`OnDragOver`.** Ours was the intra-tree node-drag veto, published over the LCL drag
    hook the base class already offers -- so the tree was the one TTy control that could not
    be an LCL drop target. The intra-tree one is `OnNodeDragOver`; `OnDragOver`,
    `OnDragDrop`, `OnStartDrag`, `OnEndDrag`, `DragMode` and `DragCursor` are back.
- **`TTyVirtualImageList.Draw` / `TTyGlyphImageList.Draw` take LCL's argument order**
  `(Canvas, X, Y, Index, Enabled)` -- note the last one is **Enabled**, not Ghosted, which is
  its opposite. The size-carrying form is `DrawIndex`. There is deliberately **no** 4-Integer
  overload: old call sites should fail to compile rather than compile with the coordinates
  and the index transposed.
- **`TTyScrollBox.ScrollBy` scrolls the view now.** `TScrollingWinControl` **overrides** it to
  do that; we did not -- so a ported `Box.ScrollBy(0,-50)` reached `TWinControl`'s
  child-mover. Same name, same arity, same parameter types, no compile error. It re-bounded
  every child **including both scrollbars** while the scroll offset stayed at 0, and the next
  range update then measured the moved children as a *smaller* extent, corrupting the range
  and the thumb. The child-moving meaning survives as `inherited ScrollBy`.
- **`TTyToolBar.Indent` is horizontal only; vertical padding is the new `ContentPadY`.** LCL's
  `Indent` is the gap before the first tool. Ours was **also** the top pad, and the bar's
  height was `Indent*2 + rows` -- so `Indent := 24`, an ordinary LCL value used to clear a
  logo, made the bar **48 px taller** and pushed every tool down 24 px. `ContentPadY` defaults
  to 4, the old default, so **a bar that never set `Indent` does not move a pixel**; one that
  did gets its vertical padding back at 4.
- **`TTyCheckGroup` / `TTyRadioGroup` lay multi-column items out row-major now** (new
  `ColumnLayout`, defaulting to LCL's `clHorizontalThenVertical`). Ours was hard-wired
  column-major, so a 6-item, 2-column group that reads `1 2 / 3 4 / 5 6` in Lazarus read
  **`1 4 / 2 5 / 3 6`** here -- the user's option list silently reordered. For the old order:
  `ColumnLayout := clVerticalThenHorizontal`. **Single-column groups (the `Columns = 1`
  default) are unaffected.**
- **`TTyListBox.Items` is retyped `TStringList` -> `TStrings`**, so `LB.Items := Memo.Lines`
  compiles.
- **`TTyColorBox.Style` composes the palette now.** The Object Inspector offered it, the `.lfm`
  streamed it, and the setter **threw every value away**. All eight set members do something
  real (standard / extended / system colours, the custom slot, none, default, pretty names,
  including `clNone`); the names come from LCL's own resourcestrings, so they arrive
  translated. The default deliberately **does not copy LCL's** -- it reproduces the existing
  curated 16 byte for byte, because a published `default` is how every `.lfm` that omits the
  line is read. The combo shape stays locked; reach it as `TTyComboBox(Box).Style`.
- **`TTyCheckComboItemState.Checked` becomes `State: TCheckBoxState`** (plus a new `Enabled`),
  matching LCL's `TCheckComboItemState`. Code reaching into the state object must change;
  anything going through the `Checked[]` property is unaffected.
- **`TTyPaintPanel`'s design-time drop size is 105×105, not 185×41.** A drawing surface arrived
  as a letterbox strip in which anything drawn was clipped. Existing `.lfm` files carry
  explicit bounds and are unaffected.
- **`TTyColorButton.Caption` parses `&` mnemonics** like every other button on the same form
  (it used to draw the ampersand literally).
- **`TTyGlyphLayout` gained `glRight` / `glBottom`** (appended, existing ordinals unchanged);
  `HasGlyphSource` (protected) is now `CanShowGlyph` (public).

### Added -- the LCL members the text controls were missing

- **`TTyMemo.Alignment`** -- horizontal alignment per visible row. A centred multi-line block
  **could not be produced by any route**, the theme included. Painting and **click
  hit-testing** share one offset, so you cannot click in one place and land in another.
- **`TTyMemo.CharCase`** -- forces case on typing and on assignment, reusing the edit's folding.
- **`Modified` (`TTyEdit` / `TTyMemo`)** -- True when the user edited, back to False after a
  programmatic write. An application **cannot rebuild that distinction** from `OnChange`, which
  fires for both. It is what drives "enable Save" and "prompt before closing".
- **`TTyEdit.EchoMode`** -- `emNormal` / `emPassword` / `emNone` (shows nothing), coupled to
  `PasswordChar` in both directions. `emNone` had no equivalent at any spelling.
- **Multicast `OnChange`** (`AddHandlerOnChange` / `RemoveHandlerOnChange`, both controls) --
  a library or framework observer no longer has to seize the application's single `OnChange`
  slot, and two observers can coexist.
- **`TTyMemo.CaretLine` / `CaretCol` / `SetCaret` are public** -- the "Ln 12, Col 4" status
  line, go-to-line and error highlighting all needed a subclass to reach them before.
- **Accessible roles** on `TTyEdit` / `TTyMaskEdit` / `TTyMemo` / `TTyLabel`. A self-drawn
  control has no native peer for assistive technology to fall back on, so without this the
  whole text family read as unidentified custom controls.

### Fixed -- controls on a gradient container read as a punched hole

When a panel or container's background is a **gradient**, the windowed controls sitting on it
(speed buttons, check boxes, toggle switches, sliders, the instruments…) rebuild the parent's
backdrop themselves -- and what they rebuilt was one **flat colour**. The control's rectangle
therefore read as a patch stamped into the sweep, worst at the far end of it. Each control now
takes the slice of the gradient that covers **its own position**, so the seam is invisible;
multi-stop gradients (three or more colour stops) are carried across too.

Where only one colour can be used (the window erase colour, the gaps outside a rounded corner,
the base a disabled control dims toward) it is now the colour at the control's **centre** --
previously it was always the gradient's last stop, even for a control sitting on its first.

### Fixed -- the mask edit's two delete paths bypassed the mask

`InjectBackspace` / `InjectDelete` cut a **raw character** out of the mask edit's display
string, mask literals included -- leaving content that no longer matches the mask the control
claims to enforce. Backspace and Delete from the keyboard were always correct; these two
methods were not. (Same shape as the `Ctrl+V` hole that was closed earlier in this pass.)

### Fixed -- knobs the Object Inspector offered and the control ignored

What these share: the member was there, it ran, it returned, and nothing happened. No
error, no log, nothing visible in a screenshot.

- **All four `TTySplitter.ResizeStyle` values do something now.** Only `rsUpdate` ever moved
  anything: a splitter set to `rsPattern` or `rsNone` **could be dragged forever and nothing
  happened**, and `rsLine` moved but drew no feedback. Picking any style other than the
  default turned the control off. All three deferred styles commit on release, and
  `rsLine` / `rsPattern` draw a live preview band -- solid and dashed respectively. The band
  borrows the same `color` token as the grip dots, so `TySplitter { color: ... }` recolours
  both.
- **A toolbar's `ShowCaptions` really makes its tools icon-only.** It reaches every tool that
  can draw an icon, along with `Images` (and the new `TTyGlyphButtonBase.ShowCaption` sets it
  per button). **A tool with no resolvable icon keeps its caption**, so the LCL-parity `False`
  default cannot blank an existing caption-only toolbar. The bar LENDS its collection to tools
  that have none; a tool carrying its own is left alone.
- **`TTyMemo.ScrollBy` scrolls the text.** Reaching for the documented memo scroll API used to
  get `TWinControl`'s child-mover: it dragged the memo's own embedded scrollbars off their
  docked edges and left the text where it was.
- **`TTyTreeView`'s `Ghosted` flag finally does something.** `OnGetImageIndex` has always
  handed the application a `var Ghosted: Boolean` and then dropped it -- the one thing it says,
  "draw this node's icon dimmed" (the cut / unavailable look), had no effect anywhere.
  `TTyVirtualImageList.Draw` can dim now: alpha only, so the icon keeps its colours and loses
  its presence -- recolouring would say "different", not "unavailable".
- **A context menu's `OnPopup` fires**, `PopupPoint` updates, and `Close`/`OnClose` are no
  longer silent no-ops. The item snapshot is taken AFTER `OnPopup`, so items added there
  actually appear.
- **`TTyColorButton.Caption` is painted** -- published, designer-editable, and never drawn.
- **Every control can now be hidden, dragged and given a horizontal wheel from the designer
  or a `.lfm`**: `Visible`, the whole `DragMode` / `OnDragOver` / `OnDragDrop` surface,
  `OnMouseWheelHorz|Left|Right`, `OnShowHint`, plus `AutoSize`, `BorderWidth` and
  `ChildSizing` were published on neither base class.
- **A masked edit no longer accepts whatever you paste into it** (Ctrl+V bypassed the mask
  entirely), and Delete no longer removes mask literals.
- **Menu bar**: a disabled top paints greyed and cannot be opened; **a childless top fires
  its `OnClick`** (it used to do nothing at all, indistinguishable from a menu that failed
  to load); `RightJustify` works, for the classic right-aligned Help / Window menu.
- **A menu item's `Hint` reaches `Application.Hint`**, so a status bar can describe the
  command under the cursor; an `AutoCheck` item draws an empty check box before it is
  checked, so you can see it is a toggle without clicking it first.
- **Date/time picker**: A/P set AM/PM, separator keys advance the field, Space toggles the
  check box -- which was mouse-only, and an unchecked picker refuses every key, so a
  keyboard user could not enable it at all.
- **`ActivePage`, `ColorBox.Selected` and `ColorListBox.Selected` are published** -- the one
  thing each control exists for could not be set in the designer or streamed.
- **The last header section's width stops lying**: new `EffectiveSectionWidth` reports the
  width actually painted.
- **`TTyScrollBox`'s view scroll is callable** (`ScrollByDelta` / `ScrollTo`, both protected
  before).
- **A disabled splitter no longer shows the resize cursor**; header and tree no longer
  destroy a caller's `Cursor`.
- **`SpeedButton.Down := True` releases its group**; turning `AllowAllUp` off restores the
  "exactly one down" invariant.
- **Single-select `ClearSelection` / `Selected[i] := False` actually deselect.**
- **`TTyCheckGroup.Checked[i] := x` no longer fires `OnItemChange`.**
- **`TTyToolBar` no longer overwrites its children's `StyleClass`** (a host's `'primary'` and
  other variants survive; `TTyToolBarEx` still overwrites for now); **the last status-bar
  panel reaches the right edge.**
- **Writing an off-palette colour to a colour box no longer appends a row.**
- **`TTyUpDown.Wrap` carries the overshoot** instead of discarding it (an Increment above 1
  had turned it into a reset); new direction-carrying `OnArrowClick`.
- **`TTyShellListView`'s Size column units are translatable** (they were hard-coded English).
- **Four popup-menu properties are finally read**: `TrackButton` (holding the right button,
  dragging onto an item and releasing used to do nothing), `GlyphShowMode` (per-item control
  over whether the icon draws), `SubMenuImages` (each submenu level can carry its own icon
  set; a cascade used to inherit its parent's unconditionally), and the whole `OwnerDraw` /
  `OnDrawItem` / `OnMeasureItem` protocol. Also: **a disabled row's icon draws greyed**.
- **Column headers can carry icons**: `TTyColumn.ImageIndex` is drawn now, and the caption
  steps aside for it. A header with no list of its own resolves against the control's
  `SmallImages`, which is where Delphi and LCL resolve column icons.
- **The shell tree's `ShowHidden` takes effect on the write**, instead of waiting for the
  next refresh to reveal it.
- **`TTyDivider` gains `LeftIndent`** (`TDividerBevel`'s property): the rule's inset from the
  left in pixels. It coexists with our `Alignment` and wins when `>= 0`; off by default, so
  existing dividers render unchanged.
- **`TTyToolBarEx` no longer overwrites a child button's `StyleClass`** -- the previous round
  fixed the base class, but the `Ex` subclass overrides layout and kept the old line, so the
  same `StyleClass := 'primary'` survived on one toolbar and was wiped on every relayout of
  the other.
- **`TTyShellListView.OnCompare` actually gets called** (the previous round handed the event
  slot back to the application but left nothing raising it).
- **Renaming a file with F2 re-reads the directory again.** When `Refresh` was renamed to
  `UpdateView` last round, the commit-edit path's `Refresh` call **silently rebound to
  `TControl.Refresh`** -- the file changed on disk and the row kept the old name.
- **The track bar draws its ticks**: `TickMarks` (top/left, bottom/right, both), `TickStyle`
  (none / auto / manual), `SetTick` / `ClearTicks` / `TickCount`, and `Reversed`.
- **Progress bar**: `Step` / `StepIt` / `StepBy`, `BarShowText` to print the percentage on the
  bar (template-configurable via `BarTextFormat`), and `Orientation` in all four directions
  including right-to-left and top-down.
- **`TTyScrollBar.LargeChange` is finally read** -- clicking the trough always paged by a full
  page, so a host-configured page step reached nothing.
- **The spin edit gained the editing-time surface it was missing**: `Text` (which reads the
  **uncommitted** input buffer), `CaretPos`, `Modified` (cleared by a code write -- it answers
  "did the user touch this?"), `EditorEnabled` (locks typing but keeps the arrows),
  `ValueEmpty`, `TextHint`, and overridable `GetLimitedValue` / `ValueToStr` / `StrToValue`.
- **`TTyUpDown` gained `OnChanging` / `OnChangingEx`**, which can veto a step --
  `OnChangingEx` also sees the proposed value and the direction. Plus `MinRepeatInterval`
  for the auto-repeat floor.
- **Shell tree**: `Root` (scope the tree to one directory), `ObjectTypes`, `Path`,
  `FileSortType` with `OnSortCompare`, `OnAddItem` (veto per entry), `UseBuiltinIcons`; the
  list view likewise, plus `AutoSizeColumns` and `MaskCaseSensitivity`. Tree, list and filter
  combo can be linked to each other (`Tree.ShellListView`, `List.ShellTreeView`,
  `Combo.ShellListView`) so navigating one drives the others.
- Name parity: `TTyCalendar.DateTime`, `TTyMaskEdit.EditMask`, `TTyMemo.Append`,
  `TTyEdit.Clear`, and the whole `Clear` / `AddItem` / `Count` / `ItemRect` list surface on
  `TTyListBox` and `TTyComboBox`.

- **`TTyShape` claims only the pixels it actually covers.** Circles, ellipses, diamonds and
  lines used to answer every click inside their **bounding rectangle**, so a control behind
  a circle could never be reached through the corners. Hit-testing follows the shape now
  (its border width included), and `PtInShape` is public for hosts that want to ask.
- **`TTyStarShape` likewise -- and a star is the worst case of it.** Five points leave five
  deep concave notches, so a great deal of the bounding rectangle is canvas the control
  never draws on; it used to answer "mine" at all of it, and **no control behind a star's
  points could be clicked**. Hit-testing follows the shape now, with `PtInShape` and
  `StarGeometry` public.
- **`TTyArrow` gains the triangle arrow** (`Shape := tasTriangle`), with the apex angle on
  `ArrowPointerAngle` -- LCL's `TArrow` name and its 60° default. This library could only
  ever draw the block arrow, so the directional triangle a ported form expects was not
  reachable at all. The block arrow stays the default: changing it would silently rotate
  every arrow on every existing form.
- **`TTyPanel.BorderWidth` actually insets now.** The base republished it, but `TWinControl`
  **never reads** the value -- in LCL that gutter is done solely by `TCustomPanel`. So the
  Object Inspector offered an 8px border the container treated as air.
- **A panel can be a dock site**: `DockSite`, `UseDockManager` and the whole `OnDockDrop` /
  `OnDockOver` / `OnStartDock` / `OnEndDock` / `OnUnDock` / `OnGetSiteInfo` /
  `OnGetDockCaption` family. The last four are protected upstream and **had no route at all**.
- **Drag-reordering tabs no longer desyncs the header from the body** (selection is pinned to
  the position, and only the header obeyed), and **moving a page to another `TTyPageControl`
  no longer leaves it counted by the old one** (un-registration hung off "was freed", not
  "was re-parented").
- **The status bar can show hints**: `AutoHint` routes `Application.Hint` into `SimpleText` or
  panel 0, and `OnHint` takes the whole job over. This is what finally makes the **menu item
  `Hint`** landed earlier in this pass visible -- the menu was publishing all along and
  nothing in the library was listening. Also `GetPanelIndexAt`, and `Style := psOwnerDraw`
  with `OnDrawPanel` (a status cell could only ever be plain text).
- **Header sections gained constraints and hiding**: `MinWidth`, `MaxWidth`, `Visible`,
  `InsertSection`. All four width paths -- the setter, a whole-record write, insertion and the
  **live drag** -- go through one clamp; a limit the setter honours and the drag ignores is
  not a limit.
- **`TMenuItem.ShowAlwaysCheckable` is read now** -- the row model only looked at `AutoCheck`,
  the flag that **also** makes the item toggle itself on click, which many applications do not
  want.
- **Buttons gained `Alignment` (caption) and `ShowAccelChar`.** `'AT&T'` used to render as
  `'ATT'` **and** acquire a stray Alt+T accelerator, escapable only by doubling the ampersand
  at every assignment site. Also `GlyphLayout` gained right and bottom (the trailing-icon
  `more ▾` look was unreachable at any setting), a per-button `Spacing`, a public
  `CanShowGlyph`, and `TTySpeedButton.FindDownButton` -- the grouping code only ever walked
  siblings to *release* them, so reading back which one is down needed a hand-rolled typed
  scan.
- **`Alignment` on the check box and radio button** -- note this is LCL's meaning: **which
  side the indicator sits on**, not caption alignment (that is `TTyGroupBox.Alignment`). One
  word, two subjects.
- **The group controls gained per-item reach**: `Buttons[]` (per-item `Hint`, `PopupMenu`,
  `Font`, `Enabled` were unreachable), `CheckEnabled[]` (one greyed row -- "this option isn't
  in your edition"), `OnItemClick`, `OnItemEnter` / `OnItemExit`. **Arrow keys move the
  selection in a radio group now** -- they used to do **nothing**, leaving Tab as the only
  keyboard route, and Tab plus Space **changes the selection on the way past every option**.
  Arrows step over disabled items and stop at the ends. The group's own `OnKeyDown` /
  `OnKeyUp` / `OnKeyPress` also fire at last (the group never holds focus, so those slots
  could be assigned and never run).
- **`TTyColorButton.ButtonColor`** -- LCL's name *and* type. Assigning a `TColor` to
  `SelectedColor` was read as ARGB and came out a different colour, silently. Plus
  `OnColorChanged`, one letter from ours and therefore reading as "the event is missing".
- **`TTyGroupBox.ClientWidth` / `ClientHeight`** -- a ported `.lfm` that pinned a *client* size
  simply lost those lines.
- **List box**: `OnSelectionChange(Sender; User)` distinguishes a user click from a code write
  (with `Lock` / `Unlock`), and `ExtendedSelect` -- the only multi-select discipline usable on
  a touch screen.
- **Check list box**: tri-state `State[]` with `AllowGrayed`, `ItemEnabled[]` (a disabled row
  now also *looks* disabled), `Toggle`, `CheckAll`. Found on the way: a foreign object in
  `Objects[]` read as *checked*, because it was non-zero.
- **Colour box / colour list box**: `Colors[]` readable **and writable**, `ColorNames[]`,
  `OnGetColors`, `DefaultColorColor` / `NoneColorColor` (`clNone` / `clDefault` were painted
  as their raw sentinel values). The swatch size moved off a hardcoded 4px onto
  `--color-swatch-width` / `--color-swatch-offset`.
- **`TTyListView.Columns` / `Column[]` / `ColumnCount`** without the `Header` hop, plus
  `OnInsert` / `OnDeletion` -- the latter is the only moment a per-item `Data` payload is
  still reachable, and it fires per row on clear and on destroy.
- **Combo box**: `ItemHeight` / `ItemWidth`, `TextHint` (painted in both shapes), `ReadOnly`, a
  **writable** `DroppedDown`, `SelStart` / `SelLength` / `SelText` / `SelectAll`,
  `AddHistoryItem`, and `OnGetItems` -- a lazily-filled combo's **first click did nothing**,
  because the empty-list early-out ran before any hook could fill it.
- **`TTyComboBoxEx.ItemsEx`**: a published collection, **editable in the designer and streamed
  to `.lfm`** -- the reason that control exists. It is the single source of truth; `Items` is
  its projection.
- **Check combo box**: tri-state, `ItemEnabled[]`, `OnItemChange`, `CheckAll` / `Toggle` /
  `AddItem` / `AssignItems` / `DeleteItem`.
- **Tabs and scrolling containers**: `TabRect`, `DisplayRect`, `IndexOfTabAt`, `AddTabSheet`,
  `ScrollTabs`, `PageIndex`, `PageControl`, `OnShow` / `OnHide`, `ScrollInView`,
  `UpdateScrollbars`, and `WordWrap` / `VerticalAlignment` / `ShowAccelChar` on tab text.
- **Accessibility**: the text controls, panels and splitters declare an `AccessibleRole`. A
  self-drawn control has no native peer for assistive technology to fall back on, so until now
  the whole text family read as unidentified custom controls.

### Added -- shape and image controls brought up to parity

- **`TTyShape` gains the rest of LCL's fifteen kinds, plus an escape hatch.** New: the
  rounded square, the squared diamond, the left / right / down triangles (flow-direction
  markers, play/back glyphs), and the star point-up and point-down -- none of which were
  reachable at **any** property setting, and a `.lfm` carrying one of those values simply
  failed to load. Plus `tskPolygon` + **`OnShapePoints`**: the app supplies the vertices,
  so hexagons, callouts and chevrons are reachable **from the designer** instead of needing
  a hand-written `TTyGraphicControl` descendant. The new enum values are APPENDED, so no
  existing form changes shape.
- **`TTyShape` / `TTyStarShape` gain `OnShapeClick`** -- fires only for a click on the ink.
- **`TTyStarShape` gains `PointDown`** (LCL's `stStarDown`). The control had no rotation of
  any kind, so that star could not be drawn.
- **`TTyImage` can draw from a shared icon set** (`Images` / `ImageIndex` / `ImageWidth`).
  A themed icon on a form previously had to be duplicated into the control's own `Picture`,
  losing both the one-place-to-change icon set and the per-DPI rendering the collection
  already does.
- **`TTyImage` gains `StretchInEnabled` / `StretchOutEnabled`** -- the shrink and the
  enlarge gates, independently. The standard LCL recipe "shrink big photos, never enlarge
  small ones" was previously unexpressible: turning Stretch/Proportional off disables both
  directions at once.
- **`TTyImage` gains `KeepOriginXWhenClipped` / `KeepOriginYWhenClipped`**: when a centred
  picture is bigger than the control, pin that axis at the origin instead of cropping
  symmetrically -- the top-left of a map, screenshot or scan is finally visible.
- **`TTyImage` gains `AntialiasingMode`**: `amOn` requires a smoothed scale (which nothing
  could ask for before), `amOff` requires hard edges, `amDontCare` (the default) is
  unchanged.
- **`TTyImage` gains `OnPictureChanged` and `HasGraphic`**: react to a new image (dimension
  label, dirty flag, thumbnail) without polling, and ask "is there anything to draw" without
  reaching into `Picture.Graphic` to null/Empty-check it by hand.

### Added -- `OnPaint`

- **Every TTy control has `OnPaint` now.** It fires after the control has finished drawing
  itself and hands you the control's own `Canvas` -- one badge, one overlay, one debug
  rectangle, without subclassing. It is **not** an owner-draw replacement: the themed
  control is already on the canvas when the handler runs, and the handler draws over it.
  The docs used to present the absence as a design position. It was not: every control here
  builds its frame into a BGRA layer and then composites that layer onto the canvas, so a
  hook fired from inside `Paint` would have had its output overwritten. The hook sits after
  the composite instead. On a cached container the overlay is never baked into the cache and
  replayed frozen.

### Fixed -- data grid

- **Paste no longer drops data silently**: pasting 100 rows into a 10-row grid used to
  discard 90 of them without a word; the grid now grows to fit the clipboard block.
- **CSV fields containing newlines no longer corrupt the data**: Excel exports such
  fields routinely, and they used to be truncated with rows appearing out of nowhere.
- **The sort triangle had never actually been displayed**: the sort state was never
  synced to the header.
- **Grouping silently discarded the user's sort column.**
- **Merged regions did not follow inserted/deleted rows**: the content moved, the
  merge box stayed behind.
- **`hoAutoResize` and column header images never did anything**: the properties were
  exposed but nothing at runtime ever read them.
- Blank values flipped position with the sort direction (reversing the sort sent every
  blank row to the top).

### Performance -- data grid

- Cell text drawing accounted for **94%** of frame render time; a cross-frame text
  cache brought it down to roughly 1/20. Scrolling large grids is noticeably smoother.


### Added — 14 modern UI controls (the Ant Design gap)

- **Cards & markers**: `TTyCard` (header + content + actions, as one themed surface; `hoverable` is just a `TyCard:hover` rule), `TTyTag` (closable pill; colour variants are `StyleClass`), `TTyBadge` (a **standalone** count/dot marker — point `Target` at any control and it glues itself to that control's corner and follows it; `TTyButton`'s built-in badge still works as before).
- **Feedback**: `TTyAlert` (an **inline** alert bar — until now every notice was a modal dialog, so "a bar that sits in the page and says something" had no equivalent at all; info / success / warning / error, closable), `TTyNotification` (a corner toast that auto-dismisses and pauses on hover), `TTyPopover` (a bubble that can **hold controls** — `TTyHint` / `TTyBalloonHint` can only show text).
- **Navigation & flow**: `TTySegmented` (focusable, arrow-key driven), `TTyPagination` (`1 2 3 … 195`; needs no grid — it drives any list), `TTySteps` (wizard steps, horizontal or vertical), `TTyBreadcrumb`.
- **Data entry**: `TTyTransfer` (two-list shuttle), `TTyTreeSelect` (a tree in a dropdown), `TTyCascader` (province/city/district).
- **Empty state**: `TTyEmpty` (picture + message + optional action — standard furniture for an empty list/tree/table, previously hand-assembled from Labels).

All of them are on the component palette (with HiDPI icons), render correctly under **all 20 themes**, and ship an API reference each.

### Added — theming

- **Two semantic seed colours, `--success` and `--warning`** (each with its `on()` pairing), for the success/warning kinds of the alert bar and the toast. Existing themes inherit them with no change.
- **The badge's corner inset and minimum size are now tunable** (`--badge-inset` / `--badge-min-size`). The defaults are unchanged, so no existing UI moves by a pixel.

### Added — examples

- **[examples/antdesign](examples/antdesign/) — "TyControls Pro"**: an Ant Design Pro-style admin shell (sider + 6 pages), defaulting to the antdesign skin, with runtime skin and light/dark switching.


### Changed — form structure (existing forms need migrating)

- **A `TTyForm`'s controls now live on a content container, `TTyFormSurface`** — one per form, named `Surface`, filling the form, with **every control inside it**. The File > New *TyControls Form / Application* templates ship with it, so new forms need no extra work, and dropping controls in the designer lands them in it.
  **Existing forms need migrating**: move the controls that sat directly on the form into the `Surface` (non-visual components — style controllers, timers, dialog components — stay where they are).
  **Graphic controls (`TTyLabel`, `TTyShape`, …) must be inside the `Surface`** — they paint onto their parent, so one left on the form is hidden behind it and will not be visible; the designer warns you when you do this.
  Dialogs (`TTyDialog`) are unaffected: they are not resizable, have no `Surface`, and take controls directly as before.

### Fixed

- **Danger buttons finally look dangerous under every built-in theme** — of the 15 built-in themes only `showcase` defined `TyButton.danger`, so on the other 14 a `StyleClass='danger'` button silently fell back to the plain button look. Each theme now carries the danger colour of the design system it imitates (Bootstrap danger, Ant Design error, Material 3 error, Apple systemRed, GNOME/Yaru, KDE Breeze negative, the Microsoft reds of each era), with separate light and dark values.

- **The unpainted white/transparent strip along the right and bottom edge of borderless resizable windows is gone** — such a window cannot paint its own outermost pixels; the content container now paints to the true edge. This is why the structural change above exists.
- **File > New *TyControls Dialog* no longer produces two title bars**, and a dialog created from it no longer fails at startup with `EClassNotFound: Class "TTyPanel" not found`.

## [2.2.0] — 2026-07-04

A large feature release. The headline is the **dialog subsystem**: **TTyForm** gains complete window chrome
(caption buttons), joined by **11 fully custom-drawn dialog components** with matching global functions, IDE
integration and a standalone example. It also adds **three small controls** (tri-state CheckBox, editable
ComboBox, TTyTabSet), completes the per-control API docs, and fixes many display issues that only surfaced on
a real machine (notably Windows 10).

### Added — Dialogs

- **TTyForm window chrome** — the title bar's minimize / maximize / close buttons are now controlled by
  `BorderIcons` (`BorderIcons:=[]` removes every button); whether the window is resizable is set by
  `Resizable`. The old `ShowMinimize` / `ShowMaximize` properties are removed.
- **11 fully custom-drawn dialog components** — LCL-parity, usable both as drop-in components and via global
  functions:
  - **Message box** (`TyShowMessage` / `TyMessageDlg`) with full button sets, results and type glyphs.
  - **Input / password / multi-line text** (`TyInputQuery` / `TyPasswordQuery` / `TyTextQuery`).
  - **List value picker** and **folder picker** (New Folder, expandable directory tree).
  - **Colour picker** (HSV + hue bar + RGB / CMYK / Alpha / Hex) and **font picker** (family / size / style /
    colour / preview).
  - **Find / Replace** (modeless, `OnFind` / `OnReplace`) and a cancelable **progress dialog**.
  - Every dialog supports `OnShow` / `OnClose` / `OnCanClose`.
- **IDE integration** — a new **TyControls Dialogs** palette group, palette icons for all 11 dialogs, a
  File > New **TyControls Dialog** template, and double-click-to-preview in the designer.
- **Examples** — a new standalone **dialogs example** demonstrating all 11 dialogs; the main demo gains a
  dialog grid too.

### Added — three small controls

- **Tri-state CheckBox** — `State` / `AllowGrayed`, with a grayed (indeterminate) glyph.
- **Editable ComboBox** — free text entry (`csDropDown`) with prefix autocomplete.
- **TTyTabSet** — a pure tab strip (not a page container).

### Added — Documentation

- **Per-control API docs for every control** (properties / events / states / theme variants / examples),
  including the previously-undocumented TreeView, Calendar, DateTimePicker, Splitter, StatusBar, ToolBar,
  TabSet, menus and NativeStyler, plus a controls index under `docs/controls/`.

### Added — example overhaul

- Every single-control example now uses the **TTyForm + TTyTitleBar** custom frame and shows more of each
  control's features.
- Seven new dedicated examples: tabset, calendar, datetimepicker, splitter, statusbar, toolbar, menu;
  the `tabcontrol` example now uses TTyPageControl + TTyTabSheet.

### Fixed

- **Windows 10 white / transparent windows** — windows and containers (dialogs, group boxes, tabs, disabled
  controls) no longer bleed glass or white on Windows 10, and no longer wash out white when the window loses
  focus.
- **Washed-out disabled controls** — disabled controls no longer look faded or show a white background.
- **Side stripes on resizable windows** — resizable windows no longer show accent / white vertical stripes on
  the left and right edges.
- **Editable ComboBox typing** — typing no longer loses focus or characters, the autocomplete popup no longer
  flickers, and clicking a suggestion fills in the correct value.
- **Tab scroll arrows** — with many tabs, the left / right scroll arrows no longer cover the first / last tab.
- **Date picker dropdown crash** — opening the calendar dropdown no longer crashes when using the global
  default theme.
- **Progress dialog flicker** — the progress dialog's text and bar no longer flicker.
- **Double-click-maximize crash** — double-clicking the title bar to maximize no longer crashes on
  multi-monitor / unusual setups.
- **Chinese UI** — on a Chinese OS, message-box buttons show 确定 / 取消 etc., and the dialogs and demo
  examples follow the system language.
- **Example fixes** — assorted example startup crashes and display glitches (radiobutton startup crash,
  GroupBox title overlap, splitter drag direction, etc.).

## [2.1.1] — 2026-06-30

A bug-fix release focused on the green image theme's on-device look and a few IDE design-time glitches.

### Fixed

- **green theme** — every container (toolbar, title bar, status bar, panel, group box, tab,
  separator, scrollbar) is now **100% transparent**, so the photo background shows through cleanly,
  with no frosting or solid fill.
- **TTyForm glass/photo backdrop** — rebuilt the instant a theme is applied: picking an image theme
  via Custom… now shows the photo **immediately** (no more minimize/restore to trigger it); the
  toolbar and status bar sample the photo too.
- **Minimize** — the main form minimizes to the taskbar (not a small box in a screen corner);
  minimizing a popup child window no longer minimizes the whole app.
- **TTyToolBar separator** — seamless with the toolbar background on solid themes (no odd fill
  patch), and shows the photo through on image themes.
- **IDE designer**
  - Switching **TTyPageControl** pages no longer leaves the old page's controls behind (set
    `csNoDesignVisible` before `Visible` so the shown-state re-evaluates immediately).
  - Internal sub-controls of **TTyTreeView / TTyListBox / TTyMemo** (scrollbars, and the
    TTyTreeView inline editor) no longer leak into the designer.

## [2.1.0] — 2026-06-30

A large feature release. The headline is **TTyTreeView**, a full VirtualTreeView-class virtual
tree, joined by five more new controls, native window resize and window effects for **TTyForm**,
and keyboard mnemonics across the whole library.

### Added — New controls

- **TTyTreeView** — a virtual, data-on-demand tree that scales to millions of nodes:
  - Lazy 3-stage node initialization; an incremental height/position cache with fast hit-testing.
  - Multi-column with a draggable header — column **resize**, **reorder**, **auto-size / spring**.
  - **Sorting** — `OnCompareNodes`, click-to-sort header with a direction glyph, lazy-aware merge sort.
  - **Checkboxes** with tri-state + automatic tri-state propagation, and **radio-button** nodes.
  - **Multi-selection** (Ctrl / Shift / Ctrl+A) and **full-row** select.
  - **Variable per-node row height** (`OnMeasureItem`).
  - **Incremental type-to-find** search.
  - **Per-cell owner-draw** (`OnDrawNode` / `OnAfterCellPaint`).
  - **Inline cell editing** (F2 / double-click; Enter commits, Esc cancels; `OnEditing` / `OnNewText`).
  - **Intra-tree node drag-drop** — reorder or reparent, accent drop-mark, circular-reparent guard.
- **TTySplitter** — drag to resize a neighbouring control.
- **TTyStatusBar** — paneled status bar.
- **TTyToolBar** — toolbar with separators.
- **TTyDateTimePicker** — segmented date/time editing with a drop-down calendar and a time spinner.
- **TTyCalendar** — calendar with day → month → year drill-down.

### Added — TTyForm

- Native window **resize** (Windows custom frame: `WS_THICKFRAME` + `WM_NCCALCSIZE` /
  `WM_NCHITTEST`) with a published **`Resizable`** property; maximize fills the monitor work area;
  title-bar drag and top-edge resize.
- OS **rounded corners + native drop shadow** (Windows 11 DWM / macOS), on by default, opt-out via CSS.

### Added — Interaction, theming, i18n

- **Mnemonics** — `&`-accelerators with Alt-underline display and Alt+letter activation across
  menus, buttons, check boxes, radio buttons, group boxes, labels and tabs.
- **TTyNativeStyler** — harmonizes native / third-party LCL controls with the active theme.
- **TTyComboBox** — shared themed drop-down popup.
- **Internationalization** — `resourcestring`s plus English and Simplified-Chinese `.po` catalogs
  for theme diagnostics, design-time strings and the demo (with a runtime language switcher).

### Fixed

- **TreeView** — node icons not painting (the ImageList draw was erased by the BGRA composite and
  is now drawn after it; the real root cause was `MainColumn` being assigned before columns
  existed); HiDPI vertical axis (scroll / hit-test / scroll-into-view); embedded scrollbars for
  huge ranges (minimum thumb size, 64-bit position mapping, constructor-time creation); expand
  chevron size; horizontal scrolling; a managed node-data leak on teardown; multi-select count
  integrity on delete / clear.
- **TTyForm** — maximize edge slipping under the taskbar; double-click-maximize "growing in place";
  top-edge resize; a too-thick top frame.
- **Theming** — crash when a dual-mode theme is loaded without a mode; `TTyNativeStyler` text colour
  on dark themes.
- **TTyEdit** — the caret height now tracks the font line-height (it was tied to the box height,
  which gave a stunted caret in tight hosts such as the tree's inline editor).
- **TTyMemo** — text-measurement performance (a per-line width cache).

### Platform

- **macOS** — compile + run fixes (a process unit for OS theme detection, `CGFloat`, multi-monitor
  startup positioning).
- **IME** support on custom-drawn edits (Qt6 / GTK2).

### Notes

- Native window resize is **Windows-only** in this release; GTK / Qt / Cocoa fall back to a manual
  resize gutter (a native handoff is planned).

## [2.0.0] — 2026-06-20

Initial 2.x baseline: the custom-drawn control set on the `.tycss` v2 theme engine (merge-then-
resolve, tiered tokens, dual `@mode`, OS light/dark + accent follow, hot-reload + lint), a 12-theme
built-in pack, per-component `About` metadata, and the release tooling.
