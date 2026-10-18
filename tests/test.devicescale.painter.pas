unit test.devicescale.painter;
{$mode objfpc}{$H+}

{ #83: the painter at a device scale S.

  The painter's coordinates stay what callers pass today (layout pixels); its layer is S times
  larger, and EndPaint draws it back into the layout rect -- or 1:1 at S times the position when
  the canvas itself counts device pixels (an S-times cache, and the test seam's DeviceUnits,
  which is how these tests get the raster back to look at). }

interface

uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes, BGRATransform,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  test.devicescale.support, test.danglingrefs;

type
  TPainterDraw = procedure(P: TTyPainter; K: Integer) of object;

  TDeviceScalePainterTest = class(TTestCase)
  private
    FCanvasBmp: TBitmap;
    FDegRect, FDegMethod: Integer;
    FRtl: Boolean;   // DrawBoth begins its painters right-to-left
    FBackdrop: TBGRABitmap;   // a raster-sized backdrop for the glass/slice tests
    function NewCanvas(AW, AH: Integer): TCanvas;
    function PixelAt(AX, AY: Integer): TBGRAPixel;
    { Draw the same thing twice and keep both layers. Scaled: S = 2 through the seam, layout
      Rect(0, 0, AW, AH) at PPI 96, ADraw(P, 1). Reference: S = 1, Rect(0, 0, 2AW, 2AH) at PPI
      192, ADraw(P, 2) -- ADraw multiplies every device coordinate it passes by K and passes
      logical values unchanged. The raster scope turns the first into exactly the second. }
    procedure DrawBoth(ADraw: TPainterDraw; AW, AH: Integer; out AScaled, ARef: TBGRABitmap);
    procedure AssertSamePixels(const AMsg: string; A, B: TBGRABitmap);
    procedure CheckSame(const AMsg: string; ADraw: TPainterDraw);
    { A theme image is a one-times asset: its pixels are layout pixels at any scale. So the
      reference here is the SAME layout rect at S = 1, and the S = 2 raster averaged down 2:1
      must match it to within ATolerance (mean channel distance). The 192-PPI reference of
      CheckSame takes image pixels as device pixels and cannot see an image drawn at half size. }
    procedure CheckLikeOneTimes(const AMsg: string; ADraw: TPainterDraw; ATolerance: Double);
    { Draws ADraw at S = 2 and at S = 1 on the same 60 x 40 layout rect; AHalf is the S = 2
      raster averaged down. The caller frees both. }
    procedure DrawAtBothScales(ADraw: TPainterDraw; out AHalf, ARef: TBGRABitmap);
    procedure DrawFillSolid(P: TTyPainter; K: Integer);
    procedure DrawFillGradient(P: TTyPainter; K: Integer);
    procedure DrawFillPerCorner(P: TTyPainter; K: Integer);
    procedure DrawStrokes(P: TTyPainter; K: Integer);
    procedure DrawEdges(P: TTyPainter; K: Integer);
    procedure DrawShadow(P: TTyPainter; K: Integer);
    procedure DrawGlyphs(P: TTyPainter; K: Integer);
    procedure DrawChevron(P: TTyPainter; K: Integer);
    procedure DrawCornerGaps(P: TTyPainter; K: Integer);
    procedure DrawErase(P: TTyPainter; K: Integer);
    procedure DrawDegenerate(P: TTyPainter; K: Integer);
    procedure DrawTextAligns(P: TTyPainter; K: Integer);
    procedure DrawTextEllipsis(P: TTyPainter; K: Integer);
    procedure DrawTextMultiLine(P: TTyPainter; K: Integer);
    procedure DrawTextMnemonic(P: TTyPainter; K: Integer);
    procedure DrawTextRtl(P: TTyPainter; K: Integer);
    procedure DrawNineSlices(P: TTyPainter; K: Integer);
    procedure DrawImageFills(P: TTyPainter; K: Integer);
    procedure DrawBlurredFill(P: TTyPainter; K: Integer);
    procedure DrawImageSlice(P: TTyPainter; K: Integer);
    procedure DrawGlassPane(P: TTyPainter; K: Integer);
    procedure DrawNineSliceFill(P: TTyPainter; K: Integer);
    procedure DrawPointerShapes(P: TTyPainter; K: Integer);
    procedure DrawStars(P: TTyPainter; K: Integer);
    procedure DrawFillThenPointer(P: TTyPainter; K: Integer);
    { As CheckSame, but each channel may differ by up to ATolerance: Canvas2D drawn through
      the preset scale(2,2) and Canvas2D given doubled coordinates rasterise the same path, but
      not necessarily to the last bit of antialiasing. }
    procedure CheckClose(const AMsg: string; ADraw: TPainterDraw; ATolerance: Integer);
    function TestImagePath: string;
    function PaintNineSliceAt(AScale: Integer; const APath: string): TBGRABitmap;
    function Backdrop: TBGRABitmap;
  protected
    procedure TearDown; override;
  published
    procedure TestRasterIsScaleTimesLayout;
    procedure TestScaleOneLeavesCanvas2DAlone;
    procedure TestDeviceUnitsLandOneToOne;
    procedure TestStretchIntoLayoutRect;
    procedure TestOpacityBaseAtScaleTwo;
    procedure TestDegenerateRects;
    procedure TestNilCanvasIsScaleOne;
    procedure TestBeginPaintOnResizesToRaster;
    procedure TestScaleOneEndPaintUnchanged;
    { Task 3: fills, borders, glyphs and shadows inside the raster scope. }
    procedure TestFillBackgroundSolidRounded;
    procedure TestFillBackgroundGradient;
    procedure TestFillBackgroundPerCorner;
    procedure TestStrokeBorderWidths;
    procedure TestDrawEdge;
    procedure TestDropShadow;
    procedure TestDrawGlyphKinds;
    procedure TestDrawDropChevron;
    procedure TestFillCornerGaps;
    procedure TestEraseRect;
    procedure TestDegenerateRectsInScope;
    procedure TestScaleAfterDrawingIsLayout;
    { Task 4: text drawn in the raster scope, measured outside it. }
    procedure TestDrawTextSingleLine;
    procedure TestDrawTextEllipsis;
    procedure TestDrawTextMultiLine;
    procedure TestDrawTextMnemonic;
    procedure TestDrawTextRtl;
    procedure TestMeasuringStaysLayout;
    { Task 5: images, glass and glyph bitmaps. }
    procedure TestNineSlice;
    procedure TestNineSliceKeepsTheCachedSource;
    { The nine-slice's corners are drawn 1:1 from the image at S = 1; at S = 2 they are the same
      image pixels, each on S x S device pixels. }
    procedure TestNineSliceCornersAreImagePixelsDoubled;
    { A blurred image fill: the blur acts on the one-times image at the layout radius, so the
      frost is as wide in layout pixels at S = 2 as at S = 1. }
    procedure TestImageFillBlurIsLayoutWide;
    procedure TestDrawImageFillModes;
    procedure TestFillImageSlice;
    procedure TestFillGlass;
    procedure TestDrawGlyphBitmapCentersRasterGlyph;
    procedure TestGlyphOverrideRendersAtDeviceSize;
    procedure TestNestedCallMapsOnce;
    { Task 6: the painter's own Canvas2D shapes follow the preset device scale. }
    procedure TestFillPointerShape;
    procedure TestDrawStar;
    procedure TestCanvas2DKeepsTransformAcrossPainterCalls;
    { Task 7: TyDeviceScaleRendering := False is the way back to one times. }
    procedure TestSwitchOffDrawsAtOne;
    { Task 13: DrawRule, the rule a control draws instead of Bitmap.DrawLine(…, False). At S = 1
      it is that line, pixel for pixel, in all four directions. }
    procedure TestDrawRuleIsDrawLineAtOne;
    { At S = 2 it is one LAYOUT pixel wide: two device pixels, at twice the place. }
    procedure TestDrawRuleIsOneLayoutPixelWide;
    { A run that is neither horizontal nor vertical is Bitmap.DrawLine(…, False) with its ends
      mapped -- in a release build too, where an assertion would be compiled out. }
    procedure TestDrawRuleSlantedIsTheLine;
  end;

const
  CSentinel = TColor($00FF00);   // lime: what the canvas held before the painter came
  { Mean channel distance allowed between an image drawn at S = 2 and averaged down, and the same
    image at S = 1. Measured when set (2026-10-18): 0.00 for the nine-slices and the image fills,
    0.95 for the nine-slice background, 0.11 for the blurred fill; with the image taken as device
    pixels (drawn at half its size) 22.16, 13.72 and 10.99, and 3.97 with the blur at the raster
    radius. }
  CImageApart = 2.0;

function IsRed(const C: TBGRAPixel): Boolean;
function IsBlue(const C: TBGRAPixel): Boolean;
function IsSentinel(const C: TBGRAPixel): Boolean;
function PxStr(const C: TBGRAPixel): string;

implementation

function IsRed(const C: TBGRAPixel): Boolean;
begin
  Result := (C.red > 200) and (C.green < 60) and (C.blue < 60);
end;

function IsBlue(const C: TBGRAPixel): Boolean;
begin
  Result := (C.red < 60) and (C.green < 60) and (C.blue > 200);
end;

function IsSentinel(const C: TBGRAPixel): Boolean;
begin
  Result := (C.red < 60) and (C.green > 200) and (C.blue < 60);
end;

function PxStr(const C: TBGRAPixel): string;
begin
  Result := Format('(%d,%d,%d,%d)', [C.red, C.green, C.blue, C.alpha]);
end;

function TDeviceScalePainterTest.NewCanvas(AW, AH: Integer): TCanvas;
begin
  FreeAndNil(FCanvasBmp);
  FCanvasBmp := TBitmap.Create;
  FCanvasBmp.PixelFormat := pf32bit;
  FCanvasBmp.SetSize(AW, AH);
  FCanvasBmp.Canvas.Brush.Color := CSentinel;
  FCanvasBmp.Canvas.FillRect(0, 0, AW, AH);
  Result := FCanvasBmp.Canvas;
end;

function TDeviceScalePainterTest.PixelAt(AX, AY: Integer): TBGRAPixel;
var
  b: TBGRABitmap;
begin
  b := TBGRABitmap.Create(FCanvasBmp);
  try
    Result := b.GetPixel(AX, AY);
  finally
    b.Free;
  end;
end;

procedure TDeviceScalePainterTest.TearDown;
begin
  TyForceDeviceScaleForTest(0, False);
  TyDeviceScaleRendering := True;
  FreeAndNil(FCanvasBmp);
  FreeAndNil(FBackdrop);
  inherited TearDown;
end;

procedure TDeviceScalePainterTest.TestRasterIsScaleTimesLayout;
var
  P: TTyPainter;
  c: TCanvas;
begin
  c := NewCanvas(80, 60);
  TyForceDeviceScaleForTest(2, True);
  P := TTyPainter.Create;
  try
    P.BeginPaint(c, Rect(0, 0, 40, 30), 96);
    AssertEquals('the layer is S times the layout width', 80, P.Bitmap.Width);
    AssertEquals('and height', 60, P.Bitmap.Height);
    AssertEquals('DeviceScale', 2, P.DeviceScale);
    AssertEquals('RasterPPI', 192, P.RasterPPI);
    AssertEquals('PPI stays the layout PPI', 96, P.PPI);
    AssertEquals('Scale stays in layout px', 10, P.Scale(10));
    AssertEquals('Dev(10)', 20, P.Dev(10));
    AssertTrue('Dev(rect)', EqualRect(Rect(2, 4, 6, 8), P.Dev(Rect(1, 2, 3, 4))));
    AssertEquals('Dev(point).X', 6, P.Dev(Point(3, 4)).X);
    AssertEquals('Dev(point).Y', 8, P.Dev(Point(3, 4)).Y);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestScaleOneLeavesCanvas2DAlone;
var
  P: TTyPainter;
  m: TAffineMatrix;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(NewCanvas(40, 30), Rect(0, 0, 40, 30), 96);
    m := P.Bitmap.Canvas2D.matrix;
    AssertTrue('S = 1: the Canvas2D matrix is the identity',
      (m[1, 1] = 1) and (m[1, 2] = 0) and (m[1, 3] = 0) and
      (m[2, 1] = 0) and (m[2, 2] = 1) and (m[2, 3] = 0));
    P.EndPaint;
    TyForceDeviceScaleForTest(2, True);
    P.BeginPaint(NewCanvas(80, 60), Rect(0, 0, 40, 30), 96);
    m := P.Bitmap.Canvas2D.matrix;
    AssertTrue('S = 2: the Canvas2D matrix scales by 2',
      (m[1, 1] = 2) and (m[1, 2] = 0) and (m[1, 3] = 0) and
      (m[2, 1] = 0) and (m[2, 2] = 2) and (m[2, 3] = 0));
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestDeviceUnitsLandOneToOne;
var
  P: TTyPainter;
begin
  NewCanvas(80, 60);
  TyForceDeviceScaleForTest(2, True);
  P := TTyPainter.Create;
  try
    P.BeginPaint(FCanvasBmp.Canvas, Rect(0, 0, 40, 30), 96);
    P.Bitmap.FillRect(0, 0, 2, 2, BGRA(255, 0, 0, 255), dmSet);
    P.EndPaint;
  finally
    P.Free;
  end;
  AssertTrue('raster (0,0) lands on canvas (0,0), got ' + PxStr(PixelAt(0, 0)), IsRed(PixelAt(0, 0)));
  AssertTrue('raster (1,1) lands on canvas (1,1), got ' + PxStr(PixelAt(1, 1)), IsRed(PixelAt(1, 1)));
  AssertTrue('canvas (2,2) untouched, got ' + PxStr(PixelAt(2, 2)), IsSentinel(PixelAt(2, 2)));
  { A layout rect off the origin lands at S times its position. }
  NewCanvas(80, 60);
  P := TTyPainter.Create;
  try
    P.BeginPaint(FCanvasBmp.Canvas, Rect(5, 6, 15, 16), 96);
    P.Bitmap.FillRect(0, 0, 2, 2, BGRA(255, 0, 0, 255), dmSet);
    P.EndPaint;
  finally
    P.Free;
  end;
  AssertTrue('layout (5,6) lands on device (10,12), got ' + PxStr(PixelAt(10, 12)),
    IsRed(PixelAt(10, 12)));
  AssertTrue('not on device (5,6), got ' + PxStr(PixelAt(5, 6)), IsSentinel(PixelAt(5, 6)));
end;

procedure TDeviceScalePainterTest.TestStretchIntoLayoutRect;
var
  P: TTyPainter;
begin
  NewCanvas(50, 40);
  TyForceDeviceScaleForTest(2, False);
  P := TTyPainter.Create;
  try
    P.BeginPaint(FCanvasBmp.Canvas, Rect(0, 0, 40, 30), 96);
    P.Bitmap.FillRect(0, 0, P.Bitmap.Width, P.Bitmap.Height, BGRA(255, 0, 0, 255), dmSet);
    P.EndPaint;
  finally
    P.Free;
  end;
  AssertTrue('inside the layout rect: red, got ' + PxStr(PixelAt(39, 29)), IsRed(PixelAt(39, 29)));
  AssertTrue('top-left too, got ' + PxStr(PixelAt(0, 0)), IsRed(PixelAt(0, 0)));
  AssertTrue('right of the layout rect: untouched, got ' + PxStr(PixelAt(45, 10)),
    IsSentinel(PixelAt(45, 10)));
  AssertTrue('below it: untouched, got ' + PxStr(PixelAt(10, 35)), IsSentinel(PixelAt(10, 35)));
end;

procedure TDeviceScalePainterTest.TestOpacityBaseAtScaleTwo;
var
  P: TTyPainter;
begin
  NewCanvas(80, 60);
  TyForceDeviceScaleForTest(2, True);
  P := TTyPainter.Create;
  try
    P.BeginPaint(FCanvasBmp.Canvas, Rect(0, 0, 40, 30), 96);
    P.Opacity := 0.5;
    P.OpacityBase := TyRGBA(0, 0, 255, 255);
    P.EndPaint;
  finally
    P.Free;
  end;
  AssertTrue('the base covers the raster''s top-left, got ' + PxStr(PixelAt(0, 0)),
    IsBlue(PixelAt(0, 0)));
  AssertTrue('and its bottom-right device pixel, got ' + PxStr(PixelAt(79, 59)),
    IsBlue(PixelAt(79, 59)));
  { Stretched into the layout rect, the base stays inside it too. }
  NewCanvas(50, 40);
  TyForceDeviceScaleForTest(2, False);
  P := TTyPainter.Create;
  try
    P.BeginPaint(FCanvasBmp.Canvas, Rect(0, 0, 20, 15), 96);
    P.Opacity := 0.5;
    P.OpacityBase := TyRGBA(0, 0, 255, 255);
    P.EndPaint;
  finally
    P.Free;
  end;
  AssertTrue('stretched: the base fills the layout rect, got ' + PxStr(PixelAt(19, 14)),
    IsBlue(PixelAt(19, 14)));
  AssertTrue('and no further, got ' + PxStr(PixelAt(30, 25)), IsSentinel(PixelAt(30, 25)));
end;

procedure TDeviceScalePainterTest.TestDegenerateRects;
var
  P: TTyPainter;
begin
  NewCanvas(20, 20);
  TyForceDeviceScaleForTest(2, True);
  P := TTyPainter.Create;
  try
    P.BeginPaint(FCanvasBmp.Canvas, Rect(0, 0, 0, 0), 96);
    P.EndPaint;
    P.BeginPaint(FCanvasBmp.Canvas, Rect(5, 5, 3, 3), 96);
    P.EndPaint;
  finally
    P.Free;
  end;
  AssertTrue('nothing drawn, got ' + PxStr(PixelAt(0, 0)), IsSentinel(PixelAt(0, 0)));
  AssertTrue('nothing drawn at (6,6) either, got ' + PxStr(PixelAt(6, 6)), IsSentinel(PixelAt(6, 6)));
end;

procedure TDeviceScalePainterTest.TestNilCanvasIsScaleOne;
var
  P: TTyPainter;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), 96);
    AssertEquals('a measuring painter draws at 1', 1, P.DeviceScale);
    AssertEquals('on a 1x1 layer', 1, P.Bitmap.Width);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestBeginPaintOnResizesToRaster;
var
  P: TTyPainter;
  surf: TBGRABitmap;
begin
  NewCanvas(80, 60);
  TyForceDeviceScaleForTest(2, True);
  surf := TBGRABitmap.Create(40, 30);
  P := TTyPainter.Create;
  try
    P.BeginPaintOn(FCanvasBmp.Canvas, Rect(0, 0, 40, 30), 96, surf);
    AssertEquals('the caller''s surface grows to the raster width', 80, surf.Width);
    AssertEquals('and height', 60, surf.Height);
    AssertTrue('and the painter draws on it', P.Bitmap = surf);
    P.EndPaint;
  finally
    P.Free;
    surf.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestScaleOneEndPaintUnchanged;
var
  P: TTyPainter;
  direct: TBGRABitmap;
  ref: TBitmap;
  a, b: TBGRABitmap;
  x, y: Integer;
begin
  { What a painter at S = 1 puts on the canvas is what drawing its layer straight onto the
    canvas always put there. }
  NewCanvas(40, 30);
  P := TTyPainter.Create;
  try
    P.BeginPaint(FCanvasBmp.Canvas, Rect(0, 0, 40, 30), 96);
    P.Bitmap.FillRect(3, 4, 20, 18, BGRA(200, 30, 40, 160), dmSet);
    P.Bitmap.FillRect(10, 10, 35, 25, BGRA(20, 60, 220, 255), dmDrawWithTransparency);
    P.EndPaint;
  finally
    P.Free;
  end;
  ref := TBitmap.Create;
  direct := TBGRABitmap.Create(40, 30, BGRAPixelTransparent);
  try
    ref.PixelFormat := pf32bit;
    ref.SetSize(40, 30);
    ref.Canvas.Brush.Color := CSentinel;
    ref.Canvas.FillRect(0, 0, 40, 30);
    direct.FillRect(3, 4, 20, 18, BGRA(200, 30, 40, 160), dmSet);
    direct.FillRect(10, 10, 35, 25, BGRA(20, 60, 220, 255), dmDrawWithTransparency);
    direct.Draw(ref.Canvas, 0, 0, False);
    a := TBGRABitmap.Create(FCanvasBmp);
    b := TBGRABitmap.Create(ref);
    try
      for y := 0 to 29 do
        for x := 0 to 39 do
          if a.GetPixel(x, y) <> b.GetPixel(x, y) then
            Fail(Format('(%d,%d): painter %s, direct %s',
              [x, y, PxStr(a.GetPixel(x, y)), PxStr(b.GetPixel(x, y))]));
    finally
      a.Free;
      b.Free;
    end;
  finally
    direct.Free;
    ref.Free;
  end;
