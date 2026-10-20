unit test.advchart.animengine2;
{$mode objfpc}{$H+}
{ GRADIENTS IN A TWEEN AND THE PAUSE, HELD TO UPSTREAM [F3b].

  tools/advchart-oracle/anim-engine2.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock:

    gradients   custom rects whose fill (and a stroke) go gradient to
                gradient under transition ['style']: linear to linear with
                the stops two to two, two to three, three to two (the target
                padded), radial to radial with global, a linear to a radial,
                a colour to a gradient and back (discrete: a jump); named
                colours and 'transparent' in the stops; graphic keyframes
                through three linear gradients with a keyframe easing, a
                looping radial, a gradient to a colour keyframe;
    the pause   the chart's animation paused and resumed (a second pause
                and a resume while running do nothing), a merge during a
                pause whose flush steps every clip once (a series-only
                merge's too); an element's
                animator paused and resumed, a loop's across its restart.

  This replays it through the control bit for bit -- the custom series'
  renderItem a Pascal transcription that reads the oracle's gradient table. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.GfxEl, tyControls.AdvanceChart.Graphic,
     tyControls.AdvanceChart.Custom,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  { the renderItem of anim-engine2.js, transcribed }
  TAe2Mirror = class
  public
    Grads: TJSONArray;
    function GradItem(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  TAdvChartAnimEngine2OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    FRoot: TJSONData;
    FMirror: TAe2Mirror;
    FBad, FCompared, FSamples: Integer;
    FWhere, FReport: string;
    procedure Bad(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStyle(const AWhat: string; AGot, AWant: TJSONData);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    function Elements: TStringList;
    function ElementOf(const AId: string): TTyGfxEl;
    procedure CheckSnap(AEl: TTyGfxEl; ASnap: TJSONObject);
    procedure CheckSample(AEls: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
    procedure RunCaseId(const AId: string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGradientTransitionsAreUpstreams;
    procedure TestTheGradientKeyframesAreUpstreams;
    procedure TestThePauseOfTheChartIsUpstreams;
    procedure TestThePauseOfAnAnimatorIsUpstreams;
    procedure TestASeriesMergeWhilePausedStepsTheGraphic;
  end;

  { What the fixture does not reach. }
  TAdvChartAnimEngine2Test = class(TTestCase)
  published
    procedure TestADiscreteGradientWritesTheObjectItWas;
    procedure TestAGradientIsNeverAdditive;
    procedure TestAPausedDriverStepsOnlyWhenAsked;
    procedure TestAPausedChartTicksNothing;
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

function IsHex(AData: TJSONData): Boolean;
var s: string; i: Integer;
begin
  Result := False;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  s := AData.AsString;
  if Length(s) <> 16 then Exit;
  for i := 1 to 16 do
    if not (s[i] in ['0'..'9', 'a'..'f']) then Exit;
  Result := True;
end;

function Num(A: Double): TJSONFloatNumber;
begin
  Result := TJSONFloatNumber.Create(A);
end;

{ ==================== the mirror ==================== }

function TAe2Mirror.GradItem(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  o, st, ua: TJSONObject;
  k, ks: Integer;
  d: Double;
begin
  k := Round(AApi.Value(2));
  ks := Round(AApi.Value(3));
  d := AApi.Value(4);
  o := TJSONObject(GetJSON('{"type": "rect", "shape": {"width": 60, "height": 40}, "transition": ["style"]}'));
  o.Add('x', Num(AApi.Value(0)));
  o.Add('y', Num(AApi.Value(1)));
  st := TJSONObject.Create;
  st.Add('fill', Grads.Items[k].Clone);
  if ks >= 0 then
  begin
    st.Add('stroke', Grads.Items[ks].Clone);
    st.Add('lineWidth', 4);
  end;
  o.Add('style', st);
  if d > 0 then
  begin
    ua := TJSONObject.Create;
    ua.Add('duration', Num(d));
    ua.Add('easing', 'linear');
    o.Add('updateAnimation', ua);
  end;
  if AParams.DataIndex < 0 then ;
  Result := o;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartAnimEngine2OracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-anim-engine2.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-anim-engine2.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FMirror := TAe2Mirror.Create;
  FMirror.Grads := TJSONObject(FRoot).Arrays['grads'];
  TyChartRegisterRenderItem('gradItem', @FMirror.GradItem);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartAnimEngine2OracleTest.TearDown;
begin
  TyChartClearRenderItems;
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FMirror);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAnimEngine2OracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAnimEngine2OracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if IsNull(AWant) then want := NaN else want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

{ a style value as the element holds it (the JSON the painter reads)
  against upstream's record: a string as it is, a gradient field by field }
procedure TAdvChartAnimEngine2OracleTest.SameStyle(const AWhat: string; AGot,
  AWant: TJSONData);
var
  w, g, gs: TJSONObject;
  ws, gst: TJSONArray;
  i: Integer;
  d: TJSONData;
  t: string;

  function GotNum(const AName: string): Double;
  var x: TJSONData;
  begin
    x := g.Find(AName);
    if IsNull(x) then Result := NaN else Result := x.AsFloat;
  end;

begin
  Inc(FCompared);
  if AWant.JSONType = jtString then
  begin
    if IsNull(AGot) or (AGot.JSONType <> jtString) then
      Bad(AWhat + ': not the text ' + AWant.AsString)
    else if AGot.AsString <> AWant.AsString then
      Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot.AsString, AWant.AsString]));
    Exit;
  end;
  w := TJSONObject(AWant);
  if not (AGot is TJSONObject) then
  begin
    Bad(AWhat + ': no gradient, upstream ' + w.AsJSON);
    Exit;
  end;
  g := TJSONObject(AGot);
  d := g.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then t := d.AsString else t := '';
  if t <> w.Strings['type'] then Bad(Format('%s type %s, upstream %s', [AWhat, t, w.Strings['type']]));
  SameNum(AWhat + '.x', GotNum('x'), w.Find('x'));
  SameNum(AWhat + '.y', GotNum('y'), w.Find('y'));
  if w.Find('r') <> nil then SameNum(AWhat + '.r', GotNum('r'), w.Find('r'))
  else
  begin
    SameNum(AWhat + '.x2', GotNum('x2'), w.Find('x2'));
    SameNum(AWhat + '.y2', GotNum('y2'), w.Find('y2'));
  end;
  Inc(FCompared);
  d := g.Find('global');
  if IsNull(w.Find('global')) then
  begin
    if (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean then Bad(AWhat + ': global, upstream none');
  end
  else if IsNull(d) or (d.JSONType <> jtBoolean) or (d.AsBoolean <> w.Booleans['global']) then
    Bad(AWhat + ': global is not ' + w.Find('global').AsJSON);
  ws := w.Arrays['stops'];
  d := g.Find('colorStops');
  if not (d is TJSONArray) then
  begin
    Bad(AWhat + ': no colorStops');
    Exit;
  end;
  gst := TJSONArray(d);
  Inc(FCompared);
  if gst.Count <> ws.Count then
    Bad(Format('%s: %d stops, upstream %d', [AWhat, gst.Count, ws.Count]));
  for i := 0 to Min(gst.Count, ws.Count) - 1 do
  begin
    gs := gst.Objects[i];
    if IsNull(gs.Find('offset')) then SameNum(Format('%s.stop%d.offset', [AWhat, i]), NaN, ws.Arrays[i].Items[0])
    else SameNum(Format('%s.stop%d.offset', [AWhat, i]), gs.Floats['offset'], ws.Arrays[i].Items[0]);
    Inc(FCompared);
    if gs.Get('color', '') <> ws.Arrays[i].Strings[1] then
      Bad(Format('%s.stop%d.color "%s", upstream "%s"', [AWhat, i, gs.Get('color', ''),
        ws.Arrays[i].Strings[1]]));
  end;
end;

procedure TAdvChartAnimEngine2OracleTest.NewChart(AW, AH: Integer);
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

procedure TAdvChartAnimEngine2OracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ every element by the oracle's key: a graphic element's id, a custom root
  's<series>:<raw>' }
function TAdvChartAnimEngine2OracleTest.Elements: TStringList;
var
  list: TTyGfxElArray;
  i, s: Integer;
  view: TTyCustomView;
begin
  Result := TStringList.Create;
  if FChart.GraphicView <> nil then
  begin
    list := nil;
    TyGfxTraverse(FChart.GraphicView.Root, list);
    for i := 0 to High(list) do Result.AddObject(TyGfxIdText(list[i].Id), list[i]);
  end;
  for s := 0 to 9 do
  begin
    view := FChart.CustomView(s);
    if view = nil then Continue;
    for i := 0 to High(view.Root.Children) do
      Result.AddObject('s' + IntToStr(s) + ':' + IntToStr(view.RawOfRoot(view.Root.Children[i])),
        view.Root.Children[i]);
  end;
end;

function TAdvChartAnimEngine2OracleTest.ElementOf(const AId: string): TTyGfxEl;
var
  got: TStringList;
  i: Integer;
begin
  Result := nil;
  got := Elements;
  try
    i := got.IndexOf(AId);
    if i >= 0 then Result := TTyGfxEl(got.Objects[i]);
  finally
    got.Free;
  end;
end;

procedure TAdvChartAnimEngine2OracleTest.CheckSnap(AEl: TTyGfxEl; ASnap: TJSONObject);
var
  i: Integer;
  key: string;
  d: TJSONData;
  v: TTyAnimValue;
begin
  for i := 0 to ASnap.Count - 1 do
  begin
    key := ASnap.Names[i];
    d := ASnap.Items[i];
    if key = 'n' then
    begin
      Inc(FCompared);
      if AEl.AnimatorCount <> d.AsInteger then
        Bad(Format('animators %d, upstream %d', [AEl.AnimatorCount, d.AsInteger]));
    end
    else if Copy(key, 1, 6) = 'style.' then
    begin
      if Copy(key, 7, MaxInt) = 'opacity' then
      begin
        v := AEl.StyleValue('opacity');
        if v.Kind <> avkNumber then Bad('no opacity') else SameNum(key, v.Num, d);
      end
      else
        SameStyle(key, AEl.Style.Find(Copy(key, 7, MaxInt)), d);
    end
    else
    begin
      v := AEl.GetAnimProp(key);
      if v.Kind <> avkNumber then Bad(key + ': no number')
      else SameNum(key, v.Num, d);
    end;
  end;
end;

procedure TAdvChartAnimEngine2OracleTest.CheckSample(AEls: TJSONObject);
var
  got: TStringList;
  k, idx: Integer;
  was: string;
begin
  was := FWhere;
  got := Elements;
  try
    Inc(FCompared);
    if got.Count <> AEls.Count then
      Bad(Format('%d elements, upstream %d', [got.Count, AEls.Count]));
    for k := 0 to AEls.Count - 1 do
    begin
      idx := got.IndexOf(AEls.Names[k]);
      if idx < 0 then
      begin
        Bad('missing ' + AEls.Names[k]);
        Continue;
      end;
      FWhere := was + ' ' + AEls.Names[k];
      CheckSnap(TTyGfxEl(got.Objects[idx]), TJSONObject(AEls.Items[k]));
    end;
  finally
    got.Free;
    FWhere := was;
  end;
end;

procedure TAdvChartAnimEngine2OracleTest.RunCase(ACase: TJSONObject);
var
  events: TJSONArray;
  ev: TJSONObject;
  j: Integer;
  t0, now_: Double;
  act: string;
  el: TTyGfxEl;
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
      Inc(FSamples);
      CheckSample(ev.Objects['els']);
    end
    else if act = 'merge' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, False);
      RenderNow;
    end
    else if act = 'pause' then FChart.AnimPause
    else if act = 'resume' then FChart.AnimResume
    else if (act = 'pauseAnimator') or (act = 'resumeAnimator') then
    begin
      el := ElementOf(ev.Strings['id']);
      if (el = nil) or (ev.Integers['k'] >= el.AnimatorCount) then
        Bad('no animator ' + IntToStr(ev.Integers['k']) + ' on ' + ev.Strings['id'])
      else if act = 'pauseAnimator' then el.AnimatorAt(ev.Integers['k']).Pause
      else el.AnimatorAt(ev.Integers['k']).Resume;
    end
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartAnimEngine2OracleTest.RunCaseId(const AId: string; AMin: Integer);
var
  cases: TJSONArray;
  i, n: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  n := 0;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then
    begin
      RunCase(cases.Objects[i]);
      Inc(n);
    end;
  AssertEquals('the case is in the fixture', 1, n);
  if FBad > 0 then
    Fail(Format('%s: %d of %d comparisons differ from upstream:%s',
      [AId, FBad, FCompared, FReport]));
  AssertTrue(Format('%s: comparisons made (%d)', [AId, FCompared]), FCompared >= AMin);
end;

procedure TAdvChartAnimEngine2OracleTest.TestTheGradientTransitionsAreUpstreams;
begin
  RunCaseId('grad-update', 1000);
end;

procedure TAdvChartAnimEngine2OracleTest.TestTheGradientKeyframesAreUpstreams;
begin
  RunCaseId('grad-keyframe', 400);
end;

procedure TAdvChartAnimEngine2OracleTest.TestThePauseOfTheChartIsUpstreams;
begin
  RunCaseId('pause-chart', 300);
end;

procedure TAdvChartAnimEngine2OracleTest.TestThePauseOfAnAnimatorIsUpstreams;
begin
  RunCaseId('pause-animator', 300);
end;

{ a merge of the series alone while paused: upstream's one animation flushes
  the graphic's clip too -- the port's series driver flushes the others }
procedure TAdvChartAnimEngine2OracleTest.TestASeriesMergeWhilePausedStepsTheGraphic;
begin
  RunCaseId('pause-series-merge', 100);
end;

{ ==================== beyond the fixture ==================== }

function Gradient(const AJson: string): TTyAnimValue;
var d: TJSONData;
begin
  d := GetJSON(AJson);
  try
    Result := TyGfxAnimOf(d);
  finally
    d.Free;
  end;
end;

{ a linear against a radial is discrete: a keyframe animation (discrete
  allowed) writes the raw object it was given -- its own colour words, not
  rgba -- on each side of the keyframe }
procedure TAdvChartAnimEngine2Test.TestADiscreteGradientWritesTheObjectItWas;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  lin, rad, v: TTyAnimValue;
  d: TJSONData;
begin
  lin := Gradient('{"type": "linear", "x": 0, "y": 0, "x2": 0, "y2": 1, '
    + '"colorStops": [{"offset": 0, "color": "red"}, {"offset": 1, "color": "#00ff00"}]}');
  rad := Gradient('{"type": "radial", "x": 0.5, "y": 0.5, "r": 0.5, '
    + '"colorStops": [{"offset": 0, "color": "blue"}, {"offset": 1, "color": "#ffffff"}]}');
  AssertTrue('a linear gradient reads as one', (lin.Kind = avkGradient) and (lin.Stride = 4));
  AssertTrue('a radial gradient reads as one', (rad.Kind = avkGradient) and (rad.Stride = 3));
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    bag.SetAnimProp('style.fill', lin);
    bag.Animation := drv;
    bag.Animate('style', False, True).WhenWithKeys(1000, ['fill'], [rad])
      .Duration(1000).Start('');
    drv.Update(1000);
    drv.Update(1500);
    v := bag.GetAnimProp('style.fill');
    d := TyGfxJsonOf(v);
    try
      AssertEquals('before the keyframe: the linear one as written', 'red',
        TJSONObject(d).Arrays['colorStops'].Objects[0].Strings['color']);
    finally
      d.Free;
    end;
    drv.Update(2000);
    v := bag.GetAnimProp('style.fill');
    d := TyGfxJsonOf(v);
    try
      AssertEquals('at it: the radial one as written', 'blue',
        TJSONObject(d).Arrays['colorStops'].Objects[0].Strings['color']);
      AssertEquals('its type', 'radial', TJSONObject(d).Strings['type']);
    finally
      d.Free;
    end;
  finally
    bag.Free;
    drv.Free;
  end;
end;

{ an additive animateTo onto a running gradient tween makes a track that adds
  to nothing (upstream's additive linear gradient reads a difference it never
  computed and throws): its own values are written, from the earlier
  animator's last keyframe }
procedure TAdvChartAnimEngine2Test.TestAGradientIsNeverAdditive;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
  a, b, c: TTyAnimValue;
  d: TJSONData;
begin
  a := Gradient('{"type": "linear", "x": 0, "y": 0, "x2": 0, "y2": 1, '
    + '"colorStops": [{"offset": 0, "color": "#000000"}, {"offset": 1, "color": "#000000"}]}');
  b := Gradient('{"type": "linear", "x": 1, "y": 0, "x2": 0, "y2": 1, '
    + '"colorStops": [{"offset": 0, "color": "#ffffff"}, {"offset": 1, "color": "#ffffff"}]}');
  c := Gradient('{"type": "linear", "x": 0, "y": 0, "x2": 0, "y2": 1, '
    + '"colorStops": [{"offset": 0, "color": "#ff0000"}, {"offset": 1, "color": "#ff0000"}]}');
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    bag.SetAnimProp('style.fill', a);
    bag.Animation := drv;
    cfg := TyAnimCfg(1000, 0, 'linear');
    bag.AnimateTo(TyAnimProps([TyAnimProp('style.fill', b)]), cfg);
    drv.Update(0, True);
    drv.Update(500);
    cfg.Additive := True;
    bag.AnimateTo(TyAnimProps([TyAnimProp('style.fill', c)]), cfg);
    drv.Update(500, True);
    AssertEquals('two animators', 2, bag.AnimatorCount);
    AssertTrue('the new track adds to nothing',
      bag.AnimatorAt(1).TrackAt(0).AdditiveTrack = nil);
    drv.Update(1000);
    d := TyGfxJsonOf(bag.GetAnimProp('style.fill'));
    try
      { from b's x (1) half-way to c's (0) }
      AssertEquals('its own values, from the last keyframe of the earlier one', 0.5,
        TJSONObject(d).Floats['x'], 0);
    finally
      d.Free;
    end;
  finally
    bag.Free;
    drv.Free;
  end;
end;

{ Animation.pause: Update itself still steps (a flush), at the clock less
  the paused time so far; resume adds the stretch }
procedure TAdvChartAnimEngine2Test.TestAPausedDriverStepsOnlyWhenAsked;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    bag.SetNum('x', 0);
    bag.Animation := drv;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(100))]), TyAnimCfg(1000, 0, 'linear'));
    drv.Update(0, True);
    drv.Update(200);
    drv.Pause(200);
    drv.Pause(300);
    AssertTrue('paused', drv.Paused);
    drv.Update(400, True);
    AssertEquals('a flush while paused steps at the wall clock', 40, bag.Num('x'), 0);
    drv.Resume(600);
    AssertEquals('the paused stretch', 400, drv.PausedTime, 0);
    drv.Update(700);
    AssertEquals('400 ms behind', 30, bag.Num('x'), 0);
    drv.Resume(800);
    AssertEquals('a resume while running does nothing', 400, drv.PausedTime, 0);
  finally
    bag.Free;
    drv.Free;
  end;
