unit test.parity.shapearrow;
{$mode objfpc}{$H+}
{ API-parity guards for tyControls.Shape / tyControls.Arrow against their LCL
  counterparts (TShape in lcl/extctrls.pp + lcl/include/shape.inc, TArrow in
  lcl/arrow.pp).

  Two defects are pinned here:

    1. TTyShape hit-tested by its BOUNDING BOX. A circle swallowed the clicks in its
       rectangle's corners, so a control behind it there could never be reached.
    2. TTyArrow could only draw the 7-point block glyph. LCL's TArrow draws a
       3-point triangle sized by an apex angle (ArrowPointerAngle), and that glyph
       was unreachable from this control at any property setting. }
interface
uses
  Classes, SysUtils, Types, TypInfo, Controls, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Shape, tyControls.Arrow;

type
  { The runtime half: what LCL's ControlAtPos asks a control while routing a mouse
    message, driven exactly as wincontrol.inc:5239 drives it. }
  TTyShapeHitTestTest = class(TTestCase)
  published
    procedure TestCircleCornerFallsThrough;
    procedure TestCircleCentreIsStillHit;
    procedure TestTriangleCornerFallsThrough;
    procedure TestDiamondCornerFallsThrough;
    procedure TestRectangleStillHitsEveryPixel;
    procedure TestPtInShapeAgreesWithHitTest;
  end;

  { The pure half: TyShapeGeometry / TyPointInShape with no control, no theme and no
    painter, so the numbers are fixed rather than whatever the active skin resolves. }
  TTyShapeGeometryTest = class(TTestCase)
  published
    procedure TestStrokeInsetMatchesPaintPath;
    procedure TestSquareAndCircleBoundsAreTheCentredSquare;
    procedure TestLineIsAlwaysStrokedEvenWithNoBorder;
    procedure TestRadiusCappedAtHalfTheShorterSide;
    procedure TestDegenerateRectIsNotValidAndHitsNothing;
    procedure TestEllipseCornerOutBodyIn;
    procedure TestTrianglePolygonAgreesWithPointTest;
    procedure TestDiamondEdgeIsHitAndBeyondIsNot;
    procedure TestLineHitsAlongItsBandOnly;
    procedure TestStrokeBandWidensTheHitArea;
    procedure TestRoundRectCornerIsRoundedNotSquare;
  end;

  { The two message protocols answer with opposite polarity; this pins both truth
    tables, because getting them backwards compiles and silently inverts the control. }
  TTyShapeHitProtocolTest = class(TTestCase)
  published
    procedure TestHitTestAnswerIsNonZeroOnShape;
    procedure TestMaskHitTestAnswerIsZeroOnShape;
    procedure TestMaskHitTestFallsBackToSelectable;
  end;

  { The whole point of routing paint and hit-test through one TTyShapeGeometry: what is
    CLICKABLE and what is VISIBLE must be the same pixels. Asserted against the actual
    rendered ink, not against a second copy of the maths. }
  TTyShapePaintAgreementTest = class(TTestCase)
  published
    procedure TestInkAndHitAreaCoincide;
  end;

  TTyArrowGlyphTest = class(TTestCase)
  published
    procedure TestTriangleModeReachesTheCanvas;
    procedure TestApexAngleIsPublished;
    procedure TestShapeModeIsPublished;
    procedure TestBlockArrowStaysTheDefault;
    procedure TestTriangleHasThreePointsEveryDirection;
    procedure TestTriangleTipLeadsOnThePointingAxis;
    procedure TestTriangleFitsInsideRectEveryAngle;
    procedure TestDefaultAngleIsEquilateral;
    procedure TestWiderAngleGivesAWiderBase;
    procedure TestAngleClampsInTheGeometry;
    procedure TestAngleClampsOnAssign;
    procedure TestTriangleDegenerateRectIsSafe;
  end;

implementation

const
  EPS = 0.001;

{ Drive CM_HITTEST the way TWinControl.ControlAtPos does while routing a mouse
  message (lcl/include/wincontrol.inc:5239): the coordinates are CONTROL-relative and
  a NON-ZERO answer means "the point is mine". A control answering 0 is skipped and
  the message falls through to whatever sits behind it. }
function AskHitTest(ACtl: TControl; AX, AY: Integer): Integer;
var
  Msg: TCMHitTest;
begin
  FillChar(Msg, SizeOf(Msg), 0);
  Msg.Msg := CM_HITTEST;
  Msg.XPos := AX;
  Msg.YPos := AY;
  Msg.Result := 1;          // TControl.CMHitTest's own answer: a plain rectangular hit
  ACtl.Dispatch(Msg);
  Result := Msg.Result;
