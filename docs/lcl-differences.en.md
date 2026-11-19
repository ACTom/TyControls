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

## `TTyRichEdit` and code from Delphi's `TRichEdit` or RichMemo

`TTyRichEdit` is drawn by the package; it is not Windows' rich edit control. Most of Delphi's `TRichEdit` members and RichMemo's methods are there under their own names, but a few compile and do something else. The lists below say which.

### What to put in `uses`

Delphi's `uses ComCtrls` (or RichMemo's `RichMemo`) becomes `tyControls.RichEdit` plus the units that declare the types and values its members take. `tyControls.RichEdit` does not pass them on, as `tyControls.Memo` does not pass on `tyControls.ScrollBar`: until they are listed, the first compile of ported code stops at `TTyRichPos`, `nsBullet` or `stMatchCase`. Event handlers the IDE makes are not affected: it adds the units their parameters need.

```pascal
uses
  tyControls.RichEdit, tyControls.RichEdit.Text, tyControls.RichEdit.Attrs,
  tyControls.RichEdit.Model, tyControls.RichEdit.Layout, tyControls.RichEdit.Find,
  tyControls.ScrollBar;  // and tyControls.RichEdit.Commands for Document.Execute
```

| Unit | What it gives |
|------|---------------|
| `tyControls.RichEdit` | `TTyRichEdit`, `ETyRichEdit`, `TTyRichFormat` (`rfAuto`, `rfRtf`, `rfText`), the event types (`OnFallbackFont`'s `TTyRichFallbackEvent` is in `tyControls.RichEdit.Layout`), `TTyRichFindEnd` (`rfeFound` …), `TTyRichReplaceEnd` (`rreDone` …), `TTyRichReplaceResult`, `TTyRichFindTask` (`rftFind`, `rftReplace`) |
| `tyControls.RichEdit.Text` | `TTyRichPos` |
| `tyControls.RichEdit.Attrs` | `TTyRichTextAttributes`, `TTyRichParaAttributes`, `TNumberingStyle` with `nsNone` and `nsBullet`, `TTySearchTypes` (`stWholeWord`, `stMatchCase`), `TTySearchOptions` (`soMatchCase`, `soWholeWord`, `soBackward`), `TTyRichConsistentAttributes` (`caBold` …), `TTyRichConsistentParaAttributes` (`cpaAlignment` …), `TTySubscriptType` (`sstNone` …); RichMemo's records, sets and helpers: `TTyFontParams`, `InitFontParams`, `TTyParaMetric`, `TTyParaNumbering` (`pnBullet` …), `TTyParaAlignment` (`paLeft` …), `TTyTabStopList`, `TTyTextModifyMask` (`tmm_Styles` …), `TTyParaModifyMask`, `TTyParaRange` |
| `tyControls.RichEdit.Model` | the numbered list kinds (`lkDecimal` … `lkUpperRoman`), `TTyParaAlign` for `ParaAlign` (`paraLeft`, `paraCenter`, `paraRight`, `paraJustify`), `TTyLineSpacing` for `LineSpacingRule` (`lsSingle` …), `TTyTextEncoding` (`teAuto`, `teUtf8` …), `TTyRichDocument` |
| `tyControls.RichEdit.Layout` | `TTyRichWrapMode` (`rwmWindow`, `rwmPage`, `rwmNone`) |
| `tyControls.RichEdit.Find` | `TTyRichFindOptions` (`rfoMatchCase`, `rfoWholeWord`, `rfoBackward`, `rfoWrap`) |
| `tyControls.RichEdit.Commands` | the commands for `Document.Execute` (`TTyRichInsertText` …) |
| `tyControls.ScrollBar` | `TTyScrollBarAutoHide` (`sbahDefault`, `sbahNever`, `sbahAuto`) |

### Positions, lines and text

- **A position counts characters (code points), not UTF-16 units.** A character outside the BMP (an emoji, a rare ideograph) is one position here and two in Delphi or in RichMemo on Windows; a paragraph end is one position.
- **Positions and lengths are `TTyRichPos` (`Int64`).** `SelStart`, `SelLength`, `FindText`'s result and the RichMemo methods take and return it. An `Integer` assigned from them compiles without a warning, and a position past `High(Integer)` is cut; documents that large are why the type is 64-bit, so declare `TTyRichPos`.
- **A line of `Lines` is a paragraph**, not a line as wrapped on screen as in Delphi: `Lines.Count` is the paragraph count and `Lines[i]` a paragraph's text. A large document is never laid out whole, so `Lines` has to answer without a layout.
- **`CaretPos` is Delphi's `TPoint` of the selection's end**: `Y` the paragraph, `X` the character in it. RichMemo's `CaretPos` (LCL's memo) reads the selection's start.
- **Writing `CaretPos` clamps `X` to the paragraph.** Delphi's adds `X` to the line's start unchecked, so a column past the end lands in a later line there.
- **`SelText` reads the selection as a copy puts it on the clipboard as text**: a paragraph end is the platform's line break (Delphi: CR) and a picture gives nothing (Delphi: U+FFFC). So `Length(SelText)` does not equal `SelLength` as it does in Delphi.
- **`Text` keeps a picture as U+FFFC** and joins paragraphs with the platform's line break; reading it in a large document builds a copy of all of it.
- **`Text :=` and `Clear` replace the content**: the undo history goes, `Modified` is `False` afterwards and a `Clear` cannot be undone, as Delphi's `WM_SETTEXT` behaves. Inside `BeginEdit … EndEdit` both raise `ETyRichEdit`.

