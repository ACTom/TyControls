unit test.memo.visualrows;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, LCLType, LazUTF8, TypInfo,
  BGRABitmap, BGRABitmapTypes, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ScrollBar, tyControls.Memo;
type
  { Probe subclass exposing the pure visual-row model surface for headless tests.
    No window/paint needed: BuildVisualRows / CaretToVisual / VisualToCaret are
    pure functions of (lines, content width, wrap mode). }
  TTyMemoVRProbe = class(TTyMemo)
  public
    procedure ProbeSetWordWrap(AValue: Boolean);
    function ProbeWordWrap: Boolean;
    function ProbeBuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
    procedure ProbeCaretToVisual(ALine, ACol, AContentWidth, APPI: Integer;
      out AVisualRow, AX: Integer);
    procedure ProbeVisualToCaret(AVisualRow, AX, AContentWidth, APPI: Integer;
      out ALine, ACol: Integer);
    function ProbeNextWordBoundary(const ALine: string; AIdx: Integer): Integer;
    function ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
    function ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
    function ProbeLineLen(ALineIndex: Integer): Integer;
    // T2 render-loop probes.
    function ProbeLineHeight(APPI: Integer): Integer;
    procedure ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    // T4 vertical-scroll-over-visual-rows probes.
    function ProbeVisibleRows: Integer;
    function ProbeTotalVisualRows(APPI: Integer): Integer;
    function ProbeMaxTopLine: Integer;
    function ProbeTopRow: Integer;        // raw FTopRow visual-row index
    function ProbeTopLine: Integer;       // mapped logical line of FTopRow
    procedure ProbeSetTopLine(AValue: Integer);
    procedure ProbeUpdateScrollBar;
    procedure ProbeEnsureCaretLineVisible(APPI: Integer);
    procedure ProbeSetCaret(ALine, ACol: Integer);
    function ProbeCaretVisualRow(APPI: Integer): Integer;
    function ProbeScrollBar: TTyScrollBar;
    function ProbeDoMouseWheel(AWheelDelta: Integer): Boolean;
  end;

  TTyMemoVisualRowsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoVRProbe;
    procedure SetUpMemo(const ACss: string);
    procedure LoadLines(const AItems: array of string);
  protected
    procedure TearDown; override;
  published
    procedure TestNoWrapIdentityRows;             // (a)
    procedure TestWrapBreaksAtWordBoundary;       // (b)
    procedure TestOverLongWordCharBreaks;         // (c)
    procedure TestCJKRunCharBreaks;               // (d)
    procedure TestEmptyLineEmitsOneRow;           // (e)
    procedure TestCaretVisualRoundTrip;           // (f)
    procedure TestWrapPointTieBreakBindsEarlier;  // (g)
    // --- T2 render loop over visual rows + published WordWrap ---
    procedure TestWordWrapDefaultsFalseAndPublished;  // (h)
    procedure TestNoWrapRenderIdentity;               // (i)
    procedure TestWrapRendersSecondVisualRow;         // (j)
    // --- T4 vertical scroll / scrollbar / wheel over visual rows ---
    procedure TestNoWrapScrollIdentityRowsEqualLogical;  // (k) compat
    procedure TestWrapScrollBarRangeOverVisualRows;      // (l)
    procedure TestWrapWheelScrollsVisualRows;            // (m)
    procedure TestWrapEnsureCaretRowVisible;             // (n)
  private
    // True if any pixel in horizontal band [X0..X1] at row Y is "light".
    function BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
  end;

implementation

{ TTyMemoVRProbe }

procedure TTyMemoVRProbe.ProbeSetWordWrap(AValue: Boolean);
begin
  WordWrap := AValue;
end;

function TTyMemoVRProbe.ProbeWordWrap: Boolean;
begin
  Result := WordWrap;
end;

function TTyMemoVRProbe.ProbeBuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
begin
  Result := BuildVisualRows(AContentWidth, APPI);
