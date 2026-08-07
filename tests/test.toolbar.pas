unit test.toolbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ImageCollection, tyControls.Menu,
  tyControls.GlyphButtons,   // TTyGlyphLayout + TTySpeedButton — the List tests speak both
  tyControls.DropButtons,    // TyDefaultDropArrowWidth — the drawn-split pixel test names it
  tyControls.ToolBar, tyControls.Button;
type
  TToolBarGeomTest = class(TTestCase)
  published
    procedure TestLayoutSingleRow;
    procedure TestLayoutWraps;
  end;

  { The FORCED row division (TyToolbarLayout's ABreakBefore) — the input TToolButton.Wrap
    needs and the width rule alone can never express. }
  TToolBarBreakTest = class(TTestCase)
  private
    procedure AssertSameLayout(const AWhat: string;
      const AExpect, AGot: TTyRectArray; AExpectRows, AGotRows: Integer);
  published
    procedure TestNoBreakMatchesLegacySignature;
    procedure TestForcedBreakStartsNewRowEvenWhenItFits;
    procedure TestBreakOnFirstItemIsNoOp;
    procedure TestBreakRebasesTheWidthWrap;
    procedure TestBreakWorksWhenNotWrapable;
    procedure TestShortBreakArrayReadsAsFalse;
    procedure TestLclWrapAfterMapsOntoBreakBefore;
  end;

  TTyToolBarAccess = class(TTyToolBar)
  public
    procedure ForceLayout;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TToolBarControlTest = class(TTestCase)
  published
    procedure TestArrangesButtons;
  end;

  { LCL's ButtonWidth rule, pure — the floor's style set and the AutoSize exemption. }
  TToolFloorWidthTest = class(TTestCase)
  published
    procedure TestFloorRaisesNeverCaps;
    procedure TestOnlyLclsThreeStylesAreFloored;
    procedure TestAutoSizeIsExempt;
  end;

  { The bar-level members this batch added, driven through a live (headless) layout. }
  TToolBarMembersTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TTyToolBarAccess;
    function AddTool(AWidth: Integer): TTyToolButton;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // ButtonWidth
    procedure TestFloorWidensNarrowButtonsInTheLayout;
    procedure TestFloorIsAFloorNotACap;
    procedure TestFloorSkipsWhatLclSkips;
    procedure TestLoweringTheFloorRestoresTheNaturalWidth;
    procedure TestHostWidthWrittenWhileFlooredWins;
    // DropDownWidth
    procedure TestDropDownWidthZeroFollowsTheToken;
    procedure TestDropDownWidthPinsZoneHitAndPreferredTogether;
    procedure TestPinnedZoneMovesTheDrawnSplit;
    procedure TestDrawnDividerIsTheFirstHitPixelUnderRealPadding;
    procedure TestSplitDividerIsVisibleOnADefaultFlatBar;
    procedure TestThemeCanRetuneTheRuleAlpha;
    procedure TestRuleInkKeepsABorderedSkinExactlyAsItWas;
    procedure TestButtonDropSharesThePinnedZone;
    // List
    procedure TestListMapsOntoTheGlyphLayouts;
    procedure TestListOffAdoptsTheStackedLayout;
    procedure TestExplicitGlyphLayoutSurvivesTheBar;
    procedure TestExplicitPinsEvenWhenItMatchesTheAdopted;
    procedure TestListDoesNotReachASpeedButton;
  end;

  TToolBarPixelTest = class(TTestCase)
  published
    procedure TestBottomHairlineIsLighterThanBody;
  end;

  { ---- TTyToolButton ------------------------------------------------------- }

  { The pure adjacency-group solver — LCL's GetGroupBounds without a bar, a window or a paint. }
  TToolGroupBoundsTest = class(TTestCase)
  published
    procedure TestUngroupedIsNoGroup;
    procedure TestNonCheckStyleIsNoGroup;
    procedure TestRunExtendsBothWays;
    procedure TestUngroupedNeighbourEndsTheRun;
    procedure TestCommandNeighbourEndsTheRun;
    procedure TestSpaceHolderDoesNotDivideARun;
    procedure TestTwoRunsDoNotMerge;
    procedure TestOutOfRangeAndShortArrays;
  end;

  { The TRAILING-Wrap -> LEADING-break shift, on its own. }
  TToolWrapShiftTest = class(TTestCase)
  published
    procedure TestShiftsByOne;
    procedure TestNeverBreaksOnTheFirst;
    procedure TestDropsTheTrailingWrap;
    procedure TestEmpty;
  end;

  { Drives the protected click/paint/measure seams headlessly, as test.dropbuttons does. }
  TToolButtonAccess = class(TTyToolButton)
  public
    { A real click is MouseDown(X) then Click — LCL synthesises Click after the mouse-up, and
      the arrow-vs-main routing reads the DOWN position. }
    procedure PressAndClickAt(AX: Integer);
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallPreferred(out AW, AH: Integer);
    { The stacked-ink height the size FLOOR is built from. Probed DIRECTLY rather than through
      Constraints.MinHeight: the two styles resolve DIFFERENT theme keys, so their padding
      differs too, and a MinHeight comparison silently measures the padding instead of the
      content — a guard that passed for the wrong reason until a mutant said so. }
    function CallMeasureContentHeight(APPI: Integer): Integer;
    { TComponent.Loading — enters csLoading, which is the window the .lfm reader holds open
      while it writes the streamed properties. Protected there; Loaded is already public on
      TTyButton, so only this end of the pair needs exposing. }
    procedure EnterLoading;
    { The arrow zone in device px — protected on the button; the DropDownWidth tests need
      the number itself, not only the hit test built on it. }
    function CallArrowZoneWidth(APPI: Integer): Integer;
    { The FULL themed composite (frame + content + zone divider), for the pixel test that
      pins the DRAWN split to the same arbitration the hit test reads. DoRenderTo above is
      the space-holder path only. }
    procedure RenderWhole(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The per-state glyph-source seam, so a test can ask WHICH picture a state resolves to
      without having to read it back out of pixels. (The pixel test exists too — this one
      alone would not prove the paint uses the answer.) }
    function CallGlyphSource(AStates: TTyStateSet): TTyGlyphSource;
    { Force the hover flag the way a real mouse-enter would, so CurrentStates reports
      tysHover on a control with no window and no pointer. }
    procedure SetHoverForTest(AValue: Boolean);
    { The resolved border colour, so a test can assert the PRECONDITION of the ghost-divider
      bug (a fully transparent border) instead of assuming it. }
    function CallBorderColor: TTyColor;
    { The resolved right padding, for tests that locate the drawn divider by arithmetic. }
    function CallPadRight: Integer;
  end;

  { The separator control, rendered on the same canvas so its ink can be compared byte for
    byte with a tbsDivider tool button's. }
  TToolSeparatorAccess = class(TTyToolSeparator)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { TTyToolBar.HotImages / DisabledImages — per-state ALTERNATE artwork, keyed by the same
    ImageName as Images.

    They were refused once, on the grounds that the pipeline already tints the icon with the
    state's TextColor so per-state COLOUR is the theme's job. That much still holds and these
    properties do not touch colour. What was left over is per-state SHAPE, which no theme can
    express, and reaching it needed a glyph-source seam in GlyphButtons.pas that did not exist
    yet. It does now (TTyGlyphButtonBase.GetGlyphSource), and this is what it buys.

    Every test below is about the SWAP staying a swap: same name, same slot, declined whenever
    the alternate has nothing to say. TestHoverReallyDrawsTheHotArt is the one that stops these
    from joining the class of published properties the paint quietly ignores. }
  TToolBarStateImagesTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TTyToolBar;
    FTool: TToolButtonAccess;
    FNormal, FHot, FDisabled: TTyImageCollection;
    function MakeHalfMask(ALeft: Boolean): TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHoverSwapsToHotImages;
    procedure TestDisabledOutranksHover;
    procedure TestAlternateMissingTheNameIsDeclined;
    procedure TestToolWithItsOwnCollectionIsLeftAlone;
    procedure TestNoIconNothingToSubstitute;
    procedure TestTheSlotDoesNotMoveWhenTheStateDoes;
    procedure TestHoverReallyDrawsTheHotArt;
    procedure TestFreeingAnAlternateNilsTheReference;
  end;

  TToolButtonTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TTyToolBarAccess;
    FClicks: Integer;
    FArrows: Integer;
    procedure CountClick(Sender: TObject);
    procedure CountArrow(Sender: TObject);
    function AddButton(AStyle: TTyToolButtonStyle; AWidth: Integer): TToolButtonAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { style + geometry }
    procedure TestSpaceHolderStylesTakeTheirLclWidths;
    procedure TestStreamedWidthOutranksTheStylesDefault;
    procedure TestSpaceHolderAsksForNoContentHeight;
    procedure TestSpaceHolderIsNotGivenTheGhostVariant;
    procedure TestArrowStylesReserveTheZoneInThePreferredWidth;
    { the bar's index space }
    procedure TestButtonsListSkipsNonToolChildren;
    procedure TestIndexIsMinusOneOffABar;
    { clicking }
    procedure TestCheckStyleTogglesDown;
    procedure TestPlainStyleDoesNotToggleDown;
    procedure TestSpaceHolderSwallowsTheClick;
    procedure TestArrowZoneClickFiresArrowNotClick;
    procedure TestMainAreaClickFiresClickNotArrow;
    procedure TestMenuSuppressesTheArrowEvent;
    procedure TestButtonDropHasNoArrowZone;
    { grouping }
    procedure TestGroupIsExclusive;
    procedure TestGroupedRadioCannotBeReleasedByHand;
    procedure TestAllowAllUpLetsTheGroupGoUp;
    procedure TestAllowAllUpOffRestoresASelection;
    procedure TestGroupingIgnoresANonToolSibling;
    { icons }
    procedure TestImageIndexIsASpellingOfImageName;
    procedure TestImageIndexSetBeforeTheCollectionSurvivesParenting;
    procedure TestImageIndexSurvivesTheBarGettingItsCollectionLater;
    procedure TestImageIndexSurvivesAnOwnCollectionFixedUpAtLoaded;
    procedure TestImageIndexMinusOneClearsTheIcon;
    procedure TestImageNameOnlyIsNeverClobbered;
    { wrap, through the real bar }
    procedure TestWrapBreaksTheBarsRowAfterTheButton;
    procedure TestWrapOnTheLastButtonAddsNoRow;
    procedure TestInvisibleButtonsWrapIsNotHonoured;
  end;

  { A tbsDivider must draw the SAME ink as the standalone separator control — they resolve one
    typeKey and run one routine, and this is the pixel proof of it. }
  TToolButtonSeparatorPixelTest = class(TTestCase)
  published
    procedure TestDividerInkMatchesTheSeparatorControl;
    procedure TestSeparatorStyleDrawsNoRule;
  end;

implementation

{ TTyToolBarAccess }
procedure TTyToolBarAccess.ForceLayout;
var dummy: TRect;
begin
  // AlignControls uses ClientWidth internally (it ignores the ARect arg); in the headless
  // runner ClientWidth matches TB.Width, so positions are deterministic.
  dummy := Rect(0, 0, Width, Height);
  AlignControls(nil, dummy);
end;

procedure TTyToolBarAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;
procedure TToolBarGeomTest.TestLayoutSingleRow;
var r: TTyRectArray; rows: Integer;
begin
  // two 40x20 items, indent 4, top pad 4, spacing 2, buttonHeight 24, bar 200 wide.
  // Indent (horizontal) and the top pad are separate arguments now -- they used to be one,
  // which is why an indented bar was also a padded, taller one.
  r := TyToolbarLayout([Size(40,20), Size(40,20)], 200, 4, 4, 2, 24, True, rows);
  AssertEquals('rows', 1, rows);
  AssertEquals('i0.left', 4, r[0].Left);     AssertEquals('i0.right', 44, r[0].Right);
  AssertEquals('i1.left', 46, r[1].Left);    AssertEquals('i1.right', 86, r[1].Right);
  AssertEquals('i0.height=buttonHeight', 24, r[0].Bottom - r[0].Top);
end;
procedure TToolBarGeomTest.TestLayoutWraps;
var r: TTyRectArray; rows: Integer;
begin
  // bar only 90 wide -> third item wraps to row 2
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], 90, 4, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('i2 wrapped to indent', 4, r[2].Left);
  AssertEquals('i2.Top = TOP PAD + buttonHeight + spacing', 30, r[2].Top);
end;

{ TToolBarBreakTest }

procedure TToolBarBreakTest.AssertSameLayout(const AWhat: string;
  const AExpect, AGot: TTyRectArray; AExpectRows, AGotRows: Integer);
var
  i: Integer;
begin
  AssertEquals(AWhat + ': item count', Length(AExpect), Length(AGot));
  AssertEquals(AWhat + ': rows', AExpectRows, AGotRows);
  for i := 0 to High(AExpect) do
  begin
    AssertEquals(Format('%s: r[%d].Left', [AWhat, i]), AExpect[i].Left, AGot[i].Left);
    AssertEquals(Format('%s: r[%d].Top', [AWhat, i]), AExpect[i].Top, AGot[i].Top);
    AssertEquals(Format('%s: r[%d].Right', [AWhat, i]), AExpect[i].Right, AGot[i].Right);
    AssertEquals(Format('%s: r[%d].Bottom', [AWhat, i]), AExpect[i].Bottom, AGot[i].Bottom);
  end;
end;

procedure TToolBarBreakTest.TestNoBreakMatchesLegacySignature;
const
  { Includes a degenerate 0-wide bar and a bar narrower than one item, because those are the
    inputs where a rewritten wrap condition is most likely to drift. }
  BarWidths: array[0..4] of Integer = (0, 33, 46, 90, 200);
  { Four width profiles: uniform, one over-wide item mid-run, all-too-wide, and a trailing
    monster after three tiny ones. }
  Profiles: array[0..3, 0..3] of Integer = (
    (40, 40, 40, 40),
    (10, 100, 10, 10),
    (60, 60, 60, 60),
    (5,  5,   5,  200));
var
  pi_, bi, ni, mi, i: Integer;
  sizes: array of TSize;
  allFalse, emptyBrk: array of Boolean;
  legacy, viaEmpty, viaFalse: TTyRectArray;
  rowsL, rowsE, rowsF: Integer;
  wrapable: Boolean;
  indent, pad, spacing, bh: Integer;
  tag: string;
begin
  { BYTE-IDENTITY GUARD. Every existing toolbar in the suite goes through the break-free
    entry point, so the one thing this change must not do is move a single pixel when no flag
    is set. The two forms are compared rect-field for rect-field (and on ARows, which is what
    the bar's auto-grown HEIGHT is computed from) across a matrix: 2 metric sets x 4 width
    profiles x 5 bar widths x item counts 0..4 x both Wrapable states = 800 layouts.
    Both "no array at all" and "an array of all False" are checked -- they reach the rule by
    different paths (a short-array read vs. a real False) and only one of them can be got
    wrong. }
  emptyBrk := nil;
  for mi := 0 to 1 do
  begin
    if mi = 0 then begin indent := 4;  pad := 4; spacing := 2; bh := 24; end
              else begin indent := 20; pad := 3; spacing := 0; bh := 38; end;
    for pi_ := 0 to High(Profiles) do
      for bi := 0 to High(BarWidths) do
        for ni := 0 to 4 do
          for wrapable := False to True do
          begin
            SetLength(sizes, ni);
            SetLength(allFalse, ni);
            for i := 0 to ni - 1 do
            begin
              sizes[i].cx := Profiles[pi_][i mod 4];
              sizes[i].cy := 20;
              allFalse[i] := False;
            end;
            tag := Format('profile%d/bar%d/n%d/wrapable%d/metrics%d',
              [pi_, BarWidths[bi], ni, Ord(wrapable), mi]);
            legacy   := TyToolbarLayout(sizes, BarWidths[bi], indent, pad, spacing, bh, wrapable, rowsL);
            viaEmpty := TyToolbarLayout(sizes, emptyBrk, BarWidths[bi], indent, pad, spacing, bh, wrapable, rowsE);
            viaFalse := TyToolbarLayout(sizes, allFalse, BarWidths[bi], indent, pad, spacing, bh, wrapable, rowsF);
            AssertSameLayout(tag + ' [empty break array]', legacy, viaEmpty, rowsL, rowsE);
            AssertSameLayout(tag + ' [all-False break array]', legacy, viaFalse, rowsL, rowsF);
          end;
  end;
end;

procedure TToolBarBreakTest.TestForcedBreakStartsNewRowEvenWhenItFits;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { Three 40px tools on a 200px bar all fit on one row -- TestLayoutSingleRow's arithmetic with
    one more tool. A break on tool 1 must move it down ANYWAY. That is the whole point of the
    parameter: a division the width never demanded. }
  SetLength(brk, 3);
  brk[0] := False; brk[1] := True; brk[2] := False;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 200, 4, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('i0 stays on row 1, at the indent', 4, r[0].Left);
  AssertEquals('i0.Top = top pad', 4, r[0].Top);
  AssertEquals('i1 restarts at the indent', 4, r[1].Left);
  AssertEquals('i1.Top = pad + buttonHeight + spacing', 30, r[1].Top);
  AssertEquals('i2 follows i1 on the NEW row', 46, r[2].Left);
  AssertEquals('i2 shares i1''s row', 30, r[2].Top);
end;

procedure TToolBarBreakTest.TestBreakOnFirstItemIsNoOp;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { There is no row above the first tool to leave, so a break on it is ignored rather than
    opening an empty leading row. An empty row would be visible twice over: a blank band at the
    top, AND a bar one button-height taller, because ARows is exactly what AlignControls sizes
    the bar from (padY*2 + rows*bh + (rows-1)*spacing). }
  SetLength(brk, 2);
  brk[0] := True; brk[1] := False;
  r := TyToolbarLayout([Size(40,20), Size(40,20)], brk, 200, 4, 4, 2, 24, True, rows);
  AssertEquals('still ONE row -- no empty leading row', 1, rows);
  AssertEquals('i0.Left', 4, r[0].Left);
  AssertEquals('i0.Top = top pad, not pad + a row', 4, r[0].Top);
  AssertEquals('i1.Left', 46, r[1].Left);
  AssertEquals('i1.Top', 4, r[1].Top);
end;

procedure TToolBarBreakTest.TestBreakRebasesTheWidthWrap;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { The same bar as TestLayoutWraps -- 90 wide, three 40px tools -- where the WIDTH alone puts
    tool 2 on row 2. Break tool 1 instead and the two rules compose: tool 1 opens row 2, which
    re-bases x to the indent, so tool 2 now FITS beside it and the width rule does not fire at
    all. A break that inserted a row without re-basing x would strand tool 2 on a third row,
    which is the failure this pins. }
  SetLength(brk, 3);
  brk[0] := False; brk[1] := True; brk[2] := False;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 90, 4, 4, 2, 24, True, rows);
  AssertEquals('two rows, not three', 2, rows);
  AssertEquals('i1 opened row 2 at the indent', 4, r[1].Left);
  AssertEquals('i1.Top', 30, r[1].Top);
  AssertEquals('i2 fits beside i1 on row 2', 46, r[2].Left);
  AssertEquals('i2.Top', 30, r[2].Top);
end;

procedure TToolBarBreakTest.TestBreakWorksWhenNotWrapable;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { AWrapable=False is LCL's "no automatic wrap" mode, and it is the ONLY mode in which LCL
    reads TToolButton.Wrap at all (toolbar.inc:1003, `if not Wrapable and ... Wrap`). So the
    break must be live here even though the width rule is dead.
    First half: confirm the width rule really is off -- three 40px tools on a 90px bar stay on
    one row and the last one overhangs. Without this the second half would pass for the wrong
    reason. }
  SetLength(brk, 3);
  brk[0] := False; brk[1] := False; brk[2] := False;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 90, 4, 4, 2, 24, False, rows);
  AssertEquals('width rule off: one row', 1, rows);
  AssertEquals('i2 overhangs rather than wrapping', 88, r[2].Left);
  AssertEquals('i2 stayed on row 1', 4, r[2].Top);

  brk[2] := True;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 90, 4, 4, 2, 24, False, rows);
  AssertEquals('the break divides even with the width rule off', 2, rows);
  AssertEquals('i2 opened row 2', 4, r[2].Left);
  AssertEquals('i2.Top', 30, r[2].Top);
  AssertEquals('i1 was left where it was', 46, r[1].Left);
  AssertEquals('i1.Top', 4, r[1].Top);
end;

procedure TToolBarBreakTest.TestShortBreakArrayReadsAsFalse;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { The flag array is parallel to the item list but need not be as long -- the same tolerance
    TyCoolBarPack's ABreaks has. Two entries against three tools, with the True in the LAST
    supplied slot: a bound read as <= instead of < would run one past the end here, and a bound
    read as one too tight would drop the flag that IS supplied. }
  SetLength(brk, 2);
  brk[0] := False; brk[1] := True;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 200, 4, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('the supplied break fired', 4, r[1].Left);
  AssertEquals('i1.Top', 30, r[1].Top);
  AssertEquals('the missing entry read as False -- no third row', 46, r[2].Left);
  AssertEquals('i2.Top', 30, r[2].Top);
end;

procedure TToolBarBreakTest.TestLclWrapAfterMapsOntoBreakBefore;
var
  r: TTyRectArray; rows, i: Integer;
  wrapAfter, breakBefore: array of Boolean;
begin
  { THE SHIFT, pinned. LCL's TToolButton.Wrap is TRAILING -- "the row breaks AFTER this button"
    -- because toolbar.inc applies it in the step-to-next-position, so it moves the NEXT
    control. This solver's flag is LEADING, matching TyCoolBarPack. The conversion is the one
    place TToolButton can go off by one, so here is the worked example it should copy:
        breakBefore[i] := (i > 0) and wrapAfter[i-1]
    Two things the mapping deliberately cannot express. It never produces breakBefore[0]:
    there is no button -1 to trail, and a leading break on tool 0 is a no-op regardless. And it
    DROPS wrapAfter on the last button: LCL still bumps FRowCount for that one and ends up
    reporting a row that has nothing on it. }
  SetLength(wrapAfter, 3);
  wrapAfter[0] := False; wrapAfter[1] := True; wrapAfter[2] := True;   // Wrap set on tools 1 and 2
  SetLength(breakBefore, Length(wrapAfter));
  for i := 0 to High(breakBefore) do
    breakBefore[i] := (i > 0) and wrapAfter[i - 1];
  AssertEquals('tool 0 can never carry a leading break', False, breakBefore[0]);
  AssertEquals('tool 1 does not either -- tool 0 had no Wrap', False, breakBefore[1]);
  AssertEquals('tool 1''s trailing Wrap becomes tool 2''s leading break', True, breakBefore[2]);

  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], breakBefore, 200, 4, 4, 2, 24, True, rows);
  AssertEquals('two rows -- the Wrap on the LAST tool adds none', 2, rows);
  AssertEquals('i0 on row 1', 4, r[0].Top);
  AssertEquals('i1 on row 1 -- its own Wrap breaks AFTER it', 4, r[1].Top);
  AssertEquals('i1.Left', 46, r[1].Left);
  AssertEquals('i2 opened row 2', 30, r[2].Top);
  AssertEquals('i2.Left', 4, r[2].Left);
