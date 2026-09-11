unit test.advancechart;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the control.

  RENDERED OFFSCREEN through the protected RenderTo, which is why every control
  in this library splits Paint from RenderTo: the on-screen paint path needs a
  handle and a message loop, and this needs neither.

  What a headless render CAN see is asserted here. What it cannot -- a windowed
  sibling biting the corners flat, a transparent erase showing the parent's LCL
  colour, a control created disabled never becoming clickable -- is on the
  manual checklist in the spec instead of being pretended at. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Layout,
     LazUTF8, tyControls.Painter,
     tyControls.AdvanceChart;
type
  { Re-exposes the protected render so a test can drive it onto a bitmap. }
  TChartProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The LAYERED path, the one Paint takes. Exposed for the same reason Render
      is: Paint needs a handle and a message loop, and a headless test has
      neither. }
    procedure RenderLayered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function TypeKey: string;
  end;

  TAdvanceChartTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(AW: Integer = 400; AH: Integer = 300; APPI: Integer = 96);
    function PixelAt(AX, AY: Integer): TBGRAPixel;
    function InkIn(AL, AT, AR, AB: Integer; const ABg: TBGRAPixel): Integer;
    function ManyCategories(ACount: Integer): string;
    function RedIn(AL, AT, AR, AB: Integer): Integer;
    function GreenIn(AL, AT, AR, AB: Integer): Integer;
    function BlueIn(AL, AT, AR, AB: Integer): Integer;
    function InkDepth(const AP, ABg: TBGRAPixel): Integer;
  published
    procedure TestItHasItsOwnStyleKey;
    procedure TestAnEmptyChartStillPaintsItsSurface;
    procedure TestEveryCornerIsPainted;
    procedure TestTheOptionDrivesTheBuild;
    procedure TestABadOptionBlanksTheChart;
    procedure TestTheOptionReadsBackWhatWasWritten;
    procedure TestWritingTheSameTextTwiceIsANoOp;
    procedure TestDiagnosticsReachTheControl;
    procedure TestAnAxisIsActuallyDrawn;
    procedure TestAValueAxisLabelsItsTicks;
    procedure TestSplitLinesDivideBandsRatherThanPointAtLabels;
    procedure TestTheTicksThemselvesAreDrawn;
    procedure TestAHiddenAxisIsNotDrawn;
    procedure TestTheAxisHonoursMinMaxAndInterval;
    procedure TestAnAxisWithNoDataStillObeysItsOptions;
    procedure TestMinorTicksDoNotGetLabels;
    procedure TestCategoriesCollectedFromSeriesDataReachTheAxis;
    procedure TestAnUnnaturalIntervalIsNotRoundedAway;
    procedure TestALongLabelBreaksToTheWidthItWasGiven;
    procedure TestCJKBreaksBetweenCharactersNotOnSpaces;
    procedure TestTruncateEllipsisesInsteadOfOverflowing;
    procedure TestMinIntervalKeepsACountingAxisWhole;
    procedure TestMaxIntervalCapsTheStep;
    procedure TestAValueAxisBoundaryGapPadsTheExtent;
    procedure TestACrowdedAxisThinsItsLabels;
    procedure TestTheSeriesIsActuallyDrawnInTheThemesColour;
    procedure TestTheSecondSeriesTakesTheSecondSlotOfTheRamp;
    procedure TestAPieIsDrawnOffItsOwnCentreWithAColourPerSector;
    procedure TestTheBackingStripIsDrawnInTheThemesOwnColour;
    procedure TestATitleIsDrawnWhereTheOptionPutIt;
    procedure TestASeriesLabelIsDrawnAndTakesItsInkFromItsMark;
    procedure TestAPieLabelsItsSlicesAndPointsAtThem;
    procedure TestALegendNamesTheSeriesAlongTheBottom;
    procedure TestSingleModeGreysEveryItemButOneBeforeAnyClick;
    procedure TestEachLegendItemTakesItsOwnSeriesColourAndIconShape;
    procedure TestALineSeriesGetsARuleWithARingOnItRatherThanABlock;
    procedure TestASwitchedOffSeriesIsNotDrawnAndDoesNotSizeTheAxis;
    procedure TestASwitchedOffSliceLeavesThePieAndTheRestKeepTheirColours;
    procedure TestTheSeriesAboveAHiddenOneDropsOntoWhatIsLeft;
    procedure TestAPieOffersItsSliceNamesAndAnswersToItsOwn;
    procedure TestATableFeedsThreeSeriesAColumnEach;
    procedure TestASeriesReadingATableNamesItselfAfterItsColumn;
    procedure TestEncodeOverridesWhichColumnASeriesReads;
    procedure TestAPieReadingATableNamesItsSlicesFromAColumn;
    procedure TestACoordinateNobodyClaimedDrawsNothing;
    procedure TestASeriesCanReadTheTableTheOtherWayRound;
    procedure TestTwoBarSeriesStandSideBySideInsteadOfOnTopOfEachOther;
    procedure TestAStackedBarStandsOnTheOneBelowIt;
    procedure TestALayeredFrameDrawsTheSamePictureAsAWholeOne;
    procedure TestAKeptStaticLayerDoesNoWorkAndInvalidateDropsIt;
    procedure TestTheLayoutOwnsTheThinningDecision;
    procedure TestTheGridThinsWithTheLabels;
    procedure TestMinorTicksVanishWhenTheMajorsAreThinned;
    procedure TestResizingRelaysOutTheAxes;
    procedure TestAnAxisNameIsDrawnInTheSpaceReservedForIt;
    procedure TestAThickerThemeBorderDrawsAThickerAxis;
    procedure TestTheMinorTickLengthComesFromTheTheme;
    procedure TestHairlinesLandOnWholePixels;
    procedure TestRepeatedRendersDoNotGrowTheHeap;
  end;
implementation

procedure TChartProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TChartProbe.RenderLayered(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

function TChartProbe.TypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TAdvanceChartTest.SetUp;
begin
  inherited SetUp;
  { PARENTED, and that is not decoration. DrawFrame starts with TyFillParentBg
    and fills the corner gaps only when a parent background resolves -- an
    orphan control paints its rounded background and leaves everything outside
    it untouched. A test that renders an unparented control is testing a
    situation a .lfm cannot produce, and the sentinel ground below turns that
    difference into a failure instead of hiding it. }
  FForm := TForm.CreateNew(nil);

  { ITS OWN CONTROLLER, pinned to the built-in default in light mode.
    Reading the process-wide TyDefaultController made these tests depend on
    whatever the suite ran before them: the tick-mark assertion passed on its
    own and failed in the full run, because another suite had left a theme in
    which the axis tick resolves no border colour and nothing is drawn. Every
    assertion here is about pixels, so the theme is an INPUT and belongs to
    the test. }
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';

  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvanceChartTest.TearDown;
begin
  FreeAndNil(FBmp);
  FChart := nil;        { owned by the form }
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvanceChartTest.Draw(AW, AH, APPI: Integer);
begin
  FreeAndNil(FBmp);
  { SENTINEL, not white. Two things made a white ground useless: the light
    theme's surface IS pure white, and BGRABitmap runs an alpha correction over
    the WHOLE bitmap after any use of Canvas, forcing every alpha to 255. So on
    a white ground "the middle is opaque" and "the corner is opaque" were both
    true of a control that painted nothing at all -- a mutation that skipped
    DrawFrame entirely survived, which is how this was found. Magenta is a
    colour no theme in this library produces. }
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 0, 255, 255));
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, AW, AH), APPI);
end;

function TAdvanceChartTest.PixelAt(AX, AY: Integer): TBGRAPixel;
begin
  Result := FBmp.GetPixel(AX, AY);
end;

procedure TAdvanceChartTest.TestItHasItsOwnStyleKey;
begin
  { Its own, never borrowed. A control answering another control's key can
    never be reached by a theme that wants to restyle only this one. }
  AssertEquals('TyAdvChart', FChart.TypeKey);
end;

procedure TAdvanceChartTest.TestAnEmptyChartStillPaintsItsSurface;
var p: TBGRAPixel;
begin
  { No option at all. The control still owns its rectangle and still has to
    fill it: a windowed control that paints nothing shows whatever the
    widgetset erased with, which is not the theme's surface. }
  Draw;
  p := PixelAt(200, 150);
  AssertFalse('the middle still holds the sentinel -- nothing was painted here',
    (p.red = 255) and (p.green = 0) and (p.blue = 255));
end;

procedure TAdvanceChartTest.TestEveryCornerIsPainted;
var i: Integer; p: TBGRAPixel;
begin
  { All four corners, because a windowed control cannot cast a shadow onto its
    parent and the frame has to fill the corner gaps itself. A corner left
    unpainted is where the widgetset erase shows through -- invisible on a white
    test ground, which is why this suite draws onto a sentinel colour. }
  Draw;
  for i := 0 to 3 do
  begin
    case i of
      0: p := PixelAt(0, 0);
      1: p := PixelAt(399, 0);
      2: p := PixelAt(0, 299);
    else p := PixelAt(399, 299);
    end;
    AssertFalse(Format('corner %d still holds the sentinel -- the corner gap was '
      + 'never filled', [i]), (p.red = 255) and (p.green = 0) and (p.blue = 255));
  end;
end;

procedure TAdvanceChartTest.TestTheOptionDrivesTheBuild;
begin
  { The whole pipeline behind one string property. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] }] }';
  Draw;
  AssertTrue('a build happened', FChart.Build <> nil);
  AssertEquals('one grid', 1, FChart.Build.GridCount);
  AssertEquals('one x axis', 1, FChart.Build.AxisCount('xAxis'));
  AssertEquals('three categories', 3,
    FChart.Build.Axis('xAxis', 0).Categories.Count);
  AssertEquals('and the y axis took the data''s range', 3,
    FChart.Build.Axis('yAxis', 0).Scale.GetExtent.Stop, 0);
end;

procedure TAdvanceChartTest.TestABadOptionBlanksTheChart;
var
  x, y, ink: Integer;
  p, bg: TBGRAPixel;
begin
  { An option that does not parse leaves NO chart. Keeping the last good one
    made the control show a picture its own property no longer described, with
    nothing on screen to say so -- and at design time that reads as "my edit
    did nothing" rather than "I broke it". }
  FChart.Option := '{ xAxis: { data: [''A'', ''B''] }, yAxis: {} }';
  Draw;
  AssertEquals(2, FChart.Build.Axis('xAxis', 0).Categories.Count);

  FChart.Option := '{ xAxis: { data: [''A'',';
  Draw;
  AssertTrue('the error is readable', FChart.OptionError <> '');
  AssertEquals('no grid is left', 0, FChart.Build.GridCount);

  { And the surface still gets painted -- blank means an empty chart, not an
    unpainted control. }
  bg := PixelAt(200, 150);
  AssertFalse('the sentinel shows through', (bg.red = 255) and (bg.green = 0)
    and (bg.blue = 255));
  ink := 0;
  for y := 20 to 279 do
    for x := 20 to 379 do
    begin
      p := PixelAt(x, y);
      if (Abs(p.red - bg.red) + Abs(p.green - bg.green)
        + Abs(p.blue - bg.blue)) > 12 then Inc(ink);
    end;
  AssertEquals(Format('%d pixels of chart survived a rejected option', [ink]),
    0, ink);
end;

procedure TAdvanceChartTest.TestTheOptionReadsBackWhatWasWritten;
const
  cGood = '{ xAxis: { data: [''A'', ''B''] }, yAxis: {} }';
  cBad  = '{ xAxis: { data: [''A'', ''B''] }, yAxis: {';
begin
  { The property is the API, and a property that does not read back what was
    written is a property that eats the host's work. In the Object Inspector
    every keystroke that does not yet parse used to revert the whole box, and a
    .lfm could not round-trip an option still being written.

    The TREE is a separate question with the opposite answer: a rejected option
    leaves no tree at all, so the picture never disagrees with the property. }
  FChart.Option := cGood;
  Draw;
  AssertEquals('a good option reads back', cGood, FChart.Option);
  AssertEquals('and parsed', '', FChart.OptionError);
  AssertEquals('and built', 1, FChart.Build.GridCount);

  FChart.Option := cBad;
  Draw;
  AssertEquals('the REJECTED text reads back too', cBad, FChart.Option);
  AssertTrue('and the reason is readable', FChart.OptionError <> '');
  AssertEquals('while the chart itself is gone', 0, FChart.Build.GridCount);
end;

procedure TAdvanceChartTest.TestWritingTheSameTextTwiceIsANoOp;
const
  cBad = '{ yAxis: {';
begin
  { The early-out has to compare against what was WRITTEN. Comparing against
    the parsed tree's text meant a second write of the same bad text was not
    recognised as a repeat -- it re-parsed and re-invalidated on every
    keystroke that failed. }
  FChart.Option := cBad;
  AssertEquals(cBad, FChart.Option);
  FChart.Option := cBad;
  AssertEquals('still the same text', cBad, FChart.Option);
end;

procedure TAdvanceChartTest.TestDiagnosticsReachTheControl;
begin
  { A chart that silently drops what it cannot draw is a chart that lies. }
  FChart.Option := '{ xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''bard'', data: [1] }] }';
  Draw;
  AssertTrue('it said so', FChart.DiagnosticCount > 0);
  AssertTrue('and named the offender', Pos('bard', FChart.Diagnostic(0)) > 0);
end;

procedure TAdvanceChartTest.TestAnAxisIsActuallyDrawn;
var
  x, y, ink: Integer;
  p: TBGRAPixel;
  bg: TBGRAPixel;
begin
  { Not "a build happened" -- pixels. Count how many differ from the surface
    colour: an axis, its ticks and its split lines are hundreds of them, and a
    chart that built its model and drew nothing would pass every assertion
    above this one. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] }] }';
  Draw;
  bg := PixelAt(200, 150);
  ink := 0;
  for y := 0 to 299 do
    for x := 0 to 399 do
    begin
      p := PixelAt(x, y);
      if (Abs(p.red - bg.red) + Abs(p.green - bg.green) + Abs(p.blue - bg.blue)) > 12 then
        Inc(ink);
    end;
  AssertTrue(Format('only %d pixels differ from the surface -- nothing was drawn',
    [ink]), ink > 100);
end;

procedure TAdvanceChartTest.TestAValueAxisLabelsItsTicks;
var
  x, y, gutter, x0, yTop, yBot, runStart, i, k, best, want: Integer;
  rowHasInk: array of Boolean;
  centres: array of Integer;
  p, bg: TBGRAPixel;
  ax: TTyAxis;
  scaleTicks: TTyScaleTickArray;
