unit test.edit.bidi;
{$mode objfpc}{$H+}

{ Bidirectional text in TTyEdit -- the caret, the hit test, the selection band and the
  arrow keys.

  c2cfafc taught TTyPainter to lay a mixed Arabic/Latin line out in visual order, and left
  the edits behind: TTyEdit answered "where is codepoint N" with a cumulative sum of
  codepoint widths taken in STRING order (MeasureCodepointWidths). That is exactly right
  for Latin and CJK and simply untrue once the glyphs have been reordered, so an Arabic
  field DREW right and SELECTED wrong -- which is the worse of the two failures, because
  the drawing is what a user tests with.

  Fixtures are built from CODEPOINTS, not from Hebrew or Arabic literals in the source: the
  file stays pure ASCII so no editor or tool can mangle it, and every assertion names the
  character it is about instead of relying on the reader to recognise a glyph. HEBREW is
  used rather than Arabic for the geometry assertions because Hebrew letters do not JOIN --
  each one keeps its own advance width, so a run's width is the sum of its letters and a
  failing assertion is about ORDER rather than about shaping.

  THE THREE-RUN FIXTURE ('ab' + two Hebrew letters + 'cd') is the one that matters. It has
  an embedded right-to-left run between two left-to-right ones, which is where a caret
  index stops having ONE screen position: the boundary between "ab" and the Hebrew run is
  shared by codepoint index 2 (after 'b') and index 4 (after the last Hebrew letter), and
  so is the boundary between the Hebrew run and "cd". Every guard below that mentions a
  "boundary" is about that. }

interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  LazUTF8,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Edit,
  test.edit;
