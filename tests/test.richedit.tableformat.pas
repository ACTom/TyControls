unit test.richedit.tableformat;

{ A table's formats through the control's doors (SetCellShading, SetCellBorders, SetCellPadding,
  SetCellVAlign, SetTableAlign, CanFormatCells): each on one cell, a rectangle and the whole
  table - one undo step, read back as set, the rows it did not touch written as they were;
  which sides each border preset sets; rows and columns inserted as many as are selected; the
  actions enabled by the control's answers, the borders' and the properties' before-execute
  events; the builder's table properties; a new table's look (Word's). A control with the test
  device; no window. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, Controls, Forms, LCLType, ActnList, fpcunit, testregistry,
  tyControls.Controller, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.RowFormat, tyControls.RichEdit.TableProps,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.Layout, tyControls.RichEdit,
  tyControls.RichEdit.Actions, tyControls.RichEdit.Builder, tyControls.StrConsts,
  test.richedit.layoutdevice;

type
  TFmtRich = class(TTyRichEdit)
  protected
    function CreateDevice: TTyRichTextDevice; override;
  public
    Refusals: TStringList;
    Waits, WaitsEnded: Integer;
    destructor Destroy; override;
    procedure Refused(Sender: TObject; const AReason: string);
    procedure BeginWait; override;
    procedure EndWait; override;
    procedure SetWaitChars(AChars: Int64);
  end;

  TTyRichTableFormatTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TFmtRich;
    FBordersAsked, FPropsAsked: Integer;
    FGot: TTyRichTableProperties;
    procedure MakeTable(ARows, ACols: Integer);
    function CellStart(ARow, ACol: Integer): TTyRichPos;
    function CellEnd(ARow, ACol: Integer): TTyRichPos;
    procedure Sel(AAnchor, ACaret: TTyRichPos);
    function TablePos: TTyRichPos;
    function Cell(ARow, ACol: Integer): TTyRichCellProps;
    function RowP(ARow: Integer): TTyRichRowProps;
    function SaveRtf: RawByteString;
    function RowCount: Integer;
    function ColCount(ARow: Integer): Integer;
    // '' or where a full shared line has two definitions
    function Disagreement: string;
    { The three ranges: the caret in cell 1,1 (AKind 0); cells 1,1 .. 2,2 (1); every cell (2). }
    procedure Range(AKind: Integer; out AR0, AC0, AR1, AC1: Integer);
    function InRange(ARow, ACol, AR0, AC0, AR1, AC1: Integer): Boolean;
    { Row ARow's definition as written: its bytes in ARtf (between its \trowd and \row). }
    function RowBytes(const ARtf: RawByteString; ARow: Integer): RawByteString;
    procedure CheckUntouchedRows(const AWhat: string; const ABefore: RawByteString; AR0, AR1: Integer);
    procedure BordersAsk(Sender: TObject; var APreset: TTyRichBorderPreset;
      var ABorder: TTyRichBorder; var AAllow: Boolean);
    procedure PropsAsk(Sender: TObject; var AProps: TTyRichTableProperties; var AAllow: Boolean);
    procedure PropsOk(Sender: TObject; var AProps: TTyRichTableProperties; var AAllow: Boolean);
    procedure PropsVAlign(Sender: TObject; var AProps: TTyRichTableProperties; var AAllow: Boolean);
    procedure PropsLines(Sender: TObject; var AProps: TTyRichTableProperties; var AAllow: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestShadingOnACellARectangleAndTheTable;
    procedure TestBordersOnACellARectangleAndTheTable;
    procedure TestPaddingOnACellARectangleAndTheTable;
    procedure TestVAlignOnACellARectangleAndTheTable;
    procedure TestTableAlignAndIndent;
    procedure TestPresetsTouchTheRightSides;
    procedure TestInsertAsManyAsSelected;
    procedure TestActionsFollowCanAnswers;
    procedure TestTheBuilderSetsEveryCellProperty;
    procedure TestANewTableIsWords;
    procedure TestWrittenAsWordWritesIt;
    procedure TestRefusedAndTold;
    procedure TestTableEditsKeepBothSidesAlike;
    procedure TestACellBelowGetsTheLineOnlyWhenItLiesUnderIt;
    procedure TestARowWithANestedTableIsLeftAsItIs;
    procedure TestDistributeRowsShowsTheWaitCursorWhenLong;
    procedure TestTablePropertiesApplyOnlyWhatChanged;
    procedure TestTableAlignLeavesTheIndent;
    procedure TestTheBuildersRowIsInTwipsAndMisuseRaises;
    procedure TestEdgesLinedUpAgainShareOneDefinition;
    procedure TestARandomWalkLeavesNoLineWithTwoDefinitions;
    procedure TestTheSelectActions;
    procedure TestTablePropertiesSetLinesInTheSameStep;
    procedure TestAlignmentActionsAreCheckedWhenAllAlike;
    procedure TestWidthsAndHeightsOverEverySelectedColumnAndRow;
  end;

implementation

{ ---- the control ---- }

function TFmtRich.CreateDevice: TTyRichTextDevice;
begin
  Result := TTyRichTestDevice.Create;
end;

destructor TFmtRich.Destroy;
begin
  Refusals.Free;
  inherited Destroy;
end;

procedure TFmtRich.Refused(Sender: TObject; const AReason: string);
begin
  Refusals.Add(AReason);
end;

// (counted only: no cursor of the screen's is touched)
procedure TFmtRich.BeginWait;
begin
  Inc(Waits);
end;

procedure TFmtRich.EndWait;
begin
  Inc(WaitsEnded);
end;

procedure TFmtRich.SetWaitChars(AChars: Int64);
begin
  CopyWaitChars := AChars;
end;

{ ---- the fixture ---- }

procedure TTyRichTableFormatTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TFmtRich.Create(nil);
  FRich.Refusals := TStringList.Create;
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 700, 500);
  FRich.OnEditRefused := @FRich.Refused;
end;

procedure TTyRichTableFormatTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

procedure TTyRichTableFormatTest.MakeTable(ARows, ACols: Integer);
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
  FRich.UpdateView;
end;

function TTyRichTableFormatTest.CellStart(ARow, ACol: Integer): TTyRichPos;
var
  f, l: Integer;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  Result := FRich.Document.Text.ParaStart(f);
end;

function TTyRichTableFormatTest.CellEnd(ARow, ACol: Integer): TTyRichPos;
var
  f, l: Integer;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  Result := FRich.Document.Text.ParaStart(l) + FRich.Document.Text.ParaLength(l) + 1;
end;

procedure TTyRichTableFormatTest.Sel(AAnchor, ACaret: TTyRichPos);
begin
  FRich.SelStart := AAnchor;
  FRich.SelLength := ACaret - AAnchor;
end;

function TTyRichTableFormatTest.TablePos: TTyRichPos;
begin
  Result := FRich.Document.Text.ParaStart(1);
end;

function TTyRichTableFormatTest.Cell(ARow, ACol: Integer): TTyRichCellProps;
begin
  Result := FRich.Document.CellProps(TablePos, ARow, ACol);
end;

function TTyRichTableFormatTest.RowP(ARow: Integer): TTyRichRowProps;
begin
  Result := FRich.Document.RowProps(TablePos, ARow);
end;

function TTyRichTableFormatTest.SaveRtf: RawByteString;
var
  st: TStringStream;
begin
  st := TStringStream.Create('');
  try
    FRich.SaveToStream(st, rfRtf);
    Result := st.DataString;
  finally
    st.Free;
  end;
end;

function TTyRichTableFormatTest.RowCount: Integer;
var
  info: TTyRichTableInfo;
begin
  AssertTrue('a table', FRich.Document.TableInfoAt(1, info));
  Result := info.RowCount;
end;

function TTyRichTableFormatTest.ColCount(ARow: Integer): Integer;
begin
  Result := FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(CellStart(ARow, 0))).Row.CellCount;
end;

procedure TTyRichTableFormatTest.Range(AKind: Integer; out AR0, AC0, AR1, AC1: Integer);
begin
  case AKind of
    0:
      begin
        FRich.SelStart := CellStart(1, 1) + 1;
        AR0 := 1; AC0 := 1; AR1 := 1; AC1 := 1;
      end;
    1:
      begin
        Sel(CellStart(1, 1), CellEnd(2, 2));
        AR0 := 1; AC0 := 1; AR1 := 2; AC1 := 2;
      end;
  else
    begin
      Sel(CellStart(0, 0), CellEnd(3, 3));
      AR0 := 0; AC0 := 0; AR1 := 3; AC1 := 3;
    end;
  end;
end;

function TTyRichTableFormatTest.InRange(ARow, ACol, AR0, AC0, AR1, AC1: Integer): Boolean;
begin
  Result := (ARow >= AR0) and (ARow <= AR1) and (ACol >= AC0) and (ACol <= AC1);
end;

function TTyRichTableFormatTest.RowBytes(const ARtf: RawByteString; ARow: Integer): RawByteString;
var
  i, k, e: Integer;
begin
  Result := '';
  k := 0;
  i := 1;
  while i > 0 do
  begin
    i := Pos('\trowd', Copy(ARtf, i, MaxInt)) + i - 1;
    if i < 1 then Exit;
    if k = ARow then
    begin
      e := Pos('\row', Copy(ARtf, i + 6, MaxInt));
      while (e > 0) and (Copy(ARtf, i + 6 + e - 1, 5) = '\rowd') do
        e := e + Pos('\row', Copy(ARtf, i + 6 + e, MaxInt));
      Exit(Copy(ARtf, i, 6 + e + 3));
    end;
    Inc(k);
    i := i + 6;
  end;
end;

procedure TTyRichTableFormatTest.CheckUntouchedRows(const AWhat: string; const ABefore: RawByteString;
  AR0, AR1: Integer);
var
  after: RawByteString;
  r: Integer;
begin
  after := SaveRtf;
  for r := 0 to 3 do
    if (r < AR0) or (r > AR1) then
      AssertTrue(Format('%s: row %d written as it was', [AWhat, r]), RowBytes(ABefore, r) = RowBytes(after, r))
    else
      AssertFalse(Format('%s: row %d written anew', [AWhat, r]), RowBytes(ABefore, r) = RowBytes(after, r));
end;

{ ---- each door on three ranges ---- }

procedure TTyRichTableFormatTest.TestShadingOnACellARectangleAndTheTable;
var
  k, r, c, r0, c0, r1, c1: Integer;
  before: RawByteString;
begin
  for k := 0 to 2 do
  begin
    MakeTable(4, 4);
    before := SaveRtf;
    Range(k, r0, c0, r1, c1);
    AssertTrue('may', FRich.CanFormatCells);
    AssertTrue('shaded', FRich.SetCellShading(clYellow));
    AssertEquals(Format('%d: one step', [k]), 1, FRich.Document.UndoDepth);
    for r := 0 to 3 do
      for c := 0 to 3 do
        if InRange(r, c, r0, c0, r1, c1) then
          AssertEquals(Format('%d: cell %d,%d shaded', [k, r, c]), clYellow, Cell(r, c).Shading)
        else
          AssertEquals(Format('%d: cell %d,%d not', [k, r, c]), clNone, Cell(r, c).Shading);
    CheckUntouchedRows(Format('shading %d', [k]), before, r0, r1);
    FRich.Undo;
    AssertTrue(Format('%d: undone, the bytes back', [k]), before = SaveRtf);
  end;
end;

const
  // the cell beside a side: the one whose facing side it shares
  FaceRow: array[TTyRowCellSide] of Integer = (0, -1, 0, 1);
  FaceCol: array[TTyRowCellSide] of Integer = (-1, 0, 1, 0);

procedure TTyRichTableFormatTest.TestBordersOnACellARectangleAndTheTable;
var
  k, r, c, r0, c0, r1, c1: Integer;
  before: RawByteString;
  p: TTyRichCellProps;
  sd: TTyRowCellSide;
begin
  for k := 0 to 2 do
  begin
    MakeTable(4, 4);
    before := SaveRtf;
    Range(k, r0, c0, r1, c1);
    AssertTrue('borders', FRich.SetCellBorders(rbpAll, TyRichBorder(rbsDouble, 30, clRed)));
    AssertEquals(Format('%d: one step', [k]), 1, FRich.Document.UndoDepth);
    for r := 0 to 3 do
      for c := 0 to 3 do
      begin
        p := Cell(r, c);
        for sd := Low(TTyRowCellSide) to High(TTyRowCellSide) do
          // (the facing side of a cell beside the range too: one line, one definition)
          if InRange(r, c, r0, c0, r1, c1) or InRange(r + FaceRow[sd], c + FaceCol[sd], r0, c0, r1, c1) then
            AssertTrue(Format('%d: cell %d,%d side %d', [k, r, c, Ord(sd)]),
              TyRichSameBorder(p.Borders[sd], TyRichBorder(rbsDouble, 30, clRed)))
          else
            AssertTrue(Format('%d: cell %d,%d side %d as it was', [k, r, c, Ord(sd)]),
              p.Borders[sd].Style = rbsSingle);
      end;
    CheckUntouchedRows(Format('borders %d', [k]), before, Max(0, r0 - 1), Min(3, r1 + 1));
    FRich.Undo;
    AssertTrue(Format('%d: undone', [k]), before = SaveRtf);
  end;
end;

procedure TTyRichTableFormatTest.TestPaddingOnACellARectangleAndTheTable;
var
  k, r, c, r0, c0, r1, c1: Integer;
  before: RawByteString;
  p: TTyRichCellProps;
begin
  for k := 0 to 2 do
  begin
    MakeTable(4, 4);
    before := SaveRtf;
    Range(k, r0, c0, r1, c1);
    // a right padding of the cells' own first: -1 leaves it as it is (not the row's)
    AssertTrue('a right padding', FRich.SetCellPadding(-1, -1, 300, -1));
    FRich.Document.ClearUndo;
    AssertTrue('padding', FRich.SetCellPadding(200, 60, -1, 90));
    AssertEquals(Format('%d: one step', [k]), 1, FRich.Document.UndoDepth);
    for r := 0 to 3 do
      for c := 0 to 3 do
      begin
        p := Cell(r, c);
        if InRange(r, c, r0, c0, r1, c1) then
        begin
          AssertEquals(Format('%d: %d,%d left', [k, r, c]), 200, p.Pad[rcsLeft]);
          AssertEquals(Format('%d: %d,%d top', [k, r, c]), 60, p.Pad[rcsTop]);
          AssertEquals(Format('%d: %d,%d right as it was', [k, r, c]), 300, p.Pad[rcsRight]);
          AssertEquals(Format('%d: %d,%d bottom', [k, r, c]), 90, p.Pad[rcsBottom]);
        end
        else
        begin
          AssertEquals(Format('%d: %d,%d left untouched', [k, r, c]), 108, p.Pad[rcsLeft]);
          AssertEquals(Format('%d: %d,%d top untouched', [k, r, c]), 0, p.Pad[rcsTop]);
        end;
      end;
    FRich.Undo;
    AssertEquals(Format('%d: undone to its own right padding', [k]), 300, Cell(r0, c0).Pad[rcsRight]);
  end;
end;

procedure TTyRichTableFormatTest.TestVAlignOnACellARectangleAndTheTable;
var
  k, r, c, r0, c0, r1, c1: Integer;
  before: RawByteString;
begin
  for k := 0 to 2 do
  begin
    MakeTable(4, 4);
    before := SaveRtf;
    Range(k, r0, c0, r1, c1);
    AssertTrue('aligned', FRich.SetCellVAlign(rcvBottom));
    AssertEquals(Format('%d: one step', [k]), 1, FRich.Document.UndoDepth);
    for r := 0 to 3 do
      for c := 0 to 3 do
        AssertEquals(Format('%d: %d,%d', [k, r, c]), InRange(r, c, r0, c0, r1, c1),
          Cell(r, c).VAlign = rcvBottom);
    CheckUntouchedRows(Format('valign %d', [k]), before, r0, r1);
    FRich.Undo;
    AssertTrue(Format('%d: undone', [k]), before = SaveRtf);
  end;
end;

procedure TTyRichTableFormatTest.TestTableAlignAndIndent;
var
  r, x0, x1: Integer;
  before: RawByteString;
begin
  MakeTable(4, 4);
  before := SaveRtf;
  FRich.SelStart := CellStart(2, 2);
  x0 := FRich.PositionRect(CellStart(0, 0), False).Left;
  AssertTrue('centred', FRich.SetTableAlign(rraCenter));
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  for r := 0 to 3 do AssertTrue(Format('row %d', [r]), RowP(r).Align = rraCenter);
  FRich.UpdateView;
  x1 := FRich.PositionRect(CellStart(0, 0), False).Left;
  AssertTrue(Format('drawn further right (%d to %d)', [x0, x1]), x1 > x0 + 20);
  AssertTrue('written: \trqc', Pos('\trqc', SaveRtf) > 0);
  FRich.Undo;
  AssertTrue('undone', before = SaveRtf);
  // left, indented
  AssertTrue('indented', FRich.SetTableAlign(rraLeft, 720));
  for r := 0 to 3 do AssertEquals(Format('row %d: its start', [r]), 720, RowP(r).LeftTwips);
  FRich.UpdateView;
  AssertTrue('drawn half an inch right', Abs(FRich.PositionRect(CellStart(0, 0), False).Left - (x0 + 48)) <= 1);
end;

{ ---- the presets ---- }

{ The sides a preset gives the border on cells 1,1 .. 3,3 of a 5 x 5 table (Own), and the
  facing side of each of those in the cell beside it: every side of every cell, the neighbours
  too, is the border exactly when it or the side it faces is one the preset names. }
function PresetOwns(APreset: TTyRichBorderPreset; ARow, ACol: Integer; ASide: TTyRowCellSide): Boolean;
const
  R0 = 1;
  R1 = 3;
begin
  Result := False;
  if (ARow < R0) or (ARow > R1) or (ACol < R0) or (ACol > R1) then Exit;
  case APreset of
    rbpAll, rbpNone: Result := True;
    rbpOutside: Result := ((ASide = rcsTop) and (ARow = R0)) or ((ASide = rcsBottom) and (ARow = R1)) or
      ((ASide = rcsLeft) and (ACol = R0)) or ((ASide = rcsRight) and (ACol = R1));
    rbpInside: Result := ((ASide = rcsTop) and (ARow > R0)) or ((ASide = rcsBottom) and (ARow < R1)) or
      ((ASide = rcsLeft) and (ACol > R0)) or ((ASide = rcsRight) and (ACol < R1));
    rbpTop: Result := (ASide = rcsTop) and (ARow = R0);
    rbpBottom: Result := (ASide = rcsBottom) and (ARow = R1);
    rbpLeft: Result := (ASide = rcsLeft) and (ACol = R0);
    rbpRight: Result := (ASide = rcsRight) and (ACol = R1);
    rbpInsideH: Result := ((ASide = rcsTop) and (ARow > R0)) or ((ASide = rcsBottom) and (ARow < R1));
    rbpInsideV: Result := ((ASide = rcsLeft) and (ACol > R0)) or ((ASide = rcsRight) and (ACol < R1));
  end;
end;

function PresetSets(APreset: TTyRichBorderPreset; ARow, ACol: Integer; ASide: TTyRowCellSide): Boolean;
const
  Opposite: array[TTyRowCellSide] of TTyRowCellSide = (rcsRight, rcsBottom, rcsLeft, rcsTop);
begin
  Result := PresetOwns(APreset, ARow, ACol, ASide) or
    PresetOwns(APreset, ARow + FaceRow[ASide], ACol + FaceCol[ASide], Opposite[ASide]);
end;

procedure TTyRichTableFormatTest.TestPresetsTouchTheRightSides;
var
  r, c: Integer;
  b, want: TTyRichBorder;
  pr: TTyRichBorderPreset;
  sd: TTyRowCellSide;
  before: RawByteString;
begin
  b := TyRichBorder(rbsSingle, 40, clRed);
  for pr := Low(TTyRichBorderPreset) to High(TTyRichBorderPreset) do
  begin
    MakeTable(6, 6);
    before := SaveRtf;
    Sel(CellStart(1, 1), CellEnd(3, 3));
    AssertTrue('applied', FRich.SetCellBorders(pr, b));
    AssertEquals(Format('%d: one step', [Ord(pr)]), 1, FRich.Document.UndoDepth);
    if pr = rbpNone then want := TyRichBorder(rbsNone, 0) else want := b;
    for r := 0 to 5 do
      for c := 0 to 5 do
        for sd := Low(TTyRowCellSide) to High(TTyRowCellSide) do
          if PresetSets(pr, r, c, sd) then
            AssertTrue(Format('%d: %d,%d side %d set', [Ord(pr), r, c, Ord(sd)]),
              TyRichSameBorder(Cell(r, c).Borders[sd], want))
          else
            AssertTrue(Format('%d: %d,%d side %d as it was', [Ord(pr), r, c, Ord(sd)]),
              TyRichSameBorder(Cell(r, c).Borders[sd], TyRichBorder(rbsSingle, 10)));
    // the rows beyond the neighbours: their bytes
    AssertTrue(Format('%d: row 5: past the neighbours, its bytes', [Ord(pr)]),
      (RowBytes(before, 5) = RowBytes(SaveRtf, 5)));
    FRich.Undo;
    AssertTrue(Format('%d: undone', [Ord(pr)]), before = SaveRtf);
  end;
  // none: no line is left around the rectangle - not the neighbours' facing sides either
  MakeTable(5, 5);
  Sel(CellStart(1, 1), CellEnd(3, 3));
  AssertTrue('none', FRich.SetCellBorders(rbpNone, b));
  AssertTrue('none: the row above, its bottom', Cell(0, 2).Borders[rcsBottom].Style = rbsNone);
  AssertTrue('none: the cell to the left, its right', Cell(2, 0).Borders[rcsRight].Style = rbsNone);
  AssertTrue('none: outside the rectangle as it was', Cell(0, 0).Borders[rcsBottom].Style = rbsSingle);
end;

procedure TTyRichTableFormatTest.TestInsertAsManyAsSelected;
var
  n0: Integer;
begin
  MakeTable(4, 4);
  // three rows selected: three rows below them, one step
  Sel(CellStart(0, 1), CellEnd(2, 2));
  AssertTrue('rows', FRich.InsertRow(True));
  AssertEquals('three more rows', 7, RowCount);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  AssertEquals('the rows below the selection', 'r3c0',
    FRich.Document.Text.GetText(CellStart(6, 0), 4));
  FRich.Undo;
  AssertEquals('undone', 4, RowCount);
  // above: two rows
  Sel(CellStart(1, 0), CellEnd(2, 0));
  AssertTrue('rows above', FRich.InsertRow(False));
  AssertEquals('two more rows above', 6, RowCount);
  AssertEquals('the selection''s first row is now row 3', 'r1c0',
    FRich.Document.Text.GetText(CellStart(3, 0), 4));
  FRich.Undo;
  // columns: two selected, two to the right
  n0 := ColCount(0);
  Sel(CellStart(0, 1), CellEnd(1, 2));
  AssertTrue('columns', FRich.InsertColumn(True));
  AssertEquals('two more columns', n0 + 2, ColCount(0));
  AssertEquals('right of the selection', 'r0c3', FRich.Document.Text.GetText(CellStart(0, 5), 4));
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  FRich.Undo;
  // left: three
  Sel(CellStart(0, 0), CellEnd(0, 2));
  AssertTrue('columns left', FRich.InsertColumn(False));
  AssertEquals('three more columns', n0 + 3, ColCount(0));
  AssertEquals('the first selected column moved right', 'r0c0', FRich.Document.Text.GetText(CellStart(0, 3), 4));
  // the caret alone: one
  FRich.Undo;
  FRich.SelStart := CellStart(1, 1);
  AssertTrue('one row', FRich.InsertRow(True));
  AssertEquals('one more', 5, RowCount);
end;

{ ---- actions ---- }

procedure TTyRichTableFormatTest.BordersAsk(Sender: TObject; var APreset: TTyRichBorderPreset;
  var ABorder: TTyRichBorder; var AAllow: Boolean);
begin
  Inc(FBordersAsked);
  APreset := rbpOutside;
  ABorder := TyRichBorder(rbsDashed, 20, clBlue);
  AAllow := FBordersAsked = 1;
end;

procedure TTyRichTableFormatTest.PropsAsk(Sender: TObject; var AProps: TTyRichTableProperties;
  var AAllow: Boolean);
begin
  Inc(FPropsAsked);
  AssertEquals('the row as it is', 0, AProps.RowHeight);
  AssertEquals('the padding as it is', 108, AProps.Pad[rcsLeft]);
  AProps.Changed := [tpfRowHeight, tpfShading, tpfVAlign];
  AProps.RowHeight := 700;
  AProps.Shading := clAqua;
  AProps.VAlign := rcvCenter;
end;

procedure TTyRichTableFormatTest.TestActionsFollowCanAnswers;
var
  list: TActionList;
  sh: TTyRichEditCellShading;
  bo: TTyRichEditCellBorders;
  pr: TTyRichEditTableProperties;
  di: TTyRichEditDistributeColumns;
begin
  list := TActionList.Create(nil);
  try
    sh := TTyRichEditCellShading.Create(list);
    sh.RichEdit := FRich;
    bo := TTyRichEditCellBorders.Create(list);
    bo.RichEdit := FRich;
    bo.OnBeforeExecute := @BordersAsk;
    pr := TTyRichEditTableProperties.Create(list);
    pr.RichEdit := FRich;
    pr.OnBeforeExecute := @PropsAsk;
    di := TTyRichEditDistributeColumns.Create(list);
    di.RichEdit := FRich;
    MakeTable(3, 3);
    // outside a table: off
    FRich.SelStart := 1;
    sh.Update;
    bo.Update;
    di.Update;
    AssertFalse('shading: no table', sh.Enabled);
    AssertFalse('borders: no table', bo.Enabled);
    AssertFalse('distribute: no table', di.Enabled);
    // in it: on
    FRich.SelStart := CellStart(1, 1);
    sh.Update;
    bo.Update;
    di.Update;
    AssertTrue('shading', sh.Enabled);
    AssertTrue('borders', bo.Enabled);
    AssertTrue('distribute', di.Enabled);
    sh.Execute;
    AssertEquals('shaded yellow', clYellow, Cell(1, 1).Shading);
    // borders: the event's preset and line
    Sel(CellStart(0, 0), CellEnd(1, 1));
    bo.Execute;
    AssertEquals('asked', 1, FBordersAsked);
    AssertTrue('the event''s line', TyRichSameBorder(Cell(0, 0).Borders[rcsTop], TyRichBorder(rbsDashed, 20, clBlue)));
    AssertTrue('the event''s preset: not inside', Cell(0, 0).Borders[rcsRight].Style = rbsSingle);
    // refused by the event: nothing
    FRich.Document.ClearUndo;
    bo.Execute;
    AssertEquals('asked again', 2, FBordersAsked);
    AssertEquals('not allowed: nothing', 0, FRich.Document.UndoDepth);
    // table properties: one step for all of it
    FRich.SelStart := CellStart(2, 2);
    pr.Execute;
    AssertEquals('properties asked', 1, FPropsAsked);
    AssertEquals('one step', 1, FRich.Document.UndoDepth);
    AssertEquals('the height', 700, RowP(2).HeightTwips);
    AssertEquals('the shading', clAqua, Cell(2, 2).Shading);
    AssertTrue('the alignment', Cell(2, 2).VAlign = rcvCenter);
    // read-only: off
    FRich.ReadOnly := True;
    sh.Update;
    AssertFalse('read-only', sh.Enabled);
  finally
    list.Free;
  end;
end;

{ ---- the builder ---- }

procedure TTyRichTableFormatTest.TestTheBuilderSetsEveryCellProperty;
var
  B: TTyRichBuilder;
  p: TTyRichCellProps;
  b0: TTyRichBorder;
begin
  B := TTyRichBuilder.Create;
  try
    B.Text('before').Paragraph;
    B.Table([1440, 2880, 1440]).TableAlign(rraRight);
    B.Cell.Text('a').Shading(clYellow).CellBorders([rcsTop, rcsBottom], rbsDouble, 30, clRed);
    B.Cell.Text('b').CellPadding(200, 60, 150, 90).CellVAlign(rcvBottom);
    B.Cell.Text('c');
    B.Row(600, True).Cell.Text('d').CellVAlign(rcvCenter).Cell.Text('e').Cell.Text('f');
    B.Row(400).Cell.Text('g').Cell.Text('h').Cell.Text('i').EndTable;
    B.Text('after');
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  AssertEquals('no undo step', 0, FRich.Document.UndoDepth);
  p := Cell(0, 0);
  AssertEquals('a: shaded', clYellow, p.Shading);
  b0 := TyRichBorder(rbsDouble, 30, clRed);
  AssertTrue('a: top', TyRichSameBorder(p.Borders[rcsTop], b0));
  AssertTrue('a: bottom', TyRichSameBorder(p.Borders[rcsBottom], b0));
  AssertTrue('a: left as Word''s new table', p.Borders[rcsLeft].Style = rbsSingle);
  // the line a's bottom is: also the top of the cell below (one line, one definition)
  AssertTrue('d: its top, a''s bottom', TyRichSameBorder(Cell(1, 0).Borders[rcsTop], b0));
  AssertTrue('d: its bottom as it was', Cell(1, 0).Borders[rcsBottom].Style = rbsSingle);
  p := Cell(0, 1);
  AssertEquals('b: left', 200, p.Pad[rcsLeft]);
  AssertEquals('b: top', 60, p.Pad[rcsTop]);
  AssertEquals('b: right', 150, p.Pad[rcsRight]);
  AssertEquals('b: bottom', 90, p.Pad[rcsBottom]);
  AssertTrue('b: at the bottom', p.VAlign = rcvBottom);
  AssertTrue('d: in the middle', Cell(1, 0).VAlign = rcvCenter);
  AssertEquals('row 1: exactly 30 pt', -600, RowP(1).HeightTwips);
  AssertEquals('row 2: at least 20 pt', 400, RowP(2).HeightTwips);
  AssertTrue('right aligned', RowP(0).Align = rraRight);
  AssertTrue('every row', RowP(2).Align = rraRight);
  AssertEquals('c: no shading', clNone, Cell(0, 2).Shading);
  // two cells giving one line two borders: the one given later is the line, on both sides
  B := TTyRichBuilder.Create;
  try
    B.Text('before').Paragraph;
    B.Table([1440, 1440]);
    B.Cell.Text('a').CellBorders([rcsRight], rbsDouble, 30, clRed);
    B.Cell.Text('b').CellBorders([rcsLeft], rbsDotted, 20, clBlue).EndTable;
    B.Text('after');
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  b0 := TyRichBorder(rbsDotted, 20, clBlue);
  AssertTrue('the later: b''s left', TyRichSameBorder(Cell(0, 1).Borders[rcsLeft], b0));
  AssertTrue('the later: a''s right too', TyRichSameBorder(Cell(0, 0).Borders[rcsRight], b0));
end;

{ A new table, the editor's and the builder's: single ½-point lines in the automatic colour,
  equal columns, 108 twips of padding left and right and none above and below. }
procedure TTyRichTableFormatTest.TestANewTableIsWords;
var
  p: TTyRichCellProps;
  e: TTyRichEdges;
  sd: TTyRowCellSide;
  B: TTyRichBuilder;
  k: Integer;
begin
  for k := 0 to 1 do
  begin
    if k = 0 then
      MakeTable(2, 3)
    else
    begin
      B := TTyRichBuilder.Create;
      try
        B.Text('before').Paragraph;
        B.Table([1440, 1440, 1440]).Cell.Text('a').Cell.Text('b').Cell.Text('c');
        B.Row.Cell.Text('d').Cell.Text('e').Cell.Text('f').EndTable.Text('after');
        FRich.SetContent(B);
      finally
        B.Free;
      end;
    end;
    p := Cell(1, 1);
    for sd := Low(TTyRowCellSide) to High(TTyRowCellSide) do
    begin
      AssertTrue(Format('%d: side %d single', [k, Ord(sd)]), p.Borders[sd].Style = rbsSingle);
      AssertEquals(Format('%d: side %d half a point', [k, Ord(sd)]), 10, p.Borders[sd].WidthTwips);
      AssertEquals(Format('%d: side %d automatic', [k, Ord(sd)]), clDefault, p.Borders[sd].Color);
    end;
    AssertEquals(Format('%d: rcsLeft', [k]), 108, p.Pad[rcsLeft]);
    AssertEquals(Format('%d: rcsRight', [k]), 108, p.Pad[rcsRight]);
    AssertEquals(Format('%d: rcsTop', [k]), 0, p.Pad[rcsTop]);
    AssertEquals(Format('%d: rcsBottom', [k]), 0, p.Pad[rcsBottom]);
    e := FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(CellStart(0, 0))).Row.CellEdges;
    AssertEquals(Format('%d: equal columns', [k]), e[1] - e[0], e[2] - e[1]);
  end;
end;

{ What Word reads: the words Word writes for each property. }
procedure TTyRichTableFormatTest.TestWrittenAsWordWritesIt;
var
  s: RawByteString;
begin
  MakeTable(2, 2);
  FRich.SelStart := CellStart(0, 0);
  FRich.SetCellShading(RGBToColor(255, 255, 0));
  FRich.SetCellBorders(rbpTop, TyRichBorder(rbsDouble, 30, clRed));
  FRich.SetCellPadding(200, 60, -1, -1);
  FRich.SetCellVAlign(rcvCenter);
  FRich.SetRowHeight(500, True);
  FRich.SetTableAlign(rraCenter);
  s := SaveRtf;
  AssertTrue('shading: \clcbpat', Pos('\clcbpat', s) > 0);
  AssertTrue('a border: \clbrdrt\brdrdb\brdrw30\brdrcf', Pos('\clbrdrt\brdrdb\brdrw30\brdrcf', s) > 0);
  // Word's swap: the left padding is \clpadt, the top \clpadl
  AssertTrue('left padding: \clpadt200', Pos('\clpadt200', s) > 0);
  AssertTrue('top padding: \clpadl60', Pos('\clpadl60', s) > 0);
  AssertTrue('vertical alignment: \clvertalc', Pos('\clvertalc', s) > 0);
  AssertTrue('exact height: \trrh-500', Pos('\trrh-500', s) > 0);
  AssertTrue('centred: \trqc', Pos('\trqc', s) > 0);
end;

procedure TTyRichTableFormatTest.TestRefusedAndTold;
const
  Nested = '{\rtf1 \trowd\cellx1000\cellx2000\pard\intbl a\cell \pard\intbl\itap2 x' +
    '\nestcell{\*\nesttableprops\trowd\cellx500\nestrow}{\nonesttables\par}\pard\intbl\cell' +
    '\row\pard b\par}';
var
  st: TStringStream;
begin
  // outside a table
  FRich.Lines.Text := 'plain';
  FRich.Refusals.Clear;
  AssertFalse('no table', FRich.SetCellShading(clYellow));
  AssertEquals('told once', 1, FRich.Refusals.Count);
  AssertFalse('not offered', FRich.CanFormatCells);
  // a row that holds a nested table
  st := TStringStream.Create(Nested);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.SelStart := 0;
  FRich.Refusals.Clear;
  AssertFalse('nested', FRich.SetCellShading(clYellow));
  AssertEquals('told once', 1, FRich.Refusals.Count);
  AssertEquals('why', rsRichEditRefusedResizeNested, FRich.Refusals[0]);
  // read-only: nothing, told nothing
  MakeTable(2, 2);
  FRich.ReadOnly := True;
  FRich.SelStart := CellStart(0, 0);
  FRich.Refusals.Clear;
  AssertFalse('read-only', FRich.SetCellShading(clYellow));
  AssertEquals('told nothing', 0, FRich.Refusals.Count);
end;

{ Rows whose edges differ: the cell below takes a line given to the cells above only when its
  whole top lies under them (within 15 twips); one that only partly does keeps its own top. }
procedure TTyRichTableFormatTest.TestACellBelowGetsTheLineOnlyWhenItLiesUnderIt;
const
  Doc = '{\rtf1 \pard before\par' +
    '\trowd\cellx1440\cellx2880\cellx4320\pard\intbl a\cell \pard\intbl b\cell \pard\intbl c\cell\row' +
    '\trowd\cellx2160\cellx2890\cellx4320\pard\intbl d\cell \pard\intbl e\cell \pard\intbl f\cell\row' +
    '\pard after\par}';
var
  st: TStringStream;
  b: TTyRichBorder;

  procedure Load;
  begin
    st := TStringStream.Create(Doc);
    try
      FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    FRich.UpdateView;
  end;

begin
  b := TyRichBorder(rbsDouble, 30, clRed);
  // a: 0 .. 1440; d below it reaches 2160 - only partly under a
  Load;
  Sel(CellStart(0, 0), CellEnd(0, 0));
  AssertTrue('a: its bottom', FRich.SetCellBorders(rbpBottom, b));
  AssertTrue('a: set', TyRichSameBorder(Cell(0, 0).Borders[rcsBottom], b));
  AssertFalse('d: partly under a - its own top', TyRichSameBorder(Cell(1, 0).Borders[rcsTop], b));
  // a and b: 0 .. 2880; d (0 .. 2160) and e (.. 2890, within 15 twips) lie under them, f not
  Load;
  Sel(CellStart(0, 0), CellEnd(0, 1));
  AssertTrue('a, b: their bottom', FRich.SetCellBorders(rbpBottom, b));
  AssertTrue('d: under them', TyRichSameBorder(Cell(1, 0).Borders[rcsTop], b));
  AssertTrue('e: under them, its edge 10 twips past', TyRichSameBorder(Cell(1, 1).Borders[rcsTop], b));
  AssertFalse('f: not', TyRichSameBorder(Cell(1, 2).Borders[rcsTop], b));
end;

{ Rows and columns in and out keep every line two cells share one definition: the one's side
  and the other's facing side alike, the line drawn there before (the wider) on both. }
procedure TTyRichTableFormatTest.TestTableEditsKeepBothSidesAlike;
var
  thick, thin: TTyRichBorder;
  before: RawByteString;

  procedure SetSide(ARow0, ACol0, ARow1, ACol1: Integer; ASide: TTyRowCellSide; const B: TTyRichBorder);
  var
    p: TTyRichCellProps;
  begin
    p := Default(TTyRichCellProps);
    case ASide of
      rcsLeft: p.Valid := [rcpBorderLeft];
      rcsTop: p.Valid := [rcpBorderTop];
      rcsRight: p.Valid := [rcpBorderRight];
    else
      p.Valid := [rcpBorderBottom];
    end;
    p.Borders[ASide] := B;
    // (straight to the document: one side only, as a file made elsewhere may have it)
    AssertTrue('a side', FRich.Document.Execute(TTyRichSetCellProps.Create(TablePos, ARow0, ACol0,
      ARow1, ACol1, p)));
    FRich.Document.ClearUndo;
  end;

  procedure CheckAgree(const AWhat: string);
  var
    r, c: Integer;
  begin
    for r := 0 to RowCount - 1 do
      for c := 0 to ColCount(r) - 1 do
      begin
        if c < ColCount(r) - 1 then
          AssertTrue(Format('%s: %d,%d right = %d,%d left', [AWhat, r, c, r, c + 1]),
            TyRichSameBorder(Cell(r, c).Borders[rcsRight], Cell(r, c + 1).Borders[rcsLeft]));
        if r < RowCount - 1 then
          AssertTrue(Format('%s: %d,%d bottom = %d,%d top', [AWhat, r, c, r + 1, c]),
            TyRichSameBorder(Cell(r, c).Borders[rcsBottom], Cell(r + 1, c).Borders[rcsTop]));
      end;
  end;

begin
  thick := TyRichBorder(rbsDouble, 30, clRed);
  thin := TyRichBorder(rbsDashed, 20, clBlue);
  // a row in below one whose bottom differs from the next row's top (the wider is the line)
  MakeTable(4, 4);
  SetSide(1, 0, 1, 3, rcsBottom, thick);
  before := SaveRtf;
  FRich.SelStart := CellStart(1, 1);
  AssertTrue('a row below', FRich.InsertRow(True));
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  AssertEquals('five rows', 5, RowCount);
  CheckAgree('row in');
  AssertTrue('row in: the wider is the line', TyRichSameBorder(Cell(2, 1).Borders[rcsTop], thick));
  FRich.Undo;
  AssertTrue('row in: undone', before = SaveRtf);
  // a row out between two that come to meet
  MakeTable(4, 4);
  SetSide(0, 0, 0, 3, rcsBottom, thin);
  SetSide(2, 0, 2, 3, rcsTop, thick);
  before := SaveRtf;
  FRich.SelStart := CellStart(1, 1);
  AssertTrue('a row out', FRich.DeleteRow);
  CheckAgree('row out');
  AssertTrue('row out: the wider is the line', TyRichSameBorder(Cell(0, 1).Borders[rcsBottom], thick));
  FRich.Undo;
  AssertTrue('row out: undone', before = SaveRtf);
  // a column in right of one whose right differs from the next cell's left
  MakeTable(4, 4);
  SetSide(0, 1, 3, 1, rcsRight, thick);
  before := SaveRtf;
  FRich.SelStart := CellStart(1, 1);
  AssertTrue('a column right', FRich.InsertColumn(True));
  AssertEquals('five columns', 5, ColCount(0));
  CheckAgree('column in');
  FRich.Undo;
  AssertTrue('column in: undone', before = SaveRtf);
  // a column out between two that come to meet
  MakeTable(4, 4);
  SetSide(0, 0, 3, 0, rcsRight, thick);
  SetSide(0, 2, 3, 2, rcsLeft, thin);
  FRich.SelStart := CellStart(1, 1);
  AssertTrue('a column out', FRich.DeleteColumn);
  CheckAgree('column out');
  AssertTrue('column out: the wider is the line', TyRichSameBorder(Cell(2, 0).Borders[rcsRight], thick));
  // a table already alike: a row in writes no row it does not make
  MakeTable(4, 4);
  before := SaveRtf;
  FRich.SelStart := CellStart(1, 1);
  AssertTrue('a row below', FRich.InsertRow(True));
  AssertTrue('the rows beside it as they were', (RowBytes(before, 1) = RowBytes(SaveRtf, 1)) and
    (RowBytes(before, 2) = RowBytes(SaveRtf, 3)));
end;

{ Rows 0 and 2 plain, row 1 holding a nested table: every cell-format door and every resize
  door on all three rows changes rows 0 and 2, leaves row 1 as it is, and says so once. }
procedure TTyRichTableFormatTest.TestARowWithANestedTableIsLeftAsItIs;
const
  Doc = '{\rtf1 \pard before\par' +
    '\trowd\cellx1440\cellx2880\pard\intbl a\cell \pard\intbl b\cell\row' +
    '\trowd\cellx1440\cellx2880\pard\intbl c\cell \pard\intbl\itap2 x' +
    '\nestcell{\*\nesttableprops\trowd\cellx500\nestrow}{\nonesttables\par}\pard\intbl\cell\row' +
    '\trowd\cellx1440\cellx2880\pard\intbl d\cell \pard\intbl e\cell\row' +
    '\pard after\par}';
  Doors = 9;
var
  st: TStringStream;
  k, r: Integer;
  before: RawByteString;
  was: array[0..2] of string;
  ok: Boolean;

  // a row's look: its cells' properties, its own, its edges
  function Look(ARow: Integer): string;
  var
    c: Integer;
    p: TTyRichCellProps;
    sd: TTyRowCellSide;
    e: TTyRichEdges;
  begin
    Result := Format('h%d l%d a%d', [RowP(ARow).HeightTwips, RowP(ARow).LeftTwips, Ord(RowP(ARow).Align)]);
    for c := 0 to 1 do
    begin
      p := Cell(ARow, c);
      Result := Result + Format(' |s%d v%d', [Integer(p.Shading), Ord(p.VAlign)]);
      for sd := Low(TTyRowCellSide) to High(TTyRowCellSide) do
        Result := Result + Format(' b%d,%d,%d p%d', [Ord(p.Borders[sd].Style), p.Borders[sd].WidthTwips,
          Integer(p.Borders[sd].Color), p.Pad[sd]]);
    end;
    FRich.Document.BeginRead;
    try
      e := FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(CellStart(ARow, 0))).Row.CellEdges;
    finally
      FRich.Document.EndRead;
    end;
    for c := 0 to High(e) do Result := Result + Format(' e%d', [e[c]]);
  end;

begin
  for k := 0 to Doors - 1 do
  begin
    st := TStringStream.Create(Doc);
    try
      FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    FRich.UpdateView;
    AssertTrue('(row 1 holds a nested table)', FRich.Document.CellAt(
      FRich.Document.Text.ParaOfPos(CellStart(1, 0))).Row.HoldsNestedTable);
    before := SaveRtf;
    for r := 0 to 2 do was[r] := Look(r);
    Sel(CellStart(0, 0), CellEnd(2, 1));
    FRich.Refusals.Clear;
    case k of
      0: ok := FRich.SetCellShading(clYellow);
      1: ok := FRich.SetCellBorders(rbpAll, TyRichBorder(rbsDouble, 30, clRed));
      2: ok := FRich.SetCellPadding(300, -1, -1, -1);
      3: ok := FRich.SetCellVAlign(rcvBottom);
      4: ok := FRich.SetRowHeight(600, False);
      5: ok := FRich.SetColumnWidth(2000);
      6: ok := FRich.DistributeRows;
      7: ok := FRich.FitTableToWindow;
    else
      ok := FRich.AutoFitColumn;
    end;
    AssertTrue(Format('%d: done', [k]), ok);
    AssertEquals(Format('%d: row 1 as it was', [k]), was[1], Look(1));
    AssertFalse(Format('%d: row 0 changed', [k]), was[0] = Look(0));
    AssertFalse(Format('%d: row 2 changed', [k]), was[2] = Look(2));
    AssertEquals(Format('%d: told once', [k]), 1, FRich.Refusals.Count);
    AssertEquals(Format('%d: why', [k]), rsRichEditRefusedResizeNested, FRich.Refusals[0]);
    AssertEquals(Format('%d: one step', [k]), 1, FRich.Document.UndoDepth);
    FRich.Undo;
    AssertTrue(Format('%d: undone', [k]), before = SaveRtf);
  end;
end;

{ DistributeRows lays out every row it reads: above the threshold the control's other long
  synchronous work uses (CopyWaitChars; a paragraph laid out counts as a hundred characters)
  the wait cursor shows meanwhile, put back after. }
procedure TTyRichTableFormatTest.TestDistributeRowsShowsTheWaitCursorWhenLong;
begin
  MakeTable(4, 4);
  FRich.SelStart := CellStart(1, 1);
  // sixteen paragraphs: 1600 against the threshold
  FRich.SetWaitChars(1600);
  FRich.Waits := 0;
  FRich.WaitsEnded := 0;
  FRich.DistributeRows;
  AssertEquals('at the threshold: none', 0, FRich.Waits);
  FRich.SetWaitChars(1599);
  FRich.DistributeRows;
  AssertEquals('above it: shown', 1, FRich.Waits);
  AssertEquals('and put back', 1, FRich.WaitsEnded);
end;

// OK on the form with nothing changed
procedure TTyRichTableFormatTest.PropsOk(Sender: TObject; var AProps: TTyRichTableProperties;
  var AAllow: Boolean);
begin
  FGot := AProps;
end;

// only the vertical alignment changed
procedure TTyRichTableFormatTest.PropsVAlign(Sender: TObject; var AProps: TTyRichTableProperties;
  var AAllow: Boolean);
begin
  FGot := AProps;
  AProps.VAlign := rcvBottom;
  AProps.Changed := [tpfVAlign];
end;

{ The properties action hands the selection's values over with the fields alike over every
  selected cell (Uniform); only the fields the handler changed (Changed) are applied - none:
  nothing, no undo step. }
procedure TTyRichTableFormatTest.TestTablePropertiesApplyOnlyWhatChanged;
var
  list: TActionList;
  pr: TTyRichEditTableProperties;
  before: RawByteString;
begin
  list := TActionList.Create(nil);
  try
    pr := TTyRichEditTableProperties.Create(list);
    pr.RichEdit := FRich;
    MakeTable(2, 2);
    FRich.SelStart := CellStart(0, 0);
    FRich.SetCellShading(clYellow);
    FRich.SelStart := CellStart(1, 1);
    FRich.SetCellShading(clAqua);
    FRich.SetCellPadding(300, -1, -1, -1);
    FRich.Document.ClearUndo;
    before := SaveRtf;
    FRich.SelectTable;
    pr.OnBeforeExecute := @PropsOk;
    pr.Execute;
    AssertFalse('the shading is mixed', tpfShading in FGot.Uniform);
    AssertFalse('the padding is mixed', tpfPadding in FGot.Uniform);
    AssertTrue('the alignment is alike', tpfVAlign in FGot.Uniform);
    AssertTrue('the rows'' height is alike', tpfRowHeight in FGot.Uniform);
    AssertTrue('nothing changed yet', FGot.Changed = []);
    AssertEquals('OK without a change: no step', 0, FRich.Document.UndoDepth);
    AssertTrue('OK without a change: the bytes as they were', before = SaveRtf);
    // one field changed: only that one
    FRich.SelectTable;
    pr.OnBeforeExecute := @PropsVAlign;
    pr.Execute;
    AssertEquals('one step', 1, FRich.Document.UndoDepth);
    AssertTrue('every cell at the bottom', (Cell(0, 0).VAlign = rcvBottom) and (Cell(1, 1).VAlign = rcvBottom));
    AssertEquals('its own shading kept', clYellow, Cell(0, 0).Shading);
    AssertEquals('its own shading kept too', clAqua, Cell(1, 1).Shading);
    AssertEquals('its own padding kept', 300, Cell(1, 1).Pad[rcsLeft]);
    AssertEquals('the other''s padding kept', 108, Cell(0, 0).Pad[rcsLeft]);
    // the door itself: nothing changed, nothing done
    FGot.Changed := [];
    AssertTrue('nothing to apply', FRich.ApplyTableProperties(FGot));
    AssertEquals('still one step', 1, FRich.Document.UndoDepth);
  finally
    list.Free;
  end;
end;

{ SetTableAlign(align) and the alignment action leave the indent as it is - a Word table's
  -108 twips stays -; SetTableAlign(align, indent) sets both. }
procedure TTyRichTableFormatTest.TestTableAlignLeavesTheIndent;
const
  WordRtf = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard before\par' +
    '\trowd\trgaph108\trleft-108\cellx1440\cellx2880\pard\intbl a0\cell a1\cell\row' +
    '\pard after\par}';
var
  st: TStringStream;
  list: TActionList;
  al: TTyRichEditTableAlign;
begin
  st := TStringStream.Create(WordRtf);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.SelStart := CellStart(0, 0) + 1;
  AssertEquals('Word''s indent', -108, RowP(0).LeftTwips);
  AssertTrue('centred', FRich.SetTableAlign(rraCenter));
  AssertTrue('left again', FRich.SetTableAlign(rraLeft));
  AssertEquals('the indent as it was', -108, RowP(0).LeftTwips);
  list := TActionList.Create(nil);
  try
    al := TTyRichEditTableAlign.Create(list);
    al.RichEdit := FRich;
    al.Align := rraRight;
    al.Execute;
    AssertTrue('the action: right', RowP(0).Align = rraRight);
    AssertEquals('the action: the indent as it was', -108, RowP(0).LeftTwips);
  finally
    list.Free;
  end;
  AssertTrue('both', FRich.SetTableAlign(rraLeft, 0));
  AssertEquals('the indent set', 0, RowP(0).LeftTwips);
end;

{ The builder's Row takes twips, as every table measure; a negative height, width or padding
  raises its misuse error. }
procedure TTyRichTableFormatTest.TestTheBuildersRowIsInTwipsAndMisuseRaises;
var
  B: TTyRichBuilder;
  k: Integer;
  raised: Boolean;
begin
  B := TTyRichBuilder.Create;
  try
    B.Text('before').Paragraph;
    B.Table([1440, 1440]).Cell.Text('a').Cell.Text('b');
    B.Row(600).Cell.Text('c').Cell.Text('d');
    B.Row(500, True).Cell.Text('e').Cell.Text('f').EndTable;
    B.Text('after');
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  AssertEquals('at least 600 twips', 600, RowP(1).HeightTwips);
  AssertEquals('exactly 500 twips', -500, RowP(2).HeightTwips);
  for k := 0 to 2 do
  begin
    raised := False;
    B := TTyRichBuilder.Create;
    try
      try
        B.Table([1440]).Cell.Text('a');
        case k of
          0: B.Row(-5);
          1: B.CellPadding(-7, 0, 0, 0);
        else
          B.CellBorders([rcsTop], rbsSingle, -1);
        end;
      except
        on E: ETyRichEdit do raised := True;
      end;
    finally
      B.Free;
    end;
    AssertTrue(Format('%d: a negative measure raises', [k]), raised);
  end;
end;

function TTyRichTableFormatTest.Disagreement: string;
var
  r, c, n, b: Integer;
  ea, eb: TTyRichEdges;
  la, lb: Integer;

  function EdgesOf(ARow: Integer; out ALeft: Integer): TTyRichEdges;
  begin
    FRich.Document.BeginRead;
    try
      Result := FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(CellStart(ARow, 0))).Row.CellEdges;
    finally
      FRich.Document.EndRead;
    end;
    ALeft := RowP(ARow).LeftTwips;
  end;

