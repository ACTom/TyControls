unit test.empty;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.StrConsts, tyControls.Empty;

type
  { Pure-geometry tests: TyEmptyStackHeight / TyEmptyLayout take only integers, so they run
    with no window handle and no control instance at all. }
  TTyEmptyLayoutTest = class(TTestCase)
  published
    procedure TestStackCentredInClient;
    procedure TestImageCentredAndSquare;
    procedure TestTextSpansFullWidth;
    procedure TestHiddenBlockTakesNoGap;
    procedure TestNoBlocksAtAllIsEmpty;
    procedure TestZeroSizeClientIsEmpty;
    procedure TestInvertedClientIsEmpty;
    procedure TestOversizeImageShrinksToWidth;
    procedure TestTooTallDropsImageFirst;
    procedure TestStillTooTallStartsAtTop;
    procedure TestBlockSquashedNotOverflowed;
    procedure TestNegativeInputsCountAsAbsent;
    procedure TestClientOriginIsHonoured;
    procedure TestStackHeightSumsPresentBlocksWithGaps;
    procedure TestStackHeightIsNegativeSafe;
    procedure TestStackHeightRoundTripsThroughLayout;
  end;

  { Headless control behaviour: typeKey, defaults, the translated default message, the
    theme-token wiring (metrics + padding), the child area, preferred size, and graceful
    degradation when a theme key is undefined. }
  TTyEmptyControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    { Render E into a fresh AW x AH white bitmap and hand back the re-read pixels. The
      caller frees the result. }
    function RenderToBGRA(E: TTyEmpty; AW, AH: Integer): TBGRABitmap;
    { Whether ARect of ABmp holds a pixel matching APredicate-ish colour tests below. }
    function HasGreenIn(ABmp: TBGRABitmap; const ARect: TRect): Boolean;
    function HasBlueIn(ABmp: TBGRABitmap; const ARect: TRect): Boolean;
    function IsAllWhite(ABmp: TBGRABitmap): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestDisplayDescriptionFallsBackToTranslatedDefault;
    procedure TestImageSizeMetricSizesThePicture;
    procedure TestHiddenImageLeavesNoPictureRect;
    procedure TestGapMetricSeparatesPictureAndMessage;
    procedure TestActionBandHiddenByDefault;
    procedure TestNoActionBandCollapsesChildAreaAtTheFoot;
    procedure TestActionBandTakesThemedHeight;
    procedure TestActionBandSitsAGapBelowTheMessage;
    procedure TestThemedPaddingInsetsTheStack;
    procedure TestPreferredHeightGrowsForActionBand;
    procedure TestPreferredHeightShrinksWithoutPicture;
    procedure TestPreferredWidthClearsThePicture;
    procedure TestPreferredWidthIncludesThemedPadding;
    procedure TestUndefinedThemeKeyDrawsNothing;
    procedure TestPictureRendersItsOwnThemeInk;
    procedure TestPictureInkFallsBackToMessageInk;
    procedure TestHiddenPictureDrawsNoBox;
    procedure TestMessageRendersThemeInk;
    procedure TestActionChildRealignsWhenDisabledPaddingChanges;
  end;

implementation

const
  { The theme every render/geometry test loads unless it is testing something else. The
    metrics are PINNED rather than left to the built-in fallbacks on purpose: the theme
    pass will give every skin (and the compiled-in base layer) its own TyEmpty rules, and
    a test that leaned on the fallback constants would quietly start measuring THOSE. }
  cBaseCss =
    ':root { --empty-image-size: 48px; --empty-gap: 8px; --empty-action-height: 32px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; }';

