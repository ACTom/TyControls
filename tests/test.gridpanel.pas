unit test.gridpanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, fpcunit, testregistry,
  tyControls.GridPanel, tyControls.GridCell;
type
  { Pure grid-math functions — the headless-tested core (no window handle). }
  TTyGridMathTest = class(TTestCase)
  private
    function Tracks(const AKinds: array of TTyGridTrackKind;
      const AValues: array of Integer): TTyGridTracks;
  published
    procedure TestPureAbsolute;
    procedure TestAbsoluteClampsNegative;
    procedure TestPurePercent;
    procedure TestPercentRounds;
    procedure TestPercentOfUsableAccountsSpacing;
    procedure TestPureStarEqualSplit;
    procedure TestStarLastAbsorbsRemainder;
    procedure TestMixedAbsolutePercentStar;
    procedure TestOverSubscriptionClampsStarPoolToZero;
    procedure TestOverSubscriptionAbsoluteNeverNegative;
    procedure TestSpacingReducesUsable;
    procedure TestZeroTracks;
    procedure TestSingleTrackNoGutter;
    procedure TestNegativeSpacingClampsToZero;
    procedure TestOrigins;
    procedure TestOriginsEmpty;
    // TyGridCellRect
    procedure TestCellRectSingleCell;
    procedure TestCellRectColSpan;
    procedure TestCellRectRowSpan;
    procedure TestCellRectFullSpan;
    procedure TestCellRectSpanClampsToGrid;
    procedure TestCellRectOutOfRangeEmpty;
    procedure TestCellRectSpanBelowOneTreatedAsOne;
    procedure TestCellRectEmptyTracksEmpty;
    procedure TestCellRectSingleRowCol;
  end;

  { The control: cell-matrix lifecycle — counts create cells, accessor by (col,row),
    grow preserves in-bounds cells + content, shrink frees out-of-bounds cells. }
  TTyGridPanelTest = class(TTestCase)
  published
    procedure TestCountCreatesCells;
    procedure TestCellsAccessorReturnsByColRow;
    procedure TestGrowPreservesInBoundsCells;
    procedure TestShrinkFreesOutOfBoundsCells;
  end;

implementation

{ ---------------------------------------------------------------------------- }
{ TTyGridMathTest                                                              }
{ ---------------------------------------------------------------------------- }

function TTyGridMathTest.Tracks(const AKinds: array of TTyGridTrackKind;
  const AValues: array of Integer): TTyGridTracks;
var i: Integer;
begin
  SetLength(Result, Length(AKinds));
  for i := 0 to High(AKinds) do
  begin
    Result[i].Kind := AKinds[i];
    if i <= High(AValues) then Result[i].Value := AValues[i] else Result[i].Value := 0;
  end;
end;

procedure TTyGridMathTest.TestPureAbsolute;
var r: TTyGridIntArray;
begin
  // Two absolute tracks, no spacing: they take their exact px.
  r := TyGridTrackSizes(300, 0, Tracks([tgtAbsolute, tgtAbsolute], [120, 80]));
  AssertEquals('two absolute tracks', 2, Length(r));
  AssertEquals('abs 0', 120, r[0]);
  AssertEquals('abs 1', 80, r[1]);
end;

procedure TTyGridMathTest.TestAbsoluteClampsNegative;
var r: TTyGridIntArray;
begin
  r := TyGridTrackSizes(300, 0, Tracks([tgtAbsolute, tgtAbsolute], [-50, 100]));
  AssertEquals('negative absolute clamps to 0', 0, r[0]);
  AssertEquals('other absolute unaffected', 100, r[1]);
end;

procedure TTyGridMathTest.TestPurePercent;
var r: TTyGridIntArray;
begin
  // 25% + 75% of 400 (no spacing) = 100 + 300.
  r := TyGridTrackSizes(400, 0, Tracks([tgtPercent, tgtPercent], [25, 75]));
  AssertEquals('25% of 400', 100, r[0]);
  AssertEquals('75% of 400', 300, r[1]);
end;

procedure TTyGridMathTest.TestPercentRounds;
var r: TTyGridIntArray;
begin
  // 33% of 100 = 33.0 -> 33 ; 50% of 101 = 50.5 -> 51 (round half up).
  r := TyGridTrackSizes(100, 0, Tracks([tgtPercent], [33]));
  AssertEquals('33% of 100 rounds to 33', 33, r[0]);
  r := TyGridTrackSizes(101, 0, Tracks([tgtPercent], [50]));
  AssertEquals('50% of 101 rounds to 51', 51, r[0]);