### Compiles, means something else

- **`PlainText` is set by every load through the control**: a text file makes it `True`, an RTF file `False`. Delphi's never changes by itself.
- **`PlainText := True` set by code or in the Object Inspector stays in charge**: every load without a format then reads text and every file save without a format writes text, as in Delphi. A load with `rfText` keeps it; `PlainText := False`, `LoadRichText`, `LoadFromStream(S, rfRtf)` or a load that went by its file ends it.
- **A load without a format goes by the file's signature** (`{\rtf` after an optional BOM and white space: RTF, else text). Delphi tries RTF and falls back to text, leaving `PlainText` alone.
- **`Lines.LoadFromFile`, `LoadFromStream`, `SaveToFile` and `SaveToStream` with one parameter are the control's own load and save**, so an RTF file is read as RTF. The overloads with a `TEncoding` are TStrings' and treat the file as plain text; set `TextEncoding` and use the one-parameter forms instead.
- **`Lines.SaveToFile` clears `Modified`**; Delphi's leaves it as it was. A "save changes?" prompt on close would otherwise ask again after a save.
- **`Modified` turns `False` again** when undo or redo returns to the content last loaded or saved; Delphi's stays `True`.
- **Undo puts back the selection there was before the step; redo leaves a plain caret where the step left it**, as Windows' rich edit does. Typing merges into one step; a format write and each edit from code are one step each.
- **A write of the value the text already has is no undo step**: no `OnChange`, `Modified` untouched.
- **`CanUndo` and `CanRedo` answer for the user**: `False` when `ReadOnly` or disabled. `Document.CanUndo` answers for code.
- **`ReadOnly` stops the user only.** Code still edits through `SelText`, `Lines`, `Text`, the format API and the replace methods, as Delphi's `SelAttributes` does; Cut, Paste, `ClearSelection`, `Undo` and `Redo` do nothing on a read-only control, as in Delphi.
- **`ClearSelection` deletes the selection**, as Delphi's does; `CollapseSelection` only collapses it.
- **A format chosen with nothing selected (bold, then typing) is dropped by any setting of the selection**, even `SelStart := SelStart`, as on Windows.
- **Inside `Lines.BeginUpdate … EndUpdate`, `Document.BeginUpdate … EndUpdate` and `BeginEdit … EndEdit` each write does what it does outside**: the caret and the selection follow `SelText`, `Lines` and `InDelText`. `BeginEdit … EndEdit` holds back the repaint and both reports: one `OnChange` and one `OnSelectionChange` at its end. `Lines.BeginUpdate` and `Document.BeginUpdate` hold back `OnChange` and the repaint; a selection set inside them (`SelStart`, `SelLength`, `CaretPos`, `CaretIndex`) is reported at once, as in Delphi.
- **Inside those brackets the user's actions do nothing**: Cut, Paste, `ClearSelection`, `Undo`, `Redo` and keys are ignored without an error or an `OnEditRefused`.
- **A change made straight through `Document.Execute` inside a bracket** does not move the selection when the same bracket also sets the selection or writes text through the control. When it does neither, the selection moves only by the bracket's one merged change at its end: a caret between two such changes goes to the first one's start.
- **`BeginEdit … EndEdit` is one undo step**: its undo puts back the selection there was at `BeginEdit`; its redo leaves a plain caret where `EndEdit` left the caret.
- **A format write raises `ETyRichEdit` while a file is loading, after a cancelled load or during a save**, states Delphi's control does not have. It passes over a table row that holds a nested table, which is kept as the file has it.
- **A format write ends an open input-method composition first.**
- **`SendMessage(Handle, EM_…)` and `Perform(EM_…)` compile and do nothing**: there is no system control to receive them. Use `ScrollCaretIntoView` for `EM_SCROLLCARET`, `Document.Text.ParaOfPos` for `EM_LINEFROMCHAR`, `Document.Text.ParaStart` for `EM_LINEINDEX`, `TopParagraph` for `EM_GETFIRSTVISIBLELINE`, `PositionRect` for `EM_POSFROMCHAR`, `PositionAtPoint` for `EM_CHARFROMPOS`, `GetText` for `EM_GETTEXTRANGE`, `Zoom` for `EM_SETZOOM` and `WrapMode` for `EM_SETTARGETDEVICE`. `EM_EXLIMITTEXT` has nothing to set: there is no length limit.

