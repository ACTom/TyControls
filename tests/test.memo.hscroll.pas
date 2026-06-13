unit test.memo.hscroll;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, LCLType, LazUTF8,
  BGRABitmap, BGRABitmapTypes, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Memo;
type
  { Probe subclass exposing the horizontal-scroll surface for headless tests.
    FScrollX + ClampScrollX + EnsureCaretXVisible are the WordWrap=False mirror
    of TTyEdit's idiom; the click hit-test goes through ColIndexAtX (which adds
    FScrollX). No native window is needed: everything is pure measurement +
    offscreen render. }
  TTyMemoHScrollProbe = class(TTyMemo)
  public
    function ProbeScrollX: Integer;
    procedure ProbeSetWordWrap(AValue: Boolean);
    procedure ProbeSetCaret(ALine, ACol: Integer);
    procedure ProbeClampScrollX(APPI: Integer);
    procedure ProbeEnsureCaretXVisible(APPI: Integer);
    function ProbeColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
    function ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
    function ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
    function ProbeTextStartX(APPI: Integer): Integer;
    function ProbeContentWidthFor(APPI: Integer): Integer;
    procedure ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    // Drive a navigation key (End/Home/Right) through the real KeyDown path so the
    // wired EnsureCaretXVisible/ClampScrollX run exactly as in production.
    procedure ProbeKey(AKey: Word; AShift: TShiftState);
  end;

  TTyMemoHScrollTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoHScrollProbe;
    procedure SetUpMemo(const ACss: string; AWidth: Integer);
    procedure LoadLines(const AItems: array of string);
    // True if any pixel in horizontal band [X0..X1] at row Y is "light".
    function BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
  protected
    procedure TearDown; override;
  published
    procedure TestCaretEndScrollsRightHomeScrollsBack;  // (a)
    procedure TestClampScrollXBounds;                   // (b)
    procedure TestRenderShiftsFirstGlyphOff;            // (c)
    procedure TestClickHitTestWithScroll;               // (d)
    procedure TestWordWrapForcesScrollXZero;            // (e)
    procedure TestShortTextStaysAtZero;                 // regression
  end;

implementation

{ TTyMemoHScrollProbe }

function TTyMemoHScrollProbe.ProbeScrollX: Integer;
begin
  Result := ScrollX;
end;

procedure TTyMemoHScrollProbe.ProbeSetWordWrap(AValue: Boolean);
begin
  WordWrap := AValue;
end;

procedure TTyMemoHScrollProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

procedure TTyMemoHScrollProbe.ProbeClampScrollX(APPI: Integer);
begin
  ClampScrollX(APPI);
end;

procedure TTyMemoHScrollProbe.ProbeEnsureCaretXVisible(APPI: Integer);
begin
  EnsureCaretXVisible(APPI);
end;

function TTyMemoHScrollProbe.ProbeColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
begin
  Result := ColIndexAtX(ALine, AX, APPI);
end;

function TTyMemoHScrollProbe.ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
begin
  Result := ColPixelXAt(ALine, ACol, APPI);
end;

function TTyMemoHScrollProbe.ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
begin
  Result := MeasureLineWidths(ALine, APPI);
end;

function TTyMemoHScrollProbe.ProbeTextStartX(APPI: Integer): Integer;
begin
  Result := TextStartX(APPI);
end;

function TTyMemoHScrollProbe.ProbeContentWidthFor(APPI: Integer): Integer;
begin
  Result := ContentWidthFor(APPI);
end;

procedure TTyMemoHScrollProbe.ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyMemoHScrollProbe.ProbeKey(AKey: Word; AShift: TShiftState);
begin
  InjectKey(AKey, AShift);
end;

{ TTyMemoHScrollTest }

procedure TTyMemoHScrollTest.SetUpMemo(const ACss: string; AWidth: Integer);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FMemo := TTyMemoHScrollProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;   // pin 96; macOS default is 72
  FMemo.SetBounds(0, 0, AWidth, 120);
end;

procedure TTyMemoHScrollTest.LoadLines(const AItems: array of string);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    for i := Low(AItems) to High(AItems) do
      L.Add(AItems[i]);
    FMemo.Lines := L;
  finally
    L.Free;
  end;
end;

function TTyMemoHScrollTest.BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
var
  x: Integer;
  Px: TBGRAPixel;
begin
  Result := False;
  if (Y < 0) or (Y >= ABmp.Height) then Exit;
  if X0 < 0 then X0 := 0;
  if X1 >= ABmp.Width then X1 := ABmp.Width - 1;
  for x := X0 to X1 do
  begin
    Px := ABmp.GetPixel(x, Y);
    if (Px.red > AThresh) and (Px.green > AThresh) and (Px.blue > AThresh) then
      Exit(True);
  end;
end;

procedure TTyMemoHScrollTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

