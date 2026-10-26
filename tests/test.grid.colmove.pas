unit test.grid.colmove;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.Grid;

type
  { A column dragged to another place has to BE in that place: drawn there, hit there,
    walked there by the keys, selected and copied in the order the user sees. The
    column's Position is its place on screen; its index stays its identity (the data
    and every event are keyed by it). }
  TTyGridColumnMoveTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMoveCalls: Integer;
    procedure HookColumnMove(Sender: TObject; AFromCol, AToCol: Integer;
      var AAllow: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- where the columns stand --- }
    procedure TestMovedColumnIsLaidOutAtItsNewPlace;
    procedure TestHeaderDragMovesTheColumnOnScreen;
    procedure TestDrawGridHeaderDragMovesTheColumnOnScreen;
    procedure TestRightFrozenBandIsLaidOutByPosition;
    procedure TestLeftColIsTheFirstBodyColumnOnScreen;
    procedure TestLeftColInTheFrozenBandMeansTheFirstBodyColumn;
    procedure TestFreezingAfterAMoveLaysTheBandOutAgain;
    procedure TestScrollPullsTheCursorToTheNearestColumnOnScreen;
    { --- where a drag may go --- }
    procedure TestColumnCannotLeaveTheLeftFrozenBand;
    procedure TestColumnCannotLeaveTheRightFrozenBand;
    procedure TestColumnCannotLeaveItsHeaderGroup;
    procedure TestHeaderGroupSpansItsColumnsInAnyOrder;
    { --- the keys --- }
    procedure TestArrowKeysWalkTheScreenOrder;
    procedure TestTabWalksTheScreenOrderAndWraps;
    procedure TestHiddenColumnIsSkippedInScreenOrder;
    procedure TestReadOnlyColumnIsSkippedInScreenOrder;
    { --- selection, clipboard, fill --- }
    procedure TestRangeSelectionCoversWhatLiesBetweenOnScreen;
    procedure TestSelectAllAndSelectRowsCoverEveryColumn;
    procedure TestSelectionReportsTheColumnsAtBothEnds;
    procedure TestFillHandleSitsAtTheSelectionsEdgeOnScreen;
    procedure TestMergeSelectionTakesTheColumnsOnScreen;
    procedure TestCopyFollowsTheScreenOrder;
    procedure TestPasteFillsColumnsInScreenOrder;
    procedure TestPasteGrowsByTheCursorsPlaceOnScreen;
    procedure TestFillDownUsesTheSelectedScreenColumns;
    procedure TestFindNextWalksTheScreenOrder;
    procedure TestReplaceOnceTakesTheFirstOnScreen;
    { --- merges --- }
    procedure TestMergeSplitByAMoveIsSuspended;
    { --- the order survives the other column operations --- }
    procedure TestUndoPutsAFarMoveBack;
    procedure TestInsertAfterAMoveKeepsTheScreenOrder;
    procedure TestUndoOfDeleteRestoresTheColumnsPlace;
    procedure TestLayoutRoundTripKeepsAnyOrder;
  end;

implementation

type
  TColMoveGrid = class(TTyStringGrid)
  public
    function LeftOf(ACol: Integer): Integer;
    function ColAt(AX: Integer): Integer;
    function SpanOf(AFirst, ALast: Integer; out ALeft, ARight: Integer): Boolean;
    function ViewW: Integer;
    function HeaderY: Integer;
    procedure DragHeader(AFromX, AToX: Integer);
    procedure Key(AKey: Word; AShift: TShiftState);
  end;

  TColMoveDrawGrid = class(TTyDrawGrid)
  public
    function LeftOf(ACol: Integer): Integer;
    procedure DragHeader(AFromX, AToX: Integer);
  end;

function TColMoveGrid.LeftOf(ACol: Integer): Integer;
begin
  Result := ColumnLeftPx(ACol);
end;

function TColMoveGrid.ColAt(AX: Integer): Integer;
begin
  Result := ColumnAtX(AX);
end;

function TColMoveGrid.SpanOf(AFirst, ALast: Integer; out ALeft, ARight: Integer): Boolean;
begin
  Result := ColumnSpanX(AFirst, ALast, ALeft, ARight);
end;

function TColMoveGrid.ViewW: Integer;
begin
  Result := ViewportW;
end;

