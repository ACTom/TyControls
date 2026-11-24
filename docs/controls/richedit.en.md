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

The whole example is `examples/richedit`: a small word processor whose menus, two toolbar rows and the editor's context menu are the actions of §4 - with a font box, a size box (half sizes too) and text and highlight colour buttons that open the package's colour dialog - with the ruler, a status bar and the skins; when the window is narrow a toolbar row wraps; its Samples menu opens a few documents (Chinese text and its formats, a table, pictures, Word's table of contents with its links) and a page built from code (§5) shown as a help page and as a home page (§6); Insert has a link and a bookmark form, and a double click on a picture shows it at its own size (§7).

## 2. Two layers of API

### 2.1 Delphi's shape (and RichMemo's methods)

Most code written for Delphi's `TRichEdit` or Lazarus' RichMemo compiles as it is:

- Text and selection: `Lines`, `Text`, `SelStart`, `SelLength`, `SelText`, `CaretPos`, `SelectAll`, `Clear`. Positions count characters (Unicode code points), a paragraph's end is one character, the type is `TTyRichPos` (`Int64`).
- Formats: `SelAttributes` (the selection's character format), `DefAttributes` (what text without a format of its own is shown in), `Paragraph` (the format of the paragraphs the selection touches), and RichMemo's `SetTextAttributes`, `GetTextAttributes`, `SetRangeParams`, `SetParaAlignment`, `SetParaMetric`, `SetParaNumbering`, `GetParaRange`, `SetParaTabs`. When read, `ConsistentAttributes` says which attributes the whole selection shares. Beyond Delphi's: `SelAttributes.SizeF` (half points), `Paragraph.ListLevel`, `ListStart` and `BulletText` (a list's level, start and bullet), `SetTab` with an alignment and a leader (a dot leader for a contents line), `LineSpacingMultiple` (any multiple: 1.08, 3), `SpaceBefore` / `SpaceAfter`, `Shading` (a paragraph's ground); and on the control `ApplyParagraphSpacing` (the user's space before and after), `SetPageSetup` (the paper's width and margins), `SetDefaultFormats` and `DocumentColor` (the document's own ground). A list's start: a number written to `Paragraph.NumberingStart` (`ListStart`) makes the selection's first list item begin a new list at that number and its other items go on from it; 0 makes them go on again, and 0 read means the item goes on from the one before it.
- Find and replace: `FindText`, RichMemo's `Search`, and the control's own `FindNext` and `ReplaceAll`, with `FindNextAsync` and `ReplaceAllAsync` running in the background.
- Files: `LoadFromFile`, `LoadFromStream`, `SaveToFile`, `SaveToStream`, `PlainText`.
- The rest: `Zoom`, `ReadOnly`, `Modified`, `Undo`, `Redo`, `CanUndo`, `CanPaste`, the clipboard methods.

Units: the character and paragraph members (sizes, indents, spacing, tab stops) are in points, as Delphi's; the page and table geometry (`SetPageSetup`, the builder's `PageSetup` and `Table` widths, `Document.Settings`) is in twips, 1440 an inch, as the file has it.

Each write of this layer is one command of the document, so one undo step. It is the program's layer: `ReadOnly` stops the user, not these calls. A write while the document loads or is being saved raises `ETyRichEdit`.

What compiles but does something else than in Delphi or RichMemo is listed item by item in the last section of [LCL differences](../lcl-differences.en.md). The ones met most:

- positions are characters, not UTF-16 units, and a line break counts one;
- `Lines` is not published: a form file holds no content;
- `Text :=`, `Clear` and a load clear the undo history;
- sizes and indents are in points, as in Delphi; inside they are twips (1/20 point).

### 2.2 The document and its commands

Below is the document model `Document` (`TTyRichDocument`, unit `tyControls.RichEdit.Model`). Every change of it is a command object given to `Document.Execute`: `TTyRichInsertText`, `TTyRichDelete`, `TTyRichSetCharFormat`, `TTyRichSetParaFormat`, `TTyRichInsertObject`, the tables' `TTyRichInsertTable`, `TTyRichInsertRow` and the others (unit `tyControls.RichEdit.Commands`). A command keeps the change (piece references, old values), never a copy of the document. The commands between `Document.BeginUpdate` and `EndUpdate` are one undo step; the control's `BeginEdit` / `EndEdit` do the same and also put the selection back.

