unit test.grid.bidi;

{$mode objfpc}{$H+}

{ Bidirectional text in the GRID's own text path.

  tests/test.bidi.pas pins this for TTyPainter.DrawText, which is how nearly every control in
  this library puts a string on screen. The grid is the exception: TTyCustomGrid.DrawCellText
  does NOT call the painter. It lays the text into its own cached TBGRABitmap with a bare
  bmp.TextRect, because that cache is what makes a hundred-thousand-row table scroll.

  A bare TextRect is always laid out with an IMPLICIT LEFT-TO-RIGHT paragraph base. The
  widgetset's engine does reorder runs and shape Arabic inside the call -- that part was never
  broken -- but it never asks whose paragraph this is. So a cell that STARTS in Arabic and ends
  in Latin ("<arabic> Acme 3.0", a perfectly ordinary row in a localised report) came out with
  its two halves the wrong way round, while the SAME string in the label next to it came out
  right. That is the defect these guards pin.

  Everything the grid draws goes through DrawCellText: cell text, the row-number gutter,
  footer totals, the filter row, wrapped header captions and button-cell captions. So this is
  one function and five visible features.

  Fixtures are built from CODEPOINTS, not from Arabic literals, for the same two reasons
  test.bidi.pas gives: the file stays pure ASCII so no tool can mangle it, and each assertion
  names the character it is about instead of relying on the reader to recognise a glyph. }

interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Grid;