begin
  { The count above is why this test exists. An axis' ticks and split lines are
    hundreds of pixels on their own, so "something was drawn" stays true when
    the axis draws no NUMBERS at all -- which is exactly what shipped, because
    PaintAxis labelled only ordinal scales and a value axis is not one. It took
    a render on a real machine to see it.

    So look in the GUTTER instead, the strip between the control's frame and the
    y axis, where nothing but a label can put ink.

    NOT from x=0: the control's own border and its rounded corners live there,
    and they are 926 pixels of ink against the 184 the labels contribute. A
    threshold on the total was met by the frame alone, and a mutation that
    labelled nothing at all survived. The window starts clear of the frame.

    And count BANDS of ink rows, not pixels: one per tick, each centred on its
    tick's coordinate. A pixel total cannot tell four labels from three, nor a
    label at the right height from one at the wrong one. }
  { NO SERIES, and an explicit range instead. The background reference below
    is sampled from the middle of the plot, which stopped being empty the day
    series marks started drawing -- it would come back as a bar's colour and
    every gutter pixel would then "differ from the background". An axis test
    measures the axis. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] },'
    + ' yAxis: { min: 0, max: 30 }, series: [] }';
  Draw;
  ax := FChart.Build.Axis('yAxis', 0);
  AssertTrue('the y axis is a value axis', not (ax.Scale is TTyOrdinalScale));
  scaleTicks := ax.Scale.GetTicks;
  { PxStart/PxStop on a VERTICAL axis are y values. Its horizontal position is the
    plot rect's left edge. }
  gutter := Trunc(FChart.Build.Grid(0).PlotRect.Left) - 8;
  AssertTrue('there is a gutter to label into', gutter > 4);

  x0 := gutter - 45;
  if x0 < 12 then x0 := 12;
  AssertTrue('the gutter window is empty', gutter > x0);

  { And bounded VERTICALLY by the plot, because a strip of the control this tall
    crosses the frame's own top and bottom edges: scanning y=0..299 found six
    bands for four ticks, and the two extras were the border rows at y=0 and
    y=298. }
  yTop := Round(FChart.Build.Grid(0).PlotRect.Top) - 6;
  yBot := Round(FChart.Build.Grid(0).PlotRect.Bottom) + 6;
  if yTop < 0 then yTop := 0;
  if yBot > 299 then yBot := 299;

  bg := PixelAt(200, 150);
  SetLength(rowHasInk, 300);
  for y := yTop to yBot do
  begin
    rowHasInk[y] := False;
    for x := x0 to gutter - 1 do
    begin
      p := PixelAt(x, y);
      if (Abs(p.red - bg.red) + Abs(p.green - bg.green) + Abs(p.blue - bg.blue)) > 12 then
      begin
        rowHasInk[y] := True;
        Break;
      end;
    end;
  end;

  centres := nil;
  y := yTop;
  while y <= yBot do
    if rowHasInk[y] then
    begin
      runStart := y;
      while (y <= yBot) and rowHasInk[y] do Inc(y);
      SetLength(centres, Length(centres) + 1);
      centres[High(centres)] := (runStart + y - 1) div 2;
    end
    else
      Inc(y);

  AssertEquals('one label per tick', Length(scaleTicks), Length(centres));

  for i := 0 to High(scaleTicks) do
  begin
    want := Round(ax.DataToCoord(scaleTicks[i].Value));
    best := MaxInt;
    for k := 0 to High(centres) do
      if Abs(centres[k] - want) < best then best := Abs(centres[k] - want);
    AssertTrue(Format('tick %s sits at y=%d but no label is centred within 4px '
      + 'of it', [FloatToStr(scaleTicks[i].Value), want]), best <= 4);
  end;
end;

procedure TAdvanceChartTest.TestSplitLinesDivideBandsRatherThanPointAtLabels;
var
  x, y, ink, left, right, band, i, want, got, best, d: Integer;
  p, bg: TBGRAPixel;
  cols: array of Integer;
  gb: TTyGridBuild;
begin
  { A split line divides the bands; a LABEL is what sits at the band's middle.
    The two differ by half a band on a category axis, which is the whole reason
    TickCoords takes an AAlignWithLabel flag -- and asking for label alignment
    here drew the grid half a band off while every "an axis was drawn" count
    stayed green. }
  { No series: this counts vertical ink across the middle of the plot, and a
    bar is vertical ink. }
  { SPLIT LINES ASKED FOR BY NAME. A category axis does not draw them by
    default -- that is upstream's behaviour and item 15's headline finding --
    so the vertical grid counted here exists because the option says so. The
    subject is still WHERE the lines land, not whether they appear. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' splitLine: { show: true } },'
    + ' yAxis: { min: 0, max: 10 }, series: [] }';
  Draw;
  gb := FChart.Build.Grid(0);
  left := Round(gb.PlotRect.Left);
  right := Round(gb.PlotRect.Right);
  band := (right - left) div 4;

  { Vertical ink, sampled on a row inside the plot and clear of the axis line.

    The reference pixel is a QUARTER band in, not half. Half a band IS where a
    regression puts its lines, so sampling there made the comparison read
    inside-out: every plot-background pixel then "differed from bg", the scan
    recorded a column every three pixels, and a line was always found near
    whatever the loop below asked for. The mutant survived a test written to
    catch it. A quarter band is on neither the boundary nor the centre. }
  y := Round((gb.PlotRect.Top + gb.PlotRect.Bottom) / 2);
  bg := PixelAt(left + band div 4, y);
  cols := nil;
  { ONE PIXEL WIDER THAN THE PLOT, both ends. Sub-pixel snapping moves a stroke
    by up to half a pixel so its outer edge lands on a whole one, which is what
    makes a hairline crisp instead of two half-lit columns; a band edge at 40.7
    inside a plot whose Left rounds to 41 therefore inks column 40. The line is
    drawn and it is where it belongs -- the window was measured to the
    UNSNAPPED geometry, and the three interior edges below, which already allow
    two pixels of slack, never noticed. }
  for x := left - 1 to right + 1 do
  begin
    p := PixelAt(x, y);
    if (Abs(p.red - bg.red) + Abs(p.green - bg.green) + Abs(p.blue - bg.blue)) > 12 then
    begin
      { one column per line, not per antialiased pixel }
      if (Length(cols) = 0) or (x - cols[High(cols)] > 2) then
      begin
        SetLength(cols, Length(cols) + 1);
        cols[High(cols)] := x;
      end;
    end;
  end;

  { EXACTLY one per band edge: four bands have five. Lines on the band CENTRES
    would be four of them PLUS the two axis lines, so the count alone separates
    the two layouts even before the positions are checked. }
  AssertEquals('one line per band edge, the two ends shared with the axes',
    5, Length(cols));

  { Every interior edge must have a line within a pixel or two of it. Band
    CENTRES sit half a band away, so a regression misses by ~%d px. }
  for i := 1 to 3 do
  begin
    want := left + i * band;
    best := MaxInt;
    for x := 0 to High(cols) do
    begin
      d := Abs(cols[x] - want);
      if d < best then begin best := d; got := cols[x]; end;
    end;
    AssertTrue(Format('band edge %d is at x=%d but the nearest line is at x=%d '
      + '(half a band is %d px)', [i, want, got, band div 2]), best <= 2);
  end;
end;

procedure TAdvanceChartTest.TestTheTicksThemselvesAreDrawn;
var
  x, y, left, tickZone, yTop, yBot, marks: Integer;
  rowHasInk: array of Boolean;
  p, bg: TBGRAPixel;
  gb: TTyGridBuild;
begin
  { The tick MARKS, which every other assertion here is blind to: they are a
    few pixels each, so the axis, the split lines and the labels satisfy every
    count in this file without them.

    Two pixels of clearance from the axis line, and BANDS rather than a pixel
    total. The first version measured from left-6 and asked for more than eight
    pixels of ink -- and the axis LINE's own antialiasing, spread down the whole
    height of the plot, supplied them. It passed with every tick mark removed. }
  { No series -- see TestAValueAxisLabelsItsTicks: the background reference
    comes from inside the plot.

    TICKS ASKED FOR BY NAME: a value axis' `axisTick.show` is `auto`, and
    against a banded category x that resolves to no. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] },'
    + ' yAxis: { min: 0, max: 30, axisTick: { show: true } },'
    + ' series: [] }';
  Draw;
  gb := FChart.Build.Grid(0);
  left := Round(gb.PlotRect.Left);
  tickZone := left - 5;          { tick length is 5 at 96 dpi }
  yTop := Round(gb.PlotRect.Top);
  yBot := Round(gb.PlotRect.Bottom);

  bg := PixelAt(200, 150);
  SetLength(rowHasInk, 300);
  for y := yTop to yBot do
  begin
    rowHasInk[y] := False;
    for x := tickZone to left - 3 do
    begin
      p := PixelAt(x, y);
      if (Abs(p.red - bg.red) + Abs(p.green - bg.green) + Abs(p.blue - bg.blue)) > 12 then
      begin
        rowHasInk[y] := True;
        Break;
      end;
    end;
  end;

  marks := 0;
  y := yTop;
  while y <= yBot do
    if rowHasInk[y] then
    begin
      Inc(marks);
      while (y <= yBot) and rowHasInk[y] do Inc(y);
    end
    else
      Inc(y);

  AssertEquals('one tick mark per tick, outside the axis line',
    Length(FChart.Build.Axis('yAxis', 0).Scale.GetTicks), marks);
end;

procedure TAdvanceChartTest.TestAHiddenAxisIsNotDrawn;
var
  x, y, inkShown, inkHidden: Integer;
  p, bg: TBGRAPixel;

  function PlotInk: Integer;
  var gb: TTyGridBuild; xx, yy: Integer;
  begin
    Result := 0;
    gb := FChart.Build.Grid(0);
    for yy := Round(gb.PlotRect.Top) to Round(gb.PlotRect.Bottom) do
      for xx := Round(gb.PlotRect.Left) to Round(gb.PlotRect.Right) do
      begin
        p := PixelAt(xx, yy);
        if (Abs(p.red - bg.red) + Abs(p.green - bg.green)
          + Abs(p.blue - bg.blue)) > 12 then Inc(Result);
      end;
  end;

begin
  { `show: false` switches an axis OFF. Before this, `show` was read in one
    place only -- into the layout spec, where it shrank the thickness reserved
    for labels -- and the axis was then drawn regardless, so the option looked
    like it did something (the plot got wider) while the lines stayed. }
  { NO SERIES, and here it changes what the test MEANS. "Both axes hidden and
    nothing is drawn inside the plot" was true when the control drew nothing
    but axes; with marks it is false and should be -- `show: false` on an axis
    hides the AXIS, and a series bound to a hidden axis still maps to pixels
    and still draws. Keeping the old assertion would have pinned a bug. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] },'
    + ' yAxis: { min: 0, max: 30 }, series: [] }';
  Draw;
  bg := PixelAt(200, 150);
  inkShown := PlotInk;
  AssertTrue('the visible chart drew something in the plot', inkShown > 50);

  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''], show: false },'
    + ' yAxis: { min: 0, max: 30, show: false }, series: [] }';
  Draw;
  bg := PixelAt(200, 150);
  inkHidden := PlotInk;
  AssertEquals(Format('both axes are hidden but %d pixels are still drawn '
    + 'inside the plot', [inkHidden]), 0, inkHidden);

  { AND A SERIES STILL DRAWS THROUGH A HIDDEN AXIS. `show: false` means "do not
    draw this axis", not "do not use it": the axis still exists, still carries
    its extent, and everything bound to it still maps to pixels. That is stated
    in PaintAxis' own comment and nothing tested it until series marks existed
    to test it with -- and the assertion above, left as it was, would have
    turned it into a bug. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''], show: false },'
    + ' yAxis: { min: 0, max: 30, show: false },'
    + ' series: [{ type: ''bar'', data: [10, 20, 30] }] }';
  Draw;
  bg := PixelAt(200, 4);
  AssertTrue('a series bound to hidden axes draws nothing at all',
    PlotInk > 50);
end;

procedure TAdvanceChartTest.TestTheAxisHonoursMinMaxAndInterval;
var
  sc: TTyScale;
  r: TTyRange;
begin
  { FixMin, FixMax and Interval have been on TTyIntervalScale since it was
    written and NOTHING ever set them, so four of the most-used axis options in
    ECharts did nothing at all. The data here would give 0..3; the option says
    otherwise and the option wins. }
  FChart.Option := '{ xAxis: { data: [''A''] },'
    + ' yAxis: { min: -10, max: 50 },'
    + ' series: [{ type: ''bar'', data: [3] }] }';
  Draw;
  sc := FChart.Build.Axis('yAxis', 0).Scale;
  r := sc.GetExtent;
  AssertEquals('min is pinned, not rounded away', -10.0, r.Start, 1e-9);
  AssertEquals('and so is max', 50.0, r.Stop, 1e-9);

  { An explicit interval is a statement about the STEP. }
  FChart.Option := '{ xAxis: { data: [''A''] },'
    + ' yAxis: { min: 0, max: 100, interval: 25 },'
    + ' series: [{ type: ''bar'', data: [3] }] }';
  Draw;
  AssertEquals('0, 25, 50, 75, 100', 5,
    Length(FChart.Build.Axis('yAxis', 0).Scale.GetTicks));

  { splitNumber asks for a tick COUNT rather than a step, and it is a hint --
    the nice-number rounding still owns the actual boundaries. }
  FChart.Option := '{ xAxis: { data: [''A''] },'
    + ' yAxis: { min: 0, max: 100, splitNumber: 2 },'
    + ' series: [{ type: ''bar'', data: [3] }] }';
  Draw;
  AssertTrue('far fewer ticks than the default five',
    Length(FChart.Build.Axis('yAxis', 0).Scale.GetTicks) <= 4);
end;

procedure TAdvanceChartTest.TestACrowdedAxisThinsItsLabels;
var
  x, y, ink, gutter, x0, yTop, yBot: Integer;
  p, bg: TBGRAPixel;

  function Bands: Integer;
  var yy, xx: Integer; run: Boolean;
  begin
    Result := 0;
    run := False;
    for yy := yTop to yBot do
    begin
      p := PixelAt(x0, yy);
      ink := 0;
      for xx := x0 to gutter - 1 do
      begin
        p := PixelAt(xx, yy);
        if (Abs(p.red - bg.red) + Abs(p.green - bg.green)
          + Abs(p.blue - bg.blue)) > 12 then begin ink := 1; Break; end;
      end;
      if (ink = 1) and not run then Inc(Result);
      run := ink = 1;
    end;
  end;

var
  fewTicks, manyTicks: Integer;
