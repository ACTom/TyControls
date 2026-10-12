unit tyControls.AdvChart.Parallel;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the parallel coordinate system, its axes and the rows of
  a parallel series. [Batch 128, C19]

  UPSTREAM'S coord/parallel (Parallel.ts, ParallelModel.ts, AxisModel.ts,
  parallelCreator.ts), component/axis/ParallelAxisView.ts and the geometry of
  chart/parallel/ParallelView.ts and parallelVisual.ts, transcribed.

  ONE COORDINATE SYSTEM PER parallel COMPONENT, its axes the parallelAxis
  components whose `parallelIndex || 0` is its index, IN COMPONENT ORDER --
  not in `dim` order. Axis k stands for dimension 'dim' + its `dim`, and a
  series' row element N feeds the axis of 'dimN' (makeDefaultEncode).

  THE BOX is the component's own (left 80, top 60, right 80, bottom 60 by
  default; mergeLayoutParam, then getLayoutRect on the chart). The axes stand
  across it, evenly spaced along it: a horizontal layout puts them upright,
  step * index from the left, each in a frame turned a quarter (rotation
  pi / 2, the transform rotate-then-translate of matrix.ts -- cos(pi / 2) is
  6e-17 and it stays in the numbers); a vertical layout puts them flat, one
  under another. Every axis' extent is [0, length across], swapped when the
  axis model says inverse; the TTyAxis' own Inverse is never set (the swap is
  in the extent, as upstream's) and the flag lives here, toggled again when a
  backwards min and max invert the axis after the extents were set.

  axisExpandable's static arithmetic (_makeLayoutInfo, layoutAxisWithExpand)
  is here too: the collapsed axes, their hidden labels and their cut names.
  [Batch 140, D7] And the interaction: _makeLayoutInfo rewrites the option's
  axisExpandWindow ([1] = [0] + the restricted size) every time it runs --
  the action's payload array is the option's, so its event shows it --, and
  getSlidedAxisExpandWindow says where a click or a move takes the window
  (TyParallelSlide).

  THE AXES ARE AxisBuilder AXES, the polar radius' way: a spec from
  TyFillAxisLayoutSpec in a frame of its own (FreeFrame), ticks and labels on
  the +1 side, the labels' own `show` overruled by the coordinate system
  (axisLabelShow), the name cut to the room between two axes
  (axisNameAvailableWidth over the sine of its turn).

  A ROW is a polyline through every axis whose value is not empty (a category
  value is empty when it is null, any other when it is null or not a number --
  an unknown category is not-a-number and keeps its point); smooth turns it
  into zrender's smoothBezier curve. Its active state is the axes' active
  intervals: none anywhere is 'normal', else 'inactive' as soon as one axis
  rejects the value.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Builder,
  tyControls.AdvChart.Convert, tyControls.AdvChart.Data,
  tyControls.AdvChart.Series, tyControls.AdvChart.Polar;

