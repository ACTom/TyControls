unit test.memo.bidi;
{$mode objfpc}{$H+}

{ Bidirectional text in TTyMemo -- the caret, the hit test, the selection bands and the
  arrow keys.

  c2cfafc taught TTyPainter to lay a mixed Arabic/Latin line out in visual order and
  7fd44ec taught TTyEdit to answer every caret question from a run table instead of from a
  cumulative sum of codepoint widths. TTyMemo was left on the prefix sum, so an Arabic
  paragraph in a memo DREW right and SELECTED wrong -- the worse of the two failures,
  because the drawing is what a reviewer checks.

  WHAT MAKES THE MEMO HARDER THAN THE EDIT, and what most of the guards below are really
  about: the memo's caret is two-dimensional, and under WordWrap a logical line is cut into
  several VISUAL ROWS. Each row is DRAWN as its own string (RenderTo draws the segment
  substring, not the line), so the bidirectional algorithm runs PER ROW and a run table
  belongs to a row -- not to a line, and not to the document. Several guards exist only to
  kill the shortcut of building one table for the whole text.

  HOW THESE GUARDS AVOID BEING VACUOUS, which cost a whole build to learn: a test that
  clicks at a pixel the memo's OWN caret function named, and then asks that same function
  where the caret went, passes under any self-consistent model -- including the wrong one.
  Nine guards here were first written that way, and all nine passed against a deliberately
  stubbed prefix-sum implementation. They are now anchored to one of two things the model
  cannot fake: the RENDERED INK (InkColumns, read off the bitmap), or TTyPainter's own
  answer for the same string. Where a guard states an ordering claim it states it about a
  COLUMN sequence, which the two models disagree about outright.

  Fixtures are built from CODEPOINTS, not from Hebrew or Arabic literals in the source: the
  file stays pure ASCII so no editor or tool can mangle it, and every assertion names the
  character it is about instead of relying on the reader to recognise a glyph. HEBREW is
  used rather than Arabic because Hebrew letters do not JOIN -- each keeps its own advance
  width, so a failing assertion is about ORDER rather than about shaping. The Latin tail is
  lower-case on purpose: the selection-band read-out probes the TOP scanline of a text row,
  and a capital's ascender would put ink there and punch holes in the band.

  THE THREE-RUN FIXTURE ('ab' + two Hebrew letters + 'cd') is the one that matters. It has
  an embedded right-to-left run between two left-to-right ones, which is where a caret
  column stops having ONE screen position: the boundary between "ab" and the Hebrew run is
  shared by column 2 (after 'b') and column 4 (after the last Hebrew letter), and those are
  the two OPPOSITE ends of the Hebrew run. Every guard below that mentions a "boundary" is
  about that. }

interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, Controls, Graphics, LCLType,
  LazUTF8,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Memo;
type
  { Probe subclass: exposes the protected caret/hit-test/diagnostic surface headlessly. }
  TTyMemoBidiProbe = class(TTyMemo)
  public
    function ProbeCaretDrawXAt(ALine, ACol: Integer; AAfterPrev: Boolean;
      APPI: Integer): Integer;
    function ProbeCaretDrawX(APPI: Integer): Integer;
    function ProbeUsesBidiCaret(APPI: Integer): Boolean;
    function ProbeGateCalls: Integer;
    function ProbeRowLookups: Integer;
    function ProbeLayoutBuilds: Integer;
    function ProbeCaretLine: Integer;
    function ProbeCaretCol: Integer;
    procedure ProbeSetCaret(ALine, ACol: Integer);
    procedure ProbeSetAnchor(ALine, ACol: Integer);
    function ProbeSelText: string;
    function ProbeHasSelection: Boolean;
    procedure ProbeSelEnd(out EL, EC: Integer);
    procedure ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure ProbeMouseDown(X, Y: Integer);
    procedure ProbeMouseMove(X, Y: Integer);
    procedure ProbeMouseUp(X, Y: Integer);
    procedure ProbeKey(AKey: Word; AShift: TShiftState);
    procedure ProbeChar(const AChar: string);
    procedure ProbeSetWordWrap(AValue: Boolean);
    function ProbeLineHeight(APPI: Integer): Integer;
    function ProbeTextStartX(APPI: Integer): Integer;
    function ProbeBuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
    function ProbeContentWidth(APPI: Integer): Integer;
    function ProbeStyleFontName: string;
    function ProbeStyleFontSize: Integer;
    function ProbeStyleFontWeight: Integer;
  end;

  TMemoBidiTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoBidiProbe;
    { A memo themed so the selection band can be read out of the rendered pixels: white
      field, black glyphs, opaque blue band. }
    procedure MakeMemo;
    procedure LoadLines(const AItems: array of string);
    { Render FMemo and report, for each device x, whether the selection band covers it on
      visual row ARow. The probe scanline is the TOP of the cell, which the fixtures'
      glyphs leave blank; the helper asserts that for itself so a font change cannot make
      the read-out quietly lie. }
    procedure BandColumns(ARow: Integer; out ABand: array of Boolean);
    { Render FMemo and report, for each device x, whether visual row ARow has glyph INK
      there -- read on a scanline through the middle of the glyph bodies. This is the one
      read-out that does not go through the caret model at all, so it is what the guards
      that must be able to fail against a self-consistent WRONG model are anchored to. }
    procedure InkColumns(ARow: Integer; out AInk: array of Boolean);
    function BandRunCount(const A: array of Boolean): Integer;
    function FirstTrue(const A: array of Boolean): Integer;
    function LastTrue(const A: array of Boolean): Integer;
  protected
    procedure TearDown; override;
  published
    { --- the caret --- }
    procedure CaretWalksLeftwardThroughARightToLeftRun;
    procedure CaretForTheLastCodepointOfARightToLeftLineSitsLeftOfTheFirst;
    procedure BothSidesOfADirectionBoundaryAreReachable;
    procedure EachLineIsReorderedOnItsOwn;
    { --- the hit test --- }
    procedure ClickingTheLeftEdgeOfTheInkLandsOnTheLeftmostGlyph;
    procedure ClickingAGlyphPutsTheCaretAgainstThatGlyph;
    procedure DragFromTheInkLeftEdgeSelectsTheGlyphsItPassedOver;
    { --- the selection --- }
    procedure SelectionAcrossADirectionBoundaryIsTwoBandsNotOne;
    procedure SelectingARightToLeftRunBandsTheGlyphsOnTheRight;
    { --- the keyboard --- }
    procedure RightArrowWalksFromTheVisualLeftEndToTheVisualRightEnd;
    procedure LeftArrowWalksFromTheVisualRightEndToTheVisualLeftEnd;
    procedure ARightwardWalkStepsBackwardThroughAReorderedRun;
    procedure ArrowKeysCrossLinesAtTheVisualEdgeNotTheStringEnd;
    procedure ArrowKeysCrossIntoAReorderedRowAtItsVisualEdge;
    procedure HomeAndEndStayLogicalNotVisual;
    procedure UpAndDownKeepTheCaretUnderTheSameScreenColumn;
    procedure TypingParksTheCaretAfterWhatWasTyped;
    procedure ProgrammaticCaretWriteParksTheAffinity;
    { --- word wrap: the half the edit never had --- }
    procedure AWrappedParagraphResolvesEachVisualRowOnItsOwn;
    procedure ClickingAWrappedContinuationRowLandsOnThatRow;
    procedure WordWrapStillBreaksOnCJKCodepoints;
    procedure ALeftToRightRowInsideARightToLeftParagraphUsesThePrefixSum;
    procedure HorizontalScrollFollowsTheDrawnCaretNotTheStringOrder;
    { --- what must NOT change --- }
    procedure LeftToRightCaretGeometryIsExactlyThePrefixSum;
    procedure ChangingTheTextEntersAndLeavesTheBidiPath;
    procedure AThousandLeftToRightLinesCostTheSameGateAsOne;
    procedure TheGateCostsFarLessThanTheCaretQueryItGuards;
    { --- the memo and the painter must not drift apart --- }
    procedure MemoCaretAgreesWithThePainterForUnambiguousIndices;
  end;

implementation

const
  { Hebrew ALEF and BET: right-to-left, and NON-joining, so each keeps its own advance. }
  cpALEF = $05D0;
  cpBET  = $05D1;
  { CJK: a codepoint word wrap must be allowed to break BEFORE, even though there is no
    space anywhere in a Chinese paragraph. }
  cpCJK1 = $4E2D;
  cpCJK2 = $6587;

  cW = 260;   // memo width, device px
  cH = 90;    // four text rows at font-size 16
  cPad = 4;   // padding in the fixture stylesheet
  cCss = 'TyMemo { background:#FFFFFF; color:#000000; padding:4px; font-size:16px; }'
       + ' TyTextSelection { background:#0000FF; }';

