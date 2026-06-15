unit test.memo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ScrollBar,
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
    // Drives the protected KeyDown so tests can inspect whether Key was consumed
    // (set to 0) or left intact (e.g. when disabled it must pass through).
    procedure ProbeKeyDown(var AKey: Word; AShift: TShiftState);
    // --- T4 vertical scroll accessors ---
    function ProbeVisibleRows: Integer;
    function ProbeMaxTopLine: Integer;
    function ProbeTopLine: Integer;
    procedure ProbeSetTopLine(AValue: Integer);
    procedure ProbeUpdateScrollBar;
    procedure ProbeEnsureCaretLineVisible(APPI: Integer);
    function ProbeScrollBar: TTyScrollBar;
    function ProbeDoMouseWheel(AWheelDelta: Integer): Boolean;
    procedure ProbeScrollBarChange;
    // --- T5 mouse caret hit-test ---
    procedure ProbeMouseDown(X, Y: Integer);
  end;

  { Clipboard-access subclass: routes the virtual clipboard hooks to an in-memory
    string so the headless ReadOnly tests never touch the real OS clipboard
    (mirrors TTyMemoClipboardProbe in test.memo.selection). }
  TTyMemoClipAccess = class(TTyMemo)
  private
    FClipText: string;
  protected
    function ReadClipboardText: string; override;
    procedure WriteClipboardText(const S: string); override;
  public
    property ClipText: string read FClipText write FClipText;
  end;

  TTyMemoCursorTest = class(TTestCase)
  published
    procedure TestMemoUsesIBeam;
  end;

  TTyMemoTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoProbe;
    FChangeCount: Integer;
    procedure SetUpWithPadding(APaddingLeft: Integer);
    procedure SetUpWithCss(const ACss: string);
    // Resolve a theme file path relative to the test executable (in /tests),
    // independent of the current working directory.
    function ThemePath(const AName: string): string;
    procedure OnMemoChange(Sender: TObject);
    // Load FMemo with the given lines (replaces existing content).
    procedure LoadLines(const AItems: array of string);
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
    // --- T3 keyboard editing ---
    procedure TestInsertPrintable;
    procedure TestEnterSplits;
    procedure TestBackspaceMergesLines;
    procedure TestBackspaceNoopAtOrigin;
    procedure TestDeleteMergesNextLine;
    procedure TestLeftWrapsToPrevLineEnd;
    procedure TestRightWrapsToNextLineStart;
    procedure TestUpDownDesiredColumn;
    procedure TestHomeEnd;
    procedure TestCtrlHomeEnd;
    procedure TestCJKBackspace;
    procedure TestDisabledIgnoresKeys;
    procedure TestOnChangeFiresOnEdit;
    // --- T4 vertical scroll ---
    procedure TestVisibleRowsFromHeight;
    procedure TestScrollBarAppearsWhenOverflow;
    procedure TestScrollBarHiddenWhenFits;
    procedure TestWheelScrollsThreeLines;
    procedure TestSetTopLineClamps;
    procedure TestEnsureCaretLineVisibleScrollsDown;
    procedure TestScrollSyncNoPingPong;
    // --- T5 mouse caret hit-test ---
    procedure TestClickSelectsLineByY;
    procedure TestClickColumnByX;
    procedure TestClickWithScroll;
    procedure TestClickPastLastLineClamps;
    procedure TestDisabledMouseIgnored;
    // --- T6 theme integration smoke ---
    procedure TestThemedMemoResolvesStyle;
    // --- Task 5: ReadOnly ---
    procedure TestMemoReadOnlyBlocksEditsAllowsNav;
    procedure TestMemoReadOnlyCutActsAsCopy;
    // T6 MaxLength: content-codepoint cap on typing + paste truncation.
    procedure TestMemoMaxLengthCapsTyping;
    procedure TestMemoMaxLengthTruncatesPaste;
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