type
  { Reaches the protected paint + measurement seams. }
  TEmptyAccess = class(TTyEmpty)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The size AutoSize would fit the placeholder to. Called directly rather than through
      AutoSize itself: LCL's AutoSizeDelayed suppresses every re-fit while the parent form
      has no handle (the headless runner never realises one), so driving AutoSize here
      would assert on inert plumbing instead of on this control's measurement. }
    procedure PreferredSize(out AWidth, AHeight: Integer);
  end;

  { Counts re-align requests. Realign (TWinControl.ReAlign) is non-virtual and forwards
    straight to the virtual AdjustSize, so spying AdjustSize catches every Realign the control
    issues — the observable action here, since headless LCL never moves a real aligned child. }
  TAlignSpyEmpty = class(TTyEmpty)
  public
    AlignCount: Integer;
    procedure AdjustSize; override;
  end;

procedure TAlignSpyEmpty.AdjustSize;
begin
  Inc(AlignCount);
  inherited AdjustSize;
end;

function TEmptyAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TEmptyAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TEmptyAccess.PreferredSize(out AWidth, AHeight: Integer);
begin
  AWidth := 0;
  AHeight := 0;
  CalculatePreferredSize(AWidth, AHeight, True);
end;

{ TTyEmptyLayoutTest }

procedure TTyEmptyLayoutTest.TestStackCentredInClient;
var
  L: TTyEmptyLayout;
begin
  // Picture 48 + gap 8 + message 16 = 72 in a 200-tall client -> 64px of air above.
  // The stack is CENTRED, not tiled: the air is what makes it read as an empty state.
  L := TyEmptyLayout(Rect(0, 0, 200, 200), 48, 16, 0, 8);
  AssertEquals('picture starts after half the slack', 64, L.ImageRect.Top);
  AssertEquals('picture is its full size', 112, L.ImageRect.Bottom);
  AssertEquals('message starts a gap below the picture', 120, L.TextRect.Top);
  AssertEquals('message band is one line tall', 136, L.TextRect.Bottom);
  AssertEquals('no action band was asked for', 0, L.ActionRect.Bottom - L.ActionRect.Top);
end;

procedure TTyEmptyLayoutTest.TestImageCentredAndSquare;
var
  L: TTyEmptyLayout;
begin
  L := TyEmptyLayout(Rect(0, 0, 200, 200), 48, 16, 0, 8);
  AssertEquals('picture centred horizontally', 76, L.ImageRect.Left);
  AssertEquals('picture right edge', 124, L.ImageRect.Right);
  AssertEquals('picture is square (w)', 48, L.ImageRect.Right - L.ImageRect.Left);
  AssertEquals('picture is square (h)', 48, L.ImageRect.Bottom - L.ImageRect.Top);
end;

procedure TTyEmptyLayoutTest.TestTextSpansFullWidth;
var
  L: TTyEmptyLayout;
begin
  // The band spans the width; the painter centres the text INSIDE it (and ellipsises).
  L := TyEmptyLayout(Rect(0, 0, 200, 200), 48, 16, 32, 8);
  AssertEquals('message band left', 0, L.TextRect.Left);
  AssertEquals('message band right', 200, L.TextRect.Right);
  AssertEquals('action band left', 0, L.ActionRect.Left);
  AssertEquals('action band right', 200, L.ActionRect.Right);
end;

procedure TTyEmptyLayoutTest.TestHiddenBlockTakesNoGap;
var
  L: TTyEmptyLayout;
begin
  // No picture: message 16 + gap 8 + action 32 = 56 -> 72px above. Hiding the picture must
  // take its AIR with it — a leading gap would push the stack off centre.
  L := TyEmptyLayout(Rect(0, 0, 200, 200), 0, 16, 32, 8);
  AssertEquals('no picture rect', 0, L.ImageRect.Bottom - L.ImageRect.Top);
  AssertEquals('message starts at half the slack, with no leading gap', 72, L.TextRect.Top);
  AssertEquals('exactly one gap between the two remaining blocks',
    8, L.ActionRect.Top - L.TextRect.Bottom);
  AssertEquals('action band is its full size', 32, L.ActionRect.Bottom - L.ActionRect.Top);
end;

procedure TTyEmptyLayoutTest.TestNoBlocksAtAllIsEmpty;
var
  L: TTyEmptyLayout;