type
  { Reaches the protected seam under test. DrawCellText is protected on purpose -- it is an
    internal rendering detail, not API -- so the established cracker idiom applies. }
  TGridTextAccess = class(TTyStringGrid)
  public
    procedure DrawCellTextForTest(P: TTyPainter; const ARect: TRect; const AText: string;
      const AFontName: string; AFontSize, AFontWeight: Integer; AColor: TTyColor;
      AHAlign: TAlignment; AVAlign: TTextLayout; AWordWrap: Boolean = False);
    procedure ClearTextCacheForTest;
    function TextCacheCountForTest: Integer;
    function BidiLayoutCountForTest: Integer;
    procedure ResetBidiLayoutCountForTest;
  end;

  TGridBidiTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TGridTextAccess;
    { Draw AText through the grid's OWN cell-text path and hand back the pixels. }
    function RenderCell(const AText: string; AW, AH: Integer;
      AHAlign: TAlignment = taLeftJustify; AVAlign: TTextLayout = tlTop;
      AWordWrap: Boolean = False): TBGRABitmap;
    { The call DrawCellText used to make: one bare TextRect, no analysis. Kept verbatim so
      "did this string leave the legacy path?" is answerable in pixels rather than assumed. }
    function RenderLegacy(const AText: string; AW, AH: Integer;
      AHAlign: TAlignment = taLeftJustify; AVAlign: TTextLayout = tlTop): TBGRABitmap;
    function DiffPixels(A, B: TBGRABitmap): Integer;
    function InkCount(A: TBGRABitmap): Integer;
    procedure InkBox(A: TBGRABitmap; out L, R, T, B: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- the defect --- }
    procedure ArabicFirstCellRendersInTheSameVisualOrderAsItsLatinFirstTwin;
    procedure HebrewFirstCellRendersInTheSameVisualOrderAsItsLatinFirstTwin;
    { --- the fast path must not move --- }
    procedure LatinCellTextIsByteIdenticalToTheLegacyTextRect;
    procedure CJKCellTextIsByteIdenticalToTheLegacyTextRect;
    { --- the rest of DrawCellText's contract, under BiDi --- }
    procedure ArabicCellTextLeavesTheLegacyPath;
    procedure ArabicCellTextStaysInsideItsCell;
    procedure ArabicCellTextHonoursHorizontalAlignment;
    procedure ArabicCellTextHonoursVerticalAlignment;
    procedure WrappedArabicCellTextUsesMoreThanOneLine;
    procedure WrappedArabicCellTextStillObeysTheCallersAlignment;
    { --- the gate, asserted where it is actually decided --- }
    procedure LatinAndCJKCellTextNeverReachTheBidiLayout;
    { --- the reason DrawCellText exists at all --- }
    procedure RepeatedArabicCellTextIsLaidOutOnceAndThenCached;
  end;

implementation

const
  cFont = 'Tahoma';      // ships with Arabic + Hebrew coverage on every target we test on
  cSize = 24;            // big enough that a one-pixel rounding cannot decide a test
  cInk  = 40;            // alpha above which a pixel counts as ink

  { Arabic. BEH and TEH are both DUAL-JOINING, so the pair also exercises shaping. }
  cpBEH = $0628;
  cpTEH = $062A;
  { Hebrew, right-to-left but NON-joining, which isolates ORDER from SHAPING. }
  cpHEB_ALEF = $05D0;
  cpHEB_BET  = $05D1;

function Cp(const ACodepoints: array of LongWord): string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(ACodepoints) to High(ACodepoints) do
    Result := Result + UnicodeToUTF8(ACodepoints[i]);
end;

{ ------------------------------------------------------------------- cracker -- }

procedure TGridTextAccess.DrawCellTextForTest(P: TTyPainter; const ARect: TRect;
  const AText: string; const AFontName: string; AFontSize, AFontWeight: Integer;
  AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AWordWrap: Boolean);
begin
  DrawCellText(P, ARect, AText, AFontName, AFontSize, AFontWeight, AColor,
    AHAlign, AVAlign, AWordWrap);
end;

procedure TGridTextAccess.ClearTextCacheForTest;
begin
  ClearTextCache;
end;

function TGridTextAccess.TextCacheCountForTest: Integer;
begin
  Result := TextCacheCount;
end;

function TGridTextAccess.BidiLayoutCountForTest: Integer;
begin
  Result := BidiLayoutCount;
end;

procedure TGridTextAccess.ResetBidiLayoutCountForTest;
begin
  ResetBidiLayoutCount;
end;

{ --------------------------------------------------------------------- setup -- }

procedure TGridBidiTest.SetUp;
begin
  { A parent is needed only so IsRightToLeft (and therefore RtlLayout) has somewhere to read
    from. No theme is loaded: DrawCellText takes its font and colour as arguments and resolves
    no style, so a stylesheet would add nothing but a way for this test to go stale. }
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FGrid := TGridTextAccess.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.Font.PixelsPerInch := 96;
  FGrid.SetBounds(0, 0, 400, 300);
end;

procedure TGridBidiTest.TearDown;
begin
  FreeAndNil(FForm);       { owns the grid }
  FGrid := nil;
end;

function TGridBidiTest.RenderCell(const AText: string; AW, AH: Integer;
  AHAlign: TAlignment; AVAlign: TTextLayout; AWordWrap: Boolean): TBGRABitmap;
var
  host: TBitmap;
  p: TTyPainter;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(AW, AH);
    p.BeginPaint(host.Canvas, Rect(0, 0, AW, AH), 96);
    FGrid.DrawCellTextForTest(p, Rect(0, 0, AW, AH), AText, cFont, cSize, 400,
      TyRGBA(0, 0, 0, 255), AHAlign, AVAlign, AWordWrap);
    Result := TBGRABitmap.Create(AW, AH);
    Result.PutImage(0, 0, p.Bitmap, dmSet);
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
end;

function TGridBidiTest.RenderLegacy(const AText: string; AW, AH: Integer;
  AHAlign: TAlignment; AVAlign: TTextLayout): TBGRABitmap;
var
  style: TTextStyle;
begin
  Result := TBGRABitmap.Create(AW, AH);
  Result.Fill(BGRAPixelTransparent);
  TyConfigureTextFont(Result, cFont, cSize, 400, 96);
  style := Default(TTextStyle);
  style.Alignment := AHAlign;
  style.Layout := AVAlign;
  style.SingleLine := True;
  style.Clipping := True;
  Result.TextRect(Rect(0, 0, AW, AH), 0, 0, AText, style, BGRABlack);
end;

function TGridBidiTest.DiffPixels(A, B: TBGRABitmap): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  if (A.Width <> B.Width) or (A.Height <> B.Height) then Exit(MaxInt);
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y) <> B.GetPixel(x, y) then Inc(Result);
end;

function TGridBidiTest.InkCount(A: TBGRABitmap): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y).alpha > cInk then Inc(Result);
end;

