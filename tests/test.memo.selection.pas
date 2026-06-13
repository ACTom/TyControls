unit test.memo.selection;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ScrollBar,
  tyControls.Memo;
type
  { Probe subclass: exposes the protected 2D-selection API for headless tests. }
  TTyMemoSelProbe = class(TTyMemo)
  public
    function ProbeHasSelection: Boolean;
    function ProbeSelText: string;
    procedure ProbeSelectAll;
    procedure ProbeClearSelection;
    procedure ProbeSetCaret(ALine, ACol: Integer);
    procedure ProbeSetAnchor(ALine, ACol: Integer);
    function ProbeCaretLine: Integer;
    function ProbeCaretCol: Integer;
    procedure ProbeSelStart(out SL, SC: Integer);
    procedure ProbeSelEnd(out EL, EC: Integer);
    procedure ProbeDeleteSelection;
    function ProbeLineCount: Integer;
    function ProbeLine(AIndex: Integer): string;
    // --- T3 paint probes (mirror TTyMemoProbe in test.memo) ---
    procedure ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure ProbeSetForceFocused(AValue: Boolean);
    function ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
    function ProbeLineHeight(APPI: Integer): Integer;
    // --- T6 word-navigation probes ---
    function ProbeNextWordBoundary(const ALine: string; AIdx: Integer): Integer;
    function ProbePrevWordBoundary(const ALine: string; AIdx: Integer): Integer;
    // --- T7 mouse drag-select probes (drive the protected mouse handlers) ---
    procedure ProbeMouseDown(X, Y: Integer);
    procedure ProbeMouseMove(X, Y: Integer);
    procedure ProbeMouseUp(X, Y: Integer);
  end;

  { Clipboard probe: routes the virtual clipboard hooks to an in-memory string so
    headless tests never touch the real OS clipboard (mirrors
    TTyEditClipboardAccess). }
  TTyMemoClipboardProbe = class(TTyMemoSelProbe)
  private
    FClipText: string;
  protected
    function ReadClipboardText: string; override;
    procedure WriteClipboardText(const S: string); override;
  public
    property ClipText: string read FClipText write FClipText;
  end;

  TTyMemoSelectionTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoSelProbe;
    FClip: TTyMemoClipboardProbe;
    FChangeCount: Integer;
    procedure SetUpMemo;
    procedure SetUpMemoCss(const ACss: string);
    // Build a clipboard probe (FClip) wired to the same controller/style as
    // SetUpMemo, with OnChange counting into FChangeCount.
    procedure SetUpClip;
    procedure LoadClipLines(const AItems: array of string);
    procedure LoadLines(const AItems: array of string);
    procedure OnMemoChange(Sender: TObject);
    // True iff some pixel x in [X0..X1] at row Y has all channels > AThresh
    // (mirrors TTyMemoTest.BandHasLightPixel in test.memo).
    function BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
    // True iff some pixel x in [X0..X1] at row Y is "band-bright": all channels in
    // (ALo..AHi]. The ~35%-alpha band over a near-black bg lands mid-grey (~99),
    // distinct from glyph ink (~240) and background (~16) — this lets band-presence
    // be detected independently of overlapping light text.
    function BandHasMidPixel(ABmp: TBGRABitmap; Y, X0, X1, ALo, AHi: Integer): Boolean;
  protected
    procedure TearDown; override;
  published
    procedure TestNoSelectionInitially;
    procedure TestSelectAllSpansDocument;
    procedure TestSelTextSingleLine;
    procedure TestSelTextMultiLineJoinedByLineEnding;
    procedure TestOrderedSelLexicographic;
    procedure TestClearSelectionCollapses;
    // --- T2: DeleteSelection 2D + typing/Enter/Backspace/Delete routing ---
    procedure TestDeleteSelectionWithinLine;
    procedure TestDeleteSelectionMultiLineMergesHeadTail;
    procedure TestTypingReplacesSelection;
    procedure TestEnterReplacesSelection;
    procedure TestBackspaceDeletesSelectionNotPrevChar;
    procedure TestBackspaceNoSelectionStillNoopAtOrigin;
    // --- T3: selection-band rendering per visible line + caret gating ---
    procedure TestSelectionBandSingleLine;
    procedure TestSelectionBandFullInteriorLine;
    procedure TestNoCaretDuringSelection;
    // --- T4: Shift-extend navigation (anchor fixed; unshifted nav collapses) ---
    procedure TestShiftRightExtends;
    procedure TestShiftDownExtendsAcrossLines;
    procedure TestShiftHomeEndExtendLineLocal;
    procedure TestUnshiftedArrowCollapses;
    // --- T5: clipboard copy/cut/multi-line paste + Ctrl/Cmd shortcuts ---
    procedure TestCopyMultiLine;
    procedure TestCutMultiLine;
    procedure TestPasteSplitsIntoLines;
    procedure TestPasteSingleSegmentInserts;
    procedure TestPasteCRLFNormalizes;
    procedure TestSelectAllKey;
    procedure TestPasteEmptyNoOp;
    // --- T6: word navigation (move/extend/delete; per-line + cross-line) ---
    procedure TestPrevNextWordBoundaryPerLine;
    procedure TestCtrlLeftMovesByWord;
    procedure TestCtrlLeftAtCol0CrossesLine;
    procedure TestCtrlRightAtLineEndCrossesLine;
    procedure TestShiftCtrlRightExtendsByWord;
    procedure TestCtrlBackspaceDeletesWord;
    procedure TestCtrlBackspaceAtCol0Merges;
    procedure TestCtrlDeleteDeletesWord;
    procedure TestWordNavCJK;
    // --- T7: mouse drag-select (MouseDown anchor + MouseMove/MouseUp) ---
    procedure TestDragSelectsAcrossColumns;
    procedure TestDragSelectsAcrossLines;
    procedure TestMouseUpEndsDrag;
    procedure TestDisabledMouseMoveIgnored;
  end;

implementation

{ TTyMemoSelProbe }

function TTyMemoSelProbe.ProbeHasSelection: Boolean;
begin
  Result := HasSelection;
end;

function TTyMemoSelProbe.ProbeSelText: string;
begin
  Result := SelText;
end;

