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
- **A control with `TabStop = False` does not take focus when clicked**; the keyboard focus stays where it was.
- **`TTyTrackBar` raises `Position` on PageUp**, as Qt does; Win32 does the opposite.
- **`TTyTreeView.AutoExpand` follows Delphi**: the node that gets the focus expands, and the one it left collapses. In LCL it means "expand a node when a child is added to it".
- **`TTyTitleBar` looks the same when disabled.** It stands for the window itself, and a window does not grey out; to show that a window cannot be used, disable what is in it.
- **A form's own `Font` does not override the theme.** The whole window takes its font from the theme; change the theme or use `StyleOverride`. A font set on a control itself still applies.
- **`TTyScrollPanel.AutoPan` is driven by the host.** Call `AutoPanTo` from `OnDragOver` while dragging and `StopAutoPan` when the drag ends.

## Controls `AutoSize` does not apply to

These controls have no natural size to fit their content to, so `AutoSize` leaves their size alone: `TTyMemo`, `TTyListView`, `TTyTreeView`, `TTyDrawGrid`, `TTyStringGrid`, `TTyValueListEditor`, the gauges, `TTyChart`, `TTySparkline`, `TTyProgressBar`, `TTyShape`, `TTyStarShape`, `TTyArrow`, `TTyBevel`, `TTySplitter`, the colour pickers, `TTyPreviewBox`, `TTyImageView`, `TTyTransfer`, `TTyRibbonBackstage`, `TTyRibbonGallery`, `TTyTitleBar`.

## Properties hidden in the designer

These properties can never act on the control that publishes them. They are kept so that saved forms still load, but the Object Inspector no longer shows them. From 4.0 on they are not published.

| Control | Properties | Why |
|---------|-----------|-----|
| `TTyNumericEdit` and descendants | `CharCase` | Only digits, a sign and a decimal separator can be entered |
| `TTyAdvancedComboBox`, `TTyCheckComboBox`, `TTyColorBox` (and `TTyColorComboBox`), `TTyFilterComboBox`, `TTyOfficeComboBox`, `TTyShellComboBox` | `MaxLength`, `CharCase`, `ReadOnly` | Pick-only: there is no text to edit |
| The same, except `TTyColorBox` | `Style` | The list offers only the pick-only styles; an editable style is replaced by its pick-only counterpart anyway |
| `TTyDrawGrid` | `HideSelectionWhenInactive`, `FadeUnfocusedSelection`, `MinEditorWidth` | No selection and no built-in cell editor; still shown on `TTyStringGrid` |
| A grid's `Header` | `MainColumn` | A grid has no main column |
