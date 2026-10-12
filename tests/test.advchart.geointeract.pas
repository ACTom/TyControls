unit test.advchart.geointeract;
{$mode objfpc}{$H+}
{ THE GEO'S REGIONS AS THINGS A POINTER AND AN ACTION REACH, HELD TO
  UPSTREAM [Batch 148, D14 GE2].

  tools/advchart-oracle/geo-interact.js drives the real ECharts 6.1 build in
  node through zrender's own handler -- moves, clicks, leaving the canvas --
  and through dispatchAction (highlight, downplay, geoSelect,
  geoUnSelect, geoToggleSelect) and setOption, over a small hand-made map
  (squares, a hole, a line, a multipolygon, a name drawn twice), and records
  after every step the chart's mouse and action events, the shown tooltip
  and, per geo, every region group's flags and every compound path's and
  text's state list and current style; and at the start, what the hit test
  finds at a set of points.

  This replays the same steps through the control's own pointer path and
  DispatchAction / SetOption, paints after each (the frame applies the
  states), and compares: the events one by one, the tooltip's text, each
  group's flags, each path's state list, and the elements the list was built
  of -- fill, stroke, width, opacity, dash, z2, and the text's words, ink,
  opacity, z2, size and place. Where upstream's colour is one of GeoModel's
  tokens (or its lift) the port must hold the skin's ink (or its lift). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits, tyControls.Types, tyControls.StyleModel,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.Style, tyControls.AdvChart.States, tyControls.AdvChart.Color,
     tyControls.AdvChart.Tooltip,
     tyControls.AdvChart.Geo, tyControls.AdvanceChart;
type
  TGiProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Move(AX, AY: Integer);
    procedure ClickAt(AX, AY: Integer);
    procedure Leave;
  end;

  { the chart's events as lines, and the two formatters the options name }
  TGiLog = class
  public
    Lines: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
    function GeoTip(const AParams: TTyChartParams): string;
    function GeoLabel(const AParams: TTyChartParams): string;
  end;

  TAdvChartGeoInteractOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGiProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FLog: TGiLog;
    FInk: TTyGeoInk;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure Finish(const AWhat: string; AMin: Integer);
    procedure NewChart(const AOption: string);
    procedure Paint;
    procedure RegisterMaps;
    procedure SameColour(const AWhat: string; AHas: Boolean; AGot: TTyChartColor;
      AWant: TJSONData);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareTip(AWant: TJSONData);
    procedure CompareGeos(AWant: TJSONArray);
    procedure RunCase(ACase: TJSONObject; AProbesOnly: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryStepAsUpstream;
    procedure TestTheHitTestFindsWhatUpstreamFinds;
  end;

  TAdvChartGeoInteractTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGiProbe;
    FBmp: TBGRABitmap;
    procedure NewChart(const AOption: string);
    procedure Paint;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePathsAreWorkedOutOnce;
    procedure TestPathContainIsZrenders;
    procedure TestTheClipCutsOnlyWhereAsked;
    procedure TestTheRegionTooltipCascade;
    procedure TestTheSelectionOutlivesARender;
  end;

implementation

const
  cW = 600;
  cH = 400;
  { a square A and B beside it, the map the hand-written tests use }
  cSquares = '{"type":"FeatureCollection","features":['
    + '{"type":"Feature","properties":{"name":"A"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[10,0],[20,0],[20,10],[10,10],[10,0]]]}}]}';

{ ==================== the probe ==================== }

procedure TGiProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGiProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TGiProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TGiProbe.ClickAt(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
  MouseDown(mbLeft, [], AX, AY);
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TGiProbe.Leave;
begin
  MouseLeave;
end;

{ ==================== the log ==================== }

constructor TGiLog.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
end;

destructor TGiLog.Destroy;
begin
  Lines.Free;
  inherited Destroy;
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

{ a JSON text's value as the option wrote it: a string's own text }
function JsonStr(const AText: string): string;
var d: TJSONData;
begin
  d := GetJSON(AText);
  try
    if d.JSONType = jtString then Result := d.AsString else Result := d.AsJSON;
  finally
    d.Free;
  end;
end;

procedure TGiLog.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var p: TTyChartCallbackParams;
begin
  if AEvent.Payload <> '' then
  begin
    Lines.Add(AEvent.EventType + '|' + JsonForm(AEvent.Payload));
    Exit;
  end;
  p := AEvent.Params;
  if p.ComponentType <> 'geo' then
  begin
    Lines.Add(AEvent.EventType + '|' + p.ComponentType);
    Exit;
  end;
  { a geo event's geoIndex is its componentIndex }
  Lines.Add(Format('%s|geo|%d|%d|%s|%s', [AEvent.EventType, p.ComponentIndex,
    p.ComponentIndex, p.Name, p.Region]));
end;

function TGiLog.GeoTip(const AParams: TTyChartParams): string;
var u: string;
begin
  if AParams[0].SeriesIndex < 0 then u := 'u' else u := 'd';
  Result := AParams[0].ComponentType + '|' + IntToStr(AParams[0].ComponentIndex)
    + '|' + AParams[0].Name + '|' + u;
end;

function TGiLog.GeoLabel(const AParams: TTyChartParams): string;
begin
  Result := '<' + AParams[0].Name + ':' + AParams[0].Status + '>';
end;

{ ==================== helpers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-geo-interact.json';
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
end;

{ ==================== the oracle ==================== }

procedure TAdvChartGeoInteractOracleTest.SetUp;
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
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TGiLog.Create;
  TyChartRegisterFormatter('geoTip', @FLog.GeoTip);
  TyChartRegisterFormatter('geoLabel', @FLog.GeoLabel);
  FInk := InkOf(FCtl);
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FWhere := '';
end;

procedure TAdvChartGeoInteractOracleTest.TearDown;
begin
  TyChartUnregisterFormatter('geoTip');
  TyChartUnregisterFormatter('geoLabel');
  TyChartClearMaps;
  FChart.Free;
  FLog.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  FRoot.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoInteractOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartGeoInteractOracleTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not ((HexOf(AGot) = AHex) or (IsNan(AGot) and IsNan(FromHex(AHex)))) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartGeoInteractOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoInteractOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoInteractOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True),
    BoolToStr(AWant, True)]));
end;

procedure TAdvChartGeoInteractOracleTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartGeoInteractOracleTest.RegisterMaps;
var maps: TJSONArray; i: Integer;
begin
  TyChartClearMaps;
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    AssertTrue('registered', TyChartRegisterMap(maps.Objects[i].Strings['name'],
      maps.Objects[i].Strings['text']));
end;

procedure TAdvChartGeoInteractOracleTest.NewChart(const AOption: string);
const
  cTypes: array[0..10] of string = ('click', 'mouseover', 'mouseout', 'mousemove',
    'mousedown', 'mouseup', 'geoselectchanged', 'geoselected', 'geounselected',
    'highlight', 'downplay');
var i: Integer;
begin
  FreeAndNil(FChart);
  FChart := TGiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  { a clock of its own: no timer runs (every case hides at once) }
  FChart.TooltipNow := 0;
  for i := 0 to High(cTypes) do FChart.ChartOn(cTypes[i], @FLog.Handle);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  Paint;
  FLog.Lines.Clear;
end;

procedure TAdvChartGeoInteractOracleTest.Paint;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ upstream's colour string as the port must hold it: a token is the skin's
  ink, a token's lift its lift }
procedure TAdvChartGeoInteractOracleTest.SameColour(const AWhat: string;
  AHas: Boolean; AGot: TTyChartColor; AWant: TJSONData);
var
  tok: TJSONObject;
  s: string;
  want: TTyChartColor;
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType = jtNull) or (AWant.AsString = 'none') then
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
  else if s = tok.Strings['border'] then want := FInk.Border
  else if s = tok.Strings['label'] then want := FInk.LabelColour
  else if s = tok.Strings['highlight'] then want := FInk.HighlightFill
  else if s = tok.Strings['labelHighlight'] then want := FInk.LabelHighlight
  else if s = tok.Strings['liftedArea'] then want := TyChartLiftColor(FInk.AreaFill)
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

procedure TAdvChartGeoInteractOracleTest.CompareEvents(AWant: TJSONArray);
var
  want: TStringList;
  i: Integer;
  e: TJSONObject;
begin
  want := TStringList.Create;
  try
    for i := 0 to AWant.Count - 1 do
    begin
      e := AWant.Objects[i];
      if e.Find('json') <> nil then
        want.Add(e.Strings['type'] + '|' + JsonForm(e.Strings['json']))
      else if (e.Find('componentType') = nil) or (e.Find('componentType').JSONType = jtNull)
        or (e.Strings['componentType'] <> 'geo') then
      begin
        if (e.Find('componentType') = nil) or (e.Find('componentType').JSONType = jtNull) then
          want.Add(e.Strings['type'] + '|')
        else
          want.Add(e.Strings['type'] + '|' + e.Strings['componentType']);
      end
      else
        want.Add(Format('%s|geo|%d|%d|%s|%s', [e.Strings['type'],
          e.Integers['componentIndex'], e.Integers['geoIndex'], e.Strings['name'],
          e.Strings['region']]));
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

procedure TAdvChartGeoInteractOracleTest.CompareTip(AWant: TJSONData);
begin
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    SameBool('tooltip shown', FChart.TooltipShown, False);
    Exit;
  end;
  SameBool('tooltip shown', FChart.TooltipShown, True);
  SameStr('tooltip text', FChart.TooltipFormatterText, TJSONObject(AWant).Strings['text']);
end;

procedure TAdvChartGeoInteractOracleTest.CompareGeos(AWant: TJSONArray);
var
  gi, g, k, j: Integer;
  geo: TTyGeo;
  dr: TTyGeoDraw;
  grp, pw, lw: TJSONObject;
  groups, paths: TJSONArray;
  flags: TTyGeoGroupSt;
  it: TTyStItem;
  p: TTyGeoDrawPath;
  els: array of TTyChartElement;
  el: TTyChartElement;
  s: TTyStName;
  dash, text, where: string;
  hasSize: Boolean;
  d: TJSONData;

  function NextEl(out AEl: TTyChartElement): Boolean;
  begin
    Result := j <= High(els);
    if Result then
    begin
      AEl := els[j];
      Inc(j);
    end
    else
      Bad(where + ': no element left');
  end;

begin
  for gi := 0 to AWant.Count - 1 do
  begin
    geo := FChart.GeoLayout(gi);
    if AWant.Items[gi].JSONType = jtNull then
    begin
      Inc(FCompared);
      if (geo <> nil) and (geo.GroupCount > 0) then Bad(Format('geo %d draws, upstream not', [gi]));
      Continue;
    end;
    if geo = nil then
    begin
      Bad(Format('geo %d: none', [gi]));
      Continue;
    end;
    dr := geo.LastDraw;
    { this geo's elements, in the order they went in }
    els := nil;
    for k := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(k);
      if (el.Datum.Kind = ctkGeo) and (el.Datum.ComponentIndex = gi) then
      begin
        SetLength(els, Length(els) + 1);
        els[High(els)] := el;
      end;
    end;
    j := 0;
    groups := TJSONArray(AWant.Items[gi]);
    SameInt(Format('geo %d groups', [gi]), Length(dr.Groups), groups.Count);
    for g := 0 to Min(groups.Count, Length(dr.Groups)) - 1 do
    begin
      grp := groups.Objects[g];
      where := Format('geo %d %s', [gi, grp.Strings['name']]);
      SameStr(where + ' name', dr.Groups[g].Name, grp.Strings['name']);
      flags := geo.GroupFlags(g);
      SameInt(where + ' hover', flags.Hover, grp.Integers['hover']);
      SameInt(where + ' hbo', Integer(flags.Hbo), grp.Integers['hbo']);
      SameBool(where + ' selected', flags.Selected, grp.Booleans['selected']);
      paths := grp.Arrays['paths'];
      SameInt(where + ' paths', Length(dr.Groups[g].Paths), paths.Count);
      for k := 0 to Min(paths.Count, Length(dr.Groups[g].Paths)) - 1 do
      begin
        pw := paths.Objects[k];
        p := dr.Groups[g].Paths[k];
        it := geo.PathItem(g, k);
        where := Format('geo %d %s path %d', [gi, grp.Strings['name'], k]);
        SameStr(where + ' states', TyStNamesText(it.Host.States), pw.Strings['states']);
        if Length(p.Drawn) > 0 then
        begin
          if not NextEl(el) then Exit;
          SameInt(where + ' datum', el.Datum.DataIndex, g);
          SameColour(where + ' fill', el.Style.HasFill, el.Style.FillColor, pw.Find('fill'));
          SameColour(where + ' stroke', el.Style.StrokeWidthLogical > 0, el.Style.StrokeColor,
            pw.Find('stroke'));
          if pw.Find('lw').JSONType <> jtNull then
            Same(where + ' lineWidth', it.Host.Cur.Num[stkLineWidth], pw.Strings['lw']);
          if pw.Find('op').JSONType = jtNull then Same(where + ' opacity', el.Style.Alpha, HexOf(1))
          else Same(where + ' opacity', el.Style.Alpha, pw.Strings['op']);
          SameInt(where + ' z2', el.Z2, pw.Integers['z2']);
          { the dash as written: the normal one, a state's over it }
          dash := '';
          if p.Paint.DashHas then dash := p.Paint.DashRaw;
          for s := Low(TTyStName) to High(TTyStName) do
            if (s in it.Host.States) and p.StatePaint[s].DashHas then dash := p.StatePaint[s].DashRaw;
          d := pw.Find('dash');
          if d.JSONType = jtNull then SameStr(where + ' dash', dash, '')
          else SameStr(where + ' dash', dash, JsonStr(d.AsString));
        end;
        d := pw.Find('label');
        SameBool(where + ' a text', p.Lbl.Exists, d.JSONType <> jtNull);
        if (d.JSONType = jtNull) or not p.Lbl.Exists or not p.Lbl.HasPos then Continue;
        lw := TJSONObject(d);
        where := where + ' text';
        SameStr(where + ' states', TyStNamesText(it.Label_.States), lw.Strings['states']);
        if not NextEl(el) then Exit;
        SameBool(where + ' ignore', el.Ignore, lw.Booleans['ignore']);
        text := '';
        if lw.Find('text').JSONType <> jtNull then text := lw.Strings['text'];
        SameStr(where + ' words', el.Caption.Text, text);
        SameColour(where + ' ink', True, el.Caption.Colour, lw.Find('fill'));
        if lw.Find('op').JSONType = jtNull then Same(where + ' opacity', el.Style.Alpha, HexOf(1))
        else Same(where + ' opacity', el.Style.Alpha, lw.Strings['op']);
        SameInt(where + ' z2', el.Z2, lw.Integers['z2']);
        { the size: the option's where a level of the list writes one, else
          upstream's global 12 is the skin's }
        hasSize := p.Lbl.HasFontSize;
        for s := Low(TTyStName) to High(TTyStName) do
          if (s in it.Label_.States) and p.Lbl.States[s].HasFontSize then hasSize := True;
        if hasSize then
          Same(where + ' size', TyFontPxOf(el.Caption.FontSizeLogical),
            HexOf(lw.Integers['fontSize']))
        else
          SameInt(where + ' upstream''s size is the global one', lw.Integers['fontSize'], 12);
        { an ignored text is never placed upstream; the anchor is where the
          text's own origin lands (its transform's translation) }
        if lw.Find('tx').JSONType <> jtNull then
        begin
          Same(where + ' x', el.Caption.X, lw.Strings['tx']);
          Same(where + ' y', el.Caption.Y, lw.Strings['ty']);
          Same(where + ' rotation', el.Caption.RotationRad, lw.Strings['rot']);
        end;
      end;
    end;
    SameInt(Format('geo %d elements', [gi]), j, Length(els));
  end;
end;

procedure TAdvChartGeoInteractOracleTest.RunCase(ACase: TJSONObject; AProbesOnly: Boolean);
var
  steps, states, probes: TJSONArray;
  st, step: TJSONObject;
  i, x, y, el: Integer;
  dt: TTyChartDatumRef;
  hit: TJSONData;
  geo: TTyGeo;
  isLabel: Boolean;
  d: TJSONData;
begin
  RegisterMaps;
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Objects['option'].AsJSON);
  probes := ACase.Arrays['probes'];
  for i := 0 to probes.Count - 1 do
  begin
    x := probes.Objects[i].Arrays['px'].Integers[0];
    y := probes.Objects[i].Arrays['px'].Integers[1];
    hit := probes.Objects[i].Find('hit');
    dt := FChart.HitTestAt(x, y, el);
    FWhere := Format('%s probe %d (%d, %d)', [ACase.Strings['id'], i, x, y]);
    Inc(FCompared);
    if hit.JSONType = jtNull then
    begin
      if dt.Kind = ctkGeo then Bad('a region, upstream none');
      Continue;
    end;
    if dt.Kind <> ctkGeo then
    begin
      Bad('no region, upstream ' + TJSONObject(hit).Strings['name']);
      Continue;
    end;
    SameInt('geo', dt.ComponentIndex, TJSONObject(hit).Integers['geo']);
    geo := FChart.GeoLayout(dt.ComponentIndex);
    SameStr('name', geo.GroupName(dt.DataIndex), TJSONObject(hit).Strings['name']);
    isLabel := FChart.List.Element(el).Caption.Text <> '';
    SameBool('on the text', isLabel, TJSONObject(hit).Booleans['label']);
  end;
  if AProbesOnly then Exit;
  states := ACase.Arrays['states'];
  steps := ACase.Arrays['steps'];
  for i := 0 to states.Count - 1 do
  begin
    FWhere := Format('%s state %d', [ACase.Strings['id'], i]);
    if i > 0 then
    begin
      step := steps.Objects[i - 1];
      if step.Find('move') <> nil then
        FChart.Move(step.Arrays['move'].Integers[0], step.Arrays['move'].Integers[1])
      else if step.Find('click') <> nil then
        FChart.ClickAt(step.Arrays['click'].Integers[0], step.Arrays['click'].Integers[1])
      else if step.Find('leave') <> nil then
        FChart.Leave
      else if step.Find('action') <> nil then
        FChart.DispatchAction(step.Objects['action'].AsJSON)
      else if step.Find('setOption') <> nil then
      begin
        d := step.Find('notMerge');
        FChart.SetOption(step.Objects['setOption'].AsJSON, (d <> nil) and d.AsBoolean);
      end
      else
        Fail('an unknown step');
      Paint;
    end;
    st := states.Objects[i];
    CompareEvents(st.Arrays['events']);
    CompareTip(st.Find('tip'));
    CompareGeos(st.Arrays['geos']);
  end;
end;

procedure TAdvChartGeoInteractOracleTest.TestEveryStepAsUpstream;
var cases: TJSONArray; c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  AssertTrue('cases', cases.Count >= 16);
  for c := 0 to cases.Count - 1 do RunCase(cases.Objects[c], False);
  Finish('every step', 4000);
end;

procedure TAdvChartGeoInteractOracleTest.TestTheHitTestFindsWhatUpstreamFinds;
var cases: TJSONArray; c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do RunCase(cases.Objects[c], True);
  Finish('the probes', 20);
end;

{ ==================== by hand ==================== }

procedure TAdvChartGeoInteractTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue(TyChartRegisterMap('sq', cSquares));
end;

procedure TAdvChartGeoInteractTest.TearDown;
begin
  TyChartClearMaps;
  FChart.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoInteractTest.NewChart(const AOption: string);
begin
  FreeAndNil(FChart);
  FChart := TGiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.TooltipNow := 0;
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  Paint;
end;

procedure TAdvChartGeoInteractTest.Paint;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ The picture is worked out once per geo: a hover restyles the list, it
  does not build the paths again -- the same arrays, the states changed. }
