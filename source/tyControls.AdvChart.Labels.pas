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
    - the PIE's labels. PieView throws the text config away and pie/labelLayout
      computes x, y and rotation itself, so `distance` and `offset` are inert
      there and the thirteen positions below do not apply. It is a different
      algorithm and it gets its own pass.
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
  TTyLabelDefaultText = (tldValue, tldName);

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
    { tlpAt only, DEVICE px from the host's top-left. }
    AtX, AtY: Double;
    { LOGICAL px. The gap outside, or the inset inside, depending on the
      position -- and unused entirely by tlpInside, which is the default, so a
      chart that sets only `distance` sees nothing happen. }
    DistanceLogical: Double;
    { LOGICAL px, added after the position is resolved. Upstream applies it
      inside the rotation; this applies it after, and says so below. }
    OffsetXLogical, OffsetYLogical: Double;
    RotationRad: Double;
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
    { What an OUTSIDE label is drawn in when the colour is automatic: the
      theme's own ink rather than anything derived from the mark. }
    OutsideColour: TTyChartColor;
    Overflow: TTyLabelOverflow;
    { The template, as written. Empty means the default text for the type. }
    Formatter: string;
    DefaultText: TTyLabelDefaultText;
    { Painted over its mark. Z2 one above the host so a caption is never
      swallowed by the thing it names. }
    Z2Lift: Integer;
  end;
  TTyLabelSpecArray = array of TTyLabelSpec;

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
function TyLabelLuminance(AColour: TTyChartColor): Double;

{ The ink an automatic label comes out in, given the host's own fill. }
function TyLabelAutoColour(const ASpec: TTyLabelSpec; AHostFill: TTyChartColor;
  AHostHasFill, AInside: Boolean): TTyChartColor;

{ Turn every stamped caption in AList into a second entry carrying the same
  datum.

  RUNS ONCE, IMMEDIATELY BEFORE RENDERING, and nothing may be appended after it.
  The companion's geometry is frozen from its host at expansion time and the
  list has no update path, so a host moved afterwards would leave its caption
  behind.

  ASpecs is indexed by SERIES index -- an element whose datum names a series
  outside the array, or whose series draws no labels, is left alone. }
procedure TyExpandLabels(AList: TTyPaintList; const ASpecs: TTyLabelSpecArray;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);

implementation

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
  { An unfilled host tells you nothing about what is behind the text, so it is
    treated as a light ground. Upstream's `pathFill !== 'none'` guard. }
  if not AHostHasFill then Exit(ASpec.InsideColour[0]);
  lum := TyLabelLuminance(AHostFill);
  if lum > 0.5 then Exit(ASpec.InsideColour[0]);
  if lum > 0.2 then Exit(ASpec.InsideColour[1]);
  Result := ASpec.InsideColour[2];
end;

procedure TyExpandLabels(AList: TTyPaintList; const ASpecs: TTyLabelSpecArray;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
var
  i, n, si: Integer;
  host, cap: TTyChartElement;
  spec: TTyLabelSpec;
  bounds, box: TTyRectF;
  x, y, w, h, scale, dist: Double;
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
    if not spec.Show then Continue;
    if spec.Position = tlpNone then Continue;

    bounds := TyShapeBounds(host.Shape);
    if not TyRectFIsValid(bounds) then Continue;

    AMeasurer.MeasureLine(host.Caption.Text, spec.FontName,
      spec.FontSizeLogical, spec.FontWeight, w, h);
    if (w <= 0) or (h <= 0) then Continue;

    dist := spec.DistanceLogical * scale;
    TyLabelAnchor(bounds, spec.Position, dist, spec.AtX, spec.AtY, x, y, ah, av);
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
    case ah of
      tahCentre: box.Left := x - w / 2;
      tahRight: box.Left := x - w;
    else
      box.Left := x;
    end;
    box.Right := box.Left + w;
    case av of
      tavMiddle: box.Top := y - h / 2;
      tavBottom: box.Top := y - h;
    else
      box.Top := y;
    end;
    box.Bottom := box.Top + h;

    cap := TyChartElement(TyShapeRect(box));
    cap.Caption := host.Caption;
    { NO FILL AND NO STROKE. The rectangle is there so the pointer can find
      the words, not so anything is painted in it -- a filled one would draw a
      solid block behind every label. }
    cap.Caption.Colour := TyLabelAutoColour(spec, host.Style.FillColor,
      host.Style.HasFill, TyLabelIsInside(spec.Position));
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
