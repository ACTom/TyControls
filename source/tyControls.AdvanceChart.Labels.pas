unit tyControls.AdvanceChart.Labels;
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

  WHY THE TEXT IS NOT A SHAPE KIND. AdvanceChart.Shape deliberately imports no
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
      [Batch 113: the polar bars came, and their positions with them --
      AdvanceChart.PolarBar works the anchor and the turn out on the sector and
      hands them over on the caption (SecHas); the offset, the style's
      alignment and the ink still run here.]
    - de-collision. That is the label layout's (AdvanceChart.LabelLayout,
      [Batch 103]), which runs over the captions this pass makes: each one
      carries what LabelManager keeps (its host, the anchor before the
      offset, the offset, the alignment its position implies and the one its
      style sets, the host's rect, the margins, the measured box).

  PURE: SysUtils, Math and the AdvanceChart units. Fonts and colours arrive
  resolved; text is measured through the injected measurer. }
interface
uses
  SysUtils, Math,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape,
  tyControls.AdvanceChart.Paint;

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

  { [R6-A] ONE STATE'S textConfig AS ITS LABEL MODEL WRITES IT:
    createTextConfig(stateModel, opt, isNotNormal) -- only the keys the
    state's label (a data item's over the series') writes: a truthy
    `position` ('outside' the host's own outside side, the array form
    against the host's box), `distance`, `offset`, `rotate` (radians).
    zrender lays the label out by the normal textConfig extended by the
    states' when they are entered (Element._applyStateObj). }
  TTyLabelStateCfg = record
    HasPosition: Boolean;
    Position: TTyLabelPosition;
    Outside: Boolean;
    AtX, AtY: Double;
    AtXIsPercent, AtYIsPercent: Boolean;
    HasDistance: Boolean;
    DistanceLogical: Double;
    HasOffset: Boolean;
    OffsetXLogical, OffsetYLogical: Double;
    HasRotation: Boolean;
    RotationRad: Double;
    { the position's word as written (a polar bar's sector positions --
      start, insideEnd ... -- are no zrender name) }
    HasPosWord: Boolean;
    PosWord: string;
  end;

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
    { [R7-Y] the font zrender joins from it (makeFont) is one the canvas
      refuses -- a fontStyle / fontWeight that is no CSS word, a fontSize
      string with a unit that is no length: the text is drawn in the font
      the canvas had (TyCanvasRunStep) }
    FontLeft: Boolean;
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
    { [R7-AF] one written as a STRING: the string where it strokes (the
      TSpan's rect joins it to its width and height), and +Infinity, which
      the canvas refuses -- stroked at the width it had (BorderWidthLogical
      nought) }
    BorderWidthText: string;
    BorderWidthInf: Boolean;
    { [F4c] textBorderType as written ('' a solid halo) }
    BorderType: string;
    { [R2-F] textBorderDashOffset, LOGICAL px: the label's, else the global
      textStyle's (HasBorderDashOffset: written somewhere) }
    HasBorderDashOffset: Boolean;
    BorderDashOffset: Double;
    { A label with its own `backgroundColor` gets no automatic halo. }
    HasBackground: Boolean;
    { A FUNNEL'S `inherit`, which upstream does not route through
      inheritColor: inside it keeps the band ink and is FORCED a stroke in
      the band's fill; outside it is the host's colour over the ground halo. }
    FunnelInherit: Boolean;
    { `emphasis.label.color`, `.textBorderColor` and `.textBorderWidth`:
      the hover's own. }
    EmphHasColour: Boolean;
    EmphColour: TTyChartColor;
    { [R5-B] the series' emphasis.label as JSON text when it writes `rich`
      ('' when not): the hovered label is laid out again in its block --
      each rich style the emphasis names merged key by key over the normal
      one, zrender's Text state merge -- rather than only re-inked }
    EmphRtNode: string;
    { [R5-F] a DATA ITEM's own emphasis.label as JSON text, where it writes
      a key that lays the text out again (TyLabelEmphWantsBlock): over the
      series' (the item's emphasis model chains to the series') }
    EmphItemNode: string;
    { A STATE SHOWS WHAT THE NORMAL LABEL HIDES: `select.label.show`,
      `emphasis.label.show` or `blur.label.show` true on the series.
      zrender creates the label when any state shows it (needsCreateText) and
      leaves it ignored at rest; the state flips it. [Batch 88] }
    StateShow: Boolean;
    EmphHasBorderWidth: Boolean;
    EmphBorderWidthLogical: Double;
    EmphHasBorderColour, EmphBorderColourNone, EmphBorderColourInherit: Boolean;
    EmphBorderColour: TTyChartColor;
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
    { THE TEXT BLOCK: zrender's styles for the label -- its rich styles, its
      box, size and overflow -- resolved over RtChain, the label nodes this
      spec was read from (most specific first, kept as JSON text: a spec
      outlives the option it was read from). Rt.Needed False is the one-run
      caption; RtAny says some node of the chain asked for a block at all,
      which is when the chain is resolved. RtGlobal is the root's side.
      [Batch 86] }
    Rt: TTyRtBlockStyle;
    RtGlobal: TTyRtGlobal;
    RtChain: TTyStringArray;
    RtAny: Boolean;
    { `valueAnimation`, truthy, and `precision`: a number, or 'auto' / none
      (HasPrecision False). Only a bar counts its value (BarView's
      setLabelValueAnimation); every other series ignores the key.
      [Batch 92, AN4] }
    ValueAnim: Boolean;
    HasPrecision: Boolean;
    Precision: Double;
    { `minMargin` (MarginType 1: half of it on every side of the label's
      global rect) or `textMargin` (2: CSS order, round its own rect) --
      what the label layout grows a label by before it weighs an overlap.
      [top, right, bottom, left], LOGICAL px. [Batch 103] }
    MarginType: Integer;
    MarginLogical: array[0..3] of Double;
    { [R2-I1] `opacity`: the label's own (retrieve2 of its model's, the
      global textStyle's) -- over the host's style.opacity, which
      setLabelStyle hands over as defaultOpacity otherwise }
    HasOpacity: Boolean;
    Opacity: Double;
    { [R7-L] A VIEW THAT HANDS OVER NO defaultOpacity (sunburst, sankey,
      themeRiver): the label is 1 under it, whatever its host's opacity }
    NoHostOpacity: Boolean;
    { [R6-A] the states' textConfig, by TTyEmphTwin.State: emphasis, blur,
      select (TyTwinEmphasis..TyTwinSelect) }
    StateCfg: array[0..2] of TTyLabelStateCfg;
  end;
  TTyLabelSpecArray = array of TTyLabelSpec;
  TTyLabelSpecTable = array of TTyLabelSpecArray;

{ A spec that draws nothing. }
function TyLabelSpecNone: TTyLabelSpec;

{ [R6-A] WHAT A STATE'S TWIN IS LAID OUT FROM: the spec (a label layout's
  font, size and alignment over it), the normal textConfig (the layout's
  offset and turn in it), the host and the caption it is a twin of, the rect
  the label hangs on, its plain box, the host's fill; where it stands when
  no position is (a fixed anchor's, a layout's x / y) and the style's
  alignment over the position's; TurnAboutBox: turned about the box's centre
  (textConfig origin 'center', a radial tree's) }
type
  TTyLabelTwinIn = record
    Spec: TTyLabelSpec;
    Normal: TTyLabelStateCfg;
    Host: TTyChartElement;
    Base: TTyElementCaption;
    Text: string;
    Bounds: TTyRectF;
    HBox: TTyXYWH;
    HasBox: Boolean;
    W, H, Scale: Double;
    HostFill: TTyChartColor;
    HostHasFill: Boolean;
    FreeX, FreeY: Double;
    FreeAH: TTyTextAnchorH;
    FreeAV: TTyTextAnchorV;
    FreeInside: Boolean;
    StyleHasAH, StyleHasAV: Boolean;
    StyleAH: TTyTextAnchorH;
    StyleAV: TTyTextAnchorV;
    TurnAboutBox: Boolean;
  end;

{ [R6-A] THE LABEL AS A STATE'S textConfig LAYS IT OUT (the twin ACode of
  AIn.Base): False where it lays out nothing }
function TyLabelLayTwin(const AIn: TTyLabelTwinIn; ACode: Byte;
  const AStates: TTyLabelStateCfg; const AMeasurer: ITyTextMeasurer;
  out ATwin: TTyEmphTwin): Boolean;

{ [R6-A] whether a state's textConfig writes any of its four keys }
function TyLabelStateCfgWrites(const ACfg: TTyLabelStateCfg): Boolean;
{ [R6-A] AOver's written keys over ABase's (zrender's extend of textConfig) }
function TyLabelStateCfgOver(const ABase, AOver: TTyLabelStateCfg): TTyLabelStateCfg;
{ [R6-A] the normal textConfig of a spec, every key written }
function TyLabelStateCfgNormal(const ASpec: TTyLabelSpec): TTyLabelStateCfg;
{ [R6-A] WHAT THE STATES OF TWIN ACODE WRITE (TTyEmphTwin.State): one
  state's, or select's with emphasis' (blur's) over it -- False where that
  twin is not wanted (none of its states writes a key) }
function TyLabelStateCfgOf(const ASpec: TTyLabelSpec; ACode: Byte;
  out ACfg: TTyLabelStateCfg): Boolean;

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
{ The same table over a rect given as x, y, width and height -- the form
  upstream adds to, so an anchor computed from it is exact. [Batch 73] }
procedure TyLabelAnchorXYWH(const AHost: TTyXYWH; APosition: TTyLabelPosition;
  ADistancePx, AAtX, AAtY: Double;
  out AX, AY: Double; out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
{ [F3d] A LABEL HUNG ON A BOX AND TURNED ABOUT THE BOX'S CENTRE (zrender's
  updateInnerText with a text config's rotation and 'center' origin, the
  radial tree's): the anchor the position puts on ABox at ADist, carried by
  getLocalTransform's turn about the centre }
procedure TyLabelTurnedAnchor(const ABox: TTyXYWH; APosition: TTyLabelPosition;
  ADist, ARot: Double; out AX, AY: Double);

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

type
  TTyAffine6 = array[0..5] of Double;

{ [R7-M] A LABEL SQUASHED ON Y BEFORE ITS TURN, as one map from its own CSS
  px to device px: anchored at (AX, AY), turned by ARot (TyRtPoint's
  sense), AScale device px to one, y scaled by AYScale first; the device
  box a text-frame box lays down as under it; and a one-run text's box in
  its own frame (AW by AH, hung by the alignment) }
procedure TyLabelAffineOf(AX, AY, ARot, AScale, AYScale: Double;
  out A: TTyAffine6);
function TyRtAffineBox(const ABox: TTyXYWH; const A: TTyAffine6): TTyRectF;
{ [R7-N] A SQUASHED CAPTION'S MAP MADE AGAIN from where it is now (its X, Y
  and turn, a frame's or a state's): Line.beforeUpdate keeps the words
  squashed by FixedYScale in every frame, at the place and the turn the
  line gives them then. A caption with no such map is left as it is. }
procedure TyCaptionAffineSync(var ACaption: TTyElementCaption);
function TyAnchorTextRect(AW, AH: Double; AAH: TTyTextAnchorH;
  AAV: TTyTextAnchorV): TTyXYWH;

{ [R7-M] A TREEMAP'S LABEL ON ITS CELL (ACaption.HasFixedBox): the width,
  the height and the padding TreemapView's beforeUpdate gives the label --
  the content rect (the strip) less the padding, which the cell was cut by }
procedure TyLabelFixBox(var ASpec: TTyLabelSpec; const ACaption: TTyElementCaption);

{ AN ATTACHED LABEL'S BLOCK: ASpec.Rt finished in the spec's font with the
  host's fill as the inherit colour, laid out about (0, 0) with the host's
  defaults -- the automatic ink and halo TyLabelInk gives a label with no
  colour of its own over that host, and the alignment the position implies.
  Shared by the expansion and by the passes that place their own labels (a
  pie's, a funnel's). [Batch 86] }
function TyLabelBlockPieces(const ASpec: TTyLabelSpec; const AText: string;
  AHostFill: TTyChartColor; AHostHasFill, AHostGradient, AInside: Boolean;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV; AScale: Double;
  const AMeasurer: ITyTextMeasurer): TTyRtPieceArray;
{ [R7-L] THE SAME TEXT AS zrender BOUNDS IT (TyRtLayJsBox): the label's
  getBoundingRect, CSS px, NaN where upstream's is -- a size written as a
  word lays a box out at NaN, which a label layout reads. }
function TyLabelBlockJsBox(const ASpec: TTyLabelSpec; const AText: string;
  AHostFill: TTyChartColor; AHostHasFill, AHostGradient, AInside: Boolean;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV; AScale: Double;
  const AMeasurer: ITyTextMeasurer): TTyXYWH;

{ [R5-F] WHAT A HOVERED TEXT IS LAID OUT UNDER besides its chain: the
  normal style's keys a site set over the option -- the label layout's
  fontSize, width and height, a pie solver's width -- which an emphasis key
  written over them still wins (zrender merges the state's style over the
  normal one). Widths CSS px; FontSize the FontUnits encoding, 0 none. }
type
  TTyLabelEmphOver = record
    FontSize: Integer;
    HasWidth, HasHeight: Boolean;
    Width, Height: Double;
    { the alignment is the site's, not the style's (a layout's align) }
    NoStyleAlign: Boolean;
    { a pie's default overflow 'truncate' under a width }
    TruncDefault: Boolean;
  end;

{ [R5-F] THE HOVERED BLOCK: the emphasis label (a data item's own over the
  series') resolved over the normal chain -- each key, and each rich
  style key by key, the emphasis' where written -- in the spec's font,
  laid out in the hover's ink about (0, 0) with AH / AV. Nil where neither
  the series nor the item writes an emphasis key that lays the text out
  again. }
function TyLabelEmphPiecesOver(const ASpec: TTyLabelSpec; const AText: string;
  AHostFill: TTyChartColor; AHostHasFill: Boolean; AEmphInk: TTyChartColor;
  AEmphStroke: TTyChartColor; AEmphStrokeW: Double;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV; AScale: Double;
  const AMeasurer: ITyTextMeasurer; const AOver: TTyLabelEmphOver): TTyRtPieceArray;
function TyLabelEmphOverNone: TTyLabelEmphOver;

{ A CAPTION IN THE HOVER'S INK: its colour and halo, and its block's
  pieces, where it stamped a hover's (HasEmph). Every place that draws a
  caption hovered goes through this, so the block cannot be left in the
  normal ink. [Batch 86] }
procedure TyCaptionToEmphasis(var ACaption: TTyElementCaption);

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

{ ZRENDER'S PLAIN-TEXT OVERFLOW, parseText.ts: AText's lines, those the
  height cannot hold dropped (the line height is the width of '国'), each
  cut to the width -- the container one short of it, AMinChar 'a' widths
  reserved before deciding whether AEllipsis fits (it is dropped if not),
  a first cut by summing character widths, a second by proportion, then the
  ellipsis. A width under one gives ''. Lengths are UTF-16 units, as JS's.
  AWidth and AHeight are the box inside the padding. ARich: the rich
  layout's threshold -- a line is cut only when wider than the box itself.
  [Batches 76, 80] }
function TyZrPlainTextLines(const AText: string; AWidth, AHeight: Double;
  AMinChar: Integer; const AEllipsis: string; const AMeasurer: ITyTextMeasurer;
  const AFontName: string; AFontSizeLogical, AWeight: Integer;
  ARich: Boolean = False): TStringArray;
{ AItemSpecs[series][raw row]: a data item's own label read over its
  series', for a caption whose ItemSpec names it [Batch 68] }
procedure TyExpandLabels(AList: TTyPaintList; const ASpecs: TTyLabelSpecArray;
  const AItemSpecs: TTyLabelSpecTable; const AMeasurer: ITyTextMeasurer;
  APPI: Integer); overload;

implementation

uses fpjson, jsonparser, tyControls.AdvanceChart.Style, tyControls.AdvanceChart.RichStyle,
  tyControls.AdvanceChart.RichText, tyControls.AdvanceChart.PolarBar,
  tyControls.AdvanceChart.LabelLayout, tyControls.AdvanceChart.Color,
  tyControls.AdvanceChart.JsMath, tyControls.AdvanceChart.Option;

{ [R5-B] THE HOVERED BLOCK when emphasis.label writes `rich`: the chain
  resolved again with the emphasis label first (its rich styles cascade over
  the normal ones key by key, its own keys over the label's), laid out in
  the hover's ink; nil when the spec has no emphasis block or no chain }
function TyLabelEmphOverNone: TTyLabelEmphOver;
begin
  Result := Default(TTyLabelEmphOver);
end;

function TyLabelEmphPiecesOver(const ASpec: TTyLabelSpec; const AText: string;
  AHostFill: TTyChartColor; AHostHasFill: Boolean; AEmphInk: TTyChartColor;
  AEmphStroke: TTyChartColor; AEmphStrokeW: Double;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV; AScale: Double;
  const AMeasurer: ITyTextMeasurer; const AOver: TTyLabelEmphOver): TTyRtPieceArray;
var
  chain: array of TJSONObject;
  parsed: array of TJSONData;
  i, nEmph, sz, emphSz, wt: Integer;
  rt: TTyRtBlockStyle;
  emphWidth, emphHeight, emphSize, emphWeight, emphStyle: Boolean;
  src: TTyStringArray;
  d: TJSONData;
begin
  Result := nil;
  if (ASpec.EmphRtNode = '') and (ASpec.EmphItemNode = '') then Exit;
  { the item's emphasis label, the series', then the normal chain }
  src := nil;
  if ASpec.EmphItemNode <> '' then
  begin
    SetLength(src, Length(src) + 1);
    src[High(src)] := ASpec.EmphItemNode;
  end;
  if ASpec.EmphRtNode <> '' then
  begin
    SetLength(src, Length(src) + 1);
    src[High(src)] := ASpec.EmphRtNode;
  end;
  nEmph := Length(src);
  SetLength(src, nEmph + Length(ASpec.RtChain));
  for i := 0 to High(ASpec.RtChain) do src[nEmph + i] := ASpec.RtChain[i];
  SetLength(parsed, Length(src));
  SetLength(chain, Length(src));
  emphWidth := False;
  emphHeight := False;
  emphSize := False;
  emphWeight := False;
  emphStyle := False;
  emphSz := 0;
  wt := ASpec.FontWeight;
  try
    for i := 0 to High(parsed) do
    begin
      parsed[i] := nil;
      try
        parsed[i] := GetJSON(src[i]);
      except
        parsed[i] := nil;
      end;
      if parsed[i] is TJSONObject then chain[i] := TJSONObject(parsed[i])
      else chain[i] := nil;
      { what the emphasis itself writes, which the site's normal keys do not
        override }
      if (i < nEmph) and (chain[i] <> nil) then
      begin
        emphWidth := emphWidth or ((chain[i].Find('width') <> nil)
          and (chain[i].Find('width').JSONType <> jtNull));
        emphHeight := emphHeight or ((chain[i].Find('height') <> nil)
          and (chain[i].Find('height').JSONType <> jtNull));
        { THE BLOCK'S FONT, which a chain does not set (the site's is final):
          the most specific emphasis node that writes each part }
        if not emphSize and (TyOptFontSize(chain[i].Find('fontSize'), 0) > 0) then
        begin
          emphSize := True;
          emphSz := TyOptFontSize(chain[i].Find('fontSize'), 0);
        end;
        d := chain[i].Find('fontWeight');
        if not emphWeight and (TyFontWeightOf(d, 0) > 0) then
        begin
          emphWeight := True;
          wt := TyFontWeightOf(d, wt);
        end;
        d := chain[i].Find('fontStyle');
        if not emphStyle and (d <> nil) and (d.JSONType = jtString) then
        begin
          emphStyle := True;
          wt := TyFontStyleOver(d, wt);
        end;
      end;
    end;
    rt := TyRtResolve(chain, ASpec.RtGlobal, TyRtResolveOpt(True));
  finally
    for i := 0 to High(parsed) do parsed[i].Free;
  end;
  if AOver.NoStyleAlign then
  begin
    rt.Style.Align := rtaNone;
    rt.Style.VAlign := rtvNone;
  end;
  if AOver.HasWidth and not emphWidth then
  begin
    rt.Style.WidthKind := rtwNumber;
    rt.Style.Width := AOver.Width;
    if AOver.TruncDefault and (rt.Style.Overflow = rtoNone) then
      rt.Style.Overflow := rtoTruncate;
  end;
  if AOver.HasHeight and not emphHeight then
  begin
    rt.Style.HasHeight := True;
    rt.Style.HeightIsText := False;
    rt.Style.Height := AOver.Height;
  end;
  sz := ASpec.FontSizeLogical;
  if emphSize then sz := emphSz
  else if AOver.FontSize > 0 then sz := AOver.FontSize;
  TyRtFinish(rt, ASpec.FontName, sz, wt, ASpec.RtGlobal, AHostHasFill, AHostFill);
  Result := TyRtLay(AText, rt, TyRtDefaultOf(True, AEmphInk, AEmphStrokeW > 0,
    AEmphStroke, True, AH, AV), AScale, AMeasurer);
end;

function TyLabelEmphPieces(const ASpec: TTyLabelSpec; const AText: string;
  AHostFill: TTyChartColor; AHostHasFill: Boolean; AEmphInk: TTyChartColor;
  AEmphStroke: TTyChartColor; AEmphStrokeW: Double;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV; AScale: Double;
  const AMeasurer: ITyTextMeasurer): TTyRtPieceArray;
begin
  Result := TyLabelEmphPiecesOver(ASpec, AText, AHostFill, AHostHasFill,
    AEmphInk, AEmphStroke, AEmphStrokeW, AH, AV, AScale, AMeasurer,
    TyLabelEmphOverNone);
end;

procedure TyLabelAffineOf(AX, AY, ARot, AScale, AYScale: Double;
  out A: TTyAffine6);
var c, s: Double;
begin
  { scale x diag(1, AYScale) x the turn, in zrender's order (x' = a x + c y,
    y' = b x + d y); the turn as TyRtPoint takes it }
  c := Cos(ARot);
  s := Sin(ARot);
  A[0] := AScale * c;
  A[1] := -AScale * AYScale * s;
  A[2] := AScale * s;
  A[3] := AScale * AYScale * c;
  A[4] := AX;
  A[5] := AY;
end;

procedure TyCaptionAffineSync(var ACaption: TTyElementCaption);
var
  aff: TTyAffine6;
  k: Integer;
  sc: Double;
begin
  if not ACaption.HasAffine or not (ACaption.FixedYScale > 0)
    or (ACaption.FixedYScale = 1) then Exit;
  sc := ACaption.RtScale;
  if not (sc > 0) then sc := 1;
  TyLabelAffineOf(ACaption.X, ACaption.Y, ACaption.RotationRad, sc,
    ACaption.FixedYScale, aff);
  for k := 0 to 5 do ACaption.Affine[k] := aff[k];
end;

function TyRtAffineBox(const ABox: TTyXYWH; const A: TTyAffine6): TTyRectF;
var
  xs, ys: array[0..3] of Double;
  k: Integer;
begin
  if ABox.W < 0 then Exit(TyRectF(A[4], A[5], A[4], A[5]));
  xs[0] := ABox.X; ys[0] := ABox.Y;
  xs[1] := ABox.X + ABox.W; ys[1] := ABox.Y;
  xs[2] := ABox.X + ABox.W; ys[2] := ABox.Y + ABox.H;
  xs[3] := ABox.X; ys[3] := ABox.Y + ABox.H;
  Result := TyRectF(Infinity, Infinity, NegInfinity, NegInfinity);
  for k := 0 to 3 do
  begin
    Result.Left := Min(Result.Left, A[0] * xs[k] + A[2] * ys[k] + A[4]);
    Result.Right := Max(Result.Right, A[0] * xs[k] + A[2] * ys[k] + A[4]);
    Result.Top := Min(Result.Top, A[1] * xs[k] + A[3] * ys[k] + A[5]);
    Result.Bottom := Max(Result.Bottom, A[1] * xs[k] + A[3] * ys[k] + A[5]);
  end;
end;

function TyAnchorTextRect(AW, AH: Double; AAH: TTyTextAnchorH;
  AAV: TTyTextAnchorV): TTyXYWH;
var x, y: Double;
begin
  case AAH of
    tahCentre: x := -AW / 2;
    tahRight: x := -AW;
  else
    x := 0;
  end;
  case AAV of
    tavMiddle: y := -AH / 2;
    tavBottom: y := -AH;
  else
    y := 0;
  end;
  Result := TyXYWH(x, y, AW, AH);
end;

procedure TyLabelFixBox(var ASpec: TTyLabelSpec; const ACaption: TTyElementCaption);
var k: Integer;
begin
  if not ACaption.HasFixedBox then Exit;
  ASpec.Rt.Style.WidthKind := rtwNumber;
  ASpec.Rt.Style.Width := ACaption.FixedBoxW;
  ASpec.Rt.Style.WidthIsText := False;
  ASpec.Rt.Style.HasHeight := True;
  ASpec.Rt.Style.Height := ACaption.FixedBoxH;
  ASpec.Rt.Style.HeightIsText := False;
  ASpec.Rt.Style.HasPadding := True;
  for k := 0 to 3 do ASpec.Rt.Style.Padding[k] := ACaption.FixedBoxPad[k];
end;

function TyLabelBlockPieces(const ASpec: TTyLabelSpec; const AText: string;
  AHostFill: TTyChartColor; AHostHasFill, AHostGradient, AInside: Boolean;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV; AScale: Double;
  const AMeasurer: ITyTextMeasurer): TTyRtPieceArray;
var
  rt: TTyRtBlockStyle;
  autoSpec: TTyLabelSpec;
  autoInk, autoStroke: TTyChartColor;
  autoW: Double;
begin
  rt := ASpec.Rt;
  TyRtFinish(rt, ASpec.FontName, ASpec.FontSizeLogical, ASpec.FontWeight,
    ASpec.RtGlobal, AHostHasFill, AHostFill);
  { [R7-L] THE TEXT'S OWN OPACITY IS THE ELEMENT'S (its label.opacity, the
    root textStyle's, the host's defaultOpacity) and every piece but a
    token with its own follows it there -- in the pieces too it drew twice
    (a label.opacity 0.5 over a box at 0.25) }
  rt.Style.HasOpacity := False;
  autoSpec := ASpec;
  autoSpec.AutoColour := True;
  autoSpec.InheritColour := False;
  autoSpec.FunnelInherit := False;
  autoSpec.HasBorderColour := False;
  autoSpec.HasBackground := False;
  TyLabelInk(autoSpec, AHostFill, AHostHasFill, AHostGradient, AInside, autoInk,
    autoStroke, autoW);
  Result := TyRtLay(AText, rt, TyRtDefaultOf(True, autoInk, autoW > 0,
    autoStroke, True, AH, AV), AScale, AMeasurer);
end;

function TyLabelBlockJsBox(const ASpec: TTyLabelSpec; const AText: string;
  AHostFill: TTyChartColor; AHostHasFill, AHostGradient, AInside: Boolean;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV; AScale: Double;
  const AMeasurer: ITyTextMeasurer): TTyXYWH;
var
  rt: TTyRtBlockStyle;
  autoSpec: TTyLabelSpec;
  autoInk, autoStroke: TTyChartColor;
  autoW: Double;
begin
  { as TyLabelBlockPieces lays it out }
  rt := ASpec.Rt;
  TyRtFinish(rt, ASpec.FontName, ASpec.FontSizeLogical, ASpec.FontWeight,
    ASpec.RtGlobal, AHostHasFill, AHostFill);
  rt.Style.HasOpacity := False;
  autoSpec := ASpec;
  autoSpec.AutoColour := True;
  autoSpec.InheritColour := False;
  autoSpec.FunnelInherit := False;
  autoSpec.HasBorderColour := False;
  autoSpec.HasBackground := False;
  TyLabelInk(autoSpec, AHostFill, AHostHasFill, AHostGradient, AInside, autoInk,
    autoStroke, autoW);
  Result := TyRtLayJsBox(AText, rt, TyRtDefaultOf(True, autoInk, autoW > 0,
    autoStroke, True, AH, AV), AScale, AMeasurer);
end;

procedure TyCaptionToEmphasis(var ACaption: TTyElementCaption);
var
  pcs: TTyRtPieceArray;
  i: Integer;
begin
  if not ACaption.HasEmph then Exit;
  ACaption.Colour := ACaption.EmphColour;
  ACaption.StrokeColour := ACaption.EmphStrokeColour;
  ACaption.StrokeWidthLogical := ACaption.EmphStrokeWidthLogical;
  if Length(ACaption.RtEmph) > 0 then ACaption.RtPieces := ACaption.RtEmph;
  { [R7-AA] A BLOCK takes the ink the hover's label writes on its text, as
    the state style's fill and stroke go over the label's own -- a rich
    token's own ink stays [was: the rest state's ink, laid out again or
    not] }
  if (Length(ACaption.RtPieces) > 0) and (ACaption.EmphOwnInk <> 0) then
  begin
    pcs := Copy(ACaption.RtPieces, 0, Length(ACaption.RtPieces));
    for i := 0 to High(pcs) do
    begin
      if pcs[i].Kind <> rpkText then Continue;
      if not pcs[i].TokenFill and ((ACaption.EmphOwnInk and 1) <> 0) then
      begin
        pcs[i].HasFill := True;
        pcs[i].Fill := ACaption.EmphColour;
        pcs[i].CanvasLeft := pcs[i].CanvasLeft and not 1;
      end;
      if not pcs[i].TokenStroke and ((ACaption.EmphOwnInk and 2) <> 0) then
      begin
        pcs[i].HasStroke := ACaption.EmphStrokeWidthLogical > 0;
        pcs[i].Stroke := ACaption.EmphStrokeColour;
        pcs[i].LineWidth := ACaption.EmphStrokeWidthLogical;
        pcs[i].CanvasLeft := pcs[i].CanvasLeft and not 2;
      end;
    end;
    ACaption.RtPieces := pcs;
  end;
end;

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
  ACaption.EmphOwnInk := 0;
  if ASpec.EmphHasColour then ACaption.EmphOwnInk := ACaption.EmphOwnInk or 1;
  if ASpec.EmphHasBorderColour or ASpec.EmphHasBorderWidth then
    ACaption.EmphOwnInk := ACaption.EmphOwnInk or 2;
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

function TyLabelStateCfgWrites(const ACfg: TTyLabelStateCfg): Boolean;
begin
  Result := ACfg.HasPosition or ACfg.HasDistance or ACfg.HasOffset or ACfg.HasRotation
    or ACfg.HasPosWord;
end;

function TyLabelStateCfgOver(const ABase, AOver: TTyLabelStateCfg): TTyLabelStateCfg;
begin
  Result := ABase;
  if AOver.HasPosition then
  begin
    Result.HasPosition := True;
    Result.Position := AOver.Position;
    Result.Outside := AOver.Outside;
    Result.AtX := AOver.AtX;
    Result.AtY := AOver.AtY;
    Result.AtXIsPercent := AOver.AtXIsPercent;
    Result.AtYIsPercent := AOver.AtYIsPercent;
  end;
  if AOver.HasDistance then
  begin
    Result.HasDistance := True;
    Result.DistanceLogical := AOver.DistanceLogical;
  end;
  if AOver.HasOffset then
  begin
    Result.HasOffset := True;
    Result.OffsetXLogical := AOver.OffsetXLogical;
    Result.OffsetYLogical := AOver.OffsetYLogical;
  end;
  if AOver.HasRotation then
  begin
    Result.HasRotation := True;
    Result.RotationRad := AOver.RotationRad;
  end;
  if AOver.HasPosWord then
  begin
    Result.HasPosWord := True;
    Result.PosWord := AOver.PosWord;
  end;
end;

function TyLabelStateCfgNormal(const ASpec: TTyLabelSpec): TTyLabelStateCfg;
begin
  Result.HasPosition := True;
  Result.Position := ASpec.Position;
  Result.Outside := ASpec.Outside;
  Result.AtX := ASpec.AtX;
  Result.AtY := ASpec.AtY;
  Result.AtXIsPercent := ASpec.AtXIsPercent;
  Result.AtYIsPercent := ASpec.AtYIsPercent;
  Result.HasDistance := True;
  Result.DistanceLogical := ASpec.DistanceLogical;
  Result.HasOffset := True;
  Result.OffsetXLogical := ASpec.OffsetXLogical;
  Result.OffsetYLogical := ASpec.OffsetYLogical;
  Result.HasRotation := True;
  Result.RotationRad := ASpec.RotationRad;
end;

function TyLabelStateCfgOf(const ASpec: TTyLabelSpec; ACode: Byte;
  out ACfg: TTyLabelStateCfg): Boolean;
begin
  ACfg := Default(TTyLabelStateCfg);
  case ACode of
    TyTwinEmphasis, TyTwinBlur, TyTwinSelect:
      begin
        ACfg := ASpec.StateCfg[ACode];
        Result := TyLabelStateCfgWrites(ACfg);
      end;
    TyTwinSelectEmphasis:
      begin
        Result := TyLabelStateCfgWrites(ASpec.StateCfg[TyTwinSelect])
          and TyLabelStateCfgWrites(ASpec.StateCfg[TyTwinEmphasis]);
        ACfg := TyLabelStateCfgOver(ASpec.StateCfg[TyTwinSelect], ASpec.StateCfg[TyTwinEmphasis]);
      end;
    TyTwinSelectBlur:
      begin
        Result := TyLabelStateCfgWrites(ASpec.StateCfg[TyTwinSelect])
          and TyLabelStateCfgWrites(ASpec.StateCfg[TyTwinBlur]);
        ACfg := TyLabelStateCfgOver(ASpec.StateCfg[TyTwinSelect], ASpec.StateCfg[TyTwinBlur]);
      end;
  else
    Result := False;
  end;
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
var r: TTyXYWH;
begin
  r.X := AHost.Left;
  r.Y := AHost.Top;
  r.W := TyRectFWidth(AHost);
  r.H := TyRectFHeight(AHost);
  TyLabelAnchorXYWH(r, APosition, ADistancePx, AAtX, AAtY, AX, AY, AH, AV);
end;

procedure TyLabelTurnedAnchor(const ABox: TTyXYWH; APosition: TTyLabelPosition;
  ADist, ARot: Double; out AX, AY: Double);
var
  x, y, ox, oy, m4, m5, st, ct, atx, aty: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
begin
  TyLabelAnchorXYWH(ABox, APosition, ADist, 0, 0, x, y, ah, av);
  { getLocalTransform with an origin at the box's centre }
  ox := ABox.X + ABox.W / 2 - x;
  oy := ABox.Y + ABox.H / 2 - y;
  if (ox <> 0) or (oy <> 0) then
  begin
    m4 := -ox;
    m5 := -oy;
  end
  else
  begin
    m4 := 0;
    m5 := 0;
  end;
  if ARot <> 0 then
  begin
    st := TyJsSin(ARot);
    ct := TyJsCos(ARot);
    atx := m4;
    aty := m5;
    m4 := ct * atx + st * aty;
    m5 := ct * aty - st * atx;
  end;
  AX := m4 + (ox + x);
  AY := m5 + (oy + y);
end;

procedure TyLabelAnchorXYWH(const AHost: TTyXYWH; APosition: TTyLabelPosition;
  ADistancePx, AAtX, AAtY: Double;
  out AX, AY: Double; out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
var
  x0, y0, w, h, halfH: Double;
begin
  x0 := AHost.X;
  y0 := AHost.Y;
  w := AHost.W;
  h := AHost.H;
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
        { zrender's grouping: x += distance + width }
        AX := x0 + (ADistancePx + w); AY := y0 + halfH;
        AV := tavMiddle;
      end;
    tlpTop:
      begin
        AX := x0 + w / 2; AY := y0 - ADistancePx;
        AH := tahCentre; AV := tavBottom;
      end;
    tlpBottom:
      begin
        AX := x0 + w / 2; AY := y0 + (h + ADistancePx);
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
        AX := x0 + (w - ADistancePx); AY := y0 + halfH;
        AH := tahRight; AV := tavMiddle;
      end;
    tlpInsideTop:
      begin
        AX := x0 + w / 2; AY := y0 + ADistancePx;
        AH := tahCentre;
      end;
    tlpInsideBottom:
      begin
        AX := x0 + w / 2; AY := y0 + (h - ADistancePx);
        AH := tahCentre; AV := tavBottom;
      end;
    tlpInsideTopLeft:
      begin
        AX := x0 + ADistancePx; AY := y0 + ADistancePx;
      end;
    tlpInsideTopRight:
      begin
        AX := x0 + (w - ADistancePx); AY := y0 + ADistancePx;
        AH := tahRight;
      end;
    tlpInsideBottomLeft:
      begin
        AX := x0 + ADistancePx; AY := y0 + (h - ADistancePx);
        AV := tavBottom;
      end;
    tlpInsideBottomRight:
      begin
        AX := x0 + (w - ADistancePx); AY := y0 + (h - ADistancePx);
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
  { the alpha as written, not the byte's [F4c]: rgba(255,255,255,0.5) is
    lum 0.5 exactly, which lands in the light band as upstream's does }
  a := TyChartColorAlpha(AColour);
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
      before it paints. [R7-W] A colour no parser reads is a string all
      the same: stroked with the strokeStyle the canvas had }
    if ((AColour shr 24) = 0) and (AColour <> cTyCanvasColourLeft) then Exit;
    AStroke := AColour;
    AStrokeWidthLogical := w;
  end;

begin
  AStroke := 0;
  AStrokeWidthLogical := 0;
  inside := AInside and AHostHasFill;
  band := TyLabelInkBand(AHostFill, AHostGradient);
  { `textBorderWidth || 2`: a nought is two. ([R7-AF] +Infinity is the
    width the canvas had: nought until the paint order settles it) }
  if ASpec.HasBorderWidth and ASpec.BorderWidthInf then
    w := 0
  else if ASpec.HasBorderWidth and (ASpec.BorderWidthLogical > 0) then
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
    if not (ASpec.HasBorderWidth and ((ASpec.BorderWidthLogical > 0) or ASpec.BorderWidthInf)) then Exit;
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
  { the hover's stroke colour over the normal one: zrender merges the
    emphasis style's `stroke` over the label's (labelStyle.ts:550-583) }
  if ASpec.EmphHasBorderColour then
  begin
    s.HasBorderColour := True;
    s.BorderColourNone := ASpec.EmphBorderColourNone;
    s.BorderColourInherit := ASpec.EmphBorderColourInherit;
    s.BorderColour := ASpec.EmphBorderColour;
  end;
  TyLabelInk(s, AHostFill, AHostHasFill, AHostGradient, AInside, AInk, AStroke,
    AStrokeWidthLogical);
end;

function TyZrPlainTextLines(const AText: string; AWidth, AHeight: Double;
  AMinChar: Integer; const AEllipsis: string; const AMeasurer: ITyTextMeasurer;
  const AFontName: string; AFontSizeLogical, AWeight: Integer;
  ARich: Boolean): TStringArray;
const
  { U+56FD, zrender's stand-in for any wide character, as UTF-8 }
  cGuo = #$E5#$9B#$BD;
var
  lines: TStringArray;
  lh, containerWidth, contentWidth, asc, ellW, lw, w: Double;
  ell: string;
  k, j, i, n, keep, sub: Integer;
  u: UnicodeString;

  function M(const S: string): Double;
  var h_: Double;
  begin
    if S = '' then Exit(0);
    AMeasurer.MeasureLine(S, AFontName, AFontSizeLogical, AWeight, Result, h_);
  end;

  function CharW(ACode: Integer): Double;
  begin
    if (ACode >= 0) and (ACode <= 127) then Result := M(Chr(ACode))
    else Result := M(cGuo);
  end;

begin
  Result := nil;
  if AText = '' then Exit;
  lines := AText.Split([#10]);
  lh := M(cGuo);
  { lineOverflow 'truncate': the lines that fit }
  if Length(lines) * lh > AHeight then
  begin
    keep := Floor(AHeight / lh);
    if keep < Length(lines) then SetLength(lines, Max(keep, 0));
  end;
  containerWidth := Max(0.0, AWidth - 1);
  contentWidth := containerWidth;
  asc := M('a');
  i := 0;
  while (i < AMinChar) and (contentWidth >= asc) do
  begin
    contentWidth := contentWidth - asc;
    Inc(i);
  end;
  ell := AEllipsis;
  ellW := M(ell);
  if ellW > contentWidth then
  begin
    ell := '';
    ellW := 0;
  end;
  contentWidth := containerWidth - ellW;
  for k := 0 to High(lines) do
  begin
    if (AWidth = 0) or (containerWidth = 0) then
    begin
      lines[k] := '';
      Continue;
    end;
    lw := M(lines[k]);
    { the rich layout cuts only a line wider than the box itself, the plain
      one a line wider than the box less one [Batch 80] }
    if ARich then
    begin
      if lw <= AWidth then Continue;
    end
    else if lw <= containerWidth then Continue;
    j := 0;
    while True do
    begin
      if (lw <= contentWidth) or (j >= 2) then
      begin
        lines[k] := lines[k] + ell;
        Break;
      end;
      u := UTF8Decode(lines[k]);
      n := Length(u);
      if j = 0 then
      begin
        { estimateLength: characters while the sum is short, the crossing
          one counted }
        w := 0;
        sub := 0;
        while (sub < n) and (w < contentWidth) do
        begin
          w := w + CharW(Ord(u[sub + 1]));
          Inc(sub);
        end;
      end
      else if lw > 0 then
        sub := Floor(n * contentWidth / lw)
      else
        sub := 0;
      lines[k] := UTF8Encode(Copy(u, 1, sub));
      lw := M(lines[k]);
      Inc(j);
    end;
  end;
  Result := lines;
end;

procedure TyExpandLabels(AList: TTyPaintList; const ASpecs: TTyLabelSpecArray;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
begin
  TyExpandLabels(AList, ASpecs, nil, AMeasurer, APPI);
end;

function TyLabelLayTwin(const AIn: TTyLabelTwinIn; ACode: Byte;
  const AStates: TTyLabelStateCfg; const AMeasurer: ITyTextMeasurer;
  out ATwin: TTyEmphTwin): Boolean;
var
  ACfg: TTyLabelStateCfg;
  tbx, tby, trot: Double;
  anc: Integer;
  sec: TTyPolarSector;
  spos: TTySectorTextPos;
  tword: string;
  known: Boolean;
  tw: TTyEmphTwin;
  tpos: TTyLabelPosition;
  tx, ty, tdist, tatX, tatY, toffX, toffY, tw2: Double;
  tah: TTyTextAnchorH;
  tav: TTyTextAnchorV;
  tm: TTyMat2D;
  tbox: TTyRectF;
  tpieces: TTyRtPieceArray;
  tinside, tgrad: Boolean;
  tspec: TTyLabelSpec;
  tink, tstroke: TTyChartColor;
begin
  Result := False;
  ATwin := Default(TTyEmphTwin);
  ACfg := TyLabelStateCfgOver(AIn.Normal, AStates);
  tdist := ACfg.DistanceLogical * AIn.Scale;
  tpos := ACfg.Position;
  { 'outside': the AIn.Host's defaultOutsidePosition, 'top' where it has none }
  if ACfg.Outside then
    case AIn.Host.Caption.Outside of
      coTop: tpos := tlpTop;
      coBottom: tpos := tlpBottom;
      coLeft: tpos := tlpLeft;
      coRight: tpos := tlpRight;
    end;
  if ACfg.AtXIsPercent then tatX := ACfg.AtX * (AIn.Bounds.Right - AIn.Bounds.Left)
  else tatX := ACfg.AtX * AIn.Scale;
  if ACfg.AtYIsPercent then tatY := ACfg.AtY * (AIn.Bounds.Bottom - AIn.Bounds.Top)
  else tatY := ACfg.AtY * AIn.Scale;
  anc := -1;
  if AIn.Host.Anim.Role = carTmRect then
  begin
    { A TREEMAP NODE'S: where the treemap's own placement puts the words
      under the states' position and distance (its padding, its cut) }
    anc := TyEmphTwinAt(AIn.Host.EmphTwin, ACode);
    if anc < 0 then Exit;
  end;
  if anc >= 0 then
  begin
    tx := AIn.Host.EmphTwin[anc].Caption.X;
    ty := AIn.Host.EmphTwin[anc].Caption.Y;
    tah := AIn.Host.EmphTwin[anc].Caption.AnchorH;
    tav := AIn.Host.EmphTwin[anc].Caption.AnchorV;
    tpos := tlpInside;
  end
  else if AIn.Host.Caption.SecHas then
  begin
    { A POLAR BAR'S: its sector positions by the sector's own
      calculateTextPosition, any other on the path's rect; the turn
      setSectorTextRotation gave the normal position unless a state
      writes one; inside where the normal position is 'middle'
      (textConfig.inside) or the word says }
    sec.CX := AIn.Host.Anim.G[0];
    sec.CY := AIn.Host.Anim.G[1];
    sec.R0 := AIn.Host.Anim.G[2];
    sec.R := AIn.Host.Anim.G[3];
    sec.SA := AIn.Host.Anim.G[4];
    sec.EA := AIn.Host.Anim.G[5];
    sec.CW := AIn.Host.Anim.G[6] <> 0;
    if AStates.HasPosWord then
    begin
      tword := AStates.PosWord;
      if tword = 'outside' then tword := TyPolarOutsideWord(sec, AIn.Host.Anim.G[7] <> 0);
      spos := TySectorTextPosOf(tword, AIn.Host.Anim.G[7] <> 0);
      tpos := TyLabelPositionOf(tword, known);
      { a word calculateTextPosition does not know: the rect's corner,
        aligned left / top (its switch has no default) }
      if (spos = stpBuiltin) and not known then
      begin
        tpos := tlpAt;
        tatX := 0;
        tatY := 0;
      end;
    end
    else
    begin
      tword := '';
      if AIn.Host.Caption.SecAnchor then spos := TTySectorTextPos(AIn.Host.Caption.SecPos)
      else spos := stpBuiltin;
    end;
    if spos <> stpBuiltin then
      TySectorLabelAnchor(sec, spos, tdist, AIn.Host.Anim.G[8] <> 0, tx, ty, tah, tav)
    else
    begin
      if ACfg.AtXIsPercent then tatX := ACfg.AtX * AIn.HBox.W;
      if ACfg.AtYIsPercent then tatY := ACfg.AtY * AIn.HBox.H;
      TyLabelAnchorXYWH(AIn.HBox, tpos, tdist, tatX, tatY, tx, ty, tah, tav);
    end;
  end
  else if not ACfg.HasPosition then
  begin
    { no position: label.x / y where the mark put it }
    tx := AIn.FreeX;
    ty := AIn.FreeY;
    tah := AIn.FreeAH;
    tav := AIn.FreeAV;
    if AIn.FreeInside then tpos := tlpInside else tpos := tlpRight;
  end
  else if AIn.HasBox then
  begin
    if ACfg.AtXIsPercent then tatX := ACfg.AtX * AIn.HBox.W;
    if ACfg.AtYIsPercent then tatY := ACfg.AtY * AIn.HBox.H;
    TyLabelAnchorXYWH(AIn.HBox, tpos, tdist, tatX, tatY, tx, ty, tah, tav);
    if (tpos = tlpInside) and AIn.Host.Caption.HasSymBox and (AIn.Host.Caption.LgSymbol = 'pin') then
      ty := AIn.HBox.Y + AIn.HBox.H * Double(0.4);
  end
  else
    TyLabelAnchor(AIn.Bounds, tpos, tdist, tatX, tatY, tx, ty, tah, tav);
  if (ACfg.HasPosition or AIn.Host.Caption.SecHas) and (anc < 0) then
  begin
    if AIn.StyleHasAH then tah := AIn.StyleAH;
    if AIn.StyleHasAV then tav := AIn.StyleAV;
    if AIn.Host.Anim.Role = carRiver then tav := tavMiddle;
  end;
  tbx := tx;
  tby := ty;
  toffX := ACfg.OffsetXLogical * AIn.Scale;
  toffY := ACfg.OffsetYLogical * AIn.Scale;
  trot := ACfg.RotationRad;
  if AIn.Host.Caption.SecHas and not AStates.HasRotation then trot := AIn.Host.Caption.SecRot;
  if AIn.TurnAboutBox and ACfg.HasPosition then
  begin
    { textConfig origin 'center': turned about the box's centre, the offset
      a plain move (an origin of its own) }
    TyLabelTurnedAnchor(AIn.HBox, tpos, tdist, trot, tx, ty);
    tx := tx + toffX;
    ty := ty + toffY;
  end
  else if TyLabelLocalTransform(tx + toffX, ty + toffY, -toffX, -toffY, trot,
    1, 1, tm) then
  begin
    tx := tm[4];
    ty := tm[5];
  end
  else
  begin
    tx := 0;
    ty := 0;
  end;
  tinside := ACfg.HasPosition and TyLabelIsInside(tpos);
  if not ACfg.HasPosition or (anc >= 0) then tinside := AIn.FreeInside;
  if AIn.Host.Caption.SecHas then
  begin
    if AStates.HasPosWord then
      tinside := AIn.Host.Caption.SecMiddle or (System.Pos('inside', tword) > 0)
    else
      tinside := AIn.Host.Caption.SecInside;
  end;
  tgrad := AIn.Host.Style.HasFill and (AIn.Host.Style.FillGradient.Kind <> cgkNone);
  tpieces := nil;
  if AIn.Spec.Rt.Needed then
  begin
    tspec := AIn.Spec;
    { [R7-M] a treemap's label on its cell, under the state's place }
    if (anc >= 0) and AIn.Host.EmphTwin[anc].Caption.HasFixedBox then
    begin
      TyLabelFixBox(tspec, AIn.Host.EmphTwin[anc].Caption);
      tspec.Rt.Style.Align := rtaNone;
      tspec.Rt.Style.VAlign := rtvNone;
      tpieces := TyLabelBlockPieces(tspec, AIn.Text, AIn.HostFill, AIn.HostHasFill,
        tgrad, tinside, AIn.Host.EmphTwin[anc].Caption.FixedBoxAH,
        AIn.Host.EmphTwin[anc].Caption.FixedBoxAV, AIn.Scale, AMeasurer);
      TyRtShiftPieces(tpieces, (AIn.Host.EmphTwin[anc].Caption.FixedBoxX + toffX - tx)
        / AIn.Scale, (AIn.Host.EmphTwin[anc].Caption.FixedBoxY + toffY - ty) / AIn.Scale);
    end
    else
      tpieces := TyLabelBlockPieces(tspec, AIn.Text, AIn.HostFill, AIn.HostHasFill,
        tgrad, tinside, tah, tav, AIn.Scale, AMeasurer);
    if Length(tpieces) = 0 then Exit;
    tbox := TyRtDeviceBox(tpieces, tx, ty, trot, AIn.Scale);
  end
  else
    tbox := TyAnchorBox(tx, ty, AIn.W, AIn.H, tah, tav);
  Result := False;
  tw := Default(TTyEmphTwin);
  tw.State := ACode;
  tw.Caption := AIn.Base;
  { a box-turned label: what a scaled box lays it out again by (RideBox) }
  if AIn.TurnAboutBox and ACfg.HasPosition then
  begin
    tw.Caption.FixedPos := Ord(tpos);
    tw.Caption.FixedDist := tdist;
    tw.Caption.FixedRotationRad := trot;
  end;
  tw.Caption.X := tx;
  tw.Caption.Y := ty;
  tw.Caption.AnchorH := tah;
  tw.Caption.AnchorV := tav;
  tw.Caption.RotationRad := trot;
  TyLabelInk(AIn.Spec, AIn.HostFill, AIn.HostHasFill, tgrad, tinside, tink, tstroke, tw2);
  tw.Caption.Colour := tink;
  tw.Caption.StrokeColour := tstroke;
  tw.Caption.StrokeWidthLogical := tw2;
  TyLabelStampEmphasis(AIn.Spec, AIn.HostFill, AIn.HostHasFill, tgrad, tinside, tw.Caption);
  tw.Caption.RtPieces := tpieces;
  tw.Caption.RtEmph := nil;
  if (AIn.Spec.EmphRtNode <> '') or (AIn.Spec.EmphItemNode <> '') then
    tw.Caption.RtEmph := TyLabelEmphPieces(AIn.Spec, AIn.Text, AIn.HostFill,
      AIn.HostHasFill, tw.Caption.EmphColour, tw.Caption.EmphStrokeColour,
      tw.Caption.EmphStrokeWidthLogical, tah, tav, AIn.Scale, AMeasurer);
  if (Length(tpieces) > 0) and (Length(tw.Caption.RtEmph) = 0) then
    tw.Caption.RtEmph := TyRtReink(tpieces, tw.Caption.EmphColour, True,
      tw.Caption.EmphStrokeColour, tw.Caption.EmphStrokeWidthLogical);
  tw.Caption.LmInkInside := tinside;
  { what a label layout lays it out again from: the anchor before the
    offset, and whether the states' offset and turn are their own }
  tw.Caption.LmBaseX := tbx;
  tw.Caption.LmBaseY := tby;
  tw.Caption.LmOffX := toffX;
  tw.Caption.LmOffY := toffY;
  tw.HasOff := AStates.HasOffset;
  tw.OffX := toffX;
  tw.OffY := toffY;
  tw.HasRot := AStates.HasRotation;
  tw.Rot := trot;
  tw.Shape := TyShapeRect(tbox);
  { what the frame lays it out on its AIn.Host by (AnchorOn) }
  tw.HasRide := not AIn.Host.Caption.SecHas;
  tw.LabelPos := Ord(tpos);
  tw.LabelDist := tdist;
  tw.LabelAtXPct := ACfg.AtXIsPercent;
  tw.LabelAtYPct := ACfg.AtYIsPercent;
  if ACfg.AtXIsPercent then tw.LabelAtX := ACfg.AtX else tw.LabelAtX := ACfg.AtX * AIn.Scale;
  if ACfg.AtYIsPercent then tw.LabelAtY := ACfg.AtY else tw.LabelAtY := ACfg.AtY * AIn.Scale;
  ATwin := tw;
  Result := True;
end;

{ zrender's isInside for the caption of AHost: a polar bar's says itself
  (textConfig.inside or the word) [Batch 113] }
function LabelInside(const AHost: TTyChartElement; APos: TTyLabelPosition): Boolean;
begin
  if AHost.Caption.SecHas then Result := AHost.Caption.SecInside
  else Result := TyLabelIsInside(APos);
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
  x, y, w, h, scale, dist, sw, atX, atY, inflate: Double;
  ah, posAH: TTyTextAnchorH;
  av, posAV: TTyTextAnchorV;
  autoSpec: TTyLabelSpec;
  pieces: TTyRtPieceArray;
  raw: TTyRectF;
  hostRect, hbox: TTyXYWH;
  rtb: TTyXYWH;
  hitPieces: TTyRtPieceArray;
  hasHostRect, hasBox: Boolean;
  baseX, baseY, offX, offY, rot: Double;
  m: TTyMat2D;
  k: Integer;
  normalCfg, stCfg: TTyLabelStateCfg;
  code: Byte;
  hasAff: Boolean;
  aff: TTyAffine6;

  { [R6-A] A LINE'S LABEL: what its states write, laid out when they are
    written (the box is the Line group's as the state draws it) }
  procedure LineTwin(ACode: Byte; const AStates: TTyLabelStateCfg);
  var tw: TTyEmphTwin;
  begin
    tw := Default(TTyEmphTwin);
    tw.State := ACode;
    tw.Defer := True;
    tw.LineBox := True;
    tw.HasPos := AStates.HasPosition;
    tw.LabelPos := Ord(AStates.Position);
    tw.LabelAtXPct := AStates.AtXIsPercent;
    tw.LabelAtYPct := AStates.AtYIsPercent;
    tw.LabelAtX := AStates.AtX;
    tw.LabelAtY := AStates.AtY;
    if AStates.HasDistance then tw.LabelDist := AStates.DistanceLogical
    else tw.LabelDist := spec.DistanceLogical;
    tw.HasOff := AStates.HasOffset;
    tw.OffX := AStates.OffsetXLogical * scale;
    tw.OffY := AStates.OffsetYLogical * scale;
    tw.HasRot := AStates.HasRotation;
    tw.Rot := AStates.RotationRad;
    SetLength(cap.EmphTwin, Length(cap.EmphTwin) + 1);
    cap.EmphTwin[High(cap.EmphTwin)] := tw;
  end;

  { [R6-A] a state's twin of the caption, as TyLabelLayTwin lays it out }
  procedure Twin(ACode: Byte; const AStates: TTyLabelStateCfg);
  var
    tin: TTyLabelTwinIn;
    tw: TTyEmphTwin;
    st: TTyLabelStateCfg;
  begin
    tin.Spec := spec;
    tin.Normal := normalCfg;
    tin.Host := host;
    tin.Base := cap.Caption;
    tin.Text := host.Caption.Text;
    tin.Bounds := bounds;
    tin.HBox := hbox;
    tin.HasBox := hasBox;
    tin.W := w;
    tin.H := h;
    tin.Scale := scale;
    tin.HostFill := hostFill;
    tin.HostHasFill := hostHasFill;
    tin.FreeX := host.Caption.FixedX;
    tin.FreeY := host.Caption.FixedY;
    tin.FreeAH := host.Caption.FixedAH;
    tin.FreeAV := host.Caption.FixedAV;
    tin.FreeInside := host.Caption.FixedInside;
    tin.StyleHasAH := spec.HasAlignH;
    tin.StyleAH := spec.AlignH;
    tin.StyleHasAV := spec.HasAlignV;
    tin.StyleAV := spec.AlignV;
    { a radial tree's node: textConfig origin 'center', its style middle }
    tin.TurnAboutBox := host.Caption.HasFixedAnchor and (host.Caption.FixedByConfig = 2);
    if tin.TurnAboutBox then
    begin
      tin.StyleHasAV := True;
      tin.StyleAV := tavMiddle;
    end;
    st := AStates;
    if host.Caption.RingTurn and (ACode in [TyTwinEmphasis, TyTwinSelectEmphasis]) then
    begin
      st.HasPosition := False;
      st.HasPosWord := False;
    end;
    if TyLabelLayTwin(tin, ACode, st, AMeasurer, tw) then
    begin
      SetLength(cap.EmphTwin, Length(cap.EmphTwin) + 1);
      cap.EmphTwin[High(cap.EmphTwin)] := tw;
    end;
  end;

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
    { most elements carry no words: asked by reference before the copy [P2] }
    if AList.Ref(i)^.Caption.Text = '' then Continue;
    host := AList.Element(i);
    si := host.Datum.SeriesIndex;
    if (si < 0) or (si > High(ASpecs)) then Continue;
    spec := ASpecs[si];
    { the item's own label, read over the series' }
    if (host.Caption.ItemSpec > 0) and (si <= High(AItemSpecs))
      and (host.Caption.ItemSpec - 1 <= High(AItemSpecs[si])) then
      spec := AItemSpecs[si][host.Caption.ItemSpec - 1];
    if not (spec.Show or spec.StateShow) then Continue;
    if spec.Position = tlpNone then Continue;

    bounds := TyShapeBounds(host.Shape);
    raw := bounds;
    { THE RECT THE LABEL HANGS OFF: a mark's own (HostBox), a symbol's
      (SymBox), else the shape's bounds }
    hasBox := host.Caption.HasHostBox or host.Caption.HasSymBox;
    if host.Caption.HasHostBox then hbox := host.Caption.HostBox
    else hbox := host.Caption.SymBox;
    if hasBox then
      bounds := TyRectF(hbox.X, hbox.Y, hbox.X + hbox.W, hbox.Y + hbox.H);
    { a fixed anchor needs no host rect -- a sankey node whose column
      overflowed has a rect of negative height and still its label }
    if not TyRectFIsValid(bounds) and not host.Caption.HasFixedAnchor then Continue;
    { THE HOST'S STROKE GROWS ITS RECT, as Path.getBoundingRect grows it: by
      the line width, or by at least five where nothing is filled, half on
      each side. A label outside a bordered cell sits past the border.
      [Batch 68] }
    inflate := 0;
    { THE HOST'S RECT AS LABELMANAGER TAKES IT -- Path.getBoundingRect, the
      stroke added to the width and half of it taken off the corner, in that
      order; the priority is its area [Batch 103] }
    hasHostRect := TyRectFIsValid(raw) or hasBox;
    if hasBox then hostRect := hbox
    else hostRect := TyXYWH(raw.Left, raw.Top, raw.Right - raw.Left, raw.Bottom - raw.Top);
    if (host.Style.StrokeWidthLogical > 0) and (host.Style.StrokeColor <> 0)
      and not host.Caption.HasHostBox then
    begin
      sw := host.Style.StrokeWidthLogical;
      if not host.Style.HasFill then sw := Max(sw, 5.0);
      sw := sw * scale;
      { the enter animation follows the shape's bounds grown by this }
      inflate := sw / 2;
      { a symbol's box has its stroke in it already }
      if not host.Caption.HasSymBox then
      begin
        bounds.Left := bounds.Left - sw / 2;
        bounds.Top := bounds.Top - sw / 2;
        bounds.Right := bounds.Right + sw / 2;
        bounds.Bottom := bounds.Bottom + sw / 2;
        hostRect.W := hostRect.W + sw;
        hostRect.H := hostRect.H + sw;
        hostRect.X := hostRect.X - sw / 2;
        hostRect.Y := hostRect.Y - sw / 2;
      end;
    end;

    { [R6-A] A CIRCULAR GRAPH'S TURNED LABEL (rotateLabel): the side's
      position on the symbol's rect, turned about its centre -- placed as a
      radial tree's (textConfig origin 'center') }
    if host.Caption.RingTurn and not host.Caption.HasFixedAnchor then
    begin
      if host.Caption.RingLeft then pos := tlpLeft else pos := tlpRight;
      hbox := TyXYWH(bounds.Left, bounds.Top, bounds.Right - bounds.Left, bounds.Bottom - bounds.Top);
      dist := spec.DistanceLogical * scale;
      TyLabelAnchorXYWH(hbox, pos, dist, 0, 0, x, y, ah, av);
      if spec.HasAlignH then ah := spec.AlignH;
      if spec.HasAlignV then av := spec.AlignV;
      TyLabelTurnedAnchor(hbox, pos, dist, -host.Caption.RingRad, x, y);
      host.Caption.HasFixedAnchor := True;
      host.Caption.FixedX := x;
      host.Caption.FixedY := y;
      host.Caption.FixedAH := ah;
      host.Caption.FixedAV := av;
      host.Caption.FixedInside := False;
      host.Caption.FixedRotationRad := -host.Caption.RingRad;
      host.Caption.FixedByConfig := 2;
      host.Caption.HasFixedPos := True;
      host.Caption.FixedPos := Ord(pos);
      host.Caption.FixedDist := dist;
      host.Caption.HasHostBox := True;
      host.Caption.HostBox := hbox;
      host.Caption.FixedInfl := inflate;
      host.Caption.FixedHalfW := hbox.W / 2 - inflate;
      hasBox := True;
    end;
    { THE BLOCK IS MEASURED WHERE IT IS LAID OUT, below; the one-run
      caption here }
    w := 0;
    h := 0;
    if not spec.Rt.Needed then
    begin
      AMeasurer.MeasureLine(host.Caption.Text, spec.FontName,
        spec.FontSizeLogical, spec.FontWeight, w, h);
      if (w <= 0) or (h <= 0) then Continue;
    end;

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
    if hasBox then
    begin
      if spec.AtXIsPercent then atX := spec.AtX * hbox.W;
      if spec.AtYIsPercent then atY := spec.AtY * hbox.H;
      TyLabelAnchorXYWH(hbox, pos, dist, atX, atY, x, y, ah, av);
      { A PIN'S INSIDE LABEL sits at 40 % of its rect's height, in its head
        (symbol.ts' SymbolClz.calculateTextPosition) [Batch 112] }
      if (pos = tlpInside) and host.Caption.HasSymBox and (host.Caption.LgSymbol = 'pin') then
        y := hbox.Y + hbox.H * Double(0.4);
    end
    else
      TyLabelAnchor(bounds, pos, dist, atX, atY, x, y, ah, av);
    if host.Caption.HasFixedAnchor then
    begin
      x := host.Caption.FixedX;
      y := host.Caption.FixedY;
      if host.Caption.FixedInside then pos := tlpInside else pos := tlpRight;
      ah := host.Caption.FixedAH;
      av := host.Caption.FixedAV;
    end;
    { A POLAR BAR'S SECTOR POSITION: the sector's own anchor and alignment
      (a built-in position took the path's rect above) [Batch 113] }
    if host.Caption.SecHas and host.Caption.SecAnchor then
    begin
      x := host.Caption.SecX;
      y := host.Caption.SecY;
      ah := host.Caption.SecAH;
      av := host.Caption.SecAV;
    end;
    { the alignment the position implies, before the style's }
    posAH := ah;
    posAV := av;
    { a fixed anchor's alignment is the mark's: it has already weighed the
      author's in (a sunburst flips it, a radial tree takes it) }
    if spec.HasAlignH and not host.Caption.HasFixedAnchor then ah := spec.AlignH;
    if spec.HasAlignV and not host.Caption.HasFixedAnchor then av := spec.AlignV;
    { OFFSET AFTER THE POSITION, and INSIDE THE ROTATION: zrender adds the
      offset to the point and sets the origin to minus it, so the label turns
      about the anchor and its offset runs along the turned axes. The
      transform's translation is where the painter hangs and turns the words,
      so it is taken whole -- getLocalTransform's own order of operations.
      [Batch 103: it was added in screen axes.] }
    baseX := x;
    baseY := y;
    offX := spec.OffsetXLogical * scale;
    offY := spec.OffsetYLogical * scale;
    if host.Caption.HasFixedAnchor then rot := host.Caption.FixedRotationRad
    else if host.Caption.SecHas then rot := host.Caption.SecRot
    else rot := spec.RotationRad;
    if host.Caption.HasFixedAnchor then
    begin
      { A MARK THAT FIXED ITS OWN ANCHOR set its own origin too (a radial
        tree's is the box's centre: textConfig.origin 'center'), and an
        origin of its own keeps zrender from moving it to minus the offset
        -- the offset is then a plain translation }
      x := baseX + offX;
      y := baseY + offY;
    end
    else if TyLabelLocalTransform(baseX + offX, baseY + offY, -offX, -offY, rot, 1, 1, m) then
    begin
      x := m[4];
      y := m[5];
    end
    else
    begin
      x := 0;
      y := 0;
    end;

    hostFill := host.Style.FillColor;
    hostHasFill := host.Style.HasFill;
    if host.Caption.HostTransparent then
    begin
      hostFill := 0;
      hostHasFill := True;
    end;
    pieces := nil;
    if spec.Rt.Needed then
    begin
      { THE BLOCK: the label's styles in its font, 'inherit' the host's
        colour (upstream's inheritColor is the bar's or symbol's visual
        colour), laid out about the anchor with the host's defaults --
        the automatic ink and halo, as updateInnerText hands them, and the
        alignment the position implies. A mark that fixed its own anchor
        fixed its alignment too. }
      autoSpec := spec;
      if host.Caption.HasFixedAnchor then
      begin
        autoSpec.Rt.Style.Align := rtaNone;
        autoSpec.Rt.Style.VAlign := rtvNone;
      end;
      { [R7-M] A TREEMAP'S LABEL ON ITS CELL: the box the cell's, laid out at
        the position's anchor by its alignment (the padding is the block's),
        and hung where the words' anchor is }
      if host.Caption.HasFixedBox then
      begin
        TyLabelFixBox(autoSpec, host.Caption);
        pieces := TyLabelBlockPieces(autoSpec, host.Caption.Text, hostFill,
          hostHasFill, host.Style.HasFill and (host.Style.FillGradient.Kind <> cgkNone),
          LabelInside(host, pos), host.Caption.FixedBoxAH, host.Caption.FixedBoxAV,
          scale, AMeasurer);
        TyRtShiftPieces(pieces, (host.Caption.FixedBoxX + offX - x) / scale,
          (host.Caption.FixedBoxY + offY - y) / scale);
      end
      else
        pieces := TyLabelBlockPieces(autoSpec, host.Caption.Text, hostFill,
          hostHasFill, host.Style.HasFill and (host.Style.FillGradient.Kind <> cgkNone),
          LabelInside(host, pos), ah, av, scale, AMeasurer);
      { [R7-L] A TEXT LAID OUT WHOLLY AT NaN (a size written as a word) draws
        nothing but is still upstream's label: the label layout weighs it by
        its box, which can hide the others. It stands as one undrawn rect,
        where its TSpans are bounded (style.x || 0). }
      if (Length(pieces) = 0) and (host.Caption.Text <> '')
        and TyRtHasStringSize(autoSpec.Rt.Style, autoSpec.Rt.Rich) then
      begin
        rtb := TyLabelBlockJsBox(autoSpec, host.Caption.Text, hostFill,
          hostHasFill, host.Style.HasFill and (host.Style.FillGradient.Kind <> cgkNone),
          LabelInside(host, pos), ah, av, scale, AMeasurer);
        SetLength(pieces, 1);
        pieces[0] := Default(TTyRtPiece);
        pieces[0].Kind := rpkRect;
        pieces[0].Placeholder := True;
        pieces[0].Line := -1;
        pieces[0].Token := -1;
        pieces[0].Opacity := 1;
        pieces[0].ImageOpacity := 1;
        if TyRtBoxIsFinite(rtb) then
        begin
          pieces[0].X := rtb.X;
          pieces[0].Y := rtb.Y;
          pieces[0].W := rtb.W;
          pieces[0].H := rtb.H;
        end;
      end;
      if Length(pieces) = 0 then Continue;
      { THE BOX IS THE UNION OF WHAT IT DRAWS, turned as it is drawn --
        zrender's getBoundingRect, which the label layout reads }
      box := TyRtDeviceBox(pieces, x, y, rot, scale);
    end
    else
    { The box the caption occupies, from the anchor and the pinned edge. This
      is what the companion's shape IS -- so the hit test and the ink describe
      the same rectangle, which is the whole reason the caption gets an entry
      of its own rather than a note on somebody else's. }
      box := TyAnchorBox(x, y, w, h, ah, av);
    { [R7-M] A TEXT SQUASHED ON Y BEFORE ITS TURN (a graph's edge label in a
      view scaled unequally): the whole map -- the turn, the device scale
      and the ratio -- and the box it lays the text's down as }
    hasAff := (host.Caption.FixedYScale > 0) and (host.Caption.FixedYScale <> 1);
    if hasAff then
    begin
      TyLabelAffineOf(x, y, rot, scale, host.Caption.FixedYScale, aff);
      if pieces <> nil then
        box := TyRtAffineBox(TyRtBounds(pieces), aff)
      else
        box := TyRtAffineBox(TyAnchorTextRect(w / scale, h / scale, ah, av), aff);
    end;

    cap := TyChartElement(TyShapeRect(box));
    cap.Caption := host.Caption;
    { WHAT THE LABEL LAYOUT READS [Batch 103] }
    if host.Caption.HasFixedAnchor and (host.Caption.FixedByConfig = 0) then
      cap.Caption.LmKind := 2
    else cap.Caption.LmKind := 1;
    cap.Caption.LmHostPlus1 := i + 1;
    cap.Caption.LmBaseX := baseX;
    cap.Caption.LmBaseY := baseY;
    cap.Caption.LmOffX := offX;
    cap.Caption.LmOffY := offY;
    { textConfig.rotation is there when the label wrote `rotate`; nought is
      the same turn either way }
    cap.Caption.LmHasAttachedRot := ((not host.Caption.HasFixedAnchor)
      or (host.Caption.FixedByConfig > 0)) and (rot <> 0);
    cap.Caption.LmAttachedRot := rot;
    cap.Caption.LmPosAH := posAH;
    cap.Caption.LmPosAV := posAV;
    { [R5-C] a fixed anchor's alignment is its style's only where upstream
      writes it there }
    cap.Caption.LmStyleHasAH := spec.HasAlignH
      or (host.Caption.HasFixedAnchor and (host.Caption.FixedByConfig = 0));
    cap.Caption.LmStyleHasAV := spec.HasAlignV
      or (host.Caption.HasFixedAnchor and (host.Caption.FixedByConfig <> 1));
    cap.Caption.LmStyleAH := ah;
    cap.Caption.LmStyleAV := av;
    cap.Caption.LmHasHostRect := hasHostRect;
    cap.Caption.LmHostRect := hostRect;
    cap.Caption.LmMarginType := spec.MarginType;
    for k := 0 to 3 do cap.Caption.LmMargin[k] := spec.MarginLogical[k] * scale;
    cap.Caption.LmTextW := w;
    cap.Caption.LmTextH := h;
    { A WRITTEN text border is counted in the text's rect; the automatic
      halo is not (Text.ts _updatePlainTexts) }
    cap.Caption.LmStrokeW := 0;
    cap.Caption.LmStrokeText := '';
    if spec.HasBorderColour and not spec.BorderColourNone and spec.HasBorderWidth
      and ((spec.BorderWidthLogical > 0) or spec.BorderWidthInf) then
    begin
      cap.Caption.LmStrokeW := spec.BorderWidthLogical * scale;
      { ([R7-AF] a string joins the rect's width and height; 'Infinity'
        takes its corner to -Infinity, its size to NaN) }
      cap.Caption.LmStrokeText := spec.BorderWidthText;
      if spec.BorderWidthInf then cap.Caption.LmStrokeW := Infinity;
    end;
    cap.Caption.LmInkFill := hostFill;
    cap.Caption.LmInkHasFill := hostHasFill;
    cap.Caption.LmInkGradient := host.Style.HasFill and (host.Style.FillGradient.Kind <> cgkNone);
    cap.Caption.LmInkInside := LabelInside(host, pos);
    { NO FILL AND NO STROKE. The rectangle is there so the pointer can find
      the words, not so anything is painted in it -- a filled one would draw a
      solid block behind every label. }
    { THE INK AND THE HALO, from the host's fill -- a pictorial bar's target
      counts as filled and transparent -- and from where the words ended up:
      a bar's `outside` is not inside. }
    TyLabelInk(spec, hostFill, hostHasFill,
      host.Style.HasFill and (host.Style.FillGradient.Kind <> cgkNone),
      LabelInside(host, pos), ink, stroke, strokeW);
    cap.Caption.Colour := ink;
    cap.Caption.StrokeColour := stroke;
    cap.Caption.StrokeWidthLogical := strokeW;
    { [R7-AF] A HALO OF 'Infinity': the canvas refuses the width and strokes
      at the one it had (the paint order settles it) [was: not stroked] }
    if spec.HasBorderWidth and spec.BorderWidthInf
      and (((stroke shr 24) <> 0) or (stroke = cTyCanvasColourLeft)) then
      cap.CanvasFlags := cap.CanvasFlags or cTyCanvasWidthLeft;
    { [R7-C] A PLAIN TEXT'S PEN GROWS ITS RECT by half its width on every
      side (TSpan.getBoundingRect), which is what the pointer is tested
      against (rectContain) -- the box above stays the words' own, as the
      layout reads it. [R7-F] A WRITTEN pen only: Text._updatePlainTexts
      gives the automatic halo a rect without it (usingDefaultStroke) [was:
      the halo grew it too] }
    if (pieces = nil) and (cap.Caption.LmStrokeW > 0) and (strokeW > 0)
      and ((stroke shr 24) <> 0) then
      cap.HitSlopLogical := strokeW / 2;
    cap.Caption.StrokeType := spec.BorderType;
    cap.Caption.StrokeDashOffset := spec.BorderDashOffset;
    TyLabelStampEmphasis(spec, hostFill, hostHasFill,
      host.Style.HasFill and (host.Style.FillGradient.Kind <> cgkNone),
      LabelInside(host, pos), cap.Caption);
    { createTextStyle: the label's own opacity, else the host's
      (defaultOpacity) [R2-I1: a written label.opacity was not read] }
    if spec.HasOpacity then cap.Style.Alpha := spec.Opacity
    else if spec.NoHostOpacity then cap.Style.Alpha := 1
    else cap.Style.Alpha := host.Style.Alpha;
    cap.Z := host.Z;
    { ABOVE ITS OWN MARK. Without the lift the two tie on (Z, Z2) and fall back
      to insertion order, which puts the caption on top anyway -- but only
      because it was appended later, and that is an accident rather than a
      rule. Saying it makes the ordering survive a future series `z`. }
    cap.Z2 := host.Z2 + spec.Z2Lift;
    if host.Caption.HasFixedZ2 then cap.Z2 := host.Caption.FixedZ2;
    { It answers for the same datum as the thing it names: hovering a bar's
      number has to report that bar. }
    cap.Silent := host.Silent;
    cap.Datum := host.Datum;
    { built for a state only: hidden until the state shows it [Batch 88];
      a racing bar's label with its ignored bar -- zrender draws no text of
      an ignored host -- though its count runs on (forceLabelAnimation)
      [Batch 135] }
    cap.Ignore := (not spec.Show) or (host.Ignore and (host.Anim.Role = carBar));
    { THE ENTER ANIMATION'S VIEW: a label of this datum, fading in, and --
      unless the mark fixed its own anchor -- hanging off its host as the
      host grows: zrender recomputes a text's place from its host's current
      rect every frame (Element.updateInnerText) [Batch 89] }
    cap.Anim := Default(TTyChartAnim);
    cap.Anim.Role := carLabel;
    cap.Anim.Series := host.Datum.SeriesIndex;
    cap.Anim.Index := host.Datum.DataIndex;
    { one of the datum's several labels, its own proxy [R2-A] }
    cap.Anim.Sub := host.Caption.LabelSub;
    { [F3d] the host's roam group: the label is carried with it }
    cap.Anim.InView := host.Anim.InView;
    cap.Anim.VSX := host.Anim.VSX;
    cap.Anim.VSY := host.Anim.VSY;
    cap.Anim.VX := host.Anim.VX;
    cap.Anim.VY := host.Anim.VY;
    { A LINES ROW'S LABEL rides its line's percent (Line.beforeUpdate): the
      line's geometry and placing with it [Batch 121] }
    if host.Anim.Role = carLinesLine then
    begin
      cap.Anim.Role := carLinesLabel;
      cap.Anim.G := host.Anim.G;
      { [spec 242] and its textConfig (rotate, offset) }
      cap.Anim.Vals := Copy(host.Anim.Vals, 0, Length(host.Anim.Vals));
    end;
    { [F3a] A GRAPH EDGE'S LABEL is the Line group's text: placed from the
      line's percent, faded on its own }
    if host.Anim.Role = carGraphEdge then
    begin
      cap.Anim := host.Anim;
      cap.Anim.Vals := Copy(host.Anim.Vals, 0, Length(host.Anim.Vals));
      cap.Anim.Role := carGraphEdgeLabel;
    end;
    { [F3a] A TREE NODE'S LABEL rides its group's slide: one hung off the
      symbol follows it as drawn, one placed on its own is carried }
    if (host.Anim.Role = carTreeNode) and host.Caption.HasFixedAnchor then
    begin
      cap.Anim.RideTree := True;
      cap.Anim.G := host.Anim.G;
    end;
    { [F3a] a treemap's breadcrumb item: disableLabelAnimation }
    cap.Anim.NoFade := host.Anim.Role = carTmCrumb;
    { [F3a] A SANKEY'S LABEL is under its host's clip paths -- the main
      group's enter clip -- and never fades (disableLabelAnimation) }
    if host.Anim.Role = carSankeyClip then
    begin
      cap.Anim.Role := carSankeyClip;
      cap.ClipHits := True;
      cap.Anim.Index := -1;
      cap.Anim.G := host.Anim.G;
    end;
    if not host.Caption.HasFixedAnchor then
    begin
      cap.Anim.HostPlus1 := i + 1;
      cap.Anim.LabelPos := Ord(pos);
      cap.Anim.LabelDist := dist;
      cap.Anim.LabelAtXPct := spec.AtXIsPercent;
      cap.Anim.LabelAtYPct := spec.AtYIsPercent;
      if spec.AtXIsPercent then cap.Anim.LabelAtX := spec.AtX
      else cap.Anim.LabelAtX := spec.AtX * scale;
      if spec.AtYIsPercent then cap.Anim.LabelAtY := spec.AtY
      else cap.Anim.LabelAtY := spec.AtY * scale;
      cap.Anim.LabelInflate := inflate;
      { a polar bar's sector position, past the thirteen [Batch 113] }
      if host.Caption.SecHas and host.Caption.SecAnchor then
      begin
        cap.Anim.LabelPos := 100 + host.Caption.SecPos;
        cap.Anim.LabelDist := host.Caption.SecDist;
      end;
    end;
    cap.Caption.FontName := spec.FontName;
    cap.Caption.FontSizeLogical := spec.FontSizeLogical;
    cap.Caption.FontWeight := spec.FontWeight;
    if spec.FontLeft then cap.CanvasFlags := cap.CanvasFlags or cTyCanvasFontLeft;
    cap.Caption.X := x;
    cap.Caption.Y := y;
    cap.Caption.AnchorH := ah;
    cap.Caption.AnchorV := av;
    { [R7-M] drawn under the whole map }
    cap.Caption.HasAffine := hasAff;
    if hasAff then
      for k := 0 to 5 do cap.Caption.Affine[k] := aff[k];
    cap.Caption.RotationRad := spec.RotationRad;
    if host.Caption.HasFixedAnchor then
      cap.Caption.RotationRad := host.Caption.FixedRotationRad;
    if host.Caption.SecHas then cap.Caption.RotationRad := host.Caption.SecRot;
    cap.Caption.Truncate := spec.Overflow = tloTruncate;
    cap.Caption.RtPieces := pieces;
    cap.Caption.RtEmph := nil;
    cap.Caption.RtScale := scale;
    { [R7-F] THE BOX IN THE LABEL'S OWN FRAME, about (X, Y) and unturned:
      where the label turns, zrender tests the point taken back into that
      frame (TSpan's and the plate's contain in local coordinates), not
      the turned box's upright bounds }
    cap.Caption.HasHitRel := True;
    { [R7-AF] A WORDS' RECT THAT JOINED A STRING (a written halo's width as a
      string, or 'Infinity') IS FOUND BY NOTHING: rectContain joins it again
      and the edge is no number, or left of the corner [was: found in the
      words' box] }
    if (pieces = nil) and (cap.Caption.LmStrokeText <> '') then
    begin
      cap.Caption.HitRelOwn := True;
      cap.Caption.HitRel := TyRectF(1e300, 1e300, -1e300, -1e300);
    end
    else if pieces <> nil then
    begin
      { a piece the pointer never finds is not in it }
      hitPieces := nil;
      for k := 0 to High(pieces) do
        if pieces[k].NoHit then cap.Caption.HitRelOwn := True
        else
        begin
          SetLength(hitPieces, Length(hitPieces) + 1);
          hitPieces[High(hitPieces)] := pieces[k];
        end;
      if cap.Caption.HitRelOwn then rtb := TyRtBounds(hitPieces)
      else rtb := TyRtBounds(pieces);
      cap.Caption.HitRel := TyRectF(rtb.X * scale, rtb.Y * scale,
        (rtb.X + rtb.W) * scale, (rtb.Y + rtb.H) * scale);
    end
    else
      cap.Caption.HitRel := TyRectF(box.Left - x, box.Top - y, box.Right - x, box.Bottom - y);
    { emphasis.label's own rich styles: laid out again [R5-B]; its font or
      box too, a one-run label's as well, and a data item's own over the
      series' [R5-F: a one-run label only changed its ink] }
    if (spec.EmphRtNode <> '') or (spec.EmphItemNode <> '') then
    begin
      if Length(pieces) = 0 then
      begin
        autoSpec := spec;
        if host.Caption.HasFixedAnchor then
        begin
          autoSpec.Rt.Style.Align := rtaNone;
          autoSpec.Rt.Style.VAlign := rtvNone;
        end;
      end;
      cap.Caption.RtEmph := TyLabelEmphPieces(autoSpec, host.Caption.Text,
        hostFill, hostHasFill, cap.Caption.EmphColour, cap.Caption.EmphStrokeColour,
        cap.Caption.EmphStrokeWidthLogical, ah, av, scale, AMeasurer);
    end;
    if (Length(pieces) > 0) and (Length(cap.Caption.RtEmph) = 0) then
      cap.Caption.RtEmph := TyRtReink(pieces, cap.Caption.EmphColour, True,
        cap.Caption.EmphStrokeColour, cap.Caption.EmphStrokeWidthLogical);
    { [R6-A] THE STATES' textConfig: a twin for every state, and every
      select-and-hover pair, whose label writes one -- a label on its host's
      textConfig only (a mark that fixed its own anchor, a polar bar's
      sector position, lay theirs out themselves) }
    cap.EmphTwin := nil;
    if host.Anim.Role in [carGraphEdge, carLinesLine] then
    begin
      for code := TyTwinEmphasis to TyTwinSelectBlur do
        if TyLabelStateCfgOf(spec, code, stCfg) then LineTwin(code, stCfg);
    end
    else if (not host.Caption.HasFixedAnchor and (not host.Caption.SecHas
        or (host.Anim.Role = carPolarBar)))
      or (host.Caption.HasFixedAnchor and ((host.Caption.FixedByConfig in [1, 2])
        or (host.Anim.Role in [carRiver, carTmRect])
        { a sankey link's curve: textConfig position 'inside' on its rect }
        or (host.Datum.IsEdge and (host.Anim.Role = carSankeyClip)))) then
    begin
      normalCfg := TyLabelStateCfgNormal(spec);
      if host.Caption.HasFixedAnchor then
      begin
        normalCfg.RotationRad := host.Caption.FixedRotationRad;
        { a box-turned label's normal position is the one its mark chose }
        if host.Caption.FixedByConfig = 2 then
          normalCfg.Position := TTyLabelPosition(host.Caption.FixedPos);
        if host.Anim.Role = carRiver then normalCfg.HasPosition := False;
      end;
      for code := TyTwinEmphasis to TyTwinSelectBlur do
        if TyLabelStateCfgOf(spec, code, stCfg) then Twin(code, stCfg);
    end;
    AList.Add(cap);
  end;
end;

end.
