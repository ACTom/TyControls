unit test.advchart.animedges;
{$mode objfpc}{$H+}
{ THE ANIMATION EDGES THE PORT DID NOT FOLLOW, HELD TO UPSTREAM [spec 243b].

  tools/advchart-oracle/anim-edges.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock, the elements of each case
  (a candlestick's boxes, a funnel's pieces and labels, ...).

  This replays every case through the control and compares what each
  element is drawn with in the frame, and whether its animation is
  running. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.AnimView, tyControls.AdvanceChart.AnimOpt, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Parallel, tyControls.AdvanceChart.ThemeRiver,
     tyControls.AdvanceChart.Chord, tyControls.AdvanceChart.PolarBar,
     tyControls.AdvanceChart.ZrPath,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  TAeProbe = class(TGfxProbe)
  public
    function Frame: TTyPaintList;
  end;

  TAdvChartAnimEdgesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAeProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSamples: Integer;
    FWhere, FReport: string;
    procedure Bad(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData); overload;
    procedure SameNum(const AWhat: string; AGot, AWant: Double); overload;
    function RoleEl(ASeries, ARow: Integer; ARole: TTyChartAnimRole;
      out AEl: TTyChartElement): Boolean;
    procedure SameRun(const AWhat: string; AProxy: TTyChartAnimProxy; AWant: TJSONObject);
    function HIdx100(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    procedure CheckSample(ARec: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
    procedure RunGroup(const AGroup: string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestACandlesticksBoxesAsUpstream;
    procedure TestAFunnelsPiecesAndLabelsAsUpstream;
    procedure TestABarClippedPastThePlotAsUpstream;
    procedure TestTheMarkersAsUpstream;
    procedure TestEachSetOptionRendersAsUpstream;
    procedure TestBarsOnAPolarAsUpstream;
  end;

implementation

function TAeProbe.Frame: TTyPaintList;
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

function Nums(AArr: TJSONArray): TTyDoubleArray;
var i: Integer;
begin
  Result := nil;
  if AArr = nil then Exit;
  SetLength(Result, AArr.Count);
  for i := 0 to AArr.Count - 1 do Result[i] := WantNum(AArr.Items[i]);
end;

{ {"$fn": name} -> '@name', in place, everywhere }
procedure AeFns(AData: TJSONData);
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
      AeFns(child);
  end;
end;

{ ==================== the oracle ==================== }

function TAdvChartAnimEdgesOracleTest.HIdx100(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  { idx => idx * 100 }
  Result := ADataIndex * 100;
end;

procedure TAdvChartAnimEdgesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-anim-edges.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-anim-edges.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  AeFns(FRoot);
  TyChartRegisterAnimDelay('idx*100', @HIdx100);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartAnimEdgesOracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  TyChartUnregisterAnimDelay('idx*100');
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAnimEdgesOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAnimEdgesOracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  SameNum(AWhat, AGot, WantNum(AWant));
end;

procedure TAdvChartAnimEdgesOracleTest.SameNum(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not SameBits(AGot, AWant) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
end;

{ the frame's element of a role at a row }
function TAdvChartAnimEdgesOracleTest.RoleEl(ASeries, ARow: Integer;
  ARole: TTyChartAnimRole; out AEl: TTyChartElement): Boolean;
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
    if (e.Anim.Role <> ARole) or (e.Anim.Series <> ASeries) or (e.Anim.Index <> ARow) then Continue;
    AEl := e;
    Exit(True);
  end;
end;

{ a proxy's key, or the rest value where the proxy has none }
function PNumOr(P: TTyChartAnimProxy; const AKey: string; AOr: Double): Double;
begin
  if (P <> nil) and (P.GetAnimProp(AKey).Kind = avkNumber) then Result := P.Num(AKey)
  else Result := AOr;
end;

{ upstream's clips on the element against the proxy running }
procedure TAdvChartAnimEdgesOracleTest.SameRun(const AWhat: string;
  AProxy: TTyChartAnimProxy; AWant: TJSONObject);
var running: Boolean;
begin
  running := (AProxy <> nil) and (AProxy.AnimatorCount > 0);
  Inc(FCompared);
  if running <> (AWant.Integers['n'] > 0) then
    Bad(Format('%s: running %s, upstream %d clips', [AWhat, BoolToStr(running, True),
      AWant.Integers['n']]));
end;

procedure TAdvChartAnimEdgesOracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TAeProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartAnimEdgesOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartAnimEdgesOracleTest.CheckSample(ARec: TJSONObject);
var
  i, k, s, slash, idx: Integer;
  name, pre, rest: string;
  leaf: TJSONObject;
  el: TTyChartElement;
  v: TTyDoubleArray;
  p: TTyChartAnimProxy;
  got: TTyAnimValue;
  gone: TJSONArray;
  ops: TTyDoubleArray;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    slash := Pos('/', name);
    pre := Copy(name, 1, 2);
    s := StrToInt(Copy(name, 3, slash - 3));
    rest := Copy(name, slash + 1, MaxInt);
    idx := StrToIntDef(rest, -1);
    leaf := nil;
    if ARec.Items[i].JSONType = jtObject then leaf := TJSONObject(ARec.Items[i]);
    if pre = 'cd' then
    begin
      { the box's proxy holds upstream's eight points }
      v := Nums(leaf.Arrays['pts']);
      p := FChart.AnimFindProxy(s, idx, 'candle');
      if p = nil then
      begin
        Bad(name + ': no proxy');
        Continue;
      end;
      got := p.GetAnimProp('shape.points');
      SameNum(name + ' points', Length(got.Arr), Length(v));
      for k := 0 to Min(High(got.Arr), High(v)) do
        SameNum(Format('%s point %d', [name, k]), got.Arr[k], v[k]);
      SameRun(name, p, leaf);
      { a simple box: its one stroke in the frame, the highest to the lowest }
      if leaf.Booleans['simple'] then
      begin
        if not RoleEl(s, idx, carCandleWickHigh, el) then
          Bad(name + ': the simple box is not drawn')
        else
        begin
          SameNum(name + ' stroke points', Length(el.Shape.Points), 2);
          if Length(el.Shape.Points) = 2 then
          begin
            SameNum(name + ' stroke x0', el.Shape.Points[0].X, v[8]);
            SameNum(name + ' stroke y0', el.Shape.Points[0].Y, v[9]);
            SameNum(name + ' stroke x1', el.Shape.Points[1].X, v[12]);
            SameNum(name + ' stroke y1', el.Shape.Points[1].Y, v[13]);
          end;
        end;
      end;
    end
    else if pre = 'br' then
    begin
      { the bar's proxy holds upstream's rect; the element is ignored as
        upstream's }
      v := Nums(leaf.Arrays['sh']);
      p := FChart.AnimFindProxy(s, idx, 'bar');
      if not RoleEl(s, idx, carBar, el) then
      begin
        Bad(name + ': not in the list');
        Continue;
      end;
      Inc(FCompared);
      if el.Ignore <> leaf.Booleans['ig'] then
        Bad(Format('%s: ignore %s, upstream %s', [name, BoolToStr(el.Ignore, True),
          BoolToStr(leaf.Booleans['ig'], True)]));
      if p = nil then
      begin
        Bad(name + ': no proxy');
        Continue;
      end;
      SameNum(name + ' x', p.Num('shape.x'), v[0]);
      SameNum(name + ' y', p.Num('shape.y'), v[1]);
      SameNum(name + ' width', p.Num('shape.width'), v[2]);
      SameNum(name + ' height', p.Num('shape.height'), v[3]);
      SameRun(name, p, leaf);
    end
    else if pre = 'ml' then
    begin
      { a markLine's proxy: its ends and its percent }
      v := Nums(leaf.Arrays['sh']);
      p := FChart.AnimFindProxy(s, idx, 'markLine');
      if p = nil then
      begin
        Bad(name + ': no proxy');
        Continue;
      end;
      { an entering proxy holds the percent alone: the ends are the line's }
      if not RoleEl(s, idx, carMarkLine, el) then el := Default(TTyChartElement);
      SameNum(name + ' x1', PNumOr(p, 'shape.x1', el.Anim.G[0]), v[0]);
      SameNum(name + ' y1', PNumOr(p, 'shape.y1', el.Anim.G[1]), v[1]);
      SameNum(name + ' x2', PNumOr(p, 'shape.x2', el.Anim.G[2]), v[2]);
      SameNum(name + ' y2', PNumOr(p, 'shape.y2', el.Anim.G[3]), v[3]);
      SameNum(name + ' percent', PNumOr(p, 'shape.percent', 1), leaf.Find('pc'));
      SameRun(name, p, leaf);
    end
    else if pre = 'mk' then
    begin
      { a markPoint's proxy: its group's place and its path's scale }
      p := FChart.AnimFindProxy(s, idx, 'markPoint');
      if p = nil then
      begin
        Bad(name + ': no proxy');
        Continue;
      end;
      if not RoleEl(s, idx, carMarkPoint, el) then el := Default(TTyChartElement);
      SameNum(name + ' x', PNumOr(p, 'x', el.Anim.G[0]), leaf.Find('x'));
      SameNum(name + ' y', PNumOr(p, 'y', el.Anim.G[1]), leaf.Find('y'));
      SameNum(name + ' scaleX', PNumOr(p, 'scaleX', el.Anim.G[2]), leaf.Find('sx'));
      SameRun(name, p, leaf);
    end
    else if pre = 'po' then
    begin
      { a polar bar: its proxy's sector, the list's corners and its
        label's turn (the static picture: what updateStyle set) }
      v := Nums(leaf.Arrays['sh']);
      if not RoleEl(s, idx, carPolarBar, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      p := FChart.AnimFindProxy(s, idx, 'bar');
      SameNum(name + ' cx', PNumOr(p, 'shape.cx', el.Anim.G[0]), v[0]);
      SameNum(name + ' cy', PNumOr(p, 'shape.cy', el.Anim.G[1]), v[1]);
      SameNum(name + ' r0', PNumOr(p, 'shape.r0', el.Anim.G[2]), v[2]);
      SameNum(name + ' r', PNumOr(p, 'shape.r', el.Anim.G[3]), v[3]);
      SameNum(name + ' startAngle', PNumOr(p, 'shape.startAngle', el.Anim.G[4]), v[4]);
      SameNum(name + ' endAngle', PNumOr(p, 'shape.endAngle', el.Anim.G[5]), v[5]);
      Inc(FCompared);
      if (el.Anim.G[8] <> 0) <> (leaf.Strings['type'] = 'sausage') then
        Bad(Format('%s: sausage %s, upstream a %s', [name, BoolToStr(el.Anim.G[8] <> 0, True),
          leaf.Strings['type']]));
      if (leaf.Find('cr') is TJSONArray) and (leaf.Strings['type'] <> 'sausage') then
      begin
        v := Nums(leaf.Arrays['cr']);
        SameNum(name + ' corners', Length(el.Anim.Pts), Length(v));
        for k := 0 to Min(High(el.Anim.Pts), High(v)) do
          SameNum(Format('%s corner %d', [name, k]), el.Anim.Pts[k], v[k]);
      end;
      if not IsNull(leaf.Find('rot')) then
        SameNum(name + ' label turn', el.Caption.SecRot, leaf.Find('rot'));
      SameRun(name, p, leaf);
    end
    else if pre = 'gh' then
    begin
      { a bar view's leaving elements: the bar ghosts of the series, their
        opacities in order }
      gone := ARec.Arrays[name];
      SetLength(ops, 0);
      for k := 0 to FChart.AnimGhostCount - 1 do
      begin
        p := FChart.AnimGhostAt(k);
        if (p = nil) or p.Gone or (p.Series <> s) or (p.Role <> 'bar') then Continue;
      { a polar bar's ghost: the sector is a ghost as a rect is }
        SetLength(ops, Length(ops) + 1);
        ops[High(ops)] := p.Num('style.opacity');
      end;
      SameNum(name + ' count', Length(ops), gone.Count);
      for k := 0 to Min(High(ops), gone.Count - 1) do
        SameNum(Format('%s %d opacity', [name, k]), ops[k], gone.Objects[k].Find('op'));
    end
    else if pre = 'fn' then
    begin
      v := Nums(leaf.Arrays['pts']);
      if not RoleEl(s, idx, carFunnel, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      SameNum(name + ' points', Length(el.Shape.Points), 4);
      for k := 0 to Min(High(el.Shape.Points), 3) do
      begin
        SameNum(Format('%s point %d x', [name, k]), el.Shape.Points[k].X, v[2 * k]);
        SameNum(Format('%s point %d y', [name, k]), el.Shape.Points[k].Y, v[2 * k + 1]);
      end;
      SameNum(name + ' opacity', el.Style.Alpha, leaf.Find('op'));
      SameRun(name, FChart.AnimFindProxy(s, idx, 'funnel'), leaf);
    end
    else if pre = 'fl' then
    begin
      if not RoleEl(s, idx, carLabel, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      SameNum(name + ' x', el.Caption.X, leaf.Find('x'));
      SameNum(name + ' y', el.Caption.Y, leaf.Find('y'));
      SameRun(name, FChart.AnimFindProxy(s, idx, 'label'), leaf);
    end
    else
      Bad(name + ': a probe the suite does not know');
  end;
end;

procedure TAdvChartAnimEdgesOracleTest.RunCase(ACase: TJSONObject);
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
      CheckSample(ev.Objects['rec']);
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
    else if act = 'mergeq' then
      { the next setOption comes before any paint }
      FChart.SetOption(ev.Objects['option'].AsJSON, False)
    else if act = 'set' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, True);
      RenderNow;
    end
    else if act = 'act' then
    begin
      FChart.DispatchAction(ev.Objects['action'].AsJSON);
      RenderNow;
    end
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartAnimEdgesOracleTest.RunGroup(const AGroup: string; AMin: Integer);
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
        on E: Exception do Bad(cases.Objects[i].Strings['id'] + ' raised ' + E.ClassName + ': ' + E.Message);
      end;
      Inc(n);
    end;
  AssertTrue('cases run', n > 0);
  if FBad > 0 then
    Fail(Format('%s: %d of %d comparisons over %d samples differ:%s',
      [AGroup, FBad, FCompared, FSamples, FReport]));
  AssertTrue('compared', FCompared >= AMin);
end;

procedure TAdvChartAnimEdgesOracleTest.TestACandlesticksBoxesAsUpstream;
begin
  RunGroup('candle', 300);
end;

procedure TAdvChartAnimEdgesOracleTest.TestAFunnelsPiecesAndLabelsAsUpstream;
begin
  RunGroup('funnel', 300);
end;

procedure TAdvChartAnimEdgesOracleTest.TestABarClippedPastThePlotAsUpstream;
begin
  RunGroup('bar', 200);
end;

procedure TAdvChartAnimEdgesOracleTest.TestTheMarkersAsUpstream;
begin
  RunGroup('mark', 150);
end;

procedure TAdvChartAnimEdgesOracleTest.TestEachSetOptionRendersAsUpstream;
begin
  RunGroup('setopt', 300);
end;

procedure TAdvChartAnimEdgesOracleTest.TestBarsOnAPolarAsUpstream;
begin
  RunGroup('polar', 600);
end;

initialization
  RegisterTest(TAdvChartAnimEdgesOracleTest);
end.