procedure TGridBidiTest.InkBox(A: TBGRABitmap; out L, R, T, B: Integer);
var
  x, y: Integer;
begin
  L := A.Width; R := -1; T := A.Height; B := -1;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y).alpha > cInk then
      begin
        if x < L then L := x;
        if x > R then R := x;
        if y < T then T := y;
        if y > B then B := y;
      end;
  if R < 0 then begin L := -1; T := -1; end;
end;

{ ---------------------------------------------------------------- the defect --

  Stated without needing to read Arabic, exactly as test.bidi.pas states it for the painter.

  "<arabic pair>W" and "W<arabic pair>" are two DIFFERENT logical strings that the Unicode
  bidirectional algorithm resolves to the SAME picture: W on the left, then the Arabic run
  right-to-left. The first is a right-to-left paragraph with an embedded Latin letter, the
  second a left-to-right paragraph with an embedded Arabic run.

  The second always came out right, because a left-to-right base is what a bare TextRect
  assumes anyway. The first did not: the grid drew the Arabic first and put the W after it,
  which is the picture for a completely different sentence.

  Asserting EQUALITY of the two renders rather than "the W is on the left" needs no glyph
  recognition and no coordinate arithmetic, and it fails loudly the moment the paragraph
  direction stops being derived from the first strong character. }
procedure TGridBidiTest.ArabicFirstCellRendersInTheSameVisualOrderAsItsLatinFirstTwin;
var
  rtlFirst, ltrFirst: TBGRABitmap;
begin
  rtlFirst := RenderCell(Cp([cpBEH, cpTEH]) + 'W', 220, 40);
  ltrFirst := RenderCell('W' + Cp([cpBEH, cpTEH]), 220, 40);
  try
    AssertTrue('the fixture must actually put ink in the cell', InkCount(rtlFirst) > 50);
    AssertEquals('an Arabic-first cell and its Latin-first twin are the same picture',
      0, DiffPixels(rtlFirst, ltrFirst));
  finally
    rtlFirst.Free;
    ltrFirst.Free;
  end;
end;

{ The same claim with Hebrew, which does not join its letters. If only the Arabic case passed,
  the fix would be something about shaping; passing here too says it is about ORDER. }
procedure TGridBidiTest.HebrewFirstCellRendersInTheSameVisualOrderAsItsLatinFirstTwin;
var
  rtlFirst, ltrFirst: TBGRABitmap;
begin
  rtlFirst := RenderCell(Cp([cpHEB_ALEF, cpHEB_BET]) + 'W', 220, 40);
  ltrFirst := RenderCell('W' + Cp([cpHEB_ALEF, cpHEB_BET]), 220, 40);
  try
    AssertTrue('the fixture must actually put ink in the cell', InkCount(rtlFirst) > 50);
    AssertEquals('a Hebrew-first cell and its Latin-first twin are the same picture',
      0, DiffPixels(rtlFirst, ltrFirst));
  finally
    rtlFirst.Free;
    ltrFirst.Free;
  end;
end;

{ Requirement one for a change to a path every cell of every grid goes through: Latin output
  does not move by a pixel. The reference is the exact call DrawCellText used to make,
  performed here, so this is asserted against the OLD CODE rather than against a stored golden
  that could drift along with the change.

  WHAT THIS DOES NOT PROVE: that Latin took the cheap branch. It does not -- a bidi layout
  renders single-run text identically, so this stays green even with the gate forced on.
  LatinAndCJKCellTextNeverReachTheBidiLayout is the guard for that half. }
procedure TGridBidiTest.LatinCellTextIsByteIdenticalToTheLegacyTextRect;
var
  now_, before: TBGRABitmap;
