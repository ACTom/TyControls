unit test.advchart.animengine;
{$mode objfpc}{$H+}
{ THE ANIMATION ENGINE, held to upstream: easing, clip, track, animator,
  driver and the option resolution, without a chart. [Batch 87, AN1]

  tools/advchart-oracle/animation.js runs the real ECharts 6.1 build under a
  hand-stepped clock and records every element's animated properties at
  t = 0, 1, 16, 50, 100, 250, 500, 750, 999, 1000, 1001 and 1500 ms, the
  live clip count at each, and what getShallow resolved per series.

  THE REPLAY. For every element whose tracks are plain numbers or number
  arrays and whose one scope is enter, update or leave, a TTyAnimBag is
  given the element's value at t = 0 (the from value) and handed to
  TyInitProps / TyUpdateProps / TyRemoveElement with the element's final
  value and a model read from the case's own option; the driver is then
  stepped at the fixture's absolute times (T0 = 1700000000000, so a
  fractional delay rounds where upstream's does) and every sample is
  compared bit for bit, with the element's animator count and -- where
  every animated element of the case was replayed -- the clip count.

  AND BY HAND: stopTracks' step back to the from value, leave's fixed
  timing, the zero-duration path, a looping clip's phase, the final value
  one unit in the last place off its target, float32 stores, colour
  strings, discrete jumps. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.JsMath, tyControls.AdvChart.Easing,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt;
type
  TAdvChartAnimEngineTest = class(TTestCase)
  private
    FDuring: array of Double;
    FDoneCount, FAbortedCount: Integer;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const AWhere: string);
    function HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function HIdx30(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function HDur600(ADataIndex: Integer; AHasIndex: Boolean): Double;
    procedure OnDuring(APercent: Double);
    procedure OnDone;
    procedure OnAborted;
    function ReplayCase(ACase: TJSONObject; out AReplayed, ASkipped: Integer): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEasingTableBitForBit;
    procedure TestCubicBezierPattern;
    procedure TestBarVerticalReplays;
    procedure TestBarHorizontalAndStackedReplay;
    procedure TestEveryOtherPlainTrackReplays;
    procedure TestResolutionMatchesEveryCase;
    procedure TestThresholdCases;
    procedure TestTypeDefaultsAndRootChain;
    procedure TestClockStartsAtTheFirstStep;
    procedure TestDelayPhaseHoldsTheFromValue;
    procedure TestStopTracksStepsBackToFrom;
    procedure TestStopTracksAfterAFrameKeepsTheCurrentValue;
    procedure TestStopForwardToLast;
    procedure TestLeaveTimingIgnoresTheOptions;
    procedure TestZeroDurationSetsAtOnce;
    procedure TestLoopRestartKeepsThePhase;
    procedure TestFinalValueIsArithmeticNotSnapped;
    procedure TestFloat32ArrayRoundsOnStore;
    procedure TestColourInterpolatesToRgba;
    procedure TestDiscreteJumpsAndUnchangedKeysDrop;
    procedure TestDuringGoesToTheFirstAnimatorOnly;
    procedure TestLifeZeroIsAThousand;
    procedure TestStopTracksSpliceSkipsTheNextAnimator;
    procedure TestArraysAlignWithTheLastKeyframe;
  end;

implementation

var
  GFixture: TJSONData = nil;

function Fixture: TJSONObject;
var sl: TStringList;
begin
  if GFixture = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-animation.json');
      GFixture := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFixture);
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function IsHex16(AData: TJSONData): Boolean;
var s: string; i: Integer;
begin
  Result := False;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  s := AData.AsString;
  if Length(s) <> 16 then Exit;
  for i := 1 to 16 do
    if not (s[i] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
  Result := True;
end;

function SameBits(AGot: Double; const AWant: string): Boolean;
begin
  if IsNan(FromHex(AWant)) then Exit(IsNan(AGot));
  Result := Hex(AGot) = LowerCase(AWant);
end;

// {"$fn": name} -> '@name', in place, everywhere
procedure ConvertFns(AData: TJSONData);
var
  i: Integer;
  o: TJSONObject;
  child: TJSONData;
begin
  if AData = nil then Exit;
  if AData.JSONType = jtArray then
  begin
    for i := 0 to AData.Count - 1 do
    begin
      child := AData.Items[i];
      if (child.JSONType = jtObject) and (TJSONObject(child).Count = 1)
        and (TJSONObject(child).Find('$fn') <> nil) then
        TJSONArray(AData).Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
      else
        ConvertFns(child);
    end;
  end
  else if AData.JSONType = jtObject then
  begin
    o := TJSONObject(AData);
    for i := 0 to o.Count - 1 do
    begin
      child := o.Items[i];
      if (child.JSONType = jtObject) and (TJSONObject(child).Count = 1)
        and (TJSONObject(child).Find('$fn') <> nil) then
        o.Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
      else
        ConvertFns(child);
    end;
  end;
end;

function CaseById(const AId: string): TJSONObject;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := Fixture.Arrays['cases'];
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then Exit(cases.Objects[i]);
  Result := nil;
end;

function T0: Double;
begin
  Result := Fixture.Objects['clock'].Floats['T0'];
end;

{ ==================== handlers and callbacks ==================== }

function TAdvChartAnimEngineTest.HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  { (idx) => idx * 50; null * 50 is 0 }
  if AHasIndex then Result := ADataIndex * 50 else Result := 0;
end;

function TAdvChartAnimEngineTest.HIdx30(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if AHasIndex then Result := ADataIndex * 30 else Result := 0;
end;

function TAdvChartAnimEngineTest.HDur600(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if AHasIndex then Result := 600 + ADataIndex * 100 else Result := 600;
end;

procedure TAdvChartAnimEngineTest.OnDuring(APercent: Double);
begin
  SetLength(FDuring, Length(FDuring) + 1);
  FDuring[High(FDuring)] := APercent;
end;

procedure TAdvChartAnimEngineTest.OnDone;
begin
  Inc(FDoneCount);
end;

procedure TAdvChartAnimEngineTest.OnAborted;
begin
  Inc(FAbortedCount);
end;

procedure TAdvChartAnimEngineTest.SetUp;
begin
  inherited SetUp;
  TyChartRegisterAnimTiming('idx*50', @HIdx50);
  TyChartRegisterAnimTiming('idx*30', @HIdx30);
  TyChartRegisterAnimTiming('dur:600+idx*100', @HDur600);
  FDuring := nil;
  FDoneCount := 0;
  FAbortedCount := 0;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartAnimEngineTest.TearDown;
begin
  TyChartClearAnimTimings;
  inherited TearDown;
end;

procedure TAdvChartAnimEngineTest.Miss(const AWhere: string);
begin
  Inc(FBad);
  if FBad <= 12 then FReport := FReport + LineEnding + '  ' + AWhere;
end;

{ ==================== easing ==================== }

procedure TAdvChartAnimEngineTest.TestEasingTableBitForBit;
var
  e: TJSONObject;
  ts, rows, vals: TJSONArray;
  row: TJSONObject;
  i, j, named: Integer;
  ez: TTyEasing;
  got: Double;
begin
  e := Fixture.Objects['easings'];
  ts := e.Arrays['ts'];
  rows := e.Arrays['table'];
  AssertEquals('95 sample points', 95, ts.Count);
  named := 0;
  for i := 0 to rows.Count - 1 do
  begin
    row := rows.Objects[i];
    ez := TyEasingResolve(row.Strings['name']);
    if (ez.Kind <> ekNone) <> row.Booleans['resolved'] then
      Miss(Format('%s: resolved %s, upstream %s', [row.Strings['name'],
        BoolToStr(ez.Kind <> ekNone, True), BoolToStr(row.Booleans['resolved'], True)]));
    if row.Strings['kind'] = 'named' then Inc(named);
    vals := row.Arrays['values'];
    for j := 0 to ts.Count - 1 do
    begin
      got := TyEasingApply(ez, FromHex(ts.Strings[j]));
      Inc(FCompared);
      if not SameBits(got, vals.Strings[j]) then
        Miss(Format('%s(%s) = %s, upstream %s', [row.Strings['name'],
          e.Arrays['tsText'].Strings[j], Hex(got), vals.Strings[j]]));
    end;
  end;
  AssertEquals('the 31 named easings', 31, named);
  AssertTrue('every row compared', FCompared = rows.Count * 95);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' differ:' + FReport, 0, FBad);
end;

procedure TAdvChartAnimEngineTest.TestCubicBezierPattern;
var a, b, c, d: Double;
begin
  AssertFalse('a minus sign is outside the class',
    TyCubicBezierParse('cubic-bezier(0.68,-0.55,0.265,1.55)', a, b, c, d));
  AssertTrue('three numbers: the fourth is +null = 0',
    TyCubicBezierParse('cubic-bezier(0.5,0.5,0.5)', a, b, c, d));
  AssertEquals(0.0, d);
  AssertTrue('anywhere in the text, spaces trimmed',
    TyCubicBezierParse('ease cubic-bezier( 0.1 , .2,1e2 ,1.)x', a, b, c, d));
  AssertEquals(0.1, a);
  AssertEquals(0.2, b);
  AssertEquals(100.0, c);
  AssertEquals(1.0, d);
  AssertFalse('1e-1 has a minus sign',
    TyCubicBezierParse('cubic-bezier(1e-1,0.5,0.9,5e-1)', a, b, c, d));
  AssertFalse('a piece Number() refuses is not-a-number',
    TyCubicBezierParse('cubic-bezier(0. 5,0,1,1)', a, b, c, d));
  AssertTrue('a later match when the first fails',
    TyCubicBezierParse('cubic-bezier(x) cubic-bezier(0,0,1,1)', a, b, c, d));
  AssertEquals(1.0, c);
  AssertTrue('an unknown name is linear', TyEasingResolve('CubicOut').Kind = ekNone);
  AssertEquals('and linear is the percent itself', 0.3,
    TyEasingApply(TyEasingResolve('foo'), 0.3));
  { the degenerate spec: 0 on the open interval }
  AssertEquals(0.0, TyEasingApply(TyEasingResolve(
    'cubic-bezier(0.3333333333333333,0,0.6666666666666666,1)'), 0.5));
end;

{ ==================== the replay ==================== }

function IsPlainKey(ATrack: TJSONArray; out AIsArray: Boolean): Boolean;
var
  i, j: Integer;
  v: TJSONData;
begin
  Result := False;
  AIsArray := False;
  for i := 0 to ATrack.Count - 1 do
  begin
    v := ATrack.Items[i];
    if v.JSONType = jtNull then Continue;
    if v.JSONType = jtArray then
    begin
      AIsArray := True;
      for j := 0 to v.Count - 1 do
        if not IsHex16(v.Items[j]) then Exit;
    end
    else if not IsHex16(v) then Exit;
  end;
  Result := True;
end;

{ an array: a line's points are a flat Float32Array (ECPolyline, the diff's
  createFloat32Array), every other element's a 2D array of [x, y] }
function ValueOf(AData: TJSONData; AIsArray, AFloat32: Boolean): TTyAnimValue;
var
  arr: array of Double;
  i: Integer;
begin
  if AIsArray then
  begin
    SetLength(arr, AData.Count);
    for i := 0 to AData.Count - 1 do arr[i] := FromHex(AData.Items[i].AsString);
    if AFloat32 then Result := TyAnimArr(arr, 0, True)
    else Result := TyAnimArr(arr, 2);
  end
  else
    Result := TyAnimNum(FromHex(AData.AsString));
end;

function FirstPresent(ATrack: TJSONArray): TJSONData;
var i: Integer;
begin
  for i := 0 to ATrack.Count - 1 do
    if ATrack.Items[i].JSONType <> jtNull then Exit(ATrack.Items[i]);
  Result := nil;
end;

type
  TReplayEl = record
    Bag: TTyAnimBag;
    Json: TJSONObject;
    Keys: array of string;
    IsArr: array of Boolean;
  end;

function TAdvChartAnimEngineTest.ReplayCase(ACase: TJSONObject;
  out AReplayed, ASkipped: Integer): Boolean;
var
  option: TJSONData;
  elements, samples, clips, track, anims, resolved, scopes: TJSONArray;
  el: TJSONObject;
  drv: TTyAnimation;
  reps: array of TReplayEl;
  i, j, k, n, si, di, cnt: Integer;
  owner, scope, id, kind: string;
  base: Double;
  plain, isArr, allCovered, animated: Boolean;
  props: TTyAnimProps;
  model: TTyAnimModel;
  opts: TTyAnimCallOpts;
  got: TTyAnimValue;
  want: TJSONData;
  present: TJSONArray;
  isPresent, f32: Boolean;
  expect: Integer;
begin
  AReplayed := 0;
  ASkipped := 0;
  id := ACase.Strings['id'];
  kind := ACase.Strings['kind'];
  option := ACase.Objects['option'].Clone;
  drv := TTyAnimation.Create;
  reps := nil;
  try
    ConvertFns(option);
    elements := ACase.Arrays['elements'];
    samples := Fixture.Arrays['samplesMs'];
    clips := ACase.Arrays['clips'];
    resolved := ACase.Arrays['resolved'];
    base := T0;
    if kind = 'update' then base := base + Fixture.Objects['clock'].Floats['T1Offset'];
    drv.Start(base);
    allCovered := True;
    for i := 0 to elements.Count - 1 do
    begin
      el := elements.Objects[i];
      animated := False;
      if el.Find('animators').JSONType = jtArray then
        for j := 0 to el.Arrays['animators'].Count - 1 do
          if el.Arrays['animators'].Integers[j] > 0 then animated := True;
      if el.Find('track').JSONType <> jtObject then
      begin
        if animated then allCovered := False;
        Continue;
      end;
      owner := el.Strings['owner'];
      scopes := el.Arrays['scopes'];
      { labels fade and slide under the label manager's rules (AN2, AN4) }
      plain := (Copy(owner, 1, 6) = 'series') and (scopes.Count = 1)
        and (Pos('#label', el.Strings['id']) = 0);
      if plain then
      begin
        scope := scopes.Strings[0];
        plain := (scope = 'enter') or (scope = 'update') or (scope = 'leave');
      end;
      if plain then
        for j := 0 to el.Objects['track'].Count - 1 do
          if not IsPlainKey(TJSONArray(el.Objects['track'].Items[j]), isArr) then plain := False;
      if not plain then
      begin
        Inc(ASkipped);
        if animated then allCovered := False;
        Continue;
      end;
      n := Length(reps);
      SetLength(reps, n + 1);
      reps[n].Json := el;
      reps[n].Bag := TTyAnimBag.Create;
      reps[n].Bag.Animation := drv;
      f32 := (el.Strings['type'] = 'ec-polyline') or (el.Strings['type'] = 'ec-polygon');
      props := nil;
      for j := 0 to el.Objects['track'].Count - 1 do
      begin
        track := TJSONArray(el.Objects['track'].Items[j]);
        IsPlainKey(track, isArr);
        SetLength(reps[n].Keys, j + 1);
        SetLength(reps[n].IsArr, j + 1);
        reps[n].Keys[j] := el.Objects['track'].Names[j];
        reps[n].IsArr[j] := isArr;
        reps[n].Bag.SetAnimProp(reps[n].Keys[j], ValueOf(FirstPresent(track), isArr, f32));
        SetLength(props, j + 1);
        if scope = 'leave' then
          props[j] := TyAnimProp(reps[n].Keys[j], TyAnimNum(0))
        else
          props[j] := TyAnimProp(reps[n].Keys[j],
            ValueOf(el.Objects['final'].Find(reps[n].Keys[j]), isArr, f32));
      end;
      si := StrToInt(Copy(owner, 7, Pos(':', owner) - 7));
      cnt := 0;
      for j := 0 to resolved.Count - 1 do
        if resolved.Objects[j].Integers['seriesIndex'] = si then
          cnt := resolved.Objects[j].Integers['dataCount'];
      model := TyAnimSeriesModel(option, si, cnt);
      if el.Find('dataIndex').JSONType = jtNull then opts := TyAnimCallNoIndex
      else
      begin
        di := el.Integers['dataIndex'];
        opts := TyAnimCallAt(di);
      end;
      { upstream's line clip is given a done and a during: force }
      if Pos('#clip', el.Strings['id']) > 0 then opts.Done := @OnDone;
      if scope = 'enter' then TyInitProps(reps[n].Bag, props, model, opts)
      else if scope = 'update' then TyUpdateProps(reps[n].Bag, props, model, opts)
      else TyRemoveElement(reps[n].Bag, props, model, opts);
      Inc(AReplayed);
    end;

    for k := 0 to samples.Count - 1 do
    begin
      drv.Update(base + samples.Floats[k]);
      { every live animator has one clip: the replayed elements' own count }
      expect := 0;
      for i := 0 to High(reps) do
        if reps[i].Json.Find('animators').JSONType = jtArray then
          Inc(expect, reps[i].Json.Arrays['animators'].Integers[k]);
      if drv.ClipCount <> expect then
        Miss(Format('%s t=%s: %d clips, the replayed elements have %d animators', [id,
          samples.Items[k].AsString, drv.ClipCount, expect]));
      for i := 0 to High(reps) do
      begin
        el := reps[i].Json;
        present := nil;
        if el.Find('present').JSONType = jtArray then present := el.Arrays['present'];
        isPresent := present = nil;
        if present <> nil then
          for j := 0 to present.Count - 1 do
            if present.Integers[j] = k then isPresent := True;
        if not isPresent then Continue;
        for j := 0 to High(reps[i].Keys) do
        begin
          want := TJSONArray(el.Objects['track'].Find(reps[i].Keys[j])).Items[k];
          got := reps[i].Bag.GetAnimProp(reps[i].Keys[j]);
          Inc(FCompared);
          if reps[i].IsArr[j] then
          begin
            if (got.Kind <> avkArray) or (Length(got.Arr) <> want.Count) then
              Miss(Format('%s %s %s t=%s: not the array', [id, el.Strings['id'],
                reps[i].Keys[j], samples.Items[k].AsString]))
            else
              for n := 0 to want.Count - 1 do
                if not SameBits(got.Arr[n], want.Items[n].AsString) then
                begin
                  Miss(Format('%s %s %s[%d] t=%s: %s, upstream %s', [id, el.Strings['id'],
                    reps[i].Keys[j], n, samples.Items[k].AsString, Hex(got.Arr[n]),
                    want.Items[n].AsString]));
                  Break;
                end;
          end
          else if (got.Kind <> avkNumber) or not SameBits(got.Num, want.AsString) then
            Miss(Format('%s %s %s t=%s: %s, upstream %s', [id, el.Strings['id'],
              reps[i].Keys[j], samples.Items[k].AsString, Hex(got.Num), want.AsString]));
        end;
        if el.Find('animators').JSONType = jtArray then
        begin
          anims := el.Arrays['animators'];
          if reps[i].Bag.AnimatorCount <> anims.Integers[k] then
            Miss(Format('%s %s t=%s: %d animators, upstream %d', [id, el.Strings['id'],
              samples.Items[k].AsString, reps[i].Bag.AnimatorCount, anims.Integers[k]]));
        end;
      end;
      if allCovered and (drv.ClipCount <> clips.Integers[k]) then
        Miss(Format('%s t=%s: %d clips, upstream %d', [id, samples.Items[k].AsString,
          drv.ClipCount, clips.Integers[k]]));
    end;
    Result := allCovered;
  finally
    for i := 0 to High(reps) do reps[i].Bag.Free;
    drv.Free;
    option.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestBarVerticalReplays;
const
  Ids: array[0..6] of string = ('bar-v.default', 'bar-v.override', 'bar-v.delayFn',
    'bar-v.durationFn', 'bar-v.elastic', 'bar-v.cubicBezier', 'bar-v.global');
var
  i, rep, skip: Integer;
begin
  for i := 0 to High(Ids) do
  begin
    AssertTrue(Ids[i] + ': every animated element replayed',
      ReplayCase(CaseById(Ids[i]), rep, skip));
    AssertEquals(Ids[i] + ': five bars', 5, rep);
  end;
  AssertTrue('every bar at every sample', FCompared >= 7 * 5 * 12);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' differ:' + FReport, 0, FBad);
end;

procedure TAdvChartAnimEngineTest.TestBarHorizontalAndStackedReplay;
const
  Ids: array[0..5] of string = ('bar-h.default', 'bar-h.override', 'bar-h.delayFn',
    'bar-stack.default', 'bar-stack.override', 'bar-stack.delayFn');
var
  i, rep, skip: Integer;
begin
  for i := 0 to High(Ids) do
  begin
    AssertTrue(Ids[i] + ': every animated element replayed',
      ReplayCase(CaseById(Ids[i]), rep, skip));
    AssertTrue(Ids[i] + ': the bars', rep >= 5);
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' differ:' + FReport, 0, FBad);
end;

procedure TAdvChartAnimEngineTest.TestEveryOtherPlainTrackReplays;
var
  cases: TJSONArray;
  i, rep, skip, total, full: Integer;
  c: TJSONObject;
  id, covered: string;
begin
  cases := Fixture.Arrays['cases'];
  total := 0;
  full := 0;
  covered := '';
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    id := c.Strings['id'];
    if (Copy(id, 1, 6) = 'bar-v.') or (Copy(id, 1, 6) = 'bar-h.')
      or (Copy(id, 1, 10) = 'bar-stack.') then Continue;
    if ReplayCase(c, rep, skip) and (rep > 0) then
    begin
      Inc(full);
      covered := covered + ' ' + id;
    end
    else
      covered := covered + Format(' [%s %d/%d]', [id, rep, skip]);
    Inc(total, rep);
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' differ:' + FReport, 0, FBad);
  AssertTrue('a good share of elements replayed: ' + IntToStr(total), total >= 180);
  AssertTrue('whole cases with their clip counts:' + covered, full >= 13);
end;

{ ==================== resolution ==================== }

function OptMatches(const AGot: TTyAnimOptValue; AWant: TJSONData): Boolean;
begin
  case AWant.JSONType of
    jtNull: Result := AGot.Kind in [aokUndefined, aokNull];
    jtNumber: Result := (AGot.Kind = aokNumber) and (AGot.Num = AWant.AsFloat);
    jtBoolean: Result := (AGot.Kind = aokBool) and ((AGot.Num <> 0) = AWant.AsBoolean);
    jtString: Result := (AGot.Kind = aokString) and (AGot.Str = AWant.AsString);
    jtObject: Result := (AGot.Kind = aokHandler)
      and (AGot.Str = TJSONObject(AWant).Strings['$fn']);
  else
    Result := False;
  end;
end;

procedure TAdvChartAnimEngineTest.TestResolutionMatchesEveryCase;
const
  Keys: array[0..7] of string = ('animation', 'animationThreshold',
    'animationDuration', 'animationEasing', 'animationDelay',
    'animationDurationUpdate', 'animationEasingUpdate', 'animationDelayUpdate');
  Fields: array[0..7] of string = ('animationOption', 'threshold', 'duration',
    'easing', 'delay', 'durationUpdate', 'easingUpdate', 'delayUpdate');
var
  cases, res: TJSONArray;
  c, r: TJSONObject;
  option: TJSONData;
  i, j, k, seen: Integer;
  model: TTyAnimModel;
begin
  cases := Fixture.Arrays['cases'];
  seen := 0;
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    option := c.Objects['option'].Clone;
    try
      ConvertFns(option);
      res := c.Arrays['resolved'];
      for j := 0 to res.Count - 1 do
      begin
        r := res.Objects[j];
        model := TyAnimSeriesModel(option, r.Integers['seriesIndex'], r.Integers['dataCount']);
        if model.TypeKey <> r.Strings['type'] then
          Miss(Format('%s series %d: type %s', [c.Strings['id'], j, model.TypeKey]));
        for k := 0 to High(Keys) do
        begin
          Inc(FCompared);
          if not OptMatches(TyAnimGetShallow(model, Keys[k]), r.Find(Fields[k])) then
            Miss(Format('%s series %d: %s', [c.Strings['id'], j, Keys[k]]));
        end;
        Inc(FCompared);
        if TyAnimIsEnabled(model) <> r.Booleans['enabled'] then
          Miss(Format('%s series %d: enabled %s', [c.Strings['id'], j,
            BoolToStr(TyAnimIsEnabled(model), True)]));
        Inc(seen);
      end;
    finally
      option.Free;
    end;
  end;
  AssertTrue('every series of every case', seen >= 67);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' differ:' + FReport, 0, FBad);
end;

procedure TAdvChartAnimEngineTest.TestThresholdCases;
const
  Ids: array[0..5] of string = ('threshold.above', 'threshold.equal',
    'threshold.rootAbove', 'threshold.rootOff', 'threshold.seriesOff',
    'threshold.zeroDuration');
  Enabled: array[0..5] of Boolean = (False, True, False, False, False, True);
var
  i, rep, skip: Integer;
  c: TJSONObject;
  option: TJSONData;
  model: TTyAnimModel;
  bag: TTyAnimBag;
  drv: TTyAnimation;
  timing: TTyAnimTiming;
begin
  for i := 0 to High(Ids) do
  begin
    c := CaseById(Ids[i]);
    option := c.Objects['option'].Clone;
    drv := TTyAnimation.Create;
    bag := TTyAnimBag.Create;
    try
      model := TyAnimSeriesModel(option, 0, c.Arrays['resolved'].Objects[0].Integers['dataCount']);
      AssertEquals(Ids[i] + ' enabled', Enabled[i], TyAnimIsEnabled(model));
      AssertEquals(Ids[i] + ' config', Enabled[i],
        TyAnimGetConfig(atEnter, model, TyAnimCallAt(0), timing));
      { a bar through initProps: a clip only where the fixture has clips }
      drv.Start(T0);
      bag.Animation := drv;
      bag.SetNum('shape.height', 0);
      TyInitProps(bag, TyAnimProps([TyAnimProp('shape.height', TyAnimNum(-40))]),
        model, TyAnimCallAt(0));
      drv.Update(T0);
      if (Ids[i] = 'threshold.seriesOff') or (c.Arrays['clips'].Integers[0] = 0) then
        AssertEquals(Ids[i] + ' the bar is static', 0, drv.ClipCount)
      else
        AssertEquals(Ids[i] + ' the bar animates', 1, drv.ClipCount);
      if drv.ClipCount = 0 then
        AssertEquals(Ids[i] + ' set at once', -40.0, bag.Num('shape.height'))
      else
        AssertEquals(Ids[i] + ' from the from value', 0.0, bag.Num('shape.height'));
    finally
      bag.Free;
      drv.Free;
      option.Free;
    end;
    ReplayCase(c, rep, skip);
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' differ:' + FReport, 0, FBad);
end;

