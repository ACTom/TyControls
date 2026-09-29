unit test.terminal.render;
{$mode objfpc}{$H+}
{ tyControls.Terminal.Render on its own: the 256-colour table against xterm.js's
  (tools/terminal-oracle/view-cases.js), how a cell's colours resolve, the glyph
  cache, the drawn box-drawing and block glyphs, the cell metrics and the glyph
  rasterizer.

  The pixel tests use cell metrics made by hand (9 x 18, and 10 x 23 for a cell that
  is not a whole ratio), not a font, so they do not move with the machine's fonts;
  the bitmaps start magenta (the sentinel) and every assertion is "is / is not this
  colour". }

interface

uses
  Classes, SysUtils, Math, Types, fpcunit, testregistry, fpjson,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal.Render, test.terminal.oracle;

type
  TTyTerminalRenderTests = class(TTestCase)
  private
    function Resolve(AIndex: Integer): Cardinal;
    function NewSentinel(AW, AH: Integer): TBGRABitmap;
  published
    procedure TestPaletteMatchesUpstream;
    procedure TestCellColors;
    procedure TestGlyphCacheEvictsTheLeastRecentlyUsed;
    procedure TestGlyphCacheCountsHitsAndMisses;
    procedure TestFullBlockFillsTheCell;
    procedure TestHalfBlocks;
    procedure TestShadesCoverTheirShare;
    procedure TestLinesJoinAcrossCells;
    procedure TestHeavyLinesAreThicker;
    procedure TestDoubleLinesKeepTheirGap;
    procedure TestArcsReachTheirEdges;
    procedure TestCellMetricsScaleWithThePPI;
    procedure TestRasterizedGlyphs;
    procedure TestDrawnGlyphMasksMatchDrawingThem;
    procedure TestDrawnGlyphsAreCachedPerCellAndPhase;
    procedure TestGlyphKeysKeepCellCountsApart;
    procedure TestSingleCodePointsAreCachedByCode;
    procedure TestTheRasterBudgetSpreadsGlyphsOverFrames;
  end;

function TyTermTestMetrics(ACellW, ACellH: Integer; ACharW: Integer = -1): TTyTermCellMetrics;
function TyTermSentinel: TBGRAPixel;
function TyTermIsSentinel(const P: TBGRAPixel): Boolean;
function TyTermSamePixel(const P: TBGRAPixel; ARgb: Cardinal): Boolean;

implementation

function TyTermTestMetrics(ACellW, ACellH: Integer; ACharW: Integer): TTyTermCellMetrics;
begin
  Result := Default(TTyTermCellMetrics);
  Result.CellW := ACellW;
  Result.CellH := ACellH;
  if ACharW < 0 then Result.CharW := ACellW else Result.CharW := ACharW;
  Result.CharH := ACellH;
  Result.Baseline := ACellH * 3 div 4;
  Result.LineW := 1;
  Result.UnderlineY := Result.Baseline + 1;
  Result.StrikeY := ACellH div 2;
  Result.OverlineY := 0;
end;

function TyTermSentinel: TBGRAPixel;
begin
  Result := BGRA(255, 0, 255, 255);
end;

function TyTermIsSentinel(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red = 255) and (P.green = 0) and (P.blue = 255);
end;

function TyTermSamePixel(const P: TBGRAPixel; ARgb: Cardinal): Boolean;
begin
  Result := (P.red = (ARgb shr 16) and $FF) and (P.green = (ARgb shr 8) and $FF) and (P.blue = ARgb and $FF);
end;

const
  Ink = $204080;

function TTyTerminalRenderTests.Resolve(AIndex: Integer): Cardinal;
begin
  Result := $100000 + Cardinal(AIndex);
end;

function TTyTerminalRenderTests.NewSentinel(AW, AH: Integer): TBGRABitmap;
begin
  Result := TBGRABitmap.Create(AW, AH, TyTermSentinel);
end;

procedure TTyTerminalRenderTests.TestPaletteMatchesUpstream;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  ansi: TJSONArray;
  i: Integer;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('view-palette', miss);
    try
      AssertEquals(miss.Text, 0, miss.Count);
      TyTermCheckUpstream(fx[0], 'view-palette', miss);
      ansi := fx[0].Arrays['ansi'];
      for i := 0 to ansi.Count - 1 do
      begin
        miss.AddCompared;
        if TyTermDefaultPaletteColor(i) <> Cardinal(ansi.Int64s[i]) then
          miss.Add(IntToStr(i), 'colour', IntToHex(ansi.Int64s[i], 6), IntToHex(TyTermDefaultPaletteColor(i), 6));
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertEquals('comparisons (2 for the pin)', 256 + 2, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalRenderTests.TestCellColors;
var
  ext: TTyTerminalExtAttrs;
  noExt: TTyTerminalExtAttrs;

  function P16(n: Cardinal): Cardinal; begin Result := TyTermAttrCmP16 or n; end;
  function P256(n: Cardinal): Cardinal; begin Result := TyTermAttrCmP256 or n; end;
  function RGB(n: Cardinal): Cardinal; begin Result := TyTermAttrCmRgb or n; end;
  function Pal(n: Cardinal): Cardinal; begin Result := $100000 + n; end;

  procedure Row(const AWhat: string; AFg, ABg: Cardinal; const AExt: TTyTerminalExtAttrs; ABright: Boolean;
    AWantFg, AWantBg: Cardinal; AWantUl: Int64 = -1; AWantDim: Boolean = False; AWantInvisible: Boolean = False);
  var
    c: TTyTermCellColors;
  begin
    c := TyTermResolveCellColors(AFg, ABg, AExt, @Resolve, ABright);
    AssertEquals(AWhat + ': fg', IntToHex(AWantFg, 6), IntToHex(c.Fg, 6));
    AssertEquals(AWhat + ': bg', IntToHex(AWantBg, 6), IntToHex(c.Bg, 6));
    if AWantUl >= 0 then
      AssertEquals(AWhat + ': underline', IntToHex(AWantUl, 6), IntToHex(c.Underline, 6));
    AssertEquals(AWhat + ': dim', AWantDim, c.Dim);
    AssertEquals(AWhat + ': invisible', AWantInvisible, c.Invisible);
  end;

begin
  noExt := Default(TTyTerminalExtAttrs);
  Row('default', 0, 0, noExt, True, Pal(256), Pal(257));
  Row('P16 1', P16(1), 0, noExt, True, Pal(1), Pal(257));
  Row('P16 1 bold', P16(1) or TyTermFgBold, 0, noExt, True, Pal(9), Pal(257));
  Row('P16 1 bold, no brightening', P16(1) or TyTermFgBold, 0, noExt, False, Pal(1), Pal(257));
  Row('P256 5 bold brightens too', P256(5) or TyTermFgBold, 0, noExt, True, Pal(13), Pal(257));
  Row('P256 9 bold stays', P256(9) or TyTermFgBold, 0, noExt, True, Pal(9), Pal(257));
  Row('RGB bold', RGB($123456) or TyTermFgBold, RGB($654321), noExt, True, $123456, $654321);
  Row('default inverse', TyTermFgInverse, 0, noExt, True, Pal(257), Pal(256));
  Row('P16 inverse', P16(1) or TyTermFgInverse, P16(4), noExt, True, Pal(4), Pal(1));
  { modes that differ: inverse swaps the MODE with the value (a value-only swap reads the
    palette index 0 as a P16 colour and the default background as ... default) }
  Row('P16 over default, inverse', P16(1) or TyTermFgInverse, 0, noExt, True, Pal(257), Pal(1));
  Row('RGB over default, inverse', RGB($123456) or TyTermFgInverse, 0, noExt, True, Pal(257), $123456);
  Row('inverse then bold', P16(1) or TyTermFgInverse or TyTermFgBold, P16(2), noExt, True, Pal(10), Pal(1));
  Row('dim', RGB($FF0000), RGB($000000) or TyTermBgDim, noExt, True, $800000, $000000, -1, True);
  Row('hidden', P16(3) or TyTermFgInvisible, 0, noExt, True, Pal(3), Pal(257), -1, False, True);
  Row('underline, default colour', P16(3) or TyTermFgUnderline, 0, noExt, True, Pal(3), Pal(257), Pal(3));
  ext := Default(TTyTerminalExtAttrs);
  ext.SetUnderlineStyle(Ord(tusSingle));
  ext.SetUnderlineColor(Integer(TyTermAttrCmP16 or 3));
  Row('underline colour P16 3, bold', P16(3) or TyTermFgUnderline or TyTermFgBold, TyTermBgHasExtended, ext, True,
    Pal(11), Pal(257), Pal(11));
  ext.SetUnderlineColor(Integer(TyTermAttrCmRgb or $0000FF));
  Row('underline colour RGB', P16(3) or TyTermFgUnderline, TyTermBgHasExtended, ext, True, Pal(3), Pal(257), $0000FF);
end;

function Key(const AText: string): TTyTermGlyphKey;
begin
  Result := Default(TTyTermGlyphKey);
  Result.Text := AText;
  Result.Cells := 1;
end;

procedure TTyTerminalRenderTests.TestGlyphCacheEvictsTheLeastRecentlyUsed;
var
  cache: TTyTermGlyphCache;
  live: Integer;
begin
  live := TTyTermGlyph.LiveCount;
  cache := TTyTermGlyphCache.Create(3);
  try
    cache.Add(Key('A'), TTyTermGlyph.Create);
    cache.Add(Key('B'), TTyTermGlyph.Create);
    cache.Add(Key('C'), TTyTermGlyph.Create);
    AssertNotNull('A is there', cache.Find(Key('A')));
    cache.Add(Key('D'), TTyTermGlyph.Create);
    AssertNull('B, the least recently used, went', cache.Find(Key('B')));
    AssertNotNull('A stays (it was used)', cache.Find(Key('A')));
    AssertNotNull('C stays', cache.Find(Key('C')));
    AssertNotNull('D is there', cache.Find(Key('D')));
    AssertEquals('count', 3, cache.Count);
    AssertEquals('glyphs alive: the evicted one was freed', live + 3, TTyTermGlyph.LiveCount);
    cache.Clear;
    AssertEquals('count after Clear', 0, cache.Count);
    AssertEquals('glyphs alive after Clear', live, TTyTermGlyph.LiveCount);
  finally
    cache.Free;
  end;
  AssertEquals('glyphs alive after Free', live, TTyTermGlyph.LiveCount);
end;

procedure TTyTerminalRenderTests.TestGlyphCacheCountsHitsAndMisses;
var
  cache: TTyTermGlyphCache;
  k: TTyTermGlyphKey;
begin
  cache := TTyTermGlyphCache.Create;
  try
    AssertNull(cache.Find(Key('x')));
    cache.Add(Key('x'), TTyTermGlyph.Create);
    AssertNotNull(cache.Find(Key('x')));
    AssertNotNull(cache.Find(Key('x')));
    AssertEquals('misses', 1, cache.Misses);
    AssertEquals('hits', 2, cache.Hits);
    k := Key('x');
    k.Bold := True;
    AssertNull('bold is another key', cache.Find(k));
    k := Key('x');
    k.Cells := 2;
    AssertNull('width is another key', cache.Find(k));
    k := Key('x');
    k.Font := tfkWide;
    AssertNull('the font is another key', cache.Find(k));
  finally
    cache.Free;
  end;
end;

procedure TTyTerminalRenderTests.TestFullBlockFillsTheCell;
var
  bmp: TBGRABitmap;
  m: TTyTermCellMetrics;
  x, y: Integer;
  cell: TRect;
  inside: Boolean;
begin
  { CharW narrower than the cell: a block fills the CELL (letter spacing included) }
  m := TyTermTestMetrics(9, 18, 6);
  bmp := NewSentinel(4 * 9, 4 * 18);
  try
    cell := Rect(9, 18, 18, 36);
    TyTermDrawCustomGlyph(bmp, cell, $2588, TyTermRgbToPixel(Ink), m, 96);
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        inside := (x >= cell.Left) and (x < cell.Right) and (y >= cell.Top) and (y < cell.Bottom);
        if inside then
          AssertTrue(Format('(%d,%d) is the ink', [x, y]), TyTermSamePixel(bmp.GetPixel(x, y), Ink))
        else
          AssertTrue(Format('(%d,%d) untouched', [x, y]), TyTermIsSentinel(bmp.GetPixel(x, y)));
      end;
  finally
    bmp.Free;
  end;
end;

procedure TTyTerminalRenderTests.TestHalfBlocks;
var
  bmp: TBGRABitmap;
  m: TTyTermCellMetrics;
  x, y: Integer;
begin
  m := TyTermTestMetrics(10, 18);
  bmp := NewSentinel(10, 18);
  try
    TyTermDrawCustomGlyph(bmp, Rect(0, 0, 10, 18), $2580, TyTermRgbToPixel(Ink), m, 96);   { upper half }
    for y := 0 to 17 do
      for x := 0 to 9 do
        if y < 9 then
          AssertTrue(Format('upper half (%d,%d)', [x, y]), TyTermSamePixel(bmp.GetPixel(x, y), Ink))
        else
          AssertTrue(Format('lower half (%d,%d)', [x, y]), TyTermIsSentinel(bmp.GetPixel(x, y)));
  finally
    bmp.Free;
  end;
  bmp := NewSentinel(10, 18);
  try
    TyTermDrawCustomGlyph(bmp, Rect(0, 0, 10, 18), $258C, TyTermRgbToPixel(Ink), m, 96);   { left half }
    for y := 0 to 17 do
      for x := 0 to 9 do
        if x < 5 then
          AssertTrue(Format('left half (%d,%d)', [x, y]), TyTermSamePixel(bmp.GetPixel(x, y), Ink))
        else
          AssertTrue(Format('right half (%d,%d)', [x, y]), TyTermIsSentinel(bmp.GetPixel(x, y)));
  finally
    bmp.Free;
  end;
end;

procedure TTyTerminalRenderTests.TestShadesCoverTheirShare;
const
  Cps: array[0..2] of Cardinal = ($2591, $2592, $2593);
  Lo: array[0..2] of Double = (0.20, 0.45, 0.70);
  Hi: array[0..2] of Double = (0.30, 0.55, 0.80);
var
  bmp: TBGRABitmap;
  m: TTyTermCellMetrics;
  k, x, y, n: Integer;
  share: Double;
begin
  m := TyTermTestMetrics(9, 18);
  for k := 0 to 2 do
  begin
    bmp := NewSentinel(9, 18);
    try
      TyTermDrawCustomGlyph(bmp, Rect(0, 0, 9, 18), Cps[k], TyTermRgbToPixel(Ink), m, 96);
      n := 0;
      for y := 0 to 17 do
        for x := 0 to 8 do
          if TyTermSamePixel(bmp.GetPixel(x, y), Ink) then Inc(n)
          else AssertTrue('only ink or untouched', TyTermIsSentinel(bmp.GetPixel(x, y)));
      share := n / (9 * 18);
      AssertTrue(Format('U+%x covers %.2f, want %.2f..%.2f', [Cps[k], share, Lo[k], Hi[k]]),
        (share >= Lo[k]) and (share <= Hi[k]));
      if k = 0 then
      begin
        { xterm.js's LIGHT SHADE pattern [[1,0],[0,0]], tiled from the surface's origin }
        AssertTrue('light shade (0,0) inked', TyTermSamePixel(bmp.GetPixel(0, 0), Ink));
        AssertTrue('light shade (1,0) clear', TyTermIsSentinel(bmp.GetPixel(1, 0)));
        AssertTrue('light shade (0,1) clear', TyTermIsSentinel(bmp.GetPixel(0, 1)));
        AssertTrue('light shade (1,1) clear', TyTermIsSentinel(bmp.GetPixel(1, 1)));
      end;
    finally
      bmp.Free;
    end;
  end;
end;

procedure TTyTerminalRenderTests.TestLinesJoinAcrossCells;
const
  PPIs: array[0..1] of Integer = (96, 144);
var
  bmp: TBGRABitmap;
  m: TTyTermCellMetrics;
  mi, pi_, c, x, y, W, H: Integer;
  found, all: Boolean;
begin
  for mi := 0 to 1 do
    for pi_ := 0 to 1 do
    begin
      if mi = 0 then m := TyTermTestMetrics(9, 18) else m := TyTermTestMetrics(10, 23);
      W := m.CellW;
      H := m.CellH;
      { four horizontal lines side by side }
      bmp := NewSentinel(4 * W, H);
      try
        for c := 0 to 3 do
          TyTermDrawCustomGlyph(bmp, Rect(c * W, 0, (c + 1) * W, H), $2500, TyTermRgbToPixel(Ink), m, PPIs[pi_]);
        found := False;
        for y := 0 to H - 1 do
        begin
          all := True;
          for x := 0 to 4 * W - 1 do
            if TyTermIsSentinel(bmp.GetPixel(x, y)) then begin all := False; Break; end;
          if all then found := True;
        end;
        AssertTrue(Format('a row inked across four cells (%dx%d, %d PPI)', [W, H, PPIs[pi_]]), found);
      finally
        bmp.Free;
      end;
      { three vertical lines stacked }
      bmp := NewSentinel(W, 3 * H);
      try
        for c := 0 to 2 do
          TyTermDrawCustomGlyph(bmp, Rect(0, c * H, W, (c + 1) * H), $2502, TyTermRgbToPixel(Ink), m, PPIs[pi_]);
        found := False;
        for x := 0 to W - 1 do
        begin
          all := True;
          for y := 0 to 3 * H - 1 do
            if TyTermIsSentinel(bmp.GetPixel(x, y)) then begin all := False; Break; end;
          if all then found := True;
        end;
        AssertTrue(Format('a column inked down three cells (%dx%d, %d PPI)', [W, H, PPIs[pi_]]), found);
      finally
        bmp.Free;
      end;
    end;
end;

function InkRows(ABmp: TBGRABitmap): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
      if not TyTermIsSentinel(ABmp.GetPixel(x, y)) then
      begin
        Inc(Result);
        Break;
      end;
end;

procedure TTyTerminalRenderTests.TestHeavyLinesAreThicker;
var
  light, heavy: TBGRABitmap;
  m: TTyTermCellMetrics;
begin
  m := TyTermTestMetrics(9, 18);
  light := NewSentinel(9, 18);
  heavy := NewSentinel(9, 18);
  try
    TyTermDrawCustomGlyph(light, Rect(0, 0, 9, 18), $2500, TyTermRgbToPixel(Ink), m, 96);
    TyTermDrawCustomGlyph(heavy, Rect(0, 0, 9, 18), $2501, TyTermRgbToPixel(Ink), m, 96);
    AssertTrue(Format('heavy %d rows, light %d', [InkRows(heavy), InkRows(light)]),
      (InkRows(light) > 0) and (InkRows(heavy) >= 2 * InkRows(light)));
  finally
    light.Free;
    heavy.Free;
  end;
end;

procedure TTyTerminalRenderTests.TestDoubleLinesKeepTheirGap;
var
  bmp: TBGRABitmap;
  m: TTyTermCellMetrics;
  mi, y, x, W, H, segs, y1, y2: Integer;
  prevInk, isInk: Boolean;
  starts: array[0..9] of Integer;
  yp, want: Double;
begin
  for mi := 0 to 1 do
  begin
    if mi = 0 then m := TyTermTestMetrics(9, 18) else m := TyTermTestMetrics(10, 23);
    W := m.CellW;
    H := m.CellH;
    bmp := NewSentinel(W, H);
    try
      TyTermDrawCustomGlyph(bmp, Rect(0, 0, W, H), $2550, TyTermRgbToPixel(Ink), m, 96);
      x := W div 2;
      segs := 0;
      prevInk := False;
      for y := 0 to H - 1 do
      begin
        isInk := not TyTermIsSentinel(bmp.GetPixel(x, y));
        if isInk and not prevInk then
        begin
          if segs <= High(starts) then starts[segs] := y;
          Inc(segs);
        end;
        prevInk := isInk;
      end;
      AssertEquals(Format('two segments down the middle column (%dx%d)', [W, H]), 2, segs);
      { where the two lines sit: 0.5 -/+ yp, yp = 0.15 / H x W, rounded to the half pixel }
      yp := 0.15 / H * W;
      y1 := Floor((0.5 - yp) * H + 1);
      y2 := Floor((0.5 + yp) * H + 1);
      want := y2 - y1;
      AssertTrue(Format('gap %d, want %.0f (+-1) for %dx%d', [starts[1] - starts[0], want, W, H]),
        Abs((starts[1] - starts[0]) - want) <= 1);
    finally
      bmp.Free;
    end;
  end;
end;

procedure TTyTerminalRenderTests.TestArcsReachTheirEdges;
var
  bmp: TBGRABitmap;
  m: TTyTermCellMetrics;
  x, y: Integer;
  right, bottom: Boolean;
begin
  m := TyTermTestMetrics(9, 18);
  bmp := NewSentinel(9, 18);
  try
    TyTermDrawCustomGlyph(bmp, Rect(0, 0, 9, 18), $256D, TyTermRgbToPixel(Ink), m, 96);
    right := False;
    for y := 7 to 10 do
      if not TyTermIsSentinel(bmp.GetPixel(8, y)) then right := True;
    bottom := False;
    for x := 3 to 5 do
      if not TyTermIsSentinel(bmp.GetPixel(x, 17)) then bottom := True;
    AssertTrue('ink at the middle of the right edge', right);
    AssertTrue('ink at the middle of the bottom edge', bottom);
    for y := 0 to 2 do
      for x := 0 to 2 do
        AssertTrue(Format('the top-left corner is clear (%d,%d)', [x, y]), TyTermIsSentinel(bmp.GetPixel(x, y)));
  finally
    bmp.Free;
  end;
end;

function SpecOf(ASize, APPI: Integer): TTyTermFontSpec;
begin
  Result := Default(TTyTermFontSpec);
  Result.MainName := 'Consolas';
  Result.SizeLogical := ASize;
  Result.PPI := APPI;
  Result.LineHeightPercent := 100;
  Result.UnderlineWidthLogical := 1;
  Result.CursorWidthLogical := 1;
end;

procedure TTyTerminalRenderTests.TestCellMetricsScaleWithThePPI;
var
  a, b, c: TTyTermCellMetrics;
  s: TTyTermFontSpec;
  ratio: Double;
begin
  a := TyTermMeasureCell(SpecOf(9, 96));
  b := TyTermMeasureCell(SpecOf(9, 144));
  ratio := b.CellW / a.CellW;
  AssertTrue(Format('cell width %d -> %d (%.2f)', [a.CellW, b.CellW, ratio]), (ratio >= 1.4) and (ratio <= 1.6));
  s := SpecOf(9, 144);
  s.LetterSpacingLogical := 2;
  c := TyTermMeasureCell(s);
  AssertEquals('letter spacing 2 at 144 PPI adds 3', b.CellW + 3, c.CellW);
  AssertEquals('letter spacing leaves the glyph box', b.CharW, c.CharW);
  s := SpecOf(9, 96);
  s.LineHeightPercent := 150;
  c := TyTermMeasureCell(s);
  AssertEquals('line height 150%', Ceil(1.5 * c.CharH), c.CellH);
  AssertEquals('the glyph box centred in the taller cell', (c.CellH - c.CharH) div 2, c.TextTop);
  AssertEquals('the baseline moves with it', a.Baseline + c.TextTop, c.Baseline);
  AssertEquals('line width at 96 PPI', 1, a.LineW);
  AssertEquals('line width at 192 PPI', 2, TyTermMeasureCell(SpecOf(9, 192)).LineW);
  AssertTrue('the underline stays in the cell', a.UnderlineY + a.LineW <= a.CellH);
  AssertTrue('the strikethrough sits between the top and the baseline',
    (a.StrikeY > a.TextTop) and (a.StrikeY < a.Baseline));
end;

procedure TTyTerminalRenderTests.TestRasterizedGlyphs;
var
  r: TTyTermGlyphRasterizer;
  cache: TTyTermGlyphCache;
  s: TTyTermFontSpec;
  m: TTyTermCellMetrics;
  g: TTyTermGlyph;
  k: TTyTermGlyphKey;
  hits: Integer;
begin
  r := TTyTermGlyphRasterizer.Create;
  cache := TTyTermGlyphCache.Create;
  try
    s := SpecOf(9, 96);
    m := TyTermMeasureCell(s);
    g := r.Rasterize(Key('W'), s, m);
    try
      AssertNotNull('W has ink', g.Mask);
      AssertTrue('W starts in its cell', g.OffsetX >= 0);
      AssertTrue(Format('W ends in its cell (%d + %d <= %d)', [g.OffsetX, g.Mask.Width, m.CellW]),
        g.OffsetX + g.Mask.Width <= m.CellW);
      AssertTrue('W sits in the row', (g.OffsetY >= 0) and (g.OffsetY + g.Mask.Height <= m.CellH));
    finally
      g.Free;
    end;
    k := Key(#$E4#$B8#$AD);          { U+4E2D }
    k.Cells := 2;
    g := r.Rasterize(k, s, m);
    try
      AssertNotNull('a CJK glyph has ink', g.Mask);
      AssertTrue(Format('a CJK glyph is wider than a cell (%d > %d)', [g.Mask.Width, m.CellW]), g.Mask.Width > m.CellW);
    finally
      g.Free;
    end;
    { W in a cell three pixels narrower than its advance: squeezed }
    s.LetterSpacingLogical := -3;
    m := TyTermMeasureCell(s);
    g := r.Rasterize(Key('W'), s, m);
    try
      AssertNotNull(g.Mask);
      AssertTrue(Format('squeezed into %d px (got %d + %d)', [m.CellW, g.OffsetX, g.Mask.Width]),
        g.OffsetX + g.Mask.Width <= m.CellW);
    finally
      g.Free;
    end;
    { a zero-width space: no ink, an empty glyph, cached like any other }
    s := SpecOf(9, 96);
    m := TyTermMeasureCell(s);
    k := Key(#$E2#$80#$8B);
    g := r.Rasterize(k, s, m);
    AssertNull('no ink, no mask', g.Mask);
    cache.Add(k, g);
    hits := cache.Hits;
    AssertNotNull(cache.Find(k));
    AssertEquals('the empty glyph is a hit', hits + 1, cache.Hits);
  finally
    cache.Free;
    r.Free;
  end;
end;

{ A row of the given cells written through a real core (so the line carries real
  attributes); the caller frees the core. }
function RowOf(const AData: RawByteString; ACols: Integer; out ACore: TTyTerminalCore): TTyTerminalLine;
begin
  ACore := TTyTerminalCore.Create(ACols, 2);
  ACore.WriteSync(AData);
  Result := ACore.Buffer.GetLine(ACore.Buffer.YBase);
end;

{ One bitmap per way, the same ground: every drawn glyph through the mask (and its
  gamma blend) against drawing it straight onto the surface through Canvas2D with the
  cell as the clip -- how the row painter drew them before. }
procedure TTyTerminalRenderTests.TestDrawnGlyphMasksMatchDrawingThem;
const
  PPIs: array[0..1] of Integer = (96, 144);
  Grounds: array[0..1] of Cardinal = ($1E1E1E, $F0F0F0);
var
  a, b: TBGRABitmap;
  m: TTyTermCellMetrics;
  mi, pi_, gi, x, y, d, maxDiff, diffPx, total, glyphs: Integer;
  cp: Cardinal;
  pa, pb: TBGRAPixel;
begin
  maxDiff := 0;
  diffPx := 0;
  total := 0;
  glyphs := 0;
  for mi := 0 to 1 do
    for pi_ := 0 to 1 do
      for gi := 0 to 1 do
      begin
        if mi = 0 then m := TyTermTestMetrics(9, 18) else m := TyTermTestMetrics(10, 23);
        for cp := $2500 to $259F do
        begin
          if not TyTermIsCustomGlyph(cp) then Continue;
          { two cells side by side at an odd x, so the shade patterns are phased }
          a := TBGRABitmap.Create(3 * m.CellW, m.CellH, TyTermRgbToPixel(Grounds[gi]));
          b := TBGRABitmap.Create(3 * m.CellW, m.CellH, TyTermRgbToPixel(Grounds[gi]));
          try
            TyTermDrawCustomGlyphDirect(a, Rect(1, 0, 1 + m.CellW, m.CellH), cp, TyTermRgbToPixel(Ink), PPIs[pi_]);
            TyTermDrawCustomGlyphDirect(a, Rect(1 + m.CellW, 0, 1 + 2 * m.CellW, m.CellH), cp, TyTermRgbToPixel(Ink), PPIs[pi_]);
            TyTermDrawCustomGlyph(b, Rect(1, 0, 1 + m.CellW, m.CellH), cp, TyTermRgbToPixel(Ink), m, PPIs[pi_]);
            TyTermDrawCustomGlyph(b, Rect(1 + m.CellW, 0, 1 + 2 * m.CellW, m.CellH), cp, TyTermRgbToPixel(Ink), m, PPIs[pi_]);
            Inc(glyphs);
            for y := 0 to a.Height - 1 do
              for x := 0 to a.Width - 1 do
              begin
                pa := a.GetPixel(x, y);
                pb := b.GetPixel(x, y);
                d := Max(Abs(pa.red - pb.red), Max(Abs(pa.green - pb.green), Abs(pa.blue - pb.blue)));
                Inc(total);
                if d > 0 then Inc(diffPx);
                if d > maxDiff then maxDiff := d;
              end;
          finally
            a.Free;
            b.Free;
          end;
        end;
      end;
  WriteLn(Format('TTyTerminalRenderTests.TestDrawnGlyphMasksMatchDrawingThem: %d glyph drawings, %d of %d pixels differ, by at most %d',
    [glyphs, diffPx, total, maxDiff]));
  AssertTrue('glyphs compared', glyphs > 4 * 150);
  { the one difference that can remain: a pixel two parts of a glyph both half-cover
    (a heavy stroke over a light one) is blended once through the mask, twice direct --
    the same sum, rounded once instead of twice }
  AssertTrue(Format('at most 1 of 255 off (%d)', [maxDiff]), maxDiff <= 1);
end;

procedure TTyTerminalRenderTests.TestDrawnGlyphsAreCachedPerCellAndPhase;
var
  p: TTyTermRowPainter;
  cache: TTyTermGlyphCache;
  core: TTyTerminalCore;
  line: TTyTerminalLine;
  a, b: TBGRABitmap;
  m: TTyTermCellMetrics;
  mi, c, x, y, px, py: Integer;
  s: TTyTermFontSpec;
  seen: set of 0..15;
  phases: array[0..1] of Integer;
begin
  cache := TTyTermGlyphCache.Create;
  p := TTyTermRowPainter.Create;
  { four light shades, a vertical line and a full block; the cache outlives a change of
    cell size (the control clears it then, the key must not rely on that) }
  line := RowOf(#$E2#$96#$91#$E2#$96#$91#$E2#$96#$91#$E2#$96#$91#$E2#$94#$82#$E2#$96#$88, 6, core);
  try
    for mi := 0 to 1 do
    begin
      if mi = 0 then m := TyTermTestMetrics(9, 18) else m := TyTermTestMetrics(10, 23);
      s := Default(TTyTermFontSpec);
      s.PPI := 96;
      p.Metrics := m;
      p.Spec := s;
      p.Resolver := @Resolve;
      p.GlyphCache := cache;
      p.DrawBoldBright := True;
      seen := [];
      for c := 0 to 3 do
      begin
        TyTermCustomGlyphPhase($2591, 1 + c * m.CellW, 0, px, py);
        Include(seen, px * 4 + py);
      end;
      phases[mi] := 0;
      for c := 0 to 15 do
        if c in seen then Inc(phases[mi]);
      a := TBGRABitmap.Create(6 * m.CellW + 1, m.CellH, TyTermSentinel);
      b := TBGRABitmap.Create(6 * m.CellW + 1, m.CellH, TyTermSentinel);
      try
        { painted at x = 1: an odd cell width makes neighbouring shades differently phased }
        AssertTrue('complete', p.PaintRow(a, 1, 0, line, 6, -1, tcpNone));
        { the reference: the same backgrounds, each glyph drawn straight }
        b.FillRect(1, 0, 1 + 6 * m.CellW, m.CellH, TyTermRgbToPixel(Resolve(257)), dmSet);
        for c := 0 to 5 do
          TyTermDrawCustomGlyphDirect(b, Rect(1 + c * m.CellW, 0, 1 + (c + 1) * m.CellW, m.CellH),
            line.GetCodePoint(c), TyTermRgbToPixel(Resolve(256)), 96);
        for y := 0 to a.Height - 1 do
          for x := 0 to a.Width - 1 do
            AssertTrue(Format('%dx%d cell: (%d,%d) as drawn directly', [m.CellW, m.CellH, x, y]),
              TyTermSamePixel(a.GetPixel(x, y), (Cardinal(b.GetPixel(x, y).red) shl 16)
                or (Cardinal(b.GetPixel(x, y).green) shl 8) or b.GetPixel(x, y).blue));
      finally
        a.Free;
        b.Free;
      end;
    end;
    { per cell size: one mask per phase the shades landed on, the line, the block }
    AssertEquals(Format('masks cached: (%d + %d shade phases) + 2 x (line + block)', [phases[0], phases[1]]),
      phases[0] + phases[1] + 4, cache.Count);
    AssertTrue('an odd cell width phases neighbouring shades differently', phases[0] > 1);
  finally
    core.Free;
    p.Free;
    cache.Free;
  end;
end;

procedure TTyTerminalRenderTests.TestGlyphKeysKeepCellCountsApart;
var
  cache: TTyTermGlyphCache;
  k: TTyTermGlyphKey;
begin
  cache := TTyTermGlyphCache.Create;
  try
    k := Key('marked');
    k.Cells := 1;
    cache.Add(k, TTyTermGlyph.Create);
    k.Cells := 17;                    { 1 + 16: a nibble would take them for one }
    AssertNull('17 cells is another glyph than 1', cache.Find(k));
    k.Cells := 257;
    AssertNull('257 cells is another glyph than 1', cache.Find(k));
    cache.Add(k, TTyTermGlyph.Create);
    AssertEquals('two entries', 2, cache.Count);
    AssertNotNull('and each is found', cache.Find(k));
  finally
    cache.Free;
  end;
end;

procedure TTyTerminalRenderTests.TestSingleCodePointsAreCachedByCode;
var
  p: TTyTermRowPainter;
  cache: TTyTermGlyphCache;
  r: TTyTermGlyphRasterizer;
  core: TTyTerminalCore;
  line: TTyTerminalLine;
  bmp: TBGRABitmap;
  s: TTyTermFontSpec;
  m: TTyTermCellMetrics;
begin
  cache := TTyTermGlyphCache.Create;
  r := TTyTermGlyphRasterizer.Create;
  p := TTyTermRowPainter.Create;
  { 中 中 bold-中 é: two CJK glyphs and a Latin one, none of them ASCII }
  line := RowOf(#$E4#$B8#$AD#$E4#$B8#$AD#27'[1m'#$E4#$B8#$AD#27'[0m'#$C3#$A9, 8, core);
  try
    s := SpecOf(9, 96);
    m := TyTermMeasureCell(s);
    p.Metrics := m;
    p.Spec := s;
    p.Resolver := @Resolve;
    p.GlyphCache := cache;
    p.Rasterizer := r;
    bmp := TBGRABitmap.Create(8 * m.CellW, m.CellH, TyTermSentinel);
    try
      AssertTrue(p.PaintRow(bmp, 0, 0, line, 8, -1, tcpNone));
    finally
      bmp.Free;
    end;
    AssertEquals('regular 中, bold 中, é', 3, cache.Count);
    AssertEquals('the second 中 was a hit', 1, cache.Hits);
    AssertNotNull('filed under its code', cache.FindCode(TyTermCodeKey($4E2D, False, False, 2, tfkMain)));
    AssertNotNull('bold apart', cache.FindCode(TyTermCodeKey($4E2D, True, False, 2, tfkMain)));
    AssertNotNull('é', cache.FindCode(TyTermCodeKey($E9, False, False, 1, tfkMain)));
  finally
    core.Free;
    p.Free;
    r.Free;
    cache.Free;
  end;
end;

type
  TStepClock = class
    Now: Double;
    function Tick: Double;
  end;

function TStepClock.Tick: Double;
begin
  Now := Now + 1;           { every look at the clock is a millisecond later }
  Result := Now;
end;

procedure TTyTerminalRenderTests.TestTheRasterBudgetSpreadsGlyphsOverFrames;
var
  p: TTyTermRowPainter;
  cache: TTyTermGlyphCache;
  r: TTyTermGlyphRasterizer;
  core: TTyTerminalCore;
  line: TTyTerminalLine;
  a, b: TBGRABitmap;
  s: TTyTermFontSpec;
  m: TTyTermCellMetrics;
  clk: TStepClock;
  frames, x, y: Integer;
  done: Boolean;
begin
  clk := TStepClock.Create;
  cache := TTyTermGlyphCache.Create;
  r := TTyTermGlyphRasterizer.Create;
  p := TTyTermRowPainter.Create;
  line := RowOf('Hello, glyphs!', 14, core);
  try
    s := SpecOf(9, 96);
    m := TyTermMeasureCell(s);
    p.Metrics := m;
    p.Spec := s;
    p.Resolver := @Resolve;
    p.GlyphCache := cache;
    p.Rasterizer := r;
    { the reference: no budget, one frame }
    b := TBGRABitmap.Create(14 * m.CellW, m.CellH, TyTermSentinel);
    a := TBGRABitmap.Create(14 * m.CellW, m.CellH, TyTermSentinel);
    try
      p.BeginFrame;
      AssertTrue('without a budget one frame does it', p.PaintRow(b, 0, 0, line, 14, -1, tcpNone));
      cache.Clear;
      { 2 ms a frame, the clock a millisecond on at every look: a frame draws a glyph
        or two and leaves the rest }
      p.Clock := @clk.Tick;
      p.RasterBudgetMs := 2;
      frames := 0;
      repeat
        p.BeginFrame;
        done := p.PaintRow(a, 0, 0, line, 14, -1, tcpNone);
        Inc(frames);
        AssertTrue('every frame draws at least one new glyph', p.RasterizedThisFrame >= 1);
        AssertTrue('and not all of them at once', done or (p.RasterizedThisFrame < 11));
      until done or (frames > 50);
      AssertTrue(Format('done in more than one frame (%d)', [frames]), done and (frames > 1));
      for y := 0 to a.Height - 1 do
        for x := 0 to a.Width - 1 do
          AssertTrue(Format('(%d,%d) the same as one frame without a budget', [x, y]),
            (a.GetPixel(x, y).red = b.GetPixel(x, y).red) and (a.GetPixel(x, y).green = b.GetPixel(x, y).green)
            and (a.GetPixel(x, y).blue = b.GetPixel(x, y).blue));
    finally
      a.Free;
      b.Free;
    end;
  finally
    core.Free;
    p.Free;
    r.Free;
    cache.Free;
    clk.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalRenderTests);
end.