end;

function MakeShape(AKind: TTyShapeKind; AW, AH: Integer): TTyShape;
begin
  Result := TTyShape.Create(nil);
  Result.Shape := AKind;
  Result.SetBounds(0, 0, AW, AH);
end;

{ ---- TTyShape: shape-precise hit testing ---- }

procedure TTyShapeHitTestTest.TestCircleCornerFallsThrough;
var
  Sh: TTyShape;
begin
  // A 200x200 circle has radius 100 about (100,100); (3,3) is ~137px out — nowhere
  // near the ink under any theme's border width. Before the fix the control answered
  // "mine" here, so a button underneath the corner could never be clicked.
  Sh := MakeShape(tskCircle, 200, 200);
  try
    AssertEquals('circle top-left corner falls through', 0, AskHitTest(Sh, 3, 3));
    AssertEquals('circle bottom-right corner falls through', 0, AskHitTest(Sh, 196, 196));
  finally
    Sh.Free;
  end;
end;

procedure TTyShapeHitTestTest.TestCircleCentreIsStillHit;
var
  Sh: TTyShape;
begin
  Sh := MakeShape(tskCircle, 200, 200);
  try
    AssertTrue('circle centre is still the control''s own click',
      AskHitTest(Sh, 100, 100) <> 0);
  finally
    Sh.Free;
  end;
end;

procedure TTyShapeHitTestTest.TestTriangleCornerFallsThrough;
var
  Sh: TTyShape;
begin
  // Apex top-centre, base along the bottom: the two TOP corners are empty canvas.
  Sh := MakeShape(tskTriangle, 200, 100);
  try
    AssertEquals('triangle top-left corner falls through', 0, AskHitTest(Sh, 3, 3));
    AssertEquals('triangle top-right corner falls through', 0, AskHitTest(Sh, 196, 3));
    AssertTrue('but the body is still hit', AskHitTest(Sh, 100, 90) <> 0);
  finally
    Sh.Free;
  end;
end;

procedure TTyShapeHitTestTest.TestDiamondCornerFallsThrough;
var
  Sh: TTyShape;
begin
  // A rhombus on the four edge midpoints leaves all four corners empty.
  Sh := MakeShape(tskDiamond, 200, 100);
  try
    AssertEquals('diamond top-left corner falls through', 0, AskHitTest(Sh, 2, 2));
    AssertEquals('diamond bottom-right corner falls through', 0, AskHitTest(Sh, 197, 97));
    AssertTrue('but the centre is still hit', AskHitTest(Sh, 100, 50) <> 0);
  finally
    Sh.Free;
  end;
end;

procedure TTyShapeHitTestTest.TestRectangleStillHitsEveryPixel;
var
  Sh: TTyShape;
begin
  // The DEFAULT kind must be untouched by the fix, right out to the last pixel: the
  // border stroke is centred on a path inset by ceil(width/2), so its ink reaches the
  // client edge and the outermost pixel row/column is still the shape.
  Sh := MakeShape(tskRectangle, 200, 100);
  try
    AssertTrue('rect top-left pixel', AskHitTest(Sh, 0, 0) <> 0);
    AssertTrue('rect bottom-right pixel', AskHitTest(Sh, 199, 99) <> 0);
    AssertTrue('rect centre', AskHitTest(Sh, 100, 50) <> 0);
  finally
    Sh.Free;
  end;
end;

procedure TTyShapeHitTestTest.TestPtInShapeAgreesWithHitTest;
var
  Sh: TTyShape;
begin
  // PtInShape is the public query; CM_HITTEST is the message. One must not be able to
  // say yes where the other says no.
  Sh := MakeShape(tskCircle, 200, 200);
  try
    AssertEquals('corner: query and message agree',
      Ord(Sh.PtInShape(Point(3, 3))), Ord(AskHitTest(Sh, 3, 3) <> 0));
    AssertEquals('centre: query and message agree',
      Ord(Sh.PtInShape(Point(100, 100))), Ord(AskHitTest(Sh, 100, 100) <> 0));
  finally
    Sh.Free;
  end;
end;

{ ---- TTyShape: the pure geometry both the paint and the hit test read ---- }

