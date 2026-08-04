unit test.parity.starshape;
{$mode objfpc}{$H+}
{ API-parity guards for tyControls.StarShape and for the TShapeType kinds
  tyControls.Shape did not have (lcl/extctrls.pp:266-269 + lcl/include/shape.inc).

  Three defects are pinned here:

    1. TTyStarShape hit-tested by its BOUNDING BOX -- the identical defect TTyShape
       had, and the worst case of it: a five-point star leaves five deep concave
       notches and four empty corners, and the control answered "mine" in all of them,
       so a control behind a star's points could never be clicked.
    2. Five of LCL's fifteen shape kinds had no equivalent at any property setting
       (the square-locked round rect and diamond, and the three non-upward triangles),
       and two more (stStar / stStarDown) were only reachable by swapping the
       COMPONENT CLASS -- with stStarDown not reachable at all, because TyStarPolygon
       always started at 12 o'clock.
    3. stPolygon + OnShapePoints -- TShape's extensibility escape hatch, the answer to
       every outline the enum does not name -- had no counterpart, so a hexagon or a
       callout meant writing a TTyGraphicControl descendant. }
interface
uses
  Classes, SysUtils, Types, TypInfo, Controls, Graphics, GraphType,
  fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Shape, tyControls.StarShape;

type
  { The runtime half: what LCL's ControlAtPos asks a control while routing a mouse
    message, driven exactly as wincontrol.inc:5239 drives it. }
  TTyStarHitTestTest = class(TTestCase)
  published
    procedure TestStarConcaveNotchFallsThrough;
    procedure TestStarPointIsStillHit;
    procedure TestStarCentreIsStillHit;
    procedure TestPtInShapeAgreesWithHitTest;
    procedure TestMaskHitTestFallsBackToSelectable;
  end;

  { The pure half: TyStarGeometry / TyPointInStar with no control, no theme and no
    painter, so the numbers are fixed rather than whatever the active skin resolves. }
  TTyStarGeometryTest = class(TTestCase)
  published
    procedure TestMarginAndStrokeInsetTheRing;
    procedure TestClampsAreAppliedInTheGeometry;
    procedure TestDegenerateRectIsNotValidAndHitsNothing;
    procedure TestTooSmallForTheMarginStillDraws;
    procedure TestStrokeBandWidensTheHitArea;
    procedure TestEveryOuterPointIsOnTheShape;
    procedure TestEveryNotchMidwayIsOff;
  end;

  { The star that LCL can draw and this library could not. }
  TTyStarPointDownTest = class(TTestCase)
  published
    procedure TestPointDownIsPublished;
    procedure TestPointDownFlipsTheRing;
    procedure TestPointDownMovesTheHitArea;
    procedure TestPointUpStaysTheDefault;
  end;

  { The whole point of routing paint and hit-test through one TTyStarGeometry: what is
    CLICKABLE and what is VISIBLE must be the same pixels. Asserted against the actual
    rendered ink, not against a second copy of the maths. }
  TTyStarPaintAgreementTest = class(TTestCase)
  published
    procedure TestInkAndHitAreaCoincide;
  end;

  { The five missing kinds, the two stars, and the app-supplied polygon. }
  TTyShapeKindTest = class(TTestCase)
  published
    procedure TestMissingShapeKindsExist;
    procedure TestExistingKindOrdinalsAreUnchanged;
    procedure TestSquareLockedKindsAreSquare;
    procedure TestRoundSquareIsRounded;
    procedure TestTrianglesPointFourWays;
    procedure TestStarKindsAreTheStarRing;
    procedure TestNewKindsHitTestTheirInk;
  end;

  TTyShapeEventTest = class(TTestCase)
  published
    procedure TestShapeEventsArePublished;
    procedure TestPolygonUsesTheSuppliedPoints;
    procedure TestPolygonWithNoHandlerHitsNothing;
    procedure TestShapeClickOnlyFiresOnTheInk;
  end;

implementation

const
  EPS = 0.001;

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

function MakeStar(AW, AH: Integer): TTyStarShape;
begin
  Result := TTyStarShape.Create(nil);
  Result.SetBounds(0, 0, AW, AH);
end;

