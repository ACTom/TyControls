unit tyControls.AdvChart.DataZoom;
{$mode objfpc}{$H+}
{ dataZoom: a window onto an axis -- which axes a dataZoom drives, the window
  it asks for in percents or in values, and that window clamped, spanned and
  rounded the way ECharts' AxisProxy.calculateDataWindow does it.

  THE PERCENTS ARE OF THE RAW EXTENT, the axis' range before "nice"
  (upstream's noZoomEffMM): data, min/max, boundaryGap, zero, a bar's start.
  An end at exactly 0% or 100% pins nothing and the axis nices that side as
  if there were no zoom; any other end becomes a fixed axis bound. The
  caller measures the raw extent and applies the pins; this unit is the
  arithmetic between the two.

  THE WINDOW IS SHIFTED, NOT CLIPPED, when it runs off the extent:
  sliderMove keeps its span. And the value is rounded (toFixed, not
  Math.round) only where it came from a percent, to a precision from the
  axis' pixel span -- or to a whole number on a category or time axis --
  while the percent itself keeps whatever the author wrote.

  PURE: option in, numbers out. }
interface
uses SysUtils, Math, fpjson,
     tyControls.AdvChart.Option, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder;

type
  TTyDzRangeMode = (dzmPercent, dzmValue);
  TTyDzFilterMode = (dzfFilter, dzfWeakFilter, dzfEmpty, dzfNone);

  { One axis a dataZoom drives: 'x', 'y', 'radius' or 'angle' [Batch 113:
    the polar's two], and the axis' component index. }
  TTyDzTarget = record
    Dim: string;
    AxisIndex: Integer;
  end;
  TTyDzTargetArray = array of TTyDzTarget;

  { An option value as written -- a number (NaN included), a string, or
    nothing. `null` is nothing, as `!= null` reads it. }
  TTyDzArg = record
    Given: Boolean;
    IsStr: Boolean;
    Num: Double;
    Str: string;
  end;

  TTyDataZoomSpec = record
    Index: Integer;
    { 'slider' or 'inside'; '' for a type this port does not know }
    SubType: string;
    Orient: string;
    NoTarget: Boolean;
    Targets: TTyDzTargetArray;
    { per end, start / end: which of percent and value it is read from }
    Mode: array[0..1] of TTyDzRangeMode;
    { start / end and startValue / endValue, as settled -- what the author
      actually wrote, never the defaults }
    Percent: array[0..1] of TTyDzArg;
    Value: array[0..1] of TTyDzArg;
    FilterMode: TTyDzFilterMode;
    MinSpan, MaxSpan, MinValueSpan, MaxValueSpan: TTyDzArg;
  end;
  TTyDataZoomSpecArray = array of TTyDataZoomSpec;

  { _minMaxSpan: percent and value spans, each NaN where not given }
  TTyDzSpans = record
    MinSpan, MaxSpan, MinValueSpan, MaxValueSpan: Double;
  end;

  TTyDzWindow = record
    Value: array[0..1] of Double;
    Percent: array[0..1] of Double;
    PercentInverted: array[0..1] of Double;
    { NaN: nothing was rounded }
    Precision: Double;
  end;

function TyDataZoomCount(AOption: TTyChartOption): Integer;
{ The model, targets resolved against ABuild's axes. }
function TyDataZoomSpecOf(AOption: TTyChartOption; AIndex: Integer;
  ABuild: TTyChartBuild): TTyDataZoomSpec;
{ THE TOOLBOX'S OWN dataZooms: `toolbox.feature.dataZoom` written makes one
  'select' dataZoom per axis it covers (every x and y axis unless it names
  them), after the author's -- full-window, filterMode the feature's. They
  draw nothing, but they host every axis no author's dataZoom does, and
  filter it. }
function TyDataZoomSelectSpecs(AOption: TTyChartOption; ABuild: TTyChartBuild;
  AFirstIndex: Integer): TTyDataZoomSpecArray;
{ The dataZoom drives this axis. }
function TyDzTargets(const ASpec: TTyDataZoomSpec; const ADim: string;
  AAxisIndex: Integer): Boolean;

{ scale.parse of a startValue / endValue / value span, on AAxis }
function TyDzParse(AAxis: TTyAxis; const AArg: TTyDzArg): Double;
{ _updateMinMaxSpan over the extent [ALo, AHi] }
function TyDzSpansOf(const ASpec: TTyDataZoomSpec; AAxis: TTyAxis;
  ALo, AHi: Double): TTyDzSpans;
{ calculateDataWindow over the raw extent [ALo, AHi]. APxSpan: the axis'
  pixel length, CSS px, before the labels shrink the grid. }
function TyDzCalculateWindow(const ASpec: TTyDataZoomSpec; AAxis: TTyAxis;
  ALo, AHi, APxSpan: Double): TTyDzWindow;

{ ---- the arithmetic, exported for the tests ---- }
{ util/number linearMap }
function TyDzLinearMap(AValue, AD0, AD1, AR0, AR1: Double; AClamp: Boolean): Double;
{ sliderMove(delta, ends, extent, 'all' | 0 | 1, minSpan, maxSpan); NaN is
  a span not given }
procedure TyDzSliderMove(ADelta: Double; var AEnds: array of Double;
  AExt0, AExt1: Double; AHandle: Integer; AMinSpan, AMaxSpan: Double);
{ util/number round: +(+x).toFixed(clamp(p, 0, 20)); NaN p is +x }
function TyDzRound(AValue, APrecision: Double): Double;

implementation

uses tyControls.AdvChart.Scale, tyControls.AdvChart.Data,
     tyControls.AdvChart.Stack, tyControls.AdvChart.Complete;

{ ---- small things ---- }

function ObjOf(A: TJSONData): TJSONObject;
begin
  if (A <> nil) and (A.JSONType = jtObject) then Result := TJSONObject(A)
  else Result := nil;
end;

function ArgOf(A: TJSONData): TTyDzArg;
begin
  Result := Default(TTyDzArg);
  Result.Num := NaN;
  if (A = nil) or (A.JSONType = jtNull) then Exit;
  Result.Given := True;
  case A.JSONType of
    jtNumber: Result.Num := A.AsFloat;
    jtString:
      begin
        Result.IsStr := True;
        Result.Str := A.AsString;
        Result.Num := TyJsToNumber(A.AsString);
      end;
    jtBoolean: if A.AsBoolean then Result.Num := 1 else Result.Num := 0;
  else
    Result.Num := NaN;
  end;
end;

function TyDzLinearMap(AValue, AD0, AD1, AR0, AR1: Double; AClamp: Boolean): Double;
var subDomain, subRange: Double;
begin
  subDomain := AD1 - AD0;
  subRange := AR1 - AR0;
  if (not IsNan(subDomain)) and (subDomain = 0) then
  begin
    if (not IsNan(subRange)) and (subRange = 0) then Exit(AR0);
    Exit((AR0 + AR1) / 2);
  end;
  { every comparison with a not-a-number is false, as in JavaScript }
  if AClamp then
  begin
    if (not IsNan(subDomain)) and (subDomain > 0) then
    begin
      if (not IsNan(AValue)) and (AValue <= AD0) then Exit(AR0)
      else if (not IsNan(AValue)) and (AValue >= AD1) then Exit(AR1);
    end
    else
    begin
      if (not IsNan(AValue)) and (AValue >= AD0) then Exit(AR0)
      else if (not IsNan(AValue)) and (AValue <= AD1) then Exit(AR1);
    end;
  end
  else
  begin
    if (not IsNan(AValue)) and (AValue = AD0) then Exit(AR0);
    if (not IsNan(AValue)) and (AValue = AD1) then Exit(AR1);
  end;
  Result := (AValue - AD0) / subDomain * subRange + AR0;
end;

function TyDzRound(AValue, APrecision: Double): Double;
var p: Integer;
begin
  if IsNan(APrecision) then Exit(AValue);
  if APrecision < 0 then p := 0
  else if APrecision > 20 then p := 20
  else p := Trunc(APrecision);
  Result := TyJsToFixed(AValue, p);
end;

{ Math.min / Math.max: a not-a-number wins }
function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

{ restrict(value, [lo, hi]), a NaN bound being `null` -- no bound }
function Restrict(AValue, ALo, AHi: Double): Double;
var lo, hi: Double;
begin
  if IsNan(AHi) then hi := Infinity else hi := AHi;
  if IsNan(ALo) then lo := NegInfinity else lo := ALo;
  Result := JsMin(hi, JsMax(lo, AValue));
end;

procedure SpanSign(const AEnds: array of Double; AHandle: Integer;
  out ASpan: Double; out ASign: Integer);
var dist: Double;
begin
  dist := AEnds[AHandle] - AEnds[1 - AHandle];
  ASpan := Abs(dist);
  if (not IsNan(dist)) and (dist > 0) then ASign := -1
  else if (not IsNan(dist)) and (dist < 0) then ASign := 1
  else if AHandle <> 0 then ASign := -1
  else ASign := 1;
end;

procedure TyDzSliderMove(ADelta: Double; var AEnds: array of Double;
  AExt0, AExt1: Double; AHandle: Integer; AMinSpan, AMaxSpan: Double);
var
  extentSpan, handleSpan, extentMinSpan, span0, span1: Double;
  sign0, sign1: Integer;
  real0, real1: Double;
begin
  if IsNan(ADelta) then ADelta := 0;
  extentSpan := TyAddSafe(AExt1, -AExt0);
  if not IsNan(AMinSpan) then AMinSpan := Restrict(AMinSpan, 0, extentSpan);
  if not IsNan(AMaxSpan) then
  begin
    if IsNan(AMinSpan) then AMaxSpan := JsMax(AMaxSpan, 0)
    else AMaxSpan := JsMax(AMaxSpan, AMinSpan);
  end;
  { 'all': both ends move, the span forced into [min, max] }
  if AHandle < 0 then
  begin
    handleSpan := Abs(TyAddSafe(AEnds[1], -AEnds[0]));
    handleSpan := Restrict(handleSpan, 0, extentSpan);
    AMinSpan := Restrict(handleSpan, AMinSpan, AMaxSpan);
    AMaxSpan := AMinSpan;
    AHandle := 0;
  end;
  AEnds[0] := Restrict(AEnds[0], AExt0, AExt1);
  AEnds[1] := Restrict(AEnds[1], AExt0, AExt1);
  SpanSign(AEnds, AHandle, span0, sign0);
  AEnds[AHandle] := AEnds[AHandle] + ADelta;
  { `minSpan || 0`: NaN and zero are nought }
  if IsNan(AMinSpan) then extentMinSpan := 0 else extentMinSpan := AMinSpan;
  real0 := AExt0;
  real1 := AExt1;
  if sign0 < 0 then real0 := TyAddSafe(real0, extentMinSpan)
  else real1 := TyAddSafe(real1, -extentMinSpan);
  AEnds[AHandle] := Restrict(AEnds[AHandle], real0, real1);
  SpanSign(AEnds, AHandle, span1, sign1);
  if (not IsNan(AMinSpan)) and ((sign1 <> sign0)
    or ((not IsNan(span1)) and (span1 < AMinSpan))) then
    AEnds[1 - AHandle] := TyAddSafe(AEnds[AHandle], sign0 * AMinSpan);
  SpanSign(AEnds, AHandle, span1, sign1);
  if (not IsNan(AMaxSpan)) and (not IsNan(span1)) and (span1 > AMaxSpan) then
    AEnds[1 - AHandle] := TyAddSafe(AEnds[AHandle], sign1 * AMaxSpan);
end;

{ zrUtil's asc on two numbers: V8's insertion step swaps only when the
  comparator a - b answers below nought }
procedure Asc(var A: array of Double);
var t: Double;
begin
  if (not IsNan(A[1])) and (not IsNan(A[0])) and (A[1] - A[0] < 0) then
  begin
    t := A[0];
    A[0] := A[1];
    A[1] := t;
  end;
end;

{ ---- the model ---- }

function TyDataZoomCount(AOption: TTyChartOption): Integer;
begin
  if AOption = nil then Exit(0);
  Result := AOption.ComponentCount('dataZoom');
end;

procedure AddTarget(var ASpec: TTyDataZoomSpec; const ADim: string; AIndex: Integer);
var k, n: Integer;
begin
  for k := 0 to High(ASpec.Targets) do
    if (ASpec.Targets[k].Dim = ADim) and (ASpec.Targets[k].AxisIndex = AIndex) then Exit;
  n := Length(ASpec.Targets);
  SetLength(ASpec.Targets, n + 1);
  ASpec.Targets[n].Dim := ADim;
  ASpec.Targets[n].AxisIndex := AIndex;
end;

{ getReferringComponents(dim + 'Axis', MULTIPLE): False when neither the
  index nor the id is written. 'all' is every axis, 'none' and false none,
  a number or a list those that exist; an id the axes carrying it. }
{ A POLAR'S AXIS IS NOT IN THE BUILD: it is a component the option holds
  [Batch 113] -- the model getReferringComponents finds }
function AxisExists(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const AMain: string; AIndex: Integer): Boolean;
begin
  if (AMain = 'radiusAxis') or (AMain = 'angleAxis') then
    Result := (AOption <> nil) and (AIndex >= 0)
      and (AIndex < AOption.ComponentCount(AMain))
      and (ObjOf(AOption.ComponentAt(AMain, AIndex)) <> nil)
  else
    Result := ABuild.Axis(AMain, AIndex) <> nil;
end;

function AxisCountOf(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const AMain: string): Integer;
begin
  if (AMain = 'radiusAxis') or (AMain = 'angleAxis') then
  begin
    if AOption = nil then Result := 0
    else Result := AOption.ComponentCount(AMain);
  end
  else
    Result := ABuild.AxisCount(AMain);
end;

function AxisIdOf(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const AMain: string; AIndex: Integer): string;
var
  ax: TTyAxis;
  o: TJSONObject;
  d: TJSONData;
begin
  Result := '';
  if (AMain = 'radiusAxis') or (AMain = 'angleAxis') then
  begin
    o := ObjOf(AOption.ComponentAt(AMain, AIndex));
    if o = nil then Exit;
    d := o.Find('id');
    if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then Result := d.AsString;
    Exit;
  end;
  ax := ABuild.Axis(AMain, AIndex);
  if ax <> nil then Result := ax.Id;
end;

function Specified(AOption: TTyChartOption; ANode: TJSONObject; ABuild: TTyChartBuild;
  const ADim: string; var ASpec: TTyDataZoomSpec): Boolean;
var
  d, e: TJSONData;
  main: string;
  k, n: Integer;

  procedure ByIndex(A: TJSONData);
  var ix: Integer;
  begin
    if (A = nil) or (A.JSONType <> jtNumber) then Exit;
    if Frac(A.AsFloat) <> 0 then Exit;
    ix := Trunc(A.AsFloat);
    if (ix >= 0) and AxisExists(AOption, ABuild, main, ix) then AddTarget(ASpec, ADim, ix);
  end;

  procedure ById(A: TJSONData);
  var
    k2: Integer;
    id: string;
  begin
    if (A = nil) or not (A.JSONType in [jtString, jtNumber]) then Exit;
    for k2 := 0 to n - 1 do
    begin
      if not AxisExists(AOption, ABuild, main, k2) then Continue;
      id := AxisIdOf(AOption, ABuild, main, k2);
      if (id <> '') and (id = A.AsString) then
        AddTarget(ASpec, ADim, k2);
    end;
  end;

begin
  main := ADim + 'Axis';
  d := ANode.Find(ADim + 'AxisIndex');
  e := ANode.Find(ADim + 'AxisId');
  if ((d = nil) or (d.JSONType = jtNull)) and ((e = nil) or (e.JSONType = jtNull)) then
    Exit(False);
  Result := True;
  n := AxisCountOf(AOption, ABuild, main);
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if (d.JSONType = jtString) and (d.AsString = 'all') then
    begin
      for k := 0 to n - 1 do
        if AxisExists(AOption, ABuild, main, k) then AddTarget(ASpec, ADim, k);
      Exit;
    end;
    if ((d.JSONType = jtString) and (d.AsString = 'none'))
      or ((d.JSONType = jtBoolean) and not d.AsBoolean) then Exit;
    if d.JSONType = jtArray then
      for k := 0 to TJSONArray(d).Count - 1 do ByIndex(TJSONArray(d).Items[k])
    else
      ByIndex(d);
    Exit;
  end;
  if e.JSONType = jtArray then
    for k := 0 to TJSONArray(e).Count - 1 do ById(TJSONArray(e).Items[k])
  else
    ById(e);
end;

{ _fillAutoTargetAxisByOrient for x / y: the first axis of that dim and
  every other axis of it in the same grid; failing that, the first category
  axis -- of x, y, then the polar's radius and angle, by the type the option
  writes [Batch 113] }
procedure AutoTargets(AOption: TTyChartOption; ABuild: TTyChartBuild;
  var ASpec: TTyDataZoomSpec);
var
  dim, main: string;
  k, n, g: Integer;
  ax, first: TTyAxis;
  d2: Integer;
begin
  if ASpec.Orient = 'vertical' then dim := 'y' else dim := 'x';
  main := dim + 'Axis';
  n := ABuild.AxisCount(main);
  first := nil;
  g := -1;
  for k := 0 to n - 1 do
  begin
    ax := ABuild.Axis(main, k);
    if ax = nil then Continue;
    if first = nil then
    begin
      first := ax;
      g := ax.GridIndex;
      AddTarget(ASpec, dim, k);
    end
    else if ax.GridIndex = g then
      AddTarget(ASpec, dim, k);
  end;
  if first <> nil then Exit;
  for d2 := 0 to 1 do
  begin
    if d2 = 0 then dim := 'x' else dim := 'y';
    main := dim + 'Axis';
    for k := 0 to ABuild.AxisCount(main) - 1 do
    begin
      ax := ABuild.Axis(main, k);
      if (ax <> nil) and (ax.AxisType = atCategory) then
      begin
        AddTarget(ASpec, dim, k);
        Exit;
      end;
    end;
  end;
  if AOption = nil then Exit;
  for d2 := 0 to 1 do
  begin
    if d2 = 0 then dim := 'radius' else dim := 'angle';
    main := dim + 'Axis';
    for k := 0 to AOption.ComponentCount(main) - 1 do
      if (ObjOf(AOption.ComponentAt(main, k)) <> nil)
        and (ObjOf(AOption.ComponentAt(main, k)).Find('type') <> nil)
        and (ObjOf(AOption.ComponentAt(main, k)).Find('type').JSONType = jtString)
        and (ObjOf(AOption.ComponentAt(main, k)).Find('type').AsString = 'category') then
      begin
        AddTarget(ASpec, dim, k);
        Exit;
      end;
  end;
end;

function TyDataZoomSpecOf(AOption: TTyChartOption; AIndex: Integer;
  ABuild: TTyChartBuild): TTyDataZoomSpec;
const
  cPercentKey: array[0..1] of string = ('start', 'end');
  cValueKey: array[0..1] of string = ('startValue', 'endValue');
var
  node: TJSONObject;
  d, rm: TJSONData;
  k: Integer;
  anySpecified, hasP, hasV: Boolean;
  orientRaw: string;
begin
  Result := Default(TTyDataZoomSpec);
  Result.Index := AIndex;
  Result.NoTarget := True;
  Result.Orient := 'horizontal';
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('dataZoom', AIndex));
  if node = nil then Exit;
  { the subtype defaulter: no type is a slider }
  d := node.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    if (d.AsString = 'slider') or (d.AsString = 'inside') then Result.SubType := d.AsString
    else Result.SubType := '';
  end
  else
    Result.SubType := TyOptDefaultSubType('dataZoom', node);
  if Result.SubType = '' then Exit;

  { the settled option: only what was written; `null` is not written }
  for k := 0 to 1 do
  begin
    Result.Percent[k] := ArgOf(node.Find(cPercentKey[k]));
    Result.Value[k] := ArgOf(node.Find(cValueKey[k]));
  end;
  { _updateRangeUse }
  rm := node.Find('rangeMode');
  for k := 0 to 1 do
  begin
    Result.Mode[k] := dzmPercent;
    hasP := Result.Percent[k].Given;
    hasV := Result.Value[k].Given;
    if hasP and not hasV then Result.Mode[k] := dzmPercent
    else if hasV and not hasP then Result.Mode[k] := dzmValue
    else if (rm <> nil) and (rm.JSONType = jtArray) and (TJSONArray(rm).Count > k) then
    begin
      if (TJSONArray(rm).Items[k].JSONType = jtString)
        and (TJSONArray(rm).Items[k].AsString = 'value') then
        Result.Mode[k] := dzmValue
      else
        Result.Mode[k] := dzmPercent;
    end
    else if hasP then Result.Mode[k] := dzmPercent;
  end;

  d := node.Find('filterMode');
  Result.FilterMode := dzfFilter;
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    if d.AsString = 'weakFilter' then Result.FilterMode := dzfWeakFilter
    else if d.AsString = 'empty' then Result.FilterMode := dzfEmpty
    else if d.AsString = 'none' then Result.FilterMode := dzfNone;
  end;
  Result.MinSpan := ArgOf(node.Find('minSpan'));
  Result.MaxSpan := ArgOf(node.Find('maxSpan'));
  Result.MinValueSpan := ArgOf(node.Find('minValueSpan'));
  Result.MaxValueSpan := ArgOf(node.Find('maxValueSpan'));

  { _resetTarget }
  orientRaw := '';
  d := node.Find('orient');
  if (d <> nil) and (d.JSONType = jtString) then orientRaw := d.AsString;
  anySpecified := False;
  if ABuild <> nil then
  begin
    if Specified(AOption, node, ABuild, 'x', Result) then anySpecified := True;
    if Specified(AOption, node, ABuild, 'y', Result) then anySpecified := True;
    { the polar's two, in DATA_ZOOM_AXIS_DIMENSIONS' order [Batch 113] }
    if Specified(AOption, node, ABuild, 'radius', Result) then anySpecified := True;
    if Specified(AOption, node, ABuild, 'angle', Result) then anySpecified := True;
  end;
  { a single axis named is specified too -- and there are none of those
    here }
  d := node.Find('singleAxisIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then anySpecified := True;
  if anySpecified then
  begin
    if orientRaw <> '' then Result.Orient := orientRaw
    else if (Length(Result.Targets) > 0) and (Result.Targets[0].Dim = 'y') then
      Result.Orient := 'vertical'
    else
      Result.Orient := 'horizontal';
  end
  else
  begin
    if orientRaw <> '' then Result.Orient := orientRaw else Result.Orient := 'horizontal';
    if ABuild <> nil then AutoTargets(AOption, ABuild, Result);
  end;
  Result.NoTarget := Length(Result.Targets) = 0;
end;

function TyDataZoomSelectSpecs(AOption: TTyChartOption; ABuild: TTyChartBuild;
  AFirstIndex: Integer): TTyDataZoomSpecArray;
var
  tb, feat, dz: TJSONObject;
  d, e: TJSONData;
  d2: Integer;
  dim, main: string;
  mode: TTyDzFilterMode;
  probe: TTyDataZoomSpec;
  k, n: Integer;
begin
  Result := nil;
  if (AOption = nil) or (ABuild = nil) then Exit;
  tb := ObjOf(AOption.ComponentAt('toolbox', 0));
  if tb = nil then Exit;
  feat := ObjOf(tb.Find('feature'));
  if feat = nil then Exit;
  { `get(['feature', 'dataZoom']) == null`: absent or null makes none }
  d := feat.Find('dataZoom');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  dz := ObjOf(d);
  mode := dzfFilter;
  if dz <> nil then
  begin
    e := dz.Find('filterMode');
    if (e <> nil) and (e.JSONType = jtString) then
    begin
      if e.AsString = 'weakFilter' then mode := dzfWeakFilter
      else if e.AsString = 'empty' then mode := dzfEmpty
      else if e.AsString = 'none' then mode := dzfNone;
    end;
  end;
  for d2 := 0 to 1 do
  begin
    if d2 = 0 then dim := 'x' else dim := 'y';
    main := dim + 'Axis';
    { makeAxisFinder: neither index nor id written is 'all' }
    probe := Default(TTyDataZoomSpec);
    if (dz = nil) or not Specified(AOption, dz, ABuild, dim, probe) then
      for k := 0 to ABuild.AxisCount(main) - 1 do
        if ABuild.Axis(main, k) <> nil then AddTarget(probe, dim, k);
    for k := 0 to High(probe.Targets) do
    begin
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := Default(TTyDataZoomSpec);
      Result[n].Index := AFirstIndex + n;
      Result[n].SubType := 'select';
      Result[n].Orient := 'horizontal';
      if dim = 'y' then Result[n].Orient := 'vertical';
      Result[n].FilterMode := mode;
      Result[n].Percent[0].Num := NaN;
      Result[n].Percent[1].Num := NaN;
      Result[n].Value[0].Num := NaN;
      Result[n].Value[1].Num := NaN;
      Result[n].MinSpan.Num := NaN;
      Result[n].MaxSpan.Num := NaN;
      Result[n].MinValueSpan.Num := NaN;
      Result[n].MaxValueSpan.Num := NaN;
      SetLength(Result[n].Targets, 1);
      Result[n].Targets[0] := probe.Targets[k];
      Result[n].NoTarget := False;
    end;
  end;
end;

function TyDzTargets(const ASpec: TTyDataZoomSpec; const ADim: string;
  AAxisIndex: Integer): Boolean;
var k: Integer;
begin
  for k := 0 to High(ASpec.Targets) do
    if (ASpec.Targets[k].Dim = ADim) and (ASpec.Targets[k].AxisIndex = AAxisIndex) then
      Exit(True);
  Result := False;
end;

{ ---- the window ---- }

function TyDzParse(AAxis: TTyAxis; const AArg: TTyDzArg): Double;
var ms: Double;
begin
  Result := NaN;
  if not AArg.Given then Exit;
  if AAxis = nil then Exit(AArg.Num);
  case AAxis.AxisType of
    atCategory:
      { OrdinalScale.parse: a name is its ordinal, a number rounded }
      if AArg.IsStr then
      begin
        if AAxis.Categories <> nil then
        begin
          Result := AAxis.Categories.GetOrdinal(AArg.Str);
          if Result < 0 then Result := NaN;
        end;
      end
      else
        Result := TyJsRound(AArg.Num);
    atTime:
      if AArg.IsStr then
      begin
        if TyParseDateMs(AArg.Str, ms, False) then Result := ms else Result := NaN;
      end
      else
        Result := AArg.Num;
  else
    Result := AArg.Num;
  end;
end;

function TyDzSpansOf(const ASpec: TTyDataZoomSpec; AAxis: TTyAxis;
  ALo, AHi: Double): TTyDzSpans;
var
  v, p: Double;
  k: Integer;
  pArg, vArg: TTyDzArg;
begin
  Result.MinSpan := NaN;
  Result.MaxSpan := NaN;
  Result.MinValueSpan := NaN;
  Result.MaxValueSpan := NaN;
  for k := 0 to 1 do
  begin
    if k = 0 then
    begin
      pArg := ASpec.MinSpan;
      vArg := ASpec.MinValueSpan;
    end
    else
    begin
      pArg := ASpec.MaxSpan;
      vArg := ASpec.MaxValueSpan;
    end;
    p := NaN;
    v := NaN;
    if vArg.Given then
    begin
      v := TyDzParse(AAxis, vArg);
      p := TyDzLinearMap(ALo + v, ALo, AHi, 0, 100, True);
    end
    else if pArg.Given then
    begin
      p := pArg.Num;
      v := TyDzLinearMap(p, 0, 100, ALo, AHi, True) - ALo;
    end;
    if k = 0 then
    begin
      Result.MinSpan := p;
      Result.MinValueSpan := v;
    end
    else
    begin
      Result.MaxSpan := p;
      Result.MaxValueSpan := v;
    end;
  end;
end;

function TyDzCalculateWindow(const ASpec: TTyDataZoomSpec; AAxis: TTyAxis;
  ALo, AHi, APxSpan: Double): TTyDzWindow;
var
  idx: Integer;
  bp, bv: Double;
  needRound: array[0..1] of Boolean;
  hasValueMode, ordOrTime: Boolean;
  ext: array[0..1] of Double;
  spans: TTyDzSpans;
  prec: Double;
begin
  Result := Default(TTyDzWindow);
  ext[0] := ALo;
  ext[1] := AHi;
  needRound[0] := False;
  needRound[1] := False;
  hasValueMode := False;
  for idx := 0 to 1 do
  begin
    if ASpec.Mode[idx] = dzmPercent then
    begin
      if ASpec.Percent[idx].Given then bp := ASpec.Percent[idx].Num
      else bp := idx * 100;
      bv := TyDzLinearMap(bp, 0, 100, ALo, AHi, False);
      needRound[idx] := True;
    end
    else
    begin
      hasValueMode := True;
      if not ASpec.Value[idx].Given then
        bv := ext[idx]
      else
      begin
        bv := TyDzParse(AAxis, ASpec.Value[idx]);
        { LogScale.sanitize: at or under zero is the extent's start }
        if (AAxis <> nil) and (AAxis.AxisType = atLog)
          and (not IsNan(ALo)) and (not IsNan(AHi)) and (ALo <= AHi)
          and (not IsNan(bv)) and (not IsInfinite(bv)) and (bv <= 0) then
          bv := ALo;
      end;
      bp := TyDzLinearMap(bv, ALo, AHi, 0, 100, False);
    end;
    if IsNan(bv) then Result.Value[idx] := ext[idx] else Result.Value[idx] := bv;
    if IsNan(bp) then Result.Percent[idx] := idx * 100 else Result.Percent[idx] := bp;
  end;
  Asc(Result.Value);
  Asc(Result.Percent);

  spans := TyDzSpansOf(ASpec, AAxis, ALo, AHi);
  if hasValueMode then
  begin
    TyDzSliderMove(0, Result.Value, ALo, AHi, -1, spans.MinValueSpan, spans.MaxValueSpan);
    for idx := 0 to 1 do
      Result.Percent[idx] := TyDzLinearMap(Result.Value[idx], ALo, AHi, 0, 100, True);
  end
  else
  begin
    TyDzSliderMove(0, Result.Percent, 0, 100, -1, spans.MinSpan, spans.MaxSpan);
    for idx := 0 to 1 do
    begin
      Result.Value[idx] := TyDzLinearMap(Result.Percent[idx], 0, 100, ALo, AHi, True);
      needRound[idx] := True;
    end;
  end;

  ordOrTime := (AAxis <> nil) and ((AAxis.AxisType = atCategory) or (AAxis.AxisType = atTime));
  if ordOrTime then prec := 0
  else prec := TyAcceptableTickPrecision(Result.Value[0], Result.Value[1], APxSpan, 0.5);
  Result.Precision := prec;
  for idx := 0 to 1 do
  begin
    if (not needRound[idx]) or IsNan(prec) or IsInfinite(prec) then Continue;
    Result.Value[idx] := TyDzRound(Result.Value[idx], prec);
    Result.Value[idx] := JsMin(AHi, JsMax(ALo, Result.Value[idx]));
    { exactly 0% or 100%: the extent's own end, whatever the rounding }
    if (not IsNan(Result.Percent[idx])) and (Result.Percent[idx] = idx * 100) then
    begin
      Result.Value[idx] := ext[idx];
      { Math.ceil of not-a-number is not-a-number; FPC's raises }
      if ordOrTime and not IsNan(Result.Value[idx]) and not IsInfinite(Result.Value[idx]) then
      begin
        { Int64: a time is milliseconds, past what an Integer holds }
        if idx = 0 then Result.Value[idx] := Ceil64(Result.Value[idx])
        else Result.Value[idx] := Floor64(Result.Value[idx]);
      end;
    end;
  end;
  for idx := 0 to 1 do
    Result.PercentInverted[idx] := TyDzLinearMap(Result.Value[idx], ALo, AHi, 0, 100, True);
end;

end.