begin
  Result := '';
  n := RowCount;
  for r := 0 to n - 1 do
  begin
    ea := EdgesOf(r, la);
    for c := 0 to High(ea) - 1 do
      if not TyRichSameBorder(Cell(r, c).Borders[rcsRight], Cell(r, c + 1).Borders[rcsLeft]) then
        Exit(Format('%d,%d right / %d,%d left', [r, c, r, c + 1]));
    if r = n - 1 then Continue;
    eb := EdgesOf(r + 1, lb);
    for c := 0 to High(ea) do
    begin
      b := TyRichFacingCell(ea, la, c, eb, lb);
      if (b >= 0) and not TyRichSameBorder(Cell(r, c).Borders[rcsBottom], Cell(r + 1, b).Borders[rcsTop]) then
        Exit(Format('%d,%d bottom / %d,%d top', [r, c, r + 1, b]));
    end;
  end;
end;

{ A column's edge dragged in one row and back: the two rows' cells line up again and the
  sides that now face each other agree - the line drawn there stays. }
procedure TTyRichTableFormatTest.TestEdgesLinedUpAgainShareOneDefinition;
var
  red: TTyRichBorder;
begin
  red := TyRichBorder(rbsSingle, 30, clRed);
  MakeTable(2, 2);
  // (the first cell of row 0 selected: its width, in that row alone)
  Sel(CellStart(0, 0), CellEnd(0, 0));
  AssertTrue('row 0''s first cell wider', FRich.SetColumnWidth(1740));
  FRich.SelStart := CellStart(1, 0) + 1;
  AssertTrue('cell 1,0''s top', FRich.SetCellBorders(rbpTop, red));
  AssertFalse('the cell above lies wider: its own bottom', TyRichSameBorder(Cell(0, 0).Borders[rcsBottom], red));
  Sel(CellStart(0, 0), CellEnd(0, 0));
  AssertTrue('back to 1440', FRich.SetColumnWidth(1440));
  AssertTrue('lined up again: one definition', TyRichSameBorder(Cell(0, 0).Borders[rcsBottom], red));
  AssertEquals('nowhere two', '', Disagreement);