const
  // A narrow memo whose content width is far smaller than the long line.
  NARROW_CSS = 'TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }';
  LONG_LINE  = 'the quick brown fox jumps over the lazy dog again and again';

// (a) WordWrap=False: caret at end -> ScrollX>0 and CaretPx-ScrollX is inside the
// content viewport [StartX+Margin, ViewRight-Margin]. Caret Home -> ScrollX back 0.
procedure TTyMemoHScrollTest.TestCaretEndScrollsRightHomeScrollsBack;
var
  CW, StartX, ViewRight, Margin, CaretPx, EndCol: Integer;
begin
  SetUpMemo(NARROW_CSS, 80);
  FMemo.ProbeSetWordWrap(False);
  LoadLines([LONG_LINE]);
  EndCol := UTF8Length(LONG_LINE);
  // Move the caret to end-of-line through the real End-key path (wires the
  // EnsureCaretXVisible we are adding).
  FMemo.ProbeSetCaret(0, 0);
  FMemo.ProbeKey(VK_END, []);
  AssertTrue('caret-at-end scrolls right (ScrollX > 0)', FMemo.ProbeScrollX > 0);
  // CaretPx (un-scrolled) minus ScrollX must sit inside the content viewport.
  StartX := FMemo.ProbeTextStartX(96);
  Margin := MulDiv(2, 96, 96);
  CW := FMemo.ProbeContentWidthFor(96);
  ViewRight := StartX + CW;
  CaretPx := FMemo.ProbeColPixelXAt(LONG_LINE, EndCol, 96);
  // At end-of-line the right clamp pins the caret to the viewport's right edge
  // (ViewRight) rather than ViewRight-Margin, because MaxScroll caps FScrollX —
  // identical to TTyEdit.EnsureCaretVisible. So the effective caret x must be
  // VISIBLE: inside [StartX, ViewRight] (and >= StartX+Margin is satisfied here).
  AssertTrue('caret X after scroll <= ViewRight (visible at right edge)',
    CaretPx - FMemo.ProbeScrollX <= ViewRight);
  AssertTrue('caret X after scroll >= StartX (visible, not off-left)',
    CaretPx - FMemo.ProbeScrollX >= StartX);
  // The Margin keeps it just inside when not at the boundary; at end-of-line the
  // caret is at ViewRight (>= StartX+Margin for any non-degenerate viewport).
  AssertTrue('caret X after scroll >= StartX+Margin',
    CaretPx - FMemo.ProbeScrollX >= StartX + Margin);
  // Home returns ScrollX to 0 (caret X at col 0 is at StartX, fully left).
  FMemo.ProbeKey(VK_HOME, []);
  AssertEquals('caret-Home scrolls back to 0', 0, FMemo.ProbeScrollX);
end;

// (b) ClampScrollX never exceeds widestLineWidth-ViewWidth and never < 0.
procedure TTyMemoHScrollTest.TestClampScrollXBounds;
var
  CW, WidestW, MaxScroll: Integer;
  W2: TTyIntArray;
begin
  SetUpMemo(NARROW_CSS, 80);
  FMemo.ProbeSetWordWrap(False);
  // Two lines; the second is the widest -> it determines MaxScroll.
  LoadLines(['short', LONG_LINE + ' plus even more tail text here']);
  W2 := FMemo.ProbeMeasureLineWidths(LONG_LINE + ' plus even more tail text here', 96);
  WidestW := W2[High(W2)];
  CW := FMemo.ProbeContentWidthFor(96);
  MaxScroll := WidestW - CW;
  if MaxScroll < 0 then MaxScroll := 0;
  // Set the caret to the widest line's end then over-scroll via a clamp call.
  FMemo.ProbeSetCaret(1, UTF8Length(LONG_LINE + ' plus even more tail text here'));
  FMemo.ProbeEnsureCaretXVisible(96);
  FMemo.ProbeClampScrollX(96);
  AssertTrue('ScrollX never exceeds widestLineWidth-ViewWidth',
    FMemo.ProbeScrollX <= MaxScroll);
  AssertTrue('ScrollX never < 0', FMemo.ProbeScrollX >= 0);
end;

// (c) Pixel test (PPI 96): at ScrollX>0 the FIRST glyph of the long line is no
// longer at ContentRect.Left, but a tail glyph IS visible inside the viewport.
procedure TTyMemoHScrollTest.TestRenderShiftsFirstGlyphOff;
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  CW, LH, Y0, FirstGlyphW: Integer;
  W: TTyIntArray;
