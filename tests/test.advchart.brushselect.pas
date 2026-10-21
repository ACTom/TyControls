unit test.advchart.brushselect;
{$mode objfpc}{$H+}
{ The brush component's selection -- held to upstream to the bit [Batch 127,
  C18].

  tools/advchart-oracle/brush-select.js runs the real ECharts 6.1 build
  through cases of pointer steps on zrender's own Handler, actions and
  merges, on a fake clock, and records after every step: each brush
  model's type, mode and areas; every series' item visuals (fill, opacity,
  symbol, symbolSize, liftZ) and what its view drew from them; the toolbox
  the brush preprocessor added, its brush buttons' statuses and places;
  the cursor; the inside dataZoom's window; and the brush / brushend /
  brushselected / globalcursortaken / axisareaselected events in order,
  brushselected with its whole batch (every brush, its areas, every series
  with the raw indices it selected).

  The port is driven the same way -- MouseMove / MouseDown / MouseUp,
  DispatchAction, SetOption -- on the same clock (BrushNow / BrushTick,
  DataZoomNow / DataZoomTick), with a headless render after each step. A
  click is part of the port's MouseUp: a mouseup's events and its click's
  are compared together, at the click. Compared through the chart's own
  API: BrushControllerOf, BrushModelAreas, VisualRow, the series list, the
  toolbox readers, GetOptionJson, DataZoomInsideRange, BrushCursorName and
  the chart events. The skin's colours stand in for upstream's two tokens:
  the out-of-brush grey is TyAdvChartBrushOut's. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Events, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Brush, tyControls.AdvanceChart.VisualMap,
     tyControls.AdvanceChart.Toolbox,
     tyControls.AdvanceChart;
