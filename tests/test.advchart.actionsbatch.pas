unit test.advchart.actionsbatch;
{$mode objfpc}{$H+}
{ EVERY ACTION AS A BATCH, THE PENDING ACTIONS, AND `rendered` ON EVERY
  FLUSH, HELD TO UPSTREAM [fix batch F4b].

  tools/advchart-oracle/actions-batch.js runs the real ECharts 6.1 build in
  node. Batch cases: each action the port dispatches with a `batch` of two
  items (one event {type, escapeConnect, batch: [each item's event]}, the
  update once, what the items dispatched waiting until after the event; a
  batch that is no list, a silent one, a refined action's one refined
  event); a twin chart takes the same items one by one, and the oracle says
  whether the two end in the same state. Pending cases: an action's own
  dispatch waits for its event; a handler's dispatch runs at once and its
  flush takes what the outer one left waiting; a silent dispatch publishes
  nothing. Flush cases: zrender's own frames, `rendered` (elapsedTime) and
  `finished` only when something was marked.

  This replays them through TTyAdvanceChart (the tooltip-actions probe):
  every event of the fixture's listen list in the order the handlers heard
  it, payloads compared key by key (numbers exactly); where upstream's two
  charts agree, the port's batch chart and its twin are compared pixel for
  pixel.

  [R2-E] More of the same oracle: a timeline batch, animated (the bars at
  the clock's steps: the update renders once, after every item); an
  axisAreaSelect batch's covers (the update skips the first axis the OUTER
  payload finds); a batch of no items (the update still runs, unless it is
  none or a component's own); the flushes a legend item, a toolbox icon and
  a dataZoom handle ask for (their over and out, not a move inside); and a
  setOption's rendered before its updated. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart.Geo, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Brush,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax, test.advchart.tooltipactions;
type
  TAdvChartActionsBatchOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp, FBmp2: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    FChart: TTaProbe;
    FHandOn: string;
    FHandLeft: Integer;
    FHandDispatch: string;
    FHandFlush: Boolean;
    FListen: TStringList;
    FAnim: Boolean;
    procedure Bad(const AWhat: string);
    procedure Finish(const AWhat: string);
    function Ssr: ITyTextMeasurer;
    function NewProbe(const AOptionJson: string; AAnim: Boolean = False): TTaProbe;
    procedure CompareBars(ABars: TJSONArray);
    procedure CompareCovers(ACovers: TJSONArray);
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure OnHandler(Sender: TObject; const AEvent: TTyChartEvent);
    procedure CompareEvents(AWant: TJSONArray);
    procedure RunStep(AChart: TTaProbe; AStep: TJSONObject; ABmp: TBGRABitmap;
      var ANow: Double);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLegendScrollAsUpstream;
    procedure TestABatchThatIsNoListAsUpstream;
    procedure TestASilentBatchAsUpstream;
    procedure TestSelectDataRangeAsUpstream;
    procedure TestTheLegacyPieSelectAsUpstream;
    procedure TestGeoToggleSelectAsUpstream;
    procedure TestGeoRoamAsUpstream;
    procedure TestSunburstRootToNodeAsUpstream;
    procedure TestTreemapRootToNodeAsUpstream;
    procedure TestGraphRoamAsUpstream;
    procedure TestDragNodeAsUpstream;
    procedure TestTakeGlobalCursorAsUpstream;
    procedure TestBrushAsUpstream;
    procedure TestBrushEndAsUpstream;
    procedure TestTimelineChangeAsUpstream;
    procedure TestTimelinePlayChangeAsUpstream;
    procedure TestAxisAreaSelectAsUpstream;
    procedure TestParallelAxisExpandAsUpstream;
    procedure TestExpandAxisBreakAsUpstream;
    procedure TestShowTipAsUpstream;
    procedure TestShowTipOnItemsAsUpstream;
    procedure TestHideTipAsUpstream;
    procedure TestUpdateAxisPointerAsUpstream;
    procedure TestALegacyActionsSelectWaitsAsUpstream;
    procedure TestAHandlersDispatchFlushesTheOuterQueueAsUpstream;
    procedure TestASilentDispatchPublishesNothingAsUpstream;
    procedure TestAHandlersDispatchRunsAtOnceAsUpstream;
    procedure TestRenderedOnEveryFlushAsUpstream;
    procedure TestRenderedWithoutATooltipAsUpstream;
    procedure TestNoFinishedWhileAnActionWaitsAsUpstream;
    { [R2-E] }
    procedure TestATimelineBatchRendersOnceAsUpstream;
    procedure TestAnAxisAreaSelectBatchsCoversAsUpstream;
    procedure TestTheOuterPayloadNamesTheSkippedAxisAsUpstream;
    procedure TestABatchOfNoItemsUpdatesAsUpstream;
    procedure TestALegendItemsHoverFlushesAsUpstream;
    procedure TestAToolboxIconsHoverFlushesAsUpstream;
    procedure TestADataZoomHandlesHoverFlushesAsUpstream;
    procedure TestSetOptionRendersBeforeUpdatedAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cNulMark = #$E2#$90#$80;

type
  { the animation's frame list, for the bars [R2-E] }
  TAbProbe = class(TTaProbe)
  end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

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
  if AJson = '' then Exit(TJSONNull.Create);
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
          if go.IndexOfName(wo.Names[i]) < 0 then Exit;
          if not SameJson(wo.Items[i], go.Find(wo.Names[i])) then Exit;
        end;
        Result := True;
      end;
  end;
end;

procedure TAdvChartActionsBatchOracleTest.SetUp;
var
  sl: TStringList;
  maps: TJSONArray;
  i: Integer;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FBmp2 := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TStringList.Create;
  FListen := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-actions-batch.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    TyChartRegisterMap(maps.Objects[i].Strings['name'], maps.Objects[i].Strings['text']);
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartActionsBatchOracleTest.TearDown;
var
  maps: TJSONArray;
  i: Integer;
begin
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    TyChartUnregisterMap(maps.Objects[i].Strings['name']);
  FLog.Free;
  FListen.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FBmp2.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartActionsBatchOracleTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartActionsBatchOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartActionsBatchOracleTest.Finish(const AWhat: string);
begin
  if GetEnvironmentVariable('TY_ACTIONSBATCH_COUNTS') = '1' then
    WriteLn(StdErr, AWhat, ': ', FCompared, ' comparisons');
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartActionsBatchOracleTest.NewProbe(const AOptionJson: string;
  AAnim: Boolean): TTaProbe;
begin
  Result := TAbProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Measurer := Ssr;
  Result.TooltipNow := 0;
  Result.AnimNow := 0;
  { [R2-E] an animated case: the chart's clock is the oracle's }
  if AAnim then Result.AnimationMode := camAlways;
  Result.SetBounds(0, 0, cW, cH);
  Result.Option := AOptionJson;
  Result.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartActionsBatchOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if Sender <> FChart then Exit;
  if FListen.IndexOf(AEvent.EventType) < 0 then Exit;
  FLog.Add(AEvent.EventType + #9 + AEvent.Payload);
  { the case's handler, registered after the listeners: it hears the event
    after they do }
  if (AEvent.EventType = FHandOn) and (FHandLeft > 0) then
  begin
    Dec(FHandLeft);
    { a flush inside the handler: the frame zrender would run there }
    if FHandFlush then FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    if FHandDispatch <> '' then FChart.DispatchAction(FHandDispatch);
  end;
end;

procedure TAdvChartActionsBatchOracleTest.OnHandler(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
end;

procedure TAdvChartActionsBatchOracleTest.CompareEvents(AWant: TJSONArray);
var
  i, n, tab: Integer;
  e: TJSONArray;
  typ, payload: string;
  got: TJSONData;
begin
  Inc(FCompared);
  if FLog.Count <> AWant.Count then
  begin
    Bad(Format('%d events, upstream %d', [FLog.Count, AWant.Count]));
    for i := 0 to FLog.Count - 1 do
      Bad(Format('  port %d: %s', [i, Copy(StringReplace(FLog[i], #9, ' ', [rfReplaceAll]), 1, 220)]));
    for i := 0 to AWant.Count - 1 do
      Bad(Format('  upstream %d: %s', [i, Copy(AWant.Items[i].AsJSON, 1, 220)]));
    Exit;
  end;
  n := FLog.Count;
  for i := 0 to n - 1 do
  begin
    e := TJSONArray(AWant.Items[i]);
    tab := Pos(#9, FLog[i]);
    typ := Copy(FLog[i], 1, tab - 1);
    payload := Copy(FLog[i], tab + 1, MaxInt);
    Inc(FCompared);
    if typ <> e.Strings[1] then
    begin
      Bad(Format('event %d: %s, upstream %s', [i, typ, e.Strings[1]]));
      Continue;
    end;
    if e.Items[2].JSONType = jtNull then Continue;
    got := ParsePort(payload);
    try
      Inc(FCompared);
      if not SameJson(e.Items[2], got) then
        Bad(Format('event %d (%s): %s, upstream %s', [i, typ,
          Copy(got.AsJSON, 1, 600), Copy(e.Items[2].AsJSON, 1, 600)]));
    finally
      got.Free;
    end;
  end;
end;

{ the bars by series and row, from the frame drawn last: x0 x1 y0 y1 as
  the rect spans them (timeline.pas' CheckBars) [R2-E] }
procedure TAdvChartActionsBatchOracleTest.CompareBars(ABars: TJSONArray);
var
  s, i, k: Integer;
  lst: TTyPaintList;
  arr, b: TJSONArray;
  el: TTyChartElement;
  found: Boolean;
  bx, by, bw, bh: Double;

  procedure Near(const AWhat: string; AWant, AGot: Double);
  begin
    Inc(FCompared);
    if not (Abs(AWant - AGot) <= 1e-9) then
      Bad(Format('%s: upstream %.17g, here %.17g', [AWhat, AWant, AGot]));
  end;

begin
  lst := TAbProbe(FChart).AnimFrame;
  Inc(FCompared);
  if lst = nil then
  begin
    Bad('no frame');
    Exit;
  end;
  for s := 0 to ABars.Count - 1 do
  begin
    if ABars.Items[s].JSONType = jtNull then Continue;
    arr := TJSONArray(ABars.Items[s]);
    for i := 0 to arr.Count - 1 do
    begin
      found := False;
      el := Default(TTyChartElement);
      for k := 0 to lst.Count - 1 do
      begin
        el := lst.Element(k);
        if (el.Datum.SeriesIndex <> s) or (el.Datum.DataIndex <> i) or el.Ignore then Continue;
        if not (el.Shape.Kind in [cskRect, cskRoundRect]) then Continue;
        found := True;
        Break;
      end;
      Inc(FCompared);
      if arr.Items[i].JSONType = jtNull then
      begin
        if found then Bad(Format('bars[%d][%d]: no bar upstream, one here', [s, i]));
        Continue;
      end;
      if not found then
      begin
        Bad(Format('bars[%d][%d]: no bar here', [s, i]));
        Continue;
      end;
      b := TJSONArray(arr.Items[i]);
      bx := FromHex(b.Strings[0]);
      by := FromHex(b.Strings[1]);
      bw := FromHex(b.Strings[2]);
      bh := FromHex(b.Strings[3]);
      Near(Format('bars[%d][%d].left', [s, i]), Min(bx, bx + bw), el.Shape.Bounds.Left);
      Near(Format('bars[%d][%d].right', [s, i]), Max(bx, bx + bw), el.Shape.Bounds.Right);
      Near(Format('bars[%d][%d].top', [s, i]), Min(by, by + bh), el.Shape.Bounds.Top);
      Near(Format('bars[%d][%d].bottom', [s, i]), Max(by, by + bh), el.Shape.Bounds.Bottom);
    end;
  end;
end;

{ every parallelAxis view's covers: how many, and each one's range
  [R2-E] }
procedure TAdvChartActionsBatchOracleTest.CompareCovers(ACovers: TJSONArray);
var
  a, c, k: Integer;
  ctl: TTyBrushController;
  want, rng: TJSONArray;
  n: Integer;
begin
  for a := 0 to ACovers.Count - 1 do
  begin
    ctl := FChart.ParallelBrushOf(a);
    if ctl = nil then n := 0 else n := Length(ctl.Covers);
    Inc(FCompared);
    if ACovers.Items[a].JSONType = jtNull then
    begin
      if n > 0 then Bad(Format('axis %d: no controller upstream, %d covers here', [a, n]));
      Continue;
    end;
    want := TJSONArray(ACovers.Items[a]);
    if n <> want.Count then
    begin
      Bad(Format('axis %d: %d covers, upstream %d', [a, n, want.Count]));
      Continue;
    end;
    for c := 0 to want.Count - 1 do
    begin
      rng := TJSONArray(want.Items[c]);
      Inc(FCompared);
      if (Length(ctl.Covers[c].Opt.Range) <> 1) or (rng.Count <> 2) then
      begin
        Bad(Format('axis %d cover %d: not a line range', [a, c]));
        Continue;
      end;
      for k := 0 to 1 do
      begin
        Inc(FCompared);
        if ctl.Covers[c].Opt.Range[0][k] <> FromHex(rng.Strings[k]) then
          Bad(Format('axis %d cover %d end %d: %.17g, upstream %.17g', [a, c, k,
            ctl.Covers[c].Opt.Range[0][k], FromHex(rng.Strings[k])]));
      end;
    end;
  end;
end;

procedure TAdvChartActionsBatchOracleTest.RunStep(AChart: TTaProbe;
  AStep: TJSONObject; ABmp: TBGRABitmap; var ANow: Double);
var
  op, js: string;
  silent: Boolean;
begin
  op := AStep.Strings['op'];
  if (op = 'move') or (op = 'click') or (op = 'leave') then
    ANow := ANow + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
  else if op = 'idle' then
    ANow := ANow + AStep.Floats['ms'];
  if (op <> 'action') and (op <> 'setOption') then
  begin
    AChart.TooltipNow := ANow;
    AChart.TooltipTick(ANow);
  end;
  { [R2-E] the clips step on the oracle's clock }
  if FAnim then
  begin
    AChart.AnimNow := ANow;
    TAbProbe(AChart).AnimTick(ANow);
  end;
  if op = 'move' then
    AChart.Move(AStep.Arrays['at'].Integers[0], AStep.Arrays['at'].Integers[1])
  else if op = 'click' then
    AChart.Click(AStep.Arrays['at'].Integers[0], AStep.Arrays['at'].Integers[1])
  else if op = 'leave' then
    AChart.Leave
  else if op = 'action' then
  begin
    js := StringReplace(AStep.Objects['payload'].AsJSON, cNulMark, '\u0000', [rfReplaceAll]);
    silent := (AStep.Find('silent') <> nil) and AStep.Booleans['silent'];
    AChart.DispatchAction(js, silent);
  end
  else if op = 'setOption' then
    AChart.SetOption(AStep.Objects['option'].AsJSON, False);
  AChart.Render(ABmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartActionsBatchOracleTest.RunCase(const AId: string);
var
  cases, steps, listen, hands, pre, items: TJSONArray;
  cs, st: TJSONObject;
  twin: TTaProbe;
  i, j, k, x, y, diff: Integer;
  now_, now2: Double;
  flush: Boolean;
  a, b: PBGRAPixel;
  t: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  flush := cs.Booleans['flush'];
  FAnim := (cs.Find('anim') <> nil) and cs.Booleans['anim'];
  FChart := nil;
  twin := nil;
  try
    FChart := NewProbe(cs.Objects['option'].AsJSON, FAnim);
    if cs.Booleans['twin'] then
    begin
      twin := NewProbe(cs.Objects['option'].AsJSON);
      twin.Render(FBmp2.Canvas, Rect(0, 0, cW, cH), 96);
    end;
    listen := TJSONObject(FRoot).Arrays['listen'];
    FListen.Clear;
    for i := 0 to listen.Count - 1 do
    begin
      t := listen.Strings[i];
      { zrender's two are heard where the frames are zrender's own }
      if ((t = 'rendered') or (t = 'finished')) and not flush then Continue;
      FListen.Add(t);
    end;
    { the actions' events through the catch-all; the three only a named
      handler hears, by name }
    FChart.OnChartEvent := @OnEvent;
    FChart.ChartOn('updated', @OnEvent);
    if flush then
    begin
      FChart.ChartOn('rendered', @OnEvent);
      FChart.ChartOn('finished', @OnEvent);
    end;
    hands := cs.Arrays['handlers'];
    FHandLeft := 0;
    FHandOn := '';
    FHandDispatch := '';
    FHandFlush := False;
    if hands.Count > 0 then
    begin
      FHandOn := hands.Objects[0].Strings['on'];
      FHandLeft := hands.Objects[0].Integers['times'];
      if hands.Objects[0].Find('dispatch') <> nil then
        FHandDispatch := hands.Objects[0].Objects['dispatch'].AsJSON;
      FHandFlush := (hands.Objects[0].Find('flush') <> nil)
        and hands.Objects[0].Booleans['flush'];
    end;
    now_ := 0;
    now2 := 0;
    pre := cs.Arrays['pre'];
    for j := 0 to pre.Count - 1 do
    begin
      FWhere := Format('%s pre %d', [AId, j]);
      RunStep(FChart, pre.Objects[j], FBmp, now_);
      if twin <> nil then RunStep(twin, pre.Objects[j], FBmp2, now2);
    end;
    { what the first frame flushed is not the steps' }
    FLog.Clear;
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      FWhere := Format('%s step %d (%s)', [AId, j, st.Strings['op']]);
      FLog.Clear;
      RunStep(FChart, st, FBmp, now_);
      CompareEvents(st.Arrays['events']);
      if st.Find('bars') <> nil then CompareBars(st.Arrays['bars']);
      if st.Find('covers') <> nil then CompareCovers(st.Arrays['covers']);
      if (twin = nil) or (st.Find('items') = nil) then Continue;
      items := st.Arrays['items'];
      for k := 0 to items.Count - 1 do
      begin
        twin.DispatchAction(StringReplace(items.Objects[k].AsJSON, cNulMark, '\u0000',
          [rfReplaceAll]), (st.Find('silent') <> nil) and st.Booleans['silent']);
        twin.Render(FBmp2.Canvas, Rect(0, 0, cW, cH), 96);
      end;
      twin.Render(FBmp2.Canvas, Rect(0, 0, cW, cH), 96);
      if not st.Booleans['sameAsItems'] then Continue;
      { the parallel axes' covers are their views' (BrushController), not the
        model's: the one update after a batch renders every view but the
        first the batch's own payload names, the items' each skip their own
        -- the spec records it; the events above are compared }
      if AId = 'b-axisareaselect' then Continue;
      { upstream's batch ends where its items one by one do: so here }
      FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      diff := 0;
      for y := 0 to cH - 1 do
      begin
        a := FBmp.ScanLine[y];
        b := FBmp2.ScanLine[y];
        for x := 0 to cW - 1 do
        begin
          if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) then Inc(diff);
          Inc(a);
          Inc(b);
        end;
      end;
      Inc(FCompared);
      if diff <> 0 then
        Bad(Format('the batch and its items one by one differ in %d pixels', [diff]));
    end;
  finally
    FChart.Free;
    FChart := nil;
    twin.Free;
  end;
  Finish(AId);
end;

procedure TAdvChartActionsBatchOracleTest.TestLegendScrollAsUpstream;
begin
  RunCase('b-legendscroll');
end;

procedure TAdvChartActionsBatchOracleTest.TestABatchThatIsNoListAsUpstream;
begin
  RunCase('b-legendscroll-object');
end;

procedure TAdvChartActionsBatchOracleTest.TestASilentBatchAsUpstream;
begin
  RunCase('b-legendscroll-silent');
end;

procedure TAdvChartActionsBatchOracleTest.TestSelectDataRangeAsUpstream;
begin
  RunCase('b-selectdatarange');
end;

procedure TAdvChartActionsBatchOracleTest.TestTheLegacyPieSelectAsUpstream;
begin
  RunCase('b-pietoggleselect');
end;

procedure TAdvChartActionsBatchOracleTest.TestGeoToggleSelectAsUpstream;
begin
  RunCase('b-geotoggleselect');
end;

procedure TAdvChartActionsBatchOracleTest.TestGeoRoamAsUpstream;
begin
  RunCase('b-georoam');
end;

procedure TAdvChartActionsBatchOracleTest.TestSunburstRootToNodeAsUpstream;
begin
  RunCase('b-sunburst');
end;

procedure TAdvChartActionsBatchOracleTest.TestTreemapRootToNodeAsUpstream;
begin
  RunCase('b-treemap');
end;

procedure TAdvChartActionsBatchOracleTest.TestGraphRoamAsUpstream;
begin
  RunCase('b-graphroam');
end;

procedure TAdvChartActionsBatchOracleTest.TestDragNodeAsUpstream;
begin
  RunCase('b-dragnode');
end;

procedure TAdvChartActionsBatchOracleTest.TestTakeGlobalCursorAsUpstream;
begin
  RunCase('b-takecursor');
end;

procedure TAdvChartActionsBatchOracleTest.TestBrushAsUpstream;
begin
  RunCase('b-brush');
end;

procedure TAdvChartActionsBatchOracleTest.TestBrushEndAsUpstream;
begin
  RunCase('b-brushend');
end;

procedure TAdvChartActionsBatchOracleTest.TestTimelineChangeAsUpstream;
begin
  RunCase('b-timeline');
end;

procedure TAdvChartActionsBatchOracleTest.TestTimelinePlayChangeAsUpstream;
begin
  RunCase('b-timelineplay');
end;

procedure TAdvChartActionsBatchOracleTest.TestAxisAreaSelectAsUpstream;
begin
  RunCase('b-axisareaselect');
end;

procedure TAdvChartActionsBatchOracleTest.TestParallelAxisExpandAsUpstream;
begin
  RunCase('b-axisexpand');
end;

procedure TAdvChartActionsBatchOracleTest.TestExpandAxisBreakAsUpstream;
begin
  RunCase('b-axisbreak');
end;

procedure TAdvChartActionsBatchOracleTest.TestShowTipAsUpstream;
begin
  RunCase('b-showtip');
end;

procedure TAdvChartActionsBatchOracleTest.TestShowTipOnItemsAsUpstream;
begin
  RunCase('b-showtip-item');
end;

procedure TAdvChartActionsBatchOracleTest.TestHideTipAsUpstream;
begin
  RunCase('b-hidetip');
end;

procedure TAdvChartActionsBatchOracleTest.TestUpdateAxisPointerAsUpstream;
begin
  RunCase('b-updateaxispointer');
end;

procedure TAdvChartActionsBatchOracleTest.TestALegacyActionsSelectWaitsAsUpstream;
begin
  RunCase('p-legacy');
end;

procedure TAdvChartActionsBatchOracleTest.TestAHandlersDispatchFlushesTheOuterQueueAsUpstream;
begin
  RunCase('p-nested');
end;

procedure TAdvChartActionsBatchOracleTest.TestASilentDispatchPublishesNothingAsUpstream;
begin
  RunCase('p-silent');
end;

procedure TAdvChartActionsBatchOracleTest.TestAHandlersDispatchRunsAtOnceAsUpstream;
begin
  RunCase('p-handler-later');
end;

procedure TAdvChartActionsBatchOracleTest.TestRenderedOnEveryFlushAsUpstream;
begin
  RunCase('r-hover');
end;

procedure TAdvChartActionsBatchOracleTest.TestRenderedWithoutATooltipAsUpstream;
begin
  RunCase('r-plain');
end;

procedure TAdvChartActionsBatchOracleTest.TestNoFinishedWhileAnActionWaitsAsUpstream;
begin
  RunCase('r-pending');
end;

procedure TAdvChartActionsBatchOracleTest.TestATimelineBatchRendersOnceAsUpstream;
begin
  RunCase('b-timeline-anim');
end;

procedure TAdvChartActionsBatchOracleTest.TestAnAxisAreaSelectBatchsCoversAsUpstream;
begin
  RunCase('b-axisareaselect-covers');
end;

procedure TAdvChartActionsBatchOracleTest.TestTheOuterPayloadNamesTheSkippedAxisAsUpstream;
begin
  RunCase('b-axisareaselect-outer');
end;

procedure TAdvChartActionsBatchOracleTest.TestABatchOfNoItemsUpdatesAsUpstream;
begin
  RunCase('r-zero-batch');
end;

procedure TAdvChartActionsBatchOracleTest.TestALegendItemsHoverFlushesAsUpstream;
begin
  RunCase('r-legend-hover');
end;

procedure TAdvChartActionsBatchOracleTest.TestAToolboxIconsHoverFlushesAsUpstream;
begin
  RunCase('r-toolbox-hover');
end;

procedure TAdvChartActionsBatchOracleTest.TestADataZoomHandlesHoverFlushesAsUpstream;
begin
  RunCase('r-dz-hover');
end;

procedure TAdvChartActionsBatchOracleTest.TestSetOptionRendersBeforeUpdatedAsUpstream;
begin
  RunCase('r-setoption');
end;

initialization
  RegisterTest(TAdvChartActionsBatchOracleTest);
end.