end;

{ TToolBarControlTest }

procedure TToolBarControlTest.TestArrangesButtons;
var
  Form: TForm;
  TB: TTyToolBarAccess;
  B1, B2: TTyButton;
  ExpectedLeft: Integer;
begin
  // In headless LCL, Realign posts a deferred message that is never processed
  // without a message pump.  We use a thin probe subclass (TTyToolBarAccess)
  // that calls AlignControls directly, bypassing the deferred path.
  // Width is set explicitly so ClientWidth is a known bar width; AlignControls
  // uses ClientWidth internally (it ignores the ARect arg), so positions are deterministic.
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 200);

    TB := TTyToolBarAccess.Create(Form);
    TB.Parent := Form;
    // alNone: prevent LCL alignment engine from fighting our explicit bounds
    TB.Align := alNone;
    TB.Width := 300;
    TB.Indent := 4;
    TB.ButtonSpacing := 2;
    TB.ButtonHeight := 24;
    TB.Wrapable := True;

    B1 := TTyButton.Create(Form);
    B1.Parent := TB;
    B1.Width := 60;

    B2 := TTyButton.Create(Form);
    B2.Parent := TB;
    B2.Width := 60;

    // Direct synchronous layout call (probe exposes the protected AlignControls).
    // The dummy rect uses TB.Width so the bar-width is 300 and no wrapping occurs.
    TB.ForceLayout;

    // Button 1 should start at Indent; Button 2 right after: Indent + B1.Width + ButtonSpacing
    AssertEquals('b1.Left = indent', TB.Indent, B1.Left);
    ExpectedLeft := TB.Indent + B1.Width + TB.ButtonSpacing;
    AssertEquals('b2.Left = indent + b1.width + spacing', ExpectedLeft, B2.Left);
  finally
    Form.Free;
  end;
end;

{ ---- TToolFloorWidthTest --------------------------------------------------- }

procedure TToolFloorWidthTest.TestFloorRaisesNeverCaps;
begin
  AssertEquals('narrower than the floor -> the floor', 60, TyToolFloorWidth(23, 60, tbsButton, False));
  AssertEquals('wider than the floor -> its own width', 80, TyToolFloorWidth(80, 60, tbsButton, False));
  AssertEquals('exactly the floor', 60, TyToolFloorWidth(60, 60, tbsButton, False));
  AssertEquals('no floor set (0) is the identity', 23, TyToolFloorWidth(23, 0, tbsButton, False));
  AssertEquals('a negative floor is no floor', 23, TyToolFloorWidth(23, -5, tbsButton, False));
end;

procedure TToolFloorWidthTest.TestOnlyLclsThreeStylesAreFloored;
begin
  { LCL's CalculatePosition floors [tbsButton, tbsDropDown, tbsCheck] and nothing else —
    its own list EXCLUDES tbsButtonDrop, and the port mirrors the list rather than
    "improving" it so a form moved between the two toolkits lays out the same. }
  AssertEquals('tbsButton floored', 60, TyToolFloorWidth(23, 60, tbsButton, False));
  AssertEquals('tbsCheck floored', 60, TyToolFloorWidth(23, 60, tbsCheck, False));
  AssertEquals('tbsDropDown floored', 60, TyToolFloorWidth(23, 60, tbsDropDown, False));
  AssertEquals('tbsButtonDrop is NOT (LCL excludes it)', 23, TyToolFloorWidth(23, 60, tbsButtonDrop, False));
  AssertEquals('tbsSeparator keeps its space-holder width', 8, TyToolFloorWidth(8, 60, tbsSeparator, False));
  AssertEquals('tbsDivider too', 5, TyToolFloorWidth(5, 60, tbsDivider, False));