end;

{ A walk of a few hundred random operations - border presets on random cells, rows and
  columns in and out, widths set on random rows (lining edges up and parting them), undo -
  never leaves a line two cells wholly share with two definitions. }
procedure TTyRichTableFormatTest.TestARandomWalkLeavesNoLineWithTwoDefinitions;
const
  Seeds: array[0..2] of Integer = (7, 2026, 31337);
  Steps = 70;
var
  sd, k, r0, c0, r1, c1, op, rows, cols: Integer;
  b: TTyRichBorder;
  what, bad: string;
begin
  for sd := 0 to High(Seeds) do
  begin
    RandSeed := Seeds[sd];
    MakeTable(4, 4);
    for k := 1 to Steps do
    begin
      rows := RowCount;
      cols := ColCount(0);
      r0 := Random(rows);
      c0 := Random(Math.Min(cols, ColCount(r0)));
      r1 := Math.Min(rows - 1, r0 + Random(2));
      c1 := Math.Min(ColCount(r1) - 1, c0 + Random(2));
      if c1 < 0 then c1 := 0;
      op := Random(10);
      what := Format('seed %d, step %d, op %d at %d,%d..%d,%d', [Seeds[sd], k, op, r0, c0, r1, c1]);
      case op of
        0..3:
          begin
            if Random(3) = 0 then b := TyRichBorder(rbsNone, 0)
            else b := TyRichBorder(TTyRichBorderStyle(1 + Random(4)), 10 + 10 * Random(3), clRed);
            Sel(CellStart(r0, Math.Min(c0, ColCount(r0) - 1)), CellEnd(r1, Math.Min(c1, ColCount(r1) - 1)));
            FRich.SetCellBorders(TTyRichBorderPreset(Random(10)), b);
          end;
        4:
          begin
            FRich.SelStart := CellStart(r0, 0) + 1;
            if rows < 7 then FRich.InsertRow(Random(2) = 0);
          end;
        5:
          begin
            FRich.SelStart := CellStart(r0, 0) + 1;
            if rows > 2 then FRich.DeleteRow;
          end;
        6:
          begin
            Sel(CellStart(r0, 0), CellEnd(r0, ColCount(r0) - 1));
            FRich.SetColumnWidth(1440 + 300 * (Random(3) - 1));
          end;
        7:
          begin
            FRich.SelStart := CellStart(r0, 0) + 1;
            FRich.SetColumnWidth(1440 + 300 * (Random(3) - 1));
          end;
        8:
          if FRich.Document.CanUndo then FRich.Undo;
      else
        begin
          FRich.SelStart := CellStart(0, 0) + 1;
          if (cols < 6) and (Random(2) = 0) then FRich.InsertColumn(True)
          else if cols > 2 then FRich.DeleteColumn;
        end;
      end;
      bad := Disagreement;
      AssertEquals(what, '', bad);
    end;
  end;
