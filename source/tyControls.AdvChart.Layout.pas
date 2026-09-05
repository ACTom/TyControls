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

  PURE: SysUtils, Math and the AdvChart units. No Controls, no Graphics, no
  handle. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Coord;

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

function TyFixedContainer(const ARect: TTyRectF): ITyBoxContainer;
function TyCoordCellContainer(const ACoordSys: ITyCoordSys;
  const AData: array of Double): ITyBoxContainer;

{ The one solver. Every component's rect comes from here. }
function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer): TTyRectF;

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
    LabelMarginLogical: Double;
    TickLengthLogical: Double;
    NameGapLogical: Double;
  end;

  { One laid-out label, ready to hand to TTyPainter.DrawTextRotated: the anchor
    plus how the box sits on it. Layout and paint therefore cannot disagree
    about where a label went. }
  TTyAxisLabelPlacement = record
    Index: Integer;
    Text: string;
    X, Y: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    Shown: Boolean;
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

{ Solve one axis. AStartV/AEndV are the near/far insets, ASizeV the extent. }
procedure SolveAxis(const AStartV, AEndV, ASizeV: TTyBoxValue;
  AContainerStart, AContainerExtent: Double; out AStart, AStop: Double);
var
  s, e, sz: Double;
begin
  s := ResolveValue(AStartV, AContainerExtent);
  e := ResolveValue(AEndV, AContainerExtent);
  sz := ResolveValue(ASizeV, AContainerExtent);

  if AStartV.Kind = buCentre then
  begin
    { Centre needs a size to centre. Without one it degenerates to the whole
      container, which is the only answer that is not a guess. }
    if IsNan(sz) then
    begin
      AStart := AContainerStart;
      AStop := AContainerStart + AContainerExtent;
      Exit;
    end;
    AStart := AContainerStart + (AContainerExtent - sz) / 2;
    AStop := AStart + sz;
    Exit;
  end;

  if (not IsNan(s)) and (not IsNan(sz)) then          { start + size }
  begin
    AStart := AContainerStart + s;
    AStop := AStart + sz;
  end
  else if (not IsNan(s)) and (not IsNan(e)) then      { start + end }
  begin
    AStart := AContainerStart + s;
    AStop := AContainerStart + AContainerExtent - e;
  end
  else if (not IsNan(e)) and (not IsNan(sz)) then     { end + size }
  begin
    AStop := AContainerStart + AContainerExtent - e;
    AStart := AStop - sz;
  end
  else if not IsNan(s) then                           { start only -> to the far edge }
  begin
    AStart := AContainerStart + s;
    AStop := AContainerStart + AContainerExtent;
  end
  else if not IsNan(e) then                           { end only -> from the near edge }
  begin
    AStart := AContainerStart;
    AStop := AContainerStart + AContainerExtent - e;
  end
  else if not IsNan(sz) then                          { size only -> at the near edge }
  begin
    AStart := AContainerStart;
    AStop := AStart + sz;
  end
  else                                                { nothing -> fill }
  begin
    AStart := AContainerStart;
    AStop := AContainerStart + AContainerExtent;
  end;

  { Over-constrained: collapse to zero at the near edge rather than invert. An
    inverted rect survives a later Min/Max swap and reappears as a phantom band
    somewhere else on screen, which is far harder to find than an empty one. }
  if AStop < AStart then
    AStop := AStart;
end;

function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer): TTyRectF;
var
  c: TTyRectF;
  l, r, t, b: Double;
begin
  if AContainer = nil then
    Exit(TyInvalidRectF);
  c := AContainer.ContainerRect;
  if not TyRectFIsValid(c) then
    Exit(TyInvalidRectF);
  SolveAxis(ASpec.Left, ASpec.Right, ASpec.Width, c.Left, TyRectFWidth(c), l, r);
  SolveAxis(ASpec.Top, ASpec.Bottom, ASpec.Height, c.Top, TyRectFHeight(c), t, b);
  Result := TyRectF(l, t, r, b);
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
    AMeasurer.MeasureLine(ASpec.Labels[i], ASpec.FontName,
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
  Result := AxisScaleF(ASpec.TickLengthLogical, APPI);
  MeasureLabels(ASpec, AMeasurer, across, along, each);
  if across > 0 then
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

function TyLayoutAxisLabels(const ASpec: TTyAxisLayoutSpec; const APlot: TTyRectF;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): TTyAxisLabelPlacementArray;
var
  i, step: Integer;
  gap, len, base: Double;
begin
  Result := nil;
  SetLength(Result, Length(ASpec.Labels));
  if Length(ASpec.Labels) = 0 then Exit;
  step := TyAxisLabelStep(ASpec, APlot, AMeasurer, APPI);
  gap := AxisScaleF(ASpec.TickLengthLogical, APPI)
       + AxisScaleF(ASpec.LabelMarginLogical, APPI);
  if AxisIsHorizontal(ASpec.Side) then
    len := TyRectFWidth(APlot)
  else
    len := TyRectFHeight(APlot);
  for i := 0 to High(ASpec.Labels) do
  begin
    Result[i].Index := i;
    Result[i].Text := ASpec.Labels[i];
    Result[i].Shown := ASpec.ShowLabels and (i mod step = 0);
    case ASpec.Side of
      asBottom:
        begin
          Result[i].X := APlot.Left + ASpec.Positions[i] * len;
          Result[i].Y := APlot.Bottom + gap;
          Result[i].AnchorH := tahCentre;
          Result[i].AnchorV := tavTop;
        end;
      asTop:
        begin
          Result[i].X := APlot.Left + ASpec.Positions[i] * len;
          Result[i].Y := APlot.Top - gap;
          Result[i].AnchorH := tahCentre;
          Result[i].AnchorV := tavBottom;
        end;
      asLeft:
        begin
          { A vertical axis' fractions run from its START, which is the BOTTOM --
            the same direction the coordinate system's y axis runs, so a label's
            fraction and its datum's fraction are the same number. }
          base := APlot.Bottom - ASpec.Positions[i] * len;
          Result[i].X := APlot.Left - gap;
          Result[i].Y := base;
          Result[i].AnchorH := tahRight;
          Result[i].AnchorV := tavMiddle;
        end;
      asRight:
        begin
          base := APlot.Bottom - ASpec.Positions[i] * len;
          Result[i].X := APlot.Right + gap;
          Result[i].Y := base;
          Result[i].AnchorH := tahLeft;
          Result[i].AnchorV := tavMiddle;
        end;
    end;
  end;
end;

end.
