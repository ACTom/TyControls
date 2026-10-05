unit tyControls.AdvChart.Paint;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the paint list: what gets drawn, in what order, and which
  datum the pointer is over.

  ONE HIT-TEST PATH. Every chart element -- a bar, a line, a slice, a marker, a
  label background -- is added here, and the pointer question is answered by
  walking this list once. The old TTyChart kept paint and hit-test honest by
  having them call the same pure functions; that scales to three geometries.
  Here they share the same DATA (a TTyChartShape), so there is no second
  description that could drift, and there is exactly one place that decides what
  the pointer is over.

  ORDER. Sorted by (Z, Z2, insertion index), painted front-to-back in that order
  and hit-tested in REVERSE, so the topmost thing the eye sees is the thing the
  pointer gets. Z separates the layers a chart has (grid under series under
  markers under tooltip); Z2 orders within one of them; the insertion index makes
  the comparison TOTAL, which is what makes the sort stable without relying on
  the sort algorithm being stable.

  PURE: SysUtils, Math and the AdvChart units. Rendering lives in
  tyControls.AdvChart.Render, which is allowed to see the painter. That split is
  the point: ordering and hit-testing are where the defects are, and they are
  testable here without a graphics stack. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Shape;

type
  { $AARRGGBB, byte-identical to tyControls.Types' TTyColor. Declared again here
    rather than imported because that unit uses Graphics, and importing it would
    end this layer's independence from the LCL for the sake of a Cardinal. The
    render bridge casts. }
  TTyChartColor = type Cardinal;

  { A COLOUR THAT IS NOT ONE COLOUR.

    Upstream detects a gradient STRUCTURALLY -- by the presence of
    `colorStops` -- and never by the `type` field; `type` only chooses
    between the two shapes afterwards, and anything that is not exactly
    `'radial'`, a missing `type` included, draws LINEAR. }
  TTyChartGradKind = (cgkNone, cgkLinear, cgkRadial);

  TTyChartGradStop = record
    Offset: Double;
    Color: TTyChartColor;
  end;
  TTyChartGradStopArray = array of TTyChartGradStop;

  TTyChartGradient = record
    Kind: TTyChartGradKind;
    { LINEAR: (X,Y) to (X2,Y2), defaults 0,0 -> 1,0, which is LEFT TO RIGHT.
      Most of the gallery writes `x2: 0, y2: 1` and so never meets the
      default, which is exactly how a port comes to assume it is vertical.

      RADIAL: (X,Y) is the centre and R the radius, defaults 0.5/0.5/0.5.
      The inner radius is always nought and it is always a true circle. }
    X, Y, X2, Y2, R: Double;
    { False -- the default -- means the numbers are fractions of the
      element's OWN box. True means they are coordinates already. The field
      is spelled `global`; the `globalCoord` in the documentation is a
      constructor parameter name and does nothing in an option literal. }
    Global: Boolean;
    { In the order they were written. Upstream neither sorts, dedupes nor
      clamps them, and emits duplicate offsets itself. }
    Stops: TTyChartGradStopArray;
  end;

  { A COLOUR THAT IS AN IMAGE: zrender's ImagePatternObject -- `image`,
    `repeat`, `x`, `y`, `rotation`, `scaleX`, `scaleY` -- detected STRUCTURALLY by `image` the way
    a gradient is by `colorStops`. [Batch 105]

    THE IMAGE IS A STRING HERE AND NOTHING ELSE. Upstream also takes an
    HTMLImageElement or a canvas, which an option written as JSON cannot hold;
    of the strings, only a `data:` URL is drawn -- a URL upstream would fetch
    and paint once it arrived, and the port fetches nothing, so that pattern
    fills nothing, which is what upstream shows until the image is ready.

    The pattern lives in the CANVAS's space, not the element's: there is no
    box to normalise against, and createCanvasPattern sets the matrix
    translate(x, y) . rotate(rotation) . scale(scaleX, scaleY) on it. }
  TTyChartPattern = record
    Present: Boolean;
    Image: string;
    { `repeat || 'repeat'` as zrender hands it to createPattern }
    Repetition: string;
    X, Y, Rotation, ScaleX, ScaleY: Double;
  end;

  { A FILL THAT IS AN OBJECT, for a renderer handed colours one per datum
    [Batch 105]: a gradient, or a pattern, or neither (Present False). }
  TTyChartObjFill = record
    Present: Boolean;
    Gradient: TTyChartGradient;
    Pattern: TTyChartPattern;
  end;
  TTyChartObjFillArray = array of TTyChartObjFill;

  TTyChartElementStyle = record
    HasFill: Boolean;
    FillColor: TTyChartColor;
    { <= 0 means no stroke at all, the same rule TTyPainter.StrokePath follows:
      a theme that set a width of 0 meant "off", not "hairline". }
    StrokeWidthLogical: Double;
    StrokeColor: TTyChartColor;
    { A GRADIENT INSTEAD OF THE FILL COLOUR, when the author wrote one.
      FillColor still holds a solid -- the gradient's first stop -- because
      a legend swatch and a tooltip dot need one colour and upstream's own
      rule for producing it is `colorStops[0].color`. }
    FillGradient: TTyChartGradient;
    StrokeGradient: TTyChartGradient;
    { AN IMAGE INSTEAD OF THE FILL COLOUR [Batch 105]. FillColor holds what
      upstream's convertToColorString makes of it -- transparent. }
    FillPattern: TTyChartPattern;
    { THE BOX A LOCAL GRADIENT NORMALISES AGAINST, when the builder knows it
      better than the shape does: upstream's el.getBoundingRect() is the PATH's
      box grown by the stroke, and a sector's path box is its arc's extent
      rather than the whole disc TyShapeBounds answers. Unset, the renderer
      takes the shape's bounds grown by the stroke itself. [Batch 105] }
    GradBoxSet: Boolean;
    GradBox: TTyXYWH;
    FillEvenOdd: Boolean;
    DashLogical: TTyDoubleArray;
    Alpha: Double;                    // 0..1; 1 = opaque
  end;

  { Which datum an element belongs to. Both -1 together means "none" -- one
    place decides that, so the two can never disagree. }
  TTyChartTargetKind = (ctkSeries, ctkMarkPoint, ctkMarkLine, ctkMarkArea,
    ctkLegend,
    { [Batch 98] a legend's selector button (DataIndex the button) and its
      pager's page buttons (DataIndex 0 the previous, 1 the next): targets
      without ECData, so no chart mouse event names them }
    ctkLegendSelector, ctkLegendPager);

  TTyChartDatumRef = record
    SeriesIndex: Integer;
    { The row in the store's CURRENT VIEW -- the subscript Get(dim, index)
      wants, and the one a reader almost always means. }
    DataIndex: Integer;
    { The same row as it arrived, before any filter -- what SetCalculated
      addresses and what a callback reports.

      TWO FIELDS BECAUSE THERE ARE TWO ANSWERS, and one name was carrying
      both: cartesian marks put the VIEW index here and pie sectors the RAW
      one, so a reader taking DataIndex to the store was right on one series
      type and silently off by the dropped rows on the other. Nothing had
      noticed because the only row filtering in the control is the pie's.
      TTyChartCallbackParams has declared both fields since it was written. }
    RawDataIndex: Integer;
    { A GRAPH EDGE, whose rows are the LINKS and not the nodes. The two are
      numbered in the same space -- edge 0 and node 0 are both row 0 -- and
      upstream tells them apart by a data type on the element; without it a
      hover over the first edge described the first node. False for every
      other datum, which is what the zero value answers. }
    IsEdge: Boolean;
    { WHAT KIND OF THING WAS HIT, for the chart's mouse events [Batch 84]:
      a series item (the zero value, so every datum built before this field
      existed is one), a marker -- ComponentIndex its HOST SERIES, DataIndex
      its place in the marker's data -- or a legend item (ComponentIndex the
      legend, DataIndex the item). SeriesIndex stays -1 on all of these, so
      nothing that walks the list for a series' rows can take one for a
      series item; and HitTestAt answers series items only, so the hover,
      the tooltip and the emphasis never see them. }
    Kind: TTyChartTargetKind;
    ComponentIndex: Integer;
  end;

  { ---- zrender's text block [Batch 86] ---- }

  TTyRtAlign = (rtaNone, rtaLeft, rtaCenter, rtaRight);
  TTyRtVAlign = (rtvNone, rtvTop, rtvMiddle, rtvBottom);
  TTyRtWidthKind = (rtwNone, rtwNumber, rtwPercent, rtwAuto);
  TTyRtOverflow = (rtoNone, rtoTruncate, rtoBreak, rtoBreakAll);

  { ONE STYLE as zrender holds it after normalizeTextStyle. `Has` flags
    are JavaScript's `'x' in style`, which is what the fill and stroke
    fallbacks ask; a colour that is 'none'/'transparent' is Has with None. }
  TTyRtStyle = record
    FontFamily: string;
    FontSizePx: Double;
    FontWeight: Integer;
    FontItalic: Boolean;
    HasFill, FillNone: Boolean;
    Fill: TTyChartColor;
    HasStroke, StrokeNone: Boolean;
    Stroke: TTyChartColor;
    HasLineWidth: Boolean;
    LineWidth: Double;
    Align: TTyRtAlign;
    VAlign: TTyRtVAlign;
    HasLineHeight: Boolean;
    LineHeight: Double;
    WidthKind: TTyRtWidthKind;
    Width: Double;          // px, or the percentage for rtwPercent
    HasHeight: Boolean;
    Height: Double;
    HasPadding: Boolean;
    Padding: array[0..3] of Double;   // top, right, bottom, left
    HasBackground: Boolean;
    Background: TTyChartColor;
    HasBorderColor: Boolean;
    BorderColor: TTyChartColor;
    BorderWidth: Double;
    Radius: array[0..3] of Double;
    HasOpacity: Boolean;
    Opacity: Double;
    Overflow: TTyRtOverflow;
    LineOverflowTruncate: Boolean;
    HasEllipsis: Boolean;
    Ellipsis: string;
    MinChar: Integer;
    { the text shadow: a part of 0 is none, as zrender's `||` reads it }
    ShadowColor: TTyChartColor;
    HasShadowColor: Boolean;
    ShadowBlur, ShadowOffsetX, ShadowOffsetY: Double;
    { WHICH FONT PARTS THE STYLE NAMED ITSELF. A rich style's missing parts
      are filled from the block's font (or the global one, with
      richInheritPlainLabel off) by TyRtFinish, once the site knows the
      font it draws the block in; the engine reads only the four values.
      [Batch 86] }
    OwnFontFamily, OwnFontSize, OwnFontWeight: Boolean;
    { `'inherit'` (or `'auto'`) colours, and a free text's "no colour at all
      takes the inherit colour" -- bound by TyRtFinish to the site's inherit
      colour (a bar's visual colour, a legend item's), or dropped when there
      is none. The engine never sees them set. [Batch 86] }
    FillInherit, StrokeInherit, BackgroundInherit, BorderColorInherit: Boolean;
  end;

  TTyRtNamedStyle = record
    Name: string;
    Style: TTyRtStyle;
  end;
  TTyRtRich = array of TTyRtNamedStyle;

  { What the host hands the text: Element.updateInnerText's defaults. }
  TTyRtDefault = record
    HasFill: Boolean;
    Fill: TTyChartColor;
    HasStroke: Boolean;
    Stroke: TTyChartColor;
    AutoStroke: Boolean;
    Align: TTyRtAlign;
    VAlign: TTyRtVAlign;
  end;

  TTyRtPieceKind = (rpkRect, rpkText);
  TTyRtPiece = record
    Kind: TTyRtPieceKind;
    { -1: the block; else the token, as (line, index in the line) }
    Line, Token: Integer;
    X, Y, W, H: Double;        // a rect's box; a text's anchor in X, Y
    Drawn: Boolean;            // a rect with no fill and no stroke is not
    HasFill: Boolean;
    Fill: TTyChartColor;
    HasStroke: Boolean;
    Stroke: TTyChartColor;
    LineWidth: Double;
    StrokeFirst: Boolean;
    Radius: array[0..3] of Double;
    Opacity: Double;
    Text: string;
    TextAlign: TTyRtAlign;     // left/center/right; the baseline is middle
    FontFamily: string;
    FontSizePx: Double;
    FontWeight: Integer;
    HasShadow: Boolean;
    ShadowColor: TTyChartColor;
    ShadowBlur, ShadowOffsetX, ShadowOffsetY: Double;
    { A TEXT'S FILL OR STROKE THAT CAME FROM THE HOST'S DEFAULT (zrender's
      useDefaultFill, and the auto stroke), not from a style: what a hover
      re-inks, and what a free text whose ink is the skin's takes at paint
      time. [Batch 86] }
    DefaultFill, DefaultStroke: Boolean;
  end;
  TTyRtPieceArray = array of TTyRtPiece;


  { A TEXT'S STYLE AS THE SITE HOLDS IT BEFORE LAYOUT: zrender's block style
    and its rich styles, resolved from the option by AdvChart.RichStyle.
    Needed says the text takes the block path at all -- it is rich, or it
    has a box, a size or an overflow the plain caption cannot draw; a text
    without any of them keeps the one-run caption it always had. [Batch 86] }
  TTyRtBlockStyle = record
    Needed: Boolean;
    IsRich: Boolean;
    { richInheritPlainLabel as resolved: whether a rich style's missing font
      parts come from the block's font or from the global one }
    InheritPlain: Boolean;
    Style: TTyRtStyle;
    Rich: TTyRtRich;
  end;

  { THE ROOT'S SIDE OF A TEXT STYLE: ecModel.option.textStyle and the root
    richInheritPlainLabel, as values. Font is the chart's global text font --
    the skin's label font with the root textStyle over it -- which a rich
    style takes its missing parts from when it does not inherit the plain
    label's. [Batch 86] }
  TTyRtGlobal = record
    FontFamily: string;
    FontSizeLogical, FontWeight: Integer;
    HasColour: Boolean;
    Colour: TTyChartColor;
    HasStroke, StrokeNone: Boolean;
    Stroke: TTyChartColor;
    HasLineWidth: Boolean;
    LineWidth: Double;
    HasOpacity: Boolean;
    Opacity: Double;
    HasShadowColor: Boolean;
    ShadowColor: TTyChartColor;
    ShadowBlur, ShadowOffsetX, ShadowOffsetY: Double;
    { the root wrote richInheritPlainLabel: false -- the zero value is
      upstream's default, on }
    InheritPlainOff: Boolean;
  end;

  { A LAID-OUT BLOCK AND WHERE IT HANGS: the pieces in the text's own frame
    (CSS px), the anchor in device px, the turn (counter-clockwise, as the
    painter's), and device px per piece px. A piece at (lx, ly) lands at
    TyRtPoint. [Batch 86] }
  TTyRtDrawn = record
    Pieces: TTyRtPieceArray;
    X, Y, RotationRad, Scale: Double;
  end;

  { WORDS ON A MARK, and -- once the label pass has placed them -- everything
    needed to draw them.

    A MARK FILLS IN Text AND NOTHING ELSE. The label pass reads that, works
    out where the words go against the mark's own bounds, and emits a SECOND
    element with the rest filled in. So a caption with Text set and FontName
    empty is a REQUEST, and one with both is an ANSWER; the two are never the
    same element.

    Why the words are not a shape kind: AdvChart.Shape imports no measurer on
    purpose -- it is the pure hit-test layer and TyShapeBounds has to answer
    from the record alone. A text kind would ask it a question it cannot
    compute. The caption rides here instead, where resolved ink already is,
    and the entry the label pass emits carries a plain rect the shape layer
    understands completely. }
  { WHICH SIDE `outside` MEANS for the mark a caption names. A bar grows up or
    down (left or right) from what it stands on, and an outside label goes
    past the end it grows to -- a -3 hangs its number below the bar. coNone,
    the zero value, is every mark with no such end, whose outside is its top. }
  TTyCaptionOutside = (coNone, coTop, coBottom, coLeft, coRight);

  TTyElementCaption = record
    Text: string;
    { Set by the mark alongside Text, and read only for `position: outside`. }
    Outside: TTyCaptionOutside;
    { THE ITEM'S OWN LABEL: 1 + the raw row whose data item wrote a `label`
      of its own, read over its series' into the expansion's per-item table;
      0, the zero value, is "the series' label". [Batch 68] }
    ItemSpec: Integer;
    { THE RECT A LABEL IS PLACED AGAINST, when the mark knows it better than
      its shape's bounds do: zrender's layoutRect for a symbol is its UNIT
      path box grown by the stroke in unit space and carried through the
      symbol's whole transform -- rotation included, so a turned ellipse's
      label sits off the rotated box, not the ellipse. Kept as x, y, width,
      height, the form upstream adds to, so the anchor is exact. [Batch 73] }
    HasHostBox: Boolean;
    HostBox: TTyXYWH;
    { A SCATTER'S OR A LINE'S SYMBOL: the same rect (TySymbolLabelBox), for
      the label's anchor and the label layout's priority -- but the enter
      animation still follows the shape's own bounds as the symbol grows,
      so it is not a HostBox. [Batch 103] }
    HasSymBox: Boolean;
    SymBox: TTyXYWH;
    { AN ANCHOR THE MARK WORKED OUT ITSELF -- a radial tree's label, turned
      about its box's centre (textConfig origin 'center'), which no position
      in the expansion's table can say. The expansion takes it as given, with
      its position (for the ink), its alignment and its turn. [Batch 74] }
    HasFixedAnchor: Boolean;
    FixedX, FixedY: Double;
    { inside its host, for the ink bands, or outside it }
    FixedInside: Boolean;
    FixedAH: TTyTextAnchorH;
    FixedAV: TTyTextAnchorV;
    FixedRotationRad: Double;
    { THE CAPTION'S OWN z2, when the mark knows it: a treemap label's is the
      running maximum over the walk plus two, not its host's plus two.
      [Batch 76] }
    HasFixedZ2: Boolean;
    FixedZ2: Integer;
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    { THE INK, and its own field rather than the style's FillColor -- a caption
      has a rectangle so the pointer can find it, and that rectangle must not
      be painted. Borrowing FillColor and leaving HasFill off would work and
      would mean two things by one name. }
    Colour: TTyChartColor;
    { DEVICE px: the point the words hang off, and WHICH OF THEIR OWN EDGES is
      pinned to it. Both are needed and they are different questions -- `top`
      puts the anchor above the mark AND pins the caption's bottom edge there,
      and that pairing is what turns a distance into a gap instead of an
      overlap. }
    X, Y: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    RotationRad: Double;
    { A ROTATED CAPTION CANNOT BE TRUNCATED. The painter's rotated text entry
      takes an anchor rather than a rect, so it has nowhere to clip and no
      ellipsis; upstream truncates rotated labels and this does not. Stated
      here rather than left for a caller to discover. }
    Truncate: Boolean;
    { THE HALO: a stroke round the glyphs, drawn under them, LOGICAL px wide.
      Zero is none -- which is what every caption that never asks for one
      (a legend, a gauge, an axis) gets from the zero value. It does not
      widen the caption's box. }
    StrokeColour: TTyChartColor;
    StrokeWidthLogical: Double;
    { THE SAME THREE UNDER A HOVER, worked out when the caption is: the host's
      fill lifted (or the emphasis colour it declares) can land in another
      band, and the halo is the lifted fill. HasEmph False keeps the normal
      ones. }
    HasEmph: Boolean;
    EmphColour, EmphStrokeColour: TTyChartColor;
    EmphStrokeWidthLogical: Double;
    { Set by a mark whose label host is FILLED BUT TRANSPARENT -- a pictorial
      bar's target rect. Its ink is chosen as over a transparent fill, not as
      over no fill at all. }
    HostTransparent: Boolean;
    { THE BLOCK, when the label's style needed one (rich, a box, a size, an
      overflow): the pieces zrender would paint, in the caption's own frame
      about (X, Y) turned by RotationRad, in CSS px -- RtScale device px
      each. Empty is the one-run caption above. RtEmph is the same block in
      the hover's ink, where HasEmph. [Batch 86] }
    RtPieces: TTyRtPieceArray;
    RtEmph: TTyRtPieceArray;
    RtScale: Double;
    { A VALUE THAT COUNTS (label.valueAnimation, a bar's or a gauge's
      reading): the raw value (ValHas: there is one -- the next render's
      prevValue), and the words with #1 where the value goes -- upstream's
      text for an interpolated value; ValHasPrec False is the precision
      'auto'. ValAnim False, the zero value, counts nothing.
      [Batch 92, AN4] }
    ValAnim: Boolean;
    ValHas: Boolean;
    ValNum: Double;
    ValTpl: string;
    ValHasPrec: Boolean;
    ValPrec: Double;
    { ==== THE LABEL MANAGER'S VIEW of a series label [Batch 103] ====
      LmKind 0, the zero value, is a caption the label layout never sees
      (an axis', a legend's, a marker's, a funnel's, an end label); 1 a label
      its host's textConfig position places (ATTACHED); 2 one placed at
      label.x / y (a pie's, or a mark that fixed its own anchor). LmHostPlus1
      is the host's list index + 1 (0: found by the datum -- a pie slice). All
      geometry in device px:
        LmBaseX / Y   the point before the offset (the position's anchor, or
                      label.x / y);
        LmOffX / Y    the offset (textConfig.offset);
        LmHasAttachedRot / LmAttachedRot  the host's textConfig.rotation;
        LmPosAH / AV  the alignment the position implies (the host's default
                      text style);
        LmStyleHas*   whether the label's STYLE sets an alignment, and which;
        LmHostRect    the host's rect through its transform, as LabelManager
                      takes it (the priority is its area);
        LmMarginType / LmMargin  minMargin (1) or textMargin (2),
                      [top, right, bottom, left];
        LmTextW / H   a one-run caption's measured box, LmStrokeW the written
                      text border its rect counts;
        LmInk*        what the block was laid out over (to lay it out again).
      Set by the layout: LmFree (drawn where label.x / y put it, no longer
      following the host), LmOverlapHidden (hideOverlap hid it), LmEmphShow
      (and so the emphasis state shows it again), LmM (the transform, when
      LmHasM). }
    LmKind: Integer;
    { THE LABEL'S OWN TEXT (zrender's style.text) where the words drawn were
      cut to a width -- a pie label the overlap solver gave one; empty when
      Text is the label's text. What a labelLayout function is handed.
      [Batch 109] }
    LmText: string;
    LmHostPlus1: Integer;
    LmBaseX, LmBaseY, LmOffX, LmOffY: Double;
    LmHasAttachedRot: Boolean;
    LmAttachedRot: Double;
    LmPosAH: TTyTextAnchorH;
    LmPosAV: TTyTextAnchorV;
    LmStyleHasAH, LmStyleHasAV: Boolean;
    LmStyleAH: TTyTextAnchorH;
    LmStyleAV: TTyTextAnchorV;
    LmHasHostRect: Boolean;
    LmHostRect: TTyXYWH;
    LmMarginType: Integer;
    LmMargin: array[0..3] of Double;
    LmTextW, LmTextH, LmStrokeW: Double;
    LmInkFill: TTyChartColor;
    LmInkHasFill, LmInkGradient, LmInkInside: Boolean;
    LmFree, LmOverlapHidden, LmEmphShow: Boolean;
    LmHasM: Boolean;
    LmM: TTyMat2D;
    { ==== WHAT A LABEL LINE READS [Batch 112] ====
      On a HOST, how updateLabelLinePoints measures it (AdvChart.LabelGuide):
        LgKind    0 nothing, 1 a symbol, 2 a rect;
        LgSymbol  the symbol's zrender type ('circle', 'path://...') and
                  LgKeepAspect (symbolKeepAspect);
        LgG       a symbol's width, height, symbolRotate (degrees), offset x
                  and y, and the point x and y; a rect's x, y, width and height
                  (the signed layout) and its four corner radii.
      On a LINE, LgSmooth: the smooth its normal state draws (its Cmds hold
      the curves; a state may straighten it). }
    LgKind: Integer;
    { the colour a line takes when its lineStyle has none: the item's
      visual colour by the series' draw type }
    LgColor: TTyChartColor;
    LgSymbol: string;
    LgKeepAspect: Boolean;
    LgG: array[0..7] of Double;
    LgSmooth: Double;
  end;

  { WHAT AN ELEMENT IS TO THE ENTER ANIMATION [Batch 89, AN2]: which of
    upstream's animated elements it stands for, and the numbers upstream
    animates it in -- a bar's signed layout, a symbol's centre and half
    size, a line's clip rect. The zero value is carNone: not animated, which
    is every element nobody tagged.

    THE KEY is (Series, Index, the role's proxy): AdvChart.AnimView keeps one
    animated proxy per key, and the proxy outlives the list -- the list is
    rebuilt on every static render, the proxy only when the option is. }
  TTyChartAnimRole = (carNone, carBar, carSymbol, carLineSymbol, carLineRun,
    carLineArea, carSector, carFunnel, carGaugePointer, carGaugeProgress,
    carGaugeCap, carRadarLine, carRadarArea, carCandleBody, carCandleWickHigh,
    carCandleWickLow, carLabel, carGuide,
    { [Batch 92, AN4] a gauge's reading; an effectScatter's symbol and its
      ripples (Sub: which ripple); a markPoint's symbol; a markLine's
      segment, its two end symbols and its label (one proxy, the line's
      percent); a line's end label (driven by its clip) }
    carGaugeDetail, carEffectSymbol, carRipple, carMarkPoint, carMarkLine,
    carMarkLineFrom, carMarkLineTo, carMarkLineLabel, carEndLabel,
    { [Batch 99, AN6] a markPoint's label: it rides its symbol's group when
      a kept marker view moves it (the markPoint's proxy) }
    carMarkPointLabel,
    { [Batch 108] a boxplot's path: its fourteen points in Pts, the median's
      value coordinate in G[0], G[1] 1 on a horizontal layout }
    carBoxplot);

  TTyChartAnim = record
    Role: TTyChartAnimRole;
    { the series index, and the datum's view row (-1 for a whole series) }
    Series, Index: Integer;
    { the role's own numbers -- see AdvChart.AnimView for each }
    G: array[0..11] of Double;
    { A LINE'S RUN OR AREA [Batch 90]: which of the series' runs it is,
      upstream's whole-series layout points (flattened x, y, Float32 values,
      not-a-number where a row has no point), its stacked-on points (nil
      without an area -- upstream keeps `false` there), each row's
      [x, y, stacked-over] data values for a point added in an update, and
      smoothMonotone }
    Sub: Integer;
    Pts, Base, Vals: TTyDoubleArray;
    Mono: string;
    { A LABEL THAT FOLLOWS ITS HOST: the host's insertion index + 1 (0, the
      zero value, follows nothing -- a pie's or a funnel's words are placed
      absolutely, upstream too), and how it hangs off the host's rect: the
      position (Ord of the label unit's TTyLabelPosition), the distance, the
      array form's two numbers and whether each is a fraction, and how far
      the host's stroke grew the rect, all device px. }
    HostPlus1: Integer;
    LabelPos: Integer;
    LabelDist, LabelAtX, LabelAtY, LabelInflate: Double;
    LabelAtXPct, LabelAtYPct: Boolean;
  end;

  TTyChartElement = record
    Shape: TTyChartShape;
    Style: TTyChartElementStyle;
    { Empty on everything that has nothing to say, which is almost every
      element in a chart. }
    Caption: TTyElementCaption;
    Z, Z2: Integer;
    { Painted, never hit. Grid lines, split areas and axis furniture are silent:
      without this a gridline drawn over a bar would swallow the hover the bar
      was meant to get. }
    Silent: Boolean;
    { How far outside the shape still counts, LOGICAL px. A 6 px scatter marker
      needs a forgiving target; a line series needs a whole ribbon. }
    HitSlopLogical: Double;
    { WHETHER THE INK IS CUT, and the flag is not redundant beside the rect.

      AN ALL-ZERO RECT IS A LEGITIMATE EMPTY CLIP -- it removes the element
      entirely -- so no rectangle can stand for "no clip at all". Several
      elements in this library are built with Default() rather than through
      TyChartElement, and with the absence carried by the rect alone every one
      of them vanished: the legend drew nothing at all, and the failure was a
      picture with a hole in it rather than anything that named a clip. The
      zero value of the record has to mean "not clipped", and only a Boolean
      can say that.

      THE FIRST REAL CLIP IN THIS LAYER, and it is here because one series
      cannot be drawn without one: a pictorial bar filled to its value cuts a
      column of glyphs MID-GLYPH, which no intersection of rectangles can do.
      Everything else that looked like clipping in this port -- a bar against
      the plot, an axis label against its gutter -- was a rect meeting a rect,
      and those stay as they are, because a shape that is really smaller is
      better than a shape that is drawn smaller.

      THE HIT TEST IGNORES IT, deliberately and the same way upstream does:
      a pictorial bar keeps a separate unclipped rectangle as its hover
      target, because the thing a reader points at is the BAR, not whichever
      half of a glyph survived the cut. }
    HasClip: Boolean;
    ClipRect: TTyRectF;
    Datum: TTyChartDatumRef;
    { zrender's `ignore`: neither drawn nor hit. A label that only a state
      shows (`select.label.show` over a hidden normal label) is built
      ignored and the state flips it. [Batch 88] }
    Ignore: Boolean;
    { A PIE'S LABEL LINE, which carries its slice's datum (silent all the
      same) so the slice's select state can move it. [Batch 88] }
    IsGuide: Boolean;
    { the enter animation's view of it [Batch 89] }
    Anim: TTyChartAnim;
  end;

  TTyPaintList = class
  private
    FItems: array of TTyChartElement;
    FCount: Integer;
    FOrder: array of Integer;
    FOrdered: Boolean;
    procedure EnsureOrder;
    function Less(A, B: Integer): Boolean;
    procedure MergeSortOrder;
  public
    constructor Create;
    procedure Clear;
    function Add(const AElement: TTyChartElement): Integer;
    { The element at its INSERTION index. }
    function Element(AIndex: Integer): TTyChartElement;
    { Replace it in place -- a state restyles an element after the list is
      built. The paint order is worked out again. }
    procedure SetElement(AIndex: Integer; const AElement: TTyChartElement);
    { The insertion index of the AIndex-th element in PAINT order (back first). }
    function PaintOrder(AIndex: Integer): Integer;
    { Topmost non-silent element containing the point, or -1. }
    function HitTestElement(AX, AY: Double; APPI: Integer): Integer;
    { The same walk, reported as a datum. This and HitTestElement are ONE code
      path, so the element the caller highlights and the datum it reports can
      never be two different things. }
    function HitTest(AX, AY: Double; APPI: Integer): TTyChartDatumRef;
    { The topmost non-silent element drawn for one datum, or -1.

      THE INVERSE OF THE HIT TEST, and it exists for the same reason the hit
      test does: something that knows WHICH datum -- an axis trigger naming a
      whole column, a highlight action, a legend hover -- has to be able to
      find the ink that datum became. Reverse paint order again, so two series
      overlapping answer with the one on top.

      ARow < 0 matches any row of the series, which is how a run element -- one
      polyline standing for a whole line -- is found at all. }
    function IndexOfDatum(ASeries, ARow: Integer): Integer;
    { The same walk, but for the topmost element that actually CARRIES A
      COLOUR -- a fill or a real stroke.

      A DATUM IS USUALLY SEVERAL ELEMENTS and the topmost is not the one that
      says what colour it is: a funnel's band sits under its own label, and a
      label is a rectangle with no fill and no stroke whose whole job is to
      hold words. A caller asking "what colour is this datum" got the label
      and no answer at all. }
    function IndexOfDatumInk(ASeries, ARow: Integer): Integer;
    property Count: Integer read FCount;
  end;

function TyChartNoDatum: TTyChartDatumRef;
function TyChartDatum(ASeries, AData: Integer): TTyChartDatumRef; overload;
{ When the two spaces disagree -- a pie, whose sectors skip the rows a
  negative value removed and whose layout therefore counts in neither. }
function TyChartDatum(ASeries, AData, ARaw: Integer): TTyChartDatumRef; overload;
{ Link ARow of a graph series -- see TTyChartDatumRef.IsEdge. }
function TyChartEdgeDatum(ASeries, ARow: Integer): TTyChartDatumRef;
{ a marker or a legend item as a hit target [Batch 84] }
function TyChartComponentDatum(AKind: TTyChartTargetKind; AComponent,
  AIndex: Integer): TTyChartDatumRef;
function TyChartDatumValid(const ADatum: TTyChartDatumRef): Boolean;
{ A style with nothing switched on: no fill, no stroke, fully opaque. Callers
  turn on what they want rather than remembering to turn off what they do not. }
function TyChartStyle: TTyChartElementStyle;
{ An element carrying a shape, silent and datum-less until the caller says
  otherwise -- so a decoration that forgets to set Silent is at worst inert,
  never a thing that steals hovers from the data. }
function TyChartElement(const AShape: TTyChartShape): TTyChartElement;

{ WHERE A PIECE'S POINT (ALX, ALY) LANDS: the anchor plus the point scaled
  and turned counter-clockwise -- zrender's Text transform, as every child
  of the text shares it. [Batch 86] }
procedure TyRtPoint(AX, AY, ARotationRad, AScale, ALX, ALY: Double;
  out AGX, AGY: Double);

{ The one colour a gradient degrades to where only one will do -- a legend
  swatch, a tooltip marker. Upstream's own rule: the FIRST stop, not an
  average and not a midpoint; transparent when it has no stops. }
function TyGradientSolid(const AGrad: TTyChartGradient): TTyChartColor;

{ The canvas pattern's matrix: DOMMatrix translateSelf(x, y), rotateSelf(0, 0,
  rotation in degrees), scaleSelf(scaleX || 1, scaleY || 1), multiplied out as
  [a, b, c, d, e, f] -- in the chart's own (css) pixels. The rotation goes to
  degrees and back because zrender hands DOMMatrix degrees. [Batch 105] }
procedure TyPatternMatrix(const APat: TTyChartPattern; out AM: TTyDoubleArray);

{ getBoundingRect's stroke allowance: the path's box grown by the line width
  -- by max(width, 5) when the path has no fill, strokeContainThreshold -- half
  on each side. ALineWidth is in the box's own units. [Batch 105] }
function TyGrowByStroke(const ABox: TTyXYWH; AHasFill: Boolean;
  ALineWidth: Double): TTyXYWH;

{ A box as zrender's BoundingRect holds it: x, y and max - min. }
function TyRectToXYWH(const ARect: TTyRectF): TTyXYWH;

{ The same against a box held as x, y, width, height -- the numbers
  createLinearGradient is handed, with no right edge to subtract. }
procedure TyResolveGradientXYWH(const AGrad: TTyChartGradient;
  const ABox: TTyXYWH; out AX1, AY1, AX2, AY2, AR: Double);

{ The gradient's geometry in real coordinates, against the element's box.

  WHICH BOX: the ELEMENT's own, and nothing larger. Not the plot, not the
  series -- upstream takes `el.getBoundingRect()`, so every bar in a series
  ramps over its own rectangle and a two-stop gradient reads the same on all
  of them. A stacked segment likewise restarts per segment. }
procedure TyResolveGradient(const AGrad: TTyChartGradient;
  const ABox: TTyRectF; out AX1, AY1, AX2, AY2, AR: Double);

implementation

function TTyPaintList.IndexOfDatum(ASeries, ARow: Integer): Integer;
var i, idx: Integer;
begin
  Result := -1;
  if ASeries < 0 then Exit;
  EnsureOrder;
  for i := FCount - 1 downto 0 do
  begin
    idx := FOrder[i];
    if FItems[idx].Silent or FItems[idx].Ignore then Continue;
    if FItems[idx].Datum.SeriesIndex <> ASeries then Continue;
    { A ROW IS A DATUM'S, never a graph link's that happens to share its
      number. }
    if FItems[idx].Datum.IsEdge then Continue;
    if (ARow >= 0) and (FItems[idx].Datum.DataIndex <> ARow) then Continue;
    Exit(idx);
  end;
end;

function TTyPaintList.IndexOfDatumInk(ASeries, ARow: Integer): Integer;
var i, idx: Integer;
begin
  Result := -1;
  if ASeries < 0 then Exit;
  EnsureOrder;
  for i := FCount - 1 downto 0 do
  begin
    idx := FOrder[i];
    if FItems[idx].Silent or FItems[idx].Ignore then Continue;
    if FItems[idx].Datum.SeriesIndex <> ASeries then Continue;
    if FItems[idx].Datum.IsEdge then Continue;
    if (ARow >= 0) and (FItems[idx].Datum.DataIndex <> ARow) then Continue;
    if FItems[idx].Style.HasFill and (FItems[idx].Style.FillColor <> 0) then
      Exit(idx);
    if (FItems[idx].Style.StrokeWidthLogical > 0)
      and (FItems[idx].Style.StrokeColor <> 0) then Exit(idx);
  end;
end;

function TyChartNoDatum: TTyChartDatumRef;
begin
  Result.SeriesIndex := -1;
  Result.DataIndex := -1;
  Result.RawDataIndex := -1;
  Result.IsEdge := False;
  Result.Kind := ctkSeries;
  Result.ComponentIndex := -1;
end;

function TyChartComponentDatum(AKind: TTyChartTargetKind; AComponent,
  AIndex: Integer): TTyChartDatumRef;
begin
  Result.SeriesIndex := -1;
  Result.DataIndex := AIndex;
  Result.RawDataIndex := AIndex;
  Result.IsEdge := False;
  Result.Kind := AKind;
  Result.ComponentIndex := AComponent;
end;

function TyChartDatum(ASeries, AData: Integer): TTyChartDatumRef;
begin
  Result.SeriesIndex := ASeries;
  Result.DataIndex := AData;
  { THE SAME ROW IN BOTH SPACES, which is the truth for every builder that
    walks a store's view without the store having been filtered -- every
    cartesian series in the control. A builder whose two answers differ says
    so with the three-argument form; one that used this while they differed
    would be making a claim it had not checked. }
  Result.RawDataIndex := AData;
  Result.IsEdge := False;
  Result.Kind := ctkSeries;
  Result.ComponentIndex := -1;
end;

function TyChartDatum(ASeries, AData, ARaw: Integer): TTyChartDatumRef;
begin
  Result.SeriesIndex := ASeries;
  Result.DataIndex := AData;
  Result.RawDataIndex := ARaw;
  Result.IsEdge := False;
  Result.Kind := ctkSeries;
  Result.ComponentIndex := -1;
end;

function TyChartEdgeDatum(ASeries, ARow: Integer): TTyChartDatumRef;
begin
  Result.SeriesIndex := ASeries;
  Result.DataIndex := ARow;
  Result.RawDataIndex := ARow;
  Result.IsEdge := True;
  Result.Kind := ctkSeries;
  Result.ComponentIndex := -1;
end;

function TyChartDatumValid(const ADatum: TTyChartDatumRef): Boolean;
begin
  { Both or neither, decided in ONE place. A half-valid datum is the defect
    TyChartHitValid exists to prevent in the old chart. }
  Result := (ADatum.SeriesIndex >= 0) and (ADatum.DataIndex >= 0);
end;

function TyChartStyle: TTyChartElementStyle;
begin
  Result := Default(TTyChartElementStyle);
  Result.HasFill := False;
  Result.StrokeWidthLogical := 0;
  Result.FillEvenOdd := False;
  Result.DashLogical := nil;
  Result.Alpha := 1;
end;

function TyChartElement(const AShape: TTyChartShape): TTyChartElement;
begin
  { Default() rather than FillChar: the record now carries five managed
    fields across three levels, and zeroing a record by bytes is only safe
    while every one of them happens to be nil already. It is, here -- FPC
    initialises a managed result before the body runs -- but the safety is
    incidental and the next field added would not know that. }
  Result := Default(TTyChartElement);
  Result.Shape := AShape;
  Result.Style := TyChartStyle;
  Result.HasClip := False;
  Result.Z := 0;
  Result.Z2 := 0;
  Result.Silent := True;
  Result.HitSlopLogical := 0;
  Result.Datum := TyChartNoDatum;
end;

procedure TyRtPoint(AX, AY, ARotationRad, AScale, ALX, ALY: Double;
  out AGX, AGY: Double);
var c, s: Double;
begin
  if ARotationRad = 0 then
  begin
    AGX := AX + ALX * AScale;
    AGY := AY + ALY * AScale;
    Exit;
  end;
  c := Cos(ARotationRad);
  s := Sin(ARotationRad);
  AGX := AX + (ALX * c + ALY * s) * AScale;
  AGY := AY + (ALY * c - ALX * s) * AScale;
end;

{ ============================ TTyPaintList ============================ }

constructor TTyPaintList.Create;
begin
  inherited Create;
  FCount := 0;
  FOrdered := True;
end;

procedure TTyPaintList.Clear;
begin
  FItems := nil;
  FOrder := nil;
  FCount := 0;
  FOrdered := True;
end;

function TTyPaintList.Add(const AElement: TTyChartElement): Integer;
begin
  if FCount = Length(FItems) then
    SetLength(FItems, Max(16, FCount * 2));
  FItems[FCount] := AElement;
  Result := FCount;
  Inc(FCount);
  FOrdered := False;
end;

procedure TTyPaintList.SetElement(AIndex: Integer;
  const AElement: TTyChartElement);
begin
  if (AIndex < 0) or (AIndex >= FCount) then Exit;
  FItems[AIndex] := AElement;
  FOrdered := False;
end;

function TTyPaintList.Element(AIndex: Integer): TTyChartElement;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Datum := TyChartNoDatum;
    Exit;
  end;
  Result := FItems[AIndex];
end;

function TTyPaintList.Less(A, B: Integer): Boolean;
begin
  if FItems[A].Z <> FItems[B].Z then
    Exit(FItems[A].Z < FItems[B].Z);
  if FItems[A].Z2 <> FItems[B].Z2 then
    Exit(FItems[A].Z2 < FItems[B].Z2);
  { The insertion index makes the order TOTAL.

    Note honestly that it is REDUNDANT today: MergeSortOrder is stable (its merge
    prefers the left run on ties), so equal-z elements already keep their
    insertion order without this line. Mutation testing proved it -- replacing
    this with `False` leaves every test green, and no test could distinguish
    them, because the two produce identical output.

    It stays because the two guarantees protect different things. The sort's
    stability is a property of the sort; this is a property of the ORDER, and it
    is what keeps paint order from silently changing if the sort is ever swapped
    for a faster unstable one. What must not happen is someone reading the
    comment, believing this line is what pins the order, and deleting the merge
    sort's tie preference on that basis -- so: either alone is sufficient, both
    is deliberate, and neither is testable while the other stands. }
  Result := A < B;
end;

procedure TTyPaintList.MergeSortOrder;
var
  buf: array of Integer;

  procedure MergeRun(ALo, AMid, AHi: Integer);
  var
    i, j, k: Integer;
  begin
    i := ALo;
    j := AMid;
    for k := ALo to AHi - 1 do
    begin
      if (i < AMid) and ((j >= AHi) or (not Less(FOrder[j], FOrder[i]))) then
      begin
        buf[k] := FOrder[i];
        Inc(i);
      end
      else
      begin
        buf[k] := FOrder[j];
        Inc(j);
      end;
    end;
    for k := ALo to AHi - 1 do
      FOrder[k] := buf[k];
  end;

  procedure SortRun(ALo, AHi: Integer);
  var
    mid: Integer;
  begin
    if AHi - ALo < 2 then Exit;
    mid := (ALo + AHi) div 2;
    SortRun(ALo, mid);
    SortRun(mid, AHi);
    MergeRun(ALo, mid, AHi);
  end;

begin
  { Merge sort rather than quicksort: chart elements arrive very nearly in z
    order already, which is quicksort's quadratic case with a naive pivot. }
  SetLength(buf, FCount);
  SortRun(0, FCount);
end;

procedure TTyPaintList.EnsureOrder;
var
  i: Integer;
begin
  if FOrdered then Exit;
  SetLength(FOrder, FCount);
  for i := 0 to FCount - 1 do
    FOrder[i] := i;
  MergeSortOrder;
  FOrdered := True;
end;

function TTyPaintList.PaintOrder(AIndex: Integer): Integer;
begin
  EnsureOrder;
  if (AIndex < 0) or (AIndex >= FCount) then Exit(-1);
  Result := FOrder[AIndex];
end;

function TTyPaintList.HitTestElement(AX, AY: Double; APPI: Integer): Integer;
var
  i, idx: Integer;
  slop: Double;
begin
  Result := -1;
  EnsureOrder;
  { REVERSE paint order: the last thing drawn is the top thing seen, and it is
    what the pointer must get. Walking forwards would report whatever is under
    the pile. }
  for i := FCount - 1 downto 0 do
  begin
    idx := FOrder[i];
    if FItems[idx].Silent or FItems[idx].Ignore then Continue;
    if APPI > 0 then
      slop := FItems[idx].HitSlopLogical * APPI / 96
    else
      slop := FItems[idx].HitSlopLogical;
    if TyShapeContains(FItems[idx].Shape, AX, AY, slop) then
      Exit(idx);
  end;
end;

function TTyPaintList.HitTest(AX, AY: Double; APPI: Integer): TTyChartDatumRef;
var
  idx: Integer;
begin
  idx := HitTestElement(AX, AY, APPI);
  if idx < 0 then
    Result := TyChartNoDatum
  else
    Result := FItems[idx].Datum;
end;

function TyGradientSolid(const AGrad: TTyChartGradient): TTyChartColor;
begin
  if Length(AGrad.Stops) = 0 then Exit(0);
  Result := AGrad.Stops[0].Color;
end;

procedure TyPatternMatrix(const APat: TTyChartPattern; out AM: TTyDoubleArray);
var deg, rad, cs, sn, sx, sy: Double;
begin
  { `p.rotation || 0` and friends: NaN and 0 fall back alike }
  deg := APat.Rotation;
  if IsNan(deg) then deg := 0;
  deg := deg * (180 / Pi);
  rad := deg * Pi / 180;
  cs := Cos(rad);
  sn := Sin(rad);
  sx := APat.ScaleX;
  if IsNan(sx) or (sx = 0) then sx := 1;
  sy := APat.ScaleY;
  if IsNan(sy) or (sy = 0) then sy := 1;
  SetLength(AM, 6);
  AM[0] := sx * cs;
  AM[1] := sx * sn;
  AM[2] := -sy * sn;
  AM[3] := sy * cs;
  AM[4] := APat.X;
  if IsNan(AM[4]) then AM[4] := 0;
  AM[5] := APat.Y;
  if IsNan(AM[5]) then AM[5] := 0;
end;

function TyGrowByStroke(const ABox: TTyXYWH; AHasFill: Boolean;
  ALineWidth: Double): TTyXYWH;
var w: Double;
begin
  Result := ABox;
  if not (ALineWidth > 0) then Exit;
  w := ALineWidth;
  if (not AHasFill) and (w < 5) then w := 5;
  { width first, then x -- rectStroke.width += w; rectStroke.x -= w / 2 }
  Result.W := ABox.W + w;
  Result.H := ABox.H + w;
  Result.X := ABox.X - w / 2;
  Result.Y := ABox.Y - w / 2;
end;

function TyRectToXYWH(const ARect: TTyRectF): TTyXYWH;
begin
  Result.X := ARect.Left;
  Result.Y := ARect.Top;
  Result.W := ARect.Right - ARect.Left;
  Result.H := ARect.Bottom - ARect.Top;
end;

function SafeNum(AValue, ADefault: Double): Double;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit(ADefault);
  Result := AValue;
end;

procedure TyResolveGradient(const AGrad: TTyChartGradient;
  const ABox: TTyRectF; out AX1, AY1, AX2, AY2, AR: Double);
begin
  TyResolveGradientXYWH(AGrad, TyRectToXYWH(ABox), AX1, AY1, AX2, AY2, AR);
end;

procedure TyResolveGradientXYWH(const AGrad: TTyChartGradient;
  const ABox: TTyXYWH; out AX1, AY1, AX2, AY2, AR: Double);
var w, h: Double;
begin
  w := ABox.W;
  h := ABox.H;
  if AGrad.Kind = cgkRadial then
  begin
    AX1 := AGrad.X;
    AY1 := AGrad.Y;
    AR := AGrad.R;
    if not AGrad.Global then
    begin
      AX1 := AX1 * w + ABox.X;
      AY1 := AY1 * h + ABox.Y;
      { THE RADIUS SCALES BY THE SMALLER SIDE, so a radial gradient is a
        circle on any box rather than an ellipse squeezed into it. }
      AR := AR * Min(w, h);
    end;
    { The sanity fallbacks run AFTER the multiply and are ABSOLUTE, so a
      degenerate box leaves a half-pixel dot rather than half a box. A
      NEGATIVE radius takes the same fallback. }
    AX1 := SafeNum(AX1, 0.5);
    AY1 := SafeNum(AY1, 0.5);
    if (AR < 0) or IsNan(AR) or IsInfinite(AR) then AR := 0.5;
    AX2 := AX1;
    AY2 := AY1;
    Exit;
  end;
  AX1 := AGrad.X;
  AY1 := AGrad.Y;
  AX2 := AGrad.X2;
  AY2 := AGrad.Y2;
  if not AGrad.Global then
  begin
    { EACH AXIS ON ITS OWN -- x by the width and y by the height. The
      anisotropy is the point: it is how `0,0 -> 0,1` is vertical whatever
      the box's shape, and Sankey exploits it deliberately. }
    AX1 := AX1 * w + ABox.X;
    AX2 := AX2 * w + ABox.X;
    AY1 := AY1 * h + ABox.Y;
    AY2 := AY2 * h + ABox.Y;
  end;
  AX1 := SafeNum(AX1, 0);
  AX2 := SafeNum(AX2, 1);
  AY1 := SafeNum(AY1, 0);
  AY2 := SafeNum(AY2, 0);
  AR := 0;
end;

end.
