unit test.advchart.keyframeanimation;
{$mode objfpc}{$H+}
{ KEYFRAME ANIMATION AND THE TRANSITION LANGUAGE, HELD TO UPSTREAM [Batch 139,
  D6].

  tools/advchart-oracle/keyframe-animation.js runs the real ECharts 6.1
  build in node and samples, on the animation clock, every graphic and
  custom element -- its eleven transform props, the style keys it has, every
  shape and extra key, how many animators it holds -- for:

    the keyframes   a missing 0%, keyframes out of order, a keyframe's own
                    easing (named and cubic-bezier) under the clip's, style
                    colours and opacity with a delay, points of changing
                    length, extra (a number and a discrete text), a text's
                    discrete text, the enter duration when none is written,
                    a group, an array of two on the root, animation off;
    the loops       across their restarts, with no 0% and no 100%, then an
                    update mid-loop: the keyframes stopped and their values
                    put back, a new one from there, 'all' beside a keyframe
                    on the same opacity, a root keyframe beside a transition
                    on the same x;
    additive        updateAnimation's `additive` over a running update --
                    ending first, ending last, on a colour -- against the
                    same move without it;
    the language    extra's enterFrom, transition 'all', extra.transition,
                    the word 'extra', style.transition and shape.transition
                    'all', the words 'shape' and 'style', a leaveTo on extra
                    given in the remove itself;
    custom          looping keyframes on a rect, its textContent's own, a
                    circle's shape, a group and its children, the series'
                    duration; new data stopping and restoring every element
                    before the default transition; extra and additive on
                    custom elements.

  This replays it through the control bit for bit, each renderItem a Pascal
  transcription (TKfMirror). }
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
  { the renderItems of keyframe-animation.js, transcribed }
  TKfMirror = class
  public
    function KfItem(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function TrItem(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  TAdvChartKeyframeOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    FRoot: TJSONData;
    FMirror: TKfMirror;
    FBad, FCompared, FSamples: Integer;
    FWhere, FReport: string;
    procedure Bad(const AWhat: string);
    procedure SameValue(const AWhat: string; const AGot: TTyAnimValue; AWant: TJSONData);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    function Elements: TStringList;
    procedure CheckSnap(AEl: TTyGfxEl; ASnap: TJSONObject);
    procedure CheckSamples(AState: TJSONObject; AStart: Double; ASamplesMs: TJSONArray);
    procedure RunCase(ACase: TJSONObject);
    procedure RunGroup(const AGroup: string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGraphicKeyframesAreUpstreams;
    procedure TestTheLoopsAndTheRestoreAreUpstreams;
    procedure TestTheAdditiveUpdatesAreUpstreams;
    procedure TestTheTransitionLanguageIsUpstreams;
    procedure TestTheCustomKeyframesAreUpstreams;
  end;

  { What the fixture does not reach. }
  TAdvChartKeyframeTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    procedure RenderNow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAKeyframesEasingShapesItsSegment;
    procedure TestAFinishedAdditiveTrackFinishesTheOneItAddsTo;
    procedure TestAnAnimateWithoutATargetSurvivesAnAnimateTo;
    procedure TestSwitchingTheAnimationOffStopsALoopAtItsEnd;
    procedure TestALoopKeepsTheChartsClockRunning;
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
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B))
    or ((A = 0) and (B = 0));
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

function TKfMirror.KfItem(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y: Double;
  o: TJSONObject;
begin
  x := AApi.Value(0);
  y := AApi.Value(1);
  if AParams.DataIndex = 0 then
  begin
    o := TJSONObject(GetJSON('{"type": "rect", "shape": {"x": -10, "y": -10, "width": 20, "height": 20},'
      + ' "style": {"fill": "#5070dd"},'
      + ' "keyframeAnimation": {"duration": 600, "loop": true, "keyframes": ['
      + '   {"percent": 0.5, "rotation": 1, "style": {"opacity": 0.4}},'
      + '   {"percent": 1, "rotation": 0, "style": {"opacity": 1}}]},'
      + ' "textContent": {"style": {"text": "A", "fill": "#000000"},'
      + '   "keyframeAnimation": {"duration": 300, "keyframes": [{"percent": 1, "style": {"fill": "#ff0000"}}]}},'
      + ' "textConfig": {"position": "top"}}'));
    o.Add('x', Num(x));
    o.Add('y', Num(y));
    Exit(o);
  end;
  if AParams.DataIndex = 1 then
  begin
    o := TJSONObject(GetJSON('{"type": "circle", "shape": {"r": 10}, "style": {"fill": "#b6d634"}}'));
    o.Add('x', Num(x));
    o.Add('y', Num(y));
    if y > 100 then o.Add('keyframeAnimation', TJSONNull.Create)
    else
      o.Add('keyframeAnimation', GetJSON('{"duration": 1000, "keyframes": ['
        + '{"percent": 0.3, "shape": {"r": 20}},'
        + '{"percent": 1, "shape": {"r": 5}, "easing": "elasticOut"}]}'));
    Exit(o);
  end;
  o := TJSONObject(GetJSON('{"type": "group",'
    + ' "keyframeAnimation": {"duration": 800, "keyframes": [{"percent": 0.5, "scaleX": 2}, {"percent": 1, "scaleX": 1}]},'
    + ' "children": ['
    + '   {"type": "rect", "shape": {"x": -5, "y": -5, "width": 10, "height": 10}, "style": {"fill": "#ff994d"},'
    + '     "keyframeAnimation": {"duration": 400, "loop": true, "keyframes": [{"percent": 1, "x": 20}]}},'
    + '   {"type": "circle", "shape": {"r": 3}, "style": {"fill": "#000000"},'
    + '     "keyframeAnimation": {"keyframes": [{"percent": 1, "shape": {"r": 6}}]}}]}'));
  o.Add('x', Num(x));
  o.Add('y', Num(y));
  Result := o;
end;

function TKfMirror.TrItem(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y: Double;
  o, sh, st, ex, ef: TJSONObject;
begin
  x := AApi.Value(0);
  y := AApi.Value(1);
  if AParams.DataIndex = 0 then
  begin
    o := TJSONObject(GetJSON('{"type": "rect", "shape": {"width": 20, "height": 20},'
      + ' "style": {"fill": "#5070dd"}, "transition": ["x", "extra"]}'));
    o.Add('x', Num(x));
    o.Add('y', Num(y));
    ex := TJSONObject.Create;
    ex.Add('k', Num(y));
    ef := TJSONObject.Create;
    ef.Add('k', 0);
    ex.Add('enterFrom', ef);
    o.Add('extra', ex);
    Exit(o);
  end;
  o := TJSONObject(GetJSON('{"type": "circle",'
    + ' "updateAnimation": {"duration": 400, "easing": "linear", "additive": true}}'));
  o.Add('x', Num(x));
  o.Add('y', Num(y));
  sh := TJSONObject.Create;
  sh.Add('r', Num(y / 10));
  sh.Add('transition', 'all');
  o.Add('shape', sh);
  st := TJSONObject.Create;
  if y > 100 then st.Add('fill', '#ff0000') else st.Add('fill', '#b6d634');
  st.Add('lineWidth', Num(y / 20));
  st.Add('stroke', '#333333');
  st.Add('transition', 'all');
  o.Add('style', st);
  Result := o;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartKeyframeOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-keyframe-animation.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-keyframe-animation.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FMirror := TKfMirror.Create;
  TyChartRegisterRenderItem('kfItem', @FMirror.KfItem);
  TyChartRegisterRenderItem('trItem', @FMirror.TrItem);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartKeyframeOracleTest.TearDown;
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

procedure TAdvChartKeyframeOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartKeyframeOracleTest.SameValue(const AWhat: string;
  const AGot: TTyAnimValue; AWant: TJSONData);
var
  i, k, n: Integer;
  row: TJSONData;
  want: Double;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    if AGot.Kind <> avkNull then Bad(AWhat + ': a value, upstream none');
    Exit;
  end;
  case AWant.JSONType of
    jtBoolean:
      if (AGot.Kind <> avkBool) or ((AGot.Num <> 0) <> AWant.AsBoolean) then
        Bad(AWhat + ': not the boolean ' + AWant.AsJSON);
    jtString:
      if IsHex(AWant) then
      begin
        want := FromHex(AWant.AsString);
        if AGot.Kind <> avkNumber then Bad(AWhat + ': no number, upstream ' + Txt(want))
        else if not SameBits(AGot.Num, want) then
          Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot.Num), Txt(want)]));
      end
      else if (AGot.Kind <> avkString) or (AGot.Str <> AWant.AsString) then
      begin
        if AGot.Kind = avkString then Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot.Str, AWant.AsString]))
        else Bad(AWhat + ': no text, upstream ' + AWant.AsString);
      end;
    jtArray:
      begin
        if AGot.Kind <> avkArray then
        begin
          Bad(AWhat + ': no array');
          Exit;
        end;
        if (AWant.Count > 0) and (AWant.Items[0].JSONType = jtArray) then
        begin
          n := 0;
          for i := 0 to AWant.Count - 1 do
          begin
            row := AWant.Items[i];
            for k := 0 to row.Count - 1 do
            begin
              if n > High(AGot.Arr) then Bad(AWhat + ': short')
              else if not SameBits(AGot.Arr[n], FromHex(row.Items[k].AsString)) then
                Bad(Format('%s[%d][%d] %s, upstream %s', [AWhat, i, k, Txt(AGot.Arr[n]),
                  Txt(FromHex(row.Items[k].AsString))]));
              Inc(n);
            end;
          end;
          if n <> Length(AGot.Arr) then Bad(Format('%s: %d numbers, upstream %d', [AWhat, Length(AGot.Arr), n]));
        end
        else
        begin
          if Length(AGot.Arr) <> AWant.Count then
            Bad(Format('%s: %d items, upstream %d', [AWhat, Length(AGot.Arr), AWant.Count]));
          for i := 0 to Min(AWant.Count, Length(AGot.Arr)) - 1 do
            if not SameBits(AGot.Arr[i], FromHex(AWant.Items[i].AsString)) then
              Bad(Format('%s[%d] %s, upstream %s', [AWhat, i, Txt(AGot.Arr[i]),
                Txt(FromHex(AWant.Items[i].AsString))]));
        end;
      end;
  else
    Bad(AWhat + ': an unexpected record ' + AWant.AsJSON);
  end;
