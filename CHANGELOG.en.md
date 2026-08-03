# Changelog

All notable changes to **ty-controls** are documented in this file. The project uses
3-part semantic versions (`MAJOR.MINOR.PATCH`). Every control is fully custom-drawn via
BGRABitmap and themed by lightweight `.tycss` text themes — pixel-identical on Windows,
Linux and macOS.

> 中文版见 [CHANGELOG.md](CHANGELOG.md)。

## [Unreleased]

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
- **`TTySplitter` gains `AutoSnap` (default on)**: dragging past `MinSize` closes the pane.
  MinSize used to be a floor no drag could get under, so no gesture closed a pane at all.
- **`TTySpinEdit`**: `MinValue = MaxValue` means "unbounded" and no longer pins every value.
- **`TTyTrackBar.Frequency` defaults to 1** (ticks visible out of the box) and
  `Orientation` swaps the axis.
- **`TTyHeaderControl.OnSectionResize` fires once, on release**; the continuous one is the
  new `OnSectionTrack`.

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
- Name parity: `TTyCalendar.DateTime`, `TTyMaskEdit.EditMask`, `TTyMemo.Append`,
  `TTyEdit.Clear`, and the whole `Clear` / `AddItem` / `Count` / `ItemRect` list surface on
  `TTyListBox` and `TTyComboBox`.

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
