unit test.parity.image;
{$mode objfpc}{$H+}
{ API-parity guards for tyControls.Image / tyControls.ImageCollection /
  tyControls.GlyphImageList against their LCL counterparts (TCustomImage+TImage in
  lcl/extctrls.pp + lcl/include/customimage.inc, TCustomImageList in lcl/imglist.pp).

  What is pinned here:

    1. TTyImage had NO image-list source at all. LCL's TImage can show entry N of a
       shared list instead of a private TPicture; ours could only ever show a picture,
       so one icon set could not be shared across a form.
    2. Center and Transparent carried the OPPOSITE default to the like-named LCL
       properties, so a form ported from TImage silently re-laid-out.
    3. The scaling gates (Stretch{In,Out}Enabled) and the clipping bias
       (KeepOrigin{X,Y}WhenClipped) had no equivalent: "shrink big photos, never
       enlarge small ones" and "show the top-left of an oversized scan" were
       unexpressible.
    4. Scaled drawing always interpolated. Pixel art and QR codes came out blurred
       with no way to ask for hard nearest-neighbour edges (AntialiasingMode).
    5. Nothing told the host that the picture had changed (OnPictureChanged), and
       there was no HasGraphic query.
    6. TTyVirtualImageList.Draw / TTyGlyphImageList.Draw carried LCL's METHOD NAME
       with the index and the coordinates TRANSPOSED. See TTyImageListDrawOrderTest. }
interface
uses
  Classes, SysUtils, Types, TypInfo, Controls, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Image, tyControls.ImageCollection,
  tyControls.GlyphImageList;

type
  { The published surface a .lfm converted from TImage streams into. A missing
    property is not a cosmetic gap: the form fails to LOAD. }
  TTyImagePublishedTest = class(TTestCase)
  published
    procedure TestImageListSourceIsPublished;
    procedure TestScaleGatesArePublished;
    procedure TestKeepOriginFlagsArePublished;
    procedure TestAntialiasingModeIsPublished;
    procedure TestPictureChangedEventIsPublished;
  end;

  { Same NAME, opposite DEFAULT: the worst kind, because nothing in the .lfm records
    it. LCL does not stream a property equal to its default, so a converted form
    carries no Center= / Transparent= line at all and the control has to agree. }
  TTyImageDefaultsTest = class(TTestCase)
  published
    procedure TestCenterDefaultsToFalseLikeLCL;
    procedure TestTransparentDefaultsToFalseLikeLCL;
  end;

  { The fit maths, with no control and no theme: LCL's DestRect gates, asserted as
    the numbers rather than as "it looks right". }
  TTyImageFitGateTest = class(TTestCase)
  published
    procedure TestStretchOutEnabledGatesEnlargement;
    procedure TestStretchInEnabledGatesShrinking;
    procedure TestBothGatesDefaultOnAndChangeNothing;
    procedure TestKeepOriginPinsAnOversizedPictureToTheCorner;
    procedure TestKeepOriginDoesNothingWhenThePictureFits;
  end;

  { Runtime behaviour that needed the new members. }
  TTyImageBehaviourTest = class(TTestCase)
  published
    procedure TestHasGraphicAnswersForPictureAndList;
    procedure TestPictureChangedEventFires;
    procedure TestImageIndexDrawsTheListEntry;
    procedure TestImageIndexRepaintsOnChange;
    procedure TestAutoSizeFollowsTheImageList;
    procedure TestNearestNeighbourUpscaleHasNoBlend;
    procedure TestDefaultUpscaleIsUnchangedAndAmOnSmooths;
  end;

  { TTyVirtualImageList.Draw / TTyGlyphImageList.Draw carry LCL's method NAME. The
    argument order therefore has to be LCL's too: an icon list whose Draw means
    something else than every other Draw in the ecosystem is a silent
    wrong-icon-in-the-wrong-place bug that no compiler can catch. }
  TTyImageListDrawOrderTest = class(TTestCase)
  published
    procedure TestVirtualListDrawUsesLCLArgumentOrder;
    procedure TestVirtualListDrawEnabledFalseDims;
    procedure TestVirtualListDrawDoesNotGhostTheSharedCache;
    procedure TestGlyphListDrawUsesLCLArgumentOrder;
    procedure TestDrawIndexKeepsTheExplicitSizeForm;
  end;

