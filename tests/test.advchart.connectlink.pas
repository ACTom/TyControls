unit test.advchart.connectlink;
{$mode objfpc}{$H+}
{ axisPointer.link, echarts.connect, batch actions and the combined export,
  HELD TO UPSTREAM [Batch 141, roadmap D8].

  tools/advchart-oracle/connect-link-batch.js runs the real ECharts 6.1
  build in node with several chart instances in one process and records:
    revertMap    the event -> action map echarts.connect broadcasts by;
    link         per pointer step: every axisInfo's status, value and
                 seriesDataIndices, showTip's dataByCoordSys and the
                 mapper's calls;
    connect      per step of a group of charts (connect, disconnect,
    batch        chart.group, dispatchAction, a wheel): every event every
                 chart published, in order, and each chart's state (the
                 legends' selected maps, the dataZoom windows, the
                 selections, the timeline's index, the brushes' areas);
    exportCases  getConnectedDataURL's canvas size and where each chart's
                 image goes.

  This replays them through TTyAdvanceChart: the pointer through MouseMove /
  MouseLeave (the hits through TipHits), the actions through DispatchAction,
  the groups through Group / TyChartConnect / TyChartDisconnect, the wheel
  through DataZoomPointer, the layout through TyConnectedLayoutOf. Text is
  measured with zrender's SSR width table. Every NUL of an auto id is
  written U+2400 on both sides; a `from` (a view uid) is '<view uid>'. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Handlers, tyControls.AdvanceChart.Coord,
     tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Events, tyControls.AdvanceChart.Series,
     tyControls.AdvanceChart.DataZoom, tyControls.AdvanceChart.DataZoomAct,
     tyControls.AdvanceChart.Brush, tyControls.AdvanceChart.Timeline,
     tyControls.AdvanceChart.Connect,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TClProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Leave;
    function Hits: TTyAxisHitArray;
    { the value the chart puts the pointer at: the axisPointer model's
      value upstream (milestone D5-D8: the suite read its own copy of the
      rule, so a pointer drawn elsewhere passed) }
    function PointerValueOf(const AHit: TTyAxisHit): Double;
  end;

  { saveAsImage's file name answered without a dialog }
  TClSaveProbe = class(TClProbe)
  protected
    function ToolboxAskFileName(var AFileName: string; const AType: string): Boolean; override;
  public
    SaveTo: string;
  end;

  { the oracle's mappers, in Pascal, logging their calls }
  TClMappers = class
  public
    Log: TStrings;
    constructor Create;
    destructor Destroy; override;
    function Note(const AName: string; AValue: Double;
      const ASource, ATarget: TTyChartMapperAxis): string;
    function Double_(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
    function Half(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
    function Shift(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
    function Hundred(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
  end;

  TAdvChartConnectLinkOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FMappers: TClMappers;
    FLog: TStrings;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure Finish(const AWhat: string);
    function Ssr: ITyTextMeasurer;
    function NewProbe(const AOptionJson: string; AW, AH, ATag: Integer): TClProbe;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure RunLinkCase(ACase: TJSONObject);
    procedure RunGroupCase(ACase: TJSONObject);
    procedure CompareState(AChart: TClProbe; AState: TJSONObject; AIndex: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRevertMapIsUpstreams;
    procedure TestLinkedAxesFollowAsUpstreams;
    procedure TestConnectedChartsAsUpstreams;
    procedure TestBatchActionsAsUpstreams;
    procedure TestTheCombinedLayoutIsUpstreams;
  end;

  TAdvChartConnectLinkTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FLog: TStrings;
    function NewChart(const AOptionJson: string; AX, AY, AW, AH: Integer): TTyAdvanceChart;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCombinedExportPutsEachChartInItsPlace;
    procedure TestNotConnectedIsTheChartsOwnExport;
    procedure TestADestroyedChartLeavesItsGroup;
    procedure TestConnectingAListKeepsOrMakesAGroup;
    procedure TestAnUnregisteredMapperMapsNothing;
    procedure TestTheAxisBreakActionsTravel;
    procedure TestTheApiDataZoomPublishesItsPayload;
    procedure TestSaveAsImageSavesTheConnectedGroup;
    procedure TestALegendBatchUpdatesOnce;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cNulMark = #$E2#$90#$80;

{ ==================== helpers ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

{ the port's text, NULs as U+2400 }
function Marked(const S: string): string;
begin
  Result := StringReplace(S, #0, cNulMark, [rfReplaceAll]);
end;

{ a fixture payload back to what upstream dispatched: U+2400 as \u0000 }
function Unmarked(const AJson: string): string;
begin
  Result := StringReplace(AJson, cNulMark, '\u0000', [rfReplaceAll]);
end;

{ a payload the port published, parsed with its NULs marked and every
  `from` string a view uid }
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

{ A BRUSH AREA whole, generateBrushOption's object and the area's own keys
  (milestone D5-D8; batches 126-141 reduced both sides to brushType,
  coordRange, range and panelId). The brush's DEFAULT colours are the
  skin's, as a palette is: where the option wrote none, brushStyle's fill
  and stroke are set aside on both sides. }
procedure SkinAreas(AData: TJSONData);
var
  i, k: Integer;
  arr: TJSONArray;
  st: TJSONData;
begin
  if AData = nil then Exit;
  if AData is TJSONObject then
  begin
    for i := 0 to AData.Count - 1 do
      if (TJSONObject(AData).Names[i] = 'areas') and (AData.Items[i] is TJSONArray) then
      begin
        arr := TJSONArray(AData.Items[i]);
        for k := 0 to arr.Count - 1 do
        begin
          if not (arr.Items[k] is TJSONObject) then Continue;
          st := TJSONObject(arr.Items[k]).Find('brushStyle');
          if not (st is TJSONObject) then Continue;
          if TJSONObject(st).IndexOfName('fill') >= 0 then
            TJSONObject(st).Strings['fill'] := '<skin>';
          if TJSONObject(st).IndexOfName('stroke') >= 0 then
            TJSONObject(st).Strings['stroke'] := '<skin>';
        end;
      end
      else
        SkinAreas(AData.Items[i]);
  end
  else if AData is TJSONArray then
    for i := 0 to AData.Count - 1 do SkinAreas(AData.Items[i]);
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

{ the pointer's value as upstream's option.value holds it }
function SdiText(AChart: TClProbe; const AHit: TTyAxisHit): string;
var
  k: Integer;
  st: TTyDataStore;
  s: Integer;
begin
  Result := '';
  for k := 0 to High(AHit.Slots) do
  begin
    s := AChart.SlotSeriesIndex(AHit.Slots[k]);
    st := AChart.SeriesStore(s);
    if k > 0 then Result := Result + ';';
    Result := Result + IntToStr(s) + ',' + IntToStr(st.GetRawIndex(AHit.Rows[k]))
      + ',' + IntToStr(AHit.Rows[k]);
  end;
end;

function FixSdiText(AArr: TJSONArray): string;
var k: Integer;
begin
  Result := '';
  for k := 0 to AArr.Count - 1 do
  begin
    if k > 0 then Result := Result + ';';
    Result := Result + IntToStr(TJSONArray(AArr.Items[k]).Integers[0]) + ','
      + IntToStr(TJSONArray(AArr.Items[k]).Integers[1]) + ','
      + IntToStr(TJSONArray(AArr.Items[k]).Integers[2]);
  end;
end;

{ ==================== the probe ==================== }

function TClProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TClProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TClProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TClProbe.Leave;
begin
  MouseLeave;
end;

function TClProbe.PointerValueOf(const AHit: TTyAxisHit): Double;
begin
  Result := PointerValue(AHit);
end;

function TClProbe.Hits: TTyAxisHitArray;
begin
  Result := TipHits;
end;

function TClSaveProbe.ToolboxAskFileName(var AFileName: string;
  const AType: string): Boolean;
begin
  AFileName := SaveTo;
  Result := True;
end;

{ ==================== the mappers ==================== }

constructor TClMappers.Create;
begin
  inherited Create;
  Log := TStringList.Create;
end;

destructor TClMappers.Destroy;
begin
  Log.Free;
  inherited Destroy;
end;

function AxisParamText(const A: TTyChartMapperAxis): string;
begin
  Result := A.AxisDim + '|' + IntToStr(A.AxisIndex) + '|' + Marked(A.AxisName)
    + '|' + Marked(A.AxisId);
end;

function TClMappers.Note(const AName: string; AValue: Double;
  const ASource, ATarget: TTyChartMapperAxis): string;
begin
  Result := AName + ' ' + HexOf(AValue) + ' ' + AxisParamText(ASource) + ' '
    + AxisParamText(ATarget);
  Log.Add(Result);
end;

function TClMappers.Double_(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
begin
  Note('Double', AValue, ASource, ATarget);
  Result := AValue * 2;
end;

function TClMappers.Half(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
begin
  Note('Half', AValue, ASource, ATarget);
  Result := AValue / 2;
end;

function TClMappers.Shift(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
begin
  Note('Shift', AValue, ASource, ATarget);
  Result := AValue + 1;
end;

function TClMappers.Hundred(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
begin
  Note('Hundred', AValue, ASource, ATarget);
  Result := AValue * 100;
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartConnectLinkOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-connect-link-batch.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FMappers := TClMappers.Create;
  TyChartRegisterAxisPointerMapper('Double', @FMappers.Double_);
  TyChartRegisterAxisPointerMapper('Half', @FMappers.Half);
  TyChartRegisterAxisPointerMapper('Shift', @FMappers.Shift);
  TyChartRegisterAxisPointerMapper('Hundred', @FMappers.Hundred);
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartConnectLinkOracleTest.TearDown;
begin
  TyChartClearAxisPointerMappers;
  FMappers.Free;
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartConnectLinkOracleTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartConnectLinkOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartConnectLinkOracleTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if HexOf(AGot) <> LowerCase(AHex) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartConnectLinkOracleTest.Finish(const AWhat: string);
begin
  if GetEnvironmentVariable('TY_CONNECTLINK_COUNTS') = '1' then
    WriteLn(StdErr, AWhat, ': ', FCompared, ' comparisons');
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartConnectLinkOracleTest.NewProbe(const AOptionJson: string;
  AW, AH, ATag: Integer): TClProbe;
begin
  Result := TClProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Measurer := Ssr;
  Result.Tag := ATag;
  Result.TooltipNow := 0;
  Result.BrushNow := 0;
  Result.SetBounds(0, 0, AW, AH);
  Result.Option := AOptionJson;
  Result.OnChartEvent := @OnEvent;
  Result.ChartOn('updated', @OnEvent);
  Result.Render(FBmp.Canvas, Rect(0, 0, AW, AH), 96);
end;

procedure TAdvChartConnectLinkOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  { the action events (a payload) and updated; not the mouse's }
  if (AEvent.Payload = '') and (AEvent.EventType <> 'updated') then Exit;
  FLog.Add(IntToStr(TComponent(Sender).Tag) + #9 + AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAdvChartConnectLinkOracleTest.TestTheRevertMapIsUpstreams;
var
  map: TJSONObject;
  i: Integer;
  act: string;
begin
  FWhere := 'revertMap';
  map := TJSONObject(FRoot).Objects['revertMap'];
  Inc(FCompared);
  if map.Count <> TyConnectEventCount then
    Bad(Format('%d events, upstream %d', [TyConnectEventCount, map.Count]));
  for i := 0 to map.Count - 1 do
  begin
    Inc(FCompared);
    if TyConnectEventAt(i, act) <> map.Names[i] then
      Bad(Format('entry %d is %s, upstream %s', [i, TyConnectEventAt(i, act), map.Names[i]]));
    Inc(FCompared);
    if TyConnectActionOf(map.Names[i]) <> map.Items[i].AsString then
      Bad(Format('%s -> %s, upstream %s', [map.Names[i], TyConnectActionOf(map.Names[i]),
        map.Items[i].AsString]));
  end;
  { what never travels }
  Inc(FCompared);
  if (TyConnectActionOf('selectchanged') <> '') or (TyConnectActionOf('updated') <> '')
    or (TyConnectActionOf('axisbreakchanged') <> '') or (TyConnectActionOf('click') <> '')
    or (TyConnectActionOf('pieselected') <> '') then
    Bad('an event that does not travel maps to an action');
  Finish('revert map');
end;

procedure TAdvChartConnectLinkOracleTest.RunLinkCase(ACase: TJSONObject);
var
  chart: TClProbe;
  steps, axes, tip, tipAxes, calls: TJSONArray;
  st, ax, src, tar: TJSONObject;
  i, k, c, h, n: Integer;
  hits: TTyAxisHitArray;
  shownHits: array of Integer;
  want: string;
  found: Boolean;
begin
  chart := NewProbe(ACase.Objects['option'].AsJSON, cW, cH, 0);
  try
    steps := ACase.Arrays['steps'];
    for i := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[i];
      FWhere := Format('%s step %d', [ACase.Strings['id'], i]);
      FMappers.Log.Clear;
      if st.Items[st.IndexOfName('at')].JSONType = jtString then chart.Leave
      else chart.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1]);
      chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      hits := chart.Hits;
      { every axisInfo: shown with its value and its series' rows, or not }
      axes := st.Arrays['axes'];
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
        Same(ax.Strings['key'] + ' value', chart.PointerValueOf(hits[h]), ax.Strings['value']);
        Inc(FCompared);
        if SdiText(chart, hits[h]) <> FixSdiText(ax.Arrays['sdi']) then
          Bad(Format('%s rows %s, upstream %s', [ax.Strings['key'],
            SdiText(chart, hits[h]), FixSdiText(ax.Arrays['sdi'])]));
      end;
      Inc(FCompared);
      if Length(hits) <> 0 then
      begin
        n := 0;
        for k := 0 to axes.Count - 1 do
          if axes.Objects[k].Strings['status'] = 'show' then Inc(n);
        if n <> Length(hits) then
          Bad(Format('%d pointers, upstream %d', [Length(hits), n]));
      end;
      { the tooltip: the axes with a tooltip and rows, in dataByCoordSys'
        order }
      shownHits := nil;
      for c := 0 to High(hits) do
        if not hits[c].Cross and (Length(hits[c].Slots) > 0) then
        begin
          SetLength(shownHits, Length(shownHits) + 1);
          shownHits[High(shownHits)] := c;
        end;
      tipAxes := TJSONArray.Create;
      try
        if st.Items[st.IndexOfName('tip')] is TJSONArray then
        begin
          tip := st.Arrays['tip'];
          for k := 0 to tip.Count - 1 do
            for c := 0 to tip.Objects[k].Arrays['axes'].Count - 1 do
              tipAxes.Add(tip.Objects[k].Arrays['axes'].Objects[c].Clone);
        end;
        Inc(FCompared);
        if tipAxes.Count <> Length(shownHits) then
          Bad(Format('tooltip of %d axes, upstream %d', [Length(shownHits), tipAxes.Count]))
        else
          for k := 0 to tipAxes.Count - 1 do
          begin
            ax := tipAxes.Objects[k];
            h := shownHits[k];
            Inc(FCompared);
            if (hits[h].Axis.Dim <> ax.Strings['dim'])
              or (hits[h].Axis.ComponentIndex <> ax.Integers['index']) then
              Bad(Format('tooltip axis %d is %s%d, upstream %s%d', [k, hits[h].Axis.Dim,
                hits[h].Axis.ComponentIndex, ax.Strings['dim'], ax.Integers['index']]))
            else
            begin
              Same(Format('tooltip axis %d value', [k]), hits[h].SnapValue, ax.Strings['value']);
              Inc(FCompared);
              if SdiText(chart, hits[h]) <> FixSdiText(ax.Arrays['sdi']) then
                Bad(Format('tooltip axis %d rows %s, upstream %s', [k,
                  SdiText(chart, hits[h]), FixSdiText(ax.Arrays['sdi'])]));
            end;
          end;
      finally
        tipAxes.Free;
      end;
      { the mapper's calls }
      calls := st.Arrays['mapper'];
      Inc(FCompared);
      if calls.Count <> FMappers.Log.Count then
        Bad(Format('%d mapper calls, upstream %d', [FMappers.Log.Count, calls.Count]))
      else
        for k := 0 to calls.Count - 1 do
        begin
          src := calls.Objects[k].Objects['src'];
          tar := calls.Objects[k].Objects['tar'];
          want := calls.Objects[k].Strings['fn'] + ' ' + calls.Objects[k].Strings['value']
            + ' ' + src.Strings['axisDim'] + '|' + IntToStr(src.Integers['axisIndex'])
            + '|' + src.Strings['axisName'] + '|' + src.Strings['axisId']
            + ' ' + tar.Strings['axisDim'] + '|' + IntToStr(tar.Integers['axisIndex'])
            + '|' + tar.Strings['axisName'] + '|' + tar.Strings['axisId'];
          Inc(FCompared);
          if FMappers.Log[k] <> want then
            Bad(Format('mapper call %d: %s, upstream %s', [k, FMappers.Log[k], want]));
        end;
      found := True;
      if not found then Bad('unreachable');
    end;
  finally
    chart.Free;
  end;
end;

procedure TAdvChartConnectLinkOracleTest.TestLinkedAxesFollowAsUpstreams;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['link'];
  for i := 0 to cases.Count - 1 do RunLinkCase(cases.Objects[i]);
  Finish('axisPointer.link');
end;

procedure TAdvChartConnectLinkOracleTest.CompareState(AChart: TClProbe;
  AState: TJSONObject; AIndex: Integer);
var
  arr: TJSONArray;
  k, host, m: Integer;
  want, got: TJSONData;
  spec: TTyDataZoomSpec;
  z: TTyAxisZoom;
  w: TTyDzWindow;
  sel: TTyIntegerArray;
  s1, s2: string;
begin
  arr := AState.Arrays['legend'];
  for k := 0 to arr.Count - 1 do
  begin
    Inc(FCompared);
    want := GetJSON(arr.Strings[k]);
    got := GetJSON(AChart.LegendSelectedText(k));
    try
      if not SameJson(want, got) then
        Bad(Format('chart %d legend %d %s, upstream %s', [AIndex, k,
          AChart.LegendSelectedText(k), arr.Strings[k]]));
    finally
      want.Free;
      got.Free;
    end;
  end;
  arr := AState.Arrays['dz'];
  for k := 0 to arr.Count - 1 do
  begin
    spec := AChart.DataZoomSpec(k);
    Inc(FCompared);
    if (Length(spec.Targets) = 0) or not AChart.AxisZoom(spec.Targets[0].Dim + 'Axis',
      spec.Targets[0].AxisIndex, z, w, host) then
    begin
      Bad(Format('chart %d dataZoom %d has no window', [AIndex, k]));
      Continue;
    end;
    Same(Format('chart %d dataZoom %d start', [AIndex, k]), w.Percent[0],
      TJSONArray(arr.Items[k]).Strings[0]);
    Same(Format('chart %d dataZoom %d end', [AIndex, k]), w.Percent[1],
      TJSONArray(arr.Items[k]).Strings[1]);
  end;
  arr := AState.Arrays['sel'];
  for k := 0 to arr.Count - 1 do
  begin
    sel := AChart.SelectedDataIndices(arr.Objects[k].Integers['s']);
    s1 := '';
    for m := 0 to High(sel) do s1 := s1 + IntToStr(sel[m]) + ',';
    s2 := '';
    for m := 0 to arr.Objects[k].Arrays['idx'].Count - 1 do
      s2 := s2 + IntToStr(arr.Objects[k].Arrays['idx'].Integers[m]) + ',';
    Inc(FCompared);
    if s1 <> s2 then
      Bad(Format('chart %d series %d selected [%s], upstream [%s]', [AIndex,
        arr.Objects[k].Integers['s'], s1, s2]));
  end;
  if AState.Items[AState.IndexOfName('tl')].JSONType = jtNumber then
  begin
    Inc(FCompared);
    if (AChart.TimelineView = nil)
      or (AChart.TimelineView.CurrentIndex <> AState.Floats['tl']) then
      Bad(Format('chart %d timeline index, upstream %s', [AIndex, AState.Items[AState.IndexOfName('tl')].AsString]));
  end;
  arr := AState.Arrays['brush'];
  for k := 0 to arr.Count - 1 do
  begin
    Inc(FCompared);
    if Length(AChart.BrushModelAreas(k)) <> arr.Integers[k] then
      Bad(Format('chart %d brush %d holds %d areas, upstream %d', [AIndex, k,
        Length(AChart.BrushModelAreas(k)), arr.Integers[k]]));
  end;
end;

procedure TAdvChartConnectLinkOracleTest.RunGroupCase(ACase: TJSONObject);
var
  charts: array of TClProbe;
  defs, steps, list, evs, states: TJSONArray;
  st: TJSONObject;
  i, k, c, n: Integer;
  op, ret, line, typ, payload: string;
  list_: array of TTyCustomAdvanceChart;
  t: Double;
  want, got: TJSONData;
  parts: TStringArray;
  ws, hs: array of Integer;
begin
  defs := ACase.Arrays['charts'];
  SetLength(charts, defs.Count);
  SetLength(ws, defs.Count);
  SetLength(hs, defs.Count);
  for i := 0 to High(charts) do charts[i] := nil;
  try
    for i := 0 to defs.Count - 1 do
    begin
      ws[i] := defs.Objects[i].Integers['w'];
      hs[i] := defs.Objects[i].Integers['h'];
      charts[i] := NewProbe(defs.Objects[i].Objects['option'].AsJSON, ws[i], hs[i], i);
    end;
    t := 0;
    steps := ACase.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      op := st.Strings['op'];
      FWhere := Format('%s step %d (%s)', [ACase.Strings['id'], k, op]);
      FLog.Clear;
      ret := '';
      if op = 'group' then
      begin
        if st.Items[st.IndexOfName('value')].JSONType = jtNull then
          charts[st.Integers['chart']].Group := ''
        else
          charts[st.Integers['chart']].Group := st.Strings['value'];
      end
      else if op = 'connect' then
        ret := TyChartConnect(st.Strings['group'])
      else if op = 'connectList' then
      begin
        list := st.Arrays['charts'];
        SetLength(list_, list.Count);
        for c := 0 to list.Count - 1 do list_[c] := charts[list.Integers[c]];
        ret := TyChartConnect(list_);
        if Copy(ret, 1, 2) = 'g_' then ret := 'g_<auto>';
      end
      else if op = 'disconnect' then
        TyChartDisconnect(st.Strings['group'])
      else if op = 'action' then
      begin
        n := st.IndexOfName('silent');
        charts[st.Integers['chart']].DispatchAction(Unmarked(st.Objects['payload'].AsJSON),
          (n >= 0) and (st.Items[n].JSONType = jtBoolean) and st.Items[n].AsBoolean);
      end
      else if op = 'wheel' then
      begin
        t := t + 200;
        for c := 0 to High(charts) do
        begin
          charts[c].DataZoomNow := t;
          charts[c].DataZoomTick(t);
        end;
        charts[st.Integers['chart']].DataZoomPointer(dpWheel, st.Floats['x'], st.Floats['y'],
          [], st.Floats['delta']);
      end
      else if op = 'idle' then
      begin
        t := t + st.Floats['ms'];
        for c := 0 to High(charts) do
        begin
          charts[c].DataZoomNow := t;
          charts[c].DataZoomTick(t);
        end;
      end
      { milestone D5-D8 }
      else if op = 'resize' then
      begin
        c := st.Integers['chart'];
        ws[c] := st.Integers['w'];
        hs[c] := st.Integers['h'];
        charts[c].SetBounds(0, 0, ws[c], hs[c]);
      end;
      for c := 0 to High(charts) do
        charts[c].Render(FBmp.Canvas, Rect(0, 0, ws[c], hs[c]), 96);
      if st.Items[st.IndexOfName('ret')].JSONType = jtString then
      begin
        Inc(FCompared);
        if ret <> st.Strings['ret'] then
          Bad(Format('connect answers %s, upstream %s', [ret, st.Strings['ret']]));
      end;
      { the events, in the order every chart's handlers heard them }
      evs := st.Arrays['events'];
      Inc(FCompared);
      if evs.Count <> FLog.Count then
      begin
        line := '';
        for c := 0 to FLog.Count - 1 do
          line := line + ' | ' + Copy(FLog[c], 1, Pos(#9, FLog[c]) - 1) + ' '
            + Copy(FLog[c], Pos(#9, FLog[c]) + 1, 24);
        Bad(Format('%d events, upstream %d:%s', [FLog.Count, evs.Count, line]));
      end;
      for c := 0 to Min(evs.Count, FLog.Count) - 1 do
      begin
        parts := FLog[c].Split([#9]);
        typ := TJSONArray(evs.Items[c]).Strings[1];
        Inc(FCompared);
        if (StrToInt(parts[0]) <> TJSONArray(evs.Items[c]).Integers[0]) or (parts[1] <> typ) then
        begin
          Bad(Format('event %d: chart %s %s, upstream chart %d %s', [c, parts[0], parts[1],
            TJSONArray(evs.Items[c]).Integers[0], typ]));
          Continue;
        end;
        if typ = 'updated' then Continue;
        payload := parts[2];
        want := TJSONArray(evs.Items[c]).Items[2].Clone;
        got := nil;
        try
          got := ParsePort(payload);
        except
          got := nil;
        end;
        try
          if (typ = 'brushselected') and (Pos('brushStyle', defs.AsJSON) = 0) then
          begin
            SkinAreas(want);
            SkinAreas(got);
          end;
          Inc(FCompared);
          if not SameJson(want, got) then
            Bad(Format('event %d %s: %s, upstream %s', [c, typ, payload, want.AsJSON]));
        finally
          got.Free;
          want.Free;
        end;
      end;
      states := st.Arrays['state'];
      for c := 0 to states.Count - 1 do CompareState(charts[c], states.Objects[c], c);
    end;
  finally
    for i := 0 to High(charts) do
      if charts[i] <> nil then
      begin
        if charts[i].Group <> '' then TyChartDisconnect(charts[i].Group);
        charts[i].Free;
      end;
  end;
end;

procedure TAdvChartConnectLinkOracleTest.TestConnectedChartsAsUpstreams;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['connect'];
  for i := 0 to cases.Count - 1 do RunGroupCase(cases.Objects[i]);
  Finish('connect');
end;

procedure TAdvChartConnectLinkOracleTest.TestBatchActionsAsUpstreams;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['batch'];
  for i := 0 to cases.Count - 1 do RunGroupCase(cases.Objects[i]);
  Finish('batch');
end;

procedure TAdvChartConnectLinkOracleTest.TestTheCombinedLayoutIsUpstreams;
var
  cases, rects, ops: TJSONArray;
  cs, opts, o: TJSONObject;
  i, k, img: Integer;
  r: TTyConnectedRectArray;
  lay: TTyConnectedLayout;
  dpr: Double;
  fills: Integer;
  bg: TJSONData;
begin
  cases := TJSONObject(FRoot).Arrays['exportCases'];
  for i := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[i];
    FWhere := cs.Strings['id'];
    if not cs.Booleans['connect'] then Continue;
    opts := cs.Objects['opts'];
    if opts.IndexOfName('pixelRatio') >= 0 then dpr := opts.Floats['pixelRatio'] else dpr := 1;
    rects := cs.Arrays['rects'];
    SetLength(r, rects.Count);
    for k := 0 to rects.Count - 1 do
    begin
      r[k].Left := rects.Objects[k].Floats['left'];
      r[k].Top := rects.Objects[k].Floats['top'];
      r[k].Width := rects.Objects[k].Floats['w'];
      r[k].Height := rects.Objects[k].Floats['h'];
    end;
    lay := TyConnectedLayoutOf(r, dpr);
    Same('canvas width', lay.Width, cs.Objects['canvas'].Strings['width']);
    Same('canvas height', lay.Height, cs.Objects['canvas'].Strings['height']);
    ops := cs.Arrays['ops'];
    img := 0;
    fills := 0;
    for k := 0 to ops.Count - 1 do
    begin
      o := ops.Objects[k];
      if o.Strings['op'] = 'fill' then
      begin
        Inc(fills);
        Continue;
      end;
      Inc(FCompared);
      if o.Integers['chart'] <> img then Bad(Format('image %d is chart %d', [img, o.Integers['chart']]));
      Same(Format('image %d x', [img]), lay.X[img], o.Strings['x']);
      Same(Format('image %d y', [img]), lay.Y[img], o.Strings['y']);
      Inc(img);
    end;
    { the port fills between the charts for a truthy background but 'none' }
    bg := opts.Find('connectedBackgroundColor');
    Inc(FCompared);
    if (fills > 0) <> ((bg <> nil) and (bg.JSONType = jtString) and (bg.AsString <> '')
      and (bg.AsString <> 'none')) then
      Bad(Format('%d background fills', [fills]));
  end;
  Finish('combined layout');
end;

{ ==================== the hand-written test ==================== }

procedure TAdvChartConnectLinkTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 800, 600);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FLog := TStringList.Create;
end;

procedure TAdvChartConnectLinkTest.TearDown;
begin
  TyChartClearAxisPointerMappers;
  FLog.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartConnectLinkTest.NewChart(const AOptionJson: string;
  AX, AY, AW, AH: Integer): TTyAdvanceChart;
var bmp: TBGRABitmap;
begin
  Result := TClProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.SetBounds(AX, AY, AW, AH);
  Result.Option := AOptionJson;
  Result.OnChartEvent := @OnEvent;
  bmp := TBGRABitmap.Create(AW, AH);
  try
    TClProbe(Result).Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartConnectLinkTest.OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if AEvent.Payload = '' then Exit;
  FLog.Add(TComponent(Sender).Name + ' ' + AEvent.EventType + ' ' + AEvent.Payload);
end;

function PixelAt(ABmp: TBGRABitmap; AX, AY: Integer): TBGRAPixel;
begin
  Result := ABmp.GetPixel(AX, AY);
end;

procedure TAdvChartConnectLinkTest.TestTheCombinedExportPutsEachChartInItsPlace;
var
  a, b, c: TTyAdvanceChart;
  bmp: TBGRABitmap;
  p: TBGRAPixel;
begin
  a := NewChart('{"backgroundColor":"#ff0000","series":[]}', 10, 20, 200, 150);
  b := NewChart('{"backgroundColor":"#00ff00","series":[]}', 230, 20, 160, 150);
  c := NewChart('{"backgroundColor":"#0000ff","series":[]}', 400, 60, 100, 80);
  a.Group := 'ex';
  b.Group := 'ex';
  c.Group := 'ex';
  TyChartConnect('ex');
  try
    bmp := b.RenderConnectedToBitmap('{"connectedBackgroundColor":"#336699"}');
    try
      { the union: 10..500 by 20..170 }
      AssertEquals('width', 490, bmp.Width);
      AssertEquals('height', 150, bmp.Height);
      p := PixelAt(bmp, 100, 75);
      AssertTrue('A at its place', (p.red = 255) and (p.green = 0) and (p.blue = 0));
      p := PixelAt(bmp, 300, 75);
      AssertTrue('B at its place', (p.red = 0) and (p.green = 255) and (p.blue = 0));
      p := PixelAt(bmp, 440, 80);
      AssertTrue('C at its place', (p.red = 0) and (p.green = 0) and (p.blue = 255));
      { between A and B, and below C }
      p := PixelAt(bmp, 215, 75);
      AssertTrue('the gap is the connected background',
        (p.red = $33) and (p.green = $66) and (p.blue = $99) and (p.alpha = 255));
      p := PixelAt(bmp, 440, 140);
      AssertTrue('below C too', (p.red = $33) and (p.green = $66) and (p.blue = $99));
    finally
      bmp.Free;
    end;
    { no background between: clear; twice the ratio: twice the size }
    bmp := a.RenderConnectedToBitmap('{"pixelRatio":2}');
    try
      AssertEquals('2x width', 980, bmp.Width);
      AssertEquals('2x height', 300, bmp.Height);
      AssertEquals('the gap is clear', 0, PixelAt(bmp, 430, 150).alpha);
      p := PixelAt(bmp, 600, 150);
      AssertTrue('B at twice its place', (p.green = 255) and (p.red = 0));
    finally
      bmp.Free;
    end;
    { 'none' is no fill }
    bmp := a.RenderConnectedToBitmap('{"connectedBackgroundColor":"none"}');
    try
      AssertEquals('none: the gap is clear', 0, PixelAt(bmp, 215, 75).alpha);
    finally
      bmp.Free;
    end;
    AssertTrue('a data URL', Pos('data:image/png;base64,', a.GetConnectedDataURL('')) = 1);
    AssertTrue('a jpeg URL', Pos('data:image/jpeg;base64,',
      a.GetConnectedDataURL('{"type":"jpeg"}')) = 1);
  finally
    TyChartDisconnect('ex');
  end;
end;

procedure TAdvChartConnectLinkTest.TestNotConnectedIsTheChartsOwnExport;
var
  a, b: TTyAdvanceChart;
  bmp: TBGRABitmap;
begin
  a := NewChart('{"backgroundColor":"#ff0000","series":[]}', 10, 20, 200, 150);
  b := NewChart('{"backgroundColor":"#00ff00","series":[]}', 230, 20, 160, 150);
  a.Group := 'nc';
  b.Group := 'nc';
  { grouped but never connected: getDataURL }
  bmp := a.RenderConnectedToBitmap('');
  try
    AssertEquals('own width', 200, bmp.Width);
    AssertEquals('own height', 150, bmp.Height);
  finally
    bmp.Free;
  end;
  TyChartConnect('nc');
  TyChartDisconnect('nc');
  bmp := a.RenderConnectedToBitmap('');
  try
    AssertEquals('disconnected: own width', 200, bmp.Width);
  finally
    bmp.Free;
  end;
  AssertTrue('the group stays', b.Group = 'nc');
end;

procedure TAdvChartConnectLinkTest.TestADestroyedChartLeavesItsGroup;
const
  cOpt = '{"animation":false,"legend":{"data":["s1"]},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{},"series":[{"name":"s1","type":"bar","data":[1,2]}]}';
var
  a, b, c: TTyAdvanceChart;
  bmp: TBGRABitmap;
  i: Integer;
begin
  a := NewChart(cOpt, 0, 0, 300, 200);
  a.Name := 'A';
  b := NewChart(cOpt, 300, 0, 300, 200);
  b.Name := 'B';
  c := NewChart(cOpt, 0, 200, 300, 200);
  c.Name := 'C';
  TyChartConnect([a, b, c]);
  try
    FreeAndNil(b);
    FLog.Clear;
    AssertTrue(a.DispatchAction('{"type":"legendToggleSelect","name":"s1"}'));
    { the toggles (the brushselected each update publishes left aside) }
    for i := FLog.Count - 1 downto 0 do
      if Pos('legendselectchanged', FLog[i]) = 0 then FLog.Delete(i);
    AssertEquals('A and C only', 2, FLog.Count);
    AssertTrue(Pos('A legendselectchanged', FLog[0]) = 1);
    AssertTrue(Pos('C legendselectchanged', FLog[1]) = 1);
    AssertEquals('C toggled too', '{"s1":false}', c.LegendSelectedText(0));
    bmp := a.RenderConnectedToBitmap('');
    try
      AssertEquals('the export spans A and C', 400, bmp.Height);
      AssertEquals('the export spans A and C', 300, bmp.Width);
    finally
      bmp.Free;
    end;
  finally
    TyChartDisconnect(a.Group);
  end;
end;

procedure TAdvChartConnectLinkTest.TestConnectingAListKeepsOrMakesAGroup;
var
  a, b: TTyAdvanceChart;
  g1, g2: string;
begin
  a := NewChart('{"series":[]}', 0, 0, 100, 100);
  b := NewChart('{"series":[]}', 100, 0, 100, 100);
  g1 := TyChartConnect([a, b]);
  try
    AssertTrue('a new group', Copy(g1, 1, 2) = 'g_');
    AssertEquals(g1, a.Group);
    AssertEquals(g1, b.Group);
    AssertTrue(TyChartGroupConnected(g1));
    g2 := TyChartConnect([a, b]);
    AssertEquals('the group kept', g1, g2);
    b.Group := 'other';
    { the LAST chart with a group gives it }
    AssertEquals('other', TyChartConnect([a, b]));
    AssertEquals('other', a.Group);
    TyChartDisconnect('other');
    AssertFalse(TyChartGroupConnected('other'));
  finally
    TyChartDisconnect(g1);
    TyChartDisconnect('other');
  end;
end;

type
  TClRaw = class
    Calls: Integer;
    function Echo(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
  end;

function TClRaw.Echo(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double;
begin
  Inc(Calls);
  Result := AValue + 3;
end;

type
  TClHitProbe = class(TTyAdvanceChart)
  public
    function Hits: TTyAxisHitArray;
  end;

function TClHitProbe.Hits: TTyAxisHitArray;
begin
  Result := TipHits;
end;

procedure TAdvChartConnectLinkTest.TestAnUnregisteredMapperMapsNothing;
const
  cOpt = '{"animation":false,"tooltip":{"trigger":"axis"},'
    + '"axisPointer":{"link":[{"xAxisIndex":"all","mapper":"@%s"}]},'
    + '"grid":[{"left":40,"width":220,"top":40,"bottom":60},{"left":330,"width":220,"top":40,"bottom":60}],'
    + '"xAxis":[{"type":"value","min":0,"max":10},{"type":"value","gridIndex":1,"min":0,"max":10}],'
    + '"yAxis":[{},{"gridIndex":1}],'
    + '"series":[{"type":"line","data":[[1,1],[5,2]]},{"type":"line","xAxisIndex":1,"yAxisIndex":1,"data":[[2,1],[8,2]]}]}';
var
  ch: TClHitProbe;
  bmp: TBGRABitmap;
  raw: TClRaw;
  h: TTyAxisHitArray;
  i, linked: Integer;
begin
  raw := TClRaw.Create;
  bmp := TBGRABitmap.Create(600, 400);
  ch := TClHitProbe.Create(FForm);
  try
    ch.Parent := FForm;
    ch.Controller := FCtl;
    ch.SetBounds(0, 0, 600, 400);
    ch.Option := Format(cOpt, ['Nope']);
    ch.RenderTo(bmp.Canvas, Rect(0, 0, 600, 400), 96);
    { 4.5 on the first axis: snapped to the row at 5 }
    ch.MouseMove([], 139, 200);
    h := ch.Hits;
    AssertEquals('two pointers', 2, Length(h));
    linked := -1;
    for i := 0 to High(h) do
      if h[i].Linked then linked := i;
    AssertTrue('one linked', linked >= 0);
    { no mapper: the source's (snapped) value as it is }
    AssertEquals('the raw value', 5, h[linked].Value, 0);
    { a registered one maps }
    TyChartRegisterAxisPointerMapper('Raw', @raw.Echo);
    ch.Option := Format(cOpt, ['Raw']);
    ch.RenderTo(bmp.Canvas, Rect(0, 0, 600, 400), 96);
    ch.MouseMove([], 140, 200);
    h := ch.Hits;
    linked := -1;
    for i := 0 to High(h) do
      if h[i].Linked then linked := i;
    AssertTrue('one linked', linked >= 0);
    AssertEquals('mapped', 8, h[linked].Value, 0);
    AssertTrue('called', raw.Calls > 0);
  finally
    ch.Free;
    bmp.Free;
    raw.Free;
  end;
end;

procedure TAdvChartConnectLinkTest.TestTheAxisBreakActionsTravel;
const
  cOpt = '{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"breaks":[{"start":100,"end":900}]},'
    + '"series":[{"type":"bar","data":[50,1000,80]}]}';
var
  a, b: TTyAdvanceChart;
  i: Integer;
begin
  a := NewChart(cOpt, 0, 0, 300, 200);
  a.Name := 'A';
  b := NewChart(cOpt, 300, 0, 300, 200);
  b.Name := 'B';
  TyChartConnect([a, b]);
  try
    FLog.Clear;
    AssertTrue(a.DispatchAction('{"type":"expandAxisBreak","yAxisIndex":0,"breaks":[{"start":100,"end":900}]}'));
    { the non-refined event travels; B publishes its own refined one --
      [F4b] the update's brushselected (each chart's, and B's forwarded
      one) is no refined event: left out here }
    for i := FLog.Count - 1 downto 0 do
      if Pos('axisbreakchanged', FLog[i]) = 0 then FLog.Delete(i);
    AssertEquals('two refined events', 2, FLog.Count);
    AssertTrue('B first (A''s internal event went before its refined one)',
      Pos('B axisbreakchanged', FLog[0]) = 1);
    AssertTrue(Pos('"isExpanded":true', FLog[0]) > 0);
    AssertTrue(Pos('A axisbreakchanged', FLog[1]) = 1);
  finally
    TyChartDisconnect(a.Group);
  end;
end;

procedure TAdvChartConnectLinkTest.TestTheApiDataZoomPublishesItsPayload;
const
  cOpt = '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"]},'
    + '"yAxis":{},"dataZoom":[{"type":"slider"}],'
    + '"series":[{"type":"bar","data":[1,2,3,4]}]}';
var
  a, b: TTyAdvanceChart;
begin
  a := NewChart(cOpt, 0, 0, 300, 200);
  a.Name := 'A';
  b := NewChart(cOpt, 300, 0, 300, 200);
  b.Name := 'B';
  TyChartConnect([a, b]);
  try
    FLog.Clear;
    AssertTrue(a.DispatchDataZoom(0, 25, 75));
    AssertTrue('A publishes the API''s payload', FLog.Count >= 2);
    AssertEquals('A datazoom {"type":"datazoom","dataZoomIndex":0,"start":25,"end":75}',
      FLog[0]);
    AssertEquals('B datazoom {"type":"datazoom","dataZoomIndex":0,"start":25,"end":75}',
      FLog[1]);
  finally
    TyChartDisconnect(a.Group);
  end;
end;

procedure TAdvChartConnectLinkTest.TestSaveAsImageSavesTheConnectedGroup;
const
  cOpt = '{"animation":false,"backgroundColor":"#ff0000","toolbox":{"feature":'
    + '{"saveAsImage":{"connectedBackgroundColor":"#336699"}}},"series":[]}';
var
  a: TClSaveProbe;
  b: TTyAdvanceChart;
  bmp, png: TBGRABitmap;
  fn: string;
  p: TBGRAPixel;
begin
  fn := GetTempDir + 'ty_d8_connected_save.png';
  if FileExists(fn) then DeleteFile(fn);
  a := TClSaveProbe.Create(FForm);
  a.Parent := FForm;
  a.Controller := FCtl;
  a.SetBounds(0, 0, 200, 100);
  a.Option := cOpt;
  a.SaveTo := fn;
  bmp := TBGRABitmap.Create(200, 100);
  try
    a.Render(bmp.Canvas, Rect(0, 0, 200, 100), 96);
  finally
    bmp.Free;
  end;
  b := NewChart('{"backgroundColor":"#00ff00","series":[]}', 250, 0, 100, 100);
  TyChartConnect([a, b]);
  try
    AssertTrue('the icon is there', a.ToolboxClick(0, 'saveAsImage', 'saveAsImage'));
    AssertTrue('saved', FileExists(fn));
    png := TBGRABitmap.Create(fn);
    try
      { both charts, the gap the feature's connectedBackgroundColor }
      AssertEquals('the group''s width', 350, png.Width);
      AssertEquals('the group''s height', 100, png.Height);
      { B's image too -- on A's background: the feature passes the option's
        backgroundColor in the options every chart is rendered with, as
        upstream's renderToCanvas(clone(opts)) does }
      p := png.GetPixel(300, 50);
      AssertTrue('B in it, on A''s background', (p.red = 255) and (p.green = 0) and (p.alpha = 255));
      p := png.GetPixel(225, 50);
      AssertTrue('the gap', (p.red = $33) and (p.green = $66) and (p.blue = $99));
    finally
      png.Free;
    end;
  finally
    TyChartDisconnect(a.Group);
    DeleteFile(fn);
  end;
end;

{ the legend actions' batch: every item over the selection, then ONE update
  (doDispatchAction's updateMethods.update after the loop). Toggling s1 off
  and on in one batch moves nothing; an update per item would hide s1's
  bars -- fading them out -- and bring them back. [Milestone D5-D8: the
  connect oracle runs without animation, where the two cannot be told
  apart.] }
procedure TAdvChartConnectLinkTest.TestALegendBatchUpdatesOnce;
const
  cOpt = '{"legend":{},"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"name":"s1","type":"bar","data":[3,5,2]},'
    + '{"name":"s2","type":"bar","data":[4,1,6]}]}';
var
  c: TClProbe;
  bmp: TBGRABitmap;
begin
  c := TClProbe.Create(FForm);
  c.Parent := FForm;
  c.Controller := FCtl;
  c.AnimationMode := camAlways;
  c.AnimNow := 1000;
  c.SetBounds(0, 0, 400, 300);
  c.Option := cOpt;
  bmp := TBGRABitmap.Create(400, 300);
  try
    c.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    c.AnimTick(1000 + 5000);
    c.AnimNow := 7000;
    AssertTrue(c.DispatchAction('{"type":"legendToggleSelect","batch":[{"name":"s1"},{"name":"s1"}]}'));
    c.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    AssertEquals('no bar fades out', 0, c.AnimGhostCount);
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartConnectLinkOracleTest);
  RegisterTest(TAdvChartConnectLinkTest);
end.