end;

{ ---- Task 3: equivalence at S = 2 ---- }

procedure TDeviceScalePainterTest.DrawBoth(ADraw: TPainterDraw; AW, AH: Integer;
  out AScaled, ARef: TBGRABitmap);
var
  P: TTyPainter;
begin
  P := TTyPainter.Create;
  try
    TyForceDeviceScaleForTest(2, True);
    P.BeginPaint(nil, Rect(0, 0, AW, AH), 96, FRtl);
    ADraw(P, 1);
    AScaled := P.Bitmap.Duplicate as TBGRABitmap;
    P.EndPaint;
    TyForceDeviceScaleForTest(0, False);
    P.BeginPaint(nil, Rect(0, 0, 2 * AW, 2 * AH), 192, FRtl);
    ADraw(P, 2);
    ARef := P.Bitmap.Duplicate as TBGRABitmap;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TDeviceScalePainterTest.AssertSamePixels(const AMsg: string; A, B: TBGRABitmap);
var
  x, y, n, fx, fy: Integer;
begin
  AssertEquals(AMsg + ': width', B.Width, A.Width);
  AssertEquals(AMsg + ': height', B.Height, A.Height);
  n := 0;
  fx := -1;
  fy := -1;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y) <> B.GetPixel(x, y) then
      begin
        if n = 0 then begin fx := x; fy := y; end;
        Inc(n);
      end;
  if n > 0 then
    Fail(Format('%s: %d pixels differ; first at (%d,%d): scaled %s, reference %s',
      [AMsg, n, fx, fy, PxStr(A.GetPixel(fx, fy)), PxStr(B.GetPixel(fx, fy))]));