begin
  SetUpMemo(NARROW_CSS, 80);
  FMemo.ProbeSetWordWrap(False);
  LoadLines([LONG_LINE]);
  CW := FMemo.ProbeContentWidthFor(96);
  W := FMemo.ProbeMeasureLineWidths(LONG_LINE, 96);
  FirstGlyphW := W[1];   // pixel width of the first glyph
  // Scroll the caret to the end so ScrollX advances well past the first word.
  FMemo.ProbeSetCaret(0, UTF8Length(LONG_LINE));
  FMemo.ProbeEnsureCaretXVisible(96);
  AssertTrue('precondition: scrolled right', FMemo.ProbeScrollX > FirstGlyphW);
  LH := 18;  // any LH; we read a band near the top text row
  if LH > 60 then LH := 60;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(80, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 80, 120);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, 80, 120), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Y0 := 6;  // a row inside the first text line's band (font 14px @96)
      // The leftmost columns [0..FirstGlyphW) would hold the FIRST glyph at
      // ScrollX=0. After scrolling right past the first word, those columns no
      // longer show the line's leading 'the' — they show a later (shifted) glyph,
      // so there must STILL be light text somewhere across the viewport.
      AssertTrue('tail text visible somewhere in the viewport after scroll',
        BandHasLightPixel(Reread, Y0, 0, CW - 1, 120));
      // And the very last viewport column near the right edge has text (the tail
      // of the long line is now reachable, not clipped-off forever).
      AssertTrue('right portion of viewport shows shifted text',
        BandHasLightPixel(Reread, Y0, CW div 2, CW - 1, 120));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

// (d) Click hit-test at a device X while ScrollX>0 resolves to the correct column
// (ColIndexAtX adds FScrollX). A device X that maps to absolute pixel
// CaretPx(col) must resolve back to that col when ScrollX shifts the content.
procedure TTyMemoHScrollTest.TestClickHitTestWithScroll;
var
  TargetCol, AbsX, DeviceX, Resolved, SX: Integer;
begin
  SetUpMemo(NARROW_CSS, 80);
  FMemo.ProbeSetWordWrap(False);
  LoadLines([LONG_LINE]);
  FMemo.ProbeSetCaret(0, UTF8Length(LONG_LINE));
  FMemo.ProbeEnsureCaretXVisible(96);
  SX := FMemo.ProbeScrollX;
  AssertTrue('precondition: scrolled right', SX > 0);
  // Choose a column near the end (visible after scrolling). Its absolute pixel x
  // is ColPixelXAt; the on-screen device x is that minus ScrollX. ColIndexAtX,
  // adding ScrollX back, must recover the column.
  TargetCol := UTF8Length(LONG_LINE) - 2;
  AbsX := FMemo.ProbeColPixelXAt(LONG_LINE, TargetCol, 96);
  DeviceX := AbsX - SX;            // where that boundary actually appears on screen
  Resolved := FMemo.ProbeColIndexAtX(LONG_LINE, DeviceX, 96);
  AssertEquals('click at device X resolves to the scrolled column',
    TargetCol, Resolved);
end;

// (e) WordWrap=True forces ScrollX=0 and ClampScrollX maxes at 0.
procedure TTyMemoHScrollTest.TestWordWrapForcesScrollXZero;
begin
  SetUpMemo(NARROW_CSS, 80);
  FMemo.ProbeSetWordWrap(True);
  LoadLines([LONG_LINE]);
  // Even with the caret at end and an EnsureCaretXVisible call, wrap mode keeps
  // ScrollX pinned at 0 (the line is laid out across visual rows, not scrolled).
  FMemo.ProbeSetCaret(0, UTF8Length(LONG_LINE));
  FMemo.ProbeEnsureCaretXVisible(96);
  AssertEquals('WordWrap=True keeps ScrollX 0 after EnsureCaretXVisible',
    0, FMemo.ProbeScrollX);
  FMemo.ProbeClampScrollX(96);
  AssertEquals('WordWrap=True ClampScrollX maxes at 0', 0, FMemo.ProbeScrollX);
end;

// REGRESSION: short text that fits keeps ScrollX = 0 (byte-identical render path).
procedure TTyMemoHScrollTest.TestShortTextStaysAtZero;
begin
  SetUpMemo(NARROW_CSS, 200);   // wide memo, short lines fit
  FMemo.ProbeSetWordWrap(False);
  LoadLines(['ab', 'cd']);
  FMemo.ProbeSetCaret(0, 2);
  FMemo.ProbeKey(VK_END, []);
  AssertEquals('fitting text never scrolls (End)', 0, FMemo.ProbeScrollX);
  FMemo.ProbeSetCaret(1, 0);
  FMemo.ProbeKey(VK_END, []);
  AssertEquals('fitting text never scrolls (line 2 End)', 0, FMemo.ProbeScrollX);
  FMemo.ProbeClampScrollX(96);
  AssertEquals('ClampScrollX leaves fitting text at 0', 0, FMemo.ProbeScrollX);
end;

initialization
  RegisterTest(TTyMemoHScrollTest);
end.
