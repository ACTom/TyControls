unit test.bidi;

{$mode objfpc}{$H+}

{ Bidirectional text in the painter.

  Every string this library draws goes through TTyPainter.DrawText, and until now that
  handed the whole caption to ONE BGRA TextRect call. What that actually produced was not
  "logical order" -- the widgetset's own text engine (GDI/LPK on Windows, Pango on GTK,
  CoreText on Cocoa) already reorders runs and shapes Arabic inside a single call. What it
  did NOT do is pick the PARAGRAPH direction: a single TextRect is always laid out with an
  implicit left-to-right base, so a caption that STARTS in Arabic or Hebrew and ends in
  Latin came out with its two halves the wrong way round. That is the defect these guards
  pin, and the reason the fix is "route the RTL cases through TBidiTextLayout" rather than
  "implement UAX #9".

  Fixtures are built from CODEPOINTS, not from Arabic literals in the source. Two reasons:
  the file stays pure ASCII so no editor or tool can mangle it, and every assertion below
  names the exact character it is about instead of relying on the reader to recognise a
  glyph. }

interface

uses
  Classes, SysUtils, Types, Graphics, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes, BGRAUnicode,
  tyControls.Types, tyControls.Painter;

type
  TBidiTextTest = class(TTestCase)
  private
    { Draw AText through the real painter and hand back the composed bitmap. The painter
      frees its own surface in EndPaint, so the pixels are copied out first. }
    function RenderPainter(const AText: string; AW, AH: Integer;
      AHAlign: TAlignment = taLeftJustify; AVAlign: TTextLayout = tlTop;
      AEllipsis: Boolean = False; AMnemonicPos: Integer = 0;
      AMultiLine: Boolean = False): TBGRABitmap;
    { The path DrawTextLine took before BiDi existed: one BGRA TextRect, no analysis.
      Kept verbatim so "did this string leave the legacy path?" is answerable in pixels. }
    function RenderLegacy(const AText: string; AW, AH: Integer;
      AHAlign: TAlignment = taLeftJustify; AVAlign: TTextLayout = tlTop): TBGRABitmap;
    function DiffPixels(A, B: TBGRABitmap): Integer;
    function InkCount(A: TBGRABitmap): Integer;
    procedure InkBox(A: TBGRABitmap; out L, R, T, B: Integer);
  published
    { --- the defect --- }
    procedure ArabicFirstCaptionRendersInTheSameVisualOrderAsItsLatinFirstTwin;
    procedure HebrewFirstCaptionRendersInTheSameVisualOrderAsItsLatinFirstTwin;
    { --- the fast path --- }
    procedure LatinStaysOnTheLegacyPath;
    procedure CJKStaysOnTheLegacyPath;
    procedure ArabicLeavesTheLegacyPath;
    procedure RTLScanNeverMissesACodepointTheUnicodeTablesCallRightToLeft;
    procedure RTLScanSaysNoToTheScriptsThisLibraryActuallyShips;
    { --- what the widgetset was already doing right, pinned so it cannot silently stop --- }
    procedure ArabicLettersAreShapedNotStrungTogetherAsIsolatedForms;
    { --- the rest of DrawText's contract, under BiDi --- }
    procedure MnemonicUnderlineFollowsTheGlyphNotTheByteOffset;
    procedure EllipsisedRTLTextStaysInsideItsBox;
    procedure RTLTextHonoursHorizontalAlignment;
    procedure RTLTextHonoursVerticalAlignment;
    procedure MultiLineRTLDrawsEveryAuthoredLine;
    { --- the seam a text-editing control needs (nothing calls it yet) --- }
    procedure CaretPositionsFollowTheGlyphsNotTheStringOrder;
    procedure ClickingTheLeftEdgeOfAnArabicCaptionLandsOnItsLatinTail;
    procedure CaretAndHitTestStillAgreeForPlainLatin;
  end;

implementation

const
  cFont = 'Tahoma';      // ships with Arabic + Hebrew coverage on every target we test on
  cSize = 24;            // big enough that a one-pixel rounding cannot decide a test
  cInk  = 40;            // alpha above which a pixel counts as ink

  { Arabic. BEH and TEH are both DUAL-JOINING, so a BEH followed by a TEH must render as
    initial-form BEH + final-form TEH -- that is the shaping assertion below. }
  cpBEH  = $0628;
  cpTEH  = $062A;
  { The same pair pre-encoded in Arabic Presentation Forms-B, which is what a shaping
    renderer is expected to produce for it. }
  cpBEH_INITIAL = $FE91;
  cpTEH_FINAL   = $FE96;
  cpBEH_ISOLATED = $FE8F;
  cpTEH_ISOLATED = $FE95;
  { Hebrew, which is right-to-left but does NOT join -- so it isolates the ORDERING
    question from the SHAPING one. }
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

function TBidiTextTest.RenderPainter(const AText: string; AW, AH: Integer;
  AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean;
  AMnemonicPos: Integer; AMultiLine: Boolean): TBGRABitmap;
var
  host: TBitmap;
  p: TTyPainter;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(AW, AH);
    p.BeginPaint(host.Canvas, Rect(0, 0, AW, AH), 96);
    p.DrawText(Rect(0, 0, AW, AH), AText, cFont, cSize, 400, TyRGBA(0, 0, 0, 255),
      AHAlign, AVAlign, AEllipsis, AMnemonicPos, False, AMultiLine, 0);
    Result := TBGRABitmap.Create(AW, AH);
    Result.PutImage(0, 0, p.Bitmap, dmSet);
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
end;

function TBidiTextTest.RenderLegacy(const AText: string; AW, AH: Integer;
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

function TBidiTextTest.DiffPixels(A, B: TBGRABitmap): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  if (A.Width <> B.Width) or (A.Height <> B.Height) then
    Exit(MaxInt);
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y) <> B.GetPixel(x, y) then
        Inc(Result);
end;

function TBidiTextTest.InkCount(A: TBGRABitmap): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y).alpha > cInk then
        Inc(Result);