{ A 1px border is the library's common case: TyShapeGeometry insets by ceil(1/2) = 1. }
function Geom1px(AKind: TTyShapeKind; AW, AH: Integer): TTyShapeGeometry;
begin
  Result := TyShapeGeometry(AKind, Rect(0, 0, AW, AH), 1, 0, True);
end;

procedure TTyShapeGeometryTest.TestStrokeInsetMatchesPaintPath;
var
  G: TTyShapeGeometry;
begin
  // Canvas2D centres a stroke on its path, so RenderTo insets by ceil(width/2) on every
  // side. The hit test reads this same Bounds — if the inset moved, both would move.
  G := TyShapeGeometry(tskRectangle, Rect(0, 0, 100, 60), 4, 0, True);
  AssertTrue('valid', G.Valid);
  AssertEquals('left inset by ceil(4/2)', 2, G.Bounds.Left);
  AssertEquals('right inset by ceil(4/2)', 98, G.Bounds.Right);
  // An odd width rounds UP, never down: a `div 2` here would clip the near edges.
  G := TyShapeGeometry(tskRectangle, Rect(0, 0, 100, 60), 3, 0, True);
  AssertEquals('odd stroke width rounds up', 2, G.Bounds.Left);
  // No border at all: the shape fills the whole rect.
  G := TyShapeGeometry(tskRectangle, Rect(0, 0, 100, 60), 1, 0, False);
  AssertFalse('unstroked', G.Stroked);
  AssertEquals('no inset without a border', 0, G.Bounds.Left);
  AssertEquals('no inset without a border', 100, G.Bounds.Right);
end;

procedure TTyShapeGeometryTest.TestSquareAndCircleBoundsAreTheCentredSquare;
var
  G: TTyShapeGeometry;
begin
  // 200x100 with a 1px inset -> 198x98 -> largest centred square is 98x98 at x=51.
  G := Geom1px(tskCircle, 200, 100);
  AssertEquals('circle bounds is a square', G.Bounds.Right - G.Bounds.Left,
    G.Bounds.Bottom - G.Bounds.Top);
  AssertEquals('circle bounds centred', 51, G.Bounds.Left);
  G := Geom1px(tskSquare, 200, 100);
  AssertEquals('square bounds is a square', G.Bounds.Right - G.Bounds.Left,
    G.Bounds.Bottom - G.Bounds.Top);
  // The ellipse is NOT squared — it fills the rect.
  G := Geom1px(tskEllipse, 200, 100);
  AssertEquals('ellipse keeps the full width', 1, G.Bounds.Left);
  AssertEquals('ellipse keeps the full width', 199, G.Bounds.Right);
end;

procedure TTyShapeGeometryTest.TestLineIsAlwaysStrokedEvenWithNoBorder;
var
  G: TTyShapeGeometry;
begin
  // tskLine's stroke IS the shape, not chrome around it, so `border-style: none` must
  // not erase it — and therefore must not erase its hit band either.
  G := TyShapeGeometry(tskLine, Rect(0, 0, 100, 100), 1, 0, False);
  AssertTrue('a line strokes regardless of the theme', G.Stroked);
  G := TyShapeGeometry(tskRectangle, Rect(0, 0, 100, 100), 1, 0, False);
  AssertFalse('every other kind obeys the theme', G.Stroked);
end;

procedure TTyShapeGeometryTest.TestRadiusCappedAtHalfTheShorterSide;
var
  G: TTyShapeGeometry;
begin
  // A theme radius larger than the box would otherwise fold the corners through
  // each other. 102x42 insets by 1 per side -> a 100x40 box -> cap at 40/2 = 20.
  G := TyShapeGeometry(tskRoundRect, Rect(0, 0, 102, 42), 1, 500, True);
  AssertEquals('radius capped at half the shorter side', 20.0, G.Radius, EPS);
  G := TyShapeGeometry(tskRoundRect, Rect(0, 0, 102, 42), 1, 6, True);
  AssertEquals('a smaller theme radius is honoured', 6.0, G.Radius, EPS);
  // Only roundrect carries one.
  G := TyShapeGeometry(tskRectangle, Rect(0, 0, 102, 42), 1, 500, True);
  AssertEquals('a plain rect has no radius', 0.0, G.Radius, EPS);
end;

procedure TTyShapeGeometryTest.TestDegenerateRectIsNotValidAndHitsNothing;
var
  G: TTyShapeGeometry;
begin
  G := TyShapeGeometry(tskRectangle, Rect(0, 0, 0, 0), 1, 0, True);
  AssertFalse('zero-size box is not valid', G.Valid);
  AssertFalse('and nothing lands on it', TyPointInShape(G, PointF(0, 0)));
  // Small enough that the stroke inset eats it entirely.
  G := TyShapeGeometry(tskRectangle, Rect(0, 0, 3, 3), 8, 0, True);
  AssertFalse('inset-away box is not valid', G.Valid);
  AssertFalse('and nothing lands on it', TyPointInShape(G, PointF(1, 1)));
end;

procedure TTyShapeGeometryTest.TestEllipseCornerOutBodyIn;
var
  G: TTyShapeGeometry;
begin
  G := Geom1px(tskEllipse, 200, 100);
  AssertTrue('centre is inside', TyPointInShape(G, PointF(100, 50)));
  AssertFalse('top-left corner is outside', TyPointInShape(G, PointF(3, 3)));
  AssertFalse('bottom-right corner is outside', TyPointInShape(G, PointF(197, 97)));
  // On the long axis the ellipse reaches the edge; on the short axis too.
  AssertTrue('left extremum is inside', TyPointInShape(G, PointF(2, 50)));
  AssertTrue('top extremum is inside', TyPointInShape(G, PointF(100, 2)));
end;

procedure TTyShapeGeometryTest.TestTrianglePolygonAgreesWithPointTest;
var
  G: TTyShapeGeometry;
  poly: ArrayOfTPointF;
begin
  // The hit test must read the SAME vertices RenderTo draws. Assert on the polygon
  // itself: its own centroid is inside, the top corners of its box are not.
  G := Geom1px(tskTriangle, 200, 100);
  poly := TyShapePolygon(tskTriangle, G.Bounds);
  AssertEquals('triangle geometry still yields 3 vertices', 3, Length(poly));
  AssertTrue('centroid is inside', TyPointInShape(G,
    PointF((poly[0].x + poly[1].x + poly[2].x) / 3,
           (poly[0].y + poly[1].y + poly[2].y) / 3)));
  AssertTrue('the apex vertex itself is on the shape', TyPointInShape(G, poly[0]));
  AssertFalse('top-left of the box is not', TyPointInShape(G, PointF(4, 4)));
  AssertFalse('top-right of the box is not', TyPointInShape(G, PointF(196, 4)));
end;

procedure TTyShapeGeometryTest.TestDiamondEdgeIsHitAndBeyondIsNot;
var
  G: TTyShapeGeometry;
  poly: ArrayOfTPointF;
  mx, my: Single;
begin
  G := Geom1px(tskDiamond, 200, 100);
  poly := TyShapePolygon(tskDiamond, G.Bounds);
  AssertTrue('centre is inside', TyPointInShape(G, PointF(100, 50)));
  // Midpoint of the top-left edge: on the outline, so within the stroke band.
  mx := (poly[3].x + poly[0].x) / 2;
  my := (poly[3].y + poly[0].y) / 2;
  AssertTrue('a point on the edge is on the shape', TyPointInShape(G, PointF(mx, my)));
  // Step well outside that same edge (up-left, away from the body).
  AssertFalse('a point clear of the edge is not',
    TyPointInShape(G, PointF(mx - 12, my - 12)));
end;

procedure TTyShapeGeometryTest.TestLineHitsAlongItsBandOnly;
var
  G: TTyShapeGeometry;
begin
  // A fat line so the band is unambiguous: width 10 -> half-band 5.
  G := TyShapeGeometry(tskLine, Rect(0, 0, 100, 100), 10, 0, True);
  AssertTrue('on the diagonal', TyPointInShape(G, PointF(50, 50)));
  AssertTrue('just off the diagonal, still under the stroke',
    TyPointInShape(G, PointF(52, 50)));
  // The top-right corner is the whole point: 45 degrees away from a diagonal line.
  AssertFalse('top-right corner is empty canvas', TyPointInShape(G, PointF(95, 5)));
  AssertFalse('bottom-left corner is empty canvas', TyPointInShape(G, PointF(5, 95)));
end;

procedure TTyShapeGeometryTest.TestStrokeBandWidensTheHitArea;
var
  thin, fat: TTyShapeGeometry;
begin
  // The ink reaches half the stroke width beyond the path, so the hit area has to as
  // well — otherwise a thick border is visibly clickable and analytically not.
  thin := TyShapeGeometry(tskEllipse, Rect(0, 0, 100, 100), 1, 0, True);
  fat  := TyShapeGeometry(tskEllipse, Rect(0, 0, 100, 100), 16, 0, True);
  // Both ellipses are centred on (50,50); the fat one's path is inset further but its
  // band reaches back out. Sample on the horizontal extremum of the thin one.
  AssertTrue('thin: on its own left extremum', TyPointInShape(thin, PointF(1.2, 50)));
  AssertTrue('fat: the band reaches the same place', TyPointInShape(fat, PointF(1.2, 50)));
  // Without the band the fat ellipse's path alone (inset 8) would stop at x=8.
  AssertTrue('fat: inside its band at x=4', TyPointInShape(fat, PointF(4, 50)));
end;

procedure TTyShapeGeometryTest.TestRoundRectCornerIsRoundedNotSquare;
var
  G: TTyShapeGeometry;
begin
  // Radius 30 on a 100x100 box: the very corner is cut away, the edge midpoints are not.
  G := TyShapeGeometry(tskRoundRect, Rect(0, 0, 100, 100), 1, 30, True);
  AssertEquals('radius kept', 30.0, G.Radius, EPS);
  AssertTrue('centre', TyPointInShape(G, PointF(50, 50)));
  AssertTrue('top edge midpoint', TyPointInShape(G, PointF(50, 1.2)));
  AssertFalse('the rounded-away corner is not on the shape',
    TyPointInShape(G, PointF(2, 2)));
  // A zero radius leaves the corner square — proving the corner test is the radius.
  G := TyShapeGeometry(tskRoundRect, Rect(0, 0, 100, 100), 1, 0, True);
  AssertTrue('a square corner IS on the shape', TyPointInShape(G, PointF(2, 2)));
end;

{ ---- the two message protocols, whose polarities are opposite ---- }

procedure TTyShapeHitProtocolTest.TestHitTestAnswerIsNonZeroOnShape;
begin
  // wincontrol.inc:5239 — `Perform(CM_HITTEST,...) <> 0` means the point is the
  // control's; TControl.CMHitTest answers 1 (control.inc:1171).
  AssertEquals('on the shape answers 1', 1, TyShapeHitTestAnswer(True));
  AssertEquals('off the shape answers 0', 0, TyShapeHitTestAnswer(False));
end;

procedure TTyShapeHitProtocolTest.TestMaskHitTestAnswerIsZeroOnShape;
begin
  // designer.pp:501 — `Perform(CM_MASKHITTEST,...) > 0` makes the designer SKIP the
  // control, and TControl has no handler at all, so an unmasked control answers 0.
  // The inverse of CM_HITTEST above, and it compiles just as happily backwards.
  AssertEquals('on the shape answers 0', 0, TyShapeMaskHitTestAnswer(True));
  AssertEquals('off the shape answers 1', 1, TyShapeMaskHitTestAnswer(False));
end;

procedure TTyShapeHitProtocolTest.TestMaskHitTestFallsBackToSelectable;
var
  Sh: TTyShape;
  Msg: TCMHitTest;
begin
  // Outside a designer the message point cannot be translated (there is no designer
  // form to translate it from). It must then answer exactly as an unmasked TControl
  // does — 0, selectable — never 1, which would make the shape unpickable.
  Sh := MakeShape(tskCircle, 200, 200);
  try
    FillChar(Msg, SizeOf(Msg), 0);
    Msg.Msg := CM_MASKHITTEST;
    Msg.XPos := 3;
    Msg.YPos := 3;
    Msg.Result := 99;
    Sh.Dispatch(Msg);
    AssertEquals('no designer form -> stays selectable', 0, Msg.Result);
  finally
    Sh.Free;
  end;
end;

{ ---- paint vs hit area ---- }

type
  { RenderTo is protected on both controls; reach it the way test.badge.pas does. }
  TShapeAccess = class(TTyShape)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TArrowAccess = class(TTyArrow)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TShapeAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TArrowAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

const
  INK_W = 80;
  INK_H = 60;

{ The shapes below paint a strong blue over a black backdrop, so "inked" is unambiguous
  and the anti-aliased rim reads as neither. }
function IsInk(const APx: TBGRAPixel): Boolean;
begin
  Result := (APx.blue > 150) and (APx.red < 100);
end;

{ Render AKind and count pixels where the ink and TyPointInShape disagree, IGNORING every
  pixel within one pixel of the analytic boundary — that is where anti-aliasing makes
  "inked" a matter of degree. A non-zero count means the painter and the hit test are
  working from different geometry. }
function InkHitDisagreements(ACtl: TTyStyleController; AKind: TTyShapeKind): Integer;
var
  Sh: TShapeAccess;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  G: TTyShapeGeometry;
  x, y, dx, dy: Integer;
  hit, onBoundary: Boolean;
begin
  Result := 0;
  Sh := TShapeAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    Sh.Controller := ACtl;
    Sh.Font.PixelsPerInch := 96;
    Sh.Shape := AKind;
    Sh.SetBounds(0, 0, INK_W, INK_H);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(INK_W, INK_H);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, INK_W, INK_H);
    Sh.RenderTo(Bmp.Canvas, Rect(0, 0, INK_W, INK_H), 96);

    G := Sh.ShapeGeometry;
    Img := TBGRABitmap.Create(Bmp);
    try
      for y := 1 to INK_H - 2 do
        for x := 1 to INK_W - 2 do
        begin
          hit := TyPointInShape(G, PointF(x + 0.5, y + 0.5));
          onBoundary := False;
          for dy := -1 to 1 do
            for dx := -1 to 1 do
              if TyPointInShape(G, PointF(x + dx + 0.5, y + dy + 0.5)) <> hit then
                onBoundary := True;
          if onBoundary then Continue;
          if IsInk(Img.GetPixel(x, y)) <> hit then Inc(Result);
        end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
    Sh.Free;
  end;
