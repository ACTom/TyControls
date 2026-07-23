unit test.image;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, Forms, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Image;
type
  TTyImageAccess = class(TTyImage)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TImageTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestPropertyDefaults;
    procedure TestPropertyRoundTrip;
    // TyImageFitRect: concrete numbers for every mode combination.
    procedure TestFitNoneCentered;
    procedure TestFitNoneTopLeft;
    procedure TestFitStretch;
    procedure TestFitProportionalCentered;
    procedure TestFitProportionalTopLeft;
    procedure TestFitProportionalWideSource;
    procedure TestFitDegenerate;
    procedure TestFitStretchIgnoredWhenProportional;
    // Paint safety.
    procedure TestPaintEmptyPictureNoRaise;
    procedure TestPaintWithBitmapNoRaise;
  end;
implementation

procedure TTyImageAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TImageTest.TestTypeKey;
var
  I: TTyImage;
begin
  I := TTyImage.Create(nil);
  try
    // Reuses the panel surface token — no new .tycss rule.
    AssertEquals('TyImage', (I as ITyStyleable).GetStyleTypeKey);
  finally
    I.Free;
  end;
end;

procedure TImageTest.TestPropertyDefaults;
var
  I: TTyImage;
begin
  I := TTyImage.Create(nil);
  try
    AssertFalse('Stretch default False', I.Stretch);
    AssertFalse('Proportional default False', I.Proportional);
    AssertTrue('Center default True', I.Center);
    AssertTrue('Transparent default True', I.Transparent);
    AssertTrue('Picture is created (non-nil)', I.Picture <> nil);
  finally
    I.Free;
  end;
end;

procedure TImageTest.TestPropertyRoundTrip;
var
  I: TTyImage;
begin
  I := TTyImage.Create(nil);
  try
    I.Stretch := True;      AssertTrue('Stretch round-trips', I.Stretch);
    I.Proportional := True; AssertTrue('Proportional round-trips', I.Proportional);
    I.Center := False;      AssertFalse('Center round-trips', I.Center);
    I.Transparent := False; AssertFalse('Transparent round-trips', I.Transparent);
  finally
    I.Free;
  end;
end;

{ --- TyImageFitRect: exact rects for each mode combination --- }

procedure TImageTest.TestFitNoneCentered;
var
  R: TRect;
begin
  // src 100x50 into 200x200, no scale, centered -> Rect(50,75,150,125).
  R := TyImageFitRect(100, 50, 200, 200, False, False, True);
  AssertEquals('none+center left', 50, R.Left);
  AssertEquals('none+center top', 75, R.Top);
  AssertEquals('none+center right', 150, R.Right);
  AssertEquals('none+center bottom', 125, R.Bottom);
end;

procedure TImageTest.TestFitNoneTopLeft;
var
  R: TRect;
begin
  // src 100x50 into 200x200, no scale, top-left -> Rect(0,0,100,50).
  R := TyImageFitRect(100, 50, 200, 200, False, False, False);
  AssertEquals('none+topleft left', 0, R.Left);
  AssertEquals('none+topleft top', 0, R.Top);
  AssertEquals('none+topleft right', 100, R.Right);
  AssertEquals('none+topleft bottom', 50, R.Bottom);
end;

procedure TImageTest.TestFitStretch;
var
  R: TRect;
begin
  // Stretch fills the dest exactly, regardless of Center -> Rect(0,0,200,200).
  R := TyImageFitRect(100, 50, 200, 200, True, False, True);
  AssertEquals('stretch left', 0, R.Left);
  AssertEquals('stretch top', 0, R.Top);
  AssertEquals('stretch right', 200, R.Right);
  AssertEquals('stretch bottom', 200, R.Bottom);
end;

procedure TImageTest.TestFitProportionalCentered;
var
  R: TRect;
begin
  // src 100x50 into 200x200, proportional -> scale 2.0 -> 200x100, centered
  // -> Rect(0,50,200,150).
  R := TyImageFitRect(100, 50, 200, 200, False, True, True);
  AssertEquals('prop+center left', 0, R.Left);
  AssertEquals('prop+center top', 50, R.Top);
  AssertEquals('prop+center right', 200, R.Right);
  AssertEquals('prop+center bottom', 150, R.Bottom);
end;

procedure TImageTest.TestFitProportionalTopLeft;
var
  R: TRect;
begin
  // Same fit as above but top-left -> Rect(0,0,200,100).
  R := TyImageFitRect(100, 50, 200, 200, False, True, False);
  AssertEquals('prop+topleft left', 0, R.Left);
  AssertEquals('prop+topleft top', 0, R.Top);
  AssertEquals('prop+topleft right', 200, R.Right);
  AssertEquals('prop+topleft bottom', 100, R.Bottom);
