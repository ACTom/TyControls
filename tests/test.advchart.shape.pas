unit test.advchart.shape;
{$mode objfpc}{$H+}
{ Shape containment -- the arithmetic the pointer's answer rests on.
  Pure: no painter, no handle, so every assertion is an exact number. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape;
type
  TAdvChartShapeTest = class(TTestCase)
  private
    function Ring: TTyChartShape;
  published
    { ---- rect ---- }
    procedure TestRectIsClosedOnEveryEdge;
    procedure TestRectRejectsOutside;
    procedure TestRectSlopWidensIt;
    { ---- round rect ---- }
    procedure TestRoundRectCutsTheCorner;
    procedure TestRoundRectKeepsTheMiddleOfEachEdge;
    procedure TestRoundRectClampsAnOversizeRadiusLikeTheRenderer;
    { ---- circle / ellipse ---- }
    procedure TestCircleBoundaryIsInside;
    procedure TestCircleRejectsJustOutside;
    procedure TestEllipseIsNotACircle;
    { ---- sector ---- }
    procedure TestSectorAcceptsInsideTheBand;
    procedure TestSectorRejectsTheDonutHole;
    procedure TestSectorRejectsBeyondTheOuterRadius;
    procedure TestSectorRejectsOutsideTheSweep;
    procedure TestSectorWrappingTheSeam;
    procedure TestFullTurnSectorAcceptsEveryAngle;
    procedure TestNegativeSweepIsNormalised;
    { ---- polyline ---- }
    procedure TestPolylineAcceptsNearTheStroke;
    procedure TestPolylineRejectsFarFromIt;
    procedure TestPolylineClampsToTheSegmentNotTheInfiniteLine;
    procedure TestPolylineNaNVertexBreaksTheRun;
    procedure TestSinglePointPolyline;
    { ---- polygon ---- }
    procedure TestPolygonAcceptsInside;
    procedure TestPolygonRejectsOutside;
    procedure TestPolygonSliverIsStillHittableThroughItsOutline;
    { ---- path ---- }
    procedure TestPathFallsBackToItsBounds;
    { ---- bounds and helpers ---- }
    procedure TestBoundsOfACircleIsItsSquare;
    procedure TestBoundsOfAPolylineSkipsNaN;
    procedure TestDegenerateSegmentIsAPointNotADivide;
    procedure TestNaNProbeNeverHits;
    procedure TestSnapShapeAlignsARectsEdges;
    procedure TestSnapShapeLeavesACircleAlone;
    procedure TestSnapShapeIgnoresAMultiPointPolyline;
  end;
implementation

const
  Eps = 1e-9;

function TAdvChartShapeTest.Ring: TTyChartShape;
begin
  { A donut band: inner 20, outer 40, the top-right quadrant. }
  Result := TyShapeSector(0, 0, 20, 40, 0, Pi / 2);
end;

{ ============================ rect ============================ }

procedure TAdvChartShapeTest.TestRectIsClosedOnEveryEdge;
var s: TTyChartShape;
begin
  s := TyShapeRect(TyRectF(0, 0, 10, 10));
  { CLOSED here, unlike TyRectFContains which is half-open. That rule exists for
    the cell question, where nothing else breaks a tie between abutting bands;
    in a paint list z order breaks it, so closed is both simpler and right. }
  AssertTrue('left edge', TyShapeContains(s, 0, 5, 0));
  AssertTrue('right edge', TyShapeContains(s, 10, 5, 0));
  AssertTrue('top edge', TyShapeContains(s, 5, 0, 0));
  AssertTrue('bottom edge', TyShapeContains(s, 5, 10, 0));
end;

procedure TAdvChartShapeTest.TestRectRejectsOutside;
var s: TTyChartShape;
begin
  s := TyShapeRect(TyRectF(0, 0, 10, 10));
  AssertFalse('just past the right', TyShapeContains(s, 10.001, 5, 0));
  AssertFalse('well away', TyShapeContains(s, 50, 50, 0));
end;

procedure TAdvChartShapeTest.TestRectSlopWidensIt;
var s: TTyChartShape;
begin
  s := TyShapeRect(TyRectF(0, 0, 10, 10));
  AssertTrue('within slop', TyShapeContains(s, 13, 5, 4));
  AssertFalse('past slop', TyShapeContains(s, 15, 5, 4));
end;

{ ============================ round rect ============================ }

procedure TAdvChartShapeTest.TestRoundRectCutsTheCorner;
var s: TTyChartShape;
begin
  s := TyShapeRoundRect(TyRectF(0, 0, 100, 100), 20);
  { (1,1) is inside the bounding box but outside the corner arc: the arc centre
    is (20,20) with radius 20, and (1,1) is about 26.9 away. }
  AssertFalse('the corner is cut off', TyShapeContains(s, 1, 1, 0));
end;

procedure TAdvChartShapeTest.TestRoundRectKeepsTheMiddleOfEachEdge;
var s: TTyChartShape;
begin
  s := TyShapeRoundRect(TyRectF(0, 0, 100, 100), 20);
  AssertTrue('top edge middle', TyShapeContains(s, 50, 0, 0));
  AssertTrue('left edge middle', TyShapeContains(s, 0, 50, 0));
  AssertTrue('the interior', TyShapeContains(s, 50, 50, 0));
end;

procedure TAdvChartShapeTest.TestRoundRectClampsAnOversizeRadiusLikeTheRenderer;
var s: TTyChartShape;
begin
  { The renderer clamps an oversize radius to half the box (BGRA does it inside
    roundRect). If the hit test did not clamp the same way, the pointer would be
    answering about a shape nothing ever drew. }
  s := TyShapeRoundRect(TyRectF(0, 0, 100, 40), 999);
  AssertTrue('the middle of a stadium', TyShapeContains(s, 50, 20, 0));
  AssertFalse('and its corner is still cut', TyShapeContains(s, 0, 0, 0));
end;

{ ============================ circle / ellipse ============================ }

procedure TAdvChartShapeTest.TestCircleBoundaryIsInside;
var s: TTyChartShape;
begin
  s := TyShapeCircle(0, 0, 10);
  AssertTrue('exactly on the rim', TyShapeContains(s, 10, 0, 0));
  AssertTrue('the centre', TyShapeContains(s, 0, 0, 0));
end;

procedure TAdvChartShapeTest.TestCircleRejectsJustOutside;
var s: TTyChartShape;
begin
  s := TyShapeCircle(0, 0, 10);
  AssertFalse('just outside the rim', TyShapeContains(s, 10.001, 0, 0));
  AssertTrue('but inside with slop', TyShapeContains(s, 12, 0, 3));
end;

procedure TAdvChartShapeTest.TestEllipseIsNotACircle;
var s: TTyChartShape;
begin
  s := TyShapeEllipse(0, 0, 40, 10);
  AssertTrue('far along the wide axis', TyShapeContains(s, 39, 0, 0));
  AssertFalse('the same distance up the narrow one', TyShapeContains(s, 0, 39, 0));
end;

{ ============================ sector ============================ }

procedure TAdvChartShapeTest.TestSectorAcceptsInsideTheBand;
begin
  { Radius 30, angle 45 degrees -- squarely in the band and in the sweep. }
  AssertTrue('in the band', TyShapeContains(Ring, 30 * Cos(Pi / 4), 30 * Sin(Pi / 4), 0));
end;

procedure TAdvChartShapeTest.TestSectorRejectsTheDonutHole;
begin
  { A donut's hole is not the donut. Getting this wrong makes the whole middle
    of a ring chart report the slice behind the pointer. }
  AssertFalse('the hole', TyShapeContains(Ring, 5 * Cos(Pi / 4), 5 * Sin(Pi / 4), 0));
  AssertFalse('the exact centre', TyShapeContains(Ring, 0, 0, 0));
end;

procedure TAdvChartShapeTest.TestSectorRejectsBeyondTheOuterRadius;
begin
  AssertFalse('past the rim', TyShapeContains(Ring, 50 * Cos(Pi / 4), 50 * Sin(Pi / 4), 0));
end;

procedure TAdvChartShapeTest.TestSectorRejectsOutsideTheSweep;
begin
  { Right radius, wrong quadrant. }
  AssertFalse('opposite quadrant', TyShapeContains(Ring, -30, -30, 0));
  AssertFalse('just past the end of the sweep',
              TyShapeContains(Ring, 30 * Cos(Pi / 2 + 0.2), 30 * Sin(Pi / 2 + 0.2), 0));
end;

procedure TAdvChartShapeTest.TestSectorWrappingTheSeam;
var s: TTyChartShape;
begin
  { From 315 degrees to 45 -- across the 0/2pi seam, which is where a naive
    "start <= angle <= end" test silently accepts nothing. }
  s := TyShapeSector(0, 0, 0, 40, 7 * Pi / 4, 9 * Pi / 4);
  AssertTrue('just after the seam', TyShapeContains(s, 30, 1, 0));
  AssertTrue('just before it', TyShapeContains(s, 30, -1, 0));
  AssertFalse('the far side', TyShapeContains(s, -30, 0, 0));
end;

procedure TAdvChartShapeTest.TestFullTurnSectorAcceptsEveryAngle;
var s: TTyChartShape;
begin
  { A single-slice pie is a full turn. Normalising the sweep would wrap it to
    zero and make the only slice un-hittable. }
  s := TyShapeSector(0, 0, 0, 40, 0, 2 * Pi);
  AssertTrue('east', TyShapeContains(s, 30, 0, 0));
  AssertTrue('north', TyShapeContains(s, 0, -30, 0));
  AssertTrue('west', TyShapeContains(s, -30, 0, 0));
  AssertTrue('south', TyShapeContains(s, 0, 30, 0));
end;

procedure TAdvChartShapeTest.TestNegativeSweepIsNormalised;
var fwd, back: TTyChartShape;
begin
  fwd := TyShapeSector(0, 0, 0, 40, 0, Pi / 2);
  back := TyShapeSector(0, 0, 0, 40, Pi / 2, 0);
  AssertEquals('the same wedge either way round',
               TyShapeContains(fwd, 30 * Cos(Pi / 4), 30 * Sin(Pi / 4), 0),
               TyShapeContains(back, 30 * Cos(Pi / 4), 30 * Sin(Pi / 4), 0));
  AssertTrue('and it really is the wedge',
             TyShapeContains(back, 30 * Cos(Pi / 4), 30 * Sin(Pi / 4), 0));
end;

{ ============================ polyline ============================ }

procedure TAdvChartShapeTest.TestPolylineAcceptsNearTheStroke;
var s: TTyChartShape;
begin
  s := TyShapePolyline([TyPointF(0, 0), TyPointF(100, 0)]);
  AssertTrue('3 px off a 4 px ribbon', TyShapeContains(s, 50, 3, 4));
  AssertTrue('right on it', TyShapeContains(s, 50, 0, 4));
end;

procedure TAdvChartShapeTest.TestPolylineRejectsFarFromIt;
var s: TTyChartShape;
begin
  s := TyShapePolyline([TyPointF(0, 0), TyPointF(100, 0)]);
  AssertFalse('well off the line', TyShapeContains(s, 50, 20, 4));
end;

procedure TAdvChartShapeTest.TestPolylineClampsToTheSegmentNotTheInfiniteLine;
var s: TTyChartShape;
begin
  s := TyShapePolyline([TyPointF(0, 0), TyPointF(100, 0)]);
  { Measured against the infinite line, (300,0) is at distance 0 and would hit.
    A line series would then claim the whole width of the chart. }
  AssertFalse('far past the end', TyShapeContains(s, 300, 0, 4));
  AssertTrue('just past it, within slop', TyShapeContains(s, 102, 0, 4));
end;

procedure TAdvChartShapeTest.TestPolylineNaNVertexBreaksTheRun;
var s: TTyChartShape;
begin
  { NaN is the no-data sentinel. With connectNulls off, the segments either side
    of a gap do not exist and must not be hittable. }
  s := TyShapePolyline([TyPointF(0, 0), TyPointF(NaN, NaN), TyPointF(100, 0)]);
  AssertFalse('the gap is not a segment', TyShapeContains(s, 50, 0, 4));
  { Nor are the surviving vertices. Both segments have a NaN end, so NOTHING was
    stroked -- and a shape that claims a hit where there is no ink breaks the one
    invariant this layer exists for. The isolated points are hoverable through
    their SYMBOL elements, which are separate shapes in the paint list. }
  AssertFalse('and neither is an isolated vertex', TyShapeContains(s, 0, 0, 4));
end;

procedure TAdvChartShapeTest.TestSinglePointPolyline;
var s: TTyChartShape;
begin
  { Same rule, and this was the inconsistent case until the NaN test above
    forced the question: one vertex strokes nothing, so it hits nothing. A
    single-datum line series is hoverable through its symbol. }
  s := TyShapePolyline([TyPointF(10, 10)]);
  AssertFalse('one vertex strokes nothing', TyShapeContains(s, 10, 10, 4));
  AssertFalse('and certainly not away from it', TyShapeContains(s, 30, 10, 4));
end;

{ ============================ polygon ============================ }

procedure TAdvChartShapeTest.TestPolygonAcceptsInside;
var s: TTyChartShape;
begin
  s := TyShapePolygon([TyPointF(0, 0), TyPointF(100, 0),
                       TyPointF(100, 50), TyPointF(0, 50)]);
  AssertTrue('the middle', TyShapeContains(s, 50, 25, 0));
end;

procedure TAdvChartShapeTest.TestPolygonRejectsOutside;
var s: TTyChartShape;
begin
  s := TyShapePolygon([TyPointF(0, 0), TyPointF(100, 0),
                       TyPointF(100, 50), TyPointF(0, 50)]);
  AssertFalse('above it', TyShapeContains(s, 50, -20, 0));
  AssertFalse('beside it', TyShapeContains(s, 150, 25, 0));
end;

procedure TAdvChartShapeTest.TestPolygonSliverIsStillHittableThroughItsOutline;
var s: TTyChartShape;
begin
  { An area series whose band has collapsed to nearly nothing still has to be
    hoverable, or a flat stretch of data becomes unreachable. }
  s := TyShapePolygon([TyPointF(0, 0), TyPointF(100, 0),
                       TyPointF(100, 0.01), TyPointF(0, 0.01)]);
  AssertTrue('near the sliver', TyShapeContains(s, 50, 2, 4));
end;

{ ============================ path ============================ }

procedure TAdvChartShapeTest.TestPathFallsBackToItsBounds;
var s: TTyChartShape;
begin
  { Documented behaviour, not an accident: resolving SVG path data exactly needs
    a rasteriser this layer has no access to, and for a symbol six to twenty
    pixels across a bounds hit is the better target anyway. }
  s := TyShapePath('M0,0 L10,0 L5,10 Z', TyRectF(0, 0, 20, 20));
  AssertTrue('inside the bounds', TyShapeContains(s, 1, 19, 0));
  AssertFalse('outside them', TyShapeContains(s, 25, 25, 0));
end;

{ ============================ bounds and helpers ============================ }

procedure TAdvChartShapeTest.TestBoundsOfACircleIsItsSquare;
var b: TTyRectF;
begin
  b := TyShapeBounds(TyShapeCircle(50, 60, 10));
  AssertEquals('left', 40.0, b.Left, Eps);
  AssertEquals('top', 50.0, b.Top, Eps);
  AssertEquals('right', 60.0, b.Right, Eps);
  AssertEquals('bottom', 70.0, b.Bottom, Eps);
end;

procedure TAdvChartShapeTest.TestBoundsOfAPolylineSkipsNaN;
var b: TTyRectF;
begin
  b := TyShapeBounds(TyShapePolyline([TyPointF(10, 10), TyPointF(NaN, NaN),
                                      TyPointF(30, 40)]));
  AssertTrue('a valid box', TyRectFIsValid(b));
  AssertEquals('left', 10.0, b.Left, Eps);
  AssertEquals('bottom', 40.0, b.Bottom, Eps);
end;

procedure TAdvChartShapeTest.TestDegenerateSegmentIsAPointNotADivide;
begin
  { Two identical vertices happen whenever consecutive data land on one pixel.
    The projection divides by the segment length, so this must be special-cased
    rather than left to produce an infinity. }
  AssertEquals('distance to a zero-length segment', 5.0,
               TyDistanceToSegment(3, 4, 0, 0, 0, 0), 1e-9);
end;

procedure TAdvChartShapeTest.TestNaNProbeNeverHits;
var s: TTyChartShape;
begin
  { A pointer position can arrive as NaN when a coordinate system fails to
    invert. It must miss everything, not match the first shape whose comparison
    happens to be vacuously true. }
  s := TyShapeRect(TyRectF(0, 0, 10, 10));
  AssertFalse('NaN x', TyShapeContains(s, NaN, 5, 0));
  AssertFalse('NaN y', TyShapeContains(s, 5, NaN, 0));
end;

procedure TAdvChartShapeTest.TestSnapShapeAlignsARectsEdges;
var s: TTyChartShape;
begin
  s := TySnapShape(TyShapeRect(TyRectF(10, 20, 60, 70)), 1);
  AssertEquals('left', 10.5, s.Bounds.Left, Eps);
  AssertEquals('right', 59.5, s.Bounds.Right, Eps);
end;

procedure TAdvChartShapeTest.TestSnapShapeLeavesACircleAlone;
var s: TTyChartShape;
begin
  { A circle has no long straight edge lying along the pixel grid, so snapping
    would distort it for no gain. }
  s := TySnapShape(TyShapeCircle(10.3, 20.7, 5), 1);
  AssertEquals('cx', 10.3, s.CX, Eps);
  AssertEquals('cy', 20.7, s.CY, Eps);
end;

procedure TAdvChartShapeTest.TestSnapShapeIgnoresAMultiPointPolyline;
var s: TTyChartShape;
begin
  { Snapping a vertex in the middle of a DATA line would move a datum -- a far
    worse crime than a soft edge. Only a two-point run (a grid line, an axis
    line) is a candidate. }
  s := TySnapShape(TyShapePolyline([TyPointF(0, 20), TyPointF(50, 20),
                                    TyPointF(100, 20)]), 1);
  AssertEquals('first vertex untouched', 20.0, s.Points[0].Y, Eps);
  AssertEquals('and the middle one', 20.0, s.Points[1].Y, Eps);
end;

initialization
  RegisterTest(TAdvChartShapeTest);
end.