begin
  { The layout unit has been able to thin labels since item 12 landed, and
    nothing called it -- so every label was drawn, and a crowded axis simply
    overlapped. This is the assertion that says something calls it now.

    A value axis over 0..30 gets a handful of ticks; over 0..3000 in a 300px
    control it gets many more than fit. The number of labels DRAWN must not
    grow in step with the number of ticks. }
  { No series -- see TestAValueAxisLabelsItsTicks. }
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 30 },'
    + ' series: [] }';
  Draw;
  gutter := Trunc(FChart.Build.Grid(0).PlotRect.Left) - 8;
  x0 := gutter - 45;
  if x0 < 12 then x0 := 12;
  yTop := Round(FChart.Build.Grid(0).PlotRect.Top) - 6;
  yBot := Round(FChart.Build.Grid(0).PlotRect.Bottom) + 6;
  if yTop < 0 then yTop := 0;
  if yBot > 299 then yBot := 299;
  bg := PixelAt(200, 150);
  fewTicks := Bands;
  AssertTrue('a sparse axis drew some labels', fewTicks > 1);

  { Same control, same height, a scale that wants far more ticks. }
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 3000,'
    + ' interval: 20 }, series: [{ type: ''bar'', data: [3000] }] }';
  Draw;
  bg := PixelAt(200, 150);
  manyTicks := Bands;
  AssertTrue(Format('%d label bands for a scale asking for 150 ticks -- '
    + 'nothing is thinning them', [manyTicks]), manyTicks < 40);
end;

procedure TAdvanceChartTest.TestResizingRelaysOutTheAxes;
var wide, narrow: Double;
begin
  { The plot rect is measured from the labels, so a resize is a relayout and
    not merely a repaint. A cached pixel extent would leave the axis the width
    it had at construction. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] }] }';
  Draw(600, 300);
  wide := FChart.Build.Axis('xAxis', 0).PxStop
        - FChart.Build.Axis('xAxis', 0).PxStart;
  Draw(300, 300);
  narrow := FChart.Build.Axis('xAxis', 0).PxStop
          - FChart.Build.Axis('xAxis', 0).PxStart;
  AssertTrue(Format('the axis did not follow the resize (%.1f then %.1f)',
    [wide, narrow]), narrow < wide);

  { And a render into a DIFFERENT rect without any SetBounds. This is the case
    the rect comparison in RenderTo exists for, and it is the only one: a real
    resize sets the dirty flag through Resize, so a mutation that dropped the
    comparison survived the two draws above. }
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(600, 300, BGRA(255, 0, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 300), 96);
  AssertTrue('a render into a wider rect kept the narrow layout',
    FChart.Build.Axis('xAxis', 0).PxStop
      - FChart.Build.Axis('xAxis', 0).PxStart > narrow);
end;

