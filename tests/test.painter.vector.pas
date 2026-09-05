unit test.painter.vector;
{$mode objfpc}{$H+}
{ Headless tests for TTyPainter's VECTOR PATH API (Tier 0 item 2).

  These pin the eight contract points in
  docs/superpowers/plans/2026-09-01-painter-vector-api.md §3 — the places where
  the API must behave one way and not the other. Shape coverage (does LineTo draw
  a line) matters far less than those, because a wrong answer there is visible
  immediately, whereas a clip that silently ignores the transform, or a dash
  measured in device px, only shows up on someone else's monitor.

  Same headless harness as test.painter.pas: a plain TBitmap for the canvas,
  BeginPaint, draw, then read pixels back off the painter's own BGRA bitmap. }
interface
uses
  Classes, SysUtils, Types, Math, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter;
type
  TPainterVectorTest = class(TTestCase)
  private
    FHost: TBitmap;
    FPainter: TTyPainter;
    function MakePainter(AWidth, AHeight, APPI: Integer): TRect;
    procedure FreePainter;
    function PixelAt(X, Y: Integer): TBGRAPixel;
    function AlphaAt(X, Y: Integer): Integer;
    function Opaque(X, Y: Integer): Boolean;
    { Number of transparent -> opaque transitions along a row. Counts dash
      segments without depending on where the first one happens to start. }
    function InkRunsAlongRow(AY, AX0, AX1: Integer): Integer;
    { Bounding box of everything with any alpha. Returns False when nothing was
      drawn at all, which is itself a result worth asserting. }
    function InkBounds(out AL, AT, AR, AB: Integer): Boolean;
  protected
    procedure TearDown; override;
  published
    { ---- units ---- }
    procedure TestScaleFIsFractionalWhereScaleRounds;
    procedure TestScaleFIsIdentityAt96;
    { ---- filling ---- }
    procedure TestFillPathFillsTheInterior;
    procedure TestFillPathLeavesTheOutsideUntouched;
    procedure TestEvenOddLeavesTheRingHole;
    procedure TestNonZeroFillsTheRingHole;
    procedure TestFillPathWithGradientVariesAcrossTheBounds;
    { ---- stroking ---- }
    procedure TestStrokeDrawsOnTheOutline;
    procedure TestZeroWidthStrokeDrawsNothing;
    procedure TestNegativeWidthStrokeDrawsNothing;
    procedure TestZeroWidthStrokeWithADashDoesNotDivideByZero;
    procedure TestDashLengthIsLogicalNotDevice;
    procedure TestEmptyDashRestoresASolidLine;
    procedure TestSquareCapExtendsPastTheEndpoint;
    { ---- state, transform, clip, alpha ---- }
    procedure TestClipRectHonoursTheCurrentTransform;
    procedure TestRestoreStateRestoresTheClip;
    procedure TestRestoreStateRestoresTheDash;
    procedure TestRestoreStateRestoresElementAlpha;
    procedure TestElementAlphaDimsTheFill;
    procedure TestPathContainsRespectsTheTransform;
    procedure TestTheHitTestUsesTheRuleItWasGiven;
    { ---- paths ---- }
    procedure TestPolylineToDrawsEverySegment;
    procedure TestRoundRectPathClampsAnOversizeRadius;
    procedure TestRoundRectRadiusIsLogicalPx;
    procedure TestSvgPathInFitsInsideTheRect;
    procedure TestSvgPathInIsCentred;
    { ---- rotated text ---- }
    procedure TestRotatedTextAtZeroMatchesUnrotated;
    procedure TestRotatedTextFullTurnMatchesZero;
    procedure TestRotatedTextQuarterTurnIsTaller;
    procedure TestRotatedTextPositiveAngleRunsCounterClockwise;
  end;

implementation

const
  Red   = TTyColor($FFFF0000);
  Blue  = TTyColor($FF0000FF);
  Black = TTyColor($FF000000);

function TPainterVectorTest.MakePainter(AWidth, AHeight, APPI: Integer): TRect;
begin
  FHost := TBitmap.Create;
  FHost.SetSize(AWidth, AHeight);
  Result := Rect(0, 0, AWidth, AHeight);
  FPainter := TTyPainter.Create;
  FPainter.BeginPaint(FHost.Canvas, Result, APPI);
end;

procedure TPainterVectorTest.FreePainter;
begin
  FreeAndNil(FPainter);
  FreeAndNil(FHost);
end;

procedure TPainterVectorTest.TearDown;
begin
  FreePainter;
  inherited TearDown;
end;

function TPainterVectorTest.PixelAt(X, Y: Integer): TBGRAPixel;
begin
  Result := FPainter.Bitmap.GetPixel(X, Y);
end;

function TPainterVectorTest.AlphaAt(X, Y: Integer): Integer;
begin
  Result := PixelAt(X, Y).alpha;
end;

function TPainterVectorTest.Opaque(X, Y: Integer): Boolean;
begin
  { Antialiasing puts partial alpha all along an edge, so "has ink" has to mean
    substantially covered, not merely non-zero. }
  Result := AlphaAt(X, Y) > 200;
end;

function TPainterVectorTest.InkRunsAlongRow(AY, AX0, AX1: Integer): Integer;
var
  x: Integer;
  wasIn, isIn: Boolean;
begin
  Result := 0;
  wasIn := False;
  for x := AX0 to AX1 do
  begin
    isIn := AlphaAt(x, AY) > 128;
    if isIn and not wasIn then
      Inc(Result);
    wasIn := isIn;
  end;
end;

function TPainterVectorTest.InkBounds(out AL, AT, AR, AB: Integer): Boolean;
var
  x, y: Integer;
begin
  AL := MaxInt; AT := MaxInt; AR := -1; AB := -1;
  Result := False;
  for y := 0 to FPainter.Bitmap.Height - 1 do
    for x := 0 to FPainter.Bitmap.Width - 1 do
      if AlphaAt(x, y) > 16 then
      begin
        Result := True;
        if x < AL then AL := x;
        if x > AR then AR := x;
        if y < AT then AT := y;
        if y > AB then AB := y;
      end;
end;

{ ============================ units ============================ }

procedure TPainterVectorTest.TestScaleFIsFractionalWhereScaleRounds;
begin
  MakePainter(20, 20, 144);
  { The whole reason ScaleF exists: at 150 % a 1 px hairline is 1.5 device px.
    The integer Scale() has to round it to 2, which is 33 % too heavy. }
  AssertEquals('integer Scale rounds', 2, FPainter.Scale(1));
  AssertEquals('ScaleF does not', 1.5, FPainter.ScaleF(1), 1e-9);
  AssertEquals('and it is linear', 6.0, FPainter.ScaleF(4), 1e-9);
end;

procedure TPainterVectorTest.TestScaleFIsIdentityAt96;
begin
  MakePainter(20, 20, 96);
  AssertEquals('96 dpi is 1:1', 7.0, FPainter.ScaleF(7), 1e-9);
end;

{ ============================ filling ============================ }

procedure TPainterVectorTest.TestFillPathFillsTheInterior;
begin
  MakePainter(60, 60, 96);
  FPainter.BeginPath;
  FPainter.RectPath(10, 10, 50, 50);
  FPainter.FillPath(Red);
  AssertTrue('centre is filled', Opaque(30, 30));
  AssertEquals('and it is the colour asked for', 255, PixelAt(30, 30).red);
  AssertEquals('with no blue in it', 0, PixelAt(30, 30).blue);
end;

procedure TPainterVectorTest.TestFillPathLeavesTheOutsideUntouched;
begin
  MakePainter(60, 60, 96);
  FPainter.BeginPath;
  FPainter.RectPath(20, 20, 40, 40);
  FPainter.FillPath(Red);
  AssertEquals('outside stays transparent', 0, AlphaAt(5, 5));
  AssertEquals('and so does the far corner', 0, AlphaAt(55, 55));
end;

procedure TPainterVectorTest.TestEvenOddLeavesTheRingHole;
begin
  MakePainter(100, 100, 96);
  { Two contours wound the SAME way. Even-odd is the rule that gives a ring its
    hole regardless of winding -- a donut, a sunburst band. Explicit arcs rather
    than CirclePath so the winding is not left to BGRA's choice. }
  FPainter.BeginPath;
  FPainter.MoveTo(50 + 40, 50);
  FPainter.ArcTo(50, 50, 40, 0, 2 * Pi, False);
  FPainter.ClosePath;
  FPainter.MoveTo(50 + 20, 50);
  FPainter.ArcTo(50, 50, 20, 0, 2 * Pi, False);
  FPainter.ClosePath;
  FPainter.FillPath(Red, tfrEvenOdd);
  AssertTrue('the band is filled', Opaque(50, 50 - 30));
  AssertEquals('and the hole is empty', 0, AlphaAt(50, 50));
end;

procedure TPainterVectorTest.TestNonZeroFillsTheRingHole;
begin
  MakePainter(100, 100, 96);
  FPainter.BeginPath;
  FPainter.MoveTo(50 + 40, 50);
  FPainter.ArcTo(50, 50, 40, 0, 2 * Pi, False);
  FPainter.ClosePath;
  FPainter.MoveTo(50 + 20, 50);
  FPainter.ArcTo(50, 50, 20, 0, 2 * Pi, False);
  FPainter.ClosePath;
  FPainter.FillPath(Red, tfrNonZero);
  AssertTrue('the band is filled', Opaque(50, 50 - 30));
  { Same winding both ways, so non-zero counts 2 and fills straight through.
    This is the assertion that makes the even-odd one mean something. }
  AssertTrue('and non-zero fills the hole in', Opaque(50, 50));
end;

procedure TPainterVectorTest.TestFillPathWithGradientVariesAcrossTheBounds;
var
  f: TTyFill;
  leftPix, rightPix: TBGRAPixel;
begin
  MakePainter(100, 40, 96);
  FillChar(f, SizeOf(f), 0);
  f.Kind := tfkLinearGradient;
  f.GradFrom := TTyColor($FF000000);
  f.GradTo := TTyColor($FFFFFFFF);
  f.GradAngleDeg := 0;                 // left to right
  FPainter.BeginPath;
  FPainter.RectPath(0, 0, 100, 40);
  FPainter.FillPathWith(f, Rect(0, 0, 100, 40));
  leftPix := PixelAt(5, 20);
  rightPix := PixelAt(94, 20);
  AssertTrue('both ends are painted',
             (leftPix.alpha > 200) and (rightPix.alpha > 200));
  AssertTrue('and the gradient actually runs across the bounds',
             rightPix.red > leftPix.red + 100);
end;

{ ============================ stroking ============================ }

procedure TPainterVectorTest.TestStrokeDrawsOnTheOutline;
begin
  MakePainter(60, 60, 96);
  FPainter.BeginPath;
  FPainter.RectPath(20, 20, 40, 40);
  FPainter.StrokePath(Red, 4);
  AssertTrue('ink on the top edge', Opaque(30, 20));
  AssertEquals('and none in the middle', 0, AlphaAt(30, 30));
end;

procedure TPainterVectorTest.TestZeroWidthStrokeDrawsNothing;
var l, t, r, b: Integer;
begin
  MakePainter(60, 60, 96);
  FPainter.BeginPath;
  FPainter.RectPath(20, 20, 40, 40);
  FPainter.StrokePath(Red, 0);
  { A theme that sets border-width 0 means NO border. Falling through to BGRA's
    default width would draw a hairline everywhere it was switched off. }
  AssertFalse('nothing was drawn at all', InkBounds(l, t, r, b));
end;

procedure TPainterVectorTest.TestNegativeWidthStrokeDrawsNothing;
var l, t, r, b: Integer;
begin
  MakePainter(60, 60, 96);
  FPainter.BeginPath;
  FPainter.RectPath(20, 20, 40, 40);
  FPainter.StrokePath(Red, -3);
  AssertFalse('a negative width is not an absolute value', InkBounds(l, t, r, b));
end;

procedure TPainterVectorTest.TestZeroWidthStrokeWithADashDoesNotDivideByZero;
var
  l, t, r, bo: Integer;
begin
  { The zero-width guard is not only about drawing nothing -- BGRA would draw
    nothing at width 0 anyway. It is load-bearing because the dash conversion
    divides BY the device width (a pen pattern is in multiples of it). Reach
    that division with a zero width and it is a divide by zero, which a test
    that only checks "no ink" walks straight past. Found by mutation: relaxing
    the guard to `w < 0` left every other test green. }
  MakePainter(80, 20, 96);
  FPainter.SetLineDash([6, 6]);
  FPainter.BeginPath;
  FPainter.MoveTo(10, 10);
  FPainter.LineTo(70, 10);
  FPainter.StrokePath(Red, 0);
  AssertFalse('nothing drawn, and nothing raised', InkBounds(l, t, r, bo));
end;

procedure TPainterVectorTest.TestDashLengthIsLogicalNotDevice;
var
  runsAt96, runsAt192: Integer;
begin
  { A [6,6] dash over the same 240 DEVICE px line: at 96 dpi the segments are 6
    device px, at 192 dpi they are 12, so twice the PPI must halve the count.
    Measure dashes in device px instead and a high-DPI chart's dashed gridlines
    shatter into dots. }
  MakePainter(260, 20, 96);
  FPainter.SetLineDash([6, 6]);
  FPainter.BeginPath;
  FPainter.MoveTo(10, 10);
  FPainter.LineTo(250, 10);
  FPainter.StrokePath(Red, 3);
  runsAt96 := InkRunsAlongRow(10, 0, 259);
  FreePainter;

  MakePainter(260, 20, 192);
  FPainter.SetLineDash([6, 6]);
  FPainter.BeginPath;
  FPainter.MoveTo(10, 10);
  FPainter.LineTo(250, 10);
  FPainter.StrokePath(Red, 3);
  runsAt192 := InkRunsAlongRow(10, 0, 259);

  AssertTrue('the 96 dpi line really is dashed (got ' + IntToStr(runsAt96) + ')',
             runsAt96 >= 6);
  AssertTrue('doubling the PPI roughly halves the segment count'
             + ' (96dpi=' + IntToStr(runsAt96) + ' 192dpi=' + IntToStr(runsAt192) + ')',
             (runsAt192 * 2 >= runsAt96 - 2) and (runsAt192 * 2 <= runsAt96 + 2));
end;

procedure TPainterVectorTest.TestEmptyDashRestoresASolidLine;
begin
  { The canvas state is shared across calls, so a dash set for one element would
    otherwise still be in force for the next one. }
  MakePainter(260, 20, 96);
  FPainter.SetLineDash([6, 6]);
  FPainter.SetLineDash([]);
  FPainter.BeginPath;
  FPainter.MoveTo(10, 10);
  FPainter.LineTo(250, 10);
  FPainter.StrokePath(Red, 3);
  AssertEquals('one unbroken run', 1, InkRunsAlongRow(10, 0, 259));
end;

procedure TPainterVectorTest.TestSquareCapExtendsPastTheEndpoint;
var
  buttRight, squareRight: Integer;
  l, t, b: Integer;
begin
  MakePainter(80, 20, 96);
  FPainter.SetLineCap(tlcButt);
  FPainter.BeginPath;
  FPainter.MoveTo(20, 10);
  FPainter.LineTo(60, 10);
  FPainter.StrokePath(Red, 8);
  InkBounds(l, t, buttRight, b);
  FreePainter;

  MakePainter(80, 20, 96);
  FPainter.SetLineCap(tlcSquare);
  FPainter.BeginPath;
  FPainter.MoveTo(20, 10);
  FPainter.LineTo(60, 10);
  FPainter.StrokePath(Red, 8);
  InkBounds(l, t, squareRight, b);

  AssertTrue('a square cap reaches further than a butt cap'
             + ' (butt=' + IntToStr(buttRight) + ' square=' + IntToStr(squareRight) + ')',
             squareRight > buttRight);
end;

{ ==================== state, transform, clip, alpha ==================== }

procedure TPainterVectorTest.TestClipRectHonoursTheCurrentTransform;
begin
  MakePainter(120, 60, 96);
  FPainter.SaveState;
  FPainter.Translate(50, 0);
  { The clip is authored at 0..20 but the matrix moves it to 50..70. Built as a
    region rather than a path, it would cut at 0..20 and the fill below would
    come out in the wrong place entirely. }
  FPainter.ClipRect(Rect(0, 0, 20, 60));
  FPainter.BeginPath;
  FPainter.RectPath(-100, 0, 200, 60);
  FPainter.FillPath(Red);
  FPainter.RestoreState;
  AssertTrue('ink inside the TRANSFORMED clip', Opaque(60, 30));
  AssertEquals('none where the clip was authored', 0, AlphaAt(10, 30));
  AssertEquals('and none past its far edge', 0, AlphaAt(100, 30));
end;

procedure TPainterVectorTest.TestRestoreStateRestoresTheClip;
begin
  MakePainter(120, 60, 96);
  FPainter.SaveState;
  FPainter.ClipRect(Rect(0, 0, 20, 60));
  FPainter.RestoreState;
  FPainter.BeginPath;
  FPainter.RectPath(0, 0, 120, 60);
  FPainter.FillPath(Red);
  AssertTrue('the clip is gone after restore', Opaque(100, 30));
end;

procedure TPainterVectorTest.TestRestoreStateRestoresTheDash;
begin
  MakePainter(260, 20, 96);
  FPainter.SaveState;
  FPainter.SetLineDash([6, 6]);
  FPainter.RestoreState;
  FPainter.BeginPath;
  FPainter.MoveTo(10, 10);
  FPainter.LineTo(250, 10);
  FPainter.StrokePath(Red, 3);
  AssertEquals('the dash did not survive the restore', 1, InkRunsAlongRow(10, 0, 259));
end;

procedure TPainterVectorTest.TestRestoreStateRestoresElementAlpha;
begin
  MakePainter(60, 60, 96);
  FPainter.SaveState;
  FPainter.SetElementAlpha(0.25);
  FPainter.RestoreState;
  FPainter.BeginPath;
  FPainter.RectPath(10, 10, 50, 50);
  FPainter.FillPath(Red);
  AssertTrue('full alpha again after restore, got ' + IntToStr(AlphaAt(30, 30)),
             AlphaAt(30, 30) > 250);
end;

procedure TPainterVectorTest.TestElementAlphaDimsTheFill;
var a: Integer;
begin
  MakePainter(60, 60, 96);
  FPainter.SetElementAlpha(0.5);
  FPainter.BeginPath;
  FPainter.RectPath(10, 10, 50, 50);
  FPainter.FillPath(Red);
  a := AlphaAt(30, 30);
  AssertTrue('roughly half alpha, got ' + IntToStr(a), (a > 100) and (a < 160));
end;

procedure TPainterVectorTest.TestPathContainsRespectsTheTransform;
begin
  MakePainter(120, 60, 96);
  FPainter.SaveState;
  FPainter.Translate(50, 0);
  FPainter.BeginPath;
  FPainter.RectPath(0, 0, 20, 60);
  { Paint and hit-test share one path -- the TTySegmented rule. If the transform
    applied to the drawing but not to the query, the pointer would report a
    datum fifty pixels from the one that was drawn. }
  AssertTrue('a point inside the TRANSFORMED path', FPainter.PathContains(60, 30));
  AssertFalse('and not one where it was authored', FPainter.PathContains(10, 30));
  FPainter.RestoreState;
end;

{ ============================ paths ============================ }

procedure TPainterVectorTest.TestPolylineToDrawsEverySegment;
begin
  MakePainter(120, 60, 96);
  FPainter.BeginPath;
  FPainter.MoveTo(10, 30);
  FPainter.PolylineTo([TyVecPoint(40, 30), TyVecPoint(70, 30), TyVecPoint(100, 30)]);
  FPainter.StrokePath(Red, 5);
  AssertTrue('first segment', Opaque(25, 30));
  AssertTrue('second segment', Opaque(55, 30));
  AssertTrue('third segment', Opaque(85, 30));
end;

procedure TPainterVectorTest.TestRoundRectPathClampsAnOversizeRadius;
var l, t, r, b: Integer;
begin
  MakePainter(80, 40, 96);
  FPainter.BeginPath;
  { A radius larger than half the box makes BGRA draw a lens rather than a pill.
    Clamped, this is a 40x20 box with 20-px round ends -- a stadium. }
  FPainter.RoundRectPath(20, 10, 60, 30, 999);
  FPainter.FillPath(Red);
  AssertTrue('there is ink', InkBounds(l, t, r, b));
  AssertTrue('it did not spill outside the box', (l >= 19) and (r <= 61));
  AssertTrue('and it still fills the middle', Opaque(40, 20));
end;

procedure TPainterVectorTest.TestRoundRectRadiusIsLogicalPx;
var
  at96, at192: Boolean;
begin
  { The corner radius comes from a theme token, so it is LOGICAL px and must
    grow with the PPI. On a 100x100 box a corner of radius r leaves the diagonal
    point (p,p) filled only when p >= 0.293*r, so (4,4) is inside a 10 px corner
    and outside a 20 px one -- which is the same logical 10 at 96 and at 192 dpi.
    Found missing by mutation: nothing else here varies the PPI on a radius. }
  MakePainter(100, 100, 96);
  FPainter.BeginPath;
  FPainter.RoundRectPath(0, 0, 100, 100, 10);
  FPainter.FillPath(Red);
  at96 := Opaque(4, 4);
  FreePainter;

  MakePainter(100, 100, 192);
  FPainter.BeginPath;
  FPainter.RoundRectPath(0, 0, 100, 100, 10);
  FPainter.FillPath(Red);
  at192 := Opaque(4, 4);

  AssertTrue('a 10 px corner at 96 dpi leaves (4,4) inside', at96);
  AssertFalse('the same logical 10 at 192 dpi is a 20 px corner, so (4,4) is cut off',
              at192);
end;

procedure TPainterVectorTest.TestSvgPathInFitsInsideTheRect;
var l, t, r, b: Integer;
begin
  MakePainter(100, 100, 96);
  FPainter.BeginPath;
  { A unit triangle, fitted into a 40x40 box at (30,30). This is the `path://`
    custom-symbol shape ECharts uses; BGRA parses the grammar, we only fit it. }
  FPainter.SvgPathIn('M0,0 L10,0 L5,10 Z', Rect(30, 30, 70, 70));
  FPainter.FillPath(Red);
  AssertTrue('something was drawn', InkBounds(l, t, r, b));
  AssertTrue('inside the target rect horizontally', (l >= 29) and (r <= 71));
  AssertTrue('inside it vertically', (t >= 29) and (b <= 71));
end;

procedure TPainterVectorTest.TestSvgPathInIsCentred;
var
  l, t, r, b, cx: Integer;
begin
  MakePainter(100, 100, 96);
  FPainter.BeginPath;
  FPainter.SvgPathIn('M0,0 L10,0 L5,10 Z', Rect(20, 20, 80, 60));
  FPainter.FillPath(Red);
  AssertTrue('something was drawn', InkBounds(l, t, r, b));
  cx := (l + r) div 2;
  { Aspect kept, so the 1:1 triangle is fitted on the SHORT axis (height 40) and
    centred on the long one -- not pinned to the left edge. }
  AssertTrue('centred horizontally in the rect, got cx=' + IntToStr(cx),
             Abs(cx - 50) <= 2);
end;

{ ============================ rotated text ============================ }

procedure TPainterVectorTest.TestRotatedTextAtZeroMatchesUnrotated;
var
  rl, rt, rr, rb: Integer;
  pl, pt, pr, pb: Integer;
  hasRot, hasPlain: Boolean;
begin
  MakePainter(160, 60, 96);
  FPainter.DrawTextRotated('Wg', '', 12, 400, Black, 20, 20, 0,
                           taLeftJustify, tlTop);
  hasRot := InkBounds(rl, rt, rr, rb);
  FreePainter;

  MakePainter(160, 60, 96);
  FPainter.DrawText(Rect(20, 20, 150, 50), 'Wg', '', 12, 400, Black,
                    taLeftJustify, tlTop, False);
  hasPlain := InkBounds(pl, pt, pr, pb);

  AssertTrue('rotated-by-zero drew something', hasRot);
  AssertTrue('and so did the plain path', hasPlain);
  { Zero rotation must not be a special case that lands somewhere else. A couple
    of pixels of slack: the two paths differ in how they anchor, not in where. }
  AssertTrue('left edges agree (rot=' + IntToStr(rl) + ' plain=' + IntToStr(pl) + ')',
             Abs(rl - pl) <= 2);
  AssertTrue('top edges agree (rot=' + IntToStr(rt) + ' plain=' + IntToStr(pt) + ')',
             Abs(rt - pt) <= 2);
end;

procedure TPainterVectorTest.TestRotatedTextFullTurnMatchesZero;
var
  al, at_, ar, ab, bl, bt, br, bb: Integer;
begin
  MakePainter(160, 60, 96);
  FPainter.DrawTextRotated('Wg', '', 12, 400, Black, 60, 30, 0,
                           taCenter, tlCenter);
  InkBounds(al, at_, ar, ab);
  FreePainter;

  MakePainter(160, 60, 96);
  FPainter.DrawTextRotated('Wg', '', 12, 400, Black, 60, 30, 2 * Pi,
                           taCenter, tlCenter);
  InkBounds(bl, bt, br, bb);

  AssertTrue('a full turn lands where zero does, left', Abs(al - bl) <= 2);
  AssertTrue('a full turn lands where zero does, top', Abs(at_ - bt) <= 2);
end;

procedure TPainterVectorTest.TestRotatedTextQuarterTurnIsTaller;
var
  w0, h0, w90, h90, l, t, r, b: Integer;
begin
  MakePainter(160, 160, 96);
  FPainter.DrawTextRotated('Category', '', 12, 400, Black, 80, 80, 0,
                           taCenter, tlCenter);
  InkBounds(l, t, r, b);
  w0 := r - l;
  h0 := b - t;
  FreePainter;

  MakePainter(160, 160, 96);
  FPainter.DrawTextRotated('Category', '', 12, 400, Black, 80, 80, Pi / 2,
                           taCenter, tlCenter);
  InkBounds(l, t, r, b);
  w90 := r - l;
  h90 := b - t;

  { The rotated-axis-label case. A quarter turn must swap the ink box's
    proportions -- if it came out the same shape, the angle never reached the
    text renderer. }
  AssertTrue('unrotated is wide (' + IntToStr(w0) + 'x' + IntToStr(h0) + ')', w0 > h0);
  AssertTrue('rotated is tall (' + IntToStr(w90) + 'x' + IntToStr(h90) + ')', h90 > w90);
end;

procedure TPainterVectorTest.TestRotatedTextPositiveAngleRunsCounterClockwise;
var
  l, t, r, b: Integer;
begin
  { Pins the SIGN, which nothing else does: "taller when turned" is true either
    way round. Anchored top-left at (80,120) and turned a quarter turn
    COUNTER-clockwise, the direction the text runs -- rightward at angle 0 --
    becomes upward, so all the ink must end up above the anchor. }
  MakePainter(160, 160, 96);
  FPainter.DrawTextRotated('Category', '', 12, 400, Black, 80, 120, Pi / 2,
                           taLeftJustify, tlTop);
  AssertTrue('something was drawn', InkBounds(l, t, r, b));
  AssertTrue('the text runs UP from the anchor, not down'
             + ' (ink bottom=' + IntToStr(b) + ', anchor y=120)', b <= 124);
  AssertTrue('and it reaches well above it (ink top=' + IntToStr(t) + ')', t < 100);
end;

procedure TPainterVectorTest.TestTheHitTestUsesTheRuleItWasGiven;
var
  holeAfterFill: Boolean;
begin
  { A RING, because a rectangle cannot tell the two rules apart and the hit-test
    test above uses one. Two contours wound the same way: even-odd calls the
    middle outside, non-zero calls it inside -- which is what TTyFillRule's own
    comment is about, a sunburst band whose hole non-zero would fill in.

    PathContains used to set no fill mode, so isPointInPath answered from
    whatever was shared: even-odd on a fresh painter, because that is the zero
    value of TFillMode, and winding after any FillPath. The rule the caller gave
    the fill was invisible to the hit test meant to agree with it. }
  MakePainter(100, 100, 96);
  FPainter.BeginPath;
  FPainter.MoveTo(50 + 40, 50);
  FPainter.ArcTo(50, 50, 40, 0, 2 * Pi, False);
  FPainter.ClosePath;
  FPainter.MoveTo(50 + 20, 50);
  FPainter.ArcTo(50, 50, 20, 0, 2 * Pi, False);
  FPainter.ClosePath;

  AssertTrue('the band is inside under either rule',
    FPainter.PathContains(50, 50 - 30, tfrEvenOdd));
  AssertFalse('even-odd says the hole is outside',
    FPainter.PathContains(50, 50, tfrEvenOdd));
  AssertTrue('and non-zero says it is inside',
    FPainter.PathContains(50, 50, tfrNonZero));

  { AND IT SURVIVES A FILL. The shared fillMode is what a fill leaves behind, so
    this is the query that used to come back with the other answer. }
  FPainter.FillPath(Red, tfrNonZero);
  holeAfterFill := FPainter.PathContains(50, 50, tfrEvenOdd);
  AssertFalse('an even-odd query still answers even-odd after a non-zero fill',
    holeAfterFill);
end;

initialization
  RegisterTest(TPainterVectorTest);
end.
