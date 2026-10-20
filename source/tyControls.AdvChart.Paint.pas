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
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.ZrPath;

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
    { A WHOLE MATRIX instead of the five numbers, css px [Batch 122]: a
      graphic image drawn through its element's transform. With UnitImage
      the matrix places the image's unit square -- the renderer divides by
      the decoded image's own size. }
    HasMatrix, UnitImage: Boolean;
    Matrix: TTyMat2D;
  end;

  { A FILL THAT IS AN OBJECT, for a renderer handed colours one per datum
    [Batch 105]: a gradient, or a pattern, or neither (Present False). }
  TTyChartObjFill = record
    Present: Boolean;
    Gradient: TTyChartGradient;
    Pattern: TTyChartPattern;
  end;
  TTyChartObjFillArray = array of TTyChartObjFill;

  { A DECAL [Batch 131]: the pattern upstream GENERATES from a decal object
    (util/decal.ts createOrUpdatePatternFromDecal) and paints over a filled
    shape as a second fill -- the aria decals, and any itemStyle.decal.
    Held NORMALISED: the defaults filled (rect, symbolSize 1, keepAspect,
    the skin's colour, no background, dash 5 by 5, rotation 0, tiles of at
    most 512), the dash arrays ceiled and their odd lengths doubled, the
    symbols a list of rows. AdvChart.Decal makes one and lays its tile out;
    the renderer draws the tile and repeats it, turned by Rotation, in the
    canvas' space. }
  TTyChartDecal = record
    Present: Boolean;
    { a row of symbol names per symbol row }
    Symbols: array of TTyStringArray;
    SymbolSize: Double;
    KeepAspect: Boolean;
    Color: TTyChartColor;
    HasBackground: Boolean;
    Background: TTyChartColor;
    { the x dashes, one array per line; the y dashes }
    DashX: array of TTyDoubleArray;
    DashY: TTyDoubleArray;
    { radians, the pattern's own: zrender turns the repeat, not the symbols }
    Rotation: Double;
    MaxTileW, MaxTileH: Double;
    { [R2-F] the ground of an `empty*` symbol in the tile: upstream's
      neutral00, the skin's TyAdvChartDecal background here }
    EmptyFill: TTyChartColor;
  end;
  TTyChartDecalArray = array of TTyChartDecal;

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
    { A DECAL OVER THE FILL [Batch 131]: zrender's decal element -- the same
      path filled with the generated pattern, then its stroke again, drawn
      right after the element. Only where the element has a fill. }
    Decal: TTyChartDecal;
    { THE BOX A LOCAL GRADIENT NORMALISES AGAINST, when the builder knows it
      better than the shape does: upstream's el.getBoundingRect() is the PATH's
      box grown by the stroke, and a sector's path box is its arc's extent
      rather than the whole disc TyShapeBounds answers. Unset, the renderer
      takes the shape's bounds grown by the stroke itself. [Batch 105] }
    GradBoxSet: Boolean;
    GradBox: TTyXYWH;
    FillEvenOdd: Boolean;
    DashLogical: TTyDoubleArray;
    { [R2-I4] THE WORD THE DASH WAS WRITTEN AS: 0 lengths as they are (or
      none), 1 'dashed', 2 'dotted'. zrender keeps the word in the style and
      the canvas normalises it against the width it strokes at, frame by
      frame: where a state tweens the width, the dash follows it
      (TyDashOfWord). }
    DashWord: Byte;
    { [R2-F] the dash's phase, LOGICAL px: zrender's lineDashOffset }
    DashOffsetLogical: Double;
    Alpha: Double;                    // 0..1; 1 = opaque
  end;

  { Which datum an element belongs to. Both -1 together means "none" -- one
    place decides that, so the two can never disagree. }
  TTyChartTargetKind = (ctkSeries, ctkMarkPoint, ctkMarkLine, ctkMarkArea,
    ctkLegend,
    { [Batch 98] a legend's selector button (DataIndex the button) and its
      pager's page buttons (DataIndex 0 the previous, 1 the next): targets
      without ECData, so no chart mouse event names them }
    ctkLegendSelector, ctkLegendPager,
    { [Batch 122] a graphic component's element: ComponentIndex the
      component, DataIndex the element's serial in the view's last build;
      it has ECData's eventData, not a data index }
    ctkGraphic,
    { [Batch 147] a matrix cell -- its rect or its label: ComponentIndex the
      matrix, DataIndex the cell's serial in the matrix's last build
      (TTyMatrix.CellInfo); eventData when the matrix says triggerEvent,
      a component tooltip when the cell has words }
    ctkMatrix,
    { [Batch 148] a geo component's region: ComponentIndex the geo,
      DataIndex its region group (one per distinct name, MapDraw's order)
      -- a path or its text; the eventData of the group }
    ctkGeo,
    { [F4c] an axis' name or one of its labels, as a tooltip target
      (AxisBuilder's setTooltipConfig): ComponentIndex the grid * 1000 plus
      the axis among the grid's x then y axes, DataIndex the label's
      placement (-1 the name). Never in a paint list. }
    ctkAxisText);

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
    { [F4c] textBorderType as written ('' none) }
    LineDash: string;
    { [R2-F] textBorderDashOffset (a graphic text's lineDashOffset), when
      written: a block's goes to every piece (Text.ts: style.lineDashOffset) }
    HasLineDashOffset: Boolean;
    LineDashOffset: Double;
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
    { [R2-F] backgroundColor: {image}: the picture's source ('' none) --
      a ZRImage over the box, the box's own rect only for a lineHeight or a
      border (Text.ts _renderBackground) }
    BgImage: string;
    HasBorderColor: Boolean;
    BorderColor: TTyChartColor;
    BorderWidth: Double;
    { [R2-I2] the box's border dash as written (a label's borderType, a
      graphic text's borderDash; '' solid) and its phase (borderDashOffset) }
    BorderDash: string;
    BorderDashOffset: Double;
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
    { [F4c] a text's textBorderType as written ('' a solid halo) }
    LineDash: string;
    { [R2-F] its phase (lineDashOffset), px }
    LineDashOffset: Double;
    StrokeFirst: Boolean;
    { [R2-I2] a rect's border dash as written ('' solid) and its phase:
      _renderBackground's rectStyle.lineDash / lineDashOffset, the pattern
      made against LineWidth (doubled under a fill) }
    BorderDash: string;
    BorderDashOffset: Double;
    Radius: array[0..3] of Double;
    Opacity: Double;
    { [R2-F] a rect's picture (backgroundColor: {image}), drawn over the
      rect's border, at ImageOpacity: the style's opacity where the picture
      is the box's only element, else zrender's own 1 }
    Image: string;
    ImageOpacity: Double;
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
    { [F4c] the global textStyle's textBorderType ('' none) }
    LineDash: string;
    { [R2-F] and its textBorderDashOffset }
    HasLineDashOffset: Boolean;
    LineDashOffset: Double;
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
    { [R2-F] Y IS A BASELINE, not the box's edge AnchorV names: 1 the
      alphabetic one (where a canvas puts it), 2 the ideographic (the box's
      bottom); drawn from the anchor, X / Y, turned by RotationRad. An SVG
      map's text. }
    BaselineKind: Integer;
    { [R2-F] A TEXT UNDER A WHOLE AFFINE MAP: Affine takes the text's own
      frame (its anchor at the origin, FontSizeLogical in its units) to the
      list's px -- skew and unequal scales a turn and one size cannot say.
      Drawn upright on a bitmap of its own and laid down through the map. }
    HasAffine: Boolean;
    Affine: array[0..5] of Double;
    { [F4c] a text of several lines drawn line by line in its rect, each
      line aligned on its own (a visualMap's end text with a line break) }
    MultiLine: Boolean;
    { Set by the mark alongside Text, and read only for `position: outside`. }
    Outside: TTyCaptionOutside;
    { THE ITEM'S OWN LABEL: 1 + the raw row whose data item wrote a `label`
      of its own, read over its series' into the expansion's per-item table;
      0, the zero value, is "the series' label". [Batch 68] }
    ItemSpec: Integer;
    { [R2-A] ONE OF SEVERAL LABELS OF ONE DATUM (a radar item's points):
      1 + its place among them, carried to the label's Anim.Sub so each has
      its own animation proxy; 0, the zero value, the datum's one label }
    LabelSub: Integer;
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
    { [F3d] A FIXED ANCHOR HUNG ON THE HOST'S BOX (a radial tree's label):
      the position and the distance (device px) it was placed by, so a
      frame can place it again on the box as drawn }
    HasFixedPos: Boolean;
    FixedPos: Integer;
    FixedDist: Double;
    { ... and what the host's box is made of: the path's half width at rest
      (its scale on the canvas) and the stroke's half margin around it --
      strokeNoScale divides the line width by the line scale, so the margin
      stays while the path scales, and goes when the scale is nought
      (Path.getBoundingRect) }
    FixedHalfW, FixedInfl: Double;
    { A POLAR BAR'S LABEL [Batch 113, C4]: the sector calculates its own
      text position (sectorLabel.ts) -- SecAnchor: one of the sector
      positions, its anchor and the alignment it implies; else a built-in
      position on the path's rect (HostBox) -- and always its own turn
      (setSectorTextRotation, which a numeric `rotate` reaches as it is
      written, not in radians). The offset, the style's alignment and the
      ink run as for any label; SecInside is zrender's isInside for it
      (textConfig.inside, set for 'middle', else 'inside' in the word). }
    SecHas: Boolean;
    SecAnchor: Boolean;
    SecX, SecY: Double;
    SecAH: TTyTextAnchorH;
    SecAV: TTyTextAnchorV;
    SecRot: Double;
    SecInside: Boolean;
    { the sector position (Ord of PolarBar's TTySectorTextPos) and its
      distance, device px -- a label following its bar through the enter
      animation is placed again on the bar as drawn }
    SecPos: Integer;
    SecDist: Double;
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
    { [F4c] textBorderType as written -- 'dashed', 'dotted', a number or a
      JSON array of numbers; '' (or 'solid') a solid halo. normalizeLineDash
      turns it into a pattern against the halo's width when it is drawn. }
    StrokeType: string;
    { [R2-F] textBorderDashOffset: the dashes' phase, LOGICAL px }
    StrokeDashOffset: Double;
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
    carBoxplot,
    { [Batch 113, C4] a bar on a polar: its Sector or Sausage, the layout in
      G[0..5] (cx, cy, r0, r, the start and end angles), G[6] clockwise,
      G[7] radial (r grows, else the end angle), G[8] a sausage, G[9] of no
      sweep }
    carPolarBar,
    { [Batch 115, C6] a sunburst piece (Index its row, 0 the return circle):
      G[0..5] cx, cy, r0, r and the start and end angles as upstream holds
      them; a treemap rect (Index its row, Sub 0 the background, 1 the
      content): its frame comes from the treemap's own drill-down
      animation (the control's TreemapFrame), G[0..3] its local shape x, y,
      width, height }
    carSunPiece, carTmRect,
    { [Batch 118, C10] a themeRiver layer's polygon (Index its layer):
      G[0..3] its path's bounding rect in the view group's frame (x, y,
      width, height) -- what the enter clip is made from -- and G[4] the
      group's y }
    carRiver,
    { [Batch 120, C11] a chord's sector or ribbon: the view group's enter
      scale, one proxy for the series (Index -1); G[0..1] the group's
      origin, the centre option against the whole canvas }
    carChord,
    { [Batch 121, C12] a lines series' row: its line (one proxy, the line's
      shape.percent, drives the line, the two end symbols and the label),
      and its effect symbol (a looping clip of its own). G[0..5] the line's
      ends and control point, G[6] curved -- see AdvChart.Lines }
    carLinesLine, carLinesFrom, carLinesTo, carLinesLabel, carLinesEffect,
    { [Batch 128, C19] a parallel series' row: the data group's enter clip
      (one proxy per series, row -1), G[0..3] the parallel's rect, G[4] 1 on
      a horizontal layout (the width grows, else the height), G[5] 1 on the
      view's first render (only then does the clip start) }
    carParallelLine,
    { [F2a] a treemap's breadcrumb item (Series its series, Index its place
      from the root): a highDownDispatcher of no data -- its own emphasis and
      mouse events (selfType 'breadcrumb'), no tooltip }
    carTmCrumb,
    { [F3a] THE ENTER ANIMATIONS OF THE REST:
      carSankeyClip      every node rect, band and their labels of a
                         sankey: the main group's clip, one proxy per series
                         (Index -1); G[0..3] the group's bounding rect in its
                         own frame (x, y, width, height), G[4..7] the frame
                         (M0, M3, M4, M5: device = M0 * x + M4, M3 * y + M5)
      carPictorialGlyph  a pictorial bar's glyph path (Index its row, Sub
                         which glyph of the row, in the order upstream makes
                         them): G[0..1] the path's position (the pivot of
                         its scale), G[2..3] symbolScale -- upstream's scale
                         at rest
      carPictorialClip   a symbolClip glyph: the bundle's clip rect, one
                         proxy per row; G[0..3] the clip shape in the
                         bundle's frame, G[4..5] the bundle's position,
                         G[6] 1 where the plot clips too, G[7..10] the plot
      carGraphEdge       a graph edge's line, and its two end symbols and
      carGraphEdgeFrom   its label: one proxy per edge, the line's
      carGraphEdgeTo     shape.percent (Line.ts _createLine); the ends and
      carGraphEdgeLabel  the label are placed from it every frame
                         (Line.beforeUpdate). G[0..5] the trimmed ends and
                         control point in the line's frame, G[6] curved,
                         G[7..10] the frame (SX, SY, X, Y), G[11] the
                         inverse scale. The label fades on a proxy of its own
      carTreeNode        a tree node's symbol path: a symbol's pop-in
                         (G as carSymbol's, G[5..6] the group's place in the
                         view's frame, G[7..8] the view's scale); its group
                         slides from its source on a proxy of its own
      carTreeEdge        a tree edge (Index the node it belongs to): its
                         shape from its source on the proxy 'treeEdge' }
    carSankeyClip, carPictorialGlyph, carPictorialClip, carGraphEdge,
    carGraphEdgeFrom, carGraphEdgeTo, carGraphEdgeLabel, carTreeNode,
    carTreeEdge,
    { [F3c] ITEM PATHS NO ANIMATION OF THEIR OWN DRIVES, for the universal
      transition (AdvChart.AnimView):
      carMapRegion   a map series' region path (Index its row, Sub 0 the
                     polygons' compound, 1 the lines'): Pts its PathProxy
                     data before the roam, G[0..5] the roam's matrix, G[6] 1
                     where there is one
      carCustomPath  a custom series' path (Index the item's row, Sub its
                     place among the item's paths): Pts its PathProxy data in
                     its own frame, G[0..5] its computed transform, G[6] 1
                     where there is one, Base its shape for the dividers }
    carMapRegion, carCustomPath,
    { [R2-I8] carPictorialRect: a pictorial bar's bar rect -- the label's
      host, no ink (Index its row): G[0..3] its shape as upstream holds it
      (x, y, width, height; the length along the value axis signed), G[4] 1
      where the row does not animate. An update tweens its shape and the
      label laid out on it rides it }
    carPictorialRect);

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
    { A COMBINING ELEMENT'S CHILD in a frame: its index + 1 (0 for the
      element itself) [Batch 137] }
    UtPiece: Integer;
    { A LABEL LabelManager never fades: its host set disableLabelAnimation
      (a treemap's breadcrumb) [F3a] }
    NoFade: Boolean;
    { A LABEL PLACED ON ITS OWN THAT RIDES A TREE NODE'S GROUP (a radial
      tree's): G[5..9] the node's, as carTreeNode has them [F3a] }
    RideTree: Boolean;
    { [F3d] AN ELEMENT OF A ROAM GROUP -- a graph's main group on a view, a
      tree's view group -- whose transform an update tweens
      (applyViewCoordSysTransToElement with the series' model): the group's
      transform at rest, scale and translation, by which a frame carries what
      moves in the group to the canvas, and the group's transform now over it
      (the series' 'viewGroup' proxy) }
    InView: Boolean;
    VSX, VSY, VX, VY: Double;
    { [R2-C] AN ELEMENT OF A MAP'S TRANSFORM GROUP (MapDraw's, a geo
      component's or a map series' own): 0 none, else the map view's key --
      VSX .. VY its roam transform at rest, the 'geoView' proxy (series -1,
      index the key) the transform now }
    GeoView: Integer;
    LabelPos: Integer;
    LabelDist, LabelAtX, LabelAtY, LabelInflate: Double;
    LabelAtXPct, LabelAtYPct: Boolean;
    { [F3c] WHAT A UNIVERSAL TRANSITION READS OF AN ELEMENT whose role says
      nothing of it (AdvChart.AnimView), the role and its numbers left as
      they are. UtTag 0 none; 1 an item path: UtRow the item's row (where
      Index is the series'), UtOrder its place in the item's getPathList,
      UtData its PathProxy data in its own frame and UtM its computed
      transform (UtHasM), UtBase what the dividers read -- [1, x, y, w, h]
      a rect, [2, cx, cy, r0, r, startAngle, endAngle, clockwise] a sector,
      [3] a symbol made from Caption.LgSymbol / LgKeepAspect / LgG as a
      scatter's (createSymbol(-1, -1, 2, 2) under its size over two, turned,
      at its place) instead of UtData; UtNoScale its strokeNoScale. 2 a path
      of a series' view that is no item's: it fades in where a transition
      morphs (UtRow a number of its own, below -1). }
    UtTag: Integer;
    UtRow, UtOrder: Integer;
    UtData, UtBase: TTyDoubleArray;
    UtHasM, UtNoScale: Boolean;
    UtM: TTyMat2D;
    { [R2-I7] A markPoint's mpData id (carMarkPoint): SymbolDraw's update
      diffs the symbols by it -- the item's name, else the coordinate on
      the series' name dimension, a repeat '__ec__<n>', no name 'e' + two
      NULs + its place -- so a max that moves to another category is a
      symbol removed and a symbol added, not one that slides }
    Key: string;
  end;

  { [F6b] zrender's own contain over an element of an SVG map, in the
    element's coordinates: ToLocal the inverse of its transform, Box its
    getBoundingRect, the stroke (Stroke, LineWidth: the width over the line
    scale, at least strokeContainThreshold without a fill) and the fill over
    Path; RectOnly a text's or an image's rectContain (the box alone) }
  TTyZrHit = record
    Active: Boolean;
    Path: TTyZrPath;
    ToLocal: TTyMat2D;
    Box: TTyXYWH;
    Stroke: Boolean;
    LineWidth: Double;
    Fill: Boolean;
    RectOnly: Boolean;
    { which node of the SVG the element draws (the node + 1; 0: not one),
      and whether it is that node's label -- for a reader of the list }
    SvgNode: Integer;
    SvgLabel: Boolean;
  end;

  { [R2-I3] A TEXT AS ITS EMPHASIS STATE LAYS IT OUT: the caption and the
    box a marker's label takes while its item is hovered -- the emphasis
    label's style merged over the normal one and placed by the emphasis
    textConfig (setLabelStyle), built with the label }
  TTyEmphTwin = record
    Caption: TTyElementCaption;
    Shape: TTyChartShape;
    { [R2-I5] the state it is the text of: 0 emphasis, 1 blur, 2 select
      (TyTwinEmphasis...) -- setLabelStyle gives every special state its
      own style and words. An emphasis twin, where there is one, comes
      first. }
    State: Byte;
  end;
  TTyEmphTwinArray = array of TTyEmphTwin;

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
    { THE PORT'S OWN FORGIVENESS on top of it, LOGICAL px: a symbol's
      target grown past what upstream's Path.contain answers, so a mouse
      does not keep missing a four-pixel mark. A COARSE POINTER drops it --
      its fallback is upstream's answer to the same problem, and with both
      a mark would be found where upstream finds none. Zero everywhere
      else. [Batch 142] }
    HitPadLogical: Double;
    { A RECT HIT ON ITS STROKE ONLY, LOGICAL px: zrender's Path.contain of a
      path with no fill -- the stroke widened to at least
      strokeContainThreshold (5) -- so the rect answers within half of this
      of its outline and not inside. 0: the area, as every other element.
      A matrix cell written `silent: false` with no fill [Batch 147]. }
    HitStrokeBand: Double;
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
    { [F4c] the clip's corner radius, device px: a rounded rectangle where
      it is above nought (a visualMap bar's `r: 3` clip) }
    ClipRadius: Double;
    { A SECTOR CLIP, a polar line's (createPolarClipPath) [Batch 113]: the
      ink is cut to the ring between ClipR0 and ClipR1 over the sweep from
      ClipSA to ClipEA (radians clockwise on screen; ClipCW zrender's
      clockwise), about (ClipCX, ClipCY). Ignored by the hit test, as the
      rect is. }
    HasClipSector: Boolean;
    ClipCX, ClipCY, ClipR0, ClipR1, ClipSA, ClipEA: Double;
    ClipCW: Boolean;
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
    { PROGRESSIVE RENDERING [Batch 119]: the chunk (1-based) whose frame
      draws the element -- 0, the zero value, for one drawn with the update
      as every element was before -- the series slot it belongs to, and
      whether its chunk is still to come. A hidden element is neither drawn
      nor hit nor found for its datum: upstream has not made it yet.
      ProgRow is the view row of an element per datum, kept where the datum
      itself is not (an incremental candle has none). }
    ProgChunk: Integer;
    ProgSlot: Integer;
    ProgRow: Integer;
    ProgHidden: Boolean;
    { A GRAPHIC ELEMENT UNDER THE AXES [Batch 122]: zlevel 0 and z 0 or
      less, which upstream draws before the axes' z 0 (the component's
      group joins the zrender root first). The list's renderer skips it;
      the control paints it before the axes. Hit and ordered as any other. }
    GfxUnder: Boolean;
    { [Batch 148] UPSTREAM'S OWN Path.contain, where the element asks for
      it (a geo region): the full path, not the shape's points -- see
      TTyPathHit. The shape test is not consulted then. }
    PathHit: TTyPathHit;
    { [Batch 148] THE CLIP CUTS THE HIT TOO, as zrender's isHover asks
      every clip path up the element's parents -- for an element that
      says so (a geo region and its text). Everything else keeps the
      rule above: the hit test ignores the clip. }
    ClipHits: Boolean;
    { [F6a] zrender's Displayable.cursor, the CSS name the canvas takes
      while the pointer is over the element (Handler.mousemove's
      setCursor): '' is the prototype's 'pointer'. Set where upstream sets
      one -- an item's or its series' `cursor` option, 'move' on a node a
      drag takes, 'default' on a large batch or a pager button that cannot
      turn the page. Meaningless on a silent element, which is no target. }
    Cursor: string;
    { [F6b] AN SVG MAP'S ELEMENT: zrender's own contain in the element's
      own coordinates -- the pointer taken back through the inverse of
      its transform, then the box, the stroke and the fill over the
      PathProxy data (Path.contain), or the box alone (RectOnly: a text's
      or an image's rectContain). Neither PathHit nor the shape is asked
      then. }
    ZrHit: TTyZrHit;
    { [R2-I3] a marker label's emphasis twin (none, or one) }
    EmphTwin: TTyEmphTwinArray;
  end;
  PTyChartElement = ^TTyChartElement;

  TTyPaintList = class
  private
    FItems: array of TTyChartElement;
    FCount: Integer;
    FOrder: array of Integer;
    FOrdered: Boolean;
    { [R2-I6] FOrder right but for the elements in FDirty, whose z or z2
      changed since it was sorted (FOrdered is False then): EnsureOrder takes
      them out and merges them back in. The order is (z, z2, index), a
      strict total order, so this is the permutation the sort makes. }
    FPartial: Boolean;
    FDirty: array of Integer;
    FDirtyN: Integer;
    { [P2] the journal: what SetElement overwrote while it recorded }
    FJrOn, FJrSession, FJrOpened, FJrTainted: Boolean;
    FJrIdx: array of Integer;
    FJrOld: array of TTyChartElement;
    FJrN: Integer;
    FJrMark: array of Boolean;
    procedure MarkOrderDirty(AIndex: Integer);
    function RepairOrder: Boolean;
    procedure EnsureOrder;
    function Less(A, B: Integer): Boolean;
    procedure MergeSortOrder;
  public
    constructor Create;
    procedure Clear;
    { [R2-L] the elements from ACount on removed, the rest as they stand }
    procedure Truncate(ACount: Integer);
    { [R2-L] the journal keeps an element at AIndex or after it }
    function JournalHoldsFrom(AIndex: Integer): Boolean;
    function Add(const AElement: TTyChartElement): Integer;
    { [R2-H] Add, answering the new element's slot: a caller that builds the
      element further works on it there (valid until the next Add or Clear) }
    function AddRef(const AElement: TTyChartElement): PTyChartElement;
    { The element at its INSERTION index. }
    function Element(AIndex: Integer): TTyChartElement;
    { The same element BY REFERENCE, for a loop that only reads it [P2]:
      Element copies the whole record -- the shape's arrays, the caption's
      strings, through the RTTI -- and a list of a few thousand paid that on
      every pass that looked at it. Valid until the next Add or Clear. Z and
      Z2 are never written through it -- SetElement is what re-sorts the
      paint order -- and nothing is written through the shared empty element
      it answers out of range, as Element does. }
    function Ref(AIndex: Integer): PTyChartElement; inline;
    { THE JOURNAL [P2]. A build opens a session (JournalOpen) and closes it
      when it is done (JournalClose); inside it, while Record is on, the
      first SetElement of each index keeps what it overwrote. Writes inside
      the session with Record off are the build's own and are not kept. A
      SetElement after the session closed taints it: the list then holds a
      write a rewind would not know to replay. Rewind puts every kept
      element back and opens a new session. Clear forgets it all; a write
      through Ref is never journaled. What it is for: a frame whose states
      alone changed puts the list back to what the states were written over
      and writes them again, instead of building the whole list. }
    procedure JournalOpen;
    procedure JournalClose;
    procedure JournalRecord(AOn: Boolean);
    procedure JournalRewind;
    { a session closed since the last Clear, and not tainted }
    function JournalReady: Boolean;
    { [R2-P] how many elements the open session has kept -- one per index
      however often it was written (FOR THE TESTS) }
    property JournalCount: Integer read FJrN;
    { [R2-L] the K-th element the open session keeps: its index, and what
      it was before the session's first write to it }
    function JournalIndex(K: Integer): Integer;
    function JournalOld(K: Integer): PTyChartElement;
    { Replace it in place -- a state restyles an element after the list is
      built. The paint order is worked out again. }
    procedure SetElement(AIndex: Integer; const AElement: TTyChartElement);
    { The insertion index of the AIndex-th element in PAINT order (back first). }
    function PaintOrder(AIndex: Integer): Integer;
    { Topmost non-silent element containing the point, or -1. APad False
      leaves out the port's pad (HitPadLogical) -- a coarse pointer's direct
      test [Batch 142]. }
    function HitTestElement(AX, AY: Double; APPI: Integer;
      APad: Boolean = True): Integer;
    { Topmost element containing the point, a silent one too -- zrender's
      `topTarget` -- or -1 [Batch 127] }
    function TopElementAt(AX, AY: Double; APPI: Integer): Integer;
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

{ [R2-I6] The paint order repaired where an element's z or z2 moved
  (TTyPaintList.RepairOrder): a switch that turns it off -- sorted whole
  after every move, the reference -- and how many times it has. }
procedure TyPaintListRepairForTest(AOn: Boolean);
function TyPaintListRepairsForTest: Integer;

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
{ [Batch 148] one element at a point, as the list's hit test asks it: its
  clip first where it asks (ClipHits), then upstream's Path.contain where it
  carries one (PathHit), else the shape with ASlopPx }
function TyElementContains(const AEl: TTyChartElement; AX, AY, ASlopPx: Double): Boolean;
{ [F6b] an SVG map element's zrender contain (ZrHit) at a point }
function TyZrHitContains(const AHit: TTyZrHit; AX, AY: Double): Boolean;
{ [R2-I1] A SYMBOL'S TARGET in two parts [Batch 142]: the pen's own reach,
  upstream's (Path.contain strokes with the line width, max(width, 5)
  without a fill; nothing without a stroke), and the rest of the four
  logical px as the port's pad (HitPadLogical), which a coarse pointer
  leaves out. Moved here from the marks so a graph's and a tree's node take
  it too [they had a fixed 4 px of slop]. }
procedure TySymbolHitSlop(var AEl: TTyChartElement);
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

{ [R2-I4] normalizeLineDash of a WORD (TTyChartStyle.DashWord) against the
  width drawn now: 'dashed' [4w, 2w], 'dotted' [w]; nothing for 0 or for a
  width that is not above nought. }
function TyDashOfWord(AWord: Byte; AWidthLogical: Double): TTyDoubleArray;

const
  { [R2-I5] TTyEmphTwin.State }
  TyTwinEmphasis = 0;
  TyTwinBlur = 1;
  TyTwinSelect = 2;

{ [R2-I5] the index of ATwins' twin for the state AState (TyTwin...), -1
  where the state has none }
function TyEmphTwinAt(const ATwins: TTyEmphTwinArray; AState: Byte): Integer;

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
    if FItems[idx].Silent or FItems[idx].Ignore or FItems[idx].ProgHidden then Continue;
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
    if FItems[idx].Silent or FItems[idx].Ignore or FItems[idx].ProgHidden then Continue;
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
  FPartial := False;
  FDirtyN := 0;
  FJrOn := False;
  FJrSession := False;
  FJrOpened := False;
  FJrTainted := False;
  FJrN := 0;
  FJrOld := nil;
  FJrMark := nil;
end;

procedure TTyPaintList.Truncate(ACount: Integer);
var k, n: Integer;
begin
  if (ACount < 0) or (ACount >= FCount) then Exit;
  for k := ACount to FCount - 1 do FItems[k] := Default(TTyChartElement);
  { [R2-I6] an order (whole or to repair) loses the elements cut, and is
    as good for the rest }
  if FOrdered or FPartial then
  begin
    n := 0;
    for k := 0 to High(FOrder) do
      if FOrder[k] < ACount then
      begin
        FOrder[n] := FOrder[k];
        Inc(n);
      end;
    SetLength(FOrder, n);
    n := 0;
    for k := 0 to FDirtyN - 1 do
      if FDirty[k] < ACount then
      begin
        FDirty[n] := FDirty[k];
        Inc(n);
      end;
    FDirtyN := n;
  end;
  FCount := ACount;
end;

function TTyPaintList.JournalIndex(K: Integer): Integer;
begin
  if (K < 0) or (K >= FJrN) then Exit(-1);
  Result := FJrIdx[K];
end;

function TTyPaintList.JournalOld(K: Integer): PTyChartElement;
begin
  Result := @FJrOld[K];
end;

function TTyPaintList.JournalHoldsFrom(AIndex: Integer): Boolean;
var k: Integer;
begin
  Result := False;
  for k := 0 to FJrN - 1 do
    if FJrIdx[k] >= AIndex then Exit(True);
end;

procedure TTyPaintList.JournalOpen;
begin
  FJrOn := False;
  FJrSession := True;
  FJrOpened := False;
  FJrTainted := False;
  FJrN := 0;
  FJrOld := nil;
  FJrIdx := nil;
  FJrMark := nil;
  SetLength(FJrMark, FCount);
end;

procedure TTyPaintList.JournalClose;
begin
  if not FJrSession then Exit;
  FJrOn := False;
  FJrSession := False;
  FJrOpened := True;
end;

procedure TTyPaintList.JournalRecord(AOn: Boolean);
begin
  FJrOn := AOn and FJrSession;
end;

procedure TTyPaintList.JournalRewind;
var k: Integer;
begin
  for k := FJrN - 1 downto 0 do
  begin
    { [R2-I6] an element whose place in the order moves }
    if (FItems[FJrIdx[k]].Z <> FJrOld[k].Z) or (FItems[FJrIdx[k]].Z2 <> FJrOld[k].Z2) then
      MarkOrderDirty(FJrIdx[k]);
    FItems[FJrIdx[k]] := FJrOld[k];
  end;
  JournalOpen;
end;

function TTyPaintList.JournalReady: Boolean;
begin
  Result := FJrOpened and not FJrSession and not FJrTainted;
end;

function TTyPaintList.Add(const AElement: TTyChartElement): Integer;
begin
  if FCount = Length(FItems) then
    SetLength(FItems, Max(16, FCount * 2));
  FItems[FCount] := AElement;
  Result := FCount;
  Inc(FCount);
  { [R2-I6] merged into an order there is, as an element that moved }
  if FOrdered or FPartial then MarkOrderDirty(Result)
  else
  begin
    FPartial := False;
    FDirtyN := 0;
  end;
end;

function TTyPaintList.AddRef(const AElement: TTyChartElement): PTyChartElement;
var k: Integer;
begin
  { Add first, on its own: Add can grow FItems, and FItems[Add(...)] may
    take the array's address before the call moves it }
  k := Add(AElement);
  Result := @FItems[k];
end;

procedure TTyPaintList.SetElement(AIndex: Integer;
  const AElement: TTyChartElement);
begin
  if (AIndex < 0) or (AIndex >= FCount) then Exit;
  if FJrOn then
  begin
    { an element added after the journal opened is journaled too }
    if AIndex >= Length(FJrMark) then SetLength(FJrMark, FCount);
    if not FJrMark[AIndex] then
    begin
      FJrMark[AIndex] := True;
      if FJrN = Length(FJrIdx) then
      begin
        SetLength(FJrIdx, Max(16, FJrN * 2));
        SetLength(FJrOld, Length(FJrIdx));
      end;
      FJrIdx[FJrN] := AIndex;
      FJrOld[FJrN] := FItems[AIndex];
      Inc(FJrN);
    end;
  end
  else if FJrOpened and not FJrSession then
    FJrTainted := True;
  { [R2-I6] the order moves only where z or z2 does [was: sorted again
    after any write] }
  if (FItems[AIndex].Z <> AElement.Z) or (FItems[AIndex].Z2 <> AElement.Z2) then
    MarkOrderDirty(AIndex);
  FItems[AIndex] := AElement;
end;

var
  GRepairOff: Boolean = False;
  GRepairs: Integer = 0;

procedure TyPaintListRepairForTest(AOn: Boolean);
begin
  GRepairOff := not AOn;
end;

function TyPaintListRepairsForTest: Integer;
begin
  Result := GRepairs;
end;

procedure TTyPaintList.MarkOrderDirty(AIndex: Integer);
begin
  { a list never sorted since its last add is sorted whole anyway }
  if not (FOrdered or FPartial) then Exit;
  if (FDirtyN >= 256) or GRepairOff then
  begin
    { many: sorted whole }
    FOrdered := False;
    FPartial := False;
    FDirtyN := 0;
    Exit;
  end;
  if FDirtyN = Length(FDirty) then SetLength(FDirty, Max(16, FDirtyN * 2));
  FDirty[FDirtyN] := AIndex;
  Inc(FDirtyN);
  FOrdered := False;
  FPartial := True;
end;

function TTyPaintList.RepairOrder: Boolean;
var
  mark: array of Boolean;
  base: array of Integer;
  dirty: array of Integer;
  i, j, k, n, nb, t: Integer;
begin
  Result := False;
  SetLength(mark, FCount);
  { the moved ones, each once, in their own order (insertion: a few) }
  n := 0;
  SetLength(dirty, FDirtyN);
  for i := 0 to FDirtyN - 1 do
  begin
    t := FDirty[i];
    if (t < 0) or (t >= FCount) or mark[t] then Continue;
    mark[t] := True;
    j := n;
    while (j > 0) and Less(t, dirty[j - 1]) do
    begin
      dirty[j] := dirty[j - 1];
      Dec(j);
    end;
    dirty[j] := t;
    Inc(n);
  end;
  { the rest keep their order; the moved ones (and the added) merged in }
  SetLength(base, Length(FOrder));
  nb := 0;
  for i := 0 to High(FOrder) do
  begin
    t := FOrder[i];
    if (t < 0) or (t >= FCount) then Exit;
    if not mark[t] then
    begin
      base[nb] := t;
      Inc(nb);
    end;
  end;
  { every element once, or sorted whole }
  if nb + n <> FCount then Exit;
  SetLength(FOrder, FCount);
  i := 0;
  j := 0;
  for k := 0 to FCount - 1 do
    if (j < n) and ((i >= nb) or Less(dirty[j], base[i])) then
    begin
      FOrder[k] := dirty[j];
      Inc(j);
    end
    else
    begin
      FOrder[k] := base[i];
      Inc(i);
    end;
  Result := True;
end;

var
  GNoElement: TTyChartElement;

function TTyPaintList.Ref(AIndex: Integer): PTyChartElement;
begin
  if (AIndex < 0) or (AIndex >= FCount) then Exit(@GNoElement);
  Result := @FItems[AIndex];
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
  if FPartial and RepairOrder then
    Inc(GRepairs)
  else
  begin
    SetLength(FOrder, FCount);
    for i := 0 to FCount - 1 do
      FOrder[i] := i;
    MergeSortOrder;
  end;
  FOrdered := True;
  FPartial := False;
  FDirtyN := 0;
end;

function TTyPaintList.PaintOrder(AIndex: Integer): Integer;
begin
  EnsureOrder;
  if (AIndex < 0) or (AIndex >= FCount) then Exit(-1);
  Result := FOrder[AIndex];
end;

{ [Batch 148] one element at a point: its clip first where it asks
  (isHover's clip paths), then upstream's own Path.contain where it carries
  one, else the shape with its slop }
{ [F6b] Path.contain / Displayable.rectContain of an SVG map's element }
function TyZrHitContains(const AHit: TTyZrHit; AX, AY: Double): Boolean;
var x, y: Double; old: TFPUExceptionMask;
begin
  Result := False;
  if IsNan(AX) or IsNan(AY) then Exit;
  { upstream's arithmetic runs into nought divisors and not-a-numbers (a
    degenerate cubic's roots): JavaScript's quiet values, not traps }
  old := GetExceptionMask;
  SetExceptionMask(old + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    x := AHit.ToLocal[0] * AX + AHit.ToLocal[2] * AY + AHit.ToLocal[4];
    y := AHit.ToLocal[1] * AX + AHit.ToLocal[3] * AY + AHit.ToLocal[5];
    if not ((x >= AHit.Box.X) and (x <= AHit.Box.X + AHit.Box.W)
      and (y >= AHit.Box.Y) and (y <= AHit.Box.Y + AHit.Box.H)) then Exit;
    if AHit.RectOnly then Exit(True);
    if AHit.Stroke and TyZrContainStroke(AHit.Path, AHit.LineWidth, x, y) then Exit(True);
    if AHit.Fill then Result := TyZrContain(AHit.Path, x, y);
  finally
    TyZrRestoreFpu(old);
  end;
end;

procedure TySymbolHitSlop(var AEl: TTyChartElement);
const
  cSymbolTargetLogical = 4;
var reach: Double;
begin
  reach := 0;
  if AEl.Style.StrokeWidthLogical > 0 then
  begin
    if AEl.Style.HasFill then reach := AEl.Style.StrokeWidthLogical / 2
    else reach := Max(AEl.Style.StrokeWidthLogical, Double(5)) / 2;
  end;
  if reach > cSymbolTargetLogical then reach := cSymbolTargetLogical;
  AEl.HitSlopLogical := reach;
  AEl.HitPadLogical := cSymbolTargetLogical - reach;
end;

function TyElementContains(const AEl: TTyChartElement; AX, AY, ASlopPx: Double): Boolean;
begin
  if AEl.ClipHits and AEl.HasClip
    and not ((AX >= AEl.ClipRect.Left) and (AX <= AEl.ClipRect.Right)
      and (AY >= AEl.ClipRect.Top) and (AY <= AEl.ClipRect.Bottom)) then
    Exit(False);
  if AEl.ZrHit.Active then Result := TyZrHitContains(AEl.ZrHit, AX, AY)
  else if AEl.PathHit.Active then Result := TyPathHitContains(AEl.PathHit, AX, AY)
  else Result := TyShapeContains(AEl.Shape, AX, AY, ASlopPx);
end;

function TTyPaintList.HitTestElement(AX, AY: Double; APPI: Integer;
  APad: Boolean): Integer;
var
  i, idx: Integer;
  slop, half: Double;
  b: TTyRectF;
begin
  Result := -1;
  EnsureOrder;
  { REVERSE paint order: the last thing drawn is the top thing seen, and it is
    what the pointer must get. Walking forwards would report whatever is under
    the pile. }
  for i := FCount - 1 downto 0 do
  begin
    idx := FOrder[i];
    if FItems[idx].Silent or FItems[idx].Ignore or FItems[idx].ProgHidden then Continue;
    if (FItems[idx].HitStrokeBand > 0) and (FItems[idx].Shape.Kind = cskRect) then
    begin
      { the outline's band: inside the rect grown by half the band, not
        strictly inside the rect shrunk by it [Batch 147] }
      half := FItems[idx].HitStrokeBand / 2;
      if APPI > 0 then half := half * APPI / 96;
      b := FItems[idx].Shape.Bounds;
      if (AX >= b.Left - half) and (AX <= b.Right + half) and (AY >= b.Top - half)
        and (AY <= b.Bottom + half) and not ((AX > b.Left + half) and (AX < b.Right - half)
        and (AY > b.Top + half) and (AY < b.Bottom - half)) then
        Exit(idx);
      Continue;
    end;
    slop := FItems[idx].HitSlopLogical;
    if APad then slop := slop + FItems[idx].HitPadLogical;
    if APPI > 0 then slop := slop * APPI / 96;
    if TyElementContains(FItems[idx], AX, AY, slop) then
      Exit(idx);
  end;
end;

function TTyPaintList.TopElementAt(AX, AY: Double; APPI: Integer): Integer;
var
  i, idx: Integer;
  slop: Double;
begin
  Result := -1;
  EnsureOrder;
  for i := FCount - 1 downto 0 do
  begin
    idx := FOrder[i];
    if FItems[idx].Ignore or FItems[idx].ProgHidden then Continue;
    slop := FItems[idx].HitSlopLogical + FItems[idx].HitPadLogical;
    if APPI > 0 then slop := slop * APPI / 96;
    if TyElementContains(FItems[idx], AX, AY, slop) then
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

function TyEmphTwinAt(const ATwins: TTyEmphTwinArray; AState: Byte): Integer;
var i: Integer;
begin
  for i := 0 to High(ATwins) do
    if ATwins[i].State = AState then Exit(i);
  Result := -1;
end;

function TyDashOfWord(AWord: Byte; AWidthLogical: Double): TTyDoubleArray;
begin
  Result := nil;
  if not (AWidthLogical > 0) then Exit;
  case AWord of
    1:
      begin
        SetLength(Result, 2);
        Result[0] := 4 * AWidthLogical;
        Result[1] := 2 * AWidthLogical;
      end;
    2:
      begin
        SetLength(Result, 1);
        Result[0] := AWidthLogical;
      end;
  end;
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

initialization
  GNoElement.Datum := TyChartNoDatum;

end.