const
  TyParallelCoordSysName = 'parallel';
  TyParallelSeriesTypeName = 'parallel';
  TyParallelDimPrefix = 'dim';
  { ParallelView's DEFAULT_SMOOTH, what `smooth: true` means }
  TyParallelDefaultSmooth = 0.3;
  { the polyline's z2 (ParallelView.addEl) }
  TyParallelLineZ2 = 10;
  { a parallelAxis' z (component/parallel/install.ts defaultAxisOption) }
  TyParallelAxisZ = 10;

type
  { 'normal' -- no axis has an active interval; else 'active' or 'inactive' }
  TTyParallelActive = (ppaNormal, ppaActive, ppaInactive);
  TTyParallelInterval = array[0..1] of Double;
  TTyParallelIntervalArray = array of TTyParallelInterval;

  { ParallelAxisLayoutInfo: where an axis stands and how it is turned, the
    room its name has, whether its labels show; NameTruncMax only for a
    collapsed axis of an expandable layout (not a number otherwise) }
  TTyParallelAxisLayout = record
    PosX, PosY, Rotation: Double;
    M: TTyMat2D;
    NameAvailableWidth: Double;
    LabelShow: Boolean;
    NameTruncMax: Double;
  end;

  { WHAT ONE AXIS' AxisBuilder DRAWS: its line, its ticks and minor ticks;
    the labels, the name and the arrows are in Spec, as a grid axis' are }
  TTyParallelAxisView = record
    Shown: Boolean;
    Blank: Boolean;
    Furn: TTyAxisFurniture;
    Spec: TTyAxisLayoutSpec;
    HasLine: Boolean;
    Line: TTyPolarLine;
    Ticks, MinorTicks: TTyPolarLineArray;
  end;

  { One parallel component. Owns its axes. }
  TTyParallel = class
  private
    FIndex: Integer;
    FId, FName: string;
    FHorizontal: Boolean;
    FRect: TTyXYWH;
    FAxes: array of TTyAxis;
  public
    { 'dimN' per axis, in axis order, and the N }
    Dims: TTyStringArray;
    DimNums: TTyIntegerArray;
    { each axis' parallelAxis component index }
    AxisIndices: TTyIntegerArray;
    { upstream's axis.inverse of each -- see the unit header }
    AxisInverse: array of Boolean;
    Layouts: array of TTyParallelAxisLayout;
    Views: array of TTyParallelAxisView;
    { each axis' activeIntervals, ascending pairs }
    Intervals: array of TTyParallelIntervalArray;
    { _makeLayoutInfo's answers }
    LayoutBase, LayoutLength, AxisBase, AxisLength: Double;
    Expandable: Boolean;
    ExpandWidth, CollapseWidth, ExpandWindow0, ExpandWindow1,
      ExpandWindow0Pos: Double;
    WinInner0, WinInner1: Double;
    { [Batch 140] what ParallelView reads off the model: axisExpandable as
      written (checkTrigger asks the option, not the layout), the trigger
      ('click' by default), axisExpandSlideTriggerArea (a null first entry:
      no jump; a null other one reads as nought), axisExpandRate (NaN: null,
      no throttle) and axisExpandDebounce }
    ExpandOpt: Boolean;
    TriggerClick, TriggerMove: Boolean;
    SlideArea: array[0..2] of Double;
    SlideJump: Boolean;
    ExpandRate, ExpandDebounce: Double;
    constructor Create(AIndex: Integer);
    destructor Destroy; override;
    function AxisCount: Integer;
    function Axis(AI: Integer): TTyAxis;
    { the axis of 'dimN', -1 when none }
    function AxisOfDim(const ADim: string): Integer;
    { the axis of parallelAxis component AComponent, -1 when none }
    function AxisOfComponent(AComponent: Integer): Integer;
    { axisCoordToPoint: [coord, 0] through the axis' transform }
    function AxisCoordToPoint(ACoord: Double; AI: Integer): TTyPointF;
    { dataToPoint of one value on axis AI }
    function DataToPoint(AValue: Double; AI: Integer): TTyPointF;
    { containPoint: across the axes and along the layout, both ends in }
    function ContainXY(AX, AY: Double): Boolean;
    { hasAxisBrushed: some axis has an active interval }
    function HasAxisBrushed: Boolean;
    { AxisModel.getActiveState of a value on axis AI (AHas False: null) }
    function AxisActiveState(AI: Integer; AValue: Double; AHas: Boolean): TTyParallelActive;
    property Index: Integer read FIndex;
    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property Horizontal: Boolean read FHorizontal;
    property Rect: TTyXYWH read FRect;
  end;
  TTyParallelArray = array of TTyParallel;

  { ONE ROW OF A PARALLEL SERIES as ParallelView draws it: its points, its
    curve (smooth), its look and its active state }
  TTyParallelRow = record
    Row: Integer;
    Raw: Integer;
    Pts: TTyPointFArray;
    Cmds: TTyPathCmdArray;
    Active: TTyParallelActive;
    Stroke: TTyChartColor;
    Width, Opacity: Double;
    Dash: TTyDoubleArray;
    { the dash as the style holds it: '' none, 'solid', 'dashed', 'dotted',
      or '[...]' for a list }
    DashWord: string;
  end;
  TTyParallelRowArray = array of TTyParallelRow;

  { ONE SERIES SOLVED: its parallel, its smooth, z and z2, its rows, and the
    enter clip's rect (the parallel's) }
  TTyParallelSolved = record
    Valid: Boolean;
    SeriesIndex: Integer;
    ParallelIndex: Integer;
    Smooth: Double;
    Z, Z2: Integer;
    Horizontal: Boolean;
    Clip: TTyXYWH;
    { the rows are tagged for the enter clip -- never an incremental view
      (incrementalPrepareRender sets _initialized) --, and the clip starts
      only on the view's first render (NewView) }
    EnterClip: Boolean;
    NewView: Boolean;
    Rows: TTyParallelRowArray;
  end;
  TTyParallelSolvedArray = array of TTyParallelSolved;

{ ---- building ---- }

{ parallelCreator.create: one parallel per parallel component (a hole is
  nil), its axes (in component order, every type -- a parallelAxis with no
  `type` is a VALUE axis even with `data`), its box on AViewport and the
  axes' places (resize / _layoutAxes). }
function TyBuildParallels(AOption: TTyChartOption;
  const AViewport: TTyRectF): TTyParallelArray;

{ The store's columns of a parallel series: one per row element up to the
  widest of the data and the highest 'dimN', 'dimN' (typed by its axis,
  interning into a category axis' list) where an axis stands, 'value',
  'value0', ... elsewhere. }
function TyParallelSeriesDims(APar: TTyParallel; ADataCount: Integer): TTySeriesDimArray;

{ Parallel.update: each axis' raw extent from the series on it and its nice
  step; a backwards min and max toggle its inverse flag. }
procedure TyParallelApplyExtents(AOption: TTyChartOption; const APars: TTyParallelArray;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex);

{ Every axis view of every parallel, as ParallelAxisView's AxisBuilder
  builds it. AMinorTickLenLogical is the theme's minor tick length where the
  option writes none. }
procedure TyLayoutParallels(const APars: TTyParallelArray; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorTickLenLogical: Double; AMemory: TTyAxisMemoryStore);

{ ---- the series ---- }

{ makeSeriesScope's smooth: true is 0.3, numericToNumber, not a number 0 }
function TyParallelSmoothOf(ASeries: TJSONObject): Double;
{ zrender's Polyline with smooth: moveTo the first point, a bezierCurveTo per
  segment from smoothBezier's control points (not a loop, no constraint) }
function TyParallelSmoothCmds(const APts: TTyPointFArray; ASmooth: Double): TTyPathCmdArray;
{ The curve sampled for the hit test, ASteps points a segment }
function TyParallelSampleCmds(const ACmds: TTyPathCmdArray; ASteps: Integer): TTyPointFArray;

{ ParallelView: one polyline per row (z2 10), its datum the row, hit within
  max(lineWidth, 5) / 2 of its stroke; a smooth one drawn by its curve and
  hit along the curve sampled; tagged for the enter clip }
function TyBuildParallelMarks(const ASolved: TTyParallelSolved; AList: TTyPaintList): Integer;

{ setActiveIntervals: each pair ascending }
function TyParallelIntervalsOf(AData: TJSONData): TTyParallelIntervalArray;

{ ---- the conversions ---- }

{ Parallel.containPoint of a JSON point }
function TyParallelContainJson(APar: TTyParallel; APoint: TJSONData): Boolean;

{ ---- the expansion [Batch 140] ---- }

type
  TTyParallelSlide = (pslNone, pslSlide, pslJump);

  { PARALLELVIEW BETWEEN POINTER EVENTS: the press a click is judged against
    (kept when a release lands too far from it -- the handler returns before
    it clears it) and the throttle createOrUpdate made of
    _throttledDispatchExpand (util/throttle.ts: fixRate at axisExpandRate,
    debounceNextCall on a jump; Gen tells a newer throttle's timers from an
    older one's) }
  TTyParallelExpandView = record
    HasDown: Boolean;
    DownX, DownY: Double;
    ThrActive: Boolean;
    ThrRate: Double;
    LastCall, LastExec: Double;
    { NaN: none }
    DebounceNext: Double;
    Gen: Integer;
    TimerId: Integer;
  end;

  { a throttle's pending call: the view, its throttle, when, and the payload
    it carries (none: the null call that only cancels) }
  TTyParallelExpandPending = record
    Id, Par, Gen: Integer;
    Due: Double;
    HasArgs: Boolean;
    W0, W1: Double;
    Jump: Boolean;
  end;

  { a parallelAxisExpand a view dispatched: when, which view, the window and
    the payload's animation as its JSON text: 'absent' for a click, 'null'
    for a jump, a duration of nought for a slide }
  TTyParallelExpandAction = record
    Time: Double;
    Par: Integer;
    W0, W1: Double;
    Animation: string;
  end;

{ _makeLayoutInfo again, on the option node as it stands: the window, its
  size, the collapse width, the inner indices -- and the option's own
  axisExpandWindow rewritten, as upstream rewrites it on every call }
procedure TyParallelRelayoutInfo(APar: TTyParallel; ANode: TJSONObject);
{ getSlidedAxisExpandWindow at (AX, AY), the window AW0 / AW1 the layout
  info gave (slid in place): none off the coordinate system or inside the
  window's quiet middle, a slide at its edges, a jump beyond them; under a
  collapse width of nought the window is laid over the pointer }
function TyParallelSlide(APar: TTyParallel; AX, AY: Double;
  var AW0, AW1: Double): TTyParallelSlide;

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.AxisLabels,
  tyControls.AdvChart.DataZoom,
  tyControls.AdvChart.AxisName, tyControls.AdvChart.Calendar, tyControls.AdvChart.Labels,
  tyControls.AdvChart.RichStyle;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ ---- option readers ---- }

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData.JSONType = jtObject) then Result := TJSONObject(AData)
  else Result := nil;
end;

function FindIn(ANode: TJSONObject; const AKey: string): TJSONData;
begin
  if ANode = nil then Exit(nil);
  Result := ANode.Find(AKey);
end;

function StrIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  d := FindIn(ANode, AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

{ JavaScript's truthiness of an option value }
function JsTruthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (not IsNan(AData.AsFloat)) and (AData.AsFloat <> 0);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

{ a number option, ADefault when it is no number }
function NumOr(AData: TJSONData; ADefault: Double): Double;
begin
  if (AData <> nil) and (AData.JSONType = jtNumber) then Result := AData.AsFloat
  else Result := ADefault;
end;

{ a lineStyle width under ANode.AKey, or ADefault }
function LineWidthIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var sub: TJSONObject;
begin
  Result := ADefault;
  sub := ObjOf(FindIn(ObjOf(FindIn(ANode, AKey)), 'lineStyle'));
  if sub <> nil then Result := NumOr(sub.Find('width'), ADefault);
end;

{ Math.min / Math.max of two: a not-a-number wins }
function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

{ restrict(len, extent) }
function Restrict(ALen, AE0, AE1: Double): Double;
begin
  Result := JMin(JMax(ALen, AE0), AE1);
end;

{ Math.floor / Math.ceil, an infinity or a not-a-number as it is }
function JFloor(A: Double): Double;
begin
  if IsNan(A) or IsInfinite(A) or (Abs(A) >= 4503599627370496.0) then Exit(A);
  Result := Floor64(A);
end;

function JCeil(A: Double): Double;
begin
  if IsNan(A) or IsInfinite(A) or (Abs(A) >= 4503599627370496.0) then Exit(A);
  Result := Ceil64(A);
end;

{ ==================== TTyParallel ==================== }

constructor TTyParallel.Create(AIndex: Integer);
begin
  inherited Create;
  FIndex := AIndex;
  FHorizontal := True;
end;

destructor TTyParallel.Destroy;
var i: Integer;
begin
  for i := 0 to High(FAxes) do FAxes[i].Free;
  inherited Destroy;
end;

function TTyParallel.AxisCount: Integer;
begin
  Result := Length(FAxes);
end;

function TTyParallel.Axis(AI: Integer): TTyAxis;
begin
  if (AI < 0) or (AI > High(FAxes)) then Exit(nil);
  Result := FAxes[AI];
end;

function TTyParallel.AxisOfDim(const ADim: string): Integer;
var i: Integer;
begin
  { _axesMap.set(dim): the last of a repeated dim wins }
  Result := -1;
  for i := 0 to High(Dims) do
    if Dims[i] = ADim then Result := i;
end;

function TTyParallel.AxisOfComponent(AComponent: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to High(AxisIndices) do
    if AxisIndices[i] = AComponent then Exit(i);
end;

function TTyParallel.AxisCoordToPoint(ACoord: Double; AI: Integer): TTyPointF;
var M: TTyMat2D;
begin
  if (AI < 0) or (AI > High(Layouts)) then Exit(TyPointF(NaN, NaN));
  M := Layouts[AI].M;
  { vector.applyTransform: m0 x + m2 y + m4, m1 x + m3 y + m5, y = 0 }
  Result.X := M[0] * ACoord + M[2] * 0 + M[4];
  Result.Y := M[1] * ACoord + M[3] * 0 + M[5];
end;

function TTyParallel.DataToPoint(AValue: Double; AI: Integer): TTyPointF;
var
  c: Double;
  mask: TFPUExceptionMask;
begin
  if (AI < 0) or (AI > High(FAxes)) then Exit(TyPointF(NaN, NaN));
  mask := MaskFP;
  try
    c := FAxes[AI].DataToCoord(AValue);
    Result := AxisCoordToPoint(c, AI);
  finally
    UnmaskFP(mask);
  end;
end;

function TTyParallel.ContainXY(AX, AY: Double): Boolean;
var pAxis, pLayout: Double;
begin
  if FHorizontal then
  begin
    pAxis := AY;
    pLayout := AX;
  end
  else
  begin
    pAxis := AX;
    pLayout := AY;
  end;
  if IsNan(pAxis) or IsNan(pLayout) then Exit(False);
  Result := (pAxis >= AxisBase) and (pAxis <= AxisBase + AxisLength)
    and (pLayout >= LayoutBase) and (pLayout <= LayoutBase + LayoutLength);
end;

function TTyParallel.HasAxisBrushed: Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(Intervals) do
    if Length(Intervals[i]) > 0 then Exit(True);
end;

function TTyParallel.AxisActiveState(AI: Integer; AValue: Double;
  AHas: Boolean): TTyParallelActive;
var
  i: Integer;
  iv: TTyParallelIntervalArray;
begin
  if (AI < 0) or (AI > High(Intervals)) then Exit(ppaNormal);
  iv := Intervals[AI];
  if Length(iv) = 0 then Exit(ppaNormal);
  { `value == null || isNaN(+value)` }
  if (not AHas) or IsNan(AValue) then Exit(ppaInactive);
  for i := 0 to High(iv) do
    if (iv[i][0] <= AValue) and (AValue <= iv[i][1]) then Exit(ppaActive);
  Result := ppaInactive;
end;

{ ==================== building ==================== }

const
  { TTyCalBoxKeys' order: width left right height top bottom }
  cBoxKey: array[0..5] of string = ('width', 'left', 'right', 'height', 'top', 'bottom');

function BoxOwn(ANode: TJSONObject; const AKey: string): TTyCalBoxKey;
var d: TJSONData;
begin
  Result := Default(TTyCalBoxKey);
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  Result.Own := True;
  Result.V := TyBoxRawOf(d);
end;

{ mergeDefaultAndTheme's mergeLayoutParam (layoutMode 'box') over the
  defaults 80 / 60 / 80 / 60, then getLayoutRect on the chart }
function ParallelBox(ANode: TJSONObject; const AViewport: TTyRectF): TTyXYWH;
var
  raw, target: TTyCalBoxKeys;
  box: TTyRawBox;
  k: Integer;

  procedure Def(AK: Integer; AV: Double);
  begin
    if target[AK].Own then Exit;
    target[AK].Own := True;
    target[AK].V := TyBoxRawNum(AV);
  end;

begin
  for k := 0 to 5 do raw[k] := BoxOwn(ANode, cBoxKey[k]);
  target := raw;
  Def(1, 80);
  Def(2, 80);
  Def(4, 60);
  Def(5, 60);
  TyCalMergeLayoutParam(target, raw, False, False);
  box := Default(TTyRawBox);
  box.Width := target[0].V;
  box.Left := target[1].V;
  box.Right := target[2].V;
  box.Height := target[3].V;
  box.Top := target[4].V;
  box.Bottom := target[5].V;
  Result := TyGetLayoutRect(box, AViewport.Left, AViewport.Top,
    AViewport.Right - AViewport.Left, AViewport.Bottom - AViewport.Top, []);
end;

{ `axisModel.get('parallelIndex') || 0`, strictly a number to match }
function AxisParallelIndex(ANode: TJSONObject): Double;
var d: TJSONData;
begin
  Result := 0;
  d := FindIn(ANode, 'parallelIndex');
  if not JsTruthy(d) then Exit(0);
  if d.JSONType = jtNumber then Result := d.AsFloat
  else Result := NaN;
end;

{ 'dim' + axisModel.get('dim'): the option as JavaScript prints it }
function DimNameOf(ANode: TJSONObject; out ANum: Integer): string;
var d: TJSONData;
begin
  ANum := -1;
  d := FindIn(ANode, 'dim');
  if (d = nil) then Exit(TyParallelDimPrefix + 'undefined');
  case d.JSONType of
    jtNumber:
      begin
        Result := TyParallelDimPrefix + TyJsNumberToString(d.AsFloat);
        if (not IsNan(d.AsFloat)) and (Frac(d.AsFloat) = 0) and (d.AsFloat >= 0)
          and (d.AsFloat < 100000) then ANum := Trunc(d.AsFloat);
      end;
    jtString:
      begin
        Result := TyParallelDimPrefix + d.AsString;
        { `+dimName.replace('dim', '')` }
        ANum := StrToIntDef(d.AsString, -1);
      end;
    jtNull: Result := TyParallelDimPrefix + 'null';
  else
    Result := TyParallelDimPrefix + '?';
  end;
end;

{ _makeLayoutInfo: the bases and lengths, the expansion's window, widths
  and inner indices -- and the option's axisExpandWindow rewritten
  ([1] = [0] + the restricted size), as upstream rewrites the model's own
  array every time it runs [Batch 140] }
procedure MakeLayoutInfo(P: TTyParallel; ANode: TJSONObject);
var
  layoutExtent1, winSize, center, collapse, expandCount, w1: Double;
  win, d: TJSONData;
  n, k: Integer;
begin
  if P.FHorizontal then
  begin
    P.LayoutBase := P.FRect.X;
    P.LayoutLength := P.FRect.W;
    P.AxisBase := P.FRect.Y;
    P.AxisLength := P.FRect.H;
  end
  else
  begin
    P.LayoutBase := P.FRect.Y;
    P.LayoutLength := P.FRect.H;
    P.AxisBase := P.FRect.X;
    P.AxisLength := P.FRect.W;
  end;
  n := Length(P.FAxes);
  layoutExtent1 := P.LayoutLength;
  P.ExpandWidth := Restrict(NumOr(FindIn(ANode, 'axisExpandWidth'), 50), 0, layoutExtent1);
  win := FindIn(ANode, 'axisExpandCount');
  if JsTruthy(win) and (win.JSONType = jtNumber) then expandCount := win.AsFloat
  else expandCount := 0;
  expandCount := Restrict(expandCount, 0, n);
  P.Expandable := JsTruthy(FindIn(ANode, 'axisExpandable')) and (n > 3)
    and (n > expandCount) and (expandCount > 1) and (P.ExpandWidth > 0)
    and (P.LayoutLength > 0);
  win := FindIn(ANode, 'axisExpandWindow');
  if (win is TJSONArray) and (win.Count >= 2) then
  begin
    P.ExpandWindow0 := NumOr(TJSONArray(win).Items[0], NaN);
    winSize := Restrict(NumOr(TJSONArray(win).Items[1], NaN) - P.ExpandWindow0, 0,
      layoutExtent1);
    P.ExpandWindow1 := P.ExpandWindow0 + winSize;
    { the model's array takes the sum: a number written back where it is
      one and differs (a not-a-number has no JSON) }
    w1 := P.ExpandWindow1;
    d := TJSONArray(win).Items[1];
    if (TJSONArray(win).Items[0].JSONType = jtNumber) and not (IsNan(w1) or IsInfinite(w1))
      and not ((d.JSONType = jtNumber) and (d.AsFloat = w1)) then
      TJSONArray(win).Floats[1] := w1;
  end
  else
  begin
    winSize := Restrict(P.ExpandWidth * (expandCount - 1), 0, layoutExtent1);
    center := NumOr(FindIn(ANode, 'axisExpandCenter'), 0);
    if not JsTruthy(FindIn(ANode, 'axisExpandCenter')) then center := JFloor(n / 2);
    P.ExpandWindow0 := P.ExpandWidth * center - winSize / 2;
    P.ExpandWindow1 := P.ExpandWindow0 + winSize;
  end;
  collapse := (P.LayoutLength - winSize) / (n - expandCount);
  if collapse < 3 then collapse := 0;
  P.CollapseWidth := collapse;
  P.WinInner0 := JFloor(TyJsToFixed(P.ExpandWindow0 / P.ExpandWidth, 1)) + 1;
  P.WinInner1 := JCeil(TyJsToFixed(P.ExpandWindow1 / P.ExpandWidth, 1)) - 1;
  P.ExpandWindow0Pos := collapse / P.ExpandWidth * P.ExpandWindow0;
  { what ParallelView reads off the model: the option as written over
    ParallelModel's defaults }
  P.ExpandOpt := JsTruthy(FindIn(ANode, 'axisExpandable'));
  d := FindIn(ANode, 'axisExpandTriggerOn');
  if d = nil then
  begin
    P.TriggerClick := True;
    P.TriggerMove := False;
  end
  else
  begin
    P.TriggerClick := (d.JSONType = jtString) and (d.AsString = 'click');
    P.TriggerMove := (d.JSONType = jtString) and (d.AsString = 'mousemove');
  end;
  P.SlideArea[0] := -0.15;
  P.SlideArea[1] := 0.05;
  P.SlideArea[2] := 0.4;
  P.SlideJump := True;
  d := FindIn(ANode, 'axisExpandSlideTriggerArea');
  if d is TJSONArray then
  begin
    for k := 0 to 2 do
      if (k < d.Count) and (TJSONArray(d).Items[k].JSONType = jtNumber) then
        P.SlideArea[k] := TJSONArray(d).Items[k].AsFloat
      else
        P.SlideArea[k] := NaN;
    P.SlideJump := not IsNan(P.SlideArea[0]);
    { `winSize * null` is nought }
    for k := 1 to 2 do
      if IsNan(P.SlideArea[k]) then P.SlideArea[k] := 0;
  end;
  d := FindIn(ANode, 'axisExpandRate');
  if d = nil then P.ExpandRate := 17
  else if d.JSONType = jtNumber then P.ExpandRate := d.AsFloat
  else P.ExpandRate := NaN;
  d := FindIn(ANode, 'axisExpandDebounce');
  if d = nil then P.ExpandDebounce := 50
  else if d.JSONType = jtNumber then P.ExpandDebounce := d.AsFloat
  else P.ExpandDebounce := 0;
end;

{ _layoutAxes }
procedure LayoutAxes(P: TTyParallel; ANode: TJSONObject);
var
  step, pos, avail, collapse: Double;
  n, i: Integer;
  e0, e1: Double;
  lay: TTyParallelAxisLayout;
  showLabel: Boolean;
  truncMax: Double;
begin
  MakeLayoutInfo(P, ANode);
  n := Length(P.FAxes);
  collapse := P.CollapseWidth;

  { every axis' extent: [0, axisLength], swapped when inverse }
  for i := 0 to n - 1 do
  begin
    if P.AxisInverse[i] then
    begin
      e0 := P.AxisLength;
      e1 := 0;
    end
    else
    begin
      e0 := 0;
      e1 := P.AxisLength;
    end;
    P.FAxes[i].SetPxExtent(e0, e1);
  end;

  SetLength(P.Layouts, n);
  for i := 0 to n - 1 do
  begin
    truncMax := NaN;
    if P.Expandable then
    begin
      { layoutAxisWithExpand }
      avail := collapse;
      showLabel := False;
      if i < P.WinInner0 then
      begin
        pos := i * collapse;
        truncMax := collapse;
      end
      else if i <= P.WinInner1 then
      begin
        pos := P.ExpandWindow0Pos + i * P.ExpandWidth - P.ExpandWindow0;
        avail := P.ExpandWidth;
        showLabel := True;
      end
      else
      begin
        pos := P.LayoutLength - (n - 1 - i) * collapse;
        truncMax := collapse;
      end;
    end
    else
    begin
      { layoutAxisWithoutExpand }
      step := P.LayoutLength / (n - 1);
      pos := step * i;
      avail := step;
      showLabel := True;
    end;
    lay := Default(TTyParallelAxisLayout);
    if P.FHorizontal then
    begin
      lay.PosX := pos + P.FRect.X;
      lay.PosY := P.AxisLength + P.FRect.Y;
      lay.Rotation := Pi / 2;
    end
    else
    begin
      lay.PosX := 0 + P.FRect.X;
      lay.PosY := pos + P.FRect.Y;
      lay.Rotation := 0;
    end;
    { matrix.rotate (the identity turned, even by nought), then translate }
    lay.M := TyMatIdentity;
    lay.M[0] := 1 * TyJsCos(lay.Rotation) + 0 * TyJsSin(lay.Rotation);
    lay.M[1] := -1 * TyJsSin(lay.Rotation) + 0 * TyJsCos(lay.Rotation);
    lay.M[2] := 0 * TyJsCos(lay.Rotation) + 1 * TyJsSin(lay.Rotation);
    lay.M[3] := -0 * TyJsSin(lay.Rotation) + TyJsCos(lay.Rotation) * 1;
    lay.M[4] := 0;
    lay.M[5] := 0;
    lay.M[4] := lay.M[4] + lay.PosX;
    lay.M[5] := lay.M[5] + lay.PosY;
    lay.NameAvailableWidth := avail;
    lay.LabelShow := showLabel;
    lay.NameTruncMax := truncMax;
    P.Layouts[i] := lay;
  end;
end;

function TyBuildParallels(AOption: TTyChartOption;
  const AViewport: TTyRectF): TTyParallelArray;
var
  n, p, k, cnt, num: Integer;
  d: TJSONData;
  node, an: TJSONObject;
  par: TTyParallel;
  ax: TTyAxis;
  u, dn: string;
  mask: TFPUExceptionMask;
begin
  Result := nil;
  if AOption = nil then Exit;
  n := AOption.ComponentCount('parallel');
  if n = 0 then Exit;
  SetLength(Result, n);
  cnt := AOption.ComponentCount('parallelAxis');
  mask := MaskFP;
  try
    for p := 0 to n - 1 do
    begin
      Result[p] := nil;
      d := AOption.ComponentAt('parallel', p);
      if not (d is TJSONObject) then Continue;
      node := TJSONObject(d);
      par := TTyParallel.Create(p);
      Result[p] := par;
      par.Id := StrIn(node, 'id');
      par.Name := StrIn(node, 'name');
      par.FHorizontal := StrIn(node, 'layout') <> 'vertical';
      if (FindIn(node, 'layout') <> nil) and (FindIn(node, 'layout').JSONType = jtString)
        and (FindIn(node, 'layout').AsString <> 'horizontal') then
        par.FHorizontal := False;
      { _initDimensions: the axes whose parallelIndex || 0 is this one }
      for k := 0 to cnt - 1 do
      begin
        an := ObjOf(AOption.ComponentAt('parallelAxis', k));
        if an = nil then Continue;
        if AxisParallelIndex(an) <> p then Continue;
        dn := DimNameOf(an, num);
        { ParallelAxis.isHorizontal: the layout is not horizontal }
        ax := TyCreateAxis(AOption, 'parallelAxis', k, dn,
          not par.FHorizontal, u, True);
        if par.FHorizontal then ax.Side := asLeft else ax.Side := asBottom;
        SetLength(par.FAxes, Length(par.FAxes) + 1);
        par.FAxes[High(par.FAxes)] := ax;
        SetLength(par.Dims, Length(par.Dims) + 1);
        par.Dims[High(par.Dims)] := dn;
        SetLength(par.DimNums, Length(par.DimNums) + 1);
        par.DimNums[High(par.DimNums)] := num;
        SetLength(par.AxisIndices, Length(par.AxisIndices) + 1);
        par.AxisIndices[High(par.AxisIndices)] := k;
        SetLength(par.AxisInverse, Length(par.AxisInverse) + 1);
        par.AxisInverse[High(par.AxisInverse)] := JsTruthy(an.Find('inverse'));
      end;
      SetLength(par.Intervals, Length(par.FAxes));
      par.FRect := ParallelBox(node, AViewport);
      LayoutAxes(par, node);
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TyParallelSeriesDims(APar: TTyParallel; ADataCount: Integer): TTySeriesDimArray;
var
  k, n, a, extra: Integer;
  ax: TTyAxis;

  function ExtraName: string;
  begin
    { genCoordDimName('value'): value, value0, value1, ... }
    if extra < 0 then Result := 'value' else Result := 'value' + IntToStr(extra);
    Inc(extra);
  end;

begin
  Result := nil;
  if APar = nil then Exit;
  n := ADataCount;
  for a := 0 to High(APar.DimNums) do
    if APar.DimNums[a] + 1 > n then n := APar.DimNums[a] + 1;
  if n < Length(APar.DimNums) then n := Length(APar.DimNums);
  SetLength(Result, n);
  extra := -1;
  for k := 0 to n - 1 do
  begin
    Result[k] := Default(TTySeriesDim);
    a := APar.AxisOfDim(TyParallelDimPrefix + IntToStr(k));
    if a >= 0 then
    begin
      ax := APar.Axis(a);
      Result[k].Name := TyParallelDimPrefix + IntToStr(k);
      case ax.AxisType of
        atCategory:
          begin
            Result[k].Kind := ddtOrdinal;
            Result[k].Axis := ax;
          end;
        atTime: Result[k].Kind := ddtTime;
      else
        Result[k].Kind := ddtFloat;
      end;
    end
    else
    begin
      Result[k].Name := ExtraName;
      Result[k].Kind := ddtFloat;
    end;
  end;
end;

procedure TyParallelApplyExtents(AOption: TTyChartOption; const APars: TTyParallelArray;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex);
var
  i, a: Integer;
  ax: TTyAxis;
  node: TJSONObject;
  raw: TTyAxisRawExtent;
  any, toggle: Boolean;
begin
  for i := 0 to High(APars) do
  begin
    if APars[i] = nil then Continue;
    for a := 0 to APars[i].AxisCount - 1 do
    begin
      ax := APars[i].Axis(a);
      node := ObjOf(AOption.ComponentAt('parallelAxis', ax.ComponentIndex));
      if AIndex <> nil then
        raw := TyAxisNoZoomExtent(AOption, ABindings, AStores, AStacks, AIndex,
          ax, 'parallelAxis', any)
      else
      begin
        raw := TyAxisRawExtent(node, ax, Infinity, NegInfinity, False);
        any := False;
      end;
      TyNiceAxisScale(AOption, ax, node, raw, any, nil, NaN, False, False,
        False, toggle);
      if toggle then APars[i].AxisInverse[a] := not APars[i].AxisInverse[a];
    end;
  end;
end;

{ ==================== the axis views ==================== }

{ a point through the axis group's matrix -- none where it needs no local
  transform }
procedure Apply(const M: TTyMat2D; AHas: Boolean; AX, AY: Double;
  out OX, OY: Double);
begin
  if not AHas then
  begin
    OX := AX;
    OY := AY;
    Exit;
  end;
  OX := M[0] * AX + M[2] * AY + M[4];
  OY := M[1] * AX + M[3] * AY + M[5];
end;

{ the name cut to AWidth (logical px) with the ellipsis nameTruncate wrote --
  what TyFillAxisLayoutSpec does for nameTruncate.maxWidth, for the width the
  coordinate system gives }
procedure CutName(var ASpec: TTyAxisLayoutSpec; AWidth: Double;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle);
begin
  if ASpec.NameRt.Needed then
  begin
    ASpec.NameRt.Style.WidthKind := rtwNumber;
    ASpec.NameRt.Style.Width := AWidth;
    ASpec.NameRt.Style.Overflow := rtoTruncate;
    ASpec.NameRt.Style.HasEllipsis := True;
    ASpec.NameRt.Style.Ellipsis := ASpec.NameTruncEllipsis;
    ASpec.NameMeter := TyRtBlockMeasurer(AMeasurer, ASpec.NameRt,
      AText.RtGlobal, ASpec.RtScale);
    Exit;
  end;
  if (ASpec.Name = '') or (AMeasurer = nil) then Exit;
  if ASpec.NameFontSizeLogical > 0 then
    ASpec.Name := string.Join(#10, TyZrPlainTextLines(ASpec.Name,
      AxisScaleF(AWidth, APPI), MaxDouble, 0, ASpec.NameTruncEllipsis, AMeasurer,
      ASpec.NameFontName, ASpec.NameFontSizeLogical, ASpec.NameFontWeight))
  else
    ASpec.Name := string.Join(#10, TyZrPlainTextLines(ASpec.Name,
      AxisScaleF(AWidth, APPI), MaxDouble, 0, ASpec.NameTruncEllipsis, AMeasurer,
      ASpec.FontName, ASpec.FontSizeLogical, ASpec.FontWeight));
  if Trim(StringReplace(ASpec.Name, #10, '', [rfReplaceAll])) = '' then
    ASpec.Name := '';
end;

{ endTextLayout's rotation for a name at either end: the name's own turn
  less the axis', into [0, 2 pi) }
function EndNameRotation(const ASpec: TTyAxisLayoutSpec; AAxisRot: Double): Double;
var r: Double;
begin
  if ASpec.HasNameRotate then r := ASpec.NameRotateRad else r := 0;
  Result := TyRemRadian(r - AAxisRot);
end;

procedure LayoutAxis(P: TTyParallel; AI: Integer; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorLen: Double; AMemory: TTyAxisMemoryStore);
var
  v: TTyParallelAxisView;
  ax: TTyAxis;
  node: TJSONObject;
  fr: TTyAxisNameFrame;
  lay: TTyParallelAxisLayout;
  e0, e1, len, endCoord, raw, used, w, mw, avail, sn: Double;
  M: TTyMat2D;
  hasM: Boolean;
  marks: TTyAxisMarkArray;
  minors: TTyDoubleArray;
  i, q: Integer;
  ln: TTyPolarLine;
  geoms: TTyLabelGeomArray;
  rect: TTyRectF;
  mask: TFPUExceptionMask;
begin
  v := Default(TTyParallelAxisView);
  ax := P.Axis(AI);
  lay := P.Layouts[AI];
  node := ObjOf(AOption.ComponentAt(ax.MainType, ax.ComponentIndex));
  v.Shown := ax.Visible;
  v.Blank := ax.Scale.Blank;
  v.Furn := TyAxisFurnitureOf(node, ax, True, True);
  if not v.Shown then
  begin
    P.Views[AI] := v;
    Exit;
  end;
  { axisLabelShow: the coordinate system's word over axisLabel.show }
  v.Furn.ShowLabels := lay.LabelShow;
  rect := TyRectF(0, 0, 1, 1);
  TyFillAxisLayoutSpec(v.Spec, ax, node, v.Furn, AText, AMeasurer, APPI,
    False, False);
  { THE NAME'S WIDTH: nameTruncateMaxWidth (a collapsed axis), else
    nameTruncate.maxWidth, else -- at either end -- the room between two
    axes over the sine of the name's turn, where that is finite }
  if not v.Spec.HasNameTrunc and (v.Spec.Name <> '') then
  begin
    mask := MaskFP;
    try
      avail := NaN;
      if not IsNan(lay.NameTruncMax) then
        avail := lay.NameTruncMax
      else if v.Spec.NameLocation <> anlMiddle then
      begin
        sn := TyJsSin(EndNameRotation(v.Spec, lay.Rotation));
        avail := Abs(lay.NameAvailableWidth / sn);
        if IsInfinite(avail) then avail := NaN;
      end;
      { device px to the logical px the name is cut in }
      if (not IsNan(avail)) and (APPI > 0) then avail := avail * 96 / APPI;
    finally
      UnmaskFP(mask);
    end;
    if not IsNan(avail) then CutName(v.Spec, avail, AMeasurer, APPI, AText);
  end;
  { AxisBuilder's frame: at the axis' place, turned by its rotation, the
    ticks and the labels on the +1 side, the name on the +1 }
  ax.LocalExtent(e0, e1);
  fr := Default(TTyAxisNameFrame);
  fr.PosX := lay.PosX;
  fr.PosY := lay.PosY;
  fr.Rotation := lay.Rotation;
  fr.Ext0 := e0;
  fr.Ext1 := e1;
  fr.LabelOffset := 0;
  fr.NameDirection := 1;
  fr.Inverse := P.AxisInverse[AI];
  if P.Horizontal then v.Spec.Side := asLeft else v.Spec.Side := asBottom;
  v.Spec.FreeFrame := True;
  v.Spec.LabelDirection := 1;
  v.Spec.TickInside := False;
  v.Spec.LabelInside := False;
  v.Spec.Inverse := P.AxisInverse[AI];
  v.Spec.NameFrame := fr;
  v.Spec.HasNameFrame := True;
  if v.Blank then v.Spec.ShowLabels := False;
  { the category interval through the axis model's store, as the grid's }
  if (v.Spec.LabelKind = lakCategory) and (v.Spec.ForcedLabelStep = 0)
    and not v.Blank and (TyCategoryLabelCount(v.Spec) >= 2) then
  begin
    raw := TyCategoryLabelInterval(v.Spec, rect, AMeasurer, APPI);
    used := raw;
    if AMemory <> nil then
      used := TyCategoryIntervalHold(AMemory.Find(ax.MainType
        + IntToStr(ax.ComponentIndex), True), raw, TyCategoryLabelCount(v.Spec),
        e0, e1);
    if (not IsNan(used)) and (not IsInfinite(used)) and (used >= 0)
      and (used < MaxInt - 1) then
      v.Spec.ForcedLabelStep := Trunc(used) + 1;
  end;
  v.Spec.LabelStep := TyAxisLabelStep(v.Spec, rect, AMeasurer, APPI);
  if v.Spec.LabelStep < 1 then v.Spec.LabelStep := 1;
  v.Spec.Placements := TyLayoutAxisLabels(v.Spec, rect, AMeasurer, APPI);
  { the name, moved off its own labels }
  if v.Spec.Name <> '' then
  begin
    geoms := TyAxisLabelGeoms(v.Spec, rect, AMeasurer, APPI);
    TySortLabelGeoms(geoms, fr);
    if v.Spec.NameNoMove then geoms := nil;
    v.Spec.NamePlacement := TyLayoutAxisName(v.Spec, fr, 0, geoms, [], 0,
      AMeasurer, APPI);
  end;
  { the blocks where they hang }
  if v.Spec.LabelRt.Needed then
    for i := 0 to High(v.Spec.Placements) do
      if v.Spec.Placements[i].Shown then
        v.Spec.Placements[i].Rt := TyAxisRtPieces(v.Spec, v.Spec.LabelRt,
          v.Spec.Placements[i].Text, v.Spec.FontName, v.Spec.FontSizeLogical,
          v.Spec.FontWeight, v.Spec.HasLabelColour, v.Spec.LabelColour,
          v.Spec.Placements[i].AnchorH, v.Spec.Placements[i].AnchorV, AMeasurer);
  if v.Spec.NameRt.Needed and v.Spec.NamePlacement.Shown then
  begin
    if v.Spec.NameFontSizeLogical > 0 then
      v.Spec.NamePlacement.Rt := TyAxisRtPieces(v.Spec, v.Spec.NameRt,
        v.Spec.NamePlacement.Text, v.Spec.NameFontName, v.Spec.NameFontSizeLogical,
        v.Spec.NameFontWeight, v.Spec.HasNameColour, v.Spec.NameColour,
        v.Spec.NamePlacement.AnchorH, v.Spec.NamePlacement.AnchorV, AMeasurer)
    else
      v.Spec.NamePlacement.Rt := TyAxisRtPieces(v.Spec, v.Spec.NameRt,
        v.Spec.NamePlacement.Text, v.Spec.FontName, v.Spec.FontSizeLogical,
        v.Spec.FontWeight, v.Spec.HasNameColour, v.Spec.NameColour,
        v.Spec.NamePlacement.AnchorH, v.Spec.NamePlacement.AnchorV, AMeasurer);
  end;

  hasM := TyNeedLocal(lay.PosX, lay.PosY, lay.Rotation);
  M := TyMatLocal(lay.PosX, lay.PosY, lay.Rotation);
  { the line, on the pixel grid }
  if v.Furn.ShowLine then
  begin
    v.HasLine := True;
    v.Line := Default(TTyPolarLine);
    Apply(M, hasM, e0, 0, v.Line.X1, v.Line.Y1);
    Apply(M, hasM, e1, 0, v.Line.X2, v.Line.Y2);
    v.Line.Value := NaN;
    v.Line.Drawn := True;
    TyPolarSubPixelLine(v.Line, AxisScaleF(LineWidthIn(node, 'axisLine', 1), APPI));
    v.Spec.Arrows := TyAxisArrows(fr, v.Furn, APPI);
  end;
  marks := TyPolarTickMarks(AOption, ax, v.Spec, v.Furn, AMeasurer, APPI);
  { the ticks: tickDirection +1, sub-pixel optimised; a tick whose label was
    built and hidden goes with it (syncLabelIgnoreToMajorTicks), unless it
    is on a band edge or the minor ticks are shown }
  if v.Furn.ShowTicks and not v.Blank then
  begin
    len := AxisScaleF(v.Spec.TickLengthLogical, APPI);
    endCoord := 1 * len;
    w := AxisScaleF(LineWidthIn(node, 'axisTick', 1), APPI);
    SetLength(v.Ticks, Length(marks));
    for i := 0 to High(marks) do
    begin
      ln := Default(TTyPolarLine);
      Apply(M, hasM, marks[i].Coord, 0, ln.X1, ln.Y1);
      Apply(M, hasM, marks[i].Coord, endCoord, ln.X2, ln.Y2);
      TyPolarSubPixelLine(ln, w);
      ln.Value := marks[i].Value;
      ln.Drawn := True;
      if (not v.Furn.MinorTickOption) and not marks[i].OnBand then
        for q := 0 to High(v.Spec.Placements) do
          if v.Spec.Placements[q].Built and not v.Spec.Placements[q].Shown
            and (q <= High(v.Spec.TickValues))
            and (v.Spec.TickValues[q] = marks[i].Value) then
          begin
            ln.Drawn := False;
            Break;
          end;
      v.Ticks[i] := ln;
    end;
  end;
  minors := TyPolarMinorCoords(ax);
  if v.Furn.ShowMinorTick and not v.Blank then
  begin
    if IsNan(v.Furn.MinorTickLengthLogical) then
      len := AxisScaleF(AMinorLen, APPI)
    else
      len := AxisScaleF(v.Furn.MinorTickLengthLogical, APPI);
    endCoord := 1 * len;
    mw := AxisScaleF(LineWidthIn(node, 'minorTick',
      LineWidthIn(node, 'axisTick', 1)), APPI);
    SetLength(v.MinorTicks, Length(minors));
    for i := 0 to High(minors) do
    begin
      ln := Default(TTyPolarLine);
      Apply(M, hasM, minors[i], 0, ln.X1, ln.Y1);
      Apply(M, hasM, minors[i], endCoord, ln.X2, ln.Y2);
      TyPolarSubPixelLine(ln, mw);
      ln.Value := NaN;
      ln.Drawn := True;
      v.MinorTicks[i] := ln;
    end;
  end;
  P.Views[AI] := v;
end;

procedure TyLayoutParallels(const APars: TTyParallelArray; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorTickLenLogical: Double; AMemory: TTyAxisMemoryStore);
var
  i, a: Integer;
  mask: TFPUExceptionMask;
begin
  { A LONE AXIS stands at Infinity * 0 -- not a number, as upstream's
    does -- and every sum after it is one too }
  mask := MaskFP;
  try
    for i := 0 to High(APars) do
    begin
      if APars[i] = nil then Continue;
      SetLength(APars[i].Views, APars[i].AxisCount);
      for a := 0 to APars[i].AxisCount - 1 do
        LayoutAxis(APars[i], a, AOption, AMeasurer, APPI, AText,
          AMinorTickLenLogical, AMemory);
    end;
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== the series ==================== }

function TyParallelSmoothOf(ASeries: TJSONObject): Double;
var
  d: TJSONData;
  v: TTyDataValue;
begin
  Result := 0;
  d := FindIn(ASeries, 'smooth');
  if d = nil then Exit(0);
  case d.JSONType of
    jtBoolean:
      if d.AsBoolean then Result := TyParallelDefaultSmooth else Result := 0;
    jtNumber:
      begin
        v := TyDataNum(d.AsFloat);
        Result := TyJsNumericToNumber(v);
      end;
    jtString:
      begin
        v := TyDataText(d.AsString);
        Result := TyJsNumericToNumber(v);
      end;
  else
    Result := NaN;
  end;
  if IsNan(Result) then Result := 0;
end;

function Cmd(AKind: TTyPathCmdKind; AX1, AY1, AX2, AY2, AX, AY: Double): TTyPathCmd;
begin
  Result.Kind := AKind;
  Result.X1 := AX1;
  Result.Y1 := AY1;
  Result.X2 := AX2;
  Result.Y2 := AY2;
  Result.X := AX;
  Result.Y := AY;
end;

function TyParallelSmoothCmds(const APts: TTyPointFArray; ASmooth: Double): TTyPathCmdArray;
var
  cps: TTyPointFArray;
  i, len, k: Integer;
  pt, prv, nxt: TTyPointF;
  vx, vy, d0, d1, sum, v1x, v1y, v2x, v2y: Double;
  mask: TFPUExceptionMask;

  function Dist(const A, B: TTyPointF): Double;
  begin
    Result := Sqrt((A.X - B.X) * (A.X - B.X) + (A.Y - B.Y) * (A.Y - B.Y));
  end;

begin
  Result := nil;
  len := Length(APts);
  if len < 2 then Exit;
  mask := MaskFP;
  try
    { smoothBezier, not a loop: an end point is its own control point }
    cps := nil;
    for i := 0 to len - 1 do
    begin
      pt := APts[i];
      if (i = 0) or (i = len - 1) then
      begin
        SetLength(cps, Length(cps) + 1);
        cps[High(cps)] := pt;
        Continue;
      end;
      prv := APts[i - 1];
      nxt := APts[i + 1];
      vx := (nxt.X - prv.X) * ASmooth;
      vy := (nxt.Y - prv.Y) * ASmooth;
      d0 := Dist(pt, prv);
      d1 := Dist(pt, nxt);
      sum := d0 + d1;
      if sum <> 0 then
      begin
        d0 := d0 / sum;
        d1 := d1 / sum;
      end;
      v1x := vx * -d0;
      v1y := vy * -d0;
      v2x := vx * d1;
      v2y := vy * d1;
      SetLength(cps, Length(cps) + 2);
      cps[High(cps) - 1] := TyPointF(pt.X + v1x, pt.Y + v1y);
      cps[High(cps)] := TyPointF(pt.X + v2x, pt.Y + v2y);
    end;
    SetLength(Result, len);
    Result[0] := Cmd(pckMove, 0, 0, 0, 0, APts[0].X, APts[0].Y);
    for k := 0 to len - 2 do
      Result[k + 1] := Cmd(pckCurve, cps[k * 2].X, cps[k * 2].Y,
        cps[k * 2 + 1].X, cps[k * 2 + 1].Y, APts[k + 1].X, APts[k + 1].Y);
  finally
    UnmaskFP(mask);
  end;
end;

function TyParallelSampleCmds(const ACmds: TTyPathCmdArray; ASteps: Integer): TTyPointFArray;
var
  i, s, n: Integer;
  x0, y0, t, u: Double;
begin
  Result := nil;
  if Length(ACmds) = 0 then Exit;
  if ASteps < 1 then ASteps := 1;
  n := 0;
  SetLength(Result, 1 + (Length(ACmds) - 1) * ASteps);
  x0 := ACmds[0].X;
  y0 := ACmds[0].Y;
  Result[0] := TyPointF(x0, y0);
  n := 1;
  for i := 1 to High(ACmds) do
  begin
    for s := 1 to ASteps do
    begin
      t := s / ASteps;
      u := 1 - t;
      if ACmds[i].Kind = pckCurve then
        Result[n] := TyPointF(
          u * u * u * x0 + 3 * u * u * t * ACmds[i].X1 + 3 * u * t * t * ACmds[i].X2 + t * t * t * ACmds[i].X,
          u * u * u * y0 + 3 * u * u * t * ACmds[i].Y1 + 3 * u * t * t * ACmds[i].Y2 + t * t * t * ACmds[i].Y)
      else
        Result[n] := TyPointF(x0 + (ACmds[i].X - x0) * t, y0 + (ACmds[i].Y - y0) * t);
      Inc(n);
    end;
    x0 := ACmds[i].X;
    y0 := ACmds[i].Y;
  end;
  SetLength(Result, n);
end;

{ a coordinate the canvas would skip: lineTo / bezierCurveTo with a
  not-a-number or an infinite argument does nothing }
function Finite2(AX, AY: Double): Boolean;
begin
  Result := not (IsNan(AX) or IsNan(AY) or IsInfinite(AX) or IsInfinite(AY));
end;

{ the path as a canvas draws it: the calls with an argument that is not
  finite dropped (the current point stays where the last good one left it) }
function DrawableCmds(const ACmds: TTyPathCmdArray): TTyPathCmdArray;
var i, n: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ACmds));
  n := 0;
  for i := 0 to High(ACmds) do
  begin
    if not Finite2(ACmds[i].X, ACmds[i].Y) then Continue;
    if (ACmds[i].Kind = pckCurve) and not (Finite2(ACmds[i].X1, ACmds[i].Y1)
      and Finite2(ACmds[i].X2, ACmds[i].Y2)) then Continue;
    Result[n] := ACmds[i];
    Inc(n);
  end;
  SetLength(Result, n);
end;

function DrawablePoints(const APts: TTyPointFArray): TTyPointFArray;
var i, n: Integer;
begin
  Result := nil;
  SetLength(Result, Length(APts));
  n := 0;
  for i := 0 to High(APts) do
    if Finite2(APts[i].X, APts[i].Y) then
    begin
      Result[n] := APts[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TyBuildParallelMarks(const ASolved: TTyParallelSolved; AList: TTyPaintList): Integer;
var
  i: Integer;
  r: TTyParallelRow;
  el: TTyChartElement;
  pts: TTyPointFArray;
  cmds: TTyPathCmdArray;
begin
  Result := 0;
  if (AList = nil) or not ASolved.Valid then Exit;
  for i := 0 to High(ASolved.Rows) do
  begin
    r := ASolved.Rows[i];
    cmds := nil;
    if Length(r.Cmds) > 0 then
    begin
      cmds := DrawableCmds(r.Cmds);
      if (Length(cmds) > 0) and (cmds[0].Kind <> pckMove) then cmds[0].Kind := pckMove;
      pts := TyParallelSampleCmds(cmds, 16);
    end
    else
      pts := DrawablePoints(r.Pts);
    el := TyChartElement(TyShapePolyline(pts));
    if Length(cmds) > 1 then el.Shape.Cmds := cmds;
    el.Style.HasFill := False;
    el.Style.StrokeColor := r.Stroke;
    el.Style.StrokeWidthLogical := r.Width;
    el.Style.Alpha := r.Opacity;
    el.Style.DashLogical := r.Dash;
    el.Z := ASolved.Z;
    el.Z2 := ASolved.Z2;
    el.Silent := False;
    el.Datum := TyChartDatum(ASolved.SeriesIndex, r.Row, r.Raw);
    { Path.contain: the stroke at max(lineWidth, strokeContainThreshold 5) }
    el.HitSlopLogical := Math.Max(r.Width, Double(5)) / 2;
    el.Anim.Series := ASolved.SeriesIndex;
    el.Anim.Index := r.Row;
    if ASolved.EnterClip then
    begin
      el.Anim.Role := carParallelLine;
      el.Anim.G[0] := ASolved.Clip.X;
      el.Anim.G[1] := ASolved.Clip.Y;
      el.Anim.G[2] := ASolved.Clip.W;
      el.Anim.G[3] := ASolved.Clip.H;
      if ASolved.Horizontal then el.Anim.G[4] := 1 else el.Anim.G[4] := 0;
      if ASolved.NewView then el.Anim.G[5] := 1 else el.Anim.G[5] := 0;
    end;
    AList.Add(el);
    Inc(Result);
  end;
end;

function TyParallelIntervalsOf(AData: TJSONData): TTyParallelIntervalArray;
var
  i: Integer;
  it: TJSONData;
  a, b, t: Double;
begin
  Result := nil;
  if not (AData is TJSONArray) then Exit;
  for i := 0 to AData.Count - 1 do
  begin
    it := TJSONArray(AData).Items[i];
    a := NaN;
    b := NaN;
    if (it is TJSONArray) and (it.Count >= 1) then a := NumOr(TJSONArray(it).Items[0], NaN);
    if (it is TJSONArray) and (it.Count >= 2) then b := NumOr(TJSONArray(it).Items[1], NaN);
    { numberUtil.asc: (a, b) => a - b; a not-a-number compares as nought }
    if (not IsNan(a)) and (not IsNan(b)) and (b < a) then
    begin
      t := a;
      a := b;
      b := t;
    end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)][0] := a;
    Result[High(Result)][1] := b;
  end;
end;

{ ==================== the conversions ==================== }

function TyParallelContainJson(APar: TTyParallel; APoint: TJSONData): Boolean;
var pt: TTyPointF;
begin
  Result := False;
  if APar = nil then Exit;
  pt := TyJsonPoint(APoint);
  Result := APar.ContainXY(pt.X, pt.Y);
end;

{ ==================== the expansion [Batch 140] ==================== }

procedure TyParallelRelayoutInfo(APar: TTyParallel; ANode: TJSONObject);
var mask: TFPUExceptionMask;
begin
  if APar = nil then Exit;
  mask := MaskFP;
  try
    MakeLayoutInfo(APar, ANode);
  finally
    UnmaskFP(mask);
  end;
end;

function TyParallelSlide(APar: TTyParallel; AX, AY: Double;
  var AW0, AW1: Double): TTyParallelSlide;
var
  ws, ws2, ext1, pc, delta, cw, pos: Double;
  ends: array[0..1] of Double;
  mask: TFPUExceptionMask;
begin
  Result := pslNone;
  if APar = nil then Exit;
  mask := MaskFP;
  try
    ws := AW1 - AW0;
    ext1 := APar.ExpandWidth * (APar.AxisCount - 1);
    { out of the coordinate system }
    if not APar.ContainXY(AX, AY) then Exit;
    { the point in expand coordinates }
    if APar.Horizontal then pc := AX else pc := AY;
    pc := pc - APar.LayoutBase - APar.ExpandWindow0Pos;
    Result := pslSlide;
    cw := APar.CollapseWidth;
    { `if (axisCollapseWidth)` }
    if (cw <> 0) and not IsNan(cw) then
    begin
      if APar.SlideJump and (pc < ws * APar.SlideArea[0]) then
      begin
        Result := pslJump;
        delta := pc - ws * APar.SlideArea[2];
      end
      else if APar.SlideJump and (pc > ws * (1 - APar.SlideArea[0])) then
      begin
        Result := pslJump;
        delta := pc - ws * (1 - APar.SlideArea[2]);
      end
      else
      begin
        { the quiet middle of the window does not slide }
        delta := pc - ws * APar.SlideArea[1];
        if delta >= 0 then
        begin
          delta := pc - ws * (1 - APar.SlideArea[1]);
          if delta <= 0 then delta := 0;
        end;
      end;
      delta := delta * (APar.ExpandWidth / cw);
      if (delta <> 0) and not IsNan(delta) then
      begin
        ends[0] := AW0;
        ends[1] := AW1;
        TyDzSliderMove(delta, ends, 0, ext1, -1, NaN, NaN);
        AW0 := ends[0];
        AW1 := ends[1];
      end
      else
        Result := pslNone;
    end
    else
    begin
      { too narrow to fold: the window laid over the pointer }
      ws2 := AW1 - AW0;
      pos := ext1 * pc / ws2;
      AW0 := JMax(0, pos - ws2 / 2);
      AW1 := JMin(ext1, AW0 + ws2);
      AW0 := AW1 - ws2;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

end.