procedure TAdvChartAnimEngineTest.TestTypeDefaultsAndRootChain;
var
  root: TJSONData;
  m: TTyAnimModel;
  v: TTyAnimOptValue;
begin
  root := GetJSON('{"animationEasing": "cubicOut", "animationDuration": 700,'
    + '"series": [{"type": "line"}, {"type": "bar", "animationEasing": null},'
    + '{"type": "candlestick", "animationDuration": null}]}');
  try
    m := TyAnimSeriesModel(root, 0, 3);
    v := TyAnimGetShallow(m, 'animationEasing');
    AssertEquals('a line''s default sits in the series option and beats the root',
      'linear', v.Str);
    AssertEquals('the root reaches a line''s duration', 700.0, TyAnimGetShallow(m, 'animationDuration').Num);
    m := TyAnimSeriesModel(root, 1, 3);
    AssertEquals('null falls through to the root', 'cubicOut',
      TyAnimGetShallow(m, 'animationEasing').Str);
    m := TyAnimSeriesModel(root, 2, 3);
    AssertEquals('a null key hides the type default too', 700.0,
      TyAnimGetShallow(m, 'animationDuration').Num);
    AssertEquals('the candlestick easing default', 'linear',
      TyAnimGetShallow(m, 'animationEasing').Str);
    AssertTrue('no delay anywhere is undefined',
      TyAnimGetShallow(m, 'animationDelay').Kind = aokUndefined);
    AssertEquals('update twin: the global 500', 500.0,
      TyAnimGetShallow(m, 'animationDurationUpdate').Num);
  finally
    root.Free;
  end;