end;

procedure TTyGridMathTest.TestPercentOfUsableAccountsSpacing;
var r: TTyGridIntArray;
begin
  // total 210, spacing 10, 2 tracks -> usable 200; 50% each = 100/100.
  r := TyGridTrackSizes(210, 10, Tracks([tgtPercent, tgtPercent], [50, 50]));
  AssertEquals('percent uses usable (total-gutters)', 100, r[0]);
  AssertEquals('percent uses usable 1', 100, r[1]);
end;

procedure TTyGridMathTest.TestPureStarEqualSplit;
var r: TTyGridIntArray;
begin
  // 3 star tracks of 300 (no spacing) -> 100 each.
  r := TyGridTrackSizes(300, 0, Tracks([tgtStar, tgtStar, tgtStar], []));
  AssertEquals('star 0', 100, r[0]);
  AssertEquals('star 1', 100, r[1]);
  AssertEquals('star 2', 100, r[2]);
end;

procedure TTyGridMathTest.TestStarLastAbsorbsRemainder;
var r: TTyGridIntArray;
begin
  // 100 across 3 stars: 33,33,34 (last absorbs remainder) -> sum == 100.
  r := TyGridTrackSizes(100, 0, Tracks([tgtStar, tgtStar, tgtStar], []));
  AssertEquals('star 0 = floor', 33, r[0]);
  AssertEquals('star 1 = floor', 33, r[1]);
  AssertEquals('last star absorbs remainder', 34, r[2]);
  AssertEquals('sum equals total', 100, r[0] + r[1] + r[2]);
end;

procedure TTyGridMathTest.TestMixedAbsolutePercentStar;
var r: TTyGridIntArray;
begin
  // total 400, no spacing. abs 100, 25% (=100), star gets leftover 200.
  r := TyGridTrackSizes(400, 0,
    Tracks([tgtAbsolute, tgtPercent, tgtStar], [100, 25, 0]));
  AssertEquals('absolute', 100, r[0]);
  AssertEquals('percent 25% of 400', 100, r[1]);
  AssertEquals('star gets leftover 400-100-100', 200, r[2]);
end;

procedure TTyGridMathTest.TestOverSubscriptionClampsStarPoolToZero;
var r: TTyGridIntArray;
begin
  // abs 250 + abs 100 = 350 > 300 total; the single star pool floors at 0.
  r := TyGridTrackSizes(300, 0,
    Tracks([tgtAbsolute, tgtAbsolute, tgtStar], [250, 100, 0]));
  AssertEquals('abs 0 kept', 250, r[0]);
  AssertEquals('abs 1 kept', 100, r[1]);
  AssertEquals('over-subscribed star clamps to 0', 0, r[2]);
end;

procedure TTyGridMathTest.TestOverSubscriptionAbsoluteNeverNegative;
var r: TTyGridIntArray;
begin
  // No star, absolutes exceed total: each track keeps its own px (>=0), none negative.
  r := TyGridTrackSizes(100, 0, Tracks([tgtAbsolute, tgtAbsolute], [80, 80]));
  AssertEquals('abs 0', 80, r[0]);
  AssertEquals('abs 1', 80, r[1]);
  AssertTrue('no negative track', (r[0] >= 0) and (r[1] >= 0));
end;

procedure TTyGridMathTest.TestSpacingReducesUsable;
var r: TTyGridIntArray;
begin
  // total 320, spacing 20, 2 star tracks -> usable 300 -> 150 each.
  r := TyGridTrackSizes(320, 20, Tracks([tgtStar, tgtStar], []));
  AssertEquals('spacing removes one 20px gutter -> 150 each', 150, r[0]);
  AssertEquals('spacing 1', 150, r[1]);
end;

procedure TTyGridMathTest.TestZeroTracks;
var r: TTyGridIntArray;
begin
  r := TyGridTrackSizes(300, 4, Tracks([], []));
  AssertEquals('no tracks -> empty result', 0, Length(r));
end;

