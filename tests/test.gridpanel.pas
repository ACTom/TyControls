unit test.gridpanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller,
  tyControls.Base, tyControls.Panel, tyControls.GridPanel;
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

  { The control: track-count defaults, cell keying, FreeNotification drop, relayout math. }
  TTyGridPanelTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsPanel;
    procedure TestDefaultCounts;
    procedure TestSetColumnCountPadsStar;
    procedure TestSetColumnStyleGrows;
    procedure TestSetCellStoresKeyed;
    procedure TestSetCellUpdatesExisting;
    procedure TestSetCellClampsSpan;
    procedure TestRemoveCell;
    procedure TestFreedChildDropsCell;
    procedure TestLayoutPlacesChildInCell;
    procedure TestLayoutSpanUnionRect;
    procedure TestLayoutSpacingInset;
  end;

implementation

type
  TGridAccess = class(TTyGridPanel)
  public
    function StyleTypeKey: string;
  end;

function TGridAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

{ helper: a plain child of a given size at a given position }
function MakeChild(AParent: TWinControl; AL, AT, AW, AH: Integer): TControl;
var c: TTyPanel;
begin
  c := TTyPanel.Create(AParent);
  c.Parent := AParent;
  c.SetBounds(AL, AT, AW, AH);
  Result := c;
end;

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

procedure TTyGridPanelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyGridPanelTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyGridPanelTest.TestTypeKeyIsPanel;
var G: TGridAccess;
begin
  G := TGridAccess.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  AssertEquals('reuses TyPanel typeKey', 'TyPanel', G.StyleTypeKey);
end;

procedure TTyGridPanelTest.TestDefaultCounts;
var G: TTyGridPanel;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  AssertEquals('default 2 columns', 2, G.ColumnCount);
  AssertEquals('default 2 rows', 2, G.RowCount);
  AssertTrue('default columns are star', G.ColumnStyle(0).Kind = tgtStar);
  AssertTrue('default rows are star', G.RowStyle(1).Kind = tgtStar);
end;

procedure TTyGridPanelTest.TestSetColumnCountPadsStar;
var G: TTyGridPanel;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  G.ColumnCount := 4;
  AssertEquals('column count grew to 4', 4, G.ColumnCount);
  AssertTrue('new column 3 padded as star', G.ColumnStyle(3).Kind = tgtStar);
  G.ColumnCount := 1;
  AssertEquals('column count shrank to 1', 1, G.ColumnCount);
end;

procedure TTyGridPanelTest.TestSetColumnStyleGrows;
var G: TTyGridPanel;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  // Sizing a track beyond the current count grows the array (gap padded star).
  G.SetColumnStyle(4, tgtAbsolute, 120);
  AssertEquals('grew to 5 columns', 5, G.ColumnCount);
  AssertTrue('column 4 is absolute', G.ColumnStyle(4).Kind = tgtAbsolute);
  AssertEquals('column 4 value', 120, G.ColumnStyle(4).Value);
  AssertTrue('gap column 3 padded star', G.ColumnStyle(3).Kind = tgtStar);
  // out-of-range read returns a default
  AssertTrue('out-of-range read is star default', G.ColumnStyle(99).Kind = tgtStar);
end;

procedure TTyGridPanelTest.TestSetCellStoresKeyed;
var G: TTyGridPanel; child: TControl; c, r, cs, rs: Integer;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  G.SetBounds(0, 0, 200, 150);
  child := MakeChild(G, 0, 0, 10, 10);
  G.SetCell(child, 1, 0, 1, 1);
  AssertEquals('one cell assigned', 1, G.CellCount);
  AssertTrue('cell retrievable by control', G.GetCell(child, c, r, cs, rs));
  AssertEquals('col', 1, c);
  AssertEquals('row', 0, r);
  AssertEquals('colspan', 1, cs);
  AssertEquals('rowspan', 1, rs);
end;

procedure TTyGridPanelTest.TestSetCellUpdatesExisting;
var G: TTyGridPanel; child: TControl; c, r, cs, rs: Integer;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  G.SetBounds(0, 0, 200, 150);
  child := MakeChild(G, 0, 0, 10, 10);
  G.SetCell(child, 0, 0, 1, 1);
  G.SetCell(child, 1, 1, 2, 2);   // re-assign, must not add a second slot
  AssertEquals('still one cell (updated in place)', 1, G.CellCount);
  G.GetCell(child, c, r, cs, rs);
  AssertEquals('updated col', 1, c);
  AssertEquals('updated row', 1, r);
  AssertEquals('updated colspan', 2, cs);
  AssertEquals('updated rowspan', 2, rs);
