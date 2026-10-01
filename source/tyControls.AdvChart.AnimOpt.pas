unit tyControls.AdvChart.AnimOpt;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- which animation an option asks for, and ECharts'
  initProps / updateProps / removeElement over the engine. [Batch 87, AN1]

  WHERE A SETTING COMES FROM. Model.getShallow on the animatable model: the
  series' own option -- what the author wrote, and where they wrote nothing
  the series type's default (a line's easing is 'linear', a candlestick's
  duration 300) -- then the root option, then the global defaults
  (model/globalDefault.ts: animation 'auto', 1000 / 500 ms, 'cubicInOut',
  threshold 2000, and NO delay). A key written as null falls through to the
  next level, and a series key written as null also hides the type default,
  because upstream merges the defaults only into keys the option does not
  have. A root-level animationDuration therefore reaches every series that
  sets none of its own -- but not a line's easing, whose default sits in the
  series option.

  IS IT ON. SeriesModel.isAnimationEnabled: `animation` truthy along that
  chain, and the series' data count NOT above `animationThreshold` -- strictly
  greater turns it off, so a count equal to the threshold still animates. A
  component (Model.isAnimationEnabled) has no threshold.

  THE TIMING (basicTransition.ts getAnimationConfig). enter reads
  animationDuration / Easing / Delay, update their *Update twins, and LEAVE
  READS NEITHER: 200 ms, 'cubicOut', delay 0, whatever the option says --
  upstream passes removeOpt or an empty object, never nothing. An update
  payload's animation (dataZoom, roam, resize) overrides all three. A
  function form is a named handler here: `animationDelay: '@Name'` calls the
  TTyAnimTimingHandler registered as Name with the element's data index, and
  AHasIndex False where upstream passes null (the line clip, a symbol group's
  position). A duration that comes to nothing, not-a-number included, is 0.

  animateOrSetProps. Unless leaving, stop the element's 'leave' animation
  (an element that comes back cancels its fade). With a config and a
  duration above 0: animateTo (animateFrom for isFrom) with setToFinal for
  enter and update, scope = the type, force when there is a done or a during.
  Otherwise: stop everything, set the props at once, call during(1) and done.

  DEVIATIONS (tiny): a STRING duration or delay is taken by Number() --
  upstream keeps the string, which for a delay concatenates onto the clock
  and freezes the clip at its start; an unregistered handler name is
  not-a-number, so a duration handler that is missing means no animation. }
interface
uses SysUtils, Classes, Math, fpjson,
  tyControls.AdvChart.Anim;

