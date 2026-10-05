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
    procedure TestTheFourCornerFormsAreNotTruncations;
    procedure TestOversizeCornersShrinkInProportionPerEdge;
    procedure TestEachCornerIsCutByItsOwnRadius;
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
    { ---- the mirror ---- }
    procedure TestAMirrorTurnsOneAxisAndLeavesTheOriginalAlone;
    { ---- the path a sector traces ---- }
    procedure TestASectorsCornerRulesAreNotTheRects;
    procedure TestAPlainSectorTracesRimLineHoleClose;
    procedure TestRoundedCornersAddArcsAndPullTheStartOffTheRim;
    procedure TestACornerCannotExceedHalfTheRingsThickness;
    procedure TestANarrowWedgeLimitsItsCornersFurther;
    procedure TestAWideWedgeIsNotLimitedByItsEdges;
    procedure TestACornersArcSitsTangentInsideItsOwnRing;
    procedure TestTheInnerCornersAreNotTheOuterOnes;
    procedure TestAWholeRingHasNoCornersToRound;
    procedure TestASectorWithNoRadiusAtAllTracesNothing;
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
  { The CONSTRUCTOR clamps now, and the renderer traces what the record says.
    Either way the point stands: a hit test answering about corners the painter
    never drew is a pointer that lies. }
  s := TyShapeRoundRect(TyRectF(0, 0, 100, 40), 999);
  AssertTrue('the middle of a stadium', TyShapeContains(s, 50, 20, 0));
  AssertFalse('and its corner is still cut', TyShapeContains(s, 0, 0, 0));
end;

procedure TAdvChartShapeTest.TestTheFourCornerFormsAreNotTruncations;
var r: TTyCornerRadii;
begin
  { roundRect.ts:30-55. The short forms mean something OTHER than `the rest
    are zero`, which is the reading a careful person arrives at and it rounds
    the wrong corners. Order here is clockwise from the top-left. }
  r := TyCornerRadii([5]);
  AssertEquals('one value is every corner', 5.0, r[0], 1e-12);
  AssertEquals('', 5.0, r[3], 1e-12);

  r := TyCornerRadii([1, 2]);
  AssertEquals('two are the DIAGONALS: top-left', 1.0, r[0], 1e-12);
  AssertEquals('top-right', 2.0, r[1], 1e-12);
  AssertEquals('bottom-right takes the first again', 1.0, r[2], 1e-12);
  AssertEquals('bottom-left the second', 2.0, r[3], 1e-12);

  r := TyCornerRadii([1, 2, 3]);
  AssertEquals('three: top-left', 1.0, r[0], 1e-12);
  AssertEquals('top-right', 2.0, r[1], 1e-12);
  AssertEquals('bottom-right', 3.0, r[2], 1e-12);
  AssertEquals('and bottom-left SHARES the middle one', 2.0, r[3], 1e-12);

  r := TyCornerRadii([1, 2, 3, 4]);
  AssertEquals('four are themselves', 4.0, r[3], 1e-12);
  r := TyCornerRadii([]);
  AssertFalse('and none is a plain rect', TyHasCorner(r));
  r := TyCornerRadii([-3]);
  AssertEquals('a negative radius is no radius', 0.0, r[0], 1e-12);
end;

procedure TAdvChartShapeTest.TestOversizeCornersShrinkInProportionPerEdge;
var s: TTyChartShape;
begin
  { roundRect.ts:57-76 shrinks each PAIR that shares an edge, in proportion.
    Clamping each radius on its own to half the shorter side is the obvious
    version and gives a different shape: on a box 40 wide, corners of 30 and 10
    keep their 3:1 ratio and come out 30 and 10, not 20 and 10. }
  s := TyShapeRoundRect(TyRectF(0, 0, 40, 200), [30, 10, 0, 0]);
  AssertEquals('the big one keeps its share of the top edge', 30.0,
    s.Radii[0], 1e-9);
  AssertEquals('and the small one keeps its own', 10.0, s.Radii[1], 1e-9);

  s := TyShapeRoundRect(TyRectF(0, 0, 40, 200), [60, 20, 0, 0]);
  AssertEquals('over the edge, both shrink by the same factor', 30.0,
    s.Radii[0], 1e-9);
  AssertEquals('', 10.0, s.Radii[1], 1e-9);

  { AND EACH PAIR IS FITTED TO THE EDGE IT SHARES, which needs a box whose two
    sides differ to say at all: the top-right and bottom-right corners share
    the RIGHT edge, so they are fitted to the height. On a box 200 by 40 they
    fit the width easily and overflow the height, and a version that measured
    them against the width would leave them alone. }
  s := TyShapeRoundRect(TyRectF(0, 0, 200, 40), [0, 30, 30, 0]);
  AssertEquals('the right-hand pair is fitted to the HEIGHT', 20.0,
    s.Radii[1], 1e-9);
  AssertEquals('both of them', 20.0, s.Radii[2], 1e-9);
