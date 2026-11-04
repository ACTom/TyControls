# Changelog

All notable changes to **ty-controls** are documented in this file. The project uses
3-part semantic versions (`MAJOR.MINOR.PATCH`). Every control is fully custom-drawn via
BGRABitmap and themed by lightweight `.tycss` text themes — pixel-identical on Windows,
Linux and macOS.

> 中文版见 [CHANGELOG.md](CHANGELOG.md)。

## [3.0.4] — 2026-11-04

A bug-fix release for 3.0. Every control's properties and events were checked: settings that did nothing, crashes and lost data are fixed. Borders and text are sharper, and every part of the table can be themed.

### Added

- Every part of the table can be themed: grid lines (colour, width, style and hiding, per direction), the header (separators, the rule below it, padding, font size and weight, the sorted and filtered looks), the sort mark, the hover scope, the selected-hover colour, the focus frame, the frozen line and its shadow, the footer rule and the current row number. One grid takes them in its `StyleOverride`; see the [tycss reference](docs/tycss-reference.en.md). ([#197](https://github.com/ACTom/TyControls/issues/197))
- A control's `StyleOverride` can set `--` tokens, for that control only. ([#98](https://github.com/ACTom/TyControls/issues/98), [#99](https://github.com/ACTom/TyControls/issues/99))
- The gap from a list or tree icon to its caption, and the tree main column's leading inset, are tokens. ([#98](https://github.com/ACTom/TyControls/issues/98), [#99](https://github.com/ACTom/TyControls/issues/99))
- Tree lines and the expander can be themed. ([#101](https://github.com/ACTom/TyControls/issues/101))
- Text fields' side padding and the room around the drop arrow are the tokens `--pad-field` and `--field-drop-pad`. ([#102](https://github.com/ACTom/TyControls/issues/102), [#103](https://github.com/ACTom/TyControls/issues/103))
- `GlyphKind` has a new value `tgNone`, so a glyph can be removed in the designer. ([#129](https://github.com/ACTom/TyControls/issues/129))

### Changed

- Borders, rounded fills and scroll bar thumbs land on whole pixels, so every control with a border changes by some pixels: straight edges are thinner and solid. ([#196](https://github.com/ACTom/TyControls/issues/196))
- Latin text on Windows now matches LCL and ordinary GDI programs pixel for pixel, as Chinese already did. Latin captions are slightly narrower, so an `AutoSize` control can change by a few pixels. ([#199](https://github.com/ACTom/TyControls/issues/199))
- The default table header is a light band with regular weight, and the built-in skins have table looks of their own. ([#197](https://github.com/ACTom/TyControls/issues/197))
- Expand, drop-down and submenu arrows share one shape, with size and colour from the theme. ([#100](https://github.com/ACTom/TyControls/issues/100))
- Text in a field starts further from the left border, matching the drop arrow on the right. ([#103](https://github.com/ACTom/TyControls/issues/103))
- `TTyRibbonQuickAccess` honours `Indent` and `Spacing`. With the defaults, buttons move 3 px right and sit 2 px further apart. ([#117](https://github.com/ACTom/TyControls/issues/117))
- `OnClick` on `TTyCheckBox` and `TTyRadioButton` fires when `Checked` changes, from code too, as in LCL, and not for a click on a radio button already checked. `TTyRadioGroup.OnClick` fires when `ItemIndex` changes. ([#188](https://github.com/ACTom/TyControls/issues/188))
- `#` in a `TTyMaskEdit` mask is a digit or sign that may be left out, as in LCL. A `##` from 2.x is now optional; write `00` to require the digits. ([#193](https://github.com/ACTom/TyControls/issues/193))
- A `TTyForm` maximized from its title bar reports `wsMaximized` in `WindowState` and fires `OnWindowStateChange`. ([#193](https://github.com/ACTom/TyControls/issues/193))
- `TTyEdit`, `TTyMemo`: text set from code or loaded with the form is where undo starts, so Ctrl+Z no longer empties a pre-filled field. ([#156](https://github.com/ACTom/TyControls/issues/156))
- `TTyDateTimePicker`: moving with the arrow keys in the drop-down calendar no longer changes the value; a click or Enter does, and Esc after that still goes back. `MinDate` and `MaxDate` limit by date, so a time on the `MaxDate` day stays. ([#160](https://github.com/ACTom/TyControls/issues/160))
- Menus: a menu taller than the work area scrolls; `AutoLineReduction` (the default) drops separators at the ends and in a row, always on Lazarus 3.x, which has no such property; opening a submenu fires its item's `OnClick`. ([#175](https://github.com/ACTom/TyControls/issues/175))
- `TTyRibbon`: KeyTips show and hide on a single press of Alt, as in Office, and no longer touch the form's `KeyPreview` and `OnKeyDown`. The File tab has a KeyTip too. ([#177](https://github.com/ACTom/TyControls/issues/177))
- `TTyBalloonHint` and `TTyNotification` no longer take the keyboard focus when they appear. ([#178](https://github.com/ACTom/TyControls/issues/178))
- `TTyRating.Value` rounds to whole stars, or half stars with `AllowHalf`, with halves going up: 2.5 stars is 3. ([#181](https://github.com/ACTom/TyControls/issues/181))
- `TTyComboBox` takes one Tab stop. In the open list, Up and Down move the highlight, Enter, Tab and F4 pick it, and Esc does not. ([#161](https://github.com/ACTom/TyControls/issues/161))
- With `goTabs`, Tab at the last cell (Shift+Tab at the first) leaves the grid, as in LCL. ([#139](https://github.com/ACTom/TyControls/issues/139))
- Properties that cannot act on a control are hidden in the designer: `CharCase` on numeric edits, `MaxLength`, `CharCase` and `ReadOnly` on pick-only combo boxes, the shell views' `Items` and the like, `ChildSizing` on text inputs, and the generated `Items` of `TTyFilterComboBox` and `TTyShellComboBox`. Forms that set them still open. ([#130](https://github.com/ACTom/TyControls/issues/130), [#163](https://github.com/ACTom/TyControls/issues/163), [#167](https://github.com/ACTom/TyControls/issues/167), [#192](https://github.com/ACTom/TyControls/issues/192))
- A form saved with 3.0.4 may not open or read back fully in an earlier 3.0.x if a `TTyValueListEditor` has rows, a `TTyFontListBox` has a font selected, or the title bar pins its button width. ([#152](https://github.com/ACTom/TyControls/issues/152), [#167](https://github.com/ACTom/TyControls/issues/167))

### Fixed

- Crashes after freeing an image list, a scroll box's content, a ribbon group or a cool band's control. ([#136](https://github.com/ACTom/TyControls/issues/136))
- Crashes when `Items` change during a click, or under a node or line a control still holds (radio and check groups, tree select, tree, memo). ([#137](https://github.com/ACTom/TyControls/issues/137))
- Gauges and meters raised an exception on every paint when `ValueFormat` had no float specifier. ([#138](https://github.com/ACTom/TyControls/issues/138))
- `TTyTrackBar` hung while painting with a large range and `Frequency` = 1. ([#187](https://github.com/ACTom/TyControls/issues/187))
- On a sorted, filtered or grouped grid or one with hidden rows, the arrow and page keys, Enter and the fill handle landed on the wrong rows; Ctrl+Home and Ctrl+End missed the first and last row; Tab and Enter did not reach the next cell while editing. ([#139](https://github.com/ACTom/TyControls/issues/139))
- Grid cut, editors and `Cells` writes lost or changed data: Ctrl+X cleared cells it had not copied, opening an editor and leaving it rewrote the cell, and a `Cells` write outside the grid raised nothing. ([#140](https://github.com/ACTom/TyControls/issues/140))
- List views, tree views and shell lists lost or moved the selection and the user's changes when the items changed. ([#141](https://github.com/ACTom/TyControls/issues/141))
- Values set in the designer were lost or changed when the form was reopened (`Cursor`, `Alignment`, `ExpandedHeight`, a saved multi-selection, column `Position` and `Width` and others). ([#108](https://github.com/ACTom/TyControls/issues/108), [#152](https://github.com/ACTom/TyControls/issues/152))
- A control's `Font.Size` and a container's `Font` for its children lost to the theme. ([#112](https://github.com/ACTom/TyControls/issues/112))
- Text in list rows, grid cells, tabs, headers, segments, gauges and charts ignored the control's `Font` and `StyleOverride`. ([#113](https://github.com/ACTom/TyControls/issues/113))
- `AutoSize := True` did nothing on 67 controls, and some did not fit again after a theme change. ([#114](https://github.com/ACTom/TyControls/issues/114))
- `BorderWidth` only worked on `TTyPanel`. ([#115](https://github.com/ACTom/TyControls/issues/115))
- Disabled controls, and the children of a disabled container, looked enabled. ([#118](https://github.com/ACTom/TyControls/issues/118))
- Controls did not lay out again after a theme, font or `StyleOverride` change. ([#146](https://github.com/ACTom/TyControls/issues/146))
- A one-property additive rule erased a control the theme leaves to the built-in layer. ([#106](https://github.com/ACTom/TyControls/issues/106))
- Children covered the frame, rounded corners and separator lines of panels, page controls, cards, group boxes and others. ([#133](https://github.com/ACTom/TyControls/issues/133))
- Controls on hidden pages answered Alt+key, and a few controls handled it wrongly. ([#142](https://github.com/ACTom/TyControls/issues/142))
- Clicks took the focus with `TabStop = False`; the menu bar took the focus from an edit, and F10 now opens its first menu; some focusable controls ignored the keyboard. ([#143](https://github.com/ACTom/TyControls/issues/143))
- Enter and Esc were swallowed, so the form's default and cancel buttons did not respond. ([#144](https://github.com/ACTom/TyControls/issues/144))
- Events fired while a form was loading or being destroyed. ([#145](https://github.com/ACTom/TyControls/issues/145))
- Drags kept going after the mouse capture was lost. ([#147](https://github.com/ACTom/TyControls/issues/147))
- Pop-ups were placed against the primary monitor only, and opened off screen on another one. ([#148](https://github.com/ACTom/TyControls/issues/148))
- Animation timers kept running while hidden and in the designer, and `TTyAnalogClock.Time` was saved in the form. ([#149](https://github.com/ACTom/TyControls/issues/149))
- Text inputs: AltGr ran shortcuts instead of typing on Polish and similar keyboards, and `OnKeyPress` could not filter the typed character. ([#150](https://github.com/ACTom/TyControls/issues/150))
- Buttons and check boxes: a held Space or Enter clicked repeatedly, and a quick second click was lost. ([#151](https://github.com/ACTom/TyControls/issues/151))
- Right-to-left: drop-downs, list rows, panel headers, popup menus and some labels did not mirror. ([#153](https://github.com/ACTom/TyControls/issues/153))
- Controls overwrote the application's `Cursor`, `Hint` and `ShowHint`. ([#154](https://github.com/ACTom/TyControls/issues/154))
- `TTyMemo`: a tab had no width, so tab-separated text ran together. The width is the token `--memo-tab-size`. ([#97](https://github.com/ACTom/TyControls/issues/97))
- `TTyMemo` fired no `OnChange` for a change through `Lines`. ([#110](https://github.com/ACTom/TyControls/issues/110))
- Numeric edits accepted pasted letters, and `TTyEdit.Text :=` ignored `CharCase`. ([#122](https://github.com/ACTom/TyControls/issues/122))
- `TTyEdit`: Shift+Del, Shift+Ins, Ctrl+Ins, Ctrl+Home, Ctrl+End, undo while read-only, `CharCase`, and copy and cut in a password field differed from LCL. ([#156](https://github.com/ACTom/TyControls/issues/156))
- `TTyMemo`: `ClearSelection`, `Clear`, `MaxLength`, Page Up and Down, drag-select scrolling and the wheel's line count were wrong. ([#157](https://github.com/ACTom/TyControls/issues/157))
- `TTyMaskEdit`: cut, paste, `SelText` and the IME could break the mask, and the focus did not return after a failed validation. ([#158](https://github.com/ACTom/TyControls/issues/158))
- Numeric edits: malformed text became 0, `OnChange` fired on every focus change, and buttons, sliders and menus changed the value while read-only. ([#159](https://github.com/ACTom/TyControls/issues/159))
- `TTySpinEdit` stepped from the old value, not the one typed, and `TTyUpDown` fired `OnChange` twice for a click after typing. ([#160](https://github.com/ACTom/TyControls/issues/160))
- `TTySpinEdit`: tabbing in and typing added to the value instead of replacing it. ([#189](https://github.com/ACTom/TyControls/issues/189))
- `TTyCalcEdit` and `TTyCalcCurrencyEdit` wrote the value back however the calculator closed, so Esc and a click away set the field to 0. ([#191](https://github.com/ACTom/TyControls/issues/191))
- Buttons: `Default` and `Cancel` set in code had no effect and the default button did not look like one; `TTySpeedButton` groups and `AllowAllUp` differed from LCL; `TTyColorButton` closed the form even when its dialog was cancelled. ([#119](https://github.com/ACTom/TyControls/issues/119))
- Combo boxes: `ItemHeight` set back to 0 kept its height, `Text :=` did not select the matching item, renaming the selected item cleared the selection, and the list highlight did not follow `Text`. ([#120](https://github.com/ACTom/TyControls/issues/120))
- `TTyColorComboBox` lost its "More..." row on a form, and the swatch properties and `cbIncludeNone` did nothing. ([#121](https://github.com/ACTom/TyControls/issues/121))
- Combo boxes: keys in the list and the field, `CloseUp`, the selection after item changes and the text of derived combo boxes were wrong. ([#161](https://github.com/ACTom/TyControls/issues/161))
- `TTyTreeSelect` and `TTyCascader` showed no text after a pick, and a reopen guard blocked `DropDown` from code. ([#162](https://github.com/ACTom/TyControls/issues/162))
- `TTyColorComboBox` changed the value twice for "More...", `TTyFilterComboBox` did not filter after loading, and `TTyShellComboBox` was empty without a `Directory`. ([#163](https://github.com/ACTom/TyControls/issues/163))
- List view report rows: the icon ignored `--listview-text-margin`. ([#98](https://github.com/ACTom/TyControls/issues/98))
- The tree's main column had no leading inset. ([#99](https://github.com/ACTom/TyControls/issues/99))
- Tree lines ran through the expander. ([#101](https://github.com/ACTom/TyControls/issues/101))
- List boxes: `ItemIndex :=` selected nothing with `MultiSelect`, inserts and deletes moved the selection to other rows, and arrow keys cleared it with `ExtendedSelect = False`. `TTyOfficeListBox` could select header rows. ([#123](https://github.com/ACTom/TyControls/issues/123))
- `TTyValueListEditor`: `Sorted` lost rows, the splitter and editor did not follow `ScrollWidth`, and an open editor still committed after `ReadOnly` was set. ([#124](https://github.com/ACTom/TyControls/issues/124))
- `TTyListView`: `Header.SortColumn`, `SortDirection`, `AutoSizeIndex` and `RowSelect` did nothing, editing with `MainColumn` still used column 0, and `AutoSort` also stopped sorting after item changes. ([#125](https://github.com/ACTom/TyControls/issues/125))
- `TTyTreeView`: changing `EmptyListMessage` did not repaint, and `Header.AutoSizeIndex` applied only on resize. ([#126](https://github.com/ACTom/TyControls/issues/126))
- Header options on list views, trees and grids (hover, column drag, click, sort switches, auto-spring, images, alignment) did nothing, and a grid header click also fired for a drag or a filter button. ([#155](https://github.com/ACTom/TyControls/issues/155))
- List boxes: a keyboard selection fired no `OnClick`, and `ItemHeight` 0, type-to-find, drag-select and horizontal scrolling were wrong. ([#164](https://github.com/ACTom/TyControls/issues/164))
- `TTyListView`: a right-click did not select, hover hit the wrong row in groups, the cut and disabled looks, horizontal scrolling and rename events were wrong, and the shell tree and list were not in step. ([#165](https://github.com/ACTom/TyControls/issues/165))
- `TTyTreeView`: Insert collapsed the node, a node expanded unsorted, `OnPaintText` could not change the font, and a double-click on the expander toggled once too often. ([#166](https://github.com/ACTom/TyControls/issues/166))
- `TTyValueListEditor` lost its rows when the form was reopened, `TTyTransfer` dropped `Objects` on a move, and `TTyListGroupPanel` did not report a click on the selected item. ([#167](https://github.com/ACTom/TyControls/issues/167))
- `TTyDrawGrid`: `OnClickCell`, `OnRightClickCell`, `OnCellButtonClick` and `OnHeaderRightClick` never fired. ([#109](https://github.com/ACTom/TyControls/issues/109))
- `TTyStringGrid`, `TTyDrawGrid`: a dragged column stayed where it was on screen. ([#111](https://github.com/ACTom/TyControls/issues/111))
- Grids: `MainColumn`, `AutoSizeIndex`, `IndicatorWidth`, `ShowIndicator`, `HeaderGroups`, `DefaultColWidth`, sorting and width limits did nothing or did not update. ([#127](https://github.com/ACTom/TyControls/issues/127))
- Grids: double-click, keyboard selection, `OnScrollHint`, `OnEditChange`, `OnCanEditCell`, `OnCanSort` and the end-of-resize events fired wrongly or not at all. ([#168](https://github.com/ACTom/TyControls/issues/168))
- Grids: inserting or deleting columns and rows misplaced sort keys, the cursor and header groups; sort settings, footers, find and replace, CSV load, Esc in the filter row, Delete and `UndoLimit` were wrong. ([#169](https://github.com/ACTom/TyControls/issues/169))
- Grids: a read-only check cell showed 1, `FixedRows` counted twice in the scroll range, the horizontal wheel was wrong, and changing a column colour at run time did not repaint. ([#170](https://github.com/ACTom/TyControls/issues/170))
- Grid text did not match other controls': heavier on dark themes, lighter on light ones, and without ClearType. ([#198](https://github.com/ACTom/TyControls/issues/198))
- `TTyExPanel` and `TTyPaintPanel` captions ignored `Alignment`, `VerticalAlignment`, `WordWrap` and `ShowAccelChar`. ([#116](https://github.com/ACTom/TyControls/issues/116))
- `TTyStatusBar` did not draw `SimpleText`, a `TTyCoolBar` band without a control took no place, `TTyListGroupPanel` heights lost to the theme, and `TTyImageView` zoom limits did not hold. ([#128](https://github.com/ACTom/TyControls/issues/128))
- `TTyCoolBar`: vertical bands all came out `BandHeight` long. ([#131](https://github.com/ACTom/TyControls/issues/131))
- `TTyCoolBar`: band captions (`ShowText`) were never drawn. ([#132](https://github.com/ACTom/TyControls/issues/132))
- Radio, check and button groups moved the selection to other items when `Items` changed; `ItemIndex` on a multi-select button group was wrong; radio buttons did not update when moved to another group. ([#171](https://github.com/ACTom/TyControls/issues/171))
- Check boxes, radio buttons, toggle switches and speed buttons did not follow an Action's `Checked` and `GroupIndex`, and a toggle switch did not show the Action's caption. ([#172](https://github.com/ACTom/TyControls/issues/172))
- Page controls: moving a page changed the active page, a switch lost the focus, side and multi-line tabs did not reflow, and `ActivePage := nil` was wrong. A tab set did not report the removal of its selected tab. ([#173](https://github.com/ACTom/TyControls/issues/173))
- `TTyExPanel` kept collapsed children in the Tab order, a group box's `Text` was its name, and card hover, the splitter's range, `TTyGridPanel`, `TTyRelativePanel` and a scroll box's controller change were wrong. ([#174](https://github.com/ACTom/TyControls/issues/174))
- macOS: drop-downs, menus and popovers opened in a modal dialog showed behind it. ([#104](https://github.com/ACTom/TyControls/issues/104))
- Menus: menu bar updates, actions and `Close` were wrong. ([#175](https://github.com/ACTom/TyControls/issues/175))
- A menu's `BannerCaption` was off-centre and partly cut off. ([#201](https://github.com/ACTom/TyControls/issues/201))
- `TTyToolBarEx` brought hidden buttons back and clipped its rows; tool button menus and the status bar's size grip were wrong; control and cool bars used the control's name as a caption, and cool band width limits did not hold. ([#176](https://github.com/ACTom/TyControls/issues/176))
- Ribbon: the gallery's inline row missed an item picked in its pop-up, arrow keys were wrong in the backstage, and the application menu lost submenus. ([#177](https://github.com/ACTom/TyControls/issues/177))
- Hints ignored `MaxWidth` and the DPI of the monitor they were on. ([#178](https://github.com/ACTom/TyControls/issues/178))
- `TTyBalloonHint` and `TTyPopover`: the arrow slid into the rounded corner. ([#134](https://github.com/ACTom/TyControls/issues/134))
- `TTyBalloonHint.Controller` sized the balloon but did not paint it. ([#135](https://github.com/ACTom/TyControls/issues/135))
- Dialogs: the dialog took Enter before the focused control, so a memo could not start a new line and Enter on No or Cancel returned the default button's result; find and replace events and progress were wrong; file dialogs asked `OnCanClose` on cancel and did not return `FilterIndex`; folder and value dialogs could be accepted with nothing chosen. ([#179](https://github.com/ACTom/TyControls/issues/179))
- Scroll bars did not repeat while a button was held, sent no end-of-scroll event and kept their size when `Kind` changed; arrow keys across the axis leaked to the form from scroll and track bars; the calendar's arrow keys in its views, `MinDate` after `MaxDate`, the lightness bar's limits and the calculator's focus were wrong. ([#180](https://github.com/ACTom/TyControls/issues/180))
- Gauges did not clamp `Value` when `Min` or `Max` changed; level meter segments, the sparkline's last point and the pie legend were wrong; `TTyHtmlLabel` did not wrap CJK text; glow and shadow labels were clipped; several fixes to images, badges and link labels. ([#181](https://github.com/ACTom/TyControls/issues/181))
- The month arrows of `TTyCalendar` and the drop-down calendar are now the library's own. ([#194](https://github.com/ACTom/TyControls/issues/194))
- `TTyValueListEditor`: `OnEditingDone` fired when an edit started; Ctrl+Enter now opens the dialog, Alt+Left and Alt+Right expand and collapse, and one click on the ... button opens it. ([#195](https://github.com/ACTom/TyControls/issues/195))
- Scroll bars and bordered controls looked blurry, with borders and rounded fills spread across two pixels. ([#196](https://github.com/ACTom/TyControls/issues/196))
- The header and row fills covered the frame of grids and lists, the whole header turned hover when the mouse was anywhere on a grid, and grid lines covered the selection frame. ([#197](https://github.com/ACTom/TyControls/issues/197))
- On Windows, text in controls without a background (labels, links and others) had no ClearType and looked softer than the rest. ([#200](https://github.com/ACTom/TyControls/issues/200))
- Expand, drop-down and submenu arrows had wrong shapes, were oversized and blurred; a drop field's arrow sat too close to the border and lost part of its second arm. ([#100](https://github.com/ACTom/TyControls/issues/100), [#102](https://github.com/ACTom/TyControls/issues/102))
- Designer: switching off a title bar button hid the one next to it. ([#105](https://github.com/ACTom/TyControls/issues/105))

### Performance

- Text-heavy repaints on Windows are faster: a run of text no longer asks the system whether ClearType is on. ([#107](https://github.com/ACTom/TyControls/issues/107))

## [3.0.3] — 2026-10-20

A bug-fix release for 3.0, mostly for macOS: sharp drawing on Retina screens, the system's window frame, and building the macOS version with Lazarus 3.x.

### Changed

- On macOS a `TTyForm` window now uses the system's window frame: rounded corners, the shadow, the traffic-light buttons, resizing from the edges, tiling and zoom are all the system's. Set `TTyTitleBar.MacTrafficLights` to False for the title bar's own drawn buttons. ([#80](https://github.com/ACTom/TyControls/issues/80), [#89](https://github.com/ACTom/TyControls/issues/89))
- On a macOS Retina screen a `TTyPainter` layer is twice the control's size. Code that works on `Bitmap` directly (`FillRect`, `PutImage` and so on) in `OnPaintSurface`, `OnDrawCell` and the like converts control coordinates to layer pixels with `Dev()`; see the [events documentation](docs/events.en.md#drawing-on-the-layer-on-a-retina-screen). `TyDeviceScaleRendering := False` takes all drawing back to one times. Windows and Linux are not affected. ([#83](https://github.com/ACTom/TyControls/issues/83))
- The Online Package Manager no longer lists GTK3 as a supported widgetset: LCL-GTK3 still has problems the library cannot work around. Building for GTK3 from source still works; see the [known issues](docs/known-issues.en.md). ([#95](https://github.com/ACTom/TyControls/issues/95))

### Fixed

- Text and graphics were blurry on macOS Retina screens. ([#83](https://github.com/ACTom/TyControls/issues/83), [#93](https://github.com/ACTom/TyControls/issues/93))
- Dark text came out too heavy on macOS. ([#91](https://github.com/ACTom/TyControls/issues/91))
- On Windows, control text was greyer and softer than the system's own. ([#90](https://github.com/ACTom/TyControls/issues/90))
- A control's `Font` name, bold, italic, underline, strikeout and colour had no effect (with `ParentFont` False). They are now laid over the theme's style; `StyleOverride` still wins. ([#92](https://github.com/ACTom/TyControls/issues/92))
- A `TMainMenu` in a `TTyForm`'s `Menu` put a native menu bar on the window on Windows and made it taller. `TTyForm` no longer uses the inherited `Menu`: the Object Inspector does not show it, the designer does not set it when a `TMainMenu` is dropped, and one already set is taken out of it with its shortcuts still working. Use a `TTyMenuBar` and the form's `MenuBar` for the window's menu. ([#78](https://github.com/ACTom/TyControls/issues/78))
- The slider of `TTyTrackEdit` and the buttons of `TTyComboEdit`, `TTyURLEdit`, `TTyCalcEdit` and the like showed the text I-beam. ([#84](https://github.com/ACTom/TyControls/issues/84))
- Scrolling a grid left a gap in its left border. ([#86](https://github.com/ACTom/TyControls/issues/86))
- With `WordWrap` off, `TTyMemo` could fall short of the end of a line with Arabic, Devanagari, combining marks or other text shaped as a run when scrolled sideways. ([#77](https://github.com/ACTom/TyControls/issues/77))
- Building the macOS version with Lazarus 3.x failed, also for projects that compile the library from source. ([#81](https://github.com/ACTom/TyControls/issues/81), [#88](https://github.com/ACTom/TyControls/issues/88))
- Some examples failed to build on macOS with an FPC internal error (DWARF3). ([#87](https://github.com/ACTom/TyControls/issues/87))
- Building the GTK3 version with a released Lazarus (before 4.99) failed. ([#82](https://github.com/ACTom/TyControls/issues/82))

## [3.0.2] — 2026-10-13

A bug-fix release for 3.0.

### Changed

- A standalone `TTyScrollBar` no longer takes the keyboard focus by default: `TabStop` now defaults to False, so the bar is not in the Tab order and a click does not focus it; set `TabStop := True` for the previous behaviour (Tab stop, click to focus, arrow and page keys). ([#56](https://github.com/ACTom/TyControls/issues/56))

### Fixed

- The built-in skins restyled only a few controls such as buttons and edits; tabs, grids, lists, trees, menus, scroll bars and the rest kept the default theme's rounded shapes. ([#47](https://github.com/ACTom/TyControls/issues/47))
- `TTyPageControl` and `TTyTabSet` tabs at the bottom, left or right kept their rounded corners on top. ([#45](https://github.com/ACTom/TyControls/issues/45))
- A `linear-gradient` with two stops ignored their positions. ([#49](https://github.com/ACTom/TyControls/issues/49))
- A left-aligned title bar caption jumped past the controls after it when the window was widened. ([#50](https://github.com/ACTom/TyControls/issues/50))
- `TTyRibbonQuickAccess.AddButton` showed its buttons in reverse order, the last one added on the left. ([#51](https://github.com/ACTom/TyControls/issues/51))
- Selected `TTyStringGrid` cells kept the normal dark text, hard to read on a dark accent. ([#46](https://github.com/ACTom/TyControls/issues/46))
- The `TTyStringGrid` cell editor stayed where it was when the grid scrolled or a column or row was resized, and a header sort dropped a value that had failed `OnValidateCell`. ([#48](https://github.com/ACTom/TyControls/issues/48))
- Up/Down while editing a `TTyStringGrid` cell or a header filter moved the keyboard focus to the scroll bar. ([#52](https://github.com/ACTom/TyControls/issues/52))
- `TTyStringGrid` PageUp/PageDown always moved 10 rows instead of a page. ([#57](https://github.com/ACTom/TyControls/issues/57))
- Up/Down on a `TTyStringGrid` pick-list cell sent the focus out of the grid and changed the cell to the next item. ([#59](https://github.com/ACTom/TyControls/issues/59))
- With row selection, or a range selected, `TTyStringGrid` did not show which cell the cursor was on. ([#60](https://github.com/ACTom/TyControls/issues/60))
- `OnMouseWheel`, `OnMouseWheelUp` and `OnMouseWheelDown` never fired on `TTyStringGrid` and `TTyDrawGrid`, nor on `TTyImageView` with a picture loaded. ([#62](https://github.com/ACTom/TyControls/issues/62))
- Typing on a `TTyStringGrid` cell lost the first key in every editor but the text editor: spin, memo, calculator, mask, date and pick-list cells. ([#64](https://github.com/ACTom/TyControls/issues/64))
- A number typed into a `TTyStringGrid` spin cell was lost when the edit ended. ([#66](https://github.com/ACTom/TyControls/issues/66))
- Ending an edit in a `TTyStringGrid` mask cell raised an error, and a value that did not fill the mask, an untouched one included, was written anyway; it is now refused with a message and only Esc leaves the cell. ([#67](https://github.com/ACTom/TyControls/issues/67), [#69](https://github.com/ACTom/TyControls/issues/69))
- Grid columns moved through `Index` (Move Up / Move Down in the collection editor) left their cells behind and went back to the old order on the next load. ([#70](https://github.com/ACTom/TyControls/issues/70))
- Without `toFullRowSelect`, a selected `TTyTreeView` node highlighted the whole row over the expand button and tree lines; only the caption is highlighted now. ([#71](https://github.com/ACTom/TyControls/issues/71))
- In a multi-select `TTyTreeView`, PgUp/PgDn, Left/Right, type-to-find, a click in the indent and a right click moved the focus without updating the selection, and `SelectedCount` drifted; Shift extended the range with Up/Down only. ([#72](https://github.com/ACTom/TyControls/issues/72))
- `toAutoTristateTracking` in `TTyTreeView` missed children made later and ignored `CheckState` and `Checked` set from code. ([#73](https://github.com/ACTom/TyControls/issues/73))
- `SelectAll` on a single-select `TTyTreeView` selected every node. ([#74](https://github.com/ACTom/TyControls/issues/74))
- Existing `TTyTreeView` rows kept their height when `DefaultNodeHeight`, the density or `toVariableNodeHeight` changed. ([#75](https://github.com/ACTom/TyControls/issues/75))
- With rows of different heights, `TTyTreeView` PgUp/PgDn skipped several pages at once. ([#76](https://github.com/ACTom/TyControls/issues/76))
- The `TTyListView` rename box closed the moment it opened. ([#54](https://github.com/ACTom/TyControls/issues/54))
- The scroll bars that grids, list boxes, list views, trees, `TTyMemo` and scroll boxes create for themselves could take the keyboard focus, so one click took it from the control. ([#55](https://github.com/ACTom/TyControls/issues/55))
- `TTyMemo.Text` came back with an extra trailing line break, and `Lines.LoadFromFile` followed by `SaveToFile` changed the file's final line break and line-break style. ([#58](https://github.com/ACTom/TyControls/issues/58))
- The `TTyImageView` wheel zoom did not keep the pointer's spot in place, and the wheel did nothing in the `TTyCascader` drop-down. ([#63](https://github.com/ACTom/TyControls/issues/63))
- The "more…" row and colour dialog title of the `TTyValueListEditor` colour drop-down, and the `TTyRibbon` overflow button hint, showed Chinese in any language. ([#68](https://github.com/ACTom/TyControls/issues/68))

### Performance

- `TTyMemo` with `WordWrap` off loads large texts much faster: 57 000 lines in under half a second instead of about 50 seconds. ([#77](https://github.com/ACTom/TyControls/issues/77))

## [3.0.1] — 2026-10-07

A bug-fix release for 3.0.

### Added

- `TTySpinEdit` / `TTyFloatSpinEdit` up/down buttons: the pointer turns into an arrow over them, they light up on hover and press, and holding one keeps stepping. ([#12](https://github.com/ACTom/TyControls/issues/12))
- `OnHelpClicked` on `TTyFindDialog` / `TTyReplaceDialog`: with `frShowHelp` in `Options` the dialog shows a Help button that fires it. ([#30](https://github.com/ACTom/TyControls/issues/30))

### Changed

- `TTyColorButton.DialogCaption` and `TTyColorComboBox.MoreCaption` default to empty, meaning the library's own text, translated with the application; the new `DialogTitle` and `MoreText` return the text actually shown. ([#41](https://github.com/ACTom/TyControls/issues/41))
- `TTyColorBox` / `TTyColorListBox` no longer write `Items` to the form file and rebuild them from `Style` on load; for a palette of your own, use `cbCustomColors` with `OnGetColors`, or `AddColor` at run time. ([#20](https://github.com/ACTom/TyControls/issues/20))
- `TTyFontComboBox` / `TTyFontListBox` no longer write `Items` to the form file and refill them from this machine's fonts on load. ([#26](https://github.com/ACTom/TyControls/issues/26))
- `TyEdit.embedded` has no padding in the built-in themes; a custom theme that defines it should add `padding: 0` too. ([#39](https://github.com/ACTom/TyControls/issues/39))

### Fixed

- The packages failed to build on Lazarus 3.x. ([#3](https://github.com/ACTom/TyControls/issues/3))
- A project made from the "TyControls Application" template did not show at run time the built-in theme picked in the designer; a project made with 3.0.0 needs the two lines described in the issue. ([#10](https://github.com/ACTom/TyControls/issues/10))
- With `AutoSize` on, `TTyCheckBox`, `TTyRadioButton`, `TTyTag`, `TTyLabel` and `TTyColorButton` came out too narrow and cut off or ellipsised the end of their caption. ([#11](https://github.com/ACTom/TyControls/issues/11))
- `TTyFloatSpinEdit`'s up/down buttons were smaller than `TTySpinEdit`'s. ([#17](https://github.com/ACTom/TyControls/issues/17))
- An editable `TTyComboBox` at its default height cut off the descenders of g, y, p and the like, and set its text further right than a non-editable one. ([#39](https://github.com/ACTom/TyControls/issues/39))
- An editable `TTyComboBox` whose `ItemIndex` was set in code showed an empty field, and picking that row from the list did not fill it either. ([#43](https://github.com/ACTom/TyControls/issues/43))
- A read-only `TTyDateTimePicker` could still change its value through the dropdown calendar. ([#35](https://github.com/ACTom/TyControls/issues/35))
- `TTyCurrencyEdit` lost or corrupted its value when the currency symbol contained a dot or a digit (`Fr.`, `kr.`, `US$1`). ([#38](https://github.com/ACTom/TyControls/issues/38))
- After scrolling, `TTyTreeView` painted rows over its header, and the last rows could not be scrolled into view. ([#19](https://github.com/ACTom/TyControls/issues/19))
- Ellipsising a very long text (hundreds of lines) nearly froze; a multi-line text in a single-line place now shows its first line. ([#18](https://github.com/ACTom/TyControls/issues/18))
- Every `TTyStringGrid` leaked two string lists when freed. ([#16](https://github.com/ACTom/TyControls/issues/16))
- Freeing a `TTyCoolBar` while its form was open raised an access violation. ([#15](https://github.com/ACTom/TyControls/issues/15))
- A `TTyColorBox` / `TTyColorListBox` read back from a form showed black swatches and lost its selected colour. ([#20](https://github.com/ACTom/TyControls/issues/20))
- `TTyFontComboBox` / `TTyFontListBox` wrote the machine's whole font list into the form file, so another machine listed the first machine's fonts. ([#26](https://github.com/ACTom/TyControls/issues/26))
- On Windows the font combo box, font list box and font dialog listed every CJK font twice, once as a vertical '@' alias that draws its glyphs on their side. ([#31](https://github.com/ACTom/TyControls/issues/31))
- `TTyRibbon` / `TTyPageControl`: a page moved away, or freed by a different owner, stayed in the page list. ([#21](https://github.com/ACTom/TyControls/issues/21))
- A `TTyRibbon` saved minimised expanded to just its tab strip after being read back. ([#23](https://github.com/ACTom/TyControls/issues/23))
- A `TTyForm` lost its content surface after being read if the surface had been renamed. ([#22](https://github.com/ACTom/TyControls/issues/22))
- Changing an icon font after a `TTyCharImage` / `TTyRibbonGallery` that used it was freed raised an access violation. ([#24](https://github.com/ACTom/TyControls/issues/24))
- Hints, balloon hints, popup menus, grids and the native styler kept pointing at a referenced component after it was freed on another form. ([#25](https://github.com/ACTom/TyControls/issues/25))
- File dialogs ignored `fdoPathMustExist`, and checked `fdoFileMustExist` only for one name in an open dialog. ([#29](https://github.com/ACTom/TyControls/issues/29))
- File dialogs asked `OnCanClose` before checking the name, so the dialog could stay open after `OnCanClose` said yes. ([#32](https://github.com/ACTom/TyControls/issues/32))
- The `frHide*`, `frDisable*` and `frShowHelp` options of `TTyFindDialog` / `TTyReplaceDialog` had no effect. ([#30](https://github.com/ACTom/TyControls/issues/30))
- `Description`, `Prompt`, `EmptyText` and other text properties were never translated in a translated application. ([#33](https://github.com/ACTom/TyControls/issues/33))
- `TTyColorButton`'s dialog title and `TTyColorComboBox`'s "More…" row stayed in English in a translated application. ([#41](https://github.com/ACTom/TyControls/issues/41))
- In a Chinese UI, the messages for a broken theme were in English, and the font dialog's preview showed no Chinese characters. ([#44](https://github.com/ACTom/TyControls/issues/44))
- Gradient and nine-slice backgrounds left some fields uninitialised: the same rule could resolve differently twice, and glass with `glass-blur` but no `glass-tint` took a random tint. ([#40](https://github.com/ACTom/TyControls/issues/40))
- Glass lost its tint when a `.tycss` rule wrote `glass-tint` before `background`, or when a later rule or a `StyleOverride` changed only the background. ([#42](https://github.com/ACTom/TyControls/issues/42))
- The tycss reference described `padding`, `alpha()` and gradient stops wrongly. ([#13](https://github.com/ACTom/TyControls/issues/13))

## [3.0.0] — 2026-09-30

TyControls 3.0, the first stable release. Only the changes below since RC3; everything that changed from 2.2 to 3.0 is in the 3.0.0-Beta through 3.0.0-RC3 sections.

### Added

- A gallery ([docs/gallery.en.md](docs/gallery.en.md)): every example and every tab page in light and dark, and all built-in themes side by side.

### Fixed

- On Windows with a non-default ClearType contrast, light text on dark themes came out lighter than the text Windows draws.
- The grid example's tab captions lost their `&`.

### Performance

- Text draws faster on Windows: text-heavy controls such as the grid and the memo take about a third less time for their first paint.

## [3.0.0-RC3] — 2026-09-28

Fixes a batch of layout errors under high-DPI scaling (150%, 175%; [#2](https://github.com/ACTom/TyControls/issues/2)) and blurry text on Windows. Still a release candidate: if nothing new comes in, this content becomes 3.0.0 final.

### Changed

- Text on Windows advances by whole pixels: in a Chinese font with no bold face of its own, bold text is 1 px wider per character, so a button with a hardcoded width may need widening or `AutoSize`.

### Fixed

- Text in every control on Windows looked softer and lighter than the text Windows draws; it is now as crisp and as heavy as the system's ClearType, without the colour fringes.
- At 150% and 175% scaling, text was measured at twice the DPI: labels spread their lines too far apart and wrapped early, and buttons and other controls came out taller and wider than designed, so rows of them overlapped. Controls created in code were affected too.
- At high DPI, a control with `AutoSize` on scaled in one direction only: a button's height and a wrapping label's width stayed at 100%, and the label wrapped into twice as many lines.
- A tool bar's `Indent` / `ButtonSpacing` / `ButtonHeight` / `ButtonWidth`, `TTyToolBarEx`'s overflow button and flyout, the `Spacing` of tool group, grid and relative panels, a status panel's `Width` and a splitter's `MinSize` did not scale at high DPI, so children crowded together or ran into each other.
- `TTyCoolBar`: at high DPI a band snapped back to its 100% width as soon as its gripper was touched, the seam lagged behind the pointer while dragging, and `AutoMaxWidth` stopped a band at just over half its content.
- The built-in dialogs kept 100% margins, columns and gaps at high DPI: the file dialog's navigation buttons lay over its file list, the font dialog's check boxes over its colour button, the editors' buttons ran out of the window, and messages wrapped at half their width.
- `TTyStringGrid`: the column filter drop-down did not scale at high DPI, and under modern density the filter row's editor opened over the column captions.
- `TTyShellListView` gave most of its width to the first column at high DPI and pushed the last two out of view.
- At high DPI, the figure in a gauge or circular progress was too big and stood out of the ring, and the calendar's today ring, the colour grid's selection ring, the list view's sort arrow, the ribbon's key tips, the status bar's grip and the tree's radio mark were drawn too thick or too large.
- The window's resize border, the smallest size a manual resize leaves, the drag threshold on a title bar, and the tolerance of a triple click and of the date picker's check box were only a little over half as forgiving at 175% as at 100%.

## [3.0.0-RC2] — 2026-09-27

Every issue reported against the RC has been addressed. Still a release candidate: if nothing new comes in, this content becomes 3.0.0 final.

### Added

- `TTyStringGrid` input validation: when `OnValidateCell` refuses a value the editor stays on its cell until the value is fixed or abandoned with `Esc`; when focus leaves the grid altogether, `OnInvalidEditExit` decides whether to abandon or keep the edit (abandon by default). Demonstrated on the grid example's Events page.
- The `system` theme follows the desktop's light/dark scheme and accent on Qt5 / Qt6 builds; GTK builds do not probe and keep the default look.

### Changed

- `TTyTransfer`'s middle buttons now draw chevrons (`>` / `>>` / `<` / `<<`), the doubled mark reading as one glyph.

### Fixed

- Switching to the `system` theme on Linux raised `List index out of bounds`.
- Following the system appearance on macOS no longer spawns a subprocess every 750 ms.
- Under modern density and skins with taller buttons (aero, for one), a message dialog's buttons hung out of the bottom strip; the file dialog's navigation buttons overlapped; rows laid out at a fixed stride in the find, font, colour, path, image-collection and structure editors clipped or overlapped.
- `TTyDateTimePicker`'s dropdown calendar was hardcoded to the classic 240×220, cramped under modern density and at high DPI; it now follows the theme's row height.
- `TTySteps` centres a horizontal step's title under its own marker, and the connector runs marker to marker.
- `TTyRibbon`'s large tiles were only an edit box tall under modern density; they now have their own theme size, `--ribbon-tile-height`.
- Windows XP: the system's blue frame on the left, right and bottom edges is gone, and opening a menu or dropdown no longer flashes the system caption over the window.
- `TTyStringGrid`'s spin, slider, memo, calculator, pick-list and date editors can now be abandoned with `Esc` (only the text and mask editors could).
- On a controller with a `ThemeName`, clearing or replacing `StyleOverride` had no effect, and the modern density pack stayed after switching back to classic.
- `TTySparkline`'s baseline floated up when the minimum was a large positive value.
- `TTyStringGrid`: dragging a column divider through the body selected a block of cells; pressing on a divider, or double-clicking it, sorted as well. Sorting now fires on release, and a press on a divider, a release elsewhere, or a column drag does not count as a click.
- `TTyTreeView`: double-clicking a column header expanded, collapsed or edited the last node clicked; a header click now sorts only when pressed and released on the same section.
- `WindowState = wsMaximized` set in the designer had no effect at run time (on Windows it could fill the whole monitor over the taskbar; on Linux nothing happened); the first show now maximizes to the work area, exactly as the caption button does.
- A title bar's `ShowMinimize` / `ShowMaximize` / `ShowClose` set to False in the designer still showed the buttons at start-up; they are now a second gate beside the form's `BorderIcons`, either one hides the button, and the form's sync no longer overwrites the bar's setting.
- With the maximize button hidden, a title-bar double-click, Aero Snap to the top edge and Win+Up still maximized; if any of `Resizable`, `biMaximize` in `BorderIcons` or the bar's `ShowMaximize` is off, all of them are now off too, while a maximized window can still restore.

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