end;

// the outline's top double red, the inner horizontal lines dashed, and the alignment
procedure TTyRichTableFormatTest.PropsLines(Sender: TObject; var AProps: TTyRichTableProperties;
  var AAllow: Boolean);
begin
  FGot := AProps;
  AProps.Lines[rclTop] := TyRichBorder(rbsDouble, 30, clRed);
  AProps.Lines[rclInsideH] := TyRichBorder(rbsDashed, 20, clBlue);
  AProps.VAlign := rcvCenter;
  AProps.Changed := [tpfLineTop, tpfLineInsideH, tpfVAlign];
end;

{ Select Cell / Row / Column / Table as actions: enabled by the control's own answer in a
  table, off outside one; each selects what it says. }
procedure TTyRichTableFormatTest.TestTheSelectActions;
var
  list: TActionList;
  ac: array[0..3] of TTyRichEditAction;
  k: Integer;
  g: TTyRichCellRange;
begin
  list := TActionList.Create(nil);
  try
    ac[0] := TTyRichEditSelectCell.Create(list);
    ac[1] := TTyRichEditSelectRow.Create(list);
    ac[2] := TTyRichEditSelectColumn.Create(list);
    ac[3] := TTyRichEditSelectTable.Create(list);
    for k := 0 to 3 do ac[k].RichEdit := FRich;
    MakeTable(3, 3);
    FRich.SelStart := 1;
    for k := 0 to 3 do
    begin
      ac[k].Update;
      AssertFalse(Format('%d: off outside a table', [k]), ac[k].Enabled);
    end;
    for k := 0 to 3 do
    begin
      FRich.SelStart := CellStart(1, 1) + 1;
      ac[k].Update;
      AssertTrue(Format('%d: on in a table', [k]), ac[k].Enabled);
      AssertEquals(Format('%d: the control''s answer', [k]), FRich.CanSelectCells, ac[k].Enabled);
      ac[k].Execute;
      g := FRich.SelectedCells;
      AssertTrue(Format('%d: cells', [k]), g.InTable);
      case k of
        0: AssertTrue('a cell', (g.Row0 = 1) and (g.Row1 = 1) and (g.Col0 = 1) and (g.Col1 = 1));
        1: AssertTrue('a row', (g.Row0 = 1) and (g.Row1 = 1) and (g.Col0 = 0) and (g.Col1 = 2));
        2: AssertTrue('a column', (g.Row0 = 0) and (g.Row1 = 2) and (g.Col0 = 1) and (g.Col1 = 1));
      else
        AssertTrue('the table', g.WholeTable);
      end;
    end;
  finally
    list.Free;
  end;
