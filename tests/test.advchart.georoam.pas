unit test.advchart.georoam;
{$mode objfpc}{$H+}
{ ROAM ON THE GEO COMPONENT, HELD TO UPSTREAM [Batch 150, D14 GE3].

  tools/advchart-oracle/geo-roam.js drives the real ECharts 6.1 build in
  node through zrender's own handler -- drags, wheels, presses with other
  buttons, moves, leaving the canvas -- and through dispatchAction (geoRoam
  by hand), setOption (merges, notMerge) and resize, over a small map (four
  squares, a hole, a line, a ring of 360 short sides), and records after
  every step: the chart's mouse events and its georoam and
  geoselectchanged events (the action events as JSON text), the tooltip,
  what the hit test finds at a few points, and per geo the view (the roam
  transformable, the transform group, the overall matrix and its inverse),
  the centre and zoom written back into the model's option, every region
  group's hover and selection, every path's state list, z2 and drawn
  commands (the stored path replayed at the current scale after a roam) and
  every label's place.

  This replays the same steps through the control's own pointer path
  (MouseMove, MouseDown, MouseUp, DoMouseWheel, MouseLeave) and
  DispatchAction / SetOption / SetBounds, paints after each step (the frame
  applies the states), and compares all of it bit for bit -- the drawn
  coordinates of a replayed Float32 path after the port's double is rounded
  to single, as Float32Array rounds it. }
interface
uses Classes, SysUtils, Math, Types, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits, tyControls.Types, tyControls.StyleModel,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.States, tyControls.AdvChart.Graph,
     tyControls.AdvChart.Geo, tyControls.AdvanceChart;
type
  TGrProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Move(AX, AY: Integer);
    procedure Down(AButton: TMouseButton; AX, AY: Integer);
    procedure Up(AButton: TMouseButton; AX, AY: Integer);
    function Wheel(AX, AY, ADelta: Integer): Boolean;
    procedure Leave;
    procedure LoseCapture;
    function RepaintFull: Boolean;
  end;

  { the chart's events as lines }
  TGrLog = class
  public
    Lines: TStringList;
    Payloads: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartGeoRoamOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGrProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FLog: TGrLog;
    FW, FH: Integer;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure SameF32(const AWhat: string; AGot: Double; const AHex: string);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure Finish(const AWhat: string; AMin: Integer);
    function NewChart(const AOption: string): TGrProbe;
    procedure Paint;
    procedure RegisterMaps;
    procedure Step(AChart: TGrProbe; AStep: TJSONObject);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareHits(AProbes, AWant: TJSONArray);
    procedure CompareCentre(const AWhere: string; AGeo: Integer; AWant: TJSONData;
      const AZoom: TJSONData);
    procedure CompareGeos(AWant: TJSONArray);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryStepAsUpstream;
    procedure TestTheGesturesAreTheirActions;
  end;

  TAdvChartGeoRoamTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGrProbe;
    FBmp: TBGRABitmap;
    FLog: TGrLog;
    procedure NewChart(const AOption: string);
    procedure Paint;
    procedure OnHostWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheApiPansZoomsAndTellsTheState;
    procedure TestAZoomThatIsNoPositiveNumberIsRefused;
    procedure TestThePictureIsKeptThroughARoam;
    procedure TestTheListFollowsBeforeAPaint;
    procedure TestALostCaptureEndsTheDrag;
    procedure TestTheHostsWheelHandlerComesFirst;
    procedure TestTheDirtyRectPathRepaintsARoamInFull;
    procedure TestAMapAloneIsDrawn;
    procedure TestAGeoThatDrawsNothingTakesNoGesture;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cSquares = '{"type":"FeatureCollection","features":['
    + '{"type":"Feature","properties":{"name":"A"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[10,0],[20,0],[20,10],[10,10],[10,0]]]}}]}';

{ ==================== the probe ==================== }

procedure TGrProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TGrProbe.Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

function TGrProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TGrProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TGrProbe.Down(AButton: TMouseButton; AX, AY: Integer);
begin
  MouseDown(AButton, [], AX, AY);
end;

procedure TGrProbe.Up(AButton: TMouseButton; AX, AY: Integer);
begin
  MouseUp(AButton, [], AX, AY);
end;

function TGrProbe.Wheel(AX, AY, ADelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TGrProbe.Leave;
begin
  MouseLeave;
end;

procedure TGrProbe.LoseCapture;
begin
  CaptureChanged;
end;

function TGrProbe.RepaintFull: Boolean;
begin
  Result := LastRepaintFull;
end;

{ ==================== the log ==================== }

constructor TGrLog.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
  Payloads := TStringList.Create;
end;

destructor TGrLog.Destroy;
begin
  Lines.Free;
  Payloads.Free;
  inherited Destroy;
end;

procedure TGrLog.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var p: TTyChartCallbackParams;
begin
  if AEvent.Payload <> '' then
  begin
    { the action event's JSON as the port writes it (JSON.stringify's form) }
    Lines.Add(AEvent.EventType + '|' + AEvent.Payload);
    if AEvent.EventType = 'georoam' then Payloads.Add(AEvent.Payload);
    Exit;
  end;
  p := AEvent.Params;
  Lines.Add(AEvent.EventType + '|' + p.ComponentType + '|' + p.Name);
end;

{ ==================== helpers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-geo-roam.json';
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

function ButtonOf(AWhich: Integer): TMouseButton;
begin
  case AWhich of
    2: Result := mbMiddle;
    3: Result := mbRight;
  else
    Result := mbLeft;
  end;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartGeoRoamOracleTest.SetUp;
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
  FW := cW;
  FH := cH;
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TGrLog.Create;
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FWhere := '';
end;

procedure TAdvChartGeoRoamOracleTest.TearDown;
begin
  TyChartClearMaps;
  FChart.Free;
  FLog.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  FRoot.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoRoamOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartGeoRoamOracleTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not ((HexOf(AGot) = AHex) or (IsNan(AGot) and IsNan(FromHex(AHex)))) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

{ a coordinate upstream replays from a Float32Array: the port's double
  rounded to single the way the array stores it }
procedure TAdvChartGeoRoamOracleTest.SameF32(const AWhat: string; AGot: Double;
  const AHex: string);
var s: Single;
begin
  s := AGot;
  Same(AWhat, s, AHex);
end;

procedure TAdvChartGeoRoamOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoRoamOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoRoamOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True),
    BoolToStr(AWant, True)]));
