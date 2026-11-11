unit test.imageink;
{$mode objfpc}{$H+}

{ An icon-font glyph of a TTyVirtualImageList takes the ink of whoever draws it.

  THE RULE, at the list and at the shared draw helpers (the controls that pass an ink are in
  test.imageink.hosts):

  * GlyphColor = TyGlyphColorDefault, the default, names no colour. A glyph of such a list
    is drawn in the ink the caller passes, and in opaque black where none is passed -- the
    baked rasters an LCL control draws, a caller written before the ink existed.
  * A GlyphColor that names a colour is that colour whatever ink is passed.
  * An image from the collection carries its own colours and is never tinted.
  * A glyph drawn in the ink is not faded by AGhosted as well; everything else is, as before.
  * Drawing the same glyphs in several inks does not send each draw back to the font.

  The glyph is U+2588, a full block, so its middle is one solid colour and can be compared
  exactly; a letter's strokes are all antialiasing at 16 px.

  One helper, one test: each entry point takes the ink on its own line of code, and a test
  that walked through several of them would stop at the first that dropped it. }

interface

uses
  Classes, SysUtils, Types, TypInfo, Graphics, GraphType, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.IconFont, tyControls.ImageCollection,
  tyControls.ImageDraw, tyControls.CharImage;

type
  TImageInkTest = class(TTestCase)
  private
    FColl: TTyImageCollection;
    FFont: TTyIconFont;
    FList: TTyVirtualImageList;
    { the middle pixel of ABmp as $AARRGGBB }
    function Mid(ABmp: TBGRABitmap): Int64;
    { the middle of a 32 px icon put at (4, 4) }
    function IconMid(ABmp: TBGRABitmap): Int64;
    { item AIndex drawn onto a white canvas: by TyDrawImage, or by the list's DrawIndex }
    function OnCanvas(AIndex: Integer; AGhosted: Boolean; AInk: TTyColor;
      AByTheList: Boolean = False): Int64;
    function Owned(AIndex: Integer; AGhosted: Boolean; AInk: TTyColor): Int64;
    function InLayer(AIndex: Integer; AGhosted: Boolean; AInk: TTyColor): Int64;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the list }
    procedure TestGlyphColorDefaultsToTheSharedConstant;
    procedure TestTheDeclaredDefaultIsTheConstructedValue;
    procedure TestWithoutAnInkTheGlyphIsOpaqueBlack;
    procedure TestTheBakedSlotIsOpaqueBlack;
    procedure TestABorrowedGlyphTakesTheInk;
    procedure TestAnOwnedGlyphTakesTheInk;
    procedure TestAnExplicitGlyphColorIsKeptUnderAnyInk;
    procedure TestACollectionImageIsNeverTinted;
    procedure TestTakesHostInkTellsTheThreeKindsApart;
    procedure TestDrawIndexPassesTheInk;
    procedure TestDrawIndexDoesNotGhostAGlyphInTheInk;
    { the helpers }
    procedure TestPutImagePassesTheInk;
    procedure TestBlitImagePassesTheInk;
    procedure TestRenderImagePassesTheInk;
    procedure TestDrawImagePassesTheInk;
    procedure TestDrawImagePassesTheInkAtADeviceScale;
    procedure TestBlitImageScaledPassesTheInk;
    procedure TestRenderImageScaledPassesTheInk;
    { ghosting }
    procedure TestAnOwnedGlyphInTheInkIsNotGhostedAsWell;
    procedure TestABlittedGlyphInTheInkIsNotGhostedAsWell;
    procedure TestAGhostedGlyphWithNoInkFadesAsBefore;
    procedure TestAGhostedImageFadesAsBefore;
    procedure TestAGhostedExplicitGlyphFadesAsBefore;
    procedure TestGhostInkCarriesTheFade;
    { the glyph cache }
    procedure TestInkingPerStateDoesNotGoBackToTheFont;
    procedure TestTheGlyphCacheKeepsTheMostRecentlyUsed;
    { the form file }
    procedure TestAStoredGlyphColorLoadsUnchanged;
    procedure TestTheDefaultIsNotWrittenToTheForm;
  end;

