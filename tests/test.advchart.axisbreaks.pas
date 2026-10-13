unit test.advchart.axisbreaks;
{$mode objfpc}{$H+}
{ Axis breaks -- roadmap D1, batch 132 -- held to upstream.

  tools/advchart-oracle/axis-breaks.js runs the real ECharts 6.1 build and
  records, render by render: the breaks as the scale holds them (their ends,
  their gap as written and the gap they take on this extent), the nice step
  on the span the breaks leave, the ticks (stepping over a break, pruned
  near one, a break's two ends added), the split lines' ticks, the minor
  ticks, every label (its text, where it stands after a break's two labels
  were moved apart, whether it is shown), the axis line cut at the breaks,
  each break's zigzag area (both polylines, point for point, from the random
  numbers the axis view keeps), the series mapped across the breaks, the
  random numbers each render drew, and the axisbreakchanged events of the
  clicks and actions -- across dataZoom windows, resizes, expands and
  collapses.

  THE REPLAY is the control's own: a fresh chart per case (the random
  numbers are seeded once per chart, as the oracle reseeds Math.random), the
  option as written, the actions through DispatchAction, a click as the
  pointer's move, press and release, a resize through the bounds, text
  measured with zrender's width table. Every number is compared to the bit.

  Hand-written beside it: the break area is on the screen over the bars; a
  render with nothing new draws no random number; a category axis ignores
  its breaks. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord, tyControls.AdvChart.Time,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Render, tyControls.AdvChart.AxisBreak,
     tyControls.AdvChart.Jitter, tyControls.AdvChart.Events, tyControls.AdvChart.Color,
     tyControls.AdvanceChart, test.advchart.gridbounds,
     test.advchart.categoryminmax;
type
  TBreakProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure ClickAt(AX, AY: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartAxisBreaksOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBreakProbe;
    FRoot, FTable: TJSONData;
    FBad, FCompared, FLabels, FAreas, FPoints, FEvents, FTicks, FItems: Integer;
    FReport, FName: string;
    FEventLog: TStringList;
    FLastState: LongWord;
    FSavedSource: TTyDateTimeNameSource;
    procedure OnBreakEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure NewChart;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameInt(const AWhat: string; AGot, AWant: Int64);
    procedure SameStr(const AWhat, AGot, AWant: string);
    function AxisOf(const ADim: string; AIndex: Integer): TTyAxis;
    procedure RenderAt(AW, AH: Integer);
    function DrawsSince: Integer;
    procedure ReplayGroup(const AGroup: string);
    procedure CheckRender(ACase, ARender: TJSONObject; AStep: Integer);
    procedure CheckAxis(ACase, AAxis: TJSONObject; const ATag: string);
    procedure CheckSeries(ASeries: TJSONObject; const ATag: string);
    procedure CheckEvents(ARender: TJSONObject; const ATag: string);
    procedure Report;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestValueAxisBreaksAsUpstream;
    procedure TestTimeAxisBreaksAsUpstream;
    procedure TestBreaksUnderDataZoom;
    procedure TestTheExpandCollapseActions;
    procedure TestTheZigzagCache;
    procedure TestTheBreakAreaIsOnTheScreen;
    procedure TestARenderWithNothingNewDrawsNothing;
    procedure TestACategoryAxisIgnoresItsBreaks;
  end;

implementation

procedure TBreakProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBreakProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TBreakProbe.ClickAt(AX, AY: Integer);
begin
  EventMove(AX, AY);
  EventDown(mbLeft, AX, AY);
  EventUp(mbLeft, AX, AY);
end;

function TBreakProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-axis-breaks.json';
end;

{ 16 hex digits }
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

function ColourOf(const AText: string): TTyChartColor;
begin
  Result := 0;
  if not TyTryParseChartColor(AText, Result) then Result := $DEADBEEF;
end;

{ the JSON text of a value, through fpjson both ways, so two texts compare
  by what they say }
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

procedure TAdvChartAxisBreaksOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  { upstream's English month names, not this machine's }
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FEventLog := TStringList.Create;
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
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartAxisBreaksOracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FRoot);
  FreeAndNil(FTable);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FEventLog);
  TyDateTimeNameSource := FSavedSource;
  inherited TearDown;