end;

procedure TAdvChartGeoRoamOracleTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartGeoRoamOracleTest.RegisterMaps;
var maps: TJSONArray; i: Integer;
begin
  TyChartClearMaps;
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    AssertTrue('registered', TyChartRegisterMap(maps.Objects[i].Strings['name'],
      maps.Objects[i].Strings['text']));
end;

function TAdvChartGeoRoamOracleTest.NewChart(const AOption: string): TGrProbe;
const
  cTypes: array[0..7] of string = ('click', 'mouseover', 'mouseout', 'mousemove',
    'mousedown', 'mouseup', 'georoam', 'geoselectchanged');
var i: Integer;
begin
  Result := TGrProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  { a clock of its own: no timer runs (every case hides at once) }
  Result.TooltipNow := 0;
  for i := 0 to High(cTypes) do Result.ChartOn(cTypes[i], @FLog.Handle);
  Result.Option := AOption;
  Result.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartGeoRoamOracleTest.Paint;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, FW, FH), 96);
end;

procedure TAdvChartGeoRoamOracleTest.Step(AChart: TGrProbe; AStep: TJSONObject);
var
  a, q: TJSONArray;
  k: Integer;
  d: TJSONData;
begin
  if AStep.Find('move') <> nil then
  begin
    a := AStep.Arrays['move'];
    AChart.Move(a.Integers[0], a.Integers[1]);
  end
  else if AStep.Find('drag') <> nil then
  begin
    { mousemove and mousedown at the first point, a mousemove to each
      further one, the release (and the click it may be) at the last }
    a := AStep.Arrays['drag'];
    q := a.Arrays[0];
    AChart.Move(q.Integers[0], q.Integers[1]);
    AChart.Down(mbLeft, q.Integers[0], q.Integers[1]);
    for k := 1 to a.Count - 1 do
    begin
      q := a.Arrays[k];
      AChart.Move(q.Integers[0], q.Integers[1]);
    end;
    q := a.Arrays[a.Count - 1];
    AChart.Up(mbLeft, q.Integers[0], q.Integers[1]);
  end
  else if AStep.Find('press') <> nil then
  begin
    a := AStep.Arrays['press'];
    AChart.Down(ButtonOf(AStep.Integers['button']), a.Integers[0], a.Integers[1]);
  end
  else if AStep.Find('release') <> nil then
  begin
    a := AStep.Arrays['release'];
    AChart.Up(ButtonOf(AStep.Integers['button']), a.Integers[0], a.Integers[1]);
  end
  else if AStep.Find('wheel') <> nil then
  begin
    a := AStep.Arrays['wheel'];
    AChart.Wheel(a.Integers[0], a.Integers[1], a.Integers[2]);
  end
  else if AStep.Find('leave') <> nil then
    AChart.Leave
  else if AStep.Find('action') <> nil then
    AChart.DispatchAction(AStep.Objects['action'].AsJSON)
  else if AStep.Find('setOption') <> nil then
  begin
    d := AStep.Find('notMerge');
    AChart.SetOption(AStep.Objects['setOption'].AsJSON, (d <> nil) and d.AsBoolean);
  end
  else if AStep.Find('resize') <> nil then
  begin
    a := AStep.Arrays['resize'];
    FW := a.Integers[0];
    FH := a.Integers[1];
    FBmp.SetSize(FW, FH);
    AChart.SetBounds(0, 0, FW, FH);
  end
  else
    Fail('an unknown step');
