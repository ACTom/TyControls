unit test.arrow;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  BGRABitmapTypes,
  tyControls.Arrow;

type
  { Exhaustively exercises the PURE block-arrow geometry function TyArrowPolygon.
    No control instance / no painting — headless, like the Phase-5 pure-solver tests. }
  TTyArrowTest = class(TTestCase)
  private
    // Assert that every returned point lies within (or on the edge of) ARect.
    procedure AssertAllInside(const ARect: TRect; const APts: array of TPointF;
      const AMsg: string);
  published
    procedure TestVertexCountIsSeven;
    procedure TestTipRightEdgeMidpoint;
    procedure TestTipLeftEdgeMidpoint;
    procedure TestTipTopEdgeMidpoint;
    procedure TestTipBottomEdgeMidpoint;
    procedure TestAllPointsInsideRectAllDirs;
    procedure TestHeadRatioClampsLow;
    procedure TestHeadRatioClampsHigh;
    procedure TestShaftRatioClampsLow;
    procedure TestShaftRatioClampsHigh;
    procedure TestHorizontalSymmetryRight;
    procedure TestVerticalSymmetryDown;
    procedure TestShaftThicknessTracksShaftRatio;
    procedure TestHeadLengthTracksHeadRatio;
    // The published properties clamp on assignment, so what streams to the .lfm and what
    // reads back agree with what is actually drawn.
    procedure TestSetHeadRatioClampsOnAssign;
    procedure TestSetShaftRatioClampsOnAssign;
    procedure TestConstructorDefaults;
  end;

implementation

const
  EPS = 0.001;

{ Standard test rect: origin 0, 200 wide x 100 tall (breadth differs from length so
  axis mix-ups surface). }
function StdRect: TRect;
begin
  Result := Rect(0, 0, 200, 100);
end;

procedure TTyArrowTest.AssertAllInside(const ARect: TRect;
  const APts: array of TPointF; const AMsg: string);
var
  i: Integer;
begin
  for i := 0 to High(APts) do
  begin
    AssertTrue(Format('%s: point %d X=%.2f below Left=%d', [AMsg, i, APts[i].x, ARect.Left]),
      APts[i].x >= ARect.Left - EPS);
    AssertTrue(Format('%s: point %d X=%.2f above Right=%d', [AMsg, i, APts[i].x, ARect.Right]),
      APts[i].x <= ARect.Right + EPS);
    AssertTrue(Format('%s: point %d Y=%.2f below Top=%d', [AMsg, i, APts[i].y, ARect.Top]),
      APts[i].y >= ARect.Top - EPS);
    AssertTrue(Format('%s: point %d Y=%.2f above Bottom=%d', [AMsg, i, APts[i].y, ARect.Bottom]),
      APts[i].y <= ARect.Bottom + EPS);
  end;
end;

procedure TTyArrowTest.TestVertexCountIsSeven;
var
  d: TTyArrowDirection;
  pts: ArrayOfTPointF;
begin
  // A block arrow is always exactly 7 vertices, in every direction.
  for d := Low(TTyArrowDirection) to High(TTyArrowDirection) do
  begin
    pts := TyArrowPolygon(StdRect, d, 0.45, 0.5);
    AssertEquals(Format('7 vertices for direction %d', [Ord(d)]), 7, Length(pts));
  end;
end;

procedure TTyArrowTest.TestTipRightEdgeMidpoint;
var
  pts: ArrayOfTPointF;
  r: TRect;
begin
  r := StdRect;
  pts := TyArrowPolygon(r, tadRight, 0.45, 0.5);
  // Tip is pts[0], on the right edge at vertical midpoint.
  AssertEquals('right tip X = Right edge', r.Right, pts[0].x, EPS);
  AssertEquals('right tip Y = vertical midpoint', (r.Top + r.Bottom) / 2, pts[0].y, EPS);
end;

procedure TTyArrowTest.TestTipLeftEdgeMidpoint;
var
  pts: ArrayOfTPointF;
  r: TRect;
begin
  r := StdRect;
  pts := TyArrowPolygon(r, tadLeft, 0.45, 0.5);
  AssertEquals('left tip X = Left edge', r.Left, pts[0].x, EPS);
  AssertEquals('left tip Y = vertical midpoint', (r.Top + r.Bottom) / 2, pts[0].y, EPS);
