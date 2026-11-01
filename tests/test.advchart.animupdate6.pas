unit test.advchart.animupdate6;
{$mode objfpc}{$H+}
{ THE UPDATE TWEENS OF THE SERIES THE PORT MOVED AT ONCE, HELD TO UPSTREAM
  [spec 242].

  tools/advchart-oracle/anim-update6.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock, a parallel's rows, a
  themeRiver's layers, a chord's pieces and ribbons and a lines series'
  lines after a merge: each kept one updateProps its shape from the old one
  to the new.

  This replays every case through the control and compares the shape each
  element is drawn with in the frame, and whether its tween is running. }
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
  TAu6Probe = class(TGfxProbe)
  public
    function Frame: TTyPaintList;
  end;

  TAdvChartAnimUpdate6OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAu6Probe;
    FRoot: TJSONData;
    FBad, FCompared, FSamples: Integer;
    FWhere, FReport: string;
    procedure Bad(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData); overload;
    procedure SameNum(const AWhat: string; AGot, AWant: Double); overload;
    function TwEl(ASeries, AKind, ARow: Integer; const AKey: string;
      out AEl: TTyChartElement): Boolean;
    procedure SameRunning(const AWhat: string; ASeries, AKind, ARow: Integer; AWant: TJSONObject);
    procedure SameCmds(const AWhat: string; const AGot, AWant: TTyPathCmdArray);
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
    procedure TestAParallelsRowsTweenAsUpstream;
    procedure TestAThemeRiversLayersTweenAsUpstream;
    procedure TestAChordsPiecesAndRibbonsTweenAsUpstream;
    procedure TestALinesSeriesLinesTweenAsUpstream;
  end;

implementation

function TAu6Probe.Frame: TTyPaintList;
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
procedure Au6Fns(AData: TJSONData);
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
      Au6Fns(child);
  end;
end;

{ ==================== the oracle ==================== }