begin
  now_   := RenderCell('Region 1234', 220, 40);
  before := RenderLegacy('Region 1234', 220, 40);
  try
    AssertTrue('the fixture must actually put ink in the cell', InkCount(now_) > 50);
    AssertEquals('Latin cell text must still take the legacy TextRect path, pixel for pixel',
      0, DiffPixels(now_, before));
  finally
    now_.Free;
    before.Free;
  end;
end;

{ CJK is the other script this library ships in volume, and it is NOT bidirectional. Same
  caveat as above: this pins the PICTURE, not the branch -- see
  LatinAndCJKCellTextNeverReachTheBidiLayout for the branch. }
procedure TGridBidiTest.CJKCellTextIsByteIdenticalToTheLegacyTextRect;
const
  cHello = #$E4#$BF#$9D#$E5#$AD#$98;      // U+4FDD U+5B58
var
  now_, before: TBGRABitmap;
begin
  now_   := RenderCell(cHello, 220, 40);
  before := RenderLegacy(cHello, 220, 40);
  try
    AssertTrue('the fixture must actually put ink in the cell', InkCount(now_) > 50);
    AssertEquals('CJK cell text must still take the legacy TextRect path, pixel for pixel',
      0, DiffPixels(now_, before));
  finally
    now_.Free;
    before.Free;
  end;
end;

{ The mirror image of the two tests above: Arabic must NOT match the legacy render. Without
  this, deleting the whole fix would still leave the two "byte-identical" guards green and
  only the equality pair red -- and a reader could mistake that for a fixture problem. }
procedure TGridBidiTest.ArabicCellTextLeavesTheLegacyPath;
var
  now_, before: TBGRABitmap;
  s: string;
begin
  s := Cp([cpBEH, cpTEH]) + 'W';
  now_   := RenderCell(s, 220, 40);
  before := RenderLegacy(s, 220, 40);
  try
    AssertTrue('the fixture must actually put ink in the cell', InkCount(now_) > 50);
    AssertTrue('an Arabic-first cell must NOT render the way a bare TextRect renders it',
      DiffPixels(now_, before) > 0);
  finally
    now_.Free;
    before.Free;
  end;
end;

{ A TBidiTextLayout does its own placement and does NOT clip the way TextRect's style.Clipping
  did. The cache bitmap is exactly the cell's size, so anything overhanging is cut by the
  bitmap edge rather than painted over the next column -- this pins that it really is. }
procedure TGridBidiTest.ArabicCellTextStaysInsideItsCell;
var
  bmp: TBGRABitmap;
  l, r, t, b: Integer;
begin
  { Deliberately far more text than 120px holds. }
  bmp := RenderCell(Cp([cpBEH, cpTEH, cpBEH, cpTEH, cpBEH, cpTEH, cpBEH, cpTEH,
                        cpBEH, cpTEH, cpBEH, cpTEH]) + ' Acme 3.0', 120, 30);
  try
    AssertTrue('the fixture must actually put ink in the cell', InkCount(bmp) > 20);
    InkBox(bmp, l, r, t, b);
    AssertTrue('no ink may fall left of the cell', l >= 0);
    AssertTrue('no ink may fall right of the cell', r <= 119);
    AssertTrue('no ink may fall above the cell', t >= 0);
    AssertTrue('no ink may fall below the cell', b <= 29);
  finally
    bmp.Free;
  end;
end;

{ AHAlign still decides where the block sits. This is the half DrawCellText already got right
  via BidiFlipAlignment and it must survive the new path: a right-to-left SCRIPT does not get
  to right-align itself, because that is the MIRRORING question and the grid answers it. }
procedure TGridBidiTest.ArabicCellTextHonoursHorizontalAlignment;
var
  bl, bc, br: TBGRABitmap;
  ll, lr, lt, lb, cl, cr, ct, cb, rl, rr, rt, rb: Integer;
  s: string;
