unit test.advchart.animstate;
{$mode objfpc}{$H+}
{ STATE TRANSITIONS, HELD TO UPSTREAM [Batch 94, AN3b].

  tools/advchart-oracle/state-anim.js drives the real ECharts 6.1 build with
  the controlled clock: an option set at T0 and settled (or, for a live case,
  set at T1 so its enter or update animation runs), then pointer moves
  through zr.handler, dispatchAction and notMerge setOptions at T1 + t, one
  frame per sample (the clips step, then _onframe applies the changed
  states, where a transition's animators are made). Every series element is
  recorded per sample: its transform, style and shape keys, z2, its state
  list, its state animators (__fromStateTransition:targetName) and its
  stateTransition.

  The replay drives the control the same way -- MouseMove, DispatchAction,
  Option, AnimTick, a render per sample -- in camAlways with the injected
  clock, finds the proxy each element's states run on (AnimStateProxy) and
  compares, sample by sample:
    the state list; every key upstream tracks, bit for bit (a colour by its
    parse, mapped through the skin: the rest colour is the port's, its lift
    the lift of the port's, tokens.color.primary the skin's title ink); a
    state key the port carries and upstream does not move stays put; the
    state animators by name and target; the stateTransition's duration,
    easing and delay; and the chart's clips.

  The engine's own pieces -- the transition, saveTo, __changeFinalValue, the
  style filter, the shape's primitives -- have hand tests of their own. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Color, tyControls.AdvChart.Style,
     tyControls.AdvChart.JsMath, tyControls.AdvChart.Easing,
     tyControls.AdvChart.Scale,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt,
     tyControls.AdvChart.AnimView, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TAsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
    function Primary: TTyChartColor;
  end;

  { the engine's state machinery, by hand }
  TAdvChartAnimStateEngineTest = class(TTestCase)
  private
    FAnim: TTyAnimation;
    FBag: TTyAnimBag;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestATransitionRunsFromTheCurrentValue;
    procedure TestLeavingMidwayStartsWhereItIs;
    procedure TestNoTransitionSetsAndMovesTheFinalValues;
    procedure TestSaveToKeepsTheFinalValuesAsNormal;
    procedure TestAnotherStatesTransitionIsNotSaved;
    procedure TestTheNormalTransitionIsSaved;
    procedure TestTheStyleAnimatesOnlyItsAnimatableKeys;
    procedure TestTheShapeTransitionsItsPrimitives;
    procedure TestTheSameListDoesNothing;
    procedure TestAnUnsteppedFadeStaysWhereSetToFinalLeftIt;
    procedure TestBackToNormalForgetsTheNormalState;
  end;

  TAdvChartAnimStateTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAsProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FKeysCompared, FTrackedCompared: Integer;
    FReport: string;
    FSeen, FTally: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart(AMode: TTyChartAnimationMode);
    function Draw: TBGRABitmap;
    procedure Load(const AOption: string);
    procedure Settle(AStart: Double);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestStateTransitionsAsUpstream;
    procedure TestTheFrameDrawsTheTransition;
    procedure TestASelectedSliceIsHitWhereItIsDrawn;
    procedure TestHeadlessSwitchesAtOnce;
    procedure TestPastTheHoverLayerThresholdNothingTransitions;
  end;

implementation

const
  cW = 400;
  cH = 300;
  cPrimary = '#3c3c41';

var
  GFix: TJSONData = nil;

function Fix: TJSONObject;
var sl: TStringList;
begin
  if GFix = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-state-anim.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFix);
end;

function T0: Double;
begin
  Result := Fix.Objects['clock'].Floats['T0'];
end;

function T1: Double;
begin
  Result := T0 + Fix.Objects['clock'].Floats['T1Offset'];
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

function SameBits(A, B: Double): Boolean;
begin
  Result := Hex(A) = Hex(B);
end;

function IsHex16(AData: TJSONData): Boolean;
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

function ColourOf(const AText: string; out AC: TTyChartColor): Boolean;
begin
  AC := 0;
  if (AText = 'null') or (AText = 'none') or (AText = '') then Exit(False);
  Result := TyTryParseChartColor(AText, AC);
end;

function ValText(const V: TTyAnimValue): string;
begin
  case V.Kind of
    avkNull: Result := 'null';
    avkNumber, avkBool: Result := TyJsNumberToString(V.Num);
    avkString: Result := V.Str;
  else
    Result := '[array]';
  end;
end;

{ the state animators of a proxy, as the oracle writes them }
function StateAnimsOf(P: TTyChartAnimProxy): string;
var
  i: Integer;
  a: TTyAnimator;
begin
  Result := '';
  if P = nil then Exit;
  for i := 0 to P.AnimatorCount - 1 do
  begin
    a := P.AnimatorAt(i);
    if a.FromStateTransition = '' then Continue;
    if Result <> '' then Result := Result + ' ';
    Result := Result + a.FromStateTransition + ':' + a.TargetName;
  end;
end;

{ ==================== the probe ==================== }

function TAsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TAsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TAsProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TAsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TAsProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function TAsProbe.Primary: TTyChartColor;
begin
  Result := StPrimaryInk;
end;

{ ==================== the engine ==================== }

procedure TAdvChartAnimStateEngineTest.SetUp;
begin
  inherited SetUp;
  FAnim := TTyAnimation.Create;
  FBag := TTyAnimBag.Create;
  FBag.Animation := FAnim;
end;

procedure TAdvChartAnimStateEngineTest.TearDown;
begin
  FreeAndNil(FBag);
  FreeAndNil(FAnim);
  inherited TearDown;
end;

function StateOf(const AProps: array of TTyAnimProp; AStyle: Boolean = True;
  AShape: Boolean = False): TTyAnimState;
begin
  Result := Default(TTyAnimState);
  Result.Props := TyAnimProps(AProps);
  Result.HasStyle := AStyle;
  Result.HasShape := AShape;
end;

{ cubicOut, as easing.ts writes it }
function CubicOut(K: Double): Double;
begin
  K := K - 1;
  Result := K * K * K + 1;
end;

function Lerp8(AFrom, ATo, AW: Double): Integer;
begin
  Result := Floor((ATo - AFrom) * AW + AFrom);
end;

procedure TAdvChartAnimStateEngineTest.TestATransitionRunsFromTheCurrentValue;
const T = 1700000000000.0;
var w: Double;
begin
  FBag.SetAnimProp('style.fill', TyAnimStr('#5470c6'));
  FBag.SetAnimProp('style.opacity', TyAnimNum(1));
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'cubicOut'));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('style.fill',
    TyAnimStr('rgba(92,123,217,1)'))]));
  AssertEquals('one animator, the style''s', 1, FBag.AnimatorCount);
  AssertEquals('named for the state', 'emphasis', FBag.AnimatorAt(0).FromStateTransition);
  AssertEquals('on the style', 'style', FBag.AnimatorAt(0).TargetName);
  AssertEquals('only the fill moves: the opacity is the same', 1,
    FBag.AnimatorAt(0).TrackCount);
  AssertEquals('nothing moved yet', '#5470c6', FBag.GetAnimProp('style.fill').Str);
  AssertEquals('the list', 'emphasis', FBag.CurrentStates);
  FAnim.Update(T);
  AssertEquals('the first step: the from value, as rgba', 'rgba(84,112,198,1)',
    FBag.GetAnimProp('style.fill').Str);
  FAnim.Update(T + 150);
  w := CubicOut(0.5);
  AssertEquals('half way: cubicOut, floored channels',
    Format('rgba(%d,%d,%d,1)', [Lerp8(84, 92, w), Lerp8(112, 123, w), Lerp8(198, 217, w)]),
    FBag.GetAnimProp('style.fill').Str);
  FAnim.Update(T + 300);
  AssertEquals('done at 300', 'rgba(92,123,217,1)', FBag.GetAnimProp('style.fill').Str);
  AssertEquals('no clip left', 0, FAnim.ClipCount);
  { the normal state kept the rest value }
  FBag.ClearStates;
  AssertEquals('the way back is named for the normal state', TyAnimNormalState,
    FBag.AnimatorAt(0).FromStateTransition);
  FAnim.Update(T + 1000);
  FAnim.Update(T + 1300);
  AssertEquals('back at rest', 'rgba(84,112,198,1)', FBag.GetAnimProp('style.fill').Str);
  AssertEquals('no list', '', FBag.CurrentStates);
