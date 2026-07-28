unit test.painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, LazUTF8, fpcunit, testregistry,
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
    { Vertical extent of the ink currently on the painter's bitmap: the first and last row
      carrying any glyph pixel, and how many rows do. -1/-1/0 when nothing was drawn.
      Rows rather than a centroid because what these tests are about is how FAR DOWN the
      text reaches — the bug being guarded is a line that never gets drawn at all. }
    procedure InkRows(out ATop, ABottom, ARows: Integer);
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
    procedure TestMeasureTextAndUnscale;
    procedure TestZeroFontSizeFallsBack;
    procedure TestClampRadiusPx;
    procedure TestLargeRadiusRendersPillNotLens;
    procedure TestEllipsisCutsWholeCharactersNotBytes;
    procedure TestSplitTextLinesHonoursAuthoredBreaks;
    procedure TestMultiLineDrawsTheSecondLine;
    procedure TestMultiLineFlagLeavesASingleLineByteIdentical;
    procedure TestLineHeightTokenSetsTheDrawnLineBox;
    procedure TestMeasureTextBlockCountsAuthoredLines;
    procedure TestMeasureTextBlockLineHeightIsDerivedNotFloored;
    procedure TestMeasureTextBlockWrapsToAWidth;
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

procedure TPainterTest.InkRows(out ATop, ABottom, ARows: Integer);
var
  x, y: Integer;
  inked: Boolean;
begin
  ATop := -1;
  ABottom := -1;
  ARows := 0;
  for y := 0 to FPainter.Bitmap.Height - 1 do
  begin
    inked := False;
    for x := 0 to FPainter.Bitmap.Width - 1 do
      if FPainter.Bitmap.GetPixel(x, y).alpha > 100 then
      begin
        inked := True;
        Break;
      end;
    if inked then
    begin
      if ATop < 0 then ATop := y;
      ABottom := y;
      Inc(ARows);
    end;
  end;
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

procedure TPainterTest.TestMeasureTextAndUnscale;
var sz: TSize;
begin
  MakePainter(60, 30, 96);   // FreePainter runs in TearDown
  sz := FPainter.MeasureText('99+', '', 9, 400);
  AssertTrue('measured width > 0', sz.cx > 0);
  AssertTrue('measured height > 0', sz.cy > 0);
  AssertEquals('unscale identity at 96ppi', 12, FPainter.Unscale(FPainter.Scale(12)));
end;

procedure TPainterTest.TestZeroFontSizeFallsBack;
var szZero, szFallback: TSize;
begin
  MakePainter(60, 30, 96);
  // A theme rule with no font-size resolves to 0; text must still be visible — the painter
  // falls back to TyFallbackFontSize instead of rendering/measuring a size-0 (invisible) glyph.
  szZero     := FPainter.MeasureText('Ag', '', 0, 400);
  szFallback := FPainter.MeasureText('Ag', '', TyFallbackFontSize, 400);
  AssertTrue('zero font-size measures non-empty', (szZero.cx > 0) and (szZero.cy > 0));
  AssertEquals('zero width == fallback width', szFallback.cx, szZero.cx);
  AssertEquals('zero height == fallback height', szFallback.cy, szZero.cy);
end;

procedure TPainterTest.TestClampRadiusPx;
{ A radius is clamped to half the SHORTER side (pill), never larger. }
begin
  AssertEquals('pill radius on a short track clamps to half-height', 9, TyClampRadiusPx(100, 420, 18));
  AssertEquals('small radius passes through', 6, TyClampRadiusPx(6, 116, 34));
  AssertEquals('clamps to half the shorter side (width here)', 10, TyClampRadiusPx(50, 20, 200));
  AssertEquals('negative radius floors at 0', 0, TyClampRadiusPx(-3, 40, 40));
end;

