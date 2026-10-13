unit test.advchart.parallel;
{$mode objfpc}{$H+}
{ THE PARALLEL COORDINATE SYSTEM, ITS AXES AND ITS SERIES, HELD TO UPSTREAM
  [Batch 128, C19].

  tools/advchart-oracle/parallel.js runs the real ECharts 6.1 build in node
  (server-side, zrender's width table for text, TZ=UTC) and records, chart by
  chart:

    the parallel  its box, its layout, its dimensions in axis order, each
                  axis' type, extent, inverse flag, scale, place, turn and
                  transform, the room its name has and whether its labels
                  show, its active intervals;
    the axes      every element each AxisBuilder draws -- the line, arrows,
                  ticks (with the ones a hidden label took), minor ticks,
                  labels (text, place, turn, alignment, hidden), the name
                  as drawn after its cut;
    the series    every row's polyline (an empty value drops its point),
                  its curve's commands, stroke, width, opacity, dash, z2 and
                  active state;
    the steps     a pointer over a line, a leave, the actions (highlight,
                  downplay, legendToggleSelect, axisAreaSelect) and a merge:
                  what is hovered, the chart events, the tooltip's rows,
                  every row's states and look, and the whole record again
                  after an action or a merge;
    the frames    the data group's enter clip as it grows;
    conversions   containPixel / convertToPixel / convertFromPixel with
                  parallel, parallelAxis and series finders.

  This replays it through the control, bit for bit: ParallelLayout,
  ParallelSolvedOf, HitTestAt, the events, TooltipContent, ItemStates,
  LegendLayout, the clip proxy, ContainPixelData / ConvertToPixelData.
  Text is measured with zrender's width table. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Convert,
     tyControls.AdvChart.States, tyControls.AdvChart.Events,
     tyControls.AdvChart.Tooltip, tyControls.AdvChart.Legend,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.Polar,
     tyControls.AdvChart.Parallel, tyControls.AdvChart.Export,
     tyControls.AdvanceChart, test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TParProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    Events: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Leave;
    function List: TTyPaintList;
    function Frame: TTyPaintList;
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
    { an action's events, which ChartOn does not take by name }
    procedure OnAny(Sender: TObject; const AEvent: TTyChartEvent);
    function Drawn: TTyChartViews;
  end;

  TAdvChartParallelOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TParProbe;
    FRoot, FTable: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FSavedSource: TTyDateTimeNameSource;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameColour(const AWhat: string; AGot: TTyChartColor; AWant: TJSONData);
    procedure NewChart(AMode: TTyChartAnimationMode);
    procedure RenderNow;
    procedure ShowCase(ACase: TJSONObject; AMode: TTyChartAnimationMode);
    function Cases: TJSONArray;
    procedure Finish(const AWhat: string; AMin: Integer);
    procedure CheckLine(const AWhat: string; const L: TTyPolarLine; ARec: TJSONObject);
    procedure CheckParallel(ARec: TJSONObject);
    procedure CheckAxisView(const AWhat: string; const V: TTyParallelAxisView;
      ARec: TJSONObject);
    procedure CheckSeries(ARec: TJSONObject);
    procedure CheckLegend(AWant: TJSONArray);
    procedure CheckRecord(ARec: TJSONObject; AViews: Boolean);
    procedure CheckStep(AStep: TJSONObject);
    procedure CheckProbe(AProbe: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCoordinateSystemIsUpstreams;
    procedure TestTheAxesDrawWhatUpstreamDraws;
    procedure TestTheRowsAreUpstreams;
    procedure TestTheStepsAreUpstreams;
    procedure TestTheEnterClipIsUpstreams;
    procedure TestEveryConversionIsUpstreams;
  end;

  { What the oracle does not reach. }
  TAdvChartParallelTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TParProbe;
    FBmp: TBGRABitmap;
    procedure Show(const AOption: string; AMode: TTyChartAnimationMode);
    procedure RenderNow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLinesAndAxesArePainted;
    procedure TestTheSmoothCurveIsSmoothBezier;
    procedure TestTheIntervalsLiveOnTheAxisModel;
    procedure TestTheActionNamesItsAxesAsAQuery;
    procedure TestAProgressiveSeriesComesInChunks;
    procedure TestAnExcludedParallelAxisIsNotDrawn;
    procedure TestASeriesOnNoParallelSaysSo;
    procedure TestTheClipIsTheViewsFirstRenderOnly;
  end;

implementation

const
  T0 = 1700000000000.0;

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
  System.Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  System.Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavTop: Result := 'top';
    tavBottom: Result := 'bottom';
  else
    Result := 'middle';
  end;
end;

function TypeName(AT: TTyAxisType): string;
begin
  case AT of
    atCategory: Result := 'category';
    atTime: Result := 'time';
    atLog: Result := 'log';
  else
    Result := 'value';
  end;
end;

function ActiveName(A: TTyParallelActive): string;
begin
  case A of
    ppaActive: Result := 'active';
    ppaInactive: Result := 'inactive';
  else
    Result := 'normal';
  end;
end;

function KindName(AKind: TTyConvertKind): string;
begin
  case AKind of
    cvkNumber: Result := 'num';
    cvkArray: Result := 'arr';
    cvkError: Result := 'throw';
  else
    Result := 'none';
  end;
end;

{ the oracle's input: every number written as an object whose one key is
  "h", its hex }
function Decode(AData: TJSONData): TJSONData;
var
  o: TJSONObject;
  i: Integer;
begin
  case AData.JSONType of
    jtArray:
      begin
        Result := TJSONArray.Create;
        for i := 0 to AData.Count - 1 do
          TJSONArray(Result).Add(Decode(AData.Items[i]));
      end;
    jtObject:
      begin
        o := TJSONObject(AData);
        if (o.Count = 1) and (o.Names[0] = 'h') and (o.Items[0].JSONType = jtString) then
          Exit(TJSONFloatNumber.Create(FromHex(o.Items[0].AsString)));
        Result := TJSONObject.Create;
        for i := 0 to o.Count - 1 do
          TJSONObject(Result).Add(o.Names[i], Decode(o.Items[i]));
      end;
  else
    Result := AData.Clone;
  end;
end;

type
  TPRow = record
    Marker, Name, Value: string;
    HasMarker, HasName, HasValue: Boolean;
  end;
  TPRows = array of TPRow;

function RowsOf(ABlock: TTyTooltipBlock): TPRows;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j: Integer;
  row: TPRow;
begin
  Result := nil;
  if ABlock = nil then Exit;
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  for i := 0 to High(lines) do
  begin
    row := Default(TPRow);
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind = ttrMarker then
      begin
        row.HasMarker := True;
        row.Marker := 'item';
      end
      else if lines[i].Runs[j].FontWeight = 900 then
      begin
        row.HasValue := True;
        row.Value := lines[i].Runs[j].Text;
      end
      else if not row.HasName then
      begin
        row.HasName := True;
        row.Name := lines[i].Runs[j].Text;
      end
      else
      begin
        row.HasValue := True;
        row.Value := lines[i].Runs[j].Text;
      end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := row;
  end;
end;

function RowText(const R: TPRow): string;
  function Q(AHas: Boolean; const S: string): string;
  begin
    if AHas then Result := '"' + S + '"' else Result := 'null';
  end;
begin
  Result := '{' + Q(R.HasMarker, R.Marker) + ' ' + Q(R.HasName, R.Name) + ' '
    + Q(R.HasValue, R.Value) + '}';
end;

function WantRowText(ARow: TJSONObject): string;
  function Q(const AKey: string): string;
  var d: TJSONData;
  begin
    d := ARow.Find(AKey);
    if (d = nil) or (d.JSONType = jtNull) then Result := 'null'
    else Result := '"' + d.AsString + '"';
  end;
begin
  Result := '{' + Q('marker') + ' ' + Q('name') + ' ' + Q('value') + '}';
end;

{ ==================== the probe ==================== }

constructor TParProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
end;

destructor TParProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

function TParProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TParProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TParProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TParProbe.Leave;
begin
  MouseLeave;
end;

function TParProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TParProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function TParProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

procedure TParProbe.OnAny(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType = 'axisareaselected') or (AEvent.EventType = 'brushselected')
    or (AEvent.EventType = 'legendselectchanged') or (AEvent.EventType = 'highlight')
    or (AEvent.EventType = 'downplay') then
    Events.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

function TParProbe.Drawn: TTyChartViews;
begin
  Result := LastViewsDrawn;
end;

procedure TParProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if AEvent.Payload <> '' then
    Events.Add(AEvent.EventType + #9 + AEvent.Payload)
  else
    Events.Add(Format('%s'#9'%d'#9'%d'#9'%s', [AEvent.EventType,
      AEvent.Params.SeriesIndex, AEvent.Params.DataIndex, AEvent.Params.Name]));
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartParallelOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-parallel.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-parallel.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-grid-bounds.json'));
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartParallelOracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FTable);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  TyDateTimeNameSource := FSavedSource;
  inherited TearDown;
end;

procedure TAdvChartParallelOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartParallelOracleTest.Same(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    Bad(AWhat + ': upstream has no number');
    Exit;
  end;
  want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartParallelOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartParallelOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TAdvChartParallelOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True), BoolToStr(AWant, True)]));
