unit test.richedit.merge;

{ Cells merged (TTyCustomRichEdit.MergeCells, the command TTyRichMergeCells): the content in
  reading order in the top-left cell, the grid after it, the look of the merged cell, one undo
  step that gives the file's bytes back, what the door refuses and what CanMergeCells says,
  and the files a person opens in Word to compare. No window. The unit is ASCII. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, LCLType, fpcunit, testregistry, tyControls.Controller,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout,
  tyControls.RichEdit.TableProps, tyControls.RichEdit.TableSel, tyControls.RichEdit,
  tyControls.RichEdit.Grid, test.richedit.layoutdevice, test.richedit.grid;

type
  TMergeRich = class(TTyRichEdit)
  protected
    function CreateDevice: TTyRichTextDevice; override;
  public
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
  end;

implementation

{ ---- the control ---- }

function TMergeRich.CreateDevice: TTyRichTextDevice;
begin
  Result := TTyRichTestDevice.Create;
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

initialization
  RegisterTest(TTyRichMergeTest);
end.