procedure TTyMemoSelProbe.ProbeSelectAll;
begin
  SelectAll;
end;

procedure TTyMemoSelProbe.ProbeClearSelection;
begin
  ClearSelection;
end;

procedure TTyMemoSelProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

procedure TTyMemoSelProbe.ProbeSetAnchor(ALine, ACol: Integer);
begin
  SetSelAnchor(ALine, ACol);
end;

function TTyMemoSelProbe.ProbeCaretLine: Integer;
begin
  Result := CaretLine;
end;

function TTyMemoSelProbe.ProbeCaretCol: Integer;
begin
  Result := CaretCol;
end;

procedure TTyMemoSelProbe.ProbeSelStart(out SL, SC: Integer);
begin
  SL := SelStartLine;
  SC := SelStartCol;
end;

procedure TTyMemoSelProbe.ProbeSelEnd(out EL, EC: Integer);
begin
  EL := SelEndLine;
  EC := SelEndCol;
end;

procedure TTyMemoSelProbe.ProbeDeleteSelection;
begin
  DeleteSelection;
end;

function TTyMemoSelProbe.ProbeLineCount: Integer;
begin
  Result := Lines.Count;
end;

function TTyMemoSelProbe.ProbeLine(AIndex: Integer): string;
begin
  Result := Lines[AIndex];
end;

procedure TTyMemoSelProbe.ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyMemoSelProbe.ProbeSetForceFocused(AValue: Boolean);
begin
  SetForceFocused(AValue);
end;

function TTyMemoSelProbe.ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
begin
  Result := ColPixelXAt(ALine, ACol, APPI);
end;

function TTyMemoSelProbe.ProbeLineHeight(APPI: Integer): Integer;
begin
  Result := LineHeight(APPI);
end;

function TTyMemoSelProbe.ProbeNextWordBoundary(const ALine: string; AIdx: Integer): Integer;
begin
  Result := NextWordBoundary(ALine, AIdx);
end;

function TTyMemoSelProbe.ProbePrevWordBoundary(const ALine: string; AIdx: Integer): Integer;
begin
  Result := PrevWordBoundary(ALine, AIdx);
end;

procedure TTyMemoSelProbe.ProbeMouseDown(X, Y: Integer);
begin
  // Left-button press at (X,Y): positions caret + sets anchor + starts dragging.
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TTyMemoSelProbe.ProbeMouseMove(X, Y: Integer);
begin
  // Drag with the left button held (Shift carries ssLeft like a real drag).
  MouseMove([ssLeft], X, Y);
end;

procedure TTyMemoSelProbe.ProbeMouseUp(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

{ TTyMemoClipboardProbe }

function TTyMemoClipboardProbe.ReadClipboardText: string;
begin
  Result := FClipText;
end;

procedure TTyMemoClipboardProbe.WriteClipboardText(const S: string);
begin
  FClipText := S;
end;

{ TTyMemoSelectionTest }

procedure TTyMemoSelectionTest.SetUpMemo;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo := TTyMemoSelProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, 200, 120);
  FChangeCount := 0;
  FMemo.OnChange := @OnMemoChange;
end;

procedure TTyMemoSelectionTest.SetUpMemoCss(const ACss: string);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FMemo := TTyMemoSelProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, 200, 120);
  FChangeCount := 0;
  FMemo.OnChange := @OnMemoChange;
end;

procedure TTyMemoSelectionTest.SetUpClip;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FClip := TTyMemoClipboardProbe.Create(nil);
  FClip.Controller := FCtl;
  FClip.Font.PixelsPerInch := 96;
  FClip.SetBounds(0, 0, 200, 120);
  FChangeCount := 0;
  FClip.OnChange := @OnMemoChange;
end;

procedure TTyMemoSelectionTest.LoadClipLines(const AItems: array of string);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    for i := Low(AItems) to High(AItems) do
      L.Add(AItems[i]);
    FClip.Lines := L;
  finally
    L.Free;
  end;
end;

procedure TTyMemoSelectionTest.OnMemoChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

function TTyMemoSelectionTest.BandHasLightPixel(ABmp: TBGRABitmap;
  Y, X0, X1, AThresh: Integer): Boolean;
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

function TTyMemoSelectionTest.BandHasMidPixel(ABmp: TBGRABitmap;
  Y, X0, X1, ALo, AHi: Integer): Boolean;
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
    if (Px.red > ALo) and (Px.red <= AHi)
      and (Px.green > ALo) and (Px.green <= AHi)
      and (Px.blue > ALo) and (Px.blue <= AHi) then
      Exit(True);
  end;
end;

procedure TTyMemoSelectionTest.LoadLines(const AItems: array of string);
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

procedure TTyMemoSelectionTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FClip.Free;
  FClip := nil;
  FCtl.Free;
  FCtl := nil;
end;

procedure TTyMemoSelectionTest.TestNoSelectionInitially;
begin
  SetUpMemo;
  AssertFalse('fresh memo has no selection', FMemo.ProbeHasSelection);
  AssertEquals('fresh memo SelText empty', '', FMemo.ProbeSelText);
end;

procedure TTyMemoSelectionTest.TestSelectAllSpansDocument;
var
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines(['ab', 'c中d', '']);
  FMemo.ProbeSelectAll;
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('SelStartLine=0', 0, SL);
  AssertEquals('SelStartCol=0', 0, SC);
  AssertEquals('SelEndLine=2 (last line)', 2, EL);
  AssertEquals('SelEndCol=0 (empty last line)', 0, EC);
  AssertTrue('SelectAll yields a selection', FMemo.ProbeHasSelection);
end;

procedure TTyMemoSelectionTest.TestSelTextSingleLine;
begin
  SetUpMemo;
  LoadLines(['abcde']);
  FMemo.ProbeSetCaret(0, 4);
  FMemo.ProbeSetAnchor(0, 1);
  AssertEquals('single-line SelText', 'bcd', FMemo.ProbeSelText);
end;

procedure TTyMemoSelectionTest.TestSelTextMultiLineJoinedByLineEnding;
begin
  SetUpMemo;
  LoadLines(['hello', 'wor中ld', 'tail']);
  FMemo.ProbeSetCaret(2, 2);
  FMemo.ProbeSetAnchor(0, 2);
  AssertEquals('multi-line SelText joined by LineEnding',
    'llo' + LineEnding + 'wor中ld' + LineEnding + 'ta', FMemo.ProbeSelText);
