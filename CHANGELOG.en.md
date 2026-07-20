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
