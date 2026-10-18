unit tyControls.AdvChart.Chord;
{$mode objfpc}{$H+}
{ The chord series (new in ECharts 6): the nodes as sectors round a ring, the
  links as ribbons between them. [Batch 120, C11]

  THE GRAPH is createGraphFromNodeEdge's: `data || nodes` and `edges ||
  links` by JS truthiness; a node keyed by its id, else its name, else its
  index; a numeric link end an INDEX into the nodes, anything else a key; a
  link that misses either end dropped. A second node of one key makes
  upstream throw -- the series is refused here and draws nothing.

  THE LEGEND filters the NODES (dataFilter): a node switched off has no data
  index, and every link touching it goes with it (Graph.update). Indices are
  kept twice: by RAW node / link (the graph's own order) and by DATA index
  (what survived, in that order).

  THE LAYOUT is chordLayout.ts statement for statement, JavaScript's `|| 0`
  and `|| 1` included: a node's value is the larger of its own and the sum of
  its links' (a self loop counts twice); padAngle and minAngle each cut to fit
  when the turn is too small; the spans are one unit angle times the value;
  the deficit of the nodes under minAngle is either spread over every angle
  (the scale branch) or borrowed node by node in order; a link's two arcs
  start where the last link of each end stopped -- a NaN there restarts at 0.
  `endAngle` is never read: the layout always takes the whole turn.

  THE PIECES: a node is a Sector of getSectorCornerRadius' radii ([0, 0, 5, 5]
  by default), its label on the mid angle -- past the rim by `distance` or in
  the ring's middle -- in the node's own colour; a link is a path of two arcs
  on the inner circle and two cubics through the centre's direction (0.7 of
  the way), filled with the source's or the target's colour, a global linear
  gradient between them, or the prototype's '#000' (a literal colour only
  strokes).

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Labels,
  tyControls.AdvChart.ZrPath, tyControls.AdvChart.PolarBar;

const
  TyChordSeriesTypeName = 'chord';

type
  TTyChordNode = record
    { the data item as written (borrowed): an object, a primitive, nil }
    Item: TJSONData;
    Obj: TJSONObject;
    Key: string;
    { data.getName: the item's name as a string, '' without one }
    Name: string;
    { node.getValue('value'): NaN where there is none }
    DataValue: Double;
    { the legend kept it; its data index (-1: filtered) }
    Kept: Boolean;
    DataIndex: Integer;
    { node.edges: every link touching it, a self loop once, in link order }
    Edges: TTyIntegerArray;
    { THE LAYOUT, as node.getLayout() holds it }
    HasLayout: Boolean;
    Angle, Value, Ratio: Double;
    HasRatio: Boolean;
    StartAngle, EndAngle: Double;
    { the colour visual, set by the control: a solid (a string upstream:
      IsString), or a gradient object }
    HasColour, IsString: Boolean;
    Colour: TTyChartColor;
    HasGradient: Boolean;
    Gradient: TTyChartGradient;
    { the label, placed: device px, upstream's alignment }
    HasLabel: Boolean;
    LabelText: string;
    LabelX, LabelY: Double;
    LabelAH: TTyTextAnchorH;
    LabelAV: TTyTextAnchorV;
    LabelInside: Boolean;
  end;

  TTyChordEdge = record
    Item: TJSONObject;
    { the link's row in the option }
    Row: Integer;
    { raw node indices }
    Source, Target: Integer;
    { edge.getValue('value') }
    Value: Double;
    { the edge data's name: the link's id, else `source + ' > ' + target` }
    Name: string;
    Kept: Boolean;
    DataIndex: Integer;
    { THE LAYOUT, edge.getLayout() }
    HasLayout: Boolean;
    S1X, S1Y, S2X, S2Y, T1X, T1Y, T2X, T2Y: Double;
    SStart, SEnd, TStart, TEnd: Double;
    LayoutValue: Double;
  end;

  TTyChordSolved = record
    { the graph was built (no duplicate key) }
    Valid: Boolean;
    { the layout ran: some link, some value }
    Laid: Boolean;
    SeriesIndex: Integer;
    Series: TJSONObject;              // borrowed
    Z: Integer;
    { device px per CSS px }
    Scale: Double;
    CX, CY, R0, R: Double;
    Clockwise: Boolean;
    { the enter animation's origin: the centre option against the whole
      canvas (ChordView: parsePercent(center, api.getWidth())) }
    OriginX, OriginY: Double;
    { what the layout settled on, and which branches it took }
    PadAngle, MinAngle: Double;
    Scaled, AsMuch: Boolean;
    Nodes: array of TTyChordNode;
    Edges: array of TTyChordEdge;
    { data index -> raw index }
    NodeView, EdgeView: TTyIntegerArray;
  end;

  TTyChordInk = record
    Label_: TTyLabelSpec;
    { one per RAW node: item -> series }
    ItemLabels: TTyLabelSpecArray;
    { one per RAW node, its decal: the piece's sector useStyle's it, and an
      edge coloured 'source' / 'target' takes that node's [F4a] }
    NodeDecals: TTyChartDecalArray;
  end;

{ The graph and the layout. AKept: the legend's verdict per raw node (nil:
  every node kept); ACanvas the control's rect. }
function TyChordSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ACanvas: TTyRectF; APPI: Integer; const AKept: TTyBoolArray): TTyChordSolved; overload;
{ [Batch 151] coordinateSystemUsage 'box': getCircleLayout's viewRect is
  getLayoutRect of the series' box in ARef (createBoxLayoutReference's
  refContainer, a matrix cell or a calendar day); the group's origin stays
  the canvas' }
function TyChordSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ACanvas: TTyRectF; const ARef: TTyXYWH; APPI: Integer;
  const AKept: TTyBoolArray): TTyChordSolved; overload;
{ [Batch 154] coordinateSystemUsage 'box' on a host with only a dataToPoint
  (a cartesian, a geo): the centre is (APX, APY), the host's point of
  `coord`; the view rect -- the radii's reference -- is the canvas' }
function TyChordSolveAt(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ACanvas: TTyRectF; APX, APY: Double; APPI: Integer;
  const AKept: TTyBoolArray): TTyChordSolved;

{ the item -> series chain of a node / a link for one key of a block ('' the
  item itself): the first that writes it, null falling through }
function TyChordNodeFind(const S: TTyChordSolved; ARaw: Integer;
  const ASub, AKey: string): TJSONData;
function TyChordEdgeFind(const S: TTyChordSolved; ARaw: Integer;
  const ASub, AKey: string): TJSONData;

{ getSectorCornerRadius(itemStyle, layout, true): the list cornerRadius holds }
function TyChordCorners(const S: TTyChordSolved; ARaw: Integer): TTyDoubleArray;
{ the node's Sector as zrender builds it (roundSector), PathProxy's data }
function TyChordSectorPath(const S: TTyChordSolved; ARaw: Integer): TTyZrPath;
{ ChordEdge.buildPath, PathProxy's data }
function TyChordRibbonPath(const S: TTyChordSolved; ARaw: Integer): TTyZrPath;

{ One label spec per raw node: the item's label over the series'; the
  colour, when none is written, the node's own (inheritColor), as is the
  alignment the layout gives }
function TyChordLabelSpecs(const S: TTyChordSolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
{ The labels' words and places. ASeriesName: the model's name, the a of a
  template. }
procedure TyChordLabels(var S: TTyChordSolved; const ASeriesName: string);

{ The ribbons (z2 0) then -- by the view's own order, the sectors first --
  the nodes (z2 2) with their captions. }
function TyBuildChordMarks(ASeriesIndex: Integer; const S: TTyChordSolved;
  const AInk: TTyChordInk; AList: TTyPaintList): Integer;

{ THE FOCUS SETS of 'adjacency' (data/Graph.ts getAdjacentDataIndices): a
  node's every kept link and both its ends, a link itself and its two ends.
  ANodes are node DATA indices, AEdges RAW link indices (the state rows). }
procedure TyChordFocusSets(const S: TTyChordSolved; AIsEdge: Boolean;
  ARaw: Integer; out ANodes, AEdges: TTyIntegerArray);

{ A node's params.value: its raw value when it has one, else its layout's;
  AHas False when neither. AText: JS String() of it. }
function TyChordNodeValue(const S: TTyChordSolved; ARaw: Integer;
  out AValue: Double; out AText: string): Boolean;
{ A link's raw value: the option's `value` as written; AHas False without }
function TyChordEdgeRawValue(const S: TTyChordSolved; ARaw: Integer;
  out AValue: Double; out AText: string): Boolean;

{ PathProxy data drawn and hit: arcs as cubics, the outline sampled. }
procedure TyZrPathToCmds(const APath: TTyZrPath; out ACmds: TTyPathCmdArray;
  out APoints: TTyPointFArray);

implementation

uses tyControls.AdvChart.Scale, tyControls.AdvChart.Handlers,
  tyControls.AdvChart.JsMath, tyControls.AdvChart.Pie,
  tyControls.AdvChart.LabelOpt, tyControls.AdvChart.LabelGuide;

const
  cRadian = Pi / 180;
  cRibbonRatio = 0.7;
  cPI2 = Pi * 2;
  cE8: Double = 1e8;

{ ==================== small readers ==================== }

function ObjIn(ANode: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtObject) then Result := TJSONObject(d);
end;

function Present(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType <> jtNull);
end;

function JsNum(AData: TJSONData): Double;
begin
  Result := NaN;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNull: Result := 0;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtNumber: Result := AData.AsFloat;
    jtString: Result := TyJsToNumber(AData.AsString);
  end;
end;

function Truthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

{ parseDataValue: absent, null and '' are NaN, an array its first }
function NumOrNaN(AData: TJSONData): Double;
begin
  Result := NaN;
  if AData = nil then Exit;
  if AData.JSONType = jtArray then
  begin
    if AData.Count = 0 then Exit;
    AData := AData.Items[0];
  end;
  case AData.JSONType of
    jtNull: Result := NaN;
    jtString: if AData.AsString = '' then Result := NaN
              else Result := TyJsToNumber(AData.AsString);
  else
    Result := JsNum(AData);
  end;
end;

{ THE NODE'S VALUE DIMENSION, as createGraphFromNodeEdge builds the node
  data: on a cartesian2d, a polar or a matrix (createSeriesData) and on a
  geo (lng, lat) the dimensions are the coordinate system's and none is
  `value` -- node.getValue('value') reads nothing (-1); on a calendar (time,
  value) it is the row's second element (1); otherwise the first (0). A
  scalar value is every element. [D9-D14 mutation round] }
function NodeValueSlot(ASeries: TJSONObject): Integer;
var d: TJSONData;
begin
  Result := 0;
  if ASeries = nil then Exit;
  d := ASeries.Find('coordinateSystem');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  if (d.AsString = 'cartesian2d') or (d.AsString = 'polar')
    or (d.AsString = 'matrix') or (d.AsString = 'geo') then Result := -1
  else if d.AsString = 'calendar' then Result := 1;
end;

{ the value at that slot: nothing at -1, an array's element (NaN past its
  end), a scalar itself }
function NodeValueAt(AData: TJSONData; ASlot: Integer): Double;
begin
  Result := NaN;
  if (AData = nil) or (ASlot < 0) then Exit;
  if AData.JSONType = jtArray then
  begin
    if ASlot >= AData.Count then Exit;
    AData := AData.Items[ASlot];
  end;
  Result := NumOrNaN(AData);
end;

{ JS String(v) }
function JsStr(AData: TJSONData): string;
var k: Integer;
begin
  Result := '';
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtString: Result := AData.AsString;
    jtArray:
      for k := 0 to AData.Count - 1 do
      begin
        if k > 0 then Result := Result + ',';
        if not (AData.Items[k].JSONType = jtNull) then
          Result := Result + JsStr(AData.Items[k]);
      end;
  else
    Result := '[object Object]';
  end;
end;

{ Math.max / Math.min of two: a not-a-number wins }
function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

{ `x || 0` of a number: undefined, NaN and nought are nought }
function OrZero(AHas: Boolean; AV: Double): Double;
begin
  if (not AHas) or IsNan(AV) or (AV = 0) then Result := 0 else Result := AV;
end;

function Finite(const A: array of Double): Boolean;
var k: Integer;
begin
  Result := False;
  for k := 0 to High(A) do
    if IsNan(A[k]) or IsInfinite(A[k]) then Exit;
  Result := True;
end;

{ the chain item -> series: Model.get, a null falling through }
function ChainFind(AItem, ASeries: TJSONObject; const ASub, AKey: string): TJSONData;
var
  k: Integer;
  chain: array[0..1] of TJSONObject;
  o: TJSONObject;
  d: TJSONData;
begin
  Result := nil;
  chain[0] := AItem;
  chain[1] := ASeries;
  for k := 0 to 1 do
  begin
    if chain[k] = nil then Continue;
    if ASub <> '' then o := ObjIn(chain[k], ASub) else o := chain[k];
    if o = nil then Continue;
    d := o.Find(AKey);
    if Present(d) then Exit(d);
  end;
end;

function TyChordNodeFind(const S: TTyChordSolved; ARaw: Integer;
  const ASub, AKey: string): TJSONData;
begin
  Result := nil;
  if (ARaw < 0) or (ARaw > High(S.Nodes)) then Exit;
  Result := ChainFind(S.Nodes[ARaw].Obj, S.Series, ASub, AKey);
end;

function TyChordEdgeFind(const S: TTyChordSolved; ARaw: Integer;
  const ASub, AKey: string): TJSONData;
begin
  Result := nil;
  if (ARaw < 0) or (ARaw > High(S.Edges)) then Exit;
  Result := ChainFind(S.Edges[ARaw].Item, S.Series, ASub, AKey);
end;

{ PathProxy's modPI2 with JavaScript's own rounding and remainder: a
  start of minus nought stays minus nought (Math.round, %) }
function JsModPI2(ARadian: Double): Double;
begin
  { a nought of either sign comes back as it went in }
  if ARadian = 0 then Exit(ARadian);
  Result := TyJsFMod(TyJsRound(ARadian / Pi * cE8) / cE8, 2) * Pi;
end;

{ PathProxy.ts normalizeArcAngles, as chordLayout calls it }
procedure NormalizeArc(var AStart, AEnd: Double; AAnticlockwise: Boolean);
var s, e, delta: Double;
begin
  s := JsModPI2(AStart);
  if s < 0 then s := s + cPI2;
  delta := s - AStart;
  e := AEnd;
  e := e + delta;
  if (not AAnticlockwise) and (e - s >= cPI2) then e := s + cPI2
  else if AAnticlockwise and (s - e >= cPI2) then e := s - cPI2
  else if (not AAnticlockwise) and (s > e) then e := s + (cPI2 - JsModPI2(s - e))
  else if AAnticlockwise and (s < e) then e := s - (cPI2 - JsModPI2(e - s));
  AStart := s;
  AEnd := e;
end;

{ ==================== the graph and the layout ==================== }

function ChordSolveImpl(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ACanvas: TTyRectF; AHasRef: Boolean; const ARef: TTyXYWH; APPI: Integer;
  const AKept: TTyBoolArray; AHasPoint: Boolean; APX, APY: Double): TTyChordSolved; forward;

function TyChordSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ACanvas: TTyRectF; APPI: Integer; const AKept: TTyBoolArray): TTyChordSolved;
begin
  Result := ChordSolveImpl(AOption, ASeriesIndex, ACanvas, False,
    TyXYWH(NaN, NaN, NaN, NaN), APPI, AKept, False, NaN, NaN);
end;

function TyChordSolveAt(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ACanvas: TTyRectF; APX, APY: Double; APPI: Integer;
  const AKept: TTyBoolArray): TTyChordSolved;
begin
  Result := ChordSolveImpl(AOption, ASeriesIndex, ACanvas, False,
    TyXYWH(NaN, NaN, NaN, NaN), APPI, AKept, True, APX, APY);
end;

function TyChordSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ACanvas: TTyRectF; const ARef: TTyXYWH; APPI: Integer;
  const AKept: TTyBoolArray): TTyChordSolved;
begin
  Result := ChordSolveImpl(AOption, ASeriesIndex, ACanvas, True, ARef, APPI, AKept,
    False, NaN, NaN);
end;

function ChordSolveImpl(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ACanvas: TTyRectF; AHasRef: Boolean; const ARef: TTyXYWH; APPI: Integer;
  const AKept: TTyBoolArray; AHasPoint: Boolean; APX, APY: Double): TTyChordSolved;
var
  vx: TTyXYWH;
  node, arr, d: TJSONData;
  n, m, i, j, k, lo, a, b, rendered, nodeCount, slot: Integer;
  ends: array[0..1] of Integer;
  keys: TTyStringArray;
  spec: TTyPieSpec;
  view: TTyRectF;
  size, startA, endA, totalAngle, dir, padA, minA, unitAngle, nodeSum, edgeSum,
    sum, value, mul, span, deficit, surplus, surplusSpan, sc, sp, br, borrow,
    rest, angle, sS, sE, tS, tE, ratio, sSpan, tSpan, v: Double;
  allZero: Boolean;
  nv: TTyDoubleArray;
  nDef: TTyBoolArray;
  acc: TTyDoubleArray;
  mask: TFPUExceptionMask;
  W, H: Double;
  pn: ^TTyChordNode;
  pe: ^TTyChordEdge;

begin
  Result := Default(TTyChordSolved);
  Result.SeriesIndex := ASeriesIndex;
  if AOption = nil then Exit;
  node := AOption.ComponentAt('series', ASeriesIndex);
  if not (node is TJSONObject) then Exit;
  Result.Series := TJSONObject(node);
  if APPI > 0 then Result.Scale := APPI / 96 else Result.Scale := 1;
  Result.Z := 2;
  d := Result.Series.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Z := Round(d.AsFloat);

  { ---- the nodes: data || nodes ---- }
  slot := NodeValueSlot(Result.Series);
  arr := Result.Series.Find('data');
  if not Truthy(arr) then arr := Result.Series.Find('nodes');
  n := 0;
  if (arr <> nil) and (arr.JSONType = jtArray) then n := arr.Count;
  SetLength(Result.Nodes, n);
  SetLength(keys, n);
  for i := 0 to n - 1 do
  begin
    Result.Nodes[i] := Default(TTyChordNode);
    Result.Nodes[i].Item := arr.Items[i];
    if arr.Items[i] is TJSONObject then Result.Nodes[i].Obj := TJSONObject(arr.Items[i]);
    Result.Nodes[i].DataIndex := -1;
    { retrieve(id, name, index) }
    d := nil;
    if Result.Nodes[i].Obj <> nil then
    begin
      d := Result.Nodes[i].Obj.Find('id');
      if not Present(d) then d := Result.Nodes[i].Obj.Find('name');
      if not Present(d) then d := nil;
    end;
    if d <> nil then keys[i] := JsStr(d) else keys[i] := IntToStr(i);
    Result.Nodes[i].Key := keys[i];
    { a second node of a key: upstream throws }
    for j := 0 to i - 1 do
      if keys[j] = keys[i] then Exit;
    { the store's name }
    d := nil;
    if Result.Nodes[i].Obj <> nil then d := Result.Nodes[i].Obj.Find('name');
    if Present(d) then Result.Nodes[i].Name := JsStr(d);
    { the value dimension: the item's `value`, or the item itself -- at the
      slot the coordinate system's dimensions give it }
    if Result.Nodes[i].Obj <> nil then
      Result.Nodes[i].DataValue := NodeValueAt(Result.Nodes[i].Obj.Find('value'), slot)
    else
      Result.Nodes[i].DataValue := NodeValueAt(arr.Items[i], slot);
  end;

  { ---- the links: edges || links; Graph.addEdge's two lookups ---- }
  arr := Result.Series.Find('edges');
  if not Truthy(arr) then arr := Result.Series.Find('links');
  m := 0;
  if (arr <> nil) and (arr.JSONType = jtArray) then
    for i := 0 to arr.Count - 1 do
    begin
      if not (arr.Items[i] is TJSONObject) then Continue;
      for k := 0 to 1 do
      begin
        if k = 0 then d := TJSONObject(arr.Items[i]).Find('source')
        else d := TJSONObject(arr.Items[i]).Find('target');
        lo := -1;
        { a number is graph.nodes[n] -- else (undefined) the key 'undefined' }
        if (d <> nil) and (d.JSONType = jtNumber) and (Frac(d.AsFloat) = 0)
          and (d.AsFloat >= 0) and (d.AsFloat < n) then
          lo := Trunc(d.AsFloat)
        else
        begin
          if (d <> nil) and (d.JSONType = jtNumber) then d := nil;
          for j := 0 to n - 1 do
            if keys[j] = JsStr(d) then
            begin
              lo := j;
              Break;
            end;
        end;
        ends[k] := lo;
      end;
      if (ends[0] < 0) or (ends[1] < 0) then Continue;
      SetLength(Result.Edges, m + 1);
      Result.Edges[m] := Default(TTyChordEdge);
      Result.Edges[m].Item := TJSONObject(arr.Items[i]);
      Result.Edges[m].Row := i;
      Result.Edges[m].Source := ends[0];
      Result.Edges[m].Target := ends[1];
      Result.Edges[m].DataIndex := -1;
      Result.Edges[m].Value := NumOrNaN(TJSONObject(arr.Items[i]).Find('value'));
      d := TJSONObject(arr.Items[i]).Find('id');
      if Present(d) then Result.Edges[m].Name := JsStr(d)
      else
        Result.Edges[m].Name := JsStr(TJSONObject(arr.Items[i]).Find('source'))
          + ' > ' + JsStr(TJSONObject(arr.Items[i]).Find('target'));
      pn := @Result.Nodes[ends[0]];
      SetLength(pn^.Edges, Length(pn^.Edges) + 1);
      pn^.Edges[High(pn^.Edges)] := m;
      if ends[1] <> ends[0] then
      begin
        pn := @Result.Nodes[ends[1]];
        SetLength(pn^.Edges, Length(pn^.Edges) + 1);
        pn^.Edges[High(pn^.Edges)] := m;
      end;
      Inc(m);
    end;
  Result.Valid := True;

  { ---- Graph.update: the kept nodes, then the links between them ---- }
  nodeCount := 0;
  for i := 0 to n - 1 do
  begin
    Result.Nodes[i].Kept := (AKept = nil) or ((i <= High(AKept)) and AKept[i]);
    if not Result.Nodes[i].Kept then Continue;
    Result.Nodes[i].DataIndex := nodeCount;
    SetLength(Result.NodeView, nodeCount + 1);
    Result.NodeView[nodeCount] := i;
    Inc(nodeCount);
  end;
  k := 0;
  for i := 0 to m - 1 do
  begin
    Result.Edges[i].Kept := Result.Nodes[Result.Edges[i].Source].Kept
      and Result.Nodes[Result.Edges[i].Target].Kept;
    if not Result.Edges[i].Kept then Continue;
    Result.Edges[i].DataIndex := k;
    SetLength(Result.EdgeView, k + 1);
    Result.EdgeView[k] := i;
    Inc(k);
  end;

  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    { ---- getCircleLayout: the box, the centre and the radii ---- }
    spec := TyPieSpecOf(AOption, ASeriesIndex);
    d := Result.Series.Find('radius');
    if not Present(d) then
    begin
      spec.Radius0 := TyBoxPercent(70);
      spec.Radius1 := TyBoxPercent(80);
    end;
    if AHasRef then
    begin
      { in the refContainer, by getLayoutRect on the raw box [Batch 151] }
      vx := TyGetLayoutRect(TyBoxSpecRaw(spec.Box), ARef.X, ARef.Y, ARef.W, ARef.H, []);
      Result.CX := TyPieResolve(spec.CentreX, vx.W) + vx.X;
      Result.CY := TyPieResolve(spec.CentreY, vx.H) + vx.Y;
      size := Math.Min(vx.W, vx.H);
    end
    else
    begin
      view := TySolveBox(spec.Box, TyFixedContainer(ACanvas));
      Result.CX := TyPieResolve(spec.CentreX, TyRectFWidth(view)) + view.Left;
      Result.CY := TyPieResolve(spec.CentreY, TyRectFHeight(view)) + view.Top;
      size := Math.Min(TyRectFWidth(view), TyRectFHeight(view));
      { the host's point of the coord [Batch 154] }
      if AHasPoint then
      begin
        Result.CX := APX;
        Result.CY := APY;
      end;
    end;
    Result.R0 := TyPieResolve(spec.Radius0, size / 2);
    Result.R := TyPieResolve(spec.Radius1, size / 2);
    W := ACanvas.Right - ACanvas.Left;
    H := ACanvas.Bottom - ACanvas.Top;
    Result.OriginX := TyPieResolve(spec.CentreX, W);
    Result.OriginY := TyPieResolve(spec.CentreY, H);

    { ---- chordLayout ---- }
    if k = 0 then Exit;
    d := Result.Series.Find('padAngle');
    if not Present(d) then v := 3 else v := JsNum(d);
    if IsNan(v) or (v = 0) then v := 0;
    padA := JsMax(v * cRadian, 0);
    d := Result.Series.Find('minAngle');
    if not Present(d) then v := 0 else v := JsNum(d);
    if IsNan(v) or (v = 0) then v := 0;
    minA := JsMax(v * cRadian, 0);
    d := Result.Series.Find('startAngle');
    if not Present(d) then v := 90 else v := JsNum(d);
    { `-startAngle * RADIAN`: (-v) * RADIAN, minus nought for a nought }
    startA := v * (-cRadian);
    endA := startA + cPI2;
    d := Result.Series.Find('clockwise');
    Result.Clockwise := (not Present(d)) or Truthy(d);
    if Result.Clockwise then dir := 1 else dir := -1;
    NormalizeArc(startA, endA, not Result.Clockwise);
    totalAngle := endA - startA;

    { getSum('value') of both data, NaN left out }
    nodeSum := 0;
    for i := 0 to n - 1 do
      if Result.Nodes[i].Kept and not IsNan(Result.Nodes[i].DataValue) then
        nodeSum := nodeSum + Result.Nodes[i].DataValue;
    edgeSum := 0;
    for i := 0 to m - 1 do
      if Result.Edges[i].Kept and not IsNan(Result.Edges[i].Value) then
        edgeSum := edgeSum + Result.Edges[i].Value;
    allZero := (nodeSum = 0) and (edgeSum = 0);

    { the node values, by data index: `(nodeValues[i] || 0) + value` }
    SetLength(nv, nodeCount);
    SetLength(nDef, nodeCount);
    rendered := 0;
    for i := 0 to m - 1 do
    begin
      if not Result.Edges[i].Kept then Continue;
      if allZero then value := 1 else value := Result.Edges[i].Value;
      if allZero and ((value > 0) or (minA <> 0)) then Inc(rendered, 2);
      a := Result.Nodes[Result.Edges[i].Source].DataIndex;
      b := Result.Nodes[Result.Edges[i].Target].DataIndex;
      nv[a] := OrZero(nDef[a], nv[a]) + value;
      nDef[a] := True;
      nv[b] := OrZero(nDef[b], nv[b]) + value;
      nDef[b] := True;
    end;
    sum := 0;
    for j := 0 to nodeCount - 1 do
    begin
      i := Result.NodeView[j];
      v := Result.Nodes[i].DataValue;
      if not IsNan(v) then
      begin
        nv[j] := JsMax(v, OrZero(nDef[j], nv[j]));
        nDef[j] := True;
      end;
      if (not allZero) and ((nDef[j] and (nv[j] > 0)) or (minA <> 0)) then Inc(rendered);
      sum := sum + OrZero(nDef[j], nv[j]);
    end;
    if (rendered = 0) or (sum = 0) then Exit;
    if padA * rendered >= Abs(totalAngle) then
      padA := JsMax(0, (Abs(totalAngle) - minA * rendered) / rendered);
    if (padA + minA) * rendered >= Abs(totalAngle) then
      minA := (Abs(totalAngle) - padA * rendered) / rendered;
    Result.PadAngle := padA;
    Result.MinAngle := minA;
    unitAngle := (totalAngle - padA * rendered * dir) / sum;

    { the spans, the deficit and the surplus }
    deficit := 0;
    surplus := 0;
    surplusSpan := 0;
    for j := 0 to nodeCount - 1 do
    begin
      i := Result.NodeView[j];
      value := OrZero(nDef[j], nv[j]);
      if sum <> 0 then mul := value else mul := 1;
      span := unitAngle * mul * dir;
      if Abs(span) < minA then deficit := deficit + (minA - Abs(span))
      else
      begin
        surplus := surplus + (Abs(span) - minA);
        surplusSpan := surplusSpan + Abs(span);
      end;
      Result.Nodes[i].HasLayout := True;
      Result.Nodes[i].Angle := span;
      Result.Nodes[i].Value := value;
      Result.Nodes[i].HasRatio := False;
    end;
    if deficit > surplus then
    begin
      { not enough to spread: every angle scaled }
      Result.Scaled := True;
      sc := deficit / surplus;
      for j := 0 to nodeCount - 1 do
      begin
        pn := @Result.Nodes[Result.NodeView[j]];
        sp := pn^.Angle;
        pn^.HasRatio := True;
        if Abs(sp) >= minA then
        begin
          pn^.Angle := sp * sc;
          pn^.Ratio := sc;
        end
        else
        begin
          pn^.Angle := minA;
          if minA = 0 then pn^.Ratio := 1 else pn^.Ratio := sp / minA;
        end;
      end;
    end
    else
      for j := 0 to nodeCount - 1 do
      begin
        if Result.AsMuch then Break;
        sp := Result.Nodes[Result.NodeView[j]].Angle;
        br := JsMin(sp / surplusSpan, 1);
        borrow := br * deficit;
        if sp - borrow < minA then Result.AsMuch := True;
      end;
    { the borrowing, node by node, until the deficit is met }
    rest := deficit;
    for j := 0 to nodeCount - 1 do
    begin
      if rest <= 0 then Continue;
      pn := @Result.Nodes[Result.NodeView[j]];
      sp := pn^.Angle;
      if (sp > minA) and (minA > 0) then
      begin
        if Result.AsMuch then br := 1 else br := JsMin(sp / surplusSpan, 1);
        borrow := JsMin(sp - minA, JsMin(rest, deficit * br));
        rest := rest - borrow;
        pn^.Angle := sp - borrow;
        pn^.Ratio := (sp - borrow) / sp;
        pn^.HasRatio := True;
      end
      else if minA > 0 then
      begin
        pn^.Angle := minA;
        if sp = 0 then pn^.Ratio := 1 else pn^.Ratio := minA / sp;
        pn^.HasRatio := True;
      end;
    end;
    { the sectors, one after another }
    angle := startA;
    SetLength(acc, nodeCount);
    for j := 0 to nodeCount - 1 do
    begin
      pn := @Result.Nodes[Result.NodeView[j]];
      span := JsMax(pn^.Angle, minA);
      pn^.StartAngle := angle;
      pn^.EndAngle := angle + span * dir;
      acc[j] := angle;
      angle := angle + (span + padA) * dir;
    end;
    { the links: each end where that node's last link stopped }
    for i := 0 to m - 1 do
    begin
      if not Result.Edges[i].Kept then Continue;
      pe := @Result.Edges[i];
      if allZero then value := 1 else value := pe^.Value;
      if sum <> 0 then mul := value else mul := 1;
      span := unitAngle * mul * dir;
      a := Result.Nodes[pe^.Source].DataIndex;
      sS := OrZero(True, acc[a]);
      ratio := OrZero(Result.Nodes[pe^.Source].HasRatio, Result.Nodes[pe^.Source].Ratio);
      if ratio = 0 then ratio := 1;
      sSpan := Abs(ratio * span);
      sE := sS + sSpan * dir;
      b := Result.Nodes[pe^.Target].DataIndex;
      tS := OrZero(True, acc[b]);
      ratio := OrZero(Result.Nodes[pe^.Target].HasRatio, Result.Nodes[pe^.Target].Ratio);
      if ratio = 0 then ratio := 1;
      tSpan := Abs(ratio * span);
      tE := tS + tSpan * dir;
      pe^.S1X := Result.CX + Result.R0 * TyJsCos(sS);
      pe^.S1Y := Result.CY + Result.R0 * TyJsSin(sS);
      pe^.S2X := Result.CX + Result.R0 * TyJsCos(sE);
      pe^.S2Y := Result.CY + Result.R0 * TyJsSin(sE);
      pe^.T1X := Result.CX + Result.R0 * TyJsCos(tS);
      pe^.T1Y := Result.CY + Result.R0 * TyJsSin(tS);
      pe^.T2X := Result.CX + Result.R0 * TyJsCos(tE);
      pe^.T2Y := Result.CY + Result.R0 * TyJsSin(tE);
      pe^.SStart := sS;
      pe^.SEnd := sE;
      pe^.TStart := tS;
      pe^.TEnd := tE;
      pe^.LayoutValue := value;
      pe^.HasLayout := True;
      acc[a] := sE;
      acc[b] := tE;
    end;
    Result.Laid := True;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the pieces ==================== }

function NodeSector(const S: TTyChordSolved; ARaw: Integer): TTyPolarSector;
begin
  Result.CX := S.CX;
  Result.CY := S.CY;
  Result.R0 := S.R0;
  Result.R := S.R;
  Result.SA := S.Nodes[ARaw].StartAngle;
  Result.EA := S.Nodes[ARaw].EndAngle;
  Result.CW := S.Clockwise;
end;

function TyChordCorners(const S: TTyChordSolved; ARaw: Integer): TTyDoubleArray;
var
  d: TJSONData;
  spec: TTyPolarCornerSpec;
  dflt: TJSONArray;
begin
  { item -> series -> the type's [0, 0, 5, 5] }
  d := TyChordNodeFind(S, ARaw, 'itemStyle', 'borderRadius');
  if d <> nil then
    spec := TyPolarCornerSpecOf(d)
  else
  begin
    dflt := TJSONArray.Create([0, 0, 5, 5]);
    try
      spec := TyPolarCornerSpecOf(dflt);
    finally
      dflt.Free;
    end;
  end;
  Result := TyPolarCornerList(spec, NodeSector(S, ARaw));
end;

function TyChordSectorPath(const S: TTyChordSolved; ARaw: Integer): TTyZrPath;
begin
  Result := TyZrSectorPath(NodeSector(S, ARaw), TyChordCorners(S, ARaw));
end;

function TyChordRibbonPath(const S: TTyChordSolved; ARaw: Integer): TTyZrPath;
var
  e: TTyChordEdge;
  mask: TFPUExceptionMask;
begin
  Result := nil;
  e := S.Edges[ARaw];
  { a link of no value carries NaN to its end }
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
  TyZrMoveTo(Result, e.S1X, e.S1Y);
  TyZrArc(Result, S.CX, S.CY, S.R0, e.SStart, e.SEnd, not S.Clockwise);
  TyZrCubic(Result,
    (S.CX - e.S2X) * cRibbonRatio + e.S2X, (S.CY - e.S2Y) * cRibbonRatio + e.S2Y,
    (S.CX - e.T1X) * cRibbonRatio + e.T1X, (S.CY - e.T1Y) * cRibbonRatio + e.T1Y,
    e.T1X, e.T1Y);
  TyZrArc(Result, S.CX, S.CY, S.R0, e.TStart, e.TEnd, not S.Clockwise);
  TyZrCubic(Result,
    (S.CX - e.T2X) * cRibbonRatio + e.T2X, (S.CY - e.T2Y) * cRibbonRatio + e.T2Y,
    (S.CX - e.S1X) * cRibbonRatio + e.S1X, (S.CY - e.S1Y) * cRibbonRatio + e.S1Y,
    e.S1X, e.S1Y);
  TyZrClose(Result);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

procedure TyZrPathToCmds(const APath: TTyZrPath; out ACmds: TTyPathCmdArray;
  out APoints: TTyPointFArray);
var
  i, k, n, steps: Integer;
  cx, cy, r, a0, sweep, th, kk, p0, p1, c0, s0, c1, s1, t, u, px, py,
    lastX, lastY: Double;

  procedure Cmd(AKind: TTyPathCmdKind; AX1, AY1, AX2, AY2, AX, AY: Double);
  var q: Integer;
  begin
    q := Length(ACmds);
    SetLength(ACmds, q + 1);
    ACmds[q] := Default(TTyPathCmd);
    ACmds[q].Kind := AKind;
    ACmds[q].X1 := AX1;
    ACmds[q].Y1 := AY1;
    ACmds[q].X2 := AX2;
    ACmds[q].Y2 := AY2;
    ACmds[q].X := AX;
    ACmds[q].Y := AY;
  end;

  procedure Pt(AX, AY: Double);
  var q: Integer;
  begin
    q := Length(APoints);
    SetLength(APoints, q + 1);
    APoints[q] := TyPointF(AX, AY);
  end;

begin
  ACmds := nil;
  APoints := nil;
  lastX := 0;
  lastY := 0;
  for i := 0 to High(APath) do
    case APath[i].Cmd of
      zrM:
        begin
          Cmd(pckMove, 0, 0, 0, 0, APath[i].V[0], APath[i].V[1]);
          lastX := APath[i].V[0];
          lastY := APath[i].V[1];
          Pt(lastX, lastY);
        end;
      zrL:
        begin
          Cmd(pckLine, 0, 0, 0, 0, APath[i].V[0], APath[i].V[1]);
          lastX := APath[i].V[0];
          lastY := APath[i].V[1];
          Pt(lastX, lastY);
        end;
      zrC:
        begin
          Cmd(pckCurve, APath[i].V[0], APath[i].V[1], APath[i].V[2], APath[i].V[3],
            APath[i].V[4], APath[i].V[5]);
          for k := 1 to 24 do
          begin
            t := k / 24;
            u := 1 - t;
            px := u * u * u * lastX + 3 * u * u * t * APath[i].V[0]
              + 3 * u * t * t * APath[i].V[2] + t * t * t * APath[i].V[4];
            py := u * u * u * lastY + 3 * u * u * t * APath[i].V[1]
              + 3 * u * t * t * APath[i].V[3] + t * t * t * APath[i].V[5];
            Pt(px, py);
          end;
          lastX := APath[i].V[4];
          lastY := APath[i].V[5];
        end;
      zrA:
        begin
          { canvas' arc: a line to its start, then the sweep -- as cubics
            of at most a quarter turn each }
          cx := APath[i].V[0];
          cy := APath[i].V[1];
          r := APath[i].V[2];
          a0 := APath[i].V[4];
          sweep := APath[i].V[5];
          Cmd(pckLine, 0, 0, 0, 0, cx + r * Cos(a0), cy + r * Sin(a0));
          n := Ceil(Abs(sweep) / (Pi / 2) - 1e-9);
          if n < 1 then n := 1;
          th := sweep / n;
          kk := 4 / 3 * Tan(th / 4);
          for k := 0 to n - 1 do
          begin
            p0 := a0 + th * k;
            p1 := a0 + th * (k + 1);
            c0 := Cos(p0);
            s0 := Sin(p0);
            c1 := Cos(p1);
            s1 := Sin(p1);
            Cmd(pckCurve, cx + r * (c0 - kk * s0), cy + r * (s0 + kk * c0),
              cx + r * (c1 + kk * s1), cy + r * (s1 - kk * c1),
              cx + r * c1, cy + r * s1);
          end;
          steps := Ceil(Abs(sweep) * 24);
          if steps < 4 then steps := 4;
          for k := 0 to steps do
            Pt(cx + r * Cos(a0 + sweep * k / steps), cy + r * Sin(a0 + sweep * k / steps));
          lastX := cx + r * Cos(a0 + sweep);
          lastY := cy + r * Sin(a0 + sweep);
        end;
      zrZ:
        Cmd(pckClose, 0, 0, 0, 0, 0, 0);
    end;
end;

{ ==================== labels ==================== }

function TyChordLabelSpecs(const S: TTyChordSolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
var
  i: Integer;
  base: TTyLabelSpec;
begin
  Result := nil;
  SetLength(Result, Length(S.Nodes));
  for i := 0 to High(S.Nodes) do
  begin
    base := ASeriesSpec;
    if S.Nodes[i].Obj <> nil then
      base := TyLabelSpecOfNode(ObjIn(S.Nodes[i].Obj, 'label'), S.Series, base);
    { inheritColor is the node's fill, and setTextStyleCommon sets it on a
      label that is not set on its text: a label written no colour wears its
      node's (an outside one with no halo, the fill being its own) }
    if base.AutoColour then
    begin
      base.AutoColour := False;
      base.InheritColour := True;
    end;
    { the piece places the words itself: textConfig is replaced whole, so
      neither an offset nor a turn survives }
    base.Position := tlpInside;
    base.OffsetXLogical := 0;
    base.OffsetYLogical := 0;
    base.RotationRad := 0;
    base.Overflow := tloNone;
    Result[i] := base;
  end;
end;

function AlignH(const AWord: string): TTyTextAnchorH;
begin
  if (AWord = 'center') or (AWord = 'middle') then Result := tahCentre
  else if AWord = 'right' then Result := tahRight
  else Result := tahLeft;
end;

function AlignV(const AWord: string): TTyTextAnchorV;
begin
  if (AWord = 'middle') or (AWord = 'center') then Result := tavMiddle
  else if AWord = 'bottom' then Result := tavBottom
  else Result := tavTop;
end;

function TyChordNodeValue(const S: TTyChordSolved; ARaw: Integer;
  out AValue: Double; out AText: string): Boolean;
var d: TJSONData;
begin
  AValue := NaN;
  AText := '';
  Result := False;
  if (ARaw < 0) or (ARaw > High(S.Nodes)) then Exit;
  { getRawValue: the item's `value`, or a primitive item itself }
  if S.Nodes[ARaw].Obj <> nil then d := S.Nodes[ARaw].Obj.Find('value')
  else d := S.Nodes[ARaw].Item;
  if Present(d) then
  begin
    AValue := NumOrNaN(d);
    AText := JsStr(d);
    Exit(True);
  end;
  { `params.value == null`: the layout's }
  if not S.Nodes[ARaw].HasLayout then Exit;
  AValue := S.Nodes[ARaw].Value;
  AText := TyJsNumberToString(AValue);
  Result := True;
end;

function TyChordEdgeRawValue(const S: TTyChordSolved; ARaw: Integer;
  out AValue: Double; out AText: string): Boolean;
var d: TJSONData;
begin
  AValue := NaN;
  AText := '';
  Result := False;
  if (ARaw < 0) or (ARaw > High(S.Edges)) then Exit;
  d := S.Edges[ARaw].Item.Find('value');
  if not Present(d) then Exit;
  AValue := NumOrNaN(d);
  AText := JsStr(d);
  Result := True;
end;

procedure TyChordLabels(var S: TTyChordSolved; const ASeriesName: string);
var
  i: Integer;
  d, fmt, pos: TJSONData;
  text, w, valueText: string;
  mid, dx, dy, rr, dist, v: Double;
  vars: array of TTyStringArray;
  prm: TTyChartCallbackParams;
  mask: TFPUExceptionMask;
  isOutside: Boolean;
begin
  if not S.Valid then Exit;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    for i := 0 to High(S.Nodes) do
    begin
      S.Nodes[i].HasLabel := False;
      if not (S.Nodes[i].Kept and S.Nodes[i].HasLayout) then Continue;
      { EVERY NODE HAS ITS TEXT: `label.ignore = !show` hides it at rest, and
        a state that shows the label shows it -- the spec's Show and
        StateShow decide, in the label pass }
      { THE WORDS: retrieve3(the normal formatter, the normal formatter, the
        item model's `name`) -- which climbs to the SERIES' name for a node
        with none (Model.get) -- through getFormattedLabel: a string is a
        template over the node's params, anything else none, and none is the
        data index }
      fmt := TyChordNodeFind(S, i, 'label', 'formatter');
      if fmt = nil then
      begin
        if S.Nodes[i].Obj <> nil then fmt := S.Nodes[i].Obj.Find('name');
        if not Present(fmt) then fmt := S.Series.Find('name');
        if not Present(fmt) then fmt := nil;
      end;
      TyChordNodeValue(S, i, v, valueText);
      text := IntToStr(S.Nodes[i].DataIndex);
      if (fmt <> nil) and (fmt.JSONType = jtString) and TyChartIsHandlerRef(fmt.AsString) then
      begin
        prm := TyChartBlankParams;
        prm.ComponentType := 'series';
        prm.SeriesType := TyChordSeriesTypeName;
        prm.SeriesIndex := S.SeriesIndex;
        prm.SeriesName := ASeriesName;
        prm.DataType := 'node';
        prm.Status := 'normal';
        prm.DataIndex := S.Nodes[i].DataIndex;
        prm.RawDataIndex := i;
        prm.Name := S.Nodes[i].Name;
        prm.ValueText := valueText;
        SetLength(prm.Values, 1);
        prm.Values[0] := v;
        text := TyChartRunHandler(fmt.AsString, TyChartOneParams(prm));
      end
      else if (fmt <> nil) and (fmt.JSONType = jtString) then
      begin
        vars := nil;
        SetLength(vars, 1);
        SetLength(vars[0], 3);
        vars[0][0] := ASeriesName;
        vars[0][1] := S.Nodes[i].Name;
        vars[0][2] := valueText;
        text := TyJsFormatTpl(fmt.AsString, 3, vars);
      end;
      { THE PLACE: on the mid angle, past the rim by `distance || 0` or in
        the ring's middle }
      pos := TyChordNodeFind(S, i, 'label', 'position');
      if Truthy(pos) then w := JsStr(pos) else w := 'outside';
      isOutside := w = 'outside';
      d := TyChordNodeFind(S, i, 'label', 'distance');
      if d = nil then dist := 5 else dist := JsNum(d);
      if IsNan(dist) then dist := 0;
      dist := dist * S.Scale;
      mid := (S.Nodes[i].StartAngle + S.Nodes[i].EndAngle) / 2;
      dx := TyJsCos(mid);
      dy := TyJsSin(mid);
      if isOutside then rr := S.R + dist
      else rr := (S.R + S.R0) / 2;
      S.Nodes[i].LabelInside := not isOutside;
      if isOutside then
      begin
        if dx > 0 then S.Nodes[i].LabelAH := tahLeft else S.Nodes[i].LabelAH := tahRight;
        if dy > 0 then S.Nodes[i].LabelAV := tavTop else S.Nodes[i].LabelAV := tavBottom;
      end
      else
      begin
        d := TyChordNodeFind(S, i, 'label', 'align');
        if Truthy(d) then S.Nodes[i].LabelAH := AlignH(JsStr(d))
        else S.Nodes[i].LabelAH := tahCentre;
        d := TyChordNodeFind(S, i, 'label', 'verticalAlign');
        if Truthy(d) then S.Nodes[i].LabelAV := AlignV(JsStr(d))
        else S.Nodes[i].LabelAV := tavMiddle;
      end;
      S.Nodes[i].LabelX := dx * rr + S.CX;
      S.Nodes[i].LabelY := dy * rr + S.CY;
      S.Nodes[i].LabelText := text;
      S.Nodes[i].HasLabel := text <> '';
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the marks ==================== }

function TyBuildChordMarks(ASeriesIndex: Integer; const S: TTyChordSolved;
  const AInk: TTyChordInk; AList: TTyPaintList): Integer;
var
  i, j: Integer;
  el: TTyChartElement;
  shape: TTyChartShape;
  path: TTyZrPath;
  cmds: TTyPathCmdArray;
  pts: TTyPointFArray;
  d: TJSONData;
  w: string;
  box: TTyXYWH;
  c: TTyChartColor;
  lw: Double;
  mask: TFPUExceptionMask;
  n1, n2, nd: Integer;
  noInk: Boolean;
  sec: TTyPolarSector;

  procedure Tag(var AEl: TTyChartElement);
  begin
    { the view group's enter scale [Batch 120] }
    AEl.Anim.Role := carChord;
    AEl.Anim.Series := ASeriesIndex;
    AEl.Anim.Index := -1;
    AEl.Anim.G[0] := S.OriginX;
    AEl.Anim.G[1] := S.OriginY;
  end;

begin
  Result := 0;
  if (AList = nil) or not S.Valid or not S.Laid then Exit;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    { ---- the nodes: one Sector each, in data order ---- }
    for j := 0 to High(S.NodeView) do
    begin
      i := S.NodeView[j];
      if not S.Nodes[i].HasLayout then Continue;
      { NaN data: no element upstream draws or styles }
      if not Finite([S.Nodes[i].StartAngle, S.Nodes[i].EndAngle, S.CX, S.CY, S.R0, S.R]) then
        Continue;
      el := TyChartElement(TyPolarSectorShape(NodeSector(S, i), TyChordCorners(S, i), False));
      el.Style.HasFill := S.Nodes[i].HasColour;
      el.Style.FillColor := S.Nodes[i].Colour;
      if S.Nodes[i].HasGradient then
      begin
        el.Style.FillGradient := S.Nodes[i].Gradient;
        box := TyZrBBox(TyChordSectorPath(S, i));
        el.Style.GradBoxSet := True;
        el.Style.GradBox := box;
      end;
      { getItemStyle: borderColor the stroke, borderWidth its width --
        zrender's 1 where none is written }
      d := TyChordNodeFind(S, i, 'itemStyle', 'borderColor');
      if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
      begin
        d := TyChordNodeFind(S, i, 'itemStyle', 'borderWidth');
        if d = nil then lw := 1 else lw := JsNum(d);
        if lw > 0 then
        begin
          el.Style.StrokeColor := c;
          el.Style.StrokeWidthLogical := lw;
        end;
      end;
      d := TyChordNodeFind(S, i, 'itemStyle', 'opacity');
      if d <> nil then el.Style.Alpha := JsNum(d) else el.Style.Alpha := 1;
      if i <= High(AInk.NodeDecals) then el.Style.Decal := AInk.NodeDecals[i];
      el.Z := S.Z;
      el.Z2 := 2;
      el.Datum := TyChartDatum(ASeriesIndex, S.Nodes[i].DataIndex, i);
      el.Silent := False;
      Tag(el);
      { [F3c] the piece's Sector for the universal transition (the view
        group's transform an identity once its scale has run -- upstream keeps
        that identity matrix or none, by the group's history: the same
        numbers either way) }
      el.Anim.UtTag := 1;
      el.Anim.UtRow := S.Nodes[i].DataIndex;
      el.Anim.UtOrder := 0;
      el.Anim.UtData := TyGuidePathData(TyChordSectorPath(S, i));
      sec := NodeSector(S, i);
      el.Anim.UtBase := TTyDoubleArray.Create(2, sec.CX, sec.CY, sec.R0, sec.R, sec.SA,
        sec.EA, Ord(sec.CW));
      if S.Nodes[i].HasLabel and Finite([S.Nodes[i].LabelX, S.Nodes[i].LabelY]) then
      begin
        el.Caption.Text := S.Nodes[i].LabelText;
        el.Caption.ItemSpec := i + 1;
        el.Caption.HasFixedAnchor := True;
        el.Caption.FixedX := S.Nodes[i].LabelX;
        el.Caption.FixedY := S.Nodes[i].LabelY;
        el.Caption.FixedInside := S.Nodes[i].LabelInside;
        el.Caption.FixedAH := S.Nodes[i].LabelAH;
        el.Caption.FixedAV := S.Nodes[i].LabelAV;
        el.Caption.FixedRotationRad := 0;
        el.Caption.HasFixedZ2 := True;
        el.Caption.FixedZ2 := 4;
      end;
      AList.Add(el);
      Inc(Result);
    end;
    { ---- the links ---- }
    for j := 0 to High(S.EdgeView) do
    begin
      i := S.EdgeView[j];
      if not S.Edges[i].HasLayout then Continue;
      { A LINK WITH NO VALUE has a start and no end: upstream builds and
        styles it, keeps its states, and draws nothing of its NaN path --
        an element of no outline here }
      noInk := not Finite([S.Edges[i].S1X, S.Edges[i].S1Y, S.Edges[i].S2X, S.Edges[i].S2Y,
        S.Edges[i].T1X, S.Edges[i].T1Y, S.Edges[i].T2X, S.Edges[i].T2Y,
        S.Edges[i].SStart, S.Edges[i].SEnd, S.Edges[i].TStart, S.Edges[i].TEnd]);
      if noInk and (IsNan(S.Edges[i].SStart) or IsNan(S.Edges[i].TStart)) then Continue;
      n1 := S.Edges[i].Source;
      n2 := S.Edges[i].Target;
      path := TyChordRibbonPath(S, i);
      if noInk then
      begin
        shape := TyShapePolygon([]);
        box := Default(TTyXYWH);
      end
      else
      begin
        TyZrPathToCmds(path, cmds, pts);
        shape := TyShapePolygon(pts);
        shape.Cmds := cmds;
        box := TyZrBBox(path);
        shape.HasCmdBounds := True;
        shape.CmdBounds := TyRectF(box.X, box.Y, box.X + box.W, box.Y + box.H);
      end;
      shape.HitNonZero := True;
      el := TyChartElement(shape);
      { THE FILL: the prototype's '#000' unless the colour word names a node
        (applyEdgeFill) }
      el.Style.HasFill := True;
      el.Style.FillColor := $FF000000;
      d := TyChordEdgeFind(S, i, 'lineStyle', 'color');
      if d = nil then w := 'source'
      else if d.JSONType = jtString then w := d.AsString
      else w := '';
      if (w = 'source') or (w = 'target') then
      begin
        if w = 'source' then nd := n1 else nd := n2;
        { edgeStyle.decal = that node's style decal [F4a] }
        if nd <= High(AInk.NodeDecals) then el.Style.Decal := AInk.NodeDecals[nd];
        el.Style.HasFill := S.Nodes[nd].HasColour;
        el.Style.FillColor := S.Nodes[nd].Colour;
        if S.Nodes[nd].HasGradient then
        begin
          el.Style.FillGradient := S.Nodes[nd].Gradient;
          el.Style.GradBoxSet := True;
          el.Style.GradBox := box;
        end;
      end
      else if w = 'gradient' then
      begin
        if S.Nodes[n1].IsString and S.Nodes[n2].IsString then
        begin
          el.Style.FillColor := S.Nodes[n1].Colour;
          el.Style.FillGradient := Default(TTyChartGradient);
          el.Style.FillGradient.Kind := cgkLinear;
          el.Style.FillGradient.Global := True;
          el.Style.FillGradient.X := (S.Edges[i].S1X + S.Edges[i].S2X) / 2;
          el.Style.FillGradient.Y := (S.Edges[i].S1Y + S.Edges[i].S2Y) / 2;
          el.Style.FillGradient.X2 := (S.Edges[i].T1X + S.Edges[i].T2X) / 2;
          el.Style.FillGradient.Y2 := (S.Edges[i].T1Y + S.Edges[i].T2Y) / 2;
          SetLength(el.Style.FillGradient.Stops, 2);
          el.Style.FillGradient.Stops[0].Offset := 0;
          el.Style.FillGradient.Stops[0].Color := S.Nodes[n1].Colour;
          el.Style.FillGradient.Stops[1].Offset := 1;
          el.Style.FillGradient.Stops[1].Color := S.Nodes[n2].Colour;
        end;
      end;
      { getLineStyle: the colour strokes, `width` wide (0 by default) }
      if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
      begin
        lw := 0;
        d := TyChordEdgeFind(S, i, 'lineStyle', 'width');
        if d <> nil then lw := JsNum(d);
        if lw > 0 then
        begin
          el.Style.StrokeColor := c;
          el.Style.StrokeWidthLogical := lw;
        end;
      end;
      d := TyChordEdgeFind(S, i, 'lineStyle', 'opacity');
      if d <> nil then el.Style.Alpha := JsNum(d) else el.Style.Alpha := 0.2;
      el.Z := S.Z;
      el.Z2 := 0;
      { BY ITS RAW INDEX, both: upstream's params.dataIndex is the raw one,
        and the state rows are kept by it }
      el.Datum := TyChartEdgeDatum(ASeriesIndex, i);
      el.Silent := False;
      Tag(el);
      { [F3c] a ribbon fades in where a universal transition morphs }
      el.Anim.UtTag := 2;
      el.Anim.UtRow := -2 - i;
      AList.Add(el);
      Inc(Result);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== focus ==================== }

procedure TyChordFocusSets(const S: TTyChordSolved; AIsEdge: Boolean;
  ARaw: Integer; out ANodes, AEdges: TTyIntegerArray);
var
  k, e: Integer;

  procedure Add(var A: TTyIntegerArray; AV: Integer);
  begin
    SetLength(A, Length(A) + 1);
    A[High(A)] := AV;
  end;

begin
  ANodes := nil;
  AEdges := nil;
  if AIsEdge then
  begin
    if (ARaw < 0) or (ARaw > High(S.Edges)) then Exit;
    Add(AEdges, ARaw);
    Add(ANodes, S.Nodes[S.Edges[ARaw].Source].DataIndex);
    Add(ANodes, S.Nodes[S.Edges[ARaw].Target].DataIndex);
    Exit;
  end;
  if (ARaw < 0) or (ARaw > High(S.Nodes)) then Exit;
  for k := 0 to High(S.Nodes[ARaw].Edges) do
  begin
    e := S.Nodes[ARaw].Edges[k];
    { `if (adjacentEdge.dataIndex < 0) continue` }
    if not S.Edges[e].Kept then Continue;
    Add(AEdges, e);
    Add(ANodes, S.Nodes[S.Edges[e].Source].DataIndex);
    Add(ANodes, S.Nodes[S.Edges[e].Target].DataIndex);
  end;
end;

end.