implementation

{ ---- helpers ---- }

{ A solid ASizePx square of AColor, as a collection master. }
function SolidBGRA(ASize: Integer; ACol: TBGRAPixel): TBGRABitmap;
begin
  Result := TBGRABitmap.Create(ASize, ASize, ACol);
end;

{ A two-entry collection: 'red' then 'blue'. Two entries is the minimum that can tell
  "drew index 0" from "drew index 1", which is exactly what a transposed argument
  order gets wrong. }
function MakeTwoColourCollection: TTyImageCollection;
var
  b: TBGRABitmap;
begin
  Result := TTyImageCollection.Create(nil);
  b := SolidBGRA(16, BGRA(255, 0, 0, 255));
  try
    Result.AddBitmap('red', b);
  finally
    b.Free;
  end;
  b := SolidBGRA(16, BGRA(0, 0, 255, 255));
  try
    Result.AddBitmap('blue', b);
  finally
    b.Free;
  end;
end;

function MakeWhiteTarget(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

{ ---- the published surface ---- }

procedure TTyImagePublishedTest.TestImageListSourceIsPublished;
var
  I: TTyImage;
begin
  // extctrls.pp:586-588 -- ImageIndex / ImageWidth / Images on TCustomImage,
  // republished on TImage. Without them a converted .lfm raises on load.
  I := TTyImage.Create(nil);
  try
    AssertTrue('Images is published', GetPropInfo(I, 'Images') <> nil);
    AssertTrue('ImageIndex is published', GetPropInfo(I, 'ImageIndex') <> nil);
    AssertTrue('ImageWidth is published', GetPropInfo(I, 'ImageWidth') <> nil);
    AssertEquals('ImageIndex starts at LCL''s -1 sentinel', -1, I.ImageIndex);
    AssertEquals('ImageWidth default 0 = the list''s own size', 0, I.ImageWidth);
  finally
    I.Free;
  end;
end;

procedure TTyImagePublishedTest.TestScaleGatesArePublished;
var
  I: TTyImage;
begin
  I := TTyImage.Create(nil);
  try
    AssertTrue('StretchInEnabled is published',
      GetPropInfo(I, 'StretchInEnabled') <> nil);
    AssertTrue('StretchOutEnabled is published',
      GetPropInfo(I, 'StretchOutEnabled') <> nil);
    AssertTrue('StretchInEnabled defaults True', I.StretchInEnabled);
    AssertTrue('StretchOutEnabled defaults True', I.StretchOutEnabled);
  finally
    I.Free;
  end;
end;

procedure TTyImagePublishedTest.TestKeepOriginFlagsArePublished;
var
  I: TTyImage;
begin
  I := TTyImage.Create(nil);
  try
    AssertTrue('KeepOriginXWhenClipped is published',
      GetPropInfo(I, 'KeepOriginXWhenClipped') <> nil);
    AssertTrue('KeepOriginYWhenClipped is published',
      GetPropInfo(I, 'KeepOriginYWhenClipped') <> nil);
    AssertFalse('KeepOriginXWhenClipped defaults False', I.KeepOriginXWhenClipped);
    AssertFalse('KeepOriginYWhenClipped defaults False', I.KeepOriginYWhenClipped);
  finally
    I.Free;
  end;
end;

procedure TTyImagePublishedTest.TestAntialiasingModeIsPublished;
var
  I: TTyImage;
begin
  I := TTyImage.Create(nil);
  try
    AssertTrue('AntialiasingMode is published',
      GetPropInfo(I, 'AntialiasingMode') <> nil);
    AssertTrue('defaults to amDontCare like LCL', I.AntialiasingMode = amDontCare);
  finally
    I.Free;
  end;
end;

procedure TTyImagePublishedTest.TestPictureChangedEventIsPublished;
var
  I: TTyImage;
begin
  I := TTyImage.Create(nil);
  try
    AssertTrue('OnPictureChanged is published',
      GetPropInfo(I, 'OnPictureChanged') <> nil);
  finally
    I.Free;
  end;
end;

{ ---- the two opposite defaults ---- }

procedure TTyImageDefaultsTest.TestCenterDefaultsToFalseLikeLCL;
var
  I: TTyImage;
begin
  // extctrls.pp:582 `property Center: Boolean ... default False`; customimage.inc's
  // ctor sets FCenter := False. A .lfm converted from TImage therefore has no
  // Center= line, and used to land on a control that centred anyway.
  I := TTyImage.Create(nil);
  try
    AssertFalse('Center defaults to False, as on TImage', I.Center);
  finally
    I.Free;
  end;
end;

procedure TTyImageDefaultsTest.TestTransparentDefaultsToFalseLikeLCL;
var
  I: TTyImage;
begin
  // extctrls.pp:603 `property Transparent: Boolean ... default False`.
  I := TTyImage.Create(nil);
  try
    AssertFalse('Transparent defaults to False, as on TImage', I.Transparent);
  finally
    I.Free;
  end;
end;

{ ---- the fit gates ---- }

procedure TTyImageFitGateTest.TestStretchOutEnabledGatesEnlargement;
var
  R: TRect;
begin
  { NOTE the direction. "Stretch OUT" is stretching the picture OUT to fill a bigger
    control -- ENLARGEMENT. customimage.inc's gate reads
      (FStretchOutEnabled or PicOutsidePartial) and (FStretchInEnabled or PicInside)
    and for a picture SMALLER than the control (PicOutsidePartial=False, PicInside=True)
    that reduces to FStretchOutEnabled alone. The audit worklist has these two the
    wrong way round; the code above is the authority. }
  // 50x50 into 200x200 with Stretch: enlargement allowed by default.
  R := TyImageFitRect(50, 50, 200, 200, True, False, False, True, True, False, False);
  AssertEquals('enlarges by default', 200, R.Right - R.Left);
  // ...and refused when the OUT gate is closed: native size, no scaling.
  R := TyImageFitRect(50, 50, 200, 200, True, False, False, True, False, False, False);
  AssertEquals('StretchOutEnabled=False keeps the native width', 50, R.Right - R.Left);
  AssertEquals('StretchOutEnabled=False keeps the native height', 50, R.Bottom - R.Top);
end;

procedure TTyImageFitGateTest.TestStretchInEnabledGatesShrinking;
var
  R: TRect;
begin
  // "Stretch IN" is fitting an oversized picture IN to the control -- SHRINKING.
  // 400x400 into 200x200 with Stretch: shrink allowed by default.
  R := TyImageFitRect(400, 400, 200, 200, True, False, False, True, True, False, False);
  AssertEquals('shrinks by default', 200, R.Right - R.Left);
  // ...and refused when the IN gate is closed: 1:1, and the overflow clips.
  R := TyImageFitRect(400, 400, 200, 200, True, False, False, False, True, False, False);
  AssertEquals('StretchInEnabled=False keeps the native width', 400, R.Right - R.Left);
  // The same gate governs Proportional, which is LCL's own "shrink to fit" switch.
  R := TyImageFitRect(400, 400, 200, 200, False, True, False, False, True, False, False);
  AssertEquals('and Proportional obeys it too', 400, R.Right - R.Left);
end;

procedure TTyImageFitGateTest.TestBothGatesDefaultOnAndChangeNothing;
var
  Old, New_: TRect;
begin
  // The gates are opt-OUT. Every existing form must fit exactly as it did, so the
  // 7-argument overload and the 11-argument one with the LCL defaults must agree.
  Old := TyImageFitRect(400, 200, 200, 200, False, True, True);
  New_ := TyImageFitRect(400, 200, 200, 200, False, True, True, True, True, False, False);
  AssertEquals('same left', Old.Left, New_.Left);
  AssertEquals('same top', Old.Top, New_.Top);
  AssertEquals('same right', Old.Right, New_.Right);
  AssertEquals('same bottom', Old.Bottom, New_.Bottom);
end;

procedure TTyImageFitGateTest.TestKeepOriginPinsAnOversizedPictureToTheCorner;
var
  R: TRect;
begin
  // 400x300 unscaled inside 200x200 and centred: the origin would go negative and the
  // top-left of the scan is cut away. KeepOrigin pins that axis at 0 instead.
  R := TyImageFitRect(400, 300, 200, 200, False, False, True, True, True, False, False);
  AssertEquals('centred pushes x negative', -100, R.Left);
  AssertEquals('centred pushes y negative', -50, R.Top);
  R := TyImageFitRect(400, 300, 200, 200, False, False, True, True, True, True, False);
  AssertEquals('KeepOriginX pins the left edge', 0, R.Left);
  AssertEquals('...and leaves the other axis centred', -50, R.Top);
  R := TyImageFitRect(400, 300, 200, 200, False, False, True, True, True, False, True);
  AssertEquals('KeepOriginY pins the top edge', 0, R.Top);
  AssertEquals('...and leaves the other axis centred', -100, R.Left);
end;

procedure TTyImageFitGateTest.TestKeepOriginDoesNothingWhenThePictureFits;
var
  R: TRect;
begin
  // customimage.inc only zeroes a NEGATIVE offset. A picture that fits must stay
  // centred, or the flag would silently become "top-left align".
  R := TyImageFitRect(50, 50, 200, 200, False, False, True, True, True, True, True);
  AssertEquals('still centred horizontally', 75, R.Left);
  AssertEquals('still centred vertically', 75, R.Top);
end;

{ ---- behaviour ---- }

type
  TImageAccess = class(TTyImage)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { Counts OnPictureChanged fires. }
  TFireCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

procedure TImageAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TFireCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

procedure TTyImageBehaviourTest.TestHasGraphicAnswersForPictureAndList;
var
  I: TTyImage;
  C: TTyImageCollection;
  L: TTyVirtualImageList;
  B: TBitmap;
begin
  // imglist/customimage.inc: GetHasGraphic is
  // Assigned(Picture.Graphic) or (Assigned(Images) and (ImageIndex>=0)).
  I := TTyImage.Create(nil);
  C := MakeTwoColourCollection;
  L := TTyVirtualImageList.Create(nil);
  B := TBitmap.Create;
  try
    AssertFalse('empty image has no graphic', I.HasGraphic);

    L.Collection := C;
    L.Names.Text := 'red' + LineEnding + 'blue';
    I.Images := L;
    AssertFalse('a list with ImageIndex=-1 is still nothing to draw', I.HasGraphic);
    I.ImageIndex := 1;
    AssertTrue('a valid list entry counts', I.HasGraphic);
    I.ImageIndex := 7;
    AssertFalse('an index past the end does not', I.HasGraphic);

    I.Images := nil;
    B.PixelFormat := pf24bit;
    B.SetSize(8, 8);
    // FillRect, not SetSize alone: an LCL bitmap that has never been drawn on has no
    // pixel data and reports Empty, which is exactly what HasGraphic is asking about.
    B.Canvas.Brush.Color := clRed;
    B.Canvas.FillRect(0, 0, 8, 8);
    I.Picture.Assign(B);
    AssertTrue('a picture counts', I.HasGraphic);
  finally
    B.Free;
    L.Free;
    C.Free;
    I.Free;
  end;
end;

procedure TTyImageBehaviourTest.TestPictureChangedEventFires;
var
  I: TTyImage;
  B: TBitmap;
  F: TFireCounter;
begin
  // customimage.inc PictureChanged fires it; the host uses it for a dimensions label
  // or a dirty flag. TPicture.OnChange is claimed by the control, so there was no
  // other seam.
  I := TTyImage.Create(nil);
  B := TBitmap.Create;
  F := TFireCounter.Create;
  try
    I.OnPictureChanged := @F.Handle;
    B.PixelFormat := pf24bit;
    B.SetSize(8, 8);
    I.Picture.Assign(B);
    AssertTrue('assigning a picture fires it', F.Count > 0);
    F.Count := 0;
    I.Picture.Clear;
    AssertTrue('clearing fires it too', F.Count > 0);
  finally
    F.Free;
    B.Free;
    I.Free;
  end;
end;

procedure TTyImageBehaviourTest.TestImageIndexDrawsTheListEntry;
var
  I: TImageAccess;
  C: TTyImageCollection;
  L: TTyVirtualImageList;
  Dst: TBitmap;
  Re: TBGRABitmap;
  px: TBGRAPixel;
begin
  // The point of the property: with no Picture at all, entry N of the shared list is
  // what lands on the canvas. Index 1 is BLUE, so drawing index 0 (red) would be the
  // classic off-by-one and is caught here.
  I := TImageAccess.Create(nil);
  C := MakeTwoColourCollection;
  L := TTyVirtualImageList.Create(nil);
  Dst := MakeWhiteTarget(64, 64);
  try
    L.Collection := C;
    L.Names.Text := 'red' + LineEnding + 'blue';
    I.Font.PixelsPerInch := 96;
    I.Images := L;
    I.ImageIndex := 1;
    I.Stretch := True;
    I.RenderTo(Dst.Canvas, Rect(0, 0, 64, 64), 96);
    Re := TBGRABitmap.Create(Dst);
    try
      px := Re.GetPixel(32, 32);
      AssertTrue(Format('list entry 1 (blue) reached the canvas, got %d,%d,%d',
        [px.red, px.green, px.blue]), (px.blue > 150) and (px.red < 100));
    finally
      Re.Free;
    end;
  finally
    Dst.Free;
    L.Free;
    C.Free;
    I.Free;
  end;
end;

procedure TTyImageBehaviourTest.TestImageIndexRepaintsOnChange;
var
  I: TImageAccess;
  C: TTyImageCollection;
  L: TTyVirtualImageList;
  Dst: TBitmap;
  Re: TBGRABitmap;
  px: TBGRAPixel;
begin
  // customimage.inc SetImageIndex repaints. A setter that only stored the field would
  // leave the previous icon on screen until something else invalidated the control.
  I := TImageAccess.Create(nil);
  C := MakeTwoColourCollection;
  L := TTyVirtualImageList.Create(nil);
  Dst := MakeWhiteTarget(64, 64);
  try
    L.Collection := C;
    L.Names.Text := 'red' + LineEnding + 'blue';
    I.Font.PixelsPerInch := 96;
    I.Images := L;
    I.Stretch := True;
    I.ImageIndex := 1;
    I.ImageIndex := 0;
    I.RenderTo(Dst.Canvas, Rect(0, 0, 64, 64), 96);
    Re := TBGRABitmap.Create(Dst);
    try
      px := Re.GetPixel(32, 32);
      AssertTrue('the new index is what draws', (px.red > 150) and (px.blue < 100));
    finally
      Re.Free;
    end;
  finally
    Dst.Free;
    L.Free;
    C.Free;
    I.Free;
  end;
end;

procedure TTyImageBehaviourTest.TestAutoSizeFollowsTheImageList;
var
  I: TTyImage;
  C: TTyImageCollection;
  L: TTyVirtualImageList;
begin
  // customimage.inc CalculatePreferredSize falls back to
  // Images.SizeForPPI[ImageWidth, PixelsPerInch] when there is no Picture, and
  // ImageWidth is what picks which resolution. Ours has one master per name, so
  // ImageWidth IS the requested edge; 0 means "the list's DefaultSize".
  I := TTyImage.Create(nil);
  C := MakeTwoColourCollection;
  L := TTyVirtualImageList.Create(nil);
  try
    L.Collection := C;
    L.Names.Text := 'red' + LineEnding + 'blue';
    L.DefaultSize := 24;
    I.Images := L;
    I.ImageIndex := 0;
    AssertEquals('no ImageWidth -> the list default', 24, I.ImageSize);
    I.ImageWidth := 48;
    AssertEquals('ImageWidth picks the edge', 48, I.ImageSize);
  finally
    L.Free;
    C.Free;
    I.Free;
  end;
end;

{ Stretch a 2x2 two-colour checkerboard up into a 64x64 control and report how many
  DISTINCT grey levels the result holds. Pixel repetition can only ever emit the two
  source levels; any interpolation manufactures intermediate ones. }
function DistinctGreys(AMode: TAntialiasingMode; ACol1, ACol2: TColor): Integer;
const
  EDGE = 64;
var
  I: TImageAccess;
  Src, Dst: TBitmap;
  Re: TBGRABitmap;
  x, y: Integer;
  seen: array[0..255] of Boolean;
  px: TBGRAPixel;
begin
  Result := 0;
  FillChar(seen, SizeOf(seen), 0);
  I := TImageAccess.Create(nil);
  Src := TBitmap.Create;
  Dst := MakeWhiteTarget(EDGE, EDGE);
  try
    Src.PixelFormat := pf24bit;
    Src.SetSize(2, 2);
    Src.Canvas.Pixels[0, 0] := ACol1;
    Src.Canvas.Pixels[1, 0] := ACol2;
    Src.Canvas.Pixels[0, 1] := ACol2;
    Src.Canvas.Pixels[1, 1] := ACol1;
    I.Font.PixelsPerInch := 96;
    I.Picture.Assign(Src);
    I.Stretch := True;
    I.AntialiasingMode := AMode;
    I.RenderTo(Dst.Canvas, Rect(0, 0, EDGE, EDGE), 96);
    Re := TBGRABitmap.Create(Dst);
    try
      for y := 0 to EDGE - 1 do
        for x := 0 to EDGE - 1 do
        begin
          px := Re.GetPixel(x, y);
          seen[px.green] := True;
        end;
    finally
      Re.Free;
    end;
    for x := 0 to 255 do
      if seen[x] then Inc(Result);
  finally
    Dst.Free;
    Src.Free;
    I.Free;
  end;
end;

{ Maximally different neighbours: black and white. }
function DistinctGreysHardEdge(AMode: TAntialiasingMode): Integer;
begin
  Result := DistinctGreys(AMode, clBlack, clWhite);
end;

{ NEARLY equal neighbours: the case an interpolating filter blends most obviously and a
  pixel-repeating one still leaves alone. }
function DistinctGreysSoftEdge(AMode: TAntialiasingMode): Integer;
begin
  Result := DistinctGreys(AMode, RGBToColor(100, 100, 100), RGBToColor(130, 130, 130));
end;

procedure TTyImageBehaviourTest.TestNearestNeighbourUpscaleHasNoBlend;
begin
  // amOff = "no antialiasing": pixel art, QR codes and sprite sheets must come out
  // with hard edges. Exactly two levels means nothing was blended.
  AssertEquals('amOff invents no intermediate levels on a hard edge', 2,
    DistinctGreysHardEdge(amOff));
  { ...and none on a NEAR-EQUAL seam either, which is where an interpolating filter is
    most obviously visible. This pair is the contract: whatever the backend does, amOff
    must never emit a level that was not in the source. }
  AssertEquals('amOff invents none on a near-equal seam either', 2,
    DistinctGreysSoftEdge(amOff));
  AssertTrue('and amOn, given the same seam, does blend',
    DistinctGreysSoftEdge(amOn) > 2);
end;

procedure TTyImageBehaviourTest.TestDefaultUpscaleIsUnchangedAndAmOnSmooths;
begin
  { Named for what the audit ASSUMED; kept, with the real answer, because the assumption
    is the thing worth recording. The claim was that our scaled draw "always interpolates"
    so pixel art came out blurred -- but BGRA's StretchPutImage already repeats pixels
    when enlarging a hard edge, so upscaled pixel art was, and remains, crisp under the
    default. The property is still a real gap: amDontCare guarantees NOTHING (it softens
    a near-equal seam, as the test above shows), and amOn's smoothed enlargement was
    unreachable at any setting. }
  AssertEquals('the DEFAULT path is unchanged: still hard-edged on a hard edge', 2,
    DistinctGreysHardEdge(amDontCare));
  AssertTrue('amOn genuinely smooths, which nothing could ask for before',
    DistinctGreysHardEdge(amOn) > 2);
end;

{ ---- Draw argument order ---- }

procedure TTyImageListDrawOrderTest.TestVirtualListDrawUsesLCLArgumentOrder;
var
  C: TTyImageCollection;
  L: TTyVirtualImageList;
  Dst: TBitmap;
  Re: TBGRABitmap;
  px: TBGRAPixel;
begin
  { imglist.pp:356 `Draw(ACanvas: TCanvas; AX, AY, AIndex: Integer; AEnabled: Boolean = True)`.
    Every argument here is an Integer, so a transposed order compiles silently and
    draws the wrong icon in the wrong place. Drawing entry 1 (BLUE) at (32,8) with
    every number distinct is what separates the two orders: under the old
    (AIndex, AX, AY) reading this call would have drawn entry 32 at (8,1). }
  C := MakeTwoColourCollection;
  L := TTyVirtualImageList.Create(nil);
  Dst := MakeWhiteTarget(64, 64);
  try
    L.Collection := C;
    L.Names.Text := 'red' + LineEnding + 'blue';
    L.DefaultSize := 16;
    L.Draw(Dst.Canvas, 32, 8, 1);
    Re := TBGRABitmap.Create(Dst);
    try
      px := Re.GetPixel(36, 12);
      AssertTrue(Format('blue landed at (32,8), got %d,%d,%d',
        [px.red, px.green, px.blue]), (px.blue > 150) and (px.red < 100));
      // (8,1) is where the transposed reading would have put it: still white.
      px := Re.GetPixel(10, 3);
      AssertTrue('nothing was drawn at the transposed position',
        (px.red > 200) and (px.green > 200) and (px.blue > 200));
    finally
      Re.Free;
    end;
  finally
    Dst.Free;
    L.Free;
    C.Free;
  end;
end;

procedure TTyImageListDrawOrderTest.TestVirtualListDrawEnabledFalseDims;
var
  C: TTyImageCollection;
  L: TTyVirtualImageList;
  Dst: TBitmap;
  Re: TBGRABitmap;
  onPx, offPx: TBGRAPixel;
begin
  { The trailing flag is LCL's AEnabled, NOT a Ghosted flag: they are negations of one
    another and both are Booleans, so the wrong polarity compiles and draws every icon
    disabled. That exact bug shipped once already in TTyTreeView. }
  C := MakeTwoColourCollection;
  L := TTyVirtualImageList.Create(nil);
  Dst := MakeWhiteTarget(64, 64);
  try
    L.Collection := C;
    L.Names.Text := 'red' + LineEnding + 'blue';
    L.DefaultSize := 16;
    L.Draw(Dst.Canvas, 0, 0, 1, True);
    L.Draw(Dst.Canvas, 32, 0, 1, False);
    Re := TBGRABitmap.Create(Dst);
    try
      onPx := Re.GetPixel(8, 8);
      offPx := Re.GetPixel(40, 8);
      AssertTrue('AEnabled=True draws at full strength', onPx.blue > 150);
      AssertTrue('AEnabled=False draws it faded, not absent',
        (offPx.blue > 150) and (offPx.red > onPx.red + 40));
    finally
      Re.Free;
    end;
  finally
    Dst.Free;
    L.Free;
    C.Free;
  end;
end;

procedure TTyImageListDrawOrderTest.TestVirtualListDrawDoesNotGhostTheSharedCache;
var
  C: TTyImageCollection;
  L: TTyVirtualImageList;
  Dst: TBitmap;
  Re: TBGRABitmap;
  px: TBGRAPixel;
begin
  { The cache hands out BORROWED bitmaps. Fading one in place would ghost that icon
    everywhere it is ever drawn again, including from other controls. Draw disabled
    first, then enabled, and the second draw must be at full strength. }
  C := MakeTwoColourCollection;
  L := TTyVirtualImageList.Create(nil);
  Dst := MakeWhiteTarget(64, 64);
  try
    L.Collection := C;
    L.Names.Text := 'red' + LineEnding + 'blue';
    L.DefaultSize := 16;
    L.Draw(Dst.Canvas, 0, 0, 1, False);     // disabled: must not mutate the cache
    L.Draw(Dst.Canvas, 32, 0, 1, True);
    Re := TBGRABitmap.Create(Dst);
    try
      px := Re.GetPixel(40, 8);
      AssertTrue(Format('the later full-strength draw is undimmed, got %d,%d,%d',
        [px.red, px.green, px.blue]), (px.blue > 200) and (px.red < 60));
    finally
      Re.Free;
    end;
  finally
    Dst.Free;
    L.Free;
    C.Free;
  end;
end;

procedure TTyImageListDrawOrderTest.TestGlyphListDrawUsesLCLArgumentOrder;
var
  L: TTyGlyphImageList;
  Dst: TBitmap;
begin
  // Same signature shape on the icon-font list, so the two "image lists" in this
  // library cannot disagree about what Draw's arguments mean. No IconFont is set, so
  // this asserts the CALL SHAPE and the guard against raising, not pixels.
  L := TTyGlyphImageList.Create(nil);
  Dst := MakeWhiteTarget(32, 32);
  try
    L.Glyphs.Text := 'a' + LineEnding + 'b';
    L.Draw(Dst.Canvas, 4, 4, 1);
    L.Draw(Dst.Canvas, 4, 4, 1, False);
    L.Draw(nil, 0, 0, 0);
    AssertTrue('LCL-ordered Draw exists and is safe without a font', True);
  finally
    Dst.Free;
    L.Free;
  end;
end;

procedure TTyImageListDrawOrderTest.TestDrawIndexKeepsTheExplicitSizeForm;
var
  C: TTyImageCollection;
  L: TTyVirtualImageList;
  Dst: TBitmap;
  Re: TBGRABitmap;
  px: TBGRAPixel;
begin
  { The size-carrying form did not disappear, it was RENAMED to DrawIndex -- a name
    that cannot be confused with LCL's. It keeps the (AIndex, AX, AY, ASizePx) order
    the library's own paint code was written against, so the old call site fails to
    COMPILE rather than silently transposing. }
  C := MakeTwoColourCollection;
  L := TTyVirtualImageList.Create(nil);
  Dst := MakeWhiteTarget(64, 64);
  try
    L.Collection := C;
    L.Names.Text := 'red' + LineEnding + 'blue';
    L.DrawIndex(Dst.Canvas, 1, 8, 8, 32);
    Re := TBGRABitmap.Create(Dst);
    try
      px := Re.GetPixel(24, 24);
      AssertTrue('DrawIndex still means (index, x, y, size)',
        (px.blue > 150) and (px.red < 100));
      // ...at the requested 32px edge, not the list default of 16.
      px := Re.GetPixel(36, 36);
      AssertTrue('the explicit size was honoured', (px.blue > 150) and (px.red < 100));
    finally
      Re.Free;
    end;
  finally
    Dst.Free;
    L.Free;
    C.Free;
  end;
end;

initialization
  RegisterTest(TTyImagePublishedTest);
  RegisterTest(TTyImageDefaultsTest);
  RegisterTest(TTyImageFitGateTest);
  RegisterTest(TTyImageBehaviourTest);
  RegisterTest(TTyImageListDrawOrderTest);
end.