end;

procedure TDeviceScalePainterTest.CheckSame(const AMsg: string; ADraw: TPainterDraw);
var
  a, b: TBGRABitmap;
begin
  a := nil;
  b := nil;
  try
    DrawBoth(ADraw, 60, 40, a, b);
    AssertSamePixels(AMsg, a, b);
  finally
    a.Free;
    b.Free;
  end;
end;

function SolidFill(AColor: TTyColor): TTyFill;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkSolid;
  Result.Color := AColor;
end;

procedure TDeviceScalePainterTest.DrawFillSolid(P: TTyPainter; K: Integer);
begin
  P.FillBackground(Rect(4 * K, 3 * K, 50 * K, 35 * K), SolidFill(TyRGBA(30, 120, 220, 255)), 6);
  P.FillBackground(Rect(20 * K, 10 * K, 58 * K, 30 * K), SolidFill(TyRGBA(220, 40, 40, 150)), 0);
end;

procedure TDeviceScalePainterTest.DrawFillGradient(P: TTyPainter; K: Integer);
var
  f: TTyFill;
begin
  f := Default(TTyFill);
  f.Kind := tfkLinearGradient;
  f.GradFrom := TyRGBA(255, 200, 0, 255);
  f.GradTo := TyRGBA(0, 80, 200, 255);
  SetLength(f.GradStops, 2);
  f.GradStops[0].Color := f.GradFrom;
  f.GradStops[0].Pos := 0;
  f.GradStops[1].Color := f.GradTo;
  f.GradStops[1].Pos := 1;
  f.GradAngleDeg := 30;
  P.FillBackground(Rect(2 * K, 2 * K, 58 * K, 38 * K), f, 4);
end;

procedure TDeviceScalePainterTest.DrawFillPerCorner(P: TTyPainter; K: Integer);
begin
  P.FillBackground(Rect(5 * K, 5 * K, 55 * K, 35 * K), SolidFill(TyRGBA(10, 150, 90, 255)),
    TyCorners(0, 4, 9, 2));
end;

procedure TDeviceScalePainterTest.DrawStrokes(P: TTyPainter; K: Integer);
begin
  P.StrokeBorder(Rect(2 * K, 2 * K, 30 * K, 20 * K), 0, 1, TyRGBA(0, 0, 0, 255));
  P.StrokeBorder(Rect(32 * K, 2 * K, 58 * K, 20 * K), 5, 1, TyRGBA(200, 0, 0, 255));
  P.StrokeBorder(Rect(2 * K, 22 * K, 30 * K, 38 * K), 0, 2, TyRGBA(0, 120, 0, 255));
  P.StrokeBorder(Rect(32 * K, 22 * K, 58 * K, 38 * K), TyCorners(5, 0, 3, 7), 2, TyRGBA(0, 0, 200, 255));
end;

procedure TDeviceScalePainterTest.DrawEdges(P: TTyPainter; K: Integer);
begin
  P.DrawEdge(Rect(2 * K, 2 * K, 28 * K, 38 * K), 1, TyRGBA(255, 255, 255, 255), TyRGBA(60, 60, 60, 255));
  P.DrawEdge(Rect(30 * K, 2 * K, 58 * K, 38 * K), 2, TyRGBA(60, 60, 60, 255), TyRGBA(255, 255, 255, 255));
end;

procedure TDeviceScalePainterTest.DrawShadow(P: TTyPainter; K: Integer);
begin
  P.DropShadow(Rect(10 * K, 8 * K, 40 * K, 28 * K), 4, TyRGBA(0, 0, 0, 120), 6, Point(2, 3));
end;

procedure TDeviceScalePainterTest.DrawGlyphs(P: TTyPainter; K: Integer);
begin
  P.DrawGlyph(Rect(0, 0, 14 * K, 14 * K), tgClose, TyRGBA(0, 0, 0, 255), 1);
  P.DrawGlyph(Rect(15 * K, 0, 29 * K, 14 * K), tgCheck, TyRGBA(0, 100, 0, 255), 2);
  P.DrawGlyph(Rect(30 * K, 0, 44 * K, 14 * K), tgChevronDown, TyRGBA(0, 0, 150, 255), 1);
  P.DrawGlyph(Rect(45 * K, 0, 59 * K, 14 * K), tgTriangleUp, TyRGBA(150, 0, 0, 255), 1);
  P.DrawGlyph(Rect(0, 16 * K, 20 * K, 36 * K), tgInfo, TyRGBA(30, 30, 30, 255), 1, 2);
end;

procedure TDeviceScalePainterTest.DrawChevron(P: TTyPainter; K: Integer);
begin
  P.DrawDropChevron(Rect(10 * K, 5 * K, 30 * K, 35 * K), TyRGBA(20, 20, 20, 255), 9);
  P.DrawDropChevron(Rect(35 * K, 5 * K, 55 * K, 35 * K), TyRGBA(20, 20, 120, 255), 13);
end;

procedure TDeviceScalePainterTest.DrawCornerGaps(P: TTyPainter; K: Integer);
begin
  P.FillCornerGaps(Rect(4 * K, 4 * K, 56 * K, 36 * K), TyUniformCorners(6), TyRGBA(250, 250, 250, 255));
end;

procedure TDeviceScalePainterTest.DrawErase(P: TTyPainter; K: Integer);
begin
  P.FillBackground(Rect(0, 0, 60 * K, 40 * K), SolidFill(TyRGBA(80, 80, 80, 255)), 0);
  P.EraseRect(Rect(5 * K, 5 * K, 20 * K, 20 * K));
end;

procedure TDeviceScalePainterTest.TestFillBackgroundSolidRounded;
begin
  CheckSame('solid fills', @DrawFillSolid);
end;

procedure TDeviceScalePainterTest.TestFillBackgroundGradient;
begin
  CheckSame('gradient fill', @DrawFillGradient);
end;

procedure TDeviceScalePainterTest.TestFillBackgroundPerCorner;
begin
  CheckSame('per-corner fill', @DrawFillPerCorner);
end;

procedure TDeviceScalePainterTest.TestStrokeBorderWidths;
begin
  CheckSame('borders', @DrawStrokes);
end;

procedure TDeviceScalePainterTest.TestDrawEdge;
begin
  CheckSame('3D edges', @DrawEdges);
end;

procedure TDeviceScalePainterTest.TestDropShadow;
begin
  CheckSame('drop shadow', @DrawShadow);
end;

procedure TDeviceScalePainterTest.TestDrawGlyphKinds;
begin
  CheckSame('vector glyphs', @DrawGlyphs);
end;

procedure TDeviceScalePainterTest.TestDrawDropChevron;
begin
  CheckSame('drop chevrons', @DrawChevron);
end;

procedure TDeviceScalePainterTest.TestFillCornerGaps;
begin
  CheckSame('corner gaps', @DrawCornerGaps);
end;

procedure TDeviceScalePainterTest.TestEraseRect;
begin
  CheckSame('erase', @DrawErase);
end;

procedure TDeviceScalePainterTest.DrawDegenerate(P: TTyPainter; K: Integer);
var
  r: TRect;
  red: TTyColor;