type
  TBsProbe = class(TTyAdvanceChart)
  public
    Events: TStringList;
    { every event's type, and the one whose handler paints the chart first
      (a handler that repaints, as a ProcessMessages would) }
    AllEvents: TStringList;
    PaintOn: string;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
    function List: TTyPaintList;
    { the datum zrender's hover holds (its element is in emphasis) }
    function Hovers(ASeries, ARaw: Integer): Boolean;
  end;

  TAdvChartBrushSelectOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBsProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSteps, FStepNo: Integer;
    FReport, FName: string;
    FClock: Double;
    FOutCss: string;
    FOutColour: TTyVisualColor;
    { upstream's state carried forward: a record's null fields are the
      record before's }
    FSeries: array of TJSONData;
    FInitial: array of TJSONData;
    FToolbox, FOptions, FZoom: TJSONData;
    { the events not compared yet (a mouseup's wait for its click) }
    FUpEvents: TJSONArray;
    FEvSeen: Integer;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameJsonTree(const AWhat: string; AGot, AWant: TJSONData);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameRange(const AWhat: string; const AGot: TTyBrushRange;
      ALine: Boolean; AWant: TJSONData);
    procedure SameColour(const AWhat: string; const AGot: TTyVisualColor; AWant: TJSONData);
    procedure NewChart;
    procedure RenderNow;
    procedure Keep(var ASlot: TJSONData; AData: TJSONData);
    procedure CheckBrushes(ARec: TJSONObject);
    procedure CheckSeries;
    procedure CheckRow(ASeries: TJSONObject; ARow: TJSONObject; AInit: TJSONObject);
    procedure CheckDrawn(const AType: string; ASi, ARaw: Integer; ADrawn: TJSONData;
      ARow: TJSONObject);
    procedure CheckToolbox;
    procedure CheckOptions;
    procedure CheckZoom;
    procedure CheckEvents;
    procedure CheckBatch(const AWhat: string; AGot, AWant: TJSONObject);
    procedure CheckRecord(ARec: TJSONObject; AStep: TJSONObject; ANext: TJSONObject);
    procedure RunScenario(ASc: TJSONObject);
    procedure RunGroup(const APrefixes: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSelectorsAndTheirVisualsAsUpstream;
    procedure TestBrushLinkAsUpstream;
    procedure TestTheEventsAfterEveryActionAsUpstream;
    procedure TestTheToolboxButtonsAndThePreprocessorAsUpstream;
    procedure TestGlobalPanAndIrrelevantElementsAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartBrushSelectTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBsProbe;
    procedure Show(const AOption: string);
    procedure RenderNow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheBrushSelectedPayloadIsUpstreamsShape;
    procedure TestTheSelectorsOnTheirOwn;
    procedure TestThePolygonSelectorNearZero;
    procedure TestAnUndefinedOpacityDrawsAtOne;
    procedure TestBrushSelectedWaitsForTheActionsHandlers;
    procedure TestTheGlobalPanMutexHasOneHolder;
    procedure TestTheSelectBrushIsAController;
    procedure TestAnItemCanOptOut;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cEvTypes: array[0..4] of string = ('brush', 'brushend', 'brushselected',
    'globalcursortaken', 'axisareaselected');

function IsEvType(const S: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(cEvTypes) do
    if cEvTypes[i] = S then Exit(True);
  Result := False;
end;

{ ==================== the probe ==================== }

constructor TBsProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
  AllEvents := TStringList.Create;
  OnChartEvent := @OnEv;
end;

destructor TBsProbe.Destroy;
begin
  Events.Free;
  AllEvents.Free;
  inherited Destroy;
end;

procedure TBsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TBsProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TBsProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TBsProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TBsProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
var bmp: TBGRABitmap;
begin
  if (PaintOn <> '') and (AEvent.EventType = PaintOn) then
  begin
    bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
    try
      RenderTo(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    finally
      bmp.Free;
    end;
  end;
  AllEvents.Add(AEvent.EventType);
  if IsEvType(AEvent.EventType) then
    Events.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

function TBsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TBsProbe.Hovers(ASeries, ARaw: Integer): Boolean;
var e: TTyChartElement;
begin
  Result := False;
  if (EvHover.Id <= 0) or (EvHover.HdKind <> 1) or (EvHover.HdSeries <> ASeries) then Exit;
  if (SeriesList = nil) or (EvHover.Id - 1 >= SeriesList.Count) then Exit;
  e := SeriesList.Element(EvHover.Id - 1);
  Result := e.Datum.RawDataIndex = ARaw;
end;

{ ==================== the fixture's numbers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-brush-select.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  System.Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function Nul(const S: string): string;
begin
  Result := StringReplace(S, #0, '<NUL>', [rfReplaceAll]);
end;

function JStr(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := '(null)'
  else if AData.JSONType = jtString then Result := AData.AsString
  else Result := AData.AsJSON;
end;

{ a colour of the fixture packed as the paint list holds one }
function PackOf(AObj: TJSONData): TTyChartColor;
  function B(A: Double): Cardinal;
  begin
    Result := Cardinal(Floor(A + 0.5));
  end;
var o: TJSONObject;
begin
  if (AObj = nil) or (AObj.JSONType <> jtObject) then Exit(0);
  o := TJSONObject(AObj);
  Result := TTyChartColor((B(HexNum(o.Find('a')) * 255) shl 24)
    or (B(o.Integers['r']) shl 16) or (B(o.Integers['g']) shl 8) or B(o.Integers['b']));
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartBrushSelectOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FOutCss := TJSONObject(FRoot).Strings['outOfBrushDefault'];
  FOutColour := TyVisualFromChart(TTyChartColor(
    FCtl.Model.ResolveStyle('TyAdvChartBrushOut', '', []).TextColor));
  FBad := 0;
  FCompared := 0;
  FSteps := 0;
  FReport := '';
end;

procedure TAdvChartBrushSelectOracleTest.TearDown;
var i: Integer;
begin
  for i := 0 to High(FSeries) do FreeAndNil(FSeries[i]);
  for i := 0 to High(FInitial) do FreeAndNil(FInitial[i]);
  FSeries := nil;
  FInitial := nil;
  FreeAndNil(FToolbox);
  FreeAndNil(FOptions);
  FreeAndNil(FZoom);
  FreeAndNil(FUpEvents);
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartBrushSelectOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if (FBad <= 400) and (Pos(FName + ': ' + AWhat, FReport) = 0) then
    FReport := FReport + LineEnding + '  ' + FName + ' @' + IntToStr(FStepNo) + ': ' + AWhat;
end;

procedure TAdvChartBrushSelectOracleTest.SameHex(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double; ok: Boolean;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else ok := AGot = want;
  if not ok then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartBrushSelectOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartBrushSelectOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

procedure TAdvChartBrushSelectOracleTest.SameRange(const AWhat: string;
  const AGot: TTyBrushRange; ALine: Boolean; AWant: TJSONData);
var i: Integer;
begin
  if (AWant = nil) or (AWant.JSONType = jtNull) then Exit;
  if ALine then
  begin
    SameStr(AWhat + ' length', IntToStr(Length(AGot) * 2), IntToStr(AWant.Count));
    if (Length(AGot) = 1) and (AWant.Count = 2) then
    begin
      SameHex(AWhat + '[0]', AGot[0][0], AWant.Items[0]);
      SameHex(AWhat + '[1]', AGot[0][1], AWant.Items[1]);
    end;
    Exit;
  end;
  SameStr(AWhat + ' length', IntToStr(Length(AGot)), IntToStr(AWant.Count));
  for i := 0 to Min(Length(AGot), AWant.Count) - 1 do
  begin
    SameHex(Format('%s[%d][0]', [AWhat, i]), AGot[i][0], AWant.Items[i].Items[0]);
    SameHex(Format('%s[%d][1]', [AWhat, i]), AGot[i][1], AWant.Items[i].Items[1]);
  end;
end;

{ upstream's colour, its default out-of-brush grey the skin's }
procedure TAdvChartBrushSelectOracleTest.SameColour(const AWhat: string;
  const AGot: TTyVisualColor; AWant: TJSONData);
var
  o: TJSONObject;
  ok: Boolean;
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType <> jtObject) then
  begin
    if AGot.Defined then Miss(AWhat + ' is undefined upstream, defined here');
    Exit;
  end;
  o := TJSONObject(AWant);
  if o.Strings['css'] = FOutCss then
    ok := AGot.Defined and (AGot.R = FOutColour.R) and (AGot.G = FOutColour.G)
      and (AGot.B = FOutColour.B) and (AGot.A = FOutColour.A)
  else
    ok := AGot.Defined and (AGot.R = o.Integers['r']) and (AGot.G = o.Integers['g'])
      and (AGot.B = o.Integers['b']) and (AGot.A = HexNum(o.Find('a')));
  if not ok then
    Miss(Format('%s is %s upstream, rgba(%s,%s,%s,%s) here', [AWhat, o.Strings['css'],
      Fmt(AGot.R), Fmt(AGot.G), Fmt(AGot.B), Fmt(AGot.A)]));
end;

procedure TAdvChartBrushSelectOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TBsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
end;

procedure TAdvChartBrushSelectOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartBrushSelectOracleTest.Keep(var ASlot: TJSONData; AData: TJSONData);
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  FreeAndNil(ASlot);
  ASlot := AData.Clone;
end;

{ each brush model: its type (the controller's while it is on), its mode,
  its areas }
procedure TAdvChartBrushSelectOracleTest.CheckBrushes(ARec: TJSONObject);
var
  bs: TJSONArray;
  b, k: Integer;
  w, a: TJSONObject;
  ctl: TTyBrushController;
  areas: TTyBrushAreaArray;
  en, what: string;
  d: TJSONData;
begin
  bs := ARec.Arrays['brushes'];
  SameStr('the brush count', IntToStr(FChart.BrushCount), IntToStr(bs.Count));
  for b := 0 to Min(bs.Count, FChart.BrushCount) - 1 do
  begin
    w := bs.Objects[b];
    what := Format('brush %d', [b]);
    ctl := FChart.BrushControllerOf(b);
    if ctl = nil then
    begin
      Miss(what + ' has no controller');
      Continue;
    end;
    if ctl.Enabled then en := TyBrushTypeName(ctl.Opt.BrushType) else en := '(null)';
    SameStr(what + ' type', en, JStr(w.Find('brushType')));
    d := w.Find('brushMode');
    if ctl.Enabled and (d <> nil) and (d.JSONType = jtString) then
      SameBool(what + ' multiple', ctl.Opt.Multiple, d.AsString = 'multiple');
    areas := FChart.BrushModelAreas(b);
    SameStr(what + ' area count', IntToStr(Length(areas)), IntToStr(w.Arrays['areas'].Count));
    for k := 0 to Min(Length(areas), w.Arrays['areas'].Count) - 1 do
    begin
      a := w.Arrays['areas'].Objects[k];
      SameStr(Format('%s area %d type', [what, k]), TyBrushTypeName(areas[k].Opt.BrushType),
        a.Strings['brushType']);
      if a.Find('panelId').JSONType = jtString then
        SameStr(Format('%s area %d panel', [what, k]), Nul(areas[k].Opt.PanelId), a.Strings['panelId']);
      SameRange(Format('%s area %d range', [what, k]), areas[k].Opt.Range,
        areas[k].Opt.BrushType in [btLineX, btLineY], a.Find('range'));
    end;
  end;
end;

{ the element a datum's view drew, by its role }
procedure TAdvChartBrushSelectOracleTest.CheckDrawn(const AType: string; ASi, ARaw: Integer;
  ADrawn: TJSONData; ARow: TJSONObject);
var
  lst: TTyPaintList;
  k, found: Integer;
  e, el: TTyChartElement;
  role: TTyChartAnimRole;
  o: TJSONObject;
  want: TTyChartColor;
  alpha: Double;
  what: string;
begin
  if AType = 'scatter' then role := carSymbol
  else if AType = 'effectScatter' then role := carEffectSymbol
  else if AType = 'line' then role := carLineSymbol
  else if AType = 'bar' then role := carBar
  else if AType = 'candlestick' then role := carCandleBody
  else Exit;
  lst := FChart.List;
  if lst = nil then Exit;
  found := 0;
  el := Default(TTyChartElement);
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if e.Datum.IsEdge or (e.Datum.SeriesIndex <> ASi) or (e.Datum.RawDataIndex <> ARaw)
      or (e.Datum.DataIndex < 0) or (e.Anim.Role <> role) then Continue;
    Inc(found);
    el := e;
  end;
  what := Format('s%d row %d drawn', [ASi, ARaw]);
  { an element in a state is not compared: the hovered one here, one
    upstream holds in a state there }
  if FChart.Hovers(ASi, ARaw) then Exit;
  if (ADrawn is TJSONObject) and (TJSONObject(ADrawn).Find('states') <> nil) then Exit;
  { NOR ONE UPSTREAM DRAWS STALE: an element re-rendered while in a state
    keeps the old visual in its normal state, and leaving the state
    restores it -- the element then shows a fill its own visual no longer
    has (a bar the hover left; not ported) }
  if (AType <> 'line') and (ADrawn is TJSONObject)
    and (TJSONObject(ADrawn).Find('fill') is TJSONObject) and (ARow.Find('fill') is TJSONObject)
    and (TJSONObject(ADrawn).Objects['fill'].Strings['css'] <> ARow.Objects['fill'].Strings['css']) then
    Exit;
  if (ADrawn = nil) or (ADrawn.JSONType <> jtObject) then
  begin
    SameStr(what + ' (none upstream)', IntToStr(found), '0');
    Exit;
  end;
  SameStr(what + ' element count', IntToStr(found), '1');
  if found <> 1 then Exit;
  o := TJSONObject(ADrawn);
  { the fill: upstream's colour, its default grey the skin's }
  if (o.Find('fill') is TJSONObject) and (o.Objects['fill'].Strings['css'] = FOutCss) then
    want := TyVisualToChart(FOutColour)
  else
    want := PackOf(o.Find('fill'));
  Inc(FCompared);
  if el.Style.FillColor <> want then
    Miss(Format('%s fill $%.8x here, $%.8x upstream (%s)', [what, el.Style.FillColor, want,
      JStr(TJSONObject(o.Find('fill')).Find('css'))]));
  if o.Find('opacity').JSONType = jtNull then alpha := 1
  else alpha := HexNum(o.Find('opacity'));
  Inc(FCompared);
  if el.Style.Alpha <> alpha then
    Miss(Format('%s opacity %s here, %s upstream', [what, Fmt(el.Style.Alpha), Fmt(alpha)]));
  { a scatter's symbol: its scale, half its size }
  if ((AType = 'scatter') or (AType = 'effectScatter')) and (o.Find('scaleX') <> nil) then
    SameHex(what + ' scaleX', el.Anim.G[2], o.Find('scaleX'));
end;

procedure TAdvChartBrushSelectOracleTest.CheckRow(ASeries: TJSONObject; ARow: TJSONObject;
  AInit: TJSONObject);
var
  si, raw: Integer;
  vr: TTyVisualRow;
  has: Boolean;
  what: string;
  d, sz: TJSONData;

  function InitOf(const AKey: string): string;
  begin
    { a row the initial record did not hold (a dataZoom let it in since):
      what upstream holds is taken as is }
    if AInit = nil then Exit(JStr(ARow.Find(AKey)));
    Result := JStr(AInit.Find(AKey));
  end;

begin
  si := ASeries.Integers['index'];
  raw := ARow.Integers['raw'];
  what := Format('s%d row %d', [si, raw]);
  has := FChart.VisualRow(si, raw, vr);
  if not has then vr := Default(TTyVisualRow);
  { what the brush wrote is the port's row; what it did not write is what
    upstream holds before any brush }
  if vr.ColorSet then SameColour(what + ' fill', vr.Color, ARow.Find('fill'))
  else SameStr(what + ' fill (unwritten)', JStr(ARow.Find('fill')), InitOf('fill'));
  d := ARow.Find('opacity');
  if vr.OpacitySet then
  begin
    if (d = nil) or (d.JSONType = jtNull) then
    begin
      Inc(FCompared);
      if vr.Opacity <> 1 then Miss(what + ' opacity: undefined upstream, ' + Fmt(vr.Opacity) + ' here');
    end
    else
      SameHex(what + ' opacity', vr.Opacity, d);
  end
  else
    SameStr(what + ' opacity (unwritten)', JStr(d), InitOf('opacity'));
  if vr.SymbolSet then SameStr(what + ' symbol', vr.Symbol, JStr(ARow.Find('symbol')))
  else SameStr(what + ' symbol (unwritten)', JStr(ARow.Find('symbol')), InitOf('symbol'));
  sz := ARow.Find('symbolSize');
  if vr.SizeSet then
  begin
    if sz is TJSONArray then sz := sz.Items[0];
    SameHex(what + ' symbolSize', vr.Size, sz);
  end
  else
    SameStr(what + ' symbolSize (unwritten)', JStr(sz), InitOf('symbolSize'));
  d := ARow.Find('liftZ');
  SameBool(what + ' liftZ written', vr.LiftZSet, (d <> nil) and (d.JSONType <> jtNull));
  if vr.LiftZSet and (d <> nil) and (d.JSONType <> jtNull) then
    SameHex(what + ' liftZ', vr.LiftZ, d);
  { what is drawn, where the brush wrote the row }
  if vr.LateColor or vr.LateOpacity or vr.SizeSet or vr.SymbolSet or vr.LiftZSet then
    CheckDrawn(ASeries.Strings['type'], si, raw, ARow.Find('drawn'), ARow);
end;

procedure TAdvChartBrushSelectOracleTest.CheckSeries;
var
  k, i, j: Integer;
  s, init: TJSONObject;
  rows, irows: TJSONArray;
  ir: TJSONObject;
begin
  for k := 0 to High(FSeries) do
  begin
    if FSeries[k] = nil then Continue;
    s := TJSONObject(FSeries[k]);
    if s.Booleans['filtered'] then Continue;
    init := nil;
    if (k <= High(FInitial)) and (FInitial[k] <> nil) then init := TJSONObject(FInitial[k]);
    rows := s.Arrays['rows'];
    for i := 0 to rows.Count - 1 do
    begin
      ir := nil;
      if init <> nil then
      begin
        irows := init.Arrays['rows'];
        for j := 0 to irows.Count - 1 do
          if irows.Objects[j].Integers['raw'] = rows.Objects[i].Integers['raw'] then
            ir := irows.Objects[j];
      end;
      CheckRow(s, rows.Objects[i], ir);
    end;
  end;
end;

{ the brush feature's buttons: status, title, rect }
procedure TAdvChartBrushSelectOracleTest.CheckToolbox;
var
  arr: TJSONArray;
  i, t, k, found: Integer;
  ic: TJSONObject;
  spec: TTyToolboxSpec;
  lay: TTyToolboxLayout;
  what, st: string;
begin
  if not (FToolbox is TJSONArray) then Exit;
  arr := TJSONArray(FToolbox);
  for i := 0 to arr.Count - 1 do
  begin
    ic := arr.Objects[i];
    if ic.Strings['feature'] <> 'brush' then Continue;
    t := ic.Integers['toolbox'];
    what := Format('toolbox %d brush.%s', [t, ic.Strings['name']]);
    st := JStr(ic.Find('status'));
    if st = '(null)' then st := '';
    SameStr(what + ' status', FChart.ToolboxIconStatus(t, 'brush', ic.Strings['name']), st);
    if t >= FChart.ToolboxCount then
    begin
      Miss(what + ': no toolbox here');
      Continue;
    end;
    spec := FChart.ToolboxSpec(t);
    lay := FChart.ToolboxLayout(t);
    found := -1;
    for k := 0 to High(spec.Icons) do
      if (spec.Icons[k].Feature = 'brush') and (spec.Icons[k].Name = ic.Strings['name']) then found := k;
    if found < 0 then
    begin
      Miss(what + ': no such icon here');
      Continue;
    end;
    SameStr(what + ' title', spec.Icons[found].Title, JStr(ic.Find('title')));
    SameHex(what + ' x', lay.GroupX + spec.Icons[found].X + spec.Icons[found].Rect.X,
      ic.Arrays['rect'].Items[0]);
    SameHex(what + ' y', lay.GroupY + spec.Icons[found].Y + spec.Icons[found].Rect.Y,
      ic.Arrays['rect'].Items[1]);
    SameHex(what + ' width', spec.Icons[found].Rect.W, ic.Arrays['rect'].Items[2]);
    SameHex(what + ' height', spec.Icons[found].Rect.H, ic.Arrays['rect'].Items[3]);
  end;
  { no brush icon here that upstream has not }
  found := 0;
  for t := 0 to FChart.ToolboxCount - 1 do
  begin
    spec := FChart.ToolboxSpec(t);
    for k := 0 to High(spec.Icons) do
      if spec.Icons[k].Feature = 'brush' then Inc(found);
  end;
  k := 0;
  for i := 0 to arr.Count - 1 do
    if arr.Objects[i].Strings['feature'] = 'brush' then Inc(k);
  SameStr('the brush icon count', IntToStr(found), IntToStr(k));
end;

{ getOption's toolboxes: the preprocessor's work }
procedure TAdvChartBrushSelectOracleTest.CheckOptions;
var
  want, tb: TJSONArray;
  got, d, f, ty: TJSONData;
  i: Integer;
  w: TJSONObject;
  names, types, types2: string;
  k: Integer;
begin
  if not (FOptions is TJSONObject) then Exit;
  want := TJSONObject(FOptions).Arrays['toolbox'];
  got := GetJSON(FChart.GetOptionJson);
  try
    tb := nil;
    if got is TJSONObject then
    begin
      d := TJSONObject(got).Find('toolbox');
      if d is TJSONArray then tb := TJSONArray(d)
      else if d is TJSONObject then
      begin
        { one toolbox written as an object: as a list of one }
        TJSONObject(got).Add('__toolboxes', TJSONArray.Create([d.Clone]));
        tb := TJSONObject(got).Arrays['__toolboxes'];
      end;
    end;
    if tb = nil then
    begin
      SameStr('the toolbox count', '0', IntToStr(want.Count));
      Exit;
    end;
    SameStr('the toolbox count', IntToStr(tb.Count), IntToStr(want.Count));
    for i := 0 to Min(tb.Count, want.Count) - 1 do
    begin
      w := want.Objects[i];
      names := '';
      types := '(null)';
      f := nil;
      if tb.Items[i] is TJSONObject then f := TJSONObject(tb.Items[i]).Find('feature');
      if f is TJSONObject then
      begin
        for k := 0 to f.Count - 1 do names := names + TJSONObject(f).Names[k] + ',';
        d := TJSONObject(f).Find('brush');
        if d is TJSONObject then
        begin
          ty := TJSONObject(d).Find('type');
          if ty is TJSONArray then
          begin
            types := '';
            for k := 0 to ty.Count - 1 do types := types + JStr(ty.Items[k]) + ',';
          end;
        end;
      end;
      d := w.Find('features');
      types2 := '';
      for k := 0 to d.Count - 1 do types2 := types2 + JStr(d.Items[k]) + ',';
      SameStr(Format('toolbox %d features', [i]), names, types2);
      d := w.Find('brushType');
      if (d = nil) or (d.JSONType = jtNull) then
        SameStr(Format('toolbox %d brush types', [i]), types, '(null)')
      else
      begin
        names := '';
        for k := 0 to d.Count - 1 do names := names + JStr(d.Items[k]) + ',';
        SameStr(Format('toolbox %d brush types', [i]), types, names);
      end;
    end;
  finally
    got.Free;
  end;
end;

{ an inside dataZoom's window }
procedure TAdvChartBrushSelectOracleTest.CheckZoom;
var
  arr: TJSONArray;
  i: Integer;
  lo, hi: Double;
begin
  if not (FZoom is TJSONArray) then Exit;
  arr := TJSONArray(FZoom);
  for i := 0 to arr.Count - 1 do
    if FChart.DataZoomInsideRange(i, lo, hi) then
    begin
      SameHex(Format('dataZoom %d start', [i]), lo, arr.Objects[i].Find('start'));
      SameHex(Format('dataZoom %d end', [i]), hi, arr.Objects[i].Find('end'));
    end;
end;

{ two JSON values alike: the same keys in the same order, numbers equal,
  the skin's default brush colours (a brushStyle's fill and stroke) set
  aside -- the scenarios write none [milestone D5-D8] }
function KeysOf(AObj: TJSONObject): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to AObj.Count - 1 do Result := Result + AObj.Names[i] + ',';
end;

procedure TAdvChartBrushSelectOracleTest.SameJsonTree(const AWhat: string; AGot, AWant: TJSONData);
var
  i: Integer;
  go, wo: TJSONObject;
  nm: string;
begin
  if (AGot = nil) or (AWant = nil) then
  begin
    if (AGot = nil) <> (AWant = nil) then Miss(AWhat + ': missing');
    Exit;
  end;
  { a number that is not finite: the oracle writes an object with $num,
    an event's JSON text null (JSON.stringify) }
  if (AGot.JSONType = jtNull) and (AWant is TJSONObject)
    and (TJSONObject(AWant).IndexOfName('$num') >= 0) then Exit;
  if (AWant.JSONType = jtNumber) and (AGot.JSONType = jtNumber) then
  begin
    if AGot.AsFloat <> AWant.AsFloat then
      Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, AWant.AsJSON]));
    Exit;
  end;
  if AGot.JSONType <> AWant.JSONType then
  begin
    Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, AWant.AsJSON]));
    Exit;
  end;
  case AWant.JSONType of
    jtArray:
      begin
        if AGot.Count <> AWant.Count then
        begin
          Miss(Format('%s: %d items here, %d upstream', [AWhat, AGot.Count, AWant.Count]));
          Exit;
        end;
        for i := 0 to AWant.Count - 1 do
          SameJsonTree(Format('%s[%d]', [AWhat, i]), AGot.Items[i], AWant.Items[i]);
      end;
    jtObject:
      begin
        go := TJSONObject(AGot);
        wo := TJSONObject(AWant);
        nm := '';
        for i := 0 to go.Count - 1 do nm := nm + go.Names[i] + ',';
        SameStr(AWhat + ' keys', nm, KeysOf(wo));
        if nm <> KeysOf(wo) then Exit;
        for i := 0 to wo.Count - 1 do
        begin
          if ((wo.Names[i] = 'fill') or (wo.Names[i] = 'stroke'))
            and (Pos('brushStyle', AWhat) > 0) then Continue;
          SameJsonTree(AWhat + '.' + wo.Names[i], go.Items[i], wo.Items[i]);
        end;
      end;
  else
    if AGot.AsJSON <> AWant.AsJSON then
      Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, AWant.AsJSON]));
  end;
end;

procedure TAdvChartBrushSelectOracleTest.CheckBatch(const AWhat: string; AGot, AWant: TJSONObject);
var
  gb, wb, gs, ws, ga, wa: TJSONArray;
  b, s, k: Integer;
  gi, wi, g1, w1: TJSONObject;
  what: string;
  rg: TTyBrushRange;
  ln: Boolean;
  d: TJSONData;
begin
  gb := AGot.Arrays['batch'];
  wb := AWant.Arrays['batch'];
  SameStr(AWhat + ' batch', IntToStr(gb.Count), IntToStr(wb.Count));
  for b := 0 to Min(gb.Count, wb.Count) - 1 do
  begin
    gi := gb.Objects[b];
    wi := wb.Objects[b];
    what := Format('%s brush %d', [AWhat, b]);
    SameStr(what + ' index', IntToStr(gi.Integers['brushIndex']), IntToStr(wi.Integers['brushIndex']));
    SameStr(what + ' id', gi.Strings['brushId'], wi.Strings['brushId']);
    SameStr(what + ' name', gi.Strings['brushName'], JStr(wi.Find('brushName')));
    SameStr(what + ' item type', gi.Strings['type'], 'brushselected');
    ga := gi.Arrays['areas'];
    wa := wi.Arrays['areas'];
    SameStr(what + ' areas', IntToStr(ga.Count), IntToStr(wa.Count));
    for k := 0 to Min(ga.Count, wa.Count) - 1 do
    begin
      SameStr(Format('%s area %d type', [what, k]), ga.Objects[k].Strings['brushType'],
        wa.Objects[k].Strings['brushType']);
      ln := (wa.Objects[k].Strings['brushType'] = 'lineX') or (wa.Objects[k].Strings['brushType'] = 'lineY');
      d := ga.Objects[k].Find('range');
      rg := nil;
      if d is TJSONArray then
      begin
        if ln then
        begin
          SetLength(rg, 1);
          rg[0][0] := d.Items[0].AsFloat;
          rg[0][1] := d.Items[1].AsFloat;
        end
        else
        begin
          SetLength(rg, d.Count);
          for s := 0 to d.Count - 1 do
          begin
            rg[s][0] := d.Items[s].Items[0].AsFloat;
            rg[s][1] := d.Items[s].Items[1].AsFloat;
          end;
        end;
      end;
      SameRange(Format('%s area %d range', [what, k]), rg, ln, wa.Objects[k].Find('range'));
    end;
    { and every key of every area, in order [milestone D5-D8] }
    if wi.Find('areasFull') is TJSONArray then
      SameJsonTree(what + ' areas', ga, wi.Arrays['areasFull']);
    gs := gi.Arrays['selected'];
    ws := wi.Arrays['selected'];
    SameStr(what + ' selected series', IntToStr(gs.Count), IntToStr(ws.Count));
    for s := 0 to Min(gs.Count, ws.Count) - 1 do
    begin
      g1 := gs.Objects[s];
      w1 := ws.Objects[s];
      SameStr(Format('%s series %d index', [what, s]), IntToStr(g1.Integers['seriesIndex']),
        IntToStr(w1.Integers['seriesIndex']));
      SameStr(Format('%s series %d id', [what, s]), g1.Strings['seriesId'], JStr(w1.Find('seriesId')));
      SameStr(Format('%s series %d name', [what, s]), g1.Strings['seriesName'], JStr(w1.Find('seriesName')));
      SameStr(Format('%s series %d dataIndex', [what, s]), g1.Arrays['dataIndex'].AsJSON,
        w1.Arrays['dataIndex'].AsJSON);
    end;
  end;
end;

{ the events since the last compare, in order: types, then each one's
  payload }
procedure TAdvChartBrushSelectOracleTest.CheckEvents;
var
  i, n: Integer;
  t, pl: string;
  e: TJSONObject;
  pj: TJSONData;
  ga, wa: TJSONArray;
  k: Integer;
begin
  n := FChart.Events.Count - FEvSeen;
  SameStr('the event count', IntToStr(n), IntToStr(FUpEvents.Count));
  for i := 0 to Min(n, FUpEvents.Count) - 1 do
  begin
    t := FChart.Events[FEvSeen + i];
    pl := Copy(t, Pos(#9, t) + 1, MaxInt);
    t := Copy(t, 1, Pos(#9, t) - 1);
    e := FUpEvents.Objects[i];
    SameStr(Format('event %d type', [i]), t, e.Strings['type']);
    if t <> e.Strings['type'] then Continue;
    pj := nil;
    try
      try
        pj := GetJSON(StringReplace(pl, '\u0000', '<NUL>', [rfReplaceAll]));
      except
        pj := nil;
      end;
      SameBool(t + ' payload parses', pj is TJSONObject, True);
      if not (pj is TJSONObject) then Continue;
      if t = 'brushselected' then
        CheckBatch(Format('event %d', [i]), TJSONObject(pj), e)
      else if ((t = 'brush') or (t = 'brushend')) and (e.Find('areas') is TJSONArray) then
      begin
        ga := nil;
        if TJSONObject(pj).Find('areas') is TJSONArray then ga := TJSONObject(pj).Arrays['areas'];
        wa := e.Arrays['areas'];
        if ga = nil then
        begin
          Miss(t + ' has no areas here');
          Continue;
        end;
        SameStr(t + ' area count', IntToStr(ga.Count), IntToStr(wa.Count));
        for k := 0 to Min(ga.Count, wa.Count) - 1 do
          SameStr(Format('%s area %d type', [t, k]), ga.Objects[k].Strings['brushType'],
            wa.Objects[k].Strings['brushType']);
        { and every key of every area, in order [milestone D5-D8] }
        if e.Find('areasFull') is TJSONArray then
          SameJsonTree(t + ' areas', ga, e.Arrays['areasFull']);
      end
      else if t = 'globalcursortaken' then
      begin
        SameStr(t + ' key', JStr(TJSONObject(pj).Find('key')), JStr(e.Find('key')));
        if (e.Find('brushOption') is TJSONObject)
          and (TJSONObject(pj).Find('brushOption') is TJSONObject) then
        begin
          if e.Objects['brushOption'].Find('brushType') <> nil then
            SameStr(t + ' brushType', JStr(TJSONObject(pj).Objects['brushOption'].Find('brushType')),
              JStr(e.Objects['brushOption'].Find('brushType')));
          if e.Objects['brushOption'].Find('brushMode') <> nil then
            SameStr(t + ' brushMode', JStr(TJSONObject(pj).Objects['brushOption'].Find('brushMode')),
              JStr(e.Objects['brushOption'].Find('brushMode')));
        end;
      end;
    finally
      pj.Free;
    end;
  end;
  FEvSeen := FChart.Events.Count;
  FUpEvents.Clear;
end;

procedure TAdvChartBrushSelectOracleTest.CheckRecord(ARec: TJSONObject; AStep: TJSONObject;
  ANext: TJSONObject);
var
  d: TJSONData;
  k, idx: Integer;
  cur, want: string;
  wait: Boolean;
begin
  d := ARec.Find('series');
  if d is TJSONArray then
    for k := 0 to d.Count - 1 do
      if d.Items[k] is TJSONObject then
      begin
        idx := TJSONObject(d.Items[k]).Integers['index'];
        if Length(FSeries) <= idx then SetLength(FSeries, idx + 1);
        Keep(FSeries[idx], d.Items[k]);
        if AStep = nil then
        begin
          if Length(FInitial) <= idx then SetLength(FInitial, idx + 1);
          Keep(FInitial[idx], d.Items[k]);
        end;
      end;
  Keep(FToolbox, ARec.Find('toolbox'));
  Keep(FOptions, ARec.Find('options'));
  Keep(FZoom, ARec.Find('zoom'));
  { A MOUSEUP FOLLOWED BY ITS CLICK is one release here: the click's work
    (a toolbox button's) is done by the port's mouseup -- the two are
    compared at the click }
  wait := (AStep <> nil) and (AStep.Strings['type'] = 'mouseup') and (ANext <> nil)
    and (ANext.Strings['type'] = 'click');
  if not wait then
  begin
    CheckBrushes(ARec);
    CheckSeries;
    CheckToolbox;
    CheckOptions;
    CheckZoom;
  end;
  { the cursor of a move: the brush's own words, else none of the brush's }
  if (AStep <> nil) and (AStep.Strings['type'] = 'mousemove') then
  begin
    want := JStr(ARec.Find('cursor'));
    cur := FChart.BrushCursorName;
    if (want = 'crosshair') or (want = 'move') or (Pos('-resize', want) > 0) then
      SameStr('the cursor', cur, want)
    else
      SameStr('the cursor (not the brush''s: ' + want + ')', cur, '');
  end;
  { the events: a mouseup's wait for its click }
  d := ARec.Find('events');
  if d is TJSONArray then
    for k := 0 to d.Count - 1 do
      if IsEvType(TJSONObject(d.Items[k]).Strings['type']) then
        FUpEvents.Add(d.Items[k].Clone);
  if not wait then CheckEvents;
end;

procedure TAdvChartBrushSelectOracleTest.RunScenario(ASc: TJSONObject);
var
  steps: TJSONArray;
  st, rec, nx: TJSONObject;
  i, k: Integer;
  typ: string;
begin
  FName := ASc.Strings['id'];
  NewChart;
  for k := 0 to High(FSeries) do FreeAndNil(FSeries[k]);
  for k := 0 to High(FInitial) do FreeAndNil(FInitial[k]);
  FSeries := nil;
  FInitial := nil;
  FreeAndNil(FToolbox);
  FreeAndNil(FOptions);
  FreeAndNil(FZoom);
  FreeAndNil(FUpEvents);
  FUpEvents := TJSONArray.Create;
  FEvSeen := 0;
  FClock := 1700000000000;
  FChart.BrushNow := FClock;
  FChart.DataZoomNow := FClock;
  FChart.SetOption(ASc.Objects['option'].AsJSON, True);
  RenderNow;
  FStepNo := -1;
  CheckRecord(ASc.Objects['initial'], nil, nil);
  steps := ASc.Arrays['steps'];
  for i := 0 to steps.Count - 1 do
  begin
    FStepNo := i;
    Inc(FSteps);
    st := steps.Objects[i].Objects['step'];
    rec := steps.Objects[i].Objects['record'];
    nx := nil;
    if i < steps.Count - 1 then nx := steps.Objects[i + 1].Objects['step'];
    typ := st.Strings['type'];
    FClock := FClock + st.Floats['dt'];
    FChart.BrushNow := FClock;
    FChart.DataZoomNow := FClock;
    FChart.BrushTick(FClock);
    FChart.DataZoomTick(FClock);
    if typ = 'mousemove' then FChart.Move(st.Integers['x'], st.Integers['y'])
    else if typ = 'mousedown' then FChart.Down(st.Integers['x'], st.Integers['y'])
    else if typ = 'mouseup' then FChart.Up(st.Integers['x'], st.Integers['y'])
    else if typ = 'action' then
      FChart.DispatchAction(st.Objects['payload'].AsJSON)
    else if typ = 'set' then
      FChart.SetOption(st.Objects['option'].AsJSON, st.Get('notMerge', False));
    RenderNow;
    { a frame: the toolbox's hover states land }
    FChart.ToolboxFrame;
    CheckRecord(rec, st, nx);
  end;
end;

procedure TAdvChartBrushSelectOracleTest.RunGroup(const APrefixes: array of string);
var
  sc: TJSONArray;
  i, k: Integer;
  id: string;
  ran: Integer;
begin
  sc := TJSONObject(FRoot).Arrays['scenarios'];
  ran := 0;
  for i := 0 to sc.Count - 1 do
  begin
    id := sc.Objects[i].Strings['id'];
    for k := 0 to High(APrefixes) do
      if Pos(APrefixes[k], id) = 1 then
      begin
        RunScenario(sc.Objects[i]);
        Inc(ran);
        Break;
      end;
  end;
  AssertTrue('the group ran cases', ran > 0);
  AssertTrue('compared something', FCompared > 0);
  if GetEnvironmentVariable('TY_BRUSHSELECT_COUNTS') = '1' then
    WriteLn(Format('brushselect %s: %d comparisons over %d steps', [APrefixes[0], FCompared, FSteps]));
  if FBad > 0 then
    Fail(Format('%d of %d comparisons over %d steps differ from upstream:%s',
      [FBad, FCompared, FSteps, FReport]));
end;

procedure TAdvChartBrushSelectOracleTest.TestTheSelectorsAndTheirVisualsAsUpstream;
begin
  RunGroup(['S-']);
end;

procedure TAdvChartBrushSelectOracleTest.TestBrushLinkAsUpstream;
begin
  RunGroup(['L-']);
end;

procedure TAdvChartBrushSelectOracleTest.TestTheEventsAfterEveryActionAsUpstream;
begin
  RunGroup(['E-']);
end;

procedure TAdvChartBrushSelectOracleTest.TestTheToolboxButtonsAndThePreprocessorAsUpstream;
begin
  RunGroup(['T-']);
end;

procedure TAdvChartBrushSelectOracleTest.TestGlobalPanAndIrrelevantElementsAsUpstream;
begin
  RunGroup(['G-', 'I-']);
end;

{ ==================== by hand ==================== }

procedure TAdvChartBrushSelectTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TBsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
  FChart.BrushNow := 1700000000000;
end;

procedure TAdvChartBrushSelectTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartBrushSelectTest.Show(const AOption: string);
begin
  FChart.SetOption(AOption, True);
  RenderNow;
end;

procedure TAdvChartBrushSelectTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

const
  cScatter = '{"animation":false,"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},'
    + '"series":[{"type":"scatter","name":"P","data":[[2,2],[5,5],[8,8]]}],'
    + '"brush":{"xAxisIndex":0}}';

procedure TAdvChartBrushSelectTest.TestTheBrushSelectedPayloadIsUpstreamsShape;
var
  s, pl: string;
  i: Integer;
  pj: TJSONData;
  item: TJSONObject;
begin
  Show(cScatter);
  FChart.Events.Clear;
  { an area over the middle point, by its data range }
  AssertTrue(FChart.DispatchAction('{"type":"brush","areas":[{"brushType":"rect",'
    + '"xAxisIndex":0,"coordRange":[[4,6],[4,6]]}]}'));
  pl := '';
  for i := 0 to FChart.Events.Count - 1 do
  begin
    s := FChart.Events[i];
    if Copy(s, 1, Pos(#9, s) - 1) = 'brushselected' then pl := Copy(s, Pos(#9, s) + 1, MaxInt);
  end;
  AssertTrue('a brushselected after the brush', pl <> '');
  AssertEquals('it comes after the brush event', 'brush',
    Copy(FChart.Events[0], 1, Pos(#9, FChart.Events[0]) - 1));
  pj := GetJSON(StringReplace(pl, '\u0000', '<NUL>', [rfReplaceAll]));
  try
    AssertEquals('the event type', 'brushselected', TJSONObject(pj).Strings['type']);
    item := TJSONObject(pj).Arrays['batch'].Objects[0];
    AssertEquals('each item is the event too', 'brushselected', item.Strings['type']);
    AssertTrue('its batch is null', item.Find('batch').JSONType = jtNull);
    AssertEquals('the brush index', 0, item.Integers['brushIndex']);
    AssertEquals('one area', 1, item.Arrays['areas'].Count);
    AssertEquals('one series', 1, item.Arrays['selected'].Count);
    AssertEquals('the middle point', '[1]', item.Arrays['selected'].Objects[0].Arrays['dataIndex'].AsJSON);
    AssertEquals('the series name', 'P', item.Arrays['selected'].Objects[0].Strings['seriesName']);
  finally
    pj.Free;
  end;
  { the log holds the same }
  AssertEquals('the last dispatch selected one', 1,
    Length(FChart.BrushSelectAt(FChart.BrushSelectCount - 1).Batch[0].Selected[0].DataIndex));
end;

procedure TAdvChartBrushSelectTest.TestTheSelectorsOnTheirOwn;
var
  a: TTyBrushArea;
  sa: TTyBrushSelArea;
  l: TTyBrushItemLayout;
  r, pts: TTyBrushRange;
  ra, rb: TTyXYWH;
begin
  { a rect touching a bar's edge selects it; a NaN layout intersects as
    JavaScript compares it -- every comparison false, so overlapping }
  a := Default(TTyBrushArea);
  a.Opt.BrushType := btRect;
  SetLength(r, 2);
  r[0][0] := 10; r[0][1] := 20;
  r[1][0] := 10; r[1][1] := 20;
  a.Opt.Range := r;
  sa := TyBrushSelAreaOf(a);
  AssertTrue('a bounding rect', sa.HasBR);
  l := Default(TTyBrushItemLayout);
  l.Kind := blkRect;
  l.X := 20; l.Y := 30; l.W := 5; l.H := -15;
  AssertTrue('touching at the corner counts', TyBrushSelects(sa, l));
  l.X := 20.5;
  AssertFalse('apart does not', TyBrushSelects(sa, l));
  ra.X := 0; ra.Y := 0; ra.W := 1; ra.H := 1;
  rb.X := NaN; rb.Y := 0; rb.W := 1; rb.H := 1;
  AssertTrue('NaN overlaps', TyBrushRectIntersect(ra, rb));
  { a point: contain; NaN is out }
  l.Kind := blkPoint;
  l.X := 15; l.Y := 15;
  AssertTrue(TyBrushSelects(sa, l));
  l.X := NaN;
  AssertFalse(TyBrushSelects(sa, l));
  { a polygon: the winding number, and a bar crossed by an edge only }
  SetLength(pts, 3);
  pts[0][0] := 0; pts[0][1] := 0;
  pts[1][0] := 100; pts[1][1] := 5;
  pts[2][0] := 0; pts[2][1] := 10;
  AssertTrue('inside', TyBrushPolygonContain(pts, 10, 5));
  AssertFalse('outside', TyBrushPolygonContain(pts, 10, 20));
  AssertTrue('an edge across', TyBrushLinePolygonIntersect(50, -10, 50, 20, pts));
  { along the first edge's own line, beyond it: colinear is no crossing }
  AssertFalse('colinear is none', TyBrushLinePolygonIntersect(200, 10, 300, 15, pts));
  a.Opt.BrushType := btPolygon;
  a.Opt.Range := pts;
  sa := TyBrushSelAreaOf(a);
  l.Kind := blkRect;
  l.X := 40; l.Y := -10; l.W := 20; l.H := 30;
  AssertTrue('a bar through the polygon, no corner inside', TyBrushSelects(sa, l));
  { lines: a reversed layout range }
  a.Opt.BrushType := btLineY;
  SetLength(r, 1);
  r[0][0] := 0; r[0][1] := 5;
  a.Opt.Range := r;
  sa := TyBrushSelAreaOf(a);
  l.X := 0; l.Y := 20; l.W := 3; l.H := -18;
  AssertTrue('the bar reaches up into the line range', TyBrushSelects(sa, l));
end;

procedure TAdvChartBrushSelectTest.TestThePolygonSelectorNearZero;
var
  a: TTyBrushArea;
  sa: TTyBrushSelArea;
  l: TTyBrushItemLayout;
  pts: TTyBrushRange;
begin
  { lineLineIntersect's nearZero is 1e-6 on the cross product, in pixels
    squared: an edge 1e-6 px off level across 100 px crosses the segment
    from (10, 0) to (90, 0) at x 50 with a cross product of 8e-5 -- an
    intersection; 1e-8 px off gives 8e-7, parallel, none. The polygon's
    other three edges stay clear of the segment. [milestone C14-C22] }
  SetLength(pts, 4);
  pts[0][0] := 0; pts[0][1] := -5e-7;
  pts[1][0] := 100; pts[1][1] := 5e-7;
  pts[2][0] := 100; pts[2][1] := 50;
  pts[3][0] := 0; pts[3][1] := 50;
  AssertTrue('a cross product of 8e-5 crosses', TyBrushLinePolygonIntersect(10, 0, 90, 0, pts));
  pts[0][1] := -5e-9;
  pts[1][1] := 5e-9;
  AssertFalse('8e-7 is near zero', TyBrushLinePolygonIntersect(10, 0, 90, 0, pts));
  { THE FIRST POINT IN THE BAR is a selection of its own (selector.ts:
    BoundingRect.create(itemLayout).contain(p[0], p[1])): a polygon a few
    1e-8 px across on the bar's right edge, its first point just inside and
    the others just outside, holds no corner of the bar, and every edge is
    near zero against every side -- only that test sees it. }
  SetLength(pts, 3);
  pts[0][0] := 10 - 1e-8; pts[0][1] := 10;
  pts[1][0] := 10 + 1e-8; pts[1][1] := 10;
  pts[2][0] := 10 + 1e-8; pts[2][1] := 10 + 1e-8;
  a := Default(TTyBrushArea);
  a.Opt.BrushType := btPolygon;
  a.Opt.Range := pts;
  sa := TyBrushSelAreaOf(a);
  l := Default(TTyBrushItemLayout);
  l.Kind := blkRect;
  l.X := 0; l.Y := 0; l.W := 10; l.H := 20;
  AssertTrue('the first point is in the bar', TyBrushSelects(sa, l));
  { and turned so the first point is outside: nothing }
  pts[0][0] := 10 + 2e-8;
  a.Opt.Range := pts;
  sa := TyBrushSelAreaOf(a);
  AssertFalse('none of it is', TyBrushSelects(sa, l));
  { THE CLOSING EDGE IS SKIPPED when the last point is within 1e-8 of the
    first (polygon.contain's isAroundEqual), even though it is not the same
    point: a point beside that sliver, 5e-10 above the first point and to
    the left of the square, then has the right edge alone crossing its ray
    -- inside, upstream's answer. Closing anyway would wind it back out. }
  SetLength(pts, 5);
  pts[0][0] := 0; pts[0][1] := 0;
  pts[1][0] := 10; pts[1][1] := 0;
  pts[2][0] := 10; pts[2][1] := 10;
  pts[3][0] := 0; pts[3][1] := 10;
  pts[4][0] := 0; pts[4][1] := 1e-9;
  AssertTrue('the sliver does not close', TyBrushPolygonContain(pts, -5, 5e-10));
  pts[4][1] := 2e-8;
  AssertFalse('a gap of 2e-8 does', TyBrushPolygonContain(pts, -5, 5e-10));
end;

procedure TAdvChartBrushSelectTest.TestAnUndefinedOpacityDrawsAtOne;
var
  vis: TTyVisualPieceVisualArray;
  row: TTyVisualRow;
begin
  { an opacity visual that is undefined (`inBrush: {opacity: null}`) is
    still set on the item -- style.opacity undefined, which zrender draws
    at 1, not as nothing [milestone C14-C22] }
  SetLength(vis, 1);
  vis[0] := Default(TTyVisualPieceVisual);
  vis[0].Kind := 'opacity';
  vis[0].Defined := False;
  row := Default(TTyVisualRow);
  row.Opacity := 0.25;
  TyBrushApplyVisual(vis, False, TyVisualUndefined, row);
  AssertTrue('set', row.OpacitySet);
  AssertEquals('at one', 1, row.Opacity, 0);
  vis[0].Defined := True;
  vis[0].IsNum := True;
  vis[0].Num := 0.4;
  TyBrushApplyVisual(vis, False, TyVisualUndefined, row);
  AssertEquals('a number is itself', 0.4, row.Opacity, 0);
end;

procedure TAdvChartBrushSelectTest.TestBrushSelectedWaitsForTheActionsHandlers;
var
  i, iLeg, iSel: Integer;
begin
  { upstream's brushSelect is a pending action while the dispatch runs:
    the action's own events go to every handler first, then brushselected.
    Here the update is lazy, so it is the handler that paints the chart
    (a repaint inside it) that runs the visual stage -- and the action
    holds its brushselected until the dispatch is over, so a handler
    still hears its own event before brushselected [milestone C14-C22] }
  Show('{"animation":false,"legend":{},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{},"series":[{"type":"bar","name":"A","data":[1,2]},'
    + '{"type":"bar","name":"B","data":[2,1]}]}');
  FChart.AllEvents.Clear;
  FChart.PaintOn := 'legendselectchanged';
  try
    AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect","name":"B"}'));
  finally
    FChart.PaintOn := '';
  end;
  iLeg := -1;
  iSel := -1;
  for i := 0 to FChart.AllEvents.Count - 1 do
  begin
    if (FChart.AllEvents[i] = 'legendselectchanged') and (iLeg < 0) then iLeg := i;
    if (FChart.AllEvents[i] = 'brushselected') and (iSel < 0) then iSel := i;
  end;
  AssertTrue('the legend event: ' + FChart.AllEvents.CommaText, iLeg >= 0);
  AssertTrue('a brushselected: ' + FChart.AllEvents.CommaText, iSel >= 0);
  AssertTrue('after the legend''s: ' + FChart.AllEvents.CommaText, iSel > iLeg);
end;

procedure TAdvChartBrushSelectTest.TestTheGlobalPanMutexHasOneHolder;
begin
  Show('{"animation":false,"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter","data":[[1,1],[2,2]]}],'
    + '"toolbox":{"feature":{"dataZoom":{}}},"brush":{"xAxisIndex":0}}');
  AssertFalse('nobody holds it', FChart.BrushGlobalPanTaken);
  FChart.DispatchAction('{"type":"takeGlobalCursor","key":"brush","brushOption":{"brushType":"rect"}}');
  RenderNow;
  AssertTrue('the brush holds it', FChart.BrushGlobalPanTaken);
  { the zoom takes the cursor: the brush's painting option goes off, the
    zoom's controller takes the mutex }
  FChart.DispatchAction('{"type":"takeGlobalCursor","key":"dataZoomSelect","dataZoomSelectActive":true}');
  RenderNow;
  AssertTrue('the zoom holds it', FChart.BrushGlobalPanTaken);
  AssertFalse('the brush is off', FChart.BrushControllerOf(0).Enabled);
  FChart.DispatchAction('{"type":"takeGlobalCursor","key":"dataZoomSelect","dataZoomSelectActive":false}');
  RenderNow;
  AssertFalse('released', FChart.BrushGlobalPanTaken);
  { a notMerge disposes the views: released }
  FChart.DispatchAction('{"type":"takeGlobalCursor","key":"brush","brushOption":{"brushType":"lineX"}}');
  RenderNow;
  AssertTrue(FChart.BrushGlobalPanTaken);
  Show('{"animation":false,"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter","data":[[1,1]]}]}');
  AssertFalse('a new option holds nothing', FChart.BrushGlobalPanTaken);
end;

procedure TAdvChartBrushSelectTest.TestTheSelectBrushIsAController;
var
  r: TTyXYWH;
  s: TTyXYWH;
  lay: TTyToolboxLayout;
begin
  Show('{"animation":false,"xAxis":{"type":"value","min":0,"max":10},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter","data":[[1,1],[9,9]]}],'
    + '"toolbox":{"feature":{"dataZoom":{"yAxisIndex":false}}}}');
  AssertTrue(FChart.ToolboxClick(0, 'dataZoom', 'zoom'));
  RenderNow;
  AssertTrue('zoom on', FChart.ToolboxZoomActive);
  AssertTrue('it holds globalPan', FChart.BrushGlobalPanTaken);
  FChart.Move(200, 200);
  FChart.Down(200, 200);
  FChart.Move(250, 220);
  AssertTrue('a cover while it is drawn', FChart.ToolboxCover(r));
  { lineX: the grid's whole height }
  AssertEquals('from the press', 200, r.X, 0);
  AssertEquals('to the pointer', 50, r.W, 0);
  AssertTrue('the grid''s height', r.H > 100);
  FChart.Move(300, 240);
  FChart.Up(300, 240);
  RenderNow;
  AssertFalse('the cover goes at the end', FChart.ToolboxCover(s));
  AssertEquals('the history grew', 2, FChart.ToolboxHistoryCount);
  lay := FChart.ToolboxLayout(0);
  AssertTrue(lay.Valid);
end;

procedure TAdvChartBrushSelectTest.TestAnItemCanOptOut;
var
  vr: TTyVisualRow;
  lst: TTyPaintList;
  k: Integer;
  e: TTyChartElement;
  fill: TTyChartColor;
begin
  Show('{"animation":false,"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},'
    + '"series":[{"type":"scatter","data":[{"value":[2,2],"itemStyle":{"color":"#ff0000"}},'
    + '{"value":[5,5],"visualMap":false},[8,8]]}],'
    + '"brush":{"xAxisIndex":0,"outOfBrush":{"color":"#00ff00"}}}');
  FChart.DispatchAction('{"type":"brush","areas":[{"brushType":"rect",'
    + '"xAxisIndex":0,"coordRange":[[7,9],[7,9]]}]}');
  RenderNow;
  AssertTrue(FChart.VisualRow(0, 0, vr));
  AssertTrue('out of the brush: green', vr.ColorSet and (vr.Color.G = 255) and (vr.Color.R = 0));
  AssertTrue(FChart.VisualRow(0, 1, vr));
  AssertFalse('visualMap: false keeps its own', vr.ColorSet);
  AssertTrue(FChart.VisualRow(0, 2, vr));
  AssertTrue('in the brush: lifted', vr.LiftZSet and (vr.LiftZ = 5));
  AssertFalse('in the brush keeps its colour', vr.ColorSet);
  { THE BRUSH'S STAGE COMES AFTER THE ITEM'S OWN STYLE: the red item out of
    the brush is drawn green }
  lst := FChart.List;
  fill := 0;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Datum.SeriesIndex = 0) and (e.Datum.RawDataIndex = 0) and (e.Anim.Role = carSymbol) then
      fill := e.Style.FillColor;
  end;
  AssertEquals('drawn green over its own red', '$FF00FF00', '$' + IntToHex(fill, 8));
end;

initialization
  RegisterTest(TAdvChartBrushSelectOracleTest);
  RegisterTest(TAdvChartBrushSelectTest);
end.