end;

{ ==================== by hand ==================== }

procedure TAdvChartAnimEngineTest.TestClockStartsAtTheFirstStep;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('x', 0);
    cfg := TyAnimCfg(100, 0, 'linear');
    cfg.SetToFinal := True;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(10))]), cfg);
    AssertEquals('setToFinal: the final value at once', 10.0, bag.Num('x'));
    { the first step comes 40 ms after the animateTo: that is the start }
    drv.Update(T0 + 40);
    AssertEquals('the first frame writes the from value', 0.0, bag.Num('x'));
    AssertEquals(1, drv.ClipCount);
    drv.Update(T0 + 90);
    AssertEquals('half of the life after the first step', 5.0, bag.Num('x'));
    drv.Update(T0 + 139);
    AssertEquals(1, drv.ClipCount);
    drv.Update(T0 + 140);
    AssertEquals('finished at first step + life', 0, drv.ClipCount);
    AssertEquals(10.0, bag.Num('x'));
    AssertEquals('done takes it off the element', 0, bag.AnimatorCount);
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestDelayPhaseHoldsTheFromValue;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('x', 2);
    cfg := TyAnimCfg(100, 50, 'cubicOut');
    cfg.SetToFinal := True;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(12))]), cfg);
    drv.Update(T0);
    AssertEquals(2.0, bag.Num('x'));
    bag.SetNum('x', 99);
    drv.Update(T0 + 49);
    AssertEquals('the delay keeps writing the from value', 2.0, bag.Num('x'));
    drv.Update(T0 + 100);
    AssertEquals('(to - from) * cubicOut(0.5) + from', (12 - 2) * 0.875 + 2, bag.Num('x'));
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestStopTracksStepsBackToFrom;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('x', 0);
    cfg := TyAnimCfg(100, 0, 'linear');
    cfg.SetToFinal := True;
    cfg.Aborted := @OnAborted;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(100))]), cfg);
    AssertEquals(100.0, bag.Num('x'));
    AssertEquals(1, bag.AnimatorAt(0).Started);
    { a second animateTo before any frame: the first animator was started
      but never stepped, so its track steps back to 0 -- the from value --
      and the new tween runs 0 -> 150, not 100 -> 150 }
    cfg.Aborted := nil;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(150))]), cfg);
    AssertEquals('the first aborted', 1, FAbortedCount);
    AssertEquals('and off the element', 1, bag.AnimatorCount);
    AssertEquals(1, drv.ClipCount);
    drv.Update(T0);
    AssertEquals(0.0, bag.Num('x'));
    drv.Update(T0 + 50);
    AssertEquals('from 0, not from 100', 75.0, bag.Num('x'));
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestStopTracksAfterAFrameKeepsTheCurrentValue;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('x', 0);
    cfg := TyAnimCfg(100, 0, 'linear');
    cfg.SetToFinal := True;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(100))]), cfg);
    drv.Update(T0);
    drv.Update(T0 + 30);
    AssertEquals(30.0, bag.Num('x'));
    AssertEquals(2, bag.AnimatorAt(0).Started);
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(130))]), cfg);
    drv.Update(T0 + 30);
    AssertEquals('the new tween starts where the old one stood', 30.0, bag.Num('x'));
    drv.Update(T0 + 80);
    AssertEquals(80.0, bag.Num('x'));
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestStopForwardToLast;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('x', 0);
    cfg := TyAnimCfg(100, 0, 'linear');
    cfg.Done := @OnDone;
    cfg.Aborted := @OnAborted;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(100))]), cfg);
    drv.Update(T0);
    drv.Update(T0 + 10);
    bag.StopAnimation('', True);
    AssertEquals('forwarded to the last frame', 100.0, bag.Num('x'));
    AssertEquals('aborted, not done', 1, FAbortedCount);
    AssertEquals(0, FDoneCount);
    AssertEquals(0, drv.ClipCount);
    AssertEquals(0, bag.AnimatorCount);
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestLeaveTimingIgnoresTheOptions;
var
  root: TJSONData;
  model: TTyAnimModel;
  timing: TTyAnimTiming;
  opts: TTyAnimCallOpts;
  drv: TTyAnimation;
  bag: TTyAnimBag;
  rep, skip: Integer;