begin
  L := TyEmptyLayout(Rect(0, 0, 200, 200), 0, 0, 0, 8);
  AssertEquals('no picture', 0, L.ImageRect.Bottom - L.ImageRect.Top);
  AssertEquals('no message', 0, L.TextRect.Bottom - L.TextRect.Top);
  AssertEquals('no action', 0, L.ActionRect.Bottom - L.ActionRect.Top);
end;

procedure TTyEmptyLayoutTest.TestZeroSizeClientIsEmpty;
var
  L: TTyEmptyLayout;
begin
  L := TyEmptyLayout(Rect(0, 0, 0, 200), 48, 16, 32, 8);
  AssertEquals('zero width: no picture', 0, L.ImageRect.Bottom - L.ImageRect.Top);
  AssertEquals('zero width: no message', 0, L.TextRect.Bottom - L.TextRect.Top);
  L := TyEmptyLayout(Rect(0, 0, 200, 0), 48, 16, 32, 8);
  AssertEquals('zero height: no picture', 0, L.ImageRect.Bottom - L.ImageRect.Top);
  AssertEquals('zero height: no message', 0, L.TextRect.Bottom - L.TextRect.Top);
end;

procedure TTyEmptyLayoutTest.TestInvertedClientIsEmpty;
var
  L: TTyEmptyLayout;
begin
  // An upside-down client must not produce negative-height bands (or crash).
  L := TyEmptyLayout(Rect(0, 50, 200, 10), 48, 16, 32, 8);
  AssertEquals('no picture', 0, L.ImageRect.Bottom - L.ImageRect.Top);
  AssertEquals('no message', 0, L.TextRect.Bottom - L.TextRect.Top);
  AssertEquals('no action', 0, L.ActionRect.Bottom - L.ActionRect.Top);
end;

procedure TTyEmptyLayoutTest.TestOversizeImageShrinksToWidth;
var
  L: TTyEmptyLayout;
begin
  // A 48px picture in a 40px-wide client shrinks to 40 rather than bleeding out the sides,
  // and stays SQUARE (so it costs 40 of height, not 48).
  L := TyEmptyLayout(Rect(0, 0, 40, 200), 48, 16, 0, 8);
  AssertEquals('picture shrank to the client width', 40, L.ImageRect.Right - L.ImageRect.Left);
  AssertEquals('and stayed square', 40, L.ImageRect.Bottom - L.ImageRect.Top);
  AssertEquals('so it sits flush', 0, L.ImageRect.Left);
  // Re-centred for the now-64px stack: (200-64) div 2 = 68.
  AssertEquals('stack re-centred for the smaller picture', 68, L.ImageRect.Top);
end;

procedure TTyEmptyLayoutTest.TestTooTallDropsImageFirst;
var
  L: TTyEmptyLayout;
begin
  // 48+8+16 = 72 does not fit 40. The picture is decoration and loses first: the message
  // is the whole reason the placeholder is on screen.
  L := TyEmptyLayout(Rect(0, 0, 200, 40), 48, 16, 0, 8);
  AssertEquals('picture dropped', 0, L.ImageRect.Bottom - L.ImageRect.Top);
  AssertEquals('message kept, and re-centred alone', 12, L.TextRect.Top);
  AssertEquals('message at full height', 28, L.TextRect.Bottom);
end;

procedure TTyEmptyLayoutTest.TestStillTooTallStartsAtTop;
var
  L: TTyEmptyLayout;
begin
  // 16+8+32 = 56 in a 20px client, with no picture left to drop. Centring would put the
  // stack at -18: instead it starts at the top, and the action band simply runs out of room.
  L := TyEmptyLayout(Rect(0, 0, 200, 20), 0, 16, 32, 8);
  AssertEquals('message starts at the client top, not above it', 0, L.TextRect.Top);
  AssertEquals('message fits whole', 16, L.TextRect.Bottom);
  AssertEquals('nothing left for the action band', 0, L.ActionRect.Bottom - L.ActionRect.Top);
