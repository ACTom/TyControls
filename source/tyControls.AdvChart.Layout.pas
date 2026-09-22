unit tyControls.AdvChart.Layout;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the box layout solver.

  CONTRACT 1, second half (see the Tier 0 spec §2). The solver takes an
  ITyBoxContainer, never a rect. Two implementations ship here:

    TyFixedContainer     — a literal rect (the control's client area, top level)
    TyCoordCellContainer — one datum's cell in another coordinate system, which
                           is coordinateSystemUsage:'box' in its smallest form

  Both go through the SAME TySolveBox. Had a component been written against "the
  control's client rect", nesting it later would be a rewrite; written against a
  provider, nesting is a different argument.

  The provider is an INTERFACE rather than a rect parameter because when nesting,
  the container is not known until the HOST has been laid out — the value has to
  be fetched late, not passed early.

  PURE: SysUtils, Math, fcl-json and the AdvChart units. No Controls, no
  Graphics, no handle.

  IT HAS GROWN PAST ITS NAME, on purpose. What lives here now is every rule
  ABOUT A TTyBoxValue -- how one resolves against a base, how one is read out
  of an option, how a pair of them becomes a centre -- plus the linear map that
  every series with a scale needs. Each arrived the same way: a second series
  was about to ask the first one how it worked, and the answer belongs where
  the TYPE is, not beside whichever caller wanted it first. }
interface
uses SysUtils, Math, fpjson,
     tyControls.AdvChart.Types, tyControls.AdvChart.Coord;

type
  { How one edge or size is expressed. }
  TTyBoxUnit = (buAuto, buPx, buPercent, buCentre);

  TTyBoxValue = record
    Kind: TTyBoxUnit;
    Value: Double;
  end;

  { left/top/right/bottom/width/height, each optional. Redundant constraints are
    resolved by PRECEDENCE, never by an error: on each axis (start, size) wins
    over (start, end) wins over (end, size). ECharts resolves the same way. }
  TTyBoxSpec = record
    Left, Top, Right, Bottom, Width, Height: TTyBoxValue;
  end;

  ITyBoxContainer = interface
    ['{8D31C60F-4A72-4B95-BE28-3F7A05D6C914}']
    function ContainerRect: TTyRectF;
  end;

function TyBoxSpec: TTyBoxSpec;              { every field buAuto }
function TyBoxPx(AValue: Double): TTyBoxValue;
function TyBoxPercent(AValue: Double): TTyBoxValue;
function TyBoxCentre: TTyBoxValue;
function TyBoxAuto: TTyBoxValue;

{ ONE BOX VALUE AGAINST A BASE -- upstream's parsePercent, in the only form
  this family needs. Here rather than beside the first caller that wanted it:
  it is a rule about TTyBoxValue, and a second series asking a PIE how to read
  a percentage is the borrowed-name mistake wearing another hat. }
function TyBoxResolve(const AValue: TTyBoxValue; ABase: Double): Double;

{ ONE OPTION VALUE READ AS A BOX VALUE -- upstream's parsePositionOption.

  A number is pixels; a string ending in `%` is a percentage; the six position
  words are the percentages they name. Anything else -- including an array, an
  object or a null -- answers ADefault rather than raising, which is the rule
  every reader in this family follows.

  ONE COPY. There were four, and they had already drifted: two accepted the
  British spelling of `centre` and two did not, and two answered buCentre where
  the others answered buPercent(50). Those two resolve identically, which is
  exactly why nobody noticed. }
function TyBoxDataOf(AData: TJSONData; const ADefault: TTyBoxValue): TTyBoxValue;
function TyBoxValueOf(ANode: TJSONObject; const AKey: string;
  const ADefault: TTyBoxValue): TTyBoxValue;
{ The STRING half on its own, for the options that stringify before they parse.
  `symbolMargin` is the one that needs it: upstream appends an empty string to
  whatever it finds, so even a number goes through the string parser -- which
  is why `'20px'` reads as twenty and `'10,20'` as ten. }
function TyBoxStrOf(const AText: string; const ADefault: TTyBoxValue): TTyBoxValue;

{ The leading number of a string, as JavaScript's parseFloat reads one: as
  much of the front as looks like a number. False when the front is not a
  number at all. Exported because it is a rule about reading OPTIONS and not
  about boxes -- `symbolMargin` needs it too. }
function TyLeadingNumber(const AText: string; out AValue: Double): Boolean;

{ A CENTRE AND THE BASE ITS RADIUS IS MEASURED AGAINST, from one rect.

  TWO DIFFERENT BASES, and that is the whole reason this is a function: the
  centre's percentages run against the rect's width and height SEPARATELY,
  while a radius' run against half its SHORTER side. A pie and a gauge both
  need it; sharing one base would put a doughnut's hole off centre on any
  rectangle that is not square. }
procedure TySolveCircle(const ACentreX, ACentreY: TTyBoxValue;
  const AViewport: TTyRectF; out ACX, ACY, ARadiusBase: Double);

{ upstream's linearMap: AValue carried from one interval to another.

  THE DEGENERATE DOMAIN IS THE BRANCH A PORT GETS WRONG, and it is not an edge
  case: every value equal is what a funnel of equal steps looks like, and
  `min: 50, max: 50` is a legal gauge. The answer is the MIDPOINT of the range,
  not its start and not zero -- so a port that guarded "denominator is zero,
  answer zero" draws nothing exactly where upstream draws half-width bands.
  When the range is degenerate too the answer is its start, which for finite
  numbers is the same thing said without an overflow.

  AClamp pins a value outside the domain to the nearer end. BOTH DIRECTIONS
  ARE HANDLED: neither the domain nor the range is required to ascend, and a
  gauge running anticlockwise has a descending range.

  NaN ANSWERS ARangeLo. Upstream lets it through every comparison and returns
  NaN; here an ordered comparison against a quiet NaN would RAISE, so the test
  comes first and the answer is the one a caller can draw. }
function TyLinearMap(AValue, ADomainLo, ADomainHi, ARangeLo, ARangeHi: Double;
  AClamp: Boolean): Double;

function TyFixedContainer(const ARect: TTyRectF): ITyBoxContainer;
function TyCoordCellContainer(const ACoordSys: ITyCoordSys;
  const AData: array of Double): ITyBoxContainer;

{ The one solver. Every component's rect comes from here. }
function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer): TTyRectF;
{ The same, with a MARGIN: space kept outside the solved rect on each edge,
  in CSS order (top, right, bottom, left).

  ECharts calls this a component's `padding` and getLayoutRect takes it as a
  margin, and the naming is not a slip on either side -- the space is outside
  the box the layout solves, and conventionally the component's own
  background covers it. title and legend both position themselves this way. }
function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer;
  const AMargin: array of Double): TTyRectF; overload;

