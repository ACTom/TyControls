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
    riverClip    a themeRiver layer's clip rect [Batch 118]: from x - 10,
                 y - 10, width 0, height + 20 of the polygon's own rect, to
                 x - 50 and width + 100, enter timing with no row, only for
                 a series that animates; gone when it ends
                 (ThemeRiverView.ts createGridClipShape)
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
    boxplot      shape.points: the fourteen points' value coordinates out of
                 the median's, at the row (BoxplotView.ts:59-75, 191-235)
                 [Batch 108]
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

  A BAR RACE [Batch 135]. A bar series with realtimeSort on a category base
  axis of a cartesian2d (BarView.updateRealtimeAnimation) splits its shape
  in two: the length (y / height on a horizontal base axis, x / width on a
  vertical one) on the SERIES' timing, the place along the base axis
  (x / width, or y / height) on the BASE AXIS model's -- both at the row,
  initProps for a new bar and updateProps for a kept one, the axis model
  only where the series animates. A render for changeAxisOrder starts the
  place alone (the length tween goes on) and touches no label: a count
  goes on, unless its last setLabelValueAnimation found no previous value
  (prevValue null), which counts again from where it is at enter timing.
  The init sort's render (isInitSort) sets every bar, racing or not, to its
  layout at once (attr) under the tweens already running. A racing bar
  clipped past the plot is kept, ignored, and its label counts on.

  A SUNBURST'S DRILL-DOWN [Batch 115, C6]. sunburstRootToNode is an
  updateView: every piece the new view keeps runs SunburstPiece.updateData
  -- updateProps of its whole shape, update timing with no row; a piece
  that is new (and the return circle, the first time) is created with r at
  r0 and initProps r, enter timing at its row; a piece the view drops is
  removed at once. Its label moves from its old layout (LabelManager) and a
  new one fades. Only the drill's own render does this (HierDrill): the
  sunburst's first render and its other updates stay unanimated here.
  A TREEMAP'S rects (carTmRect) are not this set's: TreemapView animates
  them with its own wrap, which the control runs.

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
  left to it.

  THE UNIVERSAL TRANSITION [Batch 136, D5 UT1]. After every view of a
  setOption has armed (series:transition), the new series that ask for it
  are batched with the old series of the same transition key, their items
  diffed by id, and each pair handled one to one: the same element takes
  its style from the old one; another element stops its own animation and
  morphs from the old element's path (AdvChart.Morph, its __morphT on the
  role proxy, the frame drawing the morph as a path) with the old style;
  a new element with no old one fades in. Where anything morphed, every
  path of the new views without an animation fades in. The old elements
  are read before anything of the new render is armed (SnapUniversal).
  Bars, slices, scatter symbols and line symbols take part.

  COMBINING AND SEPARATING [Batch 137, D5 UT2]. Items pair by group --
  their groupId, else their series' dataGroupId (its own or the root's),
  else their id -- and series by a list seriesKey against single keys too.
  Many old elements into one new one (combineMorph): the new path divided
  (split, or cloned with its opacity fitted), both sides sorted on the
  hilbert curve, and the new element drawn as its children -- owned piece
  proxies, each morphing from one old path -- until the host's __morphT
  (handed on in its during) or every child's own delayed morph is done.
  One old element into many new ones (separateMorph): the old path divided
  by the old item's divideShape (or a combining element's children cloned
  round), sorted, each new element morphing from its piece. An old element
  a morph takes from stops leaving. The drill direction is UT3's. }
interface
uses SysUtils, Classes, Math, contnrs, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Anim,
  tyControls.AdvChart.AnimOpt, tyControls.AdvChart.Lines,
  tyControls.AdvChart.Morph;

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
    { the last setLabelValueAnimation found no previous value
      (labelInnerStore.prevValue null) [Batch 135] }
    FValNoPrev: Boolean;
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
    { [F3a] a label's state proxy of its own: its opacity is upstream's, not
      a factor over the rest (no fade shares the key) }
    FStAbs: Boolean;
    { A LINES EFFECT SYMBOL'S RUN [Batch 121]: where the clip's during has
      moved it, and whether a clip that does not loop has finished (the
      symbol removed) }
    FEff: TTyLinesEffect;
    FEffGone: Boolean;
    { A MORPH [Batch 136, D5 UT1]: zrender's morphPath on this element --
      the two paths' bezier rings aligned, centred and turned
      (AdvChart.Morph) -- drawn at the proxy's __morphT while it runs; and
      the universal transition's style keys (style.fill / stroke / lineWidth
      / opacity), drawn over the element while their animator runs. FUtPass:
      the update that last gave it a style transition -- an older one's is
      stale once the view has set a new style }
    FMorph: TTyMorphData;
    FMorphOn: Boolean;
    FUtStyleOn: Boolean;
    FUtPass: Integer;
    { COMBINING [Batch 137, D5 UT2]: zrender's combineMorph on this element
      -- drawn as its children (childrenRef) while it runs: the pieces its
      path was divided into, each morphing from one old path. FPieces are
      owned (never in the set's index); FCombineLeft counts the pieces still
      morphing on their own delays. A PIECE: its host, its own path (local)
      with the host's transform, its own style keys -- its style is always
      the bag's. }
    FCombineOn: Boolean;
    FPieces: array of TTyChartAnimProxy;
    FCombineLeft: Integer;
    FHost: TTyChartAnimProxy;
    FRest: TTyDoubleArray;
    FRestHasM: Boolean;
    FRestM: TTyMat2D;
    FPieceOwn: TTyStringArray;
    FPieceNoScale: Boolean;
    procedure ClearPieces;
  public
    constructor Create(ASeries, AIndex: Integer; const ARole: string);
    destructor Destroy; override;
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
    { a lines effect symbol's during (_updateSymbolPosition at __t) and
      done (removed) [Batch 121] }
    procedure LinesEffectDuring(APercent: Double);
    procedure LinesEffectDone;
    property LinesEffect: TTyLinesEffect read FEff;
    property LinesEffectGone: Boolean read FEffGone;
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
    { [F3a] a label's state opacity as upstream has it (a proxy of the
      states' own); False: a factor over the rest, as a fade on the same
      proxy has it }
    property StAbsOpacity: Boolean read FStAbs write FStAbs;
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
    { the morph's done (restoreToPath), the style transition's }
    procedure MorphDone;
    procedure UtStyleDone;
    property MorphOn: Boolean read FMorphOn;
    property MorphData: TTyMorphData read FMorph;
    property UtStyleOn: Boolean read FUtStyleOn;
    { combining: the host's during hands its __morphT to every piece, its
      done (restoreToPath) ends it; a piece's own morph done counts down
      to the host's }
    procedure CombineDuring(APercent: Double);
    procedure CombineDone;
    procedure PieceMorphDone;
    property CombineOn: Boolean read FCombineOn;
    function PieceCount: Integer;
    function Piece(AIndex: Integer): TTyChartAnimProxy;
    property Host: TTyChartAnimProxy read FHost;
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
    { [Batch 115] this render is the series' drill-down (a sunburst's
      sunburstRootToNode): its pieces and labels transition }
    HierDrill: Boolean;
    { A BAR RACE [Batch 135]: shouldRealtimeSort, and the base axis' model
      (the axis tween's -- Present False where the series does not
      animate) }
    RtSort: Boolean;
    { A LINE'S LAST RENDER TOOK LineView's INIT BRANCH (its first, or one
      after its step or its coordinate system changed) [F3b]: a step line
      then kept its STEPPED points and stacked-on points as _points /
      _stackedOnPoints -- the next update's isPointsSame compares those, and
      lineAnimationDiff reads the stacked-on ones by the raw indices }
    LineInit: Boolean;
    RtAxis: TTyAnimModel;
    { THE RENDER IS changeAxisOrder's: 1, 2 for the init sort (isInitSort);
      0 for any other -- every bar series reads it }
    ChangeOrder: Integer;
    { ---- THE UNIVERSAL TRANSITION [Batch 136, D5 UT1] ----
      isUniversalTransitionEnabled (`universalTransition: true`, or an object
      whose `enabled` is truthy); the transition key as TyUtTransitionKey
      gives it, and whether seriesKey was a list (UT2 pairs a list's items
      with single keys); divideShape ('' undefined); the delay handler's
      name ('' none). Per view row: the group getGroupId gives ('' where it
      is the id, else '=' and the group) [Batch 137], and the childGroupId
      ('' where it is undefined, else '=' and the child) [Batch 138] }
    UtOn: Boolean;
    UtKey: string;
    UtKeyList: Boolean;
    UtDivide: string;
    UtDelay: string;
    UtGroupIds, UtChildGroupIds: TTyStringArray;
    { [Batch 137] a list seriesKey's items, typed as UtKey is, in the order
      sort() left them }
    UtKeyItems: TTyStringArray;
    { [F3c] the series' model id (a transition option's seriesId); the
      groups its rows name themselves (an encoded dimension's, an item's
      groupId -- '' where getGroupId falls back on the dataGroupId or the
      id) and that dataGroupId ('=' and it, '' falsy) -- a transition
      option reads the new rows against another series' dataGroupId;
      UtNamed: a transition option's `to` names it (upstream's
      __universalTransitionEnabled: a custom series makes its items anew) }
    UtModelId: string;
    UtGroupOwn: TTyStringArray;
    UtDataGroup: string;
    UtNamed: Boolean;
  end;
  TTyChartAnimSeriesArray = array of TTyChartAnimSeries;

  { A SERIES' UNIVERSAL TRANSITION AS ITS OPTION SAYS IT [Batch 137]: what
    the next update reads of an old series -- its transition key (and a
    list's items), its divideShape, and getGroupId's groupId per item of
    its `data` ('=' and String(groupId) where truthy, else '=' and the
    dataGroupId -- its own or the root's -- where truthy, else '': the
    id), GroupDefault for rows past `data`.
    [Batch 138] An encoded itemGroupId dimension wins over all of them: its
    value's string per item (getValueByDimension). ChildByRaw: the
    childGroupId per item -- the encoded itemChildGroupId dimension's
    string, else '=' and String(childGroupId) where truthy, else ''
    (undefined); ChildDefault for rows past `data`. }
  TTyUtSeriesKeys = record
    Key: string;
    List: Boolean;
    Items: TTyStringArray;
    Divide: string;
    GroupsByRaw: TTyStringArray;
    GroupDefault: string;
    ChildByRaw: TTyStringArray;
    ChildDefault: string;
    { [F3c] the groups without the dataGroupId fallback ('' there; an
      encoded dimension's are its own), GroupOwnDefault for rows past
      `data`; the dataGroupId ('=' and it, '' falsy); the model id }
    GroupsOwnByRaw: TTyStringArray;
    GroupOwnDefault: string;
    DataGroup: string;
    ModelId: string;
  end;
  TTyUtSeriesKeysArray = array of TTyUtSeriesKeys;

  { [F3c] A FINDER OF setOption's TRANSITION (UpdateLifecycleTransitionSeriesFinder):
    a seriesIndex (a number -- querySeries compares with ===) or a
    seriesId (a string, against the model id); `dimension` is read into
    groupIdDim upstream and never used }
  TTyUtFinder = record
    HasIndex: Boolean;
    Index: Double;
    HasId: Boolean;
    Id: string;
  end;
  TTyUtFinderArray = array of TTyUtFinder;
  { one item of it: the old series `from` names, the new ones `to` names }
  TTyUtTransitionItem = record
    From, To_: TTyUtFinderArray;
  end;
  TTyUtTransitionArray = array of TTyUtTransitionItem;

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
    { item elements the old data still names that the old render did not
      draw: a drilled sunburst's pieces outside its view, which a universal
      transition morphs from [milestone D5-D8] }
    UtStale: array of TTyChartElement;
    ToOldPoint: TTyChartAnimToPoint;
    { [F3c] setOption's `transition` (seriesTransition): given (truthy),
      it takes the series it names instead of the keys' batches }
    UtHasTransition: Boolean;
    UtTransition: TTyUtTransitionArray;
  end;

  { AN OLD ITEM ELEMENT AS A UNIVERSAL TRANSITION READS IT [Batch 136]:
    the path it draws (PathProxy data) and its computed transform, and its
    style's own keys -- as they were before the new render's tweens set a
    carried proxy to the new layout }
  TTyUtOldSnap = record
    Data: TTyDoubleArray;
    HasM: Boolean;
    M: TTyMat2D;
    Style: TTyAnimProps;
    { [Batch 137] what the dividers and sortPaths read: the path's type and
      its shape now (a morphing path still divides its shape), whether it
      draws a morph, its own transform (a clone keeps it), its effective
      opacity (the clone divider's), its stroke (the bounding rect's); a
      combining element's children: PieceCount snaps from PieceFirst on,
      in this same array }
    Kind: Integer;
    Morphing: Boolean;
    RX, RY, RW, RH: Double;
    SCX, SCY, SR0, SR, SSA, SEA: Double;
    SCW: Boolean;
    HasLocal: Boolean;
    Local: TTyMat2D;
    Opacity: Double;
    HasStroke, HasFill, NoScale: Boolean;
    LineWidth: Double;
    PieceFirst, PieceCount: Integer;
    { [F3c] the path's place in its item's getPathList, its element's role
      and symbol (SymbolDraw keeps a Symbol of the same type) }
    Order: Integer;
    ElRole: TTyChartAnimRole;
    Sym: string;
  end;
  TTyUtOldSnapArray = array of TTyUtOldSnap;
  { [F3c] per old item, the snaps of its paths in getPathList's order }
  TTyUtItemPathsArray = array of TTyIntegerArray;

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
    { the updates armed so far: a style transition's stamp [Batch 136] }
    FPass: Integer;
    procedure NoOp;
    { THE UNIVERSAL TRANSITION (series:transition) [Batch 136, D5 UT1]:
      after every view of the new render has armed, the series batched by
      their transition key, their items diffed by id, and each pair one to
      one -- the same element's style from the old one, another element's
      path morphed from the old element's, a new element with no old one
      faded in -- then, where anything morphed, every path of the new views
      that has no animation fades in }
    procedure ArmUniversal(AList: TTyPaintList; const ASeries: TTyChartAnimSeriesArray;
      const APrev: TTyChartAnimPrev; AUtIdx: TFPHashList;
      const AUtSnaps: TTyUtOldSnapArray; const AUtItems: TTyUtItemPathsArray;
      const AOldOf: TTyIntegerArray;
      const ARowMap: array of TTyIntegerArray; const AUpd: array of Boolean);
    { the old render's item paths as they are now, before anything is
      armed: KeyOf(series, row, 'ut') -> item + 1 into AItems, each item's
      paths (snaps into ASnaps) in getPathList's order [F3c]; nothing when
      no new series asks for a transition }
    procedure SnapUniversal(const ASeries: TTyChartAnimSeriesArray;
      const APrev: TTyChartAnimPrev; AOldIndex, AIdx: TFPHashList;
      out ASnaps: TTyUtOldSnapArray; out AItems: TTyUtItemPathsArray);
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
{ ... turned by ARad about (ACX, ACY), zrender's sense (anticlockwise on the
  screen for a positive angle): points and commands turn, a path's draw-time
  turn grows and its box moves, a circle's or an ellipse's centre turns (an
  ellipse keeps its axes, as the symbol builder does) [F3b] }
procedure TyShapeRotateAbout(var AShape: TTyChartShape; ACX, ACY, ARad: Double);
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

{ ---- THE UNIVERSAL TRANSITION [Batch 136, D5 UT1] ---- }
{ isUniversalTransitionEnabled on a series' own option object }
function TyUtEnabled(AOwn: TJSONData): Boolean;
{ series.getModel('universalTransition').get(AKey): the series' own object,
  then -- unless it is not an object -- its type's default (line, scatter,
  effectScatter: divideShape 'clone', answered nil here), then the root
  option's universalTransition object; nil for none (null falls through) }
function TyUtGet(AOwn, ARoot: TJSONData; const ASeriesType, AKey: string): TJSONData;
{ getSeriesTransitionKey + convertArraySeriesKeyToString, typed as zrender's
  Map keys them: 's:' a string (AId, the model id, when seriesKey is falsy;
  a list sorted and joined with ','), 'n:' a number, 'b:' a boolean }
function TyUtTransitionKey(AOwn, ARoot: TJSONData; const ASeriesType, AId: string;
  out AIsList: Boolean): string; overload;
{ ... and a list's items, typed, in the order sort() leaves them (the
  array is sorted in place before it is joined) [Batch 137] }
function TyUtTransitionKey(AOwn, ARoot: TJSONData; const ASeriesType, AId: string;
  out AIsList: Boolean; out AItems: TTyStringArray): string; overload;
{ the Ut* fields of a series whose Model and SeriesType are set (the group
  ids wait for its rows: TyUtRowGroups) }
procedure TyUtSeriesInfo(var ASeries: TTyChartAnimSeries; ARoot: TJSONData;
  const AId: string);
{ what an old series' option said, for the next update [Batch 137] }
function TyUtSeriesKeysOf(AOwn, ARoot: TJSONData; const ASeriesType,
  AId: string): TTyUtSeriesKeys;
{ the group of each view row (by its raw index); '' where it is the id }
function TyUtRowGroups(const AKeys: TTyUtSeriesKeys; const ARaws: TTyIntegerArray): TTyStringArray;
{ the childGroupId of each view row (by its raw index); '' where it is
  undefined [Batch 138] }
function TyUtRowChildGroups(const AKeys: TTyUtSeriesKeys; const ARaws: TTyIntegerArray): TTyStringArray;
{ [F3c] the groups a series' rows name themselves (GroupsOwnByRaw) }
function TyUtRowGroupsOwn(const AKeys: TTyUtSeriesKeys; const ARaws: TTyIntegerArray): TTyStringArray;
{ [F3c] the rows' groups with ADataGroup the fallback where they name none
  ('' where it is falsy too: the id) }
function TyUtRowGroupsWith(const AOwn: TTyStringArray; const ADataGroup: string): TTyStringArray;
{ [F3c] a transition option's finder against a series (its index, its model id) }
function TyUtFinderMatches(const AF: TTyUtFinder; AIndex: Integer; const AModelId: string): Boolean;
{ [F3c] setOption's `transition` as JSON: normalizeToArray of its items, each
  item's from / to normalizeToArray'd; AHas its truthiness (a falsy one is
  no option at all) }
procedure TyUtParseTransition(AData: TJSONData; out AHas: Boolean;
  out AItems: TTyUtTransitionArray);
{ [F3c] path commands as PathProxy data (M 1, L 2, C 3, Z 6) }
function TyUtCmdsData(const ACmds: TTyPathCmdArray): TTyDoubleArray;
{ [F3c] AN ITEM PATH, for the tests: the proxy role its transition runs on
  ('' for a path that is no item's), its place in its item's getPathList,
  and its path at the layout -- PathProxy data and computed transform }
function TyUtPathKey(const AEl: TTyChartElement): string;
function TyUtPathOrder(const AEl: TTyChartElement): Integer;
function TyUtPathRow(const AEl: TTyChartElement): Integer;
procedure TyUtLayoutPath(const AEl: TTyChartElement; out AData: TTyDoubleArray;
  out AHasM: Boolean; out AM: TTyMat2D);
{ a morph and the universal transition's style keys over one element, as
  its proxy has them now (nothing when it has neither) }
procedure TyUtApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);

implementation

uses tyControls.AdvChart.Labels, tyControls.AdvChart.Data, tyControls.AdvChart.Color,
  tyControls.AdvChart.LinePath, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.Scale, tyControls.AdvChart.MarkerView,
  tyControls.AdvChart.LabelGuide, tyControls.AdvChart.PolarBar,
  tyControls.AdvChart.ZrPath, tyControls.AdvChart.LabelLayout,
  tyControls.AdvChart.Graph;

function UtHostRole(const AEl: TTyChartElement): string; forward;

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
    `__points`, which without a step is the very array `points` is (a step
    line's own, the diff beside the stepped points [F3b]) }
  pts := GetAnimProp('shape.__points');
  if pts.Kind <> avkArray then pts := GetAnimProp('shape.points');
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

procedure TTyChartAnimProxy.LinesEffectDuring(APercent: Double);
begin
  TyLinesEffectStep(FEff, Num('__t'));
  if APercent < 0 then ;
end;

procedure TTyChartAnimProxy.LinesEffectDone;
begin
  FEffGone := True;
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
    carBar, carPolarBar: Result := 'bar';
    carSymbol: Result := 'symbol';
    carLineSymbol: Result := 'lineSymbol';
    carLineRun, carLineArea: Result := 'lineClip';
    carSector: Result := 'sector';
    carSunPiece: Result := 'sunPiece';
    carFunnel: Result := 'funnel';
    carGaugePointer: Result := 'gaugePointer';
    carGaugeProgress, carGaugeCap: Result := 'gaugeProgress';
    carRadarLine: Result := 'radarLine';
    carRadarArea: Result := 'radarArea';
    carCandleBody, carCandleWickHigh, carCandleWickLow: Result := 'candle';
    carBoxplot: Result := 'boxplot';
    carLabel: Result := 'label';
    carGuide: Result := 'guide';
    carGaugeDetail: Result := 'gaugeDetail';
    carEffectSymbol: Result := 'effectSymbol';
    carRipple: Result := 'ripple';
    carMarkPoint, carMarkPointLabel: Result := 'markPoint';
    carMarkLine, carMarkLineFrom, carMarkLineTo, carMarkLineLabel: Result := 'markLine';
    carEndLabel: Result := 'lineClip';
    carRiver: Result := 'riverClip';
    carChord: Result := 'chordGroup';
    carLinesLine, carLinesFrom, carLinesTo, carLinesLabel: Result := 'linesLine';
    carLinesEffect: Result := 'linesEffect';
    carParallelLine: Result := 'parallelClip';
    { [F3a] }
    carSankeyClip: Result := 'sankeyClip';
    carPictorialGlyph: Result := 'pglyph';
    carPictorialClip: Result := 'pclip';
    carGraphEdge, carGraphEdgeFrom, carGraphEdgeTo: Result := 'gedge';
    carGraphEdgeLabel: Result := 'gedgeLabel';
    carTreeNode: Result := 'symbol';
    carTreeEdge: Result := 'treeEdge';
  else
    Result := '';
  end;
end;

function TyChartAnimRoleKey(const AEl: TTyChartElement): string;
begin
  Result := TyChartAnimProxyRole(AEl.Anim.Role);
  { a ripple's number; a pictorial glyph's place in its column [F3a] }
  if AEl.Anim.Role in [carRipple, carPictorialGlyph] then
    Result := Result + IntToStr(AEl.Anim.Sub);
end;

{ [F3b] a row's ITEM model: the series' with the data item's own option
  object (data[raw], when it is an object) asked first }
function ItemModelOf(const AC: TTyChartAnimSeries; ARow: Integer): TTyAnimModel;
var
  raw: Integer;
  d: TJSONData;
begin
  Result := AC.Model;
  Result.Item := nil;
  if not (AC.Model.Own is TJSONObject) then Exit;
  raw := ARow;
  if (ARow >= 0) and (ARow <= High(AC.Raws)) then raw := AC.Raws[ARow];
  d := TJSONObject(AC.Model.Own).Find('data');
  if not (d is TJSONArray) or (raw < 0) or (raw >= d.Count) then Exit;
  if d.Items[raw] is TJSONObject then Result.Item := d.Items[raw];
end;

function KeyIndexOf(const AEl: TTyChartElement): Integer;
begin
  if AEl.Anim.Role in [carLineRun, carLineArea, carEndLabel, carParallelLine,
    carSankeyClip] then Result := -1
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
  if hasClip and ((flags and 8) <> 0) then
  begin
    { a polar: getArea's start and end -- the angles, or the radii -- and
      where the symbol is, the builder's [Batch 113] }
    start := AEl.Anim.G[2];
    stop := AEl.Anim.G[3];
    cur := AEl.Anim.G[9];
    if stop = start then ratio := 0
    else ratio := (cur - start) / (stop - start);
  end
  else if hasClip then
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

{ a bar on a polar: its sector, as BarView's polar creator gives it
  [Batch 113] }
function PolarBarProps(const AEl: TTyChartElement): TTyAnimProps;
begin
  Result := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]),
    Num1('shape.cy', AEl.Anim.G[1]), Num1('shape.r0', AEl.Anim.G[2]),
    Num1('shape.r', AEl.Anim.G[3]), Num1('shape.startAngle', AEl.Anim.G[4]),
    Num1('shape.endAngle', AEl.Anim.G[5])]);
end;

{ a sunburst piece's layout, upstream's shape keys [Batch 115] }
function SunPieceProps(const AEl: TTyChartElement): TTyAnimProps;
begin
  Result := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]),
    Num1('shape.cy', AEl.Anim.G[1]), Num1('shape.r0', AEl.Anim.G[2]),
    Num1('shape.r', AEl.Anim.G[3]), Num1('shape.startAngle', AEl.Anim.G[4]),
    Num1('shape.endAngle', AEl.Anim.G[5])]);
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
{ a polar line's clip sector [Batch 113] }
function PolarClipProps(const AEl: TTyChartElement): TTyAnimProps;
begin
  Result := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]),
    Num1('shape.cy', AEl.Anim.G[1]), Num1('shape.r0', AEl.Anim.G[2]),
    Num1('shape.r', AEl.Anim.G[3]), Num1('shape.startAngle', AEl.Anim.G[4]),
    Num1('shape.endAngle', AEl.Anim.G[11])]);
end;

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

{ EffectLine._updateEffectAnimation / _animateSymbol for one symbol: the
  path, then -- the period above 0 -- `animate('', loop).when(period (twice
  for a round trip), {__t: 1 or 2}).delay(delay).during(...)`, removed when
  a clip that does not loop is done. AResume: the __t an update's restart
  goes on from (delay -period * __t), below 0 for none. [Batch 121] }
procedure StartLinesEffect(AP: TTyChartAnimProxy; const AEl: TTyChartElement;
  AResume: Double);
var
  period, delay, life, top: Double;
  flags: Integer;
  loop, round_: Boolean;
  an: TTyAnimator;
begin
  TyLinesEffectOfElement(AEl, AP.FEff);
  AP.FEffGone := False;
  period := AEl.Anim.G[7];
  delay := AEl.Anim.G[8];
  flags := Round(AEl.Anim.G[9]);
  loop := (flags and 1) <> 0;
  round_ := (flags and 2) <> 0;
  AP.SetNum('__t', 0);
  AP.SetFinal(TyAnimProps([Num1('__t', 0)]));
  if not (period > 0) then Exit;
  if AResume > 0 then delay := -period * AResume;
  if round_ then
  begin
    life := period * 2;
    top := 2;
  end
  else
  begin
    life := period;
    top := 1;
  end;
  an := AP.Animate('', loop).WhenWithKeys(life, ['__t'], [TyAnimNum(top)])
    .Delay(delay).During(@AP.LinesEffectDuring);
  if not loop then an.Done(@AP.LinesEffectDone);
  an.Start('');
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

{ BarView's updateRealtimeAnimation: the length on the series' timing --
  unless the render is only an order's -- then the place along the base axis
  on the axis model's (seriesAnimationModel ? baseAxis.model : null); initProps
  for a new bar, updateProps for a kept one; both at the row [Batch 135] }
procedure RtTween(AP: TTyChartAnimProxy; const AEl: TTyChartElement;
  const AC: TTyChartAnimSeries; AUpdate, AChangeOrder: Boolean; ARow: Integer);
var
  axisT, serT: TTyAnimProps;
  axisModel: TTyAnimModel;