function TAdvChartAnimUpdate6OracleTest.HIdx100(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  { idx => idx * 100 }
  Result := ADataIndex * 100;
end;

procedure TAdvChartAnimUpdate6OracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-anim-update6.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-anim-update6.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  Au6Fns(FRoot);
  TyChartRegisterAnimDelay('idx*100', @HIdx100);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartAnimUpdate6OracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  TyChartUnregisterAnimDelay('idx*100');
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAnimUpdate6OracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAnimUpdate6OracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  SameNum(AWhat, AGot, WantNum(AWant));
end;

procedure TAdvChartAnimUpdate6OracleTest.SameNum(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not SameBits(AGot, AWant) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
end;

{ the frame's element of a tween: by its key, else its row }
function TAdvChartAnimUpdate6OracleTest.TwEl(ASeries, AKind, ARow: Integer;
  const AKey: string; out AEl: TTyChartElement): Boolean;
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
    if (e.Anim.TwKind <> AKind) or (e.Anim.Series <> ASeries) then Continue;
    if (AKey <> '') and (e.Anim.TwKey <> AKey) then Continue;
    if (AKey = '') and (e.Anim.TwRow <> ARow) then Continue;
    { a lines row: its line }
    if (AKind = 5) and (e.Anim.Role <> carLinesLine) then Continue;
    AEl := e;
    Exit(True);
  end;
end;

{ upstream's clips on the element against the tween's proxy running }
procedure TAdvChartAnimUpdate6OracleTest.SameRunning(const AWhat: string;
  ASeries, AKind, ARow: Integer; AWant: TJSONObject);
var
  p: TTyChartAnimProxy;
  running: Boolean;
begin
  p := FChart.AnimFindProxy(ASeries, ARow, 'tw' + IntToStr(AKind));
  running := (p <> nil) and (p.AnimatorCount > 0);
  Inc(FCompared);
  if running <> (AWant.Integers['n'] > 0) then
    Bad(Format('%s: tween running %s, upstream %d clips', [AWhat, BoolToStr(running, True),
      AWant.Integers['n']]));
end;

procedure TAdvChartAnimUpdate6OracleTest.SameCmds(const AWhat: string;
  const AGot, AWant: TTyPathCmdArray);
var i: Integer;
begin
  Inc(FCompared);
  if Length(AGot) <> Length(AWant) then
  begin
    Bad(Format('%s: %d commands, %d expected', [AWhat, Length(AGot), Length(AWant)]));
    Exit;
  end;
  for i := 0 to High(AGot) do
  begin
    SameNum(Format('%s cmd %d x', [AWhat, i]), AGot[i].X, AWant[i].X);
    SameNum(Format('%s cmd %d y', [AWhat, i]), AGot[i].Y, AWant[i].Y);
    SameNum(Format('%s cmd %d x1', [AWhat, i]), AGot[i].X1, AWant[i].X1);
    SameNum(Format('%s cmd %d y1', [AWhat, i]), AGot[i].Y1, AWant[i].Y1);
  end;
end;

procedure TAdvChartAnimUpdate6OracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TAu6Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartAnimUpdate6OracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartAnimUpdate6OracleTest.CheckSample(ARec: TJSONObject);
var
  i, k, s, slash, idx, n: Integer;
  name, pre, rest: string;
  leaf: TJSONObject;
  el: TTyChartElement;
  v, v2: TTyDoubleArray;
  pts, b, t: TTyPointFArray;
  want: TTyChartShape;
  sec: TTyPolarSector;
  path: TTyZrPath;
  cmds: TTyPathCmdArray;
  gone: TJSONArray;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    slash := Pos('/', name);
    pre := Copy(name, 1, 2);
    if pre = 'pa' then
    begin
      s := StrToInt(Copy(name, 4, slash - 4));
      pre := 'par';
    end
    else
      s := StrToInt(Copy(name, 3, slash - 3));
    rest := Copy(name, slash + 1, MaxInt);
    if pre = 'ch' then
    begin
      { the pieces and ribbons fading out }
      gone := ARec.Arrays[name];
      n := 0;
      for k := 0 to FChart.AnimGhostCount - 1 do
        if (FChart.AnimGhostAt(k) <> nil) and (FChart.AnimGhostAt(k).Series = s)
          and (Copy(FChart.AnimGhostAt(k).Role, 1, 5) = 'chord') then Inc(n);
      Inc(FCompared);
      if n <> gone.Count then Bad(Format('%s: %d fading, upstream %d', [name, n, gone.Count]));
      Continue;
    end;
    leaf := TJSONObject(ARec.Items[i]);
    if pre = 'par' then
    begin
      idx := StrToInt(rest);
      if not TwEl(s, 1, idx, '', el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      v := Nums(leaf.Arrays['pts']);
      SetLength(pts, Length(v) div 2);
      for k := 0 to High(pts) do pts[k] := TyPointF(v[2 * k], v[2 * k + 1]);
      want := TyParallelRowShape(pts, el.Anim.G[6]);
      SameNum(name + ' points', Length(el.Shape.Points), Length(want.Points));
      for k := 0 to Min(High(el.Shape.Points), High(want.Points)) do
      begin
        SameNum(Format('%s point %d x', [name, k]), el.Shape.Points[k].X, want.Points[k].X);
        SameNum(Format('%s point %d y', [name, k]), el.Shape.Points[k].Y, want.Points[k].Y);
      end;
      SameRunning(name, s, 1, idx, leaf);
    end
    else if pre = 'rv' then
    begin
      if not TwEl(s, 2, -1, rest, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      v := Nums(leaf.Arrays['pts']);
      v2 := Nums(leaf.Arrays['st']);
      SetLength(b, Length(v) div 2);
      SetLength(t, Length(v2) div 2);
      for k := 0 to High(b) do b[k] := TyPointF(v[2 * k], v[2 * k + 1]);
      for k := 0 to High(t) do t[k] := TyPointF(v2[2 * k], v2[2 * k + 1]);
      want := TyRiverLayerShape(b, t, el.Anim.G[4]);
      SameCmds(name, el.Shape.Cmds, want.Cmds);
      SameRunning(name, s, 2, el.Anim.TwRow, leaf);
    end
    else if pre = 'cp' then
    begin
      idx := StrToInt(rest);
      if not TwEl(s, 3, idx, '', el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      v := Nums(leaf.Arrays['sh']);
      sec.CX := v[0];
      sec.CY := v[1];
      sec.R0 := v[2];
      sec.R := v[3];
      sec.SA := v[4];
      sec.EA := v[5];
      sec.CW := el.Anim.G[2] <> 0;
      want := TyPolarSectorShape(sec, el.Anim.Pts, False);
      SameNum(name + ' cx', el.Shape.CX, want.CX);
      SameNum(name + ' cy', el.Shape.CY, want.CY);
      SameNum(name + ' r0', el.Shape.R0, want.R0);
      SameNum(name + ' r', el.Shape.R1, want.R1);
      SameNum(name + ' start', el.Shape.StartRad, want.StartRad);
      SameNum(name + ' end', el.Shape.EndRad, want.EndRad);
      SameRunning(name, s, 3, idx, leaf);
    end
    else if pre = 'ce' then
    begin
      idx := StrToInt(rest);
      if not TwEl(s, 4, idx, '', el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      v := Nums(leaf.Arrays['sh']);
      path := TyChordRibbonPathOf(v, el.Anim.G[2] <> 0);
      TyZrPathToCmds(path, cmds, pts);
      SameCmds(name, el.Shape.Cmds, cmds);
      SameRunning(name, s, 4, idx, leaf);
    end
    else if pre = 'ln' then
    begin
      idx := StrToInt(rest);
      if not TwEl(s, 5, idx, '', el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      v := Nums(leaf.Arrays['sh']);
      for k := 0 to 5 do SameNum(Format('%s shape %d', [name, k]), el.Anim.G[k], v[k]);
      SameRunning(name, s, 5, idx, leaf);
    end;
  end;
end;

procedure TAdvChartAnimUpdate6OracleTest.RunCase(ACase: TJSONObject);
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
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartAnimUpdate6OracleTest.RunGroup(const AGroup: string; AMin: Integer);
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

procedure TAdvChartAnimUpdate6OracleTest.TestAParallelsRowsTweenAsUpstream;
begin
  RunGroup('parallel', 100);
end;

procedure TAdvChartAnimUpdate6OracleTest.TestAThemeRiversLayersTweenAsUpstream;
begin
  RunGroup('river', 50);
end;

procedure TAdvChartAnimUpdate6OracleTest.TestAChordsPiecesAndRibbonsTweenAsUpstream;
begin
  RunGroup('chord', 50);
end;

procedure TAdvChartAnimUpdate6OracleTest.TestALinesSeriesLinesTweenAsUpstream;
begin
  RunGroup('lines', 50);
end;

initialization
  RegisterTest(TAdvChartAnimUpdate6OracleTest);
end.
