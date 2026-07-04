# Changelog

All notable changes to **ty-controls** are documented in this file. The project uses
3-part semantic versions (`MAJOR.MINOR.PATCH`). Every control is fully custom-drawn via
BGRABitmap and themed by lightweight `.tycss` text themes — pixel-identical on Windows,
Linux and macOS.

> 中文版见 [CHANGELOG.md](CHANGELOG.md)。

## [2.2.0] — 2026-07-04

A large feature release. The headline is the **dialog subsystem**: **TTyForm** gains complete window chrome
(caption buttons), joined by **11 fully custom-drawn dialog components** with matching global functions, IDE
integration and a standalone example. It also adds **three small controls** (tri-state CheckBox, editable
ComboBox, TTyTabSet) and fixes a long list of issues that only surfaced on a real machine (notably the Win10
DWM glass).

### Added — Dialogs

- **TTyForm window chrome** — caption buttons are driven by **`BorderIcons` + `Resizable`**:
  `BorderIcons:=[]` drops every button; `BorderStyle` is locked to `bsNone` (coercing setter); assigning a
  title bar that belongs to another form raises (cross-form guard). The old `ShowMinimize` / `ShowMaximize`
  switches are gone — `BorderIcons` is the single source of truth.
- **11 fully custom-drawn dialog components** — LCL-parity, each as both a component and a global function:
  - **TTyMessage** — message box (`TyShowMessage` / `TyMessageDlg`) with full button caption / result /
    order and type glyphs.
  - **TTyInputDialog / TTyPasswordDialog / TTyTextDialog** — single-line input, masked password and a
    resizable multi-line text query (`TyInputQuery` / `TyInputBox` / `TyPasswordQuery` / `TyTextQuery`).
  - **TTySelectValueDialog** — a list value picker.
  - **TTySelectPathDialog** — a lazy directory-tree folder picker with **New Folder**, folder icons, and
    roomier, hover-tracking rows.
  - **TTyColorDialog** — a single-model, multi-view colour picker (HSV square + hue bar + RGB / CMYK /
    Alpha / Hex kept in sync).
  - **TTyFontDialog** — a font picker over family / size / style / colour / preview.
  - **TTyFindDialog / TTyReplaceDialog** — modeless Find / Replace (LCL `TFindOptions` parity, `OnFind` /
    `OnReplace`).
  - **TTyProgressDialog** — an app-driven modeless progress dialog with Cancel.
  - All 11 components carry **`OnShow` / `OnClose` / `OnCanClose`** events (LCL parity).
- **IDE integration** — a new **TyControls Dialogs** palette group, palette icons for all 11 dialogs, a
  File > New **TyControls Dialog** item, and **double-clicking** any dialog component in the designer
  previews it.
- **Examples** — a new standalone **dialogs example** showcasing all 11 dialogs; the main demo also gained a
  three-column dialog grid.

### Added — Three small controls

- **Tri-state CheckBox** — `State` / `AllowGrayed` with a grayed (indeterminate) glyph.
- **Editable ComboBox** — `csDropDown` free text with a prefix-autocomplete popup, forwarding `MaxLength` /
  `CharCase` to the embedded editor.
- **TTyTabSet** — a pure tab-strip control on the TabStrip engine (with a palette icon and component
  registration).

### Added — Examples overhaul

- Every single-control example was migrated to the **TTyForm + TTyTitleBar** chrome skeleton (no more raw
  LCL windows), and each broadened to exercise its control's key features (e.g. checkbox demos the tri-state,
  combobox the editable + autocomplete).
- Added 7 dedicated examples: tabset, calendar, datetimepicker, splitter, statusbar, toolbar and menu; the
  `tabcontrol` example was rewritten for TTyPageControl + TTyTabSheet.

### Fixed

- **Win10 DWM glass bleed** — every TTyForm gets a whole-client sheet-of-glass extend, so any pixel a
  control leaves at alpha 0 shows the glass (white when inactive). Fixed across the board: TTyPageControl /
  TTyTabSheet / TTyGroupBox caption band / the strip past the last tab / dialog content areas now **fill an
  opaque themed background** (new `TyPageControl` / `TyTabSheet` theme rules, synced to every built-in theme);
  the Vista–10 shadow extension moved to sheet-of-glass margins `{-1,-1,-1,-1}` to kill the 1px window-edge
  line that went white / grey on activation; `WM_NCACTIVATE` is intercepted so the inactive non-client frame
  never paints; and `TyResolveParentBg` now walks up past transparent containers to an opaque backdrop so
  rounded-control corner gaps fill.
- **Disabled-control glass** — a `:disabled` control's overall opacity was applied as `ApplyGlobalOpacity`,
  multiplying every pixel's alpha and turning the opaque background semi-transparent (white on deactivate).
  Replaced by `TTyPainter.OpacityBase`: lay down an opaque base first, then draw the faded content over it —
  identically dimmed, but alpha-255.
- **Resizable TTyForm side stripes** — `WM_NCCALCSIZE` no longer insets the client rect, so the
  `WS_THICKFRAME` native frame (DWM accent / white) is no longer exposed as left/right stripes.
- **Editable ComboBox** — the autocomplete popup no longer steals focus from the embedded editor (the 2nd
  keystroke was being lost); the popup re-sizes in place while typing (no flicker); and clicking a popup row
  reads the list actually shown (fixing a wrong-list read / wrong-text commit).
- **Tab-strip overflow arrows** overlapping the first / last tab — introduced `HeaderShiftPx` so tabs render
  inside the band between the arrows (affects both TTyTabSet and TTyPageControl).
- **TTyDateTimePicker** — opening the date drop-down no longer AVs when the picker is themed via the global
  default controller (`Controller` left nil, the normal case): the dropdown path now uses the nil-safe
  `ActiveController` instead of `FCalendar.Controller.Model`.
- **TTyProgressDialog flicker** — dropped the native TPanel host in favour of throttling the visual refresh
  to ~20fps (always keeping the newest position / text, and flushing 100% on completion), plus disabling the
  bar animation and fixing the status label width.
- **TTyForm double-click-maximize crash** — `ToggleMaximize` now guards a nil `Screen.MonitorFromWindow`
  (falling back to the primary monitor work area).
- **Internationalization** — load the `tycontrols` package catalog at runtime (the message-box button reads
  确定, not OK); deploy the catalog with a dot-free filename to dodge LCL's `ChangeFileExt` truncation; give
  the dialogs example its exe-name catalog and convert its hard-coded English code strings to
  resourcestrings; follow the OS locale by autodetect.
- **Example real-machine fixes** — several launch crashes (a status label used in `OnChange` before it was
  created), GroupBox caption-band overlap, a splitter docked to an un-draggable side, and several examples
  presenting a non-existent `StyleClass` variant as a feature.

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
