unit test.advchart.furniture;
{$mode objfpc}{$H+}
{ What a cartesian axis actually DRAWS.

  THE DEFAULTS ARE THE SUBJECT HERE, not the options. On the commonest chart
  there is -- a category x against a value y, with no axis option written at
  all -- upstream draws the x domain line and the y split lines and nothing
  else: no x ticks, no x split lines, no y domain line, no y ticks. The port
  drew all six, which is four wrong answers to a question the author never
  asked, and is the difference between bars on a grid and bars in a box.

  Every fixture below is deliberately ASYMMETRIC in the thing it is about. The
  six answers differ from each other; `auto` is made to resolve true in one
  chart and false in another with the SAME option text; the overrides all point
  the opposite way from their defaults; and the split-area stripe count is two
  out of four, so neither "paint them all" nor "paint none" can pass. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Layout,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartFurnitureTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string;
                   AW: Integer = 400; AH: Integer = 300; APPI: Integer = 96);
    function Grid: TTyGridBuild;
    function XFurn: TTyAxisFurniture;
    function YFurn: TTyAxisFurniture;
    function PlotOf(const AOption: string): TTyRectF;
    function RedRunsAcross(AY, AL, AR: Integer): Integer;
    function RedRunsDown(AX, AT, AB: Integer): Integer;
    function RedStarts(AY, AL, AR: Integer): TTyDoubleArray;
  published
    { the defaults }
    procedure TestABarChartsSixAnswersAreNotAllYes;
    procedure TestTheSixAnswersReachThePixels;
    procedure TestTwoValueAxesTurnEveryAutoOn;
    procedure TestAHorizontalBarMirrorsTheAnswers;
    procedure TestNoBoundaryGapBringsTheCategoryTicksBack;
    procedure TestAutoIsResolvedNotReadAsTrue;
    procedure TestTheMinorGridIsAValueAxisAffair;
    procedure TestATimeAxisDropsItsSplitLines;
    procedure TestALogAxisKeepsTheValueAnswers;
    procedure TestATimeAxisIsNoNumberLineOnEitherSide;
    { the options }
    procedure TestEveryDefaultCanBeOverturned;
    { the gutter }
    procedure TestHiddenTicksGiveTheGutterBack;
    procedure TestAnInsideTickCostsNothingOutside;
    procedure TestTheAuthorsTickLengthMovesThePlot;
    procedure TestInsideLabelsGiveTheirGutterBack;
    procedure TestTheAuthorsLabelMarginMovesThePlot;
    procedure TestARotatedLabelDeepensTheBottomGutter;
    { the paint }
    procedure TestSplitAreasStripeEveryOtherBand;
    procedure TestAlignWithLabelMovesTheTicksHalfABand;
    procedure TestAnInsideTickPointsIntoThePlot;
    procedure TestANegativeTickLengthPointsInwardToo;
    procedure TestMinorTicksFollowTheMajorsInside;
    procedure TestTheAuthorsMinorTickLengthIsDrawn;
    procedure TestMinorTicksDoNotBecomeSplitLines;
    procedure TestAMinorGridNeedsNoMinorTicks;
    procedure TestTheAuthorsMinorSplitNumberIsUsed;
    procedure TestMinorTicksBringNoMinorGridWithThem;
    procedure TestTheEndSplitLinesAreSeparatelyDeniable;
    procedure TestARotatedLabelIsActuallyTurned;
    procedure TestATopAxisTurnsItsLabelsTheOtherWay;
    { the axis' own show }
    procedure TestAHiddenAxisGivesItsGutterBack;
  end;

implementation

const
  { The light theme's own values at 96 dpi, which is what Draw renders at. }
  cTickLen = 5.0;
  cLabelMargin = 8.0;
  Eps = 0.6;

  { Opaque primaries for the three things counted by eye below. The theme paints
    split lines at alpha 0.6 and split areas at 0.04, and neither alpha has
    anything to do with what is being asserted -- an unoverridden split area is
    four per cent of the way from white to black and no run-length scan could
    see it at all. }
  cRedSplitLine = 'TyAdvChartSplitLine { border-color: #FF0000;'
    + ' border-width: 1px; }';
  cRedSplitArea = 'TyAdvChartSplitArea { background: #FF0000; }';
  cRedTick = 'TyAdvChartAxisTick { border-color: #FF0000;'
    + ' border-width: 1px; }';

procedure TAdvChartFurnitureTest.SetUp;
begin
  inherited SetUp;
  { Parented, with its own controller pinned to the built-in light default --
    both for the reasons test.advancechart's SetUp records at length: an orphan
    control skips the corner-gap fill, and reading the process-wide controller
    makes every pixel assertion depend on whatever suite ran before this one. }
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartFurnitureTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartFurnitureTest.Draw(const AOption: string;
  AW, AH, APPI: Integer);
begin
  FreeAndNil(FBmp);
  { Magenta: a colour no theme in this library produces, so "nothing was painted
    here" stays distinguishable from "the surface was painted here". }
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 0, 255, 255));
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, AW, AH), APPI);
end;

function TAdvChartFurnitureTest.Grid: TTyGridBuild;
begin
  Result := FChart.Build.Grid(0);
end;