end;

procedure TTyShapePaintAgreementTest.TestInkAndHitAreaCoincide;
var
  Ctl: TTyStyleController;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // A fat border so the stroke BAND is a real part of the answer, not a rounding detail.
    Ctl.LoadThemeCss('TyShape { background: #3B82F6; border-color: #3B82F6; '
      + 'border-width: 3px; border-radius: 12px; }');
    AssertEquals('circle: ink and hit area coincide', 0,
      InkHitDisagreements(Ctl, tskCircle));
    AssertEquals('ellipse: ink and hit area coincide', 0,
      InkHitDisagreements(Ctl, tskEllipse));
    AssertEquals('triangle: ink and hit area coincide', 0,
      InkHitDisagreements(Ctl, tskTriangle));
    AssertEquals('diamond: ink and hit area coincide', 0,
      InkHitDisagreements(Ctl, tskDiamond));
    AssertEquals('roundrect: ink and hit area coincide', 0,
      InkHitDisagreements(Ctl, tskRoundRect));
    AssertEquals('square: ink and hit area coincide', 0,
      InkHitDisagreements(Ctl, tskSquare));
  finally
    Ctl.Free;
  end;
end;

{ ---- TTyArrow: the triangle glyph has to be reachable at all ---- }

procedure TTyArrowGlyphTest.TestTriangleModeReachesTheCanvas;
var
  Ctl: TTyStyleController;
  A: TArrowAccess;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  blockShaft, triShaft, blockBody, triBody: Boolean;
  blockInk, triInk: Integer;

  procedure Draw;
  begin
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 200, 100);
    A.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 100), 96);
    Img := TBGRABitmap.Create(Bmp);
  end;

  function InkCount: Integer;
  var
    x, y: Integer;
  begin
    Result := 0;
    for y := 0 to 99 do
      for x := 0 to 199 do
        if IsInk(Img.GetPixel(x, y)) then Inc(Result);
  end;

