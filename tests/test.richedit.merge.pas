unit test.richedit.merge;

{ Cells merged (TTyCustomRichEdit.MergeCells, the command TTyRichMergeCells): the content in
  reading order in the top-left cell, the grid after it, the look of the merged cell, one undo
  step that gives the file's bytes back, what the door refuses and what CanMergeCells says,
  and the files a person opens in Word to compare. No window. The unit is ASCII. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, LCLType, fpcunit, testregistry, tyControls.Controller,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout,
  tyControls.RichEdit.TableProps, tyControls.RichEdit.TableSel, tyControls.RichEdit,
  tyControls.RichEdit.Grid, tyControls.RichEdit.Builder, test.richedit.layoutdevice,
  test.richedit.grid;

type
  TMergeRich = class(TTyRichEdit)
  protected
    function CreateDevice: TTyRichTextDevice; override;
    // (the clipboard is the control's own here: never the system's)
    procedure WriteClipboard(const ARtf: RawByteString; const AText: string); override;
    function ClipboardFlavours: TTyRichClipFlavours; override;
    function ReadClipboardRtf: RawByteString; override;
    function ReadClipboardText: string; override;
  public
    ClipRtf: RawByteString;
    ClipText: string;
    Refusals: TStringList;
    procedure Refused(Sender: TObject; const AReason: string);
    destructor Destroy; override;
  end;

  TTyRichMergeTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TMergeRich;
    procedure MakeTable(ARows, ACols: Integer);
    function CellStart(ARow, ACol: Integer): TTyRichPos;
    function CellEnd(ARow, ACol: Integer): TTyRichPos;
    procedure SelCells(AR0, AC0, AR1, AC1: Integer);
    function SaveRtf: RawByteString;
    function Grid: TTyRichGrid;
    function CellParas(ARow, ACell: Integer): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMergeJoinsContentInReadingOrder;
    procedure TestARowAndAColumnMerge;
    procedure TestEmptyCellsAddNothing;
    procedure TestTheMergedCellKeepsTheOutline;
    procedure TestEveryStepIsOneUndoWithBytesBack;
    procedure TestASavedMergeReadsAsTheSameGrid;
    procedure TestCanMergeCellsAnswersWhatTheDoorDoes;
    procedure TestSplitRestoresAndSplitsIntoColsAndRows;
    procedure TestASplitThatCannotBeIsRefused;
    procedure TestTheBuildersSpansAreMergeCellsOwn;
    procedure TestTheBuildersSpanMisuseRaises;
    procedure TestWordReadsWhatWeWrite;
    procedure TestTheCommandRefusesCellsNotEmpty;
    procedure TestASpanSplitIntoPartsOfItsRows;
    procedure TestTheTableStillLocksOnlyForNestedTables;
    procedure TestARowInsertedInsideAVerticalSpanWidensIt;
    procedure TestDeleteTheFirstRowOfAVerticalSpanMovesContentDown;
    procedure TestARowDeletedInsideOrAtTheEndOfASpanShrinksIt;
    procedure TestInsertColumnThroughAHorizontalSpanWidensIt;
    procedure TestAColumnDeletedThroughASpanShrinksIt;
    procedure TestDistributeColumnsGoesByTheGrid;
    procedure TestACopyOfCellsKeepsItsSpans;
    procedure TestAPasteIntoCellsGoesByTheGrid;
    procedure TestABookmarkIsNeverThereTwice;
    procedure TestSelectColumnTakesASpanWhole;
    procedure TestEveryRewrittenCellSaysItsOwnWidth;
    procedure TestARandomWalkKeepsTheGridWhole;
  end;

implementation

{ ---- the control ---- }

function TMergeRich.CreateDevice: TTyRichTextDevice;
begin
  Result := TTyRichTestDevice.Create;
end;

procedure TMergeRich.WriteClipboard(const ARtf: RawByteString; const AText: string);
begin
  ClipRtf := ARtf;
  ClipText := AText;
end;

function TMergeRich.ClipboardFlavours: TTyRichClipFlavours;
begin
  Result := [];
  if ClipRtf <> '' then Include(Result, rcfRtf);
  if ClipText <> '' then Include(Result, rcfText);
end;

function TMergeRich.ReadClipboardRtf: RawByteString;
begin
  Result := ClipRtf;
end;

function TMergeRich.ReadClipboardText: string;
begin
  Result := ClipText;
end;

procedure TMergeRich.Refused(Sender: TObject; const AReason: string);
begin
  Refusals.Add(AReason);
end;

destructor TMergeRich.Destroy;
begin
  Refusals.Free;
  inherited Destroy;
end;

{ ---- the fixture ---- }

procedure TTyRichMergeTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TMergeRich.Create(nil);
  FRich.Refusals := TStringList.Create;
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 700, 500);
  FRich.OnEditRefused := @FRich.Refused;
end;

procedure TTyRichMergeTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

// 'before', an ARows x ACols table of 'rNcM' (each cell 1440 twips), 'after'
procedure TTyRichMergeTest.MakeTable(ARows, ACols: Integer);
var
  d: TTyRichDocument;
  r, c, f, l: Integer;
begin
  FRich.Lines.Text := 'before' + LineEnding + 'after';
  d := FRich.Document;
  AssertTrue('a table', d.Execute(TTyRichInsertTable.Create(d.Text.ParaStart(1), ARows, ACols,
    1440 * ACols)));
  for r := ARows - 1 downto 0 do
    for c := ACols - 1 downto 0 do
    begin
      d.TableCellParas(1, r, c, f, l);
      d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(f), Format('r%dc%d', [r, c])));
    end;
  d.ClearUndo;
end;

function TTyRichMergeTest.CellStart(ARow, ACol: Integer): TTyRichPos;
var
  f, l: Integer;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  Result := FRich.Document.Text.ParaStart(f);
end;

function TTyRichMergeTest.CellEnd(ARow, ACol: Integer): TTyRichPos;
var
  f, l: Integer;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  Result := FRich.Document.Text.ParaStart(l) + FRich.Document.Text.ParaLength(l) + 1;
end;

// cells (AR0, AC0) .. (AR1, AC1) by their indexes in their rows
procedure TTyRichMergeTest.SelCells(AR0, AC0, AR1, AC1: Integer);
begin
  FRich.SelStart := CellStart(AR0, AC0);
  FRich.SelLength := CellEnd(AR1, AC1) - CellStart(AR0, AC0);
end;

function TTyRichMergeTest.SaveRtf: RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Bytes[0], Result[1], st.Size);
  finally
    st.Free;
  end;
end;

function TTyRichMergeTest.Grid: TTyRichGrid;
begin
  Result := TyRichTableGrid(FRich.Document, FRich.Document.Text.ParaStart(1));
  AssertNotNull('a grid', Result);
end;

// the cell's paragraphs, '|' between them
function TTyRichMergeTest.CellParas(ARow, ACell: Integer): string;
var
  f, l, k: Integer;
  t: TTyRichText;
begin
  Result := '';
  t := FRich.Document.Text;
  AssertTrue('its paragraphs', FRich.Document.TableCellParas(1, ARow, ACell, f, l));
  for k := f to l do
  begin
    if k > f then Result := Result + '|';
    Result := Result + t.GetText(t.ParaStart(k), t.ParaLength(k));
  end;
end;

{ A grid listing's row without the cells' widths (span/vMerge/text). }
function StripWidths(const ALine: string): string;
var
  parts: TStringList;
  i: Integer;
  p: TStringList;
