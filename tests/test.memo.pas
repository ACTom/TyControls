unit test.memo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Memo;
type
  { Probe subclass: exposes protected helpers/fields for headless geometry tests }
  TTyMemoProbe = class(TTyMemo)
  public
    function ProbeLineHeight(APPI: Integer): Integer;
    function ProbeLineCountLogical: Integer;
    function ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
    function ProbeColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
    function ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
    function ProbeCaretLine: Integer;
    function ProbeCaretCol: Integer;
    procedure ProbeSetCaret(ALine, ACol: Integer);
    procedure ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure ProbeSetForceFocused(AValue: Boolean);
  end;

  TTyMemoTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoProbe;
    procedure SetUpWithPadding(APaddingLeft: Integer);
    procedure SetUpWithCss(const ACss: string);
    // True if any pixel in horizontal band [x0..x1] at row Y is "light" (all
    // channels above AThresh) — i.e. text/caret drew over the dark background.
    function BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
  protected
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestEmptyLinesIsOneLogicalLine;
    procedure TestSetLinesClampsCaret;
    procedure TestLineHeightPositiveAndStable;
    procedure TestColPixelMonotonic;
    procedure TestColIndexRoundTrip;
    procedure TestCJKColMapping;
    procedure TestRendersAllVisibleLinesText;
    procedure TestCaretDrawnWhenFocused;
    procedure TestSecondLineYOffset;
  end;

implementation

{ TTyMemoProbe }

function TTyMemoProbe.ProbeLineHeight(APPI: Integer): Integer;
begin
  Result := LineHeight(APPI);
end;

function TTyMemoProbe.ProbeLineCountLogical: Integer;
begin
  Result := LineCountLogical;
end;

function TTyMemoProbe.ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
begin
  Result := ColPixelXAt(ALine, ACol, APPI);
end;

function TTyMemoProbe.ProbeColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
begin
  Result := ColIndexAtX(ALine, AX, APPI);
end;

function TTyMemoProbe.ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
begin
  Result := MeasureLineWidths(ALine, APPI);
end;

function TTyMemoProbe.ProbeCaretLine: Integer;
begin
  Result := CaretLine;
end;

function TTyMemoProbe.ProbeCaretCol: Integer;
begin
  Result := CaretCol;
end;

procedure TTyMemoProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

procedure TTyMemoProbe.ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyMemoProbe.ProbeSetForceFocused(AValue: Boolean);
begin
  SetForceFocused(AValue);
end;

{ TTyMemoTest }

procedure TTyMemoTest.SetUpWithPadding(APaddingLeft: Integer);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(Format(
    'TyMemo { background:#FFFFFF; color:#000000; padding:%dpx; font-size:14px; }',
    [APaddingLeft]));
  FMemo := TTyMemoProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, 200, 120);
end;

procedure TTyMemoTest.SetUpWithCss(const ACss: string);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FMemo := TTyMemoProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, 200, 120);
end;

function TTyMemoTest.BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
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

procedure TTyMemoTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

procedure TTyMemoTest.TestTypeKey;
begin
  SetUpWithPadding(0);
  AssertEquals('TyMemo', (FMemo as ITyStyleable).GetStyleTypeKey);
end;

procedure TTyMemoTest.TestEmptyLinesIsOneLogicalLine;
begin
  SetUpWithPadding(0);
  AssertEquals('fresh memo has 1 logical line', 1, FMemo.ProbeLineCountLogical);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 0', 0, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestSetLinesClampsCaret;
var
  L: TStringList;
begin
  SetUpWithPadding(0);
  // Start with 3 lines
  L := TStringList.Create;
  try
    L.Add('line one');
    L.Add('line two');
    L.Add('line three');
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  // Move caret to (2,5) — valid in the 3-line model
  FMemo.ProbeSetCaret(2, 5);
  AssertEquals('caret line is 2', 2, FMemo.ProbeCaretLine);

  // Now assign a 2-line list; caret (2,5) is no longer valid and must clamp
  L := TStringList.Create;
  try
    L.Add('alpha');
    L.Add('be');
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  AssertEquals('logical line count is 2 after reassign', 2, FMemo.ProbeLineCountLogical);
  AssertTrue('caret line clamped into [0,1]',
    (FMemo.ProbeCaretLine >= 0) and (FMemo.ProbeCaretLine <= 1));
  AssertTrue('caret col clamped to its line length',
    FMemo.ProbeCaretCol <= UTF8Length(FMemo.Lines[FMemo.ProbeCaretLine]));
