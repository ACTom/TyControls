unit test.advchart.geosvg;
{$mode objfpc}{$H+}
{ SVG MAPS, HELD TO UPSTREAM [F6b].

  tools/advchart-oracle/geo-svg.js registers SVG maps with the real ECharts
  6.1 build in node (jsdom's DOMParser for parseXML, zrender's width table
  for the text), draws geos and map series on them and records the parsed
  tree of every MapDraw (each element's props, global transform, style,
  shape and bounding rect; the named items; the regions and their centres),
  then drives the pointer and the actions and records the events, the
  tooltip, the hit test at a set of points, every named element's state
  list and current style, its label, the series on the geo and the
  conversions.

  This replays the same through the control -- the parse compared node by
  node, bit for bit, the steps through the control's own pointer path -- and
  a few things by hand: the registry's forms, zrender's contain quirks, the
  picture in pixels and the gallery's SVG examples. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits, tyControls.Types, tyControls.StyleModel,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Handlers, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart.Style, tyControls.AdvanceChart.States, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Custom, tyControls.AdvanceChart.Convert, tyControls.AdvanceChart.Lines,
     tyControls.AdvanceChart.ZrPath, tyControls.AdvanceChart.GeoSvg, tyControls.AdvanceChart.Tooltip, tyControls.AdvanceChart.Scale, tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.Geo, tyControls.AdvanceChart;
type
  { zrender's server-side width table for every text the chart measures }
  TGsvMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TGsvProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
    function GeoSvgMeasure(const AText: string; const AFont: TTyGsFont): Double; override;
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Move(AX, AY: Integer);
    procedure Down(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure Wheel(AX, AY, ADelta: Integer);
    procedure Leave;
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
  end;

  TGsvLog = class
  public
    Lines: TStringList;
    Calls: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
    function RegionTip(const AParams: TTyChartParams): string;
    function RegionLabel(const AParams: TTyChartParams): string;
    function Pin(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  TAdvChartGeoSvgOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGsvProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FLog: TGsvLog;
    FInk: TTyGeoInk;
    FW, FH: Integer;
    FBad, FCompared, FNodes: Integer;
    { the tooltip's clock: a second a step }
    FNowMs: Double;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AHex: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameColour(const AWhat: string; AHas: Boolean; AGot: TTyChartColor;
      AWant: TJSONData);
    procedure Finish(const AWhat: string; AMin: Integer);
    function RegisterCaseMaps(ACase: TJSONObject): Boolean;
    procedure NewChart(const AOption: string);
    procedure Paint;
    procedure Step(AStep: TJSONObject);
    function GeoOfTree(ATree: TJSONObject): TTyGeo;
    procedure CompareTree(ATree: TJSONObject);
    procedure CompareNode(AGeo: TTyGeo; ANode: Integer; AWant: TJSONObject; ALite: Boolean);
    procedure CompareDraw(ATree: TJSONObject; AWant: TJSONData);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareTip(AWant: TJSONData);
    procedure CompareHits(ATrees: TJSONArray; AProbes, AWant: TJSONArray);
    procedure CompareSeries(AWant: TJSONArray);
    procedure CompareConvert(AWant: TJSONArray);
    procedure RunCase(ACase: TJSONObject; AParseOnly: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheParseAsUpstream;
    procedure TestEveryStepAsUpstream;
  end;

  TAdvChartGeoSvgTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGsvProbe;
    FBmp: TBGRABitmap;
    procedure NewChart(const AOption: string; AW: Integer = 600; AH: Integer = 400);
    procedure Paint;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRegistryTakesSvg;
    procedure TestZrenderContainQuirks;
    procedure TestTheMapIsPainted;
    procedure TestTheGallerySvgExamplesDraw;
    procedure TestATextSitsOnItsBaseline;
    procedure TestASkewedTextIsDrawnSkewed;
    procedure TestAnArcIsDrawnAsTheArc;
    procedure TestALabelWithNoRotateIsNotTurned;
  end;

implementation

const
  cSquare = '<svg width="200" height="100">'
    + '<rect x="0" y="0" width="200" height="100" fill="#ffffff"/>'
    + '<rect name="A" x="10" y="10" width="80" height="80" fill="#0000ff"/>'
    + '<g name="G"><circle cx="150" cy="50" r="30" fill="#ff0000"/></g>'
    + '<text x="100" y="95" font-size="10" fill="#000000">t</text></svg>';

{ ==================== helpers ==================== }

function RepoRoot: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..') + PathDelim;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'advchart-geo-svg.json';
end;

function ReadUtf8(const AFile: string): string;
var st: TFileStream;
begin
  Result := '';
  st := TFileStream.Create(AFile, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, st.Size);
    if st.Size > 0 then st.ReadBuffer(Result[1], st.Size);
  finally
    st.Free;
  end;
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

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function JsonForm(const AText: string): string;
var d: TJSONData;
begin
  if AText = '' then Exit('null');
  d := GetJSON(AText);
  try
    Result := d.AsJSON;
  finally
    d.Free;
  end;
end;

function KindName(AKind: TTyGsKind): string;
const
  cNames: array[TTyGsKind] of string = ('group', 'rect', 'circle', 'line', 'ellipse',
    'polygon', 'polyline', 'image', 'tspan', 'path');
begin
  Result := cNames[AKind];
end;

{ the PathProxy data a node holds: each command's code then its numbers }
function PathData(const APath: TTyZrPath): TTyDoubleArray;
const cCode: array[TTyZrCmd] of Integer = (1, 2, 3, 4, 5, 6, 7);
var i, k, n: Integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(APath) do
  begin
    SetLength(Result, n + 1 + TyZrArgCount(APath[i].Cmd));
    Result[n] := cCode[APath[i].Cmd];
    Inc(n);
    for k := 0 to TyZrArgCount(APath[i].Cmd) - 1 do
    begin
      Result[n] := APath[i].V[k];
      Inc(n);
    end;
  end;
end;

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

{ ==================== the measurer and the probe ==================== }

procedure TGsvMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var f: TTyGsFont; px: Double;
begin
  if TyFontSizeIsPx(AFontSizeLogical) then px := TyFontPxOf(AFontSizeLogical)
  else px := AFontSizeLogical;
  f := Default(TTyGsFont);
  f.Css := TyJsNumberToString(px) + 'px ' + AFontName;
  f.SizePx := px;
  f.Family := AFontName;
  AW := TyGsSsrWidth(AText, f);
  AH := px;
end;

function TGsvMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

function TGsvProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  Result := TGsvMeasurer.Create;
end;

function TGsvProbe.GeoSvgMeasure(const AText: string; const AFont: TTyGsFont): Double;
begin
  Result := TyGsSsrWidth(AText, AFont);
end;

procedure TGsvProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGsvProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TGsvProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TGsvProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TGsvProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TGsvProbe.Wheel(AX, AY, ADelta: Integer);
begin
  DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TGsvProbe.Leave;
begin
  MouseLeave;
end;

{ ==================== the log ==================== }

constructor TGsvLog.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
  Calls := TStringList.Create;
end;

destructor TGsvLog.Destroy;
begin
  Lines.Free;
  Calls.Free;
  inherited Destroy;
end;

procedure TGsvLog.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var p: TTyChartCallbackParams;
begin
  if AEvent.Payload <> '' then
  begin
    Lines.Add(AEvent.EventType + '|' + JsonForm(AEvent.Payload));
    Exit;
  end;
  p := AEvent.Params;
  if p.ComponentType = 'geo' then
    Lines.Add(Format('%s|geo|null|null|%d|%s|%s', [AEvent.EventType, p.ComponentIndex,
      p.Name, JsonForm(p.Region)]))
  else if p.ComponentType = 'series' then
    Lines.Add(Format('%s|series|%d|%d|null|%s|null', [AEvent.EventType, p.SeriesIndex,
      p.DataIndex, p.Name]))
  else
    Lines.Add(AEvent.EventType + '|' + p.ComponentType);
end;

function TGsvLog.RegionTip(const AParams: TTyChartParams): string;
begin
  Result := 'tip:' + AParams[0].ComponentType + ':' + AParams[0].Name;
end;

function TGsvLog.RegionLabel(const AParams: TTyChartParams): string;
begin
  Result := '[' + AParams[0].Name + '|' + AParams[0].Status + ']';
end;

function TGsvLog.Pin(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var v0, v1: Double; p, s: TTyDoubleArray;
begin
  v0 := AApi.Value(0);
  v1 := AApi.Value(1);
  p := AApi.Coord([v0, v1]);
  s := AApi.Size([10, 10], [v0, v1]);
  Calls.Add(Format('%d|%s %s|%s %s|%s %s', [AParams.DataIndex, HexOf(v0), HexOf(v1),
    HexOf(p[0]), HexOf(p[1]), HexOf(s[0]), HexOf(s[1])]));
  Result := TJSONObject.Create(['type', 'circle', 'shape', TJSONObject.Create([
    'cx', p[0], 'cy', p[1], 'r', 6]), 'style', TJSONObject.Create(['fill', '#ff0000'])]);
end;

function TGsvProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

{ ==================== the oracle ==================== }

procedure TAdvChartGeoSvgOracleTest.SetUp;
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
  FLog := TGsvLog.Create;
  TyChartRegisterFormatter('regionTip', @FLog.RegionTip);
  TyChartRegisterFormatter('regionLabel', @FLog.RegionLabel);
  TyChartRegisterRenderItem('pin', @FLog.Pin);
  FInk := InkOf(FCtl);
  FBad := 0;
  FCompared := 0;
  FNodes := 0;
  FReport := '';
  FWhere := '';
end;

procedure TAdvChartGeoSvgOracleTest.TearDown;
begin
  TyChartUnregisterFormatter('regionTip');
  TyChartUnregisterFormatter('regionLabel');
  TyChartUnregisterRenderItem('pin');
  TyChartClearMaps;
  FChart.Free;
  FLog.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  FRoot.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoSvgOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartGeoSvgOracleTest.Same(const AWhat: string; AGot: Double; AHex: TJSONData);
begin
  Inc(FCompared);
  if IsNull(AHex) then
  begin
    if not IsNan(AGot) then Bad(Format('%s %s, upstream null', [AWhat, Txt(AGot)]));
    Exit;
  end;
  if not ((HexOf(AGot) = AHex.AsString) or (IsNan(AGot) and IsNan(FromHex(AHex.AsString)))) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex.AsString))]));
end;

procedure TAdvChartGeoSvgOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoSvgOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoSvgOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True),
    BoolToStr(AWant, True)]));