begin
  Result := '';
  parts := TStringList.Create;
  p := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := False;
    parts.DelimitedText := ALine;
    for i := 1 to parts.Count - 1 do
    begin
      p.Delimiter := '/';
      p.StrictDelimiter := True;
      p.DelimitedText := parts[i];
      if p.Count >= 4 then Result := Result + ' ' + p[0] + '/' + p[1] + '/' + p[3];
    end;
  finally
    p.Free;
    parts.Free;
  end;
end;

{ ---- tests ---- }

{ A 2 x 2 block of a 5 x 5 table: the top-left cell takes the others' paragraphs in reading
  order and becomes one cell over two rows and two columns; the cell below it is covered and
  empty; the grid stays whole. }
procedure TTyRichMergeTest.TestMergeJoinsContentInReadingOrder;
var
  g: TTyRichGrid;
begin
  MakeTable(5, 5);
  SelCells(1, 1, 2, 2);
  AssertTrue('may merge', FRich.CanMergeCells);
  AssertTrue('merged', FRich.MergeCells);
  AssertEquals('nothing refused', 0, FRich.Refusals.Count);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  AssertEquals('the content in reading order', 'r1c1|r1c2|r2c1|r2c2', CellParas(1, 1));
  AssertEquals('row 1: four cells', 'r1c3', CellParas(1, 2));
  AssertEquals('row 2: the covered cell, empty', '', CellParas(2, 1));
  AssertEquals('row 2: after it', 'r2c3', CellParas(2, 2));
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('5 columns still', 5, g.ColCount);
    AssertEquals('two rows', 2, g.Cell(1, 1).RowSpan);
    AssertEquals('two columns', 2, g.Cell(1, 1).ColSpan);
    AssertTrue('covered below', g.Cell(2, 2).Covered and (g.Cell(2, 2).Row = 1));
  finally
    g.Free;
  end;
  AssertEquals('the caret at the merged cell', CellStart(1, 1), FRich.SelStart);
end;

procedure TTyRichMergeTest.TestARowAndAColumnMerge;
var
  g: TTyRichGrid;
begin
  MakeTable(5, 5);
  // three of a row: one wide cell
  SelCells(0, 1, 0, 3);
  AssertTrue('a row of three', FRich.MergeCells);
  AssertEquals('its content', 'r0c1|r0c2|r0c3', CellParas(0, 1));
  AssertEquals('then the last cell', 'r0c4', CellParas(0, 2));
  // three of a column: a vertical merge
  SelCells(2, 0, 4, 0);
  AssertTrue('a column of three', FRich.MergeCells);
  AssertEquals('its content', 'r2c0|r3c0|r4c0', CellParas(2, 0));
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('wide', 3, g.Cell(0, 1).ColSpan);
    AssertEquals('one row', 1, g.Cell(0, 1).RowSpan);
    AssertEquals('tall', 3, g.Cell(2, 0).RowSpan);
    AssertEquals('one column', 1, g.Cell(2, 0).ColSpan);
    AssertTrue('the last row''s first place: covered', g.Cell(4, 0).Covered);
  finally
    g.Free;
  end;
  AssertEquals('two steps', 2, FRich.Document.UndoDepth);
end;

procedure TTyRichMergeTest.TestEmptyCellsAddNothing;
begin
  MakeTable(3, 3);
  // the second and the top-left empty: no empty paragraph piles up
  SelCells(0, 0, 0, 0);
  FRich.ClearCells;
  SelCells(0, 1, 0, 1);
  FRich.ClearCells;
  FRich.Document.ClearUndo;
  SelCells(0, 0, 1, 1);
  AssertTrue('merged', FRich.MergeCells);
  AssertEquals('only what was there', 'r1c0|r1c1', CellParas(0, 0));
  // all empty: one empty paragraph
  MakeTable(2, 2);
  SelCells(0, 0, 1, 1);
  FRich.ClearCells;
  SelCells(0, 0, 1, 1);
  AssertTrue('merged too', FRich.MergeCells);
  AssertEquals('one empty paragraph', '', CellParas(0, 0));
end;

{ The merged cell: the top-left cell's shading; its outline the lines the rectangle had - in
  each row its left from the first cell, its right from the last, its top from the top-left,
  its bottom from the bottom-left. }
procedure TTyRichMergeTest.TestTheMergedCellKeepsTheOutline;
var
  p: TTyRichCellProps;
  d: TTyRichDocument;
  tp: TTyRichPos;
  got: TTyRichCellProps;
begin
  MakeTable(3, 3);
  d := FRich.Document;
  tp := d.Text.ParaStart(1);
  p := Default(TTyRichCellProps);
  p.Valid := [rcpShading];
  p.Shading := clYellow;
  AssertTrue('the top-left shaded', d.Execute(TTyRichSetCellProps.Create(tp, 0, 0, 0, 0, p)));
  p.Valid := [rcpBorderRight];
  p.Borders[rcsRight] := TyRichBorder(rbsDouble, 30, clRed);
  AssertTrue('the top-right''s right', d.Execute(TTyRichSetCellProps.Create(tp, 0, 1, 0, 1, p)));
  p.Valid := [rcpBorderBottom];
  p.Borders[rcsBottom] := TyRichBorder(rbsDashed, 20, clBlue);
  AssertTrue('the bottom-left''s bottom', d.Execute(TTyRichSetCellProps.Create(tp, 1, 0, 1, 0, p)));
  d.ClearUndo;
  SelCells(0, 0, 1, 1);
  AssertTrue('merged', FRich.MergeCells);
  got := d.CellProps(tp, 0, 0);
  AssertEquals('the shading', ColorToString(clYellow), ColorToString(got.Shading));
  AssertTrue('its right: the top-right''s', got.Borders[rcsRight].Style = rbsDouble);
  got := d.CellProps(tp, 1, 0);
  AssertTrue('the covered cell''s bottom: the bottom-left''s', got.Borders[rcsBottom].Style = rbsDashed);
  AssertEquals('the covered part shaded alike', ColorToString(clYellow), ColorToString(got.Shading));
end;

procedure TTyRichMergeTest.TestEveryStepIsOneUndoWithBytesBack;
var
  before, after: RawByteString;
begin
  MakeTable(4, 4);
  before := SaveRtf;
  SelCells(1, 1, 2, 3);
  AssertTrue('merged', FRich.MergeCells);
  after := SaveRtf;
  AssertTrue('changed', after <> before);
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  FRich.Redo;
  AssertTrue('redone: the merge''s bytes', SaveRtf = after);
end;

procedure TTyRichMergeTest.TestASavedMergeReadsAsTheSameGrid;
var
  saved: RawByteString;
  d: TTyRichDocument;
  st: TBytesStream;
  a, b: TStringList;
begin
  MakeTable(4, 4);
  SelCells(0, 1, 1, 2);
  AssertTrue('merged', FRich.MergeCells);
  SelCells(2, 0, 2, 3);
  AssertTrue('a row merged', FRich.MergeCells);
  saved := SaveRtf;
  // the vertical merge with the marks, the row's with one wide cell
  AssertTrue('a vertical merge mark', Pos('\clvmgf', saved) > 0);
  AssertTrue('... continued', Pos('\clvmrg', saved) > 0);
  AssertTrue('no horizontal mark', Pos('\clmgf', saved) = 0);
  d := TTyRichDocument.Create;
  st := TBytesStream.Create;
  try
    st.WriteBuffer(saved[1], Length(saved));
    st.Position := 0;
    TyRichLoadRtfFull(d, st);
    a := TyRichGridListing(FRich.Document, FRich.Document.Text.ParaStart(1));
    b := TyRichGridListing(d, d.Text.ParaStart(1));
    try
      AssertEquals('one grid', a.Text, b.Text);
    finally
      a.Free;
      b.Free;
    end;
  finally
    st.Free;
    d.Free;
  end;
