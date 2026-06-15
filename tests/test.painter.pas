unit test.painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter;

type
  TPainterTest = class(TTestCase)
  private
    FHost: TBitmap;
    FPainter: TTyPainter;
    function MakePainter(AWidth, AHeight, APPI: Integer): TRect;
    procedure FreePainter;
    function PixelAt(X, Y: Integer): TBGRAPixel;
    function WriteTempNineSlice: string;
  protected
    procedure TearDown; override;
  published
    procedure TestColorToBGRAChannels;
    procedure TestColorToBGRATransparent;
    procedure TestSolidFillCenter;
    procedure TestSolidFillCornerTransparent;
    procedure TestLinearGradientVertical;
    procedure TestBorderPixelColor;
    procedure TestDropShadowAlpha;
    procedure TestDrawTextRastersPixels;
    procedure TestDrawGlyphAllKinds;
    procedure TestNineSliceCenterRegion;
    procedure TestEraseRectMakesTransparent;
    procedure TestPerCornerTopRoundBottomSquare;
    procedure TestFallbackFontNameApplied;
  end;

implementation

function TPainterTest.MakePainter(AWidth, AHeight, APPI: Integer): TRect;
begin
  FHost := TBitmap.Create;
  FHost.SetSize(AWidth, AHeight);
  Result := Rect(0, 0, AWidth, AHeight);
  FPainter := TTyPainter.Create;
  FPainter.BeginPaint(FHost.Canvas, Result, APPI);
end;

procedure TPainterTest.FreePainter;
begin
  if Assigned(FPainter) then
  begin
    FPainter.EndPaint;
    FreeAndNil(FPainter);
  end;
  FreeAndNil(FHost);
end;

function TPainterTest.PixelAt(X, Y: Integer): TBGRAPixel;
begin
  Result := FPainter.Bitmap.GetPixel(X, Y);
end;

procedure TPainterTest.TearDown;
begin
  FreePainter;
  inherited TearDown;
end;

procedure TPainterTest.TestColorToBGRAChannels;
var
  px: TBGRAPixel;
begin
  px := TyColorToBGRA(TyRGBA(10, 20, 30, 200));
  AssertEquals('red', 10, px.red);
  AssertEquals('green', 20, px.green);
  AssertEquals('blue', 30, px.blue);
  AssertEquals('alpha', 200, px.alpha);
end;

procedure TPainterTest.TestColorToBGRATransparent;
var
  px: TBGRAPixel;
begin
  px := TyColorToBGRA(tyTransparent);
  AssertEquals('alpha zero', 0, px.alpha);
end;

procedure TPainterTest.TestSolidFillCenter;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 0, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 10);
  px := PixelAt(20, 20);
  AssertEquals('center red', 255, px.red);
  AssertEquals('center green', 0, px.green);
  AssertEquals('center blue', 0, px.blue);
  AssertEquals('center alpha', 255, px.alpha);
end;

procedure TPainterTest.TestSolidFillCornerTransparent;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 0, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 16);
  px := PixelAt(0, 0);
  AssertEquals('corner alpha transparent', 0, px.alpha);
end;

procedure TPainterTest.TestLinearGradientVertical;
var
  fill: TTyFill;
  top, bottom: TBGRAPixel;
