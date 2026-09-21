unit tyControls.AdvanceChart;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the control the whole AdvChart layer exists under.

  WINDOWED, not graphic, and that decision was made on day one: focus, keyboard,
  an in-chart scrollbar, a dataZoom slider and a toolbox all need a handle, and
  retrofitting one onto a graphic control means rewriting every interaction it
  already had.

  CONFIGURED BY AN OPTION TREE, not by published properties. Roughly 1,950
  option paths do not fit in an Object Inspector, and an ECharts-shaped option
  makes ECharts' documentation, its gallery and a decade of answers on the
  internet usable as they are. Option is a string; everything else is derived.

  WHAT IT DRAWS TODAY. The pipeline runs end to end -- option to axes and
  coordinate systems, series bound to their axes, data read into columnar
  stores, value ranges unioned, labels measured and the plot rect shrunk to fit
  them -- and the AXIS DOMAIN is painted from the theme. Series marks are
  deliberately not here: twenty-three renderers are Tier 1, and the point of
  this control is that when they arrive they have a coordinate system, a style
  resolver and a paint list waiting rather than a blank file.

  EVERY VISUAL VALUE COMES FROM THE THEME. Eight typeKeys and four metrics, none
  of them a literal in this file. That is the library's hard rule and it is why
  the chart follows a skin instead of looking pasted onto one. }
interface
uses
  Classes, SysUtils, Math, Types, Controls, Graphics, LCLType,
  BGRABitmap,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.StyleModel,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Time,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
  tyControls.AdvChart.Measure, tyControls.AdvChart.Handlers,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Render,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Style,
  tyControls.AdvChart.Marks, tyControls.AdvChart.BarLayout,
  tyControls.AdvChart.Stack, tyControls.AdvChart.Symbol,
  tyControls.AdvChart.Pictorial,
  tyControls.AdvChart.Color,
  tyControls.AdvChart.Pie, tyControls.AdvChart.Funnel,
  tyControls.AdvChart.Gauge, tyControls.AdvChart.Radar,
  tyControls.AdvChart.Graph,
  tyControls.AdvChart.Title,
  tyControls.AdvChart.Labels, tyControls.AdvChart.LabelOpt,
  tyControls.AdvChart.PieLabel, tyControls.AdvChart.Legend,
  tyControls.AdvChart.Tooltip, tyControls.AdvChart.AxisPointer,
  tyControls.AdvChart.Dataset,
  fpjson, tyControls.SubPixel;