end;

procedure TTyMemoSelectionTest.TestOrderedSelLexicographic;
var
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines(['abcde', 'fghij', 'klmno']);
  // Anchor AFTER caret: ordering must be independent of which side is the anchor.
  FMemo.ProbeSetCaret(0, 3);
  FMemo.ProbeSetAnchor(2, 1);
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('SelStartLine=0', 0, SL);
  AssertEquals('SelStartCol=3', 3, SC);
  AssertEquals('SelEndLine=2', 2, EL);
  AssertEquals('SelEndCol=1', 1, EC);
end;

procedure TTyMemoSelectionTest.TestClearSelectionCollapses;
begin
  SetUpMemo;
  LoadLines(['abcde', 'fghij']);
  FMemo.ProbeSetCaret(1, 2);
  FMemo.ProbeSetAnchor(0, 1);
  AssertTrue('selection present before clear', FMemo.ProbeHasSelection);
  FMemo.ProbeClearSelection;
  AssertFalse('no selection after clear', FMemo.ProbeHasSelection);
  AssertEquals('caret line unchanged after clear', 1, FMemo.ProbeCaretLine);
  AssertEquals('caret col unchanged after clear', 2, FMemo.ProbeCaretCol);
end;

// --- T2: DeleteSelection 2D + typing/Enter/Backspace/Delete routing ---

procedure TTyMemoSelectionTest.TestDeleteSelectionWithinLine;
begin
  SetUpMemo;
  LoadLines(['abcdef']);
  FMemo.ProbeSetAnchor(0, 1);
  FMemo.ProbeSetCaret(0, 4);  // SetCaret collapses; re-anchor after
  FMemo.ProbeSetAnchor(0, 1);
  AssertTrue('selection present', FMemo.ProbeHasSelection);
  FMemo.ProbeDeleteSelection;
  AssertEquals('line spliced to aef', 'aef', FMemo.ProbeLine(0));
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 1', 1, FMemo.ProbeCaretCol);
  AssertFalse('selection collapsed', FMemo.ProbeHasSelection);
end;

procedure TTyMemoSelectionTest.TestDeleteSelectionMultiLineMergesHeadTail;
begin
  SetUpMemo;
  LoadLines(['hello', 'middle', 'world']);
  FMemo.ProbeSetCaret(2, 3);
  FMemo.ProbeSetAnchor(0, 2);
  AssertTrue('selection present', FMemo.ProbeHasSelection);
  FMemo.ProbeDeleteSelection;
  AssertEquals('collapsed to single line', 1, FMemo.ProbeLineCount);
  AssertEquals('head he + tail ld', 'held', FMemo.ProbeLine(0));
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 2', 2, FMemo.ProbeCaretCol);
end;

procedure TTyMemoSelectionTest.TestTypingReplacesSelection;
begin
  SetUpMemo;
  LoadLines(['abc', 'def']);
  FMemo.ProbeSetCaret(1, 1);
  FMemo.ProbeSetAnchor(0, 1);
  FMemo.InjectChar('X');
  AssertEquals('collapsed to single line', 1, FMemo.ProbeLineCount);
  AssertEquals('aXef', 'aXef', FMemo.ProbeLine(0));
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 2', 2, FMemo.ProbeCaretCol);
  AssertEquals('OnChange fired once', 1, FChangeCount);
end;

procedure TTyMemoSelectionTest.TestEnterReplacesSelection;
begin
  SetUpMemo;
  LoadLines(['abc', 'def']);
  FMemo.ProbeSetCaret(1, 1);
  FMemo.ProbeSetAnchor(0, 1);
  FMemo.InjectKey(VK_RETURN, []);
  AssertEquals('two lines after split', 2, FMemo.ProbeLineCount);
  AssertEquals('line 0 = a', 'a', FMemo.ProbeLine(0));
  AssertEquals('line 1 = ef', 'ef', FMemo.ProbeLine(1));
end;

procedure TTyMemoSelectionTest.TestBackspaceDeletesSelectionNotPrevChar;
begin
  SetUpMemo;
  LoadLines(['abcd']);
  FMemo.ProbeSetCaret(0, 3);
  FMemo.ProbeSetAnchor(0, 1);
  FMemo.InjectBackspace;
  AssertEquals('selection deleted to ad', 'ad', FMemo.ProbeLine(0));
  AssertEquals('caret col 1', 1, FMemo.ProbeCaretCol);
  AssertFalse('selection collapsed', FMemo.ProbeHasSelection);
end;

procedure TTyMemoSelectionTest.TestBackspaceNoSelectionStillNoopAtOrigin;
begin
  SetUpMemo;
  LoadLines(['abc']);
  FMemo.ProbeSetCaret(0, 0);  // no anchor diff -> no selection
  AssertFalse('no selection', FMemo.ProbeHasSelection);
  FMemo.InjectBackspace;
  AssertEquals('line unchanged', 'abc', FMemo.ProbeLine(0));
  AssertEquals('OnChange not fired (additivity)', 0, FChangeCount);
end;

// --- T3: selection-band rendering per visible line + caret gating ---

