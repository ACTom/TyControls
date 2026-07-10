unit test.starshape;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry,
  tyControls.Types, tyControls.StarShape;

type
  TTyStarShapeTest = class(TTestCase)
  published
    // Vertex count
    procedure TestVertexCountFivePoints;
    procedure TestVertexCountSevenPoints;
    // Point-count floor / clamping
    procedure TestPointsFloorToThree;
    procedure TestZeroAndNegativePointsClampToThree;
    // Alternating outer / inner radii
    procedure TestAlternatingOuterInnerRadii;
    procedure TestInnerRatioAffectsInnerRadius;
    procedure TestInnerRatioClampsLow;
    procedure TestInnerRatioClampsHigh;
    // Bounds — every vertex within ARect
    procedure TestAllVerticesWithinRect;
    procedure TestOuterVerticesReachEdges;
    // First outer vertex points UP
    procedure TestFirstVertexPointsUp;
    // Symmetry
    procedure TestHorizontalSymmetry;
    procedure TestDegenerateRectDoesNotCrash;
  end;

implementation

const
  EPS = 0.5;   // device-px tolerance for float geometry

{ Distance from the centre of ARect to a vertex. }
function RadiusOf(const ARect: TRect; const P: TPointF): Double;
var
  cx, cy: Double;
begin
  cx := (ARect.Left + ARect.Right) / 2;
  cy := (ARect.Top + ARect.Bottom) / 2;
  Result := Sqrt(Sqr(P.x - cx) + Sqr(P.y - cy));
end;

{ ---- vertex count ---- }

procedure TTyStarShapeTest.TestVertexCountFivePoints;
var poly: array of TPointF;
begin
  poly := TyStarPolygon(Rect(0, 0, 100, 100), 5, 0.42);
  AssertEquals('5-point star has 10 vertices', 10, Length(poly));
end;

procedure TTyStarShapeTest.TestVertexCountSevenPoints;
var poly: array of TPointF;
begin
  poly := TyStarPolygon(Rect(0, 0, 100, 100), 7, 0.42);
  AssertEquals('7-point star has 14 vertices', 14, Length(poly));
end;

{ ---- point-count floor ---- }

procedure TTyStarShapeTest.TestPointsFloorToThree;
var poly: array of TPointF;
begin
  // APoints=2 is below the floor -> clamps to 3 -> 6 vertices.
  poly := TyStarPolygon(Rect(0, 0, 100, 100), 2, 0.42);
  AssertEquals('APoints<3 floors to 3 (6 vertices)', 6, Length(poly));
end;

procedure TTyStarShapeTest.TestZeroAndNegativePointsClampToThree;
var poly: array of TPointF;
begin
  poly := TyStarPolygon(Rect(0, 0, 100, 100), 0, 0.42);
  AssertEquals('0 points floors to 3', 6, Length(poly));
  poly := TyStarPolygon(Rect(0, 0, 100, 100), -5, 0.42);
  AssertEquals('negative points floors to 3', 6, Length(poly));
end;

{ ---- alternating radii ---- }

procedure TTyStarShapeTest.TestAlternatingOuterInnerRadii;
var
  poly: array of TPointF;
  i: Integer;
  rOuter, rInner: Double;
begin
  poly := TyStarPolygon(Rect(0, 0, 100, 100), 5, 0.42);
  // Even indices are outer, odd are inner; every even radius must equal, and
  // exceed, every odd radius.
  rOuter := RadiusOf(Rect(0, 0, 100, 100), poly[0]);
  rInner := RadiusOf(Rect(0, 0, 100, 100), poly[1]);
  AssertTrue('outer radius exceeds inner', rOuter > rInner + EPS);
  for i := 0 to High(poly) do
    if (i mod 2) = 0 then
      AssertTrue(Format('vertex %d is an outer point', [i]),
        Abs(RadiusOf(Rect(0, 0, 100, 100), poly[i]) - rOuter) < EPS)
    else
      AssertTrue(Format('vertex %d is an inner point', [i]),
        Abs(RadiusOf(Rect(0, 0, 100, 100), poly[i]) - rInner) < EPS);
end;

procedure TTyStarShapeTest.TestInnerRatioAffectsInnerRadius;
var
  polyA, polyB: array of TPointF;
  innerA, innerB: Double;
begin
  polyA := TyStarPolygon(Rect(0, 0, 100, 100), 5, 0.30);
  polyB := TyStarPolygon(Rect(0, 0, 100, 100), 5, 0.60);
  innerA := RadiusOf(Rect(0, 0, 100, 100), polyA[1]);
  innerB := RadiusOf(Rect(0, 0, 100, 100), polyB[1]);
  // Larger InnerRatio -> larger inner radius; outer radius unchanged.
  AssertTrue('bigger InnerRatio gives bigger inner radius', innerB > innerA + EPS);
  AssertTrue('inner radius ~= ratio * outer (0.30)',
    Abs(innerA - 0.30 * 50.0) < 1.0);
  AssertTrue('inner radius ~= ratio * outer (0.60)',
    Abs(innerB - 0.60 * 50.0) < 1.0);
end;

procedure TTyStarShapeTest.TestInnerRatioClampsLow;
var
  poly: array of TPointF;
  inner: Double;