end;

procedure TTyEmptyLayoutTest.TestBlockSquashedNotOverflowed;
var
  L: TTyEmptyLayout;
begin
  // A 16px message in a 10px client: squashed into what there is, never past it.
  L := TyEmptyLayout(Rect(0, 0, 200, 10), 0, 16, 0, 8);
  AssertEquals('starts at the top', 0, L.TextRect.Top);
  AssertEquals('clamped to the client bottom', 10, L.TextRect.Bottom);
end;

procedure TTyEmptyLayoutTest.TestNegativeInputsCountAsAbsent;
var
  L: TTyEmptyLayout;
begin
  // Negative sizes are "not shown", not "shown backwards".
  L := TyEmptyLayout(Rect(0, 0, 200, 200), -5, 16, -3, -4);
  AssertEquals('negative picture is absent', 0, L.ImageRect.Bottom - L.ImageRect.Top);
  AssertEquals('negative action is absent', 0, L.ActionRect.Bottom - L.ActionRect.Top);
  // Only the message is left, so a negative gap contributes nothing either: (200-16) div 2.
  AssertEquals('message centred alone', 92, L.TextRect.Top);
end;

procedure TTyEmptyLayoutTest.TestClientOriginIsHonoured;
var
  L: TTyEmptyLayout;
begin
  // The output is in the SAME space as the rect handed in — the caller may pass a padded,
  // non-zero-origin rect (the control does exactly that).
  L := TyEmptyLayout(Rect(10, 20, 210, 220), 48, 16, 0, 8);
  AssertEquals('picture centred in the offset client', 86, L.ImageRect.Left);
  AssertEquals('picture top is offset too', 84, L.ImageRect.Top);
  AssertEquals('message band spans the offset client (left)', 10, L.TextRect.Left);
  AssertEquals('message band spans the offset client (right)', 210, L.TextRect.Right);
  AssertEquals('message below the picture and its gap', 140, L.TextRect.Top);
end;

procedure TTyEmptyLayoutTest.TestStackHeightSumsPresentBlocksWithGaps;
begin
  AssertEquals('all three: 48+16+32 + 2 gaps', 112, TyEmptyStackHeight(48, 16, 32, 8));
  AssertEquals('one block: no gap at all', 16, TyEmptyStackHeight(0, 16, 0, 8));
  AssertEquals('two blocks: exactly one gap', 88, TyEmptyStackHeight(48, 0, 32, 8));
  AssertEquals('nothing shown: no height', 0, TyEmptyStackHeight(0, 0, 0, 8));
end;

procedure TTyEmptyLayoutTest.TestStackHeightIsNegativeSafe;
begin
  AssertEquals('negatives are absent blocks, not debts', 0, TyEmptyStackHeight(-1, -1, -1, -1));
  AssertEquals('a negative gap is no gap', 64, TyEmptyStackHeight(48, 16, 0, -8));
end;

procedure TTyEmptyLayoutTest.TestStackHeightRoundTripsThroughLayout;
var
  h: Integer;
  L: TTyEmptyLayout;
begin
  // The contract between the two: a client exactly TyEmptyStackHeight tall fits the stack
  // with nothing to spare — the first block flush at the top, the last flush at the bottom,
  // and each declared gap between. This is what AutoSize relies on.
  h := TyEmptyStackHeight(48, 16, 32, 8);
  AssertEquals('stack height', 112, h);
  L := TyEmptyLayout(Rect(0, 0, 200, h), 48, 16, 32, 8);
  AssertEquals('picture flush at the top', 0, L.ImageRect.Top);
  AssertEquals('action band flush at the bottom', h, L.ActionRect.Bottom);
  AssertEquals('gap kept above the message', 8, L.TextRect.Top - L.ImageRect.Bottom);
  AssertEquals('gap kept above the action', 8, L.ActionRect.Top - L.TextRect.Bottom);
end;

{ TTyEmptyControlTest }

