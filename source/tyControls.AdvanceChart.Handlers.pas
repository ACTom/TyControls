unit tyControls.AdvanceChart.Handlers;
{$mode objfpc}{$H+}
{ Named handlers and template strings -- what a function-valued ECharts option
  becomes when the host cannot run JavaScript.

  THE PROBLEM. Roughly 1,212 nodes in the option schema accept a function, and
  `formatter` alone is 539 of them. A closure cannot live in serialised option
  text, so an option tree needs another answer, and there are three:

    a TEMPLATE STRING   formatter: '{b}: {c} ({d}%)'
        ECharts' own syntax, and it alone covers the great majority of the 539
        formatters. Nothing has to be registered and nothing has to be compiled.

    a NAMED HANDLER     formatter: '@SalesFormatter'
        Resolved through the registry below to a Pascal method. Streamable,
        visible at design time, and the same shape ECharts 6 chose for
        registerCustomSeries -- a NAME plus a payload rather than an inline
        closure.

    a real EVENT        for the handful of cases that belong on the control
        rather than in the option text.

  A literal `function(...)` pasted from a JS example is REJECTED by the option
  reader with a message naming these two, rather than silently ignored: a
  formatter that quietly does nothing is a chart that quietly lies.

  THE PARAMETER RECORD IS v6.1's, NOT v5's. ECharts 6.1 changed
  tooltip.valueFormatter's second parameter from the dataZoom-FILTERED index to
  the index into the original input data (changelog v6.1.0: "changed from
  dataIndex ... to rawDataIndex"). Both are carried here from day one. Adopting
  it now costs nothing; migrating it once handlers exist in user code is the
  most expensive kind of change to absorb.

  LCL-free: SysUtils, Classes, Math and the AdvanceChart units. }
interface
uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
  tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Shape;

type
  { What a handler is given, and what a template expands from. Modelled on
    ECharts' formatter params (en/option/partial/formatter.md). }
  TTyChartCallbackParams = record
    ComponentType: string;      // 'series' for everything a series draws
    SeriesType: string;         // 'bar', 'line', ...
    { '' for every datum but a graph's, where it is 'node' or 'edge' --
      upstream's params.dataType, which is how a formatter tells a link from
      the node that shares its row number. }
    DataType: string;
    SeriesIndex: Integer;
    SeriesName: string;         // the a placeholder
    Name: string;               // data or category name -- the b placeholder
    { The index into the data currently being SHOWN, after dataZoom filtering. }
    DataIndex: Integer;
    { The index into the ORIGINAL input data. See the unit header: v6.1 made
      this the one a value formatter receives, and carrying both means a handler
      can ask for whichever it actually means. }
    RawDataIndex: Integer;
    { The datum's dimensions. One entry for a plain value; more for a scatter,
      a candlestick or a dataset row. }
    Values: TTyDoubleArray;
    { Parallel to Values when the data came from a dataset, so a template can
      say @price instead of counting columns. Empty otherwise. }
    DimensionNames: TTyStringArray;
    { THE ITEM AS WRITTEN, when the store kept it (rshNone otherwise): the
      template's c prints this, not Values. RawCells and RawTypes run parallel
      to Values -- each value's own cell and its dimension's type -- for the
      tooltip's value cell. Empty when there is no raw item. }
    Raw: TTyRawItem;
    RawCells: TTyDataValueArray;
    RawTypes: array of TTyDimType;
    { The d placeholder. HasPercent separates "zero per cent" from "this series
      has no percentage", which is most of them. }
    Percent: Double;
    HasPercent: Boolean;
    Color: TTyChartColor;
    { The e placeholder. ECharts documents it as existing but never says what it
      is per series type, so it is a slot the caller fills rather than something
      invented here. }
    Extra: string;
    { 'normal' for a label drawn in its resting state -- upstream's
      params.status. }
    Status: string;
    { An axis-pointer label's axis: 'x', 'y', 'radius', 'angle', 'single' and
      the axis's index among its kind. }
    AxisDimension: string;
    AxisIndex: Integer;
    { A time axis label's level (upstream's extra.level); HasLevel False is
      the null every other axis passes. }
    Level: Integer;
    HasLevel: Boolean;
    { THE VALUE AS JavaScript's String() PRINTS IT -- an array joined by
      commas, 'undefined', 'null' -- which is what `{c}` and every upstream
      function formatter that concatenates params.value would show. }
    ValueText: string;
    { AN EVENT'S params beyond a formatter's [Batch 84]: the component's
      subtype ('bar' for a bar series, '' where upstream has none) and index,
      the series' own id where the option wrote one, an axis event's
      targetType ('axisLabel', 'axisName') and tickIndex (-1: none), and a
      series-level event's selfType ('line' for a line's polyline). }
    ComponentSubType: string;
    ComponentIndex: Integer;
    SeriesId: string;
    TargetType: string;
    TickIndex: Integer;
    SelfType: string;
    { What the chart would have printed had there been no formatter -- the
      axis label's own text, a dataZoom label's valueStr. '' where upstream
      has no such thing. }
    DefaultText: string;
    { A GRAPHIC ELEMENT'S `info` [Batch 122], as JSON text ('' where the
      element has none): what its ECData's eventData carries into an event }
    Info: string;
    { A MATRIX CELL'S locator pair, upstream's `coord` in its eventData and
      `xyLocator` in its tooltip's params; empty elsewhere [Batch 147] }
    Coord: TTyDoubleArray;
    { A GEO REGION'S eventData.region [Batch 148]: its region option as
      JSON text (an empty object where the model map holds none); '' everywhere else.
      A geo event's geoIndex is its ComponentIndex. }
    Region: string;
    { A TREEMAP BREADCRUMB ITEM'S eventData.nodeData [F2a]: {dataIndex,
      name} as JSON text; '' everywhere else }
    NodeData: string;
    { A BREAK'S END [F4a]: an axis label formatter's extra.break -- 'start'
      or 'end', and the break's two ends as the extent clamps them (on a log
      axis as its lookup brings them back) -- and an axis label event's
      eventData.break, whose ends are the same (upstream writes no type
      there; the word is the tick's all the same). '' and not-a-number
      everywhere else. }
    BreakType: string;
    BreakStart, BreakEnd: Double;
    { A SUNBURST'S OR A TREEMAP'S NODE [R2-E]: upstream's treePathInfo --
      every node from the virtual root down to this one, {name, dataIndex,
      value} -- as JSON text; '' everywhere else (the treemap's
      treeAncestors is the same list) }
    TreePathInfo: string;
    { [R2-J3] A TOOLTIP FORMATTER'S params.marker: the richText marker
      upstream's TooltipMarkupStyleCreator writes -- an empty rich token of
      the marker's style name, then two spaces (TyTooltipRichMarker) --
      for which a dot of the item's colour is drawn wherever the formatter's
      text carries it. The box is richText here (AdvanceChart.Tooltip), so this
      is not the html span a browser's formatter is handed. '' everywhere
      else. }
    Marker: string;
  end;
  TTyChartParams = array of TTyChartCallbackParams;

  { A named formatter. `of object` rather than a plain procedure or a reference:
    method pointers are streamable and visible at design time, which is what a
    registry addressed by name from serialised text needs. }
  TTyChartFormatter = function(const AParams: TTyChartParams): string of object;

  { ==== tooltip.position as a function [Batch 100] ====

    Upstream calls `position(point, params, dom, rect, size)` and reads
    whatever comes back the way it reads the option: an array of two
    numbers or percent strings, a word ('inside', 'top', 'left', 'right',
    'bottom'), an object of left / top / right / bottom, or nothing (the
    default placement). A function's answer has to be a value, not a string,
    so a position handler has its own type and its own registry. }

  { One number-or-text a position holds: what parsePercent is handed. }
  TTyChartPosValueKind = (cpvAbsent, cpvNumber, cpvText);
  TTyChartPosValue = record
    Kind: TTyChartPosValueKind;
    Num: Double;
    Text: string;
  end;

  TTyChartTooltipPosKind = (ctpDefault, ctpPoint, ctpSide, ctpBox);
  { THE FOUR FORMS. ctpPoint: X, Y (the array); ctpSide: Side (the word,
    any text -- one upstream does not know places the box at nought);
    ctpBox: Left, Top, Right, Bottom (getLayoutRect's; the width and height
    are always the content's); ctpDefault: follow the pointer. }
  TTyChartTooltipPos = record
    Kind: TTyChartTooltipPosKind;
    X, Y: TTyChartPosValue;
    Side: string;
    Left, Top, Right, Bottom: TTyChartPosValue;
  end;

  { What upstream hands the function, in device px of the chart: the
    pointer; the params (one record for an item tooltip, every series' for
    an axis one -- IsAxis); the hovered element's bounding rect (HasRect
    False under an axis trigger, where upstream passes undefined); and
    size.viewSize / size.contentSize. The `dom` argument has no analogue
    here: the box is drawn, not a DOM node. }
  TTyChartTooltipPosArgs = record
    PointX, PointY: Double;
    Params: TTyChartParams;
    IsAxis: Boolean;
    HasRect: Boolean;
    RectX, RectY, RectW, RectH: Double;
    ViewW, ViewH: Double;
    ContentW, ContentH: Double;
  end;

  TTyChartPositionHandler = function(
    const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos of object;

  { ==== series.labelLayout as a function [Batch 103] ====

    LabelManager calls `labelLayout(params)` once per label on every layout
    pass and reads what comes back as the option object it stands for: x / y
    (px or a percent of the chart, through parsePercent), dx / dy, rotate
    (degrees), align / verticalAlign, fontSize, width / height, moveOverlap,
    hideOverlap, draggable and labelLinePoints. Nothing at all is an empty
    layout. The answer is a value, so this has its own type and registry. }

  { What the function is given, in device px of the chart: the label's
    datum (DataIndex is ecData.dataIndex, the index into the data as SHOWN),
    its series and dataType, its text, its host's rect (HasRect False where
    there is none), the label's own rect as it was laid out before the layout
    (LabelRectX..H), the label STYLE's align / verticalAlign ('' when the
    label did not set one -- an attached label's alignment comes from its
    position, which is not the style's), and a copy of its label line's
    points (empty without one). }
  TTyChartLabelLayoutArgs = record
    DataIndex, SeriesIndex: Integer;
    DataType: string;
    Text: string;
    HasRect: Boolean;
    RectX, RectY, RectW, RectH: Double;
    LabelRectX, LabelRectY, LabelRectW, LabelRectH: Double;
    Align, VerticalAlign: string;
    LabelLinePoints: TTyPointFArray;
    { [R2-J2] THE CHART'S SIZE in CSS px -- myChart.getWidth() / getHeight(),
      which a page's labelLayout function closes over (pie-labelLine-adjust
      tells left from right by it) -- and the device px per CSS px the rects
      above are scaled by (an answer's x / y are CSS px) }
    ChartWidth, ChartHeight: Double;
    Scale: Double;
  end;

  { WHAT A labelLayout SAYS -- the object form read off the option, or a
    function's answer. Every field is "absent" in the zero value: X / Y
    absent (cpvAbsent), no dx, dy, rotate or font size, '' for the words. }
  TTyChartLabelLayout = record
    X, Y: TTyChartPosValue;
    HasDx, HasDy: Boolean;
    Dx, Dy: Double;
    HasRotate: Boolean;
    { degrees }
    Rotate: Double;
    HasAlign, HasVerticalAlign: Boolean;
    Align, VerticalAlign: string;
    HasFontSize: Boolean;
    FontSize: Double;
    HasWidth, HasHeight: Boolean;
    Width, Height: Double;
    { 'shiftX', 'shiftY' or anything else (no move) }
    MoveOverlap: string;
    HideOverlap: Boolean;
    Draggable: Boolean;
    HasLabelLinePoints: Boolean;
    LabelLinePoints: TTyPointFArray;
  end;

  TTyChartLabelLayoutHandler = function(
    const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout of object;

  { ==== a custom toolbox feature's onclick [Batch 125] ====
    `toolbox.feature.myXxx.onclick: '@Name'` -- upstream calls the function
    with the feature as `this` and (ecModel, api, iconName). Here: the chart,
    the feature's name and the icon's (the feature's own name unless its
    `icon` is a map of several). }
  TTyChartToolboxHandler = procedure(ASender: TObject;
    const AFeature, AIcon: string) of object;

  { ==== the data view's optionToContent / contentToOption [spec 237] ====

    `toolbox.feature.dataView.optionToContent: '@Name'` -- upstream calls
    it with api.getOption() when the view opens and shows what it answers
    (an html string, or a DOM node) in place of the textarea. Here the
    handler is given the chart's option as GetOptionJson writes it (the
    same shape) and answers a TTyChartDataViewContent in one of four forms:

      cdvHtml     Text is html, as upstream's string is. Each <table> in it
                  is a grid on the dialog's Table page (a row in <thead>, or
                  a first row of <th> cells, is the grid's header); the text
                  outside the tables, read as the tooltip reads html
                  (tyControls.AdvanceChart.TipHtml), is on the Text page.
      cdvText     Text is plain text, shown as written on the Text page.
      cdvTable    Tables are the grids, with no html to write.
      cdvControl  Control is a TWinControl the handler made (unparented):
                  the dialog shows it in place of the pages. One with no
                  Owner is freed by the chart when the view is done.

    `contentToOption: '@Name'` -- upstream calls it on Refresh with the
    view's DOM and api.getOption() and merges what it answers through the
    changeDataView action. Here the handler is given the content as the
    user left it -- the same record, its Tables read back from the grids
    (and an html content's Text the html with the cells the user changed
    rewritten, as the edited DOM's innerHTML would be), a text content's
    Text from the memo, a control as it is -- and the option, and answers the
    option to merge as JSON text; '' (or null) is upstream's falsy answer:
    nothing is merged. Under the default view (no optionToContent handler)
    it is given Kind cdvText and the table text the view read back.

    Refresh reads back only when BOTH are given or neither is -- upstream's
    rule, "Data change is ignored" otherwise. A '@Name' nobody registered is
    what upstream sees for a value that is not a function: given, but not
    called (an optionToContent so named leaves the default view; a
    contentToOption so named leaves Refresh to parse the default text). }
  TTyChartDataViewKind = (cdvHtml, cdvText, cdvTable, cdvControl);
  TTyChartDataViewRows = array of TTyStringArray;
  TTyChartDataViewTable = record
    { a <caption>'s text: the heading above the grid ('' for none) }
    Caption: string;
    { the header row's cells; empty for a table with none }
    Header: TTyStringArray;
    { every other row, its cells }
    Rows: TTyChartDataViewRows;
  end;
  TTyChartDataViewTables = array of TTyChartDataViewTable;
  TTyChartDataViewContent = record
    Kind: TTyChartDataViewKind;
    Text: string;
    Tables: TTyChartDataViewTables;
    { cdvControl: a TWinControl (TObject here: this unit stays LCL-free) }
    Control: TObject;
  end;
  TTyChartOptionToContent = function(
    const AOption: string): TTyChartDataViewContent of object;
  TTyChartContentToOption = function(const AContent: TTyChartDataViewContent;
    const AOption: string): string of object;

  { ==== axisPointer.link's mapper [Batch 141] ====
    `axisPointer.link[i].mapper: '@Name'` -- upstream calls it with the
    source axis' value and the two axes as makeMapperParam builds them, and
    parses what it answers with the TARGET axis' scale (a category or time
    axis rounds it). AxisName and AxisId are the models' -- the auto ones
    ('series' + NUL + index, NUL + name + NUL + n) when the option wrote
    none. }
  TTyChartMapperAxis = record
    AxisDim: string;
    AxisIndex: Integer;
    AxisName: string;
    AxisId: string;
  end;

  TTyChartAxisPointerMapper = function(AValue: Double;
    const ASource, ATarget: TTyChartMapperAxis): Double of object;

  { ==== per-item visual callbacks [R2-J2] ====

    A series' `symbol`, `symbolSize`, `symbolRotate` and `symbolOffset`, and
    its `itemStyle.color`, may be functions upstream: visual/symbol.ts calls
    `cb(rawValue, params)` for every item and visual/style.ts calls
    `colorCallback(params)`. Written as '@Name', the handler registered under
    that name is called the same way -- AParams is the item's getDataParams,
    whose Raw is rawValue -- and answers the value the option would have held:
    a number, an array, a string. nil is upstream's undefined. The caller frees
    the answer. }
  TTyChartVisualHandler = function(
    const AParams: TTyChartCallbackParams): TJSONData of object;

  { [R2-J3] WHAT ONE SERIES' VISUAL CALLBACKS ANSWERED, per raw index: the
    symbol keys (an object of the symbol / symbolSize / symbolRotate /
    symbolOffset a callback answered, nil where none did -- read as the
    option is, TySymbolSpecOf) and the colour. A builder lays the symbol
    answers over the series' spec and under the item's own keys (and a
    graph's category), as seriesSymbolTask's item visuals lie under
    dataSymbolTask's. }
  TTyItemCallbacks = class
  public
    Sym: array of TJSONObject;
    Col: array of TTyChartColor;
    ColSet: array of Boolean;
    HasSym, HasCol: Boolean;
    destructor Destroy; override;
    { nil: no answer for the item }
    function SymOf(ARaw: Integer): TJSONObject;
    function ColOf(ARaw: Integer; out AColour: TTyChartColor): Boolean;
  end;

{ ---- the registry ---- }
{ Registering the same name twice REPLACES, so a form reopened at design time
  does not accumulate stale handlers. }
procedure TyChartRegisterFormatter(const AName: string; AHandler: TTyChartFormatter);
procedure TyChartUnregisterFormatter(const AName: string);
function TyChartFindFormatter(const AName: string; out AHandler: TTyChartFormatter): Boolean;
{ The registered names, for a design-time editor to offer. }
procedure TyChartFormatterNames(AList: TStrings);
procedure TyChartClearFormatters;

{ ---- tooltip.position handlers [Batch 100] ----
  The same rules as the formatters': a name, registered once, replaced when
  registered again; a separate registry because the answer is a position. }
procedure TyChartRegisterPositionHandler(const AName: string;
  AHandler: TTyChartPositionHandler);
procedure TyChartUnregisterPositionHandler(const AName: string);
function TyChartFindPositionHandler(const AName: string;
  out AHandler: TTyChartPositionHandler): Boolean;
procedure TyChartClearPositionHandlers;
{ Runs the handler '@Name' names. False -- and the default placement in
  APos -- when nobody registered it. }
function TyChartRunPositionHandler(const ASpec: string;
  const AArgs: TTyChartTooltipPosArgs; out APos: TTyChartTooltipPos): Boolean;
{ ---- labelLayout handlers [Batch 103] ----
  The same rules again: a name, registered once, replaced when registered
  again. }
procedure TyChartRegisterLabelLayoutHandler(const AName: string;
  AHandler: TTyChartLabelLayoutHandler);
procedure TyChartUnregisterLabelLayoutHandler(const AName: string);
function TyChartFindLabelLayoutHandler(const AName: string;
  out AHandler: TTyChartLabelLayoutHandler): Boolean;
procedure TyChartClearLabelLayoutHandlers;
{ Runs the handler '@Name' names. False -- and an empty layout in
  ALayout -- when nobody registered it. }
function TyChartRunLabelLayoutHandler(const ASpec: string;
  const AArgs: TTyChartLabelLayoutArgs; out ALayout: TTyChartLabelLayout): Boolean;

{ ---- toolbox onclick handlers [Batch 125] ----
  The same rules again. }
procedure TyChartRegisterToolboxHandler(const AName: string;
  AHandler: TTyChartToolboxHandler);
procedure TyChartUnregisterToolboxHandler(const AName: string);
function TyChartFindToolboxHandler(const AName: string;
  out AHandler: TTyChartToolboxHandler): Boolean;
procedure TyChartClearToolboxHandlers;

{ ---- the data view's optionToContent / contentToOption [spec 237] ----
  The same rules again: a name ('@' left off), registered once, replaced
  when registered again. }
procedure TyChartRegisterOptionToContent(const AName: string;
  AHandler: TTyChartOptionToContent);
procedure TyChartUnregisterOptionToContent(const AName: string);
function TyChartFindOptionToContent(const AName: string;
  out AHandler: TTyChartOptionToContent): Boolean;
procedure TyChartClearOptionToContents;
procedure TyChartRegisterContentToOption(const AName: string;
  AHandler: TTyChartContentToOption);
procedure TyChartUnregisterContentToOption(const AName: string);
function TyChartFindContentToOption(const AName: string;
  out AHandler: TTyChartContentToOption): Boolean;
procedure TyChartClearContentToOptions;

{ axisPointer.link mappers [Batch 141], by name, '@' left off as for the
  others; registering a name again replaces it }
procedure TyChartRegisterAxisPointerMapper(const AName: string;
  AHandler: TTyChartAxisPointerMapper);
procedure TyChartUnregisterAxisPointerMapper(const AName: string);
function TyChartFindAxisPointerMapper(const AName: string;
  out AHandler: TTyChartAxisPointerMapper): Boolean;
procedure TyChartClearAxisPointerMappers;

{ ---- per-item visual handlers [R2-J2] ----
  The formatters' rules: a name, registered once, replaced when registered
  again. }
procedure TyChartRegisterVisualHandler(const AName: string;
  AHandler: TTyChartVisualHandler);
procedure TyChartUnregisterVisualHandler(const AName: string);
function TyChartFindVisualHandler(const AName: string;
  out AHandler: TTyChartVisualHandler): Boolean;
procedure TyChartClearVisualHandlers;
{ Runs the handler ASpec ('@Name') names: its answer (the caller's to free),
  nil when nobody registered it or it answered undefined. }
function TyChartRunVisualHandler(const ASpec: string;
  const AParams: TTyChartCallbackParams): TJSONData;

{ Building an answer: a number, a text ('50%', 'center'), nothing. }
function TyChartPosNum(AValue: Double): TTyChartPosValue;
function TyChartPosText(const AText: string): TTyChartPosValue;
function TyChartPosAbsent: TTyChartPosValue;

{ ---- template strings ---- }
{ String.prototype.replace(pattern, replacement) with a STRING pattern: the
  first occurrence only, and the replacement read the way JavaScript reads
  it -- '$$' is a dollar, '$&' the matched text, '$`' what came before it and
  "$'" what comes after. There are no groups, so '$1' stays as written. }
function TyJsReplaceFirst(const ASubject, APattern, AReplacement: string): string;

{ upstream's formatTpl. AVars[s] holds series s's texts in the order of the
  template letters a, b, c (and d when AVarCount is 4). First every bare
  letter token -- its first occurrence -- becomes the series-0 form, `{a}` to
  `{a0}`; then, for each series in turn, the first `{a0}`, `{b0}` ... of that
  series is replaced. Everything else stays as written: a second `{c}`, an
  `{e}`, an index past the series count, a `{d}` where there is no
  percentage. }
function TyJsFormatTpl(const ATemplate: string; AVarCount: Integer;
  const AVars: array of TTyStringArray): string;

{ A tooltip formatter template: formatTpl over one entry per series. The
  letters are a (series name), b (name), c (the value -- several joined with
  ',' as JavaScript prints an array) and, for a series that has one, d (the
  percentage). @dimension forms are NOT expanded here; upstream only expands
  them in labels. }
function TyChartFormatTemplate(const ATemplate: string;
  const AParams: TTyChartParams; AEncode: Boolean = False): string;

{ [R2-I8] zrender's encodeHTML: & < > " ' written as &amp; &lt; &gt; &quot;
  &#39; -- what TooltipView's formatTpl(html, params, true) does to every
  value it puts in a template, in both render modes. }
function TyChartEncodeHtml(const AText: string): string;

{ ---- resolving an option value ---- }
{ ASpec is whatever the option tree holds: '@Name' for a registered handler,
  anything else as a template. Returns False only when a named handler was asked
  for and is not registered -- in which case AText carries a message saying so,
  because a formatter that silently does nothing is worse than a visible error. }
function TyChartResolveText(const ASpec: string; const AParams: TTyChartParams;
  out AText: string; AEncode: Boolean = False): Boolean;

{ True when ASpec names a handler rather than being a template. }
function TyChartIsHandlerRef(const ASpec: string): Boolean;

{ Runs the handler ASpec names ('@Name') on AParams -- for every formatter site
  whose template language is not the tooltip's. A name nobody registered
  answers the message saying so, never an empty text. }
function TyChartRunHandler(const ASpec: string;
  const AParams: TTyChartParams): string;

{ One params record, the shape a formatter of a single datum is given. }
function TyChartOneParams(const AParams: TTyChartCallbackParams): TTyChartParams;

{ A record with every index at -1 and nothing else set -- the start of every
  params a site builds. }
function TyChartBlankParams: TTyChartCallbackParams;

{ A number as a template or a label prints a raw value: JavaScript's String(),
  exact -- 0.30000000000000004, 1e-7, 1e+21 -- and never grouped. A missing
  value (not-a-number) is ''. }
function TyChartValueText(AValue: Double): string;

{ The OLD rounding format, six decimals and no exponent below 1e17. Only the
  radar's ring labels still use it: their values are not rounded the way
  upstream rounds an axis', and full precision would print the noise. }
function TyChartNumToStr(AValue: Double): string;

implementation

uses
  tyControls.AdvanceChart.Scale,
  { Only for the diagnostic resourcestrings; kept out of the interface uses so
    the dependency stays one-way and invisible to hosts. }
  tyControls.StrConsts;

type
  TFormatterEntry = record
    Name: string;
    Handler: TTyChartFormatter;
  end;

var
  GFormatters: array of TFormatterEntry;

type
  TVisualEntry = record
    Name: string;
    Handler: TTyChartVisualHandler;
  end;

var
  GVisuals: array of TVisualEntry;

function IndexOfVisual(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GVisuals) do
    if SameText(GVisuals[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure TyChartRegisterVisualHandler(const AName: string;
  AHandler: TTyChartVisualHandler);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfVisual(AName);
  if i < 0 then
  begin
    i := Length(GVisuals);
    SetLength(GVisuals, i + 1);
    GVisuals[i].Name := AName;
  end;
  GVisuals[i].Handler := AHandler;
end;

procedure TyChartUnregisterVisualHandler(const AName: string);
var i, j: Integer;
begin
  i := IndexOfVisual(AName);
  if i < 0 then Exit;
  for j := i to High(GVisuals) - 1 do
    GVisuals[j] := GVisuals[j + 1];
  SetLength(GVisuals, Length(GVisuals) - 1);
end;

function TyChartFindVisualHandler(const AName: string;
  out AHandler: TTyChartVisualHandler): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfVisual(AName);
  Result := (i >= 0) and Assigned(GVisuals[i].Handler);
  if Result then AHandler := GVisuals[i].Handler;
end;

procedure TyChartClearVisualHandlers;
begin
  GVisuals := nil;
end;

{ ---- TTyItemCallbacks [R2-J3] ---- }

destructor TTyItemCallbacks.Destroy;
var i: Integer;
begin
  for i := 0 to High(Sym) do FreeAndNil(Sym[i]);
  inherited Destroy;
end;

function TTyItemCallbacks.SymOf(ARaw: Integer): TJSONObject;
begin
  Result := nil;
  if (ARaw >= 0) and (ARaw <= High(Sym)) then Result := Sym[ARaw];
end;

function TTyItemCallbacks.ColOf(ARaw: Integer; out AColour: TTyChartColor): Boolean;
begin
  AColour := 0;
  Result := (ARaw >= 0) and (ARaw <= High(ColSet)) and ColSet[ARaw];
  if Result then AColour := Col[ARaw];
end;

function TyChartRunVisualHandler(const ASpec: string;
  const AParams: TTyChartCallbackParams): TJSONData;
var h: TTyChartVisualHandler;
begin
  Result := nil;
  if not TyChartIsHandlerRef(ASpec) then Exit;
  if not TyChartFindVisualHandler(Copy(ASpec, 2, MaxInt), h) then Exit;
  Result := h(AParams);
end;

type
  TPositionEntry = record
    Name: string;
    Handler: TTyChartPositionHandler;
  end;

var
  GPositions: array of TPositionEntry;

function IndexOfPosition(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GPositions) do
    if SameText(GPositions[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure TyChartRegisterPositionHandler(const AName: string;
  AHandler: TTyChartPositionHandler);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfPosition(AName);
  if i < 0 then
  begin
    i := Length(GPositions);
    SetLength(GPositions, i + 1);
    GPositions[i].Name := AName;
  end;
  GPositions[i].Handler := AHandler;
end;

procedure TyChartUnregisterPositionHandler(const AName: string);
var i, j: Integer;
begin
  i := IndexOfPosition(AName);
  if i < 0 then Exit;
  for j := i to High(GPositions) - 1 do
    GPositions[j] := GPositions[j + 1];
  SetLength(GPositions, Length(GPositions) - 1);
end;

function TyChartFindPositionHandler(const AName: string;
  out AHandler: TTyChartPositionHandler): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfPosition(AName);
  Result := (i >= 0) and Assigned(GPositions[i].Handler);
  if Result then AHandler := GPositions[i].Handler;
end;

procedure TyChartClearPositionHandlers;
begin
  GPositions := nil;
end;

function TyChartRunPositionHandler(const ASpec: string;
  const AArgs: TTyChartTooltipPosArgs; out APos: TTyChartTooltipPos): Boolean;
var h: TTyChartPositionHandler;
begin
  APos := Default(TTyChartTooltipPos);
  APos.Kind := ctpDefault;
  Result := False;
  if not TyChartIsHandlerRef(ASpec) then Exit;
  if not TyChartFindPositionHandler(Copy(ASpec, 2, MaxInt), h) then Exit;
  APos := h(AArgs);
  Result := True;
end;

type
  TToolboxEntry = record
    Name: string;
    Handler: TTyChartToolboxHandler;
  end;

var
  GToolboxHandlers: array of TToolboxEntry;

function IndexOfToolboxHandler(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GToolboxHandlers) do
    if SameText(GToolboxHandlers[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure TyChartRegisterToolboxHandler(const AName: string;
  AHandler: TTyChartToolboxHandler);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfToolboxHandler(AName);
  if i < 0 then
  begin
    i := Length(GToolboxHandlers);
    SetLength(GToolboxHandlers, i + 1);
    GToolboxHandlers[i].Name := AName;
  end;
  GToolboxHandlers[i].Handler := AHandler;
end;

procedure TyChartUnregisterToolboxHandler(const AName: string);
var i, j: Integer;
begin
  i := IndexOfToolboxHandler(AName);
  if i < 0 then Exit;
  for j := i to High(GToolboxHandlers) - 1 do
    GToolboxHandlers[j] := GToolboxHandlers[j + 1];
  SetLength(GToolboxHandlers, Length(GToolboxHandlers) - 1);
end;

function TyChartFindToolboxHandler(const AName: string;
  out AHandler: TTyChartToolboxHandler): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfToolboxHandler(AName);
  Result := (i >= 0) and Assigned(GToolboxHandlers[i].Handler);
  if Result then AHandler := GToolboxHandlers[i].Handler;
end;

procedure TyChartClearToolboxHandlers;
begin
  GToolboxHandlers := nil;
end;

type
  TO2CEntry = record
    Name: string;
    Handler: TTyChartOptionToContent;
  end;
  TC2OEntry = record
    Name: string;
    Handler: TTyChartContentToOption;
  end;

var
  GO2C: array of TO2CEntry;
  GC2O: array of TC2OEntry;

function IndexOfO2C(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GO2C) do
    if SameText(GO2C[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

function IndexOfC2O(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GC2O) do
    if SameText(GC2O[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure TyChartRegisterOptionToContent(const AName: string;
  AHandler: TTyChartOptionToContent);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfO2C(AName);
  if i < 0 then
  begin
    i := Length(GO2C);
    SetLength(GO2C, i + 1);
    GO2C[i].Name := AName;
  end;
  GO2C[i].Handler := AHandler;
end;

procedure TyChartUnregisterOptionToContent(const AName: string);
var i, j: Integer;
begin
  i := IndexOfO2C(AName);
  if i < 0 then Exit;
  for j := i to High(GO2C) - 1 do
    GO2C[j] := GO2C[j + 1];
  SetLength(GO2C, Length(GO2C) - 1);
end;

function TyChartFindOptionToContent(const AName: string;
  out AHandler: TTyChartOptionToContent): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfO2C(AName);
  Result := (i >= 0) and Assigned(GO2C[i].Handler);
  if Result then AHandler := GO2C[i].Handler;
end;

procedure TyChartClearOptionToContents;
begin
  GO2C := nil;
end;

procedure TyChartRegisterContentToOption(const AName: string;
  AHandler: TTyChartContentToOption);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfC2O(AName);
  if i < 0 then
  begin
    i := Length(GC2O);
    SetLength(GC2O, i + 1);
    GC2O[i].Name := AName;
  end;
  GC2O[i].Handler := AHandler;
end;

procedure TyChartUnregisterContentToOption(const AName: string);
var i, j: Integer;
begin
  i := IndexOfC2O(AName);
  if i < 0 then Exit;
  for j := i to High(GC2O) - 1 do
    GC2O[j] := GC2O[j + 1];
  SetLength(GC2O, Length(GC2O) - 1);
end;

function TyChartFindContentToOption(const AName: string;
  out AHandler: TTyChartContentToOption): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfC2O(AName);
  Result := (i >= 0) and Assigned(GC2O[i].Handler);
  if Result then AHandler := GC2O[i].Handler;
end;

procedure TyChartClearContentToOptions;
begin
  GC2O := nil;
end;

type
  TMapperEntry = record
    Name: string;
    Handler: TTyChartAxisPointerMapper;
  end;

var
  GMappers: array of TMapperEntry;

function IndexOfMapper(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GMappers) do
    if SameText(GMappers[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure TyChartRegisterAxisPointerMapper(const AName: string;
  AHandler: TTyChartAxisPointerMapper);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfMapper(AName);
  if i < 0 then
  begin
    i := Length(GMappers);
    SetLength(GMappers, i + 1);
    GMappers[i].Name := AName;
  end;
  GMappers[i].Handler := AHandler;
end;

procedure TyChartUnregisterAxisPointerMapper(const AName: string);
var i, j: Integer;
begin
  i := IndexOfMapper(AName);
  if i < 0 then Exit;
  for j := i to High(GMappers) - 1 do
    GMappers[j] := GMappers[j + 1];
  SetLength(GMappers, Length(GMappers) - 1);
end;

function TyChartFindAxisPointerMapper(const AName: string;
  out AHandler: TTyChartAxisPointerMapper): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfMapper(AName);
  Result := (i >= 0) and Assigned(GMappers[i].Handler);
  if Result then AHandler := GMappers[i].Handler;
end;

procedure TyChartClearAxisPointerMappers;
begin
  GMappers := nil;
end;

type
  TLabelLayoutEntry = record
    Name: string;
    Handler: TTyChartLabelLayoutHandler;
  end;

var
  GLabelLayouts: array of TLabelLayoutEntry;

function IndexOfLabelLayout(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GLabelLayouts) do
    if SameText(GLabelLayouts[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure TyChartRegisterLabelLayoutHandler(const AName: string;
  AHandler: TTyChartLabelLayoutHandler);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfLabelLayout(AName);
  if i < 0 then
  begin
    i := Length(GLabelLayouts);
    SetLength(GLabelLayouts, i + 1);
    GLabelLayouts[i].Name := AName;
  end;
  GLabelLayouts[i].Handler := AHandler;
end;

procedure TyChartUnregisterLabelLayoutHandler(const AName: string);
var i, j: Integer;
begin
  i := IndexOfLabelLayout(AName);
  if i < 0 then Exit;
  for j := i to High(GLabelLayouts) - 1 do
    GLabelLayouts[j] := GLabelLayouts[j + 1];
  SetLength(GLabelLayouts, Length(GLabelLayouts) - 1);
end;

function TyChartFindLabelLayoutHandler(const AName: string;
  out AHandler: TTyChartLabelLayoutHandler): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfLabelLayout(AName);
  Result := (i >= 0) and Assigned(GLabelLayouts[i].Handler);
  if Result then AHandler := GLabelLayouts[i].Handler;
end;

procedure TyChartClearLabelLayoutHandlers;
begin
  GLabelLayouts := nil;
end;

function TyChartRunLabelLayoutHandler(const ASpec: string;
  const AArgs: TTyChartLabelLayoutArgs; out ALayout: TTyChartLabelLayout): Boolean;
var h: TTyChartLabelLayoutHandler;
begin
  ALayout := Default(TTyChartLabelLayout);
  Result := False;
  if not TyChartIsHandlerRef(ASpec) then Exit;
  if not TyChartFindLabelLayoutHandler(Copy(ASpec, 2, MaxInt), h) then Exit;
  ALayout := h(AArgs);
  Result := True;
end;

function TyChartPosNum(AValue: Double): TTyChartPosValue;
begin
  Result := Default(TTyChartPosValue);
  Result.Kind := cpvNumber;
  Result.Num := AValue;
end;

function TyChartPosText(const AText: string): TTyChartPosValue;
begin
  Result := Default(TTyChartPosValue);
  Result.Kind := cpvText;
  Result.Text := AText;
end;

function TyChartPosAbsent: TTyChartPosValue;
begin
  Result := Default(TTyChartPosValue);
end;

function IndexOfFormatter(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GFormatters) do
    if SameText(GFormatters[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure TyChartRegisterFormatter(const AName: string; AHandler: TTyChartFormatter);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfFormatter(AName);
  if i < 0 then
  begin
    i := Length(GFormatters);
    SetLength(GFormatters, i + 1);
    GFormatters[i].Name := AName;
  end;
  GFormatters[i].Handler := AHandler;
end;

procedure TyChartUnregisterFormatter(const AName: string);
var i, j: Integer;
begin
  i := IndexOfFormatter(AName);
  if i < 0 then Exit;
  for j := i to High(GFormatters) - 1 do
    GFormatters[j] := GFormatters[j + 1];
  SetLength(GFormatters, Length(GFormatters) - 1);
end;

function TyChartFindFormatter(const AName: string; out AHandler: TTyChartFormatter): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfFormatter(AName);
  Result := i >= 0;
  if Result then
    AHandler := GFormatters[i].Handler;
end;

procedure TyChartFormatterNames(AList: TStrings);
var i: Integer;
begin
  if AList = nil then Exit;
  AList.Clear;
  for i := 0 to High(GFormatters) do
    AList.Add(GFormatters[i].Name);
end;

procedure TyChartClearFormatters;
begin
  GFormatters := nil;
end;

function TyChartNumToStr(AValue: Double): string;
var
  fs: TFormatSettings;
begin
  if IsNan(AValue) then Exit('');
  if IsInfinite(AValue) then Exit('');
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  Result := FormatFloat('0.######', AValue, fs);
end;

function TyChartValueText(AValue: Double): string;
begin
  if IsNan(AValue) then Exit('');
  Result := TyJsNumberToString(AValue);
end;

function TyJsReplaceFirst(const ASubject, APattern, AReplacement: string): string;
var
  p, i: Integer;
  repl: string;
begin
  Result := ASubject;
  p := Pos(APattern, ASubject);
  if (APattern = '') or (p <= 0) then Exit;
  repl := '';
  i := 1;
  while i <= Length(AReplacement) do
  begin
    if (AReplacement[i] = '$') and (i < Length(AReplacement)) then
      case AReplacement[i + 1] of
        '$':
          begin
            repl := repl + '$';
            Inc(i, 2);
            Continue;
          end;
        '&':
          begin
            repl := repl + APattern;
            Inc(i, 2);
            Continue;
          end;
        '`':
          begin
            repl := repl + Copy(ASubject, 1, p - 1);
            Inc(i, 2);
            Continue;
          end;
        '''':
          begin
            repl := repl + Copy(ASubject, p + Length(APattern), MaxInt);
            Inc(i, 2);
            Continue;
          end;
      end;
    repl := repl + AReplacement[i];
    Inc(i);
  end;
  Result := Copy(ASubject, 1, p - 1) + repl
    + Copy(ASubject, p + Length(APattern), MaxInt);
end;

function TyJsFormatTpl(const ATemplate: string; AVarCount: Integer;
  const AVars: array of TTyStringArray): string;
const
  cAlias: array[0..6] of Char = ('a', 'b', 'c', 'd', 'e', 'f', 'g');
var
  s, k: Integer;
begin
  Result := ATemplate;
  { no series, no text -- formatTpl's own first answer }
  if Length(AVars) = 0 then Exit('');
  if AVarCount > Length(cAlias) then AVarCount := Length(cAlias);
  for k := 0 to AVarCount - 1 do
    Result := TyJsReplaceFirst(Result, '{' + cAlias[k] + '}',
      '{' + cAlias[k] + '0}');
  for s := 0 to High(AVars) do
    for k := 0 to AVarCount - 1 do
      if k <= High(AVars[s]) then
        Result := TyJsReplaceFirst(Result,
          '{' + cAlias[k] + IntToStr(s) + '}', AVars[s][k]);
end;

function TyChartIsHandlerRef(const ASpec: string): Boolean;
begin
  Result := (Length(ASpec) > 1) and (ASpec[1] = '@') and (ASpec[2] <> '[');
end;

{ The c text: the value as JavaScript prints it, several joined with ',' as
  an array prints -- a missing one as nothing, as join leaves a null. }
function ValueTextOf(const P: TTyChartCallbackParams): string;
var i: Integer;
begin
  { THE RAW VALUE, String()-ed -- except a null or a missing one, which the
    tooltip's formatTpl prints as nothing rather than `null`. }
  if P.Raw.Shape <> rshNone then
  begin
    if P.Raw.Shape in [rshNull, rshAbsent] then Exit('');
    Exit(TyRawItemText(P.Raw));
  end;
  Result := '';
  for i := 0 to High(P.Values) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + TyChartValueText(P.Values[i]);
  end;
end;

function TyChartEncodeHtml(const AText: string): string;
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

function TyChartFormatTemplate(const ATemplate: string;
  const AParams: TTyChartParams; AEncode: Boolean): string;
var
  vars: array of TTyStringArray;
  i, n, k: Integer;
begin
  vars := nil;
  SetLength(vars, Length(AParams));
  { d is one of the letters only where the series HAS a percentage -- a pie,
    a funnel -- and the first series decides, as upstream's $vars come from
    the first entry. }
  if (Length(AParams) > 0) and AParams[0].HasPercent then n := 4 else n := 3;
  for i := 0 to High(AParams) do
  begin
    SetLength(vars[i], n);
    vars[i][0] := AParams[i].SeriesName;
    vars[i][1] := AParams[i].Name;
    vars[i][2] := ValueTextOf(AParams[i]);
    if n = 4 then
    begin
      if AParams[i].HasPercent then
        vars[i][3] := TyJsNumberToString(AParams[i].Percent)
      else
        vars[i][3] := '';
    end;
    if AEncode then
      for k := 0 to n - 1 do vars[i][k] := TyChartEncodeHtml(vars[i][k]);
  end;
  Result := TyJsFormatTpl(ATemplate, n, vars);
end;

function TyChartResolveText(const ASpec: string; const AParams: TTyChartParams;
  out AText: string; AEncode: Boolean): Boolean;
var
  h: TTyChartFormatter;
  name: string;
begin
  AText := '';
  if not TyChartIsHandlerRef(ASpec) then
  begin
    AText := TyChartFormatTemplate(ASpec, AParams, AEncode);
    Exit(True);
  end;
  name := Copy(ASpec, 2, MaxInt);
  if not TyChartFindFormatter(name, h) then
  begin
    AText := Format(rsTyChartNoSuchHandler, [name]);
    Exit(False);
  end;
  if h = nil then
  begin
    AText := Format(rsTyChartNoSuchHandler, [name]);
    Exit(False);
  end;
  AText := h(AParams);
  Result := True;
end;

function TyChartRunHandler(const ASpec: string;
  const AParams: TTyChartParams): string;
begin
  TyChartResolveText(ASpec, AParams, Result);
end;

function TyChartOneParams(const AParams: TTyChartCallbackParams): TTyChartParams;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := AParams;
end;

function TyChartBlankParams: TTyChartCallbackParams;
begin
  Result := Default(TTyChartCallbackParams);
  Result.SeriesIndex := -1;
  Result.DataIndex := -1;
  Result.RawDataIndex := -1;
  Result.AxisIndex := -1;
  Result.ComponentIndex := -1;
  Result.TickIndex := -1;
  Result.BreakStart := NaN;
  Result.BreakEnd := NaN;
end;

finalization
  TyChartClearFormatters;
  TyChartClearPositionHandlers;
  TyChartClearVisualHandlers;
  TyChartClearOptionToContents;
  TyChartClearContentToOptions;

end.
