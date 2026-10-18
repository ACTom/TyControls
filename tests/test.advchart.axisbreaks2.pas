unit test.advchart.axisbreaks2;
{$mode objfpc}{$H+}
{ Axis breaks the first batch left out -- fix phase F4a -- held to upstream.

  tools/advchart-oracle/axis-breaks2.js runs the real ECharts 6.1 build and
  records, as axis-breaks.js does: breaks on a LOG axis (LogScale's two stubs:
  the gaps and the stepping in log space, the break ends brought back through
  the scale's lookup, a second break's start overwriting the first one's end
  there), breaks on a SINGLE axis (the zigzag across its rect, the click
  expanding by singleAxisIndex), a break's two labels TURNED (moved apart by
  the oriented boxes' MTV), the `break` a function formatter is handed and an
  axis label's click event carries, and the break areas in their axis'
  groupTransition (a dataZoom: frames of the three leaves by anid).

  THE REPLAY is test.advchart.axisbreaks': a fresh chart per case (the random
  numbers reseeded), the option as written, clicks through the pointer,
  actions through DispatchAction, text measured with zrender's width table,
  every number to the bit. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord, tyControls.AdvChart.Time,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Layout, tyControls.AdvChart.Single,
     tyControls.AdvChart.Render, tyControls.AdvChart.AxisBreak, tyControls.AdvChart.Anim,
     tyControls.AdvChart.Jitter, tyControls.AdvChart.Events, tyControls.AdvChart.Color,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.AnimAxis, tyControls.AdvChart.AnimView,
     tyControls.AdvanceChart, test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TBreak2Probe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure ClickAt(AX, AY: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartAxisBreaks2OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBreak2Probe;
    FRoot, FTable: TJSONData;
    FBad, FCompared, FLabels, FAreas, FPoints, FEvents, FTicks, FItems, FCalls,
      FClicks, FFrames: Integer;
    FReport, FName: string;
    FEventLog, FClickLog, FCallLog: TStringList;
    FLastState: LongWord;
    FSavedSource: TTyDateTimeNameSource;
    procedure OnBreakEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure OnClick(Sender: TObject; const AEvent: TTyChartEvent);
    function BrkFormatter(const AParams: TTyChartParams): string;
    procedure NewChart;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameInt(const AWhat: string; AGot, AWant: Int64);
    procedure SameStr(const AWhat, AGot, AWant: string);
    function AxisOf(const ADim: string; AIndex: Integer): TTyAxis;
    function SpecOf(AAxis: TTyAxis): PTyAxisLayoutSpec;
    procedure RenderAt(AW, AH: Integer);
    function DrawsSince: Integer;
    procedure ReplayGroup(const AGroup: string);
    procedure CheckRender(ACase, ARender: TJSONObject; AStep: Integer);
    procedure CheckAxis(ACase, AAxis: TJSONObject; const ATag: string);
    procedure CheckSeries(ASeries: TJSONObject; const ATag: string);
    procedure CheckEvents(ARender: TJSONObject; const ATag: string);
    procedure CheckClicks(ARender: TJSONObject; const ATag: string);
    procedure CheckCalls(ARender: TJSONObject; const ATag: string);
    procedure Report;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLogAxisBreaksAsUpstream;
    procedure TestSingleAxisBreaksAsUpstream;
    procedure TestTurnedBreakLabelsAsUpstream;
    procedure TestTheBreakInParamsAsUpstream;
    procedure TestBreakAreasInTheTransition;
    procedure TestALogAxisBreakAreaIsDrawn;
  end;

implementation

const
  T0 = 1700000000000.0;

procedure TBreak2Probe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBreak2Probe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TBreak2Probe.ClickAt(AX, AY: Integer);
begin
  EventMove(AX, AY);
  EventDown(mbLeft, AX, AY);
  EventUp(mbLeft, AX, AY);
end;

function TBreak2Probe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-axis-breaks2.json';
end;

function NumOf(AData: TJSONData): Double;
var
  q: QWord;
  s: string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  s := AData.AsString;
  Result := 0;
  q := StrToQWord('$' + s);
  Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function NulText(const AText: string): string;
begin
  Result := StringReplace(AText, #0, '<NUL>', [rfReplaceAll]);
end;

function Canon(const AJson: string): string;
var d: TJSONData;
begin
  try
    d := GetJSON(AJson);
  except
    Exit('<bad JSON> ' + AJson);
  end;
  try
    Result := d.AsJSON;
  finally
    d.Free;
  end;
end;

{ a number as the recorder's JSON holds it: as written }
function JsNum(A: Double): string;
begin
  Result := TyJsNumberToString(A);
end;

procedure TAdvChartAxisBreaks2OracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FEventLog := TStringList.Create;
  FClickLog := TStringList.Create;
  FCallLog := TStringList.Create;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-grid-bounds.json');
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  TyChartRegisterFormatter('brk', @BrkFormatter);
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartAxisBreaks2OracleTest.TearDown;
begin
  TyChartUnregisterFormatter('brk');
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FRoot);
  FreeAndNil(FTable);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FEventLog);
  FreeAndNil(FClickLog);
  FreeAndNil(FCallLog);
  TyDateTimeNameSource := FSavedSource;
  inherited TearDown;
end;

{ RENDER.brk's mirror: String(value), and the break of a break end }
function TAdvChartAxisBreaks2OracleTest.BrkFormatter(const AParams: TTyChartParams): string;
var
  p: TTyChartCallbackParams;
  v: Double;
  rec: string;
begin
  Result := '';
  if Length(AParams) = 0 then Exit;
  p := AParams[0];
  if Length(p.Values) > 0 then v := p.Values[0] else v := NaN;
  Result := JsNum(v);
  rec := JsNum(v) + '|' + IntToStr(p.DataIndex);
  if p.BreakType <> '' then
  begin
    Result := Result + ' [' + p.BreakType + ' ' + JsNum(p.BreakStart) + '~'
      + JsNum(p.BreakEnd) + ']';
    rec := rec + '|' + p.BreakType + '|' + JsNum(p.BreakStart) + '|' + JsNum(p.BreakEnd);
  end;
  if FCallLog.IndexOf(rec) < 0 then FCallLog.Add(rec);
end;

procedure TAdvChartAxisBreaks2OracleTest.NewChart;
begin
  if FChart <> nil then
  begin
    FChart.Measurer := nil;
    FreeAndNil(FChart);
  end;
  FChart := TBreak2Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FChart.ChartOn('axisbreakchanged', @OnBreakEvent);
  FChart.ChartOn('click', @OnClick);
  FLastState := TyJitterSeed;
  FEventLog.Clear;
  FClickLog.Clear;
  FCallLog.Clear;
end;

procedure TAdvChartAxisBreaks2OracleTest.OnBreakEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  FEventLog.Add(AEvent.Payload);
end;

{ an axis label's click: componentType, targetType, value, tickIndex and
  the break as JSON }
procedure TAdvChartAxisBreaks2OracleTest.OnClick(Sender: TObject;
  const AEvent: TTyChartEvent);
var s: string;
begin
  if not AEvent.HasParams then Exit;
  s := AEvent.Params.ComponentType + '|' + AEvent.Params.TargetType + '|'
    + AEvent.Params.ValueText + '|' + IntToStr(AEvent.Params.TickIndex) + '|';
  if AEvent.Params.BreakType <> '' then
    s := s + '{"start":' + JsNum(AEvent.Params.BreakStart) + ',"end":'
      + JsNum(AEvent.Params.BreakEnd) + '}'
  else
    s := s + 'null';
  FClickLog.Add(s);
end;

procedure TAdvChartAxisBreaks2OracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 300 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartAxisBreaks2OracleTest.Same(const AWhat: string;
  AGot: Double; AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := NumOf(AWant);
  if IsNan(want) or IsNan(AGot) then
  begin
    if not (IsNan(want) and IsNan(AGot)) then
      Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
  end
  else if AGot <> want then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartAxisBreaks2OracleTest.SameInt(const AWhat: string;
  AGot, AWant: Int64);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %d upstream, %d here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartAxisBreaks2OracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

function TAdvChartAxisBreaks2OracleTest.AxisOf(const ADim: string;
  AIndex: Integer): TTyAxis;
var
  g: TTyGridBuild;
  i: Integer;
begin
  Result := nil;
  if ADim = 'single' then
  begin
    if (AIndex < FChart.SingleCount) and (FChart.SingleLayout(AIndex) <> nil) then
      Result := FChart.SingleLayout(AIndex).Axis;
    Exit;
  end;
  if (FChart.Build = nil) or (FChart.Build.GridCount = 0) then Exit;
  g := FChart.Build.Grid(0);
  if ADim = 'x' then
  begin
    for i := 0 to g.XAxisCount - 1 do
      if g.XAxis(i).ComponentIndex = AIndex then Exit(g.XAxis(i));
  end
  else
    for i := 0 to g.YAxisCount - 1 do
      if g.YAxis(i).ComponentIndex = AIndex then Exit(g.YAxis(i));
end;

function TAdvChartAxisBreaks2OracleTest.SpecOf(AAxis: TTyAxis): PTyAxisLayoutSpec;
var i: Integer;
begin
  Result := nil;
  if AAxis = nil then Exit;
  if AAxis.MainType = 'singleAxis' then
  begin
    for i := 0 to FChart.SingleCount - 1 do
      if (FChart.SingleLayout(i) <> nil) and (FChart.SingleLayout(i).Axis = AAxis) then
        Exit(@FChart.SingleLayout(i).View.Spec);
    Exit;
  end;
  Result := FChart.Build.Grid(0).SpecFor(AAxis);
end;

procedure TAdvChartAxisBreaks2OracleTest.RenderAt(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  FChart.SetBounds(0, 0, AW, AH);
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartAxisBreaks2OracleTest.DrawsSince: Integer;
var s, now_: LongWord;
begin
  now_ := FChart.AxisMemory.RandomState^;
  s := FLastState;
  Result := 0;
  while (s <> now_) and (Result < 1000000) do
  begin
    TyJitterRandom(s);
    Inc(Result);
  end;
  FLastState := now_;
end;

procedure TAdvChartAxisBreaks2OracleTest.CheckEvents(ARender: TJSONObject;
  const ATag: string);
var
  evs: TJSONArray;
  ev: TJSONObject;
  got: TJSONData;
  i: Integer;
begin
  evs := ARender.Arrays['events'];
  SameInt(ATag + ' events', FEventLog.Count, evs.Count);
  for i := 0 to Min(evs.Count, FEventLog.Count) - 1 do
  begin
    Inc(FEvents);
    ev := evs.Objects[i];
    try
      got := GetJSON(FEventLog[i]);
    except
      Miss(ATag + ' event ' + IntToStr(i) + ' is no JSON');
      Continue;
    end;
    try
      SameStr(ATag + ' event type', TJSONObject(got).Get('type', ''), ev.Strings['type']);
      SameStr(ATag + ' event fromAction', TJSONObject(got).Get('fromAction', ''),
        ev.Strings['fromAction']);
      SameStr(ATag + ' event breaks', Canon(NulText(TJSONObject(got).Arrays['breaks'].AsJSON)),
        Canon(ev.Arrays['breaks'].AsJSON));
      SameStr(ATag + ' event payload', Canon(NulText(TJSONObject(got).Objects['fromActionPayload'].AsJSON)),
        Canon(ev.Objects['payload'].AsJSON));
    finally
      got.Free;
    end;
  end;
end;

procedure TAdvChartAxisBreaks2OracleTest.CheckClicks(ARender: TJSONObject;
  const ATag: string);
var
  arr: TJSONArray;
  o: TJSONObject;
  i: Integer;
  want: string;
begin
  arr := ARender.Arrays['clicks'];
  SameInt(ATag + ' clicks', FClickLog.Count, arr.Count);
  for i := 0 to Min(arr.Count, FClickLog.Count) - 1 do
  begin
    Inc(FClicks);
    o := arr.Objects[i];
    want := o.Strings['componentType'] + '|';
    if o.Find('targetType').JSONType <> jtNull then want := want + o.Strings['targetType'];
    want := want + '|';
    if o.Find('value').JSONType = jtString then want := want + o.Strings['value']
    else if o.Find('value').JSONType = jtNumber then want := want + JsNum(o.Floats['value']);
    want := want + '|';
    if o.Find('tickIndex').JSONType <> jtNull then want := want + IntToStr(o.Integers['tickIndex'])
    else want := want + '-1';
    want := want + '|';
    if o.Find('break').JSONType = jtNull then want := want + 'null'
    else want := want + '{"start":' + JsNum(o.Objects['break'].Floats['start'])
      + ',"end":' + JsNum(o.Objects['break'].Floats['end']) + '}';
    SameStr(Format('%s click %d', [ATag, i]), FClickLog[i], want);
  end;
end;

{ every distinct call the formatter had upstream, here too, and no other }
procedure TAdvChartAxisBreaks2OracleTest.CheckCalls(ARender: TJSONObject;
  const ATag: string);
var
  arr: TJSONArray;
  o, b: TJSONObject;
  i: Integer;
  want: TStringList;
  s: string;
begin
  arr := ARender.Arrays['calls'];
  if arr.Count = 0 then Exit;
  want := TStringList.Create;
  try
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      s := JsNum(NumOf(o.Find('value'))) + '|' + IntToStr(o.Integers['index']);
      if (o.Find('extra') is TJSONObject) and (o.Objects['extra'].Find('break') is TJSONObject) then
      begin
        b := o.Objects['extra'].Objects['break'];
        s := s + '|' + b.Strings['type'] + '|' + JsNum(b.Floats['start']) + '|'
          + JsNum(b.Floats['end']);
      end;
      if want.IndexOf(s) < 0 then want.Add(s);
    end;
    want.Sort;
    FCallLog.Sort;
    Inc(FCalls, want.Count);
    SameStr(ATag + ' formatter calls', StringReplace(Trim(FCallLog.Text), LineEnding, ' ', [rfReplaceAll]),
      StringReplace(Trim(want.Text), LineEnding, ' ', [rfReplaceAll]));
  finally
    want.Free;
  end;
end;

procedure TAdvChartAxisBreaks2OracleTest.CheckAxis(ACase, AAxis: TJSONObject;
  const ATag: string);
var
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  arr, sub: TJSONArray;
  o: TJSONObject;
  e: TTyRange;
  brks: TTyAxisBreakArray;
  ticks: TTyScaleTickArray;
  vals: TTyDoubleArray;
  i, k, n: Integer;
  want, got: string;
  geom: TTyBreakAreaGeom;
  isSingle: Boolean;
  sv: TTySingleAxisView;
  order: TTyIntegerArray;
  dim: string;
  furn: TTyAxisFurniture;

  function TickKind(AK: TTyBreakTickKind): string;
  begin
    case AK of
      btkVMin: Result := 'vmin';
      btkVMax: Result := 'vmax';
    else
      Result := '';
    end;
  end;

  function Majors(const ATicks: TTyScaleTickArray): TTyScaleTickArray;
  var q, m: Integer;
  begin
    Result := nil;
    SetLength(Result, Length(ATicks));
    m := 0;
    for q := 0 to High(ATicks) do
      if ATicks[q].Level = 0 then
      begin
        Result[m] := ATicks[q];
        Inc(m);
      end;
    SetLength(Result, m);
  end;

  procedure SameValues(const AWhat: string; const ATicks: TTyScaleTickArray;
    AWant: TJSONArray);
  var q: Integer;
  begin
    SameInt(AWhat + ' count', Length(ATicks), AWant.Count);
    if Length(ATicks) <> AWant.Count then Exit;
    for q := 0 to High(ATicks) do
      Same(Format('%s %d', [AWhat, q]), ATicks[q].Value, AWant.Items[q]);
  end;

  procedure SamePoints(const AWhat: string; const AGot: TTyBreakPointArray;
    AWant: TJSONArray);
  var q: Integer;
  begin
    SameInt(AWhat + ' points', Length(AGot), AWant.Count);
    if Length(AGot) <> AWant.Count then Exit;
    for q := 0 to High(AGot) do
    begin
      Inc(FPoints);
      Same(Format('%s %d x', [AWhat, q]), AGot[q].X, TJSONArray(AWant.Items[q]).Items[0]);
      Same(Format('%s %d y', [AWhat, q]), AGot[q].Y, TJSONArray(AWant.Items[q]).Items[1]);
    end;
  end;

begin
  dim := AAxis.Strings['dim'];
  ax := AxisOf(dim, AAxis.Integers['index']);
  if ax = nil then
  begin
    Miss(ATag + ': no such axis here');
    Exit;
  end;
  isSingle := dim = 'single';
  spec := SpecOf(ax);
  if isSingle then sv := FChart.SingleLayout(AAxis.Integers['index']).View
  else furn := FChart.Build.Grid(0).FurnitureFor(ax);

  { THE SCALE }
  e := ax.Scale.GetExtent;
  Same(ATag + ' extent 0', e.Start, AAxis.Arrays['extent'].Items[0]);
  Same(ATag + ' extent 1', e.Stop, AAxis.Arrays['extent'].Items[1]);
  if ax.Scale is TTyTimeScale then
    Same(ATag + ' approx interval', TTyTimeScale(ax.Scale).ApproxInterval, AAxis.Find('interval'))
  else if ax.Scale is TTyIntervalScale then
  begin
    Same(ATag + ' interval', TTyIntervalScale(ax.Scale).Interval, AAxis.Find('interval'));
    if AAxis.Find('niceExtent') is TJSONArray then
    begin
      Same(ATag + ' nice 0', TTyIntervalScale(ax.Scale).NiceStart, AAxis.Arrays['niceExtent'].Items[0]);
      Same(ATag + ' nice 1', TTyIntervalScale(ax.Scale).NiceStop, AAxis.Arrays['niceExtent'].Items[1]);
    end;
  end;
  arr := AAxis.Arrays['breaks'];
  if ax.Scale.BreakMapper <> nil then brks := ax.Scale.BreakMapper.BreakList
  else brks := nil;
  SameInt(ATag + ' breaks', Length(brks), arr.Count);
  if Length(brks) = arr.Count then
    for i := 0 to High(brks) do
    begin
      o := arr.Objects[i];
      Same(Format('%s break %d vmin', [ATag, i]), brks[i].VMin, o.Find('vmin'));
      Same(Format('%s break %d vmax', [ATag, i]), brks[i].VMax, o.Find('vmax'));
      if brks[i].GapKind = bgkPrct then got := 'tpPrct' else got := 'tpAbs';
      SameStr(Format('%s break %d gap type', [ATag, i]), got, o.Strings['type']);
      Same(Format('%s break %d gap', [ATag, i]), brks[i].GapVal, o.Find('val'));
      Same(Format('%s break %d gapReal', [ATag, i]), brks[i].GapReal, o.Find('gapReal'));
    end;
  { A LOG AXIS: intervalStub's breaks and extent }
  if AAxis.Find('lbreaks') is TJSONArray then
  begin
    arr := AAxis.Arrays['lbreaks'];
    if Supports(ax.Scale.Mapper, ITyLogBreakScaleMapper) then
      brks := (ax.Scale.Mapper as ITyLogBreakScaleMapper).StubBreaks
    else brks := nil;
    SameInt(ATag + ' log breaks', Length(brks), arr.Count);
    if Length(brks) = arr.Count then
      for i := 0 to High(brks) do
      begin
        o := arr.Objects[i];
        Same(Format('%s log break %d vmin', [ATag, i]), brks[i].VMin, o.Find('vmin'));
        Same(Format('%s log break %d vmax', [ATag, i]), brks[i].VMax, o.Find('vmax'));
        Same(Format('%s log break %d gap', [ATag, i]), brks[i].GapVal, o.Find('val'));
      end;
    if ax.Scale is TTyIntervalScale then
    begin
      Same(ATag + ' log extent 0', TTyIntervalScale(ax.Scale).StepExtent.Start,
        AAxis.Arrays['lextent'].Items[0]);
      Same(ATag + ' log extent 1', TTyIntervalScale(ax.Scale).StepExtent.Stop,
        AAxis.Arrays['lextent'].Items[1]);
    end;
  end;

  { THE TICKS }
  if ax.AxisType <> atCategory then
  begin
    ticks := Majors(ax.Scale.GetTicks);
    arr := AAxis.Arrays['ticks'];
    SameInt(ATag + ' ticks', Length(ticks), arr.Count);
    if Length(ticks) = arr.Count then
      for i := 0 to High(ticks) do
      begin
        Inc(FTicks);
        o := arr.Objects[i];
        Same(Format('%s tick %d', [ATag, i]), ticks[i].Value, o.Find('v'));
        if o.Find('b').JSONType = jtNull then want := '' else want := o.Strings['b'];
        SameStr(Format('%s tick %d break', [ATag, i]), TickKind(ticks[i].BreakKind), want);
      end;
    SameValues(ATag + ' raw ticks', Majors(ax.Scale.GetTicksOpt(TyTicksOpt(tbmNone, tpmNo))),
      AAxis.Arrays['rawTicks']);
    SameValues(ATag + ' line ticks', Majors(ax.Scale.GetTicksOpt(TyTicksOpt(tbmNone,
      tpmPreserveExtentBound))), AAxis.Arrays['lineTicks']);
    if AAxis.Find('minor') is TJSONArray then
    begin
      vals := nil;
      ticks := ax.Scale.GetTicks;
      for i := 0 to High(ticks) do
        if ticks[i].Level = 1 then
        begin
          SetLength(vals, Length(vals) + 1);
          vals[High(vals)] := ticks[i].Value;
        end;
      arr := AAxis.Arrays['minor'];
      n := 0;
      for i := 0 to arr.Count - 1 do
      begin
        sub := TJSONArray(arr.Items[i]);
        for k := 0 to sub.Count - 1 do
        begin
          if n <= High(vals) then Same(Format('%s minor %d', [ATag, n]), vals[n], sub.Items[k]);
          Inc(n);
        end;
      end;
      SameInt(ATag + ' minor ticks', Length(vals), n);
    end;
  end;

  if spec = nil then
  begin
    Miss(ATag + ': no layout spec');
    Exit;
  end;

  { THE LABELS }
  arr := AAxis.Arrays['labels'];
  SameInt(ATag + ' labels', Length(spec^.Placements), arr.Count);
  if Length(spec^.Placements) = arr.Count then
    for i := 0 to arr.Count - 1 do
    begin
      Inc(FLabels);
      o := arr.Objects[i];
      SameStr(Format('%s label %d text', [ATag, i]), spec^.Placements[i].Text, o.Strings['text']);
      Same(Format('%s label %d x', [ATag, i]), spec^.Placements[i].X, o.Find('x'));
      Same(Format('%s label %d y', [ATag, i]), spec^.Placements[i].Y, o.Find('y'));
      Inc(FCompared);
      if spec^.Placements[i].Shown <> o.Booleans['shown'] then
        Miss(Format('%s label %d (%s) shown %s upstream', [ATag, i, o.Strings['text'],
          BoolToStr(o.Booleans['shown'], True)]));
      if o.Find('b').JSONType = jtNull then want := '0'
      else if o.Strings['b'] = 'vmin' then want := '1' else want := '2';
      if Length(spec^.LabelBreakKind) > i then got := IntToStr(spec^.LabelBreakKind[i])
      else got := '0';
      SameStr(Format('%s label %d break', [ATag, i]), got, want);
    end;

  { THE SPLIT LINES AND AXIS TICKS, by value }
  arr := AAxis.Arrays['splitLines'];
  if (not isSingle) or (arr.Count > 0) then
  begin
    want := '';
    for i := 0 to arr.Count - 1 do want := want + arr.Objects[i].Strings['v'] + ' ';
    got := '';
    if isSingle then
    begin
      for i := 0 to High(sv.SplitLines) do got := got + JsNum(sv.SplitLines[i].Value) + ' ';
    end
    else if furn.ShowSplitLine then
      for i := 0 to High(spec^.SplitLineMarks) do
        if spec^.SplitLineMarks[i].Drawn then
          got := got + JsNum(spec^.SplitLineMarks[i].Value) + ' ';
    SameStr(ATag + ' split lines', got, want);
  end;
  { A SINGLE AXIS' SPLIT LINES: upstream merges them into one path per
    colour (no anid); the lines it merged, in that order, against the
    view's, colour by colour }
  if isSingle then
  begin
    sub := AAxis.Find('singleSplit') as TJSONArray;
    if sub = nil then Miss(ATag + ': no singleSplit in the fixture')
    else
    begin
      n := 0;
      for k := 0 to High(sv.SplitLines) do
        if sv.SplitLines[k].ColourIndex > n then n := sv.SplitLines[k].ColourIndex;
      order := nil;
      for i := 0 to n do
        for k := 0 to High(sv.SplitLines) do
          if sv.SplitLines[k].ColourIndex = i then
          begin
            SetLength(order, Length(order) + 1);
            order[High(order)] := k;
          end;
      SameInt(ATag + ' single split line count', Length(order), sub.Count);
      if Length(order) = sub.Count then
        for i := 0 to High(order) do
        begin
          k := order[i];
          Same(Format('%s single split %d x1', [ATag, i]), sv.SplitLines[k].X1, TJSONArray(sub.Items[i]).Items[0]);
          Same(Format('%s single split %d y1', [ATag, i]), sv.SplitLines[k].Y1, TJSONArray(sub.Items[i]).Items[1]);
          Same(Format('%s single split %d x2', [ATag, i]), sv.SplitLines[k].X2, TJSONArray(sub.Items[i]).Items[2]);
          Same(Format('%s single split %d y2', [ATag, i]), sv.SplitLines[k].Y2, TJSONArray(sub.Items[i]).Items[3]);
        end;
    end;
  end;
  arr := AAxis.Arrays['axisTicks'];
  want := '';
  for i := 0 to arr.Count - 1 do
  begin
    want := want + arr.Objects[i].Strings['v'];
    if not arr.Objects[i].Booleans['shown'] then want := want + '(hidden)';
    want := want + ' ';
  end;
  got := '';
  if isSingle then
  begin
    for i := 0 to High(sv.Ticks) do
    begin
      got := got + JsNum(sv.Ticks[i].Value);
      if not sv.Ticks[i].Drawn then got := got + '(hidden)';
      got := got + ' ';
    end;
  end
  else if furn.ShowTicks then
    for i := 0 to High(spec^.TickMarks) do
    begin
      got := got + JsNum(spec^.TickMarks[i].Value);
      if not spec^.TickMarks[i].Drawn then got := got + '(hidden)';
      got := got + ' ';
    end;
  SameStr(ATag + ' axis ticks', got, want);

  { THE AXIS LINE, cut or whole }
  arr := AAxis.Arrays['axisLine'];
  if arr.Count > 0 then
  begin
    if arr.Objects[0].Strings['anid'] = 'line' then
    begin
      Inc(FCompared);
      if spec^.HasBreakLine then Miss(ATag + ': a cut line here, a whole one upstream');
    end
    else
    begin
      SameInt(ATag + ' line segments', Length(spec^.BreakLineSegs), arr.Count);
      if Length(spec^.BreakLineSegs) = arr.Count then
        for i := 0 to arr.Count - 1 do
        begin
          o := arr.Objects[i];
          SameStr(Format('%s segment %d anid', [ATag, i]), NulText(spec^.BreakLineSegs[i].Anid),
            o.Strings['anid']);
          Same(Format('%s segment %d x1', [ATag, i]), spec^.BreakLineSegs[i].X1, o.Find('x1'));
          Same(Format('%s segment %d y1', [ATag, i]), spec^.BreakLineSegs[i].Y1, o.Find('y1'));
          Same(Format('%s segment %d x2', [ATag, i]), spec^.BreakLineSegs[i].X2, o.Find('x2'));
          Same(Format('%s segment %d y2', [ATag, i]), spec^.BreakLineSegs[i].Y2, o.Find('y2'));
        end;
    end;
  end;

  { THE BREAK AREAS }
  arr := AAxis.Arrays['breakAreas'];
  SameInt(ATag + ' break areas', Length(spec^.BreakAreas), arr.Count);
  if Length(spec^.BreakAreas) = arr.Count then
    for i := 0 to arr.Count - 1 do
    begin
      Inc(FAreas);
      o := arr.Objects[i];
      geom := spec^.BreakAreas[i];
      SameStr(Format('%s area %d id', [ATag, i]), NulText(geom.Id), o.Strings['id']);
      SamePoints(Format('%s area %d A', [ATag, i]), geom.A, o.Arrays['a']);
      Inc(FCompared);
      if geom.HasB <> (o.Find('b').JSONType <> jtNull) then
        Miss(Format('%s area %d: polyline B here %s', [ATag, i, BoolToStr(geom.HasB, True)]))
      else if geom.HasB then
        SamePoints(Format('%s area %d B', [ATag, i]), geom.B, o.Arrays['b']);
    end;
end;

procedure TAdvChartAxisBreaks2OracleTest.CheckSeries(ASeries: TJSONObject;
  const ATag: string);
var
  si, k, i, n: Integer;
  typ: string;
  items: TJSONArray;
  lst: TTyPaintList;
  e: TTyChartElement;
  pts: TTyPointFArray;
  b: TTyRectF;
  x, y, w, h, cl, cr, ct, cb: Double;
  g: TTyXYWH;
  found: Boolean;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  items := ASeries.Arrays['items'];
  lst := FChart.List;
  if lst = nil then
  begin
    Miss(ATag + ': no paint list');
    Exit;
  end;
  if typ = 'bar' then
  begin
    g := FChart.Build.Grid(0).PlotXYWH;
    for k := 0 to items.Count - 1 do
    begin
      if items.Items[k].JSONType = jtNull then Continue;
      x := NumOf(TJSONArray(items.Items[k]).Items[0]);
      y := NumOf(TJSONArray(items.Items[k]).Items[1]);
      w := NumOf(TJSONArray(items.Items[k]).Items[2]);
      h := NumOf(TJSONArray(items.Items[k]).Items[3]);
      { the layout as the grid clips it }
      cl := Max(Min(x, x + w), g.X);
      cr := Min(Max(x, x + w), g.X + g.W);
      ct := Max(Min(y, y + h), g.Y);
      cb := Min(Max(y, y + h), g.Y + g.H);
      if (cr <= cl) or (cb <= ct) then Continue;
      found := False;
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
          or (e.Datum.RawDataIndex <> k) or (e.Caption.FontSizeLogical > 0) then Continue;
        found := True;
        Inc(FItems);
        b := TyShapeBounds(e.Shape);
        Inc(FCompared);
        if (b.Left <> cl) or (b.Right <> cr) or (b.Top <> ct) or (b.Bottom <> cb) then
          Miss(Format('%s s%d[%d] bar %s,%s %sx%s upstream, %s,%s..%s,%s here',
            [ATag, si, k, Fmt(x), Fmt(y), Fmt(w), Fmt(h), Fmt(b.Left), Fmt(b.Top),
             Fmt(b.Right), Fmt(b.Bottom)]));
        Break;
      end;
      if not found then Miss(Format('%s s%d[%d]: no bar here', [ATag, si, k]));
    end;
    Exit;
  end;
  if typ = 'scatter' then
  begin
    n := 0;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex < 0)
        or (e.Caption.FontSizeLogical > 0) or (e.Shape.Kind <> cskCircle) then Continue;
      k := e.Datum.RawDataIndex;
      if k >= items.Count then Continue;
      Inc(FItems);
      Same(Format('%s s%d[%d] x', [ATag, si, k]), e.Shape.CX, TJSONArray(items.Items[k]).Items[0]);
      Same(Format('%s s%d[%d] y', [ATag, si, k]), e.Shape.CY, TJSONArray(items.Items[k]).Items[1]);
      Inc(n);
    end;
    SameInt(ATag + ' scatter points', n, items.Count);
    Exit;
  end;
  { a line: its polyline, vertex by vertex, as singles }
  pts := nil;
  for i := 0 to lst.Count - 1 do
  begin
    e := lst.Element(i);
    if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex <> -1)
      or e.Silent or (e.Shape.Kind <> cskPolyline) then Continue;
    n := Length(pts);
    SetLength(pts, n + Length(e.Shape.Points));
    for k := 0 to High(e.Shape.Points) do pts[n + k] := e.Shape.Points[k];
  end;
  SameInt(ATag + ' line vertices', Length(pts), items.Count);
  if Length(pts) = items.Count then
    for k := 0 to items.Count - 1 do
    begin
      Inc(FItems);
      Inc(FCompared);
      if (pts[k].X <> Single(NumOf(TJSONArray(items.Items[k]).Items[0])))
        or (pts[k].Y <> Single(NumOf(TJSONArray(items.Items[k]).Items[1]))) then
        Miss(Format('%s s%d vertex %d is %s,%s here', [ATag, si, k, Fmt(pts[k].X), Fmt(pts[k].Y)]));
    end;
end;

procedure TAdvChartAxisBreaks2OracleTest.CheckRender(ACase, ARender: TJSONObject;
  AStep: Integer);
var
  r: TTyXYWH;
  arr: TJSONArray;
  i: Integer;
  tag: string;
  first: TJSONObject;
  ax: TTyAxis;
begin
  tag := Format('render %d', [AStep]);
  first := ARender.Arrays['axes'].Objects[0];
  if first.Strings['dim'] = 'single' then
  begin
    ax := AxisOf('single', first.Integers['index']);
    if ax <> nil then r := FChart.SingleLayout(first.Integers['index']).Rect
    else r := TyXYWH(NaN, NaN, NaN, NaN);
  end
  else
    r := FChart.Build.Grid(0).PlotXYWH;
  arr := ARender.Arrays['rect'];
  Same(tag + ' rect x', r.X, arr.Items[0]);
  Same(tag + ' rect y', r.Y, arr.Items[1]);
  Same(tag + ' rect w', r.W, arr.Items[2]);
  Same(tag + ' rect h', r.H, arr.Items[3]);
  SameInt(tag + ' random draws', DrawsSince, ARender.Integers['draws']);
  CheckEvents(ARender, tag);
  CheckClicks(ARender, tag);
  CheckCalls(ARender, tag);
  arr := ARender.Arrays['axes'];
  for i := 0 to arr.Count - 1 do
    CheckAxis(ACase, arr.Objects[i], Format('%s %s%d', [tag, arr.Objects[i].Strings['dim'],
      arr.Objects[i].Integers['index']]));
  arr := ARender.Arrays['series'];
  for i := 0 to arr.Count - 1 do
    CheckSeries(arr.Objects[i], tag);
end;

procedure TAdvChartAxisBreaks2OracleTest.ReplayGroup(const AGroup: string);
var
  cases, steps, renders: TJSONArray;
  cs, st, rd: TJSONObject;
  c, k: Integer;
  typ: string;
  ran: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  ran := 0;
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Strings['group'] <> AGroup then Continue;
    Inc(ran);
    FName := cs.Strings['id'];
    NewChart;
    FChart.SetOption(cs.Objects['option'].AsJSON, True);
    AssertEquals(FName + ' parses', '', FChart.OptionError);
    RenderAt(600, 400);
    renders := cs.Arrays['renders'];
    CheckRender(cs, renders.Objects[0], 0);
    steps := cs.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      rd := renders.Objects[k + 1];
      typ := st.Strings['type'];
      FEventLog.Clear;
      FClickLog.Clear;
      FCallLog.Clear;
      if typ = 'click' then
        FChart.ClickAt(rd.Arrays['point'].Integers[0], rd.Arrays['point'].Integers[1])
      else if typ = 'action' then
        AssertTrue(FName + ' takes the action', FChart.DispatchAction(st.Objects['payload'].AsJSON));
      RenderAt(600, 400);
      CheckRender(cs, rd, k + 1);
    end;
  end;
  AssertTrue('the group ' + AGroup + ' has cases', ran > 0);
end;

procedure TAdvChartAxisBreaks2OracleTest.Report;
begin
  if GetEnvironmentVariable('TY_AXISBREAKS_COUNTS') = '1' then
    WriteLn(Format('%s: %d comparisons, %d labels, %d areas, %d zigzag points, %d ticks, '
      + '%d items, %d events, %d calls, %d clicks, %d frames',
      [TestName, FCompared, FLabels, FAreas, FPoints, FTicks, FItems, FEvents, FCalls,
       FClicks, FFrames]));
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s',
      [FBad, FCompared, FReport]));
end;

procedure TAdvChartAxisBreaks2OracleTest.TestLogAxisBreaksAsUpstream;
begin
  FAreas := 0;
  FTicks := 0;
  ReplayGroup('log');
  Report;
  AssertTrue(Format('enough ticks (%d) and areas (%d)', [FTicks, FAreas]),
    (FTicks >= 30) and (FAreas >= 8));
end;

procedure TAdvChartAxisBreaks2OracleTest.TestSingleAxisBreaksAsUpstream;
begin
  FAreas := 0;
  FEvents := 0;
  ReplayGroup('single');
  Report;
  AssertTrue(Format('enough areas (%d) and events (%d)', [FAreas, FEvents]),
    (FAreas >= 6) and (FEvents >= 3));
end;

procedure TAdvChartAxisBreaks2OracleTest.TestTurnedBreakLabelsAsUpstream;
begin
  FLabels := 0;
  ReplayGroup('rotate');
  Report;
  AssertTrue(Format('enough labels (%d)', [FLabels]), FLabels >= 30);
end;

procedure TAdvChartAxisBreaks2OracleTest.TestTheBreakInParamsAsUpstream;
begin
  FCalls := 0;
  FClicks := 0;
  ReplayGroup('params');
  Report;
  AssertTrue(Format('enough calls (%d) and clicks (%d)', [FCalls, FClicks]),
    (FCalls >= 10) and (FClicks >= 2));
end;

{ THE TRANSITION: the settled first render, the action at T1, then each
  sample's frame -- the three leaves of every break by anid, from the axis
  proxies, against upstream's points }
procedure TAdvChartAxisBreaks2OracleTest.TestBreakAreasInTheTransition;
var
  anims, frames, leaves, pts: TJSONArray;
  an, fr, lf, act: TJSONObject;
  c, f, l, q, t: Integer;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  akey, anid: string;
  t1: Double;
  act2: TJSONObject;
begin
  FFrames := 0;
  anims := TJSONObject(FRoot).Arrays['anim'];
  for c := 0 to anims.Count - 1 do
  begin
    an := anims.Objects[c];
    FName := an.Strings['id'];
    NewChart;
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := T0;
    FChart.DataZoomNow := T0;
    FChart.SetBounds(0, 0, 600, 400);
    FChart.Option := TJSONObject(an.Objects['option']).AsJSON;
    AssertEquals(FName + ' parses', '', FChart.OptionError);
    RenderAt(600, 400);
    t := 16;
    while t <= 5000 do
    begin
      FChart.AnimNow := T0 + t;
      FChart.AnimTick(T0 + t);
      Inc(t, 250);
    end;
    RenderAt(600, 400);
    SameInt('first draws', DrawsSince, an.Objects['before'].Integers['draws']);
    t1 := T0 + 10000;
    FChart.AnimNow := t1;
    FChart.DataZoomNow := t1;
    act := an.Objects['action'];
    if act.Strings['type'] = 'dataZoom' then
      AssertTrue(FName + ' zooms', FChart.DispatchDataZoom(0, act.Floats['start'], act.Floats['end']))
    else
      AssertTrue(FName + ' acts', FChart.DispatchAction(act.AsJSON));
    act2 := an.Find('action2') as TJSONObject;
    akey := an.Strings['axis'];
    if akey[1] = 'y' then akey := 'yAxis' + Copy(akey, 2, MaxInt)
    else akey := 'xAxis' + Copy(akey, 2, MaxInt);
    frames := an.Arrays['frames'];
    for f := 0 to frames.Count - 1 do
    begin
      fr := frames.Objects[f];
      FChart.AnimNow := t1 + fr.Floats['t'];
      FChart.DataZoomNow := t1 + fr.Floats['t'];
      FChart.AnimTick(t1 + fr.Floats['t']);
      RenderAt(600, 400);
      Inc(FFrames);
      leaves := fr.Arrays['leaves'];
      for l := 0 to leaves.Count - 1 do
      begin
        lf := leaves.Objects[l];
        anid := StringReplace(lf.Strings['anid'], '<NUL>', #0, [rfReplaceAll]);
        pts := lf.Arrays['points'];
        p := FChart.AnimAxisProxy(akey, anid);
        Inc(FCompared);
        if p = nil then
        begin
          { no transition at all: the leaf is drawn where the layout put it,
            which the first-render cases compare; here only a proxy counts }
          if FChart.AnimAxisProxyCount > 0 then
            Miss(Format('t=%s %s: no proxy', [Fmt(fr.Floats['t']), lf.Strings['anid']]));
          Continue;
        end;
        v := p.GetAnimProp('shape.points');
        SameInt(Format('t=%s %s points', [Fmt(fr.Floats['t']), lf.Strings['anid']]),
          Length(v.Arr) div 2, pts.Count);
        if Length(v.Arr) div 2 <> pts.Count then Continue;
        for q := 0 to pts.Count - 1 do
        begin
          Same(Format('t=%s %s %d x', [Fmt(fr.Floats['t']), lf.Strings['anid'], q]),
            v.Arr[2 * q], TJSONArray(pts.Items[q]).Items[0]);
          Same(Format('t=%s %s %d y', [Fmt(fr.Floats['t']), lf.Strings['anid'], q]),
            v.Arr[2 * q + 1], TJSONArray(pts.Items[q]).Items[1]);
        end;
      end;
      { the second action right after the sample at at2: a transition that
        starts while the first one moves }
      if (act2 <> nil) and (fr.Floats['t'] = an.Floats['at2']) then
        AssertTrue(FName + ' zooms again', FChart.DispatchDataZoom(0, act2.Floats['start'],
          act2.Floats['end']));
    end;
  end;
  Report;
  AssertTrue(Format('enough frames (%d)', [FFrames]), FFrames >= 20);
end;

{ THE LOG AXIS' AREA REALLY DRAWS: its middle across the bars differs from
  the same chart without it }
procedure TAdvChartAxisBreaks2OracleTest.TestALogAxisBreakAreaIsDrawn;
const
  cOpt = '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"log","breaks":[{"start":50,"end":900,"gap":"10%%"}]%s},'
    + '"series":[{"type":"bar","data":[1,30,950,4000,10000]}]}';
var
  a, b: TBGRABitmap;
  spec: PTyAxisLayoutSpec;
  x, y, diff: Integer;
  p, q: TBGRAPixel;
begin
  NewChart;
  FChart.SetBounds(0, 0, 600, 400);
  a := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  b := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.SetOption(Format(cOpt, ['']), True);
    FChart.Render(a.Canvas, Rect(0, 0, 600, 400), 96);
    spec := SpecOf(AxisOf('y', 0));
    AssertTrue('a spec', spec <> nil);
    AssertEquals('one break area', 1, Length(spec^.BreakAreas));
    y := Round((spec^.BreakAreas[0].Lo + spec^.BreakAreas[0].Hi) / 2);
    FChart.SetOption(Format(cOpt, [',"breakArea":{"show":false}']), True);
    FChart.Render(b.Canvas, Rect(0, 0, 600, 400), 96);
    diff := 0;
    for x := 90 to 540 do
    begin
      p := a.GetPixel(x, y);
      q := b.GetPixel(x, y);
      if (p.red <> q.red) or (p.green <> q.green) or (p.blue <> q.blue) then Inc(diff);
    end;
    AssertTrue(Format('the area changed %d pixels along its middle', [diff]), diff > 100);
  finally
    a.Free;
    b.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartAxisBreaks2OracleTest);
end.