begin
  root := GetJSON('{"series": [{"type": "bar", "animationDurationUpdate": 300,'
    + '"animationEasingUpdate": "linear", "animationDelayUpdate": 100,'
    + '"animationDuration": 900, "animationEasing": "linear", "animationDelay": 70}]}');
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    model := TyAnimSeriesModel(root, 0, 1);
    AssertTrue(TyAnimGetConfig(atLeave, model, TyAnimCallAt(0), timing));
    AssertEquals('200 ms', 200.0, timing.Duration);
    AssertEquals('cubicOut', 'cubicOut', timing.Easing);
    AssertEquals('delay 0', 0.0, timing.Delay);
    AssertTrue(TyAnimGetConfig(atUpdate, model, TyAnimCallAt(0), timing));
    AssertEquals('update reads its twins', 300.0, timing.Duration);
    AssertEquals(100.0, timing.Delay);
    { a payload overrides even leave }
    opts := TyAnimCallAt(0);
    opts.HasPayload := True;
    opts.Payload.HasDuration := True;
    opts.Payload.Duration := 40;
    AssertTrue(TyAnimGetConfig(atLeave, model, opts, timing));
    AssertEquals(40.0, timing.Duration);
    { the fade: opacity 1 -> 0 over 200 ms cubicOut, then done }
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('style.opacity', 1);
    TyFadeOutElement(bag, model, 0, True, @OnDone);
    AssertEquals('leave is not set to final', 1.0, bag.Num('style.opacity'));
    drv.Update(T0);
    drv.Update(T0 + 100);
    AssertEquals((0 - 1) * 0.875 + 1, bag.Num('style.opacity'));
    AssertTrue('a leaving element is removed', bag.IsRemoved);
    TyFadeOutElement(bag, model, 0, True, @OnDone);
    AssertEquals('and is not faded twice', 1, bag.AnimatorCount);
    drv.Update(T0 + 200);
    AssertEquals(0.0, bag.Num('style.opacity'));
    AssertEquals('done once', 1, FDoneCount);
  finally
    bag.Free;
    drv.Free;
    root.Free;
  end;
  { and upstream's own leaving bar }
  ReplayCase(CaseById('bar-update.addremove'), rep, skip);
  AssertTrue('the leaving bar replayed', rep >= 1);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' differ:' + FReport, 0, FBad);
