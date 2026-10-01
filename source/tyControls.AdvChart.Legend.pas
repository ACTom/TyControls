unit tyControls.AdvChart.Legend;
{$mode objfpc}{$H+}
{ The legend -- the component that names the series and, once it can be
  clicked, decides which of them are drawn.

  103 of the 244 converted examples carry one, which is more than any other
  optional component; 21 of them write nothing but `legend: {}`, so the
  DEFAULTS are most of the feature. They are `left: 'center'`, `bottom: 15`,
  `itemGap: 8`, `itemWidth: 25`, `itemHeight: 14`, `padding: 5` -- and the
  generated option catalog is wrong about four of those (it says `left: auto`,
  `bottom: auto`, `itemGap: 10`, `borderWidth: 1`), so a legend seeded from the
  catalog would sit in the top-left corner instead of centred on the bottom
  edge. Read from src/component/legend/LegendModel.ts, ECharts 6.1.0.

  IT DOES NOT SHRINK THE GRID, for the same reason the title does not: upstream
  gives every component the same container and lets sensible defaults keep them
  apart. The grid's own default bottom gap is what leaves room for a legend.

  WHAT IS NOT HERE, and none of it is an oversight:

    THE CLICK. Drawing a legend and toggling one are two different jobs and the
    second needs machinery this control does not have yet -- a mouse path, a hit
    test, and a full re-layout on every toggle. NOTHING HIT-TESTS ANYTHING in
    this control yet: the paint list's HitTest has no production caller and the
    list is freed at the end of the frame that built it. When the click lands it
    must also set the control's dirty flag and drop the static layer, because a
    plain repaint runs neither Rebuild nor Relayout and the filter below would
    never re-run.
    [Stale since the tooltip batches: the paint list IS hit-tested now --
    HitTestAt serves the tooltip and the hover. The click itself is still not
    here, and the rest of this paragraph stands.]
    [Batch 93: the click, the hover and the five legend actions are here --
    LegendModel's select / unSelect / toggleSelected / allSelect /
    inverseSelect on the option's own `selected` map (the model keeps its
    state in its option, and so does this port), and the control runs the
    full update after each.]

    What IS here is everything decided before anyone clicks: `legend.selected`,
    the `selectedMode: 'single'` resolution that upstream performs AT LOAD, the
    inactive styling, and the FILTER those imply. Those are static option state,
    and a legend that ignored them would draw the wrong picture on the FIRST
    frame, which is a different kind of wrong from being inert.

    THE SELECTOR BUTTONS and the SCROLLING (`type: 'scroll'`) LEGEND. Both are
    controls -- an All/Inverse pair and a pager -- and an inert control is worse
    than an absent one. They land with the click. Two corpus examples ask for
    `type: 'scroll'` and get a plain legend that overflows instead.
    [Batch 98: both are here -- LegendView's selector layout and
    ScrollableLegendView's pager, clip and page info, transcribed in their own
    arithmetic (LayoutRich), the buttons' and the page buttons' clicks, the
    legendScroll action and the scroll's tween.]

    A `line` ICON WITH A VISIBLE PEN. Upstream draws `legend.icon: 'line'`
    on a bar or a pie as NOTHING AT ALL, and by a route worth naming:
    `itemStyle.borderWidth: 'auto'` resolves to 0 unless the SERIES has a
    border, `itemStyle.stroke: 'inherit'` resolves to the series' own stroke
    which is absent, and a path with neither pen nor width draws no line. The
    rule is a consequence of reading `series.itemStyle`, which this port does
    not do yet -- so transcribing the invisible half of it now would hide the
    icon for a reason that does not exist here. A line icon draws a line; when
    series item styles land, this becomes a real question.

    THE OPTION'S OWN COLOURS. `textStyle.color`, `inactiveColor`,
    `backgroundColor` and the `itemStyle`/`lineStyle` colour sentinels are not
    read, because nothing in this port reads a colour out of an option yet --
    not `color`, not `series.itemStyle.color` either. Every colour comes from
    the theme. When the palette row lands it brings a colour parser and serves
    all of them at once; reading one block early would mean a legend that obeys
    `legend.textStyle.color` while the series beside it ignores
    `series.itemStyle.color`.
    [Stale: the palette row landed (AdvChart.Color) and the series' colours,
    a visualMap's included, are read from the option now; the legend reads
    whether it has a `backgroundColor`. Its own text, inactive and swatch
    colours are still the theme's.]
    [Batch 83 reads `textStyle.color`; batch 93 `inactiveColor`,
    `inactiveBorderColor`, `inactiveBorderWidth` and the rule's
    `lineStyle.inactiveColor` / `inactiveWidth`, over the theme's inactive
    ink, and the series' own border on the icon.]

  THE FILTER, and where it lives. `TyLegendHides` is the whole rule this unit
  contributes; the control applies it, because what a switched-off name MEANS
  depends on what kind of series wears it:

    A SERIES is flagged and every solver downstream skips it, so the axis
    extents, the stack groups and the bar widths all come from the survivors.
    A legend that stopped drawing a series but left the axis sized for it
    would leave the survivor a sliver -- which a reader would call broken.

    A PIE is filtered ONE ROW AT A TIME, because its legend names slices and
    not the series. That is upstream's split too: legendFilter removes whole
    series, processor/dataFilter removes rows.

  Both run BEFORE anything is counted -- upstream puts legendFilter at
  priority 800 with the stack pass at 900 and the axis statistics at 920, and
  says in a comment why that order and no other.

  PURE: SysUtils, Math, fpjson and the AdvChart units. Text is MEASURED through
  the injected measurer; ink and fonts arrive resolved from the theme. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Symbol, tyControls.AdvChart.Paint,
  tyControls.AdvChart.ZrPath;

type
  TTyLegendOrient = (tloHorizontal, tloVertical);
  { Resolved, never tlaAuto by the time a caller sees a layout. }
  TTyLegendAlign = (tlaAuto, tlaLeft, tlaRight);
  { `false`, `true`, `'single'`, `'multiple'`. Upstream tests for `'single'` and
    for nothing else, so `'multiple'` and `true` are the same value; `false`
    only silences the item, which is why it is indistinguishable from
    tlsMultiple until the click exists. }
  TTyLegendSelectedMode = (tlsMultiple, tlsSingle, tlsOff);

  { ONE SELECTOR BUTTON as LegendModel._updateSelector normalises
    `legend.selector`: `true` is ['all', 'inverse'], a word is the object (type: word),
    and the locale's title fills a title the option left out (zrUtil.merge,
    never overwriting). A type that is neither keeps no default title, and
    its click is the inverse's -- the view asks `type === 'all'` and
    nothing else. [Batch 98] }
  TTyLegendSelectorBtn = record
    Kind: string;
    IsAll: Boolean;
    Title: string;
  end;
  TTyLegendSelectorBtns = array of TTyLegendSelectorBtn;

  TTyLegendFont = record
    Name: string;
    SizeLogical: Integer;
    Weight: Integer;
    { THE ITEMS' TEXT BLOCK: legend.textStyle's `rich`, box and size, and the
      root's side -- the words (legend.formatter's) are laid out as the block
      and measured as one [Batch 86] }
    Rt: TTyRtBlockStyle;
    RtGlobal: TTyRtGlobal;
  end;

  { One row of `legend.data`, or one name the chart offered when there is no
    `legend.data`. }
  TTyLegendEntry = record
    Name: string;
    { `legend.data[i].icon`; '' when the row did not name one. The ABSENCE
      matters: an absent icon and `icon: 'roundRect'` take different branches,
      because only the absent one lets a line series draw its own. }
    Icon: string;
    { `''` and a lone newline are not items at all -- they are line breaks. }
    Newline: Boolean;
  end;
  TTyLegendEntryArray = array of TTyLegendEntry;
  TTyLegendFlags = array of Boolean;
  { The names a chart offers a legend. Named because the two lists that
    matter -- what a legend falls back to and what it is allowed to match --
    cross a procedure boundary. }
  TTyLegendNames = array of string;

  { What the chart can say about one name. Filled in by the control, because
    this unit asks the theme and the data nothing.

    Found = False is a real answer and not a failure: a `legend.data` entry
    naming a series that does not exist is drawn, greyed, and upstream logs a
    warning.
    [Batch 98: the reason is wrong -- LegendView.renderInner draws NOTHING for
    a name no series and no data provider answers to (a probe on the 6.1
    build: data A, Nope, B gives the items 0 and 2); it only warns. The port
    still draws it greyed; a scroll legend counts its pages over that extra
    item. Left as is: changing it moves batch 45's tests.] }
  TTyLegendSource = record
    Found: Boolean;
    { 'bar' | 'line' | 'scatter' | 'pie' | '' }
    SeriesType: string;
    { The series' colour, or -- for a pie -- the DATUM's, because a pie legend
      names slices rather than series. }
    Colour: TTyChartColor;
    { The `legendIcon` visual: the series' own symbol where it has one, and ''
      where it has none. A bar and a pie have none, which is the whole reason
      the default legend icon is a rounded rectangle. A line's is 'emptyCircle'
      -- NOT 'circle': LineSeries.defaultOption names it, so the base class'
      'circle' is never reached. }
    DefaultIcon: string;
    { The series draws its OWN legend icon -- a rule with a marker sitting on
      it. Only a line does, upstream and here. }
    OwnIcon: Boolean;
    { The rule's colour and its width, LOGICAL px. `lineStyle.width: 'auto'`
      resolves to 2 for a series that draws a line and 0 for one that does
      not, and 2 is also the width this port's line mark builder falls back
      to -- so the legend's rule is the same thickness as the line it stands
      for, which is the whole point of the rule. Zero means no rule: the
      marker sits alone. }
    LineColour: TTyChartColor;
    LineWidthLogical: Double;
    { DRAWN INACTIVE WHATEVER THE LEGEND SAYS. The one case is a graph's
      category whose graph the legend switched off by its SERIES name:
      upstream never colours those categories and then throws dereferencing
      the colour it did not make. Its own comment says a name that cannot be
      found in the filtered data "will display as gray", so that is what this
      does. }
    Greyed: Boolean;
    { THE DATUM'S OWN OPACITY, for a swatch standing for a datum: a
      visualMap's. HasOpacity False is opaque. }
    HasOpacity: Boolean;
    Opacity: Double;
    { THE SERIES' (or the datum's) OWN BORDER, its style visual: the stroke
      `itemStyle.stroke: 'inherit'` takes and the width
      `borderWidth: 'auto'` asks about -- a pie's is 1 by default and has no
      colour, a bar's none at all. LOGICAL px. [Batch 93] }
    HasStroke: Boolean;
    Stroke: TTyChartColor;
    VisualLineWidth: Double;
  end;
  TTyLegendSourceArray = array of TTyLegendSource;

  TTyLegendSpec = record
    Show: Boolean;
    { THE BOX AS UPSTREAM'S MODEL HOLDS IT: the raw option values over the
      defaults (left 'center', bottom 15), merged by mergeLayoutParam's
      ignoreSize rule. `width` and `height` are wrap limits, not sizes. }
    Box: TTyRawBox;
    { CSS order: top, right, bottom, left. }
    Padding: array[0..3] of Double;
    Orient: TTyLegendOrient;
    Align: TTyLegendAlign;
    ItemGap: Double;
    ItemWidth, ItemHeight: Double;
    { `legend.icon`; '' when absent. }
    Icon: string;
    { A `{name}` template. Replaced ONCE, because upstream calls
      String.replace with a string pattern rather than a global regexp. }
    Formatter: string;
    SelectedMode: TTyLegendSelectedMode;
    HasBackground: Boolean;
    BorderWidth: Double;
    BorderRadii: TTyCornerRadii;
    { `legend.z`, so the legend sorts against the series in the one paint
      list. Default 4. }
    Z: Integer;
    { `inactiveBorderWidth: 'auto'`, the default and the ONLY value upstream
      resolves: any other value -- a number included -- leaves an unselected
      icon the width its selected self had (LegendView.ts:668-670)
      [Batch 93] }
    InactiveBorderAuto: Boolean;
    { ==== [Batch 98] the selector buttons and the scrolling legend ====

      `type: 'scroll'`: ScrollableLegendModel/View -- one line that never
      wraps, clipped, with a pager. }
    IsScroll: Boolean;
    { `selector`, normalised; HasSelector False when it is false or absent.
      An empty array is still a selector -- an empty group that takes its
      gap, as upstream's `if (selector)` on [] does. }
    HasSelector: Boolean;
    Selector: TTyLegendSelectorBtns;
    { selectorPosition, resolved: 'auto' (or missing) is 'end' on a
      horizontal legend and 'start' otherwise; anything but 'end' lays out
      as 'start' }
    SelectorAtEnd: Boolean;
    SelectorItemGap, SelectorButtonGap: Double;
    { scrollDataIndex as the model holds it: a number, or anything else
      (which matches no item -- `===` against an index) }
    ScrollIsNum: Boolean;
    ScrollNum: Double;
    PageButtonItemGap: Double;
    { NaN is null: retrieve2 falls back to itemGap }
    PageButtonGap: Double;
    { pageButtonPosition === 'end'; anything else is the start }
    PageButtonAtEnd: Boolean;
    { pageFormatter: a truthy string (a template, or '@Name'); anything else
      leaves the placeholder text in place }
    HasPageFormatter: Boolean;
    PageFormatter: string;
    { pageIcons[orient][0 prev, 1 next]: 'path://', raw path data or
      'image://'; '' where the option's array is short }
    PageIcons: array[TTyLegendOrient, 0..1] of string;
    PageIconW, PageIconH: Double;
  end;

  { One placed item. Everything is DEVICE px and absolute. }
  TTyLegendItem = record
    Entry: Integer;
    Name: string;
    { After the formatter. }
    Text: string;
    Selected: Boolean;
    { The resolved icon word -- after `legend.data[i].icon`, `legend.icon`, the
      series' own symbol and the 'roundRect' floor have all had their turn. }
    Icon: string;
    OwnIcon: Boolean;
    Colour: TTyChartColor;
    LineColour: TTyChartColor;
    LineWidthLogical: Double;
    { The box createSymbol is handed: itemWidth x itemHeight, scaled. }
    IconBox: TTyRectF;
    TextX, TextY: Double;
    TextW, TextH: Double;
    AnchorH: TTyTextAnchorH;
    { The item's own rectangle -- icon and words together, ink overhang
      included. This is what the wrap measured and what a click will hit. }
    Bounds: TTyRectF;
    { the datum's opacity on its swatch }
    HasOpacity: Boolean;
    Opacity: Double;
    { THE ICON'S PEN, getLegendStyle's (LegendView.ts:599-681) for this
      item's state: selected, the series' stroke at 2 when the series has a
      border and 0 when not; unselected, inactiveBorderColor -- at 2 only
      when the series has a border AND a stroke (`'auto'`), else at the
      selected width. HasStroke is the series' stroke; IconPen LOGICAL px,
      0 no pen. [Batch 93] }
    HasStroke: Boolean;
    Stroke: TTyChartColor;
    IconPen: Double;
  end;
  TTyLegendItemArray = array of TTyLegendItem;

  { [Batch 98] ONE SELECTOR BUTTON PLACED: its Text's global position (the
    top-left of its padded box -- setLabelStyle drops the view's
    center/middle, so the box hangs left/top from it), its box in its own
    frame and in the chart's (the border's half pen included), and its
    words laid out at rest and hovered. Device px. }
  TTyLegendSelLaid = record
    IsAll: Boolean;
    Title: string;
    X, Y: Double;
    Local: TTyXYWH;
    Box: TTyRectF;
    Pieces, EmphPieces: TTyRtPieceArray;
  end;
  TTyLegendSelLaidArray = array of TTyLegendSelLaid;

  { [Batch 98] one of the pager's three -- an icon or the page text: its
    global position, its rect in its own frame and in the chart's, and an
    icon's path fitted about the origin (graphic.createIcon). Device px. }
  TTyLegendPagerPart = record
    X, Y: Double;
    Local: TTyXYWH;
    Box: TTyRectF;
    Path: TTyZrPath;
    { an 'image://' icon: laid out, never drawn }
    IsImage: Boolean;
  end;

  TTyLegendLayout = record
    Valid: Boolean;
    { The background box, padding included. }
    Frame: TTyRectF;
    { The items' own extent, padding excluded. }
    Content: TTyRectF;
    Align: TTyLegendAlign;
    Items: TTyLegendItemArray;
    { ==== [Batch 98] ====
      the view group's position and what layoutInner returned, group-local }
    GroupX, GroupY: Double;
    MainRect: TTyXYWH;
    Selector: TTyLegendSelLaidArray;
    IsScroll: Boolean;
    { the pager is drawn and takes the pointer only when the items overflow;
      it is laid out (and sized into the main rect) either way }
    ShowController: Boolean;
    PagePrev, PageNext, PageTextPart: TTyLegendPagerPart;
    PageText: string;
    { _getPageInfo: the page shown (pageIndex, -1 with no items), how many,
      and the data index a page button scrolls to (-1: null, nowhere) }
    PageIndex, PageCount, PagePrevIndex, PageNextIndex: Integer;
    { the content's clip, device px and absolute; HasClip only with the
      pager shown }
    HasClip: Boolean;
    Clip: TTyRectF;
    { the page text's font, as the layout measured it }
    PageFontName: string;
    PageFontSize, PageFontWeight: Integer;
    { THE CONTENT GROUP'S POSITION, group-local: where the page puts it
      (ContentPos) and where it stands before any page is applied
      (ContentFrom -- a first render's start, contentPos before
      _getPageInfo). The scroll tweens between them; everything above is
      laid out at ContentPos. }
    ContentPosX, ContentPosY, ContentFromX, ContentFromY: Double;
  end;

  { [Batch 98] WHAT THE CONTROL RESOLVES for the selector buttons and the
    pager: the buttons' text block finished (the skin's font and ink under
    selectorLabel, padding, border and radius in it) and the same block in
    the hovered ink; the page text's font and the raw measurer the items'
    block measurer wraps. }
  TTyLegendDeco = record
    SelBlock, SelEmphBlock: TTyRtBlockStyle;
    PageFontName: string;
    PageFontSize, PageFontWeight: Integer;
    Measurer: ITyTextMeasurer;
  end;

  { Resolved from the theme by the control, like every other visual value in
    this layer. }
  TTyLegendInk = record
    Text: TTyChartColor;
    Inactive: TTyChartColor;
    Border: TTyChartColor;
    Background: TTyChartColor;
    { The hole in an `empty` icon: the chart's own ground, so the ring reads as
      a hole rather than as a white dot on a dark skin. }
    EmptyFill: TTyChartColor;
    { AN UNSELECTED ITEM'S PEN AND RULE: `inactiveBorderColor`, and the line
      series' rule's `lineStyle.inactiveColor` / `inactiveWidth` -- the
      theme's inactive ink and 2 unless the author wrote them. A width of 0
      keeps the selected rule's width. [Batch 93] }
    InactiveBorder: TTyChartColor;
    LineInactive: TTyChartColor;
    LineInactiveWidth: Double;
    { [Batch 98] the pager: pageIconColor, pageIconInactiveColor and
      pageTextStyle.color, the skin's under the option's }
    PageIcon, PageIconInactive, PageText: TTyChartColor;
  end;

{ How many legends the option carries. An object counts as one. }
function TyLegendCount(AOption: TTyChartOption): Integer;
function TyLegendSpecDefault: TTyLegendSpec;
function TyLegendSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyLegendSpec;

{ THE TWO BOX SOLVES of LegendView.layout, both getLayoutRect on the merged
  option with the padding as margin: the room the items may wrap in -- the
  option's own box, keywords and all -- and the place of the block they
  made, the measured size winning over any width or height written. In
  device px. }
function TyLegendWrapRect(const ASpec: TTyLegendSpec;
  const AContainer: TTyRectF; APPI: Integer): TTyXYWH;
function TyLegendPlaceRect(const ASpec: TTyLegendSpec;
  const AContainer: TTyRectF; AMainW, AMainH: Double;
  APPI: Integer): TTyXYWH;

{ The entries, in order. `legend.data` when it is an array -- INCLUDING an
  empty one, which is upstream's way of asking for no items at all -- and
  APotential otherwise. Duplicate names are dropped, first one wins, and that
  applies to the line-break markers too: a legend can carry one '' and one
  newline and no more. }
function TyLegendEntries(AOption: TTyChartOption; AIndex: Integer;
  const APotential: array of string): TTyLegendEntryArray;

{ Which entries are switched on, `legend.selected` and `selectedMode` resolved
  the way upstream resolves them at LOAD.

  AAvailable is every name the chart can offer -- series names plus the data
  names of the series whose legend names their data. A name that is not in it
  reads as NOT selected however the map is written, which is what greys out a
  `legend.data` entry that names nothing. }
function TyLegendSelected(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AAvailable: array of string;
  AMode: TTyLegendSelectedMode): TTyLegendFlags;

{ Whether THIS legend switches AName off -- the question the filter asks of
  every series and of every pie slice.

  IT IS NOT `not selected`, and the difference is a chart going blank. A name
  the legend does not list at all is not switched off; it is simply not the
  legend's business. `TyLegendSelected` answers False for such a name too --
  because it also answers False for a name the CHART cannot produce, which is
  how a `legend.data` entry naming nothing gets greyed -- and a filter that
  read that answer directly would hide every series the legend never
  mentioned, starting with every series that has no `name` at all.

  Upstream is immune to this by accident of naming: every series gets a
  generated unique name and every one of them goes into `_availableNames`, so
  `isSelected` finds it and the `selected` map has no key for it. This port
  has no such names, so the rule is stated rather than inherited.

  ONE LEGEND SAYING NO IS ENOUGH, so a caller with several ORs the answers --
  legendFilter.ts:36-41 says exactly that.

  [Overturned in part, batch 31: "not the legend's business" holds only for a
  name `selected` does not mention either. See the overload below, which is
  the one the control asks.] }
function TyLegendHides(const AEntries: TTyLegendEntryArray;
  const AFlags: TTyLegendFlags; const AName: string): Boolean; overload;

{ THE WHOLE RULE: the listed answer above, plus A NAME `selected` SWITCHES
  OFF BY NAME, listed or not. Upstream's isSelected reads the map before it
  reads the list, and every series name is available, so a `selected` map
  writing `"a": false` hides series `a` whether `legend.data` names it or
  not -- which matters most for a graph with categories, whose legend lists
  the categories and never the series.

  Only the availability half is left out, and that is what keeps the old
  rule's point: a series name is always available upstream, and a name this
  port could not prove available must not blank a series. The empty name is
  still never hidden. }
function TyLegendHides(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const AName: string): Boolean; overload;

{ UPSTREAM'S `isSelected(name)`, FOR ANY NAME -- listed or not.

  TyLegendHides leaves out the availability half, deliberately, for series.
  The graph's category filter is upstream's categoryFilter, which asks
  isSelected for every node's category, listed or not: a name switched off in
  `selected` is off whether `legend.data` names it or not, and a name the
  chart does not offer at all -- a category index out of range, a name nobody
  declared -- is NEVER selected, so its nodes go.

  A listed name answers with its flag, which already carries single mode's
  rewrite; an unlisted one asks the `selected` map and the available names,
  which single mode never touched. }
function TyLegendNameSelected(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const AAvailable: array of string; const AName: string): Boolean;

{ ==== THE SELECTION AFTER LOAD, LegendModel.ts:388-440 [Batch 93] ====

  THE MODEL KEEPS ITS STATE IN ITS OPTION: `init` makes `option.selected`
  when it is missing, every action writes into it, and `isSelected` reads
  it. So does this port -- these work on the `selected` object of the
  legend's own node in the option tree (the control's Option text is left as
  the host wrote it), and everything above that reads `selected` reads what
  the actions wrote. }

{ `option.selected ||= {}`: the map, made when missing (and when what is
  there is not an object). nil when the legend itself is not an object. }
function TyLegendSelectedNode(AOption: TTyChartOption; AIndex: Integer): TJSONObject;
{ isSelected: not switched off in the map (any falsy value is off), and a
  name the chart offers. }
function TyLegendIsSelected(AOption: TTyChartOption; AIndex: Integer;
  const AAvailable: array of string; const AName: string): Boolean;
{ select: in single mode every item of the legend's data goes false first --
  line breaks included, they are items upstream. }
procedure TyLegendSelectName(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; AMode: TTyLegendSelectedMode;
  const AName: string);
{ unSelect: a no-op in single mode. }
procedure TyLegendUnSelectName(AOption: TTyChartOption; AIndex: Integer;
  AMode: TTyLegendSelectedMode; const AName: string);
{ toggleSelected: an absent name counts as selected. }
procedure TyLegendToggleName(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; AMode: TTyLegendSelectedMode;
  const AName: string);
procedure TyLegendAllSelect(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray);
procedure TyLegendInverseSelect(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray);
{ optionUpdated in single mode: the first selected item is selected (the
  others go false), or the first item when none is. }
procedure TyLegendResolveSingle(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AAvailable: array of string);
{ An object's keys in JavaScript's own order: integer-like keys ascending,
  then the rest in insertion order. }
function TyJsKeyOrder(AObj: TJSONObject): TTyLegendNames;
{ The legend's `selected` map as JSON, in that order; '{}' when it has none. }
function TyLegendSelectedJson(AOption: TTyChartOption; AIndex: Integer): string;

{ `{name}`, replaced once. An empty formatter answers the name unchanged. }
function TyLegendText(const AFormatter, AName: string): string;

{ The `legendIcon` visual a series of this type publishes: ITS OWN SYMBOL
  where it has one, and '' where it has none.

  Only a series with a symbol visual publishes anything, and '' is what sends
  the icon chain on to `roundRect` -- which is the whole reason a bar and a
  pie get rounded rectangles. ASymbolWord is `series.symbol` as written, ''
  when the option did not name one.

  THE TWO DEFAULTS ARE NOT THE SAME WORD. A scatter reaches the base class'
  'circle'; a line names 'emptyCircle' in its own defaultOption and so never
  reaches it, which is why an ECharts line legend shows a RING and not a dot
  (LineSeries.ts:201, Series.ts:218). }
function TyLegendDefaultIcon(const ASeriesType, ASymbolWord: string): string;

{ Whether a series of this type draws its own legend icon -- a rule with a
  marker sitting on it -- rather than taking the shared one. Only a line does,
  upstream and here; `map` is the other one upstream and this port has no map. }
function TyLegendDrawsOwnIcon(const ASeriesType: string): Boolean;

{ Lay one out against AContainer. AFont is the words' font, resolved from the
  theme; APPI scales the LOGICAL gaps and the item box.

  Answers Valid = False when there is nothing to draw. }
function TyLayoutLegend(const ASpec: TTyLegendSpec;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const ASources: TTyLegendSourceArray; const AContainer: TTyRectF;
  const AMeasurer: ITyTextMeasurer; const AFont: TTyLegendFont;
  APPI: Integer): TTyLegendLayout; overload;
{ [Batch 98] The same with the selector buttons and the pager, which need
  the control's resolved ADeco. A legend with neither is laid out exactly as
  above. }
function TyLayoutLegend(const ASpec: TTyLegendSpec;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const ASources: TTyLegendSourceArray; const AContainer: TTyRectF;
  const AMeasurer: ITyTextMeasurer; const AFont: TTyLegendFont;
  APPI: Integer; const ADeco: TTyLegendDeco): TTyLegendLayout; overload;

{ [Batch 98] the page text: pageFormatter's `(current)` and `(total)` tokens in braces, each
  replaced ONCE (String.replace with a string), or the named handler given
  (current, total) -- current is pageIndex + 1 }
function TyLegendPageText(const AFormatter: string; ACurrent, ATotal: Integer): string;

{ [Batch 98] the legend's scrollDataIndex written into its option node --
  ScrollableLegendModel.setScrollDataIndex }
procedure TyLegendSetScrollDataIndex(AOption: TTyChartOption; AIndex: Integer;
  AValue: TJSONData);

{ The elements, appended to AList. Answers how many were added.

  SILENT, every one of them: the legend is not a datum and a legend icon
  swallowing the hover meant for the bar underneath it would be a bug. The
  click, when it comes, will walk the LAYOUT -- which knows which item is
  which -- rather than this list, which does not. }
function TyBuildLegendMarks(const ASpec: TTyLegendSpec;
  const ALayout: TTyLegendLayout; const AInk: TTyLegendInk;
  const AFont: TTyLegendFont; APPI: Integer; AList: TTyPaintList;
  ALegendIndex: Integer = -1; const AMeasurer: ITyTextMeasurer = nil;
  ASelHover: Integer = -1): Integer;

implementation

uses tyControls.AdvChart.Handlers, tyControls.AdvChart.RichStyle,
  tyControls.AdvChart.States, tyControls.AdvChart.MarkerView,
  tyControls.StrConsts;

const
  { LegendModel.defaultOption, LegendModel.ts:450-539. `bottom` is
    tokens.size.m. `itemGap` is 8 and the JSDoc two lines above it says 10 --
    upstream disagrees with itself and the source wins. }
  cDefaultBottom = 15.0;
  cDefaultPadding = 5.0;
  cDefaultItemGap = 8.0;
  cDefaultItemWidth = 25.0;
  cDefaultItemHeight = 14.0;
  cDefaultZ = 4;
  { [Batch 98] LegendModel.defaultOption's selector gaps and
    ScrollableLegendModel.defaultOption's pager }
  cSelectorItemGap = 7.0;
  cSelectorButtonGap = 10.0;
  cPageButtonItemGap = 5.0;
  cPageIconSize = 15.0;
  cPageFormatter = '{current}/{total}';
  { the placeholder the page text is laid out with, whatever it then says
    (ScrollableLegendView.renderInner: 'xx/xx', with a FIXME about it) }
  cPagePlaceholder = 'xx/xx';
  cPageIconsH: array[0..1] of string = ('M0,0L12,-10L12,10z', 'M0,0L-12,-10L-12,10z');
  cPageIconsV: array[0..1] of string = ('M0,0L20,0L10,-20z', 'M0,0L20,0L10,20z');
  { The gap between an icon and its words. A HARD 5 in LegendView.ts:455, and
    not itemGap -- itemGap separates whole entries. }
  cTextGap = 5.0;
  { A line series' marker is four fifths of the box's HEIGHT, LineSeries.ts:256.
    Named because the measurer and the drawer both need it and a number written
    twice is a number that drifts. }
  cOwnIconMarker = 0.8;
  { zrender grows a stroked path's bounding rect by half the pen -- and by
    half of strokeContainThreshold (5) INSTEAD, when the path has no fill at
    all, so that a hairline still has something to hit. Path.ts:373-383,
    :676.

    THAT SECOND RULE NEVER FIRES ON A LEGEND ICON, which is why there is no
    constant for it here: zrender's default path style carries fill '#000'
    and setStyle only ever writes over it, so every legend icon has a fill
    whether or not anyone chose one -- including the bare `line` icon, whose
    fill paints nothing because the path is degenerate. Half the pen, always. }

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function StrIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  if d.JSONType = jtString then Exit(d.AsString);
  if d.JSONType = jtNumber then Exit(d.AsString);
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  Result := d.AsFloat;
end;

function RectUnion(const A, B: TTyRectF): TTyRectF;
begin
  if not TyRectFIsValid(A) then Exit(B);
  if not TyRectFIsValid(B) then Exit(A);
  Result := TyRectF(Min(A.Left, B.Left), Min(A.Top, B.Top),
                    Max(A.Right, B.Right), Max(A.Bottom, B.Bottom));
end;

{ ==================== the spec ==================== }

function TyLegendCount(AOption: TTyChartOption): Integer;
begin
  Result := 0;
  if AOption = nil then Exit;
  Result := AOption.ComponentCount('legend');
end;

{ legend's defaultOption's box: `left: 'center'`, `bottom: 15`. }
function DefaultBox: TTyRawBox;
begin
  Result := Default(TTyRawBox);
  Result.Left := TyBoxRawStr('center');
  Result.Bottom := TyBoxRawNum(cDefaultBottom);
end;

function TyLegendSpecDefault: TTyLegendSpec;
var i: Integer;
begin
  Result.Show := True;
  Result.Box := DefaultBox;
  for i := 0 to 3 do Result.Padding[i] := cDefaultPadding;
  Result.Orient := tloHorizontal;
  Result.Align := tlaAuto;
  Result.ItemGap := cDefaultItemGap;
  Result.ItemWidth := cDefaultItemWidth;
  Result.ItemHeight := cDefaultItemHeight;
  Result.Icon := '';
  Result.Formatter := '';
  Result.SelectedMode := tlsMultiple;
  Result.HasBackground := False;
  Result.BorderWidth := 0;
  Result.BorderRadii := TyCornerRadii([]);
  Result.Z := cDefaultZ;
  Result.InactiveBorderAuto := True;
  { [Batch 98] }
  Result.IsScroll := False;
  Result.HasSelector := False;
  Result.Selector := nil;
  Result.SelectorAtEnd := True;
  Result.SelectorItemGap := cSelectorItemGap;
  Result.SelectorButtonGap := cSelectorButtonGap;
  Result.ScrollIsNum := True;
  Result.ScrollNum := 0;
  Result.PageButtonItemGap := cPageButtonItemGap;
  Result.PageButtonGap := NaN;
  Result.PageButtonAtEnd := True;
  Result.HasPageFormatter := True;
  Result.PageFormatter := cPageFormatter;
  for i := 0 to 1 do
  begin
    Result.PageIcons[tloHorizontal, i] := cPageIconsH[i];
    Result.PageIcons[tloVertical, i] := cPageIconsV[i];
  end;
  Result.PageIconW := cPageIconSize;
  Result.PageIconH := cPageIconSize;
end;

{ `legend.selector` as _updateSelector leaves it [Batch 98] }
procedure ReadSelector(ANode: TJSONObject; var ASpec: TTyLegendSpec);
var
  d, it, t: TJSONData;
  arr: TJSONArray;
  i: Integer;
  b: TTyLegendSelectorBtn;

  function Btn(const AKind: string): TTyLegendSelectorBtn;
  begin
    Result.Kind := AKind;
    Result.IsAll := AKind = 'all';
    if AKind = 'all' then Result.Title := rsTyChartLegendSelectAll
    else if AKind = 'inverse' then Result.Title := rsTyChartLegendSelectInverse
    else Result.Title := '';
  end;

begin
  ASpec.HasSelector := False;
  ASpec.Selector := nil;
  if ANode = nil then Exit;
  d := ANode.Find('selector');
  if d = nil then Exit;
  if d.JSONType = jtBoolean then
  begin
    if not d.AsBoolean then Exit;
    ASpec.HasSelector := True;
    SetLength(ASpec.Selector, 2);
    ASpec.Selector[0] := Btn('all');
    ASpec.Selector[1] := Btn('inverse');
    Exit;
  end;
  if not (d is TJSONArray) then Exit;
  arr := TJSONArray(d);
  ASpec.HasSelector := True;
  SetLength(ASpec.Selector, arr.Count);
  for i := 0 to arr.Count - 1 do
  begin
    it := arr.Items[i];
    if it.JSONType = jtString then b := Btn(it.AsString)
    else if it is TJSONObject then
    begin
      t := TJSONObject(it).Find('type');
      if (t <> nil) and (t.JSONType = jtString) then b := Btn(t.AsString)
      else b := Btn('');
      { merge never overwrites: a title written -- any value -- stays }
      t := TJSONObject(it).Find('title');
      if t <> nil then
      begin
        if t.JSONType in [jtString, jtNumber] then b.Title := t.AsString
        else b.Title := '';
      end;
    end
    else
      b := Btn('');
    ASpec.Selector[i] := b;
  end;
end;

{ the scrolling legend's own keys [Batch 98] }
procedure ReadScroll(ANode: TJSONObject; var ASpec: TTyLegendSpec);
var
  d, e: TJSONData;
  o: TTyLegendOrient;
  k: Integer;
  w: string;
begin
  if ANode = nil then Exit;
  d := ANode.Find('scrollDataIndex');
  if d <> nil then
  begin
    ASpec.ScrollIsNum := d.JSONType = jtNumber;
    if ASpec.ScrollIsNum then ASpec.ScrollNum := d.AsFloat;
  end;
  ASpec.PageButtonItemGap := NumIn(ANode, 'pageButtonItemGap', ASpec.PageButtonItemGap);
  ASpec.PageButtonGap := NumIn(ANode, 'pageButtonGap', NaN);
  d := ANode.Find('pageButtonPosition');
  if d <> nil then
    ASpec.PageButtonAtEnd := (d.JSONType = jtString) and (d.AsString = 'end');
  d := ANode.Find('pageFormatter');
  if d <> nil then
  begin
    ASpec.HasPageFormatter := (d.JSONType = jtString) and (d.AsString <> '');
    if ASpec.HasPageFormatter then ASpec.PageFormatter := d.AsString
    else ASpec.PageFormatter := '';
  end;
  d := ANode.Find('pageIcons');
  if d is TJSONObject then
    for o := Low(TTyLegendOrient) to High(TTyLegendOrient) do
    begin
      if o = tloHorizontal then w := 'horizontal' else w := 'vertical';
      e := TJSONObject(d).Find(w);
      if not (e is TJSONArray) then Continue;
      for k := 0 to 1 do
        if (k < TJSONArray(e).Count) and (TJSONArray(e).Items[k].JSONType = jtString) then
          ASpec.PageIcons[o, k] := TJSONArray(e).Items[k].AsString
        else
          ASpec.PageIcons[o, k] := '';
    end;
  d := ANode.Find('pageIconSize');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    ASpec.PageIconW := d.AsFloat;
    ASpec.PageIconH := d.AsFloat;
  end
  else if d is TJSONArray then
  begin
    ASpec.PageIconW := NaN;
    ASpec.PageIconH := NaN;
    if (TJSONArray(d).Count > 0) and (TJSONArray(d).Items[0].JSONType = jtNumber) then
      ASpec.PageIconW := TJSONArray(d).Items[0].AsFloat;
    if (TJSONArray(d).Count > 1) and (TJSONArray(d).Items[1].JSONType = jtNumber) then
      ASpec.PageIconH := TJSONArray(d).Items[1].AsFloat;
  end;
end;

procedure ReadPadding(ANode: TJSONObject; var APadding: array of Double);
var
  d: TJSONData;
  arr: TJSONArray;
  i, n: Integer;
  v: array[0..3] of Double;
begin
  if ANode = nil then Exit;
  d := ANode.Find('padding');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d.JSONType = jtNumber then
  begin
    for i := 0 to 3 do APadding[i] := d.AsFloat;
    Exit;
  end;
  if not (d is TJSONArray) then Exit;
  arr := TJSONArray(d);
  n := arr.Count;
  if n = 0 then Exit;
  for i := 0 to 3 do v[i] := 0;
  for i := 0 to Min(3, n - 1) do
    if arr.Items[i].JSONType = jtNumber then v[i] := arr.Items[i].AsFloat;
  case n of
    1: for i := 0 to 3 do APadding[i] := v[0];
    2: begin
         APadding[0] := v[0]; APadding[2] := v[0];
         APadding[1] := v[1]; APadding[3] := v[1];
       end;
    3: begin
         APadding[0] := v[0];
         APadding[1] := v[1]; APadding[3] := v[1];
         APadding[2] := v[2];
       end;
  else
    for i := 0 to 3 do APadding[i] := v[i];
  end;
end;

function SelectedModeOf(ANode: TJSONObject): TTyLegendSelectedMode;
var d: TJSONData;
begin
  Result := tlsMultiple;
  if ANode = nil then Exit;
  d := ANode.Find('selectedMode');
  if d = nil then Exit;
  if d.JSONType = jtBoolean then
  begin
    if d.AsBoolean then Exit(tlsMultiple) else Exit(tlsOff);
  end;
  if (d.JSONType = jtString) and (d.AsString = 'single') then Exit(tlsSingle);
end;

function TyLegendSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyLegendSpec;
var
  node: TJSONObject;
  d: TJSONData;
  w: string;
  given: Boolean;
begin
  Result := TyLegendSpecDefault;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('legend', AIndex));
  if node = nil then Exit;

  d := node.Find('show');
  if (d <> nil) and (d.JSONType = jtBoolean) then Result.Show := d.AsBoolean;

  { `legend.width` and `legend.height` are the WRAP LIMITS, not the drawn size:
    the second layout pass overwrites both with what the items measured. The
    comment saying so is at LegendModel.ts:251-254. }
  Result.Box := TyMergeBoxIgnoreSize(node, DefaultBox);

  ReadPadding(node, Result.Padding);
  if StrIn(node, 'orient') = 'vertical' then
    Result.Orient := tloVertical
  else
    Result.Orient := tloHorizontal;
  w := StrIn(node, 'align');
  if w = 'left' then Result.Align := tlaLeft
  else if w = 'right' then Result.Align := tlaRight
  else Result.Align := tlaAuto;
  Result.ItemGap := NumIn(node, 'itemGap', Result.ItemGap);
  Result.ItemWidth := NumIn(node, 'itemWidth', Result.ItemWidth);
  Result.ItemHeight := NumIn(node, 'itemHeight', Result.ItemHeight);
  Result.Icon := StrIn(node, 'icon');
  { A FUNCTION FORMATTER CANNOT SURVIVE JSON, so only the string form exists
    here and a non-string leaves the name alone. }
  d := node.Find('formatter');
  if (d <> nil) and (d.JSONType = jtString) then Result.Formatter := d.AsString;
  Result.SelectedMode := SelectedModeOf(node);

  d := node.Find('backgroundColor');
  Result.HasBackground := (d <> nil) and (d.JSONType = jtString)
    and (d.AsString <> '') and (d.AsString <> 'transparent');
  Result.BorderWidth := NumIn(node, 'borderWidth', 0);
  d := node.Find('borderRadius');
  if (d <> nil) and (d.JSONType = jtNumber) then
    Result.BorderRadii := TyCornerRadii([d.AsFloat]);
  Result.Z := TyRoundOpt(NumIn(node, 'z', cDefaultZ), cDefaultZ);
  { anything written but 'auto' (null falls back to the default) }
  d := node.Find('inactiveBorderWidth');
  Result.InactiveBorderAuto := (d = nil) or (d.JSONType = jtNull)
    or ((d.JSONType = jtString) and (d.AsString = 'auto'));

  { [Batch 98] the selector and the pager }
  Result.IsScroll := StrIn(node, 'type') = 'scroll';
  ReadSelector(node, Result);
  { `!selectorPosition || === 'auto'`: orient === 'horizontal' ? 'end' :
    'start' -- the orient WORD, so only an absent or 'horizontal' one ends }
  d := node.Find('selectorPosition');
  if (d = nil) or (d.JSONType = jtNull)
    or ((d.JSONType = jtBoolean) and not d.AsBoolean)
    or ((d.JSONType = jtNumber) and (d.AsFloat = 0))
    or ((d.JSONType = jtString) and ((d.AsString = '') or (d.AsString = 'auto'))) then
  begin
    d := node.Find('orient');
    Result.SelectorAtEnd := (d = nil)
      or ((d.JSONType = jtString) and (d.AsString = 'horizontal'));
  end
  else
    Result.SelectorAtEnd := (d.JSONType = jtString) and (d.AsString = 'end');
  Result.SelectorItemGap := NumIn(node, 'selectorItemGap', Result.SelectorItemGap);
  Result.SelectorButtonGap := NumIn(node, 'selectorButtonGap', Result.SelectorButtonGap);
  if Result.IsScroll then ReadScroll(node, Result);
end;

procedure TyLegendSetScrollDataIndex(AOption: TTyChartOption; AIndex: Integer;
  AValue: TJSONData);
var node: TJSONObject;
begin
  if (AOption = nil) or (AValue = nil) then Exit;
  node := ObjOf(AOption.ComponentAt('legend', AIndex));
  if node = nil then Exit;
  node.Elements['scrollDataIndex'] := AValue.Clone;
end;

function TyLegendPageText(const AFormatter: string; ACurrent, ATotal: Integer): string;
var prm: TTyChartCallbackParams;
begin
  if TyChartIsHandlerRef(AFormatter) then
  begin
    { upstream's pageFormatter with an object of current and total }
    prm := TyChartBlankParams;
    prm.ComponentType := 'legend';
    prm.Extra := 'page';
    SetLength(prm.Values, 2);
    prm.Values[0] := ACurrent;
    prm.Values[1] := ATotal;
    prm.DefaultText := TyLegendPageText(cPageFormatter, ACurrent, ATotal);
    Exit(TyChartRunHandler(AFormatter, TyChartOneParams(prm)));
  end;
  Result := TyJsReplaceFirst(AFormatter, '{current}', IntToStr(ACurrent));
  Result := TyJsReplaceFirst(Result, '{total}', IntToStr(ATotal));
end;

{ ==================== entries ==================== }

function TyLegendEntries(AOption: TTyChartOption; AIndex: Integer;
  const APotential: array of string): TTyLegendEntryArray;
var
  node: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  item: TJSONObject;
  raw: TTyLegendEntryArray;
  i, j, n: Integer;
  dup: Boolean;

  procedure PushRaw(const AName, AIcon: string);
  begin
    SetLength(raw, Length(raw) + 1);
    raw[High(raw)].Name := AName;
    raw[High(raw)].Icon := AIcon;
    raw[High(raw)].Newline := (AName = '') or (AName = #10);
  end;

begin
  Result := nil;
  raw := nil;
  node := nil;
  if AOption <> nil then node := ObjOf(AOption.ComponentAt('legend', AIndex));
  d := nil;
  if node <> nil then d := node.Find('data');

  if (d <> nil) and (d is TJSONArray) then
  begin
    { AN EMPTY ARRAY IS AN ANSWER. `this.get('data') || potentialData` falls
      back only on a MISSING data, and [] is truthy in JavaScript -- so
      `legend: {data: []}` asks for a legend with no items in it. }
    arr := TJSONArray(d);
    for i := 0 to arr.Count - 1 do
    begin
      case arr.Items[i].JSONType of
        jtString, jtNumber: PushRaw(arr.Items[i].AsString, '');
        jtObject:
          begin
            item := TJSONObject(arr.Items[i]);
            PushRaw(StrIn(item, 'name'), StrIn(item, 'icon'));
          end;
      end;
    end;
  end
  else
    for i := 0 to High(APotential) do PushRaw(APotential[i], '');

  { DEDUPLICATED BY NAME, first one wins -- and the line-break markers go
    through the same sieve, so a legend can hold one '' and one newline and no
    more however many the option lists. }
  n := 0;
  SetLength(Result, Length(raw));
  for i := 0 to High(raw) do
  begin
    dup := False;
    for j := 0 to n - 1 do
      if Result[j].Name = raw[i].Name then
      begin
        dup := True;
        Break;
      end;
    if dup then Continue;
    Result[n] := raw[i];
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ ==================== selection ==================== }

type
  TSelMap = record
    Names: array of string;
    On_: array of Boolean;
  end;

function MapFind(const AMap: TSelMap; const AName: string): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to High(AMap.Names) do
    if AMap.Names[i] = AName then Exit(i);
end;

procedure MapSet(var AMap: TSelMap; const AName: string; AOn: Boolean);
var i: Integer;
begin
  i := MapFind(AMap, AName);
  if i < 0 then
  begin
    i := Length(AMap.Names);
    SetLength(AMap.Names, i + 1);
    SetLength(AMap.On_, i + 1);
    AMap.Names[i] := AName;
  end;
  AMap.On_[i] := AOn;
end;

{ `legend.selected`. ANY FALSY VALUE IS OFF, not just `false`:
  `!(has(name) && !selected[name])` is JavaScript, so null, 0 and '' switch an
  item off exactly as `false` does. }
function ReadSelectedMap(ANode: TJSONObject): TSelMap;
var
  d: TJSONData;
  obj: TJSONObject;
  i: Integer;
  v: TJSONData;
  on_: Boolean;
begin
  Result.Names := nil;
  Result.On_ := nil;
  if ANode = nil then Exit;
  d := ANode.Find('selected');
  if (d = nil) or not (d is TJSONObject) then Exit;
  obj := TJSONObject(d);
  for i := 0 to obj.Count - 1 do
  begin
    v := obj.Items[i];
    case v.JSONType of
      jtBoolean: on_ := v.AsBoolean;
      jtNumber: on_ := v.AsFloat <> 0;
      jtString: on_ := v.AsString <> '';
      jtNull: on_ := False;
    else
      on_ := True;
    end;
    MapSet(Result, obj.Names[i], on_);
  end;
end;

function TyLegendSelected(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AAvailable: array of string;
  AMode: TTyLegendSelectedMode): TTyLegendFlags;
var
  node: TJSONObject;
  map: TSelMap;
  i, k: Integer;
  hasOne: Boolean;

  function Available(const AName: string): Boolean;
  var j: Integer;
  begin
    Result := False;
    for j := 0 to High(AAvailable) do
      if AAvailable[j] = AName then Exit(True);
  end;

  function IsSel(const AName: string): Boolean;
  var j: Integer;
  begin
    j := MapFind(map, AName);
    Result := ((j < 0) or map.On_[j]) and Available(AName);
  end;

  { Single mode's `select`: every other item is switched off FIRST, and the
    loop is over the entries rather than over the map, so a name the map
    carries but the legend does not list is left alone. }
  procedure SelectOnly(const AName: string);
  var j: Integer;
  begin
    for j := 0 to High(AEntries) do MapSet(map, AEntries[j].Name, False);
    MapSet(map, AName, True);
  end;

begin
  node := nil;
  if AOption <> nil then node := ObjOf(AOption.ComponentAt('legend', AIndex));
  map := ReadSelectedMap(node);

  { SINGLE MODE IS RESOLVED AT LOAD, not on the first click -- optionUpdated
    forces exactly one item on. It takes the first item that is already
    selected, and the first item of all when none is. This is why a
    `selectedMode: 'single'` chart shows ONE series before anyone touches it,
    and why a legend that only drew would be wrong on the first frame. }
  if (AMode = tlsSingle) and (Length(AEntries) > 0) then
  begin
    hasOne := False;
    { AN EQUIVALENT MUTANT LIVES ON THE `Break` and is recorded rather than
      chased: SelectOnly has just switched every entry OFF, so every later
      IsSel answers False and the loop would finish without doing anything
      more. The Break is upstream's and it is kept for that reason -- it says
      `the FIRST selected item wins` out loud, which is the rule, rather than
      leaving it to be inferred from a side effect two lines up. }
    for i := 0 to High(AEntries) do
      if IsSel(AEntries[i].Name) then
      begin
        SelectOnly(AEntries[i].Name);
        hasOne := True;
        Break;
      end;
    if not hasOne then SelectOnly(AEntries[0].Name);
  end;

  SetLength(Result, Length(AEntries));
  for k := 0 to High(AEntries) do Result[k] := IsSel(AEntries[k].Name);
end;

function TyLegendDefaultIcon(const ASeriesType, ASymbolWord: string): string;
begin
  { A GRAPH HAS A SYMBOL VISUAL -- `hasSymbolVisual = true` -- so a graph the
    legend names by its SERIES name is drawn as its node symbol, a circle by
    default. (Its CATEGORIES are drawn as rounded rectangles: the category
    provider publishes no icon.) }
  if ASeriesType = 'graph' then
  begin
    if ASymbolWord <> '' then Exit(ASymbolWord);
    Exit('circle');
  end;
  { A bar, a pie, a funnel: no symbol visual, so nothing is published and the
    chain falls through to roundRect. }
  if (ASeriesType <> 'line') and (ASeriesType <> 'scatter') then Exit('');
  if ASymbolWord <> '' then Exit(ASymbolWord);
  if ASeriesType = 'scatter' then Result := 'circle'
  else Result := 'emptyCircle';
end;

function TyLegendDrawsOwnIcon(const ASeriesType: string): Boolean;
begin
  Result := ASeriesType = 'line';
end;

function TyLegendHides(const AEntries: TTyLegendEntryArray;
  const AFlags: TTyLegendFlags; const AName: string): Boolean;
var i: Integer;
begin
  Result := False;
  if AName = '' then Exit;
  for i := 0 to High(AEntries) do
  begin
    if AEntries[i].Newline then Continue;
    if AEntries[i].Name <> AName then Continue;
    { The entry exists, so the legend does have an opinion. }
    Exit((i > High(AFlags)) or (not AFlags[i]));
  end;
end;

function TyLegendHides(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const AName: string): Boolean;
var
  node: TJSONObject;
  map: TSelMap;
  i, j: Integer;
begin
  Result := False;
  if AName = '' then Exit;
  for i := 0 to High(AEntries) do
    if (not AEntries[i].Newline) and (AEntries[i].Name = AName) then
      Exit(TyLegendHides(AEntries, AFlags, AName));
  node := nil;
  if AOption <> nil then node := ObjOf(AOption.ComponentAt('legend', AIndex));
  map := ReadSelectedMap(node);
  j := MapFind(map, AName);
  Result := (j >= 0) and not map.On_[j];
end;

function TyLegendNameSelected(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const AAvailable: array of string; const AName: string): Boolean;
var
  node: TJSONObject;
  map: TSelMap;
  i, j: Integer;
begin
  { A LINE BREAK IS LISTED TOO: `''` is an item upstream, and single mode can
    even pick it. }
  for i := 0 to High(AEntries) do
    if AEntries[i].Name = AName then
      Exit((i <= High(AFlags)) and AFlags[i]);
  node := nil;
  if AOption <> nil then node := ObjOf(AOption.ComponentAt('legend', AIndex));
  map := ReadSelectedMap(node);
  j := MapFind(map, AName);
  if (j >= 0) and not map.On_[j] then Exit(False);
  Result := False;
  for i := 0 to High(AAvailable) do
    if AAvailable[i] = AName then Exit(True);
end;

{ ==================== the selection after load [Batch 93] ==================== }

{ JavaScript's falsy, for a value in the map }
function JsFalsy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(True);
  case AData.JSONType of
    jtBoolean: Result := not AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat = 0) or IsNan(AData.AsFloat);
    jtString: Result := AData.AsString = '';
    jtNull: Result := True;
  else
    Result := False;
  end;
end;

function TyLegendSelectedNode(AOption: TTyChartOption; AIndex: Integer): TJSONObject;
var
  node: TJSONObject;
  d: TJSONData;
  k: Integer;
begin
  Result := nil;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('legend', AIndex));
  if node = nil then Exit;
  d := node.Find('selected');
  if d is TJSONObject then Exit(TJSONObject(d));
  k := node.IndexOfName('selected');
  if k >= 0 then node.Delete(k);
  Result := TJSONObject.Create;
  node.Add('selected', Result);
end;

function TyLegendIsSelected(AOption: TTyChartOption; AIndex: Integer;
  const AAvailable: array of string; const AName: string): Boolean;
var
  sel: TJSONObject;
  d: TJSONData;
  i: Integer;
begin
  sel := TyLegendSelectedNode(AOption, AIndex);
  if sel <> nil then
  begin
    d := sel.Find(AName);
    if (d <> nil) and JsFalsy(d) then Exit(False);
  end;
  Result := False;
  for i := 0 to High(AAvailable) do
    if AAvailable[i] = AName then Exit(True);
end;

procedure TyLegendSelectName(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; AMode: TTyLegendSelectedMode;
  const AName: string);
var
  sel: TJSONObject;
  i: Integer;
begin
  sel := TyLegendSelectedNode(AOption, AIndex);
  if sel = nil then Exit;
  if AMode = tlsSingle then
    for i := 0 to High(AEntries) do sel.Booleans[AEntries[i].Name] := False;
  sel.Booleans[AName] := True;
end;

procedure TyLegendUnSelectName(AOption: TTyChartOption; AIndex: Integer;
  AMode: TTyLegendSelectedMode; const AName: string);
var sel: TJSONObject;
begin
  if AMode = tlsSingle then Exit;
  sel := TyLegendSelectedNode(AOption, AIndex);
  if sel = nil then Exit;
  sel.Booleans[AName] := False;
end;

procedure TyLegendToggleName(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; AMode: TTyLegendSelectedMode;
  const AName: string);
var sel: TJSONObject;
begin
  sel := TyLegendSelectedNode(AOption, AIndex);
  if sel = nil then Exit;
  if sel.IndexOfName(AName) < 0 then sel.Booleans[AName] := True;
  if JsFalsy(sel.Find(AName)) then
    TyLegendSelectName(AOption, AIndex, AEntries, AMode, AName)
  else
    TyLegendUnSelectName(AOption, AIndex, AMode, AName);
end;

procedure TyLegendAllSelect(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray);
var
  sel: TJSONObject;
  i: Integer;
begin
  sel := TyLegendSelectedNode(AOption, AIndex);
  if sel = nil then Exit;
  for i := 0 to High(AEntries) do sel.Booleans[AEntries[i].Name] := True;
end;

procedure TyLegendInverseSelect(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray);
var
  sel: TJSONObject;
  i: Integer;
  on_: Boolean;
begin
  sel := TyLegendSelectedNode(AOption, AIndex);
  if sel = nil then Exit;
  for i := 0 to High(AEntries) do
  begin
    { initially the default is true }
    if sel.IndexOfName(AEntries[i].Name) < 0 then on_ := True
    else on_ := not JsFalsy(sel.Find(AEntries[i].Name));
    sel.Booleans[AEntries[i].Name] := not on_;
  end;
end;

procedure TyLegendResolveSingle(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AAvailable: array of string);
var i: Integer;
begin
  if Length(AEntries) = 0 then Exit;
  for i := 0 to High(AEntries) do
    if TyLegendIsSelected(AOption, AIndex, AAvailable, AEntries[i].Name) then
    begin
      TyLegendSelectName(AOption, AIndex, AEntries, tlsSingle, AEntries[i].Name);
      Exit;
    end;
  TyLegendSelectName(AOption, AIndex, AEntries, tlsSingle, AEntries[0].Name);
end;

function TyJsKeyOrder(AObj: TJSONObject): TTyLegendNames;
var
  i, j, n: Integer;
  idx: array of QWord;
  t: string;
  v: QWord;
begin
  Result := nil;
  if AObj = nil then Exit;
  SetLength(Result, AObj.Count);
  n := 0;
  idx := nil;
  { the index keys first, ascending by value (an insertion sort) }
  for i := 0 to AObj.Count - 1 do
  begin
    t := AObj.Names[i];
    if not TyJsIsIndexKey(t) then Continue;
    v := StrToQWord(t);
    SetLength(idx, n + 1);
    j := n;
    while (j > 0) and (idx[j - 1] > v) do
    begin
      idx[j] := idx[j - 1];
      Result[j] := Result[j - 1];
      Dec(j);
    end;
    idx[j] := v;
    Result[j] := t;
    Inc(n);
  end;
  for i := 0 to AObj.Count - 1 do
  begin
    t := AObj.Names[i];
    if TyJsIsIndexKey(t) then Continue;
    Result[n] := t;
    Inc(n);
  end;
end;

function TyLegendSelectedJson(AOption: TTyChartOption; AIndex: Integer): string;
var
  node, sel: TJSONObject;
  d: TJSONData;
  keys: TTyLegendNames;
  i: Integer;
begin
  Result := '{}';
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('legend', AIndex));
  if node = nil then Exit;
  d := node.Find('selected');
  if not (d is TJSONObject) then Exit;
  sel := TJSONObject(d);
  keys := TyJsKeyOrder(sel);
  Result := '{';
  for i := 0 to High(keys) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '"' + StringToJSONString(keys[i]) + '":'
      + sel.Find(keys[i]).AsJSON;
  end;
  Result := Result + '}';
end;

function TyLegendText(const AFormatter, AName: string): string;
var
  p: Integer;
  prm: TTyChartCallbackParams;
begin
  Result := AName;
  if AFormatter = '' then Exit;
  { a named handler is given the name, upstream's formatter(name) }
  if TyChartIsHandlerRef(AFormatter) then
  begin
    prm := TyChartBlankParams;
    prm.ComponentType := 'legend';
    prm.Name := AName;
    prm.DefaultText := AName;
    Exit(TyChartRunHandler(AFormatter, TyChartOneParams(prm)));
  end;
  Result := AFormatter;
  p := Pos('{name}', Result);
  if p <= 0 then Exit;
  Result := Copy(Result, 1, p - 1) + AName +
            Copy(Result, p + Length('{name}'), MaxInt);
end;

{ ==================== the layout ==================== }

{ How far a stroked shape's ink reaches past its own geometry. }
function StrokeGrow(AWidth: Double): Double;
begin
  if AWidth <= 0 then Exit(0);
  Result := AWidth / 2;
end;

{ The resolved icon word, and whether the series gets to draw its own.

  THREE TERMS, in this order: the row's own icon, then `legend.icon`, then the
  series' symbol, then 'roundRect'. The series only draws its OWN icon when the
  first two are silent or say 'inherit' -- which is why `icon: 'inherit'` on a
  bar is not a no-op but a SHARP rect: 'inherit' survives as a literal, matches
  no symbol name, and an unrecognised name is a rect. }
procedure ResolveIcon(const ASpec: TTyLegendSpec; const AEntry: TTyLegendEntry;
  const ASource: TTyLegendSource; out AIcon: string; out AOwn: Boolean);
var word_: string;
begin
  word_ := AEntry.Icon;
  if word_ = '' then word_ := ASpec.Icon;
  AOwn := ASource.OwnIcon and ((word_ = '') or (word_ = 'inherit'));
  if AOwn then
  begin
    { THE SERIES' OWN ICON IGNORES THE WORD. It does not read `legend.icon`
      at all -- it reads the series' symbol straight off the data, and maps
      `symbol: 'none'` to a circle so that a line with no markers still gets
      one in its legend. LineSeries.ts:251-253. }
    AIcon := ASource.DefaultIcon;
    if (AIcon = '') or (AIcon = 'none') then AIcon := 'circle';
    Exit;
  end;
  AIcon := word_;
  if AIcon = '' then AIcon := ASource.DefaultIcon;
  if AIcon = '' then AIcon := 'roundRect';
end;

{ The pen an `empty` icon is ringed with: the line's own width where it has
  one, and 2 where it has not. The same fallback the datum mark builders
  make, so a legend's marker and the markers on the line it stands for are
  drawn with the same pen. }
function RingPen(ALineWidthLogical: Double): Double;
begin
  Result := ALineWidthLogical;
  if Result <= 0 then Result := 2;
end;

{ The icon's ink extent in a box at the origin, which is what the wrap
  measures. It builds the same shapes TyBuildLegendMarks draws and grows them
  by the same pens, so the box measured here and the ink drawn there cannot
  disagree.

  ARulePx is the line series' rule, 0 when there is none; APenPx is the pen a
  ring or a bare stroke is drawn with, which is never 0. Both DEVICE px. }
function IconExtent(const AIcon: string; AOwn: Boolean;
  AIconW, AIconH, ARulePx, APenPx: Double; AStrokePx: Double = 0): TTyRectF;
var
  spec: TTySymbolSpec;
  empty: Boolean;
  path: string;
  kind: TTySymbolKind;
  sh: TTyChartShape;
  box, r: TTyRectF;
  size, grow: Double;
begin
  box := TyRectF(0, 0, AIconW, AIconH);
  kind := TySymbolKindOf(AIcon, empty, path);

  if AOwn then
  begin
    { A LINE SERIES DRAWS A RULE WITH A MARKER ON IT, LineSeries.ts:236-282.
      The rule spans the whole box at its middle; the marker is 80% of the
      box's HEIGHT and centred, so the 25 x 14 really is a padded slot here
      and not the edge-to-edge fill every other icon makes of it. }
    Result := TyInvalidRectF;
    if ARulePx > 0 then
    begin
      grow := StrokeGrow(ARulePx);
      Result := TyRectF(-grow, AIconH / 2 - grow, AIconW + grow,
                        AIconH / 2 + grow);
    end;
    size := AIconH * cOwnIconMarker;
    if kind <> tsyNone then
    begin
      grow := 0;
      if empty or (kind = tsyLine) then
        grow := StrokeGrow(APenPx);
      r := TyRectF((AIconW - size) / 2 - grow, (AIconH - size) / 2 - grow,
                   (AIconW + size) / 2 + grow, (AIconH + size) / 2 + grow);
      Result := RectUnion(Result, r);
    end;
    Exit;
  end;

  if kind = tsyNone then Exit(TyInvalidRectF);
  spec := Default(TTySymbolSpec);
  spec.Kind := kind;
  spec.Empty := empty;
  spec.PathData := path;
  sh := TyBuildSymbolInBox(spec, box);
  Result := TyShapeBounds(sh);
  if not TyRectFIsValid(Result) then Exit;
  { A filled icon carries no pen at all -- `itemStyle.borderWidth: 'auto'`
    resolves to 0 unless the series itself has a border -- so only the ring and
    the bare rule reach past their geometry. }
  if empty or (kind = tsyLine) then
  begin
    grow := StrokeGrow(APenPx);
    Result := TyRectF(Result.Left - grow, Result.Top - grow,
                      Result.Right + grow, Result.Bottom + grow);
  end
  else if AStrokePx > 0 then
  begin
    { [Batch 93] A SERIES WITH A BORDER gives its icon a pen, and the icon
      has a fill: half the pen, Path.ts:360-384 }
    grow := StrokeGrow(AStrokePx);
    Result := TyRectF(Result.Left - grow, Result.Top - grow,
                      Result.Right + grow, Result.Bottom + grow);
  end;
end;

{ boxLayout, layout.ts:74-142 -- the wrap, transcribed including the parts that
  read oddly.

  THE COMPARISON EXCLUDES THE GAP, and upstream's own FIXME beside it says so:
  an item that lands exactly on the limit does not wrap, and the gap that
  follows it pushes the NEXT one over instead.

  THE (-next.x + this.x) TERM is what makes the gap mean the same thing for
  every item. `x` is where an item's ORIGIN goes, not where its ink starts; the
  correction converts one into the other so that consecutive bounding rects end
  up exactly `gap` apart however far either one hangs off its own origin.

  THE ROW PITCH IS THE TALLEST ITEM IN THE ROW BEING CLOSED, not itemHeight --
  which is why a row of line-series items sits fractionally tighter than a row
  of bars: the rule-and-marker icon is a shade shorter than the box. }
procedure BoxLayout(AHorizontal: Boolean; const ARects: array of TTyRectF;
  const ANewline: array of Boolean; AGap, AMaxW, AMaxH: Double;
  var AX, AY: array of Double);
var
  i, n: Integer;
  x, y, lineMax, moveX, moveY, nextX, nextY: Double;
  r, nr: TTyRectF;
  hasNext, wrap: Boolean;
begin
  n := Length(ARects);
  x := 0;
  y := 0;
  nextX := 0;
  nextY := 0;
  lineMax := 0;
  for i := 0 to n - 1 do
  begin
    r := ARects[i];
    hasNext := i + 1 < n;
    if hasNext then nr := ARects[i + 1];
    if AHorizontal then
    begin
      moveX := TyRectFWidth(r);
      if hasNext then moveX := moveX + (r.Left - nr.Left);
      nextX := x + moveX;
      wrap := (nextX > AMaxW) or ANewline[i];
      if wrap then
      begin
        x := 0;
        nextX := moveX;
        y := y + lineMax + AGap;
        lineMax := TyRectFHeight(r);
      end
      else
        lineMax := Max(lineMax, TyRectFHeight(r));
    end
    else
    begin
      moveY := TyRectFHeight(r);
      if hasNext then moveY := moveY + (r.Top - nr.Top);
      nextY := y + moveY;
      wrap := (nextY > AMaxH) or ANewline[i];
      if wrap then
      begin
        y := 0;
        nextY := moveY;
        x := x + lineMax + AGap;
        lineMax := TyRectFWidth(r);
      end
      else
        lineMax := Max(lineMax, TyRectFWidth(r));
    end;
    { A LINE BREAK TAKES NO PLACE AND EATS NO GAP. It has already advanced the
      row above; giving it a position too would leave a hole at the start of
      the new one. }
    if ANewline[i] then Continue;
    AX[i] := x;
    AY[i] := y;
    if AHorizontal then
      x := nextX + AGap
    else
      y := nextY + AGap;
  end;
end;

{ The padding in device px, CSS order. }
procedure PadOf(const ASpec: TTyLegendSpec; APPI: Integer; out APad: array of Double);
var i: Integer; scale: Double;
begin
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  for i := 0 to 3 do APad[i] := ASpec.Padding[i] * scale;
end;

function TyLegendWrapRect(const ASpec: TTyLegendSpec;
  const AContainer: TTyRectF; APPI: Integer): TTyXYWH;
var pad: array[0..3] of Double;
begin
  { THE OPTION'S OWN BOX, keywords and all: upstream solves the wrap room
    with no size given, so `bottom: 'bottom'` on a vertical legend leaves the
    height the switch computes from a not-a-number -- not the full height. }
  PadOf(ASpec, APPI, pad);
  Result := TyGetLayoutRect(ASpec.Box, AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top, pad);
end;

function TyLegendPlaceRect(const ASpec: TTyLegendSpec;
  const AContainer: TTyRectF; AMainW, AMainH: Double;
  APPI: Integer): TTyXYWH;
var
  pad: array[0..3] of Double;
  box: TTyRawBox;
begin
  { defaults({width, height}, params): the measured pair never goes missing,
    so it wins over anything written. }
  PadOf(ASpec, APPI, pad);
  box := ASpec.Box;
  box.Width := TyBoxRawNum(AMainW);
  box.Height := TyBoxRawNum(AMainH);
  Result := TyGetLayoutRect(box, AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top, pad);
end;

{ ==================== [Batch 98] the selector and the pager ==================== }

const
  { Transformable's EPSILON: a move inside it is no move at all }
  cAroundZero: Double = 5e-5;

function NotAroundZero(V: Double): Boolean;
begin
  Result := (V > cAroundZero) or (V < -cAroundZero);
end;

{ ZRENDER'S GLOBAL TRANSFORM of a translated element under a translated
  parent: matrix.mul(parent, local) is (1 * lx + 0 * ly) + px -- and an
  element whose own move is inside the epsilon on both axes has no local
  transform at all and takes its parent's as it is
  (Transformable.needLocalTransform). Everything the selector and the
  pager place is composed this way, so every position is the bits zrender
  draws at. }
procedure Compose(ALX, ALY, APX, APY: Double; out AX, AY: Double);
begin
  if NotAroundZero(ALX) or NotAroundZero(ALY) then
  begin
    AX := ALX + APX;
    AY := ALY + APY;
  end
  else
  begin
    AX := APX;
    AY := APY;
  end;
end;

{ upstream's [wh] / [xy] by the orient index: 0 the width and x, 1 the
  height and y }
function WHOf(const R: TTyXYWH; AIdx: Integer): Double;
begin
  if AIdx = 0 then Result := R.W else Result := R.H;
end;

function XYOf(const R: TTyXYWH; AIdx: Integer): Double;
begin
  if AIdx = 0 then Result := R.X else Result := R.Y;
end;

procedure SetWH(var R: TTyXYWH; AIdx: Integer; V: Double);
begin
  if AIdx = 0 then R.W := V else R.H := V;
end;

procedure SetXY(var R: TTyXYWH; AIdx: Integer; V: Double);
begin
  if AIdx = 0 then R.X := V else R.Y := V;
end;

{ Math.min / Math.max of two doubles }
function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

{ layout.ts boxLayout over rects as zrender holds them -- x and width, not
  two edges -- so a gap lands on the bits upstream's does }
procedure BoxLayoutXY(AHorizontal: Boolean; const ARects: array of TTyXYWH;
  const ANewline: array of Boolean; AGap, AMaxW, AMaxH: Double;
  var AX, AY: array of Double);
var
  i, n: Integer;
  x, y, lineMax, moveX, moveY, nextX, nextY: Double;
  r, nr: TTyXYWH;
  hasNext, wrap: Boolean;
begin
  n := Length(ARects);
  x := 0;
  y := 0;
  nextX := 0;
  nextY := 0;
  lineMax := 0;
  for i := 0 to n - 1 do
  begin
    r := ARects[i];
    hasNext := i + 1 < n;
    if hasNext then nr := ARects[i + 1];
    if AHorizontal then
    begin
      moveX := r.W;
      if hasNext then moveX := r.W + (-nr.X + r.X);
      nextX := x + moveX;
      wrap := (nextX > AMaxW) or ANewline[i];
      if wrap then
      begin
        x := 0;
        nextX := moveX;
        y := y + lineMax + AGap;
        lineMax := r.H;
      end
      else
        lineMax := JsMax(lineMax, r.H);
    end
    else
    begin
      moveY := r.H;
      if hasNext then moveY := r.H + (-nr.Y + r.Y);
      nextY := y + moveY;
      wrap := (nextY > AMaxH) or ANewline[i];
      if wrap then
      begin
        x := x + lineMax + AGap;
        y := 0;
        nextY := moveY;
        lineMax := r.W;
      end
      else
        lineMax := JsMax(lineMax, r.W);
    end;
    if ANewline[i] then Continue;
    AX[i] := x;
    AY[i] := y;
    if AHorizontal then
      x := nextX + AGap
    else
      y := nextY + AGap;
  end;
end;

{ Group.getBoundingRect over the first ACount children, each at (AX, AY):
  through its local transform, the first one unioned with itself; an empty
  group is (0, 0, 0, 0) }
function GroupRect(const ARects: array of TTyXYWH; const AX, AY: array of Double;
  ACount: Integer): TTyXYWH;
var
  have: Boolean;
  i: Integer;
begin
  have := False;
  Result := TyXYWH(0, 0, 0, 0);
  for i := 0 to ACount - 1 do
    TyZrAccumulate(Result, have, ARects[i], TyZrLocal(1, 1, 0, AX[i], AY[i]));
  if not have then Result := TyXYWH(0, 0, 0, 0);
end;

{ graphic.createIcon(str, no options, the box x -w/2, y -h/2, w by h): an
  'image://' is an image of the box (laid out, not drawn here); anything else
  is path data with the first 'path://' taken out, fitted into the box
  keeping its aspect. A path that parses to nothing has the empty rect. }
procedure PagerIcon(const AStr: string; AW, AH: Double; out APart: TTyLegendPagerPart);
var
  s: string;
  box: TTyXYWH;
  p: Integer;
  f32: Boolean;
begin
  APart := Default(TTyLegendPagerPart);
  box := TyXYWH(-AW / 2, -AH / 2, AW, AH);
  if Copy(AStr, 1, 8) = 'image://' then
  begin
    APart.IsImage := True;
    APart.Local := box;
    Exit;
  end;
  s := AStr;
  p := Pos('path://', s);
  if p > 0 then Delete(s, p, Length('path://'));
  APart.Path := nil;
  if s <> '' then
  begin
    { an empty parse fits nothing: its rect is nought and its aspect not a
      number, and upstream's transform of no points is no points }
    if Length(TyZrParseSvg(s, f32)) > 0 then
      APart.Path := TyZrMakePathCenter(s, box);
  end;
  APart.Local := TyZrBBox(APart.Path);
end;

procedure PlacePart(var APart: TTyLegendPagerPart; ALX, ALY, APX, APY: Double);
begin
  Compose(ALX, ALY, APX, APY, APart.X, APart.Y);
  APart.Box := TyRectF(APart.X + APart.Local.X, APart.Y + APart.Local.Y,
    APart.X + APart.Local.X + APart.Local.W, APart.Y + APart.Local.Y + APart.Local.H);
end;

{ LegendView.layoutInner with a selector, and ScrollableLegendView's
  layoutInner / _layoutContentAndController / _getPageInfo -- in their own
  arithmetic, step for step, everything group-local until the group is
  placed. ARects are the items as measured, ANewline the line breaks. }
procedure LayoutRich(const ASpec: TTyLegendSpec; const ADeco: TTyLegendDeco;
  const AContainer: TTyRectF; APPI: Integer; AScale, AGap: Double;
  const APad: array of Double; const AMaxBox: TTyXYWH;
  const ARects: array of TTyRectF; const ANewline: array of Boolean;
  var R: TTyLegendLayout);
var
  o, i, k, n, nk, ns, target, winStart, winEnd, cur: Integer;
  horiz, show: Boolean;
  kids: array of Integer;
  krect, srect: array of TTyXYWH;
  knl, snl: array of Boolean;
  kx, ky, sx, sy, ks, ke: array of Double;
  prect: array[0..2] of TTyXYWH;
  pnl: array[0..2] of Boolean;
  px, py: array[0..2] of Double;
  content, selR, ctlR, mainR, maxS, lay, b: TTyXYWH;
  selPos, contentPos, containerPos, ctlPos, finalPos: array[0..1] of Double;
  gAx, gAy, cAx, cAy, nAx, nAy, sAx, sAy, tAx, tAy, ax, ay: Double;
  selGap, pbGap, rectSize, w, h, offset, clipW, clipH: Double;
  it: TTyLegendItem;
  dflt: TTyRtDefault;

  function Intersect(AK: Integer; AWinStart: Double): Boolean;
  begin
    Result := (ke[AK] >= AWinStart) and (ks[AK] <= AWinStart + rectSize);
  end;

begin
  if ASpec.Orient = tloVertical then o := 1 else o := 0;
  horiz := o = 0;
  n := Length(ARects);

  { THE CONTENT'S CHILDREN: every entry drawn, line breaks included on a
    plain legend; a scroll legend disables line breaks (newlineDisabled), so
    its '' and '\n' are names no series answers to and draw nothing }
  SetLength(kids, n);
  nk := 0;
  for i := 0 to n - 1 do
  begin
    if ASpec.IsScroll and ANewline[i] then Continue;
    kids[nk] := i;
    Inc(nk);
  end;
  SetLength(kids, nk);
  SetLength(krect, nk);
  SetLength(knl, nk);
  SetLength(kx, nk);
  SetLength(ky, nk);
  for k := 0 to nk - 1 do
  begin
    i := kids[k];
    krect[k] := TyXYWH(ARects[i].Left, ARects[i].Top,
      ARects[i].Right - ARects[i].Left, ARects[i].Bottom - ARects[i].Top);
    knl[k] := ANewline[i];
    kx[k] := 0;
    ky[k] := 0;
  end;

  { THE SELECTOR'S BUTTONS, laid out left to right whatever the orient:
    each a text block hung left/top from its origin }
  ns := 0;
  if ASpec.HasSelector then ns := Length(ASpec.Selector);
  SetLength(R.Selector, ns);
  SetLength(srect, ns);
  SetLength(snl, ns);
  SetLength(sx, ns);
  SetLength(sy, ns);
  dflt := TyRtDefaultOf(False, 0, False, 0, False, tahLeft, tavTop);
  for k := 0 to ns - 1 do
  begin
    R.Selector[k].IsAll := ASpec.Selector[k].IsAll;
    R.Selector[k].Title := ASpec.Selector[k].Title;
    R.Selector[k].Pieces := nil;
    R.Selector[k].EmphPieces := nil;
    b := TyXYWH(0, 0, 0, 0);
    if ADeco.Measurer <> nil then
    begin
      R.Selector[k].Pieces := TyRtLay(ASpec.Selector[k].Title, ADeco.SelBlock,
        dflt, AScale, ADeco.Measurer);
      R.Selector[k].EmphPieces := TyRtLay(ASpec.Selector[k].Title,
        ADeco.SelEmphBlock, dflt, AScale, ADeco.Measurer);
      b := TyRtBounds(R.Selector[k].Pieces);
      if b.W < 0 then b := TyXYWH(0, 0, 0, 0);
    end;
    R.Selector[k].Local := TyXYWH(b.X * AScale, b.Y * AScale, b.W * AScale,
      b.H * AScale);
    srect[k] := R.Selector[k].Local;
    snl[k] := False;
    sx[k] := 0;
    sy[k] := 0;
  end;
  selGap := ASpec.SelectorButtonGap * AScale;
  selR := TyXYWH(0, 0, 0, 0);
  if ASpec.HasSelector then
  begin
    BoxLayoutXY(True, srect, snl, ASpec.SelectorItemGap * AScale, Infinity,
      Infinity, sx, sy);
    selR := GroupRect(srect, sx, sy, ns);
  end;
  selPos[0] := -selR.X;
  selPos[1] := -selR.Y;

  rectSize := 0;
  show := False;
  if not ASpec.IsScroll then
  begin
    { ==== LegendView.layoutInner, the selector branch ==== }
    BoxLayoutXY(horiz, krect, knl, AGap, AMaxBox.W, AMaxBox.H, kx, ky);
    content := GroupRect(krect, kx, ky, nk);
    contentPos[0] := -content.X;
    contentPos[1] := -content.Y;
    if ASpec.SelectorAtEnd then
      selPos[o] := selPos[o] + (WHOf(content, o) + selGap)
    else
      contentPos[o] := contentPos[o] + (WHOf(selR, o) + selGap);
    { always aligned to the content as 'middle' }
    selPos[1 - o] := selPos[1 - o] + (WHOf(content, 1 - o) / 2 - WHOf(selR, 1 - o) / 2);
    mainR := TyXYWH(0, 0, 0, 0);
    SetWH(mainR, o, WHOf(content, o) + selGap + WHOf(selR, o));
    SetWH(mainR, 1 - o, JsMax(WHOf(content, 1 - o), WHOf(selR, 1 - o)));
    SetXY(mainR, 1 - o, JsMin(0, XYOf(selR, 1 - o) + selPos[1 - o]));
    finalPos := contentPos;
    containerPos[0] := 0;
    containerPos[1] := 0;
  end
  else
  begin
    { ==== ScrollableLegendView.layoutInner ==== }
    maxS := AMaxBox;
    if ASpec.HasSelector then
      SetWH(maxS, o, WHOf(AMaxBox, o) - WHOf(selR, o) - selGap);

    { ==== _layoutContentAndController ==== one line, never wrapped }
    BoxLayoutXY(horiz, krect, knl, AGap, Infinity, Infinity, kx, ky);
    { the pager, laid out left to right around the PLACEHOLDER text }
    w := ASpec.PageIconW * AScale;
    h := ASpec.PageIconH * AScale;
    PagerIcon(ASpec.PageIcons[ASpec.Orient, 0], w, h, R.PagePrev);
    PagerIcon(ASpec.PageIcons[ASpec.Orient, 1], w, h, R.PageNext);
    R.PageFontName := ADeco.PageFontName;
    R.PageFontSize := ADeco.PageFontSize;
    R.PageFontWeight := ADeco.PageFontWeight;
    w := 0;
    h := 0;
    if ADeco.Measurer <> nil then
      ADeco.Measurer.MeasureLine(cPagePlaceholder, ADeco.PageFontName,
        ADeco.PageFontSize, ADeco.PageFontWeight, w, h);
    prect[0] := R.PagePrev.Local;
    prect[1] := TyXYWH(0 - w / 2, 0 - h / 2, w, h);
    prect[2] := R.PageNext.Local;
    for k := 0 to 2 do
    begin
      pnl[k] := False;
      px[k] := 0;
      py[k] := 0;
    end;
    BoxLayoutXY(True, prect, pnl, ASpec.PageButtonItemGap * AScale, Infinity,
      Infinity, px, py);

    content := GroupRect(krect, kx, ky, nk);
    ctlR := GroupRect(prect, px, py, 3);
    show := WHOf(content, o) > WHOf(maxS, o);
    contentPos[0] := -content.X;
    contentPos[1] := -content.Y;
    containerPos[0] := 0;
    containerPos[1] := 0;
    ctlPos[0] := -ctlR.X;
    ctlPos[1] := -ctlR.Y;
    { retrieve2(pageButtonGap, itemGap) }
    if IsNan(ASpec.PageButtonGap) then pbGap := AGap
    else pbGap := ASpec.PageButtonGap * AScale;
    if show then
    begin
      if ASpec.PageButtonAtEnd then
        ctlPos[o] := ctlPos[o] + (WHOf(maxS, o) - WHOf(ctlR, o))
      else
        containerPos[o] := containerPos[o] + (WHOf(ctlR, o) + pbGap);
    end;
    { always aligned to the content as 'middle' }
    ctlPos[1 - o] := ctlPos[1 - o] + (WHOf(content, 1 - o) / 2 - WHOf(ctlR, 1 - o) / 2);

    { THE MAIN RECT counts the controller even when it is hidden: it is a
      placeholder, kept and sized in }
    mainR := TyXYWH(0, 0, 0, 0);
    if show then SetWH(mainR, o, WHOf(maxS, o))
    else SetWH(mainR, o, WHOf(content, o));
    SetWH(mainR, 1 - o, JsMax(WHOf(content, 1 - o), WHOf(ctlR, 1 - o)));
    SetXY(mainR, 1 - o, JsMin(0, XYOf(ctlR, 1 - o) + ctlPos[1 - o]));

    rectSize := WHOf(maxS, o);
    clipW := 0;
    clipH := 0;
    if show then
    begin
      offset := JsMax(WHOf(maxS, o) - WHOf(ctlR, o) - pbGap, 0);
      if o = 0 then
      begin
        clipW := offset;
        clipH := WHOf(mainR, 1 - o);
      end
      else
      begin
        clipH := offset;
        clipW := WHOf(mainR, 1 - o);
      end;
      rectSize := offset;
    end;

    { ==== _getPageInfo ==== }
    SetLength(ks, nk);
    SetLength(ke, nk);
    for k := 0 to nk - 1 do
    begin
      if o = 0 then ks[k] := XYOf(krect[k], 0) + kx[k]
      else ks[k] := XYOf(krect[k], 1) + ky[k];
      ke[k] := ks[k] + WHOf(krect[k], o);
    end;
    { _findTargetItemIndex: the first item unless the pager shows, then the
      item whose data index IS scrollDataIndex (===), else the first }
    target := -1;
    if nk > 0 then
    begin
      target := 0;
      if show and ASpec.ScrollIsNum then
        for k := 0 to nk - 1 do
          if kids[k] = ASpec.ScrollNum then target := k;
    end;
    finalPos := contentPos;
    if nk > 0 then R.PageCount := 1 else R.PageCount := 0;
    R.PageIndex := R.PageCount - 1;
    R.PagePrevIndex := -1;
    R.PageNextIndex := -1;
    if target >= 0 then
    begin
      finalPos[o] := -ks[target];
      winStart := target;
      winEnd := target;
      for i := target + 1 to nk do
      begin
        if i < nk then cur := i else cur := -1;
        { half of the last item is out of the window, or the current item
          does not reach it: a page starts at it or at the last one }
        if ((cur < 0) and (ke[winEnd] > ks[winStart] + rectSize))
          or ((cur >= 0) and not Intersect(cur, ks[winStart])) then
        begin
          if kids[winEnd] > kids[winStart] then winStart := winEnd
          else winStart := cur;
          if winStart >= 0 then
          begin
            if R.PageNextIndex < 0 then R.PageNextIndex := kids[winStart];
            Inc(R.PageCount);
          end;
        end;
        winEnd := cur;
      end;
      winStart := target;
      winEnd := target;
      for i := target - 1 downto -1 do
      begin
        cur := i;
        if ((cur < 0) or not Intersect(winEnd, ks[cur]))
          and (kids[winStart] < kids[winEnd]) then
        begin
          winEnd := winStart;
          if R.PagePrevIndex < 0 then R.PagePrevIndex := kids[winStart];
          Inc(R.PageCount);
          Inc(R.PageIndex);
        end;
        winStart := cur;
      end;
    end;

    { ==== back in layoutInner: the selector beside it all ==== }
    if ASpec.HasSelector then
    begin
      if ASpec.SelectorAtEnd then
        selPos[o] := selPos[o] + (WHOf(mainR, o) + selGap)
      else
      begin
        offset := WHOf(selR, o) + selGap;
        selPos[o] := selPos[o] - offset;
        SetXY(mainR, o, XYOf(mainR, o) - offset);
      end;
      SetWH(mainR, o, WHOf(mainR, o) + (WHOf(selR, o) + selGap));
      selPos[1 - o] := selPos[1 - o]
        + (XYOf(mainR, 1 - o) + WHOf(mainR, 1 - o) / 2 - WHOf(selR, 1 - o) / 2);
      SetWH(mainR, 1 - o, JsMax(WHOf(mainR, 1 - o), WHOf(selR, 1 - o)));
      SetXY(mainR, 1 - o, JsMin(XYOf(mainR, 1 - o), XYOf(selR, 1 - o) + selPos[1 - o]));
    end;
  end;

  { ==== LegendView.render: the group placed by the main rect ==== }
  lay := TyLegendPlaceRect(ASpec, AContainer, mainR.W, mainR.H, APPI);
  R.GroupX := lay.X - mainR.X;
  R.GroupY := lay.Y - mainR.Y;
  R.MainRect := mainR;
  R.IsScroll := ASpec.IsScroll;
  R.ShowController := show;
  Compose(R.GroupX, R.GroupY, 0, 0, gAx, gAy);

  { the items, under the container and the content }
  R.ContentPosX := finalPos[0];
  R.ContentPosY := finalPos[1];
  R.ContentFromX := contentPos[0];
  R.ContentFromY := contentPos[1];
  Compose(containerPos[0], containerPos[1], gAx, gAy, cAx, cAy);
  Compose(finalPos[0], finalPos[1], cAx, cAy, nAx, nAy);
  for k := 0 to nk - 1 do
  begin
    if knl[k] then Continue;
    i := kids[k];
    Compose(kx[k], ky[k], nAx, nAy, ax, ay);
    it := R.Items[i];
    it.IconBox := TyRectF(ax, ay, ax + ASpec.ItemWidth * AScale,
      ay + ASpec.ItemHeight * AScale);
    it.TextX := it.TextX + ax;
    it.TextY := it.TextY + ay;
    it.Bounds := TyRectF(ax + krect[k].X, ay + krect[k].Y,
      ax + krect[k].X + krect[k].W, ay + krect[k].Y + krect[k].H);
    R.Items[i] := it;
  end;

  { the buttons }
  Compose(selPos[0], selPos[1], gAx, gAy, sAx, sAy);
  for k := 0 to ns - 1 do
  begin
    Compose(sx[k], sy[k], sAx, sAy, R.Selector[k].X, R.Selector[k].Y);
    b := R.Selector[k].Local;
    R.Selector[k].Box := TyRectF(R.Selector[k].X + b.X, R.Selector[k].Y + b.Y,
      R.Selector[k].X + b.X + b.W, R.Selector[k].Y + b.Y + b.H);
  end;

  { the pager, and the clip on the container }
  if ASpec.IsScroll then
  begin
    Compose(ctlPos[0], ctlPos[1], gAx, gAy, tAx, tAy);
    PlacePart(R.PagePrev, px[0], py[0], tAx, tAy);
    PlacePart(R.PageNext, px[2], py[2], tAx, tAy);
    if ASpec.HasPageFormatter then
      R.PageText := TyLegendPageText(ASpec.PageFormatter, R.PageIndex + 1,
        R.PageCount)
    else
      R.PageText := cPagePlaceholder;
    w := 0;
    h := 0;
    if ADeco.Measurer <> nil then
      ADeco.Measurer.MeasureLine(R.PageText, ADeco.PageFontName,
        ADeco.PageFontSize, ADeco.PageFontWeight, w, h);
    R.PageTextPart := Default(TTyLegendPagerPart);
    R.PageTextPart.Local := TyXYWH(0 - w / 2, 0 - h / 2, w, h);
    PlacePart(R.PageTextPart, px[1], py[1], tAx, tAy);
    R.HasClip := show;
    if show then
      R.Clip := TyRectF(cAx, cAy, cAx + clipW, cAy + clipH);
  end;

  { makeBackground(mainRect): the padding around it, group-local }
  b := TyXYWH(mainR.X - APad[3], mainR.Y - APad[0],
    mainR.W + APad[1] + APad[3], mainR.H + APad[0] + APad[2]);
  R.Frame := TyRectF(gAx + b.X, gAy + b.Y, gAx + b.X + b.W, gAy + b.Y + b.H);
  R.Content := TyRectF(gAx + mainR.X, gAy + mainR.Y, gAx + mainR.X + mainR.W,
    gAy + mainR.Y + mainR.H);
  R.Valid := True;
end;

function TyLayoutLegend(const ASpec: TTyLegendSpec;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const ASources: TTyLegendSourceArray; const AContainer: TTyRectF;
  const AMeasurer: ITyTextMeasurer; const AFont: TTyLegendFont;
  APPI: Integer): TTyLegendLayout;
begin
  Result := TyLayoutLegend(ASpec, AEntries, AFlags, ASources, AContainer,
    AMeasurer, AFont, APPI, Default(TTyLegendDeco));
end;

function TyLayoutLegend(const ASpec: TTyLegendSpec;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const ASources: TTyLegendSourceArray; const AContainer: TTyRectF;
  const AMeasurer: ITyTextMeasurer; const AFont: TTyLegendFont;
  APPI: Integer; const ADeco: TTyLegendDeco): TTyLegendLayout;
var
  n, i: Integer;
  scale, iw, ih, gap, tgap: Double;
  pad: array[0..3] of Double;
  maxBox, layoutBox: TTyXYWH;
  content: TTyRectF;
  spec2: TTyBoxSpec;
  rects: array of TTyRectF;
  newline: array of Boolean;
  px, py: array of Double;
  src: TTyLegendSource;
  it: TTyLegendItem;
  iconR, textR: TTyRectF;
  textX, ox, oy, mainW, mainH: Double;
  drawn: Integer;
  boxM: ITyTextBoxMeasurer;
  tb: TTyRectF;
begin
  Result := Default(TTyLegendLayout);
  if not ASpec.Show then Exit;
  if AMeasurer = nil then Exit;
  if not TyRectFIsValid(AContainer) then Exit;
  n := Length(AEntries);
  if n = 0 then Exit;

  if APPI > 0 then scale := APPI / 96 else scale := 1;
  for i := 0 to 3 do pad[i] := ASpec.Padding[i] * scale;
  gap := ASpec.ItemGap * scale;
  iw := ASpec.ItemWidth * scale;
  ih := ASpec.ItemHeight * scale;
  tgap := cTextGap * scale;

  { ALIGN IS DERIVED FROM THE WORD, not from the solved edge, and only a
    VERTICAL legend pinned by the literal `left: 'right'` gets the right-hand
    form. LegendView.ts:118-125. }
  Result.Align := ASpec.Align;
  if Result.Align = tlaAuto then
  begin
    if (ASpec.Box.Left.Kind = brString) and (ASpec.Box.Left.Str = 'right')
      and (ASpec.Orient = tloVertical) then
      Result.Align := tlaRight
    else
      Result.Align := tlaLeft;
  end;

  { THE FIRST OF TWO BOX SOLVES. This one answers "how much room is there",
    and only its SIZE is used -- as the wrap limit. The second one, further
    down, places the block that the wrap produced. }
  maxBox := TyLegendWrapRect(ASpec, AContainer, APPI);

  SetLength(Result.Items, n);
  SetLength(rects, n);
  SetLength(newline, n);
  SetLength(px, n);
  SetLength(py, n);

  for i := 0 to n - 1 do
  begin
    it := Default(TTyLegendItem);
    it.Entry := i;
    it.Name := AEntries[i].Name;
    it.Selected := (i <= High(AFlags)) and AFlags[i];
    newline[i] := AEntries[i].Newline;
    px[i] := 0;
    py[i] := 0;
    if newline[i] then
    begin
      { An empty group measures (0, 0, 0, 0) and that zero is load-bearing: it
        is what resets the row pitch.

        ITS OWN BOUNDS ARE INVALID, not zero. A break is never placed, and an
        all-zero rectangle is a perfectly valid rectangle at the origin -- so
        saying `not placed` with one would leave every consumer testing a
        degenerate box instead of asking the question it means to ask. }
      rects[i] := TyRectF(0, 0, 0, 0);
      it.Bounds := TyInvalidRectF;
      it.IconBox := TyInvalidRectF;
      Result.Items[i] := it;
      Continue;
    end;

    src := Default(TTyLegendSource);
    if i <= High(ASources) then src := ASources[i];
    if src.Greyed then it.Selected := False;
    ResolveIcon(ASpec, AEntries[i], src, it.Icon, it.OwnIcon);
    it.Colour := src.Colour;
    it.LineColour := src.LineColour;
    it.HasOpacity := src.HasOpacity;
    it.Opacity := src.Opacity;
    { `lineStyle.width: 'auto'` is resolved by whoever filled the source in --
      it is the one rule here that needs to know whether the SERIES draws a
      line, and this unit does not. Zero means no rule. }
    it.LineWidthLogical := src.LineWidthLogical;
    { THE ICON'S PEN [Batch 93]: `borderWidth: 'auto'` is 2 for a series
      with a border; unselected, inactiveBorderWidth 'auto' asks for the
      series' stroke too, and any other value keeps the selected width }
    it.HasStroke := src.HasStroke;
    it.Stroke := src.Stroke;
    if src.VisualLineWidth > 0 then it.IconPen := 2 else it.IconPen := 0;
    if (not it.Selected) and ASpec.InactiveBorderAuto then
    begin
      if (src.VisualLineWidth > 0) and src.HasStroke then it.IconPen := 2
      else it.IconPen := 0;
    end;
    it.Text := TyLegendText(ASpec.Formatter, it.Name);

    AMeasurer.MeasureLine(it.Text, AFont.Name, AFont.SizeLogical,
      AFont.Weight, it.TextW, it.TextH);

    { stroked: unselected always has inactiveBorderColor, selected only the
      series' stroke }
    if (it.IconPen > 0) and ((not it.Selected) or it.HasStroke) then
      iconR := IconExtent(it.Icon, it.OwnIcon, iw, ih,
        it.LineWidthLogical * scale, RingPen(it.LineWidthLogical) * scale,
        it.IconPen * scale)
    else
      iconR := IconExtent(it.Icon, it.OwnIcon, iw, ih,
        it.LineWidthLogical * scale, RingPen(it.LineWidthLogical) * scale);

    { THE WORDS HANG OFF THE ICON'S FAR EDGE, and off its NEAR edge when the
      legend is right-aligned -- where the anchor goes NEGATIVE and the item's
      whole rectangle starts to the left of its own origin. That is the case
      the wrap's correction term exists for. }
    if Result.Align = tlaLeft then
    begin
      textX := iw + tgap;
      it.AnchorH := tahLeft;
      textR := TyRectF(textX, ih / 2 - it.TextH / 2,
                       textX + it.TextW, ih / 2 + it.TextH / 2);
    end
    else
    begin
      textX := -tgap;
      it.AnchorH := tahRight;
      textR := TyRectF(textX - it.TextW, ih / 2 - it.TextH / 2,
                       textX, ih / 2 + it.TextH / 2);
    end;
    { A BLOCK'S BOX WHERE IT SITS: a bordered token overhangs the anchor by
      half its stroke, and the overhang on the icon's side is inside the
      item's group already (LegendView.ts _createItem: the group's bounds) }
    if Supports(AMeasurer, ITyTextBoxMeasurer, boxM) then
    begin
      tb := boxM.MeasureBox(it.Text, AFont.Name, AFont.SizeLogical, AFont.Weight,
        it.AnchorH, tavMiddle);
      textR := TyRectF(textX + tb.Left, ih / 2 + tb.Top, textX + tb.Right,
        ih / 2 + tb.Bottom);
    end;
    it.TextX := textX;
    it.TextY := ih / 2;

    rects[i] := RectUnion(iconR, textR);
    if not TyRectFIsValid(rects[i]) then rects[i] := TyRectF(0, 0, 0, 0);
    Result.Items[i] := it;
  end;

  { [Batch 98] A SELECTOR OR A PAGER is upstream's other layoutInner: the
    plain one without either stays exactly as it was }
  if ASpec.IsScroll or ASpec.HasSelector then
  begin
    LayoutRich(ASpec, ADeco, AContainer, APPI, scale, gap, pad, maxBox, rects,
      newline, Result);
    Exit;
  end;

  BoxLayout(ASpec.Orient = tloHorizontal, rects, newline, gap,
    maxBox.W, maxBox.H, px, py);

  content := TyInvalidRectF;
  drawn := 0;
  for i := 0 to n - 1 do
  begin
    if newline[i] then Continue;
    content := RectUnion(content,
      TyRectF(px[i] + rects[i].Left, py[i] + rects[i].Top,
              px[i] + rects[i].Right, py[i] + rects[i].Bottom));
    Inc(drawn);
  end;
  if (drawn = 0) or not TyRectFIsValid(content) then Exit;

  mainW := TyRectFWidth(content);
  mainH := TyRectFHeight(content);

  { THE SECOND SOLVE, and the measured size WINS over `legend.width`: upstream
    merges {width, height} with defaults(), which only fills in what is
    missing, and the measured pair is never missing. }
  layoutBox := TyLegendPlaceRect(ASpec, AContainer, mainW, mainH, APPI);

  { The content group is shifted so that its own top-left lands on the solved
    corner, whatever negative overhang the items have. }
  ox := layoutBox.X - content.Left;
  oy := layoutBox.Y - content.Top;

  for i := 0 to n - 1 do
  begin
    if newline[i] then Continue;
    it := Result.Items[i];
    it.IconBox := TyRectF(ox + px[i], oy + py[i],
                          ox + px[i] + iw, oy + py[i] + ih);
    it.TextX := it.TextX + ox + px[i];
    it.TextY := it.TextY + oy + py[i];
    it.Bounds := TyRectF(ox + px[i] + rects[i].Left, oy + py[i] + rects[i].Top,
                         ox + px[i] + rects[i].Right,
                         oy + py[i] + rects[i].Bottom);
    Result.Items[i] := it;
  end;

  Result.Content := TyRectF(layoutBox.X, layoutBox.Y,
                            layoutBox.X + mainW, layoutBox.Y + mainH);
  Result.Frame := TyRectF(Result.Content.Left - pad[3],
                          Result.Content.Top - pad[0],
                          Result.Content.Right + pad[1],
                          Result.Content.Bottom + pad[2]);
  Result.Valid := True;
end;

{ ==================== the marks ==================== }

function TyBuildLegendMarks(const ASpec: TTyLegendSpec;
  const ALayout: TTyLegendLayout; const AInk: TTyLegendInk;
  const AFont: TTyLegendFont; APPI: Integer; AList: TTyPaintList;
  ALegendIndex: Integer; const AMeasurer: ITyTextMeasurer;
  ASelHover: Integer): Integer;
var
  k: Integer;
  hit: TTyRectF;
  m: TTyMat2D;
  rtb: TTyRtBlockStyle;
  pieces: TTyRtPieceArray;
  rtScale: Double;
  i: Integer;
  scale: Double;
  el: TTyChartElement;
  it: TTyLegendItem;
  empty: Boolean;
  path: string;
  kind: TTySymbolKind;
  pts: array[0..1] of TTyPointF;
  size, pen: Double;
  colour: TTyChartColor;

  function Blank: TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Z := ASpec.Z;
    Result.Silent := True;
    Result.Datum := TyChartNoDatum;
    Result.Style.Alpha := 1;
  end;

  { [Batch 98] an item's element under the scroll legend's clip }
  procedure Clipped(var AEl: TTyChartElement);
  begin
    if not ALayout.HasClip then Exit;
    AEl.HasClip := True;
    AEl.ClipRect := ALayout.Clip;
  end;

  { the pager's icon: its fitted path where the part stands }
  procedure DrawPagerIcon(const APart: TTyLegendPagerPart; ACanJump: Boolean;
    AWhich: Integer);
  begin
    if APart.IsImage or (Length(APart.Path) = 0) then
    begin
      { an image icon is not drawn here; its box still takes the click }
    end
    else
    begin
      m[0] := 1; m[1] := 0; m[2] := 0; m[3] := 1;
      m[4] := APart.X;
      m[5] := APart.Y;
      el := Blank;
      el.Shape := TyMkZrShape(APart.Path, m, True);
      el.Style.HasFill := True;
      if ACanJump then el.Style.FillColor := AInk.PageIcon
      else el.Style.FillColor := AInk.PageIconInactive;
      AList.Add(el);
      Inc(Result);
    end;
    { rectHover: the icon's box is its target, and it is clickable whether
      or not it can jump -- a click that cannot does nothing }
    if ALegendIndex >= 0 then
    begin
      el := Blank;
      el.Shape := TyShapeRect(APart.Box);
      el.Silent := False;
      el.Datum := TyChartComponentDatum(ctkLegendPager, ALegendIndex, AWhich);
      AList.Add(el);
      Inc(Result);
    end;
  end;

  { ONE ICON IN A GIVEN BOX. The marker on a line's own icon and the shared
    icon are the same shape styled the same way in two different boxes; the
    two used to be written out twice, which is how they would have drifted.

    An `empty` icon is a RING -- the series colour becomes the pen and the
    hole is the chart's own ground, so it reads as a hole rather than as a
    white dot on a dark skin. A bare `line` is the one shape that is stroked
    and not filled at all. Everything else is a solid fill. }
  function Icon(AKind: TTySymbolKind; AEmpty: Boolean;
    const APath: string; const ABox: TTyRectF): TTyChartElement;
  var sp: TTySymbolSpec;
  begin
    sp := Default(TTySymbolSpec);
    sp.Kind := AKind;
    sp.Empty := AEmpty;
    sp.PathData := APath;
    Result := Blank;
    Result.Shape := TyBuildSymbolInBox(sp, ABox);
    if AEmpty or (AKind = tsyLine) then
    begin
      Result.Style.StrokeColor := colour;
      Result.Style.StrokeWidthLogical := RingPen(it.LineWidthLogical);
      if AKind <> tsyLine then
      begin
        Result.Style.HasFill := True;
        Result.Style.FillColor := AInk.EmptyFill;
      end;
    end
    else
    begin
      Result.Style.HasFill := True;
      Result.Style.FillColor := colour;
      { THE PEN [Batch 93]: the series' stroke while selected,
        inactiveBorderColor while not -- the width resolved by the layout }
      if (it.IconPen > 0) and ((not it.Selected) or it.HasStroke) then
      begin
        if it.Selected then Result.Style.StrokeColor := it.Stroke
        else Result.Style.StrokeColor := AInk.InactiveBorder;
        Result.Style.StrokeWidthLogical := it.IconPen;
      end;
    end;
  end;

begin
  Result := 0;
  if AList = nil then Exit;
  if not ALayout.Valid then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;

  { The frame first and UNDER everything, and only when the option asked for
    one: upstream gives a legend a transparent background and a zero border, so
    painting a plate behind every legend would put a visible box on every
    chart in the gallery. }
  if ASpec.HasBackground or (ASpec.BorderWidth > 0) then
  begin
    el := Blank;
    el.Z2 := -1;
    el.Shape := TyShapeRoundRect(ALayout.Frame,
      ASpec.BorderRadii[0] * scale);
    el.Style.HasFill := ASpec.HasBackground;
    el.Style.FillColor := AInk.Background;
    if ASpec.BorderWidth > 0 then
    begin
      el.Style.StrokeWidthLogical := ASpec.BorderWidth;
      el.Style.StrokeColor := AInk.Border;
    end;
    AList.Add(el);
    Inc(Result);
  end;

  for i := 0 to High(ALayout.Items) do
  begin
    it := ALayout.Items[i];
    if not TyRectFIsValid(it.Bounds) then Continue;
    { THE ITEM'S ONE HIT TARGET: an unpainted rect over its bounds, under
      which the icon and the words stay silent -- upstream's legend item is a
      single target too, so moving from its icon to its words is no
      out-and-over [Batch 84] }
    hit := it.Bounds;
    { [Batch 98] the clip holds for the pointer too: zrender's isHover asks
      every ancestor's clip path, so an item scrolled out of the window
      takes no hover and no click }
    if ALayout.HasClip then
      hit := TyRectF(Max(hit.Left, ALayout.Clip.Left), Max(hit.Top, ALayout.Clip.Top),
        Min(hit.Right, ALayout.Clip.Right), Min(hit.Bottom, ALayout.Clip.Bottom));
    if (ALegendIndex >= 0) and (hit.Right > hit.Left) and (hit.Bottom > hit.Top) then
    begin
      el := Blank;
      el.Shape := TyShapeRect(hit);
      { `hitRect.silent = !selectMode` (LegendView.ts:506): selectedMode
        false takes the pointer away -- no hover link, no click, and no
        legend mouse event either, its children being silent already
        [Batch 93] }
      el.Silent := ASpec.SelectedMode = tlsOff;
      el.Datum := TyChartComponentDatum(ctkLegend, ALegendIndex, i);
      AList.Add(el);
      Inc(Result);
    end;

    { DESELECTED IS ONE COLOUR FOR EVERYTHING -- icon, ring, rule and words.
      Upstream reaches it through four separate options that all default to
      the same disabled token. }
    if it.Selected then colour := it.Colour else colour := AInk.Inactive;

    kind := TySymbolKindOf(it.Icon, empty, path);
    if it.OwnIcon then
    begin
      { THE RULE FIRST AND THE MARKER OVER IT, which is the order upstream
        adds them in and it shows: an `empty` marker is FILLED with the
        chart's own ground, so the ring's hole covers the middle of the rule
        and what reaches the eye is two stubs with a ring between them. }
      pen := it.LineWidthLogical;
      if pen > 0 then
      begin
        pts[0] := TyPointF(it.IconBox.Left,
                           (it.IconBox.Top + it.IconBox.Bottom) / 2);
        pts[1] := TyPointF(it.IconBox.Right,
                           (it.IconBox.Top + it.IconBox.Bottom) / 2);
        el := Blank;
        Clipped(el);
        el.Shape := TyShapePolyline(pts);
        el.Style.StrokeWidthLogical := pen;
        if it.Selected then
          el.Style.StrokeColor := it.LineColour
        else
        begin
          { `lineStyle.inactiveColor` / `inactiveWidth` [Batch 93] }
          el.Style.StrokeColor := AInk.LineInactive;
          if AInk.LineInactiveWidth > 0 then
            el.Style.StrokeWidthLogical := AInk.LineInactiveWidth;
        end;
        AList.Add(el);
        Inc(Result);
      end;
      { The marker, four fifths of the box's height and centred in it. }
      size := TyRectFHeight(it.IconBox) * cOwnIconMarker;
      if (kind <> tsyNone) and (size > 0) then
      begin
        el := Icon(kind, empty, path,
          TyRectF((it.IconBox.Left + it.IconBox.Right - size) / 2,
                  (it.IconBox.Top + it.IconBox.Bottom - size) / 2,
                  (it.IconBox.Left + it.IconBox.Right + size) / 2,
                  (it.IconBox.Top + it.IconBox.Bottom + size) / 2));
        Clipped(el);
        AList.Add(el);
        Inc(Result);
      end;
    end
    else if kind <> tsyNone then
    begin
      el := Icon(kind, empty, path, it.IconBox);
      Clipped(el);
      if it.HasOpacity then
        el.Style.Alpha := Min(Double(1), Max(Double(0), it.Opacity));
      AList.Add(el);
      Inc(Result);
    end;

    if it.Text <> '' then
    begin
      el := Blank;
      Clipped(el);
      { A PLAIN RECT UNDER THE WORDS, never painted -- it is what gives the
        caption a place in a list whose every other member is a shape. }
      el.Shape := TyShapeRect(TyRectF(
        it.TextX - it.TextW * Ord(it.AnchorH = tahRight), it.TextY - it.TextH / 2,
        it.TextX + it.TextW * Ord(it.AnchorH = tahLeft), it.TextY + it.TextH / 2));
      el.Caption.Text := it.Text;
      el.Caption.FontName := AFont.Name;
      el.Caption.FontSizeLogical := AFont.SizeLogical;
      el.Caption.FontWeight := AFont.Weight;
      if it.Selected then
        el.Caption.Colour := AInk.Text
      else
        el.Caption.Colour := AInk.Inactive;
      el.Caption.X := it.TextX;
      el.Caption.Y := it.TextY;
      el.Caption.AnchorH := it.AnchorH;
      el.Caption.AnchorV := tavMiddle;
      { THE BLOCK: the item's ink is its fixed fill and the inherit colour a
        rich style without a colour takes (LegendView.ts:470-480) [Batch 86] }
      if AFont.Rt.Needed and (AMeasurer <> nil) then
      begin
        if APPI > 0 then rtScale := APPI / 96 else rtScale := 1;
        rtb := AFont.Rt;
        TyRtFinish(rtb, AFont.Name, AFont.SizeLogical, AFont.Weight,
          AFont.RtGlobal, True, el.Caption.Colour);
        rtb.Style.HasFill := True;
        rtb.Style.FillNone := False;
        rtb.Style.Fill := el.Caption.Colour;
        pieces := TyRtLay(it.Text, rtb, TyRtDefaultOf(False, 0, False, 0, False,
          it.AnchorH, tavMiddle), rtScale, AMeasurer);
        if Length(pieces) > 0 then
        begin
          el.Caption.RtPieces := pieces;
          el.Caption.RtScale := rtScale;
          el.Shape := TyShapeRect(TyRtDeviceBox(pieces, it.TextX, it.TextY, 0,
            rtScale));
        end;
      end;
      AList.Add(el);
      Inc(Result);
    end;
  end;

  { [Batch 98] THE SELECTOR'S BUTTONS: the words as their block, in the
    hovered ink while the pointer is on one (enableHoverEmphasis), and the
    whole box as the target }
  for k := 0 to High(ALayout.Selector) do
  begin
    if ALegendIndex >= 0 then
    begin
      el := Blank;
      el.Shape := TyShapeRect(ALayout.Selector[k].Box);
      el.Silent := False;
      el.Datum := TyChartComponentDatum(ctkLegendSelector, ALegendIndex, k);
      AList.Add(el);
      Inc(Result);
    end;
    if Length(ALayout.Selector[k].Pieces) = 0 then Continue;
    el := Blank;
    el.Shape := TyShapeRect(ALayout.Selector[k].Box);
    el.Caption.Text := ALayout.Selector[k].Title;
    el.Caption.FontName := AFont.Name;
    el.Caption.FontSizeLogical := AFont.SizeLogical;
    el.Caption.FontWeight := AFont.Weight;
    el.Caption.Colour := AInk.Text;
    el.Caption.X := ALayout.Selector[k].X;
    el.Caption.Y := ALayout.Selector[k].Y;
    el.Caption.AnchorH := tahLeft;
    el.Caption.AnchorV := tavTop;
    if k = ASelHover then el.Caption.RtPieces := ALayout.Selector[k].EmphPieces
    else el.Caption.RtPieces := ALayout.Selector[k].Pieces;
    if APPI > 0 then el.Caption.RtScale := APPI / 96 else el.Caption.RtScale := 1;
    AList.Add(el);
    Inc(Result);
  end;

  { [Batch 98] THE PAGER, only when the items overflow: hidden, it is a
    placeholder neither drawn nor hit }
  if ALayout.IsScroll and ALayout.ShowController then
  begin
    DrawPagerIcon(ALayout.PagePrev, ALayout.PagePrevIndex >= 0, 0);
    el := Blank;
    el.Shape := TyShapeRect(ALayout.PageTextPart.Box);
    el.Caption.Text := ALayout.PageText;
    el.Caption.FontName := ALayout.PageFontName;
    el.Caption.FontSizeLogical := ALayout.PageFontSize;
    el.Caption.FontWeight := ALayout.PageFontWeight;
    el.Caption.Colour := AInk.PageText;
    el.Caption.X := ALayout.PageTextPart.X;
    el.Caption.Y := ALayout.PageTextPart.Y;
    el.Caption.AnchorH := tahCentre;
    el.Caption.AnchorV := tavMiddle;
    AList.Add(el);
    Inc(Result);
    DrawPagerIcon(ALayout.PageNext, ALayout.PageNextIndex >= 0, 1);
  end;
end;

end.