end;

procedure TBidiTextTest.InkBox(A: TBGRABitmap; out L, R, T, B: Integer);
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

{ THE defect, stated without needing to read Arabic.

  "<arabic pair>W" and "W<arabic pair>" are two DIFFERENT logical strings that the Unicode
  bidirectional algorithm resolves to the SAME picture: W on the left, then the Arabic run
  right-to-left. The first is a right-to-left paragraph with an embedded Latin letter; the
  second is a left-to-right paragraph with an embedded Arabic run; both display as
  [W][teh][beh].

  The second one has always come out right, because a left-to-right base is what a bare
  TextRect assumes anyway. The first one did not: the painter drew the Arabic first and put
  the W after it, which is the picture for a completely different sentence.

  Asserting EQUALITY of the two renders rather than "the W is on the left" is deliberate --
  it needs no glyph recognition, no coordinate arithmetic, and it fails loudly the moment
  the paragraph direction stops being derived from the first strong character. }
procedure TBidiTextTest.ArabicFirstCaptionRendersInTheSameVisualOrderAsItsLatinFirstTwin;
var
  rtlFirst, ltrFirst: TBGRABitmap;
begin
  rtlFirst := RenderPainter(Cp([cpBEH, cpTEH]) + 'W', 220, 40);
  ltrFirst := RenderPainter('W' + Cp([cpBEH, cpTEH]), 220, 40);
  try
    AssertTrue('the fixture must actually put ink on the surface', InkCount(rtlFirst) > 50);
    AssertEquals('an Arabic-first caption and its Latin-first twin are the same picture',
      0, DiffPixels(rtlFirst, ltrFirst));
  finally
    rtlFirst.Free;
    ltrFirst.Free;
  end;
end;

{ Same claim with Hebrew, which does not join its letters. If only the Arabic case passed,
  the fix would be something about shaping; passing here too says it is about ORDER. }