end;

procedure TAdvChartAnimEngineTest.TestZeroDurationSetsAtOnce;
var
  c: TJSONObject;
  option: TJSONData;
  model: TTyAnimModel;
  opts: TTyAnimCallOpts;
  drv: TTyAnimation;
  bag: TTyAnimBag;
begin
  c := CaseById('threshold.zeroDuration');
  option := c.Objects['option'].Clone;
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    model := TyAnimSeriesModel(option, 0, 6);
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('shape.height', 0);
    opts := TyAnimCallAt(2);
    opts.Done := @OnDone;
    opts.During := @OnDuring;
    TyInitProps(bag, TyAnimProps([TyAnimProp('shape.height', TyAnimNum(-62))]), model, opts);
    AssertEquals('no clip', 0, drv.ClipCount);
    AssertEquals('no animator', 0, bag.AnimatorCount);
    AssertEquals('set at once', -62.0, bag.Num('shape.height'));
    AssertEquals('during once', 1, Length(FDuring));
    AssertEquals('with 1', 1.0, FDuring[0]);
    AssertEquals('and done', 1, FDoneCount);
  finally
    bag.Free;
    drv.Free;
    option.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestLoopRestartKeepsThePhase;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  a: TTyAnimator;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('x', 0);
    a := bag.Animate('', True);
    a.WhenWithKeys(100, ['x'], [TyAnimNum(100)]);
    { a negative delay starts the loop mid-cycle, as the ripples do }
    a.Delay(-30);
    a.Start('linear');
    drv.Update(T0);
    AssertEquals('30 ms into the cycle at the first step', 30.0, bag.Num('x'));
    drv.Update(T0 + 75);
    AssertEquals('the cycle ends on its last frame', 100.0, bag.Num('x'));
    AssertEquals('a loop never finishes', 1, drv.ClipCount);
    drv.Update(T0 + 80);
    { restarted at T0 + 75 - (105 mod 100): 10 ms into the next cycle }
    AssertEquals('the phase is kept', 10.0, bag.Num('x'));
    drv.Update(T0 + 300);
    AssertEquals(100.0, bag.Num('x'));
    drv.Update(T0 + 301);
    AssertEquals('restarted at 300 - (230 mod 100) = 270', 31.0, bag.Num('x'));
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestFinalValueIsArithmeticNotSnapped;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('style.opacity', 0.7);
    bag.SetNum('shape.endAngle', 5.340707511102648);
    cfg := TyAnimCfg(100, 0, 'cubicInOut');
    cfg.SetToFinal := True;
    bag.AnimateTo(TyAnimProps([TyAnimProp('style.opacity', TyAnimNum(0.1)),
      TyAnimProp('shape.endAngle', TyAnimNum(1.2))]), cfg);
    AssertEquals('two animators: shape and style', 2, bag.AnimatorCount);
    drv.Update(T0);
    drv.Update(T0 + 100);
    AssertEquals('0.7 -> 0.1 rests at 0.09999999999999998', '3fb9999999999998',
      Hex(bag.Num('style.opacity')));
    AssertEquals('5.340707511102648 -> 1.2 rests at 1.2000000000000002',
      '3ff3333333333334', Hex(bag.Num('shape.endAngle')));
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestFloat32ArrayRoundsOnStore;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
  v: TTyAnimValue;
  want, third, w: Double;