### Character and paragraph formats

- **`TNumberingStyle` has seven members** (`nsNone`, `nsBullet` and the numbered kinds up to `lkUpperRoman`), so `Paragraph.Numbering := TNumberingStyle(Button.Down)` works, but a `for … in TNumberingStyle`, a `case` with an `else` or an array indexed by it sees seven values.
- **`Numbering := nsBullet` (or a numbered kind) gives a paragraph that has no indent WordPad's hanging indent** (first line at 18 pt, the others at 36 pt); `nsNone` takes the indents back to 0. Delphi's `nsBullet` raises `LeftIndent` to at least 10 pt, and its `nsNone` sets `LeftIndent` to 0.
- **A justified paragraph reads `taLeftJustify` in `Paragraph.Alignment`**, because `TAlignment` has no justify; `ParaAlign` reads all four.
- **`Paragraph.Alignment` is not swapped under a right-to-left `BiDiMode`**: the control has no right-to-left layout. An RTF file's right-to-left paragraphs are kept and saved back.
- **Automatic text colour reads `clDefault` (Delphi: `clWindowText`) and no highlight reads `clNone` (Delphi: `clWindow`)**, because the automatic colour follows the theme. Writing `clWindowText`, `clWindow` or `clDefault` means automatic or none, as in Delphi.
- **`Font.Assign(SelAttributes)` gives `clDefault` for automatic text** and sets no pitch.
- **`SelAttributes.Assign(DefAttributes)` takes the text's own font away**, so it follows `DefAttributes` and the theme from then on; Delphi copies the base font's values into the text.
- **`Name` and `Size` of text without a font of its own read the font it is shown in.** Writing back the very value it is shown in leaves such text without one, so a toolbar that writes back what it read freezes nothing into the text. The same holds for `Height`, the RichMemo methods and `Assign(TFont)`.
- **A font name of `'default'` means "no name"** in every write, so no font called `default` goes into a file.
- **`Height` takes a negative value as its absolute value.**
- **`DefAttributes` is the control's `Font` laid over the theme**: a write changes `Font` and is no undo step. Its `BackColor` and `Subscript` cannot be set (a write raises `ETyRichEdit`).
- **`ConsistentAttributes` compares what the text stores, not what it shows**: text without a font name beside text with the base font's name written out reads `caFace` as mixed.
- **`ConsistentAttributes` has a budget**: over a very large selection, or bytes of a large RTF file not parsed yet, it reports what it could not prove the same as mixed, so a toolbar can read it on every selection change.
- **`SelAttributes` over a selection that begins at a paragraph's end answers for the next paragraph's first character**, the one a write would format.
- **`FirstIndent`, `LeftIndent` and `RightIndent` change each paragraph from its own value** over a multi-paragraph selection, as Delphi's do.
- **Indents, spaces and tab stops read rounded to the nearest point**; Delphi's truncate. Writes are exact.
- **`Tab[i] :=` past `TabCount` adds stops up to it**, so the count becomes `i + 1`; Delphi's sets the count to `i`. `TabCount` is at most 32, and an index of 32 or more is ignored.

