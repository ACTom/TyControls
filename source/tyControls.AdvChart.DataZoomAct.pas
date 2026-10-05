unit tyControls.AdvChart.DataZoomAct;
{$mode objfpc}{$H+}
{ dataZoom interaction, the arithmetic: a slider's handle ends moved by a
  pointer delta (_updateInterval), the inside dataZoom's wheel zoom about the
  pointer and its drag pan (InsideZoomView over RoamController), the wheel's
  factor, and the 'fixRate' throttle both dispatch paths go through.
  [Batch 62.]

  THE ENDS ARE PIXELS, the range percents. A slider keeps its own ends after
  its own action -- descending after a cross -- and its range is them mapped
  back and sorted; an inside keeps only a range.

  PURE: numbers in, numbers out. The chart owns the pointer, the targets and
  the clock. }
interface
uses SysUtils, Math, fpjson, tyControls.AdvChart.Types,
     tyControls.AdvChart.Option;

type
  { util/throttle 'fixRate': LastExec starts at nought, so the first call
    runs; a call inside the rate arms one deferred run at LastExec + rate,
    which runs with the latest arguments. }
  TTyDzThrottle = record
    LastExec: Double;
    Armed: Boolean;
    Due: Double;
  end;

  { getDirectionInfo.grid }
  TTyDzDirection = record
    Pixel, PixelLength, PixelStart, Signal: Double;
  end;

  { One dataZoom action item: the dataZoom it names and the percent window
    setRawRange writes on it (and on every dataZoom linked to it through a
    shared axis). }
  TTyDzActionItem = record
    DataZoomIndex: Integer;
    Start, Stop: Double;
  end;
  TTyDzActionItemArray = array of TTyDzActionItem;

  { A dispatched `dataZoom` action. Batch: from an inside's roam (one item
    per inside that moved); otherwise one item, and FromSlider the slider
    that dispatched it (-1: the API). Deferred: run by the throttle's timer
    rather than by the gesture itself. }
  TTyDzAction = record
    Batch: Boolean;
    Deferred: Boolean;
    FromSlider: Integer;
    { a slider's dispatch during a realtime drag: its payload carries
      REALTIME_ANIMATION_CONFIG [Batch 96] }
    Realtime: Boolean;
    Items: TTyDzActionItemArray;
  end;

  { What a dataZoom's option says about how it answers the pointer. A
    behaviour is '' (off), '*' (on) or the modifier it waits for ('shift',
    'ctrl', 'alt', 'meta'). }
  TTyDzInteractSpec = record
    Realtime, ZoomLock, Disabled: Boolean;
    ZoomOnMouseWheel, MoveOnMouseMove, MoveOnMouseWheel: string;
    PreventDefaultMouseMove: Boolean;
    { ms; the option's own, else 100 with animation on, 20 without }
    Throttle: Double;
    { emphasis.handleLabel.show }
    EmphasisLabelShow: Boolean;
  end;

  { A slider view's own state, kept across renders its own actions cause
    and reset by any other (_buildView). Ends in slider pixels, Range in
    percents, sorted. }
  TTyDzSliderState = record
    { the ends were taken from the window at least once }
    Built: Boolean;
    Ends, Range: array[0..1] of Double;
    Dragging, OverArea, Brushing: Boolean;
    LabelsShown: Boolean;
    { _updateView(nonRealtime): labels from the view range, not the window }
    NonRealtime: Boolean;
    HandleHover: array[0..1] of Boolean;
    { the move handle's __highByOuter bits: 1 the move zone, 2 the labels }
    MoveBits: Integer;
    BrushStartX, BrushStartY, BrushStartTime: Double;
    { the brush rect: made on the first brush move and never dropped by a
      new brush (only a rebuild does); Ignored after a brush ends }
    HasBrush, BrushIgnored: Boolean;
    BrushX, BrushW: Double;
    Throttle: TTyDzThrottle;
    PendingRealtime: Boolean;
  end;

{ A call at ANow: True when it runs now (LastExec moves); False when it is
  deferred (Armed, Due). Either way an earlier deferred run is dropped. }
function TyDzThrottleCall(var T: TTyDzThrottle; ANow, ARate: Double): Boolean;
{ The timer at ANow: True when the deferred run is due -- it runs, LastExec
  becomes the moment it was due (the timer's own) and the timer is spent. }
function TyDzThrottleFire(var T: TTyDzThrottle; ANow: Double): Boolean;

{ _updateInterval: AEnds (px, [0, ALength]) moved by ADelta through
  sliderMove -- AHandle 0 or 1, or -1 for 'all' -- with the host's minSpan /
  maxSpan in percent (NaN: none) turned into pixels. ARange (percent, sorted)
  is replaced; answers whether it changed. AHadRange False: no range yet
  (the first one always counts as a change). }
function TyDzUpdateInterval(var AEnds: array of Double; ALength, ADelta: Double;
  AHandle: Integer; AMinSpan, AMaxSpan: Double; var ARange: array of Double;
  AHadRange: Boolean): Boolean;
{ the ends mapped to percents and sorted }
procedure TyDzRangeOfEnds(const AEnds: array of Double; ALength: Double;
  out ARange0, ARange1: Double);

{ RoamController's wheel: zrDelta (a notch is 1) to the zoom's scale --
  1.1, 1.2 or 1.4 by |delta|, its reciprocal downwards -- and to the
  scrollMove's step, 0 for no delta. }
function TyDzWheelScale(AZrDelta: Double): Double;
function TyDzScrollDelta(AZrDelta: Double): Double;
{ LCL's WheelDelta (120 a notch) as zrender normalises a raw wheelDelta }
function TyDzZrDelta(AWheelDelta: Integer): Double;

function TyDzDirectionInfo(AIsX, AInverse: Boolean; const ARect: TTyXYWH;
  AOldX, AOldY, ANewX, ANewY: Double): TTyDzDirection;
{ InsideZoomView.zoom: the range scaled by 1 / AScale about the point the
  pointer names, then sliderMove(0, range, [0, 100], 0, min, max). Answers
  whether the range changed. }
function TyDzInsideZoom(var ARange: array of Double; const ADir: TTyDzDirection;
  AScale, AMinSpan, AMaxSpan: Double): Boolean;
{ makeMover: sliderMove(ADelta, range, [0, 100], 'all') }
function TyDzInsideMove(var ARange: array of Double; ADelta: Double): Boolean;
{ The interaction options of dataZoom AIndex. The default throttle is 100
  ms when the option's `animation` is truthy and `animationDurationUpdate`
  above nought, else 20. }
function TyDzInteractSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyDzInteractSpec;
{ isAvailableBehavior }
function TyDzBehaviour(const ASetting: string; AShift, ACtrl, AAlt,
  AMeta: Boolean): Boolean;

{ the pan's and the scroll's percent deltas }
function TyDzPanDelta(const ARange: array of Double; const ADir: TTyDzDirection): Double;
function TyDzScrollMoveDelta(const ARange: array of Double; const ADir: TTyDzDirection;
  AScrollDelta: Double): Double;

implementation

uses tyControls.AdvChart.DataZoom;

function ObjOf(A: TJSONData): TJSONObject;
begin
  if (A <> nil) and (A.JSONType = jtObject) then Result := TJSONObject(A)
  else Result := nil;
end;

function TruthyOf(A: TJSONData): Boolean;
begin
  if A = nil then Exit(False);
  case A.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

{ a behaviour setting: absent or null the default, a string itself, any
  other value by its truth }
function BehaviourOf(A: TJSONData; const ADefault: string): string;
begin
  if (A = nil) or (A.JSONType = jtNull) then Exit(ADefault);
  if A.JSONType = jtString then
  begin
    if A.AsString = '' then Exit('');
    Exit(A.AsString);
  end;
  if TruthyOf(A) then Result := '*' else Result := '';
end;

function TyDzInteractSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyDzInteractSpec;
var
  node, root, o: TJSONObject;
  d: TJSONData;
  animOn: Boolean;
begin
  Result := Default(TTyDzInteractSpec);
  Result.Realtime := True;
  Result.ZoomOnMouseWheel := '*';
  Result.MoveOnMouseMove := '*';
  Result.MoveOnMouseWheel := '';
  Result.PreventDefaultMouseMove := True;
  Result.EmphasisLabelShow := True;
  Result.Throttle := 100;
  if AOption = nil then Exit;
  { _setDefaultThrottle: animation 'auto' (truthy) and the update duration
    (500) above nought }
  animOn := True;
  root := ObjOf(AOption.Root);
  if root <> nil then
  begin
    d := root.Find('animation');
    if d <> nil then animOn := TruthyOf(d);
    d := root.Find('animationDurationUpdate');
    if (d <> nil) and (d.JSONType = jtNumber) and not (d.AsFloat > 0) then animOn := False;
  end;
  if animOn then Result.Throttle := 100 else Result.Throttle := 20;
  node := ObjOf(AOption.ComponentAt('dataZoom', AIndex));
  if node = nil then Exit;
  d := node.Find('throttle');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Throttle := d.AsFloat;
  d := node.Find('realtime');
  if (d <> nil) and (d.JSONType <> jtNull) then Result.Realtime := TruthyOf(d);
  Result.ZoomLock := TruthyOf(node.Find('zoomLock'));
  Result.Disabled := TruthyOf(node.Find('disabled'));
  Result.ZoomOnMouseWheel := BehaviourOf(node.Find('zoomOnMouseWheel'), '*');
  Result.MoveOnMouseMove := BehaviourOf(node.Find('moveOnMouseMove'), '*');
  Result.MoveOnMouseWheel := BehaviourOf(node.Find('moveOnMouseWheel'), '');
  d := node.Find('preventDefaultMouseMove');
  if (d <> nil) and (d.JSONType <> jtNull) then
    Result.PreventDefaultMouseMove := TruthyOf(d);
  o := ObjOf(node.Find('emphasis'));
  if o <> nil then
  begin
    o := ObjOf(o.Find('handleLabel'));
    if (o <> nil) and (o.Find('show') <> nil) and (o.Find('show').JSONType <> jtNull) then
      Result.EmphasisLabelShow := TruthyOf(o.Find('show'));
  end;
end;

function TyDzBehaviour(const ASetting: string; AShift, ACtrl, AAlt,
  AMeta: Boolean): Boolean;
begin
  if ASetting = '' then Exit(False);
  if ASetting = '*' then Exit(True);
  if ASetting = 'shift' then Exit(AShift);
  if ASetting = 'ctrl' then Exit(ACtrl);
  if ASetting = 'alt' then Exit(AAlt);
  if ASetting = 'meta' then Exit(AMeta);
  { e.event[setting + 'Key'] on any other word: undefined }
  Result := False;
end;

function TyDzThrottleCall(var T: TTyDzThrottle; ANow, ARate: Double): Boolean;
var diff: Double;
begin
  diff := ANow - T.LastExec - ARate;
  T.Armed := False;
  if diff >= 0 then
  begin
    T.LastExec := ANow;
    Exit(True);
  end;
  T.Armed := True;
  T.Due := ANow + -diff;
  Result := False;
end;

function TyDzThrottleFire(var T: TTyDzThrottle; ANow: Double): Boolean;
begin
  Result := T.Armed and (ANow >= T.Due);
  if Result then
  begin
    T.Armed := False;
    T.LastExec := T.Due;
  end;
end;

procedure TyDzRangeOfEnds(const AEnds: array of Double; ALength: Double;
  out ARange0, ARange1: Double);
var a, b: Double;
begin
  a := TyDzLinearMap(AEnds[0], 0, ALength, 0, 100, True);
  b := TyDzLinearMap(AEnds[1], 0, ALength, 0, 100, True);
  { asc: swapped only when b - a is below nought }
  if (not IsNan(a)) and (not IsNan(b)) and (b - a < 0) then
  begin
    ARange0 := b;
    ARange1 := a;
  end
  else
  begin
    ARange0 := a;
    ARange1 := b;
  end;
end;

function TyDzUpdateInterval(var AEnds: array of Double; ALength, ADelta: Double;
  AHandle: Integer; AMinSpan, AMaxSpan: Double; var ARange: array of Double;
  AHadRange: Boolean): Boolean;
var minPx, maxPx, r0, r1: Double;
begin
  minPx := NaN;
  maxPx := NaN;
  if not IsNan(AMinSpan) then minPx := TyDzLinearMap(AMinSpan, 0, 100, 0, ALength, True);
  if not IsNan(AMaxSpan) then maxPx := TyDzLinearMap(AMaxSpan, 0, 100, 0, ALength, True);
  TyDzSliderMove(ADelta, AEnds, 0, ALength, AHandle, minPx, maxPx);
  TyDzRangeOfEnds(AEnds, ALength, r0, r1);
  Result := (not AHadRange) or (ARange[0] <> r0) or (ARange[1] <> r1);
  ARange[0] := r0;
  ARange[1] := r1;
end;

function TyDzWheelScale(AZrDelta: Double): Double;
var f, a: Double;
begin
  if (AZrDelta = 0) or IsNan(AZrDelta) then Exit(0);
  a := Abs(AZrDelta);
  if a > 3 then f := 1.4
  else if a > 1 then f := 1.2
  else f := 1.1;
  if AZrDelta > 0 then Result := f else Result := 1 / f;
end;

function TyDzScrollDelta(AZrDelta: Double): Double;
var s, a: Double;
begin
  if (AZrDelta = 0) or IsNan(AZrDelta) then Exit(0);
  a := Abs(AZrDelta);
  if a > 3 then s := 0.4
  else if a > 1 then s := 0.15
  else s := 0.05;
  if AZrDelta > 0 then Result := s else Result := -s;
end;

function TyDzZrDelta(AWheelDelta: Integer): Double;
begin
  Result := AWheelDelta / 120;
end;

function TyDzDirectionInfo(AIsX, AInverse: Boolean; const ARect: TTyXYWH;
  AOldX, AOldY, ANewX, ANewY: Double): TTyDzDirection;
begin
  if AIsX then
  begin
    Result.Pixel := ANewX - AOldX;
    Result.PixelLength := ARect.W;
    Result.PixelStart := ARect.X;
    if AInverse then Result.Signal := 1 else Result.Signal := -1;
  end
  else
  begin
    Result.Pixel := ANewY - AOldY;
    Result.PixelLength := ARect.H;
    Result.PixelStart := ARect.Y;
    if AInverse then Result.Signal := -1 else Result.Signal := 1;
  end;
end;

function TyDzInsideZoom(var ARange: array of Double; const ADir: TTyDzDirection;
  AScale, AMinSpan, AMaxSpan: Double): Boolean;
var
  r: array[0..1] of Double;
  pp, s: Double;
begin
  r[0] := ARange[0];
  r[1] := ARange[1];
  if ADir.Signal > 0 then
    pp := (ADir.PixelStart + ADir.PixelLength - ADir.Pixel) / ADir.PixelLength
      * (r[1] - r[0]) + r[0]
  else
    pp := (ADir.Pixel - ADir.PixelStart) / ADir.PixelLength * (r[1] - r[0]) + r[0];
  s := 1 / AScale;
  if not (s > 0) then s := 0;
  r[0] := (r[0] - pp) * s + pp;
  r[1] := (r[1] - pp) * s + pp;
  TyDzSliderMove(0, r, 0, 100, 0, AMinSpan, AMaxSpan);
  Result := (r[0] <> ARange[0]) or (r[1] <> ARange[1]);
  ARange[0] := r[0];
  ARange[1] := r[1];
end;

function TyDzInsideMove(var ARange: array of Double; ADelta: Double): Boolean;
var r: array[0..1] of Double;
begin
  r[0] := ARange[0];
  r[1] := ARange[1];
  TyDzSliderMove(ADelta, r, 0, 100, -1, NaN, NaN);
  Result := (r[0] <> ARange[0]) or (r[1] <> ARange[1]);
  ARange[0] := r[0];
  ARange[1] := r[1];
end;

function TyDzPanDelta(const ARange: array of Double; const ADir: TTyDzDirection): Double;
begin
  Result := ADir.Signal * (ARange[1] - ARange[0]) * ADir.Pixel / ADir.PixelLength;
end;

function TyDzScrollMoveDelta(const ARange: array of Double; const ADir: TTyDzDirection;
  AScrollDelta: Double): Double;
begin
  Result := ADir.Signal * (ARange[1] - ARange[0]) * AScrollDelta;
end;

end.