begin
  if FDegRect = 0 then r := Rect(0, 0, 0, 0) else r := Rect(5 * K, 5 * K, 3 * K, 3 * K);
  red := TyRGBA(255, 0, 0, 255);
  case FDegMethod of
    0: P.FillBackground(r, SolidFill(red), 4);
    1: P.StrokeBorder(r, 4, 2, red);
    2: P.DrawEdge(r, 1, red, red);
    3: P.DropShadow(r, 4, red, 3, Point(1, 1));
    4: P.DrawGlyph(r, tgClose, red, 1);
    5: P.DrawDropChevron(r, red, 9);
    6: P.FillCornerGaps(r, TyUniformCorners(4), red);
    7: P.EraseRect(r);
  end;
end;

{ An empty or inverted rect at S = 2 raises nothing and draws what the same call draws at
  S = 1 on the doubled geometry -- which for most methods is nothing, and for StrokeBorder is
  the dot it has always left on an empty rect: the device scale must not change either. }
procedure TDeviceScalePainterTest.TestDegenerateRectsInScope;
const
  CNames: array[0..7] of string = ('FillBackground', 'StrokeBorder', 'DrawEdge', 'DropShadow',
    'DrawGlyph', 'DrawDropChevron', 'FillCornerGaps', 'EraseRect');
var
  i, m: Integer;
begin
  for i := 0 to 1 do
    for m := 0 to High(CNames) do
    begin
      FDegRect := i;
      FDegMethod := m;
      CheckSame(Format('%s on empty rect #%d', [CNames[m], i]), @DrawDegenerate);
    end;
end;

procedure TDeviceScalePainterTest.TestScaleAfterDrawingIsLayout;
var
  P: TTyPainter;
begin
  TyForceDeviceScaleForTest(2, True);
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 40, 30), 96);
    P.FillBackground(Rect(0, 0, 40, 30), SolidFill(TyRGBA(1, 2, 3, 255)), 4);
    AssertEquals('Scale is back in layout px after a drawing call', 10, P.Scale(10));
    AssertEquals('and PPI is the layout PPI', 96, P.PPI);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

{ ---- Task 4: text ---- }

const
  CInk: TTyColor = $FF202020;

procedure TDeviceScalePainterTest.DrawTextAligns(P: TTyPainter; K: Integer);
const
  CH: array[0..2] of TAlignment = (taLeftJustify, taCenter, taRightJustify);
  CV: array[0..2] of TTextLayout = (tlTop, tlCenter, tlBottom);
var
  i, j: Integer;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
      P.DrawText(Rect(i * 20 * K, j * 13 * K, (i + 1) * 20 * K, (j + 1) * 13 * K), 'Ag', '', 9,
        400, CInk, CH[i], CV[j], False);
end;

procedure TDeviceScalePainterTest.DrawTextEllipsis(P: TTyPainter; K: Integer);
begin
  P.DrawText(Rect(2 * K, 2 * K, 42 * K, 18 * K), 'A long English caption that will not fit', '',
    9, 400, CInk, taLeftJustify, tlCenter, True);
  P.DrawText(Rect(2 * K, 20 * K, 58 * K, 38 * K), 'Bold, too', '', 11, 700, CInk, taCenter,
    tlCenter, True);
end;

procedure TDeviceScalePainterTest.DrawTextMultiLine(P: TTyPainter; K: Integer);
begin
  P.DrawText(Rect(0, 0, 30 * K, 40 * K), '第一行'#13#10'second', '', 9, 400, CInk, taLeftJustify,
    tlCenter, False, 0, False, True);
  P.DrawText(Rect(30 * K, 0, 60 * K, 40 * K), '第一行'#13#10'second', '', 9, 400, CInk, taCenter,
    tlTop, False, 0, False, True, 20);
end;

procedure TDeviceScalePainterTest.DrawTextMnemonic(P: TTyPainter; K: Integer);
begin
  P.DrawText(Rect(2 * K, 2 * K, 58 * K, 20 * K), 'Open', '', 10, 400, CInk, taLeftJustify,
    tlCenter, False, 1);
  P.DrawText(Rect(2 * K, 20 * K, 58 * K, 38 * K), 'Save as', '', 10, 400, CInk, taCenter,
    tlCenter, False, 6);
end;

procedure TDeviceScalePainterTest.DrawTextRtl(P: TTyPainter; K: Integer);
begin
  P.DrawText(Rect(2 * K, 2 * K, 58 * K, 20 * K), 'שלום world', '', 10, 400, CInk,
    taLeftJustify, tlCenter, False);
  P.DrawText(Rect(2 * K, 20 * K, 58 * K, 38 * K), 'שלום abc', '', 10, 400, CInk,
    taLeftJustify, tlCenter, False, 1);
end;

procedure TDeviceScalePainterTest.TestDrawTextSingleLine;
begin
  CheckSame('single-line text, nine alignments', @DrawTextAligns);
end;

procedure TDeviceScalePainterTest.TestDrawTextEllipsis;
begin
  CheckSame('ellipsised and bold text', @DrawTextEllipsis);
end;

procedure TDeviceScalePainterTest.TestDrawTextMultiLine;
begin
  CheckSame('multi-line text', @DrawTextMultiLine);
end;

procedure TDeviceScalePainterTest.TestDrawTextMnemonic;
begin
  CheckSame('mnemonic underlines', @DrawTextMnemonic);
end;

procedure TDeviceScalePainterTest.TestDrawTextRtl;
begin
  FRtl := True;
  try
    CheckSame('right-to-left text', @DrawTextRtl);
  finally
    FRtl := False;
  end;
end;

procedure TDeviceScalePainterTest.TestMeasuringStaysLayout;
var
  P: TTyPainter;
  m1, m2, m3: TSize;
  c1, c2, c3, i1, i2, i3: Integer;
  r: TRect;
begin
  r := Rect(4, 2, 120, 20);
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 130, 24), 96);
    m1 := P.MeasureText('Measure me', '', 10, 400);
    c1 := P.TextCaretX(r, 'Measure me', '', 10, 400, taLeftJustify, 4);
    i1 := P.TextCharIndexAtX(r, 'Measure me', '', 10, 400, taLeftJustify, 40);
    P.EndPaint;
    TyForceDeviceScaleForTest(2, True);
    P.BeginPaint(nil, Rect(0, 0, 130, 24), 96);
    m2 := P.MeasureText('Measure me', '', 10, 400);
    c2 := P.TextCaretX(r, 'Measure me', '', 10, 400, taLeftJustify, 4);
    i2 := P.TextCharIndexAtX(r, 'Measure me', '', 10, 400, taLeftJustify, 40);
    P.DrawText(r, 'Measure me', '', 10, 400, CInk, taLeftJustify, tlCenter, False);
    m3 := P.MeasureText('Measure me', '', 10, 400);
    c3 := P.TextCaretX(r, 'Measure me', '', 10, 400, taLeftJustify, 4);
    i3 := P.TextCharIndexAtX(r, 'Measure me', '', 10, 400, taLeftJustify, 40);
    P.EndPaint;
  finally
    P.Free;
  end;
  AssertEquals('S = 2 measures the width S = 1 measures', m1.cx, m2.cx);
  AssertEquals('and the height', m1.cy, m2.cy);
  AssertEquals('caret x', c1, c2);
  AssertEquals('char index at x', i1, i2);
  AssertEquals('after drawing: width', m1.cx, m3.cx);
  AssertEquals('after drawing: height', m1.cy, m3.cy);
  AssertEquals('after drawing: caret x', c1, c3);
  AssertEquals('after drawing: char index', i1, i3);
