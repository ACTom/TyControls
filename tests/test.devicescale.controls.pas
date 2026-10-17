unit test.devicescale.controls;
{$mode objfpc}{$H+}

{ #83: controls in the states where they draw on the painter's layer directly.

  The palette sweep (test.devicescale.sweep) sees each control as it is created -- an image with
  no picture, a tree with no nodes -- so the drawing that needs content is never reached there.
  Each check here builds a control WITH that content, draws it at S = 2 and compares it with
  S = 1 (test.devicescale.support). }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.IconFont, tyControls.Image, tyControls.ImageView, tyControls.GlyphButtons,
  tyControls.CharImage, tyControls.ComboBoxEx,
  test.devicescale.support, test.devicescale.sweep;

type
  TDeviceScaleControlsTest = class(TTestCase)
  private
    FIconFont: TTyIconFont;
    FImages: TImageList;
    FMode: Integer;
    function IconFont: TTyIconFont;
    function Images: TImageList;
    procedure CheckScale(const AName: string; ABuild: TTyBuildForScale; AW, AH: Integer);
    function BuildImage(AParent: TWinControl; APPI: Integer): TControl;
    function BuildImageView(AParent: TWinControl; APPI: Integer): TControl;
    function BuildGlyphButton(AParent: TWinControl; APPI: Integer): TControl;
    function BuildCharImage(AParent: TWinControl; APPI: Integer): TControl;
    function BuildComboBoxEx(AParent: TWinControl; APPI: Integer): TControl;
  protected
    procedure TearDown; override;
  published
    { Task 9: icons and pictures. }
    procedure TestImageStretched;
    procedure TestImageCentred;
    procedure TestImageAtItsOwnSize;
    procedure TestImageFromImageList;
    procedure TestImageView;
    procedure TestGlyphButtonIcon;
    procedure TestCharImage;
    procedure TestComboBoxExImage;
  end;

{ A picture with structure in every direction, so a placement or a stretch that is off shows. }
procedure TyFillTestPicture(ABmp: TBitmap; AW, AH: Integer);

implementation

type
  TControlAccess = class(TControl);

procedure TyFillTestPicture(ABmp: TBitmap; AW, AH: Integer);
var
  x, y: Integer;
begin
  ABmp.PixelFormat := pf24bit;
  ABmp.SetSize(AW, AH);
  for y := 0 to AH - 1 do
    for x := 0 to AW - 1 do
      ABmp.Canvas.Pixels[x, y] := RGBToColor((x * 255) div AW, (y * 255) div AH,
        ((x div 4 + y div 4) mod 2) * 200);
end;

procedure TDeviceScaleControlsTest.TearDown;
begin
  FreeAndNil(FIconFont);
  FreeAndNil(FImages);
  inherited TearDown;
end;

function TDeviceScaleControlsTest.IconFont: TTyIconFont;
var
  i: Integer;
begin
  if FIconFont = nil then
  begin
    FIconFont := TTyIconFont.Create(nil);
    FIconFont.FontFamily := 'Arial';
    for i := 0 to 11 do
      FIconFont.MapGlyph('glyph' + IntToStr(i), Ord('A') + i);   // letters: a font with ink
  end;
  Result := FIconFont;
end;

function TDeviceScaleControlsTest.Images: TImageList;
var
  b: TBitmap;
begin
  if FImages = nil then
  begin
    FImages := TImageList.Create(nil);
    FImages.Width := 16;
    FImages.Height := 16;
    b := TBitmap.Create;
    try
      TyFillTestPicture(b, 16, 16);
      FImages.Add(b, nil);
    finally
      b.Free;
    end;
  end;
  Result := FImages;
end;

procedure TDeviceScaleControlsTest.CheckScale(const AName: string; ABuild: TTyBuildForScale;
  AW, AH: Integer);
var
  a, b, d: TBGRABitmap;
  score, ink, blocks: Integer;
  dir: string;
begin
  score := TyDeviceScaleMismatchPictures(ABuild, AW, AH, a, b, ink, blocks);
  try
    dir := GetEnvironmentVariable('TY_SWEEP_DIR');
    if (score > CMaxMismatch) and (dir <> '') then
    begin
      a.SaveToFile(IncludeTrailingPathDelimiter(dir) + AName + '-s2.png');
      b.SaveToFile(IncludeTrailingPathDelimiter(dir) + AName + '-ref.png');
      d := TyInkMismatchImage(a, b, CFuzzyRadius);
      d.SaveToFile(IncludeTrailingPathDelimiter(dir) + AName + '-diff.png');
      d.Free;
    end;
  finally
    a.Free;
    b.Free;
  end;
  AssertTrue(Format('%s draws at the device scale (score %d > %d: ink %d, blocks %d)',
    [AName, score, CMaxMismatch, ink, blocks]), score <= CMaxMismatch);
