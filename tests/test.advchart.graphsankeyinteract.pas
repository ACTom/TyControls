unit test.advchart.graphsankeyinteract;
{$mode objfpc}{$H+}
{ Graph and sankey interaction -- held to upstream to the bit [Batch 114].

  tools/advchart-oracle/graph-sankey-interact.js runs the real ECharts 6.1
  build through cases of pointer steps (zrender's own Handler: press, move,
  release and the click after it, the wheel), dispatched actions and resizes,
  and records after every step: for a graph, every node's data position, its
  pixel and its Symbol group's scale, every edge's trimmed ends and control
  point in data space, its lineStyle (width, opacity, stroke, dash), its two
  symbols, and its label's transform, alignment and words; for a sankey, the
  main group's transform, every node rect's corners and label, every band's
  local shape and label, the localX / localY the drags wrote, containPixel at
  fixed probes, the view's area and overall transform, and -- in the focus
  cases -- every node's and link's hover flag, state list, opacity, z2 and
  fill; and every action a gesture dispatched (dragNode, sankeyRoam).

  The port is driven the same way -- MouseDown / MouseMove / MouseUp /
  DoMouseWheel, DispatchAction, SetBounds -- with a headless render after
  each step, and compared through its own API and its paint list.

  Everything is compared to the bit, except a ring's layout (cos and sin are
  not correctly rounded in either runtime) and what is computed from it,
  which get a billionth; and a graph node's symbol half-extent, which a hover
  scales and is not compared. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Graph, tyControls.AdvChart.Color,
     tyControls.AdvChart.Sankey, tyControls.AdvChart.States,
     tyControls.AdvChart.Events,
     tyControls.AdvanceChart;
type
  TGsiProbe = class(TTyAdvanceChart)
  public
    Drags: array of string;
    Roams: array of TTyGraphRoamPayload;
    RoamIsSankey: array of Boolean;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    function Wheel(ADelta, AX, AY: Integer): Boolean;
    procedure OnDrag(Sender: TObject; const AEvent: TTyChartEvent);
    procedure OnSRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
    procedure OnGRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
  end;

  TAdvChartGraphSankeyInteractOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGsiProbe;
    FRoot: TJSONData;
    FBad, FCompared, FCases, FStates: Integer;
    FReport, FName: string;
    FTol: Double;
    FRing: Boolean;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot, AWant: Double);
    procedure SameNum(const AWhat: string; AGot: Double; AObj: TJSONObject;
      const AKey: string; AIndex: Integer = -1);
    procedure RenderNow(AW, AH: Integer);
    procedure NewChart;
    procedure Step(AStep: TJSONObject; var AW, AH: Integer);
    procedure CheckState(ACase, AState: TJSONObject; AIndex: Integer);
    procedure CheckGraph(ACase, ASeries: TJSONObject; AStateIndex: Integer);
    procedure CheckSankey(ACase, ASeries: TJSONObject);
    procedure CheckActions(AState: TJSONObject);
    procedure CheckSt(const AWhat: string; ASt: TJSONObject; const AItem: TTyStItem;
      AHave: Boolean; AElement: Integer);
    function FindEl(ASeries, AIndex: Integer; AEdge, ACaption: Boolean): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryDragLabelAndRoamLandsWhereUpstreamPutsIt;
  end;

  { What the oracle does not reach. }
  TAdvChartGraphSankeyInteractTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGsiProbe;
    procedure Show(const AOption: string);
    procedure RenderNow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAPressOnANodeIsNotAPanWhenItDrags;
    procedure TestALostCaptureEndsANodeDrag;
    procedure TestAForceDragUnfixesOnRelease;
    procedure TestAMergeKeepsWhatDragNodeWrote;
    procedure TestANotMergeForgetsWhatDragNodeWrote;
    procedure TestDragNodeActionNeedsADataIndex;
    procedure TestASankeyRoamRefusesANonPositiveZoom;
    procedure TestEdgeLabelSpecsFollowTheEdge;
    procedure TestARichEdgeLabelIsABlock;
    procedure TestASankeyEdgeLabelTakesItsLevelsStyle;
    procedure TestASankeyNodesCornersZoomWithTheRoam;
  end;

implementation

{ ==================== the probe ==================== }

procedure TGsiProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGsiProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TGsiProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TGsiProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TGsiProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TGsiProbe.Wheel(ADelta, AX, AY: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TGsiProbe.OnDrag(Sender: TObject; const AEvent: TTyChartEvent);
begin
  SetLength(Drags, Length(Drags) + 1);
  Drags[High(Drags)] := AEvent.Payload;
end;

procedure TGsiProbe.OnSRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
begin
  SetLength(Roams, Length(Roams) + 1);
  Roams[High(Roams)] := APayload;
  SetLength(RoamIsSankey, Length(RoamIsSankey) + 1);
  RoamIsSankey[High(RoamIsSankey)] := True;
end;

procedure TGsiProbe.OnGRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
begin
  SetLength(Roams, Length(Roams) + 1);
  Roams[High(Roams)] := APayload;
  SetLength(RoamIsSankey, Length(RoamIsSankey) + 1);
  RoamIsSankey[High(RoamIsSankey)] := False;
end;

{ ==================== the fixture's numbers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-graph-sankey-interact.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  System.Move(q, Result, SizeOf(Result));
end;

function TwinNum(AData, ATwin: TJSONData): Double;
var s: string;
begin
  if (AData <> nil) and (AData.JSONType <> jtNull) then Exit(HexNum(AData));
  Result := NaN;
  if (ATwin = nil) or (ATwin.JSONType <> jtString) then Exit;
  s := ATwin.AsString;
  if s = 'Infinity' then Result := Infinity
  else if s = '-Infinity' then Result := NegInfinity;
end;

function NumAt(AObj: TJSONObject; const AKey: string; AIndex: Integer = -1): Double;
var d, t: TJSONData;
begin
  d := AObj.Find(AKey);
  t := AObj.Find(AKey + 'Text');
  if AIndex >= 0 then
  begin
    if (d is TJSONArray) and (AIndex < TJSONArray(d).Count) then
      d := TJSONArray(d).Items[AIndex]
    else
      d := nil;
    if (t is TJSONArray) and (AIndex < TJSONArray(t).Count) then
      t := TJSONArray(t).Items[AIndex]
    else
      t := nil;
  end;
  Result := TwinNum(d, t);
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function AlignOf(const AWord: string; out AH: TTyTextAnchorH): Boolean;
begin
  Result := True;
  if AWord = 'left' then AH := tahLeft
  else if AWord = 'center' then AH := tahCentre
  else if AWord = 'right' then AH := tahRight
  else Result := False;
end;

function VAlignOf(const AWord: string; out AV: TTyTextAnchorV): Boolean;
begin
  Result := True;
  if AWord = 'top' then AV := tavTop
  else if AWord = 'middle' then AV := tavMiddle
  else if AWord = 'bottom' then AV := tavBottom
  else Result := False;
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartGraphSankeyInteractOracleTest.SetUp;
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
  FCases := 0;
  FStates := 0;
  FReport := '';
end;

procedure TAdvChartGraphSankeyInteractOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphSankeyInteractOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartGraphSankeyInteractOracleTest.Same(const AWhat: string;
  AGot, AWant: Double);
var ok: Boolean;
begin
  Inc(FCompared);
  if IsNan(AWant) or IsNan(AGot) then ok := IsNan(AWant) and IsNan(AGot)
  else if IsInfinite(AWant) or IsInfinite(AGot) then ok := AGot = AWant
  else if AGot = AWant then ok := True
  else ok := Abs(AGot - AWant) <= FTol * Math.Max(Double(1), Abs(AWant));
  if not ok then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(AWant), Fmt(AGot)]));
