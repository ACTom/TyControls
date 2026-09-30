unit tyControls.AdvChart.Builder;
{$mode objfpc}{$H+}
{ Option text in, axes and coordinate systems out.

  Until this unit existed, every TTyAxis in the repository was constructed by a
  test. The scale layer, the coordinate layer and the layout solver were all
  built and all correct, and nothing connected them to an option tree -- which
  is the shape of "capability built but not wired", and this library has been
  bitten by it before.

  THREE PHASES, NOT ONE, because the pixel extent legitimately has to be written
  before the data exists and again afterwards:

    A  STRUCTURE   read grid / xAxis / yAxis, create the scales, the axes and
                   the N x M coordinate systems, and give every axis an
                   APPROXIMATE pixel extent from the raw grid rect. Series data
                   has not been read yet, and that is upstream's order for
                   upstream's reason: a dataZoom slider and a bar layouter both
                   need a pixel extent before any data extent exists.
    B  EXTENTS     union the bound series' data extents into the value axes.
                   Needs series stores, so it lands with the series binding.
    C  PIXELS      format the ticks, measure them, shrink each grid rect by the
                   space its axes need, and write every pixel extent a second
                   and final time.

  Phase B is deliberately absent here: nothing fills a data store from an option
  yet, so there would be nothing to union. Phases A and C are useful without it
  -- a category axis gets its whole extent from its categories, which phase A
  already knows.

  WHAT THE GENERATED CATALOG GETS WRONG. The catalog records xAxis.type's
  default as 'category'. The RUNTIME has no such default: both axis families run
  one identical rule -- an explicit type wins, otherwise an axis that carries a
  `data` key is categorical and everything else is a value axis. Category is the
  commonest axis because `data` is the commonest option, not because of the axis'
  name. The catalog is faithfully transcribing an upstream DOCUMENTATION bug, so
  the rule below is hand-written and the catalog is not consulted for it.

  PURE: SysUtils, Classes, Math, fpjson and the AdvChart units. No LCL. }
interface
uses SysUtils, Classes, Math, fpjson,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Time,
  tyControls.AdvChart.Dataset,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Layout;

