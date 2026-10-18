unit test.devicescale.canvasimages;
{$mode objfpc}{$H+}

{ #83: icons drawn on the CANVAS -- after the painter's layer, through GDI -- at the device scale.

  A tree's node icons and a menu's LCL-list icons are drawn onto the control's canvas once the
  layer is down (anything drawn on the canvas before it would be covered). On a Retina screen
  that canvas is in layout units, points, and the system maps each one onto S device pixels: an
  icon drawn there at its one-times size is pixel-doubled. TyDrawImage and TyDrawResolutionScaled
  take the icon at S times its size and draw it into the layout rectangle. On a canvas in DEVICE
  units -- a raster cache, the tests' seam -- they draw it 1:1 at S times the place. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, GraphType, ImgList, Menus, fpcunit,
  testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Painter, tyControls.ImageCollection, tyControls.ImageDraw, tyControls.Menu,
  test.devicescale.support;

type
  TDeviceScaleCanvasImagesTest = class(TDeviceScaleCase)
  private
    FTwoSizes: TImageList;
    function TwoSizes: TImageList;
    function BuildMenu(AParent: TWinControl; APPI: Integer): TControl;
  protected
    procedure TearDown; override;
  published
    procedure TestVectorListRendersTheRasterSize;
    procedure TestLclListTakesItsRasterResolution;
    procedure TestOneSizeLclListIsStretched;
    procedure TestDeviceUnitsCanvasTakesTheRasterPlace;
    procedure TestGhostedStaysGhosted;
    procedure TestResolutionAtScaleTwoFillsTheLayoutRect;
    { The menu's LCL-list icons: the raster resolution, at the place the row gives them. }
    procedure TestMenuIconTakesTheRasterResolution;
    { An LCL-list icon scaled for the device scale is kept: drawn again, it is not scaled again. }
    procedure TestForeignIconIsScaledOnce;
    { ... and is never handed out for another picture: not after Replace (which notifies
      nobody), not to the next list at a freed list's address. }
    procedure TestForeignIconFollowsTheList;
    procedure TestForeignIconIsNotTakenForAnotherList;
  end;

implementation

type
  TControlAccess = class(TControl);

const
  CRed: TColor = TColor($0000FF);
  CBlue: TColor = TColor($FF0000);

function Solid(AW, AH: Integer; AColor: TColor): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := AColor;
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

function NewTarget(AW, AH: Integer): TBitmap;
begin
  Result := Solid(AW, AH, clWhite);
end;

function PixelOf(ABmp: TBitmap; AX, AY: Integer): TColor;
var
  b: TBGRABitmap;
begin
  b := TBGRABitmap.Create(ABmp);
  try
    Result := BGRAToColor(b.GetPixel(AX, AY));
  finally
    b.Free;
  end;
end;

{ 16 px red at 96, 32 px blue for 192: which one was drawn shows in the colour. }
function TDeviceScaleCanvasImagesTest.TwoSizes: TImageList;
var
  a, b: TBitmap;
begin
  if FTwoSizes = nil then
  begin
    FTwoSizes := TImageList.Create(nil);
    FTwoSizes.Width := 16;
    FTwoSizes.Height := 16;
    FTwoSizes.Scaled := True;
    FTwoSizes.RegisterResolutions([16, 32]);   // else the 32 px image is not taken as one
    a := Solid(16, 16, CRed);
    b := Solid(32, 32, CBlue);
    try
      FTwoSizes.AddMultipleResolutions([TCustomBitmap(a), TCustomBitmap(b)]);
    finally
      a.Free;
      b.Free;
    end;
  end;
  Result := FTwoSizes;
end;

procedure TDeviceScaleCanvasImagesTest.TearDown;
begin
  FreeAndNil(FTwoSizes);
  inherited TearDown;
end;

procedure TDeviceScaleCanvasImagesTest.TestVectorListRendersTheRasterSize;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
  b: TBGRABitmap;
  target: TBitmap;
begin
  c := TTyImageCollection.Create(nil);
  v := TTyVirtualImageList.Create(nil);
  b := TBGRABitmap.Create(8, 8, BGRA(255, 0, 0, 255));
  target := NewTarget(60, 60);
  try
    c.AddBitmap('dot', b);
    v.Collection := c;
    v.Names.Add('dot');
    { A 20 px slot: the list renders its default size and twice it ahead, not 40. }
    AssertFalse('nothing at 40 before the draw', c.IsCached('dot', 40));
    TyForceDeviceScaleForTest(2, False);
    try
      TyDrawImage(target.Canvas, v, 0, 4, 4, 20, 96, False);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    AssertTrue('rendered at the raster size, 40', c.IsCached('dot', 40));
    AssertEquals('drawn into the layout slot', CRed, PixelOf(target, 14, 14));
    AssertEquals('and only there', clWhite, PixelOf(target, 40, 40));
  finally
    target.Free;
    b.Free;
    v.Free;
    c.Free;
  end;
end;

procedure TDeviceScaleCanvasImagesTest.TestLclListTakesItsRasterResolution;
var
  target: TBitmap;
begin
  target := NewTarget(40, 40);
  try
    TyDrawImage(target.Canvas, TwoSizes, 0, 4, 4, 16, 96, False);
    AssertEquals('S = 1: the 16 px image', CRed, PixelOf(target, 12, 12));
    TyForceDeviceScaleForTest(2, False);
    try
      TyDrawImage(target.Canvas, TwoSizes, 0, 4, 4, 16, 96, False);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    AssertEquals('S = 2: the 32 px image', CBlue, PixelOf(target, 12, 12));
    AssertEquals('in the layout slot', clWhite, PixelOf(target, 30, 30));
  finally
    target.Free;
  end;
end;

procedure TDeviceScaleCanvasImagesTest.TestOneSizeLclListIsStretched;
var
  il: TImageList;
  a, target: TBitmap;
begin
  il := TImageList.Create(nil);
  a := Solid(16, 16, CRed);
  target := NewTarget(80, 80);
  try
    il.Width := 16;
    il.Height := 16;
    il.Add(a, nil);
    TyForceDeviceScaleForTest(2, True);
    try
      TyDrawImage(target.Canvas, il, 0, 4, 4, 16, 96, False);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    { A raster canvas, 1:1: the 16 px image stretched to 32, at (8, 8). }
    AssertEquals('stretched: still red at the far corner', CRed, PixelOf(target, 38, 38));
    AssertEquals('not past it', clWhite, PixelOf(target, 41, 41));
  finally
    target.Free;
    a.Free;
    il.Free;
  end;
end;

procedure TDeviceScaleCanvasImagesTest.TestDeviceUnitsCanvasTakesTheRasterPlace;
var
  target: TBitmap;
begin
  target := NewTarget(80, 80);
  try
    TyForceDeviceScaleForTest(2, True);
    try
      TyDrawImage(target.Canvas, TwoSizes, 0, 4, 4, 16, 96, False);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    AssertEquals('before the place', clWhite, PixelOf(target, 6, 6));
    AssertEquals('the 32 px image at twice the place', CBlue, PixelOf(target, 9, 9));
    AssertEquals('to its end', CBlue, PixelOf(target, 39, 39));
    AssertEquals('and no further', clWhite, PixelOf(target, 41, 41));
  finally
    target.Free;
  end;
end;

procedure TDeviceScaleCanvasImagesTest.TestGhostedStaysGhosted;
var
  plain, ghost: TBitmap;
begin
  plain := NewTarget(40, 40);
  ghost := NewTarget(40, 40);
  try
    TyForceDeviceScaleForTest(2, False);
    try
      TyDrawImage(plain.Canvas, TwoSizes, 0, 4, 4, 16, 96, False);
      TyDrawImage(ghost.Canvas, TwoSizes, 0, 4, 4, 16, 96, True);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    AssertTrue('the ghosted icon is drawn differently',
      PixelOf(plain, 12, 12) <> PixelOf(ghost, 12, 12));
    AssertTrue('but drawn', PixelOf(ghost, 12, 12) <> clWhite);
  finally
    ghost.Free;
    plain.Free;
  end;
end;

procedure TDeviceScaleCanvasImagesTest.TestResolutionAtScaleTwoFillsTheLayoutRect;
var
  target: TBitmap;
  res: TScaledImageListResolution;
begin
  target := NewTarget(80, 80);
  try
    { The caller picks the resolution for the raster PPI; one that is not S times the slot (an
      unscaled list hands back its 16 px) is stretched to it. }
    res := TwoSizes.ResolutionForPPI[16, 96, 1];
    TyForceDeviceScaleForTest(2, True);
    try
      TyDrawResolutionScaled(target.Canvas, res, 0, Rect(4, 4, 20, 20), gdeNormal);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    AssertEquals('stretched to the raster slot', CRed, PixelOf(target, 38, 38));
    AssertEquals('which starts at twice the place', clWhite, PixelOf(target, 6, 6));
  finally
    target.Free;
  end;
end;

function TDeviceScaleCanvasImagesTest.BuildMenu(AParent: TWinControl; APPI: Integer): TControl;
var
  v: TTyMenuView;
  mm: TMainMenu;
  top, it: TMenuItem;
begin
  mm := TMainMenu.Create(AParent);   // freed with the form
  mm.Images := TwoSizes;              // the LCL list: icons drawn on the canvas
  top := TMenuItem.Create(mm);
  top.Caption := 'File';
  mm.Items.Add(top);
  it := NewItem('Open', 0, False, True, nil, 0, '');
  it.ImageIndex := 0;
  top.Add(it);
  top.Add(NewItem('Save as', 0, False, True, nil, 0, ''));
  v := TTyMenuView.Create(AParent);
  v.Parent := AParent;
  TControlAccess(v).Font.PixelsPerInch := APPI;
  v.SetRows(TyBuildMenuRows(top));
  Result := v;
end;

{ The bounding box and count of the pixels of B that are AColor's dominant channel, clearly. }
function FindColour(B: TBGRABitmap; ABlue: Boolean; out ABox: TRect): Integer;
var
  x, y: Integer;
  p: TBGRAPixel;
  hit: Boolean;
begin
  Result := 0;
  ABox := Rect(MaxInt, MaxInt, -1, -1);
  for y := 0 to B.Height - 1 do
    for x := 0 to B.Width - 1 do
    begin
      p := B.GetPixel(x, y);
      if ABlue then hit := (p.blue > 200) and (p.red < 60) and (p.green < 60)
      else hit := (p.red > 200) and (p.green < 60) and (p.blue < 60);
      if hit then
      begin
        Inc(Result);
        if x < ABox.Left then ABox.Left := x;
        if y < ABox.Top then ABox.Top := y;
        if x + 1 > ABox.Right then ABox.Right := x + 1;
        if y + 1 > ABox.Bottom then ABox.Bottom := y + 1;
      end;
    end;
end;

procedure TDeviceScaleCanvasImagesTest.TestMenuIconTakesTheRasterResolution;
var
  f1, f2: TForm;
  m1, m2: TControl;
  s2, s1: TBGRABitmap;
  box1, box2: TRect;
begin
  f1 := TForm.CreateNew(nil);
  f2 := TForm.CreateNew(nil);
  s1 := nil;
  s2 := nil;
  try
    m1 := BuildMenu(f1, 96);
    m1.SetBounds(0, 0, 160, 60);
    m2 := BuildMenu(f2, 96);
    m2.SetBounds(0, 0, 160, 60);
    s1 := TyPaintOwnSurface(m1, 1);
    s2 := TyPaintOwnSurface(m2, 2);
    AssertEquals('S = 1 draws the 16 px icon', 256, FindColour(s1, False, box1));
    AssertEquals('S = 2 draws the 32 px icon', 1024, FindColour(s2, True, box2));
    AssertEquals('at twice the place: x', 2 * box1.Left, box2.Left);
    AssertEquals('at twice the place: y', 2 * box1.Top, box2.Top);
    AssertEquals('32 wide', 32, box2.Right - box2.Left);
  finally
    s1.Free;
    s2.Free;
    f2.Free;
    f1.Free;
  end;
end;

procedure TDeviceScaleCanvasImagesTest.TestForeignIconIsScaledOnce;
var
  il: TImageList;
  a, target: TBitmap;
  n: Integer;
begin
  { A picture no other check draws: the kept icons are keyed by the picture, process-wide. }
  il := TImageList.Create(nil);
  a := Solid(16, 16, TColor($3A5C7E));
  target := NewTarget(40, 40);
  try
    il.Width := 16;
    il.Height := 16;
    il.Add(a, nil);
    TyForceDeviceScaleForTest(2, False);
    try
      n := TyForeignScaledBuildCount;
      TyDrawImage(target.Canvas, il, 0, 4, 4, 16, 96, False);
      AssertEquals('scaled for the first draw', n + 1, TyForeignScaledBuildCount);
      TyDrawImage(target.Canvas, il, 0, 4, 4, 16, 96, False);
      AssertEquals('drawn again: not scaled again', n + 1, TyForeignScaledBuildCount);
      TyDrawImage(target.Canvas, il, 0, 4, 4, 16, 96, True);
      AssertEquals('ghosted is another picture', n + 2, TyForeignScaledBuildCount);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
  finally
    target.Free;
    a.Free;
    il.Free;
  end;
end;

procedure TDeviceScaleCanvasImagesTest.TestForeignIconFollowsTheList;
var
  il: TImageList;
  a, b, target: TBitmap;
begin
  il := TImageList.Create(nil);
  a := Solid(16, 16, CRed);
  b := Solid(16, 16, CBlue);
  target := NewTarget(40, 40);
  try
    il.Width := 16;
    il.Height := 16;
    il.Add(a, nil);
    TyForceDeviceScaleForTest(2, False);
    try
      TyDrawImage(target.Canvas, il, 0, 4, 4, 16, 96, False);
      AssertEquals('the first picture', CRed, PixelOf(target, 12, 12));
      il.Replace(0, b, nil);
      TyDrawImage(target.Canvas, il, 0, 4, 4, 16, 96, False);
      AssertEquals('the list''s new picture, not the kept one', CBlue, PixelOf(target, 12, 12));
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
  finally
    target.Free;
    b.Free;
    a.Free;
    il.Free;
  end;
end;

procedure TDeviceScaleCanvasImagesTest.TestForeignIconIsNotTakenForAnotherList;
var
  il: TImageList;
  a, target: TBitmap;
  colour: Integer;
  colours: array[0..1] of TColor;
begin
  colours[0] := CRed;
  colours[1] := CBlue;
  target := NewTarget(40, 40);
  try
    { A red list, drawn and freed; then a blue one -- the heap hands it the same address more
      often than not. }
    for colour := 0 to 1 do
    begin
      il := TImageList.Create(nil);
      a := Solid(16, 16, colours[colour]);
      try
        il.Width := 16;
        il.Height := 16;
        il.Add(a, nil);
        TyForceDeviceScaleForTest(2, False);
        try
          TyDrawImage(target.Canvas, il, 0, 4, 4, 16, 96, False);
        finally
          TyForceDeviceScaleForTest(0, False);
        end;
        AssertEquals('each list draws its own picture', colours[colour], PixelOf(target, 12, 12));
      finally
        a.Free;
        il.Free;
      end;
    end;
  finally
    target.Free;
  end;
end;

initialization
  RegisterTest(TDeviceScaleCanvasImagesTest);

end.
