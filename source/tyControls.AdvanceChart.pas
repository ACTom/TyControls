unit tyControls.AdvanceChart;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the control the whole AdvanceChart layer exists under.

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
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option, tyControls.AdvanceChart.OptionMerge,
  tyControls.AdvanceChart.Media,
  tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Scale,
  tyControls.AdvanceChart.Time,
  tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.Layout,
  tyControls.AdvanceChart.Builder, tyControls.AdvanceChart.Series,
  tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Handlers, tyControls.FontUnits,
  tyControls.AdvanceChart.Events, tyControls.AdvanceChart.States,
  tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Render,
  tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Style,
  tyControls.AdvanceChart.Marks, tyControls.AdvanceChart.BarLayout,
  tyControls.AdvanceChart.Stack, tyControls.AdvanceChart.Sampling, tyControls.AdvanceChart.Symbol,
  tyControls.AdvanceChart.Pictorial,
  tyControls.AdvanceChart.Color, tyControls.AdvanceChart.VisualMap,
  tyControls.AdvanceChart.VisualMapView, tyControls.AdvanceChart.Decal,
  tyControls.AdvanceChart.DataZoom, tyControls.AdvanceChart.DataZoomView,
  tyControls.AdvanceChart.DataZoomAct, tyControls.AdvanceChart.ZrPath,
  tyControls.AdvanceChart.Marker, tyControls.AdvanceChart.MarkerView,
  tyControls.AdvanceChart.Pie, tyControls.AdvanceChart.Funnel,
  tyControls.AdvanceChart.Gauge, tyControls.AdvanceChart.Radar,
  tyControls.AdvanceChart.Calendar, tyControls.AdvanceChart.Matrix, tyControls.AdvanceChart.Tree,
  tyControls.AdvanceChart.Geo, tyControls.AdvanceChart.GeoSvg, tyControls.AdvanceChart.HeatLayer,
  tyControls.AdvanceChart.Sunburst, tyControls.AdvanceChart.Treemap,
  tyControls.AdvanceChart.Sankey,
  tyControls.AdvanceChart.Graph,
  tyControls.AdvanceChart.Title,
  tyControls.AdvanceChart.Labels, tyControls.AdvanceChart.LabelOpt,
  tyControls.AdvanceChart.PieLabel, tyControls.AdvanceChart.Legend,
  tyControls.AdvanceChart.Tooltip, tyControls.AdvanceChart.TipHtml,
  tyControls.AdvanceChart.AxisPointer,
  tyControls.AdvanceChart.Dataset, tyControls.AdvanceChart.WhiskerBox,
  tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.AnimOpt,
  tyControls.AdvanceChart.AnimView, tyControls.AdvanceChart.AnimAxis,
  tyControls.AdvanceChart.AxisLabels, tyControls.AdvanceChart.LabelLayout,
  tyControls.AdvanceChart.Export, tyControls.AdvanceChart.Loading,
  tyControls.AdvanceChart.Convert, tyControls.AdvanceChart.Jitter,
  tyControls.AdvanceChart.Large, tyControls.AdvanceChart.Progressive,
  tyControls.AdvanceChart.Polar, tyControls.AdvanceChart.PolarBar,
  tyControls.AdvanceChart.Single, tyControls.AdvanceChart.ThemeRiver,
  tyControls.AdvanceChart.Chord,
  tyControls.AdvanceChart.GfxEl, tyControls.AdvanceChart.Graphic,
  tyControls.AdvanceChart.Lines, tyControls.AdvanceChart.Custom,
  tyControls.AdvanceChart.Toolbox, tyControls.AdvanceChart.Brush,
  tyControls.AdvanceChart.Timeline,
  tyControls.AdvanceChart.Parallel, tyControls.AdvanceChart.Thumbnail,
  { echarts.connect's revert map and the combined export [Batch 141] }
  tyControls.AdvanceChart.Connect,
  { the coarse pointer and the dirty rectangles [Batch 142] }
  tyControls.AdvanceChart.DirtyRect,
  { the keyboard and the accessible tree [Batch 144] }
  tyControls.AdvanceChart.Aria, tyControls.AdvanceChart.KeyNav, tyControls.Accessible,
  fpjson, contnrs, tyControls.SubPixel;

const
  { The four axis metrics, and the defaults to fall back on when a theme has not
    been loaded at all. The names are the theme's; the numbers match what the
    option model documents so a chart looks the same before and after a skin. }
  TyAdvChartTickLenVar = '--advchart-tick-length';
  TyAdvChartTickLen = 5;
  { A SINGLE AXIS' TICK: its model's own 6 over axisDefault's 5
    (SingleAxisModel's axisTick.length) -- a metric of its own so a skin can
    move it [Batch 118] }
  TyAdvChartSingleTickLenVar = '--advchart-single-tick-length';
  TyAdvChartSingleTickLen = 6;
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
    { THE POLAR the axis belongs to; nil on a grid [Batch 111] }
    Polar: TTyPolar;
    { THE SINGLE AXIS the axis is; nil elsewhere [Batch 118] }
    Single: TTySingle;
    { PUT THERE BY axisPointer.link [Batch 141]: Value is the source axis'
      value (through the group's mapper), and the pointer stands on it --
      processOnAxis' noSnap -- while the tooltip still describes SnapValue }
    Linked: Boolean;
    { [R2-I7] THE AXIS DOES NOT TRIGGER THE TOOLTIP (axisInfo.triggerTooltip
      false): a cross' other arm, the base axis of a cross under a trigger
      that is not 'axis', an axis collected for its own `show` whose
      `triggerTooltip` says false. Its rows (when it has any) are no part of
      dataByCoordSys. False -- the zero value -- triggers. }
    NoTip: Boolean;
  end;
  TTyAxisHitArray = array of TTyAxisHit;

  { [R2-I7] ONE axisInfo OF THE axisPointer MODEL, as
    modelHelper.collectAxesInfo builds it: per coordinate system (the grids,
    the polars, the single axes, in that order) first every axis whose own
    pointer model -- its block over the root component -- says `show`
    (saveTooltipAxisInfo(false, null)), then the tooltip's axes (its base
    axes, and under a cross the other ones), which take the place of an axis
    already there. }
  TTyPtrAxisInfo = record
    Axis: TTyAxis;
    Plot: TTyRectF;
    Polar: TTyPolar;
    Single: TTySingle;
    { the coordinate system: 'g<n>', 'p<n>', 's<n>' }
    CsKey: string;
    { fromTooltip true or 'cross' }
    FromTooltip: Boolean;
    { fromTooltip 'cross' and not triggering: the cross' other arm }
    CrossArm: Boolean;
    TriggerTooltip: Boolean;
    { triggerTooltip || snap || a category axis: the series are searched }
    InvolveSeries: Boolean;
    Spec: TTyAxisPointerSpec;
  end;
  TTyPtrAxisInfoArray = array of TTyPtrAxisInfo;

  { WHAT A SINGLE AXIS' POINTER DRAWS [Batch 118]: its line or shadow rect,
    and its label's text and padded box (top-left, after the align and the
    confinement to the control) when the label is shown. }
  TTySinglePointerDraw = record
    Shape: TTySinglePointerShape;
    HasLabel: Boolean;
    Text: string;
    X, Y, W, H: Double;
  end;

  { WHAT A POLAR POINTER DRAWS [Batch 111]: its shape, and its label's text
    and padded box (top-left, after the align and the confinement to the
    control) when the label is shown. }
  TTyPolarPointerDraw = record
    Shape: TTyPolarPointerShape;
    HasLabel: Boolean;
    Text: string;
    X, Y, W, H: Double;
  end;

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
      next). Neither carries data.
      [Batch 116] 7 an element of a visualMap: HdSeries the component,
      HdRow the part (VmPart*), HdGen the build of the view it was found in
      -- a rebuilt view's elements are new ones. No data.
      [Batch 125] 8 a toolbox icon. [Batch 126] 9 a brush cover's piece:
      HdSeries the brush component, HdRow the cover's serial, HdGen the
      piece (TTyBrushPiece). No data. [Batch 129] 10 a timeline element:
      HdRow the element, HdGen the render that made it. [Batch 132] 12 a
      break area (BreakAreaClickAt), 13 a break's axis label
      (BreakExpandClick): HdSeries and HdRow as those read them. }
    HdKind: Integer;
    HdGen: Integer;
    HdSeries, HdRow: Integer;
    HdEdge: Boolean;
    { [F2b] with HdKind 1: the item's second dispatcher (a gauge's progress
      arc), a select dispatcher never flagged selected.
      [F2b] HdKind 16: a row of a large batch -- the row its handler found
      (HdSeries, HdRow inner): a select dispatcher, no highlight one }
    HdPeer: Boolean;
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
    sskCandle, sskPictorial, sskSunburst,
    { [Batch 108] a boxplot's path: one element, the host }
    sskBox,
    { [Batch 114] a sankey: node rects by node index, and its links in a
      second set of rows (EdgeRows) }
    sskSankey,
    { [Batch 118] a themeRiver's layer polygon, under the row its index is }
    sskRiver,
    { [Batch 120] a chord: node sectors by the store's raw rows, and its
      ribbons in the second set of rows (EdgeRows) by raw link index }
    sskChord,
    { [Batch 121] a lines row: its line the host, its end symbols parts
      whose states are the line's stroke and opacity }
    sskLines,
    { [Batch 123] a custom item: its first path the host, every other path
      of its tree a part with states of its own }
    sskCustom,
    { [Batch 128] a parallel row: its polyline, states read lineStyle }
    sskParallel,
    { [Batch 152] a map series' region: the row's flags only -- the paths
      and their states are the geo's (MapDraw), which takes the flags }
    sskMap,
    { [F2a] A GRAPH: its nodes by raw row (a Symbol -- the group dispatches,
      the path draws, the label is the path's), its edges' Line groups in
      EdgeRows by their place in the solved edge list (the line hosts, the
      arrows are parts, the caption the label). A TREE: its nodes as a
      graph's, and in EdgeRows by the node that draws it the edge
      symbolEl.__edge -- flags of its own, set by blurSeries and by its
      node's onHoverStateChange (TreeView.ts:464-477). A TREEMAP: a leaf's
      node group dispatches (its content hosts, its background is a part),
      a parent's background alone. }
    sskGraph, sskTree, sskTreemap,
    { [F2b] a gauge: its pointer the row's host (the item graphic element:
      the actions and the selection reach it), its progress arc a PEER --
      a highDownDispatcher of its own that blurSeries reaches too; both
      with z2EmphasisLift 0 (GaugeView.ts:526-574) }
    sskGauge,
    { [F2b] a radar item: its polyline the host, its polygon and symbols
      parts with states of their own, one dispatcher for the item group
      (RadarView.ts:181-268) }
    sskRadar);
  TTyStNodeArray = array of TJSONObject;

const
  { [Batch 152] a roam host index past this is a map series group's geo }
  cMapRoamBase = 1000000;
  { [F4a] a break area's axis key past this is a singleAxis (the index
    after it); below it a grid's (grid * 1000 + axis) }
  cBreakSingleKey = 900000;

type
  { [Batch 152, D14 GE4] A MAP_SERIES_GROUP: the map series on one geo
    component ('o' and its index) or of one `map` ('i' and the name) --
    every one of them (R, raw order) and the ones the legend left (F); the
    main one (F's first, -1: none) draws the map and holds the statistic }
  TTyMapGroup = record
    Key, MapType: string;
    Own: Boolean;
    HostGeo: Integer;
    R, F: TTyIntegerArray;
    Main: Integer;
    { mapSymbolLayout: per F series, per raw row, the symbol's offset (-1:
      none) }
    SymOff: array of TTyIntegerArray;
  end;
  { the centre and zoom a geoRoam wrote back into a group's series }
  TTyMapRoam = record
    Key: string;
    State: TTyGraphRoamState;
  end;
  { where the last build put a map picture (Geo a TTyGeo) or a series'
    legend symbols (Geo nil) }
  TTyGeoDrawRange = record
    Geo: TObject;
    Series, Start, Count: Integer;
  end;

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
    { THE EDGE DATA'S ITEMS [Batch 114]: a sankey's links, by link index --
      the band and its label -- a second data type with states of its own }
    EdgeRows: array of TTyStItem;
    EdgeHostIdx, EdgeLabelIdx: TTyIntegerArray;
    { a graph edge's arrows, by edge [F2a] }
    EdgePartIdx: array of TTyIntegerArray;
    { getComponentStates(series).isBlured: blurSeries reached it, so the next
      allLeaveBlur walks it [Batch 90] }
    IsBlured: Boolean;
    { A SECOND DISPATCHER OF THE SAME DATA ITEM [F2b]: a gauge's progress
      arc beside its pointer -- its own flags, reached by its own hover and
      by blurSeries, never by the actions or the selection (only the
      pointer is the item's graphic element); by raw index, its round caps
      following it }
    PeerRows: array of TTyStItem;
    PeerHostIdx: TTyIntegerArray;
    PeerFollowIdx: array of TTyIntegerArray;
    { THE SERIES' MARKERS [F2b]: every markPoint / markLine / markArea
      element whose host this series is, each with a blur state
      (MarkerView.toggleBlurSeries: they enter blur with the series and
      leave it in allLeaveBlur); MarkPart names it as the oracle does
      (mp0, ml0, ml0.from, ma0, ...#label) }
    Marks: array of TTyStElement;
    MarkIdx: TTyIntegerArray;
    MarkPart: TTyStringArray;
    { [R2-B] THE MARKER ITEMS' hoverStates (the Symbol / Line / polygon
      flags), by item key (mp0, ml0, ma0) -- kept across renders, as the
      updated elements keep theirs; an item at normal has no entry }
    MarkFlagKey: TTyStringArray;
    MarkFlagHover: TTyIntegerArray;
    { [R2-I9] the hover-layer flag the rows were last given (HlOn) and
      whether they were since the sync (HlSet) }
    HlOn, HlSet: Boolean;
  end;

  { WHAT A notMerge OPTION CARRIES OVER of a series' state records
    [Batch 96]: the series' view key and type, and each view row's
    DataDiffer key and raw index -- upstream keeps the view (same id, same
    type) and its elements by the data diff, and a reused element keeps its
    hoverState and __highByOuter bits }
  TTyStCarryKeys = record
    Present: Boolean;
    ViewKey, SeriesType: string;
    Keys: TTyStringArray;
    Raws: TTyIntegerArray;
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
  { saveAsImage's click [Batch 125]: AFileName the name upstream downloads
    as, AOptsJson the export options it asks for (SaveToFile's). AHandled
    True: the host saved (or declined) -- no dialog, no file. }
  TTyToolboxSaveEvent = procedure(Sender: TObject; var AFileName: string;
    const AOptsJson: string; var AHandled: Boolean) of object;
  { [R2-J2] AN IMAGE THE CHART CANNOT LOAD ITSELF: an option's picture given
    as a URL (an http address, a file path -- anything but a `data:` URL
    and an image list's `image://list/index`), written without the
    `image://` in front. Set AImage to the picture -- the chart owns it from
    then on -- or leave it nil; the answer is kept (ForgetResolvedImages
    asks again). Upstream loads the URL; this control never fetches. }
  TTyChartResolveImageEvent = procedure(Sender: TObject; const AUrl: string;
    var AImage: TBGRABitmap) of object;
  { [R2-I8] one axis' BaseAxisPointer, as far as its label goes: the memo
    render() keeps (PointerDrawLabelText) }
  TTyPtrMemoEntry = record
    Key: string;
    { _lastValue / _lastStatus: HasLast False is their null (never
      rendered, or cleared); LastShown the status 'show' }
    HasLast, LastShown: Boolean;
    LastValue: Double;
    { _lastGraphicKey (the pointer's type); none before the first show }
    HasGraphicKey: Boolean;
    GraphicKey: TTyAxisPointerType;
    { the full update (FStGen) the memo was rendered under, and the
      updateAxisPointer action (FPtrUpdGen) it last rendered for }
    Gen, UpdGen: Integer;
    Text: string;
  end;
  { the skin's inks for the toolbox [Batch 125] }
  TTyTbInk = record
    Stroke, StrokeHover, Background, Border, Brush, Title: TTyChartColor;
    FontName: string;
    FontSizeLogical, FontWeight: Integer;
  end;
  { one icon element's hover [Batch 125]: the emphasis the hover entered,
    the title shown, the adjusted position and align the emphasis state
    brought, and the hover's emphasis change waiting for the next frame
    (echarts applies an element's states in _onframe, not in the mouseover) }
  TTyTbIconLive = record
    HoverEmph, TextShown, AdjPos, AdjAlign: Boolean;
    PendEnter, PendLeave: Boolean;
  end;

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
    Silent: no `updated` event for this update.
    Transition [F3c]: `transition` -- the series the update's universal
      transition takes, `{from, to}` finders (seriesIndex / seriesId) or a
      list of them, instead of the series' own keys (HasTransition: given
      and truthy). }
  TTySetOptionOpts = record
    NotMerge, LazyUpdate, Silent: Boolean;
    ReplaceMerge: TTyStringArray;
    HasTransition: Boolean;
    Transition: TTyUtTransitionArray;
  end;

{ The options object as JSON text -- `{notMerge, replaceMerge, lazyUpdate,
  silent, transition}`, replaceMerge a main type or an array of them, the
  flags read for their JavaScript truthiness, `transition` as
  TyUtParseTransition reads it [F3c], other keys ignored. '' is no
  options. False when the text is no object. }
function TySetOptionOptsOf(const AJson: string; out AOpts: TTySetOptionOpts): Boolean;

type
  { [Batch 100] ONE TOOLTIP AS IT WAS ASKED FOR: the hover at the moment of
    a show -- or of a show still waiting out its delay. The box on screen is
    this, not the pointer: with a delay, or while a hide waits, the two are
    different things. Hits hold axis pointers into the build, so a rebuild
    drops every snapshot. }
  TTyTipSnap = record
    Datum: TTyChartDatumRef;
    Hits: TTyAxisHitArray;
    Element: Integer;
    { the point the box is placed from: a pointer's, or one a showTip found
      (findPointFromSeries, an element's centre) -- fractional [Batch 153] }
    X, Y: Double;
    { [Batch 153] a manual show's placement: `position` from the payload
      (its JSON; '' none), which goes before the cascade's, and the
      default model of position 'bottom' under the cascade }
    PosJson: string;
    PosDefault: Boolean;
    { [F4b] ACROSS A RE-RENDER (TooltipView.render keeps the box up): the
      axes as a dataByCoordSys (JSON) while the build they pointed into is
      gone -- Stale until the next build reads them back by raw row -- and
      the box held where it was painted (Frozen at FrozenX / FrozenY, its
      top-left) until a show places it again }
    DbcJson: string;
    Stale: Boolean;
    Frozen: Boolean;
    FrozenX, FrozenY: Double;
    { [R2-I7] THE DEFAULT MARKUP, built when the show is TRIED -- upstream's
      _showAxisTooltip / _showSeriesItemTooltip build it (a valueFormatter
      runs there) before _showOrMove, whatever the delay, a formatter or an
      unchanged content then does with it }
    MarkupHas: Boolean;
    Markup: TTyTooltipLineArray;
  end;

  { [R2-I7] WHAT A SHOW PUT IN THE BOX: _showTooltipContent's setContent --
    the spec it was shown under, the ink, the lines, whether it is an axis
    tooltip, the formatter's text. Has False: the show drew nothing. Built
    once per show; a paint only draws it. }
  TTyTipContent = record
    Has: Boolean;
    Spec: TTyTooltipSpec;
    Ink: TTyTooltipInk;
    Lines: TTyTooltipLineArray;
    OnAxis: Boolean;
    Fmt: string;
  end;

  { [F4b] an axis pointer kept across a re-render: the axisPointer model's
    status, value and seriesDataIndices outlive the update (updateModelActually
    wrote them into the model), so the pointer stays where it was }
  TTyPtrKeep = record
    Dim: string;
    Index: Integer;
    Cross, Linked, NoTip: Boolean;
    Value, SnapValue: Double;
    Series, Rows: TTyIntegerArray;
  end;
  TTyPtrKeepArray = array of TTyPtrKeep;

  { [Batch 153] AN ACTION WAITING: a payload the chart dispatched while one
    of its own ran (upstream's _pendingActions), or the global listener's
    pending showTip / hideTip -- with the axis hits an internal showTip
    carries beside its dataByCoordSys }
  TTyTipAct = record
    Payload: TJSONObject;
    Hits: TTyAxisHitArray;
    HasHits: Boolean;
    { [F4b] the brushSelect a visual stage dispatched inside an action: its
      brushselected event (it has no update), waiting in the same queue }
    EventJson: string;
  end;

  { [Batch 153] what TooltipView._tryShow is handed: the point, the axis
    hits of a dataByCoordSys (HasDbc), or the target -- its dispatcher's
    datum and its element -- and a manual show's placement }
  TTyTipEvent = record
    X, Y: Double;
    Hits: TTyAxisHitArray;
    HasDbc: Boolean;
    Datum: TTyChartDatumRef;
    Element: Integer;
    PosJson: string;
    PosDefault: Boolean;
  end;

  { [Batch 115] THE RETURN CIRCLE'S LAYOUT, as the virtual root's layout
    stays after a roll-up (sunburstLayout only ever sets it) }
  TTySunVirt = record
    Has: Boolean;
    CX, CY, R0, R: Double;
  end;

  { [Batch 115] ONE ANIMATION WRAP (util/animation.ts createWrap): done when
    every element added has finished or been stopped }
  TTyTmWrap = class
  public
    Pending: Integer;
    Live: Boolean;
    procedure Hit;
  end;

  { [Batch 115] A TREEMAP ELEMENT STILL LEAVING: the old rect and its words,
    its row and kind (0 the background, 1 the content), and the proxy its
    shape and opacity run on (nil: it is not animated) }
  TTyTmGhost = record
    Row, Kind: Integer;
    El: TTyChartElement;
    HasLabel: Boolean;
    LabelEl: TTyChartElement;
    P: TTyChartAnimProxy;
    { its words' fade, still running from when it was new }
    LP: TTyChartAnimProxy;
  end;

  { [Batch 115] A TREEMAP'S DRILL-DOWN (TreemapView._doAnimation): the
    proxies of its node groups (x, y; a deleted group's too), its rects
    (shape.x / y / width / height, style.opacity) and its labels' fades, by
    row; the elements leaving; the layout and storage it left; the wrap }
  TTyTmProxyPair = array[0..1] of TTyChartAnimProxy;
  TTyTmAnim = record
    Wrap: TTyTmWrap;
    Groups: array of TTyChartAnimProxy;
    Rects: array of TTyTmProxyPair;
    Labels: array of TTyTmProxyPair;
    GhostGroup: TTyBoolArray;
    Ghosts: array of TTyTmGhost;
    Old: TTyTreemapSolved;
    OldHave: TTyTreemapHave;
    { [R2-C] A MERGE'S TRANSITION, from the OLD tree to a new one: the new
      rows' old rows (Map) and back (O2N) -- nil for the same tree; the
      deleted node groups by their OLD row (OldGroups: Groups is by the new
      row). Old's borrowed option pieces are the replaced option's -- never
      read through them }
    Map, O2N: TTyIntegerArray;
    OldGroups: array of TTyChartAnimProxy;
    { a frame has been stepped since the arming: until then a leaving
      element is not dirty and its words stand where they were (setToFinal
      copies the values without marking it) }
    Stepped: Boolean;
  end;

  { [F5] ONE NODE OF THE ACCESSIBLE TREE'S COMPONENT PART: a component (Part
    -1, its parts below it) or a part (a leaf: Part its index, 0 for a
    stop of one part); Parent the plan index of its node, -1 the root's
    child }
  TTyAccPlanNode = record
    Role: TLazAccessibilityRole;
    Name: string;
    Stop: TTyKbStop;
    Part: Integer;
    Parent: Integer;
  end;
  TTyAccPlan = array of TTyAccPlanNode;

  { [R2-I6] A SERIES' STORE AS ITS FILL LEFT IT, kept for the next build of
    the same tree (StoreKeepTake): the option's Generation, the recipe it was
    filled by (dimensions, encode, the table it read), its own copy, and per
    column borrowing an axis' category list what that list was -- collecting
    or fixed, deduplicating or not, how many categories it held before this
    fill (Pre) and all it held after (List) }
  TTyStoreKeep = record
    Valid: Boolean;
    Used: Boolean;
    Gen: Int64;
    Sig: string;
    Store: TTyDataStore;
    MetaDim: TTyIntegerArray;
    MetaCollect, MetaDedup: array of Boolean;
    MetaPre: TTyIntegerArray;
    MetaList: array of TTyStringArray;
  end;
  TTyStoreKeepArray = array of TTyStoreKeep;

  TTyAdvanceChart = class(TTyCustomControl, ITyAccessibleHost)
  private
    FOption: TTyChartOption;
    FBuild: TTyChartBuild;
    FIndex: TTyAxisSeriesIndex;
    { WHAT EACH AXIS KEEPS FROM ONE RENDER TO THE NEXT [Batch 101]: the
      category interval's hysteresis store and the split areas' colours by
      tick value. Lives as long as the axis' model: a notMerge clears it, a
      merge forgets only the axes it brought in new. }
    FAxisMemory: TTyAxisMemoryStore;
    { THE POLARS of the last build, indexed by component index (a hole or a
      polar missing an axis is nil) [Batch 111] }
    FPolars: TTyPolarArray;
    { THE SINGLE AXES of the last build, indexed by component index (a hole
      is nil) [Batch 118] }
    FSingles: TTySingleArray;
    { EVERY themeRiver laid out, index-parallel to FBindings [Batch 118] }
    FRivers: TTyThemeRiverLayoutArray;
    { THE PARALLELS of the last build, by component index (a hole is nil),
      each parallel series' rows as laid out (index-parallel to FBindings),
      and the active intervals each parallelAxis MODEL keeps -- by component
      index and as long as the model: axisAreaSelect writes them, a merge
      keeps them, a notMerge or a new model in the slot drops them
      [Batch 128] }
    FParallels: TTyParallelArray;
    FParSolved: TTyParallelSolvedArray;
    FParIntervals: array of TTyParallelIntervalArray;
    { the parallel series views that have rendered (by view key): a view
      clips its enter once, on its first render (ParallelView._initialized);
      a legend-hidden series keeps its view }
    FParSeen: TStringList;
    { THE PARALLEL AXES' AREA SELECT [Batch 130]: each parallelAxis view's
      BrushController, by component index (nil until its view renders); the
      axis whose view the update of an axisAreaSelect does not render
      (fromAxisAreaSelect: the first the query finds; -1 none) -- it keeps
      its covers until an update renders it again --, whether that update
      is running, and the actions the views dispatched }
    FParBrushCtls: array of TTyBrushController;
    FParBrushSkip: Integer;
    FParBrushInAas: Boolean;
    FParBrushLog: array of TTyParallelBrushAction;
    { [Batch 140] PARALLELVIEW per parallel component: the press a click is
      judged against and its throttle; the throttles' pending calls; the
      clock a test drives (NaN: the tick count) and its timer; the
      parallelAxisExpand actions the views dispatched }
    FParExp: array of TTyParallelExpandView;
    FParExpPend: array of TTyParallelExpandPending;
    FParExpSeq: Integer;
    FParExpNow: Double;
    FParExpTimer: TTimer;
    FParExpLog: array of TTyParallelExpandAction;
    { [Batch 140] THE THUMBNAILS: each component's model, the series it
      targets (cached at its optionUpdated) and its view; the one whose
      bridge the target graph holds -- the last shown one an optionUpdated
      reached, every optionUpdated clearing every series' bridge first (-1
      none); a render's copy is due (a full update, not a roam); the
      thumbnail a press armed (-1) and where the pointer was }
    FThumbs: TTyThumbStateArray;
    FThumbOwner: Integer;
    FThumbSnapDue: Boolean;
    FThumbFresh: Boolean;
    FThumbDrag: Integer;
    FThumbDragX, FThumbDragY: Integer;
    FBindings: TTySeriesBindingArray;
    FStores: array of TTyDataStore;
    { [R2-I6] the parsed stores kept between builds of one tree, per slot }
    FStoreKeep: TTyStoreKeepArray;
    { Every bar's width and offset, index-parallel to FBindings. Solved in
      Relayout rather than Rebuild because it needs the FINAL pixel extents:
      the plot rect is shrunk to fit the labels in phase C, and a band measured
      before that is the wrong width -- silently, since nothing raises and the
      bars merely come out slightly off. }
    FBarCols: TTyBarColumnArray;
    { THE BARS ON A POLAR, index-parallel to FBindings, solved where FBarCols
      is [Batch 113] }
    FPolarBars: TTyPolarBarLayoutArray;
    { EVERY CANDLESTICK'S AND BOXPLOT'S width, offset and clip, index-parallel
      to FBindings, solved beside FBarCols for its reason [Batch 108] }
    FWhiskers: TTyWhiskerLayoutArray;
    { THE COMPUTED DATASETS (a transform's results) the sources read: kept
      as long as FSources borrow from it, cleared when the stores are built
      again [Batch 108] }
    FDatasetCache: TTyDatasetCache;
    { THE TRANSFORMS' Math.random [Batch 134]: ecStat's k-means draws from
      the chart's stream where upstream's setOption runs the transform --
      once, before the render draws anything. The cache is rebuilt every
      build, so every build runs the transforms again from FTransformSeed
      (the same clusters on a resize); only the first build after an
      option that brought datasets in moves the chart's stream on. }
    FTransformSeed: LongWord;
    FTransformSeedTaken: Boolean;
    FTransformRandom: LongWord;
    { THE SCATTER JITTER'S PASS: the random state and every category axis'
      placed points, started again by every BuildSeriesList [Batch 110] }
    FJitter: TTyJitterPass;
    { LARGE MODE, by binding slot, as the last build decided it [Batch 117] }
    FLargeKinds: array of TTyLargeKind;
    { [R2-J3] per slot, what the series' visual callbacks answered on the
      last rebuild (nil: none is a callback) -- upstream's visual stage runs
      them once per update }
    FItemCbs: array of TTyItemCallbacks;
    { PROGRESSIVE RENDERING AND appendData [Batch 119]: every slot's
      pipeline (its context, its chunks, the args its tasks ran with); a
      chunk still to draw; the next update is a setOption's (a pipeline with
      no context yet); the list a progress frame left is the one to paint;
      the ms a step costs (NaN: the clock measures it); rows appended and
      not yet taken in; the relayout taking them in; the axes' raw extents
      as the last update left them, which appendData keeps; and an update
      laid out whose `rendered` is still to fire. }
    FProg: TTyProgRunArray;
    FProgUnfinished: Boolean;
    FProgFresh: Boolean;
    FProgReuse: Boolean;
    { [R2-I9] THE LIST AN UPDATE BUILT (FullUpdateWith, DropStaticKeepList)
      and nothing has touched since: the paint draws it as it stands instead
      of building the same list a second time }
    FListFresh: Boolean;
    FProgStepCost: Double;
    FStreamPending: Boolean;
    FStreamRelayout: Boolean;
    FFrozen: TTyAxisZoomArray;
    FFrozenKeys: TTyStringArray;
    FFrozenOn: Boolean;
    FFlushDue: Boolean;
    { THE INCREMENTAL LAYER (zrender's, for `incremental` elements): every
      shown element of a progressive run painted once, onto a layer of its
      own that a frame adds its chunk to and the static layer blits where
      the first of them stands in the paint order; whether it holds the
      list as it stands, its PPI, and what of each element it holds (rows
      of a growing batch, 1 for anything else, 0 for nothing) }
    FProgLayer: TBGRABitmap;
    FProgLayerOk: Boolean;
    FProgLayerPPI: Integer;
    FProgLayerScale: Integer;   { the device scale it holds, its pixels per device px (#83) }
    FProgPainted: TTyIntegerArray;
    { [R2-L] A PROGRESS FRAME'S STATIC LAYER IN PLACE: the last full static
      paint's own bitmap (FProgWork), the same bitmap as it stood when the
      incremental layer was blitted (FProgUnder), and the layer as blitted
      then (FProgSeen). A frame that only drew chunks onto the layer
      changes the static bitmap only where the layer changed: there it
      starts from FProgUnder, takes the layer, and has what comes after it
      drawn again inside those pixels -- what the full paint would put there
      (see ProgFastPaint). FProgCap: the full paint is capturing;
      FProgFastFrame: since the capture the static layer was dropped by
      progress frames alone. }
    FProgCap, FProgCapUnder, FProgCapOk, FProgFastFrame: Boolean;
    { [R2-L] THE LAYER DRAWN AGAIN WHERE A STATE CHANGED IT: whether the layer
      is what a whole drawing in paint order gives (FProgLayerInOrder; the
      last position drawn on it, FProgLayerLastPos), and the box, in device
      px, a state patch changed on it (FProgLayerRegion when
      FProgLayerRegionOn) -- see ProgLayerRegionRedraw }
    FProgLayerInOrder, FProgLayerRegionOn: Boolean;
    FProgLayerLastPos: Integer;
    FProgLayerRegion: TTyXYWH;
    FListTailAt: Integer;
    FProgUnder, FProgWork, FProgSeen: TBGRABitmap;
    FProgBlitAt, FProgCapW, FProgCapH, FProgCapPPI, FProgCapScale: Integer;
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
    { THE MATRICES, one per component [Batch 145]: built with the stores
      (each series on one borrows its header trees' category lists), laid
      out on the canvas with the calendars, freed after the stores. }
    FMatrices: array of TTyMatrix;
    { THE GEOS, one per geo component, laid out on the canvas: the
      coordinate system and the map it draws [Batch 146] }
    FGeos: array of TTyGeo;
    { [Batch 148] each geo model's option.selectedMap -- nil until
      optionUpdated would have made it, the model's for as long as the
      model lives; the render count a region found under the pointer is
      told by; the geos' flags changed since the last frame }
    FGeoSel: array of TJSONObject;
    FGeoGen: Integer;
    FGeoDirty: Boolean;
    { [F6b] what an SVG map's text is measured with while it is parsed: one
      measurer per render, made on the first text }
    FGeoSvgMeas: ITyTextMeasurer;
    { the SVG maps' flags over a render: the geos' and the map series' }
    FSvgKeepGeo, FSvgKeepMap: array of TTyGeoSvgFlags;
    { [Batch 150] the centre and zoom a geoRoam wrote back into each geo
      model's option (Valid after the first), the model's for as long as it
      lives; and how many geos the last geoRoam moved }
    FGeoRoam: array of TTyGraphRoamState;
    FGeoRoamHits: Integer;
    { [Batch 152, D14 GE4] the map series: their groups, each slot's group,
      the original data of a series whose data is now the group's
      statistic (owned), the groups' own geos (nil for one on a geo
      component), the roam written back into a group's series, and where
      the last build put each map picture and each series' legend symbols }
    FMapGroups: array of TTyMapGroup;
    FMapGroupOf: TTyIntegerArray;
    FMapOrig: array of TTyDataStore;
    FMapGeos: array of TTyGeo;
    FMapRoam: array of TTyMapRoam;
    FGeoDraws: array of TTyGeoDrawRange;
    FMapSyms: array of TTyGeoDrawRange;
    { a heatmap on a geo's layer, per slot, as the last build made it }
    FHeatLayers: array of TTyHeatLayer;
    { THE TREES, laid out per slot -- an empty record where the slot is no
      tree. [Batch 73] }
    FTrees: array of TTyTreeSolved;
    { THE SUNBURSTS, per slot. [Batch 75] }
    FSunbursts: array of TTySunburstSolved;
    { THE TREEMAPS and their inks, per slot: the labels are cut to their
      cells when the layout is, so the specs are read then. [Batch 76] }
    FTreemaps: array of TTyTreemapSolved;
    FTreemapInks: array of TTyTreemapInk;
    { [Batch 115] THE DRILL-DOWNS, by series index: a sunburst's view root
      (0: none) and its return circle's last layout; a treemap's view (the
      view root, and what the next render is for), its last solve and
      element storage, and its drill-down animation. A new option (a merge
      that visits the series too) forgets them all, as resetViewRoot does
      on a new tree. }
    FSunRoot: TTyIntegerArray;
    FSunVirt: array of TTySunVirt;
    { THE RETURN CIRCLE'S CLICK HANDLERS, by series index: SunburstView adds
      one on every render while drilled and never takes one off (the piece
      is kept), each bound to the view root's parent of its render; a
      render at the root removes the piece, and them }
    FSunHandlers: array of TTyIntegerArray;
    FTmView: array of TTyTreemapView;
    FTmPrev: array of TTyTreemapSolved;
    FTmHave: array of TTyTreemapHave;
    FTmAnim: array of TTyTmAnim;
    { [R2-C] THE LAST SOLVE AND STORAGE a setOption's new tree takes over
      (TreemapView keeps _oldTree and _storage across it), by series index,
      with the view keys of the render they were drawn in; consumed by the
      next solve }
    FTmOld: array of TTyTreemapSolved;
    FTmOldHave: array of TTyTreemapHave;
    FTmOldKeys: TTyStringArray;
    { the series' view keys when the treemaps were last solved }
    FTmViewKeys: TTyStringArray;
    { a press on a breadcrumb item: its series, its index, where }
    FCrumbPressSeries, FCrumbPressIndex, FCrumbPressX, FCrumbPressY: Integer;
    { a press that started on a breadcrumb item is not a treemap click }
    FCrumbPressed: Boolean;
    { THE HOVERED BREADCRUMB ITEM [F2a]: its series and place (-1 none),
      and the render that made it -- every solve draws new items, which
      start in no state (Breadcrumb.render removeAll) }
    FTmCrumbHoverS, FTmCrumbHoverK, FTmCrumbHoverGen: Integer;
    FTmCrumbGen: Integer;
    FTmCrumbDirty: Boolean;
    { the series a sunburst drill renders for: its pieces transition }
    FHierDrill: TTyBoolArray;
    { THE SANKEYS and their inks, per slot. [Batch 79] }
    FSankeys: array of TTySankeySolved;
    FSankeyInks: array of TTySankeyInk;
    { THE CHORDS and their inks, per slot. [Batch 120] }
    FChords: array of TTyChordSolved;
    FChordInks: array of TTyChordInk;
    { THE LINES SERIES by slot, solved in the layout pass; the slot the
      coordinate hook projects for; the trail's layer -- a lines series
      with effect.trailLength, faded by lastFrameAlpha every frame of the
      continuous phase [Batch 121] }
    FLines: TTyLinesSolvedArray;
    FLinesSpecs: TTyLabelSpecTable;
    FLnSlot: Integer;
    FTrailLayer: TBGRABitmap;
    { THE CUSTOM SERIES [Batch 123]: one view per series index (its group
      of item roots and its last data, kept across updates for the merge
      by data id); the element each paint list entry was made from (nil for
      the rest); the action the running update is for (renderItem's
      actionType); each slot's clip (css px); and, while renderItem runs,
      the slot, its handler, its params and its api }
    FCustomViews: array of TTyCustomView;
    FCustomPaintEls: TTyGfxElArray;
    { [R2-D] the device scale the custom paths were tagged at, and whether a
      universal transition stopped a custom item's own animations (the list
      is laid out again) }
    FCustomUtScale: Double;
    FCustomUtStopped: Boolean;
    FCustomAction: string;
    FCustomClipOn: TTyBoolArray;
    FCustomClip: array of TTyXYWH;
    FCustomSlot: Integer;
    FCustomHandler: TTyChartRenderItem;
    FCustomParams: TTyCustomParams;
    FCustomApi: TObject;
    FCustomMissing: string;
    { the custom elements' transitions' own driver [Batch 124] }
    FCuAnim: TTyAnimation;
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
    { [F3d] the edge rows' DataDiffer keys, read off the option the layout
      was made from }
    FGraphEdgeKeys: array of TTyStringArray;
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
    { [Batch 150] the geo a left press armed (its RoamController), or -1 --
      FRoamSeries is -1 then; the pointer's last place is FRoamX / FRoamY }
    FRoamGeo: Integer;
    { A NODE DRAG on a graph on a view [Batch 114]: zrender's Draggable holds
      the node from the press to the release, and every move between is one
      'drag' (TyGraphDragStep). Slot -1: none. }
    FGraphDragSlot, FGraphDragNode: Integer;
    FGraphDragX, FGraphDragY: Integer;
    FGraphDragFirst: Boolean;
    { A NODE DRAG on a sankey [Batch 114]: the rect's own shape position,
      accumulated from the press (SankeyView's drift adds each delta to
      shape.x / y), the box size its closure holds, and the pointer. }
    FSankeyDragSlot, FSankeyDragNode: Integer;
    FSankeyDragX, FSankeyDragY: Integer;
    FSankeyDragShapeX, FSankeyDragShapeY, FSankeyDragW, FSankeyDragH: Double;
    { WHAT dragNode WROTE, per series and per node: localX / localY, which
      upstream writes into the series option's node item and which beat the
      item's own (setNodePosition) [Batch 114] }
    FSankeyLocal: array of TTySankeyLocalArray;
    { a sankey's roam: the centre and zoom the sankeyRoam action wrote back,
      per series [Batch 114] }
    FSankeyRoam: array of TTyGraphRoamState;
    FOnSankeyRoam: TTyGraphRoamEvent;
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
    { echarts.connect [Batch 141]: chart.group ('' is none), the connect
      status (-1 never set, 0 pending, 2 updated -- upstream never sets its
      1) and the chart's number in creation order (its view uids) }
    FGroup: string;
    FConnectStatus: Integer;
    FInstanceNo: Integer;
    { dispatchAction(payload, silent) publishes nothing [Batch 141] }
    FEvSilent: Integer;
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
    { the old option's records and keys, until the new one's first sync maps
      them across; the hovered item's series and raw row [Batch 96] }
    FStCarry: array of TTyStSeries;
    { taken since the last render: a second setOption before it carries
      nothing new -- the render the records belong to is still the old one
      [Batch 99] }
    FStCarryHeld: Boolean;
    FStCarryKeys: array of TTyStCarryKeys;
    FStCarryHover: Boolean;
    FStCarryHoverSeries, FStCarryHoverRaw: Integer;
    FStGen, FStBuiltGen: Integer;
    FStRerender, FStDirty: Boolean;
    { [R2-I9] THE HOVER LAYER: the copies it brushes (the paths on it in
      their hover style, in list order) and whether they are to be found
      again; the storage count the threshold reads (FHlCount, counted again
      when not FHlCountOk) }
    FHoverList: TTyPaintList;
    FHoverDirty: Boolean;
    FHlCount: Integer;
    FHlCountOk: Boolean;
    { [P2] the last StApplyChanged changed a geo's flags }
    FStGeoApplied: Boolean;
    { StPrimaryInk held through a sync's declarations [P2] }
    FStInk: TTyChartColor;
    FStInkHold, FStInkHeld: Boolean;
    { [P2] through the same declarations: the three state styles of the last
      row with no object of its own (its chain past the item, its block),
      and a series' emphasis spec by its node -- what every such row of a
      series reads alike }
    FStMemoOk: Boolean;
    FStMemoS: Integer;
    FStMemoBlk: string;
    FStMemoNodes: TTyStNodeArray;
    FStMemoDecl: array[0..2] of TTyStObject;
    FStMemoSpecNode: TJSONObject;
    FStMemoSpec: TTyChartEmphasisSpec;
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
    { A SANKEY'S VIEW, per slot: a View whose data rect and view rect are both
      its box (createViewCoordSysSimply), its roam options read as a graph's
      [Batch 114] }
    FSankeyViews: array of TTyGraphView;
    FSankeySpecs: array of TTyGraphSpec;
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
    { ---- visualMap interaction [Batch 116] ----
      each view's own state between renders; the indicator's and its label's
      animation bags (new with every build); their driver; what a
      selectDataRange wrote into a model -- a continuous one's range, a
      piecewise one's selected map as JSON ('' none); the drag zrender's
      Draggable holds (the component, the handle 0 / 1 / 2 the bar, the
      pointer where it was last); where the hovered target was found }
    FVmLive: array of TTyVmLive;
    FVmIndBag, FVmLabBag: array of TTyAnimBag;
    FVmAnim: TTyAnimation;
    { THE GRAPHIC COMPONENT [Batch 122]: its model (the flattened element
      list and the options pending for the view), its view (the elements by
      id), the view's own animation driver; a fresh option's init still to
      run; a render pending (an update, a new model); the size it was
      placed at; and the last build's paint elements, each with the element
      it came from (a textContent's own) -- the list's first entries, and
      the ones under the axes painted before them }
    FGfxModel: TTyGfxModel;
    FGfxView: TTyGfxView;
    FGfxAnim: TTyAnimation;
    FGfxFresh, FGfxPending: Boolean;
    FGfxW, FGfxH: Double;
    FGfxPaint: array of TTyChartElement;
    FGfxPaintEl: TTyGfxElArray;
    FGfxUnder: TTyPaintList;
    { a draggable element being dragged: its id and the last point }
    FGfxDragOn: Boolean;
    FGfxDragId: string;
    FGfxDragX, FGfxDragY: Integer;
    FVmRangeHas: array of Boolean;
    FVmRange0, FVmRange1: TTyDoubleArray;
    FVmSel: TTyStringArray;
    { [R3-B] each visualMap model's own visuals, as completeVisualOption
      left them (TyVisualMapModelNew); nil where none is kept }
    FVmModels: array of TJSONObject;
    FVmDragVm, FVmDragIdx, FVmDragX, FVmDragY: Integer;
    FVmUidSeq: Integer;
    FEvHoverX, FEvHoverY: Integer;
    { [Milestone D9-D14] the target a pan's move found before the picture
      moved: EventMove takes it instead of looking again }
    FEvPreset: Boolean;
    FEvPresetT: TTyChartEventTarget;
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
    { [F6a] THE CHART'S CURSOR: the CSS name upstream's canvas would show
      (zrender's Handler and the roam / brush listeners' setCursorStyle),
      and the host's own Cursor kept while the chart shows another }
    FCursorName: string;
    FHostCursor: TCursor;
    FHasHostCursor: Boolean;
    FCursorSet: TCursor;
    { the clock: NaN is the machine's, a number a test's }
    FDzNow: Double;
    FDzTimer: TTimer;
    FOnDataZoom: TTyDataZoomEvent;
    { an action's window in value mode (startValue / endValue in
      FDzRawStart / FDzRawStop) [Batch 125] }
    FDzRawValue: array of Boolean;
    { THE TOOLBOX [Batch 125] -- see its section }
    FTbSpecs: array of TTyToolboxSpec;
    FTbLayouts: array of TTyToolboxLayout;
    FTbPrev: array of TTyPointF;
    FTbLive: array of array of TTyTbIconLive;
    FTbGen: Integer;
    FTbStatus: TStringList;
    FTbMagicTitle: TTyStringArray;
    FTbZoomActive: Boolean;
    FTbHistory: TTyTbHistory;
    FTbSel: TTyTbSnapshot;
    FTbBackup: string;
    FTbCursor: string;
    { the select brush's end: its grid, type and range (CSS px: x lo, x hi,
      y lo, y hi) }
    FTbBrushGrid: Integer;
    FTbBrushType: TTyTbBrushType;
    FTbRange: array[0..3] of Double;
    { THE SELECT BRUSH IS A BrushController [Batch 127]: brushType 'auto',
      its panels the grids the select dataZooms target (each one's build
      grid index beside it) }
    FTbBrushCtl: TTyBrushController;
    FTbBrushGrids: TTyIntegerArray;
    { the brush feature's render: BrushFeature._brushType / _brushMode, and
      the statuses an update that renders later took at its dispatch }
    FTbBfHas, FTbBfMulti: Boolean;
    FTbBfType: TTyBrushType;
    FTbBfSnap: Boolean;
    FTbBfSnapHas, FTbBfSnapMulti, FTbBfSnapBrushed: Boolean;
    FTbBfSnapType: TTyBrushType;
    FTbError: string;
    FOnToolboxSaveAsImage: TTyToolboxSaveEvent;
    { [R2-J2] OnResolveImage and the answers it gave, by URL (owned; a nil
      answer kept too) }
    FOnResolveImage: TTyChartResolveImageEvent;
    { [R2-I8] see OnTooltipHtml and TooltipAutoRichText }
    FOnTooltipHtml: TTyChartTooltipHtmlEvent;
    FTooltipAutoRichText: Boolean;
    FResolvedImages: TStringList;
    { THE TIMELINE [Batch 129] -- see its section }
    FTlView: TTyTimelineView;
    FTlAnim: TTyAnimation;
    FTlUidSeq: Integer;
    FTlNow, FTlDue: Double;
    FTlTimer: TTimer;
    FTlDragging, FTlStatesDirty: Boolean;
    { THE BRUSH COMPONENTS [Batch 126] -- see their section. Per component:
      the model from its option, the areas and the painting option the
      model keeps (a merge keeps them, a notMerge does not), the view's
      controller. }
    FBrushSpecs: array of TTyBrushSpec;
    FBrushAreas: array of TTyBrushAreaArray;
    FBrushPaint: TTyBrushOptArray;
    FBrushHasPaint: array of Boolean;
    FBrushCtls: array of TTyBrushController;
    { zrender's Draggable on a cover's piece }
    FBrushDragOn: Boolean;
    FBrushDragBrush, FBrushDragSerial: Integer;
    FBrushDragPiece: TTyBrushPiece;
    FBrushDragX, FBrushDragY: Double;
    FBrushCursor: string;
    { brushSelect's throttle (one per chart, as upstream's is per zr), the
      dispatches waiting on it, and what ran }
    FBrushThr: TTyBrushThrottle;
    FBrushPend: array of TTyBrushPending;
    FBrushPendSeq: Integer;
    FBrushNow, FBrushTickPrev: Double;
    FBrushTimer: TTimer;
    FBrushInSelect: Boolean;
    FBrushSelLog: array of TTyBrushSelectRec;
    FBrushEvLog: array of TTyBrushEventRec;
    { THE SELECTION [Batch 127]: FVisualRows as the visual stages before the
      brush's left them (the brush writes over a copy of these); an action's
      update whose brushSelect the next visual stage dispatches; the
      brushselected events waiting for their action's own event, and how
      deep the actions nest; the globalPan mutex's holder (a controller's
      uid, 0 none) }
    FBrushVisBase: array of TTyVisualRowArray;
    FBrushVisBaseOk: Boolean;
    FBrushPayload: Boolean;
    FBrushEmitQ: TTyStringArray;
    FBrushActDepth: Integer;
    FPanHolder: Integer;
    { `itemStyle.color: 'none'` -- the series paints NO fill. Not the same as
      unwritten, which is the palette's. }
    FSeriesColorNone: array of Boolean;
    { AND THE PALETTE PICK ITSELF, kept apart from the resolved colour
      because `auto` resolves to the PICK and not to the fill. A series that
      writes `itemStyle: { color: '#fff', borderColor: 'auto' }` is white
      with a border in the palette colour -- so both numbers exist at once
      and one field could not hold them. }
    FSeriesPick: array of TTyPalettePick;
    FSeriesPickAsked: array of Boolean;
    { the fill IS the pick: unwritten, or written `auto` [Batch 105] }
    FSeriesFromPick: array of Boolean;
    { upstream's colorFromPalette: the colour was UNWRITTEN -- `auto` asks
      the palette and still is not, so its rows take no per-datum slot }
    FSeriesColorFromPalette: array of Boolean;
    { THE PER-DATUM PALETTE, colorBy other than 'series' [Batch 105]: per
      binding slot, per RAW row, what dataColorPaletteTask gave the row --
      Asked False where the row kept the series' colour (its own colour, a
      visual channel's, a series colour that was written). Solved after the
      filters, with one scope per `type-colorBy` shared by every series of
      that kind. }
    FDatumPicks: array of array of TTyPalettePick;
    FDatumAsked: array of array of Boolean;
    { SeriesRowFills' object colours, by slot, read once a build: every row's
      itemStyle read out of the option, which a tooltip's colour dot asked for
      again on every pointer move. Dropped where FDatumPicks is rebuilt. }
    FRowObjFills: array of TTyRowFillArray;
    FRowObjDone: array of Boolean;
    { the raw count FRowObjFills was read for -- the fills themselves are nil
      where no row has an object colour [R2-L] }
    FRowObjN: array of Integer;
    { DECALS [Batch 131]. The series scope of the aria decal palette lives as
      long as upstream's GlobalModel: a merge keeps it (a renamed series picks
      on), a notMerge makes a new one. Per binding slot: the series' decal,
      and per RAW row a row's own where FRowDecalSet says so. }
    FDecalScope: TTyDecalScope;
    FSeriesDecals: TTyChartDecalArray;
    FRowDecals: array of TTyChartDecalArray;
    FRowDecalSet: array of TTyBoolArray;
    { [F4a] the same decals as objects, before the defaults: what a custom
      series' api.visual('decal') hands its renderItem (nodes not owned:
      the option's, or the built-in palette's) }
    FSeriesDecalRaws: array of TTyDecalRaw;
    FRowDecalRaws: array of array of TTyDecalRaw;
    { THE KEYBOARD FOCUS ITEM [Batch 144]: its series index and view row
      (-1 none), and whether the keyboard holds it now -- the ring is
      drawn, the item is highlighted and its tooltip shown. Leaving the
      control lets go but keeps the place: the next key takes it up again. }
    FKbSeries, FKbRow: Integer;
    FKbActive: Boolean;
    { THE ACCESSIBLE TREE [Batch 144]: the way out to the platform, the
      layout generation the tree was built for (-1 never), and each item
      object with its series index and view row }
    FAccLink: TTyAccessibleLink;
    FAccGen: Integer;
    FAccSyncing: Boolean;
    FAccItemObjs: array of TLazAccessibleObject;
    FAccItemSeries, FAccItemRows: TTyIntegerArray;
    { [F5] the focus item is a graph's edge row (FKbRow the edge's inner
      index); the focus stop (KeyNav), whether a component stop's part is
      taken up -- hovered, ringed -- and which part (-1 none: forgotten);
      the pointer target the part was given, to take back; the geo region
      a stop highlighted }
    FKbEdge: Boolean;
    FKbStop: TTyKbStop;
    FKbStopOn: Boolean;
    FKbPart: Integer;
    FKbHoverT: TTyChartEventTarget;
    FKbHoverHas: Boolean;
    FKbGeoIndex: Integer;
    FKbGeoName: string;
    { [F5] which items are edges; how many of the root's children are
      series lists; the component nodes with their stop and part }
    FAccItemEdge: TTyBoolArray;
    FAccSeriesCount: Integer;
    FAccCompObjs: array of TLazAccessibleObject;
    FAccCompStops: TTyKbStopArray;
    FAccCompParts: TTyIntegerArray;
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
    { ==== THE INIT OPTIONS a zrender takes [Batch 142] ====
      useCoarsePointer / pointerSize (the coarse pointer) and useDirtyRect.
      Published with upstream's defaults: 'auto' -- off on every desktop
      widgetset, see TyTouchPlatform -- 44, and off. }
    FCoarsePointer: TTyChartCoarsePointer;
    FPointerSize: Integer;
    FUseDirtyRect: Boolean;
    { ==== THE DIRTY-RECT PATH [Batch 142] ====
      FDrWork: the static painter's surface, kept, and the scratch a partial
      repaint draws on. FDrBase: the static picture before the series (the
      frame, the ground, the graphic under the axes, the axes), captured by
      every full static paint -- what a repainted rect starts from.
      FDrSnap: the list the static layer holds now, element by element
      with its paint rect; FDrSnapOk while it describes the cache.
      FDrDyn: the dynamic layer, kept, transparent outside FDrDynTiles.
      FDrMode 1: PaintSeries builds and prepares the list but draws nothing
      (FDrStaticList is what it would draw at rest, nil when the static
      layer would not hold one list). FDrPrepDone: the build already ran
      this frame -- a fallback to the full static paint must not run it
      again. The last frame's answer: FDrLastFull, FDrLastRects. The window:
      FDrPending (something asked for a frame), FDrQueued (the flush is
      queued), FDrFlushed (the frame is prepared and its rects invalidated:
      the paint only composites). }
    FDrWork: TBGRABitmap;
    FDrBase: TBGRABitmap;
    FDrBaseOk: Boolean;
    FDrCapture: Boolean;
    FDrSnap: TTyDirtySnap;
    FDrSnapOk: Boolean;
    FDrDyn: TBGRABitmap;
    FDrDynTiles: TTyZrRectArray;
    { the device scale of this frame (#83): FDrWork, FDrBase, FDrDyn and the
      static cache hold that many pixels per device px; the snapshot, the
      repaint pool, FDrDynTiles and FDrLastRects stay in device px }
    FDrScale: Integer;
    FDrMode: Integer;
    FDrStaticList: TTyPaintList;
    FDrPrepDone: Boolean;
    FDrLastFull: Boolean;
    FDrLastRects: TTyZrRectArray;
    FDrPending, FDrQueued, FDrFlushed: Boolean;
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
    { [R2-I7] the content the last show set (FTipCurDue: a show whose build
      was not standing, built at the next paint), the shows counted (a
      position function runs once per show: FTipPosGen the show its cached
      answer FTipPosAns belongs to), and _cbParamsList's data, one per row
      of the last axis show, for _updateContentNotChangedOnAxis }
    FTipCur: TTyTipContent;
    FTipCurDue: Boolean;
    FTipShowGen, FTipPosGen: Integer;
    { the show the last paint drew (a re-render freezing a show not drawn
      yet lays its box out first), and the colour it gave the box's border }
    FTipPaintGen: Integer;
    FTipBorderPainted: TTyColor;
    { [R2-I8] each axis' BaseAxisPointer memo: see PointerDrawLabelText }
    FPtrMemo: array of TTyPtrMemoEntry;
    { [R2-I8] one per updateAxisPointer action: render() runs on an action,
      not on a paint }
    FPtrUpdGen: Integer;
    FTipPosAns: TTyChartTooltipPos;
    FTipLastSigs: TTyStringArray;
    FTipLastSigSeries: TTyIntegerArray;
    { The element the hit came from, kept because it carries the colour of the
      thing the pointer is over. Asking the series for its colour instead would
      be a second answer to a question the ink has already answered, and would
      miss a per-datum itemStyle. }
    FTipElement: Integer;
    FTipX, FTipY: Integer;
    { [Batch 100] THE BOX'S OWN STATE, upstream's TooltipView and
      TooltipRichContent: whether it is on screen (the content element
      shown) and what for; `_show`, which only hideLater reads (it goes false
      the moment a hide is ARMED, while the box stays up); the show waiting
      out showDelay and when it fires; the hide waiting out hideDelay; the
      clock (NaN: the machine's, and only then does the timer run); the box
      and the element rect the last paint used. }
    FTipShown: Boolean;
    FTipShowFlag: Boolean;
    FTipSnap: TTyTipSnap;
    FTipPend: TTyTipSnap;
    FTipShowAt, FTipHideAt: Double;
    FTipShowSeq, FTipHideSeq, FTipSeq: Integer;
    FTipNow: Double;
    FTipTimer: TTimer;
    FTipBox, FTipRect: TTyRectF;
    { [Batch 104] what the last paint's string or handler formatter said }
    FTipFormatterText: string;
    { [R2-E] what the box last painted said, and what a frozen box says:
      TooltipView.render leaves the content element as it was until a show
      sets it again }
    FTipLastHas, FTipFrozenHas: Boolean;
    FTipLastSpec, FTipFrozenSpec: TTyTooltipSpec;
    FTipLastInk, FTipFrozenInk: TTyTooltipInk;
    FTipLastLines, FTipFrozenLines: TTyTooltipLineArray;
    FTipLastOnAxis, FTipFrozenOnAxis: Boolean;
    FTipLastFmt, FTipFrozenFmt: string;
    FTipLastBorder, FTipFrozenBorder: TTyColor;
    { [Batch 100] the option's own `status: 'show'` pointers are gone: the
      first pointer event rewrites every status, and an option set brings
      them back }
    FOptPtrGone: Boolean;
    { [R2-E] the over EventMove found, for EventOver }
    FEvOverDue: Boolean;
    FEvOverT: TTyChartEventTarget;
    FEvOverX, FEvOverY: Integer;
    { [R2-E] the axes ('mainType#index') a merge wrote a status on since }
    FOptPtrBack: TTyStringArray;
    { [Batch 153] THE ACTIONS THAT DRIVE THE TOOLTIP AND THE POINTER.
      FActCycle is upstream's IN_EC_CYCLE for them: an action dispatched
      while one of them runs waits in FActPending and is flushed after it,
      before `updated`. FGlShow / FGlHide are the global listener's pendings
      (the last of each; a show wins). FUapListener marks the
      updateAxisPointer the listener dispatches -- its showTip / hideTip go
      to the listener's pendings, not to the chart. FActHits is the hits the
      showTip being dispatched carries. FPressEl is the element a press was
      on, for zrender's click. }
    FActCycle: Integer;
    FActPending: array of TTyTipAct;
    FGlActive: Boolean;
    FGlShow, FGlHide: TTyTipAct;
    FUapListener: Boolean;
    FActHits: TTyTipAct;
    FPressEl: Integer;
    { [F4b] TooltipView._lastX / _lastY (NaN: null) and _lastDataByCoordSys
      (JSON, '' null); the keep timer _keepShow arms (NaN: none); the axis
      pointers kept across a re-render, put back by the next build; a guard
      so a timer's work does not run the other timers inside it }
    FTipLastX, FTipLastY: Double;
    FTipLastDbc: string;
    FTipKeepAt: Double;
    FTipKeepSeq: Integer;
    FTipKeepPtr: TTyPtrKeepArray;
    FTipKeepPtrDue: Boolean;
    FTipAdvancing: Boolean;
    { [F4b] A BATCH OF ANY ACTION: the items' own events of the action's
      type (and a refined action's refined events) are taken here, not
      published, while FBatchCapDepth > 0; the updates the items ask for
      wait (FBatchDefer) and run once after the last item }
    FBatchCapDepth: Integer;
    FBatchCapType, FBatchCapRefined: string;
    { a batch item's own type, which the axis breaks' handler reads in
      place of the action's (FBreakActAsSet: it is set) }
    FBreakActAs: string;
    FBreakActAsSet: Boolean;
    FBatchCapList, FBatchCapRef: TTyStringArray;
    FBatchDefer: Integer;
    FBatchDue, FBatchDueHas: Boolean;
    FBatchDuePayload: TTyAnimOverride;
    { [F4b] the brushSelect a batch's items asked for: one, the last state's
      (the update runs once); and whether the update after them gave one }
    FBatchBrushJson: string;
    FBatchBrushHas, FBatchBrushQueued: Boolean;
    { [R2-E] an item's timeline merge (TlMerge): the render it would have
      run now waits for the batch's end, once }
    FBatchConvertDue: Boolean;
    { [F4b] a view action (graphRoam, sankeyRoam, dragNode) running as an
      action: the roam helpers leave the event and `updated` to it }
    FViewActionDepth: Integer;
    { [F4b] zrender's dirty flag: something asked for a repaint since the
      last flush (a paint emits `rendered` only then); the tooltip's and
      the pointer's state as the last paint drew it (their actions ask for a
      repaint only when it changed); the paint's start on the chart's clock }
    FZrDirty: Boolean;
    FTipPaintedKey: string;
    FPaintT0: Double;
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
    { THE PAUSE [F3b]: a driver with no clips that is paused and resumed
      with the chart's -- a driver made later takes its pause from it }
    FPauseClock: TTyAnimation;
    { LineView's init branch, per line view of the last render [F3b]:
      'viewKey #1 step/polar|init' -- rolled once per render, at the first
      list built after a relayout }
    FLineHist: TStringList;
    FLineHistDue: Boolean;
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
    { WHAT A SUNBURST'S DATA STILL NAMES [milestone D5-D8]: each row's
      piece as the last render that drew it left it -- a drill removes the
      pieces outside the view from the group, but the data keeps them
      (getItemGraphicEl), so a universal transition after the drill morphs
      from them. Kept while the option's data lives; a new option's
      snapshot hands the ones the last render did not draw to
      FAnimPrev.UtStale. }
    FUtStale: array of TTyChartElement;
    FAnimOldBuild: TTyChartBuild;
    FAnimOldBindings: TTySeriesBindingArray;
    FAnimOldViewKeys: TTyStringArray;
    { the old option's universal transition, by series index: its typed
      key [Batch 136], a list's items, its divideShape and its items'
      groups [Batch 137] }
    FAnimOldUtKeys: TTyUtSeriesKeysArray;
    { A FULL UPDATE OF THE SAME OPTION waiting for its arming -- a legend
      toggle, a dataZoom -- and the update payload's animation it renders
      with (a dataZoom from the inside roam or a realtime slider) [Batch 96] }
    FAnimFull: Boolean;
    FAnimPayload: TTyAnimOverride;
    FAnimHasPayload: Boolean;
    { AN ACTION RENDERED A LAZY setOption still waiting: armed with the
      action's render, not at the next paint [milestone D1-D4] }
    FAnimLazyTaken: Boolean;
    { [F3c] THE LAST setOption's `transition`, for the update it starts:
      handed to the old render's record when the update arms, read by a
      custom series' build (the series it names make their items anew) }
    FAnimUtHas: Boolean;
    FAnimUtTrans: TTyUtTransitionArray;
    { A MERGE setOption waiting for its arming [Batch 99, AN6]: the models it
      maps onto are the old ones, so are their views -- a series kept as a
      full update keeps it, the axes groupTransition, the markers update }
    FAnimMerge: Boolean;
    { [R2-C] a setOption since the render the waiting update starts from
      visited the series (notMerge, or a merge with `series` -- every
      option, through backwardCompat): their data, a tree's Tree, is new }
    FAnimDataFresh: Boolean;
    { THE AXIS VIEWS the update starts from, 'xAxis0=' + model id + #1 +
      subtype (prepareView's '_ec_' + id + '_' + type), read before the
      option changes; and the axes a replaceMerge made brand new since --
      both new views, which never transition [Batch 99] }
    FAnimOldAxisKeys, FAnimFreshAxes: TTyStringArray;
    { THE BAR RACE [Batch 135]: the views (series view key + #1 + 'bar')
      past their first frame -- BarView's _isFirstFrame false, its
      `rendered` listener on; the changeAxisOrder dispatches waiting for the
      render or the frame that made them (upstream's pending actions), each
      with the view whose init sort it is; the render being made for
      changeAxisOrder (1, 2 the init sort) and the one the next arming is
      for; a relayout of the paint path whose flush is still to be looked
      at; whether the queue is being run }
    FRtInit: TTyStringArray;
    FRtQueue, FRtQueueInit: TTyStringArray;
    FRtChange, FAnimRtChange: Integer;
    FRtAfterRelayout, FRtFlushing: Boolean;
    FRtLens: TTyDoubleArray;
    { THE AXES' groupTransition [Batch 96]: one proxy per leaf of an axis
      group, by 'xAxis0/anid', on the series' driver; made by a full update's
      arming, dropped with every other proxy }
    FAxisProxies: TFPHashList;
    FAxisList: TFPList;
    { THE SERIES WHOSE MODEL replaceMerge MADE BRAND NEW since the old keys
      were taken: upstream's __requireNewView, a new view whatever the id
      [Batch 97]. Consumed by the update that pairs the views. }
    FAnimFresh: array of Boolean;
    { A LAZY setOption's update waits for the next render, and its
      `updated` event with it [Batch 97] }
    FLazyPending, FLazySilent: Boolean;
    { a resize's update ran: its `updated` is due once the layout is done
      [milestone D5-D8] }
    FResizeDue: Boolean;
    FPaintList: TTyPaintList;
    { THE LABEL LAYOUT'S LIST as the last build left it: one item per label
      of a series with a labelLayout, in LabelManager's order, and the
      label's element index beside it [Batch 103] }
    FLmItems: TTyLabelLayoutItemArray;
    FLmEls: TTyIntegerArray;
    { beside each: its label line's element (-1 for none), and whether
      LabelManager routes that line again (needsUpdateLabelLine: an x or a y
      given, no labelLinePoints for it) [Batch 112] }
    FLmGuides: TTyIntegerArray;
    FLmRoute: TTyBoolArray;
    { The PPI the list was built at. The hit test scales HitSlopLogical by it,
      so a list built for 96 and interrogated at 192 would give targets half
      the size the marks are drawn at. }
    FPaintListPPI: Integer;
    FPaintListValid: Boolean;
    { ---- export and loading [Batch 106] ----
      AN EXPORT IS A RENDER WITH THREE THINGS SWITCHED: FExporting draws the
      finished picture (no animation frame, no proxy, no hover), FExportBare
      leaves the skin's frame out for a background the options chose, and
      FExportExclude hides the views excludeComponents names. FViewsDrawn is
      what the last full render drew, by view. }
    FExporting: Boolean;
    FExportBare: Boolean;
    FExportExclude: TTyChartViews;
    FViewsDrawn: TTyChartViews;
    { THE LOADING EFFECT: shown or not, its cfg, and the spinner -- an arc
      element on a driver of its own (the axis pointer's way), so a loading
      chart never takes its series out of the static layer. FLoadGeo is the
      geometry the last paint used, CSS px. }
    FLoadShown: Boolean;
    FLoadCfg: TTyLoadingCfg;
    FLoadAnim: TTyAnimation;
    FLoadArc: TTyAnimBag;
    FLoadGeo: TTyLoadingGeometry;
    FLoadGeoValid: Boolean;
    function ViewHidden(AView: TTyChartView): Boolean;
    procedure ViewDrew(AView: TTyChartView);
    function LoadLive: Boolean;
    procedure LoadDrop;
    procedure PaintLoading(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer);
    procedure ExportOptsOrRaise(const AJson: string; out AOpts: TTyChartExportOpts);
    function RenderExport(const AOpts: TTyChartExportOpts): TBGRABitmap;
    procedure WriteExport(AStream: TStream; ABmp: TBGRABitmap;
      AType: TTyExportImageType);
    procedure SetOptionText(const AValue: string);
    function GetOptionText: string;
    { ---- setOption [Batch 95] ---- }
    { the notMerge setOption: the text is the option, every model is new }
    procedure ApplyNotMerge(const AValue: string); overload;
    { the same, the media merged after the init in AReplace's replaceMerge
      [Batch 107] }
    procedure ApplyNotMerge(const AValue: string; const AReplace: array of string); overload;
    { the merge setOption, AReplace's main types in replaceMerge mode }
    function DoMerge(const AJson: string; const AReplace: array of string): Boolean;
  private
    { ---- media [Batch 107] ---- }
    { the merges of one setOption or one resize: the views the old render
      had (read before the first), whether the first is still to come, and
      whether a resize does them -- which snaps, as upstream's resize update
      runs with duration 0 }
    FMergeOldKeys, FMergeOldAxes: TTyStringArray;
    FMergeOldUtKeys: TTyUtSeriesKeysArray;
    FMergeFirst, FMergeResize: Boolean;
    { the size the media queries are asked about: the client area in CSS px
      (logical px at the font's PPI) }
    procedure MediaViewSize;
    { after each merge of a merge setOption or a resize: what DoMerge did
      with its one report }
    procedure MergePass(const AReport: TTyMergeReport);
    { after each media merge of a notMerge: a brand new series asks for a
      new view }
    procedure NotMergePass(const AReport: TTyMergeReport);
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
    { [R2-C] the map views the last build drew, and (ANew) the model each
      one's transform group tweens on }
    function AnimGeoViews(ANew: Boolean): TTyChartGeoViewArray;
    { ---- the states on the proxies [Batch 94, AN3b] ---- }
    { after the build and its arming: every state element's proxy found or
      made, seeded with the rest values, given the series' stateTransition,
      a full update's previous list put back at once, then the element's
      list applied -- with a transition where upstream's would make one }
    procedure StAnimSync;
    procedure StAnimEl(var AEl: TTyStElement; AListIdx, ASeries, ARaw: Integer;
      const AName: string; AKind: Integer; const ACfg: TTyAnimCfg;
      AHasCfg: Boolean);
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
    { the series' universal transition keys now, as FAnimOldUtKeys keeps
      them [Batch 136, 137] }
    function AnimUtKeys: TTyUtSeriesKeysArray;
    { [F3c] the pending transition option's `to` names series ASeries
      (series:beforeupdate's __universalTransitionEnabled) }
    function AnimUtNamed(ASeries: Integer): Boolean;
    { the axis views of the option now: 'xAxis0=' + id + #1 + subtype [Batch 99] }
    function AxisViewKeys: TTyStringArray;
    { the view of every series model now, shown or not: view key + #1 + type
      [Batch 99] }
    function AnimAliveKeys: TTyStringArray;
    { each view row's DataDiffer key and raw index }
    { [F3d] a graph's edge rows' DataDiffer keys }
    function AnimGraphEdgeKeys(ASlot: Integer): TTyStringArray;
    procedure AnimRowKeys(AStore: TTyDataStore; out AKeys: TTyStringArray;
      out ARaws: TTyIntegerArray);
    { A FULL UPDATE ANIMATES [Batch 96]: before its layout, the render it
      starts from is kept as a new option's is (and the payload noted);
      after its list is built, armed at once where the chart may animate --
      the clips first step on the next frame, as an action does not flush --
      or left for a window's paint }
    procedure AnimFullBegin(const APayload: TTyAnimOverride; AHasPayload: Boolean);
    procedure AnimFullEnd;
    { ---- the axes' groupTransition [Batch 96] ---- }
    procedure AxisAnimDrop;
    { every leaf of every cartesian axis of a build, as AnimAxis makes them,
      AKeys their proxy keys }
    function AxisAnimElementsOf(ABuild: TTyChartBuild; APPI: Integer;
      out AKeys: TTyStringArray; out AAxisKeys: TTyStringArray): TTyAxisAnimElArray;
    { the new build's leaves as proxies: a leaf an old one matched starts
      where that one is -- its proxy's value while it moves -- and tweens at
      update timing on its axis' model, no data index; the rest stand }
    procedure AxisAnimArm(AOldBuild, ANewBuild: TTyChartBuild);
    function AxisProxyOf(const AKey: string): TTyChartAnimProxy;
    { while the series move, axes with proxies are drawn in the dynamic
      layer from them }
    function AxesDynamic: Boolean;
    procedure PaintAxes(APainter: TTyPainter; APPI: Integer;
      const AMeasurer: ITyTextMeasurer; AProxied: Boolean);
    { the list and keys of the render an update starts from }
    procedure AnimSnapshot;
    procedure AnimDropPrev;
    procedure UtStaleHarvest;
    function AnimToOldPoint(AOldSeries: Integer; AX, AY: Double): TTyPointF;
    procedure AnimArmTimer;
    procedure AnimTimerFired(Sender: TObject);
    procedure AnimTickBody(ANowMs: Double);
    { a driver that takes the chart's pause [F3b] }
    function NewAnimDriver: TTyAnimation;
    { the line views of the list just built: whether each took LineView's
      init branch -- no view of its key in the render before, or one of
      another step or coordinate system [F3b] }
    procedure LineHistRoll;
    function LineHistInit(const AViewKey: string): Boolean;
    { every driver of the chart, the nil ones left out }
    function AnimDrivers: TFPList;
    { a flush while paused steps every driver, as upstream's one animation
      steps every clip [F3b] }
    procedure AnimFlushOthers(AOwn: TTyAnimation);
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
    { the shadow of AHit as it is drawn now: its proxy's rect while that
      moves, the shape upstream builds otherwise [Batch 101] }
    function PtrShadowNow(const AHit: TTyAxisHit; out AShape: TTyXYWH): Boolean;
    function PtrLive: Boolean;
    { the frame's continuous part (AContinuous) or the rest }
    function AnimPart(AContinuous: Boolean): TTyPaintList;
    procedure SetAnimMode(AValue: TTyChartAnimationMode);
    function GetErrorText: string;
    procedure FreeStores;
    procedure DropBuild;
    { [R2-I6] THE PARSED STORE KEPT between builds of one tree. A series'
      store is a function of the tree (FOption.Generation), the recipe its
      branch fills it by (StoreKeepSig) and the category lists of the axes
      it borrows -- their content now, and, for a collecting one, what it
      held before this series' fill. Take: all of it as when the store was
      kept -- the collecting lists get the categories the fill appended, in
      its order, and FStores[ASlot] becomes a copy of the kept store on the
      new axes' lists (True); else nothing changes (False). Put: keep a copy
      of the store just filled (APre: each borrowed list's count before the
      fill). Begin / End: the build's bracket (an entry no slot used goes). }
    function StoreKeepSig(ASlot, ABranch, ADs: Integer; const ADims: TTySeriesDimArray;
      const AEnc: TTySeriesEncode): string;
    procedure StoreKeepPre(const ADims: TTySeriesDimArray; out APre: TTyIntegerArray);
    function StoreKeepTake(ASlot: Integer; const ASig: string;
      const ADims: TTySeriesDimArray): Boolean;
    procedure StoreKeepPut(ASlot: Integer; const ASig: string;
      const ADims: TTySeriesDimArray; const APre: TTyIntegerArray);
    procedure StoreKeepBegin;
    procedure StoreKeepEnd;
    procedure StoreKeepDrop;
    { Option to axes, series and stores. Cheap enough to redo on a resize; the
      expensive half is the label measuring in Relayout. }
    procedure Rebuild;
    { [F6a] the bodies of Rebuild, Paint, RenderTo and RenderToBitmap: each
      public entry opens the image scope -- an `image://name/i` looks for
      `name` on this chart's Owner (AdvanceChart.Images) -- around its body }
    procedure RebuildBody;
    procedure PaintBody;
    procedure RenderToBody(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function RenderToBitmapBody(const AOptsJson: string): TBGRABitmap;
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
      const AMeasurer: ITyTextMeasurer; ABelow: Boolean; AProxied: Boolean = False);
    { THE BREAK AREAS [Batch 132]: over the series (zigzagZ, 100 by default),
      each break's polylines and the polygon between them }
    procedure PaintBreakAreas(APainter: TTyPainter);
    { the break area under (AX, AY) whose click expands it: the axis (grid
      times a thousand plus its place in the grid) and the area }
    function BreakAreaAt(AX, AY: Integer; out AAxisKey, AArea: Integer): Boolean;
    { the axis a break target names }
    function BreakAxisOf(AAxisKey: Integer; out AGrid: TTyGridBuild): TTyAxis;
    { the click on a break area: its break }
    procedure BreakAreaClickAt(AAxisKey, AArea: Integer);
    { the click on a break area or a break label: expandAxisBreak }
    procedure BreakExpandClick(AAxisKey, ABreakIndex: Integer);
    { expandAxisBreak / collapseAxisBreak / toggleAxisBreak: the axes the
      payload names take the new state into their option, the chart
      updates, and axisbreakchanged follows [Batch 132] }
    procedure DoAxisBreakAction(APayload: TJSONObject);
    { ---- the bar race (realtimeSort) [Batch 135] ---- }
    { shouldRealtimeSort: a bar series with realtimeSort, on a category base
      axis of a cartesian2d }
    function RtSortOf(ASlot: Integer): Boolean;
    function RtKeyOf(ASlot: Integer; const AViewKeys: TTyStringArray): string;
    { Grid.update: every category axis takes its model's categorySortInfo }
    procedure RtApplySortInfos;
    { the render's _enableRealtimeSort on a first frame: the init sort,
      queued }
    procedure RtRenderPass;
    { the `rendered` listeners: _updateSortWithinSameData of every racing
      view past its first frame, queued }
    procedure RtRendered;
    { flushPendingActions: the queue dispatched in order }
    procedure RtFlushQueue;
    { the changeAxisOrder action: categorySortInfo on the axes it queries,
      the update, the event }
    procedure DoChangeAxisOrder(APayload: TJSONObject);
    function RtCompare(A, B: Integer): Integer;
    function AxisByTick(AAxis: TTyAxis): TTyIntegerArray;
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
    function DzAxis(const ADim: string; AIndex: Integer): TTyAxis;
    { series.sampling over every cartesian2d line and bar [Batch 102] }
    procedure SolveSampling;
    function WeakKeep(ARawIndex: Integer): Boolean;
    procedure SolveVisualMapViews(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    function VisualMapInk(const AView: TTyVmViewSpec): TTyVisualMapInk;
    function VisualMapContent(const AView: TTyVmViewSpec): TTyVisualColor;
    function BuildVisualMaps(AList: TTyPaintList): Integer;
    { [R2-L] the components a list ends with, from the visual maps on --
      what a build adds after the legends -- and where they start in it
      (-1: a list with none built) }
    function BuildListTail(AList: TTyPaintList; const AMeasurer: ITyTextMeasurer): Integer;
    { [R2-L] those components built again in the list as it stands -- a
      visual map's indicator moved, which nothing before them reads --
      instead of the whole list; False where it cannot be (then the list
      is built whole) }
    function ListTailRebuild: Boolean;
    procedure ListTailRefresh;
    { ---- the visualMap models' visuals [R3-B] ---- }
    procedure VmModelsClear;
    { a fresh option's base: every model made and completed }
    procedure VmModelsInitAll;
    { a merge's report: new models made, merged ones merged into, every
      visited one completed again (optionUpdated) }
    procedure VmModelsPass(const AReport: TTyMergeReport);
    function VmModel(AIndex: Integer): TJSONObject;
    { the ramp and the inactive colour SolveVisualMaps reads them with }
    procedure VmThemeDefaults(AIndex: Integer; out ARamp: TTyVisualColorArray;
      out AInactive: TTyVisualColor);
    { ---- visualMap interaction [Batch 116] ---- }
    procedure VmEnsure(ACount: Integer);
    function VmKeepNow(AIndex: Integer): Boolean;
    procedure VmBuilt(AIndex: Integer);
    procedure VmDispose(AIndex: Integer);
    procedure VmDisposeAll;
    function VmContinuous(AIndex: Integer): Boolean;
    function VmScale: Double;
    function VmGroupX(AIndex: Integer): Double;
    function VmGroupY(AIndex: Integer): Double;
    function VmHitAt(AX, AY: Integer; out AIndex, APart: Integer): Boolean;
    function VmRoleOf(AIndex, APart: Integer): string;
    function VmTargetSeries(AIndex: Integer): TTyIntegerArray;
    function VmSeriesValues(AIndex, ASeries: Integer; out AStore: TTyDataStore;
      out AValues: TTyDoubleArray; out ATexts: TTyStringArray): Boolean;
    function VmFindRange(AIndex: Integer; ALo, AHi: Double): TTyVmHoverBatches;
    function VmFindPiece(AIndex, APiece: Integer): TTyVmHoverBatches;
    procedure VmDispatchHighDown(const AType: string; AIndex: Integer;
      const ABatches: TTyVmHoverBatches);
    procedure VmShowIndicator(AIndex: Integer; ACursor, AText: Double;
      const APrefix: string);
    procedure VmHideIndicator(AIndex: Integer);
    procedure VmClearHoverLink(AIndex: Integer);
    procedure VmDoHoverLink(AIndex: Integer; ACursor: Double; AOnBar: Boolean);
    procedure VmUpdateView(AIndex: Integer);
    procedure VmDragHandle(AIndex, AHandle: Integer; AIsEnd: Boolean; ADX, ADY: Double);
    { [F5] the same drag by a delta along the bar (its own units) }
    procedure VmDragHandleBar(AIndex, AHandle: Integer; AIsEnd: Boolean; AVy: Double);
    function VmDragStart(AX, AY: Integer): Boolean;
    procedure VmDragMove(AX, AY: Integer);
    procedure VmDragEnd;
    procedure VmElementEvent(const AType: string; const ATarget: TTyChartEventTarget;
      AX, AY: Integer);
    procedure VmZrMouseOut;
    procedure VmZrMouseOver(const ATarget: TTyChartEventTarget);
    procedure VmApplyStates;
    procedure VmPieceClick(AIndex, APiece: Integer);
    function VmSelectedMap(AIndex: Integer): TJSONObject;
    procedure VmSelectRange(AIndex: Integer; const APayloadFrom: string;
      ASel: TJSONData);
    procedure DoSelectDataRange(APayload: TJSONObject);
    procedure DoHighDownBatch(APayload: TJSONObject);
    function VmLive_: Boolean;
    function VmLiveDraw(AIndex: Integer): TTyVmLiveDraw;
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
    procedure DzRunSliderAction(AIndex: Integer; ADeferred, ARealtime: Boolean);
    function DzRoam(AGrid: Integer; const AKind: string; AShift: TShiftState;
      AOldX, AOldY, ANewX, ANewY, AScale, AScroll: Double): Boolean;
    procedure DzRoamDispatch(AGrid: Integer; const AItems: TTyDzActionItemArray);
    { AJson: the payload a dispatched dataZoom action carried (its event,
      its animation; the caller publishes `updated`); nil for the port's own
      dispatches, whose payload is built as upstream's views build it
      [Batch 141] }
    procedure DzDispatch(const AAction: TTyDzAction; AJson: TJSONObject = nil);
    procedure DzViewUpdate;
    function DzStateKey: string;
    procedure DzSyncLayout(const APayload: TTyAnimOverride; AHasPayload: Boolean);
    { [F6a] the cursor the pointer's position asks for: the hovered
      element's own (zrender's Handler), then the roam controllers' grab /
      grabbing, then the brush's -- applied to the control's Cursor }
    function TargetCursor(const ATarget: TTyChartEventTarget): string;
    function VmCursor(AIndex, APart: Integer): string;
    function DzGrabAt(AX, AY: Integer): Boolean;
    function AnyPanRoam: Boolean;
    function RoamGrabAt(AX, AY: Integer): Boolean;
    { [R2-E] the RoamController that has the last word on a release: -1
      none that pans, 0 the point outside its area, 1 inside }
    function RoamReleaseArea(AX, AY: Integer): Integer;
    procedure CursorAfterMove(AX, AY: Integer);
    procedure CursorAfterUp(AX, AY: Integer);
    procedure ApplyCursorName(const AName: string);
    procedure DzArmTimer;
    procedure DzTimerFired(Sender: TObject);
    function DataZoomInk(const ASpec: TTyDzSliderSpec): TTyDzInk;
    function DataZoomInput(AIndex: Integer; out AIn: TTyDzSliderInput): Boolean;
    function BuildDataZooms(AList: TTyPaintList): Integer;
    { the toolbox [Batch 125] }
    function TbTitles: TTyTbTitles;
    function TbScale: Double;
    function TbInk: TTyTbInk;
    function TbStatusOf(ATb: Integer): TStringList;
    procedure TbSetStatus(ATb: Integer; const AFeature, AIcon, AState: string);
    function TbStatusIs(ATb: Integer; const AFeature, AIcon: string): Boolean;
    function TbHasFeature(ATb: Integer; const AName: string): Boolean;
    procedure SolveToolboxes(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    procedure TbIconOrigin(ATb, AIcon: Integer; out AX, AY: Double);
    function TbEmphasised(ATb, AIcon: Integer): Boolean;
    function BuildToolboxes(AList: TTyPaintList; const AMeasurer: ITyTextMeasurer): Integer;
    function TbHitAt(AX, AY: Integer; out ATb, AIcon: Integer): Boolean;
    { ---- the timeline [Batch 129] ---- }
    function TlInk: TTyTimelineInk;
    function TlClock: Double;
    function TlLive: Boolean;
    function TlNode: TJSONObject;
    function TlCurrentIndex: Double;
    function TlAnimCfg: TTyTlAnimCfg;
    procedure SolveTimeline(APPI: Integer);
    function BuildTimeline(AList: TTyPaintList): Integer;
    function TlHitAt(AX, AY: Integer; out AEl: Integer): Boolean;
    procedure TlArmTimer;
    procedure TlTimerFired(Sender: TObject);
    procedure TlChange(AIndex: Double; AHasIndex: Boolean);
    procedure TlClick(AEl: Integer);
    procedure TlMouseOver(const ATarget: TTyChartEventTarget);
    procedure TlMouseOut(const ATarget: TTyChartEventTarget);
    procedure TlApplyStates;
    procedure TlDragStart(const ATarget: TTyChartEventTarget);
    procedure TlPointerChange(AX, AY: Integer; ATrigger: Boolean);
    procedure TlDragMove(AX, AY: Integer);
    procedure TlDragEnd(AX, AY: Integer);
    procedure TlMerge;
    procedure DoTimelineChange(APayload: TJSONObject);
    procedure DoTimelinePlayChange(APayload: TJSONObject);
    procedure TbChanged;
    procedure TbMouseOver(const ATarget: TTyChartEventTarget);
    procedure TbMouseOut(const ATarget: TTyChartEventTarget);
    procedure TbClick(ATb, AIcon: Integer);
    procedure TbDoRestore(APayload: TJSONObject);
    function TbMagicSeries: TTyMagicSeriesArray;
    procedure TbMagicType(ATb: Integer; const AType: string);
    procedure TbDoMagic(APayload: TJSONObject);
    function TbDataViewContent(out AMeta: TTyDvMetaArray): string;
    function TbDvFind(const AName: string; out AData: TJSONData): Boolean;
    procedure TbDataView(ATb: Integer);
    procedure TbDoDataView(APayload: TJSONObject);
    procedure TbSaveAsImage(ATb: Integer);
    procedure TbDoTakeCursor(APayload: TJSONObject);
    function TbSelIndexOf(const AKey: string): Integer;
    procedure TbSelPut(const AKey: string; AIsValue: Boolean; A, B: Double);
    procedure TbDispatchZoom(const ASnap: TTyTbSnapshot);
    procedure TbBack;
    { the select brush's controller [Batch 127] }
    procedure TbZoomCtlSync;
    procedure TbCtlDown(AX, AY: Integer; ADraggable: Boolean);
    procedure TbCtlMove(AX, AY: Integer);
    procedure TbCtlUp(AX, AY: Integer);
    procedure TbCtlTrigger(const ATrig: TTyBrushTrigger);
    procedure TbBrushEnd;
    { the brush feature [Batch 127] }
    procedure TbBrushModelState(out AHas, AMulti, ABrushed: Boolean; out AType: TTyBrushType);
    procedure TbBrushSnap;
    procedure TbBrushRender(ATb: Integer);
    procedure TbBrushClick(const AIcon: string);
    procedure TbApplyCursor(AX, AY: Integer);
    procedure TbFrame;
    { [R2-E] the icons' pending emphasis entered or left: True when any }
    function TbFrameApply: Boolean;
    { the brush components [Batch 126] }
    function BrushViewOf: TTyBrushView;
    procedure BrushCss(AX, AY: Double; out X, Y: Double);
    procedure BrushSync;
    procedure BrushReset;
    function BrushTargets(ABrush: Integer): TTyBrushTargetArray;
    function BrushFindTarget(const ATargets: TTyBrushTargetArray;
      const AArea: TTyBrushArea): Integer;
    procedure BrushLayout(ABrush: Integer);
    procedure BrushRender(ABrush: Integer; ARepaint: Boolean = True);
    procedure BrushPass;
    function BrushOutput(ABrush: Integer; const AAreas: TTyBrushAreaArray): TTyBrushAreaArray;
    procedure BrushOnTrigger(ABrush: Integer; const ATrig: TTyBrushTrigger);
    procedure BrushApplyOwn(ABrush: Integer; const AAreas: TTyBrushAreaArray);
    function BrushQuery(APayload: TJSONObject): TTyIntegerArray;
    procedure BrushDoAction(APayload: TJSONObject);
    procedure BrushDoEnd(APayload: TJSONObject);
    procedure BrushTakeCursor(APayload: TJSONObject);
    procedure BrushLogEvent(const AType: string; ABrush: Integer; AFromSelf: Boolean;
      const AAreas: TTyBrushAreaArray; const APayload: string);
    function BrushClock: Double;
    procedure BrushVisual(const ABatch: TTyBrushSelectBatch);
    procedure BrushExecSelect(const ABatch: TTyBrushSelectBatch; ATime: Double);
    procedure BrushDropPending(AId: Integer);
    procedure BrushArmTimer;
    procedure BrushTimerFired(Sender: TObject);
    function BrushPieceAt(AX, AY: Integer; out ABrush, AIndex: Integer;
      out APiece: TTyBrushPiece): Boolean;
    function BrushDragStart(AX, AY: Integer): Boolean;
    procedure BrushCtlDown(AX, AY: Integer; ADraggable: Boolean);
    procedure BrushPointerMove(AX, AY: Integer);
    procedure BrushDragEnd;
    procedure BrushCtlUp(AX, AY: Integer);
    function BrushCrosshair(AX, AY: Integer): Boolean;
    procedure BrushChanged;
    function BuildBrushes(AList: TTyPaintList): Integer;
    { the selection, the globalPan mutex, onIrrelevantElement [Batch 127] }
    procedure BrushEnableCtl(ACtl: TTyBrushController; const AOpt: TTyBrushOpt; AAuto: Boolean);
    procedure BrushFreeCtl(var ACtl: TTyBrushController);
    function PanTaken: Boolean;
    function BrushIrrelevant(const APanel: TTyBrushPanel; AX, AY: Double): Boolean;
    procedure BrushVisCapture;
    function BrushSelectCompute: TTyBrushSelectBatch;
    procedure BrushSelectRun(ADispatch: Boolean; ARepaint: Boolean = True);
    procedure BrushFlush;
    function BrushSelectedJson(const ABatch: TTyBrushSelectBatch): string;
    procedure BrushDoAxisAreaSelect(APayload: TJSONObject);
    { [Batch 140] the parallel axis expansion: the parallelAxisExpand
      action, ParallelView's mousedown / mouseup / mousemove, the window a
      pointer slides to, the throttle and its timer }
    procedure DoParallelAxisExpand(APayload: TJSONObject);
    procedure ParExpEnsure;
    procedure ParExpConfigure(AIndex: Integer);
    function ParExpSlideAt(AIndex: Integer; AX, AY: Double; out AW0, AW1: Double): TTyParallelSlide;
    procedure ParExpDown(AX, AY: Integer);
    procedure ParExpUp(AX, AY: Integer);
    procedure ParExpMove(AX, AY: Integer);
    procedure ParExpCall(AIndex: Integer; AHasArgs: Boolean; AW0, AW1: Double; AJump: Boolean);
    procedure ParExpDispatch(AIndex: Integer; AW0, AW1: Double; AAnim: Integer; ATime: Double);
    procedure ParExpSchedule(AIndex: Integer; ADue: Double; AHasArgs: Boolean;
      AW0, AW1: Double; AJump: Boolean);
    procedure ParExpDropPending(AId: Integer);
    function ParExpClock: Double;
    procedure ParExpArmTimer;
    procedure ParExpTimerFired(Sender: TObject);
    { [Batch 140] the thumbnails: a model's optionUpdated (_updateBridge),
      getTarget, the render (the copy and its view), the window after a
      roam, the copy of a graph, its elements in the list, a press and a
      wheel on its content }
    procedure ThumbOptionUpdated(AIndex: Integer);
    procedure ThumbInitAll;
    function ThumbResolveTarget(const AModel: TTyThumbModel): Integer;
    procedure ThumbRender;
    procedure ThumbUpdateWindows;
    function ThumbTargetMatrix(ASlot: Integer): TTyMat2D;
    function ThumbCopy(ASlot: Integer): TTyThumbItemArray;
    function BuildThumbnails(AList: TTyPaintList): Integer;
    procedure ThumbDown(AX, AY: Integer);
    function ThumbWheel(AX, AY, AWheelDelta: Integer): Boolean;
    { [Batch 130] the parallel axes' area select: a controller by its brush
      index (a brush component's, or TyParallelBrushBase plus a
      parallelAxis' index), its trigger routed; every axis view's
      _refreshBrushController; a view's _onBrush }
    function BrushCtlOf(AIndex: Integer): TTyBrushController;
    procedure BrushTriggerTo(AIndex: Integer; const ATrig: TTyBrushTrigger);
    procedure ParBrushPass;
    procedure ParBrushOnTrigger(AAxis: Integer; const ATrig: TTyBrushTrigger);
    procedure ParBrushFree;
    function BuildParallelBrushes(AList: TTyPaintList): Integer;
    { the dispatch of a payload already parsed (it is freed) }
    function DispatchActionObject(APayload: TJSONObject): Boolean;
    { ---- echarts.connect and batch actions [Batch 141] ---- }
    { enableConnect's listener: an event of the revert map, published by a
      chart of a connected group that is not itself pending, has every other
      chart of the group dispatch it as an action (escapeConnect stops it).
      AObj, when given, is the event as an object (its numbers exact). }
    procedure ConnectBroadcast(const AEventType, APayloadJson: string;
      AObj: TJSONObject);
    { a payload with a batch, for the types that take one: the legend's five,
      select / unselect / toggleSelect, dataZoom and brushSelect; False for
      any other type }
    function DoBatchAction(APayload: TJSONObject): Boolean;
    { [F4b] doDispatchAction's batch for every other action: each item over
      the payload through the action, the update once, one event }
    function DoBatchGeneric(APayload: TJSONObject; const AType: string): Boolean;
    { [F4b] zrender's `rendered` with its elapsedTime }
    procedure EmitRendered(AElapsed: Double);
    { [F4b] the tooltip's and the pointer's state, as a key; a repaint only
      when it changed since the last paint }
    function TipStateKey: string;
    procedure TipInvalidate;
    { [F4b] a repaint that marks zrender dirty only when the tooltip, the
      pointer or the states changed (the repaint itself as before) }
    procedure InvalidateFrameQuiet;
    procedure HoverInvalidate;
    { legendSelectActionHandler without the update: the event object it
      returns, its type set, as JSON; AEvent its type }
    function LegendActionApply(APayload: TJSONObject; const AType: string;
      out AEvent: string): string;
    { the select actions' updateDirectly, and their events after it: the
      action's own (AOwnEvent), selectchanged, the legacy ones }
    procedure SelApply(APayload: TJSONObject; const AType: string);
    procedure SelPublish(APayload: TJSONObject; const AOwnEvent: string);
    { the dataZoom action from a payload: its models by dataZoomIndex /
      dataZoomId / dataZoomName (none named is every one), setRawRange's
      window }
    function DzQuery(APayload: TJSONObject): TTyIntegerArray;
    procedure DzItemsOf(AItem: TJSONObject; var AAction: TTyDzAction);
    function DzModelId(AIndex: Integer): string;
    function DzPayloadOf(const AAction: TTyDzAction): TJSONObject;
    function DoDataZoomAction(APayload: TJSONObject): Boolean;
    { the chart's getBoundingClientRect: its ClientOrigin and size, logical }
    function ConnectedRect: TTyConnectedRect;
    procedure ApplyVisualMaps(var AVisual: TTySeriesVisual; ASlot,
      APPI: Integer);
    { The THEME's ramp at ASlot, with nothing of the option in it. Split out
      because a pie's slices and a chart's series both cycle it, and they
      index it by different things. }
    function ThemeRampColor(ASlot: Integer): TTyColor;
    { What `auto` means on this series: the palette's pick for it. }
    function SeriesPaletteColor(ASeriesIndex: Integer): TTyColor;
    { what a palette answer paints: the author's colour, the theme's slot, or
      nothing (an undefined pick) [Batch 105] }
    function PickColor(const APick: TTyPalettePick): TTyColor;
    { dataColorPaletteTask, after the filters [Batch 105] }
    procedure SolveDatumPalette;
    { the decal visuals: the style's, the item's, the aria palette's
      [Batch 131] }
    procedure SolveDecals;
    { the decal a slot's raw row is drawn with: its own, else the series' }
    function RowDecalOf(ASlot, ARaw: Integer): TTyChartDecal;
    { [F4a] the decal object a slot's raw row takes (api.visual('decal')),
      as JSON; nil for none }
    function RowDecalJson(ASlot, ARaw: Integer): TJSONData;
    { [F4a] every raw row's decal, by raw index }
    function RawRowDecals(ASlot: Integer): TTyChartDecalArray;
    { [R2-F] the ground of a decal's `empty*` symbols: the skin's
      TyAdvChartDecal background (upstream's neutral00) }
    function DecalGround: TTyChartColor;
    { [F4a] aria.decal on: the palette, else False }
    function AriaDecalPalette(out APal: TJSONData; out APalN: Integer): Boolean;
    { [F4a] a treemap's or a sunburst's node decals by row: the node's own
      itemStyle.decal, else the series'; with aria.decal on,
      enableAriaDecalForTree's -- every node the palette decal of its
      depth-1 ancestor's name, AOrder the tree's eachNode order }
    function TreeNodeDecals(ASlot: Integer; const AHier: TTyHierarchy;
      const AOrder: TTyIntegerArray): TTyChartDecalArray;
    { a legend item's decal: the legend's itemStyle.decal over the series' }
    function LegendDecalOf(ALegend: Integer; const AName: string;
      const ASeries: TTyChartDecal): TTyChartDecal;
    { ariaVisual's `ariaModel.get('enabled')`: the merged option's -- every
      option preprocessed, initBase's switch in the base [231b] }
    function AriaEnabled: Boolean;
    function GetAriaDescription: string;
    { the facts the description is made of, from the last layout: AAria's
      maxCount and excludeDimensionId (the defaults when it is nil), the
      first title, every series model counted, the series the legend kept
      with their rows [Batch 144: split out of GetAriaDescription] }
    procedure AriaGather(AAria: TJSONObject; out AFacts: TTyAriaFacts);
    { the accessible description: the aria description when the option
      writes `aria`, else the sentence the default templates make of the
      same facts -- a desktop control is always in the accessibility tree,
      where upstream's canvas is opaque until aria is switched on
      [Batch 144] }
    function AccessibleSummary: string;
    { ==== THE KEYBOARD [Batch 144] ==== }
    { the series the keyboard walks: those with a store the legend kept, in
      option order, with their view's row count }
    function KbSeriesList: TTyKbSeriesArray;
    { whether (FKbSeries, FKbRow) still names a row of a walked series }
    function KbValid: Boolean;
    function KbRawOf(ASeries, ARow: Integer; AEdge: Boolean = False): Integer;
    { the list the item's element is read from: the frame in motion, the
      display list at rest (the hit test's choice) }
    function KbList: TTyPaintList;
    { the item's own element in the display list -- its state host, else the
      first unlabelled, hittable element carrying its datum; -1 for none }
    function KbElementOf(ASeries, ARow: Integer; AEdge: Boolean = False): Integer;
    { the focus item moves to (ASeries, ARow): downplay the old, highlight
      the new -- the actions, so their events fire -- then its tooltip }
    procedure KbGo(ASeries, ARow: Integer; AEdge: Boolean = False);
    { the keyboard lets go: downplay (ADownplay), hide its tooltip }
    procedure KbRelease(ADownplay: Boolean);
    { upstream's showTip for the item, at its element's centre }
    procedure KbShowTip;
    procedure KbHideTip;
    { Enter / Space: the click's select or unselect, when the series has a
      selectedMode; False when nothing was dispatched }
    function KbActivate: Boolean;
    procedure PaintKbRing(APainter: TTyPainter);
    { ==== [F5] THE COMPONENT KEYBOARD ==== }
    { [R2-G] whose edges the data-item keys walk: 1 a graph's, 2 a sankey's,
      3 a chord's; 0 none }
    function KbEdgeKind(ASlot: Integer): Integer;
    { a graph's edges that survive the legend (Graph.update's filterSelf);
      [R2-G] a sankey's links, a chord's kept ribbons }
    function KbEdgeCount(ASlot: Integer): Integer;
    { an edge row's place in the solved edge list; -1 for none }
    function KbEdgeOf(ASeries, ARow: Integer): Integer;
    { the stops the chart has now, in Tab order (KeyNav) }
    function KbStops: TTyKbStopArray;
    { the current stop's place in AStops: FKbStop when it is one of them,
      else the items' stop, else the first; -1 for no stops }
    function KbCurPos(const AStops: TTyKbStopArray): Integer;
    { how many parts a component stop has (the walk over them) }
    function KbPartCount(const AStop: TTyKbStop): Integer;
    { the markers the display list holds, in host-series, kind and data
      order: each one's host series, kind (Ord of TTyChartTargetKind), data
      index and element }
    function KbMarkerList(out ASeries, AKinds, AIndex, AEls: TTyIntegerArray): Integer;
    { the display list as the next paint will have it: a layout that is due
      made, a list a state change dropped built again -- what a key reads
      between two paints (an action's update, a hover's) }
    function KbListReady: Boolean;
    { a geo's named regions (group indices) }
    function KbGeoRegions(AGeo: Integer): TTyIntegerArray;
    { a piecewise visualMap's pieces in drawn order }
    function KbVmPieces(AIndex: Integer): TTyIntegerArray;
    { a legend's item (APart below the item count) or selector button, as
      EventTargetAt finds it }
    function KbLegendTarget(ALegend, APart: Integer): TTyChartEventTarget;
    function KbLegendVisible(ALegend, AItem: Integer): Boolean;
    function KbIsSlider(AIndex: Integer): Boolean;
    function KbIsInside(AIndex: Integer): Boolean;
    function KbVmHandles(AIndex: Integer): Boolean;
    { the tooltip of an element, as TooltipView._tryShow on it at its
      centre with the box below (manuallyShowTip's target path) }
    procedure KbTipAtElement(AEl: Integer);
    { take up the part APart of FKbStop: what a pointer over it does (a
      legend item's highlight, a thumb's emphasis, a toolbox icon's title,
      a slider's labels, a marker's lift and tooltip, a region's highlight
      and tooltip); the stop is on }
    procedure KbStopTake(APart: Integer);
    { let go of the part: what the pointer leaving it does }
    procedure KbStopLeave;
    { Tab or the platform landing on AStop }
    procedure KbSwitchStop(const AStop: TTyKbStop; APart: Integer);
    { a key on a component stop; True when the chart took it }
    function KbComponentKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure KbDataZoomKey(AIndex: Integer; ACmd: TTyKbCommand);
    procedure KbVisualMapKey(AIndex, AHandle: Integer; ACmd: TTyKbCommand);
    procedure KbTimelineKey(ACmd: TTyKbCommand);
    { the part's ring, device px; False for nothing to ring }
    function KbPartRect(const AStop: TTyKbStop; APart: Integer; out R: TTyRectF): Boolean;
    { the accessible tree's component nodes [F5] }
    function AccPlan: TTyAccPlan;
    function KbEdgeName(ASlot, AEdge: Integer): string;
    function KbMarkerName(ASeries, AKind, AIndex: Integer): string;
    function AccessibleEdgeItem(ASeriesIndex, ARow: Integer): TLazAccessibleObject;
    function AccValueOf(const AStop: TTyKbStop; APart: Integer): string;
    procedure AccRefreshValues;
    function AccCompIndexOf(AObj: TLazAccessibleObject): Integer;
    procedure KbNotifyFocus;
    function AccItemIndexOf(AObj: TLazAccessibleObject): Integer;
    { the JSON item of a series' own `data` at a raw row, nil when the data
      came from elsewhere or the item is no object }
    function RawItemNode(ASlot, ARaw: Integer): TJSONObject;
    { the array RawItemNode reads its items from, nil where it reads none:
      a loop over every row asks for it once [R2-L] }
    function RawItemArray(ASlot: Integer): TJSONArray;
    { a row's own colour object -- a gradient or a pattern in the item's
      itemStyle.color -- for the row fills a renderer reads [Batch 105] }
    function RowObjectFill(ASlot, ARaw: Integer; out AColor: TTyOptColor): Boolean;
    { the row fills a series' renderer reads: palette picks and object
      colours, by raw row [Batch 105] }
    function SeriesRowFills(ASlot: Integer): TTyRowFillArray;
    { a per-datum renderer's object fill for a raw row: the datum's own
      gradient or pattern, else the series' -- unless a visual channel, a
      string colour of the datum's own or the per-datum palette coloured the
      row [Batch 105] }
    function DatumObjectFill(ASlot, ARaw: Integer): TTyChartObjFill;
    { the series' own fill as an object, `auto` aside [Batch 105] }
    function SeriesObjectFill(ASlot: Integer): TTyChartObjFill;
    { What the author wrote on this series' style blocks, laid over the
      palette colour the visual already carries. }
    procedure ApplyOptStyle(var AVisual: TTySeriesVisual; ASlot: Integer);
    function SeriesColor(ASeriesIndex: Integer): TTyColor;
    { The stack record for a series slot, or an unstacked one. }
    function StackFor(ASlot: Integer): TTySeriesStack;
    { The symbol spec for a series slot, over its type's own default. }
    function SymbolFor(ASlot: Integer): TTySymbolSpec;
    { whether this series draws as one batch: preparePipelineContext's
      `large` against the count after the dataZoom filter, on a cartesian
      only [Batch 117] }
    function LargeKindOf(ASlot: Integer): TTyLargeKind;
    { ---- progressive rendering and appendData [Batch 119] ---- }
    function ProgOnOf(ASlot: Integer): Boolean;
    function ProgCtxOf(ASlot: Integer): TTyProgRun;
    procedure ProgUpdate;
    procedure ProgStage;
    procedure ProgStep;
    function ProgAnyUnfinished: Boolean;
    procedure ProgTag(AList: TTyPaintList);
    procedure ProgApplyVisibility(AList: TTyPaintList);
    function ProgClock: Double;
    function ProgIdle: Boolean;
    function ProgLive: Boolean;
    function ProgFrame(AEmit: Boolean): Boolean;
    procedure FrozenCapture;
    function FrozenZooms: TTyAxisZoomArray;
    procedure EmitPlain(const AType: string);
    procedure EmitFlush;
    function ProgIsLayered(const AEl: TTyChartElement): Boolean;
    procedure ProgLayerBuild(AW, AH, APPI, AScale: Integer);
    procedure ProgLayerDelta;
    procedure ProgRenderList(APainter: TTyPainter; AList: TTyPaintList; APPI: Integer);
    { [R2-L] the paint-order position the incremental layer is blitted at:
      the first shown element of a run, -1 for none }
    function ProgBlitPos: Integer;
    { [R2-L] a progress frame's static layer from the last full paint's, on
      FStatic's canvas; False where it cannot be (then the full paint runs) }
    function ProgFastPaint(const R: TRect; APPI: Integer; const AScale: TTyCanvasScale): Boolean;
    procedure ProgFastDrop;
    { [R2-L] the layer drawn again inside the box a state patch changed }
    procedure ProgLayerRegionRedraw;
    { [R2-L] after a state patch: the box its writes changed on the layer,
      against what the last patch had written (AIdx / AEls) -- False where
      the layer must be drawn whole }
    function ProgPatchRegion(const AIdx: TTyIntegerArray;
      const AEls: array of TTyChartElement): Boolean;
    { the row a large element's own handler gives the pointer: the batch's
      scan, -1 for none (a candle's path has no data) }
    function LargeRowAt(AElement, AX, AY: Integer): Integer;
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
    procedure BuildMatrices;
    procedure SolveMatrices(APPI: Integer);
    procedure FreeMatrices;
    function MatrixInk: TTyMatrixInk;
    { the geo components [Batch 146] }
    procedure SolveGeos(APPI: Integer);
    procedure FreeGeos;
    function GeoInk: TTyGeoInk;
    { [Batch 148] the regions as things a pointer and an action reach }
    procedure FreeGeoSel;
    function GeoSelMap(AIndex: Integer): TJSONObject;
    function GeoIsSelected(AIndex: Integer; const AName: string): Boolean;
    procedure GeoSyncSelected(AIndex: Integer);
    function GeoMatch(APayload: TJSONObject): TTyIntegerArray;
    function GeoOfTarget(const ATarget: TTyChartEventTarget): TTyGeo;
    function GeoFinderFirst(APayload: TJSONObject): Boolean;
    procedure DoGeoSelectAction(APayload: TJSONObject; const AType: string);
    procedure DoGeoHighDown(APayload: TJSONObject);
    procedure GeoHoverOver(const ATarget: TTyChartEventTarget);
    procedure GeoHoverOut(const ATarget: TTyChartEventTarget);
    procedure GeoRegionClick(const ATarget: TTyChartEventTarget);
    function GeoApplyChanged: Boolean;
    function IsGeoDatum(const ADatum: TTyChartDatumRef): Boolean;
    function GeoTipSpec(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
    function GeoTipParams(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
    function GeoTipText(const ADatum: TTyChartDatumRef;
      const ASpec: TTyTooltipSpec): string;
    { [F4c] AN AXIS' NAME AND LABELS AS TOOLTIP TARGETS (AxisBuilder's
      setTooltipConfig, TooltipView._showComponentItemTooltip): the text
      under a point on an axis whose texts are not silent (isLabelSilent:
      silent, or neither triggerEvent nor tooltip.show), its cascade, its
      formatter params and its text }
    function IsAxisTextDatum(const ADatum: TTyChartDatumRef): Boolean;
    function AxisTextAt(AX, AY: Integer; out ADatum: TTyChartDatumRef): Boolean;
    function AxisTextOf(const ADatum: TTyChartDatumRef; out AMainType, AName,
      AValue: string; out AIndex: Integer): Boolean;
    function AxisTipSpec(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
    function AxisTipParams(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
    function AxisTipText(const ADatum: TTyChartDatumRef;
      const ASpec: TTyTooltipSpec): string;
    { [Batch 150] roam on the geos: the geo whose RoamController a gesture
      at (AX, AY) reaches first (-1: none); onIrrelevantElement for it;
      the geo or the series a gesture goes to (geos are added before series:
      a geo wins a tie); the geoRoam action; a gesture's payload; the drag's
      step (zrender's zr-level mousemove); a merge over a written-back roam }
    function GeoRoamPick(AX, AY: Integer; AZoom: Boolean): Integer;
    { [Batch 152] a roam host index's geo (a map group's past cMapRoamBase) }
    function RoamGeoOf(AIndex: Integer): TTyGeo;
    { the geoRoam action on the map series it queries (needsDrawMap) }
    procedure DoMapRoamAction(APayload: TJSONObject; var AReached: Boolean);
    function GeoIrrelevant(AGeo, AX, AY: Integer): Boolean;
    function RoamTargetAt(AX, AY: Integer; AZoom: Boolean; out AGeo: Integer): Integer;
    function DoGeoRoamAction(APayload: TJSONObject): Boolean;
    procedure GeoGesture(AGeo: Integer; AHasPan: Boolean; ADX, ADY: Double;
      AHasZoom: Boolean; AScale, AOriginX, AOriginY: Double);
    procedure GeoRoamMove(AX, AY: Integer);
    procedure GeoPatchList(AGeo: Integer);
    procedure MergeGeoRoam(var AState: TTyGraphRoamState; AIndex: Integer;
      ANew: TJSONObject);
    { ==== [Batch 152, D14 GE4] the series on a geo and the map series ==== }
    { the geo a series is on: a geo component, or a map series' own (nil:
      none, or not laid out) }
    function GeoOfSlot(ASlot: Integer): TTyGeo;
    { layout/points.ts on a geo: dataToPoint([lng, lat]) per view row, NaN
      where none -- and where a clipping geo's area (its view rect grown by
      0.1, not roamed) leaves the point out of a series that clips }
    function GeoSeriesPoints(ASlot: Integer): TTyPointFArray;
    { a coordinate of a geo as an option writes it: a region name, or a pair
      through JS ToNumber }
    function GeoPointOfJson(AGeo: TTyGeo; AValue: TJSONData; out APt: TTyPointF): Boolean;
    { a pie on a geo: createBoxLayoutReference by point -- the box against
      the chart, the centre the geo's dataToPoint of `coord`, else of
      `center` }
    function GeoPieLayout(ASlot, ADim: Integer): TTyPieLayout;
    { [Batch 154] createBoxLayoutReference's point mode: the host's
      dataToPoint (a cartesian's -- the convertToPixel arithmetic -- or a
      geo's, roam and all) of `coord`, a pie's `center` when it has none;
      False when there is no such point }
    function BoxPointOf(ASlot: Integer; out APt: TTyPointF): Boolean;
    { something besides the geo's own picture moves with a roam of AGeo:
      a series on it; any custom series (renderItem runs again) }
    function GeoRoamHasDependents(AGeo: TTyGeo): Boolean;
    { HeatmapView._renderOnGeo: the layer, as an image element }
    function BuildGeoHeatmap(ASlot: Integer; AList: TTyPaintList): Integer;
    { a scatter on a geo as the brush selects it: each row's point }
    function GeoBrushLayouts(ASlot: Integer): TTyBrushItemLayoutArray;
    { coordConvert through a brush target, a grid's or a geo's }
    function BrushConvertOn(const ATarget: TTyBrushTarget; AIndex: Integer;
      AType: TTyBrushType; AToData: Boolean; const AView: TTyBrushView;
      const ARange: TTyBrushRange; AClamp: Boolean; out AValues, AXYMinMax: TTyBrushRange): Boolean;
    { a lines series' coordinate pair on its geo }
    function GeoLinesPoint(const AX, AY: TTyLinesValue): TTyPointF;
    { a graph on a geo: every node at the geo's dataToPoint of its value's
      first two numbers (simpleLayout; NaN where either is none), then the
      edges }
    function GeoGraphPoints(ASeriesIndex: Integer; AGeo: TTyGeo): TTyPointFArray;
    procedure SolveGeoGraph(ASlot: Integer);
    { updateTransform's series: every layout a geo's view feeds, again }
    procedure GeoDependentsRelayout;
    { ---- the map series ---- }
    { getMapType: the host geo's `map`, else the series' own }
    function MapTypeOf(ASlot: Integer): string;
    { MapSeries.getInitialData: the value column, then a row for every region
      of the series' map its data does not name }
    procedure MapFillStore(ASlot: Integer; AStore: TTyDataStore);
    { buildAllMapSeriesGroups and mapDataStatistic, after the legend filter }
    procedure SolveMapSeries;
    { the groups' own geos and the data a geo draws with (after the visual
      maps); mapSymbolLayout's offsets }
    procedure SolveMapGeos(APPI: Integer);
    function GeoDataOf(AGeo: TTyGeo; ASlot: Integer; AMap: Boolean): TTyGeoData;
    function MapOrigStore(ASlot: Integer): TTyDataStore;
    { the geo a map series draws with (its group's own, or the hosting geo
      component), nil: none }
    function MapGeoOfSlot(ASlot: Integer): TTyGeo;
    { a map series' view: the main series draws its group's map, every one
      its legend symbols }
    function BuildMapSeries(ASlot: Integer; const AMeasurer: ITyTextMeasurer;
      APPI: Integer; AList: TTyPaintList): Integer;
    function BuildMapSymbols(ASlot: Integer; const AMeasurer: ITyTextMeasurer;
      APPI: Integer; AList: TTyPaintList): Integer;
    { the region groups' flags from the series' rows (setItemGraphicEl: the
      group is the item); True when one changed }
    function GeoSyncFromRows(AGeo: TTyGeo): Boolean;
    { after the states' sync of a build, and in a frame: a map picture whose
      flags moved takes its states again, its elements in place }
    procedure MapRepatch(APPI: Integer; AForce: Boolean = False);
    function MapApplyChanged: Boolean;
    { [R2-B] a map series' SVG element under the pointer (list index; -1 none) }
    procedure MapSvgPointer(ASeriesIndex, AIdx: Integer);
    { MapSeries.formatTooltip }
    function MapTooltip(const ADatum: TTyChartDatumRef; out ABlock: TTyTooltipBlock): Boolean;
    { createLegacyDataSelectAction: pieToggleSelect, mapSelect ... as the
      select action over the series of the type the query finds }
    procedure DoLegacySelect(APayload: TJSONObject; const ASeriesType, AType: string);
    procedure FreeRadars;
    { the polars go with the build [Batch 111] }
    procedure FreePolars;
    { the singles go with the build [Batch 118] }
    procedure FreeSingles;
    { every single's axis view: the grid layer (split areas and lines) with
      ABelow, the line, ticks, labels and name without [Batch 118] }
    procedure PaintSingles(APainter: TTyPainter; APPI: Integer;
      const AMeasurer: ITyTextMeasurer; ABelow: Boolean);
    procedure PaintSinglePointer(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer; const AHit: TTyAxisHit);
    { themeRiverLayout over every themeRiver, after the singles are laid out
      [Batch 118] }
    procedure SolveRivers(APPI: Integer);
    { a themeRiver's label spec: the series' label over the type's defaults
      (show, 11 px) [Batch 118] }
    function RiverLabelSpec(ASlot: Integer): TTyLabelSpec;
    function RiverEmphasisLabelOff(ASlot: Integer): Boolean;
    { a themeRiver's polygons into the list [Batch 118] }
    function BuildRiverMarks(ASlot: Integer; AList: TTyPaintList;
      APPI: Integer): Integer;
    { [Batch 128] the parallels go with the build; a parallel series' store,
      its rows laid out, the axes painted, the action's intervals written
      (True when an axis took them) and the parallel an axis stands on }
    procedure FreeParallels;
    procedure ParallelStore(ASlot: Integer; AStore: TTyDataStore);
    procedure SolveParallels(APPI: Integer);
    procedure PaintParallels(APainter: TTyPainter; APPI: Integer;
      const AMeasurer: ITyTextMeasurer);
    function ParallelAreaSelect(APayload: TJSONObject; out AFirst: Integer;
      AWrite: Boolean = True): Boolean;
    function ParallelOfAxis(AComponent: Integer): Integer;
    { both axis views of every polar: the grid layer (split areas and lines)
      with ABelow, the axis lines, ticks, labels and names without }
    procedure PaintPolars(APainter: TTyPainter; APPI: Integer;
      const AMeasurer: ITyTextMeasurer; ABelow: Boolean);
    procedure PaintPolarPointer(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer; const AHit: TTyAxisHit);
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
    procedure SolveChords(APPI: Integer);
    { [Batch 123] the custom series: every renderItem of every series
      shown, its view merged; the columns an encode spreads over one axis;
      the paint elements; the states }
    procedure SolveCustom(APPI: Integer);
    function CustomCall(AIndexInside: Integer): TJSONData;
    procedure CustomDims(ASlot: Integer; var ADims: TTySeriesDimArray);
    function CustomBuild(ASlot: Integer; AList: TTyPaintList; APPI: Integer): Integer;
    function CustomVisualFill(ASlot, ARow: Integer): TJSONData;
    procedure StDeclareCustom(ASlot, ARaw: Integer; AList: TTyPaintList);
    { [Batch 124] the custom transitions' driver has clips; a custom series
      on no coordinate system; an item's root info (nil none); a visualMap's
      row for a custom item; whether a paint element sits under an element
      with tooltipDisabled }
    function CuLive: Boolean;
    procedure AnimUtStopCustom(ASeries, ARow: Integer);
    function CustomOnNone(ASlot: Integer): Boolean;
    function CustomRootInfo(ASeriesIndex, AInside: Integer): TTyCustomElInfo;
    function CustomVisualRow(ASlot, ARow: Integer; out AVisual: TTyVisualRow): Boolean;
    function CustomTipDisabled(AElement: Integer): Boolean;
    { [Batch 121] }
    procedure SolveLines(APPI: Integer);
    function LinesProject(const AX, AY: TTyLinesValue; AClamp: Boolean): TTyPointF;
    function LinesInk(ASlot: Integer; ANode: TJSONObject; const ASolved: TTyLinesSolved;
      ARow: Integer; AStroke: TTyChartColor; AScale: Double;
      out ASpec: TTyLabelSpec): TTyLinesInk;
    function LinesTooltip(const ADatum: TTyChartDatumRef; out ABlock: TTyTooltipBlock): Boolean;
    function LinesTrailAlpha(ASeriesIndex: Integer): Double;
    procedure PaintTrail(APainter: TTyPainter; AList: TTyPaintList);
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
    procedure GraphNodeLooks(ASlot: Integer; var AInk: TTyGraphInk);
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
    function MatrixGraphPoints(ASeriesIndex: Integer; AMatrix: TTyMatrix): TTyPointFArray;
    { ---- createBoxLayoutReference [Batch 151, D13 BX1] ----
      The canvas as a refContainer; a host's dataToLayout of a coord (a
      matrix's rect, a calendar day's content rect) -- False when the host
      named is not there; a component's reference (True when it is laid
      out in a host: `coordinateSystem` 'matrix' | 'calendar' with usage
      'box', and the host is there -- ARef may then be a rect of no
      position); a series' (True for MatrixBox / CalendarBoxIndex: `coord`,
      else with ACentre a pie's `center`). }
    function CanvasXYWH: TTyXYWH;
    function HostRefAt(const ASys: string; AIndex: Integer; ACoord: TJSONData;
      out ARef: TTyXYWH): Boolean;
    function ComponentBoxRef(const AMain: string; AIndex: Integer;
      out ARef: TTyXYWH): Boolean;
    { [Batch 154] the same from the canvas' corner: device px with the
      control's origin taken off (ARefLocal), or CSS px (ARefCss: that over
      the PPI's scale) -- the frames the component views lay out in }
    function ComponentRefLocal(const AMain: string; AIndex: Integer;
      out ARef: TTyXYWH): Boolean;
    function ComponentRefCss(const AMain: string; AIndex: Integer;
      out ARef: TTyXYWH): Boolean;
    function SeriesBoxRef(ASlot: Integer; ACentre: Boolean; out ARef: TTyXYWH;
      out AFromCentre: Boolean): Boolean;
    { [Batch 154] a map series' reference: decideCoordSysUsageKind for a
      series whose own geo is laid out by it -- `coordinateSystem` 'matrix'
      or 'calendar' with usage 'box' WRITTEN (a series' default is 'data'),
      the host there -- and its dataToLayout of `coord` }
    function MapSeriesBoxRef(ASeriesIndex: Integer; out ARef: TTyXYWH): Boolean;
    { the grids and the polars laid out in their hosts' cells, once the
      matrices and the calendars are [Batch 154: and the single axes and
      the parallels] }
    procedure PlaceBoxedCoordSys;
    function CalendarGraphPoints(ASeriesIndex: Integer;
      ACal: TTyCalendar): TTyPointFArray;
    { [R2-J2] the image scope's URL resolver: OnResolveImage, once a URL }
    function ResolveImageUrl(const AUrl: string): TBGRABitmap;
    procedure SymbolItems(ASeriesIndex: Integer; const ABase: TTySymbolSpec;
      out ASpecs: TTySymbolSpecArray; out AHas: TTyBoolArray);
    { [R2-J2] a series' per-item visual callbacks ('@Name' handlers): the
      symbol options of a scatter or an effectScatter, and the
      itemStyle.color of a series that colours by itemStyle's fill; every
      row, or AOnlyRow alone }
    procedure VisualCallbacks(ASlot: Integer; var AVisual: TTySeriesVisual;
      AOnlyRow: Integer = -1);
    { [R2-J3] every series' per-item visual callbacks run (the caller frees
      the answers): the four symbol keys of a series with symbols, the
      colour key of its style path. ASymColour is the series style's colour
      a symbol callback's params carry where no colour callback answered.
      Every row, or AOnlyRow alone; nil when nothing is a callback. }
    function ItemCallbacks(ASlot: Integer; AOnlyRow: Integer;
      ASymColour: TTyChartColor): TTyItemCallbacks;
    { [R2-J3] the rebuild's callbacks: run for every slot (SolveItemCallbacks),
      read (ItemCbOf: nil when none), freed with the build }
    procedure SolveItemCallbacks;
    procedure RadarSymbolCallbacks(ASlot: Integer; var AVisual: TTyRadarVisual);
    function ItemCbOf(ASlot: Integer): TTyItemCallbacks;
    procedure FreeItemCbs;
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
    function LegendSources(const AEntries: TTyLegendEntryArray; ALegend: Integer):
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
    { a boxplot's fill, pen and width onto AVisual.Whisker [Batch 108] }
    procedure BoxplotStyle(ASlot: Integer; var AVisual: TTySeriesVisual);
    { An axis' dimension name, '' for no axis. }
    function AxisDimOf(AAxis: TTyAxis): string;
    { Rewrite ADims for a series type that declares more than one value per
      datum. A no-op for every other type. }
    procedure SeriesDataEncode(ASlot: Integer; var ADims: TTySeriesDimArray;
      out AEnc: TTySeriesEncode);
    { upstream's defaultedLabel and defaultedTooltip for one axis series,
      into its store as raw positions. }
    procedure ResolveTextDims(const AEnc: TTySeriesEncode; AStore: TTyDataStore;
      const ASource: TTyChartSource);
    { a heatmap's tooltip dimension: its generated `value` coordinate, the
      third element -- upstream's defaultedLabel, x and y being categories
      [Batch 100] }
    procedure HeatmapTipDims(ASlot: Integer; const AEnc: TTySeriesEncode;
      AStore: TTyDataStore);
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
    { SERIES LABEL LAYOUT -- LabelManager over every series that writes a
      labelLayout (AdvanceChart.LabelLayout): the layout applied to each label,
      then moveOverlap and hideOverlap across all of them. Runs on the
      finished list, after the expansion. [Batch 103] }
    procedure LayoutSeriesLabels(AList: TTyPaintList;
      const ASpecs: TTyLabelSpecArray; const AItemSpecs: TTyLabelSpecTable;
      const AMeasurer: ITyTextMeasurer; APPI: Integer);
    { LABEL LINES ROUTED AFTER THE LAYOUT -- LabelManager.processLabelsOverall's
      _updateLabelLine (AdvanceChart.LabelGuide): a pie's line again where its
      labelLayout gave an x or a y, and a line for every label of a symbol or
      a bar whose labelLine shows in some state. [Batch 112] }
    procedure RouteLabelLines(AList: TTyPaintList;
      const ASpecs: TTyLabelSpecArray; const AItemSpecs: TTyLabelSpecTable;
      const AMeasurer: ITyTextMeasurer; APPI: Integer);
    { The binding slot holding a given series index, or -1. FBindings is
      index-parallel to the option's series array only while nothing failed to
      resolve, and a hole makes the two disagree. }
    function SlotOfSeries(ASeriesIndex: Integer): Integer;
    { a scatter's jitter onto AVisual: its category base axis' points for
      this pass, or nil [Batch 110] }
    procedure JitterFor(ASlot, APPI: Integer; var AVisual: TTySeriesVisual);
    { THE PUBLIC CONVERSIONS' WORKINGS [Batch 110]: the layout brought up to
      date, the finder parsed against the option's models, each coordinate
      system asked in upstream's order }
    procedure ConvertReady;
    function ConvertDispatch(AFinder, AValue: TJSONData; AFrom: Boolean;
      AOpt: TJSONData = nil): TTyConvertResult;
    { Matrix.convertToPixel / convertFromPixel, the opt's clamp [Batch 147] }
    function ConvertOnMatrix(AMatrix: TTyMatrix; AValue, AOpt: TJSONData;
      AFrom: Boolean): TTyConvertResult;
    { the matrix a finder names: its matrix, else its series' when that is
      on a matrix per item (getCoordSys) [Batch 147] }
    function FinderMatrix(const AF: TTyParsedFinder): Integer;
    function ConvertOnGrid(AGrid: TTyGridBuild; const AF: TTyParsedFinder;
      AValue: TJSONData; AFrom: Boolean): TTyConvertResult;
    function ConvertOnCalendar(ACal: TTyCalendar; AValue: TJSONData;
      AFrom: Boolean): TTyConvertResult;
    function ConvertOnGeo(AGeo: TTyGeo; AValue: TJSONData;
      AFrom: Boolean): TTyConvertResult;
    function ConvertOnView(AView: TTyGraphView; AValue: TJSONData;
      AFrom: Boolean): TTyConvertResult;
    function ConvertOnPolar(APolar: TTyPolar; AValue: TJSONData;
      AFrom: Boolean): TTyConvertResult;
    function ConvertOnSingle(ASingle: TTySingle; AValue: TJSONData;
      AFrom: Boolean): TTyConvertResult;
    function ContainSeries(ASeriesIndex: Integer; APoint: TJSONData): Boolean;
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
    procedure GraphEdgeLabels(ASlot: Integer; var AInk: TTyGraphInk);
    function DoViewAction(const AType: string; APayload: TJSONObject): Boolean;
    { ---- the drill-downs [Batch 115] ---- }
    { a new tree: the view roots, the storage and the animation go }
    procedure HierDrillReset;
    { a row of a hierarchy series by upstream's getNodeById, -1 for none }
    function HierRowOfId(ASlot: Integer; const AId: string): Integer;
    { a node's id, for an event's targetNode }
    function HierIdOfRow(ASlot, ARow: Integer): string;
    { retrieveTargetInfo: targetNode (an id), else targetNodeId; -1 }
    function HierTarget(ASlot: Integer; APayload: TJSONObject): Integer;
    { the series an action's query names (none: every one of the type) }
    function HierQuery(APayload: TJSONObject; const AType: string): TTyIntegerArray;
    function DoSunAction(APayload: TJSONObject): Boolean;
    { [F3d] treeExpandAndCollapse as an action: the queried trees' node
      flipped, then the update (update: 'update') }
    function DoTreeToggleAction(APayload: TJSONObject): Boolean;
    { flip one tree's node (no render); False for a row it has not }
    function TreeFlip(ASlot, ADataIndex: Integer): Boolean;
    function DoTreemapAction(const AType: string; APayload: TJSONObject;
      const AEventJson: string = ''): Boolean;
    { the render an action asks for, then its event }
    procedure HierUpdate(const AEventType, APayloadJson: string);
    procedure SunburstClick(ASeries, ARow: Integer);
    procedure TreemapClick(ASeries, AX, AY: Integer);
    procedure TreemapCrumbSelect(ASeries, AIndex: Integer);
    { [R2-B] the payload the treemap view dispatches itself }
    function TreemapRoamPayload(const AType: string; ASeries: Integer;
      AX, AY, AW, AH: Double; out AJs: string): TJSONObject;
    function TreemapViewPayload(const AType: string; ASeries: Integer;
      const AId: string): TJSONObject;
    function TreemapPan(ASeries, ADX, ADY: Integer): Boolean;
    function TreemapWheel(ASeries: Integer; AScale: Double; AX, AY: Integer): Boolean;
    function TreemapRoamOk(ASlot: Integer; AZoom: Boolean): Boolean;
    function TmRowsOf(ASeries: Integer; out ASlot: Integer): Boolean;
    { the drill-down's animation: armed by a render, a frame of it, its end }
    procedure TmAnimArm(ASlot: Integer; const AView: TTyTreemapView;
      const AOld: TTyTreemapSolved; const AOldHave: TTyTreemapHave; ADirection: Integer;
      const AMap: TTyIntegerArray);
    procedure TmAnimDrop(ASeries: Integer);
    procedure TmStrandLabelFades(ASlot: Integer; const AOld: TTyTreemapSolved;
      const AOldHave, AHave: TTyTreemapHave; const AMap: TTyIntegerArray);
    procedure TmAnimDropAll;
    function TmAnimAny: Boolean;
    procedure TmWrapCheck;
    procedure TreemapFrame(AFrame: TTyPaintList);
    function IsTreemapDatum(const ADatum: TTyChartDatumRef): Boolean;
    { [F2a] a hovered breadcrumb item's emphasis, onto the list just built:
      its fill, its words, both up by ten }
    procedure TmCrumbStates(AList: TTyPaintList);
    procedure TmCrumbWrite(AList: TTyPaintList);
    { [F2a, old deferral #36] a treemap label's and upper label's opacity:
      setLabelStyle's defaultOpacity, the node's style.opacity -- the raw
      item's itemStyle.opacity over the series' (dataStyleTask), which the
      rects themselves never take (getItemStyleNormal leaves it out) }
    procedure TmLabelOpacity(AList: TTyPaintList);
    function GraphEmphasisOf(ASlot: Integer; AIsEdge: Boolean;
      AIndex: Integer): TTyChartEmphasisSpec;
    function IsTreeDatum(const ADatum: TTyChartDatumRef): Boolean;
    { ==== [Batch 100] the tooltip's timers and the targets it gained ==== }
    function TipClock: Double;
    function TipSnapNow: TTyTipSnap;
    { a series item, or a markPoint / markLine / markArea item }
    function TipTargetValid(const ADatum: TTyChartDatumRef): Boolean;
    function TipIsMarker(const ADatum: TTyChartDatumRef): Boolean;
    { [Batch 147] a matrix cell with words (it has a tooltip config) }
    function TipIsMatrix(const ADatum: TTyChartDatumRef): Boolean;
    function MatrixCellOf(const ADatum: TTyChartDatumRef; out AMatrix: TTyMatrix;
      out AInfo: TTyMatrixCellInfo): Boolean;
    function MatrixTipText(const AFormatter: string; const ADatum: TTyChartDatumRef): string;
    { the spec a snapshot is shown under: the global one for an axis
      tooltip, the cascade for an item }
    function TipSpecOf(const ASnap: TTyTipSnap): TTyTooltipSpec;
    procedure TipTryShow(const ASnap: TTyTipSnap; const ASpec: TTyTooltipSpec);
    procedure TipApplyShow(const ASnap: TTyTipSnap);
    { [R2-I7] the default markup of a show being tried; the content a show
      sets (the formatter runs here); a row's data as the unchanged-content
      test compares it }
    procedure TipMarkup(var ASnap: TTyTipSnap);
    procedure TipBuildContent(const ASnap: TTyTipSnap; out AContent: TTyTipContent);
    { [R2-I8] the box reads its text as html: the tooltip component's
      renderMode is not 'richText' ('auto' as TooltipAutoRichText says) }
    function TipHtmlMode: Boolean;
    { [R2-I8] a component item's content in the box's language: encodeHTML'd
      in html mode, as setTooltipConfig's encodeHTMLContent has it }
    function TipContentName(const AName: string): string;
    function TipRowSig(ASlot, ARow: Integer): string;
    procedure TipHide(const AGlobal: TTyTooltipSpec);
    { the timers due by ANow, in the order they would have fired; True
      when the box changed }
    function TipAdvance(ANow: Double): Boolean;
    procedure TipArmTimer;
    procedure TipTimerFired(Sender: TObject);
    { ==== [Batch 153] the tooltip and the pointer driven by actions ====
      the global listener: a zrender mousemove / click / mousewheel /
      globalout ('leave') through the axis pointer's record and the item
      tooltip's, then the last pending showTip or hideTip }
    procedure PtrListener(const ATrigger: string; AX, AY: Integer;
      const ADatum: TTyChartDatumRef; AElement: Integer);
    { the axis pointer's triggerOn: its own, else the tooltip's, else
      'mousemove|click|mousewheel' }
    function ApTriggerOn(const AGlobal: TTyTooltipSpec): string;
    { a showTip / hideTip on its way: to the listener's pendings, to the
      chart's pending actions inside a dispatch, else dispatched }
    procedure TipDispatch(APayload: TJSONObject; const AHits: TTyAxisHitArray;
      AHasHits, AViaListener: Boolean);
    procedure ActFlushPending;
    procedure ActDropPending;
    procedure ActForgetHits;
    { collectSeriesInfo's test: a series an axis tooltip gathers }
    function TipSeriesOnAxis(ASeriesIndex: Integer): Boolean;
    { doDispatchAction without the tail: no pending flush, no `updated` }
    function DispatchActionCore(APayload: TJSONObject): Boolean;
    { the three actions: axisTrigger, manuallyShowTip, manuallyHideTip }
    procedure DoUpdateAxisPointer(APayload: TJSONObject);
    procedure DoShowTip(APayload: TJSONObject);
    procedure DoHideTip(APayload: TJSONObject);
    { TooltipView._tryShow, _showSeriesItemTooltip, _showComponentItemTooltip
      and _hide }
    procedure TipTryShowEvent(const AEv: TTyTipEvent; AViaListener: Boolean);
    procedure TipHideVia(AViaListener: Boolean);
    { the tooltip view's uid, a showTip's `from` }
    function TipUid: string;
    { el.getBoundingRect() in global space: the shape's bounds and, for a
      stroked element, the stroke -- the line's width, at least 4 without a
      fill (zrender's Path.getBoundingRect) [Batch 153] }
    function TipElementRect(AIndex, APPI: Integer): TTyRectF;
    { the hits that go into dataByCoordSys: an axis that triggers the
      tooltip (the base axis under trigger 'axis', not a cross arm) with
      series rows }
    function TipAxesHits(const AHits: TTyAxisHitArray): TTyAxisHitArray;
    { showTip's dataByCoordSys from the hits; and back, for a payload that
      writes its own }
    function TipDbcJson(const AHits: TTyAxisHitArray): TJSONArray;
    { [F4b] AByRaw reads a row by its raw dataIndex (a frozen box's axes
      after a re-render), not dataIndexInside }
    function TipHitsOfDbc(ADbc: TJSONArray; AByRaw: Boolean = False): TTyAxisHitArray;
    { [F4b] an axis by dimension and component index, wherever it lives }
    function TipAxisAt(const ADim: string; AIndex: Integer; out APlot: TTyRectF;
      out APolar: TTyPolar; out ASingle: TTySingle): TTyAxis;
    { the axisPointer model's axes in collection order, for the event's
      axesInfo }
    function TipCollectionOrder: TTyAxisArray;
    { findPointFromSeries: the series' point of the payload's row --
      AFull reads dataIndexInside and name as well as dataIndex -- with the
      element and its dispatcher }
    function TipSeriesPoint(APayload: TJSONObject; AFull: Boolean;
      out AX, AY: Double; out ADatum: TTyChartDatumRef;
      out AElement: Integer): Boolean;
    { findComponentReference: a component's element by index / id / name
      and the item's name (the port's component tooltips: a matrix cell, a
      geo region) }
    function TipComponentRef(APayload: TJSONObject; out ADatum: TTyChartDatumRef;
      out AElement: Integer; out AX, AY: Double): Boolean;
    { a re-render: the hover goes; the box stays, frozen, and _keepShow
      arms its timer [F4b] }
    procedure TipReset;
    { [R2-E] a rebuild where upstream renders no tooltip view (a roam, a
      node drag, a dataZoom slider's hover): the box frozen, nothing kept }
    procedure TipResetQuiet;
    procedure TipDropDisplay;
    { [F4b] a new tooltip view (notMerge): the box, the last point and the
      kept pointer all go }
    procedure TipForget;
    { [F4b] the snapshots' axes into JSON before their build goes, the box
      held where it was painted }
    procedure TipFreeze;
    { the box of a show not painted yet, laid out on the build standing }
    procedure TipLayoutNow;
    { [F4b] TooltipView.render's _keepShow }
    procedure TipRendered;
    { [F4b] a frozen snapshot's axes and element read back from the build
      that stands now }
    procedure TipSnapRefresh;
    function GetTipSnapShown: TTyTipSnap;
    { [F4b] the axis pointers kept across a re-render, and put back }
    procedure TipKeepPointer;
    procedure TipKeepRestore;
    { [F4b] the keep timer: manuallyShowTip at the last point }
    procedure TipKeepFire;
    { [F4b] TooltipView.manuallyShowTip, the view's method: what showTip's
      update runs, and what the keep timer calls directly }
    procedure TipManualShow(APayload: TJSONObject; const AHits: TTyAxisHitArray;
      AHasHits: Boolean);
    { a marker item: its kind, its block and its place in the block }
    function MarkerItemOf(const ADatum: TTyChartDatumRef;
      out AKind: TTyMarkerKind; out ABlock: TTyMkBlock;
      out AItem: Integer): Boolean;
    { MarkerModel.formatTooltip's name and value (getName, getRawValue) }
    procedure MarkerNameValue(const ADatum: TTyChartDatumRef;
      out AName: string; out AValue: TTyMkVal);
    function MarkerTooltipContent(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function MarkerTooltipParams(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
    function MarkerColour(const ADatum: TTyChartDatumRef): TTyChartColor;
    { sunburst, treemap and sankey content [Batch 100] }
    function HierTooltipContent(const ADatum: TTyChartDatumRef;
      const AColour: TTyChartColor; out ABlock: TTyTooltipBlock): Boolean;
    function TreeEmphasisOf(ASlot, ARow: Integer): TTyChartEmphasisSpec;
    function TreeFocusOf(ASlot, ARow: Integer): string;
    function TreeRowName(ASlot, ARow: Integer): string;
    function TreeRowValue(ASlot, ARow: Integer): Double;
    { True when the datum is on a laid-out graph. }
    function IsGraphDatum(const ADatum: TTyChartDatumRef): Boolean;
    { The chart's ground for label halos, and whether it counts as dark. }
    procedure LabelGround(out AGround: TTyChartColor; out ADark: Boolean);
    { [R2-I1] A PIE'S OR A FUNNEL'S LABELS, built by their own passes after
      the marks at [ALo, AHi) of AList: each at createTextStyle's opacity --
      its own label.opacity up the item's chain, the global textStyle's, else
      its mark's style.opacity (setLabelStyle's defaultOpacity) [was: 1] }
    procedure OwnLabelOpacity(ASlot: Integer; AList: TTyPaintList; ALo, AHi: Integer);
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
    { DropStatic from a pointer handler: a list that was valid is built again
      at once (the cached picture still goes), so the pointer's next event
      hits what the change left -- zrender's storage is current the moment
      the states change, and a press usually comes before the paint the move
      asked for [Milestone D9-D14] }
    procedure DropStaticKeepList;
  protected
    { Every surviving series as a formatter would see it, in section order --
      so `{a0}` is the first row of the first section. }
    function AxisTooltipParams(const AHits: TTyAxisHitArray): TTyChartParams;
    { The elements the last render built, series and labels -- the list the
      hit test walks and the painter draws, read-only. }
    property SeriesList: TTyPaintList read FPaintList;
    { the label layout's list and each item's element [Batch 103] }
    property LabelLayoutItems: TTyLabelLayoutItemArray read FLmItems;
    property LabelLayoutEls: TTyIntegerArray read FLmEls;
    { what zrender's hover holds now, with its dispatcher [Batch 88] }
    property EvHover: TTyChartEventTarget read FEvHover;
    { the axis pointers the pointer resolved to, linked ones included, in
      the order the tooltip lists them [Batch 141] }
    property TipHits: TTyAxisHitArray read FTipHits;
    { what the box shows (or showed last): the point, the axes or the
      target, a manual placement [Batch 153] }
    property TipSnapShown: TTyTipSnap read GetTipSnapShown;
    { the series index of a hit's binding slot; -1 for none [Batch 141] }
    function SlotSeriesIndex(ASlot: Integer): Integer;
    { THE LIST AS IT STANDS THIS FRAME: every animated element read from its
      proxy, insertion indices kept. The list itself when nothing is bound.
      [Batch 89] }
    function AnimFrame: TTyPaintList;
    { What the bar solve gave a series -- its band, offset and width. An
      unsolved column (not a bar, or no such series) when there is none. }
    function BarColumnOf(ASeriesIndex: Integer): TTyBarColumn;
    { What the polar bar solve gave a series [Batch 113]: unsolved where it
      is not a bar on a polar. }
    function PolarBarOf(ASeriesIndex: Integer): TTyPolarBarLayout;
    { What the themeRiver layout gave a series [Batch 118]: not Valid where
      it is no themeRiver. }
    function RiverLayoutOf(ASeriesIndex: Integer): TTyThemeRiverLayout;
    { What every render measures its text with: the painter's own, in the
      theme's fonts. Virtual so a text table -- zrender's, for a chart laid
      out against upstream's -- can stand in for the fonts. }
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; virtual;
    { [F6b] AN SVG MAP'S TEXT while it is parsed (a <tspan> moves on by the
      width of the text before it): the width in CSS px of AText in AFont,
      zrender's platformApi.measureText. The default asks the painter's
      measurer at 96 PPI with the font size in px; virtual so a test can
      answer with zrender's own width table. }
    function GeoSvgMeasure(const AText: string; const AFont: TTyGsFont): Double; virtual;
    { THE TOOLBOX'S DIALOGS [Batch 125]: dataView's table (True when Refresh
      closed it, the text in AText) and saveAsImage's file name. Virtual so
      a host -- or a test -- answers without a modal; the defaults are the
      library's dialogs (tyControls.AdvanceChart.ToolboxDlg). }
    function ToolboxShowDataView(const ATitle: string; var AText: string;
      AReadOnly: Boolean; const ACloseCaption, ARefreshCaption: string): Boolean; virtual;
    function ToolboxAskFileName(var AFileName: string; const AType: string): Boolean; virtual;
    function GetStyleTypeKey: string; override;
    { A RESIZE ASKS THE MEDIA QUERIES AGAIN (upstream's resize ->
      resetOption('media')) [Batch 107] }
    procedure Resize; override;
    procedure Loaded; override;
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
    { ---- the dirty-rect path [Batch 142] ---- }
    { the frame: the static layer (whole, or in rects), the dynamic layer,
      the flush events; FDrLastFull / FDrLastRects say what changed }
    procedure DrPrepare(const ARect: TRect; APPI: Integer; const AScale: TTyCanvasScale);
    { what changed onto ACanvas: everything, or the rects }
    procedure DrComposite(ACanvas: TCanvas; const ARect: TRect);
    { the window's paint: composite the clip, preparing first unless a
      flush already did }
    procedure DrPaintWindow;
    procedure DrFlushAsync(AData: PtrInt);
    function DrCanPartial(AW, AH: Integer): Boolean;
    function DrStaticPartial(const R: TRect; APPI: Integer;
      var APool: TTyRepaintPool): Boolean;
    procedure DrStaticFull(const R: TRect; APPI: Integer);
    procedure DrDynamic(const R: TRect; APPI: Integer; var APool: TTyRepaintPool;
      var AFull: Boolean);
    { a frame's rect of device px on its layers: FDrScale times it (#83) }
    function DrRaster(const R: TRect): TRect;
    { the static cache's APx onto ACanvas at APx (client px), and the
      dynamic layer's APx at (ADstX, ADstY): one layer pixel per canvas pixel
      on a raster canvas, into the device-px rect on one in device px }
    procedure DrCopyStatic(ACanvas: TCanvas; const APx: TRect);
    procedure DrDrawDynamic(ACanvas: TCanvas; const APx: TRect; ADstX, ADstY: Integer);
    procedure DrCaptureBase(ABmp: TBGRABitmap);
    procedure StaticDrop;
    procedure SetUseDirtyRect(AValue: Boolean);
    { the coarse pointer's size, logical px: 0 when it is off }
    function CoarseSize: Integer;
    { the display list's hit at a point: the direct test, then the coarse
      fallback -- the insertion index, or -1 }
    function ListHitAt(AX, AY: Double): Integer;
    { the last frame's repaint, for a test and the bench: everything, or
      these rects (device px; empty when nothing changed) }
    function LastRepaintFull: Boolean;
    function LastRepaintRects: TTyZrRectArray;
    { WHAT THE LAST FULL RENDER DREW, by view -- RenderTo's, an export's, a
      static layer's. [Batch 106] }
    function LastViewsDrawn: TTyChartViews;
    { THE LOADING EFFECT AS THE LAST PAINT LAID IT OUT, CSS px (False before
      one), its cfg, the spinner's angles now and the clips its driver runs.
      [Batch 106] }
    function LoadingGeometry(out AGeo: TTyLoadingGeometry): Boolean;
    function LoadingCfg: TTyLoadingCfg;
    function LoadingArcAngles(out AStart, AEnd: Double): Boolean;
    function LoadingClipCount: Integer;
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
    { [Batch 153] axisTrigger's first pass at a point that may be
      fractional; AInput, when given, is the payload's axesInfo -- only the
      axes it names are processed, each at its own value when it writes one }
    function ResolveAxisPointers(AX, AY: Double; AInput: TJSONArray = nil): TTyAxisHitArray;
    { [R2-I7] the axisPointer model's axes, as collectAxesInfo collects them }
    function PtrCollect: TTyPtrAxisInfoArray;
    function PtrInfoOf(const AInfos: TTyPtrAxisInfoArray; AAxis: TTyAxis): Integer;
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
    { [R2-I8] THE LABEL A POINTER DRAWS, run as BaseAxisPointer.render runs
      it: a function formatter is called when the value or the status
      changed since the axis' last render, on a full update (forceRender),
      and once more after the first show -- whose graphicKey change clears
      the memo --; otherwise the text it gave stands. A template is cheap
      and has no side effects: it is just formatted. }
    function PointerDrawLabelText(const AHit: TTyAxisHit; AValue: Double): string;
    { [R2-I8] the pointers this paint does not draw are hidden: their
      memo's status is 'hide' (the value kept, as the model keeps it) }
    procedure PointerMemoHideOthers(const AHits: TTyAxisHitArray);
    { [R2-I8] the label text a pointer last drew through the memo ('' when
      it has none) -- for a probe that must not run the formatter }
    function PointerLabelDrawn(const AHit: TTyAxisHit): string;
    function AuthorBackground(out AColour: TTyChartColor): Boolean;
    procedure GlobalInk(var AName: string; var ASize, AWeight: Integer;
      var AColour: TTyChartColor; APick: TTyTextPick);
    procedure GlobalTextOver(var AName: string; var ASize, AWeight: Integer;
      var AHasColour: Boolean; var AColour: Cardinal; APick: TTyTextPick);
    { THE ROOT'S SIDE OF A TEXT BLOCK: the root textStyle and
      richInheritPlainLabel, and the chart's global text font -- the skin's
      label font with the root textStyle's over it [Batch 86] }
    function RtGlobal: TTyRtGlobal;
    { the styles an axis' labels and name are painted in: the theme's, with
      the family, size, weight and colour the layout measured them in -- the
      author's where written [Batch 83]. A time axis' heavier `{primary|...}`
      part is a rich piece of the label's block [Batch 104]. }
    procedure AxisTextStyles(ASpec: PTyAxisLayoutSpec; out ALabel,
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
    { THE SHADOW'S RECT as upstream's CartesianAxisPointer builds it
      [Batch 101]: makeRectShape([min, other0], [max - min, otherSpan]) --
      x, y, width, height, the width (on a y axis the height) negative or
      not as the other axis' extent runs. The band is a category's (at least
      1px), or on a value, log or time axis the largest positive gap of the
      bar, pictorial bar, candlestick or boxplot statistics holding a hovered
      series (taken on that series' base axis, whichever axis the pointer is
      on), four fifths of the axis for a lone value, else 1px; the ends
      clamped to the axis. False when the hit has no axis or no value. }
    function PointerShadowShape(const AHit: TTyAxisHit;
      out AShape: TTyXYWH): Boolean;
    { the same about the pixel AAt rather than the hit's own value }
    function PointerShadowShapeAt(const AHit: TTyAxisHit; AAt: Double;
      out AShape: TTyXYWH): Boolean;
    { A POLAR HIT'S POINTER as it is drawn [Batch 111]: PolarAxisPointer's
      line, circle or sector at the pointer's value, and its label -- the
      value's text in the pointer label's font, padded, hung by
      getLabelPosition's point and alignment, kept inside the control (ARect).
      False when the hit is not a polar one. }
    { calcAxisPointerShadowBandWidth on a polar axis [Batch 113]: a
      category's band, else the bars' smallest gap among the hovered series
      over this axis' mapping span -- at least 1 }
    function PolarShadowBand(const AHit: TTyAxisHit): Double;
    function PolarPointerGeometry(const AHit: TTyAxisHit; const ARect: TRect;
      const AMeasurer: ITyTextMeasurer; APPI: Integer;
      out ADraw: TTyPolarPointerDraw): Boolean;
    { A SINGLE AXIS HIT'S POINTER as it is drawn [Batch 118]:
      SingleAxisPointer's line or shadow at dataToPoint(value)[0], and its
      label -- buildCartesianSingleLabelElOption's place, the value's text
      in the pointer label's font, padded, kept inside the control (ARect).
      False when the hit is not a single one. }
    function SinglePointerGeometry(const AHit: TTyAxisHit; const ARect: TRect;
      const AMeasurer: ITyTextMeasurer; APPI: Integer;
      out ADraw: TTySinglePointerDraw): Boolean;
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
    { a sunburst's, a treemap's and a sankey's own getDataParams [R2-E] }
    function HierTipParams(const ADatum: TTyChartDatumRef; ASlot: Integer;
      var AParams: TTyChartCallbackParams): Boolean;
    { [Batch 104] THE TEXT THE LAST PAINT'S FORMATTER GAVE THE BOX -- a
      template after the time format and formatTpl, or a handler's answer --
      '' when the box was not drawn or had no formatter. }
    function TooltipFormatterText: string;
    { THE COLOUR THE LAST PAINT GAVE THE BOX'S BORDER; 0 when no box was
      drawn }
    function TooltipBorderColour: TTyColor;
    { [R2-I8] THE LINES THE LAST PAINT DREW THE BOX WITH, measured (device
      px); nil when no box was drawn }
    function TooltipLines: TTyTooltipLineArray;
    { [Batch 100] THE BOX'S SIZE AS MEASURED, device px, just before it is
      placed. Nothing here; a test that compares a placement against
      upstream's -- whose sizes come from another measurer -- answers the
      size the fixture gave. }
    procedure TooltipContentSize(var AW, AH: Double); virtual;
    { [R2-I8] AN HTML TOOLTIP'S LINES: what a formatter (or a component's
      content) answered, read as html in the tooltip's inks. OnTooltipHtml
      first; unhandled, the built-in subset (TyTooltipHtmlLines). Override
      to read more of it -- call inherited for the rest. }
    function TooltipHtmlLines(const AHtml: string;
      const AInk: TTyTooltipInk): TTyTooltipLineArray; virtual;
    { [Batch 100] THE POINTERS THE OPTION SHOWS BY ITSELF: an axis'
      `axisPointer: {status: 'show', value}` before any pointer event }
    function OptionPointerHits: TTyAxisHitArray;
    function OptPtrIsBack(const AMainType: string; AIndex: Integer): Boolean;
    procedure OptPtrTakePiece(APiece: TJSONData);
    procedure PointerStateChanged; override;
    { WHERE THE POINTER IS, every pixel of the way. The tooltip's anchor is the
      cursor, so this repaints on movement and not only when the datum under it
      changes -- the frame it asks for is a blit of the static layer plus one
      box, which is what the cache exists to make affordable. }
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure DblClick; override;
    { THE KEYBOARD [Batch 144]: the arrows, Home / End and the page keys
      move the focus item (and are always taken, so they never become the
      form's focus navigation); Enter / Space select it, Escape clears it;
      Tab is never taken. OnKeyDown runs first and may take the key.
      [F5] Tab / Shift+Tab walk the chart's focus stops and leave past the
      ends; on a component's stop the keys are the component's. }
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { leaving the control lets the focus item go (downplay, tooltip hidden)
      and keeps its place [F5: a component's part too] }
    procedure DoExit; override;
    { [F5] coming in by Tab starts at the first stop, by Shift+Tab at the
      last (KbEnter, which a test calls for the key state it cannot fake) }
    procedure DoEnter; override;
    procedure KbEnter(ABackward: Boolean);
    { the window: its accessibility link is attached to it [Batch 144] }
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    { the chart's mouse events [Batch 84] }
    function EventTargetAt(AX, AY: Integer): TTyChartEventTarget;
    { [R2-B] the breadcrumb item a list element is, and its target }
    function CrumbOfElement(AIdx: Integer; out ASeries, AIndex: Integer): Boolean;
    function CrumbTarget(ASeries, AIndex: Integer): TTyChartEventTarget;
    { [R2-B] the target of the marker element at AIdx in the list }
    function MarkerEventTarget(AIdx: Integer): TTyChartEventTarget;
    function SeriesEventTarget(const ADatum: TTyChartDatumRef;
      AElement: Integer): TTyChartEventTarget;
    function SeriesEventModel(ASeriesIndex: Integer): TTyEventModel;
    procedure SilenceSeries(AList: TTyPaintList);
    { [F6a] the series' elements' cursors: an item's `cursor` (over its
      level's, its category's, its series', the root's -- the model's
      parent chain), 'move' on a node a drag takes, 'default' on a large
      batch -- where the series' view sets one }
    procedure StampCursors(AList: TTyPaintList);
    procedure EmitChartEvent(const AType: string; const ATarget: TTyChartEventTarget;
      AX, AY: Integer; AHasOffset: Boolean = True);
    procedure EventMove(AX, AY: Integer);
    { [R2-E] EventMove in its two halves: the out and the move, then
      zrender's mouseover after every zr-level mousemove listener
      (MouseMove runs the pointer's, the brush's, the parallel's between) }
    procedure EventMoveOnly(AX, AY: Integer);
    procedure EventOver;
    procedure EventDown(AButton: TMouseButton; AX, AY: Integer);
    procedure EventUp(AButton: TMouseButton; AX, AY: Integer);
    procedure EventDblClick(AX, AY: Integer);
    procedure EventContextMenu(AX, AY: Integer);
    procedure EventLeave(AX, AY: Integer);
    { ---- the graphic component [Batch 122] ---- }
    { a merge's report: the model's optionUpdated (or a new model, or none) }
    procedure GfxPass(const AReport: TTyMergeReport);
    { a fresh option: a new model from the tree }
    procedure GfxInitFromTree;
    function GfxAnimSettings: TTyGfxAnimSettings;
    { the view rendered (an update pending) or placed (a new size), made
      ready, and turned into paint elements }
    procedure GfxBuild(APPI: Integer);
    { the elements under the axes }
    procedure GfxPaintUnder(APainter: TTyPainter);
    function GfxLive: Boolean;
    { an element's handlers, bubbling up its groups: True when one asked to
      stop (no chart event follows) }
    function GfxElementEvent(const AType: string; const ATarget: TTyChartEventTarget;
      AX, AY: Integer): Boolean;
    { zrender's Draggable: a press on a draggable element (or one under a
      draggable group) starts a drag, every move drifts it, a release ends it }
    procedure GfxDragStart(const ATarget: TTyChartEventTarget; AX, AY: Integer);
    procedure GfxDragMove(AX, AY: Integer);
    { ---- element states and the selection [Batch 88] ---- }
    function StKindOf(ASlot: Integer): TTyStKind;
    function StSeriesNode(ASeriesIndex: Integer): TJSONObject;
    function StItemNode(ASeriesIndex, ARaw: Integer): TJSONObject;
    { True where StItemNode reads the series' own `data` items: AArr is
      that array (nil when there is none) -- a loop over every row asks
      once [R2-L] }
    function StItemPlainArray(ASeriesIndex: Integer; out AArr: TJSONArray): Boolean;
    { after every build: the records follow the new elements (a re-layout
      re-applies the previous lists, upstream's full update), the selection
      flags are synced, the flags applied and the values written back }
    procedure StSync(AList: TTyPaintList; APPI: Integer);
    { a notMerge option: the records taken before the option goes, then put
      on the reused rows of the reused series views [Batch 96] }
    procedure StCarryTake(const AViewKeys: TTyStringArray);
    procedure StCarryApply;
    procedure StDeclareItem(ASlot, ARaw: Integer; AList: TTyPaintList;
      APPI: Integer);
    procedure StDeclareLine(ASlot: Integer; AList: TTyPaintList);
    procedure StDeclareCandle(ASlot, ARaw: Integer;
      const ANodes: array of TJSONObject; var AHost: TTyStElement);
    { [F2b] a gauge's progress arc, the row's second dispatcher }
    procedure StDeclarePeer(ASlot, ARaw: Integer; AList: TTyPaintList);
    { [F2b] the series' marker elements: their blur state, their flag the
      series' isBlured (MarkerView.toggleBlurSeries) }
    procedure StDeclareMarks(ASeriesIndex: Integer; AList: TTyPaintList);
    { [R2-B] a marker item's model chain, nearest first }
    function StMarkItemNodes(ASeriesIndex: Integer; AKind: TTyChartTargetKind;
      ADataIndex: Integer): TTyStNodeArray;
    { [R2-B] a marker item's hoverState, and setting it }
    function StMarkFlag(ASeriesIndex: Integer; const AKey: string): Integer;
    procedure StSetMarkFlag(ASeriesIndex: Integer; const AKey: string; AHover: Integer);
    { [R2-B] toggleBlurSeries on a series' markers: in, or out of blur }
    procedure StMarksBlur(ASeriesIndex: Integer; AEnter: Boolean);
    { [R2-B] the marker item a target is: False for none or no dispatcher }
    function StMarkTarget(const ATarget: TTyChartEventTarget; out AKey: string;
      out AFirst: Integer): Boolean;
    { [R2-B] a marker item's hover in and out }
    procedure StMarkHoverOver(const ATarget: TTyChartEventTarget);
    procedure StMarkHoverOut(const ATarget: TTyChartEventTarget);
    { the marks' flags from their items' (StMarkFlag), then their lists:
      True when a list changed }
    function StApplyMarks(ASeriesIndex: Integer): Boolean;
    { after the markers are built: every marker element by its host series,
      its state declared, applied and written into the list }
    procedure StSyncMarks(AList: TTyPaintList);
    procedure StWrite(AList: TTyPaintList);
    procedure StWriteRows(AList: TTyPaintList);
    { upstream's frame: every flag that changed since the last one becomes a
      state list. True when an element changed. }
    function StApplyChanged: Boolean;
    function StPatchList: Boolean;
    { [R2-I9] THE HOVER LAYER (zrender's hover layer, ECharts'
      updateHoverLayerStatus): the root hoverLayerThreshold as `elCount >
      value` reads it; whether a series' rendered paths carry the flag (the
      threshold, or an incremental render's own); the flags given to every
      row -- AEnter (a build) gives them to every row whether the series'
      changed or not; the copies the layer brushes, found again; whether
      there are any; and drawing them over everything the canvas holds }
    function StHoverThreshold: Double;
    function StSeriesHoverOn(ASlot: Integer; AThl: Boolean): Boolean;
    procedure StHoverStamp(AEnter: Boolean);
    procedure StHoverCollect;
    function StHoverAny: Boolean;
    procedure PaintHoverLayer(APainter: TTyPainter);
    function StItemAt(ASeriesIndex, AInnerRow: Integer): PTyStItem;
    { [F2b] the row's second dispatcher (a gauge's arc), nil for none }
    function StPeerAt(ASeriesIndex, AInnerRow: Integer): PTyStItem;
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
    function GraphCategoryNode(ASlot, ACategory: Integer): TJSONObject;
    function StEdgeNodes(ASeriesIndex, AEdge: Integer): TTyStNodeArray;
    function StIsSankey(ASeriesIndex: Integer): Boolean;
    { [Batch 120] a chord; a series with an edge data's rows (a sankey's,
      a chord's) }
    function StIsChord(ASeriesIndex: Integer): Boolean;
    function StHasEdges(ASeriesIndex: Integer): Boolean;
    procedure StDeclareChordEdge(ASlot, AEdge: Integer; AList: TTyPaintList);
    procedure StSankeyCurveFill(ASlot, AEdge: Integer;
      const ANodes: TTyStNodeArray; const AState: string; var AObj: TTyStObject);
    procedure StDeclareEdge(ASlot, AEdge: Integer; AList: TTyPaintList);
    { [F2a] graph, tree and treemap on the shared state model }
    procedure StDeclareGraphEdge(ASlot, AEdge: Integer; AList: TTyPaintList);
    procedure StDeclareTreeEdge(ASlot, ARaw: Integer; AList: TTyPaintList);
    procedure StDeclareTreemap(ASlot, ARaw: Integer; AList: TTyPaintList);
    { TreeView's onHoverStateChange on a node group that went from AOld to
      another state: unless it went to blur, its edge takes the state -- when
      the parent's symbol is not blurred at that moment }
    procedure StTreeFollow(ASeriesIndex, ARaw, AOld: Integer);
    { a graph's node by its raw row, an edge by the link row its elements
      carry; the edge data's inner index (the edges whose two ends survive
      the legend, in order) and back; -1: none }
    function StGraphNodeOfRaw(ASlot, ARaw: Integer): Integer;
    function StGraphEdgeOfRow(ASlot, ARow: Integer): Integer;
    function StGraphEdgeInner(ASlot, AEdge: Integer): Integer;
    function StGraphEdgeOfInner(ASlot, AInner: Integer): Integer;
    { the graph's edge data as the selection reads it, by inner index: the
      edge data's name, its raw index [F2a] }
    function SelEdgeData(ASlot: Integer): TTySelData;
    { [F3b] the slot holds a solved chord }
    function StChordSlot(ASlot: Integer): Boolean;
    function StSankeySlot(ASlot: Integer): Boolean;
    { queryDataIndex on a graph's edge data: solved edge indices }
    function QueryEdgeIndex(ASlot: Integer; APayload: TJSONObject;
      out AEdges: TTyIntegerArray): Boolean;
    function StItemFocus(ASeriesIndex, ARaw: Integer;
      out AScope: TTyStScope): TTyStFocus;
    function StEdgeFocus(ASeriesIndex, AEdge: Integer;
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
    procedure StHoverOverSeries(const ATarget: TTyChartEventTarget);
    { an element the state machine draws (the overlay leaves it alone) }
    function StOwnsElement(AIndex: Integer): Boolean;
    function StEmphasised(AIndex: Integer): Boolean;
    function StPrimaryInk: TTyChartColor;
    function StMemoMatches(ASeries: Integer; const ANodes: TTyStNodeArray;
      const ABlock: string): Boolean;
    procedure SelEnsure(ASlot: Integer);
    function SelData(ASlot: Integer): TTySelData;
    procedure SelSyncFlags(ASlot: Integer);
    function MatchSeries(APayload: TJSONObject): TTyIntegerArray;
    function QueryDataIndex(ASlot: Integer; APayload: TJSONObject;
      out AInner: TTyIntegerArray): Boolean;
    procedure DoSelectAction(APayload: TJSONObject);
    { ABatchItem: one item of a batch -- no allLeaveBlur of its own, no event
      [Batch 116] }
    procedure DoHighDownAction(APayload: TJSONObject; ABatchItem: Boolean = False);
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
    { ... with an update payload's animation (a dataZoom's) [Batch 96] }
    procedure FullUpdateWith(const APayload: TTyAnimOverride; AHasPayload: Boolean);
    { the target the element at AIndex of the list answers as }
    function TargetOfElement(AIndex: Integer): TTyChartEventTarget;
    { the series' (or the datum's) border, for its legend icon }
    procedure LegendBorderOf(ASlot, ARaw: Integer; var ASrc: TTyLegendSource);
    procedure EmitPayloadEvent(const AType, APayloadJson: string;
      AObj: TJSONObject = nil);
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
    { the wheel's roams: the thumbnail, the dataZoom, a graph [Batch 153] }
    function WheelRoam(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure CaptureChanged; override;
    { The graph a gesture at (AX, AY) goes to: the first, in upstream's order
      -- highest zlevel, then z, then the lowest series index -- whose roam
      allows it and whose area holds the point. -1 when none does. }
    function RoamSeriesAt(AX, AY: Integer; AZoom: Boolean): Integer;
    { the same, with the winner's z and zlevel (0 when none) [Batch 150] }
    function RoamSeriesAtZ(AX, AY: Integer; AZoom: Boolean;
      out AZ, AZLevel: Integer): Integer;
    function IsTreeSeries(ASeriesIndex: Integer): Boolean;
    function IsSankeySeries(ASeriesIndex: Integer): Boolean;
    function IsTreemapSeries(ASeriesIndex: Integer): Boolean;
    { the node drags [Batch 114] }
    procedure GraphDragMove(AX, AY: Integer);
    procedure GraphDragEnd;
    { [F3b] some force graph's iteration runs (layoutAnimation) }
    function GraphForceLive: Boolean;
    function SankeyDragStart(ASlot, ANode, AX, AY: Integer): Boolean;
    procedure SankeyDragMove(AX, AY: Integer);
    procedure SankeyViewOf(ASlot: Integer);
    procedure FreeSankeyViews;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
    { [R2-I8] WHAT A TOOLTIP'S renderMode 'auto' (the default) MEANS:
      upstream answers 'html' where there is a DOM -- every browser page,
      the gallery's -- and 'richText' where there is none (node). False (the
      default) reads 'auto' as a browser does: a formatter's text is html.
      True reads it as node does: the text is drawn as written, markup and
      all, and params.marker is richText's token. A written 'html' or
      'richText' is obeyed either way. }
    property TooltipAutoRichText: Boolean read FTooltipAutoRichText
      write FTooltipAutoRichText;
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
    { EXPORT, as getDataURL does it [Batch 106]. AOptsJson is upstream's
      options object -- `type`, `pixelRatio`, `backgroundColor`,
      `excludeComponents` -- '' for none; see tyControls.AdvanceChart.Export for
      what each one does. The picture is the FINISHED chart: an animation
      running in the window is drawn where it will rest, and the pointer's
      own state -- the tooltip box, a hovered axis pointer, a hover's
      highlight -- is left out (an option's own pointers are drawn). The
      loading effect, when shown, is in it, as upstream's is.

      A PNG, or a JPEG for `type: 'jpeg'` (composited onto black, as a
      canvas makes a JPEG of transparency, at quality 92). Raises
      EArgumentException for options that are not JSON. An image with no
      pixels writes nothing. }
    procedure SaveToStream(AStream: TStream; const AOptsJson: string = '');
    function SaveToBytes(const AOptsJson: string = ''): TBytes;
    { The type is the options' `type` when they write one, else the file's
      extension (.jpg / .jpeg are a JPEG), else PNG. }
    procedure SaveToFile(const AFileName: string; const AOptsJson: string = '');
    { 'data:image/png;base64,...' (or image/jpeg); 'data:,' for an image with
      no pixels, as a canvas answers. }
    function GetDataURL(const AOptsJson: string = ''): string;
    { renderToCanvas: the picture, unencoded. The caller frees it; nil for an
      image with no pixels. }
    function RenderToBitmap(const AOptsJson: string = ''): TBGRABitmap;
    { [R2-J2] drop every picture OnResolveImage answered (and every URL it
      left unanswered): the next draw asks again }
    procedure ForgetResolvedImages;
    { THE LOADING EFFECT, showLoading's `default` [Batch 106]: a mask over
      the chart, the text and a turning arc. ACfgJson is upstream's cfg
      (`text`, `textColor`, `color`, `maskColor`, `fontSize`, `fontWeight`,
      `fontFamily`, `showSpinner`, `spinnerRadius`, `lineWidth`); the
      colours and the font default to the theme (TyAdvChartLoading,
      TyAdvChartLoadingSpinner), the text to rsTyChartLoading. Raises
      EArgumentException for a cfg that is not JSON.

      A NAME other than 'default' (or '') shows nothing -- and, as upstream,
      has already hidden the effect shown before. The spinner turns on the
      control's timer whatever the option's `animation` says, as upstream's
      does; AnimationMode camOff holds it still. }
    procedure ShowLoading(const ACfgJson: string = ''); overload;
    procedure ShowLoading(const AName, ACfgJson: string); overload;
    procedure HideLoading;
    property LoadingShown: Boolean read FLoadShown;
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
    { THE LARGE MODE the last build drew a series in: lgkNone for one drawn
      an element per datum [Batch 117] }
    function SeriesLargeKind(ASeriesIndex: Integer): TTyLargeKind;
    { A LINES SERIES as the layout solved it: its rows, their look, its clip
      and its large batch (Valid False for any other) [Batch 121] }
    function LinesSolvedOf(ASeriesIndex: Integer): TTyLinesSolved;
    { THE TOOLBOX [Batch 125]: its model and layout as the last render made
      them (CSS px), each icon's live state, the title placed where it is
      drawn, the features' iconStatus, the select dataZoom's history and the
      brush's cover; ToolboxClick clicks an icon by name. }
    function ToolboxCount: Integer;
    function ToolboxSpec(AIndex: Integer): TTyToolboxSpec;
    function ToolboxLayout(AIndex: Integer): TTyToolboxLayout;
    function ToolboxIconState(ATb, AIcon: Integer; out AEmphasised, ATitleShown,
      APosAdjusted, AAlignAdjusted: Boolean): Boolean;
    function ToolboxTitle(ATb, AIcon: Integer): TTyTbTitlePlace;
    function ToolboxIconStatus(ATb: Integer; const AFeature, AIcon: string): string;
    function ToolboxHistoryCount: Integer;
    function ToolboxCover(out ARect: TTyXYWH): Boolean;
    function ToolboxClick(ATb: Integer; const AFeature, AIcon: string): Boolean;
    { the data view's text as the dialog would show it }
    function ToolboxDataViewText: string;
    { a frame: the icons' hover states land (a paint does it too) }
    procedure ToolboxFrame;
    property ToolboxZoomActive: Boolean read FTbZoomActive;
    { 'pointer' over an icon, 'crosshair' over a brush panel, '' neither }
    property ToolboxCursorName: string read FTbCursor;
    { why the last data view's text was not merged ('' when it was) }
    property ToolboxError: string read FTbError;
    { ---- THE TIMELINE [Batch 129] ----
      The first timeline's view as the last render left it (nil without a
      timeline): its elements, their roles and states, the model it read.
      TimelineNow is the play timer's clock (ms; NaN, the default, is the
      machine's -- and only then does a timer run); TimelineTick fires every
      play timer due by ANowMs; TimelineDue is the pending one's due instant
      (NaN for none). }
    function TimelineView: TTyTimelineView;
    function TimelineDue: Double;
    procedure TimelineTick(ANowMs: Double);
    property TimelineNow: Double read FTlNow write FTlNow;
    { ---- THE BRUSH COMPONENTS [Batch 126] ----
      Per brush component: its controller (the panels, the covers and their
      shapes, the drawing state; CSS px) and the areas its model keeps. The
      brushSelect dispatches the throttle ran and the brush / brushend
      events, each with its areas. The cursor the brush asked for on the
      last move ('' none). BrushNow drives the throttle's clock (NaN, the
      default: the machine's), BrushTick runs the timers due by ANow. }
    function BrushCount: Integer;
    function BrushControllerOf(AIndex: Integer): TTyBrushController;
    function BrushModelAreas(AIndex: Integer): TTyBrushAreaArray;
    { the piece under device px (AX, AY), as the pointer finds it }
    function BrushHitTest(AX, AY: Integer; out ABrush, AIndex: Integer;
      out APiece: TTyBrushPiece): Boolean;
    function BrushSelectCount: Integer;
    function BrushSelectAt(AIndex: Integer): TTyBrushSelectRec;
    function BrushEventCount: Integer;
    function BrushEventAt(AIndex: Integer): TTyBrushEventRec;
    procedure BrushClearLogs;
    procedure BrushTick(ANow: Double);
    property BrushCursorName: string read FBrushCursor;
    property BrushNow: Double read FBrushNow write FBrushNow;
    { whether some brush controller holds globalPan [Batch 127] }
    function BrushGlobalPanTaken: Boolean;
    { ---- THE PARALLEL AXES' AREA SELECT [Batch 130] ----
      A parallelAxis view's controller (nil before its view renders; CSS
      px, the covers in the axis' frame), the axisAreaSelect actions the
      views dispatched. BrushHitTest answers TyParallelBrushBase plus the
      axis for a parallel axis' cover. }
    function ParallelBrushOf(AAxis: Integer): TTyBrushController;
    function ParallelBrushActionCount: Integer;
    function ParallelBrushActionAt(AIndex: Integer): TTyParallelBrushAction;
    procedure ParallelBrushClearLog;
    { ---- THE PARALLEL AXIS EXPANSION [Batch 140] ----
      The clock ParallelView's throttle reads (NaN: the tick count) and its
      pending calls run up to ANow, as timers would; the parallelAxisExpand
      actions the views dispatched. }
    property ParallelExpandNow: Double read FParExpNow write FParExpNow;
    procedure ParallelExpandTick(ANow: Double);
    function ParallelExpandActionCount: Integer;
    function ParallelExpandActionAt(AIndex: Integer): TTyParallelExpandAction;
    procedure ParallelExpandClearLog;
    { ---- THE THUMBNAILS [Batch 140] ----
      Each thumbnail component as the last render laid it out (its model,
      whether it is enabled, its box, content rect, window, the copy and
      its view); the one the target graph renders into (-1); the thumbnail
      whose box or rim is under (AX, AY), the topmost, or -1. }
    function ThumbnailCount: Integer;
    function ThumbnailState(AIndex: Integer): TTyThumbState;
    function ThumbnailOwner: Integer;
    function ThumbnailHitAt(AX, AY: Double): Integer;
    { the merged option's node of component AIndex of AMainType, as the
      models hold it (nil when there is none): the window an action wrote
      and the layout rewrote is read here. Borrowed; not to be changed.
      [Batch 140] }
    function OptionComponent(const AMainType: string; AIndex: Integer): TJSONData;
    { ---- progressive rendering and appendData [Batch 119] ---- }
    { chart.appendData with seriesIndex and data: ADataJson, a JSON array of data
      items, appended to the series' own `data`. Nothing is drawn until the
      next frame (the animation timer, or ProgressTick), which takes the rows
      in WITHOUT moving the axes -- they keep the extent of the last update,
      as upstream's do -- and carries a progressive series on, or starts it
      again, as upstream's scheduler would. False, and nothing appended, for
      a series that is not there or reads a dataset (no `data` array of its
      own), and for a text that is no array or nests too deep. }
    function AppendData(ASeriesIndex: Integer; const ADataJson: string): Boolean;
    { ONE ANIMATION FRAME of progressive rendering (_onframe): appended rows
      taken in, then a chunk of every progressive series, again while the
      frame's 1 ms budget lasts; `rendered`, and `finished` with the last
      chunk. The 16 ms timer calls it with the animation's frame. }
    procedure ProgressTick;
    { a chunk still to draw, or rows appended and not yet taken in }
    function ProgressiveUnfinished: Boolean;
    { the series' pipeline as the last update and frame left it (Series -1
      for none) }
    function SeriesProgress(ASeriesIndex: Integer): TTyProgRun;
    { what one step of a frame costs, ms; NaN (the default) measures it on the
      clock. A test sets it, as upstream's own budget is wall time. }
    property ProgressiveStepCostMs: Double read FProgStepCost write FProgStepCost;
    { For a test or a designer to look inside. nil until the first build. }
    property Build: TTyChartBuild read FBuild;
    { THE visualMap MODEL AS THE LAST BUILD SOLVED IT: the completed
      components, what they wrote on the datum at ARawIndex of series
      ASeriesIndex, that series' visualMetas, and the fill its line took at
      the last render. False / empty where there is none. }
    function VisualMapCount: Integer;
    function VisualMapSpec(AIndex: Integer): TTyVisualMapSpec;
    { [R3-B] visualMap AIndex's model's own inRange / outOfRange / target /
      controller as JSON -- what completeVisualOption made of them and the
      merges kept, the theme's defaults filled in; '{}' for none }
    function VisualMapVisualsJson(AIndex: Integer): string;
    function VisualRow(ASeriesIndex, ARawIndex: Integer;
      out ARow: TTyVisualRow): Boolean;
    function VisualMetas(ASeriesIndex: Integer): TTyVisualMetaArray;
    function VisualLineFill(ASeriesIndex: Integer): TTyVisualLineFill;
    { THE PALETTE AS THE LAST BUILD SOLVED IT [Batch 105]: the colour series
      ASeriesIndex takes (its written one, its palette pick, 0 for none), and
      the colour its datum at ARawIndex takes before any element draws it --
      the series', a visual channel's, the datum's own or the per-datum
      palette's, in upstream's stage order. }
    function PaletteSeriesColour(ASeriesIndex: Integer): TTyChartColor;
    function PaletteDatumColour(ASeriesIndex, ARawIndex: Integer): TTyChartColor;
    { THE DECALS AS THE LAST BUILD SOLVED THEM [Batch 131]: the series'
      style decal, and the one its raw row ARawIndex is drawn with (its own,
      else the series'); Present False for none. }
    function DecalOfSeries(ASeriesIndex: Integer): TTyChartDecal;
    function DecalOfRow(ASeriesIndex, ARawIndex: Integer): TTyChartDecal;
    { THE CHART'S DESCRIPTION [Batch 131]: the aria-label upstream writes on
      the chart's element -- aria.label.description when one is written,
      else the sentence built from the title, the series and their data in
      the locale's words (the port's resourcestrings) with the author's
      aria.label templates over them. '' when aria is off (no `aria` object
      in the option, or enabled false), when aria.label.enabled is false,
      and when the chart has no series. Read off the last layout; for the
      platform's accessibility layer. }
    property AriaDescription: string read GetAriaDescription;
    { ==== THE KEYBOARD AND THE ACCESSIBLE TREE [Batch 144] ====
      Upstream has no keyboard; this is the port's (see
      tyControls.AdvanceChart.KeyNav for the keys). The chart is no tab stop
      unless the host makes it one (TabStop := True): then a click or Tab
      gives it focus and the keys walk the data items.

      KeyboardItem: the item the keyboard holds -- series index, view row
      (DataIndex) and raw row (RawDataIndex) -- or TyChartNoDatum.
      SetKeyboardItem moves it there by series index and RAW data index, as
      the keys would (downplay, highlight, tooltip); False when the series
      is not walked or has no such row. ClearKeyboardItem is Escape. }
    function KeyboardItem: TTyChartDatumRef;
    { [F5] AEdge: ADataIndex is a graph's raw edge index, the item one of
      its edges }
    function SetKeyboardItem(ASeriesIndex, ADataIndex: Integer; AEdge: Boolean = False): Boolean;
    { Escape on the items; [F5] and nothing held anywhere: the stop back to
      the items }
    procedure ClearKeyboardItem;
    { [F5] THE FOCUS STOPS (KeyNav): the stops the chart has, in Tab order;
      the one the keyboard is on; the part of it the keyboard holds (-1:
      none taken up, or the items' stop, where KeyboardItem says).
      SetKeyboardStop goes there as Tab would and takes part APart up (the
      items' stop takes its item up again); False when the chart has no
      such stop or part. }
    function KeyboardStops: TTyKbStopArray;
    function KeyboardStop: TTyKbStop;
    function KeyboardPart: Integer;
    function SetKeyboardStop(const AStop: TTyKbStop; APart: Integer = 0): Boolean;
    { ITyAccessibleHost. The tree under GetAccessibleObject (role larChart,
      named by the first title or rsTyChartTypeChart, described by
      AccessibleSummary): one larListBox per walked series, named with the
      description's phrase for that series, and under it one larListItem per
      row (the first cTyAccMaxItems), named with the description's phrase
      for that row, placed over its element. Rebuilt when the chart has laid
      out again. }
    procedure AccessibleSync;
    function AccessibleFocusedChild: TLazAccessibleObject;
    function AccessibleSelected(AObj: TLazAccessibleObject): Boolean;
    function AccessibleTakeFocus(AObj: TLazAccessibleObject): Boolean;
    { the item object of a series' view row, nil when there is none (after
      AccessibleSync) }
    function AccessibleItem(ASeriesIndex, ARow: Integer): TLazAccessibleObject;
    { [F5] after the series lists the root has a node per component stop
      (a legend a group of check boxes, a toolbox a toolbar, the markers
      and a geo's regions lists, a dataZoom and the timeline sliders, a
      visualMap a group of its handles or pieces, a brush a group): the
      node of a stop's part (APart -1: the component's own), nil for none;
      and how many of the root's children are series lists }
    function AccessibleStopNode(const AStop: TTyKbStop; APart: Integer): TLazAccessibleObject;
    function AccessibleSeriesCount: Integer;
    property AccessibleLink: TTyAccessibleLink read FAccLink;
    { THE COMPONENT AIndex AS THE LAST RENDER LAID IT OUT: Valid is False
      when it is hidden, piecewise, or nothing has rendered. }
    function VisualMapLayout(AIndex: Integer): TTyVisualMapLayout;
    { THE VIEW'S OWN STATE [Batch 116]: the interval and handle ends a drag
      moved, the drag and hover flags, the hover link's items, the element
      states and the indicator where it is now. Alive False before a render. }
    function VisualMapLive(AIndex: Integer): TTyVmLive;
    { what the pointer at (AX, AY) is over of a visualMap, as zrender would
      find it: 'vm0.inRange', 'vm0.outOfRange', 'vm0.handle1', 'vm0.label0',
      'vm0.text1', 'vm0.item3.symbol', 'vm0.item3.label', 'vm0.ends0'; ''
      for nothing of a visualMap }
    function VisualMapRoleAt(AX, AY: Integer): string;
    { a piecewise visualMap's `selected` map as its model holds it, JSON in
      JavaScript's key order; '' for a continuous one }
    function VisualMapSelectedText(AIndex: Integer): string;
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
    function DispatchAction(const APayloadJson: string): Boolean; overload;
    { dispatchAction(payload, silent) [Batch 141]: ASilent publishes no
      event at all -- not the action's, not updated, not the brushselected
      it causes -- and so sends nothing to a connected group.

      BATCH [Batch 141]: a truthy `batch` runs every item as its own payload
      over the outer one's keys (where the item has none or null), `batch`
      null, with ONE update and ONE event {type, escapeConnect, batch:
      [each item's event]}. Taken for highlight, downplay, select, unselect,
      toggleSelect, the five legend actions, dataZoom and brushSelect; any
      other type with a batch answers False. }
    function DispatchAction(const APayloadJson: string; ASilent: Boolean): Boolean; overload;
    { THE COMBINED EXPORT, getConnectedDataURL [Batch 141]: in a connected
      group, every chart of the group (in creation order) rendered with the
      same options, each image at the chart's offset -- its ClientOrigin, in
      logical px -- times the ratio (the options' pixelRatio, else this
      chart's PPI / 96), on a canvas spanning them all;
      `connectedBackgroundColor` fills it first. Not in a connected group:
      this chart's own export. }
    function RenderConnectedToBitmap(const AOptsJson: string = ''): TBGRABitmap;
    procedure SaveConnectedToStream(AStream: TStream; const AOptsJson: string = '');
    { the type as SaveToFile takes it: the options', else the extension }
    procedure SaveConnectedToFile(const AFileName: string; const AOptsJson: string = '');
    function GetConnectedDataURL(const AOptsJson: string = ''): string;
    { A category axis' categorySortInfo.ordinalNumbers as its model holds
      it (a bar race's changeAxisOrder writes it), as JSON; 'null' for none
      [Batch 135] }
    function CategorySortInfoText(const AMainType: string; AIndex: Integer): string;
    { What each axis keeps from one render to the next: the category
      interval's store and the split areas' colours [Batch 101]. Read-only
      to a host; a test reads it. }
    property AxisMemory: TTyAxisMemoryStore read FAxisMemory;
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
    { a sankey link's state record, by link index [Batch 114] }
    function SankeyEdgeStates(ASeriesIndex, AEdge: Integer; out AItem: TTyStItem): Boolean;
    { a chord ribbon's state record, by raw link index [Batch 120] }
    function ChordEdgeStates(ASeriesIndex, AEdge: Integer; out AItem: TTyStItem): Boolean;
    { [F2a] the state record of a series' second set of rows: a graph's edge
      (by its place in the solved edge list), a tree's edge (by the node
      that draws it), a sankey's or a chord's link }
    function EdgeStates(ASeriesIndex, AIndex: Integer; out AItem: TTyStItem): Boolean;
    { a force graph's preserved state and running instance [Batch 114] }
    function GraphForceState(ASeriesIndex: Integer): TTyGraphForceState;
    { [F3b] ONE FRAME OF EVERY RUNNING FORCE ITERATION (a graph's
      `force.layoutAnimation`, true by default): GraphView's 16 ms timer step
      -- each instance stepped once, its nodes and edges laid out from it,
      the picture redrawn. The animation timer calls it every tick while one
      runs; a test steps it by hand. True when any graph stepped. }
    function GraphForceFrame: Boolean;
    function ItemStates(ASeriesIndex, ADataIndex: Integer;
      out AItem: TTyStItem): Boolean;
    { [F2b] a gauge's progress arc, by inner row }
    function PeerStates(ASeriesIndex, ADataIndex: Integer;
      out AItem: TTyStItem): Boolean;
    { [R2-B] FOR TESTS: the keyboard's markers stop taken up at its part
      APart (False: no such part), and let go again }
    function KbTakeMarkerForTest(APart: Integer): Boolean;
    procedure KbLeaveForTest;
    { [R2-L] FOR TESTS: how many row state records series ASeriesIndex
      keeps (none where no element hosts a row, -1 for no such series) }
    function StRowRecordsForTest(ASeriesIndex: Integer): Integer;
    { [R2-I9] FOR TESTS: the hover layer as the next frame brushes it (the
      copies in list order; nil for none) }
    function HoverLayerForTest: TTyPaintList;
    { [R2-I9] FOR TESTS: how many rows of series ASeriesIndex have a state
      list or are on the hover layer }
    function StRowsInStatesForTest(ASeriesIndex: Integer): Integer;
    { [F2b] a marker element of series ASeriesIndex by its name (mp0,
      ml0.from, ma0#label ...): its state record and its index in the list }
    function MarkerStates(ASeriesIndex: Integer; const APart: string;
      out AEl: TTyStElement; out AListIndex: Integer): Boolean;
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
    { [F6a] THE CHART'S CURSOR as upstream names it: the CSS cursor its
      canvas would show after the last pointer event ('default' when the
      pointer is over nothing that sets one). The control's Cursor follows
      it through TyChartCssCursor; 'default' gives the host's own Cursor
      back. }
    property CursorName: string read FCursorName;
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
    { ---- pause [F3b] ---- }
    { zrender's animation.pause / resume (chart.getZr().animation): at the
      chart's clock every driver stops counting time; while paused no frame
      steps (AnimTick does nothing: no clip moves, no progressive chunk is
      drawn, no `rendered`), though a setOption's flush still steps every
      clip once, as upstream's refreshImmediately does. resume adds the
      stretch to each driver's paused time, so a clip goes on from where it
      stood. A second pause, or a resume while running, does nothing. A
      single animator pauses with TTyAnimator.Pause. }
    procedure AnimPause;
    procedure AnimResume;
    function AnimPaused: Boolean;
    { ---- the tooltip's box [Batch 100] ---- }
    { ms; NaN (the default) is the machine's clock -- and only then does the
      timer run. A test sets it and steps TooltipTick. }
    property TooltipNow: Double read FTipNow write FTipNow;
    { every showDelay / hideDelay timer due by ANowMs fires, in order }
    procedure TooltipTick(ANowMs: Double);
    { the box is on screen }
    function TooltipShown: Boolean;
    { what it shows: 'item:<series>:<row>' (a graph's or a sankey's link
      'edge:<series>:<row>', a marker 'markPoint:<host>:<n>'),
      'axis:<the first section's header>', '' when hidden }
    function TooltipShownWhich: string;
    { the pointer the shown box was placed from, and the datum it describes
      (no datum for an axis tooltip) }
    function TooltipAnchor: TPoint;
    { the same, fractional: a showTip's point need not be a pixel's
      [Batch 153] }
    function TooltipAnchorF: TTyPointF;
    { TooltipRichContent._show: set by a show, cleared the moment a hide is
      armed while the box stays up [Batch 153] }
    function TooltipShowFlag: Boolean;
    function TooltipShownDatum: TTyChartDatumRef;
    { the box the last paint drew and the element rect it was placed
      around (invalid: none) -- device px }
    function TooltipBox: TTyRectF;
    function TooltipTargetRect: TTyRectF;
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
    { [R2-I7] the AIndex-th ghost still leaving (0 .. AnimGhostCount - 1),
      its old element at Ghost }
    function AnimGhostAt(AIndex: Integer): TTyChartAnimProxy;
    { THE PROXY AN ELEMENT'S STATES RUN ON [Batch 94]: of series ASeries,
      inner row ARow, the part 'host', 'label', 'guide' (the row's), 'poly'
      or 'area' (a line's, ARow ignored); nil when none is bound }
    function AnimStateProxy(ASeries, ARow: Integer; const APart: string): TTyChartAnimProxy;
    { [F2b] the list index of that part (AnimStateProxy's), -1 for none }
    function StatePartIndex(ASeries, ARow: Integer; const APart: string): Integer;
    { [F2b] that part's state record: its flags, lists, rest and current
      values }
    function StatePartRecord(ASeries, ARow: Integer; const APart: string;
      out AEl: TTyStElement): Boolean;
    { THE AXES' groupTransition [Batch 96]: the proxy of the leaf AAnid
      ('label_20', 'ticks_5', 'line_10', 'line') of axis AAxisKey ('xAxis0',
      'yAxis1'); nil when there is none -- a full update makes them }
    function AnimAxisProxyCount: Integer;
    function AnimAxisProxy(const AAxisKey, AAnid: string): TTyChartAnimProxy;
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
    { upstream's sankeyRoam action, on the sankey ASeriesIndex (-1: every
      sankey): a pan and/or a zoom about a point on its view; the gestures
      dispatch it when `roam` allows (roamTrigger 'global' by default).
      [Batch 114] }
    function SankeyDispatchRoam(const APayload: TTyGraphRoamPayload): Boolean;
    function SankeyRoam(ASeriesIndex: Integer; ADX, ADY: Double): Boolean;
    function SankeyZoom(ASeriesIndex: Integer; AScale, AOriginX, AOriginY: Double): Boolean;
    { the sankey's view (nil: none), owned by the control and gone at the
      next layout [Batch 114] }
    function SankeyView(ASeriesIndex: Integer): TTyGraphView;
    { upstream's dragNode action: node ADataIndex (its raw index) of the
      sankey ASeriesIndex (-1: every sankey) to localX / localY, box
      fractions -- what a node drag dispatches on every move. A position
      not given clears that half. [Batch 114] }
    function SankeyDragNode(ASeriesIndex, ADataIndex: Integer; AHasX: Boolean;
      ALocalX: Double; AHasY: Boolean; ALocalY: Double): Boolean;
    { the solved sankey, for a test to read (Valid False: none) [Batch 114] }
    function SankeySolved(ASeriesIndex: Integer): TTySankeySolved;
    { the solved chord, for a test to read (Valid False: none) [Batch 120] }
    function ChordSolved(ASeriesIndex: Integer): TTyChordSolved;
    { the solved tree, for a test to read (Valid False: none) [Batch 151] }
    function TreeSolved(ASeriesIndex: Integer): TTyTreeSolved;
    { THE GRAPHIC COMPONENT, for a test to read [Batch 122]: the view (its
      elements by id), the model (nil: none), the last build's paint
      elements and the element each came from }
    function GraphicView: TTyGfxView;
    function GraphicModel: TTyGfxModel;
    function GraphicPaintCount: Integer;
    function GraphicPaintElement(AIndex: Integer): TTyChartElement;
    function GraphicPaintSource(AIndex: Integer): TTyGfxEl;
    { THE CUSTOM SERIES, for a test to read [Batch 123]: series
      ASeriesIndex's view (nil: none), the element a paint list entry was
      made from (nil: not a custom series'), and the series' clip in css px
      (False: none) }
    function CustomView(ASeriesIndex: Integer): TTyCustomView;
    function CustomPaintSource(AIndex: Integer): TTyGfxEl;
    function CustomClip(ASeriesIndex: Integer; out ARect: TTyXYWH): Boolean;
    { ---- the drill-downs [Batch 115] ---- }
    { upstream's sunburstRootToNode on the sunburst ASeriesIndex: the view
      root becomes ARow (a row of its tree; 0 the root) -- what a click on a
      piece and on the return circle dispatch; its event follows }
    function SunburstRootToNode(ASeriesIndex, ARow: Integer): Boolean;
    { the sunburst's view root (0: none) }
    function SunburstViewRoot(ASeriesIndex: Integer): Integer;
    { the solved sunburst and treemap, for a test to read (Valid False:
      none) }
    function SunburstSolved(ASeriesIndex: Integer): TTySunburstSolved;
    function TreemapSolved(ASeriesIndex: Integer): TTyTreemapSolved;
    { the treemap's element storage (which rows have a group, a background,
      a content) }
    function TreemapHave(ASeriesIndex: Integer): TTyTreemapHave;
    { upstream's treemapZoomToNode / treemapRootToNode on the treemap
      ASeriesIndex, the target a row of its tree }
    function TreemapZoomToNode(ASeriesIndex, ARow: Integer): Boolean;
    function TreemapRootToNode(ASeriesIndex, ARow: Integer): Boolean;
    { treemapMove / treemapRender: the root at the rect (x, y; its size for
      the render, through scaleLimit) }
    function TreemapMoveTo(ASeriesIndex: Integer; AX, AY, AW, AH: Double;
      AZoom: Boolean): Boolean;
    { the treemap's drill-down is running (TreemapView._state 'animating'):
      a click, a pan, a wheel does nothing }
    function TreemapAnimating(ASeriesIndex: Integer): Boolean;
    { the proxies of a treemap's drill-down, for a test: AKind 'group',
      'bg', 'ct', 'label' (the content's words), 'upper'; nil for none }
    function TreemapAnimProxy(ASeriesIndex, ARow: Integer; const AKind: string): TTyChartAnimProxy;
    function TreemapGhostCount(ASeriesIndex: Integer): Integer;
    { [R2-C] the AIndex-th deleted rect still leaving: its old row and kind
      (0 the background, 1 the content); nil past the end }
    function TreemapGhost(ASeriesIndex, AIndex: Integer; out ARow, AKind: Integer): TTyChartAnimProxy;
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
    { Matrix component AIndex as the last render laid it out, or nil.
      [Batch 145] }
    function MatrixLayout(AIndex: Integer): TTyMatrix;
    { Geo component AIndex as the last render laid it out -- the coordinate
      system with its map's regions and its view -- or nil. Owned by the
      control and gone at the next layout. [Batch 146] }
    function GeoCount: Integer;
    function GeoLayout(AIndex: Integer): TTyGeo;
    { [Batch 152] the geo map series ASeriesIndex is on (its group's own or
      the geo component hosting it), nil: none; where the last build put a
      geo's map picture, and a map series' legend symbols (a circle, and
      after it its label where it has one) }
    function MapGeoOf(ASeriesIndex: Integer): TTyGeo;
    { [Batch 152] a heatmap on a geo's layer as the last build made it }
    function GeoHeatLayer(ASeriesIndex: Integer; out ALayer: TTyHeatLayer): Boolean;
    function GeoDrawRange(AGeo: TTyGeo; out AStart, ACount: Integer): Boolean;
    function MapSymbolRange(ASeriesIndex: Integer; out AStart, ACount: Integer): Boolean;
    { [Batch 148] whether geo AIndex's model holds region AName selected
      (GeoModel.isSelected over option.selectedMap) }
    function GeoSelected(AIndex: Integer; const AName: string): Boolean;
    { [Batch 150] upstream's geoRoam action on geo AIndex (-1: every geo,
      componentType 'geo' with no query): a pan by (ADX, ADY) pixels, or a
      zoom by AScale about (AOriginX, AOriginY). The same path as
      DispatchAction of a geoRoam payload, its georoam event after; not
      gated by `roam`. False when no geo moved -- none laid out, or a zoom
      that is not a positive finite number. }
    function GeoRoam(AIndex: Integer; ADX, ADY: Double): Boolean;
    function GeoZoom(AIndex: Integer; AScale, AOriginX, AOriginY: Double): Boolean;
    { the centre and zoom as geo AIndex's model option says them: the
      option's own until a roam, what the roam wrote back after it (the zoom
      not clamped; GeoLayout(..).Zoom is the one the view uses) }
    function GeoRoamState(AIndex: Integer; out ACentre: TTyGraphCentre;
      out AZoom: Double): Boolean;
    { Polar component AIndex as the last render laid it out -- its centre,
      its two axes and both axis views -- or nil [Batch 111]. }
    function PolarCount: Integer;
    { singleAxis component AIndex as the last render laid it out -- its
      rect, its axis and its view -- or nil [Batch 118]. }
    function SingleCount: Integer;
    function SingleLayout(AIndex: Integer): TTySingle;
    function PolarLayout(AIndex: Integer): TTyPolar;
    { Parallel component AIndex as the last render laid it out -- its box,
      its axes, their places and views, their active intervals -- or nil;
      a parallel series' rows as laid out (Valid False for any other); the
      active intervals of parallelAxis AAxisIndex as its model keeps them
      [Batch 128] }
    function ParallelCount: Integer;
    function ParallelLayout(AIndex: Integer): TTyParallel;
    function ParallelSolvedOf(ASeriesIndex: Integer): TTyParallelSolved;
    function ParallelIntervals(AAxisIndex: Integer): TTyParallelIntervalArray;
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
      tyControls.AdvanceChart.OptionMerge). What upstream keeps in the models
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
    { THE MEDIA UNITS the last merge applied: their indices in the option's
      `media` list as read (-1 the default); empty when none applies or the
      option has none. upstream's _currentMediaIndices. [Batch 107] }
    function MediaIndices: TTyMediaIndices;
    { the queries are asked again at the control's size now -- what a
      resize does; True when units were merged }
    function MediaRecheck: Boolean;
    { ==== THE COORDINATE CONVERSIONS [Batch 110] ====
      Upstream's chart.convertToPixel / convertFromPixel / containPixel. The
      finder is a JSON string naming a main type ('series', 'grid',
      'xAxis', 'calendar' ... -- its first model) or an object of
      <mainType>Index / Id / Name keys, as util/model.ts parseFinder reads
      them. The value is any JSON: a pair for a coordinate system, one
      value for one axis, read with upstream's JavaScript rules (see
      tyControls.AdvanceChart.Convert). The coordinate systems are asked in
      upstream's order -- the grids, the graphs' views, the calendars --
      and the first that answers is the answer.

      The JSON forms answer JSON: a number, a pair (a coordinate that is not
      a finite number prints as null, as JSON.stringify prints it), or ''
      when nothing answered -- or when upstream would have thrown, having
      indexed a null value. The typed forms answer the kind and the
      numbers exactly. A dirty layout is brought up to date first, as
      upstream's synchronous setOption leaves it; a chart that has never
      been rendered answers nothing. }
    function ConvertToPixel(const AFinderJson, AValueJson: string): string; overload;
    function ConvertToPixel(const AFinderJson: string; const AValue: array of Double): TTyConvertResult; overload;
    function ConvertToPixel(const AFinderJson: string; AValue: Double): TTyConvertResult; overload;
    function ConvertToPixelData(AFinder, AValue: TJSONData; AOpt: TJSONData = nil): TTyConvertResult;
    { [Batch 147] the opt: a matrix's `clamp` (0 none, 1 all, 2 body, 3
      corner, MatrixClampOption) }
    function ConvertToPixel(const AFinderJson, AValueJson, AOptJson: string): string; overload;
    function ConvertFromPixel(const AFinderJson, APixelJson: string): string; overload;
    function ConvertFromPixel(const AFinderJson: string; AX, AY: Double): TTyConvertResult; overload;
    function ConvertFromPixel(const AFinderJson: string; AValue: Double): TTyConvertResult; overload;
    function ConvertFromPixelData(AFinder, AValue: TJSONData; AOpt: TJSONData = nil): TTyConvertResult;
    function ConvertFromPixel(const AFinderJson, APixelJson, AOptJson: string): string; overload;
    { upstream's chart.convertToLayout [Batch 147]: the calendars' (a day's
      cell and content rect) and the matrices' (the cells a coord covers,
      ranges and the opt's clamp included, and matrixXYLocatorRange). The
      JSON form answers an object of "rect" (x, y, width, height) and
      "contentRect" or "matrixXYLocatorRange" (a coordinate that is not a
      finite number prints as null), or '' when nothing answered. }
    function ConvertToLayout(const AFinderJson, AValueJson: string;
      const AOptJson: string = ''): string;
    function ConvertToLayoutData(AFinder, AValue: TJSONData;
      AOpt: TJSONData = nil): TTyConvertLayout;
    { Whether any model the finder names contains the point: a grid or a
      cartesian series by its first cartesian's area (edges included), a
      graph, tree or sankey by its view, a pie by the ring of its first
      item; a calendar, a radar, an axis and anything else never. }
    function ContainPixel(const AFinderJson, APointJson: string): Boolean; overload;
    function ContainPixel(const AFinderJson: string; AX, AY: Double): Boolean; overload;
    function ContainPixelData(AFinder, APoint: TJSONData): Boolean;
  published
    { The universal properties the base classes stopped publishing in 4.0 (LCL visibility);
      RTTI order is the 3.0 order. }
    property Version;
    property Enabled;
    property Visible;
    property Font;
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
      test.focus.tabstop.pas will force somebody to decide rather than drift.
      [Batch 62: dataZoom landed and did NOT flip it. Upstream's dataZoom is
      pointer-only -- drag, click, brush, wheel -- with no key binding at all,
      so the reason this line once gave for it no longer holds.]
      [Batch 144: the keyboard landed -- the arrows walk the data items, Enter
      selects, Escape clears -- and it STILL does not flip it, for the reason
      the first lines give: an existing form must not start pulling focus
      off its editors because the library changed. The keyboard is the
      host's to switch on: TabStop := True (in the .lfm or in code) makes a
      click and Tab give the chart focus, and the keys work whenever it has
      focus. The declaration and the constructor stay False together.] }
    property TabStop default False;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
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
    property Color;
    property ParentFont;
    property OnGraphRoam: TTyGraphRoamEvent read FOnGraphRoam write FOnGraphRoam;
    property OnTreeExpandAndCollapse: TTyTreeToggleEvent read FOnTreeToggle write FOnTreeToggle;
    { EVERY chart mouse event, unfiltered -- the published face of ChartOn
      [Batch 84] }
    property OnChartEvent: TTyChartEventHandler read FOnChartEvent write FOnChartEvent;
    property OnTreeRoam: TTyGraphRoamEvent read FOnTreeRoam write FOnTreeRoam;
    property OnSankeyRoam: TTyGraphRoamEvent read FOnSankeyRoam write FOnSankeyRoam;
    property OnDataZoom: TTyDataZoomEvent read FOnDataZoom write FOnDataZoom;
    { saveAsImage's click [Batch 125]: unhandled, the save dialog and
      SaveToFile }
    property OnToolboxSaveAsImage: TTyToolboxSaveEvent read FOnToolboxSaveAsImage
      write FOnToolboxSaveAsImage;
    { [R2-J2] a picture the option names by URL: see TTyChartResolveImageEvent }
    property OnResolveImage: TTyChartResolveImageEvent read FOnResolveImage
      write FOnResolveImage;
    { [R2-I8] an html tooltip's text, read your way: see
      TTyChartTooltipHtmlEvent. Unhandled, the built-in reading runs. }
    property OnTooltipHtml: TTyChartTooltipHtmlEvent read FOnTooltipHtml
      write FOnTooltipHtml;
    { when the enter animations play -- see TTyChartAnimationMode [Batch 89] }
    property AnimationMode: TTyChartAnimationMode read FAnimMode
      write SetAnimMode default camAuto;
    { chart.group [Batch 141]: the name of the connect group this chart is
      in, '' (the default) for none. A group does nothing until
      TyChartConnect connects it. }
    property Group: string read FGroup write FGroup;
    { echarts.init's useCoarsePointer and pointerSize [Batch 142]: when the
      pointer finds nothing, the elements near it -- within a square
      PointerSize logical px wide -- are tried at points around it, ring by
      ring (zrender's findHover). ccpAuto, the default, is upstream's 'auto':
      on for a touch platform, which no desktop widgetset is (see
      TyTouchPlatform); ccpOn and ccpOff force it. PointerSize 0 is off. }
    property CoarsePointer: TTyChartCoarsePointer read FCoarsePointer
      write FCoarsePointer default ccpAuto;
    property PointerSize: Integer read FPointerSize write FPointerSize
      default cTyDefaultPointerSize;
    { echarts.init's useDirtyRect [Batch 142], off by default as upstream's:
      a frame repaints only the rects around what changed -- a hovered
      mark's restyle in the static layer, the dynamic layer's old and new
      ink -- and a window invalidates only those. }
    property UseDirtyRect: Boolean read FUseDirtyRect write SetUseDirtyRect
      default False;
  end;

{ ==== echarts.connect [Batch 141] ====
  Every TTyAdvanceChart is an instance from its creation to its
  destruction. A connected group's charts dispatch, as an action, every
  action event another chart of the group publishes (see ConnectBroadcast).
  TyChartConnect(AGroup) connects a group by name; the array form gives the
  charts the last non-empty group among them, else a new 'g_<n>', and
  connects it; both answer the group. TyChartDisconnect keeps the charts'
  groups and only stops the broadcast. }
function TyChartConnect(const AGroup: string): string; overload;
function TyChartConnect(const ACharts: array of TTyAdvanceChart): string; overload;
procedure TyChartDisconnect(const AGroup: string);
function TyChartGroupConnected(const AGroup: string): Boolean;

{ [F6a] A CSS CURSOR AS AN LCL ONE: pointer crHandPoint, move / all-scroll /
  grabbing crSizeAll, grab crHandPoint, crosshair / cell crCross, text /
  vertical-text crIBeam, not-allowed / no-drop crNo, help crHelp, wait
  crHourGlass, progress crAppStart, ew- / e- / w-resize crSizeWE, ns- / n- /
  s-resize crSizeNS, nwse- / nw- / se-resize crSizeNWSE, nesw- / ne- /
  sw-resize crSizeNESW, col-resize crHSplit, row-resize crVSplit, none
  crNone. A list (`url(...), pointer`) is read by its last entry, the
  keyword fallback. False -- default, auto, '' and a name with no LCL
  counterpart (copy, alias, zoom-in ...) -- is the host's own cursor. }
function TyChartCssCursor(const ACss: string; out ACursor: TCursor): Boolean;

{ [P2] The state patch (StPatchList): a switch that turns it off -- every
  state change builds the list again, the reference it must match -- and
  how many frames it has patched. }
procedure TyAdvChartStPatchForTest(AOn: Boolean);
function TyAdvChartStPatchesForTest: Integer;

{ [R2-L] A progress frame's static layer kept in place (ProgFastPaint): a
  switch that turns it off -- every progress frame paints the static layer
  whole, the reference it must match -- and how many frames it has served. }
procedure TyAdvChartProgFastForTest(AOn: Boolean);
function TyAdvChartProgFastFramesForTest: Integer;
{ [R2-L] The list's components built again on their own (ListTailRebuild):
  a switch that turns it off -- the list is built whole, the reference --
  and how many times it has. }
procedure TyAdvChartListTailForTest(AOn: Boolean);
function TyAdvChartListTailsForTest: Integer;
{ [R2-I9] The list an update built drawn by the next paint as it stands
  (FListFresh): a switch that turns it off -- the paint builds it again, the
  reference it must match -- and how many paints have drawn one. }
procedure TyAdvChartListFreshForTest(AOn: Boolean);
function TyAdvChartListFreshesForTest: Integer;
{ [R2-I9] how many times any chart has built its series list (BuildSeriesList) }
function TyAdvChartListBuildsForTest: Integer;
{ [R2-L] The incremental layer drawn again only where a state changed it
  (ProgLayerRegionRedraw): a switch -- off, the layer is drawn whole, the
  reference -- and how many times it has been. }
procedure TyAdvChartLayerRegionForTest(AOn: Boolean);
function TyAdvChartLayerRegionsForTest: Integer;
{ [R2-I6] The parsed store kept between builds (StoreKeepTake): the fewest
  rows a store has to have to be kept (-1: none is, the reference; the
  default 4096), and how many builds have taken one. }
procedure TyAdvChartStoreKeepForTest(AMinRows: Integer);
function TyAdvChartStoreKeepsForTest: Integer;

implementation

uses
  tyControls.Controller,
  { the frame a dirty-rect window flushes before it is painted, and the
    rects it invalidates [Batch 142] }
  Forms, LCLIntf,
  { Only for the diagnostic resourcestrings -- the same one-way dependency the
    rest of the AdvanceChart family keeps, invisible to a host. }
  tyControls.StrConsts,
  tyControls.AdvanceChart.RichStyle, tyControls.AdvanceChart.JsMath,
  tyControls.AdvanceChart.LinePath, tyControls.AdvanceChart.LabelGuide,
  BGRABitmapTypes, FPImage, FPWriteJPEG, base64,
  tyControls.AdvanceChart.ToolboxDlg,
  tyControls.AdvanceChart.AxisBreak, tyControls.AdvanceChart.DataTransform,
  { ecStat's three transforms, registered by its initialization [Batch 134] }
  tyControls.AdvanceChart.StatTransform,
  { `image://` pictures and their image lists [F6a] }
  tyControls.AdvanceChart.Images;

var
  GStPatchOff: Boolean = False;
  GStPatches: Integer = 0;

procedure TyAdvChartStPatchForTest(AOn: Boolean);
begin
  GStPatchOff := not AOn;
end;

var
  GProgFastOff: Boolean = False;
  GProgFastFrames: Integer = 0;

procedure TyAdvChartProgFastForTest(AOn: Boolean);
begin
  GProgFastOff := not AOn;
end;

function TyAdvChartProgFastFramesForTest: Integer;
begin
  Result := GProgFastFrames;
end;

var
  GListTailOff: Boolean = False;
  GListTails: Integer = 0;
  GListFreshOff: Boolean = False;
  GListFreshes: Integer = 0;
  GListBuilds: Integer = 0;

function TyAdvChartListBuildsForTest: Integer;
begin
  Result := GListBuilds;
end;

procedure TyAdvChartListFreshForTest(AOn: Boolean);
begin
  GListFreshOff := not AOn;
end;

function TyAdvChartListFreshesForTest: Integer;
begin
  Result := GListFreshes;
end;

procedure TyAdvChartListTailForTest(AOn: Boolean);
begin
  GListTailOff := not AOn;
end;

function TyAdvChartListTailsForTest: Integer;
begin
  Result := GListTails;
end;

var
  GLayerRegionOff: Boolean = False;
  GLayerRegions: Integer = 0;

procedure TyAdvChartLayerRegionForTest(AOn: Boolean);
begin
  GLayerRegionOff := not AOn;
end;

function TyAdvChartLayerRegionsForTest: Integer;
begin
  Result := GLayerRegions;
end;

function TyAdvChartStPatchesForTest: Integer;
begin
  Result := GStPatches;
end;

const
  { [R2-I6] a store is kept from this many rows on -- below it the parse
    costs less than the copy is worth keeping -- and no more rows in all
    are kept than this (a second copy of each) }
  cStoreKeepMinRows = 4096;
  cStoreKeepMaxRows = 4000000;

var
  GStoreKeepMinRows: Integer = cStoreKeepMinRows;
  GStoreKeeps: Integer = 0;

procedure TyAdvChartStoreKeepForTest(AMinRows: Integer);
begin
  GStoreKeepMinRows := AMinRows;
end;

function TyAdvChartStoreKeepsForTest: Integer;
begin
  Result := GStoreKeeps;
end;

{ ==================== echarts.connect [Batch 141] ==================== }

const
  cConnectPending = 0;
  cConnectUpdated = 2;

var
  { instances: every chart, in creation order }
  GTyCharts: TFPList = nil;
  { connectedGroups: a group's name, connected when its object is set }
  GTyConnected: TStringList = nil;
  { groupIdBase: +new Date() when first asked, then one up per new group }
  GTyGroupIdBase: Int64 = -1;
  GTyChartSeq: Integer = 0;

{ [F6a] AN AXIS ARROW THAT IS A PICTURE: AxisBuilder's createSymbol(type,
  -w / 2, -h / 2, w, h, stroke, true) -- the image centred to its aspect in
  the arrow's box, turned and placed as the path is. False for any other
  symbol type. }
function TyAxisArrowImage(const AArrow: TTyAxisArrow; out AEl: TTyChartElement): Boolean;
var
  M: TTyMat2D;
  b: TTyRectF;
  q: array[0..3] of TTyPointF;
  x, y: Double;
begin
  AEl := Default(TTyChartElement);
  Result := Copy(AArrow.SymbolType, 1, 8) = 'image://';
  if not Result then Exit;
  b := TyImageCenterBox(AArrow.SymbolType, TyRectF(-AArrow.W / 2, -AArrow.H / 2,
    AArrow.W / 2, AArrow.H / 2));
  M := TyZrLocal(1, 1, AArrow.Rotation, AArrow.X, AArrow.Y);
  TyZrApply(M, b.Left, b.Top, x, y);
  q[0] := TyPointF(x, y);
  TyZrApply(M, b.Right, b.Top, x, y);
  q[1] := TyPointF(x, y);
  TyZrApply(M, b.Right, b.Bottom, x, y);
  q[2] := TyPointF(x, y);
  TyZrApply(M, b.Left, b.Bottom, x, y);
  q[3] := TyPointF(x, y);
  AEl.Style := TyChartStyle;
  AEl.Style.Alpha := 1;
  AEl.Shape := TyShapePolygon(q);
  AEl.Shape.Image := AArrow.SymbolType;
end;

function TyChartCssCursor(const ACss: string; out ACursor: TCursor): Boolean;
var
  s: string;
  k: Integer;
begin
  ACursor := crDefault;
  s := ACss;
  { a list: its last entry, the fallback a keyword always closes it with }
  k := LastDelimiter(',', s);
  if k > 0 then s := Copy(s, k + 1, MaxInt);
  s := LowerCase(Trim(s));
  Result := True;
  if s = 'pointer' then ACursor := crHandPoint
  else if (s = 'move') or (s = 'all-scroll') or (s = 'grabbing') then ACursor := crSizeAll
  else if s = 'grab' then ACursor := crHandPoint
  else if (s = 'crosshair') or (s = 'cell') then ACursor := crCross
  else if (s = 'text') or (s = 'vertical-text') then ACursor := crIBeam
  else if (s = 'not-allowed') or (s = 'no-drop') then ACursor := crNo
  else if s = 'help' then ACursor := crHelp
  else if s = 'wait' then ACursor := crHourGlass
  else if s = 'progress' then ACursor := crAppStart
  else if (s = 'ew-resize') or (s = 'e-resize') or (s = 'w-resize') then ACursor := crSizeWE
  else if (s = 'ns-resize') or (s = 'n-resize') or (s = 's-resize') then ACursor := crSizeNS
  else if (s = 'nwse-resize') or (s = 'nw-resize') or (s = 'se-resize') then ACursor := crSizeNWSE
  else if (s = 'nesw-resize') or (s = 'ne-resize') or (s = 'sw-resize') then ACursor := crSizeNESW
  else if s = 'col-resize' then ACursor := crHSplit
  else if s = 'row-resize' then ACursor := crVSplit
  else if s = 'none' then ACursor := crNone
  else Result := False;
end;

function TyChartGroupConnected(const AGroup: string): Boolean;
var i: Integer;
begin
  Result := False;
  if GTyConnected = nil then Exit;
  i := GTyConnected.IndexOf(AGroup);
  Result := (i >= 0) and (GTyConnected.Objects[i] <> nil);
end;

procedure TyChartSetConnected(const AGroup: string; AOn: Boolean);
var i: Integer;
begin
  if GTyConnected = nil then
  begin
    GTyConnected := TStringList.Create;
    GTyConnected.CaseSensitive := True;
  end;
  i := GTyConnected.IndexOf(AGroup);
  if i < 0 then i := GTyConnected.Add(AGroup);
  if AOn then GTyConnected.Objects[i] := TObject(PtrUInt(1))
  else GTyConnected.Objects[i] := nil;
end;

function TyChartConnect(const AGroup: string): string;
begin
  TyChartSetConnected(AGroup, True);
  Result := AGroup;
end;

function TyChartConnect(const ACharts: array of TTyAdvanceChart): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(ACharts) do
    if (ACharts[i] <> nil) and (ACharts[i].Group <> '') then Result := ACharts[i].Group;
  if Result = '' then
  begin
    if GTyGroupIdBase < 0 then
      GTyGroupIdBase := Round((Now - UnixDateDelta) * MSecsPerDay);
    Result := 'g_' + IntToStr(GTyGroupIdBase);
    Inc(GTyGroupIdBase);
  end;
  for i := 0 to High(ACharts) do
    if ACharts[i] <> nil then ACharts[i].Group := Result;
  TyChartSetConnected(Result, True);
end;

procedure TyChartDisconnect(const AGroup: string);
begin
  TyChartSetConnected(AGroup, False);
end;

{ defined with the actions below; the dataZoom action needs them first }
function VmJsJson(AData: TJSONData): string; forward;
function CopyWithType(APayload: TJSONObject; const AType: string): string; forward;
function JsTruthy(AData: TJSONData): Boolean; forward;
function BatchItemsOf(APayload: TJSONObject): TJSONArray; forward;
function BatchEventHead(APayload: TJSONObject; const AType: string): string; forward;

{ A TURNED NAME OF SEVERAL LINES. DrawTextRotated sets one line; a name with
  a line break came out as one line with the break in it. zrender turns the
  whole block about its anchor: the block's lines stack in the text's own
  frame -- each one aligned on its own, the block aligned vertically as a
  whole -- and the frame turns. ABlockH is the block's measured height, the
  same number the layout reserved its box from. [F1b] }
procedure DrawRotatedNameLines(APainter: TTyPainter; const AText, AFontName: string;
  AFontSize, AWeight: Integer; AColor: TTyColor; AX, AY, ARot: Double;
  AHAlign: TAlignment; AVAlign: TTextLayout; ABlockH: Double);
begin
  { [R2-A] the one routine the turned axis labels and the captions draw
    through too: each line centred on its line box, as zrender's
    textBaseline 'middle' (it was hung from its top) }
  TyDrawTextRotatedLines(APainter, AText, AFontName, AFontSize, AWeight, AColor,
    AX, AY, ARot, AHAlign, AVAlign, ABlockH);
end;

{ [R2-I2] A LEVEL AXIS LABEL'S LINES: each one at the block's alignment
  (zrender's TSpans share the text's textAlign) -- a line shorter than the
  block is not centred in it. One line keeps its centre in its own measured
  box, as it always did. }
function LevelLinesAlign(const AText: string; AH: TTyTextAnchorH): TAlignment;
begin
  if Pos(#10, AText) = 0 then Exit(taCenter);
  case AH of
    tahLeft: Result := taLeftJustify;
    tahRight: Result := taRightJustify;
  else Result := taCenter;
  end;
end;

{ the FPU's traps masked over a stretch that meets NaN (a point off the
  map), and the flags the stretch left cleared again }
function GeoMaskFpu: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure GeoUnmaskFpu(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ encodeHTML }
function GeoEncodeHtml(const AText: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(AText) do
    case AText[i] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      '''': Result := Result + '&#39;';
    else
      Result := Result + AText[i];
    end;
end;

{ [F2a] A GRAPH NODE'S EMPHASIS LABEL show: the item's emphasis.label.show,
  else its own label.show (Series.fillDataTextStyle's defaultEmphasis on a
  data item), else the category's emphasis, else the series' -- whose
  default is true (GraphSeries.defaultOption) }
function GraphEmLabelShow(AItem, ACat, ASeries: TJSONObject): Boolean;
var has: Boolean;
begin
  Result := TyStReadBool([AItem], ['emphasis', 'label', 'show'], has);
  if has then Exit;
  Result := TyStReadBool([AItem], ['label', 'show'], has);
  if has then Exit;
  Result := TyStReadBool([ACat, ASeries], ['emphasis', 'label', 'show'], has);
  if not has then Result := True;
end;

function LnNode(ANode: TJSONObject; const APath: array of string): TJSONData;
var i: Integer; d: TJSONData;
begin
  Result := nil;
  d := ANode;
  for i := 0 to High(APath) do
  begin
    if not (d is TJSONObject) then Exit;
    d := TJSONObject(d).Find(APath[i]);
    if d = nil then Exit;
  end;
  if (d <> nil) and (d.JSONType = jtNull) then Exit;
  Result := d;
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

{ A NaN NEVER MEETS A COMPARISON HERE: an ordered compare of a NaN raises
  with the FPU traps on, and a visualMap can hand a mark a NaN size or
  width. }
function StPositive(AValue: Double): Boolean;
begin
  Result := not IsNan(AValue) and (AValue > 0);
end;

{ an element's values at rest, as the state machine keeps them: zrender's
  default lineWidth 1 where the port draws no stroke, so a state that only
  names a border colour draws a one-pixel border as upstream does }
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
  { [R2-I3] the pen's phase at rest, which a state's dashOffset tweens from }
  TyStSetNum(Result, stkDashOffset, AEl.Style.DashOffsetLogical);
end;

{ the edge data after Graph.update's filterSelf: an edge whose two ends both
  survive the legend }
function GraphEdgeSurvives(const ANodes: TTyGraphNodeArray; const AEdge: TTyGraphEdge): Boolean;
begin
  Result := (AEdge.Source >= 0) and (AEdge.Source <= High(ANodes))
    and (AEdge.Target >= 0) and (AEdge.Target <= High(ANodes))
    and (ANodes[AEdge.Source].Row >= 0) and (ANodes[AEdge.Target].Row >= 0);
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

const
  { a continuous view's parts }
  cVmOut = 1;
  cVmIn = 2;
  cVmThumb0 = 3;
  cVmLabel0 = 5;
  cVmText0 = 7;
  { a piecewise one's: 100 + 2 * piece (+ 1 its label), 1000 + j an ends text }
  cVmPiece = 100;
  cVmEnds = 1000;
  { '≈ ' }
  cVmAbout = #$E2#$89#$88' ';

{ JSON.stringify of a parsed value: numbers as JavaScript prints them (a
  not-a-number or an infinity is null), an object's keys in JavaScript's
  order -- integer-like first, ascending, then the rest as inserted }
function VmJsJson(AData: TJSONData): string;
var
  i: Integer;
  keys: TTyLegendNames;
  v: Double;
begin
  if AData = nil then Exit('null');
  case AData.JSONType of
    jtNumber:
      begin
        v := AData.AsFloat;
        if IsNan(v) or IsInfinite(v) then Result := 'null'
        else Result := TyJsNumberToString(v);
      end;
    jtString: Result := '"' + StringToJSONString(AData.AsString) + '"';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtArray:
      begin
        Result := '[';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + VmJsJson(AData.Items[i]);
        end;
        Result := Result + ']';
      end;
    jtObject:
      begin
        keys := TyJsKeyOrder(TJSONObject(AData));
        Result := '{';
        for i := 0 to High(keys) do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + '"' + StringToJSONString(keys[i]) + '":'
            + VmJsJson(TJSONObject(AData).Find(keys[i]));
        end;
        Result := Result + '}';
      end;
  else
    Result := 'null';
  end;
end;

procedure ConvertUnmask(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  { the SSE flags too, which ClearExceptions leaves standing on this CPU }
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ extend({}, payload) with its type set: an action's event object, as
  JSON in JavaScript's key order and number text [Batch 141] }
function CopyWithType(APayload: TJSONObject; const AType: string): string;
var o: TJSONObject;
begin
  o := TJSONObject(APayload.Clone);
  try
    o.Strings['type'] := AType;
    Result := VmJsJson(o);
  finally
    o.Free;
  end;
end;

{ doDispatchAction's batch items: map(payload.batch, item => defaults(
  extend({}, item), payload)), each item's `batch` then null. A batch that is
  no list maps to none; an item that is no object is an empty one.
  [Batch 141] }
function BatchItemsOf(APayload: TJSONObject): TJSONArray;
var
  arr, x: TJSONData;
  item: TJSONObject;
  i, j: Integer;
  nm: string;
begin
  Result := TJSONArray.Create;
  arr := APayload.Find('batch');
  if not (arr is TJSONArray) then Exit;
  for i := 0 to arr.Count - 1 do
  begin
    if TJSONArray(arr).Items[i] is TJSONObject then
      item := TJSONObject(TJSONArray(arr).Items[i].Clone)
    else
      item := TJSONObject.Create;
    for j := 0 to APayload.Count - 1 do
    begin
      nm := APayload.Names[j];
      x := item.Find(nm);
      if (x = nil) or (x.JSONType = jtNull) then
        item.Elements[nm] := APayload.Items[j].Clone;
    end;
    item.Elements['batch'] := TJSONNull.Create;
    Result.Add(item);
  end;
end;

{ the batched event's head: {type, escapeConnect, batch: ...}, the
  escapeConnect only when the payload has one }
function BatchEventHead(APayload: TJSONObject; const AType: string): string;
begin
  Result := '{"type":"' + StringToJSONString(AType) + '"';
  if APayload.IndexOfName('escapeConnect') >= 0 then
    Result := Result + ',"escapeConnect":' + VmJsJson(APayload.Find('escapeConnect'));
  Result := Result + ',"batch":[';
end;

function TipEventBlank: TTyTipEvent;
begin
  Result := Default(TTyTipEvent);
  Result.X := NaN;
  Result.Y := NaN;
  Result.Datum := TyChartNoDatum;
  Result.Element := -1;
end;

{ the action's payload as its event carries it: the event's name for its
  type }
function TbEventJson(APayload: TJSONObject; const AName: string): string;
var
  o: TJSONObject;
  i: Integer;
begin
  o := TJSONObject.Create;
  try
    o.Add('type', AName);
    for i := 0 to APayload.Count - 1 do
      if APayload.Names[i] <> 'type' then
        o.Add(APayload.Names[i], APayload.Items[i].Clone);
    Result := TyTbJson(o);
  finally
    o.Free;
  end;
end;

{ THE METHODS, BY FEATURE: one include file each; inside a file they keep the order
  they had in this unit. What stays above is the unit's own routines and the helpers
  more than one feature shares. }
{$I tyControls.AdvanceChart.Control.Option.inc}
{$I tyControls.AdvanceChart.Control.Build.inc}
{$I tyControls.AdvanceChart.Control.Paint.inc}
{$I tyControls.AdvanceChart.Control.DataZoom.inc}
{$I tyControls.AdvanceChart.Control.VisualMap.inc}
{$I tyControls.AdvanceChart.Control.Geo.inc}
{$I tyControls.AdvanceChart.Control.Hierarchy.inc}
{$I tyControls.AdvanceChart.Control.Series.inc}
{$I tyControls.AdvanceChart.Control.Legend.inc}
{$I tyControls.AdvanceChart.Control.Labels.inc}
{$I tyControls.AdvanceChart.Control.Progressive.inc}
{$I tyControls.AdvanceChart.Control.Tooltip.inc}
{$I tyControls.AdvanceChart.Control.Events.inc}
{$I tyControls.AdvanceChart.Control.States.inc}
{$I tyControls.AdvanceChart.Control.Actions.inc}
{$I tyControls.AdvanceChart.Control.Anim.inc}
{$I tyControls.AdvanceChart.Control.Keyboard.inc}
{$I tyControls.AdvanceChart.Control.Graphic.inc}
{$I tyControls.AdvanceChart.Control.Export.inc}
{$I tyControls.AdvanceChart.Control.Timeline.inc}
{$I tyControls.AdvanceChart.Control.Toolbox.inc}
{$I tyControls.AdvanceChart.Control.Brush.inc}
{$I tyControls.AdvanceChart.Control.Thumbnail.inc}

finalization
  FreeAndNil(GTyCharts);
  FreeAndNil(GTyConnected);
end.