procedure TAdvanceChartTest.TestRepeatedRendersDoNotGrowTheHeap;
var before, after: PtrUInt; i: Integer;
begin
  { Every render rebuilds axes, stores and coordinate systems. A leak here
    grows with every frame rather than showing up once. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: [{}, {}],'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] },'
    + ' { type: ''line'', yAxisIndex: 1, data: [10, 20, 30] }] }';
  for i := 0 to 4 do Draw(320, 240);
  before := GetFPCHeapStatus.CurrHeapUsed;
  for i := 0 to 29 do Draw(320, 240);
  after := GetFPCHeapStatus.CurrHeapUsed;
  AssertTrue(Format('heap grew from %d to %d over thirty renders', [before, after]),
    after <= before);
end;

{ ============ what the paint path was skipping ============ }

function TAdvanceChartTest.InkIn(AL, AT, AR, AB: Integer;
  const ABg: TBGRAPixel): Integer;
var x, y: Integer;
begin
  Result := 0;
  for y := AT to AB do
    for x := AL to AR do
      if InkDepth(PixelAt(x, y), ABg) > 0 then Inc(Result);
end;

{ 0 = background, 1 = partially lit, 2 = solidly inked. The distinction is the
  whole subject of the snapping test: an unsnapped hairline is TWO partial
  columns where a snapped one is a single solid column. }
function TAdvanceChartTest.InkDepth(const AP, ABg: TBGRAPixel): Integer;
var d: Integer;
begin
  d := Abs(AP.red - ABg.red) + Abs(AP.green - ABg.green)
     + Abs(AP.blue - ABg.blue);
  if d > 120 then Result := 2
  else if d > 12 then Result := 1
  else Result := 0;
end;

procedure TAdvanceChartTest.TestAnAxisNameIsDrawnInTheSpaceReservedForIt;

  { Red pixels anywhere below the plot. Nothing else on the canvas is red, so
    this counts the axis name and only the axis name.

    Comparing TOTAL ink for a named axis against an unnamed one was the first
    attempt and it was fake-green: naming an axis MOVES THE PLOT, because the
    layout reserves the name's space whether or not anything draws into it, so
    the two runs differed for a reason unrelated to the name. Mutating the
    drawing out left the test green, which is how this was found. }
  function RedBelowPlot(const AName: string): Integer;
  var
    gb: TTyGridBuild;
    x, y: Integer;
    p: TBGRAPixel;
  begin
    FChart.Option := '{ xAxis: { data: [''A'', ''B'']' + AName + ' },'
      + ' yAxis: {}, series: [{ type: ''bar'', data: [1, 2] }] }';
    Draw;
    gb := FChart.Build.Grid(0);
    Result := 0;
    for y := Round(gb.PlotRect.Bottom) + 1 to 299 do
      for x := 0 to 399 do
      begin
        p := PixelAt(x, y);
        if (p.red > p.green + 60) and (p.red > p.blue + 60) then Inc(Result);
      end;
  end;

var
  named, unnamed: Integer;
begin
  { THE SPACE WAS ALREADY BEING RESERVED. Builder solves the grid with obcAll,
    so TyAxisThickness charged every named axis for NameGap plus the name's
    turned extent -- and nothing drew into it. Setting `name` shrank the plot by
    the width of a string that was not on screen, and every other assertion in
    this file stayed green because they all sample INSIDE the plot. }
  FCtl.StyleOverride := 'TyAdvChartAxisName { color: #FF0000; }';
  unnamed := RedBelowPlot('');
  named := RedBelowPlot(', name: ''WWWWWWWW''');
  AssertEquals('nothing is red when the axis has no name', 0, unnamed);
  AssertTrue(Format('a named axis put %d red pixels below the plot -- the name '
    + 'is not being drawn', [named]), named > 30);
end;

procedure TAdvanceChartTest.TestAThickerThemeBorderDrawsAThickerAxis;

  { Rows of the axis line, counted at mid-plot. RED in both runs, so the count
    is of the domain line alone: an inked-pixel count over a band near the axis
    also counts the tick marks and the split lines, neither of which moves with
    this override -- which made the first version of this test report the same
    number twice and read as a fix that had not worked. }
  function RedRows(const AWidth: string): Integer;
  var
    gb: TTyGridBuild;
    i, x, y: Integer;
    p: TBGRAPixel;
  begin
    FCtl.StyleOverride := 'TyAdvChartAxisLine { border-color: #FF0000;'
      + ' border-width: ' + AWidth + '; }';
    Draw;
    gb := FChart.Build.Grid(0);
    x := Round((gb.PlotRect.Left + gb.PlotRect.Right) / 2);
    y := Round(gb.PlotRect.Bottom);
    Result := 0;
    for i := y - 10 to y + 10 do
    begin
      p := PixelAt(x, i);
      if p.red > p.green + 40 then Inc(Result);
    end;
  end;

var
  thin, thick: Integer;
begin
  { The stroke width was the literal 1 while six styles were resolved two lines
    above it, so every theme drew the same axis however it was skinned. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }';
  thin := RedRows('1px');
  thick := RedRows('6px');
  AssertTrue('the axis line is drawn at all', thin > 0);
  AssertTrue(Format('a 1 px axis covered %d rows and a 6 px axis %d -- the '
    + 'theme border-width is not reaching the stroke', [thin, thick]),
    thick > thin + 2);
end;

procedure TAdvanceChartTest.TestTheMinorTickLengthComesFromTheTheme;
var
  gb: TTyGridBuild;
  bg: TBGRAPixel;
  shortT, longT, y, l, r: Integer;
begin
  { --advchart-minor-tick-length, its constant and its default had all been in
    place since item 18 while the painter used tickLen/2, so a skin that set the
    metric changed nothing. }
  FChart.Option := '{ xAxis: { min: 0, max: 10, interval: 5,'
    + ' minorTick: { show: true, splitNumber: 5 } }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [1, 2] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  l := Round(gb.PlotRect.Left);
  r := Round(gb.PlotRect.Right);
  bg := PixelAt(l + 4, Round(gb.PlotRect.Top) + 4);
  y := Round(gb.PlotRect.Bottom);
  { The band BEYOND the default minor length: only a longer minor tick reaches
    it, and the major ticks stop short of it too. }
  shortT := InkIn(l, y + 6, r, y + 11, bg);

  FCtl.StyleOverride := ':root { --advchart-minor-tick-length: 11px; }';
  Draw;
  longT := InkIn(l, y + 6, r, y + 11, bg);

  AssertTrue(Format('minor ticks inked %d px at the default length and %d at '
    + '11 px -- the metric has no reader', [shortT, longT]), longT > shortT);
end;

procedure TAdvanceChartTest.TestHairlinesLandOnWholePixels;
var
  gb: TTyGridBuild;
  p: TBGRAPixel;
  x, y, span, ones, wides: Integer;
begin
  { A 1 px stroke centred on a whole coordinate straddles two pixel columns and
    each takes half the ink: two grey columns where there should be one solid
    line. Preventing that is what item 19 is, and the shipped painter drew every
    hairline unsnapped -- the only callers of tyControls.SubPixel were in
    AdvChart.Shape, which this paint path does not go through.

    MEASURED AS RUN LENGTHS, not as intensities. The first version of this test
    scored each column by how far it sat from the background, and the theme
    paints split lines at alpha 0.6, so a perfectly snapped line read as
    half-lit and the test could not have passed however well the code worked.
    Run length says the thing itself: snapped is one column, unsnapped is two.

    The colour is overridden opaque for the same reason -- the theme's own alpha
    has nothing to do with what is being asserted. }
  FCtl.StyleOverride := 'TyAdvChartSplitLine { border-color: #FF0000;'
    + ' border-width: 1px; }';
  { SHORT BARS AGAINST A FIXED MAXIMUM, sampled near the TOP of the plot. A
    split line spans the plot's whole height, so a row up there can only be
    split lines -- while the mid-plot row this first used ran straight through
    the series ink, which is drawn from the derived palette and is therefore
    whatever the accent happens to be. Alone that row was fine; in the full run
    it found one wide red band instead of four narrow ones. The SetUp comment in
    this file records the same trap for the tick-mark test. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' splitLine: { show: true } },'
    + ' yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [1, 1, 1, 1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  y := Round(gb.PlotRect.Top) + 6;

  ones := 0;
  wides := 0;
  span := 0;
  for x := Round(gb.PlotRect.Left) - 2 to Round(gb.PlotRect.Right) + 2 do
  begin
    p := PixelAt(x, y);
    if p.red > p.green + 40 then
      Inc(span)
    else
    begin
      if span = 1 then Inc(ones)
      else if span > 1 then Inc(wides);
      span := 0;
    end;
  end;
  if span = 1 then Inc(ones) else if span > 1 then Inc(wides);

  AssertTrue(Format('there are split lines to judge at all (%d one-column, '
    + '%d wider)', [ones, wides]), ones + wides > 2);
  AssertTrue(Format('%d one-column lines against %d that straddle two or more '
    + '-- snapping is not reaching the stroke', [ones, wides]), wides = 0);
end;

procedure TAdvanceChartTest.TestAnUnnaturalIntervalIsNotRoundedAway;
var
  sc: TTyScale;
  ticks: TTyScaleTickArray;
  i, majors: Integer;
begin
  { A STEP NICENUM DOES NOT LIKE. The two fixtures above use interval 25 and
    interval 20 -- 2.5x10 and 2x10 -- and NiceNum returns both unchanged, so
    their assertions held whether or not `interval` was honoured at all.

    30 over 0..120 is the smallest case that separates them: rounded, it
    becomes 50 and the axis carries three ticks instead of five. ECharts treats
    `interval` as an outright override of the step, and half of every plausible
    value (3, 15, 30, 40, 300) was being discarded with no diagnostic. }
  FChart.Option := '{ xAxis: { data: [''A''] },'
    + ' yAxis: { min: 0, max: 120, interval: 30 },'
    + ' series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  sc := FChart.Build.Grid(0).YAxis(0).Scale;
  AssertEquals('the step is the one the option asked for', 30.0,
    TTyIntervalScale(sc).Interval, 1e-9);

  ticks := sc.GetTicks;
  majors := 0;
  for i := 0 to High(ticks) do
    if ticks[i].Level = 0 then Inc(majors);
  AssertEquals('0, 30, 60, 90, 120', 5, majors);
end;

procedure TAdvanceChartTest.TestCategoriesCollectedFromSeriesDataReachTheAxis;
var
  ax: TTyAxis;
  ticks: TTyScaleTickArray;
  i, majors: Integer;
begin
  { NO xAxis.data. The names live in the series rows, which is the case ordinal
    interning exists for -- a fixed category list needs no collecting.

    The interning half was wired and the consuming half was not:
    SetExtentFromCategories ran during axis construction, when the list was
    still empty, and again only from SetCategories, which needs an xAxis.data.
    Nothing re-derived the extent after the rows landed, so the store interned
    three categories and the axis reported one -- a single band across the whole
    plot with every point on top of it. }
  FChart.Option := '{ xAxis: { type: ''category'' }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: ['
    + ' [''Mon'', 1], [''Tue'', 2], [''Wed'', 3] ] }] }';
  Draw;
  ax := FChart.Build.Grid(0).XAxis(0);

  AssertEquals('all three names became categories', 3,
    TTyOrdinalScale(ax.Scale).CategoryCount);
  AssertTrue('and the last one is on the axis, not off the end',
    ax.Scale.Contain(2));

  { The band is the visible consequence: one category over the whole plot is
    what the bug looked like, and a count alone would not have caught a band
    still derived from the old extent. }
  AssertTrue(Format('a band is a third of the plot, not all of it (%.1f of '
    + '%.1f)', [ax.BandWidth, FChart.Build.Grid(0).PlotRect.Right
    - FChart.Build.Grid(0).PlotRect.Left]),
    ax.BandWidth < (FChart.Build.Grid(0).PlotRect.Right
                  - FChart.Build.Grid(0).PlotRect.Left) / 2);

  ticks := ax.Scale.GetTicks;
  majors := 0;
  for i := 0 to High(ticks) do
    if ticks[i].Level = 0 then Inc(majors);
  AssertEquals('one tick per collected category', 3, majors);
end;

procedure TAdvanceChartTest.TestAnAxisWithNoDataStillObeysItsOptions;
var
  sc: TTyScale;
  e: TTyRange;
begin
  { The extent pass returned as soon as no series produced a data extent -- and
    every option read came AFTER that return. So min, max, scale, splitNumber,
    interval and minorTick were all ignored on exactly the axis with nothing
    else to derive its range from: an empty chart, or one whose only series has
    no rows yet. Both are ordinary states in a designer. }
  FChart.Option := '{ xAxis: { data: [''A''] },'
    + ' yAxis: { min: -50, max: 150 },'
    + ' series: [{ type: ''bar'', data: [] }] }';
  Draw;
  sc := FChart.Build.Grid(0).YAxis(0).Scale;
  e := sc.GetExtent;
  AssertEquals('min is honoured with no data at all', -50.0, e.Start, 1e-9);
  AssertEquals('and so is max', 150.0, e.Stop, 1e-9);
end;

procedure TAdvanceChartTest.TestMinorTicksDoNotGetLabels;
var
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;
begin
  { GetTicks returns majors and minors in ONE array with Level saying which is
    which, and phase C formatted and positioned every entry. Turning on
    minorTick therefore multiplied the label count by the minor split, and the
    layout was asked to fit five times as many strings as the axis has numbers
    -- which is also how a crowded axis gets thinned for the wrong reason. }
  FChart.Option := '{ xAxis: { data: [''A''] },'
    + ' yAxis: { min: 0, max: 100, interval: 50,'
    + ' minorTick: { show: true, splitNumber: 5 } },'
    + ' series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.YAxis(0));
  AssertTrue('the axis has a layout spec', spec <> nil);
  AssertEquals('0, 50, 100 -- three labels, not eleven', 3,
    Length(spec^.Labels));
  AssertEquals('and a position for each', 3, Length(spec^.Positions));
end;

procedure TAdvanceChartTest.TestMinIntervalKeepsACountingAxisWhole;
var
  sc: TTyScale;
  ticks: TTyScaleTickArray;
  i: Integer;
begin
  { AN AXIS THAT COUNTS THINGS. Data of 0..1 nices to a step of 0.2 and labels
    0, 0.2, 0.4 -- fractions of an order, a person, an error. `minInterval: 1`
    is how ECharts says the axis counts, and the scale had no property for it:
    its only mention anywhere was a comment saying it does not apply to an
    ORDINAL scale, which is true and about something else. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { minInterval: 1 },'
    + ' series: [{ type: ''bar'', data: [0, 1] }] }';
  Draw;
  sc := FChart.Build.Grid(0).YAxis(0).Scale;
  AssertTrue('the step is at least one', TTyIntervalScale(sc).Interval >= 1.0);

  ticks := sc.GetTicks;
  for i := 0 to High(ticks) do
    if ticks[i].Level = 0 then
      AssertEquals(Format('tick %d (%.4f) is a whole number',
        [i, ticks[i].Value]), Round(ticks[i].Value), ticks[i].Value, 1e-9);
end;

procedure TAdvanceChartTest.TestMaxIntervalCapsTheStep;
var
  sc: TTyScale;
begin
  { The other end of the same pair: a wide range would otherwise nice to a step
    so large the axis carries two or three numbers. }
  FChart.Option := '{ xAxis: { data: [''A''] },'
    + ' yAxis: { min: 0, max: 1000, maxInterval: 100 },'
    + ' series: [{ type: ''bar'', data: [500] }] }';
  Draw;
  sc := FChart.Build.Grid(0).YAxis(0).Scale;
  AssertTrue(Format('the step is capped at 100, got %.2f',
    [TTyIntervalScale(sc).Interval]),
    TTyIntervalScale(sc).Interval <= 100.0 + 1e-9);
end;

procedure TAdvanceChartTest.TestAValueAxisBoundaryGapPadsTheExtent;
var
  bare, padded: TTyRange;
begin
  { A VALUE AXIS' boundaryGap IS A PAIR, not the boolean a category axis takes.
    The builder read the boolean form, acknowledged the pair in a comment, and
    nothing implemented it -- so the option was accepted and ignored.

    Compared against the same chart without it: pinning absolute numbers would
    pin whatever the niceing happens to do rather than the padding. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [10, 20] }] }';
  Draw;
  bare := FChart.Build.Grid(0).YAxis(0).Scale.GetExtent;

  FChart.Option := '{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { boundaryGap: [''50%'', ''50%''] },'
    + ' series: [{ type: ''line'', data: [10, 20] }] }';
  Draw;
  padded := FChart.Build.Grid(0).YAxis(0).Scale.GetExtent;

  AssertTrue(Format('the padded axis spans more than the bare one '
    + '(%.1f..%.1f against %.1f..%.1f)',
    [padded.Start, padded.Stop, bare.Start, bare.Stop]),
    (padded.Stop - padded.Start) > (bare.Stop - bare.Start));
  AssertTrue('and it reaches further up', padded.Stop > bare.Stop);

  { A malformed entry pads nothing rather than pushing the axis to infinity. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { boundaryGap: [''nonsense'', true] },'
    + ' series: [{ type: ''line'', data: [10, 20] }] }';
  Draw;
  padded := FChart.Build.Grid(0).YAxis(0).Scale.GetExtent;
  AssertFalse('nothing became NaN', IsNan(padded.Start) or IsNan(padded.Stop));
  AssertEquals('and the extent is the unpadded one', bare.Start,
    padded.Start, 1e-9);

  { A BARE NUMERIC STRING IS REFUSED, and that is the case that says the '%'
    check is doing something: '50' could mean fifty units or fifty per cent,
    ECharts documents neither, and choosing one would pad by a number the
    author never asked for. A number belongs in the option as a number. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { boundaryGap: [''50'', ''50''] },'
    + ' series: [{ type: ''line'', data: [10, 20] }] }';
  Draw;
  padded := FChart.Build.Grid(0).YAxis(0).Scale.GetExtent;
  AssertEquals('a bare numeric string pads nothing', bare.Start,
    padded.Start, 1e-9);
  AssertEquals('at either end', bare.Stop, padded.Stop, 1e-9);
end;

procedure TAdvanceChartTest.TestALongLabelBreaksToTheWidthItWasGiven;
var
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;
  i, wrapped: Integer;
begin
  { axisLabel.width + overflow:'break'. Every piece of this existed and none of
    it was reachable: TyWrapTextCJK, TyEllipsisPrefix, and DrawText's own
    AEllipsis and AMultiLine. The chart passed AEllipsis := False, never set
    AMultiLine, and had nowhere to say how wide a label may be.

    THE BROKEN TEXT IS IN THE SPEC, which is the point: the layout measures the
    same string the paint draws, so the gutter it reserves is the gutter the
    text needs. }
  FChart.Option := '{ xAxis: { data: [''a very long category label indeed''],'
    + ' axisLabel: { width: 40, overflow: ''break'' } },'
    + ' yAxis: {}, series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  AssertTrue('the axis has a spec', spec <> nil);
  AssertTrue('the width reached the spec', spec^.LabelWidthLogical > 0);

  wrapped := 0;
  for i := 0 to High(spec^.Labels) do
    if Pos(#10, spec^.Labels[i]) > 0 then Inc(wrapped);
  AssertTrue('the long label was broken into lines', wrapped > 0);

  { AND WITHOUT THE OPTION IT IS NOT -- so the assertion above is about the
    option and not about something the chart does anyway. }
  FChart.Option := '{ xAxis: { data: [''a very long category label indeed''] },'
    + ' yAxis: {}, series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  wrapped := 0;
  for i := 0 to High(spec^.Labels) do
    if Pos(#10, spec^.Labels[i]) > 0 then Inc(wrapped);
  AssertEquals('no width, no wrapping', 0, wrapped);
end;

procedure TAdvanceChartTest.TestCJKBreaksBetweenCharactersNotOnSpaces;
var
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;
  i, wrapped: Integer;
begin
  { CHINESE HAS NO SPACES, so a space-based wrapper treats a whole run as one
    unbreakable word and overflows instead of wrapping -- the trap this repo has
    a memory for (cjk-wordwrap-space-only-trap). Wrapping goes through the
    measurer precisely so it reaches TyWrapTextCJK, which breaks between
    ideographs; a wrapper written in the pure layer could not.

    A pure-CJK label is the case that separates the two: with a space-based
    wrapper this comes back as one line however narrow the width. }
  FChart.Option := '{ xAxis: { data: [''这是一个很长的中文标签需要折行''],'
    + ' axisLabel: { width: 40, overflow: ''break'' } },'
    + ' yAxis: {}, series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  wrapped := 0;
  for i := 0 to High(spec^.Labels) do
    if Pos(#10, spec^.Labels[i]) > 0 then Inc(wrapped);
  AssertTrue('a Chinese label wraps even with no space in it', wrapped > 0);

  { AND NOT MID-CHARACTER. Every line has to still be valid UTF-8 -- a break
    inside a three-byte character draws a replacement glyph in a real GUI and
    is invisible to a headless pixel count. }
  for i := 0 to High(spec^.Labels) do
    AssertEquals('the label survived as valid UTF-8',
      Length(spec^.Labels[i]),
      Length(UTF8Copy(spec^.Labels[i], 1, UTF8Length(spec^.Labels[i]))));
end;

procedure TAdvanceChartTest.TestTruncateEllipsisesInsteadOfOverflowing;
var
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;
  narrow, wide: Double;
begin
  { overflow:'truncate' does NOT rewrite the label -- the painter's own
    ellipsis fitter cuts it to the box, and it cuts by CHARACTER
    (TyEllipsisPrefix), not by byte. What the option has to do is make the box
    narrower than the text; without a bound the box is exactly the text's size
    and the fitter has nothing to bite on, so `overflow` would silently do
    nothing.

    Asserted through the reserved gutter, which is what a too-wide label
    actually costs: a truncating axis must not reserve the full width. }
  FChart.Option := '{ xAxis: { data: [''an extremely long category label''] },'
    + ' yAxis: {}, series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  wide := gb.PlotRect.Bottom;

  FChart.Option := '{ xAxis: { data: [''an extremely long category label''],'
    + ' axisLabel: { width: 30, overflow: ''truncate'' } },'
    + ' yAxis: {}, series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  narrow := gb.PlotRect.Bottom;

  AssertTrue('the overflow mode reached the spec',
    spec^.LabelOverflow = loTruncate);
  AssertTrue('the label text itself is left whole for the fitter to cut',
    Pos(#10, spec^.Labels[0]) = 0);
  AssertTrue(Format('a truncating axis leaves the plot at least as tall '
    + '(%.1f against %.1f)', [narrow, wide]), narrow >= wide);
end;

procedure TAdvanceChartTest.TestTheLayoutOwnsTheThinningDecision;
var
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;
begin
  { THE STEP AND THE PLACEMENTS ARE LAYOUT RESULTS, and the paint pass used to
    work them out for itself on every frame. Both come from measuring EVERY
    label, so a 5,000-category axis spent ten thousand measurements per frame
    choosing the twenty it would draw -- twelve seconds a frame, and thinning
    the split lines did not move it at all because that was never the cost.

    TTyGridBuild's own comment already gave the rule for the spec: kept "so the
    renderer draws from it rather than assembling a second one". These are the
    spec one level down.

    Asserted on the BUILD, not on a stopwatch: what makes the frame cheap is
    that the answer is already there when paint starts. }
  FChart.Option := '{ xAxis: { data: [''a'', ''b'', ''c'', ''d''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2, 3, 4] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  AssertTrue('the axis has a spec', spec <> nil);
  AssertTrue('the layout recorded a step', spec^.LabelStep >= 1);
  AssertEquals('four labels fit easily, so nothing is thinned', 1,
    spec^.LabelStep);
  AssertEquals('and it placed every label it kept', 4,
    Length(spec^.Placements));

  { A crowded axis: the step rises, and the placements say which survive. }
  FChart.Option := '{ xAxis: { data: [' + ManyCategories(120) + '] },'
    + ' yAxis: {}, series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  AssertTrue(Format('120 labels in 400 px must thin (step %d)',
    [spec^.LabelStep]), spec^.LabelStep > 1);
  AssertTrue('the placements were still computed by the layout',
    Length(spec^.Placements) > 0);
end;

procedure TAdvanceChartTest.TestTheGridThinsWithTheLabels;
var
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;
  bg: TBGRAPixel;
  x, y, span, lines: Integer;
begin
  { THE LINES BEHIND THE NUMBERS. The ticks have followed the labels since item
    12 -- "drawing every tick under a thinned set of labels reads as an axis
    that lost its labels rather than one that spaced them out" -- and the split
    lines did not, so a crowded axis wore a grid of 120 divisions under a dozen
    numbers.

    Counted as runs of red, with the split line colour overridden opaque so the
    count is of split lines and nothing else. }
  FCtl.StyleOverride := 'TyAdvChartSplitLine { border-color: #FF0000;'
    + ' border-width: 1px; }';
  FChart.Option := '{ xAxis: { data: [' + ManyCategories(120) + '],'
    + ' splitLine: { show: true } },'
    + ' yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [1] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  AssertTrue('the fixture really is crowded', spec^.LabelStep > 1);

  { Near the top of the plot, where a short bar cannot reach. }
  y := Round(gb.PlotRect.Top) + 6;
  bg := PixelAt(Round(gb.PlotRect.Left) + 3, y);
  lines := 0;
  span := 0;
  for x := Round(gb.PlotRect.Left) - 2 to Round(gb.PlotRect.Right) + 2 do
  begin
    if PixelAt(x, y).red > PixelAt(x, y).green + 40 then
      Inc(span)
    else
    begin
      if span > 0 then Inc(lines);
      span := 0;
    end;
  end;
  if span > 0 then Inc(lines);

  AssertTrue('there is a grid at all', lines > 1);
  AssertTrue(Format('120 categories drew %d split lines under a step of %d -- '
    + 'the grid is not thinning with the labels', [lines, spec^.LabelStep]),
    lines < 120 div 2);
end;

{ ACount quoted category names, for the crowded-axis fixtures. }
function TAdvanceChartTest.ManyCategories(ACount: Integer): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to ACount - 1 do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + '''c' + IntToStr(i) + '''';
  end;
end;

procedure TAdvanceChartTest.TestMinorTicksVanishWhenTheMajorsAreThinned;

  { Red runs in the band BELOW the major ticks, where only a minor tick reaches.
    The minor-tick key alone is overridden, so the count is of minor ticks. }
  function MinorRuns(const AOption: string): Integer;
  var
    gb: TTyGridBuild;
    x, y, span: Integer;
    p: TBGRAPixel;
  begin
    FCtl.StyleOverride := 'TyAdvChartMinorTick { border-color: #FF0000;'
      + ' border-width: 1px; }'
      + ' :root { --advchart-minor-tick-length: 10px; }';
    FChart.Option := AOption;
    Draw;
    gb := FChart.Build.Grid(0);
    y := Round(gb.PlotRect.Bottom) + 7;
    Result := 0;
    span := 0;
    for x := Round(gb.PlotRect.Left) - 2 to Round(gb.PlotRect.Right) + 2 do
    begin
      p := PixelAt(x, y);
      if p.red > p.green + 40 then
        Inc(span)
      else
      begin
        if span > 0 then Inc(Result);
        span := 0;
      end;
    end;
    if span > 0 then Inc(Result);
  end;

var
  roomy, crowded: Integer;
  gb: TTyGridBuild;
begin
  { A MINOR TICK SUBDIVIDES THE INTERVAL BETWEEN TWO MAJORS. Once the majors
    are being hidden, subdivisions of an interval nobody can see are noise --
    and they are the densest thing on the axis, so they are the worst noise to
    keep. This is also why a crowded axis used to cost what it did: the majors
    thinned to a handful and the minors stayed at four per hidden interval. }
  roomy := MinorRuns('{ xAxis: { min: 0, max: 40, interval: 10,'
    + ' minorTick: { show: true, splitNumber: 4 } }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [1] }] }');
  AssertTrue(Format('an uncrowded axis shows its minor ticks (%d runs)',
    [roomy]), roomy > 2);

  crowded := MinorRuns('{ xAxis: { min: 0, max: 4000, interval: 10,'
    + ' minorTick: { show: true, splitNumber: 4 } }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [1] }] }');
  gb := FChart.Build.Grid(0);
  AssertTrue('the crowded fixture really thins',
    gb.SpecFor(gb.XAxis(0))^.LabelStep > 1);
  AssertEquals('and then it draws no minor ticks at all', 0, crowded);
end;

procedure TAdvanceChartTest.TestALayeredFrameDrawsTheSamePictureAsAWholeOne;
var
  whole, layered: TBGRABitmap;
  x, y, differing: Integer;
  a, b: TBGRAPixel;
begin
  { THE LAYERED PATH MUST BE INVISIBLE. It renders the static half into a cache
    and blits it; if that changed a single pixel, every chart on screen would
    differ from every chart exported, and the export path is what the goldens
    and the example screenshots go through.

    Compared against RenderTo rather than against stored numbers, so the
    assertion stays true when the drawing changes. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''], name: ''X'' },'
    + ' yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [10, 40, 70] }] }';

  whole := TBGRABitmap.Create(400, 300, BGRA(255, 0, 255, 255));
  layered := TBGRABitmap.Create(400, 300, BGRA(255, 0, 255, 255));
  try
    FChart.SetBounds(0, 0, 400, 300);
    FChart.Render(whole.Canvas, Rect(0, 0, 400, 300), 96);
    FChart.RenderLayered(layered.Canvas, Rect(0, 0, 400, 300), 96);

    differing := 0;
    for y := 0 to 299 do
      for x := 0 to 399 do
      begin
        a := whole.GetPixel(x, y);
        b := layered.GetPixel(x, y);
        if (a.red <> b.red) or (a.green <> b.green) or (a.blue <> b.blue) then
          Inc(differing);
      end;
    AssertEquals('a layered frame differs from a whole one', 0, differing);

    { AND AGAIN FROM THE CACHE, which is the path a second frame takes -- the
      first call rendered into the cache, this one only blits it. }
    layered.Fill(BGRA(255, 0, 255, 255));
    FChart.RenderLayered(layered.Canvas, Rect(0, 0, 400, 300), 96);
    differing := 0;
    for y := 0 to 299 do
      for x := 0 to 399 do
      begin
        a := whole.GetPixel(x, y);
        b := layered.GetPixel(x, y);
        if (a.red <> b.red) or (a.green <> b.green) or (a.blue <> b.blue) then
          Inc(differing);
      end;
    AssertEquals('a blitted frame differs from a drawn one', 0, differing);

    { THE SAME SIZE AT A DIFFERENT PPI IS A DIFFERENT PICTURE, and
      TTyPaintCache cannot see it: NeedsRender compares width and height and
      nothing else. A per-monitor DPI move hands back exactly this -- the same
      client size, a new PPI -- so without the chart keying on PPI itself, a
      chart drawn for 96 would be blitted onto a 144 window at 96's text and
      tick sizes.

      Compared against the 96 picture rather than against numbers: what must be
      true is that it CHANGED, not what it changed to. }
    layered.Fill(BGRA(255, 0, 255, 255));
    FChart.RenderLayered(layered.Canvas, Rect(0, 0, 400, 300), 144);
    differing := 0;
    for y := 0 to 299 do
      for x := 0 to 399 do
      begin
        a := whole.GetPixel(x, y);
        b := layered.GetPixel(x, y);
        if (a.red <> b.red) or (a.green <> b.green) or (a.blue <> b.blue) then
          Inc(differing);
      end;
    AssertTrue('the same size at 144 PPI was served from the 96 cache',
      differing > 200);
  finally
    layered.Free;
    whole.Free;
  end;
end;

procedure TAdvanceChartTest.TestAKeptStaticLayerDoesNoWorkAndInvalidateDropsIt;

  { Every text measurement the memo saw, hits and misses together. A frame that
    re-renders the static layer measures labels; a frame that blits it measures
    nothing, so this number standing still IS the cache working. }
  function Measurements: Int64;
  var h, m: Int64; e: Integer;
  begin
    TyTextMeasureCacheStats(h, m, e);
    Result := h + m;
  end;

var
  bmp: TBGRABitmap;
  before: Int64;

  procedure Frame;
  begin
    FChart.RenderLayered(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  end;

begin
  { THE CONTRACT BETWEEN THE TWO INVALIDATES, which is the whole point of the
    layer: Invalidate means "the model may have moved" and must redraw the
    static half, because a theme change arrives as a bare Invalidate and there
    is no hook to tell the two apart. InvalidateFrame means "same model, one
    frame on" and must not.

    Asserted through the measurement counters rather than a stopwatch: a
    timing test on CI is a coin toss, and what actually makes the frame cheap
    is that no label gets measured. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] }] }';
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 0, 255, 255));
  try
    FChart.SetBounds(0, 0, 400, 300);
    Frame;                       { renders the static layer }

    before := Measurements;
    Frame;
    AssertEquals('a second frame measures nothing at all', before,
      Measurements);

    FChart.InvalidateFrame;
    Frame;
    AssertEquals('and neither does one after InvalidateFrame', before,
      Measurements);

    { INVALIDATE DROPS IT. The static layer is re-rendered, which means the
      labels are measured again -- from the memo, so they are hits, but they
      are counted. }
    FChart.Invalidate;
    Frame;
    AssertTrue('Invalidate re-renders the static layer',
      Measurements > before);
  finally
    bmp.Free;
  end;
end;

procedure TAdvanceChartTest.TestTheSeriesIsActuallyDrawnInTheThemesColour;
var
  gb: TTyGridBuild;
  tall, short_, plain: Integer;
begin
  { THE CONTROL DREW NO DATA AT ALL until this. Its own diagnostics said so --
    "Series marks are not painted yet" -- and the paint list built for item 14
    had no consumer outside tests, which the Tier 0 re-audit recorded.

    Measured as ink in the TOP HALF of the plot, where only a tall bar reaches:
    a total over the whole plot would be met by the grid lines alone, which is
    the shape of fake-green this file has been caught by before. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }';

  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [95] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  tall := RedIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Top),
                Round(gb.PlotRect.Right), Round(gb.PlotRect.Top) +
                Round((gb.PlotRect.Bottom - gb.PlotRect.Top) / 3));
  AssertTrue(Format('a bar of 95 out of 100 reaches the top third (%d px)',
    [tall]), tall > 100);

  { AND A SHORT ONE DOES NOT, which is what says the height is the VALUE and
    not just "a bar was drawn somewhere". }
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [5] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  short_ := RedIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Top),
                  Round(gb.PlotRect.Right), Round(gb.PlotRect.Top) +
                  Round((gb.PlotRect.Bottom - gb.PlotRect.Top) / 3));
  AssertEquals('a bar of 5 does not', 0, short_);

  { THE COLOUR COMES FROM THE THEME, not from the renderer. Without the
    override the palette is derived from --accent, so the bar is there and it
    is NOT red -- which is what says the red above was the theme's doing. }
  FCtl.StyleOverride := '';
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [95] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  plain := RedIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Top),
                 Round(gb.PlotRect.Right), Round(gb.PlotRect.Top) +
                 Round((gb.PlotRect.Bottom - gb.PlotRect.Top) / 3));
  AssertEquals('the default palette is not red', 0, plain);
  AssertTrue('but the bar is still drawn', tall > 100);
