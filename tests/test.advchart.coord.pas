unit test.advchart.coord;
{$mode objfpc}{$H+}
{ CONTRACT 1 ACCEPTANCE (Tier 0 spec 搂8 items 3 and 4).
  DataToPoint / PointToData must round trip within half a pixel, and the rect
  DataToLayout returns must contain the point DataToPoint returns 鈥?if those two
  can disagree, the pointer and the pixels can disagree, which is the single rule
  the TTySegmented discipline exists to enforce. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale, tyControls.AdvChart.Coord;
type
  TAdvChartCartesianTest = class(TTestCase)
  private
    function MakeCartesian(const ARect: TTyRectF): TTyCartesian2D;
    function MakeCategoryCartesian(const ARect: TTyRectF; ACount: Integer): TTyCartesian2D;
  published
    procedure TestDataToPointCorners;
    procedure TestYAxisIsInverted;
    procedure TestRoundTripWithinHalfPixel;
    procedure TestContainPointMatchesRect;
    procedure TestOutOfExtentIsStillMapped;
    procedure TestDataToLayoutContainsItsAnchor;
    procedure TestDataToLayoutIsBandWide;
    procedure TestContentRectIsInsideRect;
    procedure TestInvalidDataGivesInvalidPointAndRect;
    procedure TestThirdAxisIsAddressable;
    procedure TestDataToLayoutFollowsTheCategoryAxisToY;
    procedure TestDataToLayoutGivesAHeatmapCellBothItsBands;
  end;
implementation

const
  Eps = 1e-6;

{ A cartesian whose x axis is a real CATEGORY axis of ACount categories.

  BandWidth used to be a settable number, and these tests set it -- which pinned
  a fiction: a band width on an interval scale has no source. It is derived now,
  so the fixture has to supply the thing it is derived from. The numbers below
  are unchanged because they were chosen to be exact: 400px over 10 categories
  really is a band of 40. }
function TAdvChartCartesianTest.MakeCategoryCartesian(const ARect: TTyRectF;
  ACount: Integer): TTyCartesian2D;
var
  ax: TTyAxis;
  sy: TTyIntervalScale;
  cats: TTyStringArray;
  i: Integer;
begin
  Result := TTyCartesian2D.Create;
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  SetLength(cats, ACount);
  for i := 0 to ACount - 1 do
    cats[i] := Chr(Ord('a') + i);
  ax.SetCategories(cats);
  ax.OnBand := True;
  sy := TTyIntervalScale.Create;
  sy.SetExtent(TyRange(0, 100));
  Result.AddAxis(ax);
  Result.AddAxis(TTyAxis.Create('y', sy, False));
  Result.SetRect(ARect);
end;

function TAdvChartCartesianTest.MakeCartesian(const ARect: TTyRectF): TTyCartesian2D;
var sx, sy: TTyIntervalScale;
begin
  Result := TTyCartesian2D.Create;
  sx := TTyIntervalScale.Create;
  sx.SetExtent(TyRange(0, 10));
  sy := TTyIntervalScale.Create;
  sy.SetExtent(TyRange(0, 100));
  Result.AddAxis(TTyAxis.Create('x', sx, True));
  Result.AddAxis(TTyAxis.Create('y', sy, False));
  Result.SetRect(ARect);
end;

procedure TAdvChartCartesianTest.TestDataToPointCorners;
var c: TTyCartesian2D; p: TTyPointF;
begin
  c := MakeCartesian(TyRectF(50, 20, 450, 320));
  try
    p := c.DataToPoint([0, 0]);
    AssertEquals('origin x', 50.0, p.X, Eps);
    AssertEquals('origin y is the BOTTOM', 320.0, p.Y, Eps);
    p := c.DataToPoint([10, 100]);
    AssertEquals('far x', 450.0, p.X, Eps);
    AssertEquals('far y is the TOP', 20.0, p.Y, Eps);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestYAxisIsInverted;
var c: TTyCartesian2D;
begin
  c := MakeCartesian(TyRectF(0, 0, 100, 200));
  try
    { Screen y grows downward, values grow upward. A y axis that is not
      inverted is the single most common chart bug there is. }
    AssertTrue('larger value is higher on screen',
               c.DataToPoint([5, 90]).Y < c.DataToPoint([5, 10]).Y);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestRoundTripWithinHalfPixel;
var
  c: TTyCartesian2D; i, j: Integer; dx, dy: Double;
  p: TTyPointF; back: TTyDoubleArray;
begin
  c := MakeCartesian(TyRectF(37.5, 11.25, 613.75, 402.5));
  try
    for i := 0 to 10 do
      for j := 0 to 10 do
      begin
        dx := i;
        dy := j * 10;
        p := c.DataToPoint([dx, dy]);
        AssertTrue('pointToData succeeded', c.PointToData(p, back));
        AssertEquals('x round trip', dx, back[0], 0.5 * 10 / (613.75 - 37.5));
        AssertEquals('y round trip', dy, back[1], 0.5 * 100 / (402.5 - 11.25));
      end;
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestContainPointMatchesRect;
var c: TTyCartesian2D;
begin
  c := MakeCartesian(TyRectF(50, 20, 450, 320));
  try
    AssertTrue('inside', c.ContainPoint(TyPointF(200, 200)));
    AssertTrue('top-left corner', c.ContainPoint(TyPointF(50, 20)));
    { Closed on the far edges too: a point on the right border is still in the
      chart. That is a DIFFERENT rule from the datum-cell one, on purpose. }
    AssertTrue('right border', c.ContainPoint(TyPointF(450, 200)));
    AssertFalse('left of the band', c.ContainPoint(TyPointF(49.9, 200)));
    AssertFalse('below the band', c.ContainPoint(TyPointF(200, 320.1)));
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestOutOfExtentIsStillMapped;
var c: TTyCartesian2D; p: TTyPointF;
begin
  c := MakeCartesian(TyRectF(0, 0, 100, 100));
  try
    { Clipping is the renderer's decision, not the coordinate system's 鈥?a datum
      outside the extent must still get a real point, so a clipped line can be
      drawn towards it and cut at the boundary. }
    p := c.DataToPoint([20, 0]);
    AssertFalse('not NaN', IsNan(p.X));
    AssertEquals('extrapolated linearly', 200.0, p.X, Eps);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestDataToLayoutContainsItsAnchor;
var c: TTyCartesian2D; i: Integer; p: TTyPointF; l: TTyCoordLayout;
begin
  { Eleven categories over 400px: a band of about 36.36. No literal is asserted
    here -- the claim is that each anchor lands inside its OWN cell. }
  c := MakeCategoryCartesian(TyRectF(50, 20, 450, 320), 11);
  try
    for i := 0 to 10 do
    begin
      p := c.DataToPoint([i, 50]);
      l := c.DataToLayout([i, 50]);
      AssertTrue('layout rect is valid at ' + IntToStr(i), TyRectFIsValid(l.Rect));
      AssertTrue('anchor x is inside its own cell at ' + IntToStr(i),
                 (p.X >= l.Rect.Left - Eps) and (p.X <= l.Rect.Right + Eps));
      AssertTrue('anchor y is inside its own cell at ' + IntToStr(i),
                 (p.Y >= l.Rect.Top - Eps) and (p.Y <= l.Rect.Bottom + Eps));
    end;
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestDataToLayoutIsBandWide;
var c: TTyCartesian2D; l: TTyCoordLayout;
begin
  c := MakeCategoryCartesian(TyRectF(0, 0, 400, 300), 10);
  try
    l := c.DataToLayout([5, 50]);
    AssertEquals('cell is one band wide', 40.0, TyRectFWidth(l.Rect), Eps);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestContentRectIsInsideRect;
var c: TTyCartesian2D; l: TTyCoordLayout;
begin
  c := MakeCategoryCartesian(TyRectF(0, 0, 400, 300), 10);
  try
    c.DividerWidth := 2;
    l := c.DataToLayout([5, 50]);
    AssertTrue('content rect is valid', TyRectFIsValid(l.ContentRect));
    AssertTrue('content is inset from the left', l.ContentRect.Left >= l.Rect.Left);
    AssertTrue('content is inset from the right', l.ContentRect.Right <= l.Rect.Right);
    AssertEquals('inset by half the divider on each side',
                 TyRectFWidth(l.Rect) - 2, TyRectFWidth(l.ContentRect), Eps);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestInvalidDataGivesInvalidPointAndRect;
var c: TTyCartesian2D; p: TTyPointF; l: TTyCoordLayout;
begin
  c := MakeCartesian(TyRectF(0, 0, 400, 300));
  try
    p := c.DataToPoint([NaN, 50]);
    AssertTrue('NaN in, NaN out', IsNan(p.X));
    l := c.DataToLayout([NaN, 50]);
    AssertFalse('and an invalid rect, never an empty one', TyRectFIsValid(l.Rect));
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestThirdAxisIsAddressable;
var c: TTyCartesian2D; s: TTyIntervalScale;
begin
  { N axes, not two. A secondary y axis is the commonest real-world request and
    it must not be a special case bolted on later. }
  c := MakeCartesian(TyRectF(0, 0, 400, 300));
  try
    s := TTyIntervalScale.Create;
    s.SetExtent(TyRange(0, 1));
    c.AddAxis(TTyAxis.Create('y', s, False));
    AssertEquals('three axes', 3, c.AxisCount);
    AssertEquals('the third is a y axis', 'y', c.GetAxis(2).Dim);
    AssertEquals('and it has its own scale', 1.0, c.GetAxis(2).Scale.GetExtent.Stop, Eps);
  finally
    c.Free;
  end;
end;

{ ============ the cell when the spine is not x ============ }

{ A cartesian whose CATEGORY axis is y -- a horizontal bar chart. The mirror of
  MakeCategoryCartesian, and the arrangement no fixture in this file built. }
function MakeCategoryOnY(const ARect: TTyRectF; ACount: Integer): TTyCartesian2D;
var
  ay: TTyAxis;
  sx: TTyIntervalScale;
  cats: TTyStringArray;
  i: Integer;
begin
  Result := TTyCartesian2D.Create;
  sx := TTyIntervalScale.Create;
  sx.SetExtent(TyRange(0, 100));
  Result.AddAxis(TTyAxis.Create('x', sx, True));
  ay := TTyAxis.Create('y', TTyOrdinalScale.Create, False);
  { AxisType, not just an ordinal scale: GetBaseAxis branches on the declared
    type rather than the scale class, and Builder.pas sets it from the option.
    A fixture that skips it is a chart the builder cannot produce. }
  ay.AxisType := atCategory;
  SetLength(cats, ACount);
  for i := 0 to ACount - 1 do
    cats[i] := Chr(Ord('a') + i);
  ay.SetCategories(cats);
  ay.OnBand := True;
  Result.AddAxis(ay);
  Result.SetRect(ARect);
end;

{ Categories on BOTH axes -- a heatmap. }
function MakeCategoryBoth(const ARect: TTyRectF;
  ANX, ANY: Integer): TTyCartesian2D;
var
  ax, ay: TTyAxis;
  cats: TTyStringArray;
  i: Integer;
begin
  Result := TTyCartesian2D.Create;
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  ax.AxisType := atCategory;
  SetLength(cats, ANX);
  for i := 0 to ANX - 1 do cats[i] := Chr(Ord('a') + i);
  ax.SetCategories(cats);
  ax.OnBand := True;
  Result.AddAxis(ax);
  ay := TTyAxis.Create('y', TTyOrdinalScale.Create, False);
  ay.AxisType := atCategory;
  SetLength(cats, ANY);
  for i := 0 to ANY - 1 do cats[i] := Chr(Ord('A') + i);
  ay.SetCategories(cats);
  ay.OnBand := True;
  Result.AddAxis(ay);
  Result.SetRect(ARect);
end;

procedure TAdvChartCartesianTest.TestDataToLayoutFollowsTheCategoryAxisToY;
var
  cs: TTyCartesian2D;
  lay: TTyCoordLayout;
  p: TTyPointF;
begin
  { A HORIZONTAL BAR. The cell is one band TALL and runs from the value axis'
    baseline to the datum -- the mirror of the vertical case, and the old code
    read MasterX for the band and MasterY for the baseline by name, so it
    produced a cell of zero width standing on the wrong axis. }
  cs := MakeCategoryOnY(TyRectF(0, 0, 400, 300), 5);
  try
    lay := cs.DataToLayout([50, 2]);
    p := cs.DataToPoint([50, 2]);
    AssertTrue('the cell is valid', TyRectFIsValid(lay.Rect));
    AssertEquals('one band tall', 300 / 5, lay.Rect.Bottom - lay.Rect.Top, Eps);
    AssertEquals('centred on the datum''s band', p.Y,
      (lay.Rect.Top + lay.Rect.Bottom) / 2, Eps);
    AssertTrue('and it has real width', lay.Rect.Right - lay.Rect.Left > 1);
    AssertEquals('reaching from the value baseline to the datum', p.X,
      lay.Rect.Right, Eps);
    AssertEquals('which starts at x=0', 0.0, lay.Rect.Left, Eps);
  finally
    cs.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestDataToLayoutGivesAHeatmapCellBothItsBands;
var
  cs: TTyCartesian2D;
  lay: TTyCoordLayout;
  p: TTyPointF;
begin
  { A HEATMAP CELL is one band by one band. Spec section 2 has cartesian
    implement DataToLayout precisely so heatmap's three upstream branches
    collapse into one path here; with the value axis assumed to be y, the cell
    ran from the first category's centre to the datum's -- growing with the row
    index instead of being one row tall. }
  cs := MakeCategoryBoth(TyRectF(0, 0, 400, 300), 5, 4);
  try
    lay := cs.DataToLayout([2, 2]);
    p := cs.DataToPoint([2, 2]);
    AssertTrue('the cell is valid', TyRectFIsValid(lay.Rect));
    AssertEquals('one x band wide', 400 / 5, lay.Rect.Right - lay.Rect.Left, Eps);
    AssertEquals('one y band tall', 300 / 4, lay.Rect.Bottom - lay.Rect.Top, Eps);
    AssertEquals('centred on the anchor in x', p.X,
      (lay.Rect.Left + lay.Rect.Right) / 2, Eps);
    AssertEquals('and in y', p.Y, (lay.Rect.Top + lay.Rect.Bottom) / 2, Eps);
  finally
    cs.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartCartesianTest);
end.