begin
  // Reaching the geometry function is not enough — RenderTo has to actually call it.
  // A right-pointing block arrow's SHAFT runs out to the left edge; a 60-degree triangle
  // fitted to a 200x100 rect only spans the middle ~85px, so (10,50) separates them.
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyArrow { background: #3B82F6; border-color: #3B82F6; '
      + 'border-width: 1px; }');
    A := TArrowAccess.Create(nil);
    try
      A.Controller := Ctl;
      A.Font.PixelsPerInch := 96;
      A.Direction := tadRight;
      A.SetBounds(0, 0, 200, 100);
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(200, 100);

      A.Shape := tasBlock;
      Draw;
      try
        blockShaft := IsInk(Img.GetPixel(10, 50));
        blockBody := IsInk(Img.GetPixel(100, 50));
        blockInk := InkCount;
      finally
        Img.Free;
      end;

      A.Shape := tasTriangle;
      A.ArrowPointerAngle := 60;
      Draw;
      try
        triShaft := IsInk(Img.GetPixel(10, 50));
        triBody := IsInk(Img.GetPixel(100, 50));
        triInk := InkCount;
      finally
        Img.Free;
      end;

      // Both glyphs must actually reach the canvas — an empty render would otherwise
      // satisfy "the triangle does not ink the shaft" for the wrong reason.
      AssertTrue(Format('block arrow drew something (%d px)', [blockInk]), blockInk > 0);
      AssertTrue(Format('triangle drew something (%d px)', [triInk]), triInk > 0);
      AssertTrue('block arrow body drawn', blockBody);
      AssertTrue('triangle body drawn', triBody);
      AssertTrue('the block arrow inks its shaft out to the left edge', blockShaft);
      AssertFalse('the triangle has no shaft to ink there', triShaft);
    finally
      A.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyArrowGlyphTest.TestApexAngleIsPublished;