function TColMoveGrid.HeaderY: Integer;
begin
  { the middle of the column header band, below the group band when there is one }
  Result := GroupBandHeightPx + 10;
end;

procedure TColMoveGrid.DragHeader(AFromX, AToX: Integer);
begin
  MouseDown(mbLeft, [], AFromX, HeaderY);
  MouseMove([ssLeft], AToX, HeaderY);
  MouseUp(mbLeft, [], AToX, HeaderY);
end;

procedure TColMoveGrid.Key(AKey: Word; AShift: TShiftState);
var k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

function TColMoveDrawGrid.LeftOf(ACol: Integer): Integer;
begin
  Result := ColumnLeftPx(ACol);
end;

procedure TColMoveDrawGrid.DragHeader(AFromX, AToX: Integer);
begin
  MouseDown(mbLeft, [], AFromX, 10);
  MouseMove([ssLeft], AToX, 10);
  MouseUp(mbLeft, [], AToX, 10);
end;

const
  Letters = 'ABCDEFGH';

{ Four 80 px columns A B C D, the header showing and draggable, five rows whose cells
  read A0, B0, ... -- the letter of the column's index and the row. }
function MakeGrid(AForm: TForm; ACtl: TTyStyleController): TColMoveGrid;
var
  i, r: Integer;
  c: TTyColumn;
begin
  Result := TColMoveGrid.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  for i := 0 to 3 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := 80;
    c.Text := Letters[i + 1];
    c.Options := c.Options + [coDraggable];
  end;
  Result.Header.Options := (Result.Header.Options - [hoColumnResize, hoHeaderClickAutoSort])
    + [hoVisible, hoDrag];
  Result.Header.Height := 24;
  Result.DefaultRowHeight := 20;
  Result.RowCount := 5;
  for i := 0 to 3 do
    for r := 0 to 4 do
      Result.Cells[i, r] := Letters[i + 1] + IntToStr(r);
end;

{ The visible columns' captions, left to right as they stand on screen. }
function ScreenOrder(G: TColMoveGrid): string;
var
  i, j, n: Integer;
  idx: array of Integer;
  t: Integer;
begin
  n := 0;
  SetLength(idx, G.Header.Columns.Count);
  for i := 0 to G.Header.Columns.Count - 1 do
    if coVisible in TTyColumn(G.Header.Columns.Items[i]).Options then
    begin
      idx[n] := i;
      Inc(n);
    end;
  for i := 0 to n - 2 do
    for j := i + 1 to n - 1 do
      if G.LeftOf(idx[j]) < G.LeftOf(idx[i]) then
      begin
        t := idx[i]; idx[i] := idx[j]; idx[j] := t;
      end;
  Result := '';
  for i := 0 to n - 1 do
    Result := Result + TTyColumn(G.Header.Columns.Items[idx[i]]).Text;
end;

{ Columns 0..3 put at the screen places APlaces (APlaces[k] = the column at place k). }
procedure PutInOrder(G: TColMoveGrid; const APlaces: array of Integer);
var
  k: Integer;
begin
  { Place by place, left to right: a column put at place k never disturbs places < k. }
  for k := 0 to High(APlaces) do
    TTyColumn(G.Header.Columns.Items[APlaces[k]]).Position := k;
end;

procedure TTyGridColumnMoveTest.HookColumnMove(Sender: TObject; AFromCol,
  AToCol: Integer; var AAllow: Boolean);
begin
  Inc(FMoveCalls);
end;

procedure TTyGridColumnMoveTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
    'TyGridCell { color: #000000; }');
  FMoveCalls := 0;
end;

procedure TTyGridColumnMoveTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

{ ---- where the columns stand -------------------------------------------- }

procedure TTyGridColumnMoveTest.TestMovedColumnIsLaidOutAtItsNewPlace;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  AssertEquals('premise: natural order', 'ABCD', ScreenOrder(G));
  G.MoveColumn(0, 2);                       { A to where C stands }
  AssertEquals('premise: A took C''s place in the column model', 2,
    TTyColumn(G.Header.Columns.Items[0]).Position);
  AssertEquals('drawn in the new order', 'BCAD', ScreenOrder(G));
  AssertEquals('B now opens the row', 0, G.LeftOf(1));
  AssertEquals('A stands third', 160, G.LeftOf(0));
  AssertEquals('a click at the far left hits B, the column drawn there', 1, G.ColAt(5));
  AssertEquals('a click at 170 hits A', 0, G.ColAt(170));
end;

procedure TTyGridColumnMoveTest.TestHeaderDragMovesTheColumnOnScreen;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.OnColumnMove := @HookColumnMove;
  G.DragHeader(20, 100);                    { A's header onto B's }
  AssertEquals('premise: the move was asked for', 1, FMoveCalls);
  AssertEquals('the dragged column stands where it was dropped', 'BACD', ScreenOrder(G));
  AssertEquals('and is hit there', 0, G.ColAt(100));
  AssertEquals('the data stays with its column', 'A0', G.Cells[0, 0]);
end;

procedure TTyGridColumnMoveTest.TestDrawGridHeaderDragMovesTheColumnOnScreen;
var
  G: TColMoveDrawGrid;
  i: Integer;
  c: TTyColumn;
begin
  G := TColMoveDrawGrid.Create(FForm);
  G.Parent := FForm;
  G.Controller := FCtl;
  G.Font.PixelsPerInch := 96;
  G.SetBounds(0, 0, 400, 300);
  for i := 0 to 3 do
  begin
    c := G.Header.Columns.Add as TTyColumn;
    c.Width := 80;
    c.Options := c.Options + [coDraggable];
  end;
  G.Header.Options := (G.Header.Options - [hoColumnResize, hoHeaderClickAutoSort])
    + [hoVisible, hoDrag];
  G.Header.Height := 24;
  G.RowCount := 3;
  G.DragHeader(20, 100);
  AssertEquals('column 1 opens the row', 0, G.LeftOf(1));
  AssertEquals('column 0 stands second', 80, G.LeftOf(0));
end;

procedure TTyGridColumnMoveTest.TestRightFrozenBandIsLaidOutByPosition;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.FixedColsRight := 2;                    { C and D pinned to the right edge }
  AssertEquals('premise: D at the right edge', G.ViewW - 80, G.LeftOf(3));
  G.MoveColumn(3, 2);                       { D before C, inside the band }
  AssertEquals('D now first in the band', G.ViewW - 160, G.LeftOf(3));
  AssertEquals('C at the right edge', G.ViewW - 80, G.LeftOf(2));
end;

procedure TTyGridColumnMoveTest.TestLeftColIsTheFirstBodyColumnOnScreen;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  AssertEquals('the column at the reading start of the body', 1, G.LeftCol);
end;

procedure TTyGridColumnMoveTest.TestLeftColInTheFrozenBandMeansTheFirstBodyColumn;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.SetBounds(0, 0, 200, 300);              { 320 px of columns in a 200 px grid }
  G.FixedCols := 1;                         { A | B C D }
  G.MoveColumn(3, 1);                       { A | D B C }
  AssertEquals('premise', 'ADBC', ScreenOrder(G));
  G.LeftCol := 2;                           { scroll C to the body's start }
  AssertTrue('premise: scrolled', G.LeftCol <> 3);
  G.LeftCol := 0;                           { a frozen column: the body's first }
  AssertEquals('scrolled back to D, the first body column on screen', 3, G.LeftCol);
  AssertEquals('D stands right after the frozen band', 80, G.LeftOf(3));
end;

procedure TTyGridColumnMoveTest.TestFreezingAfterAMoveLaysTheBandOutAgain;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(1, 0);                       { B A C D }
  AssertEquals('premise', 'BACD', ScreenOrder(G));
  G.FixedCols := 1;                         { column 0, A, is the frozen one }
  AssertEquals('the frozen column opens the row', 0, G.LeftOf(0));
  AssertEquals('and the body follows it', 'ABCD', ScreenOrder(G));
end;

procedure TTyGridColumnMoveTest.TestScrollPullsTheCursorToTheNearestColumnOnScreen;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.SetBounds(0, 0, 200, 300);              { 320 px of columns in a 200 px grid }
  G.MoveColumn(3, 0);                       { D A B C }
  G.Col := 3;                               { D, first on screen }
  G.Options := G.Options + [goScrollKeepVisible];
  G.LeftCol := 1;                           { scroll as far as it goes: A B C in view }
  AssertEquals('premise: A is the first column in view', 0, G.LeftCol);
  AssertEquals('the cursor moves to A, the nearest column still in view', 0, G.Col);
end;

{ ---- where a drag may go ------------------------------------------------- }

procedure TTyGridColumnMoveTest.TestColumnCannotLeaveTheLeftFrozenBand;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.FixedCols := 1;                         { A frozen at the left }
  G.OnColumnMove := @HookColumnMove;
  G.DragHeader(20, 100);                    { A onto B }
  AssertEquals('a frozen column stays in its band', 'ABCD', ScreenOrder(G));
  G.DragHeader(100, 20);                    { B onto A }
  AssertEquals('a body column does not enter the frozen band', 'ABCD', ScreenOrder(G));
  AssertEquals('a move that cannot happen is not offered to the host', 0, FMoveCalls);
  G.DragHeader(180, 100);                   { C onto B: both in the body }
  AssertEquals('inside the body the move works', 'ACBD', ScreenOrder(G));
  G.MoveColumn(1, 0);                       { B onto A, from code }
  AssertEquals('MoveColumn keeps the same rule: B''s place unchanged', 2,
    TTyColumn(G.Header.Columns.Items[1]).Position);
end;

procedure TTyGridColumnMoveTest.TestColumnCannotLeaveTheRightFrozenBand;
var
  G: TColMoveGrid;
  xc, xd: Integer;
begin
  G := MakeGrid(FForm, FCtl);
  G.FixedColsRight := 2;                    { C and D pinned to the right edge }
  xc := G.LeftOf(2) + 20;
  xd := G.LeftOf(3) + 20;
  G.DragHeader(xd, xc);                     { D onto C, inside the band }
  AssertEquals('inside the band the move works', 'ABDC', ScreenOrder(G));
  G.DragHeader(100, G.LeftOf(3) + 20);      { B onto D }
  AssertEquals('a body column does not enter the right band', 'ABDC', ScreenOrder(G));
  G.DragHeader(G.LeftOf(2) + 20, 100);      { C onto B }
  AssertEquals('a pinned column does not leave it', 'ABDC', ScreenOrder(G));
end;

procedure TTyGridColumnMoveTest.TestColumnCannotLeaveItsHeaderGroup;
var
  G: TColMoveGrid;
  grp: TTyGridHeaderGroup;
begin
  G := MakeGrid(FForm, FCtl);
  grp := G.HeaderGroups.Add;
  grp.Text := 'G';
  grp.FirstCol := 0;
  grp.LastCol := 1;                         { A and B under one group header }
  G.DragHeader(180, 100);                   { C onto B }
  AssertEquals('a column outside the group does not enter it', 'ABCD', ScreenOrder(G));
  G.DragHeader(100, 180);                   { B onto C }
  AssertEquals('a column in the group does not leave it', 'ABCD', ScreenOrder(G));
  G.DragHeader(100, 20);                    { B onto A }
  AssertEquals('inside the group the move works', 'BACD', ScreenOrder(G));
end;

procedure TTyGridColumnMoveTest.TestHeaderGroupSpansItsColumnsInAnyOrder;
var
  G: TColMoveGrid;
  l, r: Integer;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(1, 0);                       { B A C D }
  AssertTrue('a span exists', G.SpanOf(0, 2, l, r));
  AssertEquals('it starts at B, the first of the three on screen', 0, l);
  AssertEquals('it ends after C', 240, r);
end;

{ ---- the keys ------------------------------------------------------------ }

procedure TTyGridColumnMoveTest.TestArrowKeysWalkTheScreenOrder;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.Col := 1;
  G.Key(VK_RIGHT, []);
  AssertEquals('right of B is C', 2, G.Col);
  G.Key(VK_RIGHT, []);
  AssertEquals('right of C is A', 0, G.Col);
  G.Key(VK_RIGHT, []);
  AssertEquals('right of A is D', 3, G.Col);
  G.Key(VK_RIGHT, []);
  AssertEquals('D is the last on screen', 3, G.Col);
  G.Key(VK_LEFT, []);
  AssertEquals('left of D is A', 0, G.Col);
  G.Key(VK_HOME, []);
  AssertEquals('Home goes to the first on screen', 1, G.Col);
  G.Key(VK_END, []);
  AssertEquals('End goes to the last on screen', 3, G.Col);
  G.Col := 1;
  G.Key(VK_LEFT, []);
  AssertEquals('B is the first on screen: Left stays', 1, G.Col);
  G.MoveColumn(3, 1);                       { D B C A }
  G.Col := 0;
  G.Key(VK_RIGHT, []);
  AssertEquals('A is the last on screen: Right stays', 0, G.Col);
end;

procedure TTyGridColumnMoveTest.TestTabWalksTheScreenOrderAndWraps;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.Options := G.Options + [goTabs];
  G.MoveColumn(0, 2);                       { B C A D }
  G.Col := 2;                               { C }
  G.Row := 1;
  G.Key(VK_TAB, []);
  AssertEquals('Tab after C is A', 0, G.Col);
  G.Key(VK_TAB, []);
  AssertEquals('after A is D', 3, G.Col);
  G.Key(VK_TAB, []);
  AssertEquals('D ends the row on screen: Tab wraps to B', 1, G.Col);
  AssertEquals('on the next row', 2, G.Row);
  G.Key(VK_TAB, [ssShift]);
  AssertEquals('Shift+Tab goes back to D', 3, G.Col);
  AssertEquals('on the row before', 1, G.Row);
  G.Key(VK_TAB, [ssShift]);
  AssertEquals('then A', 0, G.Col);
  G.Key(VK_TAB, [ssShift]);
  AssertEquals('then C', 2, G.Col);
  AssertEquals('still on that row', 1, G.Row);
  G.MoveColumn(3, 1);                       { D B C A }
  G.Col := 3;                               { D, first on screen }
  G.Key(VK_TAB, []);
  AssertEquals('Tab after D is B', 1, G.Col);
  AssertEquals('D does not end the row: no wrap', 1, G.Row);
end;

procedure TTyGridColumnMoveTest.TestHiddenColumnIsSkippedInScreenOrder;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.HideColumn(2);                          { B A D on screen }
  G.Col := 1;
  G.Key(VK_RIGHT, []);
  AssertEquals('right of B is A once C is hidden', 0, G.Col);
  G.ShowColumn(2);
  G.HideColumn(0);                          { B C D on screen, A hidden between C and D }
  G.Col := 2;
  G.Key(VK_RIGHT, []);
  AssertEquals('right of C, past the hidden A, is D', 3, G.Col);
end;

procedure TTyGridColumnMoveTest.TestReadOnlyColumnIsSkippedInScreenOrder;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.SkipReadOnlyCells := True;
  G.MoveColumn(0, 2);                       { B C A D }
  (G.Header.Columns.Items[0] as TTyGridColumn).ReadOnly := True;   { A }
  G.Col := 2;                               { C }
  G.Key(VK_RIGHT, []);
  AssertEquals('right of C, past the read-only A, is D', 3, G.Col);
end;

{ ---- selection, clipboard, fill ------------------------------------------- }

procedure TTyGridColumnMoveTest.TestRangeSelectionCoversWhatLiesBetweenOnScreen;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.SelectRange(1, 0, 0, 0);                { from B to A }
  AssertTrue('B selected', G.IsCellSelected(1, 0));
  AssertTrue('C, between them on screen, selected', G.IsCellSelected(2, 0));
  AssertTrue('A selected', G.IsCellSelected(0, 0));
  AssertFalse('D, past A on screen, not selected', G.IsCellSelected(3, 0));
  G.SelectRange(1, 0, 2, 0);                { B and C, the first two on screen }
  AssertTrue('C selected', G.IsCellSelected(2, 0));
  AssertFalse('A, index 0 but third on screen, not selected', G.IsCellSelected(0, 0));
end;

procedure TTyGridColumnMoveTest.TestSelectAllAndSelectRowsCoverEveryColumn;
var
  G: TColMoveGrid;
  i: Integer;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.SelectAll;
  for i := 0 to 3 do
    AssertTrue('Select all: column ' + IntToStr(i), G.IsCellSelected(i, 2));
  G.SelectRows(1, 2);
  for i := 0 to 3 do
    AssertTrue('Select rows: column ' + IntToStr(i), G.IsCellSelected(i, 1));
end;

procedure TTyGridColumnMoveTest.TestSelectionReportsTheColumnsAtBothEnds;
var
  G: TColMoveGrid;
  s: TRect;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.SelectRange(1, 0, 0, 1);                { from B to A }
  s := G.Selection;
  AssertEquals('Left: B, at the left end on screen', 1, s.Left);
  AssertEquals('Right: A, at the right end', 0, s.Right);
  s := G.SelectedRange[0];
  AssertEquals('SelectedRange agrees: Left', 1, s.Left);
  AssertEquals('SelectedRange agrees: Right', 0, s.Right);
  G.ClearSelection;
  G.Selection := s;
  AssertTrue('written back, C between them is selected again', G.IsCellSelected(2, 1));
  AssertFalse('and D is not', G.IsCellSelected(3, 1));
end;

procedure TTyGridColumnMoveTest.TestFillHandleSitsAtTheSelectionsEdgeOnScreen;
var
  G: TColMoveGrid;
  h: TRect;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.SelectRange(1, 1, 2, 2);                { B and C: the first 160 px }
  h := G.FillHandleRect;
  AssertFalse('premise: there is a handle', IsRectEmpty(h));
  AssertTrue('the handle sits at C''s right edge, 160', (h.Left < 160) and (h.Right > 155));
  AssertTrue('not out at A''s, 240', h.Right < 200);
end;

procedure TTyGridColumnMoveTest.TestMergeSelectionTakesTheColumnsOnScreen;
var
  G: TColMoveGrid;
  cs, rs: Integer;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.SelectRange(2, 0, 0, 0);                { C and A: side by side, but not 2 then 3 }
  AssertFalse('columns that are not consecutive by index do not merge', G.MergeSelection);
  AssertFalse('nothing merged', G.CellSpan(1, 0, cs, rs));
  G.SelectRange(1, 0, 2, 0);                { B and C: side by side, 1 then 2 }
  AssertTrue('these merge', G.MergeSelection);
  AssertTrue('B0 spans', G.CellSpan(1, 0, cs, rs));
  AssertEquals('two columns', 2, cs);
end;

procedure TTyGridColumnMoveTest.TestCopyFollowsTheScreenOrder;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.SelectRange(1, 0, 0, 0);                { from B to A }
  AssertEquals('copied as seen', 'B0'#9'C0'#9'A0', Trim(G.SelectionAsText));
end;

procedure TTyGridColumnMoveTest.TestPasteFillsColumnsInScreenOrder;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.Col := 1;
  G.Row := 0;
  G.PasteFromText('x'#9'y'#9'z');
  AssertEquals('first value into B', 'x', G.Cells[1, 0]);
  AssertEquals('second into C', 'y', G.Cells[2, 0]);
  AssertEquals('third into A', 'z', G.Cells[0, 0]);
  AssertEquals('D untouched', 'D0', G.Cells[3, 0]);
end;

procedure TTyGridColumnMoveTest.TestPasteGrowsByTheCursorsPlaceOnScreen;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.AutoGrowOnPaste := True;
  G.MoveColumn(0, 2);                       { B C A D }
  G.Col := 0;                               { A, third on screen }
  G.Row := 0;
  G.PasteFromText('x'#9'y'#9'z');           { A, D, and one more }
  AssertEquals('one column added for the third value', 5, G.Header.Columns.Count);
  AssertEquals('first into A', 'x', G.Cells[0, 0]);
  AssertEquals('second into D', 'y', G.Cells[3, 0]);
  AssertEquals('third into the new column', 'z', G.Cells[4, 0]);
end;

procedure TTyGridColumnMoveTest.TestFillDownUsesTheSelectedScreenColumns;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(2, 0);                       { C A B D }
  G.Cells[2, 0] := '1';   G.Cells[2, 1] := '2';
  G.Cells[0, 0] := '10';  G.Cells[0, 1] := '20';
  G.Cells[1, 0] := '100'; G.Cells[1, 1] := '200';
  G.SelectRange(2, 0, 0, 1);                { C and A, rows 0..1 }
  G.FillFromSelectionTo(0, 2);
  AssertEquals('C filled', '3', G.Cells[2, 2]);
  AssertEquals('A filled', '30', G.Cells[0, 2]);
  AssertEquals('B, not selected, untouched', 'B2', G.Cells[1, 2]);
end;

procedure TTyGridColumnMoveTest.TestFindNextWalksTheScreenOrder;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.Cells[0, 0] := 'x';                     { A0, third on screen }
  G.Cells[3, 0] := 'x';                     { D0, fourth }
  G.Col := 1;                               { B, first on screen }
  G.Row := 0;
  AssertTrue('found', G.FindNext('x', False, True));
  AssertEquals('the next match to the right on screen is A0', 0, G.Col);
  AssertTrue('found again', G.FindNext('x', False, True));
  AssertEquals('then D0', 3, G.Col);
end;

procedure TTyGridColumnMoveTest.TestReplaceOnceTakesTheFirstOnScreen;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.Cells[0, 0] := 'x';                     { A0, third on screen }
  G.Cells[1, 0] := 'x';                     { B0, first }
  AssertEquals('one replaced', 1, G.ReplaceCells('x', 'y', False, True, False));
  AssertEquals('the first on screen', 'y', G.Cells[1, 0]);
  AssertEquals('A0 left for the next one', 'x', G.Cells[0, 0]);
end;

{ ---- merges --------------------------------------------------------------- }

procedure TTyGridColumnMoveTest.TestMergeSplitByAMoveIsSuspended;
var
  G: TColMoveGrid;
  cs, rs: Integer;
begin
  G := MakeGrid(FForm, FCtl);
  G.MergeCells(0, 0, 2, 1);                 { A0 spans A and B }
  G.CellSpan(0, 0, cs, rs);
  AssertEquals('premise: two columns wide', 2, cs);
  G.MoveColumn(3, 0);                       { D A B C: A and B still side by side }
  G.CellSpan(0, 0, cs, rs);
  AssertEquals('a move that keeps them together keeps the merge', 2, cs);
  G.MoveColumn(2, 1);                       { D A C B: C between them }
  AssertEquals('premise', 'DACB', ScreenOrder(G));
  G.CellSpan(0, 0, cs, rs);
  AssertEquals('A and B no longer side by side: the merge is off', 1, cs);
  PutInOrder(G, [3, 1, 0, 2]);              { D B A C: side by side, but B first }
  G.CellSpan(0, 0, cs, rs);
  AssertEquals('B before A is not the merged block either', 1, cs);
  PutInOrder(G, [0, 1, 2, 3]);
  G.CellSpan(0, 0, cs, rs);
  AssertEquals('put back, it is there again', 2, cs);
end;

{ ---- the order survives the other column operations ----------------------- }

procedure TTyGridColumnMoveTest.TestUndoPutsAFarMoveBack;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.ClearUndo;
  G.MoveColumn(0, 2);                       { B C A D }
  AssertEquals('premise', 'BCAD', ScreenOrder(G));
  G.Undo;
  AssertEquals('undone', 'ABCD', ScreenOrder(G));
  G.Redo;
  AssertEquals('redone', 'BCAD', ScreenOrder(G));
end;

procedure TTyGridColumnMoveTest.TestInsertAfterAMoveKeepsTheScreenOrder;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.InsertColumn(1);                        { a new column at index 1, where B was }
  TTyColumn(G.Header.Columns.Items[1]).Text := 'E';
  AssertEquals('the new column comes in before B; the rest keep their order',
    'EBCAD', ScreenOrder(G));
  G.DeleteColumn(1);
  AssertEquals('deleting it gives the order back', 'BCAD', ScreenOrder(G));
end;

procedure TTyGridColumnMoveTest.TestUndoOfDeleteRestoresTheColumnsPlace;
var
  G: TColMoveGrid;
begin
  G := MakeGrid(FForm, FCtl);
  G.MoveColumn(0, 2);                       { B C A D }
  G.ClearUndo;
  G.DeleteColumn(2);                        { C }
  AssertEquals('premise', 'BAD', ScreenOrder(G));
  G.Undo;
  AssertEquals('C comes back where it stood', 'BCAD', ScreenOrder(G));
end;

procedure TTyGridColumnMoveTest.TestLayoutRoundTripKeepsAnyOrder;
var
  G: TColMoveGrid;
  s: string;
begin
  G := MakeGrid(FForm, FCtl);
  { D C A B: an order that setting the saved places column by column, in index
    order, does not reach -- it has to be done place by place. }
  PutInOrder(G, [3, 2, 0, 1]);
  AssertEquals('premise', 'DCAB', ScreenOrder(G));
  s := G.SaveLayoutToString;
  PutInOrder(G, [0, 1, 2, 3]);
  AssertEquals('premise: reset', 'ABCD', ScreenOrder(G));
  AssertTrue('the layout loads', G.LoadLayoutFromString(s));
  AssertEquals('the saved order comes back', 'DCAB', ScreenOrder(G));
end;

initialization
  RegisterTest(TTyGridColumnMoveTest);
end.