end;

{ Pixels in a rectangle that are strongly red. Used where the fixture has
  overridden a series colour to red, so the count is of that series and of
  nothing else on the canvas. }
procedure TAdvanceChartTest.TestAPieLabelsItsSlicesAndPointsAtThem;
var
  outside_, none_: Integer;
begin
  { A PIE IS LABELLED BY ITS OWN PASS, not by the one that labels bars -- and
    the two reach the canvas by different routes, so a bar test cannot stand in
    for this one. `label.show` defaults TRUE on a pie, which is the other half
    of the difference: a pie that says nothing about labels still gets them.

    Counted OUTSIDE the disc, where only an outer label and its leader can be:
    the pie is centred with a radius of a quarter of the shorter side, so the
    top strip of the chart is bare but for the labels. }
  FCtl.StyleOverride := 'TyAdvChartLabel { color: #FF0000; }';
  FChart.Option := '{ series: [{ type: ''pie'', radius: ''30%'', data: ['
    + ' { value: 1, name: ''Alpha'' }, { value: 1, name: ''Beta'' } ] }] }';
  Draw(400, 300);
  outside_ := RedIn(0, 0, 399, 299);
  AssertTrue(Format('the slices are labelled (%d px)', [outside_]),
    outside_ > 20);

  { AND SWITCHED OFF IT DRAWS NONE, which is what says the option is read
    rather than labels being drawn unconditionally. }
  FChart.Option := '{ series: [{ type: ''pie'', radius: ''30%'','
    + ' label: { show: false }, data: ['
    + ' { value: 1, name: ''Alpha'' }, { value: 1, name: ''Beta'' } ] }] }';
  Draw(400, 300);
  none_ := RedIn(0, 0, 399, 299);
  AssertEquals('none at all', 0, none_);
end;

procedure TAdvanceChartTest.TestASeriesLabelIsDrawnAndTakesItsInkFromItsMark;
var
  gb: TTyGridBuild;
  l, t, r, b, inside_, outside_, unlabelled, neither, one, both: Integer;
begin
  { LABELS ARE OFF UNLESS ASKED, so the same chart drawn twice -- once with a
    label block and once without -- is the cleanest thing to count. Anything
    that appears only in the first render is the label.

    The ink is a THEME KEY, and overriding it red is what proves the label is
    not drawn in the series colour by accident: the bar itself is overridden
    green, so red pixels can only be glyphs. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #00FF00; }'
    + ' TyAdvChartLabelOnLight { color: #FF0000; }'
    + ' TyAdvChartLabelOnMid { color: #FF0000; }'
    + ' TyAdvChartLabelOnDark { color: #FF0000; }';

  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [80] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  l := Round(gb.PlotRect.Left);
  t := Round(gb.PlotRect.Top);
  r := Round(gb.PlotRect.Right);
  b := Round(gb.PlotRect.Bottom);
  unlabelled := RedIn(l, t, r, b);
  AssertEquals('no label block, no glyphs', 0, unlabelled);

  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', label: { show: true }, data: [80] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  inside_ := RedIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Top),
                   Round(gb.PlotRect.Right), Round(gb.PlotRect.Bottom));
  AssertTrue(Format('the label is drawn (%d px)', [inside_]), inside_ > 10);

  { AND WHERE THE OPTION PUT IT -- which also changes WHICH THEME KEY it takes.
    `inside` reads the three contrast bands; `bottom` is outside the mark and
    reads TyAdvChartLabel instead, because an outside label is never derived
    from the thing it names. The override above deliberately covers only the
    inside keys, so this next render finds no red until the outside key is
    overridden too -- which is the assertion. }
  AssertEquals('the inside keys do not reach an outside label', 0,
    RedIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Bottom) - 20,
          Round(gb.PlotRect.Right), Round(gb.PlotRect.Bottom) + 30));
  FCtl.StyleOverride := FCtl.StyleOverride
    + ' TyAdvChartLabel { color: #FF0000; }';
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', label: { show: true, position: ''bottom'' },'
    + ' data: [80] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  b := Round(gb.PlotRect.Bottom);
  outside_ := RedIn(Round(gb.PlotRect.Left), b + 1,
                    Round(gb.PlotRect.Right), b + 30);
  { COUNTED AS `THERE, AND NOT IN THE MIDDLE` rather than as a pixel count.
    Two digits at the theme's own size are a dozen pixels over the red
    threshold and the exact number is the font's business, not this test's.
    What the test is for is WHERE they went: below the bar's foot, and no
    longer across its middle where `inside` had put them. }
  AssertTrue(Format('`bottom` puts it under the bar (%d px)', [outside_]),
    outside_ > 0);
  AssertEquals('and no longer inside it', 0,
    RedIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Top),
          Round(gb.PlotRect.Right), b - 10));

  { EACH SERIES KEEPS ITS OWN SPEC, and only two series can say so: with one,
    an index bug that filed every spec under slot zero would read back the same
    answer either way.

    Counted as a ladder -- neither labelled, one labelled, both labelled -- so
    the middle case has to land strictly between the other two. A version that
    shared one spec across the chart would draw the middle case as one of the
    ends. }
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [80] },'
    + ' { type: ''bar'', data: [60] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  l := Round(gb.PlotRect.Left);
  t := Round(gb.PlotRect.Top);
  r := Round(gb.PlotRect.Right);
  b := Round(gb.PlotRect.Bottom);
  neither := RedIn(l, t, r, b);

  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [80] },'
    + ' { type: ''bar'', label: { show: true }, data: [60] }] }';
  Draw;
  one := RedIn(l, t, r, b);

  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', label: { show: true }, data: [80] },'
    + ' { type: ''bar'', label: { show: true }, data: [60] }] }';
  Draw;
  both := RedIn(l, t, r, b);

  AssertEquals('neither series labelled', 0, neither);
  AssertTrue(Format('one of them is (%d px)', [one]), one > 0);
  AssertTrue(Format('and two is more than one (%d vs %d)', [both, one]),
    both > one);

  { A FORMATTER CHANGES THE WORDS, which is the only way to tell that the
    template ran at all -- the default text for a bar is the value, and a
    formatter of {c} would draw exactly the same pixels. A longer string draws
    more of them. }
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', label: { show: true,'
    + ' formatter: ''{c} kilograms'' }, data: [80] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  AssertTrue('a longer label is more ink',
    RedIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Top),
          Round(gb.PlotRect.Right), Round(gb.PlotRect.Bottom)) > inside_);