end;

procedure TAdvChartGraphSankeyInteractOracleTest.SameNum(const AWhat: string;
  AGot: Double; AObj: TJSONObject; const AKey: string; AIndex: Integer);
begin
  Same(AWhat, AGot, NumAt(AObj, AKey, AIndex));
end;

{ A NEW CHART PER CASE, as the oracle makes one: a notMerge on the same
  control would carry the last case's state records over (the reused rows). }
procedure TAdvChartGraphSankeyInteractOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TGsiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.OnSankeyRoam := @FChart.OnSRoam;
  FChart.OnGraphRoam := @FChart.OnGRoam;
  FChart.ChartOn('dragnode', @FChart.OnDrag);
end;

procedure TAdvChartGraphSankeyInteractOracleTest.RenderNow(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartGraphSankeyInteractOracleTest.Step(AStep: TJSONObject;
  var AW, AH: Integer);
var a: TJSONArray; d: TJSONData;
begin
  d := AStep.Find('down');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Down(a.Integers[0], a.Integers[1]);
    Exit;
  end;
  d := AStep.Find('move');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Move(a.Integers[0], a.Integers[1]);
    Exit;
  end;
  d := AStep.Find('up');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Up(a.Integers[0], a.Integers[1]);
    Exit;
  end;
  d := AStep.Find('wheel');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Wheel(a.Integers[2], a.Integers[0], a.Integers[1]);
    Exit;
  end;
  if AStep.Find('leave') <> nil then
  begin
    FChart.Move(-10, -10);
    Exit;
  end;
  d := AStep.Find('action');
  if d is TJSONObject then
  begin
    if not FChart.DispatchAction(d.AsJSON) then Miss('the action was refused: ' + d.AsJSON);
    Exit;
  end;
  d := AStep.Find('resize');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    AW := a.Integers[0];
    AH := a.Integers[1];
    FChart.SetBounds(0, 0, AW, AH);
    Exit;
  end;
  Miss('an unknown step ' + AStep.AsJSON);
end;

{ the element of a datum: the host (no caption) or its caption }
function TAdvChartGraphSankeyInteractOracleTest.FindEl(ASeries, AIndex: Integer;
  AEdge, ACaption: Boolean): Integer;
var i: Integer; el: TTyChartElement; l: TTyPaintList;
begin
  Result := -1;
  l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
  begin
    el := l.Element(i);
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> ASeries) then Continue;
    if (el.Datum.DataIndex <> AIndex) or (el.Datum.IsEdge <> AEdge) then Continue;
    if (el.Caption.FontSizeLogical > 0) <> ACaption then Continue;
    if not ACaption and el.Silent then Continue;
    Exit(i);
  end;
end;

procedure TAdvChartGraphSankeyInteractOracleTest.CheckActions(AState: TJSONObject);
var
  acts: TJSONArray;
  i, nd, nr: Integer;
  a: TJSONObject;
  t: string;
  p: TJSONData;
begin
  acts := AState.Arrays['actions'];
  nd := 0;
  nr := 0;
  for i := 0 to acts.Count - 1 do
  begin
    a := TJSONObject(acts.Items[i]);
    t := a.Strings['type'];
    Inc(FCompared);
    if t = 'dragNode' then
    begin
      if nd > High(FChart.Drags) then
      begin
        Miss('a dragNode upstream that was not dispatched here');
        Inc(nd);
        Continue;
      end;
      p := GetJSON(FChart.Drags[nd]);
      try
        if (p as TJSONObject).Integers['dataIndex'] <> a.Integers['dataIndex'] then
          Miss('dragNode dataIndex');
        Same('dragNode localX', (p as TJSONObject).Floats['localX'], NumAt(a, 'localX'));
        Same('dragNode localY', (p as TJSONObject).Floats['localY'], NumAt(a, 'localY'));
      finally
        p.Free;
      end;
      Inc(nd);
    end
    else if (t = 'sankeyRoam') or (t = 'graphRoam') then
    begin
      if nr > High(FChart.Roams) then
      begin
        Miss('a ' + t + ' upstream that was not dispatched here');
        Inc(nr);
        Continue;
      end;
      if FChart.RoamIsSankey[nr] <> (t = 'sankeyRoam') then Miss('the roam went to the other kind');
      if a.Find('zoom') <> nil then
      begin
        if not FChart.Roams[nr].HasZoom then Miss('a zoom upstream, none here')
        else
        begin
          Same('roam zoom', FChart.Roams[nr].Zoom, NumAt(a, 'zoom'));
          Same('roam originX', FChart.Roams[nr].OriginX, NumAt(a, 'originX'));
          Same('roam originY', FChart.Roams[nr].OriginY, NumAt(a, 'originY'));
        end;
      end
      else
      begin
        if not FChart.Roams[nr].HasPan then Miss('a pan upstream, none here')
        else
        begin
          Same('roam dx', FChart.Roams[nr].DX, NumAt(a, 'dx'));
          Same('roam dy', FChart.Roams[nr].DY, NumAt(a, 'dy'));
        end;
      end;
      Inc(nr);
    end;
  end;
  Inc(FCompared);
  if nd <> Length(FChart.Drags) then
    Miss(Format('%d dragNode upstream, %d here', [nd, Length(FChart.Drags)]));
  Inc(FCompared);
  if nr <> Length(FChart.Roams) then
    Miss(Format('%d roams upstream, %d here', [nr, Length(FChart.Roams)]));
end;

procedure TAdvChartGraphSankeyInteractOracleTest.CheckSt(const AWhat: string;
  ASt: TJSONObject; const AItem: TTyStItem; AHave: Boolean; AElement: Integer);
var el: TTyChartElement; c: TTyChartColor; fs: string;
begin
  if not AHave then
  begin
    Miss(AWhat + ' has no state record here');
    Exit;
  end;
  Inc(FCompared);
  if AItem.Host.HoverState <> ASt.Integers['hover'] then
    Miss(Format('%s hover is %d upstream, %d here', [AWhat, ASt.Integers['hover'],
      AItem.Host.HoverState]));
  Inc(FCompared);
  if TyStNamesText(AItem.Host.States) <> ASt.Strings['states'] then
    Miss(Format('%s states are "%s" upstream, "%s" here', [AWhat, ASt.Strings['states'],
      TyStNamesText(AItem.Host.States)]));
  if AElement < 0 then
  begin
    Miss(AWhat + ' is not drawn here');
    Exit;
  end;
  el := FChart.List.Element(AElement);
  SameNum(AWhat + ' opacity', el.Style.Alpha, ASt, 'opacity');
  Inc(FCompared);
  if el.Z2 <> ASt.Integers['z2'] then
    Miss(Format('%s z2 is %d upstream, %d here', [AWhat, ASt.Integers['z2'], el.Z2]));
  if (ASt.Find('fill') <> nil) and (ASt.Find('fill').JSONType = jtString) then
  begin
    fs := ASt.Strings['fill'];
    Inc(FCompared);
    if TyTryParseChartColor(fs, c) then
    begin
      if (not el.Style.HasFill) or (el.Style.FillColor <> c) then
        Miss(Format('%s fill is %s upstream, %s here', [AWhat, fs,
          IntToHex(el.Style.FillColor, 8)]));
    end;
  end;
end;

procedure TAdvChartGraphSankeyInteractOracleTest.CheckGraph(ACase, ASeries: TJSONObject;
  AStateIndex: Integer);
var
  si, i, k, e: Integer;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  arr: TJSONArray;
  n, ed, lab: TJSONObject;
  v: TTyGraphView;
  ink: TTyGraphInk;
  spec: TTyGraphSpec;
  tag, w: string;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  el: TTyChartElement;
  c: TTyChartColor;
  dash: TTyDoubleArray;
  da: TJSONArray;
  ring, curved: Boolean;
  wd: Double;
begin
  si := ASeries.Integers['index'];
  tag := 'g' + IntToStr(si);
  if not FChart.GraphLayout(si, nodes, edges, fills) then
  begin
    Miss(tag + ': no layout here');
    Exit;
  end;
  FChart.GraphInkOf(si, ink, spec);
  v := FChart.GraphView(si);
  ring := FRing;
  { the view }
  if (ASeries.Find('overall') <> nil) and (ASeries.Find('overall').JSONType = jtArray) then
  begin
    if v = nil then Miss(tag + ': a view upstream, none here')
    else
    begin
      SameNum(tag + ' overall sx', v.OverallScaleX, ASeries, 'overall', 0);
      SameNum(tag + ' overall sy', v.OverallScaleY, ASeries, 'overall', 1);
      SameNum(tag + ' overall x', v.OverallX, ASeries, 'overall', 2);
      SameNum(tag + ' overall y', v.OverallY, ASeries, 'overall', 3);
    end;
  end;
  { the nodes }
  arr := ASeries.Arrays['nodes'];
  for i := 0 to arr.Count - 1 do
  begin
    if arr.Items[i].JSONType = jtNull then Continue;
    n := TJSONObject(arr.Items[i]);
    if i > High(nodes) then
    begin
      Miss(Format('%s node %d is not here', [tag, i]));
      Continue;
    end;
    if ring and not (nodes[i].Fixed and nodes[i].HasDragScale) then FTol := 1e-9 else FTol := 0;
    if v <> nil then
    begin
      SameNum(Format('%s node %d x', [tag, i]), nodes[i].X, n, 'layout', 0);
      SameNum(Format('%s node %d y', [tag, i]), nodes[i].Y, n, 'layout', 1);
    end;
    SameNum(Format('%s node %d px', [tag, i]), nodes[i].PX, n, 'px', 0);
    SameNum(Format('%s node %d py', [tag, i]), nodes[i].PY, n, 'px', 1);
    FTol := 0;
    { the Symbol group's scale: a drag's own, else the series' }
    if v <> nil then
    begin
      if nodes[i].HasDragScale then
      begin
        SameNum(Format('%s node %d drag scale x', [tag, i]), nodes[i].DragScaleX, n, 'scale', 0);
        SameNum(Format('%s node %d drag scale y', [tag, i]), nodes[i].DragScaleY, n, 'scale', 1);
      end
      else
        SameNum(Format('%s node %d scale', [tag, i]), FChart.GraphNodeScale(si), n, 'scale', 0);
    end;
    if ring then
    begin
      Inc(FCompared);
      if nodes[i].Fixed <> n.Booleans['fixed'] then
        Miss(Format('%s node %d fixed is %s upstream', [tag, i, BoolToStr(n.Booleans['fixed'], True)]));
    end;
  end;
  { the edges }
  arr := ASeries.Arrays['edges'];
  for e := 0 to arr.Count - 1 do
  begin
    if arr.Items[e].JSONType = jtNull then Continue;
    ed := TJSONObject(arr.Items[e]);
    if e > High(edges) then
    begin
      Miss(Format('%s edge %d is not here', [tag, e]));
      Continue;
    end;
    if ring then FTol := 1e-9 else FTol := 0;
    curved := (ed.Find('cp') <> nil) and (ed.Find('cp').JSONType = jtArray);
    if v <> nil then
    begin
      SameNum(Format('%s edge %d x1', [tag, e]), edges[e].TX1, ed, 'shape', 0);
      SameNum(Format('%s edge %d y1', [tag, e]), edges[e].TY1, ed, 'shape', 1);
      SameNum(Format('%s edge %d x2', [tag, e]), edges[e].TX2, ed, 'shape', 2);
      SameNum(Format('%s edge %d y2', [tag, e]), edges[e].TY2, ed, 'shape', 3);
      Inc(FCompared);
      if curved <> edges[e].Curved then
        Miss(Format('%s edge %d curved is %s upstream', [tag, e, BoolToStr(curved, True)]))
      else if curved then
      begin
        SameNum(Format('%s edge %d cpx', [tag, e]), edges[e].TCPX, ed, 'cp', 0);
        SameNum(Format('%s edge %d cpy', [tag, e]), edges[e].TCPY, ed, 'cp', 1);
      end;
    end;
    FTol := 0;
    { the edge's own lineStyle and symbols }
    SameNum(Format('%s edge %d width', [tag, e]), TyGraphEdgeWidth(spec, edges[e]), ed, 'lineWidth');
    SameNum(Format('%s edge %d opacity', [tag, e]), TyGraphEdgeOpacity(spec, edges[e]), ed, 'opacity');
    w := '';
    if ed.Find('fromSymbol').JSONType = jtString then w := ed.Strings['fromSymbol'];
    Inc(FCompared);
    if TyGraphEdgeSymbol(spec, edges[e], False) <> w then
      Miss(Format('%s edge %d from symbol is "%s" upstream, "%s" here', [tag, e, w,
        TyGraphEdgeSymbol(spec, edges[e], False)]));
    w := '';
    if ed.Find('toSymbol').JSONType = jtString then w := ed.Strings['toSymbol'];
    Inc(FCompared);
    if TyGraphEdgeSymbol(spec, edges[e], True) <> w then
      Miss(Format('%s edge %d to symbol is "%s" upstream, "%s" here', [tag, e, w,
        TyGraphEdgeSymbol(spec, edges[e], True)]));
    SameNum(Format('%s edge %d from size', [tag, e]), TyGraphEdgeSymbolSize(spec, edges[e], False), ed, 'fromSize');
    SameNum(Format('%s edge %d to size', [tag, e]), TyGraphEdgeSymbolSize(spec, edges[e], True), ed, 'toSize');
    { the dash, as zrender turns the style's word or array into lengths }
    dash := TyGraphEdgeDash(spec, edges[e]);
    wd := TyGraphEdgeWidth(spec, edges[e]);
    Inc(FCompared);
    if (ed.Find('dashWord') <> nil) and (ed.Find('dashWord').JSONType = jtString) then
    begin
      if ed.Strings['dashWord'] = 'dashed' then
      begin
        if (Length(dash) <> 2) or (dash[0] <> 4 * wd) or (dash[1] <> 2 * wd) then
          Miss(Format('%s edge %d is dashed upstream', [tag, e]));
      end
      else if ed.Strings['dashWord'] = 'dotted' then
      begin
        if (Length(dash) <> 1) or (dash[0] <> wd) then
          Miss(Format('%s edge %d is dotted upstream', [tag, e]));
      end;
    end
    else if ed.Find('dash').JSONType = jtArray then
    begin
      da := ed.Arrays['dash'];
      if Length(dash) <> da.Count then
        Miss(Format('%s edge %d has a %d-dash upstream, %d here', [tag, e, da.Count, Length(dash)]))
      else
        for k := 0 to High(dash) do
          Same(Format('%s edge %d dash %d', [tag, e, k]), dash[k], HexNum(da.Items[k]));
    end
    else if Length(dash) > 0 then
      Miss(Format('%s edge %d is solid upstream', [tag, e]));
    { the stroke actually drawn }
    k := FindEl(si, edges[e].Row, True, False);
    if (ed.Find('stroke').JSONType = jtString) and TyTryParseChartColor(ed.Strings['stroke'], c)
      and (Pos('gs-', ACase.Strings['id']) = 1) then
    begin
      Inc(FCompared);
      if k < 0 then Miss(Format('%s edge %d is not drawn', [tag, e]))
      else
      begin
        el := FChart.List.Element(k);
        if el.Style.StrokeColor <> c then
          Miss(Format('%s edge %d stroke is %s upstream, %s here', [tag, e,
            ed.Strings['stroke'], IntToHex(el.Style.StrokeColor, 8)]));
      end;
    end;
    { the label }
    k := FindEl(si, edges[e].Row, True, True);
    Inc(FCompared);
    if (ed.Find('label').JSONType <> jtObject)
      or TJSONObject(ed.Find('label')).Booleans['ignore'] then
    begin
      if (k >= 0) and not FChart.List.Element(k).Ignore then
        Miss(Format('%s edge %d has a label here, none upstream', [tag, e]));
      Continue;
    end;
    lab := TJSONObject(ed.Find('label'));
    if k < 0 then
    begin
      Miss(Format('%s edge %d label "%s" is not here', [tag, e, lab.Strings['text']]));
      Continue;
    end;
    el := FChart.List.Element(k);
    Inc(FCompared);
    if el.Caption.Text <> lab.Strings['text'] then
      Miss(Format('%s edge %d label is "%s" upstream, "%s" here', [tag, e,
        lab.Strings['text'], el.Caption.Text]));
    if ring then FTol := 1e-9 else FTol := 0;
    SameNum(Format('%s edge %d label x', [tag, e]), el.Caption.X, lab, 'm', 4);
    SameNum(Format('%s edge %d label y', [tag, e]), el.Caption.Y, lab, 'm', 5);
    SameNum(Format('%s edge %d label rotation', [tag, e]), el.Caption.RotationRad, lab, 'local', 2);
    FTol := 0;
    if (lab.Find('align').JSONType = jtString) and AlignOf(lab.Strings['align'], ah) then
    begin
      Inc(FCompared);
      if el.Caption.AnchorH <> ah then
        Miss(Format('%s edge %d label align is %s upstream', [tag, e, lab.Strings['align']]));
    end;
    if (lab.Find('vAlign').JSONType = jtString) and VAlignOf(lab.Strings['vAlign'], av) then
    begin
      Inc(FCompared);
      if el.Caption.AnchorV <> av then
        Miss(Format('%s edge %d label vAlign is %s upstream', [tag, e, lab.Strings['vAlign']]));
    end;
    SameNum(Format('%s edge %d label opacity', [tag, e]), el.Style.Alpha, lab, 'opacity');
  end;
  if AStateIndex < 0 then ;
end;

procedure TAdvChartGraphSankeyInteractOracleTest.CheckSankey(ACase, ASeries: TJSONObject);
var
  si, i, k, p: Integer;
  s: TTySankeySolved;
  v: TTyGraphView;
  arr, pr: TJSONArray;
  n, ed, lab: TJSONObject;
  el: TTyChartElement;
  tag, cont: string;
  r: TTyRectF;
  xs, ys: array[0..1] of Double;
  m0, m3, m4, m5, x, y: Double;
  item: TTyStItem;
  have: Boolean;
  xy: TTyXYWH;
  focus: Boolean;
  sh: TJSONArray;
begin
  si := ASeries.Integers['index'];
  tag := 's' + IntToStr(si);
  s := FChart.SankeySolved(si);
  if not s.Valid then
  begin
    Miss(tag + ': no sankey here');
    Exit;
  end;
  focus := ACase.Strings['group'] = 'focus-sankey';
  { the main group's transform }
  SameNum(tag + ' m0', s.M0, ASeries, 'm', 0);
  SameNum(tag + ' m3', s.M3, ASeries, 'm', 3);
  SameNum(tag + ' m4', s.M4, ASeries, 'm', 4);
  SameNum(tag + ' m5', s.M5, ASeries, 'm', 5);
  m0 := NumAt(ASeries, 'm', 0);
  m3 := NumAt(ASeries, 'm', 3);
  m4 := NumAt(ASeries, 'm', 4);
  m5 := NumAt(ASeries, 'm', 5);
  { the view: its overall transform and area }
  v := FChart.SankeyView(si);
  if ASeries.Find('overall').JSONType = jtArray then
  begin
    if v = nil then Miss(tag + ': no view here')
    else
    begin
      SameNum(tag + ' overall sx', v.OverallScaleX, ASeries, 'overall', 0);
      SameNum(tag + ' overall sy', v.OverallScaleY, ASeries, 'overall', 1);
      SameNum(tag + ' overall x', v.OverallX, ASeries, 'overall', 2);
      SameNum(tag + ' overall y', v.OverallY, ASeries, 'overall', 3);
      xy := v.TriggerRect;
      SameNum(tag + ' trigger x', xy.X, ASeries, 'trigger', 0);
      SameNum(tag + ' trigger y', xy.Y, ASeries, 'trigger', 1);
      SameNum(tag + ' trigger w', xy.W, ASeries, 'trigger', 2);
      SameNum(tag + ' trigger h', xy.H, ASeries, 'trigger', 3);
    end;
  end;
  { containPixel at the probes }
  pr := ACase.Arrays['probes'];
  cont := ASeries.Strings['contain'];
  for p := 0 to pr.Count - 1 do
  begin
    Inc(FCompared);
    if FChart.ContainPixel(Format('{"seriesIndex":%d}', [si]),
      TJSONArray(pr.Items[p]).Integers[0], TJSONArray(pr.Items[p]).Integers[1])
      <> (Copy(cont, p + 1, 1) = '1') then
      Miss(Format('%s probe (%d, %d) is %s upstream', [tag, TJSONArray(pr.Items[p]).Integers[0],
        TJSONArray(pr.Items[p]).Integers[1], BoolToStr(Copy(cont, p + 1, 1) = '1', 'inside', 'outside')]));
  end;
  { what the drags wrote }
  arr := ASeries.Arrays['localX'];
  for i := 0 to arr.Count - 1 do
  begin
    Inc(FCompared);
    have := (i <= High(s.Local)) and s.Local[i].HasX;
    if arr.Items[i].JSONType = jtNull then
    begin
      if have then Miss(Format('%s node %d has a localX here', [tag, i]));
    end
    else if not have then Miss(Format('%s node %d has a localX upstream', [tag, i]))
    else Same(Format('%s node %d localX', [tag, i]), s.Local[i].X, NumAt(TJSONObject(arr.Items[i]), 'v'));
  end;
  arr := ASeries.Arrays['localY'];
  for i := 0 to arr.Count - 1 do
  begin
    Inc(FCompared);
    have := (i <= High(s.Local)) and s.Local[i].HasY;
    if arr.Items[i].JSONType = jtNull then
    begin
      if have then Miss(Format('%s node %d has a localY here', [tag, i]));
    end
    else if not have then Miss(Format('%s node %d has a localY upstream', [tag, i]))
    else Same(Format('%s node %d localY', [tag, i]), s.Local[i].Y, NumAt(TJSONObject(arr.Items[i]), 'v'));
  end;
  { the nodes: their corners, their labels, their states }
  arr := ASeries.Arrays['nodes'];
  for i := 0 to arr.Count - 1 do
  begin
    if arr.Items[i].JSONType = jtNull then Continue;
    n := TJSONObject(arr.Items[i]);
    k := FindEl(si, i, False, False);
    if k < 0 then
    begin
      Miss(Format('%s node %d is not drawn here', [tag, i]));
      Continue;
    end;
    el := FChart.List.Element(k);
    r := TyShapeBounds(el.Shape);
    { corners as a set on each axis: a rect of negative height turns round }
    xs[0] := NumAt(n, 'corners', 0);
    xs[1] := NumAt(n, 'corners', 2);
    ys[0] := NumAt(n, 'corners', 1);
    ys[1] := NumAt(n, 'corners', 3);
    Same(Format('%s node %d left', [tag, i]), r.Left, Math.Min(xs[0], xs[1]));
    Same(Format('%s node %d right', [tag, i]), r.Right, Math.Max(xs[0], xs[1]));
    Same(Format('%s node %d top', [tag, i]), r.Top, Math.Min(ys[0], ys[1]));
    Same(Format('%s node %d bottom', [tag, i]), r.Bottom, Math.Max(ys[0], ys[1]));
    if n.Find('label').JSONType = jtObject then
    begin
      lab := TJSONObject(n.Find('label'));
      k := FindEl(si, i, False, True);
      if k < 0 then Miss(Format('%s node %d label is not here', [tag, i]))
      else
      begin
        el := FChart.List.Element(k);
        Inc(FCompared);
        if el.Caption.Text <> lab.Strings['text'] then
          Miss(Format('%s node %d label is "%s" upstream, "%s" here', [tag, i,
            lab.Strings['text'], el.Caption.Text]));
        SameNum(Format('%s node %d label x', [tag, i]), el.Caption.X, lab, 'x');
        SameNum(Format('%s node %d label y', [tag, i]), el.Caption.Y, lab, 'y');
      end;
    end;
    if focus then
    begin
      have := FChart.ItemStates(si, i, item);
      CheckSt(Format('%s node %d', [tag, i]), n.Objects['st'], item, have, FindEl(si, i, False, False));
    end;
  end;
  { the bands: the local shape through the main group, the labels, the states }
  arr := ASeries.Arrays['edges'];
  for i := 0 to arr.Count - 1 do
  begin
    if arr.Items[i].JSONType = jtNull then Continue;
    ed := TJSONObject(arr.Items[i]);
    k := FindEl(si, i, True, False);
    if k < 0 then
    begin
      Miss(Format('%s edge %d is not drawn here', [tag, i]));
      Continue;
    end;
    el := FChart.List.Element(k);
    sh := ed.Arrays['shape'];
    if Length(el.Shape.Cmds) < 2 then
      Miss(Format('%s edge %d has no curve here', [tag, i]))
    else
    begin
      x := HexNum(sh.Items[0]);
      y := HexNum(sh.Items[1]);
      Same(Format('%s edge %d x1', [tag, i]), el.Shape.Cmds[0].X, m0 * x + 0 * y + m4);
      Same(Format('%s edge %d y1', [tag, i]), el.Shape.Cmds[0].Y, 0 * x + m3 * y + m5);
      x := HexNum(sh.Items[2]);
      y := HexNum(sh.Items[3]);
      Same(Format('%s edge %d cpx1', [tag, i]), el.Shape.Cmds[1].X1, m0 * x + 0 * y + m4);
      Same(Format('%s edge %d cpy1', [tag, i]), el.Shape.Cmds[1].Y1, 0 * x + m3 * y + m5);
      x := HexNum(sh.Items[4]);
      y := HexNum(sh.Items[5]);
      Same(Format('%s edge %d cpx2', [tag, i]), el.Shape.Cmds[1].X2, m0 * x + 0 * y + m4);
      Same(Format('%s edge %d cpy2', [tag, i]), el.Shape.Cmds[1].Y2, 0 * x + m3 * y + m5);
      x := HexNum(sh.Items[6]);
      y := HexNum(sh.Items[7]);
      Same(Format('%s edge %d x2', [tag, i]), el.Shape.Cmds[1].X, m0 * x + 0 * y + m4);
      Same(Format('%s edge %d y2', [tag, i]), el.Shape.Cmds[1].Y, 0 * x + m3 * y + m5);
    end;
    if ed.Find('label').JSONType = jtObject then
    begin
      lab := TJSONObject(ed.Find('label'));
      k := FindEl(si, i, True, True);
      if k < 0 then Miss(Format('%s edge %d label "%s" is not here', [tag, i, lab.Strings['text']]))
      else
      begin
        el := FChart.List.Element(k);
        Inc(FCompared);
        if el.Caption.Text <> lab.Strings['text'] then
          Miss(Format('%s edge %d label is "%s" upstream, "%s" here', [tag, i,
            lab.Strings['text'], el.Caption.Text]));
        SameNum(Format('%s edge %d label x', [tag, i]), el.Caption.X, lab, 'x');
        SameNum(Format('%s edge %d label y', [tag, i]), el.Caption.Y, lab, 'y');
      end;
    end
    else
    begin
      k := FindEl(si, i, True, True);
      Inc(FCompared);
      if (k >= 0) and not FChart.List.Element(k).Ignore then
        Miss(Format('%s edge %d has a label here, none upstream', [tag, i]));
    end;
    if focus then
    begin
      have := FChart.SankeyEdgeStates(si, i, item);
      CheckSt(Format('%s edge %d', [tag, i]), ed.Objects['st'], item, have, FindEl(si, i, True, False));
    end;
  end;
end;

procedure TAdvChartGraphSankeyInteractOracleTest.CheckState(ACase, AState: TJSONObject;
  AIndex: Integer);
var
  arr: TJSONArray;
  i: Integer;
  ser: TJSONObject;
begin
  Inc(FStates);
  CheckActions(AState);
  arr := AState.Arrays['series'];
  for i := 0 to arr.Count - 1 do
  begin
    ser := TJSONObject(arr.Items[i]);
    if ser.Strings['type'] = 'graph' then CheckGraph(ACase, ser, AIndex)
    else CheckSankey(ACase, ser);
  end;
end;

procedure TAdvChartGraphSankeyInteractOracleTest.TestEveryDragLabelAndRoamLandsWhereUpstreamPutsIt;
var
  cases, steps, states: TJSONArray;
  cs, st: TJSONObject;
  c, k, w, h: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := TJSONObject(cases.Items[c]);
    FName := cs.Strings['id'];
    Inc(FCases);
    FTol := 0;
    FRing := cs.Booleans['ring'];
    w := cs.Integers['W'];
    h := cs.Integers['H'];
    NewChart;
    FChart.SetBounds(0, 0, w, h);
    FChart.Option := cs.Objects['option'].AsJSON;
    FChart.Drags := nil;
    FChart.Roams := nil;
    FChart.RoamIsSankey := nil;
    RenderNow(w, h);
    states := cs.Arrays['states'];
    steps := cs.Arrays['steps'];
    CheckState(cs, TJSONObject(states.Items[0]), 0);
    for k := 0 to steps.Count - 1 do
    begin
      st := TJSONObject(steps.Items[k]);
      FChart.Drags := nil;
      FChart.Roams := nil;
      FChart.RoamIsSankey := nil;
      Step(st, w, h);
      { an action step's own events are not the gesture's }
      if st.Find('action') <> nil then
      begin
        FChart.Drags := nil;
        FChart.Roams := nil;
        FChart.RoamIsSankey := nil;
      end;
      RenderNow(w, h);
      CheckState(cs, TJSONObject(states.Items[k + 1]), k + 1);
    end;
  end;
  AssertTrue(Format('every case ran (%d)', [FCases]), FCases >= 30);
  AssertTrue(Format('and a great deal was compared (%d)', [FCompared]), FCompared > 3000);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

{ ==================== the rest ==================== }

const
  cSankey = '{"animation":false,"series":[{"type":"sankey","roam":true,'
    + '"data":[{"name":"a"},{"name":"b"},{"name":"c"}],'
    + '"links":[{"source":"a","target":"b","value":5},{"source":"a","target":"c","value":3}]}]}';
  cForce = '{"animation":false,"series":[{"type":"graph","layout":"force","draggable":true,'
    + '"symbolSize":16,"force":{"layoutAnimation":false,"repulsion":100,"edgeLength":50},'
    + '"data":[{"name":"a","value":1},{"name":"b","value":2},{"name":"c","value":3}],'
    + '"links":[{"source":"a","target":"b"},{"source":"b","target":"c"}]}]}';
  cNone = '{"animation":false,"series":[{"type":"graph","layout":"none","draggable":true,'
    + '"roam":true,"symbolSize":30,"data":[{"name":"a","x":0,"y":0},{"name":"b","x":100,"y":50}],'
    + '"links":[{"source":"a","target":"b","label":{"show":true,"position":"end"}}],'
    + '"edgeLabel":{"show":false,"position":"start","distance":[2,4]}}]}';

procedure TAdvChartGraphSankeyInteractTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TGsiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.OnSankeyRoam := @FChart.OnSRoam;
  FChart.OnGraphRoam := @FChart.OnGRoam;
  FChart.ChartOn('dragnode', @FChart.OnDrag);
  FChart.SetBounds(0, 0, 400, 300);
end;

procedure TAdvChartGraphSankeyInteractTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphSankeyInteractTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartGraphSankeyInteractTest.Show(const AOption: string);
begin
  FChart.Option := AOption;
  RenderNow;
end;

{ A press on a draggable node takes the node, not the view: the drag moves
  the node and no roam is dispatched. }
procedure TAdvChartGraphSankeyInteractTest.TestAPressOnANodeIsNotAPanWhenItDrags;
var
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  x0, y0: Double;
begin
  Show(cNone);
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  x0 := nodes[0].X;
  y0 := nodes[0].Y;
  FChart.Down(Round(nodes[0].PX), Round(nodes[0].PY));
  FChart.Move(Round(nodes[0].PX) + 20, Round(nodes[0].PY) + 10);
  FChart.Up(Round(nodes[0].PX) + 20, Round(nodes[0].PY) + 10);
  RenderNow;
  AssertEquals('no roam', 0, Length(FChart.Roams));
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  AssertTrue('the node moved', (nodes[0].X <> x0) or (nodes[0].Y <> y0));
  AssertTrue('its symbol took the drift''s scale', nodes[0].HasDragScale);
end;

{ The capture lost mid-drag ends the drag: the next move moves nothing. }
procedure TAdvChartGraphSankeyInteractTest.TestALostCaptureEndsANodeDrag;
var
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  x1: Double;
  px, py: Integer;
begin
  Show(cNone);
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  px := Round(nodes[0].PX);
  py := Round(nodes[0].PY);
  FChart.Down(px, py);
  FChart.Move(px + 10, py);
  RenderNow;
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  x1 := nodes[0].X;
  FChart.CaptureChanged;
  FChart.Move(px + 40, py);
  RenderNow;
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  AssertEquals('the node stays where the drag left it', x1, nodes[0].X);
end;

{ dragend unfixes the dragged force node, an option-pinned one included. }
procedure TAdvChartGraphSankeyInteractTest.TestAForceDragUnfixesOnRelease;
var
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  st: TTyGraphForceState;
  px, py: Integer;
begin
  Show(cForce);
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  px := Round(nodes[1].PX);
  py := Round(nodes[1].PY);
  FChart.Down(px, py);
  FChart.Move(px + 5, py + 5);
  st := FChart.GraphForceState(0);
  AssertTrue('the instance was kept', st.HasInst);
  AssertTrue('fixed after the first move', st.InstFixed[1]);
  FChart.Up(px + 5, py + 5);
  st := FChart.GraphForceState(0);
  AssertFalse('unfixed by the release', st.InstFixed[1]);
end;

{ A merge that does not write the node list keeps the dragNode positions; one
  that writes it forgets them. }
procedure TAdvChartGraphSankeyInteractTest.TestAMergeKeepsWhatDragNodeWrote;
begin
  Show(cSankey);
  AssertTrue(FChart.SankeyDragNode(0, 1, True, 0.25, True, 0.5));
  RenderNow;
  AssertTrue('written', FChart.SankeySolved(0).Local[1].HasX);
  FChart.MergeOption('{"series":[{"nodeGap":12}]}');
  RenderNow;
  AssertTrue('kept by a merge of other keys', FChart.SankeySolved(0).Local[1].HasX);
  FChart.MergeOption('{"series":[{"data":[{"name":"a"},{"name":"b"},{"name":"c"}]}]}');
  RenderNow;
  AssertTrue('gone with the node list it lived in',
    (Length(FChart.SankeySolved(0).Local) < 2) or not FChart.SankeySolved(0).Local[1].HasX);
end;

procedure TAdvChartGraphSankeyInteractTest.TestANotMergeForgetsWhatDragNodeWrote;
begin
  Show(cSankey);
  AssertTrue(FChart.SankeyDragNode(0, 1, True, 0.25, True, 0.5));
  AssertTrue(FChart.SankeyRoam(0, 10, 5));
  RenderNow;
  FChart.Option := '';
  Show(cSankey);
  AssertTrue('no drag position', (Length(FChart.SankeySolved(0).Local) < 2)
    or not FChart.SankeySolved(0).Local[1].HasX);
  AssertEquals('no roam', 0, FChart.SankeyView(0).OverallX);
end;

{ dragNode without a dataIndex, or past the node list, does nothing. }
procedure TAdvChartGraphSankeyInteractTest.TestDragNodeActionNeedsADataIndex;
begin
  Show(cSankey);
  AssertFalse('no dataIndex', FChart.DispatchAction('{"type":"dragNode","localX":0.5,"localY":0.5}'));
  AssertFalse('past the list', FChart.DispatchAction('{"type":"dragNode","dataIndex":7,"localX":0.5}'));
  AssertTrue('a node', FChart.DispatchAction('{"type":"dragNode","dataIndex":2,"localX":0.5}'));
  RenderNow;
  AssertTrue('x written', FChart.SankeySolved(0).Local[2].HasX);
  AssertFalse('y not given, not written', FChart.SankeySolved(0).Local[2].HasY);
  AssertEquals('the event', 1, Length(FChart.Drags));
end;

procedure TAdvChartGraphSankeyInteractTest.TestASankeyRoamRefusesANonPositiveZoom;
begin
  Show(cSankey);
  AssertFalse(FChart.SankeyZoom(0, 0, 10, 10));
  AssertFalse(FChart.SankeyZoom(0, -2, 10, 10));
  AssertFalse(FChart.SankeyZoom(0, NaN, 10, 10));
  AssertTrue(FChart.SankeyZoom(0, 2, 10, 10));
end;

{ An edge's own `label` resolves to the series' `edgeLabel` under it: the
  show and the position are the edge's, the distance the series'. }
procedure TAdvChartGraphSankeyInteractTest.TestEdgeLabelSpecsFollowTheEdge;
var
  ink: TTyGraphInk;
  spec: TTyGraphSpec;
begin
  Show(cNone);
  AssertTrue(FChart.GraphInkOf(0, ink, spec));
  AssertEquals('one edge', 1, Length(ink.EdgeLabelShow));
  AssertTrue('the edge shows its label', ink.EdgeLabelShow[0]);
  AssertTrue('at its own end', ink.EdgeLabelPos[0] = glpEnd);
  AssertEquals('the series distance across', 2, ink.EdgeLabelDistX[0]);
  AssertEquals('and down', 4, ink.EdgeLabelDistY[0]);
end;

{ A rich edge label goes through the block path (A5): its caption carries
  the pieces, laid out about the line's anchor. }
procedure TAdvChartGraphSankeyInteractTest.TestARichEdgeLabelIsABlock;
var
  i, found: Integer;
  el: TTyChartElement;
begin
  Show('{"animation":false,"series":[{"type":"graph","layout":"none",'
    + '"data":[{"name":"a","x":0,"y":0},{"name":"b","x":100,"y":50}],'
    + '"links":[{"source":"a","target":"b","value":3}],'
    + '"edgeLabel":{"show":true,"formatter":"{r|x} {c}","rich":{"r":{"color":"#f00",'
    + '"backgroundColor":"#ccc","padding":4}}}}]}');
  found := 0;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if el.Datum.IsEdge and (el.Caption.FontSizeLogical > 0) then
    begin
      Inc(found);
      AssertEquals('the words', '{r|x} 3', el.Caption.Text);
      AssertTrue('a block of pieces', Length(el.Caption.RtPieces) > 0);
    end;
  end;
  AssertEquals('one edge label', 1, found);
end;

{ A link's label spec runs item -> the level of its SOURCE's depth ->
  series: a level's edgeLabel colour inks the labels of the links leaving it,
  and no other. }
procedure TAdvChartGraphSankeyInteractTest.TestASankeyEdgeLabelTakesItsLevelsStyle;
var
  i, red, other: Integer;
  el: TTyChartElement;
begin
  Show('{"animation":false,"series":[{"type":"sankey",'
    + '"data":[{"name":"a"},{"name":"b"},{"name":"c"}],'
    + '"links":[{"source":"a","target":"b","value":5},{"source":"b","target":"c","value":4}],'
    + '"edgeLabel":{"show":true},"levels":[{"depth":1,"edgeLabel":{"color":"#ff0000"}}]}]}');
  red := 0;
  other := 0;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if not (el.Datum.IsEdge and (el.Caption.FontSizeLogical > 0)) then Continue;
    if el.Datum.DataIndex = 1 then
    begin
      Inc(red);
      AssertEquals('the level''s ink', IntToHex($FFFF0000, 8), IntToHex(el.Caption.Colour, 8));
    end
    else
    begin
      Inc(other);
      AssertTrue('the series'' ink', el.Caption.Colour <> TTyChartColor($FFFF0000));
    end;
  end;
  AssertEquals('one link from depth 1', 1, red);
  AssertEquals('one link from depth 0', 1, other);
end;

{ A node's borderRadius is in the main group's units: a zoom of two draws
  it twice as round. }
procedure TAdvChartGraphSankeyInteractTest.TestASankeyNodesCornersZoomWithTheRoam;
var
  i, n: Integer;
  el: TTyChartElement;
  r1, r2: Double;
begin
  Show('{"animation":false,"series":[{"type":"sankey","roam":true,"zoom":1,'
    + '"itemStyle":{"borderRadius":3},'
    + '"data":[{"name":"a"},{"name":"b"}],'
    + '"links":[{"source":"a","target":"b","value":5}]}]}');
  r1 := NaN;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (not el.Datum.IsEdge) and (el.Datum.DataIndex = 0) and (el.Shape.Kind = cskRoundRect) then
      r1 := el.Shape.Radii[0];
  end;
  AssertEquals('three at zoom one', 3, r1);
  AssertTrue(FChart.SankeyZoom(0, 2, 10, 10));
  RenderNow;
  r2 := NaN;
  n := 0;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (not el.Datum.IsEdge) and (el.Datum.DataIndex = 0) and (el.Shape.Kind = cskRoundRect) then
    begin
      r2 := el.Shape.Radii[0];
      Inc(n);
    end;
  end;
  AssertEquals('one rect', 1, n);
  AssertEquals('six at zoom two', 6, r2);
end;

initialization
  RegisterTest(TAdvChartGraphSankeyInteractOracleTest);
  RegisterTest(TAdvChartGraphSankeyInteractTest);
end.