end;

procedure TToolFloorWidthTest.TestAutoSizeIsExempt;
begin
  // An AutoSize button hugs its content — LCL's `not CurControl.AutoSize` condition.
  AssertEquals('AutoSize wins over the floor', 23, TyToolFloorWidth(23, 60, tbsButton, True));
end;

{ ---- TToolBarMembersTest --------------------------------------------------- }

procedure TToolBarMembersTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 500, 200);
  FBar := TTyToolBarAccess.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alNone;   // keep the LCL align engine off our explicit bounds
  FBar.SetBounds(0, 0, 400, 30);
end;

procedure TToolBarMembersTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TToolBarMembersTest.AddTool(AWidth: Integer): TTyToolButton;
begin
  Result := TTyToolButton.Create(FForm);
  Result.Parent := FBar;
  Result.Width := AWidth;
end;

procedure TToolBarMembersTest.TestFloorWidensNarrowButtonsInTheLayout;
var
  a, b: TTyToolButton;
begin
  a := AddTool(23);
  b := AddTool(23);
  FBar.ButtonWidth := 60;
  FBar.ForceLayout;
  AssertEquals('first button laid out at the floor', 60, a.Width);
  AssertEquals('second too', 60, b.Width);
  AssertEquals('and the second slot starts past the FLOORED first',
    FBar.Indent + 60 + FBar.ButtonSpacing, b.Left);
end;

procedure TToolBarMembersTest.TestFloorIsAFloorNotACap;
var
  a: TTyToolButton;
begin
  a := AddTool(90);
  FBar.ButtonWidth := 60;
  FBar.ForceLayout;
  AssertEquals('a wider button keeps its own width', 90, a.Width);
end;

procedure TToolBarMembersTest.TestFloorSkipsWhatLclSkips;
var
  chk, drp, bdrop, sep: TTyToolButton;
  plain: TTyButton;
begin
  { 40-wide naturals, NOT 23: an arrow style's own content minimum (theme padding + the
    ~18px arrow zone) is near 30, and a natural below it would be raised by the
    Constraints clamp — the assertion would then measure the content floor, not the
    ButtonWidth exclusion it is here to pin. }
  chk := AddTool(40);   chk.Style := tbsCheck;
  drp := AddTool(40);   drp.Style := tbsDropDown;
  bdrop := AddTool(40); bdrop.Style := tbsButtonDrop;
  sep := AddTool(40);   sep.Style := tbsSeparator;   // SetStyle snaps it to 8
  plain := TTyButton.Create(FForm);
  plain.Parent := FBar;
  plain.Width := 40;
  FBar.ButtonWidth := 60;
  FBar.ForceLayout;
  AssertEquals('tbsCheck floored', 60, chk.Width);
  AssertEquals('tbsDropDown floored', 60, drp.Width);
  AssertEquals('tbsButtonDrop kept (LCL''s own exclusion)', 40, bdrop.Width);
  AssertEquals('a separator keeps its space-holder width', 8, sep.Width);
  AssertEquals('a non-tool child is never touched', 40, plain.Width);
end;

procedure TToolBarMembersTest.TestLoweringTheFloorRestoresTheNaturalWidth;
var
  a: TTyToolButton;
begin
  { THE reversibility rule — LCL gets it free by recomputing every width from content; here
    a width is a designed value, so the bar REMEMBERS what it lent (the FLentImages pattern
    in width space) and hands it back when the floor drops. Without the memory this test's
    last assertion reads 60: the floor would be a ratchet that permanently rewrites .lfm
    widths the moment a designer tries a value. }
  a := AddTool(23);
  FBar.ButtonWidth := 60;
  FBar.ForceLayout;
  AssertEquals('floored', 60, a.Width);
  FBar.ButtonWidth := 0;
  FBar.ForceLayout;
  AssertEquals('lowering the floor restores the designed width', 23, a.Width);
end;

procedure TToolBarMembersTest.TestHostWidthWrittenWhileFlooredWins;
var
  a: TTyToolButton;
begin
  a := AddTool(23);
  FBar.ButtonWidth := 60;
  FBar.ForceLayout;
  AssertEquals('floored', 60, a.Width);
  a.Width := 100;         // the host makes a NEW choice while the floor is in force
  FBar.ForceLayout;
  AssertEquals('the host''s wider width is honoured', 100, a.Width);
  FBar.ButtonWidth := 0;
  FBar.ForceLayout;
  AssertEquals('and it IS the natural width now — not the pre-floor 23', 100, a.Width);
end;

procedure TToolBarMembersTest.TestDropDownWidthZeroFollowsTheToken;
var
  a: TToolButtonAccess;
  tokenW: Integer;
begin
  a := TToolButtonAccess.Create(FForm);
  a.Parent := FBar;
  a.Style := tbsDropDown;
  tokenW := a.CallArrowZoneWidth(96);   // whatever the theme token resolves to today
  AssertTrue('the token gives the zone SOME width', tokenW > 0);
  FBar.DropDownWidth := tokenW + 13;
  AssertEquals('a pinned bar overrides the token', tokenW + 13, a.CallArrowZoneWidth(96));
  FBar.DropDownWidth := 0;
  AssertEquals('0 hands the zone back to the token', tokenW, a.CallArrowZoneWidth(96));
  FBar.DropDownWidth := -7;
  AssertEquals('negative clamps to the one auto value', 0, FBar.DropDownWidth);
end;

procedure TToolBarMembersTest.TestDropDownWidthPinsZoneHitAndPreferredTogether;
var
  a: TToolButtonAccess;
  w0, h0, w1, h1, zone0, zone1: Integer;
begin
  { The zone is ONE arbitrated number: the drawn chevron zone, the tbsDropDown hit test and
    the preferred width must all move by the same delta, or a pinned bar would draw one
    split and click another. The zone is read at the button's OWN Font.PixelsPerInch — the
    PPI CalculatePreferredSize measures at — because the fixture's PPI is the machine's,
    not necessarily 96, and an assumed 96 here measured the runner instead of the code. }
  a := TToolButtonAccess.Create(FForm);
  a.Parent := FBar;
  a.Style := tbsDropDown;
  a.Width := 100;
  zone0 := a.CallArrowZoneWidth(a.Font.PixelsPerInch);
  a.CallPreferred(w0, h0);
  FBar.DropDownWidth := 40;
  zone1 := a.CallArrowZoneWidth(a.Font.PixelsPerInch);
  a.CallPreferred(w1, h1);
  AssertTrue('pinning really widened the zone', zone1 > zone0);
  AssertEquals('the preferred width moved by exactly the zone delta', zone1 - zone0, w1 - w0);
  { The hit test reads the same arbitration: a point just inside the pinned zone's inner
    edge is IN, and out again when the pin narrows. PointInArrow measures device px from
    the right edge at the button's own PPI, which zone1 already is. }
  AssertTrue('a point just inside the pinned zone hits',
    a.PointInArrow(a.Width - zone1 + 2, a.Height div 2));
  FBar.DropDownWidth := 10;
  AssertFalse('...and misses once the zone is pinned narrower',
    a.PointInArrow(a.Width - zone1 + 2, a.Height div 2));
end;

procedure TToolBarMembersTest.TestPinnedZoneMovesTheDrawnSplit;
const
  W = 100; H = 24;
var
  Ctl: TTyStyleController;
  a: TToolButtonAccess;
  img: TBGRABitmap;

  function ColumnHasDividerInk(AX: Integer): Boolean;
  var
    y: Integer;
    P: TBGRAPixel;
  begin
    Result := False;
    for y := 0 to H - 1 do
    begin
      P := img.GetPixel(AX, y);
      if (P.green > 160) and (P.red < 96) and (P.blue < 96) then Exit(True);
    end;
  end;

  { A FRESH target each render: reading a TBitmap back through BGRA detaches its canvas DC,
    so a second render into the same bitmap can land somewhere other than the pixels read
    (the trap test.parity.onpaint documents). }
  procedure Render;
  var
    bmp: TBitmap;
  begin
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(W, H);
      bmp.Canvas.Brush.Style := bsSolid;
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, W, H);
      a.RenderWhole(bmp.Canvas, Rect(0, 0, W, H), 96);
      FreeAndNil(img);
      img := TBGRABitmap.Create(bmp);
    finally
      bmp.Free;
    end;
  end;

begin
  { The DRAWN half of the arbitration: DrawContent re-derives the zone width to place the
    1px split divider, and re-deriving it from the raw token instead of the shared
    DropArrowLogicalWidth would draw the split in one place and hit-test another — the
    "drawn right, answers left" bug this library has been bitten by three times. The theme
    below zeroes padding and paints the divider (border-color) pure green on black, so the
    divider column is the only green ink and its x IS the zone's inner edge. }
  Ctl := TTyStyleController.Create(nil);
  img := nil;
  try
    Ctl.LoadThemeCss('TyButton { background: #000000; color: #FF0000; ' +
      'border-color: #00FF00; border-width: 0px; padding: 0px; font-size: 14px; }');
    a := TToolButtonAccess.Create(FForm);
    a.Parent := FBar;
    a.Controller := Ctl;
    a.Font.PixelsPerInch := 96;   // Scale() 1:1, so logical == device px
    a.Style := tbsDropDown;
    a.SetBounds(0, 0, W, H);

    FBar.DropDownWidth := 40;
    Render;
    AssertTrue('pinned 40: the split divider sits at x = W-40', ColumnHasDividerInk(W - 40));
    AssertFalse('...and not at the token''s inner edge',
      ColumnHasDividerInk(W - TyDefaultDropArrowWidth));

    FBar.DropDownWidth := 0;
    Render;
    AssertTrue('token again: the divider is back at the token''s inner edge',
      ColumnHasDividerInk(W - TyDefaultDropArrowWidth));
    AssertFalse('...and gone from W-40', ColumnHasDividerInk(W - 40));
    a.Free;   // before its controller
  finally
    img.Free;
    Ctl.Free;
  end;
end;

procedure TToolBarMembersTest.TestDrawnDividerIsTheFirstHitPixelUnderRealPadding;
const
  W = 140; H = 28; ArrowW = 18; PadX = 10;
var
  Ctl: TTyStyleController;
  a: TToolButtonAccess;
  img: TBGRABitmap;
  bmp: TBitmap;
  x, y, divX: Integer;
  P: TBGRAPixel;
begin
  { The twin of test.dropbuttons' TDropArrowZoneEdgeTest, on the OTHER control that shares the
    rule — both had to be corrected in one change, so both have to be pinned or the next
    person can fix one and re-split the pair.

    TestPinnedZoneMovesTheDrawnSplit above deliberately zeroes the padding to make its
    arithmetic plain. That is exactly the condition under which the drawn zone and a
    control-edge-relative zone COINCIDE — so it could never have seen this bug. This one uses
    a real 10px horizontal padding and probes the boundary a pixel at a time. }
  Ctl := TTyStyleController.Create(nil);
  img := nil;
  try
    Ctl.LoadThemeCss(Format(':root { --drop-arrow-width: %dpx; }' +
      'TyButton { background: #000000; color: #FF0000; border-color: #00FF00; ' +
      'border-width: 0px; padding: 4px %dpx; font-size: 12px; }', [ArrowW, PadX]));
    a := TToolButtonAccess.Create(FForm);
    a.Parent := FBar;
    a.Controller := Ctl;
    a.Font.PixelsPerInch := 96;   // Scale() 1:1, so logical == device px
    a.Style := tbsDropDown;
    a.SetBounds(0, 0, W, H);

    // Read the divider's column out of a real render — never from the code's own arithmetic.
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(W, H);
      bmp.Canvas.Brush.Style := bsSolid;
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, W, H);
      a.RenderWhole(bmp.Canvas, Rect(0, 0, W, H), 96);
      img := TBGRABitmap.Create(bmp);
    finally
      bmp.Free;
    end;
    divX := -1;
    for x := 0 to W - 1 do
    begin
      for y := 0 to H - 1 do
      begin
        P := img.GetPixel(x, y);
        if (P.green > 160) and (P.red < 96) and (P.blue < 96) then
        begin
          divX := x;
          Break;
        end;
      end;
      if divX >= 0 then Break;
    end;
    AssertTrue('sanity: the tbsDropDown drew its split divider', divX >= 0);
    { Stated as a number so the gap is visible in the source: the zone opens one arrow-width
      in from the CONTENT edge (140-10-18 = 112). Measuring from the control edge would put
      it at 122 — ten px of drawn arrow, divider included, that ran the primary action. }
    AssertEquals('the divider sits one right-padding in from the control edge',
      W - PadX - ArrowW, divX);

    // THE EDGE PROBE: one px either side of the drawn boundary, never the middle.
    AssertTrue('the drawn divider IS the first pixel PointInArrow answers True for',
      a.PointInArrow(divX, H div 2));
    AssertFalse('and one px to its left is still the main area',
      a.PointInArrow(divX - 1, H div 2));
    AssertTrue('the control''s last pixel is in the zone too',
      a.PointInArrow(W - 1, H div 2));
    a.Free;   // before its controller
  finally
    img.Free;
    Ctl.Free;
  end;