end;

procedure TTyMemoVRProbe.ProbeCaretToVisual(ALine, ACol, AContentWidth, APPI: Integer;
  out AVisualRow, AX: Integer);
begin
  CaretToVisual(ALine, ACol, AContentWidth, APPI, AVisualRow, AX);
end;

procedure TTyMemoVRProbe.ProbeVisualToCaret(AVisualRow, AX, AContentWidth, APPI: Integer;
  out ALine, ACol: Integer);
begin
  VisualToCaret(AVisualRow, AX, AContentWidth, APPI, ALine, ACol);
end;

function TTyMemoVRProbe.ProbeNextWordBoundary(const ALine: string; AIdx: Integer): Integer;
begin
  Result := NextWordBoundary(ALine, AIdx);
end;

function TTyMemoVRProbe.ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
begin
  Result := ColPixelXAt(ALine, ACol, APPI);
end;

function TTyMemoVRProbe.ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
begin
  Result := MeasureLineWidths(ALine, APPI);
end;

function TTyMemoVRProbe.ProbeLineLen(ALineIndex: Integer): Integer;
begin
  Result := LineLen(ALineIndex);
end;

function TTyMemoVRProbe.ProbeLineHeight(APPI: Integer): Integer;
begin
  Result := LineHeight(APPI);
end;

procedure TTyMemoVRProbe.ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TTyMemoVRProbe.ProbeVisibleRows: Integer;
begin
  Result := VisibleRows;
end;

function TTyMemoVRProbe.ProbeTotalVisualRows(APPI: Integer): Integer;
begin
  Result := TotalVisualRows(APPI);
end;

function TTyMemoVRProbe.ProbeMaxTopLine: Integer;
begin
  Result := MaxTopLine;
end;

function TTyMemoVRProbe.ProbeTopRow: Integer;
begin
  Result := TopRow;
end;

function TTyMemoVRProbe.ProbeTopLine: Integer;
begin
  Result := TopLine;
end;

procedure TTyMemoVRProbe.ProbeSetTopLine(AValue: Integer);
begin
  SetTopLine(AValue);
end;

procedure TTyMemoVRProbe.ProbeUpdateScrollBar;
begin
  UpdateScrollBar;
end;

procedure TTyMemoVRProbe.ProbeEnsureCaretLineVisible(APPI: Integer);
begin
  EnsureCaretLineVisible(APPI);
end;

procedure TTyMemoVRProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

function TTyMemoVRProbe.ProbeCaretVisualRow(APPI: Integer): Integer;
begin
  Result := CaretVisualRow(APPI);
end;

function TTyMemoVRProbe.ProbeScrollBar: TTyScrollBar;
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

function TTyMemoVRProbe.ProbeDoMouseWheel(AWheelDelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], AWheelDelta, Point(0, 0));
end;

{ TTyMemoVisualRowsTest }

procedure TTyMemoVisualRowsTest.SetUpMemo(const ACss: string);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FMemo := TTyMemoVRProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;   // pin 96; macOS default is 72
  FMemo.SetBounds(0, 0, 200, 120);
end;

procedure TTyMemoVisualRowsTest.LoadLines(const AItems: array of string);
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

procedure TTyMemoVisualRowsTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

// (a) WordWrap=False over 3 lines 'a','bb','' => exactly 3 rows, each
// (L,0,LineLen), identity: row i.Line == i.
procedure TTyMemoVisualRowsTest.TestNoWrapIdentityRows;
var
  Rows: TTyVisualRowArray;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(False);
  LoadLines(['a', 'bb', '']);
  Rows := FMemo.ProbeBuildVisualRows(180, 96);
  AssertEquals('no-wrap: exactly 3 rows', 3, Length(Rows));
  AssertEquals('row0.Line', 0, Rows[0].Line);
  AssertEquals('row0.StartCol', 0, Rows[0].StartCol);
  AssertEquals('row0.EndCol = LineLen(0)', FMemo.ProbeLineLen(0), Rows[0].EndCol);
  AssertEquals('row1.Line', 1, Rows[1].Line);
  AssertEquals('row1.StartCol', 0, Rows[1].StartCol);
  AssertEquals('row1.EndCol = LineLen(1)', FMemo.ProbeLineLen(1), Rows[1].EndCol);
  AssertEquals('row2.Line', 2, Rows[2].Line);
  AssertEquals('row2.StartCol', 0, Rows[2].StartCol);
  AssertEquals('row2.EndCol = LineLen(2)', FMemo.ProbeLineLen(2), Rows[2].EndCol);
