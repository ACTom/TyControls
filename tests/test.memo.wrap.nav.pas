unit test.memo.wrap.nav;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, LCLType, LazUTF8, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ScrollBar, tyControls.Memo;
type
  { Probe exposing the caret/visual-row surface needed to assert that Up/Down and
    Home/End operate over VISUAL ROWS under WordWrap=True while staying byte-
    identical (logical-line semantics) under WordWrap=False. }
  TTyMemoWrapNavProbe = class(TTyMemo)
  public
    procedure ProbeSetWordWrap(AValue: Boolean);
    function ProbeContentWidthFor(APPI: Integer): Integer;
    function ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
    function ProbeBuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
    procedure ProbeCaretToVisual(ALine, ACol, AContentWidth, APPI: Integer;
      out AVisualRow, AX: Integer);
    function ProbeCaretVisualRow(APPI: Integer): Integer;
    function ProbeCaretLine: Integer;
    function ProbeCaretCol: Integer;
    procedure ProbeSetCaret(ALine, ACol: Integer);
  end;

  TTyMemoWrapNavTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoWrapNavProbe;
    procedure SetUpMemo(const ACss: string; AWidth, AHeight: Integer);
    procedure LoadLines(const AItems: array of string);
    // The content width that makes 'one two three four five' wrap into >= 2 rows.
    function WrapWidthFor(const ALine: string): Integer;
  protected
    procedure TearDown; override;
  published
    // (a) WordWrap=False identity guard: Up/Down across two short lines unchanged.
    procedure TestNoWrapUpDownAcrossShortLinesUnchanged;
    // (b) WordWrap=True: Down moves to the next visual row of the SAME logical
    // line at the column under the desired-x; Up reverses.
    procedure TestWrapDownStaysSameLogicalLineNextRow;
    procedure TestWrapUpReversesDown;
    // (b) at the last visual row of a line, Down crosses to the next logical
    // line's FIRST visual row.
    procedure TestWrapDownCrossesToNextLogicalLineFirstRow;
    // (c) Home under wrap -> the caret's visual-row START col; End -> END col.
    procedure TestWrapHomeGoesToVisualRowStart;
    procedure TestWrapEndGoesToVisualRowEnd;
    // (c) Ctrl+Home / Ctrl+End remain document-wide even under wrap.
    procedure TestWrapCtrlHomeEndDocumentWide;
  end;

implementation

{ TTyMemoWrapNavProbe }

procedure TTyMemoWrapNavProbe.ProbeSetWordWrap(AValue: Boolean);
begin
  WordWrap := AValue;
end;

function TTyMemoWrapNavProbe.ProbeContentWidthFor(APPI: Integer): Integer;
begin
  Result := ContentWidthFor(APPI);
end;

function TTyMemoWrapNavProbe.ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
begin
  Result := MeasureLineWidths(ALine, APPI);
end;

function TTyMemoWrapNavProbe.ProbeBuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
begin
  Result := BuildVisualRows(AContentWidth, APPI);
end;

procedure TTyMemoWrapNavProbe.ProbeCaretToVisual(ALine, ACol, AContentWidth, APPI: Integer;
  out AVisualRow, AX: Integer);
begin
  CaretToVisual(ALine, ACol, AContentWidth, APPI, AVisualRow, AX);
end;

function TTyMemoWrapNavProbe.ProbeCaretVisualRow(APPI: Integer): Integer;
begin
  Result := CaretVisualRow(APPI);
end;

function TTyMemoWrapNavProbe.ProbeCaretLine: Integer;
begin
  Result := CaretLine;
end;

function TTyMemoWrapNavProbe.ProbeCaretCol: Integer;
begin
  Result := CaretCol;
end;

procedure TTyMemoWrapNavProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

{ TTyMemoWrapNavTest }

procedure TTyMemoWrapNavTest.SetUpMemo(const ACss: string; AWidth, AHeight: Integer);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FMemo := TTyMemoWrapNavProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;   // pin 96; macOS default is 72
  FMemo.SetBounds(0, 0, AWidth, AHeight);