procedure TTyMemoProbe.ProbeKeyDown(var AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

function TTyMemoProbe.ProbeVisibleRows: Integer;
begin
  Result := VisibleRows;
end;

function TTyMemoProbe.ProbeMaxTopLine: Integer;
begin
  Result := MaxTopLine;
end;

function TTyMemoProbe.ProbeTopLine: Integer;
begin
  Result := TopLine;
end;

procedure TTyMemoProbe.ProbeSetTopLine(AValue: Integer);
begin
  SetTopLine(AValue);
end;

procedure TTyMemoProbe.ProbeUpdateScrollBar;
begin
  UpdateScrollBar;
end;

procedure TTyMemoProbe.ProbeEnsureCaretLineVisible(APPI: Integer);
begin
  EnsureCaretLineVisible(APPI);
end;

function TTyMemoProbe.ProbeScrollBar: TTyScrollBar;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyScrollBar then
    begin
      Result := TTyScrollBar(Controls[i]);
      Exit;
    end;
end;

function TTyMemoProbe.ProbeDoMouseWheel(AWheelDelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], AWheelDelta, Point(0, 0));
end;

procedure TTyMemoProbe.ProbeScrollBarChange;
var
  SB: TTyScrollBar;
begin
  // Re-fire the scrollbar's OnChange (= TTyMemo.ScrollBarChange) without changing
  // the scrollbar position, to exercise the reentrancy guard path directly.
  SB := ProbeScrollBar;
  if (SB <> nil) and Assigned(SB.OnChange) then
    SB.OnChange(SB);
end;

procedure TTyMemoProbe.ProbeMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

{ TTyMemoClipAccess }

function TTyMemoClipAccess.ReadClipboardText: string;
begin
  Result := FClipText;
end;

procedure TTyMemoClipAccess.WriteClipboardText(const S: string);
begin
  FClipText := S;
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

function TTyMemoTest.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim
    + 'themes' + PathDelim + AName;
end;

procedure TTyMemoTest.OnMemoChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

procedure TTyMemoTest.LoadLines(const AItems: array of string);
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

{ --- T3 keyboard editing tests --- }

procedure TTyMemoTest.TestInsertPrintable;
begin
  SetUpWithPadding(0);
  FMemo.ProbeSetCaret(0, 0);
  FMemo.InjectChar('a');
  AssertEquals('Lines[0] = a', 'a', FMemo.Lines[0]);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 1', 1, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestEnterSplits;
