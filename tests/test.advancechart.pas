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
  published
    procedure TestItHasItsOwnStyleKey;
    procedure TestAnEmptyChartStillPaintsItsSurface;
    procedure TestEveryCornerIsPainted;
    procedure TestTheOptionDrivesTheBuild;
    procedure TestABadOptionKeepsTheLastGoodOne;
    procedure TestDiagnosticsReachTheControl;
    procedure TestAnAxisIsActuallyDrawn;
    procedure TestAValueAxisLabelsItsTicks;
    procedure TestSplitLinesDivideBandsRatherThanPointAtLabels;
    procedure TestTheTicksThemselvesAreDrawn;
    procedure TestAHiddenAxisIsNotDrawn;
    procedure TestResizingRelaysOutTheAxes;
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

procedure TAdvanceChartTest.TestABadOptionKeepsTheLastGoodOne;
begin
  { A design-time editor renders on every keystroke, so half-typed text is the
    normal state. Blanking the chart on each one would make the editor
    unusable. }
  FChart.Option := '{ xAxis: { data: [''A'', ''B''] }, yAxis: {} }';
  Draw;
  AssertEquals(2, FChart.Build.Axis('xAxis', 0).Categories.Count);
  FChart.Option := '{ xAxis: { data: [''A'',';
  Draw;
  AssertTrue('the error is readable', FChart.OptionError <> '');
  AssertEquals('and the last good option still stands', 2,
    FChart.Build.Axis('xAxis', 0).Categories.Count);
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
  for x := left to right do
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

initialization
  RegisterTest(TAdvanceChartTest);
end.