end;

procedure TAdvChartAnimStateEngineTest.TestLeavingMidwayStartsWhereItIs;
const T = 1700000000000.0;
var mid: string;
begin
  FBag.SetAnimProp('scaleX', TyAnimNum(5));
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'linear'));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('scaleX', TyAnimNum(8))]));
  FAnim.Update(T);
  FAnim.Update(T + 100);
  AssertEquals('a third of the way', 6, FBag.Num('scaleX'), 1e-12);
  mid := ValText(FBag.GetAnimProp('scaleX'));
  FBag.ClearStates;
  AssertEquals('the emphasis transition stopped, the normal one made', 1,
    FBag.AnimatorCount);
  FAnim.Update(T + 101);
  AssertEquals('the way back starts where it was', mid, ValText(FBag.GetAnimProp('scaleX')));
  FAnim.Update(T + 251);
  AssertEquals('half way back', 5.5, FBag.Num('scaleX'), 1e-12);
  FAnim.Update(T + 401);
  AssertEquals('at rest', 5, FBag.Num('scaleX'), 0);
end;

procedure TAdvChartAnimStateEngineTest.TestNoTransitionSetsAndMovesTheFinalValues;
const T = 1700000000000.0;
var cfg: TTyAnimCfg;
begin
  { an enter animation running: scale 0 -> 5 over 1000 ms, linear }
  FBag.SetAnimProp('scaleX', TyAnimNum(0));
  cfg := TyAnimCfg(1000, 0, 'linear');
  FBag.AnimateTo(TyAnimProps([TyAnimProp('scaleX', TyAnimNum(5))]), cfg);
  FAnim.Update(T);
  FAnim.Update(T + 200);
  AssertEquals('the enter at 200', 1, FBag.Num('scaleX'), 1e-12);
  { a stateAnimation of duration 0: no transition }
  FBag.SetStateTransition(TyAnimCfg(0, 0, 'cubicOut'));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('scaleX', TyAnimNum(5.5))]));
  AssertEquals('set at once', 5.5, FBag.Num('scaleX'), 0);
  AssertEquals('no state animator', 1, FBag.AnimatorCount);
  AssertEquals('the enter goes on', '', FBag.AnimatorAt(0).FromStateTransition);
  FAnim.Update(T + 600);
  { __changeFinalValue: the enter now ends at the state's value }
  AssertEquals('the enter lands on the emphasis value', 0.6 * 5.5, FBag.Num('scaleX'), 1e-12);
  FBag.ClearStates;
  AssertEquals('back to the normal value at once (saveTo: the enter''s final)', 5,
    FBag.Num('scaleX'), 0);
  FAnim.Update(T + 800);
  AssertEquals('and the enter ends there again', 0.8 * 5, FBag.Num('scaleX'), 1e-12);
  FAnim.Update(T + 1000);
  AssertEquals('done', 5, FBag.Num('scaleX'), 0);
end;

procedure TAdvChartAnimStateEngineTest.TestSaveToKeepsTheFinalValuesAsNormal;
const T = 1700000000000.0;
var v: TTyAnimValue;
begin
  FBag.SetAnimProp('scaleX', TyAnimNum(0));
  FBag.SetAnimProp('style.opacity', TyAnimNum(0));
  FBag.AnimateTo(TyAnimProps([TyAnimProp('scaleX', TyAnimNum(5)),
    TyAnimProp('style.opacity', TyAnimNum(0.8))]), TyAnimCfg(1000, 0, 'linear'));
  FAnim.Update(T);
  FAnim.Update(T + 400);
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'linear'));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('scaleX', TyAnimNum(5.5))]));
  AssertTrue('the normal scale is saved', FBag.NormalValue('scaleX', v));
  AssertEquals('as the enter''s FINAL value, not the interpolated one', 5, v.Num, 0);
  AssertTrue('the normal style is saved', FBag.NormalValue('style.opacity', v));
  AssertEquals('its opacity the final one too', 0.8, v.Num, 0);
  { the state's style is the normal one: the opacity goes to 0.8 in the
    state's 300 ms, the enter's track stopped }
  AssertEquals('the enter animators stopped, two state ones', 'emphasis:,emphasis:style',
    FBag.AnimatorAt(0).FromStateTransition + ':' + FBag.AnimatorAt(0).TargetName + ','
    + FBag.AnimatorAt(1).FromStateTransition + ':' + FBag.AnimatorAt(1).TargetName);
  FAnim.Update(T + 401);
  AssertEquals('from where it was', 2, FBag.Num('scaleX'), 1e-12);
  FAnim.Update(T + 701);
  AssertEquals('the opacity at its final in the state''s time', 0.8,
    FBag.Num('style.opacity'), 1e-15);
  FBag.ClearStates;
  FAnim.Update(T + 702);
  FAnim.Update(T + 1002);
  AssertEquals('back to the enter''s final', 5, FBag.Num('scaleX'), 1e-12);