end;

// (b) WordWrap=True, narrow content width, line 'aaa bbb ccc' breaks at the last
// SPACE before width. Assert StartCol/EndCol land on the boundary returned by
// NextWordBoundary, not mid-word.
procedure TTyMemoVisualRowsTest.TestWrapBreaksAtWordBoundary;
var
  Rows: TTyVisualRowArray;
  Line: string;
  W: TTyIntArray;
  CW, i, B, walk, prev: Integer;
  AllOnBoundary, OnBoundary: Boolean;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  Line := 'aaa bbb ccc';
  LoadLines([Line]);
  W := FMemo.ProbeMeasureLineWidths(Line, 96);
  // Width that fits 'aaa bbb' but not the full line: between the prefix width at
  // col 7 (after 'aaa bbb') and the full width — so the first row must break
  // somewhere before the last word.
  CW := (W[7] + W[High(W)]) div 2;
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('wrap: >= 2 rows for a too-wide line', Length(Rows) >= 2);
  // Every internal break column (EndCol of a row that is NOT the line's last row,
  // and StartCol of a non-first row on the same line) must equal a NextWordBoundary
  // value reachable from the row start — i.e. a word boundary, never mid-word.
  AllOnBoundary := True;
  for i := 0 to High(Rows) - 1 do
    if Rows[i].Line = Rows[i + 1].Line then
    begin
      // Boundary between row i and i+1 within the same logical line. A valid
      // (non-mid-word) wrap point is a genuine word boundary: walking
      // NextWordBoundary forward from the row start must land EXACTLY on B at
      // some step (the wrapper may pick any boundary <= the fit point, not only
      // the first one). If the walk steps over B, the break was mid-word.
      B := Rows[i].EndCol;
      OnBoundary := False;
      walk := FMemo.ProbeNextWordBoundary(Line, Rows[i].StartCol);
      prev := -1;
      while (walk <= B) and (walk > prev) do
      begin
        if walk = B then begin OnBoundary := True; Break; end;
        prev := walk;
        walk := FMemo.ProbeNextWordBoundary(Line, walk);
      end;
      if not OnBoundary then
        AllOnBoundary := False;
    end;
  AssertTrue('wrap breaks land on word boundaries (not mid-word)', AllOnBoundary);
  // Coverage: rows must tile the whole line [0..LineLen] with no gap/overlap.
  AssertEquals('first row starts at 0', 0, Rows[0].StartCol);
  AssertEquals('last row ends at LineLen', UTF8Length(Line), Rows[High(Rows)].EndCol);
  for i := 0 to High(Rows) - 1 do
    if Rows[i].Line = Rows[i + 1].Line then
      AssertEquals('contiguous segments (next.StartCol = prev.EndCol)',
        Rows[i].EndCol, Rows[i + 1].StartCol);
end;