end;

procedure TAdvChartGeoRoamOracleTest.CompareEvents(AWant: TJSONArray);
var
  want: TStringList;
  i: Integer;
  e: TJSONObject;
  ct, nm: string;
begin
  want := TStringList.Create;
  try
    for i := 0 to AWant.Count - 1 do
    begin
      e := AWant.Objects[i];
      if e.Find('json') <> nil then
        want.Add(e.Strings['type'] + '|' + e.Strings['json'])
      else
      begin
        ct := '';
        nm := '';
        if e.Find('componentType').JSONType <> jtNull then ct := e.Strings['componentType'];
        if e.Find('name').JSONType <> jtNull then nm := e.Strings['name'];
        want.Add(e.Strings['type'] + '|' + ct + '|' + nm);
      end;
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

procedure TAdvChartGeoRoamOracleTest.CompareHits(AProbes, AWant: TJSONArray);
var
  i, el: Integer;
  dt: TTyChartDatumRef;
  hit: TJSONData;
  geo: TTyGeo;
begin
  for i := 0 to AProbes.Count - 1 do
  begin
    dt := FChart.HitTestAt(AProbes.Arrays[i].Integers[0], AProbes.Arrays[i].Integers[1], el);
    hit := AWant.Items[i];
    Inc(FCompared);
    if hit.JSONType = jtNull then
    begin
      if dt.Kind = ctkGeo then Bad(Format('probe %d: a region, upstream none', [i]));
      Continue;
    end;
    if dt.Kind <> ctkGeo then
    begin
      Bad(Format('probe %d: no region, upstream %s', [i, TJSONObject(hit).Strings['name']]));
      Continue;
    end;
    SameInt(Format('probe %d geo', [i]), dt.ComponentIndex, TJSONObject(hit).Integers['geo']);
    geo := FChart.GeoLayout(dt.ComponentIndex);
    SameStr(Format('probe %d name', [i]), geo.GroupName(dt.DataIndex), TJSONObject(hit).Strings['name']);
  end;
end;

{ the model option's centre and zoom: a half written as a number is a
  number, as a percentage string a percentage }
procedure TAdvChartGeoRoamOracleTest.CompareCentre(const AWhere: string; AGeo: Integer;
  AWant: TJSONData; const AZoom: TJSONData);
var
  c: TTyGraphCentre;
  z: Double;
  k: Integer;
  h: TJSONObject;
  pos: TTyGraphPos;
  pct: Boolean;
  kind: string;
begin
  AssertTrue('a geo', FChart.GeoRoamState(AGeo, c, z));
  if AZoom.JSONType <> jtNull then Same(AWhere + ' option zoom', z, AZoom.AsString);
  if AWant.JSONType = jtNull then
  begin
    SameBool(AWhere + ' option centre', c.Has, False);
    Exit;
  end;
  SameBool(AWhere + ' option centre', c.Has, True);
  if not c.Has then Exit;
  for k := 0 to 1 do
  begin
    h := TJSONArray(AWant).Objects[k];
    if k = 0 then
    begin
      pos := c.X;
      pct := c.PctX;
    end
    else
    begin
      pos := c.Y;
      pct := c.PctY;
    end;
    kind := h.Strings['kind'];
    if kind = 'num' then
    begin
      SameBool(Format('%s centre[%d] a number', [AWhere, k]), pos.Kind = gpkPx, True);
      Same(Format('%s centre[%d]', [AWhere, k]), pos.V, h.Strings['v']);
    end
    else if kind = 'pct' then
    begin
      SameBool(Format('%s centre[%d] a percentage', [AWhere, k]), (pos.Kind = gpkPct) and pct, True);
      Same(Format('%s centre[%d] %%', [AWhere, k]), pos.V, h.Strings['v']);
    end
    else
      Bad(Format('%s centre[%d]: upstream %s, not in the cases', [AWhere, k, kind]));
  end;
end;

