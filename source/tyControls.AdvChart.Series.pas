unit tyControls.AdvChart.Series;
{$mode objfpc}{$H+}
{ Series types, and what each series is bound to.

  This is the unit that makes a chart able to MIX SERIES TYPES and give a series
  a SECONDARY AXIS -- and the second half of that is the half that goes wrong
  quietly. A secondary y axis that resolves but is never told which series feed
  it is drawn, is labelled, and shows the PRIMARY axis' numbers. So the
  axis-to-series inverse index ships here, in the same unit as the forward
  binding, rather than being left to whoever writes a renderer first.

  A SERIES TYPE IS DATA, NOT A HIERARCHY. What a type IS -- its default
  coordinate system, whether it is laid out against axes or into a box, what its
  columns are called -- is a record in a table. Only the thing that DRAWS is a
  class. Two reasons, and neither is style: FPC access-violates when a virtual
  class method is dispatched through a nil class reference, which is exactly the
  state twenty-one of the twenty-three types are in until someone writes their
  renderer; and a record table is something the option validator and the
  design-time editor can read, which a set of overridden methods is not.

  THE FACTS ARE HAND-WRITTEN, NOT READ FROM THE CATALOG. The generated catalog
  is documentation truth: it is wrong about six series' coordinate systems -- it
  has no node at all for radar's, and it says graph is laid out in a box when
  the source says it has a view. Rendering behaviour comes from the source.

  BINDING RESOLVES IN TWO STEPS: name the coordinate SYSTEM, then ask that
  system for its axes. Only cartesian and single-axis systems let a series name
  axes directly; polar has one index and you ask the polar system for its radius
  and angle. Doing it in one step happens to work for cartesian and has to be
  rewritten for everything else.

  AND THE REFS ARE GATED ON THE SYSTEM ACTUALLY NAMED. Read ungated, a plain
  cartesian line resolves polarIndex 0 -- the catalog's default is 0, so there
  is always one to find -- and silently widens a polar axis' range.

  PURE: SysUtils, Classes, Math, fpjson and the AdvChart units. No LCL. }
interface
uses SysUtils, Classes, Math, fpjson,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder;