begin
  { at run time: a constant expression may be folded in another precision }
  third := 1;
  third := third / 3;
  w := 100;
  w := w / 300;
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetAnimProp('shape.points', TyAnimArr([0, 0], 0, True));
    bag.SetAnimProp('shape.plain', TyAnimArr([0, 0]));
    cfg := TyAnimCfg(300, 0, 'linear');
    cfg.SetToFinal := True;
    { a typed target of the same length is NOT copied by setToFinal }
    bag.AnimateTo(TyAnimProps([
      TyAnimProp('shape.points', TyAnimArr([0.1, third], 0, True)),
      TyAnimProp('shape.plain', TyAnimArr([0.1, third]))]), cfg);
    v := bag.GetAnimProp('shape.points');
    AssertEquals('the typed quirk: still the old points', 0.0, v.Arr[0]);
    v := bag.GetAnimProp('shape.plain');
    AssertEquals('a plain array is copied', 0.1, v.Arr[0]);
    drv.Update(T0);
    drv.Update(T0 + 100);
    v := bag.GetAnimProp('shape.points');
    want := (third - 0) * w + 0;
    AssertTrue('still a Float32Array', v.Float32);
    AssertEquals('every store rounds to a single', Hex(TyJsFround(want)), Hex(v.Arr[1]));
    AssertFalse('which is not the double', TyJsFround(want) = want);
    v := bag.GetAnimProp('shape.plain');
    AssertEquals('a plain array keeps the double', Hex(want), Hex(v.Arr[1]));
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestColourInterpolatesToRgba;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetAnimProp('style.fill', TyAnimStr('#000000'));
    cfg := TyAnimCfg(100, 0, 'linear');
    bag.AnimateTo(TyAnimProps([TyAnimProp('style.fill', TyAnimStr('rgba(255,0,10,0.5)'))]), cfg);
    drv.Update(T0);
    AssertEquals('rgba(0,0,0,1)', bag.GetAnimProp('style.fill').Str);
    drv.Update(T0 + 50);
    AssertEquals('r, g, b floored, a as it prints', 'rgba(127,0,5,0.75)',
      bag.GetAnimProp('style.fill').Str);
    drv.Update(T0 + 100);
    AssertEquals('rgba(255,0,10,0.5)', bag.GetAnimProp('style.fill').Str);
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestDiscreteJumpsAndUnchangedKeysDrop;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetAnimProp('style.text', TyAnimStr('a'));
    bag.SetNum('x', 5);
    cfg := TyAnimCfg(100, 0, 'linear');
    cfg.Done := @OnDone;
    bag.AnimateTo(TyAnimProps([TyAnimProp('style.text', TyAnimStr('b'))]), cfg);
    AssertEquals('a discrete track jumps at the start', 'b', bag.GetAnimProp('style.text').Str);
    AssertEquals('no clip for it', 0, drv.ClipCount);
    AssertEquals('done at once', 1, FDoneCount);
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(5))]), cfg);
    AssertEquals('an unchanged key makes no animator', 0, bag.AnimatorCount);
    AssertEquals('and done is still called', 2, FDoneCount);
    cfg.Force := True;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(5))]), cfg);
    AssertEquals('force keeps it', 1, drv.ClipCount);
    drv.Update(T0);
    drv.Update(T0 + 100);
    AssertEquals(3, FDoneCount);
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestDuringGoesToTheFirstAnimatorOnly;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('x', 0);
    bag.SetNum('shape.width', 0);
    cfg := TyAnimCfg(100, 0, 'linear');
    cfg.During := @OnDuring;
    cfg.Done := @OnDone;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(10)),
      TyAnimProp('shape.width', TyAnimNum(20))]), cfg);
    AssertEquals(2, drv.ClipCount);
    AssertEquals('the nested object''s animator is made first', 'shape',
      bag.AnimatorAt(0).TargetName);
    drv.Update(T0);
    drv.Update(T0 + 50);
    AssertEquals('one during per frame', 2, Length(FDuring));
    AssertEquals(0.5, FDuring[1]);
    drv.Update(T0 + 100);
    AssertEquals('done once, when both finished', 1, FDoneCount);
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestLifeZeroIsAThousand;
var
  clip: TTyAnimClip;
  drv: TTyAnimation;
  bag: TTyAnimBag;
  a: TTyAnimator;
