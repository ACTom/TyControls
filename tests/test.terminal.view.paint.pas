unit test.terminal.view.paint;
{$mode objfpc}{$H+}
{ TTyTerminalView 的像素:颜色、属性、宽字符、连线、光标、脏行、字形缓存、字体、DPI。

  画法:夹具(test.terminal.view)的哨兵底色位图 + 真父窗体 + 自建 controller;颜色都从
  controller 现解析。字体相关只数「有没有墨」(像素 ≠ 那一格的底色)和格子边界,不比字形
  像素;颜色断言用自绘的 U+2588 █(整格纯色,不受抗锯齿影响)。 }

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Terminal.Core,
  tyControls.Terminal.Render, tyControls.Terminal, test.terminal.view;

type
  TTyTerminalViewPaintTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    FClockMs: Double;
    function Clock: Double;
    function Snap: TBGRABitmap;
    function CellIs(B: TBGRABitmap; ACol, ARow: Integer; ARgb: Cardinal): Boolean;
    function CountIn(B: TBGRABitmap; const R: TRect; ARgb: Cardinal): Integer;
    function InkIn(B: TBGRABitmap; const R: TRect; ABg: Cardinal): Boolean;
    function InkRows(B: TBGRABitmap; const R: TRect; ABg: Cardinal; out ATop, ABottom: Integer): Integer;
    function Bg: Cardinal;
    function Fg: Cardinal;
    function CursorBg: Cardinal;
    function CursorInk: Cardinal;
    function MedianFullRepaint: Double;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnEmptyTerminalIsAllBackground;
    procedure TestSixteenColoursComeFromTheTheme;
    procedure Test256AndTrueColour;
    procedure TestBoldBrightens;
    procedure TestInverseDimAndHidden;
    procedure TestAWideCharacterTakesTwoCells;
    procedure TestUnderlineStyles;
    procedure TestStrikeAndOverline;
    procedure TestBoxDrawingJoinsEvenWithExtraLineHeight;
    procedure TestCursorShapes;
    procedure TestInactiveCursorStyles;
    procedure TestHiddenAndScrolledAwayCursors;
    procedure TestCursorOnAWideCharacter;
    procedure TestBlinkHidesThenRests;
    procedure TestOnlyDirtyRowsArePainted;
    procedure TestDirtyRowsFollowTheViewport;
    procedure TestGlyphsAreCachedWithoutTheirColour;
    procedure TestAFontChangeClearsTheCache;
    procedure TestTheCellScalesWithThePPI;
    procedure TestPaddingComesFromTheTheme;
    procedure TestTheFontOrder;
    procedure TestBlinkingTextIsDrawnSteady;
    procedure TestWarmRedrawTime;
    procedure TestWarmRedrawWithBoxDrawing;
    procedure TestColdFillTime;
    procedure TestDisabledDimsTowardTheParent;
    procedure TestHiddenTextStaysHiddenUnderTheCursor;
    procedure TestAFrameThatChangesOnHoverIsRepainted;
    { 4 期:选区 }
    procedure TestSelectionIsPainted;
    procedure TestSelectedTextKeepsItsColourUnlessTheThemeSaysSo;
    procedure TestAColumnIsARectangle;
    procedure TestTheSelectionScrollsWithTheText;
    procedure TestOnlyTouchedRowsRepaint;
    procedure TestADisabledSelectionIsDimmed;
    { 4 期:链接下划线 }
    procedure TestAHoveredLinkIsUnderlined;
    procedure TestAWrappedLinkIsUnderlinedOnBothRows;
  end;

implementation

const
  { a warm full 200 x 60 repaint, blit included: about 12 ms on the build machine
    (ASCII, tmux borders and mc panels alike); the limit is well above it and well
    below what a per-cell allocation costs (the Canvas2D clip took 2.5 s for tmux) }
  WarmLimitMs = 30;

function Rgb(const P: TBGRAPixel): Cardinal;
begin
  Result := (Cardinal(P.red) shl 16) or (Cardinal(P.green) shl 8) or P.blue;
end;

procedure TTyTerminalViewPaintTests.SetUp;
begin
  F := TTyTermViewFixture.Create;
  F.SizeTo(20, 5);
  FClockMs := 100000;
end;

procedure TTyTerminalViewPaintTests.TearDown;
begin
  if F <> nil then F.View.Core.Clock := nil;
  FreeAndNil(F);
end;

function TTyTerminalViewPaintTests.Clock: Double;
begin
  Result := FClockMs;
end;

function TTyTerminalViewPaintTests.Snap: TBGRABitmap;
begin
  Result := F.Render;
end;

function TTyTerminalViewPaintTests.Bg: Cardinal;
begin
  Result := F.ThemeBg('TyTerminal');
end;

function TTyTerminalViewPaintTests.Fg: Cardinal;
begin
  Result := F.ThemeFg('TyTerminal');
end;

function TTyTerminalViewPaintTests.CursorBg: Cardinal;
begin
  Result := F.ThemeBg('TyTerminalCursor');
end;

function TTyTerminalViewPaintTests.CursorInk: Cardinal;
begin
  Result := F.ThemeFg('TyTerminalCursor');
end;

function TTyTerminalViewPaintTests.CountIn(B: TBGRABitmap; const R: TRect; ARgb: Cardinal): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := Max(0, R.Top) to Min(B.Height, R.Bottom) - 1 do
    for x := Max(0, R.Left) to Min(B.Width, R.Right) - 1 do
      if Rgb(B.GetPixel(x, y)) = ARgb then Inc(Result);
end;

function TTyTerminalViewPaintTests.CellIs(B: TBGRABitmap; ACol, ARow: Integer; ARgb: Cardinal): Boolean;
var
  r: TRect;
begin
  r := F.View.CellRect(ACol, ARow);
  Result := CountIn(B, r, ARgb) = (r.Right - r.Left) * (r.Bottom - r.Top);
end;

function TTyTerminalViewPaintTests.InkIn(B: TBGRABitmap; const R: TRect; ABg: Cardinal): Boolean;
begin
  Result := CountIn(B, R, ABg) < (R.Right - R.Left) * (R.Bottom - R.Top);
end;

function TTyTerminalViewPaintTests.InkRows(B: TBGRABitmap; const R: TRect; ABg: Cardinal;
  out ATop, ABottom: Integer): Integer;
var
  x, y: Integer;
  hit: Boolean;
begin
  Result := 0;
  ATop := MaxInt;
  ABottom := -1;
  for y := R.Top to R.Bottom - 1 do
  begin
    hit := False;
    for x := R.Left to R.Right - 1 do
      if Rgb(B.GetPixel(x, y)) <> ABg then hit := True;
    if hit then
    begin
      Inc(Result);
      if y - R.Top < ATop then ATop := y - R.Top;
      if y - R.Top > ABottom then ABottom := y - R.Top;
    end;
  end;