type
  TTyAnimType = (atEnter, atUpdate, atLeave);

  { a function-valued animationDelay / animationDuration (and the Update
    twins): the element's data index, AHasIndex False where upstream passes
    null or undefined }
  TTyAnimTimingHandler = function(ADataIndex: Integer; AHasIndex: Boolean): Double of object;

  TTyAnimOptKind = (aokUndefined, aokNull, aokBool, aokNumber, aokString,
    aokHandler, aokObject);

  { one option value as getShallow answers it }
  TTyAnimOptValue = record
    Kind: TTyAnimOptKind;
    Num: Double;      // aokNumber; aokBool 0 or 1
    Str: string;      // aokString; aokHandler: the name after '@'
  end;

  { removeOpt, or an update payload's animation: each part only when set }
  TTyAnimOverride = record
    HasDuration, HasEasing, HasDelay: Boolean;
    Duration, Delay: Double;
    Easing: string;
  end;

  { The animatable model. Present False is upstream's null model (BarView's
    animationModel when the series does not animate): nothing animates. }
  TTyAnimModel = record
    Present: Boolean;
    { the series' or component's own option object (nil: none) }
    Own: TJSONData;
    { the root option object (nil: none) }
    Root: TJSONData;
    { the series type ('bar', 'line' ...) or a component key ('markLine',
      'markArea', 'axisPointer', 'tooltip.axisPointer', 'legend.scroll',
      'timeline.checkpointStyle') -- picks the type defaults }
    TypeKey: string;
    { SeriesModel: the threshold applies; a component has none }
    IsSeries: Boolean;
    { getData().count(): the series' data count after filtering }
    DataCount: Integer;
    { THE UPDATE PAYLOAD'S animation, model.ecModel.getUpdatePayload():
      the action the render runs for (a dataZoom from the inside roam or a
      realtime slider) overrides every enter, update and leave timing it
      makes; a call's own payload goes first [Batch 96] }
    Payload: TTyAnimOverride;
    HasPayload: Boolean;
  end;

  TTyAnimTiming = record
    Duration: Double;
    { may be not-a-number: animateOrSetProps takes `delay || 0` }
    Delay: Double;
    { '' is upstream's undefined: no easing, linear }
    Easing: string;
  end;

  { the rest of an animateOrSetProps call }
  TTyAnimCallOpts = record
    DataIndex: Integer;
    HasIndex: Boolean;
    Done: TTyAnimNotify;
    During: TTyAnimDuring;
    IsFrom: Boolean;
    RemoveOpt: TTyAnimOverride;
    Payload: TTyAnimOverride;
    HasPayload: Boolean;
  end;

{ ---- the handler registry ('@Name') ---- }
procedure TyChartRegisterAnimTiming(const AName: string; AHandler: TTyAnimTimingHandler);
procedure TyChartUnregisterAnimTiming(const AName: string);
function TyChartFindAnimTiming(const AName: string; out AHandler: TTyAnimTimingHandler): Boolean;
procedure TyChartClearAnimTimings;

{ ---- models ---- }
{ Series ASeriesIndex of the root option ARoot (a bare `series` object is
  series 0), typed by its own `type`. }
function TyAnimSeriesModel(ARoot: TJSONData; ASeriesIndex: Integer;
  ADataCount: Integer): TTyAnimModel;
function TyAnimComponentModel(AOwn, ARoot: TJSONData; const ATypeKey: string): TTyAnimModel;
function TyAnimNoModel: TTyAnimModel;

{ The defaults a series type or component writes into its own option. }
function TyAnimTypeDefault(const ATypeKey, AKey: string; out AValue: TTyAnimOptValue): Boolean;
{ model/globalDefault.ts }
function TyAnimGlobalDefault(const AKey: string; out AValue: TTyAnimOptValue): Boolean;
{ Model.getShallow for one of the animation keys }
function TyAnimGetShallow(const AModel: TTyAnimModel; const AKey: string): TTyAnimOptValue;
{ JavaScript truthiness of a value }
function TyAnimOptTruthy(const AValue: TTyAnimOptValue): Boolean;
{ isAnimationEnabled: series (threshold, strictly greater) or component }
function TyAnimIsEnabled(const AModel: TTyAnimModel): Boolean;

{ ---- the config ---- }
function TyAnimCallAt(ADataIndex: Integer): TTyAnimCallOpts;
function TyAnimCallNoIndex: TTyAnimCallOpts;
function TyAnimNoOverride: TTyAnimOverride;

{ getAnimationConfig: False when the model does not animate (upstream's
  null); otherwise the timing, with the functions called. }
function TyAnimGetConfig(AType: TTyAnimType; const AModel: TTyAnimModel;
  const AOpts: TTyAnimCallOpts; out ATiming: TTyAnimTiming): Boolean;

{ ---- the wrappers ---- }
procedure TyAnimateOrSetProps(AType: TTyAnimType; AEl: TTyAnimElement;
  const AProps: TTyAnimProps; const AModel: TTyAnimModel; const AOpts: TTyAnimCallOpts);
procedure TyInitProps(AEl: TTyAnimElement; const AProps: TTyAnimProps;
  const AModel: TTyAnimModel; const AOpts: TTyAnimCallOpts);
procedure TyUpdateProps(AEl: TTyAnimElement; const AProps: TTyAnimProps;
  const AModel: TTyAnimModel; const AOpts: TTyAnimCallOpts);
{ removeElement: nothing when the element is already removed (no driver, or
  a 'leave' animation running) }
procedure TyRemoveElement(AEl: TTyAnimElement; const AProps: TTyAnimProps;
  const AModel: TTyAnimModel; const AOpts: TTyAnimCallOpts);
{ fadeOutDisplayable: style.opacity to 0 with leave timing, then ADone }
procedure TyFadeOutElement(AEl: TTyAnimElement; const AModel: TTyAnimModel;
  ADataIndex: Integer; AHasIndex: Boolean; ADone: TTyAnimNotify);

implementation

uses tyControls.AdvChart.Data;

type
  TTimingEntry = record
    Name: string;
    Handler: TTyAnimTimingHandler;
  end;

var
  GTimings: array of TTimingEntry;

{ ==================== registry ==================== }

function IndexOfTiming(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GTimings) do
    if GTimings[i].Name = AName then Exit(i);
  Result := -1;
end;

procedure TyChartRegisterAnimTiming(const AName: string; AHandler: TTyAnimTimingHandler);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfTiming(AName);
  if i < 0 then
  begin
    i := Length(GTimings);
    SetLength(GTimings, i + 1);
    GTimings[i].Name := AName;
  end;
  GTimings[i].Handler := AHandler;
end;

procedure TyChartUnregisterAnimTiming(const AName: string);
var i, j: Integer;
begin
  i := IndexOfTiming(AName);
  if i < 0 then Exit;
  for j := i to High(GTimings) - 1 do GTimings[j] := GTimings[j + 1];
  SetLength(GTimings, Length(GTimings) - 1);
end;

function TyChartFindAnimTiming(const AName: string; out AHandler: TTyAnimTimingHandler): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfTiming(AName);
  Result := i >= 0;
  if Result then AHandler := GTimings[i].Handler;
end;

procedure TyChartClearAnimTimings;
begin
  GTimings := nil;
end;

{ ==================== values ==================== }

function OptUndefined: TTyAnimOptValue;
begin
  Result := Default(TTyAnimOptValue);
  Result.Kind := aokUndefined;
  Result.Num := NaN;
end;

function OptNum(AV: Double): TTyAnimOptValue;
begin
  Result := OptUndefined;
  Result.Kind := aokNumber;
  Result.Num := AV;
end;

function OptStr(const AText: string): TTyAnimOptValue;
begin
  Result := OptUndefined;
  Result.Kind := aokString;
  Result.Str := AText;
end;

function OptBool(AB: Boolean): TTyAnimOptValue;
begin
  Result := OptUndefined;
  Result.Kind := aokBool;
  if AB then Result.Num := 1 else Result.Num := 0;
end;

function OptNull: TTyAnimOptValue;
begin
  Result := OptUndefined;
  Result.Kind := aokNull;
end;

function OptOf(AData: TJSONData): TTyAnimOptValue;
var s: string;
begin
  if AData = nil then Exit(OptUndefined);
  case AData.JSONType of
    jtNull: Result := OptNull;
    jtBoolean: Result := OptBool(AData.AsBoolean);
    jtNumber: Result := OptNum(AData.AsFloat);
    jtString:
      begin
        s := AData.AsString;
        if (Length(s) > 1) and (s[1] = '@') then
        begin
          Result := OptUndefined;
          Result.Kind := aokHandler;
          Result.Str := Copy(s, 2, MaxInt);
        end
        else Result := OptStr(s);
      end;
  else
    Result := OptUndefined;
    Result.Kind := aokObject;
  end;
end;

function IsNullish(const AV: TTyAnimOptValue): Boolean; inline;
begin
  Result := AV.Kind in [aokUndefined, aokNull];
end;

function TyAnimOptTruthy(const AValue: TTyAnimOptValue): Boolean;
begin
  case AValue.Kind of
    aokUndefined, aokNull: Result := False;
    aokBool: Result := AValue.Num <> 0;
    aokNumber: Result := (not IsNan(AValue.Num)) and (AValue.Num <> 0);
    aokString: Result := AValue.Str <> '';
  else
    Result := True; // a handler is a function; an object is truthy
  end;
end;

{ Number() of a value, for a comparison or an arithmetic use }
function OptToNumber(const AV: TTyAnimOptValue): Double;
begin
  case AV.Kind of
    aokNull: Result := 0;
    aokBool, aokNumber: Result := AV.Num;
    aokString: Result := TyJsToNumber(AV.Str);
  else
    Result := NaN;
  end;
end;

{ ==================== defaults ==================== }

function TyAnimGlobalDefault(const AKey: string; out AValue: TTyAnimOptValue): Boolean;
begin
  Result := True;
  if AKey = 'animation' then AValue := OptStr('auto')
  else if AKey = 'animationDuration' then AValue := OptNum(1000)
  else if AKey = 'animationDurationUpdate' then AValue := OptNum(500)
  else if AKey = 'animationEasing' then AValue := OptStr('cubicInOut')
  else if AKey = 'animationEasingUpdate' then AValue := OptStr('cubicInOut')
  else if AKey = 'animationThreshold' then AValue := OptNum(2000)
  else
  begin
    AValue := OptUndefined;
    Result := False;
  end;
end;

function TyAnimTypeDefault(const ATypeKey, AKey: string; out AValue: TTyAnimOptValue): Boolean;
  function Hit(const AType, AName: string; const AV: TTyAnimOptValue): Boolean;
  begin
    Result := (ATypeKey = AType) and (AKey = AName);
    if Result then AValue := AV;
  end;
begin
  AValue := OptUndefined;
  Result :=
    { LineSeries.ts:218 }
    Hit('line', 'animationEasing', OptStr('linear'))
    { CandlestickSeries.ts:147-148 }
    or Hit('candlestick', 'animationEasing', OptStr('linear'))
    or Hit('candlestick', 'animationDuration', OptNum(300))
    { BoxplotSeries.ts:135 }
    or Hit('boxplot', 'animationDuration', OptNum(800))
    { PieSeries.ts:328-337 }
    or Hit('pie', 'animationDuration', OptNum(1000))
    or Hit('pie', 'animationEasing', OptStr('cubicInOut'))
    or Hit('pie', 'animationDurationUpdate', OptNum(500))
    or Hit('pie', 'animationEasingUpdate', OptStr('cubicInOut'))
    { SunburstSeries.ts:285-286 }
    or Hit('sunburst', 'animationDuration', OptNum(1000))
    or Hit('sunburst', 'animationDurationUpdate', OptNum(500))
    { TreeSeries.ts:311-315 }
    or Hit('tree', 'animationEasing', OptStr('linear'))
    or Hit('tree', 'animationDuration', OptNum(700))
    or Hit('tree', 'animationDurationUpdate', OptNum(500))
    { TreemapSeries.ts:278-280 }
    or Hit('treemap', 'animation', OptBool(True))
    or Hit('treemap', 'animationDurationUpdate', OptNum(900))
    or Hit('treemap', 'animationEasing', OptStr('quinticInOut'))
    { SankeySeries.ts:369-371 }
    or Hit('sankey', 'animationEasing', OptStr('linear'))
    or Hit('sankey', 'animationDuration', OptNum(1000))
    { ThemeRiverSeries.ts:313, ParallelSeries.ts:155 }
    or Hit('themeRiver', 'animationEasing', OptStr('linear'))
    or Hit('parallel', 'animationEasing', OptStr('linear'))
    { MarkLineModel.ts:145, MarkAreaModel.ts:90 }
    or Hit('markLine', 'animationEasing', OptStr('linear'))
    or Hit('markArea', 'animation', OptBool(False))
    { AxisPointerModel.ts:101-102 }
    or Hit('axisPointer', 'animation', OptNull)
    or Hit('axisPointer', 'animationDurationUpdate', OptNum(200))
    { TooltipModel.ts:167-169 }
    or Hit('tooltip.axisPointer', 'animation', OptStr('auto'))
    or Hit('tooltip.axisPointer', 'animationDurationUpdate', OptNum(200))
    or Hit('tooltip.axisPointer', 'animationEasingUpdate', OptStr('exponentialOut'))
    { ScrollableLegendModel.ts:106 }
    or Hit('legend.scroll', 'animationDurationUpdate', OptNum(800))
    { SliderTimelineModel.ts:87-89 }
    or Hit('timeline.checkpointStyle', 'animation', OptBool(True))
    or Hit('timeline.checkpointStyle', 'animationDuration', OptNum(300))
    or Hit('timeline.checkpointStyle', 'animationEasing', OptStr('quinticInOut'));
end;

{ ==================== models ==================== }

function TyAnimNoModel: TTyAnimModel;
begin
  Result := Default(TTyAnimModel);
  Result.Present := False;
end;

function TyAnimSeriesModel(ARoot: TJSONData; ASeriesIndex: Integer;
  ADataCount: Integer): TTyAnimModel;
var
  s, t: TJSONData;
begin
  Result := Default(TTyAnimModel);
  Result.Present := True;
  Result.IsSeries := True;
  Result.DataCount := ADataCount;
  if (ARoot <> nil) and (ARoot.JSONType = jtObject) then
  begin
    Result.Root := ARoot;
    s := TJSONObject(ARoot).Find('series');
    if s <> nil then
    begin
      if s.JSONType = jtArray then
      begin
        if (ASeriesIndex >= 0) and (ASeriesIndex < s.Count) then
          Result.Own := s.Items[ASeriesIndex];
      end
      else if (s.JSONType = jtObject) and (ASeriesIndex = 0) then
        Result.Own := s;
    end;
  end;
  if (Result.Own <> nil) and (Result.Own.JSONType = jtObject) then
  begin
    t := TJSONObject(Result.Own).Find('type');
    if (t <> nil) and (t.JSONType = jtString) then Result.TypeKey := t.AsString;
  end
  else
    Result.Own := nil;
end;

function TyAnimComponentModel(AOwn, ARoot: TJSONData; const ATypeKey: string): TTyAnimModel;
begin
  Result := Default(TTyAnimModel);
  Result.Present := True;
  Result.IsSeries := False;
  if (AOwn <> nil) and (AOwn.JSONType = jtObject) then Result.Own := AOwn;
  if (ARoot <> nil) and (ARoot.JSONType = jtObject) then Result.Root := ARoot;
  Result.TypeKey := ATypeKey;
end;

function TyAnimGetShallow(const AModel: TTyAnimModel; const AKey: string): TTyAnimOptValue;
var d: TJSONData;
begin
  { the model's own option: the author's key where there is one (null
    included), else the type's default }
  Result := OptUndefined;
  d := nil;
  if AModel.Own <> nil then d := TJSONObject(AModel.Own).Find(AKey);
  if d <> nil then Result := OptOf(d)
  else TyAnimTypeDefault(AModel.TypeKey, AKey, Result);
  if not IsNullish(Result) then Exit;
  { the parent: the root option merged over the global defaults }
  d := nil;
  if AModel.Root <> nil then d := TJSONObject(AModel.Root).Find(AKey);
  if d <> nil then Result := OptOf(d)
  else TyAnimGlobalDefault(AKey, Result);
end;

function TyAnimIsEnabled(const AModel: TTyAnimModel): Boolean;
var v: TTyAnimOptValue;
begin
  if not AModel.Present then Exit(False);
  v := TyAnimGetShallow(AModel, 'animation');
  Result := TyAnimOptTruthy(v);
  { count() > animationThreshold: strictly greater, and a comparison with
    not-a-number is false }
  if Result and AModel.IsSeries then
    if Double(AModel.DataCount) > OptToNumber(TyAnimGetShallow(AModel, 'animationThreshold')) then
      Result := False;
end;

{ ==================== the config ==================== }

function TyAnimNoOverride: TTyAnimOverride;
begin
  Result := Default(TTyAnimOverride);
end;

function TyAnimCallAt(ADataIndex: Integer): TTyAnimCallOpts;
begin
  Result := Default(TTyAnimCallOpts);
  Result.DataIndex := ADataIndex;
  Result.HasIndex := True;
end;

function TyAnimCallNoIndex: TTyAnimCallOpts;
begin
  Result := Default(TTyAnimCallOpts);
  Result.DataIndex := -1;
  Result.HasIndex := False;
end;

function CallTiming(const AV: TTyAnimOptValue; const AOpts: TTyAnimCallOpts): Double;
var h: TTyAnimTimingHandler;
begin
  if AV.Kind = aokHandler then
  begin
    if TyChartFindAnimTiming(AV.Str, h) and Assigned(h) then
      Result := h(AOpts.DataIndex, AOpts.HasIndex)
    else
      Result := NaN;
  end
  else if IsNullish(AV) then
    Result := NaN
  else
    Result := OptToNumber(AV);
end;

function EasingOf(const AV: TTyAnimOptValue): string;
begin
  case AV.Kind of
    aokString: Result := AV.Str;
    aokHandler: Result := '@' + AV.Str;
  else
    { undefined, null, a number: `if (easing)` or a failed lookup -- linear }
    Result := '';
  end;
end;

function TyAnimGetConfig(AType: TTyAnimType; const AModel: TTyAnimModel;
  const AOpts: TTyAnimCallOpts; out ATiming: TTyAnimTiming): Boolean;
var
  dur, del, eas: TTyAnimOptValue;
  mask: TFPUExceptionMask;
begin
  ATiming.Duration := 0;
  ATiming.Delay := 0;
  ATiming.Easing := '';
  Result := TyAnimIsEnabled(AModel);
  if not Result then Exit;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    if AType = atLeave then
    begin
      // removeOpt || {} -- always an object: the model is never read
      if AOpts.RemoveOpt.HasDuration then dur := OptNum(AOpts.RemoveOpt.Duration)
      else dur := OptNum(200);
      if AOpts.RemoveOpt.HasEasing then eas := OptStr(AOpts.RemoveOpt.Easing)
      else eas := OptStr('cubicOut');
      del := OptNum(0);
    end
    else if AType = atUpdate then
    begin
      dur := TyAnimGetShallow(AModel, 'animationDurationUpdate');
      eas := TyAnimGetShallow(AModel, 'animationEasingUpdate');
      del := TyAnimGetShallow(AModel, 'animationDelayUpdate');
    end
    else
    begin
      dur := TyAnimGetShallow(AModel, 'animationDuration');
      eas := TyAnimGetShallow(AModel, 'animationEasing');
      del := TyAnimGetShallow(AModel, 'animationDelay');
    end;
    if AOpts.HasPayload then
    begin
      if AOpts.Payload.HasDuration then dur := OptNum(AOpts.Payload.Duration);
      if AOpts.Payload.HasEasing then eas := OptStr(AOpts.Payload.Easing);
      if AOpts.Payload.HasDelay then del := OptNum(AOpts.Payload.Delay);
    end
    { the model's: ecModel.getUpdatePayload().animation [Batch 96] }
    else if AModel.HasPayload then
    begin
      if AModel.Payload.HasDuration then dur := OptNum(AModel.Payload.Duration);
      if AModel.Payload.HasEasing then eas := OptStr(AModel.Payload.Easing);
      if AModel.Payload.HasDelay then del := OptNum(AModel.Payload.Delay);
    end;
    { the delay function first, then the duration's, as upstream calls them }
    ATiming.Delay := CallTiming(del, AOpts);
    ATiming.Duration := CallTiming(dur, AOpts);
    { duration || 0 }
    if IsNan(ATiming.Duration) then ATiming.Duration := 0;
    ATiming.Easing := EasingOf(eas);
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

{ ==================== the wrappers ==================== }

procedure TyAnimateOrSetProps(AType: TTyAnimType; AEl: TTyAnimElement;
  const AProps: TTyAnimProps; const AModel: TTyAnimModel; const AOpts: TTyAnimCallOpts);
var
  timing: TTyAnimTiming;
  cfg: TTyAnimCfg;
  ok: Boolean;
begin
  if AEl = nil then Exit;
  if AType <> atLeave then AEl.StopAnimation('leave');
  ok := TyAnimGetConfig(AType, AModel, AOpts, timing);
  if ok and (timing.Duration > 0) then
  begin
    cfg := Default(TTyAnimCfg);
    cfg.Duration := timing.Duration;
    cfg.HasDuration := True;
    { delay || 0 }
    if IsNan(timing.Delay) then cfg.Delay := 0 else cfg.Delay := timing.Delay;
    cfg.Easing := timing.Easing;
    cfg.Done := AOpts.Done;
    cfg.Force := Assigned(AOpts.Done) or Assigned(AOpts.During);
    cfg.SetToFinal := AType <> atLeave;
    case AType of
      atEnter: cfg.Scope := 'enter';
      atUpdate: cfg.Scope := 'update';
      atLeave: cfg.Scope := 'leave';
    end;
    cfg.During := AOpts.During;
    if AOpts.IsFrom then AEl.AnimateFrom(AProps, cfg)
    else AEl.AnimateTo(AProps, cfg);
  end
  else
  begin
    AEl.StopAnimation;
    { isFrom: the props are the FROM values, so there is nothing to set }
    if not AOpts.IsFrom then AEl.Attr(AProps);
    { during at least once }
    if Assigned(AOpts.During) then AOpts.During(1);
    if Assigned(AOpts.Done) then AOpts.Done();
  end;
end;

procedure TyInitProps(AEl: TTyAnimElement; const AProps: TTyAnimProps;
  const AModel: TTyAnimModel; const AOpts: TTyAnimCallOpts);
begin
  TyAnimateOrSetProps(atEnter, AEl, AProps, AModel, AOpts);
end;

procedure TyUpdateProps(AEl: TTyAnimElement; const AProps: TTyAnimProps;
  const AModel: TTyAnimModel; const AOpts: TTyAnimCallOpts);
begin
  TyAnimateOrSetProps(atUpdate, AEl, AProps, AModel, AOpts);
end;

procedure TyRemoveElement(AEl: TTyAnimElement; const AProps: TTyAnimProps;
  const AModel: TTyAnimModel; const AOpts: TTyAnimCallOpts);
begin
  if (AEl = nil) or AEl.IsRemoved then Exit;
  TyAnimateOrSetProps(atLeave, AEl, AProps, AModel, AOpts);
end;

procedure TyFadeOutElement(AEl: TTyAnimElement; const AModel: TTyAnimModel;
  ADataIndex: Integer; AHasIndex: Boolean; ADone: TTyAnimNotify);
var o: TTyAnimCallOpts;
begin
  o := TyAnimCallNoIndex;
  o.DataIndex := ADataIndex;
  o.HasIndex := AHasIndex;
  o.Done := ADone;
  TyRemoveElement(AEl, TyAnimProps([TyAnimProp('style.opacity', TyAnimNum(0))]),
    AModel, o);
end;

end.