procedure TAdvChartGeoRoamOracleTest.CompareGeos(AWant: TJSONArray);
var
  gi, g, k, j, q: Integer;
  geo: TTyGeo;
  dr: TTyGeoDraw;
  gw, grp, pw, lw, dw: TJSONObject;
  groups, paths, arr, cmds, cmd: TJSONArray;
  flags: TTyGeoGroupSt;
  it: TTyStItem;
  p: TTyGeoDrawPath;
  els: array of TTyChartElement;
  el: TTyChartElement;
  where, kind: string;
  f32: Boolean;
  gs: Double;
  m: TTyMat2D;
  rt: TTyGeoTrans;

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
    if AWant.Items[gi].JSONType = jtNull then Continue;
    if geo = nil then
    begin
      Bad(Format('geo %d: none', [gi]));
      Continue;
    end;
    gw := AWant.Objects[gi];
    where := Format('geo %d', [gi]);
    { the view: the roam transformable (and the transform group holding a
      copy of it), the overall matrix and its inverse }
    rt := geo.RoamTrans;
    arr := gw.Arrays['roam'];
    Same(where + ' roam x', rt.X, arr.Strings[0]);
    Same(where + ' roam y', rt.Y, arr.Strings[1]);
    Same(where + ' roam scaleX', rt.ScaleX, arr.Strings[2]);
    Same(where + ' roam scaleY', rt.ScaleY, arr.Strings[3]);
    arr := gw.Arrays['group'];
    Same(where + ' group x', rt.X, arr.Strings[0]);
    Same(where + ' group y', rt.Y, arr.Strings[1]);
    Same(where + ' group scaleX', rt.ScaleX, arr.Strings[2]);
    Same(where + ' group scaleY', rt.ScaleY, arr.Strings[3]);
    m := geo.MtOverall;
    arr := gw.Arrays['overall'];
    for k := 0 to 5 do Same(Format('%s overall[%d]', [where, k]), m[k], arr.Strings[k]);
    m := geo.MtOverallInv;
    arr := gw.Arrays['overallInv'];
    for k := 0 to 5 do Same(Format('%s overallInv[%d]', [where, k]), m[k], arr.Strings[k]);
    CompareCentre(where, gi, gw.Find('center'), gw.Find('zoom'));
    dr := geo.LastDraw;
    { the global scale the paths are folded at }
    if dr.HasTrans then
    begin
      gs := Sqrt(dr.Trans[0] * dr.Trans[0] + dr.Trans[1] * dr.Trans[1]);
      if dr.Trans[0] < 0 then gs := -gs;
    end
    else
      gs := 1;
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
    groups := gw.Arrays['groups'];
    SameInt(where + ' groups', Length(dr.Groups), groups.Count);
    for g := 0 to Min(groups.Count, Length(dr.Groups)) - 1 do
    begin
      grp := groups.Objects[g];
      where := Format('geo %d %s', [gi, grp.Strings['name']]);
      SameStr(where + ' name', dr.Groups[g].Name, grp.Strings['name']);
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
        where := Format('geo %d %s path %d', [gi, grp.Strings['name'], k]);
        SameStr(where + ' states', TyStNamesText(it.Host.States), pw.Strings['states']);
        { the drawn commands: local, before the transform group }
        dw := pw.Objects['drawn'];
        f32 := dw.Booleans['f32'];
        Same(where + ' scale', gs, dw.Arrays['scale'].Strings[0]);
        cmds := dw.Arrays['cmds'];
        SameInt(where + ' drawn commands', Length(p.Drawn), cmds.Count);
        if Length(p.Drawn) = cmds.Count then
          for q := 0 to cmds.Count - 1 do
          begin
            cmd := cmds.Arrays[q];
            kind := cmd.Strings[0];
            case p.Drawn[q].Kind of
              pckMove: SameStr(Format('%s cmd %d', [where, q]), 'M', kind);
              pckLine: SameStr(Format('%s cmd %d', [where, q]), 'L', kind);
              pckClose: SameStr(Format('%s cmd %d', [where, q]), 'Z', kind);
            else
              Bad(Format('%s cmd %d: a kind upstream has not', [where, q]));
            end;
            if kind = 'Z' then Continue;
            if f32 then
            begin
              SameF32(Format('%s cmd %d x', [where, q]), p.Drawn[q].X, cmd.Strings[1]);
              SameF32(Format('%s cmd %d y', [where, q]), p.Drawn[q].Y, cmd.Strings[2]);
            end
            else
            begin
              Same(Format('%s cmd %d x', [where, q]), p.Drawn[q].X, cmd.Strings[1]);
              Same(Format('%s cmd %d y', [where, q]), p.Drawn[q].Y, cmd.Strings[2]);
            end;
          end;
        if Length(p.Drawn) > 0 then
        begin
          if not NextEl(el) then Exit;
          SameInt(where + ' z2', el.Z2, pw.Integers['z2']);
        end;
        lw := nil;
        if pw.Find('label').JSONType <> jtNull then lw := pw.Objects['label'];
        SameBool(where + ' a text', p.Lbl.Exists, lw <> nil);
        if (lw = nil) or not p.Lbl.Exists or not p.Lbl.HasPos then Continue;
        where := where + ' text';
        if not NextEl(el) then Exit;
        SameBool(where + ' ignore', el.Ignore, lw.Booleans['ignore']);
        if lw.Find('text').JSONType <> jtNull then
          SameStr(where + ' words', el.Caption.Text, lw.Strings['text']);
        { the size the option wrote: kept through every zoom }
        if (lw.Find('fontSize').JSONType = jtNumber) and (lw.Integers['fontSize'] <> 12) then
          Same(where + ' size', TyFontPxOf(el.Caption.FontSizeLogical), HexOf(lw.Integers['fontSize']));
        if lw.Find('tx').JSONType <> jtNull then
        begin
          Same(where + ' x', el.Caption.X, lw.Strings['tx']);
          Same(where + ' y', el.Caption.Y, lw.Strings['ty']);
        end;
      end;
    end;
    SameInt(Format('geo %d elements', [gi]), j, Length(els));
  end;