end;

procedure TTyTerminalViewPaintTests.TestAnEmptyTerminalIsAllBackground;
var
  b: TBGRABitmap;
  w, h: Integer;
begin
  { the cursor (an outline, unfocused) would be the one thing on an empty screen }
  F.View.WriteSync(#27'[?25l');
  b := Snap;
  try
    w := b.Width;
    h := b.Height;
    AssertEquals('every pixel is the terminal background (no sentinel left)', w * h,
      CountIn(b, Rect(0, 0, w, h), Bg));
  finally
    b.Free;
  end;
  { with a border: the ring is the border colour, the rest the background }
  F.View.StyleOverride := 'border-width: 1px; border-color: #00ff00;';
  b := Snap;
  try
    { the library strokes a border antialiased: the edge pixel is green-dominated, not exact }
    AssertTrue('left edge is the border: ' + IntToHex(Rgb(b.GetPixel(0, h div 2)), 6),
      (b.GetPixel(0, h div 2).green > 150) and (b.GetPixel(0, h div 2).green > 2 * b.GetPixel(0, h div 2).red));
    AssertTrue('top edge is the border: ' + IntToHex(Rgb(b.GetPixel(w div 2, 0)), 6),
      (b.GetPixel(w div 2, 0).green > 150) and (b.GetPixel(w div 2, 0).green > 2 * b.GetPixel(w div 2, 0).red));
    AssertEquals('inside the ring', IntToHex(Bg, 6), IntToHex(Rgb(b.GetPixel(w div 2, h div 2)), 6));
    AssertEquals('no sentinel', 0, CountIn(b, Rect(0, 0, w, h), $FF00FF));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestSixteenColoursComeFromTheTheme;
var
  b: TBGRABitmap;
  s: RawByteString;
  n: Integer;
begin
  s := '';
  for n := 0 to 7 do s := s + #27'[3' + IntToStr(n) + 'm'#$E2#$96#$88;
  for n := 0 to 7 do s := s + #27'[9' + IntToStr(n) + 'm'#$E2#$96#$88;
  F.View.WriteSync(s + #27'[0m');
  b := Snap;
  try
    for n := 0 to 15 do
      AssertTrue(Format('cell %d is TyTerminalAnsi%d', [n, n]), CellIs(b, n, 0, F.Ansi(n)));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.Test256AndTrueColour;
var
  b: TBGRABitmap;
begin
  F.View.WriteSync(#27'[38;5;196m'#$E2#$96#$88#27'[38;2;1;2;3m'#$E2#$96#$88#27'[0m'#27'[48;5;21m '#27'[0m');
  b := Snap;
  try
    AssertTrue('palette 196', CellIs(b, 0, 0, $FF0000));
    AssertTrue('true colour', CellIs(b, 1, 0, $010203));
    AssertTrue('a space shows its background', CellIs(b, 2, 0, $0000FF));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestBoldBrightens;
var
  b: TBGRABitmap;
begin
  F.View.WriteSync(#27'[1;31m'#$E2#$96#$88#27'[0m');
  b := Snap;
  try
    AssertTrue('bold red is bright red', CellIs(b, 0, 0, F.Ansi(9)));
  finally
    b.Free;
  end;
  F.View.DrawBoldTextInBrightColors := False;
  b := Snap;
  try
    AssertTrue('not brightened when switched off', CellIs(b, 0, 0, F.Ansi(1)));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestInverseDimAndHidden;
var
  b: TBGRABitmap;
begin
  F.View.WriteSync(#27'[7m '#27'[0m' + #27'[2;38;2;255;0;0;48;2;0;0;0m'#$E2#$96#$88#27'[0m'
    + #27'[8m'#$E2#$96#$88#27'[0m');
  b := Snap;
  try
    AssertTrue('inverse space: the foreground', CellIs(b, 0, 0, Fg));
    AssertTrue('dim red over black', CellIs(b, 1, 0, $800000));
    AssertTrue('hidden: only the background', CellIs(b, 2, 0, Bg));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestAWideCharacterTakesTwoCells;
var
  b: TBGRABitmap;
begin
  F.View.WriteSync(#27'[?25l'#$E4#$B8#$AD'X');
  b := Snap;
  try
    AssertTrue('ink in cell 0', InkIn(b, F.View.CellRect(0, 0), Bg));
    AssertTrue('ink in cell 1', InkIn(b, F.View.CellRect(1, 0), Bg));
    AssertTrue('X in cell 2', InkIn(b, F.View.CellRect(2, 0), Bg));
    AssertFalse('nothing in cell 3', InkIn(b, F.View.CellRect(3, 0), Bg));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestUnderlineStyles;
var
  b: TBGRABitmap;
  s: Integer;
  r, band: TRect;
  m: TTyTermCellMetrics;
  top, bottom, x, y, segs, gapRun, longest4, longest5, t0: Integer;
  prev, ink: Boolean;
  tops: array of Integer;
  allSame: Boolean;
begin
  for s := 1 to 5 do
    F.View.WriteSync(Format(#27'[%d;1H'#27'[4:%dm      '#27'[0m', [s, s]));
  b := Snap;
  try
    m := F.View.CellMetrics;
    longest4 := 0;
    longest5 := 0;
    for s := 1 to 5 do
    begin
      r := F.View.CellRect(0, s - 1);
      r.Right := F.View.CellRect(5, s - 1).Right;
      AssertTrue(Format('style %d has ink', [s]), InkRows(b, r, Bg, top, bottom) > 0);
      AssertTrue(Format('style %d stays in the lower half of the cell (top ink row %d)', [s, top]),
        top > m.TextTop + m.CharH div 2);
      if s = 2 then
      begin
        x := (r.Left + r.Right) div 2;
        segs := 0;
        prev := False;
        for y := r.Top to r.Bottom - 1 do
        begin
          ink := Rgb(b.GetPixel(x, y)) <> Bg;
          if ink and not prev then Inc(segs);
          prev := ink;
        end;
        AssertEquals('double: two lines down one column', 2, segs);
      end;
      if s = 3 then
      begin
        SetLength(tops, 0);
        for x := r.Left to r.Right - 1 do
          for y := r.Top to r.Bottom - 1 do
            if Rgb(b.GetPixel(x, y)) <> Bg then
            begin
              SetLength(tops, Length(tops) + 1);
              tops[High(tops)] := y;
              Break;
            end;
        allSame := True;
        for x := 1 to High(tops) do
          if tops[x] <> tops[0] then allSame := False;
        AssertFalse('curly: the top of the ink moves along the line', allSame);
      end;
      if s in [4, 5] then
      begin
        band := Rect(r.Left, r.Top + m.UnderlineY, r.Right, r.Top + m.UnderlineY + m.LineW);
        gapRun := 0;
        t0 := 0;
        for x := band.Left to band.Right - 1 do
          if Rgb(b.GetPixel(x, band.Top)) = Bg then
          begin
            Inc(gapRun);
            if gapRun > t0 then t0 := gapRun;
          end
          else
            gapRun := 0;
        AssertTrue(Format('style %d has gaps', [s]), t0 > 0);
        if s = 4 then longest4 := t0 else longest5 := t0;
      end;
    end;
    AssertTrue(Format('dashed gaps (%d) longer than dotted (%d)', [longest5, longest4]), longest5 > longest4);
  finally
    b.Free;
  end;
  F.View.WriteSync(#27'[H'#27'[2J'#27'[4;58;2;0;0;255m '#27'[0m');
  b := Snap;
  try
    AssertTrue('the underline colour is used', CountIn(b, F.View.CellRect(0, 0), $0000FF) > 0);
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestStrikeAndOverline;
var
  b: TBGRABitmap;
  m: TTyTermCellMetrics;
  top, bottom: Integer;
begin
  F.View.WriteSync(#27'[9m '#27'[0m'#27'[53m '#27'[0m');
  b := Snap;
  try
    m := F.View.CellMetrics;
    AssertTrue('strikethrough inked', InkRows(b, F.View.CellRect(0, 0), Bg, top, bottom) > 0);
    AssertTrue(Format('strikethrough in the middle (%d..%d)', [top, bottom]),
      (top >= m.TextTop + m.CharH div 4) and (bottom <= m.TextTop + 3 * m.CharH div 4));
    AssertTrue('overline inked', InkRows(b, F.View.CellRect(1, 0), Bg, top, bottom) > 0);
    AssertTrue(Format('overline in the top third (%d..%d)', [top, bottom]), bottom < m.CellH div 3);
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestBoxDrawingJoinsEvenWithExtraLineHeight;
var
  b: TBGRABitmap;
  r: TRect;
  x, y: Integer;
  found, all: Boolean;
begin
  F.View.LineHeightPercent := 150;
  F.View.WriteSync(#$E2#$94#$82#13#10#$E2#$94#$82#13#10#$E2#$94#$82);
  b := Snap;
  try
    r := F.View.CellRect(0, 0);
    r.Bottom := F.View.CellRect(0, 2).Bottom;
    found := False;
    for x := r.Left to r.Right - 1 do
    begin
      all := True;
      for y := r.Top to r.Bottom - 1 do
        if Rgb(b.GetPixel(x, y)) = Bg then begin all := False; Break; end;
      if all then found := True;
    end;
    AssertTrue('one column inked through three cells of 150% line height', found);
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestCursorShapes;
var
  b: TBGRABitmap;
  r: TRect;
  cw, n, total, inkish, x, y: Integer;
  p: TBGRAPixel;
begin
  F.View.Enter;
  F.View.WriteSync('W'#27'[D');
  b := Snap;
  try
    r := F.View.CellRect(0, 0);
    total := (r.Right - r.Left) * (r.Bottom - r.Top);
    n := CountIn(b, r, CursorBg);
    AssertTrue(Format('block: most of the cell is the cursor colour (%d of %d)', [n, total]), n * 2 > total);
    inkish := 0;
    for y := r.Top to r.Bottom - 1 do
      for x := r.Left to r.Right - 1 do
      begin
        p := b.GetPixel(x, y);
        { closer to the cursor ink than to the cursor colour }
        if Abs(p.red - ((CursorInk shr 16) and $FF)) + Abs(p.green - ((CursorInk shr 8) and $FF)) + Abs(p.blue - (CursorInk and $FF))
          < Abs(p.red - ((CursorBg shr 16) and $FF)) + Abs(p.green - ((CursorBg shr 8) and $FF)) + Abs(p.blue - (CursorBg and $FF)) then
          Inc(inkish);
      end;
    AssertTrue('block: the glyph is redrawn in the cursor ink', inkish > 0);
  finally
    b.Free;
  end;
  cw := Max(1, MulDiv(1, F.View.Font.PixelsPerInch, 96));
  F.View.WriteSync(#27'[4 q');
  b := Snap;
  try
    r := F.View.CellRect(0, 0);
    AssertEquals('underline: the bottom rows are the cursor colour', (r.Right - r.Left) * cw,
      CountIn(b, Rect(r.Left, r.Bottom - cw, r.Right, r.Bottom), CursorBg));
    AssertEquals('underline: nothing above', 0, CountIn(b, Rect(r.Left, r.Top, r.Right, r.Bottom - cw), CursorBg));
  finally
    b.Free;
  end;
  F.View.WriteSync(#27'[6 q');
  b := Snap;
  try
    r := F.View.CellRect(0, 0);
    AssertEquals('bar: the left columns are the cursor colour', (r.Bottom - r.Top) * cw,
      CountIn(b, Rect(r.Left, r.Top, r.Left + cw, r.Bottom), CursorBg));
    AssertEquals('bar: nothing right of it', 0, CountIn(b, Rect(r.Left + cw, r.Top, r.Right, r.Bottom), CursorBg));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestInactiveCursorStyles;
var
  b: TBGRABitmap;
  r: TRect;
  lw, cx, cy: Integer;
begin
  F.View.WriteSync('W'#27'[D');
  AssertFalse('precondition: unfocused', F.View.Focus);
  b := Snap;
  try
    r := F.View.CellRect(0, 0);
    lw := F.View.CellMetrics.LineW;
    AssertEquals('outline: the top edge', (r.Right - r.Left) * lw, CountIn(b, Rect(r.Left, r.Top, r.Right, r.Top + lw), CursorBg));
    AssertEquals('outline: the left edge', (r.Bottom - r.Top) * lw, CountIn(b, Rect(r.Left, r.Top, r.Left + lw, r.Bottom), CursorBg));
    cx := (r.Left + r.Right) div 2;
    cy := (r.Top + r.Bottom) div 2;
    AssertTrue('outline: the middle is not filled', Rgb(b.GetPixel(cx, cy)) <> CursorBg);
  finally
    b.Free;
  end;
  F.View.CursorInactiveStyle := tcisNone;
  b := Snap;
  try
    AssertEquals('none: no cursor colour', 0, CountIn(b, F.View.CellRect(0, 0), CursorBg));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestHiddenAndScrolledAwayCursors;
var
  b: TBGRABitmap;
  i: Integer;
  s: RawByteString;
begin
  F.View.Enter;
  F.View.WriteSync(#27'[?25l');
  b := Snap;
  try
    AssertEquals('DECTCEM off: no cursor', 0, CountIn(b, Rect(0, 0, b.Width, b.Height), CursorBg));
  finally
    b.Free;
  end;
  s := #27'[?25h';
  for i := 1 to 30 do s := s + 'line ' + IntToStr(i) + #13#10;
  F.View.WriteSync(s);
  F.View.ScrollLines(-2);
  b := Snap;
  try
    AssertEquals('scrolled up: no cursor', 0, CountIn(b, Rect(0, 0, b.Width, b.Height), CursorBg));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestCursorOnAWideCharacter;
var
  b: TBGRABitmap;
  r: TRect;
  n, total: Integer;
begin
  F.View.Enter;
  F.View.WriteSync(#$E4#$B8#$AD#13);
  b := Snap;
  try
    r := F.View.CellRect(0, 0);
    r.Right := F.View.CellRect(1, 0).Right;
    total := (r.Right - r.Left) * (r.Bottom - r.Top);
    n := CountIn(b, Rect(r.Left, r.Top, (r.Left + r.Right) div 2, r.Bottom), CursorBg);
    AssertTrue(Format('the first cell mostly cursor (%d)', [n]), n * 4 > total);
    n := CountIn(b, Rect((r.Left + r.Right) div 2, r.Top, r.Right, r.Bottom), CursorBg);
    AssertTrue(Format('the second cell mostly cursor (%d)', [n]), n * 4 > total);
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestBlinkHidesThenRests;
var
  b: TBGRABitmap;
  t0: Double;
  i: Integer;
  dirtied: Boolean;
begin
  F.View.Core.Clock := @Clock;
  F.View.CursorBlink := True;
  F.View.Enter;
  t0 := FClockMs;
  AssertTrue('the blink timer runs when focused', F.View.BlinkOn);
  b := Snap;
  b.Free;
  F.View.ClearInvalidated;
  F.View.Tick(t0 + 600);
  dirtied := False;
  for i := 0 to High(F.View.Invalidated) do
    if (F.View.Invalidated[i].X <= 0) and (F.View.Invalidated[i].Y >= 0) then dirtied := True;
  AssertTrue('the cursor row was marked dirty', dirtied);
  b := Snap;
  try
    AssertEquals('hidden phase: no cursor colour', 0, CountIn(b, Rect(0, 0, b.Width, b.Height), CursorBg));
  finally
    b.Free;
  end;
  F.View.Tick(t0 + 1200);
  b := Snap;
  try
    AssertTrue('shown again', CountIn(b, F.View.CellRect(0, 0), CursorBg) > 0);
  finally
    b.Free;
  end;
  F.View.Tick(t0 + 1800);
  F.View.Tick(t0 + 300000);
  AssertFalse('five idle minutes: the timer stops', F.View.BlinkOn);
  b := Snap;
  try
    AssertTrue('and the cursor rests visible', CountIn(b, F.View.CellRect(0, 0), CursorBg) > 0);
  finally
    b.Free;
  end;
  FClockMs := t0 + 300100;
  F.View.WriteSync('x');
  AssertTrue('output wakes it again', F.View.BlinkOn);
  { the program asks for a blinking cursor: blinks with the property off }
  F.View.CursorBlink := False;
  AssertFalse('property off: no timer', F.View.BlinkOn);
  F.View.WriteSync(#27'[1 q');
  AssertTrue('DECSCUSR 1 makes it blink', F.View.BlinkOn);
end;

procedure TTyTerminalViewPaintTests.TestOnlyDirtyRowsArePainted;
var
  b: TBGRABitmap;
  before, i: Integer;
begin
  F.View.WriteSync(#27'[4;1H');
  b := Snap;
  b.Free;
  before := F.View.PaintedRows;
  F.View.ClearInvalidated;
  F.View.WriteSync('x');
  b := Snap;
  b.Free;
  AssertEquals('one row painted', before + 1, F.View.PaintedRows);
  AssertTrue('something invalidated', Length(F.View.Invalidated) > 0);
  for i := 0 to High(F.View.Invalidated) do
  begin
    AssertEquals('only row 3 invalidated (first)', 3, F.View.Invalidated[i].X);
    AssertEquals('only row 3 invalidated (last)', 3, F.View.Invalidated[i].Y);
  end;
end;

procedure TTyTerminalViewPaintTests.TestDirtyRowsFollowTheViewport;
var
  b: TBGRABitmap;
  s: RawByteString;
  i, before: Integer;
begin
  s := '';
  for i := 1 to 30 do
  begin
    s := s + 'line ' + IntToStr(i);
    if i < 30 then s := s + #13#10;
  end;
  F.View.WriteSync(s);
  AssertEquals('the cursor on the last screen row', 4, F.View.Core.Buffer.Y);
  b := Snap;
  b.Free;
  F.View.ScrollLines(-2);
  b := Snap;
  b.Free;
  { (a) a character on screen row 4 is viewport row 6: off the viewport }
  before := F.View.PaintedRows;
  F.View.ClearInvalidated;
  F.View.WriteSync('y');
  b := Snap;
  b.Free;
  AssertEquals('(a) nothing painted', before, F.View.PaintedRows);
  AssertEquals('(a) nothing invalidated', 0, Length(F.View.Invalidated));
  { (b) screen row 1 is viewport row 3 }
  F.View.WriteSync(#27'[2;1H');
  b := Snap;
  b.Free;
  before := F.View.PaintedRows;
  F.View.ClearInvalidated;
  F.View.WriteSync('z');
  b := Snap;
  b.Free;
  AssertEquals('(b) one row painted', before + 1, F.View.PaintedRows);
  AssertTrue('(b) invalidated', Length(F.View.Invalidated) > 0);
  for i := 0 to High(F.View.Invalidated) do
  begin
    AssertEquals('(b) viewport row 3 (first)', 3, F.View.Invalidated[i].X);
    AssertEquals('(b) viewport row 3 (last)', 3, F.View.Invalidated[i].Y);
  end;
end;

procedure TTyTerminalViewPaintTests.TestGlyphsAreCachedWithoutTheirColour;
var
  b: TBGRABitmap;
  n: Integer;
begin
  F.View.WriteSync('aaaa');
  b := Snap;
  b.Free;
  AssertEquals('one miss', 1, F.View.Cache.Misses);
  AssertTrue('three hits', F.View.Cache.Hits >= 3);
  n := F.View.Cache.Count;
  F.View.WriteSync(#27'[31ma'#27'[0m');
  b := Snap;
  b.Free;
  AssertEquals('a red a is the same glyph', n, F.View.Cache.Count);
  F.View.WriteSync(#27'[1ma'#27'[0m');
  b := Snap;
  b.Free;
  AssertEquals('a bold a is another glyph', n + 1, F.View.Cache.Count);
end;

procedure TTyTerminalViewPaintTests.TestAFontChangeClearsTheCache;
var
  b: TBGRABitmap;
  h0, misses: Integer;
begin
  { ParentFont off first, at the theme's size, so what changes below is the size alone }
  F.View.ParentFont := False;
  F.View.Font.Size := 9;
  F.View.WriteSync('a');
  b := Snap;
  b.Free;
  h0 := F.View.CellMetrics.CellH;
  misses := F.View.Cache.Misses;
  F.View.Font.Size := 16;
  b := Snap;
  b.Free;
  AssertTrue(Format('a taller cell (%d -> %d)', [h0, F.View.CellMetrics.CellH]), F.View.CellMetrics.CellH > h0);
  AssertEquals('only the glyph drawn since', 1, F.View.Cache.Count);
  AssertEquals('drawn again at the new size', misses + 1, F.View.Cache.Misses);
end;

procedure TTyTerminalViewPaintTests.TestTheCellScalesWithThePPI;
var
  b: TBGRABitmap;
  w96: Integer;
  ratio: Double;
  top, bottom: Integer;
  r: TRect;
begin
  F.View.WriteSync(#27'[4m '#27'[0m');
  b := F.Render(96);
  b.Free;
  w96 := F.View.CellMetrics.CellW;
  b := F.Render(144);
  b.Free;
  ratio := F.View.CellMetrics.CellW / w96;
  AssertTrue(Format('cell width %d at 96, %d at 144', [w96, F.View.CellMetrics.CellW]), (ratio >= 1.4) and (ratio <= 1.6));
  b := F.Render(192);
  try
    r := Rect(MulDiv(2, 192, 96), MulDiv(2, 192, 96), MulDiv(2, 192, 96) + F.View.CellMetrics.CellW,
      MulDiv(2, 192, 96) + F.View.CellMetrics.CellH);
    AssertEquals('a single underline is two rows thick at 192 PPI', 2, InkRows(b, r, Bg, top, bottom));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestPaddingComesFromTheTheme;
var
  r: TRect;
  cols: Integer;
begin
  cols := F.View.Cols;
  F.View.StyleOverride := 'padding: 10px';
  r := F.View.CellRect(0, 0);
  AssertEquals('left', MulDiv(10, F.View.Font.PixelsPerInch, 96), r.Left);
  AssertEquals('top', MulDiv(10, F.View.Font.PixelsPerInch, 96), r.Top);
  AssertTrue(Format('fewer columns (%d -> %d)', [cols, F.View.Cols]), F.View.Cols < cols);
end;

procedure TTyTerminalViewPaintTests.TestTheFontOrder;

  function MainName: string;
  begin
    F.View.CellRect(0, 0);           { re-resolves the spec }
    Result := F.View.Spec.MainName;
  end;

begin
  AssertEquals('monospace is Consolas on Windows', 'Consolas', MainName);
  F.View.StyleOverride := 'font-family: Courier New';
  AssertEquals('StyleOverride', 'Courier New', MainName);
  F.View.StyleOverride := '';
  F.View.ParentFont := False;
  F.View.Font.Name := 'Lucida Console';
  AssertEquals('an explicit Font', 'Lucida Console', MainName);
  F.View.StyleOverride := 'font-family: Courier New';
  AssertEquals('StyleOverride beats Font', 'Courier New', MainName);
  F.View.StyleOverride := '';
  F.View.Font.Name := 'default';
  AssertEquals('Font.Name default falls back to the token', 'Consolas', MainName);
end;

procedure TTyTerminalViewPaintTests.TestBlinkingTextIsDrawnSteady;
var
  a, b: TBGRABitmap;
  x, y: Integer;
  r: TRect;
begin
  F.View.WriteSync(#27'[5m'#$E2#$96#$88#27'[0m');
  a := Snap;
  try
    AssertTrue('blinking text is drawn', CellIs(a, 0, 0, Fg));
    F.View.Tick(1e9);
    F.View.DrawBoldTextInBrightColors := False;   { a full repaint }
    b := Snap;
    try
      r := F.View.CellRect(0, 0);
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
          AssertEquals('steady', Rgb(a.GetPixel(x, y)), Rgb(b.GetPixel(x, y)));
    finally
      b.Free;
    end;
  finally
    a.Free;
  end;
end;

{ Five full repaints of whatever is on screen (a property flip marks every row dirty),
  each timed as the RenderTo into a device bitmap that lives across the frames -- the
  rows AND the blit, nothing else; the median in ms. }
function TTyTerminalViewPaintTests.MedianFullRepaint: Double;
var
  bmp: TBitmap;
  times: array[0..4] of Double;
  t0, tmp: Double;
  i, j, k, w, h: Integer;
begin
  w := F.View.ClientWidth;
  h := F.View.ClientHeight;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(w, h);
    { warm: the surface exists and every glyph is cached (a frame draws only so many
      new glyphs, the rest come in the frames after) }
    k := 0;
    repeat
      F.View.Render(bmp.Canvas, Rect(0, 0, w, h), F.View.Font.PixelsPerInch);
      Inc(k);
    until (not F.View.RowsPending) or (k > 1000);
    F.View.DrawBoldTextInBrightColors := not F.View.DrawBoldTextInBrightColors;
    F.View.Render(bmp.Canvas, Rect(0, 0, w, h), F.View.Font.PixelsPerInch);
    AssertFalse('warm: nothing left to draw', F.View.RowsPending);
    for k := 0 to 4 do
    begin
      F.View.DrawBoldTextInBrightColors := not F.View.DrawBoldTextInBrightColors;
      t0 := TyTermDefaultClock;
      F.View.Render(bmp.Canvas, Rect(0, 0, w, h), F.View.Font.PixelsPerInch);
      times[k] := TyTermDefaultClock - t0;
    end;
    for i := 0 to 4 do
      for j := i + 1 to 4 do
        if times[j] < times[i] then begin tmp := times[i]; times[i] := times[j]; times[j] := tmp; end;
    Result := times[2];
    { the rows alone (no canvas, no blit), printed for the record }
    for k := 0 to 4 do
    begin
      F.View.DrawBoldTextInBrightColors := not F.View.DrawBoldTextInBrightColors;
      t0 := TyTermDefaultClock;
      F.View.Render(nil, Rect(0, 0, w, h), F.View.Font.PixelsPerInch);
      times[k] := TyTermDefaultClock - t0;
    end;
    for i := 0 to 4 do
      for j := i + 1 to 4 do
        if times[j] < times[i] then begin tmp := times[i]; times[i] := times[j]; times[j] := tmp; end;
    WriteLn(Format('  (the rows alone, without the blit: median %.1f ms)', [times[2]]));
  finally
    bmp.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestWarmRedrawTime;
var
  s: RawByteString;
  row, col: Integer;
  ms: Double;
begin
  F.SizeTo(200, 60);
  s := #27'[H';
  for row := 0 to 59 do
  begin
    for col := 0 to 199 do
      s := s + Chr(33 + (row * 200 + col) mod 94);
    if row < 59 then s := s + #13#10;
  end;
  F.View.WriteSync(s);
  ms := MedianFullRepaint;
  WriteLn(Format('TTyTerminalViewPaintTests.TestWarmRedrawTime: 200 x 60 ASCII, warm full repaint + blit, median %.1f ms',
    [ms]));
  AssertTrue(Format('a warm full screen of ASCII within %d ms (%.1f)', [WarmLimitMs, ms]), ms <= WarmLimitMs);
end;

procedure TTyTerminalViewPaintTests.TestColdFillTime;
var
  s: RawByteString;
  st, ch, frames: Integer;
  bmp: TBitmap;
  t0, ms: Double;
begin
  { 95 printable ASCII x regular, bold, italic, bold italic: 380 glyphs never drawn }
  F.SizeTo(100, 8);
  s := #27'[H';
  for st := 0 to 3 do
  begin
    case st of
      1: s := s + #27'[1m';
      2: s := s + #27'[22;3m';
      3: s := s + #27'[1;3m';
    end;
    for ch := 32 to 126 do s := s + Chr(ch);
    s := s + #27'[0m'#13#10;
  end;
  F.View.WriteSync(s);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(F.View.ClientWidth, F.View.ClientHeight);
    frames := 0;
    t0 := TyTermDefaultClock;
    repeat
      F.View.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), F.View.Font.PixelsPerInch);
      Inc(frames);
    until (not F.View.RowsPending) or (frames > 1000);
    ms := TyTermDefaultClock - t0;
  finally
    bmp.Free;
  end;
  WriteLn(Format('TTyTerminalViewPaintTests.TestColdFillTime: 380 glyphs from an empty cache, %.1f ms in %d frame(s) (%.3f ms a glyph)',
    [ms, frames, ms / 380]));
  AssertTrue('every glyph drawn in the end', F.View.Cache.Count >= 376);
end;

procedure TTyTerminalViewPaintTests.TestWarmRedrawWithBoxDrawing;
var
  s: RawByteString;
  row, col, boxes: Integer;
  ms: Double;
begin
  F.SizeTo(200, 60);
  { tmux, two panes: text everywhere, one vertical rule down column 100 and one
    horizontal rule across row 30 -- 60 + 199 drawn cells }
  s := #27'[H';
  boxes := 0;
  for row := 0 to 59 do
  begin
    for col := 0 to 199 do
      if row = 30 then
      begin
        if col = 100 then s := s + #$E2#$94#$BC else s := s + #$E2#$94#$80;   { ┼ ─ }
        Inc(boxes);
      end
      else if col = 100 then
      begin
        s := s + #$E2#$94#$82;                                               { │ }
        Inc(boxes);
      end
      else
        s := s + Chr(33 + (row * 200 + col) mod 94);
    if row < 59 then s := s + #13#10;
  end;
  F.View.WriteSync(s);
  ms := MedianFullRepaint;
  WriteLn(Format('TTyTerminalViewPaintTests.TestWarmRedrawWithBoxDrawing: tmux borders (%d drawn cells), warm full repaint + blit, median %.1f ms',
    [boxes, ms]));
  AssertTrue(Format('tmux borders within %d ms (%.1f)', [WarmLimitMs, ms]), ms <= WarmLimitMs);
  { mc: double-line rules along the top and bottom and down both sides, shades in
    between -- about 500 drawn cells }
  s := #27'[H'#27'[2J';
  boxes := 0;
  for row := 0 to 59 do
  begin
    for col := 0 to 199 do
      if (row = 0) or (row = 59) then
      begin
        s := s + #$E2#$95#$90;                                               { ═ }
        Inc(boxes);
      end
      else if (col = 0) or (col = 199) then
      begin
        s := s + #$E2#$95#$91;                                               { ║ }
        Inc(boxes);
      end
      else if (row mod 3 = 1) and (col mod 50 < 20) then
        s := s + #$E2#$96#$91                                                { ░ }
      else
        s := s + Chr(33 + (row * 200 + col) mod 94);
    if row < 59 then s := s + #13#10;
  end;
  F.View.WriteSync(s);
  ms := MedianFullRepaint;
  WriteLn(Format('TTyTerminalViewPaintTests.TestWarmRedrawWithBoxDrawing: mc panels (%d drawn cells + shades), warm full repaint + blit, median %.1f ms',
    [boxes, ms]));
  AssertTrue(Format('mc panels within %d ms (%.1f)', [WarmLimitMs, ms]), ms <= WarmLimitMs);
end;

function Mix(AColor, ABase: Cardinal; AAlpha: Integer): Cardinal;
begin
  Result := ((((AColor shr 16) and $FF) * Cardinal(AAlpha) + ((ABase shr 16) and $FF) * Cardinal(255 - AAlpha) + 127) div 255) shl 16
    or ((((AColor shr 8) and $FF) * Cardinal(AAlpha) + ((ABase shr 8) and $FF) * Cardinal(255 - AAlpha) + 127) div 255) shl 8
    or (((AColor and $FF) * Cardinal(AAlpha) + (ABase and $FF) * Cardinal(255 - AAlpha) + 127) div 255);
end;

procedure TTyTerminalViewPaintTests.TestDisabledDimsTowardTheParent;
var
  b: TBGRABitmap;
  st: TTyStyleSet;
  a: Integer;
  pc: TTyColor;
  base: Cardinal;
begin
  F.View.WriteSync(#27'[?25l'#27'[31m'#$E2#$96#$88#27'[0m');
  b := Snap;
  try
    AssertTrue('enabled: the red itself', CellIs(b, 0, 0, F.Ansi(1)));
  finally
    b.Free;
  end;
  { what the theme says a disabled terminal is, and what it fades toward (the fixture's
    patch rewrites TyTerminal, which hides the base layer's :disabled -- say it again) }
  F.Ctl.StyleOverride := TyTermFixtureCss + 'TyTerminal:disabled { opacity: 0.4; }'#10;
  st := F.Ctl.Model.ResolveStyle('TyTerminal', '', [tysDisabled]);
  AssertTrue('the theme gives :disabled an opacity', tpOpacity in st.Present);
  a := EnsureRange(Round(st.Opacity * 255), 0, 255);
  AssertTrue('a real fade', a < 255);
  AssertTrue('the parent has a colour', TyResolveParentBg(F.View, pc));
  base := Cardinal(pc) and $FFFFFF;
  F.View.Enabled := False;
  b := Snap;
  try
    AssertTrue(Format('disabled: the red faded toward the parent (%s)', [IntToHex(Mix(F.Ansi(1), base, a), 6)]),
      CellIs(b, 0, 0, Mix(F.Ansi(1), base, a)));
    AssertTrue('the empty cells faded', CellIs(b, 3, 2, Mix(Bg, base, a)));
    AssertEquals('the padding faded with them', IntToHex(Mix(Bg, base, a), 6), IntToHex(Rgb(b.GetPixel(0, 0)), 6));
  finally
    b.Free;
  end;
  AssertEquals('what the program asks still gets the theme''s colour', IntToHex(F.Ansi(1), 6),
    IntToHex(F.View.Core.ResolveColor(1), 6));
  F.View.Enabled := True;
  b := Snap;
  try
    AssertTrue('enabled again: the red itself', CellIs(b, 0, 0, F.Ansi(1)));
    AssertEquals('and the padding', IntToHex(Bg, 6), IntToHex(Rgb(b.GetPixel(0, 0)), 6));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestHiddenTextStaysHiddenUnderTheCursor;
var
  b: TBGRABitmap;
begin
  F.View.Enter;
  F.View.WriteSync(#27'[8mW'#27'[0m'#27'[D');
  b := Snap;
  try
    AssertTrue('the block cursor over hidden text is the cursor colour only', CellIs(b, 0, 0, CursorBg));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestAFrameThatChangesOnHoverIsRepainted;
var
  c: TTyStyleController;
  b: TBGRABitmap;
  n, h: Integer;
begin
  c := TTyStyleController.Create(nil);
  try
    c.Mode := 'light';
    c.ThemeName := 'default';
    c.StyleOverride := TyTermFixtureCss
      + 'TyTerminal { border-width: 1px; border-color: #102030; }'#10
      + 'TyTerminal:hover { border-color: #00ff00; }'#10;
    F.View.Controller := c;
    b := Snap;
    try
      h := b.Height;
      AssertTrue('no hover: the edge is not green', b.GetPixel(0, h div 2).green < 150);
    finally
      b.Free;
    end;
    n := F.View.Invalidations;
    F.View.Hover(True);
    AssertEquals('the frame changes on hover: repainted', n + 1, F.View.Invalidations);
    b := Snap;
    try
      AssertTrue('hovered: the edge is green ' + IntToHex(Rgb(b.GetPixel(0, h div 2)), 6),
        (b.GetPixel(0, h div 2).green > 150) and (b.GetPixel(0, h div 2).green > 2 * b.GetPixel(0, h div 2).red));
    finally
      b.Free;
    end;
    F.View.Hover(False);
    b := Snap;
    try
      AssertTrue('left again: not green', b.GetPixel(0, h div 2).green < 150);
    finally
      b.Free;
    end;
  finally
    F.View.Controller := F.Ctl;
    c.Free;
  end;
end;

{ ---- 4 期:链接下划线 ------------------------------------------------------------------ }

{ the link colour's pixels in the underline band (UnderlineY, LineW rows) of a cell }
function LinkBand(ATest: TTyTerminalViewPaintTests; B: TBGRABitmap; AView: TTyTerminalViewProbe;
  ACol, ARow: Integer; ALink: Cardinal): Integer;
var
  r: TRect;
  m: TTyTermCellMetrics;
  x, y: Integer;
begin
  r := AView.CellRect(ACol, ARow);
  m := AView.CellMetrics;
  Result := 0;
  for y := r.Top + m.UnderlineY to r.Top + m.UnderlineY + m.LineW - 1 do
    for x := r.Left to r.Right - 1 do
      if Rgb(B.GetPixel(x, y)) = ALink then Inc(Result);
end;

procedure TTyTerminalViewPaintTests.TestAHoveredLinkIsUnderlined;
var
  b: TBGRABitmap;
  c, full: Integer;
  link: Cardinal;
  m: TTyTermCellMetrics;
begin
  F.SizeTo(40, 5);
  F.View.SetPlatform(False, True);
  F.View.WriteSync(#27'[?25l' + 'see https://example.com now');
  link := F.ThemeFg('TyTerminalLink');
  AssertTrue('the link colour is not the text''s', link <> Fg);
  F.View.MoveTo([ssCtrl], F.View.CellCenter(8, 0));
  AssertTrue('hovering', F.View.HoverOn);
  m := F.View.CellMetrics;
  b := Snap;
  try
    for c := 4 to 22 do
    begin
      full := (F.View.CellRect(c, 0).Right - F.View.CellRect(c, 0).Left) * m.LineW;
      AssertEquals(Format('cell %d: the underline band is the link colour', [c]), full,
        LinkBand(Self, b, F.View, c, 0, link));
    end;
    AssertEquals('before the address: none', 0, LinkBand(Self, b, F.View, 3, 0, link));
    AssertEquals('after it: none', 0, LinkBand(Self, b, F.View, 23, 0, link));
  finally
    b.Free;
  end;
  F.View.KeyUpNow(VK_CONTROL, []);
  AssertFalse('Ctrl let go', F.View.HoverOn);
  b := Snap;
  try
    for c := 4 to 22 do
      AssertEquals(Format('cell %d: no underline any more', [c]), 0, LinkBand(Self, b, F.View, c, 0, link));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestAWrappedLinkIsUnderlinedOnBothRows;
var
  b: TBGRABitmap;
  link: Cardinal;
begin
  F.View.SetPlatform(False, True);
  F.View.WriteSync(#27'[?25l' + 'aaa http://example.com/abcdef x');
  link := F.ThemeFg('TyTerminalLink');
  F.View.MoveTo([ssCtrl], F.View.CellCenter(8, 0));
  AssertTrue('hovering', F.View.HoverOn);
  AssertEquals('two rows', F.View.HoverNow.Range.StartY + 1, F.View.HoverNow.Range.EndY);
  b := Snap;
  try
    AssertTrue('the first row', LinkBand(Self, b, F.View, 10, 0, link) > 0);
    AssertTrue('the second row', LinkBand(Self, b, F.View, 3, 1, link) > 0);
    AssertEquals('the second row stops with the address', 0, LinkBand(Self, b, F.View, 12, 1, link));
  finally
    b.Free;
  end;
end;

{ ---- 4 期:选区 ------------------------------------------------------------------------ }

{ the theme's selection colour (with its alpha) as the row painter lays it }
function SelOver(ACtl: TTyStyleController; AFocused: Boolean): TBGRAPixel;
var
  st: TTyStyleSet;
  c: TTyColor;
begin
  if AFocused then
    st := ACtl.Model.ResolveStyle('TyTerminalSelection', '', [tysFocused])
  else
    st := ACtl.Model.ResolveStyle('TyTerminalSelection', '', []);
  if not ((tpBackground in st.Present) and (st.Background.Kind = tfkSolid)) then
    raise Exception.Create('the theme has no selection colour');
  c := st.Background.Color;
  Result := BGRA(TyRedOf(c), TyGreenOf(c), TyBlueOf(c), TyAlphaOf(c));
end;

procedure TTyTerminalViewPaintTests.TestSelectionIsPainted;
var
  b: TBGRABitmap;
  c: Integer;
  unfocused, focused: Cardinal;
begin
  F.View.WriteSync(#27'[?25l');
  unfocused := TyTermBlendOver(Bg, SelOver(F.Ctl, False));
  focused := TyTermBlendOver(Bg, SelOver(F.Ctl, True));
  AssertTrue('the two selection colours differ', unfocused <> focused);
  AssertTrue('and differ from the ground', (unfocused <> Bg) and (focused <> Bg));
  F.View.Select(2, F.View.Core.Buffer.YBase, 4);
  b := Snap;
  try
    for c := 2 to 5 do
      AssertTrue(Format('cell %d: the unfocused selection over the ground', [c]), CellIs(b, c, 0, unfocused));
    AssertTrue('cell 1: the ground', CellIs(b, 1, 0, Bg));
    AssertTrue('cell 6: the ground', CellIs(b, 6, 0, Bg));
    AssertTrue('the next row: the ground', CellIs(b, 3, 1, Bg));
  finally
    b.Free;
  end;
  F.View.Enter;
  b := Snap;
  try
    for c := 2 to 5 do
      AssertTrue(Format('cell %d: focused', [c]), CellIs(b, c, 0, focused));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestSelectedTextKeepsItsColourUnlessTheThemeSaysSo;
var
  b: TBGRABitmap;
begin
  F.View.WriteSync(#27'[?25l'#$E2#$96#$88);
  F.View.Select(0, F.View.Core.Buffer.YBase, 1);
  F.View.Enter;
  b := Snap;
  try
    AssertTrue('the block keeps the foreground (the default theme gives no selection colour for text)',
      CellIs(b, 0, 0, Fg));
  finally
    b.Free;
  end;
  F.Ctl.StyleOverride := TyTermFixtureCss + 'TyTerminalSelection:focus { color: #ff0000; }'#10;
  b := Snap;
  try
    AssertTrue('a theme that gives one: the text in it', CellIs(b, 0, 0, $FF0000));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestAColumnIsARectangle;
var
  b: TBGRABitmap;
  r, c, n: Integer;
  sel: Cardinal;
begin
  F.View.WriteSync(#27'[?25l');
  sel := TyTermBlendOver(Bg, SelOver(F.Ctl, False));
  F.View.Down(mbLeft, [ssLeft, ssAlt], F.View.CellLeft(1, 0));
  F.View.MoveTo([ssLeft, ssAlt], F.View.CellLeft(4, 1));
  F.View.Up(mbLeft, [ssAlt], F.View.CellLeft(4, 1));
  b := Snap;
  try
    n := 0;
    for r := 0 to F.View.Rows - 1 do
      for c := 0 to F.View.Cols - 1 do
        if CellIs(b, c, r, sel) then
        begin
          Inc(n);
          AssertTrue(Format('(%d, %d) inside the rectangle', [c, r]), (c >= 1) and (c <= 3) and (r <= 1));
        end;
    AssertEquals('3 x 2 cells', 6, n);
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestTheSelectionScrollsWithTheText;
var
  b: TBGRABitmap;
  i: Integer;
  s: RawByteString;
  sel: Cardinal;
begin
  s := #27'[?25l';
  for i := 1 to 30 do
    s := s + #13#10;
  F.View.WriteSync(s);
  sel := TyTermBlendOver(Bg, SelOver(F.Ctl, False));
  F.View.SelectLines(F.View.Core.Buffer.YDisp + 2, F.View.Core.Buffer.YDisp + 2);
  b := Snap;
  try
    AssertTrue('row 2 selected', CellIs(b, 10, 2, sel));
    AssertTrue('row 3 not', CellIs(b, 10, 3, Bg));
  finally
    b.Free;
  end;
  F.View.ScrollLines(-1);
  b := Snap;
  try
    AssertTrue('the line moved down: row 3 selected', CellIs(b, 10, 3, sel));
    AssertTrue('row 2 not any more', CellIs(b, 10, 2, Bg));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewPaintTests.TestOnlyTouchedRowsRepaint;
var
  b: TBGRABitmap;
  i: Integer;
begin
  F.View.WriteSync('hello');
  b := Snap;
  b.Free;
  F.View.ClearInvalidated;
  F.View.Select(2, F.View.Core.Buffer.YBase + 3, 3);
  AssertTrue('something invalidated', Length(F.View.Invalidated) > 0);
  for i := 0 to High(F.View.Invalidated) do
  begin
    AssertEquals('only row 3 (first)', 3, F.View.Invalidated[i].X);
    AssertEquals('only row 3 (last)', 3, F.View.Invalidated[i].Y);
  end;
  AssertEquals('no whole-window invalidation', 0, F.View.WholeInvalidates);
  b := Snap;
  b.Free;
  F.View.ClearInvalidated;
  F.View.Select(4, F.View.Core.Buffer.YBase + 3, 2);
  for i := 0 to High(F.View.Invalidated) do
    AssertTrue('a change within row 3: row 3 only',
      (F.View.Invalidated[i].X = 3) and (F.View.Invalidated[i].Y = 3));
end;

procedure TTyTerminalViewPaintTests.TestADisabledSelectionIsDimmed;
var
  b: TBGRABitmap;
  st: TTyStyleSet;
  a: Integer;
  pc: TTyColor;
  base, rgb: Cardinal;
  over: TBGRAPixel;
begin
  F.View.WriteSync(#27'[?25l');
  F.Ctl.StyleOverride := TyTermFixtureCss + 'TyTerminal:disabled { opacity: 0.4; }'#10;
  st := F.Ctl.Model.ResolveStyle('TyTerminal', '', [tysDisabled]);
  a := EnsureRange(Round(st.Opacity * 255), 0, 255);
  AssertTrue('the parent has a colour', TyResolveParentBg(F.View, pc));
  base := Cardinal(pc) and $FFFFFF;
  over := SelOver(F.Ctl, False);
  rgb := Mix((Cardinal(over.red) shl 16) or (Cardinal(over.green) shl 8) or over.blue, base, a);
  over := BGRA((rgb shr 16) and $FF, (rgb shr 8) and $FF, rgb and $FF, over.alpha);
  F.View.Select(2, F.View.Core.Buffer.YBase, 3);
  F.View.Enabled := False;
  b := Snap;
  try
    AssertTrue(Format('the selection dimmed over the dimmed ground (%s)',
      [IntToHex(TyTermBlendOver(Mix(Bg, base, a), over), 6)]),
      CellIs(b, 3, 0, TyTermBlendOver(Mix(Bg, base, a), over)));
  finally
    b.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalViewPaintTests);
end.