type
  TTyAxisArray = array of TTyAxis;

  { What an axis actually draws, once its TYPE's defaults and the `auto`
    rule have both been applied and the option has had its say.

    THE DEFAULTS ARE THE FEATURE HERE, not the options. On the commonest
    chart there is -- a category x against a value y, with no axis option
    written at all -- upstream draws the x domain line and the y split lines
    and NOTHING ELSE: no x ticks, no x split lines, no y domain line, no y
    ticks. Drawing all six is what makes a port's bar chart read as bars in a
    box instead of bars on a grid, and it is four wrong answers to a question
    the author never asked. }
  TTyAxisFurniture = record
    ShowLine: Boolean;
    ShowTicks: Boolean;
    ShowLabels: Boolean;
    ShowSplitLine: Boolean;
    ShowSplitArea: Boolean;
    ShowMinorTick: Boolean;
    ShowMinorSplitLine: Boolean;
    { Inward-pointing furniture is INSIDE the plot, so it reserves nothing
      outside it -- which is a layout question and not only a paint one. }
    TickInside: Boolean;
    LabelInside: Boolean;
    { `axisTick.alignWithLabel`: on a banded category axis the ticks move from
      the band EDGES to the band CENTRES, and there is one per band rather
      than one per boundary. }
    AlignWithLabel: Boolean;
    { `splitLine.showMinLine` / `showMaxLine`: whether the line ON the axis'
      own extreme is drawn. Both default true. Turning the max one off is how
      an author stops the topmost grid line from doubling the plot's edge. }
    ShowMinLine: Boolean;
    ShowMaxLine: Boolean;
    { LOGICAL px, and NaN for `the theme decides`. NOT -1: upstream reads a
      NEGATIVE length as a direction -- `axisTick: { length: -5 }` points the
      mark the other way -- so a negative sentinel would swallow a legal
      value and there would be no way to write it at all. }
    TickLengthLogical: Double;
    MinorTickLengthLogical: Double;
    LabelMarginLogical: Double;
    { DEGREES, clockwise on screen, which is how the option spells it. }
    LabelRotateDeg: Double;
    { `axisLabel.formatter` when it is a STRING: its first '{value}' becomes
      the label. '' is a string too, and blanks every label. A function
      cannot come through an option text. }
    LabelFormatter: string;
    HasLabelFormatter: Boolean;
    { `axis.offset`, LOGICAL px, default 0 -- and the default is declared
      rather than implied: upstream merges `offset: 0` into all eight axis
      model classes.

      POSITIVE ALWAYS MEANS AWAY FROM THE PLOT, whichever side the axis is
      on: a left axis moves to `left - offset` and a right one to
      `right + offset`. It is not a screen direction. }
    OffsetLogical: Double;
    { `axisLine.onZero`, default `auto` -- which is TRUTHY, so an axis whose
      opposite number crosses zero sits on it unless told otherwise. }
    OnZero: Boolean;
    { THE `auto` HALF OF IT: the key absent, or the string 'auto'. Only this
      one defers to an axis whose zero a bar's half width has moved
      (TTyAxis.ZeroDiscouraged); a written `true` sits on that zero anyway. }
    OnZeroAuto: Boolean;
    { `axisLine.onZeroAxisIndex`: which of the other family provides the
      zero. -1 for `whichever qualifies first`. An index that names an axis
      that cannot provide one does NOT fall back to the scan -- upstream's
      `else` belongs to the `if (onZeroAxisIndex != null)`, so naming a bad
      one turns onZero off. }
    OnZeroAxisIndex: Integer;

    { `axisLabel.interval` and `axisTick.interval`, ALREADY TURNED INTO A
      STRIDE: nought means `auto`, and N+1 means the option said N.

      The option counts what it SKIPS. `interval: 0` shows every label,
      `interval: 1` shows every other one, `interval: 2` one in three -- so
      the stride is one more than the number written. Reading it as `every
      Nth` makes the commonest value of all, 0, throw away half the axis.

      CATEGORY AXES ONLY. Upstream routes a value, time or log axis straight
      past the interval reader, and the reason is not arbitrary: on those the
      TICKS come first and the labels are made from them, so there is nothing
      for a label stride to thin. Both stay nought on such an axis. }
    LabelStep: Integer;
    TickStep: Integer;

    { `axisLabel.showMinLabel` / `showMaxLabel`. Three-state; see
      TTyAxisEndLabel. These are read on EVERY axis type -- what counts as
      `the stride missed this end` differs (an off-stride category, a ragged
      time boundary) but the author's override does not. }
    ShowMinLabel: TTyAxisEndLabel;
    ShowMaxLabel: TTyAxisEndLabel;
    { `axisLabel.interval: 0` exactly on a category axis: every label, and
      the end rules not asked -- a negative interval also builds them all, but
      is not this }
    ShowAllLabels: Boolean;
    { axisLabel.hideOverlap, in JavaScript's truthiness }
    HideOverlap: Boolean;
    { EACH PIECE OF FURNITURE'S OWN interval on a category axis: axisTick,
      splitLine, splitArea. NaN is `auto` -- follow the labels -- and a
      number is taken whole, as axisLabel.interval is. }
    TickInterval, SplitLineInterval, SplitAreaInterval: Double;
    { splitLine.alignWithLabel / splitArea.alignWithLabel }
    SplitLineAlign, SplitAreaAlign: Boolean;
    { minorTick.show as written, on any axis: shown minor ticks keep every
      major tick, even one whose label was hidden }
    MinorTickOption: Boolean;
  end;


  { One grid: a plot rect, the axes that named it, and the coordinate systems
    over their cross product. }
  TTyGridBuild = class
  private
    FComponentIndex: Integer;
    FOuterRect: TTyRectF;
    FPlotRect: TTyRectF;
    { The same two as upstream holds them. The edges above are x + width and
      y + height of these; the axes are laid over these. }
    FOuterXYWH: TTyXYWH;
    FPlotXYWH: TTyXYWH;
    FSpecs: TTyAxisLayoutSpecArray;
    { Index-parallel to FSpecs: the x axes then the y axes, which is the
      order SpecFor already walks. }
    FFurniture: array of TTyAxisFurniture;
    FXAxes: TTyAxisArray;
    FYAxes: TTyAxisArray;
    FCartesians: array of TTyCartesian2D;   // OWNED
    FKeys: TTyStringArray;
  public
    constructor Create(AComponentIndex: Integer);
    destructor Destroy; override;
    function CartesianCount: Integer;
    function CartesianByIndex(AIndex: Integer): TTyCartesian2D;
    function CartesianKey(AIndex: Integer): string;
    { By GLOBAL component index, which is what a series' xAxisIndex names. nil
      when this grid holds no such pair. }
    function CartesianAt(AXComponentIndex, AYComponentIndex: Integer): TTyCartesian2D;
    function XAxisCount: Integer;
    function YAxisCount: Integer;
    function XAxis(AIndex: Integer): TTyAxis;
    function YAxis(AIndex: Integer): TTyAxis;
    property ComponentIndex: Integer read FComponentIndex;
    { Before the axis-thickness shrink. }
    property OuterRect: TTyRectF read FOuterRect;
    { After it. Equal to OuterRect until phase C runs. }
    property PlotRect: TTyRectF read FPlotRect;
    property OuterXYWH: TTyXYWH read FOuterXYWH;
    property PlotXYWH: TTyXYWH read FPlotXYWH;
    { WHAT THE LAYOUT PASS MEASURED, kept so the renderer draws from it rather
      than assembling a second one. The plot rect was shrunk to fit exactly
      these labels in exactly this font, and a paint pass that rebuilt the spec
      would be a second route to the same answer -- the two came apart once
      already, when the layout measured in a hardcoded 12pt while paint drew in
      the theme's font.

      nil before phase C has run. }
    function SpecFor(AAxis: TTyAxis): PTyAxisLayoutSpec;
    { What AAxis draws. Answers every-default furniture for an axis this grid
      does not hold, which is the same answer a chart with no option gets. }
    function FurnitureFor(AAxis: TTyAxis): TTyAxisFurniture;
    { WHERE AAxis' LINE SITS, in device px across the plot.

      Three answers in one: the plot's own edge; that edge pushed out by
      `offset`; or the other family's zero when `axisLine.onZero` applies.
      One function because the three are alternatives and a caller that had
      to combine them would be a second place that knows the rule. }
    function AxisLineCoord(AAxis: TTyAxis; APPI: Integer): Double;
    { The axis of the OTHER family that provides AAxis' zero, or nil.

      Not every axis can: a category or a time axis never provides one, nor
      does one whose extent has zero strictly outside it -- so a log axis
      never can either. And an axis already providing a zero for somebody
      else is skipped, which is what stops two y axes landing on top of each
      other when both ask. }
    function OnZeroProviderFor(AAxis: TTyAxis): TTyAxis;
    { THE FRAME AN AXIS' NAME IS LAID OUT IN on the plot rect as it stands:
      the line where AxisLineCoord puts it, and -- when that is the other
      family's zero -- how far the labels, which stay at the edge, stand
      from it. Asked on the raw rect for the estimate and on the final one
      for the name that is drawn. }
    function NameFrameFor(AAxis: TTyAxis; const ASpec: TTyAxisLayoutSpec;
      APPI: Integer): TTyAxisNameFrame;
  end;

  { Everything one option tree produced. Owns the grids, the axes and, through
    the grids, the coordinate systems. }
  TTyChartBuild = class
  private
    FGrids: array of TTyGridBuild;
    FXAxes: TTyAxisArray;      // OWNED; indexed by global component index
    FYAxes: TTyAxisArray;      // OWNED
    FDiagnostics: TTyStringArray;
    FViewport: TTyRectF;
  public
    { The canvas the grids were solved against -- what a grid's default outer
      bounds are measured on. }
    property Viewport: TTyRectF read FViewport;
    { Public because the series binder is a different unit and FPC's private is
      unit-scoped. One list for everything the option said that could not be
      honoured, whoever noticed it. }
    procedure Note(const AMsg: string);
    destructor Destroy; override;
    function GridCount: Integer;
    function Grid(AIndex: Integer): TTyGridBuild;
    function AxisCount(const AMainType: string): Integer;
    { By GLOBAL component index. nil when absent. }
    function Axis(const AMainType: string; AComponentIndex: Integer): TTyAxis;
    { By id rather than index. nil when no axis of that family carries it. }
    function AxisById(const AMainType, AId: string): TTyAxis;
    { The coordinate system holding exactly this pair of GLOBAL axis indices,
      searched across every grid.

      Unambiguous by construction: an axis is assigned one grid index and is
      appended only to that grid, so a global (x, y) pair matches at most one
      coordinate system anywhere in the chart. That is what lets a series name
      two axis indices and never a grid. }
    function CartesianAt(AXComponentIndex, AYComponentIndex: Integer): TTyCartesian2D;
    { What the option said that could not be honoured. A chart that silently
      drops a misspelled axis is a chart that lies; these are what an editor
      shows instead. }
    function DiagnosticCount: Integer;
    function Diagnostic(AIndex: Integer): string;
  end;

{ ---- phase A ---- }
{ Never raises and never returns nil: an option that says nothing buildable
  produces an empty build with diagnostics, because a design-time editor renders
  every keystroke and half-typed text is the normal state. }
function TyBuildGrids(AOption: TTyChartOption; const AViewport: TTyRectF): TTyChartBuild;

{ ---- phase C ---- }
{ Shrink every grid rect by the room its axes' labels and names need, then write
  the final pixel extents. Safe to call more than once. }
procedure TyLayoutGrids(ABuild: TTyChartBuild; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  const AText: TTyAxisTextStyle);

{ ---- the axis furniture ---- }

{ Resolve one axis' furniture.

  AOtherIsValue answers `is any axis of the OPPOSITE family on this grid an
  interval or a log axis` -- which is the whole input to upstream's `auto`
  rule, and note what it is NOT: it is not `is the other axis of MY pair`,
  because upstream walks every cartesian in the grid and asks each one for
  its opposite-dimension axis whether or not this axis is in it. }
function TyAxisFurnitureOf(ANode: TJSONObject; AAxis: TTyAxis;
  AOtherIsValue: Boolean): TTyAxisFurniture;

{ One tick's label as upstream's makeLabelFormatter makes it for a category,
  value or log axis: the scale's own label -- the category, or the number as
  IntervalScale.getLabel prints it, '1,234.5' -- and with a string formatter,
  that formatter with its FIRST '{value}' replaced. A time axis has its own. }
function TyAxisTickLabel(AAxis: TTyAxis; AValue: Double;
  AHasFormatter: Boolean; const AFormatter: string): string;

{ ---- reading series data ---- }
type
  { One column of a series' store, as the filler needs it: what to call it, how
    to parse it, and -- for a category column -- whose list to intern against. }
  TTySeriesDim = record
    Name: string;
    Kind: TTyDimType;
    { WHICH ELEMENT OF THE ROW THIS COLUMN TAKES, one-based; 0 means the
      column's own position, which is what every series written before a
      candlestick needed.

      ONE-BASED AND NOT ZERO-BASED ON PURPOSE. These records are made by
      SetLength and by Default(), both of which zero them, and a zero-based
      field would have every column of every store silently claiming to read
      element 0. The awkward numbering is what makes the default safe. }
    SourceSlot: Integer;
    { WHICH COORDINATE THIS COLUMN FEEDS, when that is not its own name --
      handed straight to TTyDataStore.SetDimCoord. Empty for every ordinary
      column, which is every column of every series that puts one number on
      each axis. }
    Coord: string;
    { True when this column is the ROW NUMBER rather than anything in the row.

      A candlestick's four values occupy the whole of its item array, so its
      category cannot also come from there -- upstream's default encode puts
      the category on the row index and every value on the value axis. The
      store-wide `useIndex` guess cannot express that: it fires only when the
      items are not arrays, and a candlestick's always are. }
    FromRowIndex: Boolean;
    { The axis that OWNS the category list this column interns into. nil unless
      the column is ordinal. Sharing that list is what makes two series on one
      category axis agree about which name ordinal 0 is. }
    Axis: TTyAxis;
  end;
  TTySeriesDimArray = array of TTySeriesDim;

{ The default cartesian column list: the coordinate dimensions first, then as
  many generated columns as the data has spare -- value, value0, value1 -- which
  is where a scatter's third number or a tooltip's extra field lives. }
function TySeriesCartesianDims(ACart: TTyCartesian2D;
  AExtraCount: Integer): TTySeriesDimArray;

{ How many columns the DATA declares, read from item 0 LITERALLY -- a leading
  null counts as a scalar and gives 1.

  Deliberately not the same question, and not the same item, as the one
  TySeriesUsesRowIndex asks: upstream reads item 0 raw here and the first
  NON-NULL item there, and the two genuinely disagree on data whose first entry
  is null. Merging them would be tidier and wrong. }
function TySeriesDetectedDimCount(AData: TJSONArray): Integer;

{ Does this series' category column hold the ROW INDEX rather than the data?

  A series of bare numbers on a category axis is the commonest shape on the
  internet -- `data: [120, 200, 150]` against `xAxis.data` of three names -- and
  it works because the category column is filled with 0, 1, 2 while the numbers
  go to the value column. Without this the numbers would be read as category
  NAMES, miss, and the chart would be empty.

  ONE decision for the whole series, taken from the first non-null item. In a
  mixed array the tuple rows get the row index too. }
function TySeriesUsesRowIndex(AData: TJSONArray;
  const ADims: TTySeriesDimArray): Boolean;

{ Read series[ASeriesIndex].data into AStore, which must already carry ADims as
  its dimensions and must be empty. Returns the number of rows appended. }
function TyFillSeriesStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ADims: TTySeriesDimArray; AStore: TTyDataStore;
  const AKey: string = 'data'): Integer;
{ THE SAME FILL OVER AN ARRAY THE CALLER BUILT -- a tree's rows, which are a
  hierarchy flattened in pre-order and not any one array of the option. The
  series still answers `dimensions`. [Batch 73] }
function TyFillSeriesStoreArray(AOption: TTyChartOption; ASeriesIndex: Integer;
  AArray: TJSONArray; const ADims: TTySeriesDimArray; AStore: TTyDataStore): Integer;

{ The same job from a DATASET. AEncode says which source dimension feeds each
  of ADims; a coordinate it leaves at -1 gets no value at all.

  IT IS A SECOND FUNCTION AND NOT A PARAMETER, because three of the rules the
  series-data filler follows are wrong here and would have to be gated rather
  than shared:

    THE ROW INDEX. A bare `data: [120, 200]` on a category axis means `the
    first category, the second category`, so the category column is filled
    with the row's position. A dataset's category column is a REAL column,
    named in the table, and substituting the row number would quietly plot
    the wrong thing.

    THE SCALAR FANOUT. `data: [5]` puts 5 in every column, which is what a
    one-number row means. A dataset row is a record and a missing cell is a
    gap.

    THE ITEM OBJECT. `{ value: 3, name: 'x' }` is a series-data item; a
    dataset's object row is a RECORD whose fields are dimensions, and reading
    `value` out of it would eat a column called value.

  What IS shared is the cell parsing, which is the part that has rules worth
  sharing. }
function TyFillStoreFromSource(const ASource: TTyChartSource;
  const AEncode: TTySeriesEncode; const ADims: TTySeriesDimArray;
  AStore: TTyDataStore): Integer;

{ Which component of a family this option node names.

  ONE copy, shared by the axis builder and the series binder, because two copies
  of a precedence rule are two things that have to agree:

    an INDEX wins whenever it is present, and an index naming nothing resolves
    to NOTHING -- not to the id, and not to component 0;
    an id is consulted only when no index was given;
    neither given names the FIRST component.

  A name is never consulted, even though the option carries one. }
function TyResolveComponentRef(ANode: TJSONObject;
  const AIndexKey, AIdKey: string; ACount: Integer;
  const AIds: TTyStringArray): Integer;

{ ---- the rules, exposed because they are worth testing directly ---- }
{ An explicit type wins with NO validation; otherwise a `data` key that is
  present and not null makes the axis categorical. An EMPTY data array still
  does -- it is a fixed list of no categories, which is not the same as an axis
  that never declared one. }
function TyResolveAxisType(ANode: TJSONObject; out AType: TTyAxisType;
  out AUnknown: string): Boolean;

implementation

uses
  { Only for the diagnostic resourcestrings; kept out of the interface uses so
    the dependency stays one-way and this unit's public face still names only
    the AdvChart layer. }
  tyControls.StrConsts, tyControls.AdvChart.AxisName,
  tyControls.AdvChart.AxisLabels;

const
  { GridModel's defaultOption. Percentages are of the FULL container extent, not
    of what is left after the other side. }
  GridDefaultLeft   = 15.0;   // per cent
  GridDefaultRight  = 10.0;   // per cent
  GridDefaultTop    = 65.0;   // px
  GridDefaultBottom = 80.0;   // px

{ ==================== small option helpers ==================== }

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function FindIn(ANode: TJSONObject; const AKey: string): TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  Result := ANode.Find(AKey);
end;

function StrIn(ANode: TJSONObject; const AKey, ADefault: string): string;
var d: TJSONData;
begin
  d := FindIn(ANode, AKey);
  { An ARRAY or an OBJECT where a string was expected RAISES out of AsString --
    fpjson's ConvertError. Its two siblings below both test the type and fall
    back; this one did not, and `{ xAxis: { name: [1] } }` is legal JSON that a
    half-finished edit produces all the time.

    That mattered more than a wrong value would have: the raise escaped
    TyBuildGrids before it returned, so the CALLER's build variable was never
    assigned and its try/finally never ran -- the whole build leaked, plus the
    axis under construction. And the comment further down this unit argues that
    throwing is wrong for us precisely because a design-time editor renders on
    every keystroke.

    Option.pas' own string reader already had the right shape. }
  if (d = nil) or (d.JSONType in [jtNull, jtArray, jtObject]) then
    Exit(ADefault);
  Result := d.AsString;
end;

{ AN AXIS' NAME AS UPSTREAM READS IT: there is one when the option is truthy
  (`!!name`), and it is the value's own string -- `0`, `false` and '' are no
  name at all, `true` is 'true' and 1.5 is '1.5'. An array or an object is
  none, as it always was here. }
function AxisNameIn(ANode: TJSONObject): string;
var d: TJSONData;
begin
  Result := '';
  d := FindIn(ANode, 'name');
  if d = nil then Exit;
  case d.JSONType of
    jtString: Result := d.AsString;
    jtBoolean: if d.AsBoolean then Result := 'true';
    jtNumber:
      if (not IsNan(d.AsFloat)) and (d.AsFloat <> 0) then
        Result := TyJsNumberToString(d.AsFloat);
  end;
end;

function BoolIn(ANode: TJSONObject; const AKey: string; ADefault: Boolean): Boolean;
var d: TJSONData;
begin
  d := FindIn(ANode, AKey);
  if (d = nil) or (d.JSONType = jtNull) then Exit(ADefault);
  if d.JSONType = jtBoolean then Exit(d.AsBoolean);
  Result := ADefault;
end;

function IntIn(ANode: TJSONObject; const AKey: string; ADefault: Integer): Integer;
var d: TJSONData;
begin
  d := FindIn(ANode, AKey);
  if (d = nil) or (d.JSONType = jtNull) then Exit(ADefault);
  if d.JSONType = jtNumber then Exit(TyTruncOpt(d.AsFloat));
  Result := ADefault;
end;

function HasKey(ANode: TJSONObject; const AKey: string): Boolean;
var d: TJSONData;
begin
  d := FindIn(ANode, AKey);
  Result := (d <> nil) and (d.JSONType <> jtNull);
end;

{ A box value in ECharts' three spellings: a number is px, a string ending in
  '%' is a percentage, and 'center'/'middle' centres. }
function BoxValueIn(ANode: TJSONObject; const AKey: string;
  const ADefault: TTyBoxValue): TTyBoxValue;
var
  d: TJSONData;
  s: string;
  v: Double;
  fs: TFormatSettings;
begin
  Result := ADefault;
  d := FindIn(ANode, AKey);
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d.JSONType = jtNumber then Exit(TyBoxPx(d.AsFloat));
  if d.JSONType <> jtString then Exit;
  s := Trim(d.AsString);
  if s = '' then Exit;
  if (s = 'center') or (s = 'centre') or (s = 'middle') then Exit(TyBoxCentre);
  if s[Length(s)] = '%' then
  begin
    fs := DefaultFormatSettings;
    fs.DecimalSeparator := '.';
    if TryStrToFloat(Copy(s, 1, Length(s) - 1), v, fs) then Exit(TyBoxPercent(v));
    Exit;
  end;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if TryStrToFloat(s, v, fs) then Result := TyBoxPx(v);
end;

{ UPSTREAM'S mergeLayoutParam, one direction of a box: the option's own
  left/right/width (or top/bottom/height) against the component's defaults.
  Two written wins outright -- `right` and `width` drop the default `left`
  rather than being overruled by it; one written borrows the first default
  of the three the option did not name; none, or two altogether, keep the
  defaults as they are. A key written as null or 'auto' is present but has
  no value, as upstream counts it. }
procedure MergedBoxDim(ANode: TJSONObject; const AK0, AK1, AK2: string;
  const AD0, AD1, AD2: TTyBoxValue; out AV0, AV1, AV2: TTyBoxValue);
var
  keys: array[0..2] of string;
  defs, user, res: array[0..2] of TTyBoxValue;
  own, hasNew, hasMerged: array[0..2] of Boolean;
  i, nNew, nMerged: Integer;
  d: TJSONData;
begin
  keys[0] := AK0; keys[1] := AK1; keys[2] := AK2;
  defs[0] := AD0; defs[1] := AD1; defs[2] := AD2;
  nNew := 0;
  nMerged := 0;
  for i := 0 to 2 do
  begin
    d := FindIn(ANode, keys[i]);
    own[i] := d <> nil;
    hasNew[i] := own[i] and (d.JSONType <> jtNull)
      and not ((d.JSONType = jtString) and (d.AsString = 'auto'));
    user[i] := BoxValueIn(ANode, keys[i], TyBoxAuto);
    if own[i] then hasMerged[i] := hasNew[i]
    else hasMerged[i] := defs[i].Kind <> buAuto;
    if hasNew[i] then Inc(nNew);
    if hasMerged[i] then Inc(nMerged);
  end;
  for i := 0 to 2 do
    if own[i] then res[i] := user[i] else res[i] := defs[i];
  if (nMerged <> 2) and (nNew > 0) then
  begin
    { the option's own keys only ... }
    for i := 0 to 2 do
      if own[i] then res[i] := user[i] else res[i] := TyBoxAuto;
    { ... and with only one of them, the first default it did not name }
    if nNew < 2 then
      for i := 0 to 2 do
        if (not own[i]) and (defs[i].Kind <> buAuto) then
        begin
          res[i] := defs[i];
          Break;
        end;
  end;
  AV0 := res[0];
  AV1 := res[1];
  AV2 := res[2];
end;

{ ==================== the axis type rule ==================== }

function TyResolveAxisType(ANode: TJSONObject; out AType: TTyAxisType;
  out AUnknown: string): Boolean;
var t: string;
begin
  AUnknown := '';
  AType := atValue;
  Result := True;
  t := StrIn(ANode, 'type', '');
  if t <> '' then
  begin
    if t = 'value' then AType := atValue
    else if t = 'category' then AType := atCategory
    else if t = 'time' then AType := atTime
    else if t = 'log' then AType := atLog
    else
    begin
      { ECharts THROWS here -- the component class lookup fails before any
        coercion runs. Throwing is wrong for us: a design-time editor renders on
        every keystroke, and 'cat' on the way to 'category' would blank the
        chart. The axis falls back to a value axis and the mistake is reported. }
      AUnknown := t;
      AType := atValue;
      Result := False;
    end;
    Exit;
  end;
  { No explicit type. A `data` key that is present and not null makes it
    categorical -- INCLUDING an empty array, which is a fixed list of no
    categories rather than an axis that declared none. Testing the array's
    LENGTH here would quietly turn `data: []` into a value axis. }
  if HasKey(ANode, 'data') then
    AType := atCategory;
end;

{ ==================== categories ==================== }

{ An item is either a bare value or an object with a `value`. Both are read as
  text: our category list is text, while upstream leaves an object-form numeric
  category as a number. The difference shows only if someone writes
  a data item written as an object with a numeric value and then queries by
  that number. }
procedure ReadCategories(ANode: TJSONObject; AAxis: TTyAxis);
var
  d, item, v: TJSONData;
  arr: TJSONArray;
  cats: TTyStringArray;
  i: Integer;
begin
  d := FindIn(ANode, 'data');
  if (d = nil) or (d.JSONType = jtNull) or not (d is TJSONArray) then Exit;
  arr := TJSONArray(d);
  SetLength(cats, arr.Count);
  for i := 0 to arr.Count - 1 do
  begin
    item := arr.Items[i];
    v := nil;
    if item is TJSONObject then v := TJSONObject(item).Find('value');
    { A CATEGORY IS A SCALAR OR IT IS NOTHING. `AsString` on an object or an
      array does not stringify it, it RAISES -- and both shapes are legal:
      `data: [{ value: 3, textStyle: {} }]` is how a single category is
      styled, and its `value` can be an array as easily as its item can. An
      unnameable category becomes the empty name rather than the end of the
      render. }
    if (v <> nil) and (v.JSONType <> jtNull) then
    begin
      if v.JSONType in [jtObject, jtArray] then cats[i] := ''
      else cats[i] := v.AsString;
    end
    else if item.JSONType in [jtNull, jtObject, jtArray] then
      cats[i] := ''
    else
      cats[i] := item.AsString;
  end;
  AAxis.SetCategories(cats);
end;

{ ==================== TTyGridBuild ==================== }

constructor TTyGridBuild.Create(AComponentIndex: Integer);
begin
  inherited Create;
  FComponentIndex := AComponentIndex;
  FOuterXYWH := TyXYWH(0, 0, 0, 0);
  FPlotXYWH := FOuterXYWH;
  FOuterRect := TyRectOfXYWH(FOuterXYWH);
  FPlotRect := FOuterRect;
end;

destructor TTyGridBuild.Destroy;
var i: Integer;
begin
  { The coordinate systems are ours; the AXES are not -- they belong to the
    build, because the same axis object is in several of these. }
  for i := 0 to High(FCartesians) do
    FCartesians[i].Free;
  FCartesians := nil;
  inherited Destroy;
end;

function TTyGridBuild.CartesianCount: Integer;
begin
  Result := Length(FCartesians);
end;

function TTyGridBuild.CartesianByIndex(AIndex: Integer): TTyCartesian2D;
begin
  if (AIndex < 0) or (AIndex > High(FCartesians)) then Exit(nil);
  Result := FCartesians[AIndex];
end;

function TTyGridBuild.CartesianKey(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(FKeys)) then Exit('');
  Result := FKeys[AIndex];
end;

function TTyGridBuild.CartesianAt(AXComponentIndex, AYComponentIndex: Integer): TTyCartesian2D;
var
  key: string;
  i: Integer;
begin
  key := 'x' + IntToStr(AXComponentIndex) + 'y' + IntToStr(AYComponentIndex);
  for i := 0 to High(FKeys) do
    if FKeys[i] = key then Exit(FCartesians[i]);
  { Deliberately an exact match on BOTH indices. Upstream's lookup falls back
    when only one matches, and hands back x0y0 for a request naming y axis 1 --
    which is the secondary-axis bug this whole layer exists to prevent. }
  Result := nil;
end;

function TTyGridBuild.XAxisCount: Integer;
begin
  Result := Length(FXAxes);
end;

function TTyGridBuild.YAxisCount: Integer;
begin
  Result := Length(FYAxes);
end;

function TTyGridBuild.XAxis(AIndex: Integer): TTyAxis;
begin
  if (AIndex < 0) or (AIndex > High(FXAxes)) then Exit(nil);
  Result := FXAxes[AIndex];
end;

function TTyGridBuild.YAxis(AIndex: Integer): TTyAxis;
begin
  if (AIndex < 0) or (AIndex > High(FYAxes)) then Exit(nil);
  Result := FYAxes[AIndex];
end;

{ ==================== TTyChartBuild ==================== }

destructor TTyChartBuild.Destroy;
var i: Integer;
begin
  for i := 0 to High(FGrids) do
    FGrids[i].Free;
  FGrids := nil;
  for i := 0 to High(FXAxes) do
    FXAxes[i].Free;
  for i := 0 to High(FYAxes) do
    FYAxes[i].Free;
  FXAxes := nil;
  FYAxes := nil;
  inherited Destroy;
end;

procedure TTyChartBuild.Note(const AMsg: string);
var n: Integer;
begin
  n := Length(FDiagnostics);
  SetLength(FDiagnostics, n + 1);
  FDiagnostics[n] := AMsg;
end;

function TTyChartBuild.GridCount: Integer;
begin
  Result := Length(FGrids);
end;

function TTyChartBuild.Grid(AIndex: Integer): TTyGridBuild;
begin
  if (AIndex < 0) or (AIndex > High(FGrids)) then Exit(nil);
  Result := FGrids[AIndex];
end;

function TTyChartBuild.AxisCount(const AMainType: string): Integer;
begin
  if AMainType = 'xAxis' then Exit(Length(FXAxes));
  if AMainType = 'yAxis' then Exit(Length(FYAxes));
  Result := 0;
end;

function TTyChartBuild.Axis(const AMainType: string; AComponentIndex: Integer): TTyAxis;
begin
  Result := nil;
  if AComponentIndex < 0 then Exit;
  if AMainType = 'xAxis' then
  begin
    if AComponentIndex <= High(FXAxes) then Result := FXAxes[AComponentIndex];
    Exit;
  end;
  if AMainType = 'yAxis' then
    if AComponentIndex <= High(FYAxes) then Result := FYAxes[AComponentIndex];
end;

function TTyChartBuild.AxisById(const AMainType, AId: string): TTyAxis;
var
  i: Integer;
  src: TTyAxisArray;
begin
  Result := nil;
  if AId = '' then Exit;
  if AMainType = 'xAxis' then src := FXAxes
  else if AMainType = 'yAxis' then src := FYAxes
  else Exit;
  for i := 0 to High(src) do
    if src[i].Id = AId then Exit(src[i]);
end;

function TTyChartBuild.CartesianAt(AXComponentIndex,
  AYComponentIndex: Integer): TTyCartesian2D;
var i: Integer;
begin
  for i := 0 to High(FGrids) do
  begin
    Result := FGrids[i].CartesianAt(AXComponentIndex, AYComponentIndex);
    if Result <> nil then Exit;
  end;
  Result := nil;
end;

function TTyChartBuild.DiagnosticCount: Integer;
begin
  Result := Length(FDiagnostics);
end;

function TTyChartBuild.Diagnostic(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(FDiagnostics)) then Exit('');
  Result := FDiagnostics[AIndex];
end;

{ ==================== phase A ==================== }

{ Which grid this axis names. -1 means it names none and so belongs to no plot.

  An INDEX wins over an id, and an index naming no grid falls back to NOTHING --
  not to the id, and not to grid 0. Writing both keys therefore silently ignores
  the id, which is upstream's behaviour and worth copying rather than improving:
  a chart that quietly relocated an axis would be harder to debug than one that
  drops it and says so. }
function TyResolveComponentRef(ANode: TJSONObject;
  const AIndexKey, AIdKey: string; ACount: Integer;
  const AIds: TTyStringArray): Integer;
var
  idx, i: Integer;
  id: string;
begin
  Result := -1;
  if ACount <= 0 then Exit;
  if HasKey(ANode, AIndexKey) then
  begin
    idx := IntIn(ANode, AIndexKey, -1);
    if (idx >= 0) and (idx < ACount) then Exit(idx);
    { No fallback. Quietly relocating a component would be harder to debug than
      dropping it and saying so. }
    Exit(-1);
  end;
  id := StrIn(ANode, AIdKey, '');
  if id <> '' then
  begin
    for i := 0 to High(AIds) do
      if AIds[i] = id then Exit(i);
    Exit(-1);
  end;
  Result := 0;
end;

function ResolveGridIndex(ANode: TJSONObject; AGridCount: Integer;
  const AGridIds: TTyStringArray): Integer;
begin
  Result := TyResolveComponentRef(ANode, 'gridIndex', 'gridId', AGridCount, AGridIds);
end;

function MakeScale(AType: TTyAxisType; ANode: TJSONObject): TTyScale;
var
  iv: TTyIntervalScale;
  logBase: Double;
  d: TJSONData;
begin
  case AType of
    atCategory:
      Exit(TTyOrdinalScale.Create);
    atLog:
      begin
        iv := TTyIntervalScale.Create;
        logBase := 10;
        d := FindIn(ANode, 'logBase');
        if (d <> nil) and (d.JSONType = jtNumber) then logBase := d.AsFloat;
        if logBase <= 1 then logBase := 10;
        { A replacement mapper brings its own extents, so anything already set
          would be lost -- nothing is set yet at this point, and the extent is
          written in phase B. }
        iv.Mapper := TTyLogScaleMapper.Create(logBase);
        { AND ITS STEP RULE: whole decades, not nice(). }
        iv.LogRule := True;
        Exit(iv);
      end;
    atTime:
      Exit(TTyTimeScale.Create);
  else
    Result := TTyIntervalScale.Create;
  end;
end;

function TyBuildGrids(AOption: TTyChartOption; const AViewport: TTyRectF): TTyChartBuild;
var
  build: TTyChartBuild;
  gridCount, xCount, yCount, i, j, k, gi: Integer;
  gridIds: TTyStringArray;
  node: TJSONObject;
  spec: TTyBoxSpec;
  ax: TTyAxis;
  synth: Boolean;
  usedBottom, usedLeft: Boolean;
  pos: string;
  c: TTyCartesian2D;
  n: Integer;

  procedure BuildAxisFamily(const AMainType: string; AHorizontal: Boolean;
    var ATarget: TTyAxisArray; ACount: Integer);
  var
    q: Integer;
    nd: TJSONObject;
    a: TTyAxis;
    t: TTyAxisType;
    u: string;
  begin
    SetLength(ATarget, ACount);
    for q := 0 to ACount - 1 do
    begin
      nd := ObjOf(AOption.ComponentAt(AMainType, q));
      if not TyResolveAxisType(nd, t, u) then
        build.Note(Format(rsTyChartAxisTypeUnknown, [AMainType, q, u]));
      a := TTyAxis.Create(Copy(AMainType, 1, 1), MakeScale(t, nd), AHorizontal);
      { `useUTC` IS A ROOT OPTION, not an axis one -- upstream reads it once
        off the top of the tree and every time axis in the chart obeys it. }
      if a.Scale is TTyTimeScale then
        TTyTimeScale(a.Scale).UTC := AOption.GetBool('useUTC', False);
      a.MainType := AMainType;
      a.ComponentIndex := q;
      a.Id := StrIn(nd, 'id', '');
      a.Name := AxisNameIn(nd);
      a.AxisType := t;
      if t = atCategory then
        ReadCategories(nd, a);
      { Category axes band by default; the setter refuses to band anything
        else, so a value axis' boundaryGap -- which is a pair of percentages,
        not a boolean -- cannot turn this on by accident. }
      a.OnBand := (t = atCategory) and BoolIn(nd, 'boundaryGap', True);
      a.Inverse := BoolIn(nd, 'inverse', False);
      { `show` decides whether the axis is DRAWN, not whether it exists: series
        bound to a hidden axis still get their extents and their coordinates.
        Read here so the flag reaches the renderer -- before this it was read
        only into the layout spec, where it shrank the reserved thickness and
        the axis was then drawn anyway. }
      a.Visible := BoolIn(nd, 'show', True);
      ATarget[q] := a;
    end;
  end;

begin
  build := TTyChartBuild.Create;
  Result := build;
  if AOption = nil then Exit;

  xCount := AOption.ComponentCount('xAxis');
  yCount := AOption.ComponentCount('yAxis');
  gridCount := AOption.ComponentCount('grid');

  { A default grid appears only when BOTH families are present. One alone
    creates no grid at all, which is upstream's rule and not an oversight: an
    x axis with nothing to plot against has no rect to live in. }
  synth := (gridCount = 0) and (xCount > 0) and (yCount > 0);
  if synth then gridCount := 1;
  if (gridCount = 0) and (xCount + yCount > 0) then
    build.Note(rsTyChartAxisWithoutPair);

  SetLength(gridIds, gridCount);
  for i := 0 to gridCount - 1 do
  begin
    if synth then node := nil else node := ObjOf(AOption.ComponentAt('grid', i));
    gridIds[i] := StrIn(node, 'id', '');
  end;

  BuildAxisFamily('xAxis', True, build.FXAxes, xCount);
  BuildAxisFamily('yAxis', False, build.FYAxes, yCount);

  { Assign axes to grids and default their sides. The used-flags are declared
    INSIDE this loop on purpose: they restart per grid, so grid 1's first x axis
    is at the bottom again rather than continuing grid 0's allocation. Only the
    bottom flag is consulted for x and only the left flag for y, which is why a
    THIRD x axis also lands on top -- axes stack by an offset, not by running
    out of sides. }
  SetLength(build.FGrids, gridCount);
  for i := 0 to gridCount - 1 do
  begin
    build.FGrids[i] := TTyGridBuild.Create(i);
    if synth then node := nil else node := ObjOf(AOption.ComponentAt('grid', i));

    spec := TyBoxSpec;
    MergedBoxDim(node, 'left', 'right', 'width', TyBoxPercent(GridDefaultLeft),
      TyBoxPercent(GridDefaultRight), TyBoxAuto, spec.Left, spec.Right, spec.Width);
    MergedBoxDim(node, 'top', 'bottom', 'height', TyBoxPx(GridDefaultTop),
      TyBoxPx(GridDefaultBottom), TyBoxAuto, spec.Top, spec.Bottom, spec.Height);
    { AS UPSTREAM'S getLayoutRect GIVES IT: a width that was given is the
      width, and the right edge is x + width }
    build.FGrids[i].FOuterXYWH := TySolveBoxXYWH(spec, TyFixedContainer(AViewport));
    build.FGrids[i].FOuterRect := TyRectOfXYWH(build.FGrids[i].FOuterXYWH);
    build.FViewport := AViewport;
    build.FGrids[i].FPlotXYWH := build.FGrids[i].FOuterXYWH;
    build.FGrids[i].FPlotRect := build.FGrids[i].FOuterRect;

    usedBottom := False;
    usedLeft := False;

    for j := 0 to High(build.FXAxes) do
    begin
      ax := build.FXAxes[j];
      node := ObjOf(AOption.ComponentAt('xAxis', j));
      gi := ResolveGridIndex(node, gridCount, gridIds);
      ax.GridIndex := gi;
      if gi <> i then Continue;
      pos := StrIn(node, 'position', '');
      if (pos <> 'top') and (pos <> 'bottom') then
      begin
        if usedBottom then pos := 'top' else pos := 'bottom';
      end;
      if pos = 'top' then ax.Side := asTop else ax.Side := asBottom;
      { Unconditional, so an explicit position consumes the slot too. }
      if pos = 'bottom' then usedBottom := True;
      n := Length(build.FGrids[i].FXAxes);
      SetLength(build.FGrids[i].FXAxes, n + 1);
      build.FGrids[i].FXAxes[n] := ax;
    end;

    for j := 0 to High(build.FYAxes) do
    begin
      ax := build.FYAxes[j];
      node := ObjOf(AOption.ComponentAt('yAxis', j));
      gi := ResolveGridIndex(node, gridCount, gridIds);
      ax.GridIndex := gi;
      if gi <> i then Continue;
      pos := StrIn(node, 'position', '');
      if (pos <> 'left') and (pos <> 'right') then
      begin
        if usedLeft then pos := 'right' else pos := 'left';
      end;
      if pos = 'right' then ax.Side := asRight else ax.Side := asLeft;
      if pos = 'left' then usedLeft := True;
      n := Length(build.FGrids[i].FYAxes);
      SetLength(build.FGrids[i].FYAxes, n + 1);
      build.FGrids[i].FYAxes[n] := ax;
    end;
  end;

  for i := 0 to High(build.FXAxes) do
    if build.FXAxes[i].GridIndex < 0 then
      build.Note(Format(rsTyChartXAxisNoGrid, [i]));
  for i := 0 to High(build.FYAxes) do
    if build.FYAxes[i].GridIndex < 0 then
      build.Note(Format(rsTyChartYAxisNoGrid, [i]));

  { The N x M cross product. A grid missing either family gets NO coordinate
    system at all -- one orphaned axis takes the whole plot its partner was on
    with it, which is upstream's behaviour and the honest one: half a cartesian
    cannot place a datum. }
  for i := 0 to High(build.FGrids) do
  begin
    if (build.FGrids[i].XAxisCount = 0) or (build.FGrids[i].YAxisCount = 0) then
    begin
      if build.FGrids[i].XAxisCount + build.FGrids[i].YAxisCount > 0 then
        build.Note(Format(rsTyChartGridOneDirection, [i]));
      Continue;
    end;
    for j := 0 to build.FGrids[i].XAxisCount - 1 do
      for k := 0 to build.FGrids[i].YAxisCount - 1 do
      begin
        c := TTyCartesian2D.Create;
        { The axes belong to the build: the same one is in several of these. }
        c.OwnsAxes := False;
        c.AddAxis(build.FGrids[i].FXAxes[j]);
        c.AddAxis(build.FGrids[i].FYAxes[k]);
        { The approximate pixel extent. Phase C writes the final one. }
        c.SetRectXYWH(build.FGrids[i].FOuterXYWH);
        n := Length(build.FGrids[i].FCartesians);
        SetLength(build.FGrids[i].FCartesians, n + 1);
        SetLength(build.FGrids[i].FKeys, n + 1);
        build.FGrids[i].FCartesians[n] := c;
        { GLOBAL component indices, not the per-grid ones -- this key is what a
          series' xAxisIndex and yAxisIndex will be looked up by. }
        build.FGrids[i].FKeys[n] :=
          'x' + IntToStr(build.FGrids[i].FXAxes[j].ComponentIndex) +
          'y' + IntToStr(build.FGrids[i].FYAxes[k].ComponentIndex);
      end;
  end;
end;

{ ==================== reading series data ==================== }

{ One `show` in a furniture node: the option's word, or the default, with
  `auto` resolved by AAuto.

  `'auto'` IS A THIRD VALUE AND NOT A SYNONYM FOR TRUE. Upstream writes it in
  the defaults of exactly two things -- the domain line and the ticks -- and
  it means `show me only when the other axis is a number line`. A port that
  read it as true would draw the four extra things named above. }
function ShowIn(ANode: TJSONObject; const AKey: string;
  ADefault: Boolean; AAutoDefault: Boolean; AAuto: Boolean): Boolean;
var
  sub: TJSONObject;
  d: TJSONData;
begin
  { The default first, itself possibly `auto`. }
  if AAutoDefault then Result := AAuto else Result := ADefault;
  if ANode = nil then Exit;
  sub := ObjOf(ANode.Find(AKey));
  if sub = nil then Exit;
  d := sub.Find('show');
  if d = nil then Exit;
  if d.JSONType = jtBoolean then Exit(d.AsBoolean);
  if (d.JSONType = jtString) and (d.AsString = 'auto') then Exit(AAuto);
end;

{ A number out of a furniture node, or ADefault. }
function SubNumIn(ANode: TJSONObject; const AKey, AField: string;
  ADefault: Double): Double;
var
  sub: TJSONObject;
  d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  sub := ObjOf(ANode.Find(AKey));
  if sub = nil then Exit;
  d := sub.Find(AField);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

{ A flag out of a furniture node, or ADefault. }
function SubBoolIn(ANode: TJSONObject; const AKey, AField: string;
  ADefault: Boolean): Boolean;
var
  sub: TJSONObject;
  d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  sub := ObjOf(ANode.Find(AKey));
  if sub = nil then Exit;
  d := sub.Find(AField);
  if (d <> nil) and (d.JSONType = jtBoolean) then Result := d.AsBoolean;
end;

{ `interval` on one sub-node, as a STRIDE. Nought when the option is absent
  or says `auto`.

  A NON-INTEGER IS TRUNCATED, and that is a deliberate divergence. Upstream
  accepts `interval: 2.7`, makes a stride of 3.7 out of it and walks the
  ordinal axis in steps of 3.7, emitting tick values no category has --
  which is incoherent rather than a feature. The port takes the whole part
  and draws every fourth label. }
function IntervalStrideIn(ANode: TJSONObject; const AKey: string): Integer;
var sub: TJSONData; n: Integer;
begin
  Result := 0;
  sub := FindIn(ANode, AKey);
  if (sub = nil) or (sub.JSONType <> jtObject) then Exit;
  sub := TJSONObject(sub).Find('interval');
  if (sub = nil) or (sub.JSONType <> jtNumber) then Exit;
  n := TyTruncOpt(sub.AsFloat);
  { Any non-positive count means `every one of them`. Upstream clamps the
    stride at 1 rather than validating, so `interval: -5` is legal and means
    the same as 0. }
  if n < 0 then n := 0;
  Result := n + 1;
end;

{ `interval` on one sub-node as a count, whole: NaN when absent or `auto`. }
function IntervalIn(ANode: TJSONObject; const AKey: string): Double;
var sub: TJSONData;
begin
  Result := NaN;
  sub := FindIn(ANode, AKey);
  if (sub = nil) or (sub.JSONType <> jtObject) then Exit;
  sub := TJSONObject(sub).Find('interval');
  if (sub = nil) or (sub.JSONType <> jtNumber) or IsNan(sub.AsFloat) then Exit;
  Result := TyTruncOpt(sub.AsFloat);
end;

{ `showMinLabel` / `showMaxLabel` on axisLabel: absent is AUTO, not false. }
function EndLabelIn(ANode: TJSONObject; const AKey: string): TTyAxisEndLabel;
var sub: TJSONData;
begin
  Result := aelAuto;
  sub := FindIn(ANode, 'axisLabel');
  if (sub = nil) or (sub.JSONType <> jtObject) then Exit;
  sub := TJSONObject(sub).Find(AKey);
  if (sub = nil) or (sub.JSONType <> jtBoolean) then Exit;
  if sub.AsBoolean then Result := aelShow else Result := aelHide;
end;

{ axisLabel.formatter, when it is a string. }
function LabelFormatterIn(ANode: TJSONObject; out AFormatter: string): Boolean;
var sub: TJSONData;
begin
  AFormatter := '';
  Result := False;
  sub := FindIn(ANode, 'axisLabel');
  if (sub = nil) or (sub.JSONType <> jtObject) then Exit;
  sub := TJSONObject(sub).Find('formatter');
  if (sub = nil) or (sub.JSONType <> jtString) then Exit;
  AFormatter := sub.AsString;
  Result := True;
end;

function TyAxisTickLabel(AAxis: TTyAxis; AValue: Double;
  AHasFormatter: Boolean; const AFormatter: string): string;
begin
  if AAxis.Scale is TTyOrdinalScale then
    Result := TTyOrdinalScale(AAxis.Scale).GetLabel(AValue)
  else
    Result := TyScaleValueLabel(AAxis.Scale, AValue, Default(TTyLabelPrecision));
  { String.replace with a string pattern: the first occurrence, as written,
    case and all. The label never carries a '$', so none of replace's '$'
    patterns can fire. }
  if AHasFormatter then
    Result := StringReplace(AFormatter, '{value}', Result, []);
end;

function TyAxisFurnitureOf(ANode: TJSONObject; AAxis: TTyAxis;
  AOtherIsValue: Boolean): TTyAxisFurniture;
var
  cat, tickAuto: Boolean;
  d, sub: TJSONData;
begin
  Result := Default(TTyAxisFurniture);
  if AAxis = nil then Exit;
  cat := AAxis.AxisType = atCategory;

  { THE TICK'S `auto` HAS A SECOND CLAUSE, and it is the reason a plain bar
    chart has no ticks under its categories: a banded category axis suppresses
    them even when the other axis is a number line, because a tick between two
    bands points at nothing in particular. Take the boundary gap away --
    `boundaryGap: false` -- and the ticks come back. }
  tickAuto := AOtherIsValue;
  if cat and AAxis.OnBand then tickAuto := False;

  { axisLine.show: `true` on a category axis, `auto` on every other kind. }
  Result.ShowLine := ShowIn(ANode, 'axisLine', True, not cat, AOtherIsValue);
  { axisTick.show: `auto` on every kind. }
  Result.ShowTicks := ShowIn(ANode, 'axisTick', True, True, tickAuto);
  Result.ShowLabels := ShowIn(ANode, 'axisLabel', True, False, True);
  { splitLine.show: TRUE on a value or log axis, FALSE on a category or a
    time one -- so a bar chart's horizontal grid comes from the value axis and
    the vertical lines it does not have would have come from the category one. }
  Result.ShowSplitLine := ShowIn(ANode, 'splitLine',
    not (cat or (AAxis.AxisType = atTime)), False, True);
  Result.ShowSplitArea := ShowIn(ANode, 'splitArea', False, False, True);
  { The minor pair is a value-axis affair: a category axis has nothing to
    subdivide. }
  Result.ShowMinorTick := (not cat)
    and ShowIn(ANode, 'minorTick', False, False, True);
  Result.ShowMinorSplitLine := (not cat)
    and ShowIn(ANode, 'minorSplitLine', False, False, True);

  { THE LABEL STRIDE DRIVES THE TICKS, one way. `axisTick.interval` defaults
    to `auto`, and `auto` on the ticks does not mean `work one out` -- it
    means `whatever the labels are doing`, which is why a stride of nought
    here is later read as `follow the labels` rather than `measure`. }
  if cat then
  begin
    Result.LabelStep := IntervalStrideIn(ANode, 'axisLabel');
    Result.TickStep := IntervalStrideIn(ANode, 'axisTick');
  end;
  Result.ShowMinLabel := EndLabelIn(ANode, 'showMinLabel');
  Result.ShowMaxLabel := EndLabelIn(ANode, 'showMaxLabel');
  Result.TickInterval := NaN;
  Result.SplitLineInterval := NaN;
  Result.SplitAreaInterval := NaN;
  if cat then
  begin
    Result.TickInterval := IntervalIn(ANode, 'axisTick');
    Result.SplitLineInterval := IntervalIn(ANode, 'splitLine');
    Result.SplitAreaInterval := IntervalIn(ANode, 'splitArea');
  end;
  Result.SplitLineAlign := SubBoolIn(ANode, 'splitLine', 'alignWithLabel', False);
  Result.SplitAreaAlign := SubBoolIn(ANode, 'splitArea', 'alignWithLabel', False);
  Result.MinorTickOption := ShowIn(ANode, 'minorTick', False, False, True);
  if cat then
  begin
    d := FindIn(ObjOf(FindIn(ANode, 'axisLabel')), 'interval');
    Result.ShowAllLabels := (d <> nil) and (d.JSONType = jtNumber)
      and (not IsNan(d.AsFloat)) and (d.AsFloat = 0);
  end;
  d := FindIn(ObjOf(FindIn(ANode, 'axisLabel')), 'hideOverlap');
  Result.HideOverlap := (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
    or ((d.JSONType = jtNumber) and (not IsNan(d.AsFloat)) and (d.AsFloat <> 0))
    or ((d.JSONType = jtString) and (d.AsString <> ''))
    or (d.JSONType in [jtArray, jtObject]));

  Result.TickInside := SubBoolIn(ANode, 'axisTick', 'inside', False);
  Result.LabelInside := SubBoolIn(ANode, 'axisLabel', 'inside', False);
  Result.AlignWithLabel :=
    SubBoolIn(ANode, 'axisTick', 'alignWithLabel', False);
  Result.ShowMinLine := SubBoolIn(ANode, 'splitLine', 'showMinLine', True);
  Result.ShowMaxLine := SubBoolIn(ANode, 'splitLine', 'showMaxLine', True);
  Result.TickLengthLogical := SubNumIn(ANode, 'axisTick', 'length', NaN);
  Result.MinorTickLengthLogical :=
    SubNumIn(ANode, 'minorTick', 'length', NaN);
  Result.LabelMarginLogical := SubNumIn(ANode, 'axisLabel', 'margin', NaN);
  Result.LabelRotateDeg := SubNumIn(ANode, 'axisLabel', 'rotate', 0);
  Result.HasLabelFormatter := LabelFormatterIn(ANode, Result.LabelFormatter);
  Result.OffsetLogical := 0;
  if ANode <> nil then
  begin
    d := ANode.Find('offset');
    if (d <> nil) and (d.JSONType = jtNumber) then
      Result.OffsetLogical := d.AsFloat;
  end;
  { `auto` is truthy. Only a written FALSE turns it off, and upstream keeps a
    comment saying the inconsistency between `onZero: undefined` (off) and
    an absent key (on) is preserved for compatibility -- an absent key is all
    this port can see, so it reads as on. }
  Result.OnZero := SubBoolIn(ANode, 'axisLine', 'onZero', True);
  Result.OnZeroAuto := True;
  Result.OnZeroAxisIndex := -1;
  if ANode <> nil then
  begin
    d := ObjOf(ANode.Find('axisLine'));
    if d <> nil then
    begin
      sub := TJSONObject(d).Find('onZero');
      Result.OnZeroAuto := (sub = nil) or (sub.JSONType = jtNull)
        or ((sub.JSONType = jtString) and (sub.AsString = 'auto'));
      d := TJSONObject(d).Find('onZeroAxisIndex');
      if (d <> nil) and (d.JSONType = jtNumber) then
        Result.OnZeroAxisIndex := TyTruncOpt(d.AsFloat, -1);
    end;
  end;
end;

function TySeriesCartesianDims(ACart: TTyCartesian2D;
  AExtraCount: Integer): TTySeriesDimArray;
var
  i, n: Integer;
  ax: TTyAxis;

  function KindOf(AAxis: TTyAxis): TTyDimType;
  begin
    case AAxis.AxisType of
      atCategory: Result := ddtOrdinal;
      atTime: Result := ddtTime;
    else
      Result := ddtFloat;
    end;
  end;

begin
  Result := nil;
  if ACart = nil then Exit;
  n := ACart.AxisCount;
  if AExtraCount < 0 then AExtraCount := 0;
  SetLength(Result, n + AExtraCount);
  for i := 0 to n - 1 do
  begin
    ax := ACart.GetAxis(i);
    Result[i].Name := ax.Dim;
    Result[i].Kind := KindOf(ax);
    if Result[i].Kind = ddtOrdinal then Result[i].Axis := ax else Result[i].Axis := nil;
  end;
  for i := 0 to AExtraCount - 1 do
  begin
    if i = 0 then Result[n].Name := 'value'
    else Result[n + i].Name := 'value' + IntToStr(i - 1);
    Result[n + i].Kind := ddtFloat;
    Result[n + i].Axis := nil;
  end;
end;

{ The item's value, unwrapped one level: an object with a non-null value hands
  that over, and anything else IS its own value -- including an object without
  one, which then parses to no-data.

  The null check is upstream's rule rather than an observable difference HERE:
  a null and a value-less object both reach no-data through this unit's cell
  mapping, and mutation testing duly found the branch unobservable. It is kept
  because the two stop being the same the moment a non-scalar value means
  something to a series type, and because a rule transcribed faithfully is
  easier to check against the source later than one silently optimised away. }
function UnwrapItem(AItem: TJSONData): TJSONData;
var v: TJSONData;
begin
  Result := AItem;
  if AItem = nil then Exit;
  if not (AItem is TJSONObject) then Exit;
  v := TJSONObject(AItem).Find('value');
  if (v <> nil) and (v.JSONType <> jtNull) then Result := v;
end;

function TySeriesDetectedDimCount(AData: TJSONArray): Integer;
var v: TJSONData;
begin
  Result := 1;
  if (AData = nil) or (AData.Count = 0) then Exit;
  { Item 0 RAW. A leading null is a scalar here, which is where this and the
    row-index question part company. }
  v := UnwrapItem(AData.Items[0]);
  if (v <> nil) and (v is TJSONArray) and (TJSONArray(v).Count > 0) then
    Result := TJSONArray(v).Count;
end;

function FirstCategoryDim(const ADims: TTySeriesDimArray): Integer;
var i: Integer;
begin
  for i := 0 to High(ADims) do
    if ADims[i].Kind = ddtOrdinal then Exit(i);
  Result := -1;
end;

function TySeriesUsesRowIndex(AData: TJSONArray;
  const ADims: TTySeriesDimArray): Boolean;
var
  i: Integer;
  item, v: TJSONData;
begin
  Result := False;
  if FirstCategoryDim(ADims) < 0 then Exit;
  if (AData = nil) or (AData.Count = 0) then Exit;
  { The first NON-NULL item, unlike the column count above. }
  for i := 0 to AData.Count - 1 do
  begin
    item := AData.Items[i];
    if (item = nil) or (item.JSONType = jtNull) then Continue;
    v := UnwrapItem(item);
    Result := not ((v <> nil) and (v is TJSONArray));
    Exit;
  end;
  { NOTHING BUT NULLS: the detected width is item 0's, a null's, which is
    one -- so the category is not in the item and is the row index, and a
    `data: [null]` bar still answers its category's axis tooltip with '-'. }
  Result := True;
end;

{ A JSON scalar as a raw store value. Anything that is not a scalar -- an object
  that had no `value`, a nested array -- is no data, which is what upstream's
  Number(object) produces. }
function CellValue(AData: TJSONData): TTyDataValue;
begin
  if AData = nil then Exit(TyDataNone);
  case AData.JSONType of
    jtNumber: Result := TyDataNum(AData.AsFloat);
    jtString: Result := TyDataText(AData.AsString);
    jtBoolean: Result := TyDataBool(AData.AsBoolean);
  else
    Result := TyDataNone;
  end;
end;

{ A number as an id or a name: convertOptionIdName's `'' + x`, so a name of
  1.23456789 is that and not 1.234568. }
function NumText(AValue: Double): string;
begin
  Result := TyJsNumberToString(AValue);
end;

{ An id or a name as upstream coerces it: a string is kept, a number becomes its
  decimal form, and everything else -- a boolean, an array, an object -- is
  REJECTED rather than stringified. }
function OptionIdName(AData: TJSONData; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  case AData.JSONType of
    jtString: begin AText := AData.AsString; Result := True; end;
    jtNumber: begin AText := NumText(AData.AsFloat); Result := True; end;
  end;
end;

{ Every scalar leaf of a data item, under its DOTTED path, into the store's
  sparse override table.

  Dotted rather than top-level, because every read site downstream is a leaf
  read -- emphasis.itemStyle.color, not emphasis -- so interning the leaf path
  collapses almost the whole surface into scalars and nothing needs a list of
  which keys are supported. A non-scalar leaf (a gradient object, a dash array)
  is SKIPPED rather than stored as no-data: absent and present-but-empty have to
  stay distinguishable, which is the entire point of the table. }
procedure CollectOverrides(AObj: TJSONObject; AStore: TTyDataStore;
  ARawIndex: Integer; const APrefix: string; ADepth: Integer);
var
  i: Integer;
  key, path: string;
  child: TJSONData;
begin
  if (AObj = nil) or (ADepth > 4) then Exit;
  for i := 0 to AObj.Count - 1 do
  begin
    key := AObj.Names[i];
    { Consumed elsewhere: value is the datum, name and id are identity. }
    if (APrefix = '') and ((key = 'value') or (key = 'name') or (key = 'id')) then Continue;
    if APrefix = '' then path := key else path := APrefix + '.' + key;
    child := AObj.Items[i];
    if child = nil then Continue;
    case child.JSONType of
      jtObject:
        CollectOverrides(TJSONObject(child), AStore, ARawIndex, path, ADepth + 1);
      jtNumber, jtString, jtBoolean:
        AStore.SetOverride(ARawIndex, TyOverrideKey(path), CellValue(child));
    end;
  end;
end;

{ A data item AS WRITTEN, for the text a label or a tooltip prints --
  upstream's getDataItemValue, not UnwrapItem: `{value: null}` is a null and
  an object with no `value` is absent, where UnwrapItem hands both back as the
  object. A whisker-box series on a category axis has its row index put in
  front, as upstream's unshift does. }
function RawItemOf(AItem: TJSONData; APrepend: Boolean;
  ARowIndex: Integer): TTyRawItem;
var
  v: TJSONData;
  a: TJSONArray;
  k, off: Integer;
begin
  Result := Default(TTyRawItem);
  if (AItem = nil) or (AItem.JSONType = jtNull) then
  begin
    Result.Shape := rshAbsent;
    Exit;
  end;
  v := AItem;
  if AItem is TJSONObject then
  begin
    v := TJSONObject(AItem).Find('value');
    if v = nil then
    begin
      Result.Shape := rshAbsent;
      Exit;
    end;
    if v.JSONType = jtNull then
    begin
      Result.Shape := rshNull;
      Exit;
    end;
  end;
  if v is TJSONArray then
  begin
    a := TJSONArray(v);
    if APrepend then off := 1 else off := 0;
    Result.Shape := rshArray;
    SetLength(Result.Cells, a.Count + off);
    if APrepend then Result.Cells[0] := TyDataNum(ARowIndex);
    for k := 0 to a.Count - 1 do Result.Cells[k + off] := CellValue(a.Items[k]);
  end
  else if v is TJSONObject then
    Result.Shape := rshObject
  else
  begin
    Result.Shape := rshScalar;
    Result.Scalar := CellValue(v);
  end;
end;

{ A declared type by its option spelling; False for none or one unknown. }
function DimTypeOfName(const AName: string; out AType: TTyDimType): Boolean;
begin
  Result := True;
  if AName = 'ordinal' then AType := ddtOrdinal
  else if AName = 'time' then AType := ddtTime
  else if (AName = 'float') or (AName = 'number') then AType := ddtFloat
  else if AName = 'int' then AType := ddtInt
  else Result := False;
end;

{ Declared dimensions, by position: the name `{@name}` finds, the display
  name a tooltip sub-row shows, the declared type. }
procedure DeclareDims(AStore: TTyDataStore; const ADims: TTySourceDimArray);
var k: Integer; t: TTyDimType;
begin
  for k := 0 to High(ADims) do
  begin
    if ADims[k].Name <> '' then AStore.SetRawDimName(k, ADims[k].Name);
    if ADims[k].DisplayName <> '' then AStore.SetRawDimDisplay(k, ADims[k].DisplayName);
    if DimTypeOfName(ADims[k].DimType, t) then AStore.SetRawDimType(k, t);
  end;
end;

function RawNameTaken(AStore: TTyDataStore; const AName: string;
  ACount: Integer): Boolean;
var p: Integer;
begin
  for p := 0 to ACount - 1 do
    if AStore.RawDimName(p) = AName then Exit(True);
  Result := False;
end;

function TyFillSeriesStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ADims: TTySeriesDimArray; AStore: TTyDataStore;
  const AKey: string): Integer;
var
  node: TJSONObject;
  d: TJSONData;
begin
  Result := 0;
  if (AOption = nil) or (AStore = nil) or (Length(ADims) = 0) then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if node = nil then Exit;
  { AKey IS NOT ALWAYS `data`: a graph's node list has a second name. }
  d := node.Find(AKey);
  if (d = nil) or (d.JSONType = jtNull) or not (d is TJSONArray) then Exit;
  Result := TyFillSeriesStoreArray(AOption, ASeriesIndex, TJSONArray(d), ADims, AStore);
end;

function TyFillSeriesStoreArray(AOption: TTyChartOption; ASeriesIndex: Integer;
  AArray: TJSONArray; const ADims: TTySeriesDimArray; AStore: TTyDataStore): Integer;
var
  node: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  row: array of TTyDataValue;
  i, k, src, catDim, raw, pos: Integer;
  item, v, cell: TJSONData;
  useIndex, prepend: Boolean;
  txt: string;
begin
  Result := 0;
  if (AOption = nil) or (AStore = nil) or (Length(ADims) = 0) or (AArray = nil) then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if node = nil then Exit;
  arr := AArray;

  catDim := FirstCategoryDim(ADims);
  useIndex := TySeriesUsesRowIndex(arr, ADims);
  SetLength(row, Length(ADims));

  { THE RAW SIDE. A category column on the row index means upstream put the
    index in FRONT of every item (whiskerBoxCommon), which moves every other
    element one place on. }
  prepend := False;
  for k := 0 to High(ADims) do
    if ADims[k].FromRowIndex and (ADims[k].Kind = ddtOrdinal) then prepend := True;
  for k := 0 to High(ADims) do
  begin
    if ADims[k].FromRowIndex then
    begin
      if prepend then pos := 0 else pos := -1;
    end
    else if ADims[k].SourceSlot > 0 then
    begin
      pos := ADims[k].SourceSlot - 1;
      if prepend then Inc(pos);
    end
    else
      pos := k;
    AStore.SetRawDimPos(k, pos);
    { A WHISKER BOX'S ROW INDEX is the registry's dimension `base`; its value
      columns are the DECLARED open, close, lowest, highest -- which is what
      makes a candlestick's tooltip rows. }
    if ADims[k].FromRowIndex and prepend then
      AStore.SetRawDimDisplay(pos, 'base');
    if (ADims[k].Coord <> '') and (pos >= 0) and (ADims[k].Name <> '') then
      AStore.SetRawDimDisplay(pos, ADims[k].Name);
  end;
  { THE NAMES `{@name}` FINDS: the series' own `dimensions` when it has them
    -- which replace the coordinate names outright -- and otherwise each
    column's name at the position it reads. }
  d := node.Find('dimensions');
  if (d <> nil) and (d is TJSONArray) then
  begin
    { DECLARED: each named one displays too, and its type is its own. }
    DeclareDims(AStore, TySeriesDimsSource(AOption, ASeriesIndex).Dims);
    src := TySeriesDetectedDimCount(arr);
    if prepend then Inc(src);
    AStore.RawWidth := Max(src, TJSONArray(d).Count);
  end
  else
  begin
    for k := 0 to High(ADims) do
      if (AStore.RawDimPos(k) >= 0) and (ADims[k].Name <> '') then
        AStore.SetRawDimName(AStore.RawDimPos(k), ADims[k].Name);
    { EVERY OTHER POSITION THE DATA HAS gets a generated name, in order --
      `value`, then `value0`, `value1`, ... skipping any already taken --
      which is how `{@value}` finds a scatter's third number. }
    src := TySeriesDetectedDimCount(arr);
    if prepend then Inc(src);
    AStore.RawWidth := src;
    raw := -1;
    for pos := 0 to src - 1 do
    begin
      if AStore.RawDimName(pos) <> '' then Continue;
      repeat
        if raw < 0 then txt := 'value' else txt := 'value' + IntToStr(raw);
        Inc(raw);
      until not RawNameTaken(AStore, txt, src);
      AStore.SetRawDimName(pos, txt);
    end;
  end;

  for i := 0 to arr.Count - 1 do
  begin
    item := arr.Items[i];
    v := UnwrapItem(item);
    for k := 0 to High(ADims) do
    begin
      if ADims[k].FromRowIndex or (useIndex and (k = catDim)) then
      begin
        { The row index -- either because this column asked for it, or because
          the store-wide guess says the items are not arrays and this is the
          first category column. Every other column still reads the item. }
        row[k] := TyDataNum(i);
        Continue;
      end;
      src := k;
      if ADims[k].SourceSlot > 0 then src := ADims[k].SourceSlot - 1;
      if (v <> nil) and (v is TJSONArray) then
      begin
        if src < TJSONArray(v).Count then cell := TJSONArray(v).Items[src]
        else cell := nil;
        row[k] := CellValue(cell);
      end
      else
        { NOT a bug and not a guard worth adding: a scalar goes to EVERY column,
          so `data: [5]` on a pair of value axes really does put 5 on both. It
          is what upstream does, and the category case -- where it would be
          visible -- is exactly the case the row index takes over. }
        row[k] := CellValue(v);
    end;
    raw := AStore.AppendRow(row);
    Inc(Result);
    AStore.SetRawItem(raw, RawItemOf(item, prepend, i));

    if not (item is TJSONObject) then Continue;
    if OptionIdName(TJSONObject(item).Find('name'), txt) then AStore.SetName(raw, txt);
    if OptionIdName(TJSONObject(item).Find('id'), txt) then AStore.SetId(raw, txt);
    CollectOverrides(TJSONObject(item), AStore, raw, '', 0);
  end;
  AStore.GuessRawOrdinals(True);
end;

function TyFillStoreFromSource(const ASource: TTyChartSource;
  const AEncode: TTySeriesEncode; const ADims: TTySeriesDimArray;
  AStore: TTyDataStore): Integer;
var
  row: array of TTyDataValue;
  i, k, n, col, raw: Integer;
  cell: TJSONData;
  nm: string;
  named: Boolean;
  it: TTyRawItem;
  line: TJSONArray;
begin
  Result := 0;
  if (AStore = nil) or (Length(ADims) = 0) then Exit;
  if not ASource.Valid then Exit;
  n := TySourceRowCount(ASource);
  SetLength(row, Length(ADims));

  { THE RAW SIDE: each column at the source dimension it is encoded from, and
    the names the table's own header gives -- or, with no header, the
    columns' own names at those positions. }
  named := False;
  for k := 0 to High(ASource.Dims) do
    if ASource.Dims[k].Name <> '' then
    begin
      AStore.SetRawDimName(k, ASource.Dims[k].Name);
      named := True;
    end;
  DeclareDims(AStore, ASource.Dims);
  AStore.RawWidth := ASource.DimCount;
  for k := 0 to High(ADims) do
  begin
    col := -1;
    if k <= High(AEncode.Columns) then col := AEncode.Columns[k];
    AStore.SetRawDimPos(k, col);
    if (not named) and (col >= 0) and (ADims[k].Name <> '') then
      AStore.SetRawDimName(col, ADims[k].Name);
  end;

  for i := 0 to n - 1 do
  begin
    for k := 0 to High(ADims) do
    begin
      col := -1;
      if k <= High(AEncode.Columns) then col := AEncode.Columns[k];
      if col < 0 then
        row[k] := TyDataNone
      else
        row[k] := CellValue(TySourceCell(ASource, i, col));
    end;
    raw := AStore.AppendRow(row);
    Inc(Result);

    { upstream's getItem: a column-layout row is the line itself, every cell
      of it; a row-layout record is rebuilt across every line; an object row
      is an object whose reachable fields are the source dimensions. }
    it := Default(TTyRawItem);
    if (ASource.Format = tsfArrayRows) and (ASource.LayoutBy = slbColumn) then
    begin
      line := nil;
      if (ASource.Data <> nil) and (i + ASource.StartIndex < ASource.Data.Count)
        and (ASource.Data.Items[i + ASource.StartIndex] is TJSONArray) then
        line := TJSONArray(ASource.Data.Items[i + ASource.StartIndex]);
      if line = nil then it.Shape := rshAbsent
      else
      begin
        it.Shape := rshArray;
        SetLength(it.Cells, line.Count);
        for k := 0 to line.Count - 1 do it.Cells[k] := CellValue(line.Items[k]);
      end;
    end
    else
    begin
      if ASource.Format = tsfObjectRows then it.Shape := rshObject
      else it.Shape := rshArray;
      if (ASource.Format = tsfArrayRows) and (ASource.Data <> nil) then
        col := ASource.Data.Count
      else
        col := ASource.DimCount;
      SetLength(it.Cells, col);
      for k := 0 to col - 1 do it.Cells[k] := CellValue(TySourceCell(ASource, i, k));
    end;
    AStore.SetRawItem(raw, it);

    { THE ROW'S OWN NAME comes from a column rather than from a `name` field:
      a dataset row has no fields outside its dimensions. }
    if AEncode.ItemName >= 0 then
    begin
      cell := TySourceCell(ASource, i, AEncode.ItemName);
      if (cell <> nil) and (cell.JSONType <> jtNull) then
      begin
        nm := cell.AsString;
        if nm <> '' then AStore.SetName(raw, nm);
      end;
    end;
  end;
  AStore.GuessRawOrdinals(False);
end;

{ ==================== phase C ==================== }

{ The spec this axis was laid out with, or nil before phase C. }
function TTyGridBuild.SpecFor(AAxis: TTyAxis): PTyAxisLayoutSpec;
var i: Integer;
begin
  Result := nil;
  if AAxis = nil then Exit;
  for i := 0 to XAxisCount - 1 do
    if XAxis(i) = AAxis then
    begin
      if i <= High(FSpecs) then Result := @FSpecs[i];
      Exit;
    end;
  for i := 0 to YAxisCount - 1 do
    if YAxis(i) = AAxis then
    begin
      if XAxisCount + i <= High(FSpecs) then Result := @FSpecs[XAxisCount + i];
      Exit;
    end;
end;

function TTyGridBuild.FurnitureFor(AAxis: TTyAxis): TTyAxisFurniture;
var i: Integer;

begin
  Result := Default(TTyAxisFurniture);
  Result.ShowLine := True;
  Result.ShowTicks := True;
  Result.ShowLabels := True;
  Result.ShowMinLine := True;
  Result.ShowMaxLine := True;
  Result.OffsetLogical := 0;
  Result.OnZero := True;
  Result.OnZeroAuto := True;
  Result.OnZeroAxisIndex := -1;
  Result.TickLengthLogical := NaN;
  Result.MinorTickLengthLogical := NaN;
  Result.LabelMarginLogical := NaN;
  if AAxis = nil then Exit;
  for i := 0 to XAxisCount - 1 do
    if XAxis(i) = AAxis then
    begin
      if i <= High(FFurniture) then Result := FFurniture[i];
      Exit;
    end;
  for i := 0 to YAxisCount - 1 do
    if YAxis(i) = AAxis then
    begin
      if XAxisCount + i <= High(FFurniture) then
        Result := FFurniture[XAxisCount + i];
      Exit;
    end;
end;



function CanProvideZero(AAxis: TTyAxis; AAuto: Boolean): Boolean;
var e: TTyRange;
begin
  Result := False;
  if (AAxis = nil) or (AAxis.Scale = nil) then Exit;
  { A BAR'S HALF WIDTH MOVED THIS ONE'S ZERO off where its bars start, and an
    axis that only asked for `auto` does not follow it there. }
  if AAuto and AAxis.ZeroDiscouraged then Exit;
  { A CATEGORY OR TIME AXIS NEVER PROVIDES ONE, however plainly it crosses
    zero -- upstream calls this historical and keeps it. }
  if AAxis.AxisType in [atCategory, atTime] then Exit;
  e := AAxis.Scale.GetExtent;
  if IsNan(e.Start) or IsNan(e.Stop) then Exit;
  { Zero at an END counts; zero strictly outside does not. So a log axis, whose
    extent cannot reach zero, is never a provider. }
  Result := (Min(e.Start, e.Stop) <= 0) and (Max(e.Start, e.Stop) >= 0);
end;

function TTyGridBuild.OnZeroProviderFor(AAxis: TTyAxis): TTyAxis;
var
  i, j: Integer;
  furn: TTyAxisFurniture;
  cand, other: TTyAxis;
  taken: Boolean;

  { The other family, in declaration order. }
  function OtherCount: Integer;
  begin
    if AAxis.Horizontal then Result := YAxisCount else Result := XAxisCount;
  end;

  function OtherAt(AIndex: Integer): TTyAxis;
  begin
    if AAxis.Horizontal then Result := YAxis(AIndex) else Result := XAxis(AIndex);
  end;

  function SameFamilyCount: Integer;
  begin
    if AAxis.Horizontal then Result := XAxisCount else Result := YAxisCount;
  end;

  function SameFamilyAt(AIndex: Integer): TTyAxis;
  begin
    if AAxis.Horizontal then Result := XAxis(AIndex) else Result := YAxis(AIndex);
  end;

begin
  Result := nil;
  if AAxis = nil then Exit;
  furn := FurnitureFor(AAxis);
  if not furn.OnZero then Exit;

  { NAMED EXPLICITLY: take it or take nothing. Upstream's `else` belongs to
    the `if (onZeroAxisIndex != null)`, so an index that names an axis which
    cannot provide a zero does NOT fall through to the scan -- it turns the
    whole thing off. }
  if furn.OnZeroAxisIndex >= 0 then
  begin
    if furn.OnZeroAxisIndex < OtherCount then
    begin
      cand := OtherAt(furn.OnZeroAxisIndex);
      if CanProvideZero(cand, furn.OnZeroAuto) then Result := cand;
    end;
    Exit;
  end;

  { THE FIRST THAT QUALIFIES AND IS NOT ALREADY SPOKEN FOR. Without the second
    half, two y axes that both ask would both land on the same x axis' zero and
    draw on top of each other -- which is the comment upstream leaves beside
    the same test. Who is spoken for is decided by walking this family in
    declaration order and asking each earlier axis the same question. }
  for i := 0 to OtherCount - 1 do
  begin
    cand := OtherAt(i);
    if not CanProvideZero(cand, furn.OnZeroAuto) then Continue;
    taken := False;
    for j := 0 to SameFamilyCount - 1 do
    begin
      other := SameFamilyAt(j);
      if other = AAxis then Break;
      if OnZeroProviderFor(other) = cand then
      begin
        taken := True;
        Break;
      end;
    end;
    if taken then Continue;
    Exit(cand);
  end;
end;

function TTyGridBuild.AxisLineCoord(AAxis: TTyAxis; APPI: Integer): Double;
var
  furn: TTyAxisFurniture;
  provider: TTyAxis;
  off, lo, hi: Double;
begin
  Result := 0;
  if AAxis = nil then Exit;
  furn := FurnitureFor(AAxis);
  off := AxisScaleF(furn.OffsetLogical, APPI);

  { THE TWO ENDS OF WHAT IS REACHABLE. Positive offset always means AWAY from
    the plot, so the low end moves down and the high end up -- it is a side,
    not a screen direction. }
  if AAxis.Horizontal then
  begin
    lo := FPlotRect.Top - off;
    hi := FPlotRect.Bottom + off;
  end
  else
  begin
    lo := FPlotRect.Left - off;
    hi := FPlotRect.Right + off;
  end;

  provider := OnZeroProviderFor(AAxis);
  if provider <> nil then
  begin
    { CLAMPED INTO THE REACHABLE RANGE, which the offset has already widened --
      so an offset written alongside onZero does not move the LINE, it only
      gives the clamp more room.

      THE CLAMP IS UNREACHABLE TODAY and is kept anyway. CanProvideZero has
      already refused any provider whose extent does not contain zero, so
      DataToCoord(0) is inside the plot by construction and there is nothing
      for the clamp to catch -- a mutation that deletes it survives, and it
      is recorded here rather than tidied away because upstream carries the
      same pair. The day a mapping extent differs from the effective one,
      or a break makes the axis discontinuous, this is the net. }
    Result := provider.DataToCoord(0);
    Result := Max(lo, Min(hi, Result));
    Exit;
  end;

  case AAxis.Side of
    asTop: Result := lo;
    asBottom: Result := hi;
    asLeft: Result := lo;
    asRight: Result := hi;
  end;
end;
function TTyGridBuild.NameFrameFor(AAxis: TTyAxis;
  const ASpec: TTyAxisLayoutSpec; APPI: Integer): TTyAxisNameFrame;
var line: Double;
begin
  { upstream's layout(): posBound from the rect and the offset, the line on
    the raw side of it unless the other family's zero takes it }
  Result := TyDefaultNameFrame(ASpec, FPlotRect, APPI);
  { THE EXTENT IS THE AXIS' OWN, [0, w] -- not the right edge less the left,
    which need not come back to w -- and a name at the end stands off it }
  if AAxis <> nil then
    AAxis.LocalExtent(Result.Ext0, Result.Ext1);
  if (AAxis = nil) or (OnZeroProviderFor(AAxis) = nil) then Exit;
  line := AxisLineCoord(AAxis, APPI);
  if AAxis.Horizontal then
  begin
    Result.LabelOffset := Result.PosY - line;
    Result.PosY := line;
  end
  else
  begin
    Result.LabelOffset := Result.PosX - line;
    Result.PosX := line;
  end;
end;

procedure TyLayoutGrids(ABuild: TTyChartBuild; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  const AText: TTyAxisTextStyle);
var
  g, i, j, t: Integer;
  specs: TTyAxisLayoutSpecArray;
  furn: array of TTyAxisFurniture;
  xIsValue, yIsValue: Boolean;
  ax: TTyAxis;
  ticks: TTyScaleTickArray;
  gb: TTyGridBuild;
  node, gridNode: TJSONObject;
  containLabel: Boolean;
  names: TTyAxisNamePlacementArray;
  vp: TTyRectF;
  { whether the grid's estimate ran, and whether it overflowed anything }
  estimated, noPx: Boolean;
  est: TTyAxisLabelPlacementArray;

  { `grid.containLabel` in JavaScript's truthiness: true, a non-zero number,
    a non-empty string, any object }
  function ContainLabelOn(AGridNode: TJSONObject): Boolean;
  var d: TJSONData;
  begin
    Result := False;
    if AGridNode = nil then Exit;
    d := AGridNode.Find('containLabel');
    Result := (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
      or ((d.JSONType = jtNumber) and (not IsNan(d.AsFloat)) and (d.AsFloat <> 0))
      or ((d.JSONType = jtString) and (d.AsString <> ''))
      or (d.JSONType in [jtArray, jtObject]));
  end;

  { the grid's axes by spec index: the x axes, then the y axes }
  function AxisAt(AGrid: TTyGridBuild; AIndex: Integer): TTyAxis;
  begin
    if AIndex < AGrid.XAxisCount then Result := AGrid.XAxis(AIndex)
    else Result := AGrid.YAxis(AIndex - AGrid.XAxisCount);
  end;

  { THE FURNITURE ON THE FINAL RECT. A category axis' tick marks, split
    lines and split areas each walk their own interval -- the labels' when
    they say nothing, whether or not the labels are drawn -- and, on a
    banded axis, are moved back half a band onto the edges, the last dropped
    when it is off the interval and the edge past the last category added.
    A value, log or time axis has a mark per tick. A tick whose label was
    built and then hidden goes with it, unless it sits on a band edge or the
    minor ticks are shown; a split line at an end can be denied. }
  procedure AxisMarks(AGrid: TTyGridBuild; AAxis: TTyAxis;
    var ASpec: TTyAxisLayoutSpec; const AFurn: TTyAxisFurniture);
  var
    plot: TTyRectF;
    labelIv: Double;
    n, k, i: Integer;
    ticks: TTyScaleTickArray;

    function CategoryMarks(AOptInterval: Double; AAlign: Boolean): TTyAxisMarkArray;
    var
      iv: Double;
      vals: TTyIntegerArray;
      offs: TTyBoolArray;
      q: Integer;
    begin
      if IsNan(AOptInterval) then iv := labelIv else iv := AOptInterval;
      TyCategoryBuiltList(ASpec.OrdinalStart, n, iv, vals, offs);
      Result := nil;
      SetLength(Result, Length(vals));
      for q := 0 to High(vals) do
      begin
        Result[q] := Default(TTyAxisMark);
        Result[q].Value := vals[q];
        Result[q].OffInterval := offs[q];
        { IN THE AXIS' OWN FRAME, as upstream's getTicksCoords: straight from
          the axis, not a canvas coordinate taken back into it }
        Result[q].Coord := AAxis.DataToLocal(vals[q]);
      end;
      TyFixOnBandMarks(Result, AAxis.OnBand, AAlign, AAxis.BandWidth,
        ASpec.OrdinalStart + n - 1);
      for q := 0 to High(Result) do
        Result[q].Coord := AAxis.ToGlobal(Result[q].Coord);
    end;

  begin
    ASpec.TickMarks := nil;
    ASpec.SplitLineMarks := nil;
    ASpec.SplitAreaMarks := nil;
    if (AAxis = nil) or AAxis.Scale.Blank then Exit;
    plot := AGrid.FPlotRect;
    n := Length(ASpec.Labels);
    if ASpec.LabelKind = lakCategory then
    begin
      if n = 0 then Exit;
      labelIv := TyCategoryLabelInterval(ASpec, plot, AMeasurer, APPI);
      ASpec.TickMarks := CategoryMarks(AFurn.TickInterval, AFurn.AlignWithLabel);
      ASpec.SplitLineMarks := CategoryMarks(AFurn.SplitLineInterval, AFurn.SplitLineAlign);
      ASpec.SplitAreaMarks := CategoryMarks(AFurn.SplitAreaInterval, AFurn.SplitAreaAlign);
    end
    else
    begin
      { the majors, as the labels were made from them: one mark per label }
      ticks := TyDrawnTicks(AAxis.Scale);
      SetLength(ASpec.TickMarks, Length(ticks));
      i := 0;
      for k := 0 to High(ticks) do
      begin
        if ticks[k].Level <> 0 then Continue;
        ASpec.TickMarks[i] := Default(TTyAxisMark);
        ASpec.TickMarks[i].Value := ticks[k].Value;
        ASpec.TickMarks[i].Coord := AAxis.DataToCoord(ticks[k].Value);
        Inc(i);
      end;
      SetLength(ASpec.TickMarks, i);
      ASpec.SplitLineMarks := Copy(ASpec.TickMarks);
      ASpec.SplitAreaMarks := Copy(ASpec.TickMarks);
    end;
    { WHICH ARE DRAWN }
    for k := 0 to High(ASpec.TickMarks) do
    begin
      ASpec.TickMarks[k].Drawn := ASpec.ShowTicks;
      if AFurn.MinorTickOption or ASpec.TickMarks[k].OnBand
        or (not ASpec.ShowLabels) then Continue;
      if ASpec.LabelKind = lakCategory then
        i := Round(ASpec.TickMarks[k].Value) - ASpec.OrdinalStart
      else
        i := k;
      if (i >= 0) and (i <= High(ASpec.Placements))
        and ASpec.Placements[i].Built and (not ASpec.Placements[i].Shown) then
        ASpec.TickMarks[k].Drawn := False;
    end;
    for k := 0 to High(ASpec.SplitLineMarks) do
      ASpec.SplitLineMarks[k].Drawn := AFurn.ShowSplitLine
        and not ((k = 0) and not AFurn.ShowMinLine)
        and not ((k = High(ASpec.SplitLineMarks)) and not AFurn.ShowMaxLine);
    for k := 0 to High(ASpec.SplitAreaMarks) do
      ASpec.SplitAreaMarks[k].Drawn := AFurn.ShowSplitArea;
  end;

  { ONE BOUND OF grid.outerBounds on the canvas: upstream merges it into
    {left: 0, right: 0} keeping at most two of left, right and width -- the
    author's own when they wrote two, else theirs and the first default --
    and then getLayoutRect solves it. }
  procedure OuterDim(ANode: TJSONObject; const ALo, AHi, ASize: string;
    AExtent: Double; out APos, ALen: Double);
  var
    lo, hi, sz: TTyBoxValue;
    hasLo, hasHi, hasSz: Boolean;
    n: Integer;
  begin
    hasLo := (ANode <> nil) and (ANode.Find(ALo) <> nil);
    hasHi := (ANode <> nil) and (ANode.Find(AHi) <> nil);
    hasSz := (ANode <> nil) and (ANode.Find(ASize) <> nil);
    n := Ord(hasLo) + Ord(hasHi) + Ord(hasSz);
    lo := TyBoxPx(0);
    hi := TyBoxPx(0);
    sz := TyBoxAuto;
    if hasLo then lo := TyBoxDataOf(ANode.Find(ALo), TyBoxPx(0));
    if hasHi then hi := TyBoxDataOf(ANode.Find(AHi), TyBoxPx(0));
    if hasSz then sz := TyBoxDataOf(ANode.Find(ASize), TyBoxAuto);
    { TWO WRITTEN: only those two, the defaults dropped. One written keeps
      a default beside it, and whichever it keeps comes to the same rect:
      a lone width stands at left 0, a lone left or right runs to the other
      side's 0. }
    if n >= 2 then
    begin
      if not hasLo then lo := TyBoxAuto;
      if not hasHi then hi := TyBoxAuto;
    end;
    if sz.Kind <> buAuto then
    begin
      ALen := TyBoxResolve(sz, AExtent);
      if lo.Kind <> buAuto then APos := TyBoxResolve(lo, AExtent)
      else APos := AExtent - TyBoxResolve(hi, AExtent) - ALen;
    end
    else
    begin
      APos := TyBoxResolve(lo, AExtent);
      ALen := AExtent - TyBoxResolve(hi, AExtent) - APos;
    end;
  end;

  { The grid's plot rect: upstream's resize, after the raw rect. }
  function SolveGridRect(AGrid: TTyGridBuild; AGridNode: TJSONObject;
    const ASpecs: TTyAxisLayoutSpecArray): TTyXYWH;
  var
    rawR: TTyRectF;
    raw, outer: TTyXYWH;
    d: TJSONData;
    s: string;
    contain: TTyOuterBoundsContain;
    ob: TJSONObject;
    cw, ch: Double;
    vp: TTyRectF;
  begin
    rawR := AGrid.FOuterRect;
    raw := AGrid.FOuterXYWH;
    Result := raw;
    estimated := False;
    noPx := True;
    { LEGACY containLabel WINS, and every outerBounds key is ignored }
    if ContainLabelOn(AGridNode) then
      Exit(TyLegacyContainLabelXYWH(raw, ASpecs, AMeasurer, APPI));
    s := '';
    if AGridNode <> nil then
    begin
      d := AGridNode.Find('outerBoundsMode');
      if (d <> nil) and (d.JSONType = jtString) then s := d.AsString
      else if (d <> nil) and (d.JSONType <> jtNull) then s := '?';
    end;
    vp := ABuild.Viewport;
    if s = 'same' then
      outer := raw
    else if (s = '') or (s = 'auto') then
    begin
      { the bounds on the canvas: {left, right, top, bottom: 0} unless
        grid.outerBounds says otherwise }
      ob := nil;
      if AGridNode <> nil then ob := ObjOf(AGridNode.Find('outerBounds'));
      OuterDim(ob, 'left', 'right', 'width', vp.Right - vp.Left, outer.X, outer.W);
      OuterDim(ob, 'top', 'bottom', 'height', vp.Bottom - vp.Top, outer.Y, outer.H);
      outer.X := vp.Left + outer.X;
      outer.Y := vp.Top + outer.Y;
    end
    else
      { 'none' -- and anything upstream does not know, which it ignores too }
      Exit;
    contain := obcAll;
    if (AGridNode <> nil) and (StrIn(AGridNode, 'outerBoundsContain', '') = 'axisLabel') then
      contain := obcAxisLabel;
    { THE CLAMP IS OF THE RAW RECT: a quarter of its width and height unless
      the option says }
    cw := TyBoxResolve(TyBoxPercent(25), raw.W);
    ch := TyBoxResolve(TyBoxPercent(25), raw.H);
    if AGridNode <> nil then
    begin
      d := AGridNode.Find('outerBoundsClampWidth');
      if (d <> nil) and (d.JSONType <> jtNull) then
        cw := TyBoxResolve(TyBoxDataOf(d, TyBoxPercent(25)), raw.W);
      d := AGridNode.Find('outerBoundsClampHeight');
      if (d <> nil) and (d.JSONType <> jtNull) then
        ch := TyBoxResolve(TyBoxDataOf(d, TyBoxPercent(25)), raw.H);
    end;
    { THE NAME MARGIN LEVEL IS OF THE CANVAS: the grid's rect against the
      container it was laid out in }
    Result := TySolveGridBoundsXYWH(rawR, raw, outer, contain, cw, ch, ASpecs,
      AMeasurer, APPI, TyXYWHOfRect(vp), noPx);
    estimated := True;
  end;

  { nameTextStyle's own padding: textMargin, a number or upstream's css
    array, or minMargin, which wins }
  procedure ReadNameMargin(var ASpec: TTyAxisLayoutSpec; AStyle: TJSONObject);
  var
    d: TJSONData;
    a: TJSONArray;
    v: array[0..3] of Double;
    k: Integer;
  begin
    d := FindIn(AStyle, 'minMargin');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      ASpec.NameMarginKind := nmkMinMargin;
      { `minMargin` only supports a number; anything else is none }
      if (d.JSONType = jtNumber) and not IsNan(d.AsFloat) then
        ASpec.NameMinMarginLogical := d.AsFloat
      else
        ASpec.NameMinMarginLogical := 0;
      Exit;
    end;
    d := FindIn(AStyle, 'textMargin');
    if (d = nil) or (d.JSONType = jtNull) then Exit;
    if d.JSONType = jtNumber then
    begin
      for k := 0 to 3 do v[k] := d.AsFloat;
    end
    else if (d is TJSONArray) and (TJSONArray(d).Count in [1..4]) then
    begin
      a := TJSONArray(d);
      for k := 0 to a.Count - 1 do
        if a.Items[k].JSONType <> jtNumber then Exit;
      { normalizeCssArray: [a] [v, h] [t, h, b] [t, r, b, l] }
      case a.Count of
        1: for k := 0 to 3 do v[k] := a.Items[0].AsFloat;
        2: begin
             v[0] := a.Items[0].AsFloat; v[1] := a.Items[1].AsFloat;
             v[2] := v[0]; v[3] := v[1];
           end;
        3: begin
             v[0] := a.Items[0].AsFloat; v[1] := a.Items[1].AsFloat;
             v[2] := a.Items[2].AsFloat; v[3] := v[1];
           end;
      else
        for k := 0 to 3 do v[k] := a.Items[k].AsFloat;
      end;
    end
    else
      Exit;
    ASpec.NameMarginKind := nmkTextMargin;
    for k := 0 to 3 do ASpec.NameMargin[k] := v[k];
  end;

  { EVERYTHING ABOUT THE NAME that the option says: where it goes, the gap,
    the turn, the alignment and padding, and whether it moves out of the
    labels' way. }
  procedure ReadName(var ASpec: TTyAxisLayoutSpec; AAxis: TTyAxis;
    ANode: TJSONObject);
  var
    d: TJSONData;
    st: TJSONObject;
    s: string;
  begin
    ASpec.Inverse := AAxis.Inverse;
    ASpec.NameFontName := AText.NameFontName;
    ASpec.NameFontSizeLogical := AText.NameFontSizeLogical;
    ASpec.NameFontWeight := AText.NameFontWeight;
    { 'end' by default; 'center' is 'middle'. A location upstream does not
      know takes its middle anchor and its end layout there -- here it is
      simply 'end'. }
    s := StrIn(ANode, 'nameLocation', 'end');
    if s = 'start' then ASpec.NameLocation := anlStart
    else if (s = 'middle') or (s = 'center') then ASpec.NameLocation := anlMiddle
    else ASpec.NameLocation := anlEnd;
    { `get('nameGap') || 0`: the theme's when absent, nought for null or
      false, a negative gap kept }
    d := FindIn(ANode, 'nameGap');
    if d <> nil then
    begin
      if d.JSONType = jtNumber then
      begin
        if IsNan(d.AsFloat) then ASpec.NameGapLogical := 0
        else ASpec.NameGapLogical := d.AsFloat;
      end
      else if (d.JSONType = jtNull)
        or ((d.JSONType = jtBoolean) and not d.AsBoolean) then
        ASpec.NameGapLogical := 0;
    end;
    d := FindIn(ANode, 'nameRotate');
    if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat) then
    begin
      ASpec.HasNameRotate := True;
      ASpec.NameRotateRad := d.AsFloat * Pi / 180;
    end;
    st := ObjOf(FindIn(ANode, 'nameTextStyle'));
    if st <> nil then
    begin
      { a truthy string over the layout's own; zrender reads anything but
        'right' and 'center' as left, anything but 'middle' and 'bottom' as
        top }
      s := StrIn(st, 'align', '');
      if s <> '' then
      begin
        ASpec.HasNameAlignH := True;
        if s = 'right' then ASpec.NameAlignH := tahRight
        else if s = 'center' then ASpec.NameAlignH := tahCentre
        else ASpec.NameAlignH := tahLeft;
      end;
      s := StrIn(st, 'verticalAlign', '');
      if s <> '' then
      begin
        ASpec.HasNameAlignV := True;
        if s = 'bottom' then ASpec.NameAlignV := tavBottom
        else if s = 'middle' then ASpec.NameAlignV := tavMiddle
        else ASpec.NameAlignV := tavTop;
      end;
      ReadNameMargin(ASpec, st);
    end;
    { nameMoveOverlap: null and 'auto' are the grid's -- off under legacy
      containLabel, on otherwise; any other value is its truthiness }
    d := FindIn(ANode, 'nameMoveOverlap');
    if (d = nil) or (d.JSONType = jtNull)
      or ((d.JSONType = jtString) and (d.AsString = 'auto')) then
      ASpec.NameNoMove := containLabel
    else if d.JSONType = jtBoolean then
      ASpec.NameNoMove := not d.AsBoolean
    else if d.JSONType = jtNumber then
      ASpec.NameNoMove := IsNan(d.AsFloat) or (d.AsFloat = 0)
    else if d.JSONType = jtString then
      ASpec.NameNoMove := d.AsString = '';
  end;

  procedure FillSpec(var ASpec: TTyAxisLayoutSpec; AAxis: TTyAxis;
    ANode: TJSONObject; const AFurn: TTyAxisFurniture);
  var
    q, kept: Integer;
    lbl, wd: TJSONData;
    ovf: string;
    isTime: Boolean;
    tt: TTyTimeTick;
  begin
    ASpec := Default(TTyAxisLayoutSpec);
    ASpec.Side := AAxis.Side;
    { `axisLabel.show`, NOT the axis' own `show` -- the axis-level one is
      handled at the bottom of this routine. Reading it here as well meant
      `axisLabel: { show: false }` did nothing while a hidden axis was asked
      about twice. }
    ASpec.ShowLabels := AFurn.ShowLabels;
    { legacy containLabel measures these even on a hidden axis }
    ASpec.LegacyLabels := AFurn.ShowLabels;
    ASpec.ShowTicks := AFurn.ShowTicks;
    ASpec.ForcedLabelStep := AFurn.LabelStep;
    ASpec.ShowAllLabels := AFurn.ShowAllLabels;
    ASpec.HideOverlap := AFurn.HideOverlap;
    ASpec.LabelRotateDeg := AFurn.LabelRotateDeg;
    ASpec.OnBand := AAxis.OnBand;
    if AAxis.AxisType = atCategory then ASpec.LabelKind := lakCategory
    else if AAxis.AxisType = atTime then ASpec.LabelKind := lakTime
    else ASpec.LabelKind := lakValue;
    ASpec.TickStep := AFurn.TickStep;
    ASpec.ShowMinLabel := AFurn.ShowMinLabel;
    ASpec.ShowMaxLabel := AFurn.ShowMaxLabel;
    ASpec.TickInside := AFurn.TickInside;
    ASpec.LabelInside := AFurn.LabelInside;
    { AN OFFSET AXIS HANGS FURTHER OUT, so the band it costs is its own
      thickness PLUS the offset -- upstream builds the labels AT the offset
      position and then shrinks the grid by however far they overflow the
      canvas, which comes to the same thing for one axis on a side. }
    ASpec.OffsetLogical := AFurn.OffsetLogical;
    ASpec.Name := AAxis.Name;
    { From the caller's resolved theme style, NOT from literals here: the paint
      pass draws in the theme's font and gaps, so measuring in anything else
      sizes the plot rect for a chart nobody will draw. }
    ASpec.FontName := AText.FontName;
    ASpec.FontSizeLogical := AText.FontSizeLogical;
    ASpec.FontWeight := AText.FontWeight;
    { THE THEME FIRST AND THE OPTION OVER IT. A gap is a geometric value and
      an author is allowed to name one -- the same arrangement
      `axisLabel.width` has already. Colours are the other kind and still
      come from the theme alone. }
    ASpec.LabelMarginLogical := AText.LabelMarginLogical;
    if not IsNan(AFurn.LabelMarginLogical) then
      ASpec.LabelMarginLogical := AFurn.LabelMarginLogical;
    ASpec.TickLengthLogical := AText.TickLengthLogical;
    if not IsNan(AFurn.TickLengthLogical) then
      ASpec.TickLengthLogical := AFurn.TickLengthLogical;
    ASpec.NameGapLogical := AText.NameGapLogical;
    ReadName(ASpec, AAxis, ANode);
    { `xAxis.show: false` MUST GIVE THE GUTTER BACK. Upstream builds nothing
      at all for a hidden axis and skips it again when it folds the shrink,
      so the plot grows into the band. The port hid it at PAINT time only:
      `yAxis: { show: false }` stopped drawing the numbers and went on
      reserving room for them, which is a chart with an empty margin down
      its left-hand side and no way to close it.

      Zeroed rather than skipped because FSpecs is index-parallel to the
      grid's axis lists -- SpecFor and FurnitureFor both walk them by
      position -- and a spec that costs nothing is the same answer. }
    if not AAxis.Visible then
    begin
      ASpec.ShowLabels := False;
      ASpec.ShowTicks := False;
      ASpec.Name := '';
    end;
    { DEGREES IN THE OPTION, RADIANS IN THE LAYOUT, and the same sign in both:
      `rotate` is counter-clockwise positive upstream (AxisBuilder turns it
      straight into the zrender element's `rotation`) and the painter's
      DrawTextRotated is counter-clockwise positive too. Negating it here
      turned every rotated label the wrong way -- invisible while nothing drew
      the rotation at all, because the extent a turn costs is the same either
      way round. }
    { AND A TOP AXIS TURNS THE OTHER WAY, so that `rotate: 45` slants the
      labels away from the plot on both edges instead of into it on one --
      but only where the axis IS on top: one that sits on the other family's
      zero is positioned 'onZero', which upstream never negates.
      [Revised in batch 43: this negated for `position: top` alone, and a
      top category axis over a value axis through zero slanted the wrong way
      with the wrong alignment.] }
    if (AAxis.Side = asTop) and (gb.OnZeroProviderFor(AAxis) = nil) then
      ASpec.RotationRad := -AFurn.LabelRotateDeg * Pi / 180
    else
      ASpec.RotationRad := AFurn.LabelRotateDeg * Pi / 180;
    { MAJORS ONLY. GetTicks hands back majors and minors in one array with
      Level saying which is which, and its own comment says a caller that wants
      only the majors tests Level. This did not -- so `minorTick: { show: true
      }`, which is applied earlier in the same rebuild, multiplied the label
      count by the minor split and asked the layout to fit five times as many
      strings as the axis has numbers. }
    { axisLabel.width + overflow. `none` is ECharts' default and is what this
      already did: no bound, and crowding handled by thinning the labels.

      THE BROKEN TEXT IS PRODUCED HERE, once, and stored in the spec -- so the
      layout measures exactly the string the paint draws. MeasureLine already
      honours the breaks inside a string, so nothing downstream has to know that
      wrapping happened at all. }
    ASpec.LabelWidthLogical := 0;
    ASpec.LabelOverflow := loNone;
    { textMargin: [0, 3] unless the option says -- a number for all four
      sides, or [vertical, horizontal] }
    ASpec.TextMarginVLogical := 0;
    ASpec.TextMarginHLogical := 3;
    if ANode <> nil then
    begin
      lbl := FindIn(ANode, 'axisLabel');
      if (lbl <> nil) and (lbl.JSONType = jtObject) then
      begin
        wd := FindIn(TJSONObject(lbl), 'textMargin');
        if (wd <> nil) and (wd.JSONType = jtNumber) then
        begin
          ASpec.TextMarginVLogical := wd.AsFloat;
          ASpec.TextMarginHLogical := wd.AsFloat;
        end
        else if (wd is TJSONArray) and (TJSONArray(wd).Count >= 2)
          and (TJSONArray(wd).Items[0].JSONType = jtNumber)
          and (TJSONArray(wd).Items[1].JSONType = jtNumber) then
        begin
          ASpec.TextMarginVLogical := TJSONArray(wd).Items[0].AsFloat;
          ASpec.TextMarginHLogical := TJSONArray(wd).Items[1].AsFloat;
        end;
        wd := FindIn(TJSONObject(lbl), 'width');
        if (wd <> nil) and (wd.JSONType = jtNumber) then
          ASpec.LabelWidthLogical := wd.AsFloat;
        ovf := LowerCase(StrIn(TJSONObject(lbl), 'overflow', ''));
        if ovf = 'truncate' then ASpec.LabelOverflow := loTruncate
        else if (ovf = 'break') or (ovf = 'breakall') then
          ASpec.LabelOverflow := loBreak;
      end;
    end;

    ticks := TyDrawnTicks(AAxis.Scale);
    isTime := AAxis.Scale is TTyTimeScale;
    SetLength(ASpec.Labels, Length(ticks));
    SetLength(ASpec.Positions, Length(ticks));
    SetLength(ASpec.TickValues, Length(ticks));
    SetLength(ASpec.LocalCoords, Length(ticks));
    SetLength(ASpec.Proportions, Length(ticks));
    if isTime then
    begin
      SetLength(ASpec.LabelNotNice, Length(ticks));
      SetLength(ASpec.LabelLevel, Length(ticks));
      SetLength(ASpec.LabelEmphasis, Length(ticks));
      { its coarse ticks are the ones that carry the weight }
      ASpec.EmphasisFontWeight := AText.EmphasisFontWeight;
    end;
    kept := 0;
    for q := 0 to High(ticks) do
    begin
      if ticks[q].Level <> 0 then Continue;
      if isTime then
      begin
        tt.Value := ticks[q].Value;
        tt.Unit_ := ticks[q].TimeUnit;
        tt.Level := ticks[q].TimeLevel;
        tt.NotNice := ticks[q].NotNice;
        ASpec.Labels[kept] := TyTimeLabel(tt, TTyTimeScale(AAxis.Scale).UTC);
        { THE TWO RAGGED ENDS. The extent of a time axis is the data's own,
          never rounded outwards, so its first and last ticks are wherever
          the data happens to start and stop; labelling those puts a `07:13`
          hard against the first round hour -- unless the author asks. }
        ASpec.LabelNotNice[kept] := ticks[q].NotNice;
        ASpec.LabelLevel[kept] := ticks[q].TimeLevel;
        { Every level above the finest is emphasised, which is what makes an
          axis read `12 13 14 Feb 2 3` rather than as six equal numbers. }
        ASpec.LabelEmphasis[kept] := ticks[q].TimeLevel >= 1;
      end
      else
        { UPSTREAM'S getLabel, grouped and to the tick's own decimals --
          '1,400,000', '0.0000001', '1e+21' -- and the one routine the paint
          pass calls too, so the width measured here is the width of the string
          drawn. Locale-free: no FormatFloat anywhere on the way. }
        ASpec.Labels[kept] := TyAxisTickLabel(AAxis, ticks[q].Value,
          AFurn.HasLabelFormatter, AFurn.LabelFormatter);
      { The BAND-ADJUSTED, post-inverse fraction, so the layout layer and the
        renderer cannot disagree about where a label goes. }
      { Broken to the width the option asked for, through the measurer: this
        unit is pure and CJK-aware wrapping lives in the painter. }
      if (ASpec.LabelOverflow = loBreak) and (ASpec.LabelWidthLogical > 0)
        and (AMeasurer <> nil) then
        ASpec.Labels[kept] := AMeasurer.WrapToWidth(ASpec.Labels[kept],
          ASpec.FontName, ASpec.FontSizeLogical, ASpec.FontWeight,
          AxisScaleF(ASpec.LabelWidthLogical, APPI));
      ASpec.Positions[kept] := AAxis.NormalizedCoord(ticks[q].Value);
      { on the raw rect, which is what the estimate lays out on; the final
        pass takes them again once the rect is final }
      ASpec.TickValues[kept] := ticks[q].Value;
      ASpec.LocalCoords[kept] := AAxis.DataToLocal(ticks[q].Value);
      { the first category, which the stride is aligned from nought against }
      if (kept = 0) and (AAxis.Scale is TTyOrdinalScale) then
        ASpec.OrdinalStart := Round(TTyOrdinalScale(AAxis.Scale).TickToOrdinal(
          ticks[q].Value));
      { upstream's proportion: the tick in the scale's own extent -- an
        ordinal's raw number, not band-adjusted and not inverted }
      if AAxis.Scale is TTyOrdinalScale then
        ASpec.Proportions[kept] := AAxis.Scale.Normalize(
          TTyOrdinalScale(AAxis.Scale).TickToOrdinal(ticks[q].Value))
      else
        ASpec.Proportions[kept] := AAxis.Scale.Normalize(ticks[q].Value);
      Inc(kept);
    end;
    SetLength(ASpec.Labels, kept);
    SetLength(ASpec.Positions, kept);
    SetLength(ASpec.TickValues, kept);
    SetLength(ASpec.LocalCoords, kept);
    SetLength(ASpec.Proportions, kept);
    if isTime then
    begin
      SetLength(ASpec.LabelNotNice, kept);
      SetLength(ASpec.LabelLevel, kept);
      SetLength(ASpec.LabelEmphasis, kept);
    end;
  end;

begin
  if (ABuild = nil) or (AMeasurer = nil) then Exit;
  vp := ABuild.Viewport;
  for g := 0 to ABuild.GridCount - 1 do
  begin
    gb := ABuild.Grid(g);
    gridNode := ObjOf(AOption.ComponentAt('grid', gb.ComponentIndex));
    containLabel := ContainLabelOn(gridNode);
    specs := nil;
    SetLength(specs, gb.XAxisCount + gb.YAxisCount);
    SetLength(furn, gb.XAxisCount + gb.YAxisCount);
    { WHICH FAMILY IS A NUMBER LINE, asked once per grid. This is the whole
      input to the `auto` rule, and it is asked of the FAMILY and not of a
      pair: upstream walks every cartesian in the grid and takes its
      opposite-dimension axis, whether or not the axis being resolved is in
      that cartesian. }
    xIsValue := False;
    for i := 0 to gb.XAxisCount - 1 do
      if gb.XAxis(i).AxisType in [atValue, atLog] then xIsValue := True;
    yIsValue := False;
    for i := 0 to gb.YAxisCount - 1 do
      if gb.YAxis(i).AxisType in [atValue, atLog] then yIsValue := True;

    { EVERY AXIS' FURNITURE FIRST: a spec asks which axis sits on whose zero
      (a top axis on the other's zero keeps its label rotation), and that
      reads every axis' onZero }
    t := 0;
    for i := 0 to gb.XAxisCount - 1 do
    begin
      ax := gb.XAxis(i);
      node := ObjOf(AOption.ComponentAt('xAxis', ax.ComponentIndex));
      furn[t] := TyAxisFurnitureOf(node, ax, yIsValue);
      Inc(t);
    end;
    for i := 0 to gb.YAxisCount - 1 do
    begin
      ax := gb.YAxis(i);
      node := ObjOf(AOption.ComponentAt('yAxis', ax.ComponentIndex));
      furn[t] := TyAxisFurnitureOf(node, ax, xIsValue);
      Inc(t);
    end;
    gb.FFurniture := furn;
    t := 0;
    for i := 0 to gb.XAxisCount - 1 do
    begin
      ax := gb.XAxis(i);
      node := ObjOf(AOption.ComponentAt('xAxis', ax.ComponentIndex));
      FillSpec(specs[t], ax, node, furn[t]);
      Inc(t);
    end;
    for i := 0 to gb.YAxisCount - 1 do
    begin
      ax := gb.YAxis(i);
      node := ObjOf(AOption.ComponentAt('yAxis', ax.ComponentIndex));
      FillSpec(specs[t], ax, node, furn[t]);
      Inc(t);
    end;

    { THE ESTIMATE'S FRAMES, on the raw rect: the extents are still the raw
      rect's, so the other family's zero is where upstream finds it then }
    for t := 0 to High(specs) do
    begin
      specs[t].NameFrame := gb.NameFrameFor(AxisAt(gb, t), specs[t], APPI);
      specs[t].HasNameFrame := True;
    end;

    { obcAll, explicitly. Our own default is obcAxisLabel while upstream's
      outerBoundsContain default is 'all', and taking the default here would
      make axis NAMES silently stop reserving room for themselves. }
    gb.FPlotXYWH := SolveGridRect(gb, gridNode, specs);
    gb.FPlotRect := TyRectOfXYWH(gb.FPlotXYWH);

    { WHAT THE ESTIMATE HID, CARRIED OVER. After a shrink upstream builds a
      category axis' labels again on the final rect, but lays a value, log or
      time axis' same labels out again -- and a label the estimate hid is the
      first to go this time, under the end rules and under hideOverlap
      alike. With nothing overflowed the estimate is the answer, which laying
      out again on the same rect reproduces. }
    if estimated and not noPx then
      for t := 0 to High(specs) do
        if specs[t].LabelKind <> lakCategory then
        begin
          est := TyLayoutAxisLabels(specs[t], gb.FOuterRect, AMeasurer, APPI);
          SetLength(specs[t].LabelSuggestIgnore, Length(est));
          for i := 0 to High(est) do
            specs[t].LabelSuggestIgnore[i] := not est[i].Shown;
        end;

    { THE FINAL PIXEL WRITE, BEFORE THE FINAL LABELS: upstream's resize
      writes the axes' extents from the shrunk rect and only then builds
      the axes that are drawn, reading every coordinate from them live.
      [Revised in batch 43: this came after the placements, which were then
      made from fractions taken on the raw rect and spread over the final
      one -- a y label up to eight units in the last place off along, and
      one missing the matrix' cos(pi/2) term across.] }
    for j := 0 to gb.CartesianCount - 1 do
    begin
      gb.CartesianByIndex(j).SetRectXYWH(gb.FPlotXYWH);
      { upstream's Grid.resize ends here too: the rect is final, the scales
        were final before it, and the matrix is made from both }
      gb.CartesianByIndex(j).CalcAffineTransform;
    end;
    { the frames and the labels' own coordinates, on the final axes -- the
      frame after the write, because an axis on the other's zero finds that
      zero on them }
    for t := 0 to High(specs) do
    begin
      specs[t].NameFrame := gb.NameFrameFor(AxisAt(gb, t), specs[t], APPI);
      specs[t].HasNameFrame := True;
      for i := 0 to High(specs[t].TickValues) do
      begin
        specs[t].LocalCoords[i] := AxisAt(gb, t).DataToLocal(specs[t].TickValues[i]);
        specs[t].Positions[i] := AxisAt(gb, t).NormalizedCoord(specs[t].TickValues[i]);
      end;
    end;

    { THE THINNING AND THE PLACEMENTS, DECIDED HERE. Both are derived by
      measuring every label, and the paint pass used to derive them itself on
      every frame -- ten thousand measurements per frame at 5,000 categories, to
      choose the twenty that actually get drawn. They belong to the layout for
      the same reason the spec does: the plot rect was shrunk to fit exactly
      these labels, so anything computed from them a second time is a second
      route to an answer that is already known.

      After TySolveGrid, because both need the FINAL plot rect. }
    for t := 0 to High(specs) do
    begin
      specs[t].LabelStep := TyAxisLabelStep(specs[t], gb.FPlotRect, AMeasurer, APPI);
      if specs[t].LabelStep < 1 then specs[t].LabelStep := 1;
      specs[t].Placements := TyLayoutAxisLabels(specs[t], gb.FPlotRect,
                                                AMeasurer, APPI);
    end;

    { Kept for the renderer. }
    gb.FSpecs := specs;

    { THE NAMES AS THEY ARE DRAWN: laid out again on the final rect, from the
      final frames above -- upstream's determine pass, with its own margin
      level }
    names := TyLayoutGridNames(gb.FSpecs, gb.FPlotRect, vp.Right - vp.Left,
      vp.Bottom - vp.Top, AMeasurer, APPI);
    for t := 0 to High(gb.FSpecs) do
      gb.FSpecs[t].NamePlacement := names[t];

    { AND THE FURNITURE, on the same final rect }
    for t := 0 to High(gb.FSpecs) do
      AxisMarks(gb, AxisAt(gb, t), gb.FSpecs[t], gb.FFurniture[t]);
  end;
end;

end.
