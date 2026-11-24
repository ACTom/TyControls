unit test.richedit.tableresize;

{ Column widths and row heights (TTyRichSetColumnEdge, TTyRichSetRowWidths and the control's
  edge drags): a column's edge dragged - the cells either side trade width, with Shift the
  rest follows, the last edge changes the table's width -, only the selected rows when cells
  are selected, a cell never narrower than its padding and a character, a double click's fit,
  a row's bottom at least where it is dropped, Esc and a release that moved nothing, Word's
  rows that share an edge within 15 twips, one undo step and the file's bytes back, the
  ruler's column markers, and a drag that lays nothing out. A control with the test device;
  no window. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.Controller, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.TableProps, tyControls.RichEdit.RtfRead,
  tyControls.RichEdit.Layout, tyControls.RichEdit, tyControls.RichEdit.Ruler,
  tyControls.StrConsts, test.richedit.layoutdevice;

type
  TIntArray = array of Integer;

  TResizeRich = class(TTyRichEdit)
  protected
    function CreateDevice: TTyRichTextDevice; override;
  public
    Refusals: TStringList;
    destructor Destroy; override;
    procedure Refused(Sender: TObject; const AReason: string);
    procedure Press(X, Y: Integer; AShift: TShiftState = []);
    procedure MoveTo(X, Y: Integer; AShift: TShiftState = [ssLeft]);
    procedure Release(X, Y: Integer; AShift: TShiftState = []);
    procedure Key(AKey: Word; AShift: TShiftState = []);
    function CursorAtPoint(X, Y: Integer): TCursor;
  end;

  TResizeRuler = class(TTyRichEditRuler)
  public
    procedure Press(X, Y: Integer; AShift: TShiftState = []);
    procedure MoveTo(X, Y: Integer; AShift: TShiftState = []);
    procedure Release(X, Y: Integer; AShift: TShiftState = []);
    function EdgeMid(AIndex: Integer): TPoint;
    function EdgeShown(AIndex: Integer): Boolean;
    function EditOffsetNow: Integer;
  end;

  TTyRichTableResizeTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TResizeRich;
    procedure MakeTable(ARows, ACols: Integer);
    procedure LoadRtf(const S: RawByteString);
    function SaveRtf: RawByteString;
    function CellStart(ARow, ACol: Integer): TTyRichPos;
    function CellEnd(ARow, ACol: Integer): TTyRichPos;
    function RowAt(ARow: Integer): TTyRichRow;
    function EdgesOf(ARow: Integer): TTyRichEdges;
    function RowY(ARow: Integer): Integer;
    // the client x of every column edge band along client y AY, left to right
    function Bands(AY: Integer): TIntArray;
    function RowBottomY(ARow: Integer): Integer;
    procedure Sel(AAnchor, ACaret: TTyRichPos);
    procedure Drag(AX, AY, ADX, ADY: Integer; AShift: TShiftState = []);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDragMovesOneEdgeAndKeepsTheTableWidth;
    procedure TestShiftDragShiftsTheRest;
    procedure TestTheLastEdgeChangesTheTable;
    procedure TestTheLeftEdgeMovesTheTablesStart;
    procedure TestOnlySelectedRowsWhenCellsAreSelected;
    procedure TestAnEdgeOutsideTheSelectedRowsIsItsOwn;
    procedure TestAWidthOfAFilesRowIsSaved;
    procedure TestAShiftDragPassesTheNextCellsLeast;
    procedure TestARowsBottomAnswersOnlyNearTheTable;
    procedure TestMinimumWidth;
    procedure TestDoubleClickFitsTheColumn;
    procedure TestRowEdgeSetsAtLeast;
    procedure TestEscAndNoMoveChangeNothing;
    procedure TestIrregularRowsMoveBySharedEdges;
    procedure TestOneUndoStepAndBytesBack;
    procedure TestTheRulerShowsAndDragsColumnEdges;
    procedure TestAMoveDrawsOnlyTheGuide;
    procedure TestTheUserDoors;
    procedure TestANestedRowAndAPartOfALongFileAreRefused;
    procedure TestEdgesWithin15TwipsAreOne;
    procedure TestTheViewStaysWhereItWas;
    procedure TestAPageAsTallAsItsContentFollows;
    procedure TestADisplayPageAndAViewerOfferNothing;
  end;

implementation

const
  BS = '\';

function FixtureBytes(const AName: string): RawByteString;
var
  f: TFileStream;
begin
  Result := '';
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[1], f.Size);
  finally
    f.Free;
  end;
end;

{ ---- the control ---- }

function TResizeRich.CreateDevice: TTyRichTextDevice;
begin
  Result := TTyRichTestDevice.Create;
end;

destructor TResizeRich.Destroy;
begin
  Refusals.Free;
  inherited Destroy;
end;

procedure TResizeRich.Refused(Sender: TObject; const AReason: string);
begin
  Refusals.Add(AReason);
end;

procedure TResizeRich.Press(X, Y: Integer; AShift: TShiftState);
begin
  MouseDown(mbLeft, AShift + [ssLeft], X, Y);
end;

procedure TResizeRich.MoveTo(X, Y: Integer; AShift: TShiftState);
begin
  MouseMove(AShift, X, Y);
end;

procedure TResizeRich.Release(X, Y: Integer; AShift: TShiftState);
begin
  MouseUp(mbLeft, AShift, X, Y);
end;

procedure TResizeRich.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

function TResizeRich.CursorAtPoint(X, Y: Integer): TCursor;
begin
  Result := CursorAt(X, Y);
end;

procedure TResizeRuler.Press(X, Y: Integer; AShift: TShiftState);
begin
  MouseDown(mbLeft, AShift + [ssLeft], X, Y);
end;

procedure TResizeRuler.MoveTo(X, Y: Integer; AShift: TShiftState);
begin
  MouseMove(AShift + [ssLeft], X, Y);
end;

procedure TResizeRuler.Release(X, Y: Integer; AShift: TShiftState);
begin
  MouseUp(mbLeft, AShift, X, Y);
end;

function TResizeRuler.EdgeMid(AIndex: Integer): TPoint;
var
  r: TRect;
begin
  if not MarkerRect(rmkColumnEdge, AIndex, r) then raise Exception.Create('the edge is not shown');
  Result := Point(MarkerX(rmkColumnEdge, AIndex), (r.Top + r.Bottom) div 2);
end;

function TResizeRuler.EdgeShown(AIndex: Integer): Boolean;
var
  r: TRect;
begin
  Result := MarkerRect(rmkColumnEdge, AIndex, r);
end;