begin
  s := Cp([cpBEH, cpTEH]) + 'W';
  bl := RenderCell(s, 260, 40, taLeftJustify);
  bc := RenderCell(s, 260, 40, taCenter);
  br := RenderCell(s, 260, 40, taRightJustify);
  try
    InkBox(bl, ll, lr, lt, lb);
    InkBox(bc, cl, cr, ct, cb);
    InkBox(br, rl, rr, rt, rb);
    AssertTrue('left-justified Arabic must start at the left edge', ll < cl);
    AssertTrue('centred Arabic must start left of right-justified', cl < rl);
    AssertTrue('right-justified Arabic must reach the right edge', rr > cr);
  finally
    bl.Free; bc.Free; br.Free;
  end;
end;

procedure TGridBidiTest.ArabicCellTextHonoursVerticalAlignment;
var
  bt, bb: TBGRABitmap;
  tl, tr, tt, tb, xl, xr, xt, xb: Integer;
  s: string;
begin
  s := Cp([cpBEH, cpTEH]) + 'W';
  bt := RenderCell(s, 260, 80, taLeftJustify, tlTop);
  bb := RenderCell(s, 260, 80, taLeftJustify, tlBottom);
  try
    InkBox(bt, tl, tr, tt, tb);
    InkBox(bb, xl, xr, xt, xb);
    AssertTrue('top-aligned Arabic must sit above bottom-aligned', tt < xt);
  finally
    bt.Free; bb.Free;
  end;
end;

{ Wrapped header captions are drawn by this same function with AWordWrap = True. The bidi path
  must wrap too, not silently collapse a wrapped Arabic header to one clipped line. }
procedure TGridBidiTest.WrappedArabicCellTextUsesMoreThanOneLine;
var
  one, many: TBGRABitmap;
  ol, orr, ot, ob, ml, mr, mt, mb: Integer;
  s: string;
begin
  s := Cp([cpBEH, cpTEH]) + ' ' + Cp([cpBEH, cpTEH]) + ' ' + Cp([cpBEH, cpTEH]) + ' ' +
       Cp([cpBEH, cpTEH]) + ' ' + Cp([cpBEH, cpTEH]) + ' ' + Cp([cpBEH, cpTEH]);
  one  := RenderCell(s, 90, 100, taLeftJustify, tlTop, False);
  many := RenderCell(s, 90, 100, taLeftJustify, tlTop, True);
  try
    AssertTrue('the wrapped fixture must put ink in the cell', InkCount(many) > 50);
    InkBox(one, ol, orr, ot, ob);
    InkBox(many, ml, mr, mt, mb);
    AssertTrue('wrapped Arabic must occupy more vertical space than the single line',
      (mb - mt) > (ob - ot));
  finally
    one.Free; many.Free;
  end;
end;

{ The wrapped path is the one place AvailableWidth has to be set, and setting it hands the
  layout its OWN paragraph alignment -- which for a right-to-left paragraph defaults to
  right-aligned. That would be the layout engine quietly answering the MIRRORING question,
  which belongs to the grid (RtlLayout -> BidiFlipAlignment -> AHAlign) and to nobody else.
  tyControls.Painter.pas carries the same warning for the same reason.

  Concretely: a left-justified wrapped Arabic header must NOT drift to the right edge of its
  cell just because the script reads right-to-left. }
procedure TGridBidiTest.WrappedArabicCellTextStillObeysTheCallersAlignment;
var
  bl, br: TBGRABitmap;
  ll, lr, lt, lb, rl, rr, rt, rb: Integer;
  s: string;
begin
  s := Cp([cpBEH, cpTEH]) + ' ' + Cp([cpBEH, cpTEH]) + ' ' + Cp([cpBEH, cpTEH]) + ' ' +
       Cp([cpBEH, cpTEH]) + ' ' + Cp([cpBEH, cpTEH]) + ' ' + Cp([cpBEH, cpTEH]);
  bl := RenderCell(s, 120, 100, taLeftJustify,  tlTop, True);
  br := RenderCell(s, 120, 100, taRightJustify, tlTop, True);
  try
    AssertTrue('the wrapped fixture must put ink in the cell', InkCount(bl) > 50);
    InkBox(bl, ll, lr, lt, lb);
    InkBox(br, rl, rr, rt, rb);
    AssertTrue('left-justified wrapped Arabic must start further left than right-justified',
      ll < rl);
    AssertTrue('right-justified wrapped Arabic must end further right than left-justified',
      rr > lr);
  finally
    bl.Free; br.Free;
  end;
