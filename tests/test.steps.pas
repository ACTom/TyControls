unit test.steps;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Steps;

type
  { Pure-rule tests: the status rule, the state mapping, the cell tiling, the per-step
    layout for both orientations and the preferred-size inverse all take only integers, so
    they run with no window handle and no control instance at all. }
  TTyStepsRulesTest = class(TTestCase)
  published
    procedure TestStatusIsDerivedFromStepIndex;
    procedure TestStatusNotStartedAndFinishedCursors;
    procedure TestStatusErrorWinsAnywhere;
    procedure TestStatusOutOfRangeIsWait;
    procedure TestStatesMapOntoExistingStates;
    procedure TestStatesNeverEmptyAndErrorIsNotAState;
    procedure TestCellsTileThePaddedBand;
    procedure TestCellsTileVertically;
    procedure TestCellRectDegenerate;
    procedure TestIndexAtIsTheInverseOfCellRect;
    procedure TestIndexAtGutterIsNoStep;
    procedure TestHorizontalLayoutMarkerTitleConnector;
    procedure TestVerticalLayoutMarkerTitleConnector;
    procedure TestLastStepHasNoConnector;
    procedure TestConnectorMeetsTheNextMarker;
    procedure TestTitleAndConnectorNeverOverlapHorizontally;
    procedure TestLayoutSquashesIntoATinyCell;
    procedure TestLayoutZeroCellIsEmpty;
    procedure TestPreferredSizeRoundTripsHorizontal;
    procedure TestPreferredSizeRoundTripsVertical;
    procedure TestPreferredSizeWidestTitleWidensTheCell;
    procedure TestStepIndexStepClampsOntoARealStep;
  end;

  { Headless control behaviour: typeKey, defaults, the derived status, theme-token wiring
    (padding + every metric), the click/key rules and their Clickable gate, AutoSize
    measurement, and graceful degradation when the theme leaves a key undefined. }
  TTyStepsControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FChanged: Integer;    // OnChange fire count
    procedure HandleChange(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestStepStatusFollowsStepIndex;
    procedure TestStepIndexIsNotClampedToItems;
    procedure TestItemsEditKeepsStepIndex;
    procedure TestOnChangeFiresOnceOnRealChange;
    procedure TestCellsFollowThemePadding;
    procedure TestMarkerSizeMetricRetunesTheMarker;
    procedure TestConnectorMetricsRetuneTheLine;
    procedure TestClickMovesTheCursorWhenClickable;
    procedure TestClickIsInertWhenNotClickable;
    procedure TestClickableTogglesTabStop;
    procedure TestArrowKeysFollowOrientation;
    procedure TestKeysAreInertWhenNotClickable;
    procedure TestPreferredSizeHugsSteps;
    procedure TestVerticalPreferredHeightGrowsPerStep;
    procedure TestCurrentMarkerRendersSelectedFill;
    procedure TestTitleDoesNotTakeTheSelectedMarkerInk;
    procedure TestWaitingConnectorTakesDisabledInk;
    procedure TestErrorStepResolvesTheErrorVariant;
    procedure TestUndefinedStripKeyDrawsNothing;
    procedure TestUndefinedItemKeyStillDrawsTitlesInTheStripInk;
    procedure TestUndefinedConnectorKeyDrawsNoLine;
  end;

  { The .lfm path, which is the one that shipped broken.

    Clickable's setter couples TabStop to it, but skips that while csLoading is set — and a
    form file that says `Clickable = True` does NOT have to carry `TabStop = True` with it
    (TabStop's declared default is False, so a hand-written .lfm simply omits it; the
    antdesign example is exactly this). The rail then loaded with TabStop=False: Tab could
    not reach it and a click could not focus it either (TTyCustomControl.MouseDown gates
    click-to-focus on TabStop), so its arrow keys — half of what Clickable buys — never got
    a key to handle. TTySteps.Loaded re-asserts the coupling.

    Note the assertion is on TabStop, not on an arrow key: KeyDown itself never looked at
    TabStop, so sending VK_RIGHT here would pass with or without the fix. Reachability IS
    the bug, and TabStop is what expresses it. }
  TTyStepsStreamingTest = class(TTestCase)
  published
    procedure TestClickableRailStreamsInFocusable;
    procedure TestInertRailStreamsInWithoutATabStop;
  end;

implementation

type
  { Reaches the protected paint + input seams. }
  TStepsAccess = class(TTySteps)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PressAt(X, Y: Integer);
    procedure SendKey(AKey: Word);
    { The size AutoSize would fit the rail to. Called directly rather than through AutoSize
      itself: LCL's AutoSizeDelayed suppresses every re-fit while the parent form has no
      handle (the headless runner never realises one), so driving AutoSize here would assert
      on inert plumbing instead of on this control's measurement. }
    procedure PreferredSize(out AWidth, AHeight: Integer);
  end;

function TStepsAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TStepsAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TStepsAccess.PressAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TStepsAccess.SendKey(AKey: Word);
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, []);
end;

procedure TStepsAccess.PreferredSize(out AWidth, AHeight: Integer);
begin
  AWidth := 0;
  AHeight := 0;
  CalculatePreferredSize(AWidth, AHeight, True);
end;

{ Build a rail with ACount steps wired to the test's controller. }
function MakeSteps(AForm: TForm; ACtl: TTyStyleController; ACount: Integer): TStepsAccess;
var
  i: Integer;
begin
  Result := TStepsAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  for i := 1 to ACount do
    Result.Items.Add('Step ' + IntToStr(i));
end;

{ Render a rail into an offscreen bitmap and hand back a re-read BGRA copy. }
function RenderSteps(ASteps: TStepsAccess): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(ASteps.Width, ASteps.Height);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, ASteps.Width, ASteps.Height);
    ASteps.RenderTo(Bmp.Canvas, Rect(0, 0, ASteps.Width, ASteps.Height), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ Is there a strongly BLUE pixel anywhere in ARect? (The themes below paint the thing under
  test #3B82F6 and everything else white/black, so blue can only be that thing.) }
function HasBlue(ABmp: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= ABmp.Width) or (y >= ABmp.Height) then Continue;
      px := ABmp.GetPixel(x, y);
      if (px.blue > 180) and (px.red < 120) then Exit(True);
    end;
end;

{ Is there a strongly GREEN pixel anywhere in ARect? }
function HasGreen(ABmp: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= ABmp.Width) or (y >= ABmp.Height) then Continue;
      px := ABmp.GetPixel(x, y);
      if (px.green > 120) and (px.green > px.red + 30) and (px.green > px.blue + 30) then
        Exit(True);
    end;
end;

{ TTyStepsRulesTest }

procedure TTyStepsRulesTest.TestStatusIsDerivedFromStepIndex;
begin
  // THE rule the whole control rests on: nothing per-step is stored, the cursor decides.
  AssertTrue('before the cursor = done', TyStepStatus(0, 2, -1, 4) = sstFinish);
  AssertTrue('before the cursor = done', TyStepStatus(1, 2, -1, 4) = sstFinish);
  AssertTrue('at the cursor = current', TyStepStatus(2, 2, -1, 4) = sstProcess);
  AssertTrue('after the cursor = waiting', TyStepStatus(3, 2, -1, 4) = sstWait);
end;

procedure TTyStepsRulesTest.TestStatusNotStartedAndFinishedCursors;
var
  i: Integer;
begin
  // -1 and Count are REAL wizard states, not out-of-range accidents: the cursor is a
  // progress counter, so it may point before the first step and past the last one.
  for i := 0 to 2 do
    AssertTrue('cursor -1 => nothing started', TyStepStatus(i, -1, -1, 3) = sstWait);
  for i := 0 to 2 do
    AssertTrue('cursor = Count => everything done', TyStepStatus(i, 3, -1, 3) = sstFinish);
end;

procedure TTyStepsRulesTest.TestStatusErrorWinsAnywhere;
begin
  // On the current step...
  AssertTrue('error beats current', TyStepStatus(1, 1, 1, 3) = sstError);
  // ...and on one already walked past (a wizard can report a step failed after moving on).
  AssertTrue('error beats done', TyStepStatus(0, 2, 0, 3) = sstError);
  AssertTrue('error beats waiting', TyStepStatus(2, 0, 2, 3) = sstError);
  // Its neighbours are untouched.
  AssertTrue('only the failed step is error', TyStepStatus(0, 1, 1, 3) = sstFinish);
  // -1 disables it entirely (the default).
  AssertTrue('no error index => no error step', TyStepStatus(0, 1, -1, 3) = sstFinish);
end;

procedure TTyStepsRulesTest.TestStatusOutOfRangeIsWait;
begin
  AssertTrue('negative index', TyStepStatus(-1, 1, -1, 3) = sstWait);
  AssertTrue('index past the end', TyStepStatus(3, 1, -1, 3) = sstWait);
  AssertTrue('no steps at all', TyStepStatus(0, 0, -1, 0) = sstWait);
end;

procedure TTyStepsRulesTest.TestStatesMapOntoExistingStates;
begin
  // The whole status->state vocabulary, and every value is an EXISTING TTyState.
  AssertTrue('done = the resting layer', TyStepStates(0, 2, 4) = [tysNormal]);
  AssertTrue('current = :selected', TyStepStates(2, 2, 4) = [tysSelected]);
  AssertTrue('waiting = :disabled', TyStepStates(3, 2, 4) = [tysDisabled]);
end;

procedure TTyStepsRulesTest.TestStatesNeverEmptyAndErrorIsNotAState;
var
  i: Integer;
begin
  // An empty state set would resolve the bare rule and silently lose the whole cascade.
  for i := -1 to 4 do
    AssertTrue('never the empty set', TyStepStates(i, 2, 4) <> []);
  // Error is a VARIANT, not a state: this function does not even take an error index, so a
  // failed step keeps the state its POSITION implies. (Guards the axis split — if someone
  // later folds error in here it will have to break this test on purpose.)
  AssertTrue('a failed current step is still :selected', TyStepStates(1, 1, 3) = [tysSelected]);
end;

procedure TTyStepsRulesTest.TestCellsTileThePaddedBand;
var
  c0, c1, c2: TRect;
begin
  // 300 wide, pad 6 all round, 3 steps: the cells split the padded band and ABUT exactly.
  c0 := TyStepsCellRect(300, 60, 3, 0, False, 6, 6, 6, 6);
  c1 := TyStepsCellRect(300, 60, 3, 1, False, 6, 6, 6, 6);
  c2 := TyStepsCellRect(300, 60, 3, 2, False, 6, 6, 6, 6);
  AssertEquals('first cell starts at the left padding', 6, c0.Left);
  AssertEquals('cell 0 -> cell 1 abut', c0.Right, c1.Left);
  AssertEquals('cell 1 -> cell 2 abut', c1.Right, c2.Left);
  AssertEquals('last cell ends at the right padding', 294, c2.Right);
  // The cross axis is the full padded band for every cell.
  AssertEquals('cell top = top padding', 6, c0.Top);
  AssertEquals('cell bottom = height - bottom padding', 54, c0.Bottom);
end;

procedure TTyStepsRulesTest.TestCellsTileVertically;
var
  c0, c1, c2: TRect;
begin
  // Same tiling, other axis: 3 steps down a 300px-tall rail.
  c0 := TyStepsCellRect(120, 300, 3, 0, True, 6, 6, 6, 6);
  c1 := TyStepsCellRect(120, 300, 3, 1, True, 6, 6, 6, 6);
  c2 := TyStepsCellRect(120, 300, 3, 2, True, 6, 6, 6, 6);
  AssertEquals('first cell starts at the top padding', 6, c0.Top);
  AssertEquals('cell 0 -> cell 1 abut', c0.Bottom, c1.Top);
  AssertEquals('cell 1 -> cell 2 abut', c1.Bottom, c2.Top);
  AssertEquals('last cell ends at the bottom padding', 294, c2.Bottom);
  AssertEquals('cell spans the padded width', 6, c0.Left);
  AssertEquals('cell spans the padded width', 114, c0.Right);
end;

procedure TTyStepsRulesTest.TestCellRectDegenerate;
var
  R: TRect;
begin
  R := TyStepsCellRect(300, 60, 0, 0, False, 6, 6, 6, 6);
  AssertEquals('no steps: empty', 0, R.Right - R.Left);
  R := TyStepsCellRect(300, 60, 3, 5, False, 6, 6, 6, 6);
  AssertEquals('index past the end: empty', 0, R.Right - R.Left);
  R := TyStepsCellRect(300, 60, 3, -1, False, 6, 6, 6, 6);
  AssertEquals('negative index: empty', 0, R.Right - R.Left);
  R := TyStepsCellRect(0, 60, 3, 0, False, 6, 6, 6, 6);
  AssertEquals('zero width: empty', 0, R.Right - R.Left);
  // Padding that eats the whole strip: empty, never inverted.
  R := TyStepsCellRect(10, 60, 3, 0, False, 6, 6, 6, 6);
  AssertEquals('padding eats the strip: empty', 0, R.Right - R.Left);
  AssertTrue('and never inverted', R.Right >= R.Left);
end;

procedure TTyStepsRulesTest.TestIndexAtIsTheInverseOfCellRect;
var
  i: Integer;
  R: TRect;
begin
  // Every cell's own centre must answer that cell — the hit-test IS the geometry's inverse.
  for i := 0 to 3 do
  begin
    R := TyStepsCellRect(400, 60, 4, i, False, 6, 6, 6, 6);
    AssertEquals('centre of cell ' + IntToStr(i), i,
      TyStepsIndexAt(400, 60, 4, False, 6, 6, 6, 6, (R.Left + R.Right) div 2,
        (R.Top + R.Bottom) div 2));
    // The near edge belongs to the cell; the far edge is already the next one's.
    AssertEquals('near edge of cell ' + IntToStr(i), i,
      TyStepsIndexAt(400, 60, 4, False, 6, 6, 6, 6, R.Left, R.Top));
  end;
  // Same for the vertical rail.
  for i := 0 to 3 do
  begin
    R := TyStepsCellRect(120, 400, 4, i, True, 6, 6, 6, 6);
    AssertEquals('centre of vertical cell ' + IntToStr(i), i,
      TyStepsIndexAt(120, 400, 4, True, 6, 6, 6, 6, (R.Left + R.Right) div 2,
        (R.Top + R.Bottom) div 2));
  end;
end;

procedure TTyStepsRulesTest.TestIndexAtGutterIsNoStep;
begin
  // The strip's padding gutter belongs to no step.
  AssertEquals('left gutter', -1, TyStepsIndexAt(300, 60, 3, False, 6, 6, 6, 6, 2, 30));
  AssertEquals('top gutter', -1, TyStepsIndexAt(300, 60, 3, False, 6, 6, 6, 6, 150, 2));
  AssertEquals('right gutter', -1, TyStepsIndexAt(300, 60, 3, False, 6, 6, 6, 6, 297, 30));
  AssertEquals('bottom gutter', -1, TyStepsIndexAt(300, 60, 3, False, 6, 6, 6, 6, 150, 57));
  AssertEquals('no steps at all', -1, TyStepsIndexAt(300, 60, 0, False, 6, 6, 6, 6, 150, 30));
end;

procedure TTyStepsRulesTest.TestHorizontalLayoutMarkerTitleConnector;
var
  L: TTyStepsLayout;
begin
  // Cell (0,0)-(100,60); marker 24, gap 8, title line 14, connector gap 8 / size 2.
  // Block = 24 + 8 + 14 = 46, centred in 60 -> top = (60-46) div 2 = 7.
  L := TyStepsItemLayout(Rect(0, 0, 100, 60), False, False, 24, 8, 14, 8, 2);
  AssertEquals('marker at the cell''s left', 0, L.MarkerRect.Left);
  AssertEquals('marker is square-sized', 24, L.MarkerRect.Right - L.MarkerRect.Left);
  AssertEquals('block centred: marker top', 7, L.MarkerRect.Top);
  AssertEquals('marker bottom', 31, L.MarkerRect.Bottom);
  // The title sits UNDER the marker, a gap below it, spanning the whole cell width.
  AssertEquals('title starts a gap under the marker', 39, L.TitleRect.Top);
  AssertEquals('title is one line tall', 53, L.TitleRect.Bottom);
  AssertEquals('title left-aligned with its marker', 0, L.TitleRect.Left);
  AssertEquals('title spans the cell', 100, L.TitleRect.Right);
  // The connector runs right from the marker, at the MARKER's centre (7 + 12 = 19).
  AssertEquals('connector starts a gap right of the marker', 32, L.ConnectorRect.Left);
  AssertEquals('connector stops a gap short of the cell edge', 92, L.ConnectorRect.Right);
  AssertEquals('connector centred on the marker', 18, L.ConnectorRect.Top);
  AssertEquals('connector is the themed thickness', 2,
    L.ConnectorRect.Bottom - L.ConnectorRect.Top);
end;

procedure TTyStepsRulesTest.TestVerticalLayoutMarkerTitleConnector;
var
  L: TTyStepsLayout;
begin
  // Cell (0,0)-(120,60); marker 24 at the cell's TOP-left, title beside it.
  L := TyStepsItemLayout(Rect(0, 0, 120, 60), True, False, 24, 8, 14, 8, 2);
  AssertEquals('marker at the cell''s top-left', 0, L.MarkerRect.Left);
  AssertEquals('marker at the cell''s top-left', 0, L.MarkerRect.Top);
  AssertEquals('marker is square-sized', 24, L.MarkerRect.Right - L.MarkerRect.Left);
  AssertEquals('marker is square-sized', 24, L.MarkerRect.Bottom - L.MarkerRect.Top);
  // The title sits BESIDE the marker, its line centred on the marker's centre (12).
  AssertEquals('title starts a gap right of the marker', 32, L.TitleRect.Left);
  AssertEquals('title runs to the cell edge', 120, L.TitleRect.Right);
  AssertEquals('title centred on the marker', 5, L.TitleRect.Top);
  AssertEquals('title is one line tall', 19, L.TitleRect.Bottom);
  // The connector drops from under the marker, down the marker's centre axis (12).
  AssertEquals('connector starts a gap under the marker', 32, L.ConnectorRect.Top);
  AssertEquals('connector stops a gap short of the cell bottom', 52, L.ConnectorRect.Bottom);
  AssertEquals('connector on the marker''s axis', 11, L.ConnectorRect.Left);
  AssertEquals('connector is the themed thickness', 2,
    L.ConnectorRect.Right - L.ConnectorRect.Left);
end;

procedure TTyStepsRulesTest.TestLastStepHasNoConnector;
var
  L: TTyStepsLayout;
begin
  // There is nothing to join the last step to.
  L := TyStepsItemLayout(Rect(0, 0, 100, 60), False, True, 24, 8, 14, 8, 2);
  AssertEquals('no connector on the last step', 0,
    L.ConnectorRect.Right - L.ConnectorRect.Left);
  AssertTrue('but it still has its marker', L.MarkerRect.Right > L.MarkerRect.Left);
  L := TyStepsItemLayout(Rect(0, 0, 120, 60), True, True, 24, 8, 14, 8, 2);
  AssertEquals('no connector on the last vertical step', 0,
    L.ConnectorRect.Bottom - L.ConnectorRect.Top);
  // A zero thickness also means no line, whatever the theme's gaps say.
  L := TyStepsItemLayout(Rect(0, 0, 100, 60), False, False, 24, 8, 14, 8, 0);
  AssertEquals('zero thickness -> no connector', 0,
    L.ConnectorRect.Right - L.ConnectorRect.Left);
end;

procedure TTyStepsRulesTest.TestConnectorMeetsTheNextMarker;
var
  c0, c1: TRect;
  L0, L1: TTyStepsLayout;
begin
  { The contract that makes the rail read as one line rather than as dashes: the connector
    leaving step 0 stops exactly one connector-gap short of step 1's marker. This is why the
    markers are anchored to the cell's LEADING edge — the next marker's left IS this cell's
    right, so the pure per-cell function can guarantee it without ever seeing cell 1. }
  c0 := TyStepsCellRect(300, 60, 3, 0, False, 0, 0, 0, 0);
  c1 := TyStepsCellRect(300, 60, 3, 1, False, 0, 0, 0, 0);
  L0 := TyStepsItemLayout(c0, False, False, 24, 8, 14, 8, 2);
  L1 := TyStepsItemLayout(c1, False, True, 24, 8, 14, 8, 2);
  AssertEquals('the connector ends one gap before the next marker',
    L1.MarkerRect.Left - 8, L0.ConnectorRect.Right);
  // And the same down a vertical rail.
  c0 := TyStepsCellRect(120, 300, 3, 0, True, 0, 0, 0, 0);
  c1 := TyStepsCellRect(120, 300, 3, 1, True, 0, 0, 0, 0);
  L0 := TyStepsItemLayout(c0, True, False, 24, 8, 14, 8, 2);
  L1 := TyStepsItemLayout(c1, True, True, 24, 8, 14, 8, 2);
  AssertEquals('the vertical connector ends one gap above the next marker',
    L1.MarkerRect.Top - 8, L0.ConnectorRect.Bottom);
  // ...and it drops down the same axis both markers sit on.
  AssertEquals('both markers share the connector''s axis', L0.MarkerRect.Left, L1.MarkerRect.Left);
end;

procedure TTyStepsRulesTest.TestTitleAndConnectorNeverOverlapHorizontally;
var
  L: TTyStepsLayout;
begin
  // The horizontal layout's whole point: the line runs at the MARKER's height, so it passes
  // ABOVE the title instead of striking through it — however long the title band is.
  L := TyStepsItemLayout(Rect(0, 0, 100, 60), False, False, 24, 8, 14, 8, 2);
  AssertTrue('the connector clears the title band',
    L.ConnectorRect.Bottom <= L.TitleRect.Top);
end;

procedure TTyStepsRulesTest.TestLayoutSquashesIntoATinyCell;
var
  L: TTyStepsLayout;
begin
  // A cell far too small for a 24px marker: squash it in, never past the cell's edges.
  L := TyStepsItemLayout(Rect(0, 0, 10, 8), False, False, 24, 8, 14, 8, 2);
  AssertTrue('marker never overflows the cell', L.MarkerRect.Right <= 10);
  AssertTrue('marker never overflows the cell', L.MarkerRect.Bottom <= 8);
  AssertTrue('and is never inverted', L.MarkerRect.Right >= L.MarkerRect.Left);
  // No room left for a line: an empty rect, not a negative one.
  AssertTrue('connector collapses rather than inverting',
    L.ConnectorRect.Right >= L.ConnectorRect.Left);
  // Same on the vertical side.
  L := TyStepsItemLayout(Rect(0, 0, 10, 8), True, False, 24, 8, 14, 8, 2);
  AssertTrue('vertical marker never overflows', L.MarkerRect.Bottom <= 8);
  AssertTrue('vertical connector never inverts',
    L.ConnectorRect.Bottom >= L.ConnectorRect.Top);
end;

procedure TTyStepsRulesTest.TestLayoutZeroCellIsEmpty;
var
  L: TTyStepsLayout;
begin
  L := TyStepsItemLayout(Rect(0, 0, 0, 60), False, False, 24, 8, 14, 8, 2);
  AssertEquals('zero-width cell: no marker', 0, L.MarkerRect.Right - L.MarkerRect.Left);
  AssertEquals('zero-width cell: no title', 0, L.TitleRect.Right - L.TitleRect.Left);
  AssertEquals('zero-width cell: no connector', 0, L.ConnectorRect.Right - L.ConnectorRect.Left);
  L := TyStepsItemLayout(Rect(0, 0, 100, 0), False, False, 24, 8, 14, 8, 2);
  AssertEquals('zero-height cell: no marker', 0, L.MarkerRect.Right - L.MarkerRect.Left);
end;

procedure TTyStepsRulesTest.TestPreferredSizeRoundTripsHorizontal;
var
  w, h: Integer;
  cell: TRect;
  L: TTyStepsLayout;
begin
  { The contract: feed the preferred size back in and every cell is one natural cell with
    exactly AConnectorLength of line in it. Titles are 0-wide here so the marker+run drives
    the cell: cell = 24 + 8 + 32 + 8 = 72, x3 steps, + 6/6 padding = 228. }
  TyStepsPreferredSize(3, 0, 14, 24, 8, 8, 32, 6, 6, 6, 6, False, w, h);
  AssertEquals('pad + 3 natural cells + pad', 228, w);
  AssertEquals('pad + marker + gap + title + pad', 58, h);
  cell := TyStepsCellRect(w, h, 3, 0, False, 6, 6, 6, 6);
  L := TyStepsItemLayout(cell, False, False, 24, 8, 14, 8, 2);
  AssertEquals('the connector comes out at its natural length', 32,
    L.ConnectorRect.Right - L.ConnectorRect.Left);
  AssertEquals('and the marker is whole', 24, L.MarkerRect.Right - L.MarkerRect.Left);
  // The cross axis fits the block exactly: the title lands on the bottom padding.
  AssertEquals('the title block fills the padded height', h - 6, L.TitleRect.Bottom);
end;

procedure TTyStepsRulesTest.TestPreferredSizeRoundTripsVertical;
var
  w, h: Integer;
  cell: TRect;
  L: TTyStepsLayout;
begin
  // Vertical: the main axis is the height. cell = 24 + 8 + 32 + 8 = 72, x3 + 6/6 = 228.
  TyStepsPreferredSize(3, 50, 14, 24, 8, 8, 32, 6, 6, 6, 6, True, w, h);
  AssertEquals('pad + 3 natural rows + pad', 228, h);
  // 6 + 24 + 8 + 50 + 6
  AssertEquals('pad + marker + gap + widest title + pad', 94, w);
  cell := TyStepsCellRect(w, h, 3, 0, True, 6, 6, 6, 6);
  L := TyStepsItemLayout(cell, True, False, 24, 8, 14, 8, 2);
  AssertEquals('the connector comes out at its natural length', 32,
    L.ConnectorRect.Bottom - L.ConnectorRect.Top);
  // The title band ends exactly on the right padding, i.e. the widest title fits whole.
  AssertEquals('the widest title fits exactly', 50, L.TitleRect.Right - L.TitleRect.Left);
end;

procedure TTyStepsRulesTest.TestPreferredSizeWidestTitleWidensTheCell;
var
  narrowW, wideW, h: Integer;
begin
  // Horizontal: a title wider than the marker+run run is what sets the cell width.
  TyStepsPreferredSize(3, 0, 14, 24, 8, 8, 32, 0, 0, 0, 0, False, narrowW, h);
  TyStepsPreferredSize(3, 200, 14, 24, 8, 8, 32, 0, 0, 0, 0, False, wideW, h);
  AssertEquals('the natural cell floors the width', 216, narrowW);
  AssertEquals('a wide title takes over: 3 x 200', 600, wideW);
  // Vertical: the title widens the rail instead, and does NOT change its height.
  TyStepsPreferredSize(3, 200, 14, 24, 8, 8, 32, 0, 0, 0, 0, True, wideW, h);
  AssertEquals('the vertical rail hugs its widest title', 232, wideW);
  AssertEquals('and its height is unchanged by the title width', 216, h);
end;

procedure TTyStepsRulesTest.TestStepIndexStepClampsOntoARealStep;
begin
  AssertEquals('forward', 2, TyStepsStepIndex(1, 4, 1));
  AssertEquals('back', 0, TyStepsStepIndex(1, 4, -1));
  // No wrap at either end.
  AssertEquals('stops at the last step', 3, TyStepsStepIndex(3, 4, 1));
  AssertEquals('stops at the first step', 0, TyStepsStepIndex(0, 4, -1));
  // Both cursor states outside the rail get dragged back ONTO it.
  AssertEquals('from "not started", forward enters at 0', 0, TyStepsStepIndex(-1, 4, 1));
  AssertEquals('from "not started", back also lands on 0', 0, TyStepsStepIndex(-1, 4, -1));
  AssertEquals('from "finished", back lands on the last step', 3, TyStepsStepIndex(4, 4, -1));
  AssertEquals('no steps at all', -1, TyStepsStepIndex(0, 0, 1));
end;

{ TTyStepsControlTest }

procedure TTyStepsControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FChanged := 0;
end;

procedure TTyStepsControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyStepsControlTest.HandleChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TTyStepsControlTest.TestTypeKey;
var
  T: TStepsAccess;
begin
  T := MakeSteps(FForm, FCtl, 3);
  try
    AssertEquals('TySteps', T.StyleTypeKey);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestDefaults;
var
  T: TTySteps;
begin
  T := TTySteps.Create(FForm);
  try
    AssertEquals('no steps by default', 0, T.Count);
    AssertEquals('cursor starts before the first step', -1, T.StepIndex);
    AssertEquals('no failed step', -1, T.ErrorIndex);
    AssertTrue('horizontal by default', T.Orientation = soHorizontal);
    AssertFalse('an inert status display by default', T.Clickable);
    AssertFalse('and therefore not a tab stop', T.TabStop);
    AssertEquals('default width 360', 360, T.Width);
    AssertEquals('default height 56', 56, T.Height);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestStepStatusFollowsStepIndex;
var
  T: TTySteps;
begin
  T := MakeSteps(FForm, FCtl, 4);
  try
    T.StepIndex := 2;
    AssertTrue('0 done', T.StepStatus(0) = sstFinish);
    AssertTrue('1 done', T.StepStatus(1) = sstFinish);
    AssertTrue('2 current', T.StepStatus(2) = sstProcess);
    AssertTrue('3 waiting', T.StepStatus(3) = sstWait);
    // The host moves ONE integer and every step re-reads.
    T.StepIndex := 3;
    AssertTrue('2 is now done', T.StepStatus(2) = sstFinish);
    AssertTrue('3 is now current', T.StepStatus(3) = sstProcess);
    // ErrorIndex overlays the derived status without disturbing the cursor.
    T.ErrorIndex := 1;
    AssertTrue('1 failed', T.StepStatus(1) = sstError);
    AssertTrue('its neighbour is untouched', T.StepStatus(0) = sstFinish);
    AssertEquals('the cursor did not move', 3, T.StepIndex);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestStepIndexIsNotClampedToItems;
var
  T: TTySteps;
  i: Integer;
begin
  // Unlike TTySegmented.ItemIndex (a selection), the cursor is a PROGRESS counter: past
  // the end means "finished", which is exactly what the last Next click produces.
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.StepIndex := 3;
    AssertEquals('the finished cursor is kept verbatim', 3, T.StepIndex);
    for i := 0 to 2 do
      AssertTrue('every step reads done', T.StepStatus(i) = sstFinish);
    T.StepIndex := -1;
    AssertEquals('the not-started cursor is kept verbatim', -1, T.StepIndex);
    for i := 0 to 2 do
      AssertTrue('every step reads waiting', T.StepStatus(i) = sstWait);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestItemsEditKeepsStepIndex;
var
  T: TTySteps;
begin
  // Editing Items must NOT silently re-validate the cursor (TTySegmented does re-validate
  // its ItemIndex here): "3 of 3 = finished" stays meaningful when a 4th step arrives, and
  // it then correctly means "on the last one".
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.StepIndex := 3;
    T.Items.Add('Step 4');
    AssertEquals('the cursor survived the edit', 3, T.StepIndex);
    AssertTrue('and now points at the new last step', T.StepStatus(3) = sstProcess);
    T.Items.Clear;
    AssertEquals('and survives even an empty list', 3, T.StepIndex);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestOnChangeFiresOnceOnRealChange;
var
  T: TTySteps;
begin
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.OnChange := @HandleChange;
    T.StepIndex := 1;
    AssertEquals('fired once', 1, FChanged);
    T.StepIndex := 1;
    AssertEquals('setting the same cursor is not a change', 1, FChanged);
    T.StepIndex := 2;
    AssertEquals('fired again', 2, FChanged);
    // ErrorIndex is not a cursor move: the wizard did not go anywhere.
    T.ErrorIndex := 0;
    AssertEquals('ErrorIndex is silent', 2, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestCellsFollowThemePadding;
var
  T: TStepsAccess;
  c0, c2: TRect;
begin
  // The strip's inset is the THEME's padding, not a literal.
  FCtl.LoadThemeCss('TySteps { background: #FFFFFF; color: #111111; padding: 4px 10px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    c0 := T.TyStepRect(0);
    c2 := T.TyStepRect(2);
    AssertEquals('first cell starts at the themed left padding', 10, c0.Left);
    AssertEquals('last cell ends at the themed right padding', 290, c2.Right);
    AssertEquals('cells start at the themed top padding', 4, c0.Top);
    AssertEquals('cells end at the themed bottom padding', 56, c0.Bottom);
    // And the hit-test moves with it: the gutter is now 10px wide.
    AssertEquals('the themed gutter is no step', -1, T.TyStepAt(5, 30));
    AssertEquals('just inside it is step 0', 0, T.TyStepAt(11, 30));
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestMarkerSizeMetricRetunesTheMarker;
var
  T: TStepsAccess;
  L: TTyStepsLayout;
begin
  // --steps-marker-size is a skin-tunable metric: a theme that sets it moves the painted
  // geometry, proving the marker size is not baked into the control.
  FCtl.LoadThemeCss(
    ':root { --steps-marker-size: 40px; }' +
    'TySteps { background: #FFFFFF; color: #111111; padding: 0px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 80);
    L := T.TyStepLayout(0);
    AssertEquals('the marker takes the themed size', 40, L.MarkerRect.Right - L.MarkerRect.Left);
    AssertEquals('and is square', 40, L.MarkerRect.Bottom - L.MarkerRect.Top);
    // The default is what an unset token falls back to (the constant IS the token's default).
    FCtl.LoadThemeCss('TySteps { background: #FFFFFF; color: #111111; padding: 0px; }');
    L := T.TyStepLayout(0);
    AssertEquals('unset -> the built-in default', TyStepsMarkerSize,
      L.MarkerRect.Right - L.MarkerRect.Left);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestConnectorMetricsRetuneTheLine;
var
  T: TStepsAccess;
  L: TTyStepsLayout;
  markerRight: Integer;
begin
  // Both connector metrics are live: the thickness and the clearance from the marker.
  FCtl.LoadThemeCss(
    ':root { --steps-connector-size: 5px; --steps-connector-gap: 12px; }' +
    'TySteps { background: #FFFFFF; color: #111111; padding: 0px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 80);
    L := T.TyStepLayout(0);
    AssertEquals('the line takes the themed thickness', 5,
      L.ConnectorRect.Bottom - L.ConnectorRect.Top);
    markerRight := L.MarkerRect.Right;
    AssertEquals('and the themed clearance from the marker', markerRight + 12,
      L.ConnectorRect.Left);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestClickMovesTheCursorWhenClickable;
var
  T: TStepsAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss('TySteps { background: #FFFFFF; color: #111111; padding: 0px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.Clickable := True;
    T.OnChange := @HandleChange;
    R := T.TyStepRect(2);
    T.PressAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('the click moved the cursor', 2, T.StepIndex);
    AssertEquals('and announced it', 1, FChanged);
    // The WHOLE cell is the target, title included — not just the marker.
    R := T.TyStepRect(0);
    T.PressAt(R.Left + 2, R.Bottom - 2);
    AssertEquals('a click low in the cell still selects it', 0, T.StepIndex);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestClickIsInertWhenNotClickable;
var
  T: TStepsAccess;
  R: TRect;
begin
  // The default rail is a status display: a click must not move the wizard.
  FCtl.LoadThemeCss('TySteps { background: #FFFFFF; color: #111111; padding: 0px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 1;
    T.OnChange := @HandleChange;
    R := T.TyStepRect(2);
    T.PressAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('the cursor did not move', 1, T.StepIndex);
    AssertEquals('and nothing was announced', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestClickableTogglesTabStop;
var
  T: TTySteps;
begin
  // Focusability follows clickability: the arrow keys are half of what Clickable buys, and
  // an inert rail must not eat a tab stop.
  T := MakeSteps(FForm, FCtl, 3);
  try
    AssertFalse('inert by default', T.TabStop);
    T.Clickable := True;
    AssertTrue('a navigable rail takes a tab stop', T.TabStop);
    T.Clickable := False;
    AssertFalse('and gives it back', T.TabStop);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestArrowKeysFollowOrientation;
var
  T: TStepsAccess;
begin
  FCtl.LoadThemeCss('TySteps { background: #FFFFFF; color: #111111; padding: 0px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.Clickable := True;
    T.StepIndex := 1;
    // Horizontal: Left/Right walk the rail, Up/Down are left for the form.
    T.SendKey(VK_RIGHT);
    AssertEquals('Right walks forward', 2, T.StepIndex);
    T.SendKey(VK_LEFT);
    AssertEquals('Left walks back', 1, T.StepIndex);
    T.SendKey(VK_DOWN);
    AssertEquals('Down is not ours on a horizontal rail', 1, T.StepIndex);
    T.SendKey(VK_HOME);
    AssertEquals('Home jumps to the first step', 0, T.StepIndex);
    T.SendKey(VK_END);
    AssertEquals('End jumps to the last step', 2, T.StepIndex);
    T.SendKey(VK_RIGHT);
    AssertEquals('and it does not wrap', 2, T.StepIndex);
    // Vertical: the pair that points along the rail swaps over.
    T.Orientation := soVertical;
    T.StepIndex := 1;
    T.SendKey(VK_UP);
    AssertEquals('Up walks back on a vertical rail', 0, T.StepIndex);
    T.SendKey(VK_DOWN);
    AssertEquals('Down walks forward on a vertical rail', 1, T.StepIndex);
    T.SendKey(VK_RIGHT);
    AssertEquals('Right is not ours on a vertical rail', 1, T.StepIndex);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestKeysAreInertWhenNotClickable;
var
  T: TStepsAccess;
begin
  FCtl.LoadThemeCss('TySteps { background: #FFFFFF; color: #111111; padding: 0px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 1;
    T.SendKey(VK_RIGHT);
    AssertEquals('an inert rail ignores the arrows', 1, T.StepIndex);
    T.SendKey(VK_HOME);
    AssertEquals('and Home/End too', 1, T.StepIndex);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestPreferredSizeHugsSteps;
var
  T: TStepsAccess;
  threeW, fourW, h: Integer;
begin
  // AutoSize measures a natural cell PER STEP, so a step more is a wider rail.
  FCtl.LoadThemeCss(
    'TySteps { background: #FFFFFF; color: #111111; padding: 6px; font-size: 12px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.PreferredSize(threeW, h);
    T.Items.Add('Step 4');
    T.PreferredSize(fourW, h);
    AssertTrue('a fourth step needs a wider rail', fourW > threeW);
    AssertTrue('the rail clears its themed padding', threeW > 12);
    // The cross axis must clear the marker + gap + a title line, at least.
    AssertTrue('the rail is tall enough for a marker and a title',
      h > TyStepsMarkerSize + TyStepsGap);
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestVerticalPreferredHeightGrowsPerStep;
var
  T: TStepsAccess;
  w, threeH, fourH: Integer;
begin
  // The other orientation grows along the other axis — the same rule, turned 90 degrees.
  FCtl.LoadThemeCss(
    'TySteps { background: #FFFFFF; color: #111111; padding: 6px; font-size: 12px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.Orientation := soVertical;
    T.PreferredSize(w, threeH);
    T.Items.Add('Step 4');
    T.PreferredSize(w, fourH);
    AssertTrue('a fourth step needs a taller rail', fourH > threeH);
    // Each step costs exactly one natural row: marker + gap + length + gap.
    AssertEquals('one natural row per step',
      TyStepsMarkerSize + 2 * TyStepsConnectorGap + TyStepsConnectorLength,
      fourH - threeH);
  finally
    T.Free;
  end;
end;

{ TestCurrentMarkerRendersSelectedFill
  Theme: only :selected fills the marker, in blue. Probe the CURRENT step's marker and a
  waiting one's — the blue disc must be on the current step and nowhere else, i.e. the
  status rule reaches the paint through the state cascade with no code branch. }
procedure TTyStepsControlTest.TestCurrentMarkerRendersSelectedFill;
var
  T: TStepsAccess;
  Reread: TBGRABitmap;
  L: TTyStepsLayout;
begin
  FCtl.LoadThemeCss(
    'TySteps { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }' +
    'TyStepsItem { border-radius: 0px; }' +
    'TyStepsItem:selected { background: #3B82F6; color: #FFFFFF; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 1;
    Reread := RenderSteps(T);
    try
      L := T.TyStepLayout(1);
      AssertTrue('the current step''s marker is filled', HasBlue(Reread, L.MarkerRect));
      L := T.TyStepLayout(2);
      AssertFalse('a waiting step''s marker is not', HasBlue(Reread, L.MarkerRect));
      L := T.TyStepLayout(0);
      AssertFalse('a done step''s marker is not either', HasBlue(Reread, L.MarkerRect));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

{ TestTitleDoesNotTakeTheSelectedMarkerInk
  The two-ink rule (TTyCheckBox's, which resolves its caption without tysActive): the
  current step's marker is a blue chip with WHITE ink, but its title must NOT be white or
  it would be invisible on the white strip. Theme the strip green-inked and the :selected
  layer white-inked: a green title under the current marker proves the title resolved the
  RESTING layer and never saw ':selected'. }
procedure TTyStepsControlTest.TestTitleDoesNotTakeTheSelectedMarkerInk;
var
  T: TStepsAccess;
  Reread: TBGRABitmap;
  L: TTyStepsLayout;
begin
  FCtl.LoadThemeCss(
    'TySteps { background: #FFFFFF; color: #10B981; font-size: 12px; padding: 0px; }' +
    'TyStepsItem { border-radius: 0px; }' +
    'TyStepsItem:selected { background: #3B82F6; color: #FFFFFF; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 1;
    Reread := RenderSteps(T);
    try
      L := T.TyStepLayout(1);
      AssertTrue('the current step''s title keeps the resting ink',
        HasGreen(Reread, L.TitleRect));
      // ...while the marker beside it really is the :selected chip.
      AssertTrue('the current step''s marker took :selected',
        HasBlue(Reread, L.MarkerRect));
      AssertFalse('and the title is not on the blue chip''s ink',
        HasBlue(Reread, L.TitleRect));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

{ TestWaitingConnectorTakesDisabledInk
  The connector takes the states of the step it LEADS TO, which is what lights the trail
  exactly as far as the user has walked. Cursor on step 1 of 3: the line 0->1 leads into
  the CURRENT step (travelled, blue) and the line 1->2 into a WAITING one (grey). }
procedure TTyStepsControlTest.TestWaitingConnectorTakesDisabledInk;
var
  T: TStepsAccess;
  Reread: TBGRABitmap;
  L: TTyStepsLayout;
begin
  FCtl.LoadThemeCss(
    'TySteps { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }' +
    'TyStepsItem { border-radius: 0px; }' +
    ':root { --steps-connector-size: 4px; }' +
    'TyStepsConnector { background: #3B82F6; }' +
    'TyStepsConnector:disabled { background: #10B981; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 1;
    Reread := RenderSteps(T);
    try
      L := T.TyStepLayout(0);
      AssertTrue('the line INTO the current step is travelled', HasBlue(Reread, L.ConnectorRect));
      AssertFalse('and is not the untravelled ink', HasGreen(Reread, L.ConnectorRect));
      L := T.TyStepLayout(1);
      AssertTrue('the line into a waiting step is not', HasGreen(Reread, L.ConnectorRect));
      AssertFalse('and is not the travelled ink', HasBlue(Reread, L.ConnectorRect));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

{ TestErrorStepResolvesTheErrorVariant
  Error is a VARIANT, not a state: the failed step must pick up `TyStepsItem.error` while
  keeping the state of its position. Theme only the .error variant blue: exactly the failed
  step's marker goes blue, and moving ErrorIndex moves the blue with it. }
procedure TTyStepsControlTest.TestErrorStepResolvesTheErrorVariant;
var
  T: TStepsAccess;
  Reread: TBGRABitmap;
  L: TTyStepsLayout;
begin
  FCtl.LoadThemeCss(
    'TySteps { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }' +
    'TyStepsItem { border-radius: 0px; }' +
    'TyStepsItem.error { background: #3B82F6; color: #FFFFFF; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 2;
    T.ErrorIndex := 1;
    Reread := RenderSteps(T);
    try
      L := T.TyStepLayout(1);
      AssertTrue('the failed step resolved .error', HasBlue(Reread, L.MarkerRect));
      L := T.TyStepLayout(0);
      AssertFalse('its neighbour did not', HasBlue(Reread, L.MarkerRect));
    finally
      Reread.Free;
    end;
    // No .error rule in the theme -> the step degrades to an ordinary-looking one, never
    // to a hard-coded red.
    FCtl.LoadThemeCss(
      'TySteps { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }' +
      'TyStepsItem { border-radius: 0px; }');
    Reread := RenderSteps(T);
    try
      L := T.TyStepLayout(1);
      AssertFalse('no .error rule -> no invented colour', HasBlue(Reread, L.MarkerRect));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestUndefinedStripKeyDrawsNothing;
var
  T: TStepsAccess;
  Reread: TBGRABitmap;
begin
  // A theme that gives the strip no BACKGROUND must degrade, not invent a look: nothing of
  // ours is drawn at all — not even the steps, whose own key IS defined here.
  // The TySteps rule below is deliberately present-but-backgroundless rather than absent:
  // the compiled-in base layer (themes/light.tycss) backs every typeKey a theme omits, so
  // "leave the rule out" would silently stop testing degradation the moment the base defines
  // TySteps. Any user rule for a typeKey suppresses the whole base layer for it
  // (TTyStyleModel.UserHasTypeKey), so this is how you get a genuinely background-less key.
  FCtl.LoadThemeCss(
    'TySteps { color: #000000; }' +
    'TyStepsItem:selected { background: #3B82F6; color: #FFFFFF; }' +
    'TyStepsConnector { background: #3B82F6; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 1;
    Reread := RenderSteps(T);
    try
      AssertFalse('no strip key -> no markers and no lines anywhere',
        HasBlue(Reread, Rect(0, 0, 300, 60)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestUndefinedItemKeyStillDrawsTitlesInTheStripInk;
var
  T: TStepsAccess;
  Reread: TBGRABitmap;
  L: TTyStepsLayout;
begin
  // The other degradation half: a step key carrying no COLOUR gets no chips (no background
  // to draw one from) but its titles and numbers still appear, in the STRIP's own ink.
  // White strip, GREEN ink, and a TyStepsItem rule with neither background nor color: any
  // green in a step can only be text that inherited the strip's colour — never a hard-coded
  // fallback. (The item rule must be PRESENT to suppress the base layer's own TyStepsItem,
  // which will define a colour; omitting it would inherit that instead and test nothing.
  // Same reason as TestUndefinedStripKeyDrawsNothing.)
  FCtl.LoadThemeCss(
    'TySteps { background: #FFFFFF; color: #10B981; font-size: 12px; padding: 0px; }' +
    'TyStepsItem { border-radius: 0px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 1;
    Reread := RenderSteps(T);
    try
      L := T.TyStepLayout(1);
      AssertTrue('the title inherits the strip ink', HasGreen(Reread, L.TitleRect));
      AssertTrue('and so does the marker''s number', HasGreen(Reread, L.MarkerRect));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyStepsControlTest.TestUndefinedConnectorKeyDrawsNoLine;
var
  T: TStepsAccess;
  Reread: TBGRABitmap;
  L: TTyStepsLayout;
begin
  // No connector background -> no line, and the markers still draw. (Present-but-
  // backgroundless again, to suppress the base layer's own TyStepsConnector.)
  FCtl.LoadThemeCss(
    'TySteps { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }' +
    'TyStepsItem { border-radius: 0px; }' +
    'TyStepsItem:selected { background: #3B82F6; color: #FFFFFF; }' +
    ':root { --steps-connector-size: 4px; }' +
    'TyStepsConnector { border-radius: 0px; }');
  T := MakeSteps(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 60);
    T.StepIndex := 1;
    Reread := RenderSteps(T);
    try
      L := T.TyStepLayout(0);
      AssertFalse('no connector background -> no line', HasBlue(Reread, L.ConnectorRect));
      // ...but the rail is still a rail: the current marker is there.
      L := T.TyStepLayout(1);
      AssertTrue('the markers still draw', HasBlue(Reread, L.MarkerRect));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

{ --- streaming ------------------------------------------------------------------------ }

type
  { A streamable root that owns the rail (mirrors test.pagecontrol.streaming). }
  TStepsHostForm = class(TForm)
  published
    Rail: TTySteps;
  end;

{ Load ALfm (LFM text) into a fresh TStepsHostForm and hand back the rail it created.
  Goes through the REAL reader — csLoading set for the property assignments, Loaded called
  once at the end — because that is the sequence the bug lived in. AForm is the caller's to
  free (it owns the rail). }
function LoadRailFromLfm(const ALfm: string; out AForm: TStepsHostForm): TTySteps;
var
  Text_, Bin: TMemoryStream;
begin
  AForm := TStepsHostForm.CreateNew(nil);
  Text_ := TMemoryStream.Create;
  Bin := TMemoryStream.Create;
  try
    Text_.Write(ALfm[1], Length(ALfm));
    Text_.Position := 0;
    ObjectTextToBinary(Text_, Bin);
    Bin.Position := 0;
    Bin.ReadComponent(AForm);
  finally
    Bin.Free;
    Text_.Free;
  end;
  Result := AForm.FindComponent('Rail') as TTySteps;
end;

const
  { Deliberately says nothing about TabStop — that IS the case under test. }
  cClickableLfm =
    'object StepsHost: TStepsHostForm' + LineEnding +
    '  object Rail: TTySteps' + LineEnding +
    '    Clickable = True' + LineEnding +
    '    Items.Strings = (' + LineEnding +
    '      ''One''' + LineEnding +
    '      ''Two''' + LineEnding +
    '    )' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
  cInertLfm =
    'object StepsHost: TStepsHostForm' + LineEnding +
    '  object Rail: TTySteps' + LineEnding +
    '    Items.Strings = (' + LineEnding +
    '      ''One''' + LineEnding +
    '      ''Two''' + LineEnding +
    '    )' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;

procedure TTyStepsStreamingTest.TestClickableRailStreamsInFocusable;
var
  form_: TStepsHostForm;
  rail: TTySteps;
begin
  { Guard against the fixture drifting into a test that cannot fail: the whole point is a
    form file that carries Clickable and NOT TabStop. }
  AssertTrue('the fixture must not mention TabStop', Pos('TabStop', cClickableLfm) = 0);
  rail := LoadRailFromLfm(cClickableLfm, form_);
  try
    AssertNotNull('the rail streamed in', rail);
    AssertTrue('Clickable survived streaming', rail.Clickable);
    AssertEquals('and so did the items', 2, rail.Count);
    AssertTrue('a clickable rail must load focusable, or its arrow keys are unreachable '
      + '(nothing can give it focus: not Tab, not a click)', rail.TabStop);
  finally
    form_.Free;
  end;
end;

procedure TTyStepsStreamingTest.TestInertRailStreamsInWithoutATabStop;
var
  form_: TStepsHostForm;
  rail: TTySteps;
begin
  rail := LoadRailFromLfm(cInertLfm, form_);
  try
    AssertNotNull('the rail streamed in', rail);
    AssertFalse('the default rail is an inert status display', rail.Clickable);
    AssertFalse('so it must not eat a tab stop either', rail.TabStop);
  finally
    form_.Free;
  end;
end;

initialization
  { The reader instantiates the streamed child by class name — register it. }
  RegisterClasses([TTySteps]);
  RegisterTest(TTyStepsRulesTest);
  RegisterTest(TTyStepsControlTest);
  RegisterTest(TTyStepsStreamingTest);
end.