end;

procedure TImageTest.TestFitProportionalWideSource;
var
  R: TRect;
begin
  // src 50x100 (portrait) into 200x200: limiting axis is height, scale 2.0 -> 100x200,
  // centered horizontally -> Rect(50,0,150,200).
  R := TyImageFitRect(50, 100, 200, 200, False, True, True);
  AssertEquals('prop portrait left', 50, R.Left);
  AssertEquals('prop portrait top', 0, R.Top);
  AssertEquals('prop portrait right', 150, R.Right);
  AssertEquals('prop portrait bottom', 200, R.Bottom);
end;

procedure TImageTest.TestFitDegenerate;
var
  R: TRect;
begin
  // Zero/negative sizes -> empty rect at origin (never raises, never negative extents).
  R := TyImageFitRect(0, 50, 200, 200, True, True, True);
  AssertEquals('degenerate empty width', 0, R.Right - R.Left);
  AssertEquals('degenerate empty height', 0, R.Bottom - R.Top);
  R := TyImageFitRect(100, 50, 0, 0, False, True, True);
  AssertEquals('degenerate dest empty width', 0, R.Right - R.Left);
  AssertEquals('degenerate dest empty height', 0, R.Bottom - R.Top);
end;

procedure TImageTest.TestFitStretchIgnoredWhenProportional;
var
  R: TRect;
begin
  // When Proportional is set, Stretch is ignored: the fit is the letterbox rect,
  // NOT the full-dest stretch. src 100x50 into 200x200 -> Rect(0,50,200,150).
  R := TyImageFitRect(100, 50, 200, 200, True, True, True);
  AssertEquals('prop wins left', 0, R.Left);
  AssertEquals('prop wins top', 50, R.Top);
  AssertEquals('prop wins right', 200, R.Right);
  AssertEquals('prop wins bottom', 150, R.Bottom);
end;

{ --- Paint safety --- }

procedure TImageTest.TestPaintEmptyPictureNoRaise;
var
  F: TCustomForm;
  I: TTyImageAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    I := TTyImageAccess.Create(F);
    I.Parent := F;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 90);
    // Empty picture: Paint must draw nothing and never dereference a nil graphic.
    I.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 90), 96);
    AssertTrue('empty-picture RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

{ Small opaque red bitmap centered into a white backdrop: the render must not raise,
  and the centre pixel must carry the image (red), proving the composite path ran. }
procedure TImageTest.TestPaintWithBitmapNoRaise;
var
  G: TTyImageAccess;
  Src: TBitmap;
  Dst: TBitmap;
  Reread: TBGRABitmap;
  px: TBGRAPixel;
begin
  G := TTyImageAccess.Create(nil);
  Src := TBitmap.Create;
  Dst := TBitmap.Create;
  try
    G.Font.PixelsPerInch := 96;
    // A 40x40 solid red source assigned to the Picture. pf24bit (no alpha channel)
    // so BGRA loads it fully opaque — a pf32bit LCL bitmap can carry zeroed alpha,
    // which dmDrawWithTransparency would then draw as invisible.
    Src.PixelFormat := pf24bit;
    Src.SetSize(40, 40);
    Src.Canvas.Brush.Color := clRed;
    Src.Canvas.FillRect(0, 0, 40, 40);
    G.Picture.Assign(Src);
    G.Center := True;   // native size, centered in the 120x120 client

    Dst.PixelFormat := pf32bit;
    Dst.SetSize(120, 120);
    Dst.Canvas.Brush.Color := clWhite;
    Dst.Canvas.FillRect(0, 0, 120, 120);
    G.RenderTo(Dst.Canvas, Rect(0, 0, 120, 120), 96);

    Reread := TBGRABitmap.Create(Dst);
    try
      // Centre pixel sits inside the centered 40x40 red block -> red-dominant.
      px := Reread.GetPixel(60, 60);
      AssertTrue('centre pixel carries the image (red-dominant)',
        (px.red > 150) and (px.green < 100) and (px.blue < 100));
      // A far corner is outside the image -> the white backdrop shows through
      // (Transparent default: no panel fill painted).
      px := Reread.GetPixel(4, 4);
      AssertTrue('corner shows the transparent backdrop (white)',
        (px.red > 200) and (px.green > 200) and (px.blue > 200));
    finally
      Reread.Free;
    end;
  finally
    Dst.Free;
    Src.Free;
    G.Free;
  end;
end;

initialization
  RegisterTest(TImageTest);
end.
