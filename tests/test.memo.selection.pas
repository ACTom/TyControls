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
  end;

  TTyMemoSelectionTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoSelProbe;
    FChangeCount: Integer;
    procedure SetUpMemo;
    procedure SetUpMemoCss(const ACss: string);
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

initialization
  RegisterTest(TTyMemoSelectionTest);
end.