### Find and replace

- **`FindText` takes `stWholeWord` and `stMatchCase` (type `TTySearchTypes`)**; RichMemo's `Search` takes `soMatchCase`, `soWholeWord` and `soBackward` (type `TTySearchOptions`). FPC's `StrUtils` has a `soMatchCase` and `soWholeWord` of its own: qualify them in a unit that uses both.
- **A negative `Length` (`Len`) searches to the end.** Delphi's searches to the end only when `StartPos + Length` is -1. A range past the end is clamped.
- **RichMemo's backward `Search` looks from `Start` back over `Len` characters** (down to 0 for a negative `Len`) and finds the match nearest `Start`, as RichMemo does on Windows.
- **RichMemo's `Search` with `var` results reports the match's length in this control's characters**; RichMemo reports the needle's length. A CR LF needle matching one paragraph end gives 1 here, 2 in RichMemo. An `Integer` overload is there; a match past `High(Integer)` is reported as none.
- **Whole word follows the caret's word rule**: every Chinese, Japanese or Korean character is a word boundary on both sides. Case folding is per code point (`ß` does not match `ss`, no Turkish rule) and nothing is normalised.
- **CR LF, LF and CR in the needle each match one paragraph end.** Delphi turns CR LF into CR.
- **A picture never matches**, and neither does a link's text or a merged-away table cell.
- **While a file is still loading, `FindText` and `Search` search what is loaded** and return -1 for the rest; `FindNextAsync` searches what is loaded and goes on as the load goes on.
- **A find in a very big RTF file reads the file's paragraphs as it goes**, so `FindNext`, `FindText` and `Search` can take ten seconds or more on a file of a hundred megabytes. Prefer `FindNextAsync` there: it searches in the background and can be cancelled.
- **`ReplaceAll` has three forms**: the plain one returns the number replaced; the one with `out ASkipped` also counts the matches left alone; the one with a range (`AStart`, `ALength`, a negative length to the end, as `FindText` takes it) fills a `TTyRichReplaceResult`. `ReplaceAllAsync` takes the same range (the whole text by default) and hands the same record to `OnReplaceDone`. A match the document would not let a user's edit change (in a table row that holds a nested table, or one whose deletion would join text across a table cell's or row's edge) is left as it is and counted in `Skipped`. So is every match of a document that takes no change at the moment: after a cancelled load, for `ReplaceAll` and `ReplaceAllAsync` alike; while a file is loading or being saved, for `ReplaceAll` (`ReplaceAllAsync` waits for the load to end).
- **A replace is one undo step with a limit** of four times `Document.MaxUndoBytes`. `TTyRichReplaceResult.Ending` says how it ended: `rreDone` (through its range), `rreLimit` (the step was full), `rreCancelled` (`CancelFind`, the progress handler, a new start, an edit or undo it did not make - also one taken back before its next turn -, `ClearUndo` or anything else that makes the history let its step go, a new content or a save stopped it; a background replace only) or `rreFailed` (it could not go on); `Replaced` and `Skipped` count what it did. What was replaced stays, as one undo step. Where the history lets the step go from inside another operation (the document's `ClearUndo`, a key typed that takes the history over its byte limit, a new step that drops the redo side), the replace is over at once (`FindRunning` is False) and `OnReplaceDone` is raised from the application's message loop right after, not inside that operation.
- **To go on after `rreLimit` or `rreCancelled`, call it again from the place it reports**: `ReplaceAll(AFind, AReplace, AOptions, R.ResumeAt, R.ResumeLength, R)`, repeated while `R.Ending` is `rreLimit` (a `rreCancelled` or `rreFailed` call does not go on by itself). `ResumeAt` is right behind the last match it dealt with, in the text as it is when reported (an edit made since a background replace stopped is counted in); nothing is replaced twice, also when the replacement holds the needle. `ResumeAt` is -1 when nothing is left or the content was replaced. A background replace stopped by the undo of its own step reports `Replaced` 0 and the range's start: nothing of it is left (redone again before the replace noticed, it reports what the redo put back and the place behind that). With `rfoWholeWord`, a rerun started exactly at `ResumeAt` with the text unchanged also replaces a match that touches the last one replaced, as one run would; after any edit, or from any other start, such a match is judged by the text as it is. A refused match the stopped run already counted may be counted in `Skipped` again by the rerun.
- **`OnFindDone` gives `AEnd` (`rfeFound`, `rfeNotFound`, `rfeCancelled`) and the match's `APos` and `ALen`** (-1 and 0 when none); `OnReplaceDone` gives the `TTyRichReplaceResult`. Each is raised once for every background find or replace started, unless the control is destroyed. `OnFindProgress` says in `ATask` whether a find (`rftFind`) or a replace (`rftReplace`) runs, and gives characters done of the range it searches; `ACancel` stops it. A handler of these events may free the control: the call that raised it returns as if nothing had been found or replaced (`FindNext` False, `ReplaceAll` 0 and `rreCancelled`), and no exception leaves it - also when that call was made from inside such a handler. One exception: do not free the control from a handler that runs inside an assignment to `Text` (the setter is LCL's own and still reads the control after the control's code has returned); free it after the assignment returns, for example with `Application.ReleaseComponent`.

### Tables

- **Tab moves between cells only with `WantTabs`.** In a cell, Tab goes to the next cell (after a row's last, the next row's first; a cell merged away is passed over) and selects its content; Shift+Tab goes to the cell before, and does nothing in the first cell. Tab in the table's last cell adds a row below it (one undo step) and goes into its first cell. Ctrl+Tab inserts a tab character. With `WantTabs` False, Tab moves the focus in a table too, as on Delphi's `TRichEdit`. With `ReadOnly`, Tab and Shift+Tab still go from cell to cell; Tab in the last cell does nothing.
- **Table methods**: `InsertTable(ARows, ACols)`, `InsertRow` and `InsertColumn` (`AAfter`, `True` by default: below, to the right), `DeleteRow` and `DeleteColumn` (every row or column the selection touches), `DeleteTable`, `InTable`, and `CanInsertTable` … `CanDeleteTable` for an action's `Update`. Delphi's `TRichEdit` and RichMemo have none of them. They are the user's actions: with `ReadOnly` they do nothing and return `False`, as cutting and pasting do; in a plain text document (`PlainText`), while the file loads or is saved, and where the table does not allow it they return `False`, change nothing and tell `OnEditRefused` why (no exception). `DeleteColumn` takes the column of every cell the selection covers, in text order as it is shown selected: a whole row covered is every column. Code that changes the tables of a read-only control runs the document's commands: `Document.Execute` with `TTyRichInsertTable`, `TTyRichInsertRow` and the others of `tyControls.RichEdit.Commands`.
- **What cannot be changed**: the rows and columns of a table with merged cells or with a table inside a cell (shown and saved as the file has them, but not edited); the columns of a table whose rows have different numbers of cells; more than 63 columns or 32767 rows (Word's limits). In a large RTF file read on demand, also a table too big to read whole (more than about a megabyte of the file) and one the file does not complete. `DeleteTable` deletes a table with merged cells as well.
- **Rows cannot be pasted into a table**: rows pasted with the caret in a cell go in as the cell's text, and rows pasted over a selection of whole rows are refused.
- **Two tables that came to touch** (the paragraph between them deleted) are shown as one, and Tab goes from one into the other; the row and column methods change only the one the caret is in, until the document is saved and opened again.
- **`CanInsertRow` and the others answer cheaply**: asked again with nothing changed, they give their last answer. For a table that a large RTF file read on demand gives in parts they answer `True` unless what is read of it already forbids the change; the action then reads the table and tells why it cannot, when it cannot.

### Pictures

- **Inserting from code**: `InsertPictureFromFile(AFileName)`, `InsertPictureFromStream(AStream)` and `InsertPicture(AGraphic)`, and `CanInsertPicture` for an action's `Update`; Delphi's `TRichEdit` and RichMemo have none of them (nor does this control have RichMemo's `InDelInline`). No dialog is shown: the application asks for the file. A PNG or JPEG file goes in with its own bytes, unchanged - the better way for photographs; a BMP, GIF, TIFF, icon or any other image the LCL reads is decoded and kept as PNG. `InsertPicture` keeps a `TPortableNetworkGraphic` as PNG and a `TJPEGImage` as JPEG (what their `SaveToStream` gives), anything else as PNG. The picture takes the place of the selection, as a paste does (one undo step, "Insert picture"); its size is its pixels at its own resolution (else 96 dpi), made smaller, the shape kept, when it is wider than the room at the caret (the page's text width, or the cell's).
- **They are the user's actions**: with `ReadOnly`, disabled or inside the document's update they do nothing and return `False`; a plain text document, a document loading or being saved, a place a paste could not go, a file that cannot be read (with the system's words), a metafile (`.wmf`, `.emf`), bytes that are no picture and a picture over 128 MB or about 33 million pixels are refused with the reason in `OnEditRefused` (no exception).
- **Handles**: a selected picture shows its frame and eight handles (corners and the middles of the sides) when the user may edit it; a read-only or disabled control, and an object that cannot be resized (a block of RTF the control keeps as it was read), show the frame alone. Their colours are the theme's `TyRichEditObject` (`border-color` the frame and the handles' outline, `background` their fill; `--accent` and `--surface` in `StyleOverride` reach them); their size follows the screen's DPI, not `Zoom`. An application's own object class takes part through `TTyRichObject.CanResize` and `Resized`.
- **Resizing by a handle**: an outline follows the pointer and nothing changes until the release. A corner keeps the picture's shape as it is shown (with Shift it does not), the middle of a side changes that side only, and the side opposite the handle stays where it is. A side is at least 300 twips and at most 22 inches (31,680 twips, Word's limit); the width is at most the room at the picture's place when the text wraps. These limits only stop a drag: a picture already wider than the room, or smaller than 300 twips, keeps its size until a drag makes it smaller (or larger), and a press and release on a handle without a move changes nothing. The release is one command (`TTyRichResizeObject`, one undo step, "Resize object"), and the picture stays selected. It is shown at its new size at once, from the pixels already decoded, and sharp as soon as the background work has made its image at that size. `OnObjectResize` is asked first and may change the size or refuse it. Esc, the capture lost, a release at the size it had, a scroll or a change of the document during the drag change nothing.
- **What a resize keeps**: the picture's bytes and format (a WordPad `\wmetafile8` stays that metafile, a JPEG that JPEG, byte for byte); undoing a resize gives the very picture back, so a file opened, resized, undone and saved is its bytes again. **What it does not keep**: a resized picture is written from the model at its new size, so what the file's picture group said besides the picture - scaling words (`\picscalex`), cropping, other representations of the same picture (`\nonshppict`) and properties (`\picprop`) - is not kept.
- **A metafile the control cannot draw** (an EMF, or a WMF that is more than one bitmap) is shown as a frame; a WordPad metafile that holds one bitmap is drawn. Either can be selected and resized like any picture, and its bytes are saved as they were read.

### Missing

- **Delphi's type names**: the attribute classes are `TTyRichTextAttributes` and `TTyRichParaAttributes`, the sets `TTyRichConsistentAttributes`, `TTyRichConsistentParaAttributes` and `TTySubscriptType`. Their member names are Delphi's (`caBold`, `cpaAlignment`, `sstSuperscript` …), so code that uses the values compiles and code that declares a variable of Delphi's type does not. The ordinals differ.
- **RichMemo's type names**: the records, enums and sets carry the package's prefix (`TTyFontParams`, `TTyParaMetric`, `TTyParaNumbering`, `TTyTabStopList`, `TTyTextModifyMask` …), and `TTabStop` is `TTyRichTabStop`. Members keep RichMemo's names (`paLeft`, `tmm_Styles` …); in a unit that also uses `RichMemo` or `Menus`, qualify them.
- **`Integer` variables passed to `GetStyleRange` or `GetParaRange`** do not compile: declare them `TTyRichPos`.
- **Attributes the control does not hold**: `Protected`, `Disabled`, `Hidden`, `Link`, `Offset`, `Pitch`, `RevAuthor`, `UseForAllText` and their `ConsistentAttributes` members (`caProtected` …). An RTF file's are kept as its bytes and saved back.
- **Memo members**: the control is no `TCustomMemo`, so `WordWrap` (use `WrapMode`), `ScrollBars` (bars appear as needed; `ScrollBarAutoHide`), `Alignment` (per paragraph: `Paragraph.Alignment`), `MaxLength`, `WantReturns` (Enter always makes a paragraph), `BorderStyle`, `Color` and `ParentColor` (the theme's; use `StyleOverride`), `HideSelection`, `HideScrollBars`, `GetSelTextBuf` and `SetSelTextBuf` are not there, and an `is TCustomEdit` test or LCL's standard edit actions do not see it. Its context menu is the package's text menu.
- **Delphi's other members**: `OnProtectChange`, `OnResizeRequest`, `OnSaveClipboard`, `OnLinkClick`, `EnableURLs`, `ShowURLHint`, `SelectionStreamMode`, `SpellChecking`, `ShowSpellCheckMenu`, `Transparent`, `EditMargins`, `ActiveLineNo`, `ScrollPosition` (use `ScrollY`, the view's top in pixels, which can be written; `ScrollX` reads the horizontal offset), `Print`, `RenderRange`, `PageRect`, `DefaultConverter`, `RegisterConversionFormat` and `SetSelTextToFriendlyURL`.
- **RichMemo's other members**: `SetLink`, `isLink`, `OnLinkAction`, `Print`, `OnPrintAction`, `InDelInline`, `InitParaNumber`, `InitParaBullet`, the second `InitTabStopList`, `GetFontParams`, `InitPrintParams` and `InitTextUIParams`.
- **A replace of the current match**: use `SelText :=` or `InDelText`.
- **`Lines` in a form file.** A rich document cannot be stored as lines without its formats, so `Lines` is not published: set the text or load a file at run time.
- **A form converted from Delphi** gets an unknown-property error for each property below that Delphi's `TRichEdit` stored and this control does not publish. Removing them is enough (opening the form brings up the IDE's Repair LFM file dialog: Remove all invalid properties; or, with the .lfm open in the editor, Tools → Check LFM File in Editor) unless the table names something to set instead.

| Delphi property | Use instead |
|-----------------|-------------|
| `Lines.Strings` | the text set or a file loaded at run time |
| `WordWrap` | `WrapMode` (`False`: `rwmNone`) |
| `ScrollBars`, `HideScrollBars` | nothing: the bars appear as needed; `ScrollBarAutoHide` |
| `HideSelection` | nothing: the selection stays shown without the focus, in the theme's colour for it |
| `Alignment` | `Paragraph.Alignment` or `ParaAlign`, per paragraph at run time |
| `MaxLength` | nothing: there is no length limit |
| `WantReturns` | nothing: Enter always makes a paragraph |
| `Color`, `ParentColor`, `BorderStyle`, `BorderWidth`, `BevelEdges`, `BevelInner`, `BevelOuter`, `BevelKind`, `BevelWidth`, `Ctl3D`, `ParentCtl3D`, `StyleElements`, `StyleName` | the theme; `StyleOverride` or `StyleClass` |
| `ParentFont` | nothing: `Font` is the control's own base font over the theme |
| `BiDiMode`, `ParentBiDiMode` | nothing: there is no right-to-left layout |
| `ImeMode`, `ImeName` | nothing: the input method is the system's |
| `EditMargins` | the theme's padding; `StyleOverride` |
| `EnableURLs`, `ShowURLHint`, `SelectionStreamMode`, `SpellChecking`, `Transparent`, `Touch` | nothing |
| `OnLinkClick`, `OnProtectChange`, `OnResizeRequest`, `OnSaveClipboard`, `OnGesture`, `OnMouseActivate`, `OnStartDock`, `OnEndDock` | nothing; the handler stays in the unit, unattached |
- **RichMemo's `TTyParaNumbering` keeps only `Style` and `NumberStart`**: `pnCustomChar` becomes a bullet, and `Indent`, `CustomChar`, `SepChar` and `ForceNewNum` read 0, `#0` or `False`.
- **A bar tab**: `tabWordBar` is written as a left stop.

### RichMemo methods that behave differently

- **`GetTextAttributes` gives the shown font's name and size for text without its own**; automatic colour is `clDefault`. The read-change-write idiom freezes nothing into the text.
- **`TTyParaMetric.LineSpacing` is on RichMemo's scale** (single 1.2, one and a half 1.8, double 2.4). A write takes the nearest of the four the control has; 0 or less leaves the spacing alone, and an exact or at-least spacing reads 0.
- **`SetParaMetric` and `SetRangeParaParams` change each paragraph from its own values**, in one undo step.
- **`SetRangeParams` with a style in both the add and the remove set turns it off**, as RichMemo's does.
- **`SetTextAttributes` with length 0 at the caret sets the format for what is typed next**; elsewhere length 0 does nothing.
- **`GetStyleRange` stays inside the position's paragraph.**
- **`InDelText` is one undo step** in the format of the first character it replaces, and returns the characters inserted.
- **`LoadRichText` makes `PlainText` `False`**; it and `SaveRichText` return `False` on an error (out of memory is raised).
- **`ZoomFactor` is `Zoom / 100`**, written to whole percent.

### Added

- **Paragraphs**: `ParaAlign` (with justify), `NumberingStart`, `SpaceBefore`, `SpaceAfter`, `LineSpacingRule`, `LineSpacing` (points); each write changes only its own part of each paragraph.
- **Selection and editing**: `CaretIndex` (the caret's own end), `CollapseSelection`, `BeginEdit` / `EndEdit` (several writes as one undo step), `RangeText`.
- **Tables**: `InsertTable`, `InsertRow`, `InsertColumn`, `DeleteRow`, `DeleteColumn`, `DeleteTable`, `InTable` and the `Can…` functions; Tab between cells (see Tables above).
- **Pictures**: `InsertPictureFromFile`, `InsertPictureFromStream`, `InsertPicture`, `CanInsertPicture`; a selected picture's handles and resizing by them, `OnObjectResize` (see Pictures above).
- **Find and replace**: `FindNext`, `FindNextAsync`, `ReplaceAll` (three forms), `ReplaceAllAsync`, `CancelFind`, `FindRunning`, `OnFindProgress`, `OnFindDone`, `OnReplaceDone`. A replace is one undo step and is not stopped by `ReadOnly`.
- **`Action` is published**, as on `TTyMemo` (Delphi's `TRichEdit` and LCL's `TMemo` do not publish it): with an action linked, a click on the editor runs it; its `Caption` does not go into the text.
- **Large files**: an RTF file is read in the background (`Loading`, `FinishLoading`, `CancelLoad`, `OnLoadProgress`); `OnSaveProgress` reports a save.
- **Events and settings**: `OnModifiedChange`, `OnEditRefused` (a user's edit the document refused), `OnZoomChange`, `OnFallbackFont`, `WrapMode`, `TextEncoding`, `TextCodePage`, `ScrollBarAutoHide`.
- **The document itself**: `Document` (commands, undo history, formats) for code that needs more than the control's members.