procedure TPainterTest.TestLargeRadiusRendersPillNotLens;
{ A wide, short rect with a huge "pill" radius (100 >> half-height 10) must render as a rounded
  PILL, not a pointed lens. A near-end pixel (5,3) lies inside the pill's left semicircle
  (centre (10,10) r=10) → filled; without the clamp the corner is cut into a point → transparent. }
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(200, 20, 96);
  fill := Default(TTyFill);
  fill.Kind := tfkSolid;
  fill.Color := TyRGB(255, 0, 0);
  FPainter.FillBackground(Rect(0, 0, 200, 20), fill, 100);
  px := FPainter.Bitmap.GetPixel(5, 3);
  AssertEquals('near-end pixel filled (pill), not cut to a point (lens)', 255, px.alpha);
end;

{ Ellipsising used to shorten the string one BYTE at a time (Delete(s, Length(s), 1)).
  Every CJK character is three bytes in UTF-8, so that left a half-cut sequence: the real GUI
  drew a replacement glyph, which is what the maintainer saw in title bars, buttons, list
  rows and tab headers -- they all funnel through this one DrawText.

  A pixel comparison cannot guard it. The headless BGRA path silently swallows the stray
  trailing byte, so the broken and the correct render come out IDENTICAL here (verified: with
  the byte-wise cut restored, a bitmap-equality test still passed). So assert the STRING
  invariant instead, on the function DrawText actually calls: every prefix the fitter can
  produce is a whole number of characters. }
procedure TPainterTest.TestEllipsisCutsWholeCharactersNotBytes;
const
  CJK = '积压任务徽标挂在按钮上不是按钮内置的';
var
  i, n: Integer;
  prefix: string;
begin
  n := UTF8Length(CJK);
  AssertTrue('the sample really is multi-byte', Length(CJK) = n * 3);

  for i := 0 to n do
  begin
    prefix := TyEllipsisPrefix(CJK, i);
    AssertEquals(Format('prefix of %d chars holds %d characters', [i, i]),
      i, UTF8Length(prefix));
    { The load-bearing one: a byte count that is not a multiple of three here means a
      character was cut through the middle. }
    AssertEquals(Format('prefix of %d chars ends on a character boundary', [i]),
      i * 3, Length(prefix));
  end;

  AssertEquals('a negative count yields nothing', '', TyEllipsisPrefix(CJK, -1));
end;

{ ---- multi-line text, and the line box it is laid out on ---------------------------- }

const
  { Two lines of the SAME text: the width can then never explain a difference, only the
    layout can. 'Ay' carries both an ascender and a descender, so the ink of one line is a
    full line box worth. }
  cTwoLines = 'Ay' + LineEnding + 'Ay';
  cMeasureFont = 'Tahoma';

type
  TPixBuf = array of TBGRAPixel;

function SnapshotOf(ABmp: TBGRABitmap): TPixBuf;
var
  x, y, i: Integer;
begin
  SetLength(Result, ABmp.Width * ABmp.Height);
  i := 0;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
    begin
      Result[i] := ABmp.GetPixel(x, y);
      Inc(i);
    end;
end;

function CountDifferingPixels(const A, B: TPixBuf): Integer;
var
  i: Integer;
begin
  Result := 0;
  if Length(A) <> Length(B) then
    Exit(MaxInt);
  for i := 0 to High(A) do
    if (A[i].red <> B[i].red) or (A[i].green <> B[i].green)
       or (A[i].blue <> B[i].blue) or (A[i].alpha <> B[i].alpha) then
      Inc(Result);
end;