begin
  clip := TTyAnimClip.Create(0, NaN, False);
  try
    AssertEquals(1000.0, clip.Life);
    AssertEquals(0.0, clip.Delay);
  finally
    clip.Free;
  end;
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    a := bag.Animate('');
    a.Duration(0);
    a.Start('');
    AssertEquals('forced with no track and life 0: a 1000 ms clip', 1, drv.ClipCount);
    AssertEquals(1000.0, a.Clip.Life);
    drv.Update(T0);
    drv.Update(T0 + 999);
    AssertEquals(1, drv.ClipCount);
    drv.Update(T0 + 1000);
    AssertEquals(0, drv.ClipCount);
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestStopTracksSpliceSkipsTheNextAnimator;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  cfg: TTyAnimCfg;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    bag.SetNum('x', 0);
    bag.SetNum('y', 0);
    cfg := TyAnimCfg(100, 0, 'linear');
    cfg.Aborted := @OnAborted;
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(10))]), cfg);
    bag.AnimateTo(TyAnimProps([TyAnimProp('y', TyAnimNum(10))]), cfg);
    drv.Update(T0);
    AssertEquals(2, bag.AnimatorCount);
    { the first animator is aborted and spliced out while the walk goes on
      to index 1 -- which is now past the second: upstream never stops it }
    bag.AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(20)),
      TyAnimProp('y', TyAnimNum(20))]), TyAnimCfg(100, 0, 'linear'));
    AssertEquals('only the first was aborted', 1, FAbortedCount);
    AssertEquals('the skipped one still runs beside the new one', 2, bag.AnimatorCount);
    AssertEquals(2, drv.ClipCount);
  finally
    bag.Free;
    drv.Free;
  end;