end;

procedure TTyGridPanelTest.TestSetCellClampsSpan;
var G: TTyGridPanel; child: TControl; c, r, cs, rs: Integer;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  child := MakeChild(G, 0, 0, 10, 10);
  G.SetCell(child, 0, 0, 0, -3);   // spans below 1 clamp to 1
  G.GetCell(child, c, r, cs, rs);
  AssertEquals('colspan clamped to 1', 1, cs);
  AssertEquals('rowspan clamped to 1', 1, rs);
end;

procedure TTyGridPanelTest.TestRemoveCell;
var G: TTyGridPanel; child: TControl; c, r, cs, rs: Integer;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  child := MakeChild(G, 0, 0, 10, 10);
  G.SetCell(child, 0, 0);
  AssertEquals('assigned', 1, G.CellCount);
  G.RemoveCell(child);
  AssertEquals('removed', 0, G.CellCount);
  AssertFalse('no longer retrievable', G.GetCell(child, c, r, cs, rs));
  // removing again is a no-op
  G.RemoveCell(child);
  AssertEquals('remove twice is a no-op', 0, G.CellCount);
end;

procedure TTyGridPanelTest.TestFreedChildDropsCell;
var G: TTyGridPanel; child: TControl;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  child := MakeChild(G, 0, 0, 10, 10);
  G.SetCell(child, 0, 0);
  AssertEquals('assigned before free', 1, G.CellCount);
  child.Free;   // FreeNotification must drop the dangling key
  AssertEquals('freed child dropped its cell assignment', 0, G.CellCount);
end;

procedure TTyGridPanelTest.TestLayoutPlacesChildInCell;
var G: TTyGridPanel; child: TControl;
begin
  // 2x2 all-star grid, 200x150 client (no border in the default theme -> ClientRect
  // origin 0), spacing 0 so the cell math is exact. Column 1 / row 0.
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  G.Spacing := 0;
  G.SetBounds(0, 0, 200, 150);
  child := MakeChild(G, 0, 0, 10, 10);
  G.SetCell(child, 1, 0, 1, 1);   // relayout runs inside SetCell
  // With spacing 0, 2 star columns of 200 -> 100 each; cell (1,0) starts at x=100.
  AssertEquals('child placed at column 1 origin', 100, child.Left);
  AssertEquals('child placed at row 0 origin', 0, child.Top);
  AssertEquals('child width = one column', 100, child.Width);
  // 2 star rows of 150 -> 75 each.
  AssertEquals('child height = one row', 75, child.Height);
end;

procedure TTyGridPanelTest.TestLayoutSpanUnionRect;
var G: TTyGridPanel; child: TControl;
begin
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  G.Spacing := 0;
  G.SetBounds(0, 0, 200, 150);
  child := MakeChild(G, 0, 0, 10, 10);
  G.SetCell(child, 0, 0, 2, 2);   // span the whole grid
  AssertEquals('span left', 0, child.Left);
  AssertEquals('span top', 0, child.Top);
  AssertEquals('span width covers both columns', 200, child.Width);
  AssertEquals('span height covers both rows', 150, child.Height);
end;

procedure TTyGridPanelTest.TestLayoutSpacingInset;
var G: TTyGridPanel; child: TControl;
begin
  // Spacing 10 insets the cell rect by 10 on every side. Cell (0,0) in a 2-col grid:
  // usable width = 200 - 10 (one gutter) = 190 -> col 0 = 95; cell rect x=[0..95];
  // inset by 10 -> left 10, width 95-20 = 75.
  G := TTyGridPanel.Create(FForm);
  G.Parent := FForm;
  G.Font.PixelsPerInch := 96;
  G.Spacing := 10;
  G.SetBounds(0, 0, 200, 150);
  child := MakeChild(G, 0, 0, 10, 10);
  G.SetCell(child, 0, 0, 1, 1);
  AssertEquals('cell inset by spacing on the left', 10, child.Left);
  AssertEquals('cell inset by spacing on the top', 10, child.Top);
  AssertEquals('cell width = col width minus 2*spacing', 75, child.Width);
end;

initialization
  RegisterTest(TTyGridMathTest);
  RegisterTest(TTyGridPanelTest);
end.
