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
  end;


  { One grid: a plot rect, the axes that named it, and the coordinate systems
    over their cross product. }
  TTyGridBuild = class
  private
    FComponentIndex: Integer;
    FOuterRect: TTyRectF;
    FPlotRect: TTyRectF;
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
  end;

  { Everything one option tree produced. Owns the grids, the axes and, through
    the grids, the coordinate systems. }
  TTyChartBuild = class
  private
    FGrids: array of TTyGridBuild;
    FXAxes: TTyAxisArray;      // OWNED; indexed by global component index
    FYAxes: TTyAxisArray;      // OWNED
    FDiagnostics: TTyStringArray;
  public
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
  tyControls.StrConsts;

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
  FOuterRect := TyRectF(0, 0, 0, 0);
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
      a.Name := StrIn(nd, 'name', '');
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
    spec.Left := BoxValueIn(node, 'left', TyBoxPercent(GridDefaultLeft));
    spec.Top := BoxValueIn(node, 'top', TyBoxPx(GridDefaultTop));
    spec.Right := BoxValueIn(node, 'right', TyBoxPercent(GridDefaultRight));
    spec.Bottom := BoxValueIn(node, 'bottom', TyBoxPx(GridDefaultBottom));
    spec.Width := BoxValueIn(node, 'width', TyBoxAuto);
    spec.Height := BoxValueIn(node, 'height', TyBoxAuto);
    build.FGrids[i].FOuterRect := TySolveBox(spec, TyFixedContainer(AViewport));
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
        c.SetRect(build.FGrids[i].FOuterRect);
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

function TyAxisFurnitureOf(ANode: TJSONObject; AAxis: TTyAxis;
  AOtherIsValue: Boolean): TTyAxisFurniture;
var
  cat, tickAuto: Boolean;
  d: TJSONData;
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
  Result.OnZeroAxisIndex := -1;
  if ANode <> nil then
  begin
    d := ObjOf(ANode.Find('axisLine'));
    if d <> nil then
    begin
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

{ A number in its decimal form, locale-independently. Local rather than reusing
  the formatter unit's: that one lives behind Handlers, which pulls in Paint,
  and this needs three lines of it. }
function NumText(AValue: Double): string;
var fs: TFormatSettings;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit('');
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  Result := FormatFloat('0.######', AValue, fs);
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

function TyFillSeriesStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ADims: TTySeriesDimArray; AStore: TTyDataStore;
  const AKey: string): Integer;
var
  node: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  row: array of TTyDataValue;
  i, k, src, catDim, raw: Integer;
  item, v, cell: TJSONData;
  useIndex: Boolean;
  txt: string;
