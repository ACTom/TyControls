unit test.advchart.candlestick;
{$mode objfpc}{$H+}
{ The fourth renderer, and the substrate it needed.

  A CANDLESTICK IS FOUR NUMBERS ON ONE AXIS, which the store could not hold. It
  was built one column per coordinate -- `x` and `y` -- so a candlestick's item
  lost three of its four values, the value axis sized itself from the closes
  alone, and the renderer found no columns to read and drew nothing. Upstream
  models a coordinate as a LIST of data dimensions (`mapDimensionsAll`), and
  that is what the store learned here.

  AND THE CATEGORY IS NOWHERE IN THE ROW. All four elements are values, so the
  base axis counts rows instead -- which the store-wide "the items are not
  arrays" guess cannot express, because a candlestick's always are. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     fpjson, jsonparser,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Option, tyControls.AdvChart.Marks,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Scale, tyControls.AdvChart.AnimAxis,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartCandleRuleTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    procedure TearDown; override;
    function SpecOf(const AText: string): TTyCandleSpec;
  published
    procedure TestOneCoordinateCanHaveSeveralColumns;
    procedure TestAnUnmappedStoreAnswersTheColumnOfThatName;
    procedure TestTheFourColoursAreRead;
    procedure TestABorderFollowsItsBodyUnlessWritten;
    procedure TestNoneIsAColourAndNotAnAbsence;
  end;

  TAdvChartCandleDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    function CentreColour(ACat: Integer; AValue: Double): TBGRAPixel;
    function WickColour(ACat: Integer; AValue: Double): TBGRAPixel;
    function Diagnostics: string;
  published
    procedure TestARisingCandleAndAFallingOneAreDifferentColours;
    procedure TestADojiTakesTheDirectionOfTheMoveIntoIt;
    procedure TestTheFirstRowHasNoPreviousAndIsUp;
    procedure TestTheValueAxisSpansEveryOneOfTheFourColumns;
    procedure TestTheBodyIsHalfABandWide;
    procedure TestATypeWithNoRendererSaysSo;
    procedure TestATypeWithARendererDoesNot;
  end;

implementation

const
  cW = 640;
  cH = 360;
  { FOUR ROWS CHOSEN SO THAT EVERY BRANCH OF THE SIGN RULE IS REACHED, and so
    that the doji branch cannot be mistaken for a constant.

      0  [10,30,..]  open below close        -> UP,   closes at 30
      1  [10,10,..]  a DOJI after a close of 30, so previous > its own close
                                             -> DOWN
      2  [30, 5,..]  open above close        -> DOWN, closes at 5
      3  [10,10,..]  a DOJI after a close of 5, so previous <= its own close
                                             -> UP

    The two dojis point OPPOSITE WAYS on identical numbers. A fixture whose
    every doji happened to be up -- which the first version of this one was --
    reads the same against "look at the row before" and against "always up",
    and a mutant that deleted the comparison lived through it. }
  cMixed =
    '{"tooltip":{"show":false},' +
    '"xAxis":{"type":"category","data":["a","b","c","d"]},' +
    '"yAxis":{"type":"value","min":0,"max":40},' +
    '"series":[{"type":"candlestick","name":"D","data":[' +
    '[10,30,5,35],[10,10,5,35],[30,5,1,35],[10,10,1,35]]}]}';

{ ==================== the rules ==================== }

procedure TAdvChartCandleRuleTest.TearDown;
begin
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartCandleRuleTest.SpecOf(const AText: string): TTyCandleSpec;
var d: TTyCandleSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses', FOpt.SetOptionText(AText));
  d := Default(TTyCandleSpec);
  d.Up := $FF111111;
  d.Down := $FF222222;
  d.UpBorder := $FF111111;
  d.DownBorder := $FF222222;
  d.BorderWidthLogical := 1;
  Result := TyCandleSpecOf(FOpt, 0, d);
end;

procedure TAdvChartCandleRuleTest.TestOneCoordinateCanHaveSeveralColumns;
var
  st: TTyDataStore;
  cols: TTyIntegerArray;
begin
  { THE SUBSTRATE THE RENDERER NEEDED. Upstream's `mapDimensionsAll` answers a
    LIST because a candlestick puts four data dimensions on one coordinate and
    a boxplot five; the port had only a lookup by name, which can answer with
    one column and therefore sized such an axis from a quarter of its data. }
  st := TTyDataStore.Create;
  try
    st.AddDimension('x', ddtFloat);
    st.AddDimension('open', ddtFloat);
    st.AddDimension('close', ddtFloat);
    st.SetDimCoord(1, 'y');
    st.SetDimCoord(2, 'y');
    cols := st.DimsOfCoord('y');
    AssertEquals('both', 2, Length(cols));
    AssertEquals(1, cols[0]);
    AssertEquals(2, cols[1]);
  finally
    st.Free;
  end;
end;

procedure TAdvChartCandleRuleTest.TestAnUnmappedStoreAnswersTheColumnOfThatName;
var
  st: TTyDataStore;
  cols: TTyIntegerArray;
begin
  { EVERY STORE THE PORT BUILT BEFORE THIS EXISTED maps nothing, so the
    fallback is not a nicety -- it is what keeps every other series answering
    exactly what DimIndexOf answered, and keeps the caller from having to ask
    which kind of store it is holding. }
  st := TTyDataStore.Create;
  try
    st.AddDimension('x', ddtFloat);
    st.AddDimension('y', ddtFloat);
    cols := st.DimsOfCoord('y');
    AssertEquals('the one of that name', 1, Length(cols));
    AssertEquals(1, cols[0]);
    AssertEquals('and nothing for a coordinate nobody has', 0,
                 Length(st.DimsOfCoord('z')));
  finally
    st.Free;
  end;
end;

procedure TAdvChartCandleRuleTest.TestTheFourColoursAreRead;
var s: TTyCandleSpec;
begin
  s := SpecOf('{"series":[{"type":"candlestick","itemStyle":{' +
              '"color":"#ff0000","color0":"#00ff00",' +
              '"borderColor":"#0000ff","borderColor0":"#ffff00",' +
              '"borderWidth":3}}]}');
  AssertEquals('up', Integer($FFFF0000), Integer(s.Up));
  AssertEquals('down', Integer($FF00FF00), Integer(s.Down));
  AssertEquals('up border', Integer($FF0000FF), Integer(s.UpBorder));
  AssertEquals('down border', Integer($FFFFFF00), Integer(s.DownBorder));
  AssertEquals('the pen', 3.0, s.BorderWidthLogical, 1e-9);
end;

procedure TAdvChartCandleRuleTest.TestABorderFollowsItsBodyUnlessWritten;
var s: TTyCandleSpec;
begin
  { UPSTREAM'S TWO BORDER DEFAULTS ARE THE SAME PAIR OF COLOURS WRITTEN TWICE,
    so an author who recolours the bodies and not the borders gets a candle
    that matches rather than one outlined in the theme's colours. }
  s := SpecOf('{"series":[{"type":"candlestick","itemStyle":{' +
              '"color":"#ff0000","color0":"#00ff00"}}]}');
  AssertEquals('the up border took the up body', Integer($FFFF0000),
               Integer(s.UpBorder));
  AssertEquals('and the down border the down body', Integer($FF00FF00),
               Integer(s.DownBorder));
  { And a written one is not overruled by the body beside it. }
  s := SpecOf('{"series":[{"type":"candlestick","itemStyle":{' +
              '"color":"#ff0000","borderColor":"#000000"}}]}');
  AssertEquals(Integer($FF000000), Integer(s.UpBorder));
end;

procedure TAdvChartCandleRuleTest.TestNoneIsAColourAndNotAnAbsence;
var s: TTyCandleSpec;
begin
  { `'none'` IS AN INSTRUCTION -- draw nothing -- and leaving the theme's
    colour standing would be reading it as "I said nothing". }
  s := SpecOf('{"series":[{"type":"candlestick",' +
              '"itemStyle":{"color":"none"}}]}');
  AssertEquals('a hollow up candle', 0, Integer(s.Up));
end;

{ ==================== the picture ==================== }

procedure TAdvChartCandleDrawTest.SetUp;
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

procedure TAdvChartCandleDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartCandleDrawTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartCandleDrawTest.CentreColour(ACat: Integer;
  AValue: Double): TBGRAPixel;
var g: TTyGridBuild;
begin
  g := FChart.Build.Grid(0);
  Result := FBmp.GetPixel(Round(g.XAxis(0).DataToCoord(ACat)),
                          Round(g.YAxis(0).DataToCoord(AValue)));
end;

{ THE WICK'S PIXEL: the spine is snapped to the half pixel, so a one-pixel
  pen covers the column under it whole. [Batch 108: a doji's body is a line
  of no height now, stroked where its value falls -- off the pixel grid, and
  so half on each of two rows. Its direction is read off its wick.] }
function TAdvChartCandleDrawTest.WickColour(ACat: Integer;
  AValue: Double): TBGRAPixel;
var g: TTyGridBuild;
begin
  g := FChart.Build.Grid(0);
  Result := FBmp.GetPixel(Floor(TySubPixelOptimize(g.XAxis(0).DataToCoord(ACat), 1, False)),
                          Round(g.YAxis(0).DataToCoord(AValue)));
end;

function TAdvChartCandleDrawTest.Diagnostics: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    Result := Result + FChart.Diagnostic(i) + '|';
end;

procedure TAdvChartCandleDrawTest.TestARisingCandleAndAFallingOneAreDifferentColours;
var up, down: TBGRAPixel;
begin
  Draw(cMixed);
  { Mid-body on each, which is inside whichever of open and close is lower and
    whichever is higher -- 20 is between 10 and 30 either way round. }
  up := CentreColour(0, 20);
  down := CentreColour(2, 20);
  AssertTrue('the rising candle is drawn', up.alpha > 0);
  AssertTrue('and the falling one', down.alpha > 0);
  { NOT "POSITIVE AND NEGATIVE" however they are usually described: both
    compare a datum against ITSELF, and either can happen in a rising market.
    What the test can say is that they differ. }
  AssertTrue(Format('and the two differ (%d,%d,%d vs %d,%d,%d)',
                    [up.red, up.green, up.blue,
                     down.red, down.green, down.blue]),
             (up.red <> down.red) or (up.green <> down.green)
             or (up.blue <> down.blue));
end;

procedure TAdvChartCandleDrawTest.TestADojiTakesTheDirectionOfTheMoveIntoIt;
var rose, fell, dojiDown, dojiUp: TBGRAPixel;
begin
  { OPEN EXACTLY EQUAL TO CLOSE is a real and frequent reading, not a rounding
    accident, and upstream resolves it against the PREVIOUS row's close -- so a
    flat bar takes the direction of the move that led into it.

    THE TWO DOJIS HERE CARRY IDENTICAL NUMBERS and must come out different
    colours; that is the whole assertion, and nothing weaker can distinguish
    the rule from a constant. }
  Draw(cMixed);
  rose := CentreColour(0, 20);
  fell := CentreColour(2, 20);
  AssertTrue('up and down are different to begin with',
             (rose.red <> fell.red) or (rose.green <> fell.green));

  dojiDown := WickColour(1, 20);
  dojiUp := WickColour(3, 20);
  AssertTrue('both dojis drew', (dojiDown.alpha > 0) and (dojiUp.alpha > 0));
  AssertEquals('after a higher close, a doji is down', fell.red, dojiDown.red);
  AssertEquals('', fell.green, dojiDown.green);
  AssertEquals('after a lower one it is up', rose.red, dojiUp.red);
  AssertEquals('', rose.green, dojiUp.green);
end;

procedure TAdvChartCandleDrawTest.TestTheFirstRowHasNoPreviousAndIsUp;
var first, rising: TBGRAPixel;
begin
  { A DOJI IN ROW ZERO has nothing to compare against, and upstream calls it
    up. A port that left `previous` at zero would call it up as well and for
    the wrong reason -- so the fixture makes the first row a doji and the
    second a real rise, and asks that they agree. }
  Draw('{"tooltip":{"show":false},' +
       '"xAxis":{"type":"category","data":["a","b"]},' +
       '"yAxis":{"type":"value","min":0,"max":60},' +
       '"series":[{"type":"candlestick","name":"D","data":[' +
       '[20,20,5,35],[10,30,5,35]]}]}');
  first := WickColour(0, 30);
  rising := CentreColour(1, 20);
  AssertTrue('the doji drew', first.alpha > 0);
  AssertEquals('and it is the rising colour', rising.red, first.red);
  AssertEquals('', rising.green, first.green);
  AssertEquals('', rising.blue, first.blue);
end;

procedure TAdvChartCandleDrawTest.TestTheValueAxisSpansEveryOneOfTheFourColumns;
var lo, hi: Double;
begin
  { THE AXIS USED TO BE SIZED FROM THE CLOSES ALONE, because a coordinate was
    one column. The wicks then ran off the top and bottom of the plot -- and
    nothing raised, so the only sign was a chart that looked cropped. }
  Draw('{"tooltip":{"show":false},' +
       '"xAxis":{"type":"category","data":["a","b"]},' +
       '"yAxis":{"type":"value"},' +
       '"series":[{"type":"candlestick","name":"D","data":[' +
       '[40,41,7,93],[40,41,7,93]]}]}');
  lo := FChart.Build.Grid(0).YAxis(0).Scale.GetExtent2(sekEffective).Start;
  hi := FChart.Build.Grid(0).YAxis(0).Scale.GetExtent2(sekEffective).Stop;
  AssertTrue(Format('the axis reaches the highest (%g..%g)', [lo, hi]),
             hi >= 93);
  AssertTrue('and it is not the closes only', hi > 41);
end;

procedure TAdvChartCandleDrawTest.TestTheBodyIsHalfABandWide;
var
  g: TTyGridBuild;
  band, centreX, y, span, i: Integer;
  px: TBGRAPixel;
begin
  { UPSTREAM'S OWN RULE and not the bar layouter's: `max(min(band/2,
    barMaxWidth), barMinWidth)` with the limits defaulting to the band and to
    one pixel, which collapses to half a band. A candlestick beside a bar
    overlaps it deliberately -- the two are reading the same thing. }
  Draw(cMixed);
  g := FChart.Build.Grid(0);
  band := Round(g.XAxis(0).BandWidth);
  centreX := Round(g.XAxis(0).DataToCoord(0));
  y := Round(g.YAxis(0).DataToCoord(20));
  span := 0;
  { ONLY HALF A BAND EITHER SIDE. A whole band reaches into the NEIGHBOUR's
    body -- its centre is one band away and its own half-width brings it back
    to within a quarter -- and counting that made the measurement look half
    again too wide. }
  for i := centreX - band div 2 to centreX + band div 2 do
  begin
    if (i < 0) or (i >= cW) then Continue;
    px := FBmp.GetPixel(i, y);
    { The body is a saturated fill; the plot behind it is not. }
    if Abs(px.red - px.green) + Abs(px.green - px.blue) > 60 then Inc(span);
  end;
  AssertTrue(Format('%d px of body in a %d px band', [span, band]),
             (span >= band div 2 - 3) and (span <= band div 2 + 3));
end;

procedure TAdvChartCandleDrawTest.TestATypeWithNoRendererSaysSo;
begin
  { A CHART THAT CANNOT DRAW SOMETHING HAS TO SAY SO. Binding knows the
    twenty-three names ECharts ships and nothing about which of them this
    control can paint, so a chord binds cleanly, lays out cleanly and comes
    out blank -- and with no diagnostic that is the one thing this control is
    not allowed to do.
    The example was a funnel until the funnel drew, then a sankey until the
    sankey drew; moving it is what this test is for. }
  Draw('{"xAxis":{"type":"category","data":["a"]},"yAxis":{},' +
       '"series":[{"type":"chord","data":[1]}]}');
  AssertTrue('the chord says it is not drawn',
             Pos('chord', Diagnostics) > 0);
end;

procedure TAdvChartCandleDrawTest.TestATypeWithARendererDoesNot;
begin
  Draw(cMixed);
  AssertEquals('a candlestick has a renderer now', '', Diagnostics);
  Draw('{"xAxis":{"type":"category","data":["a"]},"yAxis":{},' +
       '"series":[{"type":"bar","data":[1]}]}');
  AssertEquals('and so has a bar', '', Diagnostics);
end;

initialization
  RegisterTest(TAdvChartCandleRuleTest);
  RegisterTest(TAdvChartCandleDrawTest);
end.
