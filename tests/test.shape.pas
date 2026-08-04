unit test.shape;
{$mode objfpc}{$H+}
{ Headless unit tests for TTyShape's PURE geometry: TyShapePolygon (triangle /
  diamond vertices) and TyShapeSquareRect (largest centred square). The control
  itself is never instantiated/painted — only the free functions are asserted,
  exactly like the Phase-5 pure-solver tests. }
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  tyControls.Types, tyControls.Shape;

type
  TTyShapeGeomTest = class(TTestCase)
  published
    // ---- TyShapePolygon: vertex count per kind ----
    procedure TestTriangleHasThreePoints;
    procedure TestDiamondHasFourPoints;
    procedure TestOnlyVertexKindsReturnAPolygon;
    // ---- TyShapePolygon: triangle geometry ----
    procedure TestTriangleApexTopCentre;
    procedure TestTriangleBaseCorners;
    procedure TestTriangleWithinRect;
    procedure TestTriangleHorizontallySymmetric;
    // ---- TyShapePolygon: diamond geometry ----
    procedure TestDiamondEdgeMidpoints;
    procedure TestDiamondWithinRect;
    procedure TestDiamondSymmetric;
    // ---- TyShapePolygon: offset rect (non-zero origin) ----
    procedure TestTriangleOffsetRect;
    // ---- TyShapeSquareRect ----
    procedure TestSquareOfWideRectIsCentred;
    procedure TestSquareOfTallRectIsCentred;
    procedure TestSquareOfSquareRectIsIdentity;
    procedure TestSquareWithinRect;
    procedure TestSquareDegenerateRect;
  end;

implementation

const
  Eps = 0.001;

function InRect(const P: TPointF; const R: TRect): Boolean;
begin
  Result := (P.x >= R.Left - Eps) and (P.x <= R.Right + Eps)
        and (P.y >= R.Top - Eps) and (P.y <= R.Bottom + Eps);
end;

{ ---- vertex count ---- }

procedure TTyShapeGeomTest.TestTriangleHasThreePoints;
var poly: array of TPointF;
begin
  poly := TyShapePolygon(tskTriangle, Rect(0, 0, 100, 60));
  AssertEquals('triangle has exactly 3 vertices', 3, Length(poly));
end;

procedure TTyShapeGeomTest.TestDiamondHasFourPoints;
var poly: array of TPointF;
begin
  poly := TyShapePolygon(tskDiamond, Rect(0, 0, 100, 60));
  AssertEquals('diamond has exactly 4 vertices', 4, Length(poly));
end;

procedure TTyShapeGeomTest.TestOnlyVertexKindsReturnAPolygon;
var
  k: TTyShapeKind;
  poly: array of TPointF;
begin
  { Renamed from TestNonPolygonKindsAreEmpty, which hard-coded [tskTriangle, tskDiamond]
    as "the polygon kinds" -- true when there were eight kinds, and quietly wrong the
    moment the triangles, the squared diamond and the stars arrived. The membership now
    has ONE name, TyShapeVertexKinds, that the painter and the hit test also read, and
    this walks the whole enum against it in BOTH directions: a kind wrongly left out of
    the set draws and hit-tests as a rectangle, and one wrongly put in gets no path at
    all -- so asserting only one direction would miss half of it. }
  for k := Low(TTyShapeKind) to High(TTyShapeKind) do
  begin
    poly := TyShapePolygon(k, Rect(0, 0, 100, 60));
    if k in TyShapeVertexKinds then
      AssertTrue('vertex kind ' + IntToStr(Ord(k)) + ' returns a closed ring',
        Length(poly) >= 3)
    else
      // tskPolygon included: its vertices come from the app through OnShapePoints,
      // never from this pure function.
      AssertEquals('non-vertex kind ' + IntToStr(Ord(k)) + ' returns []',
        0, Length(poly));
  end;
end;

{ ---- triangle geometry ---- }

procedure TTyShapeGeomTest.TestTriangleApexTopCentre;
var poly: array of TPointF;
begin
  poly := TyShapePolygon(tskTriangle, Rect(0, 0, 100, 60));
  AssertEquals('apex x = horizontal centre', 50.0, poly[0].x, Eps);
  AssertEquals('apex y = top edge', 0.0, poly[0].y, Eps);
end;

procedure TTyShapeGeomTest.TestTriangleBaseCorners;
var poly: array of TPointF;
begin
  poly := TyShapePolygon(tskTriangle, Rect(0, 0, 100, 60));
  // [1] = bottom-right corner, [2] = bottom-left corner (clockwise from apex).
  AssertEquals('base-right x', 100.0, poly[1].x, Eps);
  AssertEquals('base-right y', 60.0, poly[1].y, Eps);
  AssertEquals('base-left x', 0.0, poly[2].x, Eps);
  AssertEquals('base-left y', 60.0, poly[2].y, Eps);
end;

procedure TTyShapeGeomTest.TestTriangleWithinRect;
var
  poly: array of TPointF;
  i: Integer;
  R: TRect;
begin
  R := Rect(0, 0, 100, 60);
  poly := TyShapePolygon(tskTriangle, R);
  for i := 0 to High(poly) do
    AssertTrue('triangle vertex ' + IntToStr(i) + ' within rect', InRect(poly[i], R));
end;

procedure TTyShapeGeomTest.TestTriangleHorizontallySymmetric;
var poly: array of TPointF;
begin
  poly := TyShapePolygon(tskTriangle, Rect(0, 0, 100, 60));
  // apex is centred; the two base corners are mirror images about the centre x.
  AssertEquals('base corners mirror about centre',
    50.0 - poly[2].x, poly[1].x - 50.0, Eps);
  AssertEquals('base corners share the bottom y', poly[1].y, poly[2].y, Eps);