begin
  Result := 0;
  if (AOption = nil) or (AStore = nil) or (Length(ADims) = 0) then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if node = nil then Exit;
  { AKey IS NOT ALWAYS `data`: a graph's node list has a second name. }
  d := node.Find(AKey);
  if (d = nil) or (d.JSONType = jtNull) or not (d is TJSONArray) then Exit;
  arr := TJSONArray(d);

  catDim := FirstCategoryDim(ADims);
  useIndex := TySeriesUsesRowIndex(arr, ADims);
  SetLength(row, Length(ADims));

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

    if not (item is TJSONObject) then Continue;
    if OptionIdName(TJSONObject(item).Find('name'), txt) then AStore.SetName(raw, txt);
    if OptionIdName(TJSONObject(item).Find('id'), txt) then AStore.SetId(raw, txt);
    CollectOverrides(TJSONObject(item), AStore, raw, '', 0);
  end;
end;

function TyFillStoreFromSource(const ASource: TTyChartSource;
  const AEncode: TTySeriesEncode; const ADims: TTySeriesDimArray;
  AStore: TTyDataStore): Integer;
var
  row: array of TTyDataValue;
  i, k, n, col, raw: Integer;
  cell: TJSONData;
  nm: string;
begin
  Result := 0;
  if (AStore = nil) or (Length(ADims) = 0) then Exit;
  if not ASource.Valid then Exit;
  n := TySourceRowCount(ASource);
  SetLength(row, Length(ADims));

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



function CanProvideZero(AAxis: TTyAxis): Boolean;
var e: TTyRange;
begin
  Result := False;
  if (AAxis = nil) or (AAxis.Scale = nil) then Exit;
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
      if CanProvideZero(cand) then Result := cand;
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
    if not CanProvideZero(cand) then Continue;
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
  off := furn.OffsetLogical * APPI / 96;

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
  node: TJSONObject;

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
    ASpec.ShowTicks := AFurn.ShowTicks;
    ASpec.ForcedLabelStep := AFurn.LabelStep;
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
    { AND A TOP AXIS TURNS THE OTHER WAY. Upstream negates the rotation for
      `position: top` alone, so that `rotate: 45` slants the labels away from
      the plot on both edges instead of into it on one of them. }
    if AAxis.Side = asTop then
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
    if ANode <> nil then
    begin
      lbl := FindIn(ANode, 'axisLabel');
      if (lbl <> nil) and (lbl.JSONType = jtObject) then
      begin
        wd := FindIn(TJSONObject(lbl), 'width');
        if (wd <> nil) and (wd.JSONType = jtNumber) then
          ASpec.LabelWidthLogical := wd.AsFloat;
        ovf := LowerCase(StrIn(TJSONObject(lbl), 'overflow', ''));
        if ovf = 'truncate' then ASpec.LabelOverflow := loTruncate
        else if (ovf = 'break') or (ovf = 'breakall') then
          ASpec.LabelOverflow := loBreak;
      end;
    end;

    ticks := AAxis.Scale.GetTicks;
    isTime := AAxis.Scale is TTyTimeScale;
    SetLength(ASpec.Labels, Length(ticks));
    SetLength(ASpec.Positions, Length(ticks));
    if isTime then
    begin
      SetLength(ASpec.LabelHidden, Length(ticks));
      SetLength(ASpec.LabelEmphasis, Length(ticks));
      { A time axis is never thinned by index, and its coarse ticks are the
        ones that carry the weight. }
      ASpec.KeepEveryLabel := True;
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
        { THE TWO RAGGED ENDS KEEP THEIR TICKS AND LOSE THEIR TEXT. The extent
          of a time axis is the data's own, never rounded outwards, so its
          first and last ticks are wherever the data happens to start and
          stop; labelling those puts a `07:13` hard against the first round
          hour. }
        ASpec.LabelHidden[kept] := ticks[q].NotNice;
        { Every level above the finest is emphasised, which is what makes an
          axis read `12 13 14 Feb 2 3` rather than as six equal numbers. }
        ASpec.LabelEmphasis[kept] := ticks[q].TimeLevel >= 1;
      end
      else if AAxis.Scale is TTyOrdinalScale then
        ASpec.Labels[kept] := TTyOrdinalScale(AAxis.Scale).GetLabel(ticks[q].Value)
      else
        { NumText, not FloatToStr: the paint pass formats the same tick with a
          forced '.' separator, and FloatToStr follows the machine's locale --
          on a comma-decimal machine the width measured here is not the width of
          the string that gets drawn. }
        ASpec.Labels[kept] := NumText(ticks[q].Value);
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
      Inc(kept);
    end;
    SetLength(ASpec.Labels, kept);
    SetLength(ASpec.Positions, kept);
    if isTime then
    begin
      SetLength(ASpec.LabelHidden, kept);
      SetLength(ASpec.LabelEmphasis, kept);
    end;
  end;

begin
  if (ABuild = nil) or (AMeasurer = nil) then Exit;
  for g := 0 to ABuild.GridCount - 1 do
  begin
    gb := ABuild.Grid(g);
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

    t := 0;
    for i := 0 to gb.XAxisCount - 1 do
    begin
      ax := gb.XAxis(i);
      node := ObjOf(AOption.ComponentAt('xAxis', ax.ComponentIndex));
      furn[t] := TyAxisFurnitureOf(node, ax, yIsValue);
      FillSpec(specs[t], ax, node, furn[t]);
      Inc(t);
    end;
    for i := 0 to gb.YAxisCount - 1 do
    begin
      ax := gb.YAxis(i);
      node := ObjOf(AOption.ComponentAt('yAxis', ax.ComponentIndex));
      furn[t] := TyAxisFurnitureOf(node, ax, xIsValue);
      FillSpec(specs[t], ax, node, furn[t]);
      Inc(t);
    end;
    gb.FFurniture := furn;

    { obcAll, explicitly. Our own default is obcAxisLabel while upstream's
      outerBoundsContain default is 'all', and taking the default here would
      make axis NAMES silently stop reserving room for themselves. }
    gb.FPlotRect := TySolveGrid(gb.FOuterRect, specs, AMeasurer, APPI, obmAuto, obcAll);

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

    { The second and final pixel write. Everything downstream reads band widths
      and coordinates live, so nothing has to be invalidated. }
    for j := 0 to gb.CartesianCount - 1 do
      gb.CartesianByIndex(j).SetRect(gb.FPlotRect);
  end;
end;

end.