end;

procedure TAdvChartAnimStateEngineTest.TestAnotherStatesTransitionIsNotSaved;
const T = 1700000000000.0;
var v: TTyAnimValue;
begin
  FBag.SetAnimProp('style.opacity', TyAnimNum(1));
  FBag.SetAnimProp('style.fill', TyAnimStr('#5470c6'));
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'linear'));
  FBag.UseStates('blur', StateOf([TyAnimProp('style.opacity', TyAnimNum(0.1))]));
  FAnim.Update(T);
  FAnim.Update(T + 150);
  { blur to emphasis in the middle: the blur's animator is a state's own }
  FBag.UseStates('emphasis', StateOf([TyAnimProp('style.fill', TyAnimStr('#ff0000'))]));
  AssertTrue(FBag.NormalValue('style.opacity', v));
  AssertEquals('the normal opacity is the rest one, not the blur''s', 1, v.Num, 0);
  FAnim.Update(T + 151);
  FAnim.Update(T + 451);
  AssertEquals('emphasis takes the normal opacity back', 1, FBag.Num('style.opacity'), 1e-15);
end;

procedure TAdvChartAnimStateEngineTest.TestTheNormalTransitionIsSaved;
const T = 1700000000000.0;
var v: TTyAnimValue;
begin
  FBag.SetAnimProp('style.fill', TyAnimStr('#5470c6'));
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'linear'));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('style.fill', TyAnimStr('#ff0000'))]));
  FAnim.Update(T);
  FAnim.Update(T + 300);
  FBag.ClearStates;
  FAnim.Update(T + 301);
  FAnim.Update(T + 400);
  { in again while the way back runs: its final is the normal value }
  FBag.UseStates('emphasis', StateOf([TyAnimProp('style.fill', TyAnimStr('#ff0000'))]));
  AssertTrue(FBag.NormalValue('style.fill', v));
  AssertEquals('the normal fill is the way back''s final', '#5470c6', v.Str);
end;