const
  { The four axis metrics, and the defaults to fall back on when a theme has not
    been loaded at all. The names are the theme's; the numbers match what the
    option model documents so a chart looks the same before and after a skin. }
  TyAdvChartTickLenVar = '--advchart-tick-length';
  TyAdvChartTickLen = 5;
  TyAdvChartMinorTickLenVar = '--advchart-minor-tick-length';
  TyAdvChartMinorTickLen = 3;
  TyAdvChartLabelMarginVar = '--advchart-label-margin';
  { THE TOOLTIP'S FOUR METRICS, and the count is part of the design for the
    same reason the axis' is: a skin author can check four numbers by eye
    across seventeen themes and cannot check forty. Everything else the box
    needs -- its fill, its border, its radius, its padding, both inks -- is a
    STYLE and comes from the two type keys, because that is what a theme
    already knows how to write.

    The values are upstream's own, in logical px at the 96-PPI baseline. The
    gap is the one number that is used twice: it is the distance from the
    cursor to the box AND the distance the box is flipped by when it would not
    fit, which is why it is one metric and not two. }
  TyAdvChartTooltipGapVar = '--advchart-tooltip-gap';
  TyAdvChartTooltipMarkerVar = '--advchart-tooltip-marker';
  TyAdvChartTooltipMarkerGapVar = '--advchart-tooltip-marker-gap';
  TyAdvChartTooltipGutterVar = '--advchart-tooltip-gutter';
  TyAdvChartTooltipGap = 20;
  TyAdvChartTooltipMarker = 10;
  { Upstream splits this across two declarations -- `margin-right: 4px` on the
    dot and `margin-left: 2px` on the name -- and they only ever appear
    together. }
  TyAdvChartTooltipMarkerGap = 6;
  TyAdvChartTooltipGutter = 20;
  { The axis pointer's label sits this far outside the plot, on the axis' own
    side. Upstream's `axisPointer.label.margin`, whose default is 3. }
  TyAdvChartAxisPointerMarginVar = '--advchart-axispointer-margin';
  TyAdvChartAxisPointerMargin = 3;
  TyAdvChartLabelMargin = 8;
  TyAdvChartNameGapVar = '--advchart-name-gap';
  TyAdvChartNameGap = 15;

type
  { ONE AXIS THE POINTER IS ON, and what it found there.

    NOT A DATUM. An axis trigger names a place on an axis, and the series that
    happen to be nearest it -- which can be none (a pointer with no tooltip),
    one, or several, and the several are not necessarily at the same row.

    Value and SnapValue are two answers on purpose. With `snap` off on a value
    axis the LINE sits under the cursor while the CONTENT describes the nearest
    data point, and upstream says so in as many words beside the branch that
    splits them. Collapsing the two is the bug that makes a non-snapping
    pointer describe whatever is under it rather than what it is near. }
  TTyAxisHit = record
    Axis: TTyAxis;
    { The plot the pointer is drawn across -- the OTHER axis' full extent. }
    Plot: TTyRectF;
    Spec: TTyAxisPointerSpec;
    { True for the second arm of a cross, which never triggers a tooltip. }
    Cross: Boolean;
    Value: Double;
    SnapValue: Double;
    { Binding slots and view rows, index-parallel, in the order the filter
      accepted them -- which is series order over the survivors, not over the
      option. }
    Slots: TTyIntegerArray;
    Rows: TTyIntegerArray;
  end;
  TTyAxisHitArray = array of TTyAxisHit;

  TTyAdvanceChart = class(TTyCustomControl)
  private
    FOption: TTyChartOption;
    FBuild: TTyChartBuild;
    FIndex: TTyAxisSeriesIndex;
    FBindings: TTySeriesBindingArray;
    FStores: array of TTyDataStore;
    { Every bar's width and offset, index-parallel to FBindings. Solved in
      Relayout rather than Rebuild because it needs the FINAL pixel extents:
      the plot rect is shrunk to fit the labels in phase C, and a band measured
      before that is the wrong width -- silently, since nothing raises and the
      bars merely come out slightly off. }
    FBarCols: TTyBarColumnArray;
    { Which series accumulate onto which, and into which columns. Solved in
      Rebuild, between filling the stores and sizing the axes: the totals have
      to exist before the value axis is asked how far it must reach. }
    FStacks: TTySeriesStackArray;
    { One entry per binding, meaningful only where the series is a pie.
      Solved in Relayout for the same reason FBarCols is: a pie centred on
      a percentage of its box needs the box in final pixels. }
    FPies: array of TTyPieLayout;
    { THE FUNNEL'S, kept apart from the pie's for the reason the pie's are kept
      apart from the bars': the solver runs once per layout and the builder is
      a pure unit that cannot re-read the option, so the answer has to be
      carried rather than recomputed. }
    FFunnels: array of TTyFunnelLayout;
    FFunnelSpecs: array of TTyFunnelSpec;
    { THE GAUGE'S, and it carries a third array the other two do not need: the
      per-datum title and reading. Those live in the series' own `data` and
      cannot come through the store's override table, which interns SCALAR
      leaves -- and `offsetCenter` is an array, which is exactly the one thing
      a multi-value gauge must set per datum. }
    FGauges: array of TTyGaugeLayout;
    FGaugeSpecs: array of TTyGaugeSpec;
    FGaugeItems: array of TTyGaugeItemArray;
    { ONE PER RADAR COMPONENT, not per series -- several series share a radar
      and its spokes are theirs jointly, which is the whole reason a radar is a
      coordinate system rather than a series' private geometry. }
    FRadars: array of TTyRadar;
    { ONE VIEW PER GRAPH SERIES, not one per component: a graph's coordinate
      system belongs to the series, so these are indexed by BINDING slot and
      most of them are nil. A graph on AXES has none either -- its coordinate
      system is the grid's -- and FGraphLaidOut is what says a slot holds a
      solved graph at all. }
    FGraphs: array of TTyGraphView;
    FGraphLaidOut: array of Boolean;
    FGraphSpecs: array of TTyGraphSpec;
    FGraphNodes: array of TTyGraphNodeArray;
    FGraphEdges: array of TTyGraphEdgeArray;
    FGraphCats: array of TTyGraphCategoryArray;
    { WHAT EACH FORCE LAYOUT LEFT FOR THE NEXT PASS, indexed by SERIES index
      rather than by slot, and kept OUTSIDE the build: every relayout throws
      the build away, and this is the one thing about a graph that has to
      outlive it. Cleared only when the option changes -- upstream keeps it on
      the series model, and a replaced option is new series models. }
    FGraphForce: array of TTyGraphForceState;
    FFilterCats: TTyGraphCategoryArray;
    { Which store column feeds spoke j, per series. Its own array because the
      store is exactly as wide as the first data row while the spokes come from
      the radar, and the two are allowed to disagree. }
    FRadarDims: array of TTyIntegerArray;
    { Index-parallel to FPies. The paint pass needs showEmptyCircle, and the
      mark builder is a pure unit that cannot re-read the option. }
    FPieSpecs: array of TTyPieSpec;
    { Every title the option carries, laid out. A title floats over the
      container and shrinks nothing, so this is solved beside the grids
      rather than before them. }
    FTitles: array of TTyTitleLayout;
    FTitleSpecs: array of TTyTitleSpec;
    { Every legend the option carries, in two halves. The ENTRIES and the
      SELECTION need nothing but the option and the stores, so they settle in
      Rebuild; the LAYOUT has to measure the words, so it waits for Relayout
      like the axes and the title. }
    FLegendSpecs: array of TTyLegendSpec;
    { Every name the chart offers a legend, kept past SolveLegendData because
      the graph's category filter asks upstream's isSelected -- which needs
      them -- for names no legend lists. }
    FLegendAvailable: TTyLegendNames;
    { Every graph's category colours, by SERIES index, solved once after the
      legend filter: the chip and the node read the same table, so they cannot
      disagree. }
    FGraphCatColours: TTyGraphCatColourTable;
    FLegendEntries: array of TTyLegendEntryArray;
    FLegendFlags: array of TTyLegendFlags;
    FLegends: array of TTyLegendLayout;
    { Whose rows KeepSlice is deciding about, for the length of one
      FilterSelf call and no longer. }
    FFilterStore: TTyDataStore;
    { The table each series reads, AS THAT SERIES READS IT -- so this is one
      per series and not one per dataset. Two series may read one table in
      two directions, and upstream builds two sources for exactly that
      reason. Index-parallel to FBindings. }
    FSources: array of TTyChartSource;
    { Which dataset each series reads, -1 for none, and what its columns
      mean. Both index-parallel to FBindings. }
    FSeriesDataset: array of Integer;
    FEncodes: array of TTySeriesEncode;
    { WHAT THE AUTHOR'S PALETTE GAVE EACH SERIES, resolved once per rebuild.
      Empty where they gave it nothing, and the theme's ramp answers instead
      -- so a chart with no `color` written is still the skin's chart, and one
      with `color` written is the author's. Index-parallel to the option's
      series SLOTS, not to FBindings: a series that did not resolve still
      takes its colour, because upstream's palette pass runs over the raw
      series and that is what keeps colours still across a legend click. }
    FSeriesColors: array of TTyChartColor;
    FSeriesColorKnown: array of Boolean;
    { AND THE PALETTE PICK ITSELF, kept apart from the resolved colour
      because `auto` resolves to the PICK and not to the fill. A series that
      writes `itemStyle: { color: '#fff', borderColor: 'auto' }` is white
      with a border in the palette colour -- so both numbers exist at once
      and one field could not hold them. }
    FSeriesPalette: array of TTyChartColor;
    FSeriesPaletteKnown: array of Boolean;
    FDirty: Boolean;
    FLastRect: TTyRectF;
    FOptionText: string;
    { THE STATIC LAYER. Everything whose appearance is decided by the model --
      frame, axes, grid, labels -- rendered once and blitted per frame.

      FStaticPPI is part of the key and TTyPaintCache is not: NeedsRender only
      notices a SIZE change, and a per-monitor DPI move can hand the same size
      at a different PPI. }
    FStatic: TTyPaintCache;
    FStaticPPI: Integer;
    { WHAT WAS DRAWN, KEPT. Every mark, wedge, label and legend entry of the
      last static render, with its shape, its z and the datum behind it.

      It used to be a local in PaintSeries, created and freed inside one call,
      which made the paint list's own hit test unreachable by anything but a
      test: by the time a pointer could ask what it was over, the answer had
      been freed. Keeping it costs one element record per mark and buys the
      only question a chart is ever asked interactively.

      VALID EXACTLY WHEN THE STATIC LAYER IS. Both are produced by the same
      pass over the same model at the same size, so one flag would do for both
      -- but TTyPaintCache owns its own, and a second boolean is cheaper than
      teaching the cache about a list it does not draw. DropStatic clears this
      one; the next build refills it.

      COORDINATES ARE LOCAL DEVICE px with the origin at (0,0) -- the space a
      MouseMove's X,Y arrives in. A render through RenderTo with a non-zero
      origin still fills it in local space, so a caller converting a point on
      that path has to subtract the origin itself. }
    { THE TOOLTIP. Nothing here is geometry the layout owns: the box is
      measured and placed inside the frame that draws it, because its anchor is
      the CURSOR and the cursor moves between frames. Upstream anchors the same
      way -- the raw offsetX/offsetY, never the snapped datum -- which is why
      the old TTyChart's "repaint only when the datum changes" gate cannot be
      carried over: a box that tracks the pointer would freeze between datums
      under it. }
    FTipDatum: TTyChartDatumRef;
    { AN AXIS TRIGGER HAS NO DATUM -- it has a place on an axis and whichever
      series happen to be nearest it. So the hover is two independent pieces of
      state, not one: an item hover names a row, an axis hover names a point,
      and a chart can legitimately have the second without the first (the
      pointer is over a gap between bars) or the first without the second (the
      tooltip is item-triggered).

      The axis hit itself is NOT stored. It is a handful of axes resolved from
      FTipX/FTipY, and re-resolving it in the frame that draws it is cheaper
      than keeping it correct across a rebuild -- which is the mistake the
      static layer's own history is a record of. }
    FTipHits: TTyAxisHitArray;
    { Whether the pointer's movement may drive the TOOLTIP. `triggerOn` is
      read once per move, as upstream reads it once into its listener closure,
      and it governs the box alone -- a chart set to `triggerOn: 'click'` still
      highlights what the pointer is over. }
    FTipTrack: Boolean;
    { The element the hit came from, kept because it carries the colour of the
      thing the pointer is over. Asking the series for its colour instead would
      be a second answer to a question the ink has already answered, and would
      miss a per-datum itemStyle. }
    FTipElement: Integer;
    FTipX, FTipY: Integer;
    FPaintList: TTyPaintList;
    { The PPI the list was built at. The hit test scales HitSlopLogical by it,
      so a list built for 96 and interrogated at 192 would give targets half
      the size the marks are drawn at. }
    FPaintListPPI: Integer;
    FPaintListValid: Boolean;
    procedure SetOptionText(const AValue: string);
    function GetOptionText: string;
    function GetErrorText: string;
    procedure FreeStores;
    procedure DropBuild;
    { Option to axes, series and stores. Cheap enough to redo on a resize; the
      expensive half is the label measuring in Relayout. }
    procedure Rebuild;
    { The half that needs a painter, because it has to MEASURE the labels before
      it can know how much room the plot has left. }
    procedure Relayout(APainter: TTyPainter; const ARect: TTyRectF;
      APPI: Integer; const AMeasurer: ITyTextMeasurer);
    { WHICH HALF OF AN AXIS TO DRAW.

      Everything an axis paints falls either UNDER the data or OVER it, and
      the split is not decorative: the grid belongs to the plot and the axis
      belongs to its edge. Upstream keeps them apart by z -- split lines and
      split areas sit below, the axis line carries `z2 = 1` above.

      The port had them interleaved per axis, which is the same picture
      while there is one axis of each family and wrong the moment there are
      two: the second y axis' split line lands on the first one's zero and
      rubs out the x axis line that `onZero` had just put there. }
    procedure PaintAxis(APainter: TTyPainter; AAxis: TTyAxis;
      const APlot: TTyRectF; APPI: Integer; AGrid: TTyGridBuild;
      const AMeasurer: ITyTextMeasurer; ABelow: Boolean);
    { THE TWO LAYERS, split by what makes them change rather than by what they
      look like. Static is everything the model decides; dynamic is what moves
      while the model stands still. }
    procedure PaintStatic(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer);
    { Every series' marks, in one list, ordered once. }
    procedure PaintSeries(APainter: TTyPainter;
      const AMeasurer: ITyTextMeasurer; APPI: Integer);
    { The theme colour for series ASeriesIndex, from the DERIVED ramp item 18
      landed: TyAdvChartSeries1..8, all of them computed from --accent so a skin
      that restyles the accent gets a matching chart for nothing. }
    procedure SolveSeriesColors;
    { The THEME's ramp at ASlot, with nothing of the option in it. Split out
      because a pie's slices and a chart's series both cycle it, and they
      index it by different things. }
    function ThemeRampColor(ASlot: Integer): TTyColor;
    { What `auto` means on this series: the palette's pick for it. }
    function SeriesPaletteColor(ASeriesIndex: Integer): TTyColor;
    { What the author wrote on this series' style blocks, laid over the
      palette colour the visual already carries. }
    procedure ApplyOptStyle(var AVisual: TTySeriesVisual; ASlot: Integer);
    function SeriesColor(ASeriesIndex: Integer): TTyColor;
    { The stack record for a series slot, or an unstacked one. }
    function StackFor(ASlot: Integer): TTySeriesStack;
    { The symbol spec for a series slot, over its type's own default. }
    function SymbolFor(ASlot: Integer): TTySymbolSpec;
    function SeriesIntIn(ASeriesIndex: Integer; const AKey: string;
      ADefault: Integer): Integer;
    { The label interval the layout gave this axis, or 1 when it draws them
      all. }
    function LabelStepFor(AAxis: TTyAxis): Integer;
    { Every pie series laid out. Runs in Relayout, after phase C, for the
      same reason the bar solver does: a percentage of a box needs the box
      in final pixels. }
    procedure SolvePies;
    { Every title, measured and placed. Needs the measurer, so it runs in
      Relayout beside the axis pass rather than in Rebuild. }
    procedure SolveTitles(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    { The two title fonts, resolved from the theme. }
    function TitleFont(const AKey: string): TTyTitleFont;
    procedure PaintTitles(APainter: TTyPainter);
    { One colour per SECTOR, not one per series: a pie is colorBy:data. }
    function PieVisual(ASlot: Integer): TTyPieVisual;
    { ONE COLOUR PER RAW ROW, in raw order, for a series that colours by datum.

      RAW and not view: a row dropped by a filter -- a negative value, a legend
      click -- still consumes its slot, which is the only thing that keeps the
      survivors on the colours they had. Upstream iterates its unfiltered data
      here for the same reason and says so in a comment.

      Shared because a pie and a funnel want the identical answer, and the one
      thing worse than two implementations of a palette is two implementations
      that agree today. }
    function PerDatumColours(ASlot: Integer): TTyChartColorArray;
    { Every funnel's geometry. Runs in Relayout, beside SolvePies. }
    procedure SolveFunnels;
    function FunnelVisual(ASlot: Integer): TTyFunnelVisual;
    { Every gauge's geometry. Runs in Relayout, beside SolvePies. }
    procedure SolveGauges(APPI: Integer);
    function GaugeVisual(ASlot: Integer): TTyGaugeVisual;
    { Every radar's geometry AND every spoke's value range. Both, because the
      two halves are one answer: the range of a spoke is the union over every
      series bound to that radar, which nothing else in this control is in a
      position to collect. }
    procedure SolveRadars(APPI: Integer);
    procedure FreeRadars;
    procedure SolveGraphs(APPI: Integer);
    procedure FreeGraphs;
    procedure SolveGraphCategoryColours;
    { A graph node's raw row survives the legend: upstream's categoryFilter,
      with isSelected asked of every legend. FFilterCats carries the
      categories the predicate needs. }
    function KeepGraphNode(ARawIndex: Integer): Boolean;
    function GraphInk(ASlot: Integer): TTyGraphInk;
    { What upstream's getName calls node ANode of the graph in ASlot -- its
      own name, or its category on a category axis. '' when there is none. }
    function GraphNodeName(ASlot, ANode: Integer): string;
    function RadarInk: TTyRadarInk;
    function RadarVisual(ASlot: Integer): TTyRadarVisual;
    function FunnelLabelInk: TTyFunnelLabelInk;
    { The label spec for one series, resolved from the theme and the option.
      ADefaultFormatter is the series type's own `label.formatter` default,
      which an option can override and -- with null -- remove. }
    function LabelSpecFor(ASlot: Integer): TTyLabelSpec; overload;
    function LabelSpecFor(ASlot: Integer;
      const ADefaultFormatter: string): TTyLabelSpec; overload;
    { The fonts and the four inks a pie label is drawn with. }
    function PieLabelInk: TTyPieLabelInk;
    { `series.name`, which is what `{a}` in a label formatter means -- and,
      for a series that named itself nothing and reads a dataset, the name
      of the dimension it took its values from. }
    function SeriesNameOf(ASlot: Integer): string;
    { The two name lists a legend needs: what it falls back to when the
      option lists no `data`, and what it is allowed to match. They are not
      the same list -- see the body. }
    procedure LegendNames(out APotential, AAvailable: TTyLegendNames);
    { `series.symbol` as written, '' when the option did not name one. What
      the legend makes of it is the legend's business. }
    function SeriesSymbolWord(ASlot: Integer): string;
    { What the chart can say about each of a legend's names. }
    function LegendSources(const AEntries: TTyLegendEntryArray):
      TTyLegendSourceArray;
    { Specs, entries and selection. Runs in Rebuild. }
    procedure SolveLegendData;
    { What the selection MEANS: the series a legend has switched off stop
      being counted, and the pie slices it has switched off leave the
      store. Runs in Rebuild, immediately after SolveLegendData. }
    procedure ApplyLegendFilter;
    { True when ANY legend has switched this name off. }
    function LegendHides(const AName: string): Boolean;
    { The predicate FilterSelf calls, against FFilterStore. A method
      pointer cannot carry an argument, so the store it is filtering rides
      on the field -- which is why the field exists and why it is cleared
      the moment the call returns. }
    function KeepSlice(ARawIndex: Integer): Boolean;
    { Every legend, measured and placed. Runs in Relayout. }
    procedure SolveLegends(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    function LegendFont: TTyLegendFont;
    function LegendInk: TTyLegendInk;
    { The four colours a candle falls back on, from the theme, with whatever
      the option wrote laid over them. }
    function CandleVisual(ASlot: Integer): TTyCandleSpec;
    { An axis' dimension name, '' for no axis. }
    function AxisDimOf(AAxis: TTyAxis): string;
    { Rewrite ADims for a series type that declares more than one value per
      datum. A no-op for every other type. }
    procedure MultiValueDims(const ABinding: TTySeriesBinding;
      var ADims: TTySeriesDimArray);
    { The legend's elements, into the chart's own paint list. }
    function BuildLegends(APPI: Integer; AList: TTyPaintList): Integer;
    { Every series' elements into FPaintList, and nothing drawn. Separate from
      PaintSeries because the list is the answer to "what is under the pointer"
      as much as it is the instruction for "what to draw", and only one of
      those two needs a painter -- this half never touches one. Returns how
      many elements the builders reported adding. }
    function BuildSeriesList(const AMeasurer: ITyTextMeasurer;
      APPI: Integer): Integer;
    { The binding slot holding a given series index, or -1. FBindings is
      index-parallel to the option's series array only while nothing failed to
      resolve, and a hole makes the two disagree. }
    function SlotOfSeries(ASeriesIndex: Integer): Integer;
    { Which row of a series a point is over, asked of the BASE axis.

      For a run element -- a polyline, which is one element for a whole series
      and therefore carries no row of its own. The pointer is already known to
      be on the line; this only names which datum it is nearest, by inverting
      the base axis and then walking the store for the closest value. -1 when
      the series has no base axis, no store, or no column for it. }
    function NearestRowOn(ASlot: Integer; AX, AY: Double): Integer;
    { The rows of one series nearest a value ON THIS AXIS, measured in VIEW
      COORDINATE space. Answers every row tied at the minimum. }
    function NearestOnAxis(ASlot: Integer; AAxis: TTyAxis; AValue: Double;
      AMaxDistPx: Double; out ARows: TTyIntegerArray): Boolean;
    procedure PaintAxisPointers(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer;
      const AHits: TTyAxisHitArray);
    { What the hovered element looks like while it is hovered, drawn OVER the
      copy the static layer already holds. }
    procedure PaintEmphasis(APainter: TTyPainter; APPI: Integer;
      const AHits: TTyAxisHitArray);
    { One element, lifted. False when this series has emphasis switched off or
      the element is not one that can be lifted. }
    function EmphasiseElement(AIndex: Integer; APPI: Integer;
      out AElement: TTyChartElement): Boolean;
    { Every value of one datum as one string. Several go on ONE row joined by
      two spaces, which is upstream's richText spelling of the list html joins
      with two non-breaking spaces -- and it is the branch a candlestick
      always takes. The sub-row form, a small dot per dimension on its own
      line, is the other branch and is not built yet. }
    function ValuesText(const AParams: TTyChartCallbackParams): string;
    { The colour of the thing a datum was drawn as, taken from the element
      that drew it. Asks the paint list rather than the series so a per-datum
      itemStyle comes for free and the dot can never disagree with the mark it
      names. Takes the datum rather than reading the hover, so the content
      functions depend on their argument and nothing else -- a content rule
      that only holds while a pointer is down is a rule no test can read. }
    function DatumColour(const ADatum: TTyChartDatumRef): TTyChartColor;
    procedure PaintTooltip(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer);
    procedure PaintDynamic(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer);
    { Whether the dynamic layer would draw anything. False skips a whole
      painter -- a BGRA bitmap the size of the control, filled, blitted and
      freed -- which is most of a frame when there is nothing moving. }
    function HasDynamicContent: Boolean;
    procedure DropStatic;
  protected
    { Every surviving series as a formatter would see it, in section order --
      so `{a0}` is the first row of the first section. }
    function AxisTooltipParams(const AHits: TTyAxisHitArray): TTyChartParams;
    { The elements the last render built, series and labels -- the list the
      hit test walks and the painter draws, read-only. }
    property SeriesList: TTyPaintList read FPaintList;
    function GetStyleTypeKey: string; override;
    procedure Resize; override;
    { Protected and non-virtual, exactly as every other control in the library:
      a headless test renders through it onto an offscreen bitmap, and it
      bypasses the on-screen paint path entirely. }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The layered path: the static cache blitted, then the dynamic layer over
      it. Separate from RenderTo because RenderTo is what an export and a
      headless test want -- everything, unconditionally, onto the canvas they
      named. This one is what a WINDOW wants, and works in client space:
      TTyPaintCache.Blit draws at the canvas origin. }
    procedure RenderCached(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { THE POINTER MOVED, AND THE PICTURE DID NOT. Hover, press, release and
      focus all arrive here; the base class answers them with Invalidate, and
      this control's Invalidate rebuilds the stores, re-measures every label
      and throws away the static bitmap.

      Nothing in this class reads FHover or FPressed and nothing resolves a
      hover style, so those five repaints were redrawing the identical picture
      at the cost of a full rebuild each -- and a hover session begins with
      exactly that. InvalidateFrame keeps the cache and blits it again. }
    { EVERY AXIS THE POINTER IS CURRENTLY ON, with what each one says.

      Plural because a chart can have several grids, a grid several cartesians,
      and a cross puts a pointer on both arms. Upstream dedupes base axes
      across a grid -- the x-by-y cross product yields the same axis more than
      once -- and so does this. }
    function ResolveAxisPointers(AX, AY: Integer): TTyAxisHitArray;
    { The three-layer tree an axis tooltip is: a headerless root, one section
      per axis headed by its value, one row per series. nil when nothing
      survived the filters. }
    function AxisTooltipContent(const AHits: TTyAxisHitArray;
      const ASpec: TTyTooltipSpec): TTyTooltipBlock;
    { How a value reads under an axis pointer or at the head of its tooltip:
      upstream's getValueLabel -- the category, the time label, or the number
      as IntervalScale.getLabel prints it to the label's precision ('auto'
      unless written: the step's decimals plus two, padded, so 3.00), with
      the label's string formatter over it. }
    function AxisValueText(AAxis: TTyAxis; AValue: Double;
      const ALabel: TTyAxisPointerLabelSpec): string;
    { Where a pointer stands for AValue: inside the scale's extent, which
      upstream's fixValue clamps it to before the line or the label is drawn
      -- a row past a written max puts the pointer on the max. An interval
      scale only; a category pointer is always on a category. }
    function PointerAt(AAxis: TTyAxis; AValue: Double): Double;
    { The value a pointer stands at, line and label alike: the snapped row
      with snap on, the cursor with it off, clamped by PointerAt. The tooltip
      header is not this -- it always describes the snapped row. }
    function PointerValue(const AHit: TTyAxisHit): Double;
    { WHAT THE TOOLTIP WOULD SAY, in four answerable pieces rather than one
      procedure that draws. PROTECTED for the same reason RenderTo is: a
      headless test has no window and no pointer, and a content rule tested
      only by counting pixels is a content rule nobody can read.

      The tooltip as the OPTION says it, with the cascade resolved for one
      datum: the data item's own tooltip, then the series', then the global. }
    function TooltipSpecFor(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
    { And as the THEME says it. }
    function TooltipInk(const ASpec: TTyTooltipSpec): TTyTooltipInk;
    { The default content tree for one datum, or nil when there is nothing to
      say. The caller owns it. }
    function TooltipContent(const ADatum: TTyChartDatumRef;
      const ASpec: TTyTooltipSpec): TTyTooltipBlock;
    { hit -> the record a formatter is given. }
    function TooltipParams(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
    procedure PointerStateChanged; override;
    { WHERE THE POINTER IS, every pixel of the way. The tooltip's anchor is the
      cursor, so this repaints on movement and not only when the datum under it
      changes -- the frame it asks for is a blit of the static layer plus one
      box, which is what the cache exists to make affordable. }
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
    { REPAINT WITHOUT REBUILDING. Invalidate means "the model may have moved":
      it rebuilds, re-measures and re-renders the static layer, because a theme
      change arrives as a bare Invalidate and there is no StyleChanged hook to
      tell the two apart. This one means "the same model, one frame on" -- the
      static layer is kept and only the dynamic layer is redrawn.

      An animation tick calls this. Calling Invalidate instead would rebuild the
      stores and re-measure every label sixty times a second, which is the
      difference between a frame costing a blit and a frame costing 51 ms. }
    procedure InvalidateFrame;
    { Everything the option said that could not be honoured -- a misspelled axis
      type, a series naming an axis that does not exist. A chart that silently
      drops what it cannot draw is a chart that lies, so these are readable
      rather than logged and forgotten. }
    function DiagnosticCount: Integer;
    function Diagnostic(AIndex: Integer): string;
    { Draw the chart to a PNG at its current size.

      A chart is a thing people put in reports, so exporting one is an ordinary
      feature rather than test scaffolding -- and it renders through the same
      RenderTo the screen uses, so what is saved is what was shown. Deliberately
      NOT a form-image grab: capturing a windowed control that way returns black
      on some widgetsets, which this library has already been caught by. }
    procedure SaveToPng(const AFileName: string);
    { WHAT THE POINTER IS OVER, in the control's own coordinates.

      The chart's first interactive question, and the first production caller
      the paint list's hit test has ever had. Answers TyChartNoDatum for a
      point over nothing, over decoration, or before the first render.

      ONE HIT TEST, NOT TWO. The walk itself is TTyPaintList's -- reverse paint
      order, silent elements skipped, slop scaled by PPI -- so the element a
      caller would highlight and the datum reported here can never be two
      different things. What this adds is the one thing the list cannot know:
      a LINE's stroke is a single element for a whole series and carries no
      row, so a hit on it is resolved against the base axis instead of being
      reported as the half-valid `(series, -1)` the list holds.

      LOCAL COORDINATES, origin (0, 0) -- what MouseMove is handed. After a
      RenderTo onto a rect with a non-zero origin the list is still in local
      space, so subtract that origin first. }
    function HitTestAt(AX, AY: Integer): TTyChartDatumRef; overload;
    { The same walk, also answering WHICH element replied -- which is how a
      caller gets at the colour of the thing under the pointer without asking
      the series a second time and risking a different answer. -1 for none. }
    function HitTestAt(AX, AY: Integer;
      out AElement: Integer): TTyChartDatumRef; overload;
    { For a test or a designer to look inside. nil until the first build. }
    property Build: TTyChartBuild read FBuild;
    { THE GRAPH SERIES ASeriesIndex, AS THE LAST RENDER LAID IT OUT: the nodes
      the legend kept -- in the order they were written, with their pixel
      positions -- the edges between them, and each node's fill. False when
      that series is not a laid-out graph -- on a view or on axes -- or
      nothing has been rendered. Read-only, and what a host needs to put
      something over a node. }
    function GraphLayout(ASeriesIndex: Integer; out ANodes: TTyGraphNodeArray;
      out AEdges: TTyGraphEdgeArray; out AFills: TTyChartColorArray): Boolean;
    { THE SAME GRAPH'S INK AND SPEC, which is what TyGraphEdgeStroke needs to
      say what colour each edge is drawn in. }
    function GraphInkOf(ASeriesIndex: Integer; out AInk: TTyGraphInk;
      out ASpec: TTyGraphSpec): Boolean;
    { The legends as the last render placed them. }
    function LegendLayoutCount: Integer;
    function LegendLayout(AIndex: Integer): TTyLegendLayout;
  published
    { THE API. Relaxed JSON: unquoted keys, single quotes, trailing commas and
      comments all parse, because that is what an ECharts config in the wild
      looks like.

      A REJECTED OPTION LEAVES NO CHART. The earlier rule kept the last one
      that parsed, reasoning that a half-typed config in a design-time editor
      must not blank the chart -- but the editor that got built is a modal
      dialog writing back on OK, and the Object Inspector commits once too, so
      half-typed text never arrives here. What that rule left instead was a
      control that lies: the property says A, the picture shows B, and nothing
      on screen says why. OptionError carries the reason. }
    property Option: string read GetOptionText write SetOptionText;
    { Empty when the last option parsed. }
    property OptionError: string read GetErrorText;
    property Align;
    property Anchors;
    property BorderSpacing;
    property Color;
    property Font;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property TabOrder;
    { NOT a tab stop today, and the declaration has to say so or a .lfm cannot
      stream the choice: the streamer omits a value that equals the declared
      default, so a mismatched pair silently loses whatever the host wrote.
      A chart with no keyboard behaviour that took focus on click would pull it
      off whatever the user was editing and then do nothing with it. Being
      WINDOWED is what makes focus possible later; it is not a reason to take it
      now. When dataZoom, brush or a keyboard tooltip land, this flips to True
      and the class moves to the focusable table -- which the tables in
      test.focus.tabstop.pas will force somebody to decide rather than drift. }
    property TabStop default False;
    property Visible;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
  end;

implementation

uses
  tyControls.Controller,
  { Only for the diagnostic resourcestrings -- the same one-way dependency the
    rest of the AdvChart family keeps, invisible to a host. }
  tyControls.StrConsts;

{ ==================== construction ==================== }

constructor TTyAdvanceChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOption := TTyChartOption.Create;
  FIndex := TTyAxisSeriesIndex.Create;
  FDirty := True;
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  Width := 320;
  Height := 200;
  TabStop := False;   { see the published declaration }
end;

destructor TTyAdvanceChart.Destroy;
begin
  { Order is a contract, not a habit: a store BORROWS its category list from an
    axis the build owns, so every store goes first. }
  DropBuild;
  FreeAndNil(FPaintList);
  FreeAndNil(FIndex);
  FreeAndNil(FOption);
  { The static layer owns a TBitmap. TTyPaintCache.Drop only marks it stale --
    it keeps the surface deliberately, for reuse -- so dropping is not freeing. }
  FreeAndNil(FStatic);
  inherited Destroy;
end;

procedure TTyAdvanceChart.FreeStores;
var i: Integer;
begin
  for i := 0 to High(FStores) do
    FStores[i].Free;
  FStores := nil;
  FBarCols := nil;
  FStacks := nil;
end;

procedure TTyAdvanceChart.DropBuild;
begin
  { THE AXIS HOVER GOES FIRST, because it holds TTyAxis POINTERS into the build
    about to be freed. Invalidate clears it too, but Resize sets FDirty without
    going through Invalidate -- so the one place that can be trusted to clear
    it is the one that does the freeing. }
  FTipHits := nil;
  { AND THE RADARS WITH THEM, for the same reason: a binding holds a radar's
    INDEX, and the spoke objects a paint list was built against are about to
    stop existing. }
  FreeRadars;
  FreeGraphs;
  FRadarDims := nil;
  FreeStores;
  FBindings := nil;
  if FIndex <> nil then FIndex.Clear;
  FreeAndNil(FBuild);
end;

{ ==================== the option ==================== }

{ WHAT WAS WRITTEN, not what parsed. The PROPERTY has to read back what the
  host set, or a half-typed option in the Object Inspector reverts on every
  keystroke that does not yet parse, and a .lfm cannot round-trip work in
  progress.

  The TREE is emptied when the text does not parse -- there is no last-good-one
  kept, deliberately: a control whose property says A while the picture shows B
  has no way to tell anyone which is which. OptionError says what went wrong. }
function TTyAdvanceChart.GetOptionText: string;
begin
  Result := FOptionText;
end;

procedure TTyAdvanceChart.SetOptionText(const AValue: string);
begin
  if FOptionText = AValue then Exit;
  FOptionText := AValue;
  FOption.SetOptionText(AValue);
  FGraphForce := nil;
  FDirty := True;
  Invalidate;
end;

function TTyAdvanceChart.GetErrorText: string;
begin
  Result := FOption.Error.Message;
end;

function TTyAdvanceChart.DiagnosticCount: Integer;
begin
  if FBuild = nil then Exit(0);
  Result := FBuild.DiagnosticCount;
end;

function TTyAdvanceChart.Diagnostic(AIndex: Integer): string;
begin
  if FBuild = nil then Exit('');
  Result := FBuild.Diagnostic(AIndex);
end;

{ ==================== style ==================== }

function TTyAdvanceChart.GetStyleTypeKey: string;
begin
  { Its own key, never borrowed. A control that answers another control's key
    can never be reached by a theme that wants to restyle only this one. }
  Result := 'TyAdvChart';
end;

procedure TTyAdvanceChart.Invalidate;
begin
  { A theme change arrives as a plain Invalidate broadcast and nothing else --
    the controller says so in as many words, and there is no StyleChanged hook
    to override. So every invalidate is treated as a relayout: the axis extents
    would not move, but the label FONT may have, and the plot rect is measured
    from the labels. Cheaper to redo than to be wrong about, and a chart is not
    invalidated on mouse movement. }
  FDirty := True;
  { AND THE HOVER GOES WITH IT. Invalidate means the model may have moved, and
    a hovered datum is a pair of subscripts into a build that is about to be
    thrown away -- the row it names may not exist in the next one. Upstream
    re-shows the tooltip after a setOption while the pointer is still there;
    here the next movement re-establishes it, which is a real difference and a
    small one, and the alternative is a box describing a bar nobody can see. }
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  { THE AXIS HOVER IS NOT CLEARED HERE, and deliberately not: every Invalidate
    sets FDirty, every FDirty relayouts, and every relayout rebuilds -- so
    DropBuild has already been reached by the time anything could read the
    hits again, and it clears them because it is the thing that frees what
    they point at. A second clear here would be a line no test could fail
    against, which is a line that gets deleted by somebody who cannot tell
    whether it matters. }
  { AND THE STATIC LAYER GOES. It holds a picture drawn in the theme's font at
    the theme's colours; the whole reason this method treats every invalidate
    as a relayout is that a theme change arrives as a bare Invalidate, and a
    kept cache would blit the old theme over the new one. }
  DropStatic;
  inherited Invalidate;
end;

procedure TTyAdvanceChart.InvalidateFrame;
begin
  { The static layer is KEPT -- see the declaration. This is the repaint an
    animation tick asks for: same model, same layout, same axes, one frame on. }
  inherited Invalidate;
end;

procedure TTyAdvanceChart.Resize;
begin
  inherited Resize;
  FDirty := True;
end;

{ ==================== the pipeline ==================== }

procedure TTyAdvanceChart.Rebuild;
var
  i, j, k, ds, cur: Integer;
  dims: TTySeriesDimArray;
  st: TTyDataStore;
  coord: TTyCoordDimArray;
  cursors: TTyEncodeCursorArray;
  enc: TTySeriesEncode;
  typeInfo: TTySeriesTypeInfo;
  radarSpec: TTyRadarSpec;
begin
  DropBuild;
  FBuild := TyBuildGrids(FOption, FLastRect);
  FBindings := TyBindSeries(FOption, FBuild);
  { A TYPE THAT RESOLVED AND STILL DRAWS NOTHING HAS TO SAY SO. Binding knows
    the twenty-three names ECharts ships and says nothing about which of them
    this control can paint, so a `funnel` bound cleanly, laid out cleanly and
    came out blank with no diagnostic at all -- which is the one thing the
    control is not allowed to do. Said HERE rather than in the binder because
    the binder cannot see the renderer table: the unit that owns it uses the
    binder, and a second copy of the list over there is a second thing that
    drifts. }
  for i := 0 to High(FBindings) do
    if FBindings[i].Resolved and (FBindings[i].SeriesType <> '')
      and not TySeriesTypeHasRenderer(FBindings[i].SeriesType) then
      FBuild.Note(Format(rsTyChartSeriesNoRenderer,
        [FBindings[i].SeriesIndex, FBindings[i].SeriesType]));
  SetLength(FStores, Length(FBindings));
  SetLength(FSources, Length(FBindings));
  SetLength(FSeriesDataset, Length(FBindings));
  SetLength(FEncodes, Length(FBindings));
  cursors := nil;
  for i := 0 to High(FBindings) do
  begin
    st := TTyDataStore.Create;
    FStores[i] := st;
    { WHICH TABLE, IF ANY. A series with its own `data` reads that and nothing
      else -- the table is there for the series that did not bring any. }
    FSeriesDataset[i] := TySeriesDatasetIndex(FOption, FBindings[i].SeriesIndex);
    if FSeriesDataset[i] >= 0 then
    begin
      FSources[i] := TySourceOf(FOption, FSeriesDataset[i],
        FBindings[i].SeriesIndex);
      if not FSources[i].Valid then FSeriesDataset[i] := -1;
    end;
    if not FBindings[i].HasAxes then
    begin
      { A SERIES OFF EVERY COORDINATE SYSTEM HAS DATA TOO, and until now
        only a pie got any: the columns below are the coordinate system's
        dimensions, and a series without a coordinate system has none, so
        the store stayed empty and the `data` array was never read. One
        float column, named the way ECharts names the dimension, and
        TyFillSeriesStore does the rest -- it already unwraps
        `{ value, name }`, records the name and collects the per-item
        overrides.

        THE TEST IS THE USAGE, NOT THE TYPE NAME. It read `= 'pie'` while
        the registry had said `scuBox` about a funnel and a gauge since the
        day it was written -- so both of them reached here, matched nothing,
        and left with a store of zero columns and zero rows. Nothing raised;
        their layout simply found no value dimension and drew nothing, which
        is indistinguishable from a type with no renderer. }
      { A RADAR SERIES IS NOT ON NO COORDINATE SYSTEM -- it is on one whose
        axes are spokes, and HasAxes says only that the cartesian pair is
        absent. One float column per indicator, named the way the coordinate
        system names its dimensions, and the store's own default of "column j
        takes element j of the row" is exactly a radar row. }
      if FBindings[i].RadarIndex >= 0 then
      begin
        radarSpec := TyRadarSpecOf(FOption, FBindings[i].RadarIndex);
        SetLength(dims, Length(radarSpec.Indicators));
        for j := 0 to High(dims) do
        begin
          st.AddDimension(TyRadarDimPrefix + IntToStr(j), ddtFloat);
          dims[j] := Default(TTySeriesDim);
          dims[j].Name := TyRadarDimPrefix + IntToStr(j);
          dims[j].Kind := ddtFloat;
        end;
        if Length(dims) > 0 then TyFillSeriesStore(FOption, i, dims, st);
        Continue;
      end;
      { A GRAPH IS NOT ON NO COORDINATE SYSTEM EITHER -- it is on a view, whose
        axes do not exist rather than being spokes -- and it is NOT scuBox:
        its usage says `data` because its nodes are data. So it matched
        neither branch and left with a store of no columns and no rows,
        which is the very failure the paragraph above records for the funnel
        and the gauge. The same trap, the third time.

        THE GRAPH UNIT BUILDS IT, the one way the suite builds it too: one
        value column, read from `data` or from `nodes`, its second name.
        A graph on AXES is not here at all -- it has the axes' columns, below. }
      if FBindings[i].SeriesType = TyGraphSeriesTypeName then
      begin
        TyGraphFillStore(FOption, i, st);
        Continue;
      end;
      if TySeriesFindType(FBindings[i].SeriesType, typeInfo)
        and (typeInfo.Usage = scuBox) and (Length(typeInfo.Dims) > 0) then
      begin
        st.AddDimension(typeInfo.Dims[0], ddtFloat);
        SetLength(dims, 1);
        dims[0].Name := typeInfo.Dims[0];
        dims[0].Kind := ddtFloat;
        dims[0].Axis := nil;
        ds := FSeriesDataset[i];
        if ds >= 0 then
        begin
          { A PIE NAMES ITS DATA RATHER THAN PLOTTING IT, so its default
            encode is the other one: a NAME dimension and a VALUE dimension,
            guessed from the table rather than counted off it. }
          SetLength(coord, 1);
          coord[0].Name := typeInfo.Dims[0];
          coord[0].Ordinal := False;
          enc := TyEncodeOf(FOption, FBindings[i].SeriesIndex,
            FSources[i], coord);
          if not enc.Given then
            enc := TyDefaultEncodeNameBased(FSources[i],
              FSources[i].DimCount);
          FEncodes[i] := enc;
          TyFillStoreFromSource(FSources[i], enc, dims, st);
        end
        else
          TyFillSeriesStore(FOption, i, dims, st);
      end;
      Continue;
    end;
    dims := TySeriesCartesianDims(FBindings[i].Cart, 0);
    { A SERIES WHOSE TYPE DECLARES MORE THAN A PAIR gets those columns
      instead. A candlestick is four numbers on ONE axis and a category that
      is nowhere in the row at all; a coordinate-per-column store cannot hold
      it, and the two-column version quietly kept the closes and threw the
      other three away. The axis then sized itself from a quarter of its own
      data and the renderer found no columns to read. }
    MultiValueDims(FBindings[i], dims);
    for k := 0 to High(dims) do
    begin
      st.AddDimension(dims[k].Name, dims[k].Kind);
      { WHICH COORDINATE THIS COLUMN FEEDS. Only ever different from its own
        name for a multi-value series, and only that series' extent pass and
        tooltip look at it. }
      if dims[k].Coord <> '' then st.SetDimCoord(k, dims[k].Coord);
      { The axis owns the category list and every series on it borrows the SAME
        one -- that sharing is what makes two series agree about which name
        ordinal 0 is. }
      if dims[k].Axis <> nil then st.UseOrdinalMeta(k, dims[k].Axis.Categories);
    end;
    { A GRAPH ON AXES FILLS THE AXES' COLUMNS THE GRAPH'S WAY: `data` or
      `nodes`, the series' own `category` filed into every silent node, and
      never a dataset -- upstream builds a graph's nodes from its own option
      whatever tables the chart carries. The columns are the ones every other
      series here gets, which is what upstream does too: a bare number on a
      category axis is its row and its value, and the axes size themselves
      from these like from anything else. }
    if FBindings[i].SeriesType = TyGraphSeriesTypeName then
    begin
      TyGraphFillNodes(FOption, i, dims, st);
      Continue;
    end;
    ds := FSeriesDataset[i];
    if ds < 0 then
    begin
      TyFillSeriesStore(FOption, i, dims, st);
      Continue;
    end;
    { THE COORDINATES, AS THE ENCODE RULES SEE THEM: a name and whether the
      axis under it is a category one. The second is what chooses between the
      two ways of handing a table out, and it is not the same question as
      which axis is horizontal. }
    SetLength(coord, Length(dims));
    for k := 0 to High(dims) do
    begin
      coord[k].Name := dims[k].Name;
      coord[k].Ordinal := dims[k].Kind = ddtOrdinal;
    end;
    enc := TyEncodeOf(FOption, FBindings[i].SeriesIndex, FSources[i], coord);
    { THE CURSOR IS SHARED AND IT ADVANCES, which is why this has to happen
      inside the one loop that walks the series in order. Three bars on one
      table take columns 1, 2 and 3 because the second and third ask the same
      counter the first one moved. A series that brought its own encode --
      even a partial one -- does not ask, and so does not move it. }
    if not enc.Given then
    begin
      { THE INDEX FIRST, THEN THE SUBSCRIPT. `cursors[F(cursors)]` where F may
        SetLength is the repository's own recorded footgun: FPC takes the
        array's address before it evaluates the index, so a reallocation
        inside F leaves the write going to freed memory. }
      cur := TyEncodeCursorFor(cursors, ds, FSources[i].LayoutBy);
      enc := TyDefaultEncodeAxis(cursors[cur], coord);
    end;
    FEncodes[i] := enc;
    TyFillStoreFromSource(FSources[i], enc, dims, st);
    Continue;
  end;
  { AFTER THE STORES AND BEFORE EVERYTHING THAT COUNTS. A pie legend names
    DATA ITEMS, so the names have to be in the store before the legend can
    list them; and the filter the legend implies has to be in place before
    the index, the stacks and the extents, or a switched-off series would go
    on widening the axis it is not drawn on.

    This is upstream's order too, by its priorities: legendFilter is
    SERIES_FILTER (800), the stack pass is 900 and the axis statistics are
    920, with a comment at echarts.ts:163-165 saying the statistics must come
    after the filter for exactly this reason. Nothing here measures text, so
    none of it has to wait for Relayout. }
  SolveLegendData;
  ApplyLegendFilter;
  { AFTER the filter, because a graph the legend switched off takes no slot of
    the shared category palette -- upstream's categoryVisual walks only the
    series the filter kept. }
  SolveGraphCategoryColours;
  { AFTER the filter but over EVERY series slot, hidden ones included --
    see SolveSeriesColors. The two are not in tension: the filter decides
    what is drawn, the palette decides what colour each series IS, and the
    second must not depend on the first or a legend click would repaint
    the whole chart. }
  SolveSeriesColors;
  TyIndexSeries(FBindings, FIndex);
  { BEFORE THE EXTENTS, and that order is the whole point: a stacked chart
    whose axis was sized from the raw values draws off the top of its plot. }
  FStacks := TySolveStacks(FOption, FBindings, FStores);
  TyApplyAxisExtents(FOption, FBuild, FBindings, FStores, FStacks, FIndex);
end;

procedure TTyAdvanceChart.Relayout(APainter: TTyPainter; const ARect: TTyRectF;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  txt: TTyAxisTextStyle;
  labelS: TTyStyleSet;
begin
  FLastRect := ARect;
  Rebuild;
  { The layout pass measures the labels the PAINT pass will draw, so it has to
    be handed the same font and the same gaps. Resolving them here rather than
    inside the builder keeps that unit free of the controller, which is the
    whole reason the measurer is injected too. }
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  txt := Default(TTyAxisTextStyle);
  txt.FontName := labelS.FontName;
  txt.FontSizeLogical := ResolveFontSize(labelS);
  txt.FontWeight := labelS.FontWeight;
  txt.EmphasisFontWeight := ActiveController.Model.ResolveStyle(
    'TyAdvChartAxisLabelPrimary', '', []).FontWeight;
  txt.LabelMarginLogical := ActiveController.Metric(TyAdvChartLabelMarginVar,
    TyAdvChartLabelMargin);
  txt.TickLengthLogical := ActiveController.Metric(TyAdvChartTickLenVar,
    TyAdvChartTickLen);
  txt.NameGapLogical := ActiveController.Metric(TyAdvChartNameGapVar,
    TyAdvChartNameGap);
  { Measuring goes through the painter behind an interface rather than being
    called directly, so the layout layer stays free of the painter and a test
    can hand it a deterministic measurer instead of this machine's fonts. }
  TyLayoutGrids(FBuild, FOption, AMeasurer, APPI, txt);
  { AFTER phase C, for the reason on FBarCols. }
  FBarCols := TySolveBarLayout(FOption, FBuild, FBindings, FStores, FIndex);
  SolvePies;
  SolveFunnels;
  SolveGauges(APPI);
  SolveRadars(APPI);
  SolveGraphs(APPI);
  SolveTitles(AMeasurer, APPI);
  SolveLegends(AMeasurer, APPI);
  FDirty := False;
end;

{ ==================== paint ==================== }

procedure TTyAdvanceChart.PaintAxis(APainter: TTyPainter; AAxis: TTyAxis;
  const APlot: TTyRectF; APPI: Integer; AGrid: TTyGridBuild;
  const AMeasurer: ITyTextMeasurer; ABelow: Boolean);
var
  model: TTyStyleModel;
  lineS, tickStyle, labelS, splitS: TTyStyleSet;
  lblStyle, primaryS: TTyStyleSet;
  minorTickS, minorSplitS, nameS: TTyStyleSet;
  ticks: TTyDoubleArray;
  i: Integer;
  tickLen, minorLen, at, along, x1, y1, x2, y2: Double;
  nameOff, nx, ny, nameAngle: Double;
  maxW, batched: Integer;
  horiz: Boolean;
  lblH, lblW, step, tickStep: Integer;
  scaleTicks: TTyScaleTickArray;
  spec: PTyAxisLayoutSpec;
  places: TTyAxisLabelPlacementArray;
  furn: TTyAxisFurniture;
  areaS: TTyStyleSet;
  bandLo, bandHi: Double;

  { THE BOX IS THE TRANSLATION. The layout layer says "this point, with the
    text hanging off it this way"; the painter aligns text INSIDE a rectangle.
    Building a box that is exactly the text's size around the anchor makes the
    two agree, and makes the alignment argument irrelevant.

    Mapping anchors to LCL alignments instead was the first attempt and it was
    wrong in a way worth remembering: a right-anchored label kept the old
    symmetric box, so right-justifying inside it put the text's right edge a
    whole width PAST the anchor -- straight through the tick marks. }
  { The same two anchors DrawTextRotated wants, which takes the point and the
    alignments rather than a rectangle. }
  function AnchorAlign(AH2: TTyTextAnchorH): TAlignment;
  begin
    case AH2 of
      tahLeft: Result := taLeftJustify;
      tahRight: Result := taRightJustify;
    else Result := taCenter;
    end;
  end;

  function AnchorLayout(AV: TTyTextAnchorV): TTextLayout;
  begin
    case AV of
      tavTop: Result := tlTop;
      tavBottom: Result := tlBottom;
    else Result := tlCenter;
    end;
  end;

  function AnchorBox(AX, AY: Double; AW, AH: Integer;
    AH2: TTyTextAnchorH; AV: TTyTextAnchorV): TRect;
  begin
    case AH2 of
      tahLeft: begin Result.Left := Round(AX); Result.Right := Round(AX) + AW; end;
      tahRight: begin Result.Left := Round(AX) - AW; Result.Right := Round(AX); end;
    else
      begin
        Result.Left := Round(AX - AW / 2);
        Result.Right := Result.Left + AW;
      end;
    end;
    case AV of
      tavTop: begin Result.Top := Round(AY); Result.Bottom := Round(AY) + AH; end;
      tavBottom: begin Result.Top := Round(AY) - AH; Result.Bottom := Round(AY); end;
    else
      begin
        Result.Top := Round(AY - AH / 2);
        Result.Bottom := Result.Top + AH;
      end;
    end;
  end;

  { The width the theme asked for, LOGICAL -- StrokePath scales it itself.

    An undeclared width falls back to one logical pixel rather than to zero: a
    theme that names a colour and no width means "draw it", not "draw nothing",
    and StrokePath treats a width of zero as "no border". }
  function LineWidth(const AStyle: TTyStyleSet): Double;
  begin
    if tpBorderWidth in AStyle.Present then
      Result := AStyle.BorderWidth
    else
      Result := 1;
    if Result < 0.05 then Result := 0.05;
  end;

  { THE LAYOUT'S OWN MEASURER, not the painter's TextSize. They are two
    different rasterisers -- Measure.pas' header says they disagree by about a
    pixel and that a size floor feeding a clip must take the LARGER, which is
    what the layout does -- so measuring here with the other one made the
    reserved gutter and the drawn box two different numbers. It is also the one
    path that misses the painter's measurement memo. }
  procedure TextSizeOf(const AText: string; const AStyle: TTyStyleSet;
    out AW, AH: Integer);
  var w, h: Double;
  begin
    if AMeasurer = nil then
    begin
      AW := APainter.MeasureText(AText, AStyle.FontName,
        ResolveFontSize(AStyle), AStyle.FontWeight).cx;
      AH := APainter.MeasureText('Wg', AStyle.FontName,
        ResolveFontSize(AStyle), AStyle.FontWeight).cy;
      Exit;
    end;
    AMeasurer.MeasureLine(AText, AStyle.FontName, ResolveFontSize(AStyle),
                          AStyle.FontWeight, w, h);
    AW := Round(w);
    AH := Round(h);
  end;

  { ONE SUBPATH PER LINE, ONE STROKE PER STYLE.

    Every line an axis draws shares a style with its neighbours by
    construction, and a path can hold as many subpaths as it likes -- each
    MoveTo starts a new one -- so a whole set of split lines is one BeginPath, N
    MoveTo/LineTo pairs and one StrokePath. Stroking them one at a time is what
    made a 600-point frame cost 110 ms when the same frame without axes costs
    13: the bill was never pixels, it was the per-call setup, and quartering the
    area did not quarter the time. ECharts survives 100k elements on the same
    trick (canPathBatch: consecutive same-style elements accumulate into one
    beginPath and one fill/stroke).

    SNAPPED as it is added. A stroke whose outer edge falls between two pixel
    rows lights both at half alpha, which is what makes a 1 px grid read grey
    and soft next to the crisp control chrome around it.

    TWO UNITS, DELIBERATELY. The snap works in DEVICE px -- the pixel grid the
    ink lands on is the device one, so snapping a logical coordinate would mean
    nothing -- while StrokePath wants the LOGICAL width and scales it itself.
    Handing the scaled width to both is a double scale that 96 DPI hides
    completely, which is how the first version of this passed. }
  procedure BatchLine(AX1, AY1, AX2, AY2: Double; AWidthLogical: Double);
  begin
    TySubPixelLine(AX1, AY1, AX2, AY2, APainter.ScaleF(AWidthLogical));
    APainter.MoveTo(AX1, AY1);
    APainter.LineTo(AX2, AY2);
    Inc(batched);
  end;

  { Stroke what BatchLine collected, if anything. The count guards a stroke of
    an empty path, which a fully thinned-away set of minor ticks produces. }
  procedure StrokeBatch(const AStyle: TTyStyleSet);
  begin
    if batched > 0 then
      APainter.StrokePath(AStyle.BorderColor, LineWidth(AStyle));
    batched := 0;
  end;

begin
  if AAxis = nil then Exit;
  { `show: false` means "do not draw me". The axis still exists and its series
    still map to pixels; only the domain, ticks, labels and split lines go. }
  if not AAxis.Visible then Exit;
  model := ActiveController.Model;
  { A foreign typeKey is resolved by asking the model directly -- there is no
    per-part helper in this library and inventing one here would be a second
    idiom for the same thing. }
  lineS := model.ResolveStyle('TyAdvChartAxisLine', '', []);
  minorTickS := model.ResolveStyle('TyAdvChartMinorTick', '', []);
  minorSplitS := model.ResolveStyle('TyAdvChartMinorSplitLine', '', []);
  tickStyle := model.ResolveStyle('TyAdvChartAxisTick', '', []);
  labelS := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  primaryS := model.ResolveStyle('TyAdvChartAxisLabelPrimary', '', []);
  splitS := model.ResolveStyle('TyAdvChartSplitLine', '', []);
  areaS := model.ResolveStyle('TyAdvChartSplitArea', '', []);

  horiz := AAxis.Horizontal;
  { WHERE THE AXIS SITS, asked of the build rather than worked out here: the
    plot's edge, that edge pushed out by `offset`, or the other family's zero
    when `axisLine.onZero` applies. Three alternatives and one answer.

    THE LABELS DO NOT FOLLOW IT TO ZERO. Upstream carries a `labelOffset`
    back to the raw edge precisely so that a chart with negative values has
    its axis line through the middle and its category names still along the
    bottom. The offset, by contrast, DOES move them -- that offset survives
    into labelOffset. }
  if horiz then at := APlot.Bottom else at := APlot.Left;
  if AAxis.Side = asTop then at := APlot.Top;
  if AAxis.Side = asRight then at := APlot.Right;
  if AGrid <> nil then at := AGrid.AxisLineCoord(AAxis, APPI);


  { THE THINNING STEP, READ FROM THE LAYOUT. It used to be computed halfway
    down this procedure, after the split lines had already been drawn -- so the
    ticks thinned with the labels and the lines behind them did not, which is an
    axis wearing a grid and a set of numbers that disagree about how many
    divisions it has.

    And it used to be computed AT ALL here: TyAxisLabelStep measures every
    label, so a frame spent ten thousand measurements at 5,000 categories to
    choose the twenty it would draw. Phase C already measured them to shrink the
    plot rect; it records what it decided and this reads it. }
  spec := nil;
  if AGrid <> nil then spec := AGrid.SpecFor(AAxis);
  { WHAT THIS AXIS ACTUALLY DRAWS. Resolved once by the builder, from the
    option AND from upstream's per-type defaults -- which is where most of
    the answers come from: on a chart with no axis option written at all, the
    category axis draws its domain line and nothing else, and the value axis
    draws its split lines and nothing else. }
  furn := Default(TTyAxisFurniture);
  furn.ShowLine := True;
  furn.ShowTicks := True;
  furn.ShowLabels := True;
  if AGrid <> nil then furn := AGrid.FurnitureFor(AAxis);

  { THE TICK'S LENGTH, and it has to be asked AFTER the two lines above. It
    used to be asked first -- reading `spec` and `furn` before either was
    resolved, so an authored `axisTick.length` and `axisTick.inside` were both
    decided by whatever was on the stack. The layout half was right and the
    paint half was reading uninitialised memory, which is a difference no
    assertion about the plot rectangle could ever see. }
  { THE SPEC'S LENGTH, not the theme metric over again: FillSpec has already
    laid the option over the theme, and the layout reserved the gutter from
    exactly that number. Asking the theme a second time here is how the
    reserved band and the drawn mark come to disagree. }
  tickLen := APainter.ScaleF(ActiveController.Metric(TyAdvChartTickLenVar,
    TyAdvChartTickLen));
  if spec <> nil then tickLen := APainter.ScaleF(spec^.TickLengthLogical);
  minorLen := APainter.ScaleF(ActiveController.Metric(TyAdvChartMinorTickLenVar,
    TyAdvChartMinorTickLen));
  if not IsNan(furn.MinorTickLengthLogical) then
    minorLen := APainter.ScaleF(furn.MinorTickLengthLogical);
  { INSIDE TURNS THEM ROUND -- BOTH OF THEM. A negative length points the mark
    into the plot, which is the whole of what the option does, and the layout
    has already stopped reserving room outside for it. There is no
    `minorTick.inside`: upstream flips one tickDirection and every mark on the
    axis follows it, so majors pointing in with minors still pointing out is
    not a state upstream can reach. }
  if furn.TickInside then
  begin
    tickLen := -tickLen;
    minorLen := -minorLen;
  end;
  step := 1;
  if (spec <> nil) and (spec^.LabelStep > 0) then step := spec^.LabelStep;
  { THE FURNITURE FOLLOWS THE LABELS UNLESS IT WAS TOLD OTHERWISE. Upstream
    defaults `axisTick.interval` to `auto`, and `auto` there does not compute
    anything -- it re-runs the LABEL pipeline and takes its ticks. So the
    label stride drives the marks, the split lines and the split areas one
    way, and only an explicit `axisTick.interval` breaks the tie. }
  tickStep := step;
  if (spec <> nil) and (spec^.TickStep > 0) then tickStep := spec^.TickStep;
  batched := 0;

  { Split lines first, so the domain and the ticks sit on top of them.

    TickCoords' default, NOT AAlignWithLabel: a split line divides the bands, it
    does not point at a label. On a banded category axis the two differ by half
    a band, which is exactly the width the whole parameter exists to express. }
  { MINOR FIRST, so a major line drawn at the same place wins. The two theme
    keys have been in light.tycss since item 18 with nothing that could ever be
    drawn with them: every generator wrote Level 0. }
  { MINORS ONLY WHILE THE MAJORS ARE ALL THERE. A minor tick subdivides the
    interval between two majors, so once the majors are being hidden the
    subdivisions of an interval nobody can see are noise -- and they are the
    densest thing on the axis, which makes them the worst noise to keep. }
  { SPLIT AREAS FIRST, because everything else is drawn ON them. Alternating
    bands between consecutive divisions -- so N divisions give N-1 bands, and
    the ones the theme paints are every other one. The key has been in
    light.tycss since item 18 with nothing that could draw with it.

    THE BANDS RUN BETWEEN THE SPLIT LINES, which on a banded category axis
    means between the band EDGES: one shaded band per category, which is what
    makes the alternating stripe line up with the bars rather than straddle
    them. }
  if ABelow and furn.ShowSplitArea and (tpBackground in areaS.Present) then
  begin
    ticks := AAxis.TickCoords;
    for i := 0 to High(ticks) - 1 do
    begin
      if i mod 2 <> 0 then Continue;
      bandLo := ticks[i];
      bandHi := ticks[i + 1];
      if horiz then
        APainter.FillBackground(
          Rect(Round(bandLo), Round(APlot.Top),
               Round(bandHi), Round(APlot.Bottom)), areaS.Background, 0)
      else
        APainter.FillBackground(
          Rect(Round(APlot.Left), Round(bandLo),
               Round(APlot.Right), Round(bandHi)), areaS.Background, 0);
    end;
  end;

  if ABelow and furn.ShowMinorSplitLine
    and (tpBorderColor in minorSplitS.Present) and (tickStep = 1) then
  begin
    scaleTicks := TyDrawnTicks(AAxis.Scale);
    APainter.BeginPath;
    for i := 0 to High(scaleTicks) do
    begin
      if scaleTicks[i].Level = 0 then Continue;
      along := AAxis.DataToCoord(scaleTicks[i].Value);
      if horiz then
        BatchLine(along, APlot.Top, along, APlot.Bottom, LineWidth(minorSplitS))
      else
        BatchLine(APlot.Left, along, APlot.Right, along, LineWidth(minorSplitS));
    end;
    StrokeBatch(minorSplitS);
  end;

  if ABelow and furn.ShowSplitLine and (tpBorderColor in splitS.Present) then
  begin
    ticks := AAxis.TickCoords;
    APainter.BeginPath;
    for i := 0 to High(ticks) do
    begin
      { THINNED WITH THE LABELS, on the same step the ticks use. }
      if (tickStep > 1) and (i mod tickStep <> 0) then Continue;
      { THE TWO ON THE ENDS ARE SEPARATELY DENIABLE. A grid line on the axis'
        own extreme sits exactly on the plot's edge, doubling whatever border
        is already there, and these are the keys that turn it off. }
      if (i = 0) and (not furn.ShowMinLine) then Continue;
      if (i = High(ticks)) and (not furn.ShowMaxLine) then Continue;
      along := ticks[i];
      if horiz then
        BatchLine(along, APlot.Top, along, APlot.Bottom, LineWidth(splitS))
      else
        BatchLine(APlot.Left, along, APlot.Right, along, LineWidth(splitS));
    end;
    StrokeBatch(splitS);
  end;

  { EVERYTHING ABOVE THIS LINE IS THE GRID and everything below it is the
    axis. The three grid blocks each test ABelow and this returns on it, so
    each pass paints its own half and neither repeats the other's -- the
    return alone was not enough, because the second pass would then draw the
    grid a second time, over the lines the first pass had just laid.

    THIS RETURN IS INVISIBLE ON ITS OWN. Delete it and the below pass also
    draws the lines, which the above pass then draws again on top -- same
    pixels, twice the work. A mutation that removes it survives, and it is
    the three ABelow tests above that carry the ordering; this one carries
    only the cost. }
  if ABelow then Exit;

  { The domain line. Present, not colour: an undeclared colour resolves to
    alpha zero, so testing the colour would draw an invisible line and call it
    drawn. }
  if furn.ShowLine and (tpBorderColor in lineS.Present) then
  begin
    APainter.BeginPath;
    if horiz then
      BatchLine(APlot.Left, at, APlot.Right, at, LineWidth(lineS))
    else
      BatchLine(at, APlot.Top, at, APlot.Bottom, LineWidth(lineS));
    StrokeBatch(lineS);
  end;

  { ALIGNED WITH THE LABELS OR WITH THE BAND EDGES. On a banded category axis
    the two are half a band apart, and which one a tick means is exactly what
    the option exists to say -- the split lines above keep the edges either
    way, because a divider that pointed at a label would not divide anything. }
  ticks := AAxis.TickCoords(furn.AlignWithLabel);
  { THE MARKS THIN WITH THE LABELS. Drawing every tick under a thinned set of
    labels reads as an axis that lost its labels rather than one that spaced
    them out, and computing the step by a second route is how the two drift --
    which is why `step` is worked out once, above, and the split lines use the
    same one. }
  if furn.ShowTicks and (tpBorderColor in tickStyle.Present) then
  begin
    APainter.BeginPath;
    for i := 0 to High(ticks) do
    begin
      if (tickStep > 1) and (i mod tickStep <> 0) then Continue;
      along := ticks[i];
      if horiz then
      begin
        x1 := along; x2 := along;
        y1 := at;
        if AAxis.Side = asTop then y2 := at - tickLen else y2 := at + tickLen;
      end
      else
      begin
        y1 := along; y2 := along;
        x1 := at;
        if AAxis.Side = asRight then x2 := at + tickLen else x2 := at - tickLen;
      end;
      BatchLine(x1, y1, x2, y2, LineWidth(tickStyle));
    end;
    StrokeBatch(tickStyle);
  end;

  { Minor MARKS. The difference in LENGTH is what says which is which when both
    are the same colour family -- and how much shorter is the theme's call, not
    a fraction hardcoded here. --advchart-minor-tick-length, its constant and
    its default have all been in place since item 18 with nothing reading them,
    so a skin that set it changed nothing. }
  if furn.ShowMinorTick and (tpBorderColor in minorTickS.Present)
    and (tickStep = 1) then
  begin
    scaleTicks := TyDrawnTicks(AAxis.Scale);
    APainter.BeginPath;
    for i := 0 to High(scaleTicks) do
    begin
      if scaleTicks[i].Level = 0 then Continue;
      along := AAxis.DataToCoord(scaleTicks[i].Value);
      if horiz then
      begin
        x1 := along; x2 := along;
        y1 := at;
        if AAxis.Side = asTop then y2 := at - minorLen
        else y2 := at + minorLen;
      end
      else
      begin
        y1 := along; y2 := along;
        x1 := at;
        if AAxis.Side = asRight then x2 := at + minorLen
        else x2 := at - minorLen;
      end;
      BatchLine(x1, y1, x2, y2, LineWidth(minorTickS));
    end;
    StrokeBatch(minorTickS);
  end;

  { THE AXIS NAME. Builder solves the grid with obcAll, so TyAxisThickness has
    been charging every named axis' side for NameGap plus the name's turned
    extent since item 12 -- and nothing ever drew into it. Setting xAxis.name
    shrank the plot by the width of a string that was not there.

    Placed by asking TyAxisThickness twice: once counting the name and once not.
    The difference IS the band reserved for it, so the name lands in the space
    the layout set aside rather than at an offset reassembled here out of the
    same parts -- which is the mistake this file warns about two hundred lines
    up, about computing a step by a second route.

    Centred in that band with taCenter/tlCenter, which also makes the placement
    independent of the rotation: a quarter turn about a centred anchor moves
    nothing. }
  nameS := model.ResolveStyle('TyAdvChartAxisName', '', []);
  if (AAxis.Name <> '') and (spec <> nil) and (AMeasurer <> nil)
    and (tpTextColor in nameS.Present) then
  begin
    nameOff := (TyAxisThickness(spec^, AMeasurer, APPI, obcAxisLabel)
              + TyAxisThickness(spec^, AMeasurer, APPI, obcAll)) / 2;
    if horiz then
    begin
      nx := (APlot.Left + APlot.Right) / 2;
      if AAxis.Side = asTop then ny := at - nameOff else ny := at + nameOff;
      nameAngle := 0;
    end
    else
    begin
      ny := (APlot.Top + APlot.Bottom) / 2;
      if AAxis.Side = asRight then nx := at + nameOff else nx := at - nameOff;
      { A quarter turn so it reads up the side -- and the same quarter turn
        TyAxisThickness applied when it charged the name's HEIGHT against this
        axis' width rather than its length. }
      nameAngle := Pi / 2;
    end;
    APainter.DrawTextRotated(AAxis.Name, nameS.FontName,
      ResolveFontSize(nameS), nameS.FontWeight, nameS.TextColor,
      nx, ny, nameAngle, taCenter, tlCenter);
  end;

  if not (tpTextColor in labelS.Present) then Exit;

  { PHASE 3 PLACES THEM. It was written with item 12 and never called, so every
    label was drawn at a position worked out here and none was ever thinned --
    a crowded axis simply overlapped. The placement carries the anchor too, so
    layout and paint cannot disagree about where a label went. }
  if (spec <> nil) and (Length(spec^.Placements) > 0) then
  begin
    places := spec^.Placements;
    for i := 0 to High(places) do
    begin
      if not places[i].Shown then Continue;
      if places[i].Text = '' then Continue;
      { THE WEIGHT THE LAYOUT MEASURED IT IN. A time axis marks its coarse
        ticks for emphasis -- the `Mar` in a run of day numbers -- and the
        layout already reserved the wider box that bold needs. Resolving it
        again here from anything but the placement is how the box and the
        glyphs come to disagree. }
      lblStyle := labelS;
      if places[i].Emphasis then lblStyle := primaryS;
      TextSizeOf(places[i].Text, lblStyle, lblW, lblH);
      { BOUNDED BY axisLabel.width WHEN TRUNCATING, and only then: with no
        bound the box is exactly the text's size, so the ellipsis fitter has
        nothing to bite on and `overflow` would silently do nothing.

        The other two modes need no bound here. `break` arrives already broken
        -- the builder wrapped it, so the box is the wrapped block's size and
        the multi-line flag lays it out -- and `none` is the old behaviour. }
      if (spec^.LabelOverflow = loTruncate)
        and (spec^.LabelWidthLogical > 0) then
      begin
        maxW := Round(APainter.ScaleF(spec^.LabelWidthLogical));
        if maxW < lblW then lblW := maxW;
      end;
      { TURNED, WHEN THE AUTHOR ASKED FOR IT. The layout has measured the
        turned extent since item 12 and nothing ever drew the turn, so an
        `axisLabel: { rotate: 45 }` bought a deeper gutter and put flat text in
        it. Counter-clockwise positive on both sides -- upstream's and the
        painter's -- so the angle passes straight through.

        DrawTextRotated takes the anchor as a POINT plus the alignments that
        say where in the text box it sits, which is what the placement already
        carries; AnchorBox exists only because the flat path needs a rect. }
      if spec^.RotationRad <> 0 then
      begin
        APainter.DrawTextRotated(places[i].Text, lblStyle.FontName,
          ResolveFontSize(lblStyle), lblStyle.FontWeight, lblStyle.TextColor,
          places[i].X, places[i].Y, spec^.RotationRad,
          AnchorAlign(places[i].AnchorH), AnchorLayout(places[i].AnchorV));
        Continue;
      end;
      APainter.DrawText(
        AnchorBox(places[i].X, places[i].Y, lblW, lblH,
                  places[i].AnchorH, places[i].AnchorV),
        places[i].Text, lblStyle.FontName, ResolveFontSize(lblStyle),
        lblStyle.FontWeight, lblStyle.TextColor, taCenter, tlCenter,
        { ELLIPSIS AND MULTI-LINE, both of which the painter has always had and
          this never asked for: a label was drawn as one clipped line whatever
          it contained, so a wrapped one lost every row after the first. }
        spec^.LabelOverflow = loTruncate, 0, False,
        Pos(#10, places[i].Text) > 0);
    end;
    Exit;
  end;

  { NO PLACEMENTS, NO LABELS. There used to be a second route here that
    formatted and positioned the ticks itself, for an axis laid out without a
    spec. None reaches it -- every grid axis gets a spec, and the placements
    are one per label -- so all it ever did was keep its own copy of the
    number format in step with the builder's, which it did not. The builder
    is the one place a label's text comes from. }
end;

procedure TTyAdvanceChart.RenderTo(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
var
  P: TTyPainter;
  R: TRect;
  boxStyle: TTyStyleSet;
  plotF: TTyRectF;
  g, a: Integer;
  gb: TTyGridBuild;
  measurer: ITyTextMeasurer;
begin
  { ONE measurer, held in an interface variable, for the whole render.

    Not `TTyPainterTextMeasurer.Create(APPI)` at each call site: the parameter
    is declared `const ITyTextMeasurer`, and a const interface parameter does
    not get the reference-counting temporary -- so an object passed straight in
    stays at a refcount of zero and is never freed. Two axes times two calls
    times every repaint is a leak the heap test found within thirty renders.

    Holding it here also means the layout pass and the paint pass measure with
    the same instance, which is what they are supposed to agree about. }
  measurer := TTyPainterTextMeasurer.Create(APPI);
  P := TTyPainter.Create;
  try
    { LOCAL space. EndPaint blits at ARect's origin, so everything below is
      measured from zero. }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    PaintStatic(P, R, APPI, measurer);
    PaintDynamic(P, R, APPI, measurer);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyAdvanceChart.PaintStatic(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  boxStyle: TTyStyleSet;
  plotF: TTyRectF;
  g, a: Integer;
  gb: TTyGridBuild;
begin
  { Resolved at REST on purpose. The plot rect is measured from the label
    font, and a geometry that read the focused style would move the whole
    chart the moment it took focus. }
  boxStyle := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
    [tysNormal]);
  { Mandatory first draw, and it does more than a fill: parent backdrop,
    opacity, shadow, background, border, and the corner gaps a windowed
    control cannot get from a shadow it is not allowed to cast. }
  DrawFrame(APainter, ARect, boxStyle);

  plotF := TyRectF(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  if FDirty or (plotF.Right <> FLastRect.Right)
    or (plotF.Bottom <> FLastRect.Bottom) then
    Relayout(APainter, plotF, APPI, AMeasurer);

  if FBuild <> nil then
    for g := 0 to FBuild.GridCount - 1 do
    begin
      gb := FBuild.Grid(g);
      { EVERY AXIS' GRID FIRST, then every axis' line. Two passes over the
        same list rather than one, because the order that matters is
        between the LAYERS and not between the axes. }
      for a := 0 to gb.XAxisCount - 1 do
        PaintAxis(APainter, gb.XAxis(a), gb.PlotRect, APPI, gb, AMeasurer,
                  True);
      for a := 0 to gb.YAxisCount - 1 do
        PaintAxis(APainter, gb.YAxis(a), gb.PlotRect, APPI, gb, AMeasurer,
                  True);
      for a := 0 to gb.XAxisCount - 1 do
        PaintAxis(APainter, gb.XAxis(a), gb.PlotRect, APPI, gb, AMeasurer,
                  False);
      for a := 0 to gb.YAxisCount - 1 do
        PaintAxis(APainter, gb.YAxis(a), gb.PlotRect, APPI, gb, AMeasurer,
                  False);
    end;

  { AFTER THE AXES, so a bar sits on the grid rather than under it. Within the
    series, the paint list decides the order. }
  PaintSeries(APainter, AMeasurer, APPI);
  { AND THE TITLE LAST. It floats over the container rather than reserving
    room, so anything it overlaps it is meant to overlap. }
  PaintTitles(APainter);
end;

function TTyAdvanceChart.StackFor(ASlot: Integer): TTySeriesStack;
begin
  if (ASlot >= 0) and (ASlot <= High(FStacks)) then
    Result := FStacks[ASlot]
  else
  begin
    Result := Default(TTySeriesStack);
    Result.ResultCol := -1;
    Result.OverCol := -1;
  end;
end;

function TTyAdvanceChart.LabelStepFor(AAxis: TTyAxis): Integer;
var
  g: Integer;
  spec: PTyAxisLayoutSpec;
begin
  Result := 1;
  if (AAxis = nil) or (FBuild = nil) then Exit;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    spec := FBuild.Grid(g).SpecFor(AAxis);
    if spec <> nil then
    begin
      if spec^.LabelStep > 1 then Result := spec^.LabelStep;
      Exit;
    end;
  end;
end;

{ One whole number off a series node, ADefault when it is absent or is not a
  number. Rounded rather than truncated: `z: 1.5` is somebody's mistake, and
  the two neighbouring answers are both defensible -- the nearer one is the
  one the author was closer to meaning. }
function TTyAdvanceChart.SeriesIntIn(ASeriesIndex: Integer;
  const AKey: string; ADefault: Integer): Integer;
var
  d: TJSONData;
  node: TJSONObject;
  v: Double;
begin
  Result := ADefault;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find(AKey);
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  v := d.AsFloat;
  if IsNan(v) or IsInfinite(v) then Exit;
  { CLAMPED, because Round targets an Int64 and the paint list's key is an
    Integer -- a z of 1e18 is not an order, it is an overflow. }
  v := Max(Double(-100000), Min(Double(100000), v));
  Result := Round(v);
end;

function TTyAdvanceChart.SymbolFor(ASlot: Integer): TTySymbolSpec;
var
  d: TJSONData;
  node: TJSONObject;
begin
  Result := TySymbolDefault('');
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  Result := TySymbolDefault(FBindings[ASlot].SeriesType);
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  Result := TySymbolSpecOf(node, Result);
end;

procedure TTyAdvanceChart.SolveSeriesColors;

  { An unnamed series is NOT nameless as far as the palette is concerned.
    Upstream builds `series` + NUL + index precisely so two unnamed series
    cannot collide in the memo, and its comment says so. Leaving it empty
    would give every unnamed series the first colour. }
  function NameFor(ASlot: Integer): string;
  begin
    Result := SeriesNameOf(ASlot);
    if Result = '' then Result := TyChartSeriesDefaultName(ASlot);
  end;

var
  i, n: Integer;
  declared: Boolean;
  cur, own: TTyPaletteCursor;
  ownPal: TTyChartColorArray;
  node: TJSONObject;
  d: TJSONData;
  st: string;
  style: TTyOptStyle;
  key, other: TTyOptColor;
  hasAuto: Boolean;
  c: TTyChartColor;
begin
  FSeriesColors := nil;
  FSeriesColorKnown := nil;
  FSeriesPalette := nil;
  FSeriesPaletteKnown := nil;
  if FOption = nil then Exit;
  n := FOption.ComponentCount('series');
  SetLength(FSeriesColors, n);
  SetLength(FSeriesColorKnown, n);
  SetLength(FSeriesPalette, n);
  SetLength(FSeriesPaletteKnown, n);
  cur := TyPaletteStart(TyChartPaletteOf(FOption, -1, declared));

  { DECLARATION ORDER, AND EVERY SLOT. A series the legend switched off still
    takes its colour, and so does one whose type has no renderer -- that is the
    entire mechanism by which colours stay put across a legend click. Skipping
    the hidden ones would re-shuffle every colour after them. }
  for i := 0 to n - 1 do
  begin
    d := FOption.ComponentAt('series', i);
    node := nil;
    if (d <> nil) and (d.JSONType = jtObject) then node := TJSONObject(d);
    st := '';
    if node <> nil then
    begin
      d := node.Find('type');
      if (d <> nil) and (d.JSONType = jtString) then st := d.AsString;
    end;

    { WHICH KEY SUPPRESSES THE PALETTE depends on what the series draws with.
      Nearly everything fills, so it is `itemStyle.color`; a boxplot draws with
      its stroke, so it is `itemStyle.borderColor`; `lines` and `parallel` read
      a different block entirely. A line is NOT one of the exceptions -- writing
      `lineStyle.color` on a line does not stop it taking a palette slot. }
    style := TyReadOptStyle(node, TyStyleAccessPath(st));
    if TyStyleDrawsWithStroke(st) and (TyStyleAccessPath(st) = 'itemStyle') then
    begin
      key := style.BorderColor;
      other := style.Color;
    end
    else
    begin
      key := style.Color;
      other := style.BorderColor;
    end;
    { `auto` ON EITHER HALF OF THE PAIR sends this series to the palette,
      even when the other half names a colour -- upstream tests `fill` AND
      `stroke` for the word and consults the palette if either carries it.
      So `{ color: '#fff', borderColor: 'auto' }` is a white bar with a
      border in the palette colour, and it costs a slot. }
    hasAuto := key.IsAuto or other.IsAuto;

    if key.Written and not hasAuto then
    begin
      { AN AUTHORED COLOUR CONSUMES NO SLOT, and upstream says why in a comment:
        an author who paints one series transparent, or as a backdrop, did not
        mean to shift every other series' colour. `series: [{}, {color}, {}]` is
        palette[0], the authored one, palette[1]. }
      if not key.IsNone then
      begin
        FSeriesColors[i] := key.Color;
        FSeriesColorKnown[i] := True;
      end;
      Continue;
    end;

    { A SERIES WITH ITS OWN `color` ARRAY runs its own cursor over it from
      nought, and never touches the chart-wide one. }
    ownPal := TyChartPaletteOf(FOption, i, declared);
    if Length(ownPal) > 0 then
    begin
      own := TyPaletteStart(ownPal);
      if TyPaletteTake(own, NameFor(i), c) then
      begin
        FSeriesPalette[i] := c;
        FSeriesPaletteKnown[i] := True;
        if (not key.Written) or key.IsAuto then
        begin
          FSeriesColors[i] := c;
          FSeriesColorKnown[i] := True;
        end
        else if not key.IsNone then
        begin
          FSeriesColors[i] := key.Color;
          FSeriesColorKnown[i] := True;
        end;
      end;
      Continue;
    end;

    { `auto` takes a slot as surely as writing nothing does -- it means `the
      palette colour`, so it has to have one. }
    if TyPaletteTake(cur, NameFor(i), c) then
    begin
      FSeriesPalette[i] := c;
      FSeriesPaletteKnown[i] := True;
      { THE PICK IS NOT ALWAYS THE FILL. It becomes the fill only when the
        fill was left unwritten, or was written as `auto`; a series that
        named its fill and asked for `auto` somewhere else keeps the name
        it gave. }
      if (not key.Written) or key.IsAuto then
      begin
        FSeriesColors[i] := c;
        FSeriesColorKnown[i] := True;
      end
      else if not key.IsNone then
      begin
        FSeriesColors[i] := key.Color;
        FSeriesColorKnown[i] := True;
      end;
    end;
  end;
end;

procedure TTyAdvanceChart.ApplyOptStyle(var AVisual: TTySeriesVisual;
  ASlot: Integer);
var
  node: TJSONObject;
  d: TJSONData;
  st: string;
  item, line: TTyOptStyle;
begin
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASlot);
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('type');
  st := '';
  if (d <> nil) and (d.JSONType = jtString) then st := d.AsString;

  { THE FILL IS ALREADY DECIDED. SolveSeriesColors read the same key to
    settle whether this series took a palette slot, and SeriesColor handed
    the answer over -- reading it a second time here would be a second
    place that has to agree about `auto`. }
  item := TyReadOptStyle(node, 'itemStyle');
  line := TyReadOptStyle(node, 'lineStyle');

  { `itemStyle.borderColor` / `borderWidth`. `auto` on a border means the
    palette colour, the same as it does on a fill. }
  if item.BorderColor.Written and not item.BorderColor.IsNone then
  begin
    if item.BorderColor.IsAuto then
      AVisual.Stroke := TTyChartColor(SeriesPaletteColor(ASlot))
    else
      AVisual.Stroke := item.BorderColor.Color;
  end;
  if not IsNan(item.BorderWidthLogical) then
    AVisual.StrokeWidthLogical := item.BorderWidthLogical;
  { THE PEN'S DASH, carried as the option wrote it -- see TTySeriesVisual. }
  AVisual.Dash := item.Dash;
  AVisual.DashExplicit := item.DashLogical;
  if not IsNan(item.Opacity) then
    AVisual.Alpha := Min(Double(1), Max(Double(0), item.Opacity));
  { THE RAMP, when the colour was an object rather than a string. The solid
    stays where it was -- SeriesColor already holds the first stop -- so a
    legend swatch and a tooltip marker go on working unchanged. }
  AVisual.FillGradient := item.Color.Gradient;
  AVisual.StrokeGradient := item.BorderColor.Gradient;

  { A LINE READS ITS OWN BLOCK FOR THE PEN, and only for the pen. Its
    palette colour came from `itemStyle` -- that is the trap in this whole
    row -- and that colour still goes to its symbols and its area; the
    authored `lineStyle.color` wins the polyline's pixels and nothing else. }
  if (st = 'line') or TyStyleDrawsWithStroke(st) then
  begin
    if line.Color.Written and not line.Color.IsNone then
    begin
      if line.Color.IsAuto then
        AVisual.Stroke := TTyChartColor(SeriesPaletteColor(ASlot))
      else
        AVisual.Stroke := line.Color.Color;
    end;
    if not IsNan(line.BorderWidthLogical) then
      AVisual.StrokeWidthLogical := line.BorderWidthLogical;
    { AND IT REPLACES the itemStyle one rather than adding to it: for a shape
      drawn with a stroke, lineStyle IS the pen. `lineStyle: {}` with no type
      leaves todNone, which answers solid -- so a line series that writes only
      a width does not inherit a dash from its itemStyle. }
    AVisual.Dash := line.Dash;
    AVisual.DashExplicit := line.DashLogical;
    if not IsNan(line.Opacity) then
      AVisual.Alpha := Min(Double(1), Max(Double(0), line.Opacity));
    if line.Color.Gradient.Kind <> cgkNone then
      AVisual.StrokeGradient := line.Color.Gradient;
  end;
end;

function TTyAdvanceChart.ThemeRampColor(ASlot: Integer): TTyColor;
var
  st: TTyStyleSet;
begin
  { NINE SLOTS, CYCLED -- nine because upstream's own default palette is nine
    colours and the CYCLE LENGTH is observable: it decides which series comes
    round to share a colour with the first. Derived from --accent rather than
    written out, which is what makes a re-skinned chart come out in the skin's
    own colours; slot 1 IS the accent, so a single-series chart is drawn in
    the theme's own colour. }
  st := ActiveController.Model.ResolveStyle(
    'TyAdvChartSeries' + IntToStr((Abs(ASlot) mod 9) + 1), '', []);
  if tpBackground in st.Present then
    Exit(st.Background.Color);
  { The nine keys are in the BASE layer, so a theme cannot remove them -- it
    can only restyle them, and a skin that defines none of them inherits all
    nine. Reaching here means something is wrong with the theme rather than
    with the option, so the answer is the control's own foreground: visible
    against its own surface by construction, which is the one thing a fallback
    colour has to be. }
  st := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
    [tysNormal]);
  Result := st.TextColor;
end;

function TTyAdvanceChart.SeriesPaletteColor(ASeriesIndex: Integer): TTyColor;
begin
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesPaletteKnown))
    and FSeriesPaletteKnown[ASeriesIndex] then
    Exit(TTyColor(FSeriesPalette[ASeriesIndex]));
  Result := ThemeRampColor(ASeriesIndex);
end;

function TTyAdvanceChart.SeriesColor(ASeriesIndex: Integer): TTyColor;
begin
  { THE AUTHOR'S PALETTE FIRST. `color: [...]` or an authored
    `itemStyle.color` is the author speaking about their own chart, and a
    skin has no business overruling it. }
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesColorKnown))
    and FSeriesColorKnown[ASeriesIndex] then
    Exit(TTyColor(FSeriesColors[ASeriesIndex]));

  Result := ThemeRampColor(ASeriesIndex);
end;

function TTyAdvanceChart.TitleFont(const AKey: string): TTyTitleFont;
var st: TTyStyleSet;
begin
  st := ActiveController.Model.ResolveStyle(AKey, '', []);
  Result.Name := st.FontName;
  Result.SizeLogical := ResolveFontSize(st);
  Result.Weight := st.FontWeight;
end;

procedure TTyAdvanceChart.SolveTitles(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i, n: Integer;
begin
  n := TyTitleCount(FOption);
  SetLength(FTitles, n);
  SetLength(FTitleSpecs, n);
  for i := 0 to n - 1 do
  begin
    FTitleSpecs[i] := TyTitleSpecOf(FOption, i);
    FTitles[i] := TyLayoutTitle(FTitleSpecs[i], FLastRect, AMeasurer,
      TitleFont('TyAdvChartTitle'), TitleFont('TyAdvChartSubtitle'), APPI);
  end;
end;

procedure TTyAdvanceChart.SolvePies;
var
  i, dim: Integer;
begin
  SetLength(FPies, Length(FBindings));
  SetLength(FPieSpecs, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FPies[i] := Default(TTyPieLayout);
    FPieSpecs[i] := TyPieSpecDefault;
    if i > High(FStores) then Break;
    if not FBindings[i].Resolved then Continue;
    if FBindings[i].SeriesType <> TyPieSeriesTypeName then Continue;
    FPieSpecs[i] := TyPieSpecOf(FOption, FBindings[i].SeriesIndex);
    dim := FStores[i].DimIndexOf(TyPieValueDim);
    { FLastRect, not a grid: a pie is laid out against the CONTROL, and its
      own left/top/right/bottom shrink that. Handing it a grid rect would
      centre it on the plot instead of on the chart, which is not where
      ECharts puts it. }
    FPies[i] := TyPieLayoutOf(FPieSpecs[i], FLastRect, FStores[i], dim);
  end;
end;

procedure TTyAdvanceChart.SolveFunnels;
var
  i, dim: Integer;
begin
  SetLength(FFunnels, Length(FBindings));
  SetLength(FFunnelSpecs, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FFunnels[i] := Default(TTyFunnelLayout);
    FFunnelSpecs[i] := TyFunnelSpecDefault;
    if i > High(FStores) then Break;
    if not FBindings[i].Resolved then Continue;
    if FBindings[i].SeriesType <> TyFunnelSeriesTypeName then Continue;
    FFunnelSpecs[i] := TyFunnelSpecOf(FOption, FBindings[i].SeriesIndex);
    dim := FStores[i].DimIndexOf(TyPieValueDim);
    { FLastRect, not a grid -- a funnel is laid out against the CONTROL and
      its own left/top/right/bottom shrink that, the same rule a pie follows
      and for the same reason. }
    FFunnels[i] := TyFunnelLayoutOf(FFunnelSpecs[i], FLastRect,
      FStores[i], dim);
  end;
end;

procedure TTyAdvanceChart.FreeRadars;
var i: Integer;
begin
  for i := 0 to High(FRadars) do FreeAndNil(FRadars[i]);
  FRadars := nil;
end;

function TTyAdvanceChart.GraphLayout(ASeriesIndex: Integer;
  out ANodes: TTyGraphNodeArray; out AEdges: TTyGraphEdgeArray;
  out AFills: TTyChartColorArray): Boolean;
var slot: Integer;
begin
  ANodes := nil;
  AEdges := nil;
  AFills := nil;
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FGraphLaidOut)) or not FGraphLaidOut[slot] then
    Exit;
  ANodes := Copy(FGraphNodes[slot]);
  AEdges := Copy(FGraphEdges[slot]);
  AFills := GraphInk(slot).NodeFills;
  Result := True;
end;

function TTyAdvanceChart.GraphInkOf(ASeriesIndex: Integer;
  out AInk: TTyGraphInk; out ASpec: TTyGraphSpec): Boolean;
var slot: Integer;
begin
  AInk := Default(TTyGraphInk);
  ASpec := Default(TTyGraphSpec);
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FGraphLaidOut)) or not FGraphLaidOut[slot] then
    Exit;
  AInk := GraphInk(slot);
  ASpec := FGraphSpecs[slot];
  Result := True;
end;

function TTyAdvanceChart.LegendLayoutCount: Integer;
begin
  Result := Length(FLegends);
end;

function TTyAdvanceChart.LegendLayout(AIndex: Integer): TTyLegendLayout;
begin
  Result := Default(TTyLegendLayout);
  if (AIndex >= 0) and (AIndex <= High(FLegends)) then
  begin
    Result := FLegends[AIndex];
    { A dynamic array is shared, not copied, and a caller writing into it
      would be writing into the control's own layout. }
    Result.Items := Copy(FLegends[AIndex].Items);
  end;
end;

procedure TTyAdvanceChart.SolveGraphCategoryColours;
var
  shown: array of Boolean;
  fallback: TTyChartColorArray;
  i, n: Integer;
begin
  FGraphCatColours := nil;
  if FOption = nil then Exit;
  n := FOption.ComponentCount('series');
  SetLength(shown, n);
  for i := 0 to n - 1 do shown[i] := True;
  for i := 0 to High(FBindings) do
    if (FBindings[i].SeriesIndex >= 0) and (FBindings[i].SeriesIndex < n) then
      shown[FBindings[i].SeriesIndex] := not FBindings[i].Hidden;
  { THE THEME'S NINE, standing where upstream's default palette stands -- the
    same nine every series colour falls back to. }
  SetLength(fallback, 9);
  for i := 0 to 8 do fallback[i] := TTyChartColor(ThemeRampColor(i));
  FGraphCatColours := TyGraphCategoryColours(FOption, shown, fallback);
end;

procedure TTyAdvanceChart.FreeGraphs;
var i: Integer;
begin
  for i := 0 to High(FGraphs) do FreeAndNil(FGraphs[i]);
  FGraphs := nil;
  FGraphLaidOut := nil;
  FGraphSpecs := nil;
  FGraphNodes := nil;
  FGraphEdges := nil;
  FGraphCats := nil;
end;

procedure TTyAdvanceChart.SolveGraphs(APPI: Integer);
var
  i, si, colX, colY: Integer;
  solved: TTyGraphSolved;
  store: TTyDataStore;
  cols: TTyIntegerArray;
begin
  FreeGraphs;
  SetLength(FGraphs, Length(FBindings));
  SetLength(FGraphLaidOut, Length(FBindings));
  SetLength(FGraphSpecs, Length(FBindings));
  SetLength(FGraphNodes, Length(FBindings));
  SetLength(FGraphEdges, Length(FBindings));
  SetLength(FGraphCats, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FGraphs[i] := nil;
    FGraphLaidOut[i] := False;
    if FBindings[i].SeriesType <> TyGraphSeriesTypeName then Continue;
    if not FBindings[i].Resolved then Continue;
    { A GRAPH THE LEGEND SWITCHED OFF IS NOT LAID OUT AT ALL -- upstream's
      legendFilter takes the series out before any layout runs -- and for a
      force graph of five hundred nodes that is a second and a half nobody
      would see. }
    if FBindings[i].Hidden then Continue;
    si := FBindings[i].SeriesIndex;
    if si < 0 then Continue;
    store := nil;
    if i <= High(FStores) then store := FStores[i];
    { A GRAPH ON AXES IS LAID OUT BY THE AXES IT NAMED, here, after the grids
      have their final pixels: every node at the grid's dataToPoint of its two
      columns, whatever `layout` says. Upstream skips the ring, the force
      simulation and the view alike for any coordinate system that is not a
      view, so this keeps no force state either. The columns are the first
      each axis owns, the same lookup every other renderer makes. }
    if (FBindings[i].CoordSysName = 'cartesian2d') and (FBindings[i].Cart <> nil)
      and (store <> nil) then
    begin
      colX := -1;
      colY := -1;
      if FBindings[i].XAxis <> nil then
      begin
        cols := store.DimsOfCoord(FBindings[i].XAxis.Dim);
        if Length(cols) > 0 then colX := cols[0];
      end;
      if FBindings[i].YAxis <> nil then
      begin
        cols := store.DimsOfCoord(FBindings[i].YAxis.Dim);
        if Length(cols) > 0 then colY := cols[0];
      end;
      solved := TyGraphSolveOnCoordSys(FOption, si, store, FBindings[i].Cart,
        colX, colY);
      FGraphLaidOut[i] := True;
      FGraphSpecs[i] := solved.Spec;
      FGraphNodes[i] := solved.Nodes;
      FGraphEdges[i] := solved.Edges;
      FGraphCats[i] := solved.Cats;
      Continue;
    end;
    { ANY OTHER SYSTEM BUT A VIEW IS NOT PORTED -- polar, geo, a calendar --
      and a graph on one resolves and draws nothing rather than being quietly
      given a view it did not ask for. }
    if FBindings[i].CoordSysName <> 'view' then Continue;
    if Length(FGraphForce) <= si then SetLength(FGraphForce, si + 1);
    { THE WHOLE PASS IS THE PURE UNIT'S, so the suite drives the same path this
      does rather than a copy of it. }
    solved := TyGraphSolve(FOption, si, store, FLastRect, FGraphForce[si]);
    FGraphs[i] := solved.View;
    FGraphLaidOut[i] := True;
    FGraphSpecs[i] := solved.Spec;
    FGraphNodes[i] := solved.Nodes;
    FGraphEdges[i] := solved.Edges;
    FGraphCats[i] := solved.Cats;
  end;
  if APPI < 0 then ;
end;

function TTyAdvanceChart.GraphNodeName(ASlot, ANode: Integer): string;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FGraphNodes)) or (ASlot > High(FStores))
    or (FStores[ASlot] = nil) then Exit;
  if (ANode < 0) or (ANode > High(FGraphNodes[ASlot])) then Exit;
  if FGraphNodes[ASlot][ANode].Row < 0 then Exit;
  Result := FStores[ASlot].GetItemName(FGraphNodes[ASlot][ANode].Row);
end;

function TTyAdvanceChart.GraphInk(ASlot: Integer): TTyGraphInk;
var
  i, si: Integer;
  base: TTyChartColor;
  cols: TTyGraphCatColours;
  store: TTyDataStore;
begin
  Result := Default(TTyGraphInk);
  Result.LabelValueDim := -1;
  if (ASlot < 0) or (ASlot > High(FGraphNodes)) then Exit;
  base := TTyChartColor(SeriesColor(FBindings[ASlot].SeriesIndex));
  Result.EdgeColour := FGraphSpecs[ASlot].LineColour;
  if not FGraphSpecs[ASlot].HasLineColour then
    { THE THEME'S OWN LINE, not the grey the option tree carries. Upstream's
      default is a fixed token and this library's rule is that a visual value
      comes from the theme -- so the token is replaced here, where a theme can
      be seen, rather than in the pure unit. }
    Result.EdgeColour := TTyChartColor(
      ActiveController.Model.ResolveStyle('TyAdvChartSplitLine', '',
        []).BorderColor);

  { THREE SOURCES, NEAREST FIRST: what the node wrote, then its category's
    colour, then the series' own. The category's comes from the ONE table the
    legend's chips read too -- it used to index a per-NODE palette by the
    CATEGORY number, which agreed with the chips by coincidence and let the
    first few nodes' own colours leak into whole categories. }
  si := FBindings[ASlot].SeriesIndex;
  cols := Default(TTyGraphCatColours);
  if (si >= 0) and (si <= High(FGraphCatColours)) then
    cols := FGraphCatColours[si];
  store := nil;
  if ASlot <= High(FStores) then store := FStores[ASlot];
  SetLength(Result.NodeFills, Length(FGraphNodes[ASlot]));
  SetLength(Result.EdgeEndFills, Length(FGraphNodes[ASlot]));
  for i := 0 to High(FGraphNodes[ASlot]) do
    Result.NodeFills[i] := TyGraphNodeFill(FGraphNodes[ASlot][i], cols,
      Length(FGraphCats[ASlot]), base, store, Result.EdgeEndFills[i]);

  { A NODE'S LABEL IS ITS NAME, and the graph is the only series here whose
    default formatter says so: `label.formatter: '{b}'` is in its own
    defaultOption -- a TEMPLATE, so a name is read the way formatTpl reads it.
    Being a default, the option can take it away: `formatter: null` stays
    null through upstream's merge, and a node then shows what every other
    series shows, its VALUE (on a cartesian graph, the value axis' column). }
  Result.Label_ := LabelSpecFor(ASlot, '{b}');
  Result.Label_.DefaultText := tldValue;
  Result.SeriesName := SeriesNameOf(FBindings[ASlot].SeriesIndex);
  { THE c PLACEHOLDER IS THE VALUE COLUMN on a view and the value AXIS' column on axes,
    where there is no column called value at all. }
  if (ASlot <= High(FStores)) and (FStores[ASlot] <> nil) then
  begin
    if FBindings[ASlot].ValueAxis <> nil then
      Result.LabelValueDim :=
        FStores[ASlot].DimIndexOf(FBindings[ASlot].ValueAxis.Dim)
    else
      Result.LabelValueDim := FStores[ASlot].DimIndexOf('value');
  end;
end;

procedure TTyAdvanceChart.SolveRadars(APPI: Integer);
var
  i, j, k, n, dim, slot: Integer;
  spec: TTyRadarSpec;
  lo, hi, v, dLo, dHi: Double;
  seen: Boolean;
begin
  FreeRadars;
  SetLength(FRadarDims, Length(FBindings));
  for i := 0 to High(FRadarDims) do FRadarDims[i] := nil;
  n := 0;
  if FOption <> nil then n := FOption.ComponentCount('radar');
  if n = 0 then Exit;
  SetLength(FRadars, n);
  for i := 0 to n - 1 do
  begin
    spec := TyRadarSpecOf(FOption, i);
    FRadars[i] := TTyRadar.Create(spec);
    { FLastRect, and there is nothing between it and the radar: a radar's
      option carries no left/top/right/bottom at all, so nothing can shrink
      the canvas under it. }
    FRadars[i].Resize(FLastRect, APPI);
  end;

  { ---- which store column feeds which spoke ---- }
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].RadarIndex < 0 then Continue;
    if FBindings[i].RadarIndex > High(FRadars) then Continue;
    if i > High(FStores) then Break;
    if FStores[i] = nil then Continue;
    SetLength(FRadarDims[i], FRadars[FBindings[i].RadarIndex].AxisCount);
    for j := 0 to High(FRadarDims[i]) do
      FRadarDims[i][j] := FStores[i].DimIndexOf(TyRadarDimPrefix + IntToStr(j));
  end;

  { ---- every spoke's value range ---- }
  for k := 0 to High(FRadars) do
  begin
    spec := FRadars[k].Spec;
    for j := 0 to FRadars[k].AxisCount - 1 do
    begin
      { THE UNION OVER EVERY SERIES ON THIS RADAR, and it is collected here
        because nothing else is in a position to: TyApplyAxisExtents walks the
        cartesian grids' axis lists and a spoke is in neither. }
      dLo := NaN;
      dHi := NaN;
      seen := False;
      for i := 0 to High(FBindings) do
      begin
        if FBindings[i].RadarIndex <> k then Continue;
        { AN EQUIVALENT MUTANT TODAY, recorded rather than removed. A radar's
          legend names its ROWS, so switching one off filters the store and
          the loop below never sees it -- `Hidden` is only ever set for a
          series whose legend entry is the series itself, which a radar's
          never is. The guard is what the rule SAYS, and it stops being
          equivalent the day anything else can hide a whole radar series. }
        if FBindings[i].Hidden then Continue;
        if i > High(FStores) then Break;
        if FStores[i] = nil then Continue;
        if j > High(FRadarDims[i]) then Continue;
        dim := FRadarDims[i][j];
        if (dim < 0) or (dim >= FStores[i].DimCount) then Continue;
        for slot := 0 to FStores[i].Count - 1 do
        begin
          v := FStores[i].Get(dim, slot);
          if IsNan(v) or IsInfinite(v) then Continue;
          if not seen then
          begin
            dLo := v;
            dHi := v;
            seen := True;
          end
          else
          begin
            if v < dLo then dLo := v;
            if v > dHi then dHi := v;
          end;
        end;
      end;
      TyRadarIndicatorExtent(spec.Indicators[j], dLo, dHi, spec.Scale_, lo, hi);
      FRadars[k].SetAxisExtent(j, lo, hi);
    end;
  end;
end;

function TTyAdvanceChart.RadarInk: TTyRadarInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  Result := TyRadarInk;
  model := ActiveController.Model;
  { THE SPOKES AND THE RINGS ARE AN AXIS AND ITS SPLIT LINES, whatever the
    option calls them, so they take the keys an axis already has. }
  Result.AxisLine := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisLine', '', []).BorderColor);
  Result.SplitLine := TTyChartColor(
    model.ResolveStyle('TyAdvChartSplitLine', '', []).BorderColor);
  Result.Tick := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisTick', '', []).BorderColor);
  { THE ALTERNATING BANDS. Upstream writes a pale tint and a transparent one,
    so every other band shows the ground through it -- the split-area key is
    already alpha over the ink and says exactly that, and its partner is
    nothing at all. }
  Result.SplitAreaA := TTyChartColor(
    model.ResolveStyle('TyAdvChartSplitArea', '', []).Background.Color);
  Result.SplitAreaB := 0;
  st := model.ResolveStyle('TyAdvChartAxisName', '', []);
  Result.NameColour := TTyChartColor(st.TextColor);
  Result.NameFontName := st.FontName;
  Result.NameFontSizeLogical := ResolveFontSize(st);
  Result.NameFontWeight := st.FontWeight;
  st := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  Result.LabelFontName := st.FontName;
  Result.LabelFontSizeLogical := ResolveFontSize(st);
  Result.LabelFontWeight := st.FontWeight;
  Result.Z := 0;
end;

function TTyAdvanceChart.RadarVisual(ASlot: Integer): TTyRadarVisual;
var
  node: TJSONObject;
  d: TJSONData;
  ls, ar: TJSONObject;
  c: TTyChartColor;
begin
  Result := TyRadarVisual(SeriesColor(ASlot));
  Result.Fills := PerDatumColours(ASlot);
  Result.EmptyFill := TTyChartColor(
    ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
  Result.Symbol := SymbolFor(ASlot);
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('lineStyle');
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    ls := TJSONObject(d);
    d := ls.Find('width');
    if (d <> nil) and (d.JSONType = jtNumber) then
      Result.LineWidthLogical := d.AsFloat;
    d := ls.Find('color');
    if (d <> nil) and (d.JSONType = jtString)
      and TyTryParseChartColor(d.AsString, c) then Result.Fill := c;
  end;
  { AN AREA ONLY WHEN THE AUTHOR ASKED FOR ONE, and `areaStyle: {}` counts as
    asking -- upstream's test is whether the option object exists at all, not
    whether it has anything in it. That is why an empty object is the documented
    way to fill a radar. }
  d := node.Find('areaStyle');
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    Result.HasArea := True;
    Result.Area := Result.Fill;
    ar := TJSONObject(d);
    d := ar.Find('color');
    if (d <> nil) and (d.JSONType = jtString)
      and TyTryParseChartColor(d.AsString, c) then
    begin
      Result.Area := c;
      Result.AreaAuthored := True;
    end;
    d := ar.Find('opacity');
    if (d <> nil) and (d.JSONType = jtNumber) then
      Result.AreaOpacity := Max(Double(0), Min(Double(1), d.AsFloat));
  end;
end;

procedure TTyAdvanceChart.SolveGauges(APPI: Integer);
var
  i: Integer;
begin
  SetLength(FGauges, Length(FBindings));
  SetLength(FGaugeSpecs, Length(FBindings));
  SetLength(FGaugeItems, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FGauges[i] := Default(TTyGaugeLayout);
    FGaugeSpecs[i] := TyGaugeSpecDefault;
    FGaugeItems[i] := nil;
    if i > High(FStores) then Break;
    if not FBindings[i].Resolved then Continue;
    if FBindings[i].SeriesType <> TyGaugeSeriesTypeName then Continue;
    FGaugeSpecs[i] := TyGaugeSpecOf(FOption, FBindings[i].SeriesIndex);
    FGaugeItems[i] := TyGaugeItemsOf(FOption, FBindings[i].SeriesIndex,
      FGaugeSpecs[i]);
    { FLastRect, and unlike the pie and the funnel there is no box between the
      two: a gauge resolves its centre against the CONTROL's width and height
      and its radius against half the shorter side. Its `center` is the only
      thing that moves it. }
    FGauges[i] := TyGaugeLayoutOf(FGaugeSpecs[i], FLastRect, APPI);
  end;
end;

function TTyAdvanceChart.GaugeVisual(ASlot: Integer): TTyGaugeVisual;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
  f: TTyTitleFont;
begin
  Result := TyGaugeVisual;
  Result.Fills := PerDatumColours(ASlot);
  model := ActiveController.Model;
  { THE TRACK IS THE RING A PIE DRAWS WITH NO DATA. Upstream writes a literal
    pale grey, which is a pale grey ring on a dark skin; the same key the empty
    pie uses is alpha over the ink and follows either mode. }
  Result.Track := TTyChartColor(
    model.ResolveStyle('TyAdvChartEmptyCircle', '', []).Background.Color);
  { A GAUGE'S SPLIT LINE IS A MAJOR TICK and its axisTick is a minor one --
    which is what they ARE, whatever the option calls them, so they take the
    axis' own two keys rather than a pair of their own. }
  Result.SplitLine := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisTick', '', []).BorderColor);
  Result.Tick := TTyChartColor(
    model.ResolveStyle('TyAdvChartMinorTick', '', []).BorderColor);
  st := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  Result.LabelFontName := st.FontName;
  Result.LabelFontSizeLogical := ResolveFontSize(st);
  Result.LabelFontWeight := st.FontWeight;
  f := TitleFont('TyAdvChartLabel');
  st := model.ResolveStyle('TyAdvChartLabel', '', []);
  Result.TitleColour := TTyChartColor(st.TextColor);
  Result.TitleFontName := f.Name;
  Result.TitleFontSizeLogical := f.SizeLogical;
  Result.TitleFontWeight := f.Weight;
  { THE READING IS THE ONE NEW KEY THIS SERIES NEEDED. Nothing in the existing
    vocabulary is a big bold number: the chart's own title key is bold but is
    sized from the title scale, and a gauge's reading is the headline of the
    picture rather than a heading over it. }
  f := TitleFont('TyAdvChartGaugeDetail');
  st := model.ResolveStyle('TyAdvChartGaugeDetail', '', []);
  Result.DetailColour := TTyChartColor(st.TextColor);
  Result.DetailFontName := f.Name;
  Result.DetailFontSizeLogical := f.SizeLogical;
  Result.DetailFontWeight := f.Weight;
  { The hub is the chart's own ground with the accent around it, which is what
    upstream's white-on-theme-blue means said in this vocabulary. }
  Result.AnchorFill := TTyChartColor(
    model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]).Background.Color);
  Result.AnchorBorder := TTyChartColor(ThemeRampColor(0));
end;

function TTyAdvanceChart.FunnelVisual(ASlot: Integer): TTyFunnelVisual;
var st: TTyStyleSet;
begin
  Result := TyFunnelVisual;
  Result.Fills := PerDatumColours(ASlot);
  { THE BAND'S OUTLINE IS THE CHART'S OWN GROUND, which is what separates two
    adjacent bands of nearly the same colour. Upstream writes neutral00 -- its
    white -- and on a dark skin that is a white grid over a dark funnel; the
    surface colour is the same idea said in this vocabulary. }
  st := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
    [tysNormal]);
  Result.Stroke := TTyChartColor(st.Background.Color);
  Result.StrokeWidthLogical := 1;
end;

function TTyAdvanceChart.FunnelLabelInk: TTyFunnelLabelInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartLabel', '', []);
  Result.FontName := st.FontName;
  Result.FontSizeLogical := ResolveFontSize(st);
  Result.FontWeight := st.FontWeight;
  Result.OutsideColour := TTyChartColor(st.TextColor);
  { THE SAME THREE BANDS THE PIE AND THE MARKS USE. Not a second table: a
    label over a coloured shape is one question however the shape was made. }
  Result.InsideColour[0] := TTyChartColor(
    model.ResolveStyle('TyAdvChartLabelOnLight', '', []).TextColor);
  Result.InsideColour[1] := TTyChartColor(
    model.ResolveStyle('TyAdvChartLabelOnMid', '', []).TextColor);
  Result.InsideColour[2] := TTyChartColor(
    model.ResolveStyle('TyAdvChartLabelOnDark', '', []).TextColor);
end;

function TTyAdvanceChart.PerDatumColours(ASlot: Integer): TTyChartColorArray;
var
  k, rawN: Integer;
  c: TTyChartColor;
  ov: TTyDataValue;
  pal: TTyChartColorArray;
  cur: TTyPaletteCursor;
  declared: Boolean;
  nm: string;
begin
  { colorBy: 'data'. Each DATUM takes the next slot of the same nine-colour
    ramp a bar series cycles across series -- which is what makes a pie or a
    funnel read at all, and what makes it re-skin with the accent like
    everything else.

    KEYED ON THE DATUM'S NAME, so two charts over the same categories agree
    about which category is which colour, and a repeated name inside one chart
    shares a colour rather than taking a second slot. }
  Result := nil;
  pal := TyChartPaletteOf(FOption, ASlot, declared);
  if Length(pal) = 0 then pal := TyChartPaletteOf(FOption, -1, declared);
  cur := TyPaletteStart(pal);
  rawN := 0;
  if (ASlot <= High(FStores)) and (FStores[ASlot] <> nil) then
    rawN := FStores[ASlot].RawCount;
  SetLength(Result, rawN);
  for k := 0 to rawN - 1 do
  begin
    Result[k] := TTyChartColor(ThemeRampColor(k));
    if Length(pal) = 0 then Continue;
    nm := FStores[ASlot].GetNameByRaw(k);
    if nm = '' then nm := IntToStr(k);
    if TyPaletteTake(cur, nm, c) then Result[k] := c;
  end;
  { AND A DATUM THAT NAMED ITS OWN COLOUR KEEPS IT. `data: [{ value: 5,
    itemStyle: { color: '#c23531' } }]` is the commonest thing anybody writes
    on either chart, and it beats the ramp -- the same rule a bar follows,
    reached through the same parked override. }
  for k := 0 to rawN - 1 do
    if FStores[ASlot].HasOverrideByRaw(k, TyOverrideKey('itemStyle.color')) then
    begin
      ov := FStores[ASlot].GetOverrideByRaw(k, TyOverrideKey('itemStyle.color'));
      if (ov.Kind = dvkText) and TyTryParseChartColor(ov.Text, c) then
        Result[k] := c;
    end;
end;

function TTyAdvanceChart.PieVisual(ASlot: Integer): TTyPieVisual;
var
  k, n, raw: Integer;
  perRaw: TTyChartColorArray;
begin
  Result := TyPieVisual(0);
  { colorBy:''data''. Each SECTOR takes the next slot of the same nine-colour
    ramp a bar series cycles across series -- which is what makes a pie read
    at all, and what makes it re-skin with the accent like everything else.

    A SLICE THAT NAMED ITS OWN COLOUR KEEPS IT. `data: [{ value: 5,
    itemStyle: { color: ''#c23531'' } }]` is the commonest thing anybody
    writes on a pie, and it beats the ramp -- the same rule a bar follows,
    reached through the same parked override. }
  { ONE COLOUR PER RAW ROW, TAKEN IN RAW ORDER, before a single sector is
    looked at. A slice that was filtered out -- a negative value, a legend
    click -- still consumes its slot, which is the only way the surviving
    slices keep the colours they had. Upstream iterates its raw data here for
    the same reason and says so in a comment.

    Keyed on the slice's NAME, so two pies over the same categories agree
    about which category is which colour -- and so a repeated name inside one
    pie shares a colour rather than taking a second slot. }
  perRaw := PerDatumColours(ASlot);

  n := Length(FPies[ASlot].Sectors);
  if n < 1 then n := 1;
  SetLength(Result.Fills, n);
  for k := 0 to n - 1 do
  begin
    { KEYED ON THE RAW ROW, NOT THE SECTOR. The two are the same number only
      while nothing has been dropped -- and something already is: a negative
      value is filtered out before the layout runs, and now a legend can
      filter more. Key the ramp on the sector's position and every surviving
      slice changes colour the moment a neighbour leaves, which is the one
      failure of this commit a reader would notice immediately.

      Upstream says the same thing in a comment written for the same reason:
      `Iterate on data before filtered. To make sure color from palette can
      be consistent when toggling legend.` (visual/style.ts:207-208). }
    if k <= High(FPies[ASlot].Sectors) then
    begin
      raw := FPies[ASlot].Sectors[k].RawIndex;
      if (raw >= 0) and (raw <= High(perRaw)) then
        Result.Fills[k] := perRaw[raw]
      else
        Result.Fills[k] := TTyChartColor(ThemeRampColor(raw));
    end
    else
      Result.Fills[k] := TTyChartColor(ThemeRampColor(k));
  end;
  { The empty ring has its own token rather than borrowing the split area''s:
    they are faint for different reasons and a theme has to be able to move
    one without the other. }
  Result.EmptyFill := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartEmptyCircle', '',
      []).Background.Color);
end;

procedure TTyAdvanceChart.PaintTitles(APainter: TTyPainter);
var
  i: Integer;
  st, subSt: TTyStyleSet;
  lay: TTyTitleLayout;

  { The box DrawText wants, hung off an anchor with the title's alignment.
    The same job AnchorBox does for an axis label; kept local because the two
    take their alignment from different enums and one shared helper would take
    an argument nobody could read at the call site. }
  function Hang(AX, AY, AW, AH: Double; AAlign: TTyTitleAlign;
    AVAlign: TTyTitleVAlign): TRect;
  begin
    case AAlign of
      ttaCentre: Result.Left := Round(AX - AW / 2);
      ttaRight: Result.Left := Round(AX - AW);
    else
      Result.Left := Round(AX);
    end;
    Result.Right := Result.Left + Round(AW);
    case AVAlign of
      ttvMiddle: Result.Top := Round(AY - AH / 2);
      ttvBottom: Result.Top := Round(AY - AH);
    else
      Result.Top := Round(AY);
    end;
    Result.Bottom := Result.Top + Round(AH);
  end;

  function LclAlign(AAlign: TTyTitleAlign): TAlignment;
  begin
    case AAlign of
      ttaCentre: Result := taCenter;
      ttaRight: Result := taRightJustify;
    else
      Result := taLeftJustify;
    end;
  end;

begin
  if Length(FTitles) = 0 then Exit;
  st := ActiveController.Model.ResolveStyle('TyAdvChartTitle', '', []);
  subSt := ActiveController.Model.ResolveStyle('TyAdvChartSubtitle', '',
    []);
  for i := 0 to High(FTitles) do
  begin
    lay := FTitles[i];
    if not lay.Valid then Continue;
    { The frame first, and only when the option asked for one: ECharts gives
      the title a transparent background by default, and painting the surface
      colour instead would put a visible plate behind every title on an image
      theme. }
    if FTitleSpecs[i].HasBackground then
      APainter.FillBackground(
        Rect(Round(lay.Frame.Left), Round(lay.Frame.Top),
             Round(lay.Frame.Right), Round(lay.Frame.Bottom)),
        st.Background, Round(FTitleSpecs[i].BorderRadii[0]));
    if FTitleSpecs[i].Text <> '' then
      APainter.DrawText(
        Hang(lay.TextX, lay.TextY, lay.TextW, lay.TextH, lay.Align, lay.VAlign),
        FTitleSpecs[i].Text, st.FontName, ResolveFontSize(st), st.FontWeight,
        st.TextColor, LclAlign(lay.Align), tlTop, False, 0, False,
        Pos(#10, FTitleSpecs[i].Text) > 0);
    if lay.HasSub then
      APainter.DrawText(
        Hang(lay.SubX, lay.SubY, lay.SubW, lay.SubH, lay.Align, lay.VAlign),
        FTitleSpecs[i].Subtext, subSt.FontName, ResolveFontSize(subSt),
        subSt.FontWeight, subSt.TextColor, LclAlign(lay.Align), tlTop, False,
        0, False, Pos(#10, FTitleSpecs[i].Subtext) > 0);
  end;
end;


function TTyAdvanceChart.SeriesNameOf(ASlot: Integer): string;
var
  d: TJSONData;
  node: TJSONObject;
  i, ds: Integer;
begin
  Result := '';
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASlot);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('name');
  if (d <> nil) and (d.JSONType = jtString) then Exit(d.AsString);
  { A NUMBER IS A NAME TOO -- convertOptionIdName, `'' + name` -- so a
    series called 2015 is headed and listed as 2015, not as nobody. }
  if (d <> nil) and (d.JSONType = jtNumber) then
    Exit(TyJsNumberToString(d.AsFloat));

  { A SERIES READING A TABLE NAMES ITSELF AFTER THE COLUMN IT TOOK. That is
    how three bars on one dataset end up called 2015, 2016 and 2017 in a
    legend nobody wrote entries for -- and without it those three legends
    have nothing to list. The column is the one the encode put the series'
    own name on, which the default encode sets to whichever column is not
    the shared category. }
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].SeriesIndex <> ASlot then Continue;
    if i > High(FEncodes) then Exit;
    ds := -1;
    if i <= High(FSeriesDataset) then ds := FSeriesDataset[i];
    if (ds < 0) or (i > High(FSources)) then Exit;
    if FEncodes[i].SeriesName < 0 then Exit;
    Exit(TySourceDimName(FSources[i], FEncodes[i].SeriesName));
  end;
end;

{ ==================== legend ==================== }

{ TWO LISTS, and they are deliberately different.

  POTENTIAL is what a legend with no `data` of its own falls back to: a pie
  contributes its SLICE names and everything else contributes its own, and an
  unnamed series contributes NOTHING -- upstream gives it a private dummy name
  that no legend entry can be written to match, so the effect is the same and
  an empty string is the honest way to say it here.

  AVAILABLE is what a name is allowed to match. Every name the chart can
  produce is in it, and an entry that is NOT in it reads as switched off
  however `legend.selected` is written -- which is what greys out a
  `legend.data` entry naming a series nobody declared. }
procedure TTyAdvanceChart.LegendNames(out APotential, AAvailable: TTyLegendNames);
var
  i, k, np, na: Integer;
  nm: string;
  cats: TTyGraphCategoryArray;

  { AKeepEmpty is a graph category's: a nameless category IS a name upstream,
    `''`, which the legend draws as a line break and single mode can pick. }
  procedure PushP(const AName: string; AKeepEmpty: Boolean = False);
  begin
    if (AName = '') and not AKeepEmpty then Exit;
    if np >= Length(APotential) then SetLength(APotential, np * 2 + 8);
    APotential[np] := AName;
    Inc(np);
  end;

  procedure PushA(const AName: string; AKeepEmpty: Boolean = False);
  begin
    if (AName = '') and not AKeepEmpty then Exit;
    if na >= Length(AAvailable) then SetLength(AAvailable, na * 2 + 8);
    AAvailable[na] := AName;
    Inc(na);
  end;

begin
  APotential := nil;
  AAvailable := nil;
  np := 0;
  na := 0;
  for i := 0 to High(FBindings) do
  begin
    { A GRAPH OFFERS ITS CATEGORIES, and its own name only as AVAILABLE --
      the same shape as a pie's slices. With no categories at all it is an
      ordinary series and offers its name. The categories come from the
      OPTION, never from a solved graph: this runs in Rebuild, before any
      graph is solved. }
    if FBindings[i].SeriesType = TyGraphSeriesTypeName then
    begin
      cats := TyGraphCategoriesOf(FOption, FBindings[i].SeriesIndex);
      if Length(cats) > 0 then
      begin
        PushA(SeriesNameOf(FBindings[i].SeriesIndex));
        for k := 0 to High(cats) do
        begin
          PushP(cats[k].Name_, True);
          PushA(cats[k].Name_, True);
        end;
        Continue;
      end;
    end;
    if TySeriesLegendByDatum(FBindings[i].SeriesType)
      and (i <= High(FStores)) and (FStores[i] <> nil) then
    begin
      { ITS ROW NAMES ARE WHAT THE LEGEND OFFERS, but its own name is still
        AVAILABLE -- upstream pushes every raw series' name into that list
        unconditionally, before it ever looks at a provider. The difference
        shows when an author writes the pie's own name into `legend.data`:
        with the name available the entry is live, and without it the entry
        would grey out for a reason that has nothing to do with the option. }
      PushA(SeriesNameOf(FBindings[i].SeriesIndex));
      for k := 0 to FStores[i].Count - 1 do
      begin
        nm := FStores[i].GetName(k);
        PushP(nm);
        PushA(nm);
      end;
      Continue;
    end;
    nm := SeriesNameOf(FBindings[i].SeriesIndex);
    PushP(nm);
    PushA(nm);
  end;
  SetLength(APotential, np);
  SetLength(AAvailable, na);
end;

function TTyAdvanceChart.SeriesSymbolWord(ASlot: Integer): string;
var
  d: TJSONData;
  node: TJSONObject;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('symbol');
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function TTyAdvanceChart.LegendSources(const AEntries: TTyLegendEntryArray):
  TTyLegendSourceArray;
var
  i, j, k, si: Integer;
  found: Boolean;
  perRaw: TTyChartColorArray;
  cats: TTyGraphCategoryArray;
begin
  SetLength(Result, Length(AEntries));
  for i := 0 to High(AEntries) do
  begin
    Result[i] := Default(TTyLegendSource);
    if AEntries[i].Newline then Continue;
    found := False;
    { A SERIES NAME WINS OVER A SLICE NAME, because upstream asks
      getSeriesByName first and only falls to the per-datum providers when
      nothing answered. }
    for j := 0 to High(FBindings) do
    begin
      if TySeriesLegendByDatum(FBindings[j].SeriesType) then Continue;
      if SeriesNameOf(FBindings[j].SeriesIndex) <> AEntries[i].Name then
        Continue;
      Result[i].Found := True;
      Result[i].SeriesType := FBindings[j].SeriesType;
      Result[i].Colour := TTyChartColor(SeriesColor(FBindings[j].SeriesIndex));
      Result[i].DefaultIcon := TyLegendDefaultIcon(FBindings[j].SeriesType,
        SeriesSymbolWord(j));
      Result[i].OwnIcon := TyLegendDrawsOwnIcon(FBindings[j].SeriesType);
      Result[i].LineColour := Result[i].Colour;
      { THE SAME 2 THE LINE ITSELF FALLS BACK TO in BuildLine, which is also
        what `lineStyle.width: 'auto'` resolves to upstream. When series line
        widths become an option the two will read it from one place; until
        then they agree by saying the same thing. }
      if Result[i].OwnIcon then
        Result[i].LineWidthLogical := 2;
      found := True;
      Break;
    end;
    if found then Continue;
    for j := 0 to High(FBindings) do
    begin
      { A GRAPH'S CATEGORY, AT THE GRAPH'S PLACE IN SERIES ORDER -- so a name
        that is both a pie slice and a category is drawn by whichever series
        comes first, and a name two categories share by the FIRST of them. A
        rounded rectangle in the category's colour: the category provider
        publishes no icon, and the category's `symbol` is its nodes', not its
        chip's. }
      if FBindings[j].SeriesType = TyGraphSeriesTypeName then
      begin
        si := FBindings[j].SeriesIndex;
        cats := TyGraphCategoriesOf(FOption, si);
        for k := 0 to High(cats) do
          if cats[k].Name_ = AEntries[i].Name then
          begin
            Result[i].Found := True;
            Result[i].SeriesType := FBindings[j].SeriesType;
            Result[i].DefaultIcon := '';
            Result[i].OwnIcon := False;
            if FBindings[j].Hidden then
              Result[i].Greyed := True
            else if (si <= High(FGraphCatColours))
              and (k <= High(FGraphCatColours[si].Known))
              and FGraphCatColours[si].Known[k] then
            begin
              Result[i].Colour := FGraphCatColours[si].Colours[k];
              { A TRANSPARENT CATEGORY IS SHOWN AT A FIFTH, not as nothing --
                upstream's legend rescues an alpha of zero to 0.2 so the item
                can still be found. The nodes stay transparent. }
              if (LongWord(Result[i].Colour) shr 24) = 0 then
                Result[i].Colour := TTyChartColor(
                  (LongWord(Result[i].Colour) and $00FFFFFF) or $33000000);
            end
            else if (si <= High(FGraphCatColours))
              and (k <= High(FGraphCatColours[si].Base))
              and FGraphCatColours[si].Base[k] then
              { A colour nobody can paint: the chip wears the series colour,
                as the nodes do. }
              Result[i].Colour := TTyChartColor(SeriesColor(si));
            Result[i].LineColour := Result[i].Colour;
            found := True;
            Break;
          end;
        if found then Break;
        Continue;
      end;
      if not TySeriesLegendByDatum(FBindings[j].SeriesType) then Continue;
      if (j > High(FStores)) or (FStores[j] = nil) then Continue;
      { THE RAW ROWS, NOT THE VIEW. This runs in Relayout, which is to say
        AFTER the filter has already taken the switched-off slices out of
        the store -- and those are exactly the slices whose legend items we
        are here to describe. Walking the view would find every item except
        the ones that were switched off.

        AN EQUIVALENT MUTANT LIVES HERE and is recorded rather than chased:
        walking the view instead draws the same picture TODAY, because the
        only items it would fail to find are the switched-off ones, and a
        switched-off item takes the inactive ink and the roundRect floor --
        neither of which comes from here. It stops being equivalent the
        moment a greyed item keeps anything of its own, and being wrong for
        an invisible reason is still being wrong.

        colorBy: 'data' -- a slice's colour is the same eight-slot ramp,
        keyed on the same RAW row PieVisual keys on, so the swatch and the
        wedge cannot disagree. }
      perRaw := PerDatumColours(j);
      for k := 0 to FStores[j].RawCount - 1 do
        if FStores[j].GetNameByRaw(k) = AEntries[i].Name then
        begin
          Result[i].Found := True;
          Result[i].SeriesType := FBindings[j].SeriesType;
          { THE SAME PALETTE THE MARKS USE, asked the same way. It read the
            ramp directly by row while the marks went through the shared
            per-datum rule, so an authored `color` list or a datum's own
            itemStyle moved the wedge and left the swatch behind. }
          if k <= High(perRaw) then
            Result[i].Colour := perRaw[k]
          else
            Result[i].Colour := TTyChartColor(SeriesColor(k));
          Result[i].LineColour := Result[i].Colour;
          Result[i].DefaultIcon := TyLegendDefaultIcon(
            FBindings[j].SeriesType, SeriesSymbolWord(j));
          Result[i].OwnIcon := TyLegendDrawsOwnIcon(FBindings[j].SeriesType);
          if Result[i].OwnIcon then Result[i].LineWidthLogical := 2;
          found := True;
          Break;
        end;
      if found then Break;
    end;
  end;
end;

procedure TTyAdvanceChart.SolveLegendData;
var
  i, n: Integer;
  potential, available: TTyLegendNames;
begin
  n := TyLegendCount(FOption);
  SetLength(FLegendSpecs, n);
  SetLength(FLegendEntries, n);
  SetLength(FLegendFlags, n);
  SetLength(FLegends, n);
  FLegendAvailable := nil;
  if n = 0 then Exit;
  LegendNames(potential, available);
  FLegendAvailable := available;
  for i := 0 to n - 1 do
  begin
    FLegendSpecs[i] := TyLegendSpecOf(FOption, i);
    FLegendEntries[i] := TyLegendEntries(FOption, i, potential);
    FLegendFlags[i] := TyLegendSelected(FOption, i, FLegendEntries[i],
      available, FLegendSpecs[i].SelectedMode);
    FLegends[i] := Default(TTyLegendLayout);
  end;
end;

{ A name is switched off when ANY legend says so -- legendFilter.ts:36-41.
  Nothing is switched off when there is no legend at all, which is why a
  chart without one is untouched by any of this. }
function TTyAdvanceChart.LegendHides(const AName: string): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(FLegendSpecs) do
    if TyLegendHides(FOption, i, FLegendEntries[i], FLegendFlags[i], AName) then
      Exit(True);
end;

function TTyAdvanceChart.KeepSlice(ARawIndex: Integer): Boolean;
begin
  Result := True;
  if FFilterStore = nil then Exit;
  Result := not LegendHides(FFilterStore.GetNameByRaw(ARawIndex));
end;

function TTyAdvanceChart.KeepGraphNode(ARawIndex: Integer): Boolean;
var
  v: TTyDataValue;
  i: Integer;
  nm: string;
begin
  Result := True;
  if FFilterStore = nil then Exit;
  { `category == null` KEEPS THE NODE -- absent and null alike. }
  if not FFilterStore.HasOverrideByRaw(ARawIndex, TyOverrideKey('category')) then
    Exit;
  v := FFilterStore.GetOverrideByRaw(ARawIndex, TyOverrideKey('category'));
  case v.Kind of
    dvkNone: Exit;
    dvkNumber:
      { `categoryNames[n]`: a JavaScript array indexed by the number, so an
        index out of range -- or negative, or fractional -- finds `undefined`,
        a name no legend offers. }
      { The range first: Frac of an infinity raises, and `1e999` parses as
        one. }
      if (v.Num >= 0) and (v.Num <= High(FFilterCats)) and (Frac(v.Num) = 0) then
        nm := FFilterCats[Trunc(v.Num)].Name_
      else
        Exit(False);
    dvkText:
      { A STRING IS ASKED ABOUT EXACTLY AS WRITTEN -- '1' is the name '1',
        not index one -- and against every name the CHART offers, so a node
        naming a series or another graph's category is kept, and goes when
        that name is switched off. }
      nm := v.Text;
  else
    { A boolean is never a name anything offers. }
    Exit(False);
  end;
  for i := 0 to High(FLegendSpecs) do
    if not TyLegendNameSelected(FOption, i, FLegendEntries[i], FLegendFlags[i],
      FLegendAvailable, nm) then
      Exit(False);
end;

procedure TTyAdvanceChart.ApplyLegendFilter;
var
  i, k: Integer;
  st: TTyDataStore;
  any: Boolean;
begin
  if Length(FLegendSpecs) = 0 then Exit;
  for i := 0 to High(FBindings) do
  begin
    { A GRAPH IS FILTERED TWICE: WHOLE, by its series name -- upstream's
      legendFilter runs on every series first -- and then, if it survived,
      node by node by CATEGORY. The second is upstream's categoryFilter, and
      its rule is not the series rule: it asks isSelected of every legend for
      every node that names a category, so a category switched off only in
      `selected` goes, and a node whose category the chart does not offer --
      an index past the end, a name nobody declared -- goes too, whenever any
      legend exists. With no legend at all nothing is filtered: this whole
      procedure has already returned. }
    if FBindings[i].SeriesType = TyGraphSeriesTypeName then
    begin
      FBindings[i].Hidden :=
        LegendHides(SeriesNameOf(FBindings[i].SeriesIndex));
      if FBindings[i].Hidden then Continue;
      if (i > High(FStores)) or (FStores[i] = nil) then Continue;
      st := FStores[i];
      FFilterCats := TyGraphCategoriesOf(FOption, FBindings[i].SeriesIndex);
      FFilterStore := st;
      try
        { ASKED BEFORE IT IS DONE, and with the graph's OWN rule: with a
          legend present a node can go even when every item is switched on,
          so the question is not "is anything off" but "does any node fail". }
        any := False;
        for k := 0 to st.RawCount - 1 do
          if not KeepGraphNode(k) then
          begin
            any := True;
            Break;
          end;
        if any then st.FilterSelf(@KeepGraphNode);
      finally
        FFilterStore := nil;
        FFilterCats := nil;
      end;
      Continue;
    end;
    if not TySeriesLegendByDatum(FBindings[i].SeriesType) then
    begin
      FBindings[i].Hidden :=
        LegendHides(SeriesNameOf(FBindings[i].SeriesIndex));
      Continue;
    end;
    { SUCH A SERIES IS FILTERED ONE ROW AT A TIME, because its legend names rows
      rather than series -- upstream's processor/dataFilter against this
      port's own TTyDataStore.FilterSelf, which is the same mechanism and
      has been sitting here unused since the store was written.

      It COMPOSES with the negative-value filter the pie layout applies
      later, and in upstream's order: the legend's filter is registered
      first and negativeDataFilter second (chart/pie/install.ts:35-37). }
    if (i > High(FStores)) or (FStores[i] = nil) then Continue;
    st := FStores[i];
    { ASKED BEFORE IT IS DONE, so a pie nobody switched anything off on
      keeps an UNFILTERED store -- which is not only cheaper but visible:
      a filtered store takes the slow path through its index vector in
      every extent and every read. }
    any := False;
    for k := 0 to st.RawCount - 1 do
      if LegendHides(st.GetNameByRaw(k)) then
      begin
        any := True;
        Break;
      end;
    if not any then Continue;
    FFilterStore := st;
    try
      st.FilterSelf(@KeepSlice);
    finally
      FFilterStore := nil;
    end;
  end;
end;

procedure TTyAdvanceChart.MultiValueDims(const ABinding: TTySeriesBinding;
  var ADims: TTySeriesDimArray);
var
  info: TTySeriesTypeInfo;
  i, n: Integer;
begin
  if (ABinding.BaseAxis = nil) or (ABinding.ValueAxis = nil) then Exit;
  if not TySeriesFindType(ABinding.SeriesType, info) then Exit;
  { `base` PLUS MORE THAN ONE VALUE is what makes a type multi-value, and the
    registry has said so since it was written -- a candlestick declares
    base/open/close/lowest/highest and a boxplot base/min/Q1/median/Q3/max.
    Anything declaring two or fewer is an ordinary pair and keeps the columns
    the coordinate system gave it. }
  n := Length(info.Dims);
  if (n < 3) or (info.Dims[0] <> 'base') then Exit;

  SetLength(ADims, n);
  { THE CATEGORY IS THE ROW NUMBER. Upstream's default encode for these types
    puts every element of the item on the value axis, which leaves the base
    axis nothing to read -- so it counts rows instead. The column keeps the
    base axis' own name and kind so category interning still works. }
  ADims[0].Name := ABinding.BaseAxis.Dim;
  if ABinding.BaseAxis.AxisType = atCategory then
  begin
    ADims[0].Kind := ddtOrdinal;
    ADims[0].Axis := ABinding.BaseAxis;
    ADims[0].FromRowIndex := True;
  end
  else if ABinding.BaseAxis.AxisType = atTime then
  begin
    ADims[0].Kind := ddtTime;
    ADims[0].Axis := nil;
    ADims[0].FromRowIndex := True;
  end
  else
  begin
    ADims[0].Kind := ddtFloat;
    ADims[0].Axis := nil;
    ADims[0].FromRowIndex := True;
  end;
  ADims[0].Coord := '';
  ADims[0].SourceSlot := 0;

  for i := 1 to n - 1 do
  begin
    ADims[i].Name := info.Dims[i];
    ADims[i].Kind := ddtFloat;
    ADims[i].Axis := nil;
    { ELEMENT i-1 OF THE ITEM: the base took no element at all, so the values
      start at the beginning of the row rather than one in from it. }
    ADims[i].SourceSlot := i;
    { AND EVERY ONE OF THEM FEEDS THE VALUE AXIS. This is the whole reason
      the store learned that a coordinate is a LIST of columns. }
    ADims[i].Coord := ABinding.ValueAxis.Dim;
  end;
end;

function TTyAdvanceChart.AxisDimOf(AAxis: TTyAxis): string;
begin
  if AAxis = nil then Result := '' else Result := AAxis.Dim;
end;

function TTyAdvanceChart.CandleVisual(ASlot: Integer): TTyCandleSpec;
var
  model: TTyStyleModel;
  up, down: TTyStyleSet;
  d: TTyCandleSpec;
begin
  model := ActiveController.Model;
  up := model.ResolveStyle('TyAdvChartCandleUp', '', []);
  down := model.ResolveStyle('TyAdvChartCandleDown', '', []);
  d := Default(TTyCandleSpec);
  d.Up := TTyChartColor(up.Background.Color);
  d.Down := TTyChartColor(down.Background.Color);
  { THE BORDER FOLLOWS THE BODY unless the theme said otherwise. Upstream's
    two defaults are the same pair of colours written twice, and a skin that
    wants an outlined candle sets `border-color` on these keys without having
    to restate the fill. }
  if tpBorderColor in up.Present then d.UpBorder := TTyChartColor(up.BorderColor)
  else d.UpBorder := d.Up;
  if tpBorderColor in down.Present then
    d.DownBorder := TTyChartColor(down.BorderColor)
  else d.DownBorder := d.Down;
  d.BorderWidthLogical := 1;
  if (tpBorderColor in up.Present) and (up.BorderWidth > 0) then
    d.BorderWidthLogical := up.BorderWidth;
  Result := TyCandleSpecOf(FOption, ASlot, d);
end;

function TTyAdvanceChart.LegendFont: TTyLegendFont;
var st: TTyStyleSet;
begin
  st := ActiveController.Model.ResolveStyle('TyAdvChartLegend', '', []);
  Result.Name := st.FontName;
  Result.SizeLogical := ResolveFontSize(st);
  Result.Weight := st.FontWeight;
end;

function TTyAdvanceChart.LegendInk: TTyLegendInk;
var model: TTyStyleModel;
begin
  model := ActiveController.Model;
  Result.Text := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegend', '', []).TextColor);
  Result.Inactive := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendInactive', '', []).TextColor);
  Result.Border := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendBorder', '', []).BorderColor);
  Result.Background := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendBackground', '', []).Background.Color);
  { The hole in a ring is the chart's own ground, the same substitution the
    mark builders make for a datum's `empty` marker. }
  Result.EmptyFill := TTyChartColor(
    model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
end;

procedure TTyAdvanceChart.SolveLegends(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i: Integer;
  fnt: TTyLegendFont;
begin
  if Length(FLegendSpecs) = 0 then Exit;
  fnt := LegendFont;
  for i := 0 to High(FLegendSpecs) do
    FLegends[i] := TyLayoutLegend(FLegendSpecs[i], FLegendEntries[i],
      FLegendFlags[i], LegendSources(FLegendEntries[i]), FLastRect,
      AMeasurer, fnt, APPI);
end;

function TTyAdvanceChart.BuildLegends(APPI: Integer;
  AList: TTyPaintList): Integer;
var
  i: Integer;
  ink: TTyLegendInk;
  fnt: TTyLegendFont;
begin
  Result := 0;
  if Length(FLegends) = 0 then Exit;
  ink := LegendInk;
  fnt := LegendFont;
  for i := 0 to High(FLegends) do
    Inc(Result, TyBuildLegendMarks(FLegendSpecs[i], FLegends[i], ink, fnt,
      APPI, AList));
end;

function TTyAdvanceChart.LabelSpecFor(ASlot: Integer): TTyLabelSpec;
begin
  Result := LabelSpecFor(ASlot, '');
end;

function TTyAdvanceChart.LabelSpecFor(ASlot: Integer;
  const ADefaultFormatter: string): TTyLabelSpec;
var
  base: TTyLabelSpec;
  outS, lightS, midS, darkS: TTyStyleSet;
begin
  base := TyLabelSpecNone;
  if ADefaultFormatter <> '' then
  begin
    base.Formatter := ADefaultFormatter;
    base.HasFormatter := True;
  end;
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight',
    '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '',
    []);
  base.FontName := outS.FontName;
  base.FontSizeLogical := ResolveFontSize(outS);
  base.FontWeight := outS.FontWeight;
  base.OutsideColour := TTyChartColor(outS.TextColor);
  base.InsideColour[0] := TTyChartColor(lightS.TextColor);
  base.InsideColour[1] := TTyChartColor(midS.TextColor);
  base.InsideColour[2] := TTyChartColor(darkS.TextColor);
  if ASlot > High(FBindings) then Exit(base);
  Result := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
end;

function TTyAdvanceChart.PieLabelInk: TTyPieLabelInk;
var
  outS, lightS, midS, darkS: TTyStyleSet;
begin
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight',
    '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '',
    []);
  Result.FontName := outS.FontName;
  Result.FontSizeLogical := ResolveFontSize(outS);
  Result.FontWeight := outS.FontWeight;
  Result.InsideColour[0] := TTyChartColor(lightS.TextColor);
  Result.InsideColour[1] := TTyChartColor(midS.TextColor);
  Result.InsideColour[2] := TTyChartColor(darkS.TextColor);
  Result.OutsideColour := TTyChartColor(outS.TextColor);
  { labelLine.lineStyle.width, PieSeries.ts:299 -- one logical pixel. }
  Result.LineWidthLogical := 1;
end;

function TTyAdvanceChart.BuildSeriesList(const AMeasurer: ITyTextMeasurer;
  APPI: Integer): Integer;
var
  list: TTyPaintList;
  i, drawn: Integer;
  v: TTySeriesVisual;
  pv: TTyPieVisual;
  fv: TTyFunnelVisual;
  gv: TTyGaugeVisual;
  gi: TTyGraphInk;
  specs: TTyLabelSpecArray;
begin
  Result := 0;
  { ONE LIST FOR EVERY SERIES, not one per series: the ordering rule is (Z, Z2,
    insertion) ACROSS the chart, and a list per series would order each one
    against itself and leave the between-series order to the loop. }
  if FPaintList = nil then FPaintList := TTyPaintList.Create
  else FPaintList.Clear;
  list := FPaintList;
  { BEFORE THE EARLY EXIT, not after -- and not because a stale list would
    otherwise be read: Clear has already run, so the answer would be "nothing"
    either way. It is here because a render that drew no series is still a
    render, and marking it invalid would say the chart has not drawn yet. The
    two are the same answer today and stop being it the moment a caller wants
    to tell "there is nothing there" from "there is nothing yet". }
  FPaintListPPI := APPI;
  FPaintListValid := True;
  { THE RADAR'S OWN FURNITURE, ONCE PER RADAR AND BEFORE ANY SERIES. It is not
    a series' geometry -- several series share one radar -- and it is not a
    cartesian axis either, so the grid painter never sees it. It goes into the
    same list because the ordering rule is chart-wide.

    Above the `Length(FBindings) = 0` early-out: a radar with its indicators
    written and no series at all is a legitimate chart, and an empty one is
    the first thing anybody sees while they are still typing. }
  drawn := 0;
  for i := 0 to High(FRadars) do
    Inc(drawn, TyBuildRadarGrid(FRadars[i], RadarInk, AMeasurer, APPI, list));
  if Length(FBindings) = 0 then Exit;
  begin
    for i := 0 to High(FBindings) do
    begin
      if i > High(FStores) then Break;
      { SWITCHED OFF, so nothing of it is drawn -- not its marks, not its
        labels (the expansion below only sees what reached the list), and
        not its wedges. The pie branch is inside this guard for the sake of
        the one case that can reach it: a `legend.data` entry naming the pie
        series itself. }
      if FBindings[i].Hidden then Continue;
      { A pie is not on a coordinate system, so it takes the other pass. It
        goes into the SAME list: the ordering rule is chart-wide, and a pie
        beside a bar has to sort against it like anything else. }
      { A FUNNEL IS NOT ON A COORDINATE SYSTEM EITHER, and like the pie it
        solves its own geometry in the layout pass and replays it here. }
      { A GRAPH IS ON A COORDINATE SYSTEM OF ITS OWN, and that system belongs
        to the series rather than to a component -- so it is solved in the
        layout pass like a pie's box and replayed here like a radar's. }
      if FBindings[i].SeriesType = TyGraphSeriesTypeName then
      begin
        if (i <= High(FGraphLaidOut)) and FGraphLaidOut[i] then
        begin
          gi := GraphInk(i);
          Inc(drawn, TyBuildGraphMarks(FBindings[i].SeriesIndex,
            FGraphSpecs[i], FGraphNodes[i], FGraphEdges[i],
            gi, FStores[i], list));
          { AND ITS LABEL SPEC INTO THE TABLE THE EXPANSION READS. A mark
            carries only the WORDS; where they go and what they are drawn
            in is looked up by series index afterwards, so a branch that
            returns before filling this row stamps captions nothing ever
            places -- which looks exactly like a series with no labels. }
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := gi.Label_;
        end;
        Continue;
      end;
      if FBindings[i].RadarIndex >= 0 then
      begin
        if FBindings[i].RadarIndex <= High(FRadars) then
          Inc(drawn, TyBuildRadarMarks(FBindings[i],
            FRadars[FBindings[i].RadarIndex], RadarVisual(i), FStores[i],
            FRadarDims[i], APPI, list));
        Continue;
      end;
      { A GAUGE IS NOT ON A COORDINATE SYSTEM EITHER, and it splits its
        drawing in two: the dial is the same whatever the data says, and only
        the needles, the arcs and the words depend on it. }
      if FBindings[i].SeriesType = TyGaugeSeriesTypeName then
      begin
        if i <= High(FGauges) then
        begin
          gv := GaugeVisual(i);
          Inc(drawn, TyBuildGaugeAxis(FBindings[i], FGauges[i],
            FGaugeSpecs[i], gv, AMeasurer, APPI, list));
          Inc(drawn, TyBuildGaugeValue(FBindings[i], FGauges[i],
            FGaugeSpecs[i], FGaugeItems[i], gv, FStores[i],
            FStores[i].DimIndexOf(TyGaugeValueDim), AMeasurer, APPI, list));
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TyFunnelSeriesTypeName then
      begin
        if i <= High(FFunnels) then
        begin
          fv := FunnelVisual(i);
          Inc(drawn, TyBuildFunnelMarks(FBindings[i], FFunnels[i], fv, list));
          { ITS OWN PASS, not TyExpandLabels -- for the same reason a pie's is.
            A band's words are placed from the trapezoid's CORNERS and from a
            guide line that has to be drawn with them; the box-placed
            expansion knows about neither, and a funnel's bounding box is not
            where its label goes. }
          Inc(drawn, TyBuildFunnelLabels(FBindings[i], FFunnels[i],
            TyFunnelLabelSpecOf(FOption, FBindings[i].SeriesIndex,
              TyFunnelLabelSpecDefault),
            FunnelLabelInk, fv.Fills, FStores[i], SeriesNameOf(i),
            FStores[i].DimIndexOf(TyPieValueDim), AMeasurer, APPI, list));
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TyPieSeriesTypeName then
      begin
        if i <= High(FPies) then
        begin
          pv := PieVisual(i);
          Inc(drawn, TyBuildPieMarks(FBindings[i], FPies[i], FPieSpecs[i],
            pv, list));
          { ITS OWN PASS, not TyExpandLabels. A pie label is placed from the
            slice's ANGLES and the series radius, none of which survive into
            the sector's bounding box -- the box of a wedge is the whole
            outer disc, so a label placed from it would sit at the disc's
            centre for every slice. }
          Inc(drawn, TyBuildPieLabels(FBindings[i], FPies[i],
            TyPieLabelSpecOf(FOption, FBindings[i].SeriesIndex,
              TyPieLabelSpecDefault),
            PieLabelInk, pv.Fills, FStores[i], SeriesNameOf(i),
            FStores[i].DimIndexOf(TyPieValueDim),
            FPieSpecs[i].PercentPrecision, AMeasurer, APPI, list));
        end;
        Continue;
      end;
      v := TySeriesVisual(TTyChartColor(SeriesColor(FBindings[i].SeriesIndex)));
      ApplyOptStyle(v, FBindings[i].SeriesIndex);
      if i <= High(FBarCols) then v.Bar := FBarCols[i];
      v.Line := TyLineSpecOf(FOption, FBindings[i].SeriesIndex);
      v.Candle := CandleVisual(FBindings[i].SeriesIndex);
      { The thinning the AXIS settled on. When markers would crowd, upstream
        falls back to the category axis' own label interval -- which the layout
        pass already computed, so it is fetched rather than re-derived. }
      v.Line.LabelStep := LabelStepFor(FBindings[i].BaseAxis);
      v.Symbol := SymbolFor(i);
      { THE PICTORIAL OPTIONS, read for every series rather than only for the
        one type that uses them. The alternative is a branch on the type name
        here, and this file already has too many of those: the reader is
        cheap, the builder is the only thing that looks at the answer, and a
        series that is not a pictorialBar simply carries the defaults. }
      v.Pictorial := TyPictorialSpecOf(FOption, FBindings[i].SeriesIndex);
      { An `empty` symbol is filled with the chart's own surface, so it reads as
        a hole rather than as a white dot on a dark skin. Upstream fills it from
        a token too, so parity and this library's own rule agree. }
      v.EmptyFill := TTyChartColor(
        ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
          [tysNormal]).Background.Color);

      { showBackground's strip. Its own key rather than the split area's: the
        two are faint for different reasons and a theme has to be able to move
        one without the other. }
      v.BackgroundFill := TTyChartColor(
        ActiveController.Model.ResolveStyle('TyAdvChartBarBackground', '',
          []).Background.Color);
      { `z` AND `z2`, AND NEITHER HAS A DEFAULT HERE. Upstream's series default
        is z 2, but nothing else in this port shares that scale -- the grid and
        the axes are ordered by INSERTION, not by a number -- so what matters
        is the order two series come out in, and two series that both say
        nothing keep insertion order either way.

        READ RATHER THAN INVENTED because it decides a picture nobody can work
        around: `pictorialBar-body-fill` draws the same silhouette three times,
        a grey one last, and only `z: 10` on the two clipped series keeps the
        fill in front of it. Without this the chart is three grey bodies.

        zlevel IS NOT READ. It is a separate canvas upstream, not a deeper
        sort key, and pretending it is one would put a series in the right
        order for the wrong reason. }
      v.Z := SeriesIntIn(FBindings[i].SeriesIndex, 'z', 0);
      v.Z2 := SeriesIntIn(FBindings[i].SeriesIndex, 'z2', 0);
      v.Label_ := LabelSpecFor(i);
      { `{c}` and the default text read the VALUE column -- whichever axis is
        not the base one. A label that read x on a bar chart would show the
        category ordinal, which is a number and looks like an answer. }
      v.LabelValueDim := -1;
      if (FBindings[i].ValueAxis <> nil) and (FStores[i] <> nil) then
        v.LabelValueDim := FStores[i].DimIndexOf(FBindings[i].ValueAxis.Dim);
      v.SeriesName := SeriesNameOf(FBindings[i].SeriesIndex);
      if Length(specs) <= FBindings[i].SeriesIndex then
        SetLength(specs, FBindings[i].SeriesIndex + 1);
      specs[FBindings[i].SeriesIndex] := v.Label_;
      Inc(drawn, TyBuildSeriesMarks(FBindings[i], FStores[i],
        StackFor(i), v, list));
    end;
    { THE EXPANSION RUNS ONCE, HERE, AND NOTHING IS APPENDED AFTER IT. Each
      caption's geometry is frozen from its host at this moment and the list
      has no update path, so a mark added later would have no label and a mark
      moved later would leave its label behind. }
    if drawn > 0 then
      TyExpandLabels(list, specs, AMeasurer, APPI);
    { THE LEGEND GOES IN AFTER THE EXPANSION, and it is allowed to because
      its captions are ANSWERS rather than requests -- they arrive with a
      font and an anchor already on them, which is what the expansion exists
      to supply. A MARK appended here would silently lose its label. }
    Inc(drawn, BuildLegends(APPI, list));
    Result := drawn;
  end;
end;

procedure TTyAdvanceChart.PaintSeries(APainter: TTyPainter;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
begin
  { BUILD, THEN DRAW. The list stays afterwards -- see FPaintList. }
  if BuildSeriesList(AMeasurer, APPI) > 0 then
    TyRenderPaintList(APainter, FPaintList);
end;

function TTyAdvanceChart.SlotOfSeries(ASeriesIndex: Integer): Integer;
var i: Integer;
begin
  for i := 0 to High(FBindings) do
    if FBindings[i].SeriesIndex = ASeriesIndex then Exit(i);
  Result := -1;
end;

function TTyAdvanceChart.NearestRowOn(ASlot: Integer; AX, AY: Double): Integer;
var
  axis: TTyAxis;
  st: TTyDataStore;
  col, i: Integer;
  want, v, d, best: Double;
begin
  Result := -1;
  if (ASlot < 0) or (ASlot > High(FBindings)) or (ASlot > High(FStores)) then Exit;
  axis := FBindings[ASlot].BaseAxis;
  st := FStores[ASlot];
  if (axis = nil) or (st = nil) then Exit;
  col := st.DimIndexOf(axis.Dim);
  if col < 0 then Exit;
  { WHICH COORDINATE THE BASE AXIS READS. Not "x for a line": on a horizontal
    bar chart the spine runs vertically, and asking a y axis about an x pixel
    answers a number that is the right shape and the wrong measurement. The
    binding already knows which of its two axes is the base one. }
  if axis = FBindings[ASlot].XAxis then want := AX else want := AY;
  { CoordToData extrapolates rather than failing, and has no NaN guard of its
    own -- a degenerate axis can hand back one. }
  want := axis.CoordToData(want);
  if IsNan(want) then Exit;
  best := NaN;
  for i := 0 to st.Count - 1 do
  begin
    v := st.Get(col, i);
    if IsNan(v) then Continue;
    d := Abs(v - want);
    if IsNan(best) or (d < best) then
    begin
      best := d;
      Result := i;
    end;
  end;
end;

function TTyAdvanceChart.HitTestAt(AX, AY: Integer): TTyChartDatumRef;
var ignored: Integer;
begin
  Result := HitTestAt(AX, AY, ignored);
end;

function TTyAdvanceChart.HitTestAt(AX, AY: Integer;
  out AElement: Integer): TTyChartDatumRef;
var
  idx, slot, row: Integer;
begin
  Result := TyChartNoDatum;
  AElement := -1;
  if (FPaintList = nil) or not FPaintListValid then Exit;
  idx := FPaintList.HitTestElement(AX, AY, FPaintListPPI);
  if idx < 0 then Exit;
  AElement := idx;
  Result := FPaintList.Element(idx).Datum;
  if Result.SeriesIndex < 0 then Exit;
  { A RUN ELEMENT -- one element standing for a whole series, which is what a
    line's stroke is. The list reports it as `(series, -1)`, which
    TyChartDatumValid rejects, and because the hit test answers with the
    topmost element rather than falling through, a hit there would otherwise
    name nothing at all. }
  if Result.DataIndex < 0 then
  begin
    slot := SlotOfSeries(Result.SeriesIndex);
    row := NearestRowOn(slot, AX, AY);
    if row < 0 then
    begin
      AElement := -1;
      Exit(TyChartNoDatum);
    end;
    Result := TyChartDatum(Result.SeriesIndex, row,
      FStores[slot].GetRawIndex(row));
  end;
end;

{ ==================== the tooltip ==================== }

function TTyAdvanceChart.TooltipSpecFor(
  const ADatum: TTyChartDatumRef): TTyTooltipSpec;
begin
  { THE RAW ROW, not the view row. A data-item tooltip is written beside the
    datum in the option text, and the option text is the raw order -- a filter
    is a view for readers and has never moved anything in the tree. }
  { A GRAPH LINK has a row of its own, in the LINK list, and a node's tooltip
    written at that position is somebody else's -- so a link takes the
    series'. }
  if ADatum.IsEdge then
    Result := TyTooltipSpecOf(FOption, ADatum.SeriesIndex, -1)
  else
    Result := TyTooltipSpecOf(FOption, ADatum.SeriesIndex, ADatum.RawDataIndex);
end;

function TTyAdvanceChart.TooltipInk(
  const ASpec: TTyTooltipSpec): TTyTooltipInk;
var
  nameS, valueS: TTyStyleSet;
  model: TTyStyleModel;
begin
  model := ActiveController.Model;
  nameS := model.ResolveStyle('TyAdvChartTooltip', StyleClass, [tysNormal]);
  valueS := model.ResolveStyle('TyAdvChartTooltipValue', '', []);

  Result.NameFontName := nameS.FontName;
  Result.NameSizeLogical := ResolveFontSize(nameS);
  Result.NameWeight := nameS.FontWeight;
  Result.NameColour := TTyChartColor(nameS.TextColor);

  Result.ValueFontName := valueS.FontName;
  if Result.ValueFontName = '' then Result.ValueFontName := nameS.FontName;
  Result.ValueSizeLogical := ResolveFontSize(valueS);
  Result.ValueWeight := valueS.FontWeight;
  Result.ValueColour := TTyChartColor(valueS.TextColor);

  { THE OPTION LAST, over whatever the theme said. ECharts' textStyle is one
    object for both roles, so a written colour or size takes BOTH -- the
    hierarchy a theme drew with two keys collapses into one, which is exactly
    what writing `tooltip.textStyle` asks for. }
  if ASpec.HasTextColour then
  begin
    Result.NameColour := ASpec.TextColour;
    Result.ValueColour := ASpec.TextColour;
  end;
  if ASpec.HasTextSize then
  begin
    Result.NameSizeLogical := TyRoundOpt(ASpec.TextSizeLogical, 12, 1, 400);
    Result.ValueSizeLogical := Result.NameSizeLogical;
  end;

  { UPSTREAM'S OWN HTML RULE -- round(fontSize * 3 / 2) -- and NOT its richText
    one, which is a flat 22 whatever the font is. A library whose themes change
    the type scale cannot carry a constant here: a dense skin at 11px would get
    a box of double-spaced rows and a display skin at 20px would get overlapping
    ones. Recorded as a deliberate divergence. }
  Result.LineHeightLogical :=
    Round(Max(Result.NameSizeLogical, Result.ValueSizeLogical) * 3 / 2);

  Result.MarkerSizeLogical := ActiveController.Metric(
    TyAdvChartTooltipMarkerVar, TyAdvChartTooltipMarker);
  Result.MarkerGapLogical := ActiveController.Metric(
    TyAdvChartTooltipMarkerGapVar, TyAdvChartTooltipMarkerGap);
  Result.GutterLogical := ActiveController.Metric(
    TyAdvChartTooltipGutterVar, TyAdvChartTooltipGutter);
  { The narrow gutter is half the wide one upstream (10 against 20), so it
    follows a skin that retuned the wide one instead of being a fifth metric
    nobody would think to change. }
  Result.GutterCloseLogical := Result.GutterLogical / 2;
  if Result.MarkerSizeLogical < 0 then Result.MarkerSizeLogical := 0;
  if Result.MarkerGapLogical < 0 then Result.MarkerGapLogical := 0;
  if Result.GutterLogical < 0 then Result.GutterLogical := 0;
end;

function TTyAdvanceChart.DatumColour(
  const ADatum: TTyChartDatumRef): TTyChartColor;
var
  slot, idx: Integer;
  perDatum: Boolean;
  el: TTyChartElement;
  v: TTySeriesVisual;
  gi: TTyGraphInk;
begin
  Result := 0;
  { THE SERIES' COLOUR WITH THE ROW'S OVERRIDE, which is what upstream's marker
    is: it reads `style[series.visualDrawType]`, and drawType names the colour
    the visual pipeline WROTE -- not whichever slot a symbol later painted it
    into.

    ASKING THE DRAWN ELEMENT LOOKED RIGHT AND WAS WRONG. A line's default
    marker is an `emptyCircle`: a ring in the series colour over the chart's
    own ground, so its element's FILL is the background, and a tooltip reading
    it drew an invisible white dot on a white box. Falling back to the stroke
    is no answer either, because a bar carries its colour in the fill. What
    the marker names is a SERIES and a ROW, so that is what it asks. }
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if slot < 0 then Exit;
  { A GRAPH LINK'S COLOUR IS ITS STROKE, found by its own row. }
  if ADatum.IsEdge then
  begin
    if (FBindings[slot].SeriesType = TyGraphSeriesTypeName)
      and (slot <= High(FGraphEdges)) and (slot <= High(FGraphSpecs)) then
    begin
      gi := GraphInk(slot);
      for idx := 0 to High(FGraphEdges[slot]) do
        if FGraphEdges[slot][idx].Row = ADatum.DataIndex then
          Exit(TyGraphEdgeStroke(FGraphSpecs[slot], FGraphEdges[slot], gi, idx));
    end;
    Exit;
  end;
  { A GRAPH NODE'S MARKER IS THE NODE'S FILL -- its category's colour, or its
    own -- found by the node's VIEW row. Not through the paint list: a graph's
    edges number their data in the same space as its nodes, so the first
    element carrying a datum could be an edge. }
  if (FBindings[slot].SeriesType = TyGraphSeriesTypeName)
    and (slot <= High(FGraphNodes)) then
  begin
    gi := GraphInk(slot);
    for idx := 0 to High(FGraphNodes[slot]) do
      if (FGraphNodes[slot][idx].Row = ADatum.DataIndex)
        and (idx <= High(gi.NodeFills)) then
        Exit(gi.NodeFills[idx]);
  end;
  v := TySeriesVisual(TTyChartColor(SeriesColor(ADatum.SeriesIndex)));
  ApplyOptStyle(v, ADatum.SeriesIndex);
  Result := v.Fill;
  if (slot <= High(FStores)) and (FStores[slot] <> nil)
    and (ADatum.DataIndex >= 0) and (ADatum.DataIndex < FStores[slot].Count) then
    Result := TyRowFill(v, FStores[slot], ADatum.DataIndex);

  { SOME SERIES HAVE NO SINGLE COLOUR. A pie's slices take consecutive palette
    slots; a candlestick's bodies are red or green by the datum's own two
    numbers. Asking the SERIES paints every marker of those alike, so for them
    the answer is read off the drawn element -- right here for the same reason
    it was wrong above, because both are FILLED shapes and a filled shape's
    fill IS its colour.

    FOUND BY DATUM, not taken from the hovered element: under an axis trigger
    the pointer is usually nowhere near the mark being described, and the
    element it happens to be over belongs to something else or to nothing. }
  { THE SAME LIST THE LEGEND ASKS. It read `= 'pie'` while a funnel and a
    radar colour by datum in exactly the same way, so their markers took the
    flat series colour and disagreed with the band or the ring under the
    pointer. }
  perDatum := TySeriesLegendByDatum(FBindings[slot].SeriesType)
    or (Length(FStores[slot].DimsOfCoord(
      AxisDimOf(FBindings[slot].ValueAxis))) > 1);
  if perDatum and (FPaintList <> nil) and FPaintListValid then
  begin
    idx := FPaintList.IndexOfDatumInk(ADatum.SeriesIndex, ADatum.DataIndex);
    if idx >= 0 then
    begin
      el := FPaintList.Element(idx);
      if el.Style.HasFill and (el.Style.FillColor <> 0) then
        Result := el.Style.FillColor
      { A RING HAS NO FILL. A radar's row is a stroked polyline, so the colour
        that stands for it is its STROKE -- and a filled-shape-only rule left
        every radar marker on the series colour, which is the one thing a
        series colouring by datum does not have. }
      else if (not el.Style.HasFill) and (el.Style.StrokeColor <> 0)
        and (el.Style.StrokeWidthLogical > 0) then
        Result := el.Style.StrokeColor;
    end;
  end;
end;

function TTyAdvanceChart.TooltipParams(
  const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
var
  slot, i, n: Integer;
  cols: TTyIntegerArray;
  st: TTyDataStore;
  pct: TTyDoubleArray;
begin
  Result := Default(TTyChartCallbackParams);
  Result.ComponentType := 'series';
  Result.SeriesIndex := ADatum.SeriesIndex;
  Result.DataIndex := ADatum.DataIndex;
  Result.RawDataIndex := ADatum.RawDataIndex;
  Result.Color := DatumColour(ADatum);
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if slot < 0 then Exit;
  Result.SeriesType := FBindings[slot].SeriesType;
  Result.SeriesName := SeriesNameOf(ADatum.SeriesIndex);
  if slot > High(FStores) then Exit;
  st := FStores[slot];
  if st = nil then Exit;
  if Result.SeriesType = TyGraphSeriesTypeName then
  begin
    if ADatum.IsEdge then Result.DataType := 'edge'
    else Result.DataType := 'node';
  end;
  { A GRAPH LINK IS NAMED BY ITS TWO ENDS, `source > target`, each the name
    upstream's getName answers -- so a link between two bare numbers on a
    category axis reads 'Mon > Tue'. Its value is the link's own, and most
    links have none. }
  if ADatum.IsEdge then
  begin
    if slot > High(FGraphEdges) then Exit;
    for i := 0 to High(FGraphEdges[slot]) do
      if FGraphEdges[slot][i].Row = ADatum.DataIndex then
      begin
        Result.Name := GraphNodeName(slot, FGraphEdges[slot][i].Source)
          + ' > ' + GraphNodeName(slot, FGraphEdges[slot][i].Target);
        if not IsNan(FGraphEdges[slot][i].Value) then
        begin
          SetLength(Result.Values, 1);
          Result.Values[0] := FGraphEdges[slot][i].Value;
        end;
        Break;
      end;
    Exit;
  end;
  if (ADatum.DataIndex < 0) or (ADatum.DataIndex >= st.Count) then Exit;

  { THE NAME UPSTREAM CALLS `data.getName(dataIndex)`. On a category axis it is
    the category; on two value axes there is none, because the default encode
    only assigns an item name "the category way". A line on a value x axis
    therefore shows a dot and a number and no words -- which is upstream's
    picture, not a gap in this. The store answers it, by the same rule the
    label's b placeholder asks. }
  Result.Name := st.GetItemName(ADatum.DataIndex);

  { THE d LETTER, which only a pie and a funnel have: the pie's seats (the
    largest-remainder shares, to percentPrecision) and the funnel's two-place
    share, both over the slices there are. Everywhere else `{d}` is no
    letter at all and a template leaves it as written. }
  if (Result.SeriesType = TyPieSeriesTypeName) and (slot <= High(FPies)) then
  begin
    Result.HasPercent := True;
    pct := TyPieSectorPercents(FPies[slot], FPieSpecs[slot].PercentPrecision);
    for i := 0 to High(FPies[slot].Sectors) do
      if FPies[slot].Sectors[i].Index = ADatum.DataIndex then
        Result.Percent := pct[i];
  end
  else if (Result.SeriesType = TyFunnelSeriesTypeName)
    and (slot <= High(FFunnels)) then
  begin
    Result.HasPercent := True;
    pct := TyFunnelPercents(FFunnels[slot]);
    for i := 0 to High(FFunnels[slot].Items) do
      if FFunnels[slot].Items[i].Index = ADatum.DataIndex then
        Result.Percent := pct[i];
  end;

  { WHICH VALUES, PLURAL. Upstream's `tooltipDims` is every data dimension
    mapped onto the value coordinate -- one for a bar, a line or a pie, and
    FOUR for a candlestick, which is why `mapDimensionsAll` is the plural
    spelling there and `mapDimension` is not. A port that took one column
    showed a candle's highest and called it the value. }
  cols := nil;
  if FBindings[slot].ValueAxis <> nil then
    cols := st.DimsOfCoord(FBindings[slot].ValueAxis.Dim);
  if Length(cols) = 0 then
  begin
    { A pie has no axes at all; its one dimension is the value. }
    n := st.DimCount;
    for i := n - 1 downto 0 do
      if st.DimType(i) <> ddtOrdinal then
      begin
        SetLength(cols, 1);
        cols[0] := i;
        Break;
      end;
  end;
  if Length(cols) = 0 then Exit;
  SetLength(Result.Values, Length(cols));
  SetLength(Result.DimensionNames, Length(cols));
  for i := 0 to High(cols) do
  begin
    Result.Values[i] := st.Get(cols[i], ADatum.DataIndex);
    Result.DimensionNames[i] := st.DimName(cols[i]);
  end;
end;

function TTyAdvanceChart.TooltipContent(const ADatum: TTyChartDatumRef;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
var
  p: TTyChartCallbackParams;
  seriesName, inlineName, valueText: string;
  haveValue: Boolean;
begin
  Result := nil;
  p := TooltipParams(ADatum);
  seriesName := p.SeriesName;
  inlineName := p.Name;
  haveValue := Length(p.Values) > 0;
  valueText := ValuesText(p);
  if haveValue and (valueText = '') then haveValue := False;
  { A GRAPH LINK IS ONE BARE ROW -- upstream's formatTooltip hands back a
    nameValue with no marker and no section, so no series header either,
    named or not. }
  if ADatum.IsEdge then
  begin
    { A LINK WITH NO VALUE HAS NO VALUE CELL -- upstream's noValue is
      `value == null` here -- where a node or a bar with a missing value
      shows '-'. Nothing to decide here: TooltipParams gives a link a value
      only when it has one, so haveValue is already False. }
    if (Trim(inlineName) = '') and not haveValue then Exit;
    Result := TTyTooltipBlock.CreateSection('', True);
    Result.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0,
      inlineName, False, valueText, not haveValue));
    Exit;
  end;
  if (Trim(inlineName) = '') and not haveValue and (Trim(seriesName) = '') then
    Exit;

  { ONE SECTION HOLDING ONE ROW, which is the whole of upstream's default for
    a bar, a line, a scatter and a pie. `noHeader` is decided by whether the
    series was NAMED -- an auto-generated name counts as unnamed upstream, and
    SeriesNameOf answers '' for exactly that case -- and it is a different
    LAYOUT, not a wording change: without a header the section's gap level
    drops from 1 to 0 and the box loses a row. }
  { A NAME OF BLANKS IS STILL A NAME: upstream's isNameSpecified asks only
    whether one was written, and the header then goes through
    makeValueReadable, which never shows nothing -- so it reads '-'. }
  if (seriesName <> '') and (Trim(seriesName) = '') then seriesName := '-';
  Result := TTyTooltipBlock.CreateSection(seriesName, False);
  Result.Add(TTyTooltipBlock.CreateNameValue(ttmItem, p.Color,
    inlineName, False, valueText, not haveValue));
end;

function TTyAdvanceChart.PointerAt(AAxis: TTyAxis; AValue: Double): Double;
var ext: TTyRange;
begin
  Result := AValue;
  if (AAxis = nil) or IsNan(AValue) then Exit;
  if not (AAxis.Scale is TTyIntervalScale) then Exit;
  ext := AAxis.Scale.GetExtent;
  if Result > ext.Stop then Result := ext.Stop;
  if Result < ext.Start then Result := ext.Start;
end;

function TTyAdvanceChart.PointerValue(const AHit: TTyAxisHit): Double;
begin
  if AHit.Spec.Snap then Result := AHit.SnapValue else Result := AHit.Value;
  Result := PointerAt(AHit.Axis, Result);
end;

function TTyAdvanceChart.AxisValueText(AAxis: TTyAxis; AValue: Double;
  const ALabel: TTyAxisPointerLabelSpec): string;
var tt: TTyTimeTick;
begin
  Result := '';
  if AAxis = nil then Exit;
  if AAxis.Scale is TTyOrdinalScale then
    Result := TTyOrdinalScale(AAxis.Scale).GetLabel(AValue)
  else if AAxis.Scale is TTyTimeScale then
  begin
    tt.Value := AValue;
    tt.Unit_ := TyTimeUnitOf(AValue, TTyTimeScale(AAxis.Scale).UTC);
    tt.Level := 0;
    tt.NotNice := False;
    Result := TyTimeLabel(tt, TTyTimeScale(AAxis.Scale).UTC);
  end
  else if ALabel.HasPrecision then
    Result := TyScaleValueLabel(AAxis.Scale, AValue, ALabel.Precision)
  else
    { 'AUTO' IS NOT "every digit the number has": it is the scale's interval
      precision -- the step's decimals plus two -- PADDED, as toFixed pads.
      An axis stepping by twenty labels its pointer 37.25 and one stepping by
      one 3.00. It was the step's own decimals, unpadded, and read 37 and 3. }
    Result := TyScaleValueLabel(AAxis.Scale, AValue, TyLabelPrecision(lpAuto));
  { FIRST OCCURRENCE ONLY, which is upstream's `.replace('{value}', text)` --
    a plain string pattern, not a global one. An empty formatter was never
    taken, as upstream ignores a falsy one. }
  if ALabel.HasFormatter then
    Result := StringReplace(ALabel.Formatter, '{value}', Result, []);
end;

function TTyAdvanceChart.NearestOnAxis(ASlot: Integer; AAxis: TTyAxis;
  AValue: Double; AMaxDistPx: Double; out ARows: TTyIntegerArray): Boolean;
var
  st: TTyDataStore;
  col, i, n: Integer;
  target, v, coord, diff, dist, minDist, minDiff: Double;
begin
  ARows := nil;
  Result := False;
  if (AAxis = nil) or (ASlot < 0) or (ASlot > High(FStores)) then Exit;
  st := FStores[ASlot];
  if st = nil then Exit;
  col := st.DimIndexOf(AAxis.Dim);
  if col < 0 then Exit;
  target := AAxis.DataToCoord(AValue);
  if IsNan(target) then Exit;

  { IN VIEW COORDINATE SPACE -- pixels, not data. The 0.5 a category axis is
    given is HALF A PIXEL, which after the value has already been rounded to a
    band centre means "the same band"; its purpose is to drop a series whose
    data is shorter than the axis, not to widen the search. ECharts 5.x
    compared in data space and 6.x changed it, so this is one to read rather
    than remember. }
  minDist := Infinity;
  minDiff := -1;
  n := 0;
  SetLength(ARows, st.Count);
  for i := 0 to st.Count - 1 do
  begin
    v := st.Get(col, i);
    if IsNan(v) then Continue;
    coord := AAxis.DataToCoord(v);
    if IsNan(coord) then Continue;
    diff := target - coord;
    dist := Abs(diff);
    if dist > AMaxDistPx then Continue;
    { THE SIDE TIE-BREAK. When the pointer falls exactly between two rows, the
      one at or before it wins -- otherwise both land in the list and every
      midpoint shows two rows of the same series. Rows with the SAME signed
      difference still accumulate, which is how two rows holding one value are
      both reported. }
    if (dist < minDist) or ((dist = minDist) and (diff >= 0) and (minDiff < 0)) then
    begin
      minDist := dist;
      minDiff := diff;
      n := 0;
    end;
    if diff = minDiff then
    begin
      ARows[n] := i;
      Inc(n);
    end;
  end;
  SetLength(ARows, n);
  Result := n > 0;
end;

function TTyAdvanceChart.ResolveAxisPointers(AX, AY: Integer): TTyAxisHitArray;
var
  tipSpec: TTyTooltipSpec;
  wantAxis: string;
  crossType: Boolean;
  g, c: Integer;
  gb: TTyGridBuild;
  cart: TTyCartesian2D;
  baseAxis, otherAxis: TTyAxis;
  seen: array of TTyAxis;

  function AlreadySeen(AAxis: TTyAxis): Boolean;
  var j: Integer;
  begin
    for j := 0 to High(seen) do
      if seen[j] = AAxis then Exit(True);
    SetLength(seen, Length(seen) + 1);
    seen[High(seen)] := AAxis;
    Result := False;
  end;

  { One axis, resolved and appended when it has something to say. }
  procedure Consider(AAxis: TTyAxis; const APlot: TTyRectF; ACross: Boolean);
  var
    hit: TTyAxisHit;
    coord, value, snapTo, v, diff, dist, minDist, minDiff, maxDist: Double;
    rows: TTyIntegerArray;
    s, r, m: Integer;
    isCat: Boolean;
  begin
    if AAxis = nil then Exit;
    if AlreadySeen(AAxis) then Exit;
    isCat := AAxis.Scale is TTyOrdinalScale;
    hit := Default(TTyAxisHit);
    hit.Axis := AAxis;
    hit.Plot := APlot;
    hit.Cross := ACross;
    hit.Spec := TyAxisPointerSpecOf(FOption, AAxis.MainType,
      AAxis.ComponentIndex, isCat, True,
      (tipSpec.Trigger = tttAxis) and not ACross, crossType);
    if hit.Spec.Show = apsNo then Exit;

    if AAxis.Horizontal then coord := AX else coord := AY;
    value := AAxis.CoordToData(coord);
    if IsNan(value) then Exit;
    { THE CONTAINMENT TEST IS WHAT REJECTS AN OUT-OF-RANGE POINT, not a clamp.
      CoordToData extrapolates on purpose, so a pointer forty pixels past the
      last category answers an ordinal nobody has -- and pulling it back onto
      the edge would put a tooltip on the last bar for a pointer that is not
      over it.

      AN EQUIVALENT MUTANT LIVES HERE, recorded rather than chased. Deleting
      this line changes nothing TODAY, because the caller has already required
      the point to be inside the grid's plot rect and every axis' pixel extent
      is currently that rect. It stops being equivalent the moment an axis is
      narrower than the plot -- an `offset`, or a second pair sharing the
      grid -- and a guard that is redundant only by coincidence is still the
      guard that has to be there when the coincidence ends. }
    if not TyRangeContains(AAxis.Scale.GetExtent2(sekEffective), value) then Exit;

    { ---- the nearest series, and only the nearest ---- }
    snapTo := value;
    minDist := Infinity;
    minDiff := -1;
    if isCat then maxDist := 0.5 else maxDist := Infinity;
    if not ACross then
      for s := 0 to High(FBindings) do
      begin
        if FBindings[s].Hidden then Continue;
        if FBindings[s].BaseAxis <> AAxis then Continue;
        if not NearestOnAxis(s, AAxis, value, maxDist, rows) then Continue;
        v := FStores[s].Get(FStores[s].DimIndexOf(AAxis.Dim), rows[0]);
        if IsNan(v) or IsInfinite(v) then Continue;
        diff := value - v;
        dist := Abs(diff);
        { AN AXIS TRIGGER IS NOT "EVERY SERIES IN THIS COLUMN". Upstream empties
          the batch the moment a closer series appears, so what survives is the
          series NEAREST the hovered value -- and equal-distance ones
          accumulate, because the push sits outside the test that empties it. }
        if dist <= minDist then
        begin
          if (dist < minDist) or ((diff >= 0) and (minDiff < 0)) then
          begin
            minDist := dist;
            minDiff := diff;
            snapTo := v;
            SetLength(hit.Slots, 0);
            SetLength(hit.Rows, 0);
          end;
          m := Length(hit.Slots);
          SetLength(hit.Slots, m + Length(rows));
          SetLength(hit.Rows, m + Length(rows));
          for r := 0 to High(rows) do
          begin
            hit.Slots[m + r] := s;
            hit.Rows[m + r] := rows[r];
          end;
        end;
      end;
    hit.Value := value;
    hit.SnapValue := snapTo;
    { NOTHING TO SAY AND NOTHING TO DRAW. A pointer type of `none` still
      reaches here, because its LABEL can be shown on its own. }
    if (hit.Spec.PointerType = aptNone) and not hit.Spec.LabelSpec.Show
      and (Length(hit.Slots) = 0) then Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := hit;
  end;

begin
  Result := nil;
  seen := nil;
  if (FBuild = nil) or (FOption = nil) then Exit;
  tipSpec := TyTooltipSpecOf(FOption, -1, -1);
  if not tipSpec.Show then Exit;
  crossType := TyTooltipAxisPointerType(FOption) = aptCross;
  { CROSS PUTS A POINTER ON THE BASE AXIS EVEN WHEN THE TRIGGER IS NOT 'axis'.
    Upstream's gate is `triggerAxis || cross`, and the second disjunct is the
    reason `tooltip: {axisPointer: {type: 'cross'}}` written on its own draws
    anything at all. }
  if (tipSpec.Trigger <> tttAxis) and not crossType then Exit;
  wantAxis := TyTooltipAxisPointerAxis(FOption);

  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    if not TyRectFContains(gb.PlotRect, TyPointF(AX, AY)) then Continue;
    for c := 0 to gb.CartesianCount - 1 do
    begin
      cart := gb.CartesianByIndex(c);
      if cart = nil then Continue;
      { `tooltip.axisPointer.axis` names a dimension; 'auto' asks the
        coordinate system, whose rule is ordinal before time before x -- BY
        SCALE, so a y-category chart puts its pointer on Y. }
      if wantAxis <> '' then baseAxis := cart.AxisByDim(wantAxis)
      else baseAxis := cart.GetBaseAxis;
      Consider(baseAxis, gb.PlotRect, False);
      if crossType then
      begin
        otherAxis := cart.GetOtherAxis(baseAxis);
        Consider(otherAxis, gb.PlotRect, True);
      end;
    end;
  end;
end;

function TTyAdvanceChart.EmphasiseElement(AIndex: Integer; APPI: Integer;
  out AElement: TTyChartElement): Boolean;
var
  spec: TTyChartEmphasisSpec;
  slot: Integer;
  ratio, half: Double;
  st: TTyChartStyle;
  normal: TTyChartStyle;
  states: TTyChartStateList;
begin
  Result := False;
  AElement := Default(TTyChartElement);
  if (FPaintList = nil) or not FPaintListValid then Exit;
  if (AIndex < 0) or (AIndex >= FPaintList.Count) then Exit;
  AElement := FPaintList.Element(AIndex);
  if AElement.Datum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(AElement.Datum.SeriesIndex);
  if slot < 0 then Exit;

  { THE SERIES' emphasis BLOCK. A data item can carry one of its own and this
    does not read it yet -- one more cascade level for a key almost nobody
    writes per datum, and the level that IS written is this one. Recorded
    rather than silently missing. }
  spec := TyChartReadEmphasis(FOption.ComponentAt('series',
    AElement.Datum.SeriesIndex));
  if spec.Disabled then Exit;

  { ---- the style ---- }
  normal := TyChartNoStyle;
  if AElement.Style.HasFill then
    TyChartSetColor(normal, cskFill, AElement.Style.FillColor);
  if AElement.Style.StrokeColor <> 0 then
    TyChartSetColor(normal, cskStroke, AElement.Style.StrokeColor);
  if AElement.Style.StrokeWidthLogical > 0 then
    TyChartSetNum(normal, cskLineWidth, AElement.Style.StrokeWidthLogical);
  TyChartSetNum(normal, cskOpacity, AElement.Style.Alpha);

  states := Default(TTyChartStateList);
  states.Emphasis := True;
  { WITH NOTHING DECLARED, AN EMPHASIS IS THE NORMAL COLOUR LIFTED -- ten per
    cent brighter. That is the default hover appearance of every bar, slice
    and symbol in ECharts, and a port that treated "no emphasis style" as "no
    change" would draw a hover that does nothing. }
  st := TyChartResolveStyle(normal,
    TyChartOverlay(spec.Item, spec.Line), states);

  if TyChartStyleHas(st, cskFill) then
  begin
    AElement.Style.HasFill := True;
    AElement.Style.FillColor := st.Color[cskFill];
  end;
  if TyChartStyleHas(st, cskStroke) then
    AElement.Style.StrokeColor := st.Color[cskStroke];
  if TyChartStyleHas(st, cskLineWidth) then
    AElement.Style.StrokeWidthLogical := st.Num[cskLineWidth];
  if TyChartStyleHas(st, cskOpacity) then
    AElement.Style.Alpha := st.Num[cskOpacity];
  { A GRADIENT IS NOT LIFTED. Upstream lifts a colour, and a ramp has no single
    colour to lift -- so a gradient-filled mark keeps its ramp and gains only
    whatever the option declared. }

  { ---- and the geometry ---- }
  case AElement.Shape.Kind of
    cskSector:
      { A SLICE GROWS ITS OUTER RADIUS BY PIXELS, not by a ratio: scaling it
        about the disc centre would lift its inner edge off the hole. }
      if spec.ScaleAuto or (spec.Scale <> 1) then
        AElement.Shape.R1 := AElement.Shape.R1
          + spec.ScaleSizePx * APPI / 96;
    cskRect, cskRoundRect, cskPolygon, cskPolyline:
      { A BAR DOES NOT GROW. Upstream scales SYMBOLS and sectors and leaves a
        bar's rectangle alone -- a bar that jumped a tenth larger under the
        pointer would look like the data had moved. }
      ;
  else
    begin
      half := (AElement.Shape.Bounds.Bottom - AElement.Shape.Bounds.Top) / 2;
      if AElement.Shape.Kind in [cskCircle, cskEllipse] then
        half := AElement.Shape.R1;
      ratio := TyChartSymbolScaleRatio(spec, half);
      AElement.Shape := TyScaleShape(AElement.Shape, ratio);
    end;
  end;
  Result := True;
end;

procedure TTyAdvanceChart.PaintEmphasis(APainter: TTyPainter; APPI: Integer;
  const AHits: TTyAxisHitArray);
var
  list: TTyPaintList;
  el: TTyChartElement;
  i, k, slot: Integer;

  procedure Lift(AIndex: Integer);
  begin
    if AIndex < 0 then Exit;
    if not EmphasiseElement(AIndex, APPI, el) then Exit;
    { THE CAPTION IS DROPPED. A mark's words were expanded once, into a
      SEPARATE element, and the copy drawn here carries the request rather
      than the answer -- rendering it would draw unplaced text at the origin. }
    el.Caption := Default(TTyElementCaption);
    list.Add(el);
  end;

begin
  if (FPaintList = nil) or not FPaintListValid then Exit;
  list := TTyPaintList.Create;
  try
    { AN AXIS TRIGGER HIGHLIGHTS THE WHOLE COLUMN. Upstream calls it
      triggerEmphasis and has it on by default: the rows the tooltip is
      describing are the rows that light up, which is what ties the two
      together. }
    for i := 0 to High(AHits) do
      for k := 0 to High(AHits[i].Slots) do
      begin
        slot := AHits[i].Slots[k];
        if (slot < 0) or (slot > High(FBindings)) then Continue;
        Lift(FPaintList.IndexOfDatum(FBindings[slot].SeriesIndex,
          AHits[i].Rows[k]));
      end;
    { And an item hover highlights the one thing under the pointer. }
    if Length(AHits) = 0 then Lift(FTipElement);
    if list.Count > 0 then TyRenderPaintList(APainter, list);
  finally
    list.Free;
  end;
end;

procedure TTyAdvanceChart.PaintAxisPointers(APainter: TTyPainter;
  const ARect: TRect; APPI: Integer; const AMeasurer: ITyTextMeasurer;
  const AHits: TTyAxisHitArray);
var
  i: Integer;
  lineS, shadowS, labelS: TTyStyleSet;
  hit: TTyAxisHit;
  at, lo, hi, w, pv: Double;
  colour: TTyColor;
  band: TTyRectF;
  dash: TTyDoubleArray;
  txt: string;
  tw, th, margin, padL, padT, padR, padB: Double;
  box: TRect;
  corners: TTyCorners;
  surface: TTyFill;
begin
  lineS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointer', '', []);
  shadowS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerShadow',
    '', []);
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerLabel',
    '', []);
  for i := 0 to High(AHits) do
  begin
    hit := AHits[i];
    if hit.Axis = nil then Continue;
    { SNAP MOVES THE POINTER, not the content. With snap off the line stays
      under the cursor while the tooltip still describes the nearest row --
      upstream splits them at exactly this branch. }
    { THE POINTER'S OWN VALUE: the snapped row with snap on, the cursor with
      it off -- and inside the scale's extent, which upstream's fixValue
      clamps it to before drawing the line or writing the label. A row past
      a written max puts the pointer on the max, not off the plot. }
    pv := PointerValue(hit);
    at := hit.Axis.DataToCoord(pv);
    if IsNan(at) then Continue;

    case hit.Spec.PointerType of
      aptShadow:
        begin
          { THE BAND IS THE CATEGORY'S OWN WIDTH, and only a category axis has
            one. Upstream derives a numeric axis' band from a statistics pass
            over the hovered series' minimum positive gap; this port has no
            such pass, so a shadow on a value axis draws NOTHING rather than
            the one-pixel sliver the missing statistic would produce. A
            deliberate restriction, recorded rather than approximated. }
          w := hit.Axis.BandWidth;
          if w <= 0 then Continue;
          if not (tpBackground in shadowS.Present) then Continue;
          if hit.Axis.Horizontal then
          begin
            if not TyAxisPointerBand(at, w, hit.Plot.Left, hit.Plot.Right,
              lo, hi) then Continue;
            band := TyRectF(lo, hit.Plot.Top, hi, hit.Plot.Bottom);
          end
          else
          begin
            if not TyAxisPointerBand(at, w, hit.Plot.Top, hit.Plot.Bottom,
              lo, hi) then Continue;
            band := TyRectF(hit.Plot.Left, lo, hit.Plot.Right, hi);
          end;
          colour := shadowS.Background.Color;
          if hit.Spec.HasShadowColour then colour := TTyColor(hit.Spec.ShadowColour);
          surface := shadowS.Background;
          surface.Kind := tfkSolid;
          surface.Color := colour;
          APainter.FillBackground(
            Rect(Round(band.Left), Round(band.Top),
                 Round(band.Right), Round(band.Bottom)), surface,
            TyCorners(0, 0, 0, 0));
        end;
      aptLine:
        begin
          if not (tpBorderColor in lineS.Present) then Continue;
          colour := lineS.BorderColor;
          if hit.Spec.HasLineColour then colour := TTyColor(hit.Spec.LineColour);
          w := lineS.BorderWidth;
          if hit.Spec.HasLineWidth then w := hit.Spec.LineWidthLogical;
          if w <= 0 then Continue;
          dash := TyDashPattern(hit.Spec.LineDash, hit.Spec.LineDashExplicit, w);
          APainter.SetLineDash(dash);
          APainter.BeginPath;
          if hit.Axis.Horizontal then
          begin
            APainter.MoveTo(at, hit.Plot.Top);
            APainter.LineTo(at, hit.Plot.Bottom);
          end
          else
          begin
            APainter.MoveTo(hit.Plot.Left, at);
            APainter.LineTo(hit.Plot.Right, at);
          end;
          APainter.StrokePath(colour, w);
          { AND THE DASH IS PUT BACK. SetLineDash is painter state, not an
            argument -- leaving it set dashes whatever is drawn next, which is
            the same class of leak as forgetting BeginPath and just as invisible
            until something downstream comes out wrong. }
          APainter.SetLineDash([]);
        end;
    end;

    { ---- the label ---- }
    if not hit.Spec.LabelSpec.Show then Continue;
    if not (tpBackground in labelS.Present) then Continue;
    { The value the line is at -- the cursor's with snap off, where it used to
      be the nearest row's while the line stood under the cursor. }
    txt := AxisValueText(hit.Axis, pv, hit.Spec.LabelSpec);
    if txt = '' then Continue;
    AMeasurer.MeasureLine(txt, labelS.FontName, ResolveFontSize(labelS),
      labelS.FontWeight, tw, th);
    if (tw <= 0) or (th <= 0) then Continue;
    if hit.Spec.LabelSpec.HasPadding then
    begin
      padL := APainter.ScaleF(hit.Spec.LabelSpec.PadLeft);
      padT := APainter.ScaleF(hit.Spec.LabelSpec.PadTop);
      padR := APainter.ScaleF(hit.Spec.LabelSpec.PadRight);
      padB := APainter.ScaleF(hit.Spec.LabelSpec.PadBottom);
    end
    else
    begin
      padL := APainter.Scale(labelS.Padding.Left);
      padT := APainter.Scale(labelS.Padding.Top);
      padR := APainter.Scale(labelS.Padding.Right);
      padB := APainter.Scale(labelS.Padding.Bottom);
    end;
    margin := APainter.ScaleF(ActiveController.Metric(
      TyAdvChartAxisPointerMarginVar, TyAdvChartAxisPointerMargin));
    if hit.Spec.LabelSpec.MarginLogical <> 3 then
      margin := APainter.ScaleF(hit.Spec.LabelSpec.MarginLogical);
    { OUTSIDE THE PLOT, on the axis' own side. Not on the axis LINE: an
      on-zero axis floats in the middle of the plot and its labels do not
      follow it there. }
    if hit.Axis.Horizontal then
    begin
      box.Left := Round(at - (tw + padL + padR) / 2);
      if hit.Axis.Side = asTop then
        box.Top := Round(hit.Plot.Top - margin - th - padT - padB)
      else
        box.Top := Round(hit.Plot.Bottom + margin);
    end
    else
    begin
      box.Top := Round(at - (th + padT + padB) / 2);
      if hit.Axis.Side = asRight then
        box.Left := Round(hit.Plot.Right + margin)
      else
        box.Left := Round(hit.Plot.Left - margin - tw - padL - padR);
    end;
    box.Right := box.Left + Round(tw + padL + padR);
    box.Bottom := box.Top + Round(th + padT + padB);
    { Clamped into the CONTROL, far edge first -- the same rule the tooltip
      box follows, and for the same reason: what falls outside is not clipped,
      it is not drawn. }
    if box.Right > ARect.Right then OffsetRect(box, ARect.Right - box.Right, 0);
    if box.Bottom > ARect.Bottom then OffsetRect(box, 0, ARect.Bottom - box.Bottom);
    if box.Left < ARect.Left then OffsetRect(box, ARect.Left - box.Left, 0);
    if box.Top < ARect.Top then OffsetRect(box, 0, ARect.Top - box.Top);

    corners := TyEffectiveCorners(labelS);
    if hit.Spec.LabelSpec.HasBorderRadius then
      corners := TyCorners(Round(hit.Spec.LabelSpec.BorderRadiusLogical),
        Round(hit.Spec.LabelSpec.BorderRadiusLogical),
        Round(hit.Spec.LabelSpec.BorderRadiusLogical),
        Round(hit.Spec.LabelSpec.BorderRadiusLogical));
    surface := labelS.Background;
    if hit.Spec.LabelSpec.HasBackground then
    begin
      surface.Kind := tfkSolid;
      surface.Color := TTyColor(hit.Spec.LabelSpec.Background);
    end;
    APainter.FillBackground(box, surface, corners);
    if hit.Spec.LabelSpec.HasBorderColour and hit.Spec.LabelSpec.HasBorderWidth
      and (hit.Spec.LabelSpec.BorderWidthLogical > 0) then
      APainter.StrokeBorder(box, corners,
        Round(hit.Spec.LabelSpec.BorderWidthLogical),
        TTyColor(hit.Spec.LabelSpec.BorderColour))
    else if TyBorderVisible(labelS) then
      APainter.StrokeBorder(box, corners, labelS.BorderWidth, labelS.BorderColor);
    colour := labelS.TextColor;
    if hit.Spec.LabelSpec.HasColour then colour := TTyColor(hit.Spec.LabelSpec.Colour);
    APainter.DrawText(box, txt, labelS.FontName, ResolveFontSize(labelS),
      labelS.FontWeight, colour, taCenter, tlCenter, False);
  end;
end;

function TTyAdvanceChart.ValuesText(
  const AParams: TTyChartCallbackParams): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(AParams.Values) do
  begin
    if i > 0 then Result := Result + '  ';
    Result := Result + TyTooltipValueText(AParams.Values[i]);
  end;
end;

function TTyAdvanceChart.AxisTooltipParams(
  const AHits: TTyAxisHitArray): TTyChartParams;
var
  i, k, n, slot, row: Integer;
  d: TTyChartDatumRef;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(AHits) do
  begin
    { The cross' other arm carries no series -- see AxisTooltipContent. }
    if AHits[i].Cross then Continue;
    for k := 0 to High(AHits[i].Slots) do
    begin
      slot := AHits[i].Slots[k];
      row := AHits[i].Rows[k];
      if (slot < 0) or (slot > High(FBindings)) then Continue;
      d := TyChartDatum(FBindings[slot].SeriesIndex, row,
        FStores[slot].GetRawIndex(row));
      SetLength(Result, n + 1);
      Result[n] := TooltipParams(d);
      Inc(n);
    end;
  end;
end;

function TTyAdvanceChart.AxisTooltipContent(const AHits: TTyAxisHitArray;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
var
  i, k, slot, row: Integer;
  section: TTyTooltipBlock;
  header, valueText: string;
  d: TTyChartDatumRef;
  p: TTyChartCallbackParams;
  rows: Integer;
begin
  { A HEADERLESS ROOT HOLDING ONE SECTION PER AXIS, each holding one row per
    surviving series. Three layers, and the shape is what decides the spacing
    -- two axis sections space themselves further apart than one does, and
    that falls out of the tree rather than being written anywhere. }
  Result := TTyTooltipBlock.CreateSection('', True);
  rows := 0;
  for i := 0 to High(AHits) do
  begin
    { THE SECOND ARM OF A CROSS NEVER CONTRIBUTES A SECTION. Upstream hard-codes
      its triggerTooltip to false, which is why a cross shows one tooltip and
      not two. }
    if AHits[i].Cross then Continue;
    { THE SAME ROUTINE AS THE POINTER'S LABEL, formatter and precision and
      all -- upstream's header is getValueLabel with the pointer's label
      options -- at the snapped row, which the tooltip always describes. A
      header left blank by the formatter is no header. }
    header := AxisValueText(AHits[i].Axis, AHits[i].SnapValue,
      AHits[i].Spec.LabelSpec);
    section := TTyTooltipBlock.CreateSection(header, False);
    for k := 0 to High(AHits[i].Slots) do
    begin
      slot := AHits[i].Slots[k];
      row := AHits[i].Rows[k];
      if (slot < 0) or (slot > High(FBindings)) then Continue;
      d := TyChartDatum(FBindings[slot].SeriesIndex, row,
        FStores[slot].GetRawIndex(row));
      p := TooltipParams(d);
      if Length(p.Values) = 0 then Continue;
      valueText := ValuesText(p);
      { UNDER AN AXIS TRIGGER THE INLINE NAME IS THE SERIES NAME, not the item
        name -- upstream passes `multipleSeries = true`, which both suppresses
        the per-series header AND switches the name. The item name is already
        the section's header, so repeating it on every row would say the
        category once per series. }
      section.Add(TTyTooltipBlock.CreateNameValue(ttmItem, p.Color,
        p.SeriesName, False, valueText, False)).SortParam := p.Values[0];
      Inc(rows);
    end;
    { `order` SORTS THE ROWS WITHIN ONE SECTION and nothing else. Upstream sets
      `sortBlocks` on the AXIS SECTION -- never on the root -- so a port that
      sorted the root would reorder the AXES and leave every row where it was.
      It runs after the reverse, and the reverse is unconditional. }
    if ASpec.HasOrder then section.SortBlocks(ASpec.Order);
    { THE SECTION IS ADDED WHETHER OR NOT ANY SERIES SURVIVED. Upstream pushes
      it before the series loop runs, so an axis with nothing on it still
      contributes its header line. }
    Result.Add(section);
  end;
  { THE SECTIONS ARE REVERSED, unconditionally and across coordinate systems
    rather than within one -- upstream's own comment is that the second axis
    displays above the first. }
  Result.Reverse;
  if rows = 0 then FreeAndNil(Result);
end;

procedure TTyAdvanceChart.PaintTooltip(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  onAxis: Boolean;
  spec: TTyTooltipSpec;
  ink: TTyTooltipInk;
  block: TTyTooltipBlock;
  lines: TTyTooltipLineArray;
  st: TTyStyleSet;
  params: TTyChartParams;
  tipText: string;
  w, h, lineH, gap, cx, cy: Double;
  padL, padT, padR, padB, radius, borderW: Double;
  box: TTyRectF;
  r: TRect;
  i, j, row, lineTop: Integer;
  corners: TTyCorners;
  surface: TTyFill;
  borderCol: TTyColor;
begin
  if not FTipTrack then Exit;
  onAxis := Length(FTipHits) > 0;
  if not TyChartDatumValid(FTipDatum) and not onAxis then Exit;
  { UNDER AN AXIS TRIGGER THERE IS NO CASCADE. Upstream builds the axis
    tooltip's model from the global component and a positioning hint and
    nothing else -- no series level, no data item -- so every option but
    valueFormatter is global there. }
  if onAxis then spec := TyTooltipSpecOf(FOption, -1, -1)
  else spec := TooltipSpecFor(FTipDatum);
  if not spec.Show or not spec.ShowContent then Exit;
  { AN AXIS HIT OUTRANKS AN ITEM ONE. Upstream routes on the payload's SHAPE --
    if a coordinate system reported axes, the axis path runs and the item
    trigger is never consulted. }
  if not onAxis and (spec.Trigger <> tttItem) then Exit;
  ink := TooltipInk(spec);

  st := ActiveController.Model.ResolveStyle('TyAdvChartTooltip', StyleClass,
    [tysNormal]);
  { NO BOX WITHOUT A BACKGROUND. A theme that defines no tooltip surface gets
    no tooltip -- never a hard-coded colour, which is the rule the old chart
    already follows and the reason the key lives in the base layer where every
    theme inherits it. }
  if not (tpBackground in st.Present) then Exit;

  block := nil;
  try
    if spec.HasFormatter then
    begin
      { A FORMATTER REPLACES THE CONTENT, it does not decorate it. Upstream
        builds the default markup first and then throws it away, so a
        formatter with side effects still sees them run; here the default is
        simply not built, which is the same picture for less. }
      SetLength(params, 1);
      { A FORMATTER UNDER AN AXIS TRIGGER IS GIVEN EVERY SERIES, in the order
        the sections hold them -- which is what makes `{a1}` and `{c2}` mean
        anything at all. }
      if onAxis then params := AxisTooltipParams(FTipHits)
      else params[0] := TooltipParams(FTipDatum);
      if Length(params) = 0 then Exit;
      if not TyChartResolveText(spec.Formatter, params, tipText) then
        { A named handler that is not registered says so rather than drawing
          nothing -- TyChartResolveText puts the message in the text. }
        ;
      if Trim(tipText) = '' then Exit;
      block := TTyTooltipBlock.CreateSection('', True);
      { THE WHOLE STRING AS ONE NAME. A formatter's output is words, not a
        name/value pair, so it takes the name ink and no gutter -- and with
        neither marker nor name flag set the row is the third case upstream
        has and most ports do not: no marker, no right-alignment. }
      block.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, tipText, False,
        '', True));
    end
    else if onAxis then
      block := AxisTooltipContent(FTipHits, spec)
    else
      block := TooltipContent(FTipDatum, spec);
    if block = nil then Exit;

    lines := TyTooltipFlatten(block, ink);
    if Length(lines) = 0 then Exit;

    if spec.HasPadding then
    begin
      padL := APainter.ScaleF(spec.PadLeft);
      padT := APainter.ScaleF(spec.PadTop);
      padR := APainter.ScaleF(spec.PadRight);
      padB := APainter.ScaleF(spec.PadBottom);
    end
    else
    begin
      padL := APainter.Scale(st.Padding.Left);
      padT := APainter.Scale(st.Padding.Top);
      padR := APainter.Scale(st.Padding.Right);
      padB := APainter.Scale(st.Padding.Bottom);
    end;

    TyTooltipMeasure(lines, ink, AMeasurer, APPI, padL, padT, padR, padB, w, h);
    if (w <= 0) or (h <= 0) then Exit;

    gap := APainter.ScaleF(ActiveController.Metric(TyAdvChartTooltipGapVar,
      TyAdvChartTooltipGap));
    box := TyTooltipBoxAt(FTipX, FTipY, w, h, gap,
      TyRectF(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom));
    r := Rect(Round(box.Left), Round(box.Top),
              Round(box.Right), Round(box.Bottom));

    corners := TyEffectiveCorners(st);
    if spec.HasBorderRadius then
    begin
      radius := spec.BorderRadiusLogical;
      corners.TL := Round(radius);
      corners.TR := corners.TL;
      corners.BR := corners.TL;
      corners.BL := corners.TL;
    end;

    { NOT DrawFrame. That is the CONTROL's frame path and it pushes tpOpacity
      onto the painter, which EndPaint then applies to the WHOLE bitmap -- a
      tooltip style carrying an opacity would fade the entire chart. So the
      box paints its own surface, and a translucent panel has to arrive as an
      alpha-bearing background colour rather than as an opacity. }
    if (tpShadow in st.Present) and (TyAlphaOf(st.ShadowColor) > 0) then
      APainter.DropShadow(r, st.BorderRadius, st.ShadowColor, st.ShadowBlur,
        st.ShadowOffset);
    { THE THEME'S FILL, with only its COLOUR replaced when the option named
      one -- so a skin that made the tooltip a gradient or an image keeps that
      treatment for every chart whose author did not overrule it. }
    surface := st.Background;
    if spec.HasBackground then
    begin
      surface.Kind := tfkSolid;
      surface.Color := TTyColor(spec.Background);
    end;
    APainter.FillBackground(r, surface, corners);

    { THE BORDER IS TINTED WITH THE HOVERED ITEM'S COLOUR, which is the
      signature ECharts 6 look and is easy to miss: the grey token is the
      fallback for an AXIS tooltip, and an item tooltip takes the datum's own
      colour. A written borderColor still wins over both. }
    if spec.HasBorderColour then borderCol := TTyColor(spec.BorderColour)
    else if not onAxis and (DatumColour(FTipDatum) <> 0) then
      borderCol := TTyColor(DatumColour(FTipDatum))
    else
      { THE GREY IS THE AXIS TOOLTIP'S ANSWER, not a chart-wide default: a box
        describing several series cannot take one of their colours. }
      borderCol := st.BorderColor;
    borderW := st.BorderWidth;
    if spec.HasBorderWidth then borderW := spec.BorderWidthLogical;
    if (borderW > 0) and (TyAlphaOf(borderCol) > 0) then
      APainter.StrokeBorder(r, corners, Round(borderW), borderCol);

    lineH := APainter.ScaleF(ink.LineHeightLogical);
    row := 0;
    for i := 0 to High(lines) do
    begin
      row := row + lines[i].BlankLinesBefore;
      lineTop := Round(box.Top + padT + row * lineH);
      for j := 0 to High(lines[i].Runs) do
        if lines[i].Runs[j].Kind = ttrMarker then
        begin
          cx := box.Left + padL + lines[i].Runs[j].X
                + lines[i].Runs[j].W / 2;
          cy := lineTop + lineH / 2;
          { BeginPath FIRST. CirclePath APPENDS to the canvas' current path,
            it does not start one -- so without this the fill takes in
            whatever the static pass left half-built and paints it in the
            marker's colour. It drew a blue rectangle over a legend label,
            and the pixel test that counts what changed between two frames
            went green on it, because the wrong pixels are still pixels. }
          APainter.BeginPath;
          APainter.CirclePath(cx, cy, lines[i].Runs[j].W / 2);
          APainter.FillPath(TTyColor(lines[i].Runs[j].Colour));
        end
        else
        begin
          { NO ELLIPSIS. The box was measured to fit these exact runs, and
            upstream never wraps or truncates a tooltip in either mode -- its
            width is content-driven and its CSS says `white-space: nowrap`. }
          APainter.DrawText(
            Rect(Round(box.Left + padL + lines[i].Runs[j].X), lineTop,
                 Round(box.Left + padL + lines[i].Runs[j].X
                       + lines[i].Runs[j].W) + 1,
                 Round(lineTop + lineH)),
            lines[i].Runs[j].Text, lines[i].Runs[j].FontName,
            lines[i].Runs[j].FontSizeLogical, lines[i].Runs[j].FontWeight,
            TTyColor(lines[i].Runs[j].Colour), taLeftJustify, tlCenter, False);
        end;
      Inc(row);
    end;
  finally
    block.Free;
  end;
end;

procedure TTyAdvanceChart.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  d: TTyChartDatumRef;
  spec: TTyTooltipSpec;
  el: Integer;
  wasOn: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  if csDesigning in ComponentState then Exit;
  spec := TyTooltipSpecOf(FOption, -1, -1);
  { NOTHING ABOUT THE TOOLTIP IS CHECKED HERE, and that is the point. What is
    under the pointer is a fact about geometry; whether a BOX is drawn for it
    is a question for the paint. A chart with `tooltip: {show: false}` still
    highlights the mark under the cursor -- upstream highlights from zrender's
    own hover and the tooltip is a separate listener -- and gating the hover on
    the tooltip made switching the box off switch the highlight off too.

    `triggerOn` IS read here, because it is genuinely about the pointer: it
    decides whether MOVEMENT drives the tooltip at all. The answer is carried
    rather than acted on, so the highlight is unaffected by it. }
  FTipTrack := TyTooltipTriggerOnHas(spec.TriggerOn, 'mousemove');

  wasOn := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0);
  d := HitTestAt(X, Y, el);
  FTipDatum := d;
  FTipElement := el;
  FTipX := X;
  FTipY := Y;
  { AN AXIS HOVER IS A SECOND, INDEPENDENT PIECE OF STATE, live whenever the
    pointer is inside a plot and something asks for an axis pointer -- the
    trigger, or a cross -- whether or not a mark happens to be under it, which
    is the whole point of an axis trigger.

    RESOLVED HERE AND KEPT, not re-resolved in the frame that draws it: the
    answer holds axis POINTERS into the build, and DropBuild clears it for
    exactly that reason. }
  FTipHits := ResolveAxisPointers(X, Y);
  { REPAINT ON MOVEMENT, not only when the datum changes. The box is anchored
    to the CURSOR -- upstream positions against the raw pointer offsets and
    never against the snapped datum -- so a repaint gated on the datum would
    leave it standing still while the pointer walked away from it. The frame
    this asks for is a blit of the static layer plus one box; the gate the old
    TTyChart needed was compensating for a control that re-rendered everything
    from scratch each paint, and that is what the cache removed. }
  if wasOn or TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0) then
    InvalidateFrame;
end;

procedure TTyAdvanceChart.MouseLeave;
var wasOn: Boolean;
begin
  wasOn := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0);
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  FTipHits := nil;
  { INHERITED LAST. The base class ends in PointerStateChanged, which this
    control answers with a repaint -- and a repaint before the hover was
    cleared would draw the tooltip one more time on the way out. }
  inherited MouseLeave;
  if wasOn then InvalidateFrame;
end;

procedure TTyAdvanceChart.PaintDynamic(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
begin
  { WHAT IS DRAWN HERE IS COMPOSITED OVER the blitted static layer: BeginPaint
    fills its bitmap transparent and EndPaint blends it (TBGRABitmap.Draw with
    AOpaque = False), so an overlay painter adds ink without erasing what is
    underneath. That is what makes two painters onto one canvas correct.

    ANYTHING ADDED HERE MUST BE VISIBLE TO HasDynamicContent, or RenderCached
    skips the whole pass and the new thing is written, compiled and never
    drawn. That is the failure this body's empty version was left here to
    prevent, and the tooltip is the first thing to test it. }
  { THE POINTER UNDER THE HIGHLIGHT UNDER THE BOX. A shadow band drawn over
    the bars is the layer debt showing -- series marks live in the static
    layer, so the band cannot go beneath them -- and re-drawing the hovered
    marks on top of the band is what hides it. }
  PaintAxisPointers(APainter, ARect, APPI, AMeasurer, FTipHits);
  PaintEmphasis(APainter, APPI, FTipHits);
  { THE POINTER FIRST, THE BOX OVER IT. A tooltip with the pointer's own line
    drawn across it would read as two things at one depth. }
  PaintTooltip(APainter, ARect, APPI, AMeasurer);
end;

function TTyAdvanceChart.HasDynamicContent: Boolean;
begin
  { A REAL QUESTION NOW: is anything hovered. A second painter means allocating
    a BGRA bitmap the size of the control, filling it, blending it and freeing
    it -- roughly the 13 ms floor a frame has even with no axes -- so the
    answer has to be cheap and it has to be exact. It is deliberately not
    "would the tooltip draw": resolving the option cascade and the theme to
    find out costs more than the pass it would save. }
  Result := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0);
end;

procedure TTyAdvanceChart.DropStatic;
begin
  if FStatic <> nil then FStatic.Drop;
  { AND THE LIST WITH IT. The two describe the same frame: the list is what
    the static pass added up to, so a kept list beside a dropped cache would
    answer questions about a picture no longer on screen. Not freed -- the
    next build reuses the object and only the answer is stale. }
  FPaintListValid := False;
end;

procedure TTyAdvanceChart.PointerStateChanged;
begin
  InvalidateFrame;
end;

procedure TTyAdvanceChart.RenderCached(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
var
  P: TTyPainter;
  R: TRect;
  w, h: Integer;
  measurer: ITyTextMeasurer;
begin
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;
  R := Rect(0, 0, w, h);

  if FStatic = nil then FStatic := TTyPaintCache.Create;
  { PPI IS PART OF THE KEY and TTyPaintCache does not know it: NeedsRender only
    notices a size change, and a per-monitor DPI move can hand back the same
    size at a different PPI -- a chart drawn for 96 blitted onto a 192 window. }
  if APPI <> FStaticPPI then
  begin
    FStatic.Drop;
    FStaticPPI := APPI;
  end;

  if FStatic.NeedsRender(w, h) then
  begin
    measurer := TTyPainterTextMeasurer.Create(APPI);
    P := TTyPainter.Create;
    try
      P.BeginPaint(FStatic.Canvas, R, APPI);
      PaintStatic(P, R, APPI, measurer);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  FStatic.Blit(ACanvas);

  { A SECOND PAINTER ONLY WHEN THERE IS SOMETHING TO PUT IN IT. Creating one
    means allocating a BGRA bitmap the size of the control, filling it,
    blending it and freeing it -- roughly the 13 ms floor a frame has even with
    no axes, so paying it to draw nothing would give back most of what the
    cache just saved. }
  if not HasDynamicContent then Exit;
  measurer := TTyPainterTextMeasurer.Create(APPI);
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    PaintDynamic(P, R, APPI, measurer);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyAdvanceChart.Paint;
begin
  { THE DESIGNER RENDERS STRAIGHT THROUGH, as TTyPanel's does: it repaints
    rarely and streams while it does, so a cache buys nothing there and is one
    more thing that can be holding a frame from before the last property
    change. }
  if csDesigning in ComponentState then
  begin
    RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  RenderCached(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyAdvanceChart.SaveToPng(const AFileName: string);
var bmp: TBGRABitmap;
begin
  if (Width <= 0) or (Height <= 0) then Exit;
  bmp := TBGRABitmap.Create(Width, Height);
  try
    RenderTo(bmp.Canvas, Rect(0, 0, Width, Height), Font.PixelsPerInch);
    bmp.SaveToFile(AFileName);
  finally
    bmp.Free;
  end;
end;

end.