end;

procedure TToolBarMembersTest.TestSplitDividerIsVisibleOnADefaultFlatBar;
const
  W = 140; H = 28; ArrowW = 18; PadX = 10;
var
  Ctl: TTyStyleController;
  a: TToolButtonAccess;
  img: TBGRABitmap;
  bmp: TBitmap;
  divX, padR, y: Integer;
  darkOnRule, darkBeside: Integer;
  P: TBGRAPixel;

  function Luma(const APix: TBGRAPixel): Integer;
  begin
    Result := (APix.red + APix.green + APix.blue) div 3;
  end;

begin
  { THE DEFAULT CONFIGURATION, which is where this was broken. Flat defaults to True, a flat bar
    stamps 'ghost' on every tool, and ghost's border is deliberately fully transparent
    (light.tycss: `alpha(var(--border), 0)`) — so the split divider, drawn in AStyle.BorderColor,
    was drawn in NOTHING. A tbsDropDown and a tbsButtonDrop then looked identical on screen while
    routing a click on the button body to two different places.

    The theme below reproduces exactly that: a ghost variant with a transparent border and a
    black text colour on a white backdrop. Both preconditions are ASSERTED rather than assumed,
    because if a future theme edit gave ghost a real border this test would still pass while
    testing nothing. }
  Ctl := TTyStyleController.Create(nil);
  img := nil;
  try
    Ctl.LoadThemeCss(Format(
      ':root { --drop-arrow-width: %dpx; }' +
      'TyButton { background: alpha(#FFFFFF, 0); color: #000000; border-color: #00FF00; ' +
      '  border-width: 0px; padding: 4px %dpx; font-size: 12px; }' +
      'TyButton.ghost { background: alpha(#FFFFFF, 0); color: #000000; ' +
      '  border-color: alpha(#00FF00, 0); border-width: 0px; padding: 4px %dpx; ' +
      '  font-size: 12px; }', [ArrowW, PadX, PadX]));
    FBar.Controller := Ctl;
    AssertTrue('sanity: a tool bar is flat by DEFAULT — that is what makes this the '
      + 'default configuration', FBar.Flat);

    a := TToolButtonAccess.Create(FForm);
    a.Parent := FBar;
    a.Controller := Ctl;
    a.Font.PixelsPerInch := 96;
    a.Style := tbsDropDown;
    a.Caption := '';          // no caption ink to confuse the column comparison
    a.SetBounds(0, 0, W, H);
    FBar.ForceLayout;         // this is what stamps 'ghost' on the tools

    AssertEquals('the flat bar really did hand this tool the ghost variant',
      'ghost', a.StyleClass);
    AssertEquals('and ghost really does resolve a FULLY TRANSPARENT border — the exact '
      + 'condition that used to make the divider invisible', 0, TyAlphaOf(a.CallBorderColor));

    padR := a.CallPadRight;
    divX := W - padR - ArrowW;

    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(W, H);
      bmp.Canvas.Brush.Style := bsSolid;
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, W, H);
      a.RenderWhole(bmp.Canvas, Rect(0, 0, W, H), 96);
      img := TBGRABitmap.Create(bmp);
    finally
      bmp.Free;
    end;

    { EDGE probe, on the divider's own column and the column two to its left (plain button
      face). "Visible" is stated as what it actually means: this column is measurably darker
      than the face beside it. Return the ink to AStyle.BorderColor and the two columns become
      identical — which is exactly the mutant. }
    { Scanned across the button's vertical MIDDLE only. The frame's rounded corners are
      antialiased against the backdrop, so a full-height scan would pick up corner ink in the
      comparison column and compare the divider against that instead of against the face. }
    darkOnRule := 255;
    darkBeside := 255;
    for y := (H div 2) - 2 to (H div 2) + 2 do
    begin
      P := img.GetPixel(divX, y);
      if Luma(P) < darkOnRule then darkOnRule := Luma(P);
      P := img.GetPixel(divX - 2, y);
      if Luma(P) < darkBeside then darkBeside := Luma(P);
    end;
    { The face is the BAR's surface showing through the ghost button's transparent background
      (TyFillParentBg), not the white the bitmap was cleared to — so this is "light and
      uninked", not "255". What matters is that it carries no ink of its own to compare against. }
    AssertTrue(Format('the button face beside the divider is uninked (luma %d)',
      [darkBeside]), darkBeside > 200);
    AssertTrue(Format('the split divider must be VISIBLE on a default flat bar: its column '
      + 'reads luma %d against a face of %d', [darkOnRule, darkBeside]),
      darkOnRule < darkBeside - 20);
    a.Free;
    FBar.Controller := nil;
  finally
    img.Free;
    Ctl.Free;
  end;
end;

procedure TToolBarMembersTest.TestThemeCanRetuneTheRuleAlpha;
const
  W = 140; H = 28; ArrowW = 18; PadX = 10;
var
  Ctl: TTyStyleController;
  a: TToolButtonAccess;
  img: TBGRABitmap;
  bmp: TBitmap;
  divX, y, darkest: Integer;
  P: TBGRAPixel;
begin
  { The docs promise a skin can retune the fallback rule (or suppress it with 0) through
    '--tool-rule-alpha' without any control-code change. That is a claim about plumbing that
    has to be exercised, not asserted in prose: the metric goes through TyEvalLength, and a
    token it cannot parse would silently fall back to the default and nobody would notice.
    200/255 over the bar's face is unmistakably darker than the default 50/255. }
  Ctl := TTyStyleController.Create(nil);
  img := nil;
  try
    Ctl.LoadThemeCss(Format(
      ':root { --drop-arrow-width: %dpx; --tool-rule-alpha: 200; }' +
      'TyButton.ghost { background: alpha(#FFFFFF, 0); color: #000000; ' +
      '  border-color: alpha(#00FF00, 0); border-width: 0px; padding: 4px %dpx; ' +
      '  font-size: 12px; }', [ArrowW, PadX]));
    AssertEquals('sanity: the theme''s metric is readable at all (a unit-less token must '
      + 'parse, or the control silently keeps the default)',
      200, Ctl.Metric(TyToolRuleAlphaVar, TyToolRuleGhostAlpha));

    FBar.Controller := Ctl;
    a := TToolButtonAccess.Create(FForm);
    a.Parent := FBar;
    a.Controller := Ctl;
    a.Font.PixelsPerInch := 96;
    a.Style := tbsDropDown;
    a.Caption := '';
    a.SetBounds(0, 0, W, H);
    FBar.ForceLayout;
    AssertEquals('sanity: still the ghost variant', 'ghost', a.StyleClass);
    divX := W - a.CallPadRight - ArrowW;

    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(W, H);
      bmp.Canvas.Brush.Style := bsSolid;
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, W, H);
      a.RenderWhole(bmp.Canvas, Rect(0, 0, W, H), 96);
      img := TBGRABitmap.Create(bmp);
    finally
      bmp.Free;
    end;

    darkest := 255;
    for y := (H div 2) - 2 to (H div 2) + 2 do
    begin
      P := img.GetPixel(divX, y);
      if ((P.red + P.green + P.blue) div 3) < darkest then
        darkest := (P.red + P.green + P.blue) div 3;
    end;
    { At the default 50/255 this column reads about 193 against the bar's ~240 face; at
      200/255 it is about 52. A threshold of 100 cannot be reached by the default. }
    AssertTrue(Format('the themed alpha really reached the paint (divider luma %d)',
      [darkest]), darkest < 100);
    a.Free;
    FBar.Controller := nil;
  finally
    img.Free;
    Ctl.Free;
  end;
end;

procedure TToolBarMembersTest.TestRuleInkKeepsABorderedSkinExactlyAsItWas;
var
  S: TTyStyleSet;
begin
  { The pure rule, both branches. A skin that draws a real border must come through BYTE for
    byte — the fallback exists for the transparent case and must never touch the other one. }
  S := Default(TTyStyleSet);
  S.BorderColor := TyRGBA(17, 34, 51, 255);
  S.TextColor := TyRGBA(255, 0, 0, 255);
  AssertEquals('an opaque border is used exactly as the theme stated it',
    Int64(TyRGBA(17, 34, 51, 255)), Int64(TyToolRuleInk(S, TyToolRuleGhostAlpha)));

  // Even a barely-there border is still the THEME speaking; only alpha 0 means "no ink".
  S.BorderColor := TyRGBA(17, 34, 51, 1);
  AssertEquals('alpha 1 is a border, not an absence',
    Int64(TyRGBA(17, 34, 51, 1)), Int64(TyToolRuleInk(S, TyToolRuleGhostAlpha)));

  S.BorderColor := TyRGBA(17, 34, 51, 0);
  AssertEquals('a fully transparent border falls back to the TEXT colour, dimmed',
    Int64(TyRGBA(255, 0, 0, TyToolRuleGhostAlpha)),
    Int64(TyToolRuleInk(S, TyToolRuleGhostAlpha)));
  AssertEquals('the dim factor is the caller''s (the theme metric), not a constant here',
    Int64(TyRGBA(255, 0, 0, 200)), Int64(TyToolRuleInk(S, 200)));
  AssertEquals('a theme may suppress the rule entirely with 0',
    Int64(TyRGBA(255, 0, 0, 0)), Int64(TyToolRuleInk(S, 0)));
end;

procedure TToolBarMembersTest.TestButtonDropSharesThePinnedZone;
var
  a: TToolButtonAccess;
begin
  // LCL keys tbsButtonDrop's arrow to the same property (its ButtonDropWidth derivation);
  // here both drop styles read the one arbitration.
  a := TToolButtonAccess.Create(FForm);
  a.Parent := FBar;
  a.Style := tbsButtonDrop;
  FBar.DropDownWidth := 33;
  AssertEquals('the attached-arrow style reads the same pinned zone', 33, a.CallArrowZoneWidth(96));
end;

procedure TToolBarMembersTest.TestListMapsOntoTheGlyphLayouts;
var
  a: TTyToolButton;
begin
  // The mapping table itself, then the live toggle in both directions.
  AssertTrue('List=True lays the icon BESIDE the caption', TyToolListLayout[True] = glLeft);
  AssertTrue('List=False stacks it ABOVE', TyToolListLayout[False] = glTop);
  a := AddTool(40);
  AssertTrue('a fresh bar (List=True) adopts glyph-beside', a.GlyphLayout = glLeft);
  FBar.List := False;
  AssertTrue('List off adopts the stacked layout', a.GlyphLayout = glTop);
  FBar.List := True;
  AssertTrue('and back', a.GlyphLayout = glLeft);
end;

procedure TToolBarMembersTest.TestListOffAdoptsTheStackedLayout;
var
  a: TTyToolButton;
begin
  // The other join order: the bar's mode is set BEFORE the tool arrives.
  FBar.List := False;
  a := AddTool(40);
  AssertTrue('a tool joining a List=False bar comes up stacked', a.GlyphLayout = glTop);
end;

procedure TToolBarMembersTest.TestExplicitGlyphLayoutSurvivesTheBar;
var
  a: TTyToolButton;
begin
  a := AddTool(40);
  a.GlyphLayout := glRight;     // the host's own choice for this one tool
  FBar.List := False;
  AssertTrue('a per-tool GlyphLayout survives the bar''s mode', a.GlyphLayout = glRight);
  FBar.List := True;
  AssertTrue('...and every later change to it', a.GlyphLayout = glRight);
end;

procedure TToolBarMembersTest.TestExplicitPinsEvenWhenItMatchesTheAdopted;
var
  a: TTyToolButton;
begin
  a := AddTool(40);              // joins with the bar's default: adopted glLeft
  a.GlyphLayout := glLeft;       // the host asks for EXACTLY that, in so many words
  // Writing the property is the claim, not the value change: if the claim were only
  // recorded when the value moved, this tool would silently follow the bar down.
  FBar.List := False;
  AssertTrue('writing the value the bar already pushed still pins the tool',
    a.GlyphLayout = glLeft);
end;

procedure TToolBarMembersTest.TestListDoesNotReachASpeedButton;
var
  s: TTySpeedButton;
begin
  { LCL's List reaches only its FButtons — TToolButtons and nothing else. A speed button on
    the bar keeps its own published GlyphLayout, whatever the bar's mode. }
  s := TTySpeedButton.Create(FForm);
  s.Parent := FBar;
  FBar.List := False;
  AssertTrue('a speed button is not the bar''s to relayout', s.GlyphLayout = glLeft);
end;

{ TToolBarPixelTest }

procedure TToolBarPixelTest.TestBottomHairlineIsLighterThanBody;
{ Theme: background: #202020 (32,32,32), border-color: #404040 (64,64,64).
  Control: 200x30 toolbar. RenderTo draws the full body in #202020 and
  a 1px bottom hairline in #404040 (border-color).
  At PPI 96, Scale(BorderWidth=1) = 1px, so y=29 is the hairline row.
  Assert the bottom row (y=29) red channel > mid-body (y=15) red channel.
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  TB: TTyToolBarAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxBody, PxHairline: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyToolBar { background: #202020; border-color: #404040; border-width: 1px; }');

    TB := TTyToolBarAccess.Create(Form);
    TB.Parent := Form;
    TB.Controller := Ctl;
    TB.Align := alNone;
    TB.SetBounds(0, 0, 200, 30);
    TB.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 30);
    // Pre-fill white so background rendering is unambiguous (canvas default is undefined)
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 30);
    TB.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 30), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Mid-body pixel (x=10, y=15): should be dark #202020
      PxBody := Reread.GetPixel(10, 15);
      // Bottom hairline pixel (x=10, y=29): should be #404040 — lighter
      PxHairline := Reread.GetPixel(10, 29);

      AssertTrue(
        Format('body pixel should be dark (r=%d g=%d b=%d, expected < 60)',
          [PxBody.red, PxBody.green, PxBody.blue]),
        (PxBody.red < 60) and (PxBody.green < 60) and (PxBody.blue < 60));

      AssertTrue(
        Format('hairline rendered (hairline.red=%d, expected >=55)',
          [PxHairline.red]),
        PxHairline.red >= 55);

      AssertTrue(
        Format('bottom hairline should be lighter than body (hairline.red=%d > body.red=%d)',
          [PxHairline.red, PxBody.red]),
        PxHairline.red > PxBody.red);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ ===== TTyToolButton ======================================================== }