procedure TPainterTest.TestSplitTextLinesHonoursAuthoredBreaks;
{ The split is what both the drawing path and the measuring path ask "how many lines is
  this?", so its edge cases are the edge cases of every size floor derived from it. }
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    TySplitTextLines('plain', L);
    AssertEquals('no break at all is one line', 1, L.Count);
    AssertEquals('and it is the text', 'plain', L[0]);

    TySplitTextLines('a'#13#10'b', L);
    AssertEquals('CRLF breaks', 2, L.Count);
    TySplitTextLines('a'#10'b', L);
    AssertEquals('a bare LF breaks', 2, L.Count);
    TySplitTextLines('a'#13'b', L);
    AssertEquals('a bare CR breaks', 2, L.Count);

    TySplitTextLines('one' + LineEnding + LineEnding + 'two', L);
    AssertEquals('a blank line between paragraphs is content', 3, L.Count);
    AssertEquals('and it is the empty one', '', L[1]);

    { Load-bearing: an empty caption must still be ONE line. Zero lines here would let a
      height floor of "lines x line height" collapse a control to its padding. }
    TySplitTextLines('', L);
    AssertEquals('an empty caption is one empty line', 1, L.Count);
    AssertEquals('', L[0]);
  finally
    L.Free;
  end;
end;

procedure TPainterTest.TestMultiLineDrawsTheSecondLine;
{ THE BUG. style.SingleLine was hard-coded, so a caption with an authored break drew as one
  run — the second line simply did not exist. Both draws below get the same rect, the same
  text and the same centring; only the opt-in flag differs, so any difference in how far the
  ink reaches is the second line appearing. }
var
  t1, b1, r1, t2, b2, r2: Integer;
begin
  MakePainter(200, 140, 96);
  FPainter.DrawText(Rect(0, 0, 200, 140), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  InkRows(t1, b1, r1);
  FreePainter;

  MakePainter(200, 140, 96);
  FPainter.DrawText(Rect(0, 0, 200, 140), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 0, False, True);
  InkRows(t2, b2, r2);

  AssertTrue('the single-line path inked something to compare against', r1 > 0);
  AssertTrue(Format('two lines reach lower than one (%d vs %d)', [b2, b1]), b2 > b1);
  AssertTrue(Format('and start higher — the block is centred as a whole (%d vs %d)',
    [t2, t1]), t2 < t1);
  AssertTrue(Format('so the block grew by most of a line (%d vs %d)',
    [b2 - t2, b1 - t1]), (b2 - t2) > (b1 - t1) + 8);
end;

procedure TPainterTest.TestMultiLineFlagLeavesASingleLineByteIdentical;
{ The flag defaults to off so no existing caller changes; this pins the other half of that
  promise — a caption with NO break in it is drawn by the same code either way, mnemonic
  underline included, and a themed line box does not sneak into it. }
var
  flagOff, flagOn: TPixBuf;
begin
  MakePainter(200, 60, 96);
  FPainter.DrawText(Rect(0, 0, 200, 60), 'Single', cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 3);
  flagOff := SnapshotOf(FPainter.Bitmap);
  FreePainter;

  MakePainter(200, 60, 96);
  FPainter.DrawText(Rect(0, 0, 200, 60), 'Single', cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 3, False, True, 40);
  flagOn := SnapshotOf(FPainter.Bitmap);

  AssertEquals('multi-line mode changes nothing when there is no break',
    0, CountDifferingPixels(flagOff, flagOn));
end;

procedure TPainterTest.TestLineHeightTokenSetsTheDrawnLineBox;
{ The extra leading is a VISUAL value, so it comes from the theme — and it has to work in
  BOTH directions: a bigger line box spreads the block, a smaller one pulls it in. A floor
  hard-coded at the font's line box would pass the first half and fail the second. }
var
  tNat, bNat, rNat, tBig, bBig, rBig, tSmall, bSmall, rSmall: Integer;
begin
  MakePainter(200, 200, 96);
  FPainter.DrawText(Rect(0, 0, 200, 200), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 0, False, True, 0);
  InkRows(tNat, bNat, rNat);
  FreePainter;

  MakePainter(200, 200, 96);
  FPainter.DrawText(Rect(0, 0, 200, 200), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 0, False, True, 40);
  InkRows(tBig, bBig, rBig);
  FreePainter;

  MakePainter(200, 200, 96);
  FPainter.DrawText(Rect(0, 0, 200, 200), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 0, False, True, 6);
  InkRows(tSmall, bSmall, rSmall);

  AssertTrue('the natural line box inked two lines', rNat > 0);
  AssertTrue(Format('a 40px line box spreads the block (%d vs %d)',
    [bBig - tBig, bNat - tNat]), (bBig - tBig) > (bNat - tNat) + 8);
  AssertTrue(Format('a 6px line box pulls it in (%d vs %d)',
    [bSmall - tSmall, bNat - tNat]), (bSmall - tSmall) < (bNat - tNat));
end;

procedure TPainterTest.TestMeasureTextBlockCountsAuthoredLines;
{ The measurement a size floor is built from. Two identical lines make the arithmetic exact:
  the width cannot move at all and the height must exactly double. }
var
  w1, h1, w2, h2, wEmpty, hEmpty: Integer;
begin
  TyMeasureTextBlock('one', cMeasureFont, 12, 400, 96, 0, 0, w1, h1);
  AssertTrue('one line has width', w1 > 0);
  AssertTrue('one line has height', h1 > 0);

  TyMeasureTextBlock('one' + LineEnding + 'one', cMeasureFont, 12, 400, 96, 0, 0, w2, h2);
  AssertEquals('the widest line is the width, not the sum', w1, w2);
  AssertEquals('two lines are exactly twice as tall', h1 * 2, h2);

  { An empty caption still occupies a line — otherwise a control sized from this could be
    allowed to collapse to its padding the moment its caption is cleared. }
  TyMeasureTextBlock('', cMeasureFont, 12, 400, 96, 0, 0, wEmpty, hEmpty);
  AssertEquals('an empty caption measures no width', 0, wEmpty);
  AssertEquals('but still one line of height', h1, hEmpty);
end;

procedure TPainterTest.TestMeasureTextBlockLineHeightIsDerivedNotFloored;
{ "Override the CSS if you want it smaller" is only an honest answer while the height a
  theme asks for is really the height it gets — in both directions — and while a logical-px
  token still means logical px at 192 PPI. }
var
  w, hNat, h40, h6, h40Hi: Integer;
begin
  TyMeasureTextBlock(cTwoLines, cMeasureFont, 12, 400, 96, 0, 0, w, hNat);
  TyMeasureTextBlock(cTwoLines, cMeasureFont, 12, 400, 96, 0, 40, w, h40);
  TyMeasureTextBlock(cTwoLines, cMeasureFont, 12, 400, 96, 0, 6, w, h6);
  TyMeasureTextBlock(cTwoLines, cMeasureFont, 12, 400, 192, 0, 40, w, h40Hi);

  AssertEquals('two lines on a 40px line box', 80, h40);
  AssertTrue(Format('which is taller than the font own box (%d vs %d)', [h40, hNat]),
    h40 > hNat);
  AssertEquals('two lines on a 6px line box', 12, h6);
  AssertTrue(Format('which LOWERS the block (%d vs %d)', [h6, hNat]), h6 < hNat);
  AssertEquals('the token is logical px: it doubles at 192 PPI', 160, h40Hi);
end;

procedure TPainterTest.TestMeasureTextBlockWrapsToAWidth;
{ The wrap the measurement does is the same CJK-aware wrap the label draws with — a Chinese
  run has no spaces, so a width-unaware measurer would report one very wide line and the
  control would be sized for a line it never draws. }
const
  cCJK = '积压任务徽标挂在按钮上不是按钮内置的';
var
  wFull, hFull, wNarrow, hNarrow: Integer;
begin
  TyMeasureTextBlock(cCJK, cMeasureFont, 12, 400, 96, 0, 0, wFull, hFull);
  AssertTrue('unconstrained is one wide line', wFull > 0);

  TyMeasureTextBlock(cCJK, cMeasureFont, 12, 400, 96, wFull div 4, 0, wNarrow, hNarrow);
  AssertTrue(Format('wrapping to a quarter of the width folds it (%d vs %d)',
    [wNarrow, wFull]), wNarrow <= wFull div 4);
  AssertTrue(Format('and makes it at least three lines tall (%d vs %d)',
    [hNarrow, hFull]), hNarrow >= 3 * hFull);
end;

initialization
  RegisterTest(TPainterTest);

end.
