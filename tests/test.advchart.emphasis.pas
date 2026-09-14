unit test.advchart.emphasis;
{$mode objfpc}{$H+}
{ What a hovered mark looks like while it is hovered.

  THE MACHINERY WAS ALREADY THERE. tyControls.AdvChart.Style is six hundred
  lines of four-state resolution -- two slots rather than one enum, a
  reference-counted emphasis mask, and a fallback rule that differs from the
  normal state's in five ways -- and until now every reference to it outside
  the unit was a test of itself. This file is about the join.

  WHAT IS DRAWN AND WHERE. The static layer already holds the mark at rest, so
  the emphasised copy is drawn OVER it in the dynamic layer: one element, no
  cache miss, no rebuild. That works because an emphasis GROWS or BRIGHTENS
  and therefore covers what it replaces -- which is a real constraint and is
  why blur is not here: dimming the OTHER marks means changing ink that is
  already baked into the static bitmap. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     fpjson, jsonparser,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Style,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Coord,
     tyControls.AdvanceChart;
type
  TAdvChartEmphasisRuleTest = class(TTestCase)
  private
    function EmphasisOf(const AText: string): TTyChartEmphasisSpec;
  published
    procedure TestNoEmphasisBlockLeavesTheDefaults;
    procedure TestScaleIsFourThingsInOneKey;
    procedure TestTheAutoRatioGrowsASmallMarkerMore;
    procedure TestFocusAndBlurScopeAreRead;
    procedure TestAShapeGrowsAboutItsOwnCentre;
    procedure TestARoundRectGrowsItsCornersToo;
    procedure TestAnImpossibleRatioLeavesTheShapeAlone;
    procedure TestTheDatumLookupWalksBackToFront;
  end;

  TEmphProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
  end;

  TAdvChartEmphasisDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TEmphProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    function BarPoint(ACat: Integer; AValue: Double): TPoint;
    { Pixels that differ between a plain render and a hovered one. The tooltip
      is switched off in every fixture here, so what differs IS the highlight. }
    function ChangedByHover(const AOption: string; AX, AY: Integer): Integer;
  published
    procedure TestHoveringABarLiftsIt;
    procedure TestEmphasisDisabledLiftsNothing;
    procedure TestADeclaredEmphasisColourWinsOverTheLift;
    procedure TestAHoveredSliceGrows;
    procedure TestAnAxisTriggerLiftsEveryRowItDescribes;
    procedure TestTriggerOnGovernsTheBoxAndNotTheHighlight;
  end;

implementation

const
  cW = 420;
  cH = 300;
  { THE TOOLTIP IS OFF IN EVERY DRAWING FIXTURE. A hover draws a box and a
    highlight, and a test that measured both together could not say which of
    them had stopped appearing -- which is exactly how a mutant in the
    highlight survived the tooltip file's own pixel tests. }
  cBars =
    '{"tooltip":{"show":false},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}';

{ ==================== the rules ==================== }

function TAdvChartEmphasisRuleTest.EmphasisOf(
  const AText: string): TTyChartEmphasisSpec;
var d: TJSONData;
begin
  d := GetJSON(AText);
  try
    Result := TyChartReadEmphasis(d);
  finally
    d.Free;
  end;
end;

procedure TAdvChartEmphasisRuleTest.TestNoEmphasisBlockLeavesTheDefaults;
var s: TTyChartEmphasisSpec;
begin
  s := EmphasisOf('{"type":"bar"}');
  AssertFalse('enabled', s.Disabled);
  { NO FOCUS IS THE DEFAULT, and it is what keeps blur off on every ordinary
    chart -- the dimming mechanism is gated entirely on somebody asking for
    it, and almost nobody does. }
  AssertTrue('nothing is blurred', s.Focus = cfNone);
  AssertTrue('the scale is automatic', s.ScaleAuto);
  AssertEquals('and a slice grows five pixels', 5.0, s.ScaleSizePx, 1e-9);
end;

procedure TAdvChartEmphasisRuleTest.TestScaleIsFourThingsInOneKey;
var s: TTyChartEmphasisSpec;
begin
  { Upstream's own comment names them: null or true is the default strategy, a
    finite positive number is a literal ratio, and 0 / false / negative / NaN /
    Infinity all mean no scale at all. }
  s := EmphasisOf('{"emphasis":{"scale":true}}');
  AssertTrue('true is automatic', s.ScaleAuto);
  s := EmphasisOf('{"emphasis":{"scale":false}}');
  AssertFalse('false is not', s.ScaleAuto);
  AssertEquals('and means no growth', 1.0, s.Scale, 1e-9);
  s := EmphasisOf('{"emphasis":{"scale":1.5}}');
  AssertFalse(s.ScaleAuto);
  AssertEquals('a number is taken as written', 1.5, s.Scale, 1e-9);
  s := EmphasisOf('{"emphasis":{"scale":0}}');
  AssertEquals('zero is no growth, not no size', 1.0, s.Scale, 1e-9);
  s := EmphasisOf('{"emphasis":{"scale":-2}}');
  AssertEquals('and so is a negative', 1.0, s.Scale, 1e-9);
end;

procedure TAdvChartEmphasisRuleTest.TestTheAutoRatioGrowsASmallMarkerMore;
var s: TTyChartEmphasisSpec;
begin
  s := TyChartEmphasisDefault;
  { `max(1.1, 3 / halfHeight)`. A twenty-pixel marker grows a tenth; a
    four-pixel one grows by half, because a tenth of four pixels is not a
    hover anybody can see. }
  AssertEquals('a big marker', 1.1, TyChartSymbolScaleRatio(s, 30), 1e-9);
  AssertEquals('a four-pixel marker', 1.5, TyChartSymbolScaleRatio(s, 2), 1e-9);
  { A DEGENERATE SYMBOL. Upstream divides by zero here and answers Infinity;
    in FPC that is a raise, so the floor answers instead. }
  AssertEquals('and one with no height at all', 1.1,
               TyChartSymbolScaleRatio(s, 0), 1e-9);
  s.ScaleAuto := False;
  s.Scale := 2;
  AssertEquals('a written ratio ignores the size', 2.0,
               TyChartSymbolScaleRatio(s, 2), 1e-9);
end;

procedure TAdvChartEmphasisRuleTest.TestFocusAndBlurScopeAreRead;
var s: TTyChartEmphasisSpec;
begin
  s := EmphasisOf('{"emphasis":{"focus":"series","blurScope":"global"}}');
  AssertTrue(s.Focus = cfSeries);
  AssertTrue(s.BlurScope = cbsGlobal);
  s := EmphasisOf('{"emphasis":{"focus":"self"}}');
  AssertTrue(s.Focus = cfSelf);
  { The scope's default is the COORDINATE SYSTEM, not the whole chart -- a
    focus on one grid does not dim the chart beside it. }
  AssertTrue(s.BlurScope = cbsCoordinateSystem);
end;

procedure TAdvChartEmphasisRuleTest.TestAShapeGrowsAboutItsOwnCentre;
var s: TTyChartShape;
begin
  s := TyScaleShape(TyShapeCircle(100, 50, 10), 1.5);
  AssertEquals('the centre does not move', 100.0, s.CX, 1e-9);
  AssertEquals('', 50.0, s.CY, 1e-9);
  AssertEquals('the radius does', 15.0, s.R1, 1e-9);

  s := TyScaleShape(TyShapeRect(TyRectF(10, 20, 30, 40)), 2);
  AssertEquals('a rect grows both ways from its middle', 0.0, s.Bounds.Left, 1e-9);
  AssertEquals('', 40.0, s.Bounds.Right, 1e-9);
  AssertEquals('', 10.0, s.Bounds.Top, 1e-9);
  AssertEquals('', 50.0, s.Bounds.Bottom, 1e-9);

  s := TyScaleShape(TyShapePolygon([TyPointF(0, 0), TyPointF(10, 0),
    TyPointF(10, 10), TyPointF(0, 10)]), 2);
  AssertEquals('and so does a polygon', -5.0, s.Points[0].X, 1e-9);
  AssertEquals('', 15.0, s.Points[2].X, 1e-9);
end;

procedure TAdvChartEmphasisRuleTest.TestARoundRectGrowsItsCornersToo;
var s: TTyChartShape;
begin
  { A ROUNDED RECT SCALED WITH ITS RADII LEFT ALONE IS A DIFFERENT SHAPE, not
    a larger one -- its corners get relatively tighter as it grows. }
  s := TyScaleShape(TyShapeRoundRect(TyRectF(0, 0, 20, 20), 4), 2);
  AssertEquals('the box doubled', 40.0, s.Bounds.Right - s.Bounds.Left, 1e-9);
  AssertEquals('and so did the corner', 8.0, s.Radii[0], 1e-9);
end;

procedure TAdvChartEmphasisRuleTest.TestAnImpossibleRatioLeavesTheShapeAlone;
var s: TTyChartShape;
begin
  s := TyScaleShape(TyShapeCircle(0, 0, 10), 0);
  AssertEquals('zero', 10.0, s.R1, 1e-9);
  s := TyScaleShape(TyShapeCircle(0, 0, 10), -1);
  AssertEquals('negative', 10.0, s.R1, 1e-9);
  s := TyScaleShape(TyShapeCircle(0, 0, 10), NaN);
  AssertEquals('NaN', 10.0, s.R1, 1e-9);
  s := TyScaleShape(TyShapeCircle(0, 0, 10), 1);
  AssertEquals('and one is not a change', 10.0, s.R1, 1e-9);
end;

procedure TAdvChartEmphasisRuleTest.TestTheDatumLookupWalksBackToFront;
var
  list: TTyPaintList;
  e: TTyChartElement;
  under, over: Integer;
begin
  { THE INVERSE OF THE HIT TEST, and it walks the same way round: two elements
    for one datum answer with the one ON TOP, because that is the one the
    reader can see and therefore the one a highlight has to replace. }
  list := TTyPaintList.Create;
  try
    e := TyChartElement(TyShapeRect(TyRectF(0, 0, 10, 10)));
    e.Silent := False;
    e.Datum := TyChartDatum(0, 3);
    e.Z := 1;
    under := list.Add(e);
    e.Z := 5;
    over := list.Add(e);
    AssertEquals('the topmost one', over, list.IndexOfDatum(0, 3));
    AssertTrue('and not the one below it', under <> list.IndexOfDatum(0, 3));
    AssertEquals('a row nobody drew', -1, list.IndexOfDatum(0, 9));

    { A RUN ELEMENT -- one polyline for a whole series -- carries no row, so a
      caller that knows only the series must still be able to find it. }
    list.Clear;
    e := TyChartElement(TyShapePolyline([TyPointF(0, 0), TyPointF(9, 9)]));
    e.Silent := False;
    e.Datum := TyChartDatum(2, -1);
    list.Add(e);
    AssertEquals('found by series alone', 0, list.IndexOfDatum(2, -1));
  finally
    list.Free;
  end;
end;

{ ==================== the picture ==================== }

procedure TEmphProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TEmphProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TAdvChartEmphasisDrawTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TEmphProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartEmphasisDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartEmphasisDrawTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartEmphasisDrawTest.BarPoint(ACat: Integer;
  AValue: Double): TPoint;
var g: TTyGridBuild;
begin
  g := FChart.Build.Grid(0);
  Result.X := Round(g.XAxis(0).DataToCoord(ACat));
  Result.Y := Round(g.YAxis(0).DataToCoord(AValue));
end;

function TAdvChartEmphasisDrawTest.ChangedByHover(const AOption: string;
  AX, AY: Integer): Integer;
var
  cold: TBGRABitmap;
  x, y: Integer;
  a, b: PBGRAPixel;
begin
  Draw(AOption);
  cold := TBGRABitmap.Create(cW, cH, BGRAWhite);
  try
    cold.PutImage(0, 0, FBmp, dmSet);
    FChart.Hover(AX, AY);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    Result := 0;
    for y := 0 to cH - 1 do
    begin
      a := cold.ScanLine[y];
      b := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green)
          or (a^.blue <> b^.blue) then Inc(Result);
        Inc(a);
        Inc(b);
      end;
    end;
  finally
    cold.Free;
  end;
end;

procedure TAdvChartEmphasisDrawTest.TestHoveringABarLiftsIt;
var p: TPoint;
begin
  Draw(cBars);
  p := BarPoint(2, 30);
  { WITH NOTHING DECLARED an emphasis is the normal colour ten per cent
    brighter -- the default hover appearance of every bar, slice and symbol
    there is. A port that read "no emphasis style" as "no change" would draw a
    hover that does nothing, and nothing here would have noticed. }
  AssertTrue('the bar changed under the pointer',
             ChangedByHover(cBars, p.X, p.Y + 6) > 500);
end;

procedure TAdvChartEmphasisDrawTest.TestEmphasisDisabledLiftsNothing;
var p: TPoint; opt: string;
begin
  opt := '{"tooltip":{"show":false},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","emphasis":{"disabled":true},' +
    '"data":[20,40,60,80]}]}';
  Draw(opt);
  p := BarPoint(2, 30);
  AssertEquals('disabled means disabled', 0,
               ChangedByHover(opt, p.X, p.Y + 6));
end;

procedure TAdvChartEmphasisDrawTest.TestADeclaredEmphasisColourWinsOverTheLift;
var
  p: TPoint;
  opt: string;
  px: TBGRAPixel;
begin
  opt := '{"tooltip":{"show":false},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales",' +
    '"emphasis":{"itemStyle":{"color":"#ff0000"}},"data":[20,40,60,80]}]}';
  Draw(opt);
  p := BarPoint(2, 30);
  FChart.Hover(p.X, p.Y + 6);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  px := FBmp.GetPixel(p.X, p.Y + 6);
  { A DECLARED FILL IS NOT LIFTED. The lift is what happens in its ABSENCE --
    read the other way round, a hover would brighten the colour the author
    asked for. }
  AssertTrue(Format('the bar is red, not lifted blue (%d,%d,%d)',
                    [px.red, px.green, px.blue]),
             (px.red > 200) and (px.green < 80) and (px.blue < 80));
end;

procedure TAdvChartEmphasisDrawTest.TestAHoveredSliceGrows;
var
  cx, cy, i, r, grew: Integer;
  cold: TBGRABitmap;
  opt: string;
begin
  { A SLICE GROWS ITS OUTER RADIUS BY PIXELS. Scaling it about the disc centre
    instead would lift its inner edge off the hole, so the two are different
    operations and this is the one upstream does. What the test looks for is
    ink appearing just OUTSIDE where the ring used to end. }
  opt := '{"tooltip":{"show":false},' +
    '"series":[{"type":"pie","radius":"60%","data":[' +
    '{"name":"A","value":25},{"name":"B","value":25},' +
    '{"name":"C","value":25},{"name":"D","value":25}]}]}';
  Draw(opt);
  cx := cW div 2;
  cy := cH div 2;
  cold := TBGRABitmap.Create(cW, cH, BGRAWhite);
  try
    cold.PutImage(0, 0, FBmp, dmSet);
    FChart.Hover(cx + 40, cy - 40);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    { PIXELS THAT WERE BACKGROUND AND ARE NOW INK. Counting everything that
      CHANGED would count the lift as well -- the slice is ten per cent
      brighter over its whole area, which is thousands of pixels -- and a
      slice that only brightened would pass. What only growth can do is put
      colour where there was none. }
    grew := 0;
    for i := 0 to cW - 1 do
      for r := 0 to cH - 1 do
        if (cold.GetPixel(i, r).red > 240) and (cold.GetPixel(i, r).green > 240)
          and (cold.GetPixel(i, r).blue > 240)
          and (FBmp.GetPixel(i, r).blue > 120)
          and (FBmp.GetPixel(i, r).red < 200) then
          Inc(grew);
    AssertTrue(Format('the slice reached past where it ended (%d px)', [grew]),
               grew > 100);
  finally
    cold.Free;
  end;
end;

procedure TAdvChartEmphasisDrawTest.TestTriggerOnGovernsTheBoxAndNotTheHighlight;
var p: TPoint; opt: string; n, both: Integer;
begin
  { `triggerOn` IS A TOOLTIP OPTION and the highlight is not a tooltip. A chart
    set to open its box on CLICK still lights up what the pointer is over,
    because upstream drives the two from separate listeners -- and this port
    has no click path yet, so with the box suppressed what is left is exactly
    the highlight. }
  opt := '{"tooltip":{"triggerOn":"click"},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}';
  Draw(opt);
  p := BarPoint(2, 30);
  n := ChangedByHover(opt, p.X, p.Y + 6);
  AssertTrue('the bar still lit up', n > 500);
  { AND NO BOX -- said as a COMPARISON rather than as a number, because the
    bar's own area is a few thousand pixels and so is the box's; a threshold
    between them would be a number that means nothing to a reader and breaks
    on a theme with a different bar width. }
  both := ChangedByHover(
    '{"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}',
    p.X, p.Y + 6);
  AssertTrue(Format('the default triggerOn draws more (%d vs %d)', [both, n]),
             both > n + 500);
end;

procedure TAdvChartEmphasisDrawTest.TestAnAxisTriggerLiftsEveryRowItDescribes;
var
  p: TPoint;
  one, two: Integer;
  optOne, optTwo: string;
begin
  { AN AXIS TRIGGER HIGHLIGHTS THE WHOLE COLUMN -- upstream calls it
    triggerEmphasis and has it on by default, which is what ties the rows the
    box is describing to the marks they came from. Two series changing twice
    as many pixels as one is the cheapest way to see it. }
  optOne := '{"tooltip":{"trigger":"axis","showContent":false},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"S1","data":[80,80,80,80]}]}';
  optTwo := '{"tooltip":{"trigger":"axis","showContent":false},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"S1","data":[80,80,80,80]},' +
    '{"type":"bar","name":"S2","data":[80,80,80,80]}]}';
  Draw(optOne);
  p := BarPoint(2, 40);
  one := ChangedByHover(optOne, p.X, p.Y);
  two := ChangedByHover(optTwo, p.X, p.Y);
  AssertTrue('one series lit up', one > 500);
  AssertTrue('and two series lit up more', two > one);
end;

initialization
  RegisterTest(TAdvChartEmphasisRuleTest);
  RegisterTest(TAdvChartEmphasisDrawTest);
end.