implementation

uses
  Forms;

{ BGRA's system-font renderer resolves no family until a widgetset exists, and the console
  runner never initialises one: the same lazy one-shot as test.virtualimagelist.iconfont. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

const
  { Colours no default can produce. }
  InkA: TTyColor     = $FFD2283C;
  InkB: TTyColor     = $FF1EAA5A;
  Explicit: TTyColor = $FF963CC8;
  Photo: TTyColor    = $FF145AE6;
  Black: TTyColor    = $FF000000;
  NoInk: TTyColor    = TyGlyphColorDefault;
  GLYPH = 0;    { 'block', from the font }
  IMAGE = 1;    { 'photo', from the collection }

var
  ResolverHits: Integer = 0;

{ Answers for names starting with 'c' and counts the questions. A draw asks once to find which
  source has the name; a render asks again for the text to draw. }
function CountingResolver(const AFamily, AName: string; out ACodepoint: Cardinal): Boolean;
begin
  ACodepoint := 0;
  Result := (AName <> '') and (AName[1] = 'c');
  if Result then
  begin
    Inc(ResolverHits);
    ACodepoint := $2588;
  end;
end;

{ AColor at the ghosted strength, as $AARRGGBB. }
function Faded(AColor: TTyColor): Int64;
begin
  Result := (Int64(TyGhostedAlpha) shl 24) or (Int64(AColor) and $FFFFFF);
end;

procedure TImageInkTest.SetUp;
var
  bmp: TBGRABitmap;
begin
  NeedWidgetSet;
  FColl := TTyImageCollection.Create(nil);
  bmp := TBGRABitmap.Create(32, 32, TyColorToBGRA(Photo));
  try
    FColl.AddBitmap('photo', bmp);
  finally
    bmp.Free;
  end;
  FFont := TTyIconFont.Create(nil);
  FFont.FontFamily := 'Arial';
  FFont.MapGlyph('block', $2588);
  FList := TTyVirtualImageList.Create(nil);
  FList.Collection := FColl;
  FList.IconFont := FFont;
  FList.Names.Text := 'block' + LineEnding + 'photo';
end;

procedure TImageInkTest.TearDown;
begin
  FList.Free;
  FFont.Free;
  FColl.Free;
end;

function TImageInkTest.Mid(ABmp: TBGRABitmap): Int64;
var
  px: TBGRAPixel;
begin
  if ABmp = nil then Exit(-1);
  px := ABmp.GetPixel(ABmp.Width div 2, ABmp.Height div 2);
  Result := (Int64(px.alpha) shl 24) or (Int64(px.red) shl 16) or (Int64(px.green) shl 8)
    or Int64(px.blue);
end;

function TImageInkTest.IconMid(ABmp: TBGRABitmap): Int64;
var
  px: TBGRAPixel;
begin
  px := ABmp.GetPixel(4 + 16, 4 + 16);
  Result := (Int64(px.alpha) shl 24) or (Int64(px.red) shl 16) or (Int64(px.green) shl 8)
    or Int64(px.blue);
end;

function TImageInkTest.OnCanvas(AIndex: Integer; AGhosted: Boolean; AInk: TTyColor;
  AByTheList: Boolean): Int64;
var
  b: TBitmap;
  got: TBGRABitmap;
begin
  b := TBitmap.Create;
  got := TBGRABitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(48, 48);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, 48, 48);
    if AByTheList then
      FList.DrawIndex(b.Canvas, AIndex, 4, 4, 32, AGhosted, AInk)
    else
      TyDrawImage(b.Canvas, FList, AIndex, 4, 4, 32, 96, AGhosted, AInk);
    got.Assign(b);
    Result := IconMid(got) or $FF000000;   { a canvas has no alpha to read }
  finally
    got.Free;
    b.Free;
  end;
end;

function TImageInkTest.Owned(AIndex: Integer; AGhosted: Boolean; AInk: TTyColor): Int64;
var
  bmp: TBGRABitmap;