end;

{ The table properties carry the lines too - the outline's four sides and the inner lines,
  with the same Uniform / Changed sets -: the whole form is one undo step, and a line given
  goes to the facing side of the cell beside it as every border door's. }
procedure TTyRichTableFormatTest.TestTablePropertiesSetLinesInTheSameStep;
var
  list: TActionList;
  pr: TTyRichEditTableProperties;
  v: TTyRichTableProperties;
  dbl, dash: TTyRichBorder;
begin
  dbl := TyRichBorder(rbsDouble, 30, clRed);
  dash := TyRichBorder(rbsDashed, 20, clBlue);
  list := TActionList.Create(nil);
  try
    pr := TTyRichEditTableProperties.Create(list);
    pr.RichEdit := FRich;
    pr.OnBeforeExecute := @PropsLines;
    MakeTable(4, 3);
    Sel(CellStart(1, 0), CellStart(2, 1) + 1);
    pr.Execute;
    AssertTrue('the lines were alike', (tpfLineTop in FGot.Uniform) and (tpfLineInsideH in FGot.Uniform));
    AssertTrue('a single line', FGot.Lines[rclTop].Style = rbsSingle);
    AssertEquals('one step', 1, FRich.Document.UndoDepth);
    AssertTrue('the top: 1,0', TyRichSameBorder(Cell(1, 0).Borders[rcsTop], dbl));
    AssertTrue('the top: 1,1', TyRichSameBorder(Cell(1, 1).Borders[rcsTop], dbl));
    AssertFalse('not 1,2', TyRichSameBorder(Cell(1, 2).Borders[rcsTop], dbl));
    AssertTrue('the facing side above', TyRichSameBorder(Cell(0, 0).Borders[rcsBottom], dbl));
    AssertTrue('inside: 1,0 bottom', TyRichSameBorder(Cell(1, 0).Borders[rcsBottom], dash));
    AssertTrue('inside: 2,1 top', TyRichSameBorder(Cell(2, 1).Borders[rcsTop], dash));
    AssertFalse('not the outline''s bottom', TyRichSameBorder(Cell(2, 0).Borders[rcsBottom], dash));
    AssertTrue('the alignment in the same step', Cell(2, 1).VAlign = rcvCenter);
    // read back
    Sel(CellStart(1, 0), CellStart(2, 1) + 1);
    AssertTrue('read', FRich.GetTableProperties(v));
    AssertTrue('the top alike', (tpfLineTop in v.Uniform) and TyRichSameBorder(v.Lines[rclTop], dbl));
    AssertTrue('the inner lines alike', (tpfLineInsideH in v.Uniform) and TyRichSameBorder(v.Lines[rclInsideH], dash));
    FRich.Undo;
    AssertFalse('undone in one', TyRichSameBorder(Cell(1, 0).Borders[rcsTop], dbl));
  finally
    list.Free;
  end;
end;

{ The cell alignment and table alignment actions are checked when the selection's cells (the
  table) all have their alignment, not when it is mixed. }