end;

{ ---- Task 5: images, glass, glyph bitmaps ---- }

function TDeviceScalePainterTest.TestImagePath: string;
var
  b: TBGRABitmap;
  x, y: Integer;
begin
  { A 16x16 picture with structure in every direction, so a nine-slice cut, a stretch or a
    centre placement that lands one pixel off shows up. }
  Result := GetTempDir(False) + 'tydevicescale16.png';
  if FileExists(Result) then Exit;
  b := TBGRABitmap.Create(16, 16);
  try
    for y := 0 to 15 do
      for x := 0 to 15 do
        b.SetPixel(x, y, BGRA(x * 16, y * 16, ((x + y) mod 4) * 60, 255));
    b.SaveToFile(Result);
  finally
    b.Free;
  end;
end;

function TDeviceScalePainterTest.Backdrop: TBGRABitmap;
var
  x, y: Integer;
begin
  { The form's backdrop, kept at the raster size (120 x 80 for the 60 x 40 layout at S = 2). }
  if FBackdrop = nil then
  begin
    FBackdrop := TBGRABitmap.Create(120, 80);
    for y := 0 to 79 do
      for x := 0 to 119 do
        FBackdrop.SetPixel(x, y, BGRA(x * 2, y * 3, (x * y) mod 256, 255));
  end;
  Result := FBackdrop;
end;

procedure TDeviceScalePainterTest.DrawNineSlices(P: TTyPainter; K: Integer);
begin
  P.NineSlice(Rect(2 * K, 2 * K, 28 * K, 38 * K), TestImagePath, Rect(4, 4, 4, 4), False);
  P.NineSlice(Rect(32 * K, 2 * K, 58 * K, 38 * K), TestImagePath, Rect(4, 4, 4, 4), True);
end;

procedure TDeviceScalePainterTest.DrawImageFills(P: TTyPainter; K: Integer);
begin
  P.DrawImageFill(Rect(0, 0, 20 * K, 40 * K), TestImagePath, timStretch, 0);
  P.DrawImageFill(Rect(20 * K, 0, 40 * K, 40 * K), TestImagePath, timCenter, 0);
  P.DrawImageFill(Rect(40 * K, 0, 60 * K, 40 * K), TestImagePath, timCover, 2);
end;

procedure TDeviceScalePainterTest.DrawBlurredFill(P: TTyPainter; K: Integer);
begin
  P.DrawImageFill(Rect(0, 0, 60 * K, 40 * K), TestImagePath, timStretch, 3);
end;

procedure TDeviceScalePainterTest.DrawImageSlice(P: TTyPainter; K: Integer);
begin
  P.FillImageSlice(Rect(5 * K, 5 * K, 40 * K, 30 * K), Backdrop, Point(3 * K, 5 * K));
end;

procedure TDeviceScalePainterTest.DrawGlassPane(P: TTyPainter; K: Integer);
begin
  P.FillGlass(Rect(5 * K, 5 * K, 50 * K, 35 * K), Backdrop, Point(4 * K, 2 * K),
    TyRGBA(255, 255, 255, 90), TyUniformCorners(6));
end;

procedure TDeviceScalePainterTest.DrawNineSliceFill(P: TTyPainter; K: Integer);
var
  f: TTyFill;
begin
  f := Default(TTyFill);
  f.Kind := tfkNineSlice;
  f.ImagePath := TestImagePath;
  f.SliceInsets := Rect(4, 4, 4, 4);
  P.FillBackground(Rect(3 * K, 3 * K, 57 * K, 37 * K), f, 0);
end;

procedure TDeviceScalePainterTest.DrawAtBothScales(ADraw: TPainterDraw; out AHalf, ARef: TBGRABitmap);
var
  P: TTyPainter;
  raster: TBGRABitmap;
begin
  P := TTyPainter.Create;
  try
    TyForceDeviceScaleForTest(2, True);
    try
      P.BeginPaint(nil, Rect(0, 0, 60, 40), 96, FRtl);
      ADraw(P, 1);
      raster := P.Bitmap.Duplicate as TBGRABitmap;
      P.EndPaint;
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    try
      AHalf := TyHalve(raster);
    finally
      raster.Free;
    end;
    P.BeginPaint(nil, Rect(0, 0, 60, 40), 96, FRtl);
    ADraw(P, 1);
    ARef := P.Bitmap.Duplicate as TBGRABitmap;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TDeviceScalePainterTest.CheckLikeOneTimes(const AMsg: string; ADraw: TPainterDraw;
  ATolerance: Double);
var
  half, ref: TBGRABitmap;
  x, y, d: Integer;
  sum: Int64;
  pa, pb: TBGRAPixel;
  mean: Double;
begin
  DrawAtBothScales(ADraw, half, ref);
  try
    AssertEquals(AMsg + ': width', ref.Width, half.Width);
    sum := 0;
    for y := 0 to ref.Height - 1 do
      for x := 0 to ref.Width - 1 do
      begin
        pa := half.GetPixel(x, y);
        pb := ref.GetPixel(x, y);
        d := pa.red; d := Abs(d - pb.red); Inc(sum, d);
        d := pa.green; d := Abs(d - pb.green); Inc(sum, d);
        d := pa.blue; d := Abs(d - pb.blue); Inc(sum, d);
        d := pa.alpha; d := Abs(d - pb.alpha); Inc(sum, d);
      end;
    mean := sum / (4.0 * ref.Width * ref.Height);
    AssertTrue(Format('%s: S = 2 averaged down is S = 1 (mean %.2f apart, at most %.2f)',
      [AMsg, mean, ATolerance]), mean <= ATolerance);
  finally
    half.Free;
    ref.Free;
  end;
end;

function TDeviceScalePainterTest.PaintNineSliceAt(AScale: Integer; const APath: string): TBGRABitmap;
var
  P: TTyPainter;
begin
  P := TTyPainter.Create;
  try
    if AScale > 1 then TyForceDeviceScaleForTest(AScale, True);
    try
      P.BeginPaint(nil, Rect(0, 0, 60, 40), 96);
      P.NineSlice(Rect(2, 2, 58, 38), APath, Rect(4, 4, 4, 4), True);
      Result := P.Bitmap.Duplicate as TBGRABitmap;
      P.EndPaint;
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
  finally
    P.Free;
  end;
end;

{ On main NineSlice reads its picture from the painter's image cache (GetCachedImage), which
  owns it. The 3.0 line resampled it for the device scale and freed the original -- the
  cache's own bitmap there, a dangling entry from then on and a double free at exit. Freed
  memory is poisoned (test.danglingrefs), so a second paint through the dangling entry reads
  $7F... instead of the picture that happened to still be there. }
procedure TDeviceScalePainterTest.TestNineSliceKeepsTheCachedSource;
var
  path: string;
  img, oneBefore, twoFirst, twoAgain, oneAfter: TBGRABitmap;
  x, y: Integer;
begin
  path := GetTempDir(False) + 'tydevicescale-ninekeep.png';   // no other test caches it
  img := TBGRABitmap.Create(16, 16);
  try
    for y := 0 to 15 do
      for x := 0 to 15 do
        img.SetPixel(x, y, BGRA(255 - x * 16, y * 16, ((x * y) mod 5) * 50, 255));
    img.SaveToFile(path);
  finally
    img.Free;
  end;
  oneBefore := nil;
  twoFirst := nil;
  twoAgain := nil;
  oneAfter := nil;
  try
    oneBefore := PaintNineSliceAt(1, path);
    BeginPoison;
    try
      twoFirst := PaintNineSliceAt(2, path);
      twoAgain := PaintNineSliceAt(2, path);
      oneAfter := PaintNineSliceAt(1, path);
    finally
      EndPoison;
    end;
    AssertSamePixels('S = 2 the second time as the first', twoFirst, twoAgain);
    AssertSamePixels('S = 1 after S = 2 as before it', oneBefore, oneAfter);
  finally
    oneAfter.Free;
    twoAgain.Free;
    twoFirst.Free;
    oneBefore.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestNineSlice;
begin
  CheckLikeOneTimes('nine-slice, stretched and tiled', @DrawNineSlices, CImageApart);
end;

procedure TDeviceScalePainterTest.TestNineSliceCornersAreImagePixelsDoubled;
var
  half, ref: TBGRABitmap;
  x, y: Integer;
begin
  { DrawNineSlices: the first frame at (2, 2), insets 4: its top-left corner is image pixels
    (0..3, 0..3) at layout (2..5, 2..5). }
  DrawAtBothScales(@DrawNineSlices, half, ref);
  try
    for y := 2 to 5 do
      for x := 2 to 5 do
        AssertTrue(Format('corner pixel (%d, %d)', [x, y]), half.GetPixel(x, y) = ref.GetPixel(x, y));
  finally
    half.Free;
    ref.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestImageFillBlurIsLayoutWide;
begin
  CheckLikeOneTimes('blurred image fill', @DrawBlurredFill, CImageApart);
end;

procedure TDeviceScalePainterTest.TestDrawImageFillModes;
begin
  CheckLikeOneTimes('image fill: stretch, centre, cover with blur', @DrawImageFills, CImageApart);
end;

procedure TDeviceScalePainterTest.TestFillImageSlice;
begin
  CheckSame('backdrop slice', @DrawImageSlice);
end;

procedure TDeviceScalePainterTest.TestFillGlass;
begin
  CheckSame('glass pane', @DrawGlassPane);
end;

procedure TDeviceScalePainterTest.TestNestedCallMapsOnce;
begin
  { FillBackground with a nine-slice fill calls NineSlice from inside its own scope: the rect
    must be mapped once, at the outer call. }
  CheckLikeOneTimes('nine-slice background (nested scope)', @DrawNineSliceFill, CImageApart);
end;

procedure TDeviceScalePainterTest.TestDrawGlyphBitmapCentersRasterGlyph;
var
  P: TTyPainter;
  g: TBGRABitmap;
begin
  TyForceDeviceScaleForTest(2, True);
  g := TBGRABitmap.Create(20, 20, BGRA(255, 0, 0, 255));
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 30, 30), 96);
    { A glyph rendered for the layer (raster pixels) into a 30 x 30 layout cell: centred in the
      60 x 60 raster cell, at 1:1. }
    P.DrawGlyphBitmap(Rect(0, 0, 30, 30), g);
    AssertTrue('glyph starts at raster (20,20), got ' + PxStr(P.Bitmap.GetPixel(20, 20)),
      IsRed(P.Bitmap.GetPixel(20, 20)));
    AssertEquals('nothing at (19,19)', 0, P.Bitmap.GetPixel(19, 19).alpha);
    AssertTrue('glyph ends at raster (39,39), got ' + PxStr(P.Bitmap.GetPixel(39, 39)),
      IsRed(P.Bitmap.GetPixel(39, 39)));
    AssertEquals('nothing at (40,40)', 0, P.Bitmap.GetPixel(40, 40).alpha);
    P.EndPaint;
  finally
    P.Free;
    g.Free;
  end;
