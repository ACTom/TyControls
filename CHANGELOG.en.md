# Changelog

All notable changes to **ty-controls** are documented in this file. The project uses
3-part semantic versions (`MAJOR.MINOR.PATCH`). Every control is fully custom-drawn via
BGRABitmap and themed by lightweight `.tycss` text themes — pixel-identical on Windows,
Linux and macOS.

> 中文版见 [CHANGELOG.md](CHANGELOG.md)。

## [Unreleased]

### Added

- **Gauge control (`TTyGauge`)** — a new value gauge: linear (horizontal/vertical bar), open-arc
  (speedometer) and full-ring styles, with an eased value animation and an optional formatted value
  readout; colours come from the theme's `TyGauge` / `TyGaugeFill` rules. Pixel-identical cross-platform.
- **About dialog (`TTyAboutDialog`)** — a new reusable custom-drawn About dialog: a custom title
  bar + an accent header (app name + version) over description / copyright / license / a clickable
  homepage link; **empty fields are hidden automatically**, so the dialog shrinks to what it has.
  Components' design-time `About` property now uses it too, so it looks exactly like the dialog
  the library ships.
- **Folder-picker dialog** — a path field across the top shows the current selection and lets you
  **type or paste a folder path** and press Enter to jump straight to it.

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