end;

procedure TTyMemoTest.TestLineHeightPositiveAndStable;
var
  H1, H2: Integer;
begin
  SetUpWithPadding(0);
  H1 := FMemo.ProbeLineHeight(96);
  H2 := FMemo.ProbeLineHeight(96);
  AssertTrue('LineHeight(96) > 0', H1 > 0);
  AssertEquals('LineHeight stable across calls', H1, H2);
end;

procedure TTyMemoTest.TestColPixelMonotonic;
var
  x0, x1, x2, x3: Integer;
  ExpectedLeft: Integer;
begin
  SetUpWithPadding(6);
  x0 := FMemo.ProbeColPixelXAt('abc', 0, 96);
  x1 := FMemo.ProbeColPixelXAt('abc', 1, 96);
  x2 := FMemo.ProbeColPixelXAt('abc', 2, 96);
  x3 := FMemo.ProbeColPixelXAt('abc', 3, 96);
  // Padding.Left = 6px scaled at PPI 96 = 6
  ExpectedLeft := MulDiv(6, 96, 96);
  AssertEquals('ColPixelXAt(line,0) = Padding.Left scaled', ExpectedLeft, x0);
  AssertTrue('x1 > x0', x1 > x0);
  AssertTrue('x2 > x1', x2 > x1);
  AssertTrue('x3 > x2', x3 > x2);
end;

procedure TTyMemoTest.TestColIndexRoundTrip;
const
  Line = 'Hello World';
var
  k, px, got: Integer;
begin
  SetUpWithPadding(4);
  for k := 0 to UTF8Length(Line) do
  begin
    px := FMemo.ProbeColPixelXAt(Line, k, 96);
    got := FMemo.ProbeColIndexAtX(Line, px, 96);
    AssertEquals('round-trip col ' + IntToStr(k), k, got);
  end;
end;

procedure TTyMemoTest.TestCJKColMapping;
const
  Line = 'a中b';  // 3 codepoints, 5 bytes
var
  W: TTyIntArray;
  px1, px2, idx: Integer;
begin
  SetUpWithPadding(0);
  W := FMemo.ProbeMeasureLineWidths(Line, 96);
  AssertEquals('MeasureLineWidths length = codepoints+1', 4, Length(W));
  // Indices map at codepoint granularity, not byte granularity.
  // Boundary after codepoint 1 ('a') should round-trip to index 1.
  px1 := FMemo.ProbeColPixelXAt(Line, 1, 96);
  idx := FMemo.ProbeColIndexAtX(Line, px1, 96);
  AssertEquals('codepoint boundary 1 maps to col 1', 1, idx);
  // Boundary after codepoint 2 ('中') -> col 2
  px2 := FMemo.ProbeColPixelXAt(Line, 2, 96);
  idx := FMemo.ProbeColIndexAtX(Line, px2, 96);
  AssertEquals('codepoint boundary 2 maps to col 2', 2, idx);
end;

{ TestRendersAllVisibleLinesText
  Two short lines on a dark background; assert a light pixel exists in the y band
  of line 0 AND of line 1 — i.e. both lines actually drew their text. }
procedure TTyMemoTest.TestRendersAllVisibleLinesText;
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  LH, Y0, Y1: Integer;
  L: TStringList;