{ ==================== TWO-PHASE AXIS BUILD (Tier 0 item 12) ====================
  estimate the labels -> shrink the rect -> determine the placements.

  UPSTREAM'S layOutGridByOuterBounds (v6), whole. The grid's own rect is the
  RAW rect; the labels are laid out on it as they would be drawn, and the plot
  shrinks only by how far they OVERFLOW the outer bounds -- by default the
  whole canvas. A chart whose labels fit on the canvas keeps its grid exactly
  as written. Along an axis the overflow is divided by how far along the axis
  the label sits (shrinking the plot moves a label at 40% of the way by only
  40% of the shrink); across it, it counts as it is. Each side takes the
  largest, never the sum, and a side never shrinks below the clamp.
    obmNone -- no outer bounds: the raw rect IS the plot.
    obmAuto -- the outer bounds are grid.outerBounds on the canvas.
    obmSame -- the outer bounds are the raw rect itself.
  Legacy grid.containLabel is its own rule (TyLegacyContainLabel): the
  widest label's room taken off each side, summed.
  [Revised in batch 37: the port reserved every axis' thickness INSIDE the
  grid's rect, summed per side -- which is containLabel, not v6's default --
  and every chart's plot came out some thirty pixels smaller than
  upstream's.]

  THE TWO PHASES DO NOT ITERATE, and upstream's do not either: the labels are
  estimated once on the raw rect and determined once on the final one, and a
  label the shrink has moved is not asked again.

  NOT DONE HERE, deliberately: nameMoveOverlap (v6's shuffle when an axis name
  collides with the end label). That is its own feature, not part of the pass. }

type
  { TTyAxisSide moved down to AdvChart.Types -- Coord needs it and Layout
    already uses Coord. Re-exported here so no caller has to change its uses. }
  TTyAxisSide = tyControls.AdvChart.Types.TTyAxisSide;
  TTyOuterBoundsMode = (obmNone, obmAuto, obmSame);
  { Whether an axis' NAME counts toward the space reserved, or only its labels. }
  TTyOuterBoundsContain = (obcAxisLabel, obcAll);

  { What the caller resolved FROM THE THEME for one axis' text: the label font
    and the three gaps. A record rather than six loose parameters because every
    one of them is a theme token, and a caller that fills some and forgets the
    rest is exactly the bug this replaced -- the layout pass measured labels in
    a hardcoded 12pt with no font name while the paint pass drew them in the
    theme's font, so a skin with a larger label font got a plot rect measured
    too small for the labels it would then draw.

    No defaults live here. This unit knows nothing about themes, and a default
    would be the same hardcoding one layer down. }
  TTyAxisTextStyle = record
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    { The weight an EMPHASISED label is drawn in -- a time axis' coarse
      ticks. Resolved from the theme by the caller, like everything else in
      this record, because a weight is a visual value and this library does
      not put those in control code. }
    EmphasisFontWeight: Integer;
    LabelMarginLogical: Double;
    TickLengthLogical: Double;
    NameGapLogical: Double;
    { The axis NAME's font, which the layout measures the name in: the same
      one the paint pass draws it in, and not always the labels'. }
    NameFontName: string;
    NameFontSizeLogical: Integer;
    NameFontWeight: Integer;
  end;

  { One laid-out label, ready to hand to TTyPainter.DrawTextRotated: the anchor
    plus how the box sits on it. Layout and paint therefore cannot disagree
    about where a label went. }
  { `axisLabel.showMinLabel` / `showMaxLabel`.

    THREE STATES, and the default is the third one. Upstream's default is
    `null`, which is neither `true` nor `false`: under it an end label is
    shown when the interval landed on it and hidden when it did not, which is
    a question neither Boolean can ask. A two-state port defaulting to True
    would show every ragged end label on every thinned axis; defaulting to
    False would lose the ends of every axis that is not thinned at all. }
  TTyAxisEndLabel = (aelAuto, aelShow, aelHide);

  { WHICH RULES PICK AN AXIS' LABELS. A category axis builds only every
    interval-th label, the interval measured or written; a value or log axis
    and a time axis build every tick and never thin one by its index. All
    three then lose an end label that crowds its neighbour, and any label that
    crowds a kept one under hideOverlap. The zero value is the one that never
    thins, so a spec that says nothing hides nothing by position. }
  TTyLabelAxisKind = (lakValue, lakCategory, lakTime);

  TTyAxisLabelPlacement = record
    Index: Integer;
    Text: string;
    X, Y: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    { in the list upstream builds -- every value tick, a category axis' every
      interval-th and its two ends -- whether or not it survives the overlap
      rules }
    Built: Boolean;
    { a category axis' end that the interval did not land on }
    OffInterval: Boolean;
    Shown: Boolean;
    { Drawn in the heavier weight. Carried on the PLACEMENT and not looked up
      again at paint time, because the measurement that reserved room for this
      label was made in that same weight. }
    Emphasis: Boolean;
  end;
  TTyAxisLabelPlacementArray = array of TTyAxisLabelPlacement;

  { ONE TICK MARK, SPLIT LINE OR SPLIT-AREA EDGE, where the layout put it: the
    tick it stands for (a category axis' ordinal; the category past the last
    for the closing band edge), its place in device px along the axis,
    whether it was moved onto a band edge, and whether it is drawn -- a tick
    whose label was hidden goes with it, a split line at an end can be
    denied. }
  TTyAxisMark = record
    Value: Double;
    Coord: Double;
    OffInterval: Boolean;
    OnBand: Boolean;
    Drawn: Boolean;
  end;
  TTyAxisMarkArray = array of TTyAxisMark;

  { x, y, width and height: upstream's own shape for a rect. The shrink and
    the name layout are done in it so that their arithmetic is upstream's to
    the bit -- a right edge is x + width there, and a width taken back from
    one is not always the same number. }
  TTyXYWH = record
    X, Y, W, H: Double;
  end;

  { zrender's 2-D affine matrix [a, b, c, d, tx, ty]:
    x' = a x + c y + tx, y' = b x + d y + ty. }
  TTyMat2D = array[0..5] of Double;

  { nameLocation: 'end' is upstream's default and so the zero value;
    'center' is 'middle'. }
  TTyAxisNameLocation = (anlEnd, anlStart, anlMiddle);
  { What pads the box round a name: the level table (the zero value, and
    upstream's default), nameTextStyle.textMargin in its place, or no local
    padding but the drawn rect grown by half of nameTextStyle.minMargin. }
  TTyNameMarginKind = (nmkLevel, nmkTextMargin, nmkMinMargin);

  { UPSTREAM'S AXIS FRAME for one pass (cartesianAxisHelper): the axis
    group's origin -- the line at the axis' start -- and its turn, the
    axis' extent along itself, how far the labels stand from the line (a
    line on the other axis' zero leaves them at the edge), and which side
    is out. A name is laid out in it. }
  TTyAxisNameFrame = record
    PosX, PosY: Double;
    Rotation: Double;
    Ext0, Ext1: Double;
    LabelOffset: Double;
    NameDirection: Integer;
    Inverse: Boolean;
  end;

  { WHERE AN AXIS NAME IS DRAWN, decided by the layout so that the paint pass
    and the grid's shrink read one answer. X, Y is the point the text hangs
    by (AnchorH, AnchorV), RotationRad its turn, counter-clockwise; Rect the
    padded box round it on the screen, which is what the shrink counts. }
  TTyAxisNamePlacement = record
    Shown: Boolean;
    Text: string;
    Location: TTyAxisNameLocation;
    Level: Integer;
    { before any move -- where nameLocation and nameGap put it }
    AnchorX, AnchorY: Double;
    X, Y: Double;
    MovedX, MovedY: Double;
    LocalRotationRad, RotationRad: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    LocalRect: TTyXYWH;
    M: TTyMat2D;
    { the box on the screen before the move, and after it }
    PreRect: TTyXYWH;
    Rect: TTyXYWH;
    AxisAligned: Boolean;
    { how many times it was moved }
    Moves: Integer;
    { a middle name's obstacle, in the axis' own frame: every shown label and
      the line. Only when there was a label to make it from. }
    HasOccupied: Boolean;
    Occupied: TTyXYWH;
    { along its own axis: one half for a middle name, none for an end one }
    Proportion: Double;
  end;
  TTyAxisNamePlacementArray = array of TTyAxisNamePlacement;
  { Everything one axis needs to lay itself out. Pure data: the caller has
    already resolved the font and formatted the labels, because deciding what a
    tick says is the scale's job and this unit does not know about scales. }
  TTyAxisLayoutSpec = record
    Side: TTyAxisSide;
    ShowLabels: Boolean;
    Labels: TTyStringArray;
    { Each label's place along the axis, as a fraction 0..1 of the axis' own
      extent measured from its start. Parallel to Labels. }
    Positions: TTyDoubleArray;
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    { COUNTER-CLOCKWISE positive, matching TTyPainter.DrawTextRotated. }
    RotationRad: Double;
    LabelMarginLogical: Double;
    TickLengthLogical: Double;
    Name: string;
    NameGapLogical: Double;
    { axisLabel.width, LOGICAL px; <= 0 means unbounded. Only loTruncate reads
      it at paint time -- for loBreak the labels arrive already broken. }
    LabelWidthLogical: Double;
    LabelOverflow: TTyLabelOverflow;
    { WHAT PHASE C DECIDED ABOUT THESE LABELS, so the paint pass does not decide
      it again. Both are derived by measuring EVERY label, and the paint pass
      used to call TyAxisLabelStep and TyLayoutAxisLabels itself -- ten thousand
      measurements a frame at 5,000 categories, to choose the twenty that get
      drawn.

      LabelStep is 1 when nothing is thinned. Placements holds one entry per
      label, shown or not; the renderer draws labels from nowhere else. }
    LabelStep: Integer;
    Placements: TTyAxisLabelPlacementArray;
    { WHAT THIS AXIS ACTUALLY DRAWS, resolved by the builder from the option
      and from upstream's per-type defaults. Only the two that cost SPACE are
      here -- the rest are paint-time questions and the renderer asks the
      builder for them directly.

      A tick that is hidden, or that points into the plot, reserves nothing
      outside it. Same for a label. That is the whole reason these two are a
      layout question: switch the ticks off and the plot gets five pixels
      wider on that side, which is what upstream does and what makes a
      tickless axis look deliberate rather than merely bald. }
    ShowTicks: Boolean;
    TickInside: Boolean;
    LabelInside: Boolean;
    { `axis.offset`, LOGICAL px. How far outside the plot's edge this axis
      sits -- which is how two axes on one side are separated, because
      upstream draws them both on the edge otherwise. }
    OffsetLogical: Double;

    { ---- three things a TIME axis says about its labels ----

      All three are empty or False on every other axis, which is what a fresh
      record already is, so nothing that builds a spec has to know they exist.
      They are flags rather than a scale reference because this unit is pure:
      deciding what a tick SAYS is the scale's job and the layout is only told
      the answer. }

    { A TIME AXIS' RAGGED ENDS: the data's own boundaries, not a round tick.
      Built like any label, and hidden unless showMinLabel / showMaxLabel says
      otherwise -- a `07:13` jammed against the first round hour is the most
      visible mark of a careless port, and one the author asked for is theirs.
      [Revised in batch 39: LabelHidden, never drawn whatever the option.] }
    LabelNotNice: TTyBoolArray;
    { A time label's level, which is its priority under hideOverlap: the
      coarser ticks are kept first. }
    LabelLevel: TTyIntegerArray;
    { Which labels carry the heavier weight: on a time axis the coarse ticks,
      the ones that say `Mar` among a run of day numbers. }
    LabelEmphasis: TTyBoolArray;
    { The weight those get. Nought means the spec's own weight, so an axis
      that marks no label for emphasis need not name one. }
    EmphasisFontWeight: Integer;
    { THE RULES THIS AXIS' LABELS ARE PICKED BY. Only a category axis is
      thinned by index; upstream never drops a value, log or time label for its
      position, only for crowding.
      [Revised in batch 39: KeepEveryLabel, set on time axes alone, so value
      and log axes were thinned like categories.] }
    LabelKind: TTyLabelAxisKind;
    { `axisLabel.interval: 0` exactly, on a category axis: every label, and
      the end rules not even asked -- upstream's shouldShowAllLabels. A
      negative interval builds every label too, but the ends are still
      weighed. }
    ShowAllLabels: Boolean;
    { axisLabel.rotate as written, degrees: the auto interval turns the
      band into the label's frame by it, before a top axis negates it. }
    LabelRotateDeg: Double;
    { the category axis' own band and first category, for the auto
      interval's band width and the stride's alignment from nought }
    OnBand: Boolean;
    OrdinalStart: Integer;
    { axisLabel.hideOverlap }
    HideOverlap: Boolean;
    { FROM THE ESTIMATE, on a value, log or time axis whose grid then shrank:
      the labels that pass did not show. Upstream re-lays those labels out on
      the final rect rather than building them again, and a label it hid then
      is the first to go now. Empty otherwise. }
    LabelSuggestIgnore: TTyBoolArray;

    { `axisLabel.interval` on a category axis, already turned into a stride:
      nought means the author said nothing and the measured rule decides, 1
      means every label, N means every Nth.

      A STRIDE AND NOT THE OPTION'S OWN NUMBER. `interval` counts what it
      SKIPS -- 0 shows everything, 1 shows every other one -- so the option's N
      is a stride of N+1. Read it as `every Nth` and a chart asking for all its
      labels loses half of them. }
    ForcedLabelStep: Integer;

    { The stride the TICK MARKS and the SPLIT LINES walk. Nought means `the
      same one the labels walk`, which is upstream's default and the whole
      point of it: the LABEL interval drives axisTick, splitLine and splitArea
      one way, so that two grids sharing an x axis keep the same grid even when
      only one of them draws the numbers. }
    TickStep: Integer;

    { The two ends. `aelAuto` is upstream's default: an end off the interval
      or a time axis' ragged end is dropped, and an end that crowds its
      neighbour gives way. `aelHide` drops it; `aelShow` keeps it and drops the
      neighbour it crowds. }
    ShowMinLabel: TTyAxisEndLabel;
    ShowMaxLabel: TTyAxisEndLabel;

    { ---- what the outer-bounds shrink needs besides the boxes ---- }

    { WHERE EACH LABEL'S TICK SITS IN THE SCALE'S OWN EXTENT, 0..1 from its
      start: upstream's proportion, `scale.normalize(tick)`. NOT Positions --
      those are band-adjusted and inverted, and the shrink divides by neither.
      Parallel to Labels; empty means no proportion at all. }
    Proportions: TTyDoubleArray;
    { axisLabel.textMargin, LOGICAL px: the padding round each label's box,
      across its own lines (V) and along them (H). Upstream's default is
      [0, 3]; the zero value is none. }
    TextMarginVLogical, TextMarginHLogical: Double;
    { WHAT LEGACY containLabel MEASURES: axisLabel.show on a scale that is not
      blank -- whether or not the axis itself is shown, which ShowLabels
      is not. }
    LegacyLabels: Boolean;

    { ---- the axis name ---- }

    NameLocation: TTyAxisNameLocation;
    { axis.inverse: the extent runs from the far end, so a start name stands
      there and an end name at the origin }
    Inverse: Boolean;
    { nameRotate, turned into radians as upstream turns it (degrees times pi
      over 180); without it a middle name turns with its axis and an end name
      stays level }
    HasNameRotate: Boolean;
    NameRotateRad: Double;
    { nameTextStyle.align / verticalAlign, over the layout's own }
    HasNameAlignH, HasNameAlignV: Boolean;
    NameAlignH: TTyTextAnchorH;
    NameAlignV: TTyTextAnchorV;
    NameMarginKind: TTyNameMarginKind;
    { LOGICAL px, [top, right, bottom, left], nmkTextMargin only }
    NameMargin: array[0..3] of Double;
    NameMinMarginLogical: Double;
    { nameMoveOverlap off. The zero value moves, as upstream's default does. }
    NameNoMove: Boolean;
    { The name's own font. A size of nought falls back to the label font. }
    NameFontName: string;
    NameFontSizeLogical: Integer;
    NameFontWeight: Integer;
    { the frame of the pass being laid out, set by the builder; without it a
      frame is made from the rect with the line on the plot's edge }
    HasNameFrame: Boolean;
    NameFrame: TTyAxisNameFrame;
    { the name as the paint pass draws it: the last pass, on the final rect }
    NamePlacement: TTyAxisNamePlacement;

    { THE FURNITURE AS IT IS DRAWN, on the final rect: the tick marks, the
      split lines, and the edges the split areas run between. Each follows
      the labels unless its own interval says otherwise. }
    TickMarks: TTyAxisMarkArray;
    SplitLineMarks: TTyAxisMarkArray;
    SplitAreaMarks: TTyAxisMarkArray;
  end;
  TTyAxisLayoutSpecArray = array of TTyAxisLayoutSpec;
  PTyAxisLayoutSpec = ^TTyAxisLayoutSpec;

  { One shown label as the name layout meets it: the point it hangs by, its
    box in its own frame -- textMargin included -- the matrix that places
    that box, and the axis-aligned rect round the result. }
  TTyLabelGeom = record
    { which of the spec's labels }
    Index: Integer;
    X, Y: Double;
    LocalRect: TTyXYWH;
    M: TTyMat2D;
    Rect: TTyXYWH;
    AxisAligned: Boolean;
  end;
  TTyLabelGeomArray = array of TTyLabelGeom;

  { Something that may overflow the grid's outer bounds: a label's box or a
    name's, DEVICE px. AlongY says which dimension is its axis' own; along it
    the overflow is divided by Proportion, because a thing that sits that far
    along the axis is brought in by only that much of the shrink.
    Not-a-number is no proportion, and the overflow counts as it is. }
  TTyBoundsItem = record
    R: TTyXYWH;
    AlongY: Boolean;
    Proportion: Double;
  end;
  TTyBoundsItemArray = array of TTyBoundsItem;

  { top, right, bottom, left -- upstream's order for a margin }
  TTyMargin4 = array[0..3] of Double;


{ Logical px -> device px for axis geometry. Exported because the builder
  scales axisLabel.width the same way, and a second copy of this rule is how two
  layers start disagreeing about what a pixel is. }
function AxisScaleF(ALogical: Double; APPI: Integer): Double;

{ Phase 1. How much room this axis needs on its own side, DEVICE px. }
function TyAxisThickness(const ASpec: TTyAxisLayoutSpec;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AContain: TTyOuterBoundsContain): Double;

function TyXYWH(AX, AY, AW, AH: Double): TTyXYWH;
function TyXYWHOfRect(const ARect: TTyRectF): TTyXYWH;
function TyRectOfXYWH(const A: TTyXYWH): TTyRectF;

{ Phase 2, the estimate. Every label this axis shows when laid out on ARaw,
  as the box it would be drawn in: anchored beyond the plot's edge by the
  offset and the label margin, turned, and padded by textMargin -- and with
  its proportion. Nothing for an axis that shows no labels. }
function TyAxisLabelBoundsItems(const ASpec: TTyAxisLayoutSpec;
  const ARaw: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyBoundsItemArray;

{ ---- zrender's matrix arithmetic, operation for operation ---- }
function TyMatIdentity: TTyMat2D;
{ Transformable.getLocalTransform with no scale, skew or origin }
function TyMatLocal(AX, AY, ARotation: Double): TTyMat2D;
function TyMatMul(const A, B: TTyMat2D): TTyMat2D;
{ False, and the identity, for a matrix with no inverse }
function TyMatInvert(const A: TTyMat2D; out AInverse: TTyMat2D): Boolean;
{ BoundingRect.applyTransform: the rect round ARect's four corners }
function TyRectApplyMat(const ARect: TTyXYWH; const M: TTyMat2D): TTyXYWH;
{ isBoundingRectAxisAligned }
function TyMatAxisAligned(const M: TTyMat2D): Boolean;
{ BoundingRect.union }
function TyRectUnion(const A, B: TTyXYWH): TTyXYWH;
{ expandOrShrinkRect(rect, delta, expand, may-be-negative): grow ARect by
  [top, right, bottom, left] }
function TyRectExpand(const ARect: TTyXYWH; ATop, ARight, ABottom,
  ALeft: Double): TTyXYWH;

{ Every label an axis shows when laid out on ARect, as the name layout and
  the shrink meet it. }
function TyAxisLabelGeoms(const ASpec: TTyAxisLayoutSpec;
  const ARect: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyLabelGeomArray;

{ The frame of an axis on ARect when nothing better is known: its line on
  the plot's edge, moved out by the offset. The builder, which knows about
  a line on the other axis' zero, sets its own. }
function TyDefaultNameFrame(const ASpec: TTyAxisLayoutSpec;
  const ARect: TTyRectF; APPI: Integer): TTyAxisNameFrame;

{ upstream's fillMarginOnOneDimension, over every item and the raw rect
  itself: the largest overflow of AOuter on each side, along an item's own
  dimension divided by its proportion (when the overflow is positive and the
  proportion above 1e-4). }
function TyOuterBoundsMargin(const AOuter, ARaw: TTyXYWH;
  const AItems: TTyBoundsItemArray): TTyMargin4;

{ upstream's expandOrShrinkRect, shrinking, negative margins taken as none,
  and no side smaller than AMinW / AMinH -- or than it already was. A rect
  that hits the floor keeps the side that did not ask to move. }
procedure TyShrinkRect(var ARect: TTyXYWH; const AMargin: TTyMargin4;
  AMinW, AMinH: Double);

{ Phase 2, whole: upstream's layOutGridByOuterBounds. ARaw is the grid's
  rect, AOuter the bounds the labels (and, under obcAll, the names) must
  stay inside, AClampW/H the smallest the plot may become. }
function TySolveGridBounds(const ARaw: TTyRectF; const AOuter: TTyXYWH;
  AContain: TTyOuterBoundsContain; AClampW, AClampH: Double;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; const AContainer: TTyXYWH): TTyRectF; overload;
{ The same, saying whether anything overflowed at all -- upstream's
  noPxChange, which is not `the rect came out the same`: a shrink held at
  the clamp still moves the rect. }
function TySolveGridBounds(const ARaw: TTyRectF; const AOuter: TTyXYWH;
  AContain: TTyOuterBoundsContain; AClampW, AClampH: Double;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; const AContainer: TTyXYWH;
  out ANoPxChange: Boolean): TTyRectF; overload;

{ Legacy grid.containLabel: for every axis in turn whose labels are not
  inside, the widest (or tallest) of all its labels -- unrotated, turned by
  |cos| and |sin|, no textMargin, every label up to forty and a sample past
  that -- plus the label margin, taken off its side. Axes on one side stack.
  Names, offsets and axis.show do not enter into it. }
function TyLegacyContainLabel(const ARaw: TTyRectF;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyRectF;

{ Phase 3. Place the labels along the FINAL plot band, thinning to a uniform
  step when they would collide. }
function TyLayoutAxisLabels(const ASpec: TTyAxisLayoutSpec; const APlot: TTyRectF;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): TTyAxisLabelPlacementArray;

{ A CATEGORY AXIS' LABEL INTERVAL on APlot: the author's, or measured as
  upstream's calculateCategoryInterval measures it. +Infinity on an axis of
  no length. }
function TyCategoryLabelInterval(const ASpec: TTyAxisLayoutSpec;
  const APlot: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): Double;

{ The uniform step TyLayoutAxisLabels chose: 1 = every label, 2 = every other.
  Exposed because a caller drawing tick MARKS has to thin them the same way, and
  computing it twice by two routes is how the marks and the labels drift apart. }
function TyAxisLabelStep(const ASpec: TTyAxisLayoutSpec; const APlot: TTyRectF;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): Integer;

implementation

uses tyControls.AdvChart.AxisName, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.AxisLabels;

type
  TTyFixedContainer = class(TInterfacedObject, ITyBoxContainer)
  private
    FRect: TTyRectF;
  public
    constructor Create(const ARect: TTyRectF);
    function ContainerRect: TTyRectF;
  end;

  TTyCoordCellContainer = class(TInterfacedObject, ITyBoxContainer)
  private
    FCoordSys: ITyCoordSys;
    FData: TTyDoubleArray;
  public
    constructor Create(const ACoordSys: ITyCoordSys; const AData: array of Double);
    function ContainerRect: TTyRectF;
  end;

function TyBoxAuto: TTyBoxValue;
begin
  Result.Kind := buAuto;
  Result.Value := 0;
end;

function TyBoxSpec: TTyBoxSpec;
begin
  Result.Left := TyBoxAuto;
  Result.Top := TyBoxAuto;
  Result.Right := TyBoxAuto;
  Result.Bottom := TyBoxAuto;
  Result.Width := TyBoxAuto;
  Result.Height := TyBoxAuto;
end;

function TyBoxPx(AValue: Double): TTyBoxValue;
begin
  Result.Kind := buPx;
  Result.Value := AValue;
end;

function TyBoxPercent(AValue: Double): TTyBoxValue;
begin
  Result.Kind := buPercent;
  Result.Value := AValue;
end;

function TyBoxCentre: TTyBoxValue;
begin
  Result.Kind := buCentre;
  Result.Value := 0;
end;

{ Resolve one value against a container extent. Returns NaN for buAuto (and for
  buCentre, which the caller handles first) so "not specified" stays
  distinguishable from "specified as zero" — the distinction the whole
  precedence table below rests on. }
function ResolveValue(const AV: TTyBoxValue; AExtent: Double): Double;
begin
  case AV.Kind of
    buPx: Result := AV.Value;
    buPercent: Result := AV.Value / 100 * AExtent;
  else
    Result := NaN;
  end;
end;

{ Solve one axis. AStartV/AEndV are the near/far insets, ASizeV the extent.

  AMarginStart/AMarginEnd are kept OUTSIDE the answer on each side. Every
  branch below reduces to the no-margin one when they are zero, which is why
  the margin could be added to this rather than beside it. }
procedure SolveAxis(const AStartV, AEndV, ASizeV: TTyBoxValue;
  AContainerStart, AContainerExtent, AMarginStart, AMarginEnd: Double;
  out AStart, AStop: Double);
var
  s, e, sz: Double;
begin
  s := ResolveValue(AStartV, AContainerExtent);
  e := ResolveValue(AEndV, AContainerExtent);
  sz := ResolveValue(ASizeV, AContainerExtent);

  if AStartV.Kind = buCentre then
  begin
    { CENTRE NEEDS A SIZE TO CENTRE. Without one upstream does not fall back
      to centring -- it falls through to `left = left || 0` and fills, because
      the centred left it computed was NaN and NaN is falsy. So the answer is
      the container INSET BY THE MARGINS, exactly as the no-edges case below.

      It reads like a detail and it is the legend's wrap width: a legend is
      centred by default and its first box solve asks for a size it has not
      measured yet, so this branch is the one that decides how wide a row may
      grow before it wraps. Returning the whole container would let every row
      run a padding wider than upstream's. }
    if IsNan(sz) then
    begin
      AStart := AContainerStart + AMarginStart;
      AStop := AContainerStart + AContainerExtent - AMarginEnd;
      Exit;
    end;
    { NO MARGIN TERM. Upstream writes `extent/2 - size/2 - marginStart` and
      then adds marginStart back on the way out, so the two cancel: a centred
      box is centred on the CONTAINER, not on what is left of it. }
    AStart := AContainerStart + (AContainerExtent - sz) / 2;
    AStop := AStart + sz;
    Exit;
  end;

  if (not IsNan(s)) and (not IsNan(sz)) then          { start + size }
  begin
    AStart := AContainerStart + AMarginStart + s;
    AStop := AStart + sz;
  end
  else if (not IsNan(s)) and (not IsNan(e)) then      { start + end }
  begin
    AStart := AContainerStart + AMarginStart + s;
    AStop := AContainerStart + AContainerExtent - AMarginEnd - e;
  end
  else if (not IsNan(e)) and (not IsNan(sz)) then     { end + size }
  begin
    AStop := AContainerStart + AContainerExtent - AMarginEnd - e;
    AStart := AStop - sz;
  end
  else if not IsNan(s) then                           { start only -> to the far edge }
  begin
    AStart := AContainerStart + AMarginStart + s;
    AStop := AContainerStart + AContainerExtent - AMarginEnd;
  end
  else if not IsNan(e) then                           { end only -> from the near edge }
  begin
    AStart := AContainerStart + AMarginStart;
    AStop := AContainerStart + AContainerExtent - AMarginEnd - e;
  end
  else if not IsNan(sz) then                          { size only -> at the near edge }
  begin
    AStart := AContainerStart + AMarginStart;
    AStop := AStart + sz;
  end
  else                                                { nothing -> fill }
  begin
    AStart := AContainerStart + AMarginStart;
    AStop := AContainerStart + AContainerExtent - AMarginEnd;
  end;

  { Over-constrained: collapse to zero at the near edge rather than invert. An
    inverted rect survives a later Min/Max swap and reappears as a phantom band
    somewhere else on screen, which is far harder to find than an empty one. }
  if AStop < AStart then
    AStop := AStart;
end;

function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer;
  const AMargin: array of Double): TTyRectF;
var
  c: TTyRectF;
  l, r, t, b: Double;
  m: array[0..3] of Double;
  i: Integer;
begin
  if AContainer = nil then
    Exit(TyInvalidRectF);
  c := AContainer.ContainerRect;
  if not TyRectFIsValid(c) then
    Exit(TyInvalidRectF);
  { CSS ORDER, and short forms read the CSS way: one value is every side,
    two are vertical then horizontal, three leave left taking right's value. }
  for i := 0 to 3 do m[i] := 0;
  case Length(AMargin) of
    0: ;
    1: for i := 0 to 3 do m[i] := AMargin[0];
    2: begin
         m[0] := AMargin[0]; m[2] := AMargin[0];
         m[1] := AMargin[1]; m[3] := AMargin[1];
       end;
    3: begin
         m[0] := AMargin[0];
         m[1] := AMargin[1]; m[3] := AMargin[1];
         m[2] := AMargin[2];
       end;
  else
    for i := 0 to 3 do m[i] := AMargin[i];
  end;
  SolveAxis(ASpec.Left, ASpec.Right, ASpec.Width, c.Left, TyRectFWidth(c),
    m[3], m[1], l, r);
  SolveAxis(ASpec.Top, ASpec.Bottom, ASpec.Height, c.Top, TyRectFHeight(c),
    m[0], m[2], t, b);
  Result := TyRectF(l, t, r, b);
end;

function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer): TTyRectF;
begin
  Result := TySolveBox(ASpec, AContainer, []);
end;

{ ============================ containers ============================ }

constructor TTyFixedContainer.Create(const ARect: TTyRectF);
begin
  inherited Create;
  FRect := ARect;
end;

function TTyFixedContainer.ContainerRect: TTyRectF;
begin
  Result := FRect;
end;

constructor TTyCoordCellContainer.Create(const ACoordSys: ITyCoordSys;
  const AData: array of Double);
var i: Integer;
begin
  inherited Create;
  FCoordSys := ACoordSys;
  SetLength(FData, Length(AData));
  for i := 0 to High(AData) do
    FData[i] := AData[i];
end;

function TTyCoordCellContainer.ContainerRect: TTyRectF;
var l: TTyCoordLayout;
begin
  if FCoordSys = nil then
    Exit(TyInvalidRectF);
  l := FCoordSys.DataToLayout(FData);
  { ContentRect, not Rect — a nested thing must not paint over the host's
    divider. Same choice HeatmapView.ts:279 makes. }
  Result := l.ContentRect;
end;

function TyBoxResolve(const AValue: TTyBoxValue; ABase: Double): Double;
begin
  case AValue.Kind of
    buPx: Result := AValue.Value;
    buPercent: Result := AValue.Value / 100 * ABase;
    buCentre: Result := ABase / 2;
  else
    Result := 0;
  end;
end;

{ THE LEADING NUMBER OF A STRING, the way JavaScript's parseFloat reads one:
  as much of the front as looks like a number, and never mind the rest.

  TryStrToFloat IS NOT THAT. It answers yes or no about the WHOLE string, so
  every box option written the way a stylesheet writes one -- `20px`, `8pt`,
  `10 ` with a stray space -- fell back to its default instead of to twenty,
  eight and ten. Upstream reads all three, because parsePositionSizeOption
  ends in parseFloat and parseFloat stops at the first character it cannot
  use.

  Deliberately NOT a general number reader: no exponent-only forms, no
  hexadecimal, no Infinity. parseFloat takes those too, and a box value that
  is 1e309 is a coordinate nobody can draw -- the shapes of number an author
  writes in a layout are the ones read here. }
function TyLeadingNumber(const AText: string; out AValue: Double): Boolean;
var
  i, n: Integer;
  seenDigit, seenDot: Boolean;
  fs: TFormatSettings;
begin
  Result := False;
  AValue := 0;
  i := 1;
  n := Length(AText);
  while (i <= n) and (AText[i] = ' ') do Inc(i);
  if (i <= n) and ((AText[i] = '+') or (AText[i] = '-')) then Inc(i);
  seenDigit := False;
  seenDot := False;
  while i <= n do
  begin
    if (AText[i] >= '0') and (AText[i] <= '9') then
    begin
      seenDigit := True;
      Inc(i);
    end
    else if (AText[i] = '.') and not seenDot then
    begin
      seenDot := True;
      Inc(i);
    end
    else
      Break;
  end;
  { NOT A NUMBER AT ALL. A MUTANT OF THIS LINE SURVIVES and is recorded rather
    than chased: every prefix that reaches here without a digit -- '', '+',
    '-', '.', '--5' -- is one TryStrToFloat refuses on its own two lines down.
    The check says the rule where the rule belongs; it is not, today, the thing
    enforcing it. }
  if not seenDigit then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := TryStrToFloat(Copy(AText, 1, i - 1), AValue, fs);
end;

function TyBoxStrOf(const AText: string; const ADefault: TTyBoxValue): TTyBoxValue;
var
  s: string;
  v: Double;
begin
  Result := ADefault;
  s := LowerCase(Trim(AText));
  if s = '' then Exit;
  { The presets parsePositionOption accepts. BOTH SPELLINGS of the middle one:
    one of the four readers this replaced took `centre` and the others did not,
    and nothing recorded which was meant. }
  if (s = 'center') or (s = 'centre') or (s = 'middle') then
    Exit(TyBoxPercent(50));
  if (s = 'left') or (s = 'top') then Exit(TyBoxPercent(0));
  if (s = 'right') or (s = 'bottom') then Exit(TyBoxPercent(100));
  { THE PERCENT SIGN IS TESTED ON THE WHOLE STRING, not on what the number
    reader stopped at: `/%$/` asks whether the value ENDS in one, so `50%x` is
    fifty PIXELS and not fifty per cent. }
  if s[Length(s)] = '%' then
  begin
    if TyLeadingNumber(Copy(s, 1, Length(s) - 1), v) then
      Result := TyBoxPercent(v);
    Exit;
  end;
  if TyLeadingNumber(s, v) then Result := TyBoxPx(v);
end;

function TyBoxDataOf(AData: TJSONData; const ADefault: TTyBoxValue): TTyBoxValue;
begin
  Result := ADefault;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  if AData.JSONType = jtNumber then Exit(TyBoxPx(AData.AsFloat));
  if AData.JSONType <> jtString then Exit;
  Result := TyBoxStrOf(AData.AsString, ADefault);
end;

function TyBoxValueOf(ANode: TJSONObject; const AKey: string;
  const ADefault: TTyBoxValue): TTyBoxValue;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  Result := TyBoxDataOf(ANode.Find(AKey), ADefault);
end;

procedure TySolveCircle(const ACentreX, ACentreY: TTyBoxValue;
  const AViewport: TTyRectF; out ACX, ACY, ARadiusBase: Double);
var w, h: Double;
begin
  w := AViewport.Right - AViewport.Left;
  h := AViewport.Bottom - AViewport.Top;
  ACX := AViewport.Left + TyBoxResolve(ACentreX, w);
  ACY := AViewport.Top + TyBoxResolve(ACentreY, h);
  ARadiusBase := Min(w, h) / 2;
end;

function TyLinearMap(AValue, ADomainLo, ADomainHi, ARangeLo, ARangeHi: Double;
  AClamp: Boolean): Double;
var
  subDomain, subRange: Double;
begin
  subDomain := ADomainHi - ADomainLo;
  subRange := ARangeHi - ARangeLo;
  if subDomain = 0 then
  begin
    if subRange = 0 then Exit(ARangeLo);
    Exit((ARangeLo + ARangeHi) / 2);
  end;
  if IsNan(subDomain) or IsNan(AValue) then Exit(ARangeLo);
  if AClamp then
  begin
    if subDomain > 0 then
    begin
      if AValue <= ADomainLo then Exit(ARangeLo);
      if AValue >= ADomainHi then Exit(ARangeHi);
    end
    else
    begin
      if AValue >= ADomainLo then Exit(ARangeLo);
      if AValue <= ADomainHi then Exit(ARangeHi);
    end;
  end;
  Result := (AValue - ADomainLo) / subDomain * subRange + ARangeLo;
end;

function TyFixedContainer(const ARect: TTyRectF): ITyBoxContainer;
begin
  Result := TTyFixedContainer.Create(ARect);
end;

function TyCoordCellContainer(const ACoordSys: ITyCoordSys;
  const AData: array of Double): ITyBoxContainer;
begin
  Result := TTyCoordCellContainer.Create(ACoordSys, AData);
end;


{ ==================== TWO-PHASE AXIS BUILD ==================== }

{ Local, because this unit deliberately does not depend on the painter and so
  cannot borrow its ScaleF. Unrounded for the same reason it is there: a 1 px
  tick at 150 % is 1.5 device px. }
function AxisScaleF(ALogical: Double; APPI: Integer): Double;
begin
  if APPI <= 0 then
    Exit(ALogical);
  Result := ALogical * APPI / 96;
end;

function AxisIsHorizontal(ASide: TTyAxisSide): Boolean;
begin
  Result := ASide in [asTop, asBottom];
end;

{ The bounding box of a w x h box turned by AAngleRad. Both axes at once because
  every caller wants both and computing them apart invites one being forgotten. }
procedure RotatedExtent(AW, AH, AAngleRad: Double; out ARW, ARH: Double);
var
  c, s: Double;
begin
  c := Abs(TyJsCos(AAngleRad));
  s := Abs(TyJsSin(AAngleRad));
  ARW := AW * c + AH * s;
  ARH := AW * s + AH * c;
end;

{ Largest label extent PERPENDICULAR to the axis, plus the largest ALONG it.
  One walk, because the thickness pass wants the first and the thinning pass
  wants the second, and measuring twice is measurably slower on a chart with
  hundreds of ticks. }
{ The weight label AIndex is drawn in. }
function WeightAt(const ASpec: TTyAxisLayoutSpec; AIndex: Integer): Integer;
begin
  Result := ASpec.FontWeight;
  if (ASpec.EmphasisFontWeight > 0) and (AIndex >= 0)
    and (AIndex <= High(ASpec.LabelEmphasis)) and ASpec.LabelEmphasis[AIndex]
    then Result := ASpec.EmphasisFontWeight;
end;

{ ONE LABEL'S BOX, as zrender holds it: the text's box hung by its anchor,
  with axisLabel.textMargin round it (AMargin) and without (ABare), placed by
  the label's point and turn. The end rules weigh the bare one unless the
  author asked for overlaps to be resolved. }
procedure LabelBoxes(const ASpec: TTyAxisLayoutSpec;
  const APlace: TTyAxisLabelPlacement; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; out AMargin, ABare: TTyLabelBox);
var w, h, x0, y0, padH, padV: Double;
begin
  AMeasurer.MeasureLine(APlace.Text, ASpec.FontName, ASpec.FontSizeLogical,
    WeightAt(ASpec, APlace.Index), w, h);
  { zrender's adjustTextX / adjustTextY }
  x0 := 0;
  case APlace.AnchorH of
    tahRight: x0 := x0 - w;
    tahCentre: x0 := x0 - w / 2;
  end;
  y0 := 0;
  case APlace.AnchorV of
    tavBottom: y0 := y0 - h;
    tavMiddle: y0 := y0 - h / 2;
  end;
  padH := AxisScaleF(ASpec.TextMarginHLogical, APPI);
  padV := AxisScaleF(ASpec.TextMarginVLogical, APPI);
  ABare.LocalRect := TyXYWH(x0, y0, w, h);
  AMargin.LocalRect := TyRectExpand(ABare.LocalRect, padV, padH, padV, padH);
  ABare.M := TyMatLocal(APlace.X, APlace.Y, ASpec.RotationRad);
  AMargin.M := ABare.M;
  ABare.Rect := TyRectApplyMat(ABare.LocalRect, ABare.M);
  AMargin.Rect := TyRectApplyMat(AMargin.LocalRect, AMargin.M);
  ABare.AxisAligned := TyMatAxisAligned(ABare.M);
  AMargin.AxisAligned := ABare.AxisAligned;
end;

{ The first line of a label: the auto interval measures one line's height. }
function FirstLine(const AText: string): string;
var p: Integer;
begin
  p := Pos(#10, AText);
  if p > 0 then Result := Copy(AText, 1, p - 1) else Result := AText;
end;

{ A CATEGORY AXIS' INTERVAL on APlot: the author's, or measured as upstream
  measures it -- every label up to forty, then every n/40-th, each in the
  label font, over the band width turned into the label's frame. }
function CategoryIntervalOn(const ASpec: TTyAxisLayoutSpec;
  const APlot: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): Double; forward;

function TyCategoryLabelInterval(const ASpec: TTyAxisLayoutSpec;
  const APlot: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): Double;
begin
  Result := CategoryIntervalOn(ASpec, APlot, AMeasurer, APPI);
end;

function CategoryIntervalOn(const ASpec: TTyAxisLayoutSpec;
  const APlot: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): Double;
var
  n, s, i, k: Integer;
  len, unitSpan, axisRot, w, h, lw: Double;
  ws, hs: array of Double;
begin
  if ASpec.ForcedLabelStep > 0 then Exit(ASpec.ForcedLabelStep - 1);
  Result := 0;
  n := Length(ASpec.Labels);
  if (n - 1 < 1) or (AMeasurer = nil) then Exit;
  s := TyCategorySampleStep(n);
  if AxisIsHorizontal(ASpec.Side) then
  begin
    len := TyRectFWidth(APlot);
    axisRot := 0;
  end
  else
  begin
    len := TyRectFHeight(APlot);
    axisRot := 90;
  end;
  unitSpan := TyCategoryUnitSpan(len, n, ASpec.OnBand, ASpec.Inverse);
  SetLength(ws, (n - 1) div s + 1);
  SetLength(hs, Length(ws));
  k := 0;
  i := 0;
  while i <= n - 1 do
  begin
    { the widest line, and one line's height }
    AMeasurer.MeasureLine(ASpec.Labels[i], ASpec.FontName,
      ASpec.FontSizeLogical, ASpec.FontWeight, w, h);
    AMeasurer.MeasureLine(FirstLine(ASpec.Labels[i]), ASpec.FontName,
      ASpec.FontSizeLogical, ASpec.FontWeight, lw, h);
    ws[k] := w;
    hs[k] := h;
    Inc(k);
    Inc(i, s);
  end;
  SetLength(ws, k);
  SetLength(hs, k);
  Result := TyCategoryAutoInterval(ws, hs, unitSpan, axisRot,
    ASpec.LabelRotateDeg, AxisScaleF(7, APPI));
end;

procedure MeasureLabels(const ASpec: TTyAxisLayoutSpec;
  const AMeasurer: ITyTextMeasurer; out AAcross, AAlong: Double;
  out AAlongEach: TTyDoubleArray);
var
  i: Integer;
  w, h, rw, rh, along, across: Double;
  horiz: Boolean;
begin
  AAcross := 0;
  AAlong := 0;
  AAlongEach := nil;
  if (AMeasurer = nil) or (not ASpec.ShowLabels) then Exit;
  horiz := AxisIsHorizontal(ASpec.Side);
  SetLength(AAlongEach, Length(ASpec.Labels));
  for i := 0 to High(ASpec.Labels) do
  begin
    { MEASURED IN THE WEIGHT IT WILL BE DRAWN IN. Bold is wider, and a label
      measured light and drawn bold is how an axis comes to overlap the one
      thing the measuring was for. }
    AMeasurer.MeasureLine(ASpec.Labels[i], ASpec.FontName,
                          ASpec.FontSizeLogical, WeightAt(ASpec, i), w, h);
    RotatedExtent(w, h, ASpec.RotationRad, rw, rh);
    if horiz then
    begin
      along := rw;
      across := rh;
    end
    else
    begin
      along := rh;
      across := rw;
    end;
    AAlongEach[i] := along;
    if across > AAcross then AAcross := across;
    if along > AAlong then AAlong := along;
  end;
end;

function TyAxisThickness(const ASpec: TTyAxisLayoutSpec;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AContain: TTyOuterBoundsContain): Double;
var
  across, along, nw, nh, nrw, nrh: Double;
  each: TTyDoubleArray;
begin
  { NOTHING IS CHARGED FOR FURNITURE THAT IS NOT THERE. A hidden tick, or one
    pointing into the plot, lies entirely inside the band and reserves no
    room outside it; an inside label likewise. Charging for them anyway is
    how an axis that draws nothing still pushes the plot in five pixels. }
  { THE OFFSET IS PART OF THE BAND. The axis' own furniture measures the
    same whatever the offset; what changes is where it starts, so the band
    it needs is the offset plus the furniture. A negative offset would eat
    into the plot rather than give room back, so it is floored. }
  Result := Max(Double(0), AxisScaleF(ASpec.OffsetLogical, APPI));
  if ASpec.ShowTicks and (not ASpec.TickInside) then
    { MAX, because a NEGATIVE length is upstream's other way of pointing the
      mark into the plot. Inward furniture reserves nothing outside, and
      subtracting from the gutter would let a long inward tick pull the plot
      out past its own container. }
    Result := Result + Max(Double(0), AxisScaleF(ASpec.TickLengthLogical, APPI));
  MeasureLabels(ASpec, AMeasurer, across, along, each);
  if (across > 0) and (not ASpec.LabelInside) then
    Result := Result + AxisScaleF(ASpec.LabelMarginLogical, APPI) + across;
  { The name counts only when the caller asked for outerBoundsContain:'all'.
    Under 'axisLabel' an axis name is allowed to sit outside the outer bound,
    which is what ECharts does and what keeps a long name from eating the plot. }
  if (AContain = obcAll) and (ASpec.Name <> '') and (AMeasurer <> nil) then
  begin
    AMeasurer.MeasureLine(ASpec.Name, ASpec.FontName,
                          ASpec.FontSizeLogical, ASpec.FontWeight, nw, nh);
    { An axis name reads along its own axis, so on a vertical axis it is the
      name's HEIGHT that eats width once turned. Measured unrotated and turned
      here rather than asking the caller to pre-rotate it. }
    if AxisIsHorizontal(ASpec.Side) then
      RotatedExtent(nw, nh, 0, nrw, nrh)
    else
      RotatedExtent(nw, nh, Pi / 2, nrw, nrh);
    Result := Result + AxisScaleF(ASpec.NameGapLogical, APPI)
              + IfThen(AxisIsHorizontal(ASpec.Side), nrh, nrw);
  end;
end;

function TyXYWH(AX, AY, AW, AH: Double): TTyXYWH;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

function TyXYWHOfRect(const ARect: TTyRectF): TTyXYWH;
begin
  Result := TyXYWH(ARect.Left, ARect.Top, ARect.Right - ARect.Left,
    ARect.Bottom - ARect.Top);
end;

function TyRectOfXYWH(const A: TTyXYWH): TTyRectF;
begin
  Result := TyRectF(A.X, A.Y, A.X + A.W, A.Y + A.H);
end;

{ ==================== zrender's matrices ==================== }

function TyMatIdentity: TTyMat2D;
begin
  Result[0] := 1; Result[1] := 0; Result[2] := 0;
  Result[3] := 1; Result[4] := 0; Result[5] := 0;
end;

{ matrix.rotate(out, a, rad), pivot at nought, operation for operation }
function MatRotate(const A: TTyMat2D; ARad: Double): TTyMat2D;
var aa, ac, atx, ab, ad, aty, st, ct: Double;
begin
  aa := A[0]; ac := A[2]; atx := A[4];
  ab := A[1]; ad := A[3]; aty := A[5];
  st := TyJsSin(ARad);
  ct := TyJsCos(ARad);
  Result[0] := aa * ct + ab * st;
  Result[1] := -aa * st + ab * ct;
  Result[2] := ac * ct + ad * st;
  Result[3] := -ac * st + ct * ad;
  Result[4] := ct * (atx - 0) + st * (aty - 0) + 0;
  Result[5] := ct * (aty - 0) - st * (atx - 0) + 0;
end;

function TyMatLocal(AX, AY, ARotation: Double): TTyMat2D;
begin
  Result := TyMatIdentity;
  if ARotation <> 0 then Result := MatRotate(Result, ARotation);
  Result[4] := Result[4] + (0 + AX);
  Result[5] := Result[5] + (0 + AY);
end;

function TyMatMul(const A, B: TTyMat2D): TTyMat2D;
begin
  Result[0] := A[0] * B[0] + A[2] * B[1];
  Result[1] := A[1] * B[0] + A[3] * B[1];
  Result[2] := A[0] * B[2] + A[2] * B[3];
  Result[3] := A[1] * B[2] + A[3] * B[3];
  Result[4] := A[0] * B[4] + A[2] * B[5] + A[4];
  Result[5] := A[1] * B[4] + A[3] * B[5] + A[5];
end;

function TyMatInvert(const A: TTyMat2D; out AInverse: TTyMat2D): Boolean;
var aa, ac, atx, ab, ad, aty, det: Double;
begin
  AInverse := TyMatIdentity;
  aa := A[0]; ac := A[2]; atx := A[4];
  ab := A[1]; ad := A[3]; aty := A[5];
  det := aa * ad - ab * ac;
  if (det = 0) or IsNan(det) then Exit(False);
  det := 1.0 / det;
  AInverse[0] := ad * det;
  AInverse[1] := -ab * det;
  AInverse[2] := -ac * det;
  AInverse[3] := aa * det;
  AInverse[4] := (ac * aty - ad * atx) * det;
  AInverse[5] := (ab * atx - aa * aty) * det;
  Result := True;
end;

function TyRectApplyMat(const ARect: TTyXYWH; const M: TTyMat2D): TTyXYWH;
var
  sx, sy: Double;
  px: array[0..3] of Double;
  py: array[0..3] of Double;
  cx, cy, maxX, maxY: Double;
  k: Integer;
begin
  { THE FAST PATH when nothing turns, as zrender takes it }
  if (M[1] < 1e-5) and (M[1] > -1e-5) and (M[2] < 1e-5) and (M[2] > -1e-5) then
  begin
    sx := M[0];
    sy := M[3];
    Result.X := ARect.X * sx + M[4];
    Result.Y := ARect.Y * sy + M[5];
    Result.W := ARect.W * sx;
    Result.H := ARect.H * sy;
    if Result.W < 0 then
    begin
      Result.X := Result.X + Result.W;
      Result.W := -Result.W;
    end;
    if Result.H < 0 then
    begin
      Result.Y := Result.Y + Result.H;
      Result.H := -Result.H;
    end;
    Exit;
  end;
  { lt, rt, rb, lb }
  px[0] := ARect.X;            py[0] := ARect.Y;
  px[1] := ARect.X + ARect.W;  py[1] := ARect.Y;
  px[2] := ARect.X + ARect.W;  py[2] := ARect.Y + ARect.H;
  px[3] := ARect.X;            py[3] := ARect.Y + ARect.H;
  Result.X := Infinity;
  Result.Y := Infinity;
  maxX := NegInfinity;
  maxY := NegInfinity;
  for k := 0 to 3 do
  begin
    cx := M[0] * px[k] + M[2] * py[k] + M[4];
    cy := M[1] * px[k] + M[3] * py[k] + M[5];
    if cx < Result.X then Result.X := cx;
    if cy < Result.Y then Result.Y := cy;
    if cx > maxX then maxX := cx;
    if cy > maxY then maxY := cy;
  end;
  Result.W := maxX - Result.X;
  Result.H := maxY - Result.Y;
end;

function TyMatAxisAligned(const M: TTyMat2D): Boolean;
begin
  Result := ((Abs(M[1]) < 1e-5) and (Abs(M[2]) < 1e-5))
    or ((Abs(M[0]) < 1e-5) and (Abs(M[3]) < 1e-5));
end;

function TyRectUnion(const A, B: TTyXYWH): TTyXYWH;
begin
  { A is `this`, B `other` }
  Result.X := Min(B.X, A.X);
  Result.Y := Min(B.Y, A.Y);
  if (not IsNan(A.X)) and (not IsInfinite(A.X)) and (not IsNan(A.W))
    and (not IsInfinite(A.W)) then
    Result.W := Max(B.X + B.W, A.X + A.W) - Result.X
  else
    Result.W := B.W;
  if (not IsNan(A.Y)) and (not IsInfinite(A.Y)) and (not IsNan(A.H))
    and (not IsInfinite(A.H)) then
    Result.H := Max(B.Y + B.H, A.Y + A.H) - Result.Y
  else
    Result.H := B.H;
end;

procedure ShrinkOneDimension(var APos, ASize: Double; ALo, AHi, AMin: Double); forward;

function TyRectExpand(const ARect: TTyXYWH; ATop, ARight, ABottom,
  ALeft: Double): TTyXYWH;
begin
  Result := ARect;
  ShrinkOneDimension(Result.X, Result.W, ALeft, ARight, 0);
  ShrinkOneDimension(Result.Y, Result.H, ATop, ABottom, 0);
end;

{ ==================== the labels as geometry ==================== }

function TyAxisLabelGeoms(const ASpec: TTyAxisLayoutSpec;
  const ARect: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyLabelGeomArray;
var
  places: TTyAxisLabelPlacementArray;
  i, n: Integer;
  box, bare: TTyLabelBox;
begin
  Result := nil;
  if (AMeasurer = nil) or (not ASpec.ShowLabels) then Exit;
  { THE LABELS THIS RECT SHOWS: thinned on it, the hidden ends left out --
    upstream measures the survivors and nothing else }
  places := TyLayoutAxisLabels(ASpec, ARect, AMeasurer, APPI);
  SetLength(Result, Length(places));
  n := 0;
  for i := 0 to High(places) do
  begin
    if (not places[i].Shown) or (places[i].Text = '') then Continue;
    LabelBoxes(ASpec, places[i], AMeasurer, APPI, box, bare);
    Result[n].Index := i;
    Result[n].X := places[i].X;
    Result[n].Y := places[i].Y;
    Result[n].LocalRect := box.LocalRect;
    Result[n].M := box.M;
    Result[n].Rect := box.Rect;
    Result[n].AxisAligned := box.AxisAligned;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyAxisLabelBoundsItems(const ASpec: TTyAxisLayoutSpec;
  const ARaw: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyBoundsItemArray;
var
  geoms: TTyLabelGeomArray;
  i, k: Integer;
  horiz: Boolean;
begin
  Result := nil;
  geoms := TyAxisLabelGeoms(ASpec, ARaw, AMeasurer, APPI);
  horiz := AxisIsHorizontal(ASpec.Side);
  SetLength(Result, Length(geoms));
  for k := 0 to High(geoms) do
  begin
    i := geoms[k].Index;
    Result[k].R := geoms[k].Rect;
    Result[k].AlongY := not horiz;
    { a y axis measures its proportion from the TOP, where the overflow the
      division applies to is the one below }
    Result[k].Proportion := NaN;
    if i <= High(ASpec.Proportions) then
    begin
      if horiz then Result[k].Proportion := ASpec.Proportions[i]
      else Result[k].Proportion := 1 - ASpec.Proportions[i];
    end;
  end;
end;

function TyDefaultNameFrame(const ASpec: TTyAxisLayoutSpec;
  const ARect: TTyRectF; APPI: Integer): TTyAxisNameFrame;
var off, len: Double;
begin
  Result := Default(TTyAxisNameFrame);
  off := AxisScaleF(ASpec.OffsetLogical, APPI);
  if AxisIsHorizontal(ASpec.Side) then
  begin
    Result.PosX := ARect.Left;
    if ASpec.Side = asTop then Result.PosY := ARect.Top - off
    else Result.PosY := ARect.Bottom + off;
    Result.Rotation := 0;
    len := ARect.Right - ARect.Left;
  end
  else
  begin
    if ASpec.Side = asLeft then Result.PosX := ARect.Left - off
    else Result.PosX := ARect.Right + off;
    Result.PosY := ARect.Bottom;
    Result.Rotation := Pi / 2;
    len := ARect.Bottom - ARect.Top;
  end;
  { Grid's updateAxisTransform: [0, len], turned round for an inverse axis }
  if ASpec.Inverse then
  begin
    Result.Ext0 := len;
    Result.Ext1 := 0;
  end
  else
  begin
    Result.Ext0 := 0;
    Result.Ext1 := len;
  end;
  Result.Inverse := ASpec.Inverse;
  if ASpec.Side in [asTop, asLeft] then Result.NameDirection := -1
  else Result.NameDirection := 1;
end;

function TyOuterBoundsMargin(const AOuter, ARaw: TTyXYWH;
  const AItems: TTyBoundsItemArray): TTyMargin4;
var
  i: Integer;
  m: TTyMargin4;

  function Apply(AOverflow, AProportion: Double): Double;
  begin
    { a proportion near nought gives up the division rather than blow the
      overflow up past any meaning }
    Result := AOverflow;
    if (AOverflow > 0) and (not IsNan(AProportion)) and (AProportion > 1e-4) then
      Result := AOverflow / AProportion;
  end;

  procedure Fill(const AR: TTyXYWH; AOnY: Boolean; AProportion: Double);
  var o1, o2: Double;
  begin
    if AOnY then
    begin
      o1 := AOuter.Y - AR.Y;
      o2 := (AR.H + AR.Y) - (AOuter.H + AOuter.Y);
      o1 := Apply(o1, 1 - AProportion);
      o2 := Apply(o2, AProportion);
      if o1 > m[0] then m[0] := o1;
      if o2 > m[2] then m[2] := o2;
    end
    else
    begin
      o1 := AOuter.X - AR.X;
      o2 := (AR.W + AR.X) - (AOuter.W + AOuter.X);
      o1 := Apply(o1, 1 - AProportion);
      o2 := Apply(o2, AProportion);
      if o1 > m[3] then m[3] := o1;
      if o2 > m[1] then m[1] := o2;
    end;
  end;

begin
  m[0] := 0; m[1] := 0; m[2] := 0; m[3] := 0;
  for i := 0 to High(AItems) do
  begin
    Fill(AItems[i].R, AItems[i].AlongY, AItems[i].Proportion);
    Fill(AItems[i].R, not AItems[i].AlongY, NaN);
  end;
  { AND THE RECT ITSELF: a grid written wider than its bounds overflows them
    with no label at all }
  Fill(ARaw, False, NaN);
  Fill(ARaw, True, NaN);
  Result := m;
end;

procedure ShrinkOneDimension(var APos, ASize: Double; ALo, AHi, AMin: Double);
var sum, old, least: Double;
begin
  sum := AHi + ALo;
  old := ASize;
  ASize := ASize + sum;
  least := Max(Double(0), Min(AMin, old));
  if ASize < least then
  begin
    ASize := least;
    { THE SIDE THAT DID NOT ASK TO MOVE STAYS WHERE IT WAS }
    if ALo >= 0 then APos := APos + (-ALo)
    else if AHi >= 0 then APos := APos + (old + AHi)
    else if Abs(sum) > 1e-8 then APos := APos + ((old - least) * ALo / sum);
  end
  else
    APos := APos - ALo;
end;

procedure TyShrinkRect(var ARect: TTyXYWH; const AMargin: TTyMargin4;
  AMinW, AMinH: Double);
var d: TTyMargin4;
  i: Integer;
begin
  { negative margins are none; then, to SHRINK, every one is negated }
  for i := 0 to 3 do
    d[i] := -Max(Double(0), AMargin[i]);
  if IsNan(AMinW) then AMinW := 0;
  if IsNan(AMinH) then AMinH := 0;
  ShrinkOneDimension(ARect.X, ARect.W, d[3], d[1], AMinW);
  ShrinkOneDimension(ARect.Y, ARect.H, d[0], d[2], AMinH);
end;

function TySolveGridBounds(const ARaw: TTyRectF; const AOuter: TTyXYWH;
  AContain: TTyOuterBoundsContain; AClampW, AClampH: Double;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; const AContainer: TTyXYWH): TTyRectF;
var noPx: Boolean;
begin
  Result := TySolveGridBounds(ARaw, AOuter, AContain, AClampW, AClampH, AAxes,
    AMeasurer, APPI, AContainer, noPx);
end;

function TySolveGridBounds(const ARaw: TTyRectF; const AOuter: TTyXYWH;
  AContain: TTyOuterBoundsContain; AClampW, AClampH: Double;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; const AContainer: TTyXYWH;
  out ANoPxChange: Boolean): TTyRectF;
var
  items, one: TTyBoundsItemArray;
  names: TTyAxisNamePlacementArray;
  i, k, n: Integer;
  r: TTyXYWH;
  margin: TTyMargin4;
begin
  items := nil;
  n := 0;
  { EVERY AXIS' LABELS FIRST: an end name is moved clear of the other axis'
    labels, so they must all be laid out before any name is }
  for i := 0 to High(AAxes) do
  begin
    one := TyAxisLabelBoundsItems(AAxes[i], ARaw, AMeasurer, APPI);
    SetLength(items, n + Length(one));
    for k := 0 to High(one) do
      items[n + k] := one[k];
    Inc(n, Length(one));
  end;
  { THEN THE NAMES, under 'all' only -- estimated on the raw rect, at its
    margin level, after their moves -- each counted along its own axis by
    its proportion (none for an end name) and across it as it is }
  if AContain = obcAll then
  begin
    names := TyLayoutGridNames(AAxes, ARaw, AContainer.W, AContainer.H,
      AMeasurer, APPI);
    for i := 0 to High(names) do
      if names[i].Shown then
      begin
        SetLength(items, n + 1);
        items[n].R := names[i].Rect;
        items[n].AlongY := not AxisIsHorizontal(AAxes[i].Side);
        items[n].Proportion := names[i].Proportion;
        Inc(n);
      end;
  end;
  SetLength(items, n);
  r := TyXYWHOfRect(ARaw);
  margin := TyOuterBoundsMargin(AOuter, TyXYWHOfRect(ARaw), items);
  ANoPxChange := True;
  for k := 0 to 3 do
    if margin[k] > 0 then ANoPxChange := False;
  TyShrinkRect(r, margin, AClampW, AClampH);
  Result := TyRectOfXYWH(r);
end;

function TyLegacyContainLabel(const ARaw: TTyRectF;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyRectF;
var
  i, k, n, step: Integer;
  w, h, uw, uh, c, s, rw, rh, gap: Double;
  r: TTyXYWH;
  any: Boolean;
begin
  r := TyXYWHOfRect(ARaw);
  if AMeasurer <> nil then
    for i := 0 to High(AAxes) do
    begin
      if AAxes[i].LabelInside or (not AAxes[i].LegacyLabels) then Continue;
      n := Length(AAxes[i].Labels);
      if n = 0 then Continue;
      { EVERY LABEL, NOT THE SHOWN ONES -- and past forty only a sample, which
        is upstream's own economy and so its answer }
      step := 1;
      if n > 40 then step := Ceil(n / 40);
      c := Abs(TyJsCos(AAxes[i].RotationRad));
      uw := 0;
      uh := 0;
      any := False;
      k := 0;
      while k < n do
      begin
        AMeasurer.MeasureLine(AAxes[i].Labels[k], AAxes[i].FontName,
          AAxes[i].FontSizeLogical, AAxes[i].FontWeight, w, h);
        s := TyJsSin(AAxes[i].RotationRad);
        rw := w * c + Abs(h * s);
        rh := w * Abs(s) + Abs(h * TyJsCos(AAxes[i].RotationRad));
        if (not any) or (rw > uw) then uw := rw;
        if (not any) or (rh > uh) then uh := rh;
        any := True;
        Inc(k, step);
      end;
      gap := AxisScaleF(AAxes[i].LabelMarginLogical, APPI);
      if AxisIsHorizontal(AAxes[i].Side) then
      begin
        r.H := r.H - (uh + gap);
        if AAxes[i].Side = asTop then r.Y := r.Y + (uh + gap);
      end
      else
      begin
        r.W := r.W - (uw + gap);
        if AAxes[i].Side = asLeft then r.X := r.X + (uw + gap);
      end;
    end;
  Result := TyRectOfXYWH(r);
end;

function TyAxisLabelStep(const ASpec: TTyAxisLayoutSpec; const APlot: TTyRectF;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): Integer;
var
  iv: Double;
  n: Integer;
begin
  { ONLY A CATEGORY AXIS HAS A STRIDE. A value, log or time axis builds a
    label per tick and never drops one for its index.
    [Revised in batch 39: every axis but a time one was thinned to the
    smallest uniform stride that left 4 px between labels.] }
  Result := 1;
  if ASpec.LabelKind <> lakCategory then Exit;
  { AN AUTHOR WHO NAMED A STRIDE GETS IT, measured or not. `interval: 0` on a
    crowded axis means `draw them all and let them collide`, which is a thing
    people write on purpose. And it stays ahead of the measuring because an
    axis of five thousand categories that was told what to do should not
    measure them to be told again. }
  if ASpec.ForcedLabelStep > 0 then Exit(ASpec.ForcedLabelStep);
  { MEASURED EVEN WITH THE LABELS OFF: the ticks and split lines follow this
    stride whether or not the labels are drawn }
  iv := CategoryIntervalOn(ASpec, APlot, AMeasurer, APPI);
  n := Length(ASpec.Labels);
  { an infinite interval, or one past the last label, keeps the first alone }
  if IsInfinite(iv) or (iv + 1 > n) then Result := Max(1, n)
  else Result := Trunc(iv) + 1;
end;

{ Into [0, 2*PI), which is upstream's remRadian and NOT the [-PI, PI) a
  reader expects. The interval matters: a quarter turn CLOCKWISE comes back
  as three quarters anticlockwise, which is on the far side of PI and so
  lands in the other arm of the alignment rule below. }
function RemRadian(AValue: Double): Double;
const cTwoPi = 2 * Pi;
begin
  Result := AValue - Floor(AValue / cTwoPi) * cTwoPi;
end;

{ WHICH POINT OF THE TEXT SITS ON THE ANCHOR -- upstream's
  AxisBuilder.innerTextLayout, whole.

  ONE RULE FOR FOUR SIDES AND EVERY ANGLE. Fed a rotation of nought it
  reproduces, exactly, the per-side table it replaces: bottom gets
  centre/top, top gets centre/bottom, left gets right/middle, right gets
  left/middle. So this is not a branch beside the table, it IS the table --
  and the turned case stops being a special case of anything.

  The table ignored the rotation, and that was a visible bug rather than an
  omission: anchored centre/top and then turned 45 degrees, a label
  STRADDLES its anchor, and half the string swings UP across the axis line
  into the plot, where the series paints over it. Eight categories came out
  as `Category`, `Category`, `Category`... and the same option with no
  series drew all eight whole, which is how the erasure was finally
  visible. Anchored by this rule the whole run hangs away from the axis.

  A VERTICAL AXIS IS ALREADY TURNED. The angle that decides the anchors is
  the text's RELATIVE to the axis line, so an unrotated label on a left
  axis is a quarter turn away from its own axis and lands in the last arm
  below -- which is where the right-aligned, middle-anchored placement a
  value axis has always had actually comes from. }
procedure AnchorsFor(const ASpec: TTyAxisLayoutSpec;
  out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
const
  { Upstream's RADIAN_EPSILON. }
  cRadEps = 1e-4;
var
  axisRot, diff: Double;
  dir: Integer;
begin
  if AxisIsHorizontal(ASpec.Side) then axisRot := 0 else axisRot := Pi / 2;
  diff := RemRadian(ASpec.RotationRad - axisRot);
  { Which side of the line the labels are on; `inside` puts them on the
    other one, and every anchor follows. }
  if ASpec.Side in [asBottom, asRight] then dir := 1 else dir := -1;
  if ASpec.LabelInside then dir := -dir;

  if Abs(diff) < cRadEps then
  begin
    { Along the axis line, reading the same way round. }
    AH := tahCentre;
    if dir > 0 then AV := tavTop else AV := tavBottom;
  end
  else if Abs(diff - Pi) < cRadEps then
  begin
    { Along the line, upside down: the box flips with it. }
    AH := tahCentre;
    if dir > 0 then AV := tavBottom else AV := tavTop;
  end
  else
  begin
    { At an angle to the line. The text hangs by one END so that the run
      goes away from the axis rather than across it. }
    AV := tavMiddle;
    if (diff > 0) and (diff < Pi) then
    begin
      if dir > 0 then AH := tahRight else AH := tahLeft;
    end
    else
    begin
      if dir > 0 then AH := tahLeft else AH := tahRight;
    end;
  end;
end;

function TyLayoutAxisLabels(const ASpec: TTyAxisLayoutSpec; const APlot: TTyRectF;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): TTyAxisLabelPlacementArray;
var
  i, k, m, n: Integer;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  gap, len, iv: Double;
  values: TTyIntegerArray;
  offs: TTyBoolArray;
  cands: TTyLabelCandidateArray;
begin
  Result := nil;
  SetLength(Result, Length(ASpec.Labels));
  if Length(ASpec.Labels) = 0 then Exit;
  AnchorsFor(ASpec, ah, av);
  { THE SAME SUM TyAxisThickness RESERVES, and it has to be: the thickness is
    what the plot gives up and this is where the text goes in it. They were
    written apart, so the moment the thickness stopped charging for a hidden
    or inward tick, the labels went on standing a tick-length further out --
    outside the band reserved for them, over the edge of the control.

    AND INSIDE TURNS IT ROUND. `axisLabel.inside` gave the gutter back and
    left the label exactly where it was, which is `show: false` with the text
    still drawn in the margin. Negating the gap moves it across the axis line
    and the anchors below have to follow it, or it reads outward from a point
    inside and straddles the line it was moved off. }
  gap := AxisScaleF(ASpec.LabelMarginLogical, APPI);
  if ASpec.LabelInside then gap := -gap;
  { FROM THE AXIS LINE, WHICH THE OFFSET HAS MOVED, and by the label margin
    alone: upstream's label sits at the line plus `margin`, and the default
    margin of 8 already clears the default tick of 5. Standing it a tick
    further out put every label five pixels from where upstream draws it;
    ignoring the offset left an offset axis' labels at the plot's edge while
    its line moved away.
    [Revised in batch 37: the tick length was added whenever the tick
    pointed the label's way, and the offset never was.] }
  gap := gap + AxisScaleF(ASpec.OffsetLogical, APPI);
  if AxisIsHorizontal(ASpec.Side) then
    len := TyRectFWidth(APlot)
  else
    len := TyRectFHeight(APlot);
  for i := 0 to High(ASpec.Labels) do
  begin
    Result[i].Index := i;
    Result[i].Text := ASpec.Labels[i];
    { decided below, once every label has its place }
    Result[i].Built := False;
    Result[i].OffInterval := False;
    Result[i].Shown := False;
    Result[i].Emphasis := (ASpec.EmphasisFontWeight > 0)
                          and (i <= High(ASpec.LabelEmphasis))
                          and ASpec.LabelEmphasis[i];
    { THE ANCHOR POINT is the side's business; WHICH POINT OF THE TEXT sits
      on it is AnchorsFor's, for all four alike. }
    Result[i].AnchorH := ah;
    Result[i].AnchorV := av;
    case ASpec.Side of
      asBottom:
        begin
          Result[i].X := APlot.Left + ASpec.Positions[i] * len;
          Result[i].Y := APlot.Bottom + gap;
        end;
      asTop:
        begin
          Result[i].X := APlot.Left + ASpec.Positions[i] * len;
          Result[i].Y := APlot.Top - gap;
        end;
      asLeft:
        begin
          { A vertical axis' fractions run from its START, which is the BOTTOM --
            the same direction the coordinate system's y axis runs, so a label's
            fraction and its datum's fraction are the same number. }
          Result[i].X := APlot.Left - gap;
          Result[i].Y := APlot.Bottom - ASpec.Positions[i] * len;
        end;
      asRight:
        begin
          Result[i].X := APlot.Right + gap;
          Result[i].Y := APlot.Bottom - ASpec.Positions[i] * len;
        end;
    end;
  end;

  { NOTHING IS BUILT WITH THE LABELS OFF -- a hidden axis' labels are not
    there to crowd anything }
  if not ASpec.ShowLabels then Exit;
  n := Length(ASpec.Labels);

  { THE BUILT LIST. A category axis: every interval-th category from nought,
    and its two ends; anything else: every tick. }
  values := nil;
  offs := nil;
  if ASpec.LabelKind = lakCategory then
  begin
    iv := CategoryIntervalOn(ASpec, APlot, AMeasurer, APPI);
    TyCategoryBuiltList(ASpec.OrdinalStart, n, iv, values, offs);
  end
  else
  begin
    SetLength(values, n);
    SetLength(offs, n);
    for i := 0 to n - 1 do
    begin
      values[i] := ASpec.OrdinalStart + i;
      offs[i] := False;
    end;
  end;
  m := 0;
  SetLength(cands, Length(values));
  for k := 0 to High(values) do
  begin
    i := values[k] - ASpec.OrdinalStart;
    if (i < 0) or (i >= n) then Continue;
    cands[m] := Default(TTyLabelCandidate);
    cands[m].Index := i;
    cands[m].OffInterval := offs[k];
    cands[m].NotNice := (ASpec.LabelKind = lakTime)
      and (i <= High(ASpec.LabelNotNice)) and ASpec.LabelNotNice[i];
    cands[m].SuggestIgnore := (i <= High(ASpec.LabelSuggestIgnore))
      and ASpec.LabelSuggestIgnore[i];
    { upstream's z2: ten, and a time tick's level on top }
    cands[m].Priority := 10;
    if (ASpec.LabelKind = lakTime) and (i <= High(ASpec.LabelLevel)) then
      cands[m].Priority := 10 + ASpec.LabelLevel[i];
    Inc(m);
  end;
  SetLength(cands, m);

  { THE BOXES the rules weigh: every one under hideOverlap, else only the
    two at each end }
  if AMeasurer <> nil then
    for k := 0 to m - 1 do
      if ASpec.HideOverlap or (k <= 1) or (k >= m - 2) then
      begin
        LabelBoxes(ASpec, Result[cands[k].Index], AMeasurer, APPI,
          cands[k].Margin, cands[k].Bare);
        cands[k].HasBox := True;
      end;
  if AMeasurer <> nil then
  begin
    TyFixMinMaxLabelShow(cands, ASpec.LabelKind,
      ASpec.ShowAllLabels and (ASpec.LabelKind = lakCategory),
      ASpec.ShowMinLabel, ASpec.ShowMaxLabel, ASpec.HideOverlap);
    if ASpec.HideOverlap then TyHideOverlap(cands);
  end;
  for k := 0 to m - 1 do
  begin
    Result[cands[k].Index].Built := True;
    Result[cands[k].Index].OffInterval := cands[k].OffInterval;
    Result[cands[k].Index].Shown := not cands[k].Ignore;
  end;
end;

end.