procedure TTyEmptyControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);   // room for every placeholder the tests size
end;

procedure TTyEmptyControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TTyEmptyControlTest.RenderToBGRA(E: TTyEmpty; AW, AH: Integer): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AW, AH);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, AW, AH);
    TEmptyAccess(E).RenderTo(Bmp.Canvas, Rect(0, 0, AW, AH), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

function TTyEmptyControlTest.HasGreenIn(ABmp: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
  Px: TBGRAPixel;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= ABmp.Width) or (y >= ABmp.Height) then Continue;
      Px := ABmp.GetPixel(x, y);
      if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
        Exit(True);
    end;
end;

function TTyEmptyControlTest.HasBlueIn(ABmp: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
  Px: TBGRAPixel;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= ABmp.Width) or (y >= ABmp.Height) then Continue;
      Px := ABmp.GetPixel(x, y);
      if (Px.blue > 120) and (Px.blue > Px.red + 30) and (Px.blue > Px.green + 30) then
        Exit(True);
    end;
end;

function TTyEmptyControlTest.IsAllWhite(ABmp: TBGRABitmap): Boolean;
var
  x, y: Integer;
  Px: TBGRAPixel;
begin
  Result := True;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
    begin
      Px := ABmp.GetPixel(x, y);
      if (Px.red < 250) or (Px.green < 250) or (Px.blue < 250) then
        Exit(False);
    end;
end;

procedure TTyEmptyControlTest.TestTypeKey;
var
  E: TEmptyAccess;
begin
  E := TEmptyAccess.Create(FForm);
  E.Parent := FForm;
  try
    AssertEquals('TyEmpty', E.StyleTypeKey);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestDefaults;
var
  E: TTyEmpty;
begin
  E := TTyEmpty.Create(FForm);
  try
    AssertEquals('description blank => the translated default', '', E.Description);
    AssertTrue('picture shown by default', E.ShowImage);
    AssertTrue('message shown by default', E.ShowDescription);
    AssertFalse('no action band by default', E.ShowAction);
    AssertEquals('default width 220', 220, E.Width);
    AssertEquals('default height 140', 140, E.Height);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestDisplayDescriptionFallsBackToTranslatedDefault;
var
  E: TTyEmpty;
begin
  // A blank Description means "the library's own translated default", NOT "no message".
  // Resolving the resourcestring at draw time (rather than seeding it in the constructor)
  // is what keeps the English out of the user's .lfm and lets a language switch reach it.
  E := TTyEmpty.Create(FForm);
  try
    AssertEquals('blank => the resourcestring', rsEmptyDescription, E.DisplayDescription);
    E.Description := 'nothing here yet';
    AssertEquals('set => the user text wins', 'nothing here yet', E.DisplayDescription);
    E.Description := '';
    AssertEquals('cleared => back to the default', rsEmptyDescription, E.DisplayDescription);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestImageSizeMetricSizesThePicture;
var
  E: TTyEmpty;
  R: TRect;
begin
  // --empty-image-size is a skin-tunable metric: a theme that sets it resizes the picture,
  // proving the size is not baked into the control.
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 64px; --empty-gap: 8px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, 200, 200);
    R := E.ImageRect;
    AssertEquals('picture takes the themed size', 64, R.Right - R.Left);
    AssertEquals('and is still square', 64, R.Bottom - R.Top);
    AssertEquals('re-centred for the new size', 68, R.Left);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestHiddenImageLeavesNoPictureRect;
var
  E: TTyEmpty;
begin
  FCtl.LoadThemeCss(cBaseCss);
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, 200, 200);
    AssertTrue('picture is there by default', E.ImageRect.Bottom > E.ImageRect.Top);
    E.ShowImage := False;
    AssertEquals('no picture rect once hidden', 0, E.ImageRect.Bottom - E.ImageRect.Top);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestGapMetricSeparatesPictureAndMessage;
var
  E: TTyEmpty;
