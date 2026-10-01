unit test.advchart.mouseevents;
{$mode objfpc}{$H+}
{ THE CHART'S MOUSE EVENTS, held to upstream.

  tools/advchart-oracle/mouse-events.js drives zrender's handler through
  scripted pointer steps over the real ECharts 6.1 build, with a handler for
  every one of the nine chart events and forty-odd query-filtered ones, and
  records what fires, in order, with its params. This replays the same steps
  through the control's own event path -- the move, the press, the release
  and its click, the double click, the context menu, leaving the canvas --
  with the same registrations made through ChartOn, and compares the events
  one by one: type, handler, and every params field upstream holds (and none
  it does not).

  Upstream's published action events (select, selectchanged,
  legendselectchanged, ...) are compared too, through a 'pub' handler for
  each: the selection's since batch 88, the legend's (an item's hover
  highlight / downplay, its click's legendselectchanged) since batch 93. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.Measure, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TMeProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Down(AButton: TMouseButton; AX, AY: Integer);
    procedure Up(AButton: TMouseButton; AX, AY: Integer);
    procedure Dbl(AX, AY: Integer);
    procedure Ctx(AX, AY: Integer);
    procedure Leave(AX, AY: Integer);
  end;

  { one registration's handler: it writes what it was given into the log }
  TMeLogger = class
  public
    Id: string;
    Log: TStrings;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartMouseEventsOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMeProbe;
    FRoot: TJSONData;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FLog: TStringList;
    FLoggers: TList;
    FBad, FCompared: Integer;
    FReport: string;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Register;
    procedure Run(const AOnly: string; AMinimum: Integer);
  published
    procedure TestMouseEventsAsUpstream;
    procedure TestAnUnknownTypeIsRefusedAndOffRemoves;
  end;

implementation

{ Steps the port cannot follow yet, by case and the step from which on: what
  upstream does to the picture there is a later batch's. }
const
  cStopAt: array[0..1] of record Case_: string; Step: Integer; end = (
    { a treemap and a sunburst click drill in: the drilled picture is C6's }
    (Case_: 'treemap-zoom'; Step: 3),
    (Case_: 'sunburst'; Step: 3)
    { [Batch 93: 'legend-trigger' stopped at step 3, the legend click being
      B3's -- it runs to the end now] }
  );

const
  cPubTypes: array[0..10] of string = ('select', 'unselect', 'toggleselect',
    'selectchanged', 'highlight', 'downplay',
    { the legend's [Batch 93] }
    'legendselectchanged', 'legendselected', 'legendunselected',
    'legendselectall', 'legendinverseselect');

{ ==================== the probe ==================== }

procedure TMeProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ ZRENDER'S OWN MEASURE, as the other oracle tests replay it: a title's and
  an axis label's hit box is the text's, and the machine's fonts would put
  it a pixel or three from upstream's }
function TMeProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TMeProbe.Move(AX, AY: Integer);
begin
  EventMove(AX, AY);
end;

procedure TMeProbe.Down(AButton: TMouseButton; AX, AY: Integer);
begin
  EventDown(AButton, AX, AY);
end;

procedure TMeProbe.Up(AButton: TMouseButton; AX, AY: Integer);
begin
  EventUp(AButton, AX, AY);
end;

procedure TMeProbe.Dbl(AX, AY: Integer);
begin
  EventDblClick(AX, AY);
end;

procedure TMeProbe.Ctx(AX, AY: Integer);
begin
  EventContextMenu(AX, AY);
end;

procedure TMeProbe.Leave(AX, AY: Integer);
begin
  { upstream's out carries the point the pointer left at }
  EventLeave(AX, AY);
end;

{ ==================== the log ==================== }

function Field(const AKey, AValue: string): string;
begin
  Result := AKey + '=' + AValue + ';';
end;

{ an event as a line: the handler, the type, then every field upstream holds
  in a fixed order -- ours by the port's own presence rules }
procedure TMeLogger.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var
  p: TTyChartCallbackParams;
  s: string;
  marker: Boolean;
begin
  s := 'h=' + Id + ';' + Field('type', AEvent.EventType);
  if AEvent.HasParams then
  begin
    p := AEvent.Params;
    marker := (p.ComponentType = 'markPoint') or (p.ComponentType = 'markLine')
      or (p.ComponentType = 'markArea');
    if p.ComponentType <> '' then s := s + Field('componentType', p.ComponentType);
    if (p.ComponentType = 'series') or marker then
      s := s + Field('componentSubType', p.ComponentSubType);
    if p.ComponentIndex >= 0 then s := s + Field('componentIndex', IntToStr(p.ComponentIndex));
    if p.SeriesType <> '' then s := s + Field('seriesType', p.SeriesType);
    if p.SeriesIndex >= 0 then s := s + Field('seriesIndex', IntToStr(p.SeriesIndex));
    if p.SeriesId <> '' then s := s + Field('seriesId', p.SeriesId);
    if p.SeriesType <> '' then
      s := s + Field('seriesName', StringReplace(p.SeriesName, #0, '', [rfReplaceAll]));
    if ((p.ComponentType = 'series') and (p.SelfType = '')) or marker
      or (p.TargetType = 'axisName') then
      s := s + Field('name', p.Name);
    if p.RawDataIndex >= 0 then s := s + Field('dataIndex', IntToStr(p.RawDataIndex));
    if p.DataType <> '' then s := s + Field('dataType', p.DataType);
    if p.ValueText <> '' then s := s + Field('value', p.ValueText);
    if p.TargetType <> '' then s := s + Field('targetType', p.TargetType);
    if p.TickIndex >= 0 then s := s + Field('tickIndex', IntToStr(p.TickIndex));
    if p.SelfType <> '' then s := s + Field('selfType', p.SelfType);
    if p.AxisIndex >= 0 then
      s := s + Field(p.AxisDimension + 'AxisIndex', IntToStr(p.AxisIndex));
  end;
  if AEvent.HasOffset then
    s := s + Field('offsetX', IntToStr(AEvent.OffsetX))
      + Field('offsetY', IntToStr(AEvent.OffsetY));
  Log.Add(s);
end;

{ upstream's event as the same line }
function UpstreamLine(E: TJSONObject): string;
const
  cKeys: array[0..17] of string = ('componentType', 'componentSubType',
    'componentIndex', 'seriesType', 'seriesIndex', 'seriesId', 'seriesName',
    'name', 'dataIndex', 'dataType', 'value', 'targetType', 'tickIndex',
    'selfType', 'xAxisIndex', 'yAxisIndex', 'offsetX', 'offsetY');
var
  i: Integer;
  d: TJSONData;
  v: string;
begin
  Result := 'h=' + E.Strings['h'] + ';' + Field('type', E.Strings['type']);
  for i := 0 to High(cKeys) do
  begin
    d := E.Find(cKeys[i]);
    if (d = nil) or (d.JSONType = jtNull) then Continue;
    if d.JSONType = jtNumber then v := IntToStr(Round(d.AsFloat))
    else v := d.AsString;
    Result := Result + Field(cKeys[i], v);
  end;
end;

{ ==================== plumbing ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-mouse-events.json';
end;

procedure TAdvChartMouseEventsOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TMeProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FLog := TStringList.Create;
  FLoggers := TList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
    { the width table zrender measures with, as text-style.js recorded it }
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartMouseEventsOracleTest.TearDown;
var i: Integer;
begin
  for i := 0 to FLoggers.Count - 1 do TObject(FLoggers[i]).Free;
  FLoggers.Free;
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

{ the fixture's registrations, in its order: one logger each, and the one
  that says sameFnAs shares its partner's -- so the chart sees the same
  method twice }
procedure TAdvChartMouseEventsOracleTest.Register;
var
  regs: TJSONArray;
  r: TJSONObject;
  i, k: Integer;
  lg: TMeLogger;
  q: string;
  d: TJSONData;
begin
  regs := TJSONObject(FRoot).Arrays['registrations'];
  for i := 0 to regs.Count - 1 do
  begin
    r := regs.Objects[i];
    lg := nil;
    if r.Find('sameFnAs') <> nil then
      for k := 0 to FLoggers.Count - 1 do
        if TMeLogger(FLoggers[k]).Id = r.Strings['sameFnAs'] then
          lg := TMeLogger(FLoggers[k]);
    if lg = nil then
    begin
      lg := TMeLogger.Create;
      lg.Id := r.Strings['id'];
      lg.Log := FLog;
      FLoggers.Add(lg);
    end;
    d := r.Find('query');
    if d = nil then q := ''
    else if d.JSONType = jtString then q := d.AsString
    else q := d.AsJSON;
    FChart.ChartOn(r.Strings['type'], @lg.Handle, q);
  end;
  { THEN 'pub', one plain handler for every event type the chart publishes
    (the oracle's chart._messageCenter types): the selection's are the
    port's since batch 88, so an item click's select / selectchanged are
    compared here too, across every series type of this fixture; the
    legend's since batch 93. The drill-downs' are not emitted yet. }
  lg := TMeLogger.Create;
  lg.Id := 'pub';
  lg.Log := FLog;
  FLoggers.Add(lg);
  for i := 0 to High(cPubTypes) do
    FChart.ChartOn(cPubTypes[i], @lg.Handle);
end;

procedure TAdvChartMouseEventsOracleTest.Run(const AOnly: string; AMinimum: Integer);
var
  cases, steps, evs: TJSONArray;
  cs, st: TJSONObject;
  c, s, e, k, stop: Integer;
  want: TStringList;
  kind: string;
  b: TMouseButton;
  x, y: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  want := TStringList.Create;
  try
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      if (AOnly <> '') and (cs.Strings['id'] <> AOnly) then Continue;
      stop := MaxInt;
      for k := 0 to High(cStopAt) do
        if cStopAt[k].Case_ = cs.Strings['id'] then stop := cStopAt[k].Step;
      { a fresh chart per case: its bookkeeping starts from nothing }
      FChart.Free;
      FChart := TMeProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
      FChart.Option := cs.Objects['option'].AsJSON;
      FChart.SetBounds(0, 0, 600, 400);
      FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
      Register;
      steps := cs.Arrays['steps'];
      for s := 0 to steps.Count - 1 do
      begin
        if s >= stop then Break;
        st := steps.Objects[s];
        kind := st.Strings['type'];
        x := st.Get('x', 0);
        y := st.Get('y', 0);
        if st.Get('button', 0) = 2 then b := mbRight else b := mbLeft;
        FLog.Clear;
        if kind = 'move' then FChart.Move(x, y)
        else if kind = 'down' then FChart.Down(b, x, y)
        else if kind = 'up' then FChart.Up(b, x, y)
        else if kind = 'dblclick' then FChart.Dbl(x, y)
        else if kind = 'contextmenu' then FChart.Ctx(x, y)
        else if kind = 'leave' then FChart.Leave(x, y);
        { the scene as upstream re-renders it between steps }
        FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
        want.Clear;
        evs := st.Arrays['events'];
        for e := 0 to evs.Count - 1 do
          if TyChartEventTypeOf(evs.Objects[e].Strings['type']) <> '' then
            { [Batch 93: a legend item's hover highlight / downplay was
              filtered out here as B3's; it is compared now] }
            want.Add(UpstreamLine(evs.Objects[e]));
        Inc(FCompared);
        if want.Text <> FLog.Text then
        begin
          Inc(FBad);
          if Length(FReport) < 7000 then
            FReport := FReport + LineEnding + Format('%s step %d (%s %d,%d):',
              [cs.Strings['id'], s, kind, x, y]) + LineEnding + '  upstream:'
              + LineEnding + '    ' + StringReplace(Trim(want.Text), LineEnding,
              LineEnding + '    ', [rfReplaceAll]) + LineEnding + '  here:' + LineEnding
              + '    ' + StringReplace(Trim(FLog.Text), LineEnding, LineEnding + '    ',
              [rfReplaceAll]);
        end;
      end;
      for k := 0 to FLoggers.Count - 1 do TObject(FLoggers[k]).Free;
      FLoggers.Clear;
    end;
  finally
    want.Free;
  end;
  AssertTrue(Format('%d of %d steps differ:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('only %d steps compared', [FCompared]), FCompared >= AMinimum);
end;

procedure TAdvChartMouseEventsOracleTest.TestMouseEventsAsUpstream;
begin
  Run('', 150);
end;

{ A TYPE THE CHART DOES NOT EMIT IS REFUSED, not stored to wait for ever; and
  off takes a registration away. }
procedure TAdvChartMouseEventsOracleTest.TestAnUnknownTypeIsRefusedAndOffRemoves;
var
  lg: TMeLogger;
  id: Integer;
begin
  lg := TMeLogger.Create;
  FLoggers.Add(lg);
  lg.Id := 'x';
  lg.Log := FLog;
  { [Batch 88: this asked about selectchanged, which the chart emits since
    the selection batch -- upstream publishes it from the select actions. A
    type it never emits is the question: brushselected, the brush's.] }
  AssertEquals('brushselected is not emitted', -1,
    FChart.ChartOn('brushselected', @lg.Handle));
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[10]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  id := FChart.ChartOn('globalout', @lg.Handle);
  AssertTrue('registered', id > 0);
  FChart.Leave(10, 10);
  AssertEquals('globalout fired', 1, FLog.Count);
  FChart.ChartOff(id);
  FLog.Clear;
  FChart.Leave(10, 10);
  AssertEquals('and after off, not', 0, FLog.Count);
end;

initialization
  RegisterTest(TAdvChartMouseEventsOracleTest);
end.