procedure TTyRichTableFormatTest.TestAlignmentActionsAreCheckedWhenAllAlike;
var
  list: TActionList;
  va: TTyRichEditCellVAlign;
  ta: TTyRichEditTableAlign;
begin
  list := TActionList.Create(nil);
  try
    va := TTyRichEditCellVAlign.Create(list);
    va.RichEdit := FRich;
    va.Align := rcvBottom;
    ta := TTyRichEditTableAlign.Create(list);
    ta.RichEdit := FRich;
    ta.Align := rraCenter;
    MakeTable(2, 2);
    FRich.SelStart := CellStart(0, 0) + 1;
    FRich.SelectTable;
    va.Update;
    ta.Update;
    AssertFalse('not at the bottom yet', va.Checked);
    AssertFalse('not centred yet', ta.Checked);
    FRich.SetCellVAlign(rcvBottom);
    FRich.SetTableAlign(rraCenter);
    FRich.SelStart := CellStart(0, 0) + 1;
    FRich.SelectTable;
    va.Update;
    ta.Update;
    AssertTrue('all at the bottom', va.Checked);
    AssertTrue('centred', ta.Checked);
    FRich.SelStart := CellStart(1, 1) + 1;
    FRich.SetCellVAlign(rcvTop);
    FRich.SelStart := CellStart(0, 0) + 1;
    FRich.SelectTable;
    va.Update;
    AssertFalse('mixed: not checked', va.Checked);
  finally
    list.Free;
  end;
