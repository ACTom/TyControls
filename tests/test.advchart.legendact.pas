unit test.advchart.legendact;
{$mode objfpc}{$H+}
{ THE LEGEND'S CLICK, HOVER AND ACTIONS, HELD TO UPSTREAM [Batch 93].

  The fixture of the selection and focus batches (tools/advchart-oracle/
  select-legend.js, the real ECharts 6.1 build driven through pointer moves,
  clicks and dispatchAction), its legend cases replayed through the
  control's own MouseMove / MouseDown / MouseUp and DispatchAction with
  test.advchart.select's harness, a render after every step (the frame):

    the events -- a legend item's hover highlight / downplay with
      excludeSeriesId, its click's downplay, legendselectchanged, highlight,
      the five actions' events and their payloads;
    every series' items -- a series the legend switched off has no element
      and no selected indices, a pie's slices filtered by name with the
      inner / raw mapping, the bars re-laid out for the survivors, the states
      a reused element keeps through the full update (the previous list
      re-applied, the z2 creep) and the new elements of a series or a slice
      switched back on;
    the legend -- its `selected` map in JavaScript's key order (every name
      written back after an action, single mode's one item), each item's
      words, icon fill, pen (the series' border, inactiveBorderColor, the
      'auto' width and a numeric inactiveBorderWidth ignored) and opacity.

  Then hand tests, their expected values taken from the real build
  (scratch probes, not kept): two legends forced to the same statuses, the
  legend query, a heatmap's legendHoverLink default; and what upstream's
  source says plainly: selectedMode false silences a triggerEvent legend
  too, and the control's Option text is left as the host wrote it. }
interface
uses Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Events, tyControls.AdvChart.Legend,
     tyControls.AdvChart.States,
     tyControls.AdvanceChart,
     test.advchart.select;
type
  TAdvChartLegendActTest = class(TAdvChartSelectHarness)
  private
    procedure Frame;
    procedure Plain3(const ALegend: string);
    { whether any element of series ASeries is drawn }
    function Drawn(ASeries: Integer): Boolean;
    { the centre of legend 0's item named AName }
    procedure ItemPoint(const AName: string; out AX, AY: Integer);
    { the logged events, type and payload, one per line }
    function LogText: string;
  published
    procedure TestLegendCasesAsUpstream;
    { what the fixture has no case for }
    procedure TestTwoLegendsAreForcedToTheSameStatuses;
    procedure TestAHeatmapIsExcludedFromTheHoverLink;
    procedure TestSelectedModeFalseSilencesATriggerEventLegend;
    procedure TestTheOptionTextIsLeftAsWritten;
    procedure TestTheQueriedLegendsMapsAreAnded;
    procedure TestTheMapKeepsJavaScriptsKeyOrder;
    procedure TestAFunnelsIconTakesItsBorder;
  end;

implementation

const
  { THE LEGEND BATCH'S CASES: the first ten were recorded with B1, the last
    eight added with this batch }
  cB3Cases: array[0..17] of string = ('legend-bar-toggle', 'legend-hover-bar',
    'legend-hover-focus', 'legend-single', 'legend-mode-false', 'legend-pie',
    'legend-hover-pie', 'legend-actions', 'legend-inactive-custom',
    'legend-hoverlink-false',
    'legend-single-actions', 'legend-mode-false-action', 'legend-held-hover',
    'legend-pie-inverse', 'legend-pie-border', 'legend-inverse-fresh',
    'legend-held-hover-moves', 'legend-reshown-new');

procedure TAdvChartLegendActTest.Frame;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

{ bars A, B, C on Mon..Thu, with the legend option given }
procedure TAdvChartLegendActTest.Plain3(const ALegend: string);
var o: TJSONData;
begin
  o := GetJSON('{"animation":false,"xAxis":{"type":"category","data":["Mon","Tue","Wed","Thu"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","name":"A","data":[12,20,15,30]},'
    + '{"type":"bar","name":"B","data":[8,25,18,22]},{"type":"bar","name":"C","data":[3,4,5,6]}],'
    + '"legend":' + ALegend + '}');
  try
    NewChart(TJSONObject(o));
  finally
    o.Free;
  end;
  FLogger.Log.Clear;
end;

function TAdvChartLegendActTest.Drawn(ASeries: Integer): Boolean;
var k: Integer; l: TTyPaintList;
begin
  Result := False;
  l := FChart.List;
  for k := 0 to l.Count - 1 do
    if (l.Element(k).Datum.Kind = ctkSeries) and (l.Element(k).Datum.SeriesIndex = ASeries) then
      Exit(True);
end;

procedure TAdvChartLegendActTest.ItemPoint(const AName: string; out AX, AY: Integer);
var lay: TTyLegendLayout; i: Integer;
begin
  lay := FChart.LegendLayout(0);
  for i := 0 to High(lay.Items) do
    if lay.Items[i].Name = AName then
    begin
      AX := Round((lay.Items[i].Bounds.Left + lay.Items[i].Bounds.Right) / 2);
      AY := Round((lay.Items[i].Bounds.Top + lay.Items[i].Bounds.Bottom) / 2);
      Exit;
    end;
  Fail('no legend item ' + AName);
end;

function TAdvChartLegendActTest.LogText: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FLogger.Log.Count - 1 do
    Result := Result + StringReplace(FLogger.Log[i], #9, ' ', []) + LineEnding;
end;

procedure TAdvChartLegendActTest.TestLegendCasesAsUpstream;
begin
  RunCases(cB3Cases, 60);
  AssertTrue(Format('%d mismatches over %d steps:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertEquals('every legend case ran', Length(cB3Cases), FCases);
  AssertTrue(Format('only %d steps compared', [FCompared]), FCompared >= 60);
end;

{ legendAction.ts: the method on the legends the query names, their map, then
  EVERY legend forced to it; the event's map is every legend's, ANDed; a
  series is shown only when every legend selects it -- a name a legend does
  not list but has in its map counts. Upstream, with legend 0 listing A, B
  and legend 1 (id L1, name 'second') listing B, C: }
procedure TAdvChartLegendActTest.TestTwoLegendsAreForcedToTheSameStatuses;

  procedure Check(const AStep, ASel0, ASel1, AShown, AEvent: string);
  var s: string; k: Integer;
  begin
    AssertEquals(AStep + ' legend 0', ASel0, FChart.LegendSelectedText(0));
    AssertEquals(AStep + ' legend 1', ASel1, FChart.LegendSelectedText(1));
    s := '';
    for k := 0 to 2 do
      if Drawn(k) then s := s + Chr(Ord('A') + k);
    AssertEquals(AStep + ' shown', AShown, s);
    AssertEquals(AStep + ' event', AEvent, LogText);
    FLogger.Log.Clear;
  end;

begin
  Plain3('[{"data":["A","B"]},{"id":"L1","name":"second","data":["B","C"],"top":0}]');
  AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect","name":"B","legendIndex":1}'));
  Frame;
  Check('toggle B on legend 1', '{"B":false,"C":true}', '{"B":false,"C":true}', 'AC',
    'legendselectchanged {"name":"B","selected":{"A":true,"B":false,"C":true},"type":"legendselectchanged"}' + LineEnding);
  AssertTrue(FChart.DispatchAction('{"type":"legendUnSelect","name":"A","legendId":"L1"}'));
  Frame;
  { A is not legend 1's item, yet its map switches it off: hidden, while the
    event (made from the items) still says true }
  Check('unselect A by id', '{"B":false,"C":true}', '{"B":false,"C":true,"A":false}', 'C',
    'legendunselected {"name":"A","selected":{"A":true,"B":false,"C":true},"type":"legendunselected"}' + LineEnding);
  AssertTrue(FChart.DispatchAction('{"type":"legendInverseSelect","legendName":"second"}'));
  Frame;
  Check('inverse by name', '{"B":true,"C":false}', '{"B":true,"C":false,"A":false}', 'B',
    'legendinverseselect {"selected":{"A":true,"B":true,"C":false},"legendIndex":[1],"type":"legendinverseselect"}' + LineEnding);
  AssertTrue(FChart.DispatchAction('{"type":"legendAllSelect","legendIndex":[1,0]}'));
  Frame;
  Check('all, legends in the order asked', '{"B":true,"C":true,"A":true}', '{"B":true,"C":true,"A":true}', 'ABC',
    'legendselectall {"selected":{"A":true,"B":true,"C":true},"legendIndex":[1,0],"type":"legendselectall"}' + LineEnding);
  { no name: JavaScript keys it 'undefined', and the event leaves it out }
  AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect"}'));
  Frame;
  Check('no name', '{"B":true,"C":true,"A":true,"undefined":false}',
    '{"B":true,"C":true,"A":true,"undefined":false}', 'ABC',
    'legendselectchanged {"selected":{"A":true,"B":true,"C":true},"type":"legendselectchanged"}' + LineEnding);
end;

{ legendHoverLink is the series' option or its type's default -- true for a
  bar, a scatter, a pie..., absent (falsy) for a heatmap, which therefore
  joins excludeSeriesId unless it says true. Upstream, hovering S: }
procedure TAdvChartLegendActTest.TestAHeatmapIsExcludedFromTheHoverLink;
var o: TJSONData; x, y: Integer; st: TTyStItem;

  function Compact(const AText: string): string;
  begin
    Result := StringReplace(AText, ' : ', ':', [rfReplaceAll]);
    Result := StringReplace(Result, ', ', ',', [rfReplaceAll]);
    Result := StringReplace(Result, '{ ', '{', [rfReplaceAll]);
    Result := StringReplace(Result, ' }', '}', [rfReplaceAll]);
  end;

begin
  o := GetJSON('{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"category","data":["x","y"]},"visualMap":{"show":false,"min":0,"max":10},'
    + '"series":[{"type":"heatmap","name":"H","data":[[0,0,5],[1,1,7]]},'
    + '{"type":"scatter","name":"S","data":[[0,1],[1,0]]},'
    + '{"type":"heatmap","name":"H2","legendHoverLink":true,"data":[[0,1,1]]}],"legend":{}}');
  try
    NewChart(TJSONObject(o));
  finally
    o.Free;
  end;
  FLogger.Log.Clear;
  ItemPoint('S', x, y);
  FChart.Move(x, y);
  { the raw text, NULs and all: the generated id is NUL H NUL 0 }
  AssertEquals('the highlight', 'highlight {"type":"highlight","seriesName":"S","name":null,'
    + '"excludeSeriesId":["\u0000H\u00000"]}' + LineEnding, Compact(LogText));
  { AND THE EXCLUSION HOLDS: H's own item lights nothing of H (its id came
    back through the payload's parse whole), H2's lights H2 }
  ItemPoint('H', x, y);
  FChart.Move(x, y);
  Frame;
  AssertTrue(FChart.ItemStates(0, 0, st));
  AssertEquals('H is excluded', TyStHoverNormal, st.Host.HoverState);
  ItemPoint('H2', x, y);
  FChart.Move(x, y);
  Frame;
  AssertTrue(FChart.ItemStates(2, 0, st));
  AssertEquals('H2 is not', TyStHoverEmphasis, st.Host.HoverState);
end;

{ `hitRect.silent = !selectMode` and every other child of an item is silent
  (LegendView.ts:497-506): with selectedMode false nothing of the legend is
  hit, so a triggerEvent legend publishes no mouse event either }
procedure TAdvChartLegendActTest.TestSelectedModeFalseSilencesATriggerEventLegend;
var x, y, n: Integer;
const
  cMouse: array[0..4] of string = ('mousemove', 'mouseover', 'mousedown', 'mouseup', 'click');
begin
  Plain3('{"selectedMode":false,"triggerEvent":true}');
  for n := 0 to High(cMouse) do
    FChart.ChartOn(cMouse[n], @FLogger.Handle);
  ItemPoint('B', x, y);
  FChart.ClickAt(x, y);
  Frame;
  AssertEquals('nothing at all', '', LogText);
  AssertTrue('B still drawn', Drawn(1));
  { and with selectedMode on, the same point is the item }
  Plain3('{"triggerEvent":true}');
  for n := 0 to High(cMouse) do
    FChart.ChartOn(cMouse[n], @FLogger.Handle);
  ItemPoint('B', x, y);
  FChart.ClickAt(x, y);
  Frame;
  AssertTrue('the item is hit: ' + LogText, Pos('legendselectchanged', LogText) > 0);
  AssertFalse('B switched off', Drawn(1));
end;

{ the model keeps its state in its option -- the control's Option text is
  what the host wrote, and writing a new one starts the legend afresh }
procedure TAdvChartLegendActTest.TestTheOptionTextIsLeftAsWritten;
var before: string;
begin
  Plain3('{"selected":{"C":false}}');
  before := FChart.Option;
  AssertEquals('loaded', '{"C":false}', FChart.LegendSelectedText(0));
  AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect","name":"A"}'));
  Frame;
  AssertEquals('the model moved', '{"C":false,"A":false,"B":true}', FChart.LegendSelectedText(0));
  AssertFalse('A off', Drawn(0));
  AssertEquals('the text did not', before, FChart.Option);
  { the same text again is no new option (the setter's own rule) }
  FChart.Option := before;
  Frame;
  AssertFalse('still off', Drawn(0));
  { a different text is -- the same option with a space after it: notMerge,
    new legend models, the map the option wrote }
  FChart.Option := before + ' ';
  Frame;
  AssertEquals('afresh', '{"C":false}', FChart.LegendSelectedText(0));
  AssertTrue('A back', Drawn(0));
  AssertFalse('C still off', Drawn(2));
end;

{ makeSelectedMap over the queried legends ANDs a name both list: legend 0
  has A off in its option, legend 1 not -- toggling C (which neither lists)
  writes A off into both. Upstream: }
procedure TAdvChartLegendActTest.TestTheQueriedLegendsMapsAreAnded;
var s: string; k: Integer;
begin
  Plain3('[{"data":["A","B"],"selected":{"A":false}},{"data":["A","B"],"top":0}]');
  AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect","name":"C"}'));
  Frame;
  AssertEquals('legend 0', '{"A":false,"C":false,"B":true}', FChart.LegendSelectedText(0));
  AssertEquals('legend 1', '{"C":false,"A":false,"B":true}', FChart.LegendSelectedText(1));
  s := '';
  for k := 0 to 2 do
    if Drawn(k) then s := s + Chr(Ord('A') + k);
  AssertEquals('shown', 'B', s);
  AssertEquals('the event', 'legendselectchanged {"name":"C","selected":{"A":false,"B":true},'
    + '"type":"legendselectchanged"}' + LineEnding, LogText);
end;

{ the map is a JavaScript object: integer-like names first, ascending, the
  others in insertion order -- in `selected` and in the event alike.
  Upstream, series x, 10, 2 and x toggled off: }
procedure TAdvChartLegendActTest.TestTheMapKeepsJavaScriptsKeyOrder;
var o: TJSONData;
begin
  o := GetJSON('{"animation":false,"xAxis":{"type":"category","data":["Mon","Tue"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","name":"x","data":[1,2]},'
    + '{"type":"bar","name":"10","data":[2,3]},{"type":"bar","name":"2","data":[3,4]}],"legend":{}}');
  try
    NewChart(TJSONObject(o));
  finally
    o.Free;
  end;
  FLogger.Log.Clear;
  AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect","name":"x"}'));
  Frame;
  AssertEquals('the map', '{"2":true,"10":true,"x":false}', FChart.LegendSelectedText(0));
  AssertEquals('the event', 'legendselectchanged {"name":"x","selected":{"2":true,"10":true,"x":false},'
    + '"type":"legendselectchanged"}' + LineEnding, LogText);
  AssertFalse('x off', Drawn(0));
  AssertTrue('10 on', Drawn(1));
end;

{ a funnel's own border -- tokens.color.neutral00, width 1 -- gives its
  legend icons a pen of 2 in that colour (upstream: stroke '#fff',
  lineWidth 2); here the neutral is the chart's ground }
procedure TAdvChartLegendActTest.TestAFunnelsIconTakesItsBorder;
var
  o: TJSONData;
  lay: TTyLegendLayout;
  ground: TTyChartColor;
begin
  o := GetJSON('{"animation":false,"legend":{},"series":[{"type":"funnel",'
    + '"data":[{"name":"a","value":10},{"name":"b","value":5}]}]}');
  try
    NewChart(TJSONObject(o));
  finally
    o.Free;
  end;
  lay := FChart.LegendLayout(0);
  AssertEquals('two items', 2, Length(lay.Items));
  ground := TTyChartColor(FCtl.Model.ResolveStyle('TyAdvChart', '', [tysNormal]).Background.Color);
  AssertTrue('a stroke', lay.Items[0].HasStroke);
  AssertEquals('in the ground', ground, lay.Items[0].Stroke);
  AssertEquals('at 2', 2.0, lay.Items[0].IconPen);
  AssertEquals('the second too', 2.0, lay.Items[1].IconPen);
end;

initialization
  RegisterTest(TAdvChartLegendActTest);
end.