begin
  bmp := TyRenderImage(FList, AIndex, 32, 96, AGhosted, AInk);
  try
    Result := Mid(bmp);
  finally
    bmp.Free;
  end;
end;

function TImageInkTest.InLayer(AIndex: Integer; AGhosted: Boolean; AInk: TTyColor): Int64;
var
  dest: TBGRABitmap;
begin
  dest := TBGRABitmap.Create(48, 48, BGRAPixelTransparent);
  try
    TyPutImage(dest, FList, AIndex, 4, 4, 32, AGhosted, AInk);
    Result := IconMid(dest);
  finally
    dest.Free;
  end;
end;

{ ---- the list ----------------------------------------------------------------------------- }

procedure TImageInkTest.TestGlyphColorDefaultsToTheSharedConstant;
begin
  AssertTrue('the default names no colour', FList.GlyphColor = TyGlyphColorDefault);
  AssertTrue('TTyCharImage''s constant is the same one',
    tyControls.CharImage.TyGlyphColorDefault = tyControls.Types.TyGlyphColorDefault);
end;

procedure TImageInkTest.TestTheDeclaredDefaultIsTheConstructedValue;
var
  pi: PPropInfo;
begin
  { A declared default that is not the constructed value: the streamer leaves the value the
    form set out of the .lfm, or writes the one nobody set. }
  pi := GetPropInfo(TTyVirtualImageList, 'GlyphColor');
  AssertTrue('GlyphColor is published', pi <> nil);
  AssertEquals('the declared default is the constructed value',
    Int64(LongInt(FList.GlyphColor)), Int64(pi^.Default));
end;

procedure TImageInkTest.TestWithoutAnInkTheGlyphIsOpaqueBlack;
var
  bmp: TBGRABitmap;
begin
  AssertEquals('borrowed', Int64(Black), Mid(FList.CachedIndex(GLYPH, 32)));
  bmp := FList.RenderIndex(GLYPH, 32);
  try
    AssertEquals('owned', Int64(Black), Mid(bmp));
  finally
    bmp.Free;
  end;
  AssertEquals('through a helper', Int64(Black), Owned(GLYPH, False, NoInk));
end;

procedure TImageInkTest.TestTheBakedSlotIsOpaqueBlack;
var
  raw: TRawImage;
  p: PByte;
  w: Integer;