begin
  // Below TyStarMinInnerRatio (0.05) clamps up to 0.05.
  poly := TyStarPolygon(Rect(0, 0, 100, 100), 5, 0.0);
  inner := RadiusOf(Rect(0, 0, 100, 100), poly[1]);
  AssertTrue('inner ratio clamps to >= 0.05',
    Abs(inner - TyStarMinInnerRatio * 50.0) < 1.0);
end;

procedure TTyStarShapeTest.TestInnerRatioClampsHigh;
var
  poly: array of TPointF;
  inner, outer: Double;
begin
  // Above TyStarMaxInnerRatio (0.95) clamps down to 0.95 (inner < outer still).
  poly := TyStarPolygon(Rect(0, 0, 100, 100), 5, 2.0);
  inner := RadiusOf(Rect(0, 0, 100, 100), poly[1]);
  outer := RadiusOf(Rect(0, 0, 100, 100), poly[0]);
  AssertTrue('inner ratio clamps to <= 0.95',
    Abs(inner - TyStarMaxInnerRatio * 50.0) < 1.0);
  AssertTrue('clamped inner still below outer', inner < outer);
end;

{ ---- bounds ---- }

procedure TTyStarShapeTest.TestAllVerticesWithinRect;
var
  R: TRect;
  poly: array of TPointF;
  i: Integer;
begin
  R := Rect(10, 20, 210, 140);   // non-square, offset origin
  poly := TyStarPolygon(R, 6, 0.42);
  for i := 0 to High(poly) do
  begin
    AssertTrue(Format('vertex %d x >= left', [i]),  poly[i].x >= R.Left - EPS);
    AssertTrue(Format('vertex %d x <= right', [i]), poly[i].x <= R.Right + EPS);
    AssertTrue(Format('vertex %d y >= top', [i]),   poly[i].y >= R.Top - EPS);
    AssertTrue(Format('vertex %d y <= bottom', [i]),poly[i].y <= R.Bottom + EPS);
  end;
end;

procedure TTyStarShapeTest.TestOuterVerticesReachEdges;
var
  R: TRect;
  poly: array of TPointF;
  outer, halfMin: Double;
begin
  // In a non-square rect the outer radius = half the SHORTER side, so an outer
  // vertex reaches that edge but never overruns the longer side.
  R := Rect(0, 0, 200, 100);
  poly := TyStarPolygon(R, 5, 0.42);
  outer := RadiusOf(R, poly[0]);
  halfMin := Min(R.Right - R.Left, R.Bottom - R.Top) / 2;
  AssertTrue('outer radius = half the shorter side',
    Abs(outer - halfMin) < EPS);
end;

{ ---- first vertex points up ---- }

procedure TTyStarShapeTest.TestFirstVertexPointsUp;
var
  R: TRect;
  poly: array of TPointF;
  cx, cy: Double;
begin
  R := Rect(0, 0, 100, 100);
  poly := TyStarPolygon(R, 5, 0.42);
  cx := (R.Left + R.Right) / 2;
  cy := (R.Top + R.Bottom) / 2;
  // Vertex 0 is straight up: same x as centre, y = centre - outerRadius (=cy-50).
  AssertTrue('first vertex x == centre x', Abs(poly[0].x - cx) < EPS);
  AssertTrue('first vertex sits above centre', poly[0].y < cy - EPS);
  AssertTrue('first vertex y == centre - outer radius',
    Abs(poly[0].y - (cy - 50.0)) < EPS);
end;

{ ---- symmetry ---- }

procedure TTyStarShapeTest.TestHorizontalSymmetry;
var
  R: TRect;
  poly: array of TPointF;
  cx: Double;
  i, mirror: Integer;
begin
  // A star with the top vertex on the vertical axis is left/right mirror
  // symmetric: vertex i mirrors vertex (2n - i) about the vertical centre line.
  R := Rect(0, 0, 100, 100);
  poly := TyStarPolygon(R, 5, 0.42);
  cx := (R.Left + R.Right) / 2;
  for i := 1 to High(poly) do
  begin
    mirror := Length(poly) - i;   // index 1 <-> 9, 2 <-> 8, ...
    AssertTrue(Format('vertex %d mirrors vertex %d in x', [i, mirror]),
      Abs((poly[i].x - cx) + (poly[mirror].x - cx)) < EPS);
    AssertTrue(Format('vertex %d mirrors vertex %d in y', [i, mirror]),
      Abs(poly[i].y - poly[mirror].y) < EPS);
  end;
end;

procedure TTyStarShapeTest.TestDegenerateRectDoesNotCrash;
var
  poly: array of TPointF;
begin
  // A zero-size rect must still return 2*n vertices (all at the centre) — no
  // crash, no negative radius.
  poly := TyStarPolygon(Rect(50, 50, 50, 50), 5, 0.42);
  AssertEquals('degenerate rect still yields 10 vertices', 10, Length(poly));
  AssertTrue('degenerate vertex at centre x', Abs(poly[0].x - 50.0) < EPS);
  AssertTrue('degenerate vertex at centre y', Abs(poly[0].y - 50.0) < EPS);
end;

initialization
  RegisterTest(TTyStarShapeTest);
end.
