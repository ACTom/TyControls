unit test.advchart.animupdate3;
{$mode objfpc}{$H+}
{ THE UPDATE TRANSITIONS F3a AND F3b LEFT OVER, HELD TO UPSTREAM [F3d].

  tools/advchart-oracle/anim-update3.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock, what each case's probes name:

    graph      a graph's update: the view group's transform, the nodes'
               groups and paths, the removed nodes' fade, the edges' shapes
               and their percent (a legend toggle, a merge that moves and
               adds, a circular layout solved again, an update while the
               enter runs, a graph on cartesian2d);
    tree       treeExpandAndCollapse and its removals: the node groups from
               the source's old place, the removed ones to the source's place
               + 1 and their fade, the curves and the TreePaths;
    radial     a radial tree's labels, placed from the host's scaled rect
               every frame;
    pictorial  a data item's array symbolSize / symbolOffset in the static
               layout;
    stateGrad  a state whose colour is a gradient: the gradient track of
               the state's fill.

  This replays every case through the control and compares, bit for bit,
  the proxies the control animates -- and, for what a frame derives from
  them (a node's place on the canvas, an edge's arrow, a radial label), the
  frame's element against upstream's global transform. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Anim,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.Shape, tyControls.AdvChart.AnimOpt,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  TAu3Probe = class(TGfxProbe)
  public
    function Frame: TTyPaintList;
  end;

  TAdvChartAnimUpdate3OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAu3Probe;
    FRoot: TJSONData;
    FBad, FCompared, FSamples: Integer;
    FWhere, FReport: string;
    { a circular layout's case: the ring's cos / sin are not correctly
      rounded in either runtime -- its numbers to 1e-9 }
    FTol: Double;
    { [F3d] a sample past the case's placeFrom: places not compared }
    FNoPlace: Boolean;
    { [fin] a treeExpandAndCollapse action replayed through TreeToggle (the
      public method a click goes through), and how many were }
    FByMethod: Boolean;
    FToggles: Integer;
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
      out AEl: TTyChartElement; ASub: Integer = -1): Boolean;
    procedure ProbeGraph(ARec: TJSONObject);
    procedure ProbeTree(ARec: TJSONObject);
    procedure DrawnCentre(const AWhat: string; ASeries, AIndex: Integer; ALeaf: TJSONObject);
    procedure DrawnOutline(const AWhat: string; const AEl: TTyChartElement; ALeaf: TJSONObject);
    procedure ProbePictorial(ARec: TJSONObject);
    procedure ProbeState(ARec: TJSONObject);
    procedure ProbeLabels(ARec: TJSONObject);
    procedure CheckSample(const AProbes: TJSONArray; ARec: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
    procedure RunGroup(const AGroup: string; AMin: Integer);
    function HIdx30(ADataIndex: Integer; AHasIndex: Boolean): Double;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGraphUpdatesAsUpstream;
    procedure TestTheTreeExpandsAndCollapsesAsUpstream;
    procedure TestTheRadialLabelsFollowTheirNodesAsUpstream;
    procedure TestAnItemsArraySymbolSizeAsUpstream;
    procedure TestAStatesGradientTweensAsUpstream;
    procedure TestATreeToggleIsTheAction;
    procedure TestARenderEndsTheLabelsFadesAsUpstream;
  end;

implementation

{ ==================== helpers ==================== }

function TAu3Probe.Frame: TTyPaintList;
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

{ a CSS colour as upstream writes it -- '#rgb', '#rrggbb', 'rgb(...)',
  'rgba(...)' -- into r, g, b and a; False for anything else }
function ParseCss(const S: string; out R, G, B, A: Double): Boolean;
var
  t, body: string;
  parts: TStringList;
  fs: TFormatSettings;

  function Hex2(const H: string): Double;
  begin
    Result := StrToInt('$' + H);
  end;

begin
  Result := False;
  R := NaN; G := NaN; B := NaN; A := NaN;
  t := LowerCase(Trim(S));
  if (Length(t) = 7) and (t[1] = '#') then
  begin
    R := Hex2(Copy(t, 2, 2)); G := Hex2(Copy(t, 4, 2)); B := Hex2(Copy(t, 6, 2)); A := 1;
    Exit(True);
  end;
  if (Length(t) = 4) and (t[1] = '#') then
  begin
    R := Hex2(t[2] + t[2]); G := Hex2(t[3] + t[3]); B := Hex2(t[4] + t[4]); A := 1;
    Exit(True);
  end;
  if (Copy(t, 1, 5) = 'rgba(') or (Copy(t, 1, 4) = 'rgb(') then
  begin
    body := Copy(t, Pos('(', t) + 1, MaxInt);
    body := Copy(body, 1, Pos(')', body) - 1);
    fs := DefaultFormatSettings;
    fs.DecimalSeparator := '.';
    parts := TStringList.Create;
    try
      parts.Delimiter := ',';
      parts.StrictDelimiter := True;
      parts.DelimitedText := body;
      if parts.Count < 3 then Exit;
      R := StrToFloat(Trim(parts[0]), fs);
      G := StrToFloat(Trim(parts[1]), fs);
      B := StrToFloat(Trim(parts[2]), fs);
      if parts.Count > 3 then A := StrToFloat(Trim(parts[3]), fs) else A := 1;
      Result := True;
    finally
      parts.Free;
    end;
  end;
end;

{ ==================== the oracle ==================== }

{ [fin] {"$fn": name} -> '@name', in place, everywhere: the control's timing
  registry knows the name }
procedure Au3Fns(AData: TJSONData);
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
      Au3Fns(child);
  end;
end;

function TAdvChartAnimUpdate3OracleTest.HIdx30(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  { (idx) => idx * 30; undefined * 30 is not a number, and `delay || 0` }
  if AHasIndex then Result := ADataIndex * 30 else Result := NaN;
end;

procedure TAdvChartAnimUpdate3OracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-anim-update3.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-anim-update3.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  Au3Fns(FRoot);
  TyChartRegisterAnimTiming('idx*30', @HIdx30);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartAnimUpdate3OracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  TyChartUnregisterAnimTiming('idx*30');
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAnimUpdate3OracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAnimUpdate3OracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := WantNum(AWant);
  if (FTol > 0) and not IsNan(want) and not IsNan(AGot) then
  begin
    if Abs(AGot - want) > FTol then
      Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
    Exit;
  end;
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartAnimUpdate3OracleTest.NearNum(const AWhat: string; AGot: Double;
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

procedure TAdvChartAnimUpdate3OracleTest.NearVal(const AWhat: string; AGot, AWant: Double);
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

procedure TAdvChartAnimUpdate3OracleTest.SameKey(const AWhat: string;
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

procedure TAdvChartAnimUpdate3OracleTest.SameArr(const AWhat: string;
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

procedure TAdvChartAnimUpdate3OracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TAu3Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartAnimUpdate3OracleTest.RenderNow;
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
function TAdvChartAnimUpdate3OracleTest.FrameEl(ASeries, AIndex: Integer;
  ARole: TTyChartAnimRole; out AEl: TTyChartElement; ASub: Integer): Boolean;
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
    Exit(True);
  end;
end;

{ [R2-H] AN EDGE'S END SYMBOL AS DRAWN, point by point: upstream's outline
  (its built path through its global transform -- the vertices of an arrow,
  a circle's centre and radius) against the frame's element (a polygon's
  points from the first, a circle's centre and radius) }
procedure TAdvChartAnimUpdate3OracleTest.DrawnOutline(const AWhat: string;
  const AEl: TTyChartElement; ALeaf: TJSONObject);
var
  pts, arcs: TJSONArray;
  n, k: Integer;
  bx: TTyRectF;
begin
  pts := nil;
  arcs := nil;
  if ALeaf.Find('pts') is TJSONArray then pts := TJSONArray(ALeaf.Find('pts'));
  if ALeaf.Find('arcs') is TJSONArray then arcs := TJSONArray(ALeaf.Find('arcs'));
  if arcs <> nil then
  begin
    { a circle: the moveTo before its arc is the arc's start, not a vertex }
    Inc(FCompared);
    if AEl.Shape.Kind <> cskCircle then
    begin
      Bad(AWhat + ': upstream draws a circle, the port another shape');
      Exit;
    end;
    bx := TyShapeBounds(AEl.Shape);
    NearNum(AWhat + ' drawn cx', (bx.Left + bx.Right) / 2, arcs.Items[0], 1e-6);
    NearNum(AWhat + ' drawn cy', (bx.Top + bx.Bottom) / 2, arcs.Items[1], 1e-6);
    NearNum(AWhat + ' drawn r', (bx.Right - bx.Left) / 2, arcs.Items[2], 1e-6);
    Exit;
  end;
  if pts = nil then Exit;
  { the closing lineTo back to the first point is not a vertex of its own }
  n := pts.Count div 2;
  if (n > 1) and (pts.Items[0].AsString = pts.Items[2 * n - 2].AsString)
    and (pts.Items[1].AsString = pts.Items[2 * n - 1].AsString) then Dec(n);
  Inc(FCompared);
  if Length(AEl.Shape.Points) <> n then
  begin
    Bad(Format('%s: %d points drawn, upstream %d', [AWhat, Length(AEl.Shape.Points), n]));
    Exit;
  end;
  for k := 0 to n - 1 do
  begin
    NearNum(Format('%s drawn x%d', [AWhat, k]), AEl.Shape.Points[k].X, pts.Items[2 * k], 1e-6);
    NearNum(Format('%s drawn y%d', [AWhat, k]), AEl.Shape.Points[k].Y, pts.Items[2 * k + 1], 1e-6);
  end;
end;

{ ---- a graph: the view group, the nodes, the ghosts, the edges ---- }
procedure TAdvChartAnimUpdate3OracleTest.ProbeGraph(ARec: TJSONObject);
var
  i, s, idx, slash: Integer;
  name, rest, sub: string;
  leaf: TJSONObject;
  p: TTyChartAnimProxy;
  el: TTyChartElement;
  cx, cy, vsx, vsy, vx, vy: Double;
  bx: TTyRectF;
  vw: TJSONObject;
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
        if not FNoPlace then
        begin
          SameKey(name, p, 'x', leaf.Find('x'));
          SameKey(name, p, 'y', leaf.Find('y'));
        end
        else if leaf.Integers['n'] = 0 then
        begin
          { the place not compared: still, nothing of it moves here either }
          Inc(FCompared);
          if not (SameBits(p.Num('x'), p.FinalOf('x').Num) and SameBits(p.Num('y'), p.FinalOf('y').Num)) then
            Bad(name + ': the group slides here, upstream sets it');
        end;
        SameKey(name, p, 'scaleX', leaf.Find('sx'));
        SameKey(name, p, 'scaleY', leaf.Find('sy'));
        SameKey(name, p, 'style.opacity', leaf.Find('op'));
      end;
      { THE FRAME: the node's path on the canvas -- its centre, the group's
        global place }
      if not FNoPlace and FrameEl(s, idx, carSymbol, el)
        and TyRectFIsValid(TyShapeBounds(el.Shape)) and (WantNum(leaf.Find('op')) > 0)
        and (WantNum(leaf.Find('sx')) > 0) then
      begin
        { [fin] the shape's own extent: a circle's is its centre and radius
          (Shape.Bounds is only a rect's or a path's) }
        bx := TyShapeBounds(el.Shape);
        cx := (bx.Left + bx.Right) / 2;
        cy := (bx.Top + bx.Bottom) / 2;
        NearNum(name + ' drawn x', cx, leaf.Find('wx'), 1e-6);
        NearNum(name + ' drawn y', cy, leaf.Find('wy'), 1e-6);
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
      sub := '';
      if Pos('/', rest) > 0 then
      begin
        sub := Copy(rest, Pos('/', rest) + 1, MaxInt);
        rest := Copy(rest, 1, Pos('/', rest) - 1);
      end;
      idx := StrToInt(Copy(rest, 5, MaxInt));
      p := FChart.AnimFindProxy(s, idx, 'gedge');
      if sub = '' then
      begin
        if p = nil then
        begin
          if leaf.Integers['n'] > 0 then Bad(name + ': upstream tweens the edge, the port has no proxy');
        end
        else
        begin
          SameKey(name, p, 'shape.percent', leaf.Find('percent'));
          if not FNoPlace then
          begin
            SameKey(name, p, 'shape.x1', leaf.Find('x1'));
            SameKey(name, p, 'shape.y1', leaf.Find('y1'));
            SameKey(name, p, 'shape.x2', leaf.Find('x2'));
            SameKey(name, p, 'shape.y2', leaf.Find('y2'));
            SameKey(name, p, 'shape.cpx1', leaf.Find('cpx1'));
            SameKey(name, p, 'shape.cpy1', leaf.Find('cpy1'));
          end;
        end;
      end;
      { THE FRAME: a whole straight line's two ends on the canvas -- the
        shape through the main group as it is now }
      if FNoPlace then
      else if (sub = '') and (WantNum(leaf.Find('percent')) = 1) and IsNan(WantNum(leaf.Find('cpx1')))
        and FrameEl(s, idx, carGraphEdge, el) and (Length(el.Shape.Points) = 2) then
      begin
        vw := TJSONObject(ARec.Find('g' + IntToStr(s) + '/view'));
        if vw <> nil then
        begin
          vsx := WantNum(vw.Find('scaleX'));
          vsy := WantNum(vw.Find('scaleY'));
          vx := WantNum(vw.Find('x'));
          vy := WantNum(vw.Find('y'));
        end
        else
        begin
          vsx := 1;
          vsy := 1;
          vx := 0;
          vy := 0;
        end;
        NearVal(name + ' drawn x1', el.Shape.Points[0].X, vsx * WantNum(leaf.Find('x1')) + vx);
        NearVal(name + ' drawn y1', el.Shape.Points[0].Y, vsy * WantNum(leaf.Find('y1')) + vy);
        NearVal(name + ' drawn x2', el.Shape.Points[1].X, vsx * WantNum(leaf.Find('x2')) + vx);
        NearVal(name + ' drawn y2', el.Shape.Points[1].Y, vsy * WantNum(leaf.Find('y2')) + vy);
      end
      { THE FRAME: the label's anchor where beforeUpdate hung it, through the
        group }
      else if (sub = 'label') and (WantNum(leaf.Find('op')) > 0)
        and FrameEl(s, idx, carGraphEdgeLabel, el) then
      begin
        NearNum(name + ' drawn x', el.Caption.X, leaf.Find('wx'), 1e-6);
        NearNum(name + ' drawn y', el.Caption.Y, leaf.Find('wy'), 1e-6);
      end
      { [R2-H] THE FRAME: an end symbol point by point, where the line has
        drawn out (at percent 0 its scale is 0: nothing to draw) }
      else if ((sub = 'from') or (sub = 'to')) and (leaf.Find('hidden') = nil)
        and (ARec.Find('g' + IntToStr(s) + '/edge' + IntToStr(idx)) is TJSONObject)
        and (WantNum(TJSONObject(ARec.Find('g' + IntToStr(s) + '/edge' + IntToStr(idx))).Find('percent')) > 0) then
      begin
        Inc(FCompared);
        if sub = 'to' then
        begin
          if not FrameEl(s, idx, carGraphEdgeTo, el) then
            Bad(name + ': upstream draws the end symbol, the frame has none')
          else
            DrawnOutline(name, el, leaf);
        end
        else if not FrameEl(s, idx, carGraphEdgeFrom, el) then
          Bad(name + ': upstream draws the end symbol, the frame has none')
        else
          DrawnOutline(name, el, leaf);
      end;
    end;
  end;
end;

{ ---- a tree: the view group, the nodes and their groups, the ghosts, the
  edges, the labels ---- }
procedure TAdvChartAnimUpdate3OracleTest.DrawnCentre(const AWhat: string;
  ASeries, AIndex: Integer; ALeaf: TJSONObject);
var
  el: TTyChartElement;
  bx: TTyRectF;
begin
  { THE FRAME: the path's centre on the canvas against its global place --
    a live node's, or (none live) its ghost's }
  if (WantNum(ALeaf.Find('op')) <= 0) or not (WantNum(ALeaf.Find('sx')) > 0) then Exit;
  if not FrameEl(ASeries, AIndex, carTreeNode, el) then
  begin
    Inc(FCompared);
    Bad(AWhat + ': not drawn');
    Exit;
  end;
  { [fin] the shape's own extent (a circle has no Shape.Bounds) }
  bx := TyShapeBounds(el.Shape);
  if not TyRectFIsValid(bx) then Exit;
  NearNum(AWhat + ' drawn x', (bx.Left + bx.Right) / 2, ALeaf.Find('wx'), 1e-6);
  NearNum(AWhat + ' drawn y', (bx.Top + bx.Bottom) / 2, ALeaf.Find('wy'), 1e-6);
end;

procedure TAdvChartAnimUpdate3OracleTest.ProbeTree(ARec: TJSONObject);
var
  i, s, idx, slash: Integer;
  name, rest, num: string;
  leaf: TJSONObject;
  p, g: TTyChartAnimProxy;
  el: TTyChartElement;
  d: TJSONData;
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
      DrawnCentre(name, s, idx, leaf);
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
      else if p <> nil then
      begin
        { a group at rest: the layout's place }
        if FrameEl(s, idx, carTreeNode, el) then
        begin
          SameNum(name + ' group.x (rest)', el.Anim.G[5], leaf.Find('x'));
          SameNum(name + ' group.y (rest)', el.Anim.G[6], leaf.Find('y'));
        end;
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
      if ARec.Find('tr' + IntToStr(s) + '/node' + IntToStr(idx)) = nil then
        DrawnCentre(name, s, idx, leaf);
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
        { a kept node's TreePath a collapse takes away: the node's __edge,
          a ghost here }
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
    end
    else if (Copy(rest, 1, 5) = 'label') or (Copy(rest, 1, 6) = 'glabel') then
    begin
      { THE FRAME: the text's origin on the canvas, where updateInnerText
        placed it from the host's rect as it is now -- a removed node's
        label too, where no live one has the row }
      if rest[1] = 'g' then
      begin
        num := Copy(rest, 7, MaxInt);
        if Pos('_', num) > 0 then Continue;
        if ARec.Find('tr' + IntToStr(s) + '/label' + num) <> nil then Continue;
        rest := 'label' + num;
      end;
      idx := StrToInt(Copy(rest, 6, MaxInt));
      if WantNum(leaf.Find('op')) <= 0 then Continue;
      if not FrameEl(s, idx, carLabel, el) then
      begin
        Bad(name + ': no label in the frame');
        Continue;
      end;
      NearNum(name + ' x', el.Caption.X, TJSONArray(leaf.Find('m')).Items[4], 1e-6);
      NearNum(name + ' y', el.Caption.Y, TJSONArray(leaf.Find('m')).Items[5], 1e-6);
    end;
  end;
end;

{ ---- a pictorial bar's static glyphs: how many, their scale and place ---- }
procedure TAdvChartAnimUpdate3OracleTest.ProbePictorial(ARec: TJSONObject);
var
  i, j, s, row, colon, slash, k, n, want: Integer;
  name, glyph: string;
  leaf: TJSONObject;
  l: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
begin
  l := FChart.List;
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 4) <> 'pict' then Continue;
    colon := Pos(':', name);
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 5, colon - 5));
    row := StrToInt(Copy(name, colon + 1, slash - colon - 1));
    glyph := Copy(name, slash + 1, MaxInt);
    if glyph = 'count' then
    begin
      { A GLYPH OF NO NUMBER for a scale (`symbolSize: [18]`: the second is
        parsePercent(undefined)) draws nothing upstream; the port makes no
        element of it -- the same picture, one path fewer }
      want := 0;
      for j := 0 to ARec.Integers[name] - 1 do
      begin
        leaf := TJSONObject(ARec.Find(Copy(name, 1, slash) + IntToStr(j)));
        if (leaf <> nil) and not IsNan(WantNum(leaf.Find('scaleX')))
          and not IsNan(WantNum(leaf.Find('scaleY'))) then Inc(want);
      end;
      n := 0;
      for j := 0 to l.Count - 1 do
      begin
        e := l.Element(j);
        if (e.Anim.Role = carPictorialGlyph) and (e.Anim.Series = s) and (e.Anim.Index = row) then
          Inc(n);
      end;
      Inc(FCompared);
      if n <> want then
        Bad(Format('%s: %d glyphs, upstream %d', [name, n, want]));
      Continue;
    end;
    k := StrToInt(glyph);
    leaf := TJSONObject(ARec.Items[i]);
    if IsNan(WantNum(leaf.Find('scaleX'))) or IsNan(WantNum(leaf.Find('scaleY'))) then Continue;
    found := False;
    for j := 0 to l.Count - 1 do
    begin
      e := l.Element(j);
      if (e.Anim.Role = carPictorialGlyph) and (e.Anim.Series = s) and (e.Anim.Index = row)
        and (e.Anim.Sub = k) then
      begin
        found := True;
        Break;
      end;
    end;
    if not found then
    begin
      Bad(name + ': no glyph');
      Continue;
    end;
    SameNum(name + '.scaleX', e.Anim.G[2], leaf.Find('scaleX'));
    SameNum(name + '.scaleY', e.Anim.G[3], leaf.Find('scaleY'));
    SameNum(name + '.x', e.Anim.G[0], leaf.Find('gx'));
    SameNum(name + '.y', e.Anim.G[1], leaf.Find('gy'));
  end;
end;

{ ---- a state's gradient: the state proxy's fill and the frame's ---- }
procedure TAdvChartAnimUpdate3OracleTest.ProbeState(ARec: TJSONObject);
var
  i, k, s, row, slash, n: Integer;
  name, typ: string;
  leaf, fill, stop: TJSONObject;
  stops: TJSONArray;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  el: TTyChartElement;
  r, g, b, a: Double;
  geo: array of string;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'st' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    row := StrToInt(Copy(name, slash + 1, MaxInt));
    leaf := TJSONObject(ARec.Items[i]);
    p := FChart.AnimStateProxy(s, row, 'host');
    if p = nil then
    begin
      Bad(name + ': no state proxy');
      Continue;
    end;
    v := p.GetAnimProp('style.fill');
    Inc(FCompared);
    if leaf.Find('fill').JSONType <> jtObject then
    begin
      { a colour: the port's is no gradient }
      if v.Kind = avkGradient then Bad(name + ': a gradient, upstream a colour');
      Continue;
    end;
    fill := leaf.Objects['fill'];
    if v.Kind <> avkGradient then
    begin
      Bad(name + ': no gradient, upstream ' + fill.Strings['type']);
      Continue;
    end;
    typ := fill.Strings['type'];
    if typ = 'linear' then geo := ['x', 'y', 'x2', 'y2'] else geo := ['x', 'y', 'r'];
    Inc(FCompared);
    if Length(v.Arr) <> Length(geo) then
    begin
      Bad(Format('%s: %d numbers of geometry, upstream %s', [name, Length(v.Arr), typ]));
      Continue;
    end;
    for k := 0 to High(geo) do
      SameNum(name + '.' + geo[k], v.Arr[k], fill.Find(geo[k]));
    stops := fill.Arrays['stops'];
    n := Length(v.Stops) div 5;
    Inc(FCompared);
    if n <> stops.Count then
    begin
      Bad(Format('%s: %d stops, upstream %d', [name, n, stops.Count]));
      Continue;
    end;
    for k := 0 to n - 1 do
    begin
      stop := stops.Objects[k];
      SameNum(Format('%s.stop%d.offset', [name, k]), v.Stops[k * 5], stop.Find('offset'));
      Inc(FCompared);
      if not ParseCss(stop.Strings['color'], r, g, b, a) then
      begin
        Bad(name + ': a colour the test does not read: ' + stop.Strings['color']);
        Continue;
      end;
      if not (SameBits(v.Stops[k * 5 + 1], r) and SameBits(v.Stops[k * 5 + 2], g)
        and SameBits(v.Stops[k * 5 + 3], b) and SameBits(v.Stops[k * 5 + 4], a)) then
        Bad(Format('%s.stop%d %s,%s,%s,%s, upstream %s', [name, k, Txt(v.Stops[k * 5 + 1]),
          Txt(v.Stops[k * 5 + 2]), Txt(v.Stops[k * 5 + 3]), Txt(v.Stops[k * 5 + 4]),
          stop.Strings['color']]));
    end;
    { THE FRAME draws it: the bar's fill a gradient of the same geometry and
      offsets }
    if FrameEl(s, row, carBar, el) then
    begin
      Inc(FCompared);
      if el.Style.FillGradient.Kind = cgkNone then
        Bad(name + ': the frame draws no gradient')
      else if Length(el.Style.FillGradient.Stops) <> n then
        Bad(Format('%s: the frame draws %d stops, upstream %d', [name,
          Length(el.Style.FillGradient.Stops), n]))
      else
      begin
        SameNum(name + ' drawn x', el.Style.FillGradient.X, fill.Find('x'));
        SameNum(name + ' drawn y', el.Style.FillGradient.Y, fill.Find('y'));
        for k := 0 to n - 1 do
          SameNum(Format('%s drawn stop%d.offset', [name, k]), el.Style.FillGradient.Stops[k].Offset,
            stops.Objects[k].Find('offset'));
      end;
    end;
  end;
end;

{ [R2-H] every shown label of a data item: its opacity as the frame draws
  it, against upstream's (the text's style.opacity) }
procedure TAdvChartAnimUpdate3OracleTest.ProbeLabels(ARec: TJSONObject);
var
  i, k, s, idx, slash: Integer;
  name: string;
  leaf: TJSONObject;
  l: TTyPaintList;
  e: PTyChartElement;
  found: Boolean;
begin
  l := FChart.Frame;
  if (l = nil) or (l.Count = 0) then l := FChart.List;
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'lb' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    idx := StrToInt(Copy(name, slash + 1, MaxInt));
    leaf := TJSONObject(ARec.Items[i]);
    found := False;
    if l <> nil then
      for k := 0 to l.Count - 1 do
      begin
        e := l.Ref(k);
        if (e^.Anim.Role <> carLabel) or (e^.Caption.FontSizeLogical <= 0) or e^.Ignore
          or (e^.Datum.SeriesIndex <> s) or (e^.Datum.DataIndex <> idx) then Continue;
        found := True;
        { at opacity 0 the frame keeps the label inkless (no text): drawn
          at nothing }
        if (e^.Caption.Text = '') and (Length(e^.Caption.RtPieces) = 0) then
          NearNum(name + ' opacity', 0, leaf.Find('op'), 1e-9)
        else
          NearNum(name + ' opacity', e^.Style.Alpha, leaf.Find('op'), 1e-9);
        Break;
      end;
    Inc(FCompared);
    if not found then Bad(name + ': upstream draws the label, the frame has none');
  end;
end;

procedure TAdvChartAnimUpdate3OracleTest.CheckSample(const AProbes: TJSONArray;
  ARec: TJSONObject);
var i: Integer;
begin
  for i := 0 to AProbes.Count - 1 do
    if AProbes.Strings[i] = 'graph' then ProbeGraph(ARec)
    else if AProbes.Strings[i] = 'tree' then ProbeTree(ARec)
    else if AProbes.Strings[i] = 'pictorial' then ProbePictorial(ARec)
    else if AProbes.Strings[i] = 'state' then ProbeState(ARec)
    else if AProbes.Strings[i] = 'labels' then ProbeLabels(ARec)
    else Bad('a probe the test does not know: ' + AProbes.Strings[i]);
end;

procedure TAdvChartAnimUpdate3OracleTest.RunCase(ACase: TJSONObject);
var
  events: TJSONArray;
  ev: TJSONObject;
  j: Integer;
  t0, now_: Double;
  act: string;
begin
  FWhere := ACase.Strings['id'];
  FTol := 0;
  if (ACase.Find('ring') <> nil) and ACase.Booleans['ring'] then FTol := 1e-9;
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
      FNoPlace := (ACase.Find('placeFrom') <> nil) and (ACase.Find('placeFrom').JSONType = jtNumber)
        and (ev.Floats['t'] >= ACase.Floats['placeFrom']);
      FChart.AnimTick(now_);
      RenderNow;
      Inc(FSamples);
      CheckSample(ACase.Arrays['probes'], ev.Objects['rec']);
    end
    else if act = 'frame' then
    begin
      { a frame upstream runs and the fixture does not record }
      FChart.AnimTick(now_);
      RenderNow;
    end
    else if act = 'merge' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, False);
      RenderNow;
    end
    else if act = 'notMerge' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, True);
      RenderNow;
    end
    else if act = 'action' then
    begin
      { NO PAINT: an action's render returns without a flush, and a state
        it changed is applied in the next frame (echarts' _onframe), after
        that frame's step -- the sample's tick, then its paint }
      if FByMethod and (ev.Objects['action'].Get('type', '') = 'treeExpandAndCollapse') then
      begin
        FChart.TreeToggle(ev.Objects['action'].Get('seriesIndex', -1),
          ev.Objects['action'].Integers['dataIndex']);
        Inc(FToggles);
      end
      else
        FChart.DispatchAction(ev.Objects['action'].AsJSON);
    end
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartAnimUpdate3OracleTest.RunGroup(const AGroup: string; AMin: Integer);
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

procedure TAdvChartAnimUpdate3OracleTest.TestTheGraphUpdatesAsUpstream;
begin
  RunGroup('graph', 2000);
end;

procedure TAdvChartAnimUpdate3OracleTest.TestTheTreeExpandsAndCollapsesAsUpstream;
begin
  RunGroup('tree', 2000);
end;

procedure TAdvChartAnimUpdate3OracleTest.TestTheRadialLabelsFollowTheirNodesAsUpstream;
begin
  RunGroup('radial', 500);
end;

procedure TAdvChartAnimUpdate3OracleTest.TestAnItemsArraySymbolSizeAsUpstream;
begin
  RunGroup('pictorial', 40);
end;

procedure TAdvChartAnimUpdate3OracleTest.TestAStatesGradientTweensAsUpstream;
begin
  RunGroup('stateGrad', 300);
end;

{ [R2-H] a render while the enter's label fades run: a kept label is at
  its rest at once (useStyle strands the fade), a new one fades in }
procedure TAdvChartAnimUpdate3OracleTest.TestARenderEndsTheLabelsFadesAsUpstream;
begin
  RunGroup('labelFade', 60);
end;

{ [fin] TreeToggle -- the public method, and a node's click -- is the
  action's full update too: the tree cases again, every
  treeExpandAndCollapse through it }
procedure TAdvChartAnimUpdate3OracleTest.TestATreeToggleIsTheAction;
begin
  FByMethod := True;
  FToggles := 0;
  RunGroup('tree', 2000);
  AssertTrue('toggled through the method', FToggles >= 4);
end;

initialization
  RegisterTest(TAdvChartAnimUpdate3OracleTest);
end.