end;

{ THE GATE, asserted by COUNTING rather than by looking.

  This test exists because the two "byte-identical to the legacy TextRect" guards above turn
  out NOT to pin the branch, and that was found by mutation rather than by reasoning: changing
  the gate to `if True or TyTextHasRTL(txt)` -- routing every string in the product through the
  bidi layout -- leaves both of them GREEN. A TBidiTextLayout reproduces a bare TextRect
  exactly for text that resolves to a single run, which plain Latin and plain CJK both do.
  test.bidi.pas records the same trap on the painter side.

  So the two guards above are worth keeping as "the picture did not regress", but the
  PERFORMANCE claim -- Latin never pays for a layout it does not need -- can only be counted.
  A grid draws hundreds of cells per frame, and building a layout per cell per frame is the
  exact shape of the bug that once cost TTyMemo half a second per keystroke. }
procedure TGridBidiTest.LatinAndCJKCellTextNeverReachTheBidiLayout;
const
  cHello = #$E4#$BF#$9D#$E5#$AD#$98;      // U+4FDD U+5B58
var
  a, b, c: TBGRABitmap;
begin
  FGrid.ResetBidiLayoutCountForTest;
  FGrid.ClearTextCacheForTest;
  a := RenderCell('Region 1234', 220, 40);
  try
    AssertEquals('plain Latin cell text must not build a bidi layout at all',
      0, FGrid.BidiLayoutCountForTest);
  finally
    a.Free;
  end;
  b := RenderCell(cHello, 220, 40);
  try
    AssertEquals('CJK cell text must not build a bidi layout either',
      0, FGrid.BidiLayoutCountForTest);
  finally
    b.Free;
  end;
  { ...and the counter is not simply dead: Arabic must move it. Without this the test would
    pass just as well against a probe that never increments. }
  c := RenderCell(Cp([cpBEH, cpTEH]) + 'W', 220, 40);
  try
    AssertEquals('Arabic cell text MUST build exactly one bidi layout',
      1, FGrid.BidiLayoutCountForTest);
  finally
    c.Free;
  end;
end;

{ THE performance contract for the text cache, and the reason the layout is built inside the
  cache-miss branch rather than on every frame.

  Two separate claims, because either one can break without the other: the cache must gain one
  entry for the first draw of a string and none for the second (so an RTL cell is not quietly
  drawn straight to the surface, bypassing the cache), and the LAYOUT must be built exactly
  once across both draws. }
procedure TGridBidiTest.RepeatedArabicCellTextIsLaidOutOnceAndThenCached;
var
  a, b: TBGRABitmap;
  cacheFirst, cacheSecond, layFirst, laySecond: Integer;
  s: string;
begin
  s := Cp([cpBEH, cpTEH]) + ' Acme 3.0';
  FGrid.ClearTextCacheForTest;
  FGrid.ResetBidiLayoutCountForTest;
  AssertEquals('the cache starts empty', 0, FGrid.TextCacheCountForTest);
  a := RenderCell(s, 220, 40);
  cacheFirst := FGrid.TextCacheCountForTest;
  layFirst   := FGrid.BidiLayoutCountForTest;
  b := RenderCell(s, 220, 40);
  cacheSecond := FGrid.TextCacheCountForTest;
  laySecond   := FGrid.BidiLayoutCountForTest;
  try
    AssertEquals('the first draw of an Arabic cell caches exactly one bitmap', 1, cacheFirst);
    AssertEquals('and lays it out exactly once', 1, layFirst);
    AssertEquals('drawing the same Arabic cell again must not add a cache entry',
      1, cacheSecond);
    AssertEquals('and must NOT lay the text out a second time -- that is the whole point '
      + 'of the cache', 1, laySecond);
    AssertEquals('and the cached second draw is the same picture', 0, DiffPixels(a, b));
  finally
    a.Free; b.Free;
  end;
end;

initialization
  RegisterTest(TGridBidiTest);
end.
