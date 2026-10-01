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
  tyControls.AdvChart.Types, tyControls.AdvChart.Option, tyControls.AdvChart.OptionMerge,
  tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Time,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
  tyControls.AdvChart.Measure, tyControls.AdvChart.Handlers, tyControls.FontUnits,
  tyControls.AdvChart.Events, tyControls.AdvChart.States,
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
  tyControls.AdvChart.Sankey,
  tyControls.AdvChart.Graph,
  tyControls.AdvChart.Title,
  tyControls.AdvChart.Labels, tyControls.AdvChart.LabelOpt,
  tyControls.AdvChart.PieLabel, tyControls.AdvChart.Legend,
  tyControls.AdvChart.Tooltip, tyControls.AdvChart.AxisPointer,
  tyControls.AdvChart.Dataset,
  tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt,
  tyControls.AdvChart.AnimView,
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
  { WHICH OF THE ROOT textStyle'S PROPERTIES A TEXT TAKES. Upstream falls back
    to it property by property, and only where the component has no default
    of its own: an axis label's default 12px shuts out a root fontSize but not
    a root fontWeight, a legend's default colour shuts out a root colour.
    [Batch 83] }
  TTyTextPickItem = (ttpSize, ttpWeight, ttpFamily, ttpColour);
  TTyTextPick = set of TTyTextPickItem;
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

  { A TREE NODE EXPANDED OR COLLAPSED, as upstream's
    `treeexpandandcollapse` action reports it: from a click and from the API
    alike. [Batch 81] }
  TTyTreeToggleEvent = procedure(Sender: TObject; ASeriesIndex, ADataIndex: Integer) of object;

  { WHAT THE POINTER IS OVER, as the chart's mouse events see it [Batch 84]:
    an identity (0 is nothing; the same thing answers the same identity from
    one move to the next, which is what decides out and over), whether it
    carries data -- upstream emits a chart event only for an element with
    ECData -- and, when it does, the params and the model a query is matched
    against. }
  TTyChartEventTarget = record
    Id: Int64;
    HasData: Boolean;
    Params: TTyChartCallbackParams;
    Model: TTyEventModel;
    { THE ELEMENT'S HOVER DISPATCHER and select dispatcher [Batch 88]: 1 a
      data item (HdSeries, HdRow its inner row, HdEdge a graph link), 2 the
      whole-series element of a line (its polyline), 3 a marker (HdSeries
      its host, HdRow its place in the marker's data: a select dispatcher
      only), 0 nothing that has states. A label answers for its host.
      [Batch 93] 4 a legend item: HdSeries the legend, HdRow the item, HdName
      its name, HdLegendSeries whether a series wears that name (the item's
      handlers name the series) or not (they name the data).
      [Batch 98] 5 a legend's selector button, 6 its pager's page button:
      HdSeries the legend, HdRow the button (the pager's 0 previous, 1
      next). Neither carries data. }
    HdKind: Integer;
    HdSeries, HdRow: Integer;
    HdEdge: Boolean;
    HdName: string;
    HdLegendSeries: Boolean;
  end;

  { WHAT THE STATE MACHINE KEEPS FOR ONE SERIES [Batch 88]: which of the
    port's builders it speaks for, every data item's elements by RAW index
    (a filter does not move them), and a line's polyline and area. The
    element indices are the last build's. }
  { [Batch 90] a heatmap's cell (sskRect), a funnel's band, a candlestick
    (its body the host, the wicks of the same path FOLLOWERS that take the
    host's changes), a pictorial bar (its glyphs, the first the host, the
    rest PARTS with states of their own) }
  TTyStKind = (sskNone, sskBar, sskPie, sskSymbol, sskRect, sskFunnel,
    sskCandle, sskPictorial, sskSunburst);
  TTyStNodeArray = array of TJSONObject;
  TTyStSeries = record
    Kind: TTyStKind;
    IsLine: Boolean;
    Rows: array of TTyStItem;
    HostIdx, LabelIdx, GuideIdx: TTyIntegerArray;
    { by raw index: more elements of the item -- drawn from the host's
      values (FollowIdx) or with states of their own (PartIdx) [Batch 90] }
    FollowIdx, PartIdx: array of TTyIntegerArray;
    Run, Area: TTyStItem;
    RunIdx, AreaIdx: TTyIntegerArray;
    { getComponentStates(series).isBlured: blurSeries reached it, so the next
      allLeaveBlur walks it [Batch 90] }
    IsBlured: Boolean;
  end;

  TTyChartEventReg = record
    Id: Integer;
    EventType: string;
    Query: TTyEventQuery;
    Handler: TTyChartEventHandler;
  end;

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

  { WHEN THE CHART PLAYS ITS ENTER ANIMATIONS. [Batch 89]

    camAuto, the default: when it paints onto a window on screen -- the
    first window paint after an option is set. A render that is not a
    window's (RenderTo, SaveToPng, the designer, a headless test) draws the
    finished picture and leaves the animation for the window. Upstream
    animates on every setOption wherever it is; a control that also
    exports and is rendered headless has two kinds of render, and only one
    of them has a viewer to watch a tween.

    camAlways: every render that builds the series after an option is set
    animates, headless or not -- what a test of the timelines uses.

    camOff: never. The option's own `animation: false` (root or series)
    switches a chart off in every mode. }
  TTyChartAnimationMode = (camAuto, camAlways, camOff);

  { UPSTREAM'S setOption(option, opts) [Batch 97].
    NotMerge: replace the option whole (a new set of models).
    ReplaceMerge: the main types whose models only an id keeps -- the rest
      are removed and leave index holes; ignored by a notMerge and by the
      first setOption, as upstream's initBase ignores it.
    LazyUpdate: the update -- and its `updated` event -- waits for the next
      render; the merge itself happens now, as upstream's does.
    Silent: no `updated` event for this update. }
  TTySetOptionOpts = record
    NotMerge, LazyUpdate, Silent: Boolean;
    ReplaceMerge: TTyStringArray;
  end;

{ The options object as JSON text -- `{notMerge, replaceMerge, lazyUpdate,
  silent}`, replaceMerge a main type or an array of them, the flags read for
  their JavaScript truthiness, other keys (`transition`) ignored. '' is no
  options. False when the text is no object. }
function TySetOptionOptsOf(const AJson: string; out AOpts: TTySetOptionOpts): Boolean;

type
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
    { THE SANKEYS and their inks, per slot. [Batch 79] }
    FSankeys: array of TTySankeySolved;
    FSankeyInks: array of TTySankeyInk;
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
    { EACH TREE'S TOGGLES, by SERIES index and row, outside the build: a
      click survives a resize and a relayout and goes only with the option.
      [Batch 81] }
    FTreeToggled: array of TTyBoolArray;
    FOnTreeToggle: TTyTreeToggleEvent;
    { THE CHART'S MOUSE EVENTS [Batch 84]: the registrations in the order
      they were made, the published catch-all, and zrender's bookkeeping --
      what is hovered, what the last press and release were on, and the press
      point a click is judged against (cleared by the click it makes). }
    FEventRegs: array of TTyChartEventReg;
    FEventNextId: Integer;
    FOnChartEvent: TTyChartEventHandler;
    FEvHover: TTyChartEventTarget;
    { ELEMENT STATES AND THE SELECTION [Batch 88]: each series' selection
      model (by series index, made at its first build and kept until the
      option changes), the state machine's records, the layout generation
      they were last re-rendered at, whether a flag changed since the last
      frame applied them, and the highlightKey digits in order of first use. }
    FSel: array of TTySelModel;
    FSelInit: TTyBoolArray;
    FSt: array of TTyStSeries;
    FStGen, FStBuiltGen: Integer;
    FStRerender, FStDirty: Boolean;
    FHighlightKeys: TTyStringArray;
    FEvDownId, FEvUpId: Int64;
    FEvDownArmed: Boolean;
    FEvDownX, FEvDownY: Integer;
    FEvLastX, FEvLastY: Integer;
    { EACH TREE'S VIEW, by slot and owned (rebuilt by every layout), with its
      options read as a graph's; WHAT ITS ROAM LEFT and THE BOX IT LAST HAD,
      by series index and outside the build -- a roam survives a relayout,
      and a view with no extent on an axis takes that axis from the box
      before. [Batch 82] }
    FTreeViews: array of TTyGraphView;
    FTreeSpecs: array of TTyGraphSpec;
    FTreeRoam: array of TTyGraphRoamState;
    FTreeBox: array of TTyXYWH;
    FTreeBoxHas: TTyBoolArray;
    FOnTreeRoam: TTyGraphRoamEvent;
    { THE PRESS a click is judged against: zrender's -- the same target
      (datum, and caption or not) within 4 px }
    FPressArmed, FPressCaption: Boolean;
    FPressDatum: TTyChartDatumRef;
    FPressX, FPressY: Integer;
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
    { each title's two fonts as laid out and drawn [Batch 83] }
    FTitleFonts: array of array[0..1] of TTyTitleFont;
    { each line's text block, where its style makes it one: the pieces about
      the line's anchor [Batch 86] }
    FTitleRt: array of array[0..1] of TTyRtDrawn;
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
    { THE LEGEND MODELS HAVE BEEN LOADED from this option [Batch 93]: init's
      `selected ||= {}` and optionUpdated's single-mode pick ran -- once per
      option; after it the map is what the actions made of it. }
    FLegendLoaded: Boolean;
    { [Batch 98] THE SELECTOR BUTTON UNDER THE POINTER, in its hovered ink:
      legend and button, -1 none. A re-render of the legend makes new
      buttons in no state, so every relayout drops it -- and the pointer
      resting on the new one is no new mouseover (zrender #6198). }
    FLegendSelHoverLegend, FLegendSelHoverIdx: Integer;
    { [Batch 98] THE SCROLL'S TWEEN: per legend, a proxy holding the content
      group's position (x, y), on a driver of its own -- the legend is drawn
      in the static layer, so a tick redraws that layer }
    FLegAnim: TTyAnimation;
    FLegProxies: array of TTyChartAnimProxy;
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
    { THE ENTER ANIMATION [Batch 89]. One driver per chart; the proxies the
      animated elements read, keyed so they outlive a rebuilt list; each
      list element's proxy by insertion index; the frame the dynamic layer
      draws; the clock (NaN: the machine's; a number: a test's); the 16 ms
      timer; whether an option waits for the render that animates it;
      whether the series are in motion -- drawn in the dynamic layer, not
      the static one -- and whether the paint in progress is a window's. }
    FAnim: TTyAnimation;
    FAnimSet: TTyChartAnimSet;
    FAnimBind: TTyChartAnimProxyArray;
    { THE STATE PROXIES by insertion index [Batch 94, AN3b]: the proxy each
      state element's states run on -- its role's, or one of the states'
      own; whether this build's states run through them; and an option
      armed this build, whose synchronous first step waits for them }
    FAnimStBind: TTyChartAnimProxyArray;
    FStProxied: Boolean;
    FAnimFlush: Boolean;
    FAnimFrame: TTyPaintList;
    FAnimNow: Double;
    FAnimTimer: TTimer;
    FAnimMode: TTyChartAnimationMode;
    FAnimPending: Boolean;
    FAnimLive: Boolean;
    { ONLY LOOPS LEFT (an effectScatter's ripples): the static layer takes
      everything but them and their symbols, the dynamic layer only those
      [Batch 92, AN4] }
    FAnimContinuous: Boolean;
    FAnimSplit: TTyPaintList;
    { THE AXIS POINTER'S SLIDE [Batch 92, AN4]: a driver of its own, so a
      pointer moving never takes the series out of the static layer; one
      proxy per axis (its role the axis' key) }
    FPtrAnim: TTyAnimation;
    FPtrProxies: TFPList;
    FAnimWindow: Boolean;
    { THE RENDER BEFORE AN UPDATE [Batch 90]: what the last list held and
      its series' keys, taken when a new option is laid out and kept until
      the render that animates it; that render's build, kept alive for its
      coordinate systems (a point added to a line starts where the old axes
      put it); and the old option's series view keys, read before the option
      text is replaced. }
    FAnimPrev: TTyChartAnimPrev;
    FAnimOldBuild: TTyChartBuild;
    FAnimOldBindings: TTySeriesBindingArray;
    FAnimOldViewKeys: TTyStringArray;
    { THE SERIES WHOSE MODEL replaceMerge MADE BRAND NEW since the old keys
      were taken: upstream's __requireNewView, a new view whatever the id
      [Batch 97]. Consumed by the update that pairs the views. }
    FAnimFresh: array of Boolean;
    { A LAZY setOption's update waits for the next render, and its
      `updated` event with it [Batch 97] }
    FLazyPending, FLazySilent: Boolean;
    FPaintList: TTyPaintList;
    { The PPI the list was built at. The hit test scales HitSlopLogical by it,
      so a list built for 96 and interrogated at 192 would give targets half
      the size the marks are drawn at. }
    FPaintListPPI: Integer;
    FPaintListValid: Boolean;
    procedure SetOptionText(const AValue: string);
    function GetOptionText: string;
    { ---- setOption [Batch 95] ---- }
    { the notMerge setOption: the text is the option, every model is new }
    procedure ApplyNotMerge(const AValue: string);
    { the merge setOption, AReplace's main types in replaceMerge mode }
    function DoMerge(const AJson: string; const AReplace: array of string): Boolean;
    { what every setOption ends with: the `updated` event now, or with the
      next render when lazy [Batch 97] }
    procedure AfterSetOption(ALazy, ASilent: Boolean);
    procedure EmitUpdated;
    { a lazy update done by the render that just laid out }
    procedure LazyUpdateDone;
    { a merge writing back what the control keeps outside the tree and
      upstream keeps in the model's option: an action's dataZoom window,
      when the merge writes that dataZoom's range }
    procedure MergeBefore(const AMainType: string; AIndex: Integer;
      ANode, ANew: TJSONObject);
    { what a merge keeps of the state outside the tree: by series and
      dataZoom index, for the models that survived it }
    procedure MergeKeepStates(const AReport: TTyMergeReport);
    { a kept roam's centre or zoom, where the merge wrote it: the option's }
    procedure MergeRoamOverride(var AState: TTyGraphRoamState; ASeries: Integer;
      ANew: TJSONObject);
    { ---- the enter animation [Batch 89] ---- }
    function AnimClock: Double;
    function AnimAllowed: Boolean;
    { every proxy dropped: the layout moved, so the picture is the layout's }
    procedure AnimDropAll;
    { after a list is built: arm a waiting option's enter animations (and
      take the synchronous first step, upstream's flush), then find every
      element's proxy }
    procedure AnimAfterBuild;
    { the synchronous first step of an option armed this build, after the
      states had their say (upstream's updateStates runs inside the render,
      before setOption's flush) [Batch 94] }
    procedure AnimFlushArmed;
    function AnimSeriesInfo: TTyChartAnimSeriesArray;
    { ---- the states on the proxies [Batch 94, AN3b] ---- }
    { after the build and its arming: every state element's proxy found or
      made, seeded with the rest values, given the series' stateTransition,
      a full update's previous list put back at once, then the element's
      list applied -- with a transition where upstream's would make one }
    procedure StAnimSync;
    procedure StAnimEl(var AEl: TTyStElement; AListIdx, ASeries, ARaw: Integer;
      const AName: string; AKind: Integer; const ACfg: TTyAnimCfg;
      AHasCfg, AOver: Boolean);
    { the series' stateAnimation as updateStates reads it (series, root,
      300 / cubicOut), when the series animates and the duration is above 0 }
    function StAnimCfg(ASeriesIndex: Integer; out ACfg: TTyAnimCfg): Boolean;
    { a full update's clearStates on every proxy, without a transition: the
      list each had is kept to be put back }
    procedure StAnimClearAll;
    { ---- the update [Batch 90] ---- }
    { upstream's series view ids of the option, by series index: the
      models' ids, which a merge keeps [Batch 95] }
    function AnimViewKeys: TTyStringArray;
    { each view row's DataDiffer key and raw index }
    procedure AnimRowKeys(AStore: TTyDataStore; out AKeys: TTyStringArray;
      out ARaws: TTyIntegerArray);
    { the list and keys of the render an update starts from }
    procedure AnimSnapshot;
    procedure AnimDropPrev;
    function AnimToOldPoint(AOldSeries: Integer; AX, AY: Double): TTyPointF;
    procedure AnimArmTimer;
    procedure AnimTimerFired(Sender: TObject);
    { every live clip loops }
    function AnimLoopOnly: Boolean;
    { the pointer's slide: synced to the hover, dropped with the build }
    procedure PtrAnimSync;
    procedure PtrAnimDrop;
    function PtrKeyOf(AAxis: TTyAxis): string;
    function PtrModelOf(const AHit: TTyAxisHit; out AOwn: TJSONObject): TTyAnimModel;
    function PtrMoves(const AHit: TTyAxisHit; const AModel: TTyAnimModel): Boolean;
    function PtrProps(const AHit: TTyAxisHit; AAt: Double): TTyAnimProps;
    { where the pointer of AHit is drawn: its proxy's place, AAt without one }
    function PtrAt(const AHit: TTyAxisHit; AAt: Double): Double;
    function PtrLive: Boolean;
    { the frame's continuous part (AContinuous) or the rest }
    function AnimPart(AContinuous: Boolean): TTyPaintList;
    procedure SetAnimMode(AValue: TTyChartAnimationMode);
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
    { a line's endLabel, after its marks [Batch 92, AN4] }
    function BuildEndLabel(ASlot: Integer; const AVisual: TTySeriesVisual;
      const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList): Integer;
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
    procedure LegendTextOf(AIndex: Integer; var AFont: TTyLegendFont;
      var AInk: TTyLegendInk);
    { [Batch 98] the selector buttons' blocks and the pager's font: the
      skin's under selectorLabel / emphasis.selectorLabel / pageTextStyle }
    function LegendDeco(AIndex: Integer; const AMeasurer: ITyTextMeasurer): TTyLegendDeco;
    function TitleFontOf(AIndex: Integer; const AKey, AStyleKey: string;
      APick: TTyTextPick): TTyTitleFont;
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
    procedure FreeTreeViews;
    { a tree's view over its placed nodes, and the numbers the build
      draws with [Batch 82] }
    procedure SolveTreeView(ASlot, APPI: Integer);
    procedure SolveSunbursts(APPI: Integer);
    procedure SolveTreemaps(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    procedure SolveSankeys(APPI: Integer);
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
    function BuildLegends(APPI: Integer; AList: TTyPaintList;
      const AMeasurer: ITyTextMeasurer): Integer;
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
    { A TREE'S HOVER, in place in the static list: its own focus words --
      ancestor, descendant, relative -- and upstream's edge rule. [Batch 83] }
    procedure ApplyTreeHover(AList: TTyPaintList; APPI: Integer);
    function IsTreeDatum(const ADatum: TTyChartDatumRef): Boolean;
    function TreeEmphasisOf(ASlot, ARow: Integer): TTyChartEmphasisSpec;
    function TreeFocusOf(ASlot, ARow: Integer): string;
    function TreeRowName(ASlot, ARow: Integer): string;
    function TreeRowValue(ASlot, ARow: Integer): Double;
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
    { what zrender's hover holds now, with its dispatcher [Batch 88] }
    property EvHover: TTyChartEventTarget read FEvHover;
    { THE LIST AS IT STANDS THIS FRAME: every animated element read from its
      proxy, insertion indices kept. The list itself when nothing is bound.
      [Batch 89] }
    function AnimFrame: TTyPaintList;
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
    function PointerLabelText(const AHit: TTyAxisHit; AValue: Double): string;
    function AuthorBackground(out AColour: TTyChartColor): Boolean;
    procedure GlobalInk(var AName: string; var ASize, AWeight: Integer;
      var AColour: TTyChartColor; APick: TTyTextPick);
    procedure GlobalTextOver(var AName: string; var ASize, AWeight: Integer;
      var AHasColour: Boolean; var AColour: Cardinal; APick: TTyTextPick);
    { THE ROOT'S SIDE OF A TEXT BLOCK: the root textStyle and
      richInheritPlainLabel, and the chart's global text font -- the skin's
      label font with the root textStyle's over it [Batch 86] }
    function RtGlobal: TTyRtGlobal;
    { the styles an axis' labels (plain and emphasised) and name are painted
      in: the theme's, with the family, size, weight and colour the layout
      measured them in -- the author's where written [Batch 83] }
    procedure AxisTextStyles(ASpec: PTyAxisLayoutSpec; out ALabel, APrimary,
      AName: TTyStyleSet);
    procedure AxisTextOver(var AStyle: TTyStyleSet; const AName: string;
      ASize, AWeight: Integer; AHasColour: Boolean; AColour: Cardinal;
      AKeepWeight: Boolean);
    function TipValueFormatted(const AHandler: string;
      const AParams: TTyChartCallbackParams): string; overload;
    function TipValueFormatted(const AHandler: string;
      const AParams: TTyChartCallbackParams; const AValueText: string;
      AWithIndex: Boolean): string; overload;
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
    procedure DblClick; override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    { the chart's mouse events [Batch 84] }
    function EventTargetAt(AX, AY: Integer): TTyChartEventTarget;
    function SeriesEventTarget(const ADatum: TTyChartDatumRef;
      AElement: Integer): TTyChartEventTarget;
    function SeriesEventModel(ASeriesIndex: Integer): TTyEventModel;
    procedure SilenceSeries(AList: TTyPaintList);
    procedure EmitChartEvent(const AType: string; const ATarget: TTyChartEventTarget;
      AX, AY: Integer; AHasOffset: Boolean = True);
    procedure EventMove(AX, AY: Integer);
    procedure EventDown(AButton: TMouseButton; AX, AY: Integer);
    procedure EventUp(AButton: TMouseButton; AX, AY: Integer);
    procedure EventDblClick(AX, AY: Integer);
    procedure EventContextMenu(AX, AY: Integer);
    procedure EventLeave(AX, AY: Integer);
    { ---- element states and the selection [Batch 88] ---- }
    function StKindOf(ASlot: Integer): TTyStKind;
    function StSeriesNode(ASeriesIndex: Integer): TJSONObject;
    function StItemNode(ASeriesIndex, ARaw: Integer): TJSONObject;
    { after every build: the records follow the new elements (a re-layout
      re-applies the previous lists, upstream's full update), the selection
      flags are synced, the flags applied and the values written back }
    procedure StSync(AList: TTyPaintList; APPI: Integer);
    procedure StDeclareItem(ASlot, ARaw: Integer; AList: TTyPaintList;
      APPI: Integer);
    procedure StDeclareLine(ASlot: Integer; AList: TTyPaintList);
    procedure StDeclareCandle(ASlot, ARaw: Integer;
      const ANodes: array of TJSONObject; var AHost: TTyStElement);
    procedure StWrite(AList: TTyPaintList);
    { upstream's frame: every flag that changed since the last one becomes a
      state list. True when an element changed. }
    function StApplyChanged: Boolean;
    function StItemAt(ASeriesIndex, AInnerRow: Integer): PTyStItem;
    { ---- focus and blur [Batch 90] ---- }
    { a line's polyline state, -1 for any other series; and setting it (the
      area follows the polyline, _changePolyState) }
    function StPolyOf(ASeriesIndex: Integer): Integer;
    procedure StPolyTo(ASeriesIndex, AState: Integer);
    { the coordinate system blurSeries compares: the grid of a cartesian, a
      calendar, a radar; '' for none (a series with none matches itself) }
    function StCoordKey(ASlot: Integer): string;
    { ecData.focus / blurScope of an item's element (the item, then the
      series) and of the series' own elements }
    function StNodes(ASeriesIndex, ARaw: Integer): TTyStNodeArray;
    function StItemFocus(ASeriesIndex, ARaw: Integer;
      out AScope: TTyStScope): TTyStFocus;
    function StSeriesFocus(ASeriesIndex: Integer;
      out AScope: TTyStScope): TTyStFocus;
    procedure StBlurSeries(ATarget: Integer; const AFocus: TTyStFocus;
      AScope: TTyStScope);
    procedure StAllLeaveBlur;
    { the hover dispatcher under a target: a data item (APart 0), a line's
      polyline (1) or area (2); False when there is none or its emphasis is
      disabled }
    function StDispatcher(const ATarget: TTyChartEventTarget;
      out AItem: PTyStItem; out APart: Integer): Boolean;
    function StInnerRaw(ASeriesIndex, AInner: Integer): Integer;
    procedure StHoverOut(const ATarget: TTyChartEventTarget);
    procedure StHoverOver(const ATarget: TTyChartEventTarget);
    { an element the state machine draws (the overlay leaves it alone) }
    function StOwnsElement(AIndex: Integer): Boolean;
    function StEmphasised(AIndex: Integer): Boolean;
    function StPrimaryInk: TTyChartColor;
    procedure SelEnsure(ASlot: Integer);
    function SelData(ASlot: Integer): TTySelData;
    procedure SelSyncFlags(ASlot: Integer);
    function MatchSeries(APayload: TJSONObject): TTyIntegerArray;
    function QueryDataIndex(ASlot: Integer; APayload: TJSONObject;
      out AInner: TTyIntegerArray): Boolean;
    procedure DoSelectAction(APayload: TJSONObject);
    procedure DoHighDownAction(APayload: TJSONObject);
    procedure StClickSelect(const ATarget: TTyChartEventTarget);
    { ---- the legend's actions and its item's handlers [Batch 93] ---- }
    { legendAction.ts: the method on every legend the payload names, the
      selected map of those, written back into EVERY legend, the full update,
      then the event }
    procedure DoLegendAction(APayload: TJSONObject);
    { eachComponent({mainType: 'legend', query}): legendIndex, legendId,
      legendName; none is every legend }
    function LegendQuery(APayload: TJSONObject): TTyIntegerArray;
    { makeSelectedMap: every name of the legend's data but the line breaks,
      ANDed into AMap }
    procedure LegendSelectedMapInto(AIndex: Integer; AMap: TJSONObject);
    { the ids of the series whose legendHoverLink is falsy, as a JSON array }
    function LegendExcludeIds: string;
    { dispatchHighlightAction / dispatchDownplayAction for an item }
    procedure LegendHighDown(const ATarget: TTyChartEventTarget; const AType: string);
    { dispatchSelectAction: downplay, legendToggleSelect, highlight }
    procedure LegendClick(const ATarget: TTyChartEventTarget);
    { [Batch 98] the selector button's onclick: legendAllSelect or
      legendInverseSelect by the legend's id }
    procedure LegendSelectorClick(const ATarget: TTyChartEventTarget);
    { [Batch 98] a page button's onclick (_pageGo): legendScroll to the
      previous or next page's first item, nothing when there is none }
    procedure LegendPagerClick(const ATarget: TTyChartEventTarget);
    { [Batch 98] scrollableLegendAction: scrollDataIndex into every scroll
      legend the payload names, the full update, the event }
    procedure DoLegendScroll(APayload: TJSONObject);
    { [Batch 98] the selector button in its hovered ink, or none }
    procedure LegendSelHover(ALegend, AIndex: Integer);
    { [Batch 98] _layoutContentAndController's updateProps of the content
      group: from where it stands (on a first render, unscrolled) to the
      page, with the legend's update timing when the pager shows; at once
      otherwise }
    procedure LegAnimSync;
    procedure LegAnimDrop;
    function LegLive: Boolean;
    { A FULL UPDATE NOW: the model, the layout, the list and the states, as
      upstream's update runs inside dispatchAction -- so the action that
      follows finds the new elements }
    procedure FullUpdate;
    { the target the element at AIndex of the list answers as }
    function TargetOfElement(AIndex: Integer): TTyChartEventTarget;
    { the series' (or the datum's) border, for its legend icon }
    procedure LegendBorderOf(ASlot, ARaw: Integer; var ASrc: TTyLegendSource);
    procedure EmitPayloadEvent(const AType, APayloadJson: string);
    function HasChartHandler(const AType: string): Boolean;
    function SeriesModelId(ASeriesIndex: Integer): string;
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
    function IsTreeSeries(ASeriesIndex: Integer): Boolean;
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
    { UPSTREAM'S dispatchAction for the state actions [Batch 88], the payload
      as JSON text: `select`, `unselect`, `toggleSelect` (by seriesIndex /
      seriesId / seriesName, and dataIndexInside / dataIndex / name; no series
      named is every series) publish select / unselect / toggleselect and then
      selectchanged; `highlight` and `downplay` set the emphasis by action and
      publish their own event. The picture follows at the next paint. False
      for any other type, a payload that is not an object, or a `batch`.
      [Batch 93] `legendToggleSelect`, `legendSelect`, `legendUnSelect`,
      `legendAllSelect` and `legendInverseSelect` (legendIndex / legendId /
      legendName, none is every legend) switch legend items, re-render the
      chart at once and publish legendselectchanged, legendselected,
      legendunselected, legendselectall or legendinverseselect. }
    function DispatchAction(const APayloadJson: string): Boolean;
    { getSelectedDataIndices: the RAW indices of series ASeriesIndex's
      selection, in the order the names entered it }
    function SelectedDataIndices(ASeriesIndex: Integer): TTyIntegerArray;
    { the series' selectedMap as JSON: null, "all" or an object }
    function SelectedMapText(ASeriesIndex: Integer): string;
    { LEGEND AIndex's `selected` map as the actions left it, as JSON in
      JavaScript's key order; '{}' when it has none [Batch 93] }
    function LegendSelectedText(AIndex: Integer): string;
    { THE STATE OF A DATA ITEM'S ELEMENTS, as the last paint left it: flags,
      state list, rest and current values -- for a bar, a pie slice (with its
      label and label line) or a line / scatter symbol. False when the item
      has no element the state machine speaks for. }
    function ItemStates(ASeriesIndex, ADataIndex: Integer;
      out AItem: TTyStItem): Boolean;
    { a line's polyline and area }
    function LineStates(ASeriesIndex: Integer; out ARun, AArea: TTyStItem): Boolean;
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
    { ---- the enter animation [Batch 89] ---- }
    { THE CLOCK STEPPED BY HAND: every clip advanced to ANowMs (epoch ms, as
      upstream's Date), the frame repainted, and -- when the last clip has
      run -- the series put back into the static layer. The 16 ms timer
      calls the same with the machine's clock. }
    procedure AnimTick(ANowMs: Double);
    { ms; NaN (the default) is the machine's clock -- and only then does the
      timer run }
    property AnimNow: Double read FAnimNow write FAnimNow;
    { the clips still running, and whether the series are in motion }
    function AnimClipCount: Integer;
    { the clips that loop (an effectScatter's ripples) [Batch 92] }
    function AnimLoopClipCount: Integer;
    { the axis pointer's slide [Batch 92]: its clips, and the proxy of an
      axis by its key -- 'xAxis0', 'yAxis1' }
    function AnimPointerClipCount: Integer;
    function AnimPointerProxy(const AKey: string): TTyChartAnimProxy;
    { only loops are live: the static layer holds the rest }
    property AnimContinuous: Boolean read FAnimContinuous;
    property AnimLive: Boolean read FAnimLive;
    { the animated proxies, for a test or a host to read (not the states'
      own: AnimStateProxy) }
    function AnimProxyCount: Integer;
    function AnimProxy(AIndex: Integer): TTyChartAnimProxy;
    function AnimFindProxy(ASeries, AIndex: Integer;
      const ARole: string): TTyChartAnimProxy;
    { A REMOVED ELEMENT STILL LEAVING [Batch 90]: the ghost of the OLD row
      AIndex of series ASeries, nil once its fade has ended; and how many
      are still drawn }
    function AnimFindGhost(ASeries, AIndex: Integer;
      const ARole: string): TTyChartAnimProxy;
    function AnimGhostCount: Integer;
    { THE PROXY AN ELEMENT'S STATES RUN ON [Batch 94]: of series ASeries,
      inner row ARow, the part 'host', 'label', 'guide' (the row's), 'poly'
      or 'area' (a line's, ARow ignored); nil when none is bound }
    function AnimStateProxy(ASeries, ARow: Integer; const APart: string): TTyChartAnimProxy;
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
    { upstream's treeExpandAndCollapse action: flip ADataIndex's expanded
      state in the tree series ASeriesIndex (-1: every tree). Not gated by
      `expandAndCollapse`, which gates the click only. False for a series
      that is no tree, row 0 or a row past the end. [Batch 81] }
    { THE CHART'S MOUSE EVENTS, upstream's chart.on / chart.off [Batch 84]:
      AType one of click, dblclick, mousedown, mouseup, mousemove, mouseover,
      mouseout, globalout, contextmenu (any case); AQuery '' for every event,
      a class type ('series.bar'), or a JSON object ('{"seriesIndex":1}').
      The same handler registered twice for one type is kept once, as
      upstream keeps it. Answers the registration's id, or -1 for a type the
      chart does not emit. }
    function ChartOn(const AType: string; AHandler: TTyChartEventHandler;
      const AQuery: string = ''): Integer;
    procedure ChartOff(AId: Integer);
    function TreeToggle(ASeriesIndex, ADataIndex: Integer): Boolean;
    { upstream's treeRoam action: a pan (both deltas present) and/or a zoom
      about a point, on the tree ASeriesIndex (-1: every tree). Not gated by
      `roam`, which gates the gestures only. [Batch 82] }
    function TreeDispatchRoam(const APayload: TTyGraphRoamPayload): Boolean;
    function TreeRoam(ASeriesIndex: Integer; ADX, ADY: Double): Boolean;
    function TreeZoom(ASeriesIndex: Integer; AScale, AOriginX, AOriginY: Double): Boolean;
    { whether the row is expanded now, the toggles applied }
    function TreeExpanded(ASeriesIndex, ADataIndex: Integer): Boolean;
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
    { the titles as laid out, and the font each line was measured and drawn
      in (ALine 0 the text, 1 the subtext) [Batch 83] }
    function TitleCount: Integer;
    function TitleLayoutOf(AIndex: Integer): TTyTitleLayout;
    function TitleFontUsed(AIndex, ALine: Integer): TTyTitleFont;
    { a title line's text block as drawn; no pieces where it is one run
      [Batch 86] }
    function TitleRt(AIndex, ALine: Integer): TTyRtDrawn;
    { ---- setOption [Batch 95] ---- }
    { UPSTREAM'S setOption(option, notMerge). notMerge replaces the option
      whole -- EVEN WITH THE TEXT IT ALREADY HOLDS, where the Option property
      sees no change: every model is new, so a roam, a dataZoom window, the
      legend's and the series' selection all start again. Otherwise it is
      MergeOption. }
    procedure SetOption(const AJson: string; ANotMerge: Boolean = False); overload;
    { THE OPTIONS FORM, setOption(option, opts) [Batch 97]: notMerge,
      replaceMerge, lazyUpdate, silent (TTySetOptionOpts). False, with the
      option as it was and OptionError saying why, for what MergeOption
      refuses and for a replaceMerge naming no component main type. }
    function SetOption(const AJson: string; const AOpts: TTySetOptionOpts): Boolean; overload;
    { the same with the options as JSON text, '{"replaceMerge":["series"]}';
      refused when that text is no object }
    function SetOption(const AJson, AOptsJson: string): Boolean; overload;
    { THE VIEW KEY the next update pairs series ASeries by -- its model id,
      or a key no old view has when replaceMerge made it brand new -- and
      the old render's key at an index. For the tests. [Batch 97] }
    function SeriesViewKey(ASeries: Integer): string;
    function SeriesOldViewKey(ASeries: Integer): string;
    { A MERGE setOption: components and series mapped onto the models there
      by id, then name, then index, and merged into them (see
      tyControls.AdvChart.OptionMerge). What upstream keeps in the models
      survives: the legend's selection unless the option writes `selected`,
      a roam's centre and zoom, an action's dataZoom window, the series'
      selection. It renders as an update. The Option property reads the
      merged option afterwards (GetOptionJson). False, the option unchanged
      and OptionError saying why, when the text does not parse, is no
      object, or gives two components of one main type the same id. The
      first option ever set is an init, as upstream's is. }
    function MergeOption(const AJson: string): Boolean;
    { The merged option, shaped as upstream's getOption: every component
      main type an array (null in a hole), objects in JavaScript's key order.
      It is the option as WRITTEN and merged -- no theme, no defaults, and no
      ids: those are on the models (ComponentModelId). }
    function GetOptionJson: string;
    { the model at a component index: upstream's id ('\0' + name + '\0' + n
      when none was written), name and subType; '' where there is none }
    function ComponentModelId(const AMainType: string; AIndex: Integer): string;
    function ComponentModelName(const AMainType: string; AIndex: Integer): string;
    function ComponentModelSubType(const AMainType: string; AIndex: Integer): string;
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
      on screen says why. OptionError carries the reason.

      A DECLARATION, NOT A setOption [Batch 95]: assigning the text it holds
      changes nothing, a different text replaces the option whole (upstream's
      notMerge). SetOption and MergeOption are the calls; after a merge this
      reads the merged option. }
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
    property OnTreeExpandAndCollapse: TTyTreeToggleEvent read FOnTreeToggle write FOnTreeToggle;
    { EVERY chart mouse event, unfiltered -- the published face of ChartOn
      [Batch 84] }
    property OnChartEvent: TTyChartEventHandler read FOnChartEvent write FOnChartEvent;
    property OnTreeRoam: TTyGraphRoamEvent read FOnTreeRoam write FOnTreeRoam;
    property OnDataZoom: TTyDataZoomEvent read FOnDataZoom write FOnDataZoom;
    { when the enter animations play -- see TTyChartAnimationMode [Batch 89] }
    property AnimationMode: TTyChartAnimationMode read FAnimMode
      write SetAnimMode default camAuto;
  end;

implementation

uses
  tyControls.Controller,
  { Only for the diagnostic resourcestrings -- the same one-way dependency the
    rest of the AdvChart family keeps, invisible to a host. }
  tyControls.StrConsts,
  tyControls.AdvChart.RichStyle, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.LinePath;

{ ==================== construction ==================== }

constructor TTyAdvanceChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOption := TTyChartOption.Create;
  FLegendSelHoverLegend := -1;
  FLegendSelHoverIdx := -1;
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
  FAnimNow := NaN;
  FAnimMode := camAuto;
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
  { THE PROXIES BEFORE THE DRIVER: freeing one takes its clips off it }
  FreeAndNil(FAnimTimer);
  FreeAndNil(FAnimSet);
  FreeAndNil(FAnim);
  FreeAndNil(FAnimFrame);
  FreeAndNil(FAnimSplit);
  PtrAnimDrop;
  FreeAndNil(FPtrProxies);
  FreeAndNil(FPtrAnim);
  LegAnimDrop;
  FreeAndNil(FLegAnim);
  FreeAndNil(FAnimOldBuild);
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
  { the pointer's slide goes with the axes [Batch 92] }
  PtrAnimDrop;
  { AND THE RADARS WITH THEM, for the same reason: a binding holds a radar's
    INDEX, and the spoke objects a paint list was built against are about to
    stop existing. }
  FreeRadars;
  FreeCalendars;
  FreeGraphs;
  FreeTreeViews;
  FTrees := nil;
  FSunbursts := nil;
  FTreemaps := nil;
  FTreemapInks := nil;
  FSankeys := nil;
  FSankeyInks := nil;
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

{ THE PROPERTY IS A DECLARATION, not a setOption: the text it already holds
  is no change. LCL streaming, the Object Inspector and the option editor
  all assign unchanged text, and a legend toggled by a click must not reset
  because of it [Batch 93]. Upstream's notMerge with the same option DOES
  reset everything -- that is SetOption(AJson, True). After a merge the
  property holds the merged option, so assigning the text set before the
  merge is a real change. [Batch 95] }
function TySetOptionOptsOf(const AJson: string; out AOpts: TTySetOptionOpts): Boolean;
var
  d, r: TJSONData;
  o: TJSONObject;
  k: Integer;

  function Truthy(A: TJSONData): Boolean;
  begin
    if (A = nil) or (A.JSONType = jtNull) then Exit(False);
    case A.JSONType of
      jtBoolean: Result := A.AsBoolean;
      jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
      jtString: Result := A.AsString <> '';
    else
      Result := True;
    end;
  end;

  procedure AddType(A: TJSONData);
  var n: Integer;
  begin
    { normalizeToArray, each entry a main type as it is named -- anything
      but a string is named by its text, and so is refused }
    n := Length(AOpts.ReplaceMerge);
    SetLength(AOpts.ReplaceMerge, n + 1);
    if A.JSONType = jtString then AOpts.ReplaceMerge[n] := A.AsString
    else AOpts.ReplaceMerge[n] := A.AsJSON;
  end;

begin
  AOpts := Default(TTySetOptionOpts);
  if Trim(AJson) = '' then Exit(True);
  try
    d := GetJSON(AJson);
  except
    d := nil;
  end;
  if not (d is TJSONObject) then
  begin
    d.Free;
    Exit(False);
  end;
  o := TJSONObject(d);
  try
    AOpts.NotMerge := Truthy(o.Find('notMerge'));
    AOpts.LazyUpdate := Truthy(o.Find('lazyUpdate'));
    AOpts.Silent := Truthy(o.Find('silent'));
    r := o.Find('replaceMerge');
    if r <> nil then
    begin
      if r.JSONType = jtArray then
      begin
        for k := 0 to r.Count - 1 do AddType(r.Items[k]);
      end
      else
        AddType(r);
    end;
  finally
    o.Free;
  end;
  Result := True;
end;

procedure TTyAdvanceChart.SetOptionText(const AValue: string);
begin
  if FOptionText = AValue then Exit;
  ApplyNotMerge(AValue);
  AfterSetOption(False, False);
end;

procedure TTyAdvanceChart.ApplyNotMerge(const AValue: string);
begin
  FOptionText := AValue;
  { THE OLD OPTION'S SERIES VIEWS, before the text goes: an update keeps a
    series whose view id and type are the same -- unless an update already
    waits, whose old render is still the one before it [Batch 90] -- or a
    lazy one does [Batch 97] }
  if not FAnimPrev.Valid and not FLazyPending then FAnimOldViewKeys := AnimViewKeys;
  { new models: none asks for a new view (initBase ignores replaceMerge) }
  FAnimFresh := nil;
  FOption.SetOptionText(AValue);
  FGraphForce := nil;
  { notMerge: new series models, so no roam survives either, nor a toggle. }
  FGraphRoam := nil;
  FTreeToggled := nil;
  FTreeRoam := nil;
  FTreeBox := nil;
  FTreeBoxHas := nil;
  FPressArmed := False;
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
  { new series models: no selection, no element survives [Batch 88] }
  FSel := nil;
  { AND WHAT THE POINTER IS OVER IS A REMOVED ELEMENT: the next move finds a
    new one there -- an out to the old, an over to the new, as zrender's
    hover meets elements a notMerge setOption replaced. Its identity is
    made one no element answers. }
  if FEvHover.Id <> 0 then FEvHover.Id := Low(Int64);
  FSelInit := nil;
  FSt := nil;
  FStDirty := False;
  { new legend models: init and optionUpdated run again [Batch 93] }
  FLegendLoaded := False;
  { and new legend views: a first render again [Batch 98] }
  LegAnimDrop;
  { A NEW OPTION ENTERS: the next render that may animate plays it }
  FAnimPending := True;
  FDirty := True;
  Invalidate;
end;

function TTyAdvanceChart.GetErrorText: string;
begin
  Result := FOption.Error.Message;
end;

procedure TTyAdvanceChart.SetOption(const AJson: string; ANotMerge: Boolean);
var o: TTySetOptionOpts;
begin
  o := Default(TTySetOptionOpts);
  o.NotMerge := ANotMerge;
  SetOption(AJson, o);
end;

function TTyAdvanceChart.SetOption(const AJson: string;
  const AOpts: TTySetOptionOpts): Boolean;
begin
  { normalizeSetOptionInput asserts before anything is touched }
  if not FOption.CheckReplaceMerge(AOpts.ReplaceMerge) then Exit(False);
  { THE FIRST OPTION is an init whatever the flag says (echarts.ts:768),
    and an init ignores replaceMerge (initBase merges with no opts) }
  if AOpts.NotMerge or not (FOption.Root is TJSONObject) then
  begin
    ApplyNotMerge(AJson);
    Result := not FOption.Error.Failed;
  end
  else
    Result := DoMerge(AJson, AOpts.ReplaceMerge);
  if Result then AfterSetOption(AOpts.LazyUpdate, AOpts.Silent);
end;

function TTyAdvanceChart.SetOption(const AJson, AOptsJson: string): Boolean;
var o: TTySetOptionOpts;
begin
  if not TySetOptionOptsOf(AOptsJson, o) then
  begin
    FOption.Refuse(rsTyOptSetOptsNotObject);
    Exit(False);
  end;
  Result := SetOption(AJson, o);
end;

function TTyAdvanceChart.MergeOption(const AJson: string): Boolean;
begin
  Result := SetOption(AJson, Default(TTySetOptionOpts));
end;

function TTyAdvanceChart.DoMerge(const AJson: string;
  const AReplace: array of string): Boolean;
var
  rep: TTyMergeReport;
  oldKeys: TTyStringArray;
  si, s: Integer;
begin
  { the old views, before the merge renames anything }
  oldKeys := AnimViewKeys;
  if not FOption.MergeOptionText(AJson, AReplace, @MergeBefore, rep) then Exit(False);
  { the views the next update pairs with: the last render's -- unless an
    update already waits (an old render kept) or a lazy one does }
  if not FAnimPrev.Valid and not FLazyPending then
  begin
    FAnimOldViewKeys := oldKeys;
    FAnimFresh := nil;
  end;
  { A BRAND NEW MODEL ASKS FOR A NEW VIEW, whatever id it made (a removed
    model's, often) -- until the update that pairs the views [Batch 97] }
  si := TyMergeSlotsIndex(rep, 'series');
  if si >= 0 then
    for s := 0 to High(rep.Slots[si].Brand) do
      if rep.Slots[si].Brand[s] then
      begin
        if s > High(FAnimFresh) then SetLength(FAnimFresh, s + 1);
        FAnimFresh[s] := True;
      end;
  FOptionText := FOption.OptionJson;
  MergeKeepStates(rep);
  { AN UPDATE: the series keep their views where their ids and types do }
  FAnimPending := True;
  FDirty := True;
  Invalidate;
  Result := True;
end;

procedure TTyAdvanceChart.AfterSetOption(ALazy, ASilent: Boolean);
begin
  if ALazy then
  begin
    { the next frame does the update: one pending at a time, its silent the
      last lazy call's }
    FLazyPending := True;
    FLazySilent := ASilent;
    Exit;
  end;
  { a synchronous update takes a pending lazy one with it }
  FLazyPending := False;
  if not ASilent then EmitUpdated;
end;

procedure TTyAdvanceChart.LazyUpdateDone;
begin
  if not FLazyPending then Exit;
  FLazyPending := False;
  if not FLazySilent then EmitUpdated;
end;

{ `updated`: triggerUpdatedEvent, no params. Only to a handler registered
  for it -- the catch-all OnChartEvent does not count as asking, as with
  the legacy select events [Batch 97] }
procedure TTyAdvanceChart.EmitUpdated;
var
  ev: TTyChartEvent;
  regs: array of TTyChartEventReg;
  i: Integer;
begin
  if not HasChartHandler('updated') then Exit;
  ev := Default(TTyChartEvent);
  ev.EventType := 'updated';
  ev.Params := TyChartBlankParams;
  regs := Copy(FEventRegs);
  for i := 0 to High(regs) do
    if regs[i].EventType = 'updated' then regs[i].Handler(Self, ev);
end;

function TTyAdvanceChart.SeriesViewKey(ASeries: Integer): string;
var keys: TTyStringArray;
begin
  keys := AnimViewKeys;
  Result := '';
  if (ASeries < 0) or (ASeries > High(keys)) then Exit;
  Result := keys[ASeries];
  if (ASeries <= High(FAnimFresh)) and FAnimFresh[ASeries] then Result := 'n:' + Result;
end;

function TTyAdvanceChart.SeriesOldViewKey(ASeries: Integer): string;
begin
  Result := '';
  if (ASeries >= 0) and (ASeries <= High(FAnimOldViewKeys)) then
    Result := FAnimOldViewKeys[ASeries];
end;

function TTyAdvanceChart.GetOptionJson: string;
begin
  Result := FOption.OptionJson;
end;

function TTyAdvanceChart.ComponentModelId(const AMainType: string; AIndex: Integer): string;
begin
  Result := FOption.ComponentId(AMainType, AIndex);
end;

function TTyAdvanceChart.ComponentModelName(const AMainType: string; AIndex: Integer): string;
begin
  Result := FOption.ComponentModelName(AMainType, AIndex);
end;

function TTyAdvanceChart.ComponentModelSubType(const AMainType: string; AIndex: Integer): string;
begin
  Result := FOption.ComponentSubType(AMainType, AIndex);
end;

procedure TTyAdvanceChart.MergeBefore(const AMainType: string; AIndex: Integer;
  ANode, ANew: TJSONObject);
begin
  { AN ACTION'S WINDOW is setRawRange's write into the model's option: start
    and end, their values cleared. A merge that writes this dataZoom's range
    lands on it, so it goes into the tree first and leaves the side state. }
  if AMainType <> 'dataZoom' then Exit;
  if (AIndex < 0) or (AIndex > High(FDzRawHas)) or not FDzRawHas[AIndex] then Exit;
  if (ANew.Find('start') = nil) and (ANew.Find('end') = nil)
    and (ANew.Find('startValue') = nil) and (ANew.Find('endValue') = nil)
    and (ANew.Find('rangeMode') = nil) then Exit;
  ANode.Floats['start'] := FDzRawStart[AIndex];
  ANode.Elements['startValue'] := TJSONNull.Create;
  ANode.Floats['end'] := FDzRawStop[AIndex];
  ANode.Elements['endValue'] := TJSONNull.Create;
  FDzRawHas[AIndex] := False;
end;

procedure TTyAdvanceChart.MergeRoamOverride(var AState: TTyGraphRoamState;
  ASeries: Integer; ANew: TJSONObject);
var
  spec: TTyGraphSpec;
  node: TJSONData;
  root: TJSONObject;
begin
  { upstream's roam wrote centre and zoom into the series' option; a merge
    writing one of them overwrites that one and keeps the other }
  if (not AState.Valid) or (ANew = nil) then Exit;
  if (ANew.Find('center') = nil) and (ANew.Find('zoom') = nil) then Exit;
  spec := TyGraphSpecDefault;
  node := FOption.ComponentAt('series', ASeries);
  root := nil;
  if FOption.Root is TJSONObject then root := TJSONObject(FOption.Root);
  if node is TJSONObject then TyGraphReadRoamOptions(TJSONObject(node), root, spec);
  if ANew.Find('center') <> nil then AState.Centre := spec.Centre;
  if ANew.Find('zoom') <> nil then AState.Zoom := spec.Zoom;
end;

procedure TTyAdvanceChart.MergeKeepStates(const AReport: TTyMergeReport);
var
  si, s, n, i: Integer;
  fate: TTyMergeFate;
  live: Boolean;
  opt: TJSONObject;
begin
  { ---- by series: a model that survived keeps what upstream keeps on it ---- }
  si := TyMergeSlotsIndex(AReport, 'series');
  if si >= 0 then
  begin
    n := Length(AReport.Slots[si].Fate);
    for s := 0 to n - 1 do
    begin
      fate := AReport.Slots[si].Fate[s];
      live := fate in [mfKept, mfMerged];
      opt := AReport.Slots[si].NewOpt[s];
      { the force layout's preservedPoints, the roam's write-back, the
        selection's selectedMap and the tree view's last box are the
        model's, and go with it }
      if not live then
      begin
        if s <= High(FGraphForce) then FGraphForce[s] := Default(TTyGraphForceState);
        if s <= High(FGraphRoam) then FGraphRoam[s] := Default(TTyGraphRoamState);
        if s <= High(FTreeRoam) then FTreeRoam[s] := Default(TTyGraphRoamState);
        if s <= High(FTreeBoxHas) then FTreeBoxHas[s] := False;
        if s <= High(FSelInit) then FSelInit[s] := False;
        Continue;
      end;
      if fate = mfMerged then
      begin
        if s <= High(FGraphRoam) then MergeRoamOverride(FGraphRoam[s], s, opt);
        if s <= High(FTreeRoam) then MergeRoamOverride(FTreeRoam[s], s, opt);
      end;
    end;
  end;
  { EVERY SERIES IS VISITED (backwardCompat writes `series` into every
    option) and re-creates its data: a tree's expand state is the data's }
  FTreeToggled := nil;

  { ---- by dataZoom: an action's window stays unless the merge wrote over
    it (MergeBefore); a new model has none ---- }
  si := TyMergeSlotsIndex(AReport, 'dataZoom');
  if si >= 0 then
  begin
    n := Length(AReport.Slots[si].Fate);
    i := Length(FDzRawHas);
    SetLength(FDzRawHas, n);
    SetLength(FDzRawStart, n);
    SetLength(FDzRawStop, n);
    for s := i to n - 1 do FDzRawHas[s] := False;
    for s := 0 to n - 1 do
      if not (AReport.Slots[si].Fate[s] in [mfKept, mfMerged]) then FDzRawHas[s] := False;
  end;

  { ---- what a re-render rebuilds anyway, reset as a notMerge resets it ---- }
  FPressArmed := False;
  FRoamSeries := -1;
  FDzState := nil;
  FDzRoamThrottle := nil;
  FDzRoamBatch := nil;
  FDzHover := Default(TTyDzTarget);
  FDzDrag := Default(TTyDzTarget);
  FDzHasDown := False;
  FDzPanGrid := -1;
  if FEvHover.Id <> 0 then FEvHover.Id := Low(Int64);
  FSt := nil;
  FStDirty := False;
  { THE LEGEND IS VISITED (it depends on the series): optionUpdated
    resolves single mode again; `selected` itself is in the tree, merged }
  FLegendLoaded := False;
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
  lblHasCol: Boolean;
  lblCol: Cardinal;
begin
  FLastRect := ARect;
  FLastPPI := APPI;
  { a full update: the next sync re-renders the states [Batch 88] }
  Inc(FStGen);
  { the legend is rendered anew: its buttons are new elements in no state
    [Batch 98] }
  FLegendSelHoverLegend := -1;
  FLegendSelHoverIdx := -1;
  { A NEW LAYOUT SNAPS: a resize, a theme, a zoom -- upstream sets those
    directly ({duration: 0}) -- and a new option is armed again after the
    build [Batch 89]. A NEW OPTION UPDATES: the render before it is kept --
    its list, its keys, its build -- for the render that arms it, and the
    proxies run on [Batch 90]. }
  if FAnimPending and (FAnimMode <> camOff) and not (csDesigning in ComponentState) then
  begin
    if not FAnimPrev.Valid then AnimSnapshot;
  end
  else
    AnimDropAll;
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
  { THE OPTION'S ROOT textStyle BETWEEN THE THEME AND THE AXIS: upstream's
    getFont falls back to it, and free-standing text takes its colour
    [Batch 83] }
  { labels: the family and weight only -- their 12px and their token colour
    are defaults of their own; the name has neither and takes all four }
  lblHasCol := False;
  lblCol := 0;
  GlobalTextOver(txt.FontName, txt.FontSizeLogical, txt.FontWeight,
    lblHasCol, lblCol, [ttpWeight, ttpFamily]);
  GlobalTextOver(txt.NameFontName, txt.NameFontSizeLogical, txt.NameFontWeight,
    txt.HasGlobalColour, txt.GlobalColour, [ttpSize, ttpWeight, ttpFamily, ttpColour]);
  txt.RtGlobal := RtGlobal;
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
  SolveSankeys(APPI);
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
  { DRAWN IN WHAT IT WAS MEASURED IN [Batch 83] }
  AxisTextStyles(spec, labelS, primaryS, nameS);
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
  if (spec <> nil) and spec^.NamePlacement.Shown
    and (tpTextColor in nameS.Present) then
  begin
    { A BLOCK DRAWS ITS PIECES, the skin's ink where no style gave one
      [Batch 86] }
    if Length(spec^.NamePlacement.Rt) > 0 then
      TyRenderRtPieces(APainter, spec^.NamePlacement.Rt, spec^.NamePlacement.X,
        spec^.NamePlacement.Y, spec^.NamePlacement.RotationRad, spec^.RtScale, 1,
        True, nameS.TextColor)
    { LEVEL IS LEVEL: a y axis' end name comes out of the matrices a few
      hundred quadrillionths of a radian off, and the flat path is the one
      that sets a name of several lines }
    else if Abs(spec^.NamePlacement.RotationRad) < 1e-9 then
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
      { A BLOCK DRAWS ITS PIECES [Batch 86] }
      if Length(places[i].Rt) > 0 then
      begin
        TyRenderRtPieces(APainter, places[i].Rt, places[i].X, places[i].Y,
          spec^.RotationRad, spec^.RtScale, 1, True, lblStyle.TextColor);
        Continue;
      end;
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
    { upstream's frame: the flags become state lists [Batch 88] }
    StApplyChanged;
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
  bg: TTyChartColor;
  fill: TTyFill;
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
  { THE OPTION'S backgroundColor OVER THE SKIN'S GROUND, inside the frame's
    corners -- 'transparent' and anything unreadable leave the skin's
    [Batch 83] }
  if AuthorBackground(bg) then
  begin
    fill := Default(TTyFill);
    fill.Kind := tfkSolid;
    fill.Color := TTyColor(bg);
    APainter.FillBackground(ARect, fill, boxStyle.Radius);
  end;

  plotF := TyRectF(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  if FDirty or (plotF.Right <> FLastRect.Right)
    or (plotF.Bottom <> FLastRect.Bottom) then
  begin
    Relayout(APainter, plotF, APPI, AMeasurer);
    { the frame a lazy setOption waited for [Batch 97] }
    LazyUpdateDone;
  end;

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
    room, so anything it overlaps it is meant to overlap. While the series
    move the title goes with them into the dynamic layer, so it stays over
    them [Batch 89]. }
  if not FAnimLive or FAnimContinuous then PaintTitles(APainter);
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
    { AN INDEX HOLE takes no colour: eachSeries never meets it, so the
      series after it pick on from the palette [Batch 97] }
    if node = nil then Continue;
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
  Result.FontWeight := st.FontWeight;
  Result.Text := TTyChartColor(st.TextColor);
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    Result.Text, [ttpSize, ttpWeight, ttpFamily]);
  if AView.FontSize > 0 then Result.FontSizeLogical := AView.FontSize;
  if AView.HasText_ then Result.Text := AView.TextColour;
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
  Result.FontWeight := st.FontWeight;
  Result.Text := TTyChartColor(st.TextColor);
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    Result.Text, [ttpSize, ttpWeight, ttpFamily]);
  if ASpec.FontSize > 0 then Result.FontSizeLogical := ASpec.FontSize;
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
  { the dispatch's triggerUpdatedEvent [Batch 97] }
  EmitUpdated;
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
      pin.SeriesIndex := FMarkers[i].SeriesIndex;
      if SlotOfSeries(FMarkers[i].SeriesIndex) >= 0 then
        pin.SeriesType := FBindings[SlotOfSeries(FMarkers[i].SeriesIndex)].SeriesType;
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
      pin.RtGlobal := RtGlobal;
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
  ink.RtGlobal := RtGlobal;
  for i := 0 to High(FMarkAreaPics) do
    if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkArea].Present then
      Inc(Result, TyBuildMarkAreas(FMarkAreaPics[i], FMarkers[i].Blocks[mkArea], ink,
        AMeasurer, AList, FMarkers[i].SeriesIndex));
  for i := 0 to High(FMarkPointPics) do
    if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkPoint].Present then
      Inc(Result, TyBuildMarkPoints(FMarkPointPics[i], FMarkers[i].Blocks[mkPoint], ink,
        AMeasurer, AList, FMarkers[i].SeriesIndex));
  for i := 0 to High(FMarkLinePics) do
    if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkLine].Present then
      Inc(Result, TyBuildMarkLines(FMarkLinePics[i], FMarkers[i].Blocks[mkLine], ink,
        AMeasurer, AList, FMarkers[i].SeriesIndex));
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
  Result.HasColour := False;
  Result.Colour := 0;
end;

{ A TITLE LINE'S FONT: the theme's, the root textStyle over it, the title's
  own textStyle or subtextStyle over that -- upstream's getFont order, and
  the colour free-standing text takes [Batch 83] }
function TTyAdvanceChart.TitleFontOf(AIndex: Integer; const AKey,
  AStyleKey: string; APick: TTyTextPick): TTyTitleFont;
var
  node, st, d: TJSONData;
  col: TTyChartColor;
begin
  Result := TitleFont(AKey);
  GlobalTextOver(Result.Name, Result.SizeLogical, Result.Weight,
    Result.HasColour, Result.Colour, APick);
  node := FOption.ComponentAt('title', AIndex);
  if not (node is TJSONObject) then Exit;
  st := TJSONObject(node).Find(AStyleKey);
  if not (st is TJSONObject) then Exit;
  d := TJSONObject(st).Find('fontFamily');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
    Result.Name := d.AsString;
  Result.SizeLogical := TyOptFontSize(TJSONObject(st).Find('fontSize'),
    Result.SizeLogical);
  Result.Weight := TyFontWeightOf(TJSONObject(st).Find('fontWeight'), Result.Weight);
  d := TJSONObject(st).Find('color');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
  begin
    Result.HasColour := True;
    Result.Colour := col;
  end;
end;

procedure TTyAdvanceChart.SolveTitles(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i, n, line: Integer;
  rts: array[0..1] of TTyRtBlockStyle;
  meters: array[0..1] of ITyTextMeasurer;
  node, st: TJSONData;
  glob: TTyRtGlobal;
  b: TTyRtBlockStyle;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
begin
  n := TyTitleCount(FOption);
  SetLength(FTitles, n);
  SetLength(FTitleSpecs, n);
  SetLength(FTitleFonts, n);
  SetLength(FTitleRt, n);
  glob := RtGlobal;
  for i := 0 to n - 1 do
  begin
    FTitleSpecs[i] := TyTitleSpecOf(FOption, i);
    { the title's 18px bold and both lines' colours are its own defaults;
      the subtitle's 12px is too, its weight is not }
    FTitleFonts[i][0] := TitleFontOf(i, 'TyAdvChartTitle', 'textStyle', [ttpFamily]);
    FTitleFonts[i][1] := TitleFontOf(i, 'TyAdvChartSubtitle', 'subtextStyle',
      [ttpWeight, ttpFamily]);
    { THE TWO LINES' TEXT BLOCKS: textStyle's and subtextStyle's `rich`, size
      and overflow -- never a box, which upstream disables for the title
      (install.ts:166-182) -- measured as the blocks they are and laid out
      about the anchors the layout gives them [Batch 86] }
    for line := 0 to 1 do
    begin
      rts[line] := Default(TTyRtBlockStyle);
      node := FOption.ComponentAt('title', i);
      if node is TJSONObject then
      begin
        if line = 0 then st := TJSONObject(node).Find('textStyle')
        else st := TJSONObject(node).Find('subtextStyle');
        if (st is TJSONObject) and TyRtNodeWantsBlock(TJSONObject(st)) then
          rts[line] := TyRtResolve([TJSONObject(st)], glob,
            TyRtResolveOpt(False, True));
      end;
      meters[line] := nil;
      if rts[line].Needed then
        meters[line] := TyRtBlockMeasurer(AMeasurer, rts[line], glob, APPI / 96);
    end;
    FTitles[i] := TyLayoutTitle(FTitleSpecs[i], FLastRect, AMeasurer,
      FTitleFonts[i][0], FTitleFonts[i][1], APPI, meters[0], meters[1]);
    for line := 0 to 1 do
    begin
      FTitleRt[i][line] := Default(TTyRtDrawn);
      if not rts[line].Needed or not FTitles[i].Valid then Continue;
      if (line = 1) and not FTitles[i].HasSub then Continue;
      if (line = 0) and (FTitleSpecs[i].Text = '') then Continue;
      b := rts[line];
      TyRtFinish(b, FTitleFonts[i][line].Name, FTitleFonts[i][line].SizeLogical,
        FTitleFonts[i][line].Weight, glob, False, 0);
      { the line's own ink over the block, the skin's at paint time where
        none was written -- as the title's fixed fill is }
      b.Style.HasFill := FTitleFonts[i][line].HasColour;
      b.Style.FillNone := False;
      b.Style.Fill := FTitleFonts[i][line].Colour;
      case FTitles[i].Align of
        ttaCentre: ah := tahCentre;
        ttaRight: ah := tahRight;
      else
        ah := tahLeft;
      end;
      case FTitles[i].VAlign of
        ttvMiddle: av := tavMiddle;
        ttvBottom: av := tavBottom;
      else
        av := tavTop;
      end;
      if line = 0 then
        FTitleRt[i][line].Pieces := TyRtLay(FTitleSpecs[i].Text, b,
          TyRtDefaultOf(False, 0, False, 0, False, ah, av), APPI / 96, AMeasurer)
      else
        FTitleRt[i][line].Pieces := TyRtLay(FTitleSpecs[i].Subtext, b,
          TyRtDefaultOf(False, 0, False, 0, False, ah, av), APPI / 96, AMeasurer);
      if line = 0 then
      begin
        FTitleRt[i][line].X := FTitles[i].TextX;
        FTitleRt[i][line].Y := FTitles[i].TextY;
      end
      else
      begin
        FTitleRt[i][line].X := FTitles[i].SubX;
        FTitleRt[i][line].Y := FTitles[i].SubY;
      end;
      FTitleRt[i][line].RotationRad := 0;
      FTitleRt[i][line].Scale := APPI / 96;
    end;
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
  { the dispatch's triggerUpdatedEvent [Batch 97] }
  EmitUpdated;
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
  { THE TREES, on the same terms: a tree's view is the same View [Batch 82] }
  for i := 0 to High(FTreeViews) do
  begin
    if FTreeViews[i] = nil then Continue;
    sp := FTreeSpecs[i];
    if AZoom then ok := sp.Roam in [grmZoom, grmBoth]
    else ok := sp.Roam in [grmPan, grmBoth];
    if not ok then Continue;
    if not (sp.RoamGlobal or FTreeViews[i].ContainTrigger(AX, AY)) then Continue;
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

function TTyAdvanceChart.IsTreeSeries(ASeriesIndex: Integer): Boolean;
var slot: Integer;
begin
  slot := SlotOfSeries(ASeriesIndex);
  Result := (slot >= 0) and (FBindings[slot].SeriesType = TyTreeSeriesTypeName);
end;

procedure TTyAdvanceChart.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  d: TTyChartDatumRef;
  el, slot, k: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if csDesigning in ComponentState then Exit;
  EventDown(Button, X, Y);
  { A MIDDLE OR RIGHT PRESS NEITHER ARMS NOR DISARMS. }
  if Button <> mbLeft then Exit;
  FRoamSeries := -1;
  { THE PRESS A CLICK IS JUDGED AGAINST, before anything else claims it }
  FPressDatum := HitTestAt(X, Y, el);
  FPressCaption := (el >= 0) and (FPaintList <> nil)
    and (FPaintList.Element(el).Caption.FontSizeLogical > 0);
  FPressX := X;
  FPressY := Y;
  FPressArmed := True;
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
var
  d: TTyChartDatumRef;
  el, slot: Integer;
  cap: Boolean;
  n: TJSONData;
begin
  if Button = mbLeft then
  begin
    FRoamSeries := -1;
    { the target under the release, before anything moves }
    d := HitTestAt(X, Y, el);
    cap := (el >= 0) and (FPaintList <> nil)
      and (FPaintList.Element(el).Caption.FontSizeLogical > 0);
    { zrender's mouseup, then the DOM click at the same point }
    DataZoomPointer(dpUp, X, Y, Shift, 0);
    DataZoomPointer(dpClick, X, Y, Shift, 0);
    { A CLICK: pressed and released on the same thing -- the same datum, a
      node's disc and its label being different things -- within 4 px. On a
      tree node whose series says `expandAndCollapse: true`, it toggles.
      [Batch 81] }
    if FPressArmed and (d.SeriesIndex >= 0) and not d.IsEdge
      and (d.SeriesIndex = FPressDatum.SeriesIndex)
      and (d.DataIndex = FPressDatum.DataIndex) and not FPressDatum.IsEdge
      and (cap = FPressCaption)
      and (Sqrt(Sqr(X - FPressX) + Sqr(Y - FPressY)) <= 4) then
    begin
      slot := SlotOfSeries(d.SeriesIndex);
      if (slot >= 0) and (FBindings[slot].SeriesType = TyTreeSeriesTypeName) then
      begin
        n := FOption.ComponentAt('series', d.SeriesIndex);
        if (n <> nil) and (n.JSONType = jtObject) then
        begin
          n := TJSONObject(n).Find('expandAndCollapse');
          { absent is the default, true; anything but JSON true is off }
          if (n = nil) or ((n.JSONType = jtBoolean) and n.AsBoolean) then
            TreeToggle(d.SeriesIndex, d.DataIndex);
        end;
      end;
    end;
    FPressArmed := False;
  end;
  if not (csDesigning in ComponentState) then EventUp(Button, X, Y);
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TTyAdvanceChart.CaptureChanged;
begin
  { THE BUTTON CAME UP SOMEWHERE THIS CONTROL WILL NOT HEAR OF, or another
    window took the mouse. Either way the drag is over. A dataZoom's ends as
    a mouseup where the pointer was last would end it -- its commit and all;
    the widgetset's own mouseup, when it follows, finds nothing to end. }
  FRoamSeries := -1;
  FPressArmed := False;
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
  if IsTreeSeries(si) then Result := TreeZoom(si, s, MousePos.X, MousePos.Y)
  else Result := GraphZoom(si, s, MousePos.X, MousePos.Y);
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

function TTyAdvanceChart.TitleCount: Integer;
begin
  Result := Length(FTitles);
end;

function TTyAdvanceChart.TitleLayoutOf(AIndex: Integer): TTyTitleLayout;
begin
  Result := Default(TTyTitleLayout);
  if (AIndex >= 0) and (AIndex <= High(FTitles)) then Result := FTitles[AIndex];
end;

function TTyAdvanceChart.TitleFontUsed(AIndex, ALine: Integer): TTyTitleFont;
begin
  Result := Default(TTyTitleFont);
  if (AIndex >= 0) and (AIndex <= High(FTitleFonts)) and (ALine in [0, 1]) then
    Result := FTitleFonts[AIndex][ALine];
end;

function TTyAdvanceChart.TitleRt(AIndex, ALine: Integer): TTyRtDrawn;
begin
  Result := Default(TTyRtDrawn);
  if (AIndex >= 0) and (AIndex <= High(FTitleRt)) and (ALine in [0, 1]) then
    Result := FTitleRt[AIndex][ALine];
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
    if FBindings[i].SeriesIndex <= High(FTreeToggled) then
      FTrees[i] := TyTreeSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI,
        FTreeToggled[FBindings[i].SeriesIndex])
    else
      FTrees[i] := TyTreeSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI);
    if FTrees[i].Valid then SolveTreeView(i, APPI);
  end;
end;

procedure TTyAdvanceChart.SolveTreeView(ASlot, APPI: Integer);
var
  si, row: Integer;
  node: TJSONData;
  root: TJSONObject;
  spec: TTyGraphSpec;
  mnX, mnY, mxX, mxY, one: Double;
  box: TTyXYWH;
  any: Boolean;
  centre: TTyGraphCentre;
  zoom: Double;
begin
  si := FBindings[ASlot].SeriesIndex;
  if Length(FTreeViews) < Length(FBindings) then
  begin
    SetLength(FTreeViews, Length(FBindings));
    SetLength(FTreeSpecs, Length(FBindings));
  end;
  FreeAndNil(FTreeViews[ASlot]);
  { the view's options, read as a graph's; a tree's nodeScaleRatio is 0.4 }
  spec := TyGraphSpecDefault;
  spec.NodeScaleRatio := 0.4;
  node := FOption.ComponentAt('series', si);
  root := nil;
  if FOption.Root is TJSONObject then root := TJSONObject(FOption.Root);
  if (node <> nil) and (node.JSONType = jtObject) then
  begin
    TyGraphReadRoamOptions(TJSONObject(node), root, spec);
    { a tree's roamTrigger defaults to 'global': a drag anywhere pans }
    if TJSONObject(node).Find('roamTrigger') = nil then spec.RoamGlobal := True;
  end;
  spec.Z := FTrees[ASlot].Spec.Z;
  FTreeSpecs[ASlot] := spec;
  { the bounding box of the placed nodes, local to the main group }
  any := False;
  mnX := Infinity; mnY := Infinity; mxX := NegInfinity; mxY := NegInfinity;
  for row := 0 to High(FTrees[ASlot].Pos) do
    if FTrees[ASlot].Pos[row].Placed then
    begin
      any := True;
      if FTrees[ASlot].Pos[row].X < mnX then mnX := FTrees[ASlot].Pos[row].X;
      if FTrees[ASlot].Pos[row].X > mxX then mxX := FTrees[ASlot].Pos[row].X;
      if FTrees[ASlot].Pos[row].Y < mnY then mnY := FTrees[ASlot].Pos[row].Y;
      if FTrees[ASlot].Pos[row].Y > mxY then mxY := FTrees[ASlot].Pos[row].Y;
    end;
  if not any then Exit;
  if APPI > 0 then one := APPI / 96 else one := 1;
  { no extent on an axis: the box the view last had there, else one either
    side }
  if mxX - mnX = 0 then
  begin
    if (si <= High(FTreeBoxHas)) and FTreeBoxHas[si] then
    begin
      mnX := FTreeBox[si].X;
      mxX := FTreeBox[si].X + FTreeBox[si].W;
    end
    else
    begin
      mnX := mnX - one;
      mxX := mxX + one;
    end;
  end;
  if mxY - mnY = 0 then
  begin
    if (si <= High(FTreeBoxHas)) and FTreeBoxHas[si] then
    begin
      mnY := FTreeBox[si].Y;
      mxY := FTreeBox[si].Y + FTreeBox[si].H;
    end
    else
    begin
      mnY := mnY - one;
      mxY := mxY + one;
    end;
  end;
  box := TyXYWH(mnX, mnY, mxX - mnX, mxY - mnY);
  if si > High(FTreeBox) then
  begin
    SetLength(FTreeBox, si + 1);
    SetLength(FTreeBoxHas, si + 1);
  end;
  FTreeBox[si] := box;
  FTreeBoxHas[si] := True;
  FTreeViews[ASlot] := TTyGraphView.CreateXYWH(box, box);
  { the roam's write-back, else the option's }
  if (si <= High(FTreeRoam)) and FTreeRoam[si].Valid then
  begin
    centre := FTreeRoam[si].Centre;
    zoom := FTreeRoam[si].Zoom;
  end
  else
  begin
    centre := spec.Centre;
    zoom := spec.Zoom;
  end;
  FTreeViews[ASlot].SetRoam(centre, zoom, spec.HasLimit, spec.LimitMin, spec.LimitMax);
  TyTreeApplyView(FTrees[ASlot], FTreeViews[ASlot].OverallScaleX,
    FTreeViews[ASlot].OverallX, FTreeViews[ASlot].OverallY,
    FTreeViews[ASlot].NodeScale(spec.NodeScaleRatio));
end;

function TTyAdvanceChart.TreeDispatchRoam(const APayload: TTyGraphRoamPayload): Boolean;
var
  i, si: Integer;
  p: TTyGraphRoamPayload;
  m: ITyTextMeasurer;
begin
  Result := False;
  if APayload.HasZoom and (IsNan(APayload.Zoom) or IsInfinite(APayload.Zoom)
    or (APayload.Zoom <= 0)) then Exit;
  if APayload.HasPan and (IsNan(APayload.DX) or IsNan(APayload.DY)) then Exit;
  for i := 0 to High(FTreeViews) do
  begin
    if FTreeViews[i] = nil then Continue;
    si := FBindings[i].SeriesIndex;
    if (APayload.SeriesIndex >= 0) and (si <> APayload.SeriesIndex) then Continue;
    if Length(FTreeRoam) <= si then SetLength(FTreeRoam, si + 1);
    TyGraphRoamStep(FTreeViews[i], FTreeSpecs[i], APayload, FTreeRoam[si]);
    Result := True;
    if Assigned(FOnTreeRoam) then
    begin
      p := APayload;
      p.SeriesIndex := si;
      FOnTreeRoam(Self, p);
    end;
  end;
  if not Result then Exit;
  { A NEW LAYOUT, AND AT ONCE: the transform is re-derived from what the roam
    wrote back, and the release that ends a short drag must find the node
    where the pan put it -- upstream's elements are the same objects,
    moved. }
  if FLastPPI <= 0 then
  begin
    Invalidate;
    EmitUpdated;
    Exit;
  end;
  m := NewTextMeasurer(FLastPPI);
  Relayout(nil, FLastRect, FLastPPI, m);
  DropStatic;
  BuildSeriesList(m, FLastPPI);
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  inherited Invalidate;
  { the dispatch's triggerUpdatedEvent [Batch 97] }
  EmitUpdated;
end;

function TTyAdvanceChart.TreeRoam(ASeriesIndex: Integer; ADX, ADY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasPan := True;
  p.DX := ADX;
  p.DY := ADY;
  Result := TreeDispatchRoam(p);
end;

function TTyAdvanceChart.TreeZoom(ASeriesIndex: Integer; AScale, AOriginX,
  AOriginY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasZoom := True;
  p.Zoom := AScale;
  p.OriginX := AOriginX;
  p.OriginY := AOriginY;
  Result := TreeDispatchRoam(p);
end;

function TTyAdvanceChart.TreeToggle(ASeriesIndex, ADataIndex: Integer): Boolean;
var i, s: Integer;
begin
  Result := False;
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].SeriesType <> TyTreeSeriesTypeName then Continue;
    s := FBindings[i].SeriesIndex;
    if (ASeriesIndex >= 0) and (s <> ASeriesIndex) then Continue;
    if (i > High(FTrees)) or not FTrees[i].Hier.Valid then Continue;
    if (ADataIndex <= 0) or (ADataIndex > High(FTrees[i].Hier.Nodes)) then Continue;
    if s > High(FTreeToggled) then SetLength(FTreeToggled, s + 1);
    if ADataIndex > High(FTreeToggled[s]) then
      SetLength(FTreeToggled[s], Length(FTrees[i].Hier.Nodes));
    FTreeToggled[s][ADataIndex] := not FTreeToggled[s][ADataIndex];
    { the solved flag too, so TreeExpanded answers before the relayout }
    FTrees[i].Hier.Nodes[ADataIndex].Expanded :=
      not FTrees[i].Hier.Nodes[ADataIndex].Expanded;
    Result := True;
    if Assigned(FOnTreeToggle) then FOnTreeToggle(Self, s, ADataIndex);
  end;
  if Result then
  begin
    Invalidate;
    { the dispatch's triggerUpdatedEvent [Batch 97] }
    EmitUpdated;
  end;
end;

function TTyAdvanceChart.TreeExpanded(ASeriesIndex, ADataIndex: Integer): Boolean;
var slot: Integer;
begin
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FTrees)) or not FTrees[slot].Hier.Valid then Exit;
  if (ADataIndex < 0) or (ADataIndex > High(FTrees[slot].Hier.Nodes)) then Exit;
  Result := FTrees[slot].Hier.Nodes[ADataIndex].Expanded;
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
    { the headers' specs follow the rows' and the breadcrumb's [Batch 78] }
    TyTreemapUpperLabels(FTreemaps[i], Copy(FTreemapInks[i].ItemLabels,
      Length(FTreemaps[i].Nodes) + 1, Length(FTreemaps[i].Nodes)), FStores[i],
      SeriesModelName(FBindings[i].SeriesIndex), dim, AMeasurer);
    TyTreemapBreadcrumb(FTreemaps[i],
      FTreemapInks[i].ItemLabels[Length(FTreemaps[i].Nodes)], AMeasurer,
      FLastRect);
  end;
end;

{ THE SANKEYS: each laid out in its box on the whole canvas, its nodes
  coloured by value over the palette -- the series' `color`, else the
  chart's, else the theme's -- read as zrender parses them, so an alpha
  survives; then the labels placed. [Batch 79] }
procedure TTyAdvanceChart.SolveSankeys(APPI: Integer);
var
  i, k: Integer;
  stops: TTyVisualColorArray;
  d, node: TJSONData;
  base, lk: TTyLabelSpec;
  ls: TTyStyleSet;

  procedure StopsOf(AData: TJSONData);
  var q: Integer;
  begin
    stops := nil;
    if AData.JSONType = jtArray then
    begin
      SetLength(stops, AData.Count);
      for q := 0 to AData.Count - 1 do stops[q] := TyVisualParsedStop(AData.Items[q]);
    end
    else
    begin
      SetLength(stops, 1);
      stops[0] := TyVisualParsedStop(AData);
    end;
  end;

begin
  FSankeys := nil;
  FSankeyInks := nil;
  SetLength(FSankeys, Length(FBindings));
  SetLength(FSankeyInks, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FSankeys[i] := Default(TTySankeySolved);
    FSankeyInks[i] := Default(TTySankeyInk);
    if FBindings[i].SeriesType <> TySankeySeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    FSankeys[i] := TySankeySolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI);
    if not FSankeys[i].Valid then Continue;
    { the palette: series.get('color') falls through to the chart's }
    d := nil;
    node := FOption.ComponentAt('series', FBindings[i].SeriesIndex);
    if (node <> nil) and (node.JSONType = jtObject) then d := TJSONObject(node).Find('color');
    if ((d = nil) or (d.JSONType = jtNull)) and (FOption.Root is TJSONObject) then
      d := TJSONObject(FOption.Root).Find('color');
    if (d <> nil) and (d.JSONType <> jtNull) then
      StopsOf(d)
    else
    begin
      SetLength(stops, 9);
      for k := 0 to 8 do stops[k] := TyVisualFromChart(TTyChartColor(ThemeRampColor(k)));
    end;
    TySankeyColour(FSankeys[i], stops);
    { the labels: outside by default, the chart's own label ink }
    base := LabelBaseFor(i);
    base.Show := True;
    base.DefaultText := tldName;
    FSankeyInks[i].Label_ := TyLabelSpecOf(FOption, FBindings[i].SeriesIndex, base);
    FSankeyInks[i].ItemLabels := TySankeyLabelSpecs(FSankeys[i], FSankeyInks[i].Label_);
    ls := ActiveController.Model.ResolveStyle('TyAdvChartSankeyLink', '', []);
    FSankeyInks[i].LinkColour := TTyChartColor(ls.Background.Color);
    TySankeyLabels(FSankeys[i], SeriesModelName(FBindings[i].SeriesIndex));
  end;
end;

{ A TREEMAP'S INK: its labels in their own key's ink -- white over the
  palette in every mode, never the auto bands -- read item -> level ->
  series; after the rows, the breadcrumb's words, and its chip. }
function TTyAdvanceChart.TreemapInk(ASlot: Integer): TTyTreemapInk;
var
  dummyCol: TTyChartColor;
  base, crumb: TTyLabelSpec;
  ls, cs: TTyStyleSet;
  hs: TTyLabelSpecArray;
  j, k: Integer;
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
  GlobalInk(base.FontName, base.FontSizeLogical, base.FontWeight, dummyCol, [ttpSize, ttpWeight, ttpFamily]);
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
  GlobalInk(crumb.FontName, crumb.FontSizeLogical, crumb.FontWeight, dummyCol, [ttpSize, ttpWeight, ttpFamily]);
  SetLength(Result.ItemLabels, Length(Result.ItemLabels) + 1);
  Result.ItemLabels[High(Result.ItemLabels)] := crumb;
  Result.CrumbFill := TTyChartColor(cs.Background.Color);
  { the parents' headers: outside text in the chart's label ink, a halo of
    the ground [Batch 78] }
  base := LabelBaseFor(ASlot);
  base.Show := True;
  base.DefaultText := tldName;
  hs := TyTreemapUpperSpecs(FTreemaps[ASlot], base);
  k := Length(Result.ItemLabels);
  SetLength(Result.ItemLabels, k + Length(hs));
  for j := 0 to High(hs) do Result.ItemLabels[k + j] := hs[j];
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

procedure TTyAdvanceChart.FreeTreeViews;
var i: Integer;
begin
  for i := 0 to High(FTreeViews) do FreeAndNil(FTreeViews[i]);
  FTreeViews := nil;
  FTreeSpecs := nil;
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
  GlobalInk(Result.NameFontName, Result.NameFontSizeLogical,
    Result.NameFontWeight, Result.NameColour, [ttpSize, ttpWeight, ttpFamily]);
  st := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  Result.LabelFontName := st.FontName;
  Result.LabelFontSizeLogical := ResolveFontSize(st);
  Result.LabelFontWeight := st.FontWeight;
  GlobalInk(Result.LabelFontName, Result.LabelFontSizeLogical,
    Result.LabelFontWeight, Result.LabelColour, [ttpWeight, ttpFamily]);
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
  dummyCol: TTyChartColor;
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
  { a gauge's axis label (12px), title (16px) and detail (30px bold) have
    sizes of their own }
  GlobalInk(Result.LabelFontName, Result.LabelFontSizeLogical,
    Result.LabelFontWeight, dummyCol, [ttpWeight, ttpFamily]);
  f := TitleFont('TyAdvChartLabel');
  GlobalInk(f.Name, f.SizeLogical, f.Weight, dummyCol, [ttpWeight, ttpFamily]);
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
  GlobalInk(f.Name, f.SizeLogical, f.Weight, dummyCol, [ttpFamily]);
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
  dummyCol: TTyChartColor;
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartLabel', '', []);
  Result.FontName := st.FontName;
  Result.FontSizeLogical := ResolveFontSize(st);
  Result.FontWeight := st.FontWeight;
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    dummyCol, [ttpSize, ttpWeight, ttpFamily]);
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
  f0, f1: TTyTitleFont;
  ink0, ink1: TTyColor;

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
    { in the fonts the layout measured -- the author's where written }
    f0 := FTitleFonts[i][0];
    f1 := FTitleFonts[i][1];
    if f0.HasColour then ink0 := TTyColor(f0.Colour) else ink0 := st.TextColor;
    if f1.HasColour then ink1 := TTyColor(f1.Colour) else ink1 := subSt.TextColor;
    { A LINE THAT IS A BLOCK DRAWS ITS PIECES [Batch 86] }
    if (i <= High(FTitleRt)) and (Length(FTitleRt[i][0].Pieces) > 0) then
      TyRenderRtPieces(APainter, FTitleRt[i][0].Pieces, FTitleRt[i][0].X,
        FTitleRt[i][0].Y, 0, FTitleRt[i][0].Scale, 1, True, ink0)
    else if FTitleSpecs[i].Text <> '' then
      APainter.DrawText(
        Hang(lay.TextX, lay.TextY, lay.TextW, lay.TextH, lay.Align, lay.VAlign),
        FTitleSpecs[i].Text, f0.Name, f0.SizeLogical, f0.Weight,
        ink0, LclAlign(lay.Align), tlTop, False, 0, False,
        Pos(#10, FTitleSpecs[i].Text) > 0);
    if (i <= High(FTitleRt)) and (Length(FTitleRt[i][1].Pieces) > 0) then
      TyRenderRtPieces(APainter, FTitleRt[i][1].Pieces, FTitleRt[i][1].X,
        FTitleRt[i][1].Y, 0, FTitleRt[i][1].Scale, 1, True, ink1)
    else if lay.HasSub then
      APainter.DrawText(
        Hang(lay.SubX, lay.SubY, lay.SubW, lay.SubH, lay.Align, lay.VAlign),
        FTitleSpecs[i].Subtext, f1.Name, f1.SizeLogical,
        f1.Weight, ink1, LclAlign(lay.Align), tlTop, False,
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

  { THE NAME THE MODEL KEPT [Batch 95]: a merge that writes no name keeps
    the model's (makeIdAndName's existing.name), and a type change rebuilds
    the series from an option without one -- isNameSpecified: not the dummy }
  Result := FOption.ComponentModelName('series', ASlot);
  if (Result <> '') and (Pos('series' + #0, Result) <> 1) then Exit;
  Result := '';

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
        Result[i].LineWidthLogical := 2
      else
        LegendBorderOf(j, -1, Result[i]);
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
          if Result[i].OwnIcon then Result[i].LineWidthLogical := 2
          else LegendBorderOf(j, k, Result[i]);
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
    { an index hole is no legend: no items, and it filters nothing [Batch 97] }
    if not (FOption.ComponentAt('legend', i) is TJSONObject) then
      FLegendEntries[i] := nil;
    { THE MODEL, ONCE PER OPTION [Batch 93]: init makes `selected`,
      optionUpdated forces single mode's one item ON INTO THE MAP -- an
      update afterwards (a legend action) does not run it again, so what the
      actions leave in the map is what is shown }
    if not FLegendLoaded then
    begin
      TyLegendSelectedNode(FOption, i);
      if FLegendSpecs[i].SelectedMode = tlsSingle then
        TyLegendResolveSingle(FOption, i, FLegendEntries[i], available);
    end;
    FLegendFlags[i] := TyLegendSelected(FOption, i, FLegendEntries[i],
      available, tlsMultiple);
    FLegends[i] := Default(TTyLegendLayout);
  end;
  FLegendLoaded := True;
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

{ A LINE'S END LABEL (LineView._initOrUpdateEndLabel and, for its place
  and words, _endLabelOnDuring at percent 1 -- the call createLineClipPath
  makes to "set to the final frame"): on the last legal point, pushed
  `distance` along the base axis, aligned off it; the value as the words
  ({c} the value, valueAnimation true by default), coloured as the series.
  Its datum is none (the expansion must not take it for a host: it is the
  label), and its tag carries what the clip's during needs.
  NOT HERE: a state's endLabel.show, a rich end label (one run), a step
  line's path (the unstepped one is walked), a line of one point (no run).
  [Batch 92, AN4] }
function TTyAdvanceChart.BuildEndLabel(ASlot: Integer; const AVisual: TTySeriesVisual;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList): Integer;
var
  node, en, d: TJSONData;
  run, el: TTyChartElement;
  i, last, flags, lfi, row: Integer;
  spec: TTyLabelSpec;
  st: TTyEndLabelStep;
  pts: TTyPointFArray;
  cmds: TTyPathCmdArray;
  vals: TTyDoubleArray;
  store: TTyDataStore;
  it: TTyRawItem;
  horiz, inverse, connect, found: Boolean;
  xOrY, dist, dX, dY, x, y, v, w, h: Double;
  tpl, words: string;
  ink, stroke: TTyChartColor;
  strokeW: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
begin
  Result := 0;
  if (AList = nil) or (AMeasurer = nil) or (ASlot > High(FStores)) then Exit;
  store := FStores[ASlot];
  if store = nil then Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (node is TJSONObject) then Exit;
  en := TJSONObject(node).Find('endLabel');
  if not (en is TJSONObject) then Exit;
  d := TJSONObject(en).Find('show');
  if not ((d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean) then Exit;
  { the series' line: its points and its clip }
  found := False;
  run := Default(TTyChartElement);
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = carLineRun)
      and (AList.Element(i).Anim.Series = FBindings[ASlot].SeriesIndex) then
    begin
      run := AList.Element(i);
      found := True;
      Break;
    end;
  if not found then Exit;
  last := TyLastLegalRow(run.Anim.Pts);
  if last < 0 then Exit;
  { the end label's own model over the theme: no series label leaks in;
    distance 8, valueAnimation on (LineSeries' defaults) }
  spec := LabelBaseFor(ASlot);
  spec.Show := True;
  spec.DistanceLogical := 8;
  spec.ValueAnim := True;
  spec := TyLabelSpecOfNode(TJSONObject(en), nil, spec);
  horiz := (Round(run.Anim.G[5]) and 2) <> 0;
  inverse := (Round(run.Anim.G[5]) and 4) <> 0;
  connect := run.Anim.G[10] <> 0;
  { each row's raw value, a number or none }
  SetLength(vals, store.Count);
  for row := 0 to store.Count - 1 do
  begin
    vals[row] := NaN;
    it := store.RawItem(row);
    case it.Shape of
      rshNone:
        if (AVisual.LabelValueDim >= 0) and (AVisual.LabelValueDim < store.DimCount) then
          vals[row] := store.Get(AVisual.LabelValueDim, row);
      rshScalar:
        if it.Scalar.Kind = dvkNumber then vals[row] := it.Scalar.Num;
    end;
  end;
  { the words: the value's template for the last row, else its text }
  tpl := '';
  if spec.ValueAnim then
    tpl := TyLabelValueTemplate(spec.Formatter, spec.HasFormatter, tldValue,
      store, last, AVisual.SeriesName, AVisual.LabelValueDim,
      FBindings[ASlot].SeriesIndex, 'line', AVisual.Fill);
  words := TyLabelText(spec.Formatter, spec.HasFormatter, tldValue, store, last,
    AVisual.SeriesName, AVisual.LabelValueDim, 0, False,
    FBindings[ASlot].SeriesIndex, 'line', AVisual.Fill);
  { the final frame: the clip's leading edge at rest }
  if inverse then
  begin
    if horiz then xOrY := run.Anim.G[0] else xOrY := run.Anim.G[1] + run.Anim.G[3];
  end
  else if horiz then xOrY := run.Anim.G[0] + run.Anim.G[2]
  else xOrY := run.Anim.G[1];
  SetLength(pts, Length(run.Anim.Pts) div 2);
  for i := 0 to High(pts) do
    pts[i] := TyPointF(run.Anim.Pts[i * 2], run.Anim.Pts[i * 2 + 1]);
  cmds := TyPolylinePath(pts, run.Anim.G[8], run.Anim.Mono, connect);
  lfi := 0;
  st := TyEndLabelStep(run.Anim.Pts, cmds, xOrY, horiz, connect, True, lfi);
  if not st.HasPoint then Exit;
  dist := spec.DistanceLogical * APPI / 96;
  if horiz then dX := dist else dX := 0;
  if horiz then dY := 0 else dY := -dist;
  if inverse then
  begin
    dX := dX * -1;
    dY := dY * -1;
  end;
  x := st.X + dX;
  y := st.Y + dY;
  if (tpl <> '') then
  begin
    if st.Interp then
      v := TyAnimInterpolateValue(vals[st.Row0], vals[st.Row1], st.T,
        spec.HasPrecision, spec.Precision)
    else
      v := vals[st.Row0];
    if not IsNan(v) then words := StringReplace(tpl, #1, TyJsNumberToString(v), [rfReplaceAll]);
  end;
  if words = '' then Exit;
  { getEndLabelStateSpecified: off the line along the base axis }
  if horiz then
  begin
    if inverse then ah := tahRight else ah := tahLeft;
    av := tavMiddle;
  end
  else
  begin
    ah := tahCentre;
    if inverse then av := tavTop else av := tavBottom;
  end;
  if spec.HasAlignH then ah := spec.AlignH;
  if spec.HasAlignV then av := spec.AlignV;
  AMeasurer.MeasureLine(words, spec.FontName, spec.FontSizeLogical, spec.FontWeight, w, h);
  el := TyChartElement(TyShapeRect(TyAnchorBox(x, y, w, h, ah, av)));
  el.Caption.Text := words;
  el.Caption.FontName := spec.FontName;
  el.Caption.FontSizeLogical := spec.FontSizeLogical;
  el.Caption.FontWeight := spec.FontWeight;
  TyLabelInk(spec, AVisual.Fill, True, False, False, ink, stroke, strokeW);
  el.Caption.Colour := ink;
  el.Caption.StrokeColour := stroke;
  el.Caption.StrokeWidthLogical := strokeW;
  el.Caption.X := x;
  el.Caption.Y := y;
  el.Caption.AnchorH := ah;
  el.Caption.AnchorV := av;
  el.Caption.ValTpl := tpl;
  el.Z := AVisual.Z;
  el.Z2 := 200;
  el.Silent := True;
  el.Datum := TyChartDatum(-1, -1);
  el.Anim.Role := carEndLabel;
  el.Anim.Series := FBindings[ASlot].SeriesIndex;
  el.Anim.Index := -1;
  el.Anim.Pts := run.Anim.Pts;
  el.Anim.Vals := vals;
  el.Anim.Mono := run.Anim.Mono;
  el.Anim.G[0] := dist;
  flags := 0;
  if horiz then flags := flags or 1;
  if inverse then flags := flags or 2;
  if connect then flags := flags or 4;
  if tpl <> '' then flags := flags or 8;
  if spec.HasPrecision then flags := flags or 16;
  el.Anim.G[1] := flags;
  el.Anim.G[2] := spec.Precision;
  el.Anim.G[3] := run.Anim.G[8];
  AList.Add(el);
  Result := 1;
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

{ ONE LEGEND'S FONT AND TEXT COLOUR: the theme's, the root textStyle over
  it, the legend's own textStyle over that [Batch 83] }
procedure TTyAdvanceChart.LegendTextOf(AIndex: Integer; var AFont: TTyLegendFont;
  var AInk: TTyLegendInk);
var
  node, st, d: TJSONData;
  col: TTyChartColor;
  hasCol: Boolean;
  gcol: Cardinal;
begin
  hasCol := False;
  gcol := 0;
  { a legend's colour is its own default; its font is not }
  GlobalTextOver(AFont.Name, AFont.SizeLogical, AFont.Weight, hasCol, gcol, [ttpSize, ttpWeight, ttpFamily]);
  if hasCol then AInk.Text := TTyChartColor(gcol);
  AFont.RtGlobal := RtGlobal;
  AFont.Rt := Default(TTyRtBlockStyle);
  node := FOption.ComponentAt('legend', AIndex);
  if not (node is TJSONObject) then Exit;
  { AN UNSELECTED ITEM'S COLOURS: inactiveColor (its words and its icon),
    inactiveBorderColor (its pen) and the rule's lineStyle.inactiveColor /
    inactiveWidth, over the theme's inactive ink [Batch 93] }
  d := TJSONObject(node).Find('inactiveColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.Inactive := col;
  d := TJSONObject(node).Find('inactiveBorderColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.InactiveBorder := col;
  { the pager's colours [Batch 98] }
  d := TJSONObject(node).Find('pageIconColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.PageIcon := col;
  d := TJSONObject(node).Find('pageIconInactiveColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.PageIconInactive := col;
  st := TJSONObject(node).Find('pageTextStyle');
  if st is TJSONObject then
  begin
    d := TJSONObject(st).Find('color');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
      AInk.PageText := col;
  end;
  st := TJSONObject(node).Find('lineStyle');
  if st is TJSONObject then
  begin
    d := TJSONObject(st).Find('inactiveColor');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
      AInk.LineInactive := col;
    d := TJSONObject(st).Find('inactiveWidth');
    if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat >= 0) then
      AInk.LineInactiveWidth := d.AsFloat;
  end;
  st := TJSONObject(node).Find('textStyle');
  if not (st is TJSONObject) then Exit;
  { the items' text block: free text [Batch 86] }
  if TyRtNodeWantsBlock(TJSONObject(st)) then
    AFont.Rt := TyRtResolve([TJSONObject(st)], AFont.RtGlobal,
      TyRtResolveOpt(False));
  d := TJSONObject(st).Find('fontFamily');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
    AFont.Name := d.AsString;
  AFont.SizeLogical := TyOptFontSize(TJSONObject(st).Find('fontSize'),
    AFont.SizeLogical);
  AFont.Weight := TyFontWeightOf(TJSONObject(st).Find('fontWeight'), AFont.Weight);
  d := TJSONObject(st).Find('color');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.Text := col;
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
  { upstream's three inactive defaults are the one disabled token; the rule
    is 2 wide [Batch 93] }
  Result.InactiveBorder := Result.Inactive;
  Result.LineInactive := Result.Inactive;
  Result.LineInactiveWidth := 2;
  { the pager [Batch 98] }
  Result.PageIcon := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendPageIcon', '', []).TextColor);
  Result.PageIconInactive := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendPageIconInactive', '', []).TextColor);
  Result.PageText := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendPageText', '', []).TextColor);
  { The hole in a ring is the chart's own ground, the same substitution the
    mark builders make for a datum's `empty` marker. }
  Result.EmptyFill := TTyChartColor(
    model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
end;

function TTyAdvanceChart.LegendDeco(AIndex: Integer;
  const AMeasurer: ITyTextMeasurer): TTyLegendDeco;
var
  model: TTyStyleModel;
  st, stH, stP: TTyStyleSet;
  node, d: TJSONData;
  sel, em, pts, defs: TJSONObject;
  g: TTyRtGlobal;
  fam: string;
  size, weight: Integer;
  ink, inkH, col: TTyChartColor;
  hasCol: Boolean;
  gcol: Cardinal;
begin
  Result := Default(TTyLegendDeco);
  Result.Measurer := AMeasurer;
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartLegendSelector', '', []);
  stH := model.ResolveStyle('TyAdvChartLegendSelector', '', [tysHover]);
  stP := model.ResolveStyle('TyAdvChartLegendPageText', '', []);
  sel := nil;
  em := nil;
  pts := nil;
  node := FOption.ComponentAt('legend', AIndex);
  if node is TJSONObject then
  begin
    d := TJSONObject(node).Find('selectorLabel');
    if d is TJSONObject then sel := TJSONObject(d);
    d := TJSONObject(node).Find('emphasis');
    if d is TJSONObject then
    begin
      d := TJSONObject(d).Find('selectorLabel');
      if d is TJSONObject then em := TJSONObject(d);
    end;
    d := TJSONObject(node).Find('pageTextStyle');
    if d is TJSONObject then pts := TJSONObject(d);
  end;

  { THE SELECTOR BUTTONS: selectorLabel over its defaults -- the box
    (padding [3, 5, 3, 5], a 1 px border, radius 10) as upstream writes it,
    the font and the inks the skin's. Its own fontSize and family are
    defaults upstream, so the root textStyle's never reach it. }
  fam := st.FontName;
  size := ResolveFontSize(st);
  weight := st.FontWeight;
  if sel <> nil then
  begin
    d := sel.Find('fontFamily');
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
      fam := d.AsString;
    size := TyOptFontSize(sel.Find('fontSize'), size);
    weight := TyFontWeightOf(sel.Find('fontWeight'), weight);
  end;
  ink := TTyChartColor(st.TextColor);
  inkH := TTyChartColor(stH.TextColor);
  if em <> nil then
  begin
    d := em.Find('color');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
      inkH := col;
  end;
  g := RtGlobal;
  { no root colour: an unwritten one is the skin's, bound below }
  g.HasColour := False;
  defs := TJSONObject(GetJSON('{"padding":[3,5,3,5],"borderWidth":1,"borderRadius":10}'));
  try
    Result.SelBlock := TyRtResolve([sel, defs], g, TyRtResolveOpt(False));
  finally
    defs.Free;
  end;
  if not (Result.SelBlock.Style.HasBorderColor or Result.SelBlock.Style.BorderColorInherit) then
  begin
    Result.SelBlock.Style.HasBorderColor := True;
    Result.SelBlock.Style.BorderColor := TTyChartColor(st.BorderColor);
  end;
  Result.SelBlock.Needed := True;
  Result.SelEmphBlock := Result.SelBlock;
  TyRtFinish(Result.SelBlock, fam, size, weight, g, True, ink);
  TyRtFinish(Result.SelEmphBlock, fam, size, weight, g, True, inkH);
  { emphasis.selectorLabel is only a colour: the state changes the fill }
  Result.SelEmphBlock.Style.HasFill := True;
  Result.SelEmphBlock.Style.FillNone := False;
  Result.SelEmphBlock.Style.Fill := inkH;

  { THE PAGE TEXT: getFont -- pageTextStyle, else the root textStyle, else
    the skin's }
  Result.PageFontName := stP.FontName;
  Result.PageFontSize := ResolveFontSize(stP);
  Result.PageFontWeight := stP.FontWeight;
  hasCol := False;
  gcol := 0;
  GlobalTextOver(Result.PageFontName, Result.PageFontSize, Result.PageFontWeight,
    hasCol, gcol, [ttpSize, ttpWeight, ttpFamily]);
  if pts <> nil then
  begin
    d := pts.Find('fontFamily');
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
      Result.PageFontName := d.AsString;
    Result.PageFontSize := TyOptFontSize(pts.Find('fontSize'), Result.PageFontSize);
    Result.PageFontWeight := TyFontWeightOf(pts.Find('fontWeight'), Result.PageFontWeight);
  end;
end;

procedure TTyAdvanceChart.SolveLegends(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i: Integer;
  fnt: TTyLegendFont;
  ink: TTyLegendInk;
begin
  if Length(FLegendSpecs) = 0 then Exit;
  for i := 0 to High(FLegendSpecs) do
  begin
    fnt := LegendFont;
    ink := LegendInk;
    LegendTextOf(i, fnt, ink);
    { a block is measured as the block it is drawn as [Batch 86]; the
      selector and the pager measure their own [Batch 98] }
    FLegends[i] := TyLayoutLegend(FLegendSpecs[i], FLegendEntries[i],
      FLegendFlags[i], LegendSources(FLegendEntries[i]), FLastRect,
      TyRtBlockMeasurer(AMeasurer, fnt.Rt, fnt.RtGlobal, APPI / 96), fnt, APPI,
      LegendDeco(i, AMeasurer));
  end;
  LegAnimSync;
end;

function TTyAdvanceChart.BuildLegends(APPI: Integer;
  AList: TTyPaintList; const AMeasurer: ITyTextMeasurer): Integer;
var
  i, hov, k: Integer;
  lay: TTyLegendLayout;
  dx, dy: Double;
  ink: TTyLegendInk;
  fnt: TTyLegendFont;
begin
  Result := 0;
  if Length(FLegends) = 0 then Exit;
  for i := 0 to High(FLegends) do
  begin
    ink := LegendInk;
    fnt := LegendFont;
    LegendTextOf(i, fnt, ink);
    if FLegendSelHoverLegend = i then hov := FLegendSelHoverIdx else hov := -1;
    lay := FLegends[i];
    { [Batch 98] THE SCROLL IN FLIGHT: the items where the content group is
      now, not where the page will leave it }
    if lay.IsScroll and (i <= High(FLegProxies)) and (FLegProxies[i] <> nil) then
    begin
      dx := FLegProxies[i].Num('x') - lay.ContentPosX;
      dy := FLegProxies[i].Num('y') - lay.ContentPosY;
      if IsNan(dx) then dx := 0;
      if IsNan(dy) then dy := 0;
      if (dx <> 0) or (dy <> 0) then
      begin
        lay.Items := Copy(lay.Items);
        for k := 0 to High(lay.Items) do
        begin
          if not TyRectFIsValid(lay.Items[k].Bounds) then Continue;
          lay.Items[k].IconBox := TyRectF(lay.Items[k].IconBox.Left + dx,
            lay.Items[k].IconBox.Top + dy, lay.Items[k].IconBox.Right + dx,
            lay.Items[k].IconBox.Bottom + dy);
          lay.Items[k].Bounds := TyRectF(lay.Items[k].Bounds.Left + dx,
            lay.Items[k].Bounds.Top + dy, lay.Items[k].Bounds.Right + dx,
            lay.Items[k].Bounds.Bottom + dy);
          lay.Items[k].TextX := lay.Items[k].TextX + dx;
          lay.Items[k].TextY := lay.Items[k].TextY + dy;
        end;
      end;
    end;
    Inc(Result, TyBuildLegendMarks(FLegendSpecs[i], lay, ink, fnt,
      APPI, AList, i, AMeasurer, hov));
  end;
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
  { the loop's own [Batch 92] }
  d := TJSONObject(re).Find('period');
  if (d <> nil) and (d.JSONType = jtNumber) then AVisual.RipplePeriod := d.AsFloat;
  d := TJSONObject(re).Find('scale');
  if (d <> nil) and (d.JSONType = jtNumber) then AVisual.RippleScale := d.AsFloat;
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
  hasCol: Boolean;
  col: Cardinal;
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
  { the root textStyle's font; not its colour, which a label attached to its
    mark never takes [Batch 83] }
  hasCol := False;
  col := 0;
  GlobalTextOver(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    hasCol, col, [ttpSize, ttpWeight, ttpFamily]);
  Result.OutsideColour := TTyChartColor(outS.TextColor);
  Result.InsideColour[0] := TTyChartColor(lightS.TextColor);
  Result.InsideColour[1] := TTyChartColor(midS.TextColor);
  Result.InsideColour[2] := TTyChartColor(darkS.TextColor);
  LabelGround(Result.Ground, Result.GroundDark);
  Result.RtGlobal := RtGlobal;
end;

function TTyAdvanceChart.LabelSpecFor(ASlot: Integer;
  const ADefaultFormatter: string): TTyLabelSpec;
var
  base: TTyLabelSpec;
  outS, lightS, midS, darkS: TTyStyleSet;
  hasCol: Boolean;
  col: Cardinal;
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
  hasCol := False;
  col := 0;
  GlobalTextOver(base.FontName, base.FontSizeLogical, base.FontWeight,
    hasCol, col, [ttpSize, ttpWeight, ttpFamily]);
  base.OutsideColour := TTyChartColor(outS.TextColor);
  base.InsideColour[0] := TTyChartColor(lightS.TextColor);
  base.InsideColour[1] := TTyChartColor(midS.TextColor);
  base.InsideColour[2] := TTyChartColor(darkS.TextColor);
  LabelGround(base.Ground, base.GroundDark);
  base.RtGlobal := RtGlobal;
  if ASlot > High(FBindings) then Exit(base);
  { A LINE'S LABEL GOES ABOVE ITS POINT -- the one series type that declares
    a default position; every other falls to `inside`. [Revised in batch 47:
    a line's label sat inside its symbol.] }
  if FBindings[ASlot].SeriesType = 'line' then base.Position := tlpTop;
  Result := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
end;

function TTyAdvanceChart.PieLabelInk: TTyPieLabelInk;
var
  dummyCol: TTyChartColor;
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
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    dummyCol, [ttpSize, ttpWeight, ttpFamily]);
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
      if FBindings[i].SeriesType = TySankeySeriesTypeName then
      begin
        if (i <= High(FSankeys)) and FSankeys[i].Valid then
        begin
          Inc(drawn, TyBuildSankeyMarks(FBindings[i].SeriesIndex, FSankeys[i],
            FSankeyInks[i], list));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := FSankeyInks[i].Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := FSankeyInks[i].ItemLabels;
        end;
        Continue;
      end;
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
      v.PxScale := APPI / 96;
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
        or (FBindings[i].SeriesType = 'effectScatter')
        or (FBindings[i].SeriesType = 'bar') or (FBindings[i].SeriesType = 'line')
        or (FBindings[i].SeriesType = 'pictorialBar') then
      begin
        { a symbol's own label over its series' [Batch 71]; a bar's, a
          line point's and a pictorial bar's too [Batch 82] }
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
      v.SeriesIndex := FBindings[i].SeriesIndex;
      v.SeriesType := FBindings[i].SeriesType;
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
      if FBindings[i].SeriesType = 'line' then
        Inc(drawn, BuildEndLabel(i, v, AMeasurer, APPI, list));
    end;
    { THE EXPANSION RUNS ONCE, HERE, AND NOTHING IS APPENDED AFTER IT. Each
      caption's geometry is frozen from its host at this moment and the list
      has no update path, so a mark added later would have no label and a mark
      moved later would leave its label behind. }
    if drawn > 0 then
      TyExpandLabels(list, specs, itemSpecs, AMeasurer, APPI);
    { A SILENT SERIES TAKES NO POINTER: nothing of it -- marks, labels -- is
      hit, hovered or clicked (upstream's series `silent`) [Batch 84] }
    if drawn > 0 then SilenceSeries(list);
    { AFTER THE LABELS, so a caption dims and rises with its node. }
    if drawn > 0 then ApplyGraphHover(list, APPI);
    if drawn > 0 then ApplyTreeHover(list, APPI);
    { THE STATES, onto the elements just built [Batch 88] -- and with
      nothing drawn too: a legend can switch every series off, and their
      records go with their elements [Batch 93] }
    StSync(list, APPI);
    { THE LEGEND GOES IN AFTER THE EXPANSION, and it is allowed to because
      its captions are ANSWERS rather than requests -- they arrive with a
      font and an anchor already on them, which is what the expansion exists
      to supply. A MARK appended here would silently lose its label. }
    { MARKERS arrive as answers too: their labels are placed by Line.ts's own
      table, not by the expansion }
    Inc(drawn, BuildMarkers(AMeasurer, list));
    Inc(drawn, BuildLegends(APPI, list, AMeasurer));
    Inc(drawn, BuildVisualMaps(list));
    Inc(drawn, BuildDataZooms(list));
    Result := drawn;
  end;
end;

procedure TTyAdvanceChart.PaintSeries(APainter: TTyPainter;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
var drawn: Integer;
begin
  { BUILD, THEN DRAW. The list stays afterwards -- see FPaintList. }
  drawn := BuildSeriesList(AMeasurer, APPI);
  AnimAfterBuild;
  { the states on their proxies, then the armed option's flush [Batch 94] }
  StAnimSync;
  AnimFlushArmed;
  { IN MOTION, THE SERIES ARE THE DYNAMIC LAYER'S: a static layer holding
    them would freeze the first frame under every later one (Q7). }
  { ONLY LOOPS LEFT: everything but the ripples and their symbols stays
    here [Batch 92] }
  if FAnimContinuous then
  begin
    if drawn > 0 then TyRenderPaintList(APainter, AnimPart(False));
    Exit;
  end;
  if FAnimLive then Exit;
  if drawn > 0 then
    { AT REST, a proxy may still hold a value a unit in the last place off
      the layout -- the frame draws where upstream's element rests }
    if (Length(FAnimBind) > 0) or (Length(FAnimStBind) > 0) then
      TyRenderPaintList(APainter, AnimFrame)
    else
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
  { IN MOTION, WHAT IS DRAWN IS WHAT IS HIT: the frame keeps the list's
    insertion indices, so the element named is the list's [Batch 89] }
  { and AT REST ON A STATE PROXY, where the list keeps the rest values (a
    selected slice is out, a hovered symbol larger) [Batch 94] }
  if FAnimLive or (Length(FAnimStBind) > 0) then
    idx := AnimFrame.HitTestElement(AX, AY, FPaintListPPI)
  else
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
    Result.NameSizeLogical := TyFontSizeFromPx(ASpec.TextSizeLogical);  // CSS px [Batch 83]
    Result.ValueSizeLogical := Result.NameSizeLogical;
  end;

  { UPSTREAM'S OWN HTML RULE -- round(fontSize * 3 / 2) -- and NOT its richText
    one, which is a flat 22 whatever the font is. A library whose themes change
    the type scale cannot carry a constant here: a dense skin at 11px would get
    a box of double-spaced rows and a display skin at 20px would get overlapping
    ones. Recorded as a deliberate divergence. }
  { in the point units the sizes were always given in: a pixel size is
    brought back to its point equivalent first [Batch 83] }
  Result.LineHeightLogical :=
    Round(Max(TyFontPxOf(Result.NameSizeLogical),
      TyFontPxOf(Result.ValueSizeLogical)) * 72 / 96 * 3 / 2);

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
  Result := TyChartBlankParams;
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
    { each cell as String() prints it, for a valueFormatter handler }
    Raws: TTyStringArray;
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
    SetLength(Result.Raws, k + 1);
    Result.Raws[k] := TyJsValueText(ACell, '');
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

{ a tree row's name as upstream converts it: a string, a number's text, or
  nothing }
function TTyAdvanceChart.TreeRowName(ASlot, ARow: Integer): string;
var it, d: TJSONData;
begin
  Result := '';
  it := FTrees[ASlot].Hier.Nodes[ARow].Item;
  if not (it is TJSONObject) then Exit;
  d := TJSONObject(it).Find('name');
  if d = nil then Exit;
  if d.JSONType = jtString then Result := d.AsString
  else if d.JSONType = jtNumber then Result := TyJsNumberToString(d.AsFloat);
end;

{ its value: the first of an array; NaN unless a number }
function TTyAdvanceChart.TreeRowValue(ASlot, ARow: Integer): Double;
var it, d: TJSONData;
begin
  Result := NaN;
  it := FTrees[ASlot].Hier.Nodes[ARow].Item;
  if not (it is TJSONObject) then Exit;
  d := TJSONObject(it).Find('value');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    if d.Count = 0 then Exit;
    d := d.Items[0];
  end;
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function TTyAdvanceChart.TooltipContent(const ADatum: TTyChartDatumRef;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
var
  p: TTyChartCallbackParams;
  seriesName, inlineName, valueText: string;
  haveValue: Boolean;
  slot, i: Integer;
  tv: Double;
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
  { A TREE NODE IS ONE BARE ROW too: its name the path from the real root,
    dotted; its value the first value, and none unless it is a number.
    [Batch 83] }
  if IsTreeDatum(ADatum) and (ADatum.DataIndex > 0)
    and (ADatum.DataIndex <= High(FTrees[slot].Hier.Nodes)) then
  begin
    inlineName := '';
    i := ADatum.DataIndex;
    while i > 0 do
    begin
      if inlineName = '' then inlineName := TreeRowName(slot, i)
      else inlineName := TreeRowName(slot, i) + '.' + inlineName;
      i := FTrees[slot].Hier.Nodes[i].Parent;
    end;
    tv := TreeRowValue(slot, ADatum.DataIndex);
    Result := TTyTooltipBlock.CreateSection('', True);
    Result.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, inlineName, False,
      TyTooltipValueText(tv), IsNan(tv)));
    Exit;
  end;
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
  { valueFormatter REPLACES THE VALUE CELL: upstream calls it in place of
    makeValueReadable, with the value and the raw index. [Batch 82] }
  if (ASpec.ValueFormatter <> '') and haveValue then
  begin
    { SUB-ROWS ARE FORMATTED ONE BY ONE, each with its own value and NO
      index -- upstream's sub-row fragments carry none -- and the item's own
      row gets the empty list. }
    if cells.MultiLine then
    begin
      valueText := TipValueFormatted(ASpec.ValueFormatter, p, '', True);
      for i := 0 to High(cells.Texts) do
        cells.Texts[i] := TipValueFormatted(ASpec.ValueFormatter, p,
          cells.Raws[i], False);
    end
    else
      valueText := TipValueFormatted(ASpec.ValueFormatter, p);
  end;
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

{ valueFormatter's (value, dataIndex): the value as String() prints the
  row's tooltip dimensions -- one scalar, or several joined -- and the RAW
  index, which is what 6.1 passes. }
function TTyAdvanceChart.TipValueFormatted(const AHandler: string;
  const AParams: TTyChartCallbackParams): string;
var
  prm: TTyChartCallbackParams;
  i: Integer;
begin
  prm := AParams;
  prm.ValueText := '';
  if Length(prm.RawCells) > 0 then
    for i := 0 to High(prm.RawCells) do
    begin
      if i > 0 then prm.ValueText := prm.ValueText + ',';
      prm.ValueText := prm.ValueText + TyJsValueText(prm.RawCells[i], '');
    end
  else
    for i := 0 to High(prm.Values) do
    begin
      if i > 0 then prm.ValueText := prm.ValueText + ',';
      prm.ValueText := prm.ValueText + TyChartValueText(prm.Values[i]);
    end;
  Result := TyChartRunHandler(AHandler, TyChartOneParams(prm));
end;

{ the same with the value text given -- a sub-row's own cell, or the empty
  list an item row with sub-rows gets -- and the index only where upstream
  passes one }
function TTyAdvanceChart.TipValueFormatted(const AHandler: string;
  const AParams: TTyChartCallbackParams; const AValueText: string;
  AWithIndex: Boolean): string;
var prm: TTyChartCallbackParams;
begin
  prm := AParams;
  prm.ValueText := AValueText;
  if not AWithIndex then
  begin
    prm.DataIndex := -1;
    prm.RawDataIndex := -1;
  end;
  Result := TyChartRunHandler(AHandler, TyChartOneParams(prm));
end;

{ The root textStyle over a font the theme resolved: family, size (CSS px),
  weight, and the colour free-standing text takes -- each where written. }
procedure TTyAdvanceChart.GlobalTextOver(var AName: string; var ASize,
  AWeight: Integer; var AHasColour: Boolean; var AColour: Cardinal;
  APick: TTyTextPick);
var
  ts, d: TJSONData;
  col: TTyChartColor;
begin
  if FOption = nil then Exit;
  ts := FOption.Find('textStyle');
  if not (ts is TJSONObject) then Exit;
  d := TJSONObject(ts).Find('fontFamily');
  if (ttpFamily in APick) and (d <> nil) and (d.JSONType = jtString)
    and (d.AsString <> '') then
    AName := d.AsString;
  if ttpSize in APick then
    ASize := TyOptFontSize(TJSONObject(ts).Find('fontSize'), ASize);
  if ttpWeight in APick then
    AWeight := TyFontWeightOf(TJSONObject(ts).Find('fontWeight'), AWeight);
  d := TJSONObject(ts).Find('color');
  if (ttpColour in APick) and (d <> nil) and (d.JSONType = jtString)
    and TyTryParseChartColor(d.AsString, col) then
  begin
    AHasColour := True;
    AColour := col;
  end;
end;

function TTyAdvanceChart.RtGlobal: TTyRtGlobal;
var
  st: TTyStyleSet;
  fname: string;
  fsize, fweight: Integer;
  hasCol: Boolean;
  col: Cardinal;
  root: TJSONObject;
begin
  st := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  fname := st.FontName;
  fsize := ResolveFontSize(st);
  fweight := st.FontWeight;
  hasCol := False;
  col := 0;
  GlobalTextOver(fname, fsize, fweight, hasCol, col, [ttpSize, ttpWeight, ttpFamily]);
  root := nil;
  if (FOption <> nil) and (FOption.Root is TJSONObject) then
    root := TJSONObject(FOption.Root);
  Result := TyRtGlobalOf(root, fname, fsize, fweight);
end;

{ An axis text style made what the layout measured: its family and size, its
  weight (an emphasised label keeps the theme's heavier one), and the
  author's colour where one was written. }
procedure TTyAdvanceChart.AxisTextOver(var AStyle: TTyStyleSet;
  const AName: string; ASize, AWeight: Integer; AHasColour: Boolean;
  AColour: Cardinal; AKeepWeight: Boolean);
begin
  AStyle.FontName := AName;
  AStyle.FontSize := ASize;
  Include(AStyle.Present, tpFontSize);
  if not AKeepWeight then AStyle.FontWeight := AWeight;
  if AHasColour then AStyle.TextColor := TTyColor(AColour);
end;

procedure TTyAdvanceChart.AxisTextStyles(ASpec: PTyAxisLayoutSpec;
  out ALabel, APrimary, AName: TTyStyleSet);
var model: TTyStyleModel;
begin
  model := ActiveController.Model;
  ALabel := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  APrimary := model.ResolveStyle('TyAdvChartAxisLabelPrimary', '', []);
  AName := model.ResolveStyle('TyAdvChartAxisName', '', []);
  if ASpec = nil then Exit;
  AxisTextOver(ALabel, ASpec^.FontName, ASpec^.FontSizeLogical, ASpec^.FontWeight,
    ASpec^.HasLabelColour, ASpec^.LabelColour, False);
  { the emphasised label keeps the theme's heavier weight }
  AxisTextOver(APrimary, ASpec^.FontName, ASpec^.FontSizeLogical, ASpec^.FontWeight,
    ASpec^.HasLabelColour, ASpec^.LabelColour, True);
  AxisTextOver(AName, ASpec^.NameFontName, ASpec^.NameFontSizeLogical,
    ASpec^.NameFontWeight, ASpec^.HasNameColour, ASpec^.NameColour, False);
end;

{ ==================== the chart's mouse events [Batch 84] ==================== }

function TTyAdvanceChart.ChartOn(const AType: string;
  AHandler: TTyChartEventHandler; const AQuery: string): Integer;
var
  t: string;
  i: Integer;
begin
  Result := -1;
  t := TyChartEventTypeOf(AType);
  if (t = '') or not Assigned(AHandler) then Exit;
  { THE SAME FUNCTION TWICE FOR ONE TYPE IS KEPT ONCE, whatever the second
    query -- zrender's Eventful.on }
  for i := 0 to High(FEventRegs) do
    if (FEventRegs[i].EventType = t)
      and (TMethod(FEventRegs[i].Handler).Code = TMethod(AHandler).Code)
      and (TMethod(FEventRegs[i].Handler).Data = TMethod(AHandler).Data) then
      Exit(FEventRegs[i].Id);
  Inc(FEventNextId);
  SetLength(FEventRegs, Length(FEventRegs) + 1);
  FEventRegs[High(FEventRegs)].Id := FEventNextId;
  FEventRegs[High(FEventRegs)].EventType := t;
  FEventRegs[High(FEventRegs)].Query := TyEventQueryOf(AQuery);
  FEventRegs[High(FEventRegs)].Handler := AHandler;
  Result := FEventNextId;
end;

procedure TTyAdvanceChart.ChartOff(AId: Integer);
var i, k: Integer;
begin
  for i := 0 to High(FEventRegs) do
    if FEventRegs[i].Id = AId then
    begin
      for k := i to High(FEventRegs) - 1 do FEventRegs[k] := FEventRegs[k + 1];
      SetLength(FEventRegs, Length(FEventRegs) - 1);
      Exit;
    end;
end;

function SeriesIdOf(AOption: TTyChartOption; ASeriesIndex: Integer): string;
var n, d: TJSONData;
begin
  Result := '';
  if AOption = nil then Exit;
  n := AOption.ComponentAt('series', ASeriesIndex);
  if not (n is TJSONObject) then Exit;
  d := TJSONObject(n).Find('id');
  if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then Result := d.AsString;
end;

procedure TTyAdvanceChart.SilenceSeries(AList: TTyPaintList);
var
  silent: array of Boolean;
  i, k: Integer;
  n, d: TJSONData;
  el: TTyChartElement;
  any: Boolean;
begin
  silent := nil;
  SetLength(silent, FOption.ComponentCount('series'));
  any := False;
  for i := 0 to High(silent) do
  begin
    n := FOption.ComponentAt('series', i);
    d := nil;
    if n is TJSONObject then d := TJSONObject(n).Find('silent');
    silent[i] := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
    any := any or silent[i];
  end;
  if not any then Exit;
  for k := 0 to AList.Count - 1 do
  begin
    el := AList.Element(k);
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex < 0)
      or (el.Datum.SeriesIndex > High(silent)) or not silent[el.Datum.SeriesIndex] then
      Continue;
    el.Silent := True;
    AList.SetElement(k, el);
  end;
end;

function TTyAdvanceChart.SeriesEventModel(ASeriesIndex: Integer): TTyEventModel;
var slot: Integer;
begin
  Result := Default(TTyEventModel);
  slot := SlotOfSeries(ASeriesIndex);
  if slot < 0 then Exit;
  Result.Valid := True;
  Result.MainType := 'series';
  Result.SubType := FBindings[slot].SeriesType;
  Result.Index := ASeriesIndex;
  Result.Name := SeriesModelName(ASeriesIndex);
  Result.Id := SeriesIdOf(FOption, ASeriesIndex);
end;

{ A SERIES ITEM'S params: upstream's getDataParams -- the raw index, the value
  as String() prints it (absent when undefined), 'main' for the tree family's
  data type -- or, for the one element that stands for a whole line, the
  series' own params with selfType 'line', and then only when the series
  says triggerEvent. }
function TTyAdvanceChart.SeriesEventTarget(const ADatum: TTyChartDatumRef;
  AElement: Integer): TTyChartEventTarget;
var
  slot: Integer;
  p: TTyChartCallbackParams;
  n, d: TJSONData;
  st: string;
begin
  Result := Default(TTyChartEventTarget);
  Result.Id := AElement + 1;
  if ADatum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if slot < 0 then Exit;
  st := FBindings[slot].SeriesType;
  if ADatum.DataIndex < 0 then
  begin
    n := FOption.ComponentAt('series', ADatum.SeriesIndex);
    d := nil;
    if n is TJSONObject then d := TJSONObject(n).Find('triggerEvent');
    if not ((d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean) then Exit;
    p := TyChartBlankParams;
    p.SelfType := st;
  end
  else
  begin
    p := TooltipParams(ADatum);
    if ADatum.IsEdge then
    begin
      if Length(p.Values) > 0 then p.ValueText := TyChartValueText(p.Values[0]);
    end
    else if p.Raw.Shape <> rshNone then
      p.ValueText := TyRawItemText(p.Raw);
    if p.ValueText = 'undefined' then p.ValueText := '';
    if (st = TyTreemapSeriesTypeName) or (st = TySunburstSeriesTypeName)
      or (st = TyTreeSeriesTypeName) then
      p.DataType := 'main';
  end;
  p.ComponentType := 'series';
  p.ComponentSubType := st;
  p.ComponentIndex := ADatum.SeriesIndex;
  p.SeriesType := st;
  p.SeriesIndex := ADatum.SeriesIndex;
  p.SeriesName := SeriesModelName(ADatum.SeriesIndex);
  p.SeriesId := SeriesIdOf(FOption, ADatum.SeriesIndex);
  Result.HasData := True;
  Result.Params := p;
  Result.Model := SeriesEventModel(ADatum.SeriesIndex);
end;

function TriggersEvent(ANode: TJSONData): Boolean;
var d: TJSONData;
begin
  Result := False;
  if not (ANode is TJSONObject) then Exit;
  d := TJSONObject(ANode).Find('triggerEvent');
  Result := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
end;

function TTyAdvanceChart.EventTargetAt(AX, AY: Integer): TTyChartEventTarget;
const
  cKindWord: array[TTyChartTargetKind] of string = ('series', 'markPoint',
    'markLine', 'markArea', 'legend', 'legend', 'legend');
var
  i, k, g, a, q, idx, slot, nth: Integer;
  lay: TTyTitleLayout;
  r: TTyRectF;
  el: TTyChartElement;
  d: TTyChartDatumRef;
  node: TJSONData;
  gb: TTyGridBuild;
  axObj: TTyAxis;
  spec: PTyAxisLayoutSpec;
  meas: ITyTextMeasurer;
  lblS, priS, nameS: TTyStyleSet;
  fw, fh: Double;
  kind: TTyMarkerKind;
  mk: TTyMkBlock;
  nm, mainT: string;

  function Inside(const AR: TTyRectF): Boolean;
  begin
    Result := (AX >= AR.Left) and (AX <= AR.Right) and (AY >= AR.Top)
      and (AY <= AR.Bottom);
  end;

  function Hung(AXa, AYa, AW, AH: Double; AAlign: TTyTitleAlign;
    AVAlign: TTyTitleVAlign): TTyRectF;
  var l, t: Double;
  begin
    case AAlign of
      ttaCentre: l := AXa - AW / 2;
      ttaRight: l := AXa - AW;
    else
      l := AXa;
    end;
    case AVAlign of
      ttvMiddle: t := AYa - AH / 2;
      ttvBottom: t := AYa - AH;
    else
      t := AYa;
    end;
    Result := TyRectF(l, t, l + AW, t + AH);
  end;

  function Boxed(AXa, AYa, AW, AH: Double; AAH: TTyTextAnchorH;
    AAV: TTyTextAnchorV): TTyRectF;
  var l, t: Double;
  begin
    case AAH of
      tahLeft: l := AXa;
      tahRight: l := AXa - AW;
    else
      l := AXa - AW / 2;
    end;
    case AAV of
      tavTop: t := AYa;
      tavBottom: t := AYa - AH;
    else
      t := AYa - AH / 2;
    end;
    Result := TyRectF(l, t, l + AW, t + AH);
  end;

begin
  Result := Default(TTyChartEventTarget);
  Result.Params := TyChartBlankParams;
  { THE TITLES, over everything but the tooltip: the text and the subtext are
    two targets }
  for i := 0 to High(FTitles) do
  begin
    lay := FTitles[i];
    if not lay.Valid then Continue;
    for k := 0 to 1 do
    begin
      if (k = 1) and not lay.HasSub then Continue;
      if (k = 0) and ((i > High(FTitleSpecs)) or (FTitleSpecs[i].Text = '')) then Continue;
      if k = 0 then r := Hung(lay.TextX, lay.TextY, lay.TextW, lay.TextH, lay.Align, lay.VAlign)
      else r := Hung(lay.SubX, lay.SubY, lay.SubW, lay.SubH, lay.Align, lay.VAlign);
      if not Inside(r) then Continue;
      Result.Id := -(1000 + 2 * i + k);
      if TriggersEvent(FOption.ComponentAt('title', i)) then
      begin
        Result.HasData := True;
        Result.Params.ComponentType := 'title';
        Result.Params.ComponentIndex := i;
        Result.Model.Valid := True;
        Result.Model.MainType := 'title';
        Result.Model.Index := i;
      end;
      Exit;
    end;
  end;
  { THE DISPLAY LIST: series items, their labels, markers, legend items --
    as DRAWN: in motion, or on a state proxy, the frame (its insertion
    indices are the list's) [Batch 94] }
  idx := -1;
  if (FPaintList <> nil) and FPaintListValid then
  begin
    if FAnimLive or (Length(FAnimStBind) > 0) then
      idx := AnimFrame.HitTestElement(AX, AY, FPaintListPPI)
    else
      idx := FPaintList.HitTestElement(AX, AY, FPaintListPPI);
  end;
  if idx >= 0 then
  begin
    el := FPaintList.Element(idx);
    d := el.Datum;
    Result.Id := idx + 1;
    case d.Kind of
      ctkSeries:
        if d.SeriesIndex >= 0 then
        begin
          Result := SeriesEventTarget(d, idx);
          { the dispatcher behind it [Batch 88] }
          Result.HdSeries := d.SeriesIndex;
          Result.HdRow := d.DataIndex;
          Result.HdEdge := d.IsEdge;
          if d.DataIndex >= 0 then Result.HdKind := 1 else Result.HdKind := 2;
        end;
      ctkMarkPoint, ctkMarkLine, ctkMarkArea:
        begin
          slot := SlotOfSeries(d.ComponentIndex);
          if slot < 0 then Exit;
          if d.Kind = ctkMarkPoint then kind := mkPoint
          else if d.Kind = ctkMarkLine then kind := mkLine
          else kind := mkArea;
          { THE MARKER MODEL'S OWN INDEX among its kind, and its HOST's
            series fields: MarkerModel.getDataParams }
          nth := 0;
          for k := 0 to High(FMarkers) do
          begin
            if FMarkers[k].SeriesIndex = d.ComponentIndex then Break;
            if FMarkers[k].Blocks[kind].Present then Inc(nth);
          end;
          Result.HasData := True;
          Result.Params.ComponentType := cKindWord[d.Kind];
          Result.Params.ComponentSubType := '';
          Result.Params.ComponentIndex := nth;
          Result.Params.SeriesType := FBindings[slot].SeriesType;
          Result.Params.SeriesIndex := d.ComponentIndex;
          Result.Params.SeriesName := SeriesModelName(d.ComponentIndex);
          Result.Params.SeriesId := SeriesIdOf(FOption, d.ComponentIndex);
          Result.Params.DataIndex := d.DataIndex;
          Result.Params.RawDataIndex := d.DataIndex;
          for k := 0 to High(FMarkers) do
            if FMarkers[k].SeriesIndex = d.ComponentIndex then
            begin
              mk := FMarkers[k].Blocks[kind];
              if kind = mkPoint then
              begin
                for q := 0 to High(mk.Points) do
                  if mk.Points[q].DataIndex = d.DataIndex then
                  begin
                    if mk.Points[q].E.Name.Kind = mvkStr then
                      Result.Params.Name := mk.Points[q].E.Name.Str
                    else if mk.Points[q].E.Name.Kind = mvkNum then
                      Result.Params.Name := TyChartValueText(mk.Points[q].E.Name.Num);
                    if mk.Points[q].E.Value.Kind = mvkNum then
                      Result.Params.ValueText := TyChartValueText(mk.Points[q].E.Value.Num)
                    else if mk.Points[q].E.Value.Kind = mvkStr then
                      Result.Params.ValueText := mk.Points[q].E.Value.Str;
                  end;
              end;
              Break;
            end;
          { a query is matched against the host series }
          Result.Model := SeriesEventModel(d.ComponentIndex);
          { ITS ECData HAS A dataIndex, the marker's, and the host's
            seriesIndex: a click on it dispatches select for the HOST
            series' item at that index [Batch 88] }
          Result.HdKind := 3;
          Result.HdSeries := d.ComponentIndex;
          Result.HdRow := d.DataIndex;
        end;
      ctkLegend:
        begin
          if (d.ComponentIndex > High(FLegends))
            or (d.DataIndex > High(FLegends[d.ComponentIndex].Items)) then Exit;
          nm := FLegends[d.ComponentIndex].Items[d.DataIndex].Name;
          { THE ITEM GROUP'S OWN HANDLERS, whatever triggerEvent says: a
            series legend when getSeriesByName finds one -- filtered or not --
            a data legend otherwise (LegendView.ts:208-292) [Batch 93] }
          Result.HdKind := 4;
          Result.HdSeries := d.ComponentIndex;
          Result.HdRow := d.DataIndex;
          Result.HdName := nm;
          for k := 0 to FOption.ComponentCount('series') - 1 do
            if SeriesModelName(k) = nm then
            begin
              Result.HdLegendSeries := True;
              Break;
            end;
          node := FOption.ComponentAt('legend', d.ComponentIndex);
          if not TriggersEvent(node) then Exit;
          Result.HasData := True;
          Result.Params.ComponentType := 'legend';
          Result.Params.ComponentIndex := d.ComponentIndex;
          Result.Params.DataIndex := d.DataIndex;
          Result.Params.RawDataIndex := d.DataIndex;
          Result.Params.ValueText := nm;
          { the series the name is, the first that answers to it }
          for k := 0 to High(FBindings) do
            if SeriesModelName(FBindings[k].SeriesIndex) = nm then
            begin
              Result.Params.SeriesIndex := FBindings[k].SeriesIndex;
              Break;
            end;
          Result.Model.Valid := True;
          Result.Model.MainType := 'legend';
          Result.Model.SubType := 'plain';
          if (node is TJSONObject) and (TJSONObject(node).Get('type', '') = 'scroll') then
            Result.Model.SubType := 'scroll';
          Result.Model.Index := d.ComponentIndex;
        end;
      ctkLegendSelector, ctkLegendPager:
        begin
          { [Batch 98] no ECData: an identity and a handler, no event }
          if (d.ComponentIndex < 0) or (d.ComponentIndex > High(FLegends)) then Exit;
          if d.Kind = ctkLegendSelector then Result.HdKind := 5
          else Result.HdKind := 6;
          Result.HdSeries := d.ComponentIndex;
          Result.HdRow := d.DataIndex;
        end;
    end;
    Exit;
  end;
  { THE AXES that say triggerEvent: a label's box, the name's }
  if FBuild = nil then Exit;
  meas := nil;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    for a := 0 to gb.XAxisCount + gb.YAxisCount - 1 do
    begin
      if a < gb.XAxisCount then axObj := gb.XAxis(a)
      else axObj := gb.YAxis(a - gb.XAxisCount);
      if axObj = nil then Continue;
      mainT := axObj.MainType;
      if mainT = '' then mainT := axObj.Dim + 'Axis';
      if not TriggersEvent(FOption.ComponentAt(mainT, axObj.ComponentIndex)) then Continue;
      spec := gb.SpecFor(axObj);
      if spec = nil then Continue;
      AxisTextStyles(spec, lblS, priS, nameS);
      Result.Model.Valid := True;
      Result.Model.MainType := mainT;
      case axObj.AxisType of
        atCategory: Result.Model.SubType := 'category';
        atTime: Result.Model.SubType := 'time';
        atLog: Result.Model.SubType := 'log';
      else
        Result.Model.SubType := 'value';
      end;
      Result.Model.Index := axObj.ComponentIndex;
      Result.Params.ComponentType := mainT;
      Result.Params.ComponentIndex := axObj.ComponentIndex;
      Result.Params.AxisIndex := axObj.ComponentIndex;
      Result.Params.AxisDimension := axObj.Dim;
      if spec^.NamePlacement.Shown
        and Inside(TyRectF(spec^.NamePlacement.Rect.X, spec^.NamePlacement.Rect.Y,
          spec^.NamePlacement.Rect.X + spec^.NamePlacement.Rect.W,
          spec^.NamePlacement.Rect.Y + spec^.NamePlacement.Rect.H)) then
      begin
        Result.Id := -(200000 + g * 100 + a);
        Result.HasData := True;
        Result.Params.TargetType := 'axisName';
        Result.Params.Name := spec^.NamePlacement.Text;
        Exit;
      end;
      for q := 0 to High(spec^.Placements) do
      begin
        if not spec^.Placements[q].Shown then Continue;
        if meas = nil then meas := NewTextMeasurer(FPaintListPPI);
        fw := 0;
        fh := 0;
        if meas <> nil then
          meas.MeasureLine(spec^.Placements[q].Text, lblS.FontName,
            ResolveFontSize(lblS), lblS.FontWeight, fw, fh);
        if not Inside(Boxed(spec^.Placements[q].X, spec^.Placements[q].Y, fw, fh,
          spec^.Placements[q].AnchorH, spec^.Placements[q].AnchorV)) then Continue;
        Result.Id := -(100000 + g * 10000 + a * 1000 + q);
        Result.HasData := True;
        Result.Params.TargetType := 'axisLabel';
        Result.Params.TickIndex := q;
        if axObj.Scale is TTyOrdinalScale then
        begin
          Result.Params.ValueText := TTyOrdinalScale(axObj.Scale).GetLabel(spec^.TickValues[q]);
          Result.Params.DataIndex := Round(TTyOrdinalScale(axObj.Scale).TickToOrdinal(spec^.TickValues[q]));
          Result.Params.RawDataIndex := Result.Params.DataIndex;
        end
        else
          Result.Params.ValueText := TyChartValueText(spec^.TickValues[q]);
        Exit;
      end;
      Result.Model := Default(TTyEventModel);
      Result.Params := TyChartBlankParams;
    end;
  end;
end;

procedure TTyAdvanceChart.EmitChartEvent(const AType: string;
  const ATarget: TTyChartEventTarget; AX, AY: Integer; AHasOffset: Boolean);
var
  ev: TTyChartEvent;
  regs: array of TTyChartEventReg;
  model: TTyEventModel;
  i: Integer;
begin
  ev := Default(TTyChartEvent);
  ev.EventType := AType;
  ev.HasParams := ATarget.HasData;
  if ev.HasParams then ev.Params := ATarget.Params
  else ev.Params := TyChartBlankParams;
  ev.HasOffset := AHasOffset;
  if AHasOffset then
  begin
    ev.OffsetX := AX;
    ev.OffsetY := AY;
  end;
  if ATarget.HasData then model := ATarget.Model
  else model := Default(TTyEventModel);
  if Assigned(FOnChartEvent) then FOnChartEvent(Self, ev);
  { a copy: a handler may register or unregister }
  regs := Copy(FEventRegs);
  for i := 0 to High(regs) do
    if (regs[i].EventType = AType) and TyEventQueryMatches(regs[i].Query, model, ev) then
      regs[i].Handler(Self, ev);
end;

{ zrender's mousemove: an out to what was hovered when the target changes,
  a move to the new one, an over when it changed -- each only where the
  target carries data }
procedure TTyAdvanceChart.EventMove(AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  FEvLastX := AX;
  FEvLastY := AY;
  t := EventTargetAt(AX, AY);
  if (FEvHover.Id <> 0) and (t.Id <> FEvHover.Id) then
  begin
    { echarts' own mouseout first: the dispatcher leaves emphasis [Batch 88] }
    StHoverOut(FEvHover);
    if FEvHover.HasData then EmitChartEvent('mouseout', FEvHover, AX, AY);
  end;
  if t.HasData then EmitChartEvent('mousemove', t, AX, AY);
  if (t.Id <> 0) and (t.Id <> FEvHover.Id) then
  begin
    StHoverOver(t);
    if t.HasData then EmitChartEvent('mouseover', t, AX, AY);
  end;
  FEvHover := t;
end;

procedure TTyAdvanceChart.EventDown(AButton: TMouseButton; AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  FEvLastX := AX;
  FEvLastY := AY;
  t := EventTargetAt(AX, AY);
  { ANY BUTTON: zrender records the press whichever it was }
  FEvDownId := t.Id;
  FEvUpId := t.Id;
  FEvDownArmed := True;
  FEvDownX := AX;
  FEvDownY := AY;
  if t.HasData then EmitChartEvent('mousedown', t, AX, AY);
end;

{ zrender's mouseup, then -- for the left button, as a browser follows it --
  the click: the same target pressed and released, a press point to judge
  it against, within 4 px of it. A click that passes clears the point; one
  that fails does not. }
procedure TTyAdvanceChart.EventUp(AButton: TMouseButton; AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  t := EventTargetAt(AX, AY);
  FEvUpId := t.Id;
  if t.HasData then EmitChartEvent('mouseup', t, AX, AY);
  if AButton <> mbLeft then Exit;
  if (FEvDownId <> FEvUpId) or not FEvDownArmed
    or (Sqrt(Sqr(AX - FEvDownX) + Sqr(AY - FEvDownY)) > 4) then Exit;
  FEvDownArmed := False;
  { THE ELEMENT'S OWN HANDLER BEFORE ANY zr-LEVEL ONE: a legend item's click
    is downplay, legendToggleSelect, highlight [Batch 93] }
  if t.HdKind = 4 then LegendClick(t)
  { [Batch 98] the selector's and the pager's own onclick }
  else if t.HdKind = 5 then LegendSelectorClick(t)
  else if t.HdKind = 6 then LegendPagerClick(t);
  { ECHARTS' OWN CLICK HANDLER FIRST: an item click dispatches select or
    unselect, whatever selectedMode says [Batch 88] }
  StClickSelect(t);
  if t.HasData then EmitChartEvent('click', t, AX, AY);
end;

procedure TTyAdvanceChart.EventDblClick(AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  t := EventTargetAt(AX, AY);
  if t.HasData then EmitChartEvent('dblclick', t, AX, AY);
end;

procedure TTyAdvanceChart.EventContextMenu(AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  t := EventTargetAt(AX, AY);
  if t.HasData then EmitChartEvent('contextmenu', t, AX, AY);
end;

{ THE POINTER LEFT THE CANVAS: an out to what it was over, at the last point
  it was seen, then globalout with nothing -- and what was hovered is
  remembered, so coming back onto it is no over }
procedure TTyAdvanceChart.EventLeave(AX, AY: Integer);
var none: TTyChartEventTarget;
begin
  if FEvHover.Id <> 0 then StHoverOut(FEvHover);
  if (FEvHover.Id <> 0) and FEvHover.HasData then
    EmitChartEvent('mouseout', FEvHover, AX, AY);
  none := Default(TTyChartEventTarget);
  none.Params := TyChartBlankParams;
  EmitChartEvent('globalout', none, 0, 0, False);
end;

procedure TTyAdvanceChart.DblClick;
begin
  inherited DblClick;
  if not (csDesigning in ComponentState) then EventDblClick(FEvLastX, FEvLastY);
end;

procedure TTyAdvanceChart.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
begin
  if not (csDesigning in ComponentState) then
    EventContextMenu(MousePos.X, MousePos.Y);
  inherited DoContextPopup(MousePos, Handled);
end;

{ ==================== element states and the selection [Batch 88] ==================== }

const
  cStNames: array[TTyStName] of string = ('select', 'emphasis', 'blur');

{ A NaN NEVER MEETS A COMPARISON HERE: an ordered compare of a NaN raises
  with the FPU traps on, and a visualMap can hand a mark a NaN size or
  width. }
function StPositive(AValue: Double): Boolean;
begin
  Result := not IsNan(AValue) and (AValue > 0);
end;

function StSameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := A = B;
end;

{ an element's values at rest, as the state machine keeps them: zrender's
  default lineWidth 1 where the port draws no stroke, so a state that only
  names a border colour draws a one-pixel border as upstream does }
procedure StPush(var AArr: TTyIntegerArray; AValue: Integer);
begin
  SetLength(AArr, Length(AArr) + 1);
  AArr[High(AArr)] := AValue;
end;

function StRestOf(const AEl: TTyChartElement): TTyStObject;
begin
  Result := TyStNoObject;
  if AEl.Style.HasFill then TyStSetColor(Result, stkFill, AEl.Style.FillColor)
  else TyStSetNone(Result, stkFill);
  if StPositive(AEl.Style.StrokeWidthLogical) and (AEl.Style.StrokeColor <> 0) then
    TyStSetColor(Result, stkStroke, AEl.Style.StrokeColor)
  else
    TyStSetNone(Result, stkStroke);
  if StPositive(AEl.Style.StrokeWidthLogical) then
    TyStSetNum(Result, stkLineWidth, AEl.Style.StrokeWidthLogical)
  else
    TyStSetNum(Result, stkLineWidth, 1);
  TyStSetNum(Result, stkOpacity, AEl.Style.Alpha);
  TyStSetNum(Result, stkZ2, AEl.Z2);
  TyStSetNum(Result, stkX, 0);
  TyStSetNum(Result, stkY, 0);
  if AEl.Shape.Kind = cskSector then TyStSetNum(Result, stkR, AEl.Shape.R1)
  else TyStSetNum(Result, stkR, 0);
  TyStSetNum(Result, stkScale, 1);
  TyStSetNum(Result, stkIgnore, Ord(AEl.Ignore));
end;

{ a label's: its anchor (the Text's own x / y), its paint order, whether it
  shows; its fill stays absent -- the automatic ink is the port's }
function StLabelRestOf(const AEl: TTyChartElement): TTyStObject;
begin
  Result := TyStNoObject;
  { the label's own opacity: the host's at build, as defaultOpacity hands it
    over [Batch 90] }
  TyStSetNum(Result, stkOpacity, AEl.Style.Alpha);
  TyStSetNum(Result, stkZ2, AEl.Z2);
  TyStSetNum(Result, stkX, AEl.Caption.X);
  TyStSetNum(Result, stkY, AEl.Caption.Y);
  TyStSetNum(Result, stkR, 0);
  TyStSetNum(Result, stkScale, 1);
  TyStSetNum(Result, stkIgnore, Ord(AEl.Ignore));
end;

function StGuideRestOf(const AEl: TTyChartElement): TTyStObject;
begin
  Result := TyStNoObject;
  TyStSetNum(Result, stkOpacity, AEl.Style.Alpha);
  TyStSetNum(Result, stkZ2, AEl.Z2);
  TyStSetNum(Result, stkX, 0);
  TyStSetNum(Result, stkY, 0);
  TyStSetNum(Result, stkR, 0);
  TyStSetNum(Result, stkScale, 1);
  TyStSetNum(Result, stkIgnore, Ord(AEl.Ignore));
end;

procedure StShiftShape(var AShape: TTyChartShape; ADX, ADY: Double);
var i: Integer;
begin
  if (ADX = 0) and (ADY = 0) then Exit;
  AShape.Bounds.Left := AShape.Bounds.Left + ADX;
  AShape.Bounds.Right := AShape.Bounds.Right + ADX;
  AShape.Bounds.Top := AShape.Bounds.Top + ADY;
  AShape.Bounds.Bottom := AShape.Bounds.Bottom + ADY;
  AShape.CX := AShape.CX + ADX;
  AShape.CY := AShape.CY + ADY;
  AShape.RotCX := AShape.RotCX + ADX;
  AShape.RotCY := AShape.RotCY + ADY;
  for i := 0 to High(AShape.Points) do
  begin
    AShape.Points[i].X := AShape.Points[i].X + ADX;
    AShape.Points[i].Y := AShape.Points[i].Y + ADY;
  end;
  for i := 0 to High(AShape.Cmds) do
  begin
    AShape.Cmds[i].X1 := AShape.Cmds[i].X1 + ADX;
    AShape.Cmds[i].Y1 := AShape.Cmds[i].Y1 + ADY;
    AShape.Cmds[i].X2 := AShape.Cmds[i].X2 + ADX;
    AShape.Cmds[i].Y2 := AShape.Cmds[i].Y2 + ADY;
    AShape.Cmds[i].X := AShape.Cmds[i].X + ADX;
    AShape.Cmds[i].Y := AShape.Cmds[i].Y + ADY;
  end;
  if AShape.HasCmdBounds then
  begin
    AShape.CmdBounds.Left := AShape.CmdBounds.Left + ADX;
    AShape.CmdBounds.Right := AShape.CmdBounds.Right + ADX;
    AShape.CmdBounds.Top := AShape.CmdBounds.Top + ADY;
    AShape.CmdBounds.Bottom := AShape.CmdBounds.Bottom + ADY;
  end;
end;

function SameColourKey(const A, B: TTyStObject; AKey: TTyStKey): Boolean;
begin
  Result := (A.Has[AKey] = B.Has[AKey]) and (A.None[AKey] = B.None[AKey])
    and (A.None[AKey] or (A.Color[AKey] = B.Color[AKey]));
end;

{ THE CURRENT VALUES ONTO A MARK. A colour a state did not change is left as
  the build drew it -- a gradient stays a gradient; a lifted colour over a
  gradient fill leaves the gradient too (the port does not lift a ramp). }
procedure StWriteHost(var AEl: TTyChartElement; const AState: TTyStElement;
  AProxied: Boolean);
var c, r: TTyStObject;
begin
  c := AState.Cur;
  r := AState.Rest;
  { ON A PROXY the animatable keys are the frame's: the list keeps the rest
    values, and only the paint order and the visibility are written
    [Batch 94] }
  if AProxied then
  begin
    AEl.Z2 := Round(c.Num[stkZ2]);
    AEl.Ignore := c.Num[stkIgnore] <> 0;
    Exit;
  end;
  if not SameColourKey(c, r, stkFill) then
  begin
    if c.None[stkFill] then AEl.Style.HasFill := False
    else if not (c.Lifted[stkFill] and (AEl.Style.FillGradient.Kind <> cgkNone)) then
    begin
      AEl.Style.HasFill := True;
      AEl.Style.FillColor := c.Color[stkFill];
      AEl.Style.FillGradient := Default(TTyChartGradient);
    end;
  end;
  if not SameColourKey(c, r, stkStroke) then
  begin
    if c.None[stkStroke] then AEl.Style.StrokeColor := 0
    else if not (c.Lifted[stkStroke] and (AEl.Style.StrokeGradient.Kind <> cgkNone)) then
    begin
      AEl.Style.StrokeColor := c.Color[stkStroke];
      AEl.Style.StrokeGradient := Default(TTyChartGradient);
    end;
  end;
  { the width wherever a stroke is drawn -- zrender's own 1 where the build
    had none -- and a changed one anyway }
  if TyStHasColour(c, stkStroke)
    or not StSameNum(c.Num[stkLineWidth], r.Num[stkLineWidth]) then
    AEl.Style.StrokeWidthLogical := c.Num[stkLineWidth];
  if not StSameNum(c.Num[stkOpacity], r.Num[stkOpacity]) then AEl.Style.Alpha := c.Num[stkOpacity];
  AEl.Z2 := Round(c.Num[stkZ2]);
  StShiftShape(AEl.Shape, c.Num[stkX] - r.Num[stkX], c.Num[stkY] - r.Num[stkY]);
  if (AEl.Shape.Kind = cskSector) and not StSameNum(c.Num[stkR], r.Num[stkR]) then
    AEl.Shape.R1 := c.Num[stkR];
  if not StSameNum(c.Num[stkScale], 1) and StPositive(c.Num[stkScale]) then
    AEl.Shape := TyScaleShape(AEl.Shape, c.Num[stkScale]);
  AEl.Ignore := c.Num[stkIgnore] <> 0;
end;

{ A FOLLOWER: another stretch of the host's own path (a candlestick's
  wicks) -- the colours the states changed, the host's opacity and its
  paint order, the same translation [Batch 90] }
procedure StWriteFollower(var AEl: TTyChartElement; const AHost: TTyStElement;
  AProxied: Boolean);
var c, r: TTyStObject;
begin
  c := AHost.Cur;
  r := AHost.Rest;
  if AProxied then
  begin
    AEl.Z2 := AEl.Z2 + Round(c.Num[stkZ2] - r.Num[stkZ2]);
    AEl.Ignore := c.Num[stkIgnore] <> 0;
    Exit;
  end;
  if not SameColourKey(c, r, stkFill) and AEl.Style.HasFill then
  begin
    if c.None[stkFill] then AEl.Style.HasFill := False
    else AEl.Style.FillColor := c.Color[stkFill];
  end;
  if not SameColourKey(c, r, stkStroke) and (AEl.Style.StrokeColor <> 0) then
  begin
    if c.None[stkStroke] then AEl.Style.StrokeColor := 0
    else AEl.Style.StrokeColor := c.Color[stkStroke];
  end;
  if not StSameNum(c.Num[stkLineWidth], r.Num[stkLineWidth]) then
    AEl.Style.StrokeWidthLogical := c.Num[stkLineWidth];
  if not StSameNum(c.Num[stkOpacity], r.Num[stkOpacity]) then
    AEl.Style.Alpha := c.Num[stkOpacity];
  AEl.Z2 := AEl.Z2 + Round(c.Num[stkZ2] - r.Num[stkZ2]);
  StShiftShape(AEl.Shape, c.Num[stkX] - r.Num[stkX], c.Num[stkY] - r.Num[stkY]);
  AEl.Ignore := c.Num[stkIgnore] <> 0;
end;

procedure StWriteLabel(var AEl: TTyChartElement; const AState: TTyStElement;
  AProxied: Boolean);
var c, r: TTyStObject; dx, dy: Double;
begin
  c := AState.Cur;
  r := AState.Rest;
  { on a proxy the place and the opacity are the frame's; the ink is not
    animated (a Text's style animates its opacity only) [Batch 94] }
  if not AProxied then
  begin
    dx := c.Num[stkX] - r.Num[stkX];
    dy := c.Num[stkY] - r.Num[stkY];
    AEl.Caption.X := c.Num[stkX];
    AEl.Caption.Y := c.Num[stkY];
    StShiftShape(AEl.Shape, dx, dy);
  end;
  AEl.Z2 := Round(c.Num[stkZ2]);
  AEl.Ignore := c.Num[stkIgnore] <> 0;
  { blur: the label's opacity, a tenth of it by default [Batch 90] }
  if not AProxied and not StSameNum(c.Num[stkOpacity], r.Num[stkOpacity]) then
    AEl.Style.Alpha := c.Num[stkOpacity];
  { the ink: a colour a state declares, else the hover's own under emphasis }
  if TyStHasColour(c, stkFill) then
  begin
    AEl.Caption.Colour := c.Color[stkFill];
    if Length(AEl.Caption.RtPieces) > 0 then
      AEl.Caption.RtPieces := TyRtReink(AEl.Caption.RtPieces, c.Color[stkFill],
        False, AEl.Caption.StrokeColour, AEl.Caption.StrokeWidthLogical);
  end
  else if stnEmphasis in AState.States then
    TyCaptionToEmphasis(AEl.Caption);
end;

procedure StWriteGuide(var AEl: TTyChartElement; const AState: TTyStElement;
  AProxied: Boolean);
var c, r: TTyStObject;
begin
  c := AState.Cur;
  r := AState.Rest;
  if not AProxied then
    StShiftShape(AEl.Shape, c.Num[stkX] - r.Num[stkX], c.Num[stkY] - r.Num[stkY]);
  AEl.Z2 := Round(c.Num[stkZ2]);
  AEl.Ignore := c.Num[stkIgnore] <> 0;
  if not AProxied and not StSameNum(c.Num[stkOpacity], r.Num[stkOpacity]) then
    AEl.Style.Alpha := c.Num[stkOpacity];
end;

function TTyAdvanceChart.StKindOf(ASlot: Integer): TTyStKind;
var t: string;
begin
  Result := sskNone;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  { a radar's polygons are drawn by a builder of its own, still on the
    overlay; a calendar's scatter and heatmap are the cartesian ones'
    elements [Batch 90] }
  if FBindings[ASlot].RadarIndex >= 0 then Exit;
  t := FBindings[ASlot].SeriesType;
  if t = 'bar' then Result := sskBar
  else if t = TyPieSeriesTypeName then Result := sskPie
  else if (t = 'line') or (t = 'scatter') or (t = 'effectScatter') then
    Result := sskSymbol
  else if t = 'heatmap' then Result := sskRect
  else if t = 'funnel' then Result := sskFunnel
  else if t = 'candlestick' then Result := sskCandle
  else if t = TyPictorialSeriesTypeName then Result := sskPictorial
  else if t = TySunburstSeriesTypeName then Result := sskSunburst;
  { a line on a calendar is not drawn at all }
  if (FBindings[ASlot].CalendarIndex >= 0) and (t = 'line') then Result := sskNone;
end;

function TTyAdvanceChart.StSeriesNode(ASeriesIndex: Integer): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASeriesIndex);
  if d is TJSONObject then Result := TJSONObject(d);
end;

function TTyAdvanceChart.StItemNode(ASeriesIndex, ARaw: Integer): TJSONObject;
var s: TJSONObject; d: TJSONData; slot: Integer;
begin
  Result := nil;
  { A SUNBURST'S DATA IS ITS TREE: the row's own node [Batch 90] }
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FSunbursts)) and FSunbursts[slot].Valid then
  begin
    if (ARaw >= 0) and (ARaw <= High(FSunbursts[slot].Hier.Nodes))
      and (FSunbursts[slot].Hier.Nodes[ARaw].Item is TJSONObject) then
      Result := TJSONObject(FSunbursts[slot].Hier.Nodes[ARaw].Item);
    Exit;
  end;
  s := StSeriesNode(ASeriesIndex);
  if s = nil then Exit;
  d := s.Find('data');
  if not (d is TJSONArray) then Exit;
  if (ARaw < 0) or (ARaw >= TJSONArray(d).Count) then Exit;
  d := TJSONArray(d).Items[ARaw];
  if d is TJSONObject then Result := TJSONObject(d);
end;

{ tokens.color.primary -- the ink a title is written in, which is how the
  skin says it }
function TTyAdvanceChart.StPrimaryInk: TTyChartColor;
begin
  Result := TTyChartColor(ActiveController.Model.ResolveStyle('TyAdvChartTitle',
    '', []).TextColor);
end;

procedure TTyAdvanceChart.StDeclareItem(ASlot, ARaw: Integer;
  AList: TTyPaintList; APPI: Integer);
var
  s, idx: Integer;
  item: PTyStItem;
  host, cap, guide: TTyChartElement;
  nodes: TTyStNodeArray;
  scale, off, mid, dx, dy, ss, half: Double;
  has, bolder, disabled, was, normalShow, stShow, doScale: Boolean;
  base, obj: TTyStObject;
  spec: TTyChartEmphasisSpec;
  n: TTyStName;
  txt: string;
  c: TTyChartColor;
  k: Integer;
begin
  s := FBindings[ASlot].SeriesIndex;
  item := @FSt[s].Rows[ARaw];
  host := AList.Element(FSt[s].HostIdx[ARaw]);
  nodes := StNodes(s, ARaw);
  if APPI > 0 then scale := APPI / 96 else scale := 1;

  { ---- the mark ---- }
  item^.Host.Exists := True;
  item^.Host.IsPath := True;
  { a symbol (a line's, a scatter's): the group dispatches, the path draws
    [Batch 90] }
  item^.HasGroup := FSt[s].Kind = sskSymbol;
  { emphasis.disabled: no hover dispatcher and no default proxy }
  disabled := TyStReadBool(nodes, ['emphasis', 'disabled'], has);
  item^.Host.Proxy := not disabled;
  for n := Low(TTyStName) to High(TTyStName) do item^.Host.HasState[n] := True;
  item^.Host.Rest := StRestOf(host);
  { THE SELECT LOOK the series type brings under what is declared: a bar's
    and a scatter's border in the primary ink (BarSeries.ts:165,
    ScatterSeries.ts:151); a pie's and a line's nothing }
  base := TyStNoObject;
  case FSt[s].Kind of
    sskBar:
      begin
        TyStSetColor(base, stkStroke, StPrimaryInk);
        TyStSetNum(base, stkLineWidth, 2);
      end;
    sskSymbol:
      if not FSt[s].IsLine then TyStSetColor(base, stkStroke, StPrimaryInk);
    { a heatmap's, a funnel's and a pictorial bar's: the border only
      (HeatmapSeries.ts:130, FunnelSeries.ts:200, PictorialBarSeries.ts:173)
      [Batch 90] }
    sskRect, sskFunnel, sskPictorial:
      TyStSetColor(base, stkStroke, StPrimaryInk);
  end;
  item^.Host.Decl[stnSelect] := TyStOverlay(base,
    TyStReadStyle(nodes, 'select', 'itemStyle', bolder));
  item^.Host.Decl[stnEmphasis] := TyStReadStyle(nodes, 'emphasis', 'itemStyle', bolder);
  item^.Host.Decl[stnBlur] := TyStReadStyle(nodes, 'blur', 'itemStyle', bolder);
  if FSt[s].Kind = sskCandle then StDeclareCandle(ASlot, ARaw, nodes, item^.Host);
  { a sunburst blurs to 0.2 unless told (SunburstSeries.ts:274-279) [Batch 90] }
  if (FSt[s].Kind = sskSunburst) and not item^.Host.Decl[stnBlur].Has[stkOpacity] then
    TyStSetNum(item^.Host.Decl[stnBlur], stkOpacity, 0.2);
  dx := 0;
  dy := 0;
  case FSt[s].Kind of
    sskPie:
      begin
        { PieView.ts:128-150: the SERIES' selectedOffset along the mid angle,
          and the emphasis radius the layout's plus scaleSize }
        off := TyStReadNumber([nodes[1]], ['selectedOffset'], has);
        if not has or IsNan(off) then off := 10;
        mid := (host.Shape.StartRad + host.Shape.EndRad) / 2;
        if IsNan(mid) or IsNan(off) then mid := 0;
        dx := TyJsCos(mid) * (off * scale);
        dy := TyJsSin(mid) * (off * scale);
        TyStSetNum(item^.Host.Decl[stnSelect], stkX, dx);
        TyStSetNum(item^.Host.Decl[stnSelect], stkY, dy);
        doScale := TyStReadBool(nodes, ['emphasis', 'scale'], has);
        if not has then doScale := True;
        if doScale then
        begin
          ss := TyStReadNumber(nodes, ['emphasis', 'scaleSize'], has);
          if not has then ss := 5
          else if IsNan(ss) then ss := 0;
          TyStSetNum(item^.Host.Decl[stnEmphasis], stkR, host.Shape.R1 + ss * scale);
        end;
      end;
    sskSymbol:
      begin
        { Symbol.ts:218-357: the path grows by the emphasis ratio }
        spec := TyChartReadEmphasis(nodes[1]);
        if nodes[0] <> nil then
          spec := TyChartMergeEmphasis(spec, TyChartReadEmphasis(nodes[0]));
        half := (host.Shape.Bounds.Bottom - host.Shape.Bounds.Top) / 2;
        if host.Shape.Kind in [cskCircle, cskEllipse] then half := host.Shape.R1;
        { a symbol of no size or a NaN one keeps its size }
        if StPositive(half) then
          TyStSetNum(item^.Host.Decl[stnEmphasis], stkScale,
            TyChartSymbolScaleRatio(spec, half / scale));
      end;
    sskPictorial:
      { emphasis.scale (default false): every glyph a tenth larger about its
        own origin (PictorialBarView.ts:920-924) [Batch 90] }
      if TyStReadBool(nodes, ['emphasis', 'scale'], has) then
        TyStSetNum(item^.Host.Decl[stnEmphasis], stkScale, 1.1);
  end;

  { ---- the other glyphs: the host's declared states on their own rest
    values; a new one takes the host's list [Batch 90] ---- }
  if Length(item^.Parts) <> Length(FSt[s].PartIdx[ARaw]) then
    SetLength(item^.Parts, 0);
  was := Length(item^.Parts) > 0;
  SetLength(item^.Parts, Length(FSt[s].PartIdx[ARaw]));
  for k := 0 to High(item^.Parts) do
  begin
    item^.Parts[k].Exists := True;
    item^.Parts[k].IsPath := True;
    item^.Parts[k].Proxy := item^.Host.Proxy;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      item^.Parts[k].HasState[n] := True;
      item^.Parts[k].Decl[n] := item^.Host.Decl[n];
    end;
    item^.Parts[k].Rest := StRestOf(AList.Element(FSt[s].PartIdx[ARaw][k]));
    if not was then
    begin
      item^.Parts[k].Cur := item^.Parts[k].Rest;
      item^.Parts[k].States := [];
      if item^.Host.States <> [] then
        TyStUseStates(item^.Parts[k], item^.Host.States);
    end;
  end;

  { ---- its label: the host's states, its own select / emphasis / blur
    label style (labelStyle.ts:255-273) ---- }
  idx := FSt[s].LabelIdx[ARaw];
  was := item^.Label_.Exists;
  if (idx < 0) and (FSt[s].Kind = sskPie) then
  begin
    { A PIE ALWAYS OWNS A TEXT (PieView.ts:49-51), hidden when no state shows
      it: it takes its slice's list, a select state of its own (the offset)
      and -- with no emphasis or blur object unless some state's label.show
      created the text's states -- no emphasis lift, but the blur proxy's
      opacity all the same. Nothing of it is drawn. [Batch 90] }
    normalShow := False;
    stShow := False;
    for n := Low(TTyStName) to High(TTyStName) do
      if TyStReadBool(nodes, [cStNames[n], 'label', 'show'], has) and has then
        stShow := True;
    item^.Label_.Exists := True;
    item^.Label_.IsPath := False;
    item^.Label_.Proxy := not disabled;
    item^.Label_.HasState[stnSelect] := True;
    item^.Label_.HasState[stnEmphasis] := stShow;
    item^.Label_.HasState[stnBlur] := stShow;
    obj := TyStNoObject;
    TyStSetNum(obj, stkOpacity, 1);
    TyStSetNum(obj, stkZ2, host.Z2 + 2);
    TyStSetNum(obj, stkX, 0);
    TyStSetNum(obj, stkY, 0);
    TyStSetNum(obj, stkR, 0);
    TyStSetNum(obj, stkScale, 1);
    TyStSetNum(obj, stkIgnore, 1);
    item^.Label_.Rest := obj;
    for n := Low(TTyStName) to High(TTyStName) do
      item^.Label_.Decl[n] := TyStNoObject;
    TyStSetNum(item^.Label_.Decl[stnSelect], stkX, dx);
    TyStSetNum(item^.Label_.Decl[stnSelect], stkY, dy);
    if not was then
    begin
      item^.Label_.Cur := item^.Label_.Rest;
      item^.Label_.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Label_, item^.Host.States);
    end;
  end
  else if idx < 0 then
    item^.Label_ := Default(TTyStElement)
  else
  begin
    cap := AList.Element(idx);
    item^.Label_.Exists := True;
    item^.Label_.IsPath := False;
    item^.Label_.Proxy := not disabled;
    for n := Low(TTyStName) to High(TTyStName) do item^.Label_.HasState[n] := True;
    item^.Label_.Rest := StLabelRestOf(cap);
    normalShow := not cap.Ignore;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      obj := TyStNoObject;
      { ignore = !show only when the state's show differs from the normal one }
      stShow := TyStReadBool(nodes, [cStNames[n], 'label', 'show'], has);
      if has and (stShow <> normalShow) then TyStSetNum(obj, stkIgnore, Ord(not stShow));
      txt := TyStReadString(nodes, [cStNames[n], 'label', 'color'], has);
      if has and (txt <> 'inherit') and (txt <> 'auto')
        and TyTryParseChartColor(txt, c) then
        TyStSetColor(obj, stkFill, c);
      { a declared opacity, the blur proxy's tenth otherwise [Batch 90] }
      ss := TyStReadNumber(nodes, [cStNames[n], 'label', 'opacity'], has);
      if has and not IsNan(ss) then TyStSetNum(obj, stkOpacity, ss)
      { a sunburst's label blurs to 0.1 by its series' default }
      else if (n = stnBlur) and (FSt[s].Kind = sskSunburst) then
        TyStSetNum(obj, stkOpacity, 0.1);
      { a pie's label rides with its slice: the laid-out place plus the offset
        (pie/labelLayout.ts:541-544) }
      if (n = stnSelect) and (FSt[s].Kind = sskPie) then
      begin
        TyStSetNum(obj, stkX, cap.Caption.X + dx);
        TyStSetNum(obj, stkY, cap.Caption.Y + dy);
      end;
      item^.Label_.Decl[n] := obj;
    end;
    if not was then
    begin
      item^.Label_.Cur := item^.Label_.Rest;
      item^.Label_.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Label_, item^.Host.States);
    end;
  end;

  { ---- a pie's label line: translated with the slice ---- }
  idx := FSt[s].GuideIdx[ARaw];
  was := item^.Guide.Exists;
  if idx < 0 then
    item^.Guide := Default(TTyStElement)
  else
  begin
    guide := AList.Element(idx);
    item^.Guide.Exists := True;
    item^.Guide.IsPath := False;
    item^.Guide.Proxy := not disabled;
    for n := Low(TTyStName) to High(TTyStName) do item^.Guide.HasState[n] := True;
    item^.Guide.Rest := StGuideRestOf(guide);
    for n := Low(TTyStName) to High(TTyStName) do
      item^.Guide.Decl[n] := TyStNoObject;
    TyStSetNum(item^.Guide.Decl[stnSelect], stkX, dx);
    TyStSetNum(item^.Guide.Decl[stnSelect], stkY, dy);
    if not was then
    begin
      item^.Guide.Cur := item^.Guide.Rest;
      item^.Guide.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Guide, item^.Host.States);
    end;
  end;
end;

{ CandlestickView.setBoxCommon (CandlestickView.ts:298-325): every state
  takes the colour of the candle's sign from its own itemStyle -- color or
  color0, borderColor or borderColor0, the colour again for a missing border
  -- and the emphasis border is 2 wide unless declared
  (CandlestickSeries.ts:130-134) [Batch 90] }
procedure TTyAdvanceChart.StDeclareCandle(ASlot, ARaw: Integer;
  const ANodes: array of TJSONObject; var AHost: TTyStElement);
var
  st: TTyDataStore;
  inner, cO, cC, sign: Integer;
  o, c, prev: Double;
  n: TTyStName;
  fill, stroke: string;
  hasF, hasS: Boolean;
  col: TTyChartColor;
begin
  if (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  inner := st.IndexOfRawIndex(ARaw);
  cO := st.DimIndexOf('open');
  cC := st.DimIndexOf('close');
  if (inner < 0) or (cO < 0) or (cC < 0) then Exit;
  { the sign as the layout gives it: a doji takes the previous close's }
  o := st.Get(cO, inner);
  c := st.Get(cC, inner);
  if o > c then sign := -1
  else if o < c then sign := 1
  else
  begin
    sign := 1;
    if inner > 0 then
    begin
      prev := st.Get(cC, inner - 1);
      if not IsNan(prev) and (prev > c) then sign := -1;
    end;
  end;
  for n := Low(TTyStName) to High(TTyStName) do
  begin
    if sign > 0 then
    begin
      fill := TyStReadString(ANodes, [cStNames[n], 'itemStyle', 'color'], hasF);
      stroke := TyStReadString(ANodes, [cStNames[n], 'itemStyle', 'borderColor'], hasS);
    end
    else
    begin
      fill := TyStReadString(ANodes, [cStNames[n], 'itemStyle', 'color0'], hasF);
      stroke := TyStReadString(ANodes, [cStNames[n], 'itemStyle', 'borderColor0'], hasS);
    end;
    if not hasS then
    begin
      stroke := fill;
      hasS := hasF;
    end;
    if hasF and TyTryParseChartColor(fill, col) then TyStSetColor(AHost.Decl[n], stkFill, col);
    if hasS and TyTryParseChartColor(stroke, col) then TyStSetColor(AHost.Decl[n], stkStroke, col);
  end;
  if not AHost.Decl[stnEmphasis].Has[stkLineWidth] then
    TyStSetNum(AHost.Decl[stnEmphasis], stkLineWidth, 2);
end;

procedure TTyAdvanceChart.StDeclareLine(ASlot: Integer; AList: TTyPaintList);

  procedure One(var AItem: TTyStItem; const AIdx: TTyIntegerArray;
    const ABlock: string);
  var
    s: Integer;
    nodes: array[0..0] of TJSONObject;
    was, has, bolder: Boolean;
    prev: TTyStNames;
    n: TTyStName;
    obj: TTyStObject;
  begin
    if Length(AIdx) = 0 then
    begin
      AItem := Default(TTyStItem);
      Exit;
    end;
    s := FBindings[ASlot].SeriesIndex;
    nodes[0] := StSeriesNode(s);
    was := AItem.Host.Exists;
    prev := AItem.Host.States;
    AItem.Host.Exists := True;
    AItem.Host.IsPath := True;
    AItem.Host.Proxy := not TyStReadBool(nodes, ['emphasis', 'disabled'], has);
    for n := Low(TTyStName) to High(TTyStName) do AItem.Host.HasState[n] := True;
    AItem.Host.Rest := StRestOf(AList.Element(AIdx[0]));
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      obj := TyStReadStyle(nodes, cStNames[n], ABlock, bolder);
      { LineView.ts:844-847: 'bolder' is the rest width plus one }
      if bolder then
        TyStSetNum(obj, stkLineWidth, AItem.Host.Rest.Num[stkLineWidth] + 1);
      AItem.Host.Decl[n] := obj;
    end;
    if not was then
    begin
      AItem.Host.Cur := AItem.Host.Rest;
      AItem.Host.States := [];
    end
    else if FStRerender then
    begin
      TyStClearItem(AItem);
      if prev <> [] then TyStUseStates(AItem.Host, prev);
    end;
    TyStUseStates(AItem.Host, TyStTargetStates(AItem.Host));
  end;

var s: Integer;
begin
  s := FBindings[ASlot].SeriesIndex;
  One(FSt[s].Run, FSt[s].RunIdx, 'lineStyle');
  One(FSt[s].Area, FSt[s].AreaIdx, 'areaStyle');
end;

procedure TTyAdvanceChart.StSync(AList: TTyPaintList; APPI: Integer);
var
  slot, s, k, raw, n, i: Integer;
  el: TTyChartElement;
  item: PTyStItem;
  prev: TTyStNames;
  was: Boolean;
begin
  if AList = nil then Exit;
  { a full update since the last sync re-renders: rest, the previous list,
    then the flags (echarts.ts:2667-2748) }
  FStRerender := FStBuiltGen <> FStGen;
  FStBuiltGen := FStGen;
  { THE STATES RUN ON PROXIES [Batch 94] where the render animates, or
    where proxies are bound -- a list that waits for its arming is drawn as
    laid out }
  FStProxied := AnimAllowed or ((FAnimSet <> nil) and (FAnimSet.Count > 0)
    and not FAnimPending);
  { renderSeries' clearStates comes before the render: the proxies back to
    normal at once, the lists kept, before an update's animators exist }
  if FStRerender then StAnimClearAll;
  n := 0;
  for slot := 0 to High(FBindings) do
    if FBindings[slot].SeriesIndex >= n then n := FBindings[slot].SeriesIndex + 1;
  if Length(FSt) < n then SetLength(FSt, n);
  for s := 0 to High(FSt) do
  begin
    FSt[s].Kind := sskNone;
    FSt[s].HostIdx := nil;
    FSt[s].LabelIdx := nil;
    FSt[s].GuideIdx := nil;
    FSt[s].RunIdx := nil;
    FSt[s].AreaIdx := nil;
    FSt[s].FollowIdx := nil;
    FSt[s].PartIdx := nil;
  end;
  for slot := 0 to High(FBindings) do
  begin
    if slot > High(FStores) then Break;
    if FBindings[slot].Hidden or (FStores[slot] = nil) then Continue;
    s := FBindings[slot].SeriesIndex;
    if s < 0 then Continue;
    FSt[s].Kind := StKindOf(slot);
    FSt[s].IsLine := FBindings[slot].SeriesType = 'line';
    if FSt[s].Kind = sskNone then Continue;
    k := FStores[slot].RawCount;
    if Length(FSt[s].Rows) < k then SetLength(FSt[s].Rows, k);
    SetLength(FSt[s].HostIdx, k);
    SetLength(FSt[s].LabelIdx, k);
    SetLength(FSt[s].GuideIdx, k);
    SetLength(FSt[s].FollowIdx, k);
    SetLength(FSt[s].PartIdx, k);
    for i := 0 to k - 1 do
    begin
      FSt[s].HostIdx[i] := -1;
      FSt[s].LabelIdx[i] := -1;
      FSt[s].GuideIdx[i] := -1;
    end;
  end;
  { A SERIES NOT DRAWN HAS NO ELEMENTS: a legend that switched it off took
    its view's group away, and switched back on it is drawn by new elements
    -- no flags, no states (render's `chart.remove`) [Batch 93] }
  for s := 0 to High(FSt) do
    if FSt[s].Kind = sskNone then
    begin
      FSt[s].Rows := nil;
      FSt[s].Run := Default(TTyStItem);
      FSt[s].Area := Default(TTyStItem);
      FSt[s].IsBlured := False;
    end;
  { WHICH ELEMENT IS WHICH: the mark, its label (a placed caption), its
    label line, and a line's polyline and area }
  for k := 0 to AList.Count - 1 do
  begin
    el := AList.Element(k);
    if el.Datum.Kind <> ctkSeries then Continue;
    s := el.Datum.SeriesIndex;
    if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    if el.Datum.IsEdge then Continue;
    if el.Datum.DataIndex < 0 then
    begin
      if not FSt[s].IsLine then Continue;
      if el.Shape.Kind = cskPolyline then
      begin
        SetLength(FSt[s].RunIdx, Length(FSt[s].RunIdx) + 1);
        FSt[s].RunIdx[High(FSt[s].RunIdx)] := k;
      end
      else if el.Shape.Kind = cskPolygon then
      begin
        SetLength(FSt[s].AreaIdx, Length(FSt[s].AreaIdx) + 1);
        FSt[s].AreaIdx[High(FSt[s].AreaIdx)] := k;
      end;
      Continue;
    end;
    slot := SlotOfSeries(s);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    raw := FStores[slot].GetRawIndex(el.Datum.DataIndex);
    if (raw < 0) or (raw > High(FSt[s].HostIdx)) then Continue;
    if el.Caption.FontSizeLogical > 0 then
    begin
      if FSt[s].LabelIdx[raw] < 0 then FSt[s].LabelIdx[raw] := k;
    end
    else if el.IsGuide then
      FSt[s].GuideIdx[raw] := k
    else if FSt[s].Kind = sskPictorial then
    begin
      { THE GLYPHS ARE THE PATHS (silent here: the inkless bar rect is the
        target), the first the host, the rest parts [Batch 90] }
      if not el.Silent then Continue;
      if FSt[s].HostIdx[raw] < 0 then FSt[s].HostIdx[raw] := k
      else StPush(FSt[s].PartIdx[raw], k);
    end
    else if FSt[s].Kind = sskCandle then
    begin
      { ONE PATH upstream, body and wicks: the body hosts, the wicks follow
        [Batch 90] }
      if el.Silent then Continue;
      if el.Anim.Role = carCandleBody then
      begin
        if FSt[s].HostIdx[raw] >= 0 then StPush(FSt[s].FollowIdx[raw], FSt[s].HostIdx[raw]);
        FSt[s].HostIdx[raw] := k;
      end
      else if FSt[s].HostIdx[raw] < 0 then FSt[s].HostIdx[raw] := k
      else StPush(FSt[s].FollowIdx[raw], k);
    end
    else if not el.Silent and (FSt[s].HostIdx[raw] < 0) then
      FSt[s].HostIdx[raw] := k;
  end;
  for slot := 0 to High(FBindings) do
  begin
    s := FBindings[slot].SeriesIndex;
    if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    SelEnsure(slot);
    for raw := 0 to High(FSt[s].Rows) do
    begin
      item := @FSt[s].Rows[raw];
      if (raw > High(FSt[s].HostIdx)) or (FSt[s].HostIdx[raw] < 0) then
      begin
        { gone from the picture: a NEW element if it comes back }
        item^ := Default(TTyStItem);
        Continue;
      end;
      was := item^.Host.Exists;
      prev := item^.Host.States;
      StDeclareItem(slot, raw, AList, APPI);
      if not was then
      begin
        item^.Host.Cur := item^.Host.Rest;
        item^.Host.States := [];
      end
      else if FStRerender then
      begin
        TyStClearItem(item^);
        if prev <> [] then TyStUseItemStates(item^, prev);
      end;
    end;
    { updateSeriesElementSelection, then applyElementStates }
    SelSyncFlags(slot);
    for raw := 0 to High(FSt[s].Rows) do
      if FSt[s].Rows[raw].Host.Exists then TyStApplyItem(FSt[s].Rows[raw]);
    if FSt[s].IsLine then StDeclareLine(slot, AList);
  end;
  FStDirty := False;
  StWrite(AList);
end;

procedure TTyAdvanceChart.StWrite(AList: TTyPaintList);
var
  s, raw, k: Integer;
  el: TTyChartElement;
  item: PTyStItem;
begin
  for s := 0 to High(FSt) do
  begin
    if FSt[s].Kind = sskNone then Continue;
    for raw := 0 to High(FSt[s].HostIdx) do
    begin
      if FSt[s].HostIdx[raw] < 0 then Continue;
      item := @FSt[s].Rows[raw];
      if item^.Host.States <> [] then
      begin
        el := AList.Element(FSt[s].HostIdx[raw]);
        StWriteHost(el, item^.Host, FStProxied);
        AList.SetElement(FSt[s].HostIdx[raw], el);
        { the rest of the same path: the host's changes [Batch 90] }
        if raw <= High(FSt[s].FollowIdx) then
          for k := 0 to High(FSt[s].FollowIdx[raw]) do
          begin
            el := AList.Element(FSt[s].FollowIdx[raw][k]);
            StWriteFollower(el, item^.Host, FStProxied);
            AList.SetElement(FSt[s].FollowIdx[raw][k], el);
          end;
      end;
      { the other paths, their own values [Batch 90] }
      if raw <= High(FSt[s].PartIdx) then
        for k := 0 to Min(High(FSt[s].PartIdx[raw]), High(item^.Parts)) do
          if item^.Parts[k].States <> [] then
          begin
            el := AList.Element(FSt[s].PartIdx[raw][k]);
            StWriteHost(el, item^.Parts[k], FStProxied);
            AList.SetElement(FSt[s].PartIdx[raw][k], el);
          end;
      if (FSt[s].LabelIdx[raw] >= 0) and item^.Label_.Exists
        and (item^.Label_.States <> []) then
      begin
        el := AList.Element(FSt[s].LabelIdx[raw]);
        StWriteLabel(el, item^.Label_, FStProxied);
        AList.SetElement(FSt[s].LabelIdx[raw], el);
      end;
      if (FSt[s].GuideIdx[raw] >= 0) and item^.Guide.Exists
        and (item^.Guide.States <> []) then
      begin
        el := AList.Element(FSt[s].GuideIdx[raw]);
        StWriteGuide(el, item^.Guide, FStProxied);
        AList.SetElement(FSt[s].GuideIdx[raw], el);
      end;
    end;
    if FSt[s].Run.Host.Exists and (FSt[s].Run.Host.States <> []) then
      for k := 0 to High(FSt[s].RunIdx) do
      begin
        el := AList.Element(FSt[s].RunIdx[k]);
        StWriteHost(el, FSt[s].Run.Host, FStProxied);
        AList.SetElement(FSt[s].RunIdx[k], el);
      end;
    if FSt[s].Area.Host.Exists and (FSt[s].Area.Host.States <> []) then
      for k := 0 to High(FSt[s].AreaIdx) do
      begin
        el := AList.Element(FSt[s].AreaIdx[k]);
        StWriteHost(el, FSt[s].Area.Host, FStProxied);
        AList.SetElement(FSt[s].AreaIdx[k], el);
      end;
  end;
end;

function TTyAdvanceChart.StApplyChanged: Boolean;
var s, raw: Integer;
begin
  Result := False;
  if not FStDirty then Exit;
  FStDirty := False;
  for s := 0 to High(FSt) do
  begin
    if FSt[s].Kind = sskNone then Continue;
    for raw := 0 to High(FSt[s].Rows) do
      if FSt[s].Rows[raw].Host.Exists and TyStApplyItem(FSt[s].Rows[raw]) then
        Result := True;
    if FSt[s].Run.Host.Exists
      and TyStUseStates(FSt[s].Run.Host, TyStTargetStates(FSt[s].Run.Host)) then
      Result := True;
    if FSt[s].Area.Host.Exists
      and TyStUseStates(FSt[s].Area.Host, TyStTargetStates(FSt[s].Area.Host)) then
      Result := True;
  end;
end;

{ ==================== state transitions [Batch 94, AN3b] ====================

  updateStates (echarts.ts:2697-2747) gives every element with an emphasis
  state -- and its label and label line -- the series' stateAnimation as its
  stateTransition when the series animates; zrender's useStates then
  transitions the transform keys, the animatable style keys and the shape's
  primitive keys (Anim.pas, TTyAnimElement.UseStates). Here the element is
  its proxy: the role's where upstream's element is the one the enter and
  update animations run on, else one of the states' own. The state machine
  (States.pas) still decides the lists and the merged objects; this turns a
  merged object into the proxy's keys and lets the engine run it. }

const
  { the element kinds a proxy's state keys are seeded for }
  cStPxPath = 0;
  cStPxLabel = 1;
  cStPxGuide = 2;
  cStPxPart = 3;
  cStPxLine = 4;

function StNamesOf(const AText: string): TTyStNames;
var n: TTyStName; parts: TStringArray; i: Integer;
begin
  Result := [];
  parts := AText.Split([',']);
  for i := 0 to High(parts) do
    for n := Low(TTyStName) to High(TTyStName) do
      if parts[i] = cStNames[n] then Include(Result, n);
end;

{ a colour key of a state object as the engine takes it: 'none', null for
  no stroke, a lifted colour as liftColor's rgba() string }
function StColourValue(const AObj: TTyStObject; AKey: TTyStKey): TTyAnimValue;
begin
  if AObj.None[AKey] then
  begin
    if AKey = stkStroke then Result := TyAnimNull
    else Result := TyAnimStr('none');
  end
  else
    Result := TyAnimColorValue(AObj.Color[AKey], AObj.Lifted[AKey]);
end;

{ A MERGED STATE OBJECT as the proxy's keys: the style keys, and the place,
  the scale and the radius where the proxy carries them }
function StAnimStateOf(const AEl: TTyStElement; const AM: TTyStObject;
  AKind: Integer; P: TTyChartAnimProxy): TTyAnimState;
var
  rx, ry: TTyAnimValue;
  f: Double;
begin
  Result := Default(TTyAnimState);
  { setStatesStylesFromModel gives every state a style object }
  Result.HasStyle := True;
  if AKind = cStPxLabel then
  begin
    { a label's opacity is a factor over its own (as its fade's) }
    if AM.Has[stkOpacity] then
    begin
      f := AM.Num[stkOpacity];
      if StPositive(AEl.Rest.Num[stkOpacity]) then f := f / AEl.Rest.Num[stkOpacity];
      TyAnimPropPut(Result.Props, 'style.opacity', TyAnimNum(f));
    end;
  end
  else
  begin
    if AM.Has[stkFill] and P.HasStKey('style.fill') then
      TyAnimPropPut(Result.Props, 'style.fill', StColourValue(AM, stkFill));
    if AM.Has[stkStroke] and P.HasStKey('style.stroke') then
      TyAnimPropPut(Result.Props, 'style.stroke', StColourValue(AM, stkStroke));
    if AM.Has[stkLineWidth] and P.HasStKey('style.lineWidth') then
      TyAnimPropPut(Result.Props, 'style.lineWidth', TyAnimNum(AM.Num[stkLineWidth]));
    if AM.Has[stkOpacity] then
      TyAnimPropPut(Result.Props, 'style.opacity', TyAnimNum(AM.Num[stkOpacity]));
  end;
  if AM.Has[stkX] and P.HasStKey('x') then
    TyAnimPropPut(Result.Props, 'x', TyAnimNum(AM.Num[stkX]));
  if AM.Has[stkY] and P.HasStKey('y') then
    TyAnimPropPut(Result.Props, 'y', TyAnimNum(AM.Num[stkY]));
  { Symbol.ts: emphasisState.scaleX = this._sizeX * scaleRatio }
  if AM.Has[stkScale] and P.HasStKey('scaleX') and P.StRestOf('scaleX', rx)
    and P.StRestOf('scaleY', ry) then
  begin
    TyAnimPropPut(Result.Props, 'scaleX', TyAnimNum(rx.Num * AM.Num[stkScale]));
    TyAnimPropPut(Result.Props, 'scaleY', TyAnimNum(ry.Num * AM.Num[stkScale]));
  end;
  { PieView: the emphasis shape is r = layout.r + scaleSize }
  if AM.Has[stkR] and P.HasStKey('shape.r') then
  begin
    TyAnimPropPut(Result.Props, 'shape.r', TyAnimNum(AM.Num[stkR]));
    Result.HasShape := True;
  end;
end;

procedure TTyAdvanceChart.StAnimClearAll;
var
  i: Integer;
  p: TTyChartAnimProxy;
begin
  if FAnimSet = nil then Exit;
  for i := 0 to FAnimSet.Count - 1 do
  begin
    p := FAnimSet.Item(i);
    if p.CurrentStates = '' then Continue;
    { clearStates (echarts.ts:2667-2695): the transition nulled, prevStates
      kept, back to normal without one }
    p.StPrev := p.CurrentStates;
    p.ClearStateTransition;
    p.ClearStates(True);
  end;
end;

function TTyAdvanceChart.StAnimCfg(ASeriesIndex: Integer; out ACfg: TTyAnimCfg): Boolean;
var
  slot, n: Integer;
  model: TTyAnimModel;
  own, root: TJSONObject;
  dur, delay: Double;
  easing: string;

  { stateAnimation.<key>: the series', the root's, the global default }
  function Find(const AKey: string): TJSONData;
  var d: TJSONData;
  begin
    Result := nil;
    if own <> nil then
    begin
      d := own.Find(AKey);
      if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
    end;
    if root <> nil then
    begin
      d := root.Find(AKey);
      if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
    end;
  end;

var d: TJSONData;
begin
  ACfg := Default(TTyAnimCfg);
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  n := 0;
  if (slot >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil) then
    n := FStores[slot].Count;
  model := TyAnimSeriesModel(FOption.Root, ASeriesIndex, n);
  { model.isAnimationEnabled(): `animation` and the threshold }
  if not TyAnimIsEnabled(model) then Exit;
  own := nil;
  root := nil;
  if model.Own is TJSONObject then
  begin
    d := TJSONObject(model.Own).Find('stateAnimation');
    if d is TJSONObject then own := TJSONObject(d);
  end;
  if FOption.Root is TJSONObject then
  begin
    d := TJSONObject(FOption.Root).Find('stateAnimation');
    if d is TJSONObject then root := TJSONObject(d);
  end;
  d := Find('duration');
  if d = nil then dur := 300
  else if d.JSONType = jtNumber then dur := d.AsFloat
  else dur := NaN;
  d := Find('easing');
  if (d <> nil) and (d.JSONType = jtString) then easing := d.AsString
  else easing := 'cubicOut';
  d := Find('delay');
  if (d <> nil) and (d.JSONType = jtNumber) then delay := d.AsFloat
  else delay := 0;
  { a duration above 0 makes a stateTransition, anything else none }
  if IsNan(dur) or not (dur > 0) then Exit;
  ACfg := TyAnimCfg(dur, delay, easing);
  Result := True;
end;

procedure TTyAdvanceChart.StAnimEl(var AEl: TTyStElement; AListIdx, ASeries,
  ARaw: Integer; const AName: string; AKind: Integer; const ACfg: TTyAnimCfg;
  AHasCfg, AOver: Boolean);
var
  el: TTyChartElement;
  p, role: TTyChartAnimProxy;
  isPie: Boolean;
  tmp: TTyStElement;
  want: string;
  noAnim: Boolean;
  st: TTyAnimState;

  { a state key at rest: re-seeded on a full update unless the role's own
    animation holds it }
  procedure Seed(const AKey: string; const AValue: TTyAnimValue);
  begin
    p.StSeed(AKey, AValue, FStRerender and (p.FinalOf(AKey).Kind = avkNull));
  end;

begin
  if (AListIdx < 0) or (AListIdx >= FPaintList.Count) then Exit;
  el := FPaintList.Element(AListIdx);
  role := nil;
  if AListIdx <= High(FAnimBind) then role := FAnimBind[AListIdx];
  { UPSTREAM'S SAME ELEMENT: the proxy its enter and update animations run
    on; anything else (a line symbol's group is not its path, a clip is not
    its polyline) a proxy of the states' own }
  if (role <> nil) and (el.Anim.Role in [carBar, carSymbol, carSector, carFunnel,
    carCandleBody, carCandleWickHigh, carCandleWickLow, carLabel, carGuide]) then
    p := role
  else
  begin
    p := FAnimSet.Find(ASeries, ARaw, 'st:' + AName);
    if p = nil then p := FAnimSet.MakeState(ASeries, ARaw, 'st:' + AName);
  end;
  FAnimStBind[AListIdx] := p;
  { a Text's style animates only its opacity }
  p.StatePath := AKind <> cStPxLabel;
  isPie := FSt[ASeries].Kind = sskPie;
  { ---- the rest values ---- }
  if AKind = cStPxLabel then
  begin
    Seed('style.opacity', TyAnimNum(1));
    { a pie's label is placed by its layout: x / y are its anchor }
    if isPie then
    begin
      Seed('x', TyAnimNum(AEl.Rest.Num[stkX]));
      Seed('y', TyAnimNum(AEl.Rest.Num[stkY]));
    end;
  end
  else
  begin
    if AKind <> cStPxGuide then
    begin
      Seed('style.fill', StColourValue(AEl.Rest, stkFill));
      Seed('style.stroke', StColourValue(AEl.Rest, stkStroke));
      Seed('style.lineWidth', TyAnimNum(AEl.Rest.Num[stkLineWidth]));
    end;
    Seed('style.opacity', TyAnimNum(AEl.Rest.Num[stkOpacity]));
    if isPie and (AKind in [cStPxPath, cStPxGuide]) then
    begin
      Seed('x', TyAnimNum(0));
      Seed('y', TyAnimNum(0));
    end;
    if isPie and (AKind = cStPxPath) and (el.Shape.Kind = cskSector) then
      Seed('shape.r', TyAnimNum(AEl.Rest.Num[stkR]));
    { a symbol path's scale is half its size; a pictorial glyph's its own }
    if AKind = cStPxPath then
      case el.Anim.Role of
        carSymbol, carEffectSymbol:
          begin
            Seed('scaleX', TyAnimNum(el.Anim.G[2]));
            Seed('scaleY', TyAnimNum(el.Anim.G[3]));
          end;
        carLineSymbol:
          begin
            Seed('scaleX', TyAnimNum(el.Anim.G[7]));
            Seed('scaleY', TyAnimNum(el.Anim.G[8]));
          end;
      else
        { a pictorial glyph's emphasis.scale: a factor over its own scale }
        if (FSt[ASeries].Kind = sskPictorial) and AEl.Decl[stnEmphasis].Has[stkScale] then
        begin
          Seed('scaleX', TyAnimNum(1));
          Seed('scaleY', TyAnimNum(1));
        end;
      end
    else if (AKind = cStPxPart) and (FSt[ASeries].Kind = sskPictorial)
      and AEl.Decl[stnEmphasis].Has[stkScale] then
    begin
      Seed('scaleX', TyAnimNum(1));
      Seed('scaleY', TyAnimNum(1));
    end;
  end;
  { ---- a full update: the previous list back at once (no transition: the
    render nulled it), the merged object made on the new element ---- }
  if p.StPrev <> '' then
  begin
    tmp := AEl;
    tmp.Cur := tmp.Rest;
    tmp.States := [];
    TyStUseStates(tmp, StNamesOf(p.StPrev));
    p.UseStates(p.StPrev, StAnimStateOf(tmp, tmp.Merged, AKind, p), True);
    p.StPrev := '';
  end;
  { ---- the series' stateTransition, only when it animates ---- }
  if AHasCfg then p.SetStateTransition(ACfg) else p.ClearStateTransition;
  want := TyStNamesText(AEl.States);
  if want = p.CurrentStates then Exit;
  { no timer, no transition; and an element in the hover layer has none }
  noAnim := not AnimAllowed or (AOver and ((Pos('emphasis', want) > 0)
    or (Pos('emphasis', p.CurrentStates) > 0)));
  if want = '' then p.ClearStates(noAnim)
  else
  begin
    st := StAnimStateOf(AEl, AEl.Merged, AKind, p);
    p.UseStates(want, st, noAnim);
    { a pie label's select place, for the next update's move from it }
    if (AKind = cStPxLabel) and (stnSelect in AEl.States)
      and (TyAnimPropIndex(st.Props, 'x') >= 0) and (TyAnimPropIndex(st.Props, 'y') >= 0) then
      p.StNoteSelect(st.Props[TyAnimPropIndex(st.Props, 'x')].Value.Num,
        st.Props[TyAnimPropIndex(st.Props, 'y')].Value.Num);
  end;
end;

procedure TTyAdvanceChart.StAnimSync;
var
  s, raw, k, clips: Integer;
  item: PTyStItem;
  cfg: TTyAnimCfg;
  hasCfg, over: Boolean;
  hostP: TTyChartAnimProxy;
  d: TJSONData;
  threshold: Double;
begin
  if not FStProxied or (FPaintList = nil) then Exit;
  if FAnim = nil then FAnim := TTyAnimation.Create;
  if FAnimSet = nil then FAnimSet := TTyChartAnimSet.Create(FAnim);
  SetLength(FAnimStBind, FPaintList.Count);
  for k := 0 to High(FAnimStBind) do FAnimStBind[k] := nil;
  clips := FAnim.ClipCount;
  { THE HOVER LAYER: past hoverLayerThreshold elements upstream's canvas
    hovers an element in a layer of its own, where it never transitions
    (canTransition, __inHover) }
  threshold := 3000;
  if FOption.Root is TJSONObject then
  begin
    d := TJSONObject(FOption.Root).Find('hoverLayerThreshold');
    if (d <> nil) and (d.JSONType = jtNumber) then threshold := d.AsFloat;
  end;
  over := FPaintList.Count > threshold;
  for s := 0 to High(FSt) do
  begin
    if FSt[s].Kind = sskNone then Continue;
    hasCfg := StAnimCfg(s, cfg);
    for raw := 0 to High(FSt[s].HostIdx) do
    begin
      if FSt[s].HostIdx[raw] < 0 then Continue;
      if raw > High(FSt[s].Rows) then Continue;
      item := @FSt[s].Rows[raw];
      if not item^.Host.Exists then Continue;
      StAnimEl(item^.Host, FSt[s].HostIdx[raw], s, raw, 'host', cStPxPath,
        cfg, hasCfg, over);
      { the rest of the same path: the host's proxy }
      hostP := FAnimStBind[FSt[s].HostIdx[raw]];
      if raw <= High(FSt[s].FollowIdx) then
        for k := 0 to High(FSt[s].FollowIdx[raw]) do
          FAnimStBind[FSt[s].FollowIdx[raw][k]] := hostP;
      if raw <= High(FSt[s].PartIdx) then
        for k := 0 to Min(High(FSt[s].PartIdx[raw]), High(item^.Parts)) do
          StAnimEl(item^.Parts[k], FSt[s].PartIdx[raw][k], s, raw,
            'part' + IntToStr(k), cStPxPart, cfg, hasCfg, over);
      if (FSt[s].LabelIdx[raw] >= 0) and item^.Label_.Exists then
        StAnimEl(item^.Label_, FSt[s].LabelIdx[raw], s, raw, 'label', cStPxLabel,
          cfg, hasCfg, over);
      if (FSt[s].GuideIdx[raw] >= 0) and item^.Guide.Exists then
        StAnimEl(item^.Guide, FSt[s].GuideIdx[raw], s, raw, 'guide', cStPxGuide,
          cfg, hasCfg, over);
    end;
    { a line's polyline and area: one element each upstream, its runs here }
    if FSt[s].Run.Host.Exists and (Length(FSt[s].RunIdx) > 0) then
    begin
      StAnimEl(FSt[s].Run.Host, FSt[s].RunIdx[0], s, -1, 'poly', cStPxLine,
        cfg, hasCfg, over);
      for k := 1 to High(FSt[s].RunIdx) do
        FAnimStBind[FSt[s].RunIdx[k]] := FAnimStBind[FSt[s].RunIdx[0]];
    end;
    if FSt[s].Area.Host.Exists and (Length(FSt[s].AreaIdx) > 0) then
    begin
      StAnimEl(FSt[s].Area.Host, FSt[s].AreaIdx[0], s, -1, 'area', cStPxLine,
        cfg, hasCfg, over);
      for k := 1 to High(FSt[s].AreaIdx) do
        FAnimStBind[FSt[s].AreaIdx[k]] := FAnimStBind[FSt[s].AreaIdx[0]];
    end;
  end;
  { A TRANSITION BEGAN: the series go to the dynamic layer until it ends
    (an armed option's flush decides that itself) }
  if (FAnim.ClipCount > clips) and not FAnimFlush then
  begin
    FAnimLive := True;
    FAnimContinuous := AnimLoopOnly;
    AnimArmTimer;
  end;
end;

function TTyAdvanceChart.StItemAt(ASeriesIndex, AInnerRow: Integer): PTyStItem;
var slot, raw: Integer;
begin
  Result := nil;
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSt)) then Exit;
  if FSt[ASeriesIndex].Kind = sskNone then Exit;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
  if (AInnerRow < 0) or (AInnerRow >= FStores[slot].Count) then Exit;
  raw := FStores[slot].GetRawIndex(AInnerRow);
  if (raw < 0) or (raw > High(FSt[ASeriesIndex].Rows)) then Exit;
  if not FSt[ASeriesIndex].Rows[raw].Host.Exists then Exit;
  Result := @FSt[ASeriesIndex].Rows[raw];
end;

{ ---- focus and blur [Batch 90] ---- }

function TTyAdvanceChart.StPolyOf(ASeriesIndex: Integer): Integer;
begin
  Result := -1;
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSt)) then Exit;
  if FSt[ASeriesIndex].IsLine and FSt[ASeriesIndex].Run.Host.Exists then
    Result := FSt[ASeriesIndex].Run.Host.HoverState;
end;

{ LineView._changePolyState: setStatesFlag on the polyline and the area }
procedure TTyAdvanceChart.StPolyTo(ASeriesIndex, AState: Integer);
begin
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSt)) then Exit;
  if not FSt[ASeriesIndex].IsLine then Exit;
  FSt[ASeriesIndex].Run.Host.HoverState := AState;
  FSt[ASeriesIndex].Area.Host.HoverState := AState;
  FStDirty := True;
end;

function TTyAdvanceChart.StCoordKey(ASlot: Integer): string;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  { coordinateSystem.master: a cartesian's is its GRID, so two axis pairs
    of one grid are one system }
  if FBindings[ASlot].Cart <> nil then
  begin
    if FBindings[ASlot].XAxis <> nil then
      Result := 'grid' + IntToStr(FBindings[ASlot].XAxis.GridIndex)
    else
      Result := 'cart' + IntToStr(PtrUInt(FBindings[ASlot].Cart));
  end
  else if FBindings[ASlot].CalendarIndex >= 0 then
    Result := 'calendar' + IntToStr(FBindings[ASlot].CalendarIndex)
  else if FBindings[ASlot].RadarIndex >= 0 then
    Result := 'radar' + IntToStr(FBindings[ASlot].RadarIndex);
end;

{ an item's model chain: the item, a sunburst row's level, the series }
function TTyAdvanceChart.StNodes(ASeriesIndex, ARaw: Integer): TTyStNodeArray;
var slot, d: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FSunbursts)) and FSunbursts[slot].Valid
    and (ARaw >= 0) and (ARaw <= High(FSunbursts[slot].Hier.Nodes)) then
  begin
    SetLength(Result, 3);
    Result[0] := StItemNode(ASeriesIndex, ARaw);
    d := FSunbursts[slot].Hier.Nodes[ARaw].Depth;
    Result[1] := nil;
    if (d >= 0) and (d <= High(FSunbursts[slot].Levels)) then
      Result[1] := FSunbursts[slot].Levels[d];
    Result[2] := StSeriesNode(ASeriesIndex);
    Exit;
  end;
  SetLength(Result, 2);
  Result[0] := StItemNode(ASeriesIndex, ARaw);
  Result[1] := StSeriesNode(ASeriesIndex);
end;

function TTyAdvanceChart.StItemFocus(ASeriesIndex, ARaw: Integer;
  out AScope: TTyStScope): TTyStFocus;
var
  nodes: TTyStNodeArray;
  d: TJSONData;
  w: string;
  slot, i, p: Integer;
  anc: TTyIntegerArray;

  procedure Add(AIndex: Integer);
  begin
    SetLength(Result.Indices, Length(Result.Indices) + 1);
    Result.Indices[High(Result.Indices)] := AIndex;
  end;

begin
  nodes := StNodes(ASeriesIndex, ARaw);
  d := TyStFind(nodes, ['emphasis', 'focus']);
  AScope := TyStScopeOf(TyStFind(nodes, ['emphasis', 'blurScope']));
  slot := SlotOfSeries(ASeriesIndex);
  if not ((slot >= 0) and (slot <= High(FSunbursts)) and FSunbursts[slot].Valid
    and (ARaw >= 0) and (ARaw <= High(FSunbursts[slot].Hier.Nodes))) then
    Exit(TyStFocusOf(d));
  { A SUNBURST'S WORDS ARE INDICES (SunburstPiece.ts:152-160), its default
    'descendant' (SunburstSeries.ts:271): the row's ancestors from the root
    down, its subtree in pre-order, or both [Batch 90] }
  if d = nil then w := 'descendant'
  else if d.JSONType = jtString then w := d.AsString
  else w := '';
  if (w <> 'descendant') and (w <> 'ancestor') and (w <> 'relative') then
    Exit(TyStFocusOf(d));
  Result := Default(TTyStFocus);
  Result.Kind := sfkIndices;
  if (w = 'ancestor') or (w = 'relative') then
  begin
    anc := nil;
    p := ARaw;
    while p >= 0 do
    begin
      SetLength(anc, Length(anc) + 1);
      anc[High(anc)] := p;
      p := FSunbursts[slot].Hier.Nodes[p].Parent;
    end;
    for i := High(anc) downto 0 do Add(anc[i]);
  end;
  if (w = 'descendant') or (w = 'relative') then
    for i := 0 to High(FSunbursts[slot].Hier.Nodes) do
    begin
      p := i;
      while (p >= 0) and (p <> ARaw) do p := FSunbursts[slot].Hier.Nodes[p].Parent;
      if p = ARaw then Add(i);
    end;
end;

function TTyAdvanceChart.StSeriesFocus(ASeriesIndex: Integer;
  out AScope: TTyStScope): TTyStFocus;
var nodes: array[0..0] of TJSONObject;
begin
  nodes[0] := StSeriesNode(ASeriesIndex);
  Result := TyStFocusOf(TyStFind(nodes, ['emphasis', 'focus']));
  AScope := TyStScopeOf(TyStFind(nodes, ['emphasis', 'blurScope']));
end;

function TTyAdvanceChart.StInnerRaw(ASeriesIndex, AInner: Integer): Integer;
var slot: Integer;
begin
  Result := -1;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
  if (AInner < 0) or (AInner >= FStores[slot].Count) then Exit;
  Result := FStores[slot].GetRawIndex(AInner);
end;

{ blurSeries (util/states.ts:429-517): every SHOWN series the scope reaches
  -- by series, by coordinate system (a series with none matches only
  itself), or all -- except the target itself under focus 'series': every
  element enters blur, but one held by an action stays in the target series
  under focus 'self'; data indices of a focus list leave the blur again. }
procedure TTyAdvanceChart.StBlurSeries(ATarget: Integer; const AFocus: TTyStFocus;
  AScope: TTyStScope);
var
  slot, s, raw, k, poly, tslot: Integer;
  tkey, key: string;
  same, sameCoord, spare: Boolean;
  item: PTyStItem;
begin
  if ATarget < 0 then Exit;
  if AFocus.Kind = sfkNone then Exit;
  tslot := SlotOfSeries(ATarget);
  if tslot < 0 then Exit;
  tkey := StCoordKey(tslot);
  for slot := 0 to High(FBindings) do
  begin
    if FBindings[slot].Hidden then Continue;
    s := FBindings[slot].SeriesIndex;
    if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    same := s = ATarget;
    key := StCoordKey(slot);
    if (key <> '') and (tkey <> '') then sameCoord := key = tkey
    else sameCoord := same;
    if not TyStBlursSeries(AFocus, AScope, same, sameCoord) then Continue;
    spare := same and (AFocus.Kind = sfkSelf);
    poly := StPolyOf(s);
    { the polyline and the area are elements of the group too }
    if poly >= 0 then poly := TyStHoverBlur;
    for raw := 0 to High(FSt[s].Rows) do
      if FSt[s].Rows[raw].Host.Exists then
        TyStItemEnterBlur(FSt[s].Rows[raw], spare, poly);
    if poly >= 0 then StPolyTo(s, poly);
    if AFocus.Kind = sfkIndices then
      for k := 0 to High(AFocus.Indices) do
      begin
        item := StItemAt(s, AFocus.Indices[k]);
        if item = nil then Continue;
        poly := StPolyOf(s);
        TyStItemLeaveBlur(item^, poly);
        if poly >= 0 then StPolyTo(s, poly);
      end;
    FSt[s].IsBlured := True;
    FStDirty := True;
  end;
end;

{ allLeaveBlur (util/states.ts:404-427): every series blurSeries reached
  leaves blur, whole; none is blured after }
procedure TTyAdvanceChart.StAllLeaveBlur;
var s, raw, poly: Integer;
begin
  for s := 0 to High(FSt) do
  begin
    if FSt[s].IsBlured then
    begin
      poly := StPolyOf(s);
      if poly = TyStHoverBlur then poly := TyStHoverNormal;
      for raw := 0 to High(FSt[s].Rows) do
        if FSt[s].Rows[raw].Host.Exists then
          TyStItemLeaveBlur(FSt[s].Rows[raw], poly);
      if poly >= 0 then StPolyTo(s, poly);
      { the area on its own, should it be blurred apart from the polyline }
      if FSt[s].Area.Host.HoverState = TyStHoverBlur then
        FSt[s].Area.Host.HoverState := TyStHoverNormal;
      FStDirty := True;
    end;
    FSt[s].IsBlured := False;
  end;
end;

function TTyAdvanceChart.StDispatcher(const ATarget: TTyChartEventTarget;
  out AItem: PTyStItem; out APart: Integer): Boolean;
var s, idx, k: Integer;
begin
  Result := False;
  AItem := nil;
  APart := -1;
  s := ATarget.HdSeries;
  if ATarget.HdKind = 1 then
  begin
    if ATarget.HdEdge then Exit;
    AItem := StItemAt(s, ATarget.HdRow);
    { emphasis.disabled: not a highDownDispatcher at all }
    if (AItem = nil) or not AItem^.Host.Proxy then Exit;
    APart := 0;
    Exit(True);
  end;
  if ATarget.HdKind <> 2 then Exit;
  if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) or not FSt[s].IsLine then Exit;
  idx := Integer(ATarget.Id) - 1;
  for k := 0 to High(FSt[s].RunIdx) do
    if FSt[s].RunIdx[k] = idx then
    begin
      AItem := @FSt[s].Run;
      APart := 1;
    end;
  for k := 0 to High(FSt[s].AreaIdx) do
    if FSt[s].AreaIdx[k] = idx then
    begin
      AItem := @FSt[s].Area;
      APart := 2;
    end;
  Result := (AItem <> nil) and AItem^.Host.Exists and AItem^.Host.Proxy;
end;

{ handleGlobalMouseOutForHighDown: allLeaveBlur, then the dispatcher leaves
  emphasis unless an action holds it }
procedure TTyAdvanceChart.StHoverOut(const ATarget: TTyChartEventTarget);
var item: PTyStItem; part, s, poly: Integer;
begin
  { a legend item's own mouseout: the downplay action [Batch 93] }
  if ATarget.HdKind = 4 then
  begin
    LegendHighDown(ATarget, 'downplay');
    Exit;
  end;
  { [Batch 98] a selector button: allLeaveBlur, and it leaves emphasis;
    a page button has no states }
  if ATarget.HdKind = 5 then
  begin
    StAllLeaveBlur;
    LegendSelHover(-1, -1);
    if FStDirty then InvalidateFrame;
    Exit;
  end;
  if ATarget.HdKind = 6 then Exit;
  if not StDispatcher(ATarget, item, part) then Exit;
  s := ATarget.HdSeries;
  StAllLeaveBlur;
  if part = 0 then
  begin
    poly := StPolyOf(s);
    if TyStItemHoverLeave(item^, poly) then FStDirty := True;
    if poly >= 0 then StPolyTo(s, poly);
  end
  else if (item^.Host.HighByOuter = 0) and (item^.Host.HoverState = TyStHoverEmphasis) then
  begin
    { the polyline's own change carries the area; the area is alone }
    if part = 1 then StPolyTo(s, TyStHoverNormal)
    else item^.Host.HoverState := TyStHoverNormal;
    FStDirty := True;
  end;
  if FStDirty then InvalidateFrame;
end;

{ handleGlobalMouseOverForHighDown: blurSeries by the dispatcher's focus,
  then it enters emphasis unless an action holds it }
procedure TTyAdvanceChart.StHoverOver(const ATarget: TTyChartEventTarget);
var
  item: PTyStItem;
  part, s, poly: Integer;
  focus: TTyStFocus;
  scope: TTyStScope;
begin
  { a legend item's own mouseover: the highlight action [Batch 93] }
  if ATarget.HdKind = 4 then
  begin
    LegendHighDown(ATarget, 'highlight');
    Exit;
  end;
  { [Batch 98] a selector button enters emphasis (enableHoverEmphasis) }
  if ATarget.HdKind = 5 then
  begin
    LegendSelHover(ATarget.HdSeries, ATarget.HdRow);
    Exit;
  end;
  if ATarget.HdKind = 6 then Exit;
  if not StDispatcher(ATarget, item, part) then Exit;
  s := ATarget.HdSeries;
  if part = 0 then
    focus := StItemFocus(s, StInnerRaw(s, ATarget.HdRow), scope)
  else
    focus := StSeriesFocus(s, scope);
  StBlurSeries(s, focus, scope);
  if part = 0 then
  begin
    poly := StPolyOf(s);
    if TyStItemHoverEnter(item^, poly) then FStDirty := True;
    if poly >= 0 then StPolyTo(s, poly);
  end
  else if item^.Host.HighByOuter = 0 then
  begin
    if part = 1 then StPolyTo(s, TyStHoverEmphasis)
    else item^.Host.HoverState := TyStHoverEmphasis;
    FStDirty := True;
  end;
  if FStDirty then InvalidateFrame;
end;

function TTyAdvanceChart.StOwnsElement(AIndex: Integer): Boolean;
var d: TTyChartDatumRef;
begin
  Result := False;
  if (FPaintList = nil) or (AIndex < 0) or (AIndex >= FPaintList.Count) then Exit;
  d := FPaintList.Element(AIndex).Datum;
  if (d.Kind <> ctkSeries) or (d.SeriesIndex < 0) or (d.SeriesIndex > High(FSt)) then Exit;
  Result := FSt[d.SeriesIndex].Kind <> sskNone;
end;

function TTyAdvanceChart.StEmphasised(AIndex: Integer): Boolean;
var d: TTyChartDatumRef; item: PTyStItem;
begin
  Result := False;
  if not StOwnsElement(AIndex) then Exit;
  d := FPaintList.Element(AIndex).Datum;
  item := StItemAt(d.SeriesIndex, d.DataIndex);
  Result := (item <> nil) and (stnEmphasis in item^.Host.States);
end;

{ ---- the selection model ---- }

function TTyAdvanceChart.SelData(ASlot: Integer): TTySelData;
var
  st: TTyDataStore;
  i, n, raw, s: Integer;
  key: string;
  has: Boolean;
begin
  Result := Default(TTySelData);
  if (ASlot < 0) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  s := FBindings[ASlot].SeriesIndex;
  n := st.Count;
  SetLength(Result.Keys, n);
  SetLength(Result.Raws, n);
  SetLength(Result.Disabled, n);
  for i := 0 to n - 1 do
  begin
    raw := st.GetRawIndex(i);
    Result.Raws[i] := raw;
    { getSelectionKey: the name, else the id (SeriesData's own 'e\0\0' + raw
      for an item that has neither) }
    key := st.GetItemName(i);
    if key = '' then key := st.GetId(i);
    if key = '' then key := 'e'#0#0 + IntToStr(raw);
    Result.Keys[i] := key;
    { the item model's select.disabled: the item's, else the series' }
    Result.Disabled[i] := TyStReadBool([StItemNode(s, raw), StSeriesNode(s)],
      ['select', 'disabled'], has);
  end;
end;

procedure TTyAdvanceChart.SelEnsure(ASlot: Integer);
var
  s, i: Integer;
  node: TJSONObject;
  data: TTySelData;
  flags: TTyBoolArray;
  has: Boolean;
begin
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  s := FBindings[ASlot].SeriesIndex;
  if s < 0 then Exit;
  if Length(FSel) <= s then
  begin
    SetLength(FSel, s + 1);
    SetLength(FSelInit, s + 1);
  end;
  if FSelInit[s] then Exit;
  if (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  node := StSeriesNode(s);
  if node <> nil then FSel[s] := TySelNew(TySelModeOf(node.Find('selectedMode')))
  else FSel[s] := TySelNew(ssmOff);
  FSelInit[s] := True;
  { _initSelectedMapFromData: `selected: true` on a data item }
  data := SelData(ASlot);
  flags := nil;
  SetLength(flags, Length(data.Raws));
  for i := 0 to High(data.Raws) do
    flags[i] := TyStReadBool([StItemNode(s, data.Raws[i])], ['selected'], has);
  TySelInitFromData(FSel[s], data, flags);
end;

procedure TTyAdvanceChart.SelSyncFlags(ASlot: Integer);
var
  s, raw, inner: Integer;
  data: TTySelData;
  st: TTyDataStore;
  was: Boolean;
begin
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  s := FBindings[ASlot].SeriesIndex;
  if (s < 0) or (s > High(FSt)) or (s > High(FSel)) or not FSelInit[s] then Exit;
  if (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  data := SelData(ASlot);
  for raw := 0 to High(FSt[s].Rows) do
  begin
    if not FSt[s].Rows[raw].Host.Exists then Continue;
    inner := st.IndexOfRawIndex(raw);
    was := FSt[s].Rows[raw].Host.Selected;
    FSt[s].Rows[raw].Host.Selected := (inner >= 0)
      and TySelIsSelected(FSel[s], data, inner);
    if was <> FSt[s].Rows[raw].Host.Selected then FStDirty := True;
  end;
end;

{ makeQueryConditionKindA + findComponents: seriesIndex (a number or a
  list, in its order), else seriesId, else seriesName (in series order);
  none of them is every series }
function TTyAdvanceChart.MatchSeries(APayload: TJSONObject): TTyIntegerArray;
var
  d: TJSONData;
  i, k, n, cnt: Integer;
  want: TTyStringArray;
  byId: Boolean;
  v: string;

  procedure Add(AIndex: Integer);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AIndex;
  end;

  function KeyText(AData: TJSONData; out AText: string): Boolean;
  begin
    Result := (AData <> nil) and (AData.JSONType in [jtString, jtNumber]);
    if Result then AText := AData.AsString;
  end;

begin
  Result := nil;
  cnt := FOption.ComponentCount('series');
  d := APayload.Find('seriesIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
    begin
      for k := 0 to TJSONArray(d).Count - 1 do
        if TJSONArray(d).Items[k].JSONType = jtNumber then
        begin
          n := Trunc(TJSONArray(d).Items[k].AsFloat);
          if (n >= 0) and (n < cnt) then Add(n);
        end;
    end
    else if d.JSONType = jtNumber then
    begin
      n := Trunc(d.AsFloat);
      if (n >= 0) and (n < cnt) then Add(n);
    end;
    Exit;
  end;
  byId := True;
  d := APayload.Find('seriesId');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    byId := False;
    d := APayload.Find('seriesName');
  end;
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    for i := 0 to cnt - 1 do Add(i);
    Exit;
  end;
  want := nil;
  if d is TJSONArray then
  begin
    for k := 0 to TJSONArray(d).Count - 1 do
      if KeyText(TJSONArray(d).Items[k], v) then
      begin
        SetLength(want, Length(want) + 1);
        want[High(want)] := v;
      end;
  end
  else if KeyText(d, v) then
  begin
    SetLength(want, 1);
    want[0] := v;
  end;
  for i := 0 to cnt - 1 do
  begin
    if byId then v := SeriesModelId(i) else v := SeriesModelName(i);
    for k := 0 to High(want) do
      if want[k] = v then
      begin
        Add(i);
        Break;
      end;
  end;
end;

{ queryDataIndex (util/model.ts:704-726): dataIndexInside as it is, else
  dataIndex (raw) through indexOfRawIndex, else name -- the first inner index
  of that name. False when the payload names no item at all. }
function TTyAdvanceChart.QueryDataIndex(ASlot: Integer; APayload: TJSONObject;
  out AInner: TTyIntegerArray): Boolean;
var
  d: TJSONData;
  st: TTyDataStore;
  mode, k: Integer;

  function One(AItem: TJSONData): Integer;
  var i: Integer; nm: string;
  begin
    Result := -1;
    if mode = 2 then
    begin
      if not (AItem.JSONType in [jtString, jtNumber]) then Exit;
      nm := AItem.AsString;
      for i := 0 to st.Count - 1 do
        if st.GetItemName(i) = nm then Exit(i);
      Exit;
    end;
    if AItem.JSONType <> jtNumber then Exit;
    if Frac(AItem.AsFloat) <> 0 then Exit;
    i := Trunc(AItem.AsFloat);
    if mode = 0 then Result := i
    else Result := st.IndexOfRawIndex(i);
  end;

begin
  AInner := nil;
  Result := False;
  if (ASlot < 0) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  mode := 0;
  d := APayload.Find('dataIndexInside');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    mode := 1;
    d := APayload.Find('dataIndex');
  end;
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    mode := 2;
    d := APayload.Find('name');
  end;
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  Result := True;
  if d is TJSONArray then
  begin
    SetLength(AInner, TJSONArray(d).Count);
    for k := 0 to TJSONArray(d).Count - 1 do
      AInner[k] := One(TJSONArray(d).Items[k]);
  end
  else
  begin
    SetLength(AInner, 1);
    AInner[0] := One(d);
  end;
end;

{ model/Series.ts's id: the written one, else '\0' + name + '\0' + n, n the
  first number no earlier series took (util/model.ts:500-525) }
function TTyAdvanceChart.SeriesModelId(ASeriesIndex: Integer): string;
var
  ids: TTyStringArray;
  i, k, num: Integer;
  n, d: TJSONData;
  taken: Boolean;
  cand: string;
begin
  { THE MODEL'S, which a merge keeps [Batch 95]; made afresh below only
    where there is no model }
  Result := FOption.ComponentId('series', ASeriesIndex);
  if Result <> '' then Exit;
  ids := nil;
  SetLength(ids, ASeriesIndex + 1);
  { the written ids first: they are reserved before any is generated }
  for i := 0 to FOption.ComponentCount('series') - 1 do
  begin
    n := FOption.ComponentAt('series', i);
    if not (n is TJSONObject) then Continue;
    d := TJSONObject(n).Find('id');
    if (d <> nil) and (d.JSONType in [jtString, jtNumber]) and (i <= ASeriesIndex) then
      ids[i] := d.AsString;
  end;
  for i := 0 to ASeriesIndex do
  begin
    if ids[i] <> '' then Continue;
    num := 0;
    repeat
      cand := #0 + SeriesModelName(i) + #0 + IntToStr(num);
      Inc(num);
      taken := False;
      for k := 0 to High(ids) do
        if ids[k] = cand then taken := True;
    until not taken;
    ids[i] := cand;
  end;
  Result := ids[ASeriesIndex];
end;

function TTyAdvanceChart.HasChartHandler(const AType: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(FEventRegs) do
    if FEventRegs[i].EventType = AType then Exit(True);
  Result := False;
end;

{ an action's event: no params, no pointer, the object as JSON; a query
  never filters it (upstream's eventInfo is empty for these) }
procedure TTyAdvanceChart.EmitPayloadEvent(const AType, APayloadJson: string);
var
  ev: TTyChartEvent;
  regs: array of TTyChartEventReg;
  i: Integer;
begin
  ev := Default(TTyChartEvent);
  ev.EventType := AType;
  ev.HasParams := False;
  ev.Params := TyChartBlankParams;
  ev.HasOffset := False;
  ev.Payload := APayloadJson;
  if Assigned(FOnChartEvent) then FOnChartEvent(Self, ev);
  regs := Copy(FEventRegs);
  for i := 0 to High(regs) do
    if regs[i].EventType = AType then regs[i].Handler(Self, ev);
end;

function JsTruthy(AData: TJSONData): Boolean;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(False);
  case AData.JSONType of
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

procedure TTyAdvanceChart.DoSelectAction(APayload: TJSONObject);
var
  t, lt, sel, selMap, nm: string;
  series, inner: TTyIntegerArray;
  i, k, slot, s, kind: Integer;
  data: TTySelData;
  idx: TTyIntegerArray;
  ev, fromPayload: TJSONObject;
  d: TJSONData;
  legacy: array[0..1] of string;
  post: string;
begin
  t := APayload.Strings['type'];
  if t = 'select' then kind := 0 else if t = 'unselect' then kind := 1 else kind := 2;
  { updateDirectly: every series the query names }
  series := MatchSeries(APayload);
  for i := 0 to High(series) do
  begin
    slot := SlotOfSeries(series[i]);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    SelEnsure(slot);
    s := series[i];
    if (s > High(FSel)) or not FSelInit[s] then Continue;
    { a graph's links are not this model's data }
    d := APayload.Find('dataType');
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'edge') then Continue;
    if not QueryDataIndex(slot, APayload, inner) then Continue;
    data := SelData(slot);
    case kind of
      0: TySelSelect(FSel[s], data, inner);
      1: TySelUnselect(FSel[s], data, inner);
    else
      TySelToggle(FSel[s], data, inner);
    end;
    SelSyncFlags(slot);
  end;
  if FStDirty then InvalidateFrame;

  { THE EVENTS. First the action's own, a copy of the payload with the type
    lowercased; then selectchanged }
  lt := LowerCase(t);
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := lt;
    EmitPayloadEvent(lt, ev.AsJSON);
  finally
    ev.Free;
  end;
  { getAllSelectedIndices: the shown series with a selection, in order }
  sel := '';
  for slot := 0 to High(FBindings) do
  begin
    if FBindings[slot].Hidden then Continue;
    s := FBindings[slot].SeriesIndex;
    if (s < 0) or (s > High(FSel)) or not FSelInit[s] then Continue;
    idx := TySelIndices(FSel[s], SelData(slot));
    if Length(idx) = 0 then Continue;
    if sel <> '' then sel := sel + ',';
    sel := sel + '{"dataIndex":[';
    for k := 0 to High(idx) do
    begin
      if k > 0 then sel := sel + ',';
      sel := sel + IntToStr(idx[k]);
    end;
    sel := sel + '],"seriesIndex":' + IntToStr(s) + '}';
  end;
  d := APayload.Find('isFromClick');
  if JsTruthy(d) then post := d.AsJSON else post := 'false';
  EmitPayloadEvent('selectchanged', '{"type":"selectchanged","selected":[' + sel
    + '],"isFromClick":' + post + ',"fromAction":' + '"' + StringToJSONString(t)
    + '","fromActionPayload":' + APayload.AsJSON + ',"escapeConnect":true}');

  { THE LEGACY EVENTS (legacy/dataSelectAction.ts), only to a handler that
    asked: a click -> map/pie selectchanged, an action select -> selected,
    unselect -> unselected; once per PIE series in the selection, the map
    variant included }
  if JsTruthy(APayload.Find('isFromClick')) then post := 'selectchanged'
  else if t = 'select' then post := 'selected'
  else if t = 'unselect' then post := 'unselected'
  else post := '';
  if post = '' then Exit;
  legacy[0] := 'map' + post;
  legacy[1] := 'pie' + post;
  for k := 0 to 1 do
  begin
    if not HasChartHandler(legacy[k]) then Continue;
    for slot := 0 to High(FBindings) do
    begin
      if FBindings[slot].SeriesType <> TyPieSeriesTypeName then Continue;
      if FBindings[slot].Hidden then Continue;
      s := FBindings[slot].SeriesIndex;
      if (s < 0) or (s > High(FSel)) or not FSelInit[s] then Continue;
      if Length(TySelIndices(FSel[s], SelData(slot))) = 0 then Continue;
      nm := '';
      fromPayload := APayload;
      if QueryDataIndex(slot, fromPayload, inner) and (Length(inner) > 0)
        and (inner[0] >= 0) and (inner[0] < FStores[slot].Count) then
        nm := FStores[slot].GetItemName(inner[0]);
      selMap := TySelMapJson(FSel[s]);
      EmitPayloadEvent(legacy[k], '{"type":"' + legacy[k] + '","seriesId":"'
        + StringToJSONString(SeriesModelId(s)) + '","name":"'
        + StringToJSONString(nm) + '","selected":' + selMap + '}');
    end;
  end;
end;

{ highlight / downplay (echarts.ts:2178-2205, 1792-1865): allLeaveBlur once;
  for a highlight without notBlur, every queried series whose emphasis is
  not disabled blurs by the focus of the element the payload names (its
  first, the first element there is when that one is missing); then each
  series' view enters / leaves emphasis on the queried items (all of them
  when none) with highlightKey's bit -- a line's one-point highlight on the
  symbol PATH, with the polyline (LineView.ts:937-1026). [Batch 90] }
procedure TTyAdvanceChart.DoHighDownAction(APayload: TJSONObject);
var
  t, key: string;
  series, inner, kept: TTyIntegerArray;
  excl: TTyStringArray;
  i, k, slot, s, digit, raw, q, poly: Integer;
  d: TJSONData;
  item: PTyStItem;
  skip, has, isArr, single, isHigh: Boolean;
  ev: TJSONObject;
  focus: TTyStFocus;
  scope: TTyStScope;
  nodes: array[0..0] of TJSONObject;

  procedure Apply(var AItem: TTyStItem; AOnPath: Boolean);
  begin
    poly := StPolyOf(s);
    if isHigh then
    begin
      if TyStItemEnterEmphasisBy(AItem, digit, AOnPath, poly) then FStDirty := True;
    end
    else if TyStItemLeaveEmphasisBy(AItem, digit, AOnPath, poly) then
      FStDirty := True;
    if poly >= 0 then StPolyTo(s, poly);
  end;

  { which field queryDataIndex reads, and whether it is a list }
  function QueryIsArray: Boolean;
  var x: TJSONData;
  begin
    x := APayload.Find('dataIndexInside');
    if (x = nil) or (x.JSONType = jtNull) then x := APayload.Find('dataIndex');
    if (x = nil) or (x.JSONType = jtNull) then x := APayload.Find('name');
    Result := x is TJSONArray;
  end;

begin
  t := APayload.Strings['type'];
  isHigh := t = 'highlight';
  { getHighlightDigit: in order of first use, 1 to 32, then bit 0 }
  digit := 0;
  d := APayload.Find('highlightKey');
  if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then
  begin
    key := d.AsString;
    digit := -1;
    for i := 0 to High(FHighlightKeys) do
      if FHighlightKeys[i] = key then digit := i + 1;
    if (digit < 0) and (Length(FHighlightKeys) < 32) then
    begin
      SetLength(FHighlightKeys, Length(FHighlightKeys) + 1);
      FHighlightKeys[High(FHighlightKeys)] := key;
      digit := Length(FHighlightKeys);
    end;
    if digit < 0 then digit := 0;
  end;
  excl := nil;
  d := APayload.Find('excludeSeriesId');
  if d is TJSONArray then
  begin
    for k := 0 to TJSONArray(d).Count - 1 do
      if TJSONArray(d).Items[k].JSONType in [jtString, jtNumber] then
      begin
        SetLength(excl, Length(excl) + 1);
        excl[High(excl)] := TJSONArray(d).Items[k].AsString;
      end;
  end
  else if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then
  begin
    SetLength(excl, 1);
    excl[0] := d.AsString;
  end;

  { ONCE PER DISPATCH, before anything: every blur goes }
  StAllLeaveBlur;

  series := MatchSeries(APayload);
  kept := nil;
  for i := 0 to High(series) do
  begin
    s := series[i];
    skip := False;
    for k := 0 to High(excl) do
      if excl[k] = SeriesModelId(s) then skip := True;
    if skip then Continue;
    if (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    SetLength(kept, Length(kept) + 1);
    kept[High(kept)] := s;
  end;

  { THE BLUR, a pass of its own before any series highlights }
  if isHigh and not JsTruthy(APayload.Find('notBlur')) then
    for i := 0 to High(kept) do
    begin
      s := kept[i];
      nodes[0] := StSeriesNode(s);
      if TyStReadBool(nodes, ['emphasis', 'disabled'], has) then Continue;
      slot := SlotOfSeries(s);
      { the first index of a list; || 0 }
      q := 0;
      if QueryDataIndex(slot, APayload, inner) and (Length(inner) > 0) then q := inner[0];
      item := StItemAt(s, q);
      if item = nil then
      begin
        q := 0;
        while (item = nil) and (slot >= 0) and (slot <= High(FStores))
          and (FStores[slot] <> nil) and (q < FStores[slot].Count) do
        begin
          item := StItemAt(s, q);
          if item = nil then Inc(q);
        end;
      end;
      if item <> nil then
        focus := StItemFocus(s, StInnerRaw(s, q), scope)
      else
      begin
        { no element at all: the series' own option, only when written }
        if TyStFind(nodes, ['emphasis', 'focus']) = nil then Continue;
        focus := StSeriesFocus(s, scope);
      end;
      StBlurSeries(s, focus, scope);
    end;

  { THE EMPHASIS }
  for i := 0 to High(kept) do
  begin
    s := kept[i];
    slot := SlotOfSeries(s);
    has := QueryDataIndex(slot, APayload, inner);
    isArr := QueryIsArray;
    if FSt[s].IsLine then
    begin
      { _changePolyState first, whatever the payload names }
      if isHigh then StPolyTo(s, TyStHoverEmphasis) else StPolyTo(s, TyStHoverNormal);
      { one index (`dataIndex >= 0`: a list of one coerces on the downplay
        side only) -> Symbol.highlight / downplay: the path, bit 0 }
      if has and (Length(inner) > 0) then
      begin
        if isHigh then single := not isArr and (inner[0] >= 0)
        else single := (not isArr or (Length(inner) = 1)) and (inner[0] >= 0);
      end
      else
        single := False;
      if single then
      begin
        item := StItemAt(s, inner[0]);
        if item <> nil then
        begin
          if isHigh then
          begin
            if TyStItemEnterEmphasisBy(item^, 0, True, poly) then FStDirty := True;
          end
          else if TyStItemLeaveEmphasisBy(item^, 0, True, poly) then
            FStDirty := True;
        end;
        Continue;
      end;
    end;
    if not has then
    begin
      for raw := 0 to High(FSt[s].Rows) do
        { only a highDownDispatcher: emphasis not disabled }
        if FSt[s].Rows[raw].Host.Exists and FSt[s].Rows[raw].Host.Proxy then
          Apply(FSt[s].Rows[raw], False);
    end
    else
      for k := 0 to High(inner) do
      begin
        item := StItemAt(s, inner[k]);
        if (item <> nil) and item^.Host.Proxy then Apply(item^, False);
      end;
  end;
  if FStDirty then InvalidateFrame;
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := t;
    EmitPayloadEvent(t, ev.AsJSON);
  finally
    ev.Free;
  end;
end;

{ A NUL SURVIVES THE PARSE [Batch 93]. fpjson decodes `\u0000` to nothing
  (its scanner parks a zero code unit as half a surrogate pair), and
  upstream's generated ids are '\0' + name + '\0' + n -- so the ids a legend
  hover puts in excludeSeriesId came back as 'H0' and matched no series. The
  escape is swapped for a noncharacter (U+FDD0) before the parse and back to
  #0 in every string after it. }
function NulSafeJson(const AText: string): string;
var i, n: Integer;
begin
  Result := '';
  i := 1;
  n := Length(AText);
  while i <= n do
  begin
    if AText[i] = '\' then
    begin
      if (i + 5 <= n) and (Copy(AText, i, 6) = '\u0000') then
      begin
        Result := Result + '\ufdd0';
        Inc(i, 6);
        Continue;
      end;
      { any other escape pair passes whole, so `\\u0000` stays a backslash }
      Result := Result + Copy(AText, i, 2);
      Inc(i, 2);
      Continue;
    end;
    Result := Result + AText[i];
    Inc(i);
  end;
end;

procedure NulRestore(AData: TJSONData);
var i: Integer;
begin
  if AData = nil then Exit;
  case AData.JSONType of
    jtString:
      if Pos(#$EF#$B7#$90, AData.AsString) > 0 then
        AData.AsString := StringReplace(AData.AsString, #$EF#$B7#$90, #0, [rfReplaceAll]);
    jtArray, jtObject:
      for i := 0 to AData.Count - 1 do NulRestore(AData.Items[i]);
  end;
end;

function TTyAdvanceChart.DispatchAction(const APayloadJson: string): Boolean;
var
  d, tp: TJSONData;
  p: TJSONObject;
  t: string;
begin
  Result := False;
  try
    d := GetJSON(NulSafeJson(APayloadJson));
    NulRestore(d);
  except
    d := nil;
  end;
  if not (d is TJSONObject) then
  begin
    d.Free;
    Exit;
  end;
  p := TJSONObject(d);
  try
    tp := p.Find('type');
    if (tp = nil) or (tp.JSONType <> jtString) then Exit;
    { a batch is not taken: its events are a different shape }
    if p.Find('batch') <> nil then Exit;
    t := tp.AsString;
    if (t = 'select') or (t = 'unselect') or (t = 'toggleSelect') then
    begin
      DoSelectAction(p);
      Result := True;
    end
    else if (t = 'highlight') or (t = 'downplay') then
    begin
      DoHighDownAction(p);
      Result := True;
    end
    else if (t = 'legendToggleSelect') or (t = 'legendSelect')
      or (t = 'legendUnSelect') or (t = 'legendAllSelect')
      or (t = 'legendInverseSelect') then
    begin
      DoLegendAction(p);
      Result := True;
    end
    else if t = 'legendScroll' then
    begin
      { [Batch 98] }
      DoLegendScroll(p);
      Result := True;
    end;
  finally
    p.Free;
  end;
  { every dispatch ends with triggerUpdatedEvent [Batch 97] }
  if Result then EmitUpdated;
end;

{ echarts.ts:2341-2357: the first element on the chain with a dataIndex --
  a data item, a label for its host -- dispatches unselect when it is
  selected, select otherwise, whatever selectedMode says }
procedure TTyAdvanceChart.StClickSelect(const ATarget: TTyChartEventTarget);
var
  slot, s: Integer;
  selected: Boolean;
  p: string;
begin
  if not (ATarget.HdKind in [1, 3]) then Exit;
  s := ATarget.HdSeries;
  slot := SlotOfSeries(s);
  if slot < 0 then Exit;
  selected := False;
  { a marker's element is never flagged selected: always select }
  if (ATarget.HdKind = 1) and not ATarget.HdEdge then
  begin
    SelEnsure(slot);
    if (s <= High(FSel)) and FSelInit[s] then
      selected := TySelIsSelected(FSel[s], SelData(slot), ATarget.HdRow);
  end;
  if selected then p := '{"type":"unselect"' else p := '{"type":"select"';
  { a graph's data type rides along }
  if (ATarget.HdKind = 1) and (FBindings[slot].SeriesType = TyGraphSeriesTypeName) then
  begin
    if ATarget.HdEdge then p := p + ',"dataType":"edge"'
    else p := p + ',"dataType":"node"';
  end;
  p := p + ',"dataIndexInside":' + IntToStr(ATarget.HdRow) + ',"seriesIndex":'
    + IntToStr(s) + ',"isFromClick":true}';
  DispatchAction(p);
end;

function TTyAdvanceChart.SelectedDataIndices(ASeriesIndex: Integer): TTyIntegerArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if slot < 0 then Exit;
  SelEnsure(slot);
  if (ASeriesIndex > High(FSel)) or not FSelInit[ASeriesIndex] then Exit;
  Result := TySelIndices(FSel[ASeriesIndex], SelData(slot));
end;

function TTyAdvanceChart.SelectedMapText(ASeriesIndex: Integer): string;
var slot: Integer;
begin
  Result := 'null';
  slot := SlotOfSeries(ASeriesIndex);
  if slot >= 0 then SelEnsure(slot);
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSel)) or not FSelInit[ASeriesIndex] then Exit;
  Result := TySelMapJson(FSel[ASeriesIndex]);
end;

function TTyAdvanceChart.LegendSelectedText(AIndex: Integer): string;
begin
  Result := TyLegendSelectedJson(FOption, AIndex);
end;

{ ==================== the legend's actions [Batch 93] ==================== }

function TTyAdvanceChart.LegendQuery(APayload: TJSONObject): TTyIntegerArray;
var
  d, x: TJSONData;
  i, k, n, cnt: Integer;
  byId: Boolean;
  v: string;
  node: TJSONObject;

  procedure Add(AIndex: Integer);
  var j: Integer;
  begin
    for j := 0 to High(Result) do
      if Result[j] = AIndex then Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AIndex;
  end;

  function Wanted(AValue: string): Boolean;
  var j: Integer;
  begin
    Result := False;
    if d is TJSONArray then
    begin
      for j := 0 to TJSONArray(d).Count - 1 do
        if (TJSONArray(d).Items[j].JSONType in [jtString, jtNumber])
          and (TJSONArray(d).Items[j].AsString = AValue) then Exit(True);
    end
    else if d.JSONType in [jtString, jtNumber] then
      Result := d.AsString = AValue;
  end;

begin
  Result := nil;
  cnt := Length(FLegendSpecs);
  { the index (a number or a list), else the id, else the name -- in
    component order for the last two }
  d := APayload.Find('legendIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
    begin
      for k := 0 to TJSONArray(d).Count - 1 do
        if TJSONArray(d).Items[k].JSONType = jtNumber then
        begin
          n := Trunc(TJSONArray(d).Items[k].AsFloat);
          if (n >= 0) and (n < cnt) then Add(n);
        end;
    end
    else if d.JSONType = jtNumber then
    begin
      n := Trunc(d.AsFloat);
      if (n >= 0) and (n < cnt) then Add(n);
    end;
    Exit;
  end;
  byId := True;
  d := APayload.Find('legendId');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    byId := False;
    d := APayload.Find('legendName');
  end;
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    for i := 0 to cnt - 1 do Add(i);
    Exit;
  end;
  for i := 0 to cnt - 1 do
  begin
    node := nil;
    if FOption.ComponentAt('legend', i) is TJSONObject then
      node := TJSONObject(FOption.ComponentAt('legend', i));
    if node = nil then Continue;
    { the MODEL's id -- the generated one when the option wrote none, which
      is what the selector and the pager dispatch with [Batch 98] }
    v := '';
    if byId then v := ComponentModelId('legend', i);
    if v = '' then
    begin
      if byId then x := node.Find('id') else x := node.Find('name');
      if (x = nil) or not (x.JSONType in [jtString, jtNumber]) then Continue;
      v := x.AsString;
    end;
    if Wanted(v) then Add(i);
  end;
end;

procedure TTyAdvanceChart.LegendSelectedMapInto(AIndex: Integer; AMap: TJSONObject);
var
  i, k: Integer;
  nm: string;
  on_: Boolean;
begin
  if (AIndex < 0) or (AIndex > High(FLegendEntries)) then Exit;
  for i := 0 to High(FLegendEntries[AIndex]) do
  begin
    nm := FLegendEntries[AIndex][i].Name;
    { a wrap element is no item }
    if (nm = '') or (nm = #10) then Continue;
    on_ := TyLegendIsSelected(FOption, AIndex, FLegendAvailable, nm);
    { unselected if any legend is unselected }
    k := AMap.IndexOfName(nm);
    if k >= 0 then AMap.Booleans[nm] := AMap.Booleans[nm] and on_
    else AMap.Booleans[nm] := on_;
  end;
end;

{ the map as JSON in JavaScript's key order }
function JsMapJson(AMap: TJSONObject): string;
var keys: TTyLegendNames; i: Integer;
begin
  keys := TyJsKeyOrder(AMap);
  Result := '{';
  for i := 0 to High(keys) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '"' + StringToJSONString(keys[i]) + '":'
      + AMap.Find(keys[i]).AsJSON;
  end;
  Result := Result + '}';
end;

procedure TTyAdvanceChart.DoLegendAction(APayload: TJSONObject);
var
  t, ev, nm, nameJson, idx: string;
  isAll: Boolean;
  legends: TTyIntegerArray;
  i, k: Integer;
  map, all_: TJSONObject;
  keys: TTyLegendNames;
  d: TJSONData;
begin
  t := APayload.Strings['type'];
  if t = 'legendToggleSelect' then ev := 'legendselectchanged'
  else if t = 'legendSelect' then ev := 'legendselected'
  else if t = 'legendUnSelect' then ev := 'legendunselected'
  else if t = 'legendAllSelect' then ev := 'legendselectall'
  else ev := 'legendinverseselect';
  isAll := (t = 'legendAllSelect') or (t = 'legendInverseSelect');
  { payload.name as JavaScript keys it: a missing name is the key
    'undefined' and leaves the event's name out }
  d := APayload.Find('name');
  if d = nil then
  begin
    nm := 'undefined';
    nameJson := '';
  end
  else
  begin
    case d.JSONType of
      jtString, jtNumber: nm := d.AsString;
      jtNull: nm := 'null';
      jtBoolean: if d.AsBoolean then nm := 'true' else nm := 'false';
    else
      nm := d.AsString;
    end;
    nameJson := d.AsJSON;
  end;
  map := TJSONObject.Create;
  all_ := TJSONObject.Create;
  try
    { the method on every legend the payload names, and their map }
    legends := LegendQuery(APayload);
    for i := 0 to High(legends) do
    begin
      k := legends[i];
      if t = 'legendToggleSelect' then
        TyLegendToggleName(FOption, k, FLegendEntries[k], FLegendSpecs[k].SelectedMode, nm)
      else if t = 'legendSelect' then
        TyLegendSelectName(FOption, k, FLegendEntries[k], FLegendSpecs[k].SelectedMode, nm)
      else if t = 'legendUnSelect' then
        TyLegendUnSelectName(FOption, k, FLegendSpecs[k].SelectedMode, nm)
      else if t = 'legendAllSelect' then
        TyLegendAllSelect(FOption, k, FLegendEntries[k])
      else
        TyLegendInverseSelect(FOption, k, FLegendEntries[k]);
      LegendSelectedMapInto(k, map);
    end;
    { EVERY LEGEND IS FORCED TO THE SAME STATUSES -- which writes every name
      of the map into every legend's `selected`, and re-enforces single
      mode (legendAction.ts:52-64) }
    keys := TyJsKeyOrder(map);
    for k := 0 to High(FLegendSpecs) do
    begin
      for i := 0 to High(keys) do
        if map.Booleans[keys[i]] then
          TyLegendSelectName(FOption, k, FLegendEntries[k], FLegendSpecs[k].SelectedMode, keys[i])
        else
          TyLegendUnSelectName(FOption, k, FLegendSpecs[k].SelectedMode, keys[i]);
      LegendSelectedMapInto(k, all_);
    end;
    { the update runs before the event is published }
    FullUpdate;
    if isAll then
    begin
      idx := '';
      for i := 0 to High(legends) do
      begin
        if i > 0 then idx := idx + ',';
        idx := idx + IntToStr(legends[i]);
      end;
      EmitPayloadEvent(ev, '{"selected":' + JsMapJson(all_) + ',"legendIndex":['
        + idx + '],"type":"' + ev + '"}');
    end
    else if nameJson <> '' then
      EmitPayloadEvent(ev, '{"name":' + nameJson + ',"selected":' + JsMapJson(all_)
        + ',"type":"' + ev + '"}')
    else
      EmitPayloadEvent(ev, '{"selected":' + JsMapJson(all_) + ',"type":"' + ev + '"}');
  finally
    map.Free;
    all_.Free;
  end;
end;

{ every raw series whose legendHoverLink is falsy: the option's value, else
  the type's default -- true where a type's defaultOption says so, undefined
  (falsy) elsewhere (a heatmap, a sunburst, a treemap, a tree, a sankey) }
function TTyAdvanceChart.LegendExcludeIds: string;
const
  cLinked: array[0..14] of string = ('bar', 'pictorialBar', 'line', 'scatter',
    'effectScatter', 'pie', 'funnel', 'gauge', 'graph', 'radar', 'candlestick',
    'boxplot', 'lines', 'custom', 'chord');
var
  i, k: Integer;
  n, d: TJSONData;
  linked: Boolean;
  tp: string;
begin
  Result := '[';
  for i := 0 to FOption.ComponentCount('series') - 1 do
  begin
    n := FOption.ComponentAt('series', i);
    { eachRawSeries never meets an index hole [Batch 97] }
    if not (n is TJSONObject) then Continue;
    d := nil;
    tp := '';
    if n is TJSONObject then
    begin
      d := TJSONObject(n).Find('legendHoverLink');
      tp := TJSONObject(n).Get('type', '');
    end;
    if (d <> nil) and (d.JSONType <> jtNull) then
      linked := JsTruthy(d)
    else
    begin
      linked := False;
      for k := 0 to High(cLinked) do
        if cLinked[k] = tp then linked := True;
    end;
    if linked then Continue;
    if Result <> '[' then Result := Result + ',';
    Result := Result + '"' + StringToJSONString(SeriesModelId(i)) + '"';
  end;
  Result := Result + ']';
end;

procedure TTyAdvanceChart.LegendHighDown(const ATarget: TTyChartEventTarget;
  const AType: string);
var p: string;
begin
  p := '{"type":"' + AType + '","seriesName":';
  if ATarget.HdLegendSeries then
    p := p + '"' + StringToJSONString(ATarget.HdName) + '","name":null'
  else
    p := p + 'null,"name":"' + StringToJSONString(ATarget.HdName) + '"';
  DispatchAction(p + ',"excludeSeriesId":' + LegendExcludeIds + '}');
end;

procedure TTyAdvanceChart.LegendClick(const ATarget: TTyChartEventTarget);
begin
  { downplay before unselect, highlight after select (LegendView.ts:709-724) }
  LegendHighDown(ATarget, 'downplay');
  DispatchAction('{"type":"legendToggleSelect","name":"'
    + StringToJSONString(ATarget.HdName) + '"}');
  LegendHighDown(ATarget, 'highlight');
end;

procedure TTyAdvanceChart.LegendSelectorClick(const ATarget: TTyChartEventTarget);
var k, b: Integer; p: string;
begin
  k := ATarget.HdSeries;
  b := ATarget.HdRow;
  if (k < 0) or (k > High(FLegends)) or (b < 0) or (b > High(FLegends[k].Selector)) then Exit;
  if FLegends[k].Selector[b].IsAll then p := '{"type":"legendAllSelect"'
  else p := '{"type":"legendInverseSelect"';
  DispatchAction(p + ',"legendId":"' + StringToJSONString(ComponentModelId('legend', k))
    + '"}');
end;

procedure TTyAdvanceChart.LegendPagerClick(const ATarget: TTyChartEventTarget);
var k, toIdx: Integer;
begin
  k := ATarget.HdSeries;
  if (k < 0) or (k > High(FLegends)) or not FLegends[k].IsScroll then Exit;
  if ATarget.HdRow = 0 then toIdx := FLegends[k].PagePrevIndex
  else toIdx := FLegends[k].PageNextIndex;
  { `scrollDataIndex != null && dispatchAction(...)` }
  if toIdx < 0 then Exit;
  DispatchAction('{"type":"legendScroll","scrollDataIndex":' + IntToStr(toIdx)
    + ',"legendId":"' + StringToJSONString(ComponentModelId('legend', k)) + '"}');
end;

procedure TTyAdvanceChart.DoLegendScroll(APayload: TJSONObject);
var
  d: TJSONData;
  legends: TTyIntegerArray;
  i, k: Integer;
  ev: TJSONObject;
begin
  d := APayload.Find('scrollDataIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    { eachComponent over the legends of subType 'scroll' the query names }
    legends := LegendQuery(APayload);
    for i := 0 to High(legends) do
    begin
      k := legends[i];
      if (k <= High(FLegendSpecs)) and FLegendSpecs[k].IsScroll then
        TyLegendSetScrollDataIndex(FOption, k, d);
    end;
  end;
  { the default update, then the event: the payload with its type renamed }
  FullUpdate;
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := 'legendscroll';
    EmitPayloadEvent('legendscroll', ev.AsJSON);
  finally
    ev.Free;
  end;
end;

function TTyAdvanceChart.LegLive: Boolean;
begin
  Result := (FLegAnim <> nil) and (FLegAnim.ClipCount > 0);
end;

procedure TTyAdvanceChart.LegAnimDrop;
var i: Integer;
begin
  { the proxies before the driver: freeing one takes its clips off it }
  for i := 0 to High(FLegProxies) do FreeAndNil(FLegProxies[i]);
  FLegProxies := nil;
end;

procedure TTyAdvanceChart.LegAnimSync;
var
  i: Integer;
  lay: TTyLegendLayout;
  p: TTyChartAnimProxy;
  props: TTyAnimProps;
  model: TTyAnimModel;
begin
  for i := Length(FLegends) to High(FLegProxies) do FreeAndNil(FLegProxies[i]);
  SetLength(FLegProxies, Length(FLegends));
  for i := 0 to High(FLegends) do
  begin
    lay := FLegends[i];
    if not (lay.Valid and lay.IsScroll) then
    begin
      FreeAndNil(FLegProxies[i]);
      Continue;
    end;
    props := TyAnimProps([TyAnimProp('x', TyAnimNum(lay.ContentPosX)),
      TyAnimProp('y', TyAnimNum(lay.ContentPosY))]);
    p := FLegProxies[i];
    if p = nil then
    begin
      if FLegAnim = nil then FLegAnim := TTyAnimation.Create;
      p := TTyChartAnimProxy.Create(-1, i, 'legend.scroll');
      p.Animation := FLegAnim;
      { THE FIRST RENDER: the content group stands unscrolled }
      p.Attr(TyAnimProps([TyAnimProp('x', TyAnimNum(lay.ContentFromX)),
        TyAnimProp('y', TyAnimNum(lay.ContentFromY))]));
      FLegProxies[i] := p;
    end;
    { the cross axis is setPosition's, at once: only the scroll moves }
    if FLegendSpecs[i].Orient = tloVertical then
      p.Attr(TyAnimProps([TyAnimProp('x', TyAnimNum(lay.ContentPosX))]))
    else
      p.Attr(TyAnimProps([TyAnimProp('y', TyAnimNum(lay.ContentPosY))]));
    p.SetFinal(props);
    { `showController ? legendModel : null`: a hidden pager snaps }
    if lay.ShowController and AnimAllowed then
      model := TyAnimComponentModel(FOption.ComponentAt('legend', i), FOption.Root,
        'legend.scroll')
    else
      model := TyAnimNoModel;
    TyUpdateProps(p, props, model, TyAnimCallNoIndex);
  end;
  AnimArmTimer;
end;

procedure TTyAdvanceChart.LegendSelHover(ALegend, AIndex: Integer);
begin
  if (FLegendSelHoverLegend = ALegend) and (FLegendSelHoverIdx = AIndex) then Exit;
  FLegendSelHoverLegend := ALegend;
  FLegendSelHoverIdx := AIndex;
  { the button is drawn in the static layer: a new ink is a new picture }
  if FStatic <> nil then FStatic.Drop;
  InvalidateFrame;
end;

function TTyAdvanceChart.TargetOfElement(AIndex: Integer): TTyChartEventTarget;
var d: TTyChartDatumRef;
begin
  d := FPaintList.Element(AIndex).Datum;
  Result := SeriesEventTarget(d, AIndex);
  Result.HdSeries := d.SeriesIndex;
  Result.HdRow := d.DataIndex;
  Result.HdEdge := d.IsEdge;
  if d.DataIndex >= 0 then Result.HdKind := 1 else Result.HdKind := 2;
end;

procedure TTyAdvanceChart.FullUpdate;
var
  m: ITyTextMeasurer;
  hk, hs, hraw, slot, inner: Integer;
begin
  { nothing laid out yet: the first paint does it all }
  if (FLastPPI <= 0) or (FBuild = nil) then
  begin
    FDirty := True;
    Invalidate;
    Exit;
  end;
  { THE HOVERED ELEMENT, by series and RAW row: a reused element keeps being
    the hovered one, whatever index the new list gives it }
  hk := FEvHover.HdKind;
  hs := FEvHover.HdSeries;
  hraw := -1;
  if (FEvHover.Id > 0) and (hk = 1) then hraw := StInnerRaw(hs, FEvHover.HdRow);
  m := NewTextMeasurer(FLastPPI);
  { renderSeries: clearStates, render, the previous states, then the flags
    (the generation Relayout moves) }
  Relayout(nil, FLastRect, FLastPPI, m);
  { AN ACTION THAT UPDATES does the lazy update waiting, and the dispatch
    publishes the one `updated` (echarts.ts doDispatchAction) [Batch 97] }
  FLazyPending := False;
  BuildSeriesList(m, FLastPPI);
  if FEvHover.Id > 0 then
  begin
    if (hk = 1) and (hraw >= 0) and (hs <= High(FSt)) and (FSt[hs].Kind <> sskNone)
      and (hraw <= High(FSt[hs].HostIdx)) and (FSt[hs].HostIdx[hraw] >= 0) then
    begin
      FEvHover := TargetOfElement(FSt[hs].HostIdx[hraw]);
      slot := SlotOfSeries(hs);
      inner := FStores[slot].IndexOfRawIndex(hraw);
      FEvHover.HdRow := inner;
    end
    else if (hk = 2) and (hs <= High(FSt)) and (FSt[hs].Kind <> sskNone)
      and (Length(FSt[hs].RunIdx) > 0) then
      FEvHover := TargetOfElement(FSt[hs].RunIdx[0])
    else
      { REMOVED BY THE RE-RENDER -- a legend item always is: zrender finds
        the hovered target again at the point it was found (#6198), with no
        out and no over }
      FEvHover := EventTargetAt(FEvLastX, FEvLastY);
  end;
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  { the cached picture is the old render's; the list is the new one's }
  if FStatic <> nil then FStatic.Drop;
  inherited Invalidate;
end;

procedure TTyAdvanceChart.LegendBorderOf(ASlot, ARaw: Integer;
  var ASrc: TTyLegendSource);
var
  s, k: Integer;
  t: string;
  nodes: array[0..1] of TJSONObject;
  st, d: TJSONData;
  col: TTyChartColor;
begin
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  s := FBindings[ASlot].SeriesIndex;
  t := FBindings[ASlot].SeriesType;
  ASrc.HasStroke := False;
  ASrc.Stroke := 0;
  ASrc.VisualLineWidth := 0;
  { the types' own defaults: a pie's borderWidth 1 (no colour), a funnel's
    1 in the chart's ground colour (tokens.color.neutral00) }
  if t = TyPieSeriesTypeName then ASrc.VisualLineWidth := 1
  else if t = TyFunnelSeriesTypeName then
  begin
    ASrc.VisualLineWidth := 1;
    ASrc.HasStroke := True;
    ASrc.Stroke := TTyChartColor(ActiveController.Model.ResolveStyle(
      GetStyleTypeKey, StyleClass, [tysNormal]).Background.Color);
  end;
  { the series' itemStyle, then the datum's }
  nodes[0] := StSeriesNode(s);
  nodes[1] := nil;
  if ARaw >= 0 then nodes[1] := StItemNode(s, ARaw);
  for k := 0 to 1 do
  begin
    if nodes[k] = nil then Continue;
    st := nodes[k].Find('itemStyle');
    if not (st is TJSONObject) then Continue;
    d := TJSONObject(st).Find('borderColor');
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      if TyTryParseChartColor(d.AsString, col) then
      begin
        ASrc.HasStroke := True;
        ASrc.Stroke := col;
      end
      else
        ASrc.HasStroke := False;
    end;
    d := TJSONObject(st).Find('borderWidth');
    if (d <> nil) and (d.JSONType = jtNumber) then ASrc.VisualLineWidth := d.AsFloat;
  end;
end;

function TTyAdvanceChart.ItemStates(ASeriesIndex, ADataIndex: Integer;
  out AItem: TTyStItem): Boolean;
var item: PTyStItem;
begin
  AItem := Default(TTyStItem);
  item := StItemAt(ASeriesIndex, ADataIndex);
  Result := item <> nil;
  if Result then AItem := item^;
end;

function TTyAdvanceChart.LineStates(ASeriesIndex: Integer; out ARun,
  AArea: TTyStItem): Boolean;
begin
  ARun := Default(TTyStItem);
  AArea := Default(TTyStItem);
  Result := (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt))
    and FSt[ASeriesIndex].IsLine and FSt[ASeriesIndex].Run.Host.Exists;
  if not Result then Exit;
  ARun := FSt[ASeriesIndex].Run;
  AArea := FSt[ASeriesIndex].Area;
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

{ THE POINTER'S LABEL, and the axis tooltip's header. A named handler is
  given upstream's getValueLabel params: first the axis itself (its dimension,
  index and the value), then one entry per series the pointer collected --
  params.seriesData, in the order the hit holds them. }
function TTyAdvanceChart.PointerLabelText(const AHit: TTyAxisHit;
  AValue: Double): string;
var
  prm: TTyChartParams;
  k, n, slot: Integer;
begin
  if (AHit.Axis = nil) or not AHit.Spec.LabelSpec.HasFormatter
    or not TyChartIsHandlerRef(AHit.Spec.LabelSpec.Formatter) then
    Exit(AxisValueText(AHit.Axis, AValue, AHit.Spec.LabelSpec));
  prm := nil;
  SetLength(prm, 1);
  prm[0] := TyChartBlankParams;
  prm[0].ComponentType := AHit.Axis.Dim + 'Axis';
  prm[0].AxisDimension := AHit.Axis.Dim;
  prm[0].AxisIndex := AHit.Axis.ComponentIndex;
  SetLength(prm[0].Values, 1);
  prm[0].Values[0] := AValue;
  prm[0].ValueText := TyChartValueText(AValue);
  { a category axis hands over the category, not its ordinal }
  if AHit.Axis.Scale is TTyOrdinalScale then
  begin
    prm[0].Name := TTyOrdinalScale(AHit.Axis.Scale).GetLabel(AValue);
    prm[0].ValueText := prm[0].Name;
  end;
  prm[0].DefaultText := AxisValueText(AHit.Axis, AValue,
    Default(TTyAxisPointerLabelSpec));
  n := 1;
  for k := 0 to High(AHit.Slots) do
  begin
    slot := AHit.Slots[k];
    if (slot < 0) or (slot > High(FBindings)) or (slot > High(FStores))
      or (FStores[slot] = nil) then Continue;
    SetLength(prm, n + 1);
    prm[n] := TooltipParams(TyChartDatum(FBindings[slot].SeriesIndex,
      AHit.Rows[k], FStores[slot].GetRawIndex(AHit.Rows[k])));
    Inc(n);
  end;
  Result := TyChartRunHandler(AHit.Spec.LabelSpec.Formatter, prm);
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

{ THE ROOT textStyle OVER A THEME FONT: always its font, and its colour where
  the text stands free rather than on a mark [Batch 83] }
procedure TTyAdvanceChart.GlobalInk(var AName: string; var ASize,
  AWeight: Integer; var AColour: TTyChartColor; APick: TTyTextPick);
var
  has: Boolean;
  col: Cardinal;
begin
  has := False;
  col := 0;
  GlobalTextOver(AName, ASize, AWeight, has, col, APick);
  if has then AColour := TTyChartColor(col);
end;

{ backgroundColor as the option writes it, when it is a colour that paints:
  not 'transparent', not 'none', not unreadable, not fully clear }
function TTyAdvanceChart.AuthorBackground(out AColour: TTyChartColor): Boolean;
var d: TJSONData;
begin
  Result := False;
  AColour := 0;
  if FOption = nil then Exit;
  d := FOption.Find('backgroundColor');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  if not TyTryParseChartColor(d.AsString, AColour) then Exit;
  Result := (AColour shr 24) > 0;
end;

procedure TTyAdvanceChart.LabelGround(out AGround: TTyChartColor;
  out ADark: Boolean);
var
  a, l: Double;
  d: TJSONData;
  authored, forced: Boolean;
  k: Integer;
  ch: array[0..2] of Double;
begin
  { the option's ground where it paints one, else the skin's [Batch 83] }
  authored := AuthorBackground(AGround);
  if not authored then
    AGround := TTyChartColor(ActiveController.Model.ResolveStyle(GetStyleTypeKey,
      StyleClass, [tysNormal]).Background.Color);
  { zrender's lum with a background of ONE: what shows through a translucent
    ground counts as white. Dark under 0.4. }
  a := ((AGround shr 24) and $FF) / 255;
  l := TyLabelLuminance(AGround) + (1 - a);
  ADark := l < 0.4;
  { darkMode FORCES THE ANSWER when it is a boolean: upstream's
    zr.setDarkMode after the ground set it -- null and 'auto' keep the
    luminance's [Batch 83] }
  forced := False;
  if FOption <> nil then
  begin
    d := FOption.Find('darkMode');
    if (d <> nil) and (d.JSONType = jtBoolean) then
    begin
      ADark := d.AsBoolean;
      forced := True;
    end;
  end;
  { THE GROUND AN OUTSIDE LABEL IS HALOED IN is getOutsideStroke's: the
    background over black when dark, over white when not, made opaque. With
    no background written upstream's is transparent -- black or white
    outright -- which the skin's own ground stands in for unless darkMode was
    forced. [Batch 83] }
  if not authored and forced then AGround := 0;
  if authored or forced then
  begin
    a := ((AGround shr 24) and $FF) / 255;
    ch[0] := (AGround shr 16) and $FF;
    ch[1] := (AGround shr 8) and $FF;
    ch[2] := AGround and $FF;
    for k := 0 to 2 do
      if ADark then ch[k] := ch[k] * a
      else ch[k] := ch[k] * a + 255 * (1 - a);
    AGround := TTyChartColor($FF000000 or (Cardinal(Round(ch[0])) shl 16)
      or (Cardinal(Round(ch[1])) shl 8) or Cardinal(Round(ch[2])));
  end;
end;

function TTyAdvanceChart.IsGraphDatum(const ADatum: TTyChartDatumRef): Boolean;
var slot: Integer;
begin
  Result := False;
  if ADatum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  Result := (slot >= 0) and (slot <= High(FGraphLaidOut)) and FGraphLaidOut[slot];
end;

function TTyAdvanceChart.IsTreeDatum(const ADatum: TTyChartDatumRef): Boolean;
var slot: Integer;
begin
  Result := False;
  if ADatum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  Result := (slot >= 0) and (slot <= High(FTrees)) and FTrees[slot].Valid
    and (FBindings[slot].SeriesType = TyTreeSeriesTypeName);
end;

{ a tree row's emphasis: the series', `leaves` over it for a leaf-modelled
  row, the item over both }
function TTyAdvanceChart.TreeEmphasisOf(ASlot, ARow: Integer): TTyChartEmphasisSpec;
var ser, lv: TJSONData;
begin
  Result := TyChartEmphasisDefault;
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (ser is TJSONObject) then Exit;
  Result := TyChartReadEmphasis(ser);
  if (ARow <= High(FTrees[ASlot].LeafModelled)) and FTrees[ASlot].LeafModelled[ARow] then
  begin
    lv := TJSONObject(ser).Find('leaves');
    if lv is TJSONObject then
      Result := TyChartMergeEmphasis(Result, TyChartReadEmphasis(lv));
  end;
  if (ARow > 0) and (ARow <= High(FTrees[ASlot].Hier.Nodes))
    and (FTrees[ASlot].Hier.Nodes[ARow].Item is TJSONObject) then
    Result := TyChartMergeEmphasis(Result,
      TyChartReadEmphasis(FTrees[ASlot].Hier.Nodes[ARow].Item));
end;

{ `emphasis.focus` along item -> leaves -> series, as the word it is: the
  tree reads three more than any other series }
function TTyAdvanceChart.TreeFocusOf(ASlot, ARow: Integer): string;
var
  ser, d: TJSONData;
  k: Integer;
  chain: array[0..2] of TJSONData;
begin
  Result := 'none';
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (ser is TJSONObject) then Exit;
  chain[0] := nil;
  if (ARow > 0) and (ARow <= High(FTrees[ASlot].Hier.Nodes)) then
    chain[0] := FTrees[ASlot].Hier.Nodes[ARow].Item;
  chain[1] := nil;
  if (ARow <= High(FTrees[ASlot].LeafModelled)) and FTrees[ASlot].LeafModelled[ARow] then
    chain[1] := TJSONObject(ser).Find('leaves');
  chain[2] := ser;
  for k := 0 to 2 do
  begin
    if not (chain[k] is TJSONObject) then Continue;
    d := TJSONObject(chain[k]).Find('emphasis');
    if not (d is TJSONObject) then Continue;
    d := TJSONObject(d).Find('focus');
    if (d <> nil) and (d.JSONType = jtString) then Exit(d.AsString);
    if (d <> nil) and (d.JSONType <> jtNull) then Exit('none');
  end;
end;

procedure TTyAdvanceChart.ApplyTreeHover(AList: TTyPaintList; APPI: Integer);
var
  hs, r, n, i, k, row, par, si: Integer;
  focus: string;
  blurAll: Boolean;
  spec, es: TTyChartEmphasisSpec;
  symSt, edgeSt: array of TTyGraphHoverState;
  order, anc: TTyIntegerArray;
  el: TTyChartElement;
  st: TTyGraphHoverState;
  isCaption, isSymbol: Boolean;
  normal, res: TTyChartStyle;
  states: TTyChartStateList;
  ratio: Double;

  procedure Push(ARow: Integer);
  begin
    SetLength(order, Length(order) + 1);
    order[High(order)] := ARow;
  end;

  function Blurred(ADeclared, ANormal: Double): Double;
  begin
    if not IsNan(ADeclared) then Result := ADeclared
    else Result := ANormal * TyChartBlurOpacityFactor;
  end;

begin
  if (AList = nil) or not TyChartDatumValid(FTipDatum) then Exit;
  if FTipDatum.IsEdge or not IsTreeDatum(FTipDatum) then Exit;
  hs := SlotOfSeries(FTipDatum.SeriesIndex);
  r := FTipDatum.DataIndex;
  n := Length(FTrees[hs].Hier.Nodes);
  if (r <= 0) or (r >= n) or not FTrees[hs].Pos[r].Placed then Exit;
  spec := TreeEmphasisOf(hs, r);
  { a disabled emphasis is no hover at all }
  if spec.Disabled then Exit;
  focus := TreeFocusOf(hs, r);
  if focus = 'adjacency' then focus := 'self';
  blurAll := (focus = 'self') or (focus = 'ancestor') or (focus = 'descendant')
    or (focus = 'relative');
  SetLength(symSt, n);
  SetLength(edgeSt, n);
  for i := 0 to n - 1 do
  begin
    if blurAll then symSt[i] := ghsBlur else symSt[i] := ghsNormal;
    edgeSt[i] := symSt[i];
  end;
  { THE ROWS THAT LEAVE THE BLUR, in upstream's order }
  order := nil;
  if (focus = 'ancestor') or (focus = 'relative') then
  begin
    anc := nil;
    row := r;
    while row > 0 do
    begin
      SetLength(anc, Length(anc) + 1);
      anc[High(anc)] := row;
      row := FTrees[hs].Hier.Nodes[row].Parent;
    end;
    for i := High(anc) downto 0 do Push(anc[i]);
  end;
  if (focus = 'descendant') or (focus = 'relative') then
  begin
    { the row and its pre-order subtree, contiguous }
    Push(r);
    i := r + 1;
    while (i < n) and (FTrees[hs].Hier.Nodes[i].Depth > FTrees[hs].Hier.Nodes[r].Depth) do
    begin
      if FTrees[hs].Pos[i].Placed then Push(i);
      Inc(i);
    end;
  end;
  if Length(order) = 0 then Push(r);
  for k := 0 to High(order) do
  begin
    row := order[k];
    if row = r then symSt[row] := ghsEmphasis else symSt[row] := ghsNormal;
    { a row's own edge follows it only when its parent's symbol is not
      blurred at this moment }
    par := FTrees[hs].Hier.Nodes[row].Parent;
    if (par > 0) and (symSt[par] <> ghsBlur) then edgeSt[row] := symSt[row]
    else if par <= 0 then edgeSt[row] := symSt[row];
  end;

  si := FTipDatum.SeriesIndex;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Datum.SeriesIndex <> si) or (el.Datum.DataIndex < 0)
      or (el.Datum.DataIndex >= n) then Continue;
    row := el.Datum.DataIndex;
    isCaption := el.Caption.FontSizeLogical > 0;
    isSymbol := not isCaption and (el.Z2 >= FTrees[hs].Spec.Z2 + cTyTreeNodeZ2);
    if isCaption or isSymbol then st := symSt[row] else st := edgeSt[row];
    if st = ghsNormal then Continue;
    es := TreeEmphasisOf(hs, row);
    if st = ghsBlur then
    begin
      if isCaption then el.Style.Alpha := Blurred(es.BlurLabelOpacity, el.Style.Alpha)
      else if isSymbol then el.Style.Alpha := Blurred(es.BlurItemOpacity, el.Style.Alpha)
      else el.Style.Alpha := Blurred(es.BlurLineOpacity, el.Style.Alpha);
      AList.SetElement(i, el);
      Continue;
    end;
    states := Default(TTyChartStateList);
    states.Emphasis := True;
    if isCaption then
    begin
      el.Z2 := el.Z2 + TyChartEmphasisZ2Lift;
      { the block's pieces too [Batch 86] }
      TyCaptionToEmphasis(el.Caption);
    end
    else if not isSymbol then
    begin
      { the edge: its stroke lifted unless declared, a width only if so }
      normal := TyChartNoStyle;
      TyChartSetColor(normal, cskStroke, el.Style.StrokeColor);
      TyChartSetNum(normal, cskOpacity, el.Style.Alpha);
      res := TyChartResolveStyle(normal, es.Line, states);
      el.Style.StrokeColor := res.Color[cskStroke];
      if TyChartStyleHas(es.Line, cskLineWidth) then
        el.Style.StrokeWidthLogical := es.Line.Num[cskLineWidth];
      if TyChartStyleHas(res, cskOpacity) then el.Style.Alpha := res.Num[cskOpacity];
      el.Z2 := el.Z2 + TyChartEmphasisZ2Lift;
    end
    else
    begin
      { the symbol: its fill lifted unless declared, grown about its centre }
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
        ratio := TyChartSymbolScaleRatio(es, (el.Shape.Bounds.Bottom - el.Shape.Bounds.Top) / 2);
      if ratio <> 1 then el.Shape := TyScaleShape(el.Shape, ratio);
      el.Z2 := el.Z2 + TyChartEmphasisZ2Lift;
    end;
    AList.SetElement(i, el);
  end;
  if APPI < 0 then ;
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
      { the block's pieces too [Batch 86] }
      TyCaptionToEmphasis(el.Caption);
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
  i, j, k, slot: Integer;

  procedure Lift(AIndex: Integer);
  var j: Integer; cap: TTyChartElement;
  begin
    if AIndex < 0 then Exit;
    { A GRAPH'S HOVER IS IN THE STATIC LAYER ALREADY -- see
      ApplyGraphHover. }
    if IsGraphDatum(FPaintList.Element(AIndex).Datum) then Exit;
    if IsTreeDatum(FPaintList.Element(AIndex).Datum) then Exit;
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
      { the block's pieces too [Batch 86] }
      TyCaptionToEmphasis(cap.Caption);
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
        j := FPaintList.IndexOfDatum(FBindings[slot].SeriesIndex,
          AHits[i].Rows[k]);
        { a row the states already show in emphasis is drawn so in the static
          layer [Batch 88] }
        if not StEmphasised(j) then Lift(j);
      end;
    { And an item hover highlights the one thing under the pointer -- unless
      it is one the states draw, whose hover is its flag [Batch 88]. }
    if (Length(AHits) = 0) and not StOwnsElement(FTipElement) then
      Lift(FTipElement);
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
    { ON ITS WAY THERE: the pointer, and the label with it [Batch 92] }
    at := PtrAt(hit, at);

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
    txt := PointerLabelText(hit, pv);
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
  header, valueText, vf: string;
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
    header := PointerLabelText(AHits[i], AHits[i].SnapValue);
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
      { THE SERIES' OWN valueFormatter, else the global one: upstream builds
        each row's from the series and the component, never the item. }
      vf := TyTooltipSpecOf(FOption, FBindings[slot].SeriesIndex, -1).ValueFormatter;
      if (vf <> '') and cells.MultiLine then
      begin
        { as in an item tooltip: each sub-row by itself and without an
          index, the row itself with the empty list }
        valueText := TipValueFormatted(vf, p, '', True);
        for j := 0 to High(cells.Texts) do
          cells.Texts[j] := TipValueFormatted(vf, p, cells.Raws[j], False);
      end
      else if vf <> '' then
        valueText := TipValueFormatted(vf, p);
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
    if IsTreeSeries(FRoamSeries) then TreeRoam(FRoamSeries, dx, dy)
    else GraphRoam(FRoamSeries, dx, dy);
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
  if (IsGraphDatum(d) or IsGraphDatum(FTipDatum) or IsTreeDatum(d)
    or IsTreeDatum(FTipDatum))
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
  { the pointer slides where upstream's does [Batch 92] }
  PtrAnimSync;
  { the chart's own mouse events [Batch 84] }
  EventMove(X, Y);
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
  if not (csDesigning in ComponentState) then EventLeave(FEvLastX, FEvLastY);
  wasOn := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0);
  wasGraph := IsGraphDatum(FTipDatum) or IsTreeDatum(FTipDatum);
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

{ ==================== the enter animation [Batch 89] ==================== }

function TTyAdvanceChart.AnimClock: Double;
begin
  if IsNan(FAnimNow) then Result := TyAnimClockMs else Result := FAnimNow;
end;

function TTyAdvanceChart.AnimAllowed: Boolean;
begin
  { the designer streams and repaints at will and runs no timer: never }
  if csDesigning in ComponentState then Exit(False);
  case FAnimMode of
    camAlways: Result := True;
    camOff: Result := False;
  else
    Result := FAnimWindow;
  end;
end;

procedure TTyAdvanceChart.SetAnimMode(AValue: TTyChartAnimationMode);
begin
  if FAnimMode = AValue then Exit;
  FAnimMode := AValue;
  { switched off mid-flight: the picture finishes at once }
  if AValue = camOff then
  begin
    AnimDropAll;
    FAnimPending := False;
    DropStatic;
    inherited Invalidate;
  end;
end;

procedure TTyAdvanceChart.AnimDropAll;
begin
  if FAnimSet <> nil then FAnimSet.Clear;
  FAnimBind := nil;
  FAnimStBind := nil;
  FAnimFlush := False;
  FAnimLive := False;
  FAnimContinuous := False;
  AnimDropPrev;
  AnimArmTimer;
end;

procedure TTyAdvanceChart.AnimDropPrev;
begin
  FAnimPrev := Default(TTyChartAnimPrev);
  FreeAndNil(FAnimOldBuild);
  FAnimOldBindings := nil;
end;

function TTyAdvanceChart.AnimViewKeys: TTyStringArray;
var
  i, n: Integer;
  id: string;
begin
  { the view id is '_ec_' + model.id + '_' + type, the type compared apart:
    makeIdAndName's id -- the written one, else from the name, else the
    dummy name -- which a merge never changes [Batch 95] }
  Result := nil;
  n := FOption.ComponentCount('series');
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    id := FOption.ComponentId('series', i);
    if id <> '' then Result[i] := 'i:' + id
    else Result[i] := 'x:' + IntToStr(i);
  end;
end;

procedure TTyAdvanceChart.AnimRowKeys(AStore: TTyDataStore; out AKeys: TTyStringArray;
  out ARaws: TTyIntegerArray);
var
  rawKeys: TTyStringArray;
  counts: TStringList;
  d, ord_, raw, k, c: Integer;
  id, nm: string;
  v: Double;
begin
  AKeys := nil;
  ARaws := nil;
  if AStore = nil then Exit;
  { the first category dimension names a row that has no name of its own
    (createSeriesData gives it the item-name role) }
  ord_ := -1;
  for d := 0 to AStore.DimCount - 1 do
    if AStore.DimType(d) = ddtOrdinal then
    begin
      ord_ := d;
      Break;
    end;
  { getId over the raw rows, in order: an id; else the name, '__ec__' and
    its count from the second time on; else 'e\0\0' + the raw index }
  SetLength(rawKeys, AStore.RawCount);
  counts := TStringList.Create;
  try
    counts.CaseSensitive := True;
    for raw := 0 to AStore.RawCount - 1 do
    begin
      id := AStore.GetIdByRaw(raw);
      if id <> '' then
      begin
        rawKeys[raw] := id;
        Continue;
      end;
      nm := AStore.GetNameByRaw(raw);
      if (nm = '') and (ord_ >= 0) then
      begin
        v := AStore.GetByRaw(ord_, raw);
        if (not IsNan(v)) and (Frac(v) = 0) and (v >= 0)
          and (v < AStore.CategoryCount(ord_)) then
          nm := AStore.CategoryAt(ord_, Trunc(v));
      end;
      if nm = '' then
      begin
        rawKeys[raw] := 'e'#0#0 + IntToStr(raw);
        Continue;
      end;
      k := counts.IndexOf(nm);
      if k < 0 then
      begin
        counts.AddObject(nm, TObject(PtrInt(1)));
        c := 1;
      end
      else
      begin
        c := PtrInt(counts.Objects[k]) + 1;
        counts.Objects[k] := TObject(PtrInt(c));
      end;
      if c > 1 then rawKeys[raw] := nm + '__ec__' + IntToStr(c)
      else rawKeys[raw] := nm;
    end;
  finally
    counts.Free;
  end;
  SetLength(AKeys, AStore.Count);
  SetLength(ARaws, AStore.Count);
  for k := 0 to AStore.Count - 1 do
  begin
    raw := AStore.GetRawIndex(k);
    ARaws[k] := raw;
    if (raw >= 0) and (raw <= High(rawKeys)) then AKeys[k] := rawKeys[raw]
    else AKeys[k] := 'e'#0#0 + IntToStr(raw);
  end;
end;

procedure TTyAdvanceChart.AnimSnapshot;
var
  slot, si, i, n: Integer;
  r: TTyChartAnimSeries;
  el: TTyChartElement;
begin
  AnimDropPrev;
  { NOTHING DRAWN BEFORE: the option enters }
  if FPaintList = nil then Exit;
  FAnimPrev.Valid := True;
  for slot := 0 to High(FBindings) do
  begin
    si := FBindings[slot].SeriesIndex;
    if si < 0 then Continue;
    if si > High(FAnimPrev.Series) then SetLength(FAnimPrev.Series, si + 1);
    r := Default(TTyChartAnimSeries);
    r.Present := True;
    r.SeriesType := FBindings[slot].SeriesType;
    if si <= High(FAnimOldViewKeys) then r.ViewKey := FAnimOldViewKeys[si]
    else r.ViewKey := 'x:' + IntToStr(si);
    if (slot <= High(FStores)) and (FStores[slot] <> nil) then
      AnimRowKeys(FStores[slot], r.Keys, r.Raws);
    FAnimPrev.Series[si] := r;
  end;
  n := 0;
  SetLength(FAnimPrev.Elements, FPaintList.Count);
  for i := 0 to FPaintList.Count - 1 do
  begin
    el := FPaintList.Element(i);
    if el.Anim.Role = carNone then Continue;
    FAnimPrev.Elements[n] := el;
    Inc(n);
  end;
  SetLength(FAnimPrev.Elements, n);
  FAnimPrev.ToOldPoint := @AnimToOldPoint;
  { THE OLD BUILD STAYS ALIVE for its coordinate systems; Rebuild's
    DropBuild finds nothing to free }
  FAnimOldBuild := FBuild;
  FBuild := nil;
  FAnimOldBindings := Copy(FBindings, 0, Length(FBindings));
end;

function TTyAdvanceChart.AnimToOldPoint(AOldSeries: Integer; AX, AY: Double): TTyPointF;
var i: Integer;
begin
  Result := TyPointF(NaN, NaN);
  for i := 0 to High(FAnimOldBindings) do
    if (FAnimOldBindings[i].SeriesIndex = AOldSeries)
      and (FAnimOldBindings[i].Cart <> nil) then
      Exit(FAnimOldBindings[i].Cart.DataToPoint([AX, AY]));
end;

function TTyAdvanceChart.AnimSeriesInfo: TTyChartAnimSeriesArray;
var
  slot, si, n, k: Integer;
  r: TTyChartAnimSeries;
  t: string;
  ser, lbl, va, mk: TJSONData;
  v: TTyAnimOptValue;
  viewKeys: TTyStringArray;
begin
  Result := nil;
  viewKeys := AnimViewKeys;
  for slot := 0 to High(FBindings) do
  begin
    si := FBindings[slot].SeriesIndex;
    if si < 0 then Continue;
    if si > High(Result) then SetLength(Result, si + 1);
    r := Default(TTyChartAnimSeries);
    r.Present := True;
    n := 0;
    if (slot <= High(FStores)) and (FStores[slot] <> nil) then
      n := FStores[slot].Count;
    r.Model := TyAnimSeriesModel(FOption.Root, si, n);
    r.Enabled := TyAnimIsEnabled(r.Model);
    r.On_ := TyAnimOptTruthy(TyAnimGetShallow(r.Model, 'animation'));
    t := FBindings[slot].SeriesType;
    { THE TYPES WHOSE LABELS FADE IN HERE: the ones this batch animates,
      and the heatmap, whose cells never move but whose labels upstream's
      LabelManager fades all the same }
    r.LabelFade := (t = 'bar') or (t = 'scatter') or (t = 'heatmap')
      or (t = TyPieSeriesTypeName) or (t = TyFunnelSeriesTypeName)
      or (t = 'effectScatter');
    ser := r.Model.Own;
    if ser is TJSONObject then
    begin
      lbl := TJSONObject(ser).Find('label');
      if lbl is TJSONObject then
      begin
        va := TJSONObject(lbl).Find('valueAnimation');
        { only a bar counts (BarView's setLabelValueAnimation): every other
          series' labels fade whatever the key says [Batch 92] }
        r.LabelValueAnim := (t = 'bar') and (va <> nil)
          and (va.JSONType = jtBoolean) and va.AsBoolean;
      end;
      { THE MARKERS' MODELS: MarkerModel.isAnimationEnabled is the marker's
        `animation` and the host's isAnimationEnabled [Batch 92] }
      r.MarkLine := TyAnimNoModel;
      r.MarkPoint := TyAnimNoModel;
      if r.Enabled then
      begin
        mk := TJSONObject(ser).Find('markLine');
        if mk is TJSONObject then
          r.MarkLine := TyAnimComponentModel(mk, FOption.Root, 'markLine');
        mk := TJSONObject(ser).Find('markPoint');
        if mk is TJSONObject then
          r.MarkPoint := TyAnimComponentModel(mk, FOption.Root, 'markPoint');
      end;
    end;
    r.BaseHoriz := (FBindings[slot].BaseAxis = nil)
      or FBindings[slot].BaseAxis.Horizontal;
    { AN UPDATE'S VIEW [Batch 90] }
    r.SeriesType := t;
    if si <= High(viewKeys) then r.ViewKey := viewKeys[si]
    else r.ViewKey := 'x:' + IntToStr(si);
    { brand new: a key no old view has [Batch 97] }
    if (si <= High(FAnimFresh)) and FAnimFresh[si] then r.ViewKey := 'n:' + r.ViewKey;
    if (slot <= High(FStores)) and (FStores[slot] <> nil) then
      AnimRowKeys(FStores[slot], r.Keys, r.Raws);
    if t = TyPieSeriesTypeName then
    begin
      v := TyAnimGetShallow(r.Model, 'animationTypeUpdate');
      r.PieExpandAlways := (v.Kind = aokString) and (v.Str = 'expansion');
      v := TyAnimGetShallow(r.Model, 'animationType');
      r.PieScale := (v.Kind = aokString) and (v.Str = 'scale');
      { A FIRST RENDER'S SHARED START: the first slice's whose start is a
        number (PieView.ts:248-256) }
      if (slot <= High(FPies)) and FPies[slot].Valid then
        for k := 0 to High(FPies[slot].Sectors) do
          if not IsNan(FPies[slot].Sectors[k].StartRad) then
          begin
            r.HasPieStart := True;
            r.PieStart := FPies[slot].Sectors[k].StartRad;
            Break;
          end;
    end;
    Result[si] := r;
  end;
end;

procedure TTyAdvanceChart.AnimAfterBuild;
begin
  if FAnimPending then
  begin
    if AnimAllowed then
    begin
      FAnimPending := False;
      if FAnim = nil then FAnim := TTyAnimation.Create;
      if FAnimSet = nil then FAnimSet := TTyChartAnimSet.Create(FAnim);
      { AN UPDATE when there was a render before, an entry otherwise
        [Batch 90] }
      if FAnimPrev.Valid then
        FAnimSet.ArmUpdate(FPaintList, AnimSeriesInfo, FAnimPrev)
      else
      begin
        FAnimSet.Clear;
        FAnimSet.Arm(FPaintList, AnimSeriesInfo);
      end;
      AnimDropPrev;
      { the views are paired: __requireNewView works once }
      FAnimFresh := nil;
      { THE FLUSH: upstream's setOption ends with a synchronous update, so
        every clip it made starts NOW and this same paint shows the from
        values. A step on the next tick would shift every timeline by up
        to 16 ms. It waits for the states (AnimFlushArmed). }
      FAnimFlush := True;
    end
    else if FAnimMode = camOff then
    begin
      FAnimPending := False;
      AnimDropPrev;
      FAnimFresh := nil;
    end;
  end;
  FAnimStBind := nil;
  { A LIST WAITING FOR ITS ARMING is drawn as laid out: the proxies are the
    old render's, keyed by the old rows [Batch 90] }
  if FAnimPending then
    FAnimBind := nil
  else if (FAnimSet <> nil) and (FAnimSet.Count > 0) then
    FAnimBind := FAnimSet.Bind(FPaintList)
  else
    FAnimBind := nil;
end;

procedure TTyAdvanceChart.AnimFlushArmed;
begin
  if not FAnimFlush then Exit;
  FAnimFlush := False;
  if FAnim = nil then Exit;
  FAnim.Update(AnimClock, True);
  FAnimLive := FAnim.ClipCount > 0;
  FAnimContinuous := FAnimLive and AnimLoopOnly;
  AnimArmTimer;
end;

procedure TTyAdvanceChart.AnimArmTimer;
begin
  if (FAnimLive or PtrLive or LegLive) and IsNan(FAnimNow)
    and not (csDesigning in ComponentState) then
  begin
    if FAnimTimer = nil then
    begin
      FAnimTimer := TTimer.Create(nil);
      FAnimTimer.Enabled := False;
      FAnimTimer.Interval := 16;
      FAnimTimer.OnTimer := @AnimTimerFired;
    end;
    FAnimTimer.Enabled := True;
  end
  else if FAnimTimer <> nil then
    FAnimTimer.Enabled := False;
end;

procedure TTyAdvanceChart.AnimTimerFired(Sender: TObject);
begin
  AnimTick(AnimClock);
end;

procedure TTyAdvanceChart.AnimTick(ANowMs: Double);
var ptrWas: Boolean;
begin
  { the pointer's own driver first [Batch 92] }
  if FPtrAnim <> nil then
  begin
    ptrWas := FPtrAnim.ClipCount > 0;
    FPtrAnim.Update(ANowMs);
    if ptrWas then
    begin
      InvalidateFrame;
      if (FPtrAnim.ClipCount = 0) and not FAnimLive then AnimArmTimer;
    end;
  end;
  { the legend's scroll [Batch 98]: a frame of the static layer }
  if LegLive then
  begin
    FLegAnim.Update(ANowMs);
    DropStatic;
    InvalidateFrame;
    if not LegLive and not FAnimLive then AnimArmTimer;
  end;
  if FAnim = nil then Exit;
  FAnim.Update(ANowMs);
  { a fade that ended removed its element [Batch 90] }
  if FAnimSet <> nil then FAnimSet.Purge;
  if FAnimLive and (FAnim.ClipCount = 0) then
  begin
    { AT REST: the series go back into the static layer, drawn once more
      at the values they rest at }
    FAnimLive := False;
    FAnimContinuous := False;
    AnimArmTimer;
    DropStatic;
  end
  else if FAnimLive and not FAnimContinuous and AnimLoopOnly then
  begin
    { ONLY LOOPS LEFT: the rest settles into the static layer [Batch 92] }
    FAnimContinuous := True;
    DropStatic;
  end;
  InvalidateFrame;
end;

{ ==================== the axis pointer's slide [Batch 92] ====================

  BaseAxisPointer.render: the first show is direct; a move -- the pointer's
  props differing from the last ones (propsEqual) -- is updateProps on the
  pointer's model when determineAnimation says so, else a stop and attr.
  The model is the axis' axisPointer over the tooltip's (makeAxisPointerModel:
  animation 'auto', 200 ms, exponentialOut), the root below. A hidden pointer
  keeps its place: the next show slides from it. The label goes with the
  pointer (upstream tweens its x / y with the same timing). }

function TTyAdvanceChart.PtrLive: Boolean;
begin
  Result := (FPtrAnim <> nil) and (FPtrAnim.ClipCount > 0);
end;

function TTyAdvanceChart.PtrKeyOf(AAxis: TTyAxis): string;
begin
  Result := AAxis.MainType + IntToStr(AAxis.ComponentIndex);
end;

procedure TTyAdvanceChart.PtrAnimDrop;
var i: Integer;
begin
  if FPtrProxies <> nil then
  begin
    for i := 0 to FPtrProxies.Count - 1 do TObject(FPtrProxies[i]).Free;
    FPtrProxies.Clear;
  end;
end;

{ propsEqual: every key of AProps at the value AFinal holds }
function PtrPropsSame(const AFinal, AProps: TTyAnimProps): Boolean;
var i, k: Integer; hit: Boolean;
begin
  Result := False;
  for i := 0 to High(AProps) do
  begin
    hit := False;
    for k := 0 to High(AFinal) do
      if AFinal[k].Key = AProps[i].Key then
      begin
        if not TyAnimValueSame(AFinal[k].Value, AProps[i].Value) then Exit;
        hit := True;
        Break;
      end;
    if not hit then Exit;
  end;
  Result := True;
end;

function TTyAdvanceChart.PtrModelOf(const AHit: TTyAxisHit; out AOwn: TJSONObject): TTyAnimModel;
const
  cKeys: array[0..3] of string = ('animation', 'animationDurationUpdate',
    'animationEasingUpdate', 'animationDelayUpdate');
var
  axisNode, tip, ap, tap, d: TJSONData;
  k: Integer;
begin
  { the axis' own axisPointer over the tooltip's, key by key }
  AOwn := TJSONObject.Create;
  ap := nil;
  tap := nil;
  axisNode := FOption.ComponentAt(AHit.Axis.MainType, AHit.Axis.ComponentIndex);
  if axisNode is TJSONObject then ap := TJSONObject(axisNode).Find('axisPointer');
  if FOption.Root is TJSONObject then
  begin
    tip := TJSONObject(FOption.Root).Find('tooltip');
    if (tip is TJSONArray) and (tip.Count > 0) then tip := tip.Items[0];
    if tip is TJSONObject then tap := TJSONObject(tip).Find('axisPointer');
  end;
  for k := 0 to High(cKeys) do
  begin
    d := nil;
    if ap is TJSONObject then d := TJSONObject(ap).Find(cKeys[k]);
    if ((d = nil) or (d.JSONType = jtNull)) and (tap is TJSONObject) then
      d := TJSONObject(tap).Find(cKeys[k]);
    if (d <> nil) and (d.JSONType <> jtNull) then AOwn.Add(cKeys[k], d.Clone);
  end;
  Result := TyAnimComponentModel(AOwn, FOption.Root, 'tooltip.axisPointer');
end;

function TTyAdvanceChart.PtrMoves(const AHit: TTyAxisHit; const AModel: TTyAnimModel): Boolean;
var
  v: TTyAnimOptValue;
  isCat: Boolean;
  s, cnt: Integer;
begin
  { determineAnimation (BaseAxisPointer.ts:211-242) }
  isCat := AHit.Axis.Scale is TTyOrdinalScale;
  if (not AHit.Spec.Snap) and not isCat then Exit(False);
  v := TyAnimGetShallow(AModel, 'animation');
  if (v.Kind in [aokUndefined, aokNull]) or ((v.Kind = aokString) and (v.Str = 'auto')) then
  begin
    if isCat and (AHit.Axis.BandWidth > 15) then Exit(True);
    if AHit.Spec.Snap then
    begin
      { the series on the axis' coordinate system, all their data }
      cnt := 0;
      for s := 0 to High(FBindings) do
        if (s <= High(FStores)) and (FStores[s] <> nil)
          and ((FBindings[s].XAxis = AHit.Axis) or (FBindings[s].YAxis = AHit.Axis)) then
          Inc(cnt, FStores[s].Count);
      Exit(Abs(AHit.Axis.PxStart - AHit.Axis.PxStop) / cnt > 15);
    end;
    Exit(False);
  end;
  Result := (v.Kind = aokBool) and (v.Num <> 0);
end;

function TTyAdvanceChart.PtrProps(const AHit: TTyAxisHit; AAt: Double): TTyAnimProps;
var w: Double;
begin
  { CartesianAxisPointer's shapes: a line across the other axis' extent, or
    the category's band }
  if AHit.Spec.PointerType = aptShadow then
  begin
    w := Max(Double(1), AHit.Axis.BandWidth);
    if AHit.Axis.Horizontal then
      Result := TyAnimProps([TyAnimProp('shape.x', TyAnimNum(AAt - w / 2)),
        TyAnimProp('shape.y', TyAnimNum(AHit.Plot.Bottom)),
        TyAnimProp('shape.width', TyAnimNum(w)),
        TyAnimProp('shape.height', TyAnimNum(AHit.Plot.Top - AHit.Plot.Bottom))])
    else
      Result := TyAnimProps([TyAnimProp('shape.x', TyAnimNum(AHit.Plot.Left)),
        TyAnimProp('shape.y', TyAnimNum(AAt - w / 2)),
        TyAnimProp('shape.width', TyAnimNum(AHit.Plot.Right - AHit.Plot.Left)),
        TyAnimProp('shape.height', TyAnimNum(w))]);
  end
  else if AHit.Axis.Horizontal then
    Result := TyAnimProps([TyAnimProp('shape.x1', TyAnimNum(AAt)),
      TyAnimProp('shape.y1', TyAnimNum(AHit.Plot.Bottom)),
      TyAnimProp('shape.x2', TyAnimNum(AAt)),
      TyAnimProp('shape.y2', TyAnimNum(AHit.Plot.Top))])
  else
    Result := TyAnimProps([TyAnimProp('shape.x1', TyAnimNum(AHit.Plot.Left)),
      TyAnimProp('shape.y1', TyAnimNum(AAt)),
      TyAnimProp('shape.x2', TyAnimNum(AHit.Plot.Right)),
      TyAnimProp('shape.y2', TyAnimNum(AAt))]);
end;

procedure TTyAdvanceChart.PtrAnimSync;
var
  i, k: Integer;
  hit: TTyAxisHit;
  at: Double;
  key: string;
  p: TTyChartAnimProxy;
  props: TTyAnimProps;
  model: TTyAnimModel;
  own: TJSONObject;
begin
  { a mouse moves only over a live window: every mode but camOff }
  if (FAnimMode = camOff) or (csDesigning in ComponentState) then Exit;
  for i := 0 to High(FTipHits) do
  begin
    hit := FTipHits[i];
    if (hit.Axis = nil) or (hit.Spec.PointerType = aptNone) then Continue;
    at := hit.Axis.DataToCoord(PointerValue(hit), True);
    if IsNan(at) then Continue;
    key := PtrKeyOf(hit.Axis);
    props := PtrProps(hit, at);
    if FPtrProxies = nil then FPtrProxies := TFPList.Create;
    if FPtrAnim = nil then FPtrAnim := TTyAnimation.Create;
    p := nil;
    for k := 0 to FPtrProxies.Count - 1 do
      if TTyChartAnimProxy(FPtrProxies[k]).Role = key then
      begin
        p := TTyChartAnimProxy(FPtrProxies[k]);
        Break;
      end;
    if p = nil then
    begin
      { THE FIRST SHOW IS DIRECT }
      p := TTyChartAnimProxy.Create(-1, -1, key);
      p.Animation := FPtrAnim;
      p.Attr(props);
      p.SetFinal(props);
      FPtrProxies.Add(p);
      Continue;
    end;
    { propsEqual: nothing new, nothing done }
    if PtrPropsSame(p.Final, props) then Continue;
    model := PtrModelOf(hit, own);
    try
      p.SetFinal(props);
      if PtrMoves(hit, model) then
        TyUpdateProps(p, props, model, TyAnimCallNoIndex)
      else
      begin
        p.StopAnimation;
        p.Attr(props);
      end;
    finally
      own.Free;
    end;
  end;
  AnimArmTimer;
end;

function TTyAdvanceChart.PtrAt(const AHit: TTyAxisHit; AAt: Double): Double;
var
  k: Integer;
  p: TTyChartAnimProxy;
  key: string;
begin
  Result := AAt;
  if (FPtrProxies = nil) or (AHit.Axis = nil) then Exit;
  key := PtrKeyOf(AHit.Axis);
  for k := 0 to FPtrProxies.Count - 1 do
  begin
    p := TTyChartAnimProxy(FPtrProxies[k]);
    if p.Role <> key then Continue;
    if p.AtFinal then Exit;
    if AHit.Spec.PointerType = aptShadow then
    begin
      if AHit.Axis.Horizontal then Result := p.Num('shape.x') + p.Num('shape.width') / 2
      else Result := p.Num('shape.y') + p.Num('shape.height') / 2;
    end
    else if AHit.Axis.Horizontal then Result := p.Num('shape.x1')
    else Result := p.Num('shape.y1');
    if IsNan(Result) then Result := AAt;
    Exit;
  end;
end;

function TTyAdvanceChart.AnimPointerClipCount: Integer;
begin
  if FPtrAnim = nil then Result := 0 else Result := FPtrAnim.ClipCount;
end;

function TTyAdvanceChart.AnimPointerProxy(const AKey: string): TTyChartAnimProxy;
var k: Integer;
begin
  Result := nil;
  if FPtrProxies = nil then Exit;
  for k := 0 to FPtrProxies.Count - 1 do
    if TTyChartAnimProxy(FPtrProxies[k]).Role = AKey then
      Exit(TTyChartAnimProxy(FPtrProxies[k]));
end;

function TTyAdvanceChart.AnimLoopOnly: Boolean;
var i: Integer;
begin
  Result := (FAnim <> nil) and (FAnim.ClipCount > 0);
  if not Result then Exit;
  for i := 0 to FAnim.ClipCount - 1 do
    if not FAnim.ClipAt(i).Loop then Exit(False);
end;

function TTyAdvanceChart.AnimPart(AContinuous: Boolean): TTyPaintList;
var
  frame: TTyPaintList;
  i, h: Integer;
  el: TTyChartElement;
  cont: Boolean;
begin
  frame := AnimFrame;
  if FAnimSplit = nil then FAnimSplit := TTyPaintList.Create;
  FAnimSplit.Clear;
  Result := FAnimSplit;
  if frame = nil then Exit;
  for i := 0 to frame.Count - 1 do
  begin
    el := frame.Element(i);
    { a ripple, an effect symbol, and a label hanging off one }
    cont := el.Anim.Role in [carRipple, carEffectSymbol];
    if (not cont) and (el.Anim.Role = carLabel) then
    begin
      h := el.Anim.HostPlus1 - 1;
      cont := (h >= 0) and (h < frame.Count)
        and (frame.Element(h).Anim.Role = carEffectSymbol);
    end;
    if cont = AContinuous then FAnimSplit.Add(el);
  end;
end;

function TTyAdvanceChart.AnimClipCount: Integer;
begin
  if FAnim = nil then Result := 0 else Result := FAnim.ClipCount;
end;

function TTyAdvanceChart.AnimLoopClipCount: Integer;
var i: Integer;
begin
  Result := 0;
  if FAnim = nil then Exit;
  for i := 0 to FAnim.ClipCount - 1 do
    if FAnim.ClipAt(i).Loop then Inc(Result);
end;

{ the states' own proxies ('st:' roles) are not the animations' [Batch 94] }
function IsStateOnlyProxy(P: TTyChartAnimProxy): Boolean;
begin
  Result := Copy(P.Role, 1, 3) = 'st:';
end;

function TTyAdvanceChart.AnimProxyCount: Integer;
var i: Integer;
begin
  Result := 0;
  if FAnimSet = nil then Exit;
  for i := 0 to FAnimSet.Count - 1 do
    if not IsStateOnlyProxy(FAnimSet.Item(i)) then Inc(Result);
end;

function TTyAdvanceChart.AnimProxy(AIndex: Integer): TTyChartAnimProxy;
var i, n: Integer;
begin
  Result := nil;
  if (FAnimSet = nil) or (AIndex < 0) then Exit;
  n := 0;
  for i := 0 to FAnimSet.Count - 1 do
  begin
    if IsStateOnlyProxy(FAnimSet.Item(i)) then Continue;
    if n = AIndex then Exit(FAnimSet.Item(i));
    Inc(n);
  end;
end;

function TTyAdvanceChart.AnimFindProxy(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  if FAnimSet = nil then Exit(nil);
  Result := FAnimSet.Find(ASeries, AIndex, ARole);
end;

function TTyAdvanceChart.AnimFindGhost(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  if FAnimSet = nil then Exit(nil);
  Result := FAnimSet.FindGhost(ASeries, AIndex, ARole);
end;

function TTyAdvanceChart.AnimStateProxy(ASeries, ARow: Integer;
  const APart: string): TTyChartAnimProxy;
var slot, raw, idx: Integer;
begin
  Result := nil;
  if (ASeries < 0) or (ASeries > High(FSt)) or (FSt[ASeries].Kind = sskNone) then Exit;
  idx := -1;
  if APart = 'poly' then
  begin
    if Length(FSt[ASeries].RunIdx) > 0 then idx := FSt[ASeries].RunIdx[0];
  end
  else if APart = 'area' then
  begin
    if Length(FSt[ASeries].AreaIdx) > 0 then idx := FSt[ASeries].AreaIdx[0];
  end
  else
  begin
    slot := SlotOfSeries(ASeries);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
    if (ARow < 0) or (ARow >= FStores[slot].Count) then Exit;
    raw := FStores[slot].GetRawIndex(ARow);
    if (raw < 0) or (raw > High(FSt[ASeries].HostIdx)) then Exit;
    if APart = 'host' then idx := FSt[ASeries].HostIdx[raw]
    else if APart = 'label' then idx := FSt[ASeries].LabelIdx[raw]
    else if APart = 'guide' then idx := FSt[ASeries].GuideIdx[raw];
  end;
  if (idx >= 0) and (idx <= High(FAnimStBind)) then Result := FAnimStBind[idx];
end;

function TTyAdvanceChart.AnimGhostCount: Integer;
begin
  if FAnimSet = nil then Result := 0 else Result := FAnimSet.LiveGhostCount;
end;

function TTyAdvanceChart.AnimFrame: TTyPaintList;
begin
  if (FPaintList = nil) or ((Length(FAnimBind) = 0) and (Length(FAnimStBind) = 0)
    and ((FAnimSet = nil) or (FAnimSet.GhostCount = 0))) then Exit(FPaintList);
  if FAnimFrame = nil then FAnimFrame := TTyPaintList.Create;
  TyAnimBuildFrame(FPaintList, FAnimFrame, FAnimBind, FAnimSet, FAnimStBind);
  Result := FAnimFrame;
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
  { THE SERIES IN MOTION, and the title over them: this frame's values,
    read from the proxies [Batch 89] }
  if FAnimContinuous then
    TyRenderPaintList(APainter, AnimPart(True))
  else if FAnimLive then
  begin
    TyRenderPaintList(APainter, AnimFrame);
    PaintTitles(APainter);
  end;
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
  Result := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0)
    or FAnimLive;
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
  { upstream's frame: the flags become state lists, and a changed element
    is a changed static layer [Batch 88] }
  if StApplyChanged then FStatic.Drop;

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
  { A WINDOW'S PAINT: the one render camAuto animates [Batch 89] }
  FAnimWindow := True;
  try
    RenderCached(Canvas, ClientRect, Font.PixelsPerInch);
  finally
    FAnimWindow := False;
  end;
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