The user's actions are another set of methods: `ApplyCharacterFormat` (a toolbar's Bold, a font box), `ApplyParagraphFormat` (alignment, indents; the ruler uses it too), `InsertTable`, `InsertRow`, `DeleteColumn`, `InsertPictureFromFile`. They behave as keys do: with `ReadOnly` or disabled they do nothing, a refusal is told once through `OnEditRefused`, nothing is raised. `FindNext` (the user's Find Next) belongs with them but edits nothing, so it works with `ReadOnly` too. That is what sets them apart from the format API: `SelAttributes` is the program's write, ignores `ReadOnly` and raises `ETyRichEdit` when refused. Each action has its `Can…` (`CanFormatCharacters`, `CanFormatParagraphs`, `CanInsertTable`, `CanInsertPicture`, `CanUndo` ...) that says whether it would be taken now, for a toolbar to grey a button with. They need no layout, and what they read is bounded: at most `CRichFormatQueryParas` of the selection's paragraphs from its first, each one's field depth and cell.

## 3. The ruler, `TTyRichEditRuler`

Put it above the rich edit and point `RichEdit` at it. It shows the caret paragraph's first-line indent, the indent of its other lines (the hanging indent), the right indent and the tab stops, on a scale of centimetres or inches (`MeasureUnit`, the system's by default) that follows the zoom, the screen's PPI and the horizontal scroll. With the caret in a table, the zero is the cell's text edge.

While a marker is dragged a line through the text shows where the text will go; the marker snaps to a quarter of the unit (Alt held: no snap); Esc cancels. The release is one command, one undo step (through `ApplyParagraphFormat`). A double click on empty ruler space adds a left tab stop; a stop dragged off the ruler goes. The ruler shows the paragraph a paragraph format change begins at (the one `Paragraph` reads and a drag changes): the caret's with nothing selected, the first one with several selected, and a drag gives that one value to every selected paragraph. Read-only, disabled, loading, with no rich edit linked, or where `CanFormatParagraphs` says no (a field's result, a row that holds a nested table), the markers are grey and do not move. The ruler never takes the focus.

## 4. The actions, `tyControls.RichEdit.Actions`

Ready-made actions for a `TActionList` (the IDE's action list editor shows them under "TyControls Rich Edit"); link menu items, `TTySpeedButton`s or any other control to them:

| Action | Caption | Shortcut | Enabled asks | Checked asks |
|---|---|---|---|---|
| `TTyRichEditCut` / `Copy` / `Paste` | Cut / Copy / Paste | Ctrl+X / C / V | a selection, not read-only / a selection / the clipboard holds something it can paste | — |
| `TTyRichEditSelectAll` / `Delete` | Select All / Delete | Ctrl+A / — | the document has text / a selection, not read-only | — |
| `TTyRichEditBold` / `Italic` / `Underline` | Bold / Italic / Underline | Ctrl+B / I / U | may the user format here | the whole selection has the style |
| `TTyRichEditStrikeOut` | Strikethrough | — | the same | the same |
| `TTyRichEditSuperscript` / `Subscript` | Superscript / Subscript | — | the same | the whole selection is superscript / subscript |
| `TTyRichEditFontName` | Font | — | the same | the whole selection is in `FontName` |
| `TTyRichEditFontSize` | Font Size | — | the same, and `Size` is above 0 | the whole selection is `Size` points |
| `TTyRichEditFontGrow` / `FontShrink` | Grow Font / Shrink Font | Ctrl+Shift+. / , | the same, and there is a next size | — |
| `TTyRichEditTextColor` / `HighlightColor` | Text Color / Highlight | — | the same | — |
| `TTyRichEditClearFormat` | Clear Formatting | Ctrl+Space | the same | — |
| `TTyRichEditAlignLeft` / `Center` / `Right` / `Justify` | Align Left / Center / Align Right / Justify | Ctrl+L / E / R / J | the same | every paragraph the selection touches has that alignment |
| `TTyRichEditBullets` / `Numbering` | Bullets / Numbering | Ctrl+Shift+L / — | the same | those paragraphs are that kind of list |
| `TTyRichEditIndentIncrease` / `Decrease` | Increase / Decrease Indent | — | the same | — |
| `TTyRichEditLineSpacing` | Line Spacing | — | the same | those paragraphs have `Spacing`, or `Multiple` when it is set |
| `TTyRichEditParagraphSpacing` | Paragraph Spacing | — | the same, and `Before` or `After` is set | those paragraphs have the space `Before` / `After` given |
| `TTyRichEditInsertPicture` | Picture... | — | `CanInsertPicture` | — |
| `TTyRichEditInsertTable` | Table | — | `CanInsertTable` | — |
| `TTyRichEditInsertLink` / `RemoveLink` | Link... / Remove Link | — | `CanInsertLink` or `CanEditLink` / `CanEditLink` | — |
| `TTyRichEditInsertRowAbove` / `RowBelow` | Insert Row Above / Below | — | `CanInsertRow` | — |
| `TTyRichEditInsertColumnLeft` / `ColumnRight` | Insert Column Left / Right | — | `CanInsertColumn` | — |
| `TTyRichEditDeleteRow` / `DeleteColumn` / `DeleteTable` | Delete Row / Column / Table | — | `CanDeleteRow` / `CanDeleteColumn` / `CanDeleteTable` | — |
| `TTyRichEditFind` | Find... | Ctrl+F | the control is enabled | — |
| `TTyRichEditReplace` | Replace... | Ctrl+H | may the user edit here | — |
| `TTyRichEditUndo` / `Redo` | Undo / Redo | Ctrl+Z / Y | `CanUndo` / `CanRedo` | — |
| `TTyRichEditZoomIn` / `ZoomOut` / `ZoomReset` | Zoom In / Zoom Out / 100% | Ctrl+plus / minus / 0 | the zoom is below its upper / above its lower limit | 100%: the zoom is 100 |

"May the user format here" is the control's own answer (`CanFormatCharacters`, `CanFormatParagraphs`: not read-only, enabled, the document not loading or being saved, not inside an update, and the selection not wholly inside a field's result or a row that holds a nested table). The actions add no rule of their own: what they show is the control's answer, and what they do goes through the control's door for the user. So each action is one undo step, named as the format API names it, and a refusal is told by the control through `OnEditRefused`, as for a key.