end;

{ A NEW CHART: its random numbers start from the seed again, as the oracle
  reseeds Math.random for every chart }
procedure TAdvChartAxisBreaksOracleTest.NewChart;
begin
  if FChart <> nil then
  begin
    FChart.Measurer := nil;
    FreeAndNil(FChart);
  end;
  FChart := TBreakProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FChart.ChartOn('axisbreakchanged', @OnBreakEvent);
  FLastState := TyJitterSeed;
  FEventLog.Clear;
end;

procedure TAdvChartAxisBreaksOracleTest.OnBreakEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  FEventLog.Add(AEvent.Payload);
end;

procedure TAdvChartAxisBreaksOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 300 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartAxisBreaksOracleTest.Same(const AWhat: string;
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

procedure TAdvChartAxisBreaksOracleTest.SameInt(const AWhat: string;
  AGot, AWant: Int64);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %d upstream, %d here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartAxisBreaksOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

function TAdvChartAxisBreaksOracleTest.AxisOf(const ADim: string;
  AIndex: Integer): TTyAxis;
var
  g: TTyGridBuild;
  i: Integer;
begin
  Result := nil;
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

procedure TAdvChartAxisBreaksOracleTest.RenderAt(AW, AH: Integer);
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

{ how many numbers the chart's generator gave since the last ask: the steps
  from the state then to the state now }
function TAdvChartAxisBreaksOracleTest.DrawsSince: Integer;
var
  s, now_: LongWord;
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

procedure TAdvChartAxisBreaksOracleTest.CheckEvents(ARender: TJSONObject;
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
      Miss(ATag + ' event ' + IntToStr(i) + ' is no JSON: ' + FEventLog[i]);
      Continue;
    end;
    try
      if not (got is TJSONObject) then
      begin
        Miss(ATag + ' event is no object');
        Continue;
      end;
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

procedure TAdvChartAxisBreaksOracleTest.CheckAxis(ACase, AAxis: TJSONObject;
  const ATag: string);
var
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  arr, sub, pts: TJSONArray;
  o: TJSONObject;
  e: TTyRange;
  brks: TTyAxisBreakArray;
  ticks: TTyScaleTickArray;
  vals: TTyDoubleArray;
  i, k, n: Integer;
  want, got: string;
  furn: TTyAxisFurniture;
  geom: TTyBreakAreaGeom;
  opt: TTyBreakAreaOpt;

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
  ax := AxisOf(AAxis.Strings['dim'], AAxis.Integers['index']);
  if ax = nil then
  begin
    Miss(ATag + ': no such axis here');
    Exit;
  end;
  spec := FChart.Build.Grid(0).SpecFor(ax);
  furn := FChart.Build.Grid(0).FurnitureFor(ax);

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
      SameStr(Format('%s break %d start', [ATag, i]), Canon(brks[i].StartJson),
        Canon(o.Find('start').AsJSON));
    end;

  { THE TICKS: the labels' (default), unpruned, the split lines' }
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
        if o.Find('lv') <> nil then
        begin
          SameInt(Format('%s tick %d level', [ATag, i]), ticks[i].TimeLevel, o.Integers['lv']);
          SameStr(Format('%s tick %d lower', [ATag, i]), TyTimeUnitName(ticks[i].TimeUnit), o.Strings['lo']);
          SameStr(Format('%s tick %d upper', [ATag, i]), TyTimeUnitName(ticks[i].TimeUpper), o.Strings['up']);
        end;
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

  { THE LABELS: text, place, shown }
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

  { THE SPLIT LINES DRAWN, by value }
  arr := AAxis.Arrays['splitLines'];
  want := '';
  for i := 0 to arr.Count - 1 do want := want + arr.Objects[i].Strings['v'] + ' ';
  got := '';
  if furn.ShowSplitLine then
    for i := 0 to High(spec^.SplitLineMarks) do
      if spec^.SplitLineMarks[i].Drawn then
        got := got + TyJsNumberToString(spec^.SplitLineMarks[i].Value) + ' ';
  SameStr(ATag + ' split lines', got, want);

  { THE AXIS TICKS, by value, and which are drawn (one whose label was
    hidden is ignored) }
  arr := AAxis.Arrays['axisTicks'];
  want := '';
  for i := 0 to arr.Count - 1 do
  begin
    want := want + arr.Objects[i].Strings['v'];
    if not arr.Objects[i].Booleans['shown'] then want := want + '(hidden)';
    want := want + ' ';
  end;
  got := '';
  if furn.ShowTicks then
    for i := 0 to High(spec^.TickMarks) do
    begin
      got := got + TyJsNumberToString(spec^.TickMarks[i].Value);
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
  opt := TyBreakAreaOptOf(TJSONObject(ACase.Objects['option']).Find(ax.MainType));
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
      Inc(FCompared);
      if geom.HasB <> o.Booleans['poly'] then
        Miss(Format('%s area %d: the polygon', [ATag, i]));
      { the style the option gives: z, the dash, the authored colours }
      Same(Format('%s area %d z', [ATag, i]), opt.Z, o.Find('z'));
      Inc(FCompared);
      if o.Booleans['silent'] <> (not opt.ExpandOnClick) then
        Miss(Format('%s area %d silent', [ATag, i]));
      want := '';
      if o.Find('lineDash') is TJSONArray then
        for k := 0 to o.Arrays['lineDash'].Count - 1 do
          want := want + TyJsNumberToString(o.Arrays['lineDash'].Floats[k]) + ' ';
      got := '';
      for k := 0 to High(opt.Dash) do got := got + TyJsNumberToString(opt.Dash[k]) + ' ';
      SameStr(Format('%s area %d dash', [ATag, i]), got, want);
      if opt.HasBorderColor then
      begin
        Inc(FCompared);
        if ColourOf(opt.BorderColor) <> ColourOf(o.Strings['stroke']) then
          Miss(Format('%s area %d stroke', [ATag, i]));
      end;
      if not IsNan(opt.BorderWidth) then
        Same(Format('%s area %d line width', [ATag, i]), opt.BorderWidth, o.Find('lineWidth'));
      if opt.HasColor and geom.HasB then
      begin
        Inc(FCompared);
        if ColourOf(opt.Color) <> ColourOf(o.Strings['fill']) then
          Miss(Format('%s area %d fill', [ATag, i]));
        if not IsNan(opt.Opacity) then
          Same(Format('%s area %d opacity', [ATag, i]), opt.Opacity, o.Find('opacity'));
      end;
    end;
end;

procedure TAdvChartAxisBreaksOracleTest.CheckSeries(ASeries: TJSONObject;
  const ATag: string);
var
  si, k, i, n: Integer;
  typ: string;
  items: TJSONArray;
  lst: TTyPaintList;
  e: TTyChartElement;
  b: TTyRectF;
  x, y, w, h, cl, cr, ct, cb: Double;
  g: TTyXYWH;
  pts: TTyPointFArray;
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
      { THE LAYOUT AS THE GRID CLIPS IT (the bar series' clip): a bar wholly
        outside is not drawn, or drawn with nothing in it }
      x := NumOf(TJSONArray(items.Items[k]).Items[0]);
      y := NumOf(TJSONArray(items.Items[k]).Items[1]);
      w := NumOf(TJSONArray(items.Items[k]).Items[2]);
      h := NumOf(TJSONArray(items.Items[k]).Items[3]);
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
        { the layout's rect with its sign, the element's bounds in order }
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

procedure TAdvChartAxisBreaksOracleTest.CheckRender(ACase, ARender: TJSONObject;
  AStep: Integer);
var
  r: TTyXYWH;
  arr: TJSONArray;
  i: Integer;
  tag: string;
begin
  tag := Format('render %d', [AStep]);
  r := FChart.Build.Grid(0).PlotXYWH;
  arr := ARender.Arrays['rect'];
  Same(tag + ' rect x', r.X, arr.Items[0]);
  Same(tag + ' rect y', r.Y, arr.Items[1]);
  Same(tag + ' rect w', r.W, arr.Items[2]);
  Same(tag + ' rect h', r.H, arr.Items[3]);
  SameInt(tag + ' random draws', DrawsSince, ARender.Integers['draws']);
  CheckEvents(ARender, tag);
  arr := ARender.Arrays['axes'];
  for i := 0 to arr.Count - 1 do
    CheckAxis(ACase, arr.Objects[i], Format('%s %s%d', [tag, arr.Objects[i].Strings['dim'],
      arr.Objects[i].Integers['index']]));
  arr := ARender.Arrays['series'];
  for i := 0 to arr.Count - 1 do
    CheckSeries(arr.Objects[i], tag);
end;

procedure TAdvChartAxisBreaksOracleTest.ReplayGroup(const AGroup: string);
var
  cases, steps, renders: TJSONArray;
  cs, st, rd: TJSONObject;
  c, k, w, h: Integer;
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
    w := 600;
    h := 400;
    FChart.SetOption(cs.Objects['option'].AsJSON, True);
    AssertEquals(FName + ' parses', '', FChart.OptionError);
    RenderAt(w, h);
    renders := cs.Arrays['renders'];
    CheckRender(cs, renders.Objects[0], 0);
    steps := cs.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      rd := renders.Objects[k + 1];
      typ := st.Strings['type'];
      FEventLog.Clear;
      if typ = 'click' then
        FChart.ClickAt(rd.Arrays['point'].Integers[0], rd.Arrays['point'].Integers[1])
      else if (typ = 'action') and (st.Objects['payload'].Strings['type'] = 'dataZoom') then
        AssertTrue(FName + ' takes the zoom', FChart.DispatchDataZoom(0,
          st.Objects['payload'].Floats['start'], st.Objects['payload'].Floats['end']))
      else if typ = 'action' then
        AssertTrue(FName + ' takes the action', FChart.DispatchAction(st.Objects['payload'].AsJSON))
      else if typ = 'resize' then
      begin
        w := st.Integers['W'];
        h := st.Integers['H'];
      end;
      RenderAt(w, h);
      CheckRender(cs, rd, k + 1);
    end;
  end;
  AssertTrue('the group ' + AGroup + ' has cases', ran > 0);
end;

procedure TAdvChartAxisBreaksOracleTest.Report;
begin
  if GetEnvironmentVariable('TY_AXISBREAKS_COUNTS') = '1' then
    WriteLn(Format('%s: %d comparisons, %d labels, %d areas, %d zigzag points, %d ticks, %d items, %d events',
      [TestName, FCompared, FLabels, FAreas, FPoints, FTicks, FItems, FEvents]));
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s',
      [FBad, FCompared, FReport]));
end;

procedure TAdvChartAxisBreaksOracleTest.TestValueAxisBreaksAsUpstream;
begin
  FLabels := 0;
  FAreas := 0;
  FPoints := 0;
  FItems := 0;
  ReplayGroup('value');
  Report;
  AssertTrue(Format('enough labels (%d), areas (%d), zigzag points (%d), items (%d)',
    [FLabels, FAreas, FPoints, FItems]),
    (FLabels >= 150) and (FAreas >= 25) and (FPoints >= 1500) and (FItems >= 100));
end;

procedure TAdvChartAxisBreaksOracleTest.TestTimeAxisBreaksAsUpstream;
begin
  FTicks := 0;
  FAreas := 0;
  ReplayGroup('time');
  Report;
  AssertTrue(Format('enough ticks (%d) and areas (%d)', [FTicks, FAreas]),
    (FTicks >= 30) and (FAreas >= 5));
end;

procedure TAdvChartAxisBreaksOracleTest.TestBreaksUnderDataZoom;
begin
  FLabels := 0;
  ReplayGroup('zoom');
  Report;
  AssertTrue(Format('enough labels (%d)', [FLabels]), FLabels >= 40);
end;

procedure TAdvChartAxisBreaksOracleTest.TestTheExpandCollapseActions;
begin
  FEvents := 0;
  ReplayGroup('action');
  Report;
  AssertTrue(Format('enough events (%d)', [FEvents]), FEvents >= 10);
end;

procedure TAdvChartAxisBreaksOracleTest.TestTheZigzagCache;
begin
  FAreas := 0;
  ReplayGroup('cache');
  Report;
  AssertTrue(Format('enough areas (%d)', [FAreas]), FAreas >= 8);
end;

{ ---- hand-written ---- }

const
  cBarOption = '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","breaks":[{"start":50,"end":900,"gap":"10%%"}]%s},'
    + '"series":[{"type":"bar","data":[10,30,950,40,1000]}]}';

procedure TAdvChartAxisBreaksOracleTest.TestTheBreakAreaIsOnTheScreen;
var
  a, b: TBGRABitmap;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  x, y, diff: Integer;
  p, q: TBGRAPixel;
begin
  { the same chart with its area drawn and not: the area changes the
    pixels across the bar it crosses, inside the break's band }
  NewChart;
  FChart.SetBounds(0, 0, 600, 400);
  a := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  b := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.SetOption(Format(cBarOption, ['']), True);
    FChart.Render(a.Canvas, Rect(0, 0, 600, 400), 96);
    ax := AxisOf('y', 0);
    AssertTrue('the axis', ax <> nil);
    spec := FChart.Build.Grid(0).SpecFor(ax);
    AssertEquals('one break area', 1, Length(spec^.BreakAreas));
    y := Round((spec^.BreakAreas[0].Lo + spec^.BreakAreas[0].Hi) / 2);
    FChart.SetOption(Format(cBarOption, [',"breakArea":{"show":false}']), True);
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

procedure TAdvChartAxisBreaksOracleTest.TestARenderWithNothingNewDrawsNothing;
begin
  NewChart;
  FChart.SetOption(Format(cBarOption, ['']), True);
  RenderAt(600, 400);
  AssertTrue('the first render drew', DrawsSince > 0);
  { a repaint of the same layout, and a relayout of the same rect }
  RenderAt(600, 400);
  AssertEquals('a repaint draws nothing', 0, DrawsSince);
  FChart.SetOption(Format(cBarOption, ['']), False);
  RenderAt(600, 400);
  AssertEquals('a merge of the same option draws nothing', 0, DrawsSince);
  { a narrower grid needs fewer points: still nothing new }
  RenderAt(400, 400);
  AssertEquals('a narrower grid draws nothing', 0, DrawsSince);
end;

procedure TAdvChartAxisBreaksOracleTest.TestACategoryAxisIgnoresItsBreaks;
var ax: TTyAxis;
begin
  NewChart;
  FChart.SetOption('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"],'
    + '"breaks":[{"start":1,"end":2,"gap":"5%"}]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[1,2,3,4]}]}', True);
  RenderAt(600, 400);
  ax := AxisOf('x', 0);
  AssertTrue('the axis', ax <> nil);
  AssertTrue('no break mapper on a category axis', ax.Scale.BreakMapper = nil);
  AssertEquals('no area', 0, Length(FChart.Build.Grid(0).SpecFor(ax)^.BreakAreas));
  AssertEquals('no random number', 0, DrawsSince);
end;

initialization
  RegisterTest(TAdvChartAxisBreaksOracleTest);
end.
