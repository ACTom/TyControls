unit test.advchart.multiaxis;
{$mode objfpc}{$H+}
{ Where an axis sits when it is not simply on the edge.

  Two options decide it and they are not alternatives -- an axis can have both.
  `offset` pushes an axis AWAY from the plot, which is how two axes on one side
  are separated; upstream draws them both on the edge otherwise. `axisLine.
  onZero` puts the line on the other family's zero instead, and it is on by
  DEFAULT, so a bar chart with negative values has its category axis through
  the middle without anybody asking.

  The two interact in one direction only: under onZero the offset stops moving
  the LINE (it only widens the clamp the zero is caught by) and goes on moving
  the labels. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Coord, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Layout,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartMultiAxisTest = class(TTestCase)
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
    { The x of each vertical red run along a row, left to right. }
    function RedColumns(AY, AL, AR: Integer): TTyDoubleArray;
    { The y of each horizontal red run down a column. }
    function RedRows(AX, AT, AB: Integer): TTyDoubleArray;
    function PlotOf(const AOption: string): TTyRectF;
  published
    procedure TestAnOffsetPushesTheAxisAwayFromThePlot;
    procedure TestAnOffsetAxisReservesTheRoomItNeeds;
    procedure TestAHorizontalAxisTakesItsOffsetToo;
    procedure TestTwoAxesOnOneSideAreSeparatedByOffset;
    procedure TestACategoryAxisSitsOnItsNeighboursZero;
    procedure TestTheLabelsDoNotFollowTheLineToZero;
    procedure TestOnZeroCanBeTurnedOff;
    procedure TestACategoryAxisNeverProvidesAZero;
    procedure TestTwoAxesCannotBothClaimOneZero;
    procedure TestOnZeroAxisIndexNamesTheProvider;
    procedure TestTheGridNeverPaintsOverAnAxisLine;
    procedure TestUnderOnZeroTheOffsetMovesNothing;
  end;

implementation

const
  { The axis line, overridden opaque so a run-length scan can count it. The
    theme draws it at the border colour, which a skin is free to make faint. }
  cRedAxis = 'TyAdvChartAxisLine { border-color: #FF0000; border-width: 1px; }';
  Eps = 1.5;

procedure TAdvChartMultiAxisTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartMultiAxisTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartMultiAxisTest.Draw(const AOption: string;
  AW, AH, APPI: Integer);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 0, 255, 255));
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, AW, AH), APPI);
end;

function TAdvChartMultiAxisTest.Grid: TTyGridBuild;
begin
  Result := FChart.Build.Grid(0);
end;

function TAdvChartMultiAxisTest.PlotOf(const AOption: string): TTyRectF;
begin
  Draw(AOption);
  Result := Grid.PlotRect;
end;

function TAdvChartMultiAxisTest.RedColumns(AY, AL, AR: Integer): TTyDoubleArray;
var x: Integer; p: TBGRAPixel; inRun: Boolean;
begin
  Result := nil;
  inRun := False;
  for x := AL to AR do
  begin
    p := FBmp.GetPixel(x, AY);
    if p.red > p.green + 40 then
    begin
      if not inRun then
      begin
        inRun := True;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := x;
      end;
    end
    else
      inRun := False;
  end;
end;

function TAdvChartMultiAxisTest.RedRows(AX, AT, AB: Integer): TTyDoubleArray;
var y: Integer; p: TBGRAPixel; inRun: Boolean;
begin
  Result := nil;
  inRun := False;
  for y := AT to AB do
  begin
    p := FBmp.GetPixel(AX, y);
    if p.red > p.green + 40 then
    begin
      if not inRun then
      begin
        inRun := True;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := y;
      end;
    end
    else
      inRun := False;
  end;
end;

{ ==================== offset ==================== }