begin
  { What a stock LCL control draws: the list's own storage, not a render on demand. }
  w := FList.Width;
  FList.Resolution[w].GetRawImage(GLYPH, raw);
  p := raw.Data + ((w div 2) * w + (w div 2)) * 4;
  AssertEquals('alpha', 255, p[3]);
  AssertEquals('red', 0, p[2]);
  AssertEquals('green', 0, p[1]);
  AssertEquals('blue', 0, p[0]);
end;

procedure TImageInkTest.TestABorrowedGlyphTakesTheInk;
begin
  AssertEquals('one ink', Int64(InkA), Mid(FList.CachedIndex(GLYPH, 32, InkA)));
  AssertEquals('another', Int64(InkB), Mid(FList.CachedIndex(GLYPH, 32, InkB)));
  AssertEquals('and the first again', Int64(InkA), Mid(FList.CachedIndex(GLYPH, 32, InkA)));
end;

procedure TImageInkTest.TestAnOwnedGlyphTakesTheInk;
var
  bmp: TBGRABitmap;
begin
  bmp := FList.RenderIndex(GLYPH, 32, InkA);
  try
    AssertEquals('one ink', Int64(InkA), Mid(bmp));
  finally
    bmp.Free;
  end;
  bmp := FList.RenderIndex(GLYPH, 32, InkB);
  try
    AssertEquals('another', Int64(InkB), Mid(bmp));
  finally
    bmp.Free;
  end;
end;

procedure TImageInkTest.TestAnExplicitGlyphColorIsKeptUnderAnyInk;
var
  bmp: TBGRABitmap;
begin
  FList.GlyphColor := Explicit;
  AssertEquals('no ink', Int64(Explicit), Mid(FList.CachedIndex(GLYPH, 32)));
  AssertEquals('an ink', Int64(Explicit), Mid(FList.CachedIndex(GLYPH, 32, InkA)));
  bmp := FList.RenderIndex(GLYPH, 32, InkB);
  try
    AssertEquals('owned', Int64(Explicit), Mid(bmp));
  finally
    bmp.Free;
  end;
  { Opaque black is a colour like any other once it is written down. }
  FList.GlyphColor := Black;
  AssertEquals('explicit black stays black', Int64(Black), Mid(FList.CachedIndex(GLYPH, 32, InkA)));
end;

procedure TImageInkTest.TestACollectionImageIsNeverTinted;
var
  bmp: TBGRABitmap;
begin
  AssertEquals('no ink', Int64(Photo), Mid(FList.CachedIndex(IMAGE, 32)));
  AssertEquals('an ink', Int64(Photo), Mid(FList.CachedIndex(IMAGE, 32, InkA)));
  bmp := FList.RenderIndex(IMAGE, 32, InkB);
  try
    AssertEquals('owned', Int64(Photo), Mid(bmp));
  finally
    bmp.Free;
  end;
  AssertEquals('through a helper', Int64(Photo), Owned(IMAGE, False, InkA));
  AssertEquals('on a canvas', Int64(Photo), OnCanvas(IMAGE, False, InkA));
end;

procedure TImageInkTest.TestTakesHostInkTellsTheThreeKindsApart;
begin
  AssertTrue('a glyph with no colour of its own', FList.TakesHostInk(GLYPH));
  AssertFalse('an image from the collection', FList.TakesHostInk(IMAGE));
  AssertFalse('nothing there', FList.TakesHostInk(7));
  AssertFalse('nor before the first', FList.TakesHostInk(-1));
  FList.GlyphColor := Explicit;
  AssertFalse('a glyph whose list names a colour', FList.TakesHostInk(GLYPH));
  FList.GlyphColor := TyGlyphColorDefault;
  AssertTrue('and back', FList.TakesHostInk(GLYPH));
end;

procedure TImageInkTest.TestDrawIndexPassesTheInk;
begin
  AssertEquals('one ink', Int64(InkA), OnCanvas(GLYPH, False, InkA, True));
  AssertEquals('another', Int64(InkB), OnCanvas(GLYPH, False, InkB, True));
  AssertEquals('none', Int64(Black), OnCanvas(GLYPH, False, NoInk, True));
end;

procedure TImageInkTest.TestDrawIndexDoesNotGhostAGlyphInTheInk;
begin
  AssertEquals('ghosted in the ink: the ink, at full strength', Int64(InkA),
    OnCanvas(GLYPH, True, InkA, True));
  AssertTrue('ghosted with no ink: faded towards the white under it',
    OnCanvas(GLYPH, True, NoInk, True) <> Int64(Black));
  AssertTrue('a ghosted image fades under an ink too',
    OnCanvas(IMAGE, True, InkA, True) <> Int64(Photo));
end;

{ ---- the helpers -------------------------------------------------------------------------- }

procedure TImageInkTest.TestPutImagePassesTheInk;
begin
  AssertEquals('one ink', Int64(InkA), InLayer(GLYPH, False, InkA));
  AssertEquals('another', Int64(InkB), InLayer(GLYPH, False, InkB));
  AssertEquals('none', Int64(Black), InLayer(GLYPH, False, NoInk));
end;

procedure TImageInkTest.TestBlitImagePassesTheInk;

  function Blit(AInk: TTyColor): Int64;
  var
    dest: TBGRABitmap;
  begin
    dest := TBGRABitmap.Create(48, 48, BGRAPixelTransparent);
    try
      TyBlitImage(dest, FList, GLYPH, 4, 4, 32, 96, False, AInk);
      Result := IconMid(dest);
    finally
      dest.Free;
    end;
  end;

begin
  AssertEquals('one ink', Int64(InkA), Blit(InkA));
  AssertEquals('another', Int64(InkB), Blit(InkB));
  AssertEquals('none', Int64(Black), Blit(NoInk));
end;

procedure TImageInkTest.TestRenderImagePassesTheInk;
begin
  AssertEquals('one ink', Int64(InkA), Owned(GLYPH, False, InkA));
  AssertEquals('another', Int64(InkB), Owned(GLYPH, False, InkB));
  AssertEquals('none', Int64(Black), Owned(GLYPH, False, NoInk));
end;

procedure TImageInkTest.TestDrawImagePassesTheInk;
begin
  AssertEquals('one ink', Int64(InkA), OnCanvas(GLYPH, False, InkA));
  AssertEquals('another', Int64(InkB), OnCanvas(GLYPH, False, InkB));
  AssertEquals('none', Int64(Black), OnCanvas(GLYPH, False, NoInk));
end;

procedure TImageInkTest.TestDrawImagePassesTheInkAtADeviceScale;

  { The canvas counts device pixels: the 32 px icon at (4, 4) is 64 px at (8, 8). }
  function Drawn(AInk: TTyColor): Int64;
  var
    b: TBitmap;
    got: TBGRABitmap;
    px: TBGRAPixel;
  begin
    b := TBitmap.Create;
    got := TBGRABitmap.Create;
    try
      b.PixelFormat := pf32bit;
      b.SetSize(96, 96);
      b.Canvas.Brush.Color := clWhite;
      b.Canvas.FillRect(0, 0, 96, 96);
      TyForceDeviceScaleForTest(2, True);
      try
        TyDrawImage(b.Canvas, FList, GLYPH, 4, 4, 32, 96, False, AInk);
      finally
        TyForceDeviceScaleForTest(0, False);
      end;
      got.Assign(b);
      px := got.GetPixel(8 + 32, 8 + 32);
      Result := $FF000000 or (Int64(px.red) shl 16) or (Int64(px.green) shl 8) or Int64(px.blue);
    finally
      got.Free;
      b.Free;
    end;
  end;

begin
  AssertEquals('one ink', Int64(InkA), Drawn(InkA));
  AssertEquals('another', Int64(InkB), Drawn(InkB));
  AssertEquals('none', Int64(Black), Drawn(NoInk));
end;

procedure TImageInkTest.TestBlitImageScaledPassesTheInk;
var
  P: TTyPainter;
  b: TBitmap;
begin
  P := TTyPainter.Create;
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(48, 48);
    P.BeginPaint(b.Canvas, Rect(0, 0, 48, 48), 96);
    try
      TyBlitImageScaled(P, FList, GLYPH, 4, 4, 32, False, InkA);
      AssertEquals('one ink', Int64(InkA), IconMid(P.Bitmap));
      TyBlitImageScaled(P, FList, GLYPH, 4, 4, 32, False, InkB);
      AssertEquals('another', Int64(InkB), IconMid(P.Bitmap));
    finally
      P.EndPaint;
    end;
  finally
    b.Free;
    P.Free;
  end;
end;

procedure TImageInkTest.TestRenderImageScaledPassesTheInk;
var
  P: TTyPainter;
  b: TBitmap;
  bmp: TBGRABitmap;
begin
  P := TTyPainter.Create;
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(48, 48);
    P.BeginPaint(b.Canvas, Rect(0, 0, 48, 48), 96);
    try
      bmp := TyRenderImageScaled(P, FList, GLYPH, 32, False, InkA);
      try
        AssertEquals('one ink', Int64(InkA), Mid(bmp));
      finally
        bmp.Free;
      end;
      bmp := TyRenderImageScaled(P, FList, GLYPH, 32, False, InkB);
      try
        AssertEquals('another', Int64(InkB), Mid(bmp));
      finally
        bmp.Free;
      end;
    finally
      P.EndPaint;
    end;
  finally
    b.Free;
    P.Free;
  end;
end;

{ ---- ghosting ----------------------------------------------------------------------------- }

procedure TImageInkTest.TestAnOwnedGlyphInTheInkIsNotGhostedAsWell;
begin
  AssertEquals('the ink at full strength', Int64(InkA), Owned(GLYPH, True, InkA));
  AssertEquals('whichever ink', Int64(InkB), Owned(GLYPH, True, InkB));
end;

procedure TImageInkTest.TestABlittedGlyphInTheInkIsNotGhostedAsWell;
begin
  AssertEquals('in a layer: the ink at full strength', Int64(InkA), InLayer(GLYPH, True, InkA));
  AssertEquals('on a canvas: the ink at full strength', Int64(InkA),
    OnCanvas(GLYPH, True, InkA));
end;

procedure TImageInkTest.TestAGhostedGlyphWithNoInkFadesAsBefore;
begin
  AssertEquals('in a layer', Faded(Black), InLayer(GLYPH, True, NoInk));
  AssertEquals('owned', Faded(Black), Owned(GLYPH, True, NoInk));
end;

procedure TImageInkTest.TestAGhostedImageFadesAsBefore;
begin
  AssertEquals('in a layer, under an ink', Faded(Photo), InLayer(IMAGE, True, InkA));
  AssertEquals('owned, under an ink', Faded(Photo), Owned(IMAGE, True, InkA));
  AssertEquals('with none', Faded(Photo), InLayer(IMAGE, True, NoInk));
end;

procedure TImageInkTest.TestAGhostedExplicitGlyphFadesAsBefore;
begin
  FList.GlyphColor := Explicit;
  AssertEquals('in a layer, under an ink', Faded(Explicit), InLayer(GLYPH, True, InkA));
  AssertEquals('owned, under an ink', Faded(Explicit), Owned(GLYPH, True, InkA));
  AssertEquals('with none', Faded(Explicit), InLayer(GLYPH, True, NoInk));
end;

procedure TImageInkTest.TestGhostInkCarriesTheFade;
var
  ghost: TTyColor;
begin
  ghost := TyGhostInk(InkA);
  AssertEquals('the colour is kept', Int64(InkA and $00FFFFFF), Int64(ghost and $00FFFFFF));
  AssertEquals('at the ghosted strength', TyGhostedAlpha, TyAlphaOf(ghost));
  AssertEquals('a half-strength ink fades from where it is', (128 * TyGhostedAlpha) div 255,
    TyAlphaOf(TyGhostInk($80102030)));
  AssertTrue('no ink is still no ink', TyGhostInk(NoInk) = NoInk);
  { and the glyph drawn in it is as faint as a ghosted image }
  AssertEquals('the glyph in the ghost ink', Faded(InkA), Owned(GLYPH, True, ghost));
end;

{ ---- the glyph cache ---------------------------------------------------------------------- }

procedure TImageInkTest.TestInkingPerStateDoesNotGoBackToTheFont;
var
  list: TTyVirtualImageList;
  pass, i: Integer;
  first: array[0..3] of TBGRABitmap;
  got: TBGRABitmap;
const
  Inks: array[0..1] of TTyColor = ($FFD2283C, $FF1EAA5A);
begin
  { Two glyphs, two inks each, the order a list with a selected row draws them in. }
  TyRegisterGlyphResolver(@CountingResolver);
  list := TTyVirtualImageList.Create(nil);
  try
    list.IconFont := FFont;
    list.Names.Text := 'c1' + LineEnding + 'c2';
    ResolverHits := 0;
    for i := 0 to 3 do
      first[i] := list.CachedIndex(i div 2, 16, Inks[i mod 2]);
    AssertEquals('the first frame renders each of the four once: a lookup and a render apiece',
      8, ResolverHits);
    for pass := 1 to 3 do
    begin
      ResolverHits := 0;
      for i := 0 to 3 do
      begin
        got := list.CachedIndex(i div 2, 16, Inks[i mod 2]);
        AssertTrue(Format('pass %d, draw %d: the bitmap rendered the first time', [pass, i]),
          got = first[i]);
      end;
      AssertEquals(Format('pass %d: four lookups, no render', [pass]), 4, ResolverHits);
    end;
    AssertEquals('one ink', Int64($FFD2283C), Mid(first[0]));
    AssertEquals('the other', Int64($FF1EAA5A), Mid(first[1]));
  finally
    list.Free;
    TyUnregisterGlyphResolver(@CountingResolver);
  end;
end;

procedure TImageInkTest.TestTheGlyphCacheKeepsTheMostRecentlyUsed;
var
  list: TTyVirtualImageList;
  i: Integer;

  function Shade(AIndex: Integer): TTyColor;
  begin
    Result := TTyColor($FF000100 + Cardinal(AIndex));
  end;

  { How often the font was asked while the glyph was fetched in shade AIndex: once when it
    was kept (the lookup), twice when it had to be rendered again. }
  function Asks(AIndex: Integer): Integer;
  begin
    ResolverHits := 0;
    AssertEquals(Format('shade %d comes back in its colour', [AIndex]),
      Int64(Shade(AIndex)), Mid(list.CachedIndex(0, 16, Shade(AIndex))));
    Result := ResolverHits;
  end;

begin
  TyRegisterGlyphResolver(@CountingResolver);
  list := TTyVirtualImageList.Create(nil);
  try
    list.IconFont := FFont;
    list.Names.Text := 'c1';
    { Fill every slot, oldest first; use the oldest again; then ask for one more. }
    for i := 0 to TyGlyphCacheCapacity - 1 do
      list.CachedIndex(0, 16, Shade(i));
    AssertEquals('full, and the oldest is still kept', 1, Asks(0));
    AssertEquals('one more than there are slots is rendered', 2, Asks(TyGlyphCacheCapacity));
    { What went is the one used longest ago -- shade 1, not shade 0 that was just used and
      not the newcomer. }
    AssertEquals('the one just used again was kept', 1, Asks(0));
    AssertEquals('the newcomer was kept', 1, Asks(TyGlyphCacheCapacity));
    AssertEquals('one that was never used again was kept', 1, Asks(2));
    AssertEquals('the least recently used went, and is rendered again when asked for', 2, Asks(1));
  finally
    list.Free;
    TyUnregisterGlyphResolver(@CountingResolver);
  end;
end;

{ ---- the form file ------------------------------------------------------------------------ }

procedure TImageInkTest.TestAStoredGlyphColorLoadsUnchanged;
var
  ms: TMemoryStream;
  src, back: TTyVirtualImageList;
begin
  ms := TMemoryStream.Create;
  src := TTyVirtualImageList.Create(nil);
  back := TTyVirtualImageList.Create(nil);
  try
    src.Name := 'Icons';
    src.GlyphColor := Black;   { the old default, written down }
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(back);
    AssertEquals('opaque black came back as opaque black', Int64(Black), Int64(back.GlyphColor));
    back.IconFont := FFont;
    back.Names.Text := 'block';
    AssertEquals('and is honoured under an ink', Int64(Black), Mid(back.CachedIndex(0, 32, InkA)));
  finally
    back.Free;
    src.Free;
    ms.Free;
  end;
end;

procedure TImageInkTest.TestTheDefaultIsNotWrittenToTheForm;

  function FormText(AList: TTyVirtualImageList): string;
  var
    bin: TMemoryStream;
    txt: TStringStream;
  begin
    bin := TMemoryStream.Create;
    txt := TStringStream.Create('');
    try
      bin.WriteComponent(AList);
      bin.Position := 0;
      ObjectBinaryToText(bin, txt);
      Result := txt.DataString;
    finally
      txt.Free;
      bin.Free;
    end;
  end;

var
  src: TTyVirtualImageList;
begin
  src := TTyVirtualImageList.Create(nil);
  try
    src.Name := 'Icons';
    AssertEquals('a fresh list writes no GlyphColor', 0, Pos('GlyphColor', FormText(src)));
    src.GlyphColor := Black;
    AssertTrue('a colour that was set is written', Pos('GlyphColor', FormText(src)) > 0);
  finally
    src.Free;
  end;
end;

initialization
  RegisterTest(TImageInkTest);

end.
