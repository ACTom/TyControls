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

  TTyAxisLabelPlacement = record
    Index: Integer;
    Text: string;
    X, Y: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    Shown: Boolean;
    { Drawn in the heavier weight. Carried on the PLACEMENT and not looked up
      again at paint time, because the measurement that reserved room for this
      label was made in that same weight. }
    Emphasis: Boolean;
  end;
  TTyAxisLabelPlacementArray = array of TTyAxisLabelPlacement;
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

    { Labels that exist -- they were measured, they hold their place in the
      parallel arrays -- but are not drawn. The two ends of a time axis are
      the data's own ragged boundaries, and a `07:13` jammed against the
      first round hour is the most visible mark of a careless port. }
    LabelHidden: TTyBoolArray;
    { Which labels carry the heavier weight: on a time axis the coarse ticks,
      the ones that say `Mar` among a run of day numbers. }
    LabelEmphasis: TTyBoolArray;
    { The weight those get. Nought means the spec's own weight, so an axis
      that marks no label for emphasis need not name one. }
    EmphasisFontWeight: Integer;
    { DO NOT THIN. The uniform every-Nth step below is right for a category
      axis, where the labels are interchangeable; a time axis' labels are not
      -- dropping every other one takes the month markers with it and leaves a
      row of day numbers that restart for no visible reason. Upstream thins a
      time axis by measuring collisions instead, never by index.

      This is a statement about the AXIS TYPE. What the AUTHOR asked for is
      ForcedLabelStep below, and the two cannot collide: an authored interval
      is read on category axes only, and no category axis sets this. }
    KeepEveryLabel: Boolean;

    { `axisLabel.interval`, already turned into a stride: nought means the
      author said nothing and the measured rule decides, 1 means every label,
      N means every Nth.

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

    { The two ends, separately deniable. `aelAuto` is upstream's default and
      means `shown when the stride landed on it`. }
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
  end;
  TTyAxisLayoutSpecArray = array of TTyAxisLayoutSpec;
  PTyAxisLayoutSpec = ^TTyAxisLayoutSpec;

  { x, y, width and height: upstream's own shape for a rect. The shrink is
    done in it so that its arithmetic is upstream's to the bit -- a right edge
    is x + width there, and a width taken back from one is not always the
    same number. }
  TTyXYWH = record
    X, Y, W, H: Double;
  end;

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

{ The axis NAME as the paint pass draws it, proportion one half, which is
  upstream's for a centred name. INTERIM: upstream lays names out by
  location, gap, rotation and margin level, and a name batch will; until
  then the name counts where it is actually drawn. False for no name. }
function TyAxisNameBoundsItem(const ASpec: TTyAxisLayoutSpec;
  const ARaw: TTyRectF; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  out AItem: TTyBoundsItem): Boolean;

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
  APPI: Integer): TTyRectF;

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

{ The uniform step TyLayoutAxisLabels chose: 1 = every label, 2 = every other.
  Exposed because a caller drawing tick MARKS has to thin them the same way, and
  computing it twice by two routes is how the marks and the labels drift apart. }
function TyAxisLabelStep(const ASpec: TTyAxisLayoutSpec; const APlot: TTyRectF;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): Integer;

implementation

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
  c := Abs(Cos(AAngleRad));
  s := Abs(Sin(AAngleRad));
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

{ Whether label AIndex is drawn at all. }
function HiddenAt(const ASpec: TTyAxisLayoutSpec; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ASpec.LabelHidden))
            and ASpec.LabelHidden[AIndex];
end;

{ Does one of the two end-label options decide this index outright?

  THE ENDS ARE THE ONLY INDICES A STRIDE CAN BE ASKED TO OVERRULE. A stride
  anchored at nought always lands on the first label and lands on the last
  only when the count happens to suit it, so the last label of a thinned
  axis is missing far more often than the first -- and it is the one a
  reader looks for, because it says where the data stops.

  Neither option applies to an axis with a single label: upstream's rule
  needs an inner neighbour to weigh the end against and bails without one. }