end;

procedure TAdvanceChartTest.TestATitleIsDrawnWhereTheOptionPutIt;
var
  centre, leftSide, top_, bottom_, titleOnly: Integer;
begin
  { A title floats over the container and reserves nothing, so the only thing
    that can say it was drawn is ink where nothing else paints. The chart here
    has no series and no axes: everything counted below is the title.

    THE COLOUR IS A THEME KEY, and the override is what proves it -- upstream
    hard-codes 18px bold in its primary colour, and a port that did the same
    would put a black title on a dark skin. }
  FCtl.StyleOverride := 'TyAdvChartTitle { color: #FF0000; }';
  FChart.Option := '{ title: { text: ''Referer'' } }';
  Draw(400, 300);
  top_ := RedIn(0, 0, 399, 60);
  bottom_ := RedIn(0, 200, 399, 299);
  AssertTrue(Format('the title is near the top (%d px)', [top_]), top_ > 20);
  AssertEquals('and nowhere else', 0, bottom_);

  { CENTRED BY DEFAULT, which is the one placement rule a reader would notice
    immediately if it were wrong. }
  centre := RedIn(150, 0, 250, 60);
  leftSide := RedIn(0, 0, 100, 60);
  AssertTrue(Format('centred (%d px)', [centre]), centre > 20);
  AssertEquals('not against the left edge', 0, leftSide);

  { AND left MOVES IT, so the option is read rather than the default drawn
    twice. }
  FChart.Option := '{ title: { text: ''Referer'', left: 0 } }';
  Draw(400, 300);
  AssertTrue(Format('now against the left edge (%d px)',
    [RedIn(0, 0, 100, 60)]), RedIn(0, 0, 100, 60) > 20);

  { A SUBTITLE IS A SECOND LINE, in its own theme key. }
  FCtl.StyleOverride := 'TyAdvChartTitle { color: #FF0000; }'
    + ' TyAdvChartSubtitle { color: #00FF00; }';
  FChart.Option := '{ title: { text: ''Referer'' } }';
  Draw(400, 300);
  titleOnly := RedIn(0, 0, 399, 120);
  FChart.Option := '{ title: { text: ''Referer'', subtext: ''Fake Data'' } }';
  Draw(400, 300);
  AssertTrue(Format('the subtitle is drawn too (%d px)',
    [GreenIn(0, 0, 399, 120)]), GreenIn(0, 0, 399, 120) > 20);
  AssertTrue('and below the title', GreenIn(0, 0, 399, 25) = 0);

  { IN ITS OWN KEY, which is the point of there being two: a subtitle drawn
    from the title's style would come out red.

    COUNTED AS `THE RED DID NOT GROW` rather than as `no red below line 30`,
    which is what this asserted first. The title's own descenders reach
    somewhere around there, and exactly where depends on the font the process
    ended up with -- so that version passed alone and failed in the full run,
    which is this repo's oldest-shaped false alarm. The title sits in the same
    place in both renders below, so its red is the same number in both. }
  AssertEquals('the second line added no red', titleOnly,
    RedIn(0, 0, 399, 120));

  { SWITCHED OFF DRAWS NOTHING. }
  FChart.Option := '{ title: { text: ''Referer'', show: false } }';
  Draw(400, 300);
  AssertEquals('nothing at all', 0, RedIn(0, 0, 399, 299));
end;

procedure TAdvanceChartTest.TestTheBackingStripIsDrawnInTheThemesOwnColour;
var
  gb: TTyGridBuild;
  high_, low_: Integer;
begin
  { showBackground reaches the canvas, and its colour comes from a THEME KEY
    rather than from upstream's hard-coded rgba(180,180,180,0.2). A pale grey
    band is wrong on a dark skin, and this library's rule is that a visual
    value a theme cannot reach is a bug.

    Measured in the TOP of the plot, where a bar of 5 out of 100 cannot reach
    -- so green there is the strip and nothing else. }
  FCtl.StyleOverride := 'TyAdvChartBarBackground { background: #00FF00; }';
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', showBackground: true, data: [5] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  high_ := GreenIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Top),
                   Round(gb.PlotRect.Right),
                   Round(gb.PlotRect.Top) +
                   Round((gb.PlotRect.Bottom - gb.PlotRect.Top) / 4));
  AssertTrue(Format('the strip reaches the top of the plot (%d px)', [high_]),
    high_ > 100);

  { AND NOT WHEN NOBODY ASKED, which is what says the strip is the option's
    doing and not something every bar chart now carries. }
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [5] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  low_ := GreenIn(Round(gb.PlotRect.Left), Round(gb.PlotRect.Top),
                  Round(gb.PlotRect.Right),
                  Round(gb.PlotRect.Top) +
                  Round((gb.PlotRect.Bottom - gb.PlotRect.Top) / 4));
  AssertEquals('no strip without the option', 0, low_);
end;

procedure TAdvanceChartTest.TestAPieIsDrawnOffItsOwnCentreWithAColourPerSector;
var
  left, right, corner, total: Integer;
begin
  { THE FIRST SERIES THAT IS NOT ON A COORDINATE SYSTEM, and the whole reason
    this test is at the CONTROL rather than in the pie unit: the layout and the
    sectors were both green in isolation while the control still skipped the
    series entirely -- it filled no store for a series with no axes, and its
    mark builder returns at the first line for one with no cartesian. Nothing
    below is about arithmetic; it is about whether any of it runs. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ series: [{ type: ''pie'', data: [1, 1] }] }';
  Draw(400, 300);

  { Default start is twelve o''clock running clockwise, so the first datum takes
    the RIGHT half and the second the left. A pie that came out in one colour
    would fail here and nowhere else -- colorBy is ''data'' for this type alone. }
  right := RedIn(210, 60, 290, 240);
  left := GreenIn(110, 60, 190, 240);
  AssertTrue(Format('the first sector fills the right half (%d px)', [right]),
    right > 3000);
  AssertTrue(Format('the second takes the left (%d px)', [left]), left > 3000);
  AssertEquals('and neither is on the wrong side', 0, GreenIn(210, 60, 290, 240));
  AssertEquals('either way', 0, RedIn(110, 60, 190, 240));

  { A DISC, not a rectangle: the corners of the control are untouched. }
  corner := RedIn(0, 0, 60, 60) + GreenIn(0, 0, 60, 60);
  AssertEquals('nothing in the corner', 0, corner);

  { AND IT IS THE RIGHT SIZE. radius defaults to [0, ''50%''] of HALF the shorter
    side -- 75 px on a 300-tall control -- so the disc reaches y = 75 and no
    further. The ''75%'' this library''s own option catalog still carries would
    put it at 112.5 and paint this strip solid. }
  total := RedIn(190, 20, 210, 60) + GreenIn(190, 20, 210, 60);
  AssertEquals('the disc stops where a 50% radius stops', 0, total);
  total := RedIn(190, 90, 210, 130) + GreenIn(190, 90, 210, 130);
  AssertTrue(Format('but it does reach inside that (%d px)', [total]),
    total > 200);

  { ONE DATUM IS THE CASE THAT VANISHES IF A WHOLE TURN IS TREATED AS NO TURN.
    Its sector sweeps exactly 2*Pi, and an arc primitive that normalises the
    sweep before drawing would answer with an empty path -- a pie of one slice
    is a disc, and the failure looks like the series was never drawn. }
  FChart.Option := '{ series: [{ type: ''pie'', data: [1] }] }';
  Draw(400, 300);
  AssertTrue('a single datum is a whole disc, left',
    RedIn(130, 140, 170, 160) > 200);
  AssertTrue('and right', RedIn(230, 140, 270, 160) > 200);
end;

procedure TAdvanceChartTest.TestTheSecondSeriesTakesTheSecondSlotOfTheRamp;
var
  gb: TTyGridBuild;
  red, green: Integer;
  l, t, r, b: Integer;
