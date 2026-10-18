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
  BGRACanvas2D, tyControls.Types, tyControls.Painter, test.danglingrefs;
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
    function ColourFlipsAlongRow(AY, AX0, AX1: Integer): Integer;
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
    procedure TestFillPathWithATextureFillsThePathShape;
    procedure TestAStretchedTextureCoversTheWholeBounds;
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
    procedure TestARepeatedClipIsBuiltOnceAndPaintsTheSame;
    procedure TestAKeptBitmapIsNotLeftSharingAFreedClip;
    procedure TestAKeptMaskIsOnlyTheRequestItWasBuiltFor;
    procedure TestAnEvictedMaskASavedStateSharesIsCopiedFirst;
    procedure TestAKeptMaskOutlivesItsPainter;
    procedure TestAMaskAnotherLivePainterHoldsIsNeitherTakenNorEvicted;
    { ---- BGRA's edge sort takes its pivots from the global Random ---- }
    procedure TestALongPathPaintsTheSameWhateverTheGlobalRandomHolds;
    procedure TestPaintingNeverRestartsTheApplicationsRandomStream;
    procedure TestAPaintThatDrawsNoRandomLeavesTheStreamAlone;
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

{ A chart clips every element to its series' box, and every clip used to build a mask the
  size of the surface. The painter keeps the masks a frame built and hands the same
  request -- rect, transform, surface -- the same mask. What is painted must be what
  building it every time paints: a sequence of clips under two transforms, five rects
  (more than are kept, so some are dropped and built again), clips intersected inside
  clips, translucent fills across the clip edges -- pixel for pixel against the same
  sequence with the reuse off. And fifty elements in one box build one mask. }
procedure TPainterVectorTest.TestARepeatedClipIsBuiltOnceAndPaintsTheSame;
const
  cRects: array[0..4] of TRect = ((Left: 10; Top: 5; Right: 120; Bottom: 70),
    (Left: 30; Top: 20; Right: 190; Bottom: 95), (Left: 0; Top: 0; Right: 200; Bottom: 100),
    (Left: 60; Top: 10; Right: 90; Bottom: 90), (Left: 5; Top: 40; Right: 150; Bottom: 60));
var
  ref: TBGRABitmap;
  k, x, y, built: Integer;

  procedure Paint;
  var
    i: Integer;
  begin
    for i := 0 to 39 do
    begin
      FPainter.SaveState;
      if i mod 7 = 3 then FPainter.Translate(7, 3);
      FPainter.ClipRect(cRects[(i * 3) mod 5]);
      if i mod 4 = 1 then
      begin
        FPainter.SaveState;
        FPainter.ClipRect(cRects[(i + 1) mod 5]);
        FPainter.BeginPath;
        FPainter.RectPath(i * 4.5, 0, 30, 100);
        FPainter.FillPath(TyRGBA(0, 120, 255, 90));
        FPainter.RestoreState;
      end;
      FPainter.BeginPath;
      FPainter.RectPath(i * 5.25 - 20, i * 2.5 - 10, 60.5, 45.25);
      FPainter.FillPath(TyRGBA(200, i * 6, 40, 120));
      FPainter.RestoreState;
    end;
  end;

begin
  TyPainterClipReuseForTest(False);
  try
    MakePainter(200, 100, 96);
    Paint;
    ref := FPainter.Bitmap.Duplicate as TBGRABitmap;
    FreePainter;
  finally
    TyPainterClipReuseForTest(True);
  end;
  try
    built := TyPainterClipMasksBuiltForTest;
    MakePainter(200, 100, 96);
    Paint;
    AssertTrue('the kept masks were used', TyPainterClipMasksBuiltForTest > built);
    for y := 0 to 99 do
      for x := 0 to 199 do
        if FPainter.Bitmap.GetPixel(x, y) <> ref.GetPixel(x, y) then
          Fail(Format('pixel %d,%d differs from building every clip', [x, y]));
  finally
    ref.Free;
  end;
  FreePainter;
  MakePainter(200, 100, 96);
  built := TyPainterClipMasksBuiltForTest;
  for k := 1 to 50 do
  begin
    FPainter.SaveState;
    FPainter.ClipRect(Rect(20, 10, 180, 90));
    FPainter.BeginPath;
    FPainter.RectPath(k * 3, 0, 10, 100);
    FPainter.FillPath(Red);
    FPainter.RestoreState;
  end;
  AssertEquals('fifty elements in one box, one mask', 1, TyPainterClipMasksBuiltForTest - built);
  AssertEquals('and still clipped', 0, AlphaAt(100, 5));
  AssertTrue('inside it painted', Opaque(100, 50));
end;

{ The kept masks belong to the painter and go with it; a state still sharing one -- a
  clip left unrestored on a bitmap the painter does not own -- must not be left
  pointing at freed memory. The frees are poisoned, so a dangling read faults. }
procedure TPainterVectorTest.TestAKeptBitmapIsNotLeftSharingAFreedClip;
var
  bmp: TBGRABitmap;
  p: TTyPainter;
begin
  bmp := TBGRABitmap.Create(100, 60, BGRAPixelTransparent);
  try
    p := TTyPainter.Create;
    try
      p.BeginPaintOn(nil, Rect(0, 0, 100, 60), 96, bmp);
      p.SaveState;
      p.ClipRect(Rect(0, 0, 50, 60));    // built and kept
      p.RestoreState;
      p.SaveState;
      p.ClipRect(Rect(0, 0, 50, 60));    // the kept one, shared -- and left unrestored
      p.SaveState;
      BeginPoison;
      try
        p.EndPaint;
      finally
        FreeAndNil(p);
      end;
      bmp.Canvas2D.fillStyle(BGRA(255, 0, 0, 255));
      bmp.Canvas2D.fillRect(0, 0, 100, 60);
      { and the saved state under it, which shared the kept mask too }
      bmp.Canvas2D.restore;
      bmp.Canvas2D.fillStyle(BGRA(0, 0, 255, 255));
      bmp.Canvas2D.fillRect(0, 0, 100, 60);
      EndPoison;
    except
      EndPoison;
      p.Free;
      raise;
    end;
    AssertEquals('painted inside the clip', 255, bmp.GetPixel(25, 30).alpha);
    AssertEquals('not outside it', 0, bmp.GetPixel(75, 30).alpha);
  finally
    bmp.Free;
  end;
end;

{ The key of a kept mask is everything the mask depends on. The test above varies the rect
  and, now and then, the transform -- but its translated clips happened to fall where a
  kept untranslated one made no visible difference. Here each request is made twice in a
  row, the second time with ONE input changed, and the fill after each covers the whole
  surface, so a mask handed back for the wrong request shows: another transform, another
  antialiasing, other pixel centring, a surface resized in the frame. And a hit leaves the
  canvas as building the clip leaves it: the fill rule set to nonzero winding (a caller
  filling on the canvas directly after a clip would otherwise fill by the rule it had
  set before). Each frame is compared pixel for pixel with the same frame built with the
  reuse off. }
procedure TPainterVectorTest.TestAKeptMaskIsOnlyTheRequestItWasBuiltFor;
var
  ref, refBefore, before: TBGRABitmap;
  x, y: Integer;

  { ABefore: the frame as it stands before the resize, which starts the surface over }
  procedure Paint(out ABefore: TBGRABitmap);
  var
    ctx: TBGRACanvas2D;

    procedure ClipAndFill(AColor: TTyColor);
    begin
      FPainter.ClipRect(Rect(20, 10, 130, 70));
      FPainter.BeginPath;
      FPainter.RectPath(0, 0, 300, 150);
      FPainter.FillPath(AColor);
    end;

  begin
    ctx := FPainter.Bitmap.Canvas2D;
    FPainter.SaveState;
    ClipAndFill(TyRGBA(200, 0, 0, 120));
    FPainter.RestoreState;
    { a hit leaves nonzero winding: two overlapping rects filled on the canvas itself }
    FPainter.SaveState;
    ctx.fillMode := fmAlternate;
    FPainter.ClipRect(Rect(20, 10, 130, 70));
    ctx.beginPath;
    ctx.rect(10, 20, 80, 30);
    ctx.rect(40, 30, 80, 30);
    ctx.fillStyle(BGRA(120, 0, 160, 200));
    ctx.fill;
    FPainter.RestoreState;
    { another transform }
    FPainter.SaveState;
    FPainter.Translate(13, 7);
    ClipAndFill(TyRGBA(0, 160, 0, 120));
    FPainter.RestoreState;
    { another antialiasing, on a fractional transform so the edges differ }
    FPainter.SaveState;
    FPainter.Translate(0.3, 0.6);
    ClipAndFill(TyRGBA(0, 0, 200, 90));
    FPainter.RestoreState;
    ctx.antialiasing := False;
    FPainter.SaveState;
    FPainter.Translate(0.3, 0.6);
    ClipAndFill(TyRGBA(200, 200, 0, 90));
    FPainter.RestoreState;
    ctx.antialiasing := True;
    { other pixel centring }
    ctx.pixelCenteredCoordinates := not ctx.pixelCenteredCoordinates;
    FPainter.SaveState;
    FPainter.Translate(0.3, 0.6);
    ClipAndFill(TyRGBA(0, 200, 200, 90));
    FPainter.RestoreState;
    ctx.pixelCenteredCoordinates := not ctx.pixelCenteredCoordinates;
    { the surface resized inside the frame: a mask the old size is no clip for it }
    FPainter.SaveState;
    ClipAndFill(TyRGBA(60, 60, 200, 60));
    FPainter.RestoreState;
    ABefore := FPainter.Bitmap.Duplicate as TBGRABitmap;
    FPainter.Bitmap.SetSize(300, 150);
    FPainter.Bitmap.Fill(BGRAPixelTransparent);
    FPainter.SaveState;
    ClipAndFill(TyRGBA(90, 90, 90, 200));
    FPainter.RestoreState;
  end;

begin
  TyPainterClipReuseForTest(False);
  try
    MakePainter(200, 100, 96);
    Paint(refBefore);
    ref := FPainter.Bitmap.Duplicate as TBGRABitmap;
    FreePainter;
  finally
    TyPainterClipReuseForTest(True);
  end;
  before := nil;
  try
    MakePainter(200, 100, 96);
    Paint(before);
    for y := 0 to refBefore.Height - 1 do
      for x := 0 to refBefore.Width - 1 do
        if before.GetPixel(x, y) <> refBefore.GetPixel(x, y) then
          Fail(Format('pixel %d,%d differs from building every clip', [x, y]));
    AssertEquals('the same size', ref.Width, FPainter.Bitmap.Width);
    for y := 0 to ref.Height - 1 do
      for x := 0 to ref.Width - 1 do
        if FPainter.Bitmap.GetPixel(x, y) <> ref.GetPixel(x, y) then
          Fail(Format('resized: pixel %d,%d differs from building every clip', [x, y]));
  finally
    ref.Free;
    refBefore.Free;
    before.Free;
  end;
end;

{ A kept mask a saved state still shares outlives the painter's slot for it only as a
  copy. The state that clipped is saved, the canvas's own unclip lets the current state
  go of the clip (so later clips are first clips again), four more first clips push the
  kept mask out of its slot -- and the saved state, restored, still clips as it did. The
  frees are poisoned, so a state left pointing at the evicted mask reads garbage. }
procedure TPainterVectorTest.TestAnEvictedMaskASavedStateSharesIsCopiedFirst;
var
  ctx: TBGRACanvas2D;
  i, built: Integer;
begin
  MakePainter(200, 100, 96);
  ctx := FPainter.Bitmap.Canvas2D;
  FPainter.SaveState;
  FPainter.ClipRect(Rect(0, 0, 50, 100));
  FPainter.SaveState;
  ctx.beginPath;
  ctx.rect(0, 0, 200, 100);
  ctx.unclip;
  ctx.beginPath;
  built := TyPainterClipMasksBuiltForTest;
  BeginPoison;
  try
    for i := 1 to 4 do
    begin
      FPainter.SaveState;
      FPainter.ClipRect(Rect(60 + i * 10, 0, 90 + i * 10, 100));
      FPainter.RestoreState;
    end;
    AssertEquals('four first clips built, the oldest kept mask pushed out', 4,
      TyPainterClipMasksBuiltForTest - built);
    FPainter.RestoreState;
    FPainter.BeginPath;
    FPainter.RectPath(0, 0, 200, 100);
    FPainter.FillPath(Red);
  finally
    EndPoison;
  end;
  AssertEquals('painted inside the saved clip', 255, AlphaAt(25, 50));
  AssertEquals('not outside it', 0, AlphaAt(120, 50));
  FPainter.RestoreState;
end;

{ [P2] THE POOL OUTLIVES THE PAINTER: a mask one painter built is the next painter's,
  and draws what building it would. }
procedure TPainterVectorTest.TestAKeptMaskOutlivesItsPainter;
var
  ref: TBGRABitmap;
  x, y, built: Integer;

  procedure Paint;
  var k: Integer;
  begin
    for k := 0 to 9 do
    begin
      FPainter.SaveState;
      FPainter.ClipRect(Rect(13, 7, 171, 83));
      FPainter.BeginPath;
      FPainter.RectPath(k * 17 - 5, k * 9 - 4, 40.5, 30.25);
      FPainter.FillPath(TyRGBA(30, k * 20, 200, 140));
      FPainter.RestoreState;
    end;
  end;

begin
  TyPainterClipReuseForTest(False);
  try
    MakePainter(200, 100, 96);
    Paint;
    ref := FPainter.Bitmap.Duplicate as TBGRABitmap;
    FreePainter;
  finally
    TyPainterClipReuseForTest(True);
  end;
  try
    MakePainter(200, 100, 96);
    built := TyPainterClipMasksBuiltForTest;
    Paint;
    AssertEquals('the first painter builds the box once', 1, TyPainterClipMasksBuiltForTest - built);
    FPainter.EndPaint;
    FreePainter;
    MakePainter(200, 100, 96);
    built := TyPainterClipMasksBuiltForTest;
    Paint;
    AssertEquals('the next painter builds nothing', 0, TyPainterClipMasksBuiltForTest - built);
    for y := 0 to 99 do
      for x := 0 to 199 do
        if FPainter.Bitmap.GetPixel(x, y) <> ref.GetPixel(x, y) then
          Fail(Format('pixel %d,%d differs from building every clip', [x, y]));
    { the test switch starts from an empty pool, so the first count above
      never rests on what an earlier test left [fin: a switch that kept the
      spares survived] }
    FPainter.EndPaint;
    FreePainter;
    TyPainterClipReuseForTest(True);
    MakePainter(200, 100, 96);
    built := TyPainterClipMasksBuiltForTest;
    Paint;
    AssertEquals('after the switch the box is built again', 1, TyPainterClipMasksBuiltForTest - built);
  finally
    ref.Free;
  end;
end;

{ [P2] Two painters at once: the one that holds an entry (its canvas may share it) keeps
  it -- the other builds its own, and its own first clips never push the first painter's
  out. The frees are poisoned, so a state left on an evicted mask reads garbage. }
procedure TPainterVectorTest.TestAMaskAnotherLivePainterHoldsIsNeitherTakenNorEvicted;
var
  other: TTyPainter;
  host: TBitmap;
  i, built: Integer;
begin
  TyPainterClipReuseForTest(True);
  MakePainter(200, 100, 96);
  FPainter.SaveState;
  FPainter.ClipRect(Rect(0, 0, 50, 100));
  host := TBitmap.Create;
  other := TTyPainter.Create;
  try
    host.SetSize(200, 100);
    other.BeginPaint(host.Canvas, Rect(0, 0, 200, 100), 96);
    built := TyPainterClipMasksBuiltForTest;
    other.SaveState;
    other.ClipRect(Rect(0, 0, 50, 100));
    other.RestoreState;
    AssertEquals('the other painter builds its own', 1, TyPainterClipMasksBuiltForTest - built);
    BeginPoison;
    try
      for i := 1 to 6 do
      begin
        other.SaveState;
        other.ClipRect(Rect(60 + i * 10, 0, 90 + i * 10, 100));
        other.RestoreState;
      end;
      FPainter.BeginPath;
      FPainter.RectPath(0, 0, 200, 100);
      FPainter.FillPath(Red);
    finally
      EndPoison;
    end;
    AssertEquals('painted inside the first painter''s clip', 255, AlphaAt(25, 50));
    AssertEquals('not outside it', 0, AlphaAt(120, 50));
    other.EndPaint;
  finally
    other.Free;
    host.Free;
  end;
  FPainter.RestoreState;
end;

{ A long line series' outline, 300 points 2.4 px apart that jump about.
  Generated here, not with Random -- the global generator is the thing under
  test. The data seeds are ones whose stroke came out differently under
  different global seeds before the pin (found with a scratch probe). }
procedure ZigzagPath(P: TTyPainter; ASeed: LongWord; AClosed: Boolean);
var
  i: Integer;
  st: LongWord;
  x, y: Double;
begin
  st := ASeed;
  P.BeginPath;
  for i := 0 to 299 do
  begin
    {$push}{$R-}{$Q-}
    st := st * 1103515245 + 12345;
    {$pop}
    x := 40 + i * 2.4;
    y := 100 + (st shr 8) mod 300 + ((st shr 3) mod 37) / 100;
    if i = 0 then P.MoveTo(x, y) else P.LineTo(x, y);
  end;
  if AClosed then
  begin
    P.LineTo(40 + 299 * 2.4, 480);
    P.LineTo(40, 480);
    P.ClosePath;
  end;
end;

{ Two zigzags round the same bottom edge, one path: below both the winding is
  two, so the non-zero merge -- where the order of tied crossings tells --
  runs on every row. A simple polygon (one zigzag closed) fills alike in any
  order and never shows the pivots. The seed is one whose clip came out
  differently under different global seeds unpinned (a scratch probe). }
procedure ZigzagLoops(P: TTyPainter; ASeed: LongWord);
var
  i, lp: Integer;
  st: LongWord;
  x, y: Double;
begin
  P.BeginPath;
  for lp := 0 to 1 do
  begin
    st := ASeed + LongWord(lp) * 1000;
    for i := 0 to 299 do
    begin
      {$push}{$R-}{$Q-}
      st := st * 1103515245 + 12345;
      {$pop}
      x := 40 + i * 2.4;
      y := 100 + (st shr 8) mod 300 + ((st shr 3) mod 37) / 100;
      if (i = 0) and (lp = 0) then P.MoveTo(x, y) else P.LineTo(x, y);
    end;
    P.LineTo(40 + 299 * 2.4, 480);
    P.LineTo(40, 480);
  end;
  P.ClosePath;
end;

procedure TPainterVectorTest.TestALongPathPaintsTheSameWhateverTheGlobalRandomHolds;
{ BGRA's one-pass polygon filler sorts the edges by y with a quicksort that
  picks its pivots with the global Random. Edges on the same y come out in a
  pivot-dependent order, and on a scanline where that order matters the
  antialiased coverage differs by a step or two -- so line-aqi and
  area-rainfall painted differently from one run of the same exe to the next.
  The painter pins the generator around each fill: whatever the application's
  generator holds, a path paints the same. A stroke, a fill and a clip, each
  under eight different global seeds. }
const
  cSeeds: array[0..7] of LongWord = (1, 2, 3, 99, 12345, $DEADBEEF, 7, 31337);
var
  ref: TBGRABitmap;
  k, x, y, diff: Integer;

  procedure Paint;
  begin
    FPainter.SetLineJoin(tljBevel);
    ZigzagPath(FPainter, 1, False);
    FPainter.StrokePath(TyRGBA(84, 112, 198, 255), 2);
    ZigzagPath(FPainter, 3, False);
    FPainter.StrokePath(TyRGBA(200, 60, 40, 255), 2);
    ZigzagPath(FPainter, 4, False);
    FPainter.StrokePath(TyRGBA(20, 160, 60, 255), 2);
    ZigzagPath(FPainter, 2, True);
    FPainter.FillPath(TyRGBA(200, 60, 40, 110));
    FPainter.SaveState;
    { a clip that winds twice: one zigzag closed is a simple polygon and
      clipped alike unpinned [fin: the CtxClip pin survived] }
    ZigzagLoops(FPainter, 9);
    FPainter.ClipPath;
    FPainter.BeginPath;
    FPainter.RectPath(0, 0, 800, 500);
    FPainter.FillPath(TyRGBA(20, 160, 60, 90));
    FPainter.RestoreState;
  end;

begin
  ref := nil;
  try
    for k := 0 to High(cSeeds) do
    begin
      RandSeed := cSeeds[k];
      MakePainter(800, 500, 96);
      Paint;
      if ref = nil then
        ref := FPainter.Bitmap.Duplicate as TBGRABitmap
      else
      begin
        diff := 0;
        for y := 0 to ref.Height - 1 do
          for x := 0 to ref.Width - 1 do
            if FPainter.Bitmap.GetPixel(x, y) <> ref.GetPixel(x, y) then Inc(diff);
        AssertEquals('pixels that differ under global seed ' + IntToStr(cSeeds[k]),
          0, diff);
      end;
      FreePainter;
    end;
  finally
    ref.Free;
  end;
end;

procedure TPainterVectorTest.TestPaintingNeverRestartsTheApplicationsRandomStream;
{ The pin must not cost the application its stream. Restoring the saved
  RandSeed would make FPC's generator reseed from that value at the next
  call -- after every paint the application would draw the same numbers it
  drew after the previous one. Paint, draw, three times over: the draws all
  differ, and an application that seeds its own generator still gets the
  same draws on a second go (the pin is deterministic too). }
var
  a, b: array[0..2] of LongInt;
  k: Integer;

  procedure Cycle(var AOut: array of LongInt);
  var
    i: Integer;
  begin
    RandSeed := 4242;
    for i := 0 to 2 do
    begin
      MakePainter(800, 500, 96);
      ZigzagPath(FPainter, 1, False);
      FPainter.StrokePath(TyRGBA(84, 112, 198, 255), 2);
      FreePainter;
      AOut[i] := Random(MaxInt);
    end;
  end;

begin
  Cycle(a);
  AssertTrue('the first and second draws differ', a[0] <> a[1]);
  AssertTrue('the second and third draws differ', a[1] <> a[2]);
  AssertTrue('the first and third draws differ', a[0] <> a[2]);
  Cycle(b);
  for k := 0 to 2 do
    AssertEquals('draw ' + IntToStr(k) + ' again from the same seed', a[k], b[k]);
end;

procedure TPainterVectorTest.TestAPaintThatDrawsNoRandomLeavesTheStreamAlone;
{ A short path is sorted without Random (BGRA's insertion sort below ten
  points), so the pin hands the seed back as it was: the application's next
  draw is the one it would have made without the paint -- not a draw from a
  reseeded generator. [fin: an unpin that always reseeded survived] }
var
  want, got: LongInt;
begin
  RandSeed := 4242;
  Random(MaxInt);
  want := Random(MaxInt);
  RandSeed := 4242;
  Random(MaxInt);
  MakePainter(200, 100, 96);
  FPainter.BeginPath;
  FPainter.MoveTo(10, 10);
  FPainter.LineTo(90, 20);
  FPainter.LineTo(40, 80);
  FPainter.ClosePath;
  FPainter.FillPath(TyRGBA(200, 60, 40, 255));
  FPainter.BeginPath;
  FPainter.MoveTo(100, 10);
  FPainter.LineTo(190, 90);
  FPainter.StrokePath(TyRGBA(20, 160, 60, 255), 2);
  FPainter.SaveState;
  FPainter.ClipRect(Rect(13, 7, 171, 83));
  FPainter.BeginPath;
  FPainter.RectPath(0, 0, 200, 100);
  FPainter.FillPath(TyRGBA(30, 60, 200, 140));
  FPainter.RestoreState;
  FreePainter;
  got := Random(MaxInt);
  AssertEquals('the next draw is the one the paint never touched', want, got);
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

{ How many times the dominant channel flips between red and blue along a row.
  A stretched single tile flips once; a repeat of the same tile flips several
  times, which is the difference coverage cannot see. }
function TPainterVectorTest.ColourFlipsAlongRow(AY, AX0, AX1: Integer): Integer;
var
  x, cur, prev: Integer;
  p: TBGRAPixel;
begin
  Result := 0;
  prev := 0;
  for x := AX0 to AX1 do
  begin
    p := PixelAt(x, AY);
    if p.alpha < 200 then Continue;
    if p.red > p.blue + 40 then cur := 1
    else if p.blue > p.red + 40 then cur := 2
    else cur := 0;
    if cur = 0 then Continue;
    if (prev <> 0) and (cur <> prev) then Inc(Result);
    prev := cur;
  end;
end;

{ A checker written to a temp file, since the suite keeps binaries out of git.
  Two colours, so a test can tell a TEXTURE from a flat fill.

  SIXTEEN PIXELS SQUARE, in four blocks of eight. A 2x2 tile is all edge: the
  pattern scanner interpolates, so every pixel came out a blend of the two and
  an assertion looking for red found none -- while 1,224 pixels of purple were
  sitting there proving the fill worked. }
function WriteCheckerPng: string;
var
  b: TBGRABitmap;
  x, y: Integer;
begin
  Result := GetTempDir + 'tycontrols-checker-test.png';
  b := TBGRABitmap.Create(16, 16);
  try
    for y := 0 to 15 do
      for x := 0 to 15 do
        if ((x < 8) = (y < 8)) then
          b.SetPixel(x, y, BGRA(255, 0, 0, 255))
        else
          b.SetPixel(x, y, BGRA(0, 0, 255, 255));
    { A GREEN CORNER marks the image's own origin, so a test can see where the
      tiling STARTS rather than only that it happened. }
    for y := 0 to 3 do
      for x := 0 to 3 do
        b.SetPixel(x, y, BGRA(0, 255, 0, 255));
    b.SaveToFile(Result);
  finally
    b.Free;
  end;
end;

procedure TPainterVectorTest.TestFillPathWithATextureFillsThePathShape;
var
  f: TTyFill;
  reds, blues, x, y: Integer;
  p: TBGRAPixel;
begin
  { PATTERNS ARE A FIRST-CLASS FILL, per row 2 -- and an image-backed fill used
    to paint NOTHING here. The else arm claimed the image kinds degrade to
    their base colour; an image fill's Color is tyTransparent, because neither
    place that builds one ever assigns it, so "degrade" meant alpha zero and no
    error. The suggested workaround could not work either: DrawImageFill clips
    with FBmp.ClipRect, a rectangle on the bitmap, which never sees the
    Canvas2D clip mask ClipPath writes. }
  MakePainter(60, 60, 96);
  f := Default(TTyFill);
  f.Kind := tfkImage;
  f.ImagePath := WriteCheckerPng;
  f.ImageMode := timCover;

  FPainter.BeginPath;
  FPainter.CirclePath(30, 30, 20);
  FPainter.FillPathWith(f, Rect(10, 10, 50, 50));

  reds := 0;
  blues := 0;
  for y := 0 to 59 do
    for x := 0 to 59 do
    begin
      p := PixelAt(x, y);
      if p.alpha < 200 then Continue;
      if (p.red > 200) and (p.blue < 60) then Inc(reds)
      else if (p.blue > 200) and (p.red < 60) then Inc(blues);
    end;

  AssertTrue('the texture actually painted (' + IntToStr(reds + blues)
    + ' px)', reds + blues > 300);
  { BOTH colours: one alone would mean a flat fill that happens to be opaque,
    which is what a "degrade to a colour" would look like if the colour were
    ever set. }
  AssertTrue('and it is a texture, not one flat colour (' + IntToStr(reds)
    + ' red, ' + IntToStr(blues) + ' blue)', (reds > 50) and (blues > 50));

  { PATH-SHAPED, not bounds-shaped. The corner of the bounds is outside a
    circle inscribed in it. }
  AssertTrue('the bounds corner is untouched', AlphaAt(11, 11) = 0);
end;

procedure TPainterVectorTest.TestAStretchedTextureCoversTheWholeBounds;
var
  f: TTyFill;
  inked, x, y: Integer;
begin
  { timStretch means ONE tile the size of the bounds rather than a repeat, so
    a two-pixel image has to be resampled. The resampled copy is freed after
    the fill, and the pattern holds the bitmap rather than copying it -- so
    freeing it before the fill would paint from freed memory. }
  MakePainter(60, 60, 96);
  f := Default(TTyFill);
  f.Kind := tfkImage;
  f.ImagePath := WriteCheckerPng;
  f.ImageMode := timStretch;

  FPainter.BeginPath;
  FPainter.RectPath(10, 10, 40, 40);
  FPainter.FillPathWith(f, Rect(10, 10, 50, 50));

  inked := 0;
  for y := 0 to 59 do
    for x := 0 to 59 do
      if AlphaAt(x, y) > 200 then Inc(inked);
  { RectPath is (left, top, right, bottom), so the path is 30x30 = 900 px --
    the whole of it, rather than one tile in a corner. }
  AssertTrue('the stretched texture covers the path (' + IntToStr(inked)
    + ' px of 900)', inked > 850);

  { ONE TILE, NOT A REPEAT. Coverage alone cannot tell those apart -- a repeat
    covers the path too, which is how the first version of this test passed
    with the stretch branch mutated out. The number of colour changes across
    the shape can: one stretched 16px checker gives a single flip, a repeat of
    it gives several. }
  AssertEquals('the checker crosses once, so it was scaled not repeated',
    1, ColourFlipsAlongRow(25, 12, 38));

  { AND IT STARTS AT THE BOUNDS. The image's own corner is green, so this says
    the tiling is anchored where the caller said and not at the canvas origin
    -- the other thing coverage was blind to. }
  AssertTrue('the image corner lands at the bounds corner',
    PixelAt(12, 12).green > 150);
end;

initialization
  RegisterTest(TPainterVectorTest);
end.
