unit tyControls.AdvChart.Anim;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- zrender's animation engine: Clip, Track, Animator,
  Animation and Element.animateTo, transcribed. [Batch 87, AN1]

  THE MODEL. Everything that moves is a property tween on an element. One
  ANIMATOR per nested object -- the element itself (x, y, scaleX ...), its
  `shape`, its `style` -- holds one TRACK per property, and owns one CLIP,
  which carries the time: start, delay, life, loop and one easing for the
  whole clip. Per frame:

      percent = clamp((now - (tFirstStep + delay)) / life, 0, 1)
      w       = easing(percent)
      value   = (to - from) * w + from

  THE CLOCK STARTS AT THE FIRST STEP, not at animateTo. Upstream's setOption
  ends with a synchronous flush that steps every new clip at once, so each
  clip's start is the setOption instant and that same paint already shows
  the from values; the chart must call Update right after the pass that made
  the clips, not on the next timer tick (a tick later shifts every timeline
  by up to 16 ms).

  THE LAST FRAME IS ARITHMETIC. The step where percent reaches 1 writes
  (to - from) * easing(1) + from -- which for doubles is not always `to`
  (0.7 to 0.1 rests at 0.09999999999999998). Nothing here snaps to the target;
  an animated element rests where upstream's does, one unit in the last place
  off its layout value when upstream's is.

  THE TARGET IS A PROPERTY BAG. TTyAnimElement is the abstract element: it
  answers GetAnimProp / SetAnimProp by a dotted key -- 'x', 'rotation',
  'shape.height', 'style.opacity', 'shape.points' -- and the part before the
  first dot names the nested object, which is what upstream's targetName is.
  A value is a TTyAnimValue: a number, a flat number array (Stride > 0 marks
  a 2D array of rows of Stride numbers; Float32 marks a Float32Array, whose
  every store rounds to a single), a string (a colour string interpolates in
  rgba and is written back as 'rgba(r,g,b,a)' with r, g, b floored), a
  boolean, or null. AN2 binds a chart element by deriving from it;
  TTyAnimBag is a ready-made one keyed by name.

  WHAT IS NOT HERE: additive animation (only visualMap's continuous indicator
  uses it upstream), gradients, per-keyframe easing (ECharts never sets it),
  pause/resume (ECharts never pauses a series). A numeric STRING is
  interpolated as its number; upstream classifies it as a number too but then
  concatenates, which no chart relies on.

  STATES [Batch 94, AN3b]. zrender's useStates / clearStates on an element
  (Element.ts:952-1150, _applyStateObj with Displayable's and Path's): the
  values a state sets are saved into the element's NORMAL state when it
  leaves normal (only the root keys the state sets, the whole style, the whole
  shape -- and then every running animator that is not a state transition's
  own, or is the normal one's, writes its FINAL values there: saveTo), and
  each switch either TRANSITIONS -- the transform keys, the style keys
  getAnimationStyleProps names and the primitive shape keys animate to the
  target with the element's stateTransition -- or, without one, sets them and
  moves every running animator's last keyframe onto the new values
  (__changeFinalValue). The transitions' animators carry the state name
  (__fromStateTransition).

  LIFETIME. Upstream leans on the garbage collector; here an element owns
  every animator made on it, and an animator that has finished (done or
  aborted) goes to a graveyard that is emptied only when no engine call is on
  the stack -- a done callback may destroy the element whose animator is
  running it. Destroying an element detaches its animators from the driver
  first. Main thread only.

  FLOATING POINT. The engine's entry points mask the FPU traps, so a NaN or
  an infinity propagates the way it does in JavaScript; callbacks run inside
  that. }
interface
uses SysUtils, Classes, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Easing;