end;

procedure TAdvChartGeoRoamOracleTest.RunCase(ACase: TJSONObject);
var
  steps, states, probes: TJSONArray;
  st: TJSONObject;
  i: Integer;
  d: TJSONData;
begin
  RegisterMaps;
  FW := cW;
  FH := cH;
  FBmp.SetSize(cW, cH);
  FreeAndNil(FChart);
  FWhere := ACase.Strings['id'];
  FChart := NewChart(ACase.Objects['option'].AsJSON);
  Paint;
  FLog.Lines.Clear;
  FLog.Payloads.Clear;
  states := ACase.Arrays['states'];
  steps := ACase.Arrays['steps'];
  probes := ACase.Arrays['probes'];
  for i := 0 to states.Count - 1 do
  begin
    FWhere := Format('%s state %d', [ACase.Strings['id'], i]);
    if i > 0 then
    begin
      Step(FChart, steps.Objects[i - 1]);
      Paint;
    end;
    st := states.Objects[i];
    CompareEvents(st.Arrays['events']);
    d := st.Find('tip');
    if (d = nil) or (d.JSONType = jtNull) then SameBool('tooltip shown', FChart.TooltipShown, False)
    else
    begin
      SameBool('tooltip shown', FChart.TooltipShown, True);
      SameStr('tooltip text', FChart.TooltipFormatterText, TJSONObject(d).Strings['text']);
    end;
    CompareHits(probes, st.Arrays['hits']);
    CompareGeos(st.Arrays['geos']);
  end;
end;

procedure TAdvChartGeoRoamOracleTest.TestEveryStepAsUpstream;
var cases: TJSONArray; c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  AssertTrue('cases', cases.Count >= 15);
  for c := 0 to cases.Count - 1 do RunCase(cases.Objects[c]);
  Finish('every step', 100000);
end;

{ the port's own gestures, their georoam payloads dispatched as actions on a
  fresh chart, leave the same views bit for bit (upstream: the oracle's
  self-check) }
procedure TAdvChartGeoRoamOracleTest.TestTheGesturesAreTheirActions;
var
  cases, steps: TJSONArray;
  c, i, k, g: Integer;
  st: TJSONObject;
  other: TGrProbe;
  sent: TStringList;
  gestures: Boolean;
  m1, m2: TTyMat2D;
  ran: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  ran := 0;
  sent := TStringList.Create;
  try
  for c := 0 to cases.Count - 1 do
  begin
    steps := cases.Objects[c].Arrays['steps'];
    gestures := True;
    for i := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[i];
      if (st.Find('setOption') <> nil) or (st.Find('resize') <> nil) then gestures := False;
    end;
    if not gestures then Continue;
    Inc(ran);
    RegisterMaps;
    FreeAndNil(FChart);
    FWhere := cases.Objects[c].Strings['id'];
    FChart := NewChart(cases.Objects[c].Objects['option'].AsJSON);
    other := NewChart(cases.Objects[c].Objects['option'].AsJSON);
    try
      FW := cW;
      FH := cH;
      FBmp.SetSize(cW, cH);
      Paint;
      other.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      for i := 0 to steps.Count - 1 do
      begin
        FLog.Payloads.Clear;
        Step(FChart, steps.Objects[i]);
        Paint;
        sent.Assign(FLog.Payloads);
        for k := 0 to sent.Count - 1 do
          AssertTrue('dispatched', other.DispatchAction(StringReplace(sent[k],
            '"type":"georoam"', '"type":"geoRoam"', [])));
        other.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
        for g := 0 to FChart.GeoCount - 1 do
        begin
          m1 := FChart.GeoLayout(g).MtOverall;
          m2 := other.GeoLayout(g).MtOverall;
          for k := 0 to 5 do
            Same(Format('%s step %d geo %d overall[%d]', [FWhere, i, g, k]), m2[k], HexOf(m1[k]));
        end;
      end;
    finally
      other.Free;
    end;
  end;
  finally
    sent.Free;
  end;
  AssertTrue('cases ran', ran >= 8);
  Finish('the gestures are their actions', 500);
