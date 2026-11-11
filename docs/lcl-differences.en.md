# Deliberate differences from LCL

> 中文:[lcl-differences.md](lcl-differences.md)

TyControls keeps LCL's property names and meanings wherever it can, so most code ported from Lazarus works unchanged. The points below differ **on purpose**; watch for them when porting.

## Defaults

| Property | TyControls | LCL | Notes |
|----------|-----------|-----|-------|
| `AutoSize` (label, edit, combo box, check box, radio button) | `False` | `True` | The height follows the theme; turn it on when you want the content to decide |
| `TTyMemo.WordWrap` | `False` | `True` | Long lines scroll sideways |
| `TTyMemo.ScrollBars` | `ssAutoVertical` | `ssNone` | The vertical bar appears once the text overflows |
| `TTyNumericEdit.Alignment` (and descendants) | `taRightJustify` | `taLeftJustify` | Numbers align right |
| `TTyRadioButton.TabStop` | `True` | `False` | Every radio button is reachable with Tab |
| `TTySpeedButton.Spacing` | `-1` | `4` | `-1` lets the theme's `--glyph-button-gap` set the gap between icon and text |
| `TTyCoolBar.ShowText`, `TTyCoolBand.Break` | `False` | `True` | |
| `TTyStatusBar.SimplePanel` | `False` | `True` | A bar with no panels still shows `SimpleText` |
| `TTyTreeView.RightClickSelect` | `True` | `False` | A right click selects the node before the menu opens |
| `TTyListView.ReadOnly` | `True` | `False` | Set it to `False` for in-place renaming |
| `TTyScrollBar.Kind` | `sbVertical` | `sbHorizontal` | See [TTyScrollBar](controls/scrollbar.md) |
| `TTyScrollBar.LargeChange` | `0` | `1` | `0` pages by `PageSize`; see [TTyScrollBar](controls/scrollbar.md) |

## Behaviour

- **Pixel properties are logical pixels** (pixels at 96 PPI). Widths, heights, paddings, `BorderWidth` and the like are scaled by the control to its own PPI; there is nothing to convert by hand on high-DPI screens.
- **`TTyScrollBar.Position` can reach `Max`.** LCL's scroll bar stops at `Max - PageSize + 1`.
- **A control with `TabStop = False` does not take focus when clicked**; the keyboard focus stays where it was. Text boxes, memos and the other typed fields (numbers, dates and times) are the exception: you click into one to type in it.
- **`TTyTrackBar` raises `Position` on PageUp**, as Qt does; Win32 does the opposite. On a `Reversed` bar the keys and the wheel follow the screen: each moves the thumb the way it does on an unreversed bar, so PageUp lowers `Position` there.
- **`TTyTreeView.AutoExpand` follows Delphi**: the node that gets the focus expands, and the one it left collapses. In LCL it means "expand a node when a child is added to it".
- **`TTyTitleBar` looks the same when disabled.** It stands for the window itself, and a window does not grey out; to show that a window cannot be used, disable what is in it.
- **A form's own `Font` does not override the theme.** The whole window takes its font from the theme; change the theme or use `StyleOverride`. A font set on a control itself still applies.
- **`TTyScrollPanel.AutoPan` is driven by the host.** Call `AutoPanTo` from `OnDragOver` while dragging and `StopAutoPan` when the drag ends.
- **`TTyColorDialog.Color` is a `TTyColor` (`$AARRGGBB`, with alpha), not a `TColor`.** `clRed` assigned to it is a transparent blue; use `LCLColor` to read and write a `TColor`.
- **`Delete` in a `TTyDateTimePicker` clears the whole date to NULL**, as `N` does (LCL knows only `N`). Set `NullInputAllowed := False` to keep the user from clearing it.

## Mixing in plain LCL controls

Plain LCL controls (`TPanel`, `TFrame`, `TScrollBox`, ...) can sit directly on a themed container. At run time a TyControls container that takes child controls (a panel, a group box, a card, a tool window, a page, ...) keeps its LCL `Color` equal to **the colour behind its children**:

| The container's themed background | Its `Color` |
|------|------|
| Solid | That colour |
| Translucent | That colour composited over what is behind the container |
| None (a group box, say) | What is behind the container |
| Gradient | The colour at the middle of the gradient |

A plain control with `ParentColor = True` therefore paints that colour itself, and a TyControls control placed on it takes the same colour outside its rounded corners, where it used to get `clBtnFace`. The colour follows a theme switch, another `Controller`, a change of `StyleClass` / `StyleOverride`, and a move to another parent.