end;

{ ---- diamond geometry ---- }

procedure TTyShapeGeomTest.TestDiamondEdgeMidpoints;
var poly: array of TPointF;
begin
  poly := TyShapePolygon(tskDiamond, Rect(0, 0, 100, 60));
  // top, right, bottom, left edge midpoints
  AssertEquals('top mid x', 50.0, poly[0].x, Eps);
  AssertEquals('top mid y', 0.0, poly[0].y, Eps);
  AssertEquals('right mid x', 100.0, poly[1].x, Eps);
  AssertEquals('right mid y', 30.0, poly[1].y, Eps);
  AssertEquals('bottom mid x', 50.0, poly[2].x, Eps);
  AssertEquals('bottom mid y', 60.0, poly[2].y, Eps);
  AssertEquals('left mid x', 0.0, poly[3].x, Eps);
  AssertEquals('left mid y', 30.0, poly[3].y, Eps);
end;

procedure TTyShapeGeomTest.TestDiamondWithinRect;
var
  poly: array of TPointF;
  i: Integer;
  R: TRect;
begin
  R := Rect(0, 0, 100, 60);
  poly := TyShapePolygon(tskDiamond, R);
  for i := 0 to High(poly) do
    AssertTrue('diamond vertex ' + IntToStr(i) + ' within rect', InRect(poly[i], R));
end;

procedure TTyShapeGeomTest.TestDiamondSymmetric;
var
  poly: array of TPointF;
  cx, cy: Single;
begin
  poly := TyShapePolygon(tskDiamond, Rect(0, 0, 100, 60));
  cx := 50.0;
  cy := 30.0;
  // top/bottom are vertically mirrored about cy; left/right horizontally about cx.
  AssertEquals('top/bottom mirror about cy', cy - poly[0].y, poly[2].y - cy, Eps);
  AssertEquals('left/right mirror about cx', cx - poly[3].x, poly[1].x - cx, Eps);
  AssertEquals('top and bottom share centre x', poly[0].x, poly[2].x, Eps);
  AssertEquals('left and right share centre y', poly[1].y, poly[3].y, Eps);
end;

{ ---- offset rect (non-zero origin) ---- }

procedure TTyShapeGeomTest.TestTriangleOffsetRect;
var
  poly: array of TPointF;
  R: TRect;
  i: Integer;
begin
  R := Rect(10, 20, 110, 100);   // 100 wide x 80 tall, origin (10,20)
  poly := TyShapePolygon(tskTriangle, R);
  AssertEquals('apex x = centre of offset rect', 60.0, poly[0].x, Eps);
  AssertEquals('apex y = top of offset rect', 20.0, poly[0].y, Eps);
  AssertEquals('base-right x = right edge', 110.0, poly[1].x, Eps);
  AssertEquals('base-left x = left edge', 10.0, poly[2].x, Eps);
  for i := 0 to High(poly) do
    AssertTrue('offset vertex ' + IntToStr(i) + ' within rect', InRect(poly[i], R));
end;

{ ---- TyShapeSquareRect ---- }

procedure TTyShapeGeomTest.TestSquareOfWideRectIsCentred;
var sq: TRect;
begin
  // 100x60 -> side 60, centred horizontally: x offset (100-60)/2 = 20.
  sq := TyShapeSquareRect(Rect(0, 0, 100, 60));
  AssertEquals('square side (width)', 60, sq.Right - sq.Left);
  AssertEquals('square side (height)', 60, sq.Bottom - sq.Top);
  AssertEquals('left inset centres it', 20, sq.Left);
  AssertEquals('top flush (no vertical inset)', 0, sq.Top);
end;

procedure TTyShapeGeomTest.TestSquareOfTallRectIsCentred;
var sq: TRect;
begin
  // 60x100 -> side 60, centred vertically: y offset (100-60)/2 = 20.
  sq := TyShapeSquareRect(Rect(0, 0, 60, 100));
  AssertEquals('square side (width)', 60, sq.Right - sq.Left);
  AssertEquals('square side (height)', 60, sq.Bottom - sq.Top);
  AssertEquals('left flush (no horizontal inset)', 0, sq.Left);
  AssertEquals('top inset centres it', 20, sq.Top);
end;

procedure TTyShapeGeomTest.TestSquareOfSquareRectIsIdentity;
var sq: TRect;
begin
  sq := TyShapeSquareRect(Rect(5, 5, 85, 85));   // already 80x80
  AssertEquals('identity left', 5, sq.Left);
  AssertEquals('identity top', 5, sq.Top);
  AssertEquals('identity right', 85, sq.Right);
  AssertEquals('identity bottom', 85, sq.Bottom);
end;

procedure TTyShapeGeomTest.TestSquareWithinRect;
var
  R, sq: TRect;
begin
  R := Rect(10, 20, 210, 100);   // wide
  sq := TyShapeSquareRect(R);
  AssertTrue('square left >= rect left', sq.Left >= R.Left);
  AssertTrue('square top >= rect top', sq.Top >= R.Top);
  AssertTrue('square right <= rect right', sq.Right <= R.Right);
  AssertTrue('square bottom <= rect bottom', sq.Bottom <= R.Bottom);
  AssertEquals('is a true square', sq.Right - sq.Left, sq.Bottom - sq.Top);
end;

procedure TTyShapeGeomTest.TestSquareDegenerateRect;
var sq: TRect;
begin
  // Zero/negative area -> empty (Right<=Left), never a crash.
  sq := TyShapeSquareRect(Rect(0, 0, 0, 50));
  AssertTrue('degenerate rect yields empty square', sq.Right <= sq.Left);
end;

initialization
  RegisterTest(TTyShapeGeomTest);
end.