type
  TEditBidiTest = class(TTestCase)
  private
    { An edit on a form, sized and themed so the selection band can be read out of the
      rendered pixels: white field, opaque blue band, and TALL enough that a row just under
      the top padding is inside the band but above the glyphs. }
    function MakeEdit(out AForm: TForm; out ACtl: TTyStyleController;
      const AText: string): TTyEditAccess;
    { Render AEdit and return, for each device x, whether the selection band covers it.
      Probed on ONE row near the top of the content rect -- the band spans the whole
      content height while the glyphs are centred in it, so that row is band-only and a
      glyph stem cannot punch a hole in the answer. }
    procedure BandColumns(AEdit: TTyEditAccess; out ABand: array of Boolean);
    { Count the maximal runs of True in ABand, and report the first run's bounds. }
    function BandRunCount(const ABand: array of Boolean; out AFirstL, AFirstR: Integer): Integer;
    { Click each caret boundary of AText, on BOTH of its sides, and require the caret to
      come back on the pixel that was clicked. Shared by the two fixtures because they fail
      differently: only the right-to-left-first one has its runs laid out in a different
      order from the order they appear in the string. }
    procedure CheckClickRoundTrip(const AText: string);
  published
    { --- the caret --- }
    procedure CaretWalksLeftwardThroughARightToLeftRun;
    procedure CaretForTheLastCodepointOfARightToLeftLineSitsLeftOfTheFirst;
    procedure BothSidesOfADirectionBoundaryAreReachable;
    { --- the hit test --- }
    procedure ClickingTheLatinTailOfARightToLeftFieldLandsOnTheLatinTail;
    procedure ClickingAGlyphPutsTheCaretAgainstThatGlyph;
    { --- the selection --- }
    procedure SelectingTheLatinTailHighlightsTheLeftmostGlyph;
    procedure SelectingARightToLeftRunHighlightsTheGlyphsOnTheRight;
    procedure SelectionAcrossADirectionBoundaryIsTwoBandsNotOne;
    { --- the keyboard --- }
    procedure RightArrowAlwaysMovesTheCaretRightOnScreen;
    procedure LeftArrowAlwaysMovesTheCaretLeftOnScreen;
    procedure ArrowKeysVisitEveryGlyphBoundaryExactlyOnce;
    procedure ArrowKeysCrossRunsInScreenOrderNotStringOrder;
    procedure HomeAndEndStayLogicalNotVisual;
    procedure TypingParksTheCaretAfterWhatWasTyped;
    procedure ProgrammaticSelectionParksTheCaretAffinity;
    { --- what must NOT change --- }
    procedure LeftToRightCaretGeometryIsExactlyThePrefixSum;
    procedure MaskedFieldsNeverReachTheBidiPath;
    procedure ChangingTheTextEntersAndLeavesTheBidiPath;
    procedure TheGateCostsFarLessThanTheCaretQueryItGuards;
    { --- the edit and the painter must not drift apart --- }
    procedure EditCaretAgreesWithThePainterForUnambiguousIndices;
  end;

implementation

const
  { Hebrew ALEF and BET: right-to-left, and NON-joining, so each keeps its own advance. }
  cpALEF = $05D0;
  cpBET  = $05D1;

function Cp(const ACodepoints: array of LongWord): string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(ACodepoints) to High(ACodepoints) do
    Result := Result + UnicodeToUTF8(ACodepoints[i]);
end;

{ "<alef><bet>W": a right-to-left paragraph with a Latin tail. Display order is
  [W][bet][alef] -- the LAST codepoint is the LEFTMOST glyph. }
function TextRtlThenLatin: string;
begin
  Result := Cp([cpALEF, cpBET]) + 'W';
end;

{ "ab<alef><bet>cd": a left-to-right paragraph with an embedded right-to-left run.
  Display order is [a][b][bet][alef][c][d] -- codepoints 2 and 3 swap places. }
function TextEmbeddedRtl: string;
begin
  Result := 'ab' + Cp([cpALEF, cpBET]) + 'cd';
end;

const
  cW = 260;   // edit width, device px
  cH = 60;    // TALL: leaves a band-only probe row above the centred glyphs
  cPad = 4;   // padding in the fixture stylesheet
  cProbeY = cPad + 2;

function TEditBidiTest.MakeEdit(out AForm: TForm; out ACtl: TTyStyleController;
  const AText: string): TTyEditAccess;
begin
  ACtl := TTyStyleController.Create(nil);
  AForm := TForm.CreateNew(nil);
  { Opaque blue band over a white field: a band pixel is unmistakable, and no alpha means
    the read-out does not depend on how the compositor rounds. }
  ACtl.LoadThemeCss(
    'TyEdit { background: #FFFFFF; color: #000000; padding: 4px; font-size: 16px; }' +
    ' TyTextSelection { background: #0000FF; }');
  Result := TTyEditAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.SetBounds(0, 0, cW, cH);
  Result.HideSelection := False;   // a headless control is never Focused
  { A click here is about WHERE the caret lands; AutoSelect would take the focus the click
    grants and select the whole field, hiding the answer behind SelectAll's caret. }
  Result.AutoSelect := False;
  Result.Text := AText;
end;

procedure TEditBidiTest.BandColumns(AEdit: TTyEditAccess; out ABand: array of Boolean);
var
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  x: Integer;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(cW, cH);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, cW, cH);
    AEdit.RenderTo(Bmp.Canvas, Rect(0, 0, cW, cH), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      for x := 0 to cW - 1 do
      begin
        Px := Reread.GetPixel(x, cProbeY);
        ABand[x] := (Px.blue > Px.red + 60) and (Px.blue > Px.green + 60);
      end;
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

function TEditBidiTest.BandRunCount(const ABand: array of Boolean;
  out AFirstL, AFirstR: Integer): Integer;
var
  x: Integer;
  inRun: Boolean;
begin
  Result := 0;
  AFirstL := -1;
  AFirstR := -1;
  inRun := False;
  for x := Low(ABand) to High(ABand) do
    if ABand[x] then
    begin
      if not inRun then
      begin
        Inc(Result);
        inRun := True;
        if AFirstL < 0 then AFirstL := x;
      end;
      if Result = 1 then AFirstR := x;
    end
    else
      inRun := False;
end;

{ --- the caret ------------------------------------------------------------------------ }

{ Inside a right-to-left run the caret ADVANCES LEFTWARDS. The prefix sum, which adds each
  codepoint's width to a running total, can only ever move it rightwards -- so this is the
  defect stated in one line. }
procedure TEditBidiTest.CaretWalksLeftwardThroughARightToLeftRun;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  x0, x1, x2: Integer;
begin
  E := MakeEdit(F, C, TextRtlThenLatin);
  try
    { Codepoints: 0 = alef, 1 = bet, 2 = 'W'. 0..2 walk the Hebrew run. }
    x0 := E.CaretDrawXAt(0, 96, False);
    x1 := E.CaretDrawXAt(1, 96, True);
    x2 := E.CaretDrawXAt(2, 96, True);
    AssertTrue('the caret before the first Hebrew letter must sit RIGHT of the caret after '
      + 'it (x0=' + IntToStr(x0) + ', x1=' + IntToStr(x1) + ')', x0 > x1);
    AssertTrue('and the caret after the second Hebrew letter further left still (x1='
      + IntToStr(x1) + ', x2=' + IntToStr(x2) + ')', x1 > x2);
  finally
    F.Free;
    C.Free;
  end;
end;

{ The whole-line version of the same claim: in a right-to-left paragraph the caret at the
  logical END of the text is at the LEFT of the ink, because the last codepoint is the
  leftmost glyph. }
procedure TEditBidiTest.CaretForTheLastCodepointOfARightToLeftLineSitsLeftOfTheFirst;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  xFirst, xLast: Integer;
begin
  E := MakeEdit(F, C, TextRtlThenLatin);
  try
    xFirst := E.CaretDrawXAt(0, 96, False);
    xLast := E.CaretDrawXAt(3, 96, True);
    AssertTrue('caret(0)=' + IntToStr(xFirst) + ' must be right of caret(3)='
      + IntToStr(xLast), xFirst > xLast);
  finally
    F.Free;
    C.Free;
  end;
end;

{ THE run-boundary guard.

  Where an embedded right-to-left run meets the left-to-right text around it, one codepoint
  index has TWO screen positions: index 2 of "ab<alef><bet>cd" is both "after the b" (the
  left end of the Hebrew run) and "before the first Hebrew letter" (its right end). BGRA's
  GetCaret resolves that ambiguity towards the run that ENDS at the index and throws the
  other position away, so a caret built naively on it can never be placed at the far side
  of an embedded run -- and index 2 and index 4 come out at the same pixel with no way to
  tell them apart.

  Both positions must therefore be reachable, and they must be the two ENDS of the Hebrew
  run: the same pair of x values for index 2 and for index 4, because that is what the
  Unicode algorithm actually says those boundaries are. }
procedure TEditBidiTest.BothSidesOfADirectionBoundaryAreReachable;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  a2, b2, a4, b4: Integer;
begin
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    a2 := E.CaretDrawXAt(2, 96, True);    // after the 'b'   -> left end of the Hebrew run
    b2 := E.CaretDrawXAt(2, 96, False);   // before the alef -> right end of the Hebrew run
    a4 := E.CaretDrawXAt(4, 96, True);    // after the bet   -> left end of the Hebrew run
    b4 := E.CaretDrawXAt(4, 96, False);   // before the 'c'  -> right end of the Hebrew run
    AssertTrue('the two sides of the boundary at index 2 must be different pixels (a2='
      + IntToStr(a2) + ', b2=' + IntToStr(b2) + ')', b2 > a2);
    AssertTrue('and so must the two sides of the boundary at index 4 (a4='
      + IntToStr(a4) + ', b4=' + IntToStr(b4) + ')', b4 > a4);
    { The embedded run has exactly two ends, and both boundary indices name them. }
    AssertEquals('index 2 and index 4 bind to the same run, so their trailing sides are '
      + 'the same end of it', a2, a4);
    AssertEquals('and so are their leading sides', b2, b4);
  finally
    F.Free;
    C.Free;
  end;
end;

{ --- the hit test --------------------------------------------------------------------- }

{ The 'W' of "<alef><bet>W" is the LEFTMOST glyph. Clicking it must select it, not the
  Hebrew letter whose logical index happens to be near zero. }
procedure TEditBidiTest.ClickingTheLatinTailOfARightToLeftFieldLandsOnTheLatinTail;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  hitLeft, hitRight, inkRight: Integer;
begin
  E := MakeEdit(F, C, TextRtlThenLatin);
  try
    { Just inside the left padding: the leading edge of the 'W', whose caret index is 2. }
    hitLeft := E.CaretIndexAtX(E.TextStartXForTest + 1);
    AssertEquals('a click on the leftmost glyph selects the Latin tail (codepoint 2)',
      2, hitLeft);
    { And the right-hand end of the ink is the FIRST codepoint. Measured at the PPI the hit
      test itself uses (Font.PixelsPerInch, which is not 96 on this box) -- comparing a
      pixel taken at one scale with a hit test performed at another is how the old
      TestHitTestRoundTrip earned its explicit PPI line. }
    inkRight := E.CaretDrawXAt(0, E.Font.PixelsPerInch, False);
    hitRight := E.CaretIndexAtX(inkRight - 1);
    AssertEquals('a click at the right end of the ink selects the first codepoint', 0,
      hitRight);
  finally
    F.Free;
    C.Free;
  end;
end;

{ "The caret lands where the user clicked", stated so that the bidirectional double-index
  cannot make it a false failure: click at the pixel the caret for boundary b is drawn at,
  and the caret that comes back must be drawn at THAT SAME PIXEL. (Asserting the index
  round-trips would be wrong here -- indices 2 and 4 of the embedded fixture share both of
  their pixels, so either answer is correct.) }
procedure TEditBidiTest.CheckClickRoundTrip(const AText: string);
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  b, n, ppi, clickX, gotX: Integer;
  side: Boolean;
begin
  E := MakeEdit(F, C, AText);
  try
    // The PPI the hit test uses internally; see the note in the test above.
    ppi := E.Font.PixelsPerInch;
    n := UTF8Length(AText);
    { Both sides of every boundary. The FAR side is the one that catches a hit test which
      reports the index and forgets which run it came from: the far end of an embedded run
      is only reachable by a caret bound to the character AFTER it, so a hit test that
      always answered "after the previous one" would send every one of these to the near
      end instead. }
    for side := False to True do
      for b := 0 to n do
      begin
        clickX := E.CaretDrawXAt(b, ppi, side);
        E.SimulateMouseDown(clickX, cH div 2);
        E.SimulateMouseUp(clickX, cH div 2);
        gotX := E.CaretDrawX(ppi);
        AssertEquals('clicking the caret pixel of boundary ' + IntToStr(b) + ' (afterPrev='
          + BoolToStr(side, True) + ') of "' + AText + '" must put the caret back on that '
          + 'pixel', clickX, gotX);
      end;
  finally
    F.Free;
    C.Free;
  end;
end;

procedure TEditBidiTest.ClickingAGlyphPutsTheCaretAgainstThatGlyph;
begin
  CheckClickRoundTrip(TextEmbeddedRtl);
  { And the fixture whose runs are NOT in string order -- the one that catches a hit test
    that walks the runs in the order they appear in the text and stops at the first whose
    right edge is past the click. On this fixture the leftmost glyph belongs to the LAST
    run, so such a walk never reaches it. }
  CheckClickRoundTrip(TextRtlThenLatin);
end;

{ --- the selection -------------------------------------------------------------------- }

{ Select ONLY the 'W' of "<alef><bet>W". It is the leftmost glyph, so the highlight belongs
  at the left of the field. The prefix sum puts it at the right, over two Hebrew letters
  the user did not select. }
procedure TEditBidiTest.SelectingTheLatinTailHighlightsTheLeftmostGlyph;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  band: array[0 .. cW - 1] of Boolean;
  runs, L, R, inkMid: Integer;
begin
  E := MakeEdit(F, C, TextRtlThenLatin);
  try
    E.SelStart := 2;
    E.SelLength := 1;
    BandColumns(E, band);
    runs := BandRunCount(band, L, R);
    AssertEquals('selecting one codepoint highlights exactly one band', 1, runs);
    { The 'W' is left of everything else on the line, so its band must end before the
      middle of the ink. Stated as a bound rather than an exact x so that a font
      substitution cannot turn a correctness guard into a metrics guard. }
    inkMid := (E.CaretDrawXAt(0, 96, False) + E.TextStartXForTest) div 2;
    AssertTrue('the highlight must sit on the LEFTMOST glyph, not after the Hebrew (band '
      + IntToStr(L) + '..' + IntToStr(R) + ', ink midpoint ' + IntToStr(inkMid) + ')',
      R <= inkMid);
  finally
    F.Free;
    C.Free;
  end;
end;

{ The counterpart, and the one that keeps the guard above from being satisfied by an edit
  that simply cannot draw a band over right-to-left glyphs at all.

  Selecting BOTH Hebrew letters of "<alef><bet>W" is a range that lies entirely inside one
  right-to-left run. Its two ends come out of the run in DESCENDING x -- the later codepoint
  is the further left -- so a band built as "start x to end x" is an empty or inverted
  rectangle and nothing is painted. The band must cover the two glyphs, and they are the two
  on the RIGHT. }
procedure TEditBidiTest.SelectingARightToLeftRunHighlightsTheGlyphsOnTheRight;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  band: array[0 .. cW - 1] of Boolean;
  runs, L, R, latinRight: Integer;
begin
  E := MakeEdit(F, C, TextRtlThenLatin);
  try
    E.SelStart := 0;
    E.SelLength := 2;
    BandColumns(E, band);
    runs := BandRunCount(band, L, R);
    AssertEquals('a selection inside one right-to-left run is one band', 1, runs);
    { The Latin tail is drawn to the LEFT of the Hebrew, and it is not selected -- so the
      band must start at or after where the Latin glyph ends. }
    latinRight := E.CaretDrawXAt(3, 96, True);
    AssertTrue('the band must cover the Hebrew, which is right of the Latin tail (band '
      + IntToStr(L) + '..' + IntToStr(R) + ', Latin ends at ' + IntToStr(latinRight) + ')',
      L >= latinRight - 1);
    AssertTrue('and it must be wide enough to be two letters', R - L > 8);
  finally
    F.Free;
    C.Free;
  end;
end;

{ A selection is a LOGICAL range, and a logical range that crosses a direction boundary is
  not one rectangle on screen.

  "ab<alef><bet>cd" displays as [a][b][bet][alef][c][d]. Selecting codepoints 0..2 -- 'a',
  'b' and the ALEF -- highlights [a][b] on the left and the ALEF further right, with the
  BET (which is NOT selected) in the gap between them. One band spanning the lot would be
  highlighting a letter the user did not select. }
procedure TEditBidiTest.SelectionAcrossADirectionBoundaryIsTwoBandsNotOne;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  band: array[0 .. cW - 1] of Boolean;
  runs, L, R: Integer;
begin
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    E.SelStart := 0;
    E.SelLength := 3;
    BandColumns(E, band);
    runs := BandRunCount(band, L, R);
    AssertEquals('a selection that crosses a direction boundary must paint the glyphs it '
      + 'covers and nothing between them', 2, runs);
  finally
    F.Free;
    C.Free;
  end;
end;

{ --- the keyboard --------------------------------------------------------------------- }

{ In TEXT, Left and Right are VISUAL movement -- one glyph in the direction pressed. That
  is the whole of the keyboard half of this job: a user pressing Right watches the caret
  move right, whatever the logical index does underneath.
  (plans/2026-08-04-rtl-mirroring-scope.md 6.3 item 4: this belongs to the BiDi layer.
  In lists, grids, tabs and menus the same keys are LAYOUT direction and belong to the
  mirroring layer, which is not built.) }
procedure TEditBidiTest.RightArrowAlwaysMovesTheCaretRightOnScreen;
const
  { The logical index after each press, walking "ab<alef><bet>cd" from codepoint 0.
    Display order is [a][b][bet][alef][c][d], so the walk crosses the Hebrew run BACKWARDS
    in logical terms: 3 (before the alef, which is drawn third) then 2 (before the bet,
    drawn fourth). A logical +1 walk would read 0,1,2,3,4,5,6 -- and its fifth stop would
    move the caret LEFT on screen, which is the defect. }
  cStops: array[0 .. 6] of Integer = (0, 1, 2, 3, 2, 5, 6);
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  i, prev, curr: Integer;
begin
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    E.SimulateKeyDown(VK_HOME);
    prev := E.CaretDrawX(96);
    AssertEquals('Home leaves the caret on codepoint 0', cStops[0], E.CaretPos);
    for i := 1 to 6 do
    begin
      E.SimulateKeyDown(VK_RIGHT);
      curr := E.CaretDrawX(96);
      AssertTrue('press ' + IntToStr(i) + ' of Right must move the caret RIGHT (from '
        + IntToStr(prev) + ' to ' + IntToStr(curr) + ')', curr > prev);
      AssertEquals('press ' + IntToStr(i) + ' of Right must cross ONE glyph, so the caret '
        + 'must land on the codepoint that glyph belongs to', cStops[i], E.CaretPos);
      prev := curr;
    end;
  finally
    F.Free;
    C.Free;
  end;
end;

procedure TEditBidiTest.LeftArrowAlwaysMovesTheCaretLeftOnScreen;
const
  { The mirror of cStops above, walking back from the logical end. }
  cStops: array[0 .. 6] of Integer = (6, 5, 4, 3, 4, 1, 0);
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  i, prev, curr: Integer;
begin
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    E.SimulateKeyDown(VK_END);
    prev := E.CaretDrawX(96);
    AssertEquals('End leaves the caret on the last codepoint', cStops[0], E.CaretPos);
    for i := 1 to 6 do
    begin
      E.SimulateKeyDown(VK_LEFT);
      curr := E.CaretDrawX(96);
      AssertTrue('press ' + IntToStr(i) + ' of Left must move the caret LEFT (from '
        + IntToStr(prev) + ' to ' + IntToStr(curr) + ')', curr < prev);
      AssertEquals('press ' + IntToStr(i) + ' of Left must cross ONE glyph, so the caret '
        + 'must land on the codepoint that glyph belongs to', cStops[i], E.CaretPos);
      prev := curr;
    end;
  finally
    F.Free;
    C.Free;
  end;
end;

{ Six presses of Right from the visual start must reach the visual end, and every stop on
  the way must be a place a glyph actually begins -- so the walk visits each of the seven
  boundary pixels once. Without this, "always moves right" could be satisfied by a caret
  that skipped a glyph and then crawled a pixel at a time. }
procedure TEditBidiTest.ArrowKeysVisitEveryGlyphBoundaryExactlyOnce;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  i, j: Integer;
  fwd: array[0 .. 6] of Integer;
  back: array[0 .. 6] of Integer;
begin
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    E.SimulateKeyDown(VK_HOME);
    fwd[0] := E.CaretDrawX(96);
    for i := 1 to 6 do
    begin
      E.SimulateKeyDown(VK_RIGHT);
      fwd[i] := E.CaretDrawX(96);
    end;
    { A seventh press has nowhere to go. }
    E.SimulateKeyDown(VK_RIGHT);
    AssertEquals('a Right press at the visual end of the line must not move the caret',
      fwd[6], E.CaretDrawX(96));

    E.SimulateKeyDown(VK_END);
    back[6] := E.CaretDrawX(96);
    for i := 5 downto 0 do
    begin
      E.SimulateKeyDown(VK_LEFT);
      back[i] := E.CaretDrawX(96);
    end;
    E.SimulateKeyDown(VK_LEFT);
    AssertEquals('a Left press at the visual start of the line must not move the caret',
      back[0], E.CaretDrawX(96));

    { Walking back must retrace the same seven pixels. A caret that took a different route
      home is one whose two directions disagree about where the glyph boundaries are. }
    for j := 0 to 6 do
      AssertEquals('stop ' + IntToStr(j) + ' must be the same pixel walking either way',
        fwd[j], back[j]);

    { And the stops are the GLYPH boundaries, not the logical ones. The fifth stop is the
      far end of the embedded Hebrew run -- the side codepoint 2 faces when the caret binds
      to the character AFTER it. A logical +1 walk puts its fifth stop at the prefix width
      of four codepoints instead, which is a different pixel entirely. }
    AssertEquals('the fifth stop must be the far end of the embedded run',
      E.CaretDrawXAt(2, 96, False), fwd[4]);
  finally
    F.Free;
    C.Free;
  end;
end;

{ "The next glyph to the right" lives in the next run ALONG THE SCREEN, which is not the next
  run in the string.

  The embedded fixture cannot tell those two apart -- its three runs happen to be laid out in
  the same order they appear in the text -- so this uses "<alef><bet>W" instead, where they
  disagree: the Latin run is codepoints 2..3, the LAST of the two runs in string order and
  the LEFTMOST on screen. Walking right from the left edge therefore has to go from the
  SECOND run to the FIRST. A walk that stepped through the runs in string order would find
  nothing to the right of the Latin run and stop dead after one press. }
procedure TEditBidiTest.ArrowKeysCrossRunsInScreenOrderNotStringOrder;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  i, ppi, prev, curr: Integer;
  seen: array[0 .. 3] of Integer;
begin
  E := MakeEdit(F, C, TextRtlThenLatin);
  try
    ppi := E.Font.PixelsPerInch;
    { Start at the visual LEFT edge. Home would not do: it goes to codepoint 0, which in a
      right-to-left paragraph is the far right. }
    E.SimulateMouseDown(E.TextStartXForTest, cH div 2);
    E.SimulateMouseUp(E.TextStartXForTest, cH div 2);
    AssertEquals('the leftmost glyph is the Latin tail, codepoint 2', 2, E.CaretPos);
    prev := E.CaretDrawX(ppi);
    seen[0] := prev;
    for i := 1 to 3 do
    begin
      E.SimulateKeyDown(VK_RIGHT);
      curr := E.CaretDrawX(ppi);
      AssertTrue('press ' + IntToStr(i) + ' of Right must move the caret RIGHT, across the '
        + 'run boundary as well as inside a run (from ' + IntToStr(prev) + ' to '
        + IntToStr(curr) + ')', curr > prev);
      seen[i] := curr;
      prev := curr;
    end;
    { Three presses walk the whole line: the Latin glyph, then both Hebrew letters. The last
      stop is codepoint 0 -- the first character of the string, drawn at the far right. }
    AssertEquals('the walk ends on the codepoint drawn furthest right', 0, E.CaretPos);
    E.SimulateKeyDown(VK_RIGHT);
    AssertEquals('and a fourth press has nowhere to go', seen[3], E.CaretDrawX(ppi));
  finally
    F.Free;
    C.Free;
  end;
end;

{ Home and End are LOGICAL, not visual: they go to codepoint 0 and to the last codepoint,
  wherever those happen to be drawn. (6.3 item 3 of the mirroring scope note.) Pinned
  because making the arrows visual is exactly the change that would tempt someone to make
  these visual too. }
procedure TEditBidiTest.HomeAndEndStayLogicalNotVisual;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
begin
  E := MakeEdit(F, C, TextRtlThenLatin);
  try
    E.SimulateKeyDown(VK_END);
    AssertEquals('End goes to the LOGICAL end of the text', 3, E.CaretPos);
    E.SimulateKeyDown(VK_HOME);
    AssertEquals('Home goes to the LOGICAL start of the text', 0, E.CaretPos);
    { ...and the logical end really is not the visual end here, or the claim is vacuous. }
    E.SimulateKeyDown(VK_END);
    AssertTrue('the fixture must actually have its logical end on the LEFT',
      E.CaretDrawX(96) < E.CaretDrawXAt(0, 96, False));
  finally
    F.Free;
    C.Free;
  end;
end;

{ An insertion point stands after what was written, and an edit has to say so even when the
  click before it said otherwise.

  Both halves of the fixture start with a click on the FAR side of the embedded Hebrew run,
  which is the only gesture that can leave the caret bound to the character AFTER it. Then
  the text is edited, and the caret must come back to the side of the boundary the EDIT
  implies -- not the side the click did.

  The edits are chosen so the caret lands ON a direction boundary afterwards, because that
  is the only place where the two affinities are different pixels. An earlier version of
  this test typed a Latin letter, which left the caret in the middle of a left-to-right run
  where both answers agree; it passed against an edit path that never reset the affinity at
  all. }
procedure TEditBidiTest.TypingParksTheCaretAfterWhatWasTyped;

  procedure ClickTheFarSideOfTheRun(E: TTyEditAccess; ppi: Integer);
  var x: Integer;
  begin
    x := E.CaretDrawXAt(2, ppi, False);
    E.SimulateMouseDown(x, cH div 2);
    E.SimulateMouseUp(x, cH div 2);
    AssertEquals('the click must land on the far end of the embedded run', x,
      E.CaretDrawX(ppi));
  end;

var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  ppi: Integer;
  Typed: TUTF8Char;
begin
  { Typing a Hebrew letter at the end of a Hebrew run: right-to-left typing advances
    LEFTWARDS, so the caret belongs at that run's left edge -- the opposite end from where
    the click had it. }
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    ppi := E.Font.PixelsPerInch;
    ClickTheFarSideOfTheRun(E, ppi);
    Typed := Cp([cpALEF]);
    E.InjectKey(Typed);
    AssertEquals('after typing, the caret stands against the character just written',
      E.CaretDrawXAt(E.CaretPos, ppi, True), E.CaretDrawX(ppi));
  finally
    F.Free;
    C.Free;
  end;

  { And a deletion, which reaches the same reset by the same route. }
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    ppi := E.Font.PixelsPerInch;
    ClickTheFarSideOfTheRun(E, ppi);
    E.InjectBackspace;
    AssertEquals('after a backspace, likewise',
      E.CaretDrawXAt(E.CaretPos, ppi, True), E.CaretDrawX(ppi));
  finally
    F.Free;
    C.Free;
  end;
end;

{ SelStart and SelLength are LOGICAL, code-facing properties: they name a codepoint range
  and say nothing about glyphs, so a caret they place has no run to stand against and must
  fall back to the default. Without that, `Edit.SelStart := N` would inherit whichever side
  of a boundary the user's last CLICK happened to leave behind -- so the same assignment
  would put the caret in two different places depending on what the user did before it.

  Guarded here because it is the only route by which the default is reached and not also
  reached some other way: a text mutation resets it in InvalidateWidthCache and the arrow
  keys and the mouse choose it for themselves, so removing the reset from these setters
  passed the whole suite until this existed. }
procedure TEditBidiTest.ProgrammaticSelectionParksTheCaretAffinity;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  ppi, farSide: Integer;
begin
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    ppi := E.Font.PixelsPerInch;
    farSide := E.CaretDrawXAt(2, ppi, False);
    AssertTrue('the fixture must have two distinct sides to this boundary',
      farSide <> E.CaretDrawXAt(2, ppi, True));

    E.SimulateMouseDown(farSide, cH div 2);
    E.SimulateMouseUp(farSide, cH div 2);
    AssertEquals('the click leaves the caret on the far side', farSide, E.CaretDrawX(ppi));
    E.SelStart := E.CaretPos;
    AssertEquals('a SelStart write must park the caret on the default side, not the side '
      + 'the click left behind', E.CaretDrawXAt(E.CaretPos, ppi, True), E.CaretDrawX(ppi));

    E.SimulateMouseDown(farSide, cH div 2);
    E.SimulateMouseUp(farSide, cH div 2);
    AssertEquals('the click leaves the caret on the far side again', farSide,
      E.CaretDrawX(ppi));
    E.SelLength := 0;
    AssertEquals('and so must a SelLength write',
      E.CaretDrawXAt(E.CaretPos, ppi, True), E.CaretDrawX(ppi));
  finally
    F.Free;
    C.Free;
  end;
end;

{ --- what must NOT change ------------------------------------------------------------- }

{ Requirement one: left-to-right text does not change, in behaviour OR in cost. Proven
  rather than asserted -- the reference is the prefix sum itself, measured here with the
  same BGRA engine and the same font the control configures, so the assertion is against
  the arithmetic the control used to do and not against a stored number that could drift
  with it.

  Paired with an assertion about WHICH PATH RAN, because the geometry alone cannot make the
  performance claim -- and this is not a hypothetical. Forcing the gate permanently open
  passed every geometry guard in the whole 5000-test suite, because a Latin string is ONE
  run and the bidirectional layout reproduces the prefix sum for it exactly. The only
  difference is the cost: a TBidiTextLayout per text change, ~3.3 ms against a ~23 us caret
  query. TTyMemo once cost half a second per keystroke from uncached text measurement, and
  the caret is queried on every keystroke, every mouse move during a drag-select and every
  blink. }
procedure TEditBidiTest.LeftToRightCaretGeometryIsExactlyThePrefixSum;
const
  cText = 'Hello World 123';
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  bmp: TBGRABitmap;
  i, expected, startX: Integer;
begin
  AssertFalse('the fixture must not trip the gate', TyTextHasRTL(cText));
  E := MakeEdit(F, C, cText);
  bmp := TBGRABitmap.Create(1, 1);
  try
    AssertFalse('left-to-right text must not reach the bidirectional layout AT ALL',
      E.UsesBidiCaretForTest(96));
    TyConfigureTextFont(bmp, E.StyleFontNameForTest, E.StyleFontSizeForTest,
      E.StyleFontWeightForTest, 96);
    startX := E.TextStartXForTest;
    for i := 0 to UTF8Length(cText) do
    begin
      expected := startX + bmp.TextSize(UTF8Copy(cText, 1, i)).cx;
      AssertEquals('caret ' + IntToStr(i) + ' of left-to-right text must be the prefix sum',
        expected, E.CaretDrawXAt(i, 96, True));
      AssertEquals('and must not depend on which side of it the caret binds to',
        expected, E.CaretDrawXAt(i, 96, False));
    end;
  finally
    bmp.Free;
    F.Free;
    C.Free;
  end;
end;

{ A password field displays a mask, and the mask is ASCII. The gate must be asked about
  what is DRAWN, not about what is stored, or a Hebrew password would be laid out
  bidirectionally while a column of identical asterisks is what is on screen -- and the
  caret would walk backwards through them. }
procedure TEditBidiTest.MaskedFieldsNeverReachTheBidiPath;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  i, prev, curr: Integer;
begin
  E := MakeEdit(F, C, TextEmbeddedRtl);
  try
    AssertTrue('the fixture must reach the bidirectional path BEFORE it is masked',
      E.UsesBidiCaretForTest(96));
    E.PasswordChar := '*';
    AssertFalse('the displayed mask must not trip the gate',
      TyTextHasRTL(E.DisplayTextForTest));
    AssertFalse('...and the control must agree, or the gate is being asked about FText',
      E.UsesBidiCaretForTest(96));
    prev := -1;
    for i := 0 to 6 do
    begin
      curr := E.CaretDrawXAt(i, 96, True);
      AssertTrue('a masked field''s caret marches left to right (index ' + IntToStr(i)
        + ')', curr > prev);
      prev := curr;
    end;
  finally
    F.Free;
    C.Free;
  end;
end;

{ The gate's answer is CACHED, so the cache has to be dropped when the text changes -- and
  the failure would be silent in both directions: a field that started life in English and
  had Hebrew typed into it would keep the prefix sum forever, and one that started in Hebrew
  and was cleared would keep a run table describing text that no longer exists.

  Asserted through the caret's ORDER rather than through the flag, because the flag is
  private and because the order is the thing the user sees. }
procedure TEditBidiTest.ChangingTheTextEntersAndLeavesTheBidiPath;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
begin
  E := MakeEdit(F, C, 'abcW');
  try
    AssertFalse('Latin: no run table', E.UsesBidiCaretForTest(96));
    AssertTrue('Latin: codepoint 0 is drawn left of the last one',
      E.CaretDrawXAt(0, 96, False) < E.CaretDrawXAt(4, 96, True));
    E.Text := TextRtlThenLatin;
    AssertTrue('after Hebrew is typed in, the run table is built',
      E.UsesBidiCaretForTest(96));
    AssertTrue('...and codepoint 0 is drawn RIGHT of the last one',
      E.CaretDrawXAt(0, 96, False) > E.CaretDrawXAt(3, 96, True));
    E.Text := 'abcW';
    AssertFalse('and after it is replaced by Latin again, the run table is dropped',
      E.UsesBidiCaretForTest(96));
    AssertTrue('...and codepoint 0 is left of the last one once more',
      E.CaretDrawXAt(0, 96, False) < E.CaretDrawXAt(4, 96, True));
  finally
    F.Free;
    C.Free;
  end;
end;

{ The performance contract, measured where it is actually paid: the caret path.

  The gate rejects ASCII in one compare and CJK, Cyrillic and Greek on the lead byte
  without decoding, so it must be orders of magnitude cheaper than the query it guards.
  Both sides are timed here so the assertion is a RATIO and not a wall-clock number that a
  slower machine could fail. }
procedure TEditBidiTest.TheGateCostsFarLessThanTheCaretQueryItGuards;
const
  cReps = 20000;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  i, fired, sink: Integer;
  t0, tGate, tQuery: TDateTime;
  s: string;
begin
  s := 'Customer reference 4471-A (shipped)';
  E := MakeEdit(F, C, s);
  try
    fired := 0;
    t0 := Now;
    for i := 1 to cReps do
      if TyTextHasRTL(s) then Inc(fired);
    tGate := Now - t0;
    sink := 0;
    t0 := Now;
    for i := 1 to cReps do
      Inc(sink, E.CaretDrawXAt(i mod 30, 96, True));
    tQuery := Now - t0;
    AssertEquals('the gate must not fire on a Latin fixture', 0, fired);
    AssertTrue('the caret query must have done some work', sink > 0);
    AssertTrue('the gate must cost a small fraction of the caret query it guards (gate '
      + FormatFloat('0.000', tGate * 24 * 3600 * 1000) + 'ms, query '
      + FormatFloat('0.000', tQuery * 24 * 3600 * 1000) + 'ms over '
      + IntToStr(cReps) + ' reps)', tGate <= tQuery);
  finally
    F.Free;
    C.Free;
  end;
end;

{ --- the edit and the painter must not drift apart ------------------------------------ }

{ TTyEdit lays the line out for itself rather than calling TTyPainter.TextCaretX, for two
  reasons recorded here because they are the reason this guard exists:

  the painter's seam needs a painter that is MID-PAINT (it lays out on FBmp, which only
  exists between BeginPaint and EndPaint), and a caret is queried from mouse handlers, key
  handlers and the blink timer, none of which are painting; and it answers with
  TBidiTextLayout.GetCaret, which collapses the two sides of a direction boundary onto
  whichever run ENDS there -- see BothSidesOfADirectionBoundaryAreReachable.

  So the two compute the same thing twice, and this is what stops them drifting: for every
  index that is NOT on a run boundary the answer is unambiguous, and the control's must
  equal the painter's to the pixel. Boundary indices are excluded by construction -- they
  are the ones the painter cannot express -- and are covered by the guard above instead. }
procedure TEditBidiTest.EditCaretAgreesWithThePainterForUnambiguousIndices;
var
  F: TForm;
  C: TTyStyleController;
  E: TTyEditAccess;
  host: TBitmap;
  P: TTyPainter;
  r: TRect;
  txt: string;
  i, startX, viaPainter, viaEdit, checked: Integer;
begin
  txt := TextEmbeddedRtl;
  E := MakeEdit(F, C, txt);
  host := TBitmap.Create;
  try
    startX := E.TextStartXForTest;
    host.SetSize(cW, cH);
    checked := 0;
    for i := 0 to UTF8Length(txt) do
    begin
      { Boundary indices of the fixture: 0 and 6 are the ends of the line, 2 and 4 are the
        two ends of the embedded run. 1, 3 and 5 are strictly inside a run. }
      if (i = 0) or (i = 2) or (i = 4) or (i = 6) then Continue;
      P := TTyPainter.Create;
      try
        r := Rect(startX, 0, cW, cH);
        P.BeginPaint(host.Canvas, Rect(0, 0, cW, cH), 96);
        viaPainter := P.TextCaretX(r, txt, E.StyleFontNameForTest, E.StyleFontSizeForTest,
          E.StyleFontWeightForTest, taLeftJustify, i);
        P.EndPaint;
      finally
        P.Free;
      end;
      viaEdit := E.CaretDrawXAt(i, 96, True);
      AssertEquals('the edit and the painter must agree about codepoint ' + IntToStr(i),
        viaPainter, viaEdit);
      Inc(checked);
    end;
    AssertEquals('the fixture must actually have interior indices to check', 3, checked);
  finally
    host.Free;
    F.Free;
    C.Free;
  end;
end;

initialization
  RegisterTest(TEditBidiTest);
end.