end;

{ CanMergeCells answers what MergeCells then does: not with a caret, a text selection, one
  cell, a selection reaching out of the table, read-only, a table holding a nested table;
  yes over two cells or more, also in a table that has merged cells already. }
procedure TTyRichMergeTest.TestCanMergeCellsAnswersWhatTheDoorDoes;
const
  Nested = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx2000\cellx4000\pard\intbl a\cell b\cell\row' +
    '\pard\intbl\itap2 x\nestcell{\*\nesttableprops\trowd\cellx1000\nestrow}\nestcell' +
    '\pard\intbl\itap1 c\cell\trowd\cellx2000\cellx4000\row\pard\par}';
var
  st: TStringStream;

  procedure Both(const AWhat: string; AWant: Boolean);
  var
    depth: Integer;
    got: Boolean;
  begin
    AssertEquals(AWhat + ': CanMergeCells', AWant, FRich.CanMergeCells);
    depth := FRich.Document.UndoDepth;
    got := FRich.MergeCells;
    AssertEquals(AWhat + ': MergeCells', AWant, got);
    if AWant then
    begin
      AssertEquals(AWhat + ': a step', depth + 1, FRich.Document.UndoDepth);
      FRich.Undo;
    end
    else
      AssertEquals(AWhat + ': no step', depth, FRich.Document.UndoDepth);
  end;

begin
  MakeTable(3, 3);
  FRich.SelStart := CellStart(1, 1);
  Both('a caret', False);
  FRich.SelStart := CellStart(1, 1);
  FRich.SelLength := 2;
  Both('text in a cell', False);
  SelCells(1, 1, 1, 1);
  Both('one cell', False);
  FRich.SelStart := 2;
  FRich.SelLength := CellStart(1, 1) + 1 - 2;
  Both('from outside the table', False);
  SelCells(0, 0, 0, 1);
  Both('two cells', True);
  SelCells(0, 0, 1, 1);
  AssertTrue('a merge first', FRich.MergeCells);
  SelCells(0, 1, 2, 1);
  Both('in a merged table, beside the merged cell', True);
  FRich.ReadOnly := True;
  SelCells(2, 1, 2, 2);
  Both('read-only', False);
  FRich.ReadOnly := False;
  st := TStringStream.Create(Nested);
  try
    FRich.LoadFromStream(st, rfRtf);
  finally
    st.Free;
  end;
  FRich.SelStart := 0;
  FRich.SelLength := FRich.Document.Text.ParaStart(1) + 2;
  Both('a table with a nested table', False);
end;

{ A merge split back: the grid's own cells again, the content in the first. One cell split
  into 3 columns and 2 rows: a row comes below it, the row's other cells reach over it. }
procedure TTyRichMergeTest.TestSplitRestoresAndSplitsIntoColsAndRows;
var
  before, merged: RawByteString;
  a, b: TStringList;
  g: TTyRichGrid;
  info: TTyRichTableInfo;
  i: Integer;
begin
  MakeTable(5, 5);
  a := TyRichGridListing(FRich.Document, FRich.Document.Text.ParaStart(1));
  try
    SelCells(1, 1, 2, 2);
    AssertTrue('merged', FRich.MergeCells);
    merged := SaveRtf;
    FRich.SelStart := CellStart(1, 1);
    AssertTrue('may split', FRich.CanSplitCell);
    AssertTrue('split back', FRich.SplitCell(2, 2));
    AssertEquals('the content in the first cell', 'r1c1|r1c2|r2c1|r2c2', CellParas(1, 1));
    AssertEquals('the next one empty', '', CellParas(1, 2));
    AssertEquals('row 2''s back too', '', CellParas(2, 1));
    AssertEquals('and the one after', 'r2c3', CellParas(2, 3));
    b := TyRichGridListing(FRich.Document, FRich.Document.Text.ParaStart(1));
    try
      AssertEquals('the grid''s columns', a[0], b[0]);
      AssertEquals('as many rows', a.Count, b.Count);
    finally
      b.Free;
    end;
    g := Grid;
    try
      AssertTrue('consistent', g.Consistent);
      for i := 0 to 24 do
        AssertTrue(Format('place %d: a cell of its own', [i]), not g.Cell(i div 5, i mod 5).Covered and
          (g.Cell(i div 5, i mod 5).RowSpan = 1) and (g.Cell(i div 5, i mod 5).ColSpan = 1));
    finally
      g.Free;
    end;
    FRich.Undo;
    AssertTrue('undone: the merge''s bytes', SaveRtf = merged);
  finally
    a.Free;
  end;
  // one cell into 3 x 2
  MakeTable(3, 3);
  before := SaveRtf;
  FRich.SelStart := CellStart(0, 0);
  AssertTrue('3 x 2', FRich.SplitCell(3, 2));
  AssertTrue('a row more', FRich.Document.TableInfoAt(1, info) and (info.RowCount = 4));
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('two columns more', 5, g.ColCount);
    AssertEquals('the first part: one place', 1, g.Cell(0, 0).ColSpan * g.Cell(0, 0).RowSpan);
    AssertEquals('the third part: its own row below too', 1, g.Cell(1, 2).RowSpan);
    AssertFalse('... not covered', g.Cell(1, 2).Covered);
    AssertEquals('the row''s other cells reach over the new row', 2, g.Cell(0, 3).RowSpan);
    AssertTrue('covered there', g.Cell(1, 4).Covered and (g.Cell(1, 4).Row = 0));
    AssertEquals('the next row as it was', 1, g.Cell(2, 3).RowSpan);
  finally
    g.Free;
  end;
  AssertEquals('the content stays', 'r0c0', CellParas(0, 0));
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  // a cell whose index is not its row's: the cell named, not another
  MakeTable(3, 3);
  FRich.SelStart := CellStart(0, 2);
  AssertTrue('the last cell of the first row in two', FRich.SplitCell(2, 1));
  AssertEquals('its content stays', 'r0c2', CellParas(0, 2));
  AssertEquals('the new cell after it', '', CellParas(0, 3));
  AssertEquals('the first cell as it was', 'r0c0', CellParas(0, 0));
end;

procedure TTyRichMergeTest.TestASplitThatCannotBeIsRefused;
begin
  MakeTable(4, 3);
  SelCells(0, 0, 2, 0);
  AssertTrue('three rows merged', FRich.MergeCells);
  FRich.SelStart := CellStart(0, 0);
  FRich.Refusals.Clear;
  AssertFalse('2 does not divide 3', FRich.SplitCell(1, 2));
  AssertEquals('told once', 1, FRich.Refusals.Count);
  AssertTrue('3 does', FRich.SplitCell(1, 3));
  FRich.SelStart := CellStart(1, 1);
  FRich.SelLength := 2;
  AssertFalse('a text selection: no', FRich.CanSplitCell);
  FRich.SelStart := CellStart(1, 1);
  FRich.ReadOnly := True;
  AssertFalse('read-only: no', FRich.CanSplitCell);
  AssertFalse('... nor the door', FRich.SplitCell(2, 1));
end;

type
  // a span: its top-left place and size
  TSpan = record
    R, C, RS, CS: Integer;
  end;

{ A 5 x 5 table of 1440-twip columns by the builder, a cell's text 'rNcM' at every place that
  starts a cell - with ASpans as the builder's spans (AWithSpans), else as plain cells (the
  places a span would cover empty). }
procedure BuildFive(R: TTyRichEdit; const ASpans: array of TSpan; AWithSpans: Boolean);
var
  B: TTyRichBuilder;
  rr, cc, k: Integer;
  covered, start: Boolean;
  sp: TSpan;
