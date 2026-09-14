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

  Shaped as v6's outerBounds rather than as the deprecated grid.containLabel:
    obmNone -- the rect given IS the plot band; labels may overflow outside it.
               (v5's default, containLabel:false.)
    obmAuto -- the rect given is the OUTER bound; the plot band is shrunk so the
               labels land inside it. (v6's default, ~ containLabel:true.)

  THE TWO PHASES DO NOT ITERATE, on purpose. An axis' thickness is the largest
  extent its labels reach PERPENDICULAR to it. Shrinking the plot shortens the
  axis, which can force more thinning -- but thinning changes how MANY labels
  show, not how big each one is, so the thickness is unchanged and a second pass
  would compute the same number. The one case that escapes it is the widest label
  happening to be one of the thinned-out ones; ECharts does not chase that either.

  NOT DONE HERE, deliberately: nameMoveOverlap (v6's shuffle when an axis name
  collides with the end label). That is its own feature, not part of the pass. }

type
  { TTyAxisSide moved down to AdvChart.Types -- Coord needs it and Layout
    already uses Coord. Re-exported here so no caller has to change its uses. }
  TTyAxisSide = tyControls.AdvChart.Types.TTyAxisSide;
  TTyOuterBoundsMode = (obmNone, obmAuto);
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

      LabelStep is 1 when nothing is thinned. Placements is empty when the axis
      was laid out without a plot rect to place into, and the renderer falls
      back to its own arithmetic then. }
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
  end;
  TTyAxisLayoutSpecArray = array of TTyAxisLayoutSpec;
  PTyAxisLayoutSpec = ^TTyAxisLayoutSpec;


{ Logical px -> device px for axis geometry. Exported because the builder
  scales axisLabel.width the same way, and a second copy of this rule is how two
  layers start disagreeing about what a pixel is. }
function AxisScaleF(ALogical: Double; APPI: Integer): Double;

{ Phase 1. How much room this axis needs on its own side, DEVICE px. }
function TyAxisThickness(const ASpec: TTyAxisLayoutSpec;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AContain: TTyOuterBoundsContain): Double;

{ Phase 2. Shrink the container by every axis' thickness to get the plot band.
  Under obmNone this returns AContainer unchanged -- the axes are still measured
  by the caller if it wants them, they just do not take space. }
function TySolveGrid(const AContainer: TTyRectF;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AMode: TTyOuterBoundsMode;
  AContain: TTyOuterBoundsContain = obcAxisLabel): TTyRectF;

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

function TySolveGrid(const AContainer: TTyRectF;
  const AAxes: TTyAxisLayoutSpecArray; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AMode: TTyOuterBoundsMode;
  AContain: TTyOuterBoundsContain): TTyRectF;
var
  i: Integer;
  t: Double;
  inset: array[TTyAxisSide] of Double;
  side: TTyAxisSide;
begin
  Result := AContainer;
  if AMode = obmNone then
    Exit;
  for side := Low(TTyAxisSide) to High(TTyAxisSide) do
    inset[side] := 0;
  { Several axes may share a side (a secondary y axis on the left). Each takes
    the space it needs, so the side's inset is the SUM, not the max. }
  for i := 0 to High(AAxes) do
  begin
    t := TyAxisThickness(AAxes[i], AMeasurer, APPI, AContain);
    inset[AAxes[i].Side] := inset[AAxes[i].Side] + t;
  end;
  Result.Left := AContainer.Left + inset[asLeft];
  Result.Right := AContainer.Right - inset[asRight];
  Result.Top := AContainer.Top + inset[asTop];
  Result.Bottom := AContainer.Bottom - inset[asBottom];
  { Over-constrained -- more axis furniture than container. Collapse rather than
    invert: an inverted plot rect survives a later Min/Max swap and reappears as
    a phantom band, which is far harder to find than an empty chart. }
  if Result.Right < Result.Left then
    Result.Right := Result.Left;
  if Result.Bottom < Result.Top then
    Result.Bottom := Result.Top;
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
  { THE TICK COUNTS ONLY WHEN IT IS IN THE WAY -- that is, when it points the
    same way the label does. An outward tick under an INSIDE label is on the
    other side of the axis line entirely and standing the label clear of it
    would push it a tick-length too far into the plot. }
  if ASpec.ShowTicks and (ASpec.TickInside = ASpec.LabelInside) then
    gap := gap + Max(Double(0), AxisScaleF(ASpec.TickLengthLogical, APPI));
  if ASpec.LabelInside then gap := -gap;
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