var
  A: TTyArrow;
begin
  // LCL's TArrow sizes its triangle from ArrowPointerAngle (arrow.pp, default 60 =
  // equilateral). Same name deliberately: a form ported from TArrow keeps working.
  A := TTyArrow.Create(nil);
  try
    AssertTrue('ArrowPointerAngle is a published property',
      GetPropInfo(A, 'ArrowPointerAngle') <> nil);
  finally
    A.Free;
  end;
end;

procedure TTyArrowGlyphTest.TestShapeModeIsPublished;
var
  A: TTyArrow;
begin
  A := TTyArrow.Create(nil);
  try
    AssertTrue('Shape (block / triangle) is a published property',
      GetPropInfo(A, 'Shape') <> nil);
  finally
    A.Free;
  end;
end;

procedure TTyArrowGlyphTest.TestBlockArrowStaysTheDefault;
var
  A: TTyArrow;
begin
  // Adding the triangle must not redraw a single existing form: an arrow nobody
  // configured is still the 7-point block glyph.
  A := TTyArrow.Create(nil);
  try
    AssertTrue('default shape is the block arrow', A.Shape = tasBlock);
    AssertEquals('LCL TArrow''s own default angle', 60, A.ArrowPointerAngle);
    AssertEquals('and the constant agrees', TyArrowDefPointerAngle, A.ArrowPointerAngle);
  finally
    A.Free;
  end;