function TAdvChartFurnitureTest.XFurn: TTyAxisFurniture;
begin
  Result := Grid.FurnitureFor(Grid.XAxis(0));
end;

function TAdvChartFurnitureTest.YFurn: TTyAxisFurniture;
begin
  Result := Grid.FurnitureFor(Grid.YAxis(0));
end;

function TAdvChartFurnitureTest.PlotOf(const AOption: string): TTyRectF;
begin
  Draw(AOption);
  Result := Grid.PlotRect;
end;

{ Runs of red along a row. A vertical hairline is one short run; a horizontal
  one inking the whole row would be a single run as wide as the plot, which is
  why the counts below are paired with positions or with a clear row. }
function TAdvChartFurnitureTest.RedRunsAcross(AY, AL, AR: Integer): Integer;
var x, span: Integer; p: TBGRAPixel;
begin
  Result := 0;
  span := 0;
  for x := AL to AR do
  begin
    p := FBmp.GetPixel(x, AY);
    if p.red > p.green + 40 then Inc(span)
    else begin if span > 0 then Inc(Result); span := 0; end;
  end;
  if span > 0 then Inc(Result);
end;

function TAdvChartFurnitureTest.RedRunsDown(AX, AT, AB: Integer): Integer;
var y, span: Integer; p: TBGRAPixel;
begin
  Result := 0;
  span := 0;
  for y := AT to AB do
  begin
    p := FBmp.GetPixel(AX, y);
    if p.red > p.green + 40 then Inc(span)
    else begin if span > 0 then Inc(Result); span := 0; end;
  end;
  if span > 0 then Inc(Result);
end;

{ Where each run along a row begins. }
function TAdvChartFurnitureTest.RedStarts(AY, AL, AR: Integer): TTyDoubleArray;
var x, span: Integer; p: TBGRAPixel;
begin
  Result := nil;
  span := 0;
  for x := AL to AR do
  begin
    p := FBmp.GetPixel(x, AY);
    if p.red > p.green + 40 then
    begin
      if span = 0 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := x;
      end;
      Inc(span);
    end
    else
      span := 0;
  end;
end;

{ ==================== the defaults ==================== }

procedure TAdvChartFurnitureTest.TestABarChartsSixAnswersAreNotAllYes;
var fx, fy: TTyAxisFurniture;
begin
  { THE HEADLINE. Not one axis option is written here, and upstream still
    answers six questions -- three of them one way and three the other. A port
    that says yes to everything satisfies any test that only asks "was an axis
    drawn", which is why every earlier assertion in this suite was green. }
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5, 3, 8, 2] }] }');
  fx := XFurn;
  fy := YFurn;
  AssertTrue('the category axis draws its domain line', fx.ShowLine);
  AssertFalse('...and no ticks under the bands', fx.ShowTicks);
  AssertFalse('...and no vertical grid', fx.ShowSplitLine);
  AssertFalse('the value axis draws no domain line', fy.ShowLine);
  AssertFalse('...and no ticks beside the numbers', fy.ShowTicks);
  AssertTrue('...and the horizontal grid is its', fy.ShowSplitLine);
  AssertFalse('nobody asked for shaded bands', fx.ShowSplitArea);
  AssertFalse('nor for them here', fy.ShowSplitArea);
end;

procedure TAdvChartFurnitureTest.TestTheSixAnswersReachThePixels;
var r: TTyRectF; l, t, rr, b: Integer;
begin
  { RESOLVED IS NOT DRAWN. Building a correct answer and then painting the old
    one is this project's most-repeated failure, so the same chart is counted in
    ink: a row across the plot must meet no vertical line, and a column down it
    must meet the horizontal grid. }
  FCtl.StyleOverride := cRedSplitLine;
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''] },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  r := Grid.PlotRect;
  l := Round(r.Left); t := Round(r.Top);
  rr := Round(r.Right); b := Round(r.Bottom);

  { Six pixels below the top: the top edge carries the 100 line and the next is
    a fifth of the height down, so this row is clear of both. }
  AssertEquals('a row across the plot meets no vertical split line',
    0, RedRunsAcross(t + 6, l + 2, rr - 2));
  { A column a third of the way in, clear of the axis and of any bar. Zero to a
    hundred nices to five intervals, so six lines are drawn and the two on the
    plot's own edges fall outside this scan: four is what is left, and the
    assertion is that the grid is THERE while the row above found nothing. }
  AssertEquals('but a column down it meets the horizontal grid',
    4, RedRunsDown(l + (rr - l) div 3, t + 2, b - 2));
end;

procedure TAdvChartFurnitureTest.TestTwoValueAxesTurnEveryAutoOn;
var fx, fy: TTyAxisFurniture;
begin
  { A SCATTER, where both axes are number lines -- so every `auto` in the
    defaults resolves the other way from the bar chart above. Without this the
    whole `auto` path could be hard-wired to false and the suite would not
    notice. }
  Draw('{ xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''scatter'', data: [[1, 2], [3, 4], [5, 1]] }] }');
  fx := XFurn;
  fy := YFurn;
  AssertTrue('x draws its domain line', fx.ShowLine);
  AssertTrue('and its ticks', fx.ShowTicks);
  AssertTrue('y draws its domain line', fy.ShowLine);
  AssertTrue('and its ticks', fy.ShowTicks);
  AssertTrue('both grids are on', fx.ShowSplitLine and fy.ShowSplitLine);