procedure TAdvChartGeoInteractTest.TestThePathsAreWorkedOutOnce;
var
  geo: TTyGeo;
  before: Pointer;
  x, y: Integer;
  c: TTyGeoPt;
  px: TTyPointF;
begin
  NewChart('{"animation": false, "geo": {"map": "sq"}}');
  geo := FChart.GeoLayout(0);
  AssertNotNull(geo);
  before := Pointer(geo.LastDraw.Groups[0].Paths[0].Subs);
  AssertTrue('a picture', before <> nil);
  c := geo.RegionByName('A').GetCenter;
  AssertTrue(geo.PointOf(c.X, c.Y, px));
  x := Round(px.X);
  y := Round(px.Y);
  FChart.Move(x, y);
  Paint;
  AssertEquals('A in emphasis', 'emphasis', TyStNamesText(geo.PathItem(0, 0).Host.States));
  AssertTrue('the same paths', before = Pointer(geo.LastDraw.Groups[0].Paths[0].Subs));
  FChart.Leave;
  Paint;
  AssertEquals('A at rest', '', TyStNamesText(geo.PathItem(0, 0).Host.States));
  AssertTrue('still the same paths', before = Pointer(geo.LastDraw.Groups[0].Paths[0].Subs));
end;

{ contain/path.ts and contain/line.ts by hand: the nonzero winding over
  sub-paths (a hole wound the other way is out, one wound the same way is
  in), an edge is in, the stroke within half its width, the box first. }