end;

procedure TAdvChartKeyframeOracleTest.NewChart(AW, AH: Integer);
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

procedure TAdvChartKeyframeOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ every element by the oracle's key: a graphic element's id, a custom
  element's 's<series>:<raw>' with '/<child>' per level and '#label' for its
  textContent }
function TAdvChartKeyframeOracleTest.Elements: TStringList;
var
  list: TTyGfxElArray;
  i, s: Integer;
  view: TTyCustomView;

  procedure Walk(AEl: TTyGfxEl; const AKey: string);
  var k: Integer;
  begin
    Result.AddObject(AKey, AEl);
    if AEl.TextContent <> nil then Result.AddObject(AKey + '#label', AEl.TextContent);
    for k := 0 to High(AEl.Children) do Walk(AEl.Children[k], AKey + '/' + IntToStr(k));
  end;

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
      Walk(view.Root.Children[i], 's' + IntToStr(s) + ':'
        + IntToStr(view.RawOfRoot(view.Root.Children[i])));
  end;
end;

function SkipKey(const AKey: string): Boolean;
begin
  Result := (AKey = 'transition') or (AKey = 'enterFrom') or (AKey = 'leaveTo');
end;

{ a snap: what upstream has, and nothing in the shape or extra it has not }
procedure TAdvChartKeyframeOracleTest.CheckSnap(AEl: TTyGfxEl; ASnap: TJSONObject);
var
  i: Integer;
  key: string;
  d: TJSONData;
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
      SameValue(key, AEl.StyleValue(Copy(key, 7, MaxInt)), d)
    else
      SameValue(key, AEl.GetAnimProp(key), d);
  end;
  if not AEl.IsGroup then
    for i := 0 to AEl.Shape.Count - 1 do
      if not SkipKey(AEl.Shape.Names[i]) and not IsNull(AEl.Shape.Items[i])
        and (ASnap.Find('shape.' + AEl.Shape.Names[i]) = nil) then
        Bad('shape.' + AEl.Shape.Names[i] + ': upstream has none');
  if AEl.Extra <> nil then
    for i := 0 to AEl.Extra.Count - 1 do
      if not SkipKey(AEl.Extra.Names[i]) and not IsNull(AEl.Extra.Items[i])
        and (ASnap.Find('extra.' + AEl.Extra.Names[i]) = nil) then
        Bad('extra.' + AEl.Extra.Names[i] + ': upstream has none');