function TResizeRuler.EditOffsetNow: Integer;
begin
  Result := EditOffset;
end;

{ ---- the fixture ---- }

procedure TTyRichTableResizeTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TResizeRich.Create(nil);
  FRich.Refusals := TStringList.Create;
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 700, 400);
  FRich.OnEditRefused := @FRich.Refused;
end;

procedure TTyRichTableResizeTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

// 'before', an ARows x ACols table of 'rNcM' (1440 twips a cell), 'after'
procedure TTyRichTableResizeTest.MakeTable(ARows, ACols: Integer);
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

procedure TTyRichTableResizeTest.LoadRtf(const S: RawByteString);
var
  st: TStringStream;
begin
  st := TStringStream.Create(S);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
end;

function TTyRichTableResizeTest.SaveRtf: RawByteString;
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

function TTyRichTableResizeTest.CellStart(ARow, ACol: Integer): TTyRichPos;
var
  f, l: Integer;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  Result := FRich.Document.Text.ParaStart(f);
end;

function TTyRichTableResizeTest.CellEnd(ARow, ACol: Integer): TTyRichPos;
var
  f, l: Integer;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  Result := FRich.Document.Text.ParaStart(l) + FRich.Document.Text.ParaLength(l) + 1;
end;

function TTyRichTableResizeTest.RowAt(ARow: Integer): TTyRichRow;
begin
  Result := FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(CellStart(ARow, 0))).Row;
end;

function TTyRichTableResizeTest.EdgesOf(ARow: Integer): TTyRichEdges;
begin
  Result := RowAt(ARow).CellEdges;
end;

function TTyRichTableResizeTest.RowY(ARow: Integer): Integer;
var
  r: TRect;
begin
  r := FRich.PositionRect(CellStart(ARow, 0), False);
  Result := (r.Top + r.Bottom) div 2;
end;

function TTyRichTableResizeTest.Bands(AY: Integer): TIntArray;
var
  x, start: Integer;
begin
  Result := nil;
  start := -1;
  for x := 0 to FRich.Width do
    if (x < FRich.Width) and (FRich.CursorAtPoint(x, AY) = crSizeWE) then
    begin
      if start < 0 then start := x;
    end
    else if start >= 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := (start + x - 1) div 2;
      start := -1;
    end;
end;

function TTyRichTableResizeTest.RowBottomY(ARow: Integer): Integer;
var
  y, x, start: Integer;
begin
  x := Bands(RowY(ARow))[0] + 20;
  start := -1;
  for y := RowY(ARow) to FRich.Height - 1 do
    if FRich.CursorAtPoint(x, y) = crSizeNS then
    begin
      if start < 0 then start := y;
    end
    else if start >= 0 then
      Exit((start + y - 1) div 2);
  Result := -1;
end;

procedure TTyRichTableResizeTest.Sel(AAnchor, ACaret: TTyRichPos);
begin
  FRich.SelStart := AAnchor;
  FRich.SelLength := ACaret - AAnchor;
end;

procedure TTyRichTableResizeTest.Drag(AX, AY, ADX, ADY: Integer; AShift: TShiftState);
begin
  FRich.Press(AX, AY, AShift);
  FRich.MoveTo(AX + ADX div 2, AY + ADY div 2, AShift + [ssLeft]);
  FRich.MoveTo(AX + ADX, AY + ADY, AShift + [ssLeft]);
  FRich.Release(AX + ADX, AY + ADY, AShift);
end;

{ ---- column edges ---- }

procedure TTyRichTableResizeTest.TestDragMovesOneEdgeAndKeepsTheTableWidth;
var
  b: TIntArray;
  e0, e: TTyRichEdges;
  r: Integer;
begin
  MakeTable(3, 3);
  b := Bands(RowY(1));
  AssertEquals('four edges', 4, Length(b));
  AssertEquals('a column''s edge: east-west', crSizeWE, FRich.CursorAtPoint(b[1], RowY(1)));
  e0 := EdgesOf(1);
  Drag(b[1], RowY(1), 30, 0);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  for r := 0 to 2 do
  begin
    e := EdgesOf(r);
    AssertTrue(Format('row %d: the edge moved (%d)', [r, e[0]]), Abs(e[0] - (e0[0] + 450)) <= 15);
    AssertEquals(Format('row %d: the next edge stays', [r]), e0[1], e[1]);
    AssertEquals(Format('row %d: the table''s width stays', [r]), e0[2], e[2]);
  end;
  // the edge where it went: under the pointer
  b := Bands(RowY(1));
  AssertTrue(Format('drawn there (%d)', [b[1]]), Abs(b[1] - (30 + Bands(RowY(0))[1] - 30)) <= 1);
end;

procedure TTyRichTableResizeTest.TestShiftDragShiftsTheRest;
var
  b: TIntArray;
  e0, e: TTyRichEdges;
  r: Integer;
begin
  MakeTable(3, 3);
  b := Bands(RowY(0));
  e0 := EdgesOf(0);
  Drag(b[1], RowY(0), 30, 0, [ssShift]);
  for r := 0 to 2 do
  begin
    e := EdgesOf(r);
    AssertTrue(Format('row %d: its edge', [r]), Abs(e[0] - (e0[0] + 450)) <= 15);
    AssertEquals(Format('row %d: the next cell keeps its width', [r]), e0[1] - e0[0], e[1] - e[0]);
    AssertEquals(Format('row %d: the table wider', [r]), e0[2] + (e[0] - e0[0]), e[2]);
  end;
  // narrower with Shift: the rest follows to the left
  b := Bands(RowY(0));
  e0 := EdgesOf(0);
  Drag(b[1], RowY(0), -20, 0, [ssShift]);
  e := EdgesOf(2);
  AssertTrue('narrower', Abs(e[0] - (e0[0] - 300)) <= 15);
  AssertEquals('the last cell keeps its width', e0[2] - e0[1], e[2] - e[1]);
end;

procedure TTyRichTableResizeTest.TestTheLastEdgeChangesTheTable;
var
  b: TIntArray;
  e0, e: TTyRichEdges;
begin
  MakeTable(2, 3);
  b := Bands(RowY(0));
  e0 := EdgesOf(0);
  Drag(b[3], RowY(0), 40, 0);
  e := EdgesOf(1);
  AssertEquals('the first edge stays', e0[0], e[0]);
  AssertEquals('the second edge stays', e0[1], e[1]);
  AssertTrue(Format('the table''s right edge (%d)', [e[2]]), Abs(e[2] - (e0[2] + 600)) <= 15);
  // narrower: no further than the last cell's least width
  b := Bands(RowY(0));
  Drag(b[3], RowY(0), -300, 0);
  e := EdgesOf(0);
  AssertTrue('the last cell kept a width', e[2] - e[1] >= 216);