end;

procedure TAdvChartParallelOracleTest.SameColour(const AWhat: string;
  AGot: TTyChartColor; AWant: TJSONData);
var a: TJSONArray;
begin
  Inc(FCompared);
  if not (AWant is TJSONArray) then
  begin
    Bad(AWhat + ': no colour upstream');
    Exit;
  end;
  a := TJSONArray(AWant);
  if ((AGot shr 16) and $FF <> Cardinal(a.Integers[0]))
    or ((AGot shr 8) and $FF <> Cardinal(a.Integers[1]))
    or (AGot and $FF <> Cardinal(a.Integers[2]))
    or ((AGot shr 24) and $FF <> Cardinal(Round(a.Floats[3] * 255))) then
    Bad(Format('%s is rgba(%d,%d,%d,%s) upstream, $%.8x here', [AWhat,
      a.Integers[0], a.Integers[1], a.Integers[2], Txt(a.Floats[3]), AGot]));
end;

procedure TAdvChartParallelOracleTest.Finish(const AWhat: string; AMin: Integer);
begin
  if GetEnvironmentVariable('TY_PARALLEL_COUNTS') = '1' then
    WriteLn(Format('%s: %d compared', [AWhat, FCompared]));
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartParallelOracleTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

procedure TAdvChartParallelOracleTest.NewChart(AMode: TTyChartAnimationMode);
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TParProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FChart.SetBounds(0, 0, 600, 400);
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.ChartOn('mouseover', @FChart.OnEv);
  FChart.ChartOn('mousemove', @FChart.OnEv);
  FChart.ChartOn('mouseout', @FChart.OnEv);
  FChart.OnChartEvent := @FChart.OnAny;
end;

procedure TAdvChartParallelOracleTest.RenderNow;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

procedure TAdvChartParallelOracleTest.ShowCase(ACase: TJSONObject;
  AMode: TTyChartAnimationMode);
begin
  FWhere := ACase.Strings['id'];
  NewChart(AMode);
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
end;

procedure TAdvChartParallelOracleTest.CheckLine(const AWhat: string;
  const L: TTyPolarLine; ARec: TJSONObject);
begin
  Same(AWhat + ' x1', L.X1, ARec.Find('x1'));
  Same(AWhat + ' y1', L.Y1, ARec.Find('y1'));
  Same(AWhat + ' x2', L.X2, ARec.Find('x2'));
  Same(AWhat + ' y2', L.Y2, ARec.Find('y2'));
end;

procedure TAdvChartParallelOracleTest.CheckParallel(ARec: TJSONObject);
var
  p: TTyParallel;
  i, k: Integer;
  a: TJSONObject;
  ax: TTyAxis;
  e0, e1: Double;
  what, lay: string;
  arr: TJSONArray;
begin
  p := FChart.ParallelLayout(ARec.Integers['index']);
  if p = nil then
  begin
    Bad('no parallel ' + IntToStr(ARec.Integers['index']));
    Exit;
  end;
  Same('rect x', p.Rect.X, ARec.Arrays['rect'].Items[0]);
  Same('rect y', p.Rect.Y, ARec.Arrays['rect'].Items[1]);
  Same('rect w', p.Rect.W, ARec.Arrays['rect'].Items[2]);
  Same('rect h', p.Rect.H, ARec.Arrays['rect'].Items[3]);
  if p.Horizontal then lay := 'horizontal' else lay := 'vertical';
  SameStr('layout', lay, ARec.Strings['layout']);
  SameInt('axes', p.AxisCount, ARec.Arrays['axes'].Count);
  if p.AxisCount <> ARec.Arrays['axes'].Count then Exit;
  for i := 0 to p.AxisCount - 1 do
  begin
    a := ARec.Arrays['axes'].Objects[i];
    ax := p.Axis(i);
    what := 'axis ' + a.Strings['dim'];
    SameStr(what + ' dim', p.Dims[i], a.Strings['dim']);
    SameInt(what + ' component', p.AxisIndices[i], a.Integers['axisIndex']);
    SameStr(what + ' type', TypeName(ax.AxisType), a.Strings['type']);
    ax.LocalExtent(e0, e1);
    Same(what + ' extent 0', e0, a.Arrays['extent'].Items[0]);
    Same(what + ' extent 1', e1, a.Arrays['extent'].Items[1]);
    SameBool(what + ' inverse', p.AxisInverse[i], a.Booleans['inverse']);
    SameBool(what + ' blank', ax.Scale.Blank, a.Booleans['blank']);
    if not a.Booleans['blank'] then
    begin
      Same(what + ' scale 0', ax.Scale.GetExtent.Start, a.Arrays['scale'].Items[0]);
      Same(what + ' scale 1', ax.Scale.GetExtent.Stop, a.Arrays['scale'].Items[1]);
    end;
    Same(what + ' x', p.Layouts[i].PosX, a.Arrays['position'].Items[0]);
    Same(what + ' y', p.Layouts[i].PosY, a.Arrays['position'].Items[1]);
    Same(what + ' rotation', p.Layouts[i].Rotation, a.Find('rotation'));
    for k := 0 to 5 do
      Same(what + ' transform ' + IntToStr(k), p.Layouts[i].M[k],
        a.Arrays['transform'].Items[k]);
    Same(what + ' name width', p.Layouts[i].NameAvailableWidth, a.Find('nameWidth'));
    SameBool(what + ' label show', p.Layouts[i].LabelShow, a.Booleans['labelShow']);
    arr := a.Arrays['intervals'];
    SameInt(what + ' intervals', Length(p.Intervals[i]), arr.Count);
    if Length(p.Intervals[i]) = arr.Count then
      for k := 0 to arr.Count - 1 do
      begin
        Same(what + ' interval lo', p.Intervals[i][k][0], TJSONArray(arr.Items[k]).Items[0]);
        Same(what + ' interval hi', p.Intervals[i][k][1], TJSONArray(arr.Items[k]).Items[1]);
      end;
  end;
