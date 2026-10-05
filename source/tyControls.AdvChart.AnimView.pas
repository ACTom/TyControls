unit tyControls.AdvChart.AnimView;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the enter, update and leave animations, between the
  paint list and the engine. [Batch 89, AN2; Batch 90, AN3]

  THE BINDING. A chart element is a record in a list that is rebuilt on every
  static render; an animation has to outlive that. So what animates is a
  PROXY -- a TTyAnimBag holding upstream's own props for one of upstream's
  elements (a bar's shape.x/y/width/height, a symbol's scaleX/scaleY and
  style.opacity, a line's clip rect) -- keyed by (series, view row, role).
  The builders tag each element with its role and the numbers upstream
  animates it in (TTyChartElement.Anim); Arm makes the proxies and starts
  their enter animations exactly as upstream's views do; Bind finds each
  element's proxy again after a rebuild; and a FRAME is the list with every
  bound element rewritten from its proxy's current values, which is what the
  dynamic layer draws while the clips run.

  WHAT EACH ROLE ANIMATES (wf86 3A/3B, the views cited there):
    bar          shape.height (or width laid on its side) 0 -> layout, enter
                 timing at the row (BarView.ts:241-314, 784-788)
    symbol       a scatter symbol path: scaleX/Y 0 -> size/2, style.opacity
                 0 -> its own, about the path's origin (Symbol.ts:184-200)
    lineSymbol   a line's symbol group: scale 0 -> 1, 200 ms, no easing,
                 delay = duration * (where the clip reaches it) + delay, or
                 the delay function at the row; ignores the threshold
                 (LineView.ts:1078-1177)
    lineClip     the line's clip rect grows along the base axis, enter timing
                 with no row; `clip: false` widens it after the call, and
                 the forced tracks write the unwidened rect back on the next
                 frame -- upstream's, kept (createClipPathFromCoordSys.ts)
    sector       a pie slice sweeps both angles out of the first slice's
                 start, or grows r from r0 for animationType 'scale'
                 (PieView.ts:55-130)
    funnel       style.opacity 0 -> its own (FunnelView.ts:70-79)
    gaugePointer rotation from the start angle, no row
    gaugeProgress shape.endAngle from the start angle, no row; its round
                 end cap follows the end (GaugeView.ts:464-483)
    radarLine,   shape.points out of the centre; both always, the area even
    radarArea    where nothing fills it (RadarView.ts:106-130)
    candle       shape.points: every point's value coordinate out of the
                 open price's (CandlestickView.ts:117-128, 326-332)
    label        LabelManager's first appearance: style.opacity 0 -> 1 at
                 the row, for a series that animates and a label that does
                 not count its value; a line symbol's own, 300 ms from 0,
                 the symbol's delay (LabelManager.ts:528-563)
    guide        a label line's style.strokePercent 0 -> 1, no row

  A LABEL FOLLOWS ITS HOST. zrender recomputes a text's place from its
  host's current rect every frame, so a bar's 'top' label rides the bar up;
  a frame moves each such label by the difference between its anchor on the
  host as drawn and on the host at rest.

  A PROXY AT REST IS THE LAYOUT. Every key is compared with the value the
  layout gave it; while all are equal the element is drawn untouched, so a
  finished animation draws exactly the static picture. A key that rests one
  unit in the last place off -- the final step computes (to - from) * 1 +
  from -- draws there, as upstream's does.

  AN UPDATE [Batch 90]. The control's Option is notMerge, and upstream keeps
  a series' VIEW across a notMerge setOption when the series' model id is
  the same -- its id, else its name (and how many before it share it), else
  its index -- and its type is; the view keeps its old data and diffs the new
  against it (DataDiffer by getId: the item's id, else its name -- the item's
  own or the category's -- with `__ec__N` on a repeat, else 'e\0\0' + the raw
  index). ArmUpdate does what each view's render does with the diff:
    bar          kept: updateProps(shape) from where it is, update timing at
                 the NEW row; added: the enter above; removed: the fade
    sector       kept: the whole shape, update timing at the new row; added:
                 endAngle out of its own start at UPDATE timing (or, for
                 'scale', r from r0 at enter timing); removed: the fade
    symbol       kept: path scale at the new row, group x/y with no row;
                 added: the enter; removed: opacity and scale to 0, 200 ms
    line         the clip initProps to the new rect (enter timing); symbols
                 set to their new place; the polyline and polygon through
                 lineAnimationDiff (below); removed symbols as a symbol's
    funnel       opacity at the new row; gauge pointer and progress from
                 where they were, no row; radar points, no row; candle
                 points at the new row (added candles final, removed ones
                 gone at once)
    label        a kept host's label is the same text: no new animation; a
                 new one fades in (LabelManager's first appearance)
  THE FADE (removeElementWithFadeOut): style.opacity to 0, 200 ms cubicOut
  whatever the option says, the label gone at once, the element removed when
  it ends. A removed element is a GHOST here: the old element's record and
  its proxy, drawn after the list (silent) until the fade ends.
  Under notMerge a series that is not kept is gone at once -- its view's
  group leaves the zr root -- and the axes are new views: they never
  groupTransition (probed on the real build).

  lineAnimationDiff: '=' from the old layout point (not-a-number: the new
  one), '+' from where the new datum sits in the OLD coordinate system, '-'
  dropped; sorted by the new raw index into Float32 arrays; past a 3000 px
  bounding difference the line is set, not tweened. The symbols kept
  ('=') follow the polyline's points every frame (its first animator's
  during).

  LABELS, MARKERS AND WHAT NEVER STOPS [Batch 92, AN4]:
    label        a COUNT (label.valueAnimation, a bar's only -- BarView's
                 setLabelValueAnimation): `percent` 0 -> 1 with the count
                 as its during (labelStyle.ts animateLabelValue), from the
                 previous value -- or the interpolated one of a count in
                 flight -- and nothing when the value did not change; enter
                 timing when there was no previous value, update otherwise;
                 no fade. A pie's label in an update: x / y / rotation from
                 the last layout (LabelManager's oldLayout) at update timing
                 and the row
    guide        in an update: shape.points from the old ones, no row
    gaugeDetail  the reading counts the same way, the gauge's own timing
    markPoint    SymbolDraw's pop-in on the MARKER's model (MarkerModel:
                 its `animation` and the host's isAnimationEnabled), at the
                 marker's data index
    markLine     one proxy per line, shape.percent 0 -> 1 (Line.ts
                 _createLine); the end symbols scale by the percent and the
                 label follows Line.beforeUpdate at that percent
    effectSymbol EffectSymbol: the scale at UPDATE timing from 0 (the
                 second updateData stops the first's tracks before they
                 step), the opacity tween stranded on a replaced style
                 object -- it runs, and moves nothing
    ripple       loops for ever: scale 0.5 -> rippleScale / 2, opacity
                 1 -> 0 over the period, delay -i / n * period + idx /
                 count (EffectSymbol.ts:77-119); carried through an update
                 unless the type, period, scale or number changed
    endLabel     a line's end label rides its clip: the clip's during is
                 LineView._endLabelOnDuring (the place on the line where the
                 clip has got to, and the value there).

  STATES [Batch 94, AN3b]. emphasis, blur and select switch through the
  engine's useStates on the SAME proxy the enter and update animations run on
  when upstream's element is the same one (a bar, a slice, a scatter symbol's
  path, a funnel piece, a candle, a label, a label line), so a hover in the
  middle of an enter or an update meets its animators as upstream's does
  (saveTo, stopTracks, __changeFinalValue); elsewhere a proxy of the states'
  own ('st:' roles: a line symbol's path under its group, a line's polyline
  and area, a heatmap cell, a pictorial glyph, a sunburst piece). The state
  keys a proxy carries -- style.fill / stroke / lineWidth / opacity, x / y,
  scaleX / scaleY, shape.r -- are SEEDED with the rest values (StKeys, with
  their rest values beside); a frame draws each one that is off its rest
  over the list's element (TyAnimApplyState): colours and widths and
  opacities as they are, x / y as a translation, a scale about the symbol's
  centre, a radius as the slice's. A key the role's own branch draws (a
  symbol's scale and opacity, a slice's shape, a label's place and fade) is
  left to it. }
interface
uses SysUtils, Classes, Math, contnrs,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Anim,
  tyControls.AdvChart.AnimOpt;

type
  TTyChartAnimProxy = class;

  { A LINE'S END LABEL, driven by its clip (LineView._endLabelOnDuring)
    [Batch 92, AN4] }
  TTyChartAnimEndLabel = record
    { the clip drives it: an entering clip with the label shown }
    Active: Boolean;
    { the layout points (flat x, y per row, Float32 values), each row's raw
      value (not a number: none), the polyline's path }
    Pts, Vals: TTyDoubleArray;
    Cmds: TTyPathCmdArray;
    Horiz, Inverse, ConnectNulls, ValueAnim, HasPrec: Boolean;
    Prec, Distance: Double;
    { the words, #1 where the value goes }
    Tpl: string;
    { the animation record }
    LastFrameIndex: Integer;
    HasOriginal: Boolean;
    OriginalX, OriginalY: Double;
    { where it is now, and what it says }
    X, Y: Double;
    Text: string;
    HasText: Boolean;
  end;

  { a symbol following a polyline's points: which, and its point }
  TTyChartAnimFollow = record
    P: TTyChartAnimProxy;
    Pt: Integer;
  end;

  TTyChartAnimProxy = class(TTyAnimBag)
  private
    FSeries, FIndex: Integer;
    FRole: string;
    FFinal: TTyAnimProps;
    { an update's bookkeeping: carried over to the new list }
    FClaimed: Boolean;
    { A GHOST: removed from the data, still drawn while it leaves -- the old
      element's record, and whether the fade has ended [Batch 90] }
    FLeaving, FGone: Boolean;
    FGhost: TTyChartElement;
    { a line's polyline: the symbols that follow its points }
    FFollow: array of TTyChartAnimFollow;
    { A COUNT (animateLabelValue) [Batch 92]: from, to, the interpolated
      value while it runs, the precision, the words; and the text now }
    FValFrom, FValTo, FValInterp, FValPrec: Double;
    FValHasInterp, FValHasPrec: Boolean;
    FValTpl: string;
    FText: string;
    FHasText: Boolean;
    { a line's clip: its end label }
    FEnd: TTyChartAnimEndLabel;
    { THE STATE KEYS and their rest values [Batch 94] }
    FStKeys: TTyStringArray;
    FStRest: TTyAnimProps;
    FStPrev: string;
    { a pie label's place under its select state: LabelManager's
      oldLayoutSelect }
    FStSelX, FStSelY: Double;
    FStHasSel: Boolean;
  public
    constructor Create(ASeries, AIndex: Integer; const ARole: string);
    { the values the layout gave every key }
    procedure SetFinal(const AProps: TTyAnimProps);
    function FinalOf(const AKey: string): TTyAnimValue;
    { every key at its layout value, bit for bit }
    function AtFinal: Boolean;
    { a leave animation's done: the element is removed }
    procedure LeaveDone;
    { the polyline's during: every following symbol to its point }
    procedure FollowDuring(APercent: Double);
    function FollowCount: Integer;
    { the count's during: the interpolated value into the words }
    procedure ValueDuring(APercent: Double);
    { the line clip's during and done, for its end label }
    procedure EndLabelDuring(APercent: Double);
    procedure EndLabelDone;
    { A STATE KEY at its rest value [Batch 94]: added (and set) when the
      proxy has none yet, or when AForce; its rest value either way }
    procedure StSeed(const AKey: string; const AValue: TTyAnimValue; AForce: Boolean);
    { the rest value of a state key; False for none }
    function StRestOf(const AKey: string; out AValue: TTyAnimValue): Boolean;
    function HasStKey(const AKey: string): Boolean;
    property StKeys: TTyStringArray read FStKeys;
    { a full update's prevStates: the list clearStates took away, to be put
      back at once after the render (echarts.ts:2667-2748) }
    property StPrev: string read FStPrev write FStPrev;
    { a label's place under its select state, kept for the next update's
      move (LabelManager's oldLayoutSelect) }
    procedure StNoteSelect(AX, AY: Double);
    { the words now, while a count runs }
    property Text: string read FText;
    property HasText: Boolean read FHasText;
    property EndLabel: TTyChartAnimEndLabel read FEnd;
    property Series: Integer read FSeries;
    property Index: Integer read FIndex;
    property Role: string read FRole;
    property Final: TTyAnimProps read FFinal;
    property Leaving: Boolean read FLeaving;
    property Gone: Boolean read FGone;
    property Ghost: TTyChartElement read FGhost;
  end;

  TTyChartAnimProxyArray = array of TTyChartAnimProxy;

  { WHAT ARMING NEEDS TO KNOW OF ONE SERIES, by series index. }
  TTyChartAnimSeries = record
    Present: Boolean;
    Model: TTyAnimModel;
    { isAnimationEnabled: `animation` and the threshold }
    Enabled: Boolean;
    { seriesModel.get('animation') alone -- a line's symbols and their
      labels pop in above the threshold too }
    On_: Boolean;
    { a pie: animationType 'scale'; and the shared start angle of a first
      render, the first slice's that is a number }
    PieScale: Boolean;
    HasPieStart: Boolean;
    PieStart: Double;
    { LabelManager fades this series' labels in (the types this batch
      animates); label.valueAnimation turns the fade off }
    LabelFade: Boolean;
    LabelValueAnim: Boolean;
    { the base axis runs across the screen: a candle stands upright }
    BaseHoriz: Boolean;
    { ---- an update's view [Batch 90] ---- }
    SeriesType: string;
    { upstream's view id: 'i:' the series' id, else 'n:' its name and how
      many series before it carry that name, else 'x:' its index }
    ViewKey: string;
    { per view row: the DataDiffer key (getId) and the raw index }
    Keys: TTyStringArray;
    Raws: TTyIntegerArray;
    { a pie with animationTypeUpdate 'expansion': every render is its first
      (PieView never keeps its data) }
    PieExpandAlways: Boolean;
    { THE SERIES' MARKERS' models [Batch 92]: MarkerModel.isAnimationEnabled
      -- the marker's `animation` and the host's isAnimationEnabled -- is
      Present False when the host does not animate }
    MarkLine, MarkPoint: TTyAnimModel;
  end;
  TTyChartAnimSeriesArray = array of TTyChartAnimSeries;

  { where the NEW datum (x, y) sits in the OLD coordinate system of the
    series that was AOldSeries }
  TTyChartAnimToPoint = function(AOldSeries: Integer; AX, AY: Double): TTyPointF of object;

  { THE RENDER BEFORE AN UPDATE: its series by series index, the elements
    its list tagged, and its coordinate systems [Batch 90] }
  TTyChartAnimPrev = record
    Valid: Boolean;
    { A FULL UPDATE OF THE SAME OPTION (a legend toggle, a dataZoom)
      [Batch 96]: a series it no longer draws kept its view, whose remove()
      runs -- a bar fades, a line's or a scatter's symbols fade and shrink --
      where notMerge disposes the view (gone at once). Series then carry
      their models. }
    FullUpdate: Boolean;
    { A MERGE setOption [Batch 99, AN6]: the models it maps onto are the
      same ones, so their views are too -- a series' as a full update's, the
      markers' (component views) update instead of entering again }
    Merge: Boolean;
    { the views alive after the update: every series model of the new
      option, shown or not, as ViewKey + #1 + type (a brand new one's key
      'n:'-prefixed). An old view that is not among them was disposed --
      gone at once; one that is, but draws nothing, is remove()d. }
    AliveKeys: TTyStringArray;
    Series: TTyChartAnimSeriesArray;
    Elements: array of TTyChartElement;
    ToOldPoint: TTyChartAnimToPoint;
  end;

  TTyDataDiffKind = (ddkAdd, ddkUpdate, ddkRemove);
  TTyDataDiffCmd = record
    Kind: TTyDataDiffKind;
    NewIdx, OldIdx: Integer;
  end;
  TTyDataDiffCmdArray = array of TTyDataDiffCmd;

  TTyChartAnimSet = class
  private
    FItems: TFPList;
    FIndex: TFPHashList;
    FGhosts: TFPList;
    FAnimation: TTyAnimation;
    procedure NoOp;
    function Make(ASeries, AIndex: Integer; const ARole: string): TTyChartAnimProxy;
    procedure ArmOne(AList: TTyPaintList; AAt: Integer; const AEl: TTyChartElement;
      const AC: TTyChartAnimSeries; AUpdate: Boolean = False);
    procedure Unfollow(AProxy: TTyChartAnimProxy);
  public
    constructor Create(AAnimation: TTyAnimation);
    destructor Destroy; override;
    { every proxy freed, its clips taken off the driver }
    procedure Clear;
    function Count: Integer;
    function Item(AIndex: Integer): TTyChartAnimProxy;
    function Find(ASeries, AIndex: Integer; const ARole: string): TTyChartAnimProxy;
    { a proxy of the states' own, keyed as given [Batch 94] }
    function MakeState(ASeries, AIndex: Integer; const ARole: string): TTyChartAnimProxy;
    { The enter animation of everything in AList that asks for one and has
      no proxy yet, as upstream's views start it. ASeries by series index. }
    procedure Arm(AList: TTyPaintList; const ASeries: TTyChartAnimSeriesArray);
    { THE UPDATE [Batch 90]: AList is the new render, APrev the one before;
      the proxies of the old render are carried to their new rows, tweened,
      faded out or dropped as upstream's views do. }
    procedure ArmUpdate(AList: TTyPaintList; const ASeries: TTyChartAnimSeriesArray;
      const APrev: TTyChartAnimPrev);
    { the proxy each element reads, by insertion index; nil for none }
    function Bind(AList: TTyPaintList): TTyChartAnimProxyArray;
    { ---- the ghosts ---- }
    { free every ghost whose fade has ended (never inside the engine) }
    procedure Purge;
    function GhostCount: Integer;
    function Ghost(AIndex: Integer): TTyChartAnimProxy;
    { the ghost of row AIndex (the OLD row) of series ASeries, nil if none
      or gone }
    function FindGhost(ASeries, AIndex: Integer; const ARole: string): TTyChartAnimProxy;
    function LiveGhostCount: Integer;
  end;

{ The proxy a role reads: several roles share one (a line's run and area its
  clip, a candle's body and wicks, a progress arc and its end cap). }
function TyChartAnimProxyRole(ARole: TTyChartAnimRole): string;
{ ... and the key of one element's proxy: the role's, a ripple's with its
  number [Batch 92] }
function TyChartAnimRoleKey(const AEl: TTyChartElement): string;
{ interpolateRawValues for a number (util/model.ts): from `AFrom || 0` to
  ATo at APercent, rounded to the precision -- the larger of the two values'
  getPrecision unless one is given (AHasPrec) [Batch 92] }
function TyAnimInterpolateValue(AFrom, ATo, APercent: Double; AHasPrec: Boolean;
  APrec: Double): Double;
{ One element as its proxy says it is now. }
procedure TyAnimApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
{ ... and as its STATE proxy says [Batch 94]: every state key off its rest
  value drawn over the element; ARole: the proxy is also the element's role
  proxy, whose branch drew the keys it knows }
procedure TyAnimApplyState(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy;
  ARole: Boolean);
{ A markLine's numbers with its ends as AProxy has them now (shape.x1, y1,
  x2, y2 of Line.updateData's tween; the layout's where it has none):
  Line.beforeUpdate places the symbols and the label from them every frame
  [Batch 99, AN6] }
function TyAnimMarkLineG(const AEl: TTyChartElement; AProxy: TTyChartAnimProxy): TTyDoubleArray;
{ a packed colour as the state machine hands it to the engine: lifted (or
  not opaque) as zrender's rgba() string, else as '#rrggbb' }
function TyAnimColorValue(AColor: TTyChartColor; ALifted: Boolean): TTyAnimValue;
{ ADest := ASource with every bound element applied and every following label
  moved with its host, then every ghost still leaving. Insertion indices are
  kept, so a hit on the frame names the same element as a hit on the list
  (a ghost is silent). ASet may be nil. }
procedure TyAnimBuildFrame(ASource, ADest: TTyPaintList;
  const ABind: TTyChartAnimProxyArray; ASet: TTyChartAnimSet = nil;
  const AStBind: TTyChartAnimProxyArray = nil);
{ A shape scaled by (AFX, AFY) about (ACX, ACY). }
procedure TyShapeScaleAbout(var AShape: TTyChartShape; ACX, ACY, AFX, AFY: Double);
{ ... and moved by (ADX, ADY). }
procedure TyShapeMove(var AShape: TTyChartShape; ADX, ADY: Double);
{ The first APercent of a polyline's length, as zrender's strokePercent draws
  it (PathProxy.rebuildPath). }
function TyPolylinePrefix(const APoints: TTyPointFArray; APercent: Double): TTyPointFArray;
{ DataDiffer, one to one (data/DataDiffer.ts _executeOneToOne): the old
  rows in order -- an update with the first new row of the same key, else a
  remove -- then every new row left unmatched, in order, an add. }
function TyDataDiff(const AOld, ANew: TTyStringArray): TTyDataDiffCmdArray;
{ LineView's getBoundingDiff: the greatest of the four corner distances of
  the two point sets' extents (illegal points left out). }
function TyLineBoundingDiff(const A, B: TTyDoubleArray): Double;

implementation

uses tyControls.AdvChart.Labels, tyControls.AdvChart.Data, tyControls.AdvChart.Color,
  tyControls.AdvChart.LinePath, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.Scale, tyControls.AdvChart.MarkerView;

{ ==================== the proxy ==================== }

constructor TTyChartAnimProxy.Create(ASeries, AIndex: Integer; const ARole: string);
begin
  inherited Create;
  FSeries := ASeries;
  FIndex := AIndex;
  FRole := ARole;
end;

procedure TTyChartAnimProxy.SetFinal(const AProps: TTyAnimProps);
var i: Integer;
begin
  SetLength(FFinal, Length(AProps));
  for i := 0 to High(AProps) do
  begin
    FFinal[i].Key := AProps[i].Key;
    FFinal[i].Value := TyAnimClone(AProps[i].Value);
  end;
end;

function TTyChartAnimProxy.FinalOf(const AKey: string): TTyAnimValue;
var i: Integer;
begin
  for i := 0 to High(FFinal) do
    if FFinal[i].Key = AKey then Exit(TyAnimClone(FFinal[i].Value));
  Result := TyAnimNull;
end;

function SameBitsD(A, B: Double): Boolean;
var qa, qb: QWord;
begin
  Move(A, qa, SizeOf(qa));
  Move(B, qb, SizeOf(qb));
  Result := qa = qb;
end;

function TTyChartAnimProxy.AtFinal: Boolean;
var
  i, k: Integer;
  v: TTyAnimValue;
begin
  for i := 0 to High(FFinal) do
  begin
    v := GetAnimProp(FFinal[i].Key);
    if v.Kind <> FFinal[i].Value.Kind then Exit(False);
    case v.Kind of
      avkNumber, avkBool:
        if not SameBitsD(v.Num, FFinal[i].Value.Num) then Exit(False);
      avkArray:
        begin
          if Length(v.Arr) <> Length(FFinal[i].Value.Arr) then Exit(False);
          for k := 0 to High(v.Arr) do
            if not SameBitsD(v.Arr[k], FFinal[i].Value.Arr[k]) then Exit(False);
        end;
      avkString:
        if v.Str <> FFinal[i].Value.Str then Exit(False);
    end;
  end;
  Result := True;
end;

procedure TTyChartAnimProxy.StSeed(const AKey: string; const AValue: TTyAnimValue;
  AForce: Boolean);
var have: Boolean;
begin
  have := HasStKey(AKey);
  if not have then
  begin
    SetLength(FStKeys, Length(FStKeys) + 1);
    FStKeys[High(FStKeys)] := AKey;
  end;
  { a key a role's animation already holds keeps its value }
  if AForce or (not have and (GetAnimProp(AKey).Kind = avkNull)) then
    SetAnimProp(AKey, AValue);
  TyAnimPropPut(FStRest, AKey, AValue);
end;

function TTyChartAnimProxy.StRestOf(const AKey: string; out AValue: TTyAnimValue): Boolean;
var i: Integer;
begin
  i := TyAnimPropIndex(FStRest, AKey);
  Result := i >= 0;
  if Result then AValue := TyAnimClone(FStRest[i].Value) else AValue := TyAnimNull;
end;

procedure TTyChartAnimProxy.StNoteSelect(AX, AY: Double);
begin
  FStSelX := AX;
  FStSelY := AY;
  FStHasSel := True;
end;

function TTyChartAnimProxy.HasStKey(const AKey: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(FStKeys) do
    if FStKeys[i] = AKey then Exit(True);
  Result := False;
end;

procedure TTyChartAnimProxy.LeaveDone;
begin
  { upstream's doRemove: el.parent.remove(el). The set frees it later --
    this runs inside the engine's step. }
  FGone := True;
end;

procedure TTyChartAnimProxy.FollowDuring(APercent: Double);
var
  i, o: Integer;
  pts: TTyAnimValue;
begin
  { LineView._doUpdateAnimation: el.x = points[ptIdx * 2], el.y = ... --
    `__points`, which without a step is the very array `points` is }
  pts := GetAnimProp('shape.points');
  if pts.Kind <> avkArray then Exit;
  for i := 0 to High(FFollow) do
  begin
    o := FFollow[i].Pt * 2;
    if (FFollow[i].P = nil) or (o + 1 > High(pts.Arr)) then Continue;
    FFollow[i].P.SetNum('x', pts.Arr[o]);
    FFollow[i].P.SetNum('y', pts.Arr[o + 1]);
  end;
  if APercent < 0 then ;
end;

function TTyChartAnimProxy.FollowCount: Integer;
begin
  Result := Length(FFollow);
end;

function TyAnimInterpolateValue(AFrom, ATo, APercent: Double; AHasPrec: Boolean;
  APrec: Double): Double;
var
  s, v, p: Double;
  mask: TFPUExceptionMask;
begin
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    { `sourceValue || 0`: not a number, nought and minus nought are 0 }
    if IsNan(AFrom) or (AFrom = 0) then s := 0 else s := AFrom;
    { interpolateNumber: (p1 - p0) * percent + p0 }
    v := (ATo - s) * APercent + s;
    if AHasPrec then p := APrec
    else p := Max(TyGetPrecision(s), TyGetPrecision(ATo));
    Result := TyRoundP(v, p);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

procedure TTyChartAnimProxy.ValueDuring(APercent: Double);
var v: Double;
begin
  v := TyAnimInterpolateValue(FValFrom, FValTo, APercent, FValHasPrec, FValPrec);
  { interpolatedValue: null once it lands }
  FValHasInterp := APercent <> 1;
  FValInterp := v;
  FText := StringReplace(FValTpl, #1, TyJsNumberToString(v), [rfReplaceAll]);
  FHasText := True;
end;

function EndRowValue(const AE: TTyChartAnimEndLabel; ARow: Integer): Double;
begin
  if (ARow >= 0) and (ARow <= High(AE.Vals)) then Result := AE.Vals[ARow]
  else Result := NaN;
end;

procedure TTyChartAnimProxy.EndLabelDuring(APercent: Double);
var
  xOrY, dX, dY, v: Double;
  st: TTyEndLabelStep;
begin
  if not FEnd.Active then Exit;
  { the record: where the label was the first time a frame is not the last
    (the final place `during(1)` put it when the clip was made) }
  if (APercent < 1) and not FEnd.HasOriginal then
  begin
    FEnd.HasOriginal := True;
    FEnd.OriginalX := FEnd.X;
    FEnd.OriginalY := FEnd.Y;
  end;
  { the clip's leading edge }
  if FEnd.Inverse then
  begin
    if FEnd.Horiz then xOrY := Num('shape.x')
    else xOrY := Num('shape.y') + Num('shape.height');
  end
  else if FEnd.Horiz then xOrY := Num('shape.x') + Num('shape.width')
  else xOrY := Num('shape.y');
  if FEnd.Horiz then dX := FEnd.Distance else dX := 0;
  if FEnd.Horiz then dY := 0 else dY := -FEnd.Distance;
  if FEnd.Inverse then
  begin
    dX := dX * -1;
    dY := dY * -1;
  end;
  st := TyEndLabelStep(FEnd.Pts, FEnd.Cmds, xOrY, FEnd.Horiz, FEnd.ConnectNulls,
    APercent = 1, FEnd.LastFrameIndex);
  if st.HasPoint then
  begin
    FEnd.X := st.X + dX;
    FEnd.Y := st.Y + dY;
  end;
  { valueAnimation: setLabelText(the value there) }
  if FEnd.ValueAnim and (FEnd.Tpl <> '') then
  begin
    if st.Interp then
    begin
      if IsNan(EndRowValue(FEnd, st.Row1)) then Exit;
      v := TyAnimInterpolateValue(EndRowValue(FEnd, st.Row0),
        EndRowValue(FEnd, st.Row1), st.T, FEnd.HasPrec, FEnd.Prec);
    end
    else
    begin
      v := EndRowValue(FEnd, st.Row0);
      if IsNan(v) then Exit;
    end;
    FEnd.Text := StringReplace(FEnd.Tpl, #1, TyJsNumberToString(v), [rfReplaceAll]);
    FEnd.HasText := True;
  end;
end;

procedure TTyChartAnimProxy.EndLabelDone;
begin
  { createLineClipPath's done: back to the original place }
  if FEnd.Active and FEnd.HasOriginal then
  begin
    FEnd.X := FEnd.OriginalX;
    FEnd.Y := FEnd.OriginalY;
  end;
end;

{ ==================== the diff ==================== }

function TyDataDiff(const AOld, ANew: TTyStringArray): TTyDataDiffCmdArray;
var
  map: TFPHashList;
  lists: TFPList;
  i, j, n: Integer;
  l: TList;
  key: ShortString;

  procedure Push(AKind: TTyDataDiffKind; ANewIdx, AOldIdx: Integer);
  begin
    if n > High(Result) then SetLength(Result, n * 2 + 4);
    Result[n].Kind := AKind;
    Result[n].NewIdx := ANewIdx;
    Result[n].OldIdx := AOldIdx;
    Inc(n);
  end;

  function KeyOfS(const S: string): ShortString;
  var
    h: Cardinal;
    c: Integer;
  begin
    { '_ec_' + the key; a key too long for a hash-list name is cut and
      tagged with its length and an FNV-1a hash of the whole }
    if Length(S) <= 200 then Exit('_ec_' + S);
    h := 2166136261;
    {$PUSH}{$Q-}{$R-}
    for c := 1 to Length(S) do
      h := (h xor Ord(S[c])) * 16777619;
    {$POP}
    Result := '_ec_' + Copy(S, 1, 180) + '#' + IntToHex(Length(S), 8)
      + IntToHex(h, 8);
  end;

begin
  Result := nil;
  n := 0;
  map := TFPHashList.Create;
  lists := TFPList.Create;
  try
    { the new rows by key, in order: a key held twice is a list }
    for i := 0 to High(ANew) do
    begin
      key := KeyOfS(ANew[i]);
      l := TList(map.Find(key));
      if l = nil then
      begin
        l := TList.Create;
        lists.Add(l);
        map.Add(key, l);
      end;
      l.Add(Pointer(PtrInt(i)));
    end;
    for i := 0 to High(AOld) do
    begin
      l := TList(map.Find(KeyOfS(AOld[i])));
      if (l <> nil) and (l.Count > 0) then
      begin
        { the first left of the key: `shift()` on a list, the one itself }
        j := PtrInt(l[0]);
        l.Delete(0);
        Push(ddkUpdate, j, i);
      end
      else
        Push(ddkRemove, -1, i);
    end;
    { _performRestAdd: the new rows left, in order -- a key's list all at
      once, at its first row }
    for i := 0 to High(ANew) do
    begin
      l := TList(map.Find(KeyOfS(ANew[i])));
      if l = nil then Continue;
      for j := 0 to l.Count - 1 do Push(ddkAdd, PtrInt(l[j]), -1);
      l.Clear;
    end;
  finally
    for i := 0 to lists.Count - 1 do TList(lists[i]).Free;
    lists.Free;
    map.Free;
  end;
  SetLength(Result, n);
end;

function JsMaxOf(const A: array of Double): Double;
var i: Integer;
begin
  { Math.max: a not-a-number anywhere is the answer }
  Result := NegInfinity;
  for i := 0 to High(A) do
  begin
    if IsNan(A[i]) then Exit(NaN);
    if A[i] > Result then Result := A[i];
  end;
end;

procedure XYExtent(const P: TTyDoubleArray; out AX0, AX1, AY0, AY1: Double);
var
  i: Integer;
  x, y: Double;
begin
  AX0 := Infinity;
  AX1 := NegInfinity;
  AY0 := Infinity;
  AY1 := NegInfinity;
  i := 0;
  while i + 1 <= High(P) do
  begin
    x := P[i];
    y := P[i + 1];
    Inc(i, 2);
    { isPointIllegal: not finite }
    if IsNan(x) or IsNan(y) or IsInfinite(x) or IsInfinite(y) then Continue;
    if x < AX0 then AX0 := x;
    if x > AX1 then AX1 := x;
    if y < AY0 then AY0 := y;
    if y > AY1 then AY1 := y;
  end;
end;

function TyLineBoundingDiff(const A, B: TTyDoubleArray): Double;
var
  ax0, ax1, ay0, ay1, bx0, bx1, by0, by1: Double;
  mask: TFPUExceptionMask;
begin
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    XYExtent(A, ax0, ax1, ay0, ay1);
    XYExtent(B, bx0, bx1, by0, by1);
    { Infinity - Infinity is not a number, as in JavaScript }
    Result := JsMaxOf([Abs(ax0 - bx0), Abs(ay0 - by0), Abs(ax1 - bx1),
      Abs(ay1 - by1)]);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the set ==================== }

function KeyOf(ASeries, AIndex: Integer; const ARole: string): ShortString;
begin
  Result := IntToStr(ASeries) + ':' + IntToStr(AIndex) + ':' + ARole;
end;

constructor TTyChartAnimSet.Create(AAnimation: TTyAnimation);
begin
  inherited Create;
  FAnimation := AAnimation;
  FItems := TFPList.Create;
  FIndex := TFPHashList.Create;
  FGhosts := TFPList.Create;
end;

destructor TTyChartAnimSet.Destroy;
begin
  Clear;
  FGhosts.Free;
  FIndex.Free;
  FItems.Free;
  inherited Destroy;
end;

procedure TTyChartAnimSet.Clear;
var i: Integer;
begin
  { no step runs between these frees, so a polyline's followers may go in
    any order }
  for i := FGhosts.Count - 1 downto 0 do TObject(FGhosts[i]).Free;
  FGhosts.Clear;
  for i := FItems.Count - 1 downto 0 do TObject(FItems[i]).Free;
  FItems.Clear;
  FIndex.Clear;
end;

function TTyChartAnimSet.Count: Integer;
begin
  Result := FItems.Count;
end;

function TTyChartAnimSet.Item(AIndex: Integer): TTyChartAnimProxy;
begin
  Result := TTyChartAnimProxy(FItems[AIndex]);
end;

function TTyChartAnimSet.Find(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  Result := TTyChartAnimProxy(FIndex.Find(KeyOf(ASeries, AIndex, ARole)));
end;

function TTyChartAnimSet.MakeState(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  Result := Make(ASeries, AIndex, ARole);
end;

procedure TTyChartAnimSet.NoOp;
begin
  { the line clip's done: upstream passes one, and a done makes the
    animation forced -- every key a track, changed or not }
end;

function TTyChartAnimSet.Make(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  Result := TTyChartAnimProxy.Create(ASeries, AIndex, ARole);
  Result.Animation := FAnimation;
  FItems.Add(Result);
  FIndex.Add(KeyOf(ASeries, AIndex, ARole), Result);
end;

procedure TTyChartAnimSet.Unfollow(AProxy: TTyChartAnimProxy);
var
  i, k: Integer;
  p: TTyChartAnimProxy;
begin
  for i := 0 to FItems.Count - 1 do
  begin
    p := TTyChartAnimProxy(FItems[i]);
    for k := 0 to High(p.FFollow) do
      if p.FFollow[k].P = AProxy then p.FFollow[k].P := nil;
  end;
end;

procedure TTyChartAnimSet.Purge;
var
  i: Integer;
  g: TTyChartAnimProxy;
begin
  for i := FGhosts.Count - 1 downto 0 do
  begin
    g := TTyChartAnimProxy(FGhosts[i]);
    if not g.FGone then Continue;
    FGhosts.Delete(i);
    Unfollow(g);
    g.Free;
  end;
end;

function TTyChartAnimSet.GhostCount: Integer;
begin
  Result := FGhosts.Count;
end;

function TTyChartAnimSet.Ghost(AIndex: Integer): TTyChartAnimProxy;
begin
  Result := TTyChartAnimProxy(FGhosts[AIndex]);
end;

function TTyChartAnimSet.FindGhost(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
var
  i: Integer;
  g: TTyChartAnimProxy;
begin
  Result := nil;
  for i := 0 to FGhosts.Count - 1 do
  begin
    g := TTyChartAnimProxy(FGhosts[i]);
    if (g.FSeries = ASeries) and (g.FIndex = AIndex) and (g.FRole = ARole)
      and not g.FGone then Exit(g);
  end;
end;

function TTyChartAnimSet.LiveGhostCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to FGhosts.Count - 1 do
    if not TTyChartAnimProxy(FGhosts[i]).FGone then Inc(Result);
end;

function TyChartAnimProxyRole(ARole: TTyChartAnimRole): string;
begin
  case ARole of
    carBar: Result := 'bar';
    carSymbol: Result := 'symbol';
    carLineSymbol: Result := 'lineSymbol';
    carLineRun, carLineArea: Result := 'lineClip';
    carSector: Result := 'sector';
    carFunnel: Result := 'funnel';
    carGaugePointer: Result := 'gaugePointer';
    carGaugeProgress, carGaugeCap: Result := 'gaugeProgress';
    carRadarLine: Result := 'radarLine';
    carRadarArea: Result := 'radarArea';
    carCandleBody, carCandleWickHigh, carCandleWickLow: Result := 'candle';
    carLabel: Result := 'label';
    carGuide: Result := 'guide';
    carGaugeDetail: Result := 'gaugeDetail';
    carEffectSymbol: Result := 'effectSymbol';
    carRipple: Result := 'ripple';
    carMarkPoint, carMarkPointLabel: Result := 'markPoint';
    carMarkLine, carMarkLineFrom, carMarkLineTo, carMarkLineLabel: Result := 'markLine';
    carEndLabel: Result := 'lineClip';
  else
    Result := '';
  end;
end;

function TyChartAnimRoleKey(const AEl: TTyChartElement): string;
begin
  Result := TyChartAnimProxyRole(AEl.Anim.Role);
  if AEl.Anim.Role = carRipple then Result := Result + IntToStr(AEl.Anim.Sub);
end;

function KeyIndexOf(const AEl: TTyChartElement): Integer;
begin
  if AEl.Anim.Role in [carLineRun, carLineArea, carEndLabel] then Result := -1
  else Result := AEl.Anim.Index;
end;

function Num1(const AKey: string; AValue: Double): TTyAnimProp;
begin
  Result := TyAnimProp(AKey, TyAnimNum(AValue));
end;

{ A timing option as a number the way a line's symbols read it: a function
  called with null, a number as it is, anything else not one. }
function TimingNumber(const AV: TTyAnimOptValue; AIndex: Integer;
  AHasIndex: Boolean): Double;
var h: TTyAnimTimingHandler;
begin
  case AV.Kind of
    aokNumber, aokBool: Result := AV.Num;
    aokString: Result := TyJsToNumber(AV.Str);
    aokHandler:
      if TyChartFindAnimTiming(AV.Str, h) and Assigned(h) then
        Result := h(AIndex, AHasIndex)
      else
        Result := NaN;
  else
    Result := NaN;
  end;
end;

{ LineView._initSymbolLabelAnimation's delay for the symbol at AEl:
  G = [x, y, clip x, y, width, height, flags] -- flag 1 a clip, 2 a
  horizontal base axis, 4 an inverse one. }
function LineSymbolDelay(const AEl: TTyChartElement;
  const AC: TTyChartAnimSeries): Double;
var
  flags: Integer;
  start, stop, cur, ratio, dur, del: Double;
  durV, delV: TTyAnimOptValue;
  hasClip: Boolean;
begin
  flags := Round(AEl.Anim.G[6]);
  hasClip := (flags and 1) <> 0;
  { undefined === undefined: no clip is a ratio of nought }
  ratio := 0;
  if hasClip then
  begin
    if (flags and 2) <> 0 then
    begin
      start := AEl.Anim.G[2];
      stop := AEl.Anim.G[2] + AEl.Anim.G[4];
      cur := AEl.Anim.G[0];
    end
    else
    begin
      start := AEl.Anim.G[3] + AEl.Anim.G[5];
      stop := AEl.Anim.G[3];
      cur := AEl.Anim.G[1];
    end;
    if stop = start then ratio := 0
    else ratio := (cur - start) / (stop - start);
  end;
  if (flags and 4) <> 0 then ratio := 1 - ratio;
  { seriesDuration, a function called with null }
  durV := TyAnimGetShallow(AC.Model, 'animationDuration');
  dur := TimingNumber(durV, -1, False);
  { `animationDelay || 0` }
  delV := TyAnimGetShallow(AC.Model, 'animationDelay');
  if not TyAnimOptTruthy(delV) then
    Result := dur * ratio + 0
  else if delV.Kind = aokHandler then
    Result := TimingNumber(delV, AEl.Anim.Index, True)
  else
  begin
    del := TimingNumber(delV, -1, False);
    Result := dur * ratio + del;
  end;
end;

{ ---- each role's upstream props, from an element's tag ---- }

function BarProps(const AEl: TTyChartElement): TTyAnimProps;
begin
  Result := TyAnimProps([Num1('shape.x', AEl.Anim.G[0]),
    Num1('shape.y', AEl.Anim.G[1]), Num1('shape.width', AEl.Anim.G[2]),
    Num1('shape.height', AEl.Anim.G[3])]);
end;

function SectorProps(const AEl: TTyChartElement): TTyAnimProps;
begin
  Result := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]),
    Num1('shape.cy', AEl.Anim.G[1]), Num1('shape.r0', AEl.Anim.G[2]),
    Num1('shape.r', AEl.Anim.G[3]), Num1('shape.startAngle', AEl.Anim.G[4]),
    Num1('shape.endAngle', AEl.Anim.G[5]), Num1('shape.angle', AEl.Anim.G[6])]);
end;

{ a scatter symbol: the path's scale and opacity, the group's place }
function SymbolProps(const AEl: TTyChartElement): TTyAnimProps;
begin
  Result := TyAnimProps([Num1('scaleX', AEl.Anim.G[2]),
    Num1('scaleY', AEl.Anim.G[3]), Num1('style.opacity', AEl.Anim.G[4]),
    Num1('x', AEl.Anim.G[5]), Num1('y', AEl.Anim.G[6])]);
end;

{ the line's clip rect as the static layer draws it: widened by `clip:
  false` }
function ClipProps(const AEl: TTyChartElement): TTyAnimProps;
var
  x, y, w, h, ex: Double;
  flags: Integer;
begin
  x := AEl.Anim.G[0];
  y := AEl.Anim.G[1];
  w := AEl.Anim.G[2];
  h := AEl.Anim.G[3];
  ex := AEl.Anim.G[4];
  flags := Round(AEl.Anim.G[5]);
  if ex > 0 then
  begin
    if (flags and 2) <> 0 then
    begin
      y := y - ex;
      h := h + ex * 2;
    end
    else
    begin
      x := x - ex;
      w := w + ex * 2;
    end;
  end;
  Result := TyAnimProps([Num1('shape.x', x), Num1('shape.y', y),
    Num1('shape.width', w), Num1('shape.height', h)]);
end;

{ the radar's ring, closed: the line carries the closing point, the area
  does not }
function RadarRing(const AEl: TTyChartElement): TTyDoubleArray;
var
  pts: TTyPointFArray;
  n, k: Integer;
begin
  pts := AEl.Shape.Points;
  n := Length(pts);
  Result := nil;
  if n = 0 then Exit;
  if AEl.Anim.Role = carRadarLine then
  begin
    SetLength(Result, n * 2);
    for k := 0 to n - 1 do
    begin
      Result[k * 2] := pts[k].X;
      Result[k * 2 + 1] := pts[k].Y;
    end;
  end
  else
  begin
    SetLength(Result, (n + 1) * 2);
    for k := 0 to n - 1 do
    begin
      Result[k * 2] := pts[k].X;
      Result[k * 2 + 1] := pts[k].Y;
    end;
    Result[n * 2] := pts[0].X;
    Result[n * 2 + 1] := pts[0].Y;
  end;
end;

{ [low-high body end x2, the other end x2, highest, body top, lowest, body
  bottom] -- candlestickLayout.ts' ends }
function CandleRing(const AEl: TTyChartElement; ABaseHoriz: Boolean): TTyDoubleArray;
begin
  SetLength(Result, 16);
  if ABaseHoriz then
  begin
    Result[0] := AEl.Anim.G[6];  Result[1] := AEl.Anim.G[1];
    Result[2] := AEl.Anim.G[7];  Result[3] := AEl.Anim.G[1];
    Result[4] := AEl.Anim.G[7];  Result[5] := AEl.Anim.G[2];
    Result[6] := AEl.Anim.G[6];  Result[7] := AEl.Anim.G[2];
    Result[8] := AEl.Anim.G[5];  Result[9] := AEl.Anim.G[3];
    Result[10] := AEl.Anim.G[5]; Result[11] := AEl.Anim.G[1];
    Result[12] := AEl.Anim.G[5]; Result[13] := AEl.Anim.G[4];
    Result[14] := AEl.Anim.G[5]; Result[15] := AEl.Anim.G[2];
  end
  else
  begin
    Result[0] := AEl.Anim.G[1];  Result[1] := AEl.Anim.G[6];
    Result[2] := AEl.Anim.G[1];  Result[3] := AEl.Anim.G[7];
    Result[4] := AEl.Anim.G[2];  Result[5] := AEl.Anim.G[7];
    Result[6] := AEl.Anim.G[2];  Result[7] := AEl.Anim.G[6];
    Result[8] := AEl.Anim.G[3];  Result[9] := AEl.Anim.G[5];
    Result[10] := AEl.Anim.G[1]; Result[11] := AEl.Anim.G[5];
    Result[12] := AEl.Anim.G[4]; Result[13] := AEl.Anim.G[5];
    Result[14] := AEl.Anim.G[2]; Result[15] := AEl.Anim.G[5];
  end;
end;

{ the final values of AProps added to (or replacing) the proxy's }
procedure MergeFinal(AP: TTyChartAnimProxy; const AProps: TTyAnimProps);
var
  i, k: Integer;
  found: Boolean;
begin
  for i := 0 to High(AProps) do
  begin
    found := False;
    for k := 0 to High(AP.FFinal) do
      if AP.FFinal[k].Key = AProps[i].Key then
      begin
        AP.FFinal[k].Value := TyAnimClone(AProps[i].Value);
        found := True;
        Break;
      end;
    if not found then
    begin
      SetLength(AP.FFinal, Length(AP.FFinal) + 1);
      AP.FFinal[High(AP.FFinal)].Key := AProps[i].Key;
      AP.FFinal[High(AP.FFinal)].Value := TyAnimClone(AProps[i].Value);
    end;
  end;
end;

{ animateLabelValue: `text.percent = 0`, then initProps (no previous value)
  or updateProps to 1, the count as the during, at the row [Batch 92] }
procedure StartCount(AP: TTyChartAnimProxy; const AEl: TTyChartElement;
  AFrom: Double; AUpdate: Boolean; const AModel: TTyAnimModel; ARow: Integer);
var
  opts: TTyAnimCallOpts;
  props: TTyAnimProps;
begin
  AP.FValFrom := AFrom;
  AP.FValTo := AEl.Caption.ValNum;
  AP.FValTpl := AEl.Caption.ValTpl;
  AP.FValHasPrec := AEl.Caption.ValHasPrec;
  AP.FValPrec := AEl.Caption.ValPrec;
  props := TyAnimProps([TyAnimProp('percent', TyAnimNum(1))]);
  MergeFinal(AP, props);
  AP.SetNum('percent', 0);
  opts := TyAnimCallAt(ARow);
  opts.During := @AP.ValueDuring;
  if AUpdate then TyUpdateProps(AP, props, AModel, opts)
  else TyInitProps(AP, props, AModel, opts);
end;

{ EffectSymbol.startEffectAnimation for one ripple: two looping animators,
  `animate('', true).when(period, scale)` and `animateStyle(true)
  .when(period, {opacity: 0})`, both delayed -i / n * period + idx / count }
procedure StartRipple(AP: TTyChartAnimProxy; const AEl: TTyChartElement);
var period, half, delay: Double;
begin
  period := AEl.Anim.G[4];
  half := AEl.Anim.G[5] / 2;
  delay := -AEl.Anim.G[2] / AEl.Anim.G[3] * period + AEl.Anim.G[6];
  AP.Animate('', True).WhenWithKeys(period, ['scaleX', 'scaleY'],
    [TyAnimNum(half), TyAnimNum(half)]).Delay(delay).Start('');
  AP.Animate('style', True).WhenWithKeys(period, ['opacity'],
    [TyAnimNum(0)]).Delay(delay).Start('');
end;

{ a run's points as points }
function PtsOf(const A: TTyDoubleArray): TTyPointFArray;
var i: Integer;
begin
  SetLength(Result, Length(A) div 2);
  for i := 0 to High(Result) do Result[i] := TyPointF(A[i * 2], A[i * 2 + 1]);
end;

{ the series' end label in AList, if it has one }
function FindEndLabel(AList: TTyPaintList; ASeries: Integer;
  out AEl: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = carEndLabel)
      and (AList.Element(i).Anim.Series = ASeries) then
    begin
      AEl := AList.Element(i);
      Exit(True);
    end;
end;

{ the clip's end label record from the label's tag: G[0] the distance, G[1]
  flags (1 horizontal base, 2 inverse, 4 connectNulls, 8 valueAnimation, 16
  a precision), G[2] the precision, G[3] smooth; Pts / Vals / Mono }
procedure SetupEndLabel(AP: TTyChartAnimProxy; const AEnd: TTyChartElement);
var flags: Integer;
begin
  AP.FEnd := Default(TTyChartAnimEndLabel);
  flags := Round(AEnd.Anim.G[1]);
  AP.FEnd.Active := True;
  AP.FEnd.Pts := Copy(AEnd.Anim.Pts, 0, Length(AEnd.Anim.Pts));
  AP.FEnd.Vals := Copy(AEnd.Anim.Vals, 0, Length(AEnd.Anim.Vals));
  AP.FEnd.Horiz := (flags and 1) <> 0;
  AP.FEnd.Inverse := (flags and 2) <> 0;
  AP.FEnd.ConnectNulls := (flags and 4) <> 0;
  AP.FEnd.ValueAnim := (flags and 8) <> 0;
  AP.FEnd.HasPrec := (flags and 16) <> 0;
  AP.FEnd.Prec := AEnd.Anim.G[2];
  AP.FEnd.Distance := AEnd.Anim.G[0];
  AP.FEnd.Tpl := AEnd.Caption.ValTpl;
  AP.FEnd.Cmds := TyPolylinePath(PtsOf(AP.FEnd.Pts), AEnd.Anim.G[3],
    AEnd.Anim.Mono, AP.FEnd.ConnectNulls);
  AP.FEnd.X := AEnd.Caption.X;
  AP.FEnd.Y := AEnd.Caption.Y;
  AP.FEnd.Text := AEnd.Caption.Text;
end;

procedure TTyChartAnimSet.ArmOne(AList: TTyPaintList; AAt: Integer;
  const AEl: TTyChartElement; const AC: TTyChartAnimSeries; AUpdate: Boolean);
var
  p: TTyChartAnimProxy;
  props: TTyAnimProps;
  idx, k: Integer;
  opts: TTyAnimCallOpts;
  cfg: TTyAnimCfg;
  x, y, w, h, ex, half, delay: Double;
  flags: Integer;
  host, endEl: TTyChartElement;
  ring, from: TTyDoubleArray;

  procedure Start(const AProps: TTyAnimProps; const AOpts: TTyAnimCallOpts);
  begin
    TyInitProps(p, AProps, AC.Model, AOpts);
  end;

  { the radar's two, from one ring: polygon first, as RadarView adds them }
  procedure ArmRadar(const ARole: string; const ARing: TTyDoubleArray);
  var
    q: TTyChartAnimProxy;
    k: Integer;
  begin
    if Find(AEl.Anim.Series, idx, ARole) <> nil then Exit;
    if Length(ARing) = 0 then Exit;
    SetLength(from, Length(ARing));
    for k := 0 to Length(ARing) div 2 - 1 do
    begin
      from[k * 2] := AEl.Anim.G[0];
      from[k * 2 + 1] := AEl.Anim.G[1];
    end;
    q := Make(AEl.Anim.Series, idx, ARole);
    q.Attr(TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ARing, 2))]));
    q.SetFinal(TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ARing, 2))]));
    q.SetAnimProp('shape.points', TyAnimArr(from, 2));
    TyInitProps(q, TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ARing, 2))]),
      AC.Model, TyAnimCallAt(idx));
  end;

begin
  idx := KeyIndexOf(AEl);
  half := Pi / 2;
  case AEl.Anim.Role of
    carBar:
      begin
        p := Make(AEl.Anim.Series, idx, 'bar');
        props := BarProps(AEl);
        p.Attr(props);
        p.SetFinal(props);
        { the creator zeroes the length only for a series that animates }
        if AC.Enabled then
        begin
          if AEl.Anim.G[4] <> 0 then p.SetNum('shape.height', 0)
          else p.SetNum('shape.width', 0);
        end;
        Start(props, TyAnimCallAt(idx));
      end;
    carSymbol:
      begin
        p := Make(AEl.Anim.Series, idx, 'symbol');
        props := SymbolProps(AEl);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('scaleX', 0);
        p.SetNum('scaleY', 0);
        p.SetNum('style.opacity', 0);
        Start(TyAnimProps([props[0], props[1], props[2]]), TyAnimCallAt(idx));
      end;
    carLineSymbol:
      begin
        if not AC.On_ then Exit;
        p := Make(AEl.Anim.Series, idx, 'lineSymbol');
        props := TyAnimProps([Num1('scaleX', 1), Num1('scaleY', 1)]);
        p.SetFinal(props);
        p.Attr(TyAnimProps([Num1('scaleX', 0), Num1('scaleY', 0)]));
        { a raw animateTo: no easing, no scope }
        cfg := TyAnimCfg(200, LineSymbolDelay(AEl, AC), '');
        cfg.SetToFinal := True;
        p.AnimateTo(props, cfg);
      end;
    carLineRun, carLineArea:
      begin
        p := Make(AEl.Anim.Series, -1, 'lineClip');
        x := AEl.Anim.G[0];
        y := AEl.Anim.G[1];
        w := AEl.Anim.G[2];
        h := AEl.Anim.G[3];
        ex := AEl.Anim.G[4];
        flags := Round(AEl.Anim.G[5]);
        props := TyAnimProps([Num1('shape.x', x), Num1('shape.y', y),
          Num1('shape.width', w), Num1('shape.height', h)]);
        p.Attr(props);
        { the start rect: nothing of it along the base axis }
        if (flags and 2) <> 0 then
        begin
          if (flags and 4) <> 0 then p.SetNum('shape.x', x + w);
          p.SetNum('shape.width', 0);
        end
        else
        begin
          if (flags and 4) = 0 then p.SetNum('shape.y', y + h);
          p.SetNum('shape.height', 0);
        end;
        opts := TyAnimCallNoIndex;
        opts.Done := @NoOp;
        { THE END LABEL RIDES THE CLIP: its during and done [Batch 92] }
        if FindEndLabel(AList, AEl.Anim.Series, endEl) then
        begin
          SetupEndLabel(p, endEl);
          opts.During := @p.EndLabelDuring;
          opts.Done := @p.EndLabelDone;
        end;
        Start(props, opts);
        { `clip: false` widens across the base axis AFTER the call; what the
          static layer draws is the widened rect }
        if ex > 0 then
        begin
          if (flags and 2) <> 0 then
          begin
            p.SetNum('shape.y', p.Num('shape.y') - ex);
            p.SetNum('shape.height', p.Num('shape.height') + ex * 2);
          end
          else
          begin
            p.SetNum('shape.x', p.Num('shape.x') - ex);
            p.SetNum('shape.width', p.Num('shape.width') + ex * 2);
          end;
        end;
        p.SetFinal(ClipProps(AEl));
        { "Set to the final frame. To make sure label layout is right." }
        if p.FEnd.Active then p.EndLabelDuring(1);
      end;
    carSector:
      begin
        p := Make(AEl.Anim.Series, idx, 'sector');
        props := SectorProps(AEl);
        p.Attr(props);
        p.SetFinal(props);
        if AC.PieScale then
        begin
          p.SetNum('shape.r', AEl.Anim.G[2]);
          Start(TyAnimProps([Num1('shape.r', AEl.Anim.G[3])]), TyAnimCallAt(idx));
        end
        else if AUpdate then
        begin
          { a slice added in a later render: its end out of its own start,
            at UPDATE timing (PieView.ts:110-117) }
          p.SetNum('shape.endAngle', AEl.Anim.G[4]);
          TyUpdateProps(p, TyAnimProps([Num1('shape.endAngle', AEl.Anim.G[5])]),
            AC.Model, TyAnimCallAt(idx));
        end
        else if AC.HasPieStart then
        begin
          p.SetNum('shape.startAngle', AC.PieStart);
          p.SetNum('shape.endAngle', AC.PieStart);
          Start(TyAnimProps([Num1('shape.startAngle', AEl.Anim.G[4]),
            Num1('shape.endAngle', AEl.Anim.G[5])]), TyAnimCallAt(idx));
        end;
      end;
    carFunnel:
      begin
        p := Make(AEl.Anim.Series, idx, 'funnel');
        props := TyAnimProps([Num1('style.opacity', AEl.Style.Alpha)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('style.opacity', 0);
        Start(props, TyAnimCallAt(idx));
      end;
    carGaugePointer:
      begin
        p := Make(AEl.Anim.Series, idx, 'gaugePointer');
        props := TyAnimProps([Num1('rotation', -(AEl.Anim.G[2] + half))]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('rotation', -(AEl.Anim.G[3] + half));
        Start(props, TyAnimCallNoIndex);
      end;
    carGaugeProgress:
      begin
        p := Make(AEl.Anim.Series, idx, 'gaugeProgress');
        props := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]),
          Num1('shape.cy', AEl.Anim.G[1]), Num1('shape.r0', AEl.Anim.G[2]),
          Num1('shape.r', AEl.Anim.G[3]), Num1('shape.startAngle', AEl.Anim.G[4]),
          Num1('shape.endAngle', AEl.Anim.G[5])]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('shape.endAngle', AEl.Anim.G[4]);
        Start(TyAnimProps([Num1('shape.endAngle', AEl.Anim.G[5])]),
          TyAnimCallNoIndex);
      end;
    carRadarLine, carRadarArea:
      begin
        { the first of the pair met arms both, from its own ring }
        ring := RadarRing(AEl);
        if Length(ring) = 0 then Exit;
        ArmRadar('radarArea', ring);
        ArmRadar('radarLine', ring);
      end;
    carCandleBody, carCandleWickHigh, carCandleWickLow:
      begin
        p := Make(AEl.Anim.Series, idx, 'candle');
        ring := CandleRing(AEl, AC.BaseHoriz);
        from := Copy(ring, 0, 16);
        for k := 0 to 7 do
          if AC.BaseHoriz then from[k * 2 + 1] := AEl.Anim.G[0]
          else from[k * 2] := AEl.Anim.G[0];
        props := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ring, 2))]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetAnimProp('shape.points', TyAnimArr(from, 2));
        Start(props, TyAnimCallAt(idx));
      end;
    carLabel:
      begin
        host := Default(TTyChartElement);
        if (AEl.Anim.HostPlus1 > 0) and (AEl.Anim.HostPlus1 <= AList.Count) then
          host := AList.Element(AEl.Anim.HostPlus1 - 1);
        props := TyAnimProps([Num1('style.opacity', 1)]);
        { A BAR'S LABEL COUNTS instead of fading: from nothing, at enter
          timing and the row (LabelManager -> animateLabelValue) [Batch 92] }
        if AEl.Caption.ValAnim then
        begin
          if not AC.Enabled then Exit;
          p := Make(AEl.Anim.Series, idx, 'label');
          StartCount(p, AEl, NaN, False, AC.Model, idx);
          Exit;
        end;
        if host.Anim.Role = carLineSymbol then
        begin
          if AUpdate then
          begin
            { A NEW SYMBOL IN AN UPDATE is not popped in, and its label is
              LabelManager's: a plain fade at enter timing, the row's }
            if not AC.Enabled or AC.LabelValueAnim then Exit;
            p := Make(AEl.Anim.Series, idx, 'label');
            p.Attr(props);
            p.SetFinal(props);
            p.SetNum('style.opacity', 0);
            Start(props, TyAnimCallAt(idx));
            Exit;
          end;
          { the symbol's own: from 0 over 300 ms, the symbol's delay }
          if not AC.On_ then Exit;
          delay := LineSymbolDelay(host, AC);
          p := Make(AEl.Anim.Series, idx, 'label');
          p.Attr(props);
          p.SetFinal(props);
          cfg := TyAnimCfg(300, delay, '');
          p.AnimateFrom(TyAnimProps([Num1('style.opacity', 0)]), cfg);
          Exit;
        end;
        if not (AC.Enabled and AC.LabelFade) or AC.LabelValueAnim then Exit;
        p := Make(AEl.Anim.Series, idx, 'label');
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('style.opacity', 0);
        Start(props, TyAnimCallAt(idx));
      end;
    carGuide:
      begin
        if not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, idx, 'guide');
        props := TyAnimProps([Num1('style.strokePercent', 1)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('style.strokePercent', 0);
        Start(props, TyAnimCallNoIndex);
      end;
    carGaugeDetail:
      begin
        { GaugeView: `hasAnimation && animateLabelValue(...)`, from nothing
          on a first render, at the row [Batch 92] }
        if not (AEl.Caption.ValAnim and AC.Enabled) then Exit;
        p := Make(AEl.Anim.Series, idx, 'gaugeDetail');
        StartCount(p, AEl, NaN, False, AC.Model, idx);
      end;
    carMarkPoint:
      begin
        { SymbolDraw's new symbol on the MARKER's model }
        p := Make(AEl.Anim.Series, idx, 'markPoint');
        props := TyAnimProps([Num1('scaleX', AEl.Anim.G[2]),
          Num1('scaleY', AEl.Anim.G[3]), Num1('style.opacity', AEl.Anim.G[4])]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('scaleX', 0);
        p.SetNum('scaleY', 0);
        p.SetNum('style.opacity', 0);
        TyInitProps(p, props, AC.MarkPoint, TyAnimCallAt(idx));
      end;
    carMarkLine, carMarkLineFrom, carMarkLineTo, carMarkLineLabel:
      begin
        { Line.ts _createLine: `shape.percent = 0`, initProps to 1 on the
          marker's model, at the marker's data index }
        p := Make(AEl.Anim.Series, idx, 'markLine');
        props := TyAnimProps([Num1('shape.percent', 1)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('shape.percent', 0);
        TyInitProps(p, props, AC.MarkLine, TyAnimCallAt(idx));
      end;
    carEffectSymbol:
      begin
        p := Make(AEl.Anim.Series, idx, 'effectSymbol');
        props := SymbolProps(AEl);
        p.Attr(props);
        p.SetFinal(props);
        { THE CONSTRUCTOR'S updateData: scale and the style's opacity from 0,
          enter timing ... }
        p.SetNum('scaleX', 0);
        p.SetNum('scaleY', 0);
        p.SetNum('orphan.opacity', 0);
        Start(TyAnimProps([props[0], props[1], Num1('orphan.opacity', AEl.Anim.G[4])]),
          TyAnimCallAt(idx));
        { ... then EffectSymbol.updateData's: the scale again at UPDATE timing
          (its tracks stop the first's before they step), while
          _updateCommon's new style object leaves the opacity tween moving
          nothing that is drawn }
        TyUpdateProps(p, TyAnimProps([props[0], props[1]]), AC.Model, TyAnimCallAt(idx));
      end;
    carRipple:
      begin
        p := Make(AEl.Anim.Series, idx, TyChartAnimRoleKey(AEl));
        props := TyAnimProps([Num1('scaleX', 0.5), Num1('scaleY', 0.5),
          Num1('style.opacity', 1)]);
        p.Attr(props);
        p.SetFinal(props);
        StartRipple(p, AEl);
      end;
  end;
  if AAt < 0 then ;
end;

procedure TTyChartAnimSet.Arm(AList: TTyPaintList;
  const ASeries: TTyChartAnimSeriesArray);
var
  i, s: Integer;
  el: TTyChartElement;
  role: string;
begin
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if el.Anim.Role = carNone then Continue;
    { a cap is armed by its arc, which comes after it in the list }
    if el.Anim.Role = carGaugeCap then Continue;
    s := el.Anim.Series;
    if (s < 0) or (s > High(ASeries)) or not ASeries[s].Present then Continue;
    role := TyChartAnimRoleKey(el);
    if Find(s, KeyIndexOf(el), role) <> nil then Continue;
    { the end label is armed by its clip }
    if el.Anim.Role = carEndLabel then Continue;
    ArmOne(AList, i, el, ASeries[s]);
  end;
end;

function TTyChartAnimSet.Bind(AList: TTyPaintList): TTyChartAnimProxyArray;
var
  i: Integer;
  el: TTyChartElement;
begin
  Result := nil;
  if (AList = nil) or (FItems.Count = 0) then Exit;
  SetLength(Result, AList.Count);
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if el.Anim.Role = carNone then
      Result[i] := nil
    else
      Result[i] := Find(el.Anim.Series, KeyIndexOf(el), TyChartAnimRoleKey(el));
  end;
end;

{ ==================== the update [Batch 90] ==================== }

procedure TTyChartAnimSet.ArmUpdate(AList: TTyPaintList;
  const ASeries: TTyChartAnimSeriesArray; const APrev: TTyChartAnimPrev);
var
  oldItems: TFPList;
  oldIndex: TFPHashList;
  prevIdx: TFPHashList;
  oldOf: TTyIntegerArray;
  rowMap: array of TTyIntegerArray;
  diffs: array of TTyDataDiffCmdArray;
  upd: array of Boolean;
  i, s, o, q, r, k: Integer;
  el: TTyChartElement;
  role: string;
  p: TTyChartAnimProxy;
  done: Boolean;

  { an old element of old series AOld, row ARow, role ARole }
  function OldEl(AOld, ARow: Integer; const ARole: string;
    out AEl: TTyChartElement): Boolean;
  var v: Pointer;
  begin
    v := prevIdx.Find(KeyOf(AOld, ARow, ARole));
    Result := v <> nil;
    if Result then AEl := APrev.Elements[PtrInt(v) - 1]
    else AEl := Default(TTyChartElement);
  end;

  { the old proxy of (AOld, ARow, ARole), still unclaimed }
  function OldProxy(AOld, ARow: Integer; const ARole: string): TTyChartAnimProxy;
  begin
    Result := TTyChartAnimProxy(oldIndex.Find(KeyOf(AOld, ARow, ARole)));
    if (Result <> nil) and Result.FClaimed then Result := nil;
  end;

  { carried to the new render at (ASer, ARow) }
  procedure Carry(AP: TTyChartAnimProxy; ASer, ARow: Integer);
  begin
    AP.FClaimed := True;
    AP.FSeries := ASer;
    AP.FIndex := ARow;
    FItems.Add(AP);
    FIndex.Add(KeyOf(ASer, ARow, AP.FRole), AP);
  end;

  { the old proxy carried, or a new one standing where the old element was
    (AOldProps), or -- nothing of it before -- at ANewProps }
  function Take(AOld, AOldRow, ASer, ARow: Integer; const ARole: string;
    const AOldProps, ANewProps: TTyAnimProps; AHasOld: Boolean): TTyChartAnimProxy;
  begin
    Result := OldProxy(AOld, AOldRow, ARole);
    if Result <> nil then
    begin
      Carry(Result, ASer, ARow);
      Exit;
    end;
    Result := Make(ASer, ARow, ARole);
    if AHasOld then Result.Attr(AOldProps) else Result.Attr(ANewProps);
  end;

  { a key an older proxy was made without: its old element's value }
  procedure Ensure(AP: TTyChartAnimProxy; const AKey: string; AValue: Double);
  begin
    if AP.GetAnimProp(AKey).Kind = avkNull then AP.SetNum(AKey, AValue);
  end;

  { A COUNT IN AN UPDATE (animateLabelValue) [Batch 92]: nothing when the
    value is the previous one (a count in flight goes on); else from the
    interpolated value of a count in flight, or the previous value, at
    update timing -- enter timing from nothing when there was none }
  procedure CountOn(var AP: TTyChartAnimProxy; const AOldEl, AEl: TTyChartElement;
    ASer, ARow: Integer; const ARole: string; const AModel: TTyAnimModel);
  var from: Double;
  begin
    if AOldEl.Caption.ValHas and (not IsNan(AOldEl.Caption.ValNum))
      and (not IsNan(AEl.Caption.ValNum))
      and (AOldEl.Caption.ValNum = AEl.Caption.ValNum) then Exit;
    if AP = nil then AP := Make(ASer, ARow, ARole);
    if AP.FValHasInterp then from := AP.FValInterp
    else if AOldEl.Caption.ValHas then from := AOldEl.Caption.ValNum
    else from := NaN;
    StartCount(AP, AEl, from, AOldEl.Caption.ValHas, AModel, ARow);
  end;

  { LabelManager's oldLayout: x / y / rotation from where the last layout
    put the text, at update timing and the row [Batch 92] }
  procedure MoveLabel(var AP: TTyChartAnimProxy; const AOldEl, AEl: TTyChartElement;
    ASer, ARow: Integer; const AModel: TTyAnimModel);
  var
    props: TTyAnimProps;
    fx, fy: Double;
  begin
    props := TyAnimProps([Num1('x', AEl.Caption.X), Num1('y', AEl.Caption.Y),
      Num1('rotation', AEl.Caption.RotationRad)]);
    { the move starts where the old layout was -- or, under a select the
      render took away (prevStates), where the select state had put it,
      unless emphasis was there too: oldLayoutEmphasis is applied last
      (LabelManager.ts:565-576) [Batch 94] }
    fx := AOldEl.Caption.X;
    fy := AOldEl.Caption.Y;
    if (AP <> nil) and AP.FStHasSel and (Pos('select', AP.FStPrev) > 0) then
    begin
      fx := AP.FStSelX;
      fy := AP.FStSelY;
    end;
    if (AP <> nil) and (Pos('emphasis', AP.FStPrev) > 0) then
    begin
      fx := AOldEl.Caption.X;
      fy := AOldEl.Caption.Y;
    end;
    if AP = nil then AP := Make(ASer, ARow, 'label');
    AP.Attr(TyAnimProps([Num1('x', fx), Num1('y', fy),
      Num1('rotation', AOldEl.Caption.RotationRad)]));
    MergeFinal(AP, props);
    TyUpdateProps(AP, props, AModel, TyAnimCallAt(ARow));
  end;

  { a label line's points, flat }
  function GuidePoints(const AEl: TTyChartElement): TTyAnimValue;
  var
    a: TTyDoubleArray;
    k: Integer;
  begin
    SetLength(a, Length(AEl.Shape.Points) * 2);
    for k := 0 to High(AEl.Shape.Points) do
    begin
      a[k * 2] := AEl.Shape.Points[k].X;
      a[k * 2 + 1] := AEl.Shape.Points[k].Y;
    end;
    Result := TyAnimArr(a, 2);
  end;

  { ---- one element of an updated series ---- }
  procedure UpdateOne(AAt: Integer; const AEl: TTyChartElement;
    const AC: TTyChartAnimSeries; AOld, AOldRow: Integer);
  var
    props, oprops: TTyAnimProps;
    oe, host: TTyChartElement;
    hasOld, hadProxy: Boolean;
    ring, oring: TTyDoubleArray;
    a, rot: Double;
    q2: TTyChartAnimProxy;
    rk: string;
  begin
    case AEl.Anim.Role of
      carBar:
        begin
          if AOldRow < 0 then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          props := BarProps(AEl);
          hasOld := OldEl(AOld, AOldRow, 'bar', oe);
          hadProxy := OldProxy(AOld, AOldRow, 'bar') <> nil;
          if hasOld then oprops := BarProps(oe) else oprops := nil;
          p := Take(AOld, AOldRow, s, r, 'bar', oprops, props, hasOld);
          { NO OLD ELEMENT for a kept row (its value was not a number): the
            creator makes it with no length, and updateProps grows it }
          if (not hasOld) and (not hadProxy) and AC.Enabled then
          begin
            if AEl.Anim.G[4] <> 0 then p.SetNum('shape.height', 0)
            else p.SetNum('shape.width', 0);
          end;
          p.SetFinal(props);
          TyUpdateProps(p, props, AC.Model, TyAnimCallAt(r));
        end;
      carSymbol:
        begin
          hasOld := (AOldRow >= 0) and OldEl(AOld, AOldRow, 'symbol', oe);
          { added, or no symbol before: a new Symbol, which enters }
          if not hasOld then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          props := SymbolProps(AEl);
          p := Take(AOld, AOldRow, s, r, 'symbol', SymbolProps(oe), props, True);
          Ensure(p, 'x', oe.Anim.G[5]);
          Ensure(p, 'y', oe.Anim.G[6]);
          p.SetFinal(props);
          { _updateCommon sets the style: the opacity is there at once }
          p.SetNum('style.opacity', AEl.Anim.G[4]);
          { the path's scale at the row, then the group's place with none
            (Symbol.updateData, SymbolDraw.updateData) }
          TyUpdateProps(p, TyAnimProps([props[0], props[1]]), AC.Model, TyAnimCallAt(r));
          TyUpdateProps(p, TyAnimProps([props[3], props[4]]), AC.Model, TyAnimCallNoIndex);
        end;
      carLineSymbol:
        begin
          { symbolDraw.updateData with disableAnimation: a kept symbol is set
            to its new place, an added one appears there; the polyline's
            tween moves the kept ones afterwards }
          if AOldRow < 0 then Exit;
          props := TyAnimProps([Num1('scaleX', 1), Num1('scaleY', 1),
            Num1('x', AEl.Anim.G[0]), Num1('y', AEl.Anim.G[1])]);
          p := Take(AOld, AOldRow, s, r, 'lineSymbol', nil, props, False);
          Ensure(p, 'scaleX', 1);
          Ensure(p, 'scaleY', 1);
          p.SetNum('x', AEl.Anim.G[0]);
          p.SetNum('y', AEl.Anim.G[1]);
          p.SetFinal(props);
        end;
      carLineRun, carLineArea:
        begin
          { the clip: once a series, to the new rect at ENTER timing, no row
            (LineView.ts:772-783) }
          if Find(s, -1, 'lineClip') <> nil then Exit;
          props := ClipProps(AEl);
          hasOld := OldEl(AOld, -1, 'lineClip', oe);
          if hasOld then oprops := ClipProps(oe) else oprops := nil;
          p := Take(AOld, -1, s, -1, 'lineClip', oprops, props, hasOld);
          p.SetFinal(props);
          { no during in an update: the end label stands where it ends
            (createLineClipPath without animation, during(1)) [Batch 92] }
          p.FEnd.Active := False;
          TyInitProps(p, props, AC.Model, TyAnimCallNoIndex);
        end;
      carSector:
        begin
          if AOldRow < 0 then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          props := SectorProps(AEl);
          hasOld := OldEl(AOld, AOldRow, 'sector', oe);
          if hasOld then oprops := SectorProps(oe) else oprops := nil;
          p := Take(AOld, AOldRow, s, r, 'sector', oprops, props, hasOld);
          if hasOld then Ensure(p, 'shape.angle', oe.Anim.G[6]);
          p.SetFinal(props);
          { the whole sectorShape, at the NEW row (PieView.ts:120-125) }
          TyUpdateProps(p, props, AC.Model, TyAnimCallAt(r));
        end;
      carFunnel:
        begin
          if AOldRow < 0 then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          props := TyAnimProps([Num1('style.opacity', AEl.Style.Alpha)]);
          hasOld := OldEl(AOld, AOldRow, 'funnel', oe);
          if hasOld then oprops := TyAnimProps([Num1('style.opacity', oe.Style.Alpha)])
          else oprops := nil;
          p := Take(AOld, AOldRow, s, r, 'funnel', oprops, props, hasOld);
          p.SetFinal(props);
          TyUpdateProps(p, props, AC.Model, TyAnimCallAt(r));
        end;
      carGaugePointer:
        begin
          if AOldRow < 0 then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          { THE GAUGE IS REBUILT: a new pointer from the old one's rotation
            (GaugeView.ts:493-503), no row }
          props := TyAnimProps([Num1('rotation', -(AEl.Anim.G[2] + Pi / 2))]);
          q2 := TTyChartAnimProxy(oldIndex.Find(KeyOf(AOld, AOldRow, 'gaugePointer')));
          if q2 <> nil then rot := q2.Num('rotation')
          else if OldEl(AOld, AOldRow, 'gaugePointer', oe) then
            rot := -(oe.Anim.G[2] + Pi / 2)
          else
            rot := -(AEl.Anim.G[3] + Pi / 2);
          p := Make(s, r, 'gaugePointer');
          p.Attr(props);
          p.SetFinal(props);
          p.SetNum('rotation', rot);
          TyUpdateProps(p, props, AC.Model, TyAnimCallNoIndex);
        end;
      carGaugeProgress:
        begin
          if AOldRow < 0 then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          props := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]),
            Num1('shape.cy', AEl.Anim.G[1]), Num1('shape.r0', AEl.Anim.G[2]),
            Num1('shape.r', AEl.Anim.G[3]), Num1('shape.startAngle', AEl.Anim.G[4]),
            Num1('shape.endAngle', AEl.Anim.G[5])]);
          q2 := TTyChartAnimProxy(oldIndex.Find(KeyOf(AOld, AOldRow, 'gaugeProgress')));
          if q2 <> nil then a := q2.Num('shape.endAngle')
          else if OldEl(AOld, AOldRow, 'gaugeProgress', oe) then a := oe.Anim.G[5]
          else a := AEl.Anim.G[4];
          p := Make(s, r, 'gaugeProgress');
          p.Attr(props);
          p.SetFinal(props);
          p.SetNum('shape.endAngle', a);
          TyUpdateProps(p, TyAnimProps([props[5]]), AC.Model, TyAnimCallNoIndex);
        end;
      carRadarLine, carRadarArea:
        begin
          if AOldRow < 0 then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          { the pair, once, from the first met's ring; points, no row
            (RadarView.ts:164-171) }
          if Find(s, r, 'radarArea') <> nil then Exit;
          ring := RadarRing(AEl);
          if Length(ring) = 0 then Exit;
          props := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ring, 2))]);
          oring := nil;
          if OldEl(AOld, AOldRow, 'radarArea', oe) or OldEl(AOld, AOldRow, 'radarLine', oe) then
            oring := RadarRing(oe);
          if Length(oring) > 0 then
            oprops := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(oring, 2))])
          else oprops := nil;
          p := Take(AOld, AOldRow, s, r, 'radarArea', oprops, props, Length(oring) > 0);
          p.SetFinal(props);
          TyUpdateProps(p, props, AC.Model, TyAnimCallNoIndex);
          p := Take(AOld, AOldRow, s, r, 'radarLine', oprops, props, Length(oring) > 0);
          p.SetFinal(props);
          TyUpdateProps(p, props, AC.Model, TyAnimCallNoIndex);
        end;
      carCandleBody, carCandleWickHigh, carCandleWickLow:
        begin
          { one proxy for the three; an added candle is made final }
          if (AOldRow < 0) or (Find(s, r, 'candle') <> nil) then Exit;
          ring := CandleRing(AEl, AC.BaseHoriz);
          props := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ring, 2))]);
          hasOld := OldEl(AOld, AOldRow, 'candle', oe);
          if hasOld then
            oprops := TyAnimProps([TyAnimProp('shape.points',
              TyAnimArr(CandleRing(oe, AC.BaseHoriz), 2))])
          else oprops := nil;
          p := Take(AOld, AOldRow, s, r, 'candle', oprops, props, hasOld);
          p.SetFinal(props);
          TyUpdateProps(p, props, AC.Model, TyAnimCallAt(r));
        end;
      carLabel:
        begin
          { THE SAME TEXT when its host was there before: LabelManager has its
            old layout and starts no fade (the move from it is AN4's). A
            heatmap's labels are new every render. }
          if (AOldRow >= 0) and (AC.SeriesType <> 'heatmap') then
          begin
            host := Default(TTyChartElement);
            if (AEl.Anim.HostPlus1 > 0) and (AEl.Anim.HostPlus1 <= AList.Count) then
              host := AList.Element(AEl.Anim.HostPlus1 - 1);
            if OldEl(AOld, AOldRow, 'label', oe) then
            begin
              p := OldProxy(AOld, AOldRow, 'label');
              if p <> nil then Carry(p, s, r);
              { the count, or a pie's words from their old layout [Batch 92]
                -- and any label a labelLayout put at its own x / y, which
                LabelManager moves from its old layout the same way
                [Batch 103] }
              if AC.Enabled then
              begin
                if AEl.Caption.ValAnim then
                  CountOn(p, oe, AEl, s, r, 'label', AC.Model)
                else if (AEl.Anim.HostPlus1 = 0)
                  and ((AC.SeriesType = 'pie') or AEl.Caption.LmFree) then
                  MoveLabel(p, oe, AEl, s, r, AC.Model);
              end;
              Exit;
            end;
            { a kept LINE symbol's label is no new text either }
            if host.Anim.Role = carLineSymbol then Exit;
          end;
          ArmOne(AList, AAt, AEl, AC, True);
        end;
      carGuide:
        begin
          if (AOldRow >= 0) and OldEl(AOld, AOldRow, 'guide', oe) then
          begin
            p := OldProxy(AOld, AOldRow, 'guide');
            if p <> nil then Carry(p, s, r);
            { LabelManager: the line from its old points, no row [Batch 92] }
            if AC.Enabled and (Length(oe.Shape.Points) > 0) then
            begin
              if p = nil then p := Make(s, r, 'guide');
              p.SetAnimProp('shape.points', GuidePoints(oe));
              props := TyAnimProps([TyAnimProp('shape.points', GuidePoints(AEl))]);
              MergeFinal(p, props);
              TyUpdateProps(p, props, AC.Model, TyAnimCallNoIndex);
            end;
            Exit;
          end;
          ArmOne(AList, AAt, AEl, AC, True);
        end;
      carGaugeDetail:
        begin
          if (AOldRow < 0) or not OldEl(AOld, AOldRow, 'gaugeDetail', oe) then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          { the same Text, reused (GaugeView's diff): it counts on from the
            previous value [Batch 92] }
          p := OldProxy(AOld, AOldRow, 'gaugeDetail');
          if p <> nil then Carry(p, s, r);
          if AEl.Caption.ValAnim and AC.Enabled then
            CountOn(p, oe, AEl, s, r, 'gaugeDetail', AC.Model);
        end;
      { the markers go through UpdateMarker [Batch 99] }
      carEffectSymbol:
        begin
          hasOld := (AOldRow >= 0) and OldEl(AOld, AOldRow, 'effectSymbol', oe);
          if not hasOld then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          { as a scatter symbol's: the path's scale at the row, the group's
            place with none; the style set at once }
          props := SymbolProps(AEl);
          p := Take(AOld, AOldRow, s, r, 'effectSymbol', SymbolProps(oe), props, True);
          Ensure(p, 'x', oe.Anim.G[5]);
          Ensure(p, 'y', oe.Anim.G[6]);
          p.SetFinal(props);
          p.SetNum('style.opacity', AEl.Anim.G[4]);
          TyUpdateProps(p, TyAnimProps([props[0], props[1]]), AC.Model, TyAnimCallAt(r));
          TyUpdateProps(p, TyAnimProps([props[3], props[4]]), AC.Model, TyAnimCallNoIndex);
        end;
      carRipple:
        begin
          { THE RIPPLES RUN ON through an update, unless the symbol's type,
            the period, the scale or the number changed
            (updateEffectAnimation's DIFFICULT_PROPS): then they start over }
          rk := TyChartAnimRoleKey(AEl);
          if (AOldRow >= 0) and OldEl(AOld, AOldRow, rk, oe)
            and (oe.Anim.G[3] = AEl.Anim.G[3]) and (oe.Anim.G[4] = AEl.Anim.G[4])
            and (oe.Anim.G[5] = AEl.Anim.G[5]) and (oe.Anim.G[7] = AEl.Anim.G[7]) then
          begin
            p := OldProxy(AOld, AOldRow, rk);
            if p <> nil then
            begin
              Carry(p, s, r);
              Exit;
            end;
          end;
          ArmOne(AList, AAt, AEl, AC, True);
        end;
    end;
  end;

  { ---- a marker of a kept series [Batch 99, AN6] ----
    The marker views are components': a merge and a full update keep them
    (prepareView finds the same model), a notMerge makes new ones (probed:
    the markers enter again). A kept MarkPointView updates its SymbolDraw
    -- the symbol path's scale at the marker's row, the group's x / y with
    none, the style set at once (Symbol.updateData, SymbolDraw.updateData)
    -- and a kept MarkLineView its LineDraw: the line's ends at the row
    (Line.updateData), the symbols and the label following them every frame
    (Line.beforeUpdate). Both on the MARKER's model. Rows are paired by the
    marker's data index. }
  procedure UpdateMarker(AAt: Integer; const AEl: TTyChartElement;
    const AC: TTyChartAnimSeries; AOld, ARow: Integer);
  var
    props, oprops: TTyAnimProps;
    oe: TTyChartElement;
    rk: string;
  begin
    rk := TyChartAnimRoleKey(AEl);
    { once a marker: a markLine's four elements share a proxy, a markPoint's
      label rides its symbol's }
    if Find(s, ARow, rk) <> nil then Exit;
    if AEl.Anim.Role = carMarkPointLabel then Exit;
    if not (APrev.FullUpdate or APrev.Merge) or not OldEl(AOld, ARow, rk, oe) then
    begin
      ArmOne(AList, AAt, AEl, AC, True);
      Exit;
    end;
    if AEl.Anim.Role = carMarkPoint then
    begin
      props := TyAnimProps([Num1('scaleX', AEl.Anim.G[2]), Num1('scaleY', AEl.Anim.G[3]),
        Num1('style.opacity', AEl.Anim.G[4]), Num1('x', AEl.Anim.G[0]),
        Num1('y', AEl.Anim.G[1])]);
      oprops := TyAnimProps([Num1('scaleX', oe.Anim.G[2]), Num1('scaleY', oe.Anim.G[3]),
        Num1('style.opacity', oe.Anim.G[4]), Num1('x', oe.Anim.G[0]),
        Num1('y', oe.Anim.G[1])]);
      p := Take(AOld, ARow, s, ARow, 'markPoint', oprops, props, True);
      { an entering proxy was made without the group's place }
      Ensure(p, 'x', oe.Anim.G[0]);
      Ensure(p, 'y', oe.Anim.G[1]);
      p.SetFinal(props);
      p.SetNum('style.opacity', AEl.Anim.G[4]);
      TyUpdateProps(p, TyAnimProps([props[0], props[1]]), AC.MarkPoint, TyAnimCallAt(ARow));
      TyUpdateProps(p, TyAnimProps([props[3], props[4]]), AC.MarkPoint, TyAnimCallNoIndex);
      Exit;
    end;
    props := TyAnimProps([Num1('shape.x1', AEl.Anim.G[0]), Num1('shape.y1', AEl.Anim.G[1]),
      Num1('shape.x2', AEl.Anim.G[2]), Num1('shape.y2', AEl.Anim.G[3]),
      Num1('shape.percent', 1)]);
    oprops := TyAnimProps([Num1('shape.x1', oe.Anim.G[0]), Num1('shape.y1', oe.Anim.G[1]),
      Num1('shape.x2', oe.Anim.G[2]), Num1('shape.y2', oe.Anim.G[3]),
      Num1('shape.percent', 1)]);
    p := Take(AOld, ARow, s, ARow, 'markLine', oprops, props, True);
    Ensure(p, 'shape.x1', oe.Anim.G[0]);
    Ensure(p, 'shape.y1', oe.Anim.G[1]);
    Ensure(p, 'shape.x2', oe.Anim.G[2]);
    Ensure(p, 'shape.y2', oe.Anim.G[3]);
    p.SetFinal(props);
    TyUpdateProps(p, TyAnimProps([props[0], props[1], props[2], props[3]]), AC.MarkLine,
      TyAnimCallAt(ARow));
  end;

  { ---- the line: lineAnimationDiff and the tween of its points ---- }
  procedure UpdateLine(ASer, AOld: Integer; const AC: TTyChartAnimSeries);
  var
    nr, orr: TTyChartElement;
    hasN, hasO: Boolean;
    j, m, len, ni, oi, i2, idx2: Integer;
    oldPts, newPts, oldBase, newBase, vals: TTyDoubleArray;
    cur, nxt, curS, nxtS: TTyDoubleArray;
    raws, sorted, statNew: TTyIntegerArray;
    statEq: TTyBoolArray;
    sCur, sNxt, sCurS, sNxtS: TTyDoubleArray;
    sEq: TTyBoolArray;
    sNew: TTyIntegerArray;
    cx, cy, nx, ny, base, over, oldStart: Double;
    pt: TTyPointF;
    cmds: TTyDataDiffCmdArray;
    poly, area, sym: TTyChartAnimProxy;
    horiz: Boolean;

    function At(const A: TTyDoubleArray; AI: Integer): Double;
    begin
      { a typed array read past its end, or `false[i]`: undefined, NaN once
        stored }
      if (AI >= 0) and (AI <= High(A)) then Result := A[AI] else Result := NaN;
    end;

    procedure Push2(var A: TTyDoubleArray; var ALen: Integer; AX, AY: Double);
    begin
      if ALen + 2 > Length(A) then SetLength(A, ALen * 2 + 8);
      A[ALen] := AX;
      A[ALen + 1] := AY;
    end;

    function Same(const A, B: TTyDoubleArray; AHasA, AHasB: Boolean): Boolean;
    var z: Integer;
    begin
      { isPointsSame: `false` against `false` is the same (no length, no
        loop); a length differing is not; then item by item, !== }
      if (not AHasA) and (not AHasB) then Exit(True);
      if AHasA <> AHasB then Exit(False);
      if Length(A) <> Length(B) then Exit(False);
      for z := 0 to High(A) do
        if not (A[z] = B[z]) then Exit(False);
      Result := True;
    end;

  begin
    hasN := False;
    hasO := False;
    for j := 0 to AList.Count - 1 do
    begin
      nr := AList.Element(j);
      if (nr.Anim.Role in [carLineRun, carLineArea]) and (nr.Anim.Series = ASer)
        and (Length(nr.Anim.Pts) > 0) then
      begin
        hasN := True;
        Break;
      end;
    end;
    hasO := OldEl(AOld, -1, 'lineClip', orr) and (Length(orr.Anim.Pts) > 0);
    { NOTHING TO TWEEN without both polylines, or with the series' own
      `animation` off (setShape); a STEP line is set, not tweened (a
      deviation: its stepped points are not ported) }
    if not (hasN and hasO) then Exit;
    if not AC.On_ then Exit;
    if (nr.Anim.G[7] <> 0) or (orr.Anim.G[7] <> 0) then Exit;
    oldPts := orr.Anim.Pts;
    newPts := nr.Anim.Pts;
    oldBase := orr.Anim.Base;
    newBase := nr.Anim.Base;
    { UNCHANGED: the polyline is not touched, a tween in flight goes on }
    if Same(oldBase, newBase, oldBase <> nil, newBase <> nil)
      and Same(oldPts, newPts, True, True) then
    begin
      poly := OldProxy(AOld, -1, 'linePoly');
      if poly <> nil then Carry(poly, ASer, -1);
      area := OldProxy(AOld, -1, 'lineArea');
      if area <> nil then Carry(area, ASer, -1);
      Exit;
    end;
    horiz := (Round(nr.Anim.G[5]) and 2) <> 0;
    oldStart := orr.Anim.G[6];
    vals := nr.Anim.Vals;
    cmds := TyDataDiff(APrev.Series[AOld].Keys, AC.Keys);
    len := 0;
    m := 0;
    cur := nil;
    nxt := nil;
    curS := nil;
    nxtS := nil;
    SetLength(raws, Length(cmds));
    SetLength(statEq, Length(cmds));
    SetLength(statNew, Length(cmds));
    for j := 0 to High(cmds) do
    begin
      case cmds[j].Kind of
        ddkUpdate:
          begin
            oi := cmds[j].OldIdx * 2;
            ni := cmds[j].NewIdx * 2;
            cx := At(oldPts, oi);
            cy := At(oldPts, oi + 1);
            nx := At(newPts, ni);
            ny := At(newPts, ni + 1);
            { a previous point that was not a number: the next one }
            if IsNan(cx) or IsNan(cy) then
            begin
              cx := nx;
              cy := ny;
            end;
            Push2(cur, len, cx, cy);
            Push2(nxt, len, nx, ny);
            Push2(curS, len, At(oldBase, oi), At(oldBase, oi + 1));
            Push2(nxtS, len, At(newBase, ni), At(newBase, ni + 1));
            Inc(len, 2);
            raws[m] := AC.Raws[cmds[j].NewIdx];
            statEq[m] := True;
            statNew[m] := cmds[j].NewIdx;
            Inc(m);
          end;
        ddkAdd:
          begin
            ni := cmds[j].NewIdx;
            { WHERE THE NEW DATUM SITS IN THE OLD COORDINATES }
            if Assigned(APrev.ToOldPoint) then
              pt := APrev.ToOldPoint(AOld, At(vals, ni * 3), At(vals, ni * 3 + 1))
            else pt := TyPointF(NaN, NaN);
            Push2(cur, len, pt.X, pt.Y);
            Push2(nxt, len, At(newPts, ni * 2), At(newPts, ni * 2 + 1));
            { getStackedOnPoint on the old coordinates: the value stacked
              under, else the old value start; the base value the row's }
            over := At(vals, ni * 3 + 2);
            if IsNan(over) then over := oldStart;
            if horiz then base := At(vals, ni * 3) else base := At(vals, ni * 3 + 1);
            if Assigned(APrev.ToOldPoint) then
            begin
              if horiz then pt := APrev.ToOldPoint(AOld, base, over)
              else pt := APrev.ToOldPoint(AOld, over, base);
            end
            else pt := TyPointF(NaN, NaN);
            Push2(curS, len, pt.X, pt.Y);
            Push2(nxtS, len, At(newBase, ni * 2), At(newBase, ni * 2 + 1));
            Inc(len, 2);
            raws[m] := AC.Raws[ni];
            statEq[m] := False;
            statNew[m] := ni;
            Inc(m);
          end;
      end;
    end;
    { sorted by the new raw index }
    SetLength(sorted, m);
    for j := 0 to m - 1 do sorted[j] := j;
    for j := 1 to m - 1 do
    begin
      oi := sorted[j];
      i2 := j - 1;
      while (i2 >= 0) and (raws[sorted[i2]] > raws[oi]) do
      begin
        sorted[i2 + 1] := sorted[i2];
        Dec(i2);
      end;
      sorted[i2 + 1] := oi;
    end;
    { INTO FLOAT32 ARRAYS: every value stored rounds to a single }
    SetLength(sCur, len);
    SetLength(sNxt, len);
    SetLength(sCurS, len);
    SetLength(sNxtS, len);
    SetLength(sEq, m);
    SetLength(sNew, m);
    for j := 0 to m - 1 do
    begin
      idx2 := sorted[j] * 2;
      sCur[j * 2] := TyJsFround(cur[idx2]);
      sCur[j * 2 + 1] := TyJsFround(cur[idx2 + 1]);
      sNxt[j * 2] := TyJsFround(nxt[idx2]);
      sNxt[j * 2 + 1] := TyJsFround(nxt[idx2 + 1]);
      sCurS[j * 2] := TyJsFround(curS[idx2]);
      sCurS[j * 2 + 1] := TyJsFround(curS[idx2 + 1]);
      sNxtS[j * 2] := TyJsFround(nxtS[idx2]);
      sNxtS[j * 2 + 1] := TyJsFround(nxtS[idx2 + 1]);
      sEq[j] := statEq[sorted[j]];
      sNew[j] := statNew[sorted[j]];
    end;
    { DON'T TWEEN A DIFF THIS LARGE: set the line (LineView.ts:1358-1376) }
    if (TyLineBoundingDiff(sCur, sNxt) > 3000)
      or ((newBase <> nil) and (TyLineBoundingDiff(sCurS, sNxtS) > 3000)) then
      Exit;
    poly := OldProxy(AOld, -1, 'linePoly');
    if poly <> nil then Carry(poly, ASer, -1)
    else poly := Make(ASer, -1, 'linePoly');
    poly.SetAnimProp('shape.points', TyAnimArr(sCur, 0, True));
    poly.StopAnimation;
    poly.FFollow := nil;
    TyUpdateProps(poly, TyAnimProps([TyAnimProp('shape.points',
      TyAnimArr(sNxt, 0, True))]), AC.Model, TyAnimCallNoIndex);
    poly.SetFinal(TyAnimProps([TyAnimProp('shape.points', TyAnimArr(sNxt, 0, True))]));
    if newBase <> nil then
    begin
      area := OldProxy(AOld, -1, 'lineArea');
      if area <> nil then Carry(area, ASer, -1)
      else area := Make(ASer, -1, 'lineArea');
      area.SetAnimProp('shape.stackedOnPoints', TyAnimArr(sCurS, 0, True));
      area.StopAnimation;
      TyUpdateProps(area, TyAnimProps([TyAnimProp('shape.stackedOnPoints',
        TyAnimArr(sNxtS, 0, True))]), AC.Model, TyAnimCallNoIndex);
      area.SetFinal(TyAnimProps([TyAnimProp('shape.stackedOnPoints',
        TyAnimArr(sNxtS, 0, True))]));
    end;
    { THE KEPT SYMBOLS FOLLOW the points, by their place in the sorted list }
    for j := 0 to m - 1 do
      if sEq[j] then
      begin
        sym := Find(ASer, sNew[j], 'lineSymbol');
        if sym = nil then Continue;
        SetLength(poly.FFollow, Length(poly.FFollow) + 1);
        poly.FFollow[High(poly.FFollow)].P := sym;
        poly.FFollow[High(poly.FFollow)].Pt := j;
      end;
    if poly.AnimatorCount > 0 then poly.AnimatorAt(0).During(@poly.FollowDuring);
  end;

  { ---- a removed element: the ghost that fades ---- }
  procedure Leave(ASer, AOld, AOldRow: Integer; const AModel: TTyAnimModel);
  const
    cRoles: array[0..4] of string = ('bar', 'sector', 'funnel', 'symbol', 'lineSymbol');
  var
    j: Integer;
    oe: TTyChartElement;
    g: TTyChartAnimProxy;
    opts: TTyAnimCallOpts;
  begin
    for j := 0 to High(cRoles) do
    begin
      if not OldEl(AOld, AOldRow, cRoles[j], oe) then Continue;
      { the old proxy where it is the same element; a line symbol's proxy is
        its GROUP's, and what fades is its path }
      g := nil;
      if cRoles[j] <> 'lineSymbol' then g := OldProxy(AOld, AOldRow, cRoles[j]);
      if g <> nil then
        g.FClaimed := True
      else
      begin
        g := TTyChartAnimProxy.Create(ASer, AOldRow, cRoles[j]);
        g.Animation := FAnimation;
        if cRoles[j] = 'bar' then g.Attr(BarProps(oe))
        else if cRoles[j] = 'sector' then g.Attr(SectorProps(oe))
        else if cRoles[j] = 'symbol' then g.Attr(SymbolProps(oe))
        else if cRoles[j] = 'lineSymbol' then
          g.Attr(TyAnimProps([Num1('scaleX', oe.Anim.G[7]), Num1('scaleY', oe.Anim.G[8])]));
      end;
      g.FSeries := ASer;
      g.FIndex := AOldRow;
      g.FLeaving := True;
      { the old element as it was; ApplyGhost drops its words and its hit }
      g.FGhost := oe;
      g.FFinal := nil;
      FGhosts.Add(g);
      if g.GetAnimProp('style.opacity').Kind = avkNull then
        g.SetNum('style.opacity', oe.Style.Alpha);
      opts := TyAnimCallAt(AOldRow);
      opts.Done := @g.LeaveDone;
      if (cRoles[j] = 'symbol') or (cRoles[j] = 'lineSymbol') then
        { Symbol.fadeOut: the path's opacity and scale to nought }
        TyRemoveElement(g, TyAnimProps([Num1('style.opacity', 0), Num1('scaleX', 0),
          Num1('scaleY', 0)]), AModel, opts)
      else
        { removeElementWithFadeOut }
        TyFadeOutElement(g, AModel, AOldRow, True, @g.LeaveDone);
    end;
  end;

begin
  if AList = nil then Exit;
  Purge;
  oldItems := FItems;
  oldIndex := FIndex;
  FItems := TFPList.Create;
  FIndex := TFPHashList.Create;
  prevIdx := TFPHashList.Create;
  try
    for i := 0 to oldItems.Count - 1 do
      TTyChartAnimProxy(oldItems[i]).FClaimed := False;
    { the old elements by (series, row, proxy role): the first of each }
    for i := 0 to High(APrev.Elements) do
    begin
      el := APrev.Elements[i];
      role := TyChartAnimRoleKey(el);
      if role = '' then Continue;
      if prevIdx.Find(KeyOf(el.Anim.Series, KeyIndexOf(el), role)) = nil then
        prevIdx.Add(KeyOf(el.Anim.Series, KeyIndexOf(el), role), Pointer(PtrInt(i + 1)));
    end;
    { WHICH NEW SERIES KEEPS WHICH OLD VIEW: the same model id and type }
    SetLength(oldOf, Length(ASeries));
    SetLength(rowMap, Length(ASeries));
    SetLength(diffs, Length(ASeries));
    SetLength(upd, Length(ASeries));
    for s := 0 to High(ASeries) do
    begin
      oldOf[s] := -1;
      upd[s] := False;
      if not ASeries[s].Present then Continue;
      for o := 0 to High(APrev.Series) do
        if APrev.Series[o].Present and (APrev.Series[o].ViewKey = ASeries[s].ViewKey)
          and (APrev.Series[o].SeriesType = ASeries[s].SeriesType) then
        begin
          oldOf[s] := o;
          Break;
        end;
      if oldOf[s] < 0 then Continue;
      { a pie whose update type is 'expansion' never keeps its data }
      if ASeries[s].PieExpandAlways then Continue;
      upd[s] := True;
      diffs[s] := TyDataDiff(APrev.Series[oldOf[s]].Keys, ASeries[s].Keys);
      SetLength(rowMap[s], Length(ASeries[s].Keys));
      for k := 0 to High(rowMap[s]) do rowMap[s][k] := -1;
      for k := 0 to High(diffs[s]) do
        if diffs[s][k].Kind = ddkUpdate then
          rowMap[s][diffs[s][k].NewIdx] := diffs[s][k].OldIdx;
    end;

    { EVERY ELEMENT OF THE NEW RENDER, in list order }
    for i := 0 to AList.Count - 1 do
    begin
      el := AList.Element(i);
      if el.Anim.Role in [carNone, carGaugeCap] then Continue;
      s := el.Anim.Series;
      if (s < 0) or (s > High(ASeries)) or not ASeries[s].Present then Continue;
      role := TyChartAnimRoleKey(el);
      r := KeyIndexOf(el);
      { the end label is its clip's }
      if el.Anim.Role = carEndLabel then Continue;
      if not upd[s] then
      begin
        if Find(s, r, role) = nil then ArmOne(AList, i, el, ASeries[s]);
        Continue;
      end;
      { THE MARKERS, by their own data index [Batch 99] }
      if el.Anim.Role in [carMarkPoint, carMarkPointLabel, carMarkLine, carMarkLineFrom,
        carMarkLineTo, carMarkLineLabel] then
      begin
        UpdateMarker(i, el, ASeries[s], oldOf[s], r);
        Continue;
      end;
      if (el.Anim.Role in [carLineRun, carLineArea]) then q := -1
      else if (r >= 0) and (r <= High(rowMap[s])) then q := rowMap[s][r]
      else q := -1;
      { done once a key: a candle's three, a radar's two }
      done := (el.Anim.Role in [carCandleWickHigh, carCandleWickLow, carCandleBody,
        carRadarLine, carRadarArea]) and (Find(s, r, role) <> nil);
      if done then Continue;
      UpdateOne(i, el, ASeries[s], oldOf[s], q);
    end;
    { THE LINES, once their symbols are carried }
    for s := 0 to High(ASeries) do
      if upd[s] and (ASeries[s].SeriesType = 'line') then
        UpdateLine(s, oldOf[s], ASeries[s]);
    { THE REMOVED ROWS of every kept series leave }
    for s := 0 to High(ASeries) do
      if upd[s] then
        for k := 0 to High(diffs[s]) do
          if diffs[s][k].Kind = ddkRemove then
            Leave(s, oldOf[s], diffs[s][k].OldIdx, ASeries[s].Model);
    { A VIEW A FULL UPDATE NO LONGER RENDERS (the legend switched its series
      off) is remove()d, not disposed [Batch 96]: BarView._clear fades every
      bar when its model animates, a line's and a scatter's
      SymbolDraw.remove(true) fades and shrinks every symbol (the polyline
      goes at once), every other view empties at once }
    { [Batch 99] a merge's too, where the view lives on: its model is still
      there with the same id and type, and does not ask for a new view. A
      view whose model a replaceMerge removed, whose type changed, or whose
      model is brand new is disposed: gone at once }
    if APrev.FullUpdate or APrev.Merge then
      for o := 0 to High(APrev.Series) do
      begin
        if not APrev.Series[o].Present then Continue;
        done := False;
        for s := 0 to High(oldOf) do
          if oldOf[s] = o then done := True;
        if done then Continue;
        done := True;
        for k := 0 to High(APrev.AliveKeys) do
          if APrev.AliveKeys[k] = APrev.Series[o].ViewKey + #1 + APrev.Series[o].SeriesType then
            done := False;
        if done then Continue;
        role := APrev.Series[o].SeriesType;
        if (role <> 'bar') and (role <> 'line') and (role <> 'scatter') then Continue;
        if not TyAnimIsEnabled(APrev.Series[o].Model) then Continue;
        for k := 0 to High(APrev.Series[o].Keys) do
          Leave(o, o, k, APrev.Series[o].Model);
      end;
    { THE STATES' OWN PROXIES of a reused element go with it [Batch 96]: a
      line symbol's path, a line's polyline and area, the other types' own
      ('st:' roles, by raw index) -- upstream's element is the same one and
      keeps its state lists, so a held hover does not transition again }
    for i := 0 to oldItems.Count - 1 do
    begin
      p := TTyChartAnimProxy(oldItems[i]);
      if p.FClaimed or (Copy(p.FRole, 1, 3) <> 'st:') then Continue;
      for s := 0 to High(ASeries) do
      begin
        if (not upd[s]) or (oldOf[s] <> p.FSeries) then Continue;
        if p.FIndex < 0 then
        begin
          Carry(p, s, -1);
          Break;
        end;
        r := -1;
        for k := 0 to High(diffs[s]) do
          if (diffs[s][k].Kind = ddkUpdate)
            and (diffs[s][k].OldIdx <= High(APrev.Series[oldOf[s]].Raws))
            and (APrev.Series[oldOf[s]].Raws[diffs[s][k].OldIdx] = p.FIndex)
            and (diffs[s][k].NewIdx <= High(ASeries[s].Raws)) then
            r := ASeries[s].Raws[diffs[s][k].NewIdx];
        if r >= 0 then Carry(p, s, r);
        Break;
      end;
    end;
    { EVERYTHING ELSE OF THE OLD RENDER IS GONE AT ONCE }
    for i := 0 to oldItems.Count - 1 do
    begin
      p := TTyChartAnimProxy(oldItems[i]);
      if p.FClaimed then Continue;
      Unfollow(p);
      p.Free;
    end;
  finally
    prevIdx.Free;
    oldIndex.Free;
    oldItems.Free;
  end;
  Purge;
end;

{ ==================== geometry ==================== }

procedure TyShapeScaleAbout(var AShape: TTyChartShape; ACX, ACY, AFX, AFY: Double);
var
  i: Integer;
  f: Double;

  function SX(AV: Double): Double;
  begin
    Result := ACX + (AV - ACX) * AFX;
  end;

  function SY(AV: Double): Double;
  begin
    Result := ACY + (AV - ACY) * AFY;
  end;

begin
  f := Min(Abs(AFX), Abs(AFY));
  case AShape.Kind of
    cskRect, cskRoundRect, cskPath:
      begin
        AShape.Bounds := TyRectF(SX(AShape.Bounds.Left), SY(AShape.Bounds.Top),
          SX(AShape.Bounds.Right), SY(AShape.Bounds.Bottom));
        for i := 0 to 3 do AShape.Radii[i] := AShape.Radii[i] * f;
        AShape.RotCX := SX(AShape.RotCX);
        AShape.RotCY := SY(AShape.RotCY);
      end;
    cskCircle:
      begin
        AShape.CX := SX(AShape.CX);
        AShape.CY := SY(AShape.CY);
        if AFX = AFY then
          AShape.R1 := AShape.R1 * Abs(AFX)
        else
        begin
          AShape.Kind := cskEllipse;
          AShape.R0 := AShape.R1 * Abs(AFX);
          AShape.R1 := AShape.R1 * Abs(AFY);
        end;
      end;
    cskEllipse:
      begin
        AShape.CX := SX(AShape.CX);
        AShape.CY := SY(AShape.CY);
        AShape.R0 := AShape.R0 * Abs(AFX);
        AShape.R1 := AShape.R1 * Abs(AFY);
      end;
    cskSector:
      begin
        AShape.CX := SX(AShape.CX);
        AShape.CY := SY(AShape.CY);
        AShape.R0 := AShape.R0 * f;
        AShape.R1 := AShape.R1 * f;
        for i := 0 to 3 do AShape.SectorRadii[i] := AShape.SectorRadii[i] * f;
      end;
    cskPolyline, cskPolygon:
      begin
        AShape.Points := Copy(AShape.Points, 0, Length(AShape.Points));
        for i := 0 to High(AShape.Points) do
          AShape.Points[i] := TyPointF(SX(AShape.Points[i].X), SY(AShape.Points[i].Y));
        AShape.Cmds := Copy(AShape.Cmds, 0, Length(AShape.Cmds));
        for i := 0 to High(AShape.Cmds) do
        begin
          AShape.Cmds[i].X1 := SX(AShape.Cmds[i].X1);
          AShape.Cmds[i].Y1 := SY(AShape.Cmds[i].Y1);
          AShape.Cmds[i].X2 := SX(AShape.Cmds[i].X2);
          AShape.Cmds[i].Y2 := SY(AShape.Cmds[i].Y2);
          AShape.Cmds[i].X := SX(AShape.Cmds[i].X);
          AShape.Cmds[i].Y := SY(AShape.Cmds[i].Y);
        end;
        if AShape.HasCmdBounds then
          AShape.CmdBounds := TyRectF(SX(AShape.CmdBounds.Left),
            SY(AShape.CmdBounds.Top), SX(AShape.CmdBounds.Right),
            SY(AShape.CmdBounds.Bottom));
      end;
  end;
end;

procedure TyShapeMove(var AShape: TTyChartShape; ADX, ADY: Double);
var i: Integer;
begin
  if IsNan(ADX) or IsNan(ADY) or ((ADX = 0) and (ADY = 0)) then Exit;
  case AShape.Kind of
    cskRect, cskRoundRect, cskPath:
      begin
        AShape.Bounds := TyRectF(AShape.Bounds.Left + ADX, AShape.Bounds.Top + ADY,
          AShape.Bounds.Right + ADX, AShape.Bounds.Bottom + ADY);
        AShape.RotCX := AShape.RotCX + ADX;
        AShape.RotCY := AShape.RotCY + ADY;
      end;
    cskCircle, cskEllipse, cskSector:
      begin
        AShape.CX := AShape.CX + ADX;
        AShape.CY := AShape.CY + ADY;
      end;
    cskPolyline, cskPolygon:
      begin
        { copies first: the list shares its arrays with the frame }
        AShape.Points := Copy(AShape.Points, 0, Length(AShape.Points));
        for i := 0 to High(AShape.Points) do
          AShape.Points[i] := TyPointF(AShape.Points[i].X + ADX,
            AShape.Points[i].Y + ADY);
        AShape.Cmds := Copy(AShape.Cmds, 0, Length(AShape.Cmds));
        for i := 0 to High(AShape.Cmds) do
        begin
          AShape.Cmds[i].X1 := AShape.Cmds[i].X1 + ADX;
          AShape.Cmds[i].Y1 := AShape.Cmds[i].Y1 + ADY;
          AShape.Cmds[i].X2 := AShape.Cmds[i].X2 + ADX;
          AShape.Cmds[i].Y2 := AShape.Cmds[i].Y2 + ADY;
          AShape.Cmds[i].X := AShape.Cmds[i].X + ADX;
          AShape.Cmds[i].Y := AShape.Cmds[i].Y + ADY;
        end;
        if AShape.HasCmdBounds then
          AShape.CmdBounds := TyRectF(AShape.CmdBounds.Left + ADX,
            AShape.CmdBounds.Top + ADY, AShape.CmdBounds.Right + ADX,
            AShape.CmdBounds.Bottom + ADY);
      end;
  end;
end;

function TyPolylinePrefix(const APoints: TTyPointFArray; APercent: Double): TTyPointFArray;
var
  i, n: Integer;
  total, want, seg, acc, t: Double;
begin
  n := Length(APoints);
  if (APercent >= 1) or (n < 2) then Exit(Copy(APoints, 0, n));
  Result := nil;
  if not (APercent > 0) then Exit;
  total := 0;
  for i := 1 to n - 1 do
    total := total + Hypot(APoints[i].X - APoints[i - 1].X,
      APoints[i].Y - APoints[i - 1].Y);
  want := total * APercent;
  SetLength(Result, n);
  Result[0] := APoints[0];
  acc := 0;
  for i := 1 to n - 1 do
  begin
    seg := Hypot(APoints[i].X - APoints[i - 1].X, APoints[i].Y - APoints[i - 1].Y);
    if acc + seg >= want then
    begin
      if seg > 0 then t := (want - acc) / seg else t := 0;
      Result[i] := TyPointF(APoints[i - 1].X + (APoints[i].X - APoints[i - 1].X) * t,
        APoints[i - 1].Y + (APoints[i].Y - APoints[i - 1].Y) * t);
      SetLength(Result, i + 1);
      Exit;
    end;
    acc := acc + seg;
    Result[i] := APoints[i];
  end;
end;

{ Nothing of it drawn and nothing of it hit, in this frame. }
procedure MakeInkless(var AEl: TTyChartElement);
begin
  AEl.Style.HasFill := False;
  AEl.Style.StrokeWidthLogical := 0;
  AEl.Caption.Text := '';
  AEl.Silent := True;
end;

function SectorFrom(const AEl: TTyChartElement; P: TTyChartAnimProxy): TTyChartShape;
begin
  Result := TyShapeSector(P.Num('shape.cx'), P.Num('shape.cy'), P.Num('shape.r0'),
    P.Num('shape.r'), P.Num('shape.startAngle'), P.Num('shape.endAngle'));
  Result.SectorRadii := AEl.Shape.SectorRadii;
end;

{ a key the proxy holds, as a number; AOr where it holds none }
function NumOr(P: TTyChartAnimProxy; const AKey: string; AOr: Double): Double;
var v: TTyAnimValue;
begin
  v := P.GetAnimProp(AKey);
  if v.Kind in [avkNumber, avkBool] then Result := v.Num else Result := AOr;
end;

procedure BarFrom(var AEl: TTyChartElement; P: TTyChartAnimProxy);
var
  x, y, w, h: Double;
  r: TTyRectF;
  i: Integer;
  radii: array[0..3] of Double;
begin
  x := P.Num('shape.x');
  y := P.Num('shape.y');
  w := P.Num('shape.width');
  h := P.Num('shape.height');
  r := TyRectF(Min(x, x + w), Min(y, y + h), Max(x, x + w), Max(y, y + h));
  if AEl.Shape.Kind = cskRoundRect then
  begin
    for i := 0 to 3 do radii[i] := AEl.Shape.Radii[i];
    AEl.Shape := TyShapeRoundRect(r, radii);
  end
  else
    AEl.Shape := TyShapeRect(r);
end;

{ a symbol's place moved, its host box with it }
procedure MoveSymbol(var AEl: TTyChartElement; ADX, ADY: Double);
begin
  if IsNan(ADX) or IsNan(ADY) or ((ADX = 0) and (ADY = 0)) then Exit;
  TyShapeMove(AEl.Shape, ADX, ADY);
  if AEl.Caption.HasHostBox then
  begin
    AEl.Caption.HostBox.X := AEl.Caption.HostBox.X + ADX;
    AEl.Caption.HostBox.Y := AEl.Caption.HostBox.Y + ADY;
  end;
end;

{ a caption moved by (ADX, ADY), its box with it }
procedure MoveCaption(var AEl: TTyChartElement; ADX, ADY: Double);
begin
  if IsNan(ADX) or IsNan(ADY) or ((ADX = 0) and (ADY = 0)) then Exit;
  AEl.Caption.X := AEl.Caption.X + ADX;
  AEl.Caption.Y := AEl.Caption.Y + ADY;
  AEl.Shape.Bounds := TyRectF(AEl.Shape.Bounds.Left + ADX, AEl.Shape.Bounds.Top + ADY,
    AEl.Shape.Bounds.Right + ADX, AEl.Shape.Bounds.Bottom + ADY);
end;

{ the words of a count, where the caption is one run }
procedure ApplyText(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
begin
  if AProxy.FHasText and (Length(AEl.Caption.RtPieces) = 0) then
    AEl.Caption.Text := AProxy.FText;
end;

function TyAnimMarkLineG(const AEl: TTyChartElement; AProxy: TTyChartAnimProxy): TTyDoubleArray;
var k: Integer;
begin
  SetLength(Result, Length(AEl.Anim.G));
  for k := 0 to High(AEl.Anim.G) do Result[k] := AEl.Anim.G[k];
  if AProxy = nil then Exit;
  Result[0] := NumOr(AProxy, 'shape.x1', Result[0]);
  Result[1] := NumOr(AProxy, 'shape.y1', Result[1]);
  Result[2] := NumOr(AProxy, 'shape.x2', Result[2]);
  Result[3] := NumOr(AProxy, 'shape.y2', Result[3]);
end;

procedure TyAnimApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
var
  x, y, fx, fy, a, d, c, s, cx, cy, tx, ty, lx, ly, lx1, ly1, bw, bh: Double;
  r: TTyRectF;
  v: TTyAnimValue;
  i, n, ah, av, ah1, av1, flags: Integer;
  pts: TTyPointFArray;
  mg: TTyDoubleArray;
begin
  if (AProxy = nil) or AProxy.AtFinal then Exit;
  case AEl.Anim.Role of
    carBar:
      BarFrom(AEl, AProxy);
    carSymbol, carLineSymbol, carEffectSymbol:
      begin
        if AEl.Anim.Role in [carSymbol, carEffectSymbol] then
        begin
          if AEl.Anim.G[2] <> 0 then fx := AProxy.Num('scaleX') / AEl.Anim.G[2]
          else fx := 1;
          if AEl.Anim.G[3] <> 0 then fy := AProxy.Num('scaleY') / AEl.Anim.G[3]
          else fy := 1;
          { an effect symbol's opacity tween moves a style no one draws }
          if AEl.Anim.Role = carSymbol then
            AEl.Style.Alpha := AProxy.Num('style.opacity');
        end
        else
        begin
          fx := AProxy.Num('scaleX');
          fy := AProxy.Num('scaleY');
        end;
        if (fx = 0) or (fy = 0) or IsNan(fx) or IsNan(fy) then
        begin
          MakeInkless(AEl);
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], 0, 0);
        end
        else
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], fx, fy);
        if AEl.Caption.HasHostBox then
        begin
          AEl.Caption.HostBox.X := AEl.Anim.G[0] + (AEl.Caption.HostBox.X - AEl.Anim.G[0]) * fx;
          AEl.Caption.HostBox.Y := AEl.Anim.G[1] + (AEl.Caption.HostBox.Y - AEl.Anim.G[1]) * fy;
          AEl.Caption.HostBox.W := AEl.Caption.HostBox.W * fx;
          AEl.Caption.HostBox.H := AEl.Caption.HostBox.H * fy;
        end;
        { THE GROUP'S PLACE [Batch 90]: a scatter symbol's group moves on an
          update, a line symbol's follows its polyline }
        if AEl.Anim.Role in [carSymbol, carEffectSymbol] then
          MoveSymbol(AEl, NumOr(AProxy, 'x', AEl.Anim.G[5]) - AEl.Anim.G[5],
            NumOr(AProxy, 'y', AEl.Anim.G[6]) - AEl.Anim.G[6])
        else
          MoveSymbol(AEl, NumOr(AProxy, 'x', AEl.Anim.G[0]) - AEl.Anim.G[0],
            NumOr(AProxy, 'y', AEl.Anim.G[1]) - AEl.Anim.G[1]);
      end;
    carLineRun, carLineArea:
      begin
        x := AProxy.Num('shape.x');
        y := AProxy.Num('shape.y');
        AEl.HasClip := True;
        AEl.ClipRect := TyRectF(x, y, x + AProxy.Num('shape.width'),
          y + AProxy.Num('shape.height'));
      end;
    carSector, carGaugeProgress:
      AEl.Shape := SectorFrom(AEl, AProxy);
    carGaugeCap:
      begin
        a := AProxy.Num('shape.endAngle');
        AEl.Shape.CX := AEl.Anim.G[0] + Cos(a) * AEl.Anim.G[2];
        AEl.Shape.CY := AEl.Anim.G[1] + Sin(a) * AEl.Anim.G[2];
      end;
    carFunnel:
      AEl.Style.Alpha := AProxy.Num('style.opacity');
    carGaugePointer:
      begin
        { the needle's angle is upstream's rotation turned back: the static
          needle turned about the hub by the difference }
        a := -AProxy.Num('rotation') - Pi / 2;
        d := a - AEl.Anim.G[2];
        cx := AEl.Anim.G[0];
        cy := AEl.Anim.G[1];
        if AEl.Shape.Kind = cskPath then
          AEl.Shape.RotationRad := AEl.Shape.RotationRad + d
        else
        begin
          c := Cos(d);
          s := Sin(d);
          AEl.Shape.Points := Copy(AEl.Shape.Points, 0, Length(AEl.Shape.Points));
          for i := 0 to High(AEl.Shape.Points) do
          begin
            x := AEl.Shape.Points[i].X - cx;
            y := AEl.Shape.Points[i].Y - cy;
            AEl.Shape.Points[i] := TyPointF(cx + x * c - y * s, cy + x * s + y * c);
          end;
        end;
      end;
    carRadarLine, carRadarArea:
      begin
        v := AProxy.GetAnimProp('shape.points');
        n := Length(v.Arr) div 2;
        if AEl.Anim.Role = carRadarArea then Dec(n);
        if n < 0 then n := 0;
        SetLength(pts, n);
        for i := 0 to n - 1 do pts[i] := TyPointF(v.Arr[i * 2], v.Arr[i * 2 + 1]);
        AEl.Shape.Points := pts;
      end;
    carCandleBody, carCandleWickHigh, carCandleWickLow:
      begin
        v := AProxy.GetAnimProp('shape.points');
        if Length(v.Arr) < 16 then Exit;
        { UPRIGHT when the body's first two points differ across -- they
          share the value coordinate either way, the same at every frame }
        if v.Arr[0] <> v.Arr[2] then
        begin
          if AEl.Anim.Role = carCandleBody then
          begin
            r := TyRectF(v.Arr[0], Min(v.Arr[1], v.Arr[5]), v.Arr[2],
              Max(v.Arr[1], v.Arr[5]));
            if r.Bottom - r.Top < 1 then r.Bottom := r.Top + 1;
            AEl.Shape := TyShapeRect(r);
          end
          else if AEl.Anim.Role = carCandleWickHigh then
            AEl.Shape.Points := [TyPointF(v.Arr[8], v.Arr[9]),
              TyPointF(v.Arr[10], v.Arr[11])]
          else
            AEl.Shape.Points := [TyPointF(v.Arr[12], v.Arr[13]),
              TyPointF(v.Arr[14], v.Arr[15])];
        end
        else
        begin
          if AEl.Anim.Role = carCandleBody then
          begin
            r := TyRectF(Min(v.Arr[0], v.Arr[4]), v.Arr[1], Max(v.Arr[0], v.Arr[4]),
              v.Arr[3]);
            if r.Right - r.Left < 1 then r.Right := r.Left + 1;
            AEl.Shape := TyShapeRect(r);
          end
          else if AEl.Anim.Role = carCandleWickHigh then
            AEl.Shape.Points := [TyPointF(v.Arr[8], v.Arr[9]),
              TyPointF(v.Arr[10], v.Arr[11])]
          else
            AEl.Shape.Points := [TyPointF(v.Arr[12], v.Arr[13]),
              TyPointF(v.Arr[14], v.Arr[15])];
        end;
      end;
    carLabel:
      begin
        { a pie's words on their way from the old layout [Batch 92] }
        v := AProxy.GetAnimProp('x');
        if v.Kind = avkNumber then
        begin
          MoveCaption(AEl, AProxy.Num('x') - AEl.Caption.X,
            AProxy.Num('y') - AEl.Caption.Y);
          AEl.Caption.RotationRad := NumOr(AProxy, 'rotation', AEl.Caption.RotationRad);
        end;
        ApplyText(AEl, AProxy);
        a := NumOr(AProxy, 'style.opacity', 1);
        if a <= 0 then MakeInkless(AEl)
        else AEl.Style.Alpha := AEl.Style.Alpha * a;
      end;
    carGuide:
      begin
        { an update's line on its way from its old points [Batch 92] }
        v := AProxy.GetAnimProp('shape.points');
        if (v.Kind = avkArray) and (Length(v.Arr) >= 2) then
        begin
          SetLength(pts, Length(v.Arr) div 2);
          for i := 0 to High(pts) do pts[i] := TyPointF(v.Arr[i * 2], v.Arr[i * 2 + 1]);
          AEl.Shape.Points := pts;
        end;
        a := NumOr(AProxy, 'style.strokePercent', 1);
        AEl.Shape.Points := TyPolylinePrefix(AEl.Shape.Points, a);
        if Length(AEl.Shape.Points) < 2 then MakeInkless(AEl);
      end;
    carGaugeDetail:
      ApplyText(AEl, AProxy);
    carMarkPoint:
      begin
        if AEl.Anim.G[2] <> 0 then fx := AProxy.Num('scaleX') / AEl.Anim.G[2] else fx := 1;
        if AEl.Anim.G[3] <> 0 then fy := AProxy.Num('scaleY') / AEl.Anim.G[3] else fy := 1;
        a := AProxy.Num('style.opacity');
        if (fx = 0) or (fy = 0) or IsNan(fx) or IsNan(fy) or not (a > 0) then
          MakeInkless(AEl)
        else
        begin
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], fx, fy);
          AEl.Style.Alpha := Min(1.0, a);
          { the group's place, where a kept view moves it [Batch 99] }
          TyShapeMove(AEl.Shape, NumOr(AProxy, 'x', AEl.Anim.G[0]) - AEl.Anim.G[0],
            NumOr(AProxy, 'y', AEl.Anim.G[1]) - AEl.Anim.G[1]);
        end;
      end;
    carMarkPointLabel:
      { the symbol path's text goes with its group [Batch 99] }
      MoveCaption(AEl, NumOr(AProxy, 'x', AEl.Anim.G[0]) - AEl.Anim.G[0],
        NumOr(AProxy, 'y', AEl.Anim.G[1]) - AEl.Anim.G[1]);
    carMarkLine:
      begin
        { Line's buildPath at percent: the segment to x1 * (1 - p) + x2 * p
          -- of its ends as they are now [Batch 99] }
        a := AProxy.Num('shape.percent');
        mg := TyAnimMarkLineG(AEl, AProxy);
        if Length(AEl.Shape.Points) = 2 then
          AEl.Shape.Points := [
            TyPointF(AEl.Anim.G[4] + (mg[0] - AEl.Anim.G[0]),
              AEl.Anim.G[5] + (mg[1] - AEl.Anim.G[1])),
            TyPointF((AEl.Anim.G[4] + (mg[0] - AEl.Anim.G[0])) * (1 - a)
              + (AEl.Anim.G[6] + (mg[2] - AEl.Anim.G[2])) * a,
              (AEl.Anim.G[5] + (mg[1] - AEl.Anim.G[1])) * (1 - a)
              + (AEl.Anim.G[7] + (mg[3] - AEl.Anim.G[3])) * a)];
        if not (a > 0) then MakeInkless(AEl);
      end;
    carMarkLineFrom, carMarkLineTo:
      begin
        { Line.beforeUpdate: the end symbols at pointAt(0) and
          pointAt(percent), scaled by the percent -- of the ends now }
        a := AProxy.Num('shape.percent');
        mg := TyAnimMarkLineG(AEl, AProxy);
        if not (a > 0) then
          MakeInkless(AEl)
        else if AEl.Anim.Role = carMarkLineFrom then
        begin
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], a, a);
          TyShapeMove(AEl.Shape, mg[0] - AEl.Anim.G[0], mg[1] - AEl.Anim.G[1]);
        end
        else
        begin
          TyMkLineAt(mg, a, tx, ty, lx, ly, ah, av);
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[2], AEl.Anim.G[3], a, a);
          TyShapeMove(AEl.Shape, tx - AEl.Anim.G[2], ty - AEl.Anim.G[3]);
        end;
      end;
    carMarkLineLabel:
      begin
        { and the label, placed for the percent: moved by where it is now
          less where it rests, re-aligned where the author did not align it }
        a := AProxy.Num('shape.percent');
        mg := TyAnimMarkLineG(AEl, AProxy);
        TyMkLineAt(mg, a, tx, ty, lx, ly, ah, av);
        TyMkLineAt(AEl.Anim.G, 1, tx, ty, lx1, ly1, ah1, av1);
        flags := Round(AEl.Anim.G[9]);
        x := AEl.Caption.X + (lx - lx1);
        y := AEl.Caption.Y + (ly - ly1);
        if (ah >= 0) and ((flags and 1) = 0) then
          case ah of
            0: AEl.Caption.AnchorH := tahLeft;
            1: AEl.Caption.AnchorH := tahCentre;
          else
            AEl.Caption.AnchorH := tahRight;
          end;
        if (av >= 0) and ((flags and 2) = 0) then
          case av of
            0: AEl.Caption.AnchorV := tavTop;
            1: AEl.Caption.AnchorV := tavMiddle;
          else
            AEl.Caption.AnchorV := tavBottom;
          end;
        bw := AEl.Shape.Bounds.Right - AEl.Shape.Bounds.Left;
        bh := AEl.Shape.Bounds.Bottom - AEl.Shape.Bounds.Top;
        if not (IsNan(x) or IsNan(y)) then
        begin
          AEl.Caption.X := x;
          AEl.Caption.Y := y;
          if AEl.Caption.RotationRad = 0 then
            AEl.Shape := TyShapeRect(TyAnchorBox(x, y, bw, bh, AEl.Caption.AnchorH,
              AEl.Caption.AnchorV));
        end;
      end;
    carRipple:
      begin
        { scale over the ripple's rest of 0.5 about its centre, the stroke
          unscaled (strokeNoScale); the opacity over the static one }
        fx := AProxy.Num('scaleX') / 0.5;
        fy := AProxy.Num('scaleY') / 0.5;
        a := AProxy.Num('style.opacity');
        if (fx = 0) or (fy = 0) or IsNan(fx) or IsNan(fy) or not (a > 0) then
          MakeInkless(AEl)
        else
        begin
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], fx, fy);
          AEl.Style.Alpha := AEl.Style.Alpha * Min(1.0, a);
        end;
      end;
    carEndLabel:
      if AProxy.FEnd.Active then
      begin
        { the box by the difference, the anchor exactly where the during put
          it }
        MoveCaption(AEl, AProxy.FEnd.X - AEl.Caption.X, AProxy.FEnd.Y - AEl.Caption.Y);
        AEl.Caption.X := AProxy.FEnd.X;
        AEl.Caption.Y := AProxy.FEnd.Y;
        if AProxy.FEnd.HasText then AEl.Caption.Text := AProxy.FEnd.Text;
      end;
  end;
end;

function TyAnimColorValue(AColor: TTyChartColor; ALifted: Boolean): TTyAnimValue;
var a: Cardinal;
begin
  a := (AColor shr 24) and $FF;
  if ALifted or (a <> 255) then
    Result := TyAnimStr(TyAnimRgbaString((AColor shr 16) and $FF, (AColor shr 8) and $FF,
      AColor and $FF, a / 255))
  else
    Result := TyAnimStr('#' + LowerCase(IntToHex((AColor shr 16) and $FF, 2)
      + IntToHex((AColor shr 8) and $FF, 2) + IntToHex(AColor and $FF, 2)));
end;

{ a colour value as the canvas paints it: AOk False for null or 'none' }
function StColourOf(const AV: TTyAnimValue; out AColor: TTyChartColor): Boolean;
begin
  AColor := 0;
  Result := (AV.Kind = avkString) and not TyChartColorIsNone(AV.Str)
    and TyTryParseChartColor(AV.Str, AColor);
end;

{ the same value as far as the drawing goes: a colour by its parse }
function StSameValue(const A, B: TTyAnimValue): Boolean;
var ca, cb: TTyChartColor; oa, ob: Boolean;
begin
  if (A.Kind = avkString) or (B.Kind = avkString) then
  begin
    oa := StColourOf(A, ca);
    ob := StColourOf(B, cb);
    Exit((oa = ob) and (not oa or (ca = cb)));
  end;
  if A.Kind <> B.Kind then Exit(False);
  if A.Kind in [avkNumber, avkBool] then
    Exit(SameBitsD(A.Num, B.Num) or (IsNan(A.Num) and IsNan(B.Num)));
  Result := A.Kind = avkNull;
end;

procedure TyAnimApplyState(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy;
  ARole: Boolean);
var
  i: Integer;
  key: string;
  v, rest, vx, vy, rx, ry: TTyAnimValue;
  c: TTyChartColor;
  fx, fy, cx, cy: Double;
  b: TTyRectF;

  { the role's branch draws a key its proxy rests at a layout value of }
  function RoleHas(const AKey: string): Boolean;
  begin
    Result := ARole and (AProxy.FinalOf(AKey).Kind <> avkNull);
  end;

  function Off(const AKey: string; out AV, ARest: TTyAnimValue): Boolean;
  begin
    AV := AProxy.GetAnimProp(AKey);
    Result := AProxy.StRestOf(AKey, ARest) and not StSameValue(AV, ARest);
  end;

begin
  if AProxy = nil then Exit;
  for i := 0 to High(AProxy.FStKeys) do
  begin
    key := AProxy.FStKeys[i];
    if key = 'style.fill' then
    begin
      if RoleHas(key) or not Off(key, v, rest) then Continue;
      { a follower (a candle's wick) has no fill to change }
      if not AEl.Style.HasFill and (AEl.Style.FillGradient.Kind = cgkNone) then Continue;
      if StColourOf(v, c) then
      begin
        AEl.Style.HasFill := True;
        AEl.Style.FillColor := c;
        AEl.Style.FillGradient := Default(TTyChartGradient);
      end
      else
        AEl.Style.HasFill := False;
    end
    else if key = 'style.stroke' then
    begin
      if not Off(key, v, rest) then Continue;
      if StColourOf(v, c) then
      begin
        AEl.Style.StrokeColor := c;
        AEl.Style.StrokeGradient := Default(TTyChartGradient);
        if not (AEl.Style.StrokeWidthLogical > 0) then
          AEl.Style.StrokeWidthLogical := NumOr(AProxy, 'style.lineWidth', 1);
      end
      else
        AEl.Style.StrokeColor := 0;
    end
    else if key = 'style.lineWidth' then
    begin
      if not Off(key, v, rest) then Continue;
      if v.Kind = avkNumber then AEl.Style.StrokeWidthLogical := v.Num;
    end
    else if key = 'style.opacity' then
    begin
      if RoleHas(key) then Continue;
      if not Off(key, v, rest) or (v.Kind <> avkNumber) then Continue;
      { a label's is a factor over its own, as its fade's is }
      if AEl.Caption.FontSizeLogical > 0 then
        AEl.Style.Alpha := AEl.Style.Alpha * v.Num
      else
        AEl.Style.Alpha := v.Num;
    end
    else if key = 'x' then
    begin
      if RoleHas('x') or RoleHas('y') then Continue;
      vx := AProxy.GetAnimProp('x');
      vy := AProxy.GetAnimProp('y');
      if not (AProxy.StRestOf('x', rx) and AProxy.StRestOf('y', ry)) then Continue;
      if (vx.Kind <> avkNumber) or (vy.Kind <> avkNumber) then Continue;
      if (rx.Kind <> avkNumber) or (ry.Kind <> avkNumber) then Continue;
      if AEl.Caption.FontSizeLogical > 0 then
        { a label's x / y are its anchor }
        MoveCaption(AEl, vx.Num - AEl.Caption.X, vy.Num - AEl.Caption.Y)
      else
        TyShapeMove(AEl.Shape, vx.Num - rx.Num, vy.Num - ry.Num);
    end
    else if key = 'scaleX' then
    begin
      if RoleHas('scaleX') or RoleHas('scaleY') then Continue;
      vx := AProxy.GetAnimProp('scaleX');
      vy := AProxy.GetAnimProp('scaleY');
      if not (AProxy.StRestOf('scaleX', rx) and AProxy.StRestOf('scaleY', ry)) then Continue;
      if StSameValue(vx, rx) and StSameValue(vy, ry) then Continue;
      if (rx.Num = 0) or (ry.Num = 0) or IsNan(rx.Num) or IsNan(ry.Num) then Continue;
      fx := vx.Num / rx.Num;
      fy := vy.Num / ry.Num;
      { about the symbol's centre: a line symbol's point }
      if AEl.Anim.Role in [carLineSymbol, carSymbol, carEffectSymbol] then
      begin
        cx := AEl.Anim.G[0];
        cy := AEl.Anim.G[1];
      end
      else
      begin
        b := TyShapeBounds(AEl.Shape);
        cx := (b.Left + b.Right) / 2;
        cy := (b.Top + b.Bottom) / 2;
      end;
      if (fx = 0) or (fy = 0) or IsNan(fx) or IsNan(fy) then MakeInkless(AEl)
      else TyShapeScaleAbout(AEl.Shape, cx, cy, fx, fy);
    end
    else if key = 'shape.r' then
    begin
      if RoleHas(key) then Continue;
      if not Off(key, v, rest) or (v.Kind <> avkNumber) then Continue;
      if AEl.Shape.Kind = cskSector then AEl.Shape.R1 := v.Num;
    end;
  end;
end;

function PointsOf(const A: TTyDoubleArray): TTyPointFArray;
var i: Integer;
begin
  SetLength(Result, Length(A) div 2);
  for i := 0 to High(Result) do Result[i] := TyPointF(A[i * 2], A[i * 2 + 1]);
end;

{ A LINE'S RUN OR AREA DRAWN FROM ITS POLYLINE'S POINTS AS THEY ARE NOW
  [Batch 90]: upstream's buildPath over the whole series, cut into runs,
  this element's run taken. }
procedure ApplyLine(var AEl: TTyChartElement; APoly, AArea: TTyChartAnimProxy);
var
  pv, bv: TTyAnimValue;
  base: TTyDoubleArray;
  cmds: TTyPathCmdArray;
  runs: TTyPathCmdArray2;
  r: TTyXYWH;
  i: Integer;
begin
  if ((APoly = nil) or APoly.AtFinal) and ((AArea = nil) or AArea.AtFinal) then Exit;
  if APoly <> nil then pv := APoly.GetAnimProp('shape.points')
  else pv := TyAnimArr(AEl.Anim.Pts, 0, True);
  if pv.Kind <> avkArray then Exit;
  if AEl.Anim.Role = carLineRun then
    cmds := TyPolylinePath(PointsOf(pv.Arr), AEl.Anim.G[8], AEl.Anim.Mono,
      AEl.Anim.G[10] <> 0)
  else
  begin
    base := AEl.Anim.Base;
    if AArea <> nil then
    begin
      bv := AArea.GetAnimProp('shape.stackedOnPoints');
      if bv.Kind = avkArray then base := bv.Arr;
    end;
    cmds := TyPolygonPath(PointsOf(pv.Arr), PointsOf(base), AEl.Anim.G[8],
      AEl.Anim.G[9], AEl.Anim.Mono, AEl.Anim.G[10] <> 0);
  end;
  runs := TySplitRuns(cmds);
  if (AEl.Anim.Sub < 0) or (AEl.Anim.Sub > High(runs)) then
  begin
    MakeInkless(AEl);
    Exit;
  end;
  AEl.Shape.Cmds := runs[AEl.Anim.Sub];
  r := TyPathCmdsRect(AEl.Shape.Cmds);
  AEl.Shape.HasCmdBounds := True;
  AEl.Shape.CmdBounds := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
  { the vertices, for the hit test }
  SetLength(AEl.Shape.Points, Length(AEl.Shape.Cmds));
  for i := 0 to High(AEl.Shape.Cmds) do
    AEl.Shape.Points[i] := TyPointF(AEl.Shape.Cmds[i].X, AEl.Shape.Cmds[i].Y);
end;

{ A GHOST AS IT IS NOW: the old element under its leaving proxy }
procedure ApplyGhost(var AEl: TTyChartElement; G: TTyChartAnimProxy);
var
  fx, fy, op: Double;
begin
  AEl := G.FGhost;
  op := NumOr(G, 'style.opacity', AEl.Style.Alpha);
  case AEl.Anim.Role of
    carBar:
      if G.GetAnimProp('shape.x').Kind = avkNumber then BarFrom(AEl, G);
    carSector:
      if G.GetAnimProp('shape.cx').Kind = avkNumber then AEl.Shape := SectorFrom(AEl, G);
    carSymbol:
      begin
        if AEl.Anim.G[2] <> 0 then fx := NumOr(G, 'scaleX', AEl.Anim.G[2]) / AEl.Anim.G[2]
        else fx := 1;
        if AEl.Anim.G[3] <> 0 then fy := NumOr(G, 'scaleY', AEl.Anim.G[3]) / AEl.Anim.G[3]
        else fy := 1;
        if (fx = 0) or (fy = 0) or IsNan(fx) or IsNan(fy) then op := 0
        else TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], fx, fy);
        MoveSymbol(AEl, NumOr(G, 'x', AEl.Anim.G[5]) - AEl.Anim.G[5],
          NumOr(G, 'y', AEl.Anim.G[6]) - AEl.Anim.G[6]);
      end;
    carLineSymbol:
      begin
        if AEl.Anim.G[7] <> 0 then fx := NumOr(G, 'scaleX', AEl.Anim.G[7]) / AEl.Anim.G[7]
        else fx := 1;
        if AEl.Anim.G[8] <> 0 then fy := NumOr(G, 'scaleY', AEl.Anim.G[8]) / AEl.Anim.G[8]
        else fy := 1;
        if (fx = 0) or (fy = 0) or IsNan(fx) or IsNan(fy) then op := 0
        else TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], fx, fy);
      end;
  end;
  AEl.Style.Alpha := op;
  { THE LABEL WENT AT ONCE (removeElementWithFadeOut drops the text first),
    and nothing leaving is hit }
  AEl.Silent := True;
  AEl.Caption.Text := '';
  if not (op > 0) then MakeInkless(AEl);
end;

{ Where a following label's anchor is on a host as given. }
procedure AnchorOn(const AHost: TTyChartElement; const ALabel: TTyChartElement;
  out AX, AY: Double);
var
  b: TTyRectF;
  atX, atY: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  box: TTyXYWH;
begin
  if AHost.Caption.HasHostBox then
  begin
    box := AHost.Caption.HostBox;
    atX := ALabel.Anim.LabelAtX;
    atY := ALabel.Anim.LabelAtY;
    if ALabel.Anim.LabelAtXPct then atX := atX * box.W;
    if ALabel.Anim.LabelAtYPct then atY := atY * box.H;
    TyLabelAnchorXYWH(box, TTyLabelPosition(ALabel.Anim.LabelPos),
      ALabel.Anim.LabelDist, atX, atY, AX, AY, ah, av);
    Exit;
  end;
  b := TyShapeBounds(AHost.Shape);
  b.Left := b.Left - ALabel.Anim.LabelInflate;
  b.Top := b.Top - ALabel.Anim.LabelInflate;
  b.Right := b.Right + ALabel.Anim.LabelInflate;
  b.Bottom := b.Bottom + ALabel.Anim.LabelInflate;
  atX := ALabel.Anim.LabelAtX;
  atY := ALabel.Anim.LabelAtY;
  if ALabel.Anim.LabelAtXPct then atX := atX * (b.Right - b.Left);
  if ALabel.Anim.LabelAtYPct then atY := atY * (b.Bottom - b.Top);
  TyLabelAnchor(b, TTyLabelPosition(ALabel.Anim.LabelPos), ALabel.Anim.LabelDist,
    atX, atY, AX, AY, ah, av);
end;

procedure TyAnimBuildFrame(ASource, ADest: TTyPaintList;
  const ABind: TTyChartAnimProxyArray; ASet: TTyChartAnimSet;
  const AStBind: TTyChartAnimProxyArray);
var
  i, h: Integer;
  el, hostS, hostF: TTyChartElement;
  x0, y0, x1, y1, dx, dy: Double;
  moved: Boolean;
  g: TTyChartAnimProxy;
begin
  if (ASource = nil) or (ADest = nil) then Exit;
  ADest.Clear;
  for i := 0 to ASource.Count - 1 do
  begin
    el := ASource.Element(i);
    if (i <= High(ABind)) and (ABind[i] <> nil) then TyAnimApply(el, ABind[i]);
    { THE STATES [Batch 94] }
    if (i <= High(AStBind)) and (AStBind[i] <> nil) then
      TyAnimApplyState(el, AStBind[i], (i <= High(ABind)) and (ABind[i] = AStBind[i]));
    { A LINE'S POINTS IN AN UPDATE [Batch 90] }
    if (ASet <> nil) and (el.Anim.Role in [carLineRun, carLineArea]) then
      ApplyLine(el, ASet.Find(el.Anim.Series, -1, 'linePoly'),
        ASet.Find(el.Anim.Series, -1, 'lineArea'));
    { A RIPPLE IS IN ITS SYMBOL'S GROUP, and the group moves in an update
      [Batch 92] }
    if (ASet <> nil) and (el.Anim.Role = carRipple) then
    begin
      g := ASet.Find(el.Anim.Series, el.Anim.Index, 'effectSymbol');
      if (g <> nil) and not g.AtFinal then
        TyShapeMove(el.Shape, NumOr(g, 'x', el.Anim.G[8]) - el.Anim.G[8],
          NumOr(g, 'y', el.Anim.G[9]) - el.Anim.G[9]);
    end;
    h := el.Anim.HostPlus1 - 1;
    if (el.Anim.Role = carLabel) and (h >= 0) and (h < i)
      and (h <= High(ABind)) and (ABind[h] <> nil) and not ABind[h].AtFinal then
    begin
      hostS := ASource.Element(h);
      hostF := ADest.Element(h);
      AnchorOn(hostS, el, x0, y0);
      AnchorOn(hostF, el, x1, y1);
      dx := x1 - x0;
      dy := y1 - y0;
      moved := (not IsNan(dx)) and (not IsNan(dy)) and ((dx <> 0) or (dy <> 0));
      if moved then
      begin
        el.Caption.X := el.Caption.X + dx;
        el.Caption.Y := el.Caption.Y + dy;
        el.Shape.Bounds := TyRectF(el.Shape.Bounds.Left + dx, el.Shape.Bounds.Top + dy,
          el.Shape.Bounds.Right + dx, el.Shape.Bounds.Bottom + dy);
      end;
    end;
    ADest.Add(el);
  end;
  { THE GHOSTS, after the list: silent, so a hit never lands on one }
  if ASet <> nil then
    for i := 0 to ASet.GhostCount - 1 do
    begin
      g := ASet.Ghost(i);
      if g.Gone then Continue;
      ApplyGhost(el, g);
      ADest.Add(el);
    end;
end;

end.
