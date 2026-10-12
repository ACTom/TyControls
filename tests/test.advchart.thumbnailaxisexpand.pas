unit test.advchart.thumbnailaxisexpand;
{$mode objfpc}{$H+}
{ The thumbnail and the parallel axis expansion -- held to upstream to the
  bit [Batch 140, D7].

  tools/advchart-oracle/thumbnail-axisexpand.js runs the real ECharts 6.1
  build through cases of pointer steps on zrender's own Handler (moves,
  presses, releases, wheels), actions, merges and resizes, on a fake clock,
  and records after every step: each thumbnail -- enabled, its box, rim,
  content rect, window, the copy's view (data rect, view rect, the copy
  group's transform, the overall matrix, the graph's, the thumbnail-to-graph
  one), the copy's items and their styles --, each graph's overall matrix,
  each parallel's layout info computed from its option, the option's own
  axisExpandWindow, every axis' place, label switch and name widths, the
  parallel axes' covers and intervals, the rows' opacities, the actions the
  views dispatched (graphRoam, parallelAxisExpand -- with their time --,
  axisAreaSelect) and the events.

  The port is driven the same way -- MouseMove / MouseDown / MouseUp,
  DoMouseWheel, DispatchAction, SetOption, SetBounds -- on the same clock
  (ParallelExpandNow / ParallelExpandTick beside the brush's and the
  dataZoom's), with a headless render after each step, and compared through
  ThumbnailState, ThumbnailHitAt, GraphView, ParallelLayout,
  ParallelIntervals, ParallelBrushOf, ParallelSolvedOf,
  ParallelExpandActionAt, OnGraphRoam and the chart events. }
interface
uses Classes, SysUtils, Math, Types, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Events, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Brush, tyControls.AdvChart.Parallel, tyControls.AdvChart.Graph,
     tyControls.AdvChart.Thumbnail, tyControls.AdvChart.Color, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Layout,
     tyControls.AdvanceChart;