- **The ruler** can be dragged only where `CanFormatParagraphs` says yes: in a field's result or a row that holds a nested table its markers are grey and a press starts no drag.
- **Which rich edit**: the one `RichEdit` names when it is set (on another form too); else the focused `TTyCustomRichEdit`; else none, and the action is grey.
- **The character styles** are written through `ApplyCharacterFormat`: with nothing selected they set the format of the text typed next, which is no undo step. In a field's result and in a row that holds a nested table the format actions are grey, and so is Insert picture.
- **The clipboard actions** are the text menu's (`CutToClipboard`, `CopyToClipboard`, `PasteFromClipboard`, `SelectAll`, `ClearSelection`), with the answers the edit's own context menu gives.
- **Font and size**: `TTyRichEditFontName` sets `FontName`, `TTyRichEditFontSize` sets `Size` in whole points (a font size box can give half points through `ApplyCharacterFormat`, `SizeHalfPt`). Grow and Shrink go to the next size of the usual list (8, 9, 10, 11, 12, 14 ... 72) from the selection's size.
- **Colours**: `TTyRichEditTextColor` and `TTyRichEditHighlightColor` apply their `Color` (red and yellow by default; `clDefault` is the theme's text colour, `clNone` no highlight). `OnChooseColor` comes first: the program can ask the user there (the package's `TySelectColor`), change the colour or cancel; the chosen colour is kept for the next time.
- **Clear Formatting** gives the selection's characters the default format back: font, size, styles, position and colours; the paragraph formats stay.
- **Line Spacing** sets `Spacing` (single, 1.15, 1.5, double), or `Multiple` when it is above 0 (any multiple, 1.08 or 3), on the paragraphs the selection touches; one action per spacing, as with the alignments. **Paragraph Spacing** sets the space `Before` and `After` (points, to the twip - 7.5 as well; -1, the default, leaves that side), either or both - 0, 6 and 12 as in Word's menu; it is checked when the paragraph has exactly those points. Lines are measured as Word measures them: single spacing is the font's own line height (for a Western font its height plus the gap it asks for between lines, the gap above the text; for an East Asian font such as SimSun or Microsoft YaHei 1.3 times its height, the extra split above and below), 1.15, 1.5 and double are multiples of it with the extra below the text, a multiple below 1 shrinks the whole line from above and below alike while the glyphs are drawn whole over the line above (0.1 at the least), an "at least" spacing adds what is missing above the text, and an exact spacing is exact, with the baseline four fifths of the way down. Space before and after a paragraph stays outside its lines. Each line's height is whole device pixels, so a long text can come out about one per cent shorter than in Word.
- **Links**: `TTyRichEditInsertLink` asks through `OnGetLink` for the address and the text (with no handler it does nothing: the program asks the user); in a link it changes that link (`SetLink`), elsewhere it makes one (`InsertLink`). `TTyRichEditRemoveLink` is `RemoveLink`. See §7.
- **The table operations** insert a row above or below the caret's, a column left or right of it, or delete the row, the column or the whole table; the caret goes into the new row or column. Each is grey where the control says no (outside a table, in a table with merged cells, in a row that holds a nested table, a column where the rows differ in their cells).
- **Indent** moves the caret paragraph's first line to the next (previous) half inch, never left of the margin; with several paragraphs selected each goes to that place, keeping its own hanging offset (the ruler's rule).
- **Insert table** inserts `Rows` × `Columns` (3 × 3 by default). `OnChooseSize` comes first: the program can ask the user there, change the size or cancel.
- **Insert picture** uses the package's own open dialog (`Dialog`, a `TTyOpenPictureDialog`) with a filter of the formats the control reads (`TyRichPictureFilter`: every picture the LCL reads; PNG and JPEG keep their bytes, the others become PNG; no WMF, no EMF).
- **Find and Replace** show the package's own find and replace dialogs (`Dialog`). Find Next is the control's `FindNext` (match case, whole word, up or down, going on from the other end); Replace replaces the selected match and finds the next; Replace All is `ReplaceAll`, one undo step, and `OnReplaced` says how many it replaced. Nothing found: `OnNotFound`, else the package's message box. The replace methods are the program's layer and do not stop at `ReadOnly`, so the action replaces only where the user may edit.
- **Shortcuts** are the actions' defaults and can be changed. One key is never handled twice: LCL gives a key to the focused control first; the rich edit handles Ctrl+Z and Ctrl+Y itself (undo, redo), so the actions' Ctrl+Z and Ctrl+Y only act with the focus elsewhere and `RichEdit` set; keys the rich edit leaves, such as Ctrl+B, are the actions'.