end;

procedure TAdvChartFurnitureTest.TestAHorizontalBarMirrorsTheAnswers;
var fx, fy: TTyAxisFurniture;
begin
  { Turn the bar chart on its side and all six answers swap sides. A resolver
    that keyed on the AXIS rather than on its type -- x gets this, y gets that
    -- passes the first test in this file and fails here. }
  Draw('{ yAxis: { data: [''A'', ''B'', ''C''] }, xAxis: {},'
    + ' series: [{ type: ''bar'', data: [5, 3, 8] }] }');
  fx := XFurn;
  fy := YFurn;
  AssertTrue('now the CATEGORY axis is y and it keeps its domain line',
    fy.ShowLine);
  AssertFalse('...with no ticks', fy.ShowTicks);
  AssertFalse('...and no grid', fy.ShowSplitLine);
  AssertFalse('the value axis is x now and loses its domain line', fx.ShowLine);
  AssertFalse('...and its ticks', fx.ShowTicks);
  AssertTrue('...and owns the grid', fx.ShowSplitLine);
end;

procedure TAdvChartFurnitureTest.TestNoBoundaryGapBringsTheCategoryTicksBack;
var fx: TTyAxisFurniture;
begin
  { THE SECOND CLAUSE of the tick's `auto`, and the reason a plain bar chart has
    no ticks under its categories: a tick between two bands points at nothing in
    particular, so a BANDED category axis suppresses them even when the other
    axis is a number line. Take the band away and they come back -- same chart,
    same other axis, one word different. }
  Draw('{ xAxis: { data: [''A'', ''B'', ''C''], boundaryGap: false },'
    + ' yAxis: {}, series: [{ type: ''line'', data: [5, 3, 8] }] }');
  fx := XFurn;
  AssertTrue('an unbanded category axis draws its ticks', fx.ShowTicks);
  AssertTrue('and still its domain line', fx.ShowLine);
  AssertFalse('and still no grid', fx.ShowSplitLine);
end;

procedure TAdvChartFurnitureTest.TestAutoIsResolvedNotReadAsTrue;
const
  cAuto = ' yAxis: { axisLine: { show: ''auto'' } },';