end;

procedure TAdvChartKeyframeOracleTest.CheckSamples(AState: TJSONObject; AStart: Double;
  ASamplesMs: TJSONArray);
var
  samples: TJSONArray;
  smp, els: TJSONObject;
  i, k, idx: Integer;
  t: Double;
  got: TStringList;
  was: string;
begin
  samples := AState.Arrays['samples'];
  if samples.Count <> ASamplesMs.Count then Bad('the samples are not the samplesMs');
  was := FWhere;
  for i := 0 to samples.Count - 1 do
  begin
    smp := samples.Objects[i];
    t := smp.Floats['t'];
    FWhere := Format('%s t=%s', [was, Txt(t)]);
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(FSamples);
    els := smp.Objects['els'];
    got := Elements;
    try
      Inc(FCompared);
      if got.Count <> els.Count then
        Bad(Format('%d elements, upstream %d', [got.Count, els.Count]));
      for k := 0 to got.Count - 1 do
        if els.Find(got[k]) = nil then Bad('upstream has no ' + got[k]);
      for k := 0 to els.Count - 1 do
      begin
        idx := got.IndexOf(els.Names[k]);
        if idx < 0 then
        begin
          Bad('missing ' + els.Names[k]);
          Continue;
        end;
        FWhere := Format('%s t=%s %s', [was, Txt(t), els.Names[k]]);
        CheckSnap(TTyGfxEl(got.Objects[idx]), TJSONObject(els.Items[k]));
      end;
    finally
      got.Free;
    end;
  end;
  FWhere := was;
