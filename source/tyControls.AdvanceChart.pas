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
  Classes, SysUtils, Math, Types, Controls, Graphics, LCLType, ExtCtrls,
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
  tyControls.AdvChart.Color, tyControls.AdvChart.VisualMap,
  tyControls.AdvChart.VisualMapView,
  tyControls.AdvChart.DataZoom, tyControls.AdvChart.DataZoomView,
  tyControls.AdvChart.DataZoomAct, tyControls.AdvChart.ZrPath,
  tyControls.AdvChart.Marker, tyControls.AdvChart.MarkerView,
  tyControls.AdvChart.Pie, tyControls.AdvChart.Funnel,
  tyControls.AdvChart.Gauge, tyControls.AdvChart.Radar,
  tyControls.AdvChart.Calendar, tyControls.AdvChart.Tree,
  tyControls.AdvChart.Sunburst, tyControls.AdvChart.Treemap,
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

  { A GRAPH ROAM, as upstream's `graphroam` event reports it: once per action,
    whether a gesture or the API dispatched it, with the series it moved. }
  TTyGraphRoamEvent = procedure(Sender: TObject;
    const APayload: TTyGraphRoamPayload) of object;

  { A dataZoom ACTION, as upstream's `datazoom` event reports it: once per
    action, from a gesture, the throttle's timer or DispatchDataZoom. }
  TTyDataZoomEvent = procedure(Sender: TObject; const AAction: TTyDzAction) of object;

  { What the pointer is over, as zrender's findHover answers for a slider:
    one of its non-silent elements, some other element of the chart (a
    series mark), or nothing. }
  TTyDzTargetKind = (dtkNone, dtkSlider, dtkOther);
  TTyDzTarget = record
    Kind: TTyDzTargetKind;
    Slider: Integer;
    Role: TTyDzRole;
  end;
  TTyDzPointer = (dpMove, dpDown, dpUp, dpClick, dpWheel);

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
    { THE CALENDARS, one per component, laid out on the canvas. [Batch 69] }
    FCalendars: array of TTyCalendar;
    { THE TREES, laid out per slot -- an empty record where the slot is no
      tree. [Batch 73] }
    FTrees: array of TTyTreeSolved;
    { THE SUNBURSTS, per slot. [Batch 75] }
    FSunbursts: array of TTySunburstSolved;
    { THE TREEMAPS and their inks, per slot: the labels are cut to their
      cells when the layout is, so the specs are read then. [Batch 76] }
    FTreemaps: array of TTyTreemapSolved;
    FTreemapInks: array of TTyTreemapInk;
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
    { The PPI the last layout ran at -- alignment works in logical px. }
    FLastPPI: Integer;
    { WHAT EACH GRAPH'S ROAM LEFT, by SERIES index and outside the build for
      the same reason as FGraphForce: upstream writes it back into the
      series' option, so it survives a resize and a merge and goes only with
      the option. }
    FGraphRoam: array of TTyGraphRoamState;
    { THE COMPENSATION SCALE each laid-out graph is drawn with, by slot. Set
      by every layout and every zoom -- and NOT by a pan, which leaves it at
      whatever the last zoom made it, exactly as upstream leaves its
      elements' scale. }
    FGraphNodeScale: array of Double;
    { THE DRAG IN PROGRESS: the series a left press armed, or -1, and where
      the pointer was last. }
    FRoamSeries: Integer;
    FRoamX, FRoamY: Integer;
    FOnGraphRoam: TTyGraphRoamEvent;
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
    { THE visualMap COMPONENTS, completed, and what they wrote: per binding
      slot, one row per raw datum (nil when none targets the slot) and the
      continuous components' visualMetas, in component order. The line fill
      is solved on the laid-out axes, per slot, at the last render. }
    FVisualSpecs: TTyVisualMapSpecArray;
    { dataZoom: the models, the axes each one hosts with the raw extent its
      window was measured on, and the windows (by hosted axis). }
    FZoomSpecs: TTyDataZoomSpecArray;
    FAxisZooms: TTyAxisZoomArray;
    FZoomWindows: array of TTyDzWindow;
    FZoomHost: array of Integer;
    { weakFilter's predicate state }
    FWfStore: TTyDataStore;
    FWfCols: TTyIntegerArray;
    FWfLo, FWfHi: Double;
    FVisualRows: array of TTyVisualRowArray;
    FVisualMetas: array of TTyVisualMetaArray;
    FVisualLines: array of TTyVisualLineFill;
    { AND THE COMPONENTS' OWN PICTURES: what each one's option says it looks
      like, and where the last layout put it. }
    FVisualViews: array of TTyVmViewSpec;
    FVisualLayouts: array of TTyVisualMapLayout;
    { a slider dataZoom's own picture, by the author's dataZoom index }
    FDzViews: array of TTyDzSliderSpec;
    FDzLayouts: array of TTyDzSliderLayout;
    { SERIES MARKERS, index-parallel to FBindings: markPoint / markLine /
      markArea as the last layout solved them. Solved in Relayout, after the
      bars, because an end on a bar sits on its bar within the band. }
    FMarkers: TTyMkSeriesArray;
    { each series' markLine pictures, index-parallel to FBindings }
    FMarkLinePics: array of TTyMkLinePicArray;
    FMarkPointPics: array of TTyMkPointPicArray;
    FMarkAreaPics: array of TTyMkAreaPicArray;
    { dataZoom INTERACTION, by the author's dataZoom index: the window
      setRawRange left (percents), how each answers the pointer, each
      slider view's own state, each inside's view range }
    FDzRawHas: array of Boolean;
    FDzRawStart, FDzRawStop: TTyDoubleArray;
    FDzInteract: array of TTyDzInteractSpec;
    FDzState: array of TTyDzSliderState;
    FDzInLo, FDzInHi: TTyDoubleArray;
    { a roam controller's throttle and its latest batch, by grid }
    FDzRoamThrottle: array of TTyDzThrottle;
    FDzRoamBatch: array of TTyDzActionItemArray;
    { the slider whose own action is being rendered, -1 for none }
    FDzFrom: Integer;
    { the pointer: what it is over, what the press was on and where, the
      dragged element and its last point, the grid being panned }
    FDzHover, FDzDownTarget, FDzUpTarget, FDzDrag: TTyDzTarget;
    FDzHasDown: Boolean;
    FDzDownX, FDzDownY, FDzDragX, FDzDragY, FDzPanX, FDzPanY: Double;
    FDzPanGrid: Integer;
    { the last pointer position, device px }
    FDzLastX, FDzLastY: Double;
    FDzCursor: string;
    FDzBaseCursor: TCursor;
    FDzHasBaseCursor: Boolean;
    { the clock: NaN is the machine's, a number a test's }
    FDzNow: Double;
    FDzTimer: TTimer;
    FOnDataZoom: TTyDataZoomEvent;
    { `itemStyle.color: 'none'` -- the series paints NO fill. Not the same as
      unwritten, which is the palette's. }
    FSeriesColorNone: array of Boolean;
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
    procedure SolveVisualMaps;
    procedure SolveDataZooms;
    function WeakKeep(ARawIndex: Integer): Boolean;
    procedure SolveVisualMapViews(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    function VisualMapInk(const AView: TTyVmViewSpec): TTyVisualMapInk;
    function VisualMapContent(const AView: TTyVmViewSpec): TTyVisualColor;
    function BuildVisualMaps(AList: TTyPaintList): Integer;
    procedure SolveDataZoomViews(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    procedure SolveMarkers(APPI: Integer);
    function MarkerSeriesColorCss(ASlot: Integer): string;
    function MarkerSeriesColorData(ASlot: Integer): TJSONData;
    procedure MarkerGround(out ABackground: string; out AIsDark: Boolean);
    function BuildMarkers(const AMeasurer: ITyTextMeasurer; AList: TTyPaintList): Integer;
    { ---- dataZoom interaction ---- }
    function DzRepresentative(AIndex: Integer): Integer;
    procedure DzRenderStates;
    function DzScale: Double;
    function DzClock: Double;
    function DzGridRect(AGrid: Integer): TTyXYWH;
    function DzGridContains(AGrid: Integer; AX, AY: Double): Boolean;
    function DzGridInsides(AGrid: Integer): TTyIntegerArray;
    function DzControlType(AGrid: Integer): Integer;
    function DzFindTarget(AX, AY: Double): TTyDzTarget;
    function DzHits(ASlider: Integer; ARole: TTyDzRole; AX, AY: Double): Boolean;
    procedure DzToSlider(ASlider: Integer; AX, AY: Double; out LX, LY: Double);
    function DzSpans(AIndex: Integer; out AMin, AMax: Double): Boolean;
    procedure DzShowDataInfo(AIndex: Integer; AEmphasis: Boolean);
    procedure DzMouseOut(const ATarget: TTyDzTarget);
    procedure DzMouseOver(const ATarget: TTyDzTarget);
    procedure DzDragMove(AIndex, AHandle: Integer; ADX, ADY: Double);
    procedure DzDragEnd(AIndex: Integer);
    procedure DzClickPanel(AIndex: Integer; AX, AY: Double);
    procedure DzBrushMove(AIndex: Integer; AX, AY: Double);
    procedure DzBrushEnd(AIndex: Integer);
    procedure DzSliderDispatch(AIndex: Integer; ARealtime: Boolean);
    procedure DzRunSliderAction(AIndex: Integer; ADeferred: Boolean);
    function DzRoam(AGrid: Integer; const AKind: string; AShift: TShiftState;
      AOldX, AOldY, ANewX, ANewY, AScale, AScroll: Double): Boolean;
    procedure DzRoamDispatch(AGrid: Integer; const AItems: TTyDzActionItemArray);
    procedure DzDispatch(const AAction: TTyDzAction);
    procedure DzViewUpdate;
    function DzStateKey: string;
    procedure DzSyncLayout;
    procedure DzApplyCursor;
    procedure DzArmTimer;
    procedure DzTimerFired(Sender: TObject);
    function DataZoomInk(const ASpec: TTyDzSliderSpec): TTyDzInk;
    function DataZoomInput(AIndex: Integer; out AIn: TTyDzSliderInput): Boolean;
    function BuildDataZooms(AList: TTyPaintList): Integer;
    procedure ApplyVisualMaps(var AVisual: TTySeriesVisual; ASlot,
      APPI: Integer);
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
    procedure SolveCalendars(APPI: Integer);
    procedure FreeCalendars;
    function CalendarInk: TTyCalendarInk;
    procedure FreeRadars;
    procedure SolveGraphs(APPI: Integer);
    procedure FreeGraphs;
    procedure SolveTrees(APPI: Integer);
    procedure SolveSunbursts(APPI: Integer);
    procedure SolveTreemaps(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    function TreemapInk(ASlot: Integer): TTyTreemapInk;
    function SunburstInk(ASlot: Integer): TTySunburstInk;
    function TreeInk(ASlot: Integer): TTyTreeInk;
    function LabelBaseFor(ASlot: Integer): TTyLabelSpec;
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
    function HeatmapRadii(ASeriesIndex, APPI: Integer): TTyCornerRadii;
    procedure RippleOf(ASlot: Integer; var AVisual: TTySeriesVisual);
    function CalendarPieLayout(ASlot, ADim: Integer): TTyPieLayout;
    function CalendarGraphPoints(ASeriesIndex: Integer;
      ACal: TTyCalendar): TTyPointFArray;
    procedure SymbolItems(ASeriesIndex: Integer; const ABase: TTySymbolSpec;
      out ASpecs: TTySymbolSpecArray; out AHas: TTyBoolArray);
    procedure HeatmapItemRadii(ASeriesIndex, APPI: Integer;
      out ARadii: TTyCornerRadiiArray; out AHas: TTyBoolArray);
    procedure ItemLabelSpecs(ASeriesIndex: Integer; const ABase: TTyLabelSpec;
      out ASpecs: TTyLabelSpecArray; out AHas: TTyBoolArray);
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
    procedure SeriesDataEncode(ASlot: Integer; var ADims: TTySeriesDimArray;
      out AEnc: TTySeriesEncode);
    { upstream's defaultedLabel and defaultedTooltip for one axis series,
      into its store as raw positions. }
    procedure ResolveTextDims(const AEnc: TTySeriesEncode; AStore: TTyDataStore);
    { The series' MODEL name -- what `{a}` and a handler's seriesName print:
      as written, '' when written '', and the auto name `series\0<index>`
      when not written at all. SeriesNameOf is the DISPLAY name, '' then. }
    function SeriesModelName(ASeriesIndex: Integer): string;
    { A radar's own item tooltip: headed by the item, a row per indicator. }
    function RadarTooltip(ASlot, ARow: Integer; const AColor: TTyChartColor;
      const ASpec: TTyTooltipSpec): TTyTooltipBlock;
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
    { ONE GRAPH ELEMENT'S emphasis AND blur, down its model chain: a node's
      data item, then its category, then the series; an edge's link, then the
      series. `focusNodeAdjacency`, the old spelling, counts at the series
      when `emphasis.focus` says nothing. AIndex is into FGraphNodes /
      FGraphEdges of ASlot. }
    function GraphEmphasisOf(ASlot: Integer; AIsEdge: Boolean;
      AIndex: Integer): TTyChartEmphasisSpec;
    { THE HOVER, APPLIED TO THE GRAPHS IN THE LIST: every element of the
      hovered graph -- and of every other graph its blurScope reaches --
      blurred, the focus sets spared, and the hovered element raised IN
      PLACE. A graph is not overlaid by PaintEmphasis: a translucent edge
      drawn twice darkens, and a lifted copy would cover the nodes. }
    procedure ApplyGraphHover(AList: TTyPaintList; APPI: Integer);
    { True when the datum is on a laid-out graph. }
    function IsGraphDatum(const ADatum: TTyChartDatumRef): Boolean;
    { The static layer again with the same build and the same list -- a
      hover on a graph restyles what is already there. }
    procedure RestyleStatic;
    { The chart's ground for label halos, and whether it counts as dark. }
    procedure LabelGround(out AGround: TTyChartColor; out ADark: Boolean);
    function EmphasiseElement(AIndex: Integer; APPI: Integer;
      out AElement: TTyChartElement): Boolean;
    { Every value of one datum as one string, for a store that kept no raw
      item or chose no tooltip dimensions (TipCellsOf answers the rest).
      Several go on ONE row joined by two spaces, which is upstream's
      richText spelling of the list html joins with two non-breaking spaces.
      [Batch 50: a candlestick does NOT take this branch upstream -- its
      dimensions have display names, so it gets a sub-row per value.] }
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
    { What the bar solve gave a series -- its band, offset and width. An
      unsolved column (not a bar, or no such series) when there is none. }
    function BarColumnOf(ASeriesIndex: Integer): TTyBarColumn;
    { What every render measures its text with: the painter's own, in the
      theme's fonts. Virtual so a text table -- zrender's, for a chart laid
      out against upstream's -- can stand in for the fonts. }
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; virtual;
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
    { THE ROAM GESTURES. A left press inside a graph's roam area arms a drag
      that pans by every movement after it -- off the control too -- until
      the left button comes up or the capture is lost; a wheel turn over the
      area zooms about the pointer. A wheel no graph takes is answered False,
      so the host scrolls. }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure CaptureChanged; override;
    { The graph a gesture at (AX, AY) goes to: the first, in upstream's order
      -- highest zlevel, then z, then the lowest series index -- whose roam
      allows it and whose area holds the point. -1 when none does. }
    function RoamSeriesAt(AX, AY: Integer; AZoom: Boolean): Integer;
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
    { THE visualMap MODEL AS THE LAST BUILD SOLVED IT: the completed
      components, what they wrote on the datum at ARawIndex of series
      ASeriesIndex, that series' visualMetas, and the fill its line took at
      the last render. False / empty where there is none. }
    function VisualMapCount: Integer;
    function VisualMapSpec(AIndex: Integer): TTyVisualMapSpec;
    function VisualRow(ASeriesIndex, ARawIndex: Integer;
      out ARow: TTyVisualRow): Boolean;
    function VisualMetas(ASeriesIndex: Integer): TTyVisualMetaArray;
    function VisualLineFill(ASeriesIndex: Integer): TTyVisualLineFill;
    { THE COMPONENT AIndex AS THE LAST RENDER LAID IT OUT: Valid is False
      when it is hidden, piecewise, or nothing has rendered. }
    function VisualMapLayout(AIndex: Integer): TTyVisualMapLayout;
    { THE dataZoom MODELS AS THE LAST BUILD SOLVED THEM, and the window on an
      axis: False when no dataZoom hosts that axis. AHost is the dataZoom
      that owns it. }
    function DataZoomCount: Integer;
    function DataZoomSpec(AIndex: Integer): TTyDataZoomSpec;
    { THE SLIDER AIndex AS THE LAST RENDER LAID IT OUT: Valid is False when
      it is hidden, has no target, is not a slider, or nothing has rendered. }
    function DataZoomSliderLayout(AIndex: Integer): TTyDzSliderLayout;
    { A SERIES' MARKERS OF ONE KIND AS THE LAST LAYOUT SOLVED THEM: Present
      is False when the series has none of that kind (no `data`), is not on
      a cartesian grid, is switched off by the legend, or nothing has
      rendered. }
    function MarkerLayout(ASeriesIndex: Integer; AKind: TTyMarkerKind): TTyMkBlock;
    { THE markLine PICTURES of a series as the last layout drew them, one per
      surviving line in data order; empty when there are none. }
    function MarkLinePictures(ASeriesIndex: Integer): TTyMkLinePicArray;
    { THE markPoint PICTURES likewise }
    function MarkPointPictures(ASeriesIndex: Integer): TTyMkPointPicArray;
    { THE markArea PICTURES likewise }
    function MarkAreaPictures(ASeriesIndex: Integer): TTyMkAreaPicArray;
    { THE dataZoom ACTION, upstream's dispatchAction({type: 'dataZoom',
      dataZoomIndex, start, end}): the percent window goes on dataZoom AIndex
      and on every dataZoom linked to it through a shared axis, and the chart
      follows at once. False when there is no such dataZoom. }
    function DispatchDataZoom(AIndex: Integer; AStart, AEnd: Double): Boolean;
    { THE POINTER, as the mouse handlers feed it: device px on this control.
      Answers whether upstream would have stopped the event (a wheel in a
      zooming grid, a drag). Public so a test can drive a gesture step by
      step, with the click as a step of its own. }
    function DataZoomPointer(AKind: TTyDzPointer; AX, AY: Double;
      AShift: TShiftState; AZrDelta: Double): Boolean;
    { The throttle's timer: every deferred dispatch due by ANow (ms) runs. }
    procedure DataZoomTick(ANow: Double);
    { the state behind the pointer, for a test }
    function DataZoomSliderState(AIndex: Integer): TTyDzSliderState;
    function DataZoomInsideRange(AIndex: Integer; out ALo, AHi: Double): Boolean;
    function DataZoomHoverName: string;
    property DataZoomCursorName: string read FDzCursor;
    { ms; NaN (the default) is the machine's clock }
    property DataZoomNow: Double read FDzNow write FDzNow;
    function AxisZoom(const AMainType: string; AAxisIndex: Integer;
      out AZoom: TTyAxisZoom; out AWindow: TTyDzWindow; out AHost: Integer): Boolean;
    { The rows of series ASeriesIndex as the last build left them -- filtered
      by the dataZooms. nil when there is no such series. }
    function SeriesStore(ASeriesIndex: Integer): TTyDataStore;
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
    { THE ROAM ACTIONS, upstream's `graphRoam` dispatched by hand: a pan by
      (ADX, ADY) pixels, or a zoom by AScale about (AOriginX, AOriginY).
      ASeriesIndex -1 moves every graph on a view. NOT gated by the series'
      `roam` -- an action is an action. Nothing is laid out again: the
      picture is remapped and repainted. False when no graph on a view was
      moved -- nothing rendered yet, the series is not one, or a zoom that is
      not a positive finite number. }
    function GraphRoam(ASeriesIndex: Integer; ADX, ADY: Double): Boolean;
    function GraphZoom(ASeriesIndex: Integer; AScale, AOriginX,
      AOriginY: Double): Boolean;
    function GraphDispatchRoam(const APayload: TTyGraphRoamPayload): Boolean;
    { The centre and zoom as the OPTION now says them -- the series' own
      until the first roam, what the roam wrote back after it. The zoom is
      not clamped; GraphView(..).Zoom is the one the view uses. }
    function GraphRoamState(ASeriesIndex: Integer; out ACentre: TTyGraphCentre;
      out AZoom: Double): Boolean;
    { The view itself, for a test to read the transform of. nil when the
      series is not a laid-out graph on a view. Owned by the control and gone
      at the next layout. }
    function GraphView(ASeriesIndex: Integer): TTyGraphView;
    { The compensation scale the graph is drawn with -- stale across pans. }
    function GraphNodeScale(ASeriesIndex: Integer): Double;
    { Radar component AIndex as the last render resolved it -- its spokes'
      scales, rings and angles -- or nil. Owned by the control and gone at
      the next layout. }
    function RadarLayout(AIndex: Integer): TTyRadar;
    { Calendar component AIndex as the last render laid it out, or nil. }
    function CalendarLayout(AIndex: Integer): TTyCalendar;
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
      now. When a brush or a keyboard tooltip lands, this flips to True
      and the class moves to the focusable table -- which the tables in
      test.focus.tabstop.pas will force somebody to decide rather than drift.
      [Batch 62: dataZoom landed and did NOT flip it. Upstream's dataZoom is
      pointer-only -- drag, click, brush, wheel -- with no key binding at all,
      so the reason this line once gave for it no longer holds.] }
    property TabStop default False;
    property Visible;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
    property OnResize;
    property OnGraphRoam: TTyGraphRoamEvent read FOnGraphRoam write FOnGraphRoam;
    property OnDataZoom: TTyDataZoomEvent read FOnDataZoom write FOnDataZoom;
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
  FRoamSeries := -1;
  FDzFrom := -1;
  FDzPanGrid := -1;
  FDzNow := NaN;
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
  FreeAndNil(FDzTimer);
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
  FreeCalendars;
  FreeGraphs;
  FTrees := nil;
  FSunbursts := nil;
  FTreemaps := nil;
  FTreemapInks := nil;
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
  { notMerge: new series models, so no roam survives either. }
  FGraphRoam := nil;
  FRoamSeries := -1;
  { nor a zoom: the dataZooms are new models, read from what was written }
  FDzRawHas := nil;
  FDzRawStart := nil;
  FDzRawStop := nil;
  FDzState := nil;
  FDzRoamThrottle := nil;
  FDzRoamBatch := nil;
  FDzHover := Default(TTyDzTarget);
  FDzDrag := Default(TTyDzTarget);
  FDzHasDown := False;
  FDzPanGrid := -1;
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
      { A TREE'S ROWS ARE ITS HIERARCHY IN PRE-ORDER under a virtual root --
        never the top-level `data` alone, which would lose every child. Before
        the calendar's branch: a tree on a calendar keeps its own rows.
        [Batch 73] }
      if (FBindings[i].SeriesType = TyTreeSeriesTypeName)
        or (FBindings[i].SeriesType = TySunburstSeriesTypeName)
        or (FBindings[i].SeriesType = TyTreemapSeriesTypeName) then
      begin
        { a sunburst's and a treemap's rows are the same hierarchy, their
          values completed [Batches 75, 76] }
        TyTreeFillStore(FOption, FBindings[i].SeriesIndex, st,
          FBindings[i].SeriesType <> TyTreeSeriesTypeName);
        Continue;
      end;
      { ON A CALENDAR: the calendar's two dimensions, a time and a value --
        element 0 of the row is the date and element 1 the value, and any
        more are raw positions the store keeps for the label and the
        visualMap. [Batch 70] }
      if (FBindings[i].CalendarIndex >= 0)
        and (FBindings[i].SeriesType <> TyPieSeriesTypeName) then
      begin
        st.AddDimension(TyCalendarTimeDim, ddtTime);
        st.AddDimension(TyCalendarValueDim, ddtFloat);
        SetLength(dims, 2);
        dims[0] := Default(TTySeriesDim);
        dims[0].Name := TyCalendarTimeDim;
        dims[0].Kind := ddtTime;
        dims[1] := Default(TTySeriesDim);
        dims[1].Name := TyCalendarValueDim;
        dims[1].Kind := ddtFloat;
        TyFillSeriesStore(FOption, i, dims, st);
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
      SeriesDataEncode(i, dims, enc);
      TyFillSeriesStore(FOption, i, dims, st);
      ResolveTextDims(enc, st);
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
    { A GIVEN ENCODE FILLS WHAT IT LEAVES OUT from the next free columns --
      `encode: {tooltip: [2]}` still draws x from 0 and y from 1. }
    if enc.Given then TyEncodeFillUnclaimed(enc, FSources[i].DimCount);
    FEncodes[i] := enc;
    TyFillStoreFromSource(FSources[i], enc, dims, st);
    ResolveTextDims(enc, st);
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
  { AFTER the colours, because a partial colour visual starts from the series
    colour, and BEFORE the stacks: the default dimension is the last one that
    is not a calculation, and the stack columns are calculations. }
  SolveVisualMaps;
  TyIndexSeries(FBindings, FIndex);
  { BEFORE THE EXTENTS, and that order is the whole point: a stacked chart
    whose axis was sized from the raw values draws off the top of its plot. }
  FStacks := TySolveStacks(FOption, FBindings, FStores);
  { AFTER THE STACKS AND BEFORE THE EXTENTS -- upstream's dataZoom runs at
    1000, after the stack (900): the sums are the unzoomed ones, and the
    axis not zoomed is sized from the rows the zoom left. }
  SolveDataZooms;
  { EVERY RENDER IS A RENDER OF THE VIEWS: a slider rebuilds from the window
    unless the action was its own, an inside takes the window again }
  DzRenderStates;
  TyApplyAxisExtents(FOption, FBuild, FBindings, FStores, FStacks, FIndex,
    FLastPPI, FAxisZooms);
end;

function TTyAdvanceChart.WeakKeep(ARawIndex: Integer): Boolean;
var
  k: Integer;
  v: Double;
  hasValue, leftOut, rightOut: Boolean;
begin
  { weakFilter: in the window on some dimension, or straddling it; a row
    with no value at all goes }
  hasValue := False;
  leftOut := False;
  rightOut := False;
  for k := 0 to High(FWfCols) do
  begin
    v := FWfStore.GetByRaw(FWfCols[k], ARawIndex);
    if IsNan(v) then Continue;
    { a not-a-number window end compares false both ways, as in JavaScript }
    if (not IsNan(FWfLo)) and (not IsNan(FWfHi)) and (v >= FWfLo) and (v <= FWfHi) then
      Exit(True);
    hasValue := True;
    if (not IsNan(FWfLo)) and (v < FWfLo) then leftOut := True;
    if (not IsNan(FWfHi)) and (v > FWfHi) then rightOut := True;
  end;
  Result := hasValue and leftOut and rightOut;
end;

procedure TTyAdvanceChart.SolveDataZooms;
var
  n, i, t, k, c, si, first: Integer;
  spec: TTyDataZoomSpec;
  ax: TTyAxis;
  z: TTyAxisZoom;
  win: TTyDzWindow;
  any, hosted: Boolean;
  px: Double;
  feeders, cols: TTyIntegerArray;
  ranges: array of TTyDimRange;
  sel: TTyDataZoomSpecArray;
  pass: Integer;
  alignTo: TTyAxis;
  alignWin: Integer;
  use: TTyDataZoomSpec;
begin
  FZoomSpecs := nil;
  FAxisZooms := nil;
  FZoomWindows := nil;
  FZoomHost := nil;
  if FBuild = nil then Exit;
  n := TyDataZoomCount(FOption);
  SetLength(FZoomSpecs, n);
  { setRawRange's windows survive a rebuild; a count that changed drops
    them }
  if Length(FDzRawHas) <> n then
  begin
    SetLength(FDzRawHas, n);
    SetLength(FDzRawStart, n);
    SetLength(FDzRawStop, n);
    for i := 0 to n - 1 do FDzRawHas[i] := False;
  end;
  for i := 0 to n - 1 do
  begin
    FZoomSpecs[i] := TyDataZoomSpecOf(FOption, i, FBuild);
    { AN ACTION'S WINDOW: both ends as percents, the values cleared, so
      both ends read in percent mode }
    if FDzRawHas[i] then
      for k := 0 to 1 do
      begin
        FZoomSpecs[i].Percent[k] := Default(TTyDzArg);
        FZoomSpecs[i].Percent[k].Given := True;
        if k = 0 then FZoomSpecs[i].Percent[k].Num := FDzRawStart[i]
        else FZoomSpecs[i].Percent[k].Num := FDzRawStop[i];
        FZoomSpecs[i].Value[k] := Default(TTyDzArg);
        FZoomSpecs[i].Value[k].Num := NaN;
        FZoomSpecs[i].Mode[k] := dzmPercent;
      end;
  end;
  { the toolbox's select dataZooms after the author's }
  sel := TyDataZoomSelectSpecs(FOption, FBuild, n);
  if Length(sel) > 0 then
  begin
    SetLength(FZoomSpecs, n + Length(sel));
    for i := 0 to High(sel) do FZoomSpecs[n + i] := sel[i];
    n := Length(FZoomSpecs);
  end;
  if n = 0 then Exit;
  { IN COMPONENT ORDER: each dataZoom resets the axes it hosts -- the FIRST
    dataZoom to target an axis owns it; a later one on the same axis shows
    the owner's window and has its own ignored -- then filters them, and the
    next one measures the rows this one left. }
  for i := 0 to n - 1 do
  begin
    spec := FZoomSpecs[i];
    if (spec.SubType = '') or spec.NoTarget then Continue;
    first := Length(FAxisZooms);
    { TWO PASSES: an axis that aligns its ticks to another this dataZoom
      also drives is reset last, from that one's percentInverted window --
      which wins over its own start / end (zrender's defaults keeps the
      target's keys) }
    for pass := 0 to 1 do
    for t := 0 to High(spec.Targets) do
    begin
      ax := FBuild.Axis(spec.Targets[t].Dim + 'Axis', spec.Targets[t].AxisIndex);
      if ax = nil then Continue;
      alignTo := TyAxisAlignTo(FOption, FBuild, ax);
      if (alignTo <> nil) and not TyDzTargets(spec, alignTo.Dim, alignTo.ComponentIndex) then
        alignTo := nil;
      if (alignTo <> nil) <> (pass = 1) then Continue;
      hosted := False;
      for k := 0 to High(FAxisZooms) do
        if FAxisZooms[k].Axis = ax then hosted := True;
      if hosted then Continue;
      use := spec;
      if alignTo <> nil then
      begin
        alignWin := -1;
        for k := 0 to High(FAxisZooms) do
          if FAxisZooms[k].Axis = alignTo then alignWin := k;
        if alignWin >= 0 then
          for k := 0 to 1 do
          begin
            use.Percent[k].Given := True;
            use.Percent[k].IsStr := False;
            use.Percent[k].Num := FZoomWindows[alignWin].PercentInverted[k];
          end;
      end;
      z := Default(TTyAxisZoom);
      z.Axis := ax;
      z.Raw := TyAxisNoZoomExtent(FOption, FBindings, FStores, FStacks, FIndex,
        ax, spec.Targets[t].Dim + 'Axis', any);
      z.Any := any;
      { the axis' pixel span as the grid's own box lays it out, CSS px }
      px := ax.PxLength;
      if FLastPPI > 0 then px := px * 96 / FLastPPI;
      win := TyDzCalculateWindow(use, ax, z.Raw.Lo, z.Raw.Hi, px);
      z.ZoomLo := NaN;
      z.ZoomHi := NaN;
      { an end at exactly 0% or 100% is left to nice freely (`!== 0`: a
        not-a-number pins, and pins nothing but a blank) }
      if IsNan(win.Percent[0]) or (win.Percent[0] <> 0) then z.ZoomLo := win.Value[0];
      if IsNan(win.Percent[1]) or (win.Percent[1] <> 100) then z.ZoomHi := win.Value[1];
      k := Length(FAxisZooms);
      SetLength(FAxisZooms, k + 1);
      SetLength(FZoomWindows, k + 1);
      SetLength(FZoomHost, k + 1);
      FAxisZooms[k] := z;
      FZoomWindows[k] := win;
      FZoomHost[k] := i;
    end;
    { then filter what it hosts, with the window's values }
    for k := first to High(FAxisZooms) do
    begin
      if spec.FilterMode = dzfNone then Continue;
      ax := FAxisZooms[k].Axis;
      win := FZoomWindows[k];
      feeders := FIndex.SeriesOnAxis(ax);
      for c := 0 to High(feeders) do
      begin
        si := feeders[c];
        if (si < 0) or (si > High(FStores)) or (FStores[si] = nil) then Continue;
        if FBindings[si].CoordSysName <> 'cartesian2d' then Continue;
        if si <= High(FStacks) then
          cols := TyAxisDataDims(FStores[si], ax, FBindings[si], FStacks[si])
        else
          cols := TyAxisDataDims(FStores[si], ax, FBindings[si], Default(TTySeriesStack));
        if Length(cols) = 0 then Continue;
        case spec.FilterMode of
          dzfFilter:
            begin
              { dimension by dimension: a row stays when every one is in the
                window or not a number }
              SetLength(ranges, Length(cols));
              for t := 0 to High(cols) do
              begin
                ranges[t].Dim := cols[t];
                ranges[t].Min := win.Value[0];
                ranges[t].Max := win.Value[1];
              end;
              FStores[si].SelectRange(ranges);
            end;
          dzfWeakFilter:
            begin
              FWfStore := FStores[si];
              FWfCols := cols;
              FWfLo := win.Value[0];
              FWfHi := win.Value[1];
              try
                FStores[si].FilterSelf(@WeakKeep);
              finally
                FWfStore := nil;
              end;
            end;
          dzfEmpty:
            { the other axis is NOT resized: only this axis' values go }
            for t := 0 to High(cols) do
              FStores[si].EmptyOutside(cols[t], win.Value[0], win.Value[1]);
        end;
      end;
    end;
  end;
end;

procedure TTyAdvanceChart.Relayout(APainter: TTyPainter; const ARect: TTyRectF;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  txt: TTyAxisTextStyle;
  labelS: TTyStyleSet;
begin
  FLastRect := ARect;
  FLastPPI := APPI;
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
  { the name is measured in the font it is drawn in }
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisName', '', []);
  txt.NameFontName := labelS.FontName;
  txt.NameFontSizeLogical := ResolveFontSize(labelS);
  txt.NameFontWeight := labelS.FontWeight;
  { Measuring goes through the painter behind an interface rather than being
    called directly, so the layout layer stays free of the painter and a test
    can hand it a deterministic measurer instead of this machine's fonts. }
  TyLayoutGrids(FBuild, FOption, AMeasurer, APPI, txt);
  { AFTER phase C, for the reason on FBarCols. }
  FBarCols := TySolveBarLayout(FOption, FBuild, FBindings, FStores, FIndex);
  { AFTER THE BARS: a marker on a bar series sits on its own bar }
  SolveMarkers(APPI);
  { BEFORE THE PIES: a pie on a calendar is laid out in a day's cell
    [Batch 72] }
  SolveCalendars(APPI);
  SolvePies;
  SolveFunnels;
  SolveGauges(APPI);
  SolveRadars(APPI);
  SolveGraphs(APPI);
  SolveTrees(APPI);
  SolveSunbursts(APPI);
  SolveTreemaps(AMeasurer, APPI);
  SolveTitles(AMeasurer, APPI);
  SolveLegends(AMeasurer, APPI);
  SolveVisualMapViews(AMeasurer, APPI);
  { AFTER THE GRIDS: a slider sits under (or beside) the grid it drives,
    by the rect the labels left it }
  SolveDataZoomViews(AMeasurer, APPI);
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
  i: Integer;
  tickLen, minorLen, at, along, x1, y1, x2, y2: Double;
  maxW, batched: Integer;
  horiz: Boolean;
  lblH, lblW: Integer;
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
      AW := APainter.MeasureText(TyInkText(AText), AStyle.FontName,
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
  { THE FURNITURE FOLLOWS THE LABELS UNLESS IT WAS TOLD OTHERWISE -- and
    where each tick, split line and split-area edge goes, and whether it is
    drawn, the layout has already decided (spec^.TickMarks and the rest).
    This draws that answer. }
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
  { BETWEEN THE EDGES THE LAYOUT PUT -- on the split area's own interval,
    the labels' unless it says otherwise.
    [Revised in batch 40: between every band edge, whatever the labels
    were doing.] }
  if ABelow and furn.ShowSplitArea and (tpBackground in areaS.Present)
    and (spec <> nil) then
  begin
    for i := 0 to High(spec^.SplitAreaMarks) - 1 do
    begin
      if i mod 2 <> 0 then Continue;
      if not spec^.SplitAreaMarks[i].Drawn then Continue;
      bandLo := spec^.SplitAreaMarks[i].Coord;
      bandHi := spec^.SplitAreaMarks[i + 1].Coord;
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

  { WHATEVER THE LABELS ARE DOING: upstream subdivides every interval.
    [Revised in batch 40: only while every major label was drawn.] }
  if ABelow and furn.ShowMinorSplitLine
    and (tpBorderColor in minorSplitS.Present) then
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

  { WHERE THE LAYOUT PUT THEM: the split line's own interval, the labels'
    unless it says otherwise, on the band edges of a banded axis with the
    closing edge; the two on the ends separately deniable -- a grid line on
    the axis' own extreme doubles whatever border is already there.
    [Revised in batch 40: every tickStep-th band edge, the stride of
    axisTick.interval when there was one, and no closing edge unless the
    count suited it.] }
  if ABelow and furn.ShowSplitLine and (tpBorderColor in splitS.Present)
    and (spec <> nil) then
  begin
    APainter.BeginPath;
    for i := 0 to High(spec^.SplitLineMarks) do
    begin
      if not spec^.SplitLineMarks[i].Drawn then Continue;
      along := spec^.SplitLineMarks[i].Coord;
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
  { THE MARKS WHERE THE LAYOUT PUT THEM, on their own interval or the
    labels', a tick whose label was hidden gone with it.
    [Revised in batch 40: every tickStep-th tick, a hidden label's kept.] }
  if furn.ShowTicks and (tpBorderColor in tickStyle.Present) and (spec <> nil) then
  begin
    APainter.BeginPath;
    for i := 0 to High(spec^.TickMarks) do
    begin
      if not spec^.TickMarks[i].Drawn then Continue;
      along := spec^.TickMarks[i].Coord;
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
  if furn.ShowMinorTick and (tpBorderColor in minorTickS.Present) then
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

  { THE AXIS NAME, WHERE THE LAYOUT PUT IT. The grid was shrunk for the
    name's box on its estimate pass and the name laid out again on the final
    rect -- at its location and gap, turned and aligned as upstream turns and
    aligns it, and moved clear of the labels -- so this draws that answer
    and works nothing out: a second route here is how the name used to land
    beside the band that was reserved for it. }
  nameS := model.ResolveStyle('TyAdvChartAxisName', '', []);
  if (spec <> nil) and spec^.NamePlacement.Shown
    and (tpTextColor in nameS.Present) then
  begin
    { LEVEL IS LEVEL: a y axis' end name comes out of the matrices a few
      hundred quadrillionths of a radian off, and the flat path is the one
      that sets a name of several lines }
    if Abs(spec^.NamePlacement.RotationRad) < 1e-9 then
    begin
      TextSizeOf(spec^.NamePlacement.Text, nameS, lblW, lblH);
      APainter.DrawText(
        AnchorBox(spec^.NamePlacement.X, spec^.NamePlacement.Y, lblW, lblH,
          spec^.NamePlacement.AnchorH, spec^.NamePlacement.AnchorV),
        spec^.NamePlacement.Text, nameS.FontName, ResolveFontSize(nameS),
        nameS.FontWeight, nameS.TextColor, taCenter, tlCenter, False, 0, False,
        Pos(#10, spec^.NamePlacement.Text) > 0);
    end
    else
      APainter.DrawTextRotated(spec^.NamePlacement.Text, nameS.FontName,
        ResolveFontSize(nameS), nameS.FontWeight, nameS.TextColor,
        spec^.NamePlacement.X, spec^.NamePlacement.Y,
        spec^.NamePlacement.RotationRad,
        AnchorAlign(spec^.NamePlacement.AnchorH),
        AnchorLayout(spec^.NamePlacement.AnchorV));
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
  measurer := NewTextMeasurer(APPI);
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
  FSeriesColorNone := nil;
  FSeriesPalette := nil;
  FSeriesPaletteKnown := nil;
  if FOption = nil then Exit;
  n := FOption.ComponentCount('series');
  SetLength(FSeriesColors, n);
  SetLength(FSeriesColorKnown, n);
  SetLength(FSeriesColorNone, n);
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

    { A TYPE WHOSE DEFAULTS NAME THE COLOUR takes no slot either: the style
      task reads itemStyle through the series' defaultOption, and a
      candlestick's says '#eb5454' -- so a bar beside it takes the palette's
      FIRST colour, not its second. [Batch 65: the bar took the second, and
      its markers with it.] }
    if (st = 'candlestick') and (not key.Written) and (not hasAuto) then
    begin
      FSeriesColors[i] := TTyChartColor($FFEB5454);
      FSeriesColorKnown[i] := True;
      Continue;
    end;
    { A TREE'S DEFAULTS NAME ITS COLOUR TOO (lightsteelblue upstream), so it
      takes no slot and a series after it keeps its own; the colour is the
      theme's. [Batch 73] }
    if (st = TyTreeSeriesTypeName) and (not key.Written) and (not hasAuto) then
    begin
      FSeriesColors[i] := TTyChartColor(ActiveController.Model.ResolveStyle(
        'TyAdvChartTreeNode', '', []).Background.Color);
      FSeriesColorKnown[i] := True;
      Continue;
    end;

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
      end
      else
        { WRITTEN AS `none`: no fill at all -- which also makes an inside
          label an outside one. [Revised in batch 47: it fell through to the
          theme's colour.] }
        FSeriesColorNone[i] := True;
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

procedure TTyAdvanceChart.SolveVisualMaps;
var
  i, k, n, raw, col, dimIndex: Integer;
  spec: TTyVisualMapSpec;
  st: TTyDataStore;
  sid: string;
  d: TJSONData;
  baseColor: TTyVisualColor;
  values: TTyDoubleArray;
  texts: TTyStringArray;
  rows: TTyVisualRowArray;
  meta: TTyVisualMeta;
  offKey: Integer;
  ov: TTyDataValue;
  ramp: TTyVisualColorArray;
begin
  FVisualSpecs := nil;
  FVisualRows := nil;
  FVisualMetas := nil;
  FVisualLines := nil;
  n := TyVisualMapCount(FOption);
  if n = 0 then Exit;
  { THE FALLBACK RAMP IS THE SKIN'S. Upstream derives it from its theme's
    first colour; the theme here is the .tycss accent, which is series slot
    one -- so an unconfigured visualMap is drawn in the skin's colour. A root
    `gradientColor` still wins. }
  ramp := TyVisualDefaultRamp(TTyChartColor(ThemeRampColor(0)));
  SetLength(FVisualSpecs, n);
  SetLength(FVisualViews, n);
  SetLength(FVisualLayouts, n);
  for k := 0 to n - 1 do
  begin
    FVisualViews[k] := TyVisualMapViewSpecOf(FOption, k);
    FVisualLayouts[k] := Default(TTyVisualMapLayout);
    { the controller's colour for a state it was given nothing for:
      `inactiveColor` as written, the theme's otherwise }
    if FVisualViews[k].HasInactive then
      FVisualSpecs[k] := TyVisualMapSpecOf(FOption, k, ramp,
        FVisualViews[k].Inactive)
    else
      FVisualSpecs[k] := TyVisualMapSpecOf(FOption, k, ramp,
        TyVisualFromChart(TTyChartColor(ActiveController.Model.ResolveStyle(
          'TyAdvChartVisualMapInactive', '', []).TextColor)));
    { [Batch 58: a piecewise one encodes now; its note went.] }
  end;
  SetLength(FVisualRows, Length(FBindings));
  SetLength(FVisualMetas, Length(FBindings));
  SetLength(FVisualLines, Length(FBindings));
  offKey := TyOverrideKey('visualMap');
  for i := 0 to High(FBindings) do
  begin
    if i > High(FStores) then Break;
    st := FStores[i];
    if st = nil then Continue;
    sid := '';
    d := FOption.ComponentAt('series', FBindings[i].SeriesIndex);
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      d := TJSONObject(d).Find('id');
      if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then sid := d.AsString;
    end;
    baseColor := TyVisualFromChart(TTyChartColor(
      SeriesColor(FBindings[i].SeriesIndex)));
    rows := nil;
    { IN COMPONENT ORDER: a second visualMap on the same series starts from
      what the first one wrote }
    for k := 0 to n - 1 do
    begin
      spec := FVisualSpecs[k];
      if not TyVisualMapTargets(spec, FBindings[i].SeriesIndex, sid) then Continue;
      { with each value's text: what a category or a string piece matches }
      values := TyVisualSeriesValues(st,
        TyVisualMapDimFor(spec, FBindings[i].SeriesIndex, sid), col, dimIndex,
        texts);
      if rows = nil then
      begin
        SetLength(rows, st.RawCount);
        for raw := 0 to High(rows) do
        begin
          rows[raw] := Default(TTyVisualRow);
          rows[raw].Color := baseColor;
          rows[raw].Opacity := NaN;
        end;
      end;
      for raw := 0 to High(rows) do
      begin
        { `visualMap: false` on the item opts it out of every component }
        if st.HasOverrideByRaw(raw, offKey) then
        begin
          ov := st.GetOverrideByRaw(raw, offKey);
          if (ov.Kind = dvkBool) and (ov.Num = 0) then Continue;
        end;
        TyVisualApply(spec, TyVisualValueState(spec, values[raw], texts[raw]),
          values[raw], texts[raw], rows[raw], False);
      end;
      if dimIndex >= 0 then
      begin
        meta := TyVisualMetaOf(spec, baseColor);
        meta.Dimension := dimIndex;
        meta.CoordDim := '';
        if col >= 0 then
        begin
          meta.CoordDim := st.DimCoord(col);
          if meta.CoordDim = '' then meta.CoordDim := st.DimName(col);
          if (meta.CoordDim <> 'x') and (meta.CoordDim <> 'y') then
            meta.CoordDim := '';
        end;
        SetLength(FVisualMetas[i], Length(FVisualMetas[i]) + 1);
        FVisualMetas[i][High(FVisualMetas[i])] := meta;
      end;
    end;
    FVisualRows[i] := rows;
  end;
end;

procedure TTyAdvanceChart.ApplyVisualMaps(var AVisual: TTySeriesVisual;
  ASlot, APPI: Integer);
var
  k: Integer;
  node: TJSONObject;
  d: TJSONData;
  axis: TTyAxis;
  metas: TTyVisualMetaArray;
  origin, len: Double;
begin
  if (ASlot < 0) or (ASlot > High(FVisualRows)) then Exit;
  AVisual.VisualRows := FVisualRows[ASlot];
  if APPI <= 0 then Exit;
  FVisualLines[ASlot] := Default(TTyVisualLineFill);
  { A LINE ONLY, and on a grid: LineView's getVisualGradient, from the LAST
    visualMeta whose dimension is x or y }
  if FBindings[ASlot].SeriesType <> 'line' then Exit;
  if not FBindings[ASlot].HasAxes then Exit;
  if (ASlot > High(FStores)) or (FStores[ASlot] = nil)
    or (FStores[ASlot].Count = 0) then Exit;
  metas := FVisualMetas[ASlot];
  k := High(metas);
  while (k >= 0) and (metas[k].CoordDim = '') do Dec(k);
  if k < 0 then Exit;
  axis := nil;
  if (FBindings[ASlot].BaseAxis <> nil)
    and (FBindings[ASlot].BaseAxis.Dim = metas[k].CoordDim) then
    axis := FBindings[ASlot].BaseAxis
  else if (FBindings[ASlot].ValueAxis <> nil)
    and (FBindings[ASlot].ValueAxis.Dim = metas[k].CoordDim) then
    axis := FBindings[ASlot].ValueAxis;
  if axis = nil then Exit;
  { CLIPPED TO THE CANVAS, not to the plot: api.getWidth() / getHeight() }
  if metas[k].CoordDim = 'x' then
  begin
    origin := FLastRect.Left;
    len := FLastRect.Right - FLastRect.Left;
  end
  else
  begin
    origin := FLastRect.Top;
    len := FLastRect.Bottom - FLastRect.Top;
  end;
  FVisualLines[ASlot] := TyVisualLineFillOf(metas[k], axis, origin, len,
    APPI / 96);
  AVisual.VisualLine := FVisualLines[ASlot];
  { the pen keeps an authored lineStyle.color, the area an authored
    areaStyle.color -- `defaults(style, {stroke: visualColor})` }
  AVisual.VisualLineStroke := True;
  AVisual.VisualLineArea := True;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    node := TJSONObject(d);
    AVisual.VisualLineStroke := not TyReadOptStyle(node, 'lineStyle').Color.Written;
    AVisual.VisualLineArea := not TyReadOptStyle(node, 'areaStyle').Color.Written;
  end;
end;

function TTyAdvanceChart.VisualMapContent(const AView: TTyVmViewSpec): TTyVisualColor;
begin
  { `contentColor` as written; upstream's default is its first theme colour,
    which here is the skin's accent -- series slot one }
  if AView.HasContent then Exit(AView.Content);
  Result := TyVisualFromChart(TTyChartColor(ThemeRampColor(0)));
end;

function TTyAdvanceChart.VisualMapInk(const AView: TTyVmViewSpec): TTyVisualMapInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartVisualMap', '', []);
  Result.FontName := st.FontName;
  Result.FontSizeLogical := ResolveFontSize(st);
  if AView.FontSize > 0 then Result.FontSizeLogical := AView.FontSize;
  Result.FontWeight := st.FontWeight;
  if AView.HasText_ then Result.Text := AView.TextColour
  else Result.Text := TTyChartColor(st.TextColor);
  if AView.HasBorder then Result.Border := AView.BorderColour
  else Result.Border := TTyChartColor(
    model.ResolveStyle('TyAdvChartVisualMapBorder', '', []).BorderColor);
  if AView.HasBackground then Result.Background := AView.BackgroundColour
  else Result.Background := TTyChartColor(
    model.ResolveStyle('TyAdvChartVisualMapBackground', '', []).Background.Color);
  if AView.HasHandleStroke then Result.HandleStroke := AView.HandleStroke
  else Result.HandleStroke := TTyChartColor(
    model.ResolveStyle('TyAdvChartVisualMapHandle', '', []).BorderColor);
end;

procedure TTyAdvanceChart.SolveVisualMapViews(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var k: Integer;
begin
  for k := 0 to High(FVisualLayouts) do
  begin
    FVisualLayouts[k] := Default(TTyVisualMapLayout);
    if (k > High(FVisualSpecs)) or (k > High(FVisualViews)) then Break;
    FVisualLayouts[k] := TyLayoutVisualMap(FVisualSpecs[k], FVisualViews[k],
      VisualMapContent(FVisualViews[k]), FLastRect.Right - FLastRect.Left,
      FLastRect.Bottom - FLastRect.Top, APPI / 96, AMeasurer,
      VisualMapInk(FVisualViews[k]));
  end;
end;

function TTyAdvanceChart.BuildVisualMaps(AList: TTyPaintList): Integer;
var k: Integer;
begin
  Result := 0;
  for k := 0 to High(FVisualLayouts) do
    if (k <= High(FVisualViews)) and FVisualLayouts[k].Valid then
      Inc(Result, TyBuildVisualMapMarks(FVisualLayouts[k], FVisualViews[k],
        VisualMapInk(FVisualViews[k]), FLastRect.Left, FLastRect.Top, AList));
end;

function TTyAdvanceChart.VisualMapLayout(AIndex: Integer): TTyVisualMapLayout;
begin
  Result := Default(TTyVisualMapLayout);
  if (AIndex >= 0) and (AIndex <= High(FVisualLayouts)) then
    Result := FVisualLayouts[AIndex];
end;

function TTyAdvanceChart.DataZoomInk(const ASpec: TTyDzSliderSpec): TTyDzInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartDataZoom', '', []);
  Result.FontName := st.FontName;
  Result.FontSizeLogical := ResolveFontSize(st);
  if ASpec.FontSize > 0 then Result.FontSizeLogical := ASpec.FontSize;
  Result.FontWeight := st.FontWeight;
  Result.Text := TTyChartColor(st.TextColor);
  Result.Filler := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomFiller', '', []).Background.Color);
  Result.Frame := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomBorder', '', []).BorderColor);
  Result.Background := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomBackground', '', []).Background.Color);
  st := model.ResolveStyle('TyAdvChartDataZoomHandle', '', []);
  Result.HandleFill := TTyChartColor(st.Background.Color);
  Result.HandleStroke := TTyChartColor(st.BorderColor);
  st := model.ResolveStyle('TyAdvChartDataZoomMoveHandle', '', []);
  Result.MoveHandle := TTyChartColor(st.Background.Color);
  Result.MoveIcon := TTyChartColor(st.TextColor);
  st := model.ResolveStyle('TyAdvChartDataZoomShadow', '', []);
  Result.ShadowArea[0] := TTyChartColor(st.Background.Color);
  Result.ShadowLine[0] := TTyChartColor(st.BorderColor);
  st := model.ResolveStyle('TyAdvChartDataZoomShadowSelected', '', []);
  Result.ShadowArea[1] := TTyChartColor(st.Background.Color);
  Result.ShadowLine[1] := TTyChartColor(st.BorderColor);
  st := model.ResolveStyle('TyAdvChartDataZoomHandle', '', [tysHover]);
  Result.HandleHoverFill := TTyChartColor(st.Background.Color);
  Result.HandleHoverStroke := TTyChartColor(st.BorderColor);
  Result.MoveHandleHover := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomMoveHandle', '', [tysHover]).Background.Color);
  Result.Brush := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomBrush', '', []).Background.Color);
end;

function TTyAdvanceChart.DataZoomInput(AIndex: Integer;
  out AIn: TTyDzSliderInput): Boolean;
var
  spec, hostSpec: TTyDataZoomSpec;
  view: TTyDzSliderSpec;
  scale, v, px: Double;
  t, k, rep, c, slot, thisCol, otherCol, r, g: Integer;
  st: TTyDzSliderState;
  nrWin: TTyDzWindow;
  ax, first, other: TTyAxis;
  feeders, cols: TTyIntegerArray;
  b: TTySeriesBinding;
  store: TTyDataStore;
  otherDim: string;
  grid: TTyGridBuild;
  found: Boolean;
begin
  Result := False;
  AIn := Default(TTyDzSliderInput);
  if (FBuild = nil) or (AIndex > High(FZoomSpecs)) or (AIndex > High(FDzViews)) then Exit;
  spec := FZoomSpecs[AIndex];
  view := FDzViews[AIndex];
  if (spec.SubType <> 'slider') or spec.NoTarget then Exit;
  if FLastPPI > 0 then scale := FLastPPI / 96 else scale := 1;
  AIn.CanvasW := (FLastRect.Right - FLastRect.Left) / scale;
  AIn.CanvasH := (FLastRect.Bottom - FLastRect.Top) / scale;
  AIn.Horizontal := spec.Orient <> 'vertical';
  first := nil;
  for t := 0 to High(spec.Targets) do
  begin
    ax := FBuild.Axis(spec.Targets[t].Dim + 'Axis', spec.Targets[t].AxisIndex);
    if ax = nil then Continue;
    first := ax;
    Break;
  end;
  rep := DzRepresentative(AIndex);
  if (first = nil) or (rep < 0) then Exit;
  AIn.Inverse := first.Inverse;
  { the first target's grid, as the labels left it }
  for g := 0 to FBuild.GridCount - 1 do
  begin
    grid := FBuild.Grid(g);
    if grid.ComponentIndex = first.GridIndex then
    begin
      AIn.HasCoordRect := True;
      AIn.CoordRect.X := (grid.PlotXYWH.X - FBuild.Viewport.Left) / scale;
      AIn.CoordRect.Y := (grid.PlotXYWH.Y - FBuild.Viewport.Top) / scale;
      AIn.CoordRect.W := grid.PlotXYWH.W / scale;
      AIn.CoordRect.H := grid.PlotXYWH.H / scale;
      Break;
    end;
  end;
  for k := 0 to 1 do
  begin
    AIn.Percent[k] := FZoomWindows[rep].Percent[k];
    AIn.Value[k] := FZoomWindows[rep].Value[k];
  end;
  AIn.ValuePrecision := FZoomWindows[rep].Precision;
  ax := FAxisZooms[rep].Axis;
  { THE VIEW'S OWN STATE }
  if AIndex <= High(FDzState) then
  begin
    st := FDzState[AIndex];
    if st.Built then
    begin
      AIn.HasEnds := True;
      for k := 0 to 1 do
      begin
        AIn.Ends[k] := st.Ends[k];
        AIn.ViewRange[k] := st.Range[k];
      end;
    end;
    AIn.HasLabelState := True;
    AIn.LabelsShown := st.LabelsShown;
    AIn.HandleHover[0] := st.HandleHover[0];
    AIn.HandleHover[1] := st.HandleHover[1];
    AIn.MoveHover := st.MoveBits <> 0;
    AIn.HasBrush := st.HasBrush and not st.BrushIgnored;
    AIn.BrushX := st.BrushX;
    AIn.BrushW := st.BrushW;
    { _updateView(nonRealtime): the labels say the window the view's range
      WOULD give, worked out with the host's range modes }
    if st.NonRealtime and st.Built and (FZoomHost[rep] >= 0)
      and (FZoomHost[rep] <= High(FZoomSpecs)) then
    begin
      { calculateDataWindow({start, end}): no startValue / endValue, so an
        end the host reads in value mode falls back to the data's end }
      hostSpec := FZoomSpecs[FZoomHost[rep]];
      for k := 0 to 1 do
      begin
        hostSpec.Percent[k] := Default(TTyDzArg);
        hostSpec.Percent[k].Given := True;
        hostSpec.Percent[k].Num := st.Range[k];
        hostSpec.Value[k] := Default(TTyDzArg);
        hostSpec.Value[k].Num := NaN;
      end;
      px := ax.PxLength;
      if FLastPPI > 0 then px := px * 96 / FLastPPI;
      nrWin := TyDzCalculateWindow(hostSpec, ax, FAxisZooms[rep].Raw.Lo,
        FAxisZooms[rep].Raw.Hi, px);
      AIn.Value[0] := nrWin.Value[0];
      AIn.Value[1] := nrWin.Value[1];
      AIn.ValuePrecision := nrWin.Precision;
    end;
  end;
  { a category or time axis says its ends in the scale's own words }
  if ax.AxisType = atCategory then
  begin
    AIn.LabelIsScale := True;
    for k := 0 to 1 do
    begin
      v := AIn.Value[k];
      if IsNan(v) then Continue;
      v := TyJsRound(v);
      if (v >= 0) and (v < ax.Categories.Count) then
        AIn.ScaleLabel[k] := ax.Categories.CategoryAt(Trunc(v));
    end;
  end
  else if (ax.AxisType = atTime) and (ax.Scale is TTyTimeScale) then
  begin
    AIn.LabelIsScale := True;
    for k := 0 to 1 do
      if not IsNan(AIn.Value[k]) then
        AIn.ScaleLabel[k] := TTyTimeScale(ax.Scale).GetLabel(TyJsRound(AIn.Value[k]));
  end;
  { THE DATA SHADOW: the first series on a target axis that can cast one --
    a line, bar, candlestick or scatter, or any when showDataShadow is true
    -- read RAW, before any dataZoom filtered or emptied it }
  if view.ShowShadow = 0 then Exit(True);
  found := False;
  for t := 0 to High(spec.Targets) do
  begin
    if found then Break;
    ax := FBuild.Axis(spec.Targets[t].Dim + 'Axis', spec.Targets[t].AxisIndex);
    if ax = nil then Continue;
    feeders := FIndex.SeriesOnAxis(ax);
    for c := 0 to High(feeders) do
    begin
      slot := feeders[c];
      if (slot < 0) or (slot > High(FBindings)) or (slot > High(FStores)) then Continue;
      b := FBindings[slot];
      if (view.ShowShadow <> 1) and (b.SeriesType <> 'line') and (b.SeriesType <> 'bar')
        and (b.SeriesType <> 'candlestick') and (b.SeriesType <> 'scatter') then Continue;
      found := True;
      if ax.Dim = 'x' then otherDim := 'y'
      else if ax.Dim = 'y' then otherDim := 'x'
      else otherDim := '';
      other := nil;
      if otherDim <> '' then
        if ax = b.XAxis then other := b.YAxis else other := b.XAxis;
      AIn.OtherAxisInverse := (other <> nil) and other.Inverse;
      store := FStores[slot];
      if store = nil then Break;
      cols := store.DimsOfCoord(ax.Dim);
      if Length(cols) > 0 then thisCol := cols[0] else thisCol := -1;
      otherCol := -1;
      { a candlestick's shadow is its open }
      if b.SeriesType = 'candlestick' then otherCol := store.DimIndexOf('open');
      if (otherCol < 0) and (otherDim <> '') then
      begin
        cols := store.DimsOfCoord(otherDim);
        if Length(cols) > 0 then otherCol := cols[0];
      end;
      if otherCol < 0 then Break;
      AIn.HasShadow := True;
      AIn.IsTime := ax.AxisType = atTime;
      SetLength(AIn.ThisVals, store.RawCount);
      SetLength(AIn.OtherVals, store.RawCount);
      for r := 0 to store.RawCount - 1 do
      begin
        if thisCol >= 0 then AIn.ThisVals[r] := store.GetOriginalByRaw(thisCol, r)
        else AIn.ThisVals[r] := r;
        AIn.OtherVals[r] := store.GetOriginalByRaw(otherCol, r);
      end;
      Break;
    end;
  end;
  Result := True;
end;

procedure TTyAdvanceChart.SolveDataZoomViews(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  n, k: Integer;
  inp: TTyDzSliderInput;
begin
  n := TyDataZoomCount(FOption);
  SetLength(FDzViews, n);
  SetLength(FDzLayouts, n);
  for k := 0 to n - 1 do
  begin
    FDzLayouts[k] := Default(TTyDzSliderLayout);
    FDzViews[k] := TyDzSliderSpecOf(FOption, k);
  end;
  for k := 0 to n - 1 do
    if DataZoomInput(k, inp) then
    begin
      FDzLayouts[k] := TyLayoutDzSlider(FDzViews[k], inp, AMeasurer,
        DataZoomInk(FDzViews[k]));
      { _resetInterval, once: the view keeps these until it is rebuilt }
      if (k <= High(FDzState)) and FDzLayouts[k].Valid and not FDzState[k].Built then
      begin
        FDzState[k].Built := True;
        FDzState[k].Ends[0] := FDzLayouts[k].HandleEnds[0];
        FDzState[k].Ends[1] := FDzLayouts[k].HandleEnds[1];
        FDzState[k].Range[0] := FDzLayouts[k].Range[0];
        FDzState[k].Range[1] := FDzLayouts[k].Range[1];
      end;
    end;
end;

function TTyAdvanceChart.BuildDataZooms(AList: TTyPaintList): Integer;
var
  k: Integer;
  scale: Double;
begin
  Result := 0;
  if FLastPPI > 0 then scale := FLastPPI / 96 else scale := 1;
  for k := 0 to High(FDzLayouts) do
    if (k <= High(FDzViews)) and FDzLayouts[k].Valid then
      Inc(Result, TyBuildDzSliderMarks(FDzLayouts[k], FDzViews[k],
        DataZoomInk(FDzViews[k]), FLastRect.Left, FLastRect.Top, scale, AList));
end;

{ ==================== dataZoom interaction ==================== }

{ findRepresentativeAxisProxy: the first target this dataZoom hosts, else
  the first target at all -- as an index into the hosted axes }
function TTyAdvanceChart.DzRepresentative(AIndex: Integer): Integer;
var
  spec: TTyDataZoomSpec;
  t, k, firstRec: Integer;
  ax: TTyAxis;
begin
  Result := -1;
  if (FBuild = nil) or (AIndex < 0) or (AIndex > High(FZoomSpecs)) then Exit;
  spec := FZoomSpecs[AIndex];
  firstRec := -1;
  for t := 0 to High(spec.Targets) do
  begin
    ax := FBuild.Axis(spec.Targets[t].Dim + 'Axis', spec.Targets[t].AxisIndex);
    if ax = nil then Continue;
    for k := 0 to High(FAxisZooms) do
      if FAxisZooms[k].Axis = ax then
      begin
        if (Result < 0) and (FZoomHost[k] = AIndex) then Result := k;
        if firstRec < 0 then firstRec := k;
      end;
  end;
  if Result < 0 then Result := firstRec;
end;

{ Every view rendered: a slider not the source of this action is rebuilt --
  its ends from the window again, the brush gone, the labels back to
  handleLabel.show, no emphasis; the drag and the pointer's place survive --
  and every inside takes its range from the window. }
procedure TTyAdvanceChart.DzRenderStates;
var
  n, i, rep: Integer;
  keepDrag, keepOver: Boolean;
  keepThrottle: TTyDzThrottle;
  keepPending: Boolean;
begin
  n := TyDataZoomCount(FOption);
  if Length(FDzState) <> n then SetLength(FDzState, n);
  SetLength(FDzInteract, n);
  SetLength(FDzInLo, n);
  SetLength(FDzInHi, n);
  for i := 0 to n - 1 do
  begin
    FDzInteract[i] := TyDzInteractSpecOf(FOption, i);
    if i <> FDzFrom then
    begin
      keepDrag := FDzState[i].Dragging;
      keepOver := FDzState[i].OverArea;
      keepThrottle := FDzState[i].Throttle;
      keepPending := FDzState[i].PendingRealtime;
      FDzState[i] := Default(TTyDzSliderState);
      FDzState[i].Dragging := keepDrag;
      FDzState[i].OverArea := keepOver;
      FDzState[i].Throttle := keepThrottle;
      FDzState[i].PendingRealtime := keepPending;
      FDzState[i].LabelsShown := TyDzSliderSpecOf(FOption, i).LabelShow;
    end;
    FDzInLo[i] := NaN;
    FDzInHi[i] := NaN;
    rep := DzRepresentative(i);
    if rep >= 0 then
    begin
      FDzInLo[i] := FZoomWindows[rep].Percent[0];
      FDzInHi[i] := FZoomWindows[rep].Percent[1];
    end;
  end;
  if (FBuild <> nil) and (Length(FDzRoamThrottle) <> FBuild.GridCount) then
  begin
    SetLength(FDzRoamThrottle, FBuild.GridCount);
    SetLength(FDzRoamBatch, FBuild.GridCount);
  end;
end;

function TTyAdvanceChart.DzScale: Double;
begin
  if FLastPPI > 0 then Result := FLastPPI / 96 else Result := 1;
end;

function TTyAdvanceChart.DzClock: Double;
begin
  if IsNan(FDzNow) then Result := GetTickCount64 else Result := FDzNow;
end;

function TTyAdvanceChart.DzGridRect(AGrid: Integer): TTyXYWH;
var g: TTyGridBuild; s: Double;
begin
  g := FBuild.Grid(AGrid);
  s := DzScale;
  Result.X := (g.PlotXYWH.X - FBuild.Viewport.Left) / s;
  Result.Y := (g.PlotXYWH.Y - FBuild.Viewport.Top) / s;
  Result.W := g.PlotXYWH.W / s;
  Result.H := g.PlotXYWH.H / s;
end;

{ Cartesian2D.containPoint: each axis' closed extent, the y one measured
  from the bottom }
function TTyAdvanceChart.DzGridContains(AGrid: Integer; AX, AY: Double): Boolean;
var r: TTyXYWH; lx, ly: Double;
begin
  r := DzGridRect(AGrid);
  lx := AX - r.X;
  ly := r.H - AY + r.Y;
  Result := (lx >= 0) and (lx <= r.W) and (ly >= 0) and (ly <= r.H);
end;

{ the inside dataZooms with an axis on this grid, in component order }
function TTyAdvanceChart.DzGridInsides(AGrid: Integer): TTyIntegerArray;
var
  i, t: Integer;
  ax: TTyAxis;
  gi: Integer;
begin
  Result := nil;
  if (FBuild = nil) or (AGrid < 0) or (AGrid >= FBuild.GridCount) then Exit;
  gi := FBuild.Grid(AGrid).ComponentIndex;
  for i := 0 to Min(High(FZoomSpecs), High(FDzInteract)) do
  begin
    if (FZoomSpecs[i].SubType <> 'inside') or FZoomSpecs[i].NoTarget then Continue;
    for t := 0 to High(FZoomSpecs[i].Targets) do
    begin
      ax := FBuild.Axis(FZoomSpecs[i].Targets[t].Dim + 'Axis',
        FZoomSpecs[i].Targets[t].AxisIndex);
      if (ax <> nil) and (ax.GridIndex = gi) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := i;
        Break;
      end;
    end;
  end;
end;

{ mergeControllerParams: the strongest of the insides -- 2 zooms and moves,
  1 moves only (zoomLock), 0 disabled -- or -1 for no controller }
function TTyAdvanceChart.DzControlType(AGrid: Integer): Integer;
var ins: TTyIntegerArray; k, v: Integer;
begin
  Result := -1;
  ins := DzGridInsides(AGrid);
  for k := 0 to High(ins) do
  begin
    if FDzInteract[ins[k]].Disabled then v := 0
    else if FDzInteract[ins[k]].ZoomLock then v := 1
    else v := 2;
    if v > Result then Result := v;
  end;
end;

{ a point on the canvas (CSS px) into the slider group's own coordinates:
  transformCoordToLocal, the inverse of its global matrix }
procedure TTyAdvanceChart.DzToSlider(ASlider: Integer; AX, AY: Double;
  out LX, LY: Double);
var
  L: TTyDzSliderLayout;
  G, inv: TTyMat2D;
begin
  L := FDzLayouts[ASlider];
  G := TyMatMul(TyZrLocal(1, 1, 0, L.GroupX, L.GroupY), TyMatMul(L.SG, TyMatIdentity));
  if not TyMatInvert(G, inv) then
  begin
    LX := NaN;
    LY := NaN;
    Exit;
  end;
  LX := inv[0] * AX + inv[2] * AY + inv[4];
  LY := inv[1] * AX + inv[3] * AY + inv[5];
end;

function TTyAdvanceChart.DzHits(ASlider: Integer; ARole: TTyDzRole; AX, AY: Double): Boolean;
var
  L: TTyDzSliderLayout;
  e: TTyDzElement;
  M, inv: TTyMat2D;
  lx, ly, lw: Double;
  r: TTyXYWH;
begin
  Result := False;
  L := FDzLayouts[ASlider];
  e := L.Kids[ARole];
  if not e.Present then Exit;
  M := TyDzGlobal(L, ARole);
  if not TyMatInvert(M, inv) then Exit;
  lx := inv[0] * AX + inv[2] * AY + inv[4];
  ly := inv[1] * AX + inv[3] * AY + inv[5];
  if ARole in [dzrHandle0, dzrHandle1] then
  begin
    { rectHover: the bounding rect, the stroke grown by strokeNoScale's line
      scale -- the handle's own now it has a global transform }
    if IsNan(FDzViews[ASlider].Handle.LineWidth) then lw := 1
    else lw := FDzViews[ASlider].Handle.LineWidth;
    r := TyZrStrokeRect(e.PathRect, e.DataLen, True, True, lw,
      Sqrt(Abs(M[0] * M[3] - M[2] * M[1])));
  end
  else
    r := e.Shape;
  Result := (lx >= r.X) and (lx <= r.X + r.W) and (ly >= r.Y) and (ly <= r.Y + r.H);
end;

{ findHover over the sliders' non-silent elements, topmost first: the
  handles (a hovered one raised above the other), the move zone, the filler
  when it is the move zone, the click panel; then any other element of the
  chart }
function TTyAdvanceChart.DzFindTarget(AX, AY: Double): TTyDzTarget;
var
  res: TTyDzTarget;
  i, el: Integer;
  st: TTyDzSliderState;
  order: array[0..1] of TTyDzRole;
  k: Integer;
  d: TTyChartDatumRef;
  s: Double;

  function Hit(ARole: TTyDzRole): Boolean;
  begin
    Result := DzHits(i, ARole, AX, AY);
    if Result then
    begin
      res.Kind := dtkSlider;
      res.Slider := i;
      res.Role := ARole;
    end;
  end;

begin
  Result := Default(TTyDzTarget);
  res := Default(TTyDzTarget);
  s := DzScale;
  if (AX < 0) or (AY < 0) or (AX > (FLastRect.Right - FLastRect.Left) / s)
    or (AY > (FLastRect.Bottom - FLastRect.Top) / s) then Exit;
  for i := High(FDzLayouts) downto 0 do
  begin
    if not FDzLayouts[i].Valid then Continue;
    if i <= High(FDzState) then st := FDzState[i] else st := Default(TTyDzSliderState);
    if st.HandleHover[0] and not st.HandleHover[1] then
    begin
      order[0] := dzrHandle0;
      order[1] := dzrHandle1;
    end
    else
    begin
      order[0] := dzrHandle1;
      order[1] := dzrHandle0;
    end;
    for k := 0 to 1 do
      if Hit(order[k]) then Exit(res);
  end;
  for i := High(FDzLayouts) downto 0 do
  begin
    if not FDzLayouts[i].Valid then Continue;
    if FDzViews[i].BrushSelect then
    begin
      if Hit(dzrMoveZone) then Exit(res);
    end
    else if Hit(dzrFiller) then Exit(res);
    if Hit(dzrClickPanel) then Exit(res);
  end;
  d := HitTestAt(Round(AX * s + FLastRect.Left), Round(AY * s + FLastRect.Top), el);
  { a line's own path is silent upstream (triggerLineEvent false): only its
    symbols are targets }
  if TyChartDatumValid(d) and not ((FPaintList <> nil) and (el >= 0)
    and (el < FPaintList.Count) and (FPaintList.Element(el).Shape.Kind = cskPolyline)) then
    Result.Kind := dtkOther;
end;

function SameDzTarget(const A, B: TTyDzTarget): Boolean;
begin
  Result := (A.Kind = B.Kind) and ((A.Kind <> dtkSlider)
    or ((A.Slider = B.Slider) and (A.Role = B.Role)));
end;

{ the axis proxy's spans: the HOST dataZoom's options, in percent }
function TTyAdvanceChart.DzSpans(AIndex: Integer; out AMin, AMax: Double): Boolean;
var
  rep, host: Integer;
  sp: TTyDzSpans;
begin
  AMin := NaN;
  AMax := NaN;
  rep := DzRepresentative(AIndex);
  Result := rep >= 0;
  if not Result then Exit;
  host := FZoomHost[rep];
  if (host < 0) or (host > High(FZoomSpecs)) then Exit;
  sp := TyDzSpansOf(FZoomSpecs[host], FAxisZooms[rep].Axis, FAxisZooms[rep].Raw.Lo,
    FAxisZooms[rep].Raw.Hi);
  AMin := sp.MinSpan;
  AMax := sp.MaxSpan;
end;

{ _showDataInfo: on a hover or while dragging the emphasis label setting,
  else the normal one; the move bar is highlighted with them }
procedure TTyAdvanceChart.DzShowDataInfo(AIndex: Integer; AEmphasis: Boolean);
var toShow: Boolean;
begin
  if AEmphasis or FDzState[AIndex].Dragging then
    toShow := FDzInteract[AIndex].EmphasisLabelShow
  else
    toShow := FDzViews[AIndex].LabelShow;
  FDzState[AIndex].LabelsShown := toShow;
  if FDzViews[AIndex].BrushSelect then
    if toShow then FDzState[AIndex].MoveBits := FDzState[AIndex].MoveBits or 2
    else FDzState[AIndex].MoveBits := FDzState[AIndex].MoveBits and not 2;
end;

procedure TTyAdvanceChart.DzMouseOut(const ATarget: TTyDzTarget);
var i: Integer;
begin
  if ATarget.Kind <> dtkSlider then Exit;
  i := ATarget.Slider;
  if i > High(FDzState) then Exit;
  case ATarget.Role of
    dzrHandle0, dzrHandle1:
      begin
        FDzState[i].OverArea := False;
        DzShowDataInfo(i, False);
        FDzState[i].HandleHover[Ord(ATarget.Role) - Ord(dzrHandle0)] := False;
      end;
    dzrMoveZone, dzrFiller:
      begin
        FDzState[i].OverArea := False;
        DzShowDataInfo(i, False);
        if ATarget.Role = dzrMoveZone then
          FDzState[i].MoveBits := FDzState[i].MoveBits and not 1;
      end;
  end;
end;

procedure TTyAdvanceChart.DzMouseOver(const ATarget: TTyDzTarget);
var i: Integer;
begin
  if ATarget.Kind <> dtkSlider then Exit;
  i := ATarget.Slider;
  if i > High(FDzState) then Exit;
  case ATarget.Role of
    dzrHandle0, dzrHandle1:
      begin
        FDzState[i].OverArea := True;
        DzShowDataInfo(i, True);
        FDzState[i].HandleHover[Ord(ATarget.Role) - Ord(dzrHandle0)] := True;
      end;
    dzrMoveZone, dzrFiller:
      begin
        FDzState[i].OverArea := True;
        DzShowDataInfo(i, True);
        if ATarget.Role = dzrMoveZone then
          FDzState[i].MoveBits := FDzState[i].MoveBits or 1;
      end;
  end;
end;

{ _onDragMove: the screen delta through the INVERSE of the slider group's
  local matrix, then _updateInterval; realtime dispatches }
procedure TTyAdvanceChart.DzDragMove(AIndex, AHandle: Integer; ADX, ADY: Double);
var
  inv: TTyMat2D;
  v, mn, mx: Double;
  moved: Boolean;
begin
  FDzState[AIndex].Dragging := True;
  if not TyMatInvert(FDzLayouts[AIndex].SG, inv) then Exit;
  v := inv[0] * ADX + inv[2] * ADY + inv[4];
  DzSpans(AIndex, mn, mx);
  if FDzInteract[AIndex].ZoomLock then AHandle := -1;
  moved := TyDzUpdateInterval(FDzState[AIndex].Ends, FDzLayouts[AIndex].L, v,
    AHandle, mn, mx, FDzState[AIndex].Range, True);
  FDzState[AIndex].NonRealtime := not FDzInteract[AIndex].Realtime;
  if moved and FDzInteract[AIndex].Realtime then DzSliderDispatch(AIndex, True);
end;

{ _onDragEnd }
procedure TTyAdvanceChart.DzDragEnd(AIndex: Integer);
begin
  FDzState[AIndex].Dragging := False;
  if not FDzState[AIndex].OverArea then DzShowDataInfo(AIndex, False);
  if not FDzInteract[AIndex].Realtime then DzSliderDispatch(AIndex, False);
end;

{ _onClickPanel: the window's centre to the click, keeping the span }
procedure TTyAdvanceChart.DzClickPanel(AIndex: Integer; AX, AY: Double);
var
  lx, ly, centre, mn, mx: Double;
  moved: Boolean;
begin
  DzToSlider(AIndex, AX, AY, lx, ly);
  if (lx < 0) or (lx > FDzLayouts[AIndex].L) or (ly < 0) or (ly > FDzLayouts[AIndex].T) then Exit;
  centre := (FDzState[AIndex].Ends[0] + FDzState[AIndex].Ends[1]) / 2;
  DzSpans(AIndex, mn, mx);
  moved := TyDzUpdateInterval(FDzState[AIndex].Ends, FDzLayouts[AIndex].L,
    lx - centre, -1, mn, mx, FDzState[AIndex].Range, True);
  FDzState[AIndex].NonRealtime := False;
  if moved then DzSliderDispatch(AIndex, False);
end;

{ _updateBrushRect }
procedure TTyAdvanceChart.DzBrushMove(AIndex: Integer; AX, AY: Double);
var ex, ey, sx, sy: Double;
begin
  FDzState[AIndex].HasBrush := True;
  FDzState[AIndex].BrushIgnored := False;
  DzToSlider(AIndex, AX, AY, ex, ey);
  DzToSlider(AIndex, FDzState[AIndex].BrushStartX, FDzState[AIndex].BrushStartY, sx, sy);
  { max(min(size, x), 0) on the double: Math.Max of a double and an
    integer literal takes the Single overload }
  if ex > FDzLayouts[AIndex].L then ex := FDzLayouts[AIndex].L;
  if ex < 0 then ex := 0;
  FDzState[AIndex].BrushX := sx;
  FDzState[AIndex].BrushW := ex - sx;
end;

{ _onBrushEnd: a short quick brush is a click; else the brush is the new
  window -- from the LAST brush rect, which a new press never cleared }
procedure TTyAdvanceChart.DzBrushEnd(AIndex: Integer);
var
  mn, mx, mnPx, mxPx, L: Double;
begin
  if not FDzState[AIndex].Brushing then Exit;
  FDzState[AIndex].Brushing := False;
  if not FDzState[AIndex].HasBrush then Exit;
  FDzState[AIndex].BrushIgnored := True;
  if (DzClock - FDzState[AIndex].BrushStartTime < 200)
    and (Abs(FDzState[AIndex].BrushW) < 5) then Exit;
  L := FDzLayouts[AIndex].L;
  FDzState[AIndex].Ends[0] := FDzState[AIndex].BrushX;
  FDzState[AIndex].Ends[1] := FDzState[AIndex].BrushX + FDzState[AIndex].BrushW;
  DzSpans(AIndex, mn, mx);
  mnPx := NaN;
  mxPx := NaN;
  if not IsNan(mn) then mnPx := TyDzLinearMap(mn, 0, 100, 0, L, True);
  if not IsNan(mx) then mxPx := TyDzLinearMap(mx, 0, 100, 0, L, True);
  TyDzSliderMove(0, FDzState[AIndex].Ends, 0, L, 0, mnPx, mxPx);
  TyDzRangeOfEnds(FDzState[AIndex].Ends, L, FDzState[AIndex].Range[0],
    FDzState[AIndex].Range[1]);
  FDzState[AIndex].NonRealtime := False;
  DzSliderDispatch(AIndex, False);
end;

{ _dispatchZoomAction, through the view's throttle }
procedure TTyAdvanceChart.DzSliderDispatch(AIndex: Integer; ARealtime: Boolean);
begin
  if TyDzThrottleCall(FDzState[AIndex].Throttle, DzClock, FDzInteract[AIndex].Throttle) then
    DzRunSliderAction(AIndex, False)
  else
  begin
    FDzState[AIndex].PendingRealtime := ARealtime;
    DzArmTimer;
  end;
end;

procedure TTyAdvanceChart.DzRunSliderAction(AIndex: Integer; ADeferred: Boolean);
var a: TTyDzAction;
begin
  a := Default(TTyDzAction);
  a.Deferred := ADeferred;
  a.FromSlider := AIndex;
  SetLength(a.Items, 1);
  a.Items[0].DataZoomIndex := AIndex;
  { the range as it is when the call runs }
  a.Items[0].Start := FDzState[AIndex].Range[0];
  a.Items[0].Stop := FDzState[AIndex].Range[1];
  DzDispatch(a);
end;

{ One roam event on a grid: every inside of it that the behaviour allows
  works out its range from its own view range; the ones not disabled that
  moved go in the batch. AKind 'zoom', 'pan' or 'scrollMove'. }
function TTyAdvanceChart.DzRoam(AGrid: Integer; const AKind: string;
  AShift: TShiftState; AOldX, AOldY, ANewX, ANewY, AScale, AScroll: Double): Boolean;
var
  ins: TTyIntegerArray;
  k, d, t: Integer;
  setting: string;
  ax, axis: TTyAxis;
  dir: TTyDzDirection;
  r: array[0..1] of Double;
  mn, mx: Double;
  moved: Boolean;
  items: TTyDzActionItemArray;
begin
  Result := False;
  items := nil;
  ins := DzGridInsides(AGrid);
  for k := 0 to High(ins) do
  begin
    d := ins[k];
    if AKind = 'zoom' then setting := FDzInteract[d].ZoomOnMouseWheel
    else if AKind = 'pan' then setting := FDzInteract[d].MoveOnMouseMove
    else setting := FDzInteract[d].MoveOnMouseWheel;
    if not TyDzBehaviour(setting, ssShift in AShift, ssCtrl in AShift,
      ssAlt in AShift, ssMeta in AShift) then Continue;
    { the dataZoom's first target axis on this grid }
    axis := nil;
    for t := 0 to High(FZoomSpecs[d].Targets) do
    begin
      ax := FBuild.Axis(FZoomSpecs[d].Targets[t].Dim + 'Axis',
        FZoomSpecs[d].Targets[t].AxisIndex);
      if (ax <> nil) and (ax.GridIndex = FBuild.Grid(AGrid).ComponentIndex) then
      begin
        axis := ax;
        Break;
      end;
    end;
    if axis = nil then Continue;
    r[0] := FDzInLo[d];
    r[1] := FDzInHi[d];
    if AKind = 'zoom' then
    begin
      dir := TyDzDirectionInfo(axis.Dim = 'x', axis.Inverse, DzGridRect(AGrid),
        0, 0, ANewX, ANewY);
      DzSpans(d, mn, mx);
      moved := TyDzInsideZoom(r, dir, AScale, mn, mx);
    end
    else
    begin
      dir := TyDzDirectionInfo(axis.Dim = 'x', axis.Inverse, DzGridRect(AGrid),
        AOldX, AOldY, ANewX, ANewY);
      if AKind = 'pan' then moved := TyDzInsideMove(r, TyDzPanDelta(r, dir))
      else moved := TyDzInsideMove(r, TyDzScrollMoveDelta(r, dir, AScroll));
    end;
    FDzInLo[d] := r[0];
    FDzInHi[d] := r[1];
    if moved and not FDzInteract[d].Disabled then
    begin
      SetLength(items, Length(items) + 1);
      items[High(items)].DataZoomIndex := d;
      items[High(items)].Start := r[0];
      items[High(items)].Stop := r[1];
    end;
  end;
  if Length(items) > 0 then
  begin
    DzRoamDispatch(AGrid, items);
    Result := True;
  end;
end;

{ the roam's dispatch, through the grid's throttle at the first inside's
  rate; a deferred one sends the latest batch }
procedure TTyAdvanceChart.DzRoamDispatch(AGrid: Integer; const AItems: TTyDzActionItemArray);
var
  ins: TTyIntegerArray;
  rate: Double;
  a: TTyDzAction;
begin
  ins := DzGridInsides(AGrid);
  rate := 100;
  if Length(ins) > 0 then rate := FDzInteract[ins[0]].Throttle;
  FDzRoamBatch[AGrid] := AItems;
  if TyDzThrottleCall(FDzRoamThrottle[AGrid], DzClock, rate) then
  begin
    a := Default(TTyDzAction);
    a.Batch := True;
    a.FromSlider := -1;
    a.Items := AItems;
    DzDispatch(a);
  end
  else
    DzArmTimer;
end;

{ THE ACTION: setRawRange on the named dataZooms and every one linked to
  them through a shared axis, then one update, the views rendered with the
  payload -- the source slider keeps its view }
procedure TTyAdvanceChart.DzDispatch(const AAction: TTyDzAction);
var
  n, it, i, j, t, u: Integer;
  found: array of Boolean;
  keys: array of string;
  more, linked: Boolean;

  procedure Mark(AIdx: Integer);
  var tt: Integer;
  begin
    found[AIdx] := True;
    for tt := 0 to High(FZoomSpecs[AIdx].Targets) do
    begin
      SetLength(keys, Length(keys) + 1);
      keys[High(keys)] := FZoomSpecs[AIdx].Targets[tt].Dim
        + IntToStr(FZoomSpecs[AIdx].Targets[tt].AxisIndex);
    end;
  end;

begin
  n := Min(Length(FDzRawHas), Length(FZoomSpecs));
  for it := 0 to High(AAction.Items) do
  begin
    i := AAction.Items[it].DataZoomIndex;
    if (i < 0) or (i >= n) then Continue;
    { findEffectedDataZooms }
    SetLength(found, n);
    for j := 0 to n - 1 do found[j] := False;
    keys := nil;
    Mark(i);
    repeat
      more := False;
      for j := 0 to n - 1 do
      begin
        if found[j] then Continue;
        linked := False;
        for t := 0 to High(FZoomSpecs[j].Targets) do
          for u := 0 to High(keys) do
            if keys[u] = FZoomSpecs[j].Targets[t].Dim
              + IntToStr(FZoomSpecs[j].Targets[t].AxisIndex) then linked := True;
        if linked then
        begin
          Mark(j);
          more := True;
        end;
      end;
    until not more;
    for j := 0 to n - 1 do
      if found[j] then
      begin
        FDzRawHas[j] := True;
        FDzRawStart[j] := AAction.Items[it].Start;
        FDzRawStop[j] := AAction.Items[it].Stop;
      end;
  end;
  if AAction.Batch then FDzFrom := -1 else FDzFrom := AAction.FromSlider;
  try
    DzSyncLayout;
  finally
    FDzFrom := -1;
  end;
  if Assigned(FOnDataZoom) then FOnDataZoom(Self, AAction);
end;

{ what the views draw from the slider states: a pointer event that leaves
  it unchanged repaints nothing }
function TTyAdvanceChart.DzStateKey: string;
var
  i: Integer;
  s: TTyDzSliderState;
begin
  Result := '';
  for i := 0 to High(FDzState) do
  begin
    s := FDzState[i];
    Result := Result + Format('%g,%g,%g,%g,%d%d%d%d%d,%d,%d%d,%g,%g;', [s.Ends[0],
      s.Ends[1], s.Range[0], s.Range[1], Ord(s.LabelsShown), Ord(s.NonRealtime),
      Ord(s.HandleHover[0]), Ord(s.HandleHover[1]), Ord(s.Dragging), s.MoveBits,
      Ord(s.HasBrush), Ord(s.BrushIgnored), s.BrushX, s.BrushW]);
  end;
end;

{ the views again, from the state and the window as they are }
procedure TTyAdvanceChart.DzViewUpdate;
begin
  if (FBuild = nil) or (FLastPPI <= 0) then Exit;
  SolveDataZoomViews(NewTextMeasurer(FLastPPI), FLastPPI);
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  DropStatic;
  inherited Invalidate;
end;

{ AN ACTION IS SYNCHRONOUS upstream: the model, the axes and every view are
  new before dispatchAction returns -- so the click that follows a brush
  finds the handles where the brush put them }
procedure TTyAdvanceChart.DzSyncLayout;
begin
  if FLastPPI <= 0 then
  begin
    FDirty := True;
    inherited Invalidate;
    Exit;
  end;
  Relayout(nil, FLastRect, FLastPPI, NewTextMeasurer(FLastPPI));
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  DropStatic;
  inherited Invalidate;
end;

procedure TTyAdvanceChart.DzApplyCursor;
var c: TCursor;
begin
  if FDzCursor = 'ew-resize' then c := crSizeWE
  else if FDzCursor = 'ns-resize' then c := crSizeNS
  else if FDzCursor = 'crosshair' then c := crCross
  else if (FDzCursor = 'grab') or (FDzCursor = 'pointer') then c := crHandPoint
  else if FDzCursor = 'grabbing' then c := crSizeAll
  else
  begin
    { 'default': the host's own cursor back }
    if FDzHasBaseCursor then Cursor := FDzBaseCursor;
    FDzHasBaseCursor := False;
    Exit;
  end;
  if not FDzHasBaseCursor then
  begin
    FDzBaseCursor := Cursor;
    FDzHasBaseCursor := True;
  end;
  Cursor := c;
end;

procedure TTyAdvanceChart.DzArmTimer;
var
  due, now_: Double;
  i: Integer;
  any: Boolean;
begin
  { a test drives the clock itself }
  if not IsNan(FDzNow) then Exit;
  any := False;
  due := MaxDouble;
  for i := 0 to High(FDzState) do
    if FDzState[i].Throttle.Armed then
    begin
      any := True;
      due := Math.Min(due, FDzState[i].Throttle.Due);
    end;
  for i := 0 to High(FDzRoamThrottle) do
    if FDzRoamThrottle[i].Armed then
    begin
      any := True;
      due := Math.Min(due, FDzRoamThrottle[i].Due);
    end;
  if not any then
  begin
    if FDzTimer <> nil then FDzTimer.Enabled := False;
    Exit;
  end;
  if FDzTimer = nil then
  begin
    FDzTimer := TTimer.Create(nil);
    FDzTimer.OnTimer := @DzTimerFired;
  end;
  now_ := DzClock;
  FDzTimer.Enabled := False;
  FDzTimer.Interval := Math.Max(1, Ceil(due - now_));
  FDzTimer.Enabled := True;
end;

procedure TTyAdvanceChart.DzTimerFired(Sender: TObject);
begin
  FDzTimer.Enabled := False;
  DataZoomTick(DzClock);
end;

procedure TTyAdvanceChart.DataZoomTick(ANow: Double);
var
  i, best, kind: Integer;
  due: Double;
  a: TTyDzAction;
begin
  { every run due by now, the earliest first }
  repeat
    best := -1;
    kind := 0;
    due := MaxDouble;
    for i := 0 to High(FDzState) do
      if FDzState[i].Throttle.Armed and (FDzState[i].Throttle.Due <= ANow)
        and (FDzState[i].Throttle.Due < due) then
      begin
        best := i;
        kind := 0;
        due := FDzState[i].Throttle.Due;
      end;
    for i := 0 to High(FDzRoamThrottle) do
      if FDzRoamThrottle[i].Armed and (FDzRoamThrottle[i].Due <= ANow)
        and (FDzRoamThrottle[i].Due < due) then
      begin
        best := i;
        kind := 1;
        due := FDzRoamThrottle[i].Due;
      end;
    if best < 0 then Break;
    if kind = 0 then
    begin
      TyDzThrottleFire(FDzState[best].Throttle, ANow);
      DzRunSliderAction(best, True);
    end
    else
    begin
      TyDzThrottleFire(FDzRoamThrottle[best], ANow);
      a := Default(TTyDzAction);
      a.Batch := True;
      a.Deferred := True;
      a.FromSlider := -1;
      a.Items := FDzRoamBatch[best];
      DzDispatch(a);
    end;
  until False;
  DzArmTimer;
end;

function TTyAdvanceChart.DispatchDataZoom(AIndex: Integer; AStart, AEnd: Double): Boolean;
var a: TTyDzAction;
begin
  Result := (AIndex >= 0) and (AIndex < Length(FDzRawHas)) and not IsNan(AStart)
    and not IsNan(AEnd);
  if not Result then Exit;
  a := Default(TTyDzAction);
  a.FromSlider := -1;
  SetLength(a.Items, 1);
  a.Items[0].DataZoomIndex := AIndex;
  a.Items[0].Start := AStart;
  a.Items[0].Stop := AEnd;
  DzDispatch(a);
end;

function TTyAdvanceChart.DataZoomPointer(AKind: TTyDzPointer; AX, AY: Double;
  AShift: TShiftState; AZrDelta: Double): Boolean;
var
  x, y, s, dx, dy: Double;
  t: TTyDzTarget;
  g, i, ct: Integer;
  any: Boolean;
  key: string;
begin
  Result := False;
  if (FBuild = nil) or (csDesigning in ComponentState) then Exit;
  any := False;
  for i := 0 to High(FZoomSpecs) do
    if (FZoomSpecs[i].SubType = 'slider') or (FZoomSpecs[i].SubType = 'inside') then
      any := True;
  if not any or (Length(FDzState) = 0) then Exit;
  s := DzScale;
  x := (AX - FLastRect.Left) / s;
  y := (AY - FLastRect.Top) / s;
  FDzLastX := AX;
  FDzLastY := AY;
  key := DzStateKey;
  case AKind of
    dpMove:
      begin
        t := DzFindTarget(x, y);
        { the Handler's own cursor: the target's, else the default }
        FDzCursor := 'default';
        if (t.Kind = dtkSlider) then
          case t.Role of
            dzrHandle0, dzrHandle1:
              if FDzLayouts[t.Slider].Horizontal then FDzCursor := 'ew-resize'
              else FDzCursor := 'ns-resize';
            dzrMoveZone, dzrFiller:
              if FDzState[t.Slider].Dragging and (FDzDrag.Kind = dtkSlider)
                and (FDzDrag.Role in [dzrMoveZone, dzrFiller]) then FDzCursor := 'grabbing'
              else FDzCursor := 'grab';
            dzrClickPanel:
              { zrender's own default for an element that answers the
                pointer }
              if FDzViews[t.Slider].BrushSelect then FDzCursor := 'crosshair'
              else FDzCursor := 'pointer';
          end
        else if t.Kind = dtkOther then
          FDzCursor := 'pointer';
        { mouseout to the old target, then the move -- Draggable, the roam,
          the brush -- then mouseover to the new one }
        if not SameDzTarget(t, FDzHover) then DzMouseOut(FDzHover);
        if FDzDrag.Kind = dtkSlider then
        begin
          dx := x - FDzDragX;
          dy := y - FDzDragY;
          FDzDragX := x;
          FDzDragY := y;
          if FDzDrag.Role in [dzrHandle0, dzrHandle1] then
            DzDragMove(FDzDrag.Slider, Ord(FDzDrag.Role) - Ord(dzrHandle0), dx, dy)
          else
          begin
            DzDragMove(FDzDrag.Slider, -1, dx, dy);
            FDzCursor := 'grabbing';
          end;
          Result := True;
        end;
        if FDzPanGrid >= 0 then
        begin
          FDzCursor := 'grabbing';
          if FDzPanGrid < FBuild.GridCount then
          begin
            ct := FDzPanGrid;
            dx := FDzPanX;
            dy := FDzPanY;
            FDzPanX := x;
            FDzPanY := y;
            { preventDefaultMouseMove: every inside of the grid must allow it }
            Result := True;
            for i in DzGridInsides(ct) do
              if not FDzInteract[i].PreventDefaultMouseMove then Result := False;
            DzRoam(ct, 'pan', AShift, dx, dy, x, y, 1, 0);
          end;
        end
        else if t.Kind = dtkNone then
          for g := 0 to FBuild.GridCount - 1 do
            if (DzControlType(g) >= 1) and DzGridContains(g, x, y) then
            begin
              FDzCursor := 'grab';
              Break;
            end;
        for i := 0 to High(FDzState) do
          if FDzState[i].Brushing then
          begin
            DzBrushMove(i, x, y);
            Result := True;
          end;
        if not SameDzTarget(t, FDzHover) then DzMouseOver(t);
        FDzHover := t;
        DzApplyCursor;
        if DzStateKey <> key then DzViewUpdate;
      end;
    dpDown:
      begin
        t := DzFindTarget(x, y);
        FDzDownTarget := t;
        FDzUpTarget := t;
        FDzHasDown := True;
        FDzDownX := x;
        FDzDownY := y;
        { the click panel's mousedown starts a brush }
        if (t.Kind = dtkSlider) and (t.Role = dzrClickPanel)
          and FDzViews[t.Slider].BrushSelect then
        begin
          FDzState[t.Slider].BrushStartX := x;
          FDzState[t.Slider].BrushStartY := y;
          FDzState[t.Slider].Brushing := True;
          FDzState[t.Slider].BrushStartTime := DzClock;
        end;
        { Draggable: a handle, or the move zone }
        FDzDrag := Default(TTyDzTarget);
        if (t.Kind = dtkSlider) and ((t.Role in [dzrHandle0, dzrHandle1, dzrMoveZone])
          or ((t.Role = dzrFiller) and not FDzViews[t.Slider].BrushSelect)) then
        begin
          FDzDrag := t;
          FDzDragX := x;
          FDzDragY := y;
          if t.Role in [dzrMoveZone, dzrFiller] then DzShowDataInfo(t.Slider, True);
        end;
        { the roam controller: not on a draggable element, inside a grid
          that moves }
        FDzPanGrid := -1;
        if FDzDrag.Kind = dtkNone then
          for g := 0 to FBuild.GridCount - 1 do
            if (DzControlType(g) >= 1) and DzGridContains(g, x, y) then
            begin
              FDzPanGrid := g;
              FDzPanX := x;
              FDzPanY := y;
              Break;
            end;
        if DzStateKey <> key then DzViewUpdate;
      end;
    dpUp:
      begin
        FDzUpTarget := DzFindTarget(x, y);
        if FDzDrag.Kind = dtkSlider then
        begin
          i := FDzDrag.Slider;
          FDzDrag := Default(TTyDzTarget);
          DzDragEnd(i);
        end;
        FDzPanGrid := -1;
        for i := 0 to High(FDzState) do
          if FDzState[i].Brushing then DzBrushEnd(i);
        if DzStateKey <> key then DzViewUpdate;
      end;
    dpClick:
      begin
        { zrender's click rule: the press and the release on one element,
          the click within four pixels of the press }
        if not FDzHasDown then Exit;
        FDzHasDown := False;
        if not SameDzTarget(FDzDownTarget, FDzUpTarget) then Exit;
        if Sqrt(Sqr(x - FDzDownX) + Sqr(y - FDzDownY)) > 4 then Exit;
        t := DzFindTarget(x, y);
        if (t.Kind = dtkSlider) and (t.Role = dzrClickPanel) then
        begin
          DzClickPanel(t.Slider, x, y);
          if DzStateKey <> key then DzViewUpdate;
        end;
      end;
    dpWheel:
      begin
        if AZrDelta = 0 then Exit;
        for g := 0 to FBuild.GridCount - 1 do
        begin
          if DzControlType(g) < 2 then Continue;
          if not DzGridContains(g, x, y) then Continue;
          { stopped whether or not anything zooms }
          Result := True;
          DzRoam(g, 'zoom', AShift, 0, 0, x, y, TyDzWheelScale(AZrDelta), 0);
          if (g < FBuild.GridCount) then
            DzRoam(g, 'scrollMove', AShift, 0, 0, x, y, 1, TyDzScrollDelta(AZrDelta));
        end;
      end;
  end;
end;

function TTyAdvanceChart.DataZoomSliderState(AIndex: Integer): TTyDzSliderState;
begin
  Result := Default(TTyDzSliderState);
  if (AIndex >= 0) and (AIndex <= High(FDzState)) then Result := FDzState[AIndex];
end;

function TTyAdvanceChart.DataZoomInsideRange(AIndex: Integer; out ALo, AHi: Double): Boolean;
begin
  ALo := NaN;
  AHi := NaN;
  Result := (AIndex >= 0) and (AIndex <= High(FDzInLo));
  if not Result then Exit;
  ALo := FDzInLo[AIndex];
  AHi := FDzInHi[AIndex];
end;

function TTyAdvanceChart.DataZoomHoverName: string;
const
  cNames: array[TTyDzRole] of string = ('background', 'clickPanel', 'filler',
    'frame', 'handle0', 'handle1', 'moveHandle', 'moveHandleIcon', 'moveZone',
    'shadow0', 'shadow1', 'shadow2', 'shadowPolygon0', 'shadowPolygon1',
    'shadowPolygon2', 'shadowPolyline0', 'shadowPolyline1', 'shadowPolyline2',
    'label0', 'label1');
begin
  case FDzHover.Kind of
    dtkSlider: Result := 'dz' + IntToStr(FDzHover.Slider) + '.' + cNames[FDzHover.Role];
    dtkOther: Result := 'other';
  else
    Result := '';
  end;
end;


function TTyAdvanceChart.DataZoomSliderLayout(AIndex: Integer): TTyDzSliderLayout;
begin
  Result := Default(TTyDzSliderLayout);
  if (AIndex >= 0) and (AIndex <= High(FDzLayouts)) then
    Result := FDzLayouts[AIndex];
end;

function TTyAdvanceChart.MarkerLayout(ASeriesIndex: Integer;
  AKind: TTyMarkerKind): TTyMkBlock;
var slot: Integer;
begin
  Result := Default(TTyMkBlock);
  Result.Kind := AKind;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FMarkers)) then Exit;
  Result := FMarkers[slot].Blocks[AKind];
end;

procedure TTyAdvanceChart.SolveMarkers(APPI: Integer);
var
  i, k: Integer;
  b: TTySeriesBinding;
  ctx: TTyMkContext;
  node, nd: TJSONData;
  kind: TTyMarkerKind;
  ax: TTyAxis;
  scale: Double;
  pin: TTyMkPicInput;
  fpMask: TFPUExceptionMask;
begin
  FMarkers := nil;
  SetLength(FMarkers, Length(FBindings));
  FMarkLinePics := nil;
  SetLength(FMarkLinePics, Length(FBindings));
  FMarkPointPics := nil;
  SetLength(FMarkPointPics, Length(FBindings));
  FMarkAreaPics := nil;
  SetLength(FMarkAreaPics, Length(FBindings));
  if APPI <= 0 then APPI := 96;
  scale := APPI / 96;
  for i := 0 to High(FBindings) do
  begin
    b := FBindings[i];
    FMarkers[i] := Default(TTyMkSeries);
    FMarkers[i].SeriesIndex := b.SeriesIndex;
    for kind := Low(TTyMarkerKind) to High(TTyMarkerKind) do
      FMarkers[i].Blocks[kind].Kind := kind;
    { A SERIES THE LEGEND SWITCHED OFF DRAWS NO MARKERS -- upstream's
      marker views walk only the series the filter kept. Polar markers are
      not ported. }
    if (not b.Resolved) or (b.Cart = nil) or b.Hidden or (i > High(FStores))
      or (FStores[i] = nil) then Continue;
    node := FOption.ComponentAt('series', b.SeriesIndex);
    if (node = nil) or (node.JSONType <> jtObject) then Continue;
    ctx := Default(TTyMkContext);
    ctx.Store := FStores[i];
    ctx.Cart := b.Cart;
    ctx.XAxis := b.XAxis;
    ctx.YAxis := b.YAxis;
    ax := b.Cart.GetBaseAxis;
    if ax <> nil then
    begin
      ctx.BaseDim := ax.Dim;
      ctx.CsBaseHorizontal := ax.Horizontal;
    end;
    ctx.StackedCol := -1;
    ctx.StackResultCol := -1;
    if (i <= High(FStacks)) and FStacks[i].Stacked and (b.ValueAxis <> nil) then
    begin
      ctx.StackedCol := FStores[i].DimIndexOf(b.ValueAxis.Dim);
      ctx.StackResultCol := FStacks[i].ResultCol;
    end;
    ctx.IsBar := (b.SeriesType = 'bar') or (b.SeriesType = 'pictorialBar');
    ctx.BarOffset := NaN;
    ctx.BarSize := NaN;
    if ctx.IsBar and (i <= High(FBarCols)) then
    begin
      ctx.BarOffset := FBarCols[i].Offset;
      ctx.BarSize := FBarCols[i].Width;
    end;
    for k := 0 to 1 do
    begin
      if k = 0 then ax := ctx.XAxis else ax := ctx.YAxis;
      ctx.AlignWithLabel[k] := False;
      if ax = nil then Continue;
      nd := FOption.ComponentAt(ax.MainType, ax.ComponentIndex);
      if (nd <> nil) and (nd.JSONType = jtObject) then
      begin
        nd := TJSONObject(nd).Find('axisTick');
        if (nd <> nil) and (nd.JSONType = jtObject) then
        begin
          nd := TJSONObject(nd).Find('alignWithLabel');
          ctx.AlignWithLabel[k] := (nd <> nil) and (nd.JSONType = jtBoolean)
            and nd.AsBoolean;
        end;
      end;
    end;
    nd := TJSONObject(node).Find('silent');
    ctx.SeriesSilent := (nd <> nil) and (((nd.JSONType = jtBoolean) and nd.AsBoolean)
      or ((nd.JSONType = jtNumber) and (nd.AsFloat <> 0))
      or ((nd.JSONType = jtString) and (nd.AsString <> ''))
      or (nd.JSONType in [jtArray, jtObject]));
    ctx.Scale := scale;
    ctx.OriginX := FLastRect.Left;
    ctx.OriginY := FLastRect.Top;
    ctx.Width := (FLastRect.Right - FLastRect.Left) / scale;
    ctx.Height := (FLastRect.Bottom - FLastRect.Top) / scale;
    for kind := Low(TTyMarkerKind) to High(TTyMarkerKind) do
    begin
      { the ONE nd-level component of the kind is every series marker's
        parent; an array of them gives the first }
      nd := FOption.ComponentAt(TyMarkerKey[kind], 0);
      if (nd <> nil) and (nd.JSONType <> jtObject) then nd := nil;
      FMarkers[i].Blocks[kind] := TyMarkerSolve(kind, TJSONObject(node),
        TJSONObject(nd), ctx);
    end;
    { THE PICTURE of every marker, from the layout just solved }
    if FMarkers[i].Blocks[mkLine].Present or FMarkers[i].Blocks[mkPoint].Present
      or FMarkers[i].Blocks[mkArea].Present then
    begin
      pin := Default(TTyMkPicInput);
      pin.SeriesColor := MarkerSeriesColorCss(i);
      pin.SeriesColorData := MarkerSeriesColorData(i);
      nd := TJSONObject(node).Find('name');
      if (nd <> nil) and (nd.JSONType = jtString) then
        pin.SeriesName := TyMkOf(nd)
      else
        pin.SeriesName := TyMkUndef;
      nd := FOption.Find('textStyle');
      if (nd <> nil) and (nd.JSONType = jtObject) then pin.TextStyle := TJSONObject(nd);
      MarkerGround(pin.Background, pin.IsDark);
      pin.Scale := scale;
      { UNDER MASKED TRAPS: a corner of an unknown category is not a number,
        and upstream draws on regardless }
      fpMask := GetExceptionMask;
      SetExceptionMask(fpMask + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow,
        exPrecision]);
      try
      FMarkLinePics[i] := TyMkLinePictures(FMarkers[i].Blocks[mkLine], pin);
      { the default text reads the last coordinate dim a label may come
        from: not a category, not a time }
      FMarkPointPics[i] := TyMkPointPictures(FMarkers[i].Blocks[mkPoint], pin,
        not (ctx.XAxis.AxisType in [atCategory, atTime]),
        not (ctx.YAxis.AxisType in [atCategory, atTime]));
      FMarkAreaPics[i] := TyMkAreaPictures(FMarkers[i].Blocks[mkArea], pin);
      finally
        SetExceptionMask(fpMask);
      end;
    end;
  end;
end;

{ upstream's series style colour as a css string: what the author wrote in
  itemStyle.color, candlestick's own default, else the palette's }
function TTyAdvanceChart.MarkerSeriesColorCss(ASlot: Integer): string;
var
  node, d: TJSONData;
  c: TTyColor;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (node <> nil) and (node.JSONType = jtObject) then
  begin
    d := TJSONObject(node).Find('itemStyle');
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      d := TJSONObject(d).Find('color');
      if (d <> nil) and (d.JSONType = jtString) then Exit(d.AsString);
    end;
  end;
  c := SeriesColor(FBindings[ASlot].SeriesIndex);
  if (c shr 24) = $FF then
    Result := '#' + LowerCase(IntToHex(c and $FFFFFF, 6))
  else
    Result := 'rgba(' + IntToStr((c shr 16) and $FF) + ',' + IntToStr((c shr 8) and $FF)
      + ',' + IntToStr(c and $FF) + ',' + TyJsNumberToString((c shr 24) / 255) + ')';
end;

{ the author's series colour when it is not a string: a gradient, used by a
  markArea as it is }
function TTyAdvanceChart.MarkerSeriesColorData(ASlot: Integer): TJSONData;
var node, d: TJSONData;
begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('itemStyle');
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  d := TJSONObject(d).Find('color');
  if (d <> nil) and (d.JSONType = jtObject) then Result := d;
end;

{ THE GROUND upstream's marker label halo is made of: the option's
  backgroundColor, else 'transparent' -- and dark by the option's darkMode
  when it says, else by zrender's own luminance test }
procedure TTyAdvanceChart.MarkerGround(out ABackground: string; out AIsDark: Boolean);
var
  d: TJSONData;
begin
  d := FOption.Find('backgroundColor');
  if (d <> nil) and (d.JSONType = jtString) then
    ABackground := d.AsString
  else
    { UPSTREAM'S GROUND, 'transparent', not the skin's: the picture is
      upstream's answer, and the paint takes the halo from the skin anyway }
    ABackground := 'transparent';
  d := FOption.Find('darkMode');
  if (d <> nil) and (d.JSONType = jtBoolean) then AIsDark := d.AsBoolean
  else AIsDark := TyMkGroundIsDark(ABackground);
end;

function TTyAdvanceChart.MarkLinePictures(ASeriesIndex: Integer): TTyMkLinePicArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FMarkLinePics)) then Exit;
  Result := FMarkLinePics[slot];
end;

function TTyAdvanceChart.MarkPointPictures(ASeriesIndex: Integer): TTyMkPointPicArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FMarkPointPics)) then Exit;
  Result := FMarkPointPics[slot];
end;

function TTyAdvanceChart.MarkAreaPictures(ASeriesIndex: Integer): TTyMkAreaPicArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FMarkAreaPics)) then Exit;
  Result := FMarkAreaPics[slot];
end;

function TTyAdvanceChart.BuildMarkers(const AMeasurer: ITyTextMeasurer;
  AList: TTyPaintList): Integer;
var
  i: Integer;
  ink: TTyMkInk;
  st: TTyStyleSet;
  dark: Boolean;
begin
  Result := 0;
  st := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  ink.FontName := st.FontName;
  ink.FontSizeLogical := ResolveFontSize(st);
  ink.FontWeight := st.FontWeight;
  ink.Text := TTyChartColor(st.TextColor);
  LabelGround(ink.Halo, dark);
  ink.Inside[0] := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight', '', []).TextColor);
  ink.Inside[1] := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []).TextColor);
  ink.Inside[2] := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '', []).TextColor);
  for i := 0 to High(FMarkAreaPics) do
    if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkArea].Present then
      Inc(Result, TyBuildMarkAreas(FMarkAreaPics[i], FMarkers[i].Blocks[mkArea], ink,
        AMeasurer, AList));
  for i := 0 to High(FMarkPointPics) do
    if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkPoint].Present then
      Inc(Result, TyBuildMarkPoints(FMarkPointPics[i], FMarkers[i].Blocks[mkPoint], ink,
        AMeasurer, AList));
  for i := 0 to High(FMarkLinePics) do
    if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkLine].Present then
      Inc(Result, TyBuildMarkLines(FMarkLinePics[i], FMarkers[i].Blocks[mkLine], ink,
        AMeasurer, AList));
end;

function TTyAdvanceChart.DataZoomCount: Integer;
begin
  Result := Length(FZoomSpecs);
end;

function TTyAdvanceChart.DataZoomSpec(AIndex: Integer): TTyDataZoomSpec;
begin
  Result := Default(TTyDataZoomSpec);
  if (AIndex >= 0) and (AIndex <= High(FZoomSpecs)) then Result := FZoomSpecs[AIndex];
end;

function TTyAdvanceChart.AxisZoom(const AMainType: string; AAxisIndex: Integer;
  out AZoom: TTyAxisZoom; out AWindow: TTyDzWindow; out AHost: Integer): Boolean;
var
  ax: TTyAxis;
  k: Integer;
begin
  Result := False;
  AZoom := Default(TTyAxisZoom);
  AWindow := Default(TTyDzWindow);
  AHost := -1;
  if FBuild = nil then Exit;
  ax := FBuild.Axis(AMainType, AAxisIndex);
  if ax = nil then Exit;
  for k := 0 to High(FAxisZooms) do
    if FAxisZooms[k].Axis = ax then
    begin
      AZoom := FAxisZooms[k];
      AWindow := FZoomWindows[k];
      AHost := FZoomHost[k];
      Exit(True);
    end;
end;

function TTyAdvanceChart.SeriesStore(ASeriesIndex: Integer): TTyDataStore;
var k: Integer;
begin
  Result := nil;
  for k := 0 to High(FBindings) do
    if (FBindings[k].SeriesIndex = ASeriesIndex) and (k <= High(FStores)) then
      Exit(FStores[k]);
end;

function TTyAdvanceChart.VisualMapCount: Integer;
begin
  Result := Length(FVisualSpecs);
end;

function TTyAdvanceChart.VisualMapSpec(AIndex: Integer): TTyVisualMapSpec;
begin
  Result := Default(TTyVisualMapSpec);
  if (AIndex >= 0) and (AIndex <= High(FVisualSpecs)) then
    Result := FVisualSpecs[AIndex];
end;

function TTyAdvanceChart.VisualRow(ASeriesIndex, ARawIndex: Integer;
  out ARow: TTyVisualRow): Boolean;
var slot: Integer;
begin
  ARow := Default(TTyVisualRow);
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FVisualRows)) then Exit;
  if (ARawIndex < 0) or (ARawIndex > High(FVisualRows[slot])) then Exit;
  ARow := FVisualRows[slot][ARawIndex];
  Result := True;
end;

function TTyAdvanceChart.VisualMetas(ASeriesIndex: Integer): TTyVisualMetaArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FVisualMetas)) then
    Result := FVisualMetas[slot];
end;

function TTyAdvanceChart.VisualLineFill(ASeriesIndex: Integer): TTyVisualLineFill;
var slot: Integer;
begin
  Result := Default(TTyVisualLineFill);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FVisualLines)) then
    Result := FVisualLines[slot];
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
    AVisual.Alpha := Min(Double(1), Max(Double(0), item.Opacity))
  else if st = 'scatter' then
    { A SCATTER'S SYMBOLS ARE FOUR FIFTHS OPAQUE unless told otherwise --
      ScatterSeries' own default, which its labels inherit. [Revised in
      batch 47: they were opaque.] }
    AVisual.Alpha := 0.8;
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
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesColorNone))
    and FSeriesColorNone[ASeriesIndex] then
    Exit(0);

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
    if (FBindings[i].CalendarIndex >= 0)
      and (FBindings[i].CalendarIndex <= High(FCalendars)) then
    begin
      FPies[i] := CalendarPieLayout(i, dim);
      Continue;
    end;
    FPies[i] := TyPieLayoutOf(FPieSpecs[i], FLastRect, FStores[i], dim);
  end;
end;

{ A PIE ON A CALENDAR: laid out in the content rect of a day's cell --
  createBoxLayoutReference asks the calendar's dataToLayout for the pie's
  coordinate, which is `coord` when written and else `center` read as a
  date. The box and a percentage radius are taken against that rect; the
  centre is the rect's own centre when the date came from `center`, and
  `center` inside the box when it came from `coord`. A date off the range
  leaves the cell's size and no position: the radius is a number, the
  centre is not, and nothing is drawn. [Batch 72] }
function TTyAdvanceChart.CalendarPieLayout(ASlot, ADim: Integer): TTyPieLayout;
var
  node, d: TJSONData;
  cal: TTyCalendar;
  dv: TTyDataValue;
  fromCentre: Boolean;
  lay: TTyCoordLayout;
  cx, cy: Double;
  k: Integer;
begin
  cal := FCalendars[FBindings[ASlot].CalendarIndex];
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  d := nil;
  fromCentre := True;
  if (node <> nil) and (node.JSONType = jtObject) then
  begin
    d := TJSONObject(node).Find('coord');
    if (d <> nil) and (d.JSONType <> jtNull) then fromCentre := False
    else d := TJSONObject(node).Find('center');
  end;
  dv := Default(TTyDataValue);
  if d <> nil then
    case d.JSONType of
      jtNumber: dv := TyDataNum(d.AsFloat);
      jtString:
        begin
          dv.Kind := dvkText;
          dv.Text := d.AsString;
        end;
    end;
  { no date at all -- the default ['50%', '50%'] read as one -- is a cell of
    no position }
  lay := cal.DateLayout(cal.ParseDate(dv), True);
  Result := TyPieLayoutOf(FPieSpecs[ASlot], lay.ContentRect, FStores[ASlot], ADim);
  { A CELL OF NO POSITION draws nothing: upstream's sectors are there with a
    centre that is not a number, which paints nowhere }
  if IsNan(lay.ContentRect.Left) or IsNan(lay.ContentRect.Top) then
  begin
    Result.Valid := False;
    Exit;
  end;
  if not fromCentre then Exit;
  cx := (lay.ContentRect.Left + lay.ContentRect.Right) / 2;
  cy := (lay.ContentRect.Top + lay.ContentRect.Bottom) / 2;
  Result.CX := cx;
  Result.CY := cy;
  for k := 0 to High(Result.Sectors) do
  begin
    Result.Sectors[k].CX := cx;
    Result.Sectors[k].CY := cy;
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

procedure TTyAdvanceChart.FreeCalendars;
var i: Integer;
begin
  for i := 0 to High(FCalendars) do FreeAndNil(FCalendars[i]);
  FCalendars := nil;
end;

{ THE CALENDARS: each laid out on the whole canvas, as upstream's is -- its
  box is getLayoutRect against the chart's width and height, with no margin
  and nothing else shrinking it. [Batch 69] }
procedure TTyAdvanceChart.SolveCalendars(APPI: Integer);
var i, n: Integer;
begin
  FreeCalendars;
  n := 0;
  if FOption <> nil then n := FOption.ComponentCount('calendar');
  if n = 0 then Exit;
  SetLength(FCalendars, n);
  for i := 0 to n - 1 do
  begin
    FCalendars[i] := TTyCalendar.Create(TyCalendarSpecOf(FOption, i));
    FCalendars[i].Resize(FLastRect, APPI);
  end;
end;

{ THE CALENDAR'S INK, from keys the chart already has: a day cell is the
  ground an empty symbol is filled with, its border an axis split line; the
  month lines are an axis line, the day and month names axis labels, and the
  year the subtitle's quieter ink. Upstream's own tokens for them are the
  same neutrals those keys default to. }
function TTyAdvanceChart.CalendarInk: TTyCalendarInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  Result := Default(TTyCalendarInk);
  model := ActiveController.Model;
  Result.CellFill := TTyChartColor(
    model.ResolveStyle('TyAdvChartEmptyCircle', '', []).Background.Color);
  Result.CellBorder := TTyChartColor(
    model.ResolveStyle('TyAdvChartSplitLine', '', []).BorderColor);
  Result.SplitLine := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisLine', '', []).BorderColor);
  st := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  Result.LabelFontName := st.FontName;
  Result.LabelFontSizeLogical := ResolveFontSize(st);
  Result.LabelFontWeight := st.FontWeight;
  st := model.ResolveStyle('TyAdvChartSubtitle', '', []);
  Result.YearColour := TTyChartColor(st.TextColor);
  Result.YearFontName := st.FontName;
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

function TTyAdvanceChart.GraphView(ASeriesIndex: Integer): TTyGraphView;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FGraphs)) then Exit;
  Result := FGraphs[slot];
end;

function TTyAdvanceChart.GraphNodeScale(ASeriesIndex: Integer): Double;
var slot: Integer;
begin
  Result := NaN;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FGraphNodeScale)) then Exit;
  Result := FGraphNodeScale[slot];
end;

function TTyAdvanceChart.GraphRoamState(ASeriesIndex: Integer;
  out ACentre: TTyGraphCentre; out AZoom: Double): Boolean;
var slot: Integer;
begin
  ACentre := Default(TTyGraphCentre);
  AZoom := NaN;
  slot := SlotOfSeries(ASeriesIndex);
  Result := (slot >= 0) and (slot <= High(FGraphs)) and (FGraphs[slot] <> nil);
  if not Result then Exit;
  if (ASeriesIndex <= High(FGraphRoam)) and FGraphRoam[ASeriesIndex].Valid then
  begin
    ACentre := FGraphRoam[ASeriesIndex].Centre;
    AZoom := FGraphRoam[ASeriesIndex].Zoom;
  end
  else
  begin
    ACentre := FGraphSpecs[slot].Centre;
    AZoom := FGraphSpecs[slot].Zoom;
  end;
end;

function TTyAdvanceChart.GraphRoam(ASeriesIndex: Integer;
  ADX, ADY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasPan := True;
  p.DX := ADX;
  p.DY := ADY;
  Result := GraphDispatchRoam(p);
end;

function TTyAdvanceChart.GraphZoom(ASeriesIndex: Integer; AScale, AOriginX,
  AOriginY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasZoom := True;
  p.Zoom := AScale;
  p.OriginX := AOriginX;
  p.OriginY := AOriginY;
  Result := GraphDispatchRoam(p);
end;

function TTyAdvanceChart.GraphDispatchRoam(
  const APayload: TTyGraphRoamPayload): Boolean;
var
  i, si: Integer;
  p: TTyGraphRoamPayload;
begin
  Result := False;
  { A NEGATIVE OR NON-FINITE ZOOM IS REFUSED. Upstream mirrors the picture
    through a rotation and then flips the sign back on the next step; that is
    not a thing anybody asks for on purpose. }
  if APayload.HasZoom and (IsNan(APayload.Zoom) or IsInfinite(APayload.Zoom)
    or (APayload.Zoom <= 0)) then Exit;
  if APayload.HasPan and (IsNan(APayload.DX) or IsNan(APayload.DY)) then Exit;
  for i := 0 to High(FGraphs) do
  begin
    if FGraphs[i] = nil then Continue;
    if (i > High(FGraphLaidOut)) or not FGraphLaidOut[i] then Continue;
    si := FBindings[i].SeriesIndex;
    if (APayload.SeriesIndex >= 0) and (si <> APayload.SeriesIndex) then
      Continue;
    if Length(FGraphRoam) <= si then SetLength(FGraphRoam, si + 1);
    TyGraphRoamStep(FGraphs[i], FGraphSpecs[i], APayload, FGraphRoam[si]);
    TyGraphRemap(FGraphNodes[i], FGraphEdges[i], FGraphSpecs[i], FGraphs[i],
      APayload.HasZoom, FGraphNodeScale[i]);
    Result := True;
    if Assigned(FOnGraphRoam) then
    begin
      p := APayload;
      p.SeriesIndex := si;
      FOnGraphRoam(Self, p);
    end;
  end;
  if not Result then Exit;
  { A NEW PICTURE, NOT A NEW LAYOUT: the static layer goes, the build and
    the force answer stay. The hover names an element of a list about to be
    rebuilt. }
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  DropStatic;
  inherited Invalidate;
end;

function TTyAdvanceChart.RoamSeriesAt(AX, AY: Integer; AZoom: Boolean): Integer;
var
  i, best: Integer;
  sp, bs: TTyGraphSpec;
  ok: Boolean;
begin
  Result := -1;
  best := -1;
  bs := Default(TTyGraphSpec);
  for i := 0 to High(FGraphs) do
  begin
    if FGraphs[i] = nil then Continue;
    if (i > High(FGraphLaidOut)) or not FGraphLaidOut[i] then Continue;
    sp := FGraphSpecs[i];
    if AZoom then ok := sp.Roam in [grmZoom, grmBoth]
    else ok := sp.Roam in [grmPan, grmBoth];
    if not ok then Continue;
    if not (sp.RoamGlobal or FGraphs[i].ContainTrigger(AX, AY)) then Continue;
    { HIGHER zlevel, THEN HIGHER z; A TIE GOES TO THE ONE FOUND FIRST. }
    if (best < 0) or (sp.ZLevel > bs.ZLevel)
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z > bs.Z))
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z = bs.Z)
        and (FBindings[i].SeriesIndex < FBindings[best].SeriesIndex)) then
    begin
      best := i;
      bs := sp;
    end;
  end;
  if best >= 0 then Result := FBindings[best].SeriesIndex;
end;

procedure TTyAdvanceChart.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  d: TTyChartDatumRef;
  el, slot, k: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if csDesigning in ComponentState then Exit;
  { A MIDDLE OR RIGHT PRESS NEITHER ARMS NOR DISARMS. }
  if Button <> mbLeft then Exit;
  FRoamSeries := -1;
  { A PRESS ON A DRAGGABLE NODE IS THE NODE'S, not the view's. }
  d := HitTestAt(X, Y, el);
  if (d.SeriesIndex >= 0) and not d.IsEdge then
  begin
    slot := SlotOfSeries(d.SeriesIndex);
    if (slot >= 0) and (slot <= High(FGraphNodes))
      and (slot <= High(FGraphLaidOut)) and FGraphLaidOut[slot] then
      for k := 0 to High(FGraphNodes[slot]) do
        if (FGraphNodes[slot][k].Row = d.DataIndex)
          and FGraphNodes[slot][k].Draggable then Exit;
  end;
  { A PRESS ON A dataZoom (a handle, the move bar, the slider body, a
    zooming grid) is the dataZoom's }
  DataZoomPointer(dpDown, X, Y, Shift, 0);
  if (FDzDrag.Kind = dtkSlider) or (FDzPanGrid >= 0)
    or ((FDzDownTarget.Kind = dtkSlider) and (FDzDownTarget.Role = dzrClickPanel)) then Exit;
  FRoamSeries := RoamSeriesAt(X, Y, False);
  FRoamX := X;
  FRoamY := Y;
end;

procedure TTyAdvanceChart.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if Button = mbLeft then
  begin
    FRoamSeries := -1;
    { zrender's mouseup, then the DOM click at the same point }
    DataZoomPointer(dpUp, X, Y, Shift, 0);
    DataZoomPointer(dpClick, X, Y, Shift, 0);
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TTyAdvanceChart.CaptureChanged;
begin
  { THE BUTTON CAME UP SOMEWHERE THIS CONTROL WILL NOT HEAR OF, or another
    window took the mouse. Either way the drag is over. A dataZoom's ends as
    a mouseup where the pointer was last would end it -- its commit and all;
    the widgetset's own mouseup, when it follows, finds nothing to end. }
  FRoamSeries := -1;
  if (FDzDrag.Kind <> dtkNone) or (FDzPanGrid >= 0) then
    DataZoomPointer(dpUp, FDzLastX, FDzLastY, [], 0);
  inherited CaptureChanged;
end;

function TTyAdvanceChart.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  s: Double;
  si: Integer;
begin
  { THE HOST'S HANDLER FIRST, and one that takes the wheel keeps it. }
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if csDesigning in ComponentState then Exit;
  { a wheel in a zooming grid is the dataZoom's, and stopped there }
  if DataZoomPointer(dpWheel, MousePos.X, MousePos.Y, Shift,
    TyDzZrDelta(WheelDelta)) then Exit(True);
  s := TyGraphWheelScale(WheelDelta);
  if s = 0 then Exit;
  si := RoamSeriesAt(MousePos.X, MousePos.Y, True);
  if si < 0 then Exit;
  Result := GraphZoom(si, s, MousePos.X, MousePos.Y);
end;

function TTyAdvanceChart.RadarLayout(AIndex: Integer): TTyRadar;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FRadars)) then Result := FRadars[AIndex];
end;

function TTyAdvanceChart.CalendarLayout(AIndex: Integer): TTyCalendar;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FCalendars)) then
    Result := FCalendars[AIndex];
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

{ THE TREES: each laid out in its box on the whole canvas, as a pie is.
  [Batch 73] }
procedure TTyAdvanceChart.SolveTrees(APPI: Integer);
var i: Integer;
begin
  FTrees := nil;
  SetLength(FTrees, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FTrees[i] := Default(TTyTreeSolved);
    if FBindings[i].SeriesType <> TyTreeSeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    FTrees[i] := TyTreeSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI);
  end;
end;

{ THE SUNBURSTS: laid out on the whole canvas, then coloured in one pass
  whose palette cursor every sunburst in the chart shares -- a second
  sunburst's first root takes the palette's NEXT colour. [Batch 75] }
procedure TTyAdvanceChart.SolveSunbursts(APPI: Integer);
var
  i, k: Integer;
  cur: TTyPaletteCursor;
  pal, ramp: TTyChartColorArray;
  declared: Boolean;
begin
  FSunbursts := nil;
  SetLength(FSunbursts, Length(FBindings));
  cur := TyPaletteStart(nil);
  SetLength(ramp, 9);
  for k := 0 to 8 do ramp[k] := TTyChartColor(ThemeRampColor(k));
  for i := 0 to High(FBindings) do
  begin
    FSunbursts[i] := Default(TTySunburstSolved);
    if FBindings[i].SeriesType <> TySunburstSeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    FSunbursts[i] := TySunburstSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI);
    { the series' own palette, else the chart's, else the theme's ramp }
    pal := TyChartPaletteOf(FOption, FBindings[i].SeriesIndex, declared);
    if not declared then pal := TyChartPaletteOf(FOption, -1, declared);
    if not declared then pal := ramp;
    TySunburstColour(FSunbursts[i], pal, cur);
    { A VISUALMAP RUNS AFTER the sunburst's own visual and overwrites the
      fill of every node it maps -- the label's ink follows the new fill.
      [Batch 77] }
    if (i <= High(FVisualRows)) and (FVisualRows[i] <> nil) then
      for k := 0 to Min(High(FSunbursts[i].Nodes), High(FVisualRows[i])) do
        if FVisualRows[i][k].ColorSet then
          FSunbursts[i].Nodes[k].Fill := TyVisualToChart(FVisualRows[i][k].Color);
  end;
end;

{ THE TREEMAPS: each laid out in its box on the whole canvas, coloured from
  the CHART's palette (a treemap's own `color` is a list its levels map by,
  not a palette), its labels cut to their cells and its breadcrumb found --
  all of which needs the measurer. [Batch 76] }
procedure TTyAdvanceChart.SolveTreemaps(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i, k, dim: Integer;
  pal: TTyChartColorArray;
  declared: Boolean;
  border: TTyChartColor;
begin
  FTreemaps := nil;
  FTreemapInks := nil;
  SetLength(FTreemaps, Length(FBindings));
  SetLength(FTreemapInks, Length(FBindings));
  pal := TyChartPaletteOf(FOption, -1, declared);
  if not declared then
  begin
    SetLength(pal, 9);
    for k := 0 to 8 do pal[k] := TTyChartColor(ThemeRampColor(k));
  end;
  border := TTyChartColor(ActiveController.Model.ResolveStyle(GetStyleTypeKey,
    StyleClass, [tysNormal]).Background.Color);
  for i := 0 to High(FBindings) do
  begin
    FTreemaps[i] := Default(TTyTreemapSolved);
    FTreemapInks[i] := Default(TTyTreemapInk);
    if FBindings[i].SeriesType <> TyTreemapSeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    FTreemaps[i] := TyTreemapSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI);
    if not FTreemaps[i].Valid then Continue;
    TyTreemapColour(FTreemaps[i], pal, border);
    FTreemapInks[i] := TreemapInk(i);
    dim := -1;
    if FStores[i] <> nil then dim := FStores[i].DimIndexOf('value');
    TyTreemapLabels(FTreemaps[i], FTreemapInks[i].ItemLabels, FStores[i],
      SeriesModelName(FBindings[i].SeriesIndex), dim, AMeasurer);
    TyTreemapBreadcrumb(FTreemaps[i],
      FTreemapInks[i].ItemLabels[High(FTreemapInks[i].ItemLabels)], AMeasurer,
      FLastRect);
  end;
end;

{ A TREEMAP'S INK: its labels in their own key's ink -- white over the
  palette in every mode, never the auto bands -- read item -> level ->
  series; after the rows, the breadcrumb's words, and its chip. }
function TTyAdvanceChart.TreemapInk(ASlot: Integer): TTyTreemapInk;
var
  base, crumb: TTyLabelSpec;
  ls, cs: TTyStyleSet;
begin
  Result := Default(TTyTreemapInk);
  ls := ActiveController.Model.ResolveStyle('TyAdvChartTreemapLabel', '', []);
  base := LabelBaseFor(ASlot);
  base.Show := True;
  base.DefaultText := tldName;
  base.AutoColour := False;
  base.Colour := TTyChartColor(ls.TextColor);
  base.FontName := ls.FontName;
  base.FontSizeLogical := ResolveFontSize(ls);
  base.FontWeight := ls.FontWeight;
  Result.Label_ := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
  Result.ItemLabels := TyTreemapLabelSpecs(FTreemaps[ASlot], Result.Label_);
  cs := ActiveController.Model.ResolveStyle('TyAdvChartBreadcrumb', '', []);
  crumb := TyLabelSpecNone;
  crumb.Show := True;
  crumb.AutoColour := False;
  crumb.Colour := TTyChartColor(cs.TextColor);
  crumb.FontName := cs.FontName;
  crumb.FontSizeLogical := ResolveFontSize(cs);
  crumb.FontWeight := cs.FontWeight;
  SetLength(Result.ItemLabels, Length(Result.ItemLabels) + 1);
  Result.ItemLabels[High(Result.ItemLabels)] := crumb;
  Result.CrumbFill := TTyChartColor(cs.Background.Color);
end;

{ A SUNBURST'S INK: the ring separator is the chart's own ground (upstream's
  white), and the labels are shown by default with the node's name, read
  item -> level -> series. }
function TTyAdvanceChart.SunburstInk(ASlot: Integer): TTySunburstInk;
var base: TTyLabelSpec;
begin
  Result := Default(TTySunburstInk);
  Result.Border := TTyChartColor(
    ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
  base := LabelBaseFor(ASlot);
  base.Show := True;
  base.DefaultText := tldName;
  Result.Label_ := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
  Result.ItemLabels := TySunburstLabelSpecs(FSunbursts[ASlot], Result.Label_);
  Result.SeriesName := SeriesModelName(FBindings[ASlot].SeriesIndex);
  Result.LabelValueDim := -1;
  if FStores[ASlot] <> nil then
    Result.LabelValueDim := FStores[ASlot].DimIndexOf('value');
end;

{ A TREE'S INK: the node colour the palette pass settled (the theme's, or
  the series' own), the edge colour from its key, a ring's hole from the
  chart's own ground, and the labels -- shown by default, the node's name
  their words, read item -> leaves -> series. }
function TTyAdvanceChart.TreeInk(ASlot: Integer): TTyTreeInk;
var
  base: TTyLabelSpec;
begin
  Result := Default(TTyTreeInk);
  Result.NodeColour := TTyChartColor(SeriesColor(FBindings[ASlot].SeriesIndex));
  Result.EdgeColour := TTyChartColor(ActiveController.Model.ResolveStyle(
    'TyAdvChartTreeEdge', '', []).BorderColor);
  Result.EmptyFill := TTyChartColor(
    ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
  base := LabelBaseFor(ASlot);
  base.Show := True;
  base.DefaultText := tldName;
  Result.Label_ := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
  Result.ItemLabels := TyTreeLabelSpecs(FTrees[ASlot], Result.Label_);
  Result.SeriesName := SeriesModelName(FBindings[ASlot].SeriesIndex);
  Result.LabelValueDim := -1;
  if FStores[ASlot] <> nil then
    Result.LabelValueDim := FStores[ASlot].DimIndexOf('value');
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
  FGraphNodeScale := nil;
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
  SetLength(FGraphNodeScale, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FGraphs[i] := nil;
    FGraphLaidOut[i] := False;
    FGraphNodeScale[i] := 1;
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
    { A GRAPH ON A CALENDAR: each node where the calendar puts its date,
      under upstream's own rule for which nodes are placed at all -- see
      CalendarGraphPoints. [Batch 72] }
    if (FBindings[i].CalendarIndex >= 0)
      and (FBindings[i].CalendarIndex <= High(FCalendars)) and (store <> nil) then
    begin
      solved := TyGraphSolveAtPoints(FOption, si, store,
        CalendarGraphPoints(si, FCalendars[FBindings[i].CalendarIndex]));
      FGraphLaidOut[i] := True;
      FGraphSpecs[i] := solved.Spec;
      FGraphNodes[i] := solved.Nodes;
      FGraphEdges[i] := solved.Edges;
      FGraphCats[i] := solved.Cats;
      Continue;
    end;
    { ANY OTHER SYSTEM BUT A VIEW IS NOT PORTED -- polar, geo --
      and a graph on one resolves and draws nothing rather than being quietly
      given a view it did not ask for. }
    if FBindings[i].CoordSysName <> 'view' then Continue;
    if Length(FGraphForce) <= si then SetLength(FGraphForce, si + 1);
    if Length(FGraphRoam) <= si then SetLength(FGraphRoam, si + 1);
    { THE WHOLE PASS IS THE PURE UNIT'S, so the suite drives the same path this
      does rather than a copy of it. }
    solved := TyGraphSolve(FOption, si, store, FLastRect, FGraphForce[si],
      FGraphRoam[si]);
    FGraphs[i] := solved.View;
    FGraphNodeScale[i] := solved.NodeScale;
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
  i, si, raw: Integer;
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
  begin
    Result.NodeFills[i] := TyGraphNodeFill(FGraphNodes[ASlot][i], cols,
      Length(FGraphCats[ASlot]), base, store, Result.EdgeEndFills[i]);
    { A visualMap's colour over the category's and the series' -- the
      category visual runs before the encoding -- and under the node's own }
    raw := FGraphNodes[ASlot][i].RawRow;
    if (ASlot <= High(FVisualRows)) and (raw >= 0)
      and (raw <= High(FVisualRows[ASlot])) and FVisualRows[ASlot][raw].ColorSet
      and not ((store <> nil) and store.HasOverrideByRaw(raw,
        TyOverrideKey('itemStyle.color'))) then
    begin
      Result.NodeFills[i] := TyVisualToChart(FVisualRows[ASlot][raw].Color);
      Result.EdgeEndFills[i] := Result.NodeFills[i];
    end;
  end;

  { A NODE'S LABEL IS ITS NAME, and the graph is the only series here whose
    default formatter says so: `label.formatter: '{b}'` is in its own
    defaultOption -- a TEMPLATE, so a name is read the way formatTpl reads it.
    Being a default, the option can take it away: `formatter: null` stays
    null through upstream's merge, and a node then shows what every other
    series shows, its VALUE (on a cartesian graph, the value axis' column). }
  Result.Label_ := LabelSpecFor(ASlot, '{b}');
  Result.Label_.DefaultText := tldValue;
  Result.SeriesName := SeriesModelName(FBindings[ASlot].SeriesIndex);
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
  seen, fixLo, fixHi, incl0: Boolean;
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
      { THE RAW RANGE, THEN ALIGNED to splitNumber segments -- upstream's
        radar runs every spoke through scaleCalcAlign. [Revised in batch 48:
        the raw range was the spoke's extent.] }
      TyRadarIndicatorExtent(spec.Indicators[j], dLo, dHi, spec.Scale_, lo, hi,
        fixLo, fixHi, incl0);
      FRadars[k].AlignAxis(j, lo, hi, fixLo, fixHi, incl0);
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
  k: Integer;
  node: TJSONObject;
  d: TJSONData;
  ls, ar: TJSONObject;
  c: TTyChartColor;
begin
  Result := TyRadarVisual(SeriesColor(ASlot));
  Result.Fills := PerDatumColours(ASlot);
  { a visualMap's symbolSize per ring }
  if (ASlot <= High(FVisualRows)) and (FVisualRows[ASlot] <> nil) then
  begin
    SetLength(Result.Sizes, Length(FVisualRows[ASlot]));
    for k := 0 to High(FVisualRows[ASlot]) do
      if FVisualRows[ASlot][k].SizeSet then Result.Sizes[k] := FVisualRows[ASlot][k].Size
      else Result.Sizes[k] := NaN;
  end;
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
  LabelGround(Result.Ground, Result.GroundDark);
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
  d: TJSONData;
  st: TTyOptStyle;
  mapped: array of Boolean;
  asked: Integer;
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
  SetLength(mapped, rawN);
  { A visualMap's colour FIRST: upstream's per-data palette runs after the
    encoding (priority 4500) and passes over any datum a colour channel
    wrote, so only the rest ask the palette -- in the order they ask, not
    by row. [Batch 57: the palette went to every row by row index.] }
  asked := 0;
  for k := 0 to rawN - 1 do
  begin
    mapped[k] := (ASlot <= High(FVisualRows)) and (k <= High(FVisualRows[ASlot]))
      and FVisualRows[ASlot][k].ColorSet;
    if mapped[k] then
    begin
      Result[k] := TyVisualToChart(FVisualRows[ASlot][k].Color);
      Continue;
    end;
    Result[k] := TTyChartColor(ThemeRampColor(asked));
    Inc(asked);
    if Length(pal) = 0 then Continue;
    nm := FStores[ASlot].GetNameByRaw(k);
    if nm = '' then nm := IntToStr(k);
    if TyPaletteTake(cur, nm, c) then Result[k] := c;
  end;
  { THE SERIES' OWN `itemStyle.color` beats the ramp for every datum -- it is
    the parent of each datum's style. [Revised in batch 47: it was not read,
    and every slice kept the ramp's colour.] }
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if d is TJSONObject then
  begin
    st := TyReadOptStyle(TJSONObject(d), 'itemStyle');
    if st.Color.Written and not st.Color.IsAuto then
      for k := 0 to rawN - 1 do
        { the visual colour was worked out FROM this one; it stands }
        if mapped[k] then Continue
        else if st.Color.IsNone then Result[k] := 0
        else Result[k] := st.Color.Color;
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
  { AND A visualMap's OPACITY, which a pie keeps (a funnel does not) }
  SetLength(Result.Alphas, n);
  for k := 0 to n - 1 do
  begin
    Result.Alphas[k] := NaN;
    if k > High(FPies[ASlot].Sectors) then Continue;
    raw := FPies[ASlot].Sectors[k].RawIndex;
    if (ASlot <= High(FVisualRows)) and (raw >= 0)
      and (raw <= High(FVisualRows[ASlot])) and FVisualRows[ASlot][raw].OpacitySet then
      Result.Alphas[k] := FVisualRows[ASlot][raw].Opacity;
  end;
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
          { A TRANSPARENT DATUM IS SHOWN AT A FIFTH, as the category chip
            above is -- but the swatch still carries the datum's own opacity,
            so a slice a visualMap put out of range (colour and opacity both
            nought) stays invisible there too. }
          if (LongWord(Result[i].Colour) shr 24) = 0 then
            Result[i].Colour := TTyChartColor(
              (LongWord(Result[i].Colour) and $00FFFFFF) or $33000000);
          if (j <= High(FVisualRows)) and (k <= High(FVisualRows[j]))
            and FVisualRows[j][k].OpacitySet
            and not IsNan(FVisualRows[j][k].Opacity) then
          begin
            Result[i].HasOpacity := True;
            Result[i].Opacity := FVisualRows[j][k].Opacity;
          end;
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

{ `encode` ON A SERIES' OWN DATA: `encode: {x: 1, y: 0}` has x read element
  1 of each item and y element 0, exactly as it would pick table columns.
  Only the plain coordinate columns -- a multi-value series places its own,
  and a row-index column reads no element at all. }
procedure TTyAdvanceChart.SeriesDataEncode(ASlot: Integer;
  var ADims: TTySeriesDimArray; out AEnc: TTySeriesEncode);
var
  coord: TTyCoordDimArray;
  k: Integer;
  plain: Boolean;
  node: TJSONObject;
  d: TJSONData;
begin
  plain := True;
  for k := 0 to High(ADims) do
    if (ADims[k].Coord <> '') or (ADims[k].SourceSlot > 0) then plain := False;
  coord := nil;
  SetLength(coord, Length(ADims));
  for k := 0 to High(ADims) do
  begin
    coord[k].Name := ADims[k].Name;
    coord[k].Ordinal := ADims[k].Kind = ddtOrdinal;
  end;
  { A NAME IN `encode` IS ONE OF THE SERIES' OWN `dimensions`. }
  AEnc := TyEncodeOf(FOption, FBindings[ASlot].SeriesIndex,
    TySeriesDimsSource(FOption, FBindings[ASlot].SeriesIndex), coord);
  if (not AEnc.Given) or not plain then Exit;
  { EVERY COORDINATE `encode` DOES NOT NAME takes the next element nobody
    holds, up to the width item 0 declares. }
  node := nil;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if d is TJSONObject then node := TJSONObject(d);
  d := nil;
  if node <> nil then d := node.Find('data');
  if (d <> nil) and (d is TJSONArray) then
    TyEncodeFillUnclaimed(AEnc, TySeriesDetectedDimCount(TJSONArray(d)));
  for k := 0 to High(ADims) do
    if (k <= High(AEnc.Columns)) and (AEnc.Columns[k] >= 0)
      and not ADims[k].FromRowIndex then
      ADims[k].SourceSlot := AEnc.Columns[k] + 1;
end;

procedure TTyAdvanceChart.ResolveTextDims(const AEnc: TTySeriesEncode;
  AStore: TTyDataStore);
var
  k, p, best: Integer;
  lab, tip: TTyIntegerArray;
  t: TTyDimType;

  procedure AddSorted(var A: TTyIntegerArray; AValue: Integer);
  var i: Integer;
  begin
    for i := 0 to High(A) do if A[i] = AValue then Exit;
    SetLength(A, Length(A) + 1);
    i := High(A);
    while (i > 0) and (A[i - 1] > AValue) do
    begin
      A[i] := A[i - 1];
      Dec(i);
    end;
    A[i] := AValue;
  end;

begin
  if AStore = nil then Exit;
  { THE LABEL: `encode.label` when it names anything; otherwise the LAST
    coordinate column, by position, whose type a label suits -- neither a
    category nor a time. Upstream's comment: y is what people look at. A
    category-category chart has none, and its label is empty. }
  lab := nil;
  if Length(AEnc.Labels) > 0 then lab := Copy(AEnc.Labels)
  else
  begin
    best := -1;
    for k := 0 to AStore.DimCount - 1 do
    begin
      p := AStore.RawDimPos(k);
      if p < 0 then Continue;
      t := AStore.DimType(k);
      if (t = ddtOrdinal) or (t = ddtTime) then Continue;
      if p > best then best := p;
    end;
    if best >= 0 then
    begin
      SetLength(lab, 1);
      lab[0] := best;
    end;
  end;
  { THE TOOLTIP: `encode.tooltip`; else the columns a type marks as its
    tooltip -- a candlestick's four values; else the label's. }
  tip := nil;
  if Length(AEnc.Tooltip) > 0 then tip := Copy(AEnc.Tooltip)
  else
  begin
    for k := 0 to AStore.DimCount - 1 do
      if (AStore.DimCoord(k) <> '') and (AStore.RawDimPos(k) >= 0) then
        AddSorted(tip, AStore.RawDimPos(k));
    if Length(tip) = 0 then tip := Copy(lab);
  end;
  AStore.SetLabelPositions(lab);
  AStore.SetTooltipPositions(tip);
end;

function TTyAdvanceChart.SeriesModelName(ASeriesIndex: Integer): string;
var
  d: TJSONData;
  node: TJSONObject;
begin
  Result := '';
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('name');
  { WRITTEN: as written, '' included -- only an unwritten name is replaced. }
  if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then
    Exit(SeriesNameOf(ASeriesIndex));
  Result := SeriesNameOf(ASeriesIndex);
  if Result = '' then Result := TyChartSeriesDefaultName(ASeriesIndex);
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

{ an itemStyle's borderRadius: a number, or zrender's array forms; nil for
  none }
function RadiiOfStyle(AStyle: TJSONData; APPI: Integer; out ARadii: TTyCornerRadii): Boolean;
var
  d: TJSONData;
  vals: array of Double;
  k: Integer;
begin
  ARadii := Default(TTyCornerRadii);
  Result := False;
  if (AStyle = nil) or (AStyle.JSONType <> jtObject) then Exit;
  d := TJSONObject(AStyle).Find('borderRadius');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  vals := nil;
  if d.JSONType = jtNumber then
  begin
    SetLength(vals, 1);
    vals[0] := d.AsFloat;
  end
  else if d.JSONType = jtArray then
  begin
    SetLength(vals, d.Count);
    for k := 0 to d.Count - 1 do
      if d.Items[k].JSONType = jtNumber then vals[k] := d.Items[k].AsFloat
      else vals[k] := 0;
  end
  else Exit;
  Result := True;
  if Length(vals) = 0 then Exit;
  TyZrRadii(vals, ARadii[0], ARadii[1], ARadii[2], ARadii[3]);
  for k := 0 to 3 do ARadii[k] := ARadii[k] * APPI / 96;
end;

{ each data item's own `label`, read over its series' spec, by raw row }
procedure TTyAdvanceChart.ItemLabelSpecs(ASeriesIndex: Integer; const ABase: TTyLabelSpec;
  out ASpecs: TTyLabelSpecArray; out AHas: TTyBoolArray);
var
  node, d, it, lb: TJSONData;
  k: Integer;
begin
  ASpecs := nil;
  AHas := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  SetLength(ASpecs, d.Count);
  SetLength(AHas, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    it := d.Items[k];
    if (it = nil) or (it.JSONType <> jtObject) then Continue;
    lb := TJSONObject(it).Find('label');
    if (lb = nil) or (lb.JSONType <> jtObject) then Continue;
    ASpecs[k] := TyLabelSpecOfNode(TJSONObject(lb), TJSONObject(node), ABase);
    AHas[k] := True;
  end;
end;

{ each data item's own itemStyle.borderRadius, by raw row }
procedure TTyAdvanceChart.HeatmapItemRadii(ASeriesIndex, APPI: Integer;
  out ARadii: TTyCornerRadiiArray; out AHas: TTyBoolArray);
var
  node, d, it: TJSONData;
  k: Integer;
begin
  ARadii := nil;
  AHas := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  SetLength(ARadii, d.Count);
  SetLength(AHas, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    it := d.Items[k];
    if (it <> nil) and (it.JSONType = jtObject) then
      AHas[k] := RadiiOfStyle(TJSONObject(it).Find('itemStyle'), APPI, ARadii[k]);
  end;
end;

{ WHERE A GRAPH'S NODES GO ON A CALENDAR, by raw index.

  UPSTREAM BUILDS A GRAPH'S DATA WITH PLAIN DIMENSION NAMES, so the node's
  date is not a time dimension: its type is GUESSED from the first node
  that decides it (guessOrdinal -- a finite number or numeric string says
  float, any other string but '-' says ordinal). An ordinal column keeps
  each date as written; a float one turns a date string into NaN.
  simpleLayout then places a node when ANY of its stored dimensions is a
  number -- and isNaN of a date string is true -- at the calendar's
  dataToPoint of the stored date, which the calendar parses itself. So a
  string-dated node with no numeric value is not placed at all, and after
  a first node dated by a timestamp every string-dated node is lost.
  [Batch 72] }
function TTyAdvanceChart.CalendarGraphPoints(ASeriesIndex: Integer;
  ACal: TTyCalendar): TTyPointFArray;
var
  node, d, it, arr, t0, v0: TJSONData;
  k, decided: Integer;
  floatTime, hasValue: Boolean;
  tNum, vNum, ms: Double;
  dv: TTyDataValue;

  function DateOf(AItem: TJSONData): TJSONData;
  begin
    Result := nil;
    arr := AItem;
    if (arr <> nil) and (arr.JSONType = jtObject) then arr := TJSONObject(arr).Find('value');
    if (arr <> nil) and (arr.JSONType = jtArray) and (arr.Count > 0) then
      Result := arr.Items[0];
  end;

  function NumOf(AData: TJSONData): Double;
  begin
    Result := NaN;
    if AData = nil then Exit;
    case AData.JSONType of
      jtNumber: Result := AData.AsFloat;
      jtString:
        if (AData.AsString <> '') and (AData.AsString <> '-') then
          Result := TyJsToNumber(AData.AsString);
    end;
  end;

begin
  Result := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then d := TJSONObject(node).Find('nodes');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  { the guess: the first decisive date among the first five }
  floatTime := True;
  decided := 0;
  for k := 0 to Min(d.Count, 5) - 1 do
  begin
    t0 := DateOf(d.Items[k]);
    if (t0 = nil) or (t0.JSONType = jtNull) then Continue;
    if (t0.JSONType = jtString) and ((t0.AsString = '-') or (t0.AsString = '')) then Continue;
    if (t0.JSONType = jtNumber) or ((t0.JSONType = jtString)
      and not IsNan(TyJsToNumber(t0.AsString)) and not IsInfinite(TyJsToNumber(t0.AsString))) then
      floatTime := True
    else
      floatTime := False;
    decided := 1;
    Break;
  end;
  if decided = 0 then floatTime := True;
  SetLength(Result, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    Result[k] := TyPointF(NaN, NaN);
    it := d.Items[k];
    t0 := DateOf(it);
    v0 := nil;
    if (arr <> nil) and (arr.JSONType = jtArray) and (arr.Count > 1) then v0 := arr.Items[1];
    vNum := NumOf(v0);
    { the stored date: a number either way; a string kept (ordinal) or not a
      number (float) }
    tNum := NaN;
    ms := NaN;
    if t0 <> nil then
    begin
      if t0.JSONType = jtNumber then
      begin
        tNum := t0.AsFloat;
        ms := tNum;
      end
      else if t0.JSONType = jtString then
      begin
        if floatTime then
        begin
          tNum := NumOf(t0);
          ms := tNum;
        end
        else
        begin
          dv := Default(TTyDataValue);
          dv.Kind := dvkText;
          dv.Text := t0.AsString;
          ms := ACal.ParseDate(dv);
        end;
      end;
    end;
    hasValue := not IsNan(tNum) or not IsNan(vNum);
    if not hasValue then Continue;
    Result[k] := ACal.DatePoint(ms, True);
  end;
end;

{ Each object data item's own symbol options over the series' spec. }
procedure TTyAdvanceChart.SymbolItems(ASeriesIndex: Integer;
  const ABase: TTySymbolSpec; out ASpecs: TTySymbolSpecArray; out AHas: TTyBoolArray);
var
  node, d, it: TJSONData;
  k: Integer;
begin
  ASpecs := nil;
  AHas := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  SetLength(ASpecs, d.Count);
  SetLength(AHas, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    it := d.Items[k];
    if (it = nil) or (it.JSONType <> jtObject) then Continue;
    AHas[k] := True;
    ASpecs[k] := TySymbolSpecOf(TJSONObject(it), ABase);
  end;
end;

{ AN effectScatter's rippleEffect and showEffectOn, upstream's defaults
  under them: ripples on render, three of them, filled. [Batch 71] }
procedure TTyAdvanceChart.RippleOf(ASlot: Integer; var AVisual: TTySeriesVisual);
var
  node, re, d: TJSONData;
  c: TTyChartColor;
begin
  AVisual.RippleShow := True;
  AVisual.RippleNumber := 3;
  AVisual.RippleFill := True;
  AVisual.RippleHasColor := False;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('showEffectOn');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> 'render') then
    AVisual.RippleShow := False;
  re := TJSONObject(node).Find('rippleEffect');
  if (re = nil) or (re.JSONType <> jtObject) then Exit;
  d := TJSONObject(re).Find('number');
  if (d <> nil) and (d.JSONType = jtNumber) then
    AVisual.RippleNumber := Max(0, Trunc(d.AsFloat));
  d := TJSONObject(re).Find('brushType');
  if (d <> nil) and (d.JSONType = jtString) then
    AVisual.RippleFill := d.AsString <> 'stroke';
  d := TJSONObject(re).Find('color');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
  begin
    AVisual.RippleHasColor := True;
    AVisual.RippleColor := c;
  end;
end;

{ a heatmap's itemStyle.borderRadius: a number, or zrender's array forms }
function TTyAdvanceChart.HeatmapRadii(ASeriesIndex, APPI: Integer): TTyCornerRadii;
var
  node, d: TJSONData;
  vals: array of Double;
  k: Integer;
begin
  Result := Default(TTyCornerRadii);
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('itemStyle');
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  d := TJSONObject(d).Find('borderRadius');
  if d = nil then Exit;
  vals := nil;
  if d.JSONType = jtNumber then
  begin
    SetLength(vals, 1);
    vals[0] := d.AsFloat;
  end
  else if d.JSONType = jtArray then
  begin
    SetLength(vals, d.Count);
    for k := 0 to d.Count - 1 do
      if d.Items[k].JSONType = jtNumber then vals[k] := d.Items[k].AsFloat
      else vals[k] := 0;
  end
  else Exit;
  if Length(vals) = 0 then Exit;
  TyZrRadii(vals, Result[0], Result[1], Result[2], Result[3]);
  for k := 0 to 3 do Result[k] := Result[k] * APPI / 96;
end;

function TTyAdvanceChart.LabelSpecFor(ASlot: Integer): TTyLabelSpec;
begin
  Result := LabelSpecFor(ASlot, '');
end;

{ THE THEME HALF OF A LABEL SPEC: fonts, the outside ink and the three
  inside bands, the ground -- everything but what the option says. }
function TTyAdvanceChart.LabelBaseFor(ASlot: Integer): TTyLabelSpec;
var
  outS, lightS, midS, darkS: TTyStyleSet;
begin
  Result := TyLabelSpecNone;
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight',
    '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '',
    []);
  Result.FontName := outS.FontName;
  Result.FontSizeLogical := ResolveFontSize(outS);
  Result.FontWeight := outS.FontWeight;
  Result.OutsideColour := TTyChartColor(outS.TextColor);
  Result.InsideColour[0] := TTyChartColor(lightS.TextColor);
  Result.InsideColour[1] := TTyChartColor(midS.TextColor);
  Result.InsideColour[2] := TTyChartColor(darkS.TextColor);
  LabelGround(Result.Ground, Result.GroundDark);
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
  LabelGround(base.Ground, base.GroundDark);
  if ASlot > High(FBindings) then Exit(base);
  { A LINE'S LABEL GOES ABOVE ITS POINT -- the one series type that declares
    a default position; every other falls to `inside`. [Revised in batch 47:
    a line's label sat inside its symbol.] }
  if FBindings[ASlot].SeriesType = 'line' then base.Position := tlpTop;
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
  LabelGround(Result.Ground, Result.GroundDark);
  { labelLine.lineStyle.width, PieSeries.ts:299 -- one logical pixel. }
  Result.LineWidthLogical := 1;
end;

function TTyAdvanceChart.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  Result := TTyPainterTextMeasurer.Create(APPI);
end;

function TTyAdvanceChart.BarColumnOf(ASeriesIndex: Integer): TTyBarColumn;
begin
  Result := Default(TTyBarColumn);
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FBarCols)) then
    Result := FBarCols[ASeriesIndex];
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
  ti: TTyTreeInk;
  si2: TTySunburstInk;
  specs: TTyLabelSpecArray;
  itemSpecs: TTyLabelSpecTable;
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
  { THE CALENDARS' TOO, before any series: at the same z a series is drawn
    at, the order is decided by z2 -- day cell 0, heatmap cell 1, month line
    20, names 30 -- and ties by insertion, components first. [Batch 69] }
  for i := 0 to High(FCalendars) do
    Inc(drawn, TyBuildCalendar(FCalendars[i], CalendarInk, AMeasurer, APPI, list));
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
          { ON A VIEW THE SYMBOLS ARE SCALED as zrender composes them: the
            view's overall scale times the compensation scale. }
          if (i <= High(FGraphs)) and (FGraphs[i] <> nil) then
            Inc(drawn, TyBuildGraphMarks(FBindings[i].SeriesIndex,
              FGraphSpecs[i], FGraphNodes[i], FGraphEdges[i],
              gi, FStores[i], list,
              FGraphs[i].OverallScaleX * FGraphNodeScale[i],
              FGraphs[i].OverallScaleY * FGraphNodeScale[i]))
          else
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
      { A TREE lays itself out in its box (SolveTrees) and draws its edges,
        its symbols and its label requests here -- BEFORE the expansion,
        whose per-row table carries the item -> leaves -> series chain.
        [Batch 73] }
      if FBindings[i].SeriesType = TyTreemapSeriesTypeName then
      begin
        if (i <= High(FTreemaps)) and FTreemaps[i].Valid then
        begin
          Inc(drawn, TyBuildTreemapMarks(FBindings[i].SeriesIndex, FTreemaps[i],
            FTreemapInks[i], list));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := FTreemapInks[i].Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := FTreemapInks[i].ItemLabels;
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TySunburstSeriesTypeName then
      begin
        if (i <= High(FSunbursts)) and FSunbursts[i].Valid then
        begin
          si2 := SunburstInk(i);
          Inc(drawn, TyBuildSunburstMarks(FBindings[i].SeriesIndex, FSunbursts[i], si2,
            FStores[i], list, APPI));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := si2.Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := si2.ItemLabels;
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TyTreeSeriesTypeName then
      begin
        if (i <= High(FTrees)) and FTrees[i].Valid then
        begin
          ti := TreeInk(i);
          Inc(drawn, TyBuildTreeMarks(FBindings[i].SeriesIndex, FTrees[i], ti,
            FStores[i], list, APPI));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := ti.Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := ti.ItemLabels;
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
            FunnelLabelInk, fv.Fills, FStores[i], SeriesModelName(FBindings[i].SeriesIndex),
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
            PieLabelInk, pv.Fills, FStores[i], SeriesModelName(FBindings[i].SeriesIndex),
            FStores[i].DimIndexOf(TyPieValueDim),
            FPieSpecs[i].PercentPrecision, AMeasurer, APPI, list));
        end;
        Continue;
      end;
      v := TySeriesVisual(TTyChartColor(SeriesColor(FBindings[i].SeriesIndex)));
      ApplyOptStyle(v, FBindings[i].SeriesIndex);
      ApplyVisualMaps(v, i, APPI);
      if i <= High(FBarCols) then v.Bar := FBarCols[i];
      v.Line := TyLineSpecOf(FOption, FBindings[i].SeriesIndex);
      { the area's base is smoothed as the series it stands on is }
      if (i <= High(FStacks)) and (FStacks[i].OnSlot >= 0)
        and (FStacks[i].OnSlot <= High(FBindings)) then
        v.Line.StackedOnSmooth := TyLineSpecOf(FOption,
          FBindings[FStacks[i].OnSlot].SeriesIndex).Smooth;
      v.Candle := CandleVisual(FBindings[i].SeriesIndex);
      { The thinning the AXIS settled on. When markers would crowd, upstream
        falls back to the category axis' own label interval -- which the layout
        pass already computed, so it is fetched rather than re-derived. }
      v.Line.LabelStep := LabelStepFor(FBindings[i].BaseAxis);
      v.Symbol := SymbolFor(i);
      if FBindings[i].SeriesType = 'effectScatter' then RippleOf(i, v);
      if (FBindings[i].SeriesType = 'scatter')
        or (FBindings[i].SeriesType = 'effectScatter') then
        SymbolItems(FBindings[i].SeriesIndex, v.Symbol, v.SymItems, v.SymItemHas);
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
      { `z` AND `z2`, the series default z UPSTREAM'S 2. [Batch 64: it was 0,
        on the grounds that nothing else here shared the scale. Markers do: a
        markArea sits at z 1, UNDER its series, and a markPoint or markLine at
        5, over it -- and only with the series at 2 do upstream's own numbers
        order them. The grid and the axes are still drawn outside the list.]

        READ RATHER THAN INVENTED because it decides a picture nobody can work
        around: `pictorialBar-body-fill` draws the same silhouette three times,
        a grey one last, and only `z: 10` on the two clipped series keeps the
        fill in front of it. Without this the chart is three grey bodies.

        zlevel IS NOT READ. It is a separate canvas upstream, not a deeper
        sort key, and pretending it is one would put a series in the right
        order for the wrong reason. }
      { [Batch 68: a LINE's default is 3, not 2 -- LineSeries.ts:161 --
        so a line over a bar of the same chart is drawn above it however
        the two are declared.] }
      if FBindings[i].SeriesType = 'line' then
        v.Z := SeriesIntIn(FBindings[i].SeriesIndex, 'z', 3)
      else
        v.Z := SeriesIntIn(FBindings[i].SeriesIndex, 'z', 2);
      v.Z2 := SeriesIntIn(FBindings[i].SeriesIndex, 'z2', 0);
      v.Label_ := LabelSpecFor(i);
      { A HEATMAP CELL is labelled with the third element of its raw row, and
        rounded by its series' itemStyle.borderRadius }
      v.HeatPadPx := 0.5 * APPI / 96;
      if FBindings[i].SeriesType = 'heatmap' then
      begin
        v.Label_.DefaultText := tldRawThird;
        v.Bar.Radii := HeatmapRadii(FBindings[i].SeriesIndex, APPI);
        HeatmapItemRadii(FBindings[i].SeriesIndex, APPI, v.HeatRadii, v.HeatHasRadii);
        ItemLabelSpecs(FBindings[i].SeriesIndex, v.Label_, v.ItemLabels, v.HasItemLabel);
        if Length(itemSpecs) <= FBindings[i].SeriesIndex then
          SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
        itemSpecs[FBindings[i].SeriesIndex] := v.ItemLabels;
      end
      else if (FBindings[i].SeriesType = 'scatter')
        or (FBindings[i].SeriesType = 'effectScatter') then
      begin
        { a symbol's own label over its series' [Batch 71] }
        ItemLabelSpecs(FBindings[i].SeriesIndex, v.Label_, v.ItemLabels, v.HasItemLabel);
        if Length(itemSpecs) <= FBindings[i].SeriesIndex then
          SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
        itemSpecs[FBindings[i].SeriesIndex] := v.ItemLabels;
      end;
      { `{c}` and the default text read the VALUE column -- whichever axis is
        not the base one. A label that read x on a bar chart would show the
        category ordinal, which is a number and looks like an answer. }
      v.LabelValueDim := -1;
      if (FBindings[i].ValueAxis <> nil) and (FStores[i] <> nil) then
        v.LabelValueDim := FStores[i].DimIndexOf(FBindings[i].ValueAxis.Dim);
      v.SeriesName := SeriesModelName(FBindings[i].SeriesIndex);
      if Length(specs) <= FBindings[i].SeriesIndex then
        SetLength(specs, FBindings[i].SeriesIndex + 1);
      specs[FBindings[i].SeriesIndex] := v.Label_;
      { ON A CALENDAR there is no cartesian to enter: the calendar is the
        coordinate system and only a heatmap draws on it yet. [Batch 70] }
      if FBindings[i].CalendarIndex >= 0 then
      begin
        if (FBindings[i].CalendarIndex <= High(FCalendars)) and (FStores[i] <> nil) then
        begin
          if FBindings[i].SeriesType = 'heatmap' then
            Inc(drawn, TyBuildCalendarHeatmap(FBindings[i],
              FCalendars[FBindings[i].CalendarIndex], FStores[i], v, list))
          else if (FBindings[i].SeriesType = 'scatter')
            or (FBindings[i].SeriesType = 'effectScatter') then
          begin
            { a symbol's default words are its value [Batch 71] }
            v.LabelValueDim := FStores[i].DimIndexOf(TyCalendarValueDim);
            Inc(drawn, TyBuildCalendarScatter(FBindings[i],
              FCalendars[FBindings[i].CalendarIndex], FStores[i], v, list));
          end;
        end;
        Continue;
      end;
      Inc(drawn, TyBuildSeriesMarks(FBindings[i], FStores[i],
        StackFor(i), v, list));
    end;
    { THE EXPANSION RUNS ONCE, HERE, AND NOTHING IS APPENDED AFTER IT. Each
      caption's geometry is frozen from its host at this moment and the list
      has no update path, so a mark added later would have no label and a mark
      moved later would leave its label behind. }
    if drawn > 0 then
      TyExpandLabels(list, specs, itemSpecs, AMeasurer, APPI);
    { AFTER THE LABELS, so a caption dims and rises with its node. }
    if drawn > 0 then ApplyGraphHover(list, APPI);
    { THE LEGEND GOES IN AFTER THE EXPANSION, and it is allowed to because
      its captions are ANSWERS rather than requests -- they arrive with a
      font and an anchor already on them, which is what the expansion exists
      to supply. A MARK appended here would silently lose its label. }
    { MARKERS arrive as answers too: their labels are placed by Line.ts's own
      table, not by the expansion }
    Inc(drawn, BuildMarkers(AMeasurer, list));
    Inc(drawn, BuildLegends(APPI, list));
    Inc(drawn, BuildVisualMaps(list));
    Inc(drawn, BuildDataZooms(list));
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
  { the marker is the ITEM's colour, so what a visualMap wrote on it too }
  ApplyVisualMaps(v, slot, 0);
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
  Result.SeriesName := SeriesModelName(ADatum.SeriesIndex);
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
  Result.Raw := st.RawItem(ADatum.DataIndex);

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
  { EACH VALUE'S RAW CELL, at the position its dimension was read from. }
  if Result.Raw.Shape = rshNone then Exit;
  SetLength(Result.RawCells, Length(cols));
  SetLength(Result.RawTypes, Length(cols));
  for i := 0 to High(cols) do
  begin
    if not TTyDataStore.RawCell(Result.Raw, st.RawDimPos(cols[i]),
      Result.RawCells[i]) then
      Result.RawCells[i] := Default(TTyDataValue);
    Result.RawTypes[i] := st.DimType(cols[i]);
  end;
end;

type
  { One series' tooltip cells, upstream's defaultSeriesFormatTooltip: the
    texts (inline, joined by two spaces, or one per sub-row), the sub-rows'
    names, and what `order` sorts the series by. Valid False: the store kept
    no raw item or chose no tooltip dimensions, and the caller keeps its own
    rule. }
  TTyTipCells = record
    Valid, MultiLine: Boolean;
    Texts, Names: TTyStringArray;
    Sort: TTyDataValue;
  end;

{ makeValueReadable with a type: a TIME is formatted
  `yyyy-MM-dd HH:mm:ss`, in UTC under `useUTC` -- a number as epoch ms, text
  through the date parser (local unless it says otherwise) -- and anything
  that is no date falls to the untyped rules. }
function TipReadable(const ACell: TTyDataValue; AType: TTyDimType;
  AUTC: Boolean): string;
var ms: Double; ok: Boolean;
begin
  if AType = ddtTime then
  begin
    ok := False;
    ms := NaN;
    case ACell.Kind of
      dvkNumber, dvkBool:
        if not (IsNan(ACell.Num) or IsInfinite(ACell.Num)) then
        begin
          ms := TyJsRound(ACell.Num);
          ok := True;
        end;
      dvkText:
        ok := TyParseDateMs(ACell.Text, ms, False);
    end;
    if ok and not IsNan(ms) then
      Exit(TyFormatTime(ms, '{yyyy}-{MM}-{dd} {HH}:{mm}:{ss}', AUTC));
    AType := ddtFloat;
  end;
  Result := TyReadableCell(ACell, AType);
end;

function TipCellsOf(AStore: TTyDataStore; ARow: Integer;
  AUTC: Boolean): TTyTipCells;
var
  raw: TTyRawItem;
  pos: TTyIntegerArray;
  n, i: Integer;
  info: TTyRawDimInfo;
  c: TTyDataValue;
  haveFirst: Boolean;

  procedure Put(APos: Integer; const ACell: TTyDataValue);
  var k: Integer;
  begin
    info := AStore.RawDimInfo(APos);
    k := Length(Result.Texts);
    SetLength(Result.Texts, k + 1);
    SetLength(Result.Names, k + 1);
    Result.Texts[k] := TipReadable(ACell, AStore.RawPosType(APos), AUTC);
    Result.Names[k] := '';
    if info.HasDisplay then Result.Names[k] := info.Display;
    if not haveFirst then
    begin
      Result.Sort := ACell;
      haveFirst := True;
    end;
  end;

begin
  Result := Default(TTyTipCells);
  if (AStore = nil) or not AStore.HasTooltipPositions then Exit;
  raw := AStore.RawItem(ARow);
  if raw.Shape = rshNone then Exit;
  Result.Valid := True;
  haveFirst := False;
  pos := AStore.TooltipPositions;
  n := Length(pos);
  if (n > 1) or ((raw.Shape = rshArray) and (n = 0)) then
  begin
    { SUB-ROWS WHEN ANY POSITION OF THE ITEM HAS A DISPLAY NAME -- every
      position the item has, shown or not; one a short item lacks does not
      count. }
    if raw.Shape = rshArray then
      for i := 0 to Min(High(raw.Cells), AStore.RawWidth - 1) do
      begin
        info := AStore.RawDimInfo(i);
        if info.HasDisplay then Result.MultiLine := True;
      end;
    if n > 0 then
      for i := 0 to n - 1 do
      begin
        if not TTyDataStore.RawCell(raw, pos[i], c) then c := Default(TTyDataValue);
        Put(pos[i], c);
      end
    else
      { NO TOOLTIP DIMENSION: every element the data has a dimension for. }
      for i := 0 to Min(High(raw.Cells), AStore.RawWidth - 1) do
        Put(i, raw.Cells[i]);
    { upstream sorts on the first INLINE value -- which a sub-row series has
      none of. }
    if Result.MultiLine then Result.Sort := Default(TTyDataValue);
  end
  else if n = 1 then
  begin
    if not TTyDataStore.RawCell(raw, pos[0], c) then c := Default(TTyDataValue);
    SetLength(Result.Texts, 1);
    SetLength(Result.Names, 1);
    Result.Texts[0] := TipReadable(c, AStore.RawPosType(pos[0]), AUTC);
    Result.Sort := c;
  end
  else
  begin
    { NOTHING TO CHOOSE FROM and no array: the value itself, untyped. }
    c := Default(TTyDataValue);
    if raw.Shape = rshScalar then c := raw.Scalar;
    SetLength(Result.Texts, 1);
    SetLength(Result.Names, 1);
    Result.Texts[0] := TipReadable(c, ddtFloat, AUTC);
    Result.Sort := c;
  end;
end;

function TipInline(const ACells: TTyTipCells): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(ACells.Texts) do
  begin
    if i > 0 then Result := Result + '  ';
    Result := Result + ACells.Texts[i];
  end;
end;

{ A sub-row's name as upstream prints it: makeValueReadable(name, 'ordinal'),
  so a dimension with no display name reads '-'. }
function TipRowName(const AName: string): string;
begin
  Result := TyReadableCell(TyDataText(AName), ddtOrdinal);
end;

function TTyAdvanceChart.RadarTooltip(ASlot, ARow: Integer;
  const AColor: TTyChartColor; const ASpec: TTyTooltipSpec): TTyTooltipBlock;
var
  st: TTyDataStore;
  spec: TTyRadarSpec;
  nm: string;
  j: Integer;
  v: Double;
begin
  st := FStores[ASlot];
  { HEADED BY THE ITEM, or the series when the item has no name -- the
    model's name, auto name included -- and never hidden: a blank reads '-'. }
  nm := st.GetItemName(ARow);
  if nm = '' then nm := SeriesModelName(FBindings[ASlot].SeriesIndex);
  nm := TipRowName(nm);
  Result := TTyTooltipBlock.CreateSection(nm, False);
  { A ROW PER INDICATOR, the PARSED value, sorted by `order` even in an item
    tooltip -- the radar's section asks for it. }
  spec := TyRadarSpecOf(FOption, FBindings[ASlot].RadarIndex);
  for j := 0 to High(spec.Indicators) do
  begin
    if j >= st.DimCount then Break;
    v := st.Get(j, ARow);
    Result.Add(TTyTooltipBlock.CreateNameValue(ttmSubItem, AColor,
      TipRowName(spec.Indicators[j].Name), False, TyTooltipValueText(v),
      False)).SortParam := v;
  end;
  if ASpec.HasOrder then Result.SortBlocks(ASpec.Order);
end;

function TTyAdvanceChart.TooltipContent(const ADatum: TTyChartDatumRef;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
var
  p: TTyChartCallbackParams;
  seriesName, inlineName, valueText: string;
  haveValue: Boolean;
  slot, i: Integer;
  cells: TTyTipCells;
begin
  Result := nil;
  p := TooltipParams(ADatum);
  { The DISPLAY name heads the section: an unnamed series has none. }
  seriesName := SeriesNameOf(ADatum.SeriesIndex);
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
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if (slot >= 0) and (FBindings[slot].RadarIndex >= 0) and (slot <= High(FStores))
    and (FStores[slot] <> nil) and (ADatum.DataIndex >= 0)
    and (ADatum.DataIndex < FStores[slot].Count) then
    Exit(RadarTooltip(slot, ADatum.DataIndex, p.Color, ASpec));
  cells := Default(TTyTipCells);
  if (slot >= 0) and (slot <= High(FStores)) and (ADatum.DataIndex >= 0)
    and (FStores[slot] <> nil) and (ADatum.DataIndex < FStores[slot].Count) then
    cells := TipCellsOf(FStores[slot], ADatum.DataIndex,
      (FOption <> nil) and FOption.GetBool('useUTC', False));
  if cells.Valid then
  begin
    { SUB-ROWS: the item's own row keeps its name and an EMPTY value -- a
      value cell with nothing in it, not no value cell. }
    if cells.MultiLine then valueText := '' else valueText := TipInline(cells);
    haveValue := True;
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
  { THE SUB-ROWS ARE SIBLINGS of the item row, after it, small-dotted in the
    series' colour. }
  if cells.MultiLine then
    for i := 0 to High(cells.Texts) do
      Result.Add(TTyTooltipBlock.CreateNameValue(ttmSubItem, p.Color,
        TipRowName(cells.Names[i]), False, cells.Texts[i], False));
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
  col: Integer;
begin
  ARows := nil;
  Result := False;
  if (AAxis = nil) or (ASlot < 0) or (ASlot > High(FStores)) then Exit;
  st := FStores[ASlot];
  if st = nil then Exit;
  col := st.DimIndexOf(AAxis.Dim);
  if col < 0 then Exit;
  { IN VIEW COORDINATE SPACE -- pixels, not data. The 0.5 a category axis is
    given is HALF A PIXEL, which after the value has already been rounded to a
    band centre means "the same band"; its purpose is to drop a series whose
    data is shorter than the axis, not to widen the search. ECharts 5.x
    compared in data space and 6.x changed it, so this is one to read rather
    than remember.

    THE SIDE TIE-BREAK. When the pointer falls exactly between two rows, the
    one at or before it wins -- otherwise both land in the list and every
    midpoint shows two rows of the same series. Rows with the SAME signed
    difference still accumulate, which is how two rows holding one value are
    both reported.

    [Batch 64: the loop moved to TyMkNearestRows, which the markers search a
    GIVEN column with, and it now measures in the axis' LOCAL coordinates as
    upstream's axis.dataToCoord does -- the grid's offset added to both sides
    of a difference could move a tie's last bit.] }
  ARows := TyMkNearestRows(st, col, AAxis, AValue, AMaxDistPx);
  Result := Length(ARows) > 0;
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
    { AND ON A CATEGORY AXIS, A CATEGORY: upstream's contain asks for one
      that exists, so a min or max reaching past the list leaves positions
      that take no pointer; and a blank axis takes none anywhere. }
    if AAxis.Scale.Blank then Exit;
    if isCat and not AAxis.Scale.Contain(value) then Exit;

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
    { CLOSED ON EVERY EDGE, as upstream's containPoint: a pointer on the
      plot's right or bottom edge still points at the last category
      [Revised in batch 44: this was the half-open cell rule.] }
    if (gb.CartesianCount = 0)
      or not gb.CartesianByIndex(0).ContainPoint(TyPointF(AX, AY)) then Continue;
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

procedure TTyAdvanceChart.LabelGround(out AGround: TTyChartColor;
  out ADark: Boolean);
var a, l: Double;
begin
  AGround := TTyChartColor(ActiveController.Model.ResolveStyle(GetStyleTypeKey,
    StyleClass, [tysNormal]).Background.Color);
  { zrender's lum with a background of ONE: what shows through a translucent
    ground counts as white. Dark under 0.4. }
  a := ((AGround shr 24) and $FF) / 255;
  l := TyLabelLuminance(AGround) + (1 - a);
  ADark := l < 0.4;
end;

function TTyAdvanceChart.IsGraphDatum(const ADatum: TTyChartDatumRef): Boolean;
var slot: Integer;
begin
  Result := False;
  if ADatum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  Result := (slot >= 0) and (slot <= High(FGraphLaidOut)) and FGraphLaidOut[slot];
end;

procedure TTyAdvanceChart.RestyleStatic;
begin
  { THE CACHE ONLY. The list stays valid: its geometry is what the pointer is
    still being tested against until the next paint rebuilds it. }
  if FStatic <> nil then FStatic.Drop;
  inherited Invalidate;
end;

function TTyAdvanceChart.GraphEmphasisOf(ASlot: Integer; AIsEdge: Boolean;
  AIndex: Integer): TTyChartEmphasisSpec;
var
  ser, d: TJSONData;
  arr: TJSONArray;
  sobj: TJSONObject;
  cat, raw: Integer;

  function ArrayOf(const AKey, AAlt: string): TJSONArray;
  var x: TJSONData;
  begin
    Result := nil;
    x := sobj.Find(AKey);
    if not (x is TJSONArray) then x := sobj.Find(AAlt);
    if x is TJSONArray then Result := TJSONArray(x);
  end;

begin
  Result := TyChartEmphasisDefault;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (ser is TJSONObject) then Exit;
  sobj := TJSONObject(ser);
  Result := TyChartReadEmphasis(ser);
  { THE OLD SPELLING, only where the new one is silent. Any value but null
    turns it on -- even `false`. }
  if not Result.HasFocus then
  begin
    d := sobj.Find('focusNodeAdjacency');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      Result.Focus := cfAdjacency;
      Result.HasFocus := True;
    end;
  end;
  if AIsEdge then
  begin
    if (AIndex < 0) or (AIndex > High(FGraphEdges[ASlot])) then Exit;
    arr := ArrayOf('links', 'edges');
    raw := FGraphEdges[ASlot][AIndex].Row;
    if (arr <> nil) and (raw >= 0) and (raw < arr.Count) then
      Result := TyChartMergeEmphasis(Result, TyChartReadEmphasis(arr.Items[raw]));
    Exit;
  end;
  if (AIndex < 0) or (AIndex > High(FGraphNodes[ASlot])) then Exit;
  { THE CATEGORY IS A MODEL PARENT of its nodes. }
  cat := FGraphNodes[ASlot][AIndex].ModelCategory;
  arr := ArrayOf('categories', 'categories');
  if (arr <> nil) and (cat >= 0) and (cat < arr.Count) then
    Result := TyChartMergeEmphasis(Result, TyChartReadEmphasis(arr.Items[cat]));
  arr := ArrayOf('data', 'nodes');
  raw := FGraphNodes[ASlot][AIndex].RawRow;
  if (arr <> nil) and (raw >= 0) and (raw < arr.Count) then
    Result := TyChartMergeEmphasis(Result, TyChartReadEmphasis(arr.Items[raw]));
end;

procedure TTyAdvanceChart.ApplyGraphHover(AList: TTyPaintList; APPI: Integer);
var
  hs, t, i, k, hover, si: Integer;
  hoverEdge, blur, sameCs: Boolean;
  spec, es: TTyChartEmphasisSpec;
  nodeSet, edgeSet: TTyIntegerArray;
  nstates, estates: array of TTyGraphHoverStateArray;
  el: TTyChartElement;
  st: TTyGraphHoverState;
  isCaption: Boolean;
  normal, res: TTyChartStyle;
  states: TTyChartStateList;
  ratio: Double;
  edgeStroke: TTyChartColor;
  edgeAlpha: Double;

  function NodeByRow(ASlot, ARow: Integer): Integer;
  var j: Integer;
  begin
    for j := 0 to High(FGraphNodes[ASlot]) do
      if FGraphNodes[ASlot][j].Row = ARow then Exit(j);
    Result := -1;
  end;

  function EdgeByRow(ASlot, ARow: Integer): Integer;
  var j: Integer;
  begin
    for j := 0 to High(FGraphEdges[ASlot]) do
      if FGraphEdges[ASlot][j].Row = ARow then Exit(j);
    Result := -1;
  end;

  { The blurred opacity: the declared one, or the normal one times a tenth
    -- except on an element whose emphasis is DISABLED, which upstream never
    gives the computed blur style: only a declared opacity reaches it. }
  function Blurred(ADeclared, ANormal: Double; ADisabled: Boolean): Double;
  begin
    if not IsNan(ADeclared) then Result := ADeclared
    else if ADisabled then Result := ANormal
    else Result := ANormal * TyChartBlurOpacityFactor;
  end;

begin
  if (AList = nil) or not TyChartDatumValid(FTipDatum) then Exit;
  if not IsGraphDatum(FTipDatum) then Exit;
  hs := SlotOfSeries(FTipDatum.SeriesIndex);
  hoverEdge := FTipDatum.IsEdge;
  if hoverEdge then hover := EdgeByRow(hs, FTipDatum.DataIndex)
  else hover := NodeByRow(hs, FTipDatum.DataIndex);
  if hover < 0 then Exit;
  spec := GraphEmphasisOf(hs, hoverEdge, hover);
  { A DISABLED EMPHASIS IS NO HOVER AT ALL: nothing rises and nothing
    dims. }
  if spec.Disabled then Exit;
  TyGraphFocusSets(FGraphNodes[hs], FGraphEdges[hs], hoverEdge, hover,
    nodeSet, edgeSet);

  { EVERY GRAPH'S STATES: blurred when the scope reaches it, the sets spared
    under adjacency -- by index, in another graph too. }
  SetLength(nstates, Length(FBindings));
  SetLength(estates, Length(FBindings));
  for t := 0 to High(FBindings) do
  begin
    if (t > High(FGraphLaidOut)) or not FGraphLaidOut[t] then Continue;
    { A graph on a view owns its view; graphs on axes share a grid when they
      share a cartesian. }
    sameCs := (t = hs) or ((FGraphs[t] = nil) and (FGraphs[hs] = nil)
      and (FBindings[t].Cart <> nil) and (FBindings[t].Cart = FBindings[hs].Cart));
    blur := TyChartShouldBlur(spec.Focus, spec.BlurScope, t = hs, sameCs);
    TyGraphBlurStates(Length(FGraphNodes[t]), Length(FGraphEdges[t]), blur,
      spec.Focus = cfAdjacency, nodeSet, edgeSet, nstates[t], estates[t]);
  end;
  if hoverEdge then estates[hs][hover] := ghsEmphasis
  else nstates[hs][hover] := ghsEmphasis;

  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    si := el.Datum.SeriesIndex;
    if si < 0 then Continue;
    t := SlotOfSeries(si);
    if (t < 0) or (t > High(nstates)) or (Length(nstates[t]) + Length(estates[t]) = 0)
    then Continue;
    if el.Datum.IsEdge then k := EdgeByRow(t, el.Datum.DataIndex)
    else k := NodeByRow(t, el.Datum.DataIndex);
    if k < 0 then Continue;
    if el.Datum.IsEdge then st := estates[t][k] else st := nstates[t][k];
    if st = ghsNormal then Continue;
    es := GraphEmphasisOf(t, el.Datum.IsEdge, k);
    isCaption := el.Caption.FontSizeLogical > 0;

    if st = ghsBlur then
    begin
      { DIMMED, and nothing else: colour, size and order stay. }
      if isCaption then
        el.Style.Alpha := Blurred(es.BlurLabelOpacity, el.Style.Alpha, es.Disabled)
      else if el.Datum.IsEdge then
        el.Style.Alpha := Blurred(es.BlurLineOpacity, el.Style.Alpha, es.Disabled)
      else
        el.Style.Alpha := Blurred(es.BlurItemOpacity, el.Style.Alpha, es.Disabled);
      AList.SetElement(i, el);
      Continue;
    end;

    { ---- emphasis ---- }
    states := Default(TTyChartStateList);
    states.Emphasis := True;
    if isCaption then
    begin
      { THE WORDS RISE WITH THEIR NODE, so it does not cover them -- in the
        ink the lifted node calls for. }
      el.Z2 := el.Z2 + TyChartEmphasisZ2Lift;
      if el.Caption.HasEmph then
      begin
        el.Caption.Colour := el.Caption.EmphColour;
        el.Caption.StrokeColour := el.Caption.EmphStrokeColour;
        el.Caption.StrokeWidthLogical := el.Caption.EmphStrokeWidthLogical;
      end;
    end
    else if el.Datum.IsEdge then
    begin
      { A LINE READS ONLY emphasis.lineStyle: its stroke lifted unless one is
        declared, and a width and an opacity only if declared. Its
        arrowheads take the stroke it ends up with as their fill. }
      normal := TyChartNoStyle;
      if el.Shape.Kind = cskPolyline then
        TyChartSetColor(normal, cskStroke, el.Style.StrokeColor)
      else
        TyChartSetColor(normal, cskStroke, el.Style.FillColor);
      TyChartSetNum(normal, cskOpacity, el.Style.Alpha);
      res := TyChartResolveStyle(normal, es.Line, states);
      edgeStroke := res.Color[cskStroke];
      edgeAlpha := el.Style.Alpha;
      if TyChartStyleHas(res, cskOpacity) then edgeAlpha := res.Num[cskOpacity];
      if el.Shape.Kind = cskPolyline then
      begin
        el.Style.StrokeColor := edgeStroke;
        if TyChartStyleHas(es.Line, cskLineWidth) then
          el.Style.StrokeWidthLogical := es.Line.Num[cskLineWidth];
      end
      else
      begin
        el.Style.HasFill := True;
        el.Style.FillColor := edgeStroke;
      end;
      el.Style.Alpha := edgeAlpha;
      { UP BY TEN -- above the other edges, still under every node. }
      el.Z2 := el.Z2 + TyChartEmphasisZ2Lift;
    end
    else
    begin
      { A NODE READS ONLY emphasis.itemStyle: its fill lifted unless one is
        declared, a border if declared, and the symbol grown about its
        centre. }
      normal := TyChartNoStyle;
      if el.Style.HasFill then TyChartSetColor(normal, cskFill, el.Style.FillColor);
      if el.Style.StrokeColor <> 0 then
        TyChartSetColor(normal, cskStroke, el.Style.StrokeColor);
      if el.Style.StrokeWidthLogical > 0 then
        TyChartSetNum(normal, cskLineWidth, el.Style.StrokeWidthLogical);
      TyChartSetNum(normal, cskOpacity, el.Style.Alpha);
      res := TyChartResolveStyle(normal, es.Item, states);
      if TyChartStyleHas(res, cskFill) then
      begin
        el.Style.HasFill := True;
        el.Style.FillColor := res.Color[cskFill];
      end;
      if TyChartStyleHas(res, cskStroke) then el.Style.StrokeColor := res.Color[cskStroke];
      if TyChartStyleHas(res, cskLineWidth) then
        el.Style.StrokeWidthLogical := res.Num[cskLineWidth];
      if TyChartStyleHas(res, cskOpacity) then el.Style.Alpha := res.Num[cskOpacity];
      if el.Shape.Kind in [cskCircle, cskEllipse] then
        ratio := TyChartSymbolScaleRatio(es, el.Shape.R1)
      else
        ratio := TyChartSymbolScaleRatio(es,
          (el.Shape.Bounds.Bottom - el.Shape.Bounds.Top) / 2);
      if ratio <> 1 then el.Shape := TyScaleShape(el.Shape, ratio);
      el.Z2 := el.Z2 + TyChartEmphasisZ2Lift;
    end;
    AList.SetElement(i, el);
  end;
  if APPI < 0 then ;
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
  var j: Integer; cap: TTyChartElement;
  begin
    if AIndex < 0 then Exit;
    { A GRAPH'S HOVER IS IN THE STATIC LAYER ALREADY -- see
      ApplyGraphHover. }
    if IsGraphDatum(FPaintList.Element(AIndex).Datum) then Exit;
    if not EmphasiseElement(AIndex, APPI, el) then Exit;
    { THE CAPTION IS DROPPED. A mark's words were expanded once, into a
      SEPARATE element, and the copy drawn here carries the request rather
      than the answer -- rendering it would draw unplaced text at the origin. }
    el.Caption := Default(TTyElementCaption);
    list.Add(el);
    { AND ITS ANSWER IS DRAWN AGAIN OVER IT, in the hover's ink -- otherwise
      the lifted host covers its own inside label. [Revised in batch 47.] }
    for j := 0 to FPaintList.Count - 1 do
    begin
      cap := FPaintList.Element(j);
      if (cap.Caption.FontSizeLogical <= 0) or not cap.Caption.HasEmph then
        Continue;
      if (cap.Datum.SeriesIndex <> el.Datum.SeriesIndex)
        or (cap.Datum.DataIndex <> el.Datum.DataIndex)
        or (cap.Datum.IsEdge <> el.Datum.IsEdge) then Continue;
      cap.Caption.Colour := cap.Caption.EmphColour;
      cap.Caption.StrokeColour := cap.Caption.EmphStrokeColour;
      cap.Caption.StrokeWidthLogical := cap.Caption.EmphStrokeWidthLogical;
      cap.Z2 := el.Z2 + 1;
      list.Add(cap);
    end;
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
    { CLAMPED, as upstream's pointer asks the axis: dataToCoord(value, true)
      hands the end back as itself at or past it }
    at := hit.Axis.DataToCoord(pv, True);
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
    { makeValueReadable ON THE RAW CELL: 'abc' is 'abc', true is true,
      '0x10' is '0x10' -- where the parsed Double would say '-' or 1. A
      time is still the number's (its formatting is local time). }
    if (i <= High(AParams.RawCells)) and (i <= High(AParams.RawTypes))
      and (AParams.RawTypes[i] <> ddtTime) then
      Result := Result + TyReadableCell(AParams.RawCells[i], AParams.RawTypes[i])
    else
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
  rows, j: Integer;
  cells: TTyTipCells;
  sub: TTyTooltipBlock;
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
      cells := TipCellsOf(FStores[slot], row,
        (FOption <> nil) and FOption.GetBool('useUTC', False));
      if not cells.Valid then valueText := ValuesText(p)
      else if cells.MultiLine then valueText := ''
      else valueText := TipInline(cells);
      { EACH SERIES IS ITS OWN HEADERLESS SECTION -- its row and its sub-rows
        together, so `order` and `seriesDesc` move them as one. It is what
        `order` sorts, keyed on the series' first inline RAW value. }
      sub := TTyTooltipBlock.CreateSection('', True);
      if cells.Valid then sub.SortCell := cells.Sort
      else sub.SortParam := p.Values[0];
      { UNDER AN AXIS TRIGGER THE INLINE NAME IS THE SERIES NAME, not the item
        name -- upstream passes `multipleSeries = true`, which both suppresses
        the per-series header AND switches the name. The item name is already
        the section's header, so repeating it on every row would say the
        category once per series. It is the DISPLAY name: an unnamed series'
        row has none. }
      sub.Add(TTyTooltipBlock.CreateNameValue(ttmItem, p.Color,
        SeriesNameOf(FBindings[slot].SeriesIndex), False, valueText, False));
      if cells.MultiLine then
        for j := 0 to High(cells.Texts) do
          sub.Add(TTyTooltipBlock.CreateNameValue(ttmSubItem, p.Color,
            TipRowName(cells.Names[j]), False, cells.Texts[j], False));
      section.Add(sub);
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
            TyInkText(lines[i].Runs[j].Text), lines[i].Runs[j].FontName,
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
  wasOn, graphChanged: Boolean;
  dx, dy: Double;
begin
  graphChanged := False;
  inherited MouseMove(Shift, X, Y);
  if csDesigning in ComponentState then Exit;
  { THE DRAG FIRST: the delta from where the pointer was last, wherever it is
    now -- a drag that leaves the control keeps panning. }
  if FRoamSeries >= 0 then
  begin
    dx := X - FRoamX;
    dy := Y - FRoamY;
    FRoamX := X;
    FRoamY := Y;
    GraphRoam(FRoamSeries, dx, dy);
  end;
  DataZoomPointer(dpMove, X, Y, Shift, 0);
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
  { A GRAPH'S HOVER LIVES IN THE STATIC LAYER, so a change of it -- onto a
    graph element, off one, or from one to another -- draws that layer
    again. A label's hit is its node's: they share the datum. }
  if (IsGraphDatum(d) or IsGraphDatum(FTipDatum))
    and ((d.SeriesIndex <> FTipDatum.SeriesIndex)
      or (d.DataIndex <> FTipDatum.DataIndex) or (d.IsEdge <> FTipDatum.IsEdge)) then
    graphChanged := True;
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
  if graphChanged then RestyleStatic
  else if wasOn or TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0) then
    InvalidateFrame;
end;

procedure TTyAdvanceChart.MouseLeave;
var wasOn, wasGraph: Boolean;
begin
  wasOn := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0);
  wasGraph := IsGraphDatum(FTipDatum);
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  FTipHits := nil;
  { the pointer left the canvas: a mouseout to what it was over }
  if FDzHover.Kind <> dtkNone then
  begin
    DzMouseOut(FDzHover);
    FDzHover := Default(TTyDzTarget);
    DzViewUpdate;
  end;
  { INHERITED LAST. The base class ends in PointerStateChanged, which this
    control answers with a repaint -- and a repaint before the hover was
    cleared would draw the tooltip one more time on the way out. }
  inherited MouseLeave;
  if wasGraph then RestyleStatic
  else if wasOn then InvalidateFrame;
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
    measurer := NewTextMeasurer(APPI);
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
  measurer := NewTextMeasurer(APPI);
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