begin
  SetUpWithPadding(0);
  LoadLines(['abcd']);
  FMemo.ProbeSetCaret(0, 2);
  FMemo.InjectKey(VK_RETURN, []);
  AssertEquals('LineCount = 2', 2, FMemo.ProbeLineCountLogical);
  AssertEquals('Lines[0] = ab', 'ab', FMemo.Lines[0]);
  AssertEquals('Lines[1] = cd', 'cd', FMemo.Lines[1]);
  AssertEquals('caret line 1', 1, FMemo.ProbeCaretLine);
  AssertEquals('caret col 0', 0, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestBackspaceMergesLines;
begin
  SetUpWithPadding(0);
  LoadLines(['ab', 'cd']);
  FMemo.ProbeSetCaret(1, 0);
  FMemo.InjectBackspace;
  AssertEquals('LineCount = 1', 1, FMemo.ProbeLineCountLogical);
  AssertEquals('Lines[0] = abcd', 'abcd', FMemo.Lines[0]);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 2', 2, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestBackspaceNoopAtOrigin;
begin
  SetUpWithPadding(0);
  LoadLines(['abc']);
  FMemo.ProbeSetCaret(0, 0);
  FChangeCount := 0;
  FMemo.OnChange := @OnMemoChange;
  FMemo.InjectBackspace;
  AssertEquals('Lines[0] unchanged', 'abc', FMemo.Lines[0]);
  AssertEquals('LineCount unchanged', 1, FMemo.ProbeLineCountLogical);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 0', 0, FMemo.ProbeCaretCol);
  AssertEquals('OnChange NOT fired', 0, FChangeCount);
end;

procedure TTyMemoTest.TestDeleteMergesNextLine;
begin
  SetUpWithPadding(0);
  LoadLines(['ab', 'cd']);
  FMemo.ProbeSetCaret(0, 2);
  FMemo.InjectDelete;
  AssertEquals('LineCount = 1', 1, FMemo.ProbeLineCountLogical);
  AssertEquals('Lines[0] = abcd', 'abcd', FMemo.Lines[0]);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 2', 2, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestLeftWrapsToPrevLineEnd;
begin
  SetUpWithPadding(0);
  LoadLines(['ab', 'cd']);
  FMemo.ProbeSetCaret(1, 0);
  FMemo.InjectKey(VK_LEFT, []);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 2 (end of ab)', 2, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestRightWrapsToNextLineStart;
begin
  SetUpWithPadding(0);
  LoadLines(['ab', 'cd']);
  FMemo.ProbeSetCaret(0, 2);  // end of 'ab'
  FMemo.InjectKey(VK_RIGHT, []);
  AssertEquals('caret line 1', 1, FMemo.ProbeCaretLine);
  AssertEquals('caret col 0', 0, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestUpDownDesiredColumn;
begin
  SetUpWithPadding(0);
  LoadLines(['abcde', 'xy', 'zzzzz']);
  FMemo.ProbeSetCaret(0, 4);
  FMemo.InjectKey(VK_DOWN, []);
  AssertEquals('down1 line 1', 1, FMemo.ProbeCaretLine);
  AssertEquals('down1 col clamped to len(xy)=2', 2, FMemo.ProbeCaretCol);
  FMemo.InjectKey(VK_DOWN, []);
  AssertEquals('down2 line 2', 2, FMemo.ProbeCaretLine);
  AssertEquals('down2 col desired restored to 4', 4, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestHomeEnd;
begin
  SetUpWithPadding(0);
  LoadLines(['hello world']);
  FMemo.ProbeSetCaret(0, 5);
  FMemo.InjectKey(VK_HOME, []);
  AssertEquals('home -> col 0', 0, FMemo.ProbeCaretCol);
  FMemo.InjectKey(VK_END, []);
  AssertEquals('end -> col len', UTF8Length('hello world'), FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestCtrlHomeEnd;
begin
  SetUpWithPadding(0);
  LoadLines(['alpha', 'beta', 'gamma']);
  FMemo.ProbeSetCaret(1, 2);
  FMemo.InjectKey(VK_HOME, [ssCtrl]);
  AssertEquals('ctrl+home line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('ctrl+home col 0', 0, FMemo.ProbeCaretCol);
  FMemo.InjectKey(VK_END, [ssCtrl]);
  AssertEquals('ctrl+end last line', 2, FMemo.ProbeCaretLine);
  AssertEquals('ctrl+end last col', UTF8Length('gamma'), FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestCJKBackspace;
begin
  SetUpWithPadding(0);
  LoadLines(['a中b']);
  FMemo.ProbeSetCaret(0, 2);  // after '中'
  FMemo.InjectBackspace;
  AssertEquals('whole CJK codepoint removed', 'ab', FMemo.Lines[0]);
  AssertEquals('caret col 1', 1, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestDisabledIgnoresKeys;
var
  K: Word;
begin
  SetUpWithPadding(0);
  LoadLines(['abcd']);
  FMemo.ProbeSetCaret(0, 2);
  FMemo.Enabled := False;
  FChangeCount := 0;
  FMemo.OnChange := @OnMemoChange;

  // Printable insert: no-op
  FMemo.InjectChar('z');
  AssertEquals('insert ignored when disabled', 'abcd', FMemo.Lines[0]);

  // VK keys must NOT be consumed (Key stays non-zero)
  K := VK_RETURN;
  FMemo.ProbeKeyDown(K, []);
  AssertEquals('VK_RETURN not consumed when disabled', VK_RETURN, K);
  K := VK_BACK;
  FMemo.ProbeKeyDown(K, []);
  AssertEquals('VK_BACK not consumed when disabled', VK_BACK, K);
  K := VK_LEFT;
  FMemo.ProbeKeyDown(K, []);
  AssertEquals('VK_LEFT not consumed when disabled', VK_LEFT, K);

  AssertEquals('model unchanged when disabled', 'abcd', FMemo.Lines[0]);
  AssertEquals('LineCount unchanged when disabled', 1, FMemo.ProbeLineCountLogical);
  AssertEquals('caret unchanged line', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret unchanged col', 2, FMemo.ProbeCaretCol);
  AssertEquals('OnChange NOT fired when disabled', 0, FChangeCount);
end;

procedure TTyMemoTest.TestOnChangeFiresOnEdit;
begin
  SetUpWithPadding(0);
  LoadLines(['abcd']);
  FMemo.ProbeSetCaret(0, 2);
  FMemo.OnChange := @OnMemoChange;

  // Edit fires OnChange
  FChangeCount := 0;
  FMemo.InjectChar('x');
  AssertEquals('OnChange fired on insert', 1, FChangeCount);

  FChangeCount := 0;
  FMemo.InjectKey(VK_RETURN, []);
  AssertEquals('OnChange fired on split', 1, FChangeCount);

  // Pure caret moves do NOT fire OnChange
  FChangeCount := 0;
  FMemo.InjectKey(VK_LEFT, []);
  FMemo.InjectKey(VK_RIGHT, []);
  FMemo.InjectKey(VK_HOME, []);
  FMemo.InjectKey(VK_END, []);
  FMemo.InjectKey(VK_UP, []);
  FMemo.InjectKey(VK_DOWN, []);
  AssertEquals('OnChange NOT fired on pure caret moves', 0, FChangeCount);
end;

{ --- T4 vertical scroll tests --- }

{ TestVisibleRowsFromHeight
  VisibleRows must be Height div LineHeight(96), floored at 1 (uses Height, not
  ClientHeight, per the headless ListBox note). }
procedure TTyMemoTest.TestVisibleRowsFromHeight;
var
  LH, ExpectedVR: Integer;
begin
  SetUpWithPadding(0);
  FMemo.SetBounds(0, 0, 200, 137);   // odd height -> floor matters
  LH := FMemo.ProbeLineHeight(96);
  ExpectedVR := 137 div LH;
  if ExpectedVR < 1 then ExpectedVR := 1;
  AssertEquals('VisibleRows = Height div LineHeight(96)',
    ExpectedVR, FMemo.ProbeVisibleRows);
end;

{ TestScrollBarAppearsWhenOverflow
  With VR+5 lines, after UpdateScrollBar the embedded scrollbar exists, is Visible,
  and Max = LineCount - VR. }
procedure TTyMemoTest.TestScrollBarAppearsWhenOverflow;
var
  VR, n, i, j: Integer;
  L: TStringList;
  SB: TTyScrollBar;
begin
  SetUpWithPadding(0);
  VR := FMemo.ProbeVisibleRows;
  n := VR + 5;
  L := TStringList.Create;
  try
    for i := 0 to n - 1 do
      L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ProbeUpdateScrollBar;
  SB := FMemo.ProbeScrollBar;
  AssertTrue('scrollbar created when content overflows', SB <> nil);
  AssertTrue('scrollbar visible when content overflows', SB.Visible);
  j := FMemo.ProbeLineCountLogical - VR;
  AssertEquals('scrollbar Max = LineCount - VR', j, SB.Max);
end;

{ TestScrollBarHiddenWhenFits
  A few lines (< VR) -> scrollbar not visible (either nil or Visible=False). }
procedure TTyMemoTest.TestScrollBarHiddenWhenFits;
var
  SB: TTyScrollBar;
begin
  SetUpWithPadding(0);
  LoadLines(['a', 'b']);
  FMemo.ProbeUpdateScrollBar;
  SB := FMemo.ProbeScrollBar;
  if SB <> nil then
    AssertFalse('scrollbar hidden when content fits', SB.Visible);
end;

{ TestWheelScrollsThreeLines
  Many lines, TopLine 0; one wheel-down step -> TopLine 3; wheel-up -> back to 0. }
procedure TTyMemoTest.TestWheelScrollsThreeLines;
var
  i: Integer;
  L: TStringList;
begin
  SetUpWithPadding(0);
  L := TStringList.Create;
  try
    for i := 0 to 49 do
      L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ProbeSetTopLine(0);
  AssertEquals('TopLine starts at 0', 0, FMemo.ProbeTopLine);
  // WheelDelta < 0 => scroll down => TopLine += 3
  FMemo.ProbeDoMouseWheel(-120);
  AssertEquals('wheel down scrolls 3 lines', 3, FMemo.ProbeTopLine);
  // WheelDelta > 0 => scroll up => TopLine -= 3
  FMemo.ProbeDoMouseWheel(120);
  AssertEquals('wheel up scrolls back to 0', 0, FMemo.ProbeTopLine);
end;

{ TestSetTopLineClamps
  SetTopLine(9999) clamps to MaxTopLine; SetTopLine(-5) clamps to 0. }
procedure TTyMemoTest.TestSetTopLineClamps;
var
  i: Integer;
  L: TStringList;
begin
  SetUpWithPadding(0);
  L := TStringList.Create;
  try
    for i := 0 to 29 do
      L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ProbeSetTopLine(9999);
  AssertEquals('SetTopLine(9999) clamps to MaxTopLine',
    FMemo.ProbeMaxTopLine, FMemo.ProbeTopLine);
  FMemo.ProbeSetTopLine(-5);
  AssertEquals('SetTopLine(-5) clamps to 0', 0, FMemo.ProbeTopLine);
end;

{ TestEnsureCaretLineVisibleScrollsDown
  Caret on the last line of a tall doc -> FTopLine adjusts so the caret line is
  within [FTopLine, FTopLine+VR). }
procedure TTyMemoTest.TestEnsureCaretLineVisibleScrollsDown;
var
  i, VR, Last: Integer;
  L: TStringList;
begin
  SetUpWithPadding(0);
  L := TStringList.Create;
  try
    for i := 0 to 49 do
      L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ProbeSetTopLine(0);
  VR := FMemo.ProbeVisibleRows;
  Last := FMemo.ProbeLineCountLogical - 1;
  FMemo.ProbeSetCaret(Last, 0);
  FMemo.ProbeEnsureCaretLineVisible(96);
  AssertTrue('caret line >= TopLine after EnsureCaretLineVisible',
    Last >= FMemo.ProbeTopLine);
  AssertTrue('caret line < TopLine + VR after EnsureCaretLineVisible',
    Last < FMemo.ProbeTopLine + VR);
end;

{ TestScrollSyncNoPingPong
  Drive ScrollBarChange and SetTopLine alternately; the FSyncingScroll guard must
  prevent infinite recursion and leave a stable value. }
procedure TTyMemoTest.TestScrollSyncNoPingPong;
var
  i: Integer;
  L: TStringList;
  Before: Integer;
begin
  SetUpWithPadding(0);
  L := TStringList.Create;
  try
    for i := 0 to 49 do
      L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ProbeUpdateScrollBar;
  // Move via SetTopLine -> syncs scrollbar position.
  FMemo.ProbeSetTopLine(5);
  AssertEquals('TopLine set to 5', 5, FMemo.ProbeTopLine);
  // Re-fire ScrollBarChange (scrollbar position already 5): must not change/recurse.
  Before := FMemo.ProbeTopLine;
  FMemo.ProbeScrollBarChange;
  AssertEquals('ScrollBarChange leaves TopLine stable (no ping-pong)',
    Before, FMemo.ProbeTopLine);
  // And another SetTopLine still works after the round-trip.
  FMemo.ProbeSetTopLine(7);
  AssertEquals('SetTopLine still functions after sync', 7, FMemo.ProbeTopLine);
end;

{ --- T5 mouse caret hit-test tests --- }

{ TestClickSelectsLineByY
  Three lines, TopLine 0; a click whose Y lands inside row 1's band selects
  caret line 1. }
procedure TTyMemoTest.TestClickSelectsLineByY;
var
  LH, Y: Integer;
begin
  SetUpWithPadding(0);
  LoadLines(['AAAA', 'BBBB', 'CCCC']);
  FMemo.ProbeSetTopLine(0);
  LH := FMemo.ProbeLineHeight(96);
  Y := LH + (LH div 2);   // mid-band of row 1
  FMemo.ProbeMouseDown(2, Y);
  AssertEquals('click in row-1 band selects caret line 1', 1, FMemo.ProbeCaretLine);
end;

{ TestClickColumnByX
  Click near a known ColPixelXAt(line, k) X selects column k (midpoint-nearest). }
procedure TTyMemoTest.TestClickColumnByX;
const
  Line = 'Hello World';
var
  k, px: Integer;
begin
  SetUpWithPadding(4);
  LoadLines([Line]);
  FMemo.ProbeSetTopLine(0);
  for k := 0 to UTF8Length(Line) do
  begin
    px := FMemo.ProbeColPixelXAt(Line, k, 96);
    FMemo.ProbeMouseDown(px, 1);  // y in row-0 band
    AssertEquals('click at ColPixelXAt(line,' + IntToStr(k) + ') -> col ' + IntToStr(k),
      k, FMemo.ProbeCaretCol);
  end;
end;

{ TestClickWithScroll
  TopLine 2; a click in the row-0 band selects the logical line at TopLine (=2). }
procedure TTyMemoTest.TestClickWithScroll;
var
  i: Integer;
  L: TStringList;
begin
  SetUpWithPadding(0);
  L := TStringList.Create;
  try
    for i := 0 to 49 do
      L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ProbeSetTopLine(2);
  FMemo.ProbeMouseDown(2, 1);  // row-0 band
  AssertEquals('click row-0 band with TopLine=2 selects line 2', 2, FMemo.ProbeCaretLine);
end;

{ TestClickPastLastLineClamps
  Click far below the content -> caret clamps onto the last logical line. }
procedure TTyMemoTest.TestClickPastLastLineClamps;
begin
  SetUpWithPadding(0);
  LoadLines(['AAAA', 'BBBB', 'CCCC']);
  FMemo.ProbeSetTopLine(0);
  FMemo.ProbeMouseDown(2, 10000);  // far below content
  AssertEquals('click past last line clamps to last logical line',
    FMemo.ProbeLineCountLogical - 1, FMemo.ProbeCaretLine);
end;

{ TestDisabledMouseIgnored
  Enabled := False -> MouseDown leaves the caret unchanged. }
procedure TTyMemoTest.TestDisabledMouseIgnored;
var
  LH: Integer;
begin
  SetUpWithPadding(0);
  LoadLines(['AAAA', 'BBBB', 'CCCC']);
  FMemo.ProbeSetTopLine(0);
  FMemo.ProbeSetCaret(0, 0);
  FMemo.Enabled := False;
  LH := FMemo.ProbeLineHeight(96);
  FMemo.ProbeMouseDown(2, LH + (LH div 2));  // would otherwise select line 1
  AssertEquals('disabled mouse leaves caret line unchanged', 0, FMemo.ProbeCaretLine);
  AssertEquals('disabled mouse leaves caret col unchanged', 0, FMemo.ProbeCaretCol);
end;

{ --- T6 theme integration smoke --- }

{ TestThemedMemoResolvesStyle
  Load the shipped light theme into a real controller and assert that the
  TyMemo style block resolves with both a Background fill and a TextColor
  present. A missing theme entry would leave these absent — the control would
  render invisible (the v1.3 invisible-control bug class). This guards that the
  TyMemo block actually reaches the resolver via a from-disk theme load. }
procedure TTyMemoTest.TestThemedMemoResolvesStyle;
var
  Ctl: TTyStyleController;
  S: TTyStyleSet;
begin
  AssertTrue('light.tycss must exist for the themed smoke test',
    FileExists(ThemePath('light.tycss')));
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadTheme(ThemePath('light.tycss'));
    S := Ctl.Model.ResolveStyle('TyMemo', '', []);
    AssertTrue('themed TyMemo base must set Background (visible control)',
      tpBackground in S.Present);
    AssertTrue('themed TyMemo base must set TextColor (visible content)',
      tpTextColor in S.Present);
  finally
    Ctl.Free;
  end;
end;

{ --- Task 5: ReadOnly --- }

function MemoContentCodepoints(M: TTyMemo): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to M.Lines.Count - 1 do Inc(Result, UTF8Length(M.Lines[i]));
end;

procedure TTyMemoTest.TestMemoReadOnlyBlocksEditsAllowsNav;
var M: TTyMemoClipAccess;
begin
  M := TTyMemoClipAccess.Create(nil);
  try
    M.Lines.Text := 'abc';
    M.ReadOnly := True;
    M.InjectChar('x');                 // typing blocked
    AssertEquals('typing blocked', 'abc', Trim(M.Lines.Text));
    M.InjectKey(VK_RETURN, []);         // Enter (split) blocked
    AssertEquals('enter blocked (still 1 line)', 1, M.Lines.Count);
    M.InjectBackspace; M.InjectDelete;  // blocked
    AssertEquals('bksp/del blocked', 'abc', Trim(M.Lines.Text));
    M.InjectKey(VK_BACK, []);           // real-keyboard backspace path (inline KeyDown branch)
    AssertEquals('keydown backspace blocked', 'abc', Trim(M.Lines.Text));
    M.InjectKey(VK_DELETE, []);          // real-keyboard delete path (inline KeyDown branch)
    AssertEquals('keydown delete blocked', 'abc', Trim(M.Lines.Text));
    M.ClipText := 'ZZ'; M.PasteFromClipboard;   // paste blocked
    AssertEquals('paste blocked', 'abc', Trim(M.Lines.Text));
    M.Lines.Text := 'def';             // programmatic still works
    AssertEquals('Lines:= still works', 'def', Trim(M.Lines.Text));
  finally M.Free; end;
end;

procedure TTyMemoTest.TestMemoReadOnlyCutActsAsCopy;
var M: TTyMemoClipAccess;
begin
  M := TTyMemoClipAccess.Create(nil);
  try
    M.Lines.Text := 'abc'; M.ReadOnly := True; M.SelectAll;
    M.CutToClipboard;
    AssertTrue('cut copied something', Pos('abc', M.ClipText) > 0);
    AssertEquals('cut did not delete', 'abc', Trim(M.Lines.Text));
  finally M.Free; end;
end;

procedure TTyMemoTest.TestMemoMaxLengthCapsTyping;
var M: TTyMemoClipAccess;
begin
  M := TTyMemoClipAccess.Create(nil);
  try
    M.MaxLength := 3;
    M.InjectChar('a'); M.InjectChar('b'); M.InjectChar('c');
    M.InjectChar('d');                         // blocked at cap
    AssertEquals('typing capped', 'abc', Trim(M.Lines.Text));
    M.InjectKey(VK_RETURN, []);                // Enter allowed at cap (no content cp added)
    AssertEquals('enter allowed at cap', 2, M.Lines.Count);
  finally M.Free; end;
end;

procedure TTyMemoTest.TestMemoMaxLengthTruncatesPaste;
var M: TTyMemoClipAccess;
begin
  M := TTyMemoClipAccess.Create(nil);
  try
    M.MaxLength := 5; M.Lines.Text := 'ab';
    M.InjectKey(VK_END, [ssCtrl]);             // caret to doc end
    M.ClipText := 'XXXXXXXX'; M.PasteFromClipboard;
    AssertEquals('paste truncated to remaining room', 5, MemoContentCodepoints(M));
  finally M.Free; end;
end;

procedure TTyMemoCursorTest.TestMemoUsesIBeam;
var
  M: TTyMemo;
begin
  M := TTyMemo.Create(nil);
  try
    AssertEquals(crIBeam, M.Cursor);
  finally
    M.Free;
  end;
end;

initialization
  RegisterTest(TTyMemoTest);
  RegisterTest(TTyMemoCursorTest);
end.
