unit test.advchart.geoseries;
{$mode objfpc}{$H+}
{ THE MAP SERIES AND THE SERIES ON A GEO, HELD TO UPSTREAM [Batch 152, D14 GE4].

  tools/advchart-oracle/geo-series.js drives the real ECharts 6.1 build in
  node over small maps (seven regions with a hole, a line, a two-block
  multipolygon and an echartsStyle; two squares) and four gallery maps, and
  records after every step: the chart's mouse events and its select, roam,
  legend and brush events (as JSON text), the tooltip, every map picture --
  a geo component's, or a map series' own geo -- with its view, every region
  group's data index, hover and selection and every path's state list, ink,
  z2 and text; and per series the legend symbols of a map series, the points
  of a scatter and an effectScatter, the lines' points, the pies' centres
  and radii, the graph's nodes, the custom series' renderItem calls and the
  heatmap layer's coloured bytes.

  This replays the same steps through the control's own pointer path and
  DispatchAction / SetOption, paints after each step, and compares all of
  it bit for bit. }
interface
uses Classes, SysUtils, Math, Types, fpcunit, testregistry, fpjson, jsonparser, base64,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits, tyControls.Types, tyControls.StyleModel,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Handlers, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart.Style, tyControls.AdvanceChart.States, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Tooltip, tyControls.AdvanceChart.Graph,
     tyControls.AdvanceChart.Lines, tyControls.AdvanceChart.Custom,
     tyControls.AdvanceChart.Convert, tyControls.AdvanceChart.VisualMap,
     tyControls.AdvanceChart.Geo, tyControls.AdvanceChart.HeatLayer,
     tyControls.AdvanceChart;