end;

function InkBox(B: TBGRABitmap): TRect;
var
  x, y: Integer;
begin
  Result := Rect(MaxInt, MaxInt, -1, -1);
  for y := 0 to B.Height - 1 do
    for x := 0 to B.Width - 1 do
      if B.GetPixel(x, y).alpha > 128 then
      begin
        if x < Result.Left then Result.Left := x;
        if y < Result.Top then Result.Top := y;
        if x + 1 > Result.Right then Result.Right := x + 1;
        if y + 1 > Result.Bottom then Result.Bottom := y + 1;
      end;
end;

procedure TDeviceScalePainterTest.TestGlyphOverrideRendersAtDeviceSize;
var
  ctl: TTyStyleController;
  P: TTyPainter;
  one, two: TRect;
begin
  ctl := TTyStyleController.Create(nil);
  P := TTyPainter.Create;
  try
    ctl.LoadThemeCss(':root { --glyph-test: "Arial" "\4D"; }');   // U+004D, 'M'
    P.BeginPaint(nil, Rect(0, 0, 40, 40), 96);
    AssertTrue('S = 1: the override draws', TyTryDrawGlyphOverride(P, ctl, Rect(0, 0, 40, 40),
      '--glyph-test', TyRGBA(0, 0, 0, 255)));
    one := InkBox(P.Bitmap);
    P.EndPaint;
    TyForceDeviceScaleForTest(2, True);
    P.BeginPaint(nil, Rect(0, 0, 40, 40), 96);
    AssertTrue('S = 2: the override draws', TyTryDrawGlyphOverride(P, ctl, Rect(0, 0, 40, 40),
      '--glyph-test', TyRGBA(0, 0, 0, 255)));
    two := InkBox(P.Bitmap);
    P.EndPaint;
  finally
    P.Free;
    ctl.Free;
  end;
  AssertTrue('S = 1 has ink', one.Right > one.Left);
  AssertTrue(Format('S = 2 ink is twice as wide (S = 1: %d, S = 2: %d)',
    [one.Right - one.Left, two.Right - two.Left]),
    Abs((two.Right - two.Left) - 2 * (one.Right - one.Left)) <= 2);
  AssertTrue(Format('and twice as tall (S = 1: %d, S = 2: %d)',
    [one.Bottom - one.Top, two.Bottom - two.Top]),
    Abs((two.Bottom - two.Top) - 2 * (one.Bottom - one.Top)) <= 2);
end;