end;

{ a paused chart's tick moves nothing and emits nothing; resume goes on
  from the paused value }
procedure TAdvChartAnimEngine2Test.TestAPausedChartTicksNothing;
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TGfxProbe;
  bmp: TBGRABitmap;
  el: TTyGfxEl;
  list: TTyGfxElArray;
  x1: Double;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  ctl.Mode := 'light';
  ctl.ThemeName := 'default';
  chart := TGfxProbe.Create(form);
  try
    chart.Parent := form;
    chart.Controller := ctl;
    chart.SetBounds(0, 0, 400, 300);
    chart.AnimationMode := camAlways;
    chart.AnimNow := 1000;
    chart.SetOption('{"graphic": [{"type": "rect", "id": "a", "x": 200, "y": 20, '
      + '"shape": {"width": 10, "height": 10}, "style": {"fill": "#000"}, '
      + '"enterFrom": {"x": 0}, "enterAnimation": {"duration": 1000, "easing": "linear"}}]}', True);
    bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
    try
      chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    finally
      bmp.Free;
    end;
    list := nil;
    TyGfxTraverse(chart.GraphicView.Root, list);
    AssertEquals('one element', 1, Length(list));
    el := list[0];
    chart.AnimNow := 1500;
    chart.AnimTick(1500);
    x1 := el.X;
    AssertEquals('half-way', 100, x1, 0);
    chart.AnimPause;
    AssertTrue('paused', chart.AnimPaused);
    chart.AnimNow := 1800;
    chart.AnimTick(1800);
    AssertEquals('a paused tick moves nothing', x1, el.X, 0);
    chart.AnimNow := 2000;
    chart.AnimResume;
    AssertFalse('running', chart.AnimPaused);
    chart.AnimNow := 2100;
    chart.AnimTick(2100);
    AssertEquals('on from where it stood, 500 ms behind', 120, el.X, 0);
  finally
    chart.Free;
    ctl.Free;
    form.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartAnimEngine2OracleTest);
  RegisterTest(TAdvChartAnimEngine2Test);
end.
