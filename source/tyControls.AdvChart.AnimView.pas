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
  during). }
interface
uses SysUtils, Classes, Math, contnrs,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Anim,
  tyControls.AdvChart.AnimOpt;

type
  TTyChartAnimProxy = class;

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
  end;
  TTyChartAnimSeriesArray = array of TTyChartAnimSeries;

  { where the NEW datum (x, y) sits in the OLD coordinate system of the
    series that was AOldSeries }
  TTyChartAnimToPoint = function(AOldSeries: Integer; AX, AY: Double): TTyPointF of object;

  { THE RENDER BEFORE AN UPDATE: its series by series index, the elements
    its list tagged, and its coordinate systems [Batch 90] }
  TTyChartAnimPrev = record
    Valid: Boolean;
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
{ One element as its proxy says it is now. }
procedure TyAnimApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
{ ADest := ASource with every bound element applied and every following label
  moved with its host, then every ghost still leaving. Insertion indices are
  kept, so a hit on the frame names the same element as a hit on the list
  (a ghost is silent). ASet may be nil. }
procedure TyAnimBuildFrame(ASource, ADest: TTyPaintList;
  const ABind: TTyChartAnimProxyArray; ASet: TTyChartAnimSet = nil);
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

uses tyControls.AdvChart.Labels, tyControls.AdvChart.Data,
  tyControls.AdvChart.LinePath, tyControls.AdvChart.JsMath;

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
  else
    Result := '';
  end;
end;

function KeyIndexOf(const AEl: TTyChartElement): Integer;
begin
  if AEl.Anim.Role in [carLineRun, carLineArea] then Result := -1
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
  host: TTyChartElement;
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
    role := TyChartAnimProxyRole(el.Anim.Role);
    if Find(s, KeyIndexOf(el), role) <> nil then Continue;
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
      Result[i] := Find(el.Anim.Series, KeyIndexOf(el),
        TyChartAnimProxyRole(el.Anim.Role));
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
            Exit;
          end;
          ArmOne(AList, AAt, AEl, AC, True);
        end;
    end;
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
      role := TyChartAnimProxyRole(el.Anim.Role);
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
      role := TyChartAnimProxyRole(el.Anim.Role);
      r := KeyIndexOf(el);
      if not upd[s] then
      begin
        if Find(s, r, role) = nil then ArmOne(AList, i, el, ASeries[s]);
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

procedure TyAnimApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
var
  x, y, fx, fy, a, d, c, s, cx, cy: Double;
  r: TTyRectF;
  v: TTyAnimValue;
  i, n: Integer;
  pts: TTyPointFArray;
begin
  if (AProxy = nil) or AProxy.AtFinal then Exit;
  case AEl.Anim.Role of
    carBar:
      BarFrom(AEl, AProxy);
    carSymbol, carLineSymbol:
      begin
        if AEl.Anim.Role = carSymbol then
        begin
          if AEl.Anim.G[2] <> 0 then fx := AProxy.Num('scaleX') / AEl.Anim.G[2]
          else fx := 1;
          if AEl.Anim.G[3] <> 0 then fy := AProxy.Num('scaleY') / AEl.Anim.G[3]
          else fy := 1;
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
        if AEl.Anim.Role = carSymbol then
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
        a := AProxy.Num('style.opacity');
        if a <= 0 then MakeInkless(AEl)
        else AEl.Style.Alpha := AEl.Style.Alpha * a;
      end;
    carGuide:
      begin
        a := AProxy.Num('style.strokePercent');
        AEl.Shape.Points := TyPolylinePrefix(AEl.Shape.Points, a);
        if Length(AEl.Shape.Points) < 2 then MakeInkless(AEl);
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
  const ABind: TTyChartAnimProxyArray; ASet: TTyChartAnimSet);
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
    { A LINE'S POINTS IN AN UPDATE [Batch 90] }
    if (ASet <> nil) and (el.Anim.Role in [carLineRun, carLineArea]) then
      ApplyLine(el, ASet.Find(el.Anim.Series, -1, 'linePoly'),
        ASet.Find(el.Anim.Series, -1, 'lineArea'));
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
