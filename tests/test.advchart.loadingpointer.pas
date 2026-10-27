unit test.advchart.loadingpointer;
{$mode objfpc}{$H+}
{ THE LOADING EFFECT'S MASK AS THE POINTER'S TARGET, HELD TO UPSTREAM [R5-D].

  tools/advchart-oracle/loading-pointer.js runs the real ECharts 6.1 build in
  node (the harness of tooltip-actions.js): showLoading / hideLoading, the
  pointer through zrender's Handler. Its mask (z 10000, not silent) is the
  hover target over the whole chart: no mouseover, click or item tooltip of
  what is under it, no legend click, no slider drag, the cursor its
  'pointer'; the zr-level listeners still run -- the axis pointer and an axis
  tooltip, an inside dataZoom's wheel. After hideLoading the hover is looked
  for again where the pointer last was (no mouseover for it). Per step: the
  events (mouse events by componentType / seriesIndex / dataIndex / name,
  the actions' payloads), what the box shows, the cursor the step set and
  the axes shown.

  This replays them through TTyAdvanceChart with the probe of
  test.advchart.tooltipactions (the SSR width table, the box 80 x 40). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart.Thumbnail, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.tooltipactions;
type
  TLpProbe = class(TTaProbe)
  public
    procedure Down(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
  end;

  TAdvChartLoadingPointerOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    FTypes: TStringList;
    procedure Bad(const AWhat: string);
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnItemUnderTheMaskAsUpstream;
    procedure TestTheAxisPointerUnderTheMaskAsUpstream;
    procedure TestTheZoomUnderTheMaskAsUpstream;
    procedure TestAZlevelAsUpstream;
    { [R5-D] the thumbnail's box over a node; on a calendar and a matrix }
    procedure TestTheThumbnailsBoxAsUpstream;
    procedure TestAThumbnailOverACalendarGraphAsUpstream;
    procedure TestAThumbnailOverAMatrixGraphAsUpstream;
  end;

  { [R5-D] tools/advchart-oracle/inside-roam-coordsys.js: an inside
    dataZoom on a single axis and on a polar -- one roam record per
    coordinate system, its containPoint, getDirectionInfo.singleAxis /
    .polar; per step the datazoom events, the cursor and every inside's
    view range }
  TAdvChartInsideRoamCoordSysOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    procedure Bad(const AWhat: string);
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAHorizontalSingleAxisAsUpstream;
    procedure TestAVerticalInverseSingleAxisAsUpstream;
    procedure TestThePolarRadiusAsUpstream;
    procedure TestThePolarAngleAsUpstream;
    procedure TestBothPolarAxesAsUpstream;
  end;

  { [R5-D] tools/advchart-oracle/pointer-handle.js: axisPointer.handle --
    shown from the start at the value (fixValue), kept shown, dragged (the
    press's dispatch, each drift's through the throttle, the release onto
    the value and a hideTip), on a cartesian x and y axis, from the
    axisPointer component, on a single axis; per step the
    updateaxispointer / showtip / hidetip events, the cursor, each handle's
    value and place }
  TAdvChartPointerHandleOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    procedure Bad(const AWhat: string);
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestACategoryXHandleAsUpstream;
    procedure TestAValueYHandleAsUpstream;
    procedure TestTheComponentsHandleAsUpstream;
    procedure TestASingleAxisHandleAsUpstream;
    { the handle is painted where it stands, the pointer at its value }
    procedure TestTheHandleIsDrawn;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cNulMark = #$E2#$90#$80;

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

procedure TLpProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TLpProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TAdvChartLoadingPointerOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TStringList.Create;
  FTypes := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-loading-pointer.json'));
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

procedure TAdvChartLoadingPointerOracleTest.TearDown;
begin
  FLog.Free;
  FTypes.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartLoadingPointerOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartLoadingPointerOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
var o: TJSONObject;
begin
  if FTypes.IndexOf(AEvent.EventType) < 0 then Exit;
  if AEvent.HasParams then
  begin
    { a mouse event: what the oracle keeps of its params }
    o := TJSONObject.Create;
    try
      o.Add('componentType', AEvent.Params.ComponentType);
      if AEvent.Params.SeriesIndex >= 0 then o.Add('seriesIndex', AEvent.Params.SeriesIndex)
      else o.Add('seriesIndex', TJSONNull.Create);
      if AEvent.Params.DataIndex >= 0 then o.Add('dataIndex', AEvent.Params.DataIndex)
      else o.Add('dataIndex', TJSONNull.Create);
      o.Add('name', AEvent.Params.Name);
      FLog.Add(AEvent.EventType + #9 + o.AsJSON);
    finally
      o.Free;
    end;
  end
  else
    FLog.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAdvChartLoadingPointerOracleTest.RunCase(const AId: string);
var
  cases, steps, want, pts: TJSONArray;
  cs, st, state: TJSONObject;
  probe: TLpProbe;
  i, j, k: Integer;
  op, axes: string;
  now_, t0: Double;
  e: TJSONArray;
  parts: TStringList;
  got: TJSONData;
  hits: TTyAxisHitArray;
  th: TJSONObject;
  ts: TTyThumbState;

  procedure SameRect(const AWhat: string; const AGot: TTyXYWH; AWant: TJSONArray);
  begin
    Inc(FCompared);
    if (Abs(AGot.X - AWant.Floats[0]) > 1e-6) or (Abs(AGot.Y - AWant.Floats[1]) > 1e-6)
      or (Abs(AGot.W - AWant.Floats[2]) > 1e-6) or (Abs(AGot.H - AWant.Floats[3]) > 1e-6) then
      Bad(Format('%s [%g, %g, %g, %g], upstream %s', [AWhat, AGot.X, AGot.Y, AGot.W, AGot.H,
        AWant.AsJSON]));
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  { the event types the case listens to }
  FTypes.Clear;
  for i := 0 to cs.Arrays['types'].Count - 1 do FTypes.Add(cs.Arrays['types'].Strings[i]);
  probe := TLpProbe.Create(FForm);
  parts := TStringList.Create;
  try
    probe.Parent := FForm;
    probe.Controller := FCtl;
    probe.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
      TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
      TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
    probe.TooltipNow := 0;
    t0 := TJSONObject(FRoot).Objects['clock'].Floats['start'];
    probe.DataZoomNow := t0;
    probe.AnimationMode := camOff;
    probe.SetBounds(0, 0, cW, cH);
    probe.Option := cs.Arrays['charts'].Objects[0].Objects['option'].AsJSON;
    probe.OnChartEvent := @OnEvent;
    probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
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
      if (op <> 'idle') and (op <> 'show') and (op <> 'hide') then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else if op = 'idle' then
        now_ := now_ + st.Floats['ms'];
      probe.TooltipNow := now_;
      probe.TooltipTick(now_);
      probe.DataZoomNow := t0 + now_;
      probe.DataZoomTick(t0 + now_);
      if op = 'move' then
        probe.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'click' then
      begin
        probe.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1]);
        probe.Click(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1]);
      end
      else if op = 'wheel' then
        probe.Wheel(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1],
          st.Integers['delta'])
      else if op = 'drag' then
      begin
        pts := st.Arrays['points'];
        probe.Move(pts.Arrays[0].Integers[0], pts.Arrays[0].Integers[1]);
        probe.Down(pts.Arrays[0].Integers[0], pts.Arrays[0].Integers[1]);
        { 200 ms between the moves, and before the release }
        for k := 1 to pts.Count - 1 do
        begin
          now_ := now_ + 200;
          probe.TooltipNow := now_;
          probe.TooltipTick(now_);
          probe.DataZoomNow := t0 + now_;
          probe.DataZoomTick(t0 + now_);
          probe.Move(pts.Arrays[k].Integers[0], pts.Arrays[k].Integers[1]);
        end;
        now_ := now_ + 200;
        probe.TooltipNow := now_;
        probe.TooltipTick(now_);
        probe.DataZoomNow := t0 + now_;
        probe.DataZoomTick(t0 + now_);
        k := pts.Count - 1;
        probe.Up(pts.Arrays[k].Integers[0], pts.Arrays[k].Integers[1]);
      end
      else if op = 'leave' then
        probe.Leave
      else if op = 'show' then
      begin
        if st.Find('cfg') <> nil then probe.ShowLoading(st.Objects['cfg'].AsJSON)
        else probe.ShowLoading('');
      end
      else if op = 'hide' then
        probe.HideLoading;
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      { the events }
      want := st.Arrays['events'];
      Inc(FCompared);
      if FLog.Count <> want.Count then
      begin
        Bad(Format('%d events, upstream %d', [FLog.Count, want.Count]));
        for i := 0 to FLog.Count - 1 do Bad('  port: ' + Copy(FLog[i], 1, 160));
        for i := 0 to want.Count - 1 do Bad('  upstream: ' + Copy(want.Items[i].AsJSON, 1, 160));
      end
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
          got := GetJSON(StringReplace(parts[1], '\u0000', cNulMark, [rfReplaceAll]));
          try
            FromIsUid(got);
            Inc(FCompared);
            if not SameJson(e.Items[2], got) then
              Bad(Format('event %d (%s): %s, upstream %s', [i, parts[0],
                Copy(got.AsJSON, 1, 300), Copy(e.Items[2].AsJSON, 1, 300)]));
          finally
            got.Free;
          end;
        end;
      { the state }
      state := st.Arrays['state'].Objects[0];
      Inc(FCompared);
      if state.Find('tip').JSONType = jtNull then
      begin
        if probe.TooltipShown then Bad('a box, upstream none: ' + probe.Which);
      end
      else if not probe.TooltipShown then
        Bad('no box, upstream ' + state.Strings['tip'])
      else if probe.Which <> state.Strings['tip'] then
        Bad(Format('the box shows %s, upstream %s', [probe.Which, state.Strings['tip']]));
      if state.Find('cursor').JSONType = jtString then
      begin
        Inc(FCompared);
        if probe.CursorName <> state.Strings['cursor'] then
          Bad(Format('cursor %s, upstream %s', [probe.CursorName, state.Strings['cursor']]));
      end;
      hits := probe.Hits;
      axes := '';
      for k := 0 to High(hits) do
      begin
        if axes <> '' then axes := axes + ',';
        axes := axes + hits[k].Axis.Dim + IntToStr(hits[k].Axis.ComponentIndex);
      end;
      want := state.Arrays['pointers'];
      parts.Clear;
      for k := 0 to want.Count - 1 do parts.Add(want.Strings[k]);
      parts.Delimiter := ',';
      Inc(FCompared);
      if axes <> parts.DelimitedText then
        Bad(Format('pointers [%s], upstream [%s]', [axes, parts.DelimitedText]));
      parts.Delimiter := #9;
      { [R5-D] the thumbnail: its box, its window (an empty one where the
        graph is on no view), the copy's items }
      if state.Find('thumb') <> nil then
      begin
        Inc(FCompared);
        if state.Find('thumb').JSONType = jtNull then
        begin
          if (probe.ThumbnailCount > 0) and probe.ThumbnailState(0).Enabled then
            Bad('a thumbnail, upstream none');
        end
        else if (probe.ThumbnailCount = 0) or not probe.ThumbnailState(0).Enabled then
          Bad('no thumbnail, upstream one')
        else
        begin
          th := state.Objects['thumb'];
          ts := probe.ThumbnailState(0);
          SameRect('the box', ts.Box, th.Arrays['box']);
          if ts.View.Valid then SameRect('the window', ts.Window, th.Arrays['window'])
          else SameRect('the window', TyXYWH(0, 0, 0, 0), th.Arrays['window']);
          Inc(FCompared);
          if Length(ts.Items) <> th.Integers['copy'] then
            Bad(Format('%d copied items, upstream %d', [Length(ts.Items), th.Integers['copy']]));
        end;
      end;
    end;
  finally
    parts.Free;
    probe.Free;
  end;
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartLoadingPointerOracleTest.TestAnItemUnderTheMaskAsUpstream;
begin
  RunCase('item');
end;

procedure TAdvChartLoadingPointerOracleTest.TestTheAxisPointerUnderTheMaskAsUpstream;
begin
  RunCase('axis');
end;

procedure TAdvChartLoadingPointerOracleTest.TestTheZoomUnderTheMaskAsUpstream;
begin
  RunCase('zoom');
end;

procedure TAdvChartLoadingPointerOracleTest.TestAZlevelAsUpstream;
begin
  RunCase('zlevel');
end;

procedure TAdvChartLoadingPointerOracleTest.TestTheThumbnailsBoxAsUpstream;
begin
  RunCase('thumb');
end;

procedure TAdvChartLoadingPointerOracleTest.TestAThumbnailOverACalendarGraphAsUpstream;
begin
  RunCase('thumb-calendar');
end;

procedure TAdvChartLoadingPointerOracleTest.TestAThumbnailOverAMatrixGraphAsUpstream;
begin
  RunCase('thumb-matrix');
end;

{ ==================== the inside roam on a polar and a single ==================== }

procedure TAdvChartInsideRoamCoordSysOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-inside-roam-coordsys.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if AEvent.EventType <> 'datazoom' then Exit;
  FLog.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.RunCase(const AId: string);
var
  cases, steps, want, pts, dzs: TJSONArray;
  cs, st, state: TJSONObject;
  probe: TLpProbe;
  i, j, k, n: Integer;
  op: string;
  now_, t0, lo, hi: Double;
  e: TJSONArray;
  parts: TStringList;
  got, opt: TJSONData;
  insides: array of Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  { the inside dataZooms, in component order }
  opt := cs.Arrays['charts'].Objects[0].Objects['option'];
  insides := nil;
  if TJSONObject(opt).Find('dataZoom') is TJSONArray then
  begin
    dzs := TJSONObject(opt).Arrays['dataZoom'];
    for i := 0 to dzs.Count - 1 do
      if dzs.Objects[i].Get('type', '') = 'inside' then
      begin
        SetLength(insides, Length(insides) + 1);
        insides[High(insides)] := i;
      end;
  end;
  probe := TLpProbe.Create(FForm);
  parts := TStringList.Create;
  try
    probe.Parent := FForm;
    probe.Controller := FCtl;
    probe.TooltipNow := 0;
    t0 := TJSONObject(FRoot).Objects['clock'].Floats['start'];
    probe.DataZoomNow := t0;
    probe.AnimationMode := camOff;
    probe.SetBounds(0, 0, cW, cH);
    probe.Option := opt.AsJSON;
    probe.OnChartEvent := @OnEvent;
    probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
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
      if op <> 'idle' then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else
        now_ := now_ + st.Floats['ms'];
      probe.TooltipNow := now_;
      probe.TooltipTick(now_);
      probe.DataZoomNow := t0 + now_;
      probe.DataZoomTick(t0 + now_);
      if op = 'move' then
        probe.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'wheel' then
      begin
        probe.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1]);
        probe.Wheel(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1],
          st.Integers['delta']);
      end
      else if op = 'drag' then
      begin
        pts := st.Arrays['points'];
        probe.Move(pts.Arrays[0].Integers[0], pts.Arrays[0].Integers[1]);
        probe.Down(pts.Arrays[0].Integers[0], pts.Arrays[0].Integers[1]);
        for k := 1 to pts.Count - 1 do
        begin
          now_ := now_ + 200;
          probe.TooltipNow := now_;
          probe.TooltipTick(now_);
          probe.DataZoomNow := t0 + now_;
          probe.DataZoomTick(t0 + now_);
          probe.Move(pts.Arrays[k].Integers[0], pts.Arrays[k].Integers[1]);
        end;
        now_ := now_ + 200;
        probe.TooltipNow := now_;
        probe.TooltipTick(now_);
        probe.DataZoomNow := t0 + now_;
        probe.DataZoomTick(t0 + now_);
        k := pts.Count - 1;
        probe.Up(pts.Arrays[k].Integers[0], pts.Arrays[k].Integers[1]);
      end;
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      { the events }
      want := st.Arrays['events'];
      Inc(FCompared);
      if FLog.Count <> want.Count then
      begin
        Bad(Format('%d events, upstream %d', [FLog.Count, want.Count]));
        for i := 0 to FLog.Count - 1 do Bad('  port: ' + Copy(FLog[i], 1, 300));
        for i := 0 to want.Count - 1 do Bad('  upstream: ' + Copy(want.Items[i].AsJSON, 1, 300));
      end
      else
        for i := 0 to want.Count - 1 do
        begin
          e := TJSONArray(want.Items[i]);
          parts.DelimitedText := FLog[i];
          got := GetJSON(StringReplace(parts[1], '\u0000', cNulMark, [rfReplaceAll]));
          try
            FromIsUid(got);
            Inc(FCompared);
            if not SameJson(e.Items[2], got) then
              Bad(Format('event %d: %s, upstream %s', [i, Copy(got.AsJSON, 1, 300),
                Copy(e.Items[2].AsJSON, 1, 300)]));
          finally
            got.Free;
          end;
        end;
      { the state }
      state := st.Arrays['state'].Objects[0];
      if state.Find('cursor').JSONType = jtString then
      begin
        Inc(FCompared);
        if probe.CursorName <> state.Strings['cursor'] then
          Bad(Format('cursor %s, upstream %s', [probe.CursorName, state.Strings['cursor']]));
      end;
      want := state.Arrays['ranges'];
      n := Min(want.Count, Length(insides));
      Inc(FCompared);
      if want.Count <> Length(insides) then Bad('the insides differ in number');
      for k := 0 to n - 1 do
      begin
        Inc(FCompared);
        probe.DataZoomInsideRange(insides[k], lo, hi);
        if (lo <> want.Arrays[k].Floats[0]) or (hi <> want.Arrays[k].Floats[1]) then
          Bad(Format('inside %d range [%.17g, %.17g], upstream %s', [insides[k], lo, hi,
            want.Items[k].AsJSON]));
      end;
    end;
  finally
    parts.Free;
    probe.Free;
  end;
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.TestAHorizontalSingleAxisAsUpstream;
begin
  RunCase('single-h');
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.TestAVerticalInverseSingleAxisAsUpstream;
begin
  RunCase('single-v');
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.TestThePolarRadiusAsUpstream;
begin
  RunCase('polar-radius');
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.TestThePolarAngleAsUpstream;
begin
  RunCase('polar-angle');