end;

procedure TAdvChartShapeTest.TestEachCornerIsCutByItsOwnRadius;
var s: TTyChartShape;
begin
  { A bar rounded only where it leaves the axis -- borderRadius: [8, 8, 0, 0]
    -- is the commonest form of this option there is, and it is the one a
    single-radius hit test gets wrong at BOTH ends: it would cut the square
    bottom corners and keep the rounded top ones. }
  s := TyShapeRoundRect(TyRectF(0, 0, 100, 100), [20, 20, 0, 0]);
  AssertFalse('the rounded top-left corner is cut',
    TyShapeContains(s, 1, 1, 0));
  AssertFalse('so is the top-right', TyShapeContains(s, 99, 1, 0));
  AssertTrue('but the square bottom-left is not',
    TyShapeContains(s, 0, 100, 0));
  AssertTrue('nor the bottom-right', TyShapeContains(s, 100, 100, 0));

  { FOUR DIFFERENT RADII, because with any two the same a corner tested
    against its NEIGHBOUR'S radius still answers correctly. Each probe below
    sits where only its own corner's number decides the answer: 8 px in from
    the top-left is outside a 40 px cut and inside a 20 px one, and 8 px in
    from the top-right is the other way round. }
  s := TyShapeRoundRect(TyRectF(0, 0, 200, 200), [40, 20, 10, 30]);
  AssertFalse('40 px cuts the top-left back this far',
    TyShapeContains(s, 8, 8, 0));
  AssertTrue('but 20 px does not cut the top-right that far',
    TyShapeContains(s, 192, 8, 0));
  AssertTrue('10 px barely cuts the bottom-right',
    TyShapeContains(s, 194, 194, 0));
  AssertFalse('and 30 px cuts the bottom-left well in',
    TyShapeContains(s, 5, 195, 0));

  { A SQUARE CORNER TAKES THE SLOP TOO. With slop the target reaches outside
    the shape, and a corner test that fired on a radius of zero would measure
    the distance to the corner point instead -- rejecting the diagonal reach
    that every other part of the edge is granted. }
  AssertTrue('slop reaches diagonally past a square corner',
    TyShapeContains(s, -3, 103, 4));

  { AND A RIGHT-TO-LEFT RECT IS THE SAME RECT. Corner 0 has to be its
    top-left whichever way round the caller built it, or a bar drawn from its
    value back to the axis comes out rounded at the wrong end. }
  s := TyShapeRoundRect(TyRectF(100, 100, 0, 0), [20, 20, 0, 0]);
  AssertEquals('normalised', 0.0, s.Bounds.Left, 1e-12);
  AssertEquals('', 100.0, s.Bounds.Bottom, 1e-12);
  AssertFalse('and the top-left is still the rounded one',
    TyShapeContains(s, 1, 1, 0));
  AssertTrue('with the foot still square', TyShapeContains(s, 0, 100, 0));
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

procedure TAdvChartShapeTest.TestAMirrorTurnsOneAxisAndLeavesTheOriginalAlone;
var
  before, after_: TTyChartShape;