type
  TTaProbe = class(TTyAdvanceChart)
  public
    Events: TStringList;
    Roams: array of TTyGraphRoamPayload;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    function Wheel(AX, AY, ADelta: Integer): Boolean;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
    procedure OnRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
  end;

  TAdvChartThumbnailAxisExpandOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTaProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSteps, FStepNo: Integer;
    FReport, FName: string;
    FClock: Double;
    FW, FH: Integer;
    FEvSeen, FRoamSeen, FActSeen, FAxActSeen: Integer;
    FResizeStep: Boolean;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameItem(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure NewChart;
    procedure RenderNow;
    procedure CheckThumbs(ARec: TJSONObject);
    procedure CheckGraphs(ARec: TJSONObject);
    procedure CheckPars(ARec: TJSONObject);
    procedure CheckAxes(ARec: TJSONObject);
    procedure CheckRows(ARec: TJSONObject);
    procedure CheckActions(ARec: TJSONObject);
    procedure CheckEvents(ARec: TJSONObject);
    procedure CheckRecord(ARec: TJSONObject);
    procedure RunScenario(ASc: TJSONObject);
    procedure RunGroup(const AIds: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheThumbnailOfANoneGraphAsUpstream;
    procedure TestTheThumbnailStylesAsUpstream;
    procedure TestTheThumbnailBoxesAsUpstream;
    procedure TestTheThumbnailOfForceAndCircularAsUpstream;
    procedure TestTheThumbnailTargetsAsUpstream;
    procedure TestTheExpandedLayoutsAsUpstream;
    procedure TestTheClickTriggerAsUpstream;
    procedure TestTheMoveTriggerAsUpstream;
    procedure TestTheExpandActionAsUpstream;
    procedure TestBrushingWithFoldedAxesAsUpstream;
  end;

  TAdvChartThumbnailAxisExpandTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTaProbe;
    procedure Show(const AOption: string);
    function RenderNow: TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheThumbnailIsDrawnOverTheGraph;
    procedure TestTheBoxHidesWhatIsUnderIt;
    procedure TestTheExpansionEventCanBeSubscribed;
    procedure TestTheThrottleRunsOnItsOwnClock;
    procedure TestHelpers;
  end;

implementation

const
  cW = 600;
  cH = 400;

{ ==================== the probe ==================== }

constructor TTaProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
  OnChartEvent := @OnEv;
  OnGraphRoam := @OnRoam;
end;

destructor TTaProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TTaProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTaProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TTaProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TTaProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TTaProbe.Wheel(AX, AY, ADelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TTaProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType = 'parallelaxisexpand') or (AEvent.EventType = 'brushselected')
    or (AEvent.EventType = 'axisareaselected') then
    Events.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TTaProbe.OnRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
begin
  SetLength(Roams, Length(Roams) + 1);
  Roams[High(Roams)] := APayload;
end;

{ ==================== the fixture's numbers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-thumbnail-axisexpand.json';
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

function JStr(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := '(null)'
  else if AData.JSONType = jtString then Result := AData.AsString
  else Result := AData.AsJSON;
end;

function ActiveWord(A: TTyParallelActive): string;
begin
  case A of
    ppaActive: Result := 'active';
    ppaInactive: Result := 'inactive';
  else
    Result := 'normal';
  end;
end;

{ a JSON value of an option as String(v) writes it; absent: ADefault }
function OptJs(ANode: TJSONObject; const AKey, ADefault: string): string;
var d: TJSONData;
begin
  if ANode = nil then Exit(ADefault);
  d := ANode.Find(AKey);
  if d = nil then Exit(ADefault);
  case d.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if d.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := TyJsNumberToString(d.AsFloat);
    jtString: Result := d.AsString;
  else
    Result := d.AsJSON;
  end;
end;

{ the raw text of a key's value in a JSON object text: an array up to its
  bracket, else up to the next comma or brace; 'undefined' when absent }
function RawValue(const AJson, AKey: string): string;
var p, q, depth: Integer;
begin
  p := Pos('"' + AKey + '":', AJson);
  if p = 0 then Exit('undefined');
  p := p + Length(AKey) + 3;
  q := p;
  depth := 0;
  while q <= Length(AJson) do
  begin
    if AJson[q] in ['[', '{'] then Inc(depth)
    else if AJson[q] in [']', '}'] then
    begin
      if depth = 0 then Break;
      Dec(depth);
      if depth = 0 then
      begin
        Inc(q);
        Break;
      end;
    end
    else if (AJson[q] = ',') and (depth = 0) then Break;
    Inc(q);
  end;
  Result := Copy(AJson, p, q - p);
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartThumbnailAxisExpandOracleTest.SetUp;
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
  FBad := 0;
  FCompared := 0;
  FSteps := 0;
  FReport := '';
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if (FBad <= 400) and (Pos(FName + ': ' + AWhat, FReport) = 0) then
    FReport := FReport + LineEnding + '  ' + FName + ' @' + IntToStr(FStepNo) + ': ' + AWhat;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.SameHex(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double; ok: Boolean; q: QWord;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else ok := AGot = want;
  if not ok then
  begin
    q := 0;
    System.Move(AGot, q, SizeOf(q));
    Miss(Format('%s is %s upstream, %s here (%s / %s)', [AWhat, Fmt(want), Fmt(AGot),
      JStr(AWant), LowerCase(IntToHex(q, 16))]));
  end;
end;

{ a copy's coordinate: to the bit -- but a ring's positions come from the
  port's own sine and cosine (the graph's ring is held to 1e-9, §79), so
  within that there }
procedure TAdvChartThumbnailAxisExpandOracleTest.SameItem(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  if FName <> 'TH-CIRC' then
  begin
    SameHex(AWhat, AGot, AWant);
    Exit;
  end;
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) or IsNan(AGot) then
  begin
    if not (IsNan(want) and IsNan(AGot)) then Miss(AWhat + ' differs in being a number');
    Exit;
  end;
  if Abs(AGot - want) > 1e-9 * Max(1, Abs(want)) then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TTaProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FW := cW;
  FH := cH;
  FChart.SetBounds(0, 0, FW, FH);
  FChart.AnimationMode := camOff;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FW, FH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ an upstream colour against the port's: the same colour when both parse
  -- unless it is one of upstream's own default inks (the v6 palette, the
  edge's neutral, an empty symbol's white), which the port takes from the
  skin }
function SameInk(const AUp: string; AHas: Boolean; AGot: TTyChartColor): Boolean;
const
  cDefaults: array[0..10] of string = ('#5070dd', '#b6d634', '#505372', '#ff994d',
    '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95', '#86878c', '#fff');
var c: TTyChartColor; k: Integer;
begin
  if (AUp = '') or (AUp = '(null)') then Exit(not AHas);
  for k := 0 to High(cDefaults) do
    if AUp = cDefaults[k] then Exit(AHas);
  if not TyTryParseChartColor(AUp, c) then Exit(True);
  Result := AHas and (c = AGot);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.CheckThumbs(ARec: TJSONObject);
var
  ths, its: TJSONArray;
  th, v, it, sty: TJSONObject;
  k, i, j: Integer;
  st: TTyThumbState;
  what, kind: string;
  d: TJSONData;
  item: TTyThumbItem;
  ink: string;
begin
  ths := ARec.Arrays['thumbs'];
  SameStr('the thumbnail count', IntToStr(FChart.ThumbnailCount), IntToStr(ths.Count));
  for k := 0 to Min(ths.Count, FChart.ThumbnailCount) - 1 do
  begin
    th := ths.Objects[k];
    st := FChart.ThumbnailState(k);
    what := Format('thumbnail %d', [k]);
    SameBool(what + ' enabled', st.Enabled, th.Booleans['enabled']);
    if not (th.Booleans['drawn'] and st.Enabled) then Continue;
    for j := 0 to 3 do
    begin
      case j of
        0: begin SameHex(what + ' box x', st.Box.X, th.Arrays['box'].Items[0]);
             SameHex(what + ' content x', st.Content.X, th.Arrays['content'].Items[0]);
             SameHex(what + ' window x', st.Window.X, th.Arrays['window'].Items[0]); end;
        1: begin SameHex(what + ' box y', st.Box.Y, th.Arrays['box'].Items[1]);
             SameHex(what + ' content y', st.Content.Y, th.Arrays['content'].Items[1]);
             SameHex(what + ' window y', st.Window.Y, th.Arrays['window'].Items[1]); end;
        2: begin SameHex(what + ' box w', st.Box.W, th.Arrays['box'].Items[2]);
             SameHex(what + ' content w', st.Content.W, th.Arrays['content'].Items[2]);
             SameHex(what + ' window w', st.Window.W, th.Arrays['window'].Items[2]); end;
        3: begin SameHex(what + ' box h', st.Box.H, th.Arrays['box'].Items[3]);
             SameHex(what + ' content h', st.Content.H, th.Arrays['content'].Items[3]);
             SameHex(what + ' window h', st.Window.H, th.Arrays['window'].Items[3]); end;
      end;
    end;
    { the rim and the window's style: the widths and opacities, and the
      colours the option wrote }
    sty := th.Objects['bgStyle'];
    SameHex(what + ' rim width', st.Model.BorderWidth, sty.Find('lineWidth'));
    SameHex(what + ' box opacity', st.Model.Opacity, sty.Find('opacity'));
    if st.Model.Fill.Written then SameStr(what + ' box fill', st.Model.Fill.Text, JStr(sty.Find('fill')));
    if st.Model.Border.Written then SameStr(what + ' rim colour', st.Model.Border.Text, JStr(sty.Find('stroke')));
    sty := th.Objects['winStyle'];
    SameHex(what + ' window rim width', st.Model.WinBorderWidth, sty.Find('lineWidth'));
    SameHex(what + ' window opacity', st.Model.WinOpacity, sty.Find('opacity'));
    if st.Model.WinFill.Written then SameStr(what + ' window fill', st.Model.WinFill.Text, JStr(sty.Find('fill')));
    if st.Model.WinBorder.Written then SameStr(what + ' window rim colour', st.Model.WinBorder.Text, JStr(sty.Find('stroke')));
    d := th.Find('view');
    SameBool(what + ' has a view', st.View.Valid, (d <> nil) and (d.JSONType = jtObject));
    if not ((d <> nil) and (d.JSONType = jtObject) and st.View.Valid) then Continue;
    v := TJSONObject(d);
    SameStr(what + ' z2 of the box', IntToStr(TyThumbItemZ2 - 10), th.Strings['bgZ2']);
    SameStr(what + ' z2 of the window', IntToStr(TyThumbItemZ2 + 10), th.Strings['winZ2']);
    SameHex(what + ' data x', st.View.DataRect.X, v.Arrays['dataRect'].Items[0]);
    SameHex(what + ' data y', st.View.DataRect.Y, v.Arrays['dataRect'].Items[1]);
    SameHex(what + ' data w', st.View.DataRect.W, v.Arrays['dataRect'].Items[2]);
    SameHex(what + ' data h', st.View.DataRect.H, v.Arrays['dataRect'].Items[3]);
    SameHex(what + ' view x', st.View.ViewRect.X, v.Arrays['viewRect'].Items[0]);
    SameHex(what + ' view y', st.View.ViewRect.Y, v.Arrays['viewRect'].Items[1]);
    SameHex(what + ' view w', st.View.ViewRect.W, v.Arrays['viewRect'].Items[2]);
    SameHex(what + ' view h', st.View.ViewRect.H, v.Arrays['viewRect'].Items[3]);
    SameHex(what + ' trans x', st.View.TransX, v.Arrays['trans'].Items[0]);
    SameHex(what + ' trans y', st.View.TransY, v.Arrays['trans'].Items[1]);
    SameHex(what + ' trans sx', st.View.TransSX, v.Arrays['trans'].Items[2]);
    SameHex(what + ' trans sy', st.View.TransSY, v.Arrays['trans'].Items[3]);
    for j := 0 to 5 do
    begin
      SameHex(Format('%s overall[%d]', [what, j]), st.View.Overall[j], v.Arrays['overall'].Items[j]);
      SameHex(Format('%s target[%d]', [what, j]), st.View.Target[j], v.Arrays['target'].Items[j]);
    end;
    d := v.Find('toTarget');
    SameBool(what + ' has toTarget', st.View.HasToTarget, (d <> nil) and (d.JSONType = jtArray));
    if (d is TJSONArray) and st.View.HasToTarget then
      for j := 0 to 5 do
        SameHex(Format('%s toTarget[%d]', [what, j]), st.View.ToTarget[j], TJSONArray(d).Items[j]);
    SameStr(what + ' roam', st.RoamText, v.Strings['roamType']);
    SameBool(what + ' roam on', st.RoamOn, v.Booleans['roamOn']);
    its := th.Arrays['items'];
    SameStr(what + ' item count', IntToStr(Length(st.Items)), IntToStr(its.Count));
    for i := 0 to Min(its.Count, Length(st.Items)) - 1 do
    begin
      it := its.Objects[i];
      item := st.Items[i];
      if item.Kind = tikSymbol then kind := 'symbol' else kind := 'line';
      SameStr(Format('%s item %d kind', [what, i]), kind, it.Strings['kind']);
      if kind <> it.Strings['kind'] then Continue;
      if item.Kind = tikSymbol then
      begin
        SameStr(Format('%s item %d type', [what, i]), item.SymbolType, JStr(it.Find('type')));
        SameItem(Format('%s item %d x', [what, i]), item.X, it.Arrays['rect'].Items[0]);
        SameItem(Format('%s item %d y', [what, i]), item.Y, it.Arrays['rect'].Items[1]);
        SameItem(Format('%s item %d w', [what, i]), item.W, it.Arrays['rect'].Items[2]);
        SameItem(Format('%s item %d h', [what, i]), item.H, it.Arrays['rect'].Items[3]);
      end
      else
      begin
        SameItem(Format('%s item %d x1', [what, i]), item.X1, it.Arrays['shape'].Items[0]);
        SameItem(Format('%s item %d y1', [what, i]), item.Y1, it.Arrays['shape'].Items[1]);
        SameItem(Format('%s item %d x2', [what, i]), item.X2, it.Arrays['shape'].Items[2]);
        SameItem(Format('%s item %d y2', [what, i]), item.Y2, it.Arrays['shape'].Items[3]);
        SameItem(Format('%s item %d cpx', [what, i]), item.CPX, it.Arrays['shape'].Items[4]);
        SameItem(Format('%s item %d cpy', [what, i]), item.CPY, it.Arrays['shape'].Items[5]);
      end;
      sty := it.Objects['style'];
      { the stroke: there, and its width when there }
      SameBool(Format('%s item %d stroked', [what, i]), item.HasStroke,
        (sty.Find('stroke') <> nil) and (sty.Find('stroke').JSONType = jtString)
        and (sty.Strings['stroke'] <> 'none') and (HexNum(sty.Find('lineWidth')) > 0));
      if item.HasStroke then
        SameHex(Format('%s item %d line width', [what, i]), item.LineWidth, sty.Find('lineWidth'));
      SameHex(Format('%s item %d opacity', [what, i]), item.Opacity, sty.Find('opacity'));
      { the colours, where the port's colour can be compared }
      ink := JStr(sty.Find('fill'));
      Inc(FCompared);
      if not SameInk(ink, item.HasFill, item.Fill) then
        Miss(Format('%s item %d fill is %s upstream, %s here', [what, i, ink,
          IntToHex(item.Fill, 8)]));
      if item.HasStroke then
      begin
        ink := JStr(sty.Find('stroke'));
        Inc(FCompared);
        if not SameInk(ink, True, item.Stroke) then
          Miss(Format('%s item %d stroke is %s upstream, %s here', [what, i, ink,
            IntToHex(item.Stroke, 8)]));
      end;
    end;
  end;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.CheckGraphs(ARec: TJSONObject);
var
  gs: TJSONArray;
  g: TJSONObject;
  i, si: Integer;
  v: TTyGraphView;
begin
  gs := ARec.Arrays['graphs'];
  for i := 0 to gs.Count - 1 do
  begin
    g := gs.Objects[i];
    si := g.Integers['seriesIndex'];
    v := FChart.GraphView(si);
    if v = nil then
    begin
      Miss(Format('graph %d has no view', [si]));
      Continue;
    end;
    SameHex(Format('graph %d overall sx', [si]), v.OverallScaleX, g.Arrays['overall'].Items[0]);
    SameHex(Format('graph %d overall sy', [si]), v.OverallScaleY, g.Arrays['overall'].Items[3]);
    SameHex(Format('graph %d overall x', [si]), v.OverallX, g.Arrays['overall'].Items[4]);
    SameHex(Format('graph %d overall y', [si]), v.OverallY, g.Arrays['overall'].Items[5]);
  end;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.CheckPars(ARec: TJSONObject);
var
  ps, axs, ow: TJSONArray;
  p, ax: TJSONObject;
  i, a: Integer;
  par: TTyParallel;
  node: TJSONObject;
  d: TJSONData;
  what: string;
begin
  ps := ARec.Arrays['pars'];
  for i := 0 to ps.Count - 1 do
  begin
    p := ps.Objects[i];
    par := FChart.ParallelLayout(p.Integers['k']);
    what := Format('parallel %d', [p.Integers['k']]);
    if par = nil then
    begin
      Miss(what + ' is not laid out');
      Continue;
    end;
    SameBool(what + ' expandable', par.Expandable, p.Booleans['expandable']);
    SameHex(what + ' expand width', par.ExpandWidth, p.Find('expandWidth'));
    SameHex(what + ' collapse width', par.CollapseWidth, p.Find('collapseWidth'));
    SameHex(what + ' window[0]', par.ExpandWindow0, p.Arrays['window'].Items[0]);
    SameHex(what + ' window[1]', par.ExpandWindow1, p.Arrays['window'].Items[1]);
    SameHex(what + ' inner[0]', par.WinInner0, p.Arrays['winInner'].Items[0]);
    SameHex(what + ' inner[1]', par.WinInner1, p.Arrays['winInner'].Items[1]);
    SameHex(what + ' window0Pos', par.ExpandWindow0Pos, p.Find('window0Pos'));
    { the option as the models hold it }
    node := nil;
    d := FChart.OptionComponent('parallel', p.Integers['k']);
    if d is TJSONObject then node := TJSONObject(d);
    d := nil;
    if node <> nil then d := node.Find('axisExpandWindow');
    ow := nil;
    if p.Find('optWindow') is TJSONArray then ow := p.Arrays['optWindow'];
    SameBool(what + ' option window', d is TJSONArray, ow <> nil);
    if (ow <> nil) and (d is TJSONArray) and (d.Count >= 2) then
    begin
      SameHex(what + ' option window[0]', TJSONArray(d).Items[0].AsFloat, ow.Items[0]);
      SameHex(what + ' option window[1]', TJSONArray(d).Items[1].AsFloat, ow.Items[1]);
    end;
    SameStr(what + ' option centre', OptJs(node, 'axisExpandCenter', 'null'), p.Strings['optCenter']);
    SameStr(what + ' option count', OptJs(node, 'axisExpandCount', '0'), p.Strings['optCount']);
    SameStr(what + ' option width', OptJs(node, 'axisExpandWidth', '50'), p.Strings['optWidth']);
    SameStr(what + ' option expandable', OptJs(node, 'axisExpandable', 'false'), p.Strings['optExpandable']);
    axs := p.Arrays['axes'];
    SameStr(what + ' axis count', IntToStr(par.AxisCount), IntToStr(axs.Count));
    for a := 0 to Min(axs.Count, par.AxisCount) - 1 do
    begin
      ax := axs.Objects[a];
      SameStr(Format('%s axis %d component', [what, a]), IntToStr(par.AxisIndices[a]),
        IntToStr(ax.Integers['k']));
      SameHex(Format('%s axis %d x', [what, a]), par.Layouts[a].PosX, ax.Arrays['pos'].Items[0]);
      SameHex(Format('%s axis %d y', [what, a]), par.Layouts[a].PosY, ax.Arrays['pos'].Items[1]);
      SameBool(Format('%s axis %d labels', [what, a]), par.Layouts[a].LabelShow, ax.Booleans['labelShow']);
      SameHex(Format('%s axis %d name room', [what, a]), par.Layouts[a].NameAvailableWidth,
        ax.Find('nameAvail'));
      SameHex(Format('%s axis %d name cut', [what, a]), par.Layouts[a].NameTruncMax,
        ax.Find('nameTrunc'));
    end;
  end;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.CheckAxes(ARec: TJSONObject);
var
  axs, cvs: TJSONArray;
  ax: TJSONObject;
  i, k, j: Integer;
  iv: TTyParallelIntervalArray;
  ctl: TTyBrushController;
  what: string;
begin
  axs := ARec.Arrays['axes'];
  for i := 0 to axs.Count - 1 do
  begin
    ax := axs.Objects[i];
    k := ax.Integers['k'];
    what := Format('parallelAxis %d', [k]);
    iv := FChart.ParallelIntervals(k);
    SameStr(what + ' interval count', IntToStr(Length(iv)), IntToStr(ax.Arrays['intervals'].Count));
    for j := 0 to Min(Length(iv), ax.Arrays['intervals'].Count) - 1 do
    begin
      SameHex(Format('%s interval %d [0]', [what, j]), iv[j][0], ax.Arrays['intervals'].Arrays[j].Items[0]);
      SameHex(Format('%s interval %d [1]', [what, j]), iv[j][1], ax.Arrays['intervals'].Arrays[j].Items[1]);
    end;
    ctl := FChart.ParallelBrushOf(k);
    if ctl = nil then
    begin
      Miss(what + ' has no controller');
      Continue;
    end;
    if ax.Find('mount') is TJSONArray then
    begin
      SameHex(what + ' mount x', ctl.Xf[4], ax.Arrays['mount'].Items[0]);
      SameHex(what + ' mount y', ctl.Xf[5], ax.Arrays['mount'].Items[1]);
    end;
    cvs := ax.Arrays['covers'];
    SameStr(what + ' cover count', IntToStr(Length(ctl.Covers)), IntToStr(cvs.Count));
    for j := 0 to Min(Length(ctl.Covers), cvs.Count) - 1 do
      if Length(ctl.Covers[j].Opt.Range) = 1 then
      begin
        SameHex(Format('%s cover %d [0]', [what, j]), ctl.Covers[j].Opt.Range[0][0], cvs.Arrays[j].Items[0]);
        SameHex(Format('%s cover %d [1]', [what, j]), ctl.Covers[j].Opt.Range[0][1], cvs.Arrays[j].Items[1]);
      end;
  end;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.CheckRows(ARec: TJSONObject);
var
  rows, items: TJSONArray;
  r, i, k, si: Integer;
  sol: TTyParallelSolved;
begin
  rows := ARec.Arrays['rows'];
  for r := 0 to rows.Count - 1 do
  begin
    si := rows.Objects[r].Integers['seriesIndex'];
    items := rows.Objects[r].Arrays['items'];
    sol := FChart.ParallelSolvedOf(si);
    if not sol.Valid then
    begin
      Miss(Format('series %d is not solved', [si]));
      Continue;
    end;
    for i := 0 to items.Count - 1 do
      for k := 0 to High(sol.Rows) do
        if sol.Rows[k].Row = i then
        begin
          SameHex(Format('series %d row %d opacity', [si, i]), sol.Rows[k].Opacity,
            items.Objects[i].Find('opacity'));
          SameStr(Format('series %d row %d active', [si, i]), ActiveWord(sol.Rows[k].Active),
            items.Objects[i].Strings['active']);
        end;
  end;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.CheckActions(ARec: TJSONObject);
var
  acts: TJSONArray;
  a: TJSONObject;
  i, ne, nb: Integer;
  pa: TTyParallelExpandAction;
  ba: TTyParallelBrushAction;
  t: string;
begin
  acts := ARec.Arrays['actions'];
  ne := 0;
  nb := 0;
  for i := 0 to acts.Count - 1 do
  begin
    a := acts.Objects[i];
    t := a.Strings['type'];
    if t = 'parallelAxisExpand' then
    begin
      if FActSeen + ne >= FChart.ParallelExpandActionCount then
      begin
        Miss(Format('no expansion %d here', [ne]));
        Inc(ne);
        Continue;
      end;
      pa := FChart.ParallelExpandActionAt(FActSeen + ne);
      SameStr(Format('expansion %d time', [ne]), FloatToStr(pa.Time - 1700000000000),
        IntToStr(a.Integers['t']));
      SameHex(Format('expansion %d window[0]', [ne]), pa.W0, a.Arrays['window'].Items[0]);
      SameHex(Format('expansion %d window[1]', [ne]), pa.W1, a.Arrays['window'].Items[1]);
      SameStr(Format('expansion %d animation', [ne]), pa.Animation, a.Strings['animation']);
      Inc(ne);
    end
    else if t = 'axisAreaSelect' then
    begin
      if FAxActSeen + nb < FChart.ParallelBrushActionCount then
      begin
        ba := FChart.ParallelBrushActionAt(FAxActSeen + nb);
        SameStr(Format('area select %d intervals', [nb]), IntToStr(Length(ba.Intervals)),
          IntToStr(a.Arrays['intervals'].Count));
      end
      else
        Miss(Format('no area select %d here', [nb]));
      Inc(nb);
    end;
  end;
  SameStr('the expansions dispatched', IntToStr(FChart.ParallelExpandActionCount - FActSeen), IntToStr(ne));
  SameStr('the area selects dispatched', IntToStr(FChart.ParallelBrushActionCount - FAxActSeen), IntToStr(nb));
  FActSeen := FChart.ParallelExpandActionCount;
  FAxActSeen := FChart.ParallelBrushActionCount;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.CheckEvents(ARec: TJSONObject);
var
  evs: TJSONArray;
  e: TJSONObject;
  i, n, nr, j: Integer;
  line, t, pl, keys: string;
  pd: TJSONData;
  names: TStringList;
  rp: TTyGraphRoamPayload;
begin
  evs := ARec.Arrays['events'];
  { the graphroam events against OnGraphRoam, the rest against the chart's }
  n := 0;
  nr := 0;
  for i := 0 to evs.Count - 1 do
  begin
    e := evs.Objects[i];
    t := e.Strings['type'];
    if t = 'graphroam' then
    begin
      if FRoamSeen + nr >= Length(FChart.Roams) then
      begin
        Miss(Format('no graphroam %d here', [nr]));
        Inc(nr);
        Continue;
      end;
      rp := FChart.Roams[FRoamSeen + nr];
      SameBool(Format('graphroam %d pans', [nr]), rp.HasPan, e.Find('dx').JSONType <> jtNull);
      if rp.HasPan then
      begin
        SameHex(Format('graphroam %d dx', [nr]), rp.DX, e.Find('dx'));
        SameHex(Format('graphroam %d dy', [nr]), rp.DY, e.Find('dy'));
      end;
      SameBool(Format('graphroam %d zooms', [nr]), rp.HasZoom, e.Find('zoom').JSONType <> jtNull);
      if rp.HasZoom then
      begin
        SameHex(Format('graphroam %d zoom', [nr]), rp.Zoom, e.Find('zoom'));
        SameHex(Format('graphroam %d originX', [nr]), rp.OriginX, e.Find('originX'));
        SameHex(Format('graphroam %d originY', [nr]), rp.OriginY, e.Find('originY'));
      end;
      Inc(nr);
      Continue;
    end;
    { a resize's update dispatches brushSelect upstream; the port's resize
      does not (outside this batch: a deviation of the brush's, §178) }
    if FResizeStep and (t = 'brushselected') then Continue;
    if FEvSeen + n >= FChart.Events.Count then
    begin
      Miss(Format('no event %d (%s) here', [n, t]));
      Inc(n);
      Continue;
    end;
    line := FChart.Events[FEvSeen + n];
    SameStr(Format('event %d type', [n]), Copy(line, 1, Pos(#9, line) - 1), t);
    pl := Copy(line, Pos(#9, line) + 1, MaxInt);
    if t = 'parallelaxisexpand' then
    begin
      SameStr(Format('event %d window', [n]), RawValue(pl, 'axisExpandWindow'), e.Strings['windowJs']);
      SameStr(Format('event %d animation', [n]), StringReplace(RawValue(pl, 'animation'),
        'undefined', 'absent', []), e.Strings['animation']);
      pd := GetJSON(pl);
      names := TStringList.Create;
      try
        { Array.prototype.sort: code unit order }
        names.UseLocale := False;
        names.CaseSensitive := True;
        names.Sorted := True;
        if pd is TJSONObject then
          for j := 0 to TJSONObject(pd).Count - 1 do
            if TJSONObject(pd).Names[j] <> 'type' then names.Add(TJSONObject(pd).Names[j]);
        keys := '';
        for j := 0 to names.Count - 1 do
        begin
          if j > 0 then keys := keys + ',';
          keys := keys + names[j];
        end;
      finally
        names.Free;
        pd.Free;
      end;
      SameStr(Format('event %d keys', [n]), keys, e.Strings['keys']);
    end;
    Inc(n);
  end;
  SameStr('the chart events', IntToStr(FChart.Events.Count - FEvSeen), IntToStr(n));
  SameStr('the graphroam events', IntToStr(Length(FChart.Roams) - FRoamSeen), IntToStr(nr));
  FEvSeen := FChart.Events.Count;
  FRoamSeen := Length(FChart.Roams);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.CheckRecord(ARec: TJSONObject);
begin
  CheckThumbs(ARec);
  CheckGraphs(ARec);
  CheckPars(ARec);
  CheckAxes(ARec);
  CheckRows(ARec);
  CheckActions(ARec);
  CheckEvents(ARec);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.RunScenario(ASc: TJSONObject);
var
  steps: TJSONArray;
  st, rec: TJSONObject;
  i, x, y, k: Integer;
  typ, hov, mine: string;
begin
  FName := ASc.Strings['id'];
  NewChart;
  FEvSeen := 0;
  FRoamSeen := 0;
  FActSeen := 0;
  FAxActSeen := 0;
  FClock := 1700000000000;
  FResizeStep := False;
  FChart.BrushNow := FClock;
  FChart.DataZoomNow := FClock;
  FChart.ParallelExpandNow := FClock;
  FChart.SetOption(ASc.Objects['option'].AsJSON, True);
  RenderNow;
  FStepNo := -1;
  CheckRecord(ASc.Objects['initial']);
  steps := ASc.Arrays['steps'];
  for i := 0 to steps.Count - 1 do
  begin
    FStepNo := i;
    Inc(FSteps);
    st := steps.Objects[i].Objects['step'];
    rec := steps.Objects[i].Objects['record'];
    typ := st.Strings['type'];
    FResizeStep := typ = 'resize';
    FClock := FClock + st.Floats['dt'];
    FChart.ParallelExpandNow := FClock;
    FChart.ParallelExpandTick(FClock);
    FChart.BrushNow := FClock;
    FChart.BrushTick(FClock);
    FChart.DataZoomNow := FClock;
    FChart.DataZoomTick(FClock);
    if (typ = 'mousemove') or (typ = 'mousedown') or (typ = 'mouseup') or (typ = 'click')
      or (typ = 'mousewheel') then
    begin
      x := st.Integers['x'];
      y := st.Integers['y'];
      { what is under the pointer: a thumbnail's box, as the oracle names it }
      hov := JStr(steps.Objects[i].Find('hover'));
      k := FChart.ThumbnailHitAt(x, y);
      if k >= 0 then mine := 'thumbnail' + IntToStr(k) else mine := '';
      if (Pos('thumbnail', hov) = 1) or (mine <> '') then
        SameStr('the hover', mine, hov);
      if typ = 'mousemove' then FChart.Move(x, y)
      else if typ = 'mousedown' then FChart.Down(x, y)
      else if typ = 'mouseup' then FChart.Up(x, y)
      else if typ = 'mousewheel' then FChart.Wheel(x, y, st.Integers['delta']);
    end
    else if typ = 'action' then
      FChart.DispatchAction(st.Objects['payload'].AsJSON)
    else if typ = 'set' then
      FChart.SetOption(st.Objects['option'].AsJSON, st.Get('notMerge', False))
    else if typ = 'resize' then
    begin
      FW := st.Integers['w'];
      FH := st.Integers['h'];
      FChart.SetBounds(0, 0, FW, FH);
    end;
    RenderNow;
    CheckRecord(rec);
  end;
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.RunGroup(const AIds: array of string);
var
  sc: TJSONArray;
  i, k, ran: Integer;
begin
  sc := TJSONObject(FRoot).Arrays['scenarios'];
  ran := 0;
  for i := 0 to sc.Count - 1 do
    for k := 0 to High(AIds) do
      if sc.Objects[i].Strings['id'] = AIds[k] then
      begin
        RunScenario(sc.Objects[i]);
        Inc(ran);
      end;
  AssertEquals('the group ran its cases', Length(AIds), ran);
  AssertTrue('compared something', FCompared > 0);
  if GetEnvironmentVariable('TY_THUMBEXPAND_COUNTS') = '1' then
    WriteLn(Format('thumbnail / axis expand %s: %d comparisons over %d steps',
      [AIds[0], FCompared, FSteps]));
  if FBad > 0 then
    Fail(Format('%d of %d comparisons over %d steps differ from upstream:%s',
      [FBad, FCompared, FSteps, FReport]));
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheThumbnailOfANoneGraphAsUpstream;
begin
  RunGroup(['TH-NONE']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheThumbnailStylesAsUpstream;
begin
  RunGroup(['TH-STYLE']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheThumbnailBoxesAsUpstream;
begin
  RunGroup(['TH-BOX']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheThumbnailOfForceAndCircularAsUpstream;
begin
  RunGroup(['TH-FORCE', 'TH-CIRC']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheThumbnailTargetsAsUpstream;
begin
  RunGroup(['TH-TARGET']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheExpandedLayoutsAsUpstream;
begin
  RunGroup(['AE-LAYOUT']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheClickTriggerAsUpstream;
begin
  RunGroup(['AE-CLICK', 'AE-VERT']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheMoveTriggerAsUpstream;
begin
  RunGroup(['AE-MOVE', 'AE-NARROW']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestTheExpandActionAsUpstream;
begin
  RunGroup(['AE-ACTION']);
end;

procedure TAdvChartThumbnailAxisExpandOracleTest.TestBrushingWithFoldedAxesAsUpstream;
begin
  RunGroup(['AE-BRUSH']);
end;

{ ==================== by hand ==================== }

const
  cGraph = '{"animation":false,"backgroundColor":"#ffffff",'
    + '"series":[{"type":"graph","layout":"none","roam":true,"symbolSize":30,'
    + '"itemStyle":{"color":"#ff0000"},'
    + '"data":[{"name":"a","x":0,"y":0},{"name":"b","x":100,"y":60},{"name":"c","x":40,"y":120}],'
    + '"links":[{"source":"a","target":"b"},{"source":"b","target":"c"}]}],'
    + '"thumbnail":{"itemStyle":{"color":"#0000ff","borderWidth":0},'
    + '"windowStyle":{"color":"#00ff00","opacity":1,"borderWidth":0}}}';
  cPar = '{"animation":false,"parallel":{"axisExpandable":true,"axisExpandCount":3,'
    + '"axisExpandWidth":60,"axisExpandTriggerOn":"mousemove"},'
    + '"parallelAxis":[{"dim":0},{"dim":1},{"dim":2},{"dim":3},{"dim":4},{"dim":5}],'
    + '"series":[{"type":"parallel","data":[[1,2,3,4,5,6],[6,5,4,3,2,1]]}]}';

procedure TAdvChartThumbnailAxisExpandTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTaProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
end;

procedure TAdvChartThumbnailAxisExpandTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartThumbnailAxisExpandTest.Show(const AOption: string);
begin
  FChart.SetOption(AOption, True);
  RenderNow.Free;
end;

function TAdvChartThumbnailAxisExpandTest.RenderNow: TBGRABitmap;
begin
  Result := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FChart.Render(Result.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartThumbnailAxisExpandTest.TestTheThumbnailIsDrawnOverTheGraph;
var
  bmp: TBGRABitmap;
  st: TTyThumbState;
  p: TBGRAPixel;
  x, y, blue, green: Integer;
begin
  Show(cGraph);
  st := FChart.ThumbnailState(0);
  AssertTrue('the thumbnail is enabled', st.Enabled);
  AssertTrue('it has a view', st.View.Valid);
  AssertEquals('three symbols and two lines', 5, Length(st.Items));
  bmp := RenderNow;
  try
    blue := 0;
    green := 0;
    for y := Round(st.Box.Y) + 1 to Round(st.Box.Y + st.Box.H) - 2 do
      for x := Round(st.Box.X) + 1 to Round(st.Box.X + st.Box.W) - 2 do
      begin
        p := bmp.GetPixel(x, y);
        if (p.blue > 200) and (p.red < 60) and (p.green < 60) then Inc(blue);
        if (p.green > 200) and (p.red < 60) and (p.blue < 60) then Inc(green);
      end;
    AssertTrue('the box is filled with its own colour', blue > 0);
    AssertTrue('the window is drawn in it', green > 100);
    { the window covers the whole copy at the start: no blue inside it }
    p := bmp.GetPixel(Round(st.Window.X + st.Window.W / 2), Round(st.Window.Y + st.Window.H / 2));
    AssertTrue('the window is over the copy', (p.green > 200) or (p.red > 200));
  finally
    bmp.Free;
  end;
  { a roam moves the window, not the box }
  FChart.GraphRoam(0, 100, 0);
  st := FChart.ThumbnailState(0);
  AssertTrue('the window moved left', st.Window.X < FChart.ThumbnailState(0).Content.X + 1);
end;

procedure TAdvChartThumbnailAxisExpandTest.TestTheBoxHidesWhatIsUnderIt;
var
  st: TTyThumbState;
  d: TTyChartDatumRef;
begin
  { a node under the box: the box takes the hover }
  Show(StringReplace(cGraph, '"thumbnail":{', '"thumbnail":{"left":0,"top":0,"width":600,"height":400,', []));
  st := FChart.ThumbnailState(0);
  AssertTrue('the box covers the chart', st.Box.W > 500);
  d := FChart.HitTestAt(300, 200);
  AssertEquals('nothing under the box is hit', -1, d.SeriesIndex);
  AssertEquals('the box is what is there', 0, FChart.ThumbnailHitAt(300, 200));
  { show false: no box, nothing drawn }
  FChart.SetOption('{"thumbnail":{"show":false}}', False);
  RenderNow.Free;
  AssertFalse('a hidden thumbnail is not enabled', FChart.ThumbnailState(0).Enabled);
  AssertEquals('and hides nothing', -1, FChart.ThumbnailHitAt(300, 200));
end;

procedure TAdvChartThumbnailAxisExpandTest.TestTheExpansionEventCanBeSubscribed;
var
  got: TStringList;
  par: TTyParallel;
begin
  got := TStringList.Create;
  try
    Show(cPar);
    FChart.DispatchAction('{"type":"parallelAxisExpand","axisExpandWindow":[0,120]}');
    AssertTrue('the event came', FChart.Events.Count > 0);
    AssertEquals('it is the expansion''s', 'parallelaxisexpand',
      Copy(FChart.Events[0], 1, Pos(#9, FChart.Events[0]) - 1));
    AssertEquals('it is a known chart event', 'parallelaxisexpand',
      TyChartEventTypeOf('parallelAxisExpand'));
    RenderNow.Free;
    par := FChart.ParallelLayout(0);
    AssertNotNull('the parallel is laid out', par);
    AssertEquals('the window is the action''s', 0, par.ExpandWindow0, 0);
    AssertEquals('the window is the action''s (end)', 120, par.ExpandWindow1, 0);
    { a merge keeps the window: it is the model's option }
    FChart.SetOption('{"parallel":{"axisExpandCenter":4}}', False);
    RenderNow.Free;
    AssertEquals('the window outlives a merge', 0, FChart.ParallelLayout(0).ExpandWindow0, 0);
    { notMerge forgets it }
    Show(cPar);
    AssertTrue('a new model lays the window from the centre',
      FChart.ParallelLayout(0).ExpandWindow0 <> 0);
  finally
    got.Free;
  end;
end;

procedure TAdvChartThumbnailAxisExpandTest.TestTheThrottleRunsOnItsOwnClock;
var t0: Double;
begin
  Show(cPar);
  t0 := 1700000000000;
  FChart.ParallelExpandNow := t0;
  FChart.ParallelExpandClearLog;
  { a move far left: a jump, debounced 50 ms }
  FChart.MouseMove([], 85, 200);
  AssertEquals('nothing dispatched yet', 0, FChart.ParallelExpandActionCount);
  FChart.ParallelExpandNow := t0 + 49;
  FChart.ParallelExpandTick(t0 + 49);
  AssertEquals('still waiting at 49 ms', 0, FChart.ParallelExpandActionCount);
  FChart.ParallelExpandNow := t0 + 50;
  FChart.ParallelExpandTick(t0 + 50);
  AssertEquals('the jump lands at 50 ms', 1, FChart.ParallelExpandActionCount);
  AssertEquals('a jump animates (null)', 'null', FChart.ParallelExpandActionAt(0).Animation);
  AssertEquals('at its due time', t0 + 50, FChart.ParallelExpandActionAt(0).Time, 0);
  { a jump cancelled by a move into the quiet middle }
  FChart.ParallelExpandNow := t0 + 100;
  FChart.MouseMove([], 515, 200);
  FChart.ParallelExpandNow := t0 + 110;
  FChart.MouseMove([], 160, 200);
  FChart.ParallelExpandNow := t0 + 300;
  FChart.ParallelExpandTick(t0 + 300);
  AssertEquals('the cancelled jump never lands', 1, FChart.ParallelExpandActionCount);
end;

procedure TAdvChartThumbnailAxisExpandTest.TestHelpers;
var
  it: TTyThumbItem;
  r: TTyXYWH;
  v: TTyThumbView;
  items: TTyThumbItemArray;
  tm: TTyMat2D;
  w: TTyXYWH;
  txt: string;
  onn, pan, zoom: Boolean;
  d: TJSONData;
begin
  { a circle's rect, its stroke at the line width over a fill }
  it := Default(TTyThumbItem);
  it.Kind := tikSymbol;
  it.SymbolType := 'circle';
  it.X := 0; it.Y := 0; it.W := 10; it.H := 10;
  it.HasFill := True;
  it.HasStroke := True;
  it.LineWidth := 2;
  r := TyThumbItemRect(it);
  AssertEquals('the stroke widens the rect', -1, r.X, 0);
  AssertEquals('by the line width', 12, r.W, 0);
  { a line without a fill: at least five }
  it := Default(TTyThumbItem);
  it.Kind := tikLine;
  it.X1 := 0; it.Y1 := 0; it.X2 := 10; it.Y2 := 0;
  it.CPX := NaN; it.CPY := NaN;
  it.HasStroke := True;
  it.LineWidth := 1;
  r := TyThumbItemRect(it);
  AssertEquals('a line counts five', 5, r.H, 0);
  { no lines: the empty group puts (0, 0) in the rect }
  it := Default(TTyThumbItem);
  it.Kind := tikSymbol;
  it.SymbolType := 'rect';
  it.X := 50; it.Y := 60; it.W := 10; it.H := 10;
  it.HasFill := True;
  SetLength(items, 1);
  items[0] := it;
  r := TyThumbBridgeRect(items);
  AssertEquals('the origin is in', 0, r.X, 0);
  AssertEquals('to the far side', 70, r.H, 0);
  { the centred aspect: 0.8 of the binding side }
  r := TyThumbCentredAspect(TyXYWH(0, 0, 100, 50), 1);
  AssertEquals('the height binds', 40, r.H, 0);
  AssertEquals('centred', 30, r.X, 0);
  { the window of an identity graph over a 1:1 copy is the canvas mapped }
  tm := TyMatIdentity;
  v := TyThumbFit(items, TyXYWH(0, 0, 100, 100), tm);
  TyThumbUpdateWindow(v, tm, 600, 400, w);
  AssertTrue('the window is inside the thumbnail', w.W > 0);
  { roam words }
  d := GetJSON('"move"');
  try
    TyThumbRoamOf(d, txt, onn, pan, zoom);
    AssertTrue('move pans', pan and not zoom and onn);
  finally
    d.Free;
  end;
  TyThumbRoamOf(nil, txt, onn, pan, zoom);
  AssertFalse('no roam: off', onn);
  AssertEquals('as false', 'false', txt);
  AssertEquals('empty taken off', 'circle', TyThumbSymbolType('emptyCircle'));
end;

initialization
  RegisterTest(TAdvChartThumbnailAxisExpandOracleTest);
  RegisterTest(TAdvChartThumbnailAxisExpandTest);
end.