end;

{ ==================== by hand ==================== }

procedure TAdvChartGeoRoamTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TGrLog.Create;
  AssertTrue(TyChartRegisterMap('sq', cSquares));
end;

procedure TAdvChartGeoRoamTest.TearDown;
begin
  TyChartClearMaps;
  FChart.Free;
  FLog.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoRoamTest.NewChart(const AOption: string);
begin
  FreeAndNil(FChart);
  FChart := TGrProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.TooltipNow := 0;
  FChart.ChartOn('georoam', @FLog.Handle);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  Paint;
end;

procedure TAdvChartGeoRoamTest.Paint;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartGeoRoamTest.OnHostWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  Handled := True;
end;

{ GeoRoam / GeoZoom are the action: the view moves, the option takes the
  centre and zoom back, the event says the payload }
procedure TAdvChartGeoRoamTest.TestTheApiPansZoomsAndTellsTheState;
var
  geo: TTyGeo;
  c: TTyGraphCentre;
  z, x0: Double;
begin
  NewChart('{"animation": false, "geo": {"map": "sq"}}');
  geo := FChart.GeoLayout(0);
  x0 := geo.RoamTrans.X;
  AssertTrue('no roam yet: the option''s own', FChart.GeoRoamState(0, c, z));
  AssertFalse('no centre written', c.Has);
  AssertEquals('zoom 1', 1, z, 0);
  AssertTrue('a pan', FChart.GeoRoam(0, 30, -10));
  AssertEquals('the roam moved by the pan', x0 + 30, geo.RoamTrans.X, 1e-9);
  AssertEquals('one event', 1, FLog.Lines.Count);
  AssertEquals('the payload as the event',
    'georoam|{"type":"georoam","geoIndex":0,"dx":30,"dy":-10,"animation":{"duration":0}}',
    FLog.Lines[0]);
  AssertTrue('the centre written back', FChart.GeoRoamState(0, c, z) and c.Has);
  AssertTrue('as numbers', (c.X.Kind = gpkPx) and (c.Y.Kind = gpkPx));
  AssertTrue('a zoom', FChart.GeoZoom(0, 2, 300, 200));
  AssertTrue(FChart.GeoRoamState(0, c, z));
  AssertEquals('the zoom written back', 2, z, 1e-12);
  AssertEquals('the view uses it', 2, geo.Zoom, 1e-12);
  { -1: componentType 'geo', every geo }
  AssertTrue('every geo', FChart.GeoRoam(-1, 1, 1));
  { a geo that is not there: no move, the event still }
  FLog.Lines.Clear;
  AssertFalse('no such geo', FChart.GeoRoam(3, 1, 1));
  AssertEquals('the event fires regardless', 1, FLog.Lines.Count);
end;

{ zero, negative, not-a-number and infinite zooms are refused (upstream
  turns the view NaN or mirrors it); a zoom about a point that is not
  finite too }
procedure TAdvChartGeoRoamTest.TestAZoomThatIsNoPositiveNumberIsRefused;
var
  geo: TTyGeo;
  m: TTyMat2D;
  k: Integer;
begin
  NewChart('{"animation": false, "geo": {"map": "sq"}}');
  geo := FChart.GeoLayout(0);
  m := geo.MtOverall;
  AssertFalse('zero', FChart.GeoZoom(0, 0, 300, 200));
  AssertFalse('negative', FChart.GeoZoom(0, -2, 300, 200));
  AssertFalse('NaN', FChart.GeoZoom(0, NaN, 300, 200));
  AssertFalse('infinite', FChart.GeoZoom(0, Infinity, 300, 200));
  AssertFalse('an origin not finite', FChart.GeoZoom(0, 2, Infinity, 200));
  for k := 0 to 5 do AssertTrue('the view as it was', SameValue(m[k], geo.MtOverall[k], 0));
end;

{ a roam keeps the picture: the same sub-path arrays, the state records
  where they were (a hovered region stays emphasised), the drawn commands
  and the label anchors worked out again }
procedure TAdvChartGeoRoamTest.TestThePictureIsKeptThroughARoam;
var
  geo: TTyGeo;
  subs: Pointer;
  px: TTyPointF;
  c: TTyGeoPt;
  dx0: Double;