procedure TBidiTextTest.HebrewFirstCaptionRendersInTheSameVisualOrderAsItsLatinFirstTwin;
var
  rtlFirst, ltrFirst: TBGRABitmap;
begin
  rtlFirst := RenderPainter(Cp([cpHEB_ALEF, cpHEB_BET]) + 'W', 220, 40);
  ltrFirst := RenderPainter('W' + Cp([cpHEB_ALEF, cpHEB_BET]), 220, 40);
  try
    AssertTrue('the fixture must actually put ink on the surface', InkCount(rtlFirst) > 50);
    AssertEquals('a Hebrew-first caption and its Latin-first twin are the same picture',
      0, DiffPixels(rtlFirst, ltrFirst));
  finally
    rtlFirst.Free;
    ltrFirst.Free;
  end;
end;

{ Two claims in one test, because pixels alone cannot make either of them.

  The first is requirement one: Latin output does not change. The reference is the exact call
  DrawTextLine used to make -- one BGRA TextRect -- performed here, so the assertion is
  against the old code rather than against a stored golden that could drift with it.

  The second is the performance contract. Building a TBidiTextLayout per caption per frame is
  the shape of the bug that once cost TTyMemo half a second per keystroke, so Latin must not
  reach that code at all. Pixels turn out NOT to prove that: mutating the gate to fire on
  every string left this comparison at zero differences, because the bidi layout happens to
  reproduce the legacy result for text that has only one run. So the branch is asserted where
  it is actually decided -- TyTextHasRTL, the gate itself. }
procedure TBidiTextTest.LatinStaysOnTheLegacyPath;
var
  viaPainter, viaLegacy: TBGRABitmap;
begin
  AssertFalse('Latin text must not trip the gate into the bidi layout',
    TyTextHasRTL('Hello World 123'));
  viaPainter := RenderPainter('Hello World 123', 260, 40);
  viaLegacy := RenderLegacy('Hello World 123', 260, 40);
  try
    AssertTrue('the fixture must actually put ink on the surface', InkCount(viaPainter) > 50);
    AssertEquals('Latin text must render exactly as it did before BiDi existed',
      0, DiffPixels(viaPainter, viaLegacy));
  finally
    viaPainter.Free;
    viaLegacy.Free;
  end;
end;

{ The same pair of claims for CJK -- the other script this library is actually shipped for,
  and the one with the most non-ASCII bytes per caption, so the one a sloppy byte scan would
  most easily mistake for right-to-left. }
procedure TBidiTextTest.CJKStaysOnTheLegacyPath;
const
  cHello = #$E4#$BD#$A0#$E5#$A5#$BD#$E4#$B8#$96#$E7#$95#$8C;  // U+4F60 U+597D U+4E16 U+754C
var
  viaPainter, viaLegacy: TBGRABitmap;
begin
  AssertFalse('CJK text must not trip the gate into the bidi layout', TyTextHasRTL(cHello));
  viaPainter := RenderPainter(cHello, 260, 40);
  viaLegacy := RenderLegacy(cHello, 260, 40);
  try
    AssertTrue('the fixture must actually put ink on the surface', InkCount(viaPainter) > 50);
    AssertEquals('CJK text must render exactly as it did before BiDi existed',
      0, DiffPixels(viaPainter, viaLegacy));
  finally
    viaPainter.Free;
    viaLegacy.Free;
  end;
end;

{ The counterpart, and the one that keeps the two guards above honest: a gate that answered
  "no RTL here" for EVERY string would satisfy both of them and do nothing. This one only
  passes when Arabic really does leave the single-TextRect path. }
procedure TBidiTextTest.ArabicLeavesTheLegacyPath;
var
  viaPainter, viaLegacy: TBGRABitmap;
