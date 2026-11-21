unit test.richedit.builder;

{ TTyRichBuilder: a page made from code - text in formats, paragraphs in formats, lists, tab
  stops, links, bookmarks, pictures from every source, tables - put into the control by
  SetContent (as a load), AppendContent and InsertContent (one undo step each, the file's
  bytes again after the undo). A builder needs no control; misuse raises with the call's name.

  Headless, on the display suite's probe (the test device). }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry, Controls, Graphics, LCLType,
  tyControls.Controller, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.RtfRead, tyControls.RichEdit.Attrs,
  tyControls.RichEdit.Builder, tyControls.RichEdit,
  test.richedit.control, test.richedit.display;

type
  TTyRichBuilderTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TDisplayProbe;
    FBack: TDisplayProbe;
    FImages: TImageList;
    FTemp: string;
    function NewProbe: TDisplayProbe;
    function Saved(AProbe: TDisplayProbe = nil): TBytes;
    function ReadBack(const B: TBytes): TTyRichDocument;
    function ParaText(ADoc: TTyRichDocument; AIndex: Integer): string;
    function CharAt(ADoc: TTyRichDocument; APos: TTyRichPos): TTyCharFormat;
    function PF(ADoc: TTyRichDocument; AIndex: Integer): TTyParaFormat;
    function Links(ADoc: TTyRichDocument): string;
    function Welcome(B: TTyRichBuilder): TTyRichBuilder;
    procedure NeedImages;
    procedure Raises(const ACall: string; AProc: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheWelcomePage;
    procedure TestSetContentClearsTheHistoryAndResetsTheDocument;
    procedure TestAppendAndInsertAreOneUndoStepEach;
    procedure TestWorksWhenReadOnly;
    procedure TestStylesAreOnlyAConvenience;
    procedure TestOnePaintAfterSetContent;
    procedure TestABuilderCanBeUsedTwice;
    procedure TestMisuseRaisesAClearError;
    procedure TestTheFormatsOfTheBuild;
    procedure TestLinksAndBookmarksJumpWithoutAHandler;
    procedure TestPicturesFromEverySource;
    procedure TestTablesWithWidthsAndCellsOfSeveralParagraphs;
    procedure TestABuilderAloneMakesADocument;
  end;

implementation

uses
  BGRABitmap, BGRABitmapTypes, tyControls.RichEdit.Bookmarks;

const
  BS = #92;
  CBlue = #$E6#$AC#$A2#$E8#$BF#$8E#$E4#$BD#$BF#$E7#$94#$A8;   // 欢迎使用

function AsRaw(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

{ ---- fixtures ---- }

procedure TTyRichBuilderTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
  FBack := nil;
  FImages := nil;
  FTemp := '';
end;

procedure TTyRichBuilderTest.TearDown;
begin
  FreeAndNil(FBack);
  FreeAndNil(FRich);
  FreeAndNil(FImages);
  FreeAndNil(FCtl);
  if (FTemp <> '') and FileExists(FTemp) then DeleteFile(FTemp);
end;

function TTyRichBuilderTest.NewProbe: TDisplayProbe;
begin
  Result := TDisplayProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
end;

function TTyRichBuilderTest.Saved(AProbe: TDisplayProbe): TBytes;
var
  st: TMemoryStream;
begin
  if AProbe = nil then AProbe := FRich;
  st := TMemoryStream.Create;
  try
    AProbe.SaveToStream(st, rfRtf);
    Result := nil;
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Memory^, Result[0], st.Size);
  finally
    st.Free;
  end;
end;

function TTyRichBuilderTest.ReadBack(const B: TBytes): TTyRichDocument;
var
  st: TBytesStream;
begin
  FreeAndNil(FBack);
  FBack := NewProbe;
  st := TBytesStream.Create(B);
  try
    FBack.LoadFromStream(st);
  finally
    st.Free;
  end;
  FBack.FinishLoading;
  Result := FBack.Document;
end;

function TTyRichBuilderTest.ParaText(ADoc: TTyRichDocument; AIndex: Integer): string;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
end;

function TTyRichBuilderTest.CharAt(ADoc: TTyRichDocument; APos: TTyRichPos): TTyCharFormat;
var
  k, i: Integer;
  runs: TTyRunArray;
  o: TTyRichPos;
begin
  k := ADoc.Text.ParaOfPos(APos);
  o := APos - ADoc.Text.ParaStart(k);
  runs := ADoc.RunsOf(k);
  i := 0;
  while (i < High(runs)) and (runs[i + 1].Start <= o) do Inc(i);
  Result := ADoc.Formats.CharFormat(runs[i].Format);
end;

function TTyRichBuilderTest.PF(ADoc: TTyRichDocument; AIndex: Integer): TTyParaFormat;
begin
  Result := ADoc.Formats.ParaFormat(ADoc.ParaFormatOf(AIndex));
end;

{ Every link's instruction, in order, '|' after each. }
function TTyRichBuilderTest.Links(ADoc: TTyRichDocument): string;
var
  k, i: Integer;
  runs: TTyRunArray;
begin
  Result := '';
  for k := 0 to ADoc.Text.ParaCount - 1 do
  begin
    runs := ADoc.RunsOf(k);
    for i := 0 to High(runs) do
      if (runs[i].Obj is TTyRichFieldMark) and (TTyRichFieldMark(runs[i].Obj).Kind = rfmOpen) then
        Result := Result + TyRichFieldInstruction(ADoc, TTyRichFieldMark(runs[i].Obj)) + '|';
  end;
end;

procedure TTyRichBuilderTest.NeedImages;
var
  bmp: TBitmap;
  i: Integer;
const
  Colors: array[0..3] of TColor = (clRed, clGreen, clBlue, clYellow);
begin
  if FImages <> nil then Exit;
  FImages := TImageList.Create(nil);
  FImages.Width := 16;
  FImages.Height := 16;
  bmp := TBitmap.Create;
  try
    bmp.SetSize(16, 16);
    for i := 0 to 3 do
    begin
      bmp.Canvas.Brush.Color := Colors[i];
      bmp.Canvas.FillRect(0, 0, 16, 16);
      FImages.Add(bmp, nil);
    end;
  finally
    bmp.Free;
  end;
end;

{ The page of the design (its section 5.1), as an application writes it. }
function TTyRichBuilderTest.Welcome(B: TTyRichBuilder): TTyRichBuilder;
begin
  NeedImages;
  B.Align(paraCenter).SpaceAfter(12);
  B.Font('Microsoft YaHei', 20).Bold.Text(CBlue);
  B.Paragraph;
  B.Reset.Text('This is ').Bold.Text('bold').Bold(False).Text(', then ');
  B.Link('docs', 'https://example.com/docs').Text(' and ').Link('section two', '#sec2').Text('.');
  B.Paragraph.Picture(FImages, 3);
  B.Table([2400, 4800]);
  B.Cell.Shading(clSkyBlue).Text('Name');
  B.Cell.Text('What it is');
  B.Row;
  B.Cell.Text('A');
  B.Cell.Text('...');
  B.EndTable;
  B.Paragraph.Bookmark('sec2').Text('Section two');
  Result := B;
end;

procedure TTyRichBuilderTest.Raises(const ACall: string; AProc: Integer);
var
  B: TTyRichBuilder;
  msg: string;
begin
  B := TTyRichBuilder.Create;
  msg := '';
  try
    try
      case AProc of
        0: B.Cell;
        1: B.EndTable;
        2: B.Row;
        3: B.Table([]).Cell.Table([]);
        4: B.Table([]).Text('x');
        5: B.Link('x', '');
        6: B.Bookmark('9bad');
        7: begin B.Table([1000]).Cell; B.MakeDocument.Free; end;
        8: B.Table([1000]).Cell.Cell;
        9: B.Style('nothing');
        10: B.Table([]).Cell.Row.EndTable;
      end;
    except
      on E: ETyRichEdit do msg := E.Message;
    end;
  finally
    B.Free;
  end;
  AssertTrue(ACall + ': raised', msg <> '');
  AssertTrue(ACall + ': the call named in "' + msg + '"', Pos(ACall, msg) > 0);
end;

{ ---- the tests ---- }

procedure TTyRichBuilderTest.TestTheWelcomePage;
var
  B: TTyRichBuilder;
  d: TTyRichDocument;
  f: TTyCharFormat;
  b0: TBytes;
  s: RawByteString;
  a, e: TTyRichPos;
  w, h, k: Integer;
begin
  B := Welcome(TTyRichBuilder.Create);
  try
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  d := FRich.Document;
  AssertEquals('the caret at the start', Int64(0), FRich.CaretIndex);
  AssertEquals('nothing selected', 0, FRich.SelLength);
  // heading, text, picture, two rows of two cells, the section: 3 + 4 + 1 (after the table)
  AssertEquals('paragraphs', 8, d.Text.ParaCount);
  AssertEquals('the heading', CBlue, ParaText(d, 0));
  AssertEquals('centred', Ord(paraCenter), Ord(PF(d, 0).Align));
  AssertEquals('12 pt after', 240, PF(d, 0).SpaceAfter);
  f := CharAt(d, 0);
  AssertEquals('its font', 'Microsoft YaHei', f.FontName);
  AssertEquals('20 pt', 40, f.SizeHalfPt);
  AssertTrue('bold', fsBold in f.Style);
  // the second paragraph: the default paragraph format, the document's character format
  AssertEquals('left again', Ord(paraLeft), Ord(PF(d, 1).Align));
  k := d.Text.ParaStart(1);
  AssertFalse('Reset: not bold', fsBold in CharAt(d, k).Style);
  AssertEquals('Reset: the default font', '', CharAt(d, k).FontName);
  AssertTrue('"bold" bold', fsBold in CharAt(d, k + 8).Style);
  AssertEquals('the links', 'HYPERLINK "https://example.com/docs"|HYPERLINK \l "sec2"|', Links(d));
  // the picture: image 3 of the list, 16 px
  AssertTrue('a picture', d.ObjectAt(d.Text.ParaStart(2)) is TTyRichPicture);
  AssertTrue('its size', d.ObjectAt(d.Text.ParaStart(2)).DisplaySize(w, h));
  AssertEquals('16 px', 240, w);
  // the table: two columns, 2400 and 4800 twips
  AssertTrue('a table', d.CellAt(3) <> nil);
  AssertEquals('two columns', 2, d.CellAt(3).Row.CellCount);
  AssertEquals('the first edge', 2400, d.CellAt(3).Row.CellEdges[0]);
  AssertEquals('the second edge', 7200, d.CellAt(3).Row.CellEdges[1]);
  AssertEquals('two rows', 2, d.CellAt(3).Table.RowCount);
  AssertEquals('a cell', 'Name', ParaText(d, 3));
  AssertTrue('no table after it', d.CellAt(7) = nil);
  AssertEquals('the section (after its two marks)', 'Section two', ParaText(d, 7).Replace(#$EF#$BF#$BC, ''));
  AssertTrue('the bookmark', FRich.FindBookmark('sec2', a, e));
  AssertEquals('at the section', d.Text.ParaStart(7), a);
  // saved: Word's syntax, and read back the same
  b0 := Saved;
  s := AsRaw(b0);
  AssertTrue('a field of Word''s', Pos('{' + BS + 'field{' + BS + '*' + BS + 'fldinst', s) > 0);
  AssertTrue('a bookmark of Word''s', Pos('{' + BS + '*' + BS + 'bkmkstart sec2}', s) > 0);
  AssertTrue('the column''s edge', Pos(BS + 'cellx2400', s) > 0);
  d := ReadBack(b0);
  AssertEquals('read back: paragraphs', 8, d.Text.ParaCount);
  AssertEquals('read back: the heading', CBlue, ParaText(d, 0));
  AssertEquals('read back: the links', 'HYPERLINK "https://example.com/docs"|HYPERLINK \l "sec2"|',
    Links(d));
  AssertTrue('read back: the bookmark', FBack.FindBookmark('sec2', a, e));
  AssertTrue('read back: the picture', d.ObjectAt(d.Text.ParaStart(2)) is TTyRichPicture);
  AssertEquals('read back: the edge', 7200, d.CellAt(3).Row.CellEdges[1]);
  AssertTrue('read back: bold', fsBold in CharAt(d, d.Text.ParaStart(1) + 8).Style);
end;

procedure TTyRichBuilderTest.TestSetContentClearsTheHistoryAndResetsTheDocument;
var
  B: TTyRichBuilder;
begin
  FRich.Lines.Text := 'old text';
  FRich.SelStart := 3;
  FRich.SelText := 'x';
  FRich.DocumentColor := clYellow;
  FRich.SetPageSetup(10000, 1000, 1000);
  AssertTrue('something to undo', FRich.Document.CanUndo);
  B := TTyRichBuilder.Create;
  try
    B.Text('new');
    FRich.SetContent(B);
    AssertEquals('the content', 'new', FRich.Lines.Text.Trim);
    AssertEquals('one paragraph', 1, FRich.Document.Text.ParaCount);
    AssertFalse('no history', FRich.Document.CanUndo);
    AssertFalse('not modified', FRich.Modified);
    AssertEquals('the ground: none (Clear''s)', clNone, FRich.DocumentColor);
    AssertEquals('the page: a new document''s', 11906, FRich.Document.PaperWidth);
    AssertEquals('the caret at the start', Int64(0), FRich.CaretIndex);
    // the builder's own: taken
    B.PageSetup(12240, 1440, 1440).DocumentColor(clNavy);
    FRich.SetContent(B);
    AssertEquals('the builder''s ground', clNavy, FRich.DocumentColor);
    AssertEquals('the builder''s page', 12240, FRich.Document.PaperWidth);
    AssertEquals('its margin', 1440, FRich.Document.MarginLeft);
    AssertFalse('still no history', FRich.Document.CanUndo);
  finally
    B.Free;
  end;
  // an empty builder: what Clear leaves
  B := TTyRichBuilder.Create;
  try
    FRich.SetContent(B);
    AssertEquals('empty', 0, FRich.Document.Text.Length);
    AssertEquals('the ground again', clNone, FRich.DocumentColor);
  finally
    B.Free;
  end;
end;

procedure TTyRichBuilderTest.TestAppendAndInsertAreOneUndoStepEach;
var
  B: TTyRichBuilder;
  before: TBytes;
  n: Integer;
begin
  FRich.Lines.Text := 'first' + LineEnding + 'second';
  FRich.Document.ClearUndo;
  FRich.SelStart := 2;
  before := Saved;
  B := TTyRichBuilder.Create;
  try
    B.Bold.Text('A').Paragraph.Reset.Link('l', 'http://x.test');
    n := FRich.Document.UndoDepth;
    FRich.AppendContent(B);
    AssertEquals('append: one step', n + 1, FRich.Document.UndoDepth);
    AssertEquals('after the last paragraph', 4, FRich.Document.Text.ParaCount);
    AssertEquals('the last paragraph stays', 'second', ParaText(FRich.Document, 1));
    AssertEquals('the content', 'A', ParaText(FRich.Document, 2));
    AssertEquals('the selection stays', 2, FRich.SelStart);
    FRich.Undo;
    AssertTrue('append undone: the bytes as before', SameBytes(before, Saved));
    // at a paragraph's start: whole paragraphs before it, the selection shifted
    FRich.SelStart := FRich.Document.Text.ParaStart(1) + 2;
    n := FRich.Document.UndoDepth;
    FRich.InsertContent(FRich.Document.Text.ParaStart(1), B);
    AssertEquals('insert: one step', n + 1, FRich.Document.UndoDepth);
    AssertEquals('before the second paragraph', 'A', ParaText(FRich.Document, 1));
    AssertEquals('the second paragraph after it', 'second', ParaText(FRich.Document, 3));
    AssertEquals('the caret shifted along', FRich.Document.Text.ParaStart(3) + 2, FRich.SelStart);
    FRich.Undo;
    AssertTrue('insert undone: the bytes as before', SameBytes(before, Saved));
    // in a paragraph, one paragraph of content: in line
    B.Free;
    B := TTyRichBuilder.Create;
    B.Text('XY');
    FRich.InsertContent(2, B);
    AssertEquals('in line', 'fiXYrst', ParaText(FRich.Document, 0));
    FRich.Undo;
    AssertTrue('undone again', SameBytes(before, Saved));
    // nothing in a builder: nothing put in, no step
    B.Free;
    B := TTyRichBuilder.Create;
    n := FRich.Document.UndoDepth;
    FRich.AppendContent(B);
    FRich.InsertContent(0, B);
    AssertEquals('an empty builder: no step', n, FRich.Document.UndoDepth);
  finally
    B.Free;
  end;
end;

procedure TTyRichBuilderTest.TestWorksWhenReadOnly;
var
  B: TTyRichBuilder;
begin
  FRich.ReadOnly := True;
  B := TTyRichBuilder.Create;
  try
    B.Text('page');
    FRich.SetContent(B);
    AssertEquals('set', 'page', ParaText(FRich.Document, 0));
    FRich.AppendContent(B);
    FRich.InsertContent(0, B);
    AssertEquals('appended and inserted', 3, FRich.Document.Text.ParaCount);
  finally
    B.Free;
  end;
end;

procedure TTyRichBuilderTest.TestStylesAreOnlyAConvenience;
var
  B: TTyRichBuilder;
  d: TTyRichDocument;
  s: RawByteString;
begin
  B := TTyRichBuilder.Create;
  try
    B.Font('Arial', 18).Bold.Align(paraCenter).DefineStyle('h1');
    B.Reset.Align(paraLeft).DefineStyle('body');
    B.Style('h1').Text('Title').Paragraph.Style('body').Text('Text').Paragraph.Style('h1').Text('Again');
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  d := FRich.Document;
  AssertTrue('h1: bold', fsBold in CharAt(d, 0).Style);
  AssertEquals('h1: 18 pt', 36, CharAt(d, 0).SizeHalfPt);
  AssertEquals('h1: centred', Ord(paraCenter), Ord(PF(d, 0).Align));
  AssertFalse('body: not bold', fsBold in CharAt(d, d.Text.ParaStart(1)).Style);
  AssertEquals('body: left', Ord(paraLeft), Ord(PF(d, 1).Align));
  AssertEquals('h1 again: centred', Ord(paraCenter), Ord(PF(d, 2).Align));
  s := AsRaw(Saved);
  AssertEquals('no style sheet in the file', 0, Pos('stylesheet', s));
  AssertEquals('no style word', 0, Pos(BS + 's1', s));
end;

{ Putting content in lays out and paints nothing by itself: the next paint does, once. }
procedure TTyRichBuilderTest.TestOnePaintAfterSetContent;
var
  B: TTyRichBuilder;
  laid, blocks, frames: Integer;
  i: Integer;
begin
  FRich.Lines.Text := 'x';
  FRich.UpdateView;
  B := TTyRichBuilder.Create;
  try
    for i := 1 to 200 do B.Text('Line ' + IntToStr(i)).Paragraph;
    laid := FRich.LaidParas;
    blocks := FRich.BlockPaints;
    frames := FRich.FramePaints;
    FRich.SetContent(B);
    AssertEquals('nothing laid out inside the call', laid, FRich.LaidParas);
    AssertEquals('nothing painted inside the call', blocks, FRich.BlockPaints);
    AssertEquals('no frame painted inside the call', frames, FRich.FramePaints);
    FRich.UpdateView;
    AssertTrue('one layout: only what is in view', FRich.LaidParas - laid < 60);
  finally
    B.Free;
  end;
end;

procedure TTyRichBuilderTest.TestABuilderCanBeUsedTwice;
var
  B: TTyRichBuilder;
  d: TTyRichDocument;
  k, i, n: Integer;
  runs: TTyRunArray;
  ids: array of Int64;
begin
  B := TTyRichBuilder.Create;
  try
    B.Text('see ').Link('it', 'http://x.test').Text('.');
    FRich.SetContent(B);
    FRich.AppendContent(B);
    AssertEquals('twice', 2, FRich.Document.Text.ParaCount);
    AssertEquals('the same text', ParaText(FRich.Document, 0), ParaText(FRich.Document, 1));
    // each its own marks
    d := FRich.Document;
    ids := nil;
    for k := 0 to 1 do
    begin
      runs := d.RunsOf(k);
      for i := 0 to High(runs) do
        if (runs[i].Obj is TTyRichFieldMark) and (TTyRichFieldMark(runs[i].Obj).Kind = rfmOpen) then
        begin
          n := Length(ids);
          SetLength(ids, n + 1);
          ids[n] := TTyRichFieldMark(runs[i].Obj).Id;
        end;
    end;
    AssertEquals('two links', 2, Length(ids));
    AssertTrue('two fields of their own', ids[0] <> ids[1]);
    // and it goes on building
    B.Paragraph.Text('more');
    FRich.SetContent(B);
    AssertEquals('built on', 2, FRich.Document.Text.ParaCount);
  finally
    B.Free;
  end;
end;

procedure TTyRichBuilderTest.TestMisuseRaisesAClearError;
begin
  Raises('Cell', 0);
  Raises('EndTable', 1);
  Raises('Row', 2);
  Raises('Table', 3);
  Raises('Text', 4);
  Raises('Link', 5);
  Raises('BookmarkStart', 6);
  Raises('TTyRichBuilder', 7);
  Raises('Cell', 8);
  Raises('Style', 9);
  Raises('EndTable', 10);
end;

procedure TTyRichBuilderTest.TestTheFormatsOfTheBuild;
var
  B: TTyRichBuilder;
  d: TTyRichDocument;
  f: TTyCharFormat;
  p: TTyParaFormat;
  k: TTyRichPos;
begin
  B := TTyRichBuilder.Create;
  try
    // a paragraph's format may be set any time before the next Paragraph
    B.Text('one').Indent(36, -18, 12).Spacing(6, 3).LineSpacing(1.5).Tab(72, rtaRight, rtlDot);
    B.Paragraph.Bullet(1, '>').Text('item');
    B.Paragraph.Numbered(0, 3).Text('three');
    B.Paragraph.LineSpacingExact(20).Shading(clYellow).Text('shaded');
    // Paragraph keeps the character format; a link keeps a colour of its own
    B.Paragraph.Italic.Text('a').Paragraph.Text('b').Color(clRed).Link('red', 'http://r.test');
    B.Reset.Link('theme', 'http://t.test');
    B.Paragraph.Superscript.Text('2').Subscript.Text('x').StrikeOut.Underline.Highlight(clLime).Text('y');
    B.Paragraph.Reset.Text('l1' + #10 + 'l2' + #9 + 'tab');
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  d := FRich.Document;
  p := PF(d, 0);
  AssertEquals('left indent', 720, p.LeftIndent);
  AssertEquals('first indent', -360, p.FirstIndent);
  AssertEquals('right indent', 240, p.RightIndent);
  AssertEquals('before', 120, p.SpaceBefore);
  AssertEquals('after', 60, p.SpaceAfter);
  AssertEquals('1.5 lines', Ord(ls15), Ord(p.LineSpacing));
  AssertEquals('a tab', 1, Length(p.Tabs));
  AssertEquals('its leader', Ord(ttlDot), Ord(p.Tabs[0].Leader));
  AssertEquals('bullet', Ord(lkBullet), Ord(PF(d, 1).List.Kind));
  AssertEquals('its level', 1, PF(d, 1).List.Level);
  AssertEquals('its text', '>', PF(d, 1).List.Bullet);
  AssertEquals('numbered', Ord(lkDecimal), Ord(PF(d, 2).List.Kind));
  AssertEquals('from 3', 3, PF(d, 2).List.StartAt);
  AssertEquals('Paragraph: the default format again (no list)', Ord(lkNone), Ord(PF(d, 3).List.Kind));
  AssertEquals('exactly 20 pt', Ord(lsExact), Ord(PF(d, 3).LineSpacing));
  AssertEquals('shaded', clYellow, PF(d, 3).Shading);
  AssertEquals('not the next', clNone, PF(d, 4).Shading);
  AssertTrue('Paragraph keeps italic', fsItalic in CharAt(d, d.Text.ParaStart(5)).Style);
  k := d.Text.ParaStart(5) + 3;   // past the open mark: "red"
  f := CharAt(d, k);
  AssertEquals('a link of its own colour: kept', clRed, f.Color);
  AssertTrue('underlined', fsUnderline in f.Style);
  k := d.Text.ParaStart(5) + Length('b') + 1 + 3 + 1 + 1;   // "theme"
  f := CharAt(d, k);
  AssertEquals('a theme link: automatic', clDefault, f.Color);
  AssertTrue('underlined', fsUnderline in f.Style);
  AssertEquals('links', 'HYPERLINK "http://r.test"|HYPERLINK "http://t.test"|', Links(d));
  f := CharAt(d, d.Text.ParaStart(6) + 2);
  AssertTrue('struck', f.Strike);
  AssertEquals('highlight', clLime, f.HighlightColor);
  AssertEquals('superscript then subscript', Ord(vaSub), Ord(f.VertAlign));
  AssertEquals('#10 a line break, #9 a tab', 'l1' + #11 + 'l2' + #9 + 'tab', ParaText(d, 7));
end;

procedure TTyRichBuilderTest.TestLinksAndBookmarksJumpWithoutAHandler;
var
  B: TTyRichBuilder;
  r1, r2: TRect;
  p: TPoint;
  target, a, e: TTyRichPos;
  i: Integer;
begin
  B := TTyRichBuilder.Create;
  try
    B.Text('Contents: ').Link('the end', '#theEnd');
    for i := 1 to 60 do B.Paragraph.Text('filler ' + IntToStr(i));
    B.Paragraph.Bookmark('theEnd').Text('The end');
    FRich.ReadOnly := True;
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  FRich.UpdateView;
  AssertTrue('the bookmark', FRich.FindBookmark('theEnd', a, e));
  target := a;
  r1 := FRich.PositionRect(12);
  r2 := FRich.PositionRect(13, True);
  p := Point((r1.Left + r2.Left) div 2, (r1.Top + r1.Bottom) div 2);
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MUp(mbLeft, [], p.X, p.Y);
  AssertTrue('a click on the contents'' link: at the section, no handler',
    Abs(FRich.CaretIndex - target) <= 2);
  AssertTrue('scrolled to it', FRich.ScrollY > 0);
end;

procedure TTyRichBuilderTest.TestPicturesFromEverySource;
var
  B: TTyRichBuilder;
  bmp: TBGRABitmap;
  g: TBitmap;
  st: TMemoryStream;
  d: TTyRichDocument;
  w, h, k: Integer;
  raised: Boolean;
begin
  NeedImages;
  FTemp := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tybuilder-' +
    IntToStr(GetProcessID) + '.png';
  bmp := TBGRABitmap.Create(30, 10, BGRA(0, 128, 255, 255));
  try
    bmp.SaveToFile(FTemp);
  finally
    bmp.Free;
  end;
  g := TBitmap.Create;
  st := TMemoryStream.Create;
  B := TTyRichBuilder.Create;
  try
    g.SetSize(20, 20);
    g.Canvas.Brush.Color := clRed;
    g.Canvas.FillRect(0, 0, 20, 20);
    st.LoadFromFile(FTemp);
    st.Position := 0;
    B.Text('g').Picture(g).Text('f').Picture(FTemp).Text('s').Picture(st);
    B.Text('l').Picture(FImages, 1).Text('z').Picture(g, 30).Text('b').Picture(g, 15, 45);
    FRich.SetContent(B);
    d := FRich.Document;
    k := d.Text.ParaStart(0);
    AssertTrue('a graphic', d.ObjectAt(k + 1).DisplaySize(w, h));
    AssertEquals('its own size', 300, w);
    AssertTrue('a file', d.ObjectAt(k + 3).DisplaySize(w, h));
    AssertEquals('the file''s size', 450, w);
    AssertEquals('the file''s height', 150, h);
    AssertTrue('a stream', d.ObjectAt(k + 5).DisplaySize(w, h));
    AssertEquals('the stream''s size', 450, w);
    AssertTrue('an image list', d.ObjectAt(k + 7).DisplaySize(w, h));
    AssertEquals('16 px', 240, w);
    AssertTrue('30 pt wide', d.ObjectAt(k + 9).DisplaySize(w, h));
    AssertEquals('30 pt: 600 twips', 600, w);
    AssertEquals('in proportion', 600, h);
    AssertTrue('both given', d.ObjectAt(k + 11).DisplaySize(w, h));
    AssertEquals('15 pt', 300, w);
    AssertEquals('45 pt', 900, h);
    // a resource that is not there, a file that is not there
    raised := False;
    try
      B.PictureResource('NO_SUCH_RESOURCE_HERE');
    except
      on E: ETyRichEdit do raised := Pos('PictureResource', E.Message) > 0;
    end;
    AssertTrue('no resource: raised, named', raised);
    raised := False;
    try
      B.Picture(FTemp + '.none');
    except
      on E: ETyRichEdit do raised := Pos('Picture', E.Message) > 0;
    end;
    AssertTrue('no file: raised, named', raised);
  finally
    B.Free;
    st.Free;
    g.Free;
  end;
end;

procedure TTyRichBuilderTest.TestTablesWithWidthsAndCellsOfSeveralParagraphs;
var
  B: TTyRichBuilder;
  d: TTyRichDocument;
  i: Integer;
begin
  B := TTyRichBuilder.Create;
  try
    B.Text('before');
    B.Table([]).Cell.Text('a1').Paragraph.Text('a2').Link('l', 'http://x.test');
    B.Cell.Shading(clYellow).Text('b').Cell.Text('c');
    B.Row(30).Cell.Cell.Cell.Text('last');
    B.EndTable.Text('after');
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  d := FRich.Document;
  AssertEquals('before', 'before', ParaText(d, 0));
  AssertTrue('the table', d.CellAt(1) <> nil);
  AssertEquals('a cell of two paragraphs', 'a1', ParaText(d, 1));
  AssertEquals('... its second', 'a2l', ParaText(d, 2).Replace(#$EF#$BF#$BC, ''));
  AssertTrue('the same cell', d.CellAt(1) = d.CellAt(2));
  AssertEquals('three columns', 3, d.CellAt(1).Row.CellCount);
  // equal columns over the text width (A4, 1.25-inch margins)
  AssertEquals('equal: the first edge', (11906 - 3600) div 3, d.CellAt(1).Row.CellEdges[0]);
  AssertEquals('two rows', 2, d.CellAt(1).Table.RowCount);
  // the cell's shading: recorded for the cell properties, nothing shown yet - and never a
  // paragraph's shading in its place
  for i := 0 to d.Text.ParaCount - 1 do
    AssertEquals('no paragraph shading', clNone, PF(d, i).Shading);
  AssertEquals('after', 'after', ParaText(d, d.Text.ParaCount - 1));
  AssertTrue('after: in no table', d.CellAt(d.Text.ParaCount - 1) = nil);
end;

procedure TTyRichBuilderTest.TestABuilderAloneMakesADocument;
var
  B: TTyRichBuilder;
  d: TTyRichDocument;
begin
  B := TTyRichBuilder.Create;
  try
    AssertTrue('new: empty', B.IsEmpty);
    B.Bold;
    AssertTrue('a format alone: still empty', B.IsEmpty);
    B.Text('one').Paragraph.Text('two');
    AssertFalse('not empty', B.IsEmpty);
    d := B.MakeDocument;
    try
      AssertEquals('two paragraphs', 2, d.Text.ParaCount);
      AssertEquals('its text', 'one', ParaText(d, 0));
      AssertTrue('bold', fsBold in CharAt(d, 0).Style);
    finally
      d.Free;
    end;
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TTyRichBuilderTest);

end.
