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
  Classes, SysUtils, Graphics, Controls, Forms, LCLType, ActnList, fpcunit, testregistry,
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
    destructor Destroy; override;
    procedure Refused(Sender: TObject; const AReason: string);
  end;

  TTyRichTableFormatTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TFmtRich;
    FBordersAsked, FPropsAsked: Integer;
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
    { The three ranges: the caret in cell 1,1 (AKind 0); cells 1,1 .. 2,2 (1); every cell (2). }
    procedure Range(AKind: Integer; out AR0, AC0, AR1, AC1: Integer);
    function InRange(ARow, ACol, AR0, AC0, AR1, AC1: Integer): Boolean;
    { Row ARow's definition as written: its bytes in ARtf (between its \trowd and \row). }
    function RowBytes(const ARtf: RawByteString; ARow: Integer): RawByteString;
    procedure CheckUntouchedRows(const AWhat: string; const ABefore: RawByteString; AR0, AR1: Integer);
    procedure BordersAsk(Sender: TObject; var APreset: TTyRichBorderPreset;
      var ABorder: TTyRichBorder; var AAllow: Boolean);
    procedure PropsAsk(Sender: TObject; var AProps: TTyRichTableProperties; var AAllow: Boolean);
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
          if InRange(r, c, r0, c0, r1, c1) then
            AssertTrue(Format('%d: cell %d,%d side %d', [k, r, c, Ord(sd)]),
              TyRichSameBorder(p.Borders[sd], TyRichBorder(rbsDouble, 30, clRed)))
          else
            AssertTrue(Format('%d: cell %d,%d side %d as it was', [k, r, c, Ord(sd)]),
              p.Borders[sd].Style = rbsSingle);
      end;
    CheckUntouchedRows(Format('borders %d', [k]), before, r0, r1);
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

procedure TTyRichTableFormatTest.TestPresetsTouchTheRightSides;
var
  r, c: Integer;
  b: TTyRichBorder;

  function Red(ARow, ACol: Integer; ASide: TTyRowCellSide): Boolean;
  begin
    Result := TyRichSameBorder(Cell(ARow, ACol).Borders[ASide], b);
  end;

  procedure Apply(APreset: TTyRichBorderPreset);
  begin
    MakeTable(5, 5);
    Sel(CellStart(1, 1), CellEnd(3, 3));
    AssertTrue('applied', FRich.SetCellBorders(APreset, b));
  end;

  function Inside(ARow, ACol: Integer): Boolean;
  begin
    Result := (ARow >= 1) and (ARow <= 3) and (ACol >= 1) and (ACol <= 3);
  end;

begin
  b := TyRichBorder(rbsSingle, 40, clRed);
  // inside horizontal: only the edges between the selected rows
  Apply(rbpInsideH);
  for r := 0 to 4 do
    for c := 0 to 4 do
    begin
      AssertEquals(Format('insideH %d,%d bottom', [r, c]), Inside(r, c) and (r < 3), Red(r, c, rcsBottom));
      AssertEquals(Format('insideH %d,%d top', [r, c]), Inside(r, c) and (r > 1), Red(r, c, rcsTop));
      AssertFalse(Format('insideH %d,%d left', [r, c]), Red(r, c, rcsLeft));
      AssertFalse(Format('insideH %d,%d right', [r, c]), Red(r, c, rcsRight));
    end;
  // inside vertical
  Apply(rbpInsideV);
  for r := 0 to 4 do
    for c := 0 to 4 do
    begin
      AssertEquals(Format('insideV %d,%d right', [r, c]), Inside(r, c) and (c < 3), Red(r, c, rcsRight));
      AssertEquals(Format('insideV %d,%d left', [r, c]), Inside(r, c) and (c > 1), Red(r, c, rcsLeft));
      AssertFalse(Format('insideV %d,%d top', [r, c]), Red(r, c, rcsTop));
    end;
  // outside: the rectangle's outline only
  Apply(rbpOutside);
  for r := 0 to 4 do
    for c := 0 to 4 do
    begin
      AssertEquals(Format('outside %d,%d top', [r, c]), Inside(r, c) and (r = 1), Red(r, c, rcsTop));
      AssertEquals(Format('outside %d,%d bottom', [r, c]), Inside(r, c) and (r = 3), Red(r, c, rcsBottom));
      AssertEquals(Format('outside %d,%d left', [r, c]), Inside(r, c) and (c = 1), Red(r, c, rcsLeft));
      AssertEquals(Format('outside %d,%d right', [r, c]), Inside(r, c) and (c = 3), Red(r, c, rcsRight));
    end;
  // inside: both
  Apply(rbpInside);
  AssertTrue('inside: a horizontal one', Red(1, 2, rcsBottom));
  AssertTrue('inside: a vertical one', Red(2, 1, rcsRight));
  AssertFalse('inside: not the outline', Red(1, 1, rcsTop) or Red(1, 1, rcsLeft));
  // one side each
  Apply(rbpTop);
  AssertTrue('top', Red(1, 2, rcsTop) and not Red(2, 2, rcsTop) and not Red(1, 2, rcsBottom));
  Apply(rbpBottom);
  AssertTrue('bottom', Red(3, 2, rcsBottom) and not Red(2, 2, rcsBottom));
  Apply(rbpLeft);
  AssertTrue('left', Red(2, 1, rcsLeft) and not Red(2, 2, rcsLeft));
  Apply(rbpRight);
  AssertTrue('right', Red(2, 3, rcsRight) and not Red(2, 2, rcsRight));
  // all, then none
  Apply(rbpAll);
  AssertTrue('all', Red(2, 2, rcsTop) and Red(2, 2, rcsLeft) and Red(1, 1, rcsTop) and not Red(0, 0, rcsBottom));
  Sel(CellStart(1, 1), CellEnd(3, 3));
  AssertTrue('none', FRich.SetCellBorders(rbpNone, b));
  AssertTrue('none: no line', Cell(2, 2).Borders[rcsTop].Style = rbsNone);
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
  AProps.Valid := [tpfRowHeight, tpfShading, tpfVAlign];
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
    B.Row(30, True).Cell.Text('d').CellVAlign(rcvCenter).Cell.Text('e').Cell.Text('f');
    B.Row(20).Cell.Text('g').Cell.Text('h').Cell.Text('i').EndTable;
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

initialization
  RegisterTest(TTyRichTableFormatTest);
end.