end;

procedure TTyRichTableResizeTest.TestTheLeftEdgeMovesTheTablesStart;
var
  b: TIntArray;
  e0, e: TTyRichEdges;
  l0: Integer;
begin
  MakeTable(2, 2);
  b := Bands(RowY(0));
  e0 := EdgesOf(0);
  l0 := RowAt(0).Format.Row.LeftTwips;
  Drag(b[0], RowY(0), 20, 0);
  e := EdgesOf(1);
  AssertTrue('the start moved', Abs(RowAt(1).Format.Row.LeftTwips - (l0 + 300)) <= 15);
  AssertEquals('the first cell''s right edge stays', e0[0], e[0]);
  AssertEquals('the table''s right edge stays', e0[1], e[1]);
  // with Shift: the whole table moves
  b := Bands(RowY(0));
  e0 := EdgesOf(0);
  l0 := RowAt(0).Format.Row.LeftTwips;
  Drag(b[0], RowY(0), 20, 0, [ssShift]);
  e := EdgesOf(0);
  AssertTrue('the start moved again', Abs(RowAt(0).Format.Row.LeftTwips - (l0 + 300)) <= 15);
  AssertEquals('the cells moved with it', e0[1] - e0[0], e[1] - e[0]);
  AssertEquals('the cells moved with it: by as much', RowAt(0).Format.Row.LeftTwips - l0, e[0] - e0[0]);
end;

procedure TTyRichTableResizeTest.TestOnlySelectedRowsWhenCellsAreSelected;
var
  b: TIntArray;
  e0, e: TTyRichEdges;
begin
  MakeTable(4, 3);
  e0 := EdgesOf(0);
  // rows 1 and 2, the first two cells of each
  Sel(CellStart(1, 0), CellEnd(2, 1));
  AssertTrue('cells', FRich.SelectedCells.InTable);
  b := Bands(RowY(1));
  Drag(b[1], RowY(1), 30, 0);
  AssertTrue('row 1 moved', Abs(EdgesOf(1)[0] - (e0[0] + 450)) <= 15);
  AssertTrue('row 2 moved', Abs(EdgesOf(2)[0] - (e0[0] + 450)) <= 15);
  e := EdgesOf(0);
  AssertEquals('row 0 stays', e0[0], e[0]);
  e := EdgesOf(3);
  AssertEquals('row 3 stays', e0[0], e[0]);
end;

{ Cells of rows 0 and 1 selected: an edge dragged in row 3 - outside them - moves for every row
  that shares it, as with nothing selected; row 3's bottom dragged sets row 3's height alone. }
procedure TTyRichTableResizeTest.TestAnEdgeOutsideTheSelectedRowsIsItsOwn;
var
  b: TIntArray;
  e0: TTyRichEdges;
  r, y: Integer;
begin
  MakeTable(4, 3);
  e0 := EdgesOf(0);
  Sel(CellStart(0, 0), CellEnd(1, 1));
  AssertTrue('cells', FRich.SelectedCells.InTable);
  b := Bands(RowY(3));
  Drag(b[1], RowY(3), 30, 0);
  for r := 0 to 3 do
    AssertTrue(Format('row %d moved', [r]), Abs(EdgesOf(r)[0] - (e0[0] + 450)) <= 15);
  FRich.Undo;
  Sel(CellStart(0, 0), CellEnd(1, 1));
  y := RowBottomY(3);
  AssertTrue('row 3''s bottom', y > 0);
  Drag(Bands(RowY(3))[0] + 20, y, 0, 30);
  AssertTrue('row 3 has a height', RowAt(3).Format.Row.HeightTwips > 0);
  AssertEquals('row 0 has none', 0, RowAt(0).Format.Row.HeightTwips);
  AssertEquals('row 1 has none', 0, RowAt(1).Format.Row.HeightTwips);
end;

{ With Shift the rest of the row follows: the edge goes past where the next cell's least width
  would stop it without Shift. }
procedure TTyRichTableResizeTest.TestAShiftDragPassesTheNextCellsLeast;
var
  b: TIntArray;
  e0, e: TTyRichEdges;
begin
  MakeTable(2, 3);
  e0 := EdgesOf(0);
  b := Bands(RowY(0));
  // 100 px: 1500 twips, more than the next cell (1440) has
  Drag(b[1], RowY(0), 100, 0, [ssShift]);
  e := EdgesOf(0);
  AssertTrue(Format('past the next cell''s old edge (%d)', [e[0]]), e[0] > e0[1]);
  AssertTrue('where it was dropped', Abs(e[0] - (e0[0] + 1500)) <= 15);
  AssertEquals('the next cell kept its width', e0[1] - e0[0], e[1] - e[0]);
end;