end;

procedure TTyArrowTest.TestTipTopEdgeMidpoint;
var
  pts: ArrayOfTPointF;
  r: TRect;
begin
  r := StdRect;
  pts := TyArrowPolygon(r, tadUp, 0.45, 0.5);
  AssertEquals('up tip Y = Top edge', r.Top, pts[0].y, EPS);
  AssertEquals('up tip X = horizontal midpoint', (r.Left + r.Right) / 2, pts[0].x, EPS);
end;

procedure TTyArrowTest.TestTipBottomEdgeMidpoint;
var
  pts: ArrayOfTPointF;
  r: TRect;
begin
  r := StdRect;
  pts := TyArrowPolygon(r, tadDown, 0.45, 0.5);
  AssertEquals('down tip Y = Bottom edge', r.Bottom, pts[0].y, EPS);
  AssertEquals('down tip X = horizontal midpoint', (r.Left + r.Right) / 2, pts[0].x, EPS);
end;

procedure TTyArrowTest.TestAllPointsInsideRectAllDirs;
var
  d: TTyArrowDirection;
  pts: ArrayOfTPointF;
  r: TRect;
begin
  // Every vertex, in every direction, at extreme ratios, stays inside the rect.
  r := StdRect;
  for d := Low(TTyArrowDirection) to High(TTyArrowDirection) do
  begin
    pts := TyArrowPolygon(r, d, 0.9, 0.9);
    AssertAllInside(r, pts, Format('dir %d hi ratios', [Ord(d)]));
    pts := TyArrowPolygon(r, d, 0.1, 0.1);
    AssertAllInside(r, pts, Format('dir %d lo ratios', [Ord(d)]));
  end;
end;

procedure TTyArrowTest.TestHeadRatioClampsLow;
var
  clamped, below: ArrayOfTPointF;
begin
  // A below-floor HeadRatio must produce the same geometry as the 0.1 floor.
  clamped := TyArrowPolygon(StdRect, tadRight, 0.1, 0.5);
  below   := TyArrowPolygon(StdRect, tadRight, -5.0, 0.5);
  // Compare the head-base X (shared by pts[1]) — proves the head length clamped.
  AssertEquals('head ratio clamps to floor', clamped[1].x, below[1].x, EPS);
end;

procedure TTyArrowTest.TestHeadRatioClampsHigh;
var
  clamped, above: ArrayOfTPointF;
begin
  clamped := TyArrowPolygon(StdRect, tadRight, 0.9, 0.5);
  above   := TyArrowPolygon(StdRect, tadRight, 9.0, 0.5);
  AssertEquals('head ratio clamps to ceiling', clamped[1].x, above[1].x, EPS);
end;

procedure TTyArrowTest.TestShaftRatioClampsLow;
var
  clamped, below: ArrayOfTPointF;
begin
  clamped := TyArrowPolygon(StdRect, tadRight, 0.45, 0.1);
  below   := TyArrowPolygon(StdRect, tadRight, 0.45, -2.0);
  // Shaft tail top Y (pts[3]) reflects the shaft thickness.
  AssertEquals('shaft ratio clamps to floor', clamped[3].y, below[3].y, EPS);
end;

procedure TTyArrowTest.TestShaftRatioClampsHigh;
var
  clamped, above: ArrayOfTPointF;
begin
  clamped := TyArrowPolygon(StdRect, tadRight, 0.45, 0.9);
  above   := TyArrowPolygon(StdRect, tadRight, 0.45, 3.0);
  AssertEquals('shaft ratio clamps to ceiling', clamped[3].y, above[3].y, EPS);
end;

procedure TTyArrowTest.TestHorizontalSymmetryRight;
var
  pts: ArrayOfTPointF;
  r: TRect;
  midY: Single;
begin
  // A right arrow is mirror-symmetric about the horizontal centre line: the upper
  // barb / shaft points mirror the lower ones.
  r := StdRect;
  pts := TyArrowPolygon(r, tadRight, 0.45, 0.5);
  midY := (r.Top + r.Bottom) / 2;
  // upper barb pts[1] mirrors lower barb pts[6] about midY (same X, opposite dY).
  AssertEquals('barb X mirror', pts[1].x, pts[6].x, EPS);
  AssertEquals('barb Y mirror', midY - pts[1].y, pts[6].y - midY, EPS);
  // shaft-top pts[2] mirrors shaft-bottom pts[5].
  AssertEquals('shaft-side X mirror', pts[2].x, pts[5].x, EPS);
  AssertEquals('shaft-side Y mirror', midY - pts[2].y, pts[5].y - midY, EPS);