{ ---- TToolGroupBoundsTest ------------------------------------------------- }

const
  { Shorthand for the tables below. }
  C = tbsCheck;
  B = tbsButton;
  S = tbsSeparator;
  D = tbsDivider;

procedure TToolGroupBoundsTest.TestUngroupedIsNoGroup;
var s_, e_: Integer;
begin
  { LCL's first condition. A button that is not Grouped is not in a group even when its
    neighbours are -- otherwise `Grouped` on ONE button of a bar would silently rope in every
    check button beside it. }
  AssertFalse('not grouped -> no group',
    TyToolGroupBounds([True, False, True], [C, C, C], 1, s_, e_));
  AssertEquals('start is cleared', -1, s_);
  AssertEquals('end is cleared', -1, e_);
end;

procedure TToolGroupBoundsTest.TestNonCheckStyleIsNoGroup;
var s_, e_: Integer;
begin
  { LCL's second condition, and the reason `Grouped` is not a lie on a command button: it is
    simply inert there. A tbsButton with Grouped set neither joins a group nor breaks one open. }
  AssertFalse('a grouped COMMAND button is still not a radio',
    TyToolGroupBounds([True, True, True], [C, B, C], 1, s_, e_));
  AssertEquals('start', -1, s_);
  AssertEquals('end', -1, e_);
end;

procedure TToolGroupBoundsTest.TestRunExtendsBothWays;
var s_, e_: Integer;
begin
  AssertTrue('grouped check button is in a group',
    TyToolGroupBounds([True, True, True], [C, C, C], 1, s_, e_));
  AssertEquals('the run reaches the first button', 0, s_);
  AssertEquals('...and the last', 2, e_);
  // Asking from either end gives the SAME span: the group is a property of the run, not of
  // whoever asked.
  AssertTrue(TyToolGroupBounds([True, True, True], [C, C, C], 0, s_, e_));
  AssertEquals('from the head: start', 0, s_);
  AssertEquals('from the head: end', 2, e_);
end;

procedure TToolGroupBoundsTest.TestUngroupedNeighbourEndsTheRun;
var s_, e_: Integer;
begin
  // [C C | c C]  — index 2 is a check button that is NOT Grouped, so it walls the run off.
  AssertTrue(TyToolGroupBounds([True, True, False, True], [C, C, C, C], 1, s_, e_));
  AssertEquals('start', 0, s_);
  AssertEquals('the ungrouped neighbour is the wall', 1, e_);
end;

procedure TToolGroupBoundsTest.TestCommandNeighbourEndsTheRun;
var s_, e_: Integer;
begin
  { A grouped COMMAND button between two radios divides them. This is the case that separates
    LCL's rule from "every grouped button on the bar": the style list matters, not just the
    flags. }
  AssertTrue(TyToolGroupBounds([True, True, True, True], [C, C, B, C], 1, s_, e_));
  AssertEquals('start', 0, s_);
  AssertEquals('a command button walls the run off', 1, e_);
end;

procedure TToolGroupBoundsTest.TestSpaceHolderDoesNotDivideARun;
var s_, e_: Integer;
begin
  { The whole point of the space-holder exception: a designer puts a gap between two radios of
    the SAME group. LCL lists tbsSeparator and tbsDivider beside tbsCheck for exactly this. }
  AssertTrue(TyToolGroupBounds([True, True, True, True, True], [C, S, C, D, C], 0, s_, e_));
  AssertEquals('start', 0, s_);
  AssertEquals('the run spans both space holders', 4, e_);
  // Asked from the far side, the same span.
  AssertTrue(TyToolGroupBounds([True, True, True, True, True], [C, S, C, D, C], 4, s_, e_));
  AssertEquals('start from the tail', 0, s_);
  AssertEquals('end from the tail', 4, e_);
end;

procedure TToolGroupBoundsTest.TestTwoRunsDoNotMerge;
var s_, e_: Integer;
begin
  // [C C] [B] [C C] — two independent radio sets on one bar.
  AssertTrue(TyToolGroupBounds([True, True, True, True, True], [C, C, B, C, C], 0, s_, e_));
  AssertEquals('first run: start', 0, s_);
  AssertEquals('first run: end', 1, e_);
  AssertTrue(TyToolGroupBounds([True, True, True, True, True], [C, C, B, C, C], 4, s_, e_));
  AssertEquals('second run: start', 3, s_);
  AssertEquals('second run: end', 4, e_);
end;

procedure TToolGroupBoundsTest.TestOutOfRangeAndShortArrays;
var s_, e_: Integer;
begin
  AssertFalse('negative index', TyToolGroupBounds([True], [C], -1, s_, e_));
  AssertFalse('past the end', TyToolGroupBounds([True], [C], 1, s_, e_));
  AssertFalse('empty', TyToolGroupBounds([], [], 0, s_, e_));
  { The SHORTER array governs. The styles run out at 2, so index 2 is outside the usable list
    and the run may not reach it -- a bound taken from the longer array would read past the end
    of the shorter one. }
  AssertTrue(TyToolGroupBounds([True, True, True], [C, C], 0, s_, e_));
  AssertEquals('start', 0, s_);
  AssertEquals('the run stops where the shorter array does', 1, e_);
end;

{ ---- TToolWrapShiftTest ---------------------------------------------------- }

procedure TToolWrapShiftTest.TestShiftsByOne;
var r: TBooleanDynArray;
begin
  { Wrap on tool 0 means the row ends after tool 0, i.e. tool 1 STARTS a row. The whole bug
    this function exists to prevent is the off-by-one that breaks before tool 0 instead. }
  r := TyToolWrapToBreakBefore([True, False, False]);
  AssertEquals('length is preserved', 3, Length(r));
  AssertEquals('tool 0 never carries a leading break', False, r[0]);
  AssertEquals('tool 0''s trailing Wrap became tool 1''s leading break', True, r[1]);
  AssertEquals('tool 2 is untouched', False, r[2]);
end;

procedure TToolWrapShiftTest.TestNeverBreaksOnTheFirst;
var r: TBooleanDynArray;
begin
  // Even with every flag set, item 0 cannot open a row -- there is no row above it to leave.
  r := TyToolWrapToBreakBefore([True, True, True]);
  AssertEquals('r[0]', False, r[0]);
  AssertEquals('r[1]', True, r[1]);
  AssertEquals('r[2]', True, r[2]);
end;

procedure TToolWrapShiftTest.TestDropsTheTrailingWrap;
var r: TBooleanDynArray;
begin
  { Wrap on the LAST tool has no successor to move, so it vanishes. LCL keeps it and bumps its
    row count for a row that has nothing on it -- a bar one button-height too tall. }
  r := TyToolWrapToBreakBefore([False, False, True]);
  AssertEquals('r[0]', False, r[0]);
  AssertEquals('r[1]', False, r[1]);
  AssertEquals('the last tool''s Wrap is dropped, not stored', False, r[2]);
end;

procedure TToolWrapShiftTest.TestEmpty;
var r: TBooleanDynArray;
begin
  r := TyToolWrapToBreakBefore([]);
  AssertEquals('empty in, empty out', 0, Length(r));
end;

{ ---- probes ---------------------------------------------------------------- }

procedure TToolButtonAccess.PressAndClickAt(AX: Integer);
begin
  MouseDown(mbLeft, [], AX, Height div 2);
  Click;
end;

procedure TToolButtonAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderSpaceHolder(ACanvas, ARect, APPI);
end;

procedure TToolButtonAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

function TToolButtonAccess.CallMeasureContentHeight(APPI: Integer): Integer;
begin
  Result := MeasureContentHeight(APPI);
end;

procedure TToolButtonAccess.EnterLoading;
begin
  Loading;
end;

function TToolButtonAccess.CallArrowZoneWidth(APPI: Integer): Integer;
begin
  Result := ArrowZoneWidth(APPI);
end;

procedure TToolButtonAccess.RenderWhole(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TToolButtonAccess.CallGlyphSource(AStates: TTyStateSet): TTyGlyphSource;
begin
  Result := GetGlyphSource(AStates);
end;

procedure TToolButtonAccess.SetHoverForTest(AValue: Boolean);
begin
  FHover := AValue;
end;

function TToolButtonAccess.CallBorderColor: TTyColor;
begin
  Result := CurrentStyle.BorderColor;
end;

function TToolButtonAccess.CallPadRight: Integer;
begin
  Result := CurrentStyle.Padding.Right;
end;

procedure TToolSeparatorAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ ---- TToolButtonTest ------------------------------------------------------- }

procedure TToolButtonTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 500, 200);
  FBar := TTyToolBarAccess.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alNone;          // keep LCL's align engine off our explicit bounds
  FBar.SetBounds(0, 0, 300, 30);
  FBar.Indent := 4;
  FBar.ButtonSpacing := 2;
  FBar.ButtonHeight := 24;
  FBar.Wrapable := True;
  FClicks := 0;
  FArrows := 0;
end;

procedure TToolButtonTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TToolButtonTest.CountClick(Sender: TObject);
begin
  Inc(FClicks);
end;

procedure TToolButtonTest.CountArrow(Sender: TObject);
begin
  Inc(FArrows);
end;

function TToolButtonTest.AddButton(AStyle: TTyToolButtonStyle; AWidth: Integer): TToolButtonAccess;
begin
  Result := TToolButtonAccess.Create(FForm);
  Result.Parent := FBar;
  Result.Style := AStyle;
  if AWidth > 0 then Result.Width := AWidth;
end;

procedure TToolButtonTest.TestSpaceHolderStylesTakeTheirLclWidths;
var
  b: TToolButtonAccess;
begin
  b := TToolButtonAccess.Create(FForm);
  b.Parent := FBar;
  AssertEquals('a fresh tool button is LCL''s 23px wide', 23, b.Width);
  b.Style := tbsSeparator;
  AssertEquals('tbsSeparator takes cDefSeparatorWidth', TyToolSeparatorWidth, b.Width);
  b.Style := tbsDivider;
  AssertEquals('tbsDivider takes cDefDividerWidth', TyToolDividerWidth, b.Width);
  // ...and the FLOOR moved with it, or SetBounds would have clamped the shrink away.
  AssertTrue(Format('the size floor followed the style (MinWidth=%d, expected <= %d)',
    [b.Constraints.MinWidth, TyToolDividerWidth]),
    b.Constraints.MinWidth <= TyToolDividerWidth);
end;

procedure TToolButtonTest.TestStreamedWidthOutranksTheStylesDefault;
var
  b: TToolButtonAccess;
begin
  { STREAMING ORDER. Width is declared on TControl and Style on TTyToolButton, so an .lfm writes
    Width FIRST and Style second. If Style reset the width unconditionally, a separator the
    designer had widened would be snapped back to 8 by its own Style line on every single load
    and the designed value could never survive. The two writes below are that order, inside the
    csLoading window the reader holds open. }
  b := TToolButtonAccess.Create(FForm);
  b.Parent := FBar;
  b.EnterLoading;               // csLoading, the window the reader holds open
  b.Width := 20;                // ...the .lfm's Width line
  b.Style := tbsSeparator;      // ...and its Style line, which comes second
  AssertEquals('a streamed Width survives its own Style line', 20, b.Width);
  b.Loaded;
  AssertEquals('...and still does after loading finishes', 20, b.Width);
  // Outside the loading window, an interactive Style change still snaps — which is what makes
  // the property usable in the designer.
  b.Style := tbsButton;
  b.Style := tbsDivider;
  AssertEquals('an interactive Style change snaps to the LCL width',
    TyToolDividerWidth, b.Width);
end;

procedure TToolButtonTest.TestSpaceHolderAsksForNoContentHeight;
var
  b: TToolButtonAccess;
  asButton, asSeparator, asDivider: Integer;