begin
  // --empty-gap is the air BETWEEN blocks, so the distance from the picture's foot to the
  // message's head is exactly the metric — whatever the font measures the message at.
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 24px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, 200, 200);
    AssertEquals('the themed gap separates picture and message',
      24, E.DescriptionRect.Top - E.ImageRect.Bottom);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestActionBandHiddenByDefault;
var
  E: TTyEmpty;
begin
  FCtl.LoadThemeCss(cBaseCss);
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, 200, 200);
    AssertEquals('no child area while ShowAction=False',
      0, E.ActionRect.Bottom - E.ActionRect.Top);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestNoActionBandCollapsesChildAreaAtTheFoot;
var
  E: TTyEmpty;
  R: TRect;
begin
  // "No action band" collapses the child area at the FOOT of the client, not to (0,0,0,0):
  // a zero rect at the origin would park a stray child on top of the picture.
  FCtl.LoadThemeCss(cBaseCss);
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, 200, 200);
    R := E.ActionRect;
    AssertEquals('collapsed to zero height', 0, R.Bottom - R.Top);
    AssertEquals('at the foot of the client, not at its origin', 200, R.Top);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestActionBandTakesThemedHeight;
var
  E: TTyEmpty;
  R: TRect;
begin
  // --empty-action-height is a skin decision (the band's proportions are part of the look),
  // so the child area a theme hands the action control comes from the token.
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 8px; --empty-action-height: 40px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.ShowAction := True;
    E.SetBounds(0, 0, 200, 200);
    R := E.ActionRect;
    AssertEquals('child area takes the themed band height', 40, R.Bottom - R.Top);
    AssertEquals('and spans the width (left)', 0, R.Left);
    AssertEquals('and spans the width (right)', 200, R.Right);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestActionBandSitsAGapBelowTheMessage;
var
  E: TTyEmpty;
begin
  // The child area is the LAST block of the same stack the paint lays out — it cannot
  // drift from the message above it, because both come from one LayoutAtPPI.
  FCtl.LoadThemeCss(cBaseCss);
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.ShowAction := True;
    E.SetBounds(0, 0, 200, 200);
    AssertEquals('action band sits exactly one themed gap below the message',
      8, E.ActionRect.Top - E.DescriptionRect.Bottom);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestThemedPaddingInsetsTheStack;
var
  E: TTyEmpty;
  R: TRect;
begin
  // The stack centres in the client inset by the THEME's padding, not in the raw client.
  // 200 wide with 90px of side padding leaves a 20px band, which the 48px picture must
  // shrink into (the width-clamp rule) — so both wirings show up in one measurement.
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 8px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; padding: 0px 90px; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, 200, 200);
    R := E.ImageRect;
    AssertEquals('picture shrank into the padded band', 20, R.Right - R.Left);
    AssertEquals('and starts at the themed left padding', 90, R.Left);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestPreferredHeightGrowsForActionBand;
var
  E: TEmptyAccess;
  w, h1, h2: Integer;
begin
  // Turning the action on adds exactly gap + band: the action is extra room, never room
  // stolen from the message.
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 6px; --empty-action-height: 40px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; }');
  E := TEmptyAccess.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.PreferredSize(w, h1);
    E.ShowAction := True;
    E.PreferredSize(w, h2);
    AssertEquals('grew by gap + band', h1 + 6 + 40, h2);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestPreferredHeightShrinksWithoutPicture;
var
  E: TEmptyAccess;
  w, h1, h2: Integer;
begin
  // And hiding the picture gives back exactly the picture AND its gap.
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 6px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; }');
  E := TEmptyAccess.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.PreferredSize(w, h1);
    E.ShowImage := False;
    E.PreferredSize(w, h2);
    AssertEquals('shrank by picture + gap', h1 - 48 - 6, h2);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestPreferredWidthClearsThePicture;
var
  E: TEmptyAccess;
  w, h: Integer;