procedure TTyGridMathTest.TestSingleTrackNoGutter;
var r: TTyGridIntArray;
begin
  // 1 star track: no gutters subtracted, star fills the whole total.
  r := TyGridTrackSizes(300, 25, Tracks([tgtStar], []));
  AssertEquals('single track: no gutter, fills total', 300, r[0]);
end;

procedure TTyGridMathTest.TestNegativeSpacingClampsToZero;
var r: TTyGridIntArray;
begin
  r := TyGridTrackSizes(200, -10, Tracks([tgtStar, tgtStar], []));
  AssertEquals('negative spacing treated as 0 -> 100 each', 100, r[0]);
  AssertEquals('negative spacing 1', 100, r[1]);
end;

procedure TTyGridMathTest.TestOrigins;
var r: TTyGridIntArray;
begin
  // lengths [100,50,80], spacing 10 -> origins 0, 110, 170.
  r := TyGridTrackOrigins(TTyGridIntArray.Create(100, 50, 80), 10);
  AssertEquals('origin 0', 0, r[0]);
  AssertEquals('origin 1 = 100+10', 110, r[1]);
  AssertEquals('origin 2 = 110+50+10', 170, r[2]);
end;

procedure TTyGridMathTest.TestOriginsEmpty;
var r: TTyGridIntArray;
begin
  r := TyGridTrackOrigins(nil, 8);
  AssertEquals('empty lengths -> empty origins', 0, Length(r));
end;

procedure TTyGridMathTest.TestCellRectSingleCell;
var rc: TRect;
begin
  // 3x2 grid, cell (1,0) no span.
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0, 100, 200),   // colX
    TTyGridIntArray.Create(100, 100, 100), // colW
    TTyGridIntArray.Create(0, 60),         // rowY
    TTyGridIntArray.Create(60, 60),        // rowH
    1, 0, 1, 1);
  AssertEquals('left', 100, rc.Left);
  AssertEquals('top', 0, rc.Top);
  AssertEquals('right', 200, rc.Right);
  AssertEquals('bottom', 60, rc.Bottom);
end;

procedure TTyGridMathTest.TestCellRectColSpan;
var rc: TRect;
begin
  // Span 2 columns starting at col 0 -> unions col 0 and col 1.
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0, 100, 200),
    TTyGridIntArray.Create(100, 100, 100),
    TTyGridIntArray.Create(0, 60),
    TTyGridIntArray.Create(60, 60),
    0, 0, 2, 1);
  AssertEquals('left', 0, rc.Left);
  AssertEquals('right spans two columns', 200, rc.Right);
  AssertEquals('bottom single row', 60, rc.Bottom);
end;

procedure TTyGridMathTest.TestCellRectRowSpan;
var rc: TRect;
begin
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0, 100),
    TTyGridIntArray.Create(100, 100),
    TTyGridIntArray.Create(0, 60, 120),
    TTyGridIntArray.Create(60, 60, 60),
    0, 0, 1, 2);
  AssertEquals('top', 0, rc.Top);
  AssertEquals('bottom spans two rows', 120, rc.Bottom);
  AssertEquals('right single col', 100, rc.Right);
end;

procedure TTyGridMathTest.TestCellRectFullSpan;
var rc: TRect;
begin
  // Span the whole 2x2 grid.
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0, 100),
    TTyGridIntArray.Create(100, 100),
    TTyGridIntArray.Create(0, 60),
    TTyGridIntArray.Create(60, 60),
    0, 0, 2, 2);
  AssertEquals('left', 0, rc.Left);
  AssertEquals('top', 0, rc.Top);
  AssertEquals('right', 200, rc.Right);
  AssertEquals('bottom', 120, rc.Bottom);
end;

procedure TTyGridMathTest.TestCellRectSpanClampsToGrid;
var rc: TRect;
begin
  // colspan 9 from col 1 in a 3-col grid -> clamps to the last column.
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0, 100, 200),
    TTyGridIntArray.Create(100, 100, 100),
    TTyGridIntArray.Create(0),
    TTyGridIntArray.Create(60),
    1, 0, 9, 9);
  AssertEquals('left at col 1', 100, rc.Left);
  AssertEquals('right clamps to last column edge (300)', 300, rc.Right);
  AssertEquals('bottom clamps to single row', 60, rc.Bottom);
end;