procedure TAdvChartMultiAxisTest.TestAnOffsetPushesTheAxisAwayFromThePlot;
var r: TTyRectF; cols: TTyDoubleArray;
begin
  { AWAY, NOT LEFT. The sign is by SIDE and not by screen direction: a left
    axis goes to `left - offset` and a right one to `right + offset`. Both are
    asserted, because a port that simply subtracted would pass the first and
    put the right-hand axis inside the plot.

    A scatter, so both value axes draw their lines -- and both onZero off, so
    the only thing moving them is the offset. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: { axisLine: { onZero: false } },'
    + ' yAxis: [{ offset: 30, axisLine: { onZero: false } },'
    + ' { position: ''right'', offset: 20, axisLine: { onZero: false } }],'
    + ' series: [{ type: ''scatter'', data: [[1, 2], [3, 4]] }] }');
  r := Grid.PlotRect;
  cols := RedColumns(Round((r.Top + r.Bottom) / 2),
                     Round(r.Left) - 60, Round(r.Right) + 60);
  AssertEquals('two y axis lines', 2, Length(cols));
  AssertEquals('the left one is thirty px outside the plot',
    r.Left - 30, cols[0], Eps);
  AssertEquals('and the right one twenty px outside the other edge',
    r.Right + 20, cols[1], Eps);
end;

procedure TAdvChartMultiAxisTest.TestAnOffsetAxisReservesTheRoomItNeeds;
var near_, far_: TTyRectF;
begin
  { An axis that hangs further out needs a wider band, or its labels fall off
    the control. Upstream reaches the same place by a different route -- it
    builds the labels AT the offset position and then shrinks the grid by
    however far they overflow the canvas. }
  { Against the canvas' left edge, where both sets of labels overflow and
    the offset is the whole difference. At the default grid upstream gives
    up only the few pixels by which the offset labels pass the canvas.
    [Revised in batch 37: the offset was reserved inside the grid always.] }
  near_ := PlotOf('{ grid: { left: 0 }, xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''scatter'', data: [[1, 2]] }] }');
  far_ := PlotOf('{ grid: { left: 0 }, xAxis: {}, yAxis: { offset: 40 },'
    + ' series: [{ type: ''scatter'', data: [[1, 2]] }] }');
  AssertEquals('exactly the offset, given up by the plot',
    40.0, far_.Left - near_.Left, Eps);
end;