begin
  NewChart('{"animation": false, "geo": {"map": "sq", "roam": true, '
    + '"label": {"show": true}}}');
  geo := FChart.GeoLayout(0);
  subs := Pointer(geo.LastDraw.Groups[0].Paths[0].Subs);
  dx0 := geo.LastDraw.Groups[0].Paths[0].Lbl.AnchorX;
  c := geo.RegionByName('A').GetCenter;
  AssertTrue(geo.PointOf(c.X, c.Y, px));
  FChart.Move(Round(px.X), Round(px.Y));
  Paint;
  AssertEquals('A emphasised', 'emphasis', TyStNamesText(geo.PathItem(0, 0).Host.States));
  AssertTrue(FChart.GeoRoam(0, 25, 0));
  Paint;
  AssertTrue('the same geo', geo = FChart.GeoLayout(0));
  AssertTrue('the same paths', subs = Pointer(geo.LastDraw.Groups[0].Paths[0].Subs));
  AssertEquals('A still emphasised', 'emphasis', TyStNamesText(geo.PathItem(0, 0).Host.States));
  AssertEquals('the label followed', dx0 + 25, geo.LastDraw.Groups[0].Paths[0].Lbl.AnchorX, 1e-9);
  AssertTrue('the drawn commands are the picture''s', Length(geo.LastDraw.Groups[0].Paths[0].Drawn) > 0);
end;

{ between a roam and the next paint the list already holds the moved
  region: a hit test finds it where it went, not where it was }
procedure TAdvChartGeoRoamTest.TestTheListFollowsBeforeAPaint;
var
  geo: TTyGeo;
  px: TTyPointF;
  c: TTyGeoPt;
  d: TTyChartDatumRef;
  el: Integer;
begin
  NewChart('{"animation": false, "geo": {"map": "sq", "roam": true}}');
  geo := FChart.GeoLayout(0);
  c := geo.RegionByName('A').GetCenter;
  AssertTrue(geo.PointOf(c.X, c.Y, px));
  d := FChart.HitTestAt(Round(px.X), Round(px.Y), el);
  AssertEquals('A there', 'A', geo.GroupName(d.DataIndex));
  { the drag: press on A, move 200 px right -- no paint between }
  FChart.Down(mbLeft, Round(px.X), Round(px.Y));
  FChart.Move(Round(px.X) + 200, Round(px.Y));
  d := FChart.HitTestAt(Round(px.X) + 200, Round(px.Y), el);
  AssertTrue('a region under the pointer', d.Kind = ctkGeo);
  AssertEquals('A came along', 'A', geo.GroupName(d.DataIndex));
  d := FChart.HitTestAt(Round(px.X), Round(px.Y), el);
  AssertFalse('A left its old place', (d.Kind = ctkGeo) and (geo.GroupName(d.DataIndex) = 'A'));
  FChart.Up(mbLeft, Round(px.X) + 200, Round(px.Y));
end;

{ a capture lost mid-drag ends it: the next move pans nothing }
procedure TAdvChartGeoRoamTest.TestALostCaptureEndsTheDrag;
begin
  NewChart('{"animation": false, "geo": {"map": "sq", "roam": true}}');
  FChart.Move(300, 200);
  FChart.Down(mbLeft, 300, 200);
  FChart.Move(310, 200);
  AssertEquals('the drag pans', 1, FLog.Lines.Count);
  FChart.LoseCapture;
  FChart.Move(320, 200);
  AssertEquals('not after the capture went', 1, FLog.Lines.Count);
  FChart.Up(mbLeft, 320, 200);
end;

{ the host's OnMouseWheel first: a handled wheel zooms nothing; a wheel
  nobody takes (off the map) is not consumed }
procedure TAdvChartGeoRoamTest.TestTheHostsWheelHandlerComesFirst;
begin
  NewChart('{"animation": false, "geo": {"map": "sq", "roam": true}}');
  AssertFalse('off the map: not consumed', FChart.Wheel(3, 3, 120));
  AssertTrue('on the map: consumed', FChart.Wheel(300, 200, 120));
  AssertEquals('one zoom', 1, FLog.Lines.Count);
  FChart.OnMouseWheel := @OnHostWheel;
  AssertTrue('the host took it', FChart.Wheel(300, 200, 120));
  AssertEquals('no zoom', 1, FLog.Lines.Count);
end;

{ the dirty-rect path (D9) does not take a roam: every roam frame is drawn
  in full, and the picture is the full path's pixel for pixel; a hover
  after it goes the partial way again }
procedure TAdvChartGeoRoamTest.TestTheDirtyRectPathRepaintsARoamInFull;
const
  cOpt = '{"animation": false, "geo": {"map": "sq", "roam": true, "label": {"show": true}}}';