procedure TAdvChartGeoInteractTest.TestPathContainIsZrenders;
var h: TTyPathHit;

  procedure Ring(AX0, AY0, AX1, AY1: Double; AReverse: Boolean);
  var n: Integer;
    procedure Add(AKind: TTyPathCmdKind; AX, AY: Double);
    begin
      SetLength(h.Cmds, n + 1);
      h.Cmds[n] := Default(TTyPathCmd);
      h.Cmds[n].Kind := AKind;
      h.Cmds[n].X := AX;
      h.Cmds[n].Y := AY;
      Inc(n);
    end;
  begin
    n := Length(h.Cmds);
    Add(pckMove, AX0, AY0);
    if AReverse then
    begin
      Add(pckLine, AX0, AY1);
      Add(pckLine, AX1, AY1);
      Add(pckLine, AX1, AY0);
    end
    else
    begin
      Add(pckLine, AX1, AY0);
      Add(pckLine, AX1, AY1);
      Add(pckLine, AX0, AY1);
    end;
    Add(pckClose, AX0, AY0);
  end;

begin
  h := Default(TTyPathHit);
  h.Active := True;
  h.Fill := True;
  h.Box := TyRectF(0, 0, 100, 100);
  Ring(0, 0, 100, 100, False);
  Ring(30, 30, 70, 70, True);
  AssertTrue('the ring', TyPathHitContains(h, 10, 10));
  AssertFalse('the hole', TyPathHitContains(h, 50, 50));
  { the right edge: only windingLine's own answer for a point on an edge
    (Infinity) puts it in -- the left edge would count the right one }
  AssertTrue('an edge', TyPathHitContains(h, 100, 50));
  AssertFalse('outside', TyPathHitContains(h, 150, 50));
  { the same direction: nonzero fills it }
  h.Cmds := nil;
  Ring(0, 0, 100, 100, False);
  Ring(30, 30, 70, 70, False);
  AssertTrue('a hole wound the same way is filled', TyPathHitContains(h, 50, 50));
  { a line: no fill, a stroke 5 wide }
  h.Cmds := nil;
  SetLength(h.Cmds, 2);
  h.Cmds[0] := Default(TTyPathCmd);
  h.Cmds[0].Kind := pckMove;
  h.Cmds[0].X := 50;
  h.Cmds[0].Y := 0;
  h.Cmds[1] := Default(TTyPathCmd);
  h.Cmds[1].Kind := pckLine;
  h.Cmds[1].X := 50;
  h.Cmds[1].Y := 100;
  h.Fill := False;
  h.StrokePx := 5;
  h.Box := TyRectF(47.5, -2.5, 52.5, 102.5);
  AssertTrue('2.5 px off the line', TyPathHitContains(h, 52.5, 50));
  AssertFalse('3 px off', TyPathHitContains(h, 53, 50));
  { the box comes first }
  h.Box := TyRectF(49, 0, 51, 100);
  AssertFalse('outside the box', TyPathHitContains(h, 52, 50));