end;

procedure TAdvChartInsideRoamCoordSysOracleTest.TestBothPolarAxesAsUpstream;
begin
  RunCase('polar-both');
end;

{ ==================== the axis pointer's handle ==================== }

procedure TAdvChartPointerHandleOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-pointer-handle.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartPointerHandleOracleTest.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartPointerHandleOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartPointerHandleOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType <> 'updateaxispointer') and (AEvent.EventType <> 'showtip')
    and (AEvent.EventType <> 'hidetip') then Exit;
  FLog.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAdvChartPointerHandleOracleTest.RunCase(const AId: string);
var
  cases, steps, want, pts, hs: TJSONArray;
  cs, st, state, hw, hh: TJSONObject;
  probe: TLpProbe;
  i, j, k, n: Integer;
  op: string;
  now_, t0: Double;
  e: TJSONArray;
  parts: TStringList;
  got, opt: TJSONData;
  ps: TTyPointerHandleState;

  procedure Near(const AWhat: string; AGot, AWant, ATol: Double);
  begin
    Inc(FCompared);
    if not (Abs(AGot - AWant) <= ATol) then
      Bad(Format('%s %.17g, upstream %.17g', [AWhat, AGot, AWant]));
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  opt := cs.Arrays['charts'].Objects[0].Objects['option'];
  probe := TLpProbe.Create(FForm);
  parts := TStringList.Create;
  try
    probe.Parent := FForm;
    probe.Controller := FCtl;
    probe.TooltipNow := 0;
    t0 := TJSONObject(FRoot).Objects['clock'].Floats['start'];
    probe.DataZoomNow := t0;
    probe.AnimationMode := camOff;
    probe.SetBounds(0, 0, cW, cH);
    probe.Option := opt.AsJSON;
    probe.OnChartEvent := @OnEvent;
    probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
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
      if op <> 'idle' then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else
        now_ := now_ + st.Floats['ms'];
      probe.TooltipNow := now_;
      probe.TooltipTick(now_);
      if op = 'move' then
        probe.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'leave' then
        probe.Leave
      else if op = 'drag' then
      begin
        pts := st.Arrays['points'];
        probe.Move(pts.Arrays[0].Integers[0], pts.Arrays[0].Integers[1]);
        probe.Down(pts.Arrays[0].Integers[0], pts.Arrays[0].Integers[1]);
        for k := 1 to pts.Count - 1 do
        begin
          now_ := now_ + 200;
          probe.TooltipNow := now_;
          probe.TooltipTick(now_);
          probe.Move(pts.Arrays[k].Integers[0], pts.Arrays[k].Integers[1]);
        end;
        now_ := now_ + 200;
        probe.TooltipNow := now_;
        probe.TooltipTick(now_);
        k := pts.Count - 1;
        probe.Up(pts.Arrays[k].Integers[0], pts.Arrays[k].Integers[1]);
      end;
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      { the events }
      want := st.Arrays['events'];
      Inc(FCompared);
      if FLog.Count <> want.Count then
      begin
        Bad(Format('%d events, upstream %d', [FLog.Count, want.Count]));
        for i := 0 to FLog.Count - 1 do Bad('  port: ' + Copy(FLog[i], 1, 300));
        for i := 0 to want.Count - 1 do Bad('  upstream: ' + Copy(want.Items[i].AsJSON, 1, 300));
      end
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
          got := GetJSON(StringReplace(parts[1], '\u0000', cNulMark, [rfReplaceAll]));
          try
            FromIsUid(got);
            Inc(FCompared);
            if not SameJson(e.Items[2], got) then
              Bad(Format('event %d (%s): %s, upstream %s', [i, parts[0], Copy(got.AsJSON, 1, 500),
                Copy(e.Items[2].AsJSON, 1, 500)]));
          finally
            got.Free;
          end;
        end;
      { the state }
      state := st.Arrays['state'].Objects[0];
      if state.Find('cursor').JSONType = jtString then
      begin
        Inc(FCompared);
        if probe.CursorName <> state.Strings['cursor'] then
          Bad(Format('cursor %s, upstream %s', [probe.CursorName, state.Strings['cursor']]));
      end;
      hs := state.Arrays['handles'];
      n := probe.PointerHandleCount;
      Inc(FCompared);
      if n <> hs.Count then
      begin
        Bad(Format('%d handles, upstream %d', [n, hs.Count]));
        Continue;
      end;
      for k := 0 to n - 1 do
      begin
        hw := hs.Objects[k];
        ps := probe.PointerHandleState(k);
        Inc(FCompared);
        if ps.Key <> hw.Strings['axis'] then Bad(Format('handle %d: %s, upstream %s', [k, ps.Key, hw.Strings['axis']]));
        Inc(FCompared);
        if hw.Strings['status'] <> 'show' then Bad('upstream status ' + hw.Strings['status']);
        Near(hw.Strings['axis'] + ' value', ps.Value, hw.Floats['value'], 1e-9);
        if not (hw.Find('handle') is TJSONObject) then
        begin
          Bad('no handle upstream');
          Continue;
        end;
        hh := hw.Objects['handle'];
        Near(hw.Strings['axis'] + ' x', ps.X, hh.Floats['x'], 1e-6);
        Near(hw.Strings['axis'] + ' y', ps.Y, hh.Floats['y'], 1e-6);
        Near(hw.Strings['axis'] + ' rotation', ps.Rotation, hh.Floats['rotation'], 1e-9);
        Near(hw.Strings['axis'] + ' scaleX', ps.ScaleX, hh.Floats['scaleX'], 1e-9);
        Near(hw.Strings['axis'] + ' scaleY', ps.ScaleY, hh.Floats['scaleY'], 1e-9);
        { a colour the option wrote (upstream's default is its theme's
          accent, here the skin's) }
        if Pos('#ff0000', opt.AsJSON) > 0 then
        begin
          Inc(FCompared);
          if (not ps.HasFill) or (ps.Fill <> TTyChartColor($FFFF0000)) then
            Bad(Format('fill %x, upstream %s', [ps.Fill, hh.Strings['fill']]));
        end;
      end;
    end;
  finally
    parts.Free;
    probe.Free;
  end;
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartPointerHandleOracleTest.TestACategoryXHandleAsUpstream;
begin
  RunCase('x-category');
end;

procedure TAdvChartPointerHandleOracleTest.TestAValueYHandleAsUpstream;
begin
  RunCase('y-value');
end;

procedure TAdvChartPointerHandleOracleTest.TestTheComponentsHandleAsUpstream;
begin
  RunCase('global');
end;

procedure TAdvChartPointerHandleOracleTest.TestASingleAxisHandleAsUpstream;
begin
  RunCase('single');
end;

procedure TAdvChartPointerHandleOracleTest.TestTheHandleIsDrawn;
var
  probe: TLpProbe;
  ps: TTyPointerHandleState;
  c: TBGRAPixel;
  ink, y: Integer;
  dbg: string;
begin
  probe := TLpProbe.Create(FForm);
  try
    probe.Parent := FForm;
    probe.Controller := FCtl;
    probe.AnimationMode := camOff;
    probe.SetBounds(0, 0, cW, cH);
    probe.Option := '{"xAxis":{"type":"category","data":["a","b","c","d","e"],'
      + '"axisPointer":{"handle":{"show":true,"color":"#ff0000"}}},"yAxis":{},'
      + '"series":[{"type":"line","data":[3,7,2,5,6]}]}';
    FBmp.Fill(BGRA(255, 255, 255, 255));
    probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    AssertEquals('one handle', 1, probe.PointerHandleCount);
    ps := probe.PointerHandleState(0);
    { the icon's body above its centre, in its colour }
    c := FBmp.GetPixel(Round(ps.X), Round(ps.Y - 0.6 * ps.ScaleY));
    AssertTrue(Format('the handle is red there: %d %d %d', [c.red, c.green, c.blue]),
      (c.red > 200) and (c.green < 60) and (c.blue < 60));
    { and its pointer: a line across the plot at the value's x (the last
      category), above the handle }
    { (dashed: some of the column; the series' line crosses it nowhere
      but at its last point) }
    ink := 0;
    dbg := '';
    for y := 100 to 140 do
    begin
      c := FBmp.GetPixel(Round(ps.X), y);
      dbg := dbg + IntToStr(c.red) + ' ';
      if (c.red < 250) or (c.green < 250) or (c.blue < 250) then Inc(ink);
    end;
    AssertTrue(Format('the pointer stands at the value: %d inked at x %g: %s', [ink, ps.X, dbg]), ink >= 10);
  finally
    probe.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartLoadingPointerOracleTest);
  RegisterTest(TAdvChartPointerHandleOracleTest);
  RegisterTest(TAdvChartInsideRoamCoordSysOracleTest);
end.