begin
  B := TTyRichBuilder.Create;
  try
    B.Text('before');
    B.Table([1440, 1440, 1440, 1440, 1440]);
    for rr := 0 to 4 do
    begin
      if rr > 0 then B.Row;
      for cc := 0 to 4 do
      begin
        covered := False;
        start := False;
        sp := Default(TSpan);
        for k := 0 to High(ASpans) do
          if (rr >= ASpans[k].R) and (rr < ASpans[k].R + ASpans[k].RS) and (cc >= ASpans[k].C) and
             (cc < ASpans[k].C + ASpans[k].CS) then
          begin
            if (rr = ASpans[k].R) and (cc = ASpans[k].C) then
            begin
              start := True;
              sp := ASpans[k];
            end
            else
              covered := True;
          end;
        if covered then
        begin
          // (the builder makes the places a span covers itself)
          if not AWithSpans then B.Cell;
        end
        else if start and AWithSpans then
          B.Cell(sp.CS, sp.RS).Text(Format('r%dc%d', [rr, cc]))
        else
          B.Cell.Text(Format('r%dc%d', [rr, cc]));
      end;
    end;
    B.EndTable.Text('after');
    R.SetContent(B);
  finally
    B.Free;
  end;
end;

function Span(AR, AC, ARS, ACS: Integer): TSpan;
begin
  Result.R := AR;
  Result.C := AC;
  Result.RS := ARS;
  Result.CS := ACS;
end;

{ The same table made by the builder's spans and by MergeCells over the builder's plain
  cells: the same file - a 2 x 2 block, a row of three, a column of three, and all three. }
procedure TTyRichMergeTest.TestTheBuildersSpansAreMergeCellsOwn;
var
  cases: array of array of TSpan;
  i, k: Integer;
  built, merged: RawByteString;
begin
  SetLength(cases, 4);
  cases[0] := [Span(1, 1, 2, 2)];
  cases[1] := [Span(0, 1, 1, 3)];
  cases[2] := [Span(2, 0, 3, 1)];
  cases[3] := [Span(1, 1, 2, 2), Span(0, 1, 1, 3), Span(2, 0, 3, 1)];
  for i := 0 to High(cases) do
  begin
    BuildFive(FRich, cases[i], True);
    built := SaveRtf;
    BuildFive(FRich, cases[i], False);
    for k := 0 to High(cases[i]) do
    begin
      with cases[i][k] do SelCells(R, C, R + RS - 1, C + CS - 1);
      // (a cell's index in its row: after a merge in the row before it, fewer cells)
      AssertTrue(Format('case %d: merged %d', [i, k]), FRich.MergeCells);
    end;
    merged := SaveRtf;
    AssertTrue(Format('case %d: the same file', [i]), built = merged);
  end;
end;

procedure TTyRichMergeTest.TestTheBuildersSpanMisuseRaises;

  procedure Expect(ACase: Integer; const ACall: string);
  var
    B: TTyRichBuilder;
    ok: Boolean;
  begin
    B := TTyRichBuilder.Create;
    try
      ok := False;
      try
        B.Table([1000, 1000, 1000]);
        case ACase of
          0: B.Cell(0);
          1: B.Cell(4);
          2: B.Cell.Cell(1, 2).Cell.Row.Cell(2, 1);
          3: B.Cell(1, 3).Cell.Cell.Row.Cell.Cell.EndTable;
        end;
      except
        on E: Exception do ok := Pos(ACall, E.Message) > 0;
      end;
      AssertTrue(Format('case %d raises, naming %s', [ACase, ACall]), ok);
    finally
      B.Free;
    end;
  end;

begin
  Expect(0, 'Cell');
  Expect(1, 'Cell');
  Expect(2, 'Cell');
  Expect(3, 'EndTable');
end;

function FixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim + 'fixtures' +
    PathDelim + 'rtf' + PathDelim;
end;

function FixtureRaw: RawByteString;
var
  f: TFileStream;
begin
  Result := '';
  f := TFileStream.Create(FixtureDir + 'word-table-styled.rtf', fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[1], f.Size);
  finally
    f.Free;
  end;
end;