procedure TAdvChartMultiAxisTest.TestAHorizontalAxisTakesItsOffsetToo;
var r: TTyRectF; rows: TTyDoubleArray;
begin
  { THE SAME RULE ON THE OTHER PAIR OF SIDES. Every other offset test here
    is on a y axis, and a port that reached for the plot's left and right
    whatever the axis' family would pass all of them -- an x axis would
    simply never move. onZero off, so the offset is the only thing
    positioning it. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: { data: [''A'', ''B''],'
    + ' axisLine: { onZero: false }, offset: 30 },'
    + ' yAxis: { min: -10, max: 10 },'
    + ' series: [{ type: ''bar'', data: [5, -5] }] }');
  r := Grid.PlotRect;
  rows := RedRows(Round(r.Left) + 2, Round(r.Top), FBmp.Height - 1);
  AssertEquals('one x axis line', 1, Length(rows));
  AssertEquals('thirty px BELOW the plot -- away, not up',
    r.Bottom + 30, rows[0], Eps + 1);
end;

procedure TAdvChartMultiAxisTest.TestTwoAxesOnOneSideAreSeparatedByOffset;
var r: TTyRectF; cols: TTyDoubleArray;
begin
  { THIS IS WHAT OFFSET IS FOR. Two y axes both written `left` sit on the same
    edge -- upstream draws them on top of each other and expects the author to
    separate them, and separating them is the only thing offset does. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: { axisLine: { onZero: false } },'
    + ' yAxis: [{ position: ''left'', axisLine: { onZero: false } },'
    + ' { position: ''left'', offset: 45, axisLine: { onZero: false } }],'
    + ' series: [{ type: ''scatter'', data: [[1, 2]] }] }');
  r := Grid.PlotRect;
  cols := RedColumns(Round((r.Top + r.Bottom) / 2),
                     Round(r.Left) - 70, Round(r.Right));
  AssertEquals('two distinct lines', 2, Length(cols));
  AssertEquals('forty-five px apart', 45.0, cols[1] - cols[0], Eps);
end;

{ ==================== onZero ==================== }

procedure TAdvChartMultiAxisTest.TestACategoryAxisSitsOnItsNeighboursZero;
var r: TTyRectF; rows: TTyDoubleArray; zeroY: Double;
begin
  { ON BY DEFAULT, and this is the chart everybody has seen: bars with negative
    values, the category axis through the middle rather than along the bottom.

    The ASKER may be a category axis -- it is the PROVIDER that may not be.
    Here the provider is the value y, whose extent straddles zero. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: { min: -10, max: 10 },'
    + ' series: [{ type: ''bar'', data: [5, -5, 5] }] }');
  r := Grid.PlotRect;
  zeroY := (r.Top + r.Bottom) / 2;
  { Left of the first bar, so only the axis line is in the column. }
  rows := RedRows(Round(r.Left) + 2, Round(r.Top), Round(r.Bottom));
  AssertEquals('one x axis line', 1, Length(rows));
  AssertEquals('and it is at zero, halfway up', zeroY, rows[0], Eps + 1);
end;

procedure TAdvChartMultiAxisTest.TestTheLabelsDoNotFollowTheLineToZero;
var r: TTyRectF; y, x, lowest: Integer; p, ground: TBGRAPixel;
begin
  { THE LINE MOVES AND THE WORDS DO NOT. Upstream carries a `labelOffset` back
    to the raw edge for exactly this, and it is the difference between a chart
    that reads and one whose category names are buried in its own bars.

    Counted as the LOWEST row of dark ink below the plot: if the labels had
    followed the line there would be none at all down there. }
  Draw('{ xAxis: { data: [''Mon'', ''Tue'', ''Wed''] },'
    + ' yAxis: { min: -10, max: 10 },'
    + ' series: [{ type: ''bar'', data: [5, -5, 5] }] }');
  r := Grid.PlotRect;
  ground := FBmp.GetPixel(Round(r.Left) + 5, Round(r.Top) + 5);
  lowest := -1;
  for y := Round(r.Bottom) + 4 to FBmp.Height - 10 do
    for x := Round(r.Left) to Round(r.Right) do
    begin
      p := FBmp.GetPixel(x, y);
      if (Abs(p.red - ground.red) + Abs(p.green - ground.green)
          + Abs(p.blue - ground.blue)) > 40 then
      begin
        lowest := y;
        Break;
      end;
    end;
  AssertTrue('the category names are still below the plot', lowest > 0);
end;

procedure TAdvChartMultiAxisTest.TestOnZeroCanBeTurnedOff;
var r: TTyRectF; rows: TTyDoubleArray;
begin
  { `auto` is truthy, so only a written FALSE turns it off -- and then the line
    goes back to the edge its position names. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: { data: [''A'', ''B''], axisLine: { onZero: false } },'
    + ' yAxis: { min: -10, max: 10 },'
    + ' series: [{ type: ''bar'', data: [5, -5] }] }');
  r := Grid.PlotRect;
  rows := RedRows(Round(r.Left) + 2, Round(r.Top), Round(r.Bottom));
  AssertEquals('one x axis line', 1, Length(rows));
  AssertEquals('back on the bottom edge', r.Bottom, rows[0], Eps + 1);
end;

procedure TAdvChartMultiAxisTest.TestACategoryAxisNeverProvidesAZero;
var r: TTyRectF; cols: TTyDoubleArray;
begin
  { A CATEGORY AXIS IS NEVER THE PROVIDER, however plainly its band contains
    the coordinate zero -- upstream calls the rule historical and keeps it. So
    a value y beside a category x stays on its own edge.

    Its own line has to be asked for: against a category x, `axisLine.show`
    resolves to no. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: -10, max: 10, axisLine: { show: true } },'
    + ' series: [{ type: ''bar'', data: [5, -5] }] }');
  r := Grid.PlotRect;
  cols := RedColumns(Round(r.Top) + 6, Round(r.Left) - 20, Round(r.Right));
  AssertEquals('one y axis line', 1, Length(cols));
  AssertEquals('on the left edge, not anywhere near a category''s zero',
    r.Left, cols[0], Eps);