{ 1px border, 2px margin — the library's common case. }
function Geom1px(AW, AH: Integer; APointDown: Boolean = False): TTyStarGeometry;
begin
  Result := TyStarGeometry(Rect(0, 0, AW, AH), 5, 0.42, APointDown, 1, 2, True);
end;

{ ---- TTyStarShape: shape-precise hit testing ---- }

procedure TTyStarHitTestTest.TestStarConcaveNotchFallsThrough;
var
  S: TTyStarShape;
begin
  // A 5-point star in a 200x200 box: the four corners of the box are far outside the
  // outer radius (100 about (100,100)), and the deep notches between the points are
  // empty canvas too. Before the fix the control answered "mine" at all of them.
  S := MakeStar(200, 200);
  try
    AssertEquals('star top-left corner falls through', 0, AskHitTest(S, 4, 4));
    AssertEquals('star top-right corner falls through', 0, AskHitTest(S, 196, 4));
    AssertEquals('star bottom-left corner falls through', 0, AskHitTest(S, 4, 196));
    AssertEquals('star bottom-right corner falls through', 0, AskHitTest(S, 196, 196));
  finally
    S.Free;
  end;
end;

procedure TTyStarHitTestTest.TestStarPointIsStillHit;
var
  S: TTyStarShape;
  G: TTyStarGeometry;
  poly: ArrayOfTPointF;
begin
  // Every OUTER vertex is ink and must stay clickable — a hit test that shrank to the
  // inner radius would also make every corner fall through and pass the test above.
  S := MakeStar(200, 200);
  try
    G := S.StarGeometry;
    poly := TyStarPolygon(G.Bounds, G.Points, G.InnerRatio, G.PointDown);
    AssertEquals('5-point star has 10 vertices', 10, Length(poly));
    AssertTrue('the top point is hit',
      AskHitTest(S, Round(poly[0].x), Round(poly[0].y) + 1) <> 0);
    AssertTrue('the lower-right point is hit',
      AskHitTest(S, Round(poly[2].x) - 1, Round(poly[2].y)) <> 0);
  finally
    S.Free;
  end;
end;

procedure TTyStarHitTestTest.TestStarCentreIsStillHit;
var
  S: TTyStarShape;
begin
  S := MakeStar(200, 200);
  try
    AssertTrue('star centre is still the control''s own click',
      AskHitTest(S, 100, 100) <> 0);
  finally
    S.Free;
  end;
end;

procedure TTyStarHitTestTest.TestPtInShapeAgreesWithHitTest;
var
  S: TTyStarShape;
begin
  // PtInShape is the public query; CM_HITTEST is the message. One must not be able to
  // say yes where the other says no.
  S := MakeStar(200, 200);
  try
    AssertEquals('corner: query and message agree',
      Ord(S.PtInShape(Point(4, 4))), Ord(AskHitTest(S, 4, 4) <> 0));
    AssertEquals('centre: query and message agree',
      Ord(S.PtInShape(Point(100, 100))), Ord(AskHitTest(S, 100, 100) <> 0));
  finally
    S.Free;
  end;
end;

procedure TTyStarHitTestTest.TestMaskHitTestFallsBackToSelectable;
var
  S: TTyStarShape;
  Msg: TCMHitTest;
begin
  // Outside a designer the message point cannot be translated. It must then answer
  // exactly as an unmasked TControl does — 0, selectable — never 1, which would make
  // the star unpickable in the form designer. NOTE the polarity is the INVERSE of
  // CM_HITTEST's, and it compiles just as happily backwards.
  S := MakeStar(200, 200);
  try
    FillChar(Msg, SizeOf(Msg), 0);
    Msg.Msg := CM_MASKHITTEST;
    Msg.XPos := 4;
    Msg.YPos := 4;
    Msg.Result := 99;
    S.Dispatch(Msg);
    AssertEquals('no designer form -> stays selectable', 0, Msg.Result);
  finally
    S.Free;
  end;
end;

{ ---- the pure geometry both the paint and the hit test read ---- }

procedure TTyStarGeometryTest.TestMarginAndStrokeInsetTheRing;
var
  G: TTyStarGeometry;
begin
  // margin 2 + ceil(1/2) = 3 per side. The ring's outer vertices sit ON Bounds' edge
  // and Canvas2D centres a stroke on its path, so without the half-stroke the border
  // would be cut off at the bitmap edge — and the hit band with it.
  G := TyStarGeometry(Rect(0, 0, 100, 100), 5, 0.42, False, 1, 2, True);
  AssertTrue('valid', G.Valid);
  AssertEquals('left inset by margin + ceil(bw/2)', 3, G.Bounds.Left);
  AssertEquals('right inset by margin + ceil(bw/2)', 97, G.Bounds.Right);
  // A fat border insets further, in step with the paint.
  G := TyStarGeometry(Rect(0, 0, 100, 100), 5, 0.42, False, 8, 2, True);
  AssertEquals('a fat stroke insets further', 6, G.Bounds.Left);
  // No border at all: the margin alone.
  G := TyStarGeometry(Rect(0, 0, 100, 100), 5, 0.42, False, 1, 2, False);
  AssertFalse('unstroked', G.Stroked);
  AssertEquals('margin only without a border', 2, G.Bounds.Left);
end;

procedure TTyStarGeometryTest.TestClampsAreAppliedInTheGeometry;
var
  G: TTyStarGeometry;
begin
  // The clamps have to live in the GEOMETRY, or a caller reaching TyStarGeometry
  // directly could produce a ring the control can never draw.
  G := TyStarGeometry(Rect(0, 0, 100, 100), 1, 9.9, False, 0, 2, True);
  AssertEquals('point count floored', TyStarMinPoints, G.Points);
  AssertEquals('inner ratio ceilinged', TyStarMaxInnerRatio, G.InnerRatio, EPS);
  AssertEquals('sub-pixel stroke still paints one pixel', 1, G.StrokeWidth);
  G := TyStarGeometry(Rect(0, 0, 100, 100), 9, -3, False, 1, 2, True);
  AssertEquals('inner ratio floored', TyStarMinInnerRatio, G.InnerRatio, EPS);
  AssertEquals('a legal point count is kept verbatim', 9, G.Points);
end;

procedure TTyStarGeometryTest.TestDegenerateRectIsNotValidAndHitsNothing;
var
  G: TTyStarGeometry;
begin
  G := TyStarGeometry(Rect(0, 0, 0, 0), 5, 0.42, False, 1, 2, True);
  AssertFalse('zero-size box is not valid', G.Valid);
  AssertFalse('and nothing lands on it', TyPointInStar(G, PointF(0, 0)));
end;

procedure TTyStarGeometryTest.TestTooSmallForTheMarginStillDraws;
var
  G: TTyStarGeometry;
begin
  // A control narrower than twice the margin must still show a star: the paint path has
  // always fallen back to the whole rect there, and the hit test reads the same record,
  // so it must fall back identically or a tiny star would be uncliackable.
  G := TyStarGeometry(Rect(0, 0, 6, 6), 5, 0.42, False, 4, 8, True);
  AssertTrue('a tiny star is still valid', G.Valid);
  AssertEquals('fell back to the whole rect', 0, G.Bounds.Left);
  AssertEquals('fell back to the whole rect', 6, G.Bounds.Right);
  AssertTrue('and its centre is on the shape', TyPointInStar(G, PointF(3, 3)));
end;

procedure TTyStarGeometryTest.TestStrokeBandWidensTheHitArea;
var
  thin, fat: TTyStarGeometry;
  poly: ArrayOfTPointF;
  probe: TPointF;
begin
  // The ink reaches half the stroke width beyond the ring, so the hit area has to as
  // well — otherwise a thick border is visibly clickable and analytically not.
  thin := TyStarGeometry(Rect(0, 0, 200, 200), 5, 0.42, False, 1, 2, True);
  fat  := TyStarGeometry(Rect(0, 0, 200, 200), 5, 0.42, False, 20, 2, True);
  poly := TyStarPolygon(fat.Bounds, fat.Points, fat.InnerRatio, fat.PointDown);
  // Straight up from the tip: outside the ring by 6px, inside a 20px stroke's band.
  probe := PointF(poly[0].x, poly[0].y - 6);
  AssertTrue('fat: the band reaches past the tip', TyPointInStar(fat, probe));
  // The same offset from the THIN star's own tip is outside its 1px band.
  poly := TyStarPolygon(thin.Bounds, thin.Points, thin.InnerRatio, thin.PointDown);
  AssertFalse('thin: 6px past the tip is empty canvas',
    TyPointInStar(thin, PointF(poly[0].x, poly[0].y - 6)));
end;

procedure TTyStarGeometryTest.TestEveryOuterPointIsOnTheShape;
var
  G: TTyStarGeometry;
  poly: ArrayOfTPointF;
  i: Integer;
begin
  // All ten vertices are on the outline, so all ten are ink under any stroke.
  G := Geom1px(240, 240);
  poly := TyStarPolygon(G.Bounds, G.Points, G.InnerRatio, G.PointDown);
  for i := 0 to High(poly) do
    AssertTrue(Format('vertex %d is on the shape', [i]), TyPointInStar(G, poly[i]));
end;

procedure TTyStarGeometryTest.TestEveryNotchMidwayIsOff;
var
  G: TTyStarGeometry;
  poly: ArrayOfTPointF;
  i: Integer;
  cx, cy, mx, my, ox, oy: Single;
begin
  { The five NOTCHES are the reason a bounding box is wrong. For each pair of adjacent
    outer points, the midpoint between them lies well outside the ring (the inner vertex
    between them is much closer to the centre), so it must not be hit. }
  G := Geom1px(240, 240);
  poly := TyStarPolygon(G.Bounds, G.Points, G.InnerRatio, G.PointDown);
  cx := (G.Bounds.Left + G.Bounds.Right) / 2;
  cy := (G.Bounds.Top + G.Bounds.Bottom) / 2;
  for i := 0 to 4 do
  begin
    ox := poly[i * 2].x;
    oy := poly[i * 2].y;
    mx := (ox + poly[((i + 1) mod 5) * 2].x) / 2;
    my := (oy + poly[((i + 1) mod 5) * 2].y) / 2;
    // Push a little further out from the centre so we are clear of the 1px stroke band.
    mx := cx + (mx - cx) * 1.05;
    my := cy + (my - cy) * 1.05;
    AssertFalse(Format('notch %d is empty canvas', [i]),
      TyPointInStar(G, PointF(mx, my)));
  end;
end;

{ ---- point-down ---- }

procedure TTyStarPointDownTest.TestPointDownIsPublished;
var
  S: TTyStarShape;
begin
  // LCL has stStarDown; this control had no rotation of any kind, so it was
  // unreachable at every property setting.
  S := TTyStarShape.Create(nil);
  try
    AssertTrue('PointDown is published', GetPropInfo(S, 'PointDown') <> nil);
  finally
    S.Free;
  end;
end;

procedure TTyStarPointDownTest.TestPointUpStaysTheDefault;
var
  S: TTyStarShape;
  poly: ArrayOfTPointF;
begin
  // Adding the flag must not re-draw a single existing form.
  S := TTyStarShape.Create(nil);
  try
    AssertFalse('PointDown defaults False', S.PointDown);
  finally
    S.Free;
  end;
  poly := TyStarPolygon(Rect(0, 0, 100, 100), 5, 0.42);
  AssertEquals('the 3-argument form still points UP: vertex 0 x', 50.0, poly[0].x, EPS);
  AssertEquals('the 3-argument form still points UP: vertex 0 y', 0.0, poly[0].y, EPS);
end;

procedure TTyStarPointDownTest.TestPointDownFlipsTheRing;
var
  up, down: ArrayOfTPointF;
begin
  up   := TyStarPolygon(Rect(0, 0, 100, 100), 5, 0.42, False);
  down := TyStarPolygon(Rect(0, 0, 100, 100), 5, 0.42, True);
  AssertEquals('same vertex count', Length(up), Length(down));
  AssertEquals('up: vertex 0 at 12 o''clock', 0.0, up[0].y, EPS);
  AssertEquals('down: vertex 0 at 6 o''clock', 100.0, down[0].y, EPS);
  AssertEquals('both on the vertical centre line', 50.0, down[0].x, EPS);
end;

procedure TTyStarPointDownTest.TestPointDownMovesTheHitArea;
var
  up, down: TTyStarGeometry;
  upTip, downTip: TPointF;
begin
  // The flag has to reach the HIT TEST, not only the paint: a point-down star that is
  // still clickable in the shape of a point-up one is the exact drift this record exists
  // to prevent. Sample each star's own tip against the OTHER's geometry.
  up := Geom1px(240, 240, False);
  down := Geom1px(240, 240, True);
  upTip := TyStarPolygon(up.Bounds, 5, 0.42, False)[0];
  downTip := TyStarPolygon(down.Bounds, 5, 0.42, True)[0];
  AssertTrue('the up star owns its own tip', TyPointInStar(up, upTip));
  AssertTrue('the down star owns its own tip', TyPointInStar(down, downTip));
  AssertFalse('the up star does not own the down star''s tip',
    TyPointInStar(up, downTip));
  AssertFalse('the down star does not own the up star''s tip',
    TyPointInStar(down, upTip));
end;

{ ---- paint vs hit area ---- }

type
  { RenderTo is protected on both controls; reach it the way test.badge.pas does. }
  TStarAccess = class(TTyStarShape)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TShapeAccess = class(TTyShape)
  public
    FClickPt: TPoint;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { Pin the click point instead of reading the live cursor: a headless guard must not
      have to move the USER's pointer to exercise OnShapeClick. }
    function ShapeClickPoint: TPoint; override;
  end;

procedure TStarAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TShapeAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TShapeAccess.ShapeClickPoint: TPoint;
begin
  Result := FClickPt;
end;

const
  INK_W = 90;
  INK_H = 70;

function IsInk(const APx: TBGRAPixel): Boolean;
begin
  Result := (APx.blue > 150) and (APx.red < 100);
end;

{ Render the star and count pixels where the ink and TyPointInStar disagree, IGNORING
  every pixel within one pixel of the analytic boundary — that is where anti-aliasing
  makes "inked" a matter of degree. A non-zero count means the painter and the hit test
  are working from different geometry. }
function StarInkHitDisagreements(ACtl: TTyStyleController;
  APointDown: Boolean): Integer;
var
  S: TStarAccess;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  G: TTyStarGeometry;
  x, y, dx, dy: Integer;
  hit, onBoundary: Boolean;
begin
  Result := 0;
  S := TStarAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    S.Controller := ACtl;
    S.Font.PixelsPerInch := 96;
    S.PointDown := APointDown;
    S.SetBounds(0, 0, INK_W, INK_H);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(INK_W, INK_H);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, INK_W, INK_H);
    S.RenderTo(Bmp.Canvas, Rect(0, 0, INK_W, INK_H), 96);

    G := S.StarGeometry;
    Img := TBGRABitmap.Create(Bmp);
    try
      for y := 1 to INK_H - 2 do
        for x := 1 to INK_W - 2 do
        begin
          hit := TyPointInStar(G, PointF(x + 0.5, y + 0.5));
          onBoundary := False;
          for dy := -1 to 1 do
            for dx := -1 to 1 do
              if TyPointInStar(G, PointF(x + dx + 0.5, y + dy + 0.5)) <> hit then
                onBoundary := True;
          if onBoundary then Continue;
          if IsInk(Img.GetPixel(x, y)) <> hit then Inc(Result);
        end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
    S.Free;
  end;
end;

procedure TTyStarPaintAgreementTest.TestInkAndHitAreaCoincide;
var
  Ctl: TTyStyleController;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // A fat border so the stroke BAND is a real part of the answer, not a rounding detail.
    Ctl.LoadThemeCss('TyStarShape { background: #3B82F6; border-color: #3B82F6; '
      + 'border-width: 3px; }');
    AssertEquals('point-up: ink and hit area coincide', 0,
      StarInkHitDisagreements(Ctl, False));
    AssertEquals('point-down: ink and hit area coincide', 0,
      StarInkHitDisagreements(Ctl, True));
  finally
    Ctl.Free;
  end;
end;

{ ---- the shape kinds LCL had and we did not ---- }

procedure TTyShapeKindTest.TestMissingShapeKindsExist;
begin
  // extctrls.pp:266-269 lists fifteen; we had eight. These are the seven names a .lfm
  // converted from TShape can carry, plus stPolygon's counterpart.
  AssertTrue('tskRoundSquare',
    GetEnumValue(TypeInfo(TTyShapeKind), 'tskRoundSquare') >= 0);
  AssertTrue('tskSquaredDiamond',
    GetEnumValue(TypeInfo(TTyShapeKind), 'tskSquaredDiamond') >= 0);
  AssertTrue('tskTriangleLeft',
    GetEnumValue(TypeInfo(TTyShapeKind), 'tskTriangleLeft') >= 0);
  AssertTrue('tskTriangleRight',
    GetEnumValue(TypeInfo(TTyShapeKind), 'tskTriangleRight') >= 0);
  AssertTrue('tskTriangleDown',
    GetEnumValue(TypeInfo(TTyShapeKind), 'tskTriangleDown') >= 0);
  AssertTrue('tskStar', GetEnumValue(TypeInfo(TTyShapeKind), 'tskStar') >= 0);
  AssertTrue('tskStarDown', GetEnumValue(TypeInfo(TTyShapeKind), 'tskStarDown') >= 0);
  AssertTrue('tskPolygon', GetEnumValue(TypeInfo(TTyShapeKind), 'tskPolygon') >= 0);
end;

procedure TTyShapeKindTest.TestExistingKindOrdinalsAreUnchanged;
begin
  { The new names had to be APPENDED, not slotted in next to their relatives. A .lfm
    stores the identifier, but a designer, a saved integer property or any code holding
    Ord() does not — inserting tskTriangleLeft after tskTriangle would have silently
    re-shaped every existing form. }
  AssertEquals('tskRectangle', 0, Ord(tskRectangle));
  AssertEquals('tskRoundRect', 1, Ord(tskRoundRect));
  AssertEquals('tskSquare', 2, Ord(tskSquare));
  AssertEquals('tskEllipse', 3, Ord(tskEllipse));
  AssertEquals('tskCircle', 4, Ord(tskCircle));
  AssertEquals('tskTriangle', 5, Ord(tskTriangle));
  AssertEquals('tskDiamond', 6, Ord(tskDiamond));
  AssertEquals('tskLine', 7, Ord(tskLine));
  AssertTrue('every addition sits above them', Ord(tskRoundSquare) > Ord(tskLine));
end;

procedure TTyShapeKindTest.TestSquareLockedKindsAreSquare;
var
  G: TTyShapeGeometry;
begin
  // shape.inc:93 locks stSquare, stRoundSquare, stCircle and stSquaredDiamond to the
  // largest centred square. We had the first and third only.
  G := TyShapeGeometry(tskRoundSquare, Rect(0, 0, 200, 100), 1, 0, True);
  AssertEquals('round square is square', G.Bounds.Right - G.Bounds.Left,
    G.Bounds.Bottom - G.Bounds.Top);
  AssertEquals('and centred', 51, G.Bounds.Left);
  G := TyShapeGeometry(tskSquaredDiamond, Rect(0, 0, 200, 100), 1, 0, True);
  AssertEquals('squared diamond is square', G.Bounds.Right - G.Bounds.Left,
    G.Bounds.Bottom - G.Bounds.Top);
  // ...and the plain diamond is NOT, which is the whole difference between them.
  G := TyShapeGeometry(tskDiamond, Rect(0, 0, 200, 100), 1, 0, True);
  AssertEquals('a plain diamond keeps the full width', 198,
    G.Bounds.Right - G.Bounds.Left);
end;

procedure TTyShapeKindTest.TestRoundSquareIsRounded;
var
  G: TTyShapeGeometry;
begin
  // A round square with no radius would just be a square: the kind has to reach the
  // radius branch as well as the square-lock one.
  G := TyShapeGeometry(tskRoundSquare, Rect(0, 0, 100, 100), 1, 20, True);
  AssertEquals('radius honoured', 20.0, G.Radius, EPS);
  AssertFalse('the rounded-away corner is not on the shape',
    TyPointInShape(G, PointF(3, 3)));
  AssertTrue('the edge midpoint is', TyPointInShape(G, PointF(50, 1.2)));
end;

procedure TTyShapeKindTest.TestTrianglesPointFourWays;
var
  R: TRect;
  up, dn, lf, rt: ArrayOfTPointF;
begin
  R := Rect(0, 0, 200, 100);
  up := TyShapePolygon(tskTriangle, R);
  dn := TyShapePolygon(tskTriangleDown, R);
  lf := TyShapePolygon(tskTriangleLeft, R);
  rt := TyShapePolygon(tskTriangleRight, R);
  AssertEquals('up has 3 vertices', 3, Length(up));
  AssertEquals('down has 3 vertices', 3, Length(dn));
  AssertEquals('left has 3 vertices', 3, Length(lf));
  AssertEquals('right has 3 vertices', 3, Length(rt));
  // Apex position is the whole difference between the four.
  AssertEquals('up apex at the top-centre', 0.0, up[0].y, EPS);
  AssertEquals('up apex at the top-centre', 100.0, up[0].x, EPS);
  AssertEquals('down apex at the bottom-centre', 100.0, dn[0].y, EPS);
  AssertEquals('down apex at the bottom-centre', 100.0, dn[0].x, EPS);
  AssertEquals('left apex on the left edge', 0.0, lf[0].x, EPS);
  AssertEquals('left apex on the left edge', 50.0, lf[0].y, EPS);
  AssertEquals('right apex on the right edge', 200.0, rt[0].x, EPS);
  AssertEquals('right apex on the right edge', 50.0, rt[0].y, EPS);
end;

procedure TTyShapeKindTest.TestStarKindsAreTheStarRing;
var
  up, dn, ring: ArrayOfTPointF;
  i: Integer;
begin
  // tskStar must be the SAME ring TTyStarShape draws, not a second star. A second
  // implementation is a second thing to get wrong, and the two would drift.
  up := TyShapePolygon(tskStar, Rect(0, 0, 200, 200));
  dn := TyShapePolygon(tskStarDown, Rect(0, 0, 200, 200));
  ring := TyStarRingPolygon(Rect(0, 0, 200, 200), TyShapeStarPoints,
    TyShapeStarInnerRatio, False);
  AssertEquals('5 points = 10 vertices', 10, Length(up));
  AssertEquals('5 points = 10 vertices', 10, Length(dn));
  for i := 0 to High(up) do
  begin
    AssertEquals(Format('vertex %d x is the shared ring''s', [i]),
      ring[i].x, up[i].x, EPS);
    AssertEquals(Format('vertex %d y is the shared ring''s', [i]),
      ring[i].y, up[i].y, EPS);
  end;
  AssertEquals('up points at 12 o''clock', 0.0, up[0].y, EPS);
  AssertEquals('down points at 6 o''clock', 200.0, dn[0].y, EPS);
end;

procedure TTyShapeKindTest.TestNewKindsHitTestTheirInk;
var
  G: TTyShapeGeometry;
begin
  // The kinds are only useful if the hit test knows them too — a new enum value that
  // fell through to the rectangle branch would claim its whole box.
  G := TyShapeGeometry(tskTriangleRight, Rect(0, 0, 200, 100), 1, 0, True);
  AssertTrue('right triangle: the apex end of the axis', TyPointInShape(G, PointF(180, 50)));
  AssertFalse('right triangle: the top-RIGHT corner is empty',
    TyPointInShape(G, PointF(190, 5)));
  AssertTrue('right triangle: the top-LEFT corner is on the base',
    TyPointInShape(G, PointF(4, 4)));

  G := TyShapeGeometry(tskTriangleDown, Rect(0, 0, 200, 100), 1, 0, True);
  AssertFalse('down triangle: the bottom-left corner is empty',
    TyPointInShape(G, PointF(5, 95)));
  AssertTrue('down triangle: the top-left corner is on the base',
    TyPointInShape(G, PointF(4, 4)));

  G := TyShapeGeometry(tskStar, Rect(0, 0, 200, 200), 1, 0, True);
  AssertTrue('star: the centre', TyPointInShape(G, PointF(100, 100)));
  AssertFalse('star: the box corner is empty', TyPointInShape(G, PointF(5, 5)));

  G := TyShapeGeometry(tskSquaredDiamond, Rect(0, 0, 200, 100), 1, 0, True);
  AssertTrue('squared diamond: the centre', TyPointInShape(G, PointF(100, 50)));
  AssertFalse('squared diamond: the box corner is empty',
    TyPointInShape(G, PointF(55, 5)));
end;

{ ---- OnShapePoints / OnShapeClick ---- }

type
  { Hands back a fixed hexagon and counts how often it was asked. }
  TPolygonSource = class
  public
    Calls: Integer;
    Bounds: TRect;
    procedure Supply(Sender: TObject; var Points: TPointArray; var Winding: Boolean);
  end;

  TClickCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

procedure TPolygonSource.Supply(Sender: TObject; var Points: TPointArray;
  var Winding: Boolean);
begin
  Inc(Calls);
  // A chevron: an outline the enum genuinely cannot name, so a pass here cannot be an
  // accident of some built-in kind having the same shape.
  SetLength(Points, 6);
  Points[0] := Point(Bounds.Left, Bounds.Top);
  Points[1] := Point(Bounds.Left + (Bounds.Right - Bounds.Left) div 2, Bounds.Top);
  Points[2] := Point(Bounds.Right, (Bounds.Top + Bounds.Bottom) div 2);
  Points[3] := Point(Bounds.Left + (Bounds.Right - Bounds.Left) div 2, Bounds.Bottom);
  Points[4] := Point(Bounds.Left, Bounds.Bottom);
  Points[5] := Point(Bounds.Left + (Bounds.Right - Bounds.Left) div 4,
                     (Bounds.Top + Bounds.Bottom) div 2);
  Winding := True;
end;

procedure TClickCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

procedure TTyShapeEventTest.TestShapeEventsArePublished;
var
  Sh: TTyShape;
begin
  Sh := TTyShape.Create(nil);
  try
    AssertTrue('OnShapeClick is published', GetPropInfo(Sh, 'OnShapeClick') <> nil);
    AssertTrue('OnShapePoints is published', GetPropInfo(Sh, 'OnShapePoints') <> nil);
  finally
    Sh.Free;
  end;
end;

procedure TTyShapeEventTest.TestPolygonUsesTheSuppliedPoints;
var
  Sh: TTyShape;
  Src: TPolygonSource;
  G: TTyShapeGeometry;
begin
  Sh := TTyShape.Create(nil);
  Src := TPolygonSource.Create;
  try
    Sh.SetBounds(0, 0, 200, 100);
    Sh.Shape := tskPolygon;
    Src.Bounds := Rect(0, 0, 200, 100);
    Sh.OnShapePoints := @Src.Supply;
    G := Sh.ShapeGeometry;
    AssertTrue('the handler was asked', Src.Calls > 0);
    AssertEquals('the vertices travelled on the geometry record', 6, Length(G.Polygon));
    AssertTrue('the winding flag travelled too', G.Winding);
    // The chevron's notch: inside the bounding box, outside the outline.
    AssertFalse('the chevron notch is not on the shape',
      TyPointInShape(G, PointF(8, 50)));
    // ...and the body of the chevron is.
    AssertTrue('the chevron body is', TyPointInShape(G, PointF(100, 20)));
  finally
    Src.Free;
    Sh.Free;
  end;
end;

procedure TTyShapeEventTest.TestPolygonWithNoHandlerHitsNothing;
var
  Sh: TTyShape;
begin
  // No handler = no outline = no ink. A tskPolygon that claimed its rectangle would be
  // the very bounding-box bug this whole hit test exists to remove.
  Sh := TTyShape.Create(nil);
  try
    Sh.SetBounds(0, 0, 200, 100);
    Sh.Shape := tskPolygon;
    AssertEquals('nothing supplied, nothing hit', 0, AskHitTest(Sh, 100, 50));
  finally
    Sh.Free;
  end;
end;

procedure TTyShapeEventTest.TestShapeClickOnlyFiresOnTheInk;
var
  Sh: TShapeAccess;
  C: TClickCounter;
begin
  // shape.inc:305-310 — OnShapeClick fires only when the pointer is on the drawn shape.
  Sh := TShapeAccess.Create(nil);
  C := TClickCounter.Create;
  try
    Sh.SetBounds(0, 0, 200, 200);
    Sh.Shape := tskCircle;
    Sh.OnShapeClick := @C.Handle;

    Sh.FClickPt := Point(3, 3);      // the circle's empty corner
    Sh.Click;
    AssertEquals('a click in the empty corner does not fire it', 0, C.Count);

    Sh.FClickPt := Point(100, 100);  // dead centre
    Sh.Click;
    AssertEquals('a click on the ink does', 1, C.Count);
  finally
    C.Free;
    Sh.Free;
  end;
end;

initialization
  RegisterTest(TTyStarHitTestTest);
  RegisterTest(TTyStarGeometryTest);
  RegisterTest(TTyStarPointDownTest);
  RegisterTest(TTyStarPaintAgreementTest);
  RegisterTest(TTyShapeKindTest);
  RegisterTest(TTyShapeEventTest);
end.
