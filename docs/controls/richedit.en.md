# TTyRichEdit — rich text editing

[中文](richedit.md)

## 1. What it is, and what it is not

`TTyRichEdit` is a rich text editor that draws itself; it can also be used only to show a document. It reads and writes RTF and plain text, edits formatted text, paragraphs, lists, tables and pictures, and follows the theme and the skin. It uses no rich text control of the platform, so it looks and works the same on Windows, macOS and Linux (GTK2, GTK3, Qt5, Qt6).

What it does not do:

- **No pages.** There is no page view, no headers or footers, no print preview. Text wraps at the window's width, at the document's paper width and margins (`WrapMode = rwmPage`, WordPad's "wrap to ruler"), or not at all.
- **No spell checking.**
- **Fields are read-only.** Links, a table of contents, page numbers and cross references show the result the file stores, as ordinary text and paragraphs. The control does not recalculate them, and the text of a result cannot be changed (select the whole field to delete it). A change there is refused, and the reason comes through `OnEditRefused`.
- **Right-to-left text is not laid out.** A paragraph's right-to-left flag is read and written back, but the paragraph is still laid out from the left.
- What the control does not understand in a file (comments, footnotes, tracked changes, equations, shapes, embedded objects ...) is not lost: it is kept as hidden content or as one object and written back as it was.

Unit `tyControls.RichEdit`; on the component palette, page `TyControls Edits`, are `TTyRichEdit` and its ruler `TTyRichEditRuler`. The theme's type key is `TyRichEdit` (a rule it does not set comes from `TyMemo`).

```pascal
uses tyControls.RichEdit, tyControls.RichEdit.Ruler, tyControls.RichEdit.Actions;
```

The smallest use:

```pascal
RichEdit1.LoadFromFile('notes.rtf');    // RTF or text: the file decides
RichEdit1.SelStart := 0;
RichEdit1.SelLength := 5;
RichEdit1.SelAttributes.Bold := True;   // one undo step
RichEdit1.SaveToFile('notes.rtf');
```

The whole example is `examples/richedit`: a small word processor whose menus and toolbar are the actions of §4, with the ruler, a status bar and the skins; its Samples menu opens a few documents (Chinese text and its formats, a table, pictures, Word's table of contents with its links).

## 2. Two layers of API

### 2.1 Delphi's shape (and RichMemo's methods)

Most code written for Delphi's `TRichEdit` or Lazarus' RichMemo compiles as it is:

- Text and selection: `Lines`, `Text`, `SelStart`, `SelLength`, `SelText`, `CaretPos`, `SelectAll`, `Clear`. Positions count characters (Unicode code points), a paragraph's end is one character, the type is `TTyRichPos` (`Int64`).
- Formats: `SelAttributes` (the selection's character format), `DefAttributes` (what text without a format of its own is shown in), `Paragraph` (the format of the paragraphs the selection touches), and RichMemo's `SetTextAttributes`, `GetTextAttributes`, `SetRangeParams`, `SetParaAlignment`, `SetParaMetric`, `SetParaNumbering`, `GetParaRange`, `SetParaTabs`. When read, `ConsistentAttributes` says which attributes the whole selection shares.
- Find and replace: `FindText`, RichMemo's `Search`, and the control's own `FindNext` and `ReplaceAll`, with `FindNextAsync` and `ReplaceAllAsync` running in the background.
- Files: `LoadFromFile`, `LoadFromStream`, `SaveToFile`, `SaveToStream`, `PlainText`.
- The rest: `Zoom`, `ReadOnly`, `Modified`, `Undo`, `Redo`, `CanUndo`, `CanPaste`, the clipboard methods.

Each write of this layer is one command of the document, so one undo step. It is the program's layer: `ReadOnly` stops the user, not these calls. A write while the document loads or is being saved raises `ETyRichEdit`.

What compiles but does something else than in Delphi or RichMemo is listed item by item in the last section of [LCL differences](../lcl-differences.en.md). The ones met most:

- positions are characters, not UTF-16 units, and a line break counts one;
- `Lines` is not published: a form file holds no content;
- `Text :=`, `Clear` and a load clear the undo history;
- sizes and indents are in points, as in Delphi; inside they are twips (1/20 point).

### 2.2 The document and its commands

Below is the document model `Document` (`TTyRichDocument`, unit `tyControls.RichEdit.Model`). Every change of it is a command object given to `Document.Execute`: `TTyRichInsertText`, `TTyRichDelete`, `TTyRichSetCharFormat`, `TTyRichSetParaFormat`, `TTyRichInsertObject`, the tables' `TTyRichInsertTable`, `TTyRichInsertRow` and the others (unit `tyControls.RichEdit.Commands`). A command keeps the change (piece references, old values), never a copy of the document. The commands between `Document.BeginUpdate` and `EndUpdate` are one undo step; the control's `BeginEdit` / `EndEdit` do the same and also put the selection back.

The user's actions are another set of methods: `InsertTable`, `InsertRow`, `DeleteColumn`, `InsertPictureFromFile`, `ApplyParagraphFormat` (the one the ruler uses), `FindNext`. They behave as keys do: with `ReadOnly` or disabled they do nothing, a refusal is told through `OnEditRefused`, nothing is raised. Each has its `Can…` (`CanInsertTable`, `CanInsertPicture`, `CanUndo` ...) for a toolbar to grey a button with.

## 3. The ruler, `TTyRichEditRuler`

Put it above the rich edit and point `RichEdit` at it. It shows the caret paragraph's first-line indent, the indent of its other lines (the hanging indent), the right indent and the tab stops, on a scale of centimetres or inches (`MeasureUnit`, the system's by default) that follows the zoom, the screen's PPI and the horizontal scroll. With the caret in a table, the zero is the cell's text edge.

While a marker is dragged a line through the text shows where the text will go; the marker snaps to a quarter of the unit (Alt held: no snap); Esc cancels. The release is one command, one undo step (through `ApplyParagraphFormat`). A double click on empty ruler space adds a left tab stop; a stop dragged off the ruler goes. With several paragraphs selected the ruler shows the caret paragraph's markers, and a drag gives that one value to every selected paragraph. Read-only, disabled, loading, or with no rich edit linked, the markers are grey and do not move. The ruler never takes the focus.

## 4. The actions, `tyControls.RichEdit.Actions`

Ready-made actions for a `TActionList` (the IDE's action list editor shows them under "TyControls Rich Edit"); link menu items, `TTySpeedButton`s or any other control to them:

| Action | Caption | Shortcut | Enabled asks | Checked asks |
|---|---|---|---|---|
| `TTyRichEditBold` / `Italic` / `Underline` | Bold / Italic / Underline | Ctrl+B / I / U | may the user format here | the whole selection has the style |
| `TTyRichEditStrikeOut` | Strikethrough | — | the same | the same |
| `TTyRichEditSuperscript` / `Subscript` | Superscript / Subscript | — | the same | the whole selection is superscript / subscript |
| `TTyRichEditAlignLeft` / `Center` / `Right` / `Justify` | Align Left / Center / Align Right / Justify | Ctrl+L / E / R / J | the same | every paragraph the selection touches has that alignment |
| `TTyRichEditBullets` / `Numbering` | Bullets / Numbering | Ctrl+Shift+L / — | the same | those paragraphs are that kind of list |
| `TTyRichEditIndentIncrease` / `Decrease` | Increase / Decrease Indent | — | the same | — |
| `TTyRichEditInsertPicture` | Picture... | — | `CanInsertPicture` | — |
| `TTyRichEditInsertTable` | Table | — | `CanInsertTable` | — |
| `TTyRichEditFind` | Find... | Ctrl+F | the control is enabled | — |
| `TTyRichEditReplace` | Replace... | Ctrl+H | may the user edit here | — |
| `TTyRichEditUndo` / `Redo` | Undo / Redo | Ctrl+Z / Y | `CanUndo` / `CanRedo` | — |
| `TTyRichEditZoomIn` / `ZoomOut` / `ZoomReset` | Zoom In / Zoom Out / 100% | Ctrl+plus / minus / 0 | the zoom is below its upper / above its lower limit | 100%: the zoom is 100 |

"May the user format here" is the control's own answer (`CaretParagraphView`'s `Editable`: not read-only, enabled, the document not loading or being saved, not inside an update). The actions add no rule of their own: what they show is the control's answer, and what they do goes through the control's door for the user. So each action is one undo step, named as the format API names it, and a refusal is told by the control through `OnEditRefused`, as for a key.

- **Which rich edit**: the one `RichEdit` names when it is set (on another form too); else the focused `TTyCustomRichEdit`; else none, and the action is grey.
- **The character styles** are written through `SelAttributes`: with nothing selected they set the format of the text typed next, which is no undo step. `SelAttributes` is the program's layer and does not stop at `ReadOnly`, so the actions write only where the user may format; what the engine refuses in a field's result is told by the control, never raised.
- **Indent** moves the caret paragraph's first line to the next (previous) half inch, never left of the margin; with several paragraphs selected each goes to that place, keeping its own hanging offset (the ruler's rule).
- **Insert table** inserts `Rows` × `Columns` (3 × 3 by default). `OnChooseSize` comes first: the program can ask the user there, change the size or cancel.
- **Insert picture** uses the package's own open dialog (`Dialog`, a `TTyOpenPictureDialog`) with a filter of the formats the control reads (`TyRichPictureFilter`: every picture the LCL reads; PNG and JPEG keep their bytes, the others become PNG; no WMF, no EMF).
- **Find and Replace** show the package's own find and replace dialogs (`Dialog`). Find Next is the control's `FindNext` (match case, whole word, up or down, going on from the other end); Replace replaces the selected match and finds the next; Replace All is `ReplaceAll`, one undo step, and `OnReplaced` says how many it replaced. Nothing found: `OnNotFound`, else the package's message box. The replace methods are the program's layer and do not stop at `ReadOnly`, so the action replaces only where the user may edit.
- **Shortcuts** are the actions' defaults and can be changed. One key is never handled twice: LCL gives a key to the focused control first; the rich edit handles Ctrl+Z and Ctrl+Y itself (undo, redo), so the actions' Ctrl+Z and Ctrl+Y only act with the focus elsewhere and `RichEdit` set; keys the rich edit leaves, such as Ctrl+B, are the actions'.

**What an update costs.** When the program is idle LCL updates every action, more than once when an action has a menu item and a button. The actions do not ask the control each time: each rich edit has one record (`TTyRichEditActionState`) that asks it once after its selection, content, format, view, read-only or enabled state changed - it hears the notification the ruler hears (`AddHandlerOnParagraphView`), not the program's events - and every action reads that record. So an idle round of updates asks the control nothing, whatever the selection's length or the document's size. The one asking after a change asks the format API whether the whole selection is consistent: the control bounds that walk (about 30 ms; what lies beyond counts as "not the same") and remembers the answer for the selection and the content. The figures for a whole 100 MB selection are in §6.

## 5. Files

- **RTF**: read and written. A document saved without a change is byte for byte the file it came from; a changed one writes the parts that did not change as they were. What the control does not understand is kept on its paragraph, its text or as one object, and written back as it was. Chinese: reading decodes by the font's `\fcharset`, else by `\ansicpgN`; a double-byte `\'xx\'xx` joins into one character; `\uN` and `\ucN` are understood. Writing puts every non-ASCII character as `\uN` with fallback bytes, and Chinese fonts as `\fcharset134`. A large RTF file is parsed on demand: an index first, each paragraph when it is first needed.
- **Plain text**: the encoding comes from the BOM, then from whether the bytes are valid UTF-8, then from the system's ANSI code page (`TextEncoding`, `TextCodePage` can set it). A save keeps the encoding, the BOM and the line breaks.
- **Which format**: `LoadFromFile` asks the file itself; `SaveToFile` without a format asks the extension, then `PlainText`. A document with `PlainText = True` is saved as plain text; its formats do not go into the file.
- **Pictures** keep their bytes (PNG, JPEG); WordPad's pictures (a WMF holding one bitmap) are drawn too, and a metafile the control cannot draw is shown as a frame, its bytes kept. Tables, merged cells and tables inside cells are read, shown and saved back as they were; in a table with merged cells, and in a row that holds a nested table, rows and columns cannot be inserted or deleted.

## 6. Large files

What is promised: a 100 MB txt and a 100 MB RTF open and edit without lag - the first screen within 1 s, any scroll position within 100 ms, a keystroke within 30 ms, memory at most three times the file's size. The one thing on the user interface's thread that grows with the document is the scan at load time; everything else touches only what is visible, or runs in the background in slices that can be cancelled (`OnLoadProgress`, `CancelLoad`, `FindNextAsync`, `ReplaceAllAsync`, `CancelFind`).

The figures of the performance suite (`TTyRichEditPerfTest`) on this machine:

| What | Time |
|---|---|
| 100 MB txt: load and first screen painted (the file just written, in the system's cache) | 338 ms |
| 100 MB txt: jump to the middle and paint | 52 ms |
| 100 MB txt: a character typed in the middle, to the end of its paint | 2.1 ms |
| 100 MB RTF: first slice loaded and first screen painted | 330 ms |
| 100 MB RTF: the rest indexed in the background (the interface stays free) | 1.5 s |
| 100 MB RTF: a character typed in the middle, to the end of its paint | 1.6 ms |
| the process's peak memory after a 100 MB load | about 180 MB |
| Tab in a table of 10,000 rows | 1.1 ms |
| all of a 100 MB txt / RTF selected: the 23 actions' first round of updates (the one asking) | 55 / 64 ms |
| an idle round after it | 0.0 ms |
| moving a selection of 50 Mi characters (drag and drop) | 314 ms |
| pasting 10 MB of RTF | 3.6 s |

(Windows 10; the machine's load during the run 3 to 5 %.)

What is slow - what grows with the range it changes:

- A format written over the whole document (Select All, then Bold): the command touches every paragraph, and an RTF file read on demand is parsed whole by it; over a large range the wait cursor shows.
- Copying or cutting everything, or pasting a lot: in proportion to the content.
- The synchronous `FindText`, `FindNext` and `ReplaceAll` search to the end; for a long document use `FindNextAsync` and `ReplaceAllAsync`, which run in the background in slices.
- Saving a changed large file writes all of it.

## 7. How it differs from Delphi's TRichEdit and RichMemo

The full list is the last section of [LCL differences](../lcl-differences.en.md). In short:

- it is not Windows' RichEdit: there are no `EM_` messages, `Perform(EM_…)` does nothing, and that page names what to use for each;
- positions are code points, not UTF-16 units;
- `ReadOnly` stops the user only, a program's writes still change the document; the user's actions called by code (`CutToClipboard`, `Undo` ...) do nothing with it, as in Delphi;
- `PlainText` is the document's state, and loading a text file makes it `True`;
- `OnProtectChange`, `OnResizeRequest` and `OnSaveClipboard` are not there; `OnEditRefused`, `OnObjectResize`, `OnDropFiles`, `OnFallbackFont` and the background find's events are added;
- RichMemo's `Search` goes backward by the rule of RichMemo's back ends; `ZoomFactor` is `Zoom / 100`.

## 8. Extension points

- **Events**: `OnEditRefused` (a user's action was refused; the reason is a sentence the user can be shown), `OnObjectResize` (before a picture is resized by its handles; change or refuse it), `OnDropFiles` (files dropped on the control: handle them or leave them to it), `OnFallbackFont` (a character was shown in another font), `OnLoadProgress`, `OnSaveProgress`, `OnFindProgress`, `OnFindDone`, `OnReplaceDone`.
- **Virtual methods of `TTyCustomRichEdit`**: `CreateDocument`, `CreateDevice`, `CreateLayouter` (another document, measuring and drawing device, layouter); `RunUserEdit` (see every edit of the user); `CommandRefusal`, `EditRefused` (how a refusal is told); `PlainTextDocument`; `ShowTextMenu` (the context menu); `DoChange`, `DoSelectionChange`, `DoZoomChange`; the clipboard's reading and writing.
- **Commands**: a descendant of `TTyRichCommand` given to `Document.Execute` is one undo step.
- **The ruler**: `DrawMarker`, `DrawTickLabel` and `Snap` are virtual; `OnMarkerChanging` (can refuse a change) and `OnMarkerChanged`.
- **The actions**: a descendant overrides `UpdateOn` and `ExecuteOn`; the picture's `AskFileName` and find and replace's `ShowDialog` and `ShowNotFound` are virtual, for a program's own interface.
- **A toolbar of your own**: without these actions, `CaretParagraphView`, `AddHandlerOnParagraphView`, `ApplyParagraphFormat` and the `Can…` functions are public; the ruler and the actions use only public calls like these.