begin
  SetUpWithCss('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; }');
  L := TStringList.Create;
  try
    L.Add('AAA');
    L.Add('BBB');
    FMemo.Lines := L;
  finally
    L.Free;
  end;

  LH := FMemo.ProbeLineHeight(96);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 200, 120);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, 200, 120), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Padding default 0 -> ContentTop = 0; sample mid-cell of each line band.
      Y0 := LH div 2;            // line 0 band
      Y1 := LH + (LH div 2);     // line 1 band
      AssertTrue('line 0 drew light text in its y band',
        BandHasLightPixel(Reread, Y0, 0, 60, 120));
      AssertTrue('line 1 drew light text in its y band',
        BandHasLightPixel(Reread, Y1, 0, 60, 120));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ TestCaretDrawnWhenFocused
  Force the focused state via probe and assert a light vertical caret run at the
  caret column's X within the caret line's y band. Geometry of ColPixelXAt(line,0)
  must equal scaled left padding. }
procedure TTyMemoTest.TestCaretDrawnWhenFocused;
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  LH, CaretX, BandTop, y: Integer;
  LitRun: Integer;
  Px: TBGRAPixel;
  L: TStringList;
begin
  SetUpWithCss('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:4px; }');
  L := TStringList.Create;
  try
    L.Add('Hi');
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ProbeSetCaret(0, 0);

  // Geometry: caret at col 0 sits at scaled left padding (4px @96 = 4).
  AssertEquals('ColPixelXAt(line,0) = scaled left padding',
    MulDiv(4, 96, 96), FMemo.ProbeColPixelXAt('Hi', 0, 96));

  CaretX := FMemo.ProbeColPixelXAt('Hi', 0, 96);
  LH := FMemo.ProbeLineHeight(96);
  FMemo.ProbeSetForceFocused(True);

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 200, 120);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, 200, 120), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Count light pixels in the caret X column within line 0's band (content
      // top = padding.top scaled = 4). A 1px caret bar spans most of the cell.
      BandTop := MulDiv(4, 96, 96);
      LitRun := 0;
      for y := BandTop to BandTop + LH - 1 do
      begin
        if (y < 0) or (y >= Reread.Height) then Continue;
        Px := Reread.GetPixel(CaretX, y);
        if (Px.red > 120) and (Px.green > 120) and (Px.blue > 120) then
          Inc(LitRun);
      end;
      AssertTrue(Format('caret bar lit vertical run >= LH/2 (run=%d, LH=%d)',
        [LitRun, LH]), LitRun >= LH div 2);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ TestSecondLineYOffset
  In line 1's left-column region, no light pixel should appear above ContentTop+LH
  (line 0 text is 'BBB' in col >0; we probe the empty column to the right of line 0's
  text where line 0 is blank but line 1 has its glyph). We assert line 1 text only
  begins at/after ContentTop+LH by checking the row just above the line-1 band in a
  column where line 1 draws but line 0 does not. }
procedure TTyMemoTest.TestSecondLineYOffset;
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  LH, probeY, x: Integer;
  L: TStringList;
  AnyLightAboveSecond: Boolean;
  Px: TBGRAPixel;
begin
  SetUpWithCss('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; }');
  L := TStringList.Create;
  try
    L.Add('');     // line 0 is empty -> draws no glyphs
    L.Add('BBB');  // line 1 has text
    FMemo.Lines := L;
  finally
    L.Free;
  end;

  LH := FMemo.ProbeLineHeight(96);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 200, 120);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, 200, 120), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Within line 0's band (y in [0, LH-1]) there must be NO light pixel in the
      // left text region — line 0 is empty, line 1 must not bleed upward.
      AnyLightAboveSecond := False;
      for probeY := 0 to LH - 1 do
        for x := 0 to 60 do
        begin
          Px := Reread.GetPixel(x, probeY);
          if (Px.red > 120) and (Px.green > 120) and (Px.blue > 120) then
            AnyLightAboveSecond := True;
        end;
      AssertFalse('no light pixel in line-0 band (empty line; line 1 starts at ContentTop+LH)',
        AnyLightAboveSecond);
      // Sanity: line 1 DID draw in its own band.
      AssertTrue('line 1 drew in its band at/after ContentTop+LH',
        BandHasLightPixel(Reread, LH + (LH div 2), 0, 60, 120));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

initialization
  RegisterTest(TTyMemoTest);
end.