function Cp(const ACodepoints: array of LongWord): string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(ACodepoints) to High(ACodepoints) do
    Result := Result + UnicodeToUTF8(ACodepoints[i]);
end;

{ "<alef><bet>w": a right-to-left paragraph with a Latin tail. Display order is
  [w][bet][alef] -- the LAST codepoint is the LEFTMOST glyph. }
function TextRtlThenLatin: string;
begin
  Result := Cp([cpALEF, cpBET]) + 'w';
end;

{ "ab<alef><bet>cd": a left-to-right paragraph with an embedded right-to-left run.
  Display order is [a][b][bet][alef][c][d] -- columns 2 and 3 swap places. }
function TextEmbeddedRtl: string;
begin
  Result := 'ab' + Cp([cpALEF, cpBET]) + 'cd';
end;

{ A right-to-left paragraph long enough to need more than one visual row at the fixture's
  content width, with spaces so the wrap has word boundaries to break at. }
function TextRtlParagraph: string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to 8 do
  begin
    if i > 1 then Result := Result + ' ';
    Result := Result + Cp([cpALEF, cpBET, cpBET, cpALEF, cpBET]);
  end;
end;

{ TTyMemoBidiProbe }

function TTyMemoBidiProbe.ProbeCaretDrawXAt(ALine, ACol: Integer; AAfterPrev: Boolean;
  APPI: Integer): Integer;
begin
  Result := CaretDrawXAt(ALine, ACol, AAfterPrev, APPI);
end;

function TTyMemoBidiProbe.ProbeCaretDrawX(APPI: Integer): Integer;
begin
  Result := CaretDrawX(APPI);
end;

function TTyMemoBidiProbe.ProbeUsesBidiCaret(APPI: Integer): Boolean;
begin
  Result := UsesBidiCaret(APPI);
end;

function TTyMemoBidiProbe.ProbeGateCalls: Integer;
begin
  Result := FBidiGateCalls;
end;

function TTyMemoBidiProbe.ProbeRowLookups: Integer;
begin
  Result := FBidiRowLookups;
end;

function TTyMemoBidiProbe.ProbeLayoutBuilds: Integer;
begin
  Result := FBidiLayoutBuilds;
end;

function TTyMemoBidiProbe.ProbeCaretLine: Integer;
begin
  Result := CaretLine;
end;

function TTyMemoBidiProbe.ProbeCaretCol: Integer;
begin
  Result := CaretCol;
end;

procedure TTyMemoBidiProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

procedure TTyMemoBidiProbe.ProbeSetAnchor(ALine, ACol: Integer);
begin
  SetSelAnchor(ALine, ACol);
end;

function TTyMemoBidiProbe.ProbeSelText: string;
begin
  Result := GetSelText;
end;

function TTyMemoBidiProbe.ProbeHasSelection: Boolean;
begin
  Result := HasSelection;
end;

procedure TTyMemoBidiProbe.ProbeSelEnd(out EL, EC: Integer);
begin
  EL := SelEndLine;
  EC := SelEndCol;
end;

procedure TTyMemoBidiProbe.ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyMemoBidiProbe.ProbeMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TTyMemoBidiProbe.ProbeMouseMove(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TTyMemoBidiProbe.ProbeMouseUp(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TTyMemoBidiProbe.ProbeKey(AKey: Word; AShift: TShiftState);
begin
  InjectKey(AKey, AShift);
end;

procedure TTyMemoBidiProbe.ProbeChar(const AChar: string);
begin
  InjectChar(AChar);
end;

procedure TTyMemoBidiProbe.ProbeSetWordWrap(AValue: Boolean);
begin
  WordWrap := AValue;
end;

function TTyMemoBidiProbe.ProbeLineHeight(APPI: Integer): Integer;
begin
  Result := LineHeight(APPI);
end;

function TTyMemoBidiProbe.ProbeTextStartX(APPI: Integer): Integer;
begin
  Result := TextStartX(APPI);
end;

function TTyMemoBidiProbe.ProbeBuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
begin
  Result := BuildVisualRows(AContentWidth, APPI);
end;

function TTyMemoBidiProbe.ProbeContentWidth(APPI: Integer): Integer;
begin
  Result := ContentWidthFor(APPI);
end;

function TTyMemoBidiProbe.ProbeStyleFontName: string;
begin
  Result := CurrentStyle.FontName;
end;

function TTyMemoBidiProbe.ProbeStyleFontSize: Integer;
begin
  Result := EffectiveFontSize(CurrentStyle);
end;

function TTyMemoBidiProbe.ProbeStyleFontWeight: Integer;
begin
  Result := CurrentStyle.FontWeight;
end;

{ TMemoBidiTest }

procedure TMemoBidiTest.MakeMemo;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(cCss);
  FMemo := TTyMemoBidiProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, cW, cH);
  FMemo.HideSelection := False;   // a headless control is never Focused
end;

procedure TMemoBidiTest.LoadLines(const AItems: array of string);
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

procedure TMemoBidiTest.TearDown;
begin
  FreeAndNil(FMemo);
  FreeAndNil(FCtl);
end;

procedure TMemoBidiTest.BandColumns(ARow: Integer; out ABand: array of Boolean);
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  x, y, ink: Integer;
begin
  { The probe scanline is the TOP row of the cell. Text is drawn tlTop, so the only thing
    that can be there is an ascender -- and the fixtures deliberately have none. }
  y := cPad + ARow * FMemo.ProbeLineHeight(96);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(cW, cH);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, cW, cH);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, cW, cH), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      ink := 0;
      for x := 0 to cW - 1 do
      begin
        Px := Reread.GetPixel(x, y);
        ABand[x] := (Px.blue > Px.red + 60) and (Px.blue > Px.green + 60);
        if (Px.red < 200) and (Px.green < 200) and (Px.blue < 200) then Inc(ink);
      end;
      { Self-check: black glyph ink on the probe scanline would punch holes in the band and
        make every count below meaningless. If a font ever puts ink here, this fails loudly
        instead of quietly reporting the wrong number of bands. }
      AssertEquals('the band probe scanline must carry no glyph ink (row ' + IntToStr(ARow)
        + ', y=' + IntToStr(y) + ')', 0, ink);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TMemoBidiTest.InkColumns(ARow: Integer; out AInk: array of Boolean);
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  x, y: Integer;
begin
  { Halfway down the cell: through the body of every glyph in these fixtures, and clear of
    the ascender line the band probe uses. }
  y := cPad + ARow * FMemo.ProbeLineHeight(96) + FMemo.ProbeLineHeight(96) div 2;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(cW, cH);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, cW, cH);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, cW, cH), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      for x := 0 to cW - 1 do
      begin
        Px := Reread.GetPixel(x, y);
        { 230, not 160. The Hebrew letters have thick vertical stems and come out solid,
          but a lower-case Latin 'w' is two thin diagonals that BGRA antialiases to about
          170-200 grey at this size -- so a stricter threshold reported the Latin tail as
          BLANK and every 'where does the ink start' assertion built on it silently measured
          the Hebrew instead. The background is pure white (255), so 230 still separates ink
          from field with room to spare. }
        AInk[x] := (Px.red < 230) and (Px.green < 230) and (Px.blue < 230);
      end;
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

function TMemoBidiTest.BandRunCount(const A: array of Boolean): Integer;
var
  x: Integer;
  inRun: Boolean;
begin
  Result := 0;
  inRun := False;
  for x := Low(A) to High(A) do
    if A[x] then
    begin
      if not inRun then
      begin
        Inc(Result);
        inRun := True;
      end;
    end
    else
      inRun := False;
end;

function TMemoBidiTest.FirstTrue(const A: array of Boolean): Integer;
var
  x: Integer;
begin
  for x := Low(A) to High(A) do
    if A[x] then Exit(x);
  Result := -1;
end;

function TMemoBidiTest.LastTrue(const A: array of Boolean): Integer;
var
  x: Integer;
begin
  for x := High(A) downto Low(A) do
    if A[x] then Exit(x);
  Result := -1;
end;

{ --- the caret ------------------------------------------------------------------------ }

{ Inside a right-to-left run the caret ADVANCES LEFTWARDS. The prefix sum, which adds each
  codepoint's width to a running total, can only ever move it rightwards -- so this is the
  defect stated in one line. }
procedure TMemoBidiTest.CaretWalksLeftwardThroughARightToLeftRun;
var
  x0, x1, x2: Integer;