begin
  if AEl.Anim.G[4] <> 0 then
  begin
    axisT := TyAnimProps([Num1('shape.x', AEl.Anim.G[0]), Num1('shape.width', AEl.Anim.G[2])]);
    serT := TyAnimProps([Num1('shape.y', AEl.Anim.G[1]), Num1('shape.height', AEl.Anim.G[3])]);
  end
  else
  begin
    axisT := TyAnimProps([Num1('shape.y', AEl.Anim.G[1]), Num1('shape.height', AEl.Anim.G[3])]);
    serT := TyAnimProps([Num1('shape.x', AEl.Anim.G[0]), Num1('shape.width', AEl.Anim.G[2])]);
  end;
  { animationModel: the series only where it animates }
  if not AChangeOrder then
  begin
    if AUpdate then TyUpdateProps(AP, serT, AC.Model, TyAnimCallAt(ARow))
    else TyInitProps(AP, serT, AC.Model, TyAnimCallAt(ARow));
  end;
  if AC.Enabled then axisModel := AC.RtAxis else axisModel := TyAnimNoModel;
  if AUpdate then TyUpdateProps(AP, axisT, axisModel, TyAnimCallAt(ARow))
  else TyInitProps(AP, axisT, axisModel, TyAnimCallAt(ARow));
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
    carParallelLine:
      begin
        { createGridClipShape [Batch 128]: the data group's clip, the
          parallel's rect with no width (horizontal) or no height, initProps
          to the whole rect on the series -- no row; the view removes it
          once it ends. Only on the view's first render (G[5]): a view a
          legend hid and shows again is not new }
        if AEl.Anim.G[5] = 0 then Exit;
        p := Make(AEl.Anim.Series, -1, 'parallelClip');
        props := TyAnimProps([Num1('shape.x', AEl.Anim.G[0]),
          Num1('shape.y', AEl.Anim.G[1]), Num1('shape.width', AEl.Anim.G[2]),
          Num1('shape.height', AEl.Anim.G[3])]);
        p.Attr(props);
        p.SetFinal(props);
        if AEl.Anim.G[4] <> 0 then p.SetNum('shape.width', 0)
        else p.SetNum('shape.height', 0);
        opts := TyAnimCallNoIndex;
        opts.Done := @NoOp;
        Start(TyAnimProps([Num1('shape.width', AEl.Anim.G[2]),
          Num1('shape.height', AEl.Anim.G[3])]), opts);
      end;
    carSankeyClip:
      begin
        { [F3a] SankeyView's first render (`!this._data`) of a series that
          animates: createGridClipShape over the main group's bounding rect
          -- x - 10, y - 10, no width, height + 20 -- initProps of the width
          + 20 on the series with the done as its callback (so no row, and
          forced); the clip goes when it ends }
        if AUpdate or not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, -1, 'sankeyClip');
        props := TyAnimProps([Num1('shape.x', AEl.Anim.G[0] - 10),
          Num1('shape.y', AEl.Anim.G[1] - 10), Num1('shape.width', AEl.Anim.G[2] + 20),
          Num1('shape.height', AEl.Anim.G[3] + 20)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('shape.width', 0);
        opts := TyAnimCallNoIndex;
        opts.Done := @NoOp;
        Start(TyAnimProps([props[2]]), opts);
      end;
    carTreeNode:
      begin
        { [F3a] TreeView.updateNode: a new Symbol -- its path pops in from
          nothing at enter timing and the row (Symbol.updateData's isInit);
          its group made at the source's first place and updateProps to the
          layout at update timing with no row. A series that does not
          animate sets both at once }
        if AUpdate or not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, idx, 'symbol');
        props := TyAnimProps([Num1('scaleX', AEl.Anim.G[2]), Num1('scaleY', AEl.Anim.G[3]),
          Num1('style.opacity', AEl.Anim.G[4])]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('scaleX', 0);
        p.SetNum('scaleY', 0);
        p.SetNum('style.opacity', 0);
        Start(props, TyAnimCallAt(idx));
        if AEl.Anim.G[10] = 0 then Exit;
        p := Make(AEl.Anim.Series, idx, 'treeGroup');
        props := TyAnimProps([Num1('x', AEl.Anim.G[5]), Num1('y', AEl.Anim.G[6])]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('x', AEl.Anim.G[8]);
        p.SetNum('y', AEl.Anim.G[9]);
        TyUpdateProps(p, props, AC.Model, TyAnimCallNoIndex);
      end;
    carTreeEdge:
      begin
        { [F3a] drawEdge: a curve made on the source's first place (both ends
          and both control points), a TreePath with one child point on its
          parent; updateProps to the shape at update timing with no row }
        if AUpdate or not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, idx, 'treeEdge');
        if AEl.Anim.Sub = 1 then
        begin
          ring := Copy(AEl.Anim.Pts, 0, Length(AEl.Anim.Pts));
          props := TyAnimProps([TyAnimProp('shape.parentPoint',
            TyAnimArr([AEl.Anim.G[0], AEl.Anim.G[1]], 2)),
            TyAnimProp('shape.childPoints', TyAnimArr(ring, 2))]);
          p.Attr(props);
          p.SetFinal(props);
          p.SetAnimProp('shape.childPoints', TyAnimArr([AEl.Anim.G[0], AEl.Anim.G[1]], 2));
        end
        else
        begin
          if Length(AEl.Anim.Vals) < 2 then Exit;
          props := TyAnimProps([Num1('shape.x1', AEl.Anim.G[0]), Num1('shape.y1', AEl.Anim.G[1]),
            Num1('shape.cpx1', AEl.Anim.G[2]), Num1('shape.cpy1', AEl.Anim.G[3]),
            Num1('shape.cpx2', AEl.Anim.G[4]), Num1('shape.cpy2', AEl.Anim.G[5]),
            Num1('shape.x2', AEl.Anim.G[6]), Num1('shape.y2', AEl.Anim.G[7])]);
          p.Attr(props);
          p.SetFinal(props);
          for k := 0 to 3 do
          begin
            p.SetNum(props[k * 2].Key, AEl.Anim.Vals[0]);
            p.SetNum(props[k * 2 + 1].Key, AEl.Anim.Vals[1]);
          end;
        end;
        TyUpdateProps(p, props, AC.Model, TyAnimCallNoIndex);
      end;
    carGraphEdge, carGraphEdgeFrom, carGraphEdgeTo:
      begin
        { [F3a] Line._createLine: `line.shape.percent = 0`, initProps of 1
          on the series at the edge's row -- its end symbols and its label
          are placed from it every frame (beforeUpdate) }
        if AUpdate or not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, idx, 'gedge');
        props := TyAnimProps([Num1('shape.percent', 1)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('shape.percent', 0);
        Start(props, TyAnimCallAt(idx));
      end;
    carGraphEdgeLabel:
      begin
        { [F3a] LabelManager's fade of the Line group's text, to its own
          opacity (the line's: a graph edge's is 0.5 by default) at the
          edge's row }
        if AUpdate or not (AC.Enabled and AC.LabelFade) or AEl.Ignore then Exit;
        p := Make(AEl.Anim.Series, idx, 'gedgeLabel');
        props := TyAnimProps([Num1('style.opacity', AEl.Style.Alpha)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('style.opacity', 0);
        Start(props, TyAnimCallAt(idx));
      end;
    carPictorialGlyph:
      begin
        { [F3a] createOrUpdateRepeatSymbols / createOrUpdateSingleSymbol: a
          new path at its place with no scale, initProps to symbolScale on
          the ITEM's model (ItemModel.isAnimationEnabled: the series' and
          the row's own `animation`) at the row; a row that does not animate
          is set at once -- no proxy }
        if AUpdate or not AC.Enabled or (AEl.Anim.G[4] <> 0) then Exit;
        p := Make(AEl.Anim.Series, idx, TyChartAnimRoleKey(AEl));
        { [F3b] a repeated glyph turns too: from the 0 a new path has }
        if AEl.Anim.G[6] <> 0 then
          props := TyAnimProps([Num1('scaleX', AEl.Anim.G[2]), Num1('scaleY', AEl.Anim.G[3]),
            Num1('rotation', AEl.Anim.G[5])])
        else
          props := TyAnimProps([Num1('scaleX', AEl.Anim.G[2]), Num1('scaleY', AEl.Anim.G[3])]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('scaleX', 0);
        p.SetNum('scaleY', 0);
        if AEl.Anim.G[6] <> 0 then p.SetNum('rotation', 0);
        { [F3b] on the ITEM's model }
        TyInitProps(p, props, ItemModelOf(AC, idx), TyAnimCallAt(idx));
      end;
    carPictorialClip:
      begin
        { [F3a] createOrUpdateClip: the bundle's clip made with no length
          along the value axis, initProps of that length at the row; the
          glyphs are set where they land }
        if AUpdate or not AC.Enabled or (AEl.Anim.G[8] <> 0) then Exit;
        p := Make(AEl.Anim.Series, idx, 'pclip');
        if AEl.Anim.G[1] <> 0 then
          props := TyAnimProps([Num1('shape.height', AEl.Anim.G[2])])
        else
          props := TyAnimProps([Num1('shape.width', AEl.Anim.G[2])]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum(props[0].Key, 0);
        { [F3b] on the ITEM's model }
        TyInitProps(p, props, ItemModelOf(AC, idx), TyAnimCallAt(idx));
      end;
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
        { the init sort's render sets it to its layout; a racing bar tweens
          its two halves apart [Batch 135] }
        if AC.ChangeOrder = 2 then p.Attr(props)
        else if AC.RtSort then RtTween(p, AEl, AC, False, False, idx)
        else Start(props, TyAnimCallAt(idx));
      end;
    carRiver:
      begin
        { createGridClipShape over polygon.getBoundingRect() -- taken before
          the style is set, so no stroke in it -- only where the series
          animates: x - 10, y - 10, no width, height + 20, initProps to
          x - 50, width + 100 (height + 20 again) on the series, no row; the
          clip is removed when it ends [Batch 118] }
        if not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, idx, 'riverClip');
        x := AEl.Anim.G[0];
        y := AEl.Anim.G[1];
        w := AEl.Anim.G[2];
        h := AEl.Anim.G[3];
        props := TyAnimProps([Num1('shape.x', x - 50), Num1('shape.y', y - 10),
          Num1('shape.width', w + 100), Num1('shape.height', h + 20)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('shape.x', x - 10);
        p.SetNum('shape.width', 0);
        Start(TyAnimProps([props[0], props[2], props[3]]), TyAnimCallNoIndex);
      end;
    carChord:
      begin
        { ChordView's first render: the view group at 0.01 about the centre
          option, initProps to 1 on the series, no row; with the series not
          animating initProps sets 1 at once -- no proxy [Batch 120] }
        if not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, -1, 'chordGroup');
        props := TyAnimProps([Num1('scaleX', 1), Num1('scaleY', 1)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('scaleX', 0.01);
        p.SetNum('scaleY', 0.01);
        Start(props, TyAnimCallNoIndex);
      end;
    carPolarBar:
      begin
        { the polar creator: a radial bar's r from r0, a tangential one's end
          angle from its start; its own initProps without a row is stopped
          by the one with it, so one animation at the row [Batch 113] }
        p := Make(AEl.Anim.Series, idx, 'bar');
        props := PolarBarProps(AEl);
        p.Attr(props);
        p.SetFinal(props);
        if AC.Enabled then
        begin
          if AEl.Anim.G[7] <> 0 then p.SetNum('shape.r', AEl.Anim.G[2])
          else p.SetNum('shape.endAngle', AEl.Anim.G[4]);
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
      if (Round(AEl.Anim.G[5]) and 8) <> 0 then
      begin
        { createPolarClipPath: the sweep from its start (an angle base) or
          r from r0, initProps({endAngle, r}) on the series, no row
          [Batch 113] }
        p := Make(AEl.Anim.Series, -1, 'lineClip');
        props := PolarClipProps(AEl);
        p.Attr(props);
        p.SetFinal(props);
        if (Round(AEl.Anim.G[5]) and 32) <> 0 then
          p.SetNum('shape.endAngle', AEl.Anim.G[4])
        else
          p.SetNum('shape.r', AEl.Anim.G[2]);
        Start(TyAnimProps([Num1('shape.endAngle', AEl.Anim.G[11]),
          Num1('shape.r', AEl.Anim.G[3])]), TyAnimCallNoIndex);
      end
      else
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
    carSunPiece:
      begin
        { a drill-down's new piece: created with r at r0, initProps r at its
          row (SunburstPiece.updateData's firstCreate) [Batch 115]; and
          [F3a] every piece of a first render the same way -- an update that
          is not a drill stays still here }
        if AUpdate and not AC.HierDrill then Exit;
        if not AUpdate and not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, idx, 'sunPiece');
        props := SunPieceProps(AEl);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('shape.r', AEl.Anim.G[2]);
        Start(TyAnimProps([Num1('shape.r', AEl.Anim.G[3])]), TyAnimCallAt(idx));
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
    carBoxplot:
      begin
        { transInit: every point's value coordinate on the median's -- y on
          a horizontal layout, x on a vertical one -- then initProps at the
          row [Batch 108] }
        if Length(AEl.Anim.Pts) < 28 then Exit;
        p := Make(AEl.Anim.Series, idx, 'boxplot');
        ring := Copy(AEl.Anim.Pts, 0, 28);
        from := Copy(ring, 0, 28);
        for k := 0 to 13 do
          if AEl.Anim.G[1] <> 0 then from[k * 2 + 1] := AEl.Anim.G[0]
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
          p.FValNoPrev := True;
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
        { A HIDDEN LABEL IS NOT FADED IN: LabelManager walks the texts that
          are not ignored -- a themeRiver's built for its emphasis alone
          [Batch 118]; [F3a] nor is anything's built for a state alone }
        if AEl.Ignore then Exit;
        { [F3a] A TREEMAP'S DRILL fades its new words with its own wrap; its
          breadcrumb's words never fade (disableLabelAnimation) }
        if AEl.Anim.NoFade or ((AC.SeriesType = 'treemap') and AUpdate) then Exit;
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
    carLinesLine, carLinesFrom, carLinesTo, carLinesLabel:
      begin
        { Line._createLine: `shape.percent = 0`, initProps to 1 on the
          series' model at the row -- the symbols and the label read it
          every frame (beforeUpdate), the label's fade runs on the same
          timing [Batch 121] }
        p := Make(AEl.Anim.Series, idx, 'linesLine');
        props := TyAnimProps([Num1('shape.percent', 1)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('shape.percent', 0);
        TyInitProps(p, props, AC.Model, TyAnimCallAt(idx));
      end;
    carLinesEffect:
      StartLinesEffect(Make(AEl.Anim.Series, idx, 'linesEffect'), AEl, -1);
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
  utIdx: TFPHashList;
  utSnaps: TTyUtOldSnapArray;
  utItems: TTyUtItemPathsArray;
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
    { setLabelValueAnimation: prevValue is the old value [Batch 135] }
    if AP <> nil then AP.FValNoPrev := not AOldEl.Caption.ValHas;
    if AOldEl.Caption.ValHas and (not IsNan(AOldEl.Caption.ValNum))
      and (not IsNan(AEl.Caption.ValNum))
      and (AOldEl.Caption.ValNum = AEl.Caption.ValNum) then Exit;
    if AP = nil then AP := Make(ASer, ARow, ARole);
    AP.FValNoPrev := not AOldEl.Caption.ValHas;
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
      carRiver:
        { A KEPT LAYER is not clipped again (its points tween upstream,
          snapped here); a new one enters [Batch 118] }
        if AOldRow < 0 then ArmOne(AList, AAt, AEl, AC, True);
      carChord:
        { A KEPT VIEW scales no more (`if (!oldData)`): an enter still
          running goes on [Batch 120] }
        begin
          p := OldProxy(AOld, -1, 'chordGroup');
          if p <> nil then Carry(p, s, -1);
        end;
      carParallelLine:
        begin
          { THE VIEW IS KEPT: its enter clip runs on (it is made only on the
            view's first render); a row's points move to their new place
            with no tween here [Batch 128] }
          if Find(s, -1, 'parallelClip') <> nil then Exit;
          q2 := OldProxy(AOld, -1, 'parallelClip');
          if q2 <> nil then Carry(q2, s, -1);
        end;
      carSankeyClip:
        begin
          { [F3a] the same for a sankey's main group: its enter clip runs on,
            the view has its data }
          if Find(s, -1, 'sankeyClip') <> nil then Exit;
          q2 := OldProxy(AOld, -1, 'sankeyClip');
          if q2 <> nil then Carry(q2, s, -1);
        end;
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
          { the init sort's render: the layout at once, under what runs; a
            racing bar: its two halves -- an order's render the place alone
            [Batch 135] }
          if AC.ChangeOrder = 2 then p.Attr(props)
          else if AC.RtSort then RtTween(p, AEl, AC, True, AC.ChangeOrder = 1, r)
          else TyUpdateProps(p, props, AC.Model, TyAnimCallAt(r));
        end;
      carPolarBar:
        begin
          if AOldRow < 0 then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          props := PolarBarProps(AEl);
          hasOld := OldEl(AOld, AOldRow, 'bar', oe) and (oe.Anim.Role = carPolarBar);
          hadProxy := OldProxy(AOld, AOldRow, 'bar') <> nil;
          if hasOld then oprops := PolarBarProps(oe) else oprops := nil;
          p := Take(AOld, AOldRow, s, r, 'bar', oprops, props, hasOld);
          if (not hasOld) and (not hadProxy) and AC.Enabled then
          begin
            if AEl.Anim.G[7] <> 0 then p.SetNum('shape.r', AEl.Anim.G[2])
            else p.SetNum('shape.endAngle', AEl.Anim.G[4]);
          end;
          p.SetFinal(props);
          TyUpdateProps(p, props, AC.Model, TyAnimCallAt(r));
        end;
      carSymbol:
        begin
          { [F3a] A GRAPH'S NODES enter here, and do not move in an update:
            its edges have no update tween yet, and nodes sliding under lines
            that jump is no picture upstream draws -- the whole graph is set
            (an F3 item still open) }
          if AC.SeriesType = 'graph' then Exit;
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
          if (Round(AEl.Anim.G[5]) and 8) <> 0 then
          begin
            props := PolarClipProps(AEl);
            hasOld := OldEl(AOld, -1, 'lineClip', oe) and ((Round(oe.Anim.G[5]) and 8) <> 0);
            if hasOld then oprops := PolarClipProps(oe) else oprops := nil;
          end
          else
          begin
            props := ClipProps(AEl);
            hasOld := OldEl(AOld, -1, 'lineClip', oe) and ((Round(oe.Anim.G[5]) and 8) = 0);
            if hasOld then oprops := ClipProps(oe) else oprops := nil;
          end;
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
      carSunPiece:
        begin
          { a drill-down's piece: kept -- updateProps of the whole shape
            from where it is, update timing, no row; new -- ArmOne's
            [Batch 115] }
          if not AC.HierDrill then Exit;
          hasOld := (AOldRow >= 0) and OldEl(AOld, AOldRow, 'sunPiece', oe);
          if not hasOld then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          props := SunPieceProps(AEl);
          p := Take(AOld, AOldRow, s, r, 'sunPiece', SunPieceProps(oe), props, True);
          p.SetFinal(props);
          TyUpdateProps(p, props, AC.Model, TyAnimCallNoIndex);
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
      carBoxplot:
        begin
          { BoxplotView: an added box enters (createNormalBox with isInit); a
            kept one updateProps its points from where they are, at the new
            row [Batch 108] }
          if AOldRow < 0 then
          begin
            ArmOne(AList, AAt, AEl, AC, True);
            Exit;
          end;
          if Length(AEl.Anim.Pts) < 28 then Exit;
          ring := Copy(AEl.Anim.Pts, 0, 28);
          props := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ring, 2))]);
          hasOld := OldEl(AOld, AOldRow, 'boxplot', oe) and (Length(oe.Anim.Pts) >= 28);
          if hasOld then
            oprops := TyAnimProps([TyAnimProp('shape.points',
              TyAnimArr(Copy(oe.Anim.Pts, 0, 28), 2))])
          else oprops := nil;
          p := Take(AOld, AOldRow, s, r, 'boxplot', oprops, props, hasOld);
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
                { AN ORDER'S RENDER styles no label: prevValue becomes the
                  value -- the count goes on -- unless it was null, and
                  animateLabelValue counts again from the interpolated
                  value (or 0) at ENTER timing [Batch 135] }
                if AEl.Caption.ValAnim and (AC.ChangeOrder <> 0) then
                begin
                  if (p <> nil) and p.FValNoPrev then
                  begin
                    if p.FValHasInterp then a := p.FValInterp else a := NaN;
                    StartCount(p, AEl, a, False, AC.Model, r);
                  end;
                end
                else if AEl.Caption.ValAnim then
                  CountOn(p, oe, AEl, s, r, 'label', AC.Model)
                else if (AEl.Anim.HostPlus1 = 0)
                  and ((AC.SeriesType = 'pie') or AEl.Caption.LmFree
                    { a sunburst's in its drill-down [Batch 115] }
                    or (AC.HierDrill and (AC.SeriesType = 'sunburst'))) then
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
      carLinesEffect:
        begin
          { EffectLine.updateData: the path anew; the clip runs on unless the
            period, loop or roundTrip changed -- then it starts over from
            where __t was (delay -period * __t) [Batch 121] }
          if (AOldRow >= 0) and OldEl(AOld, AOldRow, 'linesEffect', oe) then
          begin
            p := OldProxy(AOld, AOldRow, 'linesEffect');
            if p <> nil then
            begin
              Carry(p, s, r);
              if (oe.Anim.G[7] = AEl.Anim.G[7])
                and (Round(oe.Anim.G[9]) and 3 = Round(AEl.Anim.G[9]) and 3) then
              begin
                a := p.FEff.T;
                rot := p.FEff.LastT;
                TyLinesEffectOfElement(AEl, p.FEff);
                p.FEff.T := a;
                p.FEff.LastT := rot;
                p.FEff.HasLastT := True;
                p.FEff.Ignore := True;
              end
              else
              begin
                a := p.Num('__t');
                p.StopAnimation;
                StartLinesEffect(p, AEl, a);
              end;
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
    { [F3b] the stepped points }
    stepCode: Integer;
    turn: TTyStepTurn;
    cn: Boolean;
    tCur, tNxt, tCurS, tNxtS: TTyDoubleArray;
    { the old render's _points and _stackedOnPoints: stepped after its
      init branch [F3b] }
    keptPts, keptBase: TTyDoubleArray;
    oldTurn: TTyStepTurn;

    function Pts2(const A: TTyDoubleArray): TTyPointFArray;
    var z: Integer;
    begin
      SetLength(Result, Length(A) div 2);
      for z := 0 to High(Result) do Result[z] := TyPointF(A[z * 2], A[z * 2 + 1]);
    end;

    function Flat(const A: TTyPointFArray): TTyDoubleArray;
    var z: Integer;
    begin
      SetLength(Result, Length(A) * 2);
      for z := 0 to High(A) do
      begin
        Result[z * 2] := A[z].X;
        Result[z * 2 + 1] := A[z].Y;
      end;
    end;

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
      `animation` off (setShape). A STEP that changed (`step !==
      this._step`) is a new polyline upstream, which enters; here it is set
      [F3b: a step kept is tweened below] }
    if not (hasN and hasO) then Exit;
    if not AC.On_ then Exit;
    if Round(nr.Anim.G[7]) <> Round(orr.Anim.G[7]) then Exit;
    stepCode := Round(nr.Anim.G[7]);
    oldPts := orr.Anim.Pts;
    newPts := nr.Anim.Pts;
    oldBase := orr.Anim.Base;
    newBase := nr.Anim.Base;
    { THE OLD RENDER'S _points / _stackedOnPoints: a step line whose last
      render took the init branch kept them stepped (render turns its local
      points before it saves them); after an update render they are the
      layout's [F3b] }
    keptPts := oldPts;
    keptBase := oldBase;
    if APrev.Series[AOld].LineInit and (stepCode <> 0) then
    begin
      case stepCode of
        2: oldTurn := sttMiddle;
        3: oldTurn := sttEnd;
      else
        oldTurn := sttStart;
      end;
      if oldBase <> nil then
        keptBase := Flat(TyTurnPointsIntoStep(Pts2(oldBase), Pts2(oldPts), True,
          (Round(orr.Anim.G[5]) and 2) <> 0, oldTurn, orr.Anim.G[10] <> 0));
      keptPts := Flat(TyTurnPointsIntoStep(Pts2(oldPts), nil, False,
        (Round(orr.Anim.G[5]) and 2) <> 0, oldTurn, orr.Anim.G[10] <> 0));
    end;
    { UNCHANGED: the polyline is not touched, a tween in flight goes on }
    if Same(keptBase, newBase, keptBase <> nil, newBase <> nil)
      and Same(keptPts, newPts, True, True) then
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
            { oldStackedOnPoints[oldIdx * 2]: the kept array, stepped or
              not, by the raw index [F3b] }
            Push2(curS, len, At(keptBase, oi), At(keptBase, oi + 1));
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
    { A STEP LINE TWEENS ITS STEPPED POINTS (LineView._doUpdateAnimation,
      `if (step)`): the Float32 diff turned into steps -- plain number
      arrays -- the stacked-on points filtered by the line's own; the
      polyline's `__points` (the diff itself) tween beside them, and the
      symbols follow those [F3b] }
    if stepCode <> 0 then
    begin
      case stepCode of
        2: turn := sttMiddle;
        3: turn := sttEnd;
      else
        turn := sttStart;
      end;
      cn := nr.Anim.G[10] <> 0;
      tCurS := Flat(TyTurnPointsIntoStep(Pts2(sCurS), Pts2(sCur), True, horiz, turn, cn));
      tCur := Flat(TyTurnPointsIntoStep(Pts2(sCur), nil, False, horiz, turn, cn));
      tNxtS := Flat(TyTurnPointsIntoStep(Pts2(sNxtS), Pts2(sNxt), True, horiz, turn, cn));
      tNxt := Flat(TyTurnPointsIntoStep(Pts2(sNxt), nil, False, horiz, turn, cn));
    end
    else
    begin
      tCur := sCur;
      tNxt := sNxt;
      tCurS := sCurS;
      tNxtS := sNxtS;
    end;
    { DON'T TWEEN A DIFF THIS LARGE: set the line (LineView.ts:1358-1376) }
    if (TyLineBoundingDiff(tCur, tNxt) > 3000)
      or ((newBase <> nil) and (TyLineBoundingDiff(tCurS, tNxtS) > 3000)) then
      Exit;
    poly := OldProxy(AOld, -1, 'linePoly');
    if poly <> nil then Carry(poly, ASer, -1)
    else poly := Make(ASer, -1, 'linePoly');
    poly.FFollow := nil;
    if stepCode <> 0 then
    begin
      { shape.__points = diff.current; shape.points = current; the target
        {points: next, __points: diff.next} }
      poly.SetAnimProp('shape.__points', TyAnimArr(sCur, 0, True));
      poly.SetAnimProp('shape.points', TyAnimArr(tCur, 0, False));
      poly.StopAnimation;
      TyUpdateProps(poly, TyAnimProps([TyAnimProp('shape.points', TyAnimArr(tNxt, 0, False)),
        TyAnimProp('shape.__points', TyAnimArr(sNxt, 0, True))]), AC.Model, TyAnimCallNoIndex);
      poly.SetFinal(TyAnimProps([TyAnimProp('shape.points', TyAnimArr(tNxt, 0, False)),
        TyAnimProp('shape.__points', TyAnimArr(sNxt, 0, True))]));
    end
    else
    begin
      poly.SetAnimProp('shape.points', TyAnimArr(sCur, 0, True));
      poly.StopAnimation;
      TyUpdateProps(poly, TyAnimProps([TyAnimProp('shape.points',
        TyAnimArr(sNxt, 0, True))]), AC.Model, TyAnimCallNoIndex);
      poly.SetFinal(TyAnimProps([TyAnimProp('shape.points', TyAnimArr(sNxt, 0, True))]));
    end;
    if newBase <> nil then
    begin
      area := OldProxy(AOld, -1, 'lineArea');
      if area <> nil then Carry(area, ASer, -1)
      else area := Make(ASer, -1, 'lineArea');
      { a step's stacked-on points are plain numbers [F3b] }
      area.SetAnimProp('shape.stackedOnPoints', TyAnimArr(tCurS, 0, stepCode = 0));
      area.StopAnimation;
      TyUpdateProps(area, TyAnimProps([TyAnimProp('shape.stackedOnPoints',
        TyAnimArr(tNxtS, 0, stepCode = 0))]), AC.Model, TyAnimCallNoIndex);
      area.SetFinal(TyAnimProps([TyAnimProp('shape.stackedOnPoints',
        TyAnimArr(tNxtS, 0, stepCode = 0))]));
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
  Inc(FPass);
  oldItems := FItems;
  oldIndex := FIndex;
  FItems := TFPList.Create;
  FIndex := TFPHashList.Create;
  prevIdx := TFPHashList.Create;
  utIdx := TFPHashList.Create;
  try
    for i := 0 to oldItems.Count - 1 do
      TTyChartAnimProxy(oldItems[i]).FClaimed := False;
    { the old elements by (series, row, proxy role): the first of each }
    for i := 0 to High(APrev.Elements) do
    begin
      el := APrev.Elements[i];
      { a treemap's item path has no proxy role of its own: the universal
        transition finds it by its own [Batch 138] }
      if (el.Anim.Role = carTmRect) and (UtHostRole(el) <> '')
        and (prevIdx.Find(KeyOf(el.Anim.Series, el.Anim.Index, 'tmRect')) = nil) then
        prevIdx.Add(KeyOf(el.Anim.Series, el.Anim.Index, 'tmRect'), Pointer(PtrInt(i + 1)));
      role := TyChartAnimRoleKey(el);
      if role = '' then Continue;
      if prevIdx.Find(KeyOf(el.Anim.Series, KeyIndexOf(el), role)) = nil then
        prevIdx.Add(KeyOf(el.Anim.Series, KeyIndexOf(el), role), Pointer(PtrInt(i + 1)));
    end;
    { THE OLD ITEM ELEMENTS AS THEY ARE, before a tween of this update sets a
      carried proxy to the new layout [Batch 136] }
    SnapUniversal(ASeries, APrev, oldIndex, utIdx, utSnaps, utItems);
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
    { THE UNIVERSAL TRANSITION, once every view has armed [Batch 136] }
    ArmUniversal(AList, ASeries, APrev, utIdx, utSnaps, utItems, oldOf, rowMap, upd);
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
    { A STYLE TRANSITION OF AN EARLIER UPDATE is stale: the view set a new
      style object, the old animator writes into the one it replaced
      [Batch 136] }
    for i := 0 to FItems.Count - 1 do
    begin
      p := TTyChartAnimProxy(FItems[i]);
      if p.FUtStyleOn and (p.FUtPass <> FPass) then p.FUtStyleOn := False;
    end;
  finally
    utIdx.Free;
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

procedure TyShapeRotateAbout(var AShape: TTyChartShape; ACX, ACY, ARad: Double);
var
  i: Integer;
  s, c, tx, ty: Double;
  r: TTyRectF;

  procedure Turn(var AX, AY: Double);
  var dx, dy: Double;
  begin
    dx := AX - ACX;
    dy := AY - ACY;
    AX := ACX + dx * c - dy * s;
    AY := ACY + dx * s + dy * c;
  end;

  procedure TurnRect(var ARect: TTyRectF);
  var
    xs, ys: array[0..3] of Double;
    k: Integer;
  begin
    xs[0] := ARect.Left; ys[0] := ARect.Top;
    xs[1] := ARect.Right; ys[1] := ARect.Top;
    xs[2] := ARect.Right; ys[2] := ARect.Bottom;
    xs[3] := ARect.Left; ys[3] := ARect.Bottom;
    for k := 0 to 3 do Turn(xs[k], ys[k]);
    ARect := TyRectF(MinValue(xs), MinValue(ys), MaxValue(xs), MaxValue(ys));
  end;

begin
  if (ARad = 0) or IsNan(ARad) then Exit;
  { the symbol builder's turn (Place): the screen's y grows downward }
  s := Sin(-ARad);
  c := Cos(-ARad);
  case AShape.Kind of
    cskPolyline, cskPolygon:
      begin
        AShape.Points := Copy(AShape.Points, 0, Length(AShape.Points));
        for i := 0 to High(AShape.Points) do Turn(AShape.Points[i].X, AShape.Points[i].Y);
        AShape.Cmds := Copy(AShape.Cmds, 0, Length(AShape.Cmds));
        for i := 0 to High(AShape.Cmds) do
        begin
          Turn(AShape.Cmds[i].X1, AShape.Cmds[i].Y1);
          Turn(AShape.Cmds[i].X2, AShape.Cmds[i].Y2);
          Turn(AShape.Cmds[i].X, AShape.Cmds[i].Y);
        end;
        if AShape.HasCmdBounds then TurnRect(AShape.CmdBounds);
      end;
    cskPath:
      begin
        { turned about its own centre by the sum, then moved where a turn
          about (ACX, ACY) puts that centre: the painter's turn is the
          canvas' (clockwise), hence the negation }
        tx := AShape.RotCX;
        ty := AShape.RotCY;
        Turn(tx, ty);
        AShape.RotationRad := AShape.RotationRad - ARad;
        r := AShape.Bounds;
        AShape.Bounds := TyRectF(r.Left + tx - AShape.RotCX, r.Top + ty - AShape.RotCY,
          r.Right + tx - AShape.RotCX, r.Bottom + ty - AShape.RotCY);
        AShape.RotCX := tx;
        AShape.RotCY := ty;
      end;
    cskCircle, cskEllipse, cskSector:
      Turn(AShape.CX, AShape.CY);
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

{ a key the proxy holds, as a number; AOr where it holds none (or there is
  no proxy: a sunburst's first render makes none [Batch 138]) }
function NumOr(P: TTyChartAnimProxy; const AKey: string; AOr: Double): Double;
var v: TTyAnimValue;
begin
  if P = nil then Exit(AOr);
  v := P.GetAnimProp(AKey);
  if v.Kind in [avkNumber, avkBool] then Result := v.Num else Result := AOr;
end;

{ a sunburst piece as its proxy has it: its angles in order as the static
  build passes them, the corners the layout's [Batch 115] }
function SunPieceFrom(const AEl: TTyChartElement; P: TTyChartAnimProxy): TTyChartShape;
var a, b: Double;
begin
  a := NumOr(P, 'shape.startAngle', AEl.Anim.G[4]);
  b := NumOr(P, 'shape.endAngle', AEl.Anim.G[5]);
  Result := TyShapeSector(NumOr(P, 'shape.cx', AEl.Anim.G[0]),
    NumOr(P, 'shape.cy', AEl.Anim.G[1]), NumOr(P, 'shape.r0', AEl.Anim.G[2]),
    NumOr(P, 'shape.r', AEl.Anim.G[3]), Min(a, b), Max(a, b));
  Result.SectorRadii := AEl.Shape.SectorRadii;
end;

{ a polar bar as its proxy has it: the sector, its corners and its
  sausage kept; the layout numbers (G) and the label's rect follow
  [Batch 113] }
procedure PolarBarFrom(var AEl: TTyChartElement; P: TTyChartAnimProxy);
var
  s: TTyPolarSector;
  radii: TTyCornerRadii;
  sausage: Boolean;
  zp: TTyZrPath;
  list: TTyDoubleArray;
  k: Integer;
begin
  s.CX := NumOr(P, 'shape.cx', AEl.Anim.G[0]);
  s.CY := NumOr(P, 'shape.cy', AEl.Anim.G[1]);
  s.R0 := NumOr(P, 'shape.r0', AEl.Anim.G[2]);
  s.R := NumOr(P, 'shape.r', AEl.Anim.G[3]);
  s.SA := NumOr(P, 'shape.startAngle', AEl.Anim.G[4]);
  s.EA := NumOr(P, 'shape.endAngle', AEl.Anim.G[5]);
  s.CW := AEl.Anim.G[6] <> 0;
  radii := AEl.Shape.SectorRadii;
  sausage := AEl.Shape.Sausage;
  AEl.Shape := TyPolarSectorShape(s, nil, sausage);
  AEl.Shape.SectorRadii := radii;
  AEl.Anim.G[0] := s.CX;
  AEl.Anim.G[1] := s.CY;
  AEl.Anim.G[2] := s.R0;
  AEl.Anim.G[3] := s.R;
  AEl.Anim.G[4] := s.SA;
  AEl.Anim.G[5] := s.EA;
  if AEl.Caption.SecHas and AEl.Caption.HasHostBox then
  begin
    if sausage then zp := TyZrSausagePath(s)
    else
    begin
      SetLength(list, 4);
      for k := 0 to 3 do list[k] := radii[k];
      zp := TyZrSectorPath(s, list);
    end;
    AEl.Caption.HostBox := TyZrBBox(zp);
  end;
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

procedure ChordFrom(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
var
  sx, sy, ox, oy: Double;

  function GX(AV: Double): Double;
  begin
    Result := ox + (AV - ox) * sx;
  end;

  function GY(AV: Double): Double;
  begin
    Result := oy + (AV - oy) * sy;
  end;

begin
  sx := AProxy.Num('scaleX');
  sy := AProxy.Num('scaleY');
  ox := AEl.Anim.G[0];
  oy := AEl.Anim.G[1];
  if IsNan(sx) or IsNan(sy) then Exit;
  TyShapeScaleAbout(AEl.Shape, ox, oy, sx, sy);
  if AEl.Style.FillGradient.Kind <> cgkNone then
  begin
    if AEl.Style.FillGradient.Global then
    begin
      AEl.Style.FillGradient.X := GX(AEl.Style.FillGradient.X);
      AEl.Style.FillGradient.Y := GY(AEl.Style.FillGradient.Y);
      AEl.Style.FillGradient.X2 := GX(AEl.Style.FillGradient.X2);
      AEl.Style.FillGradient.Y2 := GY(AEl.Style.FillGradient.Y2);
      AEl.Style.FillGradient.R := AEl.Style.FillGradient.R * Min(Abs(sx), Abs(sy));
    end;
    if AEl.Style.GradBoxSet then
    begin
      AEl.Style.GradBox.X := GX(AEl.Style.GradBox.X);
      AEl.Style.GradBox.Y := GY(AEl.Style.GradBox.Y);
      AEl.Style.GradBox.W := AEl.Style.GradBox.W * sx;
      AEl.Style.GradBox.H := AEl.Style.GradBox.H * sy;
    end;
  end;
  AEl.Style.StrokeWidthLogical := AEl.Style.StrokeWidthLogical * Min(Abs(sx), Abs(sy));
end;

{ [F3a] A GRAPH EDGE'S LINE, END SYMBOL OR LABEL at a percent of its line
  (Line.beforeUpdate): the line drawn to it, an end symbol scaled by it
  about its end and carried to pointAt(0) or pointAt(percent), the label
  moved and turned to where beforeUpdate places it }
procedure GraphEdgeFrom(var AEl: TTyChartElement; APercent: Double);
var
  q1, q2, qc, d, d1: TTyPointF;
  cv: Boolean;
  pts: TTyPointFArray;
  k: Integer;
  x, y, s, x1, y1, gx, gy, gx1, gy1, rot, rot1: Double;
  ah, ah1: TTyTextAnchorH;
  av, av1: TTyTextAnchorV;
begin
  if IsNan(APercent) then Exit;
  case AEl.Anim.Role of
    carGraphEdge:
      begin
        TyGraphEdgeLine(AEl, q1, q2, qc, cv);
        pts := TyGraphLinePrefix(q1, q2, qc, cv, APercent);
        for k := 0 to High(pts) do pts[k] := TyGraphEdgeDev(AEl, pts[k]);
        AEl.Shape.Points := pts;
        AEl.Shape.Bounds := TyShapeBounds(TyShapePolyline(pts));
        if not (APercent > 0) then MakeInkless(AEl);
      end;
    carGraphEdgeFrom, carGraphEdgeTo:
      begin
        if not (APercent > 0) then
        begin
          MakeInkless(AEl);
          Exit;
        end;
        TyGraphEdgeEnds(AEl, APercent, AEl.Anim.Role = carGraphEdgeTo, x, y, s);
        TyGraphEdgeEnds(AEl, 1, AEl.Anim.Role = carGraphEdgeTo, x1, y1, s);
        d := TyGraphEdgeDev(AEl, TyPointF(x, y));
        d1 := TyGraphEdgeDev(AEl, TyPointF(x1, y1));
        TyShapeScaleAbout(AEl.Shape, d1.X, d1.Y, APercent, APercent);
        TyShapeMove(AEl.Shape, d.X - d1.X, d.Y - d1.Y);
      end;
    carGraphEdgeLabel:
      begin
        TyGraphEdgeLabelAt(AEl, APercent, gx, gy, rot, ah, av);
        TyGraphEdgeLabelAt(AEl, 1, gx1, gy1, rot1, ah1, av1);
        if IsNan(gx) or IsNan(gy) or IsNan(gx1) or IsNan(gy1) then Exit;
        MoveCaption(AEl, gx - gx1, gy - gy1);
        if not IsNan(rot) and not IsNan(rot1) then
          AEl.Caption.RotationRad := AEl.Caption.RotationRad + (rot - rot1);
        AEl.Caption.AnchorH := ah;
        AEl.Caption.AnchorV := av;
      end;
  end;
end;

{ [F3a] A TREE EDGE AS ITS PROXY HAS IT: the curve's eight numbers, or the
  TreePath's parent and child points (TreePath.buildPath, the fork on the
  dimension and at the place the tag says), each point through the main
  group's frame to the canvas }
procedure TreeEdgeFrom(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
var
  cmds: TTyPathCmdArray;
  pp, ch: TTyAnimValue;
  n, i, fd, od: Integer;
  f: Double;
  tmp: array[0..1] of Double;
  first, last, ci, ppt: array[0..1] of Double;
  r: TTyXYWH;

  function MX(AX, AY: Double): Double;
  begin
    if AEl.Anim.G[8] <> 0 then Result := (AEl.Anim.G[9] * AX + 0 * AY) + AEl.Anim.G[10]
    else Result := AEl.Anim.G[10] + AX;
  end;

  function MY(AX, AY: Double): Double;
  begin
    if AEl.Anim.G[8] <> 0 then Result := (0 * AX + AEl.Anim.G[9] * AY) + AEl.Anim.G[11]
    else Result := AEl.Anim.G[11] + AY;
  end;

  procedure Add(AKind: TTyPathCmdKind; AX1, AY1, AX2, AY2, AX, AY: Double);
  begin
    SetLength(cmds, Length(cmds) + 1);
    cmds[High(cmds)] := Default(TTyPathCmd);
    cmds[High(cmds)].Kind := AKind;
    cmds[High(cmds)].X1 := MX(AX1, AY1);
    cmds[High(cmds)].Y1 := MY(AX1, AY1);
    cmds[High(cmds)].X2 := MX(AX2, AY2);
    cmds[High(cmds)].Y2 := MY(AX2, AY2);
    cmds[High(cmds)].X := MX(AX, AY);
    cmds[High(cmds)].Y := MY(AX, AY);
  end;

  procedure Pt(AKind: TTyPathCmdKind; AX, AY: Double);
  begin
    Add(AKind, 0, 0, 0, 0, AX, AY);
  end;

begin
  cmds := nil;
  if AEl.Anim.Sub = 1 then
  begin
    pp := AProxy.GetAnimProp('shape.parentPoint');
    ch := AProxy.GetAnimProp('shape.childPoints');
    if (pp.Kind <> avkArray) or (ch.Kind <> avkArray) or (Length(pp.Arr) < 2) then Exit;
    n := Length(ch.Arr) div 2;
    if n = 0 then Exit;
    ppt[0] := pp.Arr[0];
    ppt[1] := pp.Arr[1];
    if n = 1 then
    begin
      Pt(pckMove, ppt[0], ppt[1]);
      Pt(pckLine, ch.Arr[0], ch.Arr[1]);
    end
    else
    begin
      fd := Round(AEl.Anim.G[2]);
      od := 1 - fd;
      f := AEl.Anim.G[3];
      first[0] := ch.Arr[0];
      first[1] := ch.Arr[1];
      last[0] := ch.Arr[(n - 1) * 2];
      last[1] := ch.Arr[(n - 1) * 2 + 1];
      tmp[fd] := ppt[fd];
      tmp[od] := ppt[od] + (last[od] - ppt[od]) * f;
      Pt(pckMove, ppt[0], ppt[1]);
      Pt(pckLine, tmp[0], tmp[1]);
      Pt(pckMove, first[0], first[1]);
      tmp[fd] := first[fd];
      Pt(pckLine, tmp[0], tmp[1]);
      tmp[fd] := last[fd];
      Pt(pckLine, tmp[0], tmp[1]);
      Pt(pckLine, last[0], last[1]);
      for i := 1 to n - 2 do
      begin
        ci[0] := ch.Arr[i * 2];
        ci[1] := ch.Arr[i * 2 + 1];
        Pt(pckMove, ci[0], ci[1]);
        tmp[fd] := ci[fd];
        Pt(pckLine, tmp[0], tmp[1]);
      end;
    end;
  end
  else
  begin
    Pt(pckMove, AProxy.Num('shape.x1'), AProxy.Num('shape.y1'));
    Add(pckCurve, AProxy.Num('shape.cpx1'), AProxy.Num('shape.cpy1'),
      AProxy.Num('shape.cpx2'), AProxy.Num('shape.cpy2'),
      AProxy.Num('shape.x2'), AProxy.Num('shape.y2'));
  end;
  AEl.Shape.Points := [TyPointF(cmds[0].X, cmds[0].Y),
    TyPointF(cmds[High(cmds)].X, cmds[High(cmds)].Y)];
  AEl.Shape.Cmds := cmds;
  r := TyPathCmdsRect(cmds);
  AEl.Shape.HasCmdBounds := True;
  AEl.Shape.CmdBounds := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
end;

procedure TyAnimApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
var
  x, y, fx, fy, a, d, c, s, cx, cy, tx, ty, lx, ly, lx1, ly1, bw, bh, rest: Double;
  r: TTyRectF;
  v: TTyAnimValue;
  i, n, ah, av, ah1, av1, flags: Integer;
  pts: TTyPointFArray;
  mg: TTyDoubleArray;
begin
  { A LINES EFFECT SYMBOL is where its run is, whatever its keys say
    [Batch 121] }
  if (AProxy <> nil) and (AEl.Anim.Role = carLinesEffect) then
  begin
    TyLinesFrameEffect(AEl, AProxy.FEff, AProxy.FEffGone);
    Exit;
  end;
  if (AProxy = nil) or AProxy.AtFinal then Exit;
  case AEl.Anim.Role of
    carParallelLine:
      begin
        { the data group's clip while it grows [Batch 128] }
        x := AProxy.Num('shape.x');
        y := AProxy.Num('shape.y');
        AEl.HasClip := True;
        AEl.ClipRect := TyRectF(x, y, x + AProxy.Num('shape.width'),
          y + AProxy.Num('shape.height'));
      end;
    carGraphEdge, carGraphEdgeFrom, carGraphEdgeTo:
      GraphEdgeFrom(AEl, AProxy.Num('shape.percent'));
    carTreeEdge:
      TreeEdgeFrom(AEl, AProxy);
    carGraphEdgeLabel:
      begin
        { [F3a] the fade, over the opacity the list gives it (a state's) }
        rest := AProxy.FinalOf('style.opacity').Num;
        a := AProxy.Num('style.opacity');
        if not (a > 0) then MakeInkless(AEl)
        else if rest > 0 then AEl.Style.Alpha := AEl.Style.Alpha * (a / rest)
        else AEl.Style.Alpha := a;
      end;
    carPictorialGlyph:
      begin
        { [F3a] the glyph scaled about its place by the scale now over its
          scale at rest }
        if AEl.Anim.G[2] <> 0 then fx := AProxy.Num('scaleX') / AEl.Anim.G[2] else fx := 1;
        if AEl.Anim.G[3] <> 0 then fy := AProxy.Num('scaleY') / AEl.Anim.G[3] else fy := 1;
        if (fx = 0) or (fy = 0) or IsNan(fx) or IsNan(fy) then MakeInkless(AEl)
        else
        begin
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], fx, fy);
          { [F3b] and turned by where its turn is now against its turn at
            rest (a uniform scale and a turn about one point commute) }
          if (AEl.Anim.G[6] <> 0) and (AProxy.GetAnimProp('rotation').Kind = avkNumber) then
            TyShapeRotateAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1],
              AProxy.Num('rotation') - AEl.Anim.G[5]);
        end;
      end;
    carPictorialClip:
      begin
        { [F3a] the bundle's clip along the value axis, from the floor to the
          length it has now; across it, the whole canvas -- and the plot
          where the plot clips }
        if AEl.Anim.G[1] <> 0 then
        begin
          a := AProxy.Num('shape.height');
          r := TyRectF(-1000000, Min(AEl.Anim.G[0], AEl.Anim.G[0] + a), 1000000,
            Max(AEl.Anim.G[0], AEl.Anim.G[0] + a));
        end
        else
        begin
          a := AProxy.Num('shape.width');
          r := TyRectF(Min(AEl.Anim.G[0], AEl.Anim.G[0] + a), -1000000,
            Max(AEl.Anim.G[0], AEl.Anim.G[0] + a), 1000000);
        end;
        if AEl.Anim.G[3] <> 0 then
          r := TyRectF(Max(r.Left, AEl.Anim.G[4]), Max(r.Top, AEl.Anim.G[5]),
            Min(r.Right, AEl.Anim.G[6]), Min(r.Bottom, AEl.Anim.G[7]));
        AEl.HasClip := True;
        AEl.ClipRect := r;
      end;
    carSankeyClip:
      begin
        { [F3a] the main group's clip while it grows: its rect in the
          group's frame carried to the canvas (M0, M3, M4, M5) }
        x := AProxy.Num('shape.x');
        y := AProxy.Num('shape.y');
        fx := x + AProxy.Num('shape.width');
        fy := y + AProxy.Num('shape.height');
        x := AEl.Anim.G[4] * x + AEl.Anim.G[6];
        y := AEl.Anim.G[5] * y + AEl.Anim.G[7];
        fx := AEl.Anim.G[4] * fx + AEl.Anim.G[6];
        fy := AEl.Anim.G[5] * fy + AEl.Anim.G[7];
        r := TyRectF(Min(x, fx), Min(y, fy), Max(x, fx), Max(y, fy));
        if AEl.HasClip then
          r := TyRectF(Max(r.Left, AEl.ClipRect.Left), Max(r.Top, AEl.ClipRect.Top),
            Min(r.Right, AEl.ClipRect.Right), Min(r.Bottom, AEl.ClipRect.Bottom));
        AEl.HasClip := True;
        AEl.ClipRect := r;
      end;
    carLinesLine:
      TyLinesFrameLine(AEl, AProxy.Num('shape.percent'));
    carLinesFrom, carLinesTo:
      TyLinesFrameSymbol(AEl, AProxy.Num('shape.percent'));
    carLinesLabel:
      TyLinesFrameLabel(AEl, AProxy.Num('shape.percent'));
    carBar:
      BarFrom(AEl, AProxy);
    carSymbol, carLineSymbol, carEffectSymbol, carTreeNode:
      begin
        if AEl.Anim.Role in [carSymbol, carEffectSymbol, carTreeNode] then
        begin
          if AEl.Anim.G[2] <> 0 then fx := AProxy.Num('scaleX') / AEl.Anim.G[2]
          else fx := 1;
          if AEl.Anim.G[3] <> 0 then fy := AProxy.Num('scaleY') / AEl.Anim.G[3]
          else fy := 1;
          { an effect symbol's opacity tween moves a style no one draws }
          if AEl.Anim.Role in [carSymbol, carTreeNode] then
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
        { a tree node's group is a proxy of its own (the frame moves it) }
        else if AEl.Anim.Role = carTreeNode then
        else
          MoveSymbol(AEl, NumOr(AProxy, 'x', AEl.Anim.G[0]) - AEl.Anim.G[0],
            NumOr(AProxy, 'y', AEl.Anim.G[1]) - AEl.Anim.G[1]);
      end;
    carPolarBar:
      PolarBarFrom(AEl, AProxy);
    carChord:
      { THE VIEW GROUP'S SCALE about its origin: the sector, the ribbon,
        their gradients and their strokes with it -- the labels are not the
        group's (a text that is not local takes no parent) [Batch 120] }
      ChordFrom(AEl, AProxy);
    carRiver:
      begin
        { the polygon cut to its clip rect, in the group's frame
          [Batch 118] }
        x := AProxy.Num('shape.x');
        y := AProxy.Num('shape.y') + AEl.Anim.G[4];
        AEl.HasClip := True;
        AEl.ClipRect := TyRectF(x, y, x + AProxy.Num('shape.width'),
          y + AProxy.Num('shape.height'));
      end;
    carLineRun, carLineArea:
      if (Round(AEl.Anim.G[5]) and 8) <> 0 then
      begin
        AEl.HasClipSector := True;
        AEl.ClipCX := NumOr(AProxy, 'shape.cx', AEl.ClipCX);
        AEl.ClipCY := NumOr(AProxy, 'shape.cy', AEl.ClipCY);
        AEl.ClipR0 := NumOr(AProxy, 'shape.r0', AEl.ClipR0);
        AEl.ClipR1 := NumOr(AProxy, 'shape.r', AEl.ClipR1);
        AEl.ClipSA := NumOr(AProxy, 'shape.startAngle', AEl.ClipSA);
        AEl.ClipEA := NumOr(AProxy, 'shape.endAngle', AEl.ClipEA);
      end
      else
      begin
        x := AProxy.Num('shape.x');
        y := AProxy.Num('shape.y');
        AEl.HasClip := True;
        AEl.ClipRect := TyRectF(x, y, x + AProxy.Num('shape.width'),
          y + AProxy.Num('shape.height'));
      end;
    carSector, carGaugeProgress:
      AEl.Shape := SectorFrom(AEl, AProxy);
    carSunPiece:
      { the ring as the proxy has it now [Batch 115] }
      AEl.Shape := SunPieceFrom(AEl, AProxy);
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
            { [Batch 108: no whole pixel for a doji, as the static body] }
            r := TyRectF(v.Arr[0], Min(v.Arr[1], v.Arr[5]), v.Arr[2],
              Max(v.Arr[1], v.Arr[5]));
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
    carBoxplot:
      begin
        { the path again from the fourteen points: the box, then the
          whiskers and the caps [Batch 108] }
        v := AProxy.GetAnimProp('shape.points');
        if Length(v.Arr) < 28 then Exit;
        AEl.Shape := TyBoxplotShape(v.Arr);
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
        { A SMOOTH LINE follows its moving points; drawing in, it is drawn
          straight [Batch 112] }
        if Length(AEl.Shape.Cmds) > 0 then
        begin
          if a < 1 then AEl.Shape.Cmds := nil
          else AEl.Shape.Cmds := TyLabelLineCmds(AEl.Shape.Points, AEl.Caption.LgSmooth);
        end;
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
          { the fade over what the list holds: the symbol's own opacity at
            rest, a blurred series' marker a tenth of it [F2b] }
          rest := Max(0.0, Min(1.0, AEl.Anim.G[4]));
          if rest > 0 then
            AEl.Style.Alpha := Min(1.0, a) * (AEl.Style.Alpha / rest)
          else
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
  { one string twice parses to one answer: at rest every state key's value
    is its rest's, and an animation frame asked that of every element
    [P2] }
  if (A.Kind = avkString) and (B.Kind = avkString) and (A.Str = B.Str) then
    Exit(True);
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
      { a label's is a factor over its own, as its fade's is -- unless no
        fade shares its proxy [F3a] }
      if (AEl.Caption.FontSizeLogical > 0) and not AProxy.FStAbs then
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
      if AEl.Anim.Role in [carLineSymbol, carSymbol, carEffectSymbol, carTreeNode] then
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
    carPolarBar:
      if G.GetAnimProp('shape.cx').Kind = avkNumber then PolarBarFrom(AEl, G);
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
  sec: TTyPolarSector;
  b: TTyRectF;
  atX, atY: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  box: TTyXYWH;
begin
  { a polar bar's sector position, on the sector as drawn [Batch 113] }
  if AHost.Caption.SecHas and (ALabel.Anim.LabelPos >= 100) then
  begin
    sec.CX := AHost.Anim.G[0];
    sec.CY := AHost.Anim.G[1];
    sec.R0 := AHost.Anim.G[2];
    sec.R := AHost.Anim.G[3];
    sec.SA := AHost.Anim.G[4];
    sec.EA := AHost.Anim.G[5];
    sec.CW := AHost.Anim.G[6] <> 0;
    TySectorLabelAnchor(sec, TTySectorTextPos(ALabel.Anim.LabelPos - 100),
      ALabel.Anim.LabelDist, AHost.Anim.G[8] <> 0, AX, AY, ah, av);
    Exit;
  end;
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

{ ==================== the universal transition [Batch 136, D5 UT1] ==================== }

type
  { one flattened data item of a transition's side (flattenDataDiffItems):
    its series (by series index), its view row, getId, and the keys UT2 and
    UT3 read -- groupId (always a string: getGroupId falls back on the id)
    and childGroupId (HasChild False: undefined) [Batch 138] }
  TUtItem = record
    Series, Row: Integer;
    Id, Group, Child: string;
    HasChild: Boolean;
    { its series' divideShape [Batch 137] }
    Divide: string;
  end;
  TUtItemArray = array of TUtItem;

const
  { DATA_COUNT_THRESHOLD }
  cUtDataLimit = 10000;
  { TRANSITION_NONE, TRANSITION_P2C, TRANSITION_C2P [Batch 138] }
  cUtDirNone = 0;
  cUtDirP2C = 1;
  cUtDirC2P = 2;

function TyUtEnabled(AOwn: TJSONData): Boolean;
var u, e: TJSONData;
begin
  Result := False;
  if not (AOwn is TJSONObject) then Exit;
  u := TJSONObject(AOwn).Find('universalTransition');
  if u = nil then Exit;
  { `=== true`, or an object's `enabled`: a number, a string or a list has
    no `enabled` }
  case u.JSONType of
    jtBoolean: Result := u.AsBoolean;
    jtObject:
      begin
        { universalTransitionOpt.enabled, truthy }
        e := TJSONObject(u).Find('enabled');
        if e = nil then Exit;
        case e.JSONType of
          jtBoolean: Result := e.AsBoolean;
          jtNumber: Result := (not IsNan(e.AsFloat)) and (e.AsFloat <> 0);
          jtString: Result := e.AsString <> '';
          jtArray, jtObject: Result := True;
        end;
      end;
  end;
end;

function TyUtGet(AOwn, ARoot: TJSONData; const ASeriesType, AKey: string): TJSONData;
var u: TJSONData;
begin
  Result := nil;
  u := nil;
  if AOwn is TJSONObject then u := TJSONObject(AOwn).Find('universalTransition');
  if u is TJSONObject then
  begin
    Result := TJSONObject(u).Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
    if Result <> nil then Exit;
  end;
  { the type's own default object merges under an object (or nothing);
    a `true` keeps it out: get on a boolean falls through to the parent }
  if ((u = nil) or (u is TJSONObject)) and (AKey = 'divideShape')
    and ((ASeriesType = 'line') or (ASeriesType = 'scatter')
    or (ASeriesType = 'effectScatter')) then Exit(nil);
  { the parent model: the root option's universalTransition }
  if ARoot is TJSONObject then
  begin
    u := TJSONObject(ARoot).Find('universalTransition');
    if u is TJSONObject then
    begin
      Result := TJSONObject(u).Find(AKey);
      if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
    end;
  end;
end;

{ the type default divideShape is 'clone' for those three; TyUtGet answers
  nil there so that a caller tells it from a written one -- here it is read }
function UtDivideOf(AOwn, ARoot: TJSONData; const ASeriesType: string): string;
var d, u: TJSONData;
begin
  d := TyUtGet(AOwn, ARoot, ASeriesType, 'divideShape');
  if (d <> nil) and (d.JSONType = jtString) then Exit(d.AsString);
  u := nil;
  if AOwn is TJSONObject then u := TJSONObject(AOwn).Find('universalTransition');
  if ((u = nil) or (u is TJSONObject)) and ((ASeriesType = 'line')
    or (ASeriesType = 'scatter') or (ASeriesType = 'effectScatter')) then
    Exit('clone');
  Result := '';
end;

{ a typed key: 's:' a string, 'n:' a number, 'b:' a boolean -- zrender's
  HashMap is a Map, which tells 5 from '5' }
function UtTypedKey(D: TJSONData): string;
begin
  case D.JSONType of
    jtString: Result := 's:' + D.AsString;
    jtNumber: Result := 'n:' + TyJsNumberToString(D.AsFloat);
    jtBoolean: if D.AsBoolean then Result := 'b:true' else Result := 'b:false';
  else
    Result := 's:' + D.AsJSON;
  end;
end;

{ a JavaScript value's String(): what join writes }
function UtJoinText(D: TJSONData): string;
begin
  case D.JSONType of
    jtString: Result := D.AsString;
    jtNumber: Result := TyJsNumberToString(D.AsFloat);
    jtBoolean: if D.AsBoolean then Result := 'true' else Result := 'false';
    jtNull: Result := '';
  else
    Result := '[object Object]';
  end;
end;

function TyUtTransitionKey(AOwn, ARoot: TJSONData; const ASeriesType, AId: string;
  out AIsList: Boolean): string;
var items: TTyStringArray;
begin
  Result := TyUtTransitionKey(AOwn, ARoot, ASeriesType, AId, AIsList, items);
end;

function TyUtTransitionKey(AOwn, ARoot: TJSONData; const ASeriesType, AId: string;
  out AIsList: Boolean; out AItems: TTyStringArray): string;
var
  k: TJSONData;
  parts, typed: TTyStringArray;
  i, j: Integer;
  t, tt: string;
  falsy: Boolean;
begin
  AIsList := False;
  AItems := nil;
  k := TyUtGet(AOwn, ARoot, ASeriesType, 'seriesKey');
  falsy := k = nil;
  if not falsy then
    case k.JSONType of
      jtString: falsy := k.AsString = '';
      jtNumber: falsy := IsNan(k.AsFloat) or (k.AsFloat = 0);
      jtBoolean: falsy := not k.AsBoolean;
    end;
  { the series' id by default }
  if falsy then Exit('s:' + AId);
  if k.JSONType <> jtArray then Exit(UtTypedKey(k));
  { a list: sort() (by the items' strings, code unit order) and join(',') --
    order independent }
  AIsList := True;
  SetLength(parts, k.Count);
  SetLength(typed, k.Count);
  for i := 0 to k.Count - 1 do
  begin
    parts[i] := UtJoinText(k.Items[i]);
    typed[i] := UtTypedKey(k.Items[i]);
  end;
  for i := 1 to High(parts) do
  begin
    t := parts[i];
    tt := typed[i];
    j := i - 1;
    while (j >= 0) and (CompareStr(parts[j], t) > 0) do
    begin
      parts[j + 1] := parts[j];
      typed[j + 1] := typed[j];
      Dec(j);
    end;
    parts[j + 1] := t;
    typed[j + 1] := tt;
  end;
  AItems := typed;
  t := '';
  for i := 0 to High(parts) do
  begin
    if i > 0 then t := t + ',';
    t := t + parts[i];
  end;
  Result := 's:' + t;
end;

procedure TyUtSeriesInfo(var ASeries: TTyChartAnimSeries; ARoot: TJSONData;
  const AId: string);
var
  own, d: TJSONData;
begin
  own := ASeries.Model.Own;
  ASeries.UtOn := TyUtEnabled(own);
  ASeries.UtKey := TyUtTransitionKey(own, ARoot, ASeries.SeriesType, AId, ASeries.UtKeyList,
    ASeries.UtKeyItems);
  ASeries.UtDivide := UtDivideOf(own, ARoot, ASeries.SeriesType);
  ASeries.UtDelay := '';
  d := TyUtGet(own, ARoot, ASeries.SeriesType, 'delay');
  if (d <> nil) and (d.JSONType = jtString) and (Copy(d.AsString, 1, 1) = '@') then
    ASeries.UtDelay := Copy(d.AsString, 2, MaxInt);
end;

{ a JavaScript value's truthiness }
function UtTruthy(D: TJSONData): Boolean;
begin
  if D = nil then Exit(False);
  case D.JSONType of
    jtString: Result := D.AsString <> '';
    jtNumber: Result := (not IsNan(D.AsFloat)) and (D.AsFloat <> 0);
    jtBoolean: Result := D.AsBoolean;
    jtArray, jtObject: Result := True;
  else
    Result := False;
  end;
end;

{ String(v): a list joins its items' (null and undefined as '') }
function UtJsString(D: TJSONData): string;
var i: Integer;
begin
  if D = nil then Exit('undefined');
  case D.JSONType of
    jtArray:
      begin
        Result := '';
        for i := 0 to D.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          if D.Items[i].JSONType <> jtNull then Result := Result + UtJsString(D.Items[i]);
        end;
      end;
    jtNull: Result := 'null';
  else
    Result := UtJoinText(D);
  end;
end;

{ getDataItemValue: an object's `value`, anything else itself }
function UtItemValue(AItem: TJSONData): TJSONData;
begin
  Result := AItem;
  if AItem is TJSONObject then Result := TJSONObject(AItem).Find('value');
end;

{ THE ENCODED GROUP DIMENSION [Batch 138]: the dimension encode[AVisual]
  names (its first entry: a name the series' `dimensions` declares, or a
  position under the dimension count), at APos of the items' values, and
  how it stores -- AKind 0 ordinal (the value as it is), 1 a number, 2 an
  Int32. Its type is the declared one, else doGuessOrdinal's over the
  first five items: the first that tells decides (a number-like value but
  '': not ordinal; other text but '-': ordinal), an item whose value is no
  array says not, none telling says not. False: no such dimension. }
function UtEncodedDim(AOwn: TJSONObject; const AVisual: string; out APos: Integer;
  out AKind: Integer): Boolean;
var
  enc, e, dims, def, data, v, c, tp: TJSONData;
  i, width: Integer;
  nm, s: string;
  told: Boolean;
begin
  Result := False;
  APos := -1;
  AKind := 1;
  enc := AOwn.Find('encode');
  if not (enc is TJSONObject) then Exit;
  e := TJSONObject(enc).Find(AVisual);
  if e is TJSONArray then
  begin
    if e.Count = 0 then Exit;
    e := e.Items[0];
  end;
  if e = nil then Exit;
  dims := AOwn.Find('dimensions');
  if not (dims is TJSONArray) then dims := nil;
  data := AOwn.Find('data');
  if not (data is TJSONArray) then data := nil;
  { the dimension count: the declared ones, else the first item's width }
  width := 0;
  if dims <> nil then width := dims.Count;
  if (data <> nil) and (data.Count > 0) then
  begin
    v := UtItemValue(data.Items[0]);
    if (v is TJSONArray) and (v.Count > width) then width := v.Count;
  end;
  case e.JSONType of
    jtString:
      begin
        if dims = nil then Exit;
        nm := e.AsString;
        for i := 0 to dims.Count - 1 do
        begin
          def := dims.Items[i];
          if def is TJSONObject then
          begin
            c := TJSONObject(def).Find('name');
            if (c <> nil) and (c.JSONType = jtString) then s := c.AsString else s := '';
          end
          else if def.JSONType = jtString then s := def.AsString
          else s := '';
          if (s <> '') and (s = nm) then
          begin
            APos := i;
            Break;
          end;
        end;
      end;
    jtNumber:
      if (Frac(e.AsFloat) = 0) and (e.AsFloat >= 0) and (e.AsFloat < width) then
        APos := Trunc(e.AsFloat);
  end;
  if (APos < 0) or (APos >= width) then Exit;
  Result := True;
  { a declared type }
  if (dims <> nil) and (APos < dims.Count) and (dims.Items[APos] is TJSONObject) then
  begin
    tp := TJSONObject(dims.Items[APos]).Find('type');
    if (tp <> nil) and (tp.JSONType = jtString) then
    begin
      if tp.AsString = 'ordinal' then AKind := 0
      else if tp.AsString = 'int' then AKind := 2;
      Exit;
    end;
  end;
  { guessOrdinal }
  if data = nil then Exit;
  told := False;
  for i := 0 to Min(data.Count, 5) - 1 do
  begin
    v := UtItemValue(data.Items[i]);
    if not (v is TJSONArray) then Break;
    if APos >= v.Count then Continue;
    c := v.Items[APos];
    case c.JSONType of
      jtNumber: told := True;
      jtBoolean: told := True;
      jtString:
        if c.AsString = '' then
        begin
          { Number('') is 0, but `val !== ''` fails first: '' is text }
          AKind := 0;
          told := True;
        end
        else if not IsNan(TyParseNumberText(c.AsString))
          and not IsInfinite(TyParseNumberText(c.AsString)) then
          told := True
        else if c.AsString <> '-' then
        begin
          AKind := 0;
          told := True;
        end;
    end;
    if told then Break;
  end;
end;

{ getValueByDimension on item AItem: what the dimension stored, + '' }
function UtDimString(AItem: TJSONData; APos, AKind: Integer): string;
var
  v, c: TJSONData;
  x: Double;
begin
  c := nil;
  if AItem <> nil then
  begin
    v := UtItemValue(AItem);
    if v is TJSONArray then
    begin
      if APos < v.Count then c := v.Items[APos];
    end
    else
      c := v;
  end;
  if AKind = 0 then Exit(UtJsString(c));
  { parseDataValue: null, undefined and '' are NaN, else Number() }
  x := NaN;
  if c <> nil then
    case c.JSONType of
      jtNumber: x := c.AsFloat;
      jtBoolean: if c.AsBoolean then x := 1 else x := 0;
      jtString: x := TyParseNumberText(c.AsString);
    end;
  if AKind = 2 then
  begin
    { an Int32Array cell }
    if IsNan(x) or IsInfinite(x) then x := 0
    else
    begin
      { ToInt32: the whole part modulo 2^32, as a signed 32-bit integer }
      x := Int(x);
      x := x - JsFloor(x / 4294967296.0) * 4294967296.0;
      if x >= 2147483648.0 then x := x - 4294967296.0;
    end;
  end;
  Result := TyJsNumberToString(x);
end;

function TyUtSeriesKeysOf(AOwn, ARoot: TJSONData; const ASeriesType,
  AId: string): TTyUtSeriesKeys;
var
  dg, data, it, g: TJSONData;
  i, gPos, gKind, cPos, cKind: Integer;
  gDim, cDim: Boolean;
begin
  Result := Default(TTyUtSeriesKeys);
  Result.Key := TyUtTransitionKey(AOwn, ARoot, ASeriesType, AId, Result.List, Result.Items);
  Result.Divide := UtDivideOf(AOwn, ARoot, ASeriesType);
  { series.get('dataGroupId'): its own, else the root option's }
  dg := nil;
  if AOwn is TJSONObject then dg := TJSONObject(AOwn).Find('dataGroupId');
  if ((dg = nil) or (dg.JSONType = jtNull)) and (ARoot is TJSONObject) then
    dg := TJSONObject(ARoot).Find('dataGroupId');
  if UtTruthy(dg) then Result.GroupDefault := '=' + UtJsString(dg);
  Result.DataGroup := Result.GroupDefault;
  Result.ModelId := AId;
  { [Batch 138] the encoded dimensions first }
  gDim := (AOwn is TJSONObject) and UtEncodedDim(TJSONObject(AOwn), 'itemGroupId', gPos, gKind);
  cDim := (AOwn is TJSONObject) and UtEncodedDim(TJSONObject(AOwn), 'itemChildGroupId', cPos, cKind);
  if gDim then Result.GroupDefault := '=' + UtDimString(nil, gPos, gKind);
  if gDim then Result.GroupOwnDefault := Result.GroupDefault;
  if cDim then Result.ChildDefault := '=' + UtDimString(nil, cPos, cKind);
  { the raw data item's groupId and childGroupId }
  data := nil;
  if AOwn is TJSONObject then data := TJSONObject(AOwn).Find('data');
  if data is TJSONArray then
  begin
    SetLength(Result.GroupsByRaw, data.Count);
    SetLength(Result.GroupsOwnByRaw, data.Count);
    SetLength(Result.ChildByRaw, data.Count);
    for i := 0 to data.Count - 1 do
    begin
      it := data.Items[i];
      if gDim then
      begin
        Result.GroupsByRaw[i] := '=' + UtDimString(it, gPos, gKind);
        Result.GroupsOwnByRaw[i] := Result.GroupsByRaw[i];
      end
      else
      begin
        g := nil;
        if it is TJSONObject then g := TJSONObject(it).Find('groupId');
        if UtTruthy(g) then Result.GroupsByRaw[i] := '=' + UtJsString(g)
        else Result.GroupsByRaw[i] := Result.GroupDefault;
        if UtTruthy(g) then Result.GroupsOwnByRaw[i] := Result.GroupsByRaw[i]
        else Result.GroupsOwnByRaw[i] := '';
      end;
      if cDim then
        Result.ChildByRaw[i] := '=' + UtDimString(it, cPos, cKind)
      else
      begin
        g := nil;
        if it is TJSONObject then g := TJSONObject(it).Find('childGroupId');
        if UtTruthy(g) then Result.ChildByRaw[i] := '=' + UtJsString(g)
        else Result.ChildByRaw[i] := '';
      end;
    end;
  end;
end;

function TyUtRowGroups(const AKeys: TTyUtSeriesKeys; const ARaws: TTyIntegerArray): TTyStringArray;
var r: Integer;
begin
  SetLength(Result, Length(ARaws));
  for r := 0 to High(ARaws) do
    if (ARaws[r] >= 0) and (ARaws[r] <= High(AKeys.GroupsByRaw)) then
      Result[r] := AKeys.GroupsByRaw[ARaws[r]]
    else
      Result[r] := AKeys.GroupDefault;
end;

function TyUtRowChildGroups(const AKeys: TTyUtSeriesKeys; const ARaws: TTyIntegerArray): TTyStringArray;
var r: Integer;
begin
  SetLength(Result, Length(ARaws));
  for r := 0 to High(ARaws) do
    if (ARaws[r] >= 0) and (ARaws[r] <= High(AKeys.ChildByRaw)) then
      Result[r] := AKeys.ChildByRaw[ARaws[r]]
    else
      Result[r] := AKeys.ChildDefault;
end;

function TyUtRowGroupsOwn(const AKeys: TTyUtSeriesKeys; const ARaws: TTyIntegerArray): TTyStringArray;
var r: Integer;
begin
  SetLength(Result, Length(ARaws));
  for r := 0 to High(ARaws) do
    if (ARaws[r] >= 0) and (ARaws[r] <= High(AKeys.GroupsOwnByRaw)) then
      Result[r] := AKeys.GroupsOwnByRaw[ARaws[r]]
    else
      Result[r] := AKeys.GroupOwnDefault;
end;

function TyUtRowGroupsWith(const AOwn: TTyStringArray; const ADataGroup: string): TTyStringArray;
var r: Integer;
begin
  SetLength(Result, Length(AOwn));
  for r := 0 to High(AOwn) do
    if AOwn[r] <> '' then Result[r] := AOwn[r] else Result[r] := ADataGroup;
end;

function TyUtFinderMatches(const AF: TTyUtFinder; AIndex: Integer; const AModelId: string): Boolean;
begin
  Result := (AF.HasIndex and (AF.Index = AIndex)) or (AF.HasId and (AF.Id = AModelId));
end;

procedure TyUtParseTransition(AData: TJSONData; out AHas: Boolean;
  out AItems: TTyUtTransitionArray);

  function Finders(D: TJSONData): TTyUtFinderArray;
  var
    k: Integer;
    res: TTyUtFinderArray;

    procedure Add(E: TJSONData);
    var
      fd: TTyUtFinder;
      x: TJSONData;
    begin
      { querySeries reads it as an object; anything else matches nothing }
      fd := Default(TTyUtFinder);
      if E is TJSONObject then
      begin
        x := TJSONObject(E).Find('seriesIndex');
        if (x <> nil) and (x.JSONType = jtNumber) then
        begin
          fd.HasIndex := True;
          fd.Index := x.AsFloat;
        end;
        x := TJSONObject(E).Find('seriesId');
        if (x <> nil) and (x.JSONType = jtString) then
        begin
          fd.HasId := True;
          fd.Id := x.AsString;
        end;
      end;
      SetLength(res, Length(res) + 1);
      res[High(res)] := fd;
    end;

  begin
    res := nil;
    { normalizeToArray: null / undefined none, an array itself, else one }
    if (D <> nil) and (D.JSONType <> jtNull) then
    begin
      if D is TJSONArray then
      begin
        for k := 0 to D.Count - 1 do Add(D.Items[k]);
      end
      else
        Add(D);
    end;
    Result := res;
  end;

  procedure AddItem(E: TJSONData);
  var it: TTyUtTransitionItem;
  begin
    it := Default(TTyUtTransitionItem);
    if E is TJSONObject then
    begin
      it.From := Finders(TJSONObject(E).Find('from'));
      it.To_ := Finders(TJSONObject(E).Find('to'));
    end;
    SetLength(AItems, Length(AItems) + 1);
    AItems[High(AItems)] := it;
  end;

var k: Integer;
begin
  AItems := nil;
  { `if (transitionOpt)`: a truthy value -- an object or a list always }
  AHas := UtTruthy(AData) or (AData is TJSONArray) or (AData is TJSONObject);
  if not AHas then Exit;
  if AData is TJSONArray then
  begin
    for k := 0 to AData.Count - 1 do AddItem(AData.Items[k]);
  end
  else
    AddItem(AData);
end;

procedure TTyChartAnimProxy.MorphDone;
begin
  { restoreToPath: the element's own path again }
  FMorphOn := False;
end;

destructor TTyChartAnimProxy.Destroy;
begin
  ClearPieces;
  inherited Destroy;
end;

procedure TTyChartAnimProxy.ClearPieces;
var i: Integer;
begin
  for i := 0 to High(FPieces) do FPieces[i].Free;
  FPieces := nil;
end;

function TTyChartAnimProxy.PieceCount: Integer;
begin
  Result := Length(FPieces);
end;

function TTyChartAnimProxy.Piece(AIndex: Integer): TTyChartAnimProxy;
begin
  Result := FPieces[AIndex];
end;

procedure TTyChartAnimProxy.CombineDuring(APercent: Double);
var
  i: Integer;
  v: TTyAnimValue;
begin
  { child.__morphT = toPath.__morphT }
  v := GetAnimProp('__morphT');
  for i := 0 to High(FPieces) do FPieces[i].SetAnimProp('__morphT', v);
end;

procedure TTyChartAnimProxy.CombineDone;
begin
  { restoreToPath: no longer combining, __morphT -1 }
  FCombineOn := False;
  SetNum('__morphT', -1);
end;

procedure TTyChartAnimProxy.PieceMorphDone;
begin
  { the piece's own morphPath done (restoreToPath), then eachDone }
  FMorphOn := False;
  SetNum('__morphT', -1);
  if FHost = nil then Exit;
  Dec(FHost.FCombineLeft);
  if FHost.FCombineLeft = 0 then FHost.CombineDone;
end;

procedure TTyChartAnimProxy.UtStyleDone;
begin
  FUtStyleOn := False;
end;

{ the role a universal transition morphs: a bar's rect, a pie's slice, a
  scatter's symbol path, a line's symbol -- the item graphic elements of the
  four types UT1 transitions ('' for anything else); [Batch 138] a
  sunburst's piece (not the virtual root's return circle) and a treemap
  node's path getPathList takes -- a leaf's content (its background is
  disableMorphing), a parent's background }
function UtHostRole(const AEl: TTyChartElement): string;
begin
  case AEl.Anim.Role of
    carBar: Result := 'bar';
    carSector: Result := 'sector';
    carSymbol: Result := 'symbol';
    carLineSymbol: Result := 'lineSymbol';
    carSunPiece:
      if AEl.Anim.Index > 0 then Result := 'sunPiece' else Result := '';
    carTmRect:
      if (AEl.Anim.Sub = 1) or ((AEl.Anim.Sub = 0) and (AEl.Anim.G[4] = 0)) then
        Result := 'tmRect'
      else
        Result := '';
    { [F3c] a funnel's polygon, a bar on a polar, a pictorial glyph (a
      picture is no path), a map's region, a lines row's line and end
      symbols, a custom series' path }
    carFunnel: Result := 'funnel';
    carPolarBar: Result := 'bar';
    carPictorialGlyph, carPictorialClip:
      if Copy(AEl.Caption.LgSymbol, 1, 8) = 'image://' then Result := ''
      else Result := 'pglyph' + IntToStr(AEl.Anim.Sub);
    carMapRegion:
      if AEl.Anim.Index >= 0 then Result := 'utMap' + IntToStr(AEl.Anim.Sub) else Result := '';
    carLinesLine: Result := 'utLine0';
    carLinesFrom: Result := 'utLine1';
    carLinesTo: Result := 'utLine2';
    carCustomPath:
      if AEl.Anim.Index >= 0 then Result := 'utCus' + IntToStr(AEl.Anim.Sub) else Result := '';
    { [F3c] a boxplot's path, a radar's line and area (an area ignored is
      no path), a gauge's pointer, an effect scatter's symbol and its
      ripples, a graph's and a tree's node symbols, a parallel's line }
    carBoxplot: Result := 'boxplot';
    carRadarLine: Result := 'radarLine';
    carRadarArea: if AEl.Ignore then Result := '' else Result := 'radarArea';
    carGaugePointer: Result := 'gaugePointer';
    carEffectSymbol: Result := 'effectSymbol';
    carRipple: Result := 'ripple' + IntToStr(AEl.Anim.Sub);
    carTreeNode: Result := 'symbol';
    carParallelLine: Result := 'utPar0';
  else
    Result := '';
  end;
end;

function UtTypeRole(const AType: string): string;
begin
  if AType = 'bar' then Result := 'bar'
  else if AType = 'pie' then Result := 'sector'
  else if AType = 'scatter' then Result := 'symbol'
  else if AType = 'line' then Result := 'lineSymbol'
  else if AType = 'sunburst' then Result := 'sunPiece'
  else if AType = 'treemap' then Result := 'tmRect'
  else Result := '';
end;

{ the proxy a treemap rect's universal transition runs on: its item path's,
  or a leaf background's fade [Batch 138] }
function UtTmRole(const AEl: TTyChartElement): string;
begin
  if UtHostRole(AEl) <> '' then Result := 'tmRect' else Result := 'utFadeTmBg';
end;

{ ==================== the rest of the element types [F3c] ==================== }

{ THE PROXY A PATH'S TRANSITION RUNS ON: its morph, its children while it
  combines, its style -- '' for a path that is no item's (a label, a line's
  run, a treemap leaf's background). Where the role's own proxy is the
  path's alone it is that one; where a role shares one over several paths
  (a lines row's line and end symbols) each path has its own }
function UtElKey(const AEl: TTyChartElement): string;
begin
  if AEl.Anim.UtTag = 1 then
  begin
    if AEl.Anim.UtRow >= 0 then Result := 'utx' + IntToStr(AEl.Anim.UtOrder) else Result := '';
    Exit;
  end;
  if AEl.Anim.UtTag = 2 then Exit('');
  Result := UtHostRole(AEl);
end;

{ the row of the item a path is in: UtRow where the element is tagged }
function UtRowOf(const AEl: TTyChartElement): Integer;
begin
  if AEl.Anim.UtTag > 0 then Result := AEl.Anim.UtRow else Result := AEl.Anim.Index;
end;

{ the path's place in its item's getPathList (the item element's traverse
  order) }
function UtElOrder(const AEl: TTyChartElement): Integer;
begin
  if AEl.Anim.UtTag = 1 then Exit(AEl.Anim.UtOrder);
  case AEl.Anim.Role of
    carPictorialGlyph, carPictorialClip, carMapRegion, carCustomPath: Result := AEl.Anim.Sub;
    carLinesFrom: Result := 1;
    carLinesTo: Result := 2;
    { [F3c] the radar's item group: the line, the area, the symbols; an
      effect symbol's: the symbol, the ripples }
    carRadarArea: Result := 1;
    carRipple: Result := 1 + AEl.Anim.Sub;
  else
    Result := 0;
  end;
end;

{ THE SERIES TYPES whose item paths the port reads and draws for a
  transition; a batch with any other keeps its own animation }
function UtTypeMorphs(const AType: string): Boolean;
begin
  Result := (AType = 'bar') or (AType = 'pie') or (AType = 'scatter') or (AType = 'line')
    or (AType = 'sunburst') or (AType = 'treemap')
    { [F3c] }
    or (AType = 'funnel') or (AType = 'pictorialBar') or (AType = 'map')
    or (AType = 'lines') or (AType = 'custom')
    or (AType = 'heatmap') or (AType = 'boxplot') or (AType = 'candlestick')
    or (AType = 'radar') or (AType = 'gauge') or (AType = 'graph') or (AType = 'tree')
    or (AType = 'effectScatter') or (AType = 'parallel') or (AType = 'sankey')
    or (AType = 'chord') or (AType = 'themeRiver');
end;

{ [F3c] the path's view saved its old style: the type's, and not a ripple
  (made by the effect, never styled again) nor a radar's symbol (made anew
  on every render) }
function UtSavesOldStyleEl(const AType: string; const AEl: TTyChartElement): Boolean;
begin
  Result := ((AType = 'bar') or (AType = 'pie') or (AType = 'scatter') or (AType = 'line')
    or (AType = 'sunburst') or (AType = 'funnel') or (AType = 'boxplot')
    or (AType = 'candlestick') or (AType = 'parallel') or (AType = 'radar')
    or (AType = 'themeRiver') or (AType = 'graph') or (AType = 'tree')
    or (AType = 'effectScatter'))
    and (AEl.Anim.Role <> carRipple) and not ((AType = 'radar') and (AEl.Anim.UtTag = 1));
end;

{ THE VIEWS THAT SAVE THE OLD STYLE of an element they keep (saveOldStyle):
  animateElementStyles has nothing to start from elsewhere }
function UtSavesOldStyle(const AType: string): Boolean;
begin
  Result := (AType = 'bar') or (AType = 'pie') or (AType = 'scatter') or (AType = 'line')
    or (AType = 'sunburst') or (AType = 'funnel');
end;

{ A KEPT VIEW KEEPS THE ITEM'S ELEMENT where its diff pairs the rows -- but
  a map draws its regions anew every time (MapDraw: regionsGroup.removeAll),
  and a custom series makes its items anew while it transitions
  (doesElNeedRecreate: isUniversalTransitionEnabled) }
function UtKeepsElement(const ASeries: TTyChartAnimSeries; const AEl: TTyChartElement): Boolean;
begin
  if ASeries.SeriesType = 'map' then Exit(False);
  if (ASeries.SeriesType = 'custom') and (ASeries.UtOn or ASeries.UtNamed) then Exit(False);
  Result := True;
end;

{ A PATH OF A VIEW THAT IS NO ITEM'S, faded in where anything morphed: its
  own proxy for that ('' for none) }
function UtFadeKey(const AEl: TTyChartElement): string;
begin
  if AEl.Anim.UtTag = 2 then Exit('utFade');
  if AEl.Anim.UtTag = 1 then Exit('');
  if (AEl.Anim.Role = carTmRect) and (UtHostRole(AEl) = '') then Result := 'utFadeTmBg'
  else Result := '';
end;

function TyUtCmdsData(const ACmds: TTyPathCmdArray): TTyDoubleArray;
var
  i, n: Integer;

  procedure Put(V: Double);
  begin
    Result[n] := V;
    Inc(n);
  end;

begin
  SetLength(Result, Length(ACmds) * 7);
  n := 0;
  for i := 0 to High(ACmds) do
    case ACmds[i].Kind of
      pckMove: begin Put(TyZrCodeM); Put(ACmds[i].X); Put(ACmds[i].Y); end;
      pckLine: begin Put(TyZrCodeL); Put(ACmds[i].X); Put(ACmds[i].Y); end;
      pckCurve:
        begin
          Put(TyZrCodeC); Put(ACmds[i].X1); Put(ACmds[i].Y1); Put(ACmds[i].X2);
          Put(ACmds[i].Y2); Put(ACmds[i].X); Put(ACmds[i].Y);
        end;
      pckClose: Put(TyZrCodeZ);
    end;
  SetLength(Result, n);
end;

function TyUtPathKey(const AEl: TTyChartElement): string;
begin
  Result := UtElKey(AEl);
end;

function TyUtPathOrder(const AEl: TTyChartElement): Integer;
begin
  Result := UtElOrder(AEl);
end;

function TyUtPathRow(const AEl: TTyChartElement): Integer;
begin
  Result := UtRowOf(AEl);
end;

procedure UtElementPathEx(const AEl: TTyChartElement; P, AMorphP: TTyChartAnimProxy;
  out AData: TTyDoubleArray; out AHasM: Boolean; out AM: TTyMat2D;
  out AHasLocal: Boolean; out ALocal: TTyMat2D); forward;

procedure TyUtLayoutPath(const AEl: TTyChartElement; out AData: TTyDoubleArray;
  out AHasM: Boolean; out AM: TTyMat2D);
var
  hasLocal: Boolean;
  local: TTyMat2D;
begin
  UtElementPathEx(AEl, nil, nil, AData, AHasM, AM, hasLocal, local);
end;

{ the proxy a path's shape is read from: its role's where that is not the
  transition's own }
function UtShapeProxy(ASet: TTyChartAnimSet; const AEl: TTyChartElement;
  AUtP: TTyChartAnimProxy): TTyChartAnimProxy;
var rk: string;
begin
  rk := TyChartAnimRoleKey(AEl);
  if (rk = '') or (rk = UtElKey(AEl)) or (AEl.Anim.UtTag = 1) then Exit(AUtP);
  Result := ASet.Find(AEl.Anim.Series, KeyIndexOf(AEl), rk);
end;

{ a symbol as SymbolDraw builds it, with its path's scale and its group's
  place and scale as they are now: the path data and its computed transform,
  and the path's own (local) transform }
procedure UtSymbolPath(const AType: string; AKeepAspect: Boolean; ASX, ASY,
  ARotateDeg, AOffX, AOffY, AGX, AGY, AGSX, AGSY: Double; out AData: TTyDoubleArray;
  out AHasM: Boolean; out AM: TTyMat2D; out AHasLocal: Boolean; out ALocal: TTyMat2D);
var
  path: TTyZrPath;
  rot: Double;
  parent: TTyMat2D;
  hasParent: Boolean;
begin
  if (Copy(AType, 1, 7) = 'path://') and not AKeepAspect then
    path := TyZrMakePathCover(Copy(AType, 8, MaxInt), TyXYWH(-1, -1, 2, 2))
  else
    path := TyZrSymbol(AType, -1, -1, 2, 2);
  AData := TyGuidePathData(path);
  rot := ARotateDeg * Pi / 180;
  if IsNan(rot) then rot := 0;
  AHasLocal := TyLabelLocalTransform(AOffX, AOffY, 0, 0, rot, ASX, ASY, ALocal);
  hasParent := TyLabelLocalTransform(AGX, AGY, 0, 0, 0, AGSX, AGSY, parent);
  AHasM := AHasLocal or hasParent;
  if AHasLocal and hasParent then AM := TyGuideMatMul(parent, ALocal)
  else if AHasLocal then AM := ALocal
  else AM := parent;
end;

{ createSymbol(AType, AX, AY, AW, AH, null, AKeepAspect): its PathProxy data
  [F3c] }
function UtSymbolData(const AType: string; AKeepAspect: Boolean; AX, AY, AW,
  AH: Double): TTyDoubleArray;
var path: TTyZrPath;
begin
  if (Copy(AType, 1, 7) = 'path://') and not AKeepAspect then
    path := TyZrMakePathCover(Copy(AType, 8, MaxInt), TyXYWH(AX, AY, AW, AH))
  else
    path := TyZrSymbol(AType, AX, AY, AW, AH);
  Result := TyGuidePathData(path);
end;

{ ECLinePath at a percent: a Line's moveTo / lineTo, or a quadratic
  BezierCurve's, the end lerped (quadraticSubdivide) short of 1; nothing at
  nought [F3c] }
function UtLinePath(const AEl: TTyChartElement; APercent: Double): TTyDoubleArray;
var
  x1, y1, x2, y2, cx, cy, p01, p12: Double;
begin
  Result := nil;
  if APercent = 0 then Exit;
  x1 := AEl.Anim.G[0];
  y1 := AEl.Anim.G[1];
  x2 := AEl.Anim.G[2];
  y2 := AEl.Anim.G[3];
  if AEl.Anim.G[6] = 0 then
  begin
    if APercent < 1 then
    begin
      x2 := x1 * (1 - APercent) + x2 * APercent;
      y2 := y1 * (1 - APercent) + y2 * APercent;
    end;
    Result := TTyDoubleArray.Create(TyZrCodeM, x1, y1, TyZrCodeL, x2, y2);
  end
  else
  begin
    cx := AEl.Anim.G[4];
    cy := AEl.Anim.G[5];
    if APercent < 1 then
    begin
      p01 := (cx - x1) * APercent + x1;
      p12 := (x2 - cx) * APercent + cx;
      x2 := (p12 - p01) * APercent + p01;
      cx := p01;
      p01 := (cy - y1) * APercent + y1;
      p12 := (y2 - cy) * APercent + cy;
      y2 := (p12 - p01) * APercent + p01;
      cy := p01;
    end;
    Result := TTyDoubleArray.Create(TyZrCodeM, x1, y1, TyZrCodeQ, cx, cy, x2, y2);
  end;
end;

{ a lines row's end symbol (Line.createSymbol, beforeUpdate): the symbol
  about nought, at the line's end (the start, or the point at the percent),
  turned by the tangent, scaled by the percent [F3c] }
procedure UtLineSymbolPath(const AEl: TTyChartElement; APercent: Double;
  out AData: TTyDoubleArray; out AHasM: Boolean; out AM: TTyMat2D);
var
  g: TTyLinesGeom;
  at: TTyPointF;
begin
  AData := UtSymbolData(AEl.Caption.LgSymbol, AEl.Caption.LgKeepAspect,
    -AEl.Anim.G[8] / 2, -AEl.Anim.G[9] / 2, AEl.Anim.G[8], AEl.Anim.G[9]);
  g := Default(TTyLinesGeom);
  SetLength(g.Pts, 2);
  g.Pts[0] := TyPointF(AEl.Anim.G[0], AEl.Anim.G[1]);
  g.Pts[1] := TyPointF(AEl.Anim.G[2], AEl.Anim.G[3]);
  g.Curved := AEl.Anim.G[6] <> 0;
  g.CP := TyPointF(AEl.Anim.G[4], AEl.Anim.G[5]);
  g.Drawn := True;
  if AEl.Anim.Role = carLinesFrom then at := TyLinesPointAt(g, 0)
  else at := TyLinesPointAt(g, APercent);
  AHasM := TyLabelLocalTransform(at.X, at.Y, 0, 0, AEl.Anim.G[11], APercent, APercent, AM);
end;

{ [F3c] a points array: the proxy's (a transition in flight) where it has
  one that long, else the layout's }
function UtPointsOf(AP: TTyChartAnimProxy; const ALayout: TTyDoubleArray;
  AMin: Integer): TTyDoubleArray;
var v: TTyAnimValue;
begin
  Result := ALayout;
  if AP = nil then Exit;
  v := AP.GetAnimProp('shape.points');
  if (v.Kind = avkArray) and (Length(v.Arr) >= AMin) then Result := v.Arr;
end;

{ a shape's points, flat }
function UtShapePoints(const AEl: TTyChartElement): TTyDoubleArray;
var k: Integer;
begin
  SetLength(Result, Length(AEl.Shape.Points) * 2);
  for k := 0 to High(AEl.Shape.Points) do
  begin
    Result[k * 2] := AEl.Shape.Points[k].X;
    Result[k * 2 + 1] := AEl.Shape.Points[k].Y;
  end;
end;

{ Polyline / Polygon (polyHelper.buildPath, no smooth): moveTo, lineTo,
  closePath for a polygon; nothing under two points }
function UtPolyData(const APts: TTyDoubleArray; AClose: Boolean): TTyDoubleArray;
var
  n, k, at: Integer;
begin
  Result := nil;
  n := Length(APts) div 2;
  if n < 2 then Exit;
  SetLength(Result, n * 3 + Ord(AClose));
  at := 0;
  for k := 0 to n - 1 do
  begin
    if k = 0 then Result[at] := TyZrCodeM else Result[at] := TyZrCodeL;
    Result[at + 1] := APts[k * 2];
    Result[at + 2] := APts[k * 2 + 1];
    Inc(at, 3);
  end;
  if AClose then Result[at] := TyZrCodeZ;
end;

{ BoxPath: the box closed, then the whiskers and the caps as moveTo /
  lineTo pairs }
function UtBoxplotPath(const APts: TTyDoubleArray): TTyDoubleArray;
var
  n, i, at: Integer;
begin
  Result := nil;
  n := Length(APts) div 2;
  if n < 4 then Exit;
  SetLength(Result, 13 + ((n - 4) div 2) * 6);
  Result[0] := TyZrCodeM;
  Result[1] := APts[0];
  Result[2] := APts[1];
  at := 3;
  for i := 1 to 3 do
  begin
    Result[at] := TyZrCodeL;
    Result[at + 1] := APts[i * 2];
    Result[at + 2] := APts[i * 2 + 1];
    Inc(at, 3);
  end;
  Result[at] := TyZrCodeZ;
  Inc(at);
  i := 4;
  while i + 1 < n do
  begin
    Result[at] := TyZrCodeM;
    Result[at + 1] := APts[i * 2];
    Result[at + 2] := APts[i * 2 + 1];
    Result[at + 3] := TyZrCodeL;
    Result[at + 4] := APts[i * 2 + 2];
    Result[at + 5] := APts[i * 2 + 3];
    Inc(at, 6);
    Inc(i, 2);
  end;
  SetLength(Result, at);
end;

{ GaugeView's pointer: a PointerPath (angle -pi/2, the width, the length,
  at the offset) or the icon (createSymbol over the width and the length,
  its foot on the offset), turned by the rotation, at the centre }
procedure UtPointerPath(const AEl: TTyChartElement; ARotation: Double;
  out AData: TTyDoubleArray; out AHasM: Boolean; out AM: TTyMat2D);
var
  w, r, x, y, ang, px, py: Double;
  mask: TFPUExceptionMask;
begin
  w := AEl.Caption.LgG[0];
  r := AEl.Caption.LgG[1];
  x := AEl.Caption.LgG[2];
  y := AEl.Caption.LgG[3];
  if AEl.Caption.LgSymbol <> '' then
    AData := UtSymbolData(AEl.Caption.LgSymbol, AEl.Caption.LgKeepAspect,
      x - w / 2, y - r, w, r)
  else
  begin
    mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
      exOverflow, exUnderflow, exPrecision]);
    try
      ang := -Pi / 2;
      if w >= r / 3 then
      begin
        px := x - TyJsCos(ang) * w * 1;
        py := y - TyJsSin(ang) * w * 1;
      end
      else
      begin
        px := x - TyJsCos(ang) * w * 2;
        py := y - TyJsSin(ang) * w * 2;
      end;
      ang := -Pi / 2 - Pi / 2;
      AData := TTyDoubleArray.Create(TyZrCodeM, px, py,
        TyZrCodeL, x + TyJsCos(ang) * w, y + TyJsSin(ang) * w,
        TyZrCodeL, x + TyJsCos(-Pi / 2) * r, y + TyJsSin(-Pi / 2) * r,
        TyZrCodeL, x - TyJsCos(ang) * w, y - TyJsSin(ang) * w,
        TyZrCodeL, px, py);
    finally
      ClearExceptions(False);
      SetExceptionMask(mask);
    end;
  end;
  AHasM := TyLabelLocalTransform(AEl.Anim.G[0], AEl.Anim.G[1], 0, 0, ARotation, 1, 1, AM);
end;

{ an effect scatter's ripple: createSymbol(-1, -1, 2, 2) at its scale, in
  the ripple group (the symbol's size, offset and turn) at the point }
procedure UtRipplePath(const AEl: TTyChartElement; ASX, ASY: Double;
  out AData: TTyDoubleArray; out AHasM: Boolean; out AM: TTyMat2D);
var
  pos, grp, own, m1: TTyMat2D;
  rot: Double;
  k: Integer;
begin
  AData := UtSymbolData(AEl.Caption.LgSymbol, False, -1, -1, 2, 2);
  for k := 0 to 5 do pos[k] := 0;
  pos[0] := 1;
  pos[3] := 1;
  pos[4] := AEl.Anim.G[8];
  pos[5] := AEl.Anim.G[9];
  rot := AEl.Caption.LgG[2] * Pi / 180;
  if IsNan(rot) then rot := 0;
  TyLabelLocalTransform(AEl.Caption.LgG[3], AEl.Caption.LgG[4], 0, 0, rot,
    AEl.Caption.LgG[0], AEl.Caption.LgG[1], grp);
  TyLabelLocalTransform(0, 0, 0, 0, 0, ASX, ASY, own);
  m1 := TyGuideMatMul(pos, grp);
  AM := TyGuideMatMul(m1, own);
  AHasM := True;
end;

{ a polar bar's sector or sausage as BarView's polar creator makes it,
  from AP's shape where it has one [F3c] }
function UtPolarSector(const AEl: TTyChartElement; AP: TTyChartAnimProxy): TTyPolarSector;
begin
  Result.CX := NumOr(AP, 'shape.cx', AEl.Anim.G[0]);
  Result.CY := NumOr(AP, 'shape.cy', AEl.Anim.G[1]);
  Result.R0 := NumOr(AP, 'shape.r0', AEl.Anim.G[2]);
  Result.R := NumOr(AP, 'shape.r', AEl.Anim.G[3]);
  Result.SA := NumOr(AP, 'shape.startAngle', AEl.Anim.G[4]);
  Result.EA := NumOr(AP, 'shape.endAngle', AEl.Anim.G[5]);
  Result.CW := AEl.Anim.G[6] <> 0;
end;

{ THE PATH AN ITEM ELEMENT DRAWS NOW, as getUpdatedPathProxy and
  getComputedTransform give it: its proxy's values where it has one (an
  animation in flight), the layout's otherwise; a morph in flight draws its
  frame, with no transform. AHasLocal / ALocal: the path's own transform
  (a symbol's; a morph leaves it as it was) [Batch 137] }
procedure UtElementPathEx(const AEl: TTyChartElement; P, AMorphP: TTyChartAnimProxy;
  out AData: TTyDoubleArray; out AHasM: Boolean; out AM: TTyMat2D;
  out AHasLocal: Boolean; out ALocal: TTyMat2D);
var
  bundle: TTyMat2D;
  path: TTyZrPath;
  s: TTyPolarSector;
  corners: TTyDoubleArray;
  r1, r2, r3, r4: Double;
  k: Integer;
  any: Boolean;
begin
  AData := nil;
  AHasM := False;
  AHasLocal := False;
  for k := 0 to 5 do
  begin
    AM[k] := 0;
    ALocal[k] := 0;
  end;
  path := nil;
  case AEl.Anim.Role of
    carBar:
      begin
        { Rect.buildPath: rect(), or the rounded one when r is set }
        if AEl.Shape.Kind = cskRoundRect then
          TyZrRadii([AEl.Shape.Radii[0], AEl.Shape.Radii[1], AEl.Shape.Radii[2],
            AEl.Shape.Radii[3]], r1, r2, r3, r4)
        else
        begin
          r1 := 0; r2 := 0; r3 := 0; r4 := 0;
        end;
        if (r1 <> 0) or (r2 <> 0) or (r3 <> 0) or (r4 <> 0) then
          TyZrRoundRect(path, NumOr(P, 'shape.x', AEl.Anim.G[0]), NumOr(P, 'shape.y', AEl.Anim.G[1]),
            NumOr(P, 'shape.width', AEl.Anim.G[2]), NumOr(P, 'shape.height', AEl.Anim.G[3]),
            r1, r2, r3, r4)
        else
          TyZrRect(path, NumOr(P, 'shape.x', AEl.Anim.G[0]), NumOr(P, 'shape.y', AEl.Anim.G[1]),
            NumOr(P, 'shape.width', AEl.Anim.G[2]), NumOr(P, 'shape.height', AEl.Anim.G[3]));
        AData := TyGuidePathData(path);
      end;
    carSector:
      begin
        s.CX := NumOr(P, 'shape.cx', AEl.Anim.G[0]);
        s.CY := NumOr(P, 'shape.cy', AEl.Anim.G[1]);
        s.R0 := NumOr(P, 'shape.r0', AEl.Anim.G[2]);
        s.R := NumOr(P, 'shape.r', AEl.Anim.G[3]);
        s.SA := NumOr(P, 'shape.startAngle', AEl.Anim.G[4]);
        s.EA := NumOr(P, 'shape.endAngle', AEl.Anim.G[5]);
        { G[7]: the layout ran anticlockwise }
        s.CW := AEl.Anim.G[7] = 0;
        any := False;
        for k := 0 to 3 do
          if AEl.Shape.SectorRadii[k] <> 0 then any := True;
        corners := nil;
        if any then
        begin
          SetLength(corners, 4);
          for k := 0 to 3 do corners[k] := AEl.Shape.SectorRadii[k];
        end;
        AData := TyGuidePathData(TyZrSectorPath(s, corners));
      end;
    carSymbol:
      UtSymbolPath(AEl.Caption.LgSymbol, AEl.Caption.LgKeepAspect,
        NumOr(P, 'scaleX', AEl.Caption.LgG[0] / 2), NumOr(P, 'scaleY', AEl.Caption.LgG[1] / 2),
        AEl.Caption.LgG[2], AEl.Caption.LgG[3], AEl.Caption.LgG[4],
        NumOr(P, 'x', AEl.Caption.LgG[5]), NumOr(P, 'y', AEl.Caption.LgG[6]), 1, 1,
        AData, AHasM, AM, AHasLocal, ALocal);
    carLineSymbol:
      UtSymbolPath(AEl.Caption.LgSymbol, AEl.Caption.LgKeepAspect,
        AEl.Caption.LgG[0] / 2, AEl.Caption.LgG[1] / 2,
        AEl.Caption.LgG[2], AEl.Caption.LgG[3], AEl.Caption.LgG[4],
        NumOr(P, 'x', AEl.Caption.LgG[5]), NumOr(P, 'y', AEl.Caption.LgG[6]),
        NumOr(P, 'scaleX', 1), NumOr(P, 'scaleY', 1), AData, AHasM, AM, AHasLocal, ALocal);
    carSunPiece:
      begin
        { [Batch 138] SunburstPiece: a Sector of the layout, its clockwise }
        s.CX := NumOr(P, 'shape.cx', AEl.Anim.G[0]);
        s.CY := NumOr(P, 'shape.cy', AEl.Anim.G[1]);
        s.R0 := NumOr(P, 'shape.r0', AEl.Anim.G[2]);
        s.R := NumOr(P, 'shape.r', AEl.Anim.G[3]);
        s.SA := NumOr(P, 'shape.startAngle', AEl.Anim.G[4]);
        s.EA := NumOr(P, 'shape.endAngle', AEl.Anim.G[5]);
        s.CW := AEl.Anim.G[6] <> 0;
        any := False;
        for k := 0 to 3 do
          if AEl.Shape.SectorRadii[k] <> 0 then any := True;
        corners := nil;
        if any then
        begin
          SetLength(corners, 4);
          for k := 0 to 3 do corners[k] := AEl.Shape.SectorRadii[k];
        end;
        AData := TyGuidePathData(TyZrSectorPath(s, corners));
      end;
    carTmRect:
      begin
        { [Batch 138] a treemap rect's local shape under its node group's
          computed transform (a translation) }
        TyZrRect(path, AEl.Anim.G[0], AEl.Anim.G[1], AEl.Anim.G[2], AEl.Anim.G[3]);
        AData := TyGuidePathData(path);
        AHasM := AEl.Anim.G[5] <> 0;
        if AHasM then
        begin
          AM[0] := 1;
          AM[3] := 1;
          AM[4] := AEl.Anim.G[6];
          AM[5] := AEl.Anim.G[7];
        end;
      end;
  end;
  if AEl.Anim.UtTag = 1 then
  begin
    { [F3c] a tagged path: its data and transform, or a scatter's symbol }
    if (Length(AEl.Anim.UtBase) > 0) and (AEl.Anim.UtBase[0] = 3) then
      UtSymbolPath(AEl.Caption.LgSymbol, AEl.Caption.LgKeepAspect,
        AEl.Caption.LgG[0] / 2, AEl.Caption.LgG[1] / 2, AEl.Caption.LgG[2],
        AEl.Caption.LgG[3], AEl.Caption.LgG[4], AEl.Caption.LgG[5], AEl.Caption.LgG[6],
        1, 1, AData, AHasM, AM, AHasLocal, ALocal)
    else
    begin
      AData := AEl.Anim.UtData;
      AHasM := AEl.Anim.UtHasM;
      if AHasM then AM := AEl.Anim.UtM;
    end;
  end
  else
  case AEl.Anim.Role of
    carFunnel:
      { [F3c] FunnelPiece: a Polygon of its four points }
      AData := TyGuidePathData(TyZrPolyPath(AEl.Shape.Points, True));
    carPolarBar:
      { [F3c] a Sector (its corner radii as updateStyle gave them) or a
        Sausage }
      if AEl.Anim.G[8] <> 0 then
        AData := TyGuidePathData(TyZrSausagePath(UtPolarSector(AEl, P)))
      else
        AData := TyGuidePathData(TyZrSectorPath(UtPolarSector(AEl, P), AEl.Anim.Pts));
    carPictorialGlyph, carPictorialClip:
      begin
        { [F3c] createPath: the symbol at the pattern size about nought,
          scaled by symbolScale, turned, at its place in the bundle }
        AData := UtSymbolData(AEl.Caption.LgSymbol, False, -AEl.Caption.LgG[4] / 2,
          -AEl.Caption.LgG[4] / 2, AEl.Caption.LgG[4], AEl.Caption.LgG[4]);
        AHasLocal := TyLabelLocalTransform(AEl.Caption.LgG[0], AEl.Caption.LgG[1], 0, 0,
          AEl.Caption.LgG[5], NumOr(P, 'scaleX', AEl.Caption.LgG[2]),
          NumOr(P, 'scaleY', AEl.Caption.LgG[3]), ALocal);
        { under the bundle: a translation (barGroup.x / y) }
        bundle[0] := 1;
        bundle[1] := 0;
        bundle[2] := 0;
        bundle[3] := 1;
        bundle[4] := AEl.Caption.LgG[6];
        bundle[5] := AEl.Caption.LgG[7];
        AHasM := True;
        if AHasLocal then AM := TyGuideMatMul(bundle, ALocal) else AM := bundle;
      end;
    carMapRegion, carCustomPath:
      begin
        { [F3c] the path as its view made it, and its computed transform }
        AData := AEl.Anim.Pts;
        AHasM := AEl.Anim.G[6] <> 0;
        if AHasM then
          for k := 0 to 5 do AM[k] := AEl.Anim.G[k];
      end;
    carLinesLine:
      AData := UtLinePath(AEl, NumOr(P, 'shape.percent', 1));
    carLinesFrom, carLinesTo:
      UtLineSymbolPath(AEl, NumOr(P, 'shape.percent', 1), AData, AHasM, AM);
    carBoxplot:
      AData := UtBoxplotPath(UtPointsOf(P, AEl.Anim.Pts, 28));
    carRadarLine, carRadarArea:
      AData := UtPolyData(UtPointsOf(P, RadarRing(AEl), 2), AEl.Anim.Role = carRadarArea);
    carParallelLine:
      AData := UtPolyData(UtShapePoints(AEl), False);
    carGaugePointer:
      UtPointerPath(AEl, NumOr(P, 'rotation', -(AEl.Anim.G[2] + Pi / 2)), AData, AHasM, AM);
    carEffectSymbol:
      UtSymbolPath(AEl.Caption.LgSymbol, AEl.Caption.LgKeepAspect,
        NumOr(P, 'scaleX', AEl.Caption.LgG[0] / 2), NumOr(P, 'scaleY', AEl.Caption.LgG[1] / 2),
        AEl.Caption.LgG[2], AEl.Caption.LgG[3], AEl.Caption.LgG[4],
        NumOr(P, 'x', AEl.Caption.LgG[5]), NumOr(P, 'y', AEl.Caption.LgG[6]), 1, 1,
        AData, AHasM, AM, AHasLocal, ALocal);
    { a tree node's symbol: its proxy's x / y are its group's place in the
      main group, its device place is the layout's }
    carTreeNode:
      UtSymbolPath(AEl.Caption.LgSymbol, AEl.Caption.LgKeepAspect,
        NumOr(P, 'scaleX', AEl.Caption.LgG[0] / 2), NumOr(P, 'scaleY', AEl.Caption.LgG[1] / 2),
        AEl.Caption.LgG[2], AEl.Caption.LgG[3], AEl.Caption.LgG[4],
        AEl.Caption.LgG[5], AEl.Caption.LgG[6], 1, 1,
        AData, AHasM, AM, AHasLocal, ALocal);
    carRipple:
      UtRipplePath(AEl, NumOr(P, 'scaleX', 0.5), NumOr(P, 'scaleY', 0.5), AData, AHasM, AM);
  end;
  if (AMorphP <> nil) and AMorphP.FMorphOn then
  begin
    { the replaced buildPath at __morphT; updateTransform leaves it none }
    AData := TyMorphPathData(AMorphP.FMorph, NumOr(AMorphP, '__morphT', 0));
    AHasM := False;
    for k := 0 to 5 do AM[k] := 0;
  end;
end;

procedure UtElementPath(const AEl: TTyChartElement; P: TTyChartAnimProxy;
  out AData: TTyDoubleArray; out AHasM: Boolean; out AM: TTyMat2D);
var
  hasLocal: Boolean;
  local: TTyMat2D;
begin
  UtElementPathEx(AEl, P, P, AData, AHasM, AM, hasLocal, local);
end;

{ THE STYLE KEYS a universal transition reads and draws: the style object's
  OWN keys of the element that was (AOwn), or the values the element that is
  answers for them -- its own or the path style's defaults (fill '#000',
  stroke null, lineWidth 1, opacity 1). Only the four the painter draws.
  A key is own: a fill (a plain colour); a stroke (a colour); a line width
  above nought; an opacity off 1 -- and always a scatter symbol's, whose
  itemStyle.opacity (0.8) is written }
function UtStyleProps(const AEl: TTyChartElement; AOwn: Boolean): TTyAnimProps;
var
  n: Integer;

  procedure Put(const AKey: string; const AValue: TTyAnimValue);
  begin
    SetLength(Result, n + 1);
    Result[n].Key := AKey;
    Result[n].Value := AValue;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  { [F3c] a lines row's line: `line.style.fill = null`, an own key of null
    (it wins a merge, and animates nothing); a radar's line: `fill:
    'none'`, a string no colour parses (the same) }
  if AEl.Anim.Role = carLinesLine then
  begin
    if AOwn then Put('style.fill', Default(TTyAnimValue))
    else Put('style.fill', TyAnimStr('#000'));
  end
  else if AEl.Anim.Role = carRadarLine then
    Put('style.fill', TyAnimStr('none'))
  else if AEl.Style.HasFill and (AEl.Style.FillGradient.Kind = cgkNone) then
    Put('style.fill', TyAnimColorValue(AEl.Style.FillColor, False))
  else if not AOwn then
    Put('style.fill', TyAnimStr('#000'));
  if ((AEl.Style.StrokeColor shr 24) and $FF) > 0 then
    Put('style.stroke', TyAnimColorValue(AEl.Style.StrokeColor, False));
  if AEl.Style.StrokeWidthLogical > 0 then
    Put('style.lineWidth', TyAnimNum(AEl.Style.StrokeWidthLogical))
  else if not AOwn then
    Put('style.lineWidth', TyAnimNum(1));
  if (not AOwn) or (AEl.Style.Alpha <> 1) or (AEl.Anim.Role = carSymbol) then
    Put('style.opacity', TyAnimNum(AEl.Style.Alpha));
end;

{ the style keys drawn over an element while their animator runs }
procedure UtApplyStyle(var AEl: TTyChartElement; P: TTyChartAnimProxy);
var
  v: TTyAnimValue;
  c: TTyChartColor;
begin
  v := P.GetAnimProp('style.fill');
  if v.Kind = avkString then
  begin
    if StColourOf(v, c) then
    begin
      AEl.Style.HasFill := True;
      AEl.Style.FillColor := c;
      AEl.Style.FillGradient := Default(TTyChartGradient);
    end
    else
      AEl.Style.HasFill := False;
  end;
  v := P.GetAnimProp('style.stroke');
  if v.Kind = avkString then
  begin
    if StColourOf(v, c) then
    begin
      AEl.Style.StrokeColor := c;
      AEl.Style.StrokeGradient := Default(TTyChartGradient);
      if not (AEl.Style.StrokeWidthLogical > 0) then
        AEl.Style.StrokeWidthLogical := NumOr(P, 'style.lineWidth', 1);
    end
    else
      AEl.Style.StrokeColor := 0;
  end;
  v := P.GetAnimProp('style.lineWidth');
  if v.Kind = avkNumber then AEl.Style.StrokeWidthLogical := v.Num;
  v := P.GetAnimProp('style.opacity');
  { nought draws nothing, and is hit all the same, as upstream's }
  if v.Kind = avkNumber then AEl.Style.Alpha := v.Num;
end;

procedure TyUtApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
var
  cmds: TTyPathCmdArray;
  r: TTyXYWH;
  i: Integer;
begin
  if AProxy = nil then Exit;
  if AProxy.FMorphOn then
  begin
    { the replaced buildPath at __morphT: moves, lines and cubics, drawn
      with no transform (the element's is null while it morphs) }
    cmds := TyMorphDataCmds(TyMorphPathData(AProxy.FMorph, NumOr(AProxy, '__morphT', 0)));
    AEl.Shape := Default(TTyChartShape);
    AEl.Shape.Kind := cskPolygon;
    AEl.Shape.Cmds := cmds;
    SetLength(AEl.Shape.Points, Length(cmds));
    for i := 0 to High(cmds) do AEl.Shape.Points[i] := TyPointF(cmds[i].X, cmds[i].Y);
    r := TyPathCmdsRect(cmds);
    AEl.Shape.HasCmdBounds := True;
    AEl.Shape.CmdBounds := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
  end;
  if AProxy.FUtStyleOn then UtApplyStyle(AEl, AProxy);
end;

{ ONE CHILD OF A COMBINING ELEMENT in the element's place [Batch 137]: its
  morph frame at its __morphT (the end frame once its own morph is done --
  its own path, drawn the same), its style always the bag's; not drawn
  while its frame is not a number }
procedure UtPieceApply(var AEl: TTyChartElement; APiece: TTyChartAnimProxy; AK: Integer);
var
  cmds: TTyPathCmdArray;
  r: TTyXYWH;
  i: Integer;
  t: Double;
begin
  if APiece.FMorphOn then t := NumOr(APiece, '__morphT', NaN) else t := 1;
  cmds := TyMorphDataCmds(TyMorphPathData(APiece.FMorph, t));
  AEl.Shape := Default(TTyChartShape);
  AEl.Shape.Kind := cskPolygon;
  AEl.Shape.Cmds := cmds;
  SetLength(AEl.Shape.Points, Length(cmds));
  for i := 0 to High(cmds) do
  begin
    AEl.Shape.Points[i] := TyPointF(cmds[i].X, cmds[i].Y);
    if IsNan(cmds[i].X) or IsNan(cmds[i].Y) then AEl.Ignore := True;
  end;
  r := TyPathCmdsRect(cmds);
  AEl.Shape.HasCmdBounds := True;
  AEl.Shape.CmdBounds := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
  { the child's own style: nothing of the host's but what it copied }
  AEl.Style.HasFill := False;
  AEl.Style.FillGradient := Default(TTyChartGradient);
  AEl.Style.StrokeColor := 0;
  AEl.Style.StrokeGradient := Default(TTyChartGradient);
  AEl.Style.StrokeWidthLogical := 0;
  AEl.Style.Alpha := 1;
  UtApplyStyle(AEl, APiece);
  AEl.Anim.UtPiece := AK + 1;
end;

{ animateOrSetProps without a done that forces: AIsFrom animates from AProps;
  ASetToFinal as enter and update set it; AScope '' for none }
procedure UtAnimate(P: TTyChartAnimProxy; const AProps: TTyAnimProps;
  const ATiming: TTyAnimTiming; AIsFrom, ASetToFinal: Boolean; const AScope: string;
  ADone: TTyAnimNotify; ADuring: TTyAnimDuring = nil);
var cfg: TTyAnimCfg;
begin
  cfg := Default(TTyAnimCfg);
  cfg.Duration := ATiming.Duration;
  cfg.HasDuration := True;
  if IsNan(ATiming.Delay) then cfg.Delay := 0 else cfg.Delay := ATiming.Delay;
  cfg.Easing := ATiming.Easing;
  cfg.SetToFinal := ASetToFinal;
  cfg.Scope := AScope;
  cfg.Done := ADone;
  cfg.During := ADuring;
  if AIsFrom then P.AnimateFrom(AProps, cfg) else P.AnimateTo(AProps, cfg);
end;

{ the props an item element rests at, by its role }
function UtFinalProps(const AEl: TTyChartElement): TTyAnimProps;
begin
  case AEl.Anim.Role of
    carBar: Result := BarProps(AEl);
    carSector: Result := SectorProps(AEl);
    carSymbol: Result := SymbolProps(AEl);
    carLineSymbol:
      Result := TyAnimProps([Num1('scaleX', 1), Num1('scaleY', 1),
        Num1('x', AEl.Anim.G[0]), Num1('y', AEl.Anim.G[1])]);
    carSunPiece:
      Result := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]), Num1('shape.cy', AEl.Anim.G[1]),
        Num1('shape.r0', AEl.Anim.G[2]), Num1('shape.r', AEl.Anim.G[3]),
        Num1('shape.startAngle', AEl.Anim.G[4]), Num1('shape.endAngle', AEl.Anim.G[5])]);
    { [F3c] }
    carFunnel: Result := TyAnimProps([Num1('style.opacity', AEl.Style.Alpha)]);
    carPolarBar: Result := PolarBarProps(AEl);
    carPictorialGlyph, carPictorialClip:
      Result := TyAnimProps([Num1('scaleX', AEl.Caption.LgG[2]), Num1('scaleY', AEl.Caption.LgG[3])]);
    carBoxplot:
      if Length(AEl.Anim.Pts) >= 28 then
        Result := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(Copy(AEl.Anim.Pts, 0, 28), 2))])
      else
        Result := nil;
    carRadarLine, carRadarArea:
      Result := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(RadarRing(AEl), 2))]);
    carGaugePointer:
      Result := TyAnimProps([Num1('rotation', -(AEl.Anim.G[2] + Pi / 2))]);
    carEffectSymbol, carTreeNode: Result := SymbolProps(AEl);
    { a ripple stopped before its loop's first step: where it was made }
    carRipple:
      Result := TyAnimProps([Num1('scaleX', 0.5), Num1('scaleY', 0.5), Num1('style.opacity', 1)]);
  else
    Result := nil;
  end;
end;

{ the old element's style as it is: its own keys, a universal transition's
  values in flight where one runs }
function UtOldStyle(const AOldEl: TTyChartElement; AOldP: TTyChartAnimProxy): TTyAnimProps;
var
  k: Integer;
  v: TTyAnimValue;
begin
  Result := UtStyleProps(AOldEl, True);
  if (AOldP <> nil) and AOldP.FUtStyleOn then
    for k := 0 to High(Result) do
    begin
      v := AOldP.GetAnimProp(Result[k].Key);
      if v.Kind <> avkNull then Result[k].Value := TyAnimClone(v);
    end;
end;

{ ==================== combining and separating [Batch 137, D5 UT2] ==================== }

const
  { TTyUtOldSnap.Kind: the path's type as split reads it }
  cUtKindOther = 0;
  cUtKindRect = 1;
  cUtKindSector = 2;
  cUtKindSymbol = 3;

{ the effective path style the own keys make (the defaults under them: fill
  '#000', stroke null, lineWidth 1, opacity 1) }
procedure UtSnapStyle(var S: TTyUtOldSnap; AFillDefault: Boolean);
var
  k: Integer;
  v: TTyAnimValue;
  c: TTyChartColor;
begin
  S.Opacity := 1;
  S.LineWidth := 1;
  S.HasFill := AFillDefault;
  S.HasStroke := False;
  for k := 0 to High(S.Style) do
  begin
    v := S.Style[k].Value;
    if S.Style[k].Key = 'style.opacity' then
    begin
      if v.Kind = avkNumber then S.Opacity := v.Num;
    end
    else if S.Style[k].Key = 'style.lineWidth' then
    begin
      if v.Kind = avkNumber then S.LineWidth := v.Num;
    end
    else if S.Style[k].Key = 'style.fill' then
      S.HasFill := (v.Kind = avkString) and StColourOf(v, c)
    else if S.Style[k].Key = 'style.stroke' then
      S.HasStroke := (v.Kind = avkString) and StColourOf(v, c);
  end;
  { hasStroke: a stroke and lineWidth > 0 }
  S.HasStroke := S.HasStroke and (not IsNan(S.LineWidth)) and (S.LineWidth > 0);
end;

{ AN ITEM ELEMENT AS A TRANSITION READS IT: its path now and transform, its
  own style keys, and what the dividers and sortPaths read }
procedure UtSnapEl(const AEl: TTyChartElement; P, AMorphP: TTyChartAnimProxy;
  out S: TTyUtOldSnap);
var k: Integer;
begin
  S := Default(TTyUtOldSnap);
  S.PieceFirst := -1;
  S.Order := UtElOrder(AEl);
  S.ElRole := AEl.Anim.Role;
  S.Sym := AEl.Caption.LgSymbol;
  UtElementPathEx(AEl, P, AMorphP, S.Data, S.HasM, S.M, S.HasLocal, S.Local);
  S.Morphing := (AMorphP <> nil) and AMorphP.FMorphOn;
  S.Style := UtOldStyle(AEl, AMorphP);
  if AEl.Anim.UtTag = 1 then
  begin
    { [F3c] a tagged path's rect or sector for the dividers }
    if (Length(AEl.Anim.UtBase) >= 5) and (AEl.Anim.UtBase[0] = 1) then
    begin
      S.Kind := cUtKindRect;
      S.RX := AEl.Anim.UtBase[1];
      S.RY := AEl.Anim.UtBase[2];
      S.RW := AEl.Anim.UtBase[3];
      S.RH := AEl.Anim.UtBase[4];
    end
    else if (Length(AEl.Anim.UtBase) >= 8) and (AEl.Anim.UtBase[0] = 2) then
    begin
      S.Kind := cUtKindSector;
      S.SCX := AEl.Anim.UtBase[1];
      S.SCY := AEl.Anim.UtBase[2];
      S.SR0 := AEl.Anim.UtBase[3];
      S.SR := AEl.Anim.UtBase[4];
      S.SSA := AEl.Anim.UtBase[5];
      S.SEA := AEl.Anim.UtBase[6];
      S.SCW := AEl.Anim.UtBase[7] <> 0;
    end
    else if (Length(AEl.Anim.UtBase) > 0) and (AEl.Anim.UtBase[0] = 3) then
      S.Kind := cUtKindSymbol;
  end
  else
  case AEl.Anim.Role of
    carBar:
      begin
        S.Kind := cUtKindRect;
        S.RX := NumOr(P, 'shape.x', AEl.Anim.G[0]);
        S.RY := NumOr(P, 'shape.y', AEl.Anim.G[1]);
        S.RW := NumOr(P, 'shape.width', AEl.Anim.G[2]);
        S.RH := NumOr(P, 'shape.height', AEl.Anim.G[3]);
      end;
    carSector:
      begin
        S.Kind := cUtKindSector;
        S.SCX := NumOr(P, 'shape.cx', AEl.Anim.G[0]);
        S.SCY := NumOr(P, 'shape.cy', AEl.Anim.G[1]);
        S.SR0 := NumOr(P, 'shape.r0', AEl.Anim.G[2]);
        S.SR := NumOr(P, 'shape.r', AEl.Anim.G[3]);
        S.SSA := NumOr(P, 'shape.startAngle', AEl.Anim.G[4]);
        S.SEA := NumOr(P, 'shape.endAngle', AEl.Anim.G[5]);
        S.SCW := AEl.Anim.G[7] = 0;
      end;
    carSymbol, carLineSymbol: S.Kind := cUtKindSymbol;
    carSunPiece:
      begin
        { [Batch 138] }
        S.Kind := cUtKindSector;
        S.SCX := NumOr(P, 'shape.cx', AEl.Anim.G[0]);
        S.SCY := NumOr(P, 'shape.cy', AEl.Anim.G[1]);
        S.SR0 := NumOr(P, 'shape.r0', AEl.Anim.G[2]);
        S.SR := NumOr(P, 'shape.r', AEl.Anim.G[3]);
        S.SSA := NumOr(P, 'shape.startAngle', AEl.Anim.G[4]);
        S.SEA := NumOr(P, 'shape.endAngle', AEl.Anim.G[5]);
        S.SCW := AEl.Anim.G[6] <> 0;
      end;
    carTmRect:
      begin
        S.Kind := cUtKindRect;
        S.RX := AEl.Anim.G[0];
        S.RY := AEl.Anim.G[1];
        S.RW := AEl.Anim.G[2];
        S.RH := AEl.Anim.G[3];
      end;
    carPolarBar:
      { [F3c] a Sector divides as one; a Sausage's type is its own }
      if AEl.Anim.G[8] = 0 then
      begin
        S.Kind := cUtKindSector;
        S.SCX := NumOr(P, 'shape.cx', AEl.Anim.G[0]);
        S.SCY := NumOr(P, 'shape.cy', AEl.Anim.G[1]);
        S.SR0 := NumOr(P, 'shape.r0', AEl.Anim.G[2]);
        S.SR := NumOr(P, 'shape.r', AEl.Anim.G[3]);
        S.SSA := NumOr(P, 'shape.startAngle', AEl.Anim.G[4]);
        S.SEA := NumOr(P, 'shape.endAngle', AEl.Anim.G[5]);
        S.SCW := AEl.Anim.G[6] <> 0;
      end;
    carPictorialGlyph, carPictorialClip: S.Kind := cUtKindSymbol;
    carCustomPath:
      { [F3c] a custom rect or sector divides as one }
      if (Length(AEl.Anim.Base) >= 5) and (AEl.Anim.Base[0] = 1) then
      begin
        S.Kind := cUtKindRect;
        S.RX := AEl.Anim.Base[1];
        S.RY := AEl.Anim.Base[2];
        S.RW := AEl.Anim.Base[3];
        S.RH := AEl.Anim.Base[4];
      end
      else if (Length(AEl.Anim.Base) >= 8) and (AEl.Anim.Base[0] = 2) then
      begin
        S.Kind := cUtKindSector;
        S.SCX := AEl.Anim.Base[1];
        S.SCY := AEl.Anim.Base[2];
        S.SR0 := AEl.Anim.Base[3];
        S.SR := AEl.Anim.Base[4];
        S.SSA := AEl.Anim.Base[5];
        S.SEA := AEl.Anim.Base[6];
        S.SCW := AEl.Anim.Base[7] <> 0;
      end;
  end;
  UtSnapStyle(S, AEl.Style.HasFill);
  { a symbol path's style says strokeNoScale -- a pictorial glyph's and a
    map region's too [F3c] }
  S.NoScale := (AEl.Anim.Role in [carSymbol, carLineSymbol, carPictorialGlyph,
    carPictorialClip, carMapRegion, carLinesLine, carEffectSymbol, carRipple, carTreeNode])
    or ((AEl.Anim.UtTag = 1) and AEl.Anim.UtNoScale);
  { [F3c] a ripple's opacity is its loop's, an own key }
  if (AEl.Anim.Role = carRipple) and (P <> nil) and (P.GetAnimProp('style.opacity').Kind = avkNumber) then
  begin
    S.Opacity := P.Num('style.opacity');
    k := 0;
    while (k <= High(S.Style)) and (S.Style[k].Key <> 'style.opacity') do Inc(k);
    if k > High(S.Style) then SetLength(S.Style, k + 1);
    S.Style[k].Key := 'style.opacity';
    S.Style[k].Value := TyAnimNum(S.Opacity);
  end;
end;

{ A COMBINING ELEMENT'S CHILD as it is now: its morph frame (no transform)
  while it morphs, else its own path under the host's transform }
procedure UtSnapPiece(APiece: TTyChartAnimProxy; out S: TTyUtOldSnap);
var
  k, n: Integer;
begin
  S := Default(TTyUtOldSnap);
  S.PieceFirst := -1;
  if APiece.FMorphOn then
  begin
    S.Data := TyMorphPathData(APiece.FMorph, NumOr(APiece, '__morphT', NaN));
    S.Morphing := True;
  end
  else
  begin
    S.Data := APiece.FRest;
    S.HasM := APiece.FRestHasM;
    S.M := APiece.FRestM;
  end;
  n := 0;
  SetLength(S.Style, Length(APiece.FPieceOwn));
  for k := 0 to High(APiece.FPieceOwn) do
  begin
    S.Style[n].Key := APiece.FPieceOwn[k];
    S.Style[n].Value := TyAnimClone(APiece.GetAnimProp(APiece.FPieceOwn[k]));
    if S.Style[n].Value.Kind <> avkNull then Inc(n);
  end;
  SetLength(S.Style, n);
  UtSnapStyle(S, True);
  S.NoScale := APiece.FPieceNoScale;
end;

{ sortPaths' centre: the bounding rect (its stroke) and the translation }
procedure UtCentre(const S: TTyUtOldSnap; out ACX, ACY: Double);
var r: TTyXYWH;
begin
  r := TyPathDataRect(S.Data);
  if Length(S.Data) > 0 then
    r := TyPathStrokeRect(r, S.HasStroke, S.HasFill, S.LineWidth, S.NoScale, S.HasM, S.M);
  if S.HasM then
  begin
    ACX := r.X + r.W / 2 + S.M[4];
    ACY := r.Y + r.H / 2 + S.M[5];
  end
  else
  begin
    ACX := r.X + r.W / 2 + 0;
    ACY := r.Y + r.H / 2 + 0;
  end;
end;

function UtSortSnaps(const A: TTyUtOldSnapArray): TTyIntegerArray;
var
  cx, cy: TTyDoubleArray;
  i: Integer;
begin
  SetLength(cx, Length(A));
  SetLength(cy, Length(A));
  for i := 0 to High(A) do UtCentre(A[i], cx[i], cy[i]);
  Result := TyMorphSortOrder(cx, cy);
end;

{ extend(extend(a new object, A), B): A's keys with B's values, then B's own }
function UtMergeStyle(const A, B: TTyAnimProps): TTyAnimProps;
var
  i, j, n: Integer;
  found: Boolean;
begin
  SetLength(Result, Length(A) + Length(B));
  n := 0;
  for i := 0 to High(A) do
  begin
    Result[n] := A[i];
    for j := 0 to High(B) do
      if B[j].Key = A[i].Key then Result[n].Value := B[j].Value;
    Inc(n);
  end;
  for j := 0 to High(B) do
  begin
    found := False;
    for i := 0 to High(A) do
      if A[i].Key = B[j].Key then found := True;
    if not found then
    begin
      Result[n] := B[j];
      Inc(n);
    end;
  end;
  SetLength(Result, n);
end;

procedure UtSetOpacity(var S: TTyUtOldSnap; AOpacity: Double);
var k: Integer;
begin
  S.Opacity := AOpacity;
  for k := 0 to High(S.Style) do
    if S.Style[k].Key = 'style.opacity' then
    begin
      S.Style[k].Value := TyAnimNum(AOpacity);
      Exit;
    end;
  SetLength(S.Style, Length(S.Style) + 1);
  S.Style[High(S.Style)].Key := 'style.opacity';
  S.Style[High(S.Style)].Value := TyAnimNum(AOpacity);
end;

{ THE DIVIDERS (pathDividers / dividePath.ts split) on a snapped path: the
  pieces as paths in its own frame, the style copied (a clone's opacity
  fitted). ASeparate: separateMorph's -- every piece takes the source's
  computed transform (setLocalTransform); else combineMorph's, where the
  pieces are sorted before they are put under the host (a split piece has
  no transform then, a clone the path's own). False: not ACount pieces
  (upstream's 'Invalid morphing: unmatched splitted path'). }
function UtDivide(const S: TTyUtOldSnap; const ADivide: string; ACount: Integer;
  ASeparate: Boolean; out APieces: TTyUtOldSnapArray): Boolean;
var
  i, k, np: Integer;
  rects: TTyDividePieceArray;
  path: TTyZrPath;
  sec: TTyPolarSector;
  scale, a, b: Double;
  polys: TTyBezierCurves;
  data: TTyDoubleArray;
  recHas: Boolean;
  recM: TTyMat2D;
begin
  APieces := nil;
  recHas := False;
  for k := 0 to 5 do recM[k] := 0;
  if ASeparate and S.HasM then TyMorphRecompose(S.M, recHas, recM);
  if ADivide = 'clone' then
  begin
    { clonePath, its opacity fitted: 1 - (1 - opacity) ^ (1 / count) }
    SetLength(APieces, ACount);
    for i := 0 to ACount - 1 do
    begin
      APieces[i] := S;
      APieces[i].PieceFirst := -1;
      APieces[i].PieceCount := 0;
      APieces[i].Style := Copy(S.Style, 0, Length(S.Style));
      UtSetOpacity(APieces[i], TyCloneOpacity(S.Opacity, ACount));
      { copyTransform: the path's own; setLocalTransform over it where the
        source has a computed one }
      if ASeparate and S.HasM then
      begin
        APieces[i].HasM := recHas;
        APieces[i].M := recM;
      end
      else
      begin
        APieces[i].HasM := S.HasLocal;
        APieces[i].M := S.Local;
      end;
    end;
    Exit(True);
  end;
  { split }
  case S.Kind of
    cUtKindRect:
      begin
        rects := TyDivideRect(S.RX, S.RY, S.RW, S.RH, ACount);
        SetLength(APieces, Length(rects));
        for i := 0 to High(rects) do
        begin
          path := nil;
          TyZrRect(path, rects[i].X, rects[i].Y, rects[i].W, rects[i].H);
          APieces[i].Data := TyGuidePathData(path);
        end;
      end;
    cUtKindSector:
      begin
        rects := TyDivideSector(S.SCX, S.SCY, S.SR0, S.SR, S.SSA, S.SEA, True, S.SCW, ACount);
        SetLength(APieces, Length(rects));
        for i := 0 to High(rects) do
        begin
          sec.CX := rects[i].CX;
          sec.CY := rects[i].CY;
          sec.R0 := rects[i].R0;
          sec.R := rects[i].R;
          sec.SA := rects[i].StartAngle;
          sec.EA := rects[i].EndAngle;
          { !!shape.clockwise }
          sec.CW := rects[i].HasClockwise and rects[i].Clockwise;
          APieces[i].Data := TyGuidePathData(TyZrSectorPath(sec, nil));
        end;
      end;
  else
    begin
      { the polygons of the path at its scale }
      scale := 1;
      if S.HasM then
      begin
        a := S.M[0] * S.M[0] + S.M[1] * S.M[1];
        b := S.M[2] * S.M[2] + S.M[3] * S.M[3];
        if IsNan(a) or IsNan(b) then scale := NaN
        else if a > b then scale := Sqrt(a)
        else scale := Sqrt(b);
      end;
      polys := TyPathToPolygons(S.Data, scale);
      rects := TyDividePolygons(polys, ACount);
      SetLength(APieces, Length(rects));
      for i := 0 to High(rects) do
      begin
        { Polygon.buildPath: moveTo, lineTo, closePath -- two points at least }
        data := nil;
        np := Length(rects[i].Points) div 2;
        if np >= 2 then
        begin
          SetLength(data, np * 3 + 1);
          for k := 0 to np - 1 do
          begin
            if k = 0 then data[0] := TyZrCodeM else data[k * 3] := TyZrCodeL;
            data[k * 3 + 1] := rects[i].Points[k * 2];
            data[k * 3 + 2] := rects[i].Points[k * 2 + 1];
          end;
          data[np * 3] := TyZrCodeZ;
        end;
        APieces[i].Data := data;
      end;
    end;
  end;
  for i := 0 to High(APieces) do
  begin
    { copyPathProps: the style copied }
    APieces[i].Style := Copy(S.Style, 0, Length(S.Style));
    APieces[i].Opacity := S.Opacity;
    APieces[i].LineWidth := S.LineWidth;
    APieces[i].HasFill := S.HasFill;
    APieces[i].HasStroke := S.HasStroke;
    APieces[i].NoScale := S.NoScale;
    APieces[i].PieceFirst := -1;
    APieces[i].HasM := ASeparate and recHas;
    APieces[i].M := recM;
  end;
  Result := Length(APieces) = ACount;
end;

procedure TTyChartAnimSet.SnapUniversal(const ASeries: TTyChartAnimSeriesArray;
  const APrev: TTyChartAnimPrev; AOldIndex, AIdx: TFPHashList;
  out ASnaps: TTyUtOldSnapArray; out AItems: TTyUtItemPathsArray);
var
  i, s, n, k, first, it: Integer;
  any: Boolean;
  el: TTyChartElement;
  key: string;
  op, sp: TTyChartAnimProxy;
  v: Pointer;
  rm: TTyMat2D;

  { THE ITEM a path belongs to: its number, a new one at the end }
  function ItemOf(const AEl: TTyChartElement): Integer;
  begin
    v := AIdx.Find(KeyOf(AEl.Anim.Series, UtRowOf(AEl), 'ut'));
    if v <> nil then Exit(PtrInt(v) - 1);
    Result := Length(AItems);
    SetLength(AItems, Result + 1);
    AItems[Result] := nil;
    AIdx.Add(KeyOf(AEl.Anim.Series, UtRowOf(AEl), 'ut'), Pointer(PtrInt(Result + 1)));
  end;

  { a path of the item, in getPathList's order (a path already there of the
    same place is the first of it, kept) }
  function PutPath(AItem, ASnap: Integer): Boolean;
  var
    q, at: Integer;
  begin
    for q := 0 to High(AItems[AItem]) do
      if ASnaps[AItems[AItem][q]].Order = ASnaps[ASnap].Order then Exit(False);
    at := Length(AItems[AItem]);
    while (at > 0) and (ASnaps[AItems[AItem][at - 1]].Order > ASnaps[ASnap].Order) do Dec(at);
    SetLength(AItems[AItem], Length(AItems[AItem]) + 1);
    for q := High(AItems[AItem]) downto at + 1 do AItems[AItem][q] := AItems[AItem][q - 1];
    AItems[AItem][at] := ASnap;
    Result := True;
  end;

  { [F3c] A VIEW THE UPDATE DISPOSED (no series of the new option keeps it):
    upstream disposes it before the transition, and some views' dispose
    takes their items off their groups (GraphView.remove: SymbolDraw.remove;
    MapView: MapDraw.remove) -- what was above them is gone from their
    transform }
  function Disposed(AOld: Integer): Boolean;
  var
    q: Integer;
    vk: string;
  begin
    if (AOld < 0) or (AOld > High(APrev.Series)) then Exit(False);
    vk := APrev.Series[AOld].ViewKey + #1 + APrev.Series[AOld].SeriesType;
    for q := 0 to High(APrev.AliveKeys) do
      if APrev.AliveKeys[q] = vk then Exit(False);
    Result := True;
  end;

  procedure Detach(const AEl: TTyChartElement; P: TTyChartAnimProxy; var S: TTyUtOldSnap);
  begin
    if (AEl.Anim.Role = carSymbol) and (AEl.Anim.G[10] = 1) then
      { a graph node: its symbol group (the node's place, the compensation
        scale) and its path, no view }
      UtSymbolPath(AEl.Caption.LgSymbol, AEl.Caption.LgKeepAspect,
        NumOr(P, 'scaleX', AEl.Caption.LgG[0] / 2), NumOr(P, 'scaleY', AEl.Caption.LgG[1] / 2),
        AEl.Caption.LgG[2], AEl.Caption.LgG[3], AEl.Caption.LgG[4],
        AEl.Anim.G[7], AEl.Anim.G[8], AEl.Anim.G[9], AEl.Anim.G[9],
        S.Data, S.HasM, S.M, S.HasLocal, S.Local)
    else if AEl.Anim.Role = carMapRegion then
      { a region: no roam }
      S.HasM := False;
  end;

begin
  ASnaps := nil;
  AItems := nil;
  if APrev.FullUpdate then Exit;
  { [F3c] setOption's transition asks whatever the series say }
  any := APrev.UtHasTransition;
  for s := 0 to High(ASeries) do
    if ASeries[s].Present and ASeries[s].UtOn and ASeries[s].Enabled then any := True;
  if not any then Exit;
  n := 0;
  for i := 0 to High(APrev.Elements) do
  begin
    el := APrev.Elements[i];
    key := UtElKey(el);
    if key = '' then Continue;
    { the proxy its path is read from, and the one a morph of it runs on
      (the same one but where the role's is shared) [F3c] }
    sp := TTyChartAnimProxy(AOldIndex.Find(KeyOf(el.Anim.Series, KeyIndexOf(el), TyChartAnimRoleKey(el))));
    op := TTyChartAnimProxy(AOldIndex.Find(KeyOf(el.Anim.Series, UtRowOf(el), key)));
    if (TyChartAnimRoleKey(el) = key) or (TyChartAnimRoleKey(el) = '') then sp := op;
    SetLength(ASnaps, n + 1);
    UtSnapEl(el, sp, op, ASnaps[n]);
    if (not ASnaps[n].Morphing) and Disposed(el.Anim.Series) then Detach(el, sp, ASnaps[n]);
    { [F3c] removeEl: an item element that is a path with a parent takes
      its computed transform as its own (setLocalTransform, decomposed and
      composed again) before the morph reads it -- a gauge's pointer, a
      custom series' item that is a path }
    if (not ASnaps[n].Morphing) and ASnaps[n].HasM
      and ((el.Anim.Role = carGaugePointer)
        or ((el.Anim.Role = carCustomPath) and (el.Anim.G[7] = 1))) then
    begin
      rm := ASnaps[n].M;
      TyMorphRecompose(rm, ASnaps[n].HasM, ASnaps[n].M);
    end;
    it := ItemOf(el);
    if not PutPath(it, n) then
    begin
      SetLength(ASnaps, n);
      Continue;
    end;
    Inc(n);
    { A COMBINING ONE's children, as they are [Batch 137] }
    if (op <> nil) and op.FCombineOn and (Length(op.FPieces) > 0) then
    begin
      first := n;
      SetLength(ASnaps, n + Length(op.FPieces));
      for k := 0 to High(op.FPieces) do
      begin
        UtSnapPiece(op.FPieces[k], ASnaps[n]);
        Inc(n);
      end;
      ASnaps[first - 1].PieceFirst := first;
      ASnaps[first - 1].PieceCount := Length(op.FPieces);
    end;
  end;
  { THE PIECES THE OLD DATA STILL NAMES, as the render that last drew
    them left them [milestone D5-D8] }
  for i := 0 to High(APrev.UtStale) do
  begin
    el := APrev.UtStale[i];
    if UtElKey(el) = '' then Continue;
    if AIdx.Find(KeyOf(el.Anim.Series, UtRowOf(el), 'ut')) <> nil then Continue;
    SetLength(ASnaps, n + 1);
    UtSnapEl(el, nil, nil, ASnaps[n]);
    it := ItemOf(el);
    PutPath(it, n);
    Inc(n);
  end;
end;

procedure TTyChartAnimSet.ArmUniversal(AList: TTyPaintList;
  const ASeries: TTyChartAnimSeriesArray; const APrev: TTyChartAnimPrev;
  AUtIdx: TFPHashList; const AUtSnaps: TTyUtOldSnapArray;
  const AUtItems: TTyUtItemPathsArray; const AOldOf: TTyIntegerArray;
  const ARowMap: array of TTyIntegerArray; const AUpd: array of Boolean);
type
  { a new item path taking part: its series and row, the element, its
    transition's proxy (stopped) and how it reads }
  TNewRef = record
    Ser, Row: Integer;
    El: TTyChartElement;
    P: TTyChartAnimProxy;
    S: TTyUtOldSnap;
  end;
  TNewRefArray = array of TNewRef;
  TNewRefLists = array of TNewRefArray;
var
  newIdx: TFPHashList;
  newItems: array of TTyIntegerArray;
  newOrders: array of TTyIntegerArray;
  bKeys: TTyStringArray;
  bOld, bNew: array of TTyIntegerArray;
  i, s, o, k, b, it, q, at: Integer;
  el: TTyChartElement;
  key, lk: string;
  olds: TTyIntegerArray;
  typesOk: Boolean;
  v: Pointer;

  { THE NEW ITEM'S PATHS (ASer, ARow): their list indices, getPathList's
    order; none for no element }
  function NewEls(ASer, ARow: Integer): TTyIntegerArray;
  var v2: Pointer;
  begin
    Result := nil;
    if (ASer < 0) or (ASer > High(ASeries)) then Exit;
    v2 := newIdx.Find(KeyOf(ASer, ARow, 'ut'));
    if v2 <> nil then Result := newItems[PtrInt(v2) - 1];
  end;

  { THE OLD ITEM'S PATHS (AOld, ARow) as they were before this update: snap
    indices; none for no element }
  function OldPaths(AOld, ARow: Integer): TTyIntegerArray;
  var v2: Pointer;
  begin
    Result := nil;
    if (AOld < 0) or (AOld > High(APrev.Series)) then Exit;
    v2 := AUtIdx.Find(KeyOf(AOld, ARow, 'ut'));
    if v2 <> nil then Result := AUtItems[PtrInt(v2) - 1];
  end;

  { THE SAME ELEMENT: the new series kept the old one's view, its diff paired
    the rows, and a symbol kept its type (SymbolDraw makes a new Symbol when
    it changes); a map's regions are made on every draw, and a custom
    series' items too while it transitions [F3c] }
  function SameEl(AOldSer, AOldRow, ANewSer, ANewRow: Integer): Boolean;
  var
    op_, ne_: TTyIntegerArray;
    oe, ne: TTyChartElement;
  begin
    Result := False;
    if (ANewSer < 0) or (ANewSer > High(AUpd)) or not AUpd[ANewSer]
      or (AOldOf[ANewSer] <> AOldSer) then Exit;
    if (ANewRow > High(ARowMap[ANewSer])) or (ARowMap[ANewSer][ANewRow] <> AOldRow) then Exit;
    op_ := OldPaths(AOldSer, AOldRow);
    ne_ := NewEls(ANewSer, ANewRow);
    if (Length(op_) = 0) or (Length(ne_) = 0) then Exit;
    ne := AList.Element(ne_[0]);
    oe := Default(TTyChartElement);
    oe.Anim.Role := AUtSnaps[op_[0]].ElRole;
    if not UtKeepsElement(ASeries[ANewSer], ne) then Exit;
    if (oe.Anim.Role in [carSymbol, carLineSymbol])
      and (AUtSnaps[op_[0]].Sym <> ne.Caption.LgSymbol) then Exit;
    Result := True;
  end;

  { the proxy a role animates an element on: stopped where it runs,
    forwarded to its layout (setToFinal already wrote it upstream) [F3c] }
  procedure StopRole(ASer, ARow: Integer; const AEl: TTyChartElement; const AKey: string);
  var rp: TTyChartAnimProxy;
  begin
    { a tree node's group slides on a proxy of its own: stopAnimation(newEl)
      stops the group first }
    if AEl.Anim.Role = carTreeNode then
    begin
      rp := Find(ASer, KeyIndexOf(AEl), 'treeGroup');
      if rp <> nil then rp.StopAnimation('', True);
    end;
    if (TyChartAnimRoleKey(AEl) = '') or (TyChartAnimRoleKey(AEl) = AKey) then Exit;
    rp := Find(ASer, KeyIndexOf(AEl), TyChartAnimRoleKey(AEl));
    if rp <> nil then rp.StopAnimation('', True);
  end;

  { the new path's proxy, its own animation stopped (stopAnimation:
    everything rests at the layout, which setToFinal already wrote) -- and,
    a deviation, a combine of its own ended }
  function StopNew(ASer, ARow: Integer; const AEl: TTyChartElement): TTyChartAnimProxy;
  var
    props: TTyAnimProps;
    key2: string;
  begin
    key2 := UtElKey(AEl);
    StopRole(ASer, ARow, AEl, key2);
    Result := Find(ASer, ARow, key2);
    if Result = nil then Result := Make(ASer, ARow, key2)
    else Result.StopAnimation('', False);
    if Result.FCombineOn then
    begin
      Result.FCombineOn := False;
      Result.ClearPieces;
    end;
    props := UtFinalProps(AEl);
    Result.Attr(props);
    Result.SetFinal(props);
    Result.FUtPass := FPass;
  end;

  { the proxy an element's style animates on: its own, made at rest if none }
  function HostProxy(ASer, ARow: Integer; const AEl: TTyChartElement): TTyChartAnimProxy;
  var
    props: TTyAnimProps;
    key2: string;
  begin
    key2 := UtElKey(AEl);
    Result := Find(ASer, ARow, key2);
    if Result = nil then
    begin
      Result := Make(ASer, ARow, key2);
      props := UtFinalProps(AEl);
      Result.Attr(props);
      Result.SetFinal(props);
    end;
  end;

  { the element's style values set on its proxy, for animateFrom to start
    from where the old one was (`animateObj[key] != null`) }
  procedure SeedStyle(P: TTyChartAnimProxy; const AEl: TTyChartElement);
  var
    props: TTyAnimProps;
    k2: Integer;
  begin
    props := UtStyleProps(AEl, False);
    for k2 := 0 to High(props) do P.SetAnimProp(props[k2].Key, props[k2].Value);
  end;

  { stopAnimation(oldEl) + removeEl(oldEl): an old element a morph takes
    from stops leaving -- its ghosts are gone at once }
  procedure DropGhost(AOld, ARow: Integer);
  var
    k2: Integer;
    g: TTyChartAnimProxy;
  begin
    if (AOld < 0) or (AOld > High(APrev.Series)) then Exit;
    for k2 := 0 to FGhosts.Count - 1 do
    begin
      g := TTyChartAnimProxy(FGhosts[k2]);
      if g.FLeaving and not g.FGone and (g.FIndex = ARow)
        and (g.FGhost.Anim.Series = AOld) and (UtElKey(g.FGhost) <> '') then
      begin
        g.StopAnimation('', False);
        g.FGone := True;
      end;
    end;
  end;

  { the new item's paths, stopped, and how they read }
  function NewRefs(ASer, ARow: Integer): TNewRefArray;
  var
    els: TTyIntegerArray;
    k2: Integer;
  begin
    els := NewEls(ASer, ARow);
    SetLength(Result, Length(els));
    for k2 := 0 to High(els) do
    begin
      Result[k2].Ser := ASer;
      Result[k2].Row := ARow;
      Result[k2].El := AList.Element(els[k2]);
      Result[k2].P := StopNew(ASer, ARow, Result[k2].El);
    end;
    { read once every path is stopped: a role's proxy may be shared }
    for k2 := 0 to High(Result) do
      UtSnapEl(Result[k2].El, UtShapeProxy(Self, Result[k2].El, Result[k2].P), Result[k2].P,
        Result[k2].S);
  end;

  { universalTransition.delay(index, count) of the series ASer }
  function UtDelayAt(ASer, AIndex, ACount: Integer): Double;
  var
    h: TTyAnimTimingHandler;
    h2: TTyUtDelayHandler;
  begin
    if TyChartFindUtDelay(ASeries[ASer].UtDelay, h2) and Assigned(h2) then
      Result := h2(AIndex, ACount)
    else if TyChartFindAnimTiming(ASeries[ASer].UtDelay, h) and Assigned(h) then
      Result := h(AIndex, True)
    else
      Result := NaN;
  end;

  { `delay || 0` }
  function Or0(A: Double): Double;
  begin
    if IsNan(A) or (A = 0) then Result := 0 else Result := A;
  end;

  { morphPath(from, to): the target's path taken over by the morph }
  procedure MorphOn(P: TTyChartAnimProxy; const AFrom, ATo: TTyUtOldSnap;
    const ATm: TTyAnimTiming);
  begin
    P.FMorph := TyPrepareMorph(AFrom.Data, AFrom.HasM, AFrom.M, ATo.Data, ATo.HasM, ATo.M);
    P.FMorphOn := True;
    P.SetNum('__morphT', 0);
    UtAnimate(P, TyAnimProps([Num1('__morphT', 1)]), ATm, False, True, '', @P.MorphDone);
  end;

  { updateMorphingPathProps on a new element: its style from AStyle }
  procedure StyleFrom(P: TTyChartAnimProxy; const AEl: TTyChartElement;
    const AStyle: TTyAnimProps; const ATm: TTyAnimTiming);
  begin
    SeedStyle(P, AEl);
    P.FUtStyleOn := True;
    P.FUtPass := FPass;
    UtAnimate(P, AStyle, ATm, True, True, '', @P.UtStyleDone);
  end;

  { fadeInElement: initProps from opacity 0, enter timing }
  procedure FadeIn(const ANew: TNewRef; AModelSer, AIndex: Integer);
  var tm: TTyAnimTiming;
  begin
    if TyAnimGetConfig(atEnter, ASeries[AModelSer].Model, TyAnimCallAt(AIndex), tm)
      and (tm.Duration > 0) then
    begin
      SeedStyle(ANew.P, ANew.El);
      ANew.P.FUtStyleOn := True;
      ANew.P.FUtPass := FPass;
      UtAnimate(ANew.P, TyAnimProps([Num1('style.opacity', 0)]), tm, True, True, 'enter',
        @ANew.P.UtStyleDone);
    end;
  end;

  { combineMorph: AOlds (snap indices; a combining one gives its children)
    into ANew's path divided -- the host drawn as the pieces while it runs }
  procedure Combine(const AOlds: array of Integer; const ANew: TNewRef; const ADivide: string;
    ASer: Integer; const ATm: TTyAnimTiming; AIdx, ACount: Integer);
  var
    from, pieces: TTyUtOldSnapArray;
    ident, fo, po: TTyIntegerArray;
    n, i2, k2, f2: Integer;
    host, pc: TTyChartAnimProxy;
    individual: Boolean;
    props, style: TTyAnimProps;
    t2: TTyAnimTiming;

    procedure AddFrom(AIdx2: Integer);
    begin
      SetLength(from, Length(from) + 1);
      from[High(from)] := AUtSnaps[AIdx2];
      SetLength(ident, Length(ident) + 1);
      ident[High(ident)] := AIdx2;
    end;

  begin
    from := nil;
    ident := nil;
    { addFromPath }
    for i2 := 0 to High(AOlds) do
      if AUtSnaps[AOlds[i2]].PieceCount > 0 then
      begin
        for k2 := 0 to AUtSnaps[AOlds[i2]].PieceCount - 1 do
          AddFrom(AUtSnaps[AOlds[i2]].PieceFirst + k2);
      end
      else
        AddFrom(AOlds[i2]);
    n := Length(from);
    if n = 0 then Exit;
    if not UtDivide(ANew.S, ADivide, n, False, pieces) then Exit;
    fo := UtSortSnaps(from);
    po := UtSortSnaps(pieces);
    host := ANew.P;
    host.ClearPieces;
    host.FMorphOn := False;
    individual := ASeries[ASer].UtDelay <> '';
    props := UtStyleProps(ANew.El, False);
    SetLength(host.FPieces, n);
    for i2 := 0 to n - 1 do
    begin
      pc := TTyChartAnimProxy.Create(ANew.Ser, ANew.Row, 'utPiece');
      pc.Animation := FAnimation;
      pc.FHost := host;
      host.FPieces[i2] := pc;
      { under the host, its transform identity: the host's computed one }
      pc.FRest := pieces[po[i2]].Data;
      pc.FRestHasM := ANew.S.HasM;
      pc.FRestM := ANew.S.M;
      pc.FMorph := TyPrepareMorph(from[fo[i2]].Data, from[fo[i2]].HasM, from[fo[i2]].M,
        pc.FRest, pc.FRestHasM, pc.FRestM);
      pc.FMorphOn := True;
      { the host's style, a clone's opacity fitted }
      for k2 := 0 to High(props) do pc.SetAnimProp(props[k2].Key, props[k2].Value);
      pc.SetNum('style.opacity', pieces[po[i2]].Opacity);
      SetLength(pc.FPieceOwn, Length(pieces[po[i2]].Style));
      for k2 := 0 to High(pieces[po[i2]].Style) do pc.FPieceOwn[k2] := pieces[po[i2]].Style[k2].Key;
      pc.FPieceNoScale := ANew.S.NoScale;
    end;
    host.FCombineOn := True;
    if not individual then
    begin
      { one __morphT on the host, handed to every child in its during }
      host.SetNum('__morphT', 0);
      UtAnimate(host, TyAnimProps([Num1('__morphT', 1)]), ATm, False, True, '',
        @host.CombineDone, @host.CombineDuring);
    end
    else
    begin
      { each child morphPath'd on its own: delay + individualDelay(i) }
      host.FCombineLeft := n;
      for i2 := 0 to n - 1 do
      begin
        t2 := ATm;
        t2.Delay := Or0(ATm.Delay) + UtDelayAt(ASer, i2 + AIdx, ACount);
        pc := host.FPieces[i2];
        pc.SetNum('__morphT', 0);
        UtAnimate(pc, TyAnimProps([Num1('__morphT', 1)]), t2, False, True, '', @pc.PieceMorphDone);
      end;
    end;
    { animateOtherProps: each child's style from its old path's (rawFrom
      the batch's k-th, unexpanded) }
    for k2 := 0 to n - 1 do
    begin
      t2 := ATm;
      if individual then t2.Delay := UtDelayAt(ASer, k2, n);
      f2 := fo[k2];
      if (k2 <= High(AOlds)) and (AOlds[k2] <> ident[f2]) then
        style := UtMergeStyle(AUtSnaps[AOlds[k2]].Style, from[f2].Style)
      else
        style := from[f2].Style;
      UtAnimate(host.FPieces[k2], style, t2, True, True, '', nil);
    end;
  end;

  { separateMorph: AOld's path divided (or a combining one's children) into
    the new elements }
  procedure Separate(AOld: Integer; const ANews: TNewRefArray; const ADivide: string;
    ASer: Integer; const ATm: TTyAnimTiming; AIdx, ACount: Integer);
  var
    from: TTyUtOldSnapArray;
    fo, no: TTyIntegerArray;
    toLen, fromLen, i2, k2: Integer;
    individual: Boolean;
    t2: TTyAnimTiming;
    news: TTyUtOldSnapArray;
  begin
    toLen := Length(ANews);
    if AUtSnaps[AOld].PieceCount > 0 then
    begin
      { a combining path reversed: its children, cloned round or cut }
      fromLen := AUtSnaps[AOld].PieceCount;
      SetLength(from, fromLen);
      for i2 := 0 to fromLen - 1 do from[i2] := AUtSnaps[AUtSnaps[AOld].PieceFirst + i2];
      if fromLen < toLen then
      begin
        k2 := 0;
        SetLength(from, toLen);
        for i2 := fromLen to toLen - 1 do
        begin
          { clonePath: the same path, no parent -- no transform }
          from[i2] := from[k2 mod fromLen];
          from[i2].HasM := False;
          Inc(k2);
        end;
      end;
      SetLength(from, toLen);
    end
    else if not UtDivide(AUtSnaps[AOld], ADivide, toLen, True, from) then
      Exit;
    SetLength(news, toLen);
    for i2 := 0 to toLen - 1 do news[i2] := ANews[i2].S;
    fo := UtSortSnaps(from);
    no := UtSortSnaps(news);
    individual := ASeries[ASer].UtDelay <> '';
    for i2 := 0 to toLen - 1 do
    begin
      t2 := ATm;
      if individual then t2.Delay := Or0(ATm.Delay) + UtDelayAt(ASer, i2 + AIdx, ACount);
      MorphOn(ANews[no[i2]].P, from[fo[i2]], news[no[i2]], t2);
    end;
    for k2 := 0 to toLen - 1 do
    begin
      t2 := ATm;
      if individual then t2.Delay := UtDelayAt(ASer, k2, toLen);
      StyleFrom(ANews[no[k2]].P, ANews[no[k2]].El,
        UtMergeStyle(AUtSnaps[AOld].Style, from[fo[k2]].Style), t2);
    end;
  end;

  { morphOneBatch with one path a side; a combining source combines again }
  procedure MorphOne(AOld: Integer; const ANew: TNewRef; const ADivide: string;
    ASer: Integer; const ATm: TTyAnimTiming; AIdx, ACount: Integer);
  var t2: TTyAnimTiming;
  begin
    if AUtSnaps[AOld].PieceCount > 0 then
    begin
      Combine([AOld], ANew, ADivide, ASer, ATm, AIdx, ACount);
      Exit;
    end;
    t2 := ATm;
    if ASeries[ASer].UtDelay <> '' then t2.Delay := UtDelayAt(ASer, AIdx, ACount);
    MorphOn(ANew.P, AUtSnaps[AOld], ANew.S, t2);
    StyleFrom(ANew.P, ANew.El, AUtSnaps[AOld].Style, t2);
  end;

  { applyMorphAnimation's timing: update, at the index; False: no morph }
  function MorphTiming(ASer, AIndex: Integer; out ATm: TTyAnimTiming): Boolean;
  begin
    Result := TyAnimGetConfig(atUpdate, ASeries[ASer].Model, TyAnimCallAt(AIndex), ATm)
      and (ATm.Duration > 0);
  end;

  { APPLYMORPHANIMATION over path lists [F3c]: AFrom the old paths (snap
    indices) -- one list, or one per old element (AFromMulti) -- ATo the new
    ones, one list or one per new element (AToMulti). The side of lists is
    the many, the other the one; with a list a side, the longer is the many.
    prepareMorphBatches deals the many's paths round the one's, and each
    batch morphs one to one, combines or separates, its animate index the
    many paths before it }
  procedure MorphPaths(const AFrom: array of TTyIntegerArray; AFromMulti: Boolean;
    const ATo: TNewRefLists; AToMulti: Boolean; const ADivide: string;
    ASer, AIndex: Integer);
  var
    tm: TTyAnimTiming;
    oneIdx: TTyIntegerArray;
    manyIdx: array of TTyIntegerArray;
    batches: TTyMorphBatchArray;
    oldFlat: TTyIntegerArray;
    newFlat: TNewRefArray;
    fromIsMany: Boolean;
    count, idx, x, y, n: Integer;
    olds_: TTyIntegerArray;
    news_: TNewRefArray;
  begin
    if (Length(AFrom) = 0) or (Length(ATo) = 0) then Exit;
    { a flat side is its first list }
    if (not AFromMulti) and (Length(AFrom[0]) = 0) then Exit;
    if (not AToMulti) and (Length(ATo[0]) = 0) then Exit;
    if not MorphTiming(ASer, AIndex, tm) then Exit;
    { every old path and every new one, numbered }
    oldFlat := nil;
    for x := 0 to High(AFrom) do
      for y := 0 to High(AFrom[x]) do
      begin
        SetLength(oldFlat, Length(oldFlat) + 1);
        oldFlat[High(oldFlat)] := AFrom[x][y];
      end;
    newFlat := nil;
    for x := 0 to High(ATo) do
      for y := 0 to High(ATo[x]) do
      begin
        SetLength(newFlat, Length(newFlat) + 1);
        newFlat[High(newFlat)] := ATo[x][y];
      end;
    manyIdx := nil;
    oneIdx := nil;
    if AFromMulti then
    begin
      fromIsMany := True;
      n := 0;
      SetLength(manyIdx, Length(AFrom));
      for x := 0 to High(AFrom) do
      begin
        SetLength(manyIdx[x], Length(AFrom[x]));
        for y := 0 to High(AFrom[x]) do
        begin
          manyIdx[x][y] := n;
          Inc(n);
        end;
      end;
      SetLength(oneIdx, Length(newFlat));
      for y := 0 to High(oneIdx) do oneIdx[y] := y;
    end
    else if AToMulti then
    begin
      fromIsMany := False;
      n := 0;
      SetLength(manyIdx, Length(ATo));
      for x := 0 to High(ATo) do
      begin
        SetLength(manyIdx[x], Length(ATo[x]));
        for y := 0 to High(ATo[x]) do
        begin
          manyIdx[x][y] := n;
          Inc(n);
        end;
      end;
      SetLength(oneIdx, Length(oldFlat));
      for y := 0 to High(oneIdx) do oneIdx[y] := y;
    end
    else
    begin
      fromIsMany := Length(oldFlat) > Length(newFlat);
      SetLength(manyIdx, 1);
      if fromIsMany then
      begin
        SetLength(manyIdx[0], Length(oldFlat));
        SetLength(oneIdx, Length(newFlat));
      end
      else
      begin
        SetLength(manyIdx[0], Length(newFlat));
        SetLength(oneIdx, Length(oldFlat));
      end;
      for y := 0 to High(manyIdx[0]) do manyIdx[0][y] := y;
      for y := 0 to High(oneIdx) do oneIdx[y] := y;
    end;
    batches := TyPrepareMorphBatches(oneIdx, manyIdx);
    count := 0;
    for x := 0 to High(batches) do count := count + Length(batches[x].Many);
    idx := 0;
    for x := 0 to High(batches) do
    begin
      if fromIsMany then
      begin
        SetLength(olds_, Length(batches[x].Many));
        for y := 0 to High(olds_) do olds_[y] := oldFlat[batches[x].Many[y]];
        if Length(olds_) = 1 then
          MorphOne(olds_[0], newFlat[batches[x].One], ADivide, ASer, tm, idx, count)
        else if Length(olds_) > 1 then
          Combine(olds_, newFlat[batches[x].One], ADivide, ASer, tm, idx, count);
      end
      else
      begin
        SetLength(news_, Length(batches[x].Many));
        for y := 0 to High(news_) do news_[y] := newFlat[batches[x].Many[y]];
        if Length(news_) = 1 then
          MorphOne(oldFlat[batches[x].One], news_[0], ADivide, ASer, tm, idx, count)
        else if Length(news_) > 1 then
          Separate(oldFlat[batches[x].One], news_, ADivide, ASer, tm, idx, count);
      end;
      idx := idx + Length(batches[x].Many);
    end;
  end;

  procedure TransitionBetween(const AOldList, ANewList: TTyIntegerArray;
    const AOldGroups, ANewGroups: array of TTyStringArray);
  var
    oldItems, newItems: TUtItemArray;
    useId, hasMorph: Boolean;
    still: TFPHashList;
    oldKeys, newKeys: TTyStringArray;
    oldMap, newMap: TFPHashList;
    oldGroups, newGroups: array of TTyIntegerArray;
    j, q, at: Integer;
    timing: TTyAnimTiming;
    p, rp: TTyChartAnimProxy;
    ne: TTyChartElement;
    done: Boolean;
    inner: TTyDataDiffCmdArray;
    ia, ib: TTyStringArray;
    role: string;

    procedure Flatten(AIsOld: Boolean; const AList_: TTyIntegerArray;
      const AGroups_: array of TTyStringArray; var AItems: TUtItemArray);
    var
      x, r, cnt: Integer;
      keys, groups, childs: TTyStringArray;
      divide: string;
    begin
      AItems := nil;
      for x := 0 to High(AList_) do
      begin
        if AIsOld then
        begin
          keys := APrev.Series[AList_[x]].Keys;
          groups := APrev.Series[AList_[x]].UtGroupIds;
          childs := APrev.Series[AList_[x]].UtChildGroupIds;
          divide := APrev.Series[AList_[x]].UtDivide;
        end
        else
        begin
          keys := ASeries[AList_[x]].Keys;
          groups := ASeries[AList_[x]].UtGroupIds;
          childs := ASeries[AList_[x]].UtChildGroupIds;
          divide := ASeries[AList_[x]].UtDivide;
        end;
        { [F3c] the groups a transition option reads instead }
        if x <= High(AGroups_) then groups := AGroups_[x];
        { universal transition is off past 10k items }
        if Length(keys) > cUtDataLimit then Continue;
        cnt := Length(AItems);
        SetLength(AItems, cnt + Length(keys));
        for r := 0 to High(keys) do
        begin
          AItems[cnt + r].Series := AList_[x];
          AItems[cnt + r].Row := r;
          AItems[cnt + r].Id := keys[r];
          { getGroupId: the encoded dimension, the groupId, else the
            dataGroupId, else the id; the childGroupId: the encoded
            dimension, the item's, else undefined [Batch 138] }
          if (r <= High(groups)) and (groups[r] <> '') then
            AItems[cnt + r].Group := Copy(groups[r], 2, MaxInt)
          else
            AItems[cnt + r].Group := keys[r];
          AItems[cnt + r].HasChild := (r <= High(childs)) and (childs[r] <> '');
          if AItems[cnt + r].HasChild then AItems[cnt + r].Child := Copy(childs[r], 2, MaxInt)
          else AItems[cnt + r].Child := '';
          AItems[cnt + r].Divide := divide;
        end;
      end;
    end;

    function StillIn(const AOi: TUtItem): Boolean;
    begin
      Result := (still <> nil) and (still.Find(KeyOf(AOi.Series, AOi.Row, 'ut')) <> nil);
    end;

    { updateOneToOne }
    procedure OneToOne(ANewIndex, AOldIndex: Integer);
    var
      oi, ni: TUtItem;
      ops, nes: TTyIntegerArray;
      k2: Integer;
      p2: TTyChartAnimProxy;
      tm: TTyAnimTiming;
      nr: TNewRefArray;
      ne2: TTyChartElement;
    begin
      oi := oldItems[AOldIndex];
      ni := newItems[ANewIndex];
      ops := OldPaths(oi.Series, oi.Row);
      nes := NewEls(ni.Series, ni.Row);
      { the same element (or none on either side) }
      if ((Length(ops) = 0) and (Length(nes) = 0))
        or ((Length(ops) > 0) and (Length(nes) > 0) and SameEl(oi.Series, oi.Row, ni.Series, ni.Row)) then
      begin
        if Length(nes) = 0 then Exit;
        { animateElementStyles: from the style the view saved, at update
          timing and the item's data index -- path by path, where the view
          saves one [F3c] }
        if not TyAnimGetConfig(atUpdate, ASeries[ni.Series].Model, TyAnimCallAt(ni.Row), tm) then
          Exit;
        for k2 := 0 to High(nes) do
        begin
          if k2 > High(ops) then Break;
          ne2 := AList.Element(nes[k2]);
          if not UtSavesOldStyleEl(ASeries[ni.Series].SeriesType, ne2) then Continue;
          p2 := HostProxy(ni.Series, ni.Row, ne2);
          SeedStyle(p2, ne2);
          p2.FUtStyleOn := True;
          p2.FUtPass := FPass;
          UtAnimate(p2, AUtSnaps[ops[k2]].Style, tm, True, False, '', @p2.UtStyleDone);
        end;
        Exit;
      end;
      { an element the new chart still has keeps its own transition }
      if (Length(ops) > 0) and StillIn(oi) then Exit;
      if Length(nes) = 0 then Exit;
      nr := NewRefs(ni.Series, ni.Row);
      if Length(ops) > 0 then
      begin
        DropGhost(oi.Series, oi.Row);
        hasMorph := True;
        MorphPaths([ops], False, TNewRefLists.Create(nr), False, ni.Divide, ni.Series, ANewIndex);
      end
      else
        for k2 := 0 to High(nr) do FadeIn(nr[k2], ni.Series, ANewIndex);
    end;

    { updateManyToOne }
    procedure ManyToOne(ANewIndex: Integer; const AOldIdx: TTyIntegerArray);
    var
      ni, oi: TUtItem;
      x: Integer;
      lists: array of TTyIntegerArray;
      oldSer: TTyIntegerArray;
      ops: TTyIntegerArray;
      nr: TNewRefArray;
    begin
      ni := newItems[ANewIndex];
      { the old elements: there, not the new one, not still in the chart }
      lists := nil;
      oldSer := nil;
      for x := 0 to High(AOldIdx) do
      begin
        oi := oldItems[AOldIdx[x]];
        ops := OldPaths(oi.Series, oi.Row);
        if Length(ops) = 0 then Continue;
        if SameEl(oi.Series, oi.Row, ni.Series, ni.Row) then Continue;
        if StillIn(oi) then Continue;
        SetLength(lists, Length(lists) + 1);
        lists[High(lists)] := ops;
        SetLength(oldSer, Length(oldSer) + 1);
        oldSer[High(oldSer)] := AOldIdx[x];
      end;
      if Length(NewEls(ni.Series, ni.Row)) = 0 then Exit;
      nr := NewRefs(ni.Series, ni.Row);
      if Length(lists) > 0 then
      begin
        for x := 0 to High(oldSer) do
          DropGhost(oldItems[oldSer[x]].Series, oldItems[oldSer[x]].Row);
        hasMorph := True;
        { prepareMorphBatches(one, many): the new paths, every old one dealt }
        MorphPaths(lists, True, TNewRefLists.Create(nr), False, ni.Divide, ni.Series, ANewIndex);
      end
      else
        { fadeInElement at the item's own data index }
        for x := 0 to High(nr) do FadeIn(nr[x], ni.Series, ni.Row);
    end;

    { updateOneToMany }
    procedure OneToMany(const ANewIdx: TTyIntegerArray; AOldIndex: Integer);
    var
      oi, ni: TUtItem;
      ops: TTyIntegerArray;
      x, y2, ser0: Integer;
      lists: TNewRefLists;
      keep: TTyIntegerArray;
    begin
      oi := oldItems[AOldIndex];
      ops := OldPaths(oi.Series, oi.Row);
      if (Length(ops) > 0) and StillIn(oi) then Exit;
      keep := nil;
      for x := 0 to High(ANewIdx) do
      begin
        ni := newItems[ANewIdx[x]];
        if Length(NewEls(ni.Series, ni.Row)) = 0 then Continue;
        if (Length(ops) > 0) and SameEl(oi.Series, oi.Row, ni.Series, ni.Row) then Continue;
        SetLength(keep, Length(keep) + 1);
        keep[High(keep)] := ANewIdx[x];
      end;
      if Length(keep) = 0 then Exit;
      ser0 := newItems[ANewIdx[0]].Series;
      { every new element stopped first }
      SetLength(lists, Length(keep));
      for x := 0 to High(keep) do
        lists[x] := NewRefs(newItems[keep[x]].Series, newItems[keep[x]].Row);
      if Length(ops) > 0 then
      begin
        DropGhost(oi.Series, oi.Row);
        hasMorph := True;
        { the old item's divideShape }
        MorphPaths([ops], False, lists, True, oi.Divide, ser0, ANewIdx[0]);
      end
      else
        for x := 0 to High(lists) do
          for y2 := 0 to High(lists[x]) do FadeIn(lists[x][y2], ser0, ANewIdx[0]);
    end;

    { THE DIRECTION [Batch 138]: the first new item whose groupId is an old
      item's childGroupId says parent -> child, the first whose (truthy)
      childGroupId is an old item's groupId child -> parent -- asked in
      that order, item by item; none else. Only truthy ids are kept. }
    function Direction: Integer;
    var
      og, oc: TFPHashList;
      x: Integer;
    begin
      Result := cUtDirNone;
      og := TFPHashList.Create;
      oc := TFPHashList.Create;
      try
        for x := 0 to High(oldItems) do
        begin
          if (oldItems[x].Group <> '') and (og.Find(oldItems[x].Group) = nil) then
            og.Add(oldItems[x].Group, Pointer(1));
          if oldItems[x].HasChild and (oldItems[x].Child <> '')
            and (oc.Find(oldItems[x].Child) = nil) then
            oc.Add(oldItems[x].Child, Pointer(1));
        end;
        for x := 0 to High(newItems) do
        begin
          if oc.Find(newItems[x].Group) <> nil then Exit(cUtDirP2C);
          if newItems[x].HasChild and (newItems[x].Child <> '')
            and (og.Find(newItems[x].Child) <> nil) then Exit(cUtDirC2P);
        end;
      finally
        og.Free;
        oc.Free;
      end;
    end;

    { createKeyGetter: the id, or by the direction the group or the child
      (undefined's key is 'undefined') }
    function ItemKey(const AItem: TUtItem; AUseChild: Boolean): string;
    begin
      if not AUseChild then Result := AItem.Group
      else if AItem.HasChild then Result := AItem.Child
      else Result := 'undefined';
    end;

    procedure IndexKeys(const AKeys: TTyStringArray; AMap: TFPHashList;
      var AGroups: array of TTyIntegerArray; out AOrder: TTyIntegerArray);
    var
      x, g, c2: Integer;
      v2: Pointer;
    begin
      AOrder := nil;
      for x := 0 to High(AKeys) do
      begin
        v2 := AMap.Find('_ec_' + AKeys[x]);
        if v2 = nil then
        begin
          g := Length(AOrder);
          SetLength(AOrder, g + 1);
          AOrder[g] := x;
          AMap.Add('_ec_' + AKeys[x], Pointer(PtrInt(g + 1)));
          SetLength(AGroups[g], 1);
          AGroups[g][0] := x;
        end
        else
        begin
          g := PtrInt(v2) - 1;
          c2 := Length(AGroups[g]);
          SetLength(AGroups[g], c2 + 1);
          AGroups[g][c2] := x;
        end;
      end;
    end;

  var
    oldOrder, newOrder: TTyIntegerArray;
    g, ng: Integer;
    v2: Pointer;
    ns, dir: Integer;
  begin
    Flatten(True, AOldList, AOldGroups, oldItems);
    Flatten(False, ANewList, ANewGroups, newItems);
    dir := Direction;
    { isAllIdSame }
    useId := Length(oldItems) = Length(newItems);
    if useId then
      for j := 0 to High(oldItems) do
        if oldItems[j].Id <> newItems[j].Id then
        begin
          useId := False;
          Break;
        end;
    still := nil;
    oldMap := TFPHashList.Create;
    newMap := TFPHashList.Create;
    try
      if not useId then
      begin
        { isElementStillInChart: an old element some new item still draws }
        still := TFPHashList.Create;
        for j := 0 to High(newItems) do
          for q := 0 to High(oldItems) do
            if (still.Find(KeyOf(oldItems[q].Series, oldItems[q].Row, 'ut')) = nil)
              and SameEl(oldItems[q].Series, oldItems[q].Row, newItems[j].Series, newItems[j].Row) then
              still.Add(KeyOf(oldItems[q].Series, oldItems[q].Row, 'ut'), Pointer(1));
      end;
      { the keys: getId when every id lines up, else the group -- the old
        side's childGroupId drilling down, the new side's drilling up
        [Batch 138] }
      SetLength(oldKeys, Length(oldItems));
      SetLength(newKeys, Length(newItems));
      for j := 0 to High(oldItems) do
        if useId then oldKeys[j] := oldItems[j].Id
        else oldKeys[j] := ItemKey(oldItems[j], dir = cUtDirP2C);
      for j := 0 to High(newItems) do
        if useId then newKeys[j] := newItems[j].Id
        else newKeys[j] := ItemKey(newItems[j], dir = cUtDirC2P);
      SetLength(oldGroups, Length(oldItems));
      SetLength(newGroups, Length(newItems));
      IndexKeys(oldKeys, oldMap, oldGroups, oldOrder);
      IndexKeys(newKeys, newMap, newGroups, newOrder);
      hasMorph := False;
      { DataDiffer 'multiple': the old keys in order }
      for g := 0 to High(oldOrder) do
      begin
        v2 := newMap.Find('_ec_' + oldKeys[oldOrder[g]]);
        if v2 = nil then Continue;
        ng := PtrInt(v2) - 1;
        if (Length(oldGroups[g]) > 1) and (Length(newGroups[ng]) = 1) then
          ManyToOne(newGroups[ng][0], oldGroups[g])
        else if (Length(oldGroups[g]) = 1) and (Length(newGroups[ng]) > 1) then
          OneToMany(newGroups[ng], oldGroups[g][0])
        else if (Length(oldGroups[g]) = 1) and (Length(newGroups[ng]) = 1) then
          OneToOne(newGroups[ng][0], oldGroups[g][0])
        else if (Length(oldGroups[g]) > 1) and (Length(newGroups[ng]) > 1) then
        begin
          { updateManyToMany: diffed again by id, one to one }
          SetLength(ia, Length(oldGroups[g]));
          SetLength(ib, Length(newGroups[ng]));
          for j := 0 to High(ia) do ia[j] := oldItems[oldGroups[g][j]].Id;
          for j := 0 to High(ib) do ib[j] := newItems[newGroups[ng][j]].Id;
          inner := TyDataDiff(ia, ib);
          for j := 0 to High(inner) do
            if inner[j].Kind = ddkUpdate then
              OneToOne(newGroups[ng][inner[j].NewIdx], oldGroups[g][inner[j].OldIdx]);
        end;
      end;
      { NOTHING LEFT WITHOUT AN ANIMATION in the new series' views: every path
        with no animator fades in from opacity 0 at update timing, index 0 }
      if hasMorph then
        for j := 0 to High(ANewList) do
        begin
          ns := ANewList[j];
          if not ASeries[ns].Enabled then Continue;
          if not TyAnimGetConfig(atUpdate, ASeries[ns].Model, TyAnimCallAt(0), timing) then Continue;
          if not (timing.Duration > 0) then Continue;
          for at := 0 to AList.Count - 1 do
          begin
            ne := AList.Element(at);
            if ne.Anim.Series <> ns then Continue;
            if ne.Anim.Role in [carLineRun, carLineArea] then
            begin
              if ne.Anim.Role = carLineRun then role := 'utFadeRun' else role := 'utFadeArea';
              if Find(ns, -1, role) <> nil then Continue;
              p := Make(ns, -1, role);
              p.SetNum('style.opacity', ne.Style.Alpha);
              p.FUtStyleOn := True;
              p.FUtPass := FPass;
              UtAnimate(p, TyAnimProps([Num1('style.opacity', 0)]), timing, True, False, '',
                @p.UtStyleDone);
              Continue;
            end;
            { a path of the view that is no item's (a treemap leaf's
              background: disableMorphing, no animator) [Batch 138] }
            role := UtFadeKey(ne);
            if role <> '' then
            begin
              if Find(ns, UtRowOf(ne), role) <> nil then Continue;
              p := Make(ns, UtRowOf(ne), role);
              p.SetNum('style.opacity', ne.Style.Alpha);
              p.FUtStyleOn := True;
              p.FUtPass := FPass;
              UtAnimate(p, TyAnimProps([Num1('style.opacity', 0)]), timing, True, False, '',
                @p.UtStyleDone);
              Continue;
            end;
            role := UtElKey(ne);
            if role = '' then Continue;
            p := Find(ns, UtRowOf(ne), role);
            { a line symbol's animators are its group's: its path has none
              unless the transition gave it one }
            if ne.Anim.Role = carLineSymbol then
              done := (p <> nil) and (p.FMorphOn or p.FUtStyleOn
                or (p.FCombineOn and (p.AnimatorCount > 0)))
            else
              done := (p <> nil) and ((p.AnimatorCount > 0) or p.FMorphOn);
            { [F3c] a path whose role animates it on a proxy of its own }
            { (a tagged path's role is its group's or its clip's: not the
              path's own animators) }
            if (not done) and (ne.Anim.UtTag = 0) and (TyChartAnimRoleKey(ne) <> '')
              and (TyChartAnimRoleKey(ne) <> role) then
            begin
              rp := Find(ns, KeyIndexOf(ne), TyChartAnimRoleKey(ne));
              done := (rp <> nil) and (rp.AnimatorCount > 0);
            end;
            if done then Continue;
            p := HostProxy(ns, UtRowOf(ne), ne);
            p.SetNum('style.opacity', ne.Style.Alpha);
            p.FUtStyleOn := True;
            p.FUtPass := FPass;
            UtAnimate(p, TyAnimProps([Num1('style.opacity', 0)]), timing, True, False, '',
              @p.UtStyleDone);
          end;
        end;
    finally
      still.Free;
      oldMap.Free;
      newMap.Free;
    end;
  end;

  { the last old series of a key that is kept (oldDataMap; -1 none) }
  function OldOfKey(const AKey: string): Integer;
  var k2: Integer;
  begin
    Result := -1;
    for k2 := 0 to High(APrev.Series) do
      if APrev.Series[k2].Present and (Length(APrev.Series[k2].Keys) < cUtDataLimit)
        and (APrev.Series[k2].UtKey = AKey) then
        Result := k2;
  end;

  { oldDataMapForSplit: the last old series whose list seriesKey holds AKey }
  function SplitOf(const AKey: string; out AListKey: string): Integer;
  var k2, m: Integer;
  begin
    Result := -1;
    AListKey := '';
    for k2 := 0 to High(APrev.Series) do
      if APrev.Series[k2].Present and (Length(APrev.Series[k2].Keys) < cUtDataLimit)
        and APrev.Series[k2].UtKeyList then
        for m := 0 to High(APrev.Series[k2].UtKeyItems) do
          if APrev.Series[k2].UtKeyItems[m] = AKey then
          begin
            Result := k2;
            AListKey := APrev.Series[k2].UtKey;
          end;
  end;

  function BatchOf(const AKey: string): Integer;
  var k2: Integer;
  begin
    Result := -1;
    for k2 := 0 to High(bKeys) do
      if bKeys[k2] = AKey then Exit(k2);
  end;

  { updateBatches.set: a key already there keeps its place }
  procedure SetBatch(const AKey: string; const AOldL, ANewL: TTyIntegerArray);
  var b2: Integer;
  begin
    b2 := BatchOf(AKey);
    if b2 < 0 then
    begin
      b2 := Length(bKeys);
      SetLength(bKeys, b2 + 1);
      SetLength(bOld, b2 + 1);
      SetLength(bNew, b2 + 1);
      bKeys[b2] := AKey;
    end;
    bOld[b2] := AOldL;
    bNew[b2] := ANewL;
  end;

  { the types whose item paths the port draws for a morph; a batch with any
    other keeps its own animation }
  function TypesOkOf(const AOldL, ANewL: TTyIntegerArray): Boolean;
  var k2: Integer;
  begin
    Result := (Length(AOldL) > 0) and (Length(ANewL) > 0);
    for k2 := 0 to High(AOldL) do
      if not UtTypeMorphs(APrev.Series[AOldL[k2]].SeriesType) then Result := False;
    for k2 := 0 to High(ANewL) do
      if not UtTypeMorphs(ASeries[ANewL[k2]].SeriesType) then Result := False;
  end;

  { THE TRANSITION OPTION (transitionSeriesFromOpt) [F3c]: the old series
    its `from` finders name, by index or id (the first that answers, a
    finder at a time), and the new ones its `to` names -- whose groups fall
    back on the dataGroupId of the OLD series at their index, as upstream's
    do; both sides found or nothing }
  procedure FromOption(const AItem: TTyUtTransitionItem);
  var
    fromL, toL: TTyIntegerArray;
    fromG, toG: array of TTyStringArray;
    f, k2, hit: Integer;
  begin
    fromL := nil;
    toL := nil;
    fromG := nil;
    toG := nil;
    for f := 0 to High(AItem.From) do
    begin
      hit := -1;
      for k2 := 0 to High(APrev.Series) do
        if APrev.Series[k2].Present and (Length(APrev.Series[k2].Keys) < cUtDataLimit)
          and TyUtFinderMatches(AItem.From[f], k2, APrev.Series[k2].UtModelId) then
        begin
          hit := k2;
          Break;
        end;
      if hit < 0 then Continue;
      SetLength(fromL, Length(fromL) + 1);
      fromL[High(fromL)] := hit;
      SetLength(fromG, Length(fromG) + 1);
      fromG[High(fromG)] := APrev.Series[hit].UtGroupIds;
    end;
    for f := 0 to High(AItem.To_) do
    begin
      hit := -1;
      for k2 := 0 to High(ASeries) do
        if ASeries[k2].Present and TyUtFinderMatches(AItem.To_[f], k2, ASeries[k2].UtModelId) then
        begin
          hit := k2;
          Break;
        end;
      if hit < 0 then Continue;
      SetLength(toL, Length(toL) + 1);
      toL[High(toL)] := hit;
      SetLength(toG, Length(toG) + 1);
      { globalStore.oldDataGroupIds[idx]: the old series' at the new one's
        index -- none there is undefined }
      if (hit <= High(APrev.Series)) and APrev.Series[hit].Present then
        toG[High(toG)] := TyUtRowGroupsWith(ASeries[hit].UtGroupOwn, APrev.Series[hit].UtDataGroup)
      else
        toG[High(toG)] := TyUtRowGroupsWith(ASeries[hit].UtGroupOwn, '');
    end;
    if (Length(fromL) > 0) and (Length(toL) > 0) and TypesOkOf(fromL, toL) then
      TransitionBetween(fromL, toL, fromG, toG);
  end;

begin
  { series:transition runs on a setOption only (optionChanged) }
  if APrev.FullUpdate then Exit;
  newIdx := TFPHashList.Create;
  try
    { THE NEW ITEMS' PATHS, in getPathList's order [F3c] }
    newItems := nil;
    newOrders := nil;
    for i := 0 to AList.Count - 1 do
    begin
      el := AList.Element(i);
      key := UtElKey(el);
      if key = '' then Continue;
      v := newIdx.Find(KeyOf(el.Anim.Series, UtRowOf(el), 'ut'));
      if v = nil then
      begin
        it := Length(newItems);
        SetLength(newItems, it + 1);
        SetLength(newOrders, it + 1);
        newItems[it] := nil;
        newOrders[it] := nil;
        newIdx.Add(KeyOf(el.Anim.Series, UtRowOf(el), 'ut'), Pointer(PtrInt(it + 1)));
      end
      else
        it := PtrInt(v) - 1;
      { a place already taken keeps its first }
      at := -1;
      for q := 0 to High(newOrders[it]) do
        if newOrders[it][q] = UtElOrder(el) then at := q;
      if at >= 0 then Continue;
      at := Length(newItems[it]);
      while (at > 0) and (newOrders[it][at - 1] > UtElOrder(el)) do Dec(at);
      SetLength(newItems[it], Length(newItems[it]) + 1);
      SetLength(newOrders[it], Length(newOrders[it]) + 1);
      for q := High(newItems[it]) downto at + 1 do
      begin
        newItems[it][q] := newItems[it][q - 1];
        newOrders[it][q] := newOrders[it][q - 1];
      end;
      newItems[it][at] := i;
      newOrders[it][at] := UtElOrder(el);
    end;
    { [F3c] SETOPTION'S TRANSITION, where it is given, instead of the keys }
    if APrev.UtHasTransition then
    begin
      for k := 0 to High(APrev.UtTransition) do FromOption(APrev.UtTransition[k]);
      Exit;
    end;
    { findTransitionSeriesBatches: an updated series that asks for it and
      animates; the old series of the same key (the last one with it) --
      else, a list key, the old series of its items (merged); else the old
      series whose list holds its key (split, the batch under the list's
      key). A batch is set again by a later series of the same key. }
    bKeys := nil;
    for s := 0 to High(ASeries) do
    begin
      if not ASeries[s].Present or not ASeries[s].UtOn or not ASeries[s].Enabled then Continue;
      o := OldOfKey(ASeries[s].UtKey);
      if o >= 0 then
      begin
        SetBatch(ASeries[s].UtKey, TTyIntegerArray.Create(o), TTyIntegerArray.Create(s));
        Continue;
      end;
      if ASeries[s].UtKeyList then
      begin
        { 'female', 'male' -> ['female', 'male'] -- an item with no old
          series is left out (upstream reads `.data` of undefined and throws) }
        olds := nil;
        for k := 0 to High(ASeries[s].UtKeyItems) do
        begin
          o := OldOfKey(ASeries[s].UtKeyItems[k]);
          if o < 0 then Continue;
          SetLength(olds, Length(olds) + 1);
          olds[High(olds)] := o;
        end;
        if Length(olds) > 0 then SetBatch(ASeries[s].UtKey, olds, TTyIntegerArray.Create(s));
        Continue;
      end;
      { ['female', 'male'] -> 'female', 'male' }
      o := SplitOf(ASeries[s].UtKey, lk);
      if o < 0 then Continue;
      b := BatchOf(lk);
      if b < 0 then
      begin
        SetBatch(lk, TTyIntegerArray.Create(o), nil);
        b := BatchOf(lk);
      end;
      SetLength(bNew[b], Length(bNew[b]) + 1);
      bNew[b][High(bNew[b])] := s;
    end;
    for b := 0 to High(bKeys) do
    begin
      typesOk := TypesOkOf(bOld[b], bNew[b]);
      if typesOk then TransitionBetween(bOld[b], bNew[b], [], []);
    end;
  finally
    newIdx.Free;
  end;
end;

procedure TyAnimBuildFrame(ASource, ADest: TTyPaintList;
  const ABind: TTyChartAnimProxyArray; ASet: TTyChartAnimSet;
  const AStBind: TTyChartAnimProxyArray);

  { the transition proxy of the element at AAt (its key's) }
  function UtProxyAt(const AEl: TTyChartElement; AAt: Integer): TTyChartAnimProxy;
  var key2: string;
  begin
    Result := nil;
    key2 := UtElKey(AEl);
    if key2 = '' then Exit;
    if (AAt <= High(ABind)) and (ABind[AAt] <> nil) and (ABind[AAt].FRole = key2) then
      Result := ABind[AAt]
    else if ASet <> nil then
      Result := ASet.Find(AEl.Anim.Series, UtRowOf(AEl), key2);
  end;

  { [F3c] a label's anchor at rest and on its host's morph frame; False
    where the host does not morph or the label reads a sector }
  function LabelOnMorph(const AHostS, AHostF, ALabel: TTyChartElement; AAt: Integer;
    out AX0, AY0, AX1, AY1: Double): Boolean;
  var
    hp: TTyChartAnimProxy;
    r: TTyXYWH;
    tmp: TTyChartElement;
    m: TTyMat2D;
    k2: Integer;
  begin
    Result := False;
    hp := UtProxyAt(AHostS, AAt);
    if (hp = nil) or not hp.FMorphOn or hp.FCombineOn then Exit;
    if AHostS.Caption.SecHas and (ALabel.Anim.LabelPos >= 100) then Exit;
    r := TyPathDataRect(TyMorphPathData(hp.FMorph, NumOr(hp, '__morphT', 0)));
    tmp := AHostS;
    if AHostS.Caption.HasHostBox then
    begin
      for k2 := 0 to 5 do m[k2] := 0;
      tmp.Caption.HostBox := TyPathStrokeRect(r,
        (((AHostF.Style.StrokeColor shr 24) and $FF) > 0) and (AHostF.Style.StrokeWidthLogical > 0),
        AHostF.Style.HasFill, AHostF.Style.StrokeWidthLogical, False, False, m);
    end
    else
    begin
      tmp.Shape := Default(TTyChartShape);
      tmp.Shape.Kind := cskRect;
      tmp.Shape.Bounds := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
    end;
    tmp.Caption.SecHas := False;
    AnchorOn(AHostS, ALabel, AX0, AY0);
    AnchorOn(tmp, ALabel, AX1, AY1);
    Result := True;
  end;

var
  i, h, k, nx: Integer;
  el: TTyChartElement;
  x0, y0, x1, y1, dx, dy: Double;
  moved: Boolean;
  g, bp: TTyChartAnimProxy;
  extras: array of TTyChartElement;
  key: string;
begin
  if (ASource = nil) or (ADest = nil) then Exit;
  ADest.Clear;
  extras := nil;
  nx := 0;
  for i := 0 to ASource.Count - 1 do
  begin
    { one copy, the one the frame keeps: read in place [P2] }
    el := ASource.Ref(i)^;
    if (i <= High(ABind)) and (ABind[i] <> nil) then TyAnimApply(el, ABind[i]);
    { A MORPH and a universal transition's style [Batch 136]; a treemap
      rect's from the set, its proxy role being none [Batch 138] }
    { [F3c] the proxy of the path's own key: its role's where that is the
      one, else the set's }
    bp := nil;
    key := UtElKey(el);
    if key = '' then key := UtFadeKey(el);
    if key <> '' then
    begin
      if (i <= High(ABind)) and (ABind[i] <> nil) and (ABind[i].FRole = key) then bp := ABind[i]
      else if ASet <> nil then bp := ASet.Find(el.Anim.Series, UtRowOf(el), key);
    end;
    if bp <> nil then TyUtApply(el, bp);
    if (ASet <> nil) and (el.Anim.Role in [carLineRun, carLineArea]) then
    begin
      if el.Anim.Role = carLineRun then g := ASet.Find(el.Anim.Series, -1, 'utFadeRun')
      else g := ASet.Find(el.Anim.Series, -1, 'utFadeArea');
      if (g <> nil) and g.FUtStyleOn then
        el.Style.Alpha := NumOr(g, 'style.opacity', el.Style.Alpha);
    end;
    { THE STATES [Batch 94] }
    if (i <= High(AStBind)) and (AStBind[i] <> nil) then
      TyAnimApplyState(el, AStBind[i], (i <= High(ABind)) and (ABind[i] = AStBind[i]));
    { [F3a] A TREE NODE'S GROUP slides on a proxy of its own; a label placed
      on its own rides it too }
    if (ASet <> nil) and ((el.Anim.Role = carTreeNode) or el.Anim.RideTree) then
    begin
      g := ASet.Find(el.Anim.Series, el.Anim.Index, 'treeGroup');
      if (g <> nil) and not g.AtFinal then
      begin
        dx := (NumOr(g, 'x', el.Anim.G[5]) - el.Anim.G[5]) * el.Anim.G[7];
        dy := (NumOr(g, 'y', el.Anim.G[6]) - el.Anim.G[6]) * el.Anim.G[7];
        if el.Anim.RideTree then MoveCaption(el, dx, dy)
        else MoveSymbol(el, dx, dy);
      end;
    end;
    { A COMBINING ELEMENT IS DRAWN AS ITS CHILDREN [Batch 137]: the first in
      its place, the others after the list, silent (insertion indices kept);
      a child has its own style -- the element's states are not its }
    if (bp <> nil) and bp.FCombineOn and (Length(bp.FPieces) > 0) then
    begin
      for k := 1 to High(bp.FPieces) do
      begin
        if nx >= Length(extras) then SetLength(extras, nx * 2 + 8);
        extras[nx] := el;
        UtPieceApply(extras[nx], bp.FPieces[k], k);
        extras[nx].Silent := True;
        Inc(nx);
      end;
      UtPieceApply(el, bp.FPieces[0], 0);
    end;
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
    { [F3a] A GRAPH EDGE'S LABEL is placed from its line's percent, whatever
      its own fade does }
    if (ASet <> nil) and (el.Anim.Role = carGraphEdgeLabel) then
    begin
      g := ASet.Find(el.Anim.Series, el.Anim.Index, 'gedge');
      if (g <> nil) and not g.AtFinal then GraphEdgeFrom(el, g.Num('shape.percent'));
    end;
    h := el.Anim.HostPlus1 - 1;
    { [F3c] A TEXT ON A MORPHING HOST rides the morph frame: zrender lays a
      textContent out on its host's bounding rect, which the replaced
      buildPath draws (with no transform) -- its stroke in it as
      Path.getBoundingRect grows it. A sector's own positions read the
      shape, which a morph leaves as it is. }
    if (el.Anim.Role = carLabel) and (h >= 0) and (h < i)
      and LabelOnMorph(ASource.Element(h), ADest.Element(h), el, h, x0, y0, x1, y1) then
    begin
      dx := x1 - x0;
      dy := y1 - y0;
      if (not IsNan(dx)) and (not IsNan(dy)) and ((dx <> 0) or (dy <> 0)) then
      begin
        el.Caption.X := el.Caption.X + dx;
        el.Caption.Y := el.Caption.Y + dy;
        el.Shape.Bounds := TyRectF(el.Shape.Bounds.Left + dx, el.Shape.Bounds.Top + dy,
          el.Shape.Bounds.Right + dx, el.Shape.Bounds.Bottom + dy);
      end;
    end
    { (a tree node's group slides on after its symbol rests) }
    else if (el.Anim.Role = carLabel) and (h >= 0) and (h < i)
      and (h <= High(ABind)) and (ABind[h] <> nil)
      and (not ABind[h].AtFinal or (ASource.Ref(h)^.Anim.Role = carTreeNode)) then
    begin
      AnchorOn(ASource.Ref(h)^, el, x0, y0);
      AnchorOn(ADest.Ref(h)^, el, x1, y1);
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
  for i := 0 to nx - 1 do ADest.Add(extras[i]);
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
