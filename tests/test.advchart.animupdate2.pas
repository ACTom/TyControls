unit test.advchart.animupdate2;
{$mode objfpc}{$H+}
{ THE UPDATE TRANSITIONS THE EARLIER BATCHES LEFT OUT, HELD TO UPSTREAM [F3b].

  tools/advchart-oracle/anim-update2.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock, what each case's probes name:

    step   a step line's update: the stepped points ('start', 'middle',
           'end', a vertical base axis, connectNulls, stacked areas, a
           second update in flight), its __points and the symbols that
           follow them;
    axis   the cartesian axes' groupTransition of the axis name, the minor
           ticks, the minor split lines and the split areas, beside the line,
           ticks, labels and split lines;
    pictorial  a pictorial bar's enter on its item's model (the data item's
           duration, easing and delay), a repeated glyph's turn from 0, the
           symbolClip clip.

  This replays every case through the control and compares, bit for bit,
  the proxies the control animates. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Anim,
     tyControls.AdvChart.AnimView,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  TAdvChartAnimUpdate2OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSamples: Integer;
    FWhere, FReport: string;
    procedure Bad(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameArr(const AWhat: string; const AGot: TTyAnimValue; AWant: TJSONData);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    procedure ProbeLine(ARec: TJSONObject);
    procedure ProbeAxis(ARec: TJSONObject);
    procedure ProbePictorial(ARec, ALast: TJSONObject);
    procedure CheckSample(const AProbes: TJSONArray; ARec, ALast: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
    procedure RunGroup(const AGroup: string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheStepLinesUpdateAsUpstream;
    procedure TestTheAxesGroupTransitionAsUpstream;
    procedure TestThePictorialGlyphsEnterAsUpstream;
  end;

implementation

{ ==================== helpers ==================== }

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

{ ==================== the oracle ==================== }

procedure TAdvChartAnimUpdate2OracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-anim-update2.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-anim-update2.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartAnimUpdate2OracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAnimUpdate2OracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAnimUpdate2OracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if IsNull(AWant) then want := NaN else want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartAnimUpdate2OracleTest.SameArr(const AWhat: string;
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

procedure TAdvChartAnimUpdate2OracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TGfxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartAnimUpdate2OracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ ---- the line probe: the polyline's proxy, the area's, the symbols ---- }
procedure TAdvChartAnimUpdate2OracleTest.ProbeLine(ARec: TJSONObject);
var
  s, i, row, nSym: Integer;
  key, name: string;
  poly, area, sym: TTyChartAnimProxy;
  d: TJSONData;
  vx, vy: TTyAnimValue;
begin
  for s := 0 to 9 do
  begin
    key := 'line' + IntToStr(s);
    if ARec.Find(key + '/points') = nil then Continue;
    poly := FChart.AnimFindProxy(s, -1, 'linePoly');
    { a polyline that moves, or a proxy the port still holds: the same
      points }
    if (ARec.Integers[key + '/n'] > 0) and (poly = nil) then
      Bad(key + ': upstream tweens the polyline, the port has no proxy')
    else if poly <> nil then
    begin
      SameArr(key + '/points', poly.GetAnimProp('shape.points'), ARec.Find(key + '/points'));
      d := ARec.Find(key + '/__points');
      if d <> nil then SameArr(key + '/__points', poly.GetAnimProp('shape.__points'), d)
      else if poly.GetAnimProp('shape.__points').Kind <> avkNull then
        Bad(key + ': __points of its own, upstream none');
    end;
    if ARec.Find(key + '/stackedOnPoints') <> nil then
    begin
      area := FChart.AnimFindProxy(s, -1, 'lineArea');
      if (ARec.Integers[key + '/areaN'] > 0) and (area = nil) then
        Bad(key + ': upstream tweens the area, the port has no proxy')
      else if area <> nil then
        SameArr(key + '/stackedOnPoints', area.GetAnimProp('shape.stackedOnPoints'),
          ARec.Find(key + '/stackedOnPoints'));
    end;
    { the symbols that follow (a proxy with its group's place) }
    if (poly = nil) or (ARec.Integers[key + '/n'] = 0) then Continue;
    nSym := 0;
    for i := 0 to ARec.Count - 1 do
    begin
      name := ARec.Names[i];
      if Copy(name, 1, Length(key) + 4) <> key + '/sym' then Continue;
      row := StrToInt(Copy(name, Length(key) + 5, MaxInt));
      sym := FChart.AnimFindProxy(s, row, 'lineSymbol');
      if sym = nil then Continue;
      vx := sym.GetAnimProp('x');
      vy := sym.GetAnimProp('y');
      if (vx.Kind <> avkNumber) or (vy.Kind <> avkNumber) then Continue;
      SameNum(name + '.x', vx.Num, ARec.Arrays[name].Items[0]);
      SameNum(name + '.y', vy.Num, ARec.Arrays[name].Items[1]);
      Inc(nSym);
    end;
    if nSym = 0 then Bad(key + ': no symbol follows');
  end;
end;

{ ---- the axis probe: every leaf the port models, by anid ---- }
procedure TAdvChartAnimUpdate2OracleTest.ProbeAxis(ARec: TJSONObject);
var
  i, slash: Integer;
  name, axKey, anid: string;
  leaf: TJSONObject;
  p: TTyChartAnimProxy;

  function Modelled(const A: string): Boolean;
  begin
    Result := (A = 'line') or (A = 'name') or (Copy(A, 1, 6) = 'ticks_')
      or (Copy(A, 1, 6) = 'label_') or (Copy(A, 1, 5) = 'line_')
      or (Copy(A, 1, 11) = 'minorticks_') or (Copy(A, 1, 11) = 'minor_line_')
      or (Copy(A, 1, 5) = 'area_');
  end;

  procedure Key(const AKey: string);
  begin
    SameNum(name + '.' + AKey, p.Num(AKey), leaf.Find(AKey));
  end;

begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 5) <> 'axis:' then Continue;
    slash := Pos('/', name);
    axKey := Copy(name, 6, slash - 6);
    anid := Copy(name, slash + 1, MaxInt);
    if not Modelled(anid) then Continue;
    leaf := TJSONObject(ARec.Items[i]);
    p := FChart.AnimAxisProxy(axKey, anid);
    if p = nil then
    begin
      if leaf.Integers['n'] > 0 then Bad(name + ': upstream tweens it, the port has no proxy');
      Continue;
    end;
    if (anid = 'name') or (Copy(anid, 1, 6) = 'label_') then
    begin
      Key('x');
      Key('y');
      Key('rotation');
    end
    else if Copy(anid, 1, 5) = 'area_' then
    begin
      Key('shape.x');
      Key('shape.y');
      Key('shape.width');
      Key('shape.height');
    end
    else
    begin
      Key('shape.x1');
      Key('shape.y1');
      Key('shape.x2');
      Key('shape.y2');
    end;
    Inc(FCompared);
    if (p.AnimatorCount > 0) <> (leaf.Integers['n'] > 0) then
      Bad(Format('%s: %d animators, upstream %d', [name, p.AnimatorCount, leaf.Integers['n']]));
  end;
end;

{ ---- the pictorial probe: each glyph's proxy, the clip's ---- }
procedure TAdvChartAnimUpdate2OracleTest.ProbePictorial(ARec, ALast: TJSONObject);
var
  i, s, row, colon, slash: Integer;
  name, glyph: string;
  leaf, last: TJSONObject;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 4) <> 'pict' then Continue;
    colon := Pos(':', name);
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 5, colon - 5));
    row := StrToInt(Copy(name, colon + 1, slash - colon - 1));
    glyph := Copy(name, slash + 1, MaxInt);
    leaf := TJSONObject(ARec.Items[i]);
    if glyph = 'clip' then p := FChart.AnimFindProxy(s, row, 'pclip')
    else p := FChart.AnimFindProxy(s, row, 'pglyph' + glyph);
    if p = nil then
    begin
      if leaf.Integers['n'] > 0 then Bad(name + ': upstream animates it, the port has no proxy');
      Continue;
    end;
    if glyph = 'clip' then
    begin
      if p.GetAnimProp('shape.width').Kind = avkNumber then
        SameNum(name + '.width', p.Num('shape.width'), leaf.Find('shape.width'))
      else
        SameNum(name + '.height', p.Num('shape.height'), leaf.Find('shape.height'));
      Continue;
    end;
    SameNum(name + '.scaleX', p.Num('scaleX'), leaf.Find('scaleX'));
    SameNum(name + '.scaleY', p.Num('scaleY'), leaf.Find('scaleY'));
    v := p.GetAnimProp('rotation');
    if v.Kind = avkNumber then SameNum(name + '.rotation', v.Num, leaf.Find('rotation'))
    else
    begin
      { a glyph whose turn moves upstream must have one }
      last := nil;
      if ALast <> nil then last := TJSONObject(ALast.Find(name));
      Inc(FCompared);
      if (last <> nil) and (last.Strings['rotation'] <> leaf.Strings['rotation']) then
        Bad(name + ': upstream turns it, the port does not');
    end;
  end;
end;

procedure TAdvChartAnimUpdate2OracleTest.CheckSample(const AProbes: TJSONArray;
  ARec, ALast: TJSONObject);
var i: Integer;
begin
  for i := 0 to AProbes.Count - 1 do
    if AProbes.Strings[i] = 'pictorial' then ProbePictorial(ARec, ALast)
    else if AProbes.Strings[i] = 'line' then ProbeLine(ARec)
    else if AProbes.Strings[i] = 'axis' then ProbeAxis(ARec)
    else Bad('a probe the test does not know: ' + AProbes.Strings[i]);
end;

procedure TAdvChartAnimUpdate2OracleTest.RunCase(ACase: TJSONObject);
var
  events: TJSONArray;
  ev: TJSONObject;
  j: Integer;
  t0, now_: Double;
  act: string;
  lastRec: TJSONObject;
begin
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  t0 := TJSONObject(FRoot).Objects['clock'].Floats['T0'];
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := t0;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
  events := ACase.Arrays['events'];
  { the last sample's record: where each glyph rests }
  lastRec := nil;
  for j := events.Count - 1 downto 0 do
    if events.Objects[j].Strings['do'] = 'sample' then
    begin
      lastRec := events.Objects[j].Objects['rec'];
      Break;
    end;
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
      CheckSample(ACase.Arrays['probes'], ev.Objects['rec'], lastRec);
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
      FChart.DispatchAction(ev.Objects['action'].AsJSON);
      RenderNow;
    end
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartAnimUpdate2OracleTest.RunGroup(const AGroup: string; AMin: Integer);
var
  cases: TJSONArray;
  i, n: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  n := 0;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['group'] = AGroup then
    begin
      RunCase(cases.Objects[i]);
      Inc(n);
    end;
  AssertTrue('cases run', n > 0);
  if FBad > 0 then
    Fail(Format('%s: %d of %d comparisons differ from upstream:%s',
      [AGroup, FBad, FCompared, FReport]));
  AssertTrue(Format('%s: comparisons made (%d)', [AGroup, FCompared]), FCompared >= AMin);
end;

procedure TAdvChartAnimUpdate2OracleTest.TestTheStepLinesUpdateAsUpstream;
begin
  RunGroup('step', 1000);
end;

procedure TAdvChartAnimUpdate2OracleTest.TestTheAxesGroupTransitionAsUpstream;
begin
  RunGroup('axis', 2000);
end;

procedure TAdvChartAnimUpdate2OracleTest.TestThePictorialGlyphsEnterAsUpstream;
begin
  RunGroup('pictorial', 500);
end;

initialization
  RegisterTest(TAdvChartAnimUpdate2OracleTest);
end.