procedure TTyGridMathTest.TestCellRectOutOfRangeEmpty;
var rc: TRect;
begin
  // col 5 in a 2-col grid -> empty rect.
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0, 100),
    TTyGridIntArray.Create(100, 100),
    TTyGridIntArray.Create(0),
    TTyGridIntArray.Create(60),
    5, 0, 1, 1);
  AssertTrue('out-of-range col -> empty rect',
    (rc.Left = 0) and (rc.Top = 0) and (rc.Right = 0) and (rc.Bottom = 0));
  // negative row -> empty
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0, 100),
    TTyGridIntArray.Create(100, 100),
    TTyGridIntArray.Create(0),
    TTyGridIntArray.Create(60),
    0, -1, 1, 1);
  AssertTrue('negative row -> empty rect',
    (rc.Right = 0) and (rc.Bottom = 0));
end;

procedure TTyGridMathTest.TestCellRectSpanBelowOneTreatedAsOne;
var rc: TRect;
begin
  // colspan 0 / rowspan 0 must behave like 1 (single cell), not empty.
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0, 100),
    TTyGridIntArray.Create(100, 100),
    TTyGridIntArray.Create(0, 60),
    TTyGridIntArray.Create(60, 60),
    0, 0, 0, 0);
  AssertEquals('span 0 acts as 1: right', 100, rc.Right);
  AssertEquals('span 0 acts as 1: bottom', 60, rc.Bottom);
end;

procedure TTyGridMathTest.TestCellRectEmptyTracksEmpty;
var rc: TRect;
begin
  rc := TyGridCellRect(nil, nil, nil, nil, 0, 0, 1, 1);
  AssertTrue('empty track lists -> empty rect',
    (rc.Right = 0) and (rc.Bottom = 0));
end;

procedure TTyGridMathTest.TestCellRectSingleRowCol;
var rc: TRect;
begin
  // 1x1 grid, the only cell.
  rc := TyGridCellRect(
    TTyGridIntArray.Create(0),
    TTyGridIntArray.Create(150),
    TTyGridIntArray.Create(0),
    TTyGridIntArray.Create(90),
    0, 0, 1, 1);
  AssertEquals('single cell right', 150, rc.Right);
  AssertEquals('single cell bottom', 90, rc.Bottom);
end;

{ ---------------------------------------------------------------------------- }
{ TTyGridPanelTest                                                            }
{ ---------------------------------------------------------------------------- }

procedure TTyGridPanelTest.TestCountCreatesCells;
var g: TTyGridPanel;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.ColumnCount := 3;
    g.RowCount := 2;
    AssertEquals('3x2 -> 6 cells', 6, g.CellCount);
  finally
    g.Free;
  end;
end;

procedure TTyGridPanelTest.TestCellsAccessorReturnsByColRow;
var g: TTyGridPanel; c: TTyGridCell;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.ColumnCount := 3; g.RowCount := 2;
    c := TTyGridCell(g.Cells[2, 1]);
    AssertTrue('cell exists', c <> nil);
    AssertEquals('col', 2, c.Col);
    AssertEquals('row', 1, c.Row);
  finally
    g.Free;
  end;
end;

procedure TTyGridPanelTest.TestGrowPreservesInBoundsCells;
var g: TTyGridPanel; keep: TTyGridCell; marker: TControl;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.ColumnCount := 2; g.RowCount := 2;
    keep := TTyGridCell(g.Cells[1, 1]);
    marker := TControl.Create(g);
    marker.Parent := keep;          // content dropped into cell (1,1)
    g.ColumnCount := 3;             // grow: (1,1) still in bounds
    AssertSame('same cell object kept', keep, g.Cells[1, 1]);
    AssertSame('content preserved', keep, marker.Parent);
  finally
    g.Free;
  end;
end;

procedure TTyGridPanelTest.TestShrinkFreesOutOfBoundsCells;
var g: TTyGridPanel;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.ColumnCount := 3; g.RowCount := 2;   // 6 cells
    g.ColumnCount := 2;                     // -> 4 cells; col 2 dropped
    AssertEquals('shrunk to 4', 4, g.CellCount);
    AssertTrue('no cell at old col 2', g.Cells[2, 0] = nil);
  finally
    g.Free;
  end;
end;

initialization
  RegisterTest(TTyGridMathTest);
  RegisterTest(TTyGridPanelTest);
end.