end;

{ upstream's colour as the port must hold it: a token the skin's ink (a
  lifted token its lift); a gradient's own records are compared apart }
procedure TAdvChartGeoSvgOracleTest.SameColour(const AWhat: string; AHas: Boolean;
  AGot: TTyChartColor; AWant: TJSONData);
var tok: TJSONObject; s: string; want: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    if AHas then Bad(AWhat + ': a colour, upstream none');
    Exit;
  end;
  if AWant.JSONType <> jtString then Exit;
  if not AHas then
  begin
    Bad(AWhat + ': no colour, upstream ' + AWant.AsString);
    Exit;
  end;
  s := AWant.AsString;
  if s = 'gradient' then Exit;
  tok := TJSONObject(FRoot).Objects['tokens'];
  if s = tok.Strings['border'] then want := FInk.Border
  else if s = tok.Strings['label'] then want := FInk.LabelColour
  else if s = tok.Strings['highlight'] then want := FInk.HighlightFill
  else if s = tok.Strings['labelHighlight'] then want := FInk.LabelHighlight
  else if s = tok.Strings['liftedBorder'] then want := TyChartLiftColor(FInk.Border)
  else if s = tok.Strings['liftedHighlight'] then want := TyChartLiftColor(FInk.HighlightFill)
  else if s = tok.Strings['mapArea'] then want := FInk.MapAreaFill
  else if not TyTryParseChartColor(Trim(s), want) then want := 0;
  if AGot <> want then
    Bad(Format('%s %s, upstream %s (%s)', [AWhat, IntToHex(AGot, 8), IntToHex(want, 8), s]));
end;

procedure TAdvChartGeoSvgOracleTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartGeoSvgOracleTest.RegisterCaseMaps(ACase: TJSONObject): Boolean;
var
  maps, svgs, reg: TJSONArray;
  i, k: Integer;
  text, nm: string;
  ok: Boolean;
begin
  TyChartClearMaps;
  Result := True;
  maps := ACase.Arrays['maps'];
  reg := ACase.Arrays['registered'];
  svgs := TJSONObject(FRoot).Arrays['svgs'];
  for i := 0 to maps.Count - 1 do
  begin
    nm := maps.Objects[i].Strings['svg'];
    text := '';
    for k := 0 to svgs.Count - 1 do
      if svgs.Objects[k].Strings['name'] = nm then
      begin
        if svgs.Objects[k].Find('text') <> nil then text := svgs.Objects[k].Strings['text']
        else text := ReadUtf8(RepoRoot + StringReplace(svgs.Objects[k].Strings['file'], '/',
          PathDelim, [rfReplaceAll]));
      end;
    ok := TyChartRegisterMap(maps.Objects[i].Strings['map'],
      TJSONObject.Create(['svg', text]).AsJSON);
    SameBool('registered ' + nm, ok, reg.Booleans[i]);
    if not ok then Result := False;
  end;
end;

procedure TAdvChartGeoSvgOracleTest.NewChart(const AOption: string);
const
  cTypes: array[0..8] of string = ('click', 'mouseover', 'mouseout', 'mousemove',
    'geoselectchanged', 'geoselected', 'geounselected', 'georoam', 'selectchanged');
var i: Integer;
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(FW, FH, BGRA(255, 255, 255, 255));
  FChart := TGsvProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FNowMs := 0;
  FChart.TooltipNow := 0;
  for i := 0 to High(cTypes) do FChart.ChartOn(cTypes[i], @FLog.Handle);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, FW, FH);
  Paint;
  FLog.Lines.Clear;
end;

procedure TAdvChartGeoSvgOracleTest.Paint;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, FW, FH), 96);
end;

