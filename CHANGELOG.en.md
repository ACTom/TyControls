# Changelog

All notable changes to **ty-controls** are documented in this file. The project uses
3-part semantic versions (`MAJOR.MINOR.PATCH`). Every control is fully custom-drawn via
BGRABitmap and themed by lightweight `.tycss` text themes — pixel-identical on Windows,
Linux and macOS.

> 中文版见 [CHANGELOG.md](CHANGELOG.md)。

## [3.0.0-RC] — 2026-08-31

Every issue reported against the Beta has been addressed; this is the release candidate for 3.0. From here the 3.0 line takes bug fixes only (the `3.0-fixes` branch).

### Added

- Structure editors: double-click (or right-click) a `TTyTreeView`, `TTyCascader`, `TTyTreeSelect` or `TTyListGroupPanel` to open a dedicated tree editor — the whole model in one tree, add/delete at any depth, move whole blocks up and down, and edit the selected node's properties right in the Object Inspector.
- `TTyTreeSelect` gains published `Items`: the dropdown tree can now be authored at design time and streams with the `.lfm` (it used to be code-only).
- `TTyListGroupPanel`: a design-time `Groups` nested collection (groups first, items under each); an `OnItemDblClick` event; `Tag` on groups and items; whole-sider collapse to an icon rail (`Collapsed`, with an optional bottom trigger band via `ShowCollapseTrigger`).
- `TTyTabSheet.TabVisible`: hide a page's tab while keeping the page; hide them all and switch from code for the wizard pattern.
- `TTyImageCollection`: double-click opens a TImageList-style manager — add, replace, rename, reorder, preview.
- `TTyChart` image export: `SaveToFile` / `SaveToStream` with PNG / BMP / JPG / TIFF and an explicit-format option.
- Design-time tab clicks switch pages on `TTyPageControl`, `TTyTabSet` and `TTyRibbon`; the PageControl context menu gains a "Show Page" jump list.
- Icon browser multi-pick: opened from an image list, each double-click adds the icon and shows its index badge at once, with the window staying open.

### Changed

- The license is pinned to the Modified LGPL-2.1 (or later) with the linking exception, matching the LCL.
- `TTyLucideImageList` no longer shows the irrelevant `Collection` / `IconFont` properties in the Object Inspector.

### Fixed

- Under themes with padding, `TTyMemo` and the list/dropdown family mis-measured their scroll range and row hit-testing, clipping the last line.
- `TTyMemo` now wraps mixed Latin/CJK lines at CJK characters instead of spaces only.
- Clicking a tab at design time left the mouse in a rubber-band selection; the Object Inspector kept showing a stale `ActivePageIndex` after a switch.
- A `TTyTabSet.TabIndex` set at design time was lost at run time.
- A collapsed `TTyListGroupPanel` rail made groups and items indistinguishable: groups now separate with a rule and icon-less rows show their caption's first glyph.
- `TTyCascader` painted the hover fill over the currently selected option.

## [3.0.0-Beta] — 2026-08-14

3.0 is the first stable release line. This release adds a large number of controls and aligns many APIs with the LCL; some of these changes are not backward compatible, so please read the Changed section before upgrading.

### Added