end;

procedure TTyMemoWrapNavTest.LoadLines(const AItems: array of string);
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

function TTyMemoWrapNavTest.WrapWidthFor(const ALine: string): Integer;
var
  W: TTyIntArray;
begin
  // A content width between the 7th-codepoint prefix and the full line width
  // forces 'one two three four five' to wrap into >= 2 word-broken rows. Mirrors
  // the existing wrap pixel test's width choice so the layout is the same shape.
  W := FMemo.ProbeMeasureLineWidths(ALine, 96);
  Result := (W[7] + W[High(W)]) div 2;
end;

procedure TTyMemoWrapNavTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

const
  CSS = 'TyMemo { background:#101010; color:#F0F0F0; border-width:0px; '
      + 'padding:0px; font-size:14px; }';

// (a) WordWrap=False: caret on line 0, Down to line 1 (desired col clamped),
// Down to line 2 (desired col restored), Up reverses — byte-identical to today's
// logical-line semantics. Guards that the wrap rework left the no-wrap path alone.
procedure TTyMemoWrapNavTest.TestNoWrapUpDownAcrossShortLinesUnchanged;
begin
  SetUpMemo(CSS, 200, 120);
  FMemo.ProbeSetWordWrap(False);
  LoadLines(['abcde', 'xy', 'zzzzz']);
  FMemo.ProbeSetCaret(0, 4);
  FMemo.InjectKey(VK_DOWN, []);
  AssertEquals('down1 line 1', 1, FMemo.ProbeCaretLine);
  AssertEquals('down1 col clamped to len(xy)=2', 2, FMemo.ProbeCaretCol);
  FMemo.InjectKey(VK_DOWN, []);
  AssertEquals('down2 line 2', 2, FMemo.ProbeCaretLine);
  AssertEquals('down2 col desired restored to 4', 4, FMemo.ProbeCaretCol);
  FMemo.InjectKey(VK_UP, []);
  AssertEquals('up1 line 1', 1, FMemo.ProbeCaretLine);
  AssertEquals('up1 col clamped to len(xy)=2', 2, FMemo.ProbeCaretCol);
  FMemo.InjectKey(VK_UP, []);
  AssertEquals('up2 line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('up2 col desired restored to 4', 4, FMemo.ProbeCaretCol);
end;

// (b) WordWrap=True: with the caret on visual row 0 of a wrapped logical line,
// VK_DOWN moves to visual row 1 of the SAME logical line, with the column under
// the caret's desired-x (within row 1's [StartCol,EndCol] segment).
procedure TTyMemoWrapNavTest.TestWrapDownStaysSameLogicalLineNextRow;
var
  Line: string;
  CW, vr0, vr1: Integer;
  Rows: TTyVisualRowArray;
begin
  SetUpMemo(CSS, 200, 120);
  FMemo.ProbeSetWordWrap(True);
  Line := 'one two three four five';
  LoadLines([Line]);
  CW := WrapWidthFor(Line);
  FMemo.SetBounds(0, 0, CW, 120);
  Rows := FMemo.ProbeBuildVisualRows(FMemo.ProbeContentWidthFor(96), 96);
  AssertTrue('setup: wraps into >= 2 visual rows', Length(Rows) >= 2);
  // Need an interior column on row 1 to land at: row 1 must be wider than one
  // codepoint so the desired-x resolves strictly inside (StartCol,EndCol) and is
  // not the shared wrap-boundary column (which would bind back to row 0).
  AssertTrue('setup: row 1 has interior columns', Rows[1].EndCol - Rows[1].StartCol >= 2);

  // Caret a few codepoints into row 0 (an INTERIOR x, not the boundary), so Down
  // lands at an interior column of row 1 that unambiguously binds to row 1.
  FMemo.ProbeSetCaret(0, 2);
  vr0 := FMemo.ProbeCaretVisualRow(96);
  AssertEquals('caret starts on visual row 0', 0, vr0);

  FMemo.InjectKey(VK_DOWN, []);
  vr1 := FMemo.ProbeCaretVisualRow(96);
  AssertEquals('down stays on the same logical line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('down moves to visual row 1', vr0 + 1, vr1);
  // The resolved column lands inside row 1's segment.
  AssertTrue('caret col >= row1 StartCol',
    FMemo.ProbeCaretCol >= Rows[1].StartCol);
  AssertTrue('caret col <= row1 EndCol',
    FMemo.ProbeCaretCol <= Rows[1].EndCol);
end;

// (b) VK_UP reverses VK_DOWN: starting on row 0, Down then Up returns to row 0.
procedure TTyMemoWrapNavTest.TestWrapUpReversesDown;
var
  Line: string;
  CW: Integer;
begin
  SetUpMemo(CSS, 200, 120);
  FMemo.ProbeSetWordWrap(True);
  Line := 'one two three four five';
  LoadLines([Line]);
  CW := WrapWidthFor(Line);
  FMemo.SetBounds(0, 0, CW, 120);

  // Interior column on row 0 so the desired-x resolves to interior columns on the
  // adjacent rows (no shared-boundary ambiguity).
  FMemo.ProbeSetCaret(0, 2);
  AssertEquals('start row 0', 0, FMemo.ProbeCaretVisualRow(96));
  FMemo.InjectKey(VK_DOWN, []);
  AssertEquals('after down, row 1', 1, FMemo.ProbeCaretVisualRow(96));
  FMemo.InjectKey(VK_UP, []);
  AssertEquals('after up, back to row 0', 0, FMemo.ProbeCaretVisualRow(96));
  AssertEquals('back on logical line 0', 0, FMemo.ProbeCaretLine);
end;

// (b) At the LAST visual row of a wrapped logical line, VK_DOWN crosses to the
// FIRST visual row of the NEXT logical line.
procedure TTyMemoWrapNavTest.TestWrapDownCrossesToNextLogicalLineFirstRow;
var
  Line0: string;
  CW, lastRow0, i: Integer;
  Rows: TTyVisualRowArray;
begin
  SetUpMemo(CSS, 200, 120);
  FMemo.ProbeSetWordWrap(True);
  Line0 := 'one two three four five';
  LoadLines([Line0, 'second']);
  CW := WrapWidthFor(Line0);
  FMemo.SetBounds(0, 0, CW, 120);
  Rows := FMemo.ProbeBuildVisualRows(FMemo.ProbeContentWidthFor(96), 96);

  // Find the LAST visual row that still belongs to logical line 0.
  lastRow0 := 0;
  for i := 0 to High(Rows) do
    if Rows[i].Line = 0 then lastRow0 := i;
  AssertTrue('setup: line 0 spans >= 2 rows', lastRow0 >= 1);

  // Caret at end of logical line 0 (binds to its last visual row).
  FMemo.ProbeSetCaret(0, UTF8Length(Line0));
  AssertEquals('caret on the last visual row of line 0',
    lastRow0, FMemo.ProbeCaretVisualRow(96));

  FMemo.InjectKey(VK_DOWN, []);
  AssertEquals('down crosses to logical line 1', 1, FMemo.ProbeCaretLine);
  AssertEquals('down lands on line 1 first visual row',
    lastRow0 + 1, FMemo.ProbeCaretVisualRow(96));
  // Line 1's first visual row begins at StartCol 0.
  AssertEquals('lands within line 1 row, col >= 0', True,
    FMemo.ProbeCaretCol >= Rows[lastRow0 + 1].StartCol);
end;

// (c) Home under wrap -> the caret's visual-row START col (not col 0 of the
// logical line). With the caret on visual row 1, Home lands on row 1's StartCol.
procedure TTyMemoWrapNavTest.TestWrapHomeGoesToVisualRowStart;
var
  Line: string;
  CW: Integer;
  Rows: TTyVisualRowArray;
begin
  SetUpMemo(CSS, 200, 120);
  FMemo.ProbeSetWordWrap(True);
  Line := 'one two three four five';
  LoadLines([Line]);
  CW := WrapWidthFor(Line);
  FMemo.SetBounds(0, 0, CW, 120);
  Rows := FMemo.ProbeBuildVisualRows(FMemo.ProbeContentWidthFor(96), 96);
  AssertTrue('setup: >= 2 rows', Length(Rows) >= 2);
  AssertTrue('setup: row 1 StartCol > 0 (not the logical line start)',
    Rows[1].StartCol > 0);

  // Put the caret in the middle of visual row 1.
  FMemo.ProbeSetCaret(0, (Rows[1].StartCol + Rows[1].EndCol) div 2);
  AssertEquals('caret on visual row 1', 1, FMemo.ProbeCaretVisualRow(96));
  FMemo.InjectKey(VK_HOME, []);
  AssertEquals('home -> visual row 1 StartCol', Rows[1].StartCol, FMemo.ProbeCaretCol);
  AssertEquals('home stays on logical line 0', 0, FMemo.ProbeCaretLine);
end;

// (c) End under wrap -> the caret's visual-row END col.
procedure TTyMemoWrapNavTest.TestWrapEndGoesToVisualRowEnd;
var
  Line: string;
  CW: Integer;
  Rows: TTyVisualRowArray;
begin
  SetUpMemo(CSS, 200, 120);
  FMemo.ProbeSetWordWrap(True);
  Line := 'one two three four five';
  LoadLines([Line]);
  CW := WrapWidthFor(Line);
  FMemo.SetBounds(0, 0, CW, 120);
  Rows := FMemo.ProbeBuildVisualRows(FMemo.ProbeContentWidthFor(96), 96);
  AssertTrue('setup: >= 2 rows', Length(Rows) >= 2);
  AssertTrue('setup: row 0 EndCol < line length (a real interior wrap)',
    Rows[0].EndCol < UTF8Length(Line));

  // Caret at the start of visual row 0; End must go to row 0's EndCol, NOT the
  // end of the whole logical line.
  FMemo.ProbeSetCaret(0, 0);
  AssertEquals('caret on visual row 0', 0, FMemo.ProbeCaretVisualRow(96));
  FMemo.InjectKey(VK_END, []);
  AssertEquals('end -> visual row 0 EndCol', Rows[0].EndCol, FMemo.ProbeCaretCol);
  AssertEquals('end stays on logical line 0', 0, FMemo.ProbeCaretLine);
  // The caret still binds to visual row 0 (boundary tie-break to the earlier row).
  AssertEquals('caret still on visual row 0 after End', 0, FMemo.ProbeCaretVisualRow(96));
end;

// (c) Ctrl+Home/Ctrl+End remain document-wide even under wrap.
procedure TTyMemoWrapNavTest.TestWrapCtrlHomeEndDocumentWide;
var
  Line0: string;
  CW: Integer;
begin
  SetUpMemo(CSS, 200, 120);
  FMemo.ProbeSetWordWrap(True);
  Line0 := 'one two three four five';
  LoadLines([Line0, 'beta', 'gamma']);
  CW := WrapWidthFor(Line0);
  FMemo.SetBounds(0, 0, CW, 120);

  FMemo.ProbeSetCaret(1, 2);
  FMemo.InjectKey(VK_HOME, [ssCtrl]);
  AssertEquals('ctrl+home line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('ctrl+home col 0', 0, FMemo.ProbeCaretCol);
  FMemo.InjectKey(VK_END, [ssCtrl]);
  AssertEquals('ctrl+end last line', 2, FMemo.ProbeCaretLine);
  AssertEquals('ctrl+end last col', UTF8Length('gamma'), FMemo.ProbeCaretCol);
end;

initialization
  RegisterTest(TTyMemoWrapNavTest);
end.