procedure TAdvChartGeoSvgOracleTest.Step(AStep: TJSONObject);
var a, q: TJSONArray; k: Integer; d: TJSONData;
begin
  FNowMs := FNowMs + 1000;
  FChart.TooltipNow := FNowMs;
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
  { a hide waiting out hideDelay: upstream's content says _show false at
    once (hideLater), so the step's snapshot is taken after the delay }
  FChart.TooltipTick(FNowMs + 500);
  FChart.TooltipNow := FNowMs + 500;
  Paint;
end;

function TAdvChartGeoSvgOracleTest.GeoOfTree(ATree: TJSONObject): TTyGeo;
begin
  if ATree.Strings['owner'] = 'geo' then Result := FChart.GeoLayout(ATree.Integers['i'])
  else Result := FChart.MapGeoOf(ATree.Integers['i']);
end;

{ a Transformable prop as the oracle wrote it: `v || 0` }
function Prop0(V: Double): Double;
begin
  if IsNan(V) or (V = 0) then Result := 0 else Result := V;
end;

procedure TAdvChartGeoSvgOracleTest.CompareNode(AGeo: TTyGeo; ANode: Integer;
  AWant: TJSONObject; ALite: Boolean);
var
  g: TTyGsGraphic;
  n: TTyGsNode;
  m: TTyMat2D;
  has: Boolean;
  d, st, sh: TJSONData;
  arr: TJSONArray;
  el: TTyStElement;
  c: TTyStObject;
  look: TTyGeoSvgLook;
  r: TTyXYWH;
  data: TTyDoubleArray;
  k: Integer;
  w: string;
  gr: TTyGsGradient;
  gj: TJSONObject;
  sil: Boolean;
  s: string;
begin
  g := AGeo.SvgGraphic;
  n := g.Nodes[ANode];
  w := Format('node %d', [ANode]);
  Inc(FNodes);
  SameStr(w + ' type', KindName(n.Kind), AWant.Strings['t']);
  SameInt(w + ' parent', n.Parent, AWant.Integers['p']);
  has := AGeo.SvgGlobal(ANode, m);
  d := AWant.Find('gt');
  SameBool(w + ' has a transform', has, not IsNull(d));
  if has and not IsNull(d) then
    for k := 0 to 5 do Same(Format('%s gt[%d]', [w, k]), m[k], TJSONArray(d).Items[k]);
  r := AGeo.SvgNodeRect(ANode);
  d := AWant.Find('br');
  if not IsNull(d) then
  begin
    Same(w + ' rect x', r.X, TJSONArray(d).Items[0]);
    Same(w + ' rect y', r.Y, TJSONArray(d).Items[1]);
    Same(w + ' rect w', r.W, TJSONArray(d).Items[2]);
    Same(w + ' rect h', r.H, TJSONArray(d).Items[3]);
  end;
  el := AGeo.SvgNodeItem(ANode);
  c := el.Cur;
  if ALite then
  begin
    if n.Kind <> gskGroup then
    begin
      SameColour(w + ' fill', TyStHasColour(c, stkFill), c.Color[stkFill], AWant.Find('fill'));
      SameColour(w + ' stroke', TyStHasColour(c, stkStroke), c.Color[stkStroke], AWant.Find('stroke'));
      Same(w + ' lw', c.Num[stkLineWidth], AWant.Find('lw'));
    end;
    Exit;
  end;
  arr := AWant.Arrays['lt'];
  Same(w + ' x', Prop0(n.T.X), arr.Items[0]);
  Same(w + ' y', Prop0(n.T.Y), arr.Items[1]);
  Same(w + ' scaleX', Prop0(n.T.ScaleX), arr.Items[2]);
  Same(w + ' scaleY', Prop0(n.T.ScaleY), arr.Items[3]);
  Same(w + ' rotation', Prop0(n.T.Rotation), arr.Items[4]);
  Same(w + ' skewX', Prop0(n.T.SkewX), arr.Items[5]);
  Same(w + ' skewY', Prop0(n.T.SkewY), arr.Items[6]);
  sil := n.Silent;
  if ANode <= High(AGeo.SvgGraphic.Nodes) then ;
  SameBool(w + ' invisible', n.Invisible, AWant.Booleans['inv']);
  SameBool(w + ' ignore', n.Ignore, AWant.Booleans['ign']);
  if n.Kind = gskGroup then Exit;
  look := AGeo.SvgLook(ANode);
  st := AWant.Find('st');
  if st is TJSONObject then
  begin
    { the fill: a gradient is compared as the paint server }
    d := TJSONObject(st).Find('fill');
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      gj := TJSONObject(d);
      Inc(FCompared);
      if look.FillGrad < 0 then Bad(w + ': no gradient, upstream one')
      else
      begin
        gr := g.Grads[look.FillGrad];
        SameStr(w + ' gradient type', BoolToStr(gr.Radial, 'radial', 'linear'), gj.Strings['type']);
        SameBool(w + ' gradient global', gr.Global, gj.Booleans['global']);
        Same(w + ' gradient x', gr.X, gj.Find('x'));
        Same(w + ' gradient y', gr.Y, gj.Find('y'));
        if gr.Radial then Same(w + ' gradient r', gr.R, gj.Find('r'))
        else
        begin
          Same(w + ' gradient x2', gr.X2, gj.Find('x2'));
          Same(w + ' gradient y2', gr.Y2, gj.Find('y2'));
        end;
        SameInt(w + ' gradient stops', Length(gr.Stops), gj.Arrays['stops'].Count);
        for k := 0 to Min(Length(gr.Stops), gj.Arrays['stops'].Count) - 1 do
        begin
          Same(Format('%s stop %d offset', [w, k]), gr.Stops[k].Offset, gj.Arrays['stops'].Arrays[k].Items[0]);
          SameStr(Format('%s stop %d colour', [w, k]), gr.Stops[k].Colour, gj.Arrays['stops'].Arrays[k].Strings[1]);
        end;
      end;
    end
    else
      SameColour(w + ' fill', TyStHasColour(c, stkFill), c.Color[stkFill], d);
    d := TJSONObject(st).Find('stroke');
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      Inc(FCompared);
      if look.StrokeGrad < 0 then Bad(w + ': no stroke gradient, upstream one');
    end
    else
      SameColour(w + ' stroke', TyStHasColour(c, stkStroke), c.Color[stkStroke], d);
    Same(w + ' lw', c.Num[stkLineWidth], TJSONObject(st).Find('lw'));
    Same(w + ' opacity', c.Num[stkOpacity], TJSONObject(st).Find('op'));
    if not IsNull(TJSONObject(st).Find('fo')) then
      Same(w + ' fillOpacity', look.FillOpacity, TJSONObject(st).Find('fo'));
    if not IsNull(TJSONObject(st).Find('so')) then
      Same(w + ' strokeOpacity', look.StrokeOpacity, TJSONObject(st).Find('so'));
    d := TJSONObject(st).Find('dash');
    Inc(FCompared);
    if IsNull(d) then
    begin
      if look.HasDash or (look.Styled and look.Opt.DashHas) then Bad(w + ': a dash, upstream none');
    end
    else if d.JSONType = jtString then
      SameStr(w + ' dash', look.Opt.DashRaw, d.AsString)
    else
    begin
      SameInt(w + ' dash count', Length(look.Dash), TJSONArray(d).Count);
      for k := 0 to Min(Length(look.Dash), TJSONArray(d).Count) - 1 do
        Same(Format('%s dash %d', [w, k]), look.Dash[k], TJSONArray(d).Items[k]);
    end;
    SameBool(w + ' strokeNoScale', look.NoScale, TJSONObject(st).Booleans['noScale']);
    if not IsNull(TJSONObject(st).Find('cap')) then
    begin
      if n.St.StrHas[gsLineCap] then s := n.St.Str[gsLineCap] else s := 'butt';
      SameStr(w + ' cap', s, TJSONObject(st).Strings['cap']);
    end;
    if not IsNull(TJSONObject(st).Find('join')) then
      SameStr(w + ' join', n.St.Str[gsLineJoin], TJSONObject(st).Strings['join']);
    if not IsNull(TJSONObject(st).Find('miter')) then
    begin
      if n.St.NumHas[gnMiterLimit] then Same(w + ' miter', n.St.Num[gnMiterLimit], TJSONObject(st).Find('miter'))
      else if n.Kind = gskTSpan then Same(w + ' miter', 2, TJSONObject(st).Find('miter'))
      else Same(w + ' miter', 10, TJSONObject(st).Find('miter'));
    end;
    if not IsNull(TJSONObject(st).Find('dashOff')) then
    begin
      if n.St.StrHas[gsLineDashOffset] then
        Same(w + ' dashOffset', TyJsToNumber(n.St.Str[gsLineDashOffset]), TJSONObject(st).Find('dashOff'))
      else
        Same(w + ' dashOffset', 0, TJSONObject(st).Find('dashOff'));
    end;
    if n.Kind = gskTSpan then
    begin
      SameStr(w + ' text', n.St.Text, TJSONObject(st).Get('text', ''));
      if n.St.HasFont then s := n.St.Font.Css else s := '12px sans-serif';
      SameStr(w + ' font', s, TJSONObject(st).Get('font', ''));
      if n.St.NumHas[gnFontSize] then Same(w + ' fontSize', n.St.Num[gnFontSize], TJSONObject(st).Find('fontSize'))
      else Same(w + ' fontSize', NaN, TJSONObject(st).Find('fontSize'));
      if n.St.StrHas[gsTextAlign] then s := n.St.Str[gsTextAlign] else s := 'left';
      SameStr(w + ' align', s, TJSONObject(st).Get('align', ''));
      if n.St.StrHas[gsTextBaseline] then s := n.St.Str[gsTextBaseline] else s := 'top';
      SameStr(w + ' baseline', s, TJSONObject(st).Get('base', ''));
    end;
    if n.Kind = gskImage then
    begin
      SameStr(w + ' image', IntToStr(Length(UTF8Decode(n.St.Image))) + ':'
        + UTF8Encode(Copy(UTF8Decode(n.St.Image), 1, 48)), TJSONObject(st).Get('img', ''));
      Same(w + ' image x', n.St.IX, TJSONObject(st).Find('ix'));
      Same(w + ' image y', n.St.IY, TJSONObject(st).Find('iy'));
      Same(w + ' image w', n.St.IW, TJSONObject(st).Find('iw'));
      Same(w + ' image h', n.St.IH, TJSONObject(st).Find('ih'));
    end;
  end;
  sh := AWant.Find('sh');
  if sh is TJSONObject then
  begin
    if TJSONObject(sh).Find('d') <> nil then
    begin
      data := PathData(n.Path);
      arr := TJSONObject(sh).Arrays['d'];
      SameInt(w + ' path length', Length(data), arr.Count);
      for k := 0 to Min(Length(data), arr.Count) - 1 do
        Same(Format('%s path[%d]', [w, k]), data[k], arr.Items[k]);
    end
    else
    begin
      arr := TJSONObject(sh).Arrays['v'];
      SameInt(w + ' shape length', Length(n.V), arr.Count);
      for k := 0 to Min(Length(n.V), arr.Count) - 1 do
        Same(Format('%s shape[%d]', [w, k]), n.V[k], arr.Items[k]);
    end;
  end;
  if sil then ;
end;

procedure TAdvChartGeoSvgOracleTest.CompareTree(ATree: TJSONObject);
var
  geo: TTyGeo;
  g: TTyGsGraphic;
  els, named, regs: TJSONArray;
  i: Integer;
  v: TJSONObject;
  pt: TTyGeoPt;
  r: TTyGeoRegion;
  nmw: TJSONObject;
begin
  geo := GeoOfTree(ATree);
  Inc(FCompared);
  if (geo = nil) or not geo.Valid or not geo.IsSvg then
  begin
    Bad('no SVG geo for ' + ATree.Strings['owner'] + ATree.Strings['i']);
    Exit;
  end;
  g := geo.SvgGraphic;
  Same('rect x', g.Rect.X, ATree.Arrays['rect'].Items[0]);
  Same('rect y', g.Rect.Y, ATree.Arrays['rect'].Items[1]);
  Same('rect w', g.Rect.W, ATree.Arrays['rect'].Items[2]);
  Same('rect h', g.Rect.H, ATree.Arrays['rect'].Items[3]);
  v := ATree.Objects['view'];
  Same('data x', geo.DataRect.X, v.Arrays['dataRect'].Items[0]);
  Same('data y', geo.DataRect.Y, v.Arrays['dataRect'].Items[1]);
  Same('data w', geo.DataRect.W, v.Arrays['dataRect'].Items[2]);
  Same('data h', geo.DataRect.H, v.Arrays['dataRect'].Items[3]);
  Same('view x', geo.ViewRect.X, v.Arrays['viewRect'].Items[0]);
  Same('view y', geo.ViewRect.Y, v.Arrays['viewRect'].Items[1]);
  Same('view w', geo.ViewRect.W, v.Arrays['viewRect'].Items[2]);
  Same('view h', geo.ViewRect.H, v.Arrays['viewRect'].Items[3]);
  for i := 0 to 5 do
  begin
    Same(Format('raw[%d]', [i]), geo.MtRaw[i], v.Arrays['mtRaw'].Items[i]);
    Same(Format('overall[%d]', [i]), geo.MtOverall[i], v.Arrays['mtOverall'].Items[i]);
    Same(Format('overall inverse[%d]', [i]), geo.MtOverallInv[i], v.Arrays['mtOverallInv'].Items[i]);
  end;
  Same('zoom', geo.Zoom, v.Find('zoom'));
  named := ATree.Arrays['named'];
  SameInt('named', Length(g.Named), named.Count);
  for i := 0 to Min(named.Count, Length(g.Named)) - 1 do
  begin
    nmw := named.Objects[i];
    SameStr(Format('named %d name', [i]), g.Named[i].Name, nmw.Strings['name']);
    SameInt(Format('named %d from', [i]), g.Named[i].From, nmw.Integers['from']);
    SameStr(Format('named %d tag', [i]), g.Named[i].Tag, nmw.Strings['tag']);
    SameInt(Format('named %d node', [i]), g.Named[i].Node, nmw.Integers['el']);
  end;
  regs := ATree.Arrays['regions'];
  SameInt('regions', Length(geo.Source.Regions), regs.Count);
  for i := 0 to Min(regs.Count, Length(geo.Source.Regions)) - 1 do
  begin
    r := geo.Source.Regions[i];
    SameStr(Format('region %d', [i]), r.Name, regs.Objects[i].Strings['name']);
    pt := r.GetCenter;
    Same(Format('region %d centre x', [i]), pt.X, regs.Objects[i].Arrays['c'].Items[0]);
    Same(Format('region %d centre y', [i]), pt.Y, regs.Objects[i].Arrays['c'].Items[1]);
  end;
  els := ATree.Arrays['els'];
  SameInt('nodes', Length(g.Nodes), els.Count);
  for i := 0 to Min(els.Count, Length(g.Nodes)) - 1 do
    CompareNode(geo, i, els.Objects[i], ATree.Booleans['lite']);
end;

{ the label's words now: the normal text, a state's in list order over it }
function LabelText(AGeo: TTyGeo; ANode: Integer): string;
var lbl: TTyGeoLabel; it: TTyStElement; s: TTyStName;
begin
  lbl := AGeo.SvgLabelOf(ANode);
  it := AGeo.SvgLabelItem(ANode);
  Result := lbl.Text;
  for s := Low(TTyStName) to High(TTyStName) do
    if s in it.States then Result := lbl.States[s].Text;
end;

procedure TAdvChartGeoSvgOracleTest.CompareDraw(ATree: TJSONObject; AWant: TJSONData);
var
  geo: TTyGeo;
  items: TJSONArray;
  it, lw: TJSONObject;
  i, node: Integer;
  el, lb: TTyStElement;
  c: TTyStObject;
  w: string;
  ax, ay, rot, tx, ty: Double;
  m: TTyMat2D;
begin
  if IsNull(AWant) then Exit;
  geo := GeoOfTree(ATree);
  if (geo = nil) or not geo.IsSvg then
  begin
    Bad('no geo to compare');
    Exit;
  end;
  items := TJSONObject(AWant).Arrays['items'];
  { the roam transform group }
  if not IsNull(TJSONObject(AWant).Find('roam')) then
  begin
    m := geo.RoamMatrix;
    for i := 0 to 5 do Same(Format('roam[%d]', [i]), m[i], TJSONObject(AWant).Arrays['roam'].Items[i]);
  end;
  for i := 0 to items.Count - 1 do
  begin
    it := items.Objects[i];
    node := it.Integers['i'];
    w := Format('node %d', [node]);
    el := geo.SvgNodeItem(node);
    c := el.Cur;
    SameStr(w + ' states', TyStNamesText(el.States), it.Strings['states']);
    SameInt(w + ' hover', el.HoverState, it.Integers['hover']);
    SameBool(w + ' selected', el.Selected, it.Booleans['sel']);
    if it.Find('fill') <> nil then
    begin
      SameColour(w + ' fill', TyStHasColour(c, stkFill), c.Color[stkFill], it.Find('fill'));
      SameColour(w + ' stroke', TyStHasColour(c, stkStroke), c.Color[stkStroke], it.Find('stroke'));
      Same(w + ' lw', c.Num[stkLineWidth], it.Find('lw'));
      Same(w + ' opacity', c.Num[stkOpacity], it.Find('op'));
      SameInt(w + ' z2', Round(c.Num[stkZ2]), it.Integers['z2']);
    end;
    SameBool(w + ' has a label', geo.SvgHasLabel(node), not IsNull(it.Find('label')));
    if IsNull(it.Find('label')) or not geo.SvgHasLabel(node) then Continue;
    lw := it.Objects['label'];
    lb := geo.SvgLabelItem(node);
    c := lb.Cur;
    w := w + ' label';
    SameStr(w + ' states', TyStNamesText(lb.States), lw.Strings['states']);
    SameBool(w + ' ignore', c.Num[stkIgnore] <> 0, lw.Booleans['ignore']);
    SameStr(w + ' text', LabelText(geo, node), lw.Get('text', ''));
    SameColour(w + ' fill', TyStHasColour(c, stkFill), c.Color[stkFill], lw.Find('fill'));
    Same(w + ' opacity', c.Num[stkOpacity], lw.Find('op'));
    SameInt(w + ' z2', Round(c.Num[stkZ2]), lw.Integers['z2']);
    if lw.Booleans['ignore'] then Continue;
    geo.SvgLabelPlace(node, 96, ax, ay, rot, tx, ty);
    Same(w + ' x', ax, lw.Find('x'));
    Same(w + ' y', ay, lw.Find('y'));
    Same(w + ' tx', tx, lw.Find('tx'));
    Same(w + ' ty', ty, lw.Find('ty'));
  end;
end;

procedure TAdvChartGeoSvgOracleTest.CompareEvents(AWant: TJSONArray);
var
  want: TStringList;
  i: Integer;
  e: TJSONObject;

  function S(const AKey: string): string;
  var d: TJSONData;
  begin
    d := e.Find(AKey);
    if IsNull(d) then Result := 'null'
    else if d.JSONType = jtString then Result := d.AsString
    else Result := d.AsJSON;
  end;

begin
  want := TStringList.Create;
  try
    for i := 0 to AWant.Count - 1 do
    begin
      e := AWant.Objects[i];
      if e.Find('json') <> nil then
        want.Add(e.Strings['type'] + '|' + JsonForm(e.Strings['json']))
      else if S('componentType') = 'geo' then
        want.Add(Format('%s|geo|null|null|%s|%s|%s', [S('type'), S('geoIndex'), S('name'),
          JsonForm(e.Get('region', ''))]))
      else if S('componentType') = 'series' then
        want.Add(Format('%s|series|%s|%s|null|%s|null', [S('type'), S('seriesIndex'),
          S('dataIndex'), S('name')]))
      else
        want.Add(S('type') + '|' + S('componentType'));
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

{ the default content as upstream's rich text reads with its styles taken
  off: the lines, each the words of its runs (no marker) }
function TipLinesText(ABlock: TTyTooltipBlock): string;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j: Integer;
begin
  Result := '';
  if ABlock = nil then Exit;
  ink := Default(TTyTooltipInk);
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  for i := 0 to High(lines) do
  begin
    if i > 0 then Result := Result + #10;
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind <> ttrMarker then
        Result := Result + lines[i].Runs[j].Text;
  end;
end;

procedure TAdvChartGeoSvgOracleTest.CompareTip(AWant: TJSONData);
var text: string; block: TTyTooltipBlock;
begin
  if IsNull(AWant) then
  begin
    SameBool('tooltip shown', FChart.TooltipShown, False);
    Exit;
  end;
  SameBool('tooltip shown', FChart.TooltipShown, True);
  if not FChart.TooltipShown then Exit;
  text := FChart.TooltipFormatterText;
  { no formatter and not a geo region: the series' default content }
  if text = '' then
  begin
    block := FChart.ContentOf(FChart.TooltipShownDatum);
    try
      text := TipLinesText(block);
    finally
      block.Free;
    end;
  end;
  { the auto series name's NUL (series\u00000): fpjson's scanner drops a
    \u0000 from the fixture, so the text loses it here too }
  text := StringReplace(text, #0, '', [rfReplaceAll]);
  SameStr('tooltip text', text, TJSONObject(AWant).Strings['text']);
end;

procedure TAdvChartGeoSvgOracleTest.CompareHits(ATrees: TJSONArray; AProbes, AWant: TJSONArray);
var
  i, k, x, y: Integer;
  dt: TTyChartDatumRef;
  hw: TJSONObject;
  el: TTyChartElement;
  w: string;
  geo: TTyGeo;
  onSvg: Boolean;
begin
  for i := 0 to AProbes.Count - 1 do
  begin
    x := AProbes.Arrays[i].Integers[0];
    y := AProbes.Arrays[i].Integers[1];
    w := Format('probe %d (%d, %d)', [i, x, y]);
    dt := FChart.HitTestAt(x, y, k);
    onSvg := (k >= 0) and (FChart.List.Element(k).ZrHit.SvgNode > 0);
    Inc(FCompared);
    if IsNull(AWant.Items[i]) or IsNull(TJSONObject(AWant.Items[i]).Find('owner')) then
    begin
      if onSvg then Bad(w + ': an SVG element, upstream none');
      Continue;
    end;
    hw := TJSONObject(AWant.Items[i]);
    if not onSvg then
    begin
      Bad(w + ': nothing of the SVG, upstream ' + hw.AsJSON);
      Continue;
    end;
    el := FChart.List.Element(k);
    if not IsNull(hw.Find('el')) then
    begin
      SameBool(w + ' on a label', el.ZrHit.SvgLabel, False);
      SameInt(w + ' node', el.ZrHit.SvgNode - 1, hw.Integers['el']);
    end
    else
    begin
      SameBool(w + ' on a label', el.ZrHit.SvgLabel, True);
      SameInt(w + ' label of', el.ZrHit.SvgNode - 1, hw.Integers['label']);
    end;
    if not IsNull(hw.Find('name')) then
    begin
      SameBool(w + ' a geo datum', dt.Kind = ctkGeo, True);
      if dt.Kind = ctkGeo then
      begin
        geo := FChart.GeoLayout(dt.ComponentIndex);
        SameStr(w + ' name', geo.GroupName(dt.DataIndex), hw.Strings['name']);
      end;
    end;
    if not IsNull(hw.Find('series')) then
    begin
      SameInt(w + ' series', dt.SeriesIndex, hw.Integers['series']);
      SameInt(w + ' data index', dt.DataIndex, hw.Integers['dataIndex']);
    end;
  end;
  if ATrees = nil then ;
end;

procedure TAdvChartGeoSvgOracleTest.CompareSeries(AWant: TJSONArray);
var
  s, i, k: Integer;
  sw: TJSONObject;
  t: string;
  pts, row: TJSONArray;
  el, found: TTyChartElement;
  has: Boolean;
  sol: TTyLinesSolved;
  calls: TJSONArray;
  c: TJSONObject;
  want: TStringList;
begin
  for s := 0 to AWant.Count - 1 do
  begin
    if IsNull(AWant.Items[s]) then Continue;
    sw := AWant.Objects[s];
    t := sw.Strings['type'];
    if (t = 'scatter') or (t = 'effectScatter') then
    begin
      pts := sw.Arrays['pts'];
      for i := 0 to pts.Count - 1 do
      begin
        if IsNull(pts.Items[i]) then Continue;
        has := False;
        found := Default(TTyChartElement);
        for k := 0 to FChart.List.Count - 1 do
        begin
          el := FChart.List.Element(k);
          if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> s)
            or (el.Datum.DataIndex <> i) or (el.Caption.FontSizeLogical > 0) or el.Silent then Continue;
          found := el;
          has := True;
          Break;
        end;
        Inc(FCompared);
        if not has then
        begin
          Bad(Format('series %d item %d not drawn', [s, i]));
          Continue;
        end;
        Same(Format('series %d item %d x', [s, i]), found.Shape.CX, pts.Arrays[i].Items[0]);
        Same(Format('series %d item %d y', [s, i]), found.Shape.CY, pts.Arrays[i].Items[1]);
      end;
    end
    else if t = 'lines' then
    begin
      sol := FChart.LinesSolvedOf(s);
      pts := sw.Arrays['pts'];
      SameInt(Format('series %d rows', [s]), Length(sol.Geoms), pts.Count);
      for i := 0 to Min(pts.Count, Length(sol.Geoms)) - 1 do
      begin
        row := pts.Arrays[i];
        SameInt(Format('series %d row %d points', [s, i]), Length(sol.Geoms[i].Pts), row.Count);
        for k := 0 to Min(row.Count, Length(sol.Geoms[i].Pts)) - 1 do
        begin
          Same(Format('series %d row %d pt %d x', [s, i, k]), sol.Geoms[i].Pts[k].X, row.Arrays[k].Items[0]);
          Same(Format('series %d row %d pt %d y', [s, i, k]), sol.Geoms[i].Pts[k].Y, row.Arrays[k].Items[1]);
        end;
      end;
    end
    else if t = 'custom' then
    begin
      calls := sw.Arrays['calls'];
      want := TStringList.Create;
      try
        for i := 0 to calls.Count - 1 do
        begin
          c := calls.Objects[i];
          want.Add(Format('%d|%s %s|%s %s|%s %s', [c.Integers['i'], c.Arrays['value'].Strings[0],
            c.Arrays['value'].Strings[1], c.Arrays['coord'].Strings[0], c.Arrays['coord'].Strings[1],
            c.Arrays['size'].Strings[0], c.Arrays['size'].Strings[1]]));
        end;
        SameInt('renderItem calls', FLog.Calls.Count, want.Count);
        for i := 0 to Min(want.Count, FLog.Calls.Count) - 1 do
          SameStr(Format('renderItem call %d', [i]), FLog.Calls[i], want[i]);
      finally
        want.Free;
      end;
      FLog.Calls.Clear;
    end;
  end;
end;

procedure TAdvChartGeoSvgOracleTest.CompareConvert(AWant: TJSONArray);
var
  i: Integer;
  q: TJSONObject;
  r: TTyConvertResult;
  out_: TJSONData;
begin
  for i := 0 to AWant.Count - 1 do
  begin
    q := AWant.Objects[i];
    if q.Find('value') <> nil then
    begin
      r := FChart.ConvertToPixelData(q.Find('finder'), q.Find('value'));
      out_ := q.Find('px');
    end
    else
    begin
      r := FChart.ConvertFromPixelData(q.Find('finder'), q.Find('px'));
      out_ := q.Find('data');
    end;
    Inc(FCompared);
    if IsNull(out_) then
    begin
      if Length(r.Values) > 0 then Bad(Format('convert %d answered, upstream not', [i]));
      Continue;
    end;
    if Length(r.Values) < 2 then
    begin
      Bad(Format('convert %d: no answer, upstream %s', [i, out_.AsJSON]));
      Continue;
    end;
    Same(Format('convert %d x', [i]), r.Values[0], TJSONArray(out_).Items[0]);
    Same(Format('convert %d y', [i]), r.Values[1], TJSONArray(out_).Items[1]);
  end;
end;

procedure TAdvChartGeoSvgOracleTest.RunCase(ACase: TJSONObject; AParseOnly: Boolean);
var
  states, steps, trees, probes, draws: TJSONArray;
  st: TJSONObject;
  i, t: Integer;
  geo: TTyGeo;
begin
  FWhere := ACase.Strings['id'];
  FW := ACase.Integers['W'];
  FH := ACase.Integers['H'];
  if not RegisterCaseMaps(ACase) then
  begin
    { the map is not there: the geo draws nothing }
    NewChart(ACase.Objects['option'].AsJSON);
    geo := FChart.GeoLayout(0);
    SameBool('no valid geo', (geo = nil) or not geo.Valid, True);
    Exit;
  end;
  if ACase.Find('throws') <> nil then
  begin
    NewChart(ACase.Objects['option'].AsJSON);
    geo := FChart.GeoLayout(0);
    SameBool('where upstream throws, no valid geo', (geo = nil) or not geo.Valid, True);
    Exit;
  end;
  { the first render's renderItem calls are state 0's }
  FLog.Calls.Clear;
  NewChart(ACase.Objects['option'].AsJSON);
  trees := ACase.Arrays['trees'];
  if AParseOnly then
  begin
    for t := 0 to trees.Count - 1 do
    begin
      FWhere := Format('%s tree %d', [ACase.Strings['id'], t]);
      CompareTree(trees.Objects[t]);
    end;
    Exit;
  end;
  states := ACase.Arrays['states'];
  steps := ACase.Arrays['steps'];
  probes := ACase.Arrays['probes'];
  for i := 0 to states.Count - 1 do
  begin
    FWhere := Format('%s state %d', [ACase.Strings['id'], i]);
    if i > 0 then Step(steps.Objects[i - 1]);
    st := states.Objects[i];
    CompareEvents(st.Arrays['events']);
    CompareTip(st.Find('tip'));
    CompareHits(trees, probes, st.Arrays['hits']);
    draws := st.Arrays['draws'];
    for t := 0 to Min(draws.Count, trees.Count) - 1 do
      CompareDraw(trees.Objects[t], draws.Items[t]);
    CompareSeries(st.Arrays['series']);
    CompareConvert(st.Arrays['convert']);
  end;
end;

procedure TAdvChartGeoSvgOracleTest.TestTheParseAsUpstream;
var cases: TJSONArray; c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  AssertTrue('cases', cases.Count >= 12);
  for c := 0 to cases.Count - 1 do RunCase(cases.Objects[c], True);
  AssertTrue(Format('nodes compared: %d', [FNodes]), FNodes > 3000);
  Finish('the parse', 20000);
end;

procedure TAdvChartGeoSvgOracleTest.TestEveryStepAsUpstream;
var cases: TJSONArray; c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do RunCase(cases.Objects[c], False);
  Finish('every step', 3000);
end;

{ ==================== by hand ==================== }

procedure TAdvChartGeoSvgTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
end;

procedure TAdvChartGeoSvgTest.TearDown;
begin
  TyChartClearMaps;
  FChart.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoSvgTest.NewChart(const AOption: string; AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  FChart := TGsvProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.TooltipNow := 0;
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  Paint;
end;

procedure TAdvChartGeoSvgTest.Paint;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

{ registerMap's SVG forms: the wrapper with an svg string, the markup
  itself; a broken document or a root that is not svg refused with the
  registry as it was; getMap answers nothing for an SVG map }
procedure TAdvChartGeoSvgTest.TestTheRegistryTakesSvg;
var gj, sa: string;
begin
  AssertTrue('the markup', TyChartRegisterMap('m1', cSquare));
  AssertTrue('an SVG map', TyGeoMapIsSvg('m1'));
  AssertTrue('the wrapper', TyChartRegisterMap('m2',
    TJSONObject.Create(['svg', cSquare]).AsJSON));
  AssertTrue(TyGeoMapIsSvg('m2'));
  AssertTrue('a byte-order mark and white space before the markup',
    TyChartRegisterMap('m3', #$EF#$BB#$BF + LineEnding + '  ' + cSquare));
  AssertFalse('a broken document', TyChartRegisterMap('m1', '<svg><rect></svg>'));
  AssertTrue('the earlier one stays', TyGeoMapIsSvg('m1'));
  AssertFalse('a root that is not svg', TyChartRegisterMap('m4', '<foo/>'));
  AssertFalse(TyChartMapRegistered('m4'));
  AssertFalse('an svg that is not a string', TyChartRegisterMap('m5', '{"svg": {"a": 1}}'));
  AssertFalse('getMap answers nothing for an SVG map', TyChartGetMap('m1', gj, sa));
  AssertTrue('still registered', TyChartMapRegistered('m1'));
  { a GeoJSON map under the same name replaces it }
  AssertTrue(TyChartRegisterMap('m1', '{"type":"FeatureCollection","features":[]}'));
  AssertFalse(TyGeoMapIsSvg('m1'));
end;

{ a division by nought in the host, traps on: EZeroDivide, not an
  EInvalidOp a sticky flag of the masked stretch left behind (MXCSR) }
function HostTrapClass: string;
var a, b: Double;
begin
  Result := 'none';
  a := 1;
  b := 0;
  try
    a := a / b;
  except
    on E: Exception do Result := E.ClassName;
  end;
end;

{ contain/path.ts as zrender has it: a cubic whose y is only quadratic
  finds no root, so the region between it and its closing line is outside
  -- the browser's own fill would say inside }
procedure TAdvChartGeoSvgTest.TestZrenderContainQuirks;
var p: TTyZrPath; hit: TTyZrHit;
begin
  p := nil;
  TyZrMoveTo(p, 40, 230);
  TyZrCubic(p, 60, 200, 100, 200, 120, 230);
  TyZrClose(p);
  AssertFalse('the degenerate cubic: no winding', TyZrContain(p, 80, 225));
  { its roots are not-a-numbers under the masked traps: none left set }
  AssertEquals('the host''s traps after the contain', 'EZeroDivide', HostTrapClass);
  hit := Default(TTyZrHit);
  hit.Active := True;
  hit.Path := p;
  hit.ToLocal[0] := 1;
  hit.ToLocal[3] := 1;
  hit.Box.X := 0;
  hit.Box.Y := 0;
  hit.Box.W := 1000;
  hit.Box.H := 1000;
  hit.Fill := True;
  AssertFalse(TyZrHitContains(hit, 80, 225));
  AssertEquals('the host''s traps after the hit', 'EZeroDivide', HostTrapClass);
  p := nil;
  TyZrMoveTo(p, 40, 230);
  TyZrCubic(p, 60, 200, 100, 199, 120, 230);
  TyZrClose(p);
  AssertTrue('a true cubic winds', TyZrContain(p, 80, 225));
  p := nil;
  TyZrRect(p, 0, 0, 10, 10);
  AssertTrue('a rect', TyZrContain(p, 5, 5));
  AssertFalse(TyZrContain(p, 15, 5));
  AssertTrue('its edge within half the width', TyZrContainStroke(p, 2, 10.9, 5));
  AssertFalse(TyZrContainStroke(p, 2, 11.1, 5));
  p := nil;
  TyZrMoveTo(p, 30, 0);
  TyZrArc(p, 0, 0, 30, 0, 2 * Pi, False);
  AssertTrue('a circle', TyZrContain(p, 0, 0));
  AssertFalse(TyZrContain(p, 25, 25));
  AssertTrue('on its stroke', TyZrContainStroke(p, 4, 0, 31.5));
end;

{ the SVG's own picture reaches the pixels: A's blue, G's red circle, and
  the hover's highlight over A }
procedure TAdvChartGeoSvgTest.TestTheMapIsPainted;
var px: TBGRAPixel; geo: TTyGeo; a: TTyPointF;
begin
  AssertTrue(TyChartRegisterMap('sq', cSquare));
  NewChart('{"animation": false, "geo": {"map": "sq", "left": 0, "top": 0, "width": 600, "height": 300}}');
  geo := FChart.GeoLayout(0);
  AssertNotNull(geo);
  AssertTrue('an SVG geo', geo.IsSvg and geo.Valid);
  AssertTrue(geo.PointOf(50, 50, a));
  px := FBmp.GetPixel(Round(a.X), Round(a.Y));
  AssertTrue(Format('A is blue (%d %d %d)', [px.red, px.green, px.blue]),
    (px.blue > 200) and (px.red < 60));
  AssertTrue(geo.PointOf(150, 50, a));
  px := FBmp.GetPixel(Round(a.X), Round(a.Y));
  AssertTrue(Format('the circle is red (%d %d %d)', [px.red, px.green, px.blue]),
    (px.red > 200) and (px.blue < 60));
  { A's centre region is region 0; the hover fills it with the highlight }
  AssertTrue(geo.PointOf(50, 50, a));
  FChart.Move(Round(a.X), Round(a.Y));
  Paint;
  px := FBmp.GetPixel(Round(a.X), Round(a.Y));
  AssertFalse(Format('the hover changed A (%d %d %d)', [px.red, px.green, px.blue]),
    (px.blue > 200) and (px.red < 60));
end;

{ the red ink's extent in rows / its mean column per row band }
procedure RedInk(ABmp: TBGRABitmap; out ATop, ABottom: Integer);
var x, y: Integer; p: TBGRAPixel;
begin
  ATop := MaxInt;
  ABottom := -1;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
    begin
      p := ABmp.GetPixel(x, y);
      if (p.red > 150) and (p.green < 110) and (p.blue < 110) then
      begin
        if y < ATop then ATop := y;
        if y > ABottom then ABottom := y;
      end;
    end;
end;

function RedMeanX(ABmp: TBGRABitmap; AY0, AY1: Integer): Double;
var x, y, n: Integer; p: TBGRAPixel; s: Double;
begin
  s := 0;
  n := 0;
  for y := AY0 to AY1 do
    for x := 0 to ABmp.Width - 1 do
    begin
      p := ABmp.GetPixel(x, y);
      if (p.red > 150) and (p.green < 110) and (p.blue < 110) then
      begin
        s := s + x;
        Inc(n);
      end;
    end;
  if n = 0 then Result := NaN else Result := s / n;
end;

{ [R2-F] AN SVG TEXT ON ITS BASELINE: with no alignment-baseline the
  TSpan's is 'alphabetic', and a canvas draws the baseline at y -- the
  capital's foot at y, its head a cap height above. It used to hang the
  text's box from the bottom of the TSpan's rect, a whole line low. }
procedure TAdvChartGeoSvgTest.TestATextSitsOnItsBaseline;
var top, bottom: Integer;
begin
  AssertTrue(TyChartRegisterMap('base', '<svg width="200" height="100">'
    + '<text x="20" y="60" font-size="30" fill="#ff0000">HH</text></svg>'));
  NewChart('{"animation": false, "geo": {"map": "base", "silent": true, "left": 0, "top": 0, '
    + '"width": 200, "height": 100}}', 200, 100);
  RedInk(FBmp, top, bottom);
  AssertTrue('the text is drawn', bottom >= 0);
  AssertTrue(Format('the foot on the baseline: ink to row %d, y 60', [bottom]),
    (bottom >= 57) and (bottom <= 61));
  AssertTrue(Format('the head a cap height above: from row %d', [top]),
    (top >= 30) and (top <= 45));
end;

{ [R2-F] A SKEWED TEXT IS DRAWN SKEWED: transform skewX(-30) moves a
  point tan 30 x its y to the left -- an upright stem leans, its top
  further right than its foot by tan 30 x its height. A turn and one size
  used to be all a text took of its matrix. }
procedure TAdvChartGeoSvgTest.TestASkewedTextIsDrawnSkewed;
var top, bottom: Integer; xt, xb, lean: Double;
begin
  AssertTrue(TyChartRegisterMap('skew', '<svg width="200" height="100">'
    + '<text x="80" y="80" font-size="60" fill="#ff0000" transform="skewX(-30)">I</text></svg>'));
  NewChart('{"animation": false, "geo": {"map": "skew", "silent": true, "left": 0, "top": 0, '
    + '"width": 200, "height": 100}}', 200, 100);
  RedInk(FBmp, top, bottom);
  AssertTrue('the text is drawn', bottom > top + 10);
  xt := RedMeanX(FBmp, top, top + 4);
  xb := RedMeanX(FBmp, bottom - 4, bottom);
  lean := (xt - xb) / (bottom - top);
  AssertTrue(Format('the stem leans as tan 30 (%.3f; top %.1f, foot %.1f)', [lean, xt, xb]),
    (lean > 0.45) and (lean < 0.7));
end;

{ [R2-F] AN SVG ARC IS THE ARC: a sixteenth of a turn a cubic at most, every
  cubic's middle within 1e-7 of the radius off the circle -- a quarter
  turn's was 2.7e-4, a pixel at a radius a zoomed map reaches }
procedure TAdvChartGeoSvgTest.TestAnArcIsDrawnAsTheArc;
var
  p: TTyZrPath;
  cmds: TTyPathCmdArray;
  pts: TTyPointFArray;
  ident: TTyMat2D;
  i, curves: Integer;
  x0, y0, mx, my, worst: Double;
begin
  p := nil;
  TyZrMoveTo(p, 1000, 0);
  TyZrArc(p, 0, 0, 1000, 0, 2 * Pi, False);
  ident[0] := 1; ident[1] := 0; ident[2] := 0; ident[3] := 1; ident[4] := 0; ident[5] := 0;
  TyGsPathCmds(p, ident, cmds, pts);
  curves := 0;
  worst := 0;
  x0 := 1000;
  y0 := 0;
  for i := 0 to High(cmds) do
    case cmds[i].Kind of
      pckMove, pckLine:
        begin
          x0 := cmds[i].X;
          y0 := cmds[i].Y;
        end;
      pckCurve:
        begin
          Inc(curves);
          { the cubic at t = 1/2 }
          mx := (x0 + 3 * cmds[i].X1 + 3 * cmds[i].X2 + cmds[i].X) / 8;
          my := (y0 + 3 * cmds[i].Y1 + 3 * cmds[i].Y2 + cmds[i].Y) / 8;
          worst := Max(worst, Abs(Sqrt(Sqr(mx) + Sqr(my)) - 1000));
          x0 := cmds[i].X;
          y0 := cmds[i].Y;
        end;
    end;
  AssertEquals('a turn is sixteen cubics', 16, curves);
  AssertTrue(Format('every one on the circle (%.3g off at r 1000)', [worst]), worst < 1e-4);
end;

{ [R2-H] the stack where the next calls will put their locals, filled with
  0x7F bytes: a local read before it is written reads 0x7F7F..., never 0 }
procedure PoisonTheStack;
var a: array[0..65535] of Byte;
begin
  FillChar(a, SizeOf(a), $7F);
  if a[1000] = 0 then WriteLn('never');
end;

{ [R2-H] AN SVG REGION'S LABEL WITH NO rotate IS NOT TURNED: updateInnerText's
  rotation is the label's own (or a state's), none when neither writes one.
  SvgPlaceLabel left its turn unset when nothing wrote one -- the stack's
  garbage: two charts of the same option differed in a hidden label's
  rotation (geo-beef-cuts), a shown one drew through the turned path. Every
  label of a map series and of a geo component, each built on a poisoned
  stack, turns by exactly nothing -- the label placed after one that turns
  (A turns 30 degrees: its call leaves its turn where the next call's local
  is) as well. }
procedure TAdvChartGeoSvgTest.TestALabelWithNoRotateIsNotTurned;
const
  cOpts: array[0..1] of string = (
    '{"animation": false, "series": [{"type": "map", "map": "sqlbl", "label": {"show": true},'
      + ' "left": 0, "top": 0, "width": 600, "height": 300, "data": [{"name": "A", "value": 1, "label": {"rotate": 30}},'
      + ' {"name": "G", "value": 2}]}]}',
    '{"animation": false, "geo": {"map": "sqlbl", "label": {"show": true}, "left": 0, "top": 0, "width": 600, "height": 300,'
      + ' "regions": [{"name": "A", "label": {"rotate": 30}}]}}');
var
  i, k, n: Integer;
  lst: TTyPaintList;
  el: TTyChartElement;
begin
  AssertTrue(TyChartRegisterMap('sqlbl', cSquare));
  n := 0;
  for i := 0 to High(cOpts) do
  begin
    PoisonTheStack;
    NewChart(cOpts[i]);
    PoisonTheStack;
    FChart.Option := cOpts[i];
    Paint;
    lst := FChart.List;
    AssertNotNull('a list', lst);
    for k := 0 to lst.Count - 1 do
    begin
      el := lst.Element(k);
      if el.Caption.Text <> 'G' then Continue;
      Inc(n);
      AssertEquals(Format('option %d: the label "%s" turns by', [i, el.Caption.Text]),
        '0000000000000000', IntToHex(PQWord(@el.Caption.RotationRad)^, 16));
    end;
  end;
  AssertTrue(Format('labels seen (%d)', [n]), n >= 2);
end;

{ the gallery's seven SVG examples (their options as harvested) draw with
  their maps registered: the three this repository ships from
  examples/advchart/maps, the others from the echarts-examples checkout
  where it is on this machine }
procedure TAdvChartGeoSvgTest.TestTheGallerySvgExamplesDraw;
const
  cCases: array[0..6] of array[0..2] of string = (
    ('geo-beef-cuts', 'Beef_cuts_France', 'Beef_cuts_France.svg'),
    ('geo-svg-scatter-simple', 'iceland_svg', 'Map_of_Iceland.svg'),
    ('geo-svg-custom-effect', 'iceland_svg', 'Map_of_Iceland.svg'),
    ('geo-svg-map', 'sicily', 'Sicily_prehellenic_topographic_map.svg'),
    ('geo-seatmap-flight', 'flight-seats', 'flight-seats.svg'),
    ('geo-svg-lines', 'MacOdrum-LV5-floorplan-web', 'MacOdrum-LV5-floorplan-web.svg'),
    ('geo-svg-traffic', 'ksia-ext-plan', 'ksia-ext-plan-min.svg'));
var
  i, drawn: Integer;
  fn, opt: string;
  geo: TTyGeo;
begin
  drawn := 0;
  for i := 0 to High(cCases) do
  begin
    TyChartClearMaps;
    fn := RepoRoot + 'examples' + PathDelim + 'advchart' + PathDelim + 'maps' + PathDelim + cCases[i][2];
    if not FileExists(fn) then
      fn := 'D:\Projects\echarts-examples\public\data\asset\geo\' + cCases[i][2];
    if not FileExists(fn) then Continue;
    AssertTrue(cCases[i][0] + ' registers', TyChartRegisterMap(cCases[i][1], ReadUtf8(fn)));
    opt := ReadUtf8(RepoRoot + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery'
      + PathDelim + cCases[i][0] + '.json');
    NewChart(opt, 800, 600);
    geo := FChart.GeoLayout(0);
    if geo = nil then geo := FChart.MapGeoOf(0);
    AssertNotNull(cCases[i][0] + ': a geo', geo);
    AssertTrue(cCases[i][0] + ': an SVG geo laid out', geo.IsSvg and geo.Valid);
    AssertTrue(cCases[i][0] + ': elements drawn', FChart.List.Count > 0);
    Inc(drawn);
  end;
  AssertTrue('the shipped three at least', drawn >= 3);
end;

initialization
  RegisterTest(TAdvChartGeoSvgOracleTest);
  RegisterTest(TAdvChartGeoSvgTest);
end.