**What an update costs.** When the program is idle LCL updates every action, more than once when an action has a menu item and a button. The actions do not ask the control each time: each rich edit has one record (`TTyRichEditActionState`) that asks it once after its selection, content, format, view, read-only or enabled state changed - it hears the notification the ruler hears (`AddHandlerOnParagraphView`), not the program's events - and every action reads that record. So an idle round of updates asks the control nothing, whatever the selection's length or the document's size - except the five clipboard actions, which ask the control's text answers (`TeHasSelection`, `TeHasText`, `TeIsReadOnly`) at every update, as LCL's own edit actions do; Paste asks `CanPaste`, which looks at the formats on the system's clipboard. The one asking after a change asks the format API whether the whole selection is consistent: the control bounds that walk (about 30 ms; what lies beyond counts as "not the same") and remembers the answer for the selection and the content. The figures for a whole 100 MB selection are in §9.

## 5. Building content from code

A page that is not a file - a home page, a help page, a "what's new" note - is written with a builder, `TTyRichBuilder` (unit `tyControls.RichEdit.Builder`). Its calls read in the order the page does, and each one returns the builder, so they chain:

```pascal
uses tyControls.RichEdit, tyControls.RichEdit.Builder, Graphics;

procedure ShowWelcome(Rich: TTyRichEdit);
var
  B: TTyRichBuilder;
begin
  B := Rich.NewBuilder;              // the document's own defaults; yours to free
  try
    B.Font('', 20).Bold.Text('Welcome');
    B.Paragraph.Reset.Text('Read the ').Link('guide', '#guide')
      .Text(' or visit ').Link('the Lazarus site', 'https://www.lazarus-ide.org/').Text('.');
    B.Paragraph.Bullet.Text('A point');
    B.Paragraph.Bullet(1).Text('a point under it');
    B.Paragraph.Shading(TColor($00D7F4FF)).Text('A note on a light yellow ground.');
    B.Table([2160, 5040]);
    B.Cell.Bold.Text('Name').Cell.Text('What it is').Reset;
    B.Row.Cell.Text('Builder').Cell.Text('Content made from code');
    B.EndTable;
    B.Paragraph.SpaceBefore(12).Bookmark('guide').Bold.Text('The guide').Reset;
    B.Paragraph.Text('A "#guide" link jumps here by itself.');
    Rich.SetContent(B);              // a new content; AppendContent, InsertContent add to it
  finally
    B.Free;
  end;
end;
```

This procedure is in `examples/richedit/upagesample.pas` word for word, so it is compiled with the example. The rest of that unit builds a longer page - a picture, a contents list of links, lists with a second level, tab stops with a dot leader, a shaded note, a table - and the example's Samples > A Page Built from Code shows it.