type
  TTyAnimValueKind = (avkNull, avkNumber, avkBool, avkString, avkArray);

  TTyAnimValue = record
    Kind: TTyAnimValueKind;
    { avkNumber; avkBool is 0 or 1 }
    Num: Double;
    { avkArray, flattened }
    Arr: TTyDoubleArray;
    { avkArray: 0 for a 1D array, else the length of each row of a 2D one }
    Stride: Integer;
    { avkArray, 1D: a Float32Array -- every store rounds to a single }
    Float32: Boolean;
    { avkString }
    Str: string;
  end;

  TTyAnimProp = record
    Key: string;
    Value: TTyAnimValue;
  end;
  TTyAnimProps = array of TTyAnimProp;

  TTyAnimNotify = procedure of object;
  TTyAnimDuring = procedure(APercent: Double) of object;

  TTyAnimation = class;
  TTyAnimator = class;
  TTyAnimElement = class;

  { ---- the time (animation/Clip.ts) ---- }
  TTyAnimClip = class
  private
    FLife, FDelay, FStartTime, FPausedTime: Double;
    FInited, FLoop: Boolean;
    FEasing: TTyEasing;
    FNext, FPrev: TTyAnimClip;
    FAnimation: TTyAnimation;
  public
    OnFrame: TTyAnimDuring;
    OnDestroy: TTyAnimNotify;
    OnRestart: TTyAnimNotify;
    { life 0 (or not-a-number) is 1000, as `opts.life || 1000`; a delay
      that is not a number is 0 }
    constructor Create(ALife, ADelay: Double; ALoop: Boolean);
    { Clip.step: True when the clip has finished. The first call fixes the
      start at AGlobalTime + delay. }
    function Step(AGlobalTime, ADeltaTime: Double): Boolean;
    procedure SetEasing(const AEasing: TTyEasing);
    property Life: Double read FLife;
    property Delay: Double read FDelay;
    property Loop: Boolean read FLoop;
    property Inited: Boolean read FInited;
    property StartTime: Double read FStartTime;
    property Easing: TTyEasing read FEasing;
    property Animation: TTyAnimation read FAnimation;
  end;

  TTyAnimValType = (vtNumber, vt1DArray, vt2DArray, vtColor, vtUnknown);

  TTyAnimKeyframe = record
    Time, Percent: Double;
    { parsed: a colour is its four rgba numbers }
    Value: TTyAnimValue;
    Raw: TTyAnimValue;
  end;

  { ---- one property (Animator.ts Track) ---- }
  TTyAnimTrack = class
  private
    FPropName: string;
    FKeyframes: array of TTyAnimKeyframe;
    FValType: TTyAnimValType;
    FDiscrete, FFinished, FNeedsSort, FInKeys: Boolean;
    FLastFr: Integer;
    FLastFrP: Double;
  public
    constructor Create(const APropName: string);
    procedure AddKeyframe(ATime: Double; const ARaw: TTyAnimValue);
    procedure Prepare(AMaxTime: Double);
    procedure Step(AAnimator: TTyAnimator; APercent: Double);
    function NeedsAnimate: Boolean;
    procedure SetFinished;
    function KeyframeCount: Integer;
    property PropName: string read FPropName;
    property ValType: TTyAnimValType read FValType;
    property Discrete: Boolean read FDiscrete;
    property Finished: Boolean read FFinished;
  end;

  TTyAnimCbKind = (ackDirty, ackRemove, ackUser);
  TTyAnimCb = record
    Kind: TTyAnimCbKind;
    Notify: TTyAnimNotify;
    During: TTyAnimDuring;
  end;

  { the done/aborted count of one animateTo (Element.ts:1837-1862) }
  TTyAnimGroup = class
  private
    FFinishCount, FRefs: Integer;
    FDoneHappened: Boolean;
    FDone, FAborted: TTyAnimNotify;
  public
    procedure AnimDone;
    procedure AnimAborted;
  end;

  { ---- one nested object (animation/Animator.ts) ---- }
  TTyAnimator = class
  private
    FElement: TTyAnimElement;
    FTargetName, FScope: string;
    FTracks: array of TTyAnimTrack;
    FTrackKeys: array of TTyAnimTrack;
    FRunTracks: array of TTyAnimTrack;
    FLoop, FAllowDiscrete, FForce: Boolean;
    FDelay, FMaxTime: Double;
    FStarted: Integer;
    FClip, FOwnedClip: TTyAnimClip;
    FAnimation: TTyAnimation;
    FDoneCbs, FAbortedCbs, FDuringCbs: array of TTyAnimCb;
    FGroups: array of TTyAnimGroup;
    FDead, FInGrave: Boolean;
    { __fromStateTransition: the state list a transition's animator was made
      for ('' for any other animator) [Batch 94] }
    FFromState: string;
    function FindTrack(const AProp: string): TTyAnimTrack;
    function FullKey(const AProp: string): string;
    procedure ClipFrame(APercent: Double);
    procedure ClipDestroy;
    procedure DoneCallback;
    procedure AbortedCallback;
    procedure SetTracksFinished;
    procedure CallList(const AList: array of TTyAnimCb);
    procedure MarkDead;
    procedure AddGroup(AGroup: TTyAnimGroup);
    function GetValue(const AProp: string): TTyAnimValue;
    procedure PutValue(const AProp: string; const AValue: TTyAnimValue);
  public
    constructor Create(AElement: TTyAnimElement; const ATargetName: string;
      ALoop, AAllowDiscrete: Boolean);
    destructor Destroy; override;
    { whenWithKeys: keyframes at ATime for AKeys, values from AValues
      (parallel to AKeys). A new track starts from the element's current
      value -- a keyframe at 0 when ATime > 0 -- and a key whose current
      value is null makes no track. }
    function WhenWithKeys(ATime: Double; const AKeys: array of string;
      const AValues: array of TTyAnimValue): TTyAnimator;
    function Delay(ATime: Double): TTyAnimator;
    { Run for ADuration whatever the tracks say, even with none; HasDuration
      False is upstream's undefined, which starts as 0. }
    function Duration(ADuration: Double; AHasDuration: Boolean = True): TTyAnimator;
    function During(ACb: TTyAnimDuring): TTyAnimator;
    function Done(ACb: TTyAnimNotify): TTyAnimator;
    function Aborted(ACb: TTyAnimNotify): TTyAnimator;
    procedure Start(const AEasing: TTyEasing); overload;
    procedure Start(const AEasing: string); overload;
    procedure Stop(AForwardToLast: Boolean = False);
    { True when the animator can no longer be used (every track finished,
      or it has no clip). A track stopped before the animator ever stepped
      (started, not run: setToFinal left the element at its final values)
      steps to 0 first, so the next animation reads the from value. }
    function StopTracks(const AKeys: array of string; AForwardToLast: Boolean = False): Boolean;
    function TrackCount: Integer;
    function TrackAt(AIndex: Integer): TTyAnimTrack;
    function GetTrack(const AProp: string): TTyAnimTrack;
    { Animator.saveTo: every unfinished track's LAST keyframe, raw, into
      AProps under its full key ('style.opacity'); a root key named in ASkip
      is left out [Batch 94] }
    procedure SaveTo(var AProps: TTyAnimProps; const ASkip: array of string);
    { Animator.__changeFinalValue: the last keyframe of each track named in
      AKeys (inner names) replaced by the value at its time, and the track
      prepared again; a track with a single keyframe is left [Batch 94] }
    procedure ChangeFinalValue(const AKeys: array of string;
      const AValues: array of TTyAnimValue);
    property Loop: Boolean read FLoop;
    property FromStateTransition: string read FFromState write FFromState;
    property Element: TTyAnimElement read FElement;
    property TargetName: string read FTargetName;
    property Scope: string read FScope write FScope;
    property Clip: TTyAnimClip read FClip;
    property MaxTime: Double read FMaxTime;
    property DelayTime: Double read FDelay;
    property Started: Integer read FStarted;
    property Animation: TTyAnimation read FAnimation;
  end;

  { ---- the frame driver (animation/Animation.ts) ---- }
  TTyAnimFrameEvent = procedure(ASender: TObject; ADelta: Double) of object;

  TTyAnimation = class
  private
    FHead, FTail: TTyAnimClip;
    FCount: Integer;
    FTime, FPausedTime: Double;
    FElements: TFPList;
    FOnWake: TNotifyEvent;
    FOnFrame: TTyAnimFrameEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddClip(AClip: TTyAnimClip);
    procedure RemoveClip(AClip: TTyAnimClip);
    procedure AddAnimator(AAnimator: TTyAnimator);
    procedure RemoveAnimator(AAnimator: TTyAnimator);
    { Animation.start: the clock's reference for the next delta. }
    procedure Start(ANow: Double);
    { Animation.update at ANow (absolute ms): every clip in list order, a
      finished one destroyed and unlinked; then the frame event unless
      ANoFrame. Call it right after the pass that created clips (the flush)
      and then on every tick. }
    procedure Update(ANow: Double; ANoFrame: Boolean = False);
    procedure Clear;
    function IsFinished: Boolean;
    { zrender's wakeUp: an animator was added -- the host's timer should run }
    procedure WakeUp;
    function ClipAt(AIndex: Integer): TTyAnimClip;
    property ClipCount: Integer read FCount;
    property Time: Double read FTime;
    property OnWake: TNotifyEvent read FOnWake write FOnWake;
    property OnFrame: TTyAnimFrameEvent read FOnFrame write FOnFrame;
  end;

  { animateTo's configuration (ElementAnimateConfig) }
  TTyAnimCfg = record
    Duration: Double;
    { False is upstream's undefined: 500 ms, and `force` then runs 0 }
    HasDuration: Boolean;
    Delay: Double;
    Easing: string;
    Force, SetToFinal: Boolean;
    Scope: string;
    Done, Aborted: TTyAnimNotify;
    During: TTyAnimDuring;
  end;

  { A STATE OBJECT as useStates merges it (Element._mergeStates and the
    Displayable / Path overrides), flattened: the keys the state sets --
    'x', 'scaleX', 'style.fill', 'shape.r' -- and whether it carries a
    style object and a shape object at all (a state without a style leaves
    the style to the normal state) [Batch 94] }
  TTyAnimState = record
    Props: TTyAnimProps;
    HasStyle, HasShape: Boolean;
  end;

  { ---- the element (zrender/src/Element.ts) ---- }
  TTyAnimElement = class
  private
    FAnimation: TTyAnimation;
    FAnimators: TFPList;
    FOwned: TFPList;
    { THE STATES [Batch 94]: _normalState (flattened, and whether its style
      and shape objects exist), currentStates joined, stateTransition, the
      root keys that are not this element's (a symbol's group position in
      the same bag), and whether it is a Path (fill, stroke ... animate) }
    FNormal: TTyAnimProps;
    FNormalStyle, FNormalShape: Boolean;
    FCurStates: string;
    FStateCfg: TTyAnimCfg;
    FHasStateCfg: Boolean;
    FStateSkip: array of string;
    FStatePath: Boolean;
    procedure SetAnimation(AValue: TTyAnimation);
    procedure AddAnimator(AAnimator: TTyAnimator);
    procedure RemoveFromList(AAnimator: TTyAnimator);
    procedure DoAnimateTo(const AProps: TTyAnimProps; const ACfg: TTyAnimCfg;
      AReverse: Boolean; const AStateName: string = '';
      AStyleFilter: Boolean = False);
    procedure Shallow(const ATopKey: string; const AKeys: array of string;
      const AValues: array of TTyAnimValue; const ACfg: TTyAnimCfg;
      AReverse, AFilter: Boolean; var AList: TFPList);
    function InStateSkip(const AKey: string): Boolean;
    function HasAnimKey(const AKey: string): Boolean;
    procedure SaveCurrentToNormal(const AState: TTyAnimState);
    procedure ApplyStateObj(const AName: string; AHasState: Boolean;
      const AState: TTyAnimState; ATransition: Boolean);
    function CanTransition(ANoAnimation: Boolean): Boolean;
    procedure StopTracksDetached(const ATopKey: string; const AProps: TTyAnimProps);
  protected
    { upstream's updateDuringAnimation / markRedraw: ATargetName changed }
    procedure AnimDirty(const ATargetName: string); virtual;
  public
    constructor Create;
    destructor Destroy; override;
    { The property bag. A missing key is avkNull. }
    function GetAnimProp(const AKey: string): TTyAnimValue; virtual; abstract;
    procedure SetAnimProp(const AKey: string; const AValue: TTyAnimValue); virtual; abstract;
    { Element.animate: a bare animator on ATargetName ('' the element). }
    function Animate(const ATargetName: string; ALoop: Boolean = False;
      AAllowDiscrete: Boolean = False): TTyAnimator;
    procedure AnimateTo(const AProps: TTyAnimProps; const ACfg: TTyAnimCfg);
    { AProps are the FROM values; the current values are the target }
    procedure AnimateFrom(const AProps: TTyAnimProps; const ACfg: TTyAnimCfg);
    { Stop the animators of AScope ('' all), each at its last frame when
      AForwardToLast. }
    procedure StopAnimation(const AScope: string = ''; AForwardToLast: Boolean = False);
    { set directly (Element.attr) }
    procedure Attr(const AProps: TTyAnimProps);
    function AnimatorCount: Integer;
    function AnimatorAt(AIndex: Integer): TTyAnimator;
    { basicTransition's isElementRemoved: no driver, or a 'leave' animator }
    function IsRemoved: Boolean;
    { every key the element holds, for the normal state's style and shape
      clones (TTyAnimBag answers its own) [Batch 94] }
    function AnimKeyList: TTyStringArray; virtual;
    { ---- states [Batch 94] ---- }
    { el.stateTransition: a duration of 0 or less transitions nothing }
    procedure SetStateTransition(const ACfg: TTyAnimCfg);
    procedure ClearStateTransition;
    { useStates(list): AName is the list joined (the transitions' animator
      name); the same list as now does nothing. ANoAnimation: no transition
      whatever the stateTransition (useStates' noAnimation, and an element
      in the hover layer) }
    procedure UseStates(const AName: string; const AState: TTyAnimState;
      ANoAnimation: Boolean = False);
    { clearStates: back to the normal state, which is then forgotten }
    procedure ClearStates(ANoAnimation: Boolean = False);
    { the normal state's value of a key; False when it holds none }
    function NormalValue(const AKey: string; out AValue: TTyAnimValue): Boolean;
    { root keys outside this element's states: not saved, not restored }
    procedure SetStateSkip(const AKeys: array of string);
    property CurrentStates: string read FCurStates;
    property HasStateTransition: Boolean read FHasStateCfg;
    property StateTransition: TTyAnimCfg read FStateCfg;
    property NormalHasStyle: Boolean read FNormalStyle;
    property NormalHasShape: Boolean read FNormalShape;
    { a Path (its fill, stroke, width ... animate), else a Text (opacity and
      the shadow only); True by default }
    property StatePath: Boolean read FStatePath write FStatePath;
    property Animation: TTyAnimation read FAnimation write SetAnimation;
  end;

  { A ready-made element: a bag of named values. }
  TTyAnimBag = class(TTyAnimElement)
  private
    FKeys: array of string;
    FValues: array of TTyAnimValue;
    FDirtyCount: Integer;
    function IndexOfKey(const AKey: string): Integer;
  protected
    procedure AnimDirty(const ATargetName: string); override;
  public
    function GetAnimProp(const AKey: string): TTyAnimValue; override;
    procedure SetAnimProp(const AKey: string; const AValue: TTyAnimValue); override;
    function AnimKeyList: TTyStringArray; override;
    function Num(const AKey: string): Double;
    procedure SetNum(const AKey: string; AValue: Double);
    property DirtyCount: Integer read FDirtyCount;
  end;

{ ---- values ---- }
function TyAnimNull: TTyAnimValue;
function TyAnimNum(AValue: Double): TTyAnimValue;
function TyAnimBool(AValue: Boolean): TTyAnimValue;
function TyAnimStr(const AValue: string): TTyAnimValue;
function TyAnimArr(const AValues: array of Double; AStride: Integer = 0;
  AFloat32: Boolean = False): TTyAnimValue;
{ a deep copy -- a record copy shares its dynamic array }
function TyAnimClone(const AValue: TTyAnimValue): TTyAnimValue;
function TyAnimProp(const AKey: string; const AValue: TTyAnimValue): TTyAnimProp;
function TyAnimProps(const AProps: array of TTyAnimProp): TTyAnimProps;
{ Element.ts isValueSame: ===, or two 1D arrays equal item by item (a 2D
  array is never the same unless both are empty) }
function TyAnimValueSame(const A, B: TTyAnimValue): Boolean;
{ rgba2String: r, g, b floored (a NaN or minus nought is 0), a as it prints }
function TyAnimRgbaString(AR, AG, AB, AA: Double): string;

{ A cfg: HasDuration True, no force, no setToFinal. }
function TyAnimCfg(ADuration, ADelay: Double; const AEasing: string): TTyAnimCfg;

const
  { the state name clearStates transitions under (PRESERVED_NORMAL_STATE) }
  TyAnimNormalState = '__zr_normal__';

{ a key of a flattened prop list: its index, -1 for none [Batch 94] }
function TyAnimPropIndex(const AProps: TTyAnimProps; const AKey: string): Integer;
{ set (or add at the end) a key of a flattened prop list }
procedure TyAnimPropPut(var AProps: TTyAnimProps; const AKey: string;
  const AValue: TTyAnimValue);
{ createStyle's prototype (DEFAULT_PATH_STYLE over DEFAULT_COMMON_STYLE): the
  default of a style key (inner name); False for a key it has none of }
function TyAnimStyleDefault(const AKey: string; out AValue: TTyAnimValue): Boolean;

{ The chart clock: epoch milliseconds, whole, from a monotonic source --
  upstream's `new Date().getTime()`. The epoch base matters to the bits: a
  fractional delay is rounded where startTime = now + delay is a double near
  1.7e12. }
function TyAnimClockMs: Double;

implementation

uses DateUtils, tyControls.AdvChart.JsMath, tyControls.AdvChart.Color,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Data;

var
  GBusy: Integer = 0;
  GGrave: TFPList = nil;
  GClockBase: Double = 0;
  GClockTick: QWord = 0;
  GClockInited: Boolean = False;

{ ==================== floating point and the graveyard ==================== }

type
  TEngineGuard = record
    Mask: TFPUExceptionMask;
  end;

procedure FreeAnimator(A: TTyAnimator); forward;

procedure FlushGrave;
var
  list: TFPList;
  i: Integer;
begin
  if (GBusy > 0) or (GGrave = nil) or (GGrave.Count = 0) then Exit;
  Inc(GBusy);
  try
    while GGrave.Count > 0 do
    begin
      list := GGrave;
      GGrave := TFPList.Create;
      try
        for i := 0 to list.Count - 1 do
          FreeAnimator(TTyAnimator(list[i]));
      finally
        list.Free;
      end;
    end;
  finally
    Dec(GBusy);
  end;
end;

function EnterEngine: TEngineGuard;
begin
  Result.Mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  Inc(GBusy);
end;

procedure LeaveEngine(const AGuard: TEngineGuard);
begin
  Dec(GBusy);
  if GBusy = 0 then FlushGrave;
  if GBusy = 0 then
  begin
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
  end;
  SetExceptionMask(AGuard.Mask);
end;

procedure Bury(A: TTyAnimator);
begin
  if A.FInGrave then Exit;
  A.FInGrave := True;
  if GGrave = nil then GGrave := TFPList.Create;
  GGrave.Add(A);
end;

procedure FreeAnimator(A: TTyAnimator);
begin
  if A.FElement <> nil then
  begin
    A.FElement.FAnimators.Remove(A);
    A.FElement.FOwned.Remove(A);
    A.FElement := nil;
  end;
  A.Free;
end;

{ JavaScript's `x || 0` for a number }
function OrZero(AV: Double): Double; inline;
begin
  if IsNan(AV) or (AV = 0) then Result := 0 else Result := AV;
end;

{ Math.max(a, b) }
function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

{ ==================== values ==================== }

function TyAnimNull: TTyAnimValue;
begin
  Result := Default(TTyAnimValue);
  Result.Kind := avkNull;
end;

function TyAnimNum(AValue: Double): TTyAnimValue;
begin
  Result := Default(TTyAnimValue);
  Result.Kind := avkNumber;
  Result.Num := AValue;
end;

function TyAnimBool(AValue: Boolean): TTyAnimValue;
begin
  Result := Default(TTyAnimValue);
  Result.Kind := avkBool;
  if AValue then Result.Num := 1 else Result.Num := 0;
end;

function TyAnimStr(const AValue: string): TTyAnimValue;
begin
  Result := Default(TTyAnimValue);
  Result.Kind := avkString;
  Result.Str := AValue;
end;

function TyAnimArr(const AValues: array of Double; AStride: Integer;
  AFloat32: Boolean): TTyAnimValue;
var i: Integer;
begin
  Result := Default(TTyAnimValue);
  Result.Kind := avkArray;
  SetLength(Result.Arr, Length(AValues));
  for i := 0 to High(AValues) do Result.Arr[i] := AValues[i];
  Result.Stride := AStride;
  Result.Float32 := AFloat32 and (AStride = 0);
end;

function TyAnimClone(const AValue: TTyAnimValue): TTyAnimValue;
begin
  Result := AValue;
  Result.Arr := Copy(AValue.Arr);
end;

function TyAnimProp(const AKey: string; const AValue: TTyAnimValue): TTyAnimProp;
begin
  Result.Key := AKey;
  Result.Value := TyAnimClone(AValue);
end;

function TyAnimProps(const AProps: array of TTyAnimProp): TTyAnimProps;
var i: Integer;
begin
  SetLength(Result, Length(AProps));
  for i := 0 to High(AProps) do
  begin
    Result[i].Key := AProps[i].Key;
    Result[i].Value := TyAnimClone(AProps[i].Value);
  end;
end;

function TyAnimValueSame(const A, B: TTyAnimValue): Boolean;
var i: Integer;
begin
  Result := False;
  if A.Kind <> B.Kind then Exit;
  case A.Kind of
    avkNull: Result := True;
    avkNumber, avkBool: Result := A.Num = B.Num;
    avkString: Result := A.Str = B.Str;
    avkArray:
      begin
        if Length(A.Arr) <> Length(B.Arr) then Exit;
        { a 2D array's items are rows, compared by reference upstream }
        if ((A.Stride > 0) or (B.Stride > 0)) then Exit(Length(A.Arr) = 0);
        for i := 0 to High(A.Arr) do
          if not (A.Arr[i] = B.Arr[i]) then Exit;
        Result := True;
      end;
  end;
end;

function JsFloor(AV: Double): Double;
begin
  if IsNan(AV) or IsInfinite(AV) then Exit(AV);
  Result := Int(AV);
  if Result > AV then Result := Result - 1;
end;

function TyAnimRgbaString(AR, AG, AB, AA: Double): string;
begin
  Result := 'rgba(' + TyJsNumberToString(OrZero(JsFloor(AR))) + ','
    + TyJsNumberToString(OrZero(JsFloor(AG))) + ','
    + TyJsNumberToString(OrZero(JsFloor(AB))) + ','
    + TyJsNumberToString(AA) + ')';
end;

function TyAnimCfg(ADuration, ADelay: Double; const AEasing: string): TTyAnimCfg;
begin
  Result := Default(TTyAnimCfg);
  Result.Duration := ADuration;
  Result.HasDuration := True;
  Result.Delay := ADelay;
  Result.Easing := AEasing;
end;

function TyAnimClockMs: Double;
var t: QWord;
begin
  t := GetTickCount64;
  if not GClockInited then
  begin
    GClockBase := Double(DateTimeToUnix(Now, False)) * 1000;
    GClockTick := t;
    GClockInited := True;
  end;
  Result := GClockBase + Double(Int64(t - GClockTick));
end;

{ ==================== Clip ==================== }

constructor TTyAnimClip.Create(ALife, ADelay: Double; ALoop: Boolean);
begin
  inherited Create;
  if IsNan(ALife) or (ALife = 0) then FLife := 1000 else FLife := ALife;
  FDelay := OrZero(ADelay);
  FLoop := ALoop;
  FEasing := TyEasingNone;
end;

procedure TTyAnimClip.SetEasing(const AEasing: TTyEasing);
begin
  FEasing := AEasing;
end;

function TTyAnimClip.Step(AGlobalTime, ADeltaTime: Double): Boolean;
var
  elapsed, percent, schedule, remainder: Double;
begin
  if not FInited then
  begin
    FStartTime := AGlobalTime + FDelay;
    FInited := True;
  end;
  elapsed := AGlobalTime - FStartTime - FPausedTime;
  percent := elapsed / FLife;
  if percent < 0 then percent := 0;
  { Math.min(percent, 1): a not-a-number stays one }
  if percent > 1 then percent := 1;
  if FEasing.Kind = ekNone then schedule := percent
  else schedule := TyEasingApply(FEasing, percent);
  if Assigned(OnFrame) then OnFrame(schedule);
  if percent = 1 then
  begin
    if FLoop then
    begin
      remainder := TyJsFMod(elapsed, FLife);
      FStartTime := AGlobalTime - remainder;
      FPausedTime := 0;
      if Assigned(OnRestart) then OnRestart();
    end
    else
      Exit(True);
  end;
  Result := False;
end;

{ ==================== Track ==================== }

constructor TTyAnimTrack.Create(const APropName: string);
begin
  inherited Create;
  FPropName := APropName;
  FValType := vtUnknown;
end;

function TTyAnimTrack.NeedsAnimate: Boolean;
begin
  Result := Length(FKeyframes) >= 1;
end;

procedure TTyAnimTrack.SetFinished;
begin
  FFinished := True;
end;

function TTyAnimTrack.KeyframeCount: Integer;
begin
  Result := Length(FKeyframes);
end;

procedure TTyAnimTrack.AddKeyframe(ATime: Double; const ARaw: TTyAnimValue);
var
  len: Integer;
  isDiscrete: Boolean;
  vt: TTyAnimValType;
  value: TTyAnimValue;
  n, r, g, b, a: Double;
begin
  FNeedsSort := True;
  len := Length(FKeyframes);
  isDiscrete := False;
  vt := vtUnknown;
  value := TyAnimClone(ARaw);
  case ARaw.Kind of
    avkArray:
      begin
        { guessArrayDim: 2 when the first item is itself an array }
        if (ARaw.Stride > 0) and (Length(ARaw.Arr) > 0) then vt := vt2DArray
        else vt := vt1DArray;
        { not a number array: an empty one has no first number }
        if Length(ARaw.Arr) = 0 then isDiscrete := True;
      end;
    avkNumber:
      if not IsNan(ARaw.Num) then vt := vtNumber;
    avkString:
      begin
        n := TyJsToNumber(ARaw.Str);
        if not IsNan(n) then
        begin
          vt := vtNumber;
          value := TyAnimNum(n);
        end
        else if TyTryParseCssRgba(ARaw.Str, r, g, b, a) then
        begin
          vt := vtColor;
          value := TyAnimArr([r, g, b, a]);
        end;
      end;
  end;
  if len = 0 then
    FValType := vt
  else if (vt <> FValType) or (vt = vtUnknown) then
    isDiscrete := True;
  FDiscrete := FDiscrete or isDiscrete;
  SetLength(FKeyframes, len + 1);
  FKeyframes[len].Time := ATime;
  FKeyframes[len].Percent := 0;
  FKeyframes[len].Value := value;
  FKeyframes[len].Raw := TyAnimClone(ARaw);
end;

{ fillArray: align an earlier keyframe's array with the last one's -- cut a
  longer one, pad a shorter one with the last frame's items, and take the
  last frame's item for a NaN }
procedure FillArray(var A0: TTyAnimValue; const A1: TTyAnimValue; ADim: Integer);
var
  len0, len1, i, j, stride, rows0, rows1: Integer;
begin
  if ADim = 1 then
  begin
    len0 := Length(A0.Arr);
    len1 := Length(A1.Arr);
    if len0 <> len1 then
    begin
      SetLength(A0.Arr, len1);
      for i := len0 to len1 - 1 do A0.Arr[i] := A1.Arr[i];
    end;
    for i := 0 to High(A0.Arr) do
      if IsNan(A0.Arr[i]) and (i < Length(A1.Arr)) then A0.Arr[i] := A1.Arr[i];
  end
  else
  begin
    stride := A1.Stride;
    if (stride <= 0) or (A0.Stride <> stride) then Exit;
    rows0 := Length(A0.Arr) div stride;
    rows1 := Length(A1.Arr) div stride;
    if rows0 <> rows1 then
    begin
      SetLength(A0.Arr, rows1 * stride);
      for i := rows0 * stride to rows1 * stride - 1 do A0.Arr[i] := A1.Arr[i];
    end;
    { len2 = arr0[0].length: nothing when arr0 has no rows }
    if Length(A0.Arr) > 0 then
      for i := 0 to (Length(A0.Arr) div stride) - 1 do
        for j := 0 to stride - 1 do
          if IsNan(A0.Arr[i * stride + j]) then
            A0.Arr[i * stride + j] := A1.Arr[i * stride + j];
  end;
end;

procedure TTyAnimTrack.Prepare(AMaxTime: Double);
var
  i, j, n: Integer;
  tmp: TTyAnimKeyframe;
  last: TTyAnimValue;
begin
  n := Length(FKeyframes);
  if FNeedsSort then
    { Array.prototype.sort is stable: insertion sort by time }
    for i := 1 to n - 1 do
    begin
      tmp := FKeyframes[i];
      j := i - 1;
      while (j >= 0) and (FKeyframes[j].Time - tmp.Time > 0) do
      begin
        FKeyframes[j + 1] := FKeyframes[j];
        Dec(j);
      end;
      FKeyframes[j + 1] := tmp;
    end;
  if n = 0 then Exit;
  last := FKeyframes[n - 1].Value;
  for i := 0 to n - 1 do
  begin
    FKeyframes[i].Percent := FKeyframes[i].Time / AMaxTime;
    if (not FDiscrete) and (FValType in [vt1DArray, vt2DArray]) and (i <> n - 1) then
    begin
      if FValType = vt1DArray then FillArray(FKeyframes[i].Value, last, 1)
      else FillArray(FKeyframes[i].Value, last, 2);
    end;
  end;
end;

procedure TTyAnimTrack.Step(AAnimator: TTyAnimator; APercent: Double);
var
  n, frameIdx, i, len, stride, rows: Integer;
  interval, w: Double;
  frame, next: ^TTyAnimKeyframe;
  cur: TTyAnimValue;
  tmp: array[0..3] of Double;
  v: Double;
begin
  if FFinished then Exit;
  n := Length(FKeyframes);
  if n = 0 then Exit;
  if n = 1 then
  begin
    frameIdx := 0;
    frame := @FKeyframes[0];
    next := @FKeyframes[0];
  end
  else
  begin
    if APercent < 0 then
      frameIdx := 0
    else if APercent < FLastFrP then
    begin
      frameIdx := Min(FLastFr + 1, n - 1);
      while frameIdx >= 0 do
      begin
        if FKeyframes[frameIdx].Percent <= APercent then Break;
        Dec(frameIdx);
      end;
      frameIdx := Min(frameIdx, n - 2);
    end
    else
    begin
      frameIdx := FLastFr;
      while frameIdx < n do
      begin
        if FKeyframes[frameIdx].Percent > APercent then Break;
        Inc(frameIdx);
      end;
      frameIdx := Min(frameIdx - 1, n - 2);
    end;
    { frameIdx may be -1 on the backward search: the defensive return }
    if (frameIdx < 0) or (frameIdx + 1 >= n) then Exit;
    frame := @FKeyframes[frameIdx];
    next := @FKeyframes[frameIdx + 1];
  end;

  FLastFr := frameIdx;
  FLastFrP := APercent;

  interval := next^.Percent - frame^.Percent;
  if interval = 0 then w := 1
  else
  begin
    w := (APercent - frame^.Percent) / interval;
    { Math.min(w, 1) }
    if w > 1 then w := 1;
  end;

  if FDiscrete then
  begin
    if w < 1 then AAnimator.PutValue(FPropName, frame^.Raw)
    else AAnimator.PutValue(FPropName, next^.Raw);
  end
  else if FValType in [vt1DArray, vt2DArray] then
  begin
    cur := AAnimator.GetValue(FPropName);
    { interpolation writes into the element's own array, in place; with no
      array there, upstream writes into a scratch one nobody sees }
    if cur.Kind <> avkArray then Exit;
    if FValType = vt1DArray then
    begin
      len := Length(frame^.Value.Arr);
      if cur.Float32 then
      begin
        { a typed array ignores a store past its end }
        for i := 0 to Min(len, Length(cur.Arr)) - 1 do
          cur.Arr[i] := TyJsFround(
            (next^.Value.Arr[i] - frame^.Value.Arr[i]) * w + frame^.Value.Arr[i]);
      end
      else
      begin
        if Length(cur.Arr) < len then SetLength(cur.Arr, len);
        for i := 0 to len - 1 do
          cur.Arr[i] := (next^.Value.Arr[i] - frame^.Value.Arr[i]) * w + frame^.Value.Arr[i];
      end;
    end
    else
    begin
      stride := frame^.Value.Stride;
      if (stride <= 0) or ((cur.Stride <> stride) and (Length(cur.Arr) > 0)) then Exit;
      rows := Length(frame^.Value.Arr) div stride;
      cur.Stride := stride;
      cur.Float32 := False;
      if Length(cur.Arr) < rows * stride then SetLength(cur.Arr, rows * stride);
      for i := 0 to rows * stride - 1 do
        cur.Arr[i] := (next^.Value.Arr[i] - frame^.Value.Arr[i]) * w + frame^.Value.Arr[i];
    end;
    AAnimator.PutValue(FPropName, cur);
  end
  else if FValType = vtColor then
  begin
    for i := 0 to 3 do
      tmp[i] := (next^.Value.Arr[i] - frame^.Value.Arr[i]) * w + frame^.Value.Arr[i];
    AAnimator.PutValue(FPropName,
      TyAnimStr(TyAnimRgbaString(tmp[0], tmp[1], tmp[2], tmp[3])));
  end
  else
  begin
    v := (next^.Value.Num - frame^.Value.Num) * w + frame^.Value.Num;
    AAnimator.PutValue(FPropName, TyAnimNum(v));
  end;
end;

{ ==================== Group ==================== }

procedure TTyAnimGroup.AnimDone;
begin
  FDoneHappened := True;
  Dec(FFinishCount);
  if FFinishCount <= 0 then
  begin
    if FDoneHappened then
    begin
      if Assigned(FDone) then FDone();
    end
    else if Assigned(FAborted) then FAborted();
  end;
end;

procedure TTyAnimGroup.AnimAborted;
begin
  Dec(FFinishCount);
  if FFinishCount <= 0 then
  begin
    if FDoneHappened then
    begin
      if Assigned(FDone) then FDone();
    end
    else if Assigned(FAborted) then FAborted();
  end;
end;

{ ==================== Animator ==================== }

constructor TTyAnimator.Create(AElement: TTyAnimElement; const ATargetName: string;
  ALoop, AAllowDiscrete: Boolean);
begin
  inherited Create;
  FElement := AElement;
  FTargetName := ATargetName;
  FLoop := ALoop;
  FAllowDiscrete := AAllowDiscrete;
  FDelay := NaN;
  FMaxTime := 0;
  if AElement <> nil then AElement.FOwned.Add(Self);
end;

destructor TTyAnimator.Destroy;
var i: Integer;
begin
  if FOwnedClip <> nil then
  begin
    if FOwnedClip.FAnimation <> nil then FOwnedClip.FAnimation.RemoveClip(FOwnedClip);
    FreeAndNil(FOwnedClip);
  end;
  for i := 0 to High(FTracks) do FTracks[i].Free;
  for i := 0 to High(FGroups) do
  begin
    Dec(FGroups[i].FRefs);
    if FGroups[i].FRefs <= 0 then FGroups[i].Free;
  end;
  inherited Destroy;
end;

function TTyAnimator.FullKey(const AProp: string): string;
begin
  if FTargetName = '' then Result := AProp
  else Result := FTargetName + '.' + AProp;
end;

function TTyAnimator.GetValue(const AProp: string): TTyAnimValue;
begin
  if FElement = nil then Exit(TyAnimNull);
  Result := FElement.GetAnimProp(FullKey(AProp));
end;

procedure TTyAnimator.PutValue(const AProp: string; const AValue: TTyAnimValue);
begin
  if FElement = nil then Exit;
  FElement.SetAnimProp(FullKey(AProp), AValue);
end;

function TTyAnimator.FindTrack(const AProp: string): TTyAnimTrack;
var i: Integer;
begin
  for i := 0 to High(FTracks) do
    if FTracks[i].FPropName = AProp then Exit(FTracks[i]);
  Result := nil;
end;

function TTyAnimator.GetTrack(const AProp: string): TTyAnimTrack;
begin
  Result := FindTrack(AProp);
end;

function TTyAnimator.TrackCount: Integer;
begin
  Result := Length(FTrackKeys);
end;

function TTyAnimator.TrackAt(AIndex: Integer): TTyAnimTrack;
begin
  Result := FTrackKeys[AIndex];
end;

function MakeCb(AKind: TTyAnimCbKind; ANotify: TTyAnimNotify; ADuring: TTyAnimDuring): TTyAnimCb;
begin
  Result.Kind := AKind;
  Result.Notify := ANotify;
  Result.During := ADuring;
end;

procedure TTyAnimator.AddGroup(AGroup: TTyAnimGroup);
begin
  SetLength(FGroups, Length(FGroups) + 1);
  FGroups[High(FGroups)] := AGroup;
  Inc(AGroup.FRefs);
end;

function TTyAnimator.WhenWithKeys(ATime: Double; const AKeys: array of string;
  const AValues: array of TTyAnimValue): TTyAnimator;
var
  i: Integer;
  track: TTyAnimTrack;
  initial: TTyAnimValue;
begin
  for i := 0 to High(AKeys) do
  begin
    track := FindTrack(AKeys[i]);
    if track = nil then
    begin
      track := TTyAnimTrack.Create(AKeys[i]);
      SetLength(FTracks, Length(FTracks) + 1);
      FTracks[High(FTracks)] := track;
      initial := GetValue(AKeys[i]);
      { an invalid value: the track exists, but is never run }
      if initial.Kind = avkNull then Continue;
      if ATime > 0 then track.AddKeyframe(0, initial);
      track.FInKeys := True;
      SetLength(FTrackKeys, Length(FTrackKeys) + 1);
      FTrackKeys[High(FTrackKeys)] := track;
    end;
    track.AddKeyframe(ATime, AValues[i]);
  end;
  FMaxTime := JsMax(FMaxTime, ATime);
  Result := Self;
end;

function TTyAnimator.Delay(ATime: Double): TTyAnimator;
begin
  FDelay := ATime;
  Result := Self;
end;

function TTyAnimator.Duration(ADuration: Double; AHasDuration: Boolean): TTyAnimator;
begin
  if AHasDuration then FMaxTime := ADuration else FMaxTime := NaN;
  FForce := True;
  Result := Self;
end;

function TTyAnimator.During(ACb: TTyAnimDuring): TTyAnimator;
begin
  if Assigned(ACb) then
  begin
    SetLength(FDuringCbs, Length(FDuringCbs) + 1);
    FDuringCbs[High(FDuringCbs)] := MakeCb(ackUser, nil, ACb);
  end;
  Result := Self;
end;

function TTyAnimator.Done(ACb: TTyAnimNotify): TTyAnimator;
begin
  if Assigned(ACb) then
  begin
    SetLength(FDoneCbs, Length(FDoneCbs) + 1);
    FDoneCbs[High(FDoneCbs)] := MakeCb(ackUser, ACb, nil);
  end;
  Result := Self;
end;

function TTyAnimator.Aborted(ACb: TTyAnimNotify): TTyAnimator;
begin
  if Assigned(ACb) then
  begin
    SetLength(FAbortedCbs, Length(FAbortedCbs) + 1);
    FAbortedCbs[High(FAbortedCbs)] := MakeCb(ackUser, ACb, nil);
  end;
  Result := Self;
end;

procedure TTyAnimator.CallList(const AList: array of TTyAnimCb);
var
  i: Integer;
  cbs: array of TTyAnimCb;
begin
  { the list as it stood when the call began }
  SetLength(cbs, Length(AList));
  for i := 0 to High(AList) do cbs[i] := AList[i];
  for i := 0 to High(cbs) do
    case cbs[i].Kind of
      ackRemove:
        if FElement <> nil then FElement.RemoveFromList(Self);
      ackUser:
        if Assigned(cbs[i].Notify) then cbs[i].Notify();
    end;
end;

procedure TTyAnimator.SetTracksFinished;
var i: Integer;
begin
  for i := 0 to High(FTrackKeys) do FTrackKeys[i].SetFinished;
end;

procedure TTyAnimator.MarkDead;
begin
  FDead := True;
  Bury(Self);
end;

procedure TTyAnimator.DoneCallback;
begin
  SetTracksFinished;
  FClip := nil;
  MarkDead;
  CallList(FDoneCbs);
end;

procedure TTyAnimator.AbortedCallback;
begin
  SetTracksFinished;
  if (FAnimation <> nil) and (FClip <> nil) then FAnimation.RemoveClip(FClip);
  FClip := nil;
  MarkDead;
  CallList(FAbortedCbs);
end;

procedure TTyAnimator.ClipFrame(APercent: Double);
var
  i: Integer;
  cbs: array of TTyAnimCb;
begin
  FStarted := 2;
  if FElement = nil then Exit;
  for i := 0 to High(FRunTracks) do
    FRunTracks[i].Step(Self, APercent);
  SetLength(cbs, Length(FDuringCbs));
  for i := 0 to High(FDuringCbs) do cbs[i] := FDuringCbs[i];
  for i := 0 to High(cbs) do
    case cbs[i].Kind of
      ackDirty:
        if FElement <> nil then FElement.AnimDirty(FTargetName);
      ackUser:
        if Assigned(cbs[i].During) then cbs[i].During(APercent);
    end;
end;

procedure TTyAnimator.ClipDestroy;
begin
  if FElement = nil then
  begin
    FClip := nil;
    Exit;
  end;
  DoneCallback;
end;

procedure TTyAnimator.Start(const AEasing: string);
begin
  Start(TyEasingResolve(AEasing));
end;

procedure TTyAnimator.Start(const AEasing: TTyEasing);
var
  i, n: Integer;
  track: TTyAnimTrack;
  mt: Double;
  g: TEngineGuard;
begin
  if FStarted > 0 then Exit;
  g := EnterEngine;
  try
    FStarted := 1;
    mt := OrZero(FMaxTime);
    FRunTracks := nil;
    for i := 0 to High(FTrackKeys) do
    begin
      track := FTrackKeys[i];
      track.Prepare(mt);
      if track.NeedsAnimate then
      begin
        if (not FAllowDiscrete) and track.FDiscrete then
        begin
          n := Length(track.FKeyframes);
          { the final value, raw, at once }
          if n > 0 then PutValue(track.FPropName, track.FKeyframes[n - 1].Raw);
          track.SetFinished;
        end
        else
        begin
          SetLength(FRunTracks, Length(FRunTracks) + 1);
          FRunTracks[High(FRunTracks)] := track;
        end;
      end;
    end;
    if (Length(FRunTracks) > 0) or FForce then
    begin
      FOwnedClip := TTyAnimClip.Create(mt, FDelay, FLoop);
      FClip := FOwnedClip;
      FClip.OnFrame := @ClipFrame;
      FClip.OnDestroy := @ClipDestroy;
      if FAnimation <> nil then FAnimation.AddClip(FClip);
      if AEasing.Kind <> ekNone then FClip.SetEasing(AEasing);
    end
    else
      DoneCallback;
  finally
    LeaveEngine(g);
  end;
end;

procedure TTyAnimator.Stop(AForwardToLast: Boolean);
var g: TEngineGuard;
begin
  if FClip = nil then Exit;
  g := EnterEngine;
  try
    if AForwardToLast then ClipFrame(1);
    AbortedCallback;
  finally
    LeaveEngine(g);
  end;
end;

function TTyAnimator.StopTracks(const AKeys: array of string; AForwardToLast: Boolean): Boolean;
var
  i: Integer;
  track: TTyAnimTrack;
  g: TEngineGuard;
begin
  if (Length(AKeys) = 0) or (FClip = nil) then Exit(True);
  g := EnterEngine;
  try
    for i := 0 to High(AKeys) do
    begin
      track := FindTrack(AKeys[i]);
      if (track <> nil) and not track.FFinished then
      begin
        if AForwardToLast then
          track.Step(Self, 1)
        { started but never stepped: setToFinal left the element at the
          final value; put the from value back }
        else if FStarted = 1 then
          track.Step(Self, 0);
        track.SetFinished;
      end;
    end;
    Result := True;
    for i := 0 to High(FTrackKeys) do
      if not FTrackKeys[i].FFinished then
      begin
        Result := False;
        Break;
      end;
    if Result then AbortedCallback;
  finally
    LeaveEngine(g);
  end;
end;

procedure TTyAnimator.SaveTo(var AProps: TTyAnimProps; const ASkip: array of string);
var
  i, k, n: Integer;
  track: TTyAnimTrack;
  skip: Boolean;
begin
  for i := 0 to High(FTrackKeys) do
  begin
    track := FTrackKeys[i];
    { a finished track is ignored }
    if track.FFinished then Continue;
    n := Length(track.FKeyframes);
    if n = 0 then Continue;
    skip := False;
    if FTargetName = '' then
      for k := 0 to High(ASkip) do
        if ASkip[k] = track.FPropName then skip := True;
    if skip then Continue;
    { the raw value, not the parsed one }
    TyAnimPropPut(AProps, FullKey(track.FPropName),
      TyAnimClone(track.FKeyframes[n - 1].Raw));
  end;
end;

procedure TTyAnimator.ChangeFinalValue(const AKeys: array of string;
  const AValues: array of TTyAnimValue);
var
  i, n: Integer;
  track: TTyAnimTrack;
  t: Double;
begin
  for i := 0 to High(AKeys) do
  begin
    track := FindTrack(AKeys[i]);
    if track = nil then Continue;
    n := Length(track.FKeyframes);
    if n <= 1 then Continue;
    { the original last keyframe out, the new one in at its time }
    t := track.FKeyframes[n - 1].Time;
    SetLength(track.FKeyframes, n - 1);
    track.AddKeyframe(t, AValues[i]);
    track.Prepare(OrZero(FMaxTime));
  end;
end;

{ ==================== Animation ==================== }

constructor TTyAnimation.Create;
begin
  inherited Create;
  FElements := TFPList.Create;
end;

destructor TTyAnimation.Destroy;
var
  i, j: Integer;
  el: TTyAnimElement;
begin
  Clear;
  for i := 0 to FElements.Count - 1 do
  begin
    el := TTyAnimElement(FElements[i]);
    el.FAnimation := nil;
    for j := 0 to el.FOwned.Count - 1 do
      TTyAnimator(el.FOwned[j]).FAnimation := nil;
  end;
  FElements.Free;
  inherited Destroy;
end;

procedure TTyAnimation.AddClip(AClip: TTyAnimClip);
begin
  if AClip.FAnimation <> nil then AClip.FAnimation.RemoveClip(AClip);
  if FHead = nil then
  begin
    FHead := AClip;
    FTail := AClip;
    AClip.FPrev := nil;
    AClip.FNext := nil;
  end
  else
  begin
    FTail.FNext := AClip;
    AClip.FPrev := FTail;
    AClip.FNext := nil;
    FTail := AClip;
  end;
  AClip.FAnimation := Self;
  Inc(FCount);
end;

procedure TTyAnimation.RemoveClip(AClip: TTyAnimClip);
var prev, next: TTyAnimClip;
begin
  if (AClip = nil) or (AClip.FAnimation <> Self) then Exit;
  prev := AClip.FPrev;
  next := AClip.FNext;
  if prev <> nil then prev.FNext := next else FHead := next;
  if next <> nil then next.FPrev := prev else FTail := prev;
  AClip.FNext := nil;
  AClip.FPrev := nil;
  AClip.FAnimation := nil;
  Dec(FCount);
end;

procedure TTyAnimation.AddAnimator(AAnimator: TTyAnimator);
begin
  AAnimator.FAnimation := Self;
  if AAnimator.FClip <> nil then AddClip(AAnimator.FClip);
end;

procedure TTyAnimation.RemoveAnimator(AAnimator: TTyAnimator);
begin
  if AAnimator.FClip <> nil then RemoveClip(AAnimator.FClip);
  AAnimator.FAnimation := nil;
end;

procedure TTyAnimation.Start(ANow: Double);
begin
  FTime := ANow;
  FPausedTime := 0;
end;

procedure TTyAnimation.Update(ANow: Double; ANoFrame: Boolean);
var
  tnow, delta: Double;
  clip, next: TTyAnimClip;
  g: TEngineGuard;
begin
  g := EnterEngine;
  try
    tnow := ANow - FPausedTime;
    delta := tnow - FTime;
    clip := FHead;
    while clip <> nil do
    begin
      { saved before the step: a clip removed in a callback does not break
        the walk -- unless it was the saved one, which ends it, as upstream }
      next := clip.FNext;
      if clip.Step(tnow, delta) then
      begin
        if Assigned(clip.OnDestroy) then clip.OnDestroy();
        RemoveClip(clip);
      end;
      clip := next;
    end;
    FTime := tnow;
    if (not ANoFrame) and Assigned(FOnFrame) then FOnFrame(Self, delta);
  finally
    LeaveEngine(g);
  end;
end;

procedure TTyAnimation.Clear;
var clip, next: TTyAnimClip;
begin
  clip := FHead;
  while clip <> nil do
  begin
    next := clip.FNext;
    clip.FPrev := nil;
    clip.FNext := nil;
    clip.FAnimation := nil;
    clip := next;
  end;
  FHead := nil;
  FTail := nil;
  FCount := 0;
end;

function TTyAnimation.IsFinished: Boolean;
begin
  Result := FHead = nil;
end;

procedure TTyAnimation.WakeUp;
begin
  if Assigned(FOnWake) then FOnWake(Self);
end;

function TTyAnimation.ClipAt(AIndex: Integer): TTyAnimClip;
var i: Integer;
begin
  Result := FHead;
  i := 0;
  while (Result <> nil) and (i < AIndex) do
  begin
    Result := Result.FNext;
    Inc(i);
  end;
end;

{ ==================== Element ==================== }

constructor TTyAnimElement.Create;
begin
  inherited Create;
  FAnimators := TFPList.Create;
  FOwned := TFPList.Create;
  FStatePath := True;
end;

destructor TTyAnimElement.Destroy;
var
  i: Integer;
  a: TTyAnimator;
  g: TEngineGuard;
begin
  g := EnterEngine;
  try
    for i := FOwned.Count - 1 downto 0 do
    begin
      a := TTyAnimator(FOwned[i]);
      if (a.FOwnedClip <> nil) and (a.FOwnedClip.FAnimation <> nil) then
        a.FOwnedClip.FAnimation.RemoveClip(a.FOwnedClip);
      a.FElement := nil;
      a.FClip := nil;
      a.FDead := True;
      Bury(a);
    end;
    FOwned.Clear;
    FAnimators.Clear;
    if FAnimation <> nil then FAnimation.FElements.Remove(Self);
    FAnimation := nil;
  finally
    LeaveEngine(g);
  end;
  FAnimators.Free;
  FOwned.Free;
  inherited Destroy;
end;

procedure TTyAnimElement.AnimDirty(const ATargetName: string);
begin
end;

procedure TTyAnimElement.SetAnimation(AValue: TTyAnimation);
var i: Integer;
begin
  if FAnimation = AValue then Exit;
  if FAnimation <> nil then
  begin
    for i := 0 to FAnimators.Count - 1 do
      FAnimation.RemoveAnimator(TTyAnimator(FAnimators[i]));
    FAnimation.FElements.Remove(Self);
  end;
  FAnimation := AValue;
  if FAnimation <> nil then
  begin
    FAnimation.FElements.Add(Self);
    for i := 0 to FAnimators.Count - 1 do
      FAnimation.AddAnimator(TTyAnimator(FAnimators[i]));
  end;
end;

procedure TTyAnimElement.RemoveFromList(AAnimator: TTyAnimator);
var idx: Integer;
begin
  idx := FAnimators.IndexOf(AAnimator);
  if idx >= 0 then FAnimators.Delete(idx);
end;

procedure TTyAnimElement.AddAnimator(AAnimator: TTyAnimator);
var n: Integer;
begin
  { during -> updateDuringAnimation, done -> out of el.animators: first in
    each list, as upstream registers them before animateTo adds its own }
  n := Length(AAnimator.FDuringCbs);
  SetLength(AAnimator.FDuringCbs, n + 1);
  AAnimator.FDuringCbs[n] := MakeCb(ackDirty, nil, nil);
  n := Length(AAnimator.FDoneCbs);
  SetLength(AAnimator.FDoneCbs, n + 1);
  AAnimator.FDoneCbs[n] := MakeCb(ackRemove, nil, nil);
  FAnimators.Add(AAnimator);
  if FAnimation <> nil then
  begin
    FAnimation.AddAnimator(AAnimator);
    FAnimation.WakeUp;
  end;
end;

function TTyAnimElement.Animate(const ATargetName: string; ALoop: Boolean;
  AAllowDiscrete: Boolean): TTyAnimator;
begin
  Result := TTyAnimator.Create(Self, ATargetName, ALoop, AAllowDiscrete);
  AddAnimator(Result);
end;

function TTyAnimElement.AnimatorCount: Integer;
begin
  Result := FAnimators.Count;
end;

function TTyAnimElement.AnimatorAt(AIndex: Integer): TTyAnimator;
begin
  Result := TTyAnimator(FAnimators[AIndex]);
end;

function TTyAnimElement.IsRemoved: Boolean;
var i: Integer;
begin
  if FAnimation = nil then Exit(True);
  for i := 0 to FAnimators.Count - 1 do
    if TTyAnimator(FAnimators[i]).FScope = 'leave' then Exit(True);
  Result := False;
end;

procedure TTyAnimElement.StopAnimation(const AScope: string; AForwardToLast: Boolean);
var
  snap, left: TFPList;
  i: Integer;
  a: TTyAnimator;
  g: TEngineGuard;
begin
  g := EnterEngine;
  snap := TFPList.Create;
  left := TFPList.Create;
  try
    snap.Assign(FAnimators);
    for i := 0 to snap.Count - 1 do
    begin
      a := TTyAnimator(snap[i]);
      if (AScope = '') or (AScope = a.FScope) then
        a.Stop(AForwardToLast)
      else
        left.Add(a);
    end;
    { this.animators = leftAnimators: anything added meanwhile is dropped }
    FAnimators.Assign(left);
  finally
    left.Free;
    snap.Free;
    LeaveEngine(g);
  end;
end;

procedure TTyAnimElement.Attr(const AProps: TTyAnimProps);
var
  i, p: Integer;
  g: TEngineGuard;
begin
  g := EnterEngine;
  try
    for i := 0 to High(AProps) do
    begin
      SetAnimProp(AProps[i].Key, AProps[i].Value);
      p := Pos('.', AProps[i].Key);
      if p > 0 then AnimDirty(Copy(AProps[i].Key, 1, p - 1))
      else AnimDirty('');
    end;
  finally
    LeaveEngine(g);
  end;
end;

procedure TTyAnimElement.AnimateTo(const AProps: TTyAnimProps; const ACfg: TTyAnimCfg);
begin
  DoAnimateTo(AProps, ACfg, False);
end;

procedure TTyAnimElement.AnimateFrom(const AProps: TTyAnimProps; const ACfg: TTyAnimCfg);
begin
  DoAnimateTo(AProps, ACfg, True);
end;

function TTyAnimElement.AnimKeyList: TTyStringArray;
begin
  Result := nil;
end;

function PrefixOf(const AKey: string; out AInner: string): string;
var p: Integer;
begin
  p := Pos('.', AKey);
  if p > 0 then
  begin
    Result := Copy(AKey, 1, p - 1);
    AInner := Copy(AKey, p + 1, MaxInt);
  end
  else
  begin
    Result := '';
    AInner := AKey;
  end;
end;

{ copyValue (Element.ts:1911-1952): the target value onto the element, with
  the typed-array quirk -- a typed source the same length as the element's
  array is NOT copied }
function CopyValueOnto(const ACur, ASource: TTyAnimValue): TTyAnimValue;
var i, n: Integer;
begin
  if ASource.Kind <> avkArray then Exit(TyAnimClone(ASource));
  Result := TyAnimClone(ACur);
  if Result.Kind <> avkArray then
  begin
    Result := TyAnimArr([]);
  end;
  if ASource.Float32 then
  begin
    if Length(Result.Arr) <> Length(ASource.Arr) then
      Result := TyAnimClone(ASource);
    Exit;
  end;
  if Result.Float32 then
  begin
    { a plain source into a typed array: each store rounds, the length stays }
    n := Min(Length(Result.Arr), Length(ASource.Arr));
    for i := 0 to n - 1 do Result.Arr[i] := TyJsFround(ASource.Arr[i]);
    Exit;
  end;
  Result.Arr := Copy(ASource.Arr);
  Result.Stride := ASource.Stride;
end;

{ getAnimationStyleProps: Path's (Path.ts:75-86) over Displayable's
  (Displayable.ts:42-50) }
const
  cPathAnimStyle: array[0..12] of string = ('fill', 'stroke', 'strokePercent',
    'fillOpacity', 'strokeOpacity', 'lineDashOffset', 'lineWidth', 'miterLimit',
    'shadowBlur', 'shadowOffsetX', 'shadowOffsetY', 'shadowColor', 'opacity');
  cCommonAnimStyle: array[0..4] of string = ('shadowBlur', 'shadowOffsetX',
    'shadowOffsetY', 'shadowColor', 'opacity');

function StyleAnimatable(APath: Boolean; const AKey: string): Boolean;
var i: Integer;
begin
  Result := True;
  if APath then
  begin
    for i := 0 to High(cPathAnimStyle) do
      if cPathAnimStyle[i] = AKey then Exit;
  end
  else
    for i := 0 to High(cCommonAnimStyle) do
      if cCommonAnimStyle[i] = AKey then Exit;
  Result := False;
end;

procedure TTyAnimElement.Shallow(const ATopKey: string; const AKeys: array of string;
  const AValues: array of TTyAnimValue; const ACfg: TTyAnimCfg;
  AReverse, AFilter: Boolean; var AList: TFPList);
var
  keys: array of string;
  vals: array of TTyAnimValue;
  assigned: array of Boolean;
  i, n, idx: Integer;
  cur: TTyAnimValue;
  full: string;
  a: TTyAnimator;
  kept: array of string;
  keptVals: array of TTyAnimValue;
  fromVals, toVals: array of TTyAnimValue;
  duration: Double;

  function FullOf(const AInner: string): string;
  begin
    if ATopKey = '' then Result := AInner else Result := ATopKey + '.' + AInner;
  end;

begin
  keys := nil;
  vals := nil;
  assigned := nil;
  for i := 0 to High(AKeys) do
  begin
    full := FullOf(AKeys[i]);
    cur := GetAnimProp(full);
    { animationProps: a state transition's style animates only the props
      getAnimationStyleProps names; the rest is assigned [Batch 94] }
    if (AValues[i].Kind <> avkNull) and (cur.Kind <> avkNull)
      and not (AFilter and (ATopKey = 'style') and not StyleAnimatable(FStatePath, AKeys[i])) then
    begin
      n := Length(keys);
      SetLength(keys, n + 1); SetLength(vals, n + 1); SetLength(assigned, n + 1);
      keys[n] := AKeys[i];
      vals[n] := AValues[i];
      assigned[n] := False;
    end
    else if not AReverse then
    begin
      { assign directly; the previous animation still stops on the key }
      SetAnimProp(full, AValues[i]);
      AnimDirty(ATopKey);
      n := Length(keys);
      SetLength(keys, n + 1); SetLength(vals, n + 1); SetLength(assigned, n + 1);
      keys[n] := AKeys[i];
      vals[n] := AValues[i];
      assigned[n] := True;
    end;
  end;

  { stop the previous animation on the same properties; the forward walk
    with a splice skips the animator after a removed one, as upstream's }
  if Length(keys) > 0 then
  begin
    i := 0;
    while i < FAnimators.Count do
    begin
      a := TTyAnimator(FAnimators[i]);
      if a.FTargetName = ATopKey then
        if a.StopTracks(keys) then
        begin
          idx := FAnimators.IndexOf(a);
          if idx >= 0 then FAnimators.Delete(idx);
        end;
      Inc(i);
    end;
  end;

  { drop the unchanged keys -- after the stop, which may have written the
    from value back }
  if not ACfg.Force then
  begin
    kept := nil; keptVals := nil;
    for i := 0 to High(keys) do
    begin
      cur := GetAnimProp(FullOf(keys[i]));
      if assigned[i] and (vals[i].Kind = avkArray) then Continue; // the same reference
      if TyAnimValueSame(vals[i], cur) then Continue;
      n := Length(kept);
      SetLength(kept, n + 1); SetLength(keptVals, n + 1);
      kept[n] := keys[i];
      keptVals[n] := vals[i];
    end;
    keys := kept;
    vals := keptVals;
  end;

  if (Length(keys) > 0) or (ACfg.Force and (AList.Count = 0)) then
  begin
    n := Length(keys);
    SetLength(fromVals, n);
    SetLength(toVals, n);
    for i := 0 to n - 1 do
    begin
      full := FullOf(keys[i]);
      cur := GetAnimProp(full);
      if AReverse then
      begin
        toVals[i] := cur;
        fromVals[i] := vals[i];
        if not ACfg.SetToFinal then SetAnimProp(full, vals[i]);
      end
      else
      begin
        toVals[i] := vals[i];
        if ACfg.SetToFinal then
        begin
          fromVals[i] := TyAnimClone(cur);
          SetAnimProp(full, CopyValueOnto(cur, vals[i]));
        end;
      end;
    end;

    a := TTyAnimator.Create(Self, ATopKey, False, False);
    if ACfg.Scope <> '' then a.FScope := ACfg.Scope;
    if ACfg.SetToFinal then a.WhenWithKeys(0, keys, fromVals);
    if ACfg.HasDuration then duration := ACfg.Duration else duration := 500;
    a.WhenWithKeys(duration, keys, toVals);
    a.Delay(OrZero(ACfg.Delay));
    AddAnimator(a);
    AList.Add(a);
  end;
end;

procedure TTyAnimElement.DoAnimateTo(const AProps: TTyAnimProps; const ACfg: TTyAnimCfg;
  AReverse: Boolean; const AStateName: string; AStyleFilter: Boolean);
var
  list: TFPList;
  prefixes: array of string;
  topKeys, groupKeys: array of string;
  topVals, groupVals: array of TTyAnimValue;
  i, j, n: Integer;
  pre, inner, inner2: string;
  seen: Boolean;
  group: TTyAnimGroup;
  a: TTyAnimator;
  g: TEngineGuard;
begin
  g := EnterEngine;
  list := TFPList.Create;
  try
    { the walk: a nested object recurses where it first appears (its
      animator is made then); the element's own keys wait for the end }
    prefixes := nil;
    topKeys := nil;
    topVals := nil;
    for i := 0 to High(AProps) do
    begin
      pre := PrefixOf(AProps[i].Key, inner);
      if pre = '' then
      begin
        n := Length(topKeys);
        SetLength(topKeys, n + 1);
        SetLength(topVals, n + 1);
        topKeys[n] := inner;
        topVals[n] := AProps[i].Value;
        Continue;
      end;
      seen := False;
      for j := 0 to High(prefixes) do
        if prefixes[j] = pre then seen := True;
      if seen then Continue;
      SetLength(prefixes, Length(prefixes) + 1);
      prefixes[High(prefixes)] := pre;
      groupKeys := nil;
      groupVals := nil;
      for j := i to High(AProps) do
        if PrefixOf(AProps[j].Key, inner2) = pre then
        begin
          n := Length(groupKeys);
          SetLength(groupKeys, n + 1);
          SetLength(groupVals, n + 1);
          groupKeys[n] := inner2;
          groupVals[n] := AProps[j].Value;
        end;
      Shallow(pre, groupKeys, groupVals, ACfg, AReverse, AStyleFilter, list);
    end;
    Shallow('', topKeys, topVals, ACfg, AReverse, AStyleFilter, list);

    group := TTyAnimGroup.Create;
    group.FFinishCount := list.Count;
    group.FDone := ACfg.Done;
    group.FAborted := ACfg.Aborted;
    if list.Count = 0 then
    begin
      group.Free;
      if Assigned(ACfg.Done) then ACfg.Done();
      Exit;
    end;
    if Assigned(ACfg.During) then
      TTyAnimator(list[0]).During(ACfg.During);
    for i := 0 to list.Count - 1 do
    begin
      a := TTyAnimator(list[i]);
      a.AddGroup(group);
      a.Done(@group.AnimDone);
      a.Aborted(@group.AnimAborted);
      if ACfg.Force then a.Duration(ACfg.Duration, ACfg.HasDuration);
      a.Start(ACfg.Easing);
    end;
    { _transitionState: the animators carry the state name }
    if AStateName <> '' then
      for i := 0 to list.Count - 1 do
        TTyAnimator(list[i]).FFromState := AStateName;
  finally
    list.Free;
    LeaveEngine(g);
  end;
end;

{ ==================== states [Batch 94] ==================== }

function TyAnimPropIndex(const AProps: TTyAnimProps; const AKey: string): Integer;
var i: Integer;
begin
  for i := 0 to High(AProps) do
    if AProps[i].Key = AKey then Exit(i);
  Result := -1;
end;

procedure TyAnimPropPut(var AProps: TTyAnimProps; const AKey: string;
  const AValue: TTyAnimValue);
var i: Integer;
begin
  i := TyAnimPropIndex(AProps, AKey);
  if i < 0 then
  begin
    i := Length(AProps);
    SetLength(AProps, i + 1);
    AProps[i].Key := AKey;
  end;
  AProps[i].Value := TyAnimClone(AValue);
end;

function TyAnimStyleDefault(const AKey: string; out AValue: TTyAnimValue): Boolean;
begin
  Result := True;
  if AKey = 'fill' then AValue := TyAnimStr('#000')
  else if AKey = 'stroke' then AValue := TyAnimNull
  else if (AKey = 'strokePercent') or (AKey = 'fillOpacity')
    or (AKey = 'strokeOpacity') or (AKey = 'lineWidth') or (AKey = 'opacity') then
    AValue := TyAnimNum(1)
  else if (AKey = 'lineDashOffset') or (AKey = 'shadowBlur')
    or (AKey = 'shadowOffsetX') or (AKey = 'shadowOffsetY') then
    AValue := TyAnimNum(0)
  else if AKey = 'miterLimit' then AValue := TyAnimNum(10)
  else if AKey = 'shadowColor' then AValue := TyAnimStr('#000')
  else
  begin
    AValue := TyAnimNull;
    Result := False;
  end;
end;

const
  { PRIMARY_STATES_KEYS (Element.ts:281): TRANSFORMABLE_PROPS and ignore }
  cPrimaryKeys: array[0..11] of string = ('x', 'y', 'originX', 'originY',
    'anchorX', 'anchorY', 'rotation', 'scaleX', 'scaleY', 'skewX', 'skewY',
    'ignore');

function SubOf(const AKey, APrefix: string; out AInner: string): Boolean;
begin
  Result := (Length(AKey) > Length(APrefix) + 1)
    and (Copy(AKey, 1, Length(APrefix) + 1) = APrefix + '.');
  if Result then AInner := Copy(AKey, Length(APrefix) + 2, MaxInt)
  else AInner := '';
end;

function IsRootKey(const AKey: string): Boolean;
begin
  Result := Pos('.', AKey) = 0;
end;

function PropGet(const AProps: TTyAnimProps; const AKey: string;
  out AValue: TTyAnimValue): Boolean;
var i: Integer;
begin
  i := TyAnimPropIndex(AProps, AKey);
  Result := i >= 0;
  if Result then AValue := TyAnimClone(AProps[i].Value) else AValue := TyAnimNull;
end;

function TTyAnimElement.InStateSkip(const AKey: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(FStateSkip) do
    if FStateSkip[i] = AKey then Exit(True);
  Result := False;
end;

function TTyAnimElement.HasAnimKey(const AKey: string): Boolean;
var
  keys: TTyStringArray;
  i: Integer;
begin
  keys := AnimKeyList;
  for i := 0 to High(keys) do
    if keys[i] = AKey then Exit(True);
  Result := False;
end;

procedure TTyAnimElement.SetStateSkip(const AKeys: array of string);
var i: Integer;
begin
  SetLength(FStateSkip, Length(AKeys));
  for i := 0 to High(AKeys) do FStateSkip[i] := AKeys[i];
end;

procedure TTyAnimElement.SetStateTransition(const ACfg: TTyAnimCfg);
begin
  FStateCfg := ACfg;
  FHasStateCfg := True;
end;

procedure TTyAnimElement.ClearStateTransition;
begin
  FStateCfg := Default(TTyAnimCfg);
  FHasStateCfg := False;
end;

function TTyAnimElement.NormalValue(const AKey: string; out AValue: TTyAnimValue): Boolean;
begin
  Result := PropGet(FNormal, AKey, AValue);
end;

{ canTransition (Element.ts:2163-2169): no noAnimation, a stateTransition,
  a duration above 0 }
function TTyAnimElement.CanTransition(ANoAnimation: Boolean): Boolean;
begin
  Result := (not ANoAnimation) and FHasStateCfg and (FStateCfg.Duration > 0);
end;

{ saveCurrentToNormalState (Element.ts:860-909, Displayable.ts:494-503,
  Path.ts:509-521) }
procedure TTyAnimElement.SaveCurrentToNormal(const AState: TTyAnimState);
var
  i: Integer;
  v: TTyAnimValue;
  keys: TTyStringArray;
  inner: string;
  a: TTyAnimator;
  ok: Boolean;
begin
  { _savePrimaryToNormal: only a key the state sets, and not saved yet }
  for i := 0 to High(cPrimaryKeys) do
  begin
    if InStateSkip(cPrimaryKeys[i]) then Continue;
    if not PropGet(AState.Props, cPrimaryKeys[i], v) or (v.Kind = avkNull) then Continue;
    if TyAnimPropIndex(FNormal, cPrimaryKeys[i]) >= 0 then Continue;
    TyAnimPropPut(FNormal, cPrimaryKeys[i], GetAnimProp(cPrimaryKeys[i]));
  end;
  keys := AnimKeyList;
  { the whole style, once; the whole shape, once }
  if AState.HasStyle and not FNormalStyle then
  begin
    FNormalStyle := True;
    for i := 0 to High(keys) do
      if SubOf(keys[i], 'style', inner) then
        TyAnimPropPut(FNormal, keys[i], GetAnimProp(keys[i]));
  end;
  if FStatePath and AState.HasShape and not FNormalShape then
  begin
    FNormalShape := True;
    for i := 0 to High(keys) do
      if SubOf(keys[i], 'shape', inner) then
        TyAnimPropPut(FNormal, keys[i], GetAnimProp(keys[i]));
  end;
  { switching away from normal during an animation: its FINAL values are the
    normal state's, not the interpolated ones -- except a loop's and another
    state's transition }
  for i := 0 to FAnimators.Count - 1 do
  begin
    a := TTyAnimator(FAnimators[i]);
    if a.FLoop then Continue;
    if (a.FFromState <> '') and (a.FFromState <> TyAnimNormalState) then Continue;
    if a.FTargetName = '' then ok := True
    else if a.FTargetName = 'style' then ok := FNormalStyle
    else if a.FTargetName = 'shape' then ok := FNormalShape
    else ok := False;
    if ok then a.SaveTo(FNormal, FStateSkip);
  end;
end;

{ A TRANSITION'S STYLE AND SHAPE ARE NEW OBJECTS (Displayable.ts:556,
  Path.ts:565): the running animators' tracks on the target keys stop, and a
  track stopped before it ever stepped writes its from value back into the
  OLD object -- which the element no longer holds. So the values stay what
  they were: an enter fade that had not stepped yet ends where setToFinal
  left it, and the transition finds nothing to do on that key. }
procedure TTyAnimElement.StopTracksDetached(const ATopKey: string; const AProps: TTyAnimProps);
var
  keys: array of string;
  snap: TTyAnimProps;
  i, idx: Integer;
  inner: string;
  a: TTyAnimator;
begin
  keys := nil;
  snap := nil;
  for i := 0 to High(AProps) do
    if SubOf(AProps[i].Key, ATopKey, inner) then
    begin
      SetLength(keys, Length(keys) + 1);
      keys[High(keys)] := inner;
      TyAnimPropPut(snap, AProps[i].Key, GetAnimProp(AProps[i].Key));
    end;
  if Length(keys) = 0 then Exit;
  i := 0;
  while i < FAnimators.Count do
  begin
    a := TTyAnimator(FAnimators[i]);
    if a.FTargetName = ATopKey then
      if a.StopTracks(keys) then
      begin
        idx := FAnimators.IndexOf(a);
        if idx >= 0 then FAnimators.Delete(idx);
      end;
    Inc(i);
  end;
  for i := 0 to High(snap) do SetAnimProp(snap[i].Key, snap[i].Value);
end;

{ _applyStateObj: Element's (Element.ts:1232-1315), then Displayable's
  style (Displayable.ts:503-600), then Path's shape (Path.ts:523-586). Not
  keeping the current states: everything the state does not set returns to
  the normal state's. }
procedure TTyAnimElement.ApplyStateObj(const AName: string; AHasState: Boolean;
  const AState: TTyAnimState; ATransition: Boolean);
var
  i, j: Integer;
  v: TTyAnimValue;
  tProps, target, prims: TTyAnimProps;
  keys: TTyStringArray;
  inner, tn: string;
  hasTarget: Boolean;
  snap: TFPList;
  a: TTyAnimator;
  ck: array of string;
  cv: array of TTyAnimValue;
  src: TTyAnimProps;
  srcStyle, srcShape: Boolean;
  cfg: TTyAnimCfg;
begin
  cfg := FStateCfg;
  { ---- the transform keys and ignore ---- }
  tProps := nil;
  for i := 0 to High(cPrimaryKeys) do
  begin
    if InStateSkip(cPrimaryKeys[i]) then Continue;
    if AHasState and PropGet(AState.Props, cPrimaryKeys[i], v) and (v.Kind <> avkNull) then
    else if PropGet(FNormal, cPrimaryKeys[i], v) and (v.Kind <> avkNull) then
    else Continue;
    if ATransition and (cPrimaryKeys[i] <> 'ignore') then
      TyAnimPropPut(tProps, cPrimaryKeys[i], v)
    else
    begin
      SetAnimProp(cPrimaryKeys[i], v);
      AnimDirty('');
    end;
  end;
  { WITHOUT A TRANSITION the running animations keep going to the NEW values
    (not stopped: that would jump) -- the state's, or the normal state's }
  if not ATransition then
  begin
    if AHasState then
    begin
      src := AState.Props;
      srcStyle := AState.HasStyle;
      srcShape := AState.HasShape;
    end
    else
    begin
      src := FNormal;
      srcStyle := FNormalStyle;
      srcShape := FNormalShape;
    end;
    snap := TFPList.Create;
    try
      snap.Assign(FAnimators);
      for i := 0 to snap.Count - 1 do
      begin
        a := TTyAnimator(snap[i]);
        if a.FLoop then Continue;
        tn := a.FTargetName;
        ck := nil;
        cv := nil;
        for j := 0 to High(src) do
        begin
          if tn = '' then
          begin
            if not IsRootKey(src[j].Key) then Continue;
            inner := src[j].Key;
          end
          else if ((tn = 'style') and srcStyle) or ((tn = 'shape') and srcShape) then
          begin
            if not SubOf(src[j].Key, tn, inner) then Continue;
          end
          else
            Continue;
          SetLength(ck, Length(ck) + 1);
          SetLength(cv, Length(cv) + 1);
          ck[High(ck)] := inner;
          cv[High(cv)] := src[j].Value;
        end;
        a.ChangeFinalValue(ck, cv);
      end;
    finally
      snap.Free;
    end;
  end;
  if Length(tProps) > 0 then DoAnimateTo(tProps, cfg, False, AName);
  { ---- the style ---- }
  hasTarget := False;
  target := nil;
  if AHasState and AState.HasStyle then
  begin
    hasTarget := True;
    { the normal style with the state's over it }
    for i := 0 to High(FNormal) do
      if SubOf(FNormal[i].Key, 'style', inner) then
        TyAnimPropPut(target, FNormal[i].Key, FNormal[i].Value);
    for i := 0 to High(AState.Props) do
      if SubOf(AState.Props[i].Key, 'style', inner) then
        TyAnimPropPut(target, AState.Props[i].Key, AState.Props[i].Value);
  end
  else if FNormalStyle then
  begin
    hasTarget := True;
    for i := 0 to High(FNormal) do
      if SubOf(FNormal[i].Key, 'style', inner) then
        TyAnimPropPut(target, FNormal[i].Key, FNormal[i].Value);
  end;
  if hasTarget then
  begin
    keys := AnimKeyList;
    if ATransition then
    begin
      { a key of the style the target lacks takes createStyle's default
        (`key in targetStyle` reaches the prototype); a target key the style
        lacks starts from its default }
      for i := 0 to High(keys) do
        if SubOf(keys[i], 'style', inner) and (TyAnimPropIndex(target, keys[i]) < 0)
          and TyAnimStyleDefault(inner, v) then
          TyAnimPropPut(target, keys[i], v);
      for i := 0 to High(target) do
        if not HasAnimKey(target[i].Key) and SubOf(target[i].Key, 'style', inner)
          and TyAnimStyleDefault(inner, v) then
          SetAnimProp(target[i].Key, v);
      StopTracksDetached('style', target);
      DoAnimateTo(target, cfg, False, AName, True);
    end
    else
    begin
      { useStyle: the target is the whole style now }
      for i := 0 to High(keys) do
        if SubOf(keys[i], 'style', inner) and (TyAnimPropIndex(target, keys[i]) < 0) then
        begin
          TyAnimStyleDefault(inner, v);
          SetAnimProp(keys[i], v);
        end;
      for i := 0 to High(target) do SetAnimProp(target[i].Key, target[i].Value);
      AnimDirty('style');
    end;
  end;
  { ---- the shape (a Path's) ---- }
  if not FStatePath then Exit;
  hasTarget := False;
  target := nil;
  if AHasState and AState.HasShape then
  begin
    hasTarget := True;
    for i := 0 to High(FNormal) do
      if SubOf(FNormal[i].Key, 'shape', inner) then
        TyAnimPropPut(target, FNormal[i].Key, FNormal[i].Value);
    for i := 0 to High(AState.Props) do
      if SubOf(AState.Props[i].Key, 'shape', inner) then
        TyAnimPropPut(target, AState.Props[i].Key, AState.Props[i].Value);
  end
  else if FNormalShape then
  begin
    hasTarget := True;
    for i := 0 to High(FNormal) do
      if SubOf(FNormal[i].Key, 'shape', inner) then
        TyAnimPropPut(target, FNormal[i].Key, FNormal[i].Value);
  end;
  if not hasTarget then Exit;
  if ATransition then
  begin
    { only the primitive keys transition; an object (an array) is assigned }
    prims := nil;
    for i := 0 to High(target) do
      if target[i].Value.Kind = avkArray then
        SetAnimProp(target[i].Key, target[i].Value)
      else
        TyAnimPropPut(prims, target[i].Key, target[i].Value);
    if Length(prims) > 0 then
    begin
      StopTracksDetached('shape', prims);
      DoAnimateTo(prims, cfg, False, AName);
    end;
  end
  else
  begin
    for i := 0 to High(target) do SetAnimProp(target[i].Key, target[i].Value);
    AnimDirty('shape');
  end;
end;

procedure TTyAnimElement.UseStates(const AName: string; const AState: TTyAnimState;
  ANoAnimation: Boolean);
var
  g: TEngineGuard;
  trans: Boolean;
begin
  if AName = '' then
  begin
    ClearStates(ANoAnimation);
    Exit;
  end;
  { the same list: nothing at all }
  if AName = FCurStates then Exit;
  g := EnterEngine;
  try
    trans := CanTransition(ANoAnimation);
    SaveCurrentToNormal(AState);
    ApplyStateObj(AName, True, AState, trans);
    FCurStates := AName;
  finally
    LeaveEngine(g);
  end;
end;

procedure TTyAnimElement.ClearStates(ANoAnimation: Boolean);
var
  g: TEngineGuard;
  none: TTyAnimState;
begin
  { from normal to normal: nothing }
  if FCurStates = '' then Exit;
  g := EnterEngine;
  try
    none := Default(TTyAnimState);
    ApplyStateObj(TyAnimNormalState, False, none, CanTransition(ANoAnimation));
    FCurStates := '';
    FNormal := nil;
    FNormalStyle := False;
    FNormalShape := False;
  finally
    LeaveEngine(g);
  end;
end;

{ ==================== Bag ==================== }

function TTyAnimBag.IndexOfKey(const AKey: string): Integer;
var i: Integer;
begin
  for i := 0 to High(FKeys) do
    if FKeys[i] = AKey then Exit(i);
  Result := -1;
end;

procedure TTyAnimBag.AnimDirty(const ATargetName: string);
begin
  Inc(FDirtyCount);
end;

function TTyAnimBag.GetAnimProp(const AKey: string): TTyAnimValue;
var i: Integer;
begin
  i := IndexOfKey(AKey);
  if i < 0 then Exit(TyAnimNull);
  Result := TyAnimClone(FValues[i]);
end;

procedure TTyAnimBag.SetAnimProp(const AKey: string; const AValue: TTyAnimValue);
var i: Integer;
begin
  i := IndexOfKey(AKey);
  if i < 0 then
  begin
    i := Length(FKeys);
    SetLength(FKeys, i + 1);
    SetLength(FValues, i + 1);
    FKeys[i] := AKey;
  end;
  FValues[i] := TyAnimClone(AValue);
end;

function TTyAnimBag.AnimKeyList: TTyStringArray;
var i: Integer;
begin
  SetLength(Result, Length(FKeys));
  for i := 0 to High(FKeys) do Result[i] := FKeys[i];
end;

function TTyAnimBag.Num(const AKey: string): Double;
var v: TTyAnimValue;
begin
  v := GetAnimProp(AKey);
  if v.Kind in [avkNumber, avkBool] then Result := v.Num else Result := NaN;
end;

procedure TTyAnimBag.SetNum(const AKey: string; AValue: Double);
begin
  SetAnimProp(AKey, TyAnimNum(AValue));
end;

finalization
  FlushGrave;
  FreeAndNil(GGrave);
end.