{ ---- Task 6: the painter's Canvas2D shapes ---- }

procedure TDeviceScalePainterTest.CheckClose(const AMsg: string; ADraw: TPainterDraw;
  ATolerance: Integer);
var
  a, b: TBGRABitmap;
  x, y, n, worst, d: Integer;
  pa, pb: TBGRAPixel;
begin
  a := nil;
  b := nil;
  try
    DrawBoth(ADraw, 60, 40, a, b);
    AssertEquals(AMsg + ': width', b.Width, a.Width);
    n := 0;
    worst := 0;
    for y := 0 to a.Height - 1 do
      for x := 0 to a.Width - 1 do
      begin
        pa := a.GetPixel(x, y);
        pb := b.GetPixel(x, y);
        d := Abs(pa.red - pb.red);
        if Abs(pa.green - pb.green) > d then d := Abs(pa.green - pb.green);
        if Abs(pa.blue - pb.blue) > d then d := Abs(pa.blue - pb.blue);
        if Abs(pa.alpha - pb.alpha) > d then d := Abs(pa.alpha - pb.alpha);
        if d > worst then worst := d;
        if d > ATolerance then Inc(n);
      end;
    if n > 0 then
      Fail(Format('%s: %d pixels differ by more than %d (worst %d)', [AMsg, n, ATolerance, worst]));
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TDeviceScalePainterTest.DrawPointerShapes(P: TTyPainter; K: Integer);
begin
  P.FillPointerShape(Rect(4 * K, 8 * K, 26 * K, 18 * K), TyUniformCorners(4), tpsTop,
    14 * K, 4 * K, 5 * K, TyRGBA(250, 250, 220, 255), TyRGBA(80, 80, 80, 255), 1);
  P.FillPointerShape(Rect(34 * K, 2 * K, 56 * K, 12 * K), TyUniformCorners(3), tpsBottom,
    44 * K, 3 * K, 4 * K, TyRGBA(220, 240, 255, 255), TyRGBA(0, 90, 200, 255), 1);
  P.FillPointerShape(Rect(10 * K, 24 * K, 28 * K, 36 * K), TyUniformCorners(2), tpsLeft,
    30 * K, 3 * K, 4 * K, TyRGBA(255, 230, 230, 255), TyRGBA(200, 0, 0, 255), 2);
  P.FillPointerShape(Rect(34 * K, 24 * K, 52 * K, 36 * K), TyUniformCorners(0), tpsRight,
    30 * K, 3 * K, 4 * K, TyRGBA(230, 255, 230, 255), TyRGBA(0, 120, 0, 255), 0);
end;

procedure TDeviceScalePainterTest.DrawStars(P: TTyPainter; K: Integer);
begin
  P.DrawStar(Rect(4 * K, 4 * K, 28 * K, 28 * K), TyRGBA(250, 180, 0, 255), True);
  P.DrawStar(Rect(32 * K, 4 * K, 56 * K, 28 * K), TyRGBA(120, 120, 120, 255), False);
end;

procedure TDeviceScalePainterTest.DrawFillThenPointer(P: TTyPainter; K: Integer);
begin
  { A scoped call (FillBackground maps and switches the PPI) before an unscoped Canvas2D one:
    the scope must leave the Canvas2D transform as BeginPaint set it. }
  P.FillBackground(Rect(0, 0, 60 * K, 40 * K), SolidFill(TyRGBA(240, 240, 240, 255)), 6);
  P.FillPointerShape(Rect(10 * K, 10 * K, 40 * K, 26 * K), TyUniformCorners(4), tpsTop,
    25 * K, 4 * K, 6 * K, TyRGBA(255, 255, 255, 255), TyRGBA(60, 60, 60, 255), 1);
  { FillPointerShape set the Canvas2D transforms aside for its own call; a star drawn through
    them afterwards shows they came back. }
  P.DrawStar(Rect(42 * K, 8 * K, 58 * K, 24 * K), TyRGBA(90, 90, 90, 255), False);
end;

procedure TDeviceScalePainterTest.TestFillPointerShape;
begin
  CheckSame('pointer shapes, four sides', @DrawPointerShapes);
end;

procedure TDeviceScalePainterTest.TestDrawStar;
begin
  CheckClose('stars, filled and stroked', @DrawStars, 2);
end;

procedure TDeviceScalePainterTest.TestCanvas2DKeepsTransformAcrossPainterCalls;
begin
  CheckClose('a scoped fill, a pointer shape, then a star', @DrawFillThenPointer, 2);
end;

procedure TDeviceScalePainterTest.TestSwitchOffDrawsAtOne;
var
  P: TTyPainter;
  m: TAffineMatrix;
begin
  TyForceDeviceScaleForTest(2, True);
  TyDeviceScaleRendering := False;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 40, 30), 96);
    AssertEquals('switched off: DeviceScale 1 despite the seam', 1, P.DeviceScale);
    AssertEquals('a layout-sized layer', 40, P.Bitmap.Width);
    AssertEquals('RasterPPI = PPI', 96, P.RasterPPI);
    m := P.Bitmap.Canvas2D.matrix;
    AssertTrue('and no Canvas2D scale', (m[1, 1] = 1) and (m[2, 2] = 1));
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestDrawRuleIsDrawLineAtOne;
const
  Lines: array[0..5, 0..3] of Integer = (
    (5, 7, 50, 7), (50, 9, 5, 9),      // right, left
    (8, 3, 8, 30), (12, 30, 12, 3),    // down, up
    (20, 20, 20, 20), (0, 39, 60, 39)); // a point (nothing), the last row
var
  a, b: TTyPainter;
  i: Integer;
  red: TBGRAPixel;
begin
  red := BGRA(255, 0, 0, 255);
  a := TTyPainter.Create;
  b := TTyPainter.Create;
  try
    a.BeginPaint(nil, Rect(0, 0, 60, 40), 96);
    b.BeginPaint(nil, Rect(0, 0, 60, 40), 96);
    for i := 0 to High(Lines) do
    begin
      a.DrawRule(Lines[i, 0], Lines[i, 1], Lines[i, 2], Lines[i, 3], red);
      b.Bitmap.DrawLine(Lines[i, 0], Lines[i, 1], Lines[i, 2], Lines[i, 3], red, False);
    end;
    AssertSamePixels('DrawRule = DrawLine(…, False) at S = 1', a.Bitmap, b.Bitmap);
    a.EndPaint;
    b.EndPaint;
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestDrawRuleIsOneLayoutPixelWide;
var
  P: TTyPainter;
  ref: TBGRABitmap;
  red: TBGRAPixel;
begin
  red := BGRA(255, 0, 0, 255);
  ref := TBGRABitmap.Create(120, 80);
  P := TTyPainter.Create;
  try
    TyForceDeviceScaleForTest(2, True);
    try
      P.BeginPaint(nil, Rect(0, 0, 60, 40), 96);
      P.DrawRule(10, 5, 50, 5, red);    // x 10..49 on row 5
      P.DrawRule(50, 7, 10, 7, red);    // x 11..50 on row 7
      P.DrawRule(30, 12, 30, 36, red);  // y 12..35 in column 30
      ref.FillRect(20, 10, 100, 12, red, dmDrawWithTransparency);
      ref.FillRect(22, 14, 102, 16, red, dmDrawWithTransparency);
      ref.FillRect(60, 24, 62, 72, red, dmDrawWithTransparency);
      AssertSamePixels('DrawRule at S = 2', P.Bitmap, ref);
      P.EndPaint;
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
  finally
    P.Free;
    ref.Free;
  end;
end;

procedure TDeviceScalePainterTest.TestDrawRuleSlantedIsTheLine;
var
  a, b: TTyPainter;
  red: TBGRAPixel;
begin
  red := BGRA(255, 0, 0, 255);
  a := TTyPainter.Create;
  b := TTyPainter.Create;
  try
    a.BeginPaint(nil, Rect(0, 0, 60, 40), 96);
    b.BeginPaint(nil, Rect(0, 0, 60, 40), 96);
    a.DrawRule(5, 5, 40, 20, red);
    b.Bitmap.DrawLine(5, 5, 40, 20, red, False);
    AssertSamePixels('slanted, S = 1', a.Bitmap, b.Bitmap);
    a.EndPaint;
    b.EndPaint;
    TyForceDeviceScaleForTest(2, True);
    try
      a.BeginPaint(nil, Rect(0, 0, 60, 40), 96);
      b.BeginPaint(nil, Rect(0, 0, 60, 40), 96);
      a.DrawRule(5, 5, 40, 20, red);
      b.Bitmap.DrawLine(10, 10, 80, 40, red, False);
      AssertSamePixels('slanted, S = 2: the ends mapped', a.Bitmap, b.Bitmap);
      a.EndPaint;
      b.EndPaint;
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
  finally
    a.Free;
    b.Free;
  end;
end;

initialization
  RegisterTest(TDeviceScalePainterTest);

end.