{ TestSelectionBandSingleLine
  Single selected line '        GH' (eight leading spaces, then GH),
  anchor(0,2)..caret(0,6). The band fills the full cell height over x in
  [ColPixelXAt(0,2)..ColPixelXAt(0,6)], which lies entirely over blank spaces
  (cols 2..5, with cols 6..7 also blank so the visible 'GH' at cols 8..9 and its
  antialias fringe stay clear of the scanned range). The band is therefore the
  ONLY thing painted in the mid-band region. The ~35%-alpha white band over the
  near-black bg lands mid-grey (~99), distinct from glyph ink (#F0F0F0=240) and
  background (~16). So a "band-bright" (mid-grey) pixel must exist in the mid-band
  x-range, but NONE left of the band start (cols 0..1 are also blank spaces; only
  the near-black bg there). Before the band code exists the mid-band region is
  blank and the test fails. }
procedure TTyMemoSelectionTest.TestSelectionBandSingleLine;
const
  LINE = '        GH';
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  LH, X2, X6, probeY: Integer;
  FoundInBand, FoundLeft: Boolean;
  yy: Integer;
begin
  SetUpMemoCss('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; }' +
    ' TyMemo:focus { border-color:#FFFFFF; }');
  LoadLines([LINE]);
  FMemo.ProbeSetCaret(0, 6);
  FMemo.ProbeSetAnchor(0, 2);
  AssertTrue('selection present', FMemo.ProbeHasSelection);
  FMemo.ProbeSetForceFocused(True);

  LH := FMemo.ProbeLineHeight(96);
  X2 := FMemo.ProbeColPixelXAt(LINE, 2, 96);
  X6 := FMemo.ProbeColPixelXAt(LINE, 6, 96);

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 200, 120);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, 200, 120), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Band-bright = mid-grey (lo=40, hi=180): catches the ~99 band, ignores the
      // ~240 glyph ink and the ~16 bg, so it works across the whole cell height.
      // Scan strictly inside the band [ColX(2)+1 .. ColX(6)-3], staying clear of
      // the 1px caret bar's antialias fringe at the band's right edge (ColX(6)).
      FoundInBand := False;
      FoundLeft := False;
      for yy := 0 to LH - 1 do
      begin
        probeY := yy;
        if BandHasMidPixel(Reread, probeY, X2 + 1, X6 - 3, 40, 180) then
          FoundInBand := True;
        if X2 - 2 >= 0 then
          if BandHasMidPixel(Reread, probeY, 0, X2 - 2, 40, 180) then
            FoundLeft := True;
      end;
      AssertTrue('band-bright pixel exists in mid-band [ColX(2)..ColX(6)]', FoundInBand);
      AssertFalse('no band-bright pixel left of band start [0..ColX(2)-2]', FoundLeft);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ TestSelectionBandFullInteriorLine
  Lines ['AAAA','BBBB','CCCC'], anchor(0,1)..caret(2,1). Interior line 1 is fully
  selected, so its band spans the whole content width up to the right content edge.
  Assert a light band pixel near the right content edge of row 1's band. }
procedure TTyMemoSelectionTest.TestSelectionBandFullInteriorLine;
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  LH, probeY: Integer;
  FoundRight: Boolean;
  yy: Integer;
begin
  SetUpMemoCss('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; }' +
    ' TyMemo:focus { border-color:#FFFFFF; }');
  LoadLines(['AAAA', 'BBBB', 'CCCC']);
  FMemo.ProbeSetCaret(2, 1);
  FMemo.ProbeSetAnchor(0, 1);
  AssertTrue('selection present', FMemo.ProbeHasSelection);
  FMemo.ProbeSetForceFocused(True);

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
      // Row 1 occupies y in [LH..2*LH); scan near the right content edge
      // (x in [180..199]) where 'BBBB' has no glyph ink — only the full-width
      // interior band reaches there. Mid-grey (40..180) = the band specifically.
      FoundRight := False;
      for yy := LH to (2 * LH) - 1 do
      begin
        probeY := yy;
        if BandHasMidPixel(Reread, probeY, 180, 199, 40, 180) then
          FoundRight := True;
      end;
      AssertTrue('full-width interior band reaches the right content edge of row 1',
        FoundRight);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ TestNoCaretDuringSelection
  With ForceFocused and a selection, the caret must be hidden (gated on not
  HasSelection). The no-selection case draws a tall light caret run at the caret
  column X; the with-selection case must NOT show that same isolated caret bar
  (the column is either band-dominated or, just past the band end, dark). We probe
  the caret column at the END of the selection (caret(0,1) on a single short line),
  scanning a column just past the band so it is NOT covered by the band: with no
  selection a caret run appears there; with a selection it does not. }
procedure TTyMemoSelectionTest.TestNoCaretDuringSelection;
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  LH, CaretX, y: Integer;
  RunWithSel, RunNoSel: Integer;
  Px: TBGRAPixel;
begin
  SetUpMemoCss('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; }' +
    ' TyMemo:focus { border-color:#FFFFFF; }');
  LoadLines(['XY']);
  FMemo.ProbeSetForceFocused(True);

  // Caret column = end of the selection at col 1. Anchor(0,0)..caret(0,1).
  CaretX := FMemo.ProbeColPixelXAt('XY', 1, 96);
  LH := FMemo.ProbeLineHeight(96);

  // (a) With selection: caret must be hidden. The selection band covers
  // [ColX(0)..ColX(1)]; the caret bar at ColX(1) would be the band's right edge.
  FMemo.ProbeSetCaret(0, 1);
  FMemo.ProbeSetAnchor(0, 0);
  AssertTrue('selection present', FMemo.ProbeHasSelection);

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 200, 120);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, 200, 120), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      // A focused caret bar is a near-white vertical run (text color #F0F0F0=240).
      // Count rows in line 0's cell where the caret column is caret-bright (>200).
      RunWithSel := 0;
      for y := 0 to LH - 1 do
      begin
        if (y < 0) or (y >= Reread.Height) then Continue;
        Px := Reread.GetPixel(CaretX, y);
        if (Px.red > 200) and (Px.green > 200) and (Px.blue > 200) then
          Inc(RunWithSel);
      end;
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;

  // (b) Without selection: caret at col 1, no anchor diff -> caret IS drawn.
  FMemo.ProbeSetCaret(0, 1);
  AssertFalse('no selection in control case', FMemo.ProbeHasSelection);

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 200, 120);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, 200, 120), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      RunNoSel := 0;
      for y := 0 to LH - 1 do
      begin
        if (y < 0) or (y >= Reread.Height) then Continue;
        Px := Reread.GetPixel(CaretX, y);
        if (Px.red > 200) and (Px.green > 200) and (Px.blue > 200) then
          Inc(RunNoSel);
      end;
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;

  // No-selection draws a tall caret run; with-selection hides it. The two cases
  // MUST differ, and the selection case must have a strictly shorter caret run.
  AssertTrue(Format('no-selection caret run is tall (run=%d, LH=%d)',
    [RunNoSel, LH]), RunNoSel >= LH div 2);
  AssertTrue(Format('selection hides caret: run shorter than no-selection ' +
    '(withSel=%d, noSel=%d)', [RunWithSel, RunNoSel]), RunWithSel < RunNoSel);
