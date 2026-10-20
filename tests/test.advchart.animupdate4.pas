unit test.advchart.animupdate4;
{$mode objfpc}{$H+}
{ THE UPDATE TRANSITIONS STILL MISSING AFTER F3d, HELD TO UPSTREAM [R2-C].

  tools/advchart-oracle/anim-update4.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock, what each case's probes name:

    sunburst  a merge that is no drill: the kept pieces' shapes, the new
              ones growing from r0, the labels moved from their old layout
              or faded in;
    treemap   a merge (a render with no payload): the hierarchical diff of
              the old tree and the new one, the kept elements from their old
              place, the new ones out of their parent's old corner, the
              deleted ones shrinking and fading;
    roam      a merge writing a view's centre / zoom: the graph's main
              group, the tree's view group, the geo's transform group;
    force     a force graph laid out again after a legend filter or a merge:
              from the preserved points, by node id;
    step      a line whose step changed: the init branch (the clip grows
              again, every symbol pops in again);
    treeData  a tree's data merge: the diff by name, the removals walking
              the old tree.
    radar     [R2-I2] a radar's update: every symbol made anew at the
              polyline's point now and sliding to its new one at update
              timing and its row, its label riding it; the rings' points.

  This replays every case through the control and compares, bit for bit,
  the proxies the control animates (and, for a static piece or a node's
  place, the frame's element). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.AnimView, tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart.AnimOpt,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  TAu4Probe = class(TGfxProbe)
  public
    function Frame: TTyPaintList;
  end;

  TAdvChartAnimUpdate4OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAu4Probe;
    FRoot: TJSONData;
    FBad, FCompared, FSamples: Integer;
    FWhere, FReport: string;
    procedure Bad(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure NearNum(const AWhat: string; AGot: Double; AWant: TJSONData; ATol: Double);
    procedure NearVal(const AWhat: string; AGot, AWant: Double);
    procedure SameKey(const AWhat: string; P: TTyChartAnimProxy; const AKey: string;
      AWant: TJSONData);
    procedure SameArr(const AWhat: string; const AGot: TTyAnimValue; AWant: TJSONData);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    function FrameEl(ASeries, AIndex: Integer; ARole: TTyChartAnimRole;
      out AEl: TTyChartElement; ASub: Integer = -1; ALast: Boolean = False): Boolean;
    procedure DrawnRect(const AWhat: string; ASeries, ARow, ASub: Integer;
      AData: TJSONObject; ALast: Boolean);
    procedure ProbeGraph(ARec: TJSONObject);
    procedure ProbeTree(ARec: TJSONObject);
    procedure ProbeSun(ARec: TJSONObject);
    procedure ProbeTm(ARec: TJSONObject);
    procedure ProbeGeo(ARec: TJSONObject);
    procedure ProbeLine(ARec: TJSONObject);
    procedure ProbeRadar(ARec: TJSONObject);
    procedure ProbeTreeHit(ARec: TJSONObject);
    function HIdx30(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function HDur300(ADataIndex: Integer; AHasIndex: Boolean): Double;
    procedure CheckSample(const AProbes: TJSONArray; ARec: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
    procedure RunGroup(const AGroup: string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSunburstUpdatesAsUpstream;
    procedure TestTheTreemapTransitionsOnAMergeAsUpstream;
    procedure TestARoamMergeTweensTheViewAsUpstream;
    procedure TestAForceLayoutGoesOnFromItsPreservedPointsAsUpstream;
    procedure TestAStepChangeEntersAgainAsUpstream;
    procedure TestATreesDataMergeWalksTheOldTreeAsUpstream;
    procedure TestARadarsSymbolsSlideAsUpstream;
    procedure TestATreesEdgeInFlightIsHitWhereItIsDrawn;
  end;

implementation

{ ==================== helpers ==================== }

function TAu4Probe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
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
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SameBits(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := (HexOf(A) = HexOf(B)) or ((A = 0) and (B = 0));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function WantNum(AData: TJSONData): Double;
begin
  if IsNull(AData) then Result := NaN else Result := FromHex(AData.AsString);
end;

{ [R2-I2] {"$fn": name} -> '@name', in place, everywhere: the control's
  timing registry knows the name }
procedure Au4Fns(AData: TJSONData);
var
  i: Integer;
  child: TJSONData;
begin
  if (AData = nil) or not (AData.JSONType in [jtArray, jtObject]) then Exit;
  for i := 0 to AData.Count - 1 do
  begin
    child := AData.Items[i];
    if (child.JSONType = jtObject) and (TJSONObject(child).Count = 1)
      and (TJSONObject(child).Find('$fn') <> nil) then
      AData.Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
    else
      Au4Fns(child);
  end;
end;

{ ==================== the oracle ==================== }

function TAdvChartAnimUpdate4OracleTest.HIdx30(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  { (idx) => idx * 30; undefined * 30 is not a number }
  if AHasIndex then Result := ADataIndex * 30 else Result := NaN;
end;

function TAdvChartAnimUpdate4OracleTest.HDur300(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  { (idx) => 300 + idx * 400 }
  if AHasIndex then Result := 300 + ADataIndex * 400 else Result := NaN;
end;

procedure TAdvChartAnimUpdate4OracleTest.SetUp;
var
  sl: TStringList;
  maps: TJSONArray;
  i: Integer;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-anim-update4.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-anim-update4.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  Au4Fns(FRoot);
  TyChartRegisterAnimTiming('idx*30', @HIdx30);
  TyChartRegisterAnimTiming('dur:300+idx*400', @HDur300);
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    AssertTrue('the map registers', TyChartRegisterMap(maps.Objects[i].Strings['name'],
      maps.Objects[i].Strings['text']));
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartAnimUpdate4OracleTest.TearDown;
var
  maps: TJSONArray;
  i: Integer;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  TyChartUnregisterAnimTiming('idx*30');
  TyChartUnregisterAnimTiming('dur:300+idx*400');
  if FRoot <> nil then
  begin
    maps := TJSONObject(FRoot).Arrays['maps'];
    for i := 0 to maps.Count - 1 do TyChartUnregisterMap(maps.Objects[i].Strings['name']);
  end;
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAnimUpdate4OracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAnimUpdate4OracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := WantNum(AWant);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartAnimUpdate4OracleTest.NearNum(const AWhat: string; AGot: Double;
  AWant: TJSONData; ATol: Double);
var want: Double;
begin
  Inc(FCompared);
  want := WantNum(AWant);
  if IsNan(want) or IsNan(AGot) then
  begin
    if not (IsNan(want) and IsNan(AGot)) then
      Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
    Exit;
  end;
  if Abs(AGot - want) > ATol then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartAnimUpdate4OracleTest.NearVal(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if IsNan(AWant) or IsNan(AGot) then
  begin
    if not (IsNan(AWant) and IsNan(AGot)) then
      Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
    Exit;
  end;
  if Abs(AGot - AWant) > 1e-6 then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
end;

procedure TAdvChartAnimUpdate4OracleTest.SameKey(const AWhat: string;
  P: TTyChartAnimProxy; const AKey: string; AWant: TJSONData);
var v: TTyAnimValue;
begin
  v := P.GetAnimProp(AKey);
  if v.Kind <> avkNumber then
  begin
    Inc(FCompared);
    Bad(Format('%s: the proxy has no %s (upstream %s)', [AWhat, AKey, Txt(WantNum(AWant))]));
    Exit;
  end;
  SameNum(AWhat + '.' + AKey, v.Num, AWant);
end;

procedure TAdvChartAnimUpdate4OracleTest.SameArr(const AWhat: string;
  const AGot: TTyAnimValue; AWant: TJSONData);
var i, bad0: Integer;
begin
  Inc(FCompared);
  if AGot.Kind <> avkArray then
  begin
    Bad(AWhat + ': no array');
    Exit;
  end;
  if Length(AGot.Arr) <> AWant.Count then
  begin
    Bad(Format('%s: %d numbers, upstream %d', [AWhat, Length(AGot.Arr), AWant.Count]));
    Exit;
  end;
  bad0 := FBad;
  for i := 0 to AWant.Count - 1 do
  begin
    if FBad - bad0 > 3 then Break;
    SameNum(Format('%s[%d]', [AWhat, i]), AGot.Arr[i], AWant.Items[i]);
  end;
end;

procedure TAdvChartAnimUpdate4OracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TAu4Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartAnimUpdate4OracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ the frame's element of (series, row, role) -- the static list's when no
  frame is drawn -- the ASub-th of them when ASub >= 0 }
function TAdvChartAnimUpdate4OracleTest.FrameEl(ASeries, AIndex: Integer;
  ARole: TTyChartAnimRole; out AEl: TTyChartElement; ASub: Integer; ALast: Boolean): Boolean;
var
  l: TTyPaintList;
  i: Integer;
  e: TTyChartElement;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  l := FChart.Frame;
  if (l = nil) or (l.Count = 0) then l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
  begin
    e := l.Element(i);
    if (e.Anim.Role <> ARole) or (e.Anim.Series <> ASeries) or (e.Anim.Index <> AIndex) then
      Continue;
    if (ASub >= 0) and (e.Anim.Sub <> ASub) then Continue;
    AEl := e;
    Result := True;
    { a treemap's deleted rects come after the live ones }
    if not ALast then Exit;
  end;
end;

{ THE FRAME: a treemap rect where the frame drew it -- its shape through its
  group's global translation now (a deleted one: the last of the row's) }
procedure TAdvChartAnimUpdate4OracleTest.DrawnRect(const AWhat: string;
  ASeries, ARow, ASub: Integer; AData: TJSONObject; ALast: Boolean);
var
  el: TTyChartElement;
  sh, t: TJSONArray;
begin
  if (AData = nil) or (AData.Find('t') = nil) then Exit;
  if not FrameEl(ASeries, ARow, carTmRect, el, ASub, ALast) then
  begin
    Inc(FCompared);
    Bad(AWhat + ': not drawn');
    Exit;
  end;
  sh := AData.Arrays['sh'];
  t := AData.Arrays['t'];
  NearNum(AWhat + ' drawn left', el.Shape.Bounds.Left - WantNum(t.Items[0]), sh.Items[0], 1e-6);
  NearNum(AWhat + ' drawn top', el.Shape.Bounds.Top - WantNum(t.Items[1]), sh.Items[1], 1e-6);
  NearNum(AWhat + ' drawn width', el.Shape.Bounds.Right - el.Shape.Bounds.Left, sh.Items[2], 1e-6);
  NearNum(AWhat + ' drawn height', el.Shape.Bounds.Bottom - el.Shape.Bounds.Top, sh.Items[3], 1e-6);
end;

{ ---- a graph: the view group, the nodes, the ghosts, the edges ---- }
procedure TAdvChartAnimUpdate4OracleTest.ProbeGraph(ARec: TJSONObject);
var
  i, s, idx, slash: Integer;
  name, rest: string;
  leaf: TJSONObject;
  p: TTyChartAnimProxy;
  el: TTyChartElement;
  bx: TTyRectF;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if (Length(name) < 2) or (name[1] <> 'g') or not (name[2] in ['0'..'9']) then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 2, slash - 2));
    rest := Copy(name, slash + 1, MaxInt);
    leaf := TJSONObject(ARec.Items[i]);
    if rest = 'view' then
    begin
      p := FChart.AnimFindProxy(s, -1, 'viewGroup');
      if p = nil then
      begin
        if leaf.Integers['n'] > 0 then Bad(name + ': upstream tweens the view group, the port has no proxy');
        Continue;
      end;
      SameKey(name, p, 'x', leaf.Find('x'));
      SameKey(name, p, 'y', leaf.Find('y'));
      SameKey(name, p, 'scaleX', leaf.Find('scaleX'));
      SameKey(name, p, 'scaleY', leaf.Find('scaleY'));
    end
    else if Copy(rest, 1, 4) = 'node' then
    begin
      idx := StrToInt(Copy(rest, 5, MaxInt));
      p := FChart.AnimFindProxy(s, idx, 'symbol');
      if p = nil then
      begin
        if leaf.Integers['n'] > 0 then Bad(name + ': upstream animates the node, the port has no proxy');
      end
      else
      begin
        SameKey(name, p, 'x', leaf.Find('x'));
        SameKey(name, p, 'y', leaf.Find('y'));
        SameKey(name, p, 'scaleX', leaf.Find('sx'));
        SameKey(name, p, 'scaleY', leaf.Find('sy'));
        SameKey(name, p, 'style.opacity', leaf.Find('op'));
      end;
      { THE FRAME: the node's path on the canvas -- its centre, the group's
        global place }
      if FrameEl(s, idx, carSymbol, el) and TyRectFIsValid(TyShapeBounds(el.Shape))
        and (WantNum(leaf.Find('op')) > 0) and (WantNum(leaf.Find('sx')) > 0) then
      begin
        bx := TyShapeBounds(el.Shape);
        NearNum(name + ' drawn x', (bx.Left + bx.Right) / 2, leaf.Find('wx'), 1e-6);
        NearNum(name + ' drawn y', (bx.Top + bx.Bottom) / 2, leaf.Find('wy'), 1e-6);
      end;
    end
    else if Copy(rest, 1, 5) = 'ghost' then
    begin
      idx := StrToInt(Copy(rest, 6, MaxInt));
      p := FChart.AnimFindGhost(s, idx, 'symbol');
      if p = nil then
      begin
        Bad(name + ': upstream still fades it, the port has no ghost');
        Continue;
      end;
      SameKey(name, p, 'scaleX', leaf.Find('sx'));
      SameKey(name, p, 'scaleY', leaf.Find('sy'));
      SameKey(name, p, 'style.opacity', leaf.Find('op'));
    end
    else if Copy(rest, 1, 4) = 'edge' then
    begin
      idx := StrToInt(Copy(rest, 5, MaxInt));
      p := FChart.AnimFindProxy(s, idx, 'gedge');
      if p = nil then
      begin
        if leaf.Integers['n'] > 0 then Bad(name + ': upstream tweens the edge, the port has no proxy');
        Continue;
      end;
      SameKey(name, p, 'shape.percent', leaf.Find('percent'));
      SameKey(name, p, 'shape.x1', leaf.Find('x1'));
      SameKey(name, p, 'shape.y1', leaf.Find('y1'));
      SameKey(name, p, 'shape.x2', leaf.Find('x2'));
      SameKey(name, p, 'shape.y2', leaf.Find('y2'));
    end;
  end;
end;

{ ---- a tree: the view group, the nodes and their groups, the ghosts, the
  edges ---- }
procedure TAdvChartAnimUpdate4OracleTest.ProbeTree(ARec: TJSONObject);
var
  i, s, idx, slash: Integer;
  name, rest, num: string;
  leaf: TJSONObject;
  p, g: TTyChartAnimProxy;
  el: TTyChartElement;
  d: TJSONData;
  bx: TTyRectF;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'tr' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    rest := Copy(name, slash + 1, MaxInt);
    leaf := TJSONObject(ARec.Items[i]);
    if rest = 'view' then
    begin
      p := FChart.AnimFindProxy(s, -1, 'viewGroup');
      if p = nil then
      begin
        if leaf.Integers['n'] > 0 then Bad(name + ': upstream tweens the view group, the port has no proxy');
        Continue;
      end;
      SameKey(name, p, 'x', leaf.Find('x'));
      SameKey(name, p, 'y', leaf.Find('y'));
      SameKey(name, p, 'scaleX', leaf.Find('scaleX'));
      SameKey(name, p, 'scaleY', leaf.Find('scaleY'));
    end
    else if Copy(rest, 1, 4) = 'node' then
    begin
      idx := StrToInt(Copy(rest, 5, MaxInt));
      p := FChart.AnimFindProxy(s, idx, 'symbol');
      g := FChart.AnimFindProxy(s, idx, 'treeGroup');
      { THE FRAME: the path's centre on the canvas }
      if (WantNum(leaf.Find('op')) > 0) and (WantNum(leaf.Find('sx')) > 0) then
      begin
        if not FrameEl(s, idx, carTreeNode, el) then
        begin
          Inc(FCompared);
          Bad(name + ': not drawn');
        end
        else
        begin
          bx := TyShapeBounds(el.Shape);
          if TyRectFIsValid(bx) then
          begin
            NearNum(name + ' drawn x', (bx.Left + bx.Right) / 2, leaf.Find('wx'), 1e-6);
            NearNum(name + ' drawn y', (bx.Top + bx.Bottom) / 2, leaf.Find('wy'), 1e-6);
          end;
        end;
      end;
      if (p = nil) and (g = nil) then
      begin
        if leaf.Integers['n'] > 0 then Bad(name + ': upstream animates the node, the port has no proxy');
        Continue;
      end;
      if p <> nil then
      begin
        SameKey(name, p, 'scaleX', leaf.Find('sx'));
        SameKey(name, p, 'scaleY', leaf.Find('sy'));
        SameKey(name, p, 'style.opacity', leaf.Find('op'));
      end;
      if g <> nil then
      begin
        SameKey(name + ' group', g, 'x', leaf.Find('x'));
        SameKey(name + ' group', g, 'y', leaf.Find('y'));
      end
      else if FrameEl(s, idx, carTreeNode, el) then
      begin
        SameNum(name + ' group.x (rest)', el.Anim.G[5], leaf.Find('x'));
        SameNum(name + ' group.y (rest)', el.Anim.G[6], leaf.Find('y'));
      end;
    end
    else if Copy(rest, 1, 5) = 'ghost' then
    begin
      num := Copy(rest, 6, MaxInt);
      if Pos('_', num) > 0 then Continue;
      idx := StrToInt(num);
      p := FChart.AnimFindGhost(s, idx, 'treeNode');
      if p = nil then
      begin
        Bad(name + ': upstream still removes it, the port has no ghost');
        Continue;
      end;
      SameKey(name, p, 'x', leaf.Find('x'));
      SameKey(name, p, 'y', leaf.Find('y'));
      SameKey(name, p, 'scaleX', leaf.Find('sx'));
      SameKey(name, p, 'scaleY', leaf.Find('sy'));
      SameKey(name, p, 'style.opacity', leaf.Find('op'));
    end
    else if (Copy(rest, 1, 4) = 'edge') or (Copy(rest, 1, 5) = 'gedge') then
    begin
      if rest[1] = 'g' then
      begin
        num := Copy(rest, 6, MaxInt);
        if Pos('_', num) > 0 then Continue;
        p := FChart.AnimFindGhost(s, StrToInt(num), 'treeEdge');
        if p = nil then
        begin
          Bad(name + ': upstream still removes the edge, the port has no ghost');
          Continue;
        end;
      end
      else
      begin
        p := FChart.AnimFindProxy(s, StrToInt(Copy(rest, 5, MaxInt)), 'treeEdge');
        if p = nil then p := FChart.AnimFindGhost(s, StrToInt(Copy(rest, 5, MaxInt)), 'treeEdge');
        if p = nil then
        begin
          if leaf.Integers['n'] > 0 then Bad(name + ': upstream tweens the edge, the port has no proxy');
          Continue;
        end;
      end;
      SameKey(name, p, 'style.opacity', leaf.Find('op'));
      d := leaf.Find('parentPoint');
      if d <> nil then
      begin
        SameArr(name + '.parentPoint', p.GetAnimProp('shape.parentPoint'), d);
        SameArr(name + '.childPoints', p.GetAnimProp('shape.childPoints'), leaf.Find('childPoints'));
      end
      else
      begin
        SameKey(name, p, 'shape.x1', leaf.Find('x1'));
        SameKey(name, p, 'shape.y1', leaf.Find('y1'));
        SameKey(name, p, 'shape.cpx1', leaf.Find('cpx1'));
        SameKey(name, p, 'shape.cpy1', leaf.Find('cpy1'));
        SameKey(name, p, 'shape.cpx2', leaf.Find('cpx2'));
        SameKey(name, p, 'shape.cpy2', leaf.Find('cpy2'));
        SameKey(name, p, 'shape.x2', leaf.Find('x2'));
        SameKey(name, p, 'shape.y2', leaf.Find('y2'));
      end;
    end;
  end;
end;

{ ---- a sunburst: every piece's shape (its proxy, or the piece at rest) and
  its label's move or fade ---- }
procedure TAdvChartAnimUpdate4OracleTest.ProbeSun(ARec: TJSONObject);
const
  cKeys: array[0..5] of string = ('shape.cx', 'shape.cy', 'shape.r0', 'shape.r',
    'shape.startAngle', 'shape.endAngle');
var
  i, k, s, idx, slash: Integer;
  name, rest: string;
  leaf: TJSONObject;
  sh: TJSONArray;
  p: TTyChartAnimProxy;
  el: TTyChartElement;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'sb' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    rest := Copy(name, slash + 1, MaxInt);
    leaf := TJSONObject(ARec.Items[i]);
    if Pos('/label', rest) > 0 then
    begin
      idx := StrToInt(Copy(rest, 1, Pos('/', rest) - 1));
      p := FChart.AnimFindProxy(s, idx, 'label');
      if p = nil then
      begin
        if leaf.Integers['n'] > 0 then Bad(name + ': upstream animates the label, the port has no proxy');
        Continue;
      end;
      if p.GetAnimProp('x').Kind = avkNumber then
      begin
        SameKey(name, p, 'x', leaf.Find('x'));
        SameKey(name, p, 'y', leaf.Find('y'));
        SameKey(name, p, 'rotation', leaf.Find('rot'));
      end
      else if leaf.Integers['n'] > 0 then
      begin
        { upstream moves it: its x tween or its fade }
        if (WantNum(leaf.Find('op')) >= 1) then Bad(name + ': upstream moves the label, the port only fades it');
      end;
      if p.GetAnimProp('style.opacity').Kind = avkNumber then
        SameKey(name, p, 'style.opacity', leaf.Find('op'))
      else if not SameBits(WantNum(leaf.Find('op')), 1) then
        Bad(name + ': upstream fades the label, the port does not');
      Continue;
    end;
    idx := StrToInt(rest);
    sh := leaf.Arrays['sh'];
    p := FChart.AnimFindProxy(s, idx, 'sunPiece');
    if p = nil then
    begin
      if leaf.Integers['n'] > 0 then
      begin
        Bad(name + ': upstream animates the piece, the port has no proxy');
        Continue;
      end;
      { at rest: the piece as laid out }
      if not FrameEl(s, idx, carSunPiece, el) then
      begin
        Inc(FCompared);
        Bad(name + ': no piece');
        Continue;
      end;
      for k := 0 to 5 do SameNum(name + ' ' + cKeys[k] + ' (rest)', el.Anim.G[k], sh.Items[k]);
      Continue;
    end;
    for k := 0 to 5 do SameKey(name, p, cKeys[k], sh.Items[k]);
  end;
end;

{ ---- a treemap: every node's group and rects, and the deleted elements ---- }
procedure TAdvChartAnimUpdate4OracleTest.ProbeTm(ARec: TJSONObject);
const
  cKeys: array[0..3] of string = ('shape.x', 'shape.y', 'shape.width', 'shape.height');
var
  i, k, j, s, idx, slash, row, kind, n, want: Integer;
  name, rest: string;
  leaf, r, dl: TJSONObject;
  dels: TJSONArray;
  p: TTyChartAnimProxy;
  found: Boolean;

  procedure OneRect(const AWhat, AKind: string; AData: TJSONData);
  var q: TTyChartAnimProxy; z: Integer; o: TJSONObject;
  begin
    if IsNull(AData) then Exit;
    o := TJSONObject(AData);
    q := FChart.TreemapAnimProxy(s, idx, AKind);
    if q = nil then
    begin
      if o.Integers['n'] > 0 then Bad(AWhat + ': upstream tweens it, the port has no proxy');
      Exit;
    end;
    for z := 0 to 3 do SameKey(AWhat, q, cKeys[z], o.Arrays['sh'].Items[z]);
    if q.GetAnimProp('style.opacity').Kind = avkNumber then
      SameKey(AWhat, q, 'style.opacity', o.Find('op'));
  end;

begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'tm' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    rest := Copy(name, slash + 1, MaxInt);
    if rest = 'state' then
    begin
      Inc(FCompared);
      if (ARec.Strings[name] = 'animating') <> FChart.TreemapAnimating(s) then
        Bad(Format('%s: animating %s, upstream %s', [name, BoolToStr(FChart.TreemapAnimating(s), True),
          ARec.Strings[name]]));
      Continue;
    end;
    if rest = 'del' then
    begin
      dels := ARec.Arrays[name];
      { every deleted element: the port's ghost of that old row and kind }
      want := 0;
      for k := 0 to dels.Count - 1 do
      begin
        dl := dels.Objects[k];
        if dl.Strings['kind'] = 'nodeGroup' then
        begin
          p := FChart.TreemapAnimProxy(s, dl.Integers['di'], 'delGroup');
          Inc(FCompared);
          if p = nil then
          begin
            Bad(Format('%s: the deleted group of %d, the port has none', [name, dl.Integers['di']]));
            Continue;
          end;
          SameKey(name + ' group ' + IntToStr(dl.Integers['di']), p, 'x', dl.Arrays['g'].Items[0]);
          SameKey(name + ' group ' + IntToStr(dl.Integers['di']), p, 'y', dl.Arrays['g'].Items[1]);
          Continue;
        end;
        Inc(want);
        if dl.Strings['kind'] = 'background' then kind := 0 else kind := 1;
        found := False;
        n := FChart.TreemapGhostCount(s);
        for j := 0 to n - 1 do
        begin
          p := FChart.TreemapGhost(s, j, row, idx);
          if (row = dl.Integers['di']) and (idx = kind) then
          begin
            found := True;
            Break;
          end;
        end;
        Inc(FCompared);
        if not found then
        begin
          Bad(Format('%s: the deleted %s of %d, the port has no ghost', [name, dl.Strings['kind'],
            dl.Integers['di']]));
          Continue;
        end;
        for j := 0 to 3 do
          SameKey(Format('%s %s %d', [name, dl.Strings['kind'], dl.Integers['di']]), p, cKeys[j],
            dl.Arrays['sh'].Items[j]);
        DrawnRect(Format('%s %s %d', [name, dl.Strings['kind'], dl.Integers['di']]), s,
          dl.Integers['di'], kind, dl, True);
        SameKey(Format('%s %s %d', [name, dl.Strings['kind'], dl.Integers['di']]), p,
          'style.opacity', dl.Find('op'));
      end;
      Continue;
    end;
    idx := StrToInt(rest);
    leaf := TJSONObject(ARec.Items[i]);
    p := FChart.TreemapAnimProxy(s, idx, 'group');
    if p = nil then
    begin
      if leaf.Integers['gn'] > 0 then Bad(name + ': upstream slides the group, the port has no proxy');
    end
    else
    begin
      SameKey(name + ' group', p, 'x', leaf.Arrays['g'].Items[0]);
      SameKey(name + ' group', p, 'y', leaf.Arrays['g'].Items[1]);
    end;
    r := nil;
    if not IsNull(leaf.Find('bg')) then r := leaf.Objects['bg'];
    OneRect(name + ' bg', 'bg', r);
    DrawnRect(name + ' bg', s, idx, 0, r, False);
    r := nil;
    if not IsNull(leaf.Find('ct')) then r := leaf.Objects['ct'];
    OneRect(name + ' ct', 'ct', r);
    DrawnRect(name + ' ct', s, idx, 1, r, False);
  end;
end;

{ ---- a geo's transform group ---- }
procedure TAdvChartAnimUpdate4OracleTest.ProbeGeo(ARec: TJSONObject);
var
  i, key, k, n: Integer;
  name: string;
  leaf: TJSONObject;
  p: TTyChartAnimProxy;
  fl, sl: TTyPaintList;
  e, r: TTyChartElement;
  bf, br: TTyRectF;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    { a geo component's map view: its index + 1; a map series' own: -(the
      series index + 1) }
    if Copy(name, 1, 3) = 'geo' then key := StrToInt(Copy(name, 4, Pos('/', name) - 4)) + 1
    else if Copy(name, 1, 3) = 'map' then key := -(StrToInt(Copy(name, 4, Pos('/', name) - 4)) + 1)
    else Continue;
    leaf := TJSONObject(ARec.Items[i]);
    p := FChart.AnimFindProxy(-1, key, 'geoView');
    if p = nil then
    begin
      if leaf.Integers['n'] > 0 then Bad(name + ': upstream tweens the transform group, the port has no proxy');
      Continue;
    end;
    SameKey(name, p, 'x', leaf.Find('x'));
    SameKey(name, p, 'y', leaf.Find('y'));
    SameKey(name, p, 'scaleX', leaf.Find('scaleX'));
    SameKey(name, p, 'scaleY', leaf.Find('scaleY'));
    { THE FRAME: every region path of the map, carried from where it rests
      by upstream's group as it is now }
    fl := FChart.Frame;
    sl := FChart.List;
    if (fl = nil) or (fl.Count = 0) or (sl = nil) then Continue;
    n := 0;
    for k := 0 to Min(fl.Count, sl.Count) - 1 do
    begin
      e := fl.Element(k);
      r := sl.Element(k);
      if (e.Anim.GeoView <> key) or (r.Anim.GeoView <> key)
        or not (e.Shape.Kind in [cskPolygon, cskPolyline, cskPath])
        or (r.Shape.Kind <> e.Shape.Kind) then Continue;
      bf := TyShapeBounds(e.Shape);
      br := TyShapeBounds(r.Shape);
      if not (TyRectFIsValid(bf) and TyRectFIsValid(br)) then Continue;
      Inc(n);
      NearVal(Format('%s path %d drawn left', [name, k]), bf.Left, WantNum(leaf.Find('x'))
        + (br.Left - r.Anim.VX) * (WantNum(leaf.Find('scaleX')) / r.Anim.VSX));
      NearVal(Format('%s path %d drawn bottom', [name, k]), bf.Bottom, WantNum(leaf.Find('y'))
        + (br.Bottom - r.Anim.VY) * (WantNum(leaf.Find('scaleY')) / r.Anim.VSY));
    end;
    Inc(FCompared);
    if n = 0 then Bad(name + ': the frame draws no region of the map');
  end;
end;

{ ---- a line: its clip, its symbols' pop, whether its polyline tweens ---- }
procedure TAdvChartAnimUpdate4OracleTest.ProbeLine(ARec: TJSONObject);
var
  i, s, idx, slash: Integer;
  name, rest: string;
  leaf: TJSONObject;
  p: TTyChartAnimProxy;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'ln' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    rest := Copy(name, slash + 1, MaxInt);
    leaf := TJSONObject(ARec.Items[i]);
    if rest = 'clip' then
    begin
      p := FChart.AnimFindProxy(s, -1, 'lineClip');
      if p = nil then
      begin
        if leaf.Integers['n'] > 0 then Bad(name + ': upstream grows the clip, the port has no proxy');
        Continue;
      end;
      SameKey(name, p, 'shape.x', leaf.Find('x'));
      SameKey(name, p, 'shape.y', leaf.Find('y'));
      SameKey(name, p, 'shape.width', leaf.Find('width'));
      SameKey(name, p, 'shape.height', leaf.Find('height'));
    end
    else if rest = 'poly' then
    begin
      p := FChart.AnimFindProxy(s, -1, 'linePoly');
      Inc(FCompared);
      if (leaf.Integers['n'] > 0) and ((p = nil) or p.AtFinal) then
        Bad(name + ': upstream tweens the polyline, the port does not')
      else if (leaf.Integers['n'] = 0) and (p <> nil) and not p.AtFinal then
        Bad(name + ': the port tweens the polyline, upstream does not');
    end
    else if Copy(rest, 1, 3) = 'sym' then
    begin
      idx := StrToInt(Copy(rest, 4, MaxInt));
      p := FChart.AnimFindProxy(s, idx, 'lineSymbol');
      if p = nil then
      begin
        if leaf.Integers['n'] > 0 then Bad(name + ': upstream pops the symbol, the port has no proxy');
        Continue;
      end;
      SameKey(name, p, 'scaleX', leaf.Find('sx'));
      SameKey(name, p, 'scaleY', leaf.Find('sy'));
    end;
  end;
end;

{ ---- [R2-I2] a radar's item: its rings, its symbols where the frame draws
  them, the labels on them ---- }
{ ---- [R2-I3] a tree's edges hit in flight: what the chart's own hit test
  finds at upstream's points (the middle of each edge as drawn, and 4 px off
  it) -- the edge of node i, node i, another element or nothing ---- }
procedure TAdvChartAnimUpdate4OracleTest.ProbeTreeHit(ARec: TJSONObject);
var
  k: Integer;
  leaf: TJSONObject;
  name: string;

  { the list's own containment WITHOUT the port's mouse pad round a symbol
    (a deviation of long standing; upstream's answer is the shape's), on
    the frame where one is drawn -- the chart's hit test walks the same }
  function HitAt(AX, AY: Integer): string;
  var idx: Integer; el: TTyChartElement; L: TTyPaintList;
  begin
    if (FChart.Frame <> nil) and (FChart.Frame.Count = FChart.List.Count) then L := FChart.Frame
    else L := FChart.List;
    idx := L.HitTestElement(AX, AY, 96, False);
    if idx < 0 then Exit('null');
    el := FChart.List.Element(idx);
    if el.Anim.Role = carTreeEdge then Exit('edge' + IntToStr(el.Anim.Index));
    if (el.Datum.SeriesIndex >= 0) and (el.Datum.DataIndex >= 0) then
      Exit('node' + IntToStr(el.Datum.DataIndex));
    Result := 'other';
  end;

  procedure One(const AWhat, AKey: string; AX, AY: Integer);
  var want, got: string;
  begin
    if leaf.Find(AKey).JSONType = jtNull then want := 'null'
    else want := leaf.Strings[AKey];
    got := HitAt(AX, AY);
    Inc(FCompared);
    if got <> want then
      Bad(Format('%s (%d, %d): %s, upstream %s', [AWhat, AX, AY, got, want]));
  end;

begin
  for k := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[k];
    if Copy(name, 1, 2) <> 'th' then Continue;
    leaf := ARec.Objects[name];
    One(name + ' middle', 'hit', leaf.Integers['x'], leaf.Integers['y']);
    One(name + ' 4 px off', 'hit4', leaf.Integers['x4'], leaf.Integers['y4']);
  end;
end;

procedure TAdvChartAnimUpdate4OracleTest.ProbeRadar(ARec: TJSONObject);
var
  i, s, row, slash, k, j, h: Integer;
  name: string;
  leaf, sj, lj: TJSONObject;
  l: TTyPaintList;
  el, lab, rest: TTyChartElement;
  b0, b1: TTyRectF;
  syms: array of Integer;
  arr: TJSONArray;
  p: TTyChartAnimProxy;
  found: Boolean;

  procedure Ring(const AWhat: string; ARole: TTyChartAnimRole; AWant: TJSONArray;
    AClosedHere: Boolean);
  var
    e: TTyChartElement;
    q, m: Integer;
  begin
    Inc(FCompared);
    if not FrameEl(s, row, ARole, e) then
    begin
      Bad(AWhat + ': not drawn');
      Exit;
    end;
    { the area drops the closing point upstream's polygon carries }
    m := Length(e.Shape.Points);
    if not AClosedHere then Inc(m);
    if m * 2 <> AWant.Count then
    begin
      Bad(Format('%s: %d points, upstream %d', [AWhat, m, AWant.Count div 2]));
      Exit;
    end;
    for q := 0 to Length(e.Shape.Points) - 1 do
    begin
      SameNum(Format('%s[%d].x', [AWhat, q]), e.Shape.Points[q].X, AWant.Items[q * 2]);
      SameNum(Format('%s[%d].y', [AWhat, q]), e.Shape.Points[q].Y, AWant.Items[q * 2 + 1]);
    end;
  end;

begin
  l := FChart.Frame;
  if (l = nil) or (l.Count = 0) then l := FChart.List;
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'rd' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    row := StrToInt(Copy(name, slash + 1, MaxInt));
    leaf := TJSONObject(ARec.Items[i]);
    Ring(name + ' line', carRadarLine, leaf.Arrays['line'], True);
    Ring(name + ' area', carRadarArea, leaf.Arrays['area'], False);
    { the rings' points are compared above, frame by frame; a tween to the
      points it already has runs a clip upstream (zrender keeps a track of
      equal values) and none here -- nothing drawn differs }
    p := FChart.AnimFindProxy(s, row, 'radarLine');
    Inc(FCompared);
    if (leaf.Integers['ln'] = 0) and (p <> nil) and not p.AtFinal then
      Bad(name + ': the port tweens the polyline, upstream does not');
    { THE SYMBOLS of the item, in the group's order (their spokes) }
    syms := nil;
    for k := 0 to l.Count - 1 do
    begin
      el := l.Element(k);
      if (el.Anim.Role <> carNone) or (el.Anim.UtTag <> 1) or (el.Anim.Sub <= 0)
        or (el.Anim.Series <> s) or (el.Anim.UtRow <> row) then Continue;
      SetLength(syms, Length(syms) + 1);
      syms[High(syms)] := k;
    end;
    arr := leaf.Arrays['syms'];
    Inc(FCompared);
    if Length(syms) <> arr.Count then
    begin
      Bad(Format('%s: %d symbols, upstream %d', [name, Length(syms), arr.Count]));
      Continue;
    end;
    for j := 0 to arr.Count - 1 do
    begin
      sj := arr.Objects[j];
      el := l.Element(syms[j]);
      SameNum(Format('%s sym%d.x', [name, j]), el.Caption.LgG[5], sj.Find('x'));
      SameNum(Format('%s sym%d.y', [name, j]), el.Caption.LgG[6], sj.Find('y'));
      { the path drawn there: the one at rest moved by as much }
      rest := FChart.List.Element(syms[j]);
      b0 := TyShapeBounds(rest.Shape);
      b1 := TyShapeBounds(el.Shape);
      NearVal(Format('%s sym%d drawn dx', [name, j]), b1.Left - b0.Left,
        WantNum(sj.Find('x')) - rest.Caption.LgG[5]);
      NearVal(Format('%s sym%d drawn dy', [name, j]), b1.Top - b0.Top,
        WantNum(sj.Find('y')) - rest.Caption.LgG[6]);
      p := FChart.AnimFindProxy(s, row, TyRadarSymRole(el.Anim.Sub - 1));
      Inc(FCompared);
      if (sj.Integers['n'] > 0) and ((p = nil) or p.AtFinal) then
        Bad(Format('%s sym%d: upstream slides it, the port does not', [name, j]))
      else if (sj.Integers['n'] = 0) and (p <> nil) and not p.AtFinal then
        Bad(Format('%s sym%d: the port slides it, upstream does not', [name, j]));
      { ITS LABEL, riding it }
      if leaf.Arrays['labs'].Items[j].JSONType = jtNull then Continue;
      lj := leaf.Arrays['labs'].Objects[j];
      { an empty text paints nothing upstream; here there is no label }
      if lj.Strings['tx'] = '' then Continue;
      found := False;
      for h := 0 to l.Count - 1 do
      begin
        lab := l.Element(h);
        if (lab.Anim.Role = carLabel) and (lab.Anim.HostPlus1 = syms[j] + 1) then
        begin
          found := True;
          Break;
        end;
      end;
      Inc(FCompared);
      if not found then
      begin
        Bad(Format('%s lab%d: a label upstream, none on the symbol here', [name, j]));
        Continue;
      end;
      NearNum(Format('%s lab%d.x', [name, j]), lab.Caption.X, lj.Find('x'), 1e-9);
      NearNum(Format('%s lab%d.y', [name, j]), lab.Caption.Y, lj.Find('y'), 1e-9);
      { a frame draws a label faded to nought as no words at all }
      if lab.Caption.Text = '' then SameNum(Format('%s lab%d.op', [name, j]), 0, lj.Find('op'))
      else SameNum(Format('%s lab%d.op', [name, j]), lab.Style.Alpha, lj.Find('op'));
      Inc(FCompared);
      if lab.Ignore <> lj.Booleans['ig'] then
        Bad(Format('%s lab%d: ignore %s, upstream %s', [name, j,
          BoolToStr(lab.Ignore, True), BoolToStr(lj.Booleans['ig'], True)]));
    end;
  end;
end;

procedure TAdvChartAnimUpdate4OracleTest.CheckSample(const AProbes: TJSONArray;
  ARec: TJSONObject);
var i: Integer;
begin
  for i := 0 to AProbes.Count - 1 do
    if AProbes.Strings[i] = 'graph' then ProbeGraph(ARec)
    else if AProbes.Strings[i] = 'tree' then ProbeTree(ARec)
    else if AProbes.Strings[i] = 'sun' then ProbeSun(ARec)
    else if AProbes.Strings[i] = 'tm' then ProbeTm(ARec)
    else if AProbes.Strings[i] = 'geo' then ProbeGeo(ARec)
    else if AProbes.Strings[i] = 'line' then ProbeLine(ARec)
    else if AProbes.Strings[i] = 'radar' then ProbeRadar(ARec)
    else if AProbes.Strings[i] = 'treeHit' then ProbeTreeHit(ARec)
    else Bad('a probe the test does not know: ' + AProbes.Strings[i]);
end;

procedure TAdvChartAnimUpdate4OracleTest.RunCase(ACase: TJSONObject);
var
  events: TJSONArray;
  ev: TJSONObject;
  j: Integer;
  t0, now_: Double;
  act: string;
begin
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  t0 := TJSONObject(FRoot).Objects['clock'].Floats['T0'];
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := t0;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
  events := ACase.Arrays['events'];
  for j := 0 to events.Count - 1 do
  begin
    ev := events.Objects[j];
    now_ := t0 + ev.Floats['t'];
    act := ev.Strings['do'];
    FWhere := Format('%s t=%s %s', [ACase.Strings['id'], Txt(ev.Floats['t']), act]);
    FChart.AnimNow := now_;
    if act = 'sample' then
    begin
      FChart.AnimTick(now_);
      RenderNow;
      Inc(FSamples);
      CheckSample(ACase.Arrays['probes'], ev.Objects['rec']);
    end
    else if act = 'frame' then
    begin
      FChart.AnimTick(now_);
      RenderNow;
    end
    else if act = 'merge' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, False);
      RenderNow;
    end
    else if act = 'action' then
      { no paint: a state an action changed is applied in the next frame }
      FChart.DispatchAction(ev.Objects['action'].AsJSON)
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartAnimUpdate4OracleTest.RunGroup(const AGroup: string; AMin: Integer);
var
  cases: TJSONArray;
  i, n: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  n := 0;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['group'] = AGroup then
    begin
      try
        RunCase(cases.Objects[i]);
      except
        on E: Exception do
        begin
          Bad(E.ClassName + ': ' + E.Message);
          if FChart <> nil then FChart.Measurer := nil;
          FreeAndNil(FChart);
        end;
      end;
      Inc(n);
    end;
  AssertTrue('cases run', n > 0);
  if FBad > 0 then
    Fail(Format('%s: %d of %d comparisons differ from upstream:%s',
      [AGroup, FBad, FCompared, FReport]));
  AssertTrue(Format('%s: comparisons made (%d)', [AGroup, FCompared]), FCompared >= AMin);
end;

procedure TAdvChartAnimUpdate4OracleTest.TestTheSunburstUpdatesAsUpstream;
begin
  RunGroup('sunburst', 1000);
end;

procedure TAdvChartAnimUpdate4OracleTest.TestTheTreemapTransitionsOnAMergeAsUpstream;
begin
  RunGroup('treemap', 1000);
end;

procedure TAdvChartAnimUpdate4OracleTest.TestARoamMergeTweensTheViewAsUpstream;
begin
  RunGroup('roam', 300);
end;

procedure TAdvChartAnimUpdate4OracleTest.TestAForceLayoutGoesOnFromItsPreservedPointsAsUpstream;
begin
  RunGroup('force', 300);
end;

procedure TAdvChartAnimUpdate4OracleTest.TestAStepChangeEntersAgainAsUpstream;
begin
  RunGroup('step', 300);
end;

procedure TAdvChartAnimUpdate4OracleTest.TestARadarsSymbolsSlideAsUpstream;
begin
  RunGroup('radar', 5000);
end;

procedure TAdvChartAnimUpdate4OracleTest.TestATreesEdgeInFlightIsHitWhereItIsDrawn;
begin
  RunGroup('treeHit', 100);
end;

procedure TAdvChartAnimUpdate4OracleTest.TestATreesDataMergeWalksTheOldTreeAsUpstream;
begin
  RunGroup('treeData', 1000);
end;

initialization
  RegisterTest(TAdvChartAnimUpdate4OracleTest);
end.
