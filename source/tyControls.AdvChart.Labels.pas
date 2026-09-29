unit tyControls.AdvChart.Labels;
{$mode objfpc}{$H+}
{ Text on a mark: where it goes, what it says, and what colour it comes out.

  A LABEL IS DECLARED ON ITS MARK AND EXPANDED INTO ITS OWN PAINT ENTRY. The
  mark builder stamps a string onto the element it just made; this unit walks
  the finished list and turns each stamped string into a SECOND entry carrying
  the same datum. Two entries, one author.

  WHY NOT ONE ENTRY WITH BOTH. Because the element's shape would then no longer
  describe its ink. A pie slice with an outside label 50 px past the rim would
  have to grow its bounds by a hundred pixels, and TyShapeContains would answer
  yes across the whole empty wedge between the arc and the caption -- which is
  precisely the "pointer answering for ink that is not there" that the shape
  layer's own header exists to prevent.

  WHY NOT A SECOND LIST. Because the datum would then live in two structures
  ordered by two different rules, and hovering a bar could report a different
  row from hovering its own caption. One list, one order, one answer.

  WHY THE TEXT IS NOT A SHAPE KIND. AdvChart.Shape deliberately imports no
  measurer -- it is the pure hit-test layer, and TyShapeBounds has to be able to
  answer from the record alone. A text kind would make it answer a question it
  cannot compute. The caption therefore rides on the ELEMENT, where resolved ink
  already lives, and the entry this unit emits carries a plain rect that the
  shape layer understands completely.

  A MARK STAMPS ONLY THE WORDS. Everything else about a label is the same for
  every datum in a series, so the spec lives once per series and a mark carries
  only what differs. A scatter series makes one element per point, and a
  per-element copy of the spec would be a hundred bytes a point for values that
  never vary.

  PORTED FROM zrender/src/contain/text.ts (calculateTextPosition) and
  echarts/src/label/labelStyle.ts, 6.1.0.

  WHAT IS NOT HERE, deliberately:
    - the PIE's labels. pie/labelLayout computes x, y and rotation itself, so
      the thirteen positions below do not apply. It is a different algorithm
      and it gets its own pass.

      AND `distance` IS INERT THERE WHILE `offset` IS NOT, which took an
      audit to notice -- an earlier version of this note said both were. The
      two die by different mechanisms and only one of them dies: PieView
      resets `position` and `rotation` only, and setTextConfig EXTENDS rather
      than replaces, so both survive into zrender. `distance` is then read
      only INSIDE the `has a position` gate, which a null position closes;
      `offset` is applied outside it, unconditionally.
    - the nine SECTOR positions. They serve polar bars, which this port has no
      renderer for; building them now would be a table nothing reads.
    - de-collision. Upstream can hide a label that overlaps another; this
      cannot, and will draw them on top of each other where ECharts hides one.

  PURE: SysUtils, Math and the AdvChart units. Fonts and colours arrive
  resolved; text is measured through the injected measurer. }
interface
uses
  SysUtils, Math,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint;

