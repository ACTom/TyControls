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
    procedure Note(const AMsg: string);
  public
    destructor Destroy; override;
    function GridCount: Integer;
    function Grid(AIndex: Integer): TTyGridBuild;
    function AxisCount(const AMainType: string): Integer;
    { By GLOBAL component index. nil when absent. }
    function Axis(const AMainType: string; AComponentIndex: Integer): TTyAxis;
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
  const AMeasurer: ITyTextMeasurer; APPI: Integer);

{ ---- the rules, exposed because they are worth testing directly ---- }
{ An explicit type wins with NO validation; otherwise a `data` key that is
  present and not null makes the axis categorical. An EMPTY data array still
  does -- it is a fixed list of no categories, which is not the same as an axis
  that never declared one. }
function TyResolveAxisType(ANode: TJSONObject; out AType: TTyAxisType;
  out AUnknown: string): Boolean;

implementation

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
  if (d = nil) or (d.JSONType = jtNull) then Exit(ADefault);
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
function ResolveGridIndex(ANode: TJSONObject; AGridCount: Integer;
  const AGridIds: TTyStringArray): Integer;
var
  idx, i: Integer;
  id: string;
begin
  Result := -1;
  if AGridCount <= 0 then Exit;
  if HasKey(ANode, 'gridIndex') then
  begin
    idx := IntIn(ANode, 'gridIndex', -1);
    if (idx >= 0) and (idx < AGridCount) then Exit(idx);
    Exit(-1);
  end;
  id := StrIn(ANode, 'gridId', '');
  if id <> '' then
  begin
    for i := 0 to High(AGridIds) do
      if AGridIds[i] = id then Exit(i);
    Exit(-1);
  end;
  { Neither given: the first grid. }
  Result := 0;
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
        build.Note(Format('%s[%d].type: "%s" is not one of value, category, time or log; '
          + 'treated as value', [AMainType, q, u]));
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
    build.Note('xAxis or yAxis without the other: no grid was created, so neither is drawn');

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
      build.Note(Format('xAxis[%d] names no grid, so it is not drawn', [i]));
  for i := 0 to High(build.FYAxes) do
    if build.FYAxes[i].GridIndex < 0 then
      build.Note(Format('yAxis[%d] names no grid, so it is not drawn', [i]));

  { The N x M cross product. A grid missing either family gets NO coordinate
    system at all -- one orphaned axis takes the whole plot its partner was on
    with it, which is upstream's behaviour and the honest one: half a cartesian
    cannot place a datum. }
  for i := 0 to High(build.FGrids) do
  begin
    if (build.FGrids[i].XAxisCount = 0) or (build.FGrids[i].YAxisCount = 0) then
    begin
      if build.FGrids[i].XAxisCount + build.FGrids[i].YAxisCount > 0 then
        build.Note(Format('grid[%d] has axes in only one direction, so it draws nothing', [i]));
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

{ ==================== phase C ==================== }

procedure TyLayoutGrids(ABuild: TTyChartBuild; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
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
    ASpec.FontSizeLogical := 12;
    ASpec.FontWeight := 400;
    ASpec.LabelMarginLogical := 8;
    ASpec.TickLengthLogical := 5;
    ASpec.NameGapLogical := 15;
    ticks := AAxis.Scale.GetTicks;
    SetLength(ASpec.Labels, Length(ticks));
    SetLength(ASpec.Positions, Length(ticks));
    for q := 0 to High(ticks) do
    begin
      if AAxis.Scale is TTyOrdinalScale then
        ASpec.Labels[q] := TTyOrdinalScale(AAxis.Scale).GetLabel(ticks[q].Value)
      else
        ASpec.Labels[q] := FloatToStr(ticks[q].Value);
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