begin
  viaPainter := RenderPainter(Cp([cpBEH, cpTEH]) + 'W', 220, 40);
  viaLegacy := RenderLegacy(Cp([cpBEH, cpTEH]) + 'W', 220, 40);
  try
    AssertTrue('the fixture must actually put ink on the surface', InkCount(viaPainter) > 50);
    AssertTrue('a mixed Arabic caption must NOT come out of the legacy single-run path',
      DiffPixels(viaPainter, viaLegacy) > 0);
  finally
    viaPainter.Free;
    viaLegacy.Free;
  end;
end;

{ The gate decides, for every caption this library draws, whether the bidirectional path is
  entered at all -- so a codepoint it fails to recognise is text drawn backwards, silently,
  on one script and not another. Rather than trusting a hand-written range list, check it
  against BGRA's own generated Unicode tables over the whole BMP and the first supplementary
  plane: every codepoint those tables class as right-to-left, Arabic-letter or Arabic-number
  must make the gate say yes.

  Only MISSES are an error. The gate is deliberately a superset -- it answers yes for the
  unassigned holes inside the Hebrew/Arabic blocks too -- because a false positive costs one
  correct-but-slower layout and a false negative costs correctness. }
procedure TBidiTextTest.RTLScanNeverMissesACodepointTheUnicodeTablesCallRightToLeft;
var
  u, firstMiss: LongWord;
  misses: Integer;
begin
  misses := 0;
  firstMiss := 0;
  for u := 1 to $1FFFF do
  begin
    if (u >= $D800) and (u <= $DFFF) then Continue;    // surrogates are not characters
    if not (GetUnicodeBidiClass(u) in [ubcRightToLeft, ubcArabicLetter, ubcArabicNumber]) then
      Continue;
    if not TyTextHasRTL(UnicodeToUTF8(u)) then
    begin
      Inc(misses);
      if firstMiss = 0 then firstMiss := u;
    end;
  end;
  { One assertion rather than 130k of them, and it names the offender so a future block
    addition is a one-line diagnosis. }
  AssertEquals('every right-to-left codepoint must trip the gate; first missed U+'
    + IntToHex(firstMiss, 4), 0, misses);
end;

{ The other half of the gate's contract, and the one the performance argument rests on: the
  scripts this library is actually shipped for must never reach the bidi path. Includes the
  characters that are nearest to being mistaken for it -- CJK and fullwidth forms are three
  UTF-8 bytes like Arabic presentation forms are, and the general-punctuation block shares a
  lead byte with the right-to-left marks. }