begin
  { AN ASYMMETRIC POINT SET, and that is the whole fixture. Most symbols are
    symmetric about their vertical axis, so a mirror that turned BOTH axes over
    would draw the identical picture on one of them -- and a test built on a
    triangle would never know. }
  before := TyShapePolygon([TyPointF(10, 10), TyPointF(40, 20),
                            TyPointF(20, 50)]);

  after_ := TyMirrorShape(before, 25, 30, False, True);
  AssertEquals('y turns about the line', 50.0, after_.Points[0].Y, 1e-9);
  AssertEquals(40.0, after_.Points[1].Y, 1e-9);
  AssertEquals(10.0, after_.Points[2].Y, 1e-9);
  AssertEquals('and x is left where it was', 10.0, after_.Points[0].X, 1e-9);
  AssertEquals(40.0, after_.Points[1].X, 1e-9);

  { THE ORIGINAL IS NOT TOUCHED. A dynamic array is assigned by reference, so
    without a copy the mirror turns the shape the caller is still holding over
    as well -- and a caller that overwrites its own variable, which is what the
    one caller does, cannot see it happen. }
  AssertEquals('the original kept its first point', 10.0,
    before.Points[0].Y, 1e-9);
  AssertEquals(20.0, before.Points[1].Y, 1e-9);
  AssertEquals(50.0, before.Points[2].Y, 1e-9);

  after_ := TyMirrorShape(before, 25, 30, True, False);
  AssertEquals('x turns instead', 40.0, after_.Points[0].X, 1e-9);
  AssertEquals(10.0, after_.Points[1].X, 1e-9);
  AssertEquals('and y is left alone', 10.0, after_.Points[0].Y, 1e-9);

  { NEITHER AXIS IS A NO-OP RATHER THAN A COPY OF NOTHING. }
  after_ := TyMirrorShape(before, 25, 30, False, False);
  AssertEquals(10.0, after_.Points[0].X, 1e-9);
  AssertEquals(10.0, after_.Points[0].Y, 1e-9);

  { A CIRCLE IS ITS OWN MIRROR IMAGE, so it comes back unchanged -- which is
    the right answer and not a skipped case. }
  after_ := TyMirrorShape(TyShapeCircle(10, 20, 5), 0, 0, True, True);
  AssertEquals(10.0, after_.CX, 1e-9);
  AssertEquals(20.0, after_.CY, 1e-9);
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

{ ======================= the path a sector traces ======================= }

function OpsOf(const AShape: TTyChartShape; AKind: TTyPathOpKind): Integer;
var
  ops: TTyPathOpArray;
  i: Integer;
begin
  Result := 0;
  ops := TySectorPath(AShape);
  for i := 0 to High(ops) do
    if ops[i].Kind = AKind then Inc(Result);
end;

procedure TAdvChartShapeTest.TestASectorsCornerRulesAreNotTheRects;
var
  r: TTyCornerRadii;
begin
  { TWO RULES THAT LOOK LIKE ONE. zrender reads a rect's corner array and a
    sector's by DIFFERENT rules, and the short forms are where they part: a
    one-element array rounds all four corners of a rect and only the INNER
    pair of a sector. Read a sector with the rect's rule and a plain doughnut
    comes out rounded at the hole and square at the rim -- not a subtle
    difference, and exactly backwards from what the option asked for. }
  r := TySectorRadii([5]);
  AssertEquals('inner start', 5.0, r[0], 1e-12);
  AssertEquals('inner end', 5.0, r[1], 1e-12);
  AssertEquals('and the rim is left alone', 0.0, r[2], 1e-12);
  AssertEquals('', 0.0, r[3], 1e-12);
  AssertEquals('while a RECT rounds everything from one value', 5.0,
    TyCornerRadii([5])[2], 1e-12);

  { Two values are the inner pair then the outer pair -- not the diagonals. }
  r := TySectorRadii([1, 2]);
  AssertEquals('inner pair', 1.0, r[0], 1e-12);
  AssertEquals('', 1.0, r[1], 1e-12);
  AssertEquals('outer pair', 2.0, r[2], 1e-12);
  AssertEquals('', 2.0, r[3], 1e-12);
  AssertEquals('where a RECT gives the second value to the top-right',
    2.0, TyCornerRadii([1, 2])[1], 1e-12);

  r := TySectorRadii([1, 2, 3]);
  AssertEquals('three: the last covers both outer corners', 3.0, r[2], 1e-12);
  AssertEquals('', 3.0, r[3], 1e-12);
  AssertEquals('and the middle one is the inner END', 2.0, r[1], 1e-12);
end;

procedure TAdvChartShapeTest.TestAPlainSectorTracesRimLineHoleClose;
var
  s: TTyChartShape;
  ops: TTyPathOpArray;