end;

{ isHover asks the clip only where the element says so: everything else
  keeps being hit outside its clip, as the list always did. }
procedure TAdvChartGeoInteractTest.TestTheClipCutsOnlyWhereAsked;
var
  list: TTyPaintList;
  el: TTyChartElement;
begin
  list := TTyPaintList.Create;
  try
    el := TyChartElement(TyShapeRect(TyRectF(0, 0, 100, 100)));
    el.Silent := False;
    el.HasClip := True;
    el.ClipRect := TyRectF(0, 0, 50, 50);
    list.Add(el);
    AssertEquals('outside the clip, not asked: hit', 0, list.HitTestElement(75, 75, 96));
    el.ClipHits := True;
    list.SetElement(0, el);
    AssertEquals('outside the clip, asked: not hit', -1, list.HitTestElement(75, 75, 96));
    AssertEquals('inside the clip: hit', 0, list.HitTestElement(25, 25, 96));
  finally
    list.Free;
  end;
end;

{ The region's cascade: its own tooltip (a string a formatter), the geo's,
  the name's level -- so the global formatter never shows over a region --
  and the global component for the rest. }
procedure TAdvChartGeoInteractTest.TestTheRegionTooltipCascade;
var
  opt: TTyChartOption;
  spec: TTyTooltipSpec;
  tip: TJSONData;