begin
  MakeMemo;
  LoadLines([TextRtlThenLatin]);
  { Columns: 0 = alef, 1 = bet, 2 = 'w'. 0..2 walk the Hebrew run. }
  x0 := FMemo.ProbeCaretDrawXAt(0, 0, False, 96);
  x1 := FMemo.ProbeCaretDrawXAt(0, 1, True, 96);
  x2 := FMemo.ProbeCaretDrawXAt(0, 2, True, 96);
  AssertTrue('the caret before the first Hebrew letter must sit RIGHT of the caret after '
    + 'it (x0=' + IntToStr(x0) + ', x1=' + IntToStr(x1) + ')', x0 > x1);
  AssertTrue('and the caret after the second Hebrew letter further left still (x1='
    + IntToStr(x1) + ', x2=' + IntToStr(x2) + ')', x1 > x2);
end;

{ The whole-line version of the same claim. }
procedure TMemoBidiTest.CaretForTheLastCodepointOfARightToLeftLineSitsLeftOfTheFirst;
var
  xFirst, xLast: Integer;
begin
  MakeMemo;
  LoadLines([TextRtlThenLatin]);
  xFirst := FMemo.ProbeCaretDrawXAt(0, 0, False, 96);
  xLast := FMemo.ProbeCaretDrawXAt(0, 3, True, 96);
  AssertTrue('caret(0)=' + IntToStr(xFirst) + ' must be right of caret(3)='
    + IntToStr(xLast), xFirst > xLast);
end;

{ A column stops having ONE screen position at a direction boundary, and BOTH positions
  have to be reachable. BGRA's own GetCaret resolves such an index towards the run that
  ENDS there and discards the other, which on this fixture makes columns 2 and 4 the same
  pixel and leaves the far end of the Hebrew run unreachable by any column at all. }
procedure TMemoBidiTest.BothSidesOfADirectionBoundaryAreReachable;
var
  lead2, trail2, lead4, trail4: Integer;