begin
  { A separator that reported a caption line would raise its MinHeight above the bar's
    ButtonHeight, and every row carrying one would be taller than every row that did not.

    ONE button, measured across a Style change, and through MeasureContentHeight itself rather
    than through Constraints.MinHeight: the two styles resolve different theme keys and so have
    different padding, and comparing two DIFFERENT buttons' MinHeight measured that padding gap
    instead — it stayed green with the space-holder rule deleted. }
  b := AddButton(tbsButton, 40);
  b.Caption := 'Open';
  asButton := b.CallMeasureContentHeight(96);
  AssertTrue(Format('a command button stacks a caption line (%d)', [asButton]), asButton > 0);
  b.Style := tbsSeparator;
  asSeparator := b.CallMeasureContentHeight(96);
  AssertEquals('a tbsSeparator stacks nothing', 0, asSeparator);
  b.Style := tbsDivider;
  asDivider := b.CallMeasureContentHeight(96);
  AssertEquals('and neither does a tbsDivider', 0, asDivider);
  // Back to a button: the rule is keyed on the STYLE, not a one-way latch.
  b.Style := tbsButton;
  AssertEquals('the caption line comes back with the style',
    asButton, b.CallMeasureContentHeight(96));
end;

procedure TToolButtonTest.TestSpaceHolderIsNotGivenTheGhostVariant;
var
  cmd, sep: TToolButtonAccess;
begin
  { A tbsSeparator resolves 'TyToolSeparator', so the button-family 'ghost' variant the bar
    stamps on its Flat children would ask the theme for a TyToolSeparator.ghost rule no skin
    defines — and would leave a StyleClass behind on a control the host never styled. }
  AssertTrue('the bar is flat by default (or this proves nothing)', FBar.Flat);
  cmd := AddButton(tbsButton, 40);
  sep := AddButton(tbsSeparator, 0);
  FBar.ForceLayout;
  AssertEquals('a command tool button DOES take the flat variant', 'ghost', cmd.StyleClass);
  AssertEquals('a space holder is left alone', '', sep.StyleClass);
end;

procedure TToolButtonTest.TestArrowStylesReserveTheZoneInThePreferredWidth;
var
  plain, split, attached: TToolButtonAccess;
  pw, ph, sw, sh, aw, ah: Integer;
begin
  { AutoSize -- and the size FLOOR that rides on the same method -- must reserve the arrow zone
    DrawContent carves off, or the chevron eats the caption and the button reports a fit. }
  plain := AddButton(tbsButton, 80);      plain.Caption := 'Open';
  split := AddButton(tbsDropDown, 80);    split.Caption := 'Open';
  attached := AddButton(tbsButtonDrop, 80); attached.Caption := 'Open';
  plain.CallPreferred(pw, ph);
  split.CallPreferred(sw, sh);
  attached.CallPreferred(aw, ah);
  AssertTrue(Format('tbsDropDown reserves the arrow zone (%d > %d)', [sw, pw]), sw > pw);
  AssertTrue(Format('tbsButtonDrop reserves it too (%d > %d)', [aw, pw]), aw > pw);
  AssertEquals('both arrow styles reserve the SAME zone', sw, aw);
  // Height stays 0 on every style: a tool button never negotiates a height with its bar.
  AssertEquals('plain height stays "no opinion"', 0, ph);
  AssertEquals('split height stays "no opinion"', 0, sh);
end;

procedure TToolButtonTest.TestButtonsListSkipsNonToolChildren;
var
  b0, b1: TToolButtonAccess;
  plain: TTyButton;
  sep: TTyToolSeparator;
begin
  { LCL's Buttons[] holds TToolButtons and nothing else, and that index space is what Grouped
    and Index speak in. A plain TTyButton or a separator CONTROL between two tool buttons must
    therefore not appear in it -- nor shift the indices of the ones that do. }
  b0 := AddButton(tbsButton, 30);
  plain := TTyButton.Create(FForm); plain.Parent := FBar;
  sep := TTyToolSeparator.Create(FForm); sep.Parent := FBar;
  b1 := AddButton(tbsButton, 30);
  AssertEquals('only the tool buttons are counted', 2, FBar.ButtonCount);
  AssertSame('Buttons[0]', b0, FBar.Buttons[0]);
  AssertSame('Buttons[1]', b1, FBar.Buttons[1]);
  AssertEquals('b0.Index', 0, b0.Index);
  AssertEquals('b1.Index is NOT pushed along by the two strangers', 1, b1.Index);
  AssertTrue('out of range answers nil rather than raising', FBar.Buttons[2] = nil);
  AssertTrue('...and so does a negative index', FBar.Buttons[-1] = nil);
end;

procedure TToolButtonTest.TestIndexIsMinusOneOffABar;
var
  b: TTyToolButton;
begin
  b := TTyToolButton.Create(FForm);
  AssertEquals('parentless', -1, b.Index);
  AssertTrue('and no bar', b.ToolBar = nil);
  b.Parent := FForm;   // a form is not a tool bar
  AssertEquals('on a non-bar parent', -1, b.Index);
  AssertTrue('still no bar', b.ToolBar = nil);
end;

procedure TToolButtonTest.TestCheckStyleTogglesDown;
var
  b: TToolButtonAccess;
begin
  b := AddButton(tbsCheck, 40);
  b.OnClick := @CountClick;
  AssertFalse('starts up', b.Down);
  b.PressAndClickAt(5);
  AssertTrue('a click checks it', b.Down);
  AssertEquals('and still fires OnClick', 1, FClicks);
  b.PressAndClickAt(5);
  AssertFalse('a second click un-checks it', b.Down);
  AssertEquals('OnClick again', 2, FClicks);
end;

procedure TToolButtonTest.TestPlainStyleDoesNotToggleDown;
var
  b: TToolButtonAccess;
begin
  // Only tbsCheck is a toggle. A plain command button that latched would be a check box.
  b := AddButton(tbsButton, 40);
  b.OnClick := @CountClick;
  b.PressAndClickAt(5);
  AssertFalse('a command button does not latch', b.Down);
  AssertEquals('but it does click', 1, FClicks);
end;

procedure TToolButtonTest.TestSpaceHolderSwallowsTheClick;
var
  b: TToolButtonAccess;
begin
  { LCL declines the hit outright (CMHitTest). Doing it in Click covers the keyboard and
    mnemonic paths too, which a hit-test alone would not. }
  b := AddButton(tbsSeparator, 0);
  b.OnClick := @CountClick;
  b.PressAndClickAt(2);
  AssertEquals('a separator is not a control surface', 0, FClicks);
  b.Style := tbsDivider;
  b.PressAndClickAt(2);
  AssertEquals('nor is a divider', 0, FClicks);
end;

procedure TToolButtonTest.TestArrowZoneClickFiresArrowNotClick;
var
  b: TToolButtonAccess;
begin
  b := AddButton(tbsDropDown, 80);
  b.OnClick := @CountClick;
  b.OnArrowClick := @CountArrow;
  // The rightmost pixel is unambiguously inside the zone whatever '--drop-arrow-width' is.
  b.PressAndClickAt(b.Width - 1);
  AssertEquals('the arrow zone fires OnArrowClick', 1, FArrows);
  AssertEquals('and never the primary OnClick', 0, FClicks);
  AssertTrue('the hit test agrees with the routing',
    b.PointInArrow(b.Width - 1, b.Height div 2));
end;

procedure TToolButtonTest.TestMainAreaClickFiresClickNotArrow;
var
  b: TToolButtonAccess;
begin
  b := AddButton(tbsDropDown, 80);
  b.OnClick := @CountClick;
  b.OnArrowClick := @CountArrow;
  b.PressAndClickAt(0);            // the leading edge: as far from the zone as it gets
  AssertEquals('the main area fires OnClick', 1, FClicks);
  AssertEquals('and never OnArrowClick', 0, FArrows);
  AssertFalse('the hit test agrees', b.PointInArrow(0, b.Height div 2));
end;

procedure TToolButtonTest.TestMenuSuppressesTheArrowEvent;
var
  b: TToolButtonAccess;
  m: TTyPopupMenu;
begin
  { LCL's rule (toolbutton.inc:170-179): OnArrowClick is the ALTERNATIVE to a menu, not a hook
    in front of it, so an assigned menu suppresses it. }
  m := TTyPopupMenu.Create(FForm);
  b := AddButton(tbsDropDown, 80);
  b.OnArrowClick := @CountArrow;
  b.OnClick := @CountClick;
  b.DropdownMenu := m;
  b.PressAndClickAt(b.Width - 1);
  AssertTrue('the menu was the decision', b.RequestedPopup);
  AssertEquals('the menu suppressed OnArrowClick', 0, FArrows);
  AssertEquals('and the primary OnClick stayed out of it', 0, FClicks);
  // Take the menu away and the same click reaches the event.
  b.DropdownMenu := nil;
  b.PressAndClickAt(b.Width - 1);
  AssertEquals('with no menu, the arrow event fires', 1, FArrows);
end;

procedure TToolButtonTest.TestButtonDropHasNoArrowZone;
var
  b: TToolButtonAccess;
  m: TTyPopupMenu;
begin
  { tbsButtonDrop draws an arrow but is ONE hit zone -- LCL's PointInArrow answers True for
    tbsDropDown and nothing else. So a click anywhere drops the menu AND runs OnClick, and
    OnArrowClick can never fire. }
  m := TTyPopupMenu.Create(FForm);
  b := AddButton(tbsButtonDrop, 80);
  b.DropdownMenu := m;
  b.OnClick := @CountClick;
  b.OnArrowClick := @CountArrow;
  AssertFalse('no arrow zone at the right edge',
    b.PointInArrow(b.Width - 1, b.Height div 2));
  b.PressAndClickAt(b.Width - 1);
  AssertTrue('the whole face drops the menu', b.RequestedPopup);
  AssertEquals('and the ordinary OnClick still runs', 1, FClicks);
  AssertEquals('OnArrowClick is unreachable on this style', 0, FArrows);
end;

procedure TToolButtonTest.TestGroupIsExclusive;
var
  b0, b1, b2: TToolButtonAccess;
begin
  b0 := AddButton(tbsCheck, 30); b0.Grouped := True; b0.AllowAllUp := True;
  b1 := AddButton(tbsCheck, 30); b1.Grouped := True;
  b2 := AddButton(tbsCheck, 30); b2.Grouped := True;
  b0.PressAndClickAt(5);
  AssertTrue('b0 down', b0.Down);
  b2.PressAndClickAt(5);
  AssertTrue('b2 down', b2.Down);
  AssertFalse('b0 was released by its group', b0.Down);
  AssertFalse('b1 was never down', b1.Down);
  // Setting Down FROM CODE must release the group too -- preselecting a saved mode is an
  // ordinary thing to do, and putting the rule only in Click left every sibling pressed.
  b1.Down := True;
  AssertTrue('b1 down from code', b1.Down);
  AssertFalse('...and the group followed', b2.Down);
end;

procedure TToolButtonTest.TestGroupedRadioCannotBeReleasedByHand;
var
  b0, b1: TToolButtonAccess;
begin
  { With AllowAllUp off the group must always hold exactly one selection, so neither a click
    nor a code write may take the last one away. }
  b0 := AddButton(tbsCheck, 30); b0.Grouped := True;
  b1 := AddButton(tbsCheck, 30); b1.Grouped := True;
  b0.Down := True;
  b0.PressAndClickAt(5);
  AssertTrue('a click on the pressed radio leaves it pressed', b0.Down);
  b0.Down := False;
  AssertTrue('and so does a code write', b0.Down);
  // The group can still MOVE the selection -- that is not the same as removing it.
  b1.Down := True;
  AssertTrue('b1 took it', b1.Down);
  AssertFalse('b0 gave it up to the group', b0.Down);
end;

procedure TToolButtonTest.TestAllowAllUpLetsTheGroupGoUp;
var
  b0, b1: TToolButtonAccess;
begin
  b0 := AddButton(tbsCheck, 30); b0.Grouped := True; b0.AllowAllUp := True;
  b1 := AddButton(tbsCheck, 30); b1.Grouped := True;
  { AllowAllUp is a property of the GROUP, not of the button: LCL asks whether ANY member has
    it. b1 does not, and must still be releasable because b0 does. }
  b1.Down := True;
  b1.Down := False;
  AssertFalse('one member''s AllowAllUp frees the whole group', b1.Down);
  AssertFalse('and nothing else came up', b0.Down);
end;

procedure TToolButtonTest.TestAllowAllUpOffRestoresASelection;
var
  b0, b1: TToolButtonAccess;
begin
  { Turning AllowAllUp OFF on an all-up group would otherwise leave an exclusive group with
    nothing selected until the user happened to click -- the same invariant TTySpeedButton
    restores. }
  b0 := AddButton(tbsCheck, 30); b0.Grouped := True; b0.AllowAllUp := True;
  b1 := AddButton(tbsCheck, 30); b1.Grouped := True;
  AssertFalse('all up to begin with', b0.Down or b1.Down);
  b0.AllowAllUp := False;
  AssertTrue('the button being configured becomes the selection', b0.Down);
end;

procedure TToolButtonTest.TestGroupingIgnoresANonToolSibling;
var
  b0, b1: TToolButtonAccess;
  stranger: TTyButton;
begin
  { LCL's FButtons list holds only TToolButtons, so a plain button sitting between two radios
    is not in their index space and does not divide them. A group computed over ALL children
    would break here. }
  b0 := AddButton(tbsCheck, 30); b0.Grouped := True;
  stranger := TTyButton.Create(FForm); stranger.Parent := FBar; stranger.Width := 30;
  b1 := AddButton(tbsCheck, 30); b1.Grouped := True;
  b0.Down := True;
  b1.Down := True;
  AssertTrue('b1 took the selection', b1.Down);
  AssertFalse('across the stranger, b0 was still released', b0.Down);