begin
  // With the message hidden the picture alone drives the width, and it must fit exactly —
  // no padding in this theme, so the answer is the themed size and nothing else.
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 6px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; }');
  E := TEmptyAccess.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.ShowDescription := False;
    E.PreferredSize(w, h);
    AssertEquals('preferred width is the themed picture', 48, w);
    AssertEquals('and the height is the picture alone (no gap for one block)', 48, h);
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestPreferredWidthIncludesThemedPadding;
var
  E: TEmptyAccess;
  w, h: Integer;
begin
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 6px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; font-size: 12px; padding: 0px 12px; }');
  E := TEmptyAccess.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.ShowDescription := False;
    E.PreferredSize(w, h);
    AssertEquals('picture + the themed padding both sides', 48 + 24, w);
  finally
    E.Free;
  end;
end;

{ TestUndefinedThemeKeyDrawsNothing
  A theme that does not define TyEmpty must degrade to a blank region — not crash, and not
  invent a look of its own.
  NOTE the CSS: it declares a TyEmpty rule WITHOUT a background rather than omitting the
  key entirely. Omitting it would be a fake test — ANY rule for a typeKey suppresses the
  whole compiled-in base layer (TTyStyleModel.UserHasTypeKey), so a CSS with no TyEmpty at
  all would happily inherit the base's TyEmpty once the theme pass writes one, and this
  test would silently start measuring THAT. }
procedure TTyEmptyControlTest.TestUndefinedThemeKeyDrawsNothing;
var
  E: TTyEmpty;
  Reread: TBGRABitmap;
begin
  FCtl.LoadThemeCss('TyEmpty { border-width: 0px; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, 120, 100);
    Reread := RenderToBGRA(E, 120, 100);
    try
      AssertTrue('an undefined TyEmpty background draws nothing at all', IsAllWhite(Reread));
    finally
      Reread.Free;
    end;
  finally
    E.Free;
  end;
end;

{ TestPictureRendersItsOwnThemeInk
  TyEmptyImage sets its own colour: the carton must take THAT ink and not the message's,
  proving the picture resolves from its own typeKey. White surface + white message ink, so
  any green in the picture's rect can only be TyEmptyImage. }
procedure TTyEmptyControlTest.TestPictureRendersItsOwnThemeInk;
var
  E: TTyEmpty;
  Reread: TBGRABitmap;
  R: TRect;
begin
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 8px; }' +
    'TyEmpty { background: #FFFFFF; color: #FFFFFF; font-size: 12px; }' +
    'TyEmptyImage { color: #10B981; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, 160, 120);
    R := E.ImageRect;
    Reread := RenderToBGRA(E, 160, 120);
    try
      AssertTrue('carton drawn in the TyEmptyImage ink', HasGreenIn(Reread, R));
    finally
      Reread.Free;
    end;
  finally
    E.Free;
  end;
end;

{ TestPictureInkFallsBackToMessageInk
  Graceful degradation for the secondary key: no TyEmptyImage COLOUR => the picture inherits
  the message's ink, never a hard-coded one. The TyEmptyImage rule here declares something
  other than a colour on purpose — see the note on TestUndefinedThemeKeyDrawsNothing: it is
  what suppresses the compiled-in base layer's own TyEmptyImage. }
procedure TTyEmptyControlTest.TestPictureInkFallsBackToMessageInk;
var
  E: TTyEmpty;
  Reread: TBGRABitmap;
  R: TRect;
begin
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 8px; }' +
    'TyEmpty { background: #FFFFFF; color: #10B981; font-size: 12px; }' +
    'TyEmptyImage { border-width: 0px; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.ShowDescription := False;   // then the only thing that CAN be green is the carton
    E.SetBounds(0, 0, 160, 120);
    R := E.ImageRect;
    Reread := RenderToBGRA(E, 160, 120);
    try
      AssertTrue('carton fell back to the message ink', HasGreenIn(Reread, R));
    finally
      Reread.Free;
    end;
  finally
    E.Free;
  end;
end;

{ TestHiddenPictureDrawsNoBox
  ShowImage=False must reach the PAINT, not merely the geometry. }
procedure TTyEmptyControlTest.TestHiddenPictureDrawsNoBox;
var
  E: TTyEmpty;
  Reread: TBGRABitmap;
begin
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 8px; }' +
    'TyEmpty { background: #FFFFFF; color: #FFFFFF; font-size: 12px; }' +
    'TyEmptyImage { color: #10B981; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.ShowImage := False;
    E.ShowDescription := False;
    E.SetBounds(0, 0, 160, 120);
    Reread := RenderToBGRA(E, 160, 120);
    try
      AssertFalse('no carton anywhere once ShowImage is off',
        HasGreenIn(Reread, Rect(0, 0, 160, 120)));
    finally
      Reread.Free;
    end;
  finally
    E.Free;
  end;