**How the builder thinks.** It keeps a current character format and the format of the paragraph being built. A character call (`Font`, `Bold`, `Italic`, `Underline`, `StrikeOut`, `Superscript`, `Subscript`, `Color`, `Highlight`) changes the format of what is added after it; `Reset` goes back to the document's default. A paragraph call (`Align`, `Indent`, `Spacing`, `SpaceBefore`, `SpaceAfter`, `LineSpacing`, `LineSpacingExact`, `Tab`, `Bullet`, `Numbered`, `Shading`) changes the paragraph being built. The first paragraph is there from the start; `Paragraph` ends it and begins the next in the default paragraph format, keeping the character format. Sizes, indents and spacing are points; table columns are twips (1440 an inch).

- **Text**: `Text` (`#9` a tab, `#10` a line break inside the paragraph).
- **Lists**: `Bullet(level, text)` and `Numbered(level, start)`; level 0 is the outermost (8 the deepest), each level its own hanging indent. An item given a start begins a new list at that number; with none (0) it goes on from the item before it on its level: `Numbered(0, 5)`, `Numbered`, `Numbered` are 5, 6, 7, and a `Numbered(0, 1)` after them is 1 again; an inner item after an outer one starts at 1.
- **Tab stops**: `Tab(pos, align, leader)`, for example `Tab(300, rtaRight, rtlDot)` for a contents line.
- **Links and bookmarks**: `Link(text, url)` - the text first, in the order the page reads, as `Text`; the control's `InsertLink(url, text)` takes the address first, because its text is optional - `Bookmark(name)` (a point), `BookmarkStart` / `BookmarkEnd` (a range). A link to `'#name'` jumps to that bookmark when clicked, with no code of yours (§7).
- **Pictures**: `Picture` from a `TGraphic`, a file, a stream or an image list and index, `PictureResource` from the application's resources; a size in points, or 0 for its own (its pixels at 96 dpi). PNG and JPEG keep their bytes, anything else becomes PNG.
- **Tables**: `Table(widths)` (empty: equal columns over the text width), `Cell` before each cell's content, `Row` for the next row, `EndTable`. Each row must have as many cells as the table has columns. A `Paragraph` right after `EndTable` is the paragraph after the table, not one more.
- **Styles**: `DefineStyle(name)` keeps the current character and paragraph format under a name, `Style(name)` applies both. They are a convenience of the build: nothing of them goes into the document.
- **The document's own values**: `PageSetup(width, left, right)` and `DocumentColor(color)` are taken by `SetContent` only.

A call in the wrong place - a `Cell` outside a table, a table inside a cell, an address or a bookmark name Word does not take, a picture that cannot be read - raises `ETyRichEdit`, its message naming the call ("TTyRichBuilder.Cell: …").

**Three ways in.** All three are edits from code: they do not ask `ReadOnly`, so they work on a read-only page. The builder stays yours, unchanged, and can be put in again. `SetContent` on a document still loading ends the load and replaces the document; one being saved raises `ETyRichEdit`. `AppendContent` and `InsertContent` raise `ETyRichEdit` on a document that is loading or being saved.

| Call | What it does |
|---|---|
| `SetContent(B)` | A new content, as a load: the undo history goes, `Modified` is False, the caret is at the start, and `PageSetup` / `DocumentColor` are taken. |
| `AppendContent(B)` | The content after the last paragraph, one undo step. A last paragraph that holds something stays as it is; an empty one takes the content's first paragraph. |
| `InsertContent(Pos, B)` | The content at `Pos`, one undo step. At a paragraph's start its paragraphs go in before that paragraph; inside a paragraph they go in as a paste does; in a table cell they become the cell's paragraphs (a table of the builder becomes its text). |

**What it costs.** The builder only records: formats are kept once each in a pool, nothing is measured or laid out while you build. Putting the content in lays out nothing either; the next paint lays the view out once and paints once. Ten thousand formatted paragraphs (bold words, a link every tenth paragraph) are built and put in with `SetContent` in about 100 ms on the development machine.

**What it cannot make yet.** A cell's shading and borders and a row's height are accepted (`Shading` inside a cell, `Row(height)`) and kept, but not shown until the table properties come; column widths work. There are no merged cells, and a table inside a cell is refused.

## 6. As a display page

A rich edit can show a page instead of editing one: a home page, a navigation page, a help page, without an HTML viewer. These properties make it one:

| Property | What it does |
|---|---|
| `ReadOnly` | True: nothing can be typed or changed by the user; code still writes. |
| `CaretWhenReadOnly` | False: no caret while `ReadOnly`. The selection is still drawn. |
| `AllowSelection` | False: the user selects nothing - no drag, no double click, no Shift+arrow, Ctrl+A and Copy do nothing; the pointer is the arrow over text and the hand over a link. With `ReadOnly` as well, a right click shows no menu of the control's own (every item would be grey); `PopupMenu` and `OnContextPopup` work as on any control. |
| `FocusOnClick` | False: a click never takes the focus (the wheel and the links still work); with `TabStop` False the control is never focused at all. |
| `ScrollBars` | `ssNone`: never a bar of its own; the keys still scroll, the wheel goes to the parent. Any other value shows a bar only when the content needs it. The wheel is the control's only in a direction it can scroll (a bar may show there and the content does not fit) - then also at its end; otherwise it goes on to the parent, so a page in a scroll box scrolls with the box. Ctrl + wheel always zooms. |
| `AutoHeight` | True: `Height` follows `ContentHeight` (within `Constraints`) whenever the content, the width, the zoom, the PPI or the theme change. It does nothing while `Align` (`alClient`, `alLeft`, `alRight`) or the top and bottom anchors decide the height, and nothing while the content's size is an estimate (`ContentSizeIsEstimate`: a file still loading, more paragraphs than are measured whole) - the control keeps the height it has. It never sets more than `CRichAutoHeightLimit` (32,000 pixels): a window fails far above that. It is for pages, not files: the control keeps a drawing surface of its own size, so a page costs its width × height × 4 bytes; a document longer than the limit belongs in a control that scrolls itself. |

`ContentHeight` and `ContentWidth` are the client pixels the content needs at the current width, zoom and theme; `ContentSizeIsEstimate` says when they are an estimate (a large document not laid out whole). `OnContentSizeChange` fires once per change.

The two usual combinations, as in the example's page form (`examples/richedit/upageform.lfm`):

- **A help page** - read, select and copy, scroll by itself: `ReadOnly := True; CaretWhenReadOnly := False;` with `Align := alClient`. `AllowSelection` and `ScrollBars` stay at their defaults (True, `ssBoth`).
- **A home page** - as tall as its content inside a `TTyScrollBox`, which scrolls it as one page among other controls: `ReadOnly := True; CaretWhenReadOnly := False; AllowSelection := False; FocusOnClick := False; TabStop := False; ScrollBars := ssNone; AutoHeight := True;` with `Align := alTop` in the scroll box. `FocusOnClick` False keeps a click from taking the focus; `TabStop` False keeps Tab from stopping there - a home page wants both. The wheel over the page scrolls the box, and a right click brings no menu of the page's own. `AcceptDrops` is still True: a file dropped on the page is the control's (and nothing happens, it is read-only) and does not reach the form - set it False when the form takes dropped files.

**Links on a page.** On a read-only page, or one with `AllowSelection` False, a plain left click (or a middle click) on a link fires `OnLinkClick`; on an editable one it takes Ctrl+click, as in Word. The control never opens an address itself: open a web address in `OnLinkClick` (`OpenURL`). A link to `'#name'` is followed by the control (`FollowBookmarkLinks`, True by default): the line the bookmark starts on comes to the top of the view, unless it is already in the top third. On a home page the rich edit is as tall as its content and has nothing to scroll; the scroll box around it must move, which `OnFollowLink` can do:

```pascal
procedure TPageForm.HomeFollowLink(Sender: TObject; const AName: string; var AAllow: Boolean);
var
  s, e: TTyRichPos;
  r: TRect;
begin
  AAllow := False;
  if not HomeRich.FindBookmark(AName, s, e) then Exit;
  r := HomeRich.PositionRect(s);
  HomeBox.ScrollTo(0, HomeBox.ScrollY + HomeRich.Top + r.Top);
end;
```

**Theme.** Text in the automatic colour is drawn in the theme's text colour and links without a colour of their own in the theme's link colour, so a page built with the builder follows the skin and its dark mode. Colours the page gives itself (a red word, a shaded paragraph, `DocumentColor`) stay; automatic text over them takes whichever of the theme's text colour and its opposite stands out.

## 7. Links and bookmarks

A link is a Word HYPERLINK field; its address is one of `'target'`, `'#name'` (a bookmark of this document) or `'target#name'`. The user's methods:

- `InsertLink(url, text)`: a selection becomes the link's text as it is; `text` given goes in its place; neither, the address itself is the text. The address comes first because the text is optional; the builder's `Link(text, url)` takes the text first, in reading order - mind the order when moving code between them.
- `SetLink(url, text)`: the link the caret or the selection is in gets the new address; with `text`, its text is replaced too.
- `RemoveLink`: the link stops being one; its text stays, without the link's look.
- `CanInsertLink`, `CanEditLink` say whether these would be taken now; `LinkAtSelection` gives the link's place and address.

