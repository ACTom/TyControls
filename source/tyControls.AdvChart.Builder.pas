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
     tyControls.AdvChart.Coord, tyControls.AdvChart.Layout;

type
  TTyAxisArray = array of TTyAxis;

  { One grid: a plot rect, the axes that named it, and the coordinate systems
    over their cross product. }
  TTyGridBuild = class
  private
    FComponentIndex: Integer;
    FOuterRect: TTyRectF;
    FPlotRect: TTyRectF;
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

{ ---- reading series data ---- }
type
  { One column of a series' store, as the filler needs it: what to call it, how
    to parse it, and -- for a category column -- whose list to intern against. }
  TTySeriesDim = record
    Name: string;
    Kind: TTyDimType;
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
  const ADims: TTySeriesDimArray; AStore: TTyDataStore): Integer;

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
  if d.JSONType = jtNumber then Exit(Trunc(d.AsFloat));
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
    if (v <> nil) and (v.JSONType <> jtNull) then
      cats[i] := v.AsString
    else if item.JSONType = jtNull then
      cats[i] := ''
    else if item is TJSONObject then
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
  else
    { Time falls back to an interval scale: epoch milliseconds ARE numbers, so
      the mapping is right and only the tick labelling is missing. }
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
  const ADims: TTySeriesDimArray; AStore: TTyDataStore): Integer;
var
  node: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  row: array of TTyDataValue;
  i, k, catDim, raw: Integer;
  item, v, cell: TJSONData;
  useIndex: Boolean;
  txt: string;
begin
  Result := 0;
  if (AOption = nil) or (AStore = nil) or (Length(ADims) = 0) then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if node = nil then Exit;
  d := node.Find('data');
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
      if useIndex and (k = catDim) then
      begin
        { The row index, and ONLY for the first category column: every other
          column still reads the item. }
        row[k] := TyDataNum(i);
        Continue;
      end;
      if (v <> nil) and (v is TJSONArray) then
      begin
        if k < TJSONArray(v).Count then cell := TJSONArray(v).Items[k] else cell := nil;
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

{ ==================== phase C ==================== }

procedure TyLayoutGrids(ABuild: TTyChartBuild; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  const AText: TTyAxisTextStyle);
var
  g, i, j, t: Integer;
  specs: TTyAxisLayoutSpecArray;
  ax: TTyAxis;
  ticks: TTyScaleTickArray;
  gb: TTyGridBuild;
  node: TJSONObject;

  procedure FillSpec(var ASpec: TTyAxisLayoutSpec; AAxis: TTyAxis; ANode: TJSONObject);
  var q: Integer;
  begin
    ASpec := Default(TTyAxisLayoutSpec);
    ASpec.Side := AAxis.Side;
    ASpec.ShowLabels := BoolIn(ANode, 'show', True);
    ASpec.Name := AAxis.Name;
    { From the caller's resolved theme style, NOT from literals here: the paint
      pass draws in the theme's font and gaps, so measuring in anything else
      sizes the plot rect for a chart nobody will draw. }
    ASpec.FontName := AText.FontName;
    ASpec.FontSizeLogical := AText.FontSizeLogical;
    ASpec.FontWeight := AText.FontWeight;
    ASpec.LabelMarginLogical := AText.LabelMarginLogical;
    ASpec.TickLengthLogical := AText.TickLengthLogical;
    ASpec.NameGapLogical := AText.NameGapLogical;
    ticks := AAxis.Scale.GetTicks;
    SetLength(ASpec.Labels, Length(ticks));
    SetLength(ASpec.Positions, Length(ticks));
    for q := 0 to High(ticks) do
    begin
      if AAxis.Scale is TTyOrdinalScale then
        ASpec.Labels[q] := TTyOrdinalScale(AAxis.Scale).GetLabel(ticks[q].Value)
      else
        { NumText, not FloatToStr: the paint pass formats the same tick with a
          forced '.' separator, and FloatToStr follows the machine's locale --
          on a comma-decimal machine the width measured here is not the width of
          the string that gets drawn. }
        ASpec.Labels[q] := NumText(ticks[q].Value);
      { The BAND-ADJUSTED, post-inverse fraction, so the layout layer and the
        renderer cannot disagree about where a label goes. }
      ASpec.Positions[q] := AAxis.NormalizedCoord(ticks[q].Value);
    end;
  end;

begin
  if (ABuild = nil) or (AMeasurer = nil) then Exit;
  for g := 0 to ABuild.GridCount - 1 do
  begin
    gb := ABuild.Grid(g);
    SetLength(specs, gb.XAxisCount + gb.YAxisCount);
    t := 0;
    for i := 0 to gb.XAxisCount - 1 do
    begin
      ax := gb.XAxis(i);
      node := ObjOf(AOption.ComponentAt('xAxis', ax.ComponentIndex));
      FillSpec(specs[t], ax, node);
      Inc(t);
    end;
    for i := 0 to gb.YAxisCount - 1 do
    begin
      ax := gb.YAxis(i);
      node := ObjOf(AOption.ComponentAt('yAxis', ax.ComponentIndex));
      FillSpec(specs[t], ax, node);
      Inc(t);
    end;

    { obcAll, explicitly. Our own default is obcAxisLabel while upstream's
      outerBoundsContain default is 'all', and taking the default here would
      make axis NAMES silently stop reserving room for themselves. }
    gb.FPlotRect := TySolveGrid(gb.FOuterRect, specs, AMeasurer, APPI, obmAuto, obcAll);

    { The second and final pixel write. Everything downstream reads band widths
      and coordinates live, so nothing has to be invalidated. }
    for j := 0 to gb.CartesianCount - 1 do
      gb.CartesianByIndex(j).SetRect(gb.FPlotRect);
  end;
end;

end.