{ A row's bottom answers within the edge band beside the table, not further right. }
procedure TTyRichTableResizeTest.TestARowsBottomAnswersOnlyNearTheTable;
var
  b: TIntArray;
  y, right: Integer;
begin
  MakeTable(2, 3);
  // the table's last row: below it no row's column edges answer first
  y := RowBottomY(1);
  AssertTrue('row 1''s bottom', y > 0);
  b := Bands(RowY(1));
  right := b[High(b)];
  AssertEquals('just right of the table', crSizeNS, FRich.CursorAtPoint(right + 1, y));
  AssertTrue('well right of it: not', FRich.CursorAtPoint(right + 40, y) <> crSizeNS);
end;

{ Every width door on a row a file wrote - Word's and WordPad's: the drag, SetColumnWidth, the
  ruler's door, AutoFitColumn, DistributeColumns, FitTableToWindow - reaches the saved file:
  loaded again in a fresh document every row has the model's edges, the row's \cellx say
  them and Word's preferred widths (\clwWidth with \clftsWidth3) agree; a row the door did not
  touch keeps its bytes. }
procedure TTyRichTableResizeTest.TestAWidthOfAFilesRowIsSaved;
const
  Files: array[0..1] of string = ('word-table-styled.rtf', 'wp-zh-table.rtf');
  Doors: array[0..6] of string = ('SetColumnWidth', 'the ruler', 'AutoFitColumn',
    'DistributeColumns', 'FitTableToWindow', 'a drag', 'SetColumnWidth on one selected row');
var
  fx, dk, first, r, c, rows, k, cut: Integer;
  bytes, before, saved, what, def: RawByteString;
  d: TTyRichDocument;
  st: TStringStream;
  model: array of TTyRichEdges;
  e: TTyRichEdges;
  ce: TTyRichColumnEdges;
  info: TTyRichTableInfo;
  changed: Boolean;
  b: TIntArray;

  function FirstTable(ADoc: TTyRichDocument): Integer;
  begin
    Result := 0;
    while (Result < ADoc.Text.ParaCount) and (ADoc.CellAt(Result) = nil) do Inc(Result);
  end;

  function Cell0(ARow, ACol: Integer): TTyRichPos;
  var
    f, l: Integer;
  begin
    AssertTrue('the cell', FRich.Document.TableCellParas(first, ARow, ACol, f, l));
    Result := FRich.Document.Text.ParaStart(f);
  end;

  function EdgesIn(ADoc: TTyRichDocument; AFirst, ARow: Integer): TTyRichEdges;
  var
    f, l: Integer;
  begin
    AssertTrue('a row', ADoc.TableCellParas(AFirst, ARow, 0, f, l));
    ADoc.BeginRead;
    try
      Result := ADoc.CellAt(f).Row.CellEdges;
    finally
      ADoc.EndRead;
    end;
  end;

begin
  for fx := 0 to High(Files) do
    for dk := 0 to High(Doors) do
    begin
      what := Files[fx] + ', ' + Doors[dk];
      bytes := FixtureBytes(Files[fx]);
      LoadRtf(bytes);
      first := FirstTable(FRich.Document);
      AssertTrue(what + ': a table', FRich.Document.TableInfoAt(first, info));
      rows := info.RowCount;
      before := SaveRtf;
      FRich.SelStart := Cell0(1, 1) + 1;
      e := EdgesIn(FRich.Document, first, 1);
      case dk of
        0: FRich.SetColumnWidth(e[1] - e[0] + 600);
        1:
          begin
            AssertTrue(what + ': edges', FRich.CaretRowEdges(ce));
            FRich.MoveCaretRowEdge(ce[2].Index, ce[2].Offset - 300, False);
          end;
        2: FRich.AutoFitColumn;
        3: FRich.DistributeColumns;
        4: FRich.FitTableToWindow;
        5:
          begin
            FRich.UpdateView;
            b := Bands(RowY(1));
            Drag(b[2], RowY(1), -20, 0);
          end;
      else
        begin
          Sel(Cell0(1, 0), Cell0(1, 1) + 1);
          FRich.SetColumnWidth(e[0] - RowAt(1).Format.Row.LeftTwips + 500);
        end;
      end;
      changed := FRich.Document.UndoDepth > 0;
      if not changed then Continue;
      model := nil;
      SetLength(model, rows);
      for r := 0 to rows - 1 do model[r] := EdgesIn(FRich.Document, first, r);
      saved := SaveRtf;
      // loaded again, in a fresh document
      d := TTyRichDocument.Create;
      st := TStringStream.Create(saved);
      try
        TyRichLoadRtfFull(d, st);
        for r := 0 to rows - 1 do
        begin
          e := EdgesIn(d, FirstTable(d), r);
          AssertEquals(Format('%s: row %d, its cells', [what, r]), Length(model[r]), Length(e));
          for c := 0 to High(e) do
            AssertEquals(Format('%s: row %d, edge %d', [what, r, c]), model[r][c], e[c]);
        end;
      finally
        st.Free;
        d.Free;
      end;
      // the row's words: its \cellx, and Word's preferred widths where the file has them
      // (row 1's: the first definition after row 0's \row)
      k := Pos('\row', saved);
      cut := Pos('\trowd', Copy(saved, k, MaxInt)) + k - 1;
      def := Copy(saved, cut, Pos('\pard', Copy(saved, cut, MaxInt)));
      for c := 0 to High(model[1]) do
        AssertTrue(Format('%s: \cellx%d in row 1''s definition', [what, model[1][c]]),
          Pos('\cellx' + IntToStr(model[1][c]), def) > 0);
      if Pos('\clftsWidth3', def) > 0 then
        AssertTrue(what + ': Word''s preferred width of the second cell',
          Pos('\clwWidth' + IntToStr(model[1][1] - model[1][0]), def) > 0);
      // a door on one selected row: the other rows keep their bytes
      if dk = 6 then
        AssertTrue(what + ': row 0 as the file had it',
          Copy(saved, 1, Pos('\row', saved)) = Copy(before, 1, Pos('\row', before)));
    end;
end;

procedure TTyRichTableResizeTest.TestMinimumWidth;
var
  b: TIntArray;
  y, g1, g2, w: Integer;
  e: TTyRichEdges;
  lft: Integer;
begin
  MakeTable(2, 3);
  y := RowY(0);
  b := Bands(y);
  FRich.Press(b[1], y);
  FRich.MoveTo(b[1] - 200, y);
  g1 := FRich.GuideLine;
  FRich.MoveTo(b[1] - 400, y);
  g2 := FRich.GuideLine;
  AssertTrue('a guide', g1 >= 0);
  AssertEquals('the guide stops at the limit', g1, g2);
  AssertTrue('the guide right of the cell''s left edge', g1 > b[0]);
  FRich.Release(b[1] - 400, y);
  e := EdgesOf(0);
  lft := RowAt(0).Format.Row.LeftTwips;
  w := e[0] - lft;
  // its padding (108 twips a side, Word's default) and a character: half the default size
  AssertTrue(Format('the narrowest (%d twips)', [w]), (w >= 216 + 20) and (w <= 216 + 300));
  AssertTrue(Format('the narrowest is the padding and a character (%d twips)', [w]),
    Abs(w - (216 + Round(FRich.SelAttributes.Size * 2) * 5)) <= 15);
  AssertEquals('drawn where the guide stopped', g1, Bands(y)[1]);
  // the next cell too: the edge goes no further right than its least width
  b := Bands(y);
  Drag(b[1], y, 600, 0);
  e := EdgesOf(1);
  AssertTrue('the cell right of it kept its least', e[1] - e[0] >= 216 + 20);
end;

procedure TTyRichTableResizeTest.TestDoubleClickFitsTheColumn;
const
  Word = 'Pneumonoultramicroscopic';
var
  b: TIntArray;
  e0, e: TTyRichEdges;
  y: Integer;
  a, z: TRect;
begin
  MakeTable(3, 3);
  FRich.Document.Execute(TTyRichInsertText.Create(CellStart(1, 0), Word + ' '));
  FRich.Document.ClearUndo;
  FRich.UpdateView;
  a := FRich.PositionRect(CellStart(1, 0), False);
  z := FRich.PositionRect(CellStart(1, 0) + Length(Word) - 1, False);
  AssertTrue('the word is broken in the narrow cell', z.Top > a.Top);
  e0 := EdgesOf(0);
  y := RowY(0);
  b := Bands(y);
  FRich.Press(b[1], y, [ssDouble]);
  FRich.Release(b[1], y);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  e := EdgesOf(2);
  AssertTrue('wider', e[0] > e0[0]);
  AssertEquals('every row', e[0], EdgesOf(0)[0]);
  AssertEquals('the next column keeps its width', e0[1] - e0[0], e[1] - e[0]);
  FRich.UpdateView;
  a := FRich.PositionRect(CellStart(1, 0), False);
  z := FRich.PositionRect(CellStart(1, 0) + Length(Word) - 1, False);
  AssertEquals('the word on one line', a.Top, z.Top);
  // AutoFitColumn: the same, from the caret (nothing more to do: no step)
  FRich.SelStart := CellStart(1, 0);
  FRich.AutoFitColumn;
  AssertEquals('fitted already', e[0], EdgesOf(0)[0]);
end;

{ ---- rows ---- }

procedure TTyRichTableResizeTest.TestRowEdgeSetsAtLeast;
var
  y0, y1, x: Integer;
  b: TIntArray;
begin
  MakeTable(3, 2);
  y0 := RowBottomY(1);
  AssertTrue('a row''s bottom', y0 > 0);
  b := Bands(RowY(1));
  x := b[0] + 30;
  AssertEquals('north-south', crSizeNS, FRich.CursorAtPoint(x, y0));
  Drag(x, y0, 0, 40);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  AssertTrue(Format('at least (%d)', [RowAt(1).Format.Row.HeightTwips]),
    RowAt(1).Format.Row.HeightTwips > 0);
  AssertEquals('the others not', 0, RowAt(0).Format.Row.HeightTwips);
  FRich.UpdateView;
  y1 := RowBottomY(1);
  AssertTrue(Format('40 pixels taller (%d to %d)', [y0, y1]), Abs(y1 - (y0 + 40)) <= 1);
  // dragged above its content: as high as its content - and so is what is kept
  Drag(x, y1, 0, -200);
  FRich.UpdateView;
  AssertTrue(Format('its content''s height (%d, %d)', [y0, RowBottomY(1)]),
    Abs(RowBottomY(1) - y0) <= 1);
  AssertTrue(Format('kept: no lower than its content (%d twips for %d pixels)',
    [RowAt(1).Format.Row.HeightTwips, y0 - (RowBottomY(0))]),
    RowAt(1).Format.Row.HeightTwips >= (y0 - RowBottomY(0)) * 15 - 30);
  // with rows selected: all of them
  Sel(CellStart(0, 0), CellEnd(2, 1));
  y0 := RowBottomY(2);
  Drag(x, y0, 0, 20);
  AssertTrue('row 0 too', RowAt(0).Format.Row.HeightTwips > 0);
  AssertEquals('one height for all', RowAt(0).Format.Row.HeightTwips, RowAt(2).Format.Row.HeightTwips);
end;

procedure TTyRichTableResizeTest.TestEscAndNoMoveChangeNothing;
var
  b: TIntArray;
  y: Integer;
  before: RawByteString;
begin
  MakeTable(2, 2);
  before := SaveRtf;
  y := RowY(0);
  b := Bands(y);
  FRich.Press(b[1], y);
  FRich.MoveTo(b[1] + 40, y);
  AssertTrue('dragging', FRich.EdgeDragging);
  AssertTrue('the guide shows', FRich.GuideLine >= 0);
  FRich.Key(VK_ESCAPE);
  AssertFalse('Esc ends it', FRich.EdgeDragging);
  AssertEquals('the guide goes', -1, FRich.GuideLine);
  FRich.Release(b[1] + 40, y);
  AssertEquals('nothing on the history', 0, FRich.Document.UndoDepth);
  // a release where it was pressed
  FRich.Press(b[1], y);
  FRich.MoveTo(b[1] + 10, y);
  FRich.MoveTo(b[1], y);
  FRich.Release(b[1], y);
  AssertEquals('no move: nothing', 0, FRich.Document.UndoDepth);
  AssertTrue('the document as it was', before = SaveRtf);
  // a row's bottom: the same
  y := RowBottomY(0);
  FRich.Press(b[0] + 30, y);
  FRich.MoveTo(b[0] + 30, y + 30);
  FRich.Key(VK_ESCAPE);
  FRich.Release(b[0] + 30, y + 30);
  AssertEquals('a row: nothing', 0, FRich.Document.UndoDepth);
  AssertEquals('no row guide', False, FRich.EdgeDragging);
end;

{ Word's table of merged cells (word-table-styled.rtf, its second table): rows of 3 and 4
  cells; 2081 is an edge of three of its rows, 4157 of all four. }
procedure TTyRichTableResizeTest.TestIrregularRowsMoveBySharedEdges;
var
  d: TTyRichDocument;
  k, i, y, first4: Integer;
  paras: array of Integer;
  before, e: TTyRichEdges;
  b: TIntArray;
  t: TTyRichTable;
  edges0: array of TTyRichEdges;
  r: TRect;

  function Has(const AE: TTyRichEdges; AV: Integer): Boolean;
  var
    j: Integer;
  begin
    Result := False;
    for j := 0 to High(AE) do
      if Abs(AE[j] - AV) <= 15 then Result := True;
  end;

  function RowEdges(AIndex: Integer): TTyRichEdges;
  begin
    Result := d.CellAt(paras[AIndex]).Row.CellEdges;
  end;

begin
  FRich.SetBounds(0, 0, 900, 900);
  LoadRtf(FixtureBytes('word-table-styled.rtf'));
  d := FRich.Document;
  // the second table's rows (their first paragraphs, in order), and its first 4-cell row
  t := nil;
  paras := nil;
  first4 := -1;
  for k := 0 to d.Text.ParaCount - 1 do
    if d.CellAt(k) <> nil then
    begin
      if t = nil then t := d.CellAt(k).Table;
      if d.CellAt(k).Table = t then Continue;
      if (Length(paras) = 0) or (d.CellAt(paras[High(paras)]).Row <> d.CellAt(k).Row) then
      begin
        SetLength(paras, Length(paras) + 1);
        paras[High(paras)] := k;
        if (first4 < 0) and (d.CellAt(k).Row.CellCount = 4) then first4 := High(paras);
      end;
    end;
  AssertTrue('the merged table', (Length(paras) >= 4) and (first4 >= 0));
  SetLength(edges0, Length(paras));
  for i := 0 to High(paras) do edges0[i] := RowEdges(i);
  AssertFalse('its first row has no edge at 2081', Has(edges0[0], 2081));
  AssertTrue('the 4-cell row has', Has(edges0[first4], 2081));
  // the edge at 2081, in the first 4-cell row
  r := FRich.PositionRect(d.Text.ParaStart(paras[first4]), False);
  y := (r.Top + r.Bottom) div 2;
  b := Bands(y);
  AssertTrue('its edges', Length(b) >= 4);
  Drag(b[1], y, 20, 0);
  AssertEquals('one step', 1, d.UndoDepth);
  for i := 0 to High(paras) do
  begin
    e := RowEdges(i);
    if Has(edges0[i], 2081) then
      AssertTrue(Format('row %d: 2081 moved (%d)', [i, e[0]]), Abs(e[0] - (edges0[i][0] + 300)) <= 15)
    else
      AssertTrue(Format('row %d: no edge there, untouched', [i]), (e[0] = edges0[i][0]) and
        (Length(e) = Length(edges0[i])) and (e[High(e)] = edges0[i][High(e)]));
    // the next edge of every row stays where it was
    if Has(edges0[i], 4157) then AssertTrue(Format('row %d: 4157 stays', [i]), Has(e, 4157));
  end;
  // 4157: every row has it
  FRich.UpdateView;
  r := FRich.PositionRect(d.Text.ParaStart(paras[first4]), False);
  y := (r.Top + r.Bottom) div 2;
  b := Bands(y);
  Drag(b[2], y, -10, 0);
  for i := 0 to High(paras) do
  begin
    e := RowEdges(i);
    AssertFalse(Format('row %d: 4157 moved', [i]), Has(e, 4157));
    AssertTrue(Format('row %d: to about 4007', [i]), Has(e, 4007));
  end;
  // the first table (another table) untouched
  k := 0;
  while d.CellAt(k) = nil do Inc(k);
  before := d.CellAt(k).Row.CellEdges;
  AssertTrue('the other table', (Length(before) = 3) and (before[0] = 1645));
end;

procedure TTyRichTableResizeTest.TestOneUndoStepAndBytesBack;
var
  file0, after: RawByteString;
  b: TIntArray;
  y: Integer;
  d: TTyRichDocument;
begin
  FRich.SetBounds(0, 0, 900, 900);
  LoadRtf(FixtureBytes('word-table-styled.rtf'));
  d := FRich.Document;
  file0 := SaveRtf;
  AssertTrue('the file as read', file0 = FixtureBytes('word-table-styled.rtf'));
  FRich.SelStart := d.Text.ParaStart(d.Text.ParaOfPos(0));
  y := RowY(0);
  b := Bands(y);
  Drag(b[1], y, 15, 0);
  Drag(b[0] + 40, RowBottomY(0), 0, 20);
  AssertEquals('two steps', 2, d.UndoDepth);
  after := SaveRtf;
  AssertFalse('changed', after = file0);
  FRich.Undo;
  FRich.Undo;
  AssertTrue('the file''s bytes back', SaveRtf = file0);
  FRich.Redo;
  FRich.Redo;
  AssertTrue('the change again', SaveRtf = after);
end;

procedure TTyRichTableResizeTest.TestTheRulerShowsAndDragsColumnEdges;
var
  form: TForm;
  ruler: TResizeRuler;
  b: TIntArray;
  p: TPoint;
  e0, e: TTyRichEdges;
  i, y, off: Integer;
begin
  form := TForm.CreateNew(nil);
  ruler := TResizeRuler.Create(nil);
  try
    FRich.Parent := form;
    FRich.SetBounds(20, 40, 700, 400);
    ruler.Controller := FCtl;
    ruler.Font.PixelsPerInch := 96;
    ruler.AutoSize := False;
    ruler.Parent := form;
    ruler.SetBounds(0, 0, 740, 40);
    ruler.MeasureUnit := ruCentimeters;
    MakeTable(3, 3);
    FRich.SelStart := CellStart(1, 1);
    ruler.RichEdit := FRich;
    ruler.CheckView;
    AssertEquals('the edges of the caret''s row', 4, Length(ruler.Edges));
    off := ruler.EditOffsetNow;
    y := RowY(1);
    b := Bands(y);
    { each marker over its edge, to the pixel - the table's left edge at the margin has only
      the right half of its band (the row's zone takes the left half): its middle is a pixel
      or two right of the line }
    for i := 0 to 3 do
      if i = 0 then
        AssertTrue(Format('edge %d at %d, the text''s at %d', [i, ruler.EdgeMid(i).X - off, b[i]]),
          (b[i] - (ruler.EdgeMid(i).X - off) >= -1) and (b[i] - (ruler.EdgeMid(i).X - off) <= 3))
      else
        AssertTrue(Format('edge %d at %d, the text''s at %d', [i, ruler.EdgeMid(i).X - off, b[i]]),
          Abs(ruler.EdgeMid(i).X - off - b[i]) <= 1);
    // a drag of the second edge: the rows' first cells wider, one step
    e0 := EdgesOf(0);
    p := ruler.EdgeMid(1);
    ruler.Press(p.X, p.Y);
    ruler.MoveTo(p.X + 20, p.Y);
    AssertTrue('the guide through the text', FRich.GuideLine >= 0);
    ruler.MoveTo(p.X + 40, p.Y);
    ruler.Release(p.X + 40, p.Y);
    AssertEquals('one step', 1, FRich.Document.UndoDepth);
    AssertEquals('no guide after', -1, FRich.GuideLine);
    e := EdgesOf(0);
    // (40 pixels, 600 twips, snapped to the nearest quarter centimetre)
    AssertTrue(Format('moved (%d to %d)', [e0[0], e[0]]), Abs(e[0] - e0[0] - 600) <= 80);
    AssertEquals('every row', e[0], EdgesOf(2)[0]);
    AssertEquals('the table''s width', e0[2], e[2]);
    // the markers follow
    ruler.CheckView;
    FRich.UpdateView;
    b := Bands(y);
    AssertTrue('the marker where the edge is now', Abs(ruler.EdgeMid(1).X - off - b[1]) <= 1);
    // Esc: nothing
    p := ruler.EdgeMid(2);
    ruler.Press(p.X, p.Y);
    ruler.MoveTo(p.X + 30, p.Y);
    ruler.CancelMarkerDrag;
    ruler.Release(p.X + 30, p.Y);
    AssertEquals('Esc: no step', 1, FRich.Document.UndoDepth);
    // outside a table: no edges
    FRich.SelStart := 1;
    ruler.CheckView;
    AssertEquals('none outside a table', 0, Length(ruler.Edges));
  finally
    ruler.Free;
    FRich.Parent := nil;
    form.Free;
  end;
end;

procedure TTyRichTableResizeTest.TestAMoveDrawsOnlyTheGuide;
var
  b: TIntArray;
  y, i, misses, g, steps: Integer;
  before: RawByteString;
begin
  MakeTable(5, 3);
  y := RowY(2);
  b := Bands(y);
  before := SaveRtf;
  FRich.Press(b[1], y);
  misses := FRich.Layouter.CacheMisses;
  steps := FRich.Document.UndoDepth;
  g := FRich.GuideLine;
  for i := 1 to 30 do
  begin
    FRich.MoveTo(b[1] + i, y);
    AssertEquals(Format('move %d: the guide follows', [i]), g + i, FRich.GuideLine);
  end;
  AssertEquals('nothing laid out while it moves', misses, FRich.Layouter.CacheMisses);
  AssertTrue('nothing changed while it moves', before = SaveRtf);
  AssertEquals('no step', steps, FRich.Document.UndoDepth);
  FRich.Release(b[1] + 30, y);
  AssertEquals('one step at the release', steps + 1, FRich.Document.UndoDepth);
  // a row's bottom: the same
  y := RowBottomY(1);
  FRich.Press(b[0] + 30, y);
  misses := FRich.Layouter.CacheMisses;
  for i := 1 to 20 do
  begin
    FRich.MoveTo(b[0] + 30, y + i);
    AssertEquals(Format('row move %d: the guide follows', [i]), y + i, FRich.GuideRow);
  end;
  AssertEquals('a row: nothing laid out while it moves', misses, FRich.Layouter.CacheMisses);
  FRich.Release(b[0] + 30, y + 20);
  AssertEquals('one step more', steps + 2, FRich.Document.UndoDepth);
end;

procedure TTyRichTableResizeTest.TestTheUserDoors;
var
  e0, e: TTyRichEdges;
  r: Integer;
  w: Integer;
begin
  MakeTable(3, 3);
  FRich.SelStart := CellStart(1, 1);
  AssertTrue('columns may change', FRich.CanResizeColumns);
  AssertTrue('rows may change', FRich.CanResizeRows);
  e0 := EdgesOf(0);
  // the caret's column 2000 twips wide, the rest shifting
  AssertTrue('a width', FRich.SetColumnWidth(2000));
  for r := 0 to 2 do
  begin
    e := EdgesOf(r);
    AssertEquals(Format('row %d: its width', [r]), 2000, e[1] - e[0]);
    AssertEquals(Format('row %d: the last keeps its', [r]), e0[2] - e0[1], e[2] - e[1]);
  end;
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  // each row's cells alike
  AssertTrue('distributed', FRich.DistributeColumns);
  e := EdgesOf(1);
  w := e[2] - RowAt(1).Format.Row.LeftTwips;
  AssertTrue('alike', (Abs((e[0] - RowAt(1).Format.Row.LeftTwips) - w div 3) <= 1) and
    (Abs((e[1] - e[0]) - w div 3) <= 1));
  // the text's width
  AssertTrue('fitted', FRich.FitTableToWindow);
  e := EdgesOf(0);
  AssertTrue(Format('as wide as the text (%d)', [e[2] - RowAt(0).Format.Row.LeftTwips]),
    e[2] - RowAt(0).Format.Row.LeftTwips > 4320);
  // heights
  AssertTrue('a height', FRich.SetRowHeight(600, False));
  AssertEquals('at least', 600, RowAt(1).Format.Row.HeightTwips);
  AssertEquals('only the caret''s row', 0, RowAt(0).Format.Row.HeightTwips);
  AssertTrue('exactly', FRich.SetRowHeight(400, True));
  AssertEquals('exactly', -400, RowAt(1).Format.Row.HeightTwips);
  AssertTrue('rows alike', FRich.DistributeRows);
  AssertEquals('alike', RowAt(0).Format.Row.HeightTwips, RowAt(2).Format.Row.HeightTwips);
  AssertTrue('a height to them', RowAt(0).Format.Row.HeightTwips > 0);
  // read-only: nothing, told nothing
  FRich.ReadOnly := True;
  AssertFalse('read-only: not offered', FRich.CanResizeColumns);
  FRich.Refusals.Clear;
  AssertFalse('read-only: nothing', FRich.SetColumnWidth(3000));
  AssertEquals('read-only: told nothing', 0, FRich.Refusals.Count);
  // read-only: no edge to drag
  AssertEquals('read-only: no edge to drag', 0, Length(Bands(RowY(0))));
  FRich.ReadOnly := False;
  // outside a table: refused, told once
  FRich.SelStart := 1;
  FRich.Refusals.Clear;
  AssertFalse('outside', FRich.SetColumnWidth(3000));
  AssertEquals('told once', 1, FRich.Refusals.Count);
  AssertFalse('not offered outside', FRich.CanResizeColumns);
end;

procedure TTyRichTableResizeTest.TestANestedRowAndAPartOfALongFileAreRefused;
const
  Nested = '{\rtf1 \trowd\cellx1000\cellx2000\pard\intbl a\cell \pard\intbl\itap2 x' +
    '\nestcell{\*\nesttableprops\trowd\cellx500\nestrow}{\nonesttables\par}\pard\intbl\cell' +
    '\row\pard b\par}';
var
  s: string;
  i, k, y: Integer;
  st: TStringStream;
  e: TTyRichColumnEdges;
  r: TRect;
begin
  LoadRtf(Nested);
  FRich.SelStart := 0;
  AssertFalse('a nested row: not offered', FRich.CanResizeColumns);
  FRich.Refusals.Clear;
  AssertFalse('a nested row: refused', FRich.SetColumnWidth(3000));
  AssertEquals('told once', 1, FRich.Refusals.Count);
  AssertEquals('why', rsRichEditRefusedResizeNested, FRich.Refusals[0]);
  r := FRich.PositionRect(0, False);
  y := (r.Top + r.Bottom) div 2;
  AssertEquals('no edge to drag in it', 0, Length(Bands(y)));
  // a table of more than a megabyte: the reader gives it in parts
  s := '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' + LineEnding;
  for i := 0 to 14999 do
    s := s + Format('\trowd\cellx3000\cellx6000\pard\intbl row %d of the long table, cell one\cell row %d cell two\cell\row', [i, i]) + LineEnding;
  s := s + '\pard after\par}';
  st := TStringStream.Create(s);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  k := 2 * 7000;
  AssertTrue('a part', FRich.Document.TableAt(k).Cut);
  FRich.SelStart := FRich.Document.Text.ParaStart(k);
  FRich.UpdateView;
  FRich.Refusals.Clear;
  AssertFalse('a whole column of a part: refused', FRich.DistributeColumns);
  AssertEquals('told once', 1, FRich.Refusals.Count);
  AssertEquals('why', rsRichEditRefusedResizeNotWhole, FRich.Refusals[0]);
  // its own row's height: that row only, it may
  AssertTrue('a row of it', FRich.SetRowHeight(500, False));
  AssertTrue('the edges shown', FRich.CaretRowEdges(e));
end;

{ Rows whose edges differ by at most 15 twips share one; 16 apart they do not. }
procedure TTyRichTableResizeTest.TestEdgesWithin15TwipsAreOne;
const
  Rtf = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx1440\cellx2880\pard\intbl a\cell b\cell\row' +
    '\trowd\cellx1455\cellx2880\pard\intbl c\cell d\cell\row' +
    '\trowd\cellx1425\cellx2880\pard\intbl e\cell f\cell\row' +
    '\trowd\cellx1456\cellx2880\pard\intbl g\cell h\cell\row\pard after\par}';
var
  d: TTyRichDocument;
  y: Integer;
  b: TIntArray;
  r: TRect;

  function E0(APara: Integer): Integer;
  begin
    Result := d.CellAt(APara).Row.CellEdges[0];
  end;

begin
  LoadRtf(Rtf);
  d := FRich.Document;
  r := FRich.PositionRect(0, False);
  y := (r.Top + r.Bottom) div 2;
  b := Bands(y);
  Drag(b[1], y, 20, 0);
  AssertEquals('the row dragged', 1440 + 300, E0(0));
  AssertEquals('15 twips off: the same edge', 1455 + 300, E0(2));
  AssertEquals('15 twips off the other way', 1425 + 300, E0(4));
  AssertEquals('16 twips off: another edge, untouched', 1456, E0(6));
end;

{ A column's edge in every row of a long table, the view in its middle: it stays there - the
  rows the person looks at are still on screen, not the table's start. }
procedure TTyRichTableResizeTest.TestTheViewStaysWhereItWas;
var
  d: TTyRichDocument;
  k, y, top0: Integer;
  b: TIntArray;
  e: TTyRichColumnEdges;
begin
  FRich.Lines.Text := 'before' + LineEnding + 'after';
  d := FRich.Document;
  AssertTrue('a long table', d.Execute(TTyRichInsertTable.Create(d.Text.ParaStart(1), 400, 3)));
  k := 1 + 3 * 200;
  FRich.SelStart := d.Text.ParaStart(k);
  FRich.UpdateView;
  top0 := FRich.ScrollY;
  AssertTrue('scrolled down', top0 > 1000);
  y := (FRich.PositionRect(d.Text.ParaStart(k), False).Top + FRich.PositionRect(d.Text.ParaStart(k),
    False).Bottom) div 2;
  b := Bands(y);
  Drag(b[1], y, 25, 0);
  FRich.UpdateView;
  AssertTrue(Format('the view stays (%d, was %d)', [FRich.ScrollY, top0]), Abs(FRich.ScrollY - top0) <= 40);
  AssertTrue('the caret''s row still shown', FRich.CaretRowEdges(e));
end;

{ AutoHeight: a row made taller by its bottom's drag, and cells made narrower (their text
  wraps), make the control as tall as its content again. }
procedure TTyRichTableResizeTest.TestAPageAsTallAsItsContentFollows;
var
  h0, y: Integer;
  b: TIntArray;
begin
  MakeTable(3, 3);
  FRich.AutoHeight := True;
  FRich.UpdateView;
  h0 := FRich.Height;
  AssertEquals('as tall as its content', FRich.ContentHeight, h0);
  b := Bands(RowY(1));
  y := RowBottomY(1);
  Drag(b[0] + 30, y, 0, 40);
  FRich.UpdateView;
  AssertTrue(Format('taller by the row (%d to %d)', [h0, FRich.Height]), Abs(FRich.Height - (h0 + 40)) <= 1);
  AssertEquals('as tall as its content again', FRich.ContentHeight, FRich.Height);
  // a column made narrow: its text wraps, the rows grow, so does the page
  h0 := FRich.Height;
  y := RowY(0);
  b := Bands(y);
  Drag(b[1], y, -60, 0);
  FRich.UpdateView;
  AssertTrue(Format('taller again (%d to %d)', [h0, FRich.Height]), FRich.Height > h0);
  AssertEquals('as tall as its content, still', FRich.ContentHeight, FRich.Height);
end;

{ A display page (AllowSelection False) shows no handle, no zone and no resize cursor; a
  viewer (ReadOnly) shows no handle and no resize cursor, and a press on an edge drags
  nothing. }
procedure TTyRichTableResizeTest.TestADisplayPageAndAViewerOfferNothing;
var
  y, x, yy: Integer;
  b: TIntArray;
  r: TRect;
  c: TCursor;
  seen: Boolean;
begin
  MakeTable(2, 2);
  y := RowY(0);
  b := Bands(y);
  AssertEquals('edges, editing', 3, Length(b));
  r := FRich.PositionRect(CellStart(0, 0), False);
  FRich.AllowSelection := False;
  AssertEquals('a display page: no resize cursor', 0, Length(Bands(y)));
  FRich.MoveTo(r.Left + 10, y, []);
  seen := False;
  for yy := r.Top - 20 to r.Bottom do
    for x := 0 to r.Left + 20 do
    begin
      c := FRich.CursorAtPoint(x, yy);
      if (c = crSizeAll) or (c = crSizeNS) or (c = crSizeWE) or (c = crUpArrow) then seen := True;
    end;
  AssertFalse('a display page: no handle, no zone', seen);
  FRich.AllowSelection := True;
  FRich.ReadOnly := True;
  AssertEquals('a viewer: no resize cursor', 0, Length(Bands(y)));
  FRich.MoveTo(r.Left + 10, y, []);
  seen := False;
  for yy := r.Top - 20 to r.Bottom do
    for x := 0 to r.Left + 20 do
      if FRich.CursorAtPoint(x, yy) = crSizeAll then seen := True;
  AssertFalse('a viewer: no handle', seen);
  FRich.Press(b[1], y);
  FRich.MoveTo(b[1] + 30, y);
  AssertFalse('a viewer: no drag', FRich.EdgeDragging);
  FRich.Release(b[1] + 30, y);
  AssertEquals('a viewer: nothing changed', 0, FRich.Document.UndoDepth);
end;

initialization
  RegisterTest(TTyRichTableResizeTest);
end.
