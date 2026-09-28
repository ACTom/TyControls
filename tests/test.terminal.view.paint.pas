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
  tyControls.Types, tyControls.Terminal.Core, tyControls.Terminal.Render, tyControls.Terminal,
  test.terminal.view;

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
  end;

implementation

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
  F.View.WriteSync('a');
  b := Snap;
  b.Free;
  h0 := F.View.CellMetrics.CellH;
  misses := F.View.Cache.Misses;
  F.View.ParentFont := False;
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

procedure TTyTerminalViewPaintTests.TestWarmRedrawTime;
var
  s: RawByteString;
  row, col, k: Integer;
  b: TBGRABitmap;
  times: array[0..4] of Double;
  t0, tmp: Double;
  i, j: Integer;
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
  b := Snap;
  b.Free;
  for k := 0 to 4 do
  begin
    F.View.DrawBoldTextInBrightColors := not F.View.DrawBoldTextInBrightColors;
    t0 := TyTermDefaultClock;
    b := Snap;
    times[k] := TyTermDefaultClock - t0;
    b.Free;
  end;
  for i := 0 to 4 do
    for j := i + 1 to 4 do
      if times[j] < times[i] then begin tmp := times[i]; times[i] := times[j]; times[j] := tmp; end;
  WriteLn(Format('TTyTerminalViewPaintTests.TestWarmRedrawTime: 200 x 60 full repaint (with the blit), median %.1f ms',
    [times[2]]));
  AssertTrue('measured', times[2] >= 0);
end;

initialization
  RegisterTest(TTyTerminalViewPaintTests);
end.
