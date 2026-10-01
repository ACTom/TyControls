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

const
  { A series on a calendar: the system's name, and the two dimensions it
    gives a series -- Calendar.ts `dimensions = ['time', 'value']`. }
  TyCalendarSysName = 'calendar';
  TyCalendarTimeDim = 'time';
  TyCalendarValueDim = 'value';

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
    { WHICH CALENDAR, or -1 -- an index for the reason RadarIndex is one: the
      calendar is laid out by the control, after binding. Resolved with
      HasAxes False, like a radar. [Batch 70] }
    CalendarIndex: Integer;
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

type
  { One axis' extent before any nicing -- upstream's scaleRawExtentInfo for a
    number or a time axis, in its order: the data widened by dataMin/dataMax,
    min and max (which pin), boundaryGap on the ends nobody pinned, zero on a
    plain value axis, the ends turned round when they came backwards,
    startValue, and on a log axis no end at or under zero. Lo and Hi are
    not-a-number where nothing gave them a value; Blank says so. FixLo/FixHi are the pins the nice step must keep. }
  TTyAxisRawExtent = record
    Lo, Hi: Double;
    FixLo, FixHi: Boolean;
    ToggleInverse: Boolean;
    Blank: Boolean;
    { THE VALUE A BAR STANDS ON: startValue as written, or -- where a bar asked
      for one and none was written -- 1 on a log axis and 0 elsewhere. Kept
      as parsed, NOT sanitized with the extent: a log start of 0 stays 0, and
      no bar can stand on it. HasStartValue False, the zero value, is an axis
      with no start at all. }
    HasStartValue: Boolean;
    StartValue: Double;
    { A PLAIN VALUE AXIS INCLUDES ZERO unless `scale` says otherwise -- the
      rule that gave Lo and Hi their zero, which alignment asks again. }
    Incl0: Boolean;
  end;

{ ADataLo/ADataHi are the series' own extent, +Infinity/-Infinity when there
  is none. ARequireStartValue is a bar's: its value axis wants its base in
  view. }
function TyAxisRawExtent(ANode: TJSONObject; AAxis: TTyAxis;
  ADataLo, ADataHi: Double; ARequireStartValue: Boolean): TTyAxisRawExtent;

const
  { The two answers upstream's liPosMinGap gives besides a gap: nothing to
    measure at all, and exactly one distinct value. Both negative, so no
    caller can mistake either for a gap. }
  cTyMinGapNone = -1.0;
  cTyMinGapSingle = -2.0;

{ UPSTREAM'S liPosMinGap over a plain list: the smallest strictly positive
  difference between two of the values once sorted. Not-a-number and the
  infinities are not values. cTyMinGapSingle when every value that is left
  is the same one, cTyMinGapNone when none is left. }
function TyMinGapOf(const AValues: array of Double): Double;
{ The same statistic over the base values of a set of series on AAxis --
  every row of every store, whatever its value column holds. On a log axis
  a value at or under zero is dropped and the rest are measured in decades,
  which is the space a log axis is laid out in. }
function TyLiPosMinGap(const AStores: array of TTyDataStore;
  const ASeries: TTyIntegerArray; AAxis: TTyAxis): Double;
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
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  APPI: Integer = 96); overload;

type
  { A dataZoom's hold on one axis. Raw is the raw extent measured when the
    window was worked out -- upstream builds an axis' raw extent info ONCE
    per update, so a zoomed axis keeps that one and is not re-measured from
    the rows the zoom has since filtered away. ZoomLo / ZoomHi are the
    window's ends, not-a-number where the window reaches 0% or 100% and that
    end nices as if there were no zoom. }
  TTyAxisZoom = record
    Axis: TTyAxis;
    Raw: TTyAxisRawExtent;
    Any: Boolean;
    ZoomLo, ZoomHi: Double;
  end;
  TTyAxisZoomArray = array of TTyAxisZoom;

{ The same with dataZoom's pins: a pinned end is the window's own, fixed --
  no nice step rounds it out and no half bar widens it. }
procedure TyApplyAxisExtents(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  APPI: Integer; const AZooms: TTyAxisZoomArray); overload;

{ axis.__alignTo: the axis AAxis aligns its ticks to, or nil -- per grid and
  direction, walking the number axes in reverse index order, the last that
  does not ask for alignTicks is the reference (the first to ask when all
  do), and every other asker aligns to it. }
function TyAxisAlignTo(AOption: TTyChartOption; ABuild: TTyChartBuild;
  AAxis: TTyAxis): TTyAxis;