end;

// --- T4: Shift-extend navigation (Shift keeps anchor; unshifted nav collapses) ---

{ TestShiftRightExtends
  Over ['abcde'], caret(0,1). Shift+Right twice extends the caret to (0,3) while
  the anchor stays at (0,1): a forward selection of 'bc'. }
procedure TTyMemoSelectionTest.TestShiftRightExtends;
var
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines(['abcde']);
  FMemo.ProbeSetCaret(0, 1);
  FMemo.InjectKey(VK_RIGHT, [ssShift]);
  FMemo.InjectKey(VK_RIGHT, [ssShift]);
  AssertTrue('selection present after Shift+Right x2', FMemo.ProbeHasSelection);
  AssertEquals('SelText bc', 'bc', FMemo.ProbeSelText);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 3', 3, FMemo.ProbeCaretCol);
  // Anchor must remain at (0,1): the selection start is (0,1).
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('SelStartLine 0', 0, SL);
  AssertEquals('SelStartCol 1 (anchor fixed)', 1, SC);
  AssertEquals('SelEndLine 0', 0, EL);
  AssertEquals('SelEndCol 3', 3, EC);
end;

{ TestShiftDownExtendsAcrossLines
  Over ['abcd','efgh'], caret(0,2). Shift+Down extends to (1,2) keeping anchor at
  (0,2): a multi-line selection of 'cd' + LineEnding + 'ef'. }
procedure TTyMemoSelectionTest.TestShiftDownExtendsAcrossLines;
var
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines(['abcd', 'efgh']);
  FMemo.ProbeSetCaret(0, 2);
  FMemo.InjectKey(VK_DOWN, [ssShift]);
  AssertTrue('selection present after Shift+Down', FMemo.ProbeHasSelection);
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('SelStartLine 0', 0, SL);
  AssertEquals('SelStartCol 2', 2, SC);
  AssertEquals('SelEndLine 1', 1, EL);
  AssertEquals('SelEndCol 2', 2, EC);
  AssertEquals('SelText cd<LE>ef', 'cd' + LineEnding + 'ef', FMemo.ProbeSelText);
end;

{ TestShiftHomeEndExtendLineLocal
  Over ['hello world'], caret(0,5). Shift+Home extends to (0,0) keeping anchor at
  (0,5): SelText 'hello'. Then from the SAME anchor Shift+End extends to (0,11):
  selection (0,5)..(0,11), SelText ' world'. }
procedure TTyMemoSelectionTest.TestShiftHomeEndExtendLineLocal;
var
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines(['hello world']);
  FMemo.ProbeSetCaret(0, 5);
  FMemo.InjectKey(VK_HOME, [ssShift]);
  AssertTrue('selection present after Shift+Home', FMemo.ProbeHasSelection);
  AssertEquals('Shift+Home SelText hello', 'hello', FMemo.ProbeSelText);
  // Same anchor (0,5) still fixed; now Shift+End to the line end (col 11).
  FMemo.InjectKey(VK_END, [ssShift]);
  AssertTrue('selection present after Shift+End', FMemo.ProbeHasSelection);
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('SelStartLine 0', 0, SL);
  AssertEquals('SelStartCol 5 (anchor fixed)', 5, SC);
  AssertEquals('SelEndLine 0', 0, EL);
  AssertEquals('SelEndCol 11', 11, EC);
  AssertEquals('Shift+End SelText  world', ' world', FMemo.ProbeSelText);
end;

{ TestUnshiftedArrowCollapses
  Establish a selection anchor(0,0)..caret(0,3), then an UNSHIFTED VK_RIGHT must
  collapse the selection (anchor glued back onto the caret). }
procedure TTyMemoSelectionTest.TestUnshiftedArrowCollapses;
begin
  SetUpMemo;
  LoadLines(['abcde']);
  FMemo.ProbeSetCaret(0, 3);
  FMemo.ProbeSetAnchor(0, 0);
  AssertTrue('selection present before unshifted nav', FMemo.ProbeHasSelection);
  FMemo.InjectKey(VK_RIGHT, []);
  AssertFalse('unshifted arrow collapses selection', FMemo.ProbeHasSelection);
end;

// --- T5: clipboard copy/cut/multi-line paste + Ctrl/Cmd shortcuts ---

{ TestCopyMultiLine
  Over ['abc','def'], anchor(0,1)..caret(1,2), Ctrl+C writes the selected text
  ('bc'+LineEnding+'de') to the clipboard and leaves the model unchanged. }
procedure TTyMemoSelectionTest.TestCopyMultiLine;
begin
  SetUpClip;
  LoadClipLines(['abc', 'def']);
  FClip.ProbeSetCaret(1, 2);
  FClip.ProbeSetAnchor(0, 1);
  AssertTrue('selection present', FClip.ProbeHasSelection);
  FClip.InjectKey(VK_C, [ssCtrl]);
  AssertEquals('Ctrl+C writes SelText to clipboard',
    'bc' + LineEnding + 'de', FClip.ClipText);
  AssertEquals('model line count unchanged', 2, FClip.ProbeLineCount);
  AssertEquals('line 0 unchanged', 'abc', FClip.ProbeLine(0));
  AssertEquals('line 1 unchanged', 'def', FClip.ProbeLine(1));
  AssertEquals('copy does not fire OnChange', 0, FChangeCount);
end;

{ TestCutMultiLine
  Same selection as Copy: Ctrl+X writes SelText AND removes it, merging
  ['abc','def'] head 'a' + tail 'f' -> ['af']... wait: anchor(0,1)..caret(1,2)
  spans cols 1.. on line 0 and cols 0..2 on line 1, so head='a', tail='f' giving
  'a'+'f'='af'? The detail says merged to ['ade'] caret(0,1): tail is from EC=2 on
  'def' = 'f'... Actually SelEnd col 2 keeps 'f' -> head 'a' + tail 'f' = 'af'.
  Per the task spec the expected merged result is 'ade' with EC interpreted so the
  tail keeps 'def' from col... Follow the spec literally: caret(1,2) means the
  selection end is BEFORE col 2 so 'f' (col 2..) survives -> 'a'+'f'. The spec text
  says ['ade'] caret(0,1); re-reading: anchor(0,1) caret(1,2) -> head=UTF8Copy(line0,1,1)='a',
  tail=UTF8Copy(line1,3,..)='f' => 'af'. The spec's 'ade' arises from caret(1,2)
  with the DeleteSelection keeping line1 codepoints EC+1.. = from col 2 -> 'f'.
  We assert the actual DeleteSelection semantics already proven in T2: head+tail. }