begin
  MakeMemo;
  LoadLines([TextEmbeddedRtl]);
  trail2 := FMemo.ProbeCaretDrawXAt(0, 2, True, 96);    // against the 'b'
  lead2  := FMemo.ProbeCaretDrawXAt(0, 2, False, 96);   // against the first Hebrew letter
  trail4 := FMemo.ProbeCaretDrawXAt(0, 4, True, 96);    // against the last Hebrew letter
  lead4  := FMemo.ProbeCaretDrawXAt(0, 4, False, 96);   // against the 'c'
  AssertTrue('boundary 2 must have two distinct sides (trail=' + IntToStr(trail2)
    + ', lead=' + IntToStr(lead2) + ')', trail2 <> lead2);
  AssertTrue('boundary 4 must have two distinct sides (trail=' + IntToStr(trail4)
    + ', lead=' + IntToStr(lead4) + ')', trail4 <> lead4);
  { The two boundaries share their two x values, and WHICH pairs with which is the part
    worth writing down. The Hebrew run is drawn between "ab" and "cd"; its LEFT edge is both
    "after the b" (trail2, in the Latin run) and "after the last Hebrew letter" (trail4,
    which is the right-to-left run's logical END and therefore its left edge). Its RIGHT edge
    is both "before the first Hebrew letter" (lead2, the run's logical START) and "before
    the c" (lead4). So the two TRAILING sides coincide and the two LEADING sides coincide --
    not, as this guard first claimed, trailing with leading. }
  AssertEquals('the run''s LEFT edge is reached from either side of it', trail2, trail4);
  AssertEquals('and its RIGHT edge likewise', lead2, lead4);
  AssertTrue('and the left edge really is left of the right edge', trail2 < lead2);
end;

{ A run table belongs to a ROW, not to the document. A memo whose second line is Hebrew and
  whose first is Latin must reorder the second and leave the first alone -- one table for
  the whole text (or a table built from the wrong line) gets one of the two wrong. }
procedure TMemoBidiTest.EachLineIsReorderedOnItsOwn;
var
  a0, a1, b0, b1: Integer;
begin
  MakeMemo;
  LoadLines(['abc', TextRtlThenLatin]);
  a0 := FMemo.ProbeCaretDrawXAt(0, 0, False, 96);
  a1 := FMemo.ProbeCaretDrawXAt(0, 3, True, 96);
  b0 := FMemo.ProbeCaretDrawXAt(1, 0, False, 96);
  b1 := FMemo.ProbeCaretDrawXAt(1, 3, True, 96);
  AssertTrue('the Latin line still runs left to right (' + IntToStr(a0) + ' < '
    + IntToStr(a1) + ')', a0 < a1);
  AssertTrue('the Hebrew line runs right to left (' + IntToStr(b0) + ' > '
    + IntToStr(b1) + ')', b0 > b1);
end;

{ --- the hit test --------------------------------------------------------------------- }

{ THE BUG, stated against the pixels and nothing else. In "<alef><bet>w" the Latin 'w' is
  the LEFTMOST glyph, so a click on the left edge of the INK must land on the LAST
  codepoints. The click x comes from the rendered bitmap, not from the memo's own caret
  function, so a self-consistent prefix-sum model cannot satisfy it: that model answers
  column 0, which is drawn at the far RIGHT.

  Aimed at the ink's left EDGE rather than at the middle of a glyph, because every drift
  this library has actually shipped shows up at an edge and cancels out at a centre. }
procedure TMemoBidiTest.ClickingTheLeftEdgeOfTheInkLandsOnTheLeftmostGlyph;
var
  ink: array[0 .. cW - 1] of Boolean;
  midY, xLeft: Integer;
begin
  MakeMemo;
  LoadLines([TextRtlThenLatin]);
  InkColumns(0, ink);
  xLeft := FirstTrue(ink);
  AssertTrue('the fixture must have drawn some ink', xLeft >= 0);
  midY := cPad + FMemo.ProbeLineHeight(96) div 2;
  FMemo.ProbeMouseDown(xLeft + 1, midY);
  FMemo.ProbeMouseUp(xLeft + 1, midY);
  AssertTrue('a click on the LEFT EDGE OF THE INK of a right-to-left line must land on '
    + 'the last codepoints -- the leftmost glyph there is the Latin tail, not the first '
    + 'Hebrew letter (got column ' + IntToStr(FMemo.ProbeCaretCol) + ')',
    FMemo.ProbeCaretCol >= 2);
end;

{ Consistency, exhaustively: click every caret boundary on both of its sides and require
  the caret to come back on the pixel that was clicked. On its own this passes under any
  self-consistent model; it earns its place because CaretDrawXAt is pinned to the PAINTER
  by MemoCaretAgreesWithThePainterForUnambiguousIndices, so "self-consistent" here means
  "consistent with what was drawn". The ink-anchored assertion at the end is what makes it
  able to fail on its own. }
procedure TMemoBidiTest.ClickingAGlyphPutsTheCaretAgainstThatGlyph;
var
  txt: string;
  ink: array[0 .. cW - 1] of Boolean;
  i, midY, x, got, xLeft: Integer;
begin
  MakeMemo;
  txt := TextEmbeddedRtl;
  LoadLines([txt]);
  midY := cPad + FMemo.ProbeLineHeight(96) div 2;
  for i := 0 to UTF8Length(txt) do
  begin
    x := FMemo.ProbeCaretDrawXAt(0, i, True, 96);
    FMemo.ProbeMouseDown(x, midY);
    FMemo.ProbeMouseUp(x, midY);
    got := FMemo.ProbeCaretDrawX(96);
    AssertEquals('a click at the trailing side of column ' + IntToStr(i)
      + ' must put the caret there', x, got);

    x := FMemo.ProbeCaretDrawXAt(0, i, False, 96);
    FMemo.ProbeMouseDown(x, midY);
    FMemo.ProbeMouseUp(x, midY);
    got := FMemo.ProbeCaretDrawX(96);
    AssertEquals('a click at the leading side of column ' + IntToStr(i)
      + ' must put the caret there', x, got);
  end;

  { The ink anchor. In "<alef><bet>w" the paragraph reads right to left, so the Hebrew word
    goes at the RIGHT and the Latin tail to its LEFT: the display is [w][bet][alef]. The
    leftmost caret position is therefore the LEFT edge of the 'w', which is column 2 -- the
    logical START of the Latin run, not the end of the line. (Column 3, the 'w' right edge,
    sits in the middle of the ink, against the Hebrew.) A prefix-sum hit test answers column
    0 or 1 here, which is drawn at the far right. }
  LoadLines([TextRtlThenLatin]);
  InkColumns(0, ink);
  xLeft := FirstTrue(ink);
  AssertTrue('the fixture must have drawn some ink', xLeft >= 0);
  FMemo.ProbeMouseDown(xLeft - 1, midY);
  FMemo.ProbeMouseUp(xLeft - 1, midY);
  AssertEquals('a click left of ALL the ink lands on the left edge of the LATIN tail, '
    + 'which is where the leftmost glyph of a right-to-left paragraph is',
    2, FMemo.ProbeCaretCol);
end;

{ A drag reports the LOGICAL range between where it started and where it ended, and on
  reordered text that is NOT the same set as "every glyph the pointer swept over". Sweeping
  the whole of "<alef><bet>w" left to right starts at the left edge of the 'w' (column 2,
  the Latin run's logical START, which the right-to-left paragraph puts leftmost) and ends
  at the right edge of the Hebrew (column 0), so the range is columns 0..2 -- the two Hebrew
  letters, and NOT the 'w' the pointer crossed first. That is what every other editor does,
  and it is exactly why multi-band selection has to exist: the highlight goes where the
  selected CODEPOINTS are, which is not one rectangle.

  Anchored to the ink at BOTH ends, which is what makes it able to fail: the prefix-sum
  model reads those same two pixels as columns 0 and 3 and selects the entire line. }
procedure TMemoBidiTest.DragFromTheInkLeftEdgeSelectsTheGlyphsItPassedOver;
var
  ink: array[0 .. cW - 1] of Boolean;
  midY, xLeft, xRight: Integer;
begin
  MakeMemo;
  LoadLines([TextRtlThenLatin]);
  InkColumns(0, ink);
  xLeft := FirstTrue(ink);
  xRight := LastTrue(ink);
  AssertTrue('the fixture must have drawn some ink', xLeft >= 0);
  AssertTrue('and must be wider than one pixel', xRight > xLeft + 4);
  midY := cPad + FMemo.ProbeLineHeight(96) div 2;
  FMemo.ProbeMouseDown(xLeft - 1, midY);
  FMemo.ProbeMouseMove(xRight + 1, midY);
  FMemo.ProbeMouseUp(xRight + 1, midY);
  AssertTrue('the drag must produce a selection', FMemo.ProbeHasSelection);
  AssertEquals('a sweep from the left edge of the ink to its right edge selects the range '
    + 'between the two VISUAL ends -- the Hebrew word, not the whole line',
    Cp([cpALEF, cpBET]), FMemo.ProbeSelText);
end;

{ --- the selection -------------------------------------------------------------------- }

{ A selection is a LOGICAL range, and a logical range that crosses a direction boundary is
  not one rectangle on screen. Selecting "ab" plus the FIRST Hebrew letter highlights the
  "ab" and that letter -- with the SECOND Hebrew letter, which is NOT selected, drawn in
  the gap between them. One band spanning the lot would tell the user they had selected it. }
procedure TMemoBidiTest.SelectionAcrossADirectionBoundaryIsTwoBandsNotOne;
var
  band: array[0 .. cW - 1] of Boolean;
begin
  MakeMemo;
  LoadLines([TextEmbeddedRtl]);
  FMemo.ProbeSetCaret(0, 3);       // caret after the FIRST Hebrew letter...
  FMemo.ProbeSetAnchor(0, 0);      // ...anchor at the line start: columns 0..3
  BandColumns(0, band);
  AssertEquals('a selection crossing a direction boundary must paint TWO bands',
    2, BandRunCount(band));
end;

{ Where the band SITS, anchored to the ink so the wrong model cannot satisfy it. On
  "<alef><bet>w" the two Hebrew letters are drawn to the RIGHT of the Latin 'w', so
  selecting columns 0..2 must band the right-hand part of the ink and leave its left edge
  clear. The prefix sum bands the left-hand part -- exactly inverted. }
procedure TMemoBidiTest.SelectingARightToLeftRunBandsTheGlyphsOnTheRight;
var
  band, ink: array[0 .. cW - 1] of Boolean;
  xInkLeft, xInkRight: Integer;
begin
  MakeMemo;
  LoadLines([TextRtlThenLatin]);
  InkColumns(0, ink);
  xInkLeft := FirstTrue(ink);
  xInkRight := LastTrue(ink);
  AssertTrue('the fixture must have drawn some ink', xInkLeft >= 0);

  FMemo.ProbeSetCaret(0, 2);       // the two Hebrew letters, columns 0..2
  FMemo.ProbeSetAnchor(0, 0);
  BandColumns(0, band);
  AssertEquals('an all-inside-one-run selection is ONE band', 1, BandRunCount(band));
  AssertTrue('the band must NOT start at the left edge of the ink -- the Hebrew letters '
    + 'are drawn to the RIGHT of the Latin tail (band starts ' + IntToStr(FirstTrue(band))
    + ', ink starts ' + IntToStr(xInkLeft) + ')', FirstTrue(band) > xInkLeft + 2);
  AssertTrue('...and must reach the right edge of the ink (band ends '
    + IntToStr(LastTrue(band)) + ', ink ends ' + IntToStr(xInkRight) + ')',
    LastTrue(band) >= xInkRight - 2);
end;

{ --- the keyboard --------------------------------------------------------------------- }

{ Left and Right in TEXT are VISUAL movement: the caret goes one glyph the way the key
  points, whichever direction the run under it reads. Anchored at both ends -- the walk
  STARTS at the visually leftmost caret and must FINISH at the visually rightmost one, and
  on a right-to-left line those are the logical LAST and FIRST columns. A logical walk ends
  at the opposite end from the correct one, so the endpoint assertion is the whole claim. }
procedure TMemoBidiTest.RightArrowWalksFromTheVisualLeftEndToTheVisualRightEnd;
var
  ink: array[0 .. cW - 1] of Boolean;
  i, prev, curr, midY: Integer;
begin
  MakeMemo;
  LoadLines([TextRtlThenLatin]);
  { The visual LEFT end of "<alef><bet>w" is column 2, the left edge of the Latin 'w' that
    the right-to-left paragraph puts leftmost -- reached here by CLICKING there rather than
    by naming a column, so the walk's starting point is anchored to the pixels too. }
  InkColumns(0, ink);
  AssertTrue('the fixture must have drawn some ink', FirstTrue(ink) >= 0);
  midY := cPad + FMemo.ProbeLineHeight(96) div 2;
  FMemo.ProbeMouseDown(FirstTrue(ink) - 1, midY);
  FMemo.ProbeMouseUp(FirstTrue(ink) - 1, midY);
  prev := FMemo.ProbeCaretDrawX(96);
  for i := 1 to 3 do
  begin
    FMemo.ProbeKey(VK_RIGHT, []);
    curr := FMemo.ProbeCaretDrawX(96);
    AssertTrue('step ' + IntToStr(i) + ': Right must move the caret RIGHT (from '
      + IntToStr(prev) + ' to ' + IntToStr(curr) + ')', curr > prev);
    prev := curr;
  end;
  AssertEquals('three Rights from the visual LEFT end of a right-to-left line must reach '
    + 'its visual RIGHT end, which is logical column 0', 0, FMemo.ProbeCaretCol);
end;

procedure TMemoBidiTest.LeftArrowWalksFromTheVisualRightEndToTheVisualLeftEnd;
var
  i, prev, curr: Integer;
begin
  MakeMemo;
  LoadLines([TextRtlThenLatin]);
  FMemo.ProbeSetCaret(0, 0);       // logical start == visual RIGHT end
  prev := FMemo.ProbeCaretDrawX(96);
  for i := 1 to 3 do
  begin
    FMemo.ProbeKey(VK_LEFT, []);
    curr := FMemo.ProbeCaretDrawX(96);
    AssertTrue('step ' + IntToStr(i) + ': Left must move the caret LEFT (from '
      + IntToStr(prev) + ' to ' + IntToStr(curr) + ')', curr < prev);
    prev := curr;
  end;
  AssertEquals('three Lefts from the visual RIGHT end must reach the visual LEFT end, '
    + 'which on this fixture is the left edge of the Latin tail: column 2',
    2, FMemo.ProbeCaretCol);
end;

{ The claim stated about COLUMNS, which the two models disagree about outright: a rightward
  walk across a line with an embedded right-to-left run CANNOT be strictly increasing in
  column, because inside that run one glyph to the right is one codepoint BACKWARD. Also
  requires every step to land on a distinct x -- a run-crossing rule that lands ON a shared
  edge produces a keypress that does not move the caret, and one that overshoots skips a
  glyph. }
procedure TMemoBidiTest.ARightwardWalkStepsBackwardThroughAReorderedRun;
var
  n, i, k: Integer;
  cols, xs: array of Integer;
  ascending, dup: Boolean;
begin
  MakeMemo;
  LoadLines([TextEmbeddedRtl]);
  n := UTF8Length(TextEmbeddedRtl);
  FMemo.ProbeSetCaret(0, 0);
  SetLength(cols, n + 1);
  SetLength(xs, n + 1);
  cols[0] := FMemo.ProbeCaretCol;
  xs[0] := FMemo.ProbeCaretDrawX(96);
  for i := 1 to n do
  begin
    FMemo.ProbeKey(VK_RIGHT, []);
    cols[i] := FMemo.ProbeCaretCol;
    xs[i] := FMemo.ProbeCaretDrawX(96);
  end;

  ascending := True;
  for i := 1 to n do
    if cols[i] <= cols[i - 1] then ascending := False;
  AssertFalse('a rightward walk across a reordered line cannot be strictly increasing in '
    + 'COLUMN: inside a right-to-left run a rightward keypress steps BACKWARD through the '
    + 'string. Getting the string order back means the arrows never left it.', ascending);

  dup := False;
  for i := 0 to n do
    for k := 0 to i - 1 do
      if xs[i] = xs[k] then dup := True;
  AssertFalse('every step must land on a DISTINCT glyph boundary -- a keypress that does '
    + 'not move the caret, or one that skips a glyph, shows up here', dup);
end;

{ At the VISUAL edge of a reordered line, Left/Right must leave the line -- not step to the
  logically adjacent column, which in a right-to-left run is the opposite direction. In
  "<alef><bet>w" the caret at the line's logical END (column 3) is the LEFTMOST position,
  so Left from there must go to the previous line. }
procedure TMemoBidiTest.ArrowKeysCrossLinesAtTheVisualEdgeNotTheStringEnd;
var
  ink: array[0 .. cW - 1] of Boolean;
  midY: Integer;
begin
  MakeMemo;
  LoadLines(['abc', TextRtlThenLatin]);
  { Put the caret at the Hebrew line's visual LEFT edge by clicking left of all its ink,
    which is the only way to name that position without assuming which column it is. }
  InkColumns(1, ink);
  AssertTrue('the second line must have drawn some ink', FirstTrue(ink) >= 0);
  midY := cPad + FMemo.ProbeLineHeight(96) + FMemo.ProbeLineHeight(96) div 2;
  FMemo.ProbeMouseDown(FirstTrue(ink) - 1, midY);
  FMemo.ProbeMouseUp(FirstTrue(ink) - 1, midY);
  AssertEquals('the click must have stayed on the second line', 1, FMemo.ProbeCaretLine);
  FMemo.ProbeKey(VK_LEFT, []);
  AssertEquals('Left at the visual LEFT edge of a right-to-left line leaves the line',
    0, FMemo.ProbeCaretLine);
  AssertEquals('...landing at the end of the previous line', 3, FMemo.ProbeCaretCol);
end;

{ Crossing INTO a reordered row, which is the other half of the row-crossing rule and the
  half the fixture above cannot reach: there the arrow lands on 'abc', a row with no
  reordering, so it exercises only the plain "previous line's end" branch.

  When BOTH lines read right to left, the edges swap. Leaving line 1 leftwards must land on
  line 0's visual RIGHT edge -- which for an all-right-to-left line is its LOGICAL START,
  column 0 -- and leaving line 0 rightwards must land on line 1's visual LEFT edge, its
  logical END. Getting those two round the wrong way puts the caret at the opposite end of
  the line it just entered, and a mutant that ignored the run's direction here survived the
  whole file until this existed. }
procedure TMemoBidiTest.ArrowKeysCrossIntoAReorderedRowAtItsVisualEdge;
var
  ink: array[0 .. cW - 1] of Boolean;
  heb: string;
  LH: Integer;
begin
  MakeMemo;
  heb := Cp([cpALEF, cpBET, cpBET, cpALEF, cpALEF, cpBET]);
  LoadLines([heb, heb]);
  LH := FMemo.ProbeLineHeight(96);

  { Down-left: start at the visual LEFT end of line 1 (clicked, so the position is anchored
    to the pixels) and step left out of the row. }
  InkColumns(1, ink);
  AssertTrue('line 1 must have drawn ink', FirstTrue(ink) >= 0);
  FMemo.ProbeMouseDown(FirstTrue(ink) - 1, LH + LH div 2 + cPad);
  FMemo.ProbeMouseUp(FirstTrue(ink) - 1, LH + LH div 2 + cPad);
  AssertEquals('the click must land on line 1', 1, FMemo.ProbeCaretLine);
  AssertEquals('...at its visual LEFT end, which on a right-to-left line is the logical end',
    UTF8Length(heb), FMemo.ProbeCaretCol);
  FMemo.ProbeKey(VK_LEFT, []);
  AssertEquals('Left out of line 1 lands on line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('...at line 0''s visual RIGHT edge, which on a right-to-left line is column 0',
    0, FMemo.ProbeCaretCol);

  { And back the other way: Right out of line 0's visual right edge enters line 1 at ITS
    visual left edge, which is that line's logical end. }
  FMemo.ProbeKey(VK_RIGHT, []);
  AssertEquals('Right out of line 0 lands on line 1', 1, FMemo.ProbeCaretLine);
  AssertEquals('...at line 1''s visual LEFT edge, its logical end',
    UTF8Length(heb), FMemo.ProbeCaretCol);
end;

{ Home and End are LOGICAL ends, never visual ones -- the same rule the scoping document
  gives for PageUp/PageDown. On a right-to-left line Home therefore puts the caret at the
  RIGHT of the ink, and that is correct. }
procedure TMemoBidiTest.HomeAndEndStayLogicalNotVisual;
var
  xHome, xEnd: Integer;
begin
  MakeMemo;
  LoadLines([TextRtlThenLatin]);
  FMemo.ProbeSetCaret(0, 1);
  FMemo.ProbeKey(VK_HOME, []);
  AssertEquals('Home is column 0', 0, FMemo.ProbeCaretCol);
  xHome := FMemo.ProbeCaretDrawX(96);
  FMemo.ProbeKey(VK_END, []);
  AssertEquals('End is the last column', 3, FMemo.ProbeCaretCol);
  xEnd := FMemo.ProbeCaretDrawX(96);
  AssertTrue('on a right-to-left line Home is drawn to the RIGHT of End (' + IntToStr(xHome)
    + ' > ' + IntToStr(xEnd) + ')', xHome > xEnd);
end;

{ Up/Down keep the caret under the same SCREEN column. Under the old model they restored the
  remembered logical COLUMN, and a visual column and a logical column are not the same thing
  in a reordered line -- so moving from a Latin line onto a Hebrew one jumped the caret
  clear across the ink.

  The fixture is built so the two models land at OPPOSITE ENDS: the source column is near
  the right of a Latin line, and the target line is entirely right-to-left, so the correct
  landing is a LOW column (drawn on the right) and the logical one is column 5 (drawn on
  the far left). }
procedure TMemoBidiTest.UpAndDownKeepTheCaretUnderTheSameScreenColumn;
var
  xBefore, xAfter, glyph: Integer;
begin
  MakeMemo;
  LoadLines(['abcdef', Cp([cpALEF, cpBET, cpALEF, cpBET, cpALEF, cpBET])]);
  FMemo.ProbeSetCaret(0, 5);
  xBefore := FMemo.ProbeCaretDrawX(96);
  FMemo.ProbeKey(VK_DOWN, []);
  AssertEquals('Down lands on the next line', 1, FMemo.ProbeCaretLine);
  xAfter := FMemo.ProbeCaretDrawX(96);
  glyph := FMemo.ProbeCaretDrawXAt(1, 0, False, 96) - FMemo.ProbeCaretDrawXAt(1, 1, True, 96);
  if glyph < 0 then glyph := -glyph;
  AssertTrue('the fixture needs a measurable glyph width', glyph > 2);
  AssertTrue('Down must keep the caret under the same SCREEN column (' + IntToStr(xBefore)
    + ' -> ' + IntToStr(xAfter) + ', one glyph is ' + IntToStr(glyph) + ')',
    Abs(xAfter - xBefore) <= glyph);
  AssertTrue('...which on an all-right-to-left target line is a LOW column, not the '
    + 'remembered logical column 5 (got ' + IntToStr(FMemo.ProbeCaretCol) + ')',
    FMemo.ProbeCaretCol <= 2);
end;

{ Typing parks the caret against what was just written -- an insertion point means "the
  text I just wrote ends here", and in a right-to-left run that is the run's LEFT edge. }
procedure TMemoBidiTest.TypingParksTheCaretAfterWhatWasTyped;
var
  midY, farSide: Integer;
begin
  MakeMemo;
  LoadLines([TextEmbeddedRtl]);
  midY := cPad + FMemo.ProbeLineHeight(96) div 2;
  farSide := FMemo.ProbeCaretDrawXAt(0, 2, False, 96);
  AssertTrue('the fixture must have two distinct sides to this boundary, or this guard is '
    + 'vacuous', farSide <> FMemo.ProbeCaretDrawXAt(0, 2, True, 96));
  { Put the caret on the FAR side of the boundary with a click, so the affinity is the
    non-default one before the edit. }
  FMemo.ProbeMouseDown(farSide, midY);
  FMemo.ProbeMouseUp(farSide, midY);
  AssertEquals('the click leaves the caret on the far side', farSide,
    FMemo.ProbeCaretDrawX(96));
  FMemo.ProbeChar(Cp([cpALEF]));
  AssertEquals('after typing, the caret stands against the character just written',
    FMemo.ProbeCaretDrawXAt(FMemo.ProbeCaretLine, FMemo.ProbeCaretCol, True, 96),
    FMemo.ProbeCaretDrawX(96));
end;

{ SetCaret / SelStart are LOGICAL, code-facing writes: they name a (line, column) and say
  nothing about glyphs, so a caret they place has no run to stand against and must fall back
  to the default. Without the reset the same assignment would land in two different places
  depending on what the user clicked before it. }
procedure TMemoBidiTest.ProgrammaticCaretWriteParksTheAffinity;
var
  midY, farSide: Integer;
begin
  MakeMemo;
  LoadLines([TextEmbeddedRtl]);
  midY := cPad + FMemo.ProbeLineHeight(96) div 2;
  farSide := FMemo.ProbeCaretDrawXAt(0, 2, False, 96);
  AssertTrue('the fixture must have two distinct sides to this boundary',
    farSide <> FMemo.ProbeCaretDrawXAt(0, 2, True, 96));

  FMemo.ProbeMouseDown(farSide, midY);
  FMemo.ProbeMouseUp(farSide, midY);
  AssertEquals('the click leaves the caret on the far side', farSide,
    FMemo.ProbeCaretDrawX(96));
  FMemo.ProbeSetCaret(FMemo.ProbeCaretLine, FMemo.ProbeCaretCol);
  AssertEquals('a SetCaret write must park the caret on the DEFAULT side, not the side the '
    + 'click left behind',
    FMemo.ProbeCaretDrawXAt(FMemo.ProbeCaretLine, FMemo.ProbeCaretCol, True, 96),
    FMemo.ProbeCaretDrawX(96));

  FMemo.ProbeMouseDown(farSide, midY);
  FMemo.ProbeMouseUp(farSide, midY);
  AssertEquals('the click leaves the caret on the far side again', farSide,
    FMemo.ProbeCaretDrawX(96));
  FMemo.SelStart := FMemo.SelStart;
  AssertEquals('and so must a SelStart write',
    FMemo.ProbeCaretDrawXAt(FMemo.ProbeCaretLine, FMemo.ProbeCaretCol, True, 96),
    FMemo.ProbeCaretDrawX(96));
end;

{ --- word wrap: the half the edit never had -------------------------------------------- }

{ Each visual row is DRAWN as its own string, so the bidirectional algorithm runs per ROW.
  A run table built for the whole logical line would place a continuation row's caret at
  that line's coordinates -- off to the right of the viewport -- rather than inside the row
  it is drawn in. }
procedure TMemoBidiTest.AWrappedParagraphResolvesEachVisualRowOnItsOwn;
var
  Rows: TTyVisualRowArray;
  CW, i, startX, x: Integer;
begin
  MakeMemo;
  FMemo.ProbeSetWordWrap(True);
  LoadLines([TextRtlParagraph]);
  CW := FMemo.ProbeContentWidth(96);
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('the fixture must wrap into at least two rows (' + IntToStr(Length(Rows))
    + ')', Length(Rows) >= 2);
  startX := FMemo.ProbeTextStartX(96);
  { Every caret column on the SECOND row must be drawn inside that row's width. }
  for i := Rows[1].StartCol to Rows[1].EndCol do
  begin
    x := FMemo.ProbeCaretDrawXAt(0, i, True, 96);
    AssertTrue('column ' + IntToStr(i) + ' of the continuation row is drawn at x='
      + IntToStr(x) + ', outside the row [' + IntToStr(startX) + '..'
      + IntToStr(startX + CW) + ']', (x >= startX) and (x <= startX + CW));
  end;
  { And the row must actually be REORDERED in its own frame: an early column of the row is
    drawn to the RIGHT of a late one, because the row reads right to left.

    Both columns are taken from the row's INTERIOR on purpose. Rows[1].StartCol is a
    soft-wrap boundary column, and CaretToVisual's tie-break binds such a column to the
    EARLIER row -- so asking about it measures row 0's frame, and an assertion built on it
    passes for entirely the wrong reason (it did, on the first draft of this guard). }
  AssertTrue('the fixture''s continuation row must have interior columns',
    Rows[1].EndCol > Rows[1].StartCol + 1);
  AssertTrue('the continuation row must be laid out right-to-left in its own frame: '
    + 'column ' + IntToStr(Rows[1].StartCol + 1) + ' at x='
    + IntToStr(FMemo.ProbeCaretDrawXAt(0, Rows[1].StartCol + 1, True, 96))
    + ' must be RIGHT of column ' + IntToStr(Rows[1].EndCol) + ' at x='
    + IntToStr(FMemo.ProbeCaretDrawXAt(0, Rows[1].EndCol, True, 96)),
    FMemo.ProbeCaretDrawXAt(0, Rows[1].StartCol + 1, True, 96)
      > FMemo.ProbeCaretDrawXAt(0, Rows[1].EndCol, True, 96));
end;

{ ...and the hit test has to answer in the same frame the caret is drawn in: a click on a
  continuation row must land on a column of THAT row. }
procedure TMemoBidiTest.ClickingAWrappedContinuationRowLandsOnThatRow;
var
  Rows: TTyVisualRowArray;
  CW, LH, x, y: Integer;
begin
  MakeMemo;
  FMemo.ProbeSetWordWrap(True);
  LoadLines([TextRtlParagraph]);
  CW := FMemo.ProbeContentWidth(96);
  LH := FMemo.ProbeLineHeight(96);
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('the fixture must wrap', Length(Rows) >= 2);
  AssertTrue('the fixture''s continuation row must have interior columns',
    Rows[1].EndCol > Rows[1].StartCol + 1);
  y := cPad + LH + LH div 2;                 // inside visual row 1
  { The click x is the exact caret x of one specific interior column, so the nearest
    boundary to it is that column and nothing else. Asserting only "landed somewhere in the
    row" is not enough: the hit test used to resolve a continuation row's x against the
    WHOLE LINE's widths and then clamp into the row's segment, which lands on StartCol for
    most of the row -- and "StartCol is in the row" is true. }
  x := FMemo.ProbeCaretDrawXAt(0, Rows[1].StartCol + 1, True, 96);
  FMemo.ProbeMouseDown(x, y);
  FMemo.ProbeMouseUp(x, y);
  AssertEquals('a click at the caret x of column ' + IntToStr(Rows[1].StartCol + 1)
    + ' on the continuation row must land on THAT column',
    Rows[1].StartCol + 1, FMemo.ProbeCaretCol);
end;

{ Regression guard, not a bidi guard: word wrap must keep breaking on CJK codepoints and
  not only on spaces, or a pure-Chinese paragraph becomes one long overflowing line. Row
  segmentation is on the path this commit touches, so it is pinned here. }
procedure TMemoBidiTest.WordWrapStillBreaksOnCJKCodepoints;
var
  Rows: TTyVisualRowArray;
  Line: string;
  CW, i: Integer;
begin
  MakeMemo;
  Line := '';
  for i := 1 to 40 do
    Line := Line + Cp([cpCJK1, cpCJK2]);   // 80 CJK codepoints, not one space
  FMemo.ProbeSetWordWrap(True);
  LoadLines([Line]);
  CW := FMemo.ProbeContentWidth(96);
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('a space-free Chinese paragraph must still wrap into several rows (got '
    + IntToStr(Length(Rows)) + ')', Length(Rows) >= 4);
end;

{ HORIZONTAL SCROLL -- the fourth thing the run table had to be threaded through, and the
  one where being wrong is least visible in a screenshot. With WordWrap off the memo scrolls
  to keep the CARET in view, and on a right-to-left line the caret for the logical END of
  the text is at the LEFT of the ink. Answering that with the prefix sum sends the viewport
  to the opposite end of the line: the user presses End and the text jumps away from where
  the caret now is.

  Stated as a COMPARISON between the two ends, and run on a left-to-right line as well, so
  it cannot pass by the scroll simply refusing to move: the left-to-right fixture pins the
  normal direction and the right-to-left one must come out reversed. }
procedure TMemoBidiTest.HorizontalScrollFollowsTheDrawnCaretNotTheStringOrder;
var
  i, rtlHome, rtlEnd, ltrHome, ltrEnd: Integer;
  Line: string;
begin
  MakeMemo;   // WordWrap defaults False, so the horizontal offset is live

  Line := '';
  for i := 1 to 60 do Line := Line + Cp([cpALEF, cpBET]);
  LoadLines([Line]);
  AssertTrue('the right-to-left fixture must overflow the viewport',
    FMemo.ProbeCaretDrawXAt(0, 0, False, 96) > cW);
  FMemo.ProbeSetCaret(0, 0);
  FMemo.ProbeKey(VK_END, []);
  rtlEnd := FMemo.ScrollX;
  FMemo.ProbeKey(VK_HOME, []);
  rtlHome := FMemo.ScrollX;

  Line := '';
  for i := 1 to 60 do Line := Line + 'ab';
  LoadLines([Line]);
  AssertTrue('the left-to-right fixture must overflow the viewport too',
    FMemo.ProbeCaretDrawXAt(0, 120, True, 96) > cW);
  FMemo.ProbeSetCaret(0, 0);
  FMemo.ProbeKey(VK_END, []);
  ltrEnd := FMemo.ScrollX;
  FMemo.ProbeKey(VK_HOME, []);
  ltrHome := FMemo.ScrollX;

  AssertTrue('a left-to-right line scrolls RIGHT for End and back for Home (End='
    + IntToStr(ltrEnd) + ', Home=' + IntToStr(ltrHome) + ')', ltrEnd > ltrHome);
  AssertTrue('a right-to-left line must do the OPPOSITE, because End is the LEFT edge of '
    + 'its ink: End must leave the viewport further left than Home does (End='
    + IntToStr(rtlEnd) + ', Home=' + IntToStr(rtlHome) + ')', rtlEnd < rtlHome);
end;

{ THE CONTROL'S GATE MUST BE THE PAINTER'S GATE, asked of the same string.

  TTyPainter.DrawText asks TyTextHasRTL of the very string it is about to draw and takes the
  bidirectional path only when it says yes; a row whose segment carries no right-to-left
  codepoint is drawn by the plain TextRect path. So EnsureRowBidi has to ask the SAME
  question of the SAME segment -- reading such a row's caret out of a TBidiTextLayout instead
  would be a second rasterisation of the same row, and the two round differently.

  The line gate cannot cover this, because it fires for the whole logical LINE: a wrapped
  right-to-left paragraph can perfectly well have a continuation row that is entirely Latin,
  and that row is drawn by the plain path while its line is "a right-to-left line". This is
  the only fixture in the file that reaches that combination, and a mutant that removed the
  second gate survived everything else. }
procedure TMemoBidiTest.ALeftToRightRowInsideARightToLeftParagraphUsesThePrefixSum;
var
  Rows: TTyVisualRowArray;
  bmp: TBGRABitmap;
  Line, Seg: string;
  CW, i, r, ltrRow, startX, expected, builds: Integer;
begin
  MakeMemo;
  FMemo.ProbeSetWordWrap(True);
  { A right-to-left paragraph (its first strong character is Hebrew, so the LINE gate fires)
    whose tail is a long run of Latin words -- long enough that the wrap must give at least
    one row made only of them. }
  Line := Cp([cpALEF, cpBET, cpBET, cpALEF]) + ' onetwo threefour fivesix seveneight '
        + 'nineten eleventwelve thirteen fourteen fifteen sixteen';
  LoadLines([Line]);
  AssertTrue('the fixture must trip the LINE gate', TyTextHasRTL(Line));
  CW := FMemo.ProbeContentWidth(96);
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('the fixture must wrap', Length(Rows) >= 2);

  { Find a row whose own segment carries no right-to-left codepoint. }
  ltrRow := -1;
  for r := 0 to High(Rows) do
  begin
    Seg := UTF8Copy(Line, Rows[r].StartCol + 1, Rows[r].EndCol - Rows[r].StartCol);
    if (Seg <> '') and not TyTextHasRTL(Seg) then
    begin
      ltrRow := r;
      Break;
    end;
  end;
  AssertTrue('the fixture must produce a row that is entirely left-to-right inside a '
    + 'right-to-left paragraph -- that combination is the whole point of this guard',
    ltrRow >= 0);

  Seg := UTF8Copy(Line, Rows[ltrRow].StartCol + 1,
    Rows[ltrRow].EndCol - Rows[ltrRow].StartCol);
  { Prime the row's FIRST column before counting. That column sits on a soft-wrap boundary,
    and CaretToVisual's tie-break binds such a column to the EARLIER row -- which here is a
    genuinely reordered one, so it legitimately builds a layout. Counting from before that
    call would blame this row for the previous row's work. }
  FMemo.ProbeCaretDrawXAt(0, Rows[ltrRow].StartCol, True, 96);
  builds := FMemo.ProbeLayoutBuilds;
  bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(bmp, FMemo.ProbeStyleFontName, FMemo.ProbeStyleFontSize,
      FMemo.ProbeStyleFontWeight, 96);
    startX := FMemo.ProbeTextStartX(96);
    for i := 0 to UTF8Length(Seg) do
    begin
      expected := startX + bmp.TextSize(UTF8Copy(Seg, 1, i)).cx;
      AssertEquals('column ' + IntToStr(i) + ' of an all-left-to-right row must be the '
        + 'prefix sum, because that is what the PAINTER drew it with',
        expected, FMemo.ProbeCaretDrawXAt(0, Rows[ltrRow].StartCol + i, True, 96));
    end;
    { And the equality above is NOT enough on its own, which took two rounds of mutants to
      learn: BGRA's layout reproduces the cumulative-prefix positions exactly for a string
      with no right-to-left codepoint, so a control that laid this row out bidirectionally
      anyway would satisfy every assertion above -- having rasterised the row a second time
      to get the same answer. The claim is that it never asks. }
    AssertEquals('an all-left-to-right row must not build a bidirectional layout at all, '
      + 'even inside a right-to-left paragraph: the control''s gate has to be the same '
      + 'question the painter asks, of the same string',
      builds, FMemo.ProbeLayoutBuilds);
  finally
    bmp.Free;
  end;
end;

{ --- what must NOT change -------------------------------------------------------------- }

{ Requirement one: left-to-right text does not change, in behaviour OR in cost. The
  reference is the prefix sum itself, measured here with the same BGRA engine and the same
  font the control configures.

  Paired with an assertion about WHICH PATH RAN, because the geometry alone cannot make the
  performance claim: a Latin line is ONE run and the bidirectional layout reproduces the
  prefix sum for it exactly, so a gate wedged permanently open is invisible in the output
  and shows up only in the cost. }
procedure TMemoBidiTest.LeftToRightCaretGeometryIsExactlyThePrefixSum;
const
  cText = 'Hello World 123';
var
  bmp: TBGRABitmap;
  i, expected, startX, lookups: Integer;
begin
  AssertFalse('the fixture must not trip the gate', TyTextHasRTL(cText));
  MakeMemo;
  LoadLines([cText]);
  bmp := TBGRABitmap.Create(1, 1);
  try
    AssertFalse('left-to-right text must not reach the bidirectional layout AT ALL',
      FMemo.ProbeUsesBidiCaret(96));
    TyConfigureTextFont(bmp, FMemo.ProbeStyleFontName, FMemo.ProbeStyleFontSize,
      FMemo.ProbeStyleFontWeight, 96);
    startX := FMemo.ProbeTextStartX(96);
    lookups := FMemo.ProbeRowLookups;
    for i := 0 to UTF8Length(cText) do
    begin
      expected := startX + bmp.TextSize(UTF8Copy(cText, 1, i)).cx;
      AssertEquals('caret ' + IntToStr(i) + ' of left-to-right text must be the prefix sum',
        expected, FMemo.ProbeCaretDrawXAt(0, i, True, 96));
      AssertEquals('and must not depend on which side of it the caret binds to',
        expected, FMemo.ProbeCaretDrawXAt(0, i, False, 96));
    end;
    { "AT ALL" made to mean what it says. The assertion above is about the ANSWER, and the
      answer cannot see a gate wedged open: EnsureRowBidi has a second gate of its own --
      TyTextHasRTL of the segment, which is the question the PAINTER asks -- so a broken
      line gate still returns "no reordering here", having paid a segment substring, a
      dictionary hash and a second scan to say so. Two mutants that forced the line gate
      open passed this entire file until this counter was added. }
    AssertEquals('a left-to-right caret must not reach the row-layout machinery even ONCE '
      + 'across ' + IntToStr(UTF8Length(cText) * 2 + 2) + ' queries -- the line gate is '
      + 'what stops it, and its whole purpose is the work it avoids',
      lookups, FMemo.ProbeRowLookups);
  finally
    bmp.Free;
  end;
end;

{ The gate's answer is CACHED, so the cache has to be dropped when the text changes -- and
  the failure would be silent in both directions. Asserted through the caret's ORDER rather
  than through the flag, because the order is the thing the user sees. }
procedure TMemoBidiTest.ChangingTheTextEntersAndLeavesTheBidiPath;
begin
  MakeMemo;
  LoadLines(['abcw']);
  AssertFalse('Latin: no run table', FMemo.ProbeUsesBidiCaret(96));
  AssertTrue('Latin: column 0 is drawn left of the last one',
    FMemo.ProbeCaretDrawXAt(0, 0, False, 96) < FMemo.ProbeCaretDrawXAt(0, 4, True, 96));
  LoadLines([TextRtlThenLatin]);
  AssertTrue('after Hebrew is loaded, the run table is built',
    FMemo.ProbeUsesBidiCaret(96));
  AssertTrue('...and column 0 is drawn RIGHT of the last one',
    FMemo.ProbeCaretDrawXAt(0, 0, False, 96) > FMemo.ProbeCaretDrawXAt(0, 3, True, 96));
  LoadLines(['abcw']);
  AssertFalse('and after it is replaced by Latin again, the run table is dropped',
    FMemo.ProbeUsesBidiCaret(96));
  AssertTrue('...and column 0 is left of the last one once more',
    FMemo.ProbeCaretDrawXAt(0, 0, False, 96) < FMemo.ProbeCaretDrawXAt(0, 4, True, 96));

  { And a TYPED right-to-left character enters the path, which is the route a user takes. }
  FMemo.ProbeSetCaret(0, 4);
  FMemo.ProbeChar(Cp([cpALEF]));
  AssertTrue('typing a Hebrew letter into a Latin memo builds the run table',
    FMemo.ProbeUsesBidiCaret(96));
end;

{ THE PERFORMANCE CONTRACT, and the one that decides whether this commit is shippable.

  TTyEdit holds ONE line, so "the text" and "the line" are the same thing and its gate can
  be a document-wide flag recomputed per text change. A memo's document is unbounded, and a
  per-change scan of it would put an O(document) cost on the keystroke path -- exactly the
  shape of the bug that once cost this control half a second per key. So the gate here is
  asked of ONE LINE, memoised on the line it was last asked about.

  Measured as a COUNT rather than as a clock, so the guard is deterministic: a thousand
  left-to-right lines must cost the caret the same number of gate scans as one line does. A
  document-wide gate fails this by three orders of magnitude. }
procedure TMemoBidiTest.AThousandLeftToRightLinesCostTheSameGateAsOne;
var
  i, oneLine, manyLines: Integer;
  L: TStringList;
begin
  MakeMemo;
  LoadLines(['the quick brown fox jumps over the lazy dog']);
  FMemo.ProbeSetCaret(0, 4);
  i := FMemo.ProbeGateCalls;
  FMemo.ProbeCaretDrawX(96);
  FMemo.ProbeCaretDrawX(96);
  FMemo.ProbeCaretDrawX(96);
  oneLine := FMemo.ProbeGateCalls - i;

  L := TStringList.Create;
  try
    for i := 1 to 1000 do
      L.Add('the quick brown fox jumps over the lazy dog');
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ProbeSetCaret(500, 4);
  i := FMemo.ProbeGateCalls;
  FMemo.ProbeCaretDrawX(96);
  FMemo.ProbeCaretDrawX(96);
  FMemo.ProbeCaretDrawX(96);
  manyLines := FMemo.ProbeGateCalls - i;

  AssertTrue('a thousand left-to-right lines must not cost the caret more gate scans than '
    + 'one line does (1 line: ' + IntToStr(oneLine) + ', 1000 lines: '
    + IntToStr(manyLines) + ')', manyLines <= oneLine + 1);
  AssertTrue('and repeated caret queries on an unchanged line must not rescan it '
    + '(' + IntToStr(manyLines) + ' scans for 3 queries)', manyLines <= 2);
  { And the gate must actually be GATING: no left-to-right caret query may reach the row
    layout. Counted rather than timed, so it is deterministic on a loaded machine. }
  i := FMemo.ProbeRowLookups;
  FMemo.ProbeCaretDrawX(96);
  FMemo.ProbeCaretDrawX(96);
  AssertEquals('a left-to-right caret must never enter the row-layout machinery',
    i, FMemo.ProbeRowLookups);
end;

{ The same contract measured where it is actually paid: the caret path. The gate rejects
  ASCII in one compare and CJK, Cyrillic and Greek on the lead byte without decoding, so it
  must be orders of magnitude cheaper than the query it guards. Both sides are timed so the
  assertion is a RATIO, not a wall-clock number a slower machine could fail. }
procedure TMemoBidiTest.TheGateCostsFarLessThanTheCaretQueryItGuards;
const
  cReps = 20000;
var
  i, fired, sink: Integer;
  t0, tGate, tQuery: TDateTime;
  s: string;
begin
  s := 'Customer reference 4471-A (shipped)';
  MakeMemo;
  LoadLines([s]);
  fired := 0;
  t0 := Now;
  for i := 1 to cReps do
    if TyTextHasRTL(s) then Inc(fired);
  tGate := Now - t0;
  sink := 0;
  t0 := Now;
  for i := 1 to cReps do
    Inc(sink, FMemo.ProbeCaretDrawXAt(0, i mod 30, True, 96));
  tQuery := Now - t0;
  AssertEquals('the gate must not fire on a Latin fixture', 0, fired);
  AssertTrue('the caret query must have done some work', sink > 0);
  AssertTrue('the gate must cost a small fraction of the caret query it guards (gate '
    + FormatFloat('0.000', tGate * 24 * 3600 * 1000) + 'ms, query '
    + FormatFloat('0.000', tQuery * 24 * 3600 * 1000) + 'ms over '
    + IntToStr(cReps) + ' reps)', tGate <= tQuery);
end;

{ --- the memo and the painter must not drift apart ------------------------------------- }

{ TTyMemo lays its rows out for itself rather than calling TTyPainter.TextCaretX, for the
  two structural reasons recorded in tyControls.Memo.pas: the painter's seam needs a painter
  that is MID-PAINT, and a caret is queried from mouse handlers, key handlers and the blink
  timer; and TextCaretX answers with TBidiTextLayout.GetCaret, which collapses the two sides
  of a direction boundary onto whichever run ENDS there.

  So the two compute the same thing twice, and this is what stops them drifting: for every
  column that is NOT on a run boundary the answer is unambiguous, and the control's must
  equal the painter's to the pixel. This is also the guard that gives every OTHER caret
  assertion in this file its ground truth -- without it they would only prove the memo is
  self-consistent, which the buggy model was too. }
procedure TMemoBidiTest.MemoCaretAgreesWithThePainterForUnambiguousIndices;
var
  host: TBitmap;
  P: TTyPainter;
  r: TRect;
  txt: string;
  i, startX, viaPainter, viaMemo, checked: Integer;
begin
  MakeMemo;
  txt := TextEmbeddedRtl;
  LoadLines([txt]);
  host := TBitmap.Create;
  try
    startX := FMemo.ProbeTextStartX(96);
    host.SetSize(cW, cH);
    checked := 0;
    for i := 0 to UTF8Length(txt) do
    begin
      { Boundary columns of the fixture: 0 and 6 are the ends of the line, 2 and 4 are the
        two ends of the embedded run. 1, 3 and 5 are strictly inside a run. }
      if (i = 0) or (i = 2) or (i = 4) or (i = 6) then Continue;
      P := TTyPainter.Create;
      try
        r := Rect(startX, 0, cW, cH);
        P.BeginPaint(host.Canvas, Rect(0, 0, cW, cH), 96);
        viaPainter := P.TextCaretX(r, txt, FMemo.ProbeStyleFontName,
          FMemo.ProbeStyleFontSize, FMemo.ProbeStyleFontWeight, taLeftJustify, i);
        P.EndPaint;
      finally
        P.Free;
      end;
      viaMemo := FMemo.ProbeCaretDrawXAt(0, i, True, 96);
      AssertEquals('the memo and the painter must agree about column ' + IntToStr(i),
        viaPainter, viaMemo);
      Inc(checked);
    end;
    AssertEquals('the fixture must actually have interior columns to check', 3, checked);
  finally
    host.Free;
  end;
end;

initialization
  RegisterTest(TMemoBidiTest);
end.