{ data.mapDimensionsAll(axisDim): every column of the store on AAxis -- a
  stacked series' own value AND its stack result on its value axis, four on
  a candlestick's. What a dataZoom filters. }
function TyAxisDataDims(AStore: TTyDataStore; AAxis: TTyAxis;
  const ABinding: TTySeriesBinding; const AStack: TTySeriesStack): TTyIntegerArray;

{ scaleRawExtentInfo for AAxis over the stores AS THEY STAND: the union of
  what its series put on it -- a stack's total on its value axis, a log
  axis' positive values -- and TyAxisRawExtent over that. What a dataZoom
  measures its percents against, and what TyApplyAxisExtents starts from.
  AAny: some series gave an extent. }
function TyAxisNoZoomExtent(AOption: TTyChartOption;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  AAxis: TTyAxis; const AMainType: string; out AAny: Boolean): TTyAxisRawExtent;

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
    if ABuild.Axis(AMainType, i) <> nil then Result[i] := ABuild.Axis(AMainType, i).Id
    else Result[i] := '';
end;

{ Which axes of a family are index holes [Batch 97] }
function AxisHoles(ABuild: TTyChartBuild; const AMainType: string): TTyBoolArray;
var i: Integer;
begin
  Result := nil;
  SetLength(Result, ABuild.AxisCount(AMainType));
  for i := 0 to High(Result) do Result[i] := ABuild.Axis(AMainType, i) = nil;
end;

{ Each calendar component's `id`, '' where it has none. }
function CalendarIds(AOption: TTyChartOption): TTyStringArray;
var
  k: Integer;
  d: TJSONData;
begin
  Result := nil;
  SetLength(Result, AOption.ComponentCount('calendar'));
  for k := 0 to High(Result) do
  begin
    Result[k] := '';
    d := AOption.ComponentAt('calendar', k);
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      d := TJSONObject(d).Find('id');
      if (d <> nil) and (d.JSONType = jtString) then Result[k] := d.AsString
      else if (d <> nil) and (d.JSONType = jtNumber) then Result[k] := d.AsString;
    end;
  end;
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
    { AN INDEX HOLE replaceMerge left: no model, so nothing to say about it
      either -- the slot stays so the later series keep their indices
      [Batch 97] }
    if (node = nil) and (AOption.ComponentAt('series', i) <> nil) then
    begin
      Result[i] := b;
      Continue;
    end;
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
    b.CalendarIndex := -1;

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

    if sys = TyCalendarSysName then
    begin
      { A CALENDAR: which one, by calendarIndex or calendarId; its dates and
        its days are the calendar's own, not an axis'. [Batch 70] }
      b.CalendarIndex := TyResolveComponentRef(node, 'calendarIndex', 'calendarId',
        AOption.ComponentCount('calendar'), CalendarIds(AOption));
      if b.CalendarIndex < 0 then
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

    if sys = 'view' then
    begin
      { THE THIRD SYSTEM, AND THE ONE WITH NOTHING TO LOOK UP. A radar names
        which radar; a cartesian names which pair of axes. A view belongs to
        the series that draws into it -- there is no `view` component and no
        viewIndex -- so naming the system IS resolving it, and the series
        solves its own geometry from the box the way a pie does. }
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
      ABuild.AxisCount('xAxis'), AxisIds(ABuild, 'xAxis'), AxisHoles(ABuild, 'xAxis'));
    yi := TyResolveComponentRef(node, 'yAxisIndex', 'yAxisId',
      ABuild.AxisCount('yAxis'), AxisIds(ABuild, 'yAxis'), AxisHoles(ABuild, 'yAxis'));
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

procedure SortDoubles(var A: TTyDoubleArray);
var
  n, i, j, k: Integer;
  t: Double;

  procedure Sift(ARoot, AEnd: Integer);
  begin
    i := ARoot;
    while 2 * i + 1 <= AEnd do
    begin
      j := 2 * i + 1;
      if (j < AEnd) and (A[j] < A[j + 1]) then Inc(j);
      if A[i] >= A[j] then Exit;
      t := A[i];
      A[i] := A[j];
      A[j] := t;
      i := j;
    end;
  end;

begin
  { A heap sort: a large bar series is tens of thousands of rows in any
    order, and the gap statistic has to sort them every build. }
  n := Length(A);
  for k := n div 2 - 1 downto 0 do Sift(k, n - 1);
  for k := n - 1 downto 1 do
  begin
    t := A[0];
    A[0] := A[k];
    A[k] := t;
    Sift(0, k - 1);
  end;
end;

function MinGapOfSorted(const AVals: TTyDoubleArray): Double;
var
  i: Integer;
  gap: Double;
begin
  if Length(AVals) = 0 then Exit(cTyMinGapNone);
  Result := Infinity;
  for i := 1 to High(AVals) do
  begin
    gap := AVals[i] - AVals[i - 1];
    { STRICTLY positive. Duplicates are ordinary -- two series both reporting
      the same x -- and a zero gap would collapse every bar to nothing. }
    if (gap > 0) and (gap < Result) then Result := gap;
  end;
  if IsInfinite(Result) then Result := cTyMinGapSingle;
end;

function TyMinGapOf(const AValues: array of Double): Double;
var
  vals: TTyDoubleArray;
  i, n: Integer;
begin
  n := 0;
  SetLength(vals, Length(AValues));
  for i := 0 to High(AValues) do
    if not (IsNan(AValues[i]) or IsInfinite(AValues[i])) then
    begin
      vals[n] := AValues[i];
      Inc(n);
    end;
  SetLength(vals, n);
  SortDoubles(vals);
  Result := MinGapOfSorted(vals);
end;

function TyLiPosMinGap(const AStores: array of TTyDataStore;
  const ASeries: TTyIntegerArray; AAxis: TTyAxis): Double;
var
  vals: TTyDoubleArray;
  k, si, col, r, n: Integer;
  v: Double;
  isLog: Boolean;
begin
  Result := cTyMinGapNone;
  if (AAxis = nil) or (AAxis.Scale = nil) then Exit;
  isLog := AAxis.AxisType = atLog;
  vals := nil;
  n := 0;
  for k := 0 to High(ASeries) do
  begin
    si := ASeries[k];
    if (si < 0) or (si > High(AStores)) or (AStores[si] = nil) then Continue;
    col := AStores[si].DimIndexOf(AAxis.Dim);
    if col < 0 then Continue;
    { THE RAW ROWS: upstream's axis statistics run at 920, before the
      dataZoom filter (1000) -- a zoom does not change a bar's width.
      [Batch 60: this read the view, which the zoom had narrowed.] }
    for r := 0 to AStores[si].RawCount - 1 do
    begin
      v := AStores[si].GetByRaw(col, r);
      if IsNan(v) or IsInfinite(v) then Continue;
      { A log axis' TransformIn answers not-a-number at or under zero, which
        is upstream's `v > 0` filter. }
      if isLog then
      begin
        v := AAxis.Scale.Mapper.TransformIn(v);
        if IsNan(v) or IsInfinite(v) then Continue;
      end;
      if n > High(vals) then SetLength(vals, Max(16, n * 2));
      vals[n] := v;
      Inc(n);
    end;
  end;
  SetLength(vals, n);
  SortDoubles(vals);
  Result := MinGapOfSorted(vals);
end;

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

{ ==================== the raw extent, upstream's order ==================== }

{ JavaScript's parseFloat: the longest numeric prefix, not-a-number when
  there is none. '10%' is 10, '1e3px' 1000, 'abc' not-a-number. }
function JsParseFloat(const AText: string): Double;
var
  s: string;
  i, n, code: Integer;
  seenDigit, seenDot, seenExp: Boolean;
begin
  Result := NaN;
  s := TrimLeft(AText);
  n := 0;
  i := 1;
  if (i <= Length(s)) and (s[i] in ['+', '-']) then Inc(i);
  if Copy(s, i, 8) = 'Infinity' then
  begin
    if (i > 1) and (s[1] = '-') then Exit(NegInfinity);
    Exit(Infinity);
  end;
  seenDigit := False;
  seenDot := False;
  seenExp := False;
  while i <= Length(s) do
  begin
    if s[i] in ['0'..'9'] then
    begin
      seenDigit := True;
      n := i;
    end
    else if (s[i] = '.') and not seenDot and not seenExp then
      seenDot := True
    else if (s[i] in ['e', 'E']) and seenDigit and not seenExp
      and (i < Length(s)) and ((s[i + 1] in ['0'..'9'])
        or ((i + 1 < Length(s)) and (s[i + 1] in ['+', '-'])
          and (s[i + 2] in ['0'..'9']))) then
    begin
      seenExp := True;
      if s[i + 1] in ['+', '-'] then Inc(i);
    end
    else
      Break;
    Inc(i);
  end;
  if not seenDigit then Exit;
  Val(Copy(s, 1, n), Result, code);
  if code <> 0 then Result := NaN;
end;

{ JavaScript's Number(x) for an option value. False for null or absent --
  upstream's "not specified" -- and not-a-number for whatever Number() cannot
  read, which is a deliberate invalid bound, not an absent one. }
function JsNumberOf(AData: TJSONData; out AValue: Double): Boolean;
var s: string; code: Integer;
begin
  AValue := NaN;
  Result := False;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  Result := True;
  case AData.JSONType of
    jtNumber: AValue := AData.AsFloat;
    jtBoolean: if AData.AsBoolean then AValue := 1 else AValue := 0;
    jtString:
      begin
        s := Trim(AData.AsString);
        if s = '' then AValue := 0
        else if s = 'Infinity' then AValue := Infinity
        else if s = '-Infinity' then AValue := NegInfinity
        else
        begin
          Val(s, AValue, code);
          if code <> 0 then AValue := NaN;
        end;
      end;
  end;
end;

{ JavaScript's Number() of an array: its string form read as a number --
  [] is 0, [3] is 3, ['c'] and [1, 2] are not numbers. }
function JsNumberOfArray(AArr: TJSONArray): Double;
var
  d: TJSONData;
  s: string;
  code: Integer;
begin
  if AArr.Count = 0 then Exit(0);
  if AArr.Count > 1 then Exit(NaN);
  d := AArr.Items[0];
  case d.JSONType of
    jtNull: Result := 0;
    jtNumber: Result := d.AsFloat;
    jtArray: Result := JsNumberOfArray(TJSONArray(d));
    jtString:
      begin
        s := Trim(d.AsString);
        if s = '' then Result := 0
        else
        begin
          Val(s, Result, code);
          if code <> 0 then Result := NaN;
        end;
      end;
  else
    Result := NaN;
  end;
end;

{ UPSTREAM'S ORDINAL parse (Ordinal.ts): a string is a category's NAME,
  looked up as written -- no trim, and never read as a number, so '3' names
  nothing and blanks the axis -- and anything else is Number()'d and rounded
  the way Math.round rounds: 2.5 is 3, -2.5 is -2. }
function ParseOrdinalBound(AData: TJSONData; AAxis: TTyAxis;
  out AValue: Double): Boolean;
begin
  AValue := NaN;
  Result := False;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  Result := True;
  case AData.JSONType of
    jtString:
      if AAxis.Scale is TTyOrdinalScale then
        AValue := TTyOrdinalScale(AAxis.Scale).ParseText(AData.AsString);
    jtNumber: AValue := AData.AsFloat;
    jtBoolean: if AData.AsBoolean then AValue := 1 else AValue := 0;
    jtArray: AValue := JsNumberOfArray(TJSONArray(AData));
  end;
  if (AData.JSONType <> jtString) and not (IsNan(AValue) or IsInfinite(AValue)) then
    AValue := TyJsRound(AValue);
end;

{ One bound the way the axis' scale parses it: Number() on a number axis, a
  date on a time axis, a category on a category one. }
function ParseBound(AData: TJSONData; AAxis: TTyAxis; out AValue: Double): Boolean;
var ms: Double;
begin
  if (AAxis <> nil) and (AAxis.AxisType = atCategory) then
    Exit(ParseOrdinalBound(AData, AAxis, AValue));
  if (AAxis <> nil) and (AAxis.AxisType = atTime) and (AData <> nil)
    and (AData.JSONType = jtString) then
  begin
    AValue := NaN;
    if TyParseDateMs(AData.AsString, ms) then AValue := ms;
    Exit(True);
  end;
  Result := JsNumberOf(AData, AValue);
end;

{ parsePercent(item, 1) || 0 -- one end of a value axis' boundaryGap as a
  RATIO of the data's span. A number is a ratio already (0.1 is ten per
  cent); a string ending in '%' is its number over a hundred; any other
  string is parseFloat'd, and 'center', 'left' and the rest are the ratios a
  box position would give them. A boolean is nothing. }
function GapRatio(AData: TJSONData): Double;
var s: string;
begin
  Result := 0;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtString:
      begin
        s := AData.AsString;
        if (s = 'center') or (s = 'middle') then s := '50%'
        else if (s = 'left') or (s = 'top') then s := '0%'
        else if (s = 'right') or (s = 'bottom') then s := '100%';
        if (Trim(s) <> '') and (Trim(s)[Length(Trim(s))] = '%') then
          Result := JsParseFloat(s) / 100 * 1
        else
          Result := JsParseFloat(s);
      end;
  end;
  if IsNan(Result) then Result := 0;
end;

function JsTruthyOf(AData: TJSONData): Boolean;
begin
  Result := False;
  if AData = nil then Exit;
  case AData.JSONType of
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (not IsNan(AData.AsFloat)) and (AData.AsFloat <> 0);
    jtString: Result := AData.AsString <> '';
    jtArray, jtObject: Result := True;
  end;
end;

function Finite(AValue: Double): Boolean;
begin
  Result := not (IsNan(AValue) or IsInfinite(AValue));
end;

function TyAxisRawExtent(ANode: TJSONObject; AAxis: TTyAxis;
  ADataLo, ADataHi: Double; ARequireStartValue: Boolean): TTyAxisRawExtent;
var
  d: TJSONData;
  dLo, dHi, v, span, sv: Double;
  hasLo, hasHi, interval, needZero, svSpecified, ordinal: Boolean;
  nCat: Integer;
  mask: TFPUExceptionMask;
begin
  Result := Default(TTyAxisRawExtent);
  { A CATEGORY AXIS takes the same path with three differences, upstream's
    own: no dataMin / dataMax key widens its data, an end nobody wrote is
    the first or the last category rather than the data plus a gap, and an
    axis with no categories at all is blank. }
  ordinal := (AAxis <> nil) and (AAxis.AxisType = atCategory);
  nCat := 0;
  if ordinal and (AAxis.Scale is TTyOrdinalScale) then
    nCat := TTyOrdinalScale(AAxis.Scale).CategoryCount;
  { Not-a-number is a legal value all the way through, as in JavaScript, and
    comparing one with the traps on raises. }
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide]);
  try
    { (1) THE DATA, widened by the option's own dataMin / dataMax -- which
      can only widen it. Nothing at all is not-a-number from here on. }
    dLo := ADataLo;
    dHi := ADataHi;
    if (ANode <> nil) and not ordinal then
    begin
      if ParseBound(ANode.Find('dataMin'), AAxis, v) and Finite(v) and (v < dLo) then
        dLo := v;
      if ParseBound(ANode.Find('dataMax'), AAxis, v) and Finite(v) and (v > dHi) then
        dHi := v;
    end;
    span := dHi - dLo;
    if not (Finite(span) and (span >= 0)) then
    begin
      dLo := NaN;
      dHi := NaN;
    end;

    { (2) min AND max, which pin. 'dataMin' and 'dataMax' pin to the data;
      anything else goes through the scale's parse, and even a not-a-number
      pins -- it is a deliberate bad bound, and it blanks the axis. }
    hasLo := False;
    hasHi := False;
    Result.Lo := NaN;
    Result.Hi := NaN;
    if ANode <> nil then
    begin
      d := ANode.Find('min');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'dataMin') then
      begin
        Result.Lo := dLo;
        hasLo := True;
      end
      else if ParseBound(d, AAxis, v) then
      begin
        Result.Lo := v;
        hasLo := True;
      end;
      d := ANode.Find('max');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'dataMax') then
      begin
        Result.Hi := dHi;
        hasHi := True;
      end
      else if ParseBound(d, AAxis, v) then
      begin
        Result.Hi := v;
        hasHi := True;
      end;
    end;
    Result.FixLo := hasLo;
    Result.FixHi := hasHi;

    { (3) boundaryGap, on the ends nobody pinned, as a ratio of the DATA's
      span -- or of the lone value's size when there is one. A category
      axis' free ends are its first and last category. }
    if ordinal then
    begin
      if not hasLo then
        if nCat > 0 then Result.Lo := 0 else Result.Lo := NaN;
      if not hasHi then
        if nCat > 0 then Result.Hi := nCat - 1 else Result.Hi := NaN;
      hasLo := True;
      hasHi := True;
    end;
    span := dHi - dLo;
    if IsNan(span) or (span = 0) then span := Abs(dLo);
    if not hasLo then
    begin
      v := 0;
      if ANode <> nil then
      begin
        d := ANode.Find('boundaryGap');
        if (d <> nil) and (d.JSONType = jtArray) then
        begin
          if TJSONArray(d).Count > 0 then v := GapRatio(TJSONArray(d).Items[0]);
        end
        else if (d <> nil) and (d.JSONType <> jtBoolean) then
          v := GapRatio(d);
      end;
      Result.Lo := dLo - v * span;
    end;
    if not hasHi then
    begin
      v := 0;
      if ANode <> nil then
      begin
        d := ANode.Find('boundaryGap');
        if (d <> nil) and (d.JSONType = jtArray) then
        begin
          if TJSONArray(d).Count > 1 then v := GapRatio(TJSONArray(d).Items[1]);
        end
        else if (d <> nil) and (d.JSONType <> jtBoolean) then
          v := GapRatio(d);
      end;
      Result.Hi := dHi + v * span;
    end;

    { (4) not a finite number is no end. }
    if not Finite(Result.Lo) then Result.Lo := NaN;
    if not Finite(Result.Hi) then Result.Hi := NaN;
    { (a category axis with no categories at all keeps the ends it was
      given and is blank all the same -- the scale answers that one) }
    Result.Blank := IsNan(Result.Lo) or IsNan(Result.Hi);

    { (5) ZERO, on a plain value axis unless `scale` is truthy -- and only
      pulling an end nobody pinned, when both ends share a sign. }
    interval := (AAxis <> nil) and (AAxis.AxisType = atValue);
    needZero := interval and not ((ANode <> nil) and JsTruthyOf(ANode.Find('scale')));
    Result.Incl0 := needZero;
    if needZero then
    begin
      if (Result.Lo > 0) and (Result.Hi > 0) and not Result.FixLo then
        Result.Lo := 0;
      if (Result.Lo < 0) and (Result.Hi < 0) and not Result.FixHi then
        Result.Hi := 0;
    end;

    { (6) BACKWARDS IS TURNED ROUND, and the axis inverted -- the pin flags
      stay on their index, as upstream leaves them. }
    if Result.Lo > Result.Hi then
    begin
      v := Result.Lo;
      Result.Lo := Result.Hi;
      Result.Hi := v;
      Result.ToggleInverse := True;
    end;

    { (7) startValue joins the extent and pins the end it moves. A bar's
      value axis asks for one even unwritten: 1 on a log axis, and on a plain
      one zero -- which the zero rule has always already covered. }
    svSpecified := False;
    sv := NaN;
    if ANode <> nil then
      svSpecified := ParseBound(ANode.Find('startValue'), AAxis, sv);
    if (not Finite(sv)) and ARequireStartValue then
    begin
      if (AAxis <> nil) and (AAxis.AxisType = atLog) then sv := 1 else sv := 0;
    end;
    if Finite(sv) then
    begin
      Result.HasStartValue := True;
      Result.StartValue := sv;
    end;
    if Finite(sv) and (svSpecified or (not interval) or needZero) then
    begin
      if (sv < Result.Lo) and not Result.FixLo then
      begin
        Result.Lo := sv;
        Result.FixLo := True;
      end
      else if (sv > Result.Hi) and not Result.FixHi then
      begin
        Result.Hi := sv;
        Result.FixHi := True;
      end;
    end;

    { (8) NOTHING AT OR UNDER ZERO ON A LOG AXIS: upstream's sanitize moves
      such an end -- a min of 0, a bar's base -- onto the lowest value the
      data holds. Only while the data is an extent at all; the pins stay. }
    if (AAxis <> nil) and (AAxis.AxisType = atLog)
      and Finite(dLo) and Finite(dHi) and (dLo <= dHi) then
    begin
      if Finite(Result.Lo) and (Result.Lo <= 0) then Result.Lo := dLo;
      if Finite(Result.Hi) and (Result.Hi <= 0) then Result.Hi := dLo;
      { A PAIR THAT NOW RUNS BACKWARDS IS NO EXTENT. Upstream means to close
        it (ensureExtentAscSimply), but asks isValidBoundsForExtent first,
        which wants start <= end -- so it never does. The log scale then
        refuses the pair whole and keeps its initial [Infinity, -Infinity],
        which the nice step makes [0, 1]: one decade up from 1, whatever
        was written. }
      if Finite(Result.Lo) and Finite(Result.Hi) and (Result.Lo > Result.Hi) then
      begin
        Result.Lo := NaN;
        Result.Hi := NaN;
      end;
    end;
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    { And the SSE flags, which ClearExceptions leaves standing on this CPU. }
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

function TyAxisAlignTo(AOption: TTyChartOption; ABuild: TTyChartBuild;
  AAxis: TTyAxis): TTyAxis;
var
  g: TTyGridBuild;
  horiz: Boolean;
  k, cnt: Integer;
  ax, ref: TTyAxis;
  main: string;
  askers: array of TTyAxis;
  isAsker: Boolean;

  function Numeric(A: TTyAxis): Boolean;
  begin
    Result := (A <> nil) and (A.Scale is TTyIntervalScale)
      and not (A.Scale is TTyTimeScale);
  end;

  function Asks(A: TTyAxis): Boolean;
  var node: TJSONObject; d: TJSONData;
  begin
    Result := False;
    node := ObjAt(AOption, main, A.ComponentIndex);
    if node = nil then Exit;
    d := node.Find('alignTicks');
    if (d = nil) or not JsTruthyOf(d) then Exit;
    d := node.Find('interval');
    Result := (d = nil) or (d.JSONType = jtNull);
  end;

begin
  Result := nil;
  if (ABuild = nil) or (AAxis = nil) or not Numeric(AAxis) then Exit;
  if (AAxis.GridIndex < 0) or (AAxis.GridIndex >= ABuild.GridCount) then Exit;
  g := ABuild.Grid(AAxis.GridIndex);
  horiz := AAxis.Dim = 'x';
  if horiz then main := 'xAxis' else main := 'yAxis';
  if horiz then cnt := g.XAxisCount else cnt := g.YAxisCount;
  ref := nil;
  askers := nil;
  for k := cnt - 1 downto 0 do
  begin
    if horiz then ax := g.XAxis(k) else ax := g.YAxis(k);
    if not Numeric(ax) then Continue;
    if Asks(ax) then
    begin
      SetLength(askers, Length(askers) + 1);
      askers[High(askers)] := ax;
    end
    else
      ref := ax;
  end;
  if (ref = nil) and (Length(askers) > 0) then
  begin
    ref := askers[High(askers)];
    SetLength(askers, Length(askers) - 1);
  end;
  if ref = nil then Exit;
  isAsker := False;
  for k := 0 to High(askers) do
    if askers[k] = AAxis then isAsker := True;
  if isAsker then Result := ref;
end;

function TyAxisDataDims(AStore: TTyDataStore; AAxis: TTyAxis;
  const ABinding: TTySeriesBinding; const AStack: TTySeriesStack): TTyIntegerArray;
var n: Integer;
begin
  Result := ColumnsForAxis(AStore, AAxis);
  if AStack.Stacked and (AStack.ResultCol >= 0) and (AAxis = ABinding.ValueAxis) then
  begin
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := AStack.ResultCol;
  end;
end;

function TyAxisNoZoomExtent(AOption: TTyChartOption;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  AAxis: TTyAxis; const AMainType: string; out AAny: Boolean): TTyAxisRawExtent;
var
  k, c, si: Integer;
  cols: TTyIntegerArray;
  feeders: TTyIntegerArray;
  lo, hi, dlo, dhi: Double;
  filter: TTyExtentFilter;
  requireStart: Boolean;
begin
  AAny := False;
  { A CATEGORY AXIS' RANGE is its categories, first to last -- read off the
    axis, never computed from the values, so a name the data never mentions
    still gets a band and a bar chart does not shuffle when a value goes
    missing -- unless min and max narrow it, or widen it past either end,
    which upstream lets them do. It goes through the raw extent below with
    the number axes, in its ordinal mode.

    But the count has to be read AFTER the rows are in. An axis with no
    `data` of its own collects its categories while the store parses, and
    until this ran the extent was the one fixed during construction, when the
    list was empty: one band across the whole plot with every point stacked
    on it. This is the one place the extent comes from, asked once the list
    is full.
    [Revised in batch 44: this set [0, n - 1] and returned before min and
    max were read.] }
  if AAxis.AxisType = atLog then filter := defPositive else filter := defNone;

  requireStart := False;
  lo := Infinity;
  hi := NegInfinity;
  feeders := AIndex.SeriesOnAxis(AAxis);
  for k := 0 to High(feeders) do
  begin
    si := feeders[k];
    { A BAR WANTS ITS BASE IN VIEW: upstream's __requireStartValue, on the
      bar's value axis and nowhere else. }
    if (si >= 0) and (si <= High(ABindings))
      and ((ABindings[si].SeriesType = 'bar')
        or (ABindings[si].SeriesType = 'pictorialBar'))
      and (ABindings[si].ValueAxis = AAxis) then
      requireStart := True;
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
      AAny := True;
      { unionExtentFromExtent: a series whose extent has an infinite end
        adds NOTHING -- upstream drops it whole, so one 'Infinity' blanks
        only an axis nothing else is on. }
      if IsInfinite(dlo) or IsInfinite(dhi) or (dlo > dhi) then Continue;
      if dlo < lo then lo := dlo;
      if dhi > hi then hi := dhi;
    end;
  end;
  { THE RAW EXTENT, UPSTREAM'S ORDER. No data is not-a-number from here on --
    the data loop left the ends at their infinities -- and min, max,
    boundaryGap, zero, a backwards pair and startValue all happen in
    scaleRawExtentInfo's sequence, in TyAxisRawExtent. }
  if AAxis.AxisType = atCategory then requireStart := False;
  Result := TyAxisRawExtent(ObjAt(AOption, AMainType, AAxis.ComponentIndex),
    AAxis, lo, hi, requireStart);
end;

procedure TyApplyAxisExtents(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  APPI: Integer);
begin
  TyApplyAxisExtents(AOption, ABuild, ABindings, AStores, AStacks, AIndex,
    APPI, nil);
end;

procedure TyApplyAxisExtents(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  APPI: Integer; const AZooms: TTyAxisZoomArray);
var
  g, a: Integer;
  ax: TTyAxis;
  alignTo: TTyAxis;
  aligners: array of TTyAxis;
  { the axis being done: its ends a dataZoom pinned (zoomFixMM) }
  zoomFixLo, zoomFixHi: Boolean;

  { A BAR OF THIS TYPE IS LAID OUT ALONG AAxis -- upstream's statistics key,
    which exists for a series the legend has switched off and for one with no
    rows. The index skips the first, so the bindings are asked directly. }
  function KeyOnAxis(AAxis: TTyAxis; const AType: string): Boolean;
  var i: Integer;
  begin
    Result := False;
    for i := 0 to High(ABindings) do
      if (ABindings[i].BaseAxis = AAxis) and (ABindings[i].SeriesType = AType)
        and (ABindings[i].CoordSysName = 'cartesian2d') then Exit(True);
  end;

  { UPSTREAM'S ctnShp. `containShape` as written, JavaScript-truthy; absent,
    it is on unless the axis has bands, where the bar already sits inside
    one. And only on the base axis of a series that registers the handler:
    the axis a bar stands on is its value axis, and that one is never
    widened.

    [Batch 64: FOUR types register it, not two -- bar and pictorialBar
    (layout/barGrid.ts) and candlestick and boxplot (their layouts), all with
    the same band-width handler. A zoomed candlestick on a category axis
    without boundaryGap (candlestick-sh) mapped its candles half a band too
    wide; its markers showed it.] }
  function WantsContainShape(AAxis: TTyAxis; ANode: TJSONObject): Boolean;
  var
    d: TJSONData;
    opt: Boolean;
  begin
    d := nil;
    if ANode <> nil then d := ANode.Find('containShape');
    if (d = nil) or (d.JSONType = jtNull) then opt := not AAxis.OnBand
    else opt := JsTruthyOf(d);
    Result := opt and (KeyOnAxis(AAxis, 'bar')
      or KeyOnAxis(AAxis, 'pictorialBar') or KeyOnAxis(AAxis, 'candlestick')
      or KeyOnAxis(AAxis, 'boxplot'));
  end;

  { THE MAPPING EXTENT: the effective one, widened by half a bar each way so
    the bars at its ends are drawn inside the plot. Run once the effective
    extent is final. Ticks, labels and split lines stay on the effective
    extent; only where values land moves.

    The half bar is measured in data space, from the axis' pixel length AS
    THE LAYOUT OPTIONS GAVE IT -- phase A's extent, before labels shrank the
    plot. Upstream does the same, because its nice step runs on a freshly
    made coordinate system that has not been shrunk yet. }
  procedure ApplyContainShape(AAxis: TTyAxis);
  const
    cSingleRatio: Double = 0.8;
  var
    e, lin: TTyRange;
    a, b, span, px, w2, gap, sup0, sup1, lo, hi: Double;
    haveSup, ordinal: Boolean;
    k: Integer;
    typ: string;
  begin
    ordinal := AAxis.Scale is TTyOrdinalScale;
    { A band already holds its bar: no half width to add. }
    if ordinal and AAxis.OnBand then Exit;
    e := AAxis.Scale.GetExtent;
    a := AAxis.Scale.Mapper.TransformIn(e.Start);
    b := AAxis.Scale.Mapper.TransformIn(e.Stop);
    { the span in the linear space as the scale KEEPS it -- a log axis' nice
      decades -- while the ends the half bar is added to are taken through
      the logarithm, as upstream's transformIn takes them }
    lin := AAxis.Scale.LinearExtent2(sekEffective);
    span := lin.Stop - lin.Start;
    px := AAxis.PxLength;
    haveSup := False;
    sup0 := 0;
    sup1 := 0;
    for k := 0 to 3 do
    begin
      case k of
        0: typ := 'bar';
        1: typ := 'pictorialBar';
        2: typ := 'candlestick';
      else
        typ := 'boxplot';
      end;
      if not KeyOnAxis(AAxis, typ) then Continue;
      w2 := NaN;
      if ordinal then
      begin
        { One category's width in categories -- 1, give or take the last bit,
          which upstream's round trip through pixels decides. }
        if (span <> 0) and (px <> 0) and not IsNan(span) then
          w2 := px / span * span / px;
      end
      else
      begin
        gap := TyLiPosMinGap(AStores,
          AIndex.SeriesOnAxisOfKey(AAxis, TySeriesStatKey(typ, 'cartesian2d')),
          AAxis);
        if (not IsNan(span)) and (not IsInfinite(span)) and (span > 0)
          and (gap > 0) then
          w2 := gap
        else if (gap = cTyMinGapSingle) and (px > 0) then
          { ONE VALUE: the band is four fifths of the axis, and the round
            trip through pixels is upstream's -- 0.8 * span parts from it in
            the last bit a third of the time. }
          w2 := px * cSingleRatio * span / px;
      end;
      if IsNan(w2) or IsInfinite(w2) then Continue;
      haveSup := True;
      sup0 := Min(sup0, -w2 / 2);
      sup1 := Max(sup1, w2 / 2);
      AAxis.ZeroDiscouraged := True;
    end;
    if not haveSup then Exit;
    if ordinal then
      AAxis.Scale.SetExtent2(sekMapping,
        TyRange(Min(e.Start, e.Start + sup0), Max(e.Stop, e.Stop + sup1)))
    else
    begin
      { AN END A dataZoom PINNED IS NOT WIDENED: the axis ends exactly at the
        window, and a bar past it is clipped }
      if zoomFixLo then lo := e.Start
      else lo := Min(e.Start, AAxis.Scale.Mapper.TransformOut(a + sup0));
      if zoomFixHi then hi := e.Stop
      else hi := Max(e.Stop, AAxis.Scale.Mapper.TransformOut(b + sup1));
      if (lo < e.Start) or (hi > e.Stop) then
        AAxis.Scale.SetExtent2(sekMapping, TyRange(lo, hi));
    end;
  end;

  { A category axis' extent from its raw one: the ends as rounded -- not a
    number where a bound named nothing, which blanks the axis: no count, no
    ticks and no bars. And a window of more categories than anything can draw
    is refused rather than walked: min: 1e300 would build a label per
    category. }
  procedure ApplyCategoryExtent(AAxis: TTyAxis; const ARaw: TTyAxisRawExtent;
    ACtnShp: Boolean);
  const
    cMaxWindow = 1048576;
  var
    e: TTyRange;
    blank: Boolean;
  begin
    e.Start := ARaw.Lo;
    e.Stop := ARaw.Hi;
    blank := ARaw.Blank;
    if (not blank) and (ARaw.Hi - ARaw.Lo + 1 > cMaxWindow) then
    begin
      blank := True;
      e.Start := NaN;
      e.Stop := NaN;
    end;
    AAxis.Scale.SetExtent(e);
    AAxis.Scale.MarkedBlank := blank;
    { startValue has already moved the extent; nothing stands on this axis }
    AAxis.Scale.StartValue := NaN;
    if ACtnShp and not blank then ApplyContainShape(AAxis);
  end;

  procedure DoAxis(AAxis: TTyAxis; const AMainType: string;
    AAlignTo: TTyAxis; AAlignPx: Double);
  var
    k, zi: Integer;
    node: TJSONObject;
    d: TJSONData;
    ivl, split: Double;
    minor: Integer;
    minorSplit: Integer;
    wantMinor: Boolean;
    sub2: TJSONData;
    lo, hi, minIvl, maxIvl: Double;
    any: Boolean;
    raw: TTyAxisRawExtent;
    ctnShp: Boolean;
  begin
    if AAxis = nil then Exit;
    node := ObjAt(AOption, AMainType, AAxis.ComponentIndex);
    ctnShp := WantsContainShape(AAxis, node);
    zoomFixLo := False;
    zoomFixHi := False;
    zi := -1;
    for k := 0 to High(AZooms) do
      if AZooms[k].Axis = AAxis then zi := k;
    if zi >= 0 then
    begin
      { THE RAW EXTENT THE WINDOW WAS MEASURED ON, not one re-measured from
        the rows the zoom has filtered -- then makeFinal: a pinned end is the
        window's, fixed. (A log end is never at or under zero here: the
        window lies inside a sanitized extent.) }
      raw := AZooms[zi].Raw;
      any := AZooms[zi].Any;
      if not IsNan(AZooms[zi].ZoomLo) then
      begin
        raw.Lo := AZooms[zi].ZoomLo;
        raw.FixLo := True;
        zoomFixLo := True;
      end;
      if not IsNan(AZooms[zi].ZoomHi) then
      begin
        raw.Hi := AZooms[zi].ZoomHi;
        raw.FixHi := True;
        zoomFixHi := True;
      end;
    end
    else
      raw := TyAxisNoZoomExtent(AOption, ABindings, AStores, AStacks, AIndex,
        AAxis, AMainType, any);
    if (not any) and (AAxis.AxisType = atTime) and raw.Blank then
    begin
      { A TIME AXIS WITH NOTHING ON IT SHOWS TODAY, which is upstream's
        answer and the only one an author reads as empty rather than as
        broken: 0..1 on a time axis is the first second of 1970, and a
        chart that lost its data should not look like a chart about the
        Apollo programme. }
      raw.Hi := TyDateTimeToMs(Date, False);
      raw.Lo := raw.Hi - 86400000;
    end;

    { SIX ON A TIME AXIS, five everywhere else -- the options' own two
      defaults. The value is handed on as written; the nice step makes it a
      whole number the way upstream does. }
    if AAxis.AxisType = atTime then split := 6 else split := 5;
    ivl := NaN;
    minIvl := 0;
    maxIvl := 0;
    minor := 0;
    if node <> nil then
    begin
      d := node.Find('splitNumber');
      if (d <> nil) and (d.JSONType = jtNumber) then split := d.AsFloat;
      { `interval` AS WRITTEN, zero and negatives included: upstream draws no
        ticks for either, and the scale says so rather than this. }
      d := node.Find('interval');
      if (d <> nil) and (d.JSONType = jtNumber) then ivl := d.AsFloat;
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

    { A BACKWARDS min AND max INVERT THE AXIS, unless the chart asked for the
      old behaviour by name. }
    if raw.ToggleInverse and not ((AOption <> nil)
      and (AOption.Root is TJSONObject)
      and JsTruthyOf(TJSONObject(AOption.Root).Find('legacyMinMaxDontInverseAxis'))) then
      AAxis.Inverse := not AAxis.Inverse;

    if AAxis.AxisType = atCategory then
    begin
      if AAxis.Scale is TTyOrdinalScale then
        ApplyCategoryExtent(AAxis, raw, ctnShp);
      Exit;
    end;

    lo := raw.Lo;
    hi := raw.Hi;
    { A BLANK END IS NO EXTENT: upstream's nice step replaces the pair with
      [0, 1] -- a max written beside no data included -- and the pins stay. }
    if IsNan(lo) or IsNan(hi) then
    begin
      lo := 0;
      hi := 1;
    end;
    { A FLAT TIME RANGE OPENS BY A DAY EACH WAY, on the scale -- upstream's
      calcNiceForTimeScale. Opening it only where the ticks are made left the
      extent flat, and every tick then normalised to the middle of the axis. }
    if (AAxis.AxisType = atTime) and (lo = hi) then
    begin
      lo := lo - 86400000;
      hi := hi + 86400000;
    end;
    AAxis.Scale.SetExtent(TyRange(lo, hi));
    { NOTHING TO GO ON is still [0, 1] with ticks on it, as upstream's is; the
      flag is what keeps them from being drawn. }
    AAxis.Scale.MarkedBlank := raw.Blank;
    { AND WHERE ITS BARS STAND. Written every build, not-a-number included, so
      an axis that has lost its bars loses its start with them. }
    if raw.HasStartValue then AAxis.Scale.StartValue := raw.StartValue
    else AAxis.Scale.StartValue := NaN;
    if AAxis.Scale is TTyIntervalScale then
    begin
      TTyIntervalScale(AAxis.Scale).FixMin := raw.FixLo;
      TTyIntervalScale(AAxis.Scale).FixMax := raw.FixHi;
      { BEFORE Niceify, because they bound the step it is about to choose. }
      TTyIntervalScale(AAxis.Scale).MinInterval := minIvl;
      TTyIntervalScale(AAxis.Scale).MaxInterval := maxIvl;
      TTyIntervalScale(AAxis.Scale).ContainShape := ctnShp;
      { NOT NICIED WHEN IT IS A CALENDAR. Niceify opens the extent out to
        round numbers before picking a step, and the round number nearest a
        week in March 2024 is somewhere in 1973. A time scale is handed the
        tick count instead and snaps to the calendar itself. }
      if AAxis.Scale is TTyTimeScale then
        TTyTimeScale(AAxis.Scale).SplitNumber := TyValidSplitNumber(split, 10)
      { ALIGNED TO ANOTHER AXIS' TICKS, over the grid's pixel span as its
        option alone lays it out -- upstream aligns before the labels shrink
        the grid. A reference with nothing to align to nices instead. }
      else if (AAlignTo <> nil) and (AAlignTo.Scale is TTyIntervalScale)
        and TTyIntervalScale(AAxis.Scale).AlignTo(
          TTyIntervalScale(AAlignTo.Scale), raw.FixLo or zoomFixLo or zoomFixHi,
          raw.FixHi or zoomFixLo or zoomFixHi, raw.Incl0, AAlignPx) then
      else
        TTyIntervalScale(AAxis.Scale).Niceify(split, ivl);
      { AFTER Niceify: it is the major interval that gets subdivided, and
        Niceify is what decides the major interval. }
      TTyIntervalScale(AAxis.Scale).MinorSplitNumber := minor;
    end;
    { AFTER the effective extent is final: the half bar widens what the
      nice step left, pins and all. }
    if ctnShp then ApplyContainShape(AAxis);
  end;

  function InList(AAxis: TTyAxis): Boolean;
  var k: Integer;
  begin
    for k := 0 to High(aligners) do
      if aligners[k] = AAxis then Exit(True);
    Result := False;
  end;

  { THE AXIS IS A NUMBER AXIS -- value or log, not category and not time --
    and so can align or be aligned to. }
  function Numeric(AAxis: TTyAxis): Boolean;
  begin
    Result := (AAxis <> nil) and (AAxis.Scale is TTyIntervalScale)
      and not (AAxis.Scale is TTyTimeScale);
  end;

  { `alignTicks` asked for, and no `interval` written. }
  function WantsAlign(AAxis: TTyAxis; const AMainType: string): Boolean;
  var node: TJSONObject; d: TJSONData;
  begin
    Result := False;
    node := ObjAt(AOption, AMainType, AAxis.ComponentIndex);
    if node = nil then Exit;
    d := node.Find('alignTicks');
    if (d = nil) or not JsTruthyOf(d) then Exit;
    d := node.Find('interval');
    Result := (d = nil) or (d.JSONType = jtNull);
  end;

  { ONE DIRECTION OF ONE GRID, as upstream's prepareAlignToInCoordSysCreate
    and updateAxisTicks do it: walking the axes in REVERSE index order, the
    last number axis that does not ask to align is the reference -- or, if
    every one asks, the first to ask -- and every other asker aligns to it
    after the rest are niced. }
  procedure Direction(AGrid: TTyGridBuild; AHoriz: Boolean;
    const AMainType: string);
  var
    k, cnt: Integer;
    px: Double;
    list: array of TTyAxis;
  begin
    if AHoriz then cnt := AGrid.XAxisCount else cnt := AGrid.YAxisCount;
    SetLength(list, cnt);
    for k := 0 to cnt - 1 do
      if AHoriz then list[k] := AGrid.XAxis(k) else list[k] := AGrid.YAxis(k);
    alignTo := nil;
    aligners := nil;
    for k := cnt - 1 downto 0 do
    begin
      if not Numeric(list[k]) then Continue;
      if WantsAlign(list[k], AMainType) then
      begin
        SetLength(aligners, Length(aligners) + 1);
        aligners[High(aligners)] := list[k];
      end
      else
        alignTo := list[k];
    end;
    if (alignTo = nil) and (Length(aligners) > 0) then
    begin
      alignTo := aligners[High(aligners)];
      SetLength(aligners, Length(aligners) - 1);
    end;
    if alignTo = nil then aligners := nil;
    { The grid's span as its option alone lays it out, in LOGICAL px. }
    if AHoriz then px := AGrid.OuterXYWH.W else px := AGrid.OuterXYWH.H;
    if APPI > 0 then px := px * 96 / APPI;
    { EVERY AXIS THAT DOES NOT ALIGN FIRST, in reverse order, so the
      reference has its ticks before anyone asks for them. }
    for k := cnt - 1 downto 0 do
    begin
      ax := list[k];
      if not InList(ax) then DoAxis(ax, AMainType, nil, NaN);
    end;
    for k := 0 to High(aligners) do
      DoAxis(aligners[k], AMainType, alignTo, px);
  end;

begin
  if (ABuild = nil) or (AIndex = nil) then Exit;
  for g := 0 to ABuild.GridCount - 1 do
  begin
    Direction(ABuild.Grid(g), True, 'xAxis');
    Direction(ABuild.Grid(g), False, 'yAxis');
  end;
end;

initialization
  TySeriesRegisterBuiltinTypes;

finalization
  TySeriesClearTypes;

end.