- **At run time only.** In the designer the container's `Color` is left alone, and the colour is never written to an `.lfm`.
- **Read from the style at rest.** Hovering or focusing the container does not move it.
- **A `Color` you set is yours.** Once you assign the container's `Color` the library leaves it alone; assign `clDefault` (on a `TTyFrame`, `ParentColor := True` works too) and it follows the theme again.
- **A gradient becomes one flat colour.** A plain LCL control paints a single colour. For a view that is seamless on a gradient host, make it a [TTyFrame](controls/frame.md): it paints the slice of the host's background it covers.
- A container of your own that does not want this overrides `ThemesChildBackdrop` to return `False`.

The form (`TTyForm`) has always done this: `ApplyChromeTheme` writes a solid form background into the form's `Color`.

## Controls `AutoSize` does not apply to

These controls have no natural size to fit their content to, so `AutoSize` leaves their size alone: `TTyMemo`, `TTyListView`, `TTyTreeView`, `TTyDrawGrid`, `TTyStringGrid`, `TTyValueListEditor`, the gauges, `TTyChart`, `TTySparkline`, `TTyProgressBar`, `TTyShape`, `TTyStarShape`, `TTyArrow`, `TTyBevel`, `TTySplitter`, the colour pickers, `TTyPreviewBox`, `TTyImageView`, `TTyTransfer`, `TTyRibbonBackstage`, `TTyRibbonGallery`, `TTyTitleBar`, `TTyTerminalView` (use `SizeForGrid` for a fixed grid).

## Properties no longer published

These properties can never act on the control that publishes them, and from 4.0 on they are not published (3.0 only hid them in the Object Inspector). A 3.x form that sets one of them still loads in 4.0: the value is dropped, and the line is gone from the `.lfm` the next time the form is saved.

| Control | Properties | Why |
|---------|-----------|-----|
| The numeric edits: `TTyNumericEdit`, `TTyCurrencyEdit`, `TTyCalcEdit`, `TTyCalcCurrencyEdit`, `TTyFloatSpinEdit`, `TTyTrackEdit` and their DB versions | `CharCase` | Only digits, a sign and a decimal separator can be entered |
| `TTyAdvancedComboBox`, `TTyCheckComboBox`, `TTyColorBox`, `TTyColorComboBox`, `TTyFilterComboBox`, `TTyOfficeComboBox`, `TTyShellComboBox` | `MaxLength`, `CharCase`, `ReadOnly` | Pick-only: there is no text to edit |
| `TTyDrawGrid` | `HideSelectionWhenInactive`, `FadeUnfocusedSelection`, `MinEditorWidth` | No selection and no built-in cell editor; still published on `TTyStringGrid` |
| A grid's `Header` | `MainColumn` | A grid has no main column; still published on the headers of `TTyListView` and `TTyTreeView` |
| `TTyShellListView` | `OwnerData`, `ItemCount`, `Items`, `OnGetItemText`, `OnGetItemImage`, `OnGetItemGroup` | It lists the folder itself; still published on `TTyListView` |
| `TTyShellTreeView` | `NodeDataSize`, `RootNodeCount`, `Items`, `OnInitChildren` | It builds its nodes from the file system; still published on `TTyTreeView` |
| `TTyDBLookupListBox` | `MultiSelect`, `ExtendedSelect` | A lookup list holds one key (LCL does not publish them either); still published on `TTyDBListBox` |
| The text inputs: `TTyEdit`, `TTyMaskEdit`, `TTyComboEdit`, `TTyURLEdit`, the numeric edits, `TTyMemo`, `TTySpinEdit`, `TTyDateTimePicker` and their DB versions | `ChildSizing` | No children to size |
| `TTyRangeTrackBar`, `TTyMultiTrackBar`, `TTyGradientTrackBar` | `ChildSizing` | No children to size |
| `TTyTerminalView` | `ChildSizing` | The terminal places its scroll bar itself; with it set, the bar covered the last columns |
| `TTyToolWindowActions` | `AutoSize`, `ChildSizing`, `BorderSpacing` | Its tool window places and sizes it, and it lays its children out in a row itself |

The `Style` of these pick-only combo boxes (except `TTyColorBox` and `TTyColorComboBox`) is still published, but the Object Inspector lists only the pick-only styles; an editable style is replaced by its pick-only counterpart anyway.