end;

procedure TAdvChartAnimEngineTest.TestArraysAlignWithTheLastKeyframe;
var
  drv: TTyAnimation;
  bag: TTyAnimBag;
  v: TTyAnimValue;
begin
  drv := TTyAnimation.Create;
  bag := TTyAnimBag.Create;
  try
    drv.Start(T0);
    bag.Animation := drv;
    { no setToFinal: the element keeps its own (shorter) array }
    bag.SetAnimProp('shape.a', TyAnimArr([0, 0]));
    bag.SetAnimProp('shape.b', TyAnimArr([NaN, 0]));
    bag.AnimateTo(TyAnimProps([TyAnimProp('shape.a', TyAnimArr([10, 20, 30, 40])),
      TyAnimProp('shape.b', TyAnimArr([10, 20]))]), TyAnimCfg(100, 0, 'linear'));
    drv.Update(T0);
    drv.Update(T0 + 50);
    v := bag.GetAnimProp('shape.a');
    AssertEquals('the from array is padded with the last frame''s items', 4, Length(v.Arr));
    AssertEquals(5.0, v.Arr[0]);
    AssertEquals(30.0, v.Arr[2]);
    v := bag.GetAnimProp('shape.b');
    AssertEquals('a NaN takes the last frame''s item', 10.0, v.Arr[0]);
    AssertEquals(10.0, v.Arr[1]);
  finally
    bag.Free;
    drv.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartAnimEngineTest);
finalization
  FreeAndNil(GFixture);
end.