begin
  MakePainter(20, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkLinearGradient;
  fill.GradFrom := TyRGBA(0, 0, 0, 255);
  fill.GradTo := TyRGBA(255, 255, 255, 255);
  fill.GradAngleDeg := 90;
  FPainter.FillBackground(Rect(0, 0, 20, 40), fill, 0);
  top := PixelAt(10, 1);
  bottom := PixelAt(10, 38);
  AssertTrue('top dark', top.red < 60);
  AssertTrue('bottom light', bottom.red > 195);
  AssertEquals('top opaque', 255, top.alpha);
end;

procedure TPainterTest.TestBorderPixelColor;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(0, 255, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 0);
  FPainter.StrokeBorder(Rect(0, 0, 40, 40), 0, 4, TyRGBA(0, 0, 255, 255));
  px := PixelAt(20, 1);
  AssertTrue('border blue dominant', px.blue > 200);
  AssertTrue('border green low', px.green < 80);
  AssertEquals('border opaque', 255, px.alpha);
end;

procedure TPainterTest.TestDropShadowAlpha;
var
  px: TBGRAPixel;
begin
  MakePainter(60, 60, 96);
  FPainter.DropShadow(Rect(10, 10, 40, 40), 4, TyRGBA(0, 0, 0, 200), 6, Point(4, 4));
  px := PixelAt(44, 44);
  AssertTrue('shadow alpha present', px.alpha > 0);
  AssertTrue('shadow alpha partial', px.alpha < 200);
end;

procedure TPainterTest.TestDrawTextRastersPixels;
var
  x, y, hits: Integer;
  px: TBGRAPixel;
begin
  MakePainter(120, 40, 96);
  FPainter.DrawText(Rect(0, 0, 120, 40), 'Ty', 'DejaVu Sans', 14, 700,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  hits := 0;
  for y := 0 to 39 do
    for x := 0 to 119 do
    begin
      px := PixelAt(x, y);
      if px.alpha > 100 then
        Inc(hits);
    end;
  AssertTrue('glyph pixels rendered', hits > 0);
end;

procedure TPainterTest.TestDrawGlyphAllKinds;
var
  g: TTyGlyphKind;
  x, y, hits: Integer;
  px: TBGRAPixel;
begin
  for g := Low(TTyGlyphKind) to High(TTyGlyphKind) do
  begin
    MakePainter(24, 24, 96);
    FPainter.DrawGlyph(Rect(0, 0, 24, 24), g, TyRGBA(0, 0, 0, 255), 2);
    hits := 0;
    for y := 0 to 23 do
      for x := 0 to 23 do
      begin
        px := PixelAt(x, y);
        if px.alpha > 100 then
          Inc(hits);
      end;
    AssertTrue('glyph ' + IntToStr(Ord(g)) + ' painted', hits > 0);
    FreePainter;
  end;
end;

function TPainterTest.WriteTempNineSlice: string;
var
  bmp: TBGRABitmap;
begin
  Result := GetTempDir(False) + 'tyninetest.png';
  bmp := TBGRABitmap.Create(9, 9, BGRA(0, 0, 255, 255));
  try
    bmp.FillRect(3, 3, 6, 6, BGRA(255, 0, 0, 255), dmSet);
    bmp.SaveToFile(Result);
  finally
    bmp.Free;
  end;
end;

procedure TPainterTest.TestNineSliceCenterRegion;
var
  fn: string;
  px: TBGRAPixel;
begin
  fn := WriteTempNineSlice;
  try
    MakePainter(60, 60, 96);
    FPainter.NineSlice(Rect(0, 0, 60, 60), fn, Rect(3, 3, 3, 3));
    px := PixelAt(30, 30);
    AssertTrue('center red', px.red > 200);
    AssertTrue('center blue low', px.blue < 80);
  finally
    DeleteFile(fn);
  end;
end;

procedure TPainterTest.TestEraseRectMakesTransparent;
{ Fill the entire bitmap solid red, then EraseRect a sub-region.
  Assert the erased sub-region pixel is fully transparent (alpha=0)
  and a pixel outside the erased rect still has alpha=255. }
var
  fill: TTyFill;
  pxInside, pxOutside: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 0, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 0);
  // Erase a 10x10 sub-rect in the top-left
  FPainter.EraseRect(Rect(5, 5, 15, 15));
  pxInside := PixelAt(10, 10);
  pxOutside := PixelAt(30, 30);
  AssertEquals('erased pixel alpha = 0', 0, pxInside.alpha);
  AssertEquals('outside pixel alpha = 255 (unchanged)', 255, pxOutside.alpha);
  AssertEquals('outside pixel red = 255 (unchanged)', 255, pxOutside.red);
end;

procedure TPainterTest.TestPerCornerTopRoundBottomSquare;
{ border-radius 6 6 0 0: top corners rounded away (transparent in BGRA bitmap),
  bottom corners square (green fill reaches the corner). Read directly from the
  internal BGRA bitmap before EndPaint, consistent with all other painter tests.
  Discriminate on alpha/red:
    top-left   alpha = 0   (rounded corner cut away, transparent)
    bottom-left alpha = 255, red = $20 (square corner, fully-opaque green fill) }
var
  fill: TTyFill;
  r: TRect;
  pxTL, pxBL: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  r := Rect(0, 0, 40, 40);
  fill := Default(TTyFill);
  fill.Kind := tfkSolid;
  fill.Color := TyRGB($20, $C0, $40);       // green, red channel = $20
  FPainter.FillBackground(r, fill, TyCorners(6, 6, 0, 0));
  pxTL := FPainter.Bitmap.GetPixel(0, 0);   // top-left: rounded -> transparent
  pxBL := FPainter.Bitmap.GetPixel(1, 38);  // bottom-left: (1,38) is outside the r=6 arc centered at (6,33) (distance ~7.07 > 6), so it is filled green only when the corner is truly square
  AssertEquals('top-left rounded (transparent): alpha = 0', 0, pxTL.alpha);
  AssertEquals('bottom-left square: alpha opaque', 255, pxBL.alpha);
  AssertEquals('bottom-left green fill: red = $20', $20, pxBL.red);
end;

procedure TPainterTest.TestFallbackFontNameApplied;
{ Mechanism guard for the empty-FontName fix (no real GUI needed):
  - With TyFallbackFontName set, an empty AFontName is replaced by it.
  - A non-empty AFontName always passes through unchanged.
  - With no fallback, the empty name is preserved (original behavior). }
var
  bmp: TBGRABitmap;
  saved: string;
begin
  saved := TyFallbackFontName;
  bmp := TBGRABitmap.Create(4, 4);
  try
    TyFallbackFontName := 'Arial';
    TyConfigureTextFont(bmp, '', 9, 400, 96);
    AssertEquals('empty name uses fallback', 'Arial', bmp.FontName);
    TyConfigureTextFont(bmp, 'Verdana', 9, 400, 96);
    AssertEquals('explicit name preserved', 'Verdana', bmp.FontName);
    TyFallbackFontName := '';
    TyConfigureTextFont(bmp, '', 9, 400, 96);
    AssertEquals('no fallback => empty preserved', '', bmp.FontName);
  finally
    bmp.Free;
    TyFallbackFontName := saved;
  end;
end;

initialization
  RegisterTest(TPainterTest);

end.