// (c) Over-long single word 'aaaaaaaaaa' (no space) with width fitting ~5 chars
// CHAR-breaks into >= 2 rows, each advancing >= 1 col, covering the whole line.
procedure TTyMemoVisualRowsTest.TestOverLongWordCharBreaks;
var
  Rows: TTyVisualRowArray;
  Line: string;
  W: TTyIntArray;
  CW, i: Integer;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  Line := 'aaaaaaaaaa';   // 10 chars, no boundary
  LoadLines([Line]);
  W := FMemo.ProbeMeasureLineWidths(Line, 96);
  CW := W[5];             // fits exactly 5 chars
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('over-long word char-breaks into >= 2 rows', Length(Rows) >= 2);
  for i := 0 to High(Rows) do
    AssertTrue('each row advances >= 1 col', Rows[i].EndCol > Rows[i].StartCol);
  // Contiguous + full coverage.
  AssertEquals('first row starts at 0', 0, Rows[0].StartCol);
  AssertEquals('last row ends at LineLen', UTF8Length(Line), Rows[High(Rows)].EndCol);
  for i := 0 to High(Rows) - 1 do
    AssertEquals('contiguous', Rows[i].EndCol, Rows[i + 1].StartCol);
end;

// (d) CJK run (no spaces) char-breaks at the width (every CJK cp is a word cp).
procedure TTyMemoVisualRowsTest.TestCJKRunCharBreaks;
var
  Rows: TTyVisualRowArray;
  Line: string;
  W: TTyIntArray;
  CW, i: Integer;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  Line := '你好世界天地玄黄';   // 8 CJK codepoints, no spaces
  LoadLines([Line]);
  W := FMemo.ProbeMeasureLineWidths(Line, 96);
  CW := W[3];                  // fits ~3 CJK cps
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('CJK run char-breaks into >= 2 rows', Length(Rows) >= 2);
  for i := 0 to High(Rows) do
    AssertTrue('each CJK row advances >= 1 col', Rows[i].EndCol > Rows[i].StartCol);
  AssertEquals('first row starts at 0', 0, Rows[0].StartCol);
  AssertEquals('last row ends at LineLen', UTF8Length(Line), Rows[High(Rows)].EndCol);
end;

// (e) Empty logical line emits one (L,0,0) row.
procedure TTyMemoVisualRowsTest.TestEmptyLineEmitsOneRow;
var
  Rows: TTyVisualRowArray;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  LoadLines(['x', '', 'y']);
  Rows := FMemo.ProbeBuildVisualRows(180, 96);
  AssertEquals('3 short lines => 3 rows', 3, Length(Rows));
  AssertEquals('empty line row.Line', 1, Rows[1].Line);
  AssertEquals('empty line StartCol', 0, Rows[1].StartCol);
  AssertEquals('empty line EndCol', 0, Rows[1].EndCol);
end;

// (f) CaretToVisual round-trips with VisualToCaret. For several (line,col) the
// caret maps to a row whose [StartCol,EndCol] contains col, and
// VisualToCaret(row, x) returns the same (line,col).
procedure TTyMemoVisualRowsTest.TestCaretVisualRoundTrip;
var
  Rows: TTyVisualRowArray;
  L0, L1: string;
  CW, vr, x, rl, rc, i: Integer;

  procedure CheckRT(ALine, ACol: Integer);
  var
    RVR, RX, OL, OC: Integer;
  begin
    FMemo.ProbeCaretToVisual(ALine, ACol, CW, 96, RVR, RX);
    AssertTrue(Format('vr index in range for (%d,%d)', [ALine, ACol]),
      (RVR >= 0) and (RVR <= High(Rows)));
    AssertTrue(Format('col %d within row [%d..%d]',
      [ACol, Rows[RVR].StartCol, Rows[RVR].EndCol]),
      (ACol >= Rows[RVR].StartCol) and (ACol <= Rows[RVR].EndCol));
    FMemo.ProbeVisualToCaret(RVR, RX, CW, 96, OL, OC);
    AssertEquals(Format('round-trip line (%d,%d)', [ALine, ACol]), ALine, OL);
    AssertEquals(Format('round-trip col (%d,%d)', [ALine, ACol]), ACol, OC);
  end;

begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  L0 := 'hello world foo bar';
  L1 := 'second line here';
  LoadLines([L0, L1]);
  CW := FMemo.ProbeMeasureLineWidths(L0, 96)[11];  // narrow enough to wrap L0
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  vr := 0; x := 0; rl := 0; rc := 0; i := 0;  // silence hints
  if (vr <> 0) or (x <> 0) or (rl <> 0) or (rc <> 0) or (i <> 0) then ;
  // Several caret positions on each logical line, including row-interior cols.
  CheckRT(0, 0);
  CheckRT(0, 3);
  CheckRT(0, UTF8Length(L0));
  CheckRT(1, 0);
  CheckRT(1, 7);
  CheckRT(1, UTF8Length(L1));
end;

// (g) WRAP-POINT TIE-BREAK: a caret at a soft-wrap column binds to the earlier
// (line-end) row.
procedure TTyMemoVisualRowsTest.TestWrapPointTieBreakBindsEarlier;
var
  Rows: TTyVisualRowArray;
  Line: string;
  CW, vr, x, breakCol, i: Integer;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  Line := 'aaa bbb ccc ddd';
  LoadLines([Line]);
  CW := (FMemo.ProbeMeasureLineWidths(Line, 96)[7]
       + FMemo.ProbeMeasureLineWidths(Line, 96)[High(FMemo.ProbeMeasureLineWidths(Line, 96))]) div 2;
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('tie-break setup needs >= 2 rows on the line', Length(Rows) >= 2);
  // Find the first soft-wrap boundary column (EndCol of row 0, which continues
  // into row 1 on the same logical line).
  breakCol := -1;
  for i := 0 to High(Rows) - 1 do
    if (Rows[i].Line = 0) and (Rows[i + 1].Line = 0) then
    begin
      breakCol := Rows[i].EndCol;
      Break;
    end;
  AssertTrue('found a soft-wrap break column', breakCol > 0);
  // A caret at the soft-wrap column binds to the EARLIER row (the one whose
  // EndCol == breakCol), not the next row whose StartCol == breakCol.
  FMemo.ProbeCaretToVisual(0, breakCol, CW, 96, vr, x);
  AssertEquals('tie-break: caret at wrap col binds to earlier row',
    breakCol, Rows[vr].EndCol);
  AssertTrue('tie-break: bound row is not the continuation row',
    Rows[vr].StartCol < breakCol);
end;

function TTyMemoVisualRowsTest.BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
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

// (h) WordWrap is published (RTTI-visible / streamable) and reads back False on a
// fresh memo (the default). After SetWordWrap(True) the getter reflects the new
// value. Asserts the property exists in published RTTI so it survives streaming.
procedure TTyMemoVisualRowsTest.TestWordWrapDefaultsFalseAndPublished;
var
  PI: PPropInfo;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  AssertFalse('WordWrap defaults False on a fresh memo', FMemo.ProbeWordWrap);
  // RTTI: the published property must be discoverable (so it streams to .lfm).
  PI := GetPropInfo(FMemo, 'WordWrap');
  AssertTrue('WordWrap is a published property (RTTI-visible)', PI <> nil);
  AssertEquals('WordWrap RTTI type is Boolean', Ord(tkBool), Ord(PI^.PropType^.Kind));
  // Toggling through the published setter is observed by the getter.
  FMemo.ProbeSetWordWrap(True);
  AssertTrue('WordWrap reads back True after SetWordWrap(True)', FMemo.ProbeWordWrap);
end;