end;

{ As Word: a width given with several columns selected goes to each of them, a row height to
  each selected row, a fit to each selected column - one undo step each. }
procedure TTyRichTableFormatTest.TestWidthsAndHeightsOverEverySelectedColumnAndRow;
var
  e: TTyRichEdges;

  function EdgesOf(ARow: Integer): TTyRichEdges;
  begin
    FRich.Document.BeginRead;
    try
      Result := FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(CellStart(ARow, 0))).Row.CellEdges;
    finally
      FRich.Document.EndRead;
    end;
  end;

begin
  MakeTable(3, 4);
  Sel(CellStart(0, 1), CellStart(2, 2) + 1);
  AssertTrue('widths', FRich.SetColumnWidth(2000));
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  e := EdgesOf(1);
  AssertEquals('column 0 as it was', 1440, e[0] - RowP(1).LeftTwips);
  AssertEquals('column 1', 2000, e[1] - e[0]);
  AssertEquals('column 2', 2000, e[2] - e[1]);
  AssertEquals('column 3 as it was', 1440, e[3] - e[2]);
  FRich.Undo;
  // a height to every selected row
  Sel(CellStart(0, 0), CellStart(1, 1) + 1);
  AssertTrue('heights', FRich.SetRowHeight(700, False));
  AssertEquals('row 0', 700, RowP(0).HeightTwips);
  AssertEquals('row 1', 700, RowP(1).HeightTwips);
  AssertEquals('row 2 as it was', 0, RowP(2).HeightTwips);
  FRich.Undo;
  // a fit to each selected column, by its own content
  FRich.Document.Execute(TTyRichInsertText.Create(CellStart(1, 2), 'a much longer text in here'));
  FRich.Document.ClearUndo;
  Sel(CellStart(0, 1), CellStart(2, 2) + 1);
  AssertTrue('fitted', FRich.AutoFitColumn);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  e := EdgesOf(1);
  AssertTrue(Format('column 2 wider than column 1 (%d, %d)', [e[2] - e[1], e[1] - e[0]]),
    e[2] - e[1] > e[1] - e[0]);
  AssertTrue('column 1 fitted to its short text', e[1] - e[0] < 1440);
end;

initialization
  RegisterTest(TTyRichTableFormatTest);
end.