- Data grid `TTyStringGrid` / `TTyDrawGrid`: frozen rows/columns, million-row virtualization, multi-column sorting, conditional filtering plus an inline filter row, multi-level grouping with subtotals, cell merging, a summary band, 16 built-in editors plus a custom-editor interface, per-cell styling and borders, tree columns, drag-reordering of rows and columns, layout persistence, CSV import/export, Excel-compatible clipboard, per-cell `Objects[]`, `TStrings` views via `Rows` / `Cols`, and undo/redo.
- 14 modern UI controls: `TTyCard`, `TTyTag`, `TTyBadge`, `TTyAlert`, `TTyNotification`, `TTyPopover`, `TTySegmented`, `TTyPagination`, `TTySteps`, `TTyBreadcrumb`, `TTyTransfer`, `TTyTreeSelect`, `TTyCascader`, `TTyEmpty`.
- New controls `TTyFloatSpinEdit` (decimal spinner), `TTyLucideImageList` (image list backed by the bundled Lucide icons), `TTyIconBrowserDialog` (searchable icon browser).
- `TTyVirtualImageList` now inherits from `TCustomImageList` and can be assigned to any LCL or third-party control.
- Icons can be referenced by name: `TTyImage`, header columns, tabs, tree nodes, `TTyComboBoxEx`, and list-view items gained `ImageName` properties, so reordering an image list no longer changes which icon shows.
- `OnPaint` on every control, fired after the control finishes painting.
- `TTyForm.StyleOverride`: override a single form's appearance at runtime with a CSS snippet.
- `TTyTreeView` gained an `Items` node collection, editable at design time; virtual mode is unaffected.
- Tab strip: `TabPosition` (top/bottom/left/right), per-tab icons, `MultiLine`.
- Combo box: owner-draw (`csOwnerDrawFixed`, …), the always-visible `csSimple` list, per-item heights, `ItemHeight` / `TextHint` / `ReadOnly`, writable `DroppedDown`, `SelStart` / `SelText`, `OnGetItems` lazy loading; list-box horizontal scrolling (`ScrollWidth`).
- `TTyToolBar`: six `TTyToolButton` styles, `Grouped` adjacency groups, `HotImages` / `DisabledImages`, `ShowCaptions`, `ButtonWidth` / `DropDownWidth` / `List`, `OnPaintButton`, explicit row breaks.
- Date-time picker: null-date support (`NullInputAllowed` / `NullDate` / `TextForNullDate`), two-digit years expanded via `CenturyFrom`, `LeadingZeros`, `Esc` reverts the whole edit, A / P keys set AM/PM, Space toggles the check box.
- `TTyUpDown`: two-way `Associate` binding, `OnChanging` / `OnChangingEx` veto events, a directional `OnArrowClick`, `MinRepeatInterval`.
- Text controls: `TTyMemo.Alignment` / `CharCase`, `TTyEdit.EchoMode`, `Modified`, multicast `OnChange`, public `CaretLine` / `CaretCol` / `SetCaret`, accessibility roles.
- Shapes: `TTyShape` covers all 15 LCL shapes plus custom polygons (`OnShapePoints`) and `OnShapeClick`; `TTyStarShape.PointDown`; triangular `TTyArrow` heads.
- `TTyImage`: shared image lists (`Images` / `ImageIndex`), `StretchInEnabled` / `StretchOutEnabled`, `KeepOriginXWhenClipped` / `KeepOriginYWhenClipped`, `AntialiasingMode`, `OnPictureChanged`.
- `TTyImageCollection.Images` streams to the `.lfm`, editable at design time; same-name entries form a multi-resolution set.
- Docking: `TTyPanel` / `TTyGroupBox` / `TTyPageControl` / `TTyControlBar` support `DockSite` and the full set of docking events.
- Track-bar ticks (`TickMarks` / `TickStyle` / `Reversed`); progress bar `Step` / `StepIt` / `StepBy`, on-bar text, four orientations.
- `TTyScrollBar.LiveTracking`; `TTySplitter.AutoSnap`; `TTyPanel.VerticalAlignment`; `TTyDivider.LeftIndent`.
- Status bar `AutoHint` and owner-drawn panels (`OnDrawPanel`); menu bar `RightJustify`; popup-menu owner-draw protocol, `TrackButton`, `SubMenuImages`, `GlyphShowMode`.
- Grid `Options` set: about 21 LCL behavior flags in one place.
- Calendar and date-picker month and weekday names follow the application language.
- Group controls: `Buttons[]` / `CheckEnabled[]` / `OnItemClick`, arrow-key navigation between items.
- List, combo, check, and color controls gained many LCL members: tri-state `State[]`, `ItemEnabled[]`, writable `Colors[]`, `OnSelectionChange`, `ExtendedSelect`, design-time-editable `TTyComboBoxEx.ItemsEx`, and more.
- Shell controls: `Root` / `Path` / `ObjectTypes` / `FileSortType` / `OnAddItem`, plus cross-linking between tree, list, and filter combo.
- Value list editor: `KeyOptions`, writable `Keys[]`.
- Themes: new semantic colors `--success` / `--warning`; badge tokens `--badge-inset` / `--badge-min-size`.
- New example antdesign: an Ant Design Pro-style admin with runtime theming.

### Changed