end;

procedure TAdvChartParallelOracleTest.CheckAxisView(const AWhat: string;
  const V: TTyParallelAxisView; ARec: TJSONObject);
var
  arr: TJSONArray;
  o: TJSONObject;
  i, k, built: Integer;
  what: string;
begin
  SameBool(AWhat + ' shown', V.Shown, ARec.Booleans['shown']);
  if not ARec.Booleans['shown'] then Exit;
  Inc(FCompared);
  if (ARec.Find('line').JSONType = jtNull) <> not V.HasLine then
    Bad(AWhat + ' line drawn ' + BoolToStr(V.HasLine, True))
  else if V.HasLine then
    CheckLine(AWhat + ' line', V.Line, ARec.Objects['line']);
  arr := ARec.Arrays['arrows'];
  Inc(FCompared);
  if Length(V.Spec.Arrows) <> arr.Count then
    Bad(Format('%s %d arrows, upstream %d', [AWhat, Length(V.Spec.Arrows), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      SameStr(AWhat + ' arrow type', V.Spec.Arrows[i].SymbolType, o.Strings['type']);
      Same(AWhat + ' arrow x', V.Spec.Arrows[i].X, o.Find('x'));
      Same(AWhat + ' arrow y', V.Spec.Arrows[i].Y, o.Find('y'));
      Same(AWhat + ' arrow rotation', V.Spec.Arrows[i].Rotation, o.Find('rotation'));
      Same(AWhat + ' arrow w', V.Spec.Arrows[i].W, o.Find('w'));
      Same(AWhat + ' arrow h', V.Spec.Arrows[i].H, o.Find('h'));
    end;
  arr := ARec.Arrays['ticks'];
  Inc(FCompared);
  if Length(V.Ticks) <> arr.Count then
    Bad(Format('%s %d ticks, upstream %d', [AWhat, Length(V.Ticks), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := AWhat + ' tick ' + o.Strings['tick'];
      SameStr(what + ' value', TyJsNumberToString(V.Ticks[i].Value), o.Strings['tick']);
      CheckLine(what, V.Ticks[i], o);
      SameBool(what + ' hidden', not V.Ticks[i].Drawn, o.Booleans['ignore']);
    end;
  arr := ARec.Arrays['minorTicks'];
  Inc(FCompared);
  if Length(V.MinorTicks) <> arr.Count then
    Bad(Format('%s %d minor ticks, upstream %d', [AWhat, Length(V.MinorTicks), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
      CheckLine(AWhat + ' minor tick ' + IntToStr(i), V.MinorTicks[i], arr.Objects[i]);
  arr := ARec.Arrays['labels'];
  built := 0;
  for k := 0 to High(V.Spec.Placements) do
    if V.Spec.Placements[k].Built then Inc(built);
  Inc(FCompared);
  if built <> arr.Count then
    Bad(Format('%s %d labels built, upstream %d', [AWhat, built, arr.Count]))
  else
  begin
    i := 0;
    for k := 0 to High(V.Spec.Placements) do
    begin
      if not V.Spec.Placements[k].Built then Continue;
      o := arr.Objects[i];
      what := AWhat + ' label ' + o.Strings['tick'];
      SameStr(what + ' value', TyJsNumberToString(V.Spec.TickValues[k]), o.Strings['tick']);
      SameStr(what + ' text', V.Spec.Placements[k].Text, o.Strings['text']);
      Same(what + ' x', V.Spec.Placements[k].X, o.Find('x'));
      Same(what + ' y', V.Spec.Placements[k].Y, o.Find('y'));
      Same(what + ' rotation', V.Spec.Placements[k].DecRotation, o.Find('rotation'));
      SameStr(what + ' align', AlignName(V.Spec.Placements[k].AnchorH), o.Strings['align']);
      SameStr(what + ' vertical align', VAlignName(V.Spec.Placements[k].AnchorV), o.Strings['va']);
      SameBool(what + ' hidden', not V.Spec.Placements[k].Shown, o.Booleans['ignore']);
      Inc(i);
    end;
  end;
  Inc(FCompared);
  if ARec.Find('name').JSONType = jtNull then
  begin
    if V.Spec.NamePlacement.Shown then Bad(AWhat + ' a name upstream does not draw');
  end
  else if not V.Spec.NamePlacement.Shown then
    Bad(AWhat + ' no name')
  else
  begin
    o := ARec.Objects['name'];
    SameStr(AWhat + ' name text', V.Spec.NamePlacement.Text, o.Strings['text']);
    Same(AWhat + ' name x', V.Spec.NamePlacement.X, o.Find('x'));
    Same(AWhat + ' name y', V.Spec.NamePlacement.Y, o.Find('y'));
    Same(AWhat + ' name rotation', V.Spec.NamePlacement.RotationRad, o.Find('rotation'));
    SameStr(AWhat + ' name align', AlignName(V.Spec.NamePlacement.AnchorH), o.Strings['align']);
    SameStr(AWhat + ' name vertical align', VAlignName(V.Spec.NamePlacement.AnchorV), o.Strings['va']);
  end;
end;

procedure TAdvChartParallelOracleTest.CheckSeries(ARec: TJSONObject);
var
  sol: TTyParallelSolved;
  items, path, pts: TJSONArray;
  it: TJSONObject;
  i, k, q: Integer;
  r: TTyParallelRow;
  what, dw: string;
begin
  sol := FChart.ParallelSolvedOf(ARec.Integers['seriesIndex']);
  what := 'series ' + IntToStr(ARec.Integers['seriesIndex']);
  SameBool(what + ' solved', sol.Valid, True);
  if not sol.Valid then Exit;
  SameInt(what + ' parallel', sol.ParallelIndex, ARec.Integers['parallelIndex']);
  items := ARec.Arrays['items'];
  SameInt(what + ' rows', Length(sol.Rows), items.Count);
  if Length(sol.Rows) <> items.Count then Exit;
  if ARec.Find('smooth').JSONType <> jtNull then
  begin
    Same(what + ' smooth', sol.Smooth, ARec.Find('smooth'));
    SameInt(what + ' z', sol.Z, ARec.Integers['z']);
  end;
  for i := 0 to items.Count - 1 do
  begin
    it := items.Objects[i];
    if not it.Booleans['el'] then Continue;
    r := sol.Rows[i];
    FWhere := FWhere;
    pts := it.Arrays['points'];
    SameInt(Format('%s row %d points', [what, i]), Length(r.Pts) * 2, pts.Count);
    if Length(r.Pts) * 2 = pts.Count then
      for k := 0 to High(r.Pts) do
      begin
        Same(Format('%s row %d point %d x', [what, i, k]), r.Pts[k].X, pts.Items[k * 2]);
        Same(Format('%s row %d point %d y', [what, i, k]), r.Pts[k].Y, pts.Items[k * 2 + 1]);
      end;
    { the path: M then L per point, or M then C per segment }
    path := it.Arrays['path'];
    if Length(r.Cmds) > 0 then
    begin
      SameInt(Format('%s row %d path length', [what, i]), 3 + (Length(r.Cmds) - 1) * 7, path.Count);
      if 3 + (Length(r.Cmds) - 1) * 7 = path.Count then
      begin
        SameStr(Format('%s row %d move', [what, i]), 'M', path.Strings[0]);
        Same(Format('%s row %d move x', [what, i]), r.Cmds[0].X, path.Items[1]);
        Same(Format('%s row %d move y', [what, i]), r.Cmds[0].Y, path.Items[2]);
        q := 3;
        for k := 1 to High(r.Cmds) do
        begin
          SameStr(Format('%s row %d seg %d', [what, i, k]), 'C', path.Strings[q]);
          Same(Format('%s row %d seg %d cp1x', [what, i, k]), r.Cmds[k].X1, path.Items[q + 1]);
          Same(Format('%s row %d seg %d cp1y', [what, i, k]), r.Cmds[k].Y1, path.Items[q + 2]);
          Same(Format('%s row %d seg %d cp2x', [what, i, k]), r.Cmds[k].X2, path.Items[q + 3]);
          Same(Format('%s row %d seg %d cp2y', [what, i, k]), r.Cmds[k].Y2, path.Items[q + 4]);
          Same(Format('%s row %d seg %d x', [what, i, k]), r.Cmds[k].X, path.Items[q + 5]);
          Same(Format('%s row %d seg %d y', [what, i, k]), r.Cmds[k].Y, path.Items[q + 6]);
          Inc(q, 7);
        end;
      end;
    end
    else if Length(r.Pts) >= 2 then
    begin
      SameInt(Format('%s row %d path length', [what, i]), Length(r.Pts) * 3, path.Count);
      if path.Count > 0 then SameStr(Format('%s row %d straight', [what, i]), 'M', path.Strings[0]);
      if (path.Count > 3) then SameStr(Format('%s row %d straight', [what, i]), 'L', path.Strings[3]);
    end
    else
      SameInt(Format('%s row %d no path', [what, i]), 0, path.Count);
    SameColour(Format('%s row %d stroke', [what, i]), r.Stroke, it.Find('stroke'));
    Same(Format('%s row %d width', [what, i]), r.Width, it.Find('lineWidth'));
    Same(Format('%s row %d opacity', [what, i]), r.Opacity, it.Find('opacity'));
    if it.Find('lineDash').JSONType = jtNull then dw := ''
    else if it.Find('lineDash').JSONType = jtString then dw := it.Strings['lineDash']
    else dw := it.Find('lineDash').AsJSON;
    SameStr(Format('%s row %d dash', [what, i]), r.DashWord, dw);
    SameInt(Format('%s row %d z2', [what, i]), sol.Z2, it.Integers['z2']);
    SameStr(Format('%s row %d active', [what, i]), ActiveName(r.Active), it.Strings['active']);
  end;
end;

procedure TAdvChartParallelOracleTest.CheckLegend(AWant: TJSONArray);
var
  lay: TTyLegendLayout;
  j, k: Integer;
  w: TJSONObject;
  found: Boolean;
begin
  if FChart.LegendLayoutCount = 0 then
  begin
    Bad('no legend here');
    Exit;
  end;
  lay := FChart.LegendLayout(0);
  for j := 0 to AWant.Count - 1 do
  begin
    w := AWant.Objects[j];
    found := False;
    for k := 0 to High(lay.Items) do
      if lay.Items[k].Name = w.Strings['name'] then
      begin
        found := True;
        SameStr('legend ' + w.Strings['name'] + ' icon', lay.Items[k].Icon, w.Strings['icon']);
        SameBool('legend ' + w.Strings['name'] + ' selected', lay.Items[k].Selected, w.Booleans['selected']);
        if w.Booleans['selected'] then
          SameColour('legend ' + w.Strings['name'] + ' colour', lay.Items[k].Colour, w.Find('fill'));
      end;
    if not found then Bad('no legend item ' + w.Strings['name']);
  end;
end;

procedure TAdvChartParallelOracleTest.CheckRecord(ARec: TJSONObject; AViews: Boolean);
var
  i, a: Integer;
  pr: TJSONObject;
  p: TTyParallel;
begin
  for i := 0 to ARec.Arrays['parallels'].Count - 1 do
  begin
    pr := ARec.Arrays['parallels'].Objects[i];
    CheckParallel(pr);
    if not AViews then Continue;
    p := FChart.ParallelLayout(pr.Integers['index']);
    if (p = nil) or (p.AxisCount <> pr.Arrays['axes'].Count) then Continue;
    for a := 0 to p.AxisCount - 1 do
      CheckAxisView('parallel' + IntToStr(pr.Integers['index']) + ' ' + p.Dims[a],
        p.Views[a], pr.Arrays['axes'].Objects[a].Objects['view']);
  end;
  for i := 0 to ARec.Arrays['series'].Count - 1 do
    CheckSeries(ARec.Arrays['series'].Objects[i]);
  if ARec.Find('legend').JSONType = jtArray then CheckLegend(ARec.Arrays['legend']);
end;

{ ---- the coordinate system ---- }

procedure TAdvChartParallelOracleTest.TestTheCoordinateSystemIsUpstreams;
var
  c, i, n: Integer;
  cs: TJSONObject;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    ShowCase(cs, camOff);
    SameInt('parallels', FChart.ParallelCount, cs.Objects['record'].Arrays['parallels'].Count);
    for i := 0 to cs.Objects['record'].Arrays['parallels'].Count - 1 do
    begin
      CheckParallel(cs.Objects['record'].Arrays['parallels'].Objects[i]);
      Inc(n);
    end;
  end;
  AssertTrue(Format('enough parallels (%d)', [n]), n >= 30);
  Finish('the coordinate system', 1500);
end;

procedure TAdvChartParallelOracleTest.TestTheAxesDrawWhatUpstreamDraws;
var
  c, i, a, n: Integer;
  cs, pr: TJSONObject;
  p: TTyParallel;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    ShowCase(cs, camOff);
    for i := 0 to cs.Objects['record'].Arrays['parallels'].Count - 1 do
    begin
      pr := cs.Objects['record'].Arrays['parallels'].Objects[i];
      p := FChart.ParallelLayout(pr.Integers['index']);
      if (p = nil) or (p.AxisCount <> pr.Arrays['axes'].Count) then
      begin
        Bad('no parallel to compare');
        Continue;
      end;
      for a := 0 to p.AxisCount - 1 do
      begin
        CheckAxisView('parallel' + IntToStr(pr.Integers['index']) + ' ' + p.Dims[a],
          p.Views[a], pr.Arrays['axes'].Objects[a].Objects['view']);
        Inc(n);
      end;
    end;
  end;
  AssertTrue(Format('enough axes (%d)', [n]), n >= 90);
  Finish('the axes', 5000);
end;

procedure TAdvChartParallelOracleTest.TestTheRowsAreUpstreams;
var
  c, i, n: Integer;
  cs: TJSONObject;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    ShowCase(cs, camOff);
    for i := 0 to cs.Objects['record'].Arrays['series'].Count - 1 do
    begin
      CheckSeries(cs.Objects['record'].Arrays['series'].Objects[i]);
      Inc(n);
    end;
    if cs.Objects['record'].Find('legend').JSONType = jtArray then
      CheckLegend(cs.Objects['record'].Arrays['legend']);
  end;
  AssertTrue(Format('enough series (%d)', [n]), n >= 35);
  Finish('the rows', 2000);
end;

{ ---- the steps ---- }

procedure TAdvChartParallelOracleTest.CheckStep(AStep: TJSONObject);
var
  hv, tip, er: TJSONObject;
  ev, rows, states: TJSONArray;
  el, j, k, s, r: Integer;
  d: TTyChartDatumRef;
  got, want, typ: string;
  item: TTyStItem;
  block: TTyTooltipBlock;
  prow: TPRows;
  parts: TStringList;
  pl: TJSONData;
begin
  { the row under the pointer }
  if AStep.Find('hover').JSONType = jtObject then
  begin
    hv := AStep.Objects['hover'];
    d := FChart.HitTestAt(AStep.Integers['x'], AStep.Integers['y'], el);
    if hv.Find('seriesIndex').JSONType = jtNull then
      SameBool('nothing hovered', TyChartDatumValid(d), False)
    else
    begin
      SameInt('hovered series', d.SeriesIndex, hv.Integers['seriesIndex']);
      SameInt('hovered row', d.DataIndex, hv.Integers['dataIndex']);
    end;
  end;
  { the events: the mouse ones by series, row and name; an action's by its
    payload }
  ev := AStep.Arrays['events'];
  SameInt('events', FChart.Events.Count, ev.Count);
  parts := TStringList.Create;
  try
    parts.Delimiter := #9;
    parts.StrictDelimiter := True;
    for j := 0 to Min(ev.Count, FChart.Events.Count) - 1 do
    begin
      er := ev.Objects[j];
      typ := er.Strings['type'];
      parts.DelimitedText := FChart.Events[j];
      SameStr(Format('event %d type', [j]), parts[0], typ);
      if (typ = 'mouseover') or (typ = 'mousemove') or (typ = 'mouseout') then
      begin
        if parts.Count >= 4 then
        begin
          got := Format('%s:%s "%s"', [parts[1], parts[2], parts[3]]);
          want := Format('%d:%d "%s"', [er.Integers['seriesIndex'],
            er.Integers['dataIndex'], er.Get('name', '')]);
          SameStr(Format('event %d', [j]), got, want);
        end;
      end
      else if (typ = 'axisareaselected') and (parts.Count >= 2) then
      begin
        pl := GetJSON(parts[1]);
        try
          SameStr(Format('event %d intervals', [j]),
            TJSONObject(pl).Find('intervals').AsJSON, er.Find('intervals').AsJSON);
          if er.Find('parallelAxisId').JSONType <> jtNull then
            SameStr(Format('event %d axis id', [j]), TJSONObject(pl).Get('parallelAxisId', ''),
              er.Strings['parallelAxisId']);
        finally
          pl.Free;
        end;
      end
      else if (typ = 'brushselected') and (parts.Count >= 2) then
      begin
        pl := GetJSON(parts[1]);
        try
          SameStr(Format('event %d batch', [j]), TJSONObject(pl).Find('batch').AsJSON,
            er.Find('batch').AsJSON);
        finally
          pl.Free;
        end;
      end
      else if (typ = 'legendselectchanged') and (parts.Count >= 2) then
      begin
        pl := GetJSON(parts[1]);
        try
          SameStr(Format('event %d name', [j]), TJSONObject(pl).Get('name', ''), er.Strings['name']);
          SameStr(Format('event %d selected', [j]), TJSONObject(pl).Find('selected').AsJSON,
            er.Find('selected').AsJSON);
        finally
          pl.Free;
        end;
      end;
    end;
    if FChart.Events.Count <> ev.Count then
      for j := 0 to FChart.Events.Count - 1 do Bad('  here: ' + FChart.Events[j]);
  finally
    parts.Free;
  end;
  { the tooltip }
  tip := AStep.Objects['tooltip'];
  SameBool('the tooltip shown', FChart.TooltipShown, tip.Booleans['shown']);
  if tip.Booleans['shown'] and FChart.TooltipShown then
  begin
    rows := tip.Arrays['rows'];
    block := FChart.ContentOf(FChart.TooltipShownDatum);
    try
      prow := RowsOf(block);
    finally
      block.Free;
    end;
    SameInt('tooltip rows', Length(prow), rows.Count);
    if Length(prow) = rows.Count then
      for j := 0 to rows.Count - 1 do
        SameStr(Format('tooltip row %d', [j]), RowText(prow[j]), WantRowText(rows.Objects[j]));
  end;
  { every row's states and look }
  states := AStep.Arrays['states'];
  for j := 0 to states.Count - 1 do
  begin
    er := states.Objects[j];
    s := er.Integers['seriesIndex'];
    r := er.Integers['dataIndex'];
    if not FChart.ItemStates(s, r, item) then
    begin
      Bad(Format('no states for series %d row %d', [s, r]));
      Continue;
    end;
    want := '';
    for k := 0 to er.Arrays['states'].Count - 1 do
    begin
      if want <> '' then want := want + ',';
      want := want + er.Arrays['states'].Strings[k];
    end;
    SameStr(Format('series %d row %d states', [s, r]), TyStNamesText(item.Host.States), want);
    if item.Host.Cur.Has[stkStroke] then
      SameColour(Format('series %d row %d stroke', [s, r]), item.Host.Cur.Color[stkStroke],
        er.Find('stroke'));
    if item.Host.Cur.Has[stkOpacity] then
      Same(Format('series %d row %d opacity', [s, r]), item.Host.Cur.Num[stkOpacity],
        er.Find('opacity'));
    if item.Host.Cur.Has[stkLineWidth] then
      Same(Format('series %d row %d line width', [s, r]), item.Host.Cur.Num[stkLineWidth],
        er.Find('lineWidth'));
    if item.Host.Cur.Has[stkZ2] then
      SameInt(Format('series %d row %d z2', [s, r]), Round(item.Host.Cur.Num[stkZ2]),
        er.Integers['z2']);
  end;
  if AStep.Find('record') is TJSONObject then
    CheckRecord(AStep.Objects['record'], False);
end;

procedure TAdvChartParallelOracleTest.TestTheStepsAreUpstreams;
var
  c, j, steps: Integer;
  cs, st: TJSONObject;
  t, id: string;
  nowMs: Double;
begin
  steps := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Arrays['steps'].Count = 0 then Continue;
    id := cs.Strings['id'];
    ShowCase(cs, camOff);
    FChart.TooltipNow := 0;
    for j := 0 to cs.Arrays['steps'].Count - 1 do
    begin
      st := cs.Arrays['steps'].Objects[j];
      t := st.Strings['t'];
      FWhere := id + '/' + IntToStr(j) + ' ' + t;
      nowMs := (j + 1) * 1000;
      FChart.TooltipNow := nowMs;
      FChart.Events.Clear;
      if t = 'move' then
        FChart.Move(st.Integers['x'], st.Integers['y'])
      else if t = 'leave' then
        FChart.Leave
      else if t = 'action' then
        FChart.DispatchAction(st.Objects['payload'].AsJSON)
      else if t = 'merge' then
        FChart.SetOption(st.Objects['option'].AsJSON, False);
      FChart.TooltipTick(nowMs + 500);
      FChart.TooltipNow := nowMs + 500;
      RenderNow;
      CheckStep(st);
      Inc(steps);
    end;
  end;
  AssertTrue(Format('enough steps (%d)', [steps]), steps >= 15);
  Finish('the steps', 800);
end;

{ ---- the enter clip ---- }

procedure TAdvChartParallelOracleTest.TestTheEnterClipIsUpstreams;
var
  c, f, k, s, n: Integer;
  cs, fr, cl: TJSONObject;
  p: TTyChartAnimProxy;
  t: Double;
  want: TJSONArray;
  sol: TTyParallelSolved;
  full: Boolean;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'enter' then Continue;
    FWhere := cs.Strings['id'];
    NewChart(camAlways);
    FChart.SetOption(cs.Objects['option'].AsJSON, True);
    RenderNow;
    for f := 0 to cs.Arrays['frames'].Count - 1 do
    begin
      fr := cs.Arrays['frames'].Objects[f];
      t := fr.Floats['t'];
      FWhere := cs.Strings['id'] + ' at ' + Txt(t);
      if t > 0 then FChart.AnimTick(T0 + t);
      RenderNow;
      for k := 0 to fr.Arrays['clips'].Count - 1 do
      begin
        cl := fr.Arrays['clips'].Objects[k];
        s := cl.Integers['seriesIndex'];
        p := FChart.AnimFindProxy(s, -1, 'parallelClip');
        Inc(FCompared);
        if cl.Find('clip').JSONType = jtNull then
        begin
          if (p <> nil) and not p.AtFinal then
            Bad(Format('series %d still clipped, upstream not', [s]));
          Continue;
        end;
        want := cl.Arrays['clip'];
        sol := FChart.ParallelSolvedOf(s);
        { a whole clip waiting for its removal draws what no clip draws }
        full := SameBits(FromHex(want.Strings[2]), sol.Clip.W)
          and SameBits(FromHex(want.Strings[3]), sol.Clip.H);
        if (p = nil) or p.AtFinal then
        begin
          if not full then Bad(Format('series %d not clipped, upstream %s x %s', [s,
            Txt(FromHex(want.Strings[2])), Txt(FromHex(want.Strings[3]))]));
          Continue;
        end;
        Same(Format('series %d clip x', [s]), p.Num('shape.x'), want.Items[0]);
        Same(Format('series %d clip y', [s]), p.Num('shape.y'), want.Items[1]);
        Same(Format('series %d clip w', [s]), p.Num('shape.width'), want.Items[2]);
        Same(Format('series %d clip h', [s]), p.Num('shape.height'), want.Items[3]);
        Inc(n);
      end;
    end;
  end;
  AssertTrue(Format('enough clips (%d)', [n]), n >= 15);
  Finish('the enter clip', 80);
end;

{ ---- the conversions ---- }

procedure TAdvChartParallelOracleTest.CheckProbe(AProbe: TJSONObject);
var
  op, k: string;
  finder, value: TJSONData;
  outNode: TJSONObject;
  r: TTyConvertResult;
  got: Boolean;
  i: Integer;
  arr: TJSONArray;
  where0: string;
begin
  op := AProbe.Strings['op'];
  outNode := AProbe.Objects['out'];
  k := outNode.Strings['k'];
  where0 := FWhere;
  FWhere := where0 + ' ' + op + ' ' + AProbe.Objects['finder'].Strings['text']
    + ' ' + AProbe.Objects['value'].Strings['text'];
  finder := Decode(AProbe.Objects['finder'].Find('in'));
  value := Decode(AProbe.Objects['value'].Find('in'));
  try
    if op = 'contain' then
    begin
      got := FChart.ContainPixelData(finder, value);
      Inc(FCompared);
      if k = 'throw' then
      begin
        if got then Bad('contains, upstream throws');
      end
      else if got <> outNode.Booleans['v'] then
        Bad(Format('contains %s, upstream %s', [BoolToStr(got, True),
          BoolToStr(outNode.Booleans['v'], True)]));
      Exit;
    end;
    if op = 'to' then r := FChart.ConvertToPixelData(finder, value)
    else r := FChart.ConvertFromPixelData(finder, value);
    Inc(FCompared);
    if KindName(r.Kind) <> k then
    begin
      Bad(Format('%s here, upstream %s', [KindName(r.Kind), k]));
      Exit;
    end;
    if k = 'num' then
      Same('the number', r.Values[0], outNode.Find('v'))
    else if k = 'arr' then
    begin
      arr := outNode.Arrays['v'];
      if Length(r.Values) <> arr.Count then
        Bad(Format('%d numbers, upstream %d', [Length(r.Values), arr.Count]))
      else
        for i := 0 to arr.Count - 1 do
          Same(Format('[%d]', [i]), r.Values[i], arr.Items[i]);
    end;
  finally
    finder.Free;
    value.Free;
    FWhere := where0;
  end;
end;

procedure TAdvChartParallelOracleTest.TestEveryConversionIsUpstreams;
var
  c, p, contains: Integer;
  cs: TJSONObject;
begin
  contains := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'convert' then Continue;
    ShowCase(cs, camOff);
    for p := 0 to cs.Arrays['convert'].Count - 1 do
    begin
      if (cs.Arrays['convert'].Objects[p].Objects['out'].Strings['k'] = 'bool')
        and cs.Arrays['convert'].Objects[p].Objects['out'].Booleans['v'] then
        Inc(contains);
      CheckProbe(cs.Arrays['convert'].Objects[p]);
    end;
  end;
  AssertTrue(Format('enough answers that contain (%d)', [contains]), contains >= 20);
  Finish('the conversions', 90);
end;

{ ==================== hand-written ==================== }

procedure TAdvChartParallelTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartParallelTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartParallelTest.Show(const AOption: string; AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TParProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.OnChartEvent := @FChart.OnAny;
  FChart.SetOption(AOption, True);
  RenderNow;
end;

procedure TAdvChartParallelTest.RenderNow;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

procedure TAdvChartParallelTest.TestTheLinesAndAxesArePainted;
var
  x, y, red, ink: Integer;
  px: TBGRAPixel;
begin
  { one red line across three axes at mid height, and the axis lines }
  Show('{"animation": false, "parallelAxis": [{"dim": 0, "min": 0, "max": 2}, '
    + '{"dim": 1, "min": 0, "max": 2}, {"dim": 2, "min": 0, "max": 2}], '
    + '"series": {"type": "parallel", "lineStyle": {"color": "#ff0000", "width": 3, '
    + '"opacity": 1}, "data": [[1, 1, 1]]}}', camOff);
  red := 0;
  for x := 100 to 500 do
  begin
    px := FBmp.GetPixel(x, 200);
    if (px.red > 200) and (px.green < 80) and (px.blue < 80) then Inc(red);
  end;
  AssertTrue(Format('the line is drawn across the box (%d red pixels)', [red]), red > 300);
  { the middle axis' line at x = 300 (300.5 on the pixel grid) above the
    line: inked }
  ink := 0;
  for y := 70 to 180 do
  begin
    px := FBmp.GetPixel(300, y);
    if (px.red < 250) or (px.green < 250) or (px.blue < 250) then Inc(ink);
  end;
  AssertTrue(Format('the axis line is drawn (%d inked pixels)', [ink]), ink > 80);
  AssertTrue('the axes are a view drawn', cvParallelAxis in FChart.Drawn);
end;

procedure TAdvChartParallelTest.TestTheSmoothCurveIsSmoothBezier;
var
  pts: TTyPointFArray;
  cmds: TTyPathCmdArray;
begin
  SetLength(pts, 3);
  pts[0] := TyPointF(0, 0);
  pts[1] := TyPointF(10, 10);
  pts[2] := TyPointF(30, 0);
  cmds := TyParallelSmoothCmds(pts, 0.5);
  AssertEquals('a move and two curves', 3, Length(cmds));
  AssertTrue('the move', cmds[0].Kind = pckMove);
  { an end point is its own control point }
  AssertEquals('first control is the start x', 0, cmds[1].X1, 0);
  AssertEquals('last control is the end x', 30, cmds[2].X2, 0);
  { the middle point's handles lie along (next - prev) * smooth, split by
    the two distances: v = (15, 0); d0 = sqrt 200, d1 = sqrt 500 }
  AssertEquals('the handle before', 10 + 15 * -(Sqrt(200) / (Sqrt(200) + Sqrt(500))),
    cmds[1].X2, 1e-12);
  AssertEquals('the handle after', 10 + 15 * (Sqrt(500) / (Sqrt(200) + Sqrt(500))),
    cmds[2].X1, 1e-12);
  AssertEquals('no points no curve', 0, Length(TyParallelSmoothCmds(nil, 0.3)));
  AssertEquals('numericToNumber of a string', 0.25,
    TyParallelSmoothOf(TJSONObject(GetJSON('{"smooth": "0.25"}'))), 0);
end;

procedure TAdvChartParallelTest.TestTheIntervalsLiveOnTheAxisModel;
const
  cOpt = '{"animation": false, "parallelAxis": [{"dim": 0}, {"dim": 1}], '
    + '"series": {"type": "parallel", "data": [[1, 1], [2, 2], [3, 3]]}}';
var sol: TTyParallelSolved;
begin
  Show(cOpt, camOff);
  FChart.DispatchAction('{"type": "axisAreaSelect", "parallelAxisIndex": 0, '
    + '"intervals": [[1.5, 2.5]]}');
  RenderNow;
  sol := FChart.ParallelSolvedOf(0);
  AssertTrue('row 1 active', sol.Rows[1].Active = ppaActive);
  AssertTrue('row 0 inactive', sol.Rows[0].Active = ppaInactive);
  AssertEquals('the model keeps one interval', 1, Length(FChart.ParallelIntervals(0)));
  { a merge keeps the model and its intervals }
  FChart.SetOption('{"series": [{"data": [[1, 1], [2, 2]]}]}', False);
  RenderNow;
  AssertEquals('kept across a merge', 1, Length(FChart.ParallelIntervals(0)));
  AssertTrue('still selecting', FChart.ParallelSolvedOf(0).Rows[0].Active = ppaInactive);
  { a notMerge makes new models }
  FChart.SetOption(cOpt, True);
  RenderNow;
  AssertEquals('gone with a notMerge', 0, Length(FChart.ParallelIntervals(0)));
  AssertTrue('normal again', FChart.ParallelSolvedOf(0).Rows[0].Active = ppaNormal);
  AssertEquals('normal opacity', 0.45, FChart.ParallelSolvedOf(0).Rows[0].Opacity, 0);
end;

procedure TAdvChartParallelTest.TestTheActionNamesItsAxesAsAQuery;
begin
  Show('{"animation": false, "parallel": [{}, {}], "parallelAxis": ['
    + '{"dim": 0, "id": "a"}, {"dim": 1, "name": "b"}, {"dim": 0, "parallelIndex": 1}, '
    + '{"dim": 0, "parallelIndex": 7}], '
    + '"series": [{"type": "parallel", "data": [[1, 1]]}]}', camOff);
  FChart.DispatchAction('{"type": "axisAreaSelect", "parallelAxisId": "a", "intervals": [[3, 1]]}');
  AssertEquals('by id', 1, Length(FChart.ParallelIntervals(0)));
  AssertEquals('ascending', 1, FChart.ParallelIntervals(0)[0][0], 0);
  AssertEquals('only it', 0, Length(FChart.ParallelIntervals(1)));
  FChart.DispatchAction('{"type": "axisAreaSelect", "parallelAxisName": "b", "intervals": [[0, 1]]}');
  AssertEquals('by name', 1, Length(FChart.ParallelIntervals(1)));
  FChart.DispatchAction('{"type": "axisAreaSelect", "parallelAxisIndex": ["2", 1], "intervals": [[5, 6], [7, 8]]}');
  AssertEquals('an index as a numeric string', 2, Length(FChart.ParallelIntervals(2)));
  AssertEquals('and a number', 2, Length(FChart.ParallelIntervals(1)));
  FChart.DispatchAction('{"type": "axisAreaSelect", "intervals": []}');
  AssertEquals('no query is every axis', 0, Length(FChart.ParallelIntervals(0)));
  AssertEquals('every axis 1', 0, Length(FChart.ParallelIntervals(1)));
  AssertEquals('an axis on no parallel takes nothing', 0, Length(FChart.ParallelIntervals(3)));
  AssertTrue('the event goes out', FChart.Events.Count >= 4);
  AssertTrue('as axisareaselected', Pos('axisareaselected', FChart.Events[0]) = 1);
end;

procedure TAdvChartParallelTest.TestAProgressiveSeriesComesInChunks;
var
  sb: TStringBuilder;
  i, shown, hidden: Integer;
  el: TTyChartElement;
  list: TTyPaintList;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "parallelAxis": [{"dim": 0, "min": 0, "max": 100}, '
      + '{"dim": 1, "min": 0, "max": 100}], "series": {"type": "parallel", '
      + '"progressive": 20, "progressiveThreshold": 50, "data": [');
    for i := 0 to 59 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append('[' + IntToStr(i) + ', ' + IntToStr(60 - i) + ']');
    end;
    sb.Append(']}}');
    Show(sb.ToString, camOff);
  finally
    sb.Free;
  end;
  AssertTrue('unfinished after the first chunk', FChart.ProgressiveUnfinished);
  list := FChart.List;
  shown := 0;
  hidden := 0;
  for i := 0 to list.Count - 1 do
  begin
    el := list.Element(i);
    if el.Datum.SeriesIndex <> 0 then Continue;
    if el.ProgHidden then Inc(hidden) else Inc(shown);
  end;
  AssertEquals('the first chunk of rows is shown', 20, shown);
  AssertEquals('the rest wait', 40, hidden);
  { no enter clip on an incremental view }
  AssertTrue('no clip proxy', FChart.AnimFindProxy(0, -1, 'parallelClip') = nil);
end;

procedure TAdvChartParallelTest.TestAnExcludedParallelAxisIsNotDrawn;
begin
  Show('{"animation": false, "parallelAxis": [{"dim": 0}, {"dim": 1}], '
    + '"series": {"type": "parallel", "data": [[1, 2]]}}', camOff);
  AssertTrue('drawn', cvParallelAxis in FChart.Drawn);
  AssertEquals('the view name', 'parallelAxis', TyChartViewName(cvParallelAxis));
end;

procedure TAdvChartParallelTest.TestASeriesOnNoParallelSaysSo;
var
  i: Integer;
  found: Boolean;
begin
  Show('{"animation": false, "parallel": {}, "parallelAxis": [{"dim": 0}, {"dim": 1}], '
    + '"series": {"type": "parallel", "parallelIndex": 3, "data": [[1, 2]]}}', camOff);
  found := False;
  for i := 0 to FChart.DiagnosticCount - 1 do
    if Pos('parallel', FChart.Diagnostic(i)) > 0 then found := True;
  AssertTrue('a diagnostic names the coordinate system', found);
  AssertFalse('nothing solved', FChart.ParallelSolvedOf(0).Valid);
  { the default parallelIndex 0 wins over a parallelId }
  Show('{"animation": false, "parallel": [{"id": "x"}, {"id": "y"}], '
    + '"parallelAxis": [{"dim": 0}, {"dim": 0, "parallelIndex": 1}], '
    + '"series": {"type": "parallel", "parallelId": "y", "data": [[1]]}}', camOff);
  AssertEquals('parallelIndex 0', 0, FChart.ParallelSolvedOf(0).ParallelIndex);
  Show('{"animation": false, "parallel": [{"id": "x"}, {"id": "y"}], '
    + '"parallelAxis": [{"dim": 0}, {"dim": 0, "parallelIndex": 1}], '
    + '"series": {"type": "parallel", "parallelIndex": null, "parallelId": "y", "data": [[1]]}}', camOff);
  AssertEquals('parallelId once the index is null', 1, FChart.ParallelSolvedOf(0).ParallelIndex);
end;

procedure TAdvChartParallelTest.TestTheClipIsTheViewsFirstRenderOnly;
const
  cOpt = '{"legend": {}, "parallelAxis": [{"dim": 0}, {"dim": 1}], "series": ['
    + '{"type": "parallel", "name": "a", "data": [[1, 2], [2, 1]]}, '
    + '{"type": "parallel", "name": "b", "data": [[1, 1]]}]}';
var
  p: TTyChartAnimProxy;
  list: TTyPaintList;
  i: Integer;
  clipped: Boolean;
begin
  Show(cOpt, camAlways);
  p := FChart.AnimFindProxy(0, -1, 'parallelClip');
  AssertTrue('the first render clips', p <> nil);
  FChart.AnimTick(T0 + 400);
  RenderNow;
  p := FChart.AnimFindProxy(0, -1, 'parallelClip');
  AssertTrue('still growing', (p <> nil) and not p.AtFinal);
  AssertEquals('linear: 40% of the width', 440 * 0.4, p.Num('shape.width'), 1e-9);
  { the frame draws every row of the series through it }
  list := FChart.Frame;
  clipped := False;
  for i := 0 to list.Count - 1 do
    if (list.Element(i).Datum.SeriesIndex = 0) and list.Element(i).HasClip then
      clipped := True;
  AssertTrue('the frame clips the rows', clipped);
  { a merge in the middle: the kept view's clip runs on }
  FChart.SetOption('{"series": [{"data": [[1, 2], [2, 1], [1.5, 1.5]]}]}', False);
  RenderNow;
  FChart.AnimTick(T0 + 600);
  RenderNow;
  p := FChart.AnimFindProxy(0, -1, 'parallelClip');
  AssertTrue('carried through the merge', (p <> nil) and not p.AtFinal);
  FChart.AnimTick(T0 + 1200);
  RenderNow;
  p := FChart.AnimFindProxy(0, -1, 'parallelClip');
  AssertTrue('done', (p = nil) or p.AtFinal);
  { a legend hides and shows series b: its view is not new, no clip }
  FChart.DispatchAction('{"type": "legendToggleSelect", "name": "b"}');
  RenderNow;
  FChart.AnimTick(T0 + 1500);
  FChart.DispatchAction('{"type": "legendToggleSelect", "name": "b"}');
  RenderNow;
  { a tick into what would be a second clip's run: a proxy reads its final
    values until the clock moves [milestone C14-C22: without the tick a
    second clip passed as done] }
  FChart.AnimTick(T0 + 1600);
  RenderNow;
  p := FChart.AnimFindProxy(1, -1, 'parallelClip');
  AssertTrue('no second clip', (p = nil) or p.AtFinal);
  { and the frame draws series b's rows unclipped }
  list := FChart.Frame;
  clipped := False;
  for i := 0 to list.Count - 1 do
    if (list.Element(i).Datum.SeriesIndex = 1) and list.Element(i).HasClip then
      clipped := True;
  AssertFalse('the rows shown again are not clipped', clipped);
end;

initialization
  RegisterTest(TAdvChartParallelOracleTest);
  RegisterTest(TAdvChartParallelTest);
end.