end;

{ TestMessageRendersThemeInk
  The message paints from the TyEmpty colour token. Deliberately NOT a glyph-extent
  assertion: the headless runner has TyAutoSystemFontFallback off, so the BGRA default font
  sits and measures differently from a real UI font. Hiding the picture leaves the message
  as the only possible source of ink, and the whole surface is scanned for it. }
procedure TTyEmptyControlTest.TestMessageRendersThemeInk;
var
  E: TTyEmpty;
  Reread: TBGRABitmap;
begin
  FCtl.LoadThemeCss(
    ':root { --empty-image-size: 48px; --empty-gap: 8px; }' +
    'TyEmpty { background: #FFFFFF; color: #3B82F6; font-size: 12px; }');
  E := TTyEmpty.Create(FForm);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.ShowImage := False;
    E.Description := 'nothing to show';
    E.SetBounds(0, 0, 200, 120);
    Reread := RenderToBGRA(E, 200, 120);
    try
      AssertTrue('message drawn in the themed accent ink',
        HasBlueIn(Reread, Rect(0, 0, 200, 120)));
    finally
      Reread.Free;
    end;
  finally
    E.Free;
  end;
end;

procedure TTyEmptyControlTest.TestActionChildRealignsWhenDisabledPaddingChanges;
{ Adversarial-review finding (CONFIRMED): the action band (the CHILD area) is inset by
  CurrentStyle padding, which a theme may vary per state. Disabling the placeholder repaints
  the stack at the new padding, but the base's CMEnabledChanged only Invalidates — it never
  Realigns, so an aligned action child stayed parked at the ENABLED band and drifted out of
  the (now moved) disabled band. The fix Realigns on the state change.

  Headless, LCL's alignment machinery does not reposition a real alClient child (see the card
  suite's TestChildAreaNeverOverlapsThePaintedStrips for the same limitation), so this asserts
  the control's ACTION — that disabling re-runs alignment — via an AlignControls spy, rather
  than a child's bounds. Only fires when there is an action band to align a child into. }
var
  E: TAlignSpyEmpty;
  Child: TCustomControl;
begin
  FCtl.LoadThemeCss(
    ':root { --empty-action-height: 40px; }' +
    'TyEmpty { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }' +
    'TyEmpty:disabled { background: #FFFFFF; color: #111111; padding: 40px; }');
  E := TAlignSpyEmpty.Create(FForm);
  Child := TCustomControl.Create(E);
  try
    E.Parent := FForm;
    E.Controller := FCtl;
    E.Font.PixelsPerInch := 96;
    E.ShowAction := True;
    E.SetBounds(0, 0, 200, 200);
    Child.Parent := E;
    Child.Align := alClient;   // gives the control a child to re-align

    E.AlignCount := 0;         // ignore every align from construction/bounds/parenting
    E.Enabled := False;        // -> CMEnabledChanged -> Realign (the fix)
    AssertTrue('disabling an Empty with an action band re-aligns its child area '
      + '(CMEnabledChanged must Realign, not just Invalidate)', E.AlignCount > 0);
  finally
    E.Free;
  end;
end;

initialization
  RegisterTest(TTyEmptyLayoutTest);
  RegisterTest(TTyEmptyControlTest);
end.