end;

procedure TToolButtonTest.TestImageIndexIsASpellingOfImageName;
var
  b: TToolButtonAccess;
  coll: TTyImageCollection;
  m: TBGRABitmap;
begin
  coll := TTyImageCollection.Create(FForm);
  m := TBGRABitmap.Create(4, 4, BGRAWhite);
  try
    coll.AddBitmap('new', m);
    coll.AddBitmap('open', m);
    coll.AddBitmap('save', m);
  finally
    m.Free;
  end;
  FBar.Images := coll;
  b := AddButton(tbsButton, 30);
  AssertEquals('no icon yet', -1, b.ImageIndex);
  b.ImageIndex := 2;
  AssertEquals('the index was resolved to a NAME', 'save', b.ImageName);
  AssertEquals('and reads back as the same index', 2, b.ImageIndex);
  // Writing the NAME is the same write: they are two spellings of one state, so there is no
  // precedence rule and the index simply follows.
  b.ImageName := 'new';
  AssertEquals('the index follows the name', 0, b.ImageIndex);
  // An index past the end resolves to no name (and so no icon), not to a stale one.
  b.ImageIndex := 99;
  AssertEquals('an out-of-range index draws nothing', '', b.ImageName);
end;

procedure TToolButtonTest.TestImageIndexSetBeforeTheCollectionSurvivesParenting;
var
  b: TToolButtonAccess;
  coll: TTyImageCollection;
  m: TBGRABitmap;
begin
  { The streaming case, in the shape code hits it: ImageIndex is written while there is no
    collection to look it up in (an .lfm fixes component references up AFTER the properties
    are read). The request has to be remembered, or a designed tool bar loses every icon. }
  coll := TTyImageCollection.Create(FForm);
  m := TBGRABitmap.Create(4, 4, BGRAWhite);
  try
    coll.AddBitmap('new', m);
    coll.AddBitmap('open', m);
  finally
    m.Free;
  end;
  b := TToolButtonAccess.Create(FForm);      // NOT on the bar yet: Images is nil
  b.ImageIndex := 1;
  AssertEquals('nothing to resolve against yet', '', b.ImageName);
  AssertEquals('but the request is remembered', 1, b.ImageIndex);
  FBar.Images := coll;
  b.Parent := FBar;                          // the bar lends its collection here
  AssertEquals('joining the bar resolved it', 'open', b.ImageName);
  AssertEquals('and it still reads back', 1, b.ImageIndex);
end;

procedure TToolButtonTest.TestImageIndexSurvivesTheBarGettingItsCollectionLater;
var
  b: TToolButtonAccess;
  coll: TTyImageCollection;
  m: TBGRABitmap;
begin
  { The other order, and the one only the BAR's retry can serve: the tool is already on the bar
    when the bar is handed a collection. Nothing on the button is written at that moment — the
    bar writes the button's inherited Images through a private setter this class cannot hook —
    so without TTyToolBar.ApplyToolProperties calling back, the request would sit pending
    forever and the tool would be iconless. }
  coll := TTyImageCollection.Create(FForm);
  m := TBGRABitmap.Create(4, 4, BGRAWhite);
  try
    coll.AddBitmap('new', m);
    coll.AddBitmap('open', m);
  finally
    m.Free;
  end;
  b := AddButton(tbsButton, 30);      // on the bar FIRST; the bar has no collection yet
  b.ImageIndex := 1;
  AssertEquals('nothing to resolve against yet', '', b.ImageName);
  FBar.Images := coll;
  AssertEquals('the bar''s collection resolved the pending index', 'open', b.ImageName);
  AssertEquals('and it reads back', 1, b.ImageIndex);
end;

procedure TToolButtonTest.TestImageIndexSurvivesAnOwnCollectionFixedUpAtLoaded;
var
  b: TToolButtonAccess;
  coll: TTyImageCollection;
  m: TBGRABitmap;
begin
  { The case the BAR can never reach, and the only reason Loaded is overridden: a button that
    carries its OWN Images in an .lfm. The reader streams the properties first and fixes the
    component reference up afterwards, so ImageIndex was read against a nil collection, and
    the assignment that finally arrives goes through TTyGlyphButtonBase's private setter —
    invisible from here. Loaded is the one moment after the fixup that this class controls.
    (The two writes below are that sequence, in order.) }
  coll := TTyImageCollection.Create(FForm);
  m := TBGRABitmap.Create(4, 4, BGRAWhite);
  try
    coll.AddBitmap('new', m);
    coll.AddBitmap('open', m);
  finally
    m.Free;
  end;
  b := TToolButtonAccess.Create(FForm);
  b.ImageIndex := 1;             // streamed while the reference is still unresolved
  AssertEquals('unresolvable at stream time', '', b.ImageName);
  b.Images := coll;              // the reader's fixup: a private setter, no hook
  AssertEquals('the fixup alone does not resolve it', '', b.ImageName);
  b.Loaded;
  AssertEquals('Loaded is what turns it into an icon', 'open', b.ImageName);
end;

procedure TToolButtonTest.TestImageIndexMinusOneClearsTheIcon;
var
  b: TToolButtonAccess;
  coll: TTyImageCollection;
  m: TBGRABitmap;
begin
  coll := TTyImageCollection.Create(FForm);
  m := TBGRABitmap.Create(4, 4, BGRAWhite);
  try
    coll.AddBitmap('new', m);
  finally
    m.Free;
  end;
  FBar.Images := coll;
  b := AddButton(tbsButton, 30);
  b.ImageIndex := 0;
  AssertEquals('icon set', 'new', b.ImageName);
  b.ImageIndex := -1;
  AssertEquals('an explicit -1 clears it, as LCL''s does', '', b.ImageName);
  AssertEquals('and reads back as -1', -1, b.ImageIndex);
end;

procedure TToolButtonTest.TestImageNameOnlyIsNeverClobbered;
var
  b: TToolButtonAccess;
  coll: TTyImageCollection;
  m: TBGRABitmap;
begin
  { A button that only ever used ImageName must never be touched by the ImageIndex retry --
    the retry runs on parenting, on Loaded and whenever the bar hands over a collection, so a
    retry that fired unconditionally would blank a perfectly good icon at an unpredictable
    moment. FImageIndex is -1 on such a button, which is exactly the value that CLEARS one. }
  coll := TTyImageCollection.Create(FForm);
  m := TBGRABitmap.Create(4, 4, BGRAWhite);
  try
    coll.AddBitmap('new', m);
  finally
    m.Free;
  end;
  b := TToolButtonAccess.Create(FForm);
  b.ImageName := 'new';          // by NAME only; ImageIndex is never written
  FBar.Images := coll;
  b.Parent := FBar;              // SetParent retry
  AssertEquals('parenting left the name alone', 'new', b.ImageName);
  FBar.Images := nil;
  FBar.Images := coll;           // the bar's lend/retract retry
  AssertEquals('re-lending left it alone too', 'new', b.ImageName);
  b.Loaded;                      // the streaming retry
  AssertEquals('and so did Loaded', 'new', b.ImageName);
end;

procedure TToolButtonTest.TestWrapBreaksTheBarsRowAfterTheButton;
var
  b0, b1, b2: TToolButtonAccess;