procedure TBidiTextTest.RTLScanSaysNoToTheScriptsThisLibraryActuallyShips;
begin
  AssertFalse('empty', TyTextHasRTL(''));
  AssertFalse('plain ascii', TyTextHasRTL('Save and close (Ctrl+S) 12345'));
  AssertFalse('latin-1 accents', TyTextHasRTL(#$C3#$A9#$C3#$BC#$C3#$9F));       // e-acute u-umlaut sharp-s
  AssertFalse('greek', TyTextHasRTL(#$CE#$B1#$CE#$B2#$CE#$B3));                  // alpha beta gamma
  AssertFalse('cyrillic', TyTextHasRTL(#$D0#$9F#$D1#$80#$D0#$B8));               // Pri
  AssertFalse('chinese', TyTextHasRTL(#$E4#$BF#$9D#$E5#$AD#$98));                // U+4FDD U+5B58
  AssertFalse('japanese kana', TyTextHasRTL(#$E3#$81#$82#$E3#$81#$84));          // U+3042 U+3044
  AssertFalse('hangul', TyTextHasRTL(#$ED#$95#$9C#$EA#$B5#$AD));                 // U+D55C U+AD6D
  AssertFalse('fullwidth punctuation', TyTextHasRTL(#$EF#$BC#$8C#$EF#$BC#$81));  // U+FF0C U+FF01
  AssertFalse('typographic punctuation', TyTextHasRTL(#$E2#$80#$94#$E2#$80#$A6));// em dash, ellipsis
  AssertFalse('left-to-right mark', TyTextHasRTL(#$E2#$80#$8E));                 // U+200E
  AssertFalse('emoji', TyTextHasRTL(#$F0#$9F#$91#$8D));                          // U+1F44D
  { and the positives, so an "always false" gate cannot pass this test either }
  AssertTrue('hebrew', TyTextHasRTL(Cp([cpHEB_ALEF])));
  AssertTrue('arabic', TyTextHasRTL(Cp([cpBEH])));
  AssertTrue('arabic presentation form', TyTextHasRTL(Cp([cpBEH_INITIAL])));
  AssertTrue('one arabic word inside a latin sentence',
    TyTextHasRTL('Order ' + Cp([cpBEH, cpTEH]) + ' shipped'));
  AssertTrue('right-to-left mark', TyTextHasRTL(#$E2#$80#$8F));                  // U+200F
end;

{ Shaping is a different problem from ordering, and this library does not solve it -- the
  widgetset's text engine does, inside the single run the layout hands it. That is worth an
  assertion rather than a comment, because it is the thing that decides whether Arabic is
  legible at all, and because it is the part most likely to differ on a platform we cannot
  test from here.

  BEH followed by TEH must come out as the initial+final PRESENTATION forms (which is what
  a shaping engine substitutes) and must NOT come out as the two isolated forms strung
  together (which is what "no shaping" looks like). }
procedure TBidiTextTest.ArabicLettersAreShapedNotStrungTogetherAsIsolatedForms;
var
  joined, shaped, isolated: TBGRABitmap;
begin
  joined := RenderPainter(Cp([cpBEH, cpTEH]), 160, 44);
  shaped := RenderPainter(Cp([cpBEH_INITIAL, cpTEH_FINAL]), 160, 44);
  isolated := RenderPainter(Cp([cpBEH_ISOLATED, cpTEH_ISOLATED]), 160, 44);
  try
    AssertTrue('the fixture must actually put ink on the surface', InkCount(joined) > 50);
    AssertEquals('two joining Arabic letters render as their connected presentation forms',
      0, DiffPixels(joined, shaped));
    AssertTrue('and not as two isolated forms side by side',
      DiffPixels(joined, isolated) > 0);
  finally
    joined.Free;
    shaped.Free;
    isolated.Free;
  end;
end;

{ AMnemonicPos is a byte offset into the caption, and the underline used to be placed by
  measuring the bytes BEFORE it -- which assumes the glyphs come out in the order the bytes
  went in. Under BiDi they do not.

  Fixture: "<arabic pair>W" with the mnemonic on the W. The W displays at the LEFT (it is
  the embedded left-to-right run of a right-to-left paragraph), so the underline belongs
  under the left-hand glyph. The old arithmetic put it a whole Arabic word to the right.

  The underline is isolated by rendering the same caption twice, with and without the
  mnemonic, and looking only at the pixels that differ. }
procedure TBidiTextTest.MnemonicUnderlineFollowsTheGlyphNotTheByteOffset;
var
  plain, marked: TBGRABitmap;
  x, y, mnemonicByte, uL, uR: Integer;
  txt: string;
begin
  txt := Cp([cpBEH, cpTEH]) + 'W';
  mnemonicByte := Length(Cp([cpBEH, cpTEH])) + 1;   // 1-based byte index of the 'W'
  plain := RenderPainter(txt, 220, 44, taLeftJustify, tlTop, False, 0);
  marked := RenderPainter(txt, 220, 44, taLeftJustify, tlTop, False, mnemonicByte);
  try
    uL := marked.Width; uR := -1;
    for y := 0 to marked.Height - 1 do
      for x := 0 to marked.Width - 1 do
        if plain.GetPixel(x, y) <> marked.GetPixel(x, y) then
        begin
          if x < uL then uL := x;
          if x > uR then uR := x;
        end;
    AssertTrue('the mnemonic must draw an underline at all', uR >= 0);
    { The W is the leftmost glyph of the display order, so its underline cannot start past
      the middle of the ink. Stated as a half-width bound rather than an exact x so a font
      substitution cannot turn a correctness guard into a metrics guard. }
    AssertTrue('the underline must sit under the leftmost (Latin) glyph, not after the Arabic',
      uR < 40);
  finally
    plain.Free;
    marked.Free;
  end;
end;

{ TextRect clipped to its rectangle for free (style.Clipping); TBidiTextLayout does not, so
  the new path has to clip for itself or an overlong caption paints over whatever sits beside
  the control.

  Drawn into a rectangle strictly INSIDE the surface, and the assertion is on the pixels
  outside it -- not on the ink's bounding box, which a rectangle that fills the whole bitmap
  can never violate. That earlier version of this test let a mutant that removed the clip
  entirely go by unnoticed.

  Both overflow routes are exercised: a caption that has been ellipsis-fitted (where the
  measured width and the laid-out width come from two different pieces of code and can
  disagree by a pixel or two) and one that is simply longer than its box. }
procedure TBidiTextTest.EllipsisedRTLTextStaysInsideItsBox;
const
  cBoxL = 20; cBoxT = 10; cBoxR = 110; cBoxB = 50;

  function OutsideInk(A: TBGRABitmap): Integer;
  var x, y: Integer;
  begin
    Result := 0;
    for y := 0 to A.Height - 1 do
      for x := 0 to A.Width - 1 do
        if (A.GetPixel(x, y).alpha > cInk)
           and ((x < cBoxL) or (x >= cBoxR) or (y < cBoxT) or (y >= cBoxB)) then
          Inc(Result);
  end;

var
  host: TBitmap;
  p: TTyPainter;
  fitted, unfitted: TBGRABitmap;
  txt: string;
  i: Integer;
begin
  txt := '';
  for i := 1 to 12 do
    txt := txt + Cp([cpBEH, cpTEH]) + ' ';
  host := TBitmap.Create;
  fitted := nil;
  unfitted := nil;
  try
    host.SetSize(200, 70);
    p := TTyPainter.Create;
    try
      p.BeginPaint(host.Canvas, Rect(0, 0, 200, 70), 96);
      p.DrawText(Rect(cBoxL, cBoxT, cBoxR, cBoxB), txt, cFont, cSize, 400,
        TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, True);
      fitted := TBGRABitmap.Create(200, 70);
      fitted.PutImage(0, 0, p.Bitmap, dmSet);
      p.EndPaint;
    finally
      p.Free;
    end;
    p := TTyPainter.Create;
    try
      p.BeginPaint(host.Canvas, Rect(0, 0, 200, 70), 96);
      p.DrawText(Rect(cBoxL, cBoxT, cBoxR, cBoxB), txt, cFont, cSize, 400,
        TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
      unfitted := TBGRABitmap.Create(200, 70);
      unfitted.PutImage(0, 0, p.Bitmap, dmSet);
      p.EndPaint;
    finally
      p.Free;
    end;
    AssertTrue('the fixture must actually put ink on the surface', InkCount(fitted) > 20);
    AssertEquals('ellipsised right-to-left text may not paint outside its rectangle',
      0, OutsideInk(fitted));
    AssertTrue('and the unfitted fixture must be long enough to overflow',
      InkCount(unfitted) > 20);
    AssertEquals('nor may right-to-left text that is simply wider than its rectangle',
      0, OutsideInk(unfitted));
  finally
    fitted.Free;
    unfitted.Free;
    host.Free;
  end;
end;

{ AHAlign is the CALLER's instruction about where the text block sits in its rectangle, and
  BiDi does not get to overrule it -- mirroring a control's geometry is a separate job that
  has not been done. A right-to-left caption asked to sit on the left sits on the left. }
procedure TBidiTextTest.RTLTextHonoursHorizontalAlignment;
var
  left, centre, right: TBGRABitmap;
  lL, lR, cL, cR, rL, rR, t, b: Integer;
  txt: string;
begin
  txt := Cp([cpBEH, cpTEH]) + 'W';
  left := RenderPainter(txt, 240, 44, taLeftJustify, tlCenter);
  centre := RenderPainter(txt, 240, 44, taCenter, tlCenter);
  right := RenderPainter(txt, 240, 44, taRightJustify, tlCenter);
  try
    InkBox(left, lL, lR, t, b);
    InkBox(centre, cL, cR, t, b);
    InkBox(right, rL, rR, t, b);
    AssertTrue('left-aligned right-to-left text starts near the left edge', lL < 6);
    AssertTrue('centred text starts further right than left-aligned', cL > lL + 20);
    AssertTrue('right-aligned text starts further right than centred', rL > cL + 20);
    AssertTrue('right-aligned text ends near the right edge', rR > 240 - 8);
  finally
    left.Free;
    centre.Free;
    right.Free;
  end;
end;

{ The same for AVAlign. The BiDi layout carries its own vertical metrics, so the block could
  easily end up anchored somewhere the legacy path never put it. }
procedure TBidiTextTest.RTLTextHonoursVerticalAlignment;
var
  top, centre, bottom: TBGRABitmap;
  l, r, tT, tB, cT, cB, bT, bB: Integer;
  txt: string;
begin
  txt := Cp([cpBEH, cpTEH]) + 'W';
  top := RenderPainter(txt, 200, 80, taLeftJustify, tlTop);
  centre := RenderPainter(txt, 200, 80, taLeftJustify, tlCenter);
  bottom := RenderPainter(txt, 200, 80, taLeftJustify, tlBottom);
  try
    InkBox(top, l, r, tT, tB);
    InkBox(centre, l, r, cT, cB);
    InkBox(bottom, l, r, bT, bB);
    AssertTrue('top-anchored right-to-left text starts near the top', tT < 12);
    AssertTrue('centred text sits below top-anchored', cT > tT + 8);
    AssertTrue('bottom-anchored sits below centred', bT > cT + 8);
    AssertTrue('and stays inside the box', bB < 80);
  finally
    top.Free;
    centre.Free;
    bottom.Free;
  end;
end;

{ The multi-line dispatcher splits on the author's breaks and draws one line box at a time,
  so each line reaches the single-line path independently. This is the case where a gate
  placed at the wrong level -- on the whole block instead of on the line -- would draw the
  first line and lose the second.

  Counted as "ink in the first line box AND ink in the second", not as row bands: Arabic
  carries dots above and below the letters, so a single line of it is already several
  disconnected bands of rows. }
procedure TBidiTextTest.MultiLineRTLDrawsEveryAuthoredLine;
var
  bmp: TBGRABitmap;
  y, x, firstBox, secondBox, belowBoth: Integer;
begin
  bmp := RenderPainter(Cp([cpBEH, cpTEH]) + 'W' + #13#10 + 'W' + Cp([cpBEH, cpTEH]),
    220, 120, taLeftJustify, tlTop, False, 0, True);
  try
    firstBox := 0; secondBox := 0; belowBoth := 0;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
        if bmp.GetPixel(x, y).alpha > cInk then
        begin
          if y < 36 then Inc(firstBox)
          else if y < 80 then Inc(secondBox)
          else Inc(belowBoth);
        end;
    AssertTrue('the first authored line must be drawn', firstBox > 50);
    AssertTrue('and so must the second', secondBox > 50);
    AssertEquals('and nothing may land below the two line boxes', 0, belowBoth);
  finally
    bmp.Free;
  end;
end;

{ --- the caret seam ---------------------------------------------------------------------

  TTyEdit answers "where is codepoint N on screen" with a cumulative sum of codepoint widths
  taken in STRING order. That is exactly right for Latin and CJK and simply untrue here: in
  "<arabic pair>W" the LAST codepoint is the LEFTMOST glyph, so the prefix sum puts the caret
  for it at the far right of the run and a click on the W selects an Arabic letter.

  These three guard the painter's answer to the same two questions. Nothing in the library
  calls them yet -- the edits still walk their own prefix sum -- so this is the seam, tested,
  waiting for the control work that is not in this change. }

procedure TBidiTextTest.CaretPositionsFollowTheGlyphsNotTheStringOrder;
var
  host: TBitmap;
  p: TTyPainter;
  r: TRect;
  atStart, atEnd, txt: string;
  xFirst, xLast: Integer;
begin
  { Codepoints: 0 = beh, 1 = teh, 2 = 'W'. The paragraph is right-to-left, so codepoint 0
    displays at the RIGHT edge and the caret before it belongs there -- while the caret after
    the final codepoint ('W', the leftmost glyph) belongs near the left edge. A prefix sum
    taken in string order produces precisely the opposite pair. }
  txt := Cp([cpBEH, cpTEH]) + 'W';
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(240, 44);
    r := Rect(0, 0, 240, 44);
    p.BeginPaint(host.Canvas, r, 96);
    xFirst := p.TextCaretX(r, txt, cFont, cSize, 400, taLeftJustify, 0);
    xLast := p.TextCaretX(r, txt, cFont, cSize, 400, taLeftJustify, 3);
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
  atStart := 'caret before the first codepoint x=' + IntToStr(xFirst);
  atEnd := 'caret after the last codepoint x=' + IntToStr(xLast);
  AssertTrue('in a right-to-left paragraph the caret for codepoint 0 sits to the RIGHT of '
    + 'the caret for the last one -- ' + atStart + ', ' + atEnd, xFirst > xLast);
  AssertTrue('and the whole run stays inside the box', xFirst <= 240);
end;

procedure TBidiTextTest.ClickingTheLeftEdgeOfAnArabicCaptionLandsOnItsLatinTail;
var
  host: TBitmap;
  p: TTyPainter;
  r: TRect;
  hitLeft, hitRight: Integer;
  txt: string;
begin
  txt := Cp([cpBEH, cpTEH]) + 'W';
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(240, 44);
    r := Rect(0, 0, 240, 44);
    p.BeginPaint(host.Canvas, r, 96);
    hitLeft := p.TextCharIndexAtX(r, txt, cFont, cSize, 400, taLeftJustify, 2);
    hitRight := p.TextCharIndexAtX(r, txt, cFont, cSize, 400, taLeftJustify, 66);
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
  { The 'W' is codepoint 2 and it is the leftmost glyph; the first Arabic letter is codepoint
    0 and it is the rightmost. A logical-order hit test answers exactly the other way round. }
  AssertEquals('a click at the left edge selects the Latin tail (codepoint 2)', 2, hitLeft);
  AssertEquals('and a click at the right edge selects the first Arabic letter', 0, hitRight);
end;

procedure TBidiTextTest.CaretAndHitTestStillAgreeForPlainLatin;
var
  host: TBitmap;
  p: TTyPainter;
  r: TRect;
  x0, x1, x2, x3, hit: Integer;
begin
  { The seam has to be usable for ALL text, not only the bidirectional kind, or a control
    adopting it would need two code paths and would keep the buggy one. For plain Latin the
    carets must simply march left to right. }
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(240, 44);
    r := Rect(0, 0, 240, 44);
    p.BeginPaint(host.Canvas, r, 96);
    x0 := p.TextCaretX(r, 'abc', cFont, cSize, 400, taLeftJustify, 0);
    x1 := p.TextCaretX(r, 'abc', cFont, cSize, 400, taLeftJustify, 1);
    x2 := p.TextCaretX(r, 'abc', cFont, cSize, 400, taLeftJustify, 2);
    x3 := p.TextCaretX(r, 'abc', cFont, cSize, 400, taLeftJustify, 3);
    hit := p.TextCharIndexAtX(r, 'abc', cFont, cSize, 400, taLeftJustify, 1);
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
  AssertEquals('the caret before the first character is at the left edge', 0, x0);
  AssertTrue('and each following caret is further right', (x1 > x0) and (x2 > x1) and (x3 > x2));
  AssertEquals('a click at the left edge selects the first character', 0, hit);
end;

initialization
  RegisterTest(TBidiTextTest);
end.