// (i) RENDER-EQUIVALENCE GUARD (PPI 96): WordWrap=False with short fitting text
// renders the SAME light-pixel bands as the legacy logical-line render — a row at
// y=ContentTop+i*LH still has text. ContentTop = 0 (padding 0). This guards the
// existing TestRendersAllVisibleLinesText / TestSecondLineYOffset expectations
// against the render-loop rewrite.
procedure TTyMemoVisualRowsTest.TestNoWrapRenderIdentity;
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  LH, Y0, Y1: Integer;
begin
  SetUpMemo('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(False);
  LoadLines(['AAA', 'BBB']);
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
      Y0 := LH div 2;            // visual row 0 == logical line 0 band
      Y1 := LH + (LH div 2);     // visual row 1 == logical line 1 band
      AssertTrue('no-wrap: row 0 drew text at ContentTop+0*LH',
        BandHasLightPixel(Reread, Y0, 0, 60, 120));
      AssertTrue('no-wrap: row 1 drew text at ContentTop+1*LH',
        BandHasLightPixel(Reread, Y1, 0, 60, 120));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

// (j) WRAP RENDER (PPI 96): WordWrap=True with ONE long logical line that wraps
// into >= 2 visual rows must DRAW the continuation segment in the SECOND visual
// row's y band (ContentTop+1*LH). The legacy logical-line render draws the line
// only once (in row 0) and clips the rest, so this FAILS before the render loop
// iterates visual rows and PASSES after.
procedure TTyMemoVisualRowsTest.TestWrapRendersSecondVisualRow;
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Rows: TTyVisualRowArray;
  Line: string;
  W: TTyIntArray;
  LH, CW, Y0, Y1: Integer;
begin
  // Padding 0 so ContentTop = 0 and the content width == control width.
  SetUpMemo('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  Line := 'aaa bbb ccc ddd eee fff';
  LoadLines([Line]);
  W := FMemo.ProbeMeasureLineWidths(Line, 96);
  // Content width that fits only part of the line -> forces a wrap.
  CW := (W[7] + W[High(W)]) div 2;
  FMemo.SetBounds(0, 0, CW, 120);   // control width == content width (padding 0)
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('wrap setup needs >= 2 visual rows', Length(Rows) >= 2);
  LH := FMemo.ProbeLineHeight(96);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(CW, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, CW, 120);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, CW, 120), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Y0 := LH div 2;            // visual row 0 band
      Y1 := LH + (LH div 2);     // visual row 1 (continuation) band
      AssertTrue('wrap: row 0 drew text',
        BandHasLightPixel(Reread, Y0, 0, CW - 1, 120));
      AssertTrue('wrap: continuation drew in row 1 band (ContentTop+LH)',
        BandHasLightPixel(Reread, Y1, 0, CW - 1, 120));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

// (k) COMPAT: WordWrap=False over N single-row logical lines (N > VisibleRows).
// TotalVisualRows == LineCountLogical, MaxTopLine == LineCount-VR, and FTopRow
// indexes a row whose .Line equals the row index (identity). This is the
// assertion that the existing scroll tests stay green under the row rename.
procedure TTyMemoVisualRowsTest.TestNoWrapScrollIdentityRowsEqualLogical;
var
  L: TStringList;
  i, VR, Total, N: Integer;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(False);
  VR := FMemo.ProbeVisibleRows;
  N := VR + 10;
  L := TStringList.Create;
  try
    for i := 0 to N - 1 do
      L.Add('line ' + IntToStr(i));   // each fits at width 200 -> one row
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  Total := FMemo.ProbeTotalVisualRows(96);
  AssertEquals('no-wrap: TotalVisualRows == LineCountLogical', N, Total);
  AssertEquals('no-wrap: MaxTopLine == LineCount - VR', N - VR, FMemo.ProbeMaxTopLine);
  // Set FTopRow to 3; the mapped TopLine must equal 3 (row index == logical line).
  FMemo.ProbeSetTopLine(3);
  AssertEquals('no-wrap: FTopRow == 3', 3, FMemo.ProbeTopRow);
  AssertEquals('no-wrap: TopLine maps to logical line 3', 3, FMemo.ProbeTopLine);
end;

// (l) WRAP: a SINGLE logical line wrapping to > VisibleRows visual rows makes the
// scrollbar visible with Max == TotalVisualRows - VisibleRows (it was 0 before,
// since one logical line never overflowed the logical-line count).
procedure TTyMemoVisualRowsTest.TestWrapScrollBarRangeOverVisualRows;
var
  Line: string;
  i, VR, Total: Integer;
  SB: TTyScrollBar;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  // Build a single long line of many short words so it wraps into many rows.
  Line := '';
  for i := 0 to 79 do
    Line := Line + 'wo' + IntToStr(i) + ' ';
  LoadLines([Line]);
  VR := FMemo.ProbeVisibleRows;
  Total := FMemo.ProbeTotalVisualRows(96);
  AssertTrue('wrap: one logical line wraps to > VisibleRows rows', Total > VR);
  FMemo.ProbeUpdateScrollBar;
  SB := FMemo.ProbeScrollBar;
  AssertTrue('wrap: scrollbar created for wrapped overflow', SB <> nil);
  AssertTrue('wrap: scrollbar visible for wrapped overflow', SB.Visible);
  AssertEquals('wrap: scrollbar Max == TotalVisualRows - VisibleRows',
    Total - VR, SB.Max);
  AssertEquals('wrap: MaxTopLine == TotalVisualRows - VisibleRows',
    Total - VR, FMemo.ProbeMaxTopLine);
end;

// (m) WRAP: wheel scrolls +/-3 VISUAL rows; scrollbar Position tracks FTopRow.
procedure TTyMemoVisualRowsTest.TestWrapWheelScrollsVisualRows;
var
  Line: string;
  i, VR, Total: Integer;
  SB: TTyScrollBar;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  Line := '';
  for i := 0 to 79 do
    Line := Line + 'wo' + IntToStr(i) + ' ';
  LoadLines([Line]);
  VR := FMemo.ProbeVisibleRows;
  Total := FMemo.ProbeTotalVisualRows(96);
  AssertTrue('wrap-wheel setup needs > VisibleRows rows', Total > VR);
  FMemo.ProbeUpdateScrollBar;
  FMemo.ProbeSetTopLine(0);
  AssertEquals('wrap: FTopRow starts at 0', 0, FMemo.ProbeTopRow);
  FMemo.ProbeDoMouseWheel(-120);            // wheel down
  AssertEquals('wrap: wheel down scrolls 3 visual rows', 3, FMemo.ProbeTopRow);
  SB := FMemo.ProbeScrollBar;
  AssertEquals('wrap: scrollbar Position tracks FTopRow', 3, SB.Position);
  FMemo.ProbeDoMouseWheel(120);             // wheel up
  AssertEquals('wrap: wheel up scrolls back to 0', 0, FMemo.ProbeTopRow);
end;

// (n) WRAP: EnsureCaretLineVisible keeps the caret's VISUAL ROW inside the
// visible window [FTopRow, FTopRow+VR-1]. Caret at end-of-(long-)line sits on a
// late visual row; ensuring visibility scrolls FTopRow down to include it.
procedure TTyMemoVisualRowsTest.TestWrapEnsureCaretRowVisible;
var
  Line: string;
  i, VR, CaretVR, Top: Integer;
begin
  SetUpMemo('TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo.ProbeSetWordWrap(True);
  Line := '';
  for i := 0 to 79 do
    Line := Line + 'wo' + IntToStr(i) + ' ';
  LoadLines([Line]);
  VR := FMemo.ProbeVisibleRows;
  FMemo.ProbeSetTopLine(0);
  // Caret to end of the single long line: it lives on the last visual row.
  FMemo.ProbeSetCaret(0, UTF8Length(Line));
  FMemo.ProbeEnsureCaretLineVisible(96);
  CaretVR := FMemo.ProbeCaretVisualRow(96);
  Top := FMemo.ProbeTopRow;
  AssertTrue('wrap: caret visual row >= FTopRow', CaretVR >= Top);
  AssertTrue('wrap: caret visual row <= FTopRow + VR - 1', CaretVR <= Top + VR - 1);
end;

initialization
  RegisterTest(TTyMemoVisualRowsTest);
end.