begin
  { Three 40px tools on a 300px bar all fit on one row. Wrap on tool 0 means "the row ends
    AFTER tool 0", so tool 1 opens row 2 -- and tool 2 follows it there. If the flag were
    applied as LEADING, tool 0 itself would move and tool 1 would stay put. }
  b0 := AddButton(tbsButton, 40);
  b1 := AddButton(tbsButton, 40);
  b2 := AddButton(tbsButton, 40);
  b0.Wrap := True;
  FBar.ForceLayout;
  AssertEquals('b0 stays on row 1 at the indent', 4, b0.Left);
  AssertEquals('b1 opened row 2 at the indent', 4, b1.Left);
  { Exactly ONE row down, not two and not a nudge: the row pitch is
    ButtonHeight + ButtonSpacing, and both tools are centred the same way inside their rows,
    so the difference of their tops is the pitch. (An absolute Top would be wrong here — a
    child shorter than the row is centred in it, so the first row's tools do not sit at the
    bar's top pad.) }
  AssertEquals('b1 is exactly one row below b0',
    FBar.ButtonHeight + FBar.ButtonSpacing, b1.Top - b0.Top);
  AssertEquals('b2 followed b1 onto row 2', b1.Top, b2.Top);
  AssertEquals('b2 sits beside b1', 4 + 40 + 2, b2.Left);
end;

procedure TToolButtonTest.TestWrapOnTheLastButtonAddsNoRow;
var
  b0, b1: TToolButtonAccess;
  hBefore: Integer;
begin
  { LCL bumps its row count for a Wrap on the last button and reports a row with nothing on it
    -- a bar one button-height too tall. The bar's height is computed straight from the row
    count, so that extra row would be visible as dead space. }
  b0 := AddButton(tbsButton, 40);
  b1 := AddButton(tbsButton, 40);
  FBar.ForceLayout;
  hBefore := FBar.Height;
  b1.Wrap := True;
  FBar.ForceLayout;
  AssertEquals('the bar did not grow a phantom row', hBefore, FBar.Height);
  AssertEquals('and both tools are still on one row', b0.Top, b1.Top);
end;

procedure TToolButtonTest.TestInvisibleButtonsWrapIsNotHonoured;
var
  b0, b1, b2, b3: TToolButtonAccess;
begin
  { An invisible tool is not laid out, so it has no row to end.

    FOUR tools with the hidden one SECOND, not three: the flags are collected parallel to the
    VISIBLE list, and reading them off the unfiltered child list instead shifts every flag past
    the hidden tool by one. With only three tools that misalignment happens to land on a slot
    where it changes nothing — it passed the mutant — so the case has to be long enough for the
    shifted flag to reach a tool that would move. Here b1's Wrap, mis-read against the visible
    list, would land on b3 and open a second row. }
  b0 := AddButton(tbsButton, 40);
  b1 := AddButton(tbsButton, 40);
  b2 := AddButton(tbsButton, 40);
  b3 := AddButton(tbsButton, 40);
  b1.Wrap := True;
  b1.Visible := False;
  FBar.ForceLayout;
  AssertEquals('b0 and b2 share a row', b0.Top, b2.Top);
  AssertEquals('b3 is on that row too — the hidden tool ended no row', b0.Top, b3.Top);
  AssertEquals('b2 took the hidden tool''s slot', 4 + 40 + 2, b2.Left);
  AssertEquals('and b3 the next one', 4 + (40 + 2) * 2, b3.Left);
  { The other half, so this is "the flag was ignored" and not "no flag ever works": make the
    SAME position visible again and the very same flag does end its row. }
  b1.Visible := True;
  FBar.ForceLayout;
  AssertEquals('now visible, b1''s Wrap ends its row', 4, b2.Left);
  AssertTrue(Format('and b2 moved down (top=%d vs %d)', [b2.Top, b0.Top]), b2.Top > b0.Top);
end;

{ ---- TToolButtonSeparatorPixelTest ---------------------------------------- }

{ Render AControl-sized ink for both a tbsDivider tool button and a TTyToolSeparator under the
  same theme, then compare. Returns True when every pixel matches. }
procedure TToolButtonSeparatorPixelTest.TestDividerInkMatchesTheSeparatorControl;
var
  Ctl: TTyStyleController;
  Form: TForm;
  btn: TToolButtonAccess;
  sep: TToolSeparatorAccess;
  bmpA, bmpB: TBitmap;
  a, b: TBGRABitmap;
  x, y, diffs, ruleCols: Integer;
  pa: TBGRAPixel;
const
  W = 9; H = 24;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  bmpA := TBitmap.Create;
  bmpB := TBitmap.Create;
  try
    // A background that is clearly NOT the rule colour, so "the rule was drawn" is decidable.
    Ctl.LoadThemeCss('TyToolSeparator { background: #202020; border-color: #C0C0C0; }');

    btn := TToolButtonAccess.Create(Form);
    btn.Parent := Form; btn.Controller := Ctl;
    btn.Style := tbsDivider;
    btn.SetBounds(0, 0, W, H);
    btn.Font.PixelsPerInch := 96;

    sep := TToolSeparatorAccess.Create(Form);
    sep.Parent := Form; sep.Controller := Ctl;
    sep.SetBounds(0, 0, W, H);
    sep.Font.PixelsPerInch := 96;

    bmpA.PixelFormat := pf32bit; bmpA.SetSize(W, H);
    bmpA.Canvas.Brush.Color := clWhite; bmpA.Canvas.FillRect(0, 0, W, H);
    btn.DoRenderTo(bmpA.Canvas, Rect(0, 0, W, H), 96);

    bmpB.PixelFormat := pf32bit; bmpB.SetSize(W, H);
    bmpB.Canvas.Brush.Color := clWhite; bmpB.Canvas.FillRect(0, 0, W, H);
    sep.DoRenderTo(bmpB.Canvas, Rect(0, 0, W, H), 96);

    a := TBGRABitmap.Create(bmpA);
    b := TBGRABitmap.Create(bmpB);
    try
      // First: the divider really was drawn. A blank-vs-blank comparison would pass for the
      // wrong reason, which is the classic way a "they match" test goes fake-green.
      ruleCols := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
        begin
          pa := a.GetPixel(x, y);
          if (pa.red > 150) and (pa.green > 150) and (pa.blue > 150) then Inc(ruleCols);
        end;
      AssertTrue(Format('the tbsDivider drew a light rule over the dark plate (%d px)',
        [ruleCols]), ruleCols > 0);

      diffs := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
          if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(diffs);
      AssertEquals('a tbsDivider and a TTyToolSeparator are the same ink, pixel for pixel',
        0, diffs);
    finally
      a.Free; b.Free;
    end;
  finally
    bmpA.Free; bmpB.Free; Form.Free; Ctl.Free;
  end;
end;

procedure TToolButtonSeparatorPixelTest.TestSeparatorStyleDrawsNoRule;
var
  Ctl: TTyStyleController;
  Form: TForm;
  btn: TToolButtonAccess;
  bmp: TBitmap;
  img: TBGRABitmap;
  x, y, light: Integer;
  p: TBGRAPixel;
const
  W = 9; H = 24;
begin
  { tbsSeparator is "space holder", tbsDivider is "space holder WITH LINE" -- LCL's own words.
    A separator that drew the rule would make the two styles indistinguishable and the enum
    would carry a member that means nothing. }
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyToolSeparator { background: #202020; border-color: #C0C0C0; }');
    btn := TToolButtonAccess.Create(Form);
    btn.Parent := Form; btn.Controller := Ctl;
    btn.Style := tbsSeparator;
    btn.SetBounds(0, 0, W, H);
    btn.Font.PixelsPerInch := 96;
    bmp.PixelFormat := pf32bit; bmp.SetSize(W, H);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0, 0, W, H);
    btn.DoRenderTo(bmp.Canvas, Rect(0, 0, W, H), 96);
    img := TBGRABitmap.Create(bmp);
    try
      light := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
        begin
          p := img.GetPixel(x, y);
          if (p.red > 150) and (p.green > 150) and (p.blue > 150) then Inc(light);
        end;
      AssertEquals('tbsSeparator lays the backdrop and no rule', 0, light);
      // ...and the backdrop IS there, so this is "no rule", not "no paint at all".
      p := img.GetPixel(W div 2, H div 2);
      AssertTrue(Format('the seamless backdrop was still laid (r=%d g=%d b=%d)',
        [p.red, p.green, p.blue]),
        (p.red < 60) and (p.green < 60) and (p.blue < 60));
    finally
      img.Free;
    end;
  finally
    bmp.Free; Form.Free; Ctl.Free;
  end;
end;

{ TToolBarStateImagesTest }

procedure TToolBarStateImagesTest.SetUp;
var
  m: TBGRABitmap;
begin
  FForm := TForm.CreateNew(nil);
  FBar := TTyToolBar.Create(FForm);
  FBar.Parent := FForm;

  { Three collections carrying the SAME name 'save', so the swap is a swap and nothing else.
    The shapes differ by which half of the square is opaque — alpha survives the tint (the
    paint replaces RGB only), so which collection was drawn is readable from the pixels.
    That is the point: a colour difference would prove nothing, because the theme already
    recolours per state and the whole reason these properties exist is per-state SHAPE. }
  FNormal := TTyImageCollection.Create(FForm);
  FHot := TTyImageCollection.Create(FForm);
  FDisabled := TTyImageCollection.Create(FForm);

  m := MakeHalfMask(True);            // opaque LEFT half
  try FNormal.AddBitmap('save', m); finally m.Free; end;
  m := MakeHalfMask(False);           // opaque RIGHT half
  try FHot.AddBitmap('save', m); finally m.Free; end;
  m := MakeHalfMask(False);
  try FDisabled.AddBitmap('save', m); finally m.Free; end;

  FBar.Images := FNormal;
  FTool := TToolButtonAccess.Create(FForm);
  FTool.Parent := FBar;
  FTool.ImageName := 'save';
end;

procedure TToolBarStateImagesTest.TearDown;
begin
  FForm.Free;
  FForm := nil;
end;

{ A 16px square whose LEFT (or RIGHT) half is opaque white and the other half fully
  transparent. The opaque half is what the tint keeps and the paint blits. }
function TToolBarStateImagesTest.MakeHalfMask(ALeft: Boolean): TBGRABitmap;
var
  x, y: Integer;
  opaque: Boolean;
begin
  Result := TBGRABitmap.Create(16, 16, BGRAPixelTransparent);
  for y := 0 to 15 do
    for x := 0 to 15 do
    begin
      opaque := (x < 8) = ALeft;
      if opaque then
        Result.SetPixel(x, y, BGRAWhite);
    end;
end;

procedure TToolBarStateImagesTest.TestHoverSwapsToHotImages;
var
  src: TTyGlyphSource;
begin
  src := FTool.CallGlyphSource([]);
  AssertTrue('at rest the tool draws the bar''s normal collection', src.Images = FNormal);
  AssertEquals('and the name never changes', 'save', src.ImageName);

  // Not assigned yet: hover must still resolve the normal art rather than nothing.
  src := FTool.CallGlyphSource([tysHover]);
  AssertTrue('with no HotImages, hover is still the normal collection', src.Images = FNormal);

  FBar.HotImages := FHot;
  src := FTool.CallGlyphSource([tysHover]);
  AssertTrue('hover now resolves the hot collection', src.Images = FHot);
  AssertEquals('by the SAME name — this is a swap, not a re-key', 'save', src.ImageName);
  src := FTool.CallGlyphSource([]);
  AssertTrue('and at rest it is unchanged', src.Images = FNormal);
end;

procedure TToolBarStateImagesTest.TestDisabledOutranksHover;
var
  src: TTyGlyphSource;
begin
  FBar.HotImages := FHot;
  FBar.DisabledImages := FDisabled;
  src := FTool.CallGlyphSource([tysDisabled]);
  AssertTrue('disabled resolves the disabled collection', src.Images = FDisabled);
  { A disabled tool can still have the pointer over it, so both states arrive together.
    LCL resolves the same way: disabled wins. }
  src := FTool.CallGlyphSource([tysDisabled, tysHover]);
  AssertTrue('disabled beats hover when both are set', src.Images = FDisabled);
end;

procedure TToolBarStateImagesTest.TestAlternateMissingTheNameIsDeclined;
var
  empty: TTyImageCollection;
  other: TTyImageCollection;
  m: TBGRABitmap;
  src: TTyGlyphSource;
begin
  { The difference between a NAME-keyed library and an index-keyed one. LCL indexes parallel
    lists and blanks the icon when HotImages is shorter; here an alternate that does not carry
    this name simply has nothing to say, and the normal art is drawn. }
  empty := TTyImageCollection.Create(FForm);
  FBar.HotImages := empty;
  src := FTool.CallGlyphSource([tysHover]);
  AssertTrue('an empty alternate cannot blank the icon on hover', src.Images = FNormal);

  other := TTyImageCollection.Create(FForm);
  m := MakeHalfMask(False);
  try other.AddBitmap('open', m); finally m.Free; end;
  FBar.HotImages := other;
  src := FTool.CallGlyphSource([tysHover]);
  AssertTrue('an alternate carrying only OTHER names is declined too', src.Images = FNormal);
end;

procedure TToolBarStateImagesTest.TestToolWithItsOwnCollectionIsLeftAlone;
var
  own: TTyImageCollection;
  m: TBGRABitmap;
  src: TTyGlyphSource;
begin
  { The bar's alternates describe the BAR's icons. A tool that brought its own collection is
    not something the bar has an opinion about — and the lend-and-return rule already says the
    bar only manages the reference it put there. }
  own := TTyImageCollection.Create(FForm);
  m := MakeHalfMask(True);
  try own.AddBitmap('save', m); finally m.Free; end;
  FTool.Images := own;
  FBar.HotImages := FHot;
  src := FTool.CallGlyphSource([tysHover]);
  AssertTrue('a tool drawing its OWN collection keeps it on hover', src.Images = own);
end;

procedure TToolBarStateImagesTest.TestNoIconNothingToSubstitute;
var
  src: TTyGlyphSource;
begin
  FBar.HotImages := FHot;
  FTool.ImageName := '';
  src := FTool.CallGlyphSource([tysHover]);
  AssertEquals('a tool with no icon name resolves no name', '', src.ImageName);
  AssertTrue('and the alternate is not smuggled in behind it', src.Images = FNormal);
end;

procedure TToolBarStateImagesTest.TestTheSlotDoesNotMoveWhenTheStateDoes;
var
  w0, h0, w1, h1: Integer;
begin
  { The contract that makes the seam safe: it may change the PICTURE, never the PRESENCE or
    the SIZE. Layout reads the published fields, not the seam — so assigning alternates, and
    entering the hover state, must leave the measured box exactly where it was. A button that
    resized under the pointer would be a far worse bug than the one these properties fix. }
  FTool.CallPreferred(w0, h0);
  AssertTrue('sanity: the tool reports a width', w0 > 0);
  AssertTrue('sanity: it has an icon to measure', FTool.CanShowGlyph);

  FBar.HotImages := FHot;
  FBar.DisabledImages := FDisabled;
  FTool.SetHoverForTest(True);
  FTool.CallPreferred(w1, h1);
  AssertEquals('the preferred width is untouched by the alternates and by hover', w0, w1);
  AssertEquals('and so is the preferred height', h0, h1);
  AssertTrue('the glyph still exists as far as layout is concerned', FTool.CanShowGlyph);
end;

procedure TToolBarStateImagesTest.TestHoverReallyDrawsTheHotArt;
const
  W = 40; H = 28;
var
  Ctl: TTyStyleController;
  leftInk0, rightInk0, leftInk1, rightInk1: Integer;

  { Count opaque-ish ink pixels either side of the button's vertical centre line. The masks
    are half-opaque squares, so which collection was blitted decides which side carries ink. }
  procedure RenderAndCount(out ALeft, ARight: Integer);
  var
    bmp: TBitmap;
    img: TBGRABitmap;
    x, y: Integer;
    P: TBGRAPixel;
  begin
    ALeft := 0; ARight := 0;
    bmp := TBitmap.Create;
    img := nil;
    try
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(W, H);
      bmp.Canvas.Brush.Style := bsSolid;
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, W, H);
      FTool.RenderWhole(bmp.Canvas, Rect(0, 0, W, H), 96);
      img := TBGRABitmap.Create(bmp);
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
        begin
          P := img.GetPixel(x, y);
          // The glyph is tinted to the theme's colour (#FF0000) on a black background.
          if (P.red > 150) and (P.green < 100) and (P.blue < 100) then
          begin
            if x < W div 2 then Inc(ALeft) else Inc(ARight);
          end;
        end;
    finally
      img.Free;
      bmp.Free;
    end;
  end;

begin
  { The test that stops these from being properties the paint ignores. Everything above asks
    the seam what it WOULD answer; this one reads the answer back out of the pixels. }
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #000000; color: #FF0000; border-width: 0px; '
      + 'padding: 4px 4px; font-size: 12px; }');
    FBar.Controller := Ctl;
    FTool.Controller := Ctl;
    FTool.Font.PixelsPerInch := 96;
    FTool.Caption := '';
    FTool.ShowCaption := False;      // icon only, so the glyph owns the content box
    FTool.GlyphSize := 16;
    FTool.SetBounds(0, 0, W, H);
    FBar.HotImages := FHot;

    RenderAndCount(leftInk0, rightInk0);
    AssertTrue('at rest the LEFT-half mask is drawn', leftInk0 > 0);
    AssertEquals('and nothing on the right', 0, rightInk0);

    FTool.SetHoverForTest(True);
    RenderAndCount(leftInk1, rightInk1);
    AssertTrue('hovered, the RIGHT-half hot mask is drawn instead', rightInk1 > 0);
    AssertEquals('and nothing on the left', 0, leftInk1);
    AssertEquals('the same amount of ink — a swap, not a resize', leftInk0, rightInk1);

    FTool.Free;   // before its controller
    FTool := nil;
    FBar.Controller := nil;
  finally
    Ctl.Free;
  end;
end;

procedure TToolBarStateImagesTest.TestFreeingAnAlternateNilsTheReference;
var
  tmp: TTyImageCollection;
  m: TBGRABitmap;
begin
  { FreeNotification, not just the Notification override: a collection created with Owner=nil
    would be freed without a word and every tool paint reads these references. }
  tmp := TTyImageCollection.Create(nil);
  try
    m := MakeHalfMask(False);
    try tmp.AddBitmap('save', m); finally m.Free; end;
    FBar.HotImages := tmp;
    AssertTrue('assigned', FBar.HotImages = tmp);
  finally
    tmp.Free;
  end;
  AssertTrue('freeing the collection nils HotImages', FBar.HotImages = nil);
  AssertTrue('and a hover still resolves the normal art rather than a dangling pointer',
    FTool.CallGlyphSource([tysHover]).Images = FNormal);
end;

initialization
  RegisterTest(TToolBarGeomTest);
  RegisterTest(TToolBarBreakTest);
  RegisterTest(TToolBarControlTest);
  RegisterTest(TToolFloorWidthTest);
  RegisterTest(TToolBarMembersTest);
  RegisterTest(TToolBarPixelTest);
  RegisterTest(TToolGroupBoundsTest);
  RegisterTest(TToolWrapShiftTest);
  RegisterTest(TToolButtonTest);
  RegisterTest(TToolButtonSeparatorPixelTest);
  RegisterTest(TToolBarStateImagesTest);
end.
