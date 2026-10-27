unit test.advchart.axisemphasis;
{$mode objfpc}{$H+}
{ THE AXIS POINTER'S triggerEmphasis, HELD TO UPSTREAM [R5-D].

  tools/advchart-oracle/axis-emphasis.js runs the real ECharts 6.1 build in
  node with the harness of tooltip-actions.js: pointer steps through
  zrender's Handler, hand-dispatched actions, a connected pair. Per step it
  records every highlight, downplay, updateaxispointer, showtip, hidetip and
  updated of every chart in the order the handlers heard them, and per
  series which items are in emphasis or blur (data.getItemGraphicEl's
  currentStates, a symbol's path), a line's temporary symbols and its
  polyline's states, and what the tooltip box shows.

  This replays them through TTyAdvanceChart with the probe of
  test.advchart.tooltipactions (the SSR width table, the box answering
  80 x 40); the states come from ItemStates / LineStates.

  tools/advchart-oracle/tooltip-sources.js (same harness) records where a
  tooltip's option comes from besides the global component: a coordinate
  system's own `tooltip` (the item cascade's third level, and the base
  tooltip model collectAxesInfo reads: show, trigger, axisPointer.type), a
  showTip's payload.tooltip at x / y (a proxy element shown as a component
  item) and tooltipOption (the axis tooltip's top level). Per step: the
  events, the axisPointer model's axes (shown, type, label) and the box
  (shown, what, its text, the anchor and the top-left). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.AxisPointer,
     tyControls.AdvanceChart.Events, tyControls.AdvanceChart.Connect,
     tyControls.AdvanceChart.States,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.tooltipactions;
type
  TAeProbe = class(TTaProbe)
  public
    { per series: e / b lists and the polyline's states, as the oracle
      writes them }
    function SeriesText(ASeriesIndex: Integer; out AEmph, ABlur, APoly: string): Boolean;
  end;

  TAeOracleBase = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    procedure Bad(const AWhat: string);
    procedure Finish(const AWhat: string);
    function NewProbe(const AOptionJson: string; ATag: Integer): TAeProbe;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareState(AChart: TAeProbe; AState: TJSONObject; AIndex: Integer);
  protected
    procedure RunCase(const AId: string);
    function FixtureName: string; virtual;
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  TAdvChartAxisEmphasisOracleTest = class(TAeOracleBase)
  published
    procedure TestTheDefaultAsUpstream;
    procedure TestTheRootSaysNoAsUpstream;
    procedure TestTheAxisSaysNoAsUpstream;
    procedure TestTheTooltipKeyIsDeadAsUpstream;
    procedure TestACategoryCrossArmAsUpstream;
    procedure TestNoBlurAsUpstream;
    procedure TestAnItemSeriesStaysDownAsUpstream;
    procedure TestTheActionsAsUpstream;
    procedure TestAConnectedPairAsUpstream;
    procedure TestALineWithoutSymbolsAsUpstream;
    procedure TestLinkedAxesAsUpstream;
    procedure TestAPolarAsUpstream;
    { what the pointer stands on is painted lifted only where the axis'
      model says triggerEmphasis }
    procedure TestTheRootsNoLiftsNothing;
  end;

  { [R5-D] tools/advchart-oracle/sunburst-legacy.js: sunburstHighlight /
    sunburstUnhighlight, the same records }
  TAdvChartSunburstLegacyOracleTest = class(TAeOracleBase)
  protected
    function FixtureName: string; override;
  published
    procedure TestOneSunburstAsUpstream;
    procedure TestTwoSunburstsAsUpstream;
  end;

  TAdvChartTooltipSourcesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    function NewProbe(const AOptionJson: string; ATag: Integer): TAeProbe;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure CompareState(AChart: TAeProbe; AState: TJSONObject);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAGridFormatterAsUpstream;
    procedure TestTheSeriesOverItsGridAsUpstream;
    procedure TestAGridTriggerAsUpstream;
    procedure TestAGridCrossAsUpstream;
    procedure TestAGridShadowAsUpstream;
    procedure TestAGridHiddenAsUpstream;
    procedure TestAPolarTriggerAsUpstream;
    procedure TestASingleAxisAsUpstream;
    procedure TestACalendarIsNotReadAsUpstream;
    procedure TestTheProxyAsUpstream;
    procedure TestTheTooltipOptionAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cNulMark = #$E2#$90#$80;
  cTypes: array[0..7] of string = ('highlight', 'downplay', 'updateaxispointer',
    'showtip', 'hidetip', 'updated', 'sunbursthighlight', 'sunburstunhighlight');

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

procedure FromIsUid(AData: TJSONData);
var i: Integer;
begin
  if AData = nil then Exit;
  if AData is TJSONObject then
  begin
    for i := 0 to AData.Count - 1 do
      if (TJSONObject(AData).Names[i] = 'from') and (AData.Items[i].JSONType = jtString) then
        AData.Items[i].AsString := '<view uid>'
      else
        FromIsUid(AData.Items[i]);
  end
  else if AData is TJSONArray then
    for i := 0 to AData.Count - 1 do FromIsUid(AData.Items[i]);
end;

function ParsePort(const AJson: string): TJSONData;
begin
  Result := GetJSON(StringReplace(AJson, '\u0000', cNulMark, [rfReplaceAll]));
  FromIsUid(Result);
end;

function SameJson(AWant, AGot: TJSONData): Boolean;
var
  i: Integer;
  wo, go: TJSONObject;
begin
  Result := False;
  if (AWant = nil) or (AGot = nil) then Exit(AWant = AGot);
  if AWant.JSONType <> AGot.JSONType then Exit;
  case AWant.JSONType of
    jtNull: Result := True;
    jtBoolean: Result := AWant.AsBoolean = AGot.AsBoolean;
    jtNumber: Result := AWant.AsFloat = AGot.AsFloat;
    jtString: Result := AWant.AsString = AGot.AsString;
    jtArray:
      begin
        if AWant.Count <> AGot.Count then Exit;
        for i := 0 to AWant.Count - 1 do
          if not SameJson(TJSONArray(AWant).Items[i], TJSONArray(AGot).Items[i]) then Exit;
        Result := True;
      end;
    jtObject:
      begin
        wo := TJSONObject(AWant);
        go := TJSONObject(AGot);
        if wo.Count <> go.Count then Exit;
        for i := 0 to wo.Count - 1 do
        begin
          if go.Names[i] <> wo.Names[i] then Exit;
          if not SameJson(wo.Items[i], go.Items[i]) then Exit;
        end;
        Result := True;
      end;
  end;
end;

function ListText(AArr: TJSONArray; AWithout: TJSONArray = nil): string;
var k, j: Integer; skip: Boolean;
begin
  Result := '';
  for k := 0 to AArr.Count - 1 do
  begin
    skip := False;
    if AWithout <> nil then
      for j := 0 to AWithout.Count - 1 do
        if AWithout.Integers[j] = AArr.Integers[k] then skip := True;
    if skip then Continue;
    if Result <> '' then Result := Result + ',';
    Result := Result + IntToStr(AArr.Integers[k]);
  end;
end;

function IsAeType(const AType: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(cTypes) do
    if cTypes[i] = AType then Exit(True);
  Result := False;
end;

function StatesText(AStates: TTyStNames): string;
begin
  Result := '';
  if stnSelect in AStates then Result := 'select';
  if stnEmphasis in AStates then
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + 'emphasis';
  end;
  if stnBlur in AStates then
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + 'blur';
  end;
end;

{ ==================== the probe ==================== }

function TAeProbe.SeriesText(ASeriesIndex: Integer; out AEmph, ABlur, APoly: string): Boolean;
var
  st: TTyDataStore;
  r: Integer;
  item, run, area: TTyStItem;
begin
  AEmph := '';
  ABlur := '';
  APoly := #0;
  st := SeriesStore(ASeriesIndex);
  Result := st <> nil;
  if not Result then Exit;
  for r := 0 to st.Count - 1 do
  begin
    if not ItemStates(ASeriesIndex, r, item) then Continue;
    if stnEmphasis in item.Host.States then
    begin
      if AEmph <> '' then AEmph := AEmph + ',';
      AEmph := AEmph + IntToStr(st.GetRawIndex(r));
    end;
    if stnBlur in item.Host.States then
    begin
      if ABlur <> '' then ABlur := ABlur + ',';
      ABlur := ABlur + IntToStr(st.GetRawIndex(r));
    end;
  end;
  if LineStates(ASeriesIndex, run, area) then APoly := StatesText(run.Host.States);
end;

{ ==================== the oracle test ==================== }

procedure TAeOracleBase.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath(FixtureName));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

function TAeOracleBase.FixtureName: string;
begin
  Result := 'advchart-axis-emphasis.json';
end;

procedure TAeOracleBase.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAeOracleBase.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAeOracleBase.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAeOracleBase.NewProbe(const AOptionJson: string;
  ATag: Integer): TAeProbe;
begin
  Result := TAeProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  Result.Tag := ATag;
  Result.TooltipNow := 0;
  Result.SetBounds(0, 0, cW, cH);
  Result.Option := AOptionJson;
  Result.OnChartEvent := @OnEvent;
  Result.ChartOn('updated', @OnEvent);
  Result.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAeOracleBase.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if not IsAeType(AEvent.EventType) then Exit;
  FLog.Add(IntToStr(TComponent(Sender).Tag) + #9 + AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAeOracleBase.CompareEvents(AWant: TJSONArray);
var
  i, n: Integer;
  e: TJSONArray;
  parts: TStringList;
  got: TJSONData;
begin
  Inc(FCompared);
  if FLog.Count <> AWant.Count then
  begin
    Bad(Format('%d events, upstream %d', [FLog.Count, AWant.Count]));
    for i := 0 to Min(FLog.Count, AWant.Count + 3) - 1 do
      Bad(Format('  port %d: %s', [i, Copy(StringReplace(FLog[i], #9, ' ', [rfReplaceAll]), 1, 200)]));
    for i := 0 to AWant.Count - 1 do
      Bad(Format('  upstream %d: %s', [i, Copy(AWant.Items[i].AsJSON, 1, 200)]));
  end;
  n := Min(FLog.Count, AWant.Count);
  parts := TStringList.Create;
  try
    parts.Delimiter := #9;
    parts.StrictDelimiter := True;
    for i := 0 to n - 1 do
    begin
      e := TJSONArray(AWant.Items[i]);
      parts.DelimitedText := FLog[i];
      Inc(FCompared);
      if (parts[0] <> IntToStr(e.Integers[0])) or (parts[1] <> e.Strings[1]) then
      begin
        Bad(Format('event %d: chart %s %s, upstream chart %d %s', [i, parts[0], parts[1],
          e.Integers[0], e.Strings[1]]));
        Continue;
      end;
      if e.Items[2].JSONType = jtNull then Continue;
      got := ParsePort(parts[2]);
      try
        Inc(FCompared);
        if not SameJson(e.Items[2], got) then
          Bad(Format('event %d (%s %s): %s, upstream %s', [i, parts[0], parts[1],
            Copy(got.AsJSON, 1, 400), Copy(e.Items[2].AsJSON, 1, 400)]));
      finally
        got.Free;
      end;
    end;
  finally
    parts.Free;
  end;
end;

procedure TAeOracleBase.CompareState(AChart: TAeProbe;
  AState: TJSONObject; AIndex: Integer);
var
  series: TJSONArray;
  sr: TJSONObject;
  s: Integer;
  emph, blur, poly, want, who: string;
begin
  who := 'chart ' + IntToStr(AIndex);
  series := AState.Arrays['series'];
  for s := 0 to series.Count - 1 do
  begin
    sr := series.Objects[s];
    Inc(FCompared);
    if not AChart.SeriesText(s, emph, blur, poly) then
    begin
      Bad(Format('%s series %d: none', [who, s]));
      Continue;
    end;
    { A LINE'S TEMPORARY SYMBOL (LineView.highlight on a row with no
      symbol) is built and in emphasis like any other [R5-F: it was not
      built, and left out of the comparison] }
    Inc(FCompared);
    if emph <> ListText(sr.Arrays['e']) then
      Bad(Format('%s series %d: emphasis [%s], upstream [%s]', [who, s, emph,
        ListText(sr.Arrays['e'])]));
    Inc(FCompared);
    if blur <> ListText(sr.Arrays['b']) then
      Bad(Format('%s series %d: blur [%s], upstream [%s]', [who, s, blur, ListText(sr.Arrays['b'])]));
    if sr.Find('poly').JSONType = jtString then
    begin
      want := sr.Strings['poly'];
      Inc(FCompared);
      if poly <> want then
        Bad(Format('%s series %d: the polyline %s, upstream %s', [who, s,
          StringReplace(poly, #0, '(none)', []), want]));
    end;
  end;
  if AState.Find('tip').JSONType = jtString then
  begin
    Inc(FCompared);
    if not AChart.TooltipShown then
      Bad(Format('%s: no box, upstream %s', [who, AState.Strings['tip']]))
    else if AChart.Which <> AState.Strings['tip'] then
      Bad(Format('%s: the box shows %s, upstream %s', [who, AChart.Which, AState.Strings['tip']]));
  end;
end;

procedure TAeOracleBase.RunCase(const AId: string);
var
  cases, charts, steps: TJSONArray;
  cs, st: TJSONObject;
  probes: array of TAeProbe;
  i, j, c: Integer;
  op, group: string;
  now_: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  charts := cs.Arrays['charts'];
  SetLength(probes, charts.Count);
  for i := 0 to High(probes) do probes[i] := nil;
  group := '';
  if cs.Find('group').JSONType = jtString then group := cs.Strings['group'];
  try
    for i := 0 to charts.Count - 1 do
    begin
      probes[i] := NewProbe(charts.Objects[i].Objects['option'].AsJSON, i);
      if group <> '' then probes[i].Group := group;
    end;
    if group <> '' then TyChartConnect(group);
    now_ := 0;
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      op := st.Strings['op'];
      FWhere := Format('%s step %d (%s)', [AId, j, op]);
      FLog.Clear;
      if (op = 'move') or (op = 'click') or (op = 'leave') then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else if op = 'idle' then
        now_ := now_ + st.Floats['ms'];
      if op <> 'action' then
        for i := 0 to High(probes) do
        begin
          probes[i].TooltipNow := now_;
          probes[i].TooltipTick(now_);
        end;
      if op <> 'idle' then c := st.Integers['chart'] else c := -1;
      if op = 'move' then
        probes[c].Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'click' then
        probes[c].Click(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'leave' then
        probes[c].Leave
      else if op = 'action' then
        probes[c].DispatchAction(StringReplace(st.Objects['payload'].AsJSON, cNulMark,
          '\u0000', [rfReplaceAll]));
      for i := 0 to High(probes) do
        probes[i].Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      CompareEvents(st.Arrays['events']);
      for i := 0 to High(probes) do
        CompareState(probes[i], st.Arrays['state'].Objects[i], i);
    end;
  finally
    if group <> '' then TyChartDisconnect(group);
    for i := 0 to High(probes) do probes[i].Free;
  end;
  Finish(AId);
end;

procedure TAdvChartAxisEmphasisOracleTest.TestTheDefaultAsUpstream;
begin
  RunCase('default');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestTheRootSaysNoAsUpstream;
begin
  RunCase('root-off');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestTheAxisSaysNoAsUpstream;
begin
  RunCase('axis-off');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestTheTooltipKeyIsDeadAsUpstream;
begin
  RunCase('tooltip-key');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestACategoryCrossArmAsUpstream;
begin
  RunCase('cross-cat');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestNoBlurAsUpstream;
begin
  RunCase('focus');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestAnItemSeriesStaysDownAsUpstream;
begin
  RunCase('series-item');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestTheActionsAsUpstream;
begin
  RunCase('actions');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestAConnectedPairAsUpstream;
begin
  RunCase('pair');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestALineWithoutSymbolsAsUpstream;
begin
  RunCase('no-symbol');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestLinkedAxesAsUpstream;
begin
  RunCase('link');
end;

procedure TAdvChartAxisEmphasisOracleTest.TestTheRootsNoLiftsNothing;
const
  cOpt = '{%s"tooltip":{"trigger":"axis"},"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[5,8,3],"itemStyle":{"color":"#3366cc"}}]}';

  { the colour at the low last bar's left edge + 3 before and after the
    pointer stands in its column above it (not on the bar: hovering the bar
    itself would light it) }
  function Changed(const ARoot: string): Boolean;
  var
    probe: TAeProbe;
    x, y, bx, by, top: Integer;
    c0, c1: TBGRAPixel;
  begin
    probe := NewProbe(Format(cOpt, [ARoot]), 0);
    try
      bx := -1;
      by := -1;
      for y := cH - 1 downto 0 do
      begin
        for x := 2 * cW div 3 to cW - 1 do
        begin
          c0 := FBmp.GetPixel(x, y);
          if (c0.red = $33) and (c0.green = $66) and (c0.blue = $CC) then
          begin
            bx := x + 3;
            by := y - 5;
            Break;
          end;
        end;
        if bx >= 0 then Break;
      end;
      AssertTrue('the last bar is drawn', bx >= 0);
      top := by;
      while (top > 0) and (FBmp.GetPixel(bx, top - 1).blue = $CC) do Dec(top);
      c0 := FBmp.GetPixel(bx, by);
      probe.Move(bx, top - 30);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      c1 := FBmp.GetPixel(bx, by);
      Result := (c0.red <> c1.red) or (c0.green <> c1.green) or (c0.blue <> c1.blue);
    finally
      probe.Free;
    end;
  end;

begin
  { the default: the highlight lifts it }
  AssertTrue('lit by default', Changed(''));
  { the root says no: no highlight, and nothing painted lifted either }
  AssertFalse('not lit when the root says no', Changed('"axisPointer":{"triggerEmphasis":false},'));
end;

procedure TAdvChartAxisEmphasisOracleTest.TestAPolarAsUpstream;
begin
  RunCase('polar');
end;

{ ==================== sunburst-legacy ==================== }

function TAdvChartSunburstLegacyOracleTest.FixtureName: string;
begin
  Result := 'advchart-sunburst-legacy.json';
end;

procedure TAdvChartSunburstLegacyOracleTest.TestOneSunburstAsUpstream;
begin
  RunCase('one');
end;

procedure TAdvChartSunburstLegacyOracleTest.TestTwoSunburstsAsUpstream;
begin
  RunCase('two');
end;

{ ==================== tooltip-sources ==================== }

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

procedure TAdvChartTooltipSourcesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-tooltip-sources.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartTooltipSourcesOracleTest.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartTooltipSourcesOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartTooltipSourcesOracleTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if HexOf(AGot) <> LowerCase(AHex) then
    Bad(Format('%s %s, upstream %s', [AWhat, FloatToStr(AGot), AHex]));
end;

function TAdvChartTooltipSourcesOracleTest.NewProbe(const AOptionJson: string;
  ATag: Integer): TAeProbe;
begin
  Result := TAeProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  Result.Tag := ATag;
  Result.TooltipNow := 0;
  Result.SetBounds(0, 0, cW, cH);
  Result.Option := AOptionJson;
  Result.OnChartEvent := @OnEvent;
  Result.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartTooltipSourcesOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType <> 'updateaxispointer') and (AEvent.EventType <> 'showtip')
    and (AEvent.EventType <> 'hidetip') then Exit;
  FLog.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAdvChartTooltipSourcesOracleTest.CompareState(AChart: TAeProbe;
  AState: TJSONObject);
const
  cTypeName: array[TTyAxisPointerType] of string = ('line', 'shadow', 'cross', 'none');
var
  axes: TJSONArray;
  ax, tip: TJSONObject;
  hits: TTyAxisHitArray;
  k, c, h, n: Integer;
  which, want: string;
  box: TTyRectF;
  at: TTyPointF;
begin
  hits := AChart.Hits;
  axes := AState.Arrays['axes'];
  n := 0;
  for k := 0 to axes.Count - 1 do
  begin
    ax := axes.Objects[k];
    h := -1;
    for c := 0 to High(hits) do
      if (hits[c].Axis.Dim = ax.Strings['dim'])
        and (hits[c].Axis.ComponentIndex = ax.Integers['index']) then h := c;
    Inc(FCompared);
    if (ax.Strings['status'] = 'show') <> (h >= 0) then
    begin
      Bad(Format('%s: shown %s, upstream %s', [ax.Strings['key'],
        BoolToStr(h >= 0, True), ax.Strings['status']]));
      Continue;
    end;
    if h < 0 then Continue;
    Inc(n);
    Inc(FCompared);
    if cTypeName[hits[h].Spec.PointerType] <> ax.Strings['type'] then
      Bad(Format('%s: a %s pointer, upstream %s', [ax.Strings['key'],
        cTypeName[hits[h].Spec.PointerType], ax.Strings['type']]));
    Inc(FCompared);
    if hits[h].Spec.LabelSpec.Show <> ax.Booleans['label'] then
      Bad(Format('%s: label %s, upstream %s', [ax.Strings['key'],
        BoolToStr(hits[h].Spec.LabelSpec.Show, True), BoolToStr(ax.Booleans['label'], True)]));
  end;
  Inc(FCompared);
  if n <> Length(hits) then
    Bad(Format('%d pointers, upstream %d', [Length(hits), n]));
  if AState.Find('tip').JSONType = jtNull then Exit;
  tip := AState.Objects['tip'];
  Inc(FCompared);
  if AChart.TooltipShown <> tip.Booleans['visible'] then
  begin
    Bad(Format('box shown %s, upstream %s', [BoolToStr(AChart.TooltipShown, True),
      BoolToStr(tip.Booleans['visible'], True)]));
    Exit;
  end;
  if not AChart.TooltipShown then Exit;
  which := AChart.TooltipShownWhich;
  if which <> 'proxy' then which := AChart.Which;
  Inc(FCompared);
  if which <> tip.Strings['which'] then
    Bad(Format('the box shows %s, upstream %s', [which, tip.Strings['which']]));
  { the text: a formatter's, or 'default' -- the default markup, no
    formatter text }
  want := '';
  if tip.Find('text').JSONType = jtString then want := tip.Strings['text'];
  if want = 'default' then want := '';
  Inc(FCompared);
  if AChart.TooltipFormatterText <> want then
    Bad(Format('the text %s, upstream %s', [AChart.TooltipFormatterText, tip.Strings['text']]));
  at := AChart.TooltipAnchorF;
  Same('anchor x', at.X, tip.Arrays['anchor'].Strings[0]);
  Same('anchor y', at.Y, tip.Arrays['anchor'].Strings[1]);
  box := AChart.TooltipBox;
  Same('box x', box.Left, tip.Arrays['box'].Strings[0]);
  Same('box y', box.Top, tip.Arrays['box'].Strings[1]);
end;

procedure TAdvChartTooltipSourcesOracleTest.RunCase(const AId: string);
var
  cases, steps, want: TJSONArray;
  cs, st: TJSONObject;
  probe: TAeProbe;
  i, j: Integer;
  op: string;
  now_: Double;
  e: TJSONArray;
  parts: TStringList;
  got: TJSONData;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  probe := NewProbe(cs.Arrays['charts'].Objects[0].Objects['option'].AsJSON, 0);
  parts := TStringList.Create;
  try
    parts.Delimiter := #9;
    parts.StrictDelimiter := True;
    now_ := 0;
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      op := st.Strings['op'];
      FWhere := Format('%s step %d (%s)', [AId, j, op]);
      FLog.Clear;
      if (op = 'move') or (op = 'leave') then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else if op = 'idle' then
        now_ := now_ + st.Floats['ms'];
      if op <> 'action' then
      begin
        probe.TooltipNow := now_;
        probe.TooltipTick(now_);
      end;
      if op = 'move' then
        probe.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'leave' then
        probe.Leave
      else if op = 'action' then
        probe.DispatchAction(StringReplace(st.Objects['payload'].AsJSON, cNulMark,
          '\u0000', [rfReplaceAll]));
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      { the events }
      want := st.Arrays['events'];
      Inc(FCompared);
      if FLog.Count <> want.Count then
        Bad(Format('%d events, upstream %d', [FLog.Count, want.Count]))
      else
        for i := 0 to want.Count - 1 do
        begin
          e := TJSONArray(want.Items[i]);
          parts.DelimitedText := FLog[i];
          Inc(FCompared);
          if parts[0] <> e.Strings[1] then
          begin
            Bad(Format('event %d: %s, upstream %s', [i, parts[0], e.Strings[1]]));
            Continue;
          end;
          got := ParsePort(parts[1]);
          try
            Inc(FCompared);
            if not SameJson(e.Items[2], got) then
              Bad(Format('event %d (%s): %s, upstream %s', [i, parts[0],
                Copy(got.AsJSON, 1, 300), Copy(e.Items[2].AsJSON, 1, 300)]));
          finally
            got.Free;
          end;
        end;
      CompareState(probe, st.Arrays['state'].Objects[0]);
    end;
  finally
    parts.Free;
    probe.Free;
  end;
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartTooltipSourcesOracleTest.TestAGridFormatterAsUpstream;
begin
  RunCase('grid-item');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestTheSeriesOverItsGridAsUpstream;
begin
  RunCase('grid-series');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestAGridTriggerAsUpstream;
begin
  RunCase('grid-trigger');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestAGridCrossAsUpstream;
begin
  RunCase('grid-cross');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestAGridShadowAsUpstream;
begin
  RunCase('grid-shadow');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestAGridHiddenAsUpstream;
begin
  RunCase('grid-hidden');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestAPolarTriggerAsUpstream;
begin
  RunCase('polar');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestASingleAxisAsUpstream;
begin
  RunCase('single');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestACalendarIsNotReadAsUpstream;
begin
  RunCase('calendar');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestTheProxyAsUpstream;
begin
  RunCase('proxy');
end;

procedure TAdvChartTooltipSourcesOracleTest.TestTheTooltipOptionAsUpstream;
begin
  RunCase('tooltip-option');
end;

initialization
  RegisterTest(TAdvChartAxisEmphasisOracleTest);
  RegisterTest(TAdvChartSunburstLegacyOracleTest);
  RegisterTest(TAdvChartTooltipSourcesOracleTest);
end.