begin
  { THE SAME OPTION TEXT, TWICE, and it must answer differently. `auto` is a
    third value and not a synonym for true: it means "show me only when the
    other axis is a number line". Read as true it would draw the four extra
    things this file is about. }
  Draw('{ xAxis: { data: [''A'', ''B''] },' + cAuto
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertFalse('against a category x, auto is no', YFurn.ShowLine);

  Draw('{ xAxis: {},' + cAuto
    + ' series: [{ type: ''scatter'', data: [[1, 2], [3, 4]] }] }');
  AssertTrue('against a value x, the same word is yes', YFurn.ShowLine);
end;

procedure TAdvChartFurnitureTest.TestTheMinorGridIsAValueAxisAffair;
var fx, fy: TTyAxisFurniture;
begin
  { Asked for on both axes and granted on only one: a category axis has nothing
    between its categories to subdivide. }
  Draw('{ xAxis: { data: [''A'', ''B''], minorTick: { show: true },'
    + ' minorSplitLine: { show: true } },'
    + ' yAxis: { minorTick: { show: true }, minorSplitLine: { show: true } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  fx := XFurn;
  fy := YFurn;
  AssertFalse('a category axis has no minor ticks to give', fx.ShowMinorTick);
  AssertFalse('nor minor split lines', fx.ShowMinorSplitLine);
  AssertTrue('the value axis grants the ticks', fy.ShowMinorTick);
  AssertTrue('and the lines', fy.ShowMinorSplitLine);
end;

procedure TAdvChartFurnitureTest.TestATimeAxisDropsItsSplitLines;
var fx, fy: TTyAxisFurniture;
begin
  { A time axis inherits the value defaults and then turns the grid off again --
    a date axis is dense and a line per tick would be a cage. The value y beside
    it keeps its own grid, which is what makes this fixture asymmetric rather
    than a chart with no grid at all.

    AND TIME IS NOT A NUMBER LINE for the axis opposite it. `auto` asks
    isIntervalOrLogScale, which is `type = interval or type = log` and nothing
    else -- a time scale's type is `time`, and upstream's own comment beside the
    rule says "not show axisTick or axisLine if other axis is category / time".
    So the two axes here answer OPPOSITELY on both: the time axis sees a value
    axis and draws its line and ticks; the value axis sees a time axis and draws
    neither. Reading `time` as a number line would make both halves true and is
    the mistake this pairing exists to catch. }
  Draw('{ xAxis: { type: ''time'' }, yAxis: {},'
    + ' series: [{ type: ''line'', data: ['
    + '[''2024-03-05T00:00:00Z'', 5], [''2024-03-07T00:00:00Z'', 9]] }] }');
  fx := XFurn;
  fy := YFurn;
  AssertFalse('the time axis draws no grid', fx.ShowSplitLine);
  AssertTrue('the value axis beside it still does', fy.ShowSplitLine);
  AssertTrue('the time axis sees a value axis, so it draws its domain line',
    fx.ShowLine);
  AssertTrue('and its ticks', fx.ShowTicks);
  AssertFalse('the value axis sees a TIME axis, which does not count, so no',
    fy.ShowLine);
  AssertFalse('and no ticks either', fy.ShowTicks);
end;

procedure TAdvChartFurnitureTest.TestATimeAxisIsNoNumberLineOnEitherSide;
begin
  { THE SAME QUESTION WITH THE AXES SWAPPED. `is any axis of the other family
    a number line` is asked twice per grid, once walking the x axes and once
    the y, and the two walks are separate code. With the time axis only ever
    on x, the y walk could have counted time as a number line and every
    assertion in this file would still have passed -- the chart would only
    have gone wrong the day somebody put a date up the side.

    Here the date IS up the side, so it is the y walk that has to exclude it,
    and the value x opposite must draw no domain line and no ticks. }
  Draw('{ yAxis: { type: ''time'' }, xAxis: {},'
    + ' series: [{ type: ''line'', data: ['
    + '[5, ''2024-03-05T00:00:00Z''], [9, ''2024-03-07T00:00:00Z'']] }] }');
  AssertFalse('the value axis sees a time axis, which does not count',
    XFurn.ShowLine);
  AssertFalse('and no ticks either', XFurn.ShowTicks);
  AssertTrue('while the time axis, seeing a value axis, draws both',
    YFurn.ShowLine and YFurn.ShowTicks);
  AssertFalse('and still no grid of its own', YFurn.ShowSplitLine);
end;

procedure TAdvChartFurnitureTest.TestALogAxisKeepsTheValueAnswers;
var fy: TTyAxisFurniture;
begin
  { Log is the value defaults with a base bolted on -- so unlike time it KEEPS
    its split lines, and unlike category it counts as a number line for the axis
    on the other side. Both halves are asserted. }
  Draw('{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: { type: ''log'' },'
    + ' series: [{ type: ''bar'', data: [1, 10, 100] }] }');
  fy := YFurn;
  AssertTrue('a log axis keeps the value axis'' grid', fy.ShowSplitLine);
  AssertTrue('and counts as a number line for the category axis opposite it',
    XFurn.ShowLine);
end;

{ ==================== the options ==================== }

procedure TAdvChartFurnitureTest.TestEveryDefaultCanBeOverturned;
var fx, fy: TTyAxisFurniture;
begin
  { EVERY ASSERTION HERE IS THE OPPOSITE OF THE DEFAULT, so not one of them can
    be satisfied by the resolver ignoring the option and answering from the
    type. The two axes are given opposite instructions for the same reason. }
  Draw('{ xAxis: { data: [''A'', ''B''],'
    + ' axisLine: { show: false }, axisTick: { show: true },'
    + ' splitLine: { show: true }, splitArea: { show: true } },'
    + ' yAxis: { axisLine: { show: true }, axisTick: { show: true },'
    + ' axisLabel: { show: false }, splitLine: { show: false },'
    + ' minorTick: { show: true }, minorSplitLine: { show: true } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  fx := XFurn;
  fy := YFurn;
  AssertFalse('the category axis'' domain line, switched off', fx.ShowLine);
  AssertTrue('its ticks, switched on', fx.ShowTicks);
  AssertTrue('its grid, switched on', fx.ShowSplitLine);
  AssertTrue('its bands, switched on', fx.ShowSplitArea);
  AssertTrue('the value axis'' domain line, switched on', fy.ShowLine);
  AssertTrue('its ticks, switched on', fy.ShowTicks);
  AssertFalse('its labels, switched off', fy.ShowLabels);
  AssertFalse('its grid, switched off', fy.ShowSplitLine);
  AssertTrue('its minor ticks, switched on', fy.ShowMinorTick);
  AssertTrue('its minor grid, switched on', fy.ShowMinorSplitLine);
end;

{ ==================== the gutter ==================== }

procedure TAdvChartFurnitureTest.TestHiddenTicksGiveTheGutterBack;
var withT, without: TTyRectF;
begin
  { Switching the ticks off must give the space back, not merely stop drawing
    them -- otherwise a tickless axis still pushes the plot in five pixels and
    reads as an axis that lost its marks rather than one that has none. }
  withT := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { axisTick: { show: true } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  without := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { axisTick: { show: false } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertEquals('exactly the tick''s length, given back',
    cTickLen, withT.Left - without.Left, Eps);
end;

procedure TAdvChartFurnitureTest.TestAnInsideTickCostsNothingOutside;
var outside, inside, off: TTyRectF;
begin
  { THREE WAYS, because two would not separate the readings. An inside tick is
    drawn and costs nothing; a hidden tick is not drawn and costs nothing; an
    outside tick is drawn and costs its length. Read `inside` as `hidden` and
    the first two still agree -- the pixels in TestAnInsideTickPointsIntoThePlot
    are what tell those apart. }
  outside := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { axisTick: { show: true, inside: false } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  inside := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { axisTick: { show: true, inside: true } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  off := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { axisTick: { show: false } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertEquals('an inside tick reserves nothing outside',
    off.Left, inside.Left, Eps);
  AssertEquals('and an outside one reserves its length',
    cTickLen, outside.Left - inside.Left, Eps);
end;

procedure TAdvChartFurnitureTest.TestTheAuthorsTickLengthMovesThePlot;
var short_, long_: TTyRectF;
begin
  { A length is a geometric value and an author is allowed to name one. Twenty
    against the theme's five, so the difference is fifteen and no rounding can
    mistake it for the default. }
  short_ := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { axisTick: { show: true } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  long_ := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { axisTick: { show: true, length: 20 } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertEquals('fifteen more than the theme''s five',
    20 - cTickLen, long_.Left - short_.Left, Eps);
end;

procedure TAdvChartFurnitureTest.TestInsideLabelsGiveTheirGutterBack;
var outside, inside, off: TTyRectF;
begin
  { Same three-way as the ticks. The labels here are wide -- five figures -- so
    the gutter they own is far larger than the margin, and a reading that gave
    back only the margin would still fail. }
  outside := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 10000 },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  inside := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 10000, axisLabel: { inside: true } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  off := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 10000, axisLabel: { show: false } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertEquals('inside labels reserve nothing outside',
    off.Left, inside.Left, Eps);
  AssertTrue(Format('and outside ones reserve their width plus the margin '
    + '(%.1f given back, the margin alone is %.1f)',
    [outside.Left - inside.Left, cLabelMargin]),
    outside.Left - inside.Left > cLabelMargin + 10);
end;

procedure TAdvChartFurnitureTest.TestTheAuthorsLabelMarginMovesThePlot;
var near_, far_: TTyRectF;
begin
  near_ := PlotOf('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  far_ := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { axisLabel: { margin: 40 } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertEquals('forty instead of the theme''s eight',
    40 - cLabelMargin, far_.Left - near_.Left, Eps);
end;

procedure TAdvChartFurnitureTest.TestARotatedLabelDeepensTheBottomGutter;
var flat, turned: TTyRectF;
begin
  { Turned upright, a bottom label's WIDTH is what eats height. The categories
    are long enough that the two readings cannot be confused -- nine characters
    against one line of text. }
  flat := PlotOf('{ xAxis: { data: [''Wednesday'', ''Thursday''] },'
    + ' yAxis: {}, series: [{ type: ''bar'', data: [1, 2] }] }');
  turned := PlotOf('{ xAxis: { data: [''Wednesday'', ''Thursday''],'
    + ' axisLabel: { rotate: 90 } },'
    + ' yAxis: {}, series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertTrue(Format('a quarter turn costs height (flat bottom %.1f, '
    + 'turned %.1f)', [flat.Bottom, turned.Bottom]),
    turned.Bottom < flat.Bottom - 15);
end;

{ ==================== the paint ==================== }

procedure TAdvChartFurnitureTest.TestSplitAreasStripeEveryOtherBand;
var r: TTyRectF; runs: Integer;
begin
  { TWO OF FOUR. The bands alternate, so four categories give two stripes:
    painting them all gives four runs and painting none gives nought, and
    neither can pass. The key has been in light.tycss since item 18 with
    nothing in the painter that could draw with it. }
  FCtl.StyleOverride := cRedSplitArea;
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' splitArea: { show: true } },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  r := Grid.PlotRect;
  runs := RedRunsAcross(Round(r.Top) + 6, Round(r.Left), Round(r.Right));
  AssertEquals('four bands, every other one shaded', 2, runs);
end;

procedure TAdvChartFurnitureTest.TestAlignWithLabelMovesTheTicksHalfABand;
var r: TTyRectF; edges, centres: TTyDoubleArray; band: Double; y: Integer;
begin
  { Half a band apart, and the COUNT differs too: four bands have five edges and
    four centres. Either reading alone would be a plausible-looking bug that
    draws ticks somewhere. }
  FCtl.StyleOverride := cRedTick;
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' axisTick: { show: true } },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  r := Grid.PlotRect;
  band := (r.Right - r.Left) / 4;
  { Three pixels below the axis line, inside the five the tick is long. }
  y := Round(r.Bottom) + 3;
  edges := RedStarts(y, Round(r.Left) - 2, Round(r.Right) + 2);

  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' axisTick: { show: true, alignWithLabel: true } },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  centres := RedStarts(y, Round(r.Left) - 2, Round(r.Right) + 2);

  AssertEquals('one tick per band EDGE', 5, Length(edges));
  AssertEquals('one tick per band CENTRE', 4, Length(centres));
  AssertEquals(Format('and the first centre is half a band (%.1f px) past the '
    + 'first edge', [band / 2]), band / 2, centres[0] - edges[0], 2.0);
end;

procedure TAdvChartFurnitureTest.TestAnInsideTickPointsIntoThePlot;
var r: TTyRectF; below, above: Integer;
begin
  { The whole of what `inside` does is turn the mark round. Counted on both
    sides of the axis line, so "inside means hidden" fails the second probe and
    "inside is ignored" fails the first. }
  FCtl.StyleOverride := cRedTick;
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' axisTick: { show: true, inside: true } },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  r := Grid.PlotRect;
  below := RedRunsAcross(Round(r.Bottom) + 3, Round(r.Left) - 2,
                         Round(r.Right) + 2);
  above := RedRunsAcross(Round(r.Bottom) - 3, Round(r.Left) - 2,
                         Round(r.Right) + 2);
  AssertEquals('nothing below the axis line', 0, below);
  AssertEquals('and one mark per band edge above it', 5, above);
end;

procedure TAdvChartFurnitureTest.TestANegativeTickLengthPointsInwardToo;
var r: TTyRectF; below, above: Integer;
begin
  { UPSTREAM'S OTHER WAY OF SAYING `inside`: the length itself carries the
    direction. It also has to survive being READ -- a -1 sentinel for `the
    theme decides` would swallow every negative length an author writes, and
    there would be no way to express this at all. }
  FCtl.StyleOverride := cRedTick;
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' axisTick: { show: true, length: -6 } },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  r := Grid.PlotRect;
  below := RedRunsAcross(Round(r.Bottom) + 3, Round(r.Left) - 2,
                         Round(r.Right) + 2);
  above := RedRunsAcross(Round(r.Bottom) - 4, Round(r.Left) - 2,
                         Round(r.Right) + 2);
  AssertEquals('nothing below the axis line', 0, below);
  AssertEquals('and one mark per band edge above it', 5, above);
end;

procedure TAdvChartFurnitureTest.TestMinorTicksFollowTheMajorsInside;
var r: TTyRectF;
begin
  { There is no `minorTick.inside`. Upstream flips ONE tick direction and every
    mark on the axis follows it, so majors pointing in with minors still
    pointing out is not a state it can reach -- and the layout, which reserved
    nothing outside, would be drawn over. }
  FCtl.StyleOverride := 'TyAdvChartMinorTick { border-color: #FF0000;'
    + ' border-width: 1px; }';
  Draw('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100, axisTick: { show: true, inside: true },'
    + ' minorTick: { show: true } },'
    + ' series: [] }');
  r := Grid.PlotRect;
  AssertEquals('no minor mark outside the plot', 0,
    RedRunsDown(Round(r.Left) - 2, Round(r.Top), Round(r.Bottom)));
  AssertTrue('but they are drawn, inside it',
    RedRunsDown(Round(r.Left) + 2, Round(r.Top), Round(r.Bottom)) > 2);
end;

procedure TAdvChartFurnitureTest.TestTheAuthorsMinorTickLengthIsDrawn;
var r: TTyRectF; reach, x: Integer;
begin
  { Fifteen against the theme's three, so the reach is unmistakable. The option
    was catalogued and never read: only `axisTick.length` was. }
  FCtl.StyleOverride := 'TyAdvChartMinorTick { border-color: #FF0000;'
    + ' border-width: 1px; }';
  Draw('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100,'
    + ' minorTick: { show: true, length: 15 } },'
    + ' series: [] }');
  r := Grid.PlotRect;
  reach := 0;
  for x := Round(r.Left) - 1 downto Round(r.Left) - 20 do
    if RedRunsDown(x, Round(r.Top), Round(r.Bottom)) > 0 then
      reach := Round(r.Left) - x;
  AssertTrue(Format('the marks reach %d px out, and should reach about 15',
    [reach]), (reach >= 13) and (reach <= 16));
end;

procedure TAdvChartFurnitureTest.TestMinorTicksDoNotBecomeSplitLines;
var r: TTyRectF; withMinor, without: Integer;
begin
  { GetTicks hands majors and minors back in ONE array with a Level field, and
    TickCoords took it whole -- so asking for a minor grid drew the MAJOR grid
    at every subdivision as well, in the major style, five lines where there
    should be one. Counted with and without, because the count alone proves
    nothing: the two must be EQUAL. }
  FCtl.StyleOverride := cRedSplitLine;
  Draw('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  r := Grid.PlotRect;
  without := RedRunsDown(Round(r.Left) + 20, Round(r.Top) + 2,
                         Round(r.Bottom) - 2);
  Draw('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100, minorTick: { show: true } },'
    + ' series: [] }');
  withMinor := RedRunsDown(Round(r.Left) + 20, Round(r.Top) + 2,
                           Round(r.Bottom) - 2);
  AssertTrue('there is a major grid to count', without > 2);
  AssertEquals('asking for minor ticks adds no MAJOR split lines',
    without, withMinor);
end;

procedure TAdvChartFurnitureTest.TestAMinorGridNeedsNoMinorTicks;
var r: TTyRectF;
begin
  { `minorSplitLine: { show: true }` ALONE. The subdivisions upstream draws
    it at come from `minorTick.splitNumber` and from nothing else -- asking
    for the grid is asking for them. The port computed them only when
    `minorTick.show` was true, so this option drew nothing whatever, and the
    two halves could not be told apart by any test: a minor tick could not
    exist unless the option that made it had also asked to draw it.

    Both halves asserted. The grid appears AND the marks do not, which is
    what makes each gate load-bearing rather than merely present. }
  { ONE COLOUR FOR BOTH, and the geometry separates them: a minor split line
    spans the plot's width and a minor MARK hangs outside its left edge, so
    the two probes below cannot see each other's subject. Overriding the
    marks green instead -- which is what this did first -- made the second
    assertion vacuous, because RedRunsDown asks whether red beats green and
    green never does: the marks were counted as absent whether they were
    drawn or not, and mutating their gate away changed nothing. }
  FCtl.StyleOverride := 'TyAdvChartMinorSplitLine { border-color: #FF0000;'
    + ' border-width: 1px; } TyAdvChartMinorTick { border-color: #FF0000;'
    + ' border-width: 1px; } TyAdvChartSplitLine { border-color: #FFFFFF; }';
  Draw('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100, minorSplitLine: { show: true } },'
    + ' series: [] }');
  r := Grid.PlotRect;
  AssertTrue('the minor grid is drawn without a single minor tick asked for',
    RedRunsDown(Round(r.Left) + 20, Round(r.Top) + 2, Round(r.Bottom) - 2)
      > 8);
  AssertEquals('and no minor MARKS came with it', 0,
    RedRunsDown(Round(r.Left) - 2, Round(r.Top), Round(r.Bottom)));
end;

procedure TAdvChartFurnitureTest.TestTheAuthorsMinorSplitNumberIsUsed;

  function GridLines(const AOption: string): Integer;
  var r: TTyRectF;
  begin
    Draw(AOption);
    r := Grid.PlotRect;
    Result := RedRunsDown(Round(r.Left) + 20, Round(r.Top) + 2,
                          Round(r.Bottom) - 2);
  end;

var five, two: Integer;
begin
  { `minorTick.splitNumber` is read whether or not `minorTick.show` is --
    upstream's getMinorTicksCoords asks for it and nothing else. Zero to a
    hundred nices to five intervals, so the default five subdivisions give
    four lines in each and a split of two gives one: twenty against five, and
    no rounding can confuse them. }
  FCtl.StyleOverride := 'TyAdvChartMinorSplitLine { border-color: #FF0000;'
    + ' border-width: 1px; } TyAdvChartSplitLine { border-color: #FFFFFF; }';
  five := GridLines('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100, minorSplitLine: { show: true } },'
    + ' series: [] }');
  two := GridLines('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100, minorSplitLine: { show: true },'
    + ' minorTick: { splitNumber: 2 } },'
    + ' series: [] }');
  AssertTrue(Format('five subdivisions of five intervals give about twenty '
    + 'lines, and gave %d', [five]), (five >= 16) and (five <= 20));
  AssertTrue(Format('two subdivisions give about five, and gave %d', [two]),
    (two >= 4) and (two <= 6));
end;

procedure TAdvChartFurnitureTest.TestMinorTicksBringNoMinorGridWithThem;
var r: TTyRectF;
begin
  { And the other way round: asking for the MARKS must not grow a grid. The
    subdivisions now exist as soon as either option is written, so the two
    show flags are the only thing keeping them apart. }
  FCtl.StyleOverride := 'TyAdvChartMinorSplitLine { border-color: #FF0000;'
    + ' border-width: 1px; } TyAdvChartSplitLine { border-color: #FFFFFF; }';
  Draw('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 100, minorTick: { show: true } },'
    + ' series: [] }');
  r := Grid.PlotRect;
  AssertEquals('the marks were asked for, the grid was not', 0,
    RedRunsDown(Round(r.Left) + 20, Round(r.Top) + 2, Round(r.Bottom) - 2));
end;

procedure TAdvChartFurnitureTest.TestTheEndSplitLinesAreSeparatelyDeniable;
var r: TTyRectF; all_, noMax, noMin: Integer;
begin
  { A grid line on the axis' own extreme sits exactly on the plot's edge and
    doubles whatever border is already there. The two ends are denied
    separately, and each must cost exactly one line -- denying `max` and
    getting the `min` one back would satisfy a count of `one fewer`. }
  FCtl.StyleOverride := cRedSplitLine;
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' splitLine: { show: true } },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  r := Grid.PlotRect;
  all_ := RedRunsAcross(Round(r.Top) + 6, Round(r.Left) - 2,
                        Round(r.Right) + 2);
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' splitLine: { show: true, showMaxLine: false } },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  noMax := RedRunsAcross(Round(r.Top) + 6, Round(r.Left) - 2,
                         Round(r.Right) + 2);
  Draw('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''],'
    + ' splitLine: { show: true, showMinLine: false } },'
    + ' yAxis: { min: 0, max: 100 }, series: [] }');
  noMin := RedRunsAcross(Round(r.Top) + 6, Round(r.Left) - 2,
                         Round(r.Right) + 2);
  AssertEquals('five band edges, all drawn', 5, all_);
  AssertEquals('without the last one', 4, noMax);
  AssertEquals('without the first one', 4, noMin);
end;

procedure TAdvChartFurnitureTest.TestARotatedLabelIsActuallyTurned;

  { The height of the dark ink below ABottom: one line of text when the labels
    lie down, their own length when they stand up. }
  function InkHeightBelow(const APlot: TTyRectF;
    const AGround: TBGRAPixel): Integer;
  var x, y, lo, hi: Integer; p, ground: TBGRAPixel;
  begin
    lo := MaxInt;
    hi := -1;
    { RELATIVE TO THE SURFACE, not to a fixed darkness. The theme draws axis
      labels at `alpha(--on-surface, .5)`, so a glyph's core is half way to
      the surface colour and its antialiased edge is less than that -- an
      absolute threshold either finds nothing or finds the whole page,
      depending on the skin.

      AND THE GROUND COMES FROM INSIDE THE PLOT, handed in. Sampled near the
      control's own left edge it landed on the sentinel the bitmap was filled
      with, outside the rounded frame -- so every surface pixel differed from
      it and the whole band below the axis read as ink: 91 px of `text`. }
    ground := AGround;
    { INSIDE THE PLOT'S OWN COLUMN, and stopping short of the control's edge.
      DrawFrame strokes a rounded border round the whole control and leaves
      the bitmap's sentinel showing outside the curve at the corners -- both
      are ink by any measure, and scanning the full width reported the same
      eighty-four pixels of `text` whichever way the labels were turned. The
      labels sit on the band centres, so the plot's own span holds all of
      them and none of the frame. }
    for y := Round(APlot.Bottom) + 6 to FBmp.Height - 8 do
      for x := Round(APlot.Left) to Round(APlot.Right) do
      begin
        p := FBmp.GetPixel(x, y);
        if Abs(p.red - ground.red) + Abs(p.green - ground.green)
           + Abs(p.blue - ground.blue) > 40 then
        begin
          if y < lo then lo := y;
          if y > hi then hi := y;
          Break;
        end;
      end;
    if hi < 0 then Result := 0 else Result := hi - lo + 1;
  end;

var flat, turned: Integer; r: TTyRectF;
begin
  { MEASURED AS THE INK'S HEIGHT, which is the one thing a quarter turn changes
    past all doubt: `Wednesday` lying down is one line of text tall and standing
    up is its own length tall. The layout has measured the turned extent since
    item 12 and nothing ever drew the turn, so the option bought a deeper gutter
    and put flat text in it -- and no assertion about the plot rectangle could
    tell the difference. }
  Draw('{ xAxis: { data: [''Wednesday'', ''Thursday''] },'
    + ' yAxis: { min: 0, max: 10 }, series: [] }');
  r := Grid.PlotRect;
  flat := InkHeightBelow(r,
    FBmp.GetPixel(Round(r.Left) + 5, Round(r.Top) + 5));
  Draw('{ xAxis: { data: [''Wednesday'', ''Thursday''],'
    + ' axisLabel: { rotate: 90 } },'
    + ' yAxis: { min: 0, max: 10 }, series: [] }');
  r := Grid.PlotRect;
  turned := InkHeightBelow(r,
    FBmp.GetPixel(Round(r.Left) + 5, Round(r.Top) + 5));
  AssertTrue(Format('flat text is one line tall, and is %d px', [flat]),
    (flat > 5) and (flat < 25));
  AssertTrue(Format('turned text should be its own length tall, and is %d',
    [turned]), turned > flat * 2);
end;

procedure TAdvChartFurnitureTest.TestATopAxisTurnsItsLabelsTheOtherWay;
var bottom, top_: Double;
begin
  { Upstream negates `rotate` for `position: top` and for nothing else, so
    that a slant leans AWAY from the plot on both edges instead of into it on
    one of them. Asserted as the two angles rather than in ink: at forty-five
    degrees the two turns differ by a lean, and a pixel probe that could tell
    them apart would be measuring the font more than the option.

    Opposite signs and equal magnitudes, both asserted -- `-x` and `0` are
    also opposite in the only sense a sign test can see. }
  Draw('{ xAxis: { data: [''A'', ''B''], axisLabel: { rotate: 45 } },'
    + ' yAxis: { min: 0, max: 10 }, series: [] }');
  bottom := Grid.SpecFor(Grid.XAxis(0))^.RotationRad;
  Draw('{ xAxis: { data: [''A'', ''B''], position: ''top'','
    + ' axisLabel: { rotate: 45 } },'
    + ' yAxis: { min: 0, max: 10 }, series: [] }');
  top_ := Grid.SpecFor(Grid.XAxis(0))^.RotationRad;
  AssertEquals('a bottom axis turns counter-clockwise, as written',
    Pi / 4, bottom, 1e-6);
  AssertEquals('and a top axis turns the other way', -Pi / 4, top_, 1e-6);
end;

procedure TAdvChartFurnitureTest.TestAHiddenAxisGivesItsGutterBack;
var shown, hidden, labelsOff: TTyRectF;
begin
  { `yAxis: { show: false }` used to stop DRAWING the numbers and go on
    reserving room for them -- a chart with an empty margin down its left-hand
    side and no way to close it. Upstream builds nothing at all for a hidden
    axis and skips it again when it folds the shrink.

    Three ways: hiding the AXIS gives back exactly what hiding everything it
    draws gives back, and that is more than twenty pixels of numbers. }
  shown := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 10000 },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  labelsOff := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 10000, axisLabel: { show: false } },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  hidden := PlotOf('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 10000, show: false },'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertTrue(Format('a hidden axis costs no gutter (shown %.1f, hidden %.1f)',
    [shown.Left, hidden.Left]), shown.Left - hidden.Left > 20);
  AssertEquals('which is what hiding everything it draws gives back',
    labelsOff.Left, hidden.Left, Eps);
end;

initialization
  RegisterTest(TAdvChartFurnitureTest);
end.