type
  TGsProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Move(AX, AY: Integer);
    procedure Down(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    function Wheel(AX, AY, ADelta: Integer): Boolean;
    procedure Leave;
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
  end;

  { the chart's events as lines, and the renderItems the options name }
  TGsLog = class
  public
    Lines: TStringList;
    Calls: TStringList;
    CoordSys: string;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
    function GeoRect(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function GeoSeg(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  TAdvChartGeoSeriesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGsProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FLog: TGsLog;
    FInk: TTyGeoInk;
    FW, FH: Integer;
    FBad, FCompared: Integer;
    { how much of each kind was compared: the heat bytes, the map regions,
      the symbols of the series on a geo }
    FHeatBytes, FRegions, FPoints: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameColour(const AWhat: string; AHas: Boolean; AGot: TTyChartColor;
      AWant: TJSONData);
    procedure Finish(const AWhat: string; AMin: Integer);
    procedure NewChart(const AOption: string);
    procedure Paint;
    procedure RegisterMaps;
    procedure Step(AStep: TJSONObject);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareTip(AWant: TJSONData);
    procedure CompareDraw(AWant: TJSONObject);
    procedure CompareSeries(ASeries: Integer; AWant: TJSONObject);
    procedure CompareCustom(AWant: TJSONData);
    procedure CompareHeat(AState: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryStepAsUpstream;
  end;

  TAdvChartGeoSeriesTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGsProbe;
    FBmp: TBGRABitmap;
    procedure NewChart(const AOption: string);
    procedure Paint;
    function PixelAt(AX, AY: Double): TBGRAPixel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheHeatLayerPieces;
    procedure TestAMapSeriesIsPaintedInItsInk;
    procedure TestASeriesOnAGeoFollowsARoamBeforeAPaint;
    procedure TestAMapNobodyRegisteredDrawsNothing;
    procedure TestTheLegacySelectActionsSelect;
    procedure TestAMapSeriesIsAlwaysOnAGeo;
    procedure TestTheGalleryGeoFilesDraw;
  end;

implementation

{ ==================== the probe ==================== }

procedure TGsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TGsProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TGsProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TGsProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TGsProbe.Wheel(AX, AY, ADelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TGsProbe.Leave;
begin
  MouseLeave;
end;

function TGsProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

{ ==================== helpers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-geo-series.json';
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

{ a JSON text as fpjson writes it back: the two sides compared in one form }
function JsonForm(const AText: string): string;
var d: TJSONData;
begin
  d := GetJSON(AText);
  try
    Result := d.AsJSON;
  finally
    d.Free;
  end;
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

{ the skin's ink, as the control resolves it }
function InkOf(ACtl: TTyStyleController): TTyGeoInk;
var st: TTyStyleSet;
begin
  Result := Default(TTyGeoInk);
  st := ACtl.Model.ResolveStyle('TyAdvChartGeoArea', '', []);
  Result.AreaFill := TTyChartColor(st.Background.Color);
  Result.Border := TTyChartColor(st.BorderColor);
  st := ACtl.Model.ResolveStyle('TyAdvChartGeoLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  st := ACtl.Model.ResolveStyle('TyAdvChartGeoArea', '', [tysHover]);
  Result.HighlightFill := TTyChartColor(st.Background.Color);
  st := ACtl.Model.ResolveStyle('TyAdvChartGeoLabel', '', [tysHover]);
  Result.LabelHighlight := TTyChartColor(st.TextColor);
  st := ACtl.Model.ResolveStyle('TyAdvChartMapArea', '', []);
  Result.MapAreaFill := TTyChartColor(st.Background.Color);
end;

{ ==================== the log ==================== }

constructor TGsLog.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
  Calls := TStringList.Create;
end;

destructor TGsLog.Destroy;
begin
  Lines.Free;
  Calls.Free;
  inherited Destroy;
end;

procedure TGsLog.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var p: TTyChartCallbackParams;
begin
  if AEvent.Payload <> '' then
  begin
    Lines.Add(AEvent.EventType + '|' + JsonForm(AEvent.Payload));
    Exit;
  end;
  p := AEvent.Params;
  Lines.Add(Format('%s|%s|%d|%d|%s', [AEvent.EventType, p.ComponentType, p.SeriesIndex,
    p.DataIndex, p.Name]));
end;

function CoordSysText(const AParams: TTyCustomParams): string;
begin
  Result := Format('%s|%s|%s|%s|%s|%s', [AParams.CoordSys.Type_, HexOf(AParams.CoordSys.X),
    HexOf(AParams.CoordSys.Y), HexOf(AParams.CoordSys.Width), HexOf(AParams.CoordSys.Height),
    HexOf(AParams.CoordSys.Zoom)]);
end;

{ RENDER.geoRect: a rect two by one degrees round each point }
function TGsLog.GeoRect(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var v0, v1: Double; p, s: TTyDoubleArray;
begin
  v0 := AApi.Value(0);
  v1 := AApi.Value(1);
  p := AApi.Coord([v0, v1]);
  s := AApi.Size([2, 1], [v0, v1]);
  Calls.Add(Format('%d|coord %s %s -> %s %s|size %s %s -> %s %s', [AParams.DataIndex,
    HexOf(v0), HexOf(v1), HexOf(p[0]), HexOf(p[1]), HexOf(v0), HexOf(v1), HexOf(s[0]),
    HexOf(s[1])]));
  CoordSys := CoordSysText(AParams);
  Result := TJSONObject.Create(['type', 'rect', 'shape', TJSONObject.Create([
    'x', p[0] - s[0] / 2, 'y', p[1] - s[1] / 2, 'width', s[0], 'height', s[1]]),
    'style', TJSONObject.Create(['fill', AApi.Visual('color')])]);
end;

{ RENDER.geoSeg: a line between two pairs }
function TGsLog.GeoSeg(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var a, b: TTyDoubleArray; v0, v1, v2, v3: Double;
begin
  v0 := AApi.Value(0);
  v1 := AApi.Value(1);
  v2 := AApi.Value(2);
  v3 := AApi.Value(3);
  a := AApi.Coord([v0, v1]);
  b := AApi.Coord([v2, v3]);
  Calls.Add(Format('%d|coord %s %s -> %s %s', [AParams.DataIndex, HexOf(v0), HexOf(v1),
    HexOf(a[0]), HexOf(a[1])]));
  Calls.Add(Format('%d|coord %s %s -> %s %s', [AParams.DataIndex, HexOf(v2), HexOf(v3),
    HexOf(b[0]), HexOf(b[1])]));
  CoordSys := CoordSysText(AParams);
  Result := TJSONObject.Create(['type', 'line', 'shape', TJSONObject.Create([
    'x1', a[0], 'y1', a[1], 'x2', b[0], 'y2', b[1]]),
    'style', TJSONObject.Create(['stroke', '#333', 'lineWidth', 2])]);
end;

{ ==================== the oracle ==================== }

procedure TAdvChartGeoSeriesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FLog := TGsLog.Create;
  TyChartRegisterRenderItem('geoRect', @FLog.GeoRect);
  TyChartRegisterRenderItem('geoSeg', @FLog.GeoSeg);
  FInk := InkOf(FCtl);
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FWhere := '';
end;

procedure TAdvChartGeoSeriesOracleTest.TearDown;
begin
  TyChartUnregisterRenderItem('geoRect');
  TyChartUnregisterRenderItem('geoSeg');
  TyChartClearMaps;
  FChart.Free;
  FLog.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  FRoot.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoSeriesOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 200000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartGeoSeriesOracleTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not ((HexOf(AGot) = AHex) or (IsNan(AGot) and IsNan(FromHex(AHex)))) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartGeoSeriesOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoSeriesOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoSeriesOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True),
    BoolToStr(AWant, True)]));
end;

{ upstream's colour string as the port must hold it: a token is the skin's
  ink, a token's lift its lift }
procedure TAdvChartGeoSeriesOracleTest.SameColour(const AWhat: string;
  AHas: Boolean; AGot: TTyChartColor; AWant: TJSONData);
var
  tok: TJSONObject;
  s: string;
  want: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AWant) or (AWant.AsString = 'none') then
  begin
    if AHas then Bad(AWhat + ': a colour, upstream none');
    Exit;
  end;
  if not AHas then
  begin
    Bad(AWhat + ': no colour, upstream ' + AWant.AsString);
    Exit;
  end;
  s := AWant.AsString;
  tok := TJSONObject(FRoot).Objects['tokens'];
  if s = tok.Strings['area'] then want := FInk.AreaFill
  else if s = tok.Strings['mapArea'] then want := FInk.MapAreaFill
  else if s = tok.Strings['border'] then want := FInk.Border
  else if s = tok.Strings['label'] then want := FInk.LabelColour
  else if s = tok.Strings['highlight'] then want := FInk.HighlightFill
  else if s = tok.Strings['labelHighlight'] then want := FInk.LabelHighlight
  else if s = tok.Strings['liftedArea'] then want := TyChartLiftColor(FInk.AreaFill)
  else if s = tok.Strings['liftedMapArea'] then want := TyChartLiftColor(FInk.MapAreaFill)
  else if s = tok.Strings['liftedBorder'] then want := TyChartLiftColor(FInk.Border)
  else if s = tok.Strings['liftedHighlight'] then want := TyChartLiftColor(FInk.HighlightFill)
  else if not TyTryParseChartColor(s, want) then
  begin
    Bad(AWhat + ': upstream''s colour does not parse: ' + s);
    Exit;
  end;
  if AGot <> want then
    Bad(Format('%s %s, upstream %s (%s)', [AWhat, IntToHex(AGot, 8), IntToHex(want, 8), s]));
end;

procedure TAdvChartGeoSeriesOracleTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartGeoSeriesOracleTest.RegisterMaps;
var maps: TJSONArray; i: Integer; sp: string; d: TJSONData;
begin
  TyChartClearMaps;
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
  begin
    sp := '';
    d := maps.Objects[i].Find('special');
    if not IsNull(d) then sp := d.AsJSON;
    AssertTrue('registered', TyChartRegisterMap(maps.Objects[i].Strings['name'],
      maps.Objects[i].Strings['text'], sp));
  end;
end;

procedure TAdvChartGeoSeriesOracleTest.NewChart(const AOption: string);
const
  cTypes: array[0..7] of string = ('click', 'mouseover', 'mouseout', 'mousemove',
    'georoam', 'selectchanged', 'legendselectchanged', 'geoselectchanged');
var i: Integer;
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(FW, FH, BGRA(255, 255, 255, 255));
  FChart := TGsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.TooltipNow := 0;
  for i := 0 to High(cTypes) do FChart.ChartOn(cTypes[i], @FLog.Handle);
  { brushselected where the option has a brush: upstream's visual stage
    fires an empty one on many an update otherwise }
  if Pos('"brush"', AOption) > 0 then FChart.ChartOn('brushselected', @FLog.Handle);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, FW, FH);
  Paint;
end;

procedure TAdvChartGeoSeriesOracleTest.Paint;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, FW, FH), 96);
end;

procedure TAdvChartGeoSeriesOracleTest.Step(AStep: TJSONObject);
var a, q: TJSONArray; k: Integer; d: TJSONData;
begin
  if AStep.Find('move') <> nil then
  begin
    a := AStep.Arrays['move'];
    FChart.Move(a.Integers[0], a.Integers[1]);
  end
  else if AStep.Find('click') <> nil then
  begin
    a := AStep.Arrays['click'];
    FChart.Move(a.Integers[0], a.Integers[1]);
    FChart.Down(a.Integers[0], a.Integers[1]);
    FChart.Up(a.Integers[0], a.Integers[1]);
  end
  else if AStep.Find('drag') <> nil then
  begin
    a := AStep.Arrays['drag'];
    q := a.Arrays[0];
    FChart.Move(q.Integers[0], q.Integers[1]);
    FChart.Down(q.Integers[0], q.Integers[1]);
    for k := 1 to a.Count - 1 do
    begin
      q := a.Arrays[k];
      FChart.Move(q.Integers[0], q.Integers[1]);
    end;
    q := a.Arrays[a.Count - 1];
    FChart.Up(q.Integers[0], q.Integers[1]);
  end
  else if AStep.Find('wheel') <> nil then
  begin
    a := AStep.Arrays['wheel'];
    FChart.Wheel(a.Integers[0], a.Integers[1], a.Integers[2]);
  end
  else if AStep.Find('leave') <> nil then
    FChart.Leave
  else if AStep.Find('action') <> nil then
    FChart.DispatchAction(AStep.Objects['action'].AsJSON)
  else if AStep.Find('setOption') <> nil then
  begin
    d := AStep.Find('notMerge');
    FChart.SetOption(AStep.Objects['setOption'].AsJSON, (d <> nil) and d.AsBoolean);
  end
  else
    Fail('an unknown step');
  Paint;
end;

procedure TAdvChartGeoSeriesOracleTest.CompareEvents(AWant: TJSONArray);
var
  want: TStringList;
  i: Integer;
  e: TJSONObject;

  function S(AKey: string): string;
  begin
    if IsNull(e.Find(AKey)) then Result := '' else Result := e.Find(AKey).AsString;
  end;

  function N(AKey: string): Integer;
  begin
    if IsNull(e.Find(AKey)) then Result := -1 else Result := e.Integers[AKey];
  end;

begin
  want := TStringList.Create;
  try
    for i := 0 to AWant.Count - 1 do
    begin
      e := AWant.Objects[i];
      if e.Find('json') <> nil then
        want.Add(e.Strings['type'] + '|' + JsonForm(e.Strings['json']))
      else
        want.Add(Format('%s|%s|%d|%d|%s', [e.Strings['type'], S('componentType'),
          N('seriesIndex'), N('dataIndex'), S('name')]));
    end;
    SameInt('events', FLog.Lines.Count, want.Count);
    for i := 0 to Min(want.Count, FLog.Lines.Count) - 1 do
      SameStr(Format('event %d', [i]), FLog.Lines[i], want[i]);
    if FLog.Lines.Count <> want.Count then
      Bad('the events: ' + StringReplace(FLog.Lines.Text, LineEnding, ' ; ', [rfReplaceAll])
        + ' upstream: ' + StringReplace(want.Text, LineEnding, ' ; ', [rfReplaceAll]));
  finally
    want.Free;
  end;
  FLog.Lines.Clear;
end;

{ ---- the tooltip's rows ---- }

type
  TGsRow = record
    Marker, Name, Value: string;
    HasMarker, HasName, HasValue: Boolean;
  end;
  TGsRows = array of TGsRow;

function RowsOf(ABlock: TTyTooltipBlock): TGsRows;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j, n: Integer;
  row: TGsRow;
begin
  Result := nil;
  if ABlock = nil then Exit;
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  n := 0;
  for i := 0 to High(lines) do
  begin
    row := Default(TGsRow);
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
      else
      begin
        row.HasName := True;
        row.Name := lines[i].Runs[j].Text;
      end;
    SetLength(Result, n + 1);
    Result[n] := row;
    Inc(n);
  end;
end;

function RowText(const R: TGsRow): string;
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
    if IsNull(d) then Result := 'null'
    else Result := '"' + d.AsString + '"';
  end;
begin
  Result := '{' + Q('marker') + ' ' + Q('name') + ' ' + Q('value') + '}';
end;

procedure TAdvChartGeoSeriesOracleTest.CompareTip(AWant: TJSONData);
var
  rows: TJSONArray;
  block: TTyTooltipBlock;
  got: TGsRows;
  j: Integer;
begin
  if IsNull(AWant) then
  begin
    SameBool('tooltip shown', FChart.TooltipShown, False);
    Exit;
  end;
  SameBool('tooltip shown', FChart.TooltipShown, True);
  if not FChart.TooltipShown then Exit;
  if TJSONObject(AWant).Find('text') <> nil then
  begin
    SameStr('tooltip text', FChart.TooltipFormatterText, TJSONObject(AWant).Strings['text']);
    Exit;
  end;
  rows := TJSONObject(AWant).Arrays['rows'];
  block := FChart.ContentOf(FChart.TooltipShownDatum);
  try
    got := RowsOf(block);
  finally
    block.Free;
  end;
  SameInt('tooltip rows', Length(got), rows.Count);
  for j := 0 to Min(rows.Count, Length(got)) - 1 do
    SameStr(Format('tooltip row %d', [j]), RowText(got[j]), WantRowText(rows.Objects[j]));
end;

{ one map picture: the view, then every region group and path in MapDraw's
  order, the elements the build put down for it }
procedure TAdvChartGeoSeriesOracleTest.CompareDraw(AWant: TJSONObject);
var
  owner, where, text: string;
  geo: TTyGeo;
  idx, g, k, j, start, count: Integer;
  dr: TTyGeoDraw;
  groups, paths, arr: TJSONArray;
  grp, pw, lw, ds: TJSONObject;
  flags: TTyGeoGroupSt;
  it: TTyStItem;
  p: TTyGeoDrawPath;
  el: TTyChartElement;
  data: TTyGeoData;
  d: TJSONData;

  function NextEl(out AEl: TTyChartElement): Boolean;
  begin
    Result := j < start + count;
    if Result then
    begin
      AEl := FChart.List.Element(j);
      Inc(j);
    end
    else
      Bad(where + ': no element left');
  end;

begin
  owner := AWant.Strings['owner'];
  idx := StrToInt(Copy(owner, Pos(' ', owner) + 1, MaxInt));
  if Copy(owner, 1, 3) = 'geo' then geo := FChart.GeoLayout(idx)
  else geo := FChart.MapGeoOf(idx);
  where := owner;
  Inc(FCompared);
  if geo = nil then
  begin
    Bad(owner + ': no geo');
    Exit;
  end;
  arr := AWant.Arrays['overall'];
  for k := 0 to 5 do Same(where + Format(' overall[%d]', [k]), geo.MtOverall[k], arr.Strings[k]);
  arr := AWant.Arrays['view'];
  Same(where + ' view x', geo.ViewRect.X, arr.Strings[0]);
  Same(where + ' view y', geo.ViewRect.Y, arr.Strings[1]);
  Same(where + ' view w', geo.ViewRect.W, arr.Strings[2]);
  Same(where + ' view h', geo.ViewRect.H, arr.Strings[3]);
  if not FChart.GeoDrawRange(geo, start, count) then
  begin
    Bad(owner + ': not drawn');
    Exit;
  end;
  j := start;
  dr := geo.LastDraw;
  data := geo.Data;
  groups := AWant.Arrays['groups'];
  SameInt(where + ' groups', Length(dr.Groups), groups.Count);
  for g := 0 to Min(groups.Count, Length(dr.Groups)) - 1 do
  begin
    grp := groups.Objects[g];
    Inc(FRegions);
    where := Format('%s %s', [owner, grp.Get('name', '?')]);
    SameStr(where + ' name', dr.Groups[g].Name, grp.Get('name', ''));
    d := grp.Find('ds');
    if IsNull(d) then
      SameBool(where + ' the series'' data', data.Active, False)
    else
    begin
      ds := TJSONObject(d);
      SameBool(where + ' the series'' data', data.Active, True);
      if data.Active and (g <= High(data.Groups)) then
      begin
        SameInt(where + ' series', data.SeriesIndex, ds.Integers['s']);
        SameInt(where + ' data index', data.Groups[g].Row, ds.Integers['d']);
      end;
    end;
    flags := geo.GroupFlags(g);
    SameInt(where + ' hover', flags.Hover, grp.Integers['hover']);
    SameBool(where + ' selected', flags.Selected, grp.Booleans['selected']);
    paths := grp.Arrays['paths'];
    SameInt(where + ' paths', Length(dr.Groups[g].Paths), paths.Count);
    for k := 0 to Min(paths.Count, Length(dr.Groups[g].Paths)) - 1 do
    begin
      pw := paths.Objects[k];
      p := dr.Groups[g].Paths[k];
      it := geo.PathItem(g, k);
      where := Format('%s %s path %d', [owner, grp.Get('name', '?'), k]);
      SameStr(where + ' states', TyStNamesText(it.Host.States), pw.Strings['states']);
      if Length(p.Drawn) > 0 then
      begin
        if not NextEl(el) then Exit;
        SameColour(where + ' fill', el.Style.HasFill, el.Style.FillColor, pw.Find('fill'));
        SameColour(where + ' stroke', el.Style.StrokeWidthLogical > 0, el.Style.StrokeColor,
          pw.Find('stroke'));
        if not IsNull(pw.Find('lw')) then
          Same(where + ' lineWidth', it.Host.Cur.Num[stkLineWidth], pw.Strings['lw']);
        if not IsNull(pw.Find('opacity')) then
          Same(where + ' opacity', el.Style.Alpha, pw.Strings['opacity']);
        SameInt(where + ' z2', el.Z2, pw.Integers['z2']);
      end;
      d := pw.Find('label');
      SameBool(where + ' a text', p.Lbl.Exists, not IsNull(d));
      if IsNull(d) or not p.Lbl.Exists or not p.Lbl.HasPos then Continue;
      lw := TJSONObject(d);
      where := where + ' text';
      if not NextEl(el) then Exit;
      SameBool(where + ' ignore', el.Ignore, lw.Booleans['ignore']);
      text := '';
      if not IsNull(lw.Find('text')) then text := lw.Strings['text'];
      SameStr(where + ' words', el.Caption.Text, text);
      if not lw.Booleans['ignore'] then
        SameColour(where + ' ink', True, el.Caption.Colour, lw.Find('fill'));
      if not IsNull(lw.Find('tx')) then
      begin
        Same(where + ' x', el.Caption.X, lw.Strings['tx']);
        Same(where + ' y', el.Caption.Y, lw.Strings['ty']);
      end;
    end;
  end;
  SameInt(owner + ' elements', j - start, count);
end;

procedure TAdvChartGeoSeriesOracleTest.CompareSeries(ASeries: Integer; AWant: TJSONObject);
var
  t, where: string;
  items, arr, pts: TJSONArray;
  i, k, n, start, count, ripples: Integer;
  it: TJSONObject;
  el, found: TTyChartElement;
  has, lbl: Boolean;
  st: TTyStItem;
  sol: TTyLinesSolved;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  lst: TTyPaintList;
  d: TJSONData;
begin
  t := AWant.Strings['type'];
  lst := FChart.List;
  where := Format('series %d (%s)', [ASeries, t]);
  if t = 'map' then
  begin
    items := AWant.Arrays['symbols'];
    if not FChart.MapSymbolRange(ASeries, start, count) then
    begin
      SameInt(where + ' symbols', 0, items.Count);
      Exit;
    end;
    k := start;
    n := 0;
    for i := 0 to items.Count - 1 do
    begin
      it := items.Objects[i];
      if k >= start + count then
      begin
        Bad(where + Format(': symbol %d missing', [i]));
        Break;
      end;
      el := lst.Element(k);
      Inc(k);
      Inc(n);
      Same(where + Format(' symbol %d cx', [i]), el.Shape.CX, it.Strings['cx']);
      Same(where + Format(' symbol %d cy', [i]), el.Shape.CY, it.Strings['cy']);
      SameInt(where + Format(' symbol %d z2', [i]), el.Z2, it.Integers['z2']);
      d := it.Find('label');
      lbl := (k < start + count) and (lst.Element(k).Caption.FontSizeLogical > 0);
      SameBool(where + Format(' symbol %d label', [i]), lbl, not IsNull(d));
      if IsNull(d) or not lbl then Continue;
      el := lst.Element(k);
      Inc(k);
      SameBool(where + Format(' symbol %d label ignore', [i]), el.Ignore,
        TJSONObject(d).Booleans['ignore']);
      SameStr(where + Format(' symbol %d label text', [i]), el.Caption.Text,
        TJSONObject(d).Get('text', ''));
      if not IsNull(TJSONObject(d).Find('tx')) then
      begin
        Same(where + Format(' symbol %d label x', [i]), el.Caption.X, TJSONObject(d).Strings['tx']);
        Same(where + Format(' symbol %d label y', [i]), el.Caption.Y, TJSONObject(d).Strings['ty']);
      end;
    end;
    SameInt(where + ' symbol elements', k - start, count);
    Exit;
  end;
  if (t = 'scatter') or (t = 'effectScatter') then
  begin
    items := AWant.Arrays['items'];
    for i := 0 to items.Count - 1 do
    begin
      it := items.Objects[i];
      has := False;
      ripples := 0;
      found := Default(TTyChartElement);
      for k := 0 to lst.Count - 1 do
      begin
        el := lst.Element(k);
        if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> ASeries)
          or (el.Datum.DataIndex <> i) or (el.Caption.FontSizeLogical > 0) then Continue;
        if el.Silent then
        begin
          if el.Z2 = 99 then Inc(ripples);
          Continue;
        end;
        if not has then found := el;
        has := True;
      end;
      SameBool(where + Format(' item %d drawn', [i]), has, it.Booleans['el']);
      if not (has and it.Booleans['el']) then Continue;
      Inc(FPoints);
      Same(where + Format(' item %d x', [i]), found.Shape.CX, it.Arrays['p'].Strings[0]);
      Same(where + Format(' item %d y', [i]), found.Shape.CY, it.Arrays['p'].Strings[1]);
      if not IsNull(it.Find('z2')) then SameInt(where + Format(' item %d z2', [i]), found.Z2,
        it.Integers['z2']);
      if FChart.ItemStates(ASeries, i, st) then
        SameStr(where + Format(' item %d states', [i]), TyStNamesText(st.Host.States),
          it.Get('states', ''));
      if not IsNull(it.Find('ripples')) then
        SameInt(where + Format(' item %d ripples', [i]), ripples, it.Integers['ripples']);
    end;
    Exit;
  end;
  if t = 'lines' then
  begin
    sol := FChart.LinesSolvedOf(ASeries);
    items := AWant.Arrays['items'];
    SameInt(where + ' rows', Length(sol.Geoms), items.Count);
    for i := 0 to Min(items.Count, Length(sol.Geoms)) - 1 do
    begin
      it := items.Objects[i];
      SameBool(where + Format(' row %d drawn', [i]), sol.Geoms[i].Drawn, it.Booleans['el']);
      if IsNull(it.Find('pts')) then Continue;
      pts := it.Arrays['pts'];
      n := Length(sol.Geoms[i].Pts);
      if sol.Geoms[i].Curved then Inc(n);
      SameInt(where + Format(' row %d points', [i]), n, pts.Count);
      for k := 0 to Min(pts.Count, Length(sol.Geoms[i].Pts)) - 1 do
      begin
        Same(where + Format(' row %d pt %d x', [i, k]), sol.Geoms[i].Pts[k].X, pts.Arrays[k].Strings[0]);
        Same(where + Format(' row %d pt %d y', [i, k]), sol.Geoms[i].Pts[k].Y, pts.Arrays[k].Strings[1]);
      end;
      if sol.Geoms[i].Curved and (pts.Count = Length(sol.Geoms[i].Pts) + 1) then
      begin
        Same(where + Format(' row %d cp x', [i]), sol.Geoms[i].CP.X, pts.Arrays[pts.Count - 1].Strings[0]);
        Same(where + Format(' row %d cp y', [i]), sol.Geoms[i].CP.Y, pts.Arrays[pts.Count - 1].Strings[1]);
      end;
    end;
    Exit;
  end;
  if t = 'pie' then
  begin
    items := AWant.Arrays['items'];
    for i := 0 to items.Count - 1 do
    begin
      it := items.Objects[i];
      has := False;
      for k := 0 to lst.Count - 1 do
      begin
        el := lst.Element(k);
        if (el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex = ASeries)
          and (el.Datum.DataIndex = i) and (el.Shape.Kind = cskSector) then
        begin
          found := el;
          has := True;
          Break;
        end;
      end;
      Inc(FCompared);
      if not has then
      begin
        Bad(where + Format(': sector %d not drawn', [i]));
        Continue;
      end;
      Same(where + Format(' sector %d cx', [i]), found.Shape.CX, it.Strings['cx']);
      Same(where + Format(' sector %d cy', [i]), found.Shape.CY, it.Strings['cy']);
      Same(where + Format(' sector %d r0', [i]), found.Shape.R0, it.Strings['r0']);
      Same(where + Format(' sector %d r', [i]), found.Shape.R1, it.Strings['r']);
    end;
    Exit;
  end;
  if t = 'graph' then
  begin
    items := AWant.Arrays['nodes'];
    Inc(FCompared);
    if not FChart.GraphLayout(ASeries, nodes, edges, fills) then
    begin
      Bad(where + ': not laid out');
      Exit;
    end;
    SameInt(where + ' nodes', Length(nodes), items.Count);
    for i := 0 to Min(items.Count, Length(nodes)) - 1 do
    begin
      it := items.Objects[i];
      if IsNull(it.Find('p')) then Continue;
      Same(where + Format(' node %d x', [i]), nodes[i].PX, it.Arrays['p'].Strings[0]);
      Same(where + Format(' node %d y', [i]), nodes[i].PY, it.Arrays['p'].Strings[1]);
    end;
    Exit;
  end;
  if t = 'heatmap' then Exit;
  if t = 'custom' then Exit;
end;

procedure TAdvChartGeoSeriesOracleTest.CompareCustom(AWant: TJSONData);
var
  calls: TJSONArray;
  c, cs: TJSONObject;
  want: TStringList;
  i: Integer;
begin
  if IsNull(AWant) then
  begin
    SameInt('renderItem calls', FLog.Calls.Count, 0);
    FLog.Calls.Clear;
    Exit;
  end;
  want := TStringList.Create;
  try
    calls := TJSONObject(AWant).Arrays['calls'];
    for i := 0 to calls.Count - 1 do
    begin
      c := calls.Objects[i];
      if c.Find('size') <> nil then
        want.Add(Format('%d|coord %s %s -> %s %s|size %s %s -> %s %s', [c.Integers['i'],
          c.Arrays['coord'].Arrays[0].Strings[0], c.Arrays['coord'].Arrays[0].Strings[1],
          c.Arrays['coord'].Arrays[1].Strings[0], c.Arrays['coord'].Arrays[1].Strings[1],
          c.Arrays['size'].Arrays[0].Strings[2], c.Arrays['size'].Arrays[0].Strings[3],
          c.Arrays['size'].Arrays[1].Strings[0], c.Arrays['size'].Arrays[1].Strings[1]]))
      else
        want.Add(Format('%d|coord %s %s -> %s %s', [c.Integers['i'],
          c.Arrays['coord'].Arrays[0].Strings[0], c.Arrays['coord'].Arrays[0].Strings[1],
          c.Arrays['coord'].Arrays[1].Strings[0], c.Arrays['coord'].Arrays[1].Strings[1]]));
    end;
    SameInt('renderItem calls', FLog.Calls.Count, want.Count);
    for i := 0 to Min(want.Count, FLog.Calls.Count) - 1 do
      SameStr(Format('renderItem call %d', [i]), FLog.Calls[i], want[i]);
    if not IsNull(TJSONObject(AWant).Find('coordSys')) then
    begin
      cs := TJSONObject(AWant).Objects['coordSys'];
      SameStr('coordSys', FLog.CoordSys, Format('%s|%s|%s|%s|%s|%s', [cs.Strings['type'],
        cs.Strings['x'], cs.Strings['y'], cs.Strings['width'], cs.Strings['height'],
        cs.Strings['zoom']]));
    end;
  finally
    want.Free;
  end;
  FLog.Calls.Clear;
end;

{ the heatmap layer: the image's rect, every drawImage (the brush's corner
  and the point's alpha), and the coloured bytes }
procedure TAdvChartGeoSeriesOracleTest.CompareHeat(AState: TJSONObject);
var
  series, heat, draws, img: TJSONArray;
  k, i, nbad: Integer;
  lay: TTyHeatLayer;
  want: TJSONObject;
  raw: string;
begin
  series := AState.Arrays['series'];
  for k := 0 to series.Count - 1 do
  begin
    if IsNull(series.Items[k]) or (series.Objects[k].Strings['type'] <> 'heatmap') then Continue;
    Inc(FCompared);
    if not FChart.GeoHeatLayer(k, lay) then
    begin
      Bad(Format('series %d: no heatmap layer', [k]));
      Continue;
    end;
    img := series.Objects[k].Arrays['img'];
    Same('heat image x', lay.X, img.Strings[0]);
    Same('heat image y', lay.Y, img.Strings[1]);
    Same('heat image w', lay.W, img.Strings[2]);
    Same('heat image h', lay.H, img.Strings[3]);
    if IsNull(AState.Find('heat')) then Continue;
    heat := AState.Arrays['heat'];
    want := heat.Objects[heat.Count - 1];
    draws := want.Arrays['draws'];
    SameInt('heat draws', Length(lay.DrawX), draws.Count);
    for i := 0 to Min(draws.Count, Length(lay.DrawX)) - 1 do
    begin
      Same(Format('heat draw %d x', [i]), lay.DrawX[i], draws.Arrays[i].Strings[0]);
      Same(Format('heat draw %d y', [i]), lay.DrawY[i], draws.Arrays[i].Strings[1]);
      Same(Format('heat draw %d alpha', [i]), lay.DrawAlpha[i], draws.Arrays[i].Strings[2]);
    end;
    raw := DecodeStringBase64(want.Strings['px']);
    SameInt('heat bytes', Length(lay.Bytes), Length(raw));
    nbad := 0;
    for i := 0 to Min(Length(raw), Length(lay.Bytes)) - 1 do
    begin
      Inc(FCompared);
      Inc(FHeatBytes);
      if lay.Bytes[i] <> Ord(raw[i + 1]) then
      begin
        Inc(nbad);
        if nbad <= 8 then
          Bad(Format('heat byte %d (pixel %d channel %d) %d, upstream %d', [i, i div 4,
            i mod 4, lay.Bytes[i], Ord(raw[i + 1])]));
      end;
    end;
    if nbad > 8 then Bad(Format('heat: %d bytes differ in all', [nbad]));
  end;
end;

procedure TAdvChartGeoSeriesOracleTest.RunCase(ACase: TJSONObject);
var
  steps, states, draws, series, conv, got: TJSONArray;
  st, cv, want: TJSONObject;
  i, k: Integer;
  r: TTyConvertResult;
  d: TJSONData;
begin
  RegisterMaps;
  FW := ACase.Integers['W'];
  FH := ACase.Integers['H'];
  FWhere := ACase.Strings['id'];
  FLog.Calls.Clear;
  FLog.CoordSys := '';
  NewChart(ACase.Objects['option'].AsJSON);
  states := ACase.Arrays['states'];
  steps := ACase.Arrays['steps'];
  for i := 0 to states.Count - 1 do
  begin
    FWhere := Format('%s state %d', [ACase.Strings['id'], i]);
    if i > 0 then Step(steps.Objects[i - 1]);
    st := states.Objects[i];
    CompareEvents(st.Arrays['events']);
    CompareTip(st.Find('tip'));
    draws := st.Arrays['draws'];
    for k := 0 to draws.Count - 1 do CompareDraw(draws.Objects[k]);
    series := st.Arrays['series'];
    for k := 0 to series.Count - 1 do
      if not IsNull(series.Items[k]) then CompareSeries(k, series.Objects[k]);
    CompareCustom(st.Find('custom'));
    CompareHeat(st);
    { convertToPixel / convertFromPixel by a series finder, at the start }
    if i = 0 then
    begin
      conv := ACase.Arrays['convert'];
      d := st.Find('convert');
      for k := 0 to conv.Count - 1 do
      begin
        cv := conv.Objects[k];
        want := TJSONArray(d).Objects[k];
        if cv.Find('value') <> nil then
        begin
          r := FChart.ConvertToPixelData(cv.Objects['finder'], cv.Find('value'));
          d := want.Find('to');
        end
        else
        begin
          r := FChart.ConvertFromPixelData(cv.Objects['finder'], cv.Find('pixel'));
          d := want.Find('from');
        end;
        SameBool(Format('convert %d answers', [k]), r.Kind = cvkArray, not IsNull(d));
        if (r.Kind = cvkArray) and not IsNull(d) and (Length(r.Values) >= 2) then
        begin
          got := TJSONArray(d);
          Same(Format('convert %d x', [k]), r.Values[0], got.Strings[0]);
          Same(Format('convert %d y', [k]), r.Values[1], got.Strings[1]);
        end;
        d := st.Find('convert');
      end;
    end;
  end;
end;

procedure TAdvChartGeoSeriesOracleTest.TestEveryStepAsUpstream;
var cases: TJSONArray; c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  AssertTrue('cases', cases.Count >= 20);
  FHeatBytes := 0;
  FRegions := 0;
  FPoints := 0;
  for c := 0 to cases.Count - 1 do RunCase(cases.Objects[c]);
  Finish('every step', 5000);
  AssertTrue(Format('heat bytes compared: %d', [FHeatBytes]), FHeatBytes > 50000);
  AssertTrue(Format('region groups compared: %d', [FRegions]), FRegions > 400);
  AssertTrue(Format('points compared: %d', [FPoints]), FPoints > 200);
end;

{ ==================== by hand ==================== }

const
  cSquares = '{"type":"FeatureCollection","features":['
    + '{"type":"Feature","properties":{"name":"A"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[10,0],[20,0],[20,10],[10,10],[10,0]]]}}]}';

procedure TAdvChartGeoSeriesTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  TyChartClearMaps;
  AssertTrue(TyChartRegisterMap('sq', cSquares));
end;

procedure TAdvChartGeoSeriesTest.TearDown;
begin
  TyChartClearMaps;
  FChart.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoSeriesTest.NewChart(const AOption: string);
begin
  FreeAndNil(FChart);
  FChart := TGsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.TooltipNow := 0;
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, 600, 400);
  Paint;
end;

procedure TAdvChartGeoSeriesTest.Paint;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

function TAdvChartGeoSeriesTest.PixelAt(AX, AY: Double): TBGRAPixel;
var px: PBGRAPixel;
begin
  px := FBmp.ScanLine[Round(AY)];
  Inc(px, Round(AX));
  Result := px^;
end;

{ the layer's own arithmetic: the Uint8ClampedArray rounding (a tie to
  even), the brush (a disc with no blur, a blurred one symmetric and
  fading out), isInRange's memory of the piece it last found, and an
  empty colour list's gradient }
procedure TAdvChartGeoSeriesTest.TestTheHeatLayerPieces;
var
  b: TBytes;
  side, i: Integer;
  rng: TTyHeatRange;
  g: TTyHeatGradient;
  cols: TTyVisualColorArray;
begin
  AssertEquals('0.5 to even', 0, TyHeatClampByte(0.5));
  AssertEquals('1.5 to even', 2, TyHeatClampByte(1.5));
  AssertEquals('2.5 to even', 2, TyHeatClampByte(2.5));
  AssertEquals('2.6 up', 3, TyHeatClampByte(2.6));
  AssertEquals('NaN', 0, TyHeatClampByte(NaN));
  AssertEquals('over', 255, TyHeatClampByte(300));
  b := TyHeatBrush(3, 0, side);
  AssertEquals('the side', 6, side);
  AssertEquals('the centre inside', 255, b[2 * side + 2]);
  AssertEquals('a corner outside', 0, b[0]);
  b := TyHeatBrush(4, 6, side);
  AssertEquals('the blurred side', 20, side);
  for i := 0 to side - 1 do
    AssertEquals(Format('symmetric along x at row 10, %d', [i]),
      b[10 * side + i], b[10 * side + (side - 1 - i)]);
  AssertTrue('the middle darker than the edge', b[10 * side + 10] > b[10 * side + 1]);
  { a piece found last is asked first: 0.5 is in both pieces }
  rng := TyHeatPiecewiseRange(0, 10, [0, 5], [5, 10], [True, False]);
  AssertTrue('0.2 in the first, selected', TyHeatInRange(rng, 0.2));
  AssertFalse('0.7 in the second, not selected', TyHeatInRange(rng, 0.7));
  AssertFalse('0.5 from the second, where the last one was found', TyHeatInRange(rng, 0.5));
  rng := TyHeatPiecewiseRange(0, 10, [0, 5], [5, 10], [True, False]);
  AssertTrue('0.5 from the first on a fresh range', TyHeatInRange(rng, 0.5));
  { an empty colour list leaves every colour black and clear }
  cols := nil;
  g := TyHeatGradientOf(cols);
  for i := 0 to 1023 do AssertEquals('nothing', 0, g[i]);
  SetLength(cols, 1);
  cols[0] := TyVisualRgba(10, 20, 30, 0.5);
  g := TyHeatGradientOf(cols);
  AssertEquals('red', 10, g[0]);
  AssertEquals('alpha 0.5 is a tie to 0', 0, g[3]);
end;

{ the map is drawn: the region's middle in the skin's map ink, the
  highlight under the pointer -- the picture, not the list }
procedure TAdvChartGeoSeriesTest.TestAMapSeriesIsPaintedInItsInk;
var
  geo: TTyGeo;
  c: TTyGeoPt;
  p: TTyPointF;
  want, hl: TTyChartColor;
  px: TBGRAPixel;
begin
  NewChart('{"animation": false, "series": [{"type": "map", "map": "sq",'
    + ' "data": [{"name": "A", "value": 1}]}]}');
  geo := FChart.MapGeoOf(0);
  AssertTrue('the series has a geo', (geo <> nil) and geo.Valid);
  c := geo.RegionByName('B').GetCenter;
  AssertTrue(geo.PointOf(c.X, c.Y, p));
  want := TTyChartColor(FCtl.Model.ResolveStyle('TyAdvChartMapArea', '', []).Background.Color);
  px := PixelAt(p.X, p.Y);
  AssertEquals('the fill of B, red', (want shr 16) and $FF, px.red);
  AssertEquals('the fill of B, green', (want shr 8) and $FF, px.green);
  AssertEquals('the fill of B, blue', want and $FF, px.blue);
  FChart.Move(Round(p.X), Round(p.Y));
  Paint;
  hl := TTyChartColor(FCtl.Model.ResolveStyle('TyAdvChartGeoArea', '', [tysHover]).Background.Color);
  px := PixelAt(p.X, p.Y);
  AssertEquals('hovered: the highlight, red', (hl shr 16) and $FF, px.red);
  AssertEquals('hovered: the highlight, blue', hl and $FF, px.blue);
end;

{ a geoRoam moves a scatter on the geo at once: the hit test finds the
  point where the pan put it, with no paint between }
procedure TAdvChartGeoSeriesTest.TestASeriesOnAGeoFollowsARoamBeforeAPaint;
var
  geo: TTyGeo;
  p: TTyPointF;
  d: TTyChartDatumRef;
begin
  NewChart('{"animation": false, "geo": {"map": "sq"}, "series": [{"type": "scatter",'
    + ' "coordinateSystem": "geo", "symbolSize": 12, "data": [[5, 5]]}]}');
  geo := FChart.GeoLayout(0);
  AssertTrue(geo.PointOf(5, 5, p));
  d := FChart.HitTestAt(Round(p.X), Round(p.Y));
  AssertEquals('the point is found', 0, d.DataIndex);
  FChart.DispatchAction('{"type": "geoRoam", "geoIndex": 0, "dx": 40, "dy": 30}');
  d := FChart.HitTestAt(Round(p.X), Round(p.Y));
  AssertTrue('not where it was', (d.SeriesIndex <> 0) or (d.DataIndex <> 0));
  d := FChart.HitTestAt(Round(p.X) + 40, Round(p.Y) + 30);
  AssertEquals('where the pan put it, series', 0, d.SeriesIndex);
  AssertEquals('where the pan put it, item', 0, d.DataIndex);
end;

{ a map nobody registered: upstream throws in setOption; here the series
  draws nothing and the rest of the chart is drawn }
procedure TAdvChartGeoSeriesTest.TestAMapNobodyRegisteredDrawsNothing;
var
  s, n: Integer;
  p: TTyPointF;
begin
  NewChart('{"animation": false, "geo": {"map": "sq"}, "series": [{"type": "map",'
    + ' "map": "nowhere", "data": [{"name": "A", "value": 1}]}, {"type": "scatter",'
    + ' "coordinateSystem": "geo", "symbolSize": 12, "data": [[5, 5]]}]}');
  AssertTrue('no geo of its own', (FChart.MapGeoOf(0) = nil) or not FChart.MapGeoOf(0).Valid);
  n := 0;
  if FChart.MapGeoOf(0) <> nil then FChart.GeoDrawRange(FChart.MapGeoOf(0), s, n);
  AssertEquals('no map picture', 0, n);
  AssertTrue(FChart.GeoLayout(0).PointOf(5, 5, p));
  AssertEquals('the scatter beside it drawn', 1,
    FChart.HitTestAt(Round(p.X), Round(p.Y)).SeriesIndex);
end;

{ pieToggleSelect and mapSelect: the select actions over the series of
  their type the query finds }
procedure TAdvChartGeoSeriesTest.TestTheLegacySelectActionsSelect;
var idx: TTyIntegerArray;
begin
  NewChart('{"animation": false, "series": [{"type": "pie", "selectedMode": "multiple",'
    + ' "data": [{"name": "a", "value": 1}, {"name": "b", "value": 2}]},'
    + ' {"type": "map", "map": "sq", "data": [{"name": "A", "value": 1}]}]}');
  FChart.DispatchAction('{"type": "pieToggleSelect", "name": "b"}');
  idx := FChart.SelectedDataIndices(0);
  AssertEquals('the pie took it', 1, Length(idx));
  AssertEquals('b', 1, idx[0]);
  idx := FChart.SelectedDataIndices(1);
  AssertEquals('not the map', 0, Length(idx));
  FChart.DispatchAction('{"type": "mapSelect", "name": "B"}');
  idx := FChart.SelectedDataIndices(1);
  AssertEquals('the map took it', 1, Length(idx));
  AssertEquals('B, the appended region', 1, idx[0]);
end;

{ coordinateSystem written otherwise: a map series is on its geo all the
  same (buildAllMapSeriesGroups takes every map series) }
procedure TAdvChartGeoSeriesTest.TestAMapSeriesIsAlwaysOnAGeo;
begin
  NewChart('{"animation": false, "xAxis": {}, "yAxis": {}, "series": [{"type": "map",'
    + ' "map": "sq", "coordinateSystem": "cartesian2d", "data": [{"name": "A", "value": 1}]}]}');
  AssertTrue('drawn on a geo of its own', (FChart.MapGeoOf(0) <> nil) and FChart.MapGeoOf(0).Valid);
end;


{ THE GALLERY'S GEO FILES that are GeoJSON (the SVG ones stay out): each
  rendered over the two squares registered under the map name it asks for
  -- no exception, and a map picture drawn (a geo component's or a map
  series' own) }
procedure TAdvChartGeoSeriesTest.TestTheGalleryGeoFilesDraw;
const
  cFiles: array[0..6] of string = ('effectScatter-map', 'geo-choropleth-scatter',
    'geo-graph', 'lines-ny', 'map-HK', 'map-usa', 'scatter-map-brush');
  cMaps: array[0..6] of string = ('china', 'iceland', 'ch', 'world', 'HK', 'USA', 'china');
var
  dir, d: string;
  i, k, s, n: Integer;
  sl: TStringList;
  geo: TTyGeo;
begin
  dir := '';
  d := ExtractFilePath(ParamStr(0));
  for i := 0 to 5 do
  begin
    if DirectoryExists(d + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery') then
    begin
      dir := d + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim;
      Break;
    end;
    d := d + '..' + PathDelim;
  end;
  AssertTrue('the gallery is where the test can reach it', dir <> '');
  for k := 0 to High(cFiles) do
  begin
    AssertTrue(TyChartRegisterMap(cMaps[k], cSquares));
    sl := TStringList.Create;
    try
      sl.LoadFromFile(dir + cFiles[k] + '.json');
      NewChart(sl.Text);
    finally
      sl.Free;
    end;
    n := 0;
    if FChart.GeoCount > 0 then geo := FChart.GeoLayout(0) else geo := FChart.MapGeoOf(0);
    AssertTrue(cFiles[k] + ': a geo', (geo <> nil) and geo.Valid);
    AssertTrue(cFiles[k] + ': drawn', FChart.GeoDrawRange(geo, s, n) and (n > 0));
  end;
end;

initialization
  RegisterTest(TAdvChartGeoSeriesOracleTest);
  RegisterTest(TAdvChartGeoSeriesTest);
end.