function EndLabelDecides(const ASpec: TTyAxisLayoutSpec;
  AIndex, ACount: Integer; out AShown: Boolean): Boolean;
var opt: TTyAxisEndLabel;
begin
  Result := False;
  AShown := False;
  if ACount < 2 then Exit;
  if AIndex = 0 then opt := ASpec.ShowMinLabel
  else if AIndex = ACount - 1 then opt := ASpec.ShowMaxLabel
  else Exit;
  if opt = aelAuto then Exit;
  AShown := opt = aelShow;
  Result := True;
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

{ The box a label is drawn in, turned about its anchor and padded, as the
  axis-aligned rect round it -- zrender's getBoundingRect after the label's
  transform: the four corners, their least and greatest. }
function LabelBox(AX, AY, AW, AH, APadH, APadV, ARot: Double;
  AAnchorH: TTyTextAnchorH; AAnchorV: TTyTextAnchorV): TTyXYWH;
var
  x0, x1, y0, y1, c, s, px, py, lo, hi, vlo, vhi: Double;
  k: Integer;
begin
  case AAnchorH of
    tahLeft: x0 := 0;
    tahRight: x0 := -AW;
  else
    x0 := -AW / 2;
  end;
  case AAnchorV of
    tavTop: y0 := 0;
    tavBottom: y0 := -AH;
  else
    y0 := -AH / 2;
  end;
  x1 := x0 + AW + APadH;
  x0 := x0 - APadH;
  y1 := y0 + AH + APadV;
  y0 := y0 - APadV;
  if ARot = 0 then
    Exit(TyXYWH(AX + x0, AY + y0, x1 - x0, y1 - y0));
  { COUNTER-CLOCKWISE on a screen whose y runs down, zrender's rotate: x' is
    x cos + y sin, y' is -x sin + y cos }
  c := Cos(ARot);
  s := Sin(ARot);
  lo := Infinity;
  hi := NegInfinity;
  vlo := Infinity;
  vhi := NegInfinity;
  for k := 0 to 3 do
  begin
    if k in [0, 3] then px := x0 else px := x1;
    if k in [0, 1] then py := y0 else py := y1;
    if px * c + py * s < lo then lo := px * c + py * s;
    if px * c + py * s > hi then hi := px * c + py * s;
    if -px * s + py * c < vlo then vlo := -px * s + py * c;
    if -px * s + py * c > vhi then vhi := -px * s + py * c;
  end;
  Result := TyXYWH(AX + lo, AY + vlo, hi - lo, vhi - vlo);
end;

function TyAxisLabelBoundsItems(const ASpec: TTyAxisLayoutSpec;
  const ARaw: TTyRectF; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyBoundsItemArray;
var
  places: TTyAxisLabelPlacementArray;
  i, n: Integer;
  w, h, padH, padV: Double;
  horiz: Boolean;
begin
  Result := nil;
  if (AMeasurer = nil) or (not ASpec.ShowLabels) then Exit;
  { THE LABELS THE ESTIMATE SHOWS: thinned on the raw rect, the hidden ends
    left out -- upstream measures the survivors and nothing else }
  places := TyLayoutAxisLabels(ASpec, ARaw, AMeasurer, APPI);
  padH := AxisScaleF(ASpec.TextMarginHLogical, APPI);
  padV := AxisScaleF(ASpec.TextMarginVLogical, APPI);
  horiz := AxisIsHorizontal(ASpec.Side);
  SetLength(Result, Length(places));
  n := 0;
  for i := 0 to High(places) do
  begin
    if (not places[i].Shown) or (places[i].Text = '') then Continue;
    AMeasurer.MeasureLine(places[i].Text, ASpec.FontName,
      ASpec.FontSizeLogical, WeightAt(ASpec, i), w, h);
    Result[n].R := LabelBox(places[i].X, places[i].Y, w, h, padH, padV,
      ASpec.RotationRad, places[i].AnchorH, places[i].AnchorV);
    Result[n].AlongY := not horiz;
    { a y axis measures its proportion from the TOP, where the overflow the
      division applies to is the one below }
    Result[n].Proportion := NaN;
    if i <= High(ASpec.Proportions) then
    begin
      if horiz then Result[n].Proportion := ASpec.Proportions[i]
      else Result[n].Proportion := 1 - ASpec.Proportions[i];
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyAxisNameBoundsItem(const ASpec: TTyAxisLayoutSpec;
  const ARaw: TTyRectF; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  out AItem: TTyBoundsItem): Boolean;
var
  nw, nh, off, at, cx, cy: Double;
begin
  AItem := Default(TTyBoundsItem);
  Result := (ASpec.Name <> '') and (AMeasurer <> nil);
  if not Result then Exit;
  AMeasurer.MeasureLine(ASpec.Name, ASpec.FontName, ASpec.FontSizeLogical,
    ASpec.FontWeight, nw, nh);
  { WHERE THE PAINT PASS PUTS IT: the middle of the band the thickness sets
    aside for it, measured out from the axis line }
  off := (TyAxisThickness(ASpec, AMeasurer, APPI, obcAxisLabel)
    + TyAxisThickness(ASpec, AMeasurer, APPI, obcAll)) / 2;
  at := AxisScaleF(ASpec.OffsetLogical, APPI);
  case ASpec.Side of
    asBottom: begin cx := (ARaw.Left + ARaw.Right) / 2; cy := ARaw.Bottom + at + off; end;
    asTop: begin cx := (ARaw.Left + ARaw.Right) / 2; cy := ARaw.Top - at - off; end;
    asLeft: begin cy := (ARaw.Top + ARaw.Bottom) / 2; cx := ARaw.Left - at - off; end;
  else
    begin cy := (ARaw.Top + ARaw.Bottom) / 2; cx := ARaw.Right + at + off; end;
  end;
  if AxisIsHorizontal(ASpec.Side) then
    AItem.R := TyXYWH(cx - nw / 2, cy - nh / 2, nw, nh)
  else
    AItem.R := TyXYWH(cx - nh / 2, cy - nw / 2, nh, nw);
  AItem.AlongY := not AxisIsHorizontal(ASpec.Side);
  AItem.Proportion := 0.5;
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
  APPI: Integer): TTyRectF;
var
  items, one: TTyBoundsItemArray;
  name: TTyBoundsItem;
  i, k, n: Integer;
  r: TTyXYWH;
begin
  items := nil;
  n := 0;
  for i := 0 to High(AAxes) do
  begin
    one := TyAxisLabelBoundsItems(AAxes[i], ARaw, AMeasurer, APPI);
    SetLength(items, n + Length(one) + 1);
    for k := 0 to High(one) do
      items[n + k] := one[k];
    Inc(n, Length(one));
    { A hidden axis has lost its name in the builder, as it has its labels }
    if (AContain = obcAll)
      and TyAxisNameBoundsItem(AAxes[i], ARaw, AMeasurer, APPI, name) then
    begin
      items[n] := name;
      Inc(n);
    end;
  end;
  SetLength(items, n);
  r := TyXYWHOfRect(ARaw);
  TyShrinkRect(r, TyOuterBoundsMargin(AOuter, TyXYWHOfRect(ARaw), items),
    AClampW, AClampH);
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
      c := Abs(Cos(AAxes[i].RotationRad));
      uw := 0;
      uh := 0;
      any := False;
      k := 0;
      while k < n do
      begin
        AMeasurer.MeasureLine(AAxes[i].Labels[k], AAxes[i].FontName,
          AAxes[i].FontSizeLogical, AAxes[i].FontWeight, w, h);
        s := Sin(AAxes[i].RotationRad);
        rw := w * c + Abs(h * s);
        rh := w * Abs(s) + Abs(h * Cos(AAxes[i].RotationRad));
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

{ Does showing every AStep-th label leave every shown pair clear of its
  neighbour? Positions are fractions of the axis, ALength is the axis in px. }
function StepFits(const APositions: TTyDoubleArray; const AAlongEach: TTyDoubleArray;
  ALength, AMinGap: Double; AStep: Integer): Boolean;
var
  i, prev: Integer;
  cPrev, cCur, need: Double;
begin
  Result := True;
  prev := -1;
  i := 0;
  while i <= High(APositions) do
  begin
    if prev >= 0 then
    begin
      cPrev := APositions[prev] * ALength;
      cCur := APositions[i] * ALength;
      need := (AAlongEach[prev] + AAlongEach[i]) / 2 + AMinGap;
      if Abs(cCur - cPrev) < need then
        Exit(False);
    end;
    prev := i;
    Inc(i, AStep);
  end;
end;

function TyAxisLabelStep(const ASpec: TTyAxisLayoutSpec; const APlot: TTyRectF;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): Integer;
var
  across, along, len, minGap: Double;
  each: TTyDoubleArray;
  n, step: Integer;
begin
  Result := 1;
  { An axis that says so is never thinned by index. }
  if ASpec.KeepEveryLabel then Exit;
  { AND AN AUTHOR WHO NAMED A STRIDE GETS IT, measured or not. `interval` is
    not a hint: `interval: 0` on a crowded axis means `draw them all and let
    them collide`, which is a thing people write on purpose and which no
    value the measured rule can return expresses.

    BEFORE the measuring, and that placement is cost rather than answer:
    mutation testing moved this line below MeasureLabels and every reading
    stayed identical, because measuring changes nothing but the locals. It
    stays here because an axis of five thousand categories that was told what
    to do should not measure five thousand strings to be told again. }
  if ASpec.ForcedLabelStep > 0 then Exit(ASpec.ForcedLabelStep);
  MeasureLabels(ASpec, AMeasurer, across, along, each);
  n := Length(each);
  if n < 2 then Exit;
  if AxisIsHorizontal(ASpec.Side) then
    len := TyRectFWidth(APlot)
  else
    len := TyRectFHeight(APlot);
  if len <= 0 then Exit;
  minGap := AxisScaleF(4, APPI);
  { A UNIFORM step, not a greedy keep-if-it-fits. Greedy leaves the kept labels
    unevenly spaced, which on a category axis reads as missing data rather than
    as thinning. This is also what axisLabel.interval:'auto' means in ECharts. }
  for step := 1 to n - 1 do
    if StepFits(ASpec.Positions, each, len, minGap, step) then
      Exit(step);
  { Stop ONE SHORT of n and state the terminal case outright. At step = n the
    shown indices are 0, n, 2n... and the last label is n-1, so only the first
    is ever shown and StepFits can never fail -- which would make this line
    unreachable if the loop ran to n, and unreachable code that looks like a
    safety net is worse than none. Written this way it is the answer, not a
    fallback: an axis with no labels at all looks broken, and one still tells
    the reader what the axis counts in. }
  Result := n;
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
  i, step: Integer;
  endShown: Boolean;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  gap, len, base: Double;
begin
  Result := nil;
  SetLength(Result, Length(ASpec.Labels));
  if Length(ASpec.Labels) = 0 then Exit;
  step := TyAxisLabelStep(ASpec, APlot, AMeasurer, APPI);
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
    { HIDDEN IS NOT THE SAME AS THINNED. A thinned label was crowded out and
      the ones around it stand where they always did; a hidden one was never
      going to be drawn, yet it keeps its place in every parallel array so
      that the indices still line up with the ticks. }
    if EndLabelDecides(ASpec, i, Length(ASpec.Labels), endShown) then
      Result[i].Shown := ASpec.ShowLabels and endShown
                         and (not HiddenAt(ASpec, i))
    else
      Result[i].Shown := ASpec.ShowLabels and (i mod step = 0)
                         and (not HiddenAt(ASpec, i));
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
end;

end.