type
  { How a series occupies the chart.

    scuData   laid out against a coordinate system's axes -- a bar, a line
    scuBox    given a rectangle and left to fill it -- a pie, a treemap
    scuNone   neither; it builds its own space, like a force-directed graph }
  TTySeriesUsage = (scuData, scuBox, scuNone);

  { What a series type is, as data. }
  TTySeriesTypeInfo = record
    Name: string;
    { The literal default from the source, or '' when the type declares none --
      which is NOT the same as 'none': an absent declaration falls back to being
      laid out as data, while 'none' means the series makes its own space. }
    DefaultCoordSys: string;
    Usage: TTySeriesUsage;
    { The systems the RENDERER actually branches on. Documentation truth is
      wider: line's docs allow a single axis, its renderer has no branch for
      one. An empty list means the renderer is coordinate-system agnostic -- it
      needs only dimensions and a point mapping, which is how scatter works. }
    RendersOn: TTyStringArray;
    { Declared column names, in order. Empty means "take them from the
      coordinate system", which is what line, bar and scatter do. }
    Dims: TTyStringArray;
    { 'Graph' or 'Tree' when a flat table is not enough. }
    Companion: string;
  end;

  { Where one series ended up. }
  TTySeriesBinding = record
    { The series' slot in the option's series array. Holes are preserved, so
      this is stable even when a neighbour failed to resolve. }
    SeriesIndex: Integer;
    SeriesType: string;
    { False when the type was missing or unknown, or the named system could not
      be found. A binding that did not resolve still carries its index. }
    Resolved: Boolean;
    { False for a pie or a treemap: resolved, laid out, and simply not on any
      axis. Separate from Resolved because "no axes" and "did not work" are
      different answers and a caller has to be able to tell them apart. }
    HasAxes: Boolean;
    CoordSysName: string;
    Usage: TTySeriesUsage;
    { nil unless the system is a cartesian. This is the coordinate system whose
      MASTER PAIR is the resolved pair, so a series on the second y axis maps
      through it and paint and hit test cannot disagree. }
    Cart: TTyCartesian2D;
    XAxis: TTyAxis;
    YAxis: TTyAxis;
    { The axis the series is laid out ALONG -- the categorical or temporal
      spine. Bars share their band along it, stacks accumulate across it. }
    BaseAxis: TTyAxis;
    { The other one, which carries the value. }
    ValueAxis: TTyAxis;
    { WHICH RADAR, or -1. The radar itself is not here: a binding is resolved
      in phase B, before the control has laid anything out, and a coordinate
      system that does not know its own centre yet is not worth carrying. The
      control keeps the objects and looks them up by this index.

      A radar series is Resolved with HasAxes FALSE, which reads oddly until
      you see what HasAxes is for: it means "on the cartesian pair", and every
      caller that tests it is asking whether there is an x and a y to map
      through. A radar has neither. }
    RadarIndex: Integer;
    { SWITCHED OFF BY A LEGEND. Set by the control after the stores are
      filled and before anything is counted; every solver downstream skips
      such a binding, so the axis extents, the stack groups and the bar
      widths are all taken from the survivors.

      A FLAG AND NOT A COMPACTION, which is upstream's shape too: ECharts
      rewrites `_seriesIndices` and never touches the series array, because
      the legend still has to see what it switched off -- a greyed item
      keeps its own icon and its own colour. Closing the gap here would
      also break the one contract this array has: the subscript IS
      `series[n]`.

      A PIE IS NEVER HIDDEN THIS WAY. Its legend names SLICES, not the
      series, so it is filtered one row at a time in the store instead. }
    Hidden: Boolean;
  end;
  TTySeriesBindingArray = array of TTySeriesBinding;

{ ---- the type registry ---- }
{ Registering the same name twice REPLACES, so a design-time reload does not
  accumulate stale entries. }
procedure TySeriesRegisterType(const AInfo: TTySeriesTypeInfo);
function TySeriesFindType(const AName: string; out AInfo: TTySeriesTypeInfo): Boolean;
function TySeriesTypeCount: Integer;
function TySeriesTypeNameAt(AIndex: Integer): string;
procedure TySeriesClearTypes;
{ The twenty-three types ECharts ships, as the SOURCE describes them. Called at
  unit start; exposed so a test can prove the table is what it claims. }
procedure TySeriesRegisterBuiltinTypes;

{ ---- binding ---- }
{ Resolve every series in the option. One entry per series slot, holes included,
  so an index into this array is the option's own series index. Diagnostics for
  anything that could not be honoured go onto ABuild. }
function TyBindSeries(AOption: TTyChartOption; ABuild: TTyChartBuild): TTySeriesBindingArray;

type
  { Which series feed which axis.

    TWO POPULATIONS, not one, and they are not each other's subsets in the
    direction you would guess. The FLAT one holds every (axis, series) pair and
    is what an axis' data range is computed from -- it has to see a line on the
    axis a bar is not based on, or that axis ends up with no range at all. The
    KEYED one is bucketed by (series type, coordinate system) and holds only the
    pairs where the axis is that series' BASE axis; it is what shares a band
    between bars.

    Ship only the flat one and a line sharing an x axis with a bar is counted as
    a bar: every bar comes out half as wide, on a chart that otherwise looks
    right. Ship only the keyed one and the value axes get no range. }
  TTyAxisSeriesIndex = class
  private
    type
      TEntry = record
        AxisUid: string;
        Key: string;          // '' = the flat population
        Series: TTyIntegerArray;
      end;
  private
    FEntries: array of TEntry;
    FCount: Integer;
    function IndexOf(const AAxisUid, AKey: string): Integer;
    procedure Add(const AAxisUid, AKey: string; ASeriesIndex: Integer);
  public
    procedure Clear;
    { Record that this series feeds this axis.

      Order matters inside: the flat population is written FIRST and
      unconditionally, then the keyed one only when the axis is the series'
      base. Swap them and the value axis stops reaching the range union while
      still looking associated. }
    procedure Associate(AAxis, ABaseAxis: TTyAxis; ASeriesIndex: Integer;
      const ASeriesType, ACoordSysName: string);
    { Every series on this axis, in ascending series index. }
    function SeriesOnAxis(AAxis: TTyAxis): TTyIntegerArray;
    { Only the series of one type-and-system whose BASE axis this is. }
    function SeriesOnAxisOfKey(AAxis: TTyAxis; const AKey: string): TTyIntegerArray;
    function CountOnAxisOfKey(AAxis: TTyAxis; const AKey: string): Integer;
  end;

{ The bucket key. Two segments, not three: whether the axis is the series' base
  is an admission TEST rather than part of the key, so one axis has one bucket
  per type-and-system. Putting it in the key gives an axis two buckets and the
  bar layouter reads the wrong one. }
{ Whether this type's LEGEND entries are its ROWS rather than the series.

  It is a real distinction and not a pie special case: upstream registers a
  `dataFilter` processor for exactly these types, and everything follows from
  it -- what the legend offers, which colour a swatch takes, and whether a
  legend click hides a series or one row of one.

  A LIST AND NOT A DERIVATION. `colorBy: 'data'` is close but not the same
  question: a series can colour by datum and still be one legend entry, and
  the day one does, a derived test would quietly change what the legend
  says. }
function TySeriesLegendByDatum(const AType: string): Boolean;

function TySeriesStatKey(const ASeriesType, ACoordSysName: string): string;

{ Build the index over a whole set of bindings. }
procedure TyIndexSeries(const ABindings: TTySeriesBindingArray;
  AIndex: TTyAxisSeriesIndex);

{ ---- phase B: axis ranges ---- }
{ Give every value axis the range its bound series actually need.

  AStacks says which series plot an accumulated total rather than their own
  value; pass an empty array when nothing stacks.

  Without this a value axis keeps whatever its scale was constructed with and
  every datum is drawn by extrapolating off the end of it -- nothing raises, the
  chart simply draws in the wrong place, hundreds of pixels outside the plot.

  A category axis is untouched: its range is its category count and comes from
  the axis, never from the data. }
procedure TyApplyAxisExtents(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex);

implementation

uses
  { Only for the diagnostic resourcestrings; kept out of the interface uses so
    the dependency stays one-way and this unit's public face still names only
    the AdvChart layer. }
  tyControls.StrConsts;

const
  StatDelim = '|&';

var
  GTypes: array of TTySeriesTypeInfo;

{ ==================== the type registry ==================== }

function FindTypeSlot(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GTypes) do
    if GTypes[i].Name = AName then Exit(i);
  Result := -1;
end;

procedure TySeriesRegisterType(const AInfo: TTySeriesTypeInfo);
var i: Integer;
begin
  if AInfo.Name = '' then Exit;
  i := FindTypeSlot(AInfo.Name);
  if i < 0 then
  begin
    i := Length(GTypes);
    SetLength(GTypes, i + 1);
  end;
  GTypes[i] := AInfo;
end;

function TySeriesFindType(const AName: string; out AInfo: TTySeriesTypeInfo): Boolean;
var i: Integer;
begin
  AInfo := Default(TTySeriesTypeInfo);
  i := FindTypeSlot(AName);
  Result := i >= 0;
  if Result then AInfo := GTypes[i];
end;

function TySeriesTypeCount: Integer;
begin
  Result := Length(GTypes);
end;

function TySeriesTypeNameAt(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(GTypes)) then Exit('');
  Result := GTypes[AIndex].Name;
end;

procedure TySeriesClearTypes;
begin
  GTypes := nil;
end;

procedure Reg(const AName, ADefaultCoordSys: string; AUsage: TTySeriesUsage;
  const ARendersOn, ADims: array of string; const ACompanion: string);
var
  info: TTySeriesTypeInfo;
  i: Integer;
begin
  info := Default(TTySeriesTypeInfo);
  info.Name := AName;
  info.DefaultCoordSys := ADefaultCoordSys;
  info.Usage := AUsage;
  SetLength(info.RendersOn, Length(ARendersOn));
  for i := 0 to High(ARendersOn) do info.RendersOn[i] := ARendersOn[i];
  SetLength(info.Dims, Length(ADims));
  for i := 0 to High(ADims) do info.Dims[i] := ADims[i];
  info.Companion := ACompanion;
  TySeriesRegisterType(info);
end;

procedure TySeriesRegisterBuiltinTypes;
begin
  { Every row read out of the series and view sources, not out of the docs. The
    empty RendersOn lists are not omissions: those renderers genuinely have no
    coordinate-system branch and work against anything that can map a point. }
  Reg('line', 'cartesian2d', scuData, ['cartesian2d', 'polar'], [], '');
  Reg('bar', 'cartesian2d', scuData, ['cartesian2d', 'polar'], [], '');
  Reg('pictorialBar', 'cartesian2d', scuData, ['cartesian2d'], [], '');
  Reg('scatter', 'cartesian2d', scuData, [], [], '');
  Reg('effectScatter', 'cartesian2d', scuData, [], [], '');
  Reg('heatmap', 'cartesian2d', scuData,
      ['cartesian2d', 'calendar', 'matrix', 'geo'], [], '');
  Reg('boxplot', 'cartesian2d', scuData, ['cartesian2d'],
      ['base', 'min', 'Q1', 'median', 'Q3', 'max'], '');
  Reg('candlestick', 'cartesian2d', scuData, ['cartesian2d'],
      ['base', 'open', 'close', 'lowest', 'highest'], '');
  Reg('lines', 'geo', scuData, [], ['value'], '');
  Reg('map', 'geo', scuData, ['geo'], ['value'], '');
  { Absent rather than 'none': the source declares no coordinateSystem at all
    and lays these out in a box. }
  Reg('pie', '', scuBox, [], ['value'], '');
  Reg('funnel', '', scuBox, [], ['value'], '');
  Reg('gauge', '', scuBox, [], ['value'], '');
  Reg('radar', 'radar', scuData, ['radar'], [], '');
  Reg('parallel', 'parallel', scuData, ['parallel'], [], '');
  Reg('themeRiver', 'singleAxis', scuData, ['singleAxis'],
      ['time', 'value', 'name'], '');
  { The catalog says 'none' here and the source says 'view'. }
  Reg('graph', 'view', scuData,
      ['view', 'cartesian2d', 'polar', 'geo', 'calendar', 'matrix'], ['value'], 'Graph');
  Reg('sankey', '', scuBox, ['view'], ['value'], 'Graph');
  Reg('chord', 'none', scuNone, [], ['value'], 'Graph');
  Reg('tree', '', scuBox, ['view'], [], 'Tree');
  Reg('treemap', '', scuBox, [], [], 'Tree');
  Reg('sunburst', '', scuNone, [], [], 'Tree');
  Reg('custom', 'cartesian2d', scuData,
      ['cartesian2d', 'geo', 'singleAxis', 'polar', 'calendar', 'matrix'], [], '');
end;

{ ==================== binding ==================== }

function ObjAt(AOption: TTyChartOption; const AMainType: string;
  AIndex: Integer): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  d := AOption.ComponentAt(AMainType, AIndex);
  if (d <> nil) and (d is TJSONObject) then Result := TJSONObject(d);
end;

function StrOf(ANode: TJSONObject; const AKey, ADefault: string): string;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  { Non-scalar where a string was expected RAISES out of AsString. See the note
    on Builder's StrIn: `series: [{ type: {} }]` is legal JSON and a normal
    mid-edit state. }
  if (d = nil) or (d.JSONType in [jtNull, jtArray, jtObject]) then Exit;
  Result := d.AsString;
end;

{ Every axis id of a family, positionally, so the shared reference rule can
  match one. }
function AxisIds(ABuild: TTyChartBuild; const AMainType: string): TTyStringArray;
var i: Integer;
begin
  Result := nil;
  SetLength(Result, ABuild.AxisCount(AMainType));
  for i := 0 to High(Result) do
    Result[i] := ABuild.Axis(AMainType, i).Id;
end;

function TyBindSeries(AOption: TTyChartOption; ABuild: TTyChartBuild): TTySeriesBindingArray;
var
  i, n, xi, yi: Integer;
  node: TJSONObject;
  b: TTySeriesBinding;
  info: TTySeriesTypeInfo;
  sys: string;
begin
  Result := nil;
  if (AOption = nil) or (ABuild = nil) then Exit;
  n := AOption.ComponentCount('series');
  SetLength(Result, n);

  for i := 0 to n - 1 do
  begin
    b := Default(TTySeriesBinding);
    b.SeriesIndex := i;
    Result[i] := b;

    node := ObjAt(AOption, 'series', i);
    b.SeriesType := StrOf(node, 'type', '');
    if b.SeriesType = '' then
    begin
      { Upstream drops such a series with a log and leaves a hole in its
        component array. Ours keeps the slot -- a hole here would renumber every
        later series and silently move whatever a callback or a hit test was
        pointing at -- and says why. }
      ABuild.Note(Format(rsTyChartSeriesNoType, [i]));
      Result[i] := b;
      Continue;
    end;
    if not TySeriesFindType(b.SeriesType, info) then
    begin
      ABuild.Note(Format(rsTyChartSeriesBadType, [i, b.SeriesType]));
      Result[i] := b;
      Continue;
    end;

    { Step one: which coordinate system. An explicit coordinateSystem wins;
      otherwise the type's own default, which for a pie or a treemap is nothing
      at all. }
    sys := StrOf(node, 'coordinateSystem', info.DefaultCoordSys);
    b.CoordSysName := sys;
    b.Usage := info.Usage;
    b.RadarIndex := -1;

    if (sys = '') or (sys = 'none') then
    begin
      { Resolved, and deliberately on no axis. A pie is laid out into a
        rectangle; asking which axis it is on has no answer, and treating that
        as a failure would make every pie a permanent error. }
      b.Resolved := True;
      b.HasAxes := False;
      Result[i] := b;
      Continue;
    end;

    if sys = 'radar' then
    begin
      { THE SECOND SYSTEM, and the step-one/step-two shape finally earns its
        keep: name the system, then ask it for its axes. A radar's axes are
        the indicator spokes and they belong to the radar, not to a component
        list of their own -- so there is nothing to look up here beyond which
        radar. }
      b.RadarIndex := TyResolveComponentRef(node, 'radarIndex', 'radarId',
        AOption.ComponentCount('radar'), nil);
      if b.RadarIndex < 0 then
      begin
        ABuild.Note(Format(rsTyChartSeriesCoordSys, [i, sys]));
        Result[i] := b;
        Continue;
      end;
      b.Resolved := True;
      b.HasAxes := False;
      Result[i] := b;
      Continue;
    end;

    if sys <> 'cartesian2d' then
    begin
      { The two-step shape is here; only cartesian and radar have a system to
        ask yet. A series naming polar resolves to nothing rather than
        silently falling back to the cartesian it did not ask for. }
      ABuild.Note(Format(rsTyChartSeriesCoordSys, [i, sys]));
      Result[i] := b;
      Continue;
    end;

    { Step two: ask the system for its axes. For a cartesian the system IS the
      pair, so naming the pair and finding the system are one lookup -- which is
      why a series on the second y axis maps through a coordinate system whose
      master pair is its own, and paint and hit test cannot drift apart.

      ONLY the cartesian reference keys are read. A stray polarIndex on this
      series is not consulted, and the catalog's default for it is 0, so an
      ungated read would find a polar axis every single time. }
    xi := TyResolveComponentRef(node, 'xAxisIndex', 'xAxisId',
      ABuild.AxisCount('xAxis'), AxisIds(ABuild, 'xAxis'));
    yi := TyResolveComponentRef(node, 'yAxisIndex', 'yAxisId',
      ABuild.AxisCount('yAxis'), AxisIds(ABuild, 'yAxis'));
    if (xi < 0) or (yi < 0) then
    begin
      ABuild.Note(Format(rsTyChartSeriesNoAxis, [i]));
      Result[i] := b;
      Continue;
    end;
    b.Cart := ABuild.CartesianAt(xi, yi);
    if b.Cart = nil then
    begin
      ABuild.Note(Format(rsTyChartSeriesAxesSplit, [i, xi, yi]));
      Result[i] := b;
      Continue;
    end;
    b.XAxis := ABuild.Axis('xAxis', xi);
    b.YAxis := ABuild.Axis('yAxis', yi);
    b.BaseAxis := b.Cart.GetBaseAxis;
    b.ValueAxis := b.Cart.GetOtherAxis(b.BaseAxis);
    b.Resolved := True;
    b.HasAxes := True;
    Result[i] := b;
  end;
end;

{ ==================== the inverse index ==================== }

function TySeriesLegendByDatum(const AType: string): Boolean;
const
  cByDatum: array[0..2] of string = ('pie', 'funnel', 'radar');
var i: Integer;
begin
  for i := 0 to High(cByDatum) do
    if cByDatum[i] = AType then Exit(True);
  Result := False;
end;

function TySeriesStatKey(const ASeriesType, ACoordSysName: string): string;
begin
  Result := ASeriesType + StatDelim + ACoordSysName;
end;

function TTyAxisSeriesIndex.IndexOf(const AAxisUid, AKey: string): Integer;
var i: Integer;
begin
  for i := 0 to FCount - 1 do
    if (FEntries[i].AxisUid = AAxisUid) and (FEntries[i].Key = AKey) then Exit(i);
  Result := -1;
end;

procedure TTyAxisSeriesIndex.Add(const AAxisUid, AKey: string; ASeriesIndex: Integer);
var i, n: Integer;
begin
  i := IndexOf(AAxisUid, AKey);
  if i < 0 then
  begin
    if FCount = Length(FEntries) then SetLength(FEntries, 8 + FCount * 2);
    i := FCount;
    Inc(FCount);
    FEntries[i].AxisUid := AAxisUid;
    FEntries[i].Key := AKey;
    FEntries[i].Series := nil;
  end;
  n := Length(FEntries[i].Series);
  { Ascending by construction, because the caller walks the series in order.
    The bar layouter depends on it: the first series declared supplies the
    default gap and the last supplies the explicit one. }
  SetLength(FEntries[i].Series, n + 1);
  FEntries[i].Series[n] := ASeriesIndex;
end;

procedure TTyAxisSeriesIndex.Clear;
begin
  FEntries := nil;
  FCount := 0;
end;

procedure TTyAxisSeriesIndex.Associate(AAxis, ABaseAxis: TTyAxis;
  ASeriesIndex: Integer; const ASeriesType, ACoordSysName: string);
begin
  if AAxis = nil then Exit;
  { Flat first and unconditionally. The keyed population is a filtered view of
    the same pairs, and writing it first would let an early exit skip the flat
    one -- which is how a value axis ends up associated for statistics and
    invisible to the range union. }
  Add(AAxis.Uid, '', ASeriesIndex);
  if AAxis = ABaseAxis then
    Add(AAxis.Uid, TySeriesStatKey(ASeriesType, ACoordSysName), ASeriesIndex);
end;

function TTyAxisSeriesIndex.SeriesOnAxis(AAxis: TTyAxis): TTyIntegerArray;
var i: Integer;
begin
  Result := nil;
  if AAxis = nil then Exit;
  i := IndexOf(AAxis.Uid, '');
  if i >= 0 then Result := Copy(FEntries[i].Series);
end;

function TTyAxisSeriesIndex.SeriesOnAxisOfKey(AAxis: TTyAxis;
  const AKey: string): TTyIntegerArray;
var i: Integer;
begin
  Result := nil;
  if AAxis = nil then Exit;
  i := IndexOf(AAxis.Uid, AKey);
  if i >= 0 then Result := Copy(FEntries[i].Series);
end;

function TTyAxisSeriesIndex.CountOnAxisOfKey(AAxis: TTyAxis;
  const AKey: string): Integer;
begin
  Result := Length(SeriesOnAxisOfKey(AAxis, AKey));
end;

procedure TyIndexSeries(const ABindings: TTySeriesBindingArray;
  AIndex: TTyAxisSeriesIndex);
var i: Integer;
begin
  if AIndex = nil then Exit;
  AIndex.Clear;
  for i := 0 to High(ABindings) do
  begin
    { A hole is inert in both populations, and it needs no guard here to be:
      its axes are nil and Associate refuses a nil axis. Mutation testing
      removed the guard that used to be here and nothing went red, which is the
      only way a safeguard that is really a restatement gets found.

      A HIDDEN SERIES IS DIFFERENT and does need one: its axes are perfectly
      good. Leaving it out of the index HERE is what keeps it out of the axis
      extents and out of the bar-width solve, because both of those take
      their populations from the index and from nowhere else. }
    if ABindings[i].Hidden then Continue;
    AIndex.Associate(ABindings[i].XAxis, ABindings[i].BaseAxis, i,
      ABindings[i].SeriesType, ABindings[i].CoordSysName);
    AIndex.Associate(ABindings[i].YAxis, ABindings[i].BaseAxis, i,
      ABindings[i].SeriesType, ABindings[i].CoordSysName);
  end;
end;

{ ==================== phase B: axis ranges ==================== }

{ Which column of a series' store feeds this axis. The store's columns are the
  coordinate dimensions in order, so the axis' own dim names it. }
function ColumnsForAxis(AStore: TTyDataStore; AAxis: TTyAxis): TTyIntegerArray;
begin
  Result := nil;
  if (AStore = nil) or (AAxis = nil) then Exit;
  { PLURAL, because a candlestick puts four columns on its value axis and a
    boxplot five. A store that mapped nothing answers with the single column
    of the axis' own name, which is every other series there is. }
  Result := AStore.DimsOfCoord(AAxis.Dim);
end;

{ One end of a value axis' boundaryGap: a number is an absolute amount, a string
  ending in '%' is that share of the data's own span. NaN for anything else, so a
  malformed entry pads nothing rather than pushing the axis to infinity. The '.'
  is forced, because a comma-decimal machine would otherwise read '10.5%' as
  nothing at all. }
function GapAmount(AData: TJSONData; ASpan: Double): Double;
var
  txt: string;
  pct: Double;
  fs: TFormatSettings;
begin
  Result := NaN;
  if AData = nil then Exit;
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  if AData.JSONType <> jtString then Exit;
  txt := Trim(AData.AsString);
  if (txt = '') or (txt[Length(txt)] <> '%') then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if not TryStrToFloat(Copy(txt, 1, Length(txt) - 1), pct, fs) then Exit;
  Result := ASpan * pct / 100;
end;

{ One end of an axis' range as the option wrote it: a number everywhere, and
  on a TIME axis a date string as well -- `min: '2024-01-01'` is how everybody
  writes that bound. False when the option said nothing, which leaves the
  data-derived end alone. }
function AxisBound(AData: TJSONData; AAxis: TTyAxis; var AValue: Double): Boolean;
var ms: Double;
begin
  Result := False;
  if AData = nil then Exit;
  if AData.JSONType = jtNumber then
  begin
    AValue := AData.AsFloat;
    Exit(True);
  end;
  if (AAxis <> nil) and (AAxis.AxisType = atTime)
    and (AData.JSONType = jtString) and TyParseDateMs(AData.AsString, ms) then
  begin
    AValue := ms;
    Exit(True);
  end;
end;

procedure TyApplyAxisExtents(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex);
var
  g, a: Integer;
  ax: TTyAxis;

  procedure DoAxis(AAxis: TTyAxis; const AMainType: string);
  var
    k, c, si, split: Integer;
    cols: TTyIntegerArray;
    node: TJSONObject;
    d: TJSONData;
    fixLo, fixHi: Boolean;
    ivl: Double;
    minor: Integer;
    minorSplit: Integer;
    wantMinor: Boolean;
    sub2: TJSONData;
    feeders: TTyIntegerArray;
    lo, hi, dlo, dhi, minIvl, maxIvl, gapLo, gapHi: Double;
    any, scaleOpt: Boolean;
    filter: TTyExtentFilter;
  begin
    if AAxis = nil then Exit;
    { A category axis' range is its category COUNT -- read off the axis, never
      computed from the values, so a name the data never mentions still gets a
      band and a bar chart does not shuffle when a value goes missing.

      But the count has to be read AFTER the rows are in. An axis with no
      `data` of its own collects its categories while the store parses, and
      until this ran the extent was the one fixed during construction, when the
      list was empty: one band across the whole plot with every point stacked
      on it, and Contain(2) answering False for a category the store had
      interned. Re-deriving is not "from the data" -- it is the same one place
      the extent has always come from, asked once more now the list is full. }
    if AAxis.AxisType = atCategory then
    begin
      if AAxis.Scale is TTyOrdinalScale then
        TTyOrdinalScale(AAxis.Scale).SetExtentFromCategories;
      Exit;
    end;

    node := ObjAt(AOption, AMainType, AAxis.ComponentIndex);
    if AAxis.AxisType = atLog then filter := defPositive else filter := defNone;

    any := False;
    lo := Infinity;
    hi := NegInfinity;
    feeders := AIndex.SeriesOnAxis(AAxis);
    for k := 0 to High(feeders) do
    begin
      si := feeders[k];
      if (si < 0) or (si > High(AStores)) then Continue;
      cols := ColumnsForAxis(AStores[si], AAxis);
      { A STACKED SERIES CONTRIBUTES ITS TOTAL, not its own value. Upstream
        gets this for free -- the stack-result dimension is registered under
        the VALUE coord dim, so anything unioning that coord dim picks it up,
        while the stacked-over dimension is deliberately given its own coord
        dim so it stays OUT of the extent. Here the columns are found by axis
        dimension name, which one column can only have one of, so the swap is
        made explicitly.

        Without it the axis is sized from the largest single value while the
        chart draws the sum of them, and every stack taller than its biggest
        member runs off the top of the plot. Nothing raises. }
      if (si <= High(AStacks)) and AStacks[si].Stacked
        and (AStacks[si].ResultCol >= 0) and (AAxis = ABindings[si].ValueAxis) then
      begin
        SetLength(cols, 1);
        cols[0] := AStacks[si].ResultCol;
      end;
      for c := 0 to High(cols) do
      begin
        if cols[c] < 0 then Continue;
        if not AStores[si].DataExtent(cols[c], dlo, dhi, filter) then Continue;
        if dlo < lo then lo := dlo;
        if dhi > hi then hi := dhi;
        any := True;
      end;
    end;
    { NOT A RETURN. Everything below is the AUTHOR's instruction --
      scale/min/max/splitNumber/interval/minorTick -- and returning here
      skipped all six on precisely the axis with no data to fall back on:
      `yAxis: { min: 0, max: 100 }` beside an empty series kept whatever extent
      construction happened to give it.

      Only the data-derived ends depend on `any`. With no data they are 0..1,
      which is what an axis showing nothing should span, and `min`/`max` below
      overwrite them when the author said otherwise. }
    if not any then
      if AAxis.AxisType = atTime then
      begin
        { A TIME AXIS WITH NOTHING ON IT SHOWS TODAY, which is upstream's
          answer and the only one an author reads as empty rather than as
          broken: 0..1 on a time axis is the first second of 1970, and a
          chart that lost its data should not look like a chart about the
          Apollo programme. }
        hi := TyDateTimeToMs(Date, False);
        lo := hi - 86400000;
      end
      else
      begin
        lo := 0;
        hi := 1;
      end;

    { An axis includes zero unless it was told to fit its data. That is why a
      bar chart's baseline is the axis line rather than a floating number, and
      it applies to every value axis rather than only to ones with bars on
      them. A log axis is exempt: zero has no logarithm. }
    scaleOpt := False;
    if node <> nil then
    begin
      d := node.Find('scale');
      if (d <> nil) and (d.JSONType = jtBoolean) then scaleOpt := d.AsBoolean;
    end;
    { A TIME AXIS IS EXEMT TOO, and far more visibly than a log one: zero on a
      time axis is the first instant of 1970, so a chart of last week would
      span fifty-six years and draw its seven points in the last pixel. }
    if (not scaleOpt) and not (AAxis.AxisType in [atLog, atTime]) then
    begin
      if lo > 0 then lo := 0;
      if hi < 0 then hi := 0;
    end;

    { WHAT THE AUTHOR ASKED FOR BEATS WHAT THE DATA SUGGESTS. `min` and `max`
      pin an end; a pinned end must survive Niceify, which is exactly what
      FixMin and FixMax are for -- they have been on the scale since it was
      written and nothing ever set them, so four of the most-used axis options
      in ECharts did nothing at all. }
    fixLo := False;
    fixHi := False;
    { SIX ON A TIME AXIS, five everywhere else -- upstream's own two defaults.
      A date is a wider label than a number and six of them is what fits. }
    if AAxis.AxisType = atTime then split := 6 else split := 5;
    ivl := 0;
    minIvl := 0;
    maxIvl := 0;
    minor := 0;
    if node <> nil then
    begin
      { ON A TIME AXIS THE BOUND IS USUALLY A DATE STRING. `min: '2024-01-01'`
        is how everybody writes it, and reading numbers only meant the
        commonest form of the two most-used axis options silently did nothing
        on the one axis type that needs them most. }
      d := node.Find('min');
      if AxisBound(d, AAxis, lo) then fixLo := True;
      d := node.Find('max');
      if AxisBound(d, AAxis, hi) then fixHi := True;
      { A VALUE AXIS' boundaryGap IS A PAIR, not the boolean a category axis
        takes -- `['10%', '10%']` or a pair of absolute amounts -- and it pads
        the extent before it is nicied. Read here rather than in the builder
        because it acts on the extent, and the builder has none yet. }
      d := node.Find('boundaryGap');
      if (d <> nil) and (d.JSONType = jtArray) and (TJSONArray(d).Count = 2) then
      begin
        gapLo := GapAmount(TJSONArray(d).Items[0], hi - lo);
        gapHi := GapAmount(TJSONArray(d).Items[1], hi - lo);
        if not IsNan(gapLo) then lo := lo - gapLo;
        if not IsNan(gapHi) then hi := hi + gapHi;
      end;

      d := node.Find('splitNumber');
      if (d <> nil) and (d.JSONType = jtNumber) then
      begin
        split := TyTruncOpt(d.AsFloat, split);
        if split < 1 then split := 1;
      end;
      d := node.Find('interval');
      if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat > 0) then
        ivl := d.AsFloat;
      { minorTick: { splitNumber: n }. Off unless asked for -- an axis that
        grows a second set of lines just by being drawn is not what anybody
        wrote. Upstream's default split is 5. }
      d := node.Find('minInterval');
      if (d <> nil) and (d.JSONType = jtNumber) then minIvl := d.AsFloat;
      d := node.Find('maxInterval');
      if (d <> nil) and (d.JSONType = jtNumber) then maxIvl := d.AsFloat;

      { THE SPLIT NUMBER IS NOT `minorTick.show`. Upstream's
        getMinorTicksCoords reads `minorTick.splitNumber` and nothing else --
        the two SHOW questions, one for the marks and one for the grid, are
        asked later and separately, by the axis furniture.

        Tying the coordinates to `minorTick.show` had two consequences. The
        visible one: `minorSplitLine: { show: true }` on its own drew
        nothing, because there were no minor ticks to draw it at. The other
        was invisible and worse -- it made both furniture gates unobservable,
        since a minor tick could not exist unless the same option that
        created it had also asked to draw it. Mutating either gate away
        changed no pixel anywhere, which is how this was found.

        Still not computed unless SOMEBODY asked, though: upstream builds the
        subdivisions of every value axis on every frame and this does not
        need to. Either of the two options counts as asking. }
      minorSplit := 5;
      wantMinor := False;
      d := node.Find('minorTick');
      if (d <> nil) and (d.JSONType = jtObject) then
      begin
        sub2 := TJSONObject(d).Find('splitNumber');
        if (sub2 <> nil) and (sub2.JSONType = jtNumber) then
          minorSplit := TyTruncOpt(sub2.AsFloat, minorSplit);
        sub2 := TJSONObject(d).Find('show');
        wantMinor := (sub2 <> nil) and (sub2.JSONType = jtBoolean)
                     and sub2.AsBoolean;
      end;
      d := node.Find('minorSplitLine');
      if (d <> nil) and (d.JSONType = jtObject) then
      begin
        sub2 := TJSONObject(d).Find('show');
        if (sub2 <> nil) and (sub2.JSONType = jtBoolean) and sub2.AsBoolean
          then wantMinor := True;
      end;
      { Upstream's own guard on the number, verbatim: out of (0, 100) and it
        goes back to five rather than subdividing an axis into nothing or
        into a thousand. }
      if (minorSplit <= 0) or (minorSplit >= 100) then minorSplit := 5;
      if wantMinor then minor := minorSplit;
    end;

    if lo > hi then Exit;
    AAxis.Scale.SetExtent(TyRange(lo, hi));
    if AAxis.Scale is TTyIntervalScale then
    begin
      TTyIntervalScale(AAxis.Scale).FixMin := fixLo;
      TTyIntervalScale(AAxis.Scale).FixMax := fixHi;
      { BEFORE Niceify, because they bound the step it is about to choose. }
      TTyIntervalScale(AAxis.Scale).MinInterval := minIvl;
      TTyIntervalScale(AAxis.Scale).MaxInterval := maxIvl;
      { An explicit `interval` is a statement about the STEP, so it is handed
        to the tick generator AS the step -- one generator, one set of rules,
        told the answer rather than asked to infer it.

        Deriving a split number from it and letting Niceify re-round was the
        first shape of this, and it lost every step NiceNum does not already
        like: interval:30 on 0..120 came out 50, interval:3 on 0..12 came out
        5. The split number is still computed, because it is what the minor
        ticks and the fallback path need. }
      if ivl > 0 then
      begin
        { The same hazard one indirection along: `max: 1e19` with
          `interval: 1` asks how many whole intervals fit and the answer
          does not fit in an Int64. The split only feeds a divisor, and an
          interval too small to draw is caught in the tick generator. }
        split := TyTruncOpt((hi - lo) / ivl, 1, 1, High(Integer));
        if split < 1 then split := 1;
      end;
      { NOT NICIED WHEN IT IS A CALENDAR. Niceify opens the extent out to
        round numbers before picking a step, and the round number nearest a
        week in March 2024 is somewhere in 1973. A time scale is handed the
        tick count instead and snaps to the calendar itself. }
      if AAxis.Scale is TTyTimeScale then
        TTyTimeScale(AAxis.Scale).SplitNumber := split
      else
        TTyIntervalScale(AAxis.Scale).Niceify(split, ivl);
      { AFTER Niceify: it is the major interval that gets subdivided, and
        Niceify is what decides the major interval. }
      TTyIntervalScale(AAxis.Scale).MinorSplitNumber := minor;
    end;
  end;

begin
  if (ABuild = nil) or (AIndex = nil) then Exit;
  for g := 0 to ABuild.GridCount - 1 do
  begin
    for a := 0 to ABuild.Grid(g).XAxisCount - 1 do
    begin
      ax := ABuild.Grid(g).XAxis(a);
      DoAxis(ax, 'xAxis');
    end;
    for a := 0 to ABuild.Grid(g).YAxisCount - 1 do
    begin
      ax := ABuild.Grid(g).YAxis(a);
      DoAxis(ax, 'yAxis');
    end;
  end;
end;

initialization
  TySeriesRegisterBuiltinTypes;

finalization
  TySeriesClearTypes;

end.