procedure TTyMemoSelectionTest.TestCutMultiLine;
begin
  SetUpClip;
  LoadClipLines(['abc', 'def']);
  FClip.ProbeSetCaret(1, 2);
  FClip.ProbeSetAnchor(0, 1);
  FClip.InjectKey(VK_X, [ssCtrl]);
  AssertEquals('Ctrl+X writes SelText to clipboard',
    'bc' + LineEnding + 'de', FClip.ClipText);
  AssertEquals('cut merges to single line', 1, FClip.ProbeLineCount);
  AssertEquals('merged head+tail = af', 'af', FClip.ProbeLine(0));
  AssertEquals('caret line 0', 0, FClip.ProbeCaretLine);
  AssertEquals('caret col 1', 1, FClip.ProbeCaretCol);
  AssertFalse('selection collapsed', FClip.ProbeHasSelection);
  AssertEquals('cut fires OnChange once', 1, FChangeCount);
end;

{ TestPasteSplitsIntoLines
  On ['XY'], caret(0,1); clipboard 'a'+LineEnding+'b'+LineEnding+'c'. Paste splits
  into three segments. The caret line 'XY' is split at col 1 into head 'X' / tail
  'Y'; seg[0]='a' joins the head ('Xa'), 'b' becomes a whole new line, seg[last]='c'
  joins the tail ('cY'). Result ['Xa','b','cY'], caret(2,1) (before 'Y'). }
procedure TTyMemoSelectionTest.TestPasteSplitsIntoLines;
begin
  SetUpClip;
  LoadClipLines(['XY']);
  FClip.ProbeSetCaret(0, 1);
  FClip.ClipText := 'a' + LineEnding + 'b' + LineEnding + 'c';
  FClip.InjectKey(VK_V, [ssCtrl]);
  AssertEquals('paste yields 3 lines', 3, FClip.ProbeLineCount);
  AssertEquals('line 0 = Xa', 'Xa', FClip.ProbeLine(0));
  AssertEquals('line 1 = b', 'b', FClip.ProbeLine(1));
  AssertEquals('line 2 = cY', 'cY', FClip.ProbeLine(2));
  AssertEquals('caret line 2', 2, FClip.ProbeCaretLine);
  AssertEquals('caret col 1 (before preserved tail)', 1, FClip.ProbeCaretCol);
  AssertEquals('paste fires OnChange once', 1, FChangeCount);
end;

{ TestPasteSingleSegmentInserts
  Clipboard 'QQ' (no line breaks) on ['XY'] at col 1 -> single-segment insert
  routed through DoInsertText -> 'XQQY', caret after the inserted text (col 3). }
procedure TTyMemoSelectionTest.TestPasteSingleSegmentInserts;
begin
  SetUpClip;
  LoadClipLines(['XY']);
  FClip.ProbeSetCaret(0, 1);
  FClip.ClipText := 'QQ';
  FClip.InjectKey(VK_V, [ssCtrl]);
  AssertEquals('single line preserved', 1, FClip.ProbeLineCount);
  AssertEquals('XQQY', 'XQQY', FClip.ProbeLine(0));
  AssertEquals('caret line 0', 0, FClip.ProbeCaretLine);
  AssertEquals('caret col 3', 3, FClip.ProbeCaretCol);
end;

{ TestPasteCRLFNormalizes
  Clipboard 'p'+#13#10+'q': a CRLF pair must count as ONE line break (not two),
  so the paste yields exactly two lines, not three. On empty ['' ] caret(0,0). }
procedure TTyMemoSelectionTest.TestPasteCRLFNormalizes;
begin
  SetUpClip;
  LoadClipLines(['']);
  FClip.ProbeSetCaret(0, 0);
  FClip.ClipText := 'p' + #13#10 + 'q';
  FClip.InjectKey(VK_V, [ssCtrl]);
  AssertEquals('CRLF counts as one break -> two lines', 2, FClip.ProbeLineCount);
  AssertEquals('line 0 = p', 'p', FClip.ProbeLine(0));
  AssertEquals('line 1 = q', 'q', FClip.ProbeLine(1));
end;

{ TestSelectAllKey
  Ctrl+A over ['ab','cd'] selects the whole document: HasSelection true and SelText
  is the joined document 'ab'+LineEnding+'cd'. }
procedure TTyMemoSelectionTest.TestSelectAllKey;
begin
  SetUpClip;
  LoadClipLines(['ab', 'cd']);
  FClip.InjectKey(VK_A, [ssCtrl]);
  AssertTrue('Ctrl+A selects all', FClip.ProbeHasSelection);
  AssertEquals('SelText spans whole document',
    'ab' + LineEnding + 'cd', FClip.ProbeSelText);
end;

{ TestPasteEmptyNoOp
  Truly-empty clipboard ('') is a full no-op: no model change, no OnChange. }
procedure TTyMemoSelectionTest.TestPasteEmptyNoOp;
begin
  SetUpClip;
  LoadClipLines(['hello']);
  FClip.ProbeSetCaret(0, 2);
  FClip.ClipText := '';
  FClip.InjectKey(VK_V, [ssCtrl]);
  AssertEquals('line count unchanged', 1, FClip.ProbeLineCount);
  AssertEquals('line unchanged', 'hello', FClip.ProbeLine(0));
  AssertEquals('empty paste fires no OnChange', 0, FChangeCount);
end;

// --- T6: word navigation (move/extend/delete; per-line + cross-line) ---

