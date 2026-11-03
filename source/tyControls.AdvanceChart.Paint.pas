unit tyControls.AdvanceChart.Paint;
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

  PURE: SysUtils, Math and the AdvanceChart units. Rendering lives in
  tyControls.AdvanceChart.Render, which is allowed to see the painter. That split is
  the point: ordering and hit-testing are where the defects are, and they are
  testable here without a graphics stack. }
interface
uses SysUtils, Math, tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape,
  tyControls.AdvanceChart.ZrPath, tyControls.AdvanceChart.JsMath;

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
    { [spec 242] A UNIT IMAGE'S SOURCE RECT (zrender's brushImage, sx / sy /
      sWidth / sHeight): the part of the image, in its natural px, that the
      unit square shows -- drawImage's nine-argument form. What falls off
      the image is nothing, as a canvas clips the source. CropOk False:
      drawImage was handed a number that is none, and draws nothing. }
    HasCrop, CropOk: Boolean;
    CropX, CropY, CropW, CropH: Double;
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
    symbols a list of rows. AdvanceChart.Decal makes one and lays its tile out;
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
    { [R5-D] zrender's lineCap / lineJoin / miterLimit where a builder sets
      them (a brush cover's): 0 is the canvas default -- 'butt', 'miter' --
      and a MiterLimit of 0 is the default 10 }
    LineCap: Byte;                    // 0 butt, 1 round, 2 square
    LineJoin: Byte;                   // 0 miter, 1 round, 2 bevel
    MiterLimit: Double;
    { [R5-A] THE SHADOW, zrender's style.shadowBlur / shadowOffsetX / shadowOffsetY
      (LOGICAL px) and shadowColor: cast by the fill and by the stroke, each its own, under
      them (the canvas' shadow; the painter's SetShadow). Drawn where the colour has alpha
      and any of the three is not nought -- the zero value is none. A decal over the fill
      casts none (zrender's decal element nulls it). }
    ShadowBlur, ShadowOffsetX, ShadowOffsetY: Double;
    ShadowColor: TTyChartColor;
    { [R6-C] zrender's style.fillOpacity / strokeOpacity where a style writes
      them (a custom series' or a graphic element's path): the canvas'
      globalAlpha for the fill, for the pen, over Alpha. Has* False is 1 --
      the zero value draws as before }
    HasFillOpacity, HasStrokeOpacity: Boolean;
    FillOpacity, StrokeOpacity: Double;
    { [R6-F] zrender's style.strokeFirst: the pen before the fill, which then
      covers its inner half (a text's plate with a fill and a border) --
      False, the zero value, the fill first }
    StrokeFirst: Boolean;
    { [R5-A] zrender's style.blend, the canvas' globalCompositeOperation: a
      series' blendMode on every element its view renders (echarts'
      updateBlend) -- '' source over }
    Blend: string;
    { [R6-E] A PEN IN THE SHAPE'S OWN FRAME: the scale the canvas' transform
      puts on the stroke of a path that is no strokeNoScale -- a pictorial
      bar's glyph, built at the pattern size and scaled to its box (useStyle
      drops the strokeNoScale createPath gave it). The width, the dash and
      its phase above are the style's, as upstream holds them (a state sets
      and tweens them as they are); the renderer draws them times this.
      sqrt|det| of the transform, one number for both axes: zrender's line
      scale, where the canvas strokes a stretched pen. 0, the zero value,
      and 1 are none. }
    PenScale: Double;
    { [R7-P] THE PEN STRETCHED WITH THE SHAPE. The canvas strokes a path in
      the space its transform maps, so where that transform scales x and y
      unequally (or skews) the pen is the transform's linear part times a
      round pen -- an elliptical one -- and a dash is measured along the path
      in that space: a symbol of symbolSize [w, h] (Symbol.ts scales its unit
      path by half the size, strokeNoScale dividing the width by the line
      scale), a graph under a view whose scaleY is not its scaleX, a graphic
      element's own scaleX / scaleY, a pictorial glyph, an SVG map's shape.
      HasPenMap with PenMap (x' = PenMap[0] x + PenMap[2] y, y' = PenMap[1] x
      + PenMap[3] y; [4], [5] unread): the pen drawn is PenMap times a round
      pen of the width above (times PenScale where there is one), the dash
      and its phase lengths in the same space. Set only where the map is no
      turn and uniform scale (TyStyleSetPenMap), which a round pen draws
      alike -- False, the zero value, is the round pen. The hit test asks
      the same pen (a symbol's own frame, a ZrHit's local path, or the path
      taken back through the map). }
    HasPenMap: Boolean;
    PenMap: TTyMat2D;
    { [R7-F] WHAT THE HIT TEST ASKS OF THE STYLE that the paint cannot tell:
      zrender's hasFill() is `fill != null && fill !== 'none'` and its
      hasStroke() `stroke != null && stroke !== 'none' && lineWidth > 0`,
      so a colour written 'transparent' or rgba(..., 0) fills and strokes
      for the pointer while it paints nothing, and 'none' does neither.
      The colours above hold both as transparent. HitNoFill: a closed
      shape's fill is null or 'none' -- Path.contain asks no inside, and
      the pen reaches at least strokeContainThreshold (an open line asks
      HasFill, as before). HitClearPen: a pen of no alpha that is a colour
      all the same (it strokes for the pointer at its width). The zero
      values are the old reading: a closed shape filled, a clear pen none.
      The painter reads neither. }
    HitNoFill: Boolean;
    HitClearPen: Boolean;
  end;

  { [R5-A] A SHADOW AS A STYLE HOLDS IT: shadowBlur, shadowOffsetX / Y (LOGICAL px) and
    shadowColor -- zrender's four common style keys, read off a model by getItemStyle,
    getLineStyle or getAreaStyle. The zero value is none. }
  TTyChartShadow = record
    Blur, OffsetX, OffsetY: Double;
    Color: TTyChartColor;
  end;

const
  { [R7-S] TTyChartElement.CanvasFlags }
  cTyCanvasOwnShadow = 1;
  cTyCanvasShadowLeft = 2;
  cTyCanvasTransformLeft = 4;
  { [R7-V] a value the canvas refuses, the one it had kept: a shadowBlur
    below nought, a lineCap / lineJoin that is no word of theirs, a
    miterLimit below nought (TyLinesCanvasLeftovers settles each in paint
    order and marks it here) }
  cTyCanvasBlurLeft = 8;
  cTyCanvasCapLeft = 16;
  cTyCanvasJoinLeft = 32;
  cTyCanvasMiterLeft = 64;
  { [R7-V] what a builder writes for such a value until the paint order
    settles it: a shadowColor no colour parser takes (alpha 0: none drawn
    meanwhile), a lineCap / lineJoin of 3 (drawn as the default meanwhile);
    a shadowBlur or miterLimit keeps its own negative }
  cTyCanvasColourLeft = TTyChartColor($00010203);
  cTyCanvasWordLeft = 3;
  { [R7-W] more of them: a fill / stroke colour no parser reads (written as
    cTyCanvasColourLeft: the canvas keeps the fillStyle / strokeStyle it
    had), a width of 'Infinity' (marked by its builder, drawn as none until
    settled: the lineWidth it had), a dash phase no number or infinite
    (written as cTyCanvasPhaseLeft: the lineDashOffset it had), a caption's
    text fill / stroke colour or one of its pieces' (cTyCanvasColourLeft) }
  cTyCanvasFillLeft = 128;
  cTyCanvasStrokeLeft = 256;
  cTyCanvasWidthLeft = 512;
  cTyCanvasPhaseLeftFlag = 1024;
  cTyCanvasTextFillLeft = 2048;
  cTyCanvasTextStrokeLeft = 4096;
  cTyCanvasPhaseLeft = -1.0e305;
  { [R7-Y] and more: a shadowOffsetX / Y the canvas refuses (a string that
    is no finite number: dpr times it is not one -- written as
    cTyCanvasPhaseLeft, the offset it had), a blend (globalCompositeOperation)
    that is none of the canvas' words (the one it had), a caption's font the
    canvas refuses (the font the text before it left) }
  cTyCanvasOffXLeft = 8192;
  cTyCanvasOffYLeft = 16384;
  cTyCanvasBlendLeft = 32768;
  cTyCanvasFontLeft = 65536;
  { [R5-C] TTyChartElementStyle.LineCap / LineJoin }
  cTyCapButt = 0;
  cTyCapRound = 1;
  cTyCapSquare = 2;
  cTyJoinMiter = 0;
  cTyJoinRound = 1;
  cTyJoinBevel = 2;

type

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
  { [R7-H] rtwText: a token's width written as a string that is no
    percentage and not 'auto' ('60', 'abc') -- written, so it is no width
    the token takes from its words alone, yet no number either }
  TTyRtWidthKind = (rtwNone, rtwNumber, rtwPercent, rtwAuto, rtwText);
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
    { [R7-H] A WIDTH, HEIGHT OR LINE HEIGHT WRITTEN AS A STRING, as zrender
      holds it -- createTextStyle hands the option's value on as it is, and
      zrender does JS arithmetic with it: where it compares or divides, the
      string is its JS number (Width / Height / LineHeight hold it, NaN for
      a word such as '50%' or 'abc'); where it ADDS -- the padding to the
      outer width, a block's left edge to its width, a plain line's y to the
      line height -- the string is joined ('60' + 0 = '600'). The block's
      width is a string whatever its kind (rtwPercent, rtwAuto and rtwText
      alike: zrender reads no percentage on a block); a site that sets a
      width or height of its own clears the flag. }
    WidthIsText, HeightIsText, LineHeightIsText: Boolean;
    WidthText, HeightText, LineHeightText: string;
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
    { [R7-F] the box's borderWidth written +Infinity: drawn as none (the
      canvas takes no such width), and the box's stroked rect is
      not-a-number upstream -- the pointer never finds the box }
    BorderWidthInf: Boolean;
    { [R2-I2] the box's border dash as written (a label's borderType, a
      graphic text's borderDash; '' solid) and its phase (borderDashOffset) }
    BorderDash: string;
    BorderDashOffset: Double;
    Radius: array[0..3] of Double;
    { [R7-L] borderRadius is truthy (a number not nought, any array, [0, 0]
      too): zrender's Rect takes the rounded path (roundRect), which joins a
      size written as a string to the corner's place }
    RadiusTruthy: Boolean;
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
    { [R5-A] THE BOX'S SHADOW (TEXT_PROPS_BOX' shadowBlur / shadowColor /
      shadowOffsetX / Y): the rect or the picture of the box casts it, in
      shadowColor -- 'transparent' when none (Text.ts _renderBackground) }
    BoxShadowBlur, BoxShadowOffsetX, BoxShadowOffsetY: Double;
    HasBoxShadowColor: Boolean;
    BoxShadowColor: TTyChartColor;
    { WHICH FONT PARTS THE STYLE NAMED ITSELF. A rich style's missing parts
      are filled from the block's font (or the global one, with
      richInheritPlainLabel off) by TyRtFinish, once the site knows the
      font it draws the block in; the engine reads only the four values.
      [Batch 86] }
    OwnFontFamily, OwnFontSize, OwnFontWeight: Boolean;
    { [R5-A] the style wrote a fontStyle string of its own (FontItalic its
      reading); where it did not, TyRtFinish hands it the block's or the
      global one, as the other parts. The italic a text DRAWS is the
      TyChartFontItalic flag in its FontWeight. }
    OwnFontStyle: Boolean;
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
    { [R7-F] a rect the pointer never finds (a box whose border is
      +Infinity: its stroked rect is not-a-number) }
    NoHit: Boolean;
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
    { [R7-H] A RECT WHOSE SIZE WAS A STRING ('600'): canvas draws a plain
      rect at X, Y, W, H (its numbers), but zrender's path ADDS the size to
      the corner as a string -- a rounded rect runs from X to EdgeX1 = X +
      '600' joined, and so do the bounds of every such rect (PathProxy's
      fromLine). EdgeX1 / EdgeY1 are those joined edges. }
    PathEdges: Boolean;
    EdgeX1, EdgeY1: Double;
    { [R7-L] the rounded path (roundRect), radii nought or not -- see
      TTyRtStyle.RadiusTruthy }
    Rounded: Boolean;
    Opacity: Double;
    { [R7-L] A TOKEN'S OWN OPACITY (its style's, the root textStyle's under
      it): zrender gives the token retrieve3(its own, the Text's, 1), so it
      is drawn at Opacity whatever the Text's own opacity is -- every other
      piece follows the Text's (the element's alpha) }
    OwnOpacity: Boolean;
    { [R7-L] NOT ONE OF zrender's CHILDREN: the undrawn rect a label laid
      out wholly at NaN stands as, where its TSpans are bounded, so the
      label layout and the pointer still find it }
    Placeholder: Boolean;
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
    { [spec 242] a rich token's fill or stroke of its own: a state's style
      on the block (a custom text's emphasis fill) leaves it }
    TokenFill, TokenStroke: Boolean;
    { [R7-W] its fill (1) / stroke (2) colour one the canvas refused, the
      one it had settled in (TyLinesCanvasLeftovers) }
    CanvasLeft: Byte;
  end;
  TTyRtPieceArray = array of TTyRtPiece;


  { A TEXT'S STYLE AS THE SITE HOLDS IT BEFORE LAYOUT: zrender's block style
    and its rich styles, resolved from the option by AdvanceChart.RichStyle.
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
    { [R7-M] under a whole affine map instead (the caption's Affine: the
      text's own CSS px to device px, the anchor in [4..5]) }
    HasAffine: Boolean;
    Affine: array[0..5] of Double;
  end;

  { WORDS ON A MARK, and -- once the label pass has placed them -- everything
    needed to draw them.

    A MARK FILLS IN Text AND NOTHING ELSE. The label pass reads that, works
    out where the words go against the mark's own bounds, and emits a SECOND
    element with the rest filled in. So a caption with Text set and FontName
    empty is a REQUEST, and one with both is an ANSWER; the two are never the
    same element.

    Why the words are not a shape kind: AdvanceChart.Shape imports no measurer on
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
    { [R7-M] A FIXED ANCHOR'S TEXT SQUASHED ON Y BEFORE ITS TURN: a graph's
      edge label in a view scaled unequally (Line.beforeUpdate scales it by
      1 / the ancestors' scaleX, so the main group's scaleY / scaleX is left
      on it) -- the ratio; 0 (or 1) none. The label pass draws such a text
      under the whole map (HasAffine). }
    FixedYScale: Double;
    { [R7-M] A TREEMAP'S LABEL ON ITS CELL: TreemapView's beforeUpdate sets
      the label's width and height to its content rect's (an upper label's
      strip's) less the padding, so a block's box is the whole cell. A block
      is laid out at FixedBoxX / Y (device px: the position's anchor, before
      the padding the one-run caption's FixedX / Y has in it) by
      FixedBoxAH / AV, its width FixedBoxW, its height FixedBoxH and its
      padding FixedBoxPad (top, right, bottom, left) CSS px -- the padding
      the cell was cut by, the label's own or the treemap's default }
    HasFixedBox: Boolean;
    FixedBoxX, FixedBoxY, FixedBoxW, FixedBoxH: Double;
    FixedBoxAH: TTyTextAnchorH;
    FixedBoxAV: TTyTextAnchorV;
    FixedBoxPad: array[0..3] of Double;
    { [F3d] A FIXED ANCHOR HUNG ON THE HOST'S BOX (a radial tree's label):
      the position and the distance (device px) it was placed by, so a
      frame can place it again on the box as drawn }
    HasFixedPos: Boolean;
    FixedPos: Integer;
    FixedDist: Double;
    { [R5-C] HOW UPSTREAM PLACES THE LABEL a fixed anchor stands for: 0 the
      label's own x / y and style (a pie's, a sunburst's: free under a
      labelLayout, its alignment in its style); 1 the host's textConfig
      position (a sankey node's: attached, the alignment the position's,
      none in the style); 2 the same with the style's verticalAlign set (a
      radial tree's: textConfig with an origin, verticalAlign 'middle') }
    FixedByConfig: Byte;
    { ... and what the host's box is made of: the path's half width at rest
      (its scale on the canvas) and the stroke's half margin around it --
      strokeNoScale divides the line width by the line scale, so the margin
      stays while the path scales, and goes when the scale is nought
      (Path.getBoundingRect) }
    FixedHalfW, FixedInfl: Double;
    { [R6-A] a circular graph's rotateLabel: the label turned by -RingRad
      about its symbol's rect, on its left (RingLeft) or right }
    RingTurn, RingLeft: Boolean;
    RingRad: Double;
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
    { [R6-A] the normal position is 'middle': textConfig.inside, which a
      state's position does not undo }
    SecMiddle: Boolean;
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
    { [R7-F] A SERIES LABEL'S BOX IN ITS OWN FRAME: about (X, Y), unturned,
      device px (the block's union, or the plain words' box). Where the
      label turns (RotationRad), the hit test takes the point back into
      that frame and asks this box -- zrender's rectContain / Path.contain
      in local coordinates -- not the element's upright bounds. HitRelOwn:
      the box leaves out a piece the pointer never finds (NoHit), so it is
      asked turned or not. }
    HasHitRel: Boolean;
    HitRelOwn: Boolean;
    HitRel: TTyRectF;
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
    { [R5-C] the layout's draggable: the label takes the pointer to be
      dragged (zrender's Draggable), its cursor 'move' }
    LmDraggable: Boolean;
    LmHasM: Boolean;
    LmM: TTyMat2D;
    { ==== WHAT A LABEL LINE READS [Batch 112] ====
      On a HOST, how updateLabelLinePoints measures it (AdvanceChart.LabelGuide):
        LgKind    0 nothing, 1 a symbol, 2 a rect, 3 a sector [R5-C];
        LgSymbol  the symbol's zrender type ('circle', 'path://...') and
                  LgKeepAspect (symbolKeepAspect);
        LgG       a symbol's width, height, symbolRotate (degrees), offset x
                  and y, and the point x and y; a rect's x, y, width and height
                  (the signed layout) and its four corner radii; a sector's
                  cx, cy, r0, r, startAngle, endAngle, 1 clockwise, the
                  number of corner radii given (0..4) and they [R5-C];
        LgHasFrame / LgFrame  [R5-C] the host's parent group's computed
                  transform where the host sits in one (a view's group, a
                  node's group): the host's own shape is in that frame and
                  its computed transform is the frame times its own (a
                  symbol's point is then nought).
      On a LINE, LgSmooth: the smooth its normal state draws (its Cmds hold
      the curves; a state may straighten it). }
    LgKind: Integer;
    { the colour a line takes when its lineStyle has none: the item's
      visual colour by the series' draw type }
    LgColor: TTyChartColor;
    LgSymbol: string;
    LgKeepAspect: Boolean;
    LgG: array[0..11] of Double;
    LgHasFrame: Boolean;
    LgFrame: TTyMat2D;
    LgSmooth: Double;
  end;

  { WHAT AN ELEMENT IS TO THE ENTER ANIMATION [Batch 89, AN2]: which of
    upstream's animated elements it stands for, and the numbers upstream
    animates it in -- a bar's signed layout, a symbol's centre and half
    size, a line's clip rect. The zero value is carNone: not animated, which
    is every element nobody tagged.

    THE KEY is (Series, Index, the role's proxy): AdvanceChart.AnimView keeps one
    animated proxy per key, and the proxy outlives the list -- the list is
    rebuilt on every static render, the proxy only when the option is. }
  TTyChartAnimRole = (carNone, carBar, carSymbol, carLineSymbol, carLineRun,
    carLineArea, carSector, carFunnel, carGaugePointer, carGaugeProgress,
    carRadarLine, carRadarArea, carCandleBody, carCandleWickHigh,
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
      ends and control point, G[6] curved -- see AdvanceChart.Lines }
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
      transition (AdvanceChart.AnimView):
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
    { [spec 242] AN UPDATE'S updateProps of a shape the role does not tween
      itself: 0 none; 1 a parallel row's polyline (TwVals its points, flat;
      G[6] its smooth), 2 a themeRiver layer's polygon (its bottoms then its
      tops, flat; G[4] the group's y), 3 a chord piece's sector (cx, cy, r0,
      r, startAngle, endAngle; G[2] clockwise; Pts its corner radii), 4 a
      chord ribbon (s1, s2, its start and end angle, t1, t2, theirs, cx,
      cy, r; G[2] clockwise), 5 a lines row's line (x1, y1, x2, y2, cpx1,
      cpy1: G[0..5]; its line, end symbols and label alike). TwRow the
      proxy's row; TwKey the old element's key where the data diff is not
      the rows' (a layer's name, a node's or a link's), '' the row map }
    TwKind, TwRow: Integer;
    TwKey: string;
    TwVals: TTyDoubleArray;
    { the role's own numbers -- see AdvanceChart.AnimView for each }
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
    { [R6-A] A PIE LABEL UNDER A STATE POSITION: its slice's list index + 1
      (0 none) and the anchor the list placed it by -- a frame places it
      again on the slice as the frame draws it (the radius tweening) }
    PieHostPlus1, PieTwin: Integer;
    PieAX, PieAY, PieLX, PieLY, PieScale: Double;
    { A COMBINING ELEMENT'S CHILD in a frame: its index + 1 (0 for the
      element itself) [Batch 137] }
    UtPiece: Integer;
    { [R6-C] A CHILD ADDED AFTER THE FRAME'S LIST: its host's insertion index
      + 1 (0, the zero value, for any other element). It paints and is hit
      at the host's place (Storage puts childrenRef where the host would
      be), and a hit on it names the host }
    PieceOf: Integer;
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
    { [R6-B] AN SVG MAP'S ELEMENT drawn in the map's own units: what a frame
      carries with the group's points also scales with it -- VStroke its
      stroke's width, dash and offset (a shape that is not strokeNoScale:
      no option style), VInk a text's glyphs and halo (or its whole map),
      an image's pattern. A GeoJSON region and a named SVG shape are
      strokeNoScale (MapDraw's applyOptionStyleForRegion): neither is set,
      their width stays on the screen. VPx the list's px per logical px the
      image's pattern map is in (APPI / 96). }
    VStroke, VInk: Boolean;
    VPx: Double;
    { [R6-B] A BOX GRADIENT TURNED WITH AN SVG SHAPE WHOSE STROKE IS
      strokeNoScale: the box zrender takes it on grows by the stroke over the
      line scale, which a frame changes -- VGradFrac the gradient as written
      (its fractions), VGradL the shape's transform at rest (its linear
      part), VGradW0 / VGradH0 its own box ungrown, VGradG the growth per
      side at rest, VGradLS the line scale at rest }
    VGradNS: Boolean;
    VGradFrac: TTyChartGradient;
    VGradL: array[0..3] of Double;
    VGradW0, VGradH0, VGradG, VGradLS: Double;
    LabelPos: Integer;
    LabelDist, LabelAtX, LabelAtY, LabelInflate: Double;
    LabelAtXPct, LabelAtYPct: Boolean;
    { [F3c] WHAT A UNIVERSAL TRANSITION READS OF AN ELEMENT whose role says
      nothing of it (AdvanceChart.AnimView), the role and its numbers left as
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
    { [spec 242] A GRADIENT IN THE ELEMENT'S OWN FRAME -- a lines end
      symbol's colour, a lines effect symbol's: LGrad as written (Kind
      cgkNone: none), LGradBox the element's getBoundingRect in that frame,
      LGradStroke whether it is the pen's (an empty or a 'line' symbol). A
      frame that turns, scales or moves the element puts it on the style
      again, carried by the element's transform (canvas' own way: the
      gradient lives in the element's coordinates) }
    LGrad: TTyChartGradient;
    LGradBox: TTyXYWH;
    LGradStroke: Boolean;
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
    { [R7-O] A strokeNoScale PEN READ OFF THE STYLE AT HIT TIME (a state
      tweens it): the stroke width is the element's StrokeWidthLogical
      (device px), at least strokeContainThreshold, over LineScale, and Box
      is PathBox grown by it -- a graph edge's line under a view scaled
      unequally. False, the zero value: LineWidth and Box as written. }
    StyleWidth: Boolean;
    LineScale: Double;
    PathBox: TTyXYWH;
    { [R7-S] A GRAPHIC OR CUSTOM SERIES ELEMENT'S WHOLE Path.contain IN ITS
      OWN FRAME: Path its path there (TyGfxPath), ToLocal the inverse of its
      device transform, PathBox the path's rect, Fill its hasFill and Stroke
      its hasStroke as built; the pen's width read off the style at hit time
      (a state tweens it) as its own lineWidth -- StrokeWidthLogical over
      LwDiv, the css px of the drawn width per unit of it; FixedLw instead
      where it is not drawn (invisible: the style holds no pen, upstream
      still asks it) -- at least strokeContainThreshold without a fill, over
      LineScale (getLineScale where strokeNoScale, else 1); the rect grown by
      that. So a segment's end box, an arc's whole width and the threshold
      are all upstream's, in its frame [was: the drawn outline on the
      canvas, its arcs as cubics at half the width]. }
    OwnPen: Boolean;
    LwDiv: Double;
    FixedLw: Double;
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
    { [R6-A] A SERIES LABEL'S: what the frame lays it out on its host by
      under that state (TTyChartAnim.LabelPos ...), HasRide where it says }
    HasRide: Boolean;
    LabelPos: Integer;
    LabelDist, LabelAtX, LabelAtY: Double;
    LabelAtXPct, LabelAtYPct: Boolean;
    { [R6-A] A PIE LABEL'S, laid out when the state is written, on its
      slice as that state draws it (PieView nulls the normal position: the
      label stands at label.x / y unless a state writes one): HasPos the
      position LabelPos at LabelDist (device px), HasOff the offset, HasRot
      the turn, each where the states write it }
    Defer: Boolean;
    { [R6-A] A TREEMAP NODE'S, on its host: where the treemap places the
      words under that state's position and distance (Caption.X / Y and
      the alignment) }
    Anchored: Boolean;
    { [R6-A] A LINE'S LABEL (a graph edge's, a lines row's), laid out when
      the state is written on the Line group's box (the line grown by the
      state's width, its end symbols): HasPos, LabelPos / LabelAt* and
      LabelDist (LOGICAL px, in the group's units) the position, HasOff /
      OffX / OffY (device px) and HasRot / Rot the states' own }
    LineBox: Boolean;
    HasPos, HasOff, HasRot: Boolean;
    OffX, OffY, Rot: Double;
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
    { [R7-R] STROKECONTAINTHRESHOLD IN THE ELEMENT'S OWN FRAME: Path.contain
      takes an unfilled path's pen to at least 5 of the element's own units
      (over its line scale where it is strokeNoScale), so where a transform
      scales the element the threshold scales with it -- 5 times this, in
      the space the hit test asks the pen in (the canvas, or the pen map's
      space: the element's frame times the root of the map's determinant).
      A graphic / custom series element under its own or a group's scale
      (10 px at scale 2; its line scale where strokeNoScale). 0, the zero
      value, is 1: 5 on the canvas, as every element built in px. }
    HitMinScale: Double;
    { [R7-S] WHAT THE CANVAS IS LEFT WITH (TyLinesCanvasLeftovers): a lines
      effect symbol's own canvas shadowColor (CanvasShadow, where
      CanvasFlags has cTyCanvasOwnShadow: its written shadowColor or its
      colour, which zrender assigns even where nothing casts it); its shadow
      in the colour the canvas had (cTyCanvasShadowLeft: its colour a
      gradient, or no colour, the canvas refuses); its transform the one the
      canvas had (cTyCanvasTransformLeft: a scale that is not a number, the
      transform refused) }
    CanvasFlags: LongWord;
    CanvasShadow: TTyChartColor;
    { [R7-V] THE TRANSFORM IT HANDS THE CANVAS (zrender's setTransform of its
      own transform), device px, [a, b, c, d, e, f], where it is not read
      off the element otherwise (a lines series' end symbol, ...): what an
      effect symbol of no transform is drawn under after it. Nil, the zero
      value: read off the element (an effect symbol's place, a caption's
      anchor and turn, a symbol's frame, an own-frame path's) or none }
    CanvasM: TTyDoubleArray;
    { [R6-F] NEVER HIT, though drawn and in the states: zrender's
      Path.contain of a path whose bounding rect is not-a-number -- a pen of
      infinite width grows it by Infinity / 2 each way, and x - Inf + Inf is
      NaN (a bar whose infinite border took all of its width) }
    HitNone: Boolean;
    { [R7-C] A POINTER IN ITS OWN FRAME: the polygon is upstream's
      PointerPath, drawn upright along its local y and turned to its angle
      by its transform -- Path.contain's stroked bounding rect is upright in
      that frame, so the hit test turns the polygon (its tip, Points[2], off
      its back, Points[0]) and the point back first. False everywhere else }
    HitUpright: Boolean;
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
      rule above: the hit test ignores the clip.
      [R7-I] Its rect or its sector, wherever upstream's clip is a clipPath
      on the element or a parent: a line's run and area (the lineGroup's),
      a lines series' every element, a custom series' (clip: true), a candle
      or box partly clipped (its own), a thumbnail's window (its
      contentGroup's), and while they enter, a parallel line, a theme river
      layer and a sankey's group (removed when the entering ends). A large
      batch asks its own (TTyLargeGeom.ClipOn). Not a series that cuts its
      geometry (bars, a scatter's points) or none (a graph). }
    ClipHits: Boolean;
    { [spec 242] A GRAPHIC OR CUSTOM ELEMENT'S clipPath, and every clipPath
      up its parents (and its host's, for a label), as zrender's Storage
      hands them down: each a filled path in the element's coordinates, the
      ink cut to all of them (nonzero), and the hit too (isHover asks each
      clip's contain). Empty everywhere else. }
    ClipPaths: TTyChartShapeArray;
    { [R5-I] the caption is cut to ClipPaths too, whatever it is (a
      themeRiver layer's label under the layer's clip); else only a block's }
    ClipCaption: Boolean;
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
    { [R5-A] zrender's zlevel: a layer of its own, painted over every lower
      one whatever the z -- the first key of the order. A series' (and its
      labels'), a marker's; 0, the zero value, for everything else }
    ZLevel: Integer;
    { [spec 244] the part of a z that is not whole, the second key after Z
      (Z its floor): a geo's z of 2.5 sorts over a series' 2 and under a 3,
      as zrender sorts the number. 0, the zero value, for everything else }
    ZFrac: Double;
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

{ [R5-J] A ZLEVEL BAND FOR THE HIT TEST: while one is set, the list's hit
  tests (HitTestElement, TyCoarseHitTest) consider only an element whose
  ZLevel is above ALo and at most AHi -- the pointer searched canvas by
  canvas, the highest first, as zrender's handler walks the sorted display
  list. TyClearHitBand: every element again. }
procedure TySetHitBand(ALo, AHi: Integer);
procedure TyClearHitBand;
function TyHitBandHas(AZ: Integer): Boolean;

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
{ [R7-C] THE WIDTH zrender's Path.contain tests the element's stroke at,
  device px (AScale the device px per logical one): the pen as drawn --
  its width times the pen's own scale (PenScale) -- at least
  strokeContainThreshold (5) where the element has no fill (an open line
  without one: a closed shape whose fill is no colour is taken as filled
  with a transparent one, since this port's colours cannot tell 'none' from
  'transparent'). 0: no stroke to test (no width, or no colour as drawn);
  -1: a pen of infinite width, whose stroked bounding rect is
  not-a-number, so the element is never hit. }
function TyElementStrokeHitPx(const AEl: TTyChartElement; AScale: Double): Double;
{ [R7-C] ONE ELEMENT AT A POINT, as the list's hit tests ask it: the clips,
  then ZrHit or PathHit where the element carries one, else zrender's
  Path.contain over the shape -- where the element strokes, the fill (the
  shape grown by the port's pad, APad) or the stroke within its reach of the
  outline (TyZrShapeContainStroke at TyElementStrokeHitPx); where it does
  not, the shape grown by the element's slop (and the pad) as before. }
function TyElementHit(const AEl: TTyChartElement; AX, AY: Double; APPI: Integer;
  APad: Boolean): Boolean;
{ the sector an element's HasClipSector names, run forward as zrender's arc
  runs it from ClipSA to ClipEA in its direction (the renderer cuts the ink
  to it; [R7-I] where ClipHits, the hit too) }
function TyClipSectorShape(const AElement: TTyChartElement): TTyChartShape;
{ [F6b] an SVG map element's zrender contain (ZrHit) at a point }
function TyZrHitContains(const AHit: TTyZrHit; AX, AY: Double): Boolean;
{ [R2-I1] A SYMBOL'S TARGET in two parts [Batch 142]: the pen's own reach,
  upstream's (Path.contain strokes with the line width, max(width, 5)
  without a fill; nothing without a stroke), and the rest of the four
  logical px as the port's pad (HitPadLogical), which a coarse pointer
  leaves out. Moved here from the marks so a graph's and a tree's node take
  it too [they had a fixed 4 px of slop]. }
procedure TySymbolHitSlop(var AEl: TTyChartElement);
{ [R7-P] zrender's Path.getLineScale over a transform's linear part: the
  square root of |det|, 1 where either diagonal entry (A0, A3) is 1 }
function TyZrLineScaleOf(A0, A1, A2, A3: Double): Double;
{ [R7-P] THE PEN MAP onto a style (TTyChartElementStyle.PenMap): AL the
  linear map the canvas puts on the round pen of the style's width. Kept
  only where AL is no turn and uniform scale (nor a mirror of one) -- a
  round pen is the same there -- and finite; else HasPenMap goes off. }
procedure TyStyleSetPenMap(var AStyle: TTyChartElementStyle; const AL: TTyMat2D);
{ [R7-P] A strokeNoScale PATH under its whole transform AM (its unit or
  own path to the canvas): the canvas' pen is AM over its line scale
  (TyZrLineScaleOf) times a round pen of the style's lineWidth }
procedure TyStyleNoScalePen(var AStyle: TTyChartElementStyle; const AM: TTyMat2D);
{ [R7-P] THE SHAPE OF THE PEN AL puts on a path whose style's width (with
  PenScale) already holds the round pen's size -- the root of |det AL|
  times the width: AL over that root }
procedure TyStyleSetPenShape(var AStyle: TTyChartElementStyle; const AL: TTyMat2D);
{ [R7-P] a strokeNoScale path's pen under a graph view's scale (ASX, ASY):
  diag(ASX, ASY) over its line scale }
procedure TyStyleViewPen(var AStyle: TTyChartElementStyle; ASX, ASY: Double);
{ [R7-P] THE PEN THE RENDERER DRAWS: AE the map onto a round pen of the
  style's StrokeWidthLogical -- PenMap times PenScale (where it is one).
  False where it is round (no map): the width times PenScale as before. }
function TyStylePenOf(const AStyle: TTyChartElementStyle; out AE: TTyMat2D): Boolean;
{ A style with nothing switched on: no fill, no stroke, fully opaque. Callers
  turn on what they want rather than remembering to turn off what they do not. }
function TyChartStyle: TTyChartElementStyle;
{ [R5-A] the element's style casts a shadow: a colour with alpha and a blur or an offset }
function TyStyleHasShadow(const AStyle: TTyChartElementStyle): Boolean;
{ [R7-V] THE ALPHA A FILL (AFill) OR A PEN IS DRAWN AT: the element's
  opacity as the canvas' globalAlpha, under its fillOpacity / strokeOpacity
  where it has one -- the renderer's one rule for both }
function TyCanvasPartAlpha(const AStyle: TTyChartElementStyle; AFill: Boolean): Double;
{ [R7-W] whether a dash phase is cTyCanvasPhaseLeft (scaled or not; a
  not-a-number is not) }
function TyPhaseLeft(AValue: Double): Boolean;
{ [R7-Y] whether the canvas takes AWord for globalCompositeOperation: one of
  its words exactly (case and spaces matter) }
function TyBlendWordKnown(const AWord: string): Boolean;
{ [R5-A] AShadow onto a style, all four keys }
procedure TyStyleSetShadow(var AStyle: TTyChartElementStyle; const AShadow: TTyChartShadow);
{ An element carrying a shape, silent and datum-less until the caller says
  otherwise -- so a decoration that forgets to set Silent is at worst inert,
  never a thing that steals hovers from the data. }
function TyChartElement(const AShape: TTyChartShape): TTyChartElement;

{ WHERE A PIECE'S POINT (ALX, ALY) LANDS: the anchor plus the point scaled
  and turned counter-clockwise -- zrender's Text transform, as every child
  of the text shares it. [Batch 86] }
procedure TyRtPoint(AX, AY, ARotationRad, AScale, ALX, ALY: Double;
  out AGX, AGY: Double);
{ [R7-M] a drawn block's point: through its whole map where it has one }
procedure TyRtDrawnPoint(const AD: TTyRtDrawn; ALX, ALY: Double;
  out AGX, AGY: Double);

{ [R5-C] a lineCap / lineJoin word as zrender's canvas takes it (anything
  else leaves the canvas' default: butt, miter) }
function TyCapOfWord(const S: string): Byte;
function TyJoinOfWord(const S: string): Byte;

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
  { [R6-A] a series label's select-and-hover pairs: select's textConfig and
    then emphasis' (or blur's) over it }
  TyTwinSelectEmphasis = 3;
  TyTwinSelectBlur = 4;

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

function TyCapOfWord(const S: string): Byte;
begin
  if S = 'round' then Result := cTyCapRound
  else if S = 'square' then Result := cTyCapSquare
  { [R7-V] `style.lineCap || 'butt'`: an empty word is the default; any
    other word the canvas refuses, keeping the one it had (settled in paint
    order, TyLinesCanvasLeftovers) [was: the default] }
  else if (S = 'butt') or (S = '') then Result := cTyCapButt
  else Result := cTyCanvasWordLeft;
end;

function TyJoinOfWord(const S: string): Byte;
begin
  if S = 'round' then Result := cTyJoinRound
  else if S = 'bevel' then Result := cTyJoinBevel
  { [R7-V] the same for lineJoin }
  else if (S = 'miter') or (S = '') then Result := cTyJoinMiter
  else Result := cTyCanvasWordLeft;
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

procedure TyStyleSetShadow(var AStyle: TTyChartElementStyle; const AShadow: TTyChartShadow);
begin
  AStyle.ShadowBlur := AShadow.Blur;
  AStyle.ShadowOffsetX := AShadow.OffsetX;
  AStyle.ShadowOffsetY := AShadow.OffsetY;
  AStyle.ShadowColor := AShadow.Color;
end;

function TyStyleHasShadow(const AStyle: TTyChartElementStyle): Boolean;
begin
  Result := ((AStyle.ShadowColor shr 24) <> 0)
    and ((AStyle.ShadowBlur > 0) or (AStyle.ShadowOffsetX <> 0) or (AStyle.ShadowOffsetY <> 0));
end;

function TyBlendWordKnown(const AWord: string): Boolean;
const
  cWords: array[0..25] of string = ('source-over', 'source-in', 'source-out',
    'source-atop', 'destination-over', 'destination-in', 'destination-out',
    'destination-atop', 'lighter', 'copy', 'xor', 'multiply', 'screen', 'overlay',
    'darken', 'lighten', 'color-dodge', 'color-burn', 'hard-light', 'soft-light',
    'difference', 'exclusion', 'hue', 'saturation', 'color', 'luminosity');
var k: Integer;
begin
  for k := 0 to High(cWords) do
    if AWord = cWords[k] then Exit(True);
  Result := False;
end;

function TyPhaseLeft(AValue: Double): Boolean;
begin
  { (NaN first: a comparison with it raises here) }
  Result := (not IsNan(AValue)) and (AValue < -1e290);
end;

function TyCanvasPartAlpha(const AStyle: TTyChartElementStyle; AFill: Boolean): Double;
var p: Double;
begin
  { bindCommonProps: Math.max(Math.min(opacity, 1), 0), not-a-number 1 --
    a value outside 0..1 is drawn clamped, the canvas never asked [was:
    the same, a not-a-number nought] }
  if IsNan(AStyle.Alpha) then Result := 1
  else Result := Max(0.0, Min(1.0, AStyle.Alpha));
  { [R7-V] doFillPath / doStrokePath: globalAlpha = fillOpacity * opacity,
    the raw opacity, which the canvas refuses outside 0..1 (and not a
    number) -- the clamped opacity stays [was: each clamped, then the
    product] }
  if AFill and AStyle.HasFillOpacity and (AStyle.FillOpacity <> 1) then
    p := AStyle.FillOpacity * AStyle.Alpha
  else if not AFill and AStyle.HasStrokeOpacity and (AStyle.StrokeOpacity <> 1) then
    p := AStyle.StrokeOpacity * AStyle.Alpha
  else Exit;
  if not IsNan(p) and (p >= 0) and (p <= 1) then Result := p;
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

procedure TyRtDrawnPoint(const AD: TTyRtDrawn; ALX, ALY: Double;
  out AGX, AGY: Double);
begin
  if AD.HasAffine then
  begin
    AGX := AD.Affine[0] * ALX + AD.Affine[2] * ALY + AD.Affine[4];
    AGY := AD.Affine[1] * ALX + AD.Affine[3] * ALY + AD.Affine[5];
  end
  else
    TyRtPoint(AD.X, AD.Y, AD.RotationRad, AD.Scale, ALX, ALY, AGX, AGY);
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
    if (FItems[FJrIdx[k]].Z <> FJrOld[k].Z) or (FItems[FJrIdx[k]].Z2 <> FJrOld[k].Z2)
      or (FItems[FJrIdx[k]].ZLevel <> FJrOld[k].ZLevel)
      or (FItems[FJrIdx[k]].ZFrac <> FJrOld[k].ZFrac) then
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
  if (FItems[AIndex].Z <> AElement.Z) or (FItems[AIndex].Z2 <> AElement.Z2)
    or (FItems[AIndex].ZLevel <> AElement.ZLevel) or (FItems[AIndex].ZFrac <> AElement.ZFrac) then
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
var pa, pb: Integer;
begin
  { [R5-A] the layer first: zrender paints each zlevel's canvas over the
    lower ones }
  if FItems[A].ZLevel <> FItems[B].ZLevel then
    Exit(FItems[A].ZLevel < FItems[B].ZLevel);
  if FItems[A].Z <> FItems[B].Z then
    Exit(FItems[A].Z < FItems[B].Z);
  if FItems[A].ZFrac <> FItems[B].ZFrac then
    Exit(FItems[A].ZFrac < FItems[B].ZFrac);
  if FItems[A].Z2 <> FItems[B].Z2 then
    Exit(FItems[A].Z2 < FItems[B].Z2);
  { [R6-C] a combining host's child added after the list sorts at its
    host's place, after the host and the children before it }
  if (FItems[A].Anim.PieceOf > 0) or (FItems[B].Anim.PieceOf > 0) then
  begin
    pa := A;
    pb := B;
    if FItems[A].Anim.PieceOf > 0 then pa := FItems[A].Anim.PieceOf - 1;
    if FItems[B].Anim.PieceOf > 0 then pb := FItems[B].Anim.PieceOf - 1;
    if pa <> pb then Exit(pa < pb);
  end;
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

function TyZrLineScaleOf(A0, A1, A2, A3: Double): Double;
begin
  if (Abs(A0 - 1) > 1e-10) and (Abs(A3 - 1) > 1e-10) then
    Result := Sqrt(Abs(A0 * A3 - A2 * A1))
  else
    Result := 1;
end;

procedure TyStyleSetPenMap(var AStyle: TTyChartElementStyle; const AL: TTyMat2D);
var n: Double; k: Integer;
begin
  AStyle.HasPenMap := False;
  AStyle.PenMap := Default(TTyMat2D);
  for k := 0 to 3 do
    if IsNan(AL[k]) or IsInfinite(AL[k]) then Exit;
  n := Max(Max(Abs(AL[0]), Abs(AL[1])), Max(Abs(AL[2]), Abs(AL[3])));
  if not (n > 0) then Exit;
  { a turn and a scale, or a mirror of one: the same round pen }
  if (Abs(AL[0] - AL[3]) <= 1e-9 * n) and (Abs(AL[1] + AL[2]) <= 1e-9 * n) then Exit;
  if (Abs(AL[0] + AL[3]) <= 1e-9 * n) and (Abs(AL[1] - AL[2]) <= 1e-9 * n) then Exit;
  AStyle.HasPenMap := True;
  for k := 0 to 3 do AStyle.PenMap[k] := AL[k];
end;

procedure TyStyleNoScalePen(var AStyle: TTyChartElementStyle; const AM: TTyMat2D);
var ls: Double; L: TTyMat2D;
begin
  ls := TyZrLineScaleOf(AM[0], AM[1], AM[2], AM[3]);
  if not (ls > 1e-10) or IsNan(ls) or IsInfinite(ls) then
  begin
    AStyle.HasPenMap := False;
    Exit;
  end;
  L := Default(TTyMat2D);
  L[0] := AM[0] / ls;
  L[1] := AM[1] / ls;
  L[2] := AM[2] / ls;
  L[3] := AM[3] / ls;
  TyStyleSetPenMap(AStyle, L);
end;

procedure TyStyleSetPenShape(var AStyle: TTyChartElementStyle; const AL: TTyMat2D);
var d: Double; L: TTyMat2D;
begin
  d := Sqrt(Abs(AL[0] * AL[3] - AL[1] * AL[2]));
  if not (d > 0) or IsInfinite(d) then
  begin
    AStyle.HasPenMap := False;
    Exit;
  end;
  L := Default(TTyMat2D);
  L[0] := AL[0] / d;
  L[1] := AL[1] / d;
  L[2] := AL[2] / d;
  L[3] := AL[3] / d;
  TyStyleSetPenMap(AStyle, L);
end;

procedure TyStyleViewPen(var AStyle: TTyChartElementStyle; ASX, ASY: Double);
var M: TTyMat2D;
begin
  M := Default(TTyMat2D);
  M[0] := ASX;
  M[3] := ASY;
  TyStyleNoScalePen(AStyle, M);
end;

function TyStylePenOf(const AStyle: TTyChartElementStyle; out AE: TTyMat2D): Boolean;
var ps: Double; k: Integer;
begin
  AE := Default(TTyMat2D);
  Result := AStyle.HasPenMap;
  if not Result then Exit;
  ps := AStyle.PenScale;
  if (ps <= 0) or IsNan(ps) or IsInfinite(ps) then ps := 1;
  for k := 0 to 3 do AE[k] := AStyle.PenMap[k] * ps;
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

{ [R7-F] zrender's hasFill() of the element: an open line's fill as it is
  painted, a closed shape's unless written 'none' (HitNoFill) }
function ElFills(const AEl: TTyChartElement): Boolean; inline;
begin
  if AEl.Shape.Kind = cskPolyline then Result := AEl.Style.HasFill
  else Result := not AEl.Style.HitNoFill;
end;

function TyElementStrokeHitPx(const AEl: TTyChartElement; AScale: Double): Double;
var w, ps: Double;
begin
  Result := 0;
  w := AEl.Style.StrokeWidthLogical;
  if not (w > 0) then Exit;
  if ((AEl.Style.StrokeColor shr 24) = 0) and (AEl.Style.StrokeGradient.Kind = cgkNone)
    and not AEl.Style.HitClearPen then Exit;
  if IsInfinite(w) then Exit(-1);
  { strokeContainThreshold where Path.contain asks no fill; a symbol in its
    own frame takes it there (SymbolHit); [R7-R] 5 of the element's own
    units (HitMinScale) [was: 5 on the canvas whatever its scale] }
  if not ElFills(AEl) and (AEl.Shape.HitSym = '') then
  begin
    if AEl.HitMinScale > 0 then w := Max(w, 5 * AEl.HitMinScale)
    else w := Max(w, Double(5));
  end;
  ps := AEl.Style.PenScale;
  if ps > 0 then w := w * ps;
  Result := w * AScale;
end;

{ the shape's own area at a point, grown by ASlopPx: a rounded sector by
  its path where nothing grows it (SectorContains is the plain ring) }
function ShapeArea(const AShape: TTyChartShape; AX, AY, ASlopPx: Double): Boolean;
begin
  { a path by its own outline (the box grown by a slop or a pad is the
    port's forgiving target) }
  if (ASlopPx <= 0) and (((AShape.Kind = cskSector) and not AShape.Sausage
    and TyHasCorner(AShape.SectorRadii)) or (AShape.Kind = cskPath)) then
    Result := TyZrShapeContainFill(AShape, AX, AY)
  else
    Result := TyShapeContains(AShape, AX, AY, ASlopPx);
end;

{ [R7-C] a pointer polygon upright, and the point with it }
procedure Upright(var AShape: TTyChartShape; var AX, AY: Double);
var
  a, c, s, dx, dy: Double;
  i: Integer;
begin
  if (AShape.Kind <> cskPolygon) or (Length(AShape.Points) < 3) then Exit;
  { the turn that takes the back-to-tip axis onto -y }
  a := ArcTan2(AShape.Points[2].X - AShape.Points[0].X,
    -(AShape.Points[2].Y - AShape.Points[0].Y));
  c := Cos(a);
  s := Sin(a);
  AShape.Points := Copy(AShape.Points, 0, Length(AShape.Points));
  for i := 0 to High(AShape.Points) do
  begin
    dx := AShape.Points[i].X;
    dy := AShape.Points[i].Y;
    AShape.Points[i].X := dx * c + dy * s;
    AShape.Points[i].Y := -dx * s + dy * c;
  end;
  dx := AX;
  dy := AY;
  AX := dx * c + dy * s;
  AY := -dx * s + dy * c;
end;

{ [R7-F] Path.contain of a quadratic edge (BezierCurve): its stroked rect --
  the curve's own extent (fromQuadratic) grown by half the width -- then
  quadratic.containStroke; it has no fill }
function QuadHit(const AShape: TTyChartShape; AWidthPx, AX, AY: Double): Boolean;
var
  path: TTyZrPath;
  box: TTyXYWH;
  n: Integer;
  old: TFPUExceptionMask;
begin
  Result := False;
  n := Length(AShape.Points);
  if (n < 2) or not (AWidthPx > 0) then Exit;
  path := nil;
  TyZrMoveTo(path, AShape.Points[0].X, AShape.Points[0].Y);
  TyZrQuad(path, AShape.HitCP.X, AShape.HitCP.Y, AShape.Points[n - 1].X, AShape.Points[n - 1].Y);
  old := GetExceptionMask;
  SetExceptionMask(old + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    box := TyZrBBox(path);
    if not ((AX >= box.X - AWidthPx / 2) and (AX <= box.X - AWidthPx / 2 + (box.W + AWidthPx))
      and (AY >= box.Y - AWidthPx / 2) and (AY <= box.Y - AWidthPx / 2 + (box.H + AWidthPx))) then Exit;
  finally
    TyZrRestoreFpu(old);
  end;
  Result := TyZrContainStroke(path, AWidthPx, AX, AY);
end;

{ [R7-F] Path.contain of a symbol in its own frame (TTyChartShape.HitSym):
  the point taken back through HitM (transformCoordToLocal), the unit
  path's rect grown by the pen over the line scale (getLineScale: the
  square root of the frame's determinant, 1 where either diagonal entry is
  1), containStroke at that width (at least strokeContainThreshold without
  a fill), then the fill. The port's pad tests the drawn shape first. }
{ the path part of it: the unit path's rect grown by AE, the stroke at ALw
  (none where it is nought), the fill -- its own routine, so the managed
  path costs nothing to the symbols refused before it }
function SymbolPathHit(const AName: string; ALx, ALy, AE, ALw: Double;
  AFill: Boolean; ABoxW, ABoxH: Double): Boolean;
var
  path: TTyZrPath;
  box: TTyXYWH;
  i, k: Integer;
begin
  Result := False;
  { [R7-R] a real box where the shape names one; [R7-V] a collapsed one (a
    side of nought) too }
  if (ABoxW >= 0) and (ABoxH >= 0) and ((ABoxW > 0) or (ABoxH > 0)) then
    path := TyZrSymbol(AName, -ABoxW / 2, -ABoxH / 2, ABoxW, ABoxH)
  else
    path := TyZrSymbol(AName, -1, -1, 2, 2);
  { [R7-Y] AS THE PROXY HOLDS IT ONCE PAINTED: toStatic stores data of more
    than eleven numbers in a Float32Array -- a point exactly on a vertex or
    an edge is in or out by those singles [was: the doubles]. Only where
    the path is upstream's own (the real box createSymbol made): the unit
    path stood in for a scaled frame rounds otherwise }
  if (ABoxW >= 0) and (ABoxH >= 0) and ((ABoxW > 0) or (ABoxH > 0))
    and (TyZrDataLength(path) > 11) then
    for i := 0 to High(path) do
      for k := 0 to TyZrArgCount(path[i].Cmd) - 1 do
        path[i].V[k] := TyJsFround(path[i].V[k]);
  box := TyZrBBox(path);
  if not ((ALx >= box.X - AE) and (ALx <= box.X - AE + (box.W + 2 * AE))
    and (ALy >= box.Y - AE) and (ALy <= box.Y - AE + (box.H + 2 * AE))) then Exit;
  if (ALw > 0) and TyZrContainStroke(path, ALw, ALx, ALy) then Exit(True);
  if AFill then Result := TyZrContain(path, ALx, ALy);
end;

function SymbolHit(const AEl: TTyChartElement; AWidthPx, APadPx, AScale: Double;
  AFill: Boolean; AX, AY: Double): Boolean;
var
  m, inv: TTyMat2D;
  det, lx, ly, ls, w, e, hx, hy, ux, uy: Double;
  b: TTyRectF;
begin
  Result := False;
  if IsNan(AX) or IsNan(AY) then Exit;
  m := AEl.Shape.HitM;
  { [R7-W] A FRAME THAT DOES NOT INVERT (a side of nought): matrix.invert
    fails and the inverse stays the one the element was made with, the
    identity -- the unit symbol at the canvas' top left, in css px [was:
    never hit] }
  det := m[0] * m[3] - m[1] * m[2];
  if (not IsNan(det)) and (det = 0) then
    m := TyZrLocal(AScale, AScale, 0, 0, 0);
  { [R7-R] the frame's half extents the refusal box scales by: the unit
    box's 1, or a real box's larger half (a pin's head may stand taller
    than its box) }
  ux := 1;
  uy := 1;
  if (AEl.Shape.HitBoxW >= 0) and (AEl.Shape.HitBoxH >= 0)
    and ((AEl.Shape.HitBoxW > 0) or (AEl.Shape.HitBoxH > 0)) then
  begin
    ux := Max(AEl.Shape.HitBoxW, AEl.Shape.HitBoxH) / 2;
    uy := ux;
  end;
  w := AWidthPx;
  if (w > 0) and not AFill then w := Max(w, 5 * AScale);
  { [R7-O] a pen in the symbol's own frame: the frame's whole scale }
  if AEl.Shape.HitPenInFrame
    or ((Abs(m[0] - 1) > 1e-10) and (Abs(m[3] - 1) > 1e-10)) then
    ls := Sqrt(Abs(m[0] * m[3] - m[2] * m[1]))
  else ls := 1;
  e := 0;
  if (w > 0) and (ls > 1e-10) then e := w / ls / 2;
  { THE CHEAP REFUSAL FIRST, nothing managed here: every built-in path lies
    in [-4/3, 4/3] x [-2, 2] of its unit box (a pin's head and an arrow's body
    leave it upward and downward, the arrow's barbs sideways: its half width
    is two thirds of its width [R7-O: was 1, which cut the barbs off]), and
    the pen reaches e past it there -- a point off that box's image under the
    frame is off the stroked rect; the pad is the drawn shape's }
  hx := (4 / 3 * ux + e) * Abs(m[0]) + (2 * uy + e) * Abs(m[2]);
  hy := (4 / 3 * ux + e) * Abs(m[1]) + (2 * uy + e) * Abs(m[3]);
  if not ((Abs(AX - m[4]) <= hx) and (Abs(AY - m[5]) <= hy)) then
  begin
    if not ((APadPx > 0) and AFill) then Exit;
    b := TyShapeBounds(AEl.Shape);
    if not ((AX >= b.Left - APadPx) and (AX <= b.Right + APadPx)
      and (AY >= b.Top - APadPx) and (AY <= b.Bottom + APadPx)) then Exit;
    Exit(ShapeArea(AEl.Shape, AX, AY, APadPx));
  end;
  if (APadPx > 0) and AFill and ShapeArea(AEl.Shape, AX, AY, APadPx) then Exit(True);
  { matrix.invert, then applyTransform }
  det := m[0] * m[3] - m[1] * m[2];
  if (det = 0) or IsNan(det) or IsInfinite(det) then Exit;
  det := 1 / det;
  inv[0] := m[3] * det;
  inv[1] := -m[1] * det;
  inv[2] := -m[2] * det;
  inv[3] := m[0] * det;
  inv[4] := (m[2] * m[5] - m[3] * m[4]) * det;
  inv[5] := (m[1] * m[4] - m[0] * m[5]) * det;
  lx := inv[0] * AX + inv[2] * AY + inv[4];
  ly := inv[1] * AX + inv[3] * AY + inv[5];
  if IsNan(lx) or IsNan(ly) or (Abs(lx) > 4 / 3 * ux + e) or (Abs(ly) > 2 * uy + e) then Exit;
  if (w > 0) and (ls > 1e-10) then
    Result := SymbolPathHit(AEl.Shape.HitSym, lx, ly, e, w / ls, AFill, AEl.Shape.HitBoxW,
      AEl.Shape.HitBoxH)
  else
    Result := SymbolPathHit(AEl.Shape.HitSym, lx, ly, e, 0, AFill, AEl.Shape.HitBoxW,
      AEl.Shape.HitBoxH);
end;

{ [R7-P] a zrender path's points through the linear map AM (no move):
  lines, quadratics and cubics exactly; a rect as its four sides; an arc
  as cubics of at most a quarter turn on its ellipse, then mapped }
function MapZrPath(const APath: TTyZrPath; const AM: TTyMat2D): TTyZrPath;
var
  i, k, n, seg: Integer;
  v: array[0..7] of Double;
  x, y, cx, cy, rx, ry, a0, da, psi, cp, sp, t0, t1, kk, c0, s0, c1, s1: Double;
  p: array[0..5] of Double;

  procedure Put(var AX, AY: Double);
  var px, py: Double;
  begin
    px := AX;
    py := AY;
    AX := AM[0] * px + AM[2] * py;
    AY := AM[1] * px + AM[3] * py;
  end;

  function Pt(ATh: Double; out AY: Double): Double;
  var ex, ey: Double;
  begin
    ex := rx * Cos(ATh);
    ey := ry * Sin(ATh);
    Result := cx + ex * cp - ey * sp;
    AY := cy + ex * sp + ey * cp;
  end;

begin
  Result := nil;
  for i := 0 to High(APath) do
  begin
    for k := 0 to 7 do v[k] := APath[i].V[k];
    case APath[i].Cmd of
      zrM:
        begin
          Put(v[0], v[1]);
          TyZrMoveTo(Result, v[0], v[1]);
        end;
      zrL:
        begin
          Put(v[0], v[1]);
          TyZrLineTo(Result, v[0], v[1]);
        end;
      zrQ:
        begin
          Put(v[0], v[1]);
          Put(v[2], v[3]);
          TyZrQuad(Result, v[0], v[1], v[2], v[3]);
        end;
      zrC:
        begin
          Put(v[0], v[1]);
          Put(v[2], v[3]);
          Put(v[4], v[5]);
          TyZrCubic(Result, v[0], v[1], v[2], v[3], v[4], v[5]);
        end;
      zrR:
        begin
          p[0] := v[0]; p[1] := v[1];
          p[2] := v[0] + v[2]; p[3] := v[1] + v[3];
          x := p[0]; y := p[1]; Put(x, y); TyZrMoveTo(Result, x, y);
          x := p[2]; y := p[1]; Put(x, y); TyZrLineTo(Result, x, y);
          x := p[2]; y := p[3]; Put(x, y); TyZrLineTo(Result, x, y);
          x := p[0]; y := p[3]; Put(x, y); TyZrLineTo(Result, x, y);
          TyZrClose(Result);
        end;
      zrA:
        begin
          cx := v[0]; cy := v[1]; rx := v[2]; ry := v[3];
          a0 := v[4]; da := v[5]; psi := v[6];
          cp := Cos(psi);
          sp := Sin(psi);
          { the pen goes to the arc's start (PathProxy's arc lines to it) }
          x := Pt(a0, y);
          Put(x, y);
          if Length(Result) = 0 then TyZrMoveTo(Result, x, y)
          else TyZrLineTo(Result, x, y);
          n := Ceil(Abs(da) / (Pi / 2) - 1e-12);
          if n < 1 then n := 1;
          for seg := 0 to n - 1 do
          begin
            t0 := a0 + da * seg / n;
            t1 := a0 + da * (seg + 1) / n;
            kk := 4 / 3 * Tan((t1 - t0) / 4);
            c0 := Cos(t0); s0 := Sin(t0);
            c1 := Cos(t1); s1 := Sin(t1);
            { on the unit circle, then the ellipse's radii, its turn, its centre }
            p[0] := c0 - kk * s0; p[1] := s0 + kk * c0;
            p[2] := c1 + kk * s1; p[3] := s1 - kk * c1;
            p[4] := c1; p[5] := s1;
            for k := 0 to 2 do
            begin
              x := rx * p[2 * k];
              y := ry * p[2 * k + 1];
              p[2 * k] := cx + x * cp - y * sp;
              p[2 * k + 1] := cy + x * sp + y * cp;
              Put(p[2 * k], p[2 * k + 1]);
            end;
            TyZrCubic(Result, p[0], p[1], p[2], p[3], p[4], p[5]);
          end;
        end;
      zrZ: TyZrClose(Result);
    end;
  end;
end;

{ [R7-P] THE STROKE OF A PEN STRETCHED BY ITS MAP (TTyChartElementStyle.
  PenMap): the canvas' pen region is the map's image of a round pen's band
  about the path the map takes back, so the path and the point go back
  through the map's inverse and containStroke asks AWidthPx there -- within
  its stroked rect first, as Path.contain. [R7-R] A turned or mirrored path
  shape (its path built in its own frame, TyZrShapePath): the point goes to
  that frame first (TyZrShapeLocal), and the map with it -- the frame's turn
  and reflection undone on the pen too, so the band about the path there is
  the same region [was: not asked, the drawn outline's round pen answered]. }
function PenMapStrokeHit(const AEl: TTyChartElement; AWidthPx, AX, AY: Double;
  out AAsked: Boolean): Boolean;
var
  E, F, inv: TTyMat2D;
  det, lx, ly, px, py, c, s: Double;
  path: TTyZrPath;
  box: TTyXYWH;
  old: TFPUExceptionMask;
begin
  Result := False;
  AAsked := False;
  { the map's shape alone: AWidthPx holds PenScale already }
  if not AEl.Style.HasPenMap then Exit;
  E := AEl.Style.PenMap;
  if AEl.Shape.Kind in [cskSector, cskLarge] then Exit;
  px := AX;
  py := AY;
  if (AEl.Shape.Kind = cskPath) and ((AEl.Shape.RotationRad <> 0) or AEl.Shape.FlipX
    or AEl.Shape.FlipY) then
  begin
    { [R7-R] into the path's own frame: the point by TyZrShapeLocal, the
      pen by the same linear part -- the reflection, then the turn undone
      (x' = c x + s y, y' = -s x + c y) }
    TyZrShapeLocal(AEl.Shape, px, py);
    if AEl.Shape.FlipX then
    begin
      E[0] := -E[0];
      E[2] := -E[2];
    end;
    if AEl.Shape.FlipY then
    begin
      E[1] := -E[1];
      E[3] := -E[3];
    end;
    if AEl.Shape.RotationRad <> 0 then
    begin
      c := Cos(AEl.Shape.RotationRad);
      s := Sin(AEl.Shape.RotationRad);
      F := E;
      E[0] := c * F[0] + s * F[1];
      E[1] := -s * F[0] + c * F[1];
      E[2] := c * F[2] + s * F[3];
      E[3] := -s * F[2] + c * F[3];
    end;
  end;
  det := E[0] * E[3] - E[1] * E[2];
  if (det = 0) or IsNan(det) or IsInfinite(det) then Exit;
  path := TyZrShapePath(AEl.Shape);
  if Length(path) = 0 then Exit;
  AAsked := True;
  if not (AWidthPx > 0) then Exit;
  inv := Default(TTyMat2D);
  inv[0] := E[3] / det;
  inv[1] := -E[1] / det;
  inv[2] := -E[2] / det;
  inv[3] := E[0] / det;
  path := MapZrPath(path, inv);
  lx := inv[0] * px + inv[2] * py;
  ly := inv[1] * px + inv[3] * py;
  old := GetExceptionMask;
  SetExceptionMask(old + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    box := TyZrBBox(path);
    if not ((lx >= box.X - AWidthPx / 2) and (lx <= box.X - AWidthPx / 2 + (box.W + AWidthPx))
      and (ly >= box.Y - AWidthPx / 2) and (ly <= box.Y - AWidthPx / 2 + (box.H + AWidthPx))) then Exit;
  finally
    TyZrRestoreFpu(old);
  end;
  Result := TyZrContainStroke(path, AWidthPx, lx, ly);
end;

{ Path.contain of a stroked shape: the fill (grown by the pad), then the
  stroke -- an open line has no fill to ask }
function StrokedHit(const AShape: TTyChartShape; AHasFill: Boolean;
  AWidthPx, APadPx, AX, AY: Double): Boolean;
var
  b: TTyRectF;
  r: Double;
begin
  if AShape.HitQuad then
    Exit(((APadPx > 0) and ShapeArea(AShape, AX, AY, APadPx)) or QuadHit(AShape, AWidthPx, AX, AY));
  { far from the shape's own bounds is far from its fill, its pad and its
    stroked rect alike: most of a list is refused here at a compare (a turned
    or mirrored path's bounds are in its own frame, and a poly's curves may
    bulge past its points where it has no measured rect: those are asked
    whole) }
  if ((AShape.Kind <> cskPath) or ((AShape.RotationRad = 0) and not AShape.FlipX
    and not AShape.FlipY)) and ((Length(AShape.Cmds) = 0) or AShape.HasCmdBounds) then
  begin
    b := TyShapeBounds(AShape);
    r := Max(AWidthPx / 2, APadPx);
    if not ((AX >= b.Left - r) and (AX <= b.Right + r) and (AY >= b.Top - r)
      and (AY <= b.Bottom + r)) then Exit(False);
  end;
  if AHasFill and ShapeArea(AShape, AX, AY, APadPx) then
    Exit(True);
  Result := TyZrShapeContainStroke(AShape, AWidthPx, AX, AY);
end;

function TyClipSectorShape(const AElement: TTyChartElement): TTyChartShape;
var st, en, t: Double;
begin
  Result := TyShapeSector(AElement.ClipCX, AElement.ClipCY, AElement.ClipR0,
    AElement.ClipR1, 0, 1);
  st := AElement.ClipSA;
  en := AElement.ClipEA;
  if AElement.ClipCW then
  begin
    if en - st >= 2 * Pi then en := st + 2 * Pi
    else if st > en then en := st + (2 * Pi - (st - en - Floor((st - en) / (2 * Pi)) * 2 * Pi));
  end
  else
  begin
    if st - en >= 2 * Pi then en := st - 2 * Pi
    else if st < en then en := st - (2 * Pi - (en - st - Floor((en - st) / (2 * Pi)) * 2 * Pi));
    t := st;
    st := en;
    en := t;
  end;
  Result.StartRad := st;
  Result.EndRad := en;
end;

{ [R7-I] a point outside the clip an element's hit is cut to (ClipHits):
  its rect, or its sector (createPolarClipPath's Sector.contain) -- its own
  routine, so the sector's shape (a managed record) costs nothing to the
  elements that have no clip }
function OutsideHitClip(const AEl: TTyChartElement; AX, AY: Double): Boolean;
begin
  Result := False;
  if AEl.HasClip
    and not ((AX >= AEl.ClipRect.Left) and (AX <= AEl.ClipRect.Right)
      and (AY >= AEl.ClipRect.Top) and (AY <= AEl.ClipRect.Bottom)) then Exit(True);
  if AEl.HasClipSector
    and not TyShapeContains(TyClipSectorShape(AEl), AX, AY, 0) then Exit(True);
end;

{ the same over a pointer turned upright -- its own routine, so the copy of
  the shape (a managed record) costs nothing to the elements that need none }
function UprightHit(const AEl: TTyChartElement; AWidthPx, APadPx, AX, AY: Double): Boolean;
var shape: TTyChartShape;
begin
  shape := AEl.Shape;
  Upright(shape, AX, AY);
  Result := StrokedHit(shape, ElFills(AEl), AWidthPx, APadPx, AX, AY);
end;

{ [R7-O] a ZrHit whose pen is the style's now: Path.contain's stroked rect
  and stroke at max(width, 5) over the line scale (the path has no fill) --
  its own routine, so the managed copy costs nothing to the rest }
function StyleZrHit(const AEl: TTyChartElement; AX, AY: Double; APPI: Integer): Boolean;
var
  h: TTyZrHit;
  w, s: Double;
begin
  Result := False;
  w := AEl.Style.StrokeWidthLogical;
  if not (w > 0) or (((AEl.Style.StrokeColor shr 24) = 0)
    and (AEl.Style.StrokeGradient.Kind = cgkNone) and not AEl.Style.HitClearPen) then Exit;
  if IsInfinite(w) then Exit;
  if APPI > 0 then s := APPI / 96 else s := 1;
  w := w * s;
  if not (AEl.ZrHit.LineScale > 1e-10) then Exit;
  h := AEl.ZrHit;
  h.Box := TyZrStrokeRect(AEl.ZrHit.PathBox, Length(AEl.ZrHit.Path), True, False,
    w, AEl.ZrHit.LineScale);
  h.Stroke := True;
  h.LineWidth := Max(w, Double(5) * s) / AEl.ZrHit.LineScale;
  Result := TyZrHitContains(h, AX, AY);
end;

{ [R7-S] Path.contain of a graphic or custom series element in its own
  frame (TTyZrHit.OwnPen): the pen as the style holds it now -- its own
  routine, so the managed copy costs nothing to the rest }
function OwnZrHit(const AEl: TTyChartElement; AX, AY: Double): Boolean;
var
  h: TTyZrHit;
  lw, w: Double;
  stroke: Boolean;
begin
  h := AEl.ZrHit;
  { hasStroke() as the style is now: the pen it was built with, or one a
    state gives it }
  stroke := h.Stroke or ((AEl.Style.StrokeColor shr 24) <> 0)
    or (AEl.Style.StrokeGradient.Kind <> cgkNone);
  if not IsNan(h.FixedLw) then lw := h.FixedLw
  else if (AEl.Style.StrokeWidthLogical > 0) and (h.LwDiv > 0) then
    lw := AEl.Style.StrokeWidthLogical / h.LwDiv
  else lw := 0;
  { hasStroke(): a pen of a width above nought -- a state that takes it to
    none takes the stroke away }
  if not (lw > 0) then stroke := False;
  { an infinite pen: the stroked rect is not a number, nothing is inside }
  if stroke and IsInfinite(lw) then Exit(False);
  w := lw;
  if stroke and not h.Fill then w := Max(w, Double(5));
  if not (h.LineScale > 1e-10) then stroke := False;
  h.Box := h.PathBox;
  if stroke then
  begin
    { width first, then x -- rectStroke.width += w; rectStroke.x -= w / 2 }
    h.Box.W := h.PathBox.W + w / h.LineScale;
    h.Box.H := h.PathBox.H + w / h.LineScale;
    h.Box.X := h.PathBox.X - w / h.LineScale / 2;
    h.Box.Y := h.PathBox.Y - w / h.LineScale / 2;
    h.LineWidth := w / h.LineScale;
  end;
  h.Stroke := stroke;
  Result := TyZrHitContains(h, AX, AY);
end;

function TyElementHit(const AEl: TTyChartElement; AX, AY: Double; APPI: Integer;
  APad: Boolean): Boolean;
var
  k: Integer;
  s, w, pad, padArea, c, sn, dx, dy, lx, ly, r: Double;
  asked: Boolean;
begin
  if AEl.HitNone then Exit(False);
  for k := 0 to High(AEl.ClipPaths) do
    if not TyShapeContains(AEl.ClipPaths[k], AX, AY, 0) then Exit(False);
  { [R7-I] the rect or the sector [was: the rect alone] }
  if AEl.ClipHits and OutsideHitClip(AEl, AX, AY) then Exit(False);
  { [R7-S] a graphic or custom element: all of it in its own frame }
  if AEl.ZrHit.Active and AEl.ZrHit.OwnPen then Exit(OwnZrHit(AEl, AX, AY));
  if AEl.ZrHit.Active and AEl.ZrHit.StyleWidth then
    Exit(StyleZrHit(AEl, AX, AY, APPI));
  if AEl.ZrHit.Active then Exit(TyZrHitContains(AEl.ZrHit, AX, AY));
  if AEl.PathHit.Active then Exit(TyPathHitContains(AEl.PathHit, AX, AY));
  if APPI > 0 then s := APPI / 96 else s := 1;
  pad := 0;
  if APad then pad := AEl.HitPadLogical * s;
  w := 0;
  if AEl.Shape.Kind in [cskRect, cskRoundRect, cskCircle, cskEllipse, cskSector,
    cskPolyline, cskPolygon, cskPath] then
    w := TyElementStrokeHitPx(AEl, s);
  if w < 0 then Exit(False);
  { [R7-F] a turned label in its own frame }
  if AEl.Caption.HasHitRel and ((AEl.Caption.RotationRad <> 0) or AEl.Caption.HitRelOwn)
    and (w = 0) then
  begin
    c := Cos(AEl.Caption.RotationRad);
    sn := Sin(AEl.Caption.RotationRad);
    dx := AX - AEl.Caption.X;
    dy := AY - AEl.Caption.Y;
    lx := dx * c - dy * sn;
    ly := dx * sn + dy * c;
    r := AEl.HitSlopLogical * s + pad;
    Exit((lx >= AEl.Caption.HitRel.Left - r) and (lx <= AEl.Caption.HitRel.Right + r)
      and (ly >= AEl.Caption.HitRel.Top - r) and (ly <= AEl.Caption.HitRel.Bottom + r));
  end;
  { [R7-F] THE PAD TOPS THE PEN'S REACH UP TO ITS FOUR PIXELS: the drawn
    shape grown by both (TySymbolHitSlop's reach is the slop) -- the pen's
    own reach alone answered past the pad [R7-C: the pad was all of it] }
  padArea := 0;
  if pad > 0 then padArea := AEl.HitSlopLogical * s + pad;
  { [R7-F] a symbol in its own frame, upstream's own outline }
  if AEl.Shape.HitSym <> '' then Exit(SymbolHit(AEl, w, padArea, s, ElFills(AEl), AX, AY));
  { [R7-P] a pen the map stretches: its stroke in the map's own space }
  if (w > 0) and AEl.Style.HasPenMap and not AEl.HitUpright then
  begin
    if ElFills(AEl) and ShapeArea(AEl.Shape, AX, AY, padArea) then Exit(True);
    Result := PenMapStrokeHit(AEl, w, AX, AY, asked);
    if asked then Exit;
  end;
  if w > 0 then
  begin
    { the slop the builder gave the element stood for the stroke and is not
      asked }
    if AEl.HitUpright then Exit(UprightHit(AEl, w, padArea, AX, AY));
    Exit(StrokedHit(AEl.Shape, ElFills(AEl), w, padArea, AX, AY));
  end;
  { an open line with neither a pen nor a fill: Path.contain has nothing to
    ask (a line written at width 0) }
  if (AEl.Shape.Kind = cskPolyline) and not AEl.Style.HasFill
    and not (AEl.Style.StrokeWidthLogical > 0) then Exit(False);
  { [R7-F] nor a closed shape whose fill is 'none' and that strokes nothing }
  if (AEl.Shape.Kind <> cskPolyline) and AEl.Style.HitNoFill then Exit(False);
  Result := ShapeArea(AEl.Shape, AX, AY, AEl.HitSlopLogical * s + pad);
end;

function TyElementContains(const AEl: TTyChartElement; AX, AY, ASlopPx: Double): Boolean;
var k: Integer;
begin
  if AEl.HitNone then Exit(False);
  { [spec 242] a point outside a clip path is not over the element }
  for k := 0 to High(AEl.ClipPaths) do
    if not TyShapeContains(AEl.ClipPaths[k], AX, AY, 0) then Exit(False);
  if AEl.ClipHits and OutsideHitClip(AEl, AX, AY) then Exit(False);
  if AEl.ZrHit.Active then Result := TyZrHitContains(AEl.ZrHit, AX, AY)
  else if AEl.PathHit.Active then Result := TyPathHitContains(AEl.PathHit, AX, AY)
  else Result := TyShapeContains(AEl.Shape, AX, AY, ASlopPx);
end;

var
  GHitBandOn: Boolean = False;
  GHitBandLo, GHitBandHi: Integer;

procedure TySetHitBand(ALo, AHi: Integer);
begin
  GHitBandOn := True;
  GHitBandLo := ALo;
  GHitBandHi := AHi;
end;

procedure TyClearHitBand;
begin
  GHitBandOn := False;
end;

function TyHitBandHas(AZ: Integer): Boolean;
begin
  Result := not GHitBandOn or ((AZ > GHitBandLo) and (AZ <= GHitBandHi));
end;

function TTyPaintList.HitTestElement(AX, AY: Double; APPI: Integer;
  APad: Boolean): Integer;
var
  i, idx: Integer;
  half: Double;
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
    { [R5-J] the canvas searched now }
    if GHitBandOn and not TyHitBandHas(FItems[idx].ZLevel) then Continue;
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
    if TyElementHit(FItems[idx], AX, AY, APPI, APad) then
      Exit(idx);
  end;
end;

function TTyPaintList.TopElementAt(AX, AY: Double; APPI: Integer): Integer;
var
  i, idx: Integer;
begin
  Result := -1;
  EnsureOrder;
  for i := FCount - 1 downto 0 do
  begin
    idx := FOrder[i];
    if FItems[idx].Ignore or FItems[idx].ProgHidden then Continue;
    if TyElementHit(FItems[idx], AX, AY, APPI, True) then
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