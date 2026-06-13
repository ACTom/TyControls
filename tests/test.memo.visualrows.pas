unit test.memo.visualrows;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, LCLType, LazUTF8, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Memo;
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

initialization
  RegisterTest(TTyMemoVisualRowsTest);
end.
