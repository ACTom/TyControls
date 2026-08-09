unit test.virtualimagelist.iconfont;
{$mode objfpc}{$H+}

{ TTyVirtualImageList's SECOND source: an icon font.

  WHY IT EXISTS AT ALL. Sixteen published `Images` properties in this library take a
  TTyVirtualImageList (menus, ribbon, file dialogs, ...); five take a TTyImageCollection; one
  takes LCL's TCustomImageList. NOTHING takes a TTyGlyphImageList -- so before this, an icon
  font's glyphs could not reach a single one of those properties, and a bundled pack was
  usable only through TTyCharImage. Hanging the font off the list every consumer already
  accepts is the smallest change that opens all of them, and it breaks no published type.

  THE RULE THESE TESTS PIN. Both sources may be set, and the choice is made PER NAME: the
  collection first, the font second. Not "collection wins outright" -- that would make
  IconFont silently inert whenever a collection happened to be assigned, which is exactly the
  published-but-does-nothing defect the parity work spent months removing. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.IconFont, tyControls.ImageCollection;

type
  TVilIconFontTest = class(TTestCase)
  private
    FColl: TTyImageCollection;
    FFont: TTyIconFont;
    FList: TTyVirtualImageList;
    function InkOf(ABmp: TBGRABitmap): Integer;
    procedure AddCollectionImage(const AName: string; AColor: TBGRAPixel);
    function RedInk(ABmp: TBGRABitmap): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure GlyphNameRendersFromTheFont;
    procedure UnknownNameStillRendersAnEmptySquare;
    procedure CollectionWinsForANameItHas;
    procedure FontServesANameTheCollectionDoesNot;
    procedure CachedIndexBorrowsAndIsStable;
    procedure CacheFollowsTheFontsVersion;
    procedure CacheFollowsTheColour;
    procedure FreeingTheFontLeavesNoDanglingCache;
    procedure GlyphColorDefaultsToSomethingVisible;
  end;

implementation

uses
  Forms;

{ The console runner never calls Application.Initialize, so no widgetset exists and BGRA's
  system-font renderer resolves NO family -- a named font draws nothing at all. Lazy one-shot
  init, the same pattern and the same reason as test.windoweffects's NeedWidgetSet. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

const
  { A codepoint with real ink in almost any font; the tests only need "something drew". }
  TestGlyphCp = Ord('W');

function TVilIconFontTest.InkOf(ABmp: TBGRABitmap): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  if ABmp = nil then Exit;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
      if ABmp.GetPixel(x, y).alpha > 40 then Inc(Result);
end;

function TVilIconFontTest.RedInk(ABmp: TBGRABitmap): Integer;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := 0;
  if ABmp = nil then Exit;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
    begin
      px := ABmp.GetPixel(x, y);
      if (px.alpha > 40) and (px.red > 180) and (px.green < 80) then Inc(Result);
    end;
end;

procedure TVilIconFontTest.AddCollectionImage(const AName: string; AColor: TBGRAPixel);
var
  bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(32, 32, AColor);
  try
    FColl.AddBitmap(AName, bmp);
  finally
    bmp.Free;
  end;
end;

procedure TVilIconFontTest.SetUp;
begin
  NeedWidgetSet;
  FColl := TTyImageCollection.Create(nil);
  FFont := TTyIconFont.Create(nil);
  FList := TTyVirtualImageList.Create(nil);
  { A family the test process can actually render with -- the point here is the ROUTING, not
    which typeface it lands in. }
  FFont.FontFamily := 'Arial';
  FFont.MapGlyph('glyph-a', TestGlyphCp);
  FFont.MapGlyph('shared', TestGlyphCp);
end;

procedure TVilIconFontTest.TearDown;
begin
  FList.Free;
  FFont.Free;
  FColl.Free;
end;

procedure TVilIconFontTest.GlyphNameRendersFromTheFont;
var
  bmp: TBGRABitmap;
begin
  FList.IconFont := FFont;
  FList.Names.Text := 'glyph-a';
  AssertEquals('one item', 1, FList.Count);
  bmp := FList.RenderIndex(0, 32);
  try
    AssertEquals('the requested size', 32, bmp.Width);
    AssertTrue('the font drew something', InkOf(bmp) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TVilIconFontTest.UnknownNameStillRendersAnEmptySquare;
var
  bmp: TBGRABitmap;
begin
  FList.IconFont := FFont;
  FList.Names.Text := 'no-such-glyph';
  bmp := FList.RenderIndex(0, 24);
  try
    { Never nil, and the requested size -- the contract the raster path already had. }
    AssertEquals('still the requested size', 24, bmp.Width);
    AssertEquals('and empty', 0, InkOf(bmp));
  finally
    bmp.Free;
  end;
  AssertTrue('CachedIndex says nothing to draw', FList.CachedIndex(0, 24) = nil);
end;

procedure TVilIconFontTest.CollectionWinsForANameItHas;
var
  bmp: TBGRABitmap;
  px: TBGRAPixel;
begin
  { 'shared' exists in BOTH. The collection is asked first, so the solid red square wins over
    the glyph -- and the assertion is on the PIXEL, not on which branch ran. }
  AddCollectionImage('shared', BGRA(255, 0, 0, 255));
  FList.Collection := FColl;
  FList.IconFont := FFont;
  FList.Names.Text := 'shared';
  bmp := FList.RenderIndex(0, 16);
  try
    px := bmp.GetPixel(8, 8);
    AssertEquals('red from the collection', 255, px.red);
    AssertEquals('not the glyph ink', 0, px.green);
  finally
    bmp.Free;
  end;
end;

procedure TVilIconFontTest.FontServesANameTheCollectionDoesNot;
var
  bmp: TBGRABitmap;
begin
  { The half that makes "collection first" a FALLBACK rather than an outright winner. With an
    outright winner, IconFont would be inert here purely because a collection is assigned. }
  AddCollectionImage('raster-only', BGRA(0, 0, 255, 255));
  FList.Collection := FColl;
  FList.IconFont := FFont;
  FList.Names.Text := 'raster-only' + LineEnding + 'glyph-a';
  bmp := FList.RenderIndex(1, 32);
  try
    AssertTrue('the font served the name the collection lacks', InkOf(bmp) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TVilIconFontTest.CachedIndexBorrowsAndIsStable;
var
  a, b: TBGRABitmap;
begin
  FList.IconFont := FFont;
  FList.Names.Text := 'glyph-a';
  a := FList.CachedIndex(0, 20);
  b := FList.CachedIndex(0, 20);
  AssertTrue('a glyph came back', a <> nil);
  { Borrowed means the SAME object twice -- callers do not free it, and DrawIndex relies on
    that (it duplicates before dimming precisely because the bitmap is shared). }
  AssertTrue('the same borrowed bitmap', a = b);
  AssertTrue('with ink', InkOf(a) > 0);
end;

procedure TVilIconFontTest.CacheFollowsTheFontsVersion;
var
  wide, narrow: Integer;
begin
  FList.IconFont := FFont;
  FList.Names.Text := 'glyph-a';
  wide := InkOf(FList.CachedIndex(0, 20));
  AssertTrue('cached with ink', wide > 0);
  { Re-map the name to a much SMALLER glyph. A cache keyed only on (name, size) would keep
    serving the old one forever; the font's Version is in the key for exactly this.
    Asserted on the ink, not on the pointer -- a freed 20x20 bitmap and its replacement land
    on the same heap block often enough that pointer identity proves nothing either way. }
  FFont.MapGlyph('glyph-a', Ord('.'));
  narrow := InkOf(FList.CachedIndex(0, 20));
  AssertTrue(Format('re-rendered after the map changed (%d -> %d ink)', [wide, narrow]),
    narrow < wide);
end;

procedure TVilIconFontTest.CacheFollowsTheColour;
var
  redBefore, redAfter: Integer;
begin
  FList.IconFont := FFont;
  FList.Names.Text := 'glyph-a';
  redBefore := RedInk(FList.CachedIndex(0, 20));
  FList.GlyphColor := TyRGB(255, 0, 0);
  redAfter := RedInk(FList.CachedIndex(0, 20));
  { Content, not pointer identity. Black ink has no red pixels; red ink is all of them. }
  AssertEquals('black by default -- no red pixels', 0, redBefore);
  AssertTrue('re-rendered in the new ink', redAfter > 0);
end;

procedure TVilIconFontTest.FreeingTheFontLeavesNoDanglingCache;
var
  f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  f.FontFamily := 'Arial';
  f.MapGlyph('glyph-a', TestGlyphCp);
  FList.IconFont := f;
  FList.Names.Text := 'glyph-a';
  AssertTrue('cached from the temporary font', FList.CachedIndex(0, 20) <> nil);
  { FreeNotification nils the reference; the cached bitmap it produced must go with it, or
    the next paint hands out a bitmap belonging to a font that no longer exists. }
  f.Free;
  AssertTrue('the reference was nil-ed', FList.IconFont = nil);
  AssertTrue('and nothing is served from the dead font', FList.CachedIndex(0, 20) = nil);
end;

procedure TVilIconFontTest.GlyphColorDefaultsToSomethingVisible;
begin
  { TTyColor is $AARRGGBB, so a 0 default would be fully TRANSPARENT and every glyph would
    come out invisible until the caller thought to set a colour. This library has already
    shipped that exact bug once (the track bar's ShowValue readout, invisible in every theme
    for as long as it existed), which is why the default is asserted rather than assumed. }
  AssertEquals('opaque by default', 255, TyAlphaOf(FList.GlyphColor));
end;

initialization
  RegisterTest(TVilIconFontTest);

end.