begin
  { THE RAMP HAS EIGHT SLOTS AND THEY ARE MEANT TO BE USED. A version that
    resolved TyAdvChartSeries1 for every series passed every test there was --
    a one-series chart cannot tell the difference, and one-series charts were
    all this file had. Two series in two colours is the smallest case that can.

    Both are given the whole plot to themselves by putting them on different
    categories, so each colour has somewhere to be. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100 }, series: ['
    + '{ type: ''bar'', data: [95, 0] }, { type: ''bar'', data: [0, 95] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  l := Round(gb.PlotRect.Left);
  t := Round(gb.PlotRect.Top);
  r := Round(gb.PlotRect.Right);
  b := t + Round((gb.PlotRect.Bottom - gb.PlotRect.Top) / 3);
  red := RedIn(l, t, r, b);
  green := GreenIn(l, t, r, b);
  AssertTrue(Format('the first series is drawn in slot 1 (%d px)', [red]),
    red > 100);
  AssertTrue(Format('and the second in slot 2, not slot 1 again (%d px)',
    [green]), green > 100);
end;

procedure TAdvanceChartTest.TestALegendNamesTheSeriesAlongTheBottom;
var
  bottom_, top_: Integer;
begin
  { A legend floats over the container and reserves nothing, exactly like the
    title -- so the thing that says it was drawn is ink where nothing else
    paints. The WORDS carry a theme key of their own, and overriding it is
    what proves the key is consulted rather than a colour written into the
    control. }
  FCtl.StyleOverride := 'TyAdvChartLegend { color: #FF0000; }';
  FChart.Option := '{ legend: {}, series: [{ type: ''bar'', '
    + 'name: ''Alpha'', data: [5] }] }';
  Draw(400, 300);
  bottom_ := RedIn(0, 250, 399, 299);
  top_ := RedIn(0, 0, 399, 120);
  AssertTrue(Format('the legend is along the bottom (%d px)', [bottom_]),
    bottom_ > 10);
  AssertEquals('and nowhere near the top', 0, top_);

  { AND `top` MOVES IT, so the option is read rather than the default drawn
    twice. }
  FChart.Option := '{ legend: { top: 0 }, series: [{ type: ''bar'', '
    + 'name: ''Alpha'', data: [5] }] }';
  Draw(400, 300);
  top_ := RedIn(0, 0, 399, 60);
  AssertTrue(Format('now at the top (%d px)', [top_]), top_ > 10);
  AssertEquals('and no longer at the bottom', 0, RedIn(0, 250, 399, 299));

  { THE WORDS TAKE THE LEGEND'S OWN FONT KEY. Overriding the SIZE is what
    proves it: every other text key in this theme is the same size, so a
    colour override alone cannot tell which key was read. }
  FCtl.StyleOverride := 'TyAdvChartLegend { color: #FF0000; font-size: 20px; }';
  FChart.Option := '{ legend: { top: 0 }, series: [{ type: ''bar'', '
    + 'name: ''Alpha'', data: [5] }] }';
  Draw(400, 300);
  AssertTrue(Format('bigger words make more ink (%d px)',
    [RedIn(0, 0, 399, 60)]), RedIn(0, 0, 399, 60) > top_);

  { A SERIES WITH NO NAME OFFERS NOTHING, so the legend has nothing to list
    and draws nothing at all. }
  FChart.Option := '{ legend: {}, series: [{ type: ''bar'', data: [5] }] }';
  Draw(400, 300);
  AssertEquals('an unnamed series puts no words in the legend', 0,
    RedIn(0, 0, 399, 299));
end;

procedure TAdvanceChartTest.TestSingleModeGreysEveryItemButOneBeforeAnyClick;
var
  live, dead: Integer;
begin
  { `selectedMode: 'single'` is resolved AT LOAD -- upstream forces exactly
    one item on before anything is drawn, so this is a first-frame difference
    and not an interaction one. Four corpus examples depend on it.

    TWO SERIES AND TWO COLOURS, because a chart where every item ends up the
    same colour cannot tell `one of them is greyed` from `all of them are`. }
  FCtl.StyleOverride := 'TyAdvChartLegend { color: #FF0000; }'
    + ' TyAdvChartLegendInactive { color: #00FF00; }';
  FChart.Option := '{ legend: {}, series: ['
    + '{ type: ''bar'', name: ''Alpha'', data: [5] },'
    + '{ type: ''bar'', name: ''Beta'', data: [3] }] }';
  Draw(400, 300);
  live := RedIn(0, 250, 399, 299);
  AssertTrue(Format('both names are drawn live (%d px)', [live]), live > 20);
  AssertEquals('and none of them greyed', 0, GreenIn(0, 250, 399, 299));

  FChart.Option := '{ legend: { selectedMode: ''single'' }, series: ['
    + '{ type: ''bar'', name: ''Alpha'', data: [5] },'
    + '{ type: ''bar'', name: ''Beta'', data: [3] }] }';
  Draw(400, 300);
  dead := GreenIn(0, 250, 399, 299);
  AssertTrue(Format('one of the two is now greyed (%d px)', [dead]),
    dead > 10);
  AssertTrue(Format('and the other is still live (%d px)',
    [RedIn(0, 250, 399, 299)]), RedIn(0, 250, 399, 299) > 10);
  AssertTrue('with less live ink than before',
    RedIn(0, 250, 399, 299) < live);

  { `selected` says the same thing without the mode, and names WHICH one. }
  FChart.Option := '{ legend: { selected: { Alpha: false } }, series: ['
    + '{ type: ''bar'', name: ''Alpha'', data: [5] },'
    + '{ type: ''bar'', name: ''Beta'', data: [3] }] }';
  Draw(400, 300);
  AssertTrue(Format('the named item is greyed (%d px)',
    [GreenIn(0, 250, 399, 299)]), GreenIn(0, 250, 399, 299) > 10);
end;

procedure TAdvanceChartTest.TestEachLegendItemTakesItsOwnSeriesColourAndIconShape;
var
  widest, y, span, x: Integer;
  p: TBGRAPixel;
begin
  { TWO SERIES, TWO OVERRIDDEN RAMP SLOTS, and the probe restricted to the
    legend band -- the grid's own bottom edge is 80 px up from it, so nothing
    but the legend paints down here. A legend that matched every name against
    the FIRST series would put slot one's colour on both icons. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ legend: {}, series: ['
    + '{ type: ''bar'', name: ''Alpha'', data: [5] },'
    + '{ type: ''bar'', name: ''Beta'', data: [3] }] }';
  Draw(400, 300);
  AssertTrue(Format('the first item is the first slot (%d px)',
    [RedIn(0, 250, 399, 299)]), RedIn(0, 250, 399, 299) > 10);
  AssertTrue(Format('the second is the second (%d px)',
    [GreenIn(0, 250, 399, 299)]), GreenIn(0, 250, 399, 299) > 10);

  { AND THE SHAPE IS A ROUNDED RECTANGLE, filled: a bar publishes no symbol, so
    the chain lands on roundRect and the icon is a solid 25-wide block. The
    WIDEST UNBROKEN RUN is what tells that from a ring or a circle -- a 14 px
    tall ring can never manage more than 14 across. }
  widest := 0;
  for y := 250 to 299 do
  begin
    span := 0;
    for x := 0 to 399 do
    begin
      p := PixelAt(x, y);
      if (p.red > 180) and (p.green < 80) and (p.blue < 80) then
      begin
        Inc(span);
        if span > widest then widest := span;
      end
      else
        span := 0;
    end;
  end;
  AssertTrue(Format('a solid block, not a marker (%d px across)', [widest]),
    widest >= 20);
end;

procedure TAdvanceChartTest.TestALineSeriesGetsARuleWithARingOnItRatherThanABlock;
var
  x0, x1, y0, y1, runs: Integer;
  wasRed, isRed: Boolean;

  { REDDER THAN ITS SURROUNDINGS, not saturated red. A line icon's box starts
    on a half-pixel -- the marker's pen overhangs its own geometry, so the
    block's top edge is fractional -- and every edge of it is anti-aliased. A
    `red > 180, green < 80` probe reads a half-covered red pixel as background
    and would find most of the icon missing. }
  function Red(AX, AY: Integer): Boolean;
  var q: TBGRAPixel;
  begin
    q := PixelAt(AX, AY);
    Result := (q.red > q.green + 40) and (q.red > q.blue + 40);
  end;

  { The ink's bounding box in the legend band, and the number of separate
    vertical runs down the middle of it. }
  { FPC will not let a nested routine drive a for-loop with the enclosing
    one's variable, so the counters are local here. }
  procedure Measure;
  var xx, yy: Integer;
  begin
    x0 := 9999; x1 := -1; y0 := 9999; y1 := -1;
    for yy := 250 to 299 do
      for xx := 0 to 399 do
        if Red(xx, yy) then
        begin
          if xx < x0 then x0 := xx;
          if xx > x1 then x1 := xx;
          if yy < y0 then y0 := yy;
          if yy > y1 then y1 := yy;
        end;
    runs := 0;
    wasRed := False;
    for yy := y0 to y1 do
    begin
      isRed := Red((x0 + x1) div 2, yy);
      if isRed and not wasRed then Inc(runs);
      wasRed := isRed;
    end;
  end;

begin
  { A LINE SERIES DRAWS ITS OWN LEGEND ICON and nothing else does: a rule
    across the whole item box with a RING sitting on it, four fifths of the
    box's height. Two things can go wrong and they look different:

      - forget that a line draws its own, and the icon collapses to a single
        `emptyCircle` in the 25 x 14 box -- a ring of radius 7 and no rule,
        so the ink is 14 wide instead of 26;
      - forget which icon the series publishes, and the marker loses its
        `empty` and comes out a solid dot, so the middle of the icon fills in.

    THE RULE IS BROKEN IN THE MIDDLE, and that is not a defect: the ring is
    drawn over it and an `empty` symbol is FILLED with the chart's own ground,
    so the rule survives as two stubs either side. Upstream draws it the same
    way, for the same reason. Measuring the widest unbroken run would therefore
    find six pixels where the rule is twenty-five wide -- the ink's BOUNDING
    BOX is what answers `is there a rule', and the number of separate runs down
    its middle is what answers `is the marker a ring'. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }';
  FChart.Option := '{ legend: {}, xAxis: { type: ''category'', '
    + 'data: [''a'', ''b''] }, yAxis: {}, series: [{ type: ''line'', '
    + 'name: ''Alpha'', data: [5, 3] }] }';
  Draw(400, 300);
  Measure;
  AssertTrue(Format('the rule spans the item box (%d px wide)', [x1 - x0 + 1]),
    x1 - x0 + 1 >= 24);
  AssertTrue(Format('and the marker on it is a RING (%d runs down the middle)',
    [runs]), runs >= 2);

  { A BAR IS THE OTHER HALF OF THE SAME RULE: no symbol at all, so no rule and
    no ring -- one solid rounded block, as wide as the item box and solid all
    the way down its middle. }
  FChart.Option := '{ legend: {}, series: [{ type: ''bar'', '
    + 'name: ''Alpha'', data: [5] }] }';
  Draw(400, 300);
  Measure;
  AssertTrue(Format('a bar icon is as wide as the box too (%d px)',
    [x1 - x0 + 1]), x1 - x0 + 1 >= 24);
  AssertEquals('but solid through and through', 1, runs);
end;

procedure TAdvanceChartTest.TestASwitchedOffSeriesIsNotDrawnAndDoesNotSizeTheAxis;
var
  redAlone, redBoth, greenBoth: Integer;
begin
  { TWO SERIES A HUNDRED TIMES APART. With both drawn the axis is sized by the
    big one and the small one is a sliver; switch the big one off and the axis
    re-scales to what is left, so the SAME data draws a full-height bar.

    That second half is the point. A legend that only stopped drawing the
    series would leave the axis at 500 and the survivor at a sliver -- which
    is what a reader would call `it did not work`. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ legend: {}, xAxis: { type: ''category'', '
    + 'data: [''a'', ''b''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', name: ''Small'', data: [5, 5] },'
    + '{ type: ''bar'', name: ''Large'', data: [500, 500] }] }';
  Draw(400, 300);
  redBoth := RedIn(0, 0, 399, 219);
  greenBoth := GreenIn(0, 0, 399, 219);
  AssertTrue(Format('both are drawn (%d red, %d green)',
    [redBoth, greenBoth]), (redBoth > 0) and (greenBoth > 0));

  FChart.Option := '{ legend: { selected: { Large: false } }, '
    + 'xAxis: { type: ''category'', data: [''a'', ''b''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', name: ''Small'', data: [5, 5] },'
    + '{ type: ''bar'', name: ''Large'', data: [500, 500] }] }';
  Draw(400, 300);
  AssertEquals('the switched-off series is gone from the plot', 0,
    GreenIn(0, 0, 399, 219));
  redAlone := RedIn(0, 0, 399, 219);
  AssertTrue(Format('and the axis re-scaled around the survivor '
    + '(%d px, was %d)', [redAlone, redBoth]), redAlone > redBoth * 4);
end;

procedure TAdvanceChartTest.TestASwitchedOffSliceLeavesThePieAndTheRestKeepTheirColours;
var
  blueBefore: Integer;
begin
  { A PIE'S LEGEND NAMES SLICES, so the filter is per ROW and not per series.
    Three equal slices in three overridden ramp slots; switch the middle one
    off and it must leave the circle -- and the third must STAY BLUE.

    That last clause is the whole reason this commit touched PieVisual. The
    fills used to be keyed on the sector's POSITION, so dropping a slice slid
    every later one down a colour: the third slice would come back GREEN,
    wearing the colour of the slice that had just been switched off. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }'
    + ' TyAdvChartSeries3 { background: #0000FF; }';
  FChart.Option := '{ legend: {}, series: [{ type: ''pie'', label: '
    + '{ show: false }, data: ['
    + '{ name: ''A'', value: 1 }, { name: ''B'', value: 1 },'
    + '{ name: ''C'', value: 1 }] }] }';
  Draw(400, 300);
  blueBefore := BlueIn(0, 0, 399, 245);
  AssertTrue(Format('three slices, three colours (%d, %d, %d)',
    [RedIn(0, 0, 399, 245), GreenIn(0, 0, 399, 245), blueBefore]),
    (RedIn(0, 0, 399, 245) > 100) and (GreenIn(0, 0, 399, 245) > 100)
    and (blueBefore > 100));

  FChart.Option := '{ legend: { selected: { B: false } }, series: '
    + '[{ type: ''pie'', label: { show: false }, data: ['
    + '{ name: ''A'', value: 1 }, { name: ''B'', value: 1 },'
    + '{ name: ''C'', value: 1 }] }] }';
  Draw(400, 300);
  AssertEquals('the switched-off slice left the circle', 0,
    GreenIn(0, 0, 399, 245));
  AssertTrue(Format('the third slice is still blue (%d px)',
    [BlueIn(0, 0, 399, 245)]), BlueIn(0, 0, 399, 245) > blueBefore);
  AssertTrue('and the first still red', RedIn(0, 0, 399, 245) > 100);
end;

procedure TAdvanceChartTest.TestTheSeriesAboveAHiddenOneDropsOntoWhatIsLeft;
begin
  { THE STACK IS THE ONE THING THE INDEX CANNOT DO FOR US. The axis extents
    and the bar widths both take their populations from the axis-to-series
    index, so leaving a hidden series out of THAT covers them both -- but the
    stack solver never sees the index, and a hidden member left in the group
    would go on holding the one above it up in the air.

    Two bars of five in one stack. With both drawn the upper one occupies the
    TOP half of the plot and the lower half is the other colour; switch the
    lower one off and the upper one must come all the way down to the
    baseline, which puts its colour where it has never been. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ legend: {}, xAxis: { type: ''category'', '
    + 'data: [''a''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', name: ''Bottom'', stack: ''s'', data: [5] },'
    + '{ type: ''bar'', name: ''Top'', stack: ''s'', data: [5] }] }';
  Draw(400, 300);
  AssertTrue(Format('the upper series is in the top half (%d px)',
    [GreenIn(0, 70, 399, 135)]), GreenIn(0, 70, 399, 135) > 100);
  AssertEquals('and nowhere near the baseline', 0,
    GreenIn(0, 160, 399, 215));

  FChart.Option := '{ legend: { selected: { Bottom: false } }, '
    + 'xAxis: { type: ''category'', data: [''a''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', name: ''Bottom'', stack: ''s'', data: [5] },'
    + '{ type: ''bar'', name: ''Top'', stack: ''s'', data: [5] }] }';
  Draw(400, 300);
  AssertEquals('the hidden one is gone', 0, RedIn(0, 70, 399, 215));
  AssertTrue(Format('and the one above it came down to the baseline (%d px)',
    [GreenIn(0, 160, 399, 215)]), GreenIn(0, 160, 399, 215) > 100);
end;

procedure TAdvanceChartTest.TestAPieOffersItsSliceNamesAndAnswersToItsOwn;
var
  x0, x1: Integer;

  { Local counters: FPC will not let a nested routine drive a for-loop with
    the enclosing one's variable. }
  function Wide: Integer;
  var q: TBGRAPixel; xx, yy: Integer;
  begin
    x0 := 9999; x1 := -1;
    for yy := 250 to 299 do
      for xx := 0 to 399 do
      begin
        q := PixelAt(xx, yy);
        if (q.red > 180) and (q.green < 80) and (q.blue < 80) then
        begin
          if xx < x0 then x0 := xx;
          if xx > x1 then x1 := xx;
        end;
      end;
    if x1 < x0 then Result := 0 else Result := x1 - x0 + 1;
  end;

begin
  { A PIE'S LEGEND NAMES ITS SLICES AND NOT THE SERIES, so a pie with two
    slices makes a legend with two items -- and the pie's own name, however
    long, must not turn up as a third. Twenty characters long on purpose: an
    extra item carrying it would roughly triple the block's width, which no
    amount of font variation can explain away. }
  FCtl.StyleOverride := 'TyAdvChartLegend { color: #FF0000; }';
  FChart.Option := '{ legend: {}, series: [{ type: ''pie'', '
    + 'name: ''ZZZZZZZZZZZZZZZZZZZZ'', label: { show: false }, data: ['
    + '{ name: ''A'', value: 1 }, { name: ''B'', value: 1 }] }] }';
  Draw(400, 300);
  { Two one-character items measure about fifty across; a third carrying
    that twenty-character name measures about two hundred. The bound sits
    between them with room for any font either side. }
  AssertTrue(Format('two items and no third (%d px across)', [Wide]),
    (Wide > 20) and (Wide < 120));

  { BUT IT STILL ANSWERS TO ITS OWN NAME. Upstream pushes every raw series'
    name into the AVAILABLE list unconditionally, before it ever asks a
    provider for data names -- so an author who writes the pie's own name into
    `legend.data` gets a live item. Without that push the item would grey out
    for a reason that has nothing to do with the option: the chart would be
    claiming it cannot produce a name that is written on one of its series. }
  FCtl.StyleOverride := 'TyAdvChartLegend { color: #FF0000; }'
    + ' TyAdvChartLegendInactive { color: #00FF00; }';
  FChart.Option := '{ legend: { data: [''Zzz''] }, series: [{ type: ''pie'', '
    + 'name: ''Zzz'', label: { show: false }, data: ['
    + '{ name: ''A'', value: 1 }, { name: ''B'', value: 1 }] }] }';
  Draw(400, 300);
  AssertTrue(Format('the item is live (%d px)', [RedIn(0, 250, 399, 299)]),
    RedIn(0, 250, 399, 299) > 5);
  AssertEquals('and not greyed', 0, GreenIn(0, 250, 399, 299));
end;

procedure TAdvanceChartTest.TestATableFeedsThreeSeriesAColumnEach;
var
  redTop, greenTop: Integer;
begin
  { THE CANONICAL DATASET, and the reason the feature exists: one table, two
    bar series, NO `data` and NO `encode` anywhere. The category column is
    shared and the value columns are handed out one per series by a counter
    that advances -- so the second series must read column 2 and not column 1.

    THE TWO COLUMNS RUN OPPOSITE WAYS ON PURPOSE: 10/20 against 90/80. A
    series that read the wrong column would still draw two bars of plausible
    height, and only the ORDER tells them apart. So the probe asks which
    colour is the tall one. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ "dataset": { "source": ['
    + '["product","2015","2016"],'
    + '["a", 10, 90],'
    + '["b", 20, 80]] },'
    + '"xAxis": { "type": "category" }, "yAxis": {},'
    + '"series": [{"type":"bar"},{"type":"bar"}] }';
  Draw(400, 300);
  AssertTrue(Format('both series drew (%d red, %d green)',
    [RedIn(0, 0, 399, 219), GreenIn(0, 0, 399, 219)]),
    (RedIn(0, 0, 399, 219) > 100) and (GreenIn(0, 0, 399, 219) > 100));

  { The top sixth of the plot is reached only by a bar near the axis maximum,
    which on a 10..90 table is the SECOND column's bar. }
  redTop := RedIn(0, 70, 399, 100);
  greenTop := GreenIn(0, 70, 399, 100);
  AssertEquals('the first series took the low column', 0, redTop);
  AssertTrue(Format('and the second took the high one (%d px)', [greenTop]),
    greenTop > 20);
end;

procedure TAdvanceChartTest.TestASeriesReadingATableNamesItselfAfterItsColumn;
var
  withNames, without: Integer;
begin
  { A SERIES THAT NAMED ITSELF NOTHING TAKES THE NAME OF ITS COLUMN, and that
    is the whole reason `legend: {}` works on a dataset chart: the legend has
    entries to list only because the series have names to give it.

    Measured as ink in the legend band against the same chart with no legend:
    a chart whose series are all nameless has nothing to draw there. }
  FCtl.StyleOverride := 'TyAdvChartLegend { color: #FF0000; }';
  FChart.Option := '{ "dataset": { "source": ['
    + '["product","2015","2016"],'
    + '["a", 10, 90],'
    + '["b", 20, 80]] },'
    + '"xAxis": { "type": "category" }, "yAxis": {}, "legend": {},'
    + '"series": [{"type":"bar"},{"type":"bar"}] }';
  Draw(400, 300);
  withNames := RedIn(0, 250, 399, 299);
  AssertTrue(Format('the legend found names to list (%d px)', [withNames]),
    withNames > 20);

  { The same table read by series that DO name themselves proves the ink is
    the legend's and not something else in the band. }
  FChart.Option := '{ "dataset": { "source": ['
    + '["product","2015","2016"],'
    + '["a", 10, 90],'
    + '["b", 20, 80]] },'
    + '"xAxis": { "type": "category" }, "yAxis": {}, "legend": {},'
    + '"series": [{"type":"bar","name":"Own"},{"type":"bar"}] }';
  Draw(400, 300);
  without := RedIn(0, 250, 399, 299);
  AssertTrue(Format('a written name is still a name (%d px)', [without]),
    without > 20);
end;

procedure TAdvanceChartTest.TestEncodeOverridesWhichColumnASeriesReads;
var
  red, green: Integer;
begin
  { AN ENCODE NAMES A COLUMN BY NAME and takes the series out of the counter.

    THE PROBE IS A RATIO, not a position: with one column 10/20 and the other
    90/80, a series reading the high one draws several times the ink of one
    reading the low one. Asking instead whether a bar reaches the top of the
    plot would test the AXIS -- which re-scales around whatever is left -- and
    a single low series would reach the top too.

    TWO SERIES IN BOTH CHARTS, so the axis is the same in both and the only
    difference is which column the second one read. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ "dataset": { "source": ['
    + '["product","2015","2016"],'
    + '["a", 10, 90],'
    + '["b", 20, 80]] },'
    + '"xAxis": { "type": "category" }, "yAxis": {},'
    + '"series": [{"type":"bar"},{"type":"bar"}] }';
  Draw(400, 300);
  red := RedIn(0, 0, 399, 219);
  green := GreenIn(0, 0, 399, 219);
  AssertTrue(Format('by default the second takes the HIGH column '
    + '(%d red, %d green)', [red, green]), green > red * 2);

  { Now name the low column for the second series. It leaves the counter, the
    first series still takes column 1 from it, and the two draw the same
    height -- so the ratio collapses. }
  FChart.Option := '{ "dataset": { "source": ['
    + '["product","2015","2016"],'
    + '["a", 10, 90],'
    + '["b", 20, 80]] },'
    + '"xAxis": { "type": "category" }, "yAxis": {},'
    + '"series": [{"type":"bar"},'
    + '{"type":"bar","encode":{"x":"product","y":"2015"}}] }';
  Draw(400, 300);
  red := RedIn(0, 0, 399, 219);
  green := GreenIn(0, 0, 399, 219);
  AssertTrue(Format('named by name, it reads the low one instead '
    + '(%d red, %d green)', [red, green]),
    (green < red * 2) and (red < green * 2));
end;

procedure TAdvanceChartTest.TestAPieReadingATableNamesItsSlicesFromAColumn;
var
  red, green: Integer;
begin
  { A PIE OVER A TABLE ASKS TWO QUESTIONS the other series do not: which column
    is the NUMBER and which is the LABEL. It gets them from the other defaulter
    -- the one that guesses rather than counts -- and if that never ran the pie
    would have no value column at all and draw nothing.

    THE SLICE NAMES ARE THE TEST for the second half: a pie's legend lists its
    SLICES, so a legend with entries proves the rows were named off a column.
    Nothing else in this chart can name them -- a dataset row has no `name`
    field to fall back on. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }'
    + ' TyAdvChartLegend { color: #0000FF; }';
  FChart.Option := '{ "dataset": { "source": ['
    + '["product","2015","2016"],'
    + '["a", 10, 90],'
    + '["b", 20, 80]] },'
    + '"legend": {},'
    + '"series": [{"type":"pie","label":{"show":false}}] }';
  Draw(400, 300);
  red := RedIn(0, 0, 399, 245);
  green := GreenIn(0, 0, 399, 245);
  AssertTrue(Format('two slices, one per row (%d, %d)', [red, green]),
    (red > 100) and (green > 100));
  AssertTrue(Format('and the legend found names for them (%d px)',
    [BlueIn(0, 250, 399, 299)]), BlueIn(0, 250, 399, 299) > 10);
end;

procedure TAdvanceChartTest.TestACoordinateNobodyClaimedDrawsNothing;
begin
  { `encode: { x: -1 }` opts the coordinate out, and a bar with no category is
    not a bar at the origin -- it is no bar.

    IT IS THE X THAT IS OPTED OUT AND NOT THE Y, which matters: a reader that
    treated `unclaimed` as `column 0` would land on the PRODUCT column, which
    is exactly the category column a bar wants -- so the two answers would
    agree and the fixture would prove nothing. Opting the Y out instead lands
    the fallback on a column of words, which parses to no number and draws
    nothing either way. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ "dataset": { "source": ['
    + '["product","2015","2016"],'
    + '["a", 10, 90],'
    + '["b", 20, 80]] },'
    + '"xAxis": { "type": "category" }, "yAxis": {},'
    + '"series": [{"type":"bar","encode":{"x":-1,"y":"2016"}},'
    + '{"type":"bar"}] }';
  Draw(400, 300);
  AssertEquals('the opted-out series draws nothing', 0,
    RedIn(0, 0, 399, 219));
  AssertTrue(Format('while its neighbour draws (%d px)',
    [GreenIn(0, 0, 399, 219)]), GreenIn(0, 0, 399, 219) > 100);
end;

procedure TAdvanceChartTest.TestASeriesCanReadTheTableTheOtherWayRound;
var
  red, green: Integer;
begin
  { `seriesLayoutBy` IS A SERIES' OPTION AS WELL AS A DATASET'S, and the
    series' answer wins -- so two series can read one table in two directions.
    A corpus example does exactly that, seven bars over one table with three of
    them transposed and the dataset saying nothing.

    THE TABLE IS NOT SQUARE, on purpose, and its first column starts with a
    word and continues with numbers -- so the two readings disagree about the
    header as well as about the direction. A reader that ignored the override
    would draw the same picture twice. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ "dataset": { "source": ['
    + '["p", "q", "r"],'
    + '[1, 2, 3],'
    + '[40, 50, 60]] },'
    + '"xAxis": { "type": "category" }, "yAxis": {},'
    + '"series": [{"type":"bar"},'
    + '{"type":"bar","seriesLayoutBy":"row"}] }';
  Draw(400, 300);
  red := RedIn(0, 0, 399, 219);
  green := GreenIn(0, 0, 399, 219);
  AssertTrue(Format('both drew (%d red, %d green)', [red, green]),
    (red > 50) and (green > 50));
  { WHAT EACH ONE ACTUALLY GOT, which is worth spelling out because the answer
    is not the obvious one:

      read DOWN, the header is the first ROW, so the columns are p/q/r and the
      first series takes the category from p and its values from q -- 2 and 50,
      one of them the largest number on the chart;

      read ACROSS, the header is the first COLUMN, whose cells are `p`, 1 and
      40 -- a string then a number, so there is NO header at all, the three
      rows become three dimensions, and the transposed series takes its values
      from the second of them: 1, 2, 3.

    So the axis is sized by the 50 and the transposed series' three bars are
    slivers beside it. Ignore the override and that series would read column 2
    instead -- 3 and 60 -- and carry MORE ink than its neighbour, not less, so
    the ratio does not merely shrink but flips. }
  AssertTrue(Format('and the transposed one read a different shape '
    + '(%d red, %d green)', [red, green]), red > green * 2);
end;

procedure TAdvanceChartTest.TestTwoBarSeriesStandSideBySideInsteadOfOnTopOfEachOther;
var
  gb: TTyGridBuild;
  t, b, x, firstRed, lastRed, firstGreen, lastGreen: Integer;
begin
  { WHAT THE SOLVER IS FOR, seen from the outside. Two bar series on ONE
    category used to be drawn in exactly the same rectangle: the second hid the
    first, and a chart with two series looked like a chart with one.

    Both are given the same value so the only thing that can distinguish them
    is WHERE they are, not how tall. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', data: [80] }, { type: ''bar'', data: [80] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  t := Round(gb.PlotRect.Top) + 4;
  b := Round((gb.PlotRect.Top + gb.PlotRect.Bottom) / 2);

  firstRed := -1; lastRed := -1; firstGreen := -1; lastGreen := -1;
  for x := Round(gb.PlotRect.Left) to Round(gb.PlotRect.Right) do
  begin
    if RedIn(x, t, x, b) > 0 then
    begin
      if firstRed < 0 then firstRed := x;
      lastRed := x;
    end;
    if GreenIn(x, t, x, b) > 0 then
    begin
      if firstGreen < 0 then firstGreen := x;
      lastGreen := x;
    end;
  end;

  AssertTrue('the first series is drawn', firstRed >= 0);
  AssertTrue('and so is the second -- which it was not before the solver, '
    + 'because it was underneath', firstGreen >= 0);
  { SIDE BY SIDE: one column entirely left of the other. Overlap of any kind
    would put a green column inside the red one's span. }
  AssertTrue(Format('they do not overlap (red %d..%d, green %d..%d)',
    [firstRed, lastRed, firstGreen, lastGreen]), lastRed < firstGreen);

  { AND THE GROUP IS STILL CENTRED on the single category's band, so adding a
    series does not shove the chart sideways. }
  AssertEquals('the pair straddles the band centre',
    (gb.PlotRect.Left + gb.PlotRect.Right) / 2,
    (firstRed + lastGreen) / 2, 2.0);
end;

procedure TAdvanceChartTest.TestAStackedBarStandsOnTheOneBelowIt;
var
  gb: TTyGridBuild;
  l, r, y, redTop, redBot, greenTop, greenBot: Integer;
begin
  { STACKING, SEEN FROM THE OUTSIDE. Two series naming one stack occupy ONE
    column -- the bar solver already saw to that -- and the second stands on
    top of the first rather than starting from the axis.

    Both are 40 out of 100, so if the upper one drew from the baseline the two
    would coincide exactly and the picture would show a single 40-tall bar. }
  FCtl.StyleOverride := 'TyAdvChartSeries1 { background: #FF0000; }'
    + ' TyAdvChartSeries2 { background: #00FF00; }';
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 100 },'
    + ' series: [{ type: ''bar'', stack: ''s'', data: [40] },'
    + '          { type: ''bar'', stack: ''s'', data: [40] }] }';
  Draw;
  gb := FChart.Build.Grid(0);
  l := Round(gb.PlotRect.Left);
  r := Round(gb.PlotRect.Right);

  redTop := -1; redBot := -1; greenTop := -1; greenBot := -1;
  for y := Round(gb.PlotRect.Top) to Round(gb.PlotRect.Bottom) do
  begin
    if RedIn(l, y, r, y) > 0 then
    begin
      if redTop < 0 then redTop := y;
      redBot := y;
    end;
    if GreenIn(l, y, r, y) > 0 then
    begin
      if greenTop < 0 then greenTop := y;
      greenBot := y;
    end;
  end;

  AssertTrue('the lower series is drawn', redTop >= 0);
  AssertTrue('and the upper one', greenTop >= 0);
  { ONE ABOVE THE OTHER, not side by side and not on top of each other: the
    upper bar's whole span is above the lower bar's top edge. }
  AssertTrue(Format('the upper sits above the lower (red %d..%d, green %d..%d)',
    [redTop, redBot, greenTop, greenBot]), greenBot <= redTop + 1);
  { AND THEY MEET. A gap would mean the floor was computed from something other
    than the value below. }
  AssertTrue(Format('with no gap between them (%d vs %d)', [greenBot, redTop]),
    Abs(greenBot - redTop) <= 2);

  { THE TOTAL REACHES 80 OF 100, which is what says the values accumulated
    rather than merely being drawn in two places. }
  AssertTrue(Format('the pile is about 80%% of the plot, got %d..%d',
    [greenTop, redBot]),
    Abs((redBot - greenTop) - Round(0.8 * (gb.PlotRect.Bottom - gb.PlotRect.Top))) < 6);
end;

function TAdvanceChartTest.RedIn(AL, AT, AR, AB: Integer): Integer;
var x, y: Integer; p: TBGRAPixel;
begin
  Result := 0;
  for y := AT to AB do
    for x := AL to AR do
    begin
      p := PixelAt(x, y);
      if (p.red > 180) and (p.green < 80) and (p.blue < 80) then Inc(Result);
    end;
end;

function TAdvanceChartTest.BlueIn(AL, AT, AR, AB: Integer): Integer;
var x, y: Integer; p: TBGRAPixel;
begin
  Result := 0;
  for y := AT to AB do
    for x := AL to AR do
    begin
      p := PixelAt(x, y);
      if (p.blue > 180) and (p.red < 80) and (p.green < 80) then Inc(Result);
    end;
end;

function TAdvanceChartTest.GreenIn(AL, AT, AR, AB: Integer): Integer;
var x, y: Integer; p: TBGRAPixel;
begin
  Result := 0;
  for y := AT to AB do
    for x := AL to AR do
    begin
      p := PixelAt(x, y);
      if (p.green > 180) and (p.red < 80) and (p.blue < 80) then Inc(Result);
    end;
end;

initialization
  RegisterTest(TAdvanceChartTest);
end.