begin
  opt := TTyChartOption.Create;
  tip := GetJSON('"R {a}"');
  try
    opt.SetOptionText('{"tooltip": {"formatter": "GLOBAL", "show": true},'
      + ' "geo": {"map": "sq", "tooltip": {"formatter": "G {a}", "showDelay": 7}}}');
    spec := TyTooltipSpecOfGeo(opt, 0, tip, 'A');
    AssertTrue('a component', spec.HasComponent);
    AssertEquals('the region''s string', 'R {a}', spec.Formatter);
    AssertEquals('the geo''s delay', 7, spec.ShowDelayMs);
    spec := TyTooltipSpecOfGeo(opt, 0, nil, 'A');
    AssertEquals('the geo''s formatter', 'G {a}', spec.Formatter);
    opt.SetOptionText('{"tooltip": {"formatter": "GLOBAL"}, "geo": {"map": "sq"}}');
    spec := TyTooltipSpecOfGeo(opt, 0, nil, 'A');
    AssertEquals('the name, never the global formatter', 'A', spec.Formatter);
    opt.SetOptionText('{"geo": {"map": "sq"}}');
    spec := TyTooltipSpecOfGeo(opt, 0, nil, 'A');
    AssertFalse('no component', spec.HasComponent);
  finally
    tip.Free;
    opt.Free;
  end;