end;

procedure TTyArrowGlyphTest.TestTriangleHasThreePointsEveryDirection;
var
  d: TTyArrowDirection;
  pts: ArrayOfTPointF;
begin
  // Three, not seven: this IS the glyph difference the control could not express.
  for d := Low(TTyArrowDirection) to High(TTyArrowDirection) do
  begin
    pts := TyArrowTrianglePolygon(Rect(0, 0, 200, 100), d, 60);
    AssertEquals(Format('3 vertices for direction %d', [Ord(d)]), 3, Length(pts));
  end;
  // ...and the block arrow is untouched.
  AssertEquals('block arrow still has 7', 7,
    Length(TyArrowPolygon(Rect(0, 0, 200, 100), tadRight, 0.45, 0.5)));
end;

procedure TTyArrowGlyphTest.TestTriangleTipLeadsOnThePointingAxis;
var
  pts: ArrayOfTPointF;
  r: TRect;
begin
  // pts[0] is the tip, as in TyArrowPolygon. It sits on the pointing axis' centre line
  // and AHEAD of both base corners — the triangle is centred, so it need not touch the
  // rect edge when the angle is narrower than the rect.
  r := Rect(0, 0, 200, 100);

  pts := TyArrowTrianglePolygon(r, tadRight, 60);
  AssertEquals('right tip on the vertical centre line', 50.0, pts[0].y, EPS);
  AssertTrue('right tip is right of the base', pts[0].x > pts[1].x);
  AssertEquals('base corners share an x', pts[1].x, pts[2].x, EPS);

  pts := TyArrowTrianglePolygon(r, tadLeft, 60);
  AssertEquals('left tip on the vertical centre line', 50.0, pts[0].y, EPS);
  AssertTrue('left tip is left of the base', pts[0].x < pts[1].x);

  pts := TyArrowTrianglePolygon(r, tadUp, 60);
  AssertEquals('up tip on the horizontal centre line', 100.0, pts[0].x, EPS);
  AssertTrue('up tip is above the base', pts[0].y < pts[1].y);

  pts := TyArrowTrianglePolygon(r, tadDown, 60);
  AssertEquals('down tip on the horizontal centre line', 100.0, pts[0].x, EPS);
  AssertTrue('down tip is below the base', pts[0].y > pts[1].y);
end;

procedure TTyArrowGlyphTest.TestTriangleFitsInsideRectEveryAngle;
var
  d: TTyArrowDirection;
  pts: ArrayOfTPointF;
  r: TRect;
  i, a: Integer;
begin
  // The angle scales the triangle DOWN to fit; it must never push a vertex out of the
  // rect, at either clamp or in between, in any direction.
  r := Rect(10, 20, 210, 120);
  for d := Low(TTyArrowDirection) to High(TTyArrowDirection) do
    for a := 0 to 3 do
    begin
      pts := TyArrowTrianglePolygon(r, d, 20 + a * 47);   // 20, 67, 114, 161 -> clamped
      for i := 0 to High(pts) do
      begin
        AssertTrue(Format('dir %d angle %d: x in rect', [Ord(d), 20 + a * 47]),
          (pts[i].x >= r.Left - EPS) and (pts[i].x <= r.Right + EPS));
        AssertTrue(Format('dir %d angle %d: y in rect', [Ord(d), 20 + a * 47]),
          (pts[i].y >= r.Top - EPS) and (pts[i].y <= r.Bottom + EPS));
      end;
    end;
end;