begin
  { One contour: out to the rim, round it, in to the hole, back round it. That
    is what makes a ring fill under either rule and describe the same area the
    hit test's annulus does. }
  s := TyShapeSector(100, 100, 30, 80, 0, Pi / 2);
  ops := TySectorPath(s);
  AssertEquals('five ops', 5, Length(ops));
  AssertEquals(Ord(pokMoveTo), Ord(ops[0].Kind));
  AssertEquals('starting on the rim at the start angle', 180.0, ops[0].X, 1e-9);
  AssertEquals('', 100.0, ops[0].Y, 1e-9);
  AssertEquals(Ord(pokArc), Ord(ops[1].Kind));
  AssertEquals('the rim', 80.0, ops[1].R, 1e-9);
  AssertFalse('drawn forward', ops[1].Anti);
  AssertEquals(Ord(pokLineTo), Ord(ops[2].Kind));
  AssertEquals(Ord(pokArc), Ord(ops[3].Kind));
  AssertEquals('the hole', 30.0, ops[3].R, 1e-9);
  AssertTrue('drawn back', ops[3].Anti);
  AssertEquals(Ord(pokClose), Ord(ops[4].Kind));

  { A SOLID WEDGE closes through the centre rather than round a hole. }
  s := TyShapeSector(100, 100, 0, 80, 0, Pi / 2);
  ops := TySectorPath(s);
  AssertEquals('four ops', 4, Length(ops));
  AssertEquals(Ord(pokLineTo), Ord(ops[2].Kind));
  AssertEquals('to the centre', 100.0, ops[2].X, 1e-9);
  AssertEquals('', 100.0, ops[2].Y, 1e-9);
end;

procedure TAdvChartShapeTest.TestRoundedCornersAddArcsAndPullTheStartOffTheRim;
var
  plain, round_: TTyChartShape;
  ops: TTyPathOpArray;
begin
  plain := TyShapeSector(100, 100, 30, 80, 0, Pi / 2);
  round_ := TyShapeSector(100, 100, 30, 80, 0, Pi / 2, [6, 6, 6, 6]);
  ops := TySectorPath(round_);

  { Four corner arcs on top of the two ring arcs, so the path GROWS rather
    than merely changing shape -- which is what says the corners were cut and
    not just asked for. }
  AssertEquals('two ring arcs when plain', 2, OpsOf(plain, pokArc));
  AssertEquals('six with every corner rounded', 6, OpsOf(round_, pokArc));

  { AND THE PATH NO LONGER STARTS ON THE RIM. The first point is pulled back
    along the radial edge by the corner's radius; a version that computed the
    corners and then started from the sharp point anyway would draw a spike. }
  AssertTrue('the start is off the rim: ' + FloatToStr(ops[0].X),
    Abs(ops[0].X - 180.0) > 1);

  { A corner of nothing changes nothing. }
  AssertEquals('zero radii trace the plain path', 2,
    OpsOf(TyShapeSector(100, 100, 30, 80, 0, Pi / 2, [0, 0, 0, 0]), pokArc));
end;

procedure TAdvChartShapeTest.TestACornerCannotExceedHalfTheRingsThickness;
var
  ops: TTyPathOpArray;
  i: Integer;
  biggest: Double;
begin
  { roundSector.ts:209. Without it two corners on the same radial edge meet in
    the middle and the wedge turns inside out. The ring here is 20 px thick,
    so no corner may exceed 10 however large the option is. }
  ops := TySectorPath(
    TyShapeSector(100, 100, 60, 80, 0, Pi, [999, 999, 999, 999]));
  biggest := 0;
  for i := 0 to High(ops) do
    if (ops[i].Kind = pokArc) and (ops[i].R < 50) and (ops[i].R > biggest) then
      biggest := ops[i].R;
  AssertTrue('no corner is larger than half the thickness: '
    + FloatToStr(biggest), biggest <= 10 + 1e-9);
  AssertTrue('and one really was drawn', biggest > 1);
end;

procedure TAdvChartShapeTest.TestANarrowWedgeLimitsItsCornersFurther;
var
  wide, narrow: TTyPathOpArray;

  function Smallest(const AOps: TTyPathOpArray): Double;
  var i: Integer;
  begin
    Result := 1e30;
    for i := 0 to High(AOps) do
      if (AOps[i].Kind = pokArc) and (AOps[i].R < 50)
        and (AOps[i].R < Result) then
        Result := AOps[i].R;
  end;

begin
  { HALF THE THICKNESS IS NOT THE ONLY LIMIT. Under half a turn the two radial
    edges converge, so a corner that fits the ring can still be too big to fit
    between them -- and a thin slice of a pie is the ordinary case, not a
    contrived one. Both wedges below have the same ring; only the angle
    differs, and only the narrow one is cut back. }
  wide := TySectorPath(
    TyShapeSector(100, 100, 20, 80, 0, Pi / 2, [20, 20, 20, 20]));
  narrow := TySectorPath(
    TyShapeSector(100, 100, 20, 80, 0, Pi / 40, [20, 20, 20, 20]));
  AssertTrue('the wide one keeps its corners: ' + FloatToStr(Smallest(wide)),
    Smallest(wide) > 15);

  { AND CUT BACK BY EXACTLY THIS MUCH. `less than it was` is satisfied by
    any formula that shrinks something, which is how a version using the
    INNER ring's divisor on the outer one stayed green: it answers 3.269
    where upstream answers 3.022, and both are less than 20.

    The number: the two radial edges meet at the centre, so b is 0 and the
    half-angle between them is Pi/80. a = 1/sin(Pi/80) = 25.4713, and the
    outer limit is radius/(a + 1) = 80/26.4713. The INNER one divides by
    (a - 1) instead -- they are different formulas, not one with a sign.

    Both corners merged, so the path is MoveTo, one outer arc, LineTo, one
    inner arc, Close -- and the two radii sit at 1 and 3 where a test can name
    them apart instead of taking whichever happened to be smaller. }
  AssertEquals('five ops when both corners merge', 5, Length(narrow));
  AssertEquals('the outer corner is limited to radius/(a+1)', 3.022137,
    narrow[1].R, 1e-5);
  AssertEquals('and the inner one by innerRadius/(a-1)', 0.817283,
    narrow[3].R, 1e-5);
end;

procedure TAdvChartShapeTest.TestAWideWedgeIsNotLimitedByItsEdges;
var
  ops: TTyPathOpArray;
  i: Integer;
  biggest: Double;
begin
  { THE EDGE LIMIT IS GATED ON arc < Pi, and the gate is load-bearing. Past
    half a turn the radial edges no longer close in front of the wedge, and
    applying the formula anyway cuts corners that had room: this wedge is
    three quarters of a turn with a 40 px half-thickness, so 35 fits -- while
    the ungated formula would trim it to 33.14. }
  ops := TySectorPath(
    TyShapeSector(100, 100, 0, 80, 0, 3 * Pi / 2, [35, 35, 35, 35]));
  biggest := 0;
  for i := 0 to High(ops) do
    if (ops[i].Kind = pokArc) and (ops[i].R < 50) and (ops[i].R > biggest) then
      biggest := ops[i].R;
  AssertEquals('the corner keeps the size it asked for', 35.0, biggest, 1e-6);
end;

procedure TAdvChartShapeTest.TestACornersArcSitsTangentInsideItsOwnRing;
var
  ops: TTyPathOpArray;
  i: Integer;
  d, found, ang: Double;
begin
  { WHERE THE CORNER IS, not how big it is. Four mutants that MOVE a corner
    -- picking the farther of the two tangent circles, dropping the sign of
    the perpendicular offset, swapping inner for outer -- all draw arcs of
    the right radius in the right number, and every test that counted them
    stayed green.

    The property that pins it: a corner of radius cr is tangent to the
    INSIDE of the rim, so its centre is exactly (radius - cr) from the
    sector's own centre. Anywhere else and the corner is not on the rim. }
  ops := TySectorPath(
    TyShapeSector(100, 100, 30, 80, 0, Pi / 2, [0, 0, 10, 10]));
  found := -1;
  for i := 0 to High(ops) do
    if (ops[i].Kind = pokArc) and (Abs(ops[i].R - 10) < 1e-6) then
    begin
      d := Sqrt(Sqr(ops[i].X - 100) + Sqr(ops[i].Y - 100));
      AssertEquals('an outer corner is tangent inside the rim', 70.0, d, 1e-6);
      { AND ON THE RIGHT SIDE OF THE RING. Distance alone cannot say: the
        solve finds TWO circles tangent to both edges and both are exactly
        this far out. They differ in where they sit AROUND the ring -- the
        one to keep is just inside the sweep, its twin is most of a turn
        away at 2.998 rad. Taking the wrong one draws the corner on the far
        side of the pie. }
      ang := ArcTan2(ops[i].Y - 100, ops[i].X - 100);
      AssertTrue('and inside the sweep, not across the chart: '
        + FloatToStr(ang), (ang >= -1e-9) and (ang <= Pi / 2 + 1e-9));
      found := d;
    end;
  AssertTrue('and there were some', found > 0);

  { The inner corners bulge the OTHER way -- into the hole -- so their
    centres sit at (innerRadius + cr) instead. Same test, opposite sign, and
    it is the sign a transcription is most likely to lose. }
  ops := TySectorPath(
    TyShapeSector(100, 100, 30, 80, 0, Pi / 2, [10, 10, 0, 0]));
  found := -1;
  for i := 0 to High(ops) do
    if (ops[i].Kind = pokArc) and (Abs(ops[i].R - 10) < 1e-6) then
    begin
      d := Sqrt(Sqr(ops[i].X - 100) + Sqr(ops[i].Y - 100));
      AssertEquals('an inner corner is tangent outside the hole', 40.0,
        d, 1e-6);
      ang := ArcTan2(ops[i].Y - 100, ops[i].X - 100);
      AssertTrue('inside the sweep too: ' + FloatToStr(ang),
        (ang >= -1e-9) and (ang <= Pi / 2 + 1e-9));
      found := d;
    end;
  AssertTrue('and there were some', found > 0);

  { THE HOLE IS TRACED BACKWARDS, always. One contour means the inner arc
    runs against the outer one, and a corner-rounded hole is the branch
    where that is easiest to lose -- it is written out there rather than
    falling out of the plain path. }
  found := -1;
  for i := 0 to High(ops) do
    if (ops[i].Kind = pokArc) and (Abs(ops[i].R - 30) < 1e-6) then
    begin
      AssertTrue('the rounded hole still runs back', ops[i].Anti);
      found := 1;
    end;
  AssertTrue('and the hole was traced at all', found > 0);
end;

procedure TAdvChartShapeTest.TestTheInnerCornersAreNotTheOuterOnes;
var
  outerOnly, innerOnly: TTyPathOpArray;
begin
  { THE ORDER IS INNER FIRST, and nothing symmetric can say so. Every corner
    test until now handed the same number to all four, so reading the array
    outer-first drew exactly the same picture.

    Told apart by WHERE THE PATH STARTS: the first point is pulled back off
    the rim only when the OUTER start corner is rounded. Round only the
    inner pair and the path still begins on the rim at 180. }
  outerOnly := TySectorPath(
    TyShapeSector(100, 100, 30, 80, 0, Pi / 2, [0, 0, 10, 10]));
  innerOnly := TySectorPath(
    TyShapeSector(100, 100, 30, 80, 0, Pi / 2, [10, 10, 0, 0]));
  AssertTrue('an outer corner moves the start off the rim: '
    + FloatToStr(outerOnly[0].X), Abs(outerOnly[0].X - 180) > 1);
  AssertEquals('an inner one leaves it there', 180.0, innerOnly[0].X, 1e-9);
  AssertEquals('', 100.0, innerOnly[0].Y, 1e-9);
end;

procedure TAdvChartShapeTest.TestAWholeRingHasNoCornersToRound;
begin
  { It has no radial edges, so there is nothing for a corner to sit between.
    Upstream leaves the cornerRadius unread on this branch and so does this. }
  AssertEquals('two arcs, corners or not', 2,
    OpsOf(TyShapeSector(100, 100, 30, 80, 0, 2 * Pi, [20, 20, 20, 20]), pokArc));
end;

procedure TAdvChartShapeTest.TestASectorWithNoRadiusAtAllTracesNothing;
var s: TTyChartShape;
begin
  s := TyShapeSector(100, 100, 0, 0, 0, Pi / 2);
  AssertEquals('nothing to trace', 0, Length(TySectorPath(s)));

  { A HOLE WITH NO RIM IS A DISC, not nothing: upstream promotes the inner
    radius to the outer one rather than drawing an empty path. }
  s := TyShapeSector(100, 100, 40, 0, 0, Pi / 2);
  AssertTrue('a lone inner radius still draws', Length(TySectorPath(s)) > 0);
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