They are the user's actions: `ReadOnly` refuses them, each is one undo step, a refusal is told through `OnEditRefused`. A link's text is a field's result and cannot be typed in; `SetLink` changes it. The actions `TTyRichEditInsertLink` (its `OnGetLink` asks for the address and the text; in a link it changes that link) and `TTyRichEditRemoveLink` do the same from a menu (§4).

**Two looks.** `InsertLink` gives a new link Word's look: underlined, in Word's link blue where the text has no colour of its own, as Word makes one. The builder's `Link` makes it underlined in the automatic colour, drawn in the theme's link colour, so it follows the skin. Text with a colour of its own keeps it in both.

**Bookmarks.** `BookmarkCount` and `BookmarkName(index)` list them in the order of their places; the hidden ones (names beginning with "_", Word's own for a table of contents' headings) only when asked (`AIncludeHidden`). `FindBookmark` gives a bookmark's start and end, `GoToBookmark` puts the caret there and its line at the top of the view (a move, not an edit, so it works on a read-only page). `AddBookmark(name)` marks the selection or the caret's place, `DeleteBookmark`, `RenameBookmark`; these three are the user's actions, as `InsertLink`, and `CanEditBookmarks` says whether they would be taken. A name follows Word's rule (`TyRichBookmarkNameValid`: a letter first, then letters, digits or "_", at most 40) and is compared without regard to case. In a large RTF read on demand, a bookmark is found by reading only the paragraphs its two ends are in.

**Typing and pasting at a bookmark.** As in Word, text typed right at a bookmark's start goes into the bookmark, and text typed right at its end goes after it; at a bookmark that is a single point, the text goes after the point. A paste and an input method's text do the same. A pasted, dropped or inserted bookmark (`InsertContent`, `AppendContent`) whose name the document already has is left out: its text comes in, and the bookmark already there stays. So is one that comes in with only one of its two ends. A cut and a paste, or a drag that moves the text, takes the bookmark along.

**Following a link.** A click on a link fires `OnLinkClick(Sender, URL, Button)`, as in Delphi. A `'#name'` link is then followed: `OnFollowLink(Sender, Name, var Allow)` comes first, and `Allow := False` stops it; then `GoToBookmark`. A bookmark that is not there: nothing happens. `'target#name'` and any other address are never followed by the control.

**Objects.** `OnObjectClick` and `OnObjectDblClick` fire for a picture or a block that shows one (an equation, an embedded object): `procedure(Sender: TObject; const AClick: TTyRichObjectClick; var AHandled: Boolean)`. The record holds the object (`RichObject`), its position (`Pos`), the button, the keys (`Shift`), the point in client pixels (`Point`) and the object's box in client pixels (`Bounds`); `PointInPicture(Width, Height)` gives the point inside a picture of that size - an image map on a home page. It is a record so that a member added later breaks no handler. `AHandled := True` stops what the click would do next. `ObjectAtPoint(X, Y, Pos)` finds the object under a point. A picture hands itself to a `TPicture` or a `TBitmap` (`Picture.Assign(TheObject)`) at its own size, and `TTyRichPicture.SaveImageToStream` writes its file's bytes. The example's picture viewer (`uviewerform.pas`) is a double click handled that way.

## 8. Files