end;

{ option.selectedMap is the model's: a render (a resize) makes new
  elements, the selection comes back on them (updateSelectStatus). }
procedure TAdvChartGeoInteractTest.TestTheSelectionOutlivesARender;
var geo: TTyGeo; g, gen: Integer;
begin
  NewChart('{"animation": false, "geo": {"map": "sq", "selectedMode": "multiple"}}');
  FChart.DispatchAction('{"type": "geoSelect", "name": "B"}');
  Paint;
  geo := FChart.GeoLayout(0);
  g := geo.GroupIndexOf('B');
  AssertTrue('B selected', geo.GroupFlags(g).Selected);
  AssertEquals('select', 'select', TyStNamesText(geo.PathItem(g, 0).Host.States));
  gen := geo.Gen;
  FChart.SetBounds(0, 0, cW - 100, cH - 50);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW - 100, cH - 50), 96);
  geo := FChart.GeoLayout(0);
  AssertTrue('a new render', geo.Gen <> gen);
  AssertTrue('the model still holds B', FChart.GeoSelected(0, 'B'));
  AssertTrue('and the new elements show it', geo.GroupFlags(geo.GroupIndexOf('B')).Selected);
  AssertEquals('select again', 'select',
    TyStNamesText(geo.PathItem(geo.GroupIndexOf('B'), 0).Host.States));
  AssertFalse('A not', FChart.GeoSelected(0, 'A'));
end;

initialization
  RegisterTest(TAdvChartGeoInteractOracleTest);
  RegisterTest(TAdvChartGeoInteractTest);
end.