- A `TTyForm`'s visual controls now live on the content container `Surface` (`TTyFormSurface`); existing forms must move their controls into `Surface`. Non-visual components and `TTyDialog` are unaffected. See [docs/controls/ttyform.md](docs/controls/ttyform.md).
- `TTyMaskEdit` now uses the LCL / Delphi mask language (`0` / `9` / `L` / `A` / `C` / `H` / `B`, case sections, `;` parts); old-syntax `#` masks raise an exception. An empty masked edit now shows the placeholder (`SpaceChar`), `Text` returns the display string (use the new `MaskedValue` for the value), losing focus validates and raises `ETyMaskError` when incomplete (`ValidateEdit` can be called explicitly), and assigning `Text` goes through the mask like pasting does.
- `TTyMemo.SelStart` / `SelLength` count full line breaks, matching offsets into `Text`.
- `TTyEdit` / `TTyMemo` `ClearSelection` now deletes the selected text (LCL semantics); the old collapse-only behavior is renamed `CollapseSelection`.
- `TTyListBox.Items` changed type from `TStringList` to `TStrings`.
- All `Images` properties are now `TCustomImageList` and accept both the library's vector lists and plain LCL image lists.
- `TTyVirtualImageList` / `TTyGlyphImageList` `Draw` now uses the LCL parameter order `(Canvas, X, Y, Index, Enabled)`; the sized variant is renamed `DrawIndex`. Old four-integer calls fail to compile.
- Data grid: `VisibleRowCount` now means rows that fit the viewport (use `FilteredRowCount` for the filtered row count); `ClearRows` / `ClearCols` now delete rows/columns (use `ClearRowContents` / `ClearColContents` to clear contents); `SaveToStream` / `LoadFromStream` now store the full layout (use `SaveToCSVStream` / `LoadFromCSVStream` for CSV); `Selection` is writable; the new `Objects` / `Cols` / `Rows` may collide with same-named members in descendants (a compile-time duplicate-identifier error).
- `TTyValueListEditor`: `Values` is now keyed by name (use `ValueFromIndex` for row access) and `ValueOf` is gone; `VisibleRowCount` now means rows that fit the viewport (the old meaning is `DisplayRowCount`); `InsertRow` uses the LCL signature; `RowCount` is writable.
- `TTyTreeView`: `GetNodeAt(X, Y)` now has the LCL meaning (the old method is `GetNodeAtOffset`); `Selected` now returns the current node (use `NodeSelected[]` for by-index access); `OnDragOver` and the other LCL drag events belong to the application again (in-tree drag vetoing moved to `OnNodeDragOver`).
- `TTyListView` `OnChange` / `OnChanging` / `OnSelectItem` now use the LCL signatures; re-selecting an already-selected row no longer fires `OnSelectItem`.
- `TTyScrollBox.ScrollBy` and `TTyMemo.ScrollBy` now scroll the view / the text.
- `TTyImage`: `Proportional` no longer upscales; `Center` and `Transparent` default to `False` (matching `TImage`) — forms relying on the old defaults must set them explicitly.
- `TTySpinEdit`: `MaxValue` defaults to 0 (no limit); `MinValue = MaxValue` means unlimited; `OnChange` now fires on every keystroke, with committed-value changes reported by the new `OnValueChange`.
- `TTyDateTimePicker`: assigning `DateTime` from code no longer fires `OnChange` (opt back in with `dtpoDoChangeOnSetDateTime`); format strings are no longer silently doubled; clicking an adjacent month's gray cell selects it and flips the month (restore the old behavior with `dsNoMonthChange`).
- `TTyCalendar`: `FirstDayOfWeek` defaults to following the system; out-of-range `Date` assignments raise (use `SetDateClamped` to clamp).
- Out-of-range `TTyCheckGroup.Checked[]` and `TTyRadioGroup.ItemIndex` assignments raise.
- `TTyCheckGroup` / `TTyRadioGroup` multi-column layout defaults to row-major (new `ColumnLayout` property, LCL default); single-column groups are unaffected.
- `TTyToolBar.Indent` is horizontal-only; vertical padding moved to the new `ContentPadY`.
- Shell controls: `TTyShellListView.Refresh` renamed `UpdateView`; `TTyShellTreeView.SelectPath` is now a `Boolean` function and assigning an invalid `Directory` raises; directory expansion re-reads the disk by default (`ecmKeepChildren` restores the old behavior); the 7 published event slots (`OnGetText`, …) belong to the application again.
- `TTyScrollPanel.AutoScroll` renamed `AutoPan`.
- `TTyPanel` / `TTyTabSheet` / `TTyDivider` `Caption` and `Text` are unified.
- `TTyCheckComboBox`: `Objects[]` belongs to the application; the item state's `Checked` became `State: TCheckBoxState` plus a new `Enabled`.
- `TTyColorButton`: new LCL-compatible `ButtonColor` and `OnColorChanged`; `OnColorChange` now fires on any color change; `Caption` parses `&` mnemonics.
- `TTyEdit.PasswordChar := #0` now disables masking.
- `TTyGauge` no longer publishes `Caption`.
- `TTyTabStrip.TabHeight`: negative means automatic height; 0 still hides the strip.
- `TTyHeaderControl`: the three section events' first parameter is now typed `TTyHeaderControl`; `OnSectionResize` fires once on release, with the drag reported by the new `OnSectionTrack`.
- `TTyUpDown`: `OnArrowClick` fires after the value changes; `Wrap` carries over instead of discarding overflow.
- `TTyTrackBar`: `Frequency` defaults to 1; `Orientation` swaps width and height.
- `TTyPaintPanel` design-time default size is now 105×105.
- `TTyGlyphLayout` gained `glRight` / `glBottom` (appended at the end); `HasGlyphSource` renamed `CanShowGlyph` and made public.
- Theme tokens: the spin-button arrow override tokens renamed from `--glyph-arrow-up/down` to `--glyph-triangle-up/down`.