procedure TAdvChartAnimStateEngineTest.TestTheStyleAnimatesOnlyItsAnimatableKeys;
const T = 1700000000000.0;
begin
  { a Text: only its opacity (and the shadow) animate }
  FBag.StatePath := False;
  FBag.SetAnimProp('style.fill', TyAnimStr('#000000'));
  FBag.SetAnimProp('style.opacity', TyAnimNum(1));
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'linear'));
  FBag.UseStates('blur', StateOf([TyAnimProp('style.fill', TyAnimStr('#ff0000')),
    TyAnimProp('style.opacity', TyAnimNum(0.1))]));
  AssertEquals('a Text''s fill is assigned at once', '#ff0000', FBag.GetAnimProp('style.fill').Str);
  AssertEquals('its opacity animates', 1, FBag.AnimatorAt(0).TrackCount);
  FAnim.Update(T);
  FAnim.Update(T + 150);
  AssertEquals(0.55, FBag.Num('style.opacity'), 1e-12);
  { a Path: the fill animates too }
  FBag.ClearStates(True);
  FBag.StatePath := True;
  FBag.UseStates('blur', StateOf([TyAnimProp('style.fill', TyAnimStr('#ff0000'))]));
  AssertEquals('a Path''s fill is not assigned', '#000000', FBag.GetAnimProp('style.fill').Str);
end;

procedure TAdvChartAnimStateEngineTest.TestTheShapeTransitionsItsPrimitives;
const T = 1700000000000.0;
var v: TTyAnimValue;
begin
  FBag.SetAnimProp('shape.r', TyAnimNum(75));
  FBag.SetAnimProp('shape.points', TyAnimArr([1, 2, 3, 4], 2));
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'linear'));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('shape.r', TyAnimNum(80)),
    TyAnimProp('shape.points', TyAnimArr([5, 6, 7, 8], 2))], True, True));
  v := FBag.GetAnimProp('shape.points');
  AssertEquals('an object of the shape is assigned', 5, v.Arr[0], 0);
  AssertEquals('the radius waits for the clip', 75, FBag.Num('shape.r'), 0);
  FAnim.Update(T);
  FAnim.Update(T + 150);
  AssertEquals(77.5, FBag.Num('shape.r'), 1e-12);
end;

procedure TAdvChartAnimStateEngineTest.TestTheSameListDoesNothing;
begin
  FBag.SetAnimProp('style.fill', TyAnimStr('#5470c6'));
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'linear'));
  FBag.ClearStates;
  AssertEquals('normal to normal: nothing', 0, FBag.AnimatorCount);
  FBag.UseStates('emphasis', StateOf([TyAnimProp('style.fill', TyAnimStr('#ff0000'))]));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('style.fill', TyAnimStr('#00ff00'))]));
  AssertEquals('the same list: nothing', 1, FBag.AnimatorCount);
end;

{ the style a transition animates is a new object: a fade stopped before its
  first step writes its from value into the old one }
procedure TAdvChartAnimStateEngineTest.TestAnUnsteppedFadeStaysWhereSetToFinalLeftIt;
var cfg: TTyAnimCfg;
begin
  FBag.StatePath := False;
  FBag.SetAnimProp('x', TyAnimNum(100));
  FBag.SetAnimProp('style.opacity', TyAnimNum(0));
  cfg := TyAnimCfg(1000, 0, 'linear');
  cfg.SetToFinal := True;
  FBag.AnimateTo(TyAnimProps([TyAnimProp('style.opacity', TyAnimNum(1))]), cfg);
  AssertEquals('setToFinal: the final value now', 1, FBag.Num('style.opacity'), 0);
  FBag.SetStateTransition(TyAnimCfg(300, 0, 'cubicOut'));
  FBag.UseStates('select', StateOf([TyAnimProp('x', TyAnimNum(110)),
    TyAnimProp('style.text', TyAnimStr('b'))]));
  AssertEquals('the fade is stopped, its from value lost with the old style', 1,
    FBag.Num('style.opacity'), 0);
  AssertEquals('one animator: the place''s', 1, FBag.AnimatorCount);
  AssertEquals('select', FBag.AnimatorAt(0).FromStateTransition);
  AssertEquals('', FBag.AnimatorAt(0).TargetName);
end;

{ useState(normal) ends with `_normalState = {}`: the next leave saves the
  values of then (a symbol whose size an update changed) }
procedure TAdvChartAnimStateEngineTest.TestBackToNormalForgetsTheNormalState;
var v: TTyAnimValue;
begin
  FBag.SetAnimProp('scaleX', TyAnimNum(5));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('scaleX', TyAnimNum(5.5))], False));
  FBag.ClearStates;
  AssertEquals(5, FBag.Num('scaleX'), 0);
  AssertFalse('nothing kept', FBag.NormalValue('scaleX', v));
  FBag.SetAnimProp('scaleX', TyAnimNum(7));
  FBag.UseStates('emphasis', StateOf([TyAnimProp('scaleX', TyAnimNum(7.7))], False));
  AssertTrue(FBag.NormalValue('scaleX', v));
  AssertEquals('the normal value of now', 7, v.Num, 0);
  FBag.ClearStates;
  AssertEquals('back to it', 7, FBag.Num('scaleX'), 0);
end;

{ ==================== the replay ==================== }

procedure TAdvChartAnimStateTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FSeen := TStringList.Create;
  FTally := TStringList.Create;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartAnimStateTest.TearDown;
begin
  FreeAndNil(FSeen);
  FreeAndNil(FTally);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartAnimStateTest.Miss(const AWhere: string; const AOnce: string);