- **RTF**: read and written. A document saved without a change is byte for byte the file it came from; a changed one writes the parts that did not change as they were. What the control does not understand is kept on its paragraph, its text or as one object, and written back as it was. Chinese: reading decodes by the font's `\fcharset`, else by `\ansicpgN`; a double-byte `\'xx\'xx` joins into one character; `\uN` and `\ucN` are understood. Writing puts every non-ASCII character as `\uN` with fallback bytes, and Chinese fonts as `\fcharset134`. A large RTF file is parsed on demand: an index first, each paragraph when it is first needed.
- **Lists** are written as Word's list table (`\listtable`, `\listoverridetable`, `\lsN\ilvlM` on the paragraph), with a `{\*\pn ...}` beside it for programs that know no list table, such as the system's RichEdit; Word shows the numbers the control draws. There is one rule: an item given a start begins a new list at it (the builder's `Numbered(0, 5)`), one without (`Numbered`, start 0) goes on from the item before it on its level; an outer item, a paragraph that is no item or another kind on the level ends a list, and the next item is 1. So `Numbered(0, 5)`, `Numbered`, `Numbered` are 5, 6, 7, and a `Numbered(0, 1)` right after them is 1 again; an inner item after an outer one always starts at 1. Levels are 0 to 8 (RTF and Word have nine).
- **Plain text**: the encoding comes from the BOM, then from whether the bytes are valid UTF-8, then from the system's ANSI code page (`TextEncoding`, `TextCodePage` can set it). A save keeps the encoding, the BOM and the line breaks.
- **Which format**: `LoadFromFile` asks the file itself; `SaveToFile` without a format asks the extension, then `PlainText`. A document with `PlainText = True` is saved as plain text; its formats do not go into the file.
- **Pictures** keep their bytes (PNG, JPEG); WordPad's pictures (a WMF holding one bitmap) are drawn too, and a metafile the control cannot draw is shown as a frame, its bytes kept. Tables, merged cells and tables inside cells are read, shown and saved back as they were; in a table with merged cells, and in a row that holds a nested table, rows and columns cannot be inserted or deleted.

## 9. Large files

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
| all of a 100 MB txt / RTF selected: the 23 actions' first round of updates (the one asking) | 50 / 70 ms |
| an idle round after it | 0.0 ms |
| moving a selection of 50 Mi characters (drag and drop) | 314 ms |
| pasting 10 MB of RTF | 3.6 s |

(Windows 10; the machine's load during the run 3 to 5 %.)

What is slow - what grows with the range it changes:

- A format written over the whole document (Select All, then Bold): the command touches every paragraph, and an RTF file read on demand is parsed whole by it; over a large range the wait cursor shows.
- Copying or cutting everything, or pasting a lot: in proportion to the content.
- The synchronous `FindText`, `FindNext` and `ReplaceAll` search to the end; for a long document use `FindNextAsync` and `ReplaceAllAsync`, which run in the background in slices.
- Saving a changed large file writes all of it.

## 10. How it differs from Delphi's TRichEdit and RichMemo

The full list is the last section of [LCL differences](../lcl-differences.en.md). In short:

- it is not Windows' RichEdit: there are no `EM_` messages, `Perform(EM_…)` does nothing, and that page names what to use for each;
- positions are code points, not UTF-16 units;
- `ReadOnly` stops the user only, a program's writes still change the document; the user's actions called by code (`CutToClipboard`, `Undo` ...) do nothing with it, as in Delphi;
- `PlainText` is the document's state, and loading a text file makes it `True`;
- `OnProtectChange` and `OnSaveClipboard` are not there, and `OnResizeRequest` is `OnContentSizeChange` with `ContentHeight` (§6); `OnEditRefused`, `OnObjectResize`, `OnDropFiles`, `OnFallbackFont` and the background find's events are added;
- RichMemo's `Search` goes backward by the rule of RichMemo's back ends; `ZoomFactor` is `Zoom / 100`.

## 11. Extension points

- **Events**: `OnEditRefused` (a user's action was refused; the reason is a sentence the user can be shown), `OnObjectResize` (before a picture is resized by its handles; change or refuse it), `OnDropFiles` (files dropped on the control: handle them or leave them to it), `OnFallbackFont` (a character was shown in another font), `OnLinkClick` and `OnFollowLink` (a link clicked, a bookmark about to be followed), `OnObjectClick` and `OnObjectDblClick` (a picture clicked), `OnContentSizeChange` (the content's size changed), `OnLoadProgress`, `OnSaveProgress`, `OnFindProgress`, `OnFindDone`, `OnReplaceDone`.
- **Virtual methods of `TTyCustomRichEdit`**: `CreateDocument`, `CreateDevice`, `CreateLayouter` (another document, measuring and drawing device, layouter); `RunUserEdit` (see every edit of the user); `CommandRefusal`, `EditRefused` (how a refusal is told); `PlainTextDocument`; `ShowTextMenu` (the context menu); `DoChange`, `DoSelectionChange`, `DoZoomChange`; the clipboard's reading and writing.
- **Commands**: a descendant of `TTyRichCommand` given to `Document.Execute` is one undo step.
- **The ruler**: `DrawMarker`, `DrawTickLabel` and `Snap` are virtual; `OnMarkerChanging` (can refuse a change) and `OnMarkerChanged`.
- **The actions**: a descendant overrides `UpdateOn` and `ExecuteOn`; the picture's `AskFileName` and find and replace's `ShowDialog` and `ShowNotFound` are virtual, for a program's own interface.
- **A toolbar of your own**: without these actions, `ApplyCharacterFormat`, `ApplyParagraphFormat`, the `Can…` functions, `AddHandlerOnParagraphView` (when to ask again) and `ParagraphView` are public; the ruler and the actions use only public calls like these.