{ The files a person opens in Word to compare its grid with ours: each case saved, read again
  as the same grid, and - with TY_RICH_WORD_DIR set - written there with its grid listing
  (TyRichGridListing, from the model: the table the listing's first line names). }
procedure TTyRichMergeTest.TestWordReadsWhatWeWrite;
var
  dir: string;
  n: Integer;

  // the table at ATable (0: the first) of the control's document: saved, read, compared, written
  procedure Keep(const AName: string; ATable: Integer);
  var
    saved: RawByteString;
    d: TTyRichDocument;
    st: TBytesStream;
    a, b: TStringList;
    fs: TFileStream;
    k, tp: Integer;
    t: TTyRichTable;
  begin
    saved := SaveRtf;
    // the paragraph the table starts at
    tp := -1;
    k := 0;
    t := nil;
    while k < FRich.Document.Text.ParaCount do
    begin
      if (FRich.Document.TableAt(k) <> nil) and (FRich.Document.TableAt(k) <> t) and
         ((k = 0) or (FRich.Document.CellAt(k - 1) = nil)) then
      begin
        if ATable = 0 then
        begin
          tp := k;
          Break;
        end;
        Dec(ATable);
      end;
      t := FRich.Document.TableAt(k);
      Inc(k);
    end;
    AssertTrue(AName + ': the table', tp >= 0);
    d := TTyRichDocument.Create;
    st := TBytesStream.Create;
    try
      st.WriteBuffer(saved[1], Length(saved));
      st.Position := 0;
      TyRichLoadRtfFull(d, st);
      a := TyRichGridListing(FRich.Document, FRich.Document.Text.ParaStart(tp));
      b := TyRichGridListing(d, d.Text.ParaStart(tp));
      try
        AssertEquals(AName + ': read again, the same grid', a.Text, b.Text);
        if dir <> '' then
        begin
          fs := TFileStream.Create(dir + AName + '.rtf', fmCreate);
          try
            fs.WriteBuffer(saved[1], Length(saved));
          finally
            fs.Free;
          end;
          a.Insert(0, Format('# %s.rtf, the table starting at paragraph %d, from the model', [AName, tp]));
          a.SaveToFile(dir + AName + '.grid.txt');
        end;
      finally
        a.Free;
        b.Free;
      end;
    finally
      st.Free;
      d.Free;
    end;
    Inc(n);
  end;

  procedure LoadFixture;
  var
    st: TFileStream;
  begin
    st := TFileStream.Create(FixtureDir + 'word-table-styled.rtf', fmOpenRead or fmShareDenyWrite);
    try
      FRich.LoadFromStream(st, rfRtf);
    finally
      st.Free;
    end;
    FRich.FinishLoading;
  end;

  // row ARow, cell ACell of the second table
  function Cell2(ARow, ACell: Integer): TTyRichPos;
  var
    f, l, k, seen: Integer;
    t: TTyRichTable;
  begin
    k := 0;
    seen := 0;
    t := nil;
    while k < FRich.Document.Text.ParaCount do
    begin
      if (FRich.Document.TableAt(k) <> nil) and (FRich.Document.TableAt(k) <> t) and
         ((k = 0) or (FRich.Document.CellAt(k - 1) = nil)) then
      begin
        Inc(seen);
        if seen = 2 then Break;
      end;
      t := FRich.Document.TableAt(k);
      Inc(k);
    end;
    AssertTrue('the second table''s cell', FRich.Document.TableCellParas(k, ARow, ACell, f, l));
    Result := FRich.Document.Text.ParaStart(f);
  end;

  procedure Sel2(AR0, AC0, AR1, AC1: Integer);
  var
    f, l, k: Integer;
  begin
    FRich.SelStart := Cell2(AR0, AC0);
    k := FRich.Document.Text.ParaOfPos(Cell2(AR1, AC1));
    AssertTrue('its last cell', TyRichCellParasOf(FRich.Document, k, f, l));
    FRich.SelLength := FRich.Document.Text.ParaStart(l) + FRich.Document.Text.ParaLength(l) + 1 -
      FRich.SelStart;
  end;

begin
  dir := GetEnvironmentVariable('TY_RICH_WORD_DIR');
  if dir <> '' then dir := IncludeTrailingPathDelimiter(dir);
  n := 0;
  // a new 5 x 5 table through the doors
  MakeTable(5, 5);
  SelCells(1, 1, 2, 2);
  AssertTrue(FRich.MergeCells);
  Keep('doors-2x2-merged', 0);
  MakeTable(5, 5);
  SelCells(0, 1, 0, 3);
  AssertTrue(FRich.MergeCells);
  Keep('doors-row-of-three', 0);
  MakeTable(5, 5);
  SelCells(1, 0, 3, 0);
  AssertTrue(FRich.MergeCells);
  Keep('doors-column-of-three', 0);
  MakeTable(5, 5);
  SelCells(1, 1, 2, 2);
  AssertTrue(FRich.MergeCells);
  FRich.SelStart := CellStart(1, 1);
  AssertTrue(FRich.SplitCell(2, 2));
  Keep('doors-merged-and-split-back', 0);
  MakeTable(5, 5);
  FRich.SelStart := CellStart(2, 2);
  AssertTrue(FRich.SplitCell(3, 2));
  Keep('doors-one-cell-3x2', 0);
  // Word's merged table (the second of the file)
  LoadFixture;
  Keep('word-unchanged', 1);
  AssertTrue('Word''s file unchanged: its bytes', SaveRtf = FixtureRaw);
  LoadFixture;
  FRich.SelStart := Cell2(2, 2);
  AssertTrue('Word''s 2 x 2 split back', FRich.SplitCell(2, 2));
  Keep('word-2x2-split-back', 1);
  LoadFixture;
  Sel2(0, 0, 0, 1);
  AssertTrue('Word''s first-row span with the cell beside it', FRich.MergeCells);
  Keep('word-first-row-merged-on', 1);
  LoadFixture;
  FRich.SelStart := Cell2(0, 1);
  AssertTrue('Word''s: a column deleted through its spans', FRich.DeleteColumn);
  Keep('word-column-deleted-through-spans', 1);
  // the edits of rows and columns through spans, on a new 5 x 5 table
  MakeTable(5, 5);
  SelCells(1, 1, 1, 2);
  AssertTrue(FRich.MergeCells);
  FRich.SelStart := CellStart(0, 1);
  AssertTrue(FRich.InsertColumn(True));
  Keep('doors-column-inserted-through-a-span', 0);
  MakeTable(5, 5);
  SelCells(1, 1, 3, 1);
  AssertTrue(FRich.MergeCells);
  FRich.SelStart := CellStart(1, 0);
  AssertTrue(FRich.DeleteRow);
  Keep('doors-first-row-of-a-span-deleted', 0);
  MakeTable(5, 5);
  SelCells(1, 1, 3, 1);
  AssertTrue(FRich.MergeCells);
  FRich.SelStart := CellStart(1, 0);
  AssertTrue(FRich.InsertRow(True));
  Keep('doors-row-inserted-inside-a-span', 0);
  // a copy of cells with their spans, pasted as a table of its own
  MakeTable(4, 4);
  SelCells(1, 1, 2, 2);
  AssertTrue(FRich.MergeCells);
  SelCells(0, 1, 1, 0);
  // (a part of the table: rows 1 .. 3, columns 0 .. 2)
  SelCells(1, 0, 3, 2);
  FRich.CopyToClipboard;
  FRich.Lines.Text := '';
  FRich.ClipText := '';
  FRich.PasteFromClipboard;
  Keep('copy-of-cells-with-spans', 0);
  // the builder's spans: the same files as the doors' merges over the builder's cells
  BuildFive(FRich, [Span(1, 1, 2, 2)], True);
  Keep('builder-2x2-merged', 0);
  BuildFive(FRich, [Span(0, 1, 1, 3)], True);
  Keep('builder-row-of-three', 0);
  BuildFive(FRich, [Span(1, 0, 3, 1)], True);
  Keep('builder-column-of-three', 0);
  AssertEquals('every case', 16, n);
end;

{ The command alone merges only cells that are empty but the first (the door moves their
  content first): with text in a cell that would go, refused, nothing changed. }
procedure TTyRichMergeTest.TestTheCommandRefusesCellsNotEmpty;
var
  d: TTyRichDocument;
  before: RawByteString;
begin
  MakeTable(3, 3);
  d := FRich.Document;
  before := SaveRtf;
  AssertTrue('refused: not empty', TTyRichMergeCells.Create(d.Text.ParaStart(1), 0, 0, 0, 2880).Refusal(d) =
    rtrNotEmpty);
  AssertFalse('the command does nothing', d.Execute(TTyRichMergeCells.Create(d.Text.ParaStart(1), 0, 0, 0, 2880)));
  AssertTrue('the bytes as they were', SaveRtf = before);
end;

{ A cell over four rows split into two down: two cells over two rows each. }
procedure TTyRichMergeTest.TestASpanSplitIntoPartsOfItsRows;
var
  g: TTyRichGrid;
begin
  MakeTable(5, 2);
  SelCells(0, 0, 3, 0);
  AssertTrue('a span over four rows', FRich.MergeCells);
  FRich.SelStart := CellStart(0, 0);
  AssertTrue('into two', FRich.SplitCell(1, 2));
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('the first part over two rows', 2, g.Cell(0, 0).RowSpan);
    AssertEquals('the second starts at row 2', 2, g.Cell(2, 0).Row);
    AssertFalse('... its own', g.Cell(2, 0).Covered);
    AssertEquals('... over two rows', 2, g.Cell(2, 0).RowSpan);
  finally
    g.Free;
  end;
end;

{ Merged cells - a file's or merged here - forbid no structure edit; a nested table forbids
  them all, told with its reason. }
procedure TTyRichMergeTest.TestTheTableStillLocksOnlyForNestedTables;
var
  st: TFileStream;
begin
  MakeTable(4, 3);
  SelCells(1, 1, 2, 1);
  AssertTrue('merged down', FRich.MergeCells);
  FRich.SelStart := CellStart(0, 0);
  AssertTrue('a row inserted', FRich.CanInsertRow);
  AssertTrue('a row deleted', FRich.CanDeleteRow);
  AssertTrue('a column inserted', FRich.CanInsertColumn);
  AssertTrue('a column deleted', FRich.CanDeleteColumn);
  FRich.SelStart := CellStart(1, 1);
  AssertTrue('split: yes', FRich.CanSplitCell);
  st := TFileStream.Create(FixtureDir + 'word-table-merged.rtf', fmOpenRead or fmShareDenyWrite);
  try
    FRich.LoadFromStream(st, rfRtf);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.SelStart := FRich.Document.Text.ParaStart(1);
  AssertFalse('nested: no row', FRich.CanInsertRow);
  AssertFalse('nested: no column', FRich.CanInsertColumn);
  FRich.Refusals.Clear;
  AssertFalse('nested: the door', FRich.InsertRow(True));
  AssertEquals('told once', 1, FRich.Refusals.Count);
end;

{ A table with a cell over three rows: a row put in inside the span makes it four rows (the new
  row's cell there covered); one below the span's last row or above its first is a row of its
  own cells. One undo step each, the bytes back. }
procedure TTyRichMergeTest.TestARowInsertedInsideAVerticalSpanWidensIt;
var
  g: TTyRichGrid;
  before: RawByteString;
begin
  MakeTable(5, 3);
  SelCells(1, 1, 3, 1);
  AssertTrue('a span over rows 1 .. 3', FRich.MergeCells);
  FRich.Document.ClearUndo;
  before := SaveRtf;
  FRich.SelStart := CellStart(1, 0);
  AssertTrue('may insert', FRich.CanInsertRow);
  AssertTrue('a row below row 1: inside', FRich.InsertRow(True));
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('6 rows', 6, g.RowCount);
    AssertEquals('the span over four rows', 4, g.Cell(1, 1).RowSpan);
    AssertTrue('the new row''s place covered', g.Cell(2, 1).Covered);
    AssertFalse('its other cells its own', g.Cell(2, 0).Covered);
  finally
    g.Free;
  end;
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  // below the span's last row: outside it
  FRich.SelStart := CellStart(3, 0);
  AssertTrue('a row below row 3', FRich.InsertRow(True));
  g := Grid;
  try
    AssertEquals('the span as it was', 3, g.Cell(1, 1).RowSpan);
    AssertFalse('the new row''s cell its own', g.Cell(4, 1).Covered);
    AssertTrue('consistent', g.Consistent);
  finally
    g.Free;
  end;
  FRich.Undo;
  // above the span's first row
  FRich.SelStart := CellStart(1, 0);
  AssertTrue('a row above row 1', FRich.InsertRow(False));
  g := Grid;
  try
    AssertEquals('the span moved down, as it was', 3, g.Cell(2, 1).RowSpan);
    AssertFalse('the new row''s cell its own', g.Cell(1, 1).Covered);
    AssertEquals('... over one row', 1, g.Cell(1, 1).RowSpan);
  finally
    g.Free;
  end;
  FRich.Undo;
  AssertTrue('all undone: the bytes', SaveRtf = before);
end;

{ The first row of a span over three rows deleted: the span's content goes down to the next
  row, which begins the span now (over two rows). Undone: the bytes back. }
procedure TTyRichMergeTest.TestDeleteTheFirstRowOfAVerticalSpanMovesContentDown;
var
  g: TTyRichGrid;
  before: RawByteString;
begin
  MakeTable(4, 3);
  SelCells(0, 1, 2, 1);
  AssertTrue('a span over rows 0 .. 2', FRich.MergeCells);
  FRich.Document.ClearUndo;
  before := SaveRtf;
  // (the command alone: the merge's content would go with the row - refused)
  AssertTrue('the command alone: refused', TTyRichDeleteRow.Create(CellStart(0, 0), 0).Refusal(
    FRich.Document) = rtrNotEmpty);
  FRich.SelStart := CellStart(0, 0);
  AssertTrue('may delete', FRich.CanDeleteRow);
  AssertTrue('the first row deleted', FRich.DeleteRow);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  AssertEquals('the next row begins the merge (rcmFirst)', 1, TyRichCellVMerge(
    FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(CellStart(0, 1))).Row, 1));
  AssertEquals('the content moved down', 'r0c1|r1c1|r2c1', CellParas(0, 1));
  AssertEquals('the row''s own cell went', 'r1c0', CellParas(0, 0));
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('3 rows', 3, g.RowCount);
    AssertEquals('the span over two rows', 2, g.Cell(0, 1).RowSpan);
    AssertTrue('covered below', g.Cell(1, 1).Covered);
  finally
    g.Free;
  end;
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
end;

{ A row inside a span deleted: the span shrinks; the last row of a span over two: the first is
  an ordinary cell again (no mark written). }
procedure TTyRichMergeTest.TestARowDeletedInsideOrAtTheEndOfASpanShrinksIt;
var
  g: TTyRichGrid;
begin
  MakeTable(5, 3);
  SelCells(1, 1, 3, 1);
  AssertTrue('a span over rows 1 .. 3', FRich.MergeCells);
  FRich.SelStart := CellStart(2, 0);
  AssertTrue('a row inside deleted', FRich.DeleteRow);
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('the span over two rows', 2, g.Cell(1, 1).RowSpan);
  finally
    g.Free;
  end;
  FRich.SelStart := CellStart(2, 0);
  AssertTrue('its last row deleted', FRich.DeleteRow);
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('one row', 1, g.Cell(1, 1).RowSpan);
  finally
    g.Free;
  end;
  AssertEquals('no mark left (rcmNone)', 0, TyRichCellVMerge(FRich.Document.CellAt(
    FRich.Document.Text.ParaOfPos(CellStart(1, 1))).Row, 1));
  AssertTrue('none written', Pos('\clvmgf', SaveRtf) = 0);
end;

{ A column put in at an edge a span crosses: the span grows by it, the other rows get a cell. }
procedure TTyRichMergeTest.TestInsertColumnThroughAHorizontalSpanWidensIt;
var
  g: TTyRichGrid;
  before: RawByteString;
begin
  MakeTable(4, 4);
  SelCells(1, 1, 1, 2);
  AssertTrue('a wide cell in row 1', FRich.MergeCells);
  FRich.Document.ClearUndo;
  before := SaveRtf;
  FRich.SelStart := CellStart(0, 1);
  AssertTrue('may insert', FRich.CanInsertColumn);
  AssertTrue('a column right of column 1', FRich.InsertColumn(True));
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('5 columns', 5, g.ColCount);
    AssertEquals('the span over three', 3, g.CellOf(1, 1).ColSpan);
    AssertEquals('its content', 'r1c1|r1c2', CellParas(1, 1));
    AssertEquals('row 0: a new cell', '', CellParas(0, 2));
    AssertEquals('row 0: the next moved', 'r0c2', CellParas(0, 3));
  finally
    g.Free;
  end;
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
end;

{ A column deleted through a span: the cells wholly inside go, the span keeps its content,
  one column narrower. }
procedure TTyRichMergeTest.TestAColumnDeletedThroughASpanShrinksIt;
var
  g: TTyRichGrid;
  before: RawByteString;
begin
  MakeTable(4, 4);
  SelCells(1, 1, 2, 2);
  AssertTrue('a 2 x 2 span', FRich.MergeCells);
  FRich.Document.ClearUndo;
  before := SaveRtf;
  FRich.SelStart := CellStart(0, 2);
  AssertTrue('may delete', FRich.CanDeleteColumn);
  AssertTrue('column 2 deleted', FRich.DeleteColumn);
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('3 columns', 3, g.ColCount);
    AssertEquals('the span one column', 1, g.Cell(1, 1).ColSpan);
    AssertEquals('... over two rows still', 2, g.Cell(1, 1).RowSpan);
    AssertEquals('its content', 'r1c1|r1c2|r2c1|r2c2', CellParas(1, 1));
    AssertEquals('row 0: column 3 came left', 'r0c3', CellParas(0, 2));
  finally
    g.Free;
  end;
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  // the span's first column deleted: it starts there and reaches out - it stays, narrower
  FRich.SelStart := CellStart(0, 1);
  AssertTrue('column 1 deleted', FRich.DeleteColumn);
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('3 columns', 3, g.ColCount);
    AssertEquals('the span one column', 1, g.Cell(1, 1).ColSpan);
    AssertEquals('its content kept', 'r1c1|r1c2|r2c1|r2c2', CellParas(1, 1));
  finally
    g.Free;
  end;
  FRich.Undo;
  AssertTrue('undone again: the bytes', SaveRtf = before);
end;

{ A table that is no plain grid: its grid's columns made as wide as each other, every cell
  keeping the grid's columns it covered. }
procedure TTyRichMergeTest.TestDistributeColumnsGoesByTheGrid;
const
  Wide = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\cellx1000\cellx3000\cellx6000\pard\intbl A\cell B\cell C\cell\row' +
    '\trowd\cellx1000\cellx6000\pard\intbl D\cell E\cell\row' +
    '\pard\par}';
var
  st: TStringStream;
  e: TTyRichEdges;
begin
  st := TStringStream.Create(Wide);
  try
    FRich.LoadFromStream(st, rfRtf);
  finally
    st.Free;
  end;
  FRich.SelStart := FRich.Document.Text.ParaStart(1);
  AssertTrue('distributed', FRich.DistributeColumns);
  e := FRich.Document.CellAt(1).Row.CellEdges;
  AssertEquals('the first row: 2000', 2000, e[0]);
  AssertEquals('... 4000', 4000, e[1]);
  AssertEquals('... 6000', 6000, e[2]);
  e := FRich.Document.CellAt(4).Row.CellEdges;
  AssertEquals('the wide cell''s row: 2000', 2000, e[0]);
  AssertEquals('... the wide cell still over two', 6000, e[1]);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
end;

{ A copy of cells with a span holds the span: read back, the same grid. }
procedure TTyRichMergeTest.TestACopyOfCellsKeepsItsSpans;
var
  a, b: TStringList;
  d: TTyRichDocument;
  st: TBytesStream;
  k: Integer;
begin
  MakeTable(4, 4);
  SelCells(1, 1, 2, 2);
  AssertTrue('merged', FRich.MergeCells);
  // (a part of the table: a whole table is copied as text, its spans with it)
  SelCells(1, 0, 3, 2);
  FRich.CopyToClipboard;
  d := TTyRichDocument.Create;
  st := TBytesStream.Create;
  try
    st.WriteBuffer(FRich.ClipRtf[1], Length(FRich.ClipRtf));
    st.Position := 0;
    TyRichLoadRtfFull(d, st);
    k := 0;
    while (k < d.Text.ParaCount) and (d.CellAt(k) = nil) do Inc(k);
    a := TyRichGridListing(FRich.Document, FRich.Document.Text.ParaStart(1));
    b := TyRichGridListing(d, d.Text.ParaStart(k));
    try
      // (rows 1 .. 3, columns 0 .. 2: the span whole in it)
      AssertEquals('three rows', 4, b.Count);
      AssertTrue('the span begins: ' + b[1], Pos('  2/restart/', b[1]) > 0);
      AssertTrue('... with its content: ' + b[1], Pos('r1c1r1c2r2c1r2c2', b[1]) > 0);
      AssertTrue('the span goes on: ' + b[2], Pos('  2/cont/', b[2]) > 0);
      AssertTrue('the last row its own: ' + b[3], Pos('restart', b[3] + b[3]) + Pos('cont', b[3]) = 0);
      AssertTrue('the source as listed', a.Count = 5);
    finally
      a.Free;
      b.Free;
    end;
  finally
    st.Free;
    d.Free;
  end;
end;

{ A paste into cells: row by row, the k-th cell of the source row into the k-th cell of the
  row that no merge covers, from the rectangle's left; a covered place is never filled. }
procedure TTyRichMergeTest.TestAPasteIntoCellsGoesByTheGrid;
var
  g: TTyRichGrid;
begin
  MakeTable(4, 4);
  SelCells(1, 1, 2, 1);
  AssertTrue('a span over rows 1 .. 2', FRich.MergeCells);
  FRich.ClipRtf := '';
  FRich.ClipText := 'x1' + #9 + 'x2' + #9 + 'x3' + #13#10 + 'y1' + #9 + 'y2' + #9 + 'y3' + #13#10;
  FRich.SelStart := CellStart(1, 0);
  FRich.PasteFromClipboard;
  AssertEquals('row 1: x1', 'x1', CellParas(1, 0));
  AssertEquals('row 1: x2 in the span', 'x2', CellParas(1, 1));
  AssertEquals('row 1: x3', 'x3', CellParas(1, 2));
  AssertEquals('row 2: y1', 'y1', CellParas(2, 0));
  AssertEquals('row 2: the covered place stays empty', '', CellParas(2, 1));
  AssertEquals('row 2: y2 past it', 'y2', CellParas(2, 2));
  AssertEquals('row 2: y3', 'y3', CellParas(2, 3));
  g := Grid;
  try
    AssertTrue('consistent', g.Consistent);
    AssertEquals('the span as it was', 2, g.Cell(1, 1).RowSpan);
  finally
    g.Free;
  end;
end;

{ After a merge and a row deleted out of a span, every bookmark there is once, at its text. }
procedure TTyRichMergeTest.TestABookmarkIsNeverThereTwice;
var
  a, z: TTyRichPos;

  procedure Mark(ARow, ACol: Integer; const AName: string);
  begin
    FRich.SelStart := CellStart(ARow, ACol);
    FRich.SelLength := 4;
    AssertTrue(AName, FRich.AddBookmark(AName));
  end;

begin
  MakeTable(4, 3);
  Mark(0, 1, 'emptied');
  Mark(1, 0, 'covered');
  Mark(1, 1, 'kept');
  // a merge across that empties (0, 1) and down over row 1, whose first cell stays covered
  SelCells(0, 0, 1, 1);
  AssertTrue('merged', FRich.MergeCells);
  AssertEquals('three bookmarks, once each', 3, FRich.BookmarkCount);
  AssertTrue('emptied: at its text', FRich.FindBookmark('emptied', a, z) and
    (Pos('r0c1', FRich.Document.Text.GetText(a, z - a)) > 0) and (z - a <= 6));
  AssertTrue('covered: at its text', FRich.FindBookmark('covered', a, z) and
    (Pos('r1c0', FRich.Document.Text.GetText(a, z - a)) > 0) and (z - a <= 6));
  // the span's first row deleted: its content - and the bookmarks - go down
  // (row 0: the merged cell and the one after it)
  FRich.SelStart := CellStart(0, 1);
  AssertTrue('the first row deleted', FRich.DeleteRow);
  AssertEquals('still once each', 3, FRich.BookmarkCount);
  AssertTrue('kept: at its text', FRich.FindBookmark('kept', a, z) and
    (Pos('r1c1', FRich.Document.Text.GetText(a, z - a)) > 0) and (z - a <= 6));
  FRich.Undo;
  FRich.Undo;
  AssertEquals('undone: once each', 3, FRich.BookmarkCount);
end;

{ SelectColumn in a table with a span: the grid's column, grown to hold the span whole. }
procedure TTyRichMergeTest.TestSelectColumnTakesASpanWhole;
begin
  MakeTable(4, 4);
  SelCells(1, 1, 1, 2);
  AssertTrue('a wide cell in row 1', FRich.MergeCells);
  FRich.SelStart := CellStart(0, 1);
  AssertTrue('a column', FRich.SelectColumn);
  AssertEquals('every row', 0, FRich.SelectedCells.Row0);
  AssertEquals('every row: the last', 3, FRich.SelectedCells.Row1);
  AssertTrue('cleared', FRich.ClearCells);
  AssertEquals('column 1 cleared', '', CellParas(0, 1));
  AssertEquals('the span''s other column too (grown)', '', CellParas(0, 2));
  AssertEquals('column 3 not', 'r0c3', CellParas(0, 3));
end;

{ Every cell of a row the model writes says its own width in Word's preferred width (in
  twips): after a merge, a split back, a column put in through a span and one deleted, on Word's
  merged table. }
procedure TTyRichMergeTest.TestEveryRewrittenCellSaysItsOwnWidth;
var
  checked: Integer;

  procedure CheckWidths(const AWhat: string);
  var
    f: RawByteString;
    i, k, left, prev, w, x, fts: Integer;
    word: string;
    num: Integer;
    neg: Boolean;
  begin
    f := SaveRtf;
    i := 1;
    left := 0;
    prev := 0;
    w := -1;
    fts := -1;
    while i <= Length(f) do
    begin
      if f[i] <> '\' then
      begin
        Inc(i);
        Continue;
      end;
      k := i + 1;
      while (k <= Length(f)) and (f[k] in ['a'..'z', 'A'..'Z']) do Inc(k);
      word := Copy(f, i + 1, k - i - 1);
      neg := (k <= Length(f)) and (f[k] = '-');
      if neg then Inc(k);
      num := 0;
      x := k;
      while (k <= Length(f)) and (f[k] in ['0'..'9']) do
      begin
        num := num * 10 + Ord(f[k]) - Ord('0');
        Inc(k);
      end;
      if neg then num := -num;
      if word = 'trowd' then
      begin
        left := 0;
        prev := 0;
        w := -1;
        fts := -1;
      end
      else if (word = 'trleft') and (k > x) then
      begin
        left := num;
        prev := num;
      end
      else if word = 'clftsWidth' then fts := num
      else if (word = 'clwWidth') and (k > x) then w := num
      else if (word = 'cellx') and (k > x) then
      begin
        if (fts = 3) and (w >= 0) then
        begin
          AssertEquals(Format('%s: a cell at %d says its width', [AWhat, num]), num - prev, w);
          Inc(checked);
        end;
        prev := num;
        w := -1;
        fts := -1;
      end;
      i := k;
    end;
  end;

  procedure LoadWord;
  var
    st: TFileStream;
  begin
    st := TFileStream.Create(FixtureDir + 'word-table-styled.rtf', fmOpenRead or fmShareDenyWrite);
    try
      FRich.LoadFromStream(st, rfRtf);
    finally
      st.Free;
    end;
    FRich.FinishLoading;
  end;

  function SecondTablePara: Integer;
  var
    k, seen: Integer;
    t: TTyRichTable;
  begin
    k := 0;
    seen := 0;
    t := nil;
    while k < FRich.Document.Text.ParaCount do
    begin
      if (FRich.Document.TableAt(k) <> nil) and (FRich.Document.TableAt(k) <> t) and
         ((k = 0) or (FRich.Document.CellAt(k - 1) = nil)) then
      begin
        Inc(seen);
        if seen = 2 then Exit(k);
      end;
      t := FRich.Document.TableAt(k);
      Inc(k);
    end;
    Result := -1;
  end;

  function C2(ARow, ACell: Integer): TTyRichPos;
  var
    f, l: Integer;
  begin
    AssertTrue('the cell', FRich.Document.TableCellParas(SecondTablePara, ARow, ACell, f, l));
    Result := FRich.Document.Text.ParaStart(f);
  end;

  procedure Sel2(AR0, AC0, AR1, AC1: Integer);
  var
    f, l: Integer;
  begin
    FRich.SelStart := C2(AR0, AC0);
    AssertTrue('the cell', FRich.Document.TableCellParas(SecondTablePara, AR1, AC1, f, l));
    FRich.SelLength := FRich.Document.Text.ParaStart(l) + FRich.Document.Text.ParaLength(l) + 1 -
      FRich.SelStart;
  end;

begin
  checked := 0;
  LoadWord;
  CheckWidths('as read');
  AssertTrue('widths were read', checked > 20);
  Sel2(0, 0, 0, 1);
  AssertTrue('merged', FRich.MergeCells);
  CheckWidths('merge');
  LoadWord;
  FRich.SelStart := C2(2, 2);
  AssertTrue('split back', FRich.SplitCell(2, 2));
  CheckWidths('split back');
  LoadWord;
  FRich.SelStart := C2(1, 1);
  AssertTrue('split in three', FRich.SplitCell(3, 1));
  CheckWidths('split in equal parts');
  LoadWord;
  FRich.SelStart := C2(1, 0);
  AssertTrue('a column put in', FRich.InsertColumn(True));
  CheckWidths('a column put in');
  LoadWord;
  FRich.SelStart := C2(1, 1);
  AssertTrue('a column deleted', FRich.DeleteColumn);
  CheckWidths('a column deleted');
end;

{ Merges, splits, rows and columns in and out, undo and redo, at random (a fixed seed): the
  grid whole after every step, the file read back as the same grid every few steps, and every
  step undone: the first bytes. }
procedure TTyRichMergeTest.TestARandomWalkKeepsTheGridWhole;
var
  first, saved: RawByteString;
  step, op, r0, r1, c0, c1, n: Integer;
  g: TTyRichGrid;
  d: TTyRichDocument;
  st: TBytesStream;
  a, b: TStringList;
  info: TTyRichTableInfo;

  function Rows: Integer;
  begin
    AssertTrue('the table', FRich.Document.TableInfoAt(1, info));
    Result := info.RowCount;
  end;

  function CellsOf(ARow: Integer): Integer;
  var
    f, l: Integer;
  begin
    Result := 0;
    while FRich.Document.TableCellParas(1, ARow, Result, f, l) do Inc(Result);
  end;

begin
  MakeTable(6, 5);
  first := SaveRtf;
  RandSeed := 20261125;
  for step := 1 to 60 do
  begin
    op := Random(9);
    r0 := Random(Rows);
    c0 := Random(Math.Max(1, CellsOf(r0)));
    case op of
      0, 1:
        begin
          r1 := Math.Min(Rows - 1, r0 + Random(2));
          c1 := Math.Min(CellsOf(r1) - 1, c0 + Random(2));
          if c1 < 0 then c1 := 0;
          SelCells(r0, c0, r1, c1);
          FRich.MergeCells;
        end;
      2:
        begin
          FRich.SelStart := CellStart(r0, c0);
          FRich.SplitCell(1 + Random(2), 1 + Random(2));
        end;
      3:
        begin
          FRich.SelStart := CellStart(r0, c0);
          FRich.InsertRow(Random(2) = 0);
        end;
      4:
        if Rows > 2 then
        begin
          FRich.SelStart := CellStart(r0, c0);
          FRich.DeleteRow;
        end;
      5:
        begin
          FRich.SelStart := CellStart(r0, c0);
          FRich.InsertColumn(Random(2) = 0);
        end;
      6:
        begin
          FRich.SelStart := CellStart(r0, c0);
          if CellsOf(r0) > 2 then FRich.DeleteColumn;
        end;
      7: FRich.Undo;
    else
      FRich.Redo;
    end;
    g := Grid;
    try
      AssertTrue(Format('step %d (%d): the grid whole', [step, op]), g.Consistent);
    finally
      g.Free;
    end;
    if step mod 6 = 0 then
    begin
      saved := SaveRtf;
      d := TTyRichDocument.Create;
      st := TBytesStream.Create;
      try
        st.WriteBuffer(saved[1], Length(saved));
        st.Position := 0;
        TyRichLoadRtfFull(d, st);
        a := TyRichGridListing(FRich.Document, FRich.Document.Text.ParaStart(1));
        b := TyRichGridListing(d, d.Text.ParaStart(1));
        try
          AssertEquals(Format('step %d: read back, the same grid', [step]), a.Text, b.Text);
        finally
          a.Free;
          b.Free;
        end;
      finally
        st.Free;
        d.Free;
      end;
    end;
  end;
  n := 0;
  while FRich.Document.CanUndo and (n < 1000) do
  begin
    FRich.Undo;
    Inc(n);
  end;
  AssertTrue('every step undone: the first bytes', SaveRtf = first);
end;

initialization
  RegisterTest(TTyRichMergeTest);
end.
