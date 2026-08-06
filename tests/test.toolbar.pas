unit test.toolbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ImageCollection, tyControls.Menu,
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
  end;

  { The separator control, rendered on the same canvas so its ink can be compared byte for
    byte with a tbsDivider tool button's. }
  TToolSeparatorAccess = class(TTyToolSeparator)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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

initialization
  RegisterTest(TToolBarGeomTest);
  RegisterTest(TToolBarBreakTest);
  RegisterTest(TToolBarControlTest);
  RegisterTest(TToolBarPixelTest);
  RegisterTest(TToolGroupBoundsTest);
  RegisterTest(TToolWrapShiftTest);
  RegisterTest(TToolButtonTest);
  RegisterTest(TToolButtonSeparatorPixelTest);
end.