end;

procedure TTyArrowTest.TestVerticalSymmetryDown;
var
  pts: ArrayOfTPointF;
  r: TRect;
  midX: Single;
begin
  // A down arrow is mirror-symmetric about the vertical centre line.
  r := StdRect;
  pts := TyArrowPolygon(r, tadDown, 0.45, 0.5);
  midX := (r.Left + r.Right) / 2;
  // right barb pts[1] mirrors left barb pts[6].
  AssertEquals('barb Y mirror', pts[1].y, pts[6].y, EPS);
  AssertEquals('barb X mirror', pts[1].x - midX, midX - pts[6].x, EPS);
end;

procedure TTyArrowTest.TestShaftThicknessTracksShaftRatio;
var
  thin, thick: ArrayOfTPointF;
  thinT, thickT: Single;
begin
  // A larger ShaftRatio yields a thicker shaft (shaft-side pts closer to the edges).
  thin  := TyArrowPolygon(StdRect, tadRight, 0.45, 0.2);
  thick := TyArrowPolygon(StdRect, tadRight, 0.45, 0.8);
  // Shaft half-thickness = distance from midY (50) to shaft-top pts[3].y.
  thinT  := 50 - thin[3].y;
  thickT := 50 - thick[3].y;
  AssertTrue(Format('thicker shaft (thin=%.2f thick=%.2f)', [thinT, thickT]),
    thickT > thinT);
end;

procedure TTyArrowTest.TestHeadLengthTracksHeadRatio;
var
  shortH, longH: ArrayOfTPointF;
  shortLen, longLen: Single;
begin
  // A larger HeadRatio yields a longer head (head-base further from the tip).
  shortH := TyArrowPolygon(StdRect, tadRight, 0.2, 0.5);
  longH  := TyArrowPolygon(StdRect, tadRight, 0.8, 0.5);
  // Head length = tip X (200) - head-base X (pts[1].x).
  shortLen := 200 - shortH[1].x;
  longLen  := 200 - longH[1].x;
  AssertTrue(Format('longer head (short=%.2f long=%.2f)', [shortLen, longLen]),
    longLen > shortLen);
end;

{ ---- published-property clamping (a TGraphicControl needs no window handle) ---- }

procedure TTyArrowTest.TestSetHeadRatioClampsOnAssign;
var
  A: TTyArrow;
begin
  A := TTyArrow.Create(nil);
  try
    A.HeadRatio := 2.0;
    AssertEquals('above range clamps to max', TyArrowMaxRatio, A.HeadRatio, EPS);
    A.HeadRatio := 0.0;
    AssertEquals('below range clamps to min', TyArrowMinRatio, A.HeadRatio, EPS);
    A.HeadRatio := 0.6;
    AssertEquals('in range is kept verbatim', 0.6, A.HeadRatio, EPS);
  finally
    A.Free;
  end;
end;

procedure TTyArrowTest.TestSetShaftRatioClampsOnAssign;
var
  A: TTyArrow;
begin
  A := TTyArrow.Create(nil);
  try
    A.ShaftRatio := -1.0;
    AssertEquals('below range clamps to min', TyArrowMinRatio, A.ShaftRatio, EPS);
    A.ShaftRatio := 5.0;
    AssertEquals('above range clamps to max', TyArrowMaxRatio, A.ShaftRatio, EPS);
  finally
    A.Free;
  end;
end;

procedure TTyArrowTest.TestConstructorDefaults;
var
  A: TTyArrow;
begin
  A := TTyArrow.Create(nil);
  try
    AssertTrue('default direction is right', A.Direction = tadRight);
    AssertEquals('default head ratio', TyArrowDefHeadRatio, A.HeadRatio, EPS);
    AssertEquals('default shaft ratio', TyArrowDefShaftRatio, A.ShaftRatio, EPS);
  finally
    A.Free;
  end;
end;

initialization
  RegisterTest(TTyArrowTest);
end.
