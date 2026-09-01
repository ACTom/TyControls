unit test.advchart.layout;
{$mode objfpc}{$H+}
{ CONTRACT 1 ACCEPTANCE, second half (Tier 0 spec §8 item 6).
  The box solver must take a CONTAINER PROVIDER, not a rect, and the same code
  path must serve both "the container is the control's client area" and "the
  container is another coordinate system's DataToLayout". If those are two paths,
  coordinateSystemUsage:'box' is a rewrite instead of a parameter. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Layout;
type
  TAdvChartLayoutTest = class(TTestCase)
  private
    function MakeCartesian: TTyCartesian2D;
  published
    procedure TestPixelInsets;
    procedure TestPercentInsets;
    procedure TestWidthWinsOverRight;
    procedure TestHeightAndBottomAgree;
    procedure TestCentreKeyword;
    procedure TestOverConstrainedCollapsesNotInverts;
    procedure TestFixedContainerProvider;
    procedure TestCoordCellContainerProvider;
    procedure TestBothProvidersTakeTheSamePath;
  end;
implementation

const
  Eps = 1e-9;

function TAdvChartLayoutTest.MakeCartesian: TTyCartesian2D;
var sx, sy: TTyIntervalScale;
begin
  Result := TTyCartesian2D.Create;
  sx := TTyIntervalScale.Create;
  sx.SetExtent(TyRange(0, 10));
  sy := TTyIntervalScale.Create;
  sy.SetExtent(TyRange(0, 100));
  Result.AddAxis(TTyAxis.Create('x', sx, True));
  Result.AddAxis(TTyAxis.Create('y', sy, False));
  Result.SetRect(TyRectF(0, 0, 400, 300));
  Result.GetAxis(0).BandWidth := 40;
  { Non-zero on purpose: with a zero divider Rect and ContentRect coincide, and
    nothing would pin down WHICH of the two the container hands over. }
  Result.DividerWidth := 6;
end;

procedure TAdvChartLayoutTest.TestPixelInsets;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxPx(10);
  b.Top := TyBoxPx(20);
  b.Right := TyBoxPx(30);
  b.Bottom := TyBoxPx(40);
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('left', 10.0, r.Left, Eps);
  AssertEquals('top', 20.0, r.Top, Eps);
  AssertEquals('right', 170.0, r.Right, Eps);
  AssertEquals('bottom', 60.0, r.Bottom, Eps);
end;

procedure TAdvChartLayoutTest.TestPercentInsets;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxPercent(10);
  b.Right := TyBoxPercent(10);
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('left', 20.0, r.Left, Eps);
  AssertEquals('right', 180.0, r.Right, Eps);
end;

procedure TAdvChartLayoutTest.TestWidthWinsOverRight;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxPx(10);
  b.Width := TyBoxPx(50);
  b.Right := TyBoxPx(999);
  { Left+Width is fully determined; Right is redundant and must be ignored
    rather than fought over. ECharts resolves the same way. }
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('left', 10.0, r.Left, Eps);
  AssertEquals('right', 60.0, r.Right, Eps);
end;

procedure TAdvChartLayoutTest.TestHeightAndBottomAgree;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Bottom := TyBoxPx(10);
  b.Height := TyBoxPx(40);
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('bottom', 90.0, r.Bottom, Eps);
  AssertEquals('top', 50.0, r.Top, Eps);
end;

procedure TAdvChartLayoutTest.TestCentreKeyword;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxCentre;
  b.Width := TyBoxPx(50);
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('centred left', 75.0, r.Left, Eps);
  AssertEquals('centred right', 125.0, r.Right, Eps);
end;

procedure TAdvChartLayoutTest.TestOverConstrainedCollapsesNotInverts;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxPx(150);
  b.Right := TyBoxPx(150);
  { 150+150 > 200. A negative-width rect would let a later Min/Max silently swap
    the edges; collapse to zero width at the left instead, which stays a VALID
    rect and draws nothing. }
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertTrue('still a valid rect', TyRectFIsValid(r));
  AssertEquals('collapsed to zero width', 0.0, TyRectFWidth(r), Eps);
end;

procedure TAdvChartLayoutTest.TestFixedContainerProvider;
var c: ITyBoxContainer;
begin
  c := TyFixedContainer(TyRectF(5, 6, 105, 106));
  AssertEquals('left', 5.0, c.ContainerRect.Left, Eps);
  AssertEquals('width', 100.0, TyRectFWidth(c.ContainerRect), Eps);
end;

procedure TAdvChartLayoutTest.TestCoordCellContainerProvider;
var cs: TTyCartesian2D; c: ITyBoxContainer; cell: TTyRectF;
begin
  cs := MakeCartesian;
  try
    { The container is one datum's cell in another coordinate system — this is
      coordinateSystemUsage:'box' in its smallest form. }
    c := TyCoordCellContainer(cs, [5, 100]);
    cell := c.ContainerRect;
    AssertTrue('the cell is a valid rect', TyRectFIsValid(cell));
    { The CONTENT rect, not the raw cell: a nested thing must not paint over the
      host's divider. Band 40 minus a 6 px divider = 34. }
    AssertEquals('band minus the divider', 34.0, TyRectFWidth(cell), 1e-6);
    AssertEquals('and it is inset, not shifted',
                 TyRectFWidth(cs.DataToLayout([5, 100]).Rect) - 6,
                 TyRectFWidth(cell), 1e-6);
  finally
    c := nil;
    cs.Free;
  end;
end;

procedure TAdvChartLayoutTest.TestBothProvidersTakeTheSamePath;
var
  cs: TTyCartesian2D;
  b: TTyBoxSpec;
  viaCell, viaFixed, cell: TTyRectF;
begin
  cs := MakeCartesian;
  try
    b := TyBoxSpec;
    b.Left := TyBoxPercent(10);
    b.Right := TyBoxPercent(10);
    b.Top := TyBoxPx(2);
    b.Bottom := TyBoxPx(2);

    cell := TyCoordCellContainer(cs, [5, 100]).ContainerRect;
    viaCell := TySolveBox(b, TyCoordCellContainer(cs, [5, 100]));
    viaFixed := TySolveBox(b, TyFixedContainer(cell));

    { THE ACCEPTANCE ASSERTION. Solving into a coordinate cell and solving into
      the identical rect handed over as a literal must produce the same answer —
      that is what "one code path" means, and it is the whole of contract 1's
      second half. }
    AssertEquals('left', viaFixed.Left, viaCell.Left, Eps);
    AssertEquals('top', viaFixed.Top, viaCell.Top, Eps);
    AssertEquals('right', viaFixed.Right, viaCell.Right, Eps);
    AssertEquals('bottom', viaFixed.Bottom, viaCell.Bottom, Eps);
  finally
    cs.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartLayoutTest);
end.