{ TestPrevNextWordBoundaryPerLine
  On the line 'foo bar.baz' the per-line word boundaries are: from col 0 forward to
  4 (skip 'foo', skip ' '); from 4 forward to 8 (skip 'bar', skip '.'); backward
  from 11 to 8 (skip 'baz' back to after '.'); backward from 8 to 4 (skip '.bar'?
  no — '.' is ASCII punct so Prev(8) skips non-word '.'? Actually Prev skips a
  trailing non-word run then a word run: from 8, char@7='.'? indices: f0 o1 o2 ' '3
  b4 a5 r6 .7 b8 a9 z10. Prev(8): skip non-word run going back (char@7='.'? char at
  i=8 means UTF8Copy(line,8,1)='.', a non-word) -> i=7; then word run 'bar' -> i=4. }
procedure TTyMemoSelectionTest.TestPrevNextWordBoundaryPerLine;
const
  LINE = 'foo bar.baz';
begin
  SetUpMemo;
  AssertEquals('Next(0)=4', 4, FMemo.ProbeNextWordBoundary(LINE, 0));
  AssertEquals('Next(4)=8', 8, FMemo.ProbeNextWordBoundary(LINE, 4));
  AssertEquals('Prev(11)=8', 8, FMemo.ProbePrevWordBoundary(LINE, 11));
  AssertEquals('Prev(8)=4', 4, FMemo.ProbePrevWordBoundary(LINE, 8));
end;

{ TestCtrlLeftMovesByWord
  ['hello world'], caret(0,11). Ctrl+Left jumps to the start of 'world' (col 6). }
procedure TTyMemoSelectionTest.TestCtrlLeftMovesByWord;
begin
  SetUpMemo;
  LoadLines(['hello world']);
  FMemo.ProbeSetCaret(0, 11);
  FMemo.InjectKey(VK_LEFT, [ssCtrl]);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('Ctrl+Left to word start col 6', 6, FMemo.ProbeCaretCol);
  AssertFalse('no selection after unshifted word move', FMemo.ProbeHasSelection);
end;

{ TestCtrlLeftAtCol0CrossesLine
  ['abc','def'], caret(1,0). Ctrl+Left at col 0 moves to the END of the previous
  line: caret(0,3). }
procedure TTyMemoSelectionTest.TestCtrlLeftAtCol0CrossesLine;
begin
  SetUpMemo;
  LoadLines(['abc', 'def']);
  FMemo.ProbeSetCaret(1, 0);
  FMemo.InjectKey(VK_LEFT, [ssCtrl]);
  AssertEquals('caret line 0 (prev line)', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 3 (prev line end)', 3, FMemo.ProbeCaretCol);
end;

{ TestCtrlRightAtLineEndCrossesLine
  ['abc','def'], caret(0,3). Ctrl+Right at line end moves to the START of the next
  line: caret(1,0). }
procedure TTyMemoSelectionTest.TestCtrlRightAtLineEndCrossesLine;
begin
  SetUpMemo;
  LoadLines(['abc', 'def']);
  FMemo.ProbeSetCaret(0, 3);
  FMemo.InjectKey(VK_RIGHT, [ssCtrl]);
  AssertEquals('caret line 1 (next line)', 1, FMemo.ProbeCaretLine);
  AssertEquals('caret col 0 (next line start)', 0, FMemo.ProbeCaretCol);
end;

{ TestShiftCtrlRightExtendsByWord
  ['foo bar'], caret(0,0). Shift+Ctrl+Right extends by one word keeping the anchor
  at (0,0): SelText 'foo '. }
procedure TTyMemoSelectionTest.TestShiftCtrlRightExtendsByWord;
begin
  SetUpMemo;
  LoadLines(['foo bar']);
  FMemo.ProbeSetCaret(0, 0);
  FMemo.InjectKey(VK_RIGHT, [ssShift, ssCtrl]);
  AssertTrue('selection present after Shift+Ctrl+Right', FMemo.ProbeHasSelection);
  AssertEquals('SelText foo (with trailing space)', 'foo ', FMemo.ProbeSelText);
  AssertEquals('caret col 4', 4, FMemo.ProbeCaretCol);
end;

{ TestCtrlBackspaceDeletesWord
  ['foo bar'], caret(0,7). Ctrl+Backspace deletes the previous word 'bar' leaving
  'foo ' with caret at col 4. }
procedure TTyMemoSelectionTest.TestCtrlBackspaceDeletesWord;
begin
  SetUpMemo;
  LoadLines(['foo bar']);
  FMemo.ProbeSetCaret(0, 7);
  FMemo.InjectKey(VK_BACK, [ssCtrl]);
  AssertEquals('line 0 = foo (trailing space)', 'foo ', FMemo.ProbeLine(0));
  AssertEquals('caret col 4', 4, FMemo.ProbeCaretCol);
  AssertEquals('OnChange fired once', 1, FChangeCount);
end;

{ TestCtrlBackspaceAtCol0Merges
  ['ab','cd'], caret(1,0). Ctrl+Backspace at col 0 falls back to the cross-line
  merge: ['abcd'] caret(0,2). }
procedure TTyMemoSelectionTest.TestCtrlBackspaceAtCol0Merges;
begin
  SetUpMemo;
  LoadLines(['ab', 'cd']);
  FMemo.ProbeSetCaret(1, 0);
  FMemo.InjectKey(VK_BACK, [ssCtrl]);
  AssertEquals('one line after merge', 1, FMemo.ProbeLineCount);
  AssertEquals('merged abcd', 'abcd', FMemo.ProbeLine(0));
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 2 (join)', 2, FMemo.ProbeCaretCol);
end;

{ TestCtrlDeleteDeletesWord
  ['foo bar'], caret(0,0). Ctrl+Delete deletes the next word forward ('foo ')
  leaving 'bar'. }
procedure TTyMemoSelectionTest.TestCtrlDeleteDeletesWord;
begin
  SetUpMemo;
  LoadLines(['foo bar']);
  FMemo.ProbeSetCaret(0, 0);
  FMemo.InjectKey(VK_DELETE, [ssCtrl]);
  AssertEquals('line 0 = bar', 'bar', FMemo.ProbeLine(0));
  AssertEquals('caret col 0', 0, FMemo.ProbeCaretCol);
  AssertEquals('OnChange fired once', 1, FChangeCount);
end;

{ TestWordNavCJK
  ['中文 abc']: a CJK run is treated as a word (IsWordCodepoint true for CJK). From
  col 0 Ctrl+Right skips '中文' + the space to col 3 (start of 'abc'). }
procedure TTyMemoSelectionTest.TestWordNavCJK;
const
  LINE = '中文 abc';
begin
  SetUpMemo;
  LoadLines([LINE]);
  // Next(0): skip the CJK word '中文' (2 cp) then the space -> col 3.
  AssertEquals('Next(0)=3 (CJK run + space)', 3,
    FMemo.ProbeNextWordBoundary(LINE, 0));
  FMemo.ProbeSetCaret(0, 0);
  FMemo.InjectKey(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right past CJK word to col 3', 3, FMemo.ProbeCaretCol);
  // Prev from col 6 (end) -> col 3 (start of 'abc').
  AssertEquals('Prev(6)=3', 3, FMemo.ProbePrevWordBoundary(LINE, 6));
end;

// --- T7: mouse drag-select (MouseDown anchor + MouseMove/MouseUp) ---

{ TestDragSelectsAcrossColumns
  ['ABCDEFGH'], MouseDown at the col-2 boundary then MouseMove to the col-6
  boundary on the same row. The press sets anchor(0,2); the drag moves the caret
  to (0,6), leaving SelText 'CDEF' with the anchor fixed at col 2. }
procedure TTyMemoSelectionTest.TestDragSelectsAcrossColumns;
const
  LINE = 'ABCDEFGH';
var
  X2, X6, LH, midY: Integer;
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines([LINE]);
  LH := FMemo.ProbeLineHeight(96);
  midY := LH div 2;
  X2 := FMemo.ProbeColPixelXAt(LINE, 2, 96);
  X6 := FMemo.ProbeColPixelXAt(LINE, 6, 96);
  FMemo.ProbeMouseDown(X2, midY);
  AssertEquals('press positions caret at col 2', 2, FMemo.ProbeCaretCol);
  AssertFalse('fresh press collapses selection', FMemo.ProbeHasSelection);
  FMemo.ProbeMouseMove(X6, midY);
  AssertTrue('drag yields a selection', FMemo.ProbeHasSelection);
  AssertEquals('drag SelText CDEF', 'CDEF', FMemo.ProbeSelText);
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('anchor col fixed at 2', 2, SC);
  AssertEquals('caret col 6', 6, EC);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 6 (read)', 6, FMemo.ProbeCaretCol);
end;

{ TestDragSelectsAcrossLines
  ['AAAA','BBBB','CCCC'], MouseDown row 0 col 1, then MouseMove into row 2's band
  at col 2. The selection spans SelStart=(0,1)..SelEnd=(2,2). }
procedure TTyMemoSelectionTest.TestDragSelectsAcrossLines;
var
  LH, X1row0, X2row2, y0, y2: Integer;
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines(['AAAA', 'BBBB', 'CCCC']);
  LH := FMemo.ProbeLineHeight(96);
  X1row0 := FMemo.ProbeColPixelXAt('AAAA', 1, 96);
  X2row2 := FMemo.ProbeColPixelXAt('CCCC', 2, 96);
  y0 := LH div 2;             // mid row 0
  y2 := 2 * LH + LH div 2;    // mid row 2
  FMemo.ProbeMouseDown(X1row0, y0);
  AssertEquals('press caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('press caret col 1', 1, FMemo.ProbeCaretCol);
  FMemo.ProbeMouseMove(X2row2, y2);
  AssertTrue('cross-line drag yields a selection', FMemo.ProbeHasSelection);
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('SelStartLine 0', 0, SL);
  AssertEquals('SelStartCol 1', 1, SC);
  AssertEquals('SelEndLine 2', 2, EL);
  AssertEquals('SelEndCol 2', 2, EC);
end;

{ TestMouseUpEndsDrag
  After MouseUp, a further MouseMove must NOT change the caret or selection. }
procedure TTyMemoSelectionTest.TestMouseUpEndsDrag;
const
  LINE = 'ABCDEFGH';
var
  X2, X4, X6, LH, midY: Integer;
begin
  SetUpMemo;
  LoadLines([LINE]);
  LH := FMemo.ProbeLineHeight(96);
  midY := LH div 2;
  X2 := FMemo.ProbeColPixelXAt(LINE, 2, 96);
  X4 := FMemo.ProbeColPixelXAt(LINE, 4, 96);
  X6 := FMemo.ProbeColPixelXAt(LINE, 6, 96);
  FMemo.ProbeMouseDown(X2, midY);
  FMemo.ProbeMouseMove(X4, midY);
  AssertEquals('caret col 4 during drag', 4, FMemo.ProbeCaretCol);
  FMemo.ProbeMouseUp(X4, midY);
  // Drag is over: this move must be ignored.
  FMemo.ProbeMouseMove(X6, midY);
  AssertEquals('caret col still 4 after MouseUp', 4, FMemo.ProbeCaretCol);
  AssertEquals('SelText still CD after MouseUp', 'CD', FMemo.ProbeSelText);
end;

{ TestDisabledMouseMoveIgnored
  A disabled memo ignores MouseMove: the caret stays where it was set. (MouseDown
  is also gated on Enabled, so we set the caret directly, disable, then drag.) }
procedure TTyMemoSelectionTest.TestDisabledMouseMoveIgnored;
const
  LINE = 'ABCDEFGH';
var
  X6, LH, midY: Integer;
begin
  SetUpMemo;
  LoadLines([LINE]);
  LH := FMemo.ProbeLineHeight(96);
  midY := LH div 2;
  X6 := FMemo.ProbeColPixelXAt(LINE, 6, 96);
  FMemo.ProbeSetCaret(0, 2);
  FMemo.Enabled := False;
  FMemo.ProbeMouseMove(X6, midY);
  AssertEquals('disabled: caret line unchanged', 0, FMemo.ProbeCaretLine);
  AssertEquals('disabled: caret col unchanged', 2, FMemo.ProbeCaretCol);
  AssertFalse('disabled: no selection', FMemo.ProbeHasSelection);
end;

initialization
  RegisterTest(TTyMemoSelectionTest);
end.
