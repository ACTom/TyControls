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
  tyControls.Types, tyControls.Painter;

type
  TDeviceScalePainterTest = class(TTestCase)
  private
    FCanvasBmp: TBitmap;
    function NewCanvas(AW, AH: Integer): TCanvas;
    function PixelAt(AX, AY: Integer): TBGRAPixel;
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
  end;

const
  CSentinel = TColor($00FF00);   // lime: what the canvas held before the painter came

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

initialization
  RegisterTest(TDeviceScalePainterTest);

end.