type
  { The thirteen built-in positions, plus the two forms that are not one of
    them.

    tlpNone is "no label". tlpAt is the ARRAY form -- an offset from the host's
    top-left corner, where the two numbers are percentages of the HOST'S OWN
    width and height, resolved to px before they get here. }
  TTyLabelPosition = (tlpNone,
    tlpLeft, tlpRight, tlpTop, tlpBottom,
    tlpInside, tlpInsideLeft, tlpInsideRight, tlpInsideTop, tlpInsideBottom,
    tlpInsideTopLeft, tlpInsideTopRight, tlpInsideBottomLeft,
    tlpInsideBottomRight,
    tlpAt);

  { How a label that does not fit is dealt with. }
  TTyLabelOverflow = (tloNone, tloTruncate);

  { What a label says when no formatter asked for anything else.

    IT IS NOT THE SAME FOR EVERY SERIES. A bar, a line and a scatter point
    show their VALUE; a pie slice shows its NAME. One default for all of them
    renders every unformatted pie label as a number. }
  TTyLabelDefaultText = (tldValue, tldName,
    { a heatmap cell's: the THIRD element of the raw item as written, else
      '-' (HeatmapView.ts:313-317) [Batch 68] }
    tldRawThird);

  { Everything about one series' labels except the words.

    THE THREE INSIDE COLOURS ARE A BAND TABLE, not a light/dark pair. Upstream
    picks by the host fill's luminance: above 0.5 the dark ink, above 0.2 the
    LIGHTEST one, and below that the dimmer light one -- which reads backwards
    until you see why. On a mid-dark fill you want maximum contrast; on a nearly
    black one the brightest ink glares, and the dimmer one is easier to read.
    Two bands would collapse that and get the dark end wrong. }
  TTyLabelSpec = record
    Show: Boolean;
    Position: TTyLabelPosition;
    { `position: 'outside'`, which is not a position but a request for the
      mark's own: Position then holds tlpTop, the answer for a mark that has
      none, and a mark with an outside side (a bar) answers per datum. }
    Outside: Boolean;
    { tlpAt only: from the host's top-left, a FRACTION of the host's width /
      height when AtXIsPercent / AtYIsPercent, else LOGICAL px. [Batch 68:
      they were device px, and a '30%' became 0.3 px.] }
    AtX, AtY: Double;
    AtXIsPercent, AtYIsPercent: Boolean;
    { LOGICAL px. The gap outside, or the inset inside, depending on the
      position -- and unused entirely by tlpInside, which is the default, so a
      chart that sets only `distance` sees nothing happen. }
    DistanceLogical: Double;
    { LOGICAL px, added after the position is resolved. Upstream applies it
      inside the rotation; this applies it after, and says so below. }
    OffsetXLogical, OffsetYLogical: Double;
    RotationRad: Double;
    { `align` / `verticalAlign` (or `baseline`) as written, over the ones the
      position implies -- normalised as zrender does: 'middle' is centre,
      'center' is middle, anything else left / top [Batch 68] }
    HasAlignH, HasAlignV: Boolean;
    AlignH: TTyTextAnchorH;
    AlignV: TTyTextAnchorV;
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    { When False the ink is Colour. When True it is chosen from the host's own
      fill, the way an unset label.color is. }
    AutoColour: Boolean;
    Colour: TTyChartColor;
    { `color: inherit` -- the caption takes the mark's OWN fill rather than a
      contrast ink. Kept apart from Colour because the fill is not known
      until the expansion pass has the host in hand. }
    InheritColour: Boolean;
    { Bands 0..2: the ink for a light host, a mid host and a dark host. }
    InsideColour: array[0..2] of TTyChartColor;
    { THE GROUND the chart is drawn on, and whether it counts as dark
      (luminance under 0.4). An outside label's halo is the ground; an inside
      one's halo is its host's fill, and only when the ink is the band that
      reads against that ground. }
    Ground: TTyChartColor;
    GroundDark: Boolean;
    { `textBorderColor`: written, `none`/`transparent`, or `inherit`. }
    HasBorderColour, BorderColourNone, BorderColourInherit: Boolean;
    BorderColour: TTyChartColor;
    { `textBorderWidth`, LOGICAL px. }
    HasBorderWidth: Boolean;
    BorderWidthLogical: Double;
    { A label with its own `backgroundColor` gets no automatic halo. }
    HasBackground: Boolean;
    { A FUNNEL'S `inherit`, which upstream does not route through
      inheritColor: inside it keeps the band ink and is FORCED a stroke in
      the band's fill; outside it is the host's colour over the ground halo. }
    FunnelInherit: Boolean;
    { `emphasis.label.color` and `.textBorderWidth`: the hover's own. }
    EmphHasColour: Boolean;
    EmphColour: TTyChartColor;
    EmphHasBorderWidth: Boolean;
    EmphBorderWidthLogical: Double;
    { `emphasis.itemStyle.color`: the hovered host's fill, when written;
      otherwise it is the normal fill lifted. }
    EmphHostHasColour: Boolean;
    EmphHostColour: TTyChartColor;
    { What an OUTSIDE label is drawn in when the colour is automatic: the
      theme's own ink rather than anything derived from the mark. }
    OutsideColour: TTyChartColor;
    Overflow: TTyLabelOverflow;
    { The template, as written. HasFormatter says one was written at all: an
      EMPTY template is an empty label, as upstream's is, and only no template
      -- or null -- means the default text for the type. }
    Formatter: string;
    HasFormatter: Boolean;
    DefaultText: TTyLabelDefaultText;
    { Painted over its mark. Z2 one above the host so a caption is never
      swallowed by the thing it names. }
    Z2Lift: Integer;
  end;
  TTyLabelSpecArray = array of TTyLabelSpec;
  TTyLabelSpecTable = array of TTyLabelSpecArray;

{ A spec that draws nothing. }
function TyLabelSpecNone: TTyLabelSpec;

{ The position named, or tlpNone when the string is not one of the thirteen.

  NOT tlpInside FOR AN UNKNOWN NAME. zrender's switch has no default case, so an
  unrecognised position leaves x and y at the host rect's TOP-LEFT with the text
  hanging down and right from it. That is a different picture from `inside`, and
  a port that quietly substituted the default would hide a typo that upstream
  shows. AKnown says which happened. }
function TyLabelPositionOf(const AName: string; out AKnown: Boolean): TTyLabelPosition;

{ Where one caption hangs off one host rect, and which of its own edges is
  pinned there.

  BOTH ANSWERS ARE NEEDED and they are not the same question. `top` puts the
  anchor above the rect AND pins the caption's BOTTOM edge to it; that pairing
  is what turns `distance` into a visible gap rather than an overlap. Get the
  anchor right and the alignment wrong and every outside label sits on top of
  the mark it names.

  ADistancePx is DEVICE px by the time it arrives. }
procedure TyLabelAnchor(const AHost: TTyRectF; APosition: TTyLabelPosition;
  ADistancePx, AAtX, AAtY: Double;
  out AX, AY: Double; out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);

{ Whether a position puts the caption over its host. Upstream decides this by
  asking whether the position's NAME contains "inside" -- a substring test on a
  string, not a property of the geometry -- so `insideTopLeft` counts and
  `center` does not. Transcribed as the same set rather than re-derived, because
  re-deriving it from the geometry would put `inside` and `at` in the same
  bucket and they are not. }
function TyLabelIsInside(APosition: TTyLabelPosition): Boolean;

{ Relative luminance the way zrender computes it, 0..1.

  ALPHA BLENDS TOWARD BLACK, not toward white -- the call site that picks a
  label's ink passes a background luminance of zero. So a half-transparent fill
  reads as DARKER than its colour suggests and gets lighter ink. The comment
  beside upstream's own formula says "assumed white background" and is wrong for
  this call; it is right for the two dark-mode calls, which pass one. }
{ A W x H BOX HUNG OFF ONE POINT, given which of its own edges is pinned
  there.

  Exported because it had been written out longhand in seven places by the time
  an eighth wanted it, and because the pairing is the contract everything
  downstream reads: an anchor alone does not say where the words go. }
function TyAnchorBox(AX, AY, AW, AH: Double; AAnchorH: TTyTextAnchorH;
  AAnchorV: TTyTextAnchorV): TTyRectF;

function TyLabelLuminance(AColour: TTyChartColor): Double;

{ The ink an automatic label comes out in, given the host's own fill. }
function TyLabelAutoColour(const ASpec: TTyLabelSpec; AHostFill: TTyChartColor;
  AHostHasFill, AInside: Boolean): TTyChartColor;

{ Which of the three inside inks a host's fill takes: 0 over a light fill
  (luminance above a half), 1 over a mid one (above a fifth), 2 over a dark
  one -- and 2 over a gradient, which has no one colour to measure. }
function TyLabelInkBand(AHostFill: TTyChartColor; AHostGradient: Boolean): Integer;

{ THE WHOLE ANSWER for one caption: its ink, and its halo's colour and
  LOGICAL width (0 for none). zrender's rule: a label is inside only over a
  host that HAS a fill; inside, the ink is the band's and the halo is the
  host's own fill -- only when the band is the one that reads against the
  ground (a dark ground halos the light band, a light ground the others) and
  never over a gradient; outside, the ink is the theme's and the halo is the
  ground. A literal or inherited colour has no automatic halo;
  `textBorderColor` with a width draws its own; a label background has none.
  Two logical pixels unless `textBorderWidth` says more. }
procedure TyLabelInk(const ASpec: TTyLabelSpec; AHostFill: TTyChartColor;
  AHostHasFill, AHostGradient, AInside: Boolean;
  out AInk, AStroke: TTyChartColor; out AStrokeWidthLogical: Double);

{ Work out the hover's ink and halo for a caption now, from the host's fill
  as a hover leaves it, and stamp them on ACaption (HasEmph). }
procedure TyLabelStampEmphasis(const ASpec: TTyLabelSpec;
  AHostFill: TTyChartColor; AHostHasFill, AHostGradient, AInside: Boolean;
  var ACaption: TTyElementCaption);

{ THE SAME UNDER A HOVER: the host's fill is the lifted one, and
  `emphasis.label.color` / `.textBorderWidth` override. }
procedure TyLabelInkEmphasis(const ASpec: TTyLabelSpec; AHostFill: TTyChartColor;
  AHostHasFill, AHostGradient, AInside: Boolean;
  out AInk, AStroke: TTyChartColor; out AStrokeWidthLogical: Double);

{ Turn every stamped caption in AList into a second entry carrying the same
  datum.

  RUNS ONCE, IMMEDIATELY BEFORE RENDERING, and nothing may be appended after it.
  The companion's geometry is frozen from its host at expansion time and the
  list has no update path, so a host moved afterwards would leave its caption
  behind.

  ASpecs is indexed by SERIES index -- an element whose datum names a series
  outside the array, or whose series draws no labels, is left alone. }
procedure TyExpandLabels(AList: TTyPaintList; const ASpecs: TTyLabelSpecArray;
  const AMeasurer: ITyTextMeasurer; APPI: Integer); overload;
{ AItemSpecs[series][raw row]: a data item's own label read over its
  series', for a caption whose ItemSpec names it [Batch 68] }
procedure TyExpandLabels(AList: TTyPaintList; const ASpecs: TTyLabelSpecArray;
  const AItemSpecs: TTyLabelSpecTable; const AMeasurer: ITyTextMeasurer;
  APPI: Integer); overload;

implementation

uses tyControls.AdvChart.Style;

procedure TyLabelStampEmphasis(const ASpec: TTyLabelSpec;
  AHostFill: TTyChartColor; AHostHasFill, AHostGradient, AInside: Boolean;
  var ACaption: TTyElementCaption);
var fill: TTyChartColor; grad: Boolean;
begin
  fill := AHostFill;
  grad := AHostGradient;
  if ASpec.EmphHostHasColour then
  begin
    fill := ASpec.EmphHostColour;
    grad := False;
  end
  else if AHostHasFill and not grad then
    fill := TyChartLiftColor(fill);
  TyLabelInkEmphasis(ASpec, fill, AHostHasFill, grad, AInside,
    ACaption.EmphColour, ACaption.EmphStrokeColour,
    ACaption.EmphStrokeWidthLogical);
  ACaption.HasEmph := True;
end;

function TyLabelSpecNone: TTyLabelSpec;
var i: Integer;
begin
  Result := Default(TTyLabelSpec);
  Result.Show := False;
  Result.Position := tlpInside;
  Result.DistanceLogical := 5;
  Result.FontSizeLogical := 9;
  Result.FontWeight := 400;
  Result.AutoColour := True;
  Result.Colour := 0;
  for i := 0 to 2 do Result.InsideColour[i] := 0;
  Result.OutsideColour := 0;
  Result.Overflow := tloNone;
  Result.Formatter := '';
  Result.DefaultText := tldValue;
  Result.Z2Lift := 1;
end;

function TyLabelPositionOf(const AName: string; out AKnown: Boolean): TTyLabelPosition;
begin
  AKnown := True;
  if AName = 'left' then Exit(tlpLeft);
  if AName = 'right' then Exit(tlpRight);
  if AName = 'top' then Exit(tlpTop);
  if AName = 'bottom' then Exit(tlpBottom);
  if AName = 'inside' then Exit(tlpInside);
  if AName = 'insideLeft' then Exit(tlpInsideLeft);
  if AName = 'insideRight' then Exit(tlpInsideRight);
  if AName = 'insideTop' then Exit(tlpInsideTop);
  if AName = 'insideBottom' then Exit(tlpInsideBottom);
  if AName = 'insideTopLeft' then Exit(tlpInsideTopLeft);
  if AName = 'insideTopRight' then Exit(tlpInsideTopRight);
  if AName = 'insideBottomLeft' then Exit(tlpInsideBottomLeft);
  if AName = 'insideBottomRight' then Exit(tlpInsideBottomRight);
  AKnown := False;
  Result := tlpNone;
end;

function TyLabelIsInside(APosition: TTyLabelPosition): Boolean;
begin
  Result := APosition in [tlpInside, tlpInsideLeft, tlpInsideRight,
    tlpInsideTop, tlpInsideBottom, tlpInsideTopLeft, tlpInsideTopRight,
    tlpInsideBottomLeft, tlpInsideBottomRight];
end;

procedure TyLabelAnchor(const AHost: TTyRectF; APosition: TTyLabelPosition;
  ADistancePx, AAtX, AAtY: Double;
  out AX, AY: Double; out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
var
  x0, y0, w, h, halfH: Double;
begin
  x0 := AHost.Left;
  y0 := AHost.Top;
  w := TyRectFWidth(AHost);
  h := TyRectFHeight(AHost);
  { NAMED, because upstream names it and uses it five times -- while the
    horizontal half is written out inline every time. Kept the same way so the
    two tables read against the source line by line. }
  halfH := h / 2;

  { THE TOP-LEFT IS THE FALLTHROUGH, not the default position. zrender's switch
    has no default case, so an unrecognised name leaves these initialisers
    standing. tlpNone reaches here only from a caller that asked for it. }
  AX := x0;
  AY := y0;
  AH := tahLeft;
  AV := tavTop;

  case APosition of
    tlpLeft:
      begin
        AX := x0 - ADistancePx; AY := y0 + halfH;
        AH := tahRight; AV := tavMiddle;
      end;
    tlpRight:
      begin
        AX := x0 + ADistancePx + w; AY := y0 + halfH;
        AV := tavMiddle;
      end;
    tlpTop:
      begin
        AX := x0 + w / 2; AY := y0 - ADistancePx;
        AH := tahCentre; AV := tavBottom;
      end;
    tlpBottom:
      begin
        AX := x0 + w / 2; AY := y0 + h + ADistancePx;
        AH := tahCentre;
      end;
    tlpInside:
      begin
        { NO DISTANCE TERM, and it is the default position -- so a chart that
          sets only `distance` and leaves `position` alone sees nothing move. }
        AX := x0 + w / 2; AY := y0 + halfH;
        AH := tahCentre; AV := tavMiddle;
      end;
    tlpInsideLeft:
      begin
        AX := x0 + ADistancePx; AY := y0 + halfH;
        AV := tavMiddle;
      end;
    tlpInsideRight:
      begin
        AX := x0 + w - ADistancePx; AY := y0 + halfH;
        AH := tahRight; AV := tavMiddle;
      end;
    tlpInsideTop:
      begin
        AX := x0 + w / 2; AY := y0 + ADistancePx;
        AH := tahCentre;
      end;
    tlpInsideBottom:
      begin
        AX := x0 + w / 2; AY := y0 + h - ADistancePx;
        AH := tahCentre; AV := tavBottom;
      end;
    tlpInsideTopLeft:
      begin
        AX := x0 + ADistancePx; AY := y0 + ADistancePx;
      end;
    tlpInsideTopRight:
      begin
        AX := x0 + w - ADistancePx; AY := y0 + ADistancePx;
        AH := tahRight;
      end;
    tlpInsideBottomLeft:
      begin
        AX := x0 + ADistancePx; AY := y0 + h - ADistancePx;
        AV := tavBottom;
      end;
    tlpInsideBottomRight:
      begin
        AX := x0 + w - ADistancePx; AY := y0 + h - ADistancePx;
        AH := tahRight; AV := tavBottom;
      end;
    tlpAt:
      begin
        { THE ARRAY FORM PINS THE CAPTION'S TOP-LEFT, which is the one thing
          about it that surprises people: ['50%','50%'] lands the anchor in the
          middle of the host like `inside` does, and then hangs the text down
          and to the right of that point instead of centring it. Upstream sets
          both alignments to null here on purpose, and null resolves to
          left/top. }
        AX := x0 + AAtX;
        AY := y0 + AAtY;
      end;
  end;
end;

function TyAnchorBox(AX, AY, AW, AH: Double; AAnchorH: TTyTextAnchorH;
  AAnchorV: TTyTextAnchorV): TTyRectF;
begin
  case AAnchorH of
    tahCentre: Result.Left := AX - AW / 2;
    tahRight: Result.Left := AX - AW;
  else
    Result.Left := AX;
  end;
  Result.Right := Result.Left + AW;
  case AAnchorV of
    tavMiddle: Result.Top := AY - AH / 2;
    tavBottom: Result.Top := AY - AH;
  else
    Result.Top := AY;
  end;
  Result.Bottom := Result.Top + AH;
end;

function TyLabelLuminance(AColour: TTyChartColor): Double;
var
  a, r, g, b: Double;
begin
  a := ((AColour shr 24) and $FF) / 255;
  r := (AColour shr 16) and $FF;
  g := (AColour shr 8) and $FF;
  b := AColour and $FF;
  { zrender's lum(), with a background luminance of zero: the alpha term is
    multiplied in and nothing is added back, so translucency darkens. }
  Result := (0.299 * r + 0.587 * g + 0.114 * b) * a / 255;
end;

function TyLabelAutoColour(const ASpec: TTyLabelSpec; AHostFill: TTyChartColor;
  AHostHasFill, AInside: Boolean): TTyChartColor;
var lum: Double;
begin
  { `inherit` first, because it is the one answer that is neither automatic
    nor a literal: the caption comes out in the mark's own colour, which is
    only legible where the caption is NOT over the mark. }
  if ASpec.InheritColour then Exit(AHostFill);
  if not ASpec.AutoColour then Exit(ASpec.Colour);
  { OUTSIDE is not derived from the mark at all -- upstream returns the theme's
    own ink, light or dark by mode, and never looks at what it is labelling. }
  if not AInside then Exit(ASpec.OutsideColour);
  { AN UNFILLED HOST MAKES THE LABEL AN OUTSIDE ONE: zrender tests
    `hasFill()` before it calls anything inside, so the caption takes the
    theme's outside ink and the ground's halo. [Revised in batch 47: it took
    the light band's ink.] }
  if not AHostHasFill then Exit(ASpec.OutsideColour);
  lum := TyLabelLuminance(AHostFill);
  if lum > 0.5 then Exit(ASpec.InsideColour[0]);
  if lum > 0.2 then Exit(ASpec.InsideColour[1]);
  Result := ASpec.InsideColour[2];
end;

function TyLabelInkBand(AHostFill: TTyChartColor; AHostGradient: Boolean): Integer;
var lum: Double;
begin
  if AHostGradient then Exit(2);
  lum := TyLabelLuminance(AHostFill);
  if lum > 0.5 then Result := 0
  else if lum > 0.2 then Result := 1
  else Result := 2;
end;

procedure TyLabelInk(const ASpec: TTyLabelSpec; AHostFill: TTyChartColor;
  AHostHasFill, AHostGradient, AInside: Boolean;
  out AInk, AStroke: TTyChartColor; out AStrokeWidthLogical: Double);
var
  inside, auto: Boolean;
  band: Integer;
  w: Double;
  ground: TTyChartColor;

  procedure Halo(AColour: TTyChartColor);
  begin
    { A STROKE THAT IS TRANSPARENT IS NONE -- zrender drops `transparent`
      before it paints. }
    if (AColour shr 24) = 0 then Exit;
    AStroke := AColour;
    AStrokeWidthLogical := w;
  end;

begin
  AStroke := 0;
  AStrokeWidthLogical := 0;
  inside := AInside and AHostHasFill;
  band := TyLabelInkBand(AHostFill, AHostGradient);
  { `textBorderWidth || 2`: a nought is two. }
  if ASpec.HasBorderWidth and (ASpec.BorderWidthLogical > 0) then
    w := ASpec.BorderWidthLogical
  else
    w := 2;
  { THE GROUND AS A HALO, made opaque. }
  ground := ASpec.Ground or $FF000000;

  auto := False;
  if ASpec.InheritColour and ASpec.FunnelInherit then
  begin
    if inside then AInk := ASpec.InsideColour[band] else AInk := AHostFill;
  end
  else if ASpec.InheritColour then AInk := AHostFill
  else if not ASpec.AutoColour then AInk := ASpec.Colour
  else
  begin
    auto := True;
    if inside then AInk := ASpec.InsideColour[band]
    else AInk := ASpec.OutsideColour;
  end;

  { A WRITTEN BORDER COLOUR IS ITS OWN STROKE, whatever the ink -- and with
    no width written it is a stroke of no width, which draws nothing. }
  if ASpec.HasBorderColour then
  begin
    if ASpec.BorderColourNone then Exit;
    if not (ASpec.HasBorderWidth and (ASpec.BorderWidthLogical > 0)) then Exit;
    if ASpec.BorderColourInherit then Halo(AHostFill)
    else Halo(ASpec.BorderColour);
    Exit;
  end;
  if ASpec.HasBackground then Exit;

  if ASpec.InheritColour and ASpec.FunnelInherit then
  begin
    { FORCED: the band's own fill, even over a light host. }
    if inside then
    begin
      if not AHostGradient then Halo(AHostFill);
    end
    else
      Halo(ground);
    Exit;
  end;
  if not auto then Exit;
  if inside then
  begin
    if AHostGradient then Exit;
    if ASpec.GroundDark <> (band = 0) then Exit;
    Halo(AHostFill);
  end
  else
    Halo(ground);
end;

procedure TyLabelInkEmphasis(const ASpec: TTyLabelSpec; AHostFill: TTyChartColor;
  AHostHasFill, AHostGradient, AInside: Boolean;
  out AInk, AStroke: TTyChartColor; out AStrokeWidthLogical: Double);
var s: TTyLabelSpec;
begin
  s := ASpec;
  if ASpec.EmphHasColour then
  begin
    s.AutoColour := False;
    s.InheritColour := False;
    s.FunnelInherit := False;
    s.Colour := ASpec.EmphColour;
  end;
  if ASpec.EmphHasBorderWidth then
  begin
    s.HasBorderWidth := True;
    s.BorderWidthLogical := ASpec.EmphBorderWidthLogical;
  end;
  TyLabelInk(s, AHostFill, AHostHasFill, AHostGradient, AInside, AInk, AStroke,
    AStrokeWidthLogical);
end;

procedure TyExpandLabels(AList: TTyPaintList; const ASpecs: TTyLabelSpecArray;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
begin
  TyExpandLabels(AList, ASpecs, nil, AMeasurer, APPI);
end;

procedure TyExpandLabels(AList: TTyPaintList; const ASpecs: TTyLabelSpecArray;
  const AItemSpecs: TTyLabelSpecTable; const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i, n, si: Integer;
  host, cap: TTyChartElement;
  spec: TTyLabelSpec;
  hostFill, ink, stroke: TTyChartColor;
  hostHasFill: Boolean;
  strokeW: Double;
  pos: TTyLabelPosition;
  bounds, box: TTyRectF;
  x, y, w, h, scale, dist, sw, atX, atY: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
begin
  if (AList = nil) or (AMeasurer = nil) then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  { THE COUNT IS TAKEN ONCE, and the local is documentation rather than the
    thing that makes it safe -- which is worth saying plainly, because the
    first version of this comment claimed otherwise and was wrong twice over.

    A companion DOES carry a caption (it is copied whole from its host), so a
    pass that re-read the length would expand its own output and never stop.
    What prevents that today is the LANGUAGE: a Pascal `for` evaluates its
    limit once, so `to AList.Count - 1` would behave identically. The local is
    a guard against a future rewrite into a `while i < AList.Count` loop, and
    a mutant that removes it therefore survives -- correctly. }
  n := AList.Count;
  for i := 0 to n - 1 do
  begin
    host := AList.Element(i);
    if host.Caption.Text = '' then Continue;
    si := host.Datum.SeriesIndex;
    if (si < 0) or (si > High(ASpecs)) then Continue;
    spec := ASpecs[si];
    { the item's own label, read over the series' }
    if (host.Caption.ItemSpec > 0) and (si <= High(AItemSpecs))
      and (host.Caption.ItemSpec - 1 <= High(AItemSpecs[si])) then
      spec := AItemSpecs[si][host.Caption.ItemSpec - 1];
    if not spec.Show then Continue;
    if spec.Position = tlpNone then Continue;

    bounds := TyShapeBounds(host.Shape);
    if not TyRectFIsValid(bounds) then Continue;
    { THE HOST'S STROKE GROWS ITS RECT, as Path.getBoundingRect grows it: by
      the line width, or by at least five where nothing is filled, half on
      each side. A label outside a bordered cell sits past the border.
      [Batch 68] }
    if (host.Style.StrokeWidthLogical > 0) and (host.Style.StrokeColor <> 0) then
    begin
      sw := host.Style.StrokeWidthLogical;
      if not host.Style.HasFill then sw := Max(sw, 5.0);
      sw := sw * scale;
      bounds.Left := bounds.Left - sw / 2;
      bounds.Top := bounds.Top - sw / 2;
      bounds.Right := bounds.Right + sw / 2;
      bounds.Bottom := bounds.Bottom + sw / 2;
    end;

    AMeasurer.MeasureLine(host.Caption.Text, spec.FontName,
      spec.FontSizeLogical, spec.FontWeight, w, h);
    if (w <= 0) or (h <= 0) then Continue;

    dist := spec.DistanceLogical * scale;
    { OUTSIDE IS DECIDED PER MARK: past whichever end the bar grows to. }
    pos := spec.Position;
    if spec.Outside then
      case host.Caption.Outside of
        coTop: pos := tlpTop;
        coBottom: pos := tlpBottom;
        coLeft: pos := tlpLeft;
        coRight: pos := tlpRight;
      end;
    { the array form against the host's own rect }
    if spec.AtXIsPercent then atX := spec.AtX * (bounds.Right - bounds.Left)
    else atX := spec.AtX * scale;
    if spec.AtYIsPercent then atY := spec.AtY * (bounds.Bottom - bounds.Top)
    else atY := spec.AtY * scale;
    TyLabelAnchor(bounds, pos, dist, atX, atY, x, y, ah, av);
    if spec.HasAlignH then ah := spec.AlignH;
    if spec.HasAlignV then av := spec.AlignV;
    { OFFSET AFTER THE POSITION, which is upstream's order. Upstream also
      applies it INSIDE the rotation, so a rotated label's offset runs along
      the rotated axes; this applies it in screen axes and says so, because the
      painter rotates around the anchor and has no separate origin to move. }
    x := x + spec.OffsetXLogical * scale;
    y := y + spec.OffsetYLogical * scale;

    { The box the caption occupies, from the anchor and the pinned edge. This
      is what the companion's shape IS -- so the hit test and the ink describe
      the same rectangle, which is the whole reason the caption gets an entry
      of its own rather than a note on somebody else's. }
    box := TyAnchorBox(x, y, w, h, ah, av);

    cap := TyChartElement(TyShapeRect(box));
    cap.Caption := host.Caption;
    { NO FILL AND NO STROKE. The rectangle is there so the pointer can find
      the words, not so anything is painted in it -- a filled one would draw a
      solid block behind every label. }
    { THE INK AND THE HALO, from the host's fill -- a pictorial bar's target
      counts as filled and transparent -- and from where the words ended up:
      a bar's `outside` is not inside. }
    hostFill := host.Style.FillColor;
    hostHasFill := host.Style.HasFill;
    if host.Caption.HostTransparent then
    begin
      hostFill := 0;
      hostHasFill := True;
    end;
    TyLabelInk(spec, hostFill, hostHasFill,
      host.Style.HasFill and (host.Style.FillGradient.Kind <> cgkNone),
      TyLabelIsInside(pos), ink, stroke, strokeW);
    cap.Caption.Colour := ink;
    cap.Caption.StrokeColour := stroke;
    cap.Caption.StrokeWidthLogical := strokeW;
    TyLabelStampEmphasis(spec, hostFill, hostHasFill,
      host.Style.HasFill and (host.Style.FillGradient.Kind <> cgkNone),
      TyLabelIsInside(pos), cap.Caption);
    cap.Style.Alpha := host.Style.Alpha;
    cap.Z := host.Z;
    { ABOVE ITS OWN MARK. Without the lift the two tie on (Z, Z2) and fall back
      to insertion order, which puts the caption on top anyway -- but only
      because it was appended later, and that is an accident rather than a
      rule. Saying it makes the ordering survive a future series `z`. }
    cap.Z2 := host.Z2 + spec.Z2Lift;
    { It answers for the same datum as the thing it names: hovering a bar's
      number has to report that bar. }
    cap.Silent := host.Silent;
    cap.Datum := host.Datum;
    cap.Caption.FontName := spec.FontName;
    cap.Caption.FontSizeLogical := spec.FontSizeLogical;
    cap.Caption.FontWeight := spec.FontWeight;
    cap.Caption.X := x;
    cap.Caption.Y := y;
    cap.Caption.AnchorH := ah;
    cap.Caption.AnchorV := av;
    cap.Caption.RotationRad := spec.RotationRad;
    cap.Caption.Truncate := spec.Overflow = tloTruncate;
    AList.Add(cap);
  end;
end;

end.
