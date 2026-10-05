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
     tyControls.AdvChart.Types, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Paint;

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
{ A grid's rect as upstream's getLayoutRect gives it: x, y, and a width and
  height that are the ones given, where one was, rather than an edge less an
  edge. No margin: a grid has none. }
function TySolveBoxXYWH(const ASpec: TTyBoxSpec;
  const AContainer: ITyBoxContainer): TTyXYWH;

{ ---- a box as upstream's option holds it: title and legend ----

  The shared solver above is kinder than upstream -- it trims, lower-cases,
  takes `centre` and falls back to the default for a word it does not know.
  Title and legend are placed by getLayoutRect on the RAW option values, so
  they keep them raw: what was written, of which JSON kind. }
type
  TTyBoxRawKind = (brAbsent, brNull, brNumber, brString, brBool, brOther);
  TTyBoxRaw = record
    Kind: TTyBoxRawKind;
    Num: Double;   // a number; a boolean's 0 or 1
    Str: string;
  end;
  TTyRawBox = record
    Left, Right, Top, Bottom, Width, Height: TTyBoxRaw;
  end;
  { parsePositionOption's answer before it meets a base. }
  TTyPosKind = (tpkNaN, tpkPx, tpkPct);
  TTyPos = record
    Kind: TTyPosKind;
    V: Double;
  end;

function TyBoxRawOf(AData: TJSONData): TTyBoxRaw;
function TyBoxRawNum(AValue: Double): TTyBoxRaw;
function TyBoxRawStr(const AText: string): TTyBoxRaw;
{ mergeLayoutParam's ignoreSize branch, for a component laid out at init:
  the six keys from the option (a JSON null included) or else ADefault; then
  when the option's OWN left (top) has a value -- not null, not 'auto' -- the
  right (bottom) becomes null, else when its own right (bottom) has one the
  left (top) does. Width and height are never touched. }
function TyMergeBoxIgnoreSize(ANode: TJSONObject;
  const ADefault: TTyRawBox): TTyRawBox;
{ parsePositionOption: the four words exactly, a trimmed string ending in
  `%` a percentage, other strings parseFloat, null not-a-number, anything
  else a unary plus. }
function TyBoxRawPos(const A: TTyBoxRaw): TTyPos;
{ That against its base: a percentage of it, a pixel count, or not-a-number. }
function TyBoxRawResolve(const A: TTyBoxRaw; ABase: Double): Double;
{ `a || b` as getLayoutRect's keyword switch sees it: the first truthy of the
  two, as its string -- '' when it is no string. }
function TyBoxWord(const A, B: TTyBoxRaw): string;
{ getLayoutRect, line for line: NaN arithmetic in upstream's order, the
  keyword switch, the width fallback, and BoundingRect's sign flip. AMargin
  in CSS order. }
function TyGetLayoutRect(const ABox: TTyRawBox; ACX, ACY, ACW, ACH: Double;
  const AMargin: array of Double): TTyXYWH;

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
    { THE TIME AXIS' `rich.primary`, from the skin: the weight (and the
      colour, where the skin gives one) its coarse ticks' `{primary|...}`
      tags are drawn in -- upstream's default is `fontWeight: 'bold'`. An
      author's axisLabel.rich.primary is laid over it. Resolved from the theme
      by the caller, like everything else in this record, because these are
      visual values and this library does not put those in control code.
      [Revised in batch 104: the weight of a whole label marked emphasised;
      now the default of a rich style, so only the tagged part is heavier.] }
    EmphasisFontWeight: Integer;
    HasEmphasisColour: Boolean;
    EmphasisColour: Cardinal;
    LabelMarginLogical: Double;
    TickLengthLogical: Double;
    NameGapLogical: Double;
    { The axis NAME's font, which the layout measures the name in: the same
      one the paint pass draws it in, and not always the labels'. }
    NameFontName: string;
    NameFontSizeLogical: Integer;
    NameFontWeight: Integer;
    { THE OPTION'S ROOT textStyle.color, which an axis NAME takes where its
      own options give none -- free-standing text with no default colour of
      its own (upstream's setTextStyleCommon; the labels have one). A chart
      colour (TTyChartColor) carried as the Cardinal it is, as this unit does
      not see the paint layer. }
    HasGlobalColour: Boolean;
    GlobalColour: Cardinal;
    { the root's side of a label's or a name's text block [Batch 86] }
    RtGlobal: TTyRtGlobal;
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
    { THE LABEL'S MATRIX AS ZRENDER ENDS UP WITH IT: the axis group's times
      the label's own turn, decomposed into props and recomposed from them --
      which is not the turn asked for, by a few units in the last place, and
      at a skew of 2 pi goes through V8's tan. HasM False (the zero value)
      means a hand-built spec, which keeps the plain turn. DecRotation is the
      decomposed rotation, what upstream's element reports. }
    M: TTyMat2D;
    HasM: Boolean;
    DecRotation: Double;
    { THE BLOCK, where the labels' style needs one: its pieces about (X, Y),
      turned as the label is, in CSS px [Batch 86] }
    Rt: TTyRtPieceArray;
  end;
  TTyAxisLabelPlacementArray = array of TTyAxisLabelPlacement;

  { Transformable's props after decomposeTransform, parentless, origin 0. }
  TTyTransformProps = record
    X, Y, Rotation, ScaleX, ScaleY, SkewX: Double;
  end;

  { ONE TICK MARK, SPLIT LINE OR SPLIT-AREA EDGE, where the layout put it: the
    tick it stands for (a category axis' ordinal; the category past the last
    for the closing band edge), its place in device px along the axis,
    whether it was moved onto a band edge, and whether it is drawn -- a tick
    whose label was hidden goes with it, a split line at an end can be
    denied. }
  TTyAxisMark = record
    Value: Double;
    Coord: Double;
    { the same place in the axis' own frame, upstream's ticksCoords[i].coord
      -- what a tick is drawn from through the axis group's matrix
      [Batch 96] }
    Local: Double;
    OffInterval: Boolean;
    OnBand: Boolean;
    Drawn: Boolean;
    { WHICH COLOUR OF ITS LIST [Batch 101]: a split line's is the count of
      the lines drawn before it, a split area mark's the colour of the band
      that starts at it -- carried from the last render by tick value, as
      upstream's axis view keeps it. Nought on a tick. }
    ColourIndex: Integer;
  end;
  TTyAxisMarkArray = array of TTyAxisMark;

  { AN ARROW AT ONE END OF THE AXIS LINE [Batch 101]: axisLine.symbol at that
    end, its box (-W/2, -H/2, W, H) about (X, Y), turned by Rotation
    (counter-clockwise, as zrender turns it) -- AxisBuilder's element as it
    stands. End_ is 0 for the start, which is the SMALLER end of the axis'
    local extent whichever way the axis runs, and 1 for the other. }
  TTyAxisArrow = record
    End_: Integer;
    SymbolType: string;
    X, Y, Rotation, W, H: Double;
  end;
  TTyAxisArrowArray = array of TTyAxisArrow;

  { ONE COLOUR OF AN AUTHOR'S SPLIT LINE OR SPLIT AREA LIST [Batch 101]. Ok
    False is a colour the port cannot read: nothing is drawn in it. }
  TTyAxisInk = record
    Ok: Boolean;
    Colour: Cardinal;
  end;
  TTyAxisInkArray = array of TTyAxisInk;

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
    { THE BLOCK, where the name's style needs one [Batch 86] }
    Rt: TTyRtPieceArray;
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
    { Each label's tick value, and its place in the axis' OWN frame --
      TTyAxis.DataToLocal on the rect of the pass being laid out. Parallel to
      Labels. With these a label is placed as upstream places it, through
      the axis group's matrix from the name frame; without them -- a spec
      built by hand -- it falls back to the fraction along the plot. }
    TickValues: TTyDoubleArray;
    LocalCoords: TTyDoubleArray;
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    { axisLabel.color over the root textStyle's, as a chart colour; the
      theme's where neither is written }
    HasLabelColour: Boolean;
    LabelColour: Cardinal;
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
    { THE TEXT BLOCKS of the labels (axisLabel's `rich`, box, size) and of
      the name (nameTextStyle's), resolved by the builder; the root's side;
      device px per CSS px; and the measurers that answer a block's box,
      which every measurement of a label or the name goes through -- so the
      interval, the gutter and the name's room are the block's and not the
      markup's. Nil meters: the plain measurer. [Batch 86] }
    LabelRt, NameRt: TTyRtBlockStyle;
    RtGlobal: TTyRtGlobal;
    RtScale: Double;
    LabelMeter, NameMeter: ITyTextMeasurer;
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

    { axisLabel.customValues WRITTEN (any truthy value) [Batch 110]: Labels,
      TickValues and the arrays parallel to them are the custom values' --
      those in the extent, deduplicated, ascending -- and every one is built:
      no interval thins them, and the end rules leave them alone unless
      hideOverlap or showMin/MaxLabel says otherwise. A CATEGORY axis keeps
      its own labels beside them in CatLabels, CatTickValues and
      CatLocalCoords, because its auto interval -- which its ticks, split
      lines and line symbols still walk -- is measured from those. }
    CustomLabels: Boolean;
    CatLabels: TTyStringArray;
    CatTickValues: TTyDoubleArray;
    CatLocalCoords: TTyDoubleArray;

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
    HasNameColour: Boolean;
    NameColour: Cardinal;
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

    { ---- the finishing touches [Batch 101] ---- }

    { THE AXIS LINE'S ARROWS on the final rect, in the order upstream adds
      them (the start first); empty when the line is not drawn }
    Arrows: TTyAxisArrowArray;
    { THE AUTHOR'S SPLIT COLOURS: splitLine.lineStyle.color and
      splitArea.areaStyle.color, a string as a list of one. Empty is the
      skin's -- one line colour, and for the areas the skin's colour and
      none in turn, which is upstream's default pair (a tint and a
      transparent). Each mark's ColourIndex picks from it. }
    SplitLineInks: TTyAxisInkArray;
    SplitAreaInks: TTyAxisInkArray;
    { the length upstream's split-area cache counts in: the list's, a
      string's own (each band then falls back to the one colour), 2 for the
      skin's pair }
    SplitAreaInkCount: Integer;
    { nameTruncate [Batch 101]: whether a maxWidth was written, the width
      and the ellipsis; applied to Name by the builder. A flag and not a
      sentinel width: the zero value has to be `no cut`, and 0 is a width
      upstream honours (it leaves nothing). }
    HasNameTrunc: Boolean;
    NameTruncWidth: Double;
    NameTruncEllipsis: string;
    { A FRAME OF ITS OWN [Batch 111]: an axis AxisBuilder lays out away from
      a grid -- the polar's radius axis -- turned by NameFrame.Rotation, its
      labels on the LabelDirection side of the line whatever axisLabel.inside
      says (AxisBuilder reads no `inside`; a grid's helper flips the
      direction before it gets there). False, the zero value, is a grid axis
      on its Side. }
    FreeFrame: Boolean;
    LabelDirection: Integer;
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
{ Transformable.decomposeTransform on a parentless element with no origin --
  its order of operations exactly. }
function TyMatDecompose(const M: TTyMat2D): TTyTransformProps;
{ Transformable.getLocalTransform from those props: [sx, 0, tan(skewX) sy,
  sy], turned by the rotation, then moved. }
function TyMatRecompose(const P: TTyTransformProps): TTyMat2D;
{ needLocalTransform for a turn and a move: any of them past 5e-5. }
function TyNeedLocal(AX, AY, ARotation: Double): Boolean;
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
{ The same, from and to the rect as upstream holds it: ARawXYWH is the raw
  rect's own x, y, width and height, and the shrunk one comes back whole. }
function TySolveGridBoundsXYWH(const ARaw: TTyRectF; const ARawXYWH: TTyXYWH;
  const AOuter: TTyXYWH; AContain: TTyOuterBoundsContain;
  AClampW, AClampH: Double; const AAxes: TTyAxisLayoutSpecArray;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AContainer: TTyXYWH;
  out ANoPxChange: Boolean): TTyXYWH;

{ Legacy grid.containLabel: for every axis in turn whose labels are not
  inside, the widest (or tallest) of all its labels -- unrotated, turned by
  |cos| and |sin|, no textMargin, every label up to forty and a sample past
  that -- plus the label margin, taken off its side. Axes on one side stack.
  Names, offsets and axis.show do not enter into it. }
function TyLegacyContainLabel(const ARaw: TTyRectF;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyRectF;
function TyLegacyContainLabelXYWH(const ARawXYWH: TTyXYWH;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyXYWH;

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

{ A category axis' own label count: its categories in the extent, whether or
  not custom labels stand in for them [Batch 110] }
function TyCategoryLabelCount(const ASpec: TTyAxisLayoutSpec): Integer;

{ The uniform step TyLayoutAxisLabels chose: 1 = every label, 2 = every other.
  Exposed because a caller drawing tick MARKS has to thin them the same way, and
  computing it twice by two routes is how the marks and the labels drift apart. }
function TyAxisLabelStep(const ASpec: TTyAxisLayoutSpec; const APlot: TTyRectF;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): Integer;

implementation

uses tyControls.AdvChart.AxisName, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.AxisLabels, tyControls.AdvChart.Data;

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
  out AStart, AStop, ALen: Double);
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
      ALen := AStop - AStart;
      Exit;
    end;
    { NO MARGIN TERM. Upstream writes `extent/2 - size/2 - marginStart` and
      then adds marginStart back on the way out, so the two cancel: a centred
      box is centred on the CONTAINER, not on what is left of it. }
    AStart := AContainerStart + (AContainerExtent - sz) / 2;
    AStop := AStart + sz;
    ALen := sz;
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

  { THE LENGTH AS UPSTREAM HOLDS IT: a size that was given is the width,
    not the far edge less the near one, which need not round back to it. }
  if not IsNan(sz) then
    ALen := sz
  else
    ALen := AStop - AStart;

  { Over-constrained: collapse to zero at the near edge rather than invert. An
    inverted rect survives a later Min/Max swap and reappears as a phantom band
    somewhere else on screen, which is far harder to find than an empty one. }
  if AStop < AStart then
  begin
    AStop := AStart;
    ALen := 0;
  end;
end;

function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer;
  const AMargin: array of Double): TTyRectF;
var
  c: TTyRectF;
  l, r, t, b, lw, lh: Double;
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
    m[3], m[1], l, r, lw);
  SolveAxis(ASpec.Top, ASpec.Bottom, ASpec.Height, c.Top, TyRectFHeight(c),
    m[0], m[2], t, b, lh);
  Result := TyRectF(l, t, r, b);
end;

function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer): TTyRectF;
begin
  Result := TySolveBox(ASpec, AContainer, []);
end;

function TySolveBoxXYWH(const ASpec: TTyBoxSpec;
  const AContainer: ITyBoxContainer): TTyXYWH;
var
  c: TTyRectF;
  l, r, t, b, lw, lh: Double;
begin
  Result := TyXYWH(NaN, NaN, NaN, NaN);
  if AContainer = nil then Exit;
  c := AContainer.ContainerRect;
  if not TyRectFIsValid(c) then Exit;
  SolveAxis(ASpec.Left, ASpec.Right, ASpec.Width, c.Left, TyRectFWidth(c),
    0, 0, l, r, lw);
  SolveAxis(ASpec.Top, ASpec.Bottom, ASpec.Height, c.Top, TyRectFHeight(c),
    0, 0, t, b, lh);
  Result := TyXYWH(l, t, lw, lh);
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
  { THE LENGTH AS WRITTEN at 96: v * 96 / 96 is not v for a sixth of all
    doubles -- 2.7 and 12.3 among them -- and upstream uses the length as it
    is. The ratio first, which is exactly 1 there. }
  Result := ALogical * (APPI / 96);
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
{ the measurer a label (a name) of ASpec is measured through [Batch 86] }
function LabelMeterOf(const ASpec: TTyAxisLayoutSpec;
  const AMeasurer: ITyTextMeasurer): ITyTextMeasurer;
begin
  if (ASpec.LabelMeter <> nil) and (AMeasurer <> nil) then Result := ASpec.LabelMeter
  else Result := AMeasurer;
end;

function NameMeterOf(const ASpec: TTyAxisLayoutSpec;
  const AMeasurer: ITyTextMeasurer): ITyTextMeasurer;
begin
  if (ASpec.NameMeter <> nil) and (AMeasurer <> nil) then Result := ASpec.NameMeter
  else Result := AMeasurer;
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
  LabelMeterOf(ASpec, AMeasurer).MeasureLine(APlace.Text, ASpec.FontName,
    ASpec.FontSizeLogical, ASpec.FontWeight, w, h);
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
  if APlace.HasM then ABare.M := APlace.M
  else ABare.M := TyMatLocal(APlace.X, APlace.Y, ASpec.RotationRad);
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

function TyCategoryLabelCount(const ASpec: TTyAxisLayoutSpec): Integer;
begin
  if ASpec.CustomLabels then Result := Length(ASpec.CatLabels)
  else Result := Length(ASpec.Labels);
end;

{ the spec its category interval is measured from: the category's own
  labels where custom ones stand in for them }
function IntervalSpec(const ASpec: TTyAxisLayoutSpec): TTyAxisLayoutSpec;
begin
  Result := ASpec;
  if not ASpec.CustomLabels then Exit;
  Result.CustomLabels := False;
  Result.Labels := ASpec.CatLabels;
  Result.TickValues := ASpec.CatTickValues;
  Result.LocalCoords := ASpec.CatLocalCoords;
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
  if ASpec.CustomLabels then
    Exit(CategoryIntervalOn(IntervalSpec(ASpec), APlot, AMeasurer, APPI));
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
  { UPSTREAM'S OWN EXPRESSION when the axis gave the labels' coordinates:
    dataToCoord(e0 + 1) - dataToCoord(e0), over the mapping extent -- which
    half a bar widens on an unbanded axis, and which the closed form below
    does not know about }
  if Length(ASpec.LocalCoords) = n then
    unitSpan := ASpec.LocalCoords[1] - ASpec.LocalCoords[0]
  else
    unitSpan := TyCategoryUnitSpan(len, n, ASpec.OnBand, ASpec.Inverse);
  SetLength(ws, (n - 1) div s + 1);
  SetLength(hs, Length(ws));
  k := 0;
  i := 0;
  while i <= n - 1 do
  begin
    { the widest line, and one line's height }
    LabelMeterOf(ASpec, AMeasurer).MeasureLine(ASpec.Labels[i], ASpec.FontName,
      ASpec.FontSizeLogical, ASpec.FontWeight, w, h);
    LabelMeterOf(ASpec, AMeasurer).MeasureLine(FirstLine(ASpec.Labels[i]),
      ASpec.FontName, ASpec.FontSizeLogical, ASpec.FontWeight, lw, h);
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
    { MEASURED AS IT WILL BE DRAWN: a time axis' `{primary|...}` part is
      bold, and the label meter lays the tags out in their own weight -- a
      label measured light and drawn bold is how an axis comes to overlap the
      one thing the measuring was for. }
    LabelMeterOf(ASpec, AMeasurer).MeasureLine(ASpec.Labels[i], ASpec.FontName,
      ASpec.FontSizeLogical, ASpec.FontWeight, w, h);
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
    NameMeterOf(ASpec, AMeasurer).MeasureLine(ASpec.Name, ASpec.FontName,
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


{ ==================== getLayoutRect on raw values ==================== }

function TyBoxRawOf(AData: TJSONData): TTyBoxRaw;
begin
  Result := Default(TTyBoxRaw);
  if AData = nil then Exit;
  case AData.JSONType of
    jtNull: Result.Kind := brNull;
    jtNumber:
      begin
        Result.Kind := brNumber;
        Result.Num := AData.AsFloat;
      end;
    jtString:
      begin
        Result.Kind := brString;
        Result.Str := AData.AsString;
      end;
    jtBoolean:
      begin
        Result.Kind := brBool;
        if AData.AsBoolean then Result.Num := 1 else Result.Num := 0;
      end;
  else
    Result.Kind := brOther;
  end;
end;

function TyBoxRawNum(AValue: Double): TTyBoxRaw;
begin
  Result := Default(TTyBoxRaw);
  Result.Kind := brNumber;
  Result.Num := AValue;
end;

function TyBoxRawStr(const AText: string): TTyBoxRaw;
begin
  Result := Default(TTyBoxRaw);
  Result.Kind := brString;
  Result.Str := AText;
end;

function TyMergeBoxIgnoreSize(ANode: TJSONObject;
  const ADefault: TTyRawBox): TTyRawBox;

  { The option's own value when it has the key, the default otherwise. }
  function Pick(const AKey: string; const ADef: TTyBoxRaw): TTyBoxRaw;
  var d: TJSONData;
  begin
    Result := ADef;
    if ANode = nil then Exit;
    d := ANode.Find(AKey);
    if d <> nil then Result := TyBoxRawOf(d);
  end;

  { hasValue on the OPTION'S OWN value: `!= null && !== 'auto'`. }
  function Own(const AKey: string): Boolean;
  var d: TJSONData;
  begin
    Result := False;
    if ANode = nil then Exit;
    d := ANode.Find(AKey);
    if (d = nil) or (d.JSONType = jtNull) then Exit;
    if (d.JSONType = jtString) and (d.AsString = 'auto') then Exit;
    Result := True;
  end;

var nul: TTyBoxRaw;
begin
  Result.Left := Pick('left', ADefault.Left);
  Result.Right := Pick('right', ADefault.Right);
  Result.Top := Pick('top', ADefault.Top);
  Result.Bottom := Pick('bottom', ADefault.Bottom);
  Result.Width := Pick('width', ADefault.Width);
  Result.Height := Pick('height', ADefault.Height);
  nul := Default(TTyBoxRaw);
  nul.Kind := brNull;
  if Own('left') then Result.Right := nul
  else if Own('right') then Result.Left := nul;
  if Own('top') then Result.Bottom := nul
  else if Own('bottom') then Result.Top := nul;
end;

function TyBoxRawPos(const A: TTyBoxRaw): TTyPos;
var s: string;
begin
  Result.Kind := tpkNaN;
  Result.V := NaN;
  case A.Kind of
    brNumber, brBool:
      begin
        Result.Kind := tpkPx;
        Result.V := A.Num;
      end;
    brString:
      begin
        s := A.Str;
        if (s = 'center') or (s = 'middle') then s := '50%'
        else if (s = 'left') or (s = 'top') then s := '0%'
        else if (s = 'right') or (s = 'bottom') then s := '100%';
        s := TyJsTrim(s);
        if (s <> '') and (s[Length(s)] = '%') then Result.Kind := tpkPct
        else Result.Kind := tpkPx;
        if (A.Str = 'center') or (A.Str = 'middle') then Result.V := 50
        else if (A.Str = 'left') or (A.Str = 'top') then Result.V := 0
        else if (A.Str = 'right') or (A.Str = 'bottom') then Result.V := 100
        else Result.V := TyJsParseFloat(A.Str);
        if IsNan(Result.V) then Result.Kind := tpkNaN;
      end;
  end;
end;

{ One position against its base: `parseFloat(option) / 100 * base + 0`, a
  pixel count, or not-a-number. }
function TyBoxRawResolve(const A: TTyBoxRaw; ABase: Double): Double;
var p: TTyPos;
begin
  p := TyBoxRawPos(A);
  case p.Kind of
    tpkPx: Result := p.V;
    tpkPct: Result := p.V / 100 * ABase + 0;
  else
    Result := NaN;
  end;
end;

function RawTruthy(const A: TTyBoxRaw): Boolean;
begin
  case A.Kind of
    brNumber, brBool: Result := (not IsNan(A.Num)) and (A.Num <> 0);
    brString: Result := A.Str <> '';
    brOther: Result := True;
  else
    Result := False;
  end;
end;

function TyBoxWord(const A, B: TTyBoxRaw): string;
begin
  Result := '';
  if RawTruthy(A) then
  begin
    if A.Kind = brString then Result := A.Str;
  end
  else if B.Kind = brString then
    Result := B.Str;
end;

{ `x || 0`: not-a-number and either nought are nought. }
function OrZero(AV: Double): Double;
begin
  if IsNan(AV) or (AV = 0) then Result := 0 else Result := AV;
end;

function TyGetLayoutRect(const ABox: TTyRawBox; ACX, ACY, ACW, ACH: Double;
  const AMargin: array of Double): TTyXYWH;
var
  left, top, right, bottom, w, h, vm, hm: Double;
  m: array[0..3] of Double;
  i: Integer;
  wordH, wordV: string;
begin
  for i := 0 to 3 do
    if i <= High(AMargin) then m[i] := AMargin[i] else m[i] := 0;
  left := TyBoxRawResolve(ABox.Left, ACW);
  top := TyBoxRawResolve(ABox.Top, ACH);
  right := TyBoxRawResolve(ABox.Right, ACW);
  bottom := TyBoxRawResolve(ABox.Bottom, ACH);
  w := TyBoxRawResolve(ABox.Width, ACW);
  h := TyBoxRawResolve(ABox.Height, ACH);
  vm := m[2] + m[0];
  hm := m[1] + m[3];
  { a size from the two sides }
  if IsNan(w) then w := ACW - right - hm - left;
  if IsNan(h) then h := ACH - bottom - vm - top;
  { a missing side from the other one }
  if IsNan(left) then left := ACW - right - w - hm;
  if IsNan(top) then top := ACH - bottom - h - vm;
  { THE KEYWORD SWITCH on `left || right`, `top || bottom` }
  wordH := TyBoxWord(ABox.Left, ABox.Right);
  if wordH = 'center' then left := ACW / 2 - w / 2 - m[3]
  else if wordH = 'right' then left := ACW - w - hm;
  wordV := TyBoxWord(ABox.Top, ABox.Bottom);
  if (wordV = 'middle') or (wordV = 'center') then top := ACH / 2 - h / 2 - m[0]
  else if wordV = 'bottom' then top := ACH - h - vm;
  left := OrZero(left);
  top := OrZero(top);
  if IsNan(w) then w := ACW - hm - left - OrZero(right);
  if IsNan(h) then h := ACH - vm - top - OrZero(bottom);
  Result.X := OrZero(ACX) + left + m[3];
  Result.Y := OrZero(ACY) + top + m[0];
  Result.W := w;
  Result.H := h;
  { new BoundingRect: a negative size flips the rect onto its other edge }
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

function TyMatDecompose(const M: TTyMat2D): TTyTransformProps;
var sx, sy, r, sh: Double;
begin
  sx := M[0] * M[0] + M[1] * M[1];
  sy := M[2] * M[2] + M[3] * M[3];
  r := TyJsAtan2(M[1], M[0]);
  sh := Pi / 2 + r - TyJsAtan2(M[3], M[2]);
  sy := Sqrt(sy) * TyJsCos(sh);
  sx := Sqrt(sx);
  Result.SkewX := sh;
  Result.Rotation := -r;
  Result.X := M[4];
  Result.Y := M[5];
  Result.ScaleX := sx;
  Result.ScaleY := sy;
end;

function TyMatRecompose(const P: TTyTransformProps): TTyMat2D;
var k: Double;
begin
  if P.SkewX <> 0 then k := TyJsTan(P.SkewX) else k := 0;
  Result[4] := 0;
  Result[5] := 0;
  Result[0] := P.ScaleX;
  Result[3] := P.ScaleY;
  Result[1] := 0 * P.ScaleX;
  Result[2] := k * P.ScaleY;
  { `rotation && rotate(...)`: a nought -- minus nought too -- turns nothing }
  if P.Rotation <> 0 then Result := MatRotate(Result, P.Rotation);
  Result[4] := Result[4] + (0 + P.X);
  Result[5] := Result[5] + (0 + P.Y);
end;

function TyNeedLocal(AX, AY, ARotation: Double): Boolean;
const cEps = 5e-5;
begin
  Result := (ARotation > cEps) or (ARotation < -cEps)
    or (AX > cEps) or (AX < -cEps) or (AY > cEps) or (AY < -cEps);
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
begin
  Result := TyRectOfXYWH(TySolveGridBoundsXYWH(ARaw, TyXYWHOfRect(ARaw),
    AOuter, AContain, AClampW, AClampH, AAxes, AMeasurer, APPI, AContainer,
    ANoPxChange));
end;

function TySolveGridBoundsXYWH(const ARaw: TTyRectF; const ARawXYWH: TTyXYWH;
  const AOuter: TTyXYWH; AContain: TTyOuterBoundsContain;
  AClampW, AClampH: Double; const AAxes: TTyAxisLayoutSpecArray;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AContainer: TTyXYWH;
  out ANoPxChange: Boolean): TTyXYWH;
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
  r := ARawXYWH;
  margin := TyOuterBoundsMargin(AOuter, ARawXYWH, items);
  ANoPxChange := True;
  for k := 0 to 3 do
    if margin[k] > 0 then ANoPxChange := False;
  TyShrinkRect(r, margin, AClampW, AClampH);
  Result := r;
end;

function TyLegacyContainLabel(const ARaw: TTyRectF;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyRectF;
begin
  Result := TyRectOfXYWH(TyLegacyContainLabelXYWH(TyXYWHOfRect(ARaw), AAxes,
    AMeasurer, APPI));
end;

function TyLegacyContainLabelXYWH(const ARawXYWH: TTyXYWH;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyXYWH;
var
  i, k, n, step: Integer;
  w, h, uw, uh, c, s, rw, rh, gap: Double;
  r: TTyXYWH;
  any: Boolean;
begin
  r := ARawXYWH;
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
        LabelMeterOf(AAxes[i], AMeasurer).MeasureLine(AAxes[i].Labels[k],
          AAxes[i].FontName, AAxes[i].FontSizeLogical, AAxes[i].FontWeight, w, h);
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
  Result := r;
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
  n := TyCategoryLabelCount(ASpec);
  { an infinite interval, or one past the last label, keeps the first alone }
  if IsInfinite(iv) or (iv + 1 > n) then Result := Max(1, n)
  else Result := Trunc(iv) + 1;
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
  { an axis in a frame of its own is turned by it [Batch 111] }
  if ASpec.FreeFrame then axisRot := ASpec.NameFrame.Rotation;
  { Into [0, 2*PI) by upstream's remRadian -- JavaScript's % twice, not a
    Floor, which is 1 ulp off -- and NOT the [-PI, PI) a reader expects. The
    interval matters: a quarter turn CLOCKWISE comes back as three quarters
    anticlockwise, which is on the far side of PI and so lands in the other
    arm of the alignment rule below. }
  diff := TyRemRadian(ASpec.RotationRad - axisRot);
  { Which side of the line the labels are on; `inside` puts them on the
    other one, and every anchor follows. }
  if ASpec.Side in [asBottom, asRight] then dir := 1 else dir := -1;
  if ASpec.LabelInside then dir := -dir;
  if ASpec.FreeFrame then dir := ASpec.LabelDirection;

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
  gap, len, iv, t: Double;
  values: TTyIntegerArray;
  offs: TTyBoolArray;
  cands: TTyLabelCandidateArray;
  byFrame: Boolean;
  fr: TTyAxisNameFrame;
  g, lm: TTyMat2D;
  lr: Double;
  props: TTyTransformProps;
begin
  Result := nil;
  SetLength(Result, Length(ASpec.Labels));
  if Length(ASpec.Labels) = 0 then Exit;
  AnchorsFor(ASpec, ah, av);
  { UPSTREAM'S ANCHOR (AxisBuilder): the label's point in the axis' own
    frame -- its coordinate c along, and t across, the label offset of an
    axis on the other's zero plus the margin outward -- turned into the
    canvas by the axis group's matrix, [1,0,0,1,X,Y] across and a quarter
    turn down. That turn is not exact: cos(pi/2) is 6e-17, and it moves a
    y axis' labels in their last bits, as upstream's move. The offset is
    already in the frame's X and Y, so not in t. }
  byFrame := Length(ASpec.LocalCoords) = Length(ASpec.Labels);
  if byFrame then
  begin
    if ASpec.HasNameFrame then fr := ASpec.NameFrame
    else fr := TyDefaultNameFrame(ASpec, APlot, APPI);
    t := AxisScaleF(ASpec.LabelMarginLogical, APPI);
    if ASpec.LabelInside then t := -t;
    { cfg.labelOffset + cfg.labelDirection * margin: a grid's label
      direction is its name direction, a frame of its own says [Batch 111] }
    if ASpec.FreeFrame then
      t := fr.LabelOffset + ASpec.LabelDirection * AxisScaleF(ASpec.LabelMarginLogical, APPI)
    else
      t := fr.LabelOffset + fr.NameDirection * t;
    g := TyMatLocal(fr.PosX, fr.PosY, fr.Rotation);
  end;
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
    { THE ANCHOR POINT is the side's business; WHICH POINT OF THE TEXT sits
      on it is AnchorsFor's, for all four alike. }
    Result[i].AnchorH := ah;
    Result[i].AnchorV := av;
    if byFrame then
    begin
      { AxisBuilder: the label is a child of the axis group, at (c, t) and
        turned by the requested angle less the axis' own; zrender multiplies
        the two, and a turn or move within 5e-5 of nothing is no local
        transform at all. The anchor is that product's translation. }
      lr := TyRemRadian(ASpec.RotationRad - fr.Rotation);
      if TyNeedLocal(ASpec.LocalCoords[i], t, lr) then
        lm := TyMatMul(g, TyMatLocal(ASpec.LocalCoords[i], t, lr))
      else
        lm := g;
      Result[i].X := lm[4];
      Result[i].Y := lm[5];
      { THEN THE LABEL IS TAKEN OUT OF THE GROUP -- decomposed to props and
        recomposed from them -- and that matrix is the one its rect, its
        overlap box and the name's occupied area are made with. }
      props := TyMatDecompose(lm);
      Result[i].M := TyMatRecompose(props);
      Result[i].DecRotation := props.Rotation;
      Result[i].HasM := True;
    end
    else
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
  { custom labels: every one, as a value axis builds its ticks [Batch 110] }
  if (ASpec.LabelKind = lakCategory) and not ASpec.CustomLabels then
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
      ASpec.ShowMinLabel, ASpec.ShowMaxLabel, ASpec.HideOverlap,
      ASpec.CustomLabels);
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