end;

{ ---- builders ---- }

function TDeviceScaleControlsTest.BuildImage(AParent: TWinControl; APPI: Integer): TControl;
var
  im: TTyImage;
  b: TBitmap;
begin
  im := TTyImage.Create(AParent);
  im.Parent := AParent;
  TControlAccess(im).Font.PixelsPerInch := APPI;
  if FMode = 3 then
  begin
    { From an image list instead of a picture -- a foreign (LCL) one with a 16 px bitmap
      only, which at S = 2 must still show 16 layout pixels. }
    im.Images := Images;
    im.ImageIndex := 0;
    im.Center := True;
  end
  else
  begin
    b := TBitmap.Create;
    try
      TyFillTestPicture(b, 40, 28);
      im.Picture.Assign(b);
    finally
      b.Free;
    end;
  end;
  case FMode of
    0: im.Stretch := True;
    1: im.Center := True;
  end;
  Result := im;
end;

function TDeviceScaleControlsTest.BuildImageView(AParent: TWinControl; APPI: Integer): TControl;
var
  v: TTyImageView;
  b: TBitmap;
begin
  v := TTyImageView.Create(AParent);
  v.Parent := AParent;
  TControlAccess(v).Font.PixelsPerInch := APPI;
  b := TBitmap.Create;
  try
    TyFillTestPicture(b, 60, 40);
    v.Picture.Assign(b);
  finally
    b.Free;
  end;
  Result := v;
end;

function TDeviceScaleControlsTest.BuildGlyphButton(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyGlyphButton;
begin
  g := TTyGlyphButton.Create(AParent);
  g.Parent := AParent;
  TControlAccess(g).Font.PixelsPerInch := APPI;
  g.IconFont := IconFont;
  g.GlyphName := 'glyph3';
  g.Caption := 'Save';
  Result := g;
end;

function TDeviceScaleControlsTest.BuildCharImage(AParent: TWinControl; APPI: Integer): TControl;
var
  c: TTyCharImage;
begin
  c := TTyCharImage.Create(AParent);
  c.Parent := AParent;
  TControlAccess(c).Font.PixelsPerInch := APPI;
  c.IconFont := IconFont;
  c.GlyphName := 'glyph6';
  Result := c;
end;

function TDeviceScaleControlsTest.BuildComboBoxEx(AParent: TWinControl; APPI: Integer): TControl;
var
  c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(AParent);
  c.Parent := AParent;
  TControlAccess(c).Font.PixelsPerInch := APPI;
  c.Images := Images;
  c.AddItem('First', 0);
  c.AddItem('Second', 0);
  c.ItemIndex := 0;
  Result := c;
end;

{ ---- Task 9 ---- }

procedure TDeviceScaleControlsTest.TestImageStretched;
begin
  FMode := 0;
  CheckScale('TTyImage-stretched', @BuildImage, 120, 80);
end;

procedure TDeviceScaleControlsTest.TestImageCentred;
begin
  FMode := 1;
  CheckScale('TTyImage-centred', @BuildImage, 120, 80);
end;

procedure TDeviceScaleControlsTest.TestImageAtItsOwnSize;
begin
  FMode := 2;
  CheckScale('TTyImage-own-size', @BuildImage, 120, 80);
end;

procedure TDeviceScaleControlsTest.TestImageFromImageList;
begin
  FMode := 3;
  CheckScale('TTyImage-image-list', @BuildImage, 60, 40);
end;

procedure TDeviceScaleControlsTest.TestImageView;
begin
  CheckScale('TTyImageView', @BuildImageView, 160, 120);
end;

procedure TDeviceScaleControlsTest.TestGlyphButtonIcon;
begin
  CheckScale('TTyGlyphButton-icon', @BuildGlyphButton, 110, 32);
end;

procedure TDeviceScaleControlsTest.TestCharImage;
begin
  CheckScale('TTyCharImage', @BuildCharImage, 64, 64);
end;

procedure TDeviceScaleControlsTest.TestComboBoxExImage;
begin
  CheckScale('TTyComboBoxEx-image', @BuildComboBoxEx, 160, 28);
end;

initialization
  RegisterTest(TDeviceScaleControlsTest);

end.