end;

procedure TAdvChartKeyframeOracleTest.RunCase(ACase: TJSONObject);
var
  steps, states, smp: TJSONArray;
  step: TJSONObject;
  j, si: Integer;
  t0, clock, start: Double;
begin
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  t0 := TJSONObject(FRoot).Objects['clock'].Floats['T0'];
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := t0;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
  states := ACase.Arrays['states'];
  smp := ACase.Arrays['samplesMs'];
  FWhere := ACase.Strings['id'] + ' state 0';
  CheckSamples(states.Objects[0], t0, smp);
  clock := t0 + smp.Floats[smp.Count - 1];
  steps := ACase.Arrays['steps'];
  si := 0;
  for j := 0 to steps.Count - 1 do
  begin
    step := steps.Objects[j];
    if step.Find('wait') <> nil then
    begin
      clock := clock + step.Floats['wait'];
      FChart.AnimNow := clock;
      FChart.AnimTick(clock);
      Continue;
    end;
    Inc(si);
    FWhere := Format('%s step %d', [ACase.Strings['id'], j]);
    FChart.AnimNow := clock;
    FChart.SetOption(step.Objects['merge'].AsJSON, False);
    RenderNow;
    start := clock;
    smp := step.Arrays['samplesMs'];
    CheckSamples(states.Objects[si], start, smp);
    clock := start + smp.Floats[smp.Count - 1];
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartKeyframeOracleTest.RunGroup(const AGroup: string; AMin: Integer);
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

procedure TAdvChartKeyframeOracleTest.TestTheGraphicKeyframesAreUpstreams;
begin
  RunGroup('keyframe', 2000);
  AssertTrue('samples compared', FSamples >= 18);
end;

procedure TAdvChartKeyframeOracleTest.TestTheLoopsAndTheRestoreAreUpstreams;
begin
  RunGroup('loop', 800);
end;

procedure TAdvChartKeyframeOracleTest.TestTheAdditiveUpdatesAreUpstreams;
begin
  RunGroup('additive', 600);
end;

procedure TAdvChartKeyframeOracleTest.TestTheTransitionLanguageIsUpstreams;
begin
  RunGroup('transition', 600);
end;

procedure TAdvChartKeyframeOracleTest.TestTheCustomKeyframesAreUpstreams;
begin
  RunGroup('custom', 800);
end;

{ ==================== beyond the fixture ==================== }

procedure TAdvChartKeyframeTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TGfxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 400, 300);
end;

procedure TAdvChartKeyframeTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartKeyframeTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

{ a keyframe's easing shapes the segment that ends on it, after the clip's
  percent: halfway through a 0-to-100 segment eased quadraticIn is 25 }
procedure TAdvChartKeyframeTest.TestAKeyframesEasingShapesItsSegment;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    bag.SetNum('x', 0);
    bag.Animation := drv;
    bag.Animate('', False, True).WhenWithKeys(0, ['x'], [TyAnimNum(0)])
      .WhenWithKeys(1000, ['x'], [TyAnimNum(100)], 'quadraticIn')
      .Duration(1000).Start('');
    drv.Update(1000);
    drv.Update(1500);
    AssertEquals('quadraticIn at the middle', 25, bag.Num('x'), 0);
    drv.Update(2000);
    AssertEquals('the end', 100, bag.Num('x'), 0);
    { an easing that resolves to nothing eases nothing }
    bag.SetNum('y', 0);
    bag.Animate('', False, True).WhenWithKeys(1000, ['y'], [TyAnimNum(100)], 'noSuchEasing')
      .Duration(1000).Start('');
    drv.Update(3000);
    drv.Update(3500);
    AssertEquals('an unknown easing is linear', 50, bag.Num('y'), 0);
  finally
    bag.Free;
    drv.Free;
  end;
