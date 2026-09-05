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
     tyControls.AdvanceChart;
type
  { Re-exposes the protected render so a test can drive it onto a bitmap. }
  TChartProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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
    procedure TestCategoriesCollectedFromSeriesDataReachTheAxis;
    procedure TestAnUnnaturalIntervalIsNotRoundedAway;
    procedure TestACrowdedAxisThinsItsLabels;
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
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [10, 20, 30] }] }';
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
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C'', ''D''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2, 3, 4] }] }';
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
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [10, 20, 30] }] }';
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
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [10, 20, 30] }] }';
  Draw;
  bg := PixelAt(200, 150);
  inkShown := PlotInk;
  AssertTrue('the visible chart drew something in the plot', inkShown > 50);

  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C''], show: false },'
    + ' yAxis: { show: false },'
    + ' series: [{ type: ''bar'', data: [10, 20, 30] }] }';
  Draw;
  bg := PixelAt(200, 150);
  inkHidden := PlotInk;
  AssertEquals(Format('both axes are hidden but %d pixels are still drawn '
    + 'inside the plot', [inkHidden]), 0, inkHidden);
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
  FChart.Option := '{ xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [30] }] }';
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
  FChart.Option := '{ xAxis: { data: [''A'', ''B'', ''C'', ''D''] },'
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

initialization
  RegisterTest(TAdvanceChartTest);
end.