procedure TTyArrowGlyphTest.TestDefaultAngleIsEquilateral;
var
  d: TTyArrowDirection;
  pts: ArrayOfTPointF;
  base, height: Single;
begin
  // LCL's default 60 degrees is the equilateral triangle: base/height = 2*tan(30) =
  // 1.1547. Assert it in EVERY direction — the pointing axis swaps for left/right, and
  // an arrow whose apex angle is only right for the vertical pair still fits its rect,
  // still points the right way, and is still the wrong triangle. tadRight is this
  // control's default direction, so that is the one the naive test would have missed.
  for d := Low(TTyArrowDirection) to High(TTyArrowDirection) do
  begin
    pts := TyArrowTrianglePolygon(Rect(0, 0, 200, 200), d, 60);
    if d in [tadUp, tadDown] then
    begin
      base := Abs(pts[2].x - pts[1].x);      // base runs across X
      height := Abs(pts[1].y - pts[0].y);    // tip to base along Y
    end
    else
    begin
      base := Abs(pts[2].y - pts[1].y);      // base runs across Y
      height := Abs(pts[1].x - pts[0].x);    // tip to base along X
    end;
    AssertEquals(Format('equilateral base:height for direction %d', [Ord(d)]),
      1.1547, base / height, 0.001);
  end;
end;

procedure TTyArrowGlyphTest.TestWiderAngleGivesAWiderBase;
var
  narrow, wide: ArrayOfTPointF;
begin
  // The angle has to actually reach the geometry, not just be stored.
  narrow := TyArrowTrianglePolygon(Rect(0, 0, 200, 200), tadUp, 30);
  wide   := TyArrowTrianglePolygon(Rect(0, 0, 200, 200), tadUp, 120);
  AssertTrue('a wider apex angle gives a wider base',
    Abs(wide[2].x - wide[1].x) > Abs(narrow[2].x - narrow[1].x));
end;

procedure TTyArrowGlyphTest.TestAngleClampsInTheGeometry;
var
  atMin, below, atMax, above: ArrayOfTPointF;
  r: TRect;
begin
  // Same limits as LCL's cMinAngle / cMaxAngle (arrow.pp), enforced in the geometry so
  // a caller reaching the free function directly cannot escape them either.
  r := Rect(0, 0, 200, 200);
  atMin := TyArrowTrianglePolygon(r, tadUp, TyArrowMinPointerAngle);
  below := TyArrowTrianglePolygon(r, tadUp, -400);
  AssertEquals('below the floor draws the floor', atMin[1].x, below[1].x, EPS);
  atMax := TyArrowTrianglePolygon(r, tadUp, TyArrowMaxPointerAngle);
  above := TyArrowTrianglePolygon(r, tadUp, 999);
  AssertEquals('above the ceiling draws the ceiling', atMax[1].x, above[1].x, EPS);
  AssertTrue('the two clamps are not the same triangle',
    Abs(atMin[1].x - atMax[1].x) > 1.0);
end;

procedure TTyArrowGlyphTest.TestAngleClampsOnAssign;
var
  A: TTyArrow;
begin
  // Clamped on assignment like HeadRatio / ShaftRatio, so what streams to the .lfm and
  // what reads back agree with what is drawn.
  A := TTyArrow.Create(nil);
  try
    A.ArrowPointerAngle := 5;
    AssertEquals('below range clamps to min', TyArrowMinPointerAngle, A.ArrowPointerAngle);
    A.ArrowPointerAngle := 900;
    AssertEquals('above range clamps to max', TyArrowMaxPointerAngle, A.ArrowPointerAngle);
    A.ArrowPointerAngle := 45;
    AssertEquals('in range is kept verbatim', 45, A.ArrowPointerAngle);
  finally
    A.Free;
  end;
end;

procedure TTyArrowGlyphTest.TestTriangleDegenerateRectIsSafe;
var
  pts: ArrayOfTPointF;
begin
  // The fit divides by the rect's height; a zero-size rect must collapse, not trap.
  pts := TyArrowTrianglePolygon(Rect(7, 9, 7, 9), tadUp, 60);
  AssertEquals('still 3 vertices', 3, Length(pts));
  AssertEquals('collapsed to the centre x', 7.0, pts[0].x, EPS);
  AssertEquals('collapsed to the centre y', 9.0, pts[0].y, EPS);
end;

initialization
  RegisterTest(TTyShapeHitTestTest);
  RegisterTest(TTyShapeGeometryTest);
  RegisterTest(TTyShapeHitProtocolTest);
  RegisterTest(TTyShapePaintAgreementTest);
  RegisterTest(TTyArrowGlyphTest);
end.
