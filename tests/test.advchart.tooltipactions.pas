unit test.advchart.tooltipactions;
{$mode objfpc}{$H+}
{ THE TOOLTIP AND THE AXIS POINTER DRIVEN BY ACTIONS, HELD TO UPSTREAM
  [Batch 153, roadmap D8b].

  tools/advchart-oracle/tooltip-actions.js runs the real ECharts 6.1 build in
  node with several chart instances in one process: pointer steps through
  zrender's own Handler (the global listener's axisPointer and itemTooltip
  records), hand-dispatched updateAxisPointer / showTip / hideTip, groups
  joined with echarts.connect. Per step it records every updateaxispointer,
  showtip, hidetip and updated of every chart in the order the handlers heard
  them, and per chart the axisPointer model's axes (status, value, rows) and
  the tooltip content (shown, `_show`, what it shows, the point it was placed
  from, the box's top-left with the content answering 80 x 40).

  This replays them through TTyAdvanceChart: the pointer through MouseMove /
  MouseLeave / MouseDown + MouseUp / DoMouseWheel, the actions through
  DispatchAction, the groups through Group / TyChartConnect, the clock
  through TooltipNow / TooltipTick, the box's size through
  TooltipContentSize. Text is measured with zrender's SSR width table. Every
  NUL of an auto id is written U+2400 on both sides; a `from` (a view uid) is
  '<view uid>'. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Data, tyControls.AdvChart.Events,
     tyControls.AdvChart.Connect, tyControls.AdvChart.Geo,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TTaProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
    procedure TooltipContentSize(var AW, AH: Double); override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Leave;
    procedure Click(AX, AY: Integer);
    procedure Wheel(AX, AY, ADelta: Integer);
    function Hits: TTyAxisHitArray;
    function PointerValueOf(const AHit: TTyAxisHit): Double;
    { what the box shows, as the oracle writes it }
    function Which: string;
    function RowsText(const AHit: TTyAxisHit): string;
  end;

  TAdvChartTooltipActionsOracleTest = class(TTestCase)
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
    procedure Finish(const AWhat: string);
    function Ssr: ITyTextMeasurer;
    function NewProbe(const AOptionJson: string; ATag: Integer): TTaProbe;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareState(AChart: TTaProbe; AState: TJSONObject; AIndex: Integer);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheAxisPairAsUpstream;
    procedure TestTheItemPairAsUpstream;
    procedure TestThreeShapesAsUpstream;
    procedure TestLinkedAxesInAGroupAsUpstream;
    procedure TestAlwaysShowContentAsUpstream;
    procedure TestTriggerOnClickAsUpstream;
    procedure TestTriggerOnNoneAsUpstream;
    procedure TestTheBoxIsNoTargetAsUpstream;
    procedure TestDelaysInAGroupAsUpstream;
    procedure TestACrossInAGroupAsUpstream;
    procedure TestHandDispatchedAsUpstream;
    procedure TestNoTooltipComponentAsUpstream;
    procedure TestTheAxesInfoRestrictsAsUpstream;
    procedure TestABaseAxisWithoutRowsAsUpstream;
  end;

  TAdvChartTooltipActionsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FLog: TStrings;
    function NewChart(const AOptionJson: string): TTyAdvanceChart;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAShowTipEventIsThePayload;
    procedure TestASilentShowTipPublishesNothing;
    procedure TestAShowTipBatchIsTaken;
    procedure TestAMatrixCellByNameShowsItsTip;
    procedure TestAGeoRegionByNameShowsItsTip;
    procedure TestAGeoRegionUnderThePointerShowsItsTip;
    procedure TestTheKeyboardDispatchesShowTip;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cNulMark = #$E2#$90#$80;
  cTypes: array[0..2] of string = ('updateaxispointer', 'showtip', 'hidetip');

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

{ a payload the port published, parsed with its NULs marked and every `from`
  string a view uid }
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

function IsTipType(const AType: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(cTypes) do
    if cTypes[i] = AType then Exit(True);
  Result := False;
end;

{ ==================== the probe ==================== }

function TTaProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TTaProbe.TooltipContentSize(var AW, AH: Double);
begin
  { TooltipRichContent.getSize, as the oracle answers it }
  AW := 80;
  AH := 40;
end;

procedure TTaProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTaProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TTaProbe.Leave;
begin
  MouseLeave;
end;

procedure TTaProbe.Click(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TTaProbe.Wheel(AX, AY, ADelta: Integer);
begin
  DoMouseWheel([], ADelta * 120, Point(AX, AY));
end;

function TTaProbe.Hits: TTyAxisHitArray;
begin
  Result := TipHits;
end;

function TTaProbe.PointerValueOf(const AHit: TTyAxisHit): Double;
begin
  Result := PointerValue(AHit);
end;

function TTaProbe.RowsText(const AHit: TTyAxisHit): string;
var
  k, s: Integer;
  st: TTyDataStore;
begin
  Result := '';
  for k := 0 to High(AHit.Slots) do
  begin
    s := SlotSeriesIndex(AHit.Slots[k]);
    st := SeriesStore(s);
    if k > 0 then Result := Result + ';';
    Result := Result + IntToStr(s) + ',' + IntToStr(st.GetRawIndex(AHit.Rows[k]))
      + ',' + IntToStr(AHit.Rows[k]);
  end;
end;

function TTaProbe.Which: string;
var
  snap: TTyTipSnap;
  i, k, s: Integer;
  first: Boolean;
  st: TTyDataStore;
begin
  snap := TipSnapShown;
  if Length(snap.Hits) > 0 then
  begin
    Result := 'axis:';
    first := True;
    for i := 0 to High(snap.Hits) do
    begin
      { [R2-I7] the axes that trigger the tooltip }
      if snap.Hits[i].NoTip or (snap.Hits[i].Axis = nil) then Continue;
      for k := 0 to High(snap.Hits[i].Slots) do
      begin
        s := SlotSeriesIndex(snap.Hits[i].Slots[k]);
        st := SeriesStore(s);
        if not first then Result := Result + ',';
        first := False;
        Result := Result + IntToStr(s) + '/' + IntToStr(st.GetRawIndex(snap.Hits[i].Rows[k]))
          + '@' + snap.Hits[i].Axis.Dim + IntToStr(snap.Hits[i].Axis.ComponentIndex);
      end;
    end;
    Exit;
  end;
  { a cell: its matrix (the name is compared by the hand-written test) }
  if snap.Datum.Kind = ctkMatrix then
  begin
    Result := 'cmpt:matrix:' + IntToStr(snap.Datum.ComponentIndex) + ':';
    Exit;
  end;
  if snap.Datum.IsEdge then
    Result := 'item:' + IntToStr(snap.Datum.SeriesIndex) + ':'
      + IntToStr(snap.Datum.RawDataIndex) + ':edge'
  else
  begin
    Result := 'item:' + IntToStr(snap.Datum.SeriesIndex) + ':'
      + IntToStr(snap.Datum.RawDataIndex);
    { a graph's node is params.dataType 'node' [R2-E] }
    if TooltipParams(snap.Datum).DataType <> '' then
      Result := Result + ':' + TooltipParams(snap.Datum).DataType;
  end;
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartTooltipActionsOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-tooltip-actions.json'));
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

procedure TAdvChartTooltipActionsOracleTest.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartTooltipActionsOracleTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartTooltipActionsOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartTooltipActionsOracleTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if HexOf(AGot) <> LowerCase(AHex) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartTooltipActionsOracleTest.Finish(const AWhat: string);
begin
  if GetEnvironmentVariable('TY_TOOLTIPACTIONS_COUNTS') = '1' then
    WriteLn(StdErr, AWhat, ': ', FCompared, ' comparisons');
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartTooltipActionsOracleTest.NewProbe(const AOptionJson: string;
  ATag: Integer): TTaProbe;
begin
  Result := TTaProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Measurer := Ssr;
  Result.Tag := ATag;
  Result.TooltipNow := 0;
  Result.SetBounds(0, 0, cW, cH);
  Result.Option := AOptionJson;
  Result.OnChartEvent := @OnEvent;
  Result.ChartOn('updated', @OnEvent);
  Result.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartTooltipActionsOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  { the pointer's and the tooltip's actions, and updated: not the mouse's,
    nor another action's }
  if not IsTipType(AEvent.EventType) and (AEvent.EventType <> 'updated') then Exit;
  FLog.Add(IntToStr(TComponent(Sender).Tag) + #9 + AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAdvChartTooltipActionsOracleTest.CompareEvents(AWant: TJSONArray);
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
      Bad(Format('  port %d: %s', [i, Copy(StringReplace(FLog[i], #9, ' ', [rfReplaceAll]), 1, 160)]));
    for i := 0 to AWant.Count - 1 do
      Bad(Format('  upstream %d: %s', [i, Copy(AWant.Items[i].AsJSON, 1, 160)]));
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

procedure TAdvChartTooltipActionsOracleTest.CompareState(AChart: TTaProbe;
  AState: TJSONObject; AIndex: Integer);
var
  axes: TJSONArray;
  ax, tip: TJSONObject;
  hits: TTyAxisHitArray;
  k, c, h, n: Integer;
  shown: Boolean;
  box: TTyRectF;
  at: TTyPointF;
  who: string;
begin
  who := 'chart ' + IntToStr(AIndex);
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
      Bad(Format('%s %s: shown %s, upstream %s', [who, ax.Strings['key'],
        BoolToStr(h >= 0, True), ax.Strings['status']]));
      Continue;
    end;
    if h < 0 then Continue;
    Inc(n);
    Same(who + ' ' + ax.Strings['key'] + ' value', AChart.PointerValueOf(hits[h]), ax.Strings['value']);
    Inc(FCompared);
    if AChart.RowsText(hits[h]) <> FixSdiText(ax.Arrays['sdi']) then
      Bad(Format('%s %s rows %s, upstream %s', [who, ax.Strings['key'],
        AChart.RowsText(hits[h]), FixSdiText(ax.Arrays['sdi'])]));
  end;
  Inc(FCompared);
  if n <> Length(hits) then
    Bad(Format('%s: %d pointers, upstream %d', [who, Length(hits), n]));
  { the box }
  if AState.Find('tip').JSONType = jtNull then Exit;
  tip := AState.Objects['tip'];
  shown := AChart.TooltipShown;
  Inc(FCompared);
  if shown <> tip.Booleans['visible'] then
  begin
    Bad(Format('%s: box shown %s, upstream %s', [who, BoolToStr(shown, True),
      BoolToStr(tip.Booleans['visible'], True)]));
    Exit;
  end;
  Inc(FCompared);
  if AChart.TooltipShowFlag <> tip.Booleans['show'] then
    Bad(Format('%s: _show %s, upstream %s', [who, BoolToStr(AChart.TooltipShowFlag, True),
      BoolToStr(tip.Booleans['show'], True)]));
  if not shown then Exit;
  Inc(FCompared);
  if tip.Strings['which'] <> AChart.Which then
    Bad(Format('%s: the box shows %s, upstream %s', [who, AChart.Which, tip.Strings['which']]));
  at := AChart.TooltipAnchorF;
  Same(who + ' anchor x', at.X, tip.Arrays['anchor'].Strings[0]);
  Same(who + ' anchor y', at.Y, tip.Arrays['anchor'].Strings[1]);
  box := AChart.TooltipBox;
  Same(who + ' box x', box.Left, tip.Arrays['box'].Strings[0]);
  Same(who + ' box y', box.Top, tip.Arrays['box'].Strings[1]);
end;

procedure TAdvChartTooltipActionsOracleTest.RunCase(const AId: string);
var
  cases, charts, steps: TJSONArray;
  cs, st: TJSONObject;
  probes: array of TTaProbe;
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
      if (op = 'move') or (op = 'click') or (op = 'wheel') or (op = 'leave') then
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
      else if op = 'wheel' then
        probes[c].Wheel(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1],
          st.Integers['delta'])
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

procedure TAdvChartTooltipActionsOracleTest.TestTheAxisPairAsUpstream;
begin
  RunCase('axis-pair');
end;

procedure TAdvChartTooltipActionsOracleTest.TestTheItemPairAsUpstream;
begin
  RunCase('item-pair');
end;

procedure TAdvChartTooltipActionsOracleTest.TestThreeShapesAsUpstream;
begin
  RunCase('three-shapes');
end;

procedure TAdvChartTooltipActionsOracleTest.TestLinkedAxesInAGroupAsUpstream;
begin
  RunCase('link-pair');
end;

procedure TAdvChartTooltipActionsOracleTest.TestAlwaysShowContentAsUpstream;
begin
  RunCase('always');
end;

procedure TAdvChartTooltipActionsOracleTest.TestTriggerOnClickAsUpstream;
begin
  RunCase('click');
end;

procedure TAdvChartTooltipActionsOracleTest.TestTriggerOnNoneAsUpstream;
begin
  RunCase('none');
end;

procedure TAdvChartTooltipActionsOracleTest.TestTheBoxIsNoTargetAsUpstream;
begin
  RunCase('enterable');
  FBad := 0;
  FCompared := 0;
  FReport := '';
  RunCase('enterable-off');
end;

procedure TAdvChartTooltipActionsOracleTest.TestDelaysInAGroupAsUpstream;
begin
  RunCase('delay');
end;

procedure TAdvChartTooltipActionsOracleTest.TestACrossInAGroupAsUpstream;
begin
  RunCase('cross-pair');
end;

procedure TAdvChartTooltipActionsOracleTest.TestHandDispatchedAsUpstream;
begin
  RunCase('hand');
end;

procedure TAdvChartTooltipActionsOracleTest.TestNoTooltipComponentAsUpstream;
begin
  RunCase('no-tooltip');
end;

procedure TAdvChartTooltipActionsOracleTest.TestTheAxesInfoRestrictsAsUpstream;
begin
  RunCase('restrict');
end;

{ [D9-D14 mutation round] showTooltip skips a base axis with no row under
  the point; with none left the pointer's action is a hideTip }
procedure TAdvChartTooltipActionsOracleTest.TestABaseAxisWithoutRowsAsUpstream;
begin
  RunCase('short-rows');
end;

{ ==================== the hand-written test ==================== }

const
  cBars = '{"animation":false,"tooltip":{"trigger":"item"},'
    + '"xAxis":{"type":"category","data":["a","b","c","d"]},"yAxis":{"min":0,"max":10},'
    + '"series":[{"type":"bar","data":[3,5,2,6]}]}';
  cAxisBars = '{"animation":false,"tooltip":{"trigger":"axis"},'
    + '"xAxis":{"type":"category","data":["a","b","c","d"]},"yAxis":{"min":0,"max":10},'
    + '"series":[{"type":"bar","data":[3,5,2,6]}]}';
  { two unit squares side by side, A then B }
  cSquares = '{"type":"FeatureCollection","features":['
    + '{"type":"Feature","properties":{"name":"A"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[10,0],[20,0],[20,10],[10,10],[10,0]]]}}]}';
  cGeo = '{"animation":false,"tooltip":{},'
    + '"geo":{"id":"g0","map":"mgeo_sq","tooltip":{"show":true}}}';

procedure TAdvChartTooltipActionsTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FLog := TStringList.Create;
end;

procedure TAdvChartTooltipActionsTest.TearDown;
begin
  FLog.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartTooltipActionsTest.NewChart(const AOptionJson: string): TTyAdvanceChart;
var bmp: TBGRABitmap;
begin
  Result := TTaProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.TooltipNow := 0;
  Result.SetBounds(0, 0, cW, cH);
  Result.Option := AOptionJson;
  Result.OnChartEvent := @OnEvent;
  Result.ChartOn('updated', @OnEvent);
  bmp := TBGRABitmap.Create(cW, cH);
  try
    TTaProbe(Result).Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartTooltipActionsTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if not IsTipType(AEvent.EventType) and (AEvent.EventType <> 'updated')
    and (AEvent.EventType <> 'highlight') and (AEvent.EventType <> 'downplay') then Exit;
  FLog.Add(AEvent.EventType + ' ' + AEvent.Payload);
end;

procedure TAdvChartTooltipActionsTest.TestAShowTipEventIsThePayload;
var ch: TTyAdvanceChart;
begin
  ch := NewChart(cBars);
  try
    FLog.Clear;
    AssertTrue('taken', ch.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":1,"foo":[1,2]}'));
    { the payload's copy, the type lowercased; then the view's own showTip,
      then one updated }
    AssertEquals(3, FLog.Count);
    AssertEquals('showtip {"type":"showtip","seriesIndex":0,"dataIndex":1,"foo":[1,2]}', FLog[0]);
    AssertEquals(1, Pos('showtip {"type":"showtip","dataIndexInside":1,"dataIndex":1,"seriesIndex":0,'
      + '"from":"ec_', FLog[1]));
    AssertEquals(Length(FLog[1]) - Length('_tooltip"}') + 1, Pos('_tooltip"}', FLog[1]));
    AssertEquals('updated ', FLog[2]);
    AssertTrue('shown', ch.TooltipShown);
    AssertEquals('item:0:1', ch.TooltipShownWhich);
  finally
    ch.Free;
  end;
end;

procedure TAdvChartTooltipActionsTest.TestASilentShowTipPublishesNothing;
var ch: TTyAdvanceChart;
begin
  ch := NewChart(cAxisBars);
  try
    FLog.Clear;
    AssertTrue('taken', ch.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":2}', True));
    { the pending updateAxisPointer and showTip run silent too }
    AssertEquals('nothing published', 0, FLog.Count);
    AssertTrue('shown', ch.TooltipShown);
    AssertEquals('axis:c', ch.TooltipShownWhich);
    FLog.Clear;
    AssertTrue('taken', ch.DispatchAction('{"type":"hideTip"}', True));
    AssertEquals('nothing published', 0, FLog.Count);
    AssertFalse('the hide armed', ch.TooltipShowFlag);
  finally
    ch.Free;
  end;
end;

procedure TAdvChartTooltipActionsTest.TestAShowTipBatchIsTaken;
var ch: TTyAdvanceChart;
begin
  { [F4b: this said a batch of showTip is not taken -- upstream takes it:
    manuallyShowTip per item, one showtip event of the items, the view's
    own showTip after it (actions-batch.js, b-showtip-item)] }
  ch := NewChart(cBars);
  try
    FLog.Clear;
    AssertTrue('a batch of showTip is taken',
      ch.DispatchAction('{"type":"showTip","batch":[{"seriesIndex":0,"dataIndex":1}]}'));
    AssertTrue(FLog.Count >= 2);
    AssertEquals(1, Pos('showtip {"type":"showtip","batch":[', FLog[0]));
    AssertTrue(ch.TooltipShown);
  finally
    ch.Free;
  end;
end;

procedure TAdvChartTooltipActionsTest.TestAMatrixCellByNameShowsItsTip;
var ch: TTyAdvanceChart;
begin
  ch := NewChart('{"animation":false,"tooltip":{},'
    + '"matrix":{"x":{"data":["A","B"]},"y":{"data":["P","Q"]},"tooltip":{"show":true}}}');
  try
    FLog.Clear;
    AssertTrue('taken', ch.DispatchAction('{"type":"showTip","matrixIndex":0,"name":"B"}'));
    AssertTrue('shown', ch.TooltipShown);
    AssertEquals('matrix:0:', Copy(ch.TooltipShownWhich, 1, 9));
    { showTip, the view's showTip, updated }
    AssertEquals(3, FLog.Count);
    AssertEquals('showtip {"type":"showtip","matrixIndex":0,"name":"B"}', FLog[0]);
    AssertEquals(1, Pos('showtip {"type":"showtip","from":"ec_', FLog[1]));
    FLog.Clear;
    { a name no cell has: nothing shown, nothing hidden }
    AssertTrue('taken', ch.DispatchAction('{"type":"hideTip"}'));
    ch.TooltipTick(1000);
    AssertFalse(ch.TooltipShown);
    AssertTrue('taken', ch.DispatchAction('{"type":"showTip","matrixIndex":0,"name":"Z"}'));
    AssertFalse(ch.TooltipShown);
  finally
    ch.Free;
  end;
end;

{ findComponentReference on a geo: the region group whose tooltip config
  names the payload's name, by geoIndex or geoId; the box placed from the
  group's centre [Batch 148 x Batch 153] }
procedure TAdvChartTooltipActionsTest.TestAGeoRegionByNameShowsItsTip;
var
  ch: TTyAdvanceChart;
  geo: TTyGeo;
  c: TTyGeoPt;
  px: TTyPointF;
begin
  AssertTrue(TyChartRegisterMap('mgeo_sq', cSquares));
  ch := NewChart(cGeo);
  try
    FLog.Clear;
    AssertTrue('taken', ch.DispatchAction('{"type":"showTip","geoIndex":0,"name":"B"}'));
    AssertTrue('shown', ch.TooltipShown);
    AssertEquals('geo:0:B', ch.TooltipShownWhich);
    { the point is region B's centre }
    geo := ch.GeoLayout(0);
    AssertNotNull(geo);
    c := geo.RegionByName('B').GetCenter;
    AssertTrue(geo.PointOf(c.X, c.Y, px));
    AssertEquals('placed from x', px.X, ch.TooltipAnchorF.X, 0.5);
    AssertEquals('placed from y', px.Y, ch.TooltipAnchorF.Y, 0.5);
    { showTip, the view's showTip, updated }
    AssertEquals(3, FLog.Count);
    AssertEquals('showtip {"type":"showtip","geoIndex":0,"name":"B"}', FLog[0]);
    AssertEquals(1, Pos('showtip {"type":"showtip","from":"ec_', FLog[1]));
    FLog.Clear;
    AssertTrue('taken', ch.DispatchAction('{"type":"hideTip"}'));
    ch.TooltipTick(1000);
    AssertFalse(ch.TooltipShown);
    { by id }
    AssertTrue('taken', ch.DispatchAction('{"type":"showTip","geoId":"g0","name":"A"}'));
    AssertEquals('geo:0:A', ch.TooltipShownWhich);
    AssertTrue('taken', ch.DispatchAction('{"type":"hideTip"}'));
    ch.TooltipTick(2000);
    { a name no region has, a geo that is not there: nothing shown }
    AssertTrue('taken', ch.DispatchAction('{"type":"showTip","geoIndex":0,"name":"Z"}'));
    AssertFalse(ch.TooltipShown);
    AssertTrue('taken', ch.DispatchAction('{"type":"showTip","geoIndex":1,"name":"A"}'));
    AssertFalse(ch.TooltipShown);
  finally
    ch.Free;
    TyChartClearMaps;
  end;
end;

{ a region under the pointer: the item tooltip's listener shows the
  component's tooltip whatever the trigger says and hands the listener a
  showTip from the view; leaving hides it through a hideTip }
procedure TAdvChartTooltipActionsTest.TestAGeoRegionUnderThePointerShowsItsTip;
var
  ch: TTyAdvanceChart;
  geo: TTyGeo;
  c: TTyGeoPt;
  px: TTyPointF;
begin
  AssertTrue(TyChartRegisterMap('mgeo_sq', cSquares));
  ch := NewChart(StringReplace(cGeo, '"tooltip":{},', '"tooltip":{"trigger":"axis"},', []));
  try
    geo := ch.GeoLayout(0);
    AssertNotNull(geo);
    c := geo.RegionByName('A').GetCenter;
    AssertTrue(geo.PointOf(c.X, c.Y, px));
    FLog.Clear;
    TTaProbe(ch).Move(Round(px.X), Round(px.Y));
    AssertTrue('shown', ch.TooltipShown);
    AssertEquals('geo:0:A', ch.TooltipShownWhich);
    AssertTrue('a showTip from the view',
      Pos('showtip {"type":"showtip","from":"ec_', FLog.Text) > 0);
    FLog.Clear;
    TTaProbe(ch).Leave;
    AssertTrue('a hideTip from the view',
      Pos('hidetip {"type":"hidetip","from":"ec_', FLog.Text) > 0);
  finally
    ch.Free;
    TyChartClearMaps;
  end;
end;

procedure TAdvChartTooltipActionsTest.TestTheKeyboardDispatchesShowTip;
var ch: TTyAdvanceChart;
begin
  ch := NewChart(cAxisBars);
  try
    FLog.Clear;
    ch.SetKeyboardItem(0, 1);
    { highlight, then the showTip, its updateAxisPointer (the axis
      detour) and the showTip that dispatches }
    AssertTrue('the keyboard dispatches showTip',
      Pos('showtip {"type":"showtip","seriesIndex":0,"dataIndex":1}', FLog.Text) > 0);
    AssertTrue('through updateAxisPointer', Pos('updateaxispointer ', FLog.Text) > 0);
    AssertTrue('shown', ch.TooltipShown);
    AssertEquals('axis:b', ch.TooltipShownWhich);
    AssertEquals('one pointer', 1, Length(TTaProbe(ch).Hits));
    FLog.Clear;
    ch.ClearKeyboardItem;
    AssertTrue('the pointer goes',
      Pos('updateaxispointer {"axesInfo":[],"type":"updateaxispointer"}', FLog.Text) > 0);
    AssertFalse('the hide armed', ch.TooltipShowFlag);
  finally
    ch.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartTooltipActionsOracleTest);
  RegisterTest(TAdvChartTooltipActionsTest);
end.
