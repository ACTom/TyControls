unit test.advchart.graphroam;
{$mode objfpc}{$H+}
{ A graph on a view, roamed -- held to upstream to the bit.

  tools/advchart-oracle/roam.js runs the real ECharts 6.1 build through a list
  of cases, each an option and a list of steps: a dispatched graphRoam action,
  a wheel turn, a drag with any button, a resize, a merge that lays the chart
  out again, and a replaced option. After the first render and after every
  step it records, per graph series, the view's three transforms and their
  inverses, the area a gesture is taken in and which probe points fall inside
  it, the centre and zoom the option now holds, the compensation scale the
  nodes are drawn with, every node's data position, pixel and half-extents,
  every edge's trimmed ends in data space and in pixels -- and, for a gesture,
  every graphroam payload it emitted.

  The port is driven the same way: the API for an action, the control's own
  MouseDown / MouseMove / MouseUp / DoMouseWheel for a gesture, SetBounds for
  a resize, Invalidate for the merge and the Option property for a
  replacement, with a headless render after each.

  THE RULES IT HOLDS THE PORT TO: a point goes through the overall matrix, not
  through a scale and a translate; the roam is recomputed from the centre and
  zoom it writes back, with upstream's order of operations; a percentage
  centre stays a percentage; the compensation scale follows a zoom and NOT a
  pan; a relayout re-lays a ring with the roamed scale; the gesture area
  shrinks with the picture.

  Everything is compared to the bit, except a ring's layout -- sine and cosine
  are not correctly rounded in either runtime -- which gets a billionth, and
  everything computed FROM a ring's layout, which gets the same; and a node's
  label, which gets a billionth too (see CheckSeries). Only a SERIES-level
  label is compared: an item's own `label` is not read by the port. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Graph, tyControls.AdvChart.Color,
     tyControls.AdvanceChart;
type
  TGraphRoamProbe = class(TTyAdvanceChart)
  public
    Events: array of TTyGraphRoamPayload;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Down(AButton: TMouseButton; AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AButton: TMouseButton; AX, AY: Integer);
    function Wheel(ADelta, AX, AY: Integer): Boolean;
    procedure Log(Sender: TObject; const APayload: TTyGraphRoamPayload);
    procedure Relayout;
    procedure LoseCapture;
    procedure TakeWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
  end;

  { What the oracle cannot reach: a zoom far past anything upstream draws, a
    wheel the host takes, a zoom that is refused, a drag the capture ends. }
  TAdvChartGraphRoamTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGraphRoamProbe;
    procedure Show(const AOption: string);
    procedure RenderNow;
    function ZoomOf: Double;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAFarNodeStaysDrawnUnderAHugeZoom;
    procedure TestAWheelNobodyTakesIsTheHosts;
    procedure TestAWheelTheHostTookIsNotAZoom;
    procedure TestAZoomThatIsNotPositiveIsRefused;
    procedure TestALostCaptureEndsTheDrag;
  end;

  TAdvChartGraphRoamOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGraphRoamProbe;
    FRoot: TJSONData;
    FBad, FCompared, FCases, FStates, FGestures: Integer;
    FReport, FName: string;
    FTol: Double;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: Double);
    procedure SameNum(const AWhat: string; AGot: Double; AObj: TJSONObject;
      const AKey: string; AIndex: Integer = -1);
    procedure CheckState(ACase, AState: TJSONObject; AStep: Integer;
      AGesture: Boolean);
    procedure CheckSeries(ACase, ASeries: TJSONObject);
    procedure CheckEvents(AState: TJSONObject);
    procedure RenderNow(AW, AH: Integer);
    procedure Step(AStep: TJSONObject; out AW, AH: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryRoamLandsWhereUpstreamPutsIt;
  end;

implementation

procedure TGraphRoamProbe.Render(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGraphRoamProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TGraphRoamProbe.Down(AButton: TMouseButton; AX, AY: Integer);
begin
  MouseDown(AButton, [], AX, AY);
end;

procedure TGraphRoamProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TGraphRoamProbe.Up(AButton: TMouseButton; AX, AY: Integer);
begin
  MouseUp(AButton, [], AX, AY);
end;

function TGraphRoamProbe.Wheel(ADelta, AX, AY: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TGraphRoamProbe.Log(Sender: TObject;
  const APayload: TTyGraphRoamPayload);
begin
  SetLength(Events, Length(Events) + 1);
  Events[High(Events)] := APayload;
end;

procedure TGraphRoamProbe.Relayout;
begin
  Invalidate;
end;

procedure TGraphRoamProbe.LoseCapture;
begin
  CaptureChanged;
end;

procedure TGraphRoamProbe.TakeWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  Handled := True;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-graph-roam.json';
end;

{ A recorded number: 16 hex digits, or null with a text twin naming the
  non-finite value, or null with none -- absent, read as not-a-number. }
function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  Move(q, Result, SizeOf(Result));
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

function NumAt(AObj: TJSONObject; const AKey: string;
  AIndex: Integer = -1): Double;
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

procedure TAdvChartGraphRoamOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TGraphRoamProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.OnGraphRoam := @FChart.Log;
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
  FGestures := 0;
  FReport := '';
end;

procedure TAdvChartGraphRoamOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphRoamOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

{ Exact, or within FTol relatively on a ring; a non-finite value by kind; -0
  as 0. }
procedure TAdvChartGraphRoamOracleTest.Same(const AWhat: string; AGot: Double;
  AWant: Double);
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

procedure TAdvChartGraphRoamOracleTest.SameNum(const AWhat: string;
  AGot: Double; AObj: TJSONObject; const AKey: string; AIndex: Integer);
begin
  Same(AWhat, AGot, NumAt(AObj, AKey, AIndex));
end;

procedure TAdvChartGraphRoamOracleTest.RenderNow(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

function ButtonOf(AN: Integer; out AButton: TMouseButton): Boolean;
begin
  Result := True;
  case AN of
    1: AButton := mbLeft;
    2: AButton := mbMiddle;
    3: AButton := mbRight;
  else
    Result := False;
    AButton := mbLeft;
  end;
end;

procedure TAdvChartGraphRoamOracleTest.Step(AStep: TJSONObject;
  out AW, AH: Integer);
var
  o: TJSONObject;
  p: TTyGraphRoamPayload;
  d: TJSONData;
  path: TJSONArray;
  b: TMouseButton;
  k: Integer;
begin
  AW := FChart.Width;
  AH := FChart.Height;
  d := AStep.Find('action');
  if d <> nil then
  begin
    o := TJSONObject(d);
    p := Default(TTyGraphRoamPayload);
    p.SeriesIndex := -1;
    if o.Find('seriesIndex') <> nil then p.SeriesIndex := o.Integers['seriesIndex'];
    p.HasPan := (o.Find('dx') <> nil) and (o.Find('dy') <> nil);
    if p.HasPan then
    begin
      p.DX := NumAt(o, 'dx');
      p.DY := NumAt(o, 'dy');
    end;
    p.HasZoom := o.Find('zoom') <> nil;
    if p.HasZoom then
    begin
      p.Zoom := NumAt(o, 'zoom');
      p.OriginX := NumAt(o, 'originX');
      p.OriginY := NumAt(o, 'originY');
    end;
    FChart.GraphDispatchRoam(p);
    Exit;
  end;
  d := AStep.Find('wheel');
  if d <> nil then
  begin
    o := TJSONObject(d);
    FChart.Wheel(o.Integers['delta'], o.Integers['x'], o.Integers['y']);
    Exit;
  end;
  d := AStep.Find('drag');
  if d <> nil then
  begin
    o := TJSONObject(d);
    path := o.Arrays['path'];
    k := 0;
    if ButtonOf(o.Integers['button'], b) then
    begin
      FChart.Down(b, TJSONArray(path.Items[0]).Integers[0],
        TJSONArray(path.Items[0]).Integers[1]);
      k := 1;
    end;
    while k < path.Count do
    begin
      FChart.Move(TJSONArray(path.Items[k]).Integers[0],
        TJSONArray(path.Items[k]).Integers[1]);
      Inc(k);
    end;
    if ButtonOf(o.Integers['up'], b) then
      FChart.Up(b, TJSONArray(path.Items[path.Count - 1]).Integers[0],
        TJSONArray(path.Items[path.Count - 1]).Integers[1]);
    Exit;
  end;
  d := AStep.Find('resize');
  if d <> nil then
  begin
    AW := TJSONArray(d).Integers[0];
    AH := TJSONArray(d).Integers[1];
    FChart.SetBounds(0, 0, AW, AH);
    Exit;
  end;
  if AStep.Find('relayout') <> nil then
  begin
    FChart.Relayout;
    Exit;
  end;
  d := AStep.Find('reset');
  if d <> nil then
  begin
    { THROUGH AN EMPTY OPTION FIRST: assigning the text the property already
      holds is a no-op here, where upstream's notMerge replaces the models
      whatever they say. }
    FChart.Option := '';
    if (d is TJSONObject) and (TJSONObject(d).Find('option') <> nil) then
      FChart.Option := TJSONObject(d).Objects['option'].AsJSON
    else
      FChart.Option := d.AsJSON;
    Exit;
  end;
  Miss('a step this test does not know: ' + AStep.AsJSON);
end;

procedure TAdvChartGraphRoamOracleTest.CheckEvents(AState: TJSONObject);
var
  arr: TJSONArray;
  e: TJSONObject;
  i: Integer;
  tag: string;
begin
  arr := AState.Arrays['events'];
  Inc(FCompared);
  if arr.Count <> Length(FChart.Events) then
  begin
    Miss(Format('%d graphroam payloads upstream, %d here',
      [arr.Count, Length(FChart.Events)]));
    Exit;
  end;
  for i := 0 to arr.Count - 1 do
  begin
    e := TJSONObject(arr.Items[i]);
    tag := 'payload ' + IntToStr(i);
    Inc(FCompared);
    if FChart.Events[i].SeriesIndex <> e.Integers['series'] then
      Miss(Format('%s goes to series %d upstream, %d here',
        [tag, e.Integers['series'], FChart.Events[i].SeriesIndex]));
    if e.Find('dx') <> nil then
    begin
      Inc(FCompared);
      if not FChart.Events[i].HasPan or FChart.Events[i].HasZoom then
        Miss(tag + ' is a pan upstream and not here')
      else
      begin
        SameNum(tag + ' dx', FChart.Events[i].DX, e, 'dx');
        SameNum(tag + ' dy', FChart.Events[i].DY, e, 'dy');
      end;
    end
    else
    begin
      Inc(FCompared);
      if FChart.Events[i].HasPan or not FChart.Events[i].HasZoom then
        Miss(tag + ' is a zoom upstream and not here')
      else
      begin
        SameNum(tag + ' zoom', FChart.Events[i].Zoom, e, 'zoom');
        SameNum(tag + ' originX', FChart.Events[i].OriginX, e, 'originX');
        SameNum(tag + ' originY', FChart.Events[i].OriginY, e, 'originY');
      end;
    end;
  end;
end;

{ The element the node was drawn as: the symbol, not its caption. }
function NodeShape(AList: TTyPaintList; ASeries, ARow: Integer;
  out AShape: TTyChartShape): Boolean;
var i: Integer; el: TTyChartElement;
begin
  Result := False;
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Datum.SeriesIndex = ASeries) and (el.Datum.DataIndex = ARow)
      and not el.Datum.IsEdge
      and (el.Shape.Kind in [cskCircle, cskEllipse]) then
    begin
      AShape := el.Shape;
      Exit(True);
    end;
  end;
end;

{ The caption the label pass answered for a node or an edge. }
function CaptionOf(AList: TTyPaintList; ASeries, ARow: Integer;
  AEdge: Boolean; out ACap: TTyElementCaption): Boolean;
var i: Integer; el: TTyChartElement;
begin
  Result := False;
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Datum.SeriesIndex = ASeries) and (el.Datum.DataIndex = ARow)
      and (el.Datum.IsEdge = AEdge) and (el.Caption.FontSizeLogical > 0) then
    begin
      ACap := el.Caption;
      Exit(True);
    end;
  end;
end;

{ The stroke an edge was drawn as. }
function EdgePolyline(AList: TTyPaintList; ASeries, ARow: Integer;
  out APoints: TTyPointFArray): Boolean;
var i: Integer; el: TTyChartElement;
begin
  Result := False;
  APoints := nil;
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Datum.SeriesIndex = ASeries) and (el.Datum.DataIndex = ARow)
      and el.Datum.IsEdge and (el.Shape.Kind = cskPolyline)
      and (Length(el.Shape.Points) >= 2) then
    begin
      APoints := el.Shape.Points;
      Exit(True);
    end;
  end;
end;

function AnchorHName(A: TTyTextAnchorH): string;
begin
  case A of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

function AnchorVName(A: TTyTextAnchorV): string;
begin
  case A of
    tavTop: Result := 'top';
    tavBottom: Result := 'bottom';
  else
    Result := 'middle';
  end;
end;

procedure TAdvChartGraphRoamOracleTest.CheckSeries(ACase, ASeries: TJSONObject);
var
  si, i, k, row: Integer;
  v: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  tag, s, kind: string;
  xy: TTyXYWH;
  arr, pr, ep: TJSONArray;
  d: TJSONData;
  o, dim: TJSONObject;
  c: TTyGraphCentre;
  z, ringTol: Double;
  sh: TTyChartShape;
  skipNode: array of Boolean;
  dragged: TJSONArray;
  inside: Boolean;
  pos: TTyGraphPos;
  pct: Boolean;
  ink: TTyGraphInk;
  spec: TTyGraphSpec;
  cap: TTyElementCaption;
  seriesLabel: Boolean;
  back: TTyDoubleArray;
  px, py: Double;
  ends: TTyPointFArray;
  mid: TTyPointF;
  sd: TJSONData;
begin
  si := ASeries.Integers['index'];
  seriesLabel := False;
  sd := ACase.Objects['option'].Find('series');
  if (sd is TJSONArray) and (si < TJSONArray(sd).Count)
    and (TJSONArray(sd).Items[si] is TJSONObject) then
  begin
    sd := TJSONObject(TJSONArray(sd).Items[si]).Find('label');
    seriesLabel := (sd is TJSONObject) and (TJSONObject(sd).Find('show') <> nil)
      and (TJSONObject(sd).Find('show').JSONType = jtBoolean)
      and TJSONObject(sd).Booleans['show'];
  end;
  tag := 's' + IntToStr(si);
  v := FChart.GraphView(si);
  Inc(FCompared);
  if v = nil then
  begin
    Miss(tag + ': no view here');
    Exit;
  end;

  xy := v.DataXYWH;
  SameNum(tag + ' data x', xy.X, ASeries, 'dataRect', 0);
  SameNum(tag + ' data y', xy.Y, ASeries, 'dataRect', 1);
  SameNum(tag + ' data w', xy.W, ASeries, 'dataRect', 2);
  SameNum(tag + ' data h', xy.H, ASeries, 'dataRect', 3);
  xy := v.ViewXYWH;
  SameNum(tag + ' view x', xy.X, ASeries, 'viewRect', 0);
  SameNum(tag + ' view y', xy.Y, ASeries, 'viewRect', 1);
  SameNum(tag + ' view w', xy.W, ASeries, 'viewRect', 2);
  SameNum(tag + ' view h', xy.H, ASeries, 'viewRect', 3);
  SameNum(tag + ' raw sx', v.RawSX, ASeries, 'raw', 0);
  SameNum(tag + ' raw sy', v.RawSY, ASeries, 'raw', 1);
  SameNum(tag + ' raw x', v.RawX, ASeries, 'raw', 2);
  SameNum(tag + ' raw y', v.RawY, ASeries, 'raw', 3);
  SameNum(tag + ' rawInv 0', v.RawInv(0), ASeries, 'rawInv', 0);
  SameNum(tag + ' rawInv 3', v.RawInv(3), ASeries, 'rawInv', 1);
  SameNum(tag + ' rawInv 4', v.RawInv(4), ASeries, 'rawInv', 2);
  SameNum(tag + ' rawInv 5', v.RawInv(5), ASeries, 'rawInv', 3);
  SameNum(tag + ' roam x', v.RoamX, ASeries, 'roam', 0);
  SameNum(tag + ' roam y', v.RoamY, ASeries, 'roam', 1);
  SameNum(tag + ' roam s', v.Zoom, ASeries, 'roam', 2);
  SameNum(tag + ' overall sx', v.OverallScaleX, ASeries, 'overall', 0);
  SameNum(tag + ' overall sy', v.OverallScaleY, ASeries, 'overall', 1);
  SameNum(tag + ' overall x', v.OverallX, ASeries, 'overall', 2);
  SameNum(tag + ' overall y', v.OverallY, ASeries, 'overall', 3);
  SameNum(tag + ' overallInv 0', v.OverallInv(0), ASeries, 'overallInv', 0);
  SameNum(tag + ' overallInv 1', 0, ASeries, 'overallInv', 1);
  SameNum(tag + ' overallInv 2', 0, ASeries, 'overallInv', 2);
  SameNum(tag + ' overallInv 3', v.OverallInv(3), ASeries, 'overallInv', 3);
  SameNum(tag + ' overallInv 4', v.OverallInv(4), ASeries, 'overallInv', 4);
  SameNum(tag + ' overallInv 5', v.OverallInv(5), ASeries, 'overallInv', 5);
  xy := v.TriggerRect;
  SameNum(tag + ' trigger x', xy.X, ASeries, 'trigger', 0);
  SameNum(tag + ' trigger y', xy.Y, ASeries, 'trigger', 1);
  SameNum(tag + ' trigger w', xy.W, ASeries, 'trigger', 2);
  SameNum(tag + ' trigger h', xy.H, ASeries, 'trigger', 3);

  { THE AREA, point by point. }
  pr := ACase.Arrays['probes'];
  d := ASeries.Find('contain');
  if d <> nil then
    for i := 0 to pr.Count - 1 do
    begin
      if d.JSONType = jtString then s := Copy(d.AsString, i + 1, 1)
      else s := TJSONArray(d).Items[i].AsString;
      inside := v.ContainPoint(TyPointF(TJSONArray(pr.Items[i]).Integers[0],
        TJSONArray(pr.Items[i]).Integers[1]));
      { AND BACK TO DATA through upstream's own inverse -- pointToData is
        vectorApplyTransform by mtOverallInv. }
      px := TJSONArray(pr.Items[i]).Integers[0];
      py := TJSONArray(pr.Items[i]).Integers[1];
      if v.PointToData(TyPointF(px, py), back) then
      begin
        Same(Format('%s probe %d back to x', [tag, i]), back[0],
          NumAt(ASeries, 'overallInv', 0) * px + NumAt(ASeries, 'overallInv', 4));
        Same(Format('%s probe %d back to y', [tag, i]), back[1],
          NumAt(ASeries, 'overallInv', 3) * py + NumAt(ASeries, 'overallInv', 5));
      end
      else if not IsNan(NumAt(ASeries, 'overallInv', 0)) then
        Miss(Format('%s probe %d does not go back to data here', [tag, i]));
      Inc(FCompared);
      if inside <> (s = '1') then
        Miss(Format('%s probe (%d, %d) is %s upstream', [tag,
          TJSONArray(pr.Items[i]).Integers[0],
          TJSONArray(pr.Items[i]).Integers[1],
          BoolToStr(s = '1', 'inside', 'outside')]));
    end;
  arr := ASeries.Arrays['edgeProbes'];
  for i := 0 to arr.Count - 1 do
  begin
    ep := TJSONArray(arr.Items[i]);
    inside := v.ContainPoint(TyPointF(HexNum(ep.Items[0]), HexNum(ep.Items[1])));
    Inc(FCompared);
    if inside <> (ep.Items[2].AsInteger = 1) then
      Miss(Format('%s edge probe %d (%s, %s) is %s upstream', [tag, i,
        Fmt(HexNum(ep.Items[0])), Fmt(HexNum(ep.Items[1])),
        BoolToStr(ep.Items[2].AsInteger = 1, 'inside', 'outside')]));
  end;

  { THE OPTION'S CENTRE AND ZOOM. }
  FChart.GraphRoamState(si, c, z);
  d := ASeries.Find('center');
  Inc(FCompared);
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    if c.Has then Miss(tag + ' has no centre upstream, one here');
  end
  else if not c.Has then
    Miss(tag + ' has a centre upstream, none here')
  else
    for k := 0 to 1 do
    begin
      dim := TJSONObject(TJSONArray(d).Items[k]);
      if k = 0 then begin pos := c.X; pct := c.PctX; end
      else begin pos := c.Y; pct := c.PctY; end;
      kind := dim.Strings['kind'];
      Inc(FCompared);
      if kind = 'num' then
      begin
        if (pos.Kind <> gpkPx) or pct then
          Miss(Format('%s centre %d is a number upstream', [tag, k]))
        else SameNum(Format('%s centre %d', [tag, k]), pos.V, dim, 'v');
      end
      else if kind = 'pct' then
      begin
        if (pos.Kind <> gpkPct) or not pct then
          Miss(Format('%s centre %d is a percentage upstream', [tag, k]))
        else SameNum(Format('%s centre %d %%', [tag, k]), pos.V, dim, 'v');
      end
      else if kind = 'kw' then
      begin
        s := dim.Strings['str'];
        if (pos.Kind <> gpkPct) or pct then
          Miss(Format('%s centre %d is the word %s upstream', [tag, k, s]))
        else if ((s = 'center') or (s = 'middle')) then Same(tag + ' keyword', pos.V, 50)
        else if ((s = 'left') or (s = 'top')) then Same(tag + ' keyword', pos.V, 0)
        else Same(tag + ' keyword', pos.V, 100);
      end
      else if kind = 'str' then
      begin
        if pct then Miss(Format('%s centre %d is a plain string upstream', [tag, k]))
        else if IsNan(NumAt(dim, 'v')) then
        begin
          if pos.Kind <> gpkNaN then
            Miss(Format('%s centre %d does not parse upstream', [tag, k]));
        end
        else if pos.Kind <> gpkPx then
          Miss(Format('%s centre %d is a numeric string upstream', [tag, k]))
        else SameNum(Format('%s centre %d', [tag, k]), pos.V, dim, 'v');
      end
      else if pos.Kind <> gpkNaN then
        Miss(Format('%s centre %d is %s upstream', [tag, k, kind]));
    end;
  if not IsNan(NumAt(ASeries, 'zoom')) then
    SameNum(tag + ' zoom option', z, ASeries, 'zoom');
  SameNum(tag + ' zoom used', v.Zoom, ASeries, 'csZoom');
  if not IsNan(NumAt(ASeries, 'nodeScale')) then
    SameNum(tag + ' node scale', FChart.GraphNodeScale(si), ASeries, 'nodeScale');
  FChart.GraphInkOf(si, ink, spec);
  SameNum(tag + ' node scale recomputed', v.NodeScale(spec.NodeScaleRatio),
    ASeries, 'nodeScaleIfRecomputed');

  { THE NODES AND EDGES. }
  if not FChart.GraphLayout(si, nodes, edges, fills) then
  begin
    Miss(tag + ': no layout here');
    Exit;
  end;
  if ACase.Booleans['ring'] then ringTol := 1e-9 else ringTol := 0;
  SetLength(skipNode, Length(nodes));
  d := ACase.Find('dragsNode');
  if d is TJSONArray then
  begin
    dragged := TJSONArray(d);
    for i := 0 to dragged.Count - 1 do
      if (dragged.Integers[i] >= 0) and (dragged.Integers[i] <= High(skipNode)) then
        skipNode[dragged.Integers[i]] := True;
  end;
  arr := ASeries.Arrays['nodes'];
  Inc(FCompared);
  if arr.Count <> Length(nodes) then
  begin
    Miss(Format('%s: %d nodes upstream, %d here', [tag, arr.Count,
      Length(nodes)]));
    Exit;
  end;
  FTol := ringTol;
  for i := 0 to arr.Count - 1 do
  begin
    if skipNode[i] then Continue;
    if arr.Items[i].JSONType = jtNull then
    begin
      Inc(FCompared);
      if not IsNan(nodes[i].PX) then
        Miss(Format('%s node %d is not drawn upstream', [tag, i]));
      Continue;
    end;
    o := TJSONObject(arr.Items[i]);
    SameNum(Format('%s node %d x', [tag, i]), nodes[i].X, o, 'layout', 0);
    SameNum(Format('%s node %d y', [tag, i]), nodes[i].Y, o, 'layout', 1);
    SameNum(Format('%s node %d px', [tag, i]), nodes[i].PX, o, 'px', 0);
    SameNum(Format('%s node %d py', [tag, i]), nodes[i].PY, o, 'px', 1);
    row := nodes[i].Row;
    if NodeShape(FChart.List, si, row, sh) then
    begin
      if sh.Kind = cskCircle then
      begin
        SameNum(Format('%s node %d half x', [tag, i]), sh.R1, o, 'half', 0);
        SameNum(Format('%s node %d half y', [tag, i]), sh.R1, o, 'half', 1);
      end
      else
      begin
        SameNum(Format('%s node %d half x', [tag, i]), sh.R0, o, 'half', 0);
        SameNum(Format('%s node %d half y', [tag, i]), sh.R1, o, 'half', 1);
      end;
    end
    else if not IsNan(nodes[i].PX) then
      Miss(Format('%s node %d has no symbol here', [tag, i]));
    { THE LABEL, off the SCALED symbol's box. }
    { ONLY A SERIES-LEVEL LABEL: an item's own `label` is not read here, and
      the case that writes one records it for the reader. }
    d := o.Find('label');
    if (d <> nil) and (d.JSONType = jtObject) and seriesLabel then
    begin
      Inc(FCompared);
      if not CaptionOf(FChart.List, si, row, False, cap) then
        Miss(Format('%s node %d has no label here', [tag, i]))
      else
      begin
        { A BILLIONTH, NOT THE BIT. Upstream reaches the box's far edge as
          `(px - half) + 2 half` through the symbol's own transform and the
          label pass here as `px + half`; the two part by an ulp now and
          then. What the roam decides -- that the box is the SCALED one --
          moves a label by pixels. }
        FTol := Math.Max(ringTol, 1e-9);
        SameNum(Format('%s node %d label x', [tag, i]), cap.X,
          TJSONObject(d), 'x');
        SameNum(Format('%s node %d label y', [tag, i]), cap.Y,
          TJSONObject(d), 'y');
        FTol := ringTol;
        Inc(FCompared);
        if (AnchorHName(cap.AnchorH) <> TJSONObject(d).Strings['align'])
          or (AnchorVName(cap.AnchorV) <> TJSONObject(d).Strings['vAlign']) then
          Miss(Format('%s node %d label is %s/%s upstream, %s/%s here', [tag,
            i, TJSONObject(d).Strings['align'], TJSONObject(d).Strings['vAlign'],
            AnchorHName(cap.AnchorH), AnchorVName(cap.AnchorV)]));
      end;
    end;
  end;

  arr := ASeries.Arrays['edges'];
  Inc(FCompared);
  if arr.Count <> Length(edges) then
  begin
    Miss(Format('%s: %d edges upstream, %d here', [tag, arr.Count,
      Length(edges)]));
    Exit;
  end;
  for i := 0 to arr.Count - 1 do
  begin
    if arr.Items[i].JSONType = jtNull then Continue;
    if (edges[i].Source >= 0) and (edges[i].Source <= High(skipNode))
      and skipNode[edges[i].Source] then Continue;
    if (edges[i].Target >= 0) and (edges[i].Target <= High(skipNode))
      and skipNode[edges[i].Target] then Continue;
    o := TJSONObject(arr.Items[i]);
    Inc(FCompared);
    if not edges[i].HasEnds then
    begin
      Miss(Format('%s edge %d was never trimmed here', [tag, i]));
      Continue;
    end;
    SameNum(Format('%s edge %d x1', [tag, i]), edges[i].TX1, o, 'shape', 0);
    SameNum(Format('%s edge %d y1', [tag, i]), edges[i].TY1, o, 'shape', 1);
    SameNum(Format('%s edge %d x2', [tag, i]), edges[i].TX2, o, 'shape', 2);
    SameNum(Format('%s edge %d y2', [tag, i]), edges[i].TY2, o, 'shape', 3);
    d := o.Find('cp');
    Inc(FCompared);
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      if not edges[i].Curved then
        Miss(Format('%s edge %d is curved upstream', [tag, i]))
      else
      begin
        SameNum(Format('%s edge %d cpx', [tag, i]), edges[i].TCPX, o, 'cp', 0);
        SameNum(Format('%s edge %d cpy', [tag, i]), edges[i].TCPY, o, 'cp', 1);
      end;
    end
    else if edges[i].Curved then
      Miss(Format('%s edge %d is straight upstream', [tag, i]));
    SameNum(Format('%s edge %d px1', [tag, i]), edges[i].EX1, o, 'pixelEnds', 0);
    SameNum(Format('%s edge %d py1', [tag, i]), edges[i].EY1, o, 'pixelEnds', 1);
    SameNum(Format('%s edge %d px2', [tag, i]), edges[i].EX2, o, 'pixelEnds', 2);
    SameNum(Format('%s edge %d py2', [tag, i]), edges[i].EY2, o, 'pixelEnds', 3);
    { AND WHAT WAS DRAWN: the stroke runs between those two points. }
    if EdgePolyline(FChart.List, si, edges[i].Row, ends) then
    begin
      SameNum(Format('%s edge %d drawn from x', [tag, i]), ends[0].X, o, 'pixelEnds', 0);
      SameNum(Format('%s edge %d drawn from y', [tag, i]), ends[0].Y, o, 'pixelEnds', 1);
      SameNum(Format('%s edge %d drawn to x', [tag, i]), ends[High(ends)].X, o, 'pixelEnds', 2);
      SameNum(Format('%s edge %d drawn to y', [tag, i]), ends[High(ends)].Y, o, 'pixelEnds', 3);
      { A CURVE BENDS THROUGH THE TRIMMED CONTROL POINT: its middle sample is
        a quarter of each end and half the control point, carried through
        the view. A billionth -- the sample is the port's own arithmetic. }
      d := o.Find('cp');
      if (d <> nil) and (d.JSONType <> jtNull) and (Length(ends) > 2) then
      begin
        mid := v.DataToPoint([NumAt(o, 'cp', 0), NumAt(o, 'cp', 1)]);
        FTol := Math.Max(ringTol, 1e-9);
        Same(Format('%s edge %d bends through x', [tag, i]),
          ends[Length(ends) div 2].X,
          0.25 * NumAt(o, 'pixelEnds', 0) + 0.5 * mid.X + 0.25 * NumAt(o, 'pixelEnds', 2));
        Same(Format('%s edge %d bends through y', [tag, i]),
          ends[Length(ends) div 2].Y,
          0.25 * NumAt(o, 'pixelEnds', 1) + 0.5 * mid.Y + 0.25 * NumAt(o, 'pixelEnds', 3));
        FTol := ringTol;
      end;
    end;
  end;
  FTol := 0;
end;

procedure TAdvChartGraphRoamOracleTest.CheckState(ACase, AState: TJSONObject;
  AStep: Integer; AGesture: Boolean);
var
  arr: TJSONArray;
  i: Integer;
  keep: string;
begin
  Inc(FStates);
  keep := FName;
  FName := keep + ' @' + IntToStr(AStep);
  try
    if AGesture then CheckEvents(AState);
    arr := AState.Arrays['series'];
    for i := 0 to arr.Count - 1 do
      CheckSeries(ACase, TJSONObject(arr.Items[i]));
  finally
    FName := keep;
  end;
end;

procedure TAdvChartGraphRoamOracleTest.TestEveryRoamLandsWhereUpstreamPutsIt;
var
  cases, steps, states: TJSONArray;
  cs, st: TJSONObject;
  c, k, w, h: Integer;
  gesture: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := TJSONObject(cases.Items[c]);
    FName := cs.Strings['name'];
    if cs.Get('documentary', False) or cs.Get('deferred', False) then Continue;
    Inc(FCases);
    FTol := 0;
    w := cs.Integers['W'];
    h := cs.Integers['H'];
    FChart.Option := '';
    FChart.Option := cs.Objects['option'].AsJSON;
    FChart.SetBounds(0, 0, w, h);
    FChart.Events := nil;
    RenderNow(w, h);
    states := cs.Arrays['states'];
    steps := cs.Arrays['steps'];
    CheckState(cs, TJSONObject(states.Items[0]), 0, False);
    for k := 0 to steps.Count - 1 do
    begin
      st := TJSONObject(steps.Items[k]);
      gesture := (st.Find('wheel') <> nil) or (st.Find('drag') <> nil);
      if gesture then Inc(FGestures);
      FChart.Events := nil;
      Step(st, w, h);
      RenderNow(w, h);
      CheckState(cs, TJSONObject(states.Items[k + 1]), k + 1, gesture);
    end;
  end;
  AssertTrue(Format('every case ran (%d)', [FCases]), FCases >= 30);
  AssertTrue(Format('the gestures ran (%d)', [FGestures]), FGestures >= 15);
  AssertTrue(Format('and a great deal was compared (%d)', [FCompared]),
    FCompared > 5000);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

{ ==================== the rest ==================== }

const
  cThree = '{animation:false, series:[{type:"graph", layout:"none", roam:true,'
    + ' symbolSize:20, data:[{name:"a",x:0,y:0},{name:"b",x:100,y:30},'
    + '{name:"c",x:40,y:90}], links:[{source:"a",target:"b"},'
    + '{source:"b",target:"c",lineStyle:{curveness:0.3}}]}]}';

procedure TAdvChartGraphRoamTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TGraphRoamProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.OnGraphRoam := @FChart.Log;
  FChart.SetBounds(0, 0, 400, 300);
end;

procedure TAdvChartGraphRoamTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphRoamTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartGraphRoamTest.Show(const AOption: string);
begin
  FChart.Option := AOption;
  RenderNow;
  FChart.Events := nil;
end;

function TAdvChartGraphRoamTest.ZoomOf: Double;
var c: TTyGraphCentre;
begin
  AssertTrue('the graph is on a view', FChart.GraphRoamState(0, c, Result));
end;

procedure TAdvChartGraphRoamTest.TestAFarNodeStaysDrawnUnderAHugeZoom;
var
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  i: Integer;
begin
  Show(cThree);
  { A hundred thousand times, about the middle: every node is now tens of
    millions of pixels away -- far past the thousand screens a layout is
    allowed to wander before its node is dropped. }
  AssertTrue(FChart.GraphZoom(0, 1e5, 200, 150));
  AssertTrue('the roam was taken', ZoomOf > 1000);
  FChart.GraphLayout(0, nodes, edges, fills);
  for i := 0 to High(nodes) do
  begin
    AssertFalse(Format('node %d is still drawn after the step', [i]),
      IsNan(nodes[i].PX));
    AssertTrue(Format('node %d really is far away', [i]),
      Abs(nodes[i].PX) + Abs(nodes[i].PY) > 1e6);
  end;
  { AND AFTER A LAYOUT, which authors the control points again -- where the
    distance test for a curve's control point lives. }
  FChart.Relayout;
  RenderNow;
  FChart.GraphLayout(0, nodes, edges, fills);
  for i := 0 to High(nodes) do
    AssertFalse(Format('node %d is still drawn after a layout', [i]),
      IsNan(nodes[i].PX));
  AssertTrue('the curved edge keeps its curve', edges[1].Curved);
  AssertFalse('and is not hidden', edges[1].Hidden);
end;

procedure TAdvChartGraphRoamTest.TestAWheelNobodyTakesIsTheHosts;
var z: Double;
begin
  Show(cThree);
  z := ZoomOf;
  { The corner is inside the control and outside the graph's area. }
  AssertFalse('a wheel over no graph is not taken', FChart.Wheel(120, 5, 5));
  AssertEquals('no payload', 0, Length(FChart.Events));
  AssertTrue('nothing zoomed', ZoomOf = z);
  AssertFalse('a wheel of nothing is not taken either',
    FChart.Wheel(0, 200, 150));
  AssertTrue('over the graph it is', FChart.Wheel(120, 200, 150));
  AssertEquals('one payload', 1, Length(FChart.Events));
  AssertTrue('the zoom moved', ZoomOf <> z);
end;

procedure TAdvChartGraphRoamTest.TestAWheelTheHostTookIsNotAZoom;
var z: Double;
begin
  Show(cThree);
  z := ZoomOf;
  FChart.OnMouseWheel := @FChart.TakeWheel;
  AssertTrue('the host took it', FChart.Wheel(120, 200, 150));
  AssertEquals('so no payload', 0, Length(FChart.Events));
  AssertTrue('and nothing zoomed', ZoomOf = z);
end;

procedure TAdvChartGraphRoamTest.TestAZoomThatIsNotPositiveIsRefused;
var z: Double;
begin
  Show(cThree);
  z := ZoomOf;
  AssertFalse('nought', FChart.GraphZoom(0, 0, 200, 150));
  AssertFalse('negative', FChart.GraphZoom(0, -2, 200, 150));
  AssertFalse('not a number', FChart.GraphZoom(0, NaN, 200, 150));
  AssertFalse('infinite', FChart.GraphZoom(0, Infinity, 200, 150));
  AssertFalse('a pan of not-a-number', FChart.GraphRoam(0, NaN, 3));
  AssertEquals('no payload', 0, Length(FChart.Events));
  AssertTrue('nothing zoomed', ZoomOf = z);
  AssertTrue('a real one is taken', FChart.GraphZoom(0, 2, 200, 150));
  AssertFalse('a series that is not there is not',
    FChart.GraphZoom(3, 2, 200, 150));
end;

procedure TAdvChartGraphRoamTest.TestALostCaptureEndsTheDrag;
begin
  Show(cThree);
  FChart.Down(mbLeft, 200, 150);
  FChart.Move(205, 152);
  AssertEquals('the drag pans', 1, Length(FChart.Events));
  FChart.LoseCapture;
  FChart.Move(215, 160);
  AssertEquals('and stops when the capture goes', 1, Length(FChart.Events));
end;

initialization
  RegisterTest(TAdvChartGraphRoamOracleTest);
  RegisterTest(TAdvChartGraphRoamTest);
end.