### Fixed

- Editable combo boxes no longer draw a double border.
- Spin buttons, scroll-bar ends, and tab-strip scroll keys now draw solid triangles; their oversized icon padding is fixed too.
- Menu-button and date-picker dropdown markers now match the combo box.
- Track bar: the track is now a centered groove (new theme key `TyTrackGroove`) and ticks no longer overlap it.
- Trailing widgets in the edit family sit at a consistent distance from the border.
- `window-shadow: false`: the shadow actually turns off; deactivating no longer reveals a classic system caption; edge resizing works; fixed-size windows now get a shadow too.
- At 250% scaling the title bar is no longer double height and the min/max/close glyphs are no longer overweight.
- Cross-monitor DPI (PerMonitorV2) round trips restore the layout exactly.
- The aero theme gained a real dark mode; classic is pinned light; the danger button works in all 15 built-in themes; black corner blocks under aero are gone.
- Windowed controls on gradient containers rebuild their background from the matching gradient slice instead of a flat color.
- Radio groups: clicking focuses the clicked item; rows no longer overlap; the whole group is a single tab stop.
- CoolBar / ToolBarEx / ControlBar: children no longer erase the container border; CoolBar grip dragging matches the native rebar and supports reordering.
- Scroll box: no more flicker while dragging; anchored children inside the viewport scroll along.
- Read-only grids block paste, cut, and the fill handle; per-cell/per-column locks apply to filling; Ctrl+X added.
- Grid: oversized pastes grow the grid instead of dropping data; CSV fields containing newlines parse correctly; the sort triangle shows; grouping no longer drops the sort column; merged ranges follow row/column insertion; `hoAutoResize` and header icons work; null rows keep their position when the sort direction flips.
- A batch of set-but-ignored members now work: `TTySplitter.ResizeStyle`, toolbar `ShowCaptions`, tree-node `Ghosted`, popup-menu `OnPopup` / `Close` / dynamic items, `TTyColorButton.Caption`, `TTyScrollBar.LargeChange`, `TTyColorBox.Style`, menu-item `ShowAlwaysCheckable`, `TTyPanel.BorderWidth`, and `ActivePage` and friends are now published.
- Masked edit: pasting and `InjectBackspace` / `InjectDelete` no longer bypass the mask; Delete no longer removes mask literals.
- Menus: disabled top-level menus draw gray and don't open; caption-only top-level items fire `OnClick`; item `Hint` reaches `Application.Hint`; unchecked `AutoCheck` items draw an empty check box; disabled item icons draw gray.
- `TTyShape` / `TTyStarShape` hit-test against the actual shape; `PtInShape` is public.
- The localized check-box true word applies immediately; toolbar captions measure and draw with the same engine, so English no longer truncates; the Ribbon File tab is translatable; ~740 strings across 43 examples are translatable.
- 42 examples gained application manifests (common-controls v6 and DPI declarations).
- `TTySpeedButton.Down := True` releases the rest of its group; single-select list-box `ClearSelection` works; assigning an off-palette color to the color combo no longer appends a row; `ShowHidden` applies immediately; the file list re-reads the disk after an F2 rename; `TTyShellListView.OnCompare` is called; file-size units are translatable.
- Header control: the last section reports its real width (new `EffectiveSectionWidth`); width constraints apply on all four resize paths; header icons draw.
- Drag-reordering tabs no longer desyncs headers from pages; a page moved to another `TTyPageControl` is released by its old owner.
- The File → New TyControls Dialog template no longer produces two title bars or an `EClassNotFound` error.
- The unpainted right/bottom edge line on borderless resizable windows is gone.
- macOS: Chinese text renders crisp and complete; the IME candidate window follows the caret (Edit / Memo).
- GTK2: container panels no longer render black; modal dialogs can be dragged.
- `TTyMemo`: the caret lands correctly after Backspace at a line's end and at the last line's start.

### Performance

- Grid cell text is cached across frames; scrolling a large grid spends about 1/20 of the previous paint time.
- Cross-monitor DPI synchronization is 42% faster.

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