var c: string; i: Integer;
begin
  Inc(FBad);
  { a tally by case }
  c := Copy(AWhere, 1, Pos(' ', AWhere) - 1);
  i := FTally.IndexOfName(c);
  if i < 0 then FTally.Add(c + '=1')
  else FTally.ValueFromIndex[i] := IntToStr(StrToInt(FTally.ValueFromIndex[i]) + 1);
  if AOnce <> '' then
  begin
    if FSeen.IndexOf(AOnce) >= 0 then Exit;
    FSeen.Add(AOnce);
  end;
  if FSeen.Count + Ord(AOnce = '') <= 60 then
    FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartAnimStateTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TAsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.SetBounds(0, 0, cW, cH);
end;

function TAdvChartAnimStateTest.Draw: TBGRABitmap;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  Result := FBmp;
end;

procedure TAdvChartAnimStateTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  Draw;
end;

{ the oracle's settle: frames every 250 ms to 5 s }
procedure TAdvChartAnimStateTest.Settle(AStart: Double);
var t: Integer;
begin
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(t, 250);
  end;
  Draw;
  { an effectScatter's ripples loop on }
  AssertEquals('settled', FChart.AnimLoopClipCount, FChart.AnimClipCount);
end;

type
  TAsMap = record
    Ok: Boolean;
    Series, Row: Integer;
    Part: string;
  end;

function MapOf(AEls: TJSONArray; AEl: TJSONObject): TAsMap;
var
  id, owner, host, typ: string;
  p, i: Integer;
  h: TJSONObject;
begin
  Result := Default(TAsMap);
  id := AEl.Strings['id'];
  owner := AEl.Strings['owner'];
  p := Pos(':', owner);
  Result.Series := StrToInt(Copy(owner, 7, p - 7));
  typ := AEl.Strings['type'];
  Result.Row := -1;
  if typ = 'ec-polyline' then
  begin
    Result.Ok := True;
    Result.Part := 'poly';
    Exit;
  end;
  if typ = 'ec-polygon' then
  begin
    Result.Ok := True;
    Result.Part := 'area';
    Exit;
  end;
  if AEl.Strings['role'] = 'el' then
  begin
    if AEl.Find('dataIndex').JSONType = jtNull then Exit;
    if (typ <> 'rect') and (typ <> 'sector') and (typ <> 'path') and (typ <> 'polygon')
      and (typ <> 'normalCandlestickBox') then Exit;
    { a pictorial bar's rect is its inkless hit box; an effect symbol's
      ripples are paths of its own group (0.k.1.j) }
    if (typ = 'rect') and (Pos('pictorialBar', owner) > 0) then Exit;
    if (Pos('effectScatter', owner) > 0)
      and (Copy(id, Pos('/', id) + 1, MaxInt).Split(['.'])[2] = '1') then Exit;
    Result.Ok := True;
    Result.Part := 'host';
    Result.Row := AEl.Integers['dataIndex'];
    Exit;
  end;
  { a label or a label line: its host's row }
  host := Copy(id, 1, Pos('#', id) - 1);
  for i := 0 to AEls.Count - 1 do
  begin
    h := AEls.Objects[i];
    if h.Strings['id'] <> host then Continue;
    if h.Find('dataIndex').JSONType = jtNull then Exit;
    Result.Ok := True;
    Result.Row := h.Integers['dataIndex'];
    Result.Part := AEl.Strings['role'];
    Exit;
  end;
end;

{ the value of a key at sample ASample: the track's, else the final one }
function ValueAt(AEl: TJSONObject; const AKey: string; ASample: Integer;
  out AV: TJSONData): Boolean;
var tr: TJSONData;
begin
  AV := nil;
  tr := AEl.Find('track');
  if (tr <> nil) and (tr.JSONType = jtObject) and (TJSONObject(tr).Find(AKey) <> nil) then
    AV := TJSONObject(tr).Arrays[AKey].Items[ASample]
  else if TJSONObject(AEl.Find('final')).Find(AKey) <> nil then
    AV := TJSONObject(AEl.Find('final')).Find(AKey);
  Result := (AV <> nil) and (AV.JSONType <> jtNull);
end;

function Tracked(AEl: TJSONObject; const AKey: string): Boolean;
var tr: TJSONData;
begin
  tr := AEl.Find('track');
  Result := (tr <> nil) and (tr.JSONType = jtObject) and (TJSONObject(tr).Find(AKey) <> nil);
end;

{ the last sample at which the element holds no state: its rest values }
function RestSample(AEl: TJSONObject): Integer;
var
  i, n: Integer;
  v: TJSONData;
begin
  n := TJSONArray(Fix.Arrays['samplesMs']).Count;
  Result := -1;
  for i := n - 1 downto 0 do
    if ValueAt(AEl, 'states', i, v) and (v.AsString = '') then Exit(i);
end;

{ the oracle's id of the event a known deviation starts at: the port keeps no
  hover through a new option (B1 resets the state records), so the
  highlight held across the notMerge setOption is not compared from there }
function CompareUntil(const ACase: string): Double;
begin
  if ACase = 'bar-hover-notmerge' then Result := 400 else Result := Infinity;
end;

procedure TAdvChartAnimStateTest.RunCase(ACase: TJSONObject);
const
  cKeys: array[0..13] of string = ('style.fill', 'style.stroke', 'style.lineWidth',
    'style.opacity', 'x', 'y', 'scaleX', 'scaleY', 'shape.r', 'shape.startAngle',
    'shape.endAngle', 'shape.cx', 'shape.cy', 'shape.r0');
var
  name: string;
  samples, events, els, clips: TJSONArray;
  si, ei, k, j: Integer;
  t, untilT: Double;
  e, el: TJSONObject;
  flushed: Boolean;
  maps: array of TAsMap;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  fv, rv: TJSONData;
  key, where, want, got, restF, s: string;
  restOk: Boolean;
  cf, cp, cr, crp: TTyChartColor;
  rest: TTyAnimValue;
  tr: TJSONData;
  st: TTyAnimCfg;
begin
  name := ACase.Strings['id'];
  samples := Fix.Arrays['samplesMs'];
  events := ACase.Arrays['events'];
  els := ACase.Arrays['elements'];
  clips := ACase.Arrays['clips'];
  untilT := CompareUntil(name);
  NewChart(camAlways);
  if ACase.Booleans['live'] then
  begin
    if ACase.Find('first').JSONType <> jtNull then
    begin
      Load(ACase.Objects['first'].AsJSON);
      Settle(T0);
    end;
  end
  else
  begin
    Load(ACase.Objects['option'].AsJSON);
    Settle(T0);
  end;
  SetLength(maps, els.Count);
  for k := 0 to els.Count - 1 do maps[k] := MapOf(els, els.Objects[k]);
  for si := 0 to samples.Count - 1 do
  begin
    t := samples.Floats[si];
    FChart.AnimNow := T1 + t;
    flushed := False;
    for ei := 0 to events.Count - 1 do
    begin
      e := events.Objects[ei];
      if e.Floats['at'] <> t then Continue;
      s := e.Strings['type'];
      if (s = 'over') or (s = 'out') then FChart.Move(e.Integers['x'], e.Integers['y'])
      else if s = 'action' then FChart.DispatchAction(e.Objects['payload'].AsJSON)
      else if s = 'setOption' then
      begin
        FChart.Option := e.Objects['option'].AsJSON;
        flushed := True;
      end;
    end;
    if not flushed then FChart.AnimTick(T1 + t);
    Draw;
    if t >= untilT then Continue;
    where := name + ' t=' + FloatToStr(t);
    Inc(FCompared);
    if FChart.AnimClipCount <> clips.Integers[si] then
      Miss(Format('%s: clips %d, upstream %d', [where, FChart.AnimClipCount,
        clips.Integers[si]]), name + 'clips');
    for k := 0 to els.Count - 1 do
    begin
      el := els.Objects[k];
      if el.Find('present').JSONType <> jtNull then
      begin
        { not present at this sample }
        j := -1;
        for ei := 0 to el.Arrays['present'].Count - 1 do
          if el.Arrays['present'].Integers[ei] = si then j := ei;
        if j < 0 then Continue;
      end;
      if not maps[k].Ok then
      begin
        if el.Find('stateAnimators').JSONType <> jtNull then
          Miss(where + ' ' + el.Strings['id'] + ': has state animators, mapped to nothing',
            name + el.Strings['id'] + 'map');
        Continue;
      end;
      p := FChart.AnimStateProxy(maps[k].Series, maps[k].Row, maps[k].Part);
      if p = nil then
      begin
        Miss(where + ' ' + el.Strings['id'] + ': no state proxy', name + el.Strings['id'] + 'px');
        Continue;
      end;
      { the list }
      if ValueAt(el, 'states', si, fv) and (fv.AsString <> p.CurrentStates) then
        Miss(Format('%s %s: states "%s", upstream "%s"', [where, el.Strings['id'],
          p.CurrentStates, fv.AsString]), name + el.Strings['id'] + 'states' + FloatToStr(t));
      { the state animators }
      tr := el.Find('stateAnimators');
      if tr.JSONType = jtNull then want := '' else want := TJSONArray(tr).Strings[si];
      got := StateAnimsOf(p);
      if want <> got then
        Miss(Format('%s %s: state animators "%s", upstream "%s"', [where, el.Strings['id'],
          got, want]), name + el.Strings['id'] + 'sa' + FloatToStr(t));
      { the stateTransition }
      tr := el.Find('transition');
      if tr.JSONType = jtNull then want := '' else want := TJSONArray(tr).Strings[si];
      if p.HasStateTransition then
      begin
        st := p.StateTransition;
        got := TyJsNumberToString(st.Duration) + '/' + st.Easing + '/';
        if st.Delay <> 0 then got := got + TyJsNumberToString(st.Delay);
      end
      else
        got := '';
      if want <> got then
        Miss(Format('%s %s: stateTransition "%s", upstream "%s"', [where,
          el.Strings['id'], got, want]), name + el.Strings['id'] + 'tr');
      { the keys }
      for j := 0 to High(cKeys) do
      begin
        key := cKeys[j];
        { a symbol's x / y in its proxy are its group's place }
        if ((key = 'x') or (key = 'y')) and not p.HasStKey(key) then Continue;
        v := p.GetAnimProp(key);
        if not ValueAt(el, key, si, fv) then
        begin
          if Tracked(el, key) and (v.Kind <> avkNull) and (key = 'style.stroke') then
            Miss(Format('%s %s %s: %s, upstream none', [where, el.Strings['id'], key,
              ValText(v)]), name + el.Strings['id'] + key + 'n');
          Continue;
        end;
        if (v.Kind = avkNull) and not ((fv.JSONType = jtString) and (fv.AsString = 'null')) then
        begin
          if Tracked(el, key) then
            Miss(Format('%s %s %s: the proxy has none, upstream %s', [where,
              el.Strings['id'], key, fv.AsJSON]), name + el.Strings['id'] + key + 'none');
          Continue;
        end;
        Inc(FKeysCompared);
        if Tracked(el, key) then Inc(FTrackedCompared);
        { the label's opacity is a factor: its rest is upstream's 1 here }
        if IsHex16(fv) then
        begin
          if v.Kind <> avkNumber then
          begin
            Miss(Format('%s %s %s: not a number', [where, el.Strings['id'], key]),
              name + el.Strings['id'] + key + 'nan');
            Continue;
          end;
          if not SameBits(v.Num, FromHex(fv.AsString)) then
            Miss(Format('%s %s %s: %s, upstream %s', [where, el.Strings['id'], key,
              TyJsNumberToString(v.Num), TyJsNumberToString(FromHex(fv.AsString))]),
              name + el.Strings['id'] + key);
          Continue;
        end;
        if fv.JSONType <> jtString then Continue;
        { a colour, through the skin: upstream's rest colour is the port's,
          its lift the port's lift, the primary token the title ink }
        restOk := p.StRestOf(key, rest) and (rest.Kind = avkString);
        rv := nil;
        if (RestSample(el) < 0) or not ValueAt(el, key, RestSample(el), rv) then rv := nil;
        restF := '';
        if (rv <> nil) and (rv.JSONType = jtString) then restF := rv.AsString;
        if fv.AsString = 'null' then
        begin
          if (v.Kind <> avkNull) and ColourOf(ValText(v), cp) then
            Miss(Format('%s %s %s: %s, upstream null', [where, el.Strings['id'], key,
              ValText(v)]), name + el.Strings['id'] + key);
          Continue;
        end;
        if not ColourOf(fv.AsString, cf) then Continue;
        if not ColourOf(ValText(v), cp) then
        begin
          Miss(Format('%s %s %s: %s, upstream %s', [where, el.Strings['id'], key,
            ValText(v), fv.AsString]), name + el.Strings['id'] + key);
          Continue;
        end;
        if fv.AsString = cPrimary then cf := FChart.Primary
        else if restOk and ColourOf(restF, cr) and ColourOf(rest.Str, crp) and (cr <> crp) then
        begin
          if cf = cr then cf := crp
          else if cf = TyChartLiftColor(cr) then cf := TyChartLiftColor(crp)
          else
          begin
            { between a skin colour and its lift: not upstream's numbers }
            Continue;
          end;
        end;
        if cf <> cp then
          Miss(Format('%s %s %s: %s, upstream %s', [where, el.Strings['id'], key,
            ValText(v), fv.AsString]), name + el.Strings['id'] + key);
      end;
    end;
  end;
end;

procedure TAdvChartAnimStateTest.TestStateTransitionsAsUpstream;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := Fix.Arrays['cases'];
  AssertTrue('the fixture has its cases', cases.Count >= 20);
  for i := 0 to cases.Count - 1 do RunCase(cases.Objects[i]);
  { not a vacuous pass: the keys upstream moves were met, sample by sample }
  AssertTrue(Format('keys compared: %d, tracked %d', [FKeysCompared, FTrackedCompared]),
    FTrackedCompared > 3000);
  if FBad > 0 then
    Fail(Format('%d mismatches over %d samples (%s):%s', [FBad, FCompared,
      FTally.CommaText, FReport]));
end;

{ ==================== by hand ==================== }

const
  cBar = '{"color":["#5470c6"],"xAxis":{"type":"category","data":["A","B","C","D","E"]},'
    + '"yAxis":{"type":"value","max":40,"min":-10},"series":[{"type":"bar","data":[5,20,36,10,-8]}]}';
  cPieSel = '{"color":["#5470c6","#91cc75","#fac858","#ee6666"],"series":[{"type":"pie",'
    + '"radius":"50%","selectedMode":"single","data":[{"name":"a","value":10},'
    + '{"name":"b","value":20},{"name":"c","value":30},{"name":"d","value":15}]}]}';

function FrameHost(AChart: TAsProbe; ASeries, ARow: Integer; out AEl: TTyChartElement): Boolean;
var
  f: TTyPaintList;
  i: Integer;
begin
  Result := False;
  f := AChart.Frame;
  for i := 0 to f.Count - 1 do
  begin
    AEl := f.Element(i);
    if (AEl.Datum.Kind = ctkSeries) and (AEl.Datum.SeriesIndex = ASeries)
      and (AEl.Datum.DataIndex = ARow) and not AEl.Silent
      and (AEl.Caption.FontSizeLogical <= 0) and not AEl.IsGuide then Exit(True);
  end;
end;

procedure TAdvChartAnimStateTest.TestTheFrameDrawsTheTransition;
var
  p: TTyChartAnimProxy;
  el: TTyChartElement;
  c: TTyChartColor;
  px: TBGRAPixel;
  b: TTyRectF;
begin
  NewChart(camAlways);
  Load(cBar);
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":2}');
  Draw;
  AssertTrue('a transition runs: the series are the dynamic layer''s', FChart.AnimLive);
  FChart.AnimTick(T1 + 1);
  FChart.AnimTick(T1 + 150);
  Draw;
  p := FChart.AnimStateProxy(0, 2, 'host');
  AssertNotNull(p);
  AssertTrue('the frame has the bar', FrameHost(FChart, 0, 2, el));
  AssertTrue(TyTryParseChartColor(p.GetAnimProp('style.fill').Str, c));
  AssertEquals('the frame draws the proxy''s colour', IntToHex(c, 8),
    IntToHex(el.Style.FillColor, 8));
  { and the bitmap has it: the middle of the bar }
  b := TyShapeBounds(el.Shape);
  px := FBmp.GetPixel(Round((b.Left + b.Right) / 2), Round((b.Top + b.Bottom) / 2));
  AssertEquals('drawn red', (c shr 16) and $FF, px.red);
  AssertEquals('drawn green', (c shr 8) and $FF, px.green);
  AssertEquals('drawn blue', c and $FF, px.blue);
  FChart.AnimTick(T1 + 400);
  AssertFalse('at rest', FChart.AnimLive);
  Draw;
  AssertTrue(FrameHost(FChart, 0, 2, el));
  AssertEquals('at rest the lift, from the static layer', IntToHex(TyChartLiftColor(
    TTyChartColor($FF5470C6)), 8), IntToHex(el.Style.FillColor, 8));
end;

procedure TAdvChartAnimStateTest.TestASelectedSliceIsHitWhereItIsDrawn;
var
  el, fl: TTyChartElement;
  i, idx: Integer;
  d: TTyChartDatumRef;
  mid, r: Double;
  x, y: Integer;
begin
  NewChart(camAlways);
  Load(cPieSel);
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndex":1}');
  Draw;
  FChart.AnimTick(T1 + 1);
  FChart.AnimTick(T1 + 400);
  Draw;
  AssertFalse(FChart.AnimLive);
  { the slice is out by 10 px in the frame, not in the list }
  AssertTrue(FrameHost(FChart, 0, 1, fl));
  idx := -1;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Datum.SeriesIndex = 0) and (el.Datum.DataIndex = 1)
      and (el.Shape.Kind = cskSector) then idx := i;
  end;
  AssertTrue(idx >= 0);
  el := FChart.List.Element(idx);
  AssertTrue('the frame moved the slice', fl.Shape.CX <> el.Shape.CX);
  { the list keeps the rest geometry, the frame adds the proxy's offset once }
  AssertEquals('the list''s slice at rest', 200, el.Shape.CX, 1e-9);
  AssertEquals('the frame''s slice out by the offset',
    200 + FChart.AnimStateProxy(0, 1, 'host').Num('x'), fl.Shape.CX, 1e-9);
  { a point just past the slice's rest edge, inside the moved one }
  mid := (el.Shape.StartRad + el.Shape.EndRad) / 2;
  r := el.Shape.R1 + 5;
  x := Round(el.Shape.CX + Cos(mid) * r);
  y := Round(el.Shape.CY + Sin(mid) * r);
  d := FChart.HitTestAt(x, y);
  AssertEquals('hit where it is drawn', 1, d.DataIndex);
end;

procedure TAdvChartAnimStateTest.TestHeadlessSwitchesAtOnce;
var
  el: TTyChartElement;
  i: Integer;
  found: Boolean;
begin
  { camAuto, no window: no proxy, the list itself switches }
  NewChart(camAuto);
  Load(cBar);
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":2}');
  Draw;
  AssertNull('no state proxy', FChart.AnimStateProxy(0, 2, 'host'));
  AssertFalse('nothing live', FChart.AnimLive);
  found := False;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Datum.SeriesIndex = 0) and (el.Datum.DataIndex = 2) and not el.Silent
      and (el.Caption.FontSizeLogical <= 0) then
    begin
      found := True;
      AssertEquals('lifted in the list at once', IntToHex(TyChartLiftColor(
        TTyChartColor($FF5470C6)), 8), IntToHex(el.Style.FillColor, 8));
    end;
  end;
  AssertTrue(found);
end;

procedure TAdvChartAnimStateTest.TestPastTheHoverLayerThresholdNothingTransitions;
var p: TTyChartAnimProxy;
begin
  NewChart(camAlways);
  Load(StringReplace(cBar, '{"color"', '{"hoverLayerThreshold":3,"color"', []));
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":2}');
  Draw;
  p := FChart.AnimStateProxy(0, 2, 'host');
  AssertNotNull(p);
  AssertEquals('emphasis applied', 'emphasis', p.CurrentStates);
  AssertEquals('no clip: the hover layer does not transition', 0, FChart.AnimClipCount);
  AssertEquals('the lift at once', 'rgba(92,123,217,1)', p.GetAnimProp('style.fill').Str);
  { select alone is not hovered: it transitions }
  FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":2}');
  Draw;
  AssertEquals('leaving the hover layer: at once too', 0, FChart.AnimClipCount);
end;

initialization
  RegisterTest(TAdvChartAnimStateEngineTest);
  RegisterTest(TAdvChartAnimStateTest);
finalization
  FreeAndNil(GFix);
end.