var
  a, b: TGrProbe;
  ba, bb: TBGRABitmap;
  i, partial: Integer;

  procedure Both(AX, AY: Integer);
  begin
    a.Move(AX, AY);
    b.Move(AX, AY);
  end;

  function Frame(const AWhat: string = ''): Boolean;
  var
    x, y, n: Integer;
    pa, pb: PBGRAPixel;
    first: string;
  begin
    a.Layered(ba.Canvas, Rect(0, 0, cW, cH), 96);
    bb.Fill(BGRA(1, 2, 3, 255));
    b.Layered(bb.Canvas, Rect(0, 0, cW, cH), 96);
    Result := a.RepaintFull;
    n := 0;
    first := '';
    for y := 0 to cH - 1 do
    begin
      pa := ba.ScanLine[y];
      pb := bb.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        if (pa^.red <> pb^.red) or (pa^.green <> pb^.green) or (pa^.blue <> pb^.blue) then
        begin
          if n = 0 then
            first := Format(' first at (%d, %d): dirty %d,%d,%d full %d,%d,%d',
              [x, y, pa^.red, pa^.green, pa^.blue, pb^.red, pb^.green, pb^.blue]);
          Inc(n);
        end;
        Inc(pa);
        Inc(pb);
      end;
    end;
    AssertEquals('the dirty path paints what the full one does: ' + AWhat + first, 0, n);
  end;

begin
  a := TGrProbe.Create(FForm);
  b := TGrProbe.Create(FForm);
  ba := TBGRABitmap.Create(cW, cH, BGRA(1, 2, 3, 255));
  bb := TBGRABitmap.Create(cW, cH, BGRA(1, 2, 3, 255));
  try
    a.Parent := FForm;
    b.Parent := FForm;
    a.Controller := FCtl;
    b.Controller := FCtl;
    a.TooltipNow := 0;
    b.TooltipNow := 0;
    a.SetBounds(0, 0, cW, cH);
    b.SetBounds(0, 0, cW, cH);
    a.Option := cOpt;
    b.Option := cOpt;
    a.UseDirtyRect := True;
    AssertTrue('the first frame is full', Frame('first'));
    Both(250, 200);
    Frame('hover 1');
    Both(350, 200);
    partial := Ord(not Frame('hover 2'));
    a.Down(mbLeft, 350, 200);
    b.Down(mbLeft, 350, 200);
    for i := 1 to 5 do
    begin
      Both(350 + i * 7, 200 - i * 3);
      AssertTrue(Format('roam frame %d is full', [i]), Frame(Format('roam %d', [i])));
    end;
    a.Up(mbLeft, 385, 185);
    b.Up(mbLeft, 385, 185);
    Frame;
    AssertTrue('a wheel frame is full', a.Wheel(385, 185, 240) and b.Wheel(385, 185, 240) and Frame);
    Both(300, 230);
    Frame;
    Both(250, 230);
    Inc(partial, Ord(not Frame));
    AssertTrue('the hovers went the dirty way', partial >= 1);
  finally
    a.Free;
    b.Free;
    ba.Free;
    bb.Free;
  end;
end;

{ a chart of a geo and no series draws the map: the list's answer counts
  the components' elements before the no-series exit (it used to count the
  graphic elements alone, and nothing was painted) [Batch 150] }
procedure TAdvChartGeoRoamTest.TestAMapAloneIsDrawn;
var
  px: PBGRAPixel;
  geo: TTyGeo;
  c: TTyGeoPt;
  p: TTyPointF;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  NewChart('{"animation": false, "geo": {"map": "sq"}}');
  geo := FChart.GeoLayout(0);
  c := geo.RegionByName('A').GetCenter;
  AssertTrue(geo.PointOf(c.X, c.Y, p));
  px := FBmp.ScanLine[Round(p.Y)];
  Inc(px, Round(p.X));
  AssertTrue(Format('A is filled: %d,%d,%d', [px^.red, px^.green, px^.blue]),
    (px^.red <> 255) or (px^.green <> 255) or (px^.blue <> 255));
end;

{ show: false -- no MapDraw, so no RoamController: a drag and a wheel go
  nowhere; the action still moves the coordinate system }
procedure TAdvChartGeoRoamTest.TestAGeoThatDrawsNothingTakesNoGesture;
begin
  NewChart('{"animation": false, "geo": {"map": "sq", "roam": true, "show": false}}');
  FChart.Move(300, 200);
  FChart.Down(mbLeft, 300, 200);
  FChart.Move(320, 210);
  FChart.Up(mbLeft, 320, 210);
  AssertFalse('the wheel not taken', FChart.Wheel(300, 200, 120));
  AssertEquals('no gesture', 0, FLog.Lines.Count);
  AssertTrue('the action moves it', FChart.GeoRoam(0, 5, 5));
end;

initialization
  RegisterTest(TAdvChartGeoRoamOracleTest);
  RegisterTest(TAdvChartGeoRoamTest);
end.
