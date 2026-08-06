unit test.tabstrip.multiline;
{ TTyCustomTabStrip: MultiLine / RaggedRight / RowCount -- the run FOLDS instead of
  overflowing.

  The same rule as test.tabstrip.axis, and for a sharper reason. Folding adds a SECOND
  dimension to a layout that had one, so every consumer that used to be able to ignore the
  cross axis can now be wrong about it while still looking right:

    * a hit test that compares only the main axis finds the row-0 tab first and makes every
      tab on row 1 undrawn-but-unclickable -- no, worse, DRAWN and unclickable;
    * a drag-reorder midpoint rule that compares only the main axis answers "the nearest
      midpoint anywhere", which across a row boundary is a whole slot wrong;
    * a close glyph or an icon whose cross coordinate is measured from the BAND rather than
      from its own row stays stranded on row 0 while its tab moves down.

  So the agreement tests below are grounded in the PAINT and not in a second call to the
  layout. Each takes the bounding box of the pixels the active tab actually filled, asserts
  that box IS TabRect, and only then uses it to aim. That chain is what makes the probe
  non-circular: the axis work found that asking the layout where the layout put something
  proves nothing, and the mutant that moved the paint without the hit test survived it.

  Every probe is at an EDGE -- one pixel inside a row boundary, one pixel either side of a
  midpoint. A row boundary is the exact place a one-pixel drift hides, and a probe at a row's
  centre passes for any fold that is merely in the right neighbourhood. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes, ComCtrls,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller,
  tyControls.TabStrip, tyControls.PageControl, tyControls.TabSheet, tyControls.TabSet,
  test.tabstrip, test.tabstrip.axis;
type
  { A strip that reserves room at the head of its band, the way TTyRibbon reserves it for the
    File tab. Nothing else in the suite has a non-zero HeaderLeftInset, so without this the
    difference between wrapping against the band and wrapping against the band MINUS the
    inset is invisible -- and the row would be justified 40px wider than the space it is
    drawn in, overhanging the control by exactly the inset. }
  TInsetStrip = class(TAxisStrip)
  protected
    function HeaderLeftInset: Integer; override;
  end;

  TTabMultiLineTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FStrip: TAxisStrip;
    procedure Build(APos: TTabPosition; ACount: Integer = 4;
                    AW: Integer = 400; AH: Integer = 300;
                    AClosable: Boolean = False; ARtl: Boolean = False);
    function  Shot: TBGRABitmap;
    { One row's extent across the cross axis, derived from the two numbers the control
      reports rather than assumed: a top/bottom row is TabHeight, a side one is the widest
      caption box, and this test must not care which. }
    function  RowThick: Integer;
    function  RowOf(AIndex: Integer): Integer;
    function  NaturalWidths: TIntegerDynArray;
    { A device-px point from a MAIN and a (screen, mirror-already-applied) CROSS coordinate.
      The axis suite's AtMain pinned the cross to the band's centre, which is exactly the
      probe folding makes useless: the band's centre is a ROW BOUNDARY once there are two. }
    function  PtAt(AMain, ACrossScreen: Integer): TPoint;
    function  MainLo(const R: TRect): Integer;
    function  MainHi(const R: TRect): Integer;
    function  CrossLo(const R: TRect): Integer;
    function  CrossHi(const R: TRect): Integer;
    procedure CheckPaintHitAndDragAgree(APos: TTabPosition; ARtl: Boolean);
  protected
    procedure TearDown; override;
  published
    { --- the unfolded shape must not have moved --------------------------------------- }
    procedure DefaultsAreOffAndRowCountIsOne;
    procedure AnEmptyStripStillHasItsBand;
    { --- the fold itself --------------------------------------------------------------- }
    procedure ATabFoldsAtTheExactPixelItStopsFitting;
    procedure AnOverWideTabKeepsItsOwnRowAndLeavesNoneEmpty;
    procedure RaggedRightOffFillsTheRowToTheLastPixel;
    procedure RaggedRightOnLeavesTheRowShort;
    procedure TheStripExtentIsTheLongestRowNotTheLast;
    { --- the interlocks ---------------------------------------------------------------- }
    procedure FoldingTurnsTheOverflowAffordanceOff;
    procedure TheBodyGivesUpEveryRowNotJustTheFirst;
    procedure SelectionIsStillARenderStateNotALayoutInput;
    { --- one source: paint / hit test / drag ------------------------------------------- }
    procedure PaintHitAndDragAgreeOnEveryFoldedBand;
    procedure PaintHitAndDragAgreeOnAFoldedMirroredBand;
    procedure ADragAcrossARowBoundaryLandsInTheRightSlot;
    procedure ADragOffTheBandClampsIntoTheNearestRow;
    procedure TheOneAxisDropEntryPointStillIgnoresTheOtherAxis;
    procedure AHiddenBandStillResolvesADropByMidpoints;
    procedure PressAndHoverReachTheSecondRow;
    { --- the parts INSIDE a tab travel with it ---------------------------------------- }
    procedure TheCloseGlyphTravelsDownToItsOwnRow;
    { --- side bands -------------------------------------------------------------------- }
    procedure ASideBandFoldsIntoColumns;
    procedure AReservedHeadIsRoomTheRowsDoNotGet;
    { --- the concrete strips ----------------------------------------------------------- }
    procedure ThePagerAndTheTabSetPublishIt;
  end;

implementation

uses TypInfo;

const
  { Borrowed wholesale from test.tabstrip.axis so a bounding box IS the rect the painter was
    handed: no border, no radius, one distinct colour for the active tab. }
  MlCss =
    'TyTabControl  { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyPageControl { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTabSet      { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTabSheet    { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTab         { background: #FFFFFF; color: #101010; font-size: 12px; ' +
                    'border-width: 0px; border-radius: 0px; }' +
    'TyTab:active  { background: #FF0000; color: #101010; }';
  ActiveRed: TBGRAPixel = (blue: 0; green: 0; red: 255; alpha: 255);
  AllPositions: array[0..3] of TTabPosition = (tpTop, tpBottom, tpLeft, tpRight);

function PosName(P: TTabPosition): string;
begin
  case P of
    tpTop:    Result := 'tpTop';
    tpBottom: Result := 'tpBottom';
    tpLeft:   Result := 'tpLeft';
  else        Result := 'tpRight';
  end;
end;

function BoundsOfColor(bmp: TBGRABitmap; AColor: TBGRAPixel): TRect;
var
  x, y: Integer;
  p: TBGRAPixel;
  found: Boolean;
begin
  Result := Rect(0, 0, 0, 0);
  found := False;
  for y := 0 to bmp.Height - 1 do
    for x := 0 to bmp.Width - 1 do
    begin
      p := bmp.GetPixel(x, y);
      if (p.red = AColor.red) and (p.green = AColor.green) and (p.blue = AColor.blue) then
      begin
        if not found then
        begin
          Result := Rect(x, y, x + 1, y + 1);
          found := True;
        end
        else
        begin
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
      end;
    end;
end;

function TInsetStrip.HeaderLeftInset: Integer;
begin
  Result := 40;
end;

{ ---------------------------------------------------------------------------------- }

procedure TTabMultiLineTest.Build(APos: TTabPosition; ACount, AW, AH: Integer;
  AClosable, ARtl: Boolean);
var
  i: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(MlCss);
  FStrip := TAxisStrip.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Controller := FCtl;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.TabHeight := 28;              // pin it: the fixture must not follow density
  FStrip.SetBounds(0, 0, AW, AH);
  FStrip.TabsClosable := AClosable;
  for i := 1 to ACount do FStrip.AddCap('Tab ' + IntToStr(i));
  if ARtl then FStrip.BiDiMode := bdRightToLeft;
  FStrip.TabPosition := APos;
end;

procedure TTabMultiLineTest.TearDown;
begin
  if FForm <> nil then FForm.Free;
  FForm := nil; FStrip := nil; FCtl := nil;
end;

function TTabMultiLineTest.Shot: TBGRABitmap;
var
  host: TBitmap;
begin
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(FStrip.Width, FStrip.Height);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, FStrip.Width, FStrip.Height);
    FStrip.Render(host.Canvas, Rect(0, 0, FStrip.Width, FStrip.Height), 96);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
  end;
end;

function TTabMultiLineTest.RowThick: Integer;
begin
  if FStrip.RowCount <= 0 then Exit(FStrip.BandThicknessPx);
  Result := FStrip.BandThicknessPx div FStrip.RowCount;
end;

{ Which row a tab landed on, read off its CONTENT-space cross coordinate -- the number the
  fold actually wrote, not one re-derived from a screen rect. }
function TTabMultiLineTest.RowOf(AIndex: Integer): Integer;
begin
  Result := FStrip.TyTabHeaderRect(AIndex).Top div RowThick;
end;

function TTabMultiLineTest.NaturalWidths: TIntegerDynArray;
var
  i: Integer;
  r: TRect;
begin
  SetLength(Result, FStrip.TabCount);
  for i := 0 to FStrip.TabCount - 1 do
  begin
    r := FStrip.TyTabHeaderRect(i);
    Result[i] := r.Right - r.Left;
  end;
end;

function TTabMultiLineTest.PtAt(AMain, ACrossScreen: Integer): TPoint;
begin
  { On a side band the main axis is y and the cross axis is x; on a top/bottom band it is the
    other way round. Both coordinates come straight off the PAINTED box in the callers, so
    the mirror is already baked into them and nothing here has to re-apply it. }
  if FStrip.BandIsVertical then
    Result := Point(ACrossScreen, AMain)
  else
    Result := Point(AMain, ACrossScreen);
end;

function TTabMultiLineTest.MainLo(const R: TRect): Integer;
begin
  if FStrip.BandIsVertical then Result := R.Top else Result := R.Left;
end;

function TTabMultiLineTest.MainHi(const R: TRect): Integer;
begin
  if FStrip.BandIsVertical then Result := R.Bottom else Result := R.Right;
end;

function TTabMultiLineTest.CrossLo(const R: TRect): Integer;
begin
  if FStrip.BandIsVertical then Result := R.Left else Result := R.Top;
end;

function TTabMultiLineTest.CrossHi(const R: TRect): Integer;
begin
  if FStrip.BandIsVertical then Result := R.Right else Result := R.Bottom;
end;

{ === the unfolded shape must not have moved ======================================== }

{ The three properties are new, so False/False is both LCL's default AND "nothing changed",
  which is the pair of facts that lets `default False` be written at all. RowCount answers
  the layout's own question and must therefore be 1 while nothing folds. }
procedure TTabMultiLineTest.DefaultsAreOffAndRowCountIsOne;
var
  pi, i: Integer;
  r: TRect;
  who: string;
begin
  for pi := 0 to High(AllPositions) do
  begin
    Build(AllPositions[pi]);
    who := PosName(AllPositions[pi]);
    try
      AssertFalse(who + ': MultiLine must start off', FStrip.MultiLine);
      AssertFalse(who + ': RaggedRight must start off', FStrip.RaggedRight);
      AssertEquals(who + ': an unfolded strip is exactly one row', 1, FStrip.RowCount);
      { Every tab still spans the WHOLE band across the cross axis -- which is precisely why
        the main-axis-only hit test was correct before folding and is not after. }
      for i := 0 to FStrip.TabCount - 1 do
      begin
        r := FStrip.TyTabHeaderRect(i);
        AssertEquals(who + ': tab ' + IntToStr(i) + ' does not start at the band edge',
          0, r.Top);
        AssertEquals(who + ': tab ' + IntToStr(i) + ' does not span the whole band',
          FStrip.BandThicknessPx, r.Bottom - r.Top);
      end;
    finally
      TearDown;
    end;
  end;
end;

{ FBandThickness = RowCount * RowThick is the whole reason InsetForBand / BandBoxPx /
  BandRect need no change -- and it is also a trap: with no tabs RowCount is 0, and taken
  literally that would DELETE the band an empty strip has always drawn. }
procedure TTabMultiLineTest.AnEmptyStripStillHasItsBand;
var
  pi: Integer;
  who: string;
begin
  for pi := 0 to High(AllPositions) do
  begin
    Build(AllPositions[pi], 0);
    who := PosName(AllPositions[pi]);
    try
      AssertEquals(who + ': no tabs is no rows', 0, FStrip.RowCount);
      AssertEquals(who + ': but an empty strip still shows one row of band',
        28, FStrip.BandThicknessPx);
      FStrip.MultiLine := True;
      AssertEquals(who + ': and folding an empty strip must not change that',
        28, FStrip.BandThicknessPx);
      AssertEquals(who + ': still no rows', 0, FStrip.RowCount);
    finally
      TearDown;
    end;
  end;
end;

{ === the fold itself =============================================================== }

{ Probed at the EXACT pixel, from both sides. The control is first sized so tab 2's right
  edge lands one pixel PAST the band, then widened by that one pixel. A `>=` where the code
  wants `>` (or the reverse) survives any probe that is not this one. }
procedure TTabMultiLineTest.ATabFoldsAtTheExactPixelItStopsFitting;
var
  w: TIntegerDynArray;
  need: Integer;
begin
  Build(tpTop, 4, 600, 300);
  w := NaturalWidths;
  need := w[0] + w[1] + w[2];        // the width at which tab 2 exactly fits on row 0

  FStrip.MultiLine := True;
  FStrip.SetBounds(0, 0, need - 1, 300);
  AssertEquals('one pixel short, tab 0 must stay on row 0', 0, RowOf(0));
  AssertEquals('one pixel short, tab 1 must stay on row 0', 0, RowOf(1));
  AssertEquals('one pixel short, tab 2 must have folded onto row 1', 1, RowOf(2));

  FStrip.SetBounds(0, 0, need, 300);
  AssertEquals('at exactly the width it needs, tab 2 must NOT fold', 0, RowOf(2));
  AssertEquals('and tab 1 must not have moved either', 0, RowOf(1));
end;

{ The `(X > 0)` guard. Not, as it happens, against an infinite loop -- the fold is a FOR over
  a fixed tab count and cannot spin -- but against folding a tab that is wider than the whole
  band at the START of its row, which pushes it down and leaves the row above it EMPTY.
  Nothing narrower exists to put it in; it has to be allowed to overhang. }
procedure TTabMultiLineTest.AnOverWideTabKeepsItsOwnRowAndLeavesNoneEmpty;
var
  w: TIntegerDynArray;
begin
  { Tab 0 is the over-wide one, and it has to be FIRST: an over-wide tab in the middle folds
    onto a fresh row under either rule, so only a leading one separates them. }
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(MlCss);
  FStrip := TAxisStrip.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Controller := FCtl;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.TabHeight := 28;
  FStrip.SetBounds(0, 0, 600, 300);
  FStrip.AddCap(StringOfChar('W', 60));
  FStrip.AddCap('Second');

  w := NaturalWidths;
  FStrip.SetBounds(0, 0, w[0] - 40, 300);   // narrower than tab 0 alone
  AssertTrue('the fixture was supposed to make tab 0 wider than the band',
    w[0] > FStrip.Width);

  FStrip.MultiLine := True;
  AssertEquals('an over-wide tab must occupy the FIRST row, not push itself off it',
    0, RowOf(0));
  AssertEquals('and the next tab folds under it', 1, RowOf(1));
  AssertEquals('so there are two rows and no empty one above', 2, FStrip.RowCount);
  AssertEquals('the band is two rows thick', 2 * 28, FStrip.BandThicknessPx);
  AssertTrue('an over-wide tab is allowed to overhang; it must never be shrunk',
    FStrip.TyTabHeaderRect(0).Right >= w[0]);

  { AND the overflow affordance must STILL be off. This is the only fixture in the unit
    where that is a real question: an over-wide row is the one folded shape whose run
    genuinely reaches past the control, so it is the one shape where the `not MultiLine`
    term in the affordance test does any work. See FoldingTurnsTheOverflowAffordanceOff --
    a justified fixture cannot ask this, because justification pins every row to exactly the
    band width and the overflow test then answers False on its own. }
  AssertTrue('the fixture must actually overhang for this to be a real question',
    FStrip.TyHeaderStripWidth > FStrip.Width);
  AssertEquals('a folded strip must not grow overflow arrows even when a row overhangs',
    0, FStrip.TyMaxHeaderScroll);
  AssertTrue('nor a back arrow',
    FStrip.TyTabScrollLeftRect.Right <= FStrip.TyTabScrollLeftRect.Left);
  AssertTrue('nor a forward one',
    FStrip.TyTabScrollRightRect.Right <= FStrip.TyTabScrollRightRect.Left);
end;

{ RaggedRight = False is LCL's default and LCL's polarity: WITHOUT the TCS_RAGGEDRIGHT bit
  comctl32 stretches. The remainder is the load-bearing part -- `extra div n` alone leaves a
  row up to n-1 px short, which is a visible notch on any skin with a tab border. }
procedure TTabMultiLineTest.RaggedRightOffFillsTheRowToTheLastPixel;
var
  w: TIntegerDynArray;
  W0: Integer;
  r0, r1, r2: TRect;
begin
  Build(tpTop, 3, 600, 300);
  w := NaturalWidths;
  AssertTrue('the fixture needs a third tab wider than the 3px slack it leaves', w[2] > 3);

  { Width = tabs 0 and 1 natural + 3. Row 0 therefore holds exactly {0,1} with 3px of slack,
    so share = 1 and remainder = 1: dropping the remainder is off by exactly one pixel. }
  W0 := w[0] + w[1] + 3;
  FStrip.SetBounds(0, 0, W0, 300);
  FStrip.MultiLine := True;

  AssertEquals('the fixture was supposed to fold into two rows', 2, FStrip.RowCount);
  r0 := FStrip.TyTabHeaderRect(0);
  r1 := FStrip.TyTabHeaderRect(1);
  r2 := FStrip.TyTabHeaderRect(2);

  AssertEquals('row 0 must reach the band''s last pixel -- the remainder was dropped',
    W0, r1.Right);
  AssertEquals('the first tab of the row takes share + the spare pixel',
    w[0] + 2, r0.Right - r0.Left);
  AssertEquals('the second takes share alone', w[1] + 1, r1.Right - r1.Left);
  AssertEquals('and they still tile without a seam', r0.Right, r1.Left);
  AssertEquals('a row with ONE tab is justified too -- it becomes the whole band',
    W0, r2.Right);
  AssertEquals('and it starts at the band''s leading edge', 0, r2.Left);
end;

procedure TTabMultiLineTest.RaggedRightOnLeavesTheRowShort;
var
  w: TIntegerDynArray;
  W0: Integer;
  r0, r1: TRect;
begin
  Build(tpTop, 3, 600, 300);
  w := NaturalWidths;
  W0 := w[0] + w[1] + 3;
  FStrip.SetBounds(0, 0, W0, 300);
  FStrip.MultiLine := True;
  FStrip.RaggedRight := True;

  r0 := FStrip.TyTabHeaderRect(0);
  r1 := FStrip.TyTabHeaderRect(1);
  AssertEquals('a ragged row keeps tab 0 at its natural width', w[0], r0.Right - r0.Left);
  AssertEquals('and tab 1 at its own', w[1], r1.Right - r1.Left);
  AssertEquals('so the row stops short of the band edge', W0 - 3, r1.Right);
  AssertEquals('the fold itself is unchanged by justification', 2, FStrip.RowCount);
end;

{ TyHeaderStripWidth read the LAST header's right edge, which is the same number as the
  longest row only while there is one row. Folded, the last header is at the end of the last
  row -- normally the SHORTEST, because it holds the leftovers -- so the strip would report
  itself narrower than it is drawn, and TyMaxHeaderScroll (which measures off the same
  quantity) with it.

  RAGGED on purpose. Every other folded fixture in this unit is justified, and justification
  makes every row exactly the band width -- which makes the longest row and the last row the
  same number and hides the difference completely. That is how this went unnoticed the first
  time: the mutant that reads the last header instead of the maximum survived a suite of
  twenty tests, all of them measuring rows that had been flattened to equal length. }
procedure TTabMultiLineTest.TheStripExtentIsTheLongestRowNotTheLast;
var
  i, longest, lastRight: Integer;
begin
  Build(tpTop, 7, 220, 300);
  FStrip.RaggedRight := True;
  FStrip.MultiLine := True;
  AssertTrue('the fixture was supposed to fold', FStrip.RowCount > 1);

  longest := 0;
  for i := 0 to FStrip.TabCount - 1 do
    if FStrip.TyTabHeaderRect(i).Right > longest then
      longest := FStrip.TyTabHeaderRect(i).Right;
  lastRight := FStrip.TyTabHeaderRect(FStrip.TabCount - 1).Right;

  AssertTrue('the fixture must leave the LAST row shorter than the longest, or this test ' +
    'cannot tell the two readings apart', lastRight < longest);
  AssertEquals('the strip''s main extent is its longest row', longest,
    FStrip.TyHeaderStripWidth);
end;

{ === the interlocks =============================================================== }

{ Folding and overflow-scrolling are the two answers to the same question and a strip must
  not give both: arrows over a fully visible run reserve 16px at each end of every row and
  bury the first tab of each under one of them.

  NOT SUFFICIENT ON ITS OWN, and the reason is worth keeping. This fixture is justified
  (RaggedRight defaults False), and justification pins every row to exactly the band width --
  so the overflow test `StripLen > MainVisible` answers False by arithmetic and the explicit
  `not MultiLine` term is never consulted. Deleting that term leaves this test green. The
  guard that actually bites lives in AnOverWideTabKeepsItsOwnRowAndLeavesNoneEmpty, where a
  row really does overhang. This one still earns its place: it is the only test that pins the
  ARROW RECTS going empty and the live scroll offset being dropped rather than kept. }
procedure TTabMultiLineTest.FoldingTurnsTheOverflowAffordanceOff;
var
  l, r: TRect;
begin
  Build(tpTop, 12, 220, 150);
  AssertTrue('the fixture was supposed to overflow', FStrip.TyMaxHeaderScroll > 0);
  FStrip.SetHeaderScroll(30);
  AssertEquals('and to be scrolled when folding arrives', 30, FStrip.HeaderScroll);
  l := FStrip.TyTabScrollLeftRect;
  AssertTrue('the fixture was supposed to show arrows', l.Right > l.Left);

  FStrip.MultiLine := True;

  AssertEquals('a folded strip has nothing off-screen, so nothing to scroll to',
    0, FStrip.TyMaxHeaderScroll);
  AssertEquals('and the offset it was carrying must be dropped, not kept',
    0, FStrip.HeaderScroll);
  l := FStrip.TyTabScrollLeftRect;
  r := FStrip.TyTabScrollRightRect;
  AssertTrue('the back arrow must be gone', l.Right <= l.Left);
  AssertTrue('the forward arrow must be gone', r.Right <= r.Left);
  AssertTrue('and the fixture really did fold', FStrip.RowCount > 1);
  { With no arrow band reserved, content-main 0 maps straight to the band's edge again. }
  AssertEquals('the first tab must start at the band edge, not behind an arrow',
    0, MainLo(FStrip.TabRect(0)));
end;

{ AdjustClientRect and DisplayRect both go through InsetForBand, which speaks in
  BandThicknessPx -- so the body has to give up RowCount rows and not one. }
procedure TTabMultiLineTest.TheBodyGivesUpEveryRowNotJustTheFirst;
var
  rows: Integer;
begin
  Build(tpTop, 8, 200, 300);
  FStrip.MultiLine := True;
  rows := FStrip.RowCount;
  AssertTrue('the fixture was supposed to fold', rows > 1);
  AssertEquals('the band is RowCount rows thick', rows * 28, FStrip.BandThicknessPx);
  AssertEquals('the body starts below EVERY row', rows * 28, FStrip.DisplayRect.Top);
  AssertEquals('and still keeps the full width', FStrip.Width, FStrip.DisplayRect.Right);

  FStrip.TabPosition := tpBottom;
  rows := FStrip.RowCount;
  AssertEquals('a bottom band gives up its rows from the bottom',
    FStrip.Height - rows * 28, FStrip.DisplayRect.Bottom);
end;

{ The one thing this deliberately did NOT build. Delphi/comctl32 re-seat the selected row
  next to the page body when MultiLine is on -- which is what would turn selection from a
  render state into a layout input, and would re-fold the band underneath a drag-reorder
  gesture that pins selection to the POSITION. If that ever gets built, this test is the one
  that has to be rewritten first, on purpose. }
procedure TTabMultiLineTest.SelectionIsStillARenderStateNotALayoutInput;
var
  i: Integer;
  before: array of TRect;
begin
  Build(tpTop, 8, 200, 300);
  FStrip.MultiLine := True;
  AssertTrue('the fixture was supposed to fold', FStrip.RowCount > 1);
  FStrip.TabIndex := 0;
  SetLength(before, FStrip.TabCount);
  for i := 0 to FStrip.TabCount - 1 do before[i] := FStrip.TabRect(i);

  FStrip.TabIndex := FStrip.TabCount - 1;   // a tab on the LAST row
  AssertEquals('the selection did not take', FStrip.TabCount - 1, FStrip.TabIndex);
  for i := 0 to FStrip.TabCount - 1 do
  begin
    AssertEquals('selecting a tab moved tab ' + IntToStr(i) + ' (left)',
      before[i].Left, FStrip.TabRect(i).Left);
    AssertEquals('selecting a tab moved tab ' + IntToStr(i) + ' (top)',
      before[i].Top, FStrip.TabRect(i).Top);
  end;
  AssertTrue('and MultiLine must not have grown a ScrollOpposite that does nothing',
    GetPropInfo(TTyPageControl, 'ScrollOpposite') = nil);
end;

{ === one source: paint / hit test / drag ========================================== }

{ The chain, in order, per tab:
    1. select it, render, take the bounding box of the pixels it FILLED;
    2. assert that box is exactly TabRect -- this is what grounds everything after it in the
       paint rather than in a second call to the layout;
    3. hit-test one pixel inside each of that box's four corners: both are on the tab's own
       row and inside its own main span, so a main-only hit test names the row-0 tab instead;
    4. drop-test one pixel either side of that box's drawn midpoint, on its own row. }
procedure TTabMultiLineTest.CheckPaintHitAndDragAgree(APos: TTabPosition; ARtl: Boolean);
var
  i, mid, fwd, cLo, cHi: Integer;
  bmp: TBGRABitmap;
  box: TRect;
  who: string;
begin
  { Deliberately non-square, and small along the main axis so the run folds at every
    position: 200 wide folds a top band, 150 high folds a side one. }
  Build(APos, 6, 200, 150, False, ARtl);
  who := PosName(APos);
  if ARtl then who := who + '+rtl';
  try
    FStrip.MultiLine := True;
    AssertTrue(who + ': the fixture was supposed to fold', FStrip.RowCount > 1);
    if FStrip.BandIsVertical or not ARtl then fwd := 1 else fwd := -1;

    for i := 0 to FStrip.TabCount - 1 do
    begin
      FStrip.TabIndex := i;
      bmp := Shot;
      try
        box := BoundsOfColor(bmp, ActiveRed);
        AssertTrue(who + ': the active tab painted nothing, tab ' + IntToStr(i),
          (box.Right > box.Left) and (box.Bottom > box.Top));
        AssertEquals(who + ': painted left <> TabRect left, tab ' + IntToStr(i),
          FStrip.TabRect(i).Left, box.Left);
        AssertEquals(who + ': painted top <> TabRect top, tab ' + IntToStr(i),
          FStrip.TabRect(i).Top, box.Top);
        AssertEquals(who + ': painted right <> TabRect right, tab ' + IntToStr(i),
          FStrip.TabRect(i).Right, box.Right);
        AssertEquals(who + ': painted bottom <> TabRect bottom, tab ' + IntToStr(i),
          FStrip.TabRect(i).Bottom, box.Bottom);

        { One pixel inside each corner of what was actually painted. }
        AssertEquals(who + ': the hit test misses the pixel the paint filled (leading), tab ' +
          IntToStr(i), i, FStrip.IndexOfTabAt(box.Left + 1, box.Top + 1));
        AssertEquals(who + ': the hit test misses the pixel the paint filled (trailing), tab ' +
          IntToStr(i), i, FStrip.IndexOfTabAt(box.Right - 1, box.Bottom - 1));

        { The drop rule, on the tab's own row, probed one pixel inside BOTH cross edges so a
          rule that is right in the middle of a row and wrong at its boundary cannot hide. }
        mid := (MainLo(box) + MainHi(box)) div 2;
        cLo := CrossLo(box) + 1;      // one pixel inside the row's leading cross edge
        cHi := CrossHi(box) - 1;      // and one inside its trailing one
        AssertEquals(who + ': back of tab ' + IntToStr(i) + '''s drawn midpoint, row leading edge',
          i, FStrip.TyDropIndexAtPoint(PtAt(mid - fwd, cLo), 96));
        AssertEquals(who + ': back of tab ' + IntToStr(i) + '''s drawn midpoint, row trailing edge',
          i, FStrip.TyDropIndexAtPoint(PtAt(mid - fwd, cHi), 96));
        if i < FStrip.TabCount - 1 then
          AssertEquals(who + ': forward of tab ' + IntToStr(i) + '''s drawn midpoint must ' +
            'drop into tab ' + IntToStr(i + 1),
            i + 1, FStrip.TyDropIndexAtPoint(PtAt(mid + fwd, cLo), 96))
        else
          AssertEquals(who + ': forward of the LAST drawn midpoint must stay on the last tab',
            i, FStrip.TyDropIndexAtPoint(PtAt(mid + fwd, cLo), 96));
      finally
        bmp.Free;
      end;
    end;
  finally
    TearDown;
  end;
end;

procedure TTabMultiLineTest.PaintHitAndDragAgreeOnEveryFoldedBand;
var
  pi: Integer;
begin
  for pi := 0 to High(AllPositions) do
    CheckPaintHitAndDragAgree(AllPositions[pi], False);
end;

procedure TTabMultiLineTest.PaintHitAndDragAgreeOnAFoldedMirroredBand;
var
  pi: Integer;
begin
  for pi := 0 to High(AllPositions) do
    CheckPaintHitAndDragAgree(AllPositions[pi], True);
end;

{ The silent failure folding introduces, and the one a one-dimensional midpoint rule cannot
  even be close on. Both probes are OFF by a whole slot under the old rule:

    * past the last midpoint of row 0 -> the lexicographic rule says "the first tab of row 1"
      (the slot at the row boundary); the main-only rule runs out of midpoints and defaults
      to the LAST tab of the whole strip;
    * before the first midpoint of row 1 -> the lexicographic rule says "the first tab of
      row 1"; the main-only rule sees a small main coordinate and says tab 0. }
procedure TTabMultiLineTest.ADragAcrossARowBoundaryLandsInTheRightSlot;
var
  i, firstOfRow1, lastOfRow0, thick: Integer;
  r: TRect;
begin
  Build(tpTop, 8, 220, 300);
  FStrip.MultiLine := True;
  AssertTrue('the fixture was supposed to fold', FStrip.RowCount > 1);
  thick := RowThick;

  firstOfRow1 := -1;
  for i := 0 to FStrip.TabCount - 1 do
    if (RowOf(i) = 1) and (firstOfRow1 < 0) then firstOfRow1 := i;
  AssertTrue('the fixture was supposed to put something on row 1', firstOfRow1 > 0);
  lastOfRow0 := firstOfRow1 - 1;

  { In row 0, one pixel inside its BOTTOM edge, past the last row-0 midpoint. }
  r := FStrip.TabRect(lastOfRow0);
  AssertEquals('a point past the end of row 0 must drop at the row boundary, not at the ' +
    'last tab of the strip',
    firstOfRow1, FStrip.TyDropIndexAtPoint(Point(r.Right - 1, thick - 1), 96));

  { In row 1, one pixel inside its TOP edge, before the first row-1 midpoint. }
  r := FStrip.TabRect(firstOfRow1);
  AssertEquals('a point at the start of row 1 must drop there, not back at tab 0',
    firstOfRow1, FStrip.TyDropIndexAtPoint(Point(r.Left + 1, thick + 1), 96));

  { And the row-0 answer must not have been poisoned: the same main coordinate one pixel
    HIGHER is still row 0. }
  AssertEquals('one pixel up is still row 0',
    0, FStrip.TyDropIndexAtPoint(Point(FStrip.TabRect(0).Left + 1, thick - 1), 96));
end;

{ A drag does not stop at the band's edge -- the pointer leaves it constantly. Unclamped, the
  row half of the comparison answers "the row above the first" or "the row below the last",
  which are different SLOTS rather than nearby ones: above the band every probe would resolve
  to tab 0 whatever its main coordinate. }
procedure TTabMultiLineTest.ADragOffTheBandClampsIntoTheNearestRow;
var
  i, firstOfRow1, thick, lastRowTop: Integer;
  r: TRect;
begin
  Build(tpTop, 8, 220, 300);
  FStrip.MultiLine := True;
  AssertTrue('the fixture was supposed to fold', FStrip.RowCount > 1);
  thick := RowThick;
  firstOfRow1 := -1;
  for i := 0 to FStrip.TabCount - 1 do
    if (RowOf(i) = 1) and (firstOfRow1 < 0) then firstOfRow1 := i;
  AssertTrue('the fixture was supposed to put something on row 1', firstOfRow1 > 0);
  lastRowTop := (FStrip.RowCount - 1) * thick;

  { ABOVE the band, past the end of row 0: clamps into row 0 and answers exactly what a
    probe one pixel INSIDE row 0 answers -- not "tab 0". }
  r := FStrip.TabRect(firstOfRow1 - 1);
  AssertEquals('a drag above the band must clamp into the FIRST row, not collapse to tab 0',
    FStrip.TyDropIndexAtPoint(Point(r.Right - 1, thick - 1), 96),
    FStrip.TyDropIndexAtPoint(Point(r.Right - 1, -40), 96));

  { BELOW the band, at the start of the last row: clamps into the last row. }
  r := FStrip.TabRect(FStrip.TabCount - 1);
  AssertEquals('a drag below the band must clamp into the LAST row',
    FStrip.TyDropIndexAtPoint(Point(r.Left + 1, lastRowTop + 1), 96),
    FStrip.TyDropIndexAtPoint(Point(r.Left + 1, FStrip.Height + 40), 96));
end;

{ TyDropIndexAt takes an x and nothing else, so it hands the point form a y of 0 -- which on
  a tpBottom band is nowhere near the band. It answered correctly before folding because the
  rule ignored y entirely; it has to go on answering correctly now that the rule does not,
  and the CLAMP is the only thing making that true. Asserted against the two-axis form at the
  band's own cross centre, so this pins AGREEMENT and not a number.

  Top and bottom only: this entry point is documented as meaningless on a side band, where
  the main axis IS y and an x alone cannot answer. }
procedure TTabMultiLineTest.TheOneAxisDropEntryPointStillIgnoresTheOtherAxis;
const
  Horizontals: array[0..1] of TTabPosition = (tpTop, tpBottom);
var
  pi, i, mid, cross: Integer;
  b, r: TRect;
  who: string;
begin
  for pi := 0 to High(Horizontals) do
  begin
    Build(Horizontals[pi], 5, 400, 300);
    who := PosName(Horizontals[pi]);
    try
      AssertEquals(who + ': this fixture must NOT fold', 1, FStrip.RowCount);
      b := FStrip.BandRect;
      cross := (b.Top + b.Bottom) div 2;
      for i := 0 to FStrip.TabCount - 1 do
      begin
        r   := FStrip.TabRect(i);
        mid := (MainLo(r) + MainHi(r)) div 2;
        AssertEquals(who + ': the x-only entry point disagrees with the point form at tab ' +
          IntToStr(i) + ' (back)',
          FStrip.TyDropIndexAtPoint(PtAt(mid - 1, cross), 96),
          FStrip.TyDropIndexAt(mid - 1, 96));
        AssertEquals(who + ': the x-only entry point disagrees with the point form at tab ' +
          IntToStr(i) + ' (forward)',
          FStrip.TyDropIndexAtPoint(PtAt(mid + 1, cross), 96),
          FStrip.TyDropIndexAt(mid + 1, 96));
      end;
    finally
      TearDown;
    end;
  end;
end;

{ `TabHeight = 0` means NO band -- a shipped capability, pinned by
  TPageControlTest.TestTabHeightZeroHidesTheStrip and by the axis suite -- and it makes every
  row ZERO thick. A drop rule that always compares rows would then test `RC < HR.Bottom`
  against a row whose Top and Bottom are equal, which no value satisfies: the scan falls
  through every tab and answers with its default for every point on the strip. Before folding
  the rule never touched the cross axis, so this worked; it has to go on working.

  TyDropIndexAt is pure public API and is NOT behind the HitBandMinor gate that hides the
  rest of a zero-height band, so "nobody can reach it" is not an answer. }
procedure TTabMultiLineTest.AHiddenBandStillResolvesADropByMidpoints;
var
  i, mid: Integer;
  r: TRect;
begin
  Build(tpTop, 4, 400, 300);
  FStrip.TabHeight := 0;
  AssertEquals('TabHeight 0 still means no band at all', 0, FStrip.BandThicknessPx);
  for i := 0 to FStrip.TabCount - 1 do
  begin
    r   := FStrip.TyTabHeaderRect(i);
    mid := (r.Left + r.Right) div 2;
    AssertEquals('one pixel back from tab ' + IntToStr(i) + '''s midpoint',
      i, FStrip.TyDropIndexAt(mid - 1, 96));
    if i < FStrip.TabCount - 1 then
      AssertEquals('one pixel forward of tab ' + IntToStr(i) + '''s midpoint',
        i + 1, FStrip.TyDropIndexAt(mid + 1, 96))
    else
      AssertEquals('forward of the last midpoint stays on the last tab',
        i, FStrip.TyDropIndexAt(mid + 1, 96));
  end;
end;

{ MouseDown and MouseMove run their OWN header scans -- IndexOfTabAt is a third one, so
  proving that one is not proving these. Both were main-axis-only, and a main-only scan finds
  the row-0 tab covering the same main span first: a press on row 1 selects the tab ABOVE it,
  and the hover highlight lands a row out.

  The hover half is asserted through TyTabHoverClose rather than through IndexOfTabAt,
  because that is a value MouseMove itself wrote: a main-only scan stops at the row-0 tab,
  tests THAT tab's close rect against a point on row 1, misses, and reports -1. }
procedure TTabMultiLineTest.PressAndHoverReachTheSecondRow;
var
  i, firstOfRow1: Integer;
  hdr, cls: TRect;
begin
  Build(tpTop, 8, 260, 300, True);
  FStrip.MultiLine := True;
  firstOfRow1 := -1;
  for i := 0 to FStrip.TabCount - 1 do
    if (RowOf(i) = 1) and (firstOfRow1 < 0) then firstOfRow1 := i;
  AssertTrue('the fixture was supposed to put something on row 1', firstOfRow1 > 0);

  FStrip.TabIndex := 0;
  hdr := FStrip.TabRect(firstOfRow1);
  { One pixel inside row 1's leading corner, not its centre, and away from the close slot. }
  FStrip.CallMouseDown(mbLeft, hdr.Left + 1, hdr.Top + 1);
  AssertEquals('a press on row 1 selected a tab from row 0', firstOfRow1, FStrip.TabIndex);

  cls := FStrip.ToScreenRect(FStrip.TyTabCloseRect(firstOfRow1));
  AssertTrue('the fixture needs a close slot on row 1', cls.Right > cls.Left);
  FStrip.CallMouseMove(cls.Left + 1, cls.Top + 1);
  AssertEquals('the close-hover scan never reached row 1',
    firstOfRow1, FStrip.TyTabHoverClose);
  { and leaving row 1 for the same main coordinate on row 0 must NOT keep it lit }
  FStrip.CallMouseMove(cls.Left + 1, 1);
  AssertEquals('the same main coordinate one row up is a different tab',
    -1, FStrip.TyTabHoverClose);
end;

{ === the parts INSIDE a tab travel with it ======================================== }

{ The close glyph's cross coordinate used to be measured from the BAND (`(TabH - size) div 2`
  and `Cross - Margin - size`), which is the row's own edge only while there is one row. Left
  alone, every close button on the strip would pile up on row 0. }
procedure TTabMultiLineTest.TheCloseGlyphTravelsDownToItsOwnRow;
var
  i, firstOfRow1: Integer;
  hdr, cls: TRect;
begin
  Build(tpTop, 8, 260, 300, True);
  FStrip.MultiLine := True;
  firstOfRow1 := -1;
  for i := 0 to FStrip.TabCount - 1 do
    if (RowOf(i) = 1) and (firstOfRow1 < 0) then firstOfRow1 := i;
  AssertTrue('the fixture was supposed to put something on row 1', firstOfRow1 > 0);

  for i := 0 to FStrip.TabCount - 1 do
  begin
    hdr := FStrip.TyTabHeaderRect(i);
    cls := FStrip.TyTabCloseRect(i);
    AssertTrue('tab ' + IntToStr(i) + ' lost its close slot', cls.Right > cls.Left);
    AssertTrue('tab ' + IntToStr(i) + '''s close slot escaped its row (top)',
      cls.Top >= hdr.Top);
    AssertTrue('tab ' + IntToStr(i) + '''s close slot escaped its row (bottom)',
      cls.Bottom <= hdr.Bottom);
    AssertTrue('tab ' + IntToStr(i) + '''s close slot escaped its tab (right)',
      cls.Right <= hdr.Right);
  end;
  { And the load-bearing one: a row-1 close slot is BELOW the first row entirely. }
  AssertTrue('the close glyph stayed on row 0 while its tab moved to row 1',
    FStrip.TyTabCloseRect(firstOfRow1).Top >= RowThick);
end;

{ === side bands =================================================================== }

{ A side band's run goes down the page, so folding it grows a COLUMN. Same statement about
  the cross axis, same code, and the thickness is still RowCount rows -- here, RowCount
  caption boxes wide. }
procedure TTabMultiLineTest.ASideBandFoldsIntoColumns;
var
  oneCol, rows, i: Integer;
  r0, r1: TRect;
begin
  Build(tpLeft, 6, 400, 100);
  oneCol := FStrip.BandThicknessPx;         // one column = the widest caption box
  AssertEquals('an unfolded side band is one column', 1, FStrip.RowCount);

  FStrip.MultiLine := True;
  rows := FStrip.RowCount;
  AssertTrue('a 100px-high band holding 28px rows was supposed to fold', rows > 1);
  AssertEquals('a folded side band is RowCount COLUMNS wide',
    rows * oneCol, FStrip.BandThicknessPx);
  AssertEquals('and the body gives all of them up', rows * oneCol, FStrip.DisplayRect.Left);

  { The first tab of column 1 sits at the TOP of the band again, one column further across. }
  r0 := FStrip.TyTabHeaderRect(0);
  i := 0;
  while (i < FStrip.TabCount) and (FStrip.TyTabHeaderRect(i).Top < oneCol) do Inc(i);
  AssertTrue('nothing reached column 1', i < FStrip.TabCount);
  r1 := FStrip.TyTabHeaderRect(i);
  AssertEquals('column 1 starts at the band''s main origin, like column 0',
    r0.Left, r1.Left);
  AssertEquals('and one column across', oneCol, r1.Top);
end;

{ A subclass's leading inset is band the tab run never gets: the run is DRAWN shifted past it
  (HeaderShiftPx), so a row measured against the full main extent is justified to a width it
  is then pushed out of, and every row overhangs the control by exactly the inset. }
procedure TTabMultiLineTest.AReservedHeadIsRoomTheRowsDoNotGet;
var
  s: TInsetStrip;
  i, rows, lastOfRow0: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(MlCss);
  s := TInsetStrip.Create(FForm);
  s.Parent := FForm;
  s.Controller := FCtl;
  s.Font.PixelsPerInch := 96;
  s.TabHeight := 28;
  s.SetBounds(0, 0, 260, 200);
  for i := 1 to 8 do s.AddCap('Tab ' + IntToStr(i));
  s.MultiLine := True;

  rows := s.RowCount;
  AssertTrue('the fixture was supposed to fold', rows > 1);
  AssertEquals('the run must start after the reserved head', 40, s.TabRect(0).Left);

  lastOfRow0 := -1;
  for i := 0 to s.TabCount - 1 do
    if s.TyTabHeaderRect(i).Top = 0 then lastOfRow0 := i;
  AssertTrue('row 0 has to hold something', lastOfRow0 >= 0);
  AssertEquals('a justified row must end at the control''s edge, not 40px past it',
    s.Width, s.TabRect(lastOfRow0).Right);
  for i := 0 to s.TabCount - 1 do
    AssertTrue('tab ' + IntToStr(i) + ' overhangs the control',
      s.TabRect(i).Right <= s.Width);
end;

{ === the concrete strips ========================================================== }

{ Published on the two concrete strips and NOT on the shared base, exactly as TabPosition is:
  TTyRibbon's File tab, collapse chevron and KeyTip chips are all sized to one row.
  RowCount is read-only and therefore stays public -- TWriter skips a setter-less published
  property and the Object Inspector calls it unreadable. }
procedure TTabMultiLineTest.ThePagerAndTheTabSetPublishIt;
var
  pager: TTyPageControl;
  strip: TTyTabSet;
begin
  AssertTrue('TTyPageControl must publish MultiLine',
    GetPropInfo(TTyPageControl, 'MultiLine') <> nil);
  AssertTrue('TTyPageControl must publish RaggedRight',
    GetPropInfo(TTyPageControl, 'RaggedRight') <> nil);
  AssertTrue('TTyTabSet must publish MultiLine',
    GetPropInfo(TTyTabSet, 'MultiLine') <> nil);
  AssertTrue('TTyTabSet must publish RaggedRight',
    GetPropInfo(TTyTabSet, 'RaggedRight') <> nil);
  AssertTrue('RowCount is read-only, so it must NOT be published',
    GetPropInfo(TTyPageControl, 'RowCount') = nil);
  { `default False` on the base declaration, inherited by the bare re-publish. Without it
    TWriter stores the property unconditionally and EVERY existing .lfm grows two lines the
    next time the designer touches it -- which is why `default` could be written at all here:
    False is simultaneously LCL's default and the "nothing changed" side. Read off the RTTI
    rather than by round-tripping a stream, because this IS the datum TWriter consults. }
  AssertEquals('MultiLine must carry default False into the .lfm rules',
    0, GetPropInfo(TTyPageControl, 'MultiLine')^.Default);
  AssertEquals('RaggedRight must carry default False too',
    0, GetPropInfo(TTyPageControl, 'RaggedRight')^.Default);
  AssertEquals('and the same on the caption-only strip',
    0, GetPropInfo(TTyTabSet, 'MultiLine')^.Default);

  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(MlCss);

  pager := TTyPageControl.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.TabHeight := 28;
  pager.SetBounds(0, 0, 200, 300);
  pager.AddPage('Alpha'); pager.AddPage('Beta'); pager.AddPage('Gamma');
  pager.AddPage('Delta'); pager.AddPage('Epsilon');
  pager.MultiLine := True;
  AssertTrue('the pager was supposed to fold', pager.RowCount > 1);
  AssertEquals('and its pages start below every row',
    pager.RowCount * 28, pager.DisplayRect.Top);

  strip := TTyTabSet.Create(FForm);
  strip.Parent := FForm;
  strip.Controller := FCtl;
  strip.Font.PixelsPerInch := 96;
  strip.TabHeight := 28;
  strip.SetBounds(0, 0, 200, 120);
  strip.Tabs.Add('Alpha'); strip.Tabs.Add('Beta'); strip.Tabs.Add('Gamma');
  strip.Tabs.Add('Delta'); strip.Tabs.Add('Epsilon');
  strip.MultiLine := True;
  AssertTrue('a caption-only strip folds too', strip.RowCount > 1);
  AssertEquals('and its band is RowCount rows', strip.RowCount * 28, strip.BandThicknessPx);
end;

initialization
  RegisterTest(TTabMultiLineTest);
end.