end;

{ zrender's Track.setFinished: the additive track that ends finishes the
  one it adds to, so the earlier animator writes no more }
procedure TAdvChartKeyframeTest.TestAFinishedAdditiveTrackFinishesTheOneItAddsTo;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
  first, second: TTyAnimator;
  held: Double;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    bag.SetNum('x', 0);
    bag.Animation := drv;
    cfg := TyAnimCfg(1000, 0, 'linear');
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(200))]), cfg);
    first := bag.AnimatorAt(0);
    drv.Update(0);
    drv.Update(300);
    cfg := TyAnimCfg(200, 0, 'linear');
    cfg.Additive := True;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(100))]), cfg);
    second := bag.AnimatorAt(1);
    AssertTrue('the second adds to the first', second.TrackAt(0).AdditiveTrack = first.TrackAt(0));
    drv.Update(300);
    drv.Update(500);
    AssertTrue('the first track is finished with the second', first.TrackAt(0).Finished);
    held := bag.Num('x');
    drv.Update(800);
    AssertEquals('the value stays where the additive one left it', held, bag.Num('x'), 0);
  finally
    bag.Free;
    drv.Free;
  end;
end;

{ Element.animate('') leaves targetName undefined: an animateTo of the same
  key (whose animators are '') does not stop it, and it is not one an
  additive animateTo adds to }
procedure TAdvChartKeyframeTest.TestAnAnimateWithoutATargetSurvivesAnAnimateTo;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  kf: TTyAnimator;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    bag.SetNum('x', 0);
    bag.Animation := drv;
    kf := bag.Animate('', True, True);
    kf.WhenWithKeys(1000, ['x'], [TyAnimNum(100)]).Duration(1000).Start('');
    AssertTrue('no target name', kf.NoTargetName);
    drv.Update(0);
    drv.Update(100);
    cfg := TyAnimCfg(500, 0, 'linear');
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(50))]), cfg);
    AssertFalse('the keyframe track still runs', kf.TrackAt(0).Finished);
    AssertTrue('the keyframe animator keeps its clip', kf.Clip <> nil);
    AssertFalse('the animateTo is no element.animate', bag.AnimatorAt(1).NoTargetName);
  finally
    bag.Free;
    drv.Free;
  end;
end;

{ the chart's animation switched off mid-loop: every keyframe animation at
  its last frame, nothing left running }
procedure TAdvChartKeyframeTest.TestSwitchingTheAnimationOffStopsALoopAtItsEnd;
var el: TTyGfxEl;
begin
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := 1000000;
  FChart.SetOption('{"animation": true, "graphic": [{"type": "rect", "id": "r", "x": 10,'
    + ' "shape": {"width": 10, "height": 10},'
    + ' "keyframeAnimation": {"duration": 400, "loop": true, "keyframes": [{"percent": 0.5, "x": 90}, {"percent": 1, "x": 30}]}}]}', True);
  RenderNow;
  FChart.AnimNow := 1000100;
  FChart.AnimTick(1000100);
  el := FChart.GraphicView.Find('r');
  AssertTrue('the element', el <> nil);
  AssertTrue('the loop runs', el.AnimatorCount = 1);
  FChart.AnimationMode := camOff;
  AssertEquals('at the last keyframe', 30, el.X, 0);
  AssertEquals('nothing left', 0, el.AnimatorCount);
end;

{ a loop never ends: the chart keeps ticking }
procedure TAdvChartKeyframeTest.TestALoopKeepsTheChartsClockRunning;
var el: TTyGfxEl;
begin
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := 1000000;
  FChart.SetOption('{"animation": true, "graphic": [{"type": "circle", "id": "c",'
    + ' "shape": {"r": 10},'
    + ' "keyframeAnimation": {"duration": 200, "loop": true, "keyframes": [{"percent": 1, "shape": {"r": 20}}]}}]}', True);
  RenderNow;
  FChart.AnimNow := 1100000;
  FChart.AnimTick(1100000);
  el := FChart.GraphicView.Find('c');
  AssertTrue('the element', el <> nil);
  AssertEquals('still looping long after', 1, el.AnimatorCount);
  AssertTrue('the graphic clock is live', FChart.GraphicView.Animation.ClipCount > 0);
end;

initialization
  RegisterTest(TAdvChartKeyframeOracleTest);
  RegisterTest(TAdvChartKeyframeTest);
end.