end;

procedure TAdvChartMultiAxisTest.TestTwoAxesCannotBothClaimOneZero;
var r: TTyRectF; rows: TTyDoubleArray;
begin
  { Two x axes both asking, one value y that can answer. If both were given it
    they would draw on top of each other, which is the comment upstream leaves
    beside the same test -- so the SECOND is refused and falls back to its own
    edge. One line at zero and one at the top: two distinct rows. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: [{}, { position: ''top'' }],'
    + ' yAxis: { min: -10, max: 10 },'
    + ' series: [{ type: ''scatter'', data: [[1, 5], [3, -5]] }] }');
  r := Grid.PlotRect;
  rows := RedRows(Round((r.Left + r.Right) / 2) + 17,
                  Round(r.Top), Round(r.Bottom));
  AssertEquals('two x axis lines, in two places', 2, Length(rows));
  AssertTrue(Format('and they are far apart (%.0f and %.0f)',
    [rows[0], rows[1]]), rows[1] - rows[0] > 20);
end;

procedure TAdvChartMultiAxisTest.TestOnZeroAxisIndexNamesTheProvider;
var r: TTyRectF; want: Double;
begin
  { Two y axes with different extents. Left to itself the x axis takes the
    FIRST that qualifies; named, it takes the one it was told. The two zeros
    are deliberately at different heights, so `it ignored the index` and `it
    honoured it` cannot look the same.

    ASKED OF THE BUILD RATHER THAN OF THE PIXELS. Which axis provides a zero
    is arithmetic, and the pixel probes in this file are for the things only
    a render can answer -- where a line ended up relative to its labels, or
    whether two lines are distinct. }
  Draw('{ xAxis: { axisLine: { onZeroAxisIndex: 1 } },'
    + ' yAxis: [{ min: -10, max: 10 }, { min: -30, max: 10 }],'
    + ' series: [{ type: ''scatter'', data: [[1, 2], [3, 4]] }] }');
  r := Grid.PlotRect;
  { The second axis runs -30..10, so its zero is a quarter of the way DOWN
    from the top; the first one's is halfway. }
  want := r.Top + (r.Bottom - r.Top) * 10 / 40;
  AssertEquals('the named axis provides the zero',
    want, Grid.AxisLineCoord(Grid.XAxis(0), 96), Eps);

  { And with nobody named, the FIRST that qualifies does. }
  Draw('{ xAxis: {},'
    + ' yAxis: [{ min: -10, max: 10 }, { min: -30, max: 10 }],'
    + ' series: [{ type: ''scatter'', data: [[1, 2], [3, 4]] }] }');
  r := Grid.PlotRect;
  AssertEquals('which is the first axis'' zero, halfway up',
    (r.Top + r.Bottom) / 2, Grid.AxisLineCoord(Grid.XAxis(0), 96), Eps);

  { An index naming an axis that cannot provide one turns onZero OFF rather
    than falling back to the scan -- upstream's `else` belongs to the
    `if (onZeroAxisIndex != null)`. Index 1 here is a CATEGORY axis. }
  Draw('{ xAxis: { axisLine: { onZeroAxisIndex: 1 } },'
    + ' yAxis: [{ min: -10, max: 10 }, { data: [''p'', ''q''] }],'
    + ' series: [{ type: ''scatter'', data: [[1, 2], [3, 4]] }] }');
  r := Grid.PlotRect;
  AssertEquals('a named axis that cannot answer leaves the line on its edge',
    r.Bottom, Grid.AxisLineCoord(Grid.XAxis(0), 96), Eps);
end;

procedure TAdvChartMultiAxisTest.TestUnderOnZeroTheOffsetMovesNothing;
var r: TTyRectF; rows: TTyDoubleArray;
begin
  { The two options do not add up. When an axis is on zero, its offset only
    widens the range the zero is clamped into -- and a zero already inside the
    plot is nowhere near either end of it, so the line does not move off zero.

    ASSERTED AGAINST THE PLOT, not against the other render. An offset DOES
    change the plot rectangle -- it costs a wider band -- so the line's
    absolute position legitimately differs between the two charts; what must
    not differ is that it is at the CURRENT plot's zero. With -10..10 that is
    the vertical middle, whatever the rectangle turns out to be. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: { data: [''A'', ''B''] }, yAxis: { min: -10, max: 10 },'
    + ' series: [{ type: ''bar'', data: [5, -5] }] }');
  r := Grid.PlotRect;
  rows := RedRows(Round(r.Left) + 2, Round(r.Top) - 40, Round(r.Bottom) + 40);
  AssertEquals('one line', 1, Length(rows));
  AssertEquals('at the middle', (r.Top + r.Bottom) / 2, rows[0], Eps + 1);

  Draw('{ xAxis: { data: [''A'', ''B''], offset: 25 },'
    + ' yAxis: { min: -10, max: 10 },'
    + ' series: [{ type: ''bar'', data: [5, -5] }] }');
  r := Grid.PlotRect;
  rows := RedRows(Round(r.Left) + 2, Round(r.Top) - 40, Round(r.Bottom) + 40);
  AssertEquals('still one line', 1, Length(rows));
  AssertEquals('and still at the middle -- the offset moved the band, not it',
    (r.Top + r.Bottom) / 2, rows[0], Eps + 1);
  AssertTrue('while the band it cost is real',
    r.Bottom < 300 - 25);
end;

procedure TAdvChartMultiAxisTest.TestTheGridNeverPaintsOverAnAxisLine;
var
  r: TTyRectF; rows: TTyDoubleArray; want: Double;
  ticks: TTyScaleTickArray; col: Integer;
begin
  { ALL THE GRID BELOW ALL THE AXES. Upstream keeps them apart by z; the
    port used to draw one axis' grid AND line before starting the next, and
    with two y axes that is visibly wrong -- the second y axis' split line
    lands on the FIRST one's zero, which is exactly where onZero has just
    put the x axis line, and rubs it out.

    Two y axes whose zeros coincide, so the collision is certain rather
    than lucky, and the line looked for is the one that was being lost. }
  FCtl.StyleOverride := cRedAxis;
  Draw('{ xAxis: {},'
    + ' yAxis: [{ min: -10, max: 10 }, { min: -20, max: 20 }],'
    + ' series: [{ type: ''scatter'', data: [[1, 2], [3, 4]] }] }');
  r := Grid.PlotRect;
  want := (r.Top + r.Bottom) / 2;
  { A column HALFWAY BETWEEN TWO X TICKS, so neither y axis' own line is in
    it -- and nor is an x tick, whose mark starts on the axis line and is
    drawn over it, as upstream draws it. (The plot's middle was used here
    until batch 33 gave the x axis a tick at 1.5; it failed only after some
    earlier suite had brought the widgetset up, because that moved the plot
    by three pixels and put the tick's first row exactly on the line's.) }
  ticks := Grid.XAxis(0).Scale.GetTicks;
  AssertTrue('the x axis has ticks to go between', Length(ticks) >= 3);
  col := Round(Grid.XAxis(0).DataToCoord((ticks[1].Value + ticks[2].Value) / 2));
  rows := RedRows(col, Round(r.Top), Round(r.Bottom));
  AssertEquals('the x axis line survives the grid drawn after it',
    1, Length(rows));
  AssertEquals('and is still on zero', want, rows[0], Eps + 1);
end;

initialization
  RegisterTest(TAdvChartMultiAxisTest);
end.
