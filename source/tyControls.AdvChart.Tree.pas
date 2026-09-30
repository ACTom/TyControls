unit tyControls.AdvChart.Tree;
{$mode objfpc}{$H+}
{ The tree series: a hierarchy, laid out by Reingold-Tilford, drawn as a
  symbol per node, an edge from each parent to each child and a label on
  every node.

  THE HIERARCHY IS UPSTREAM'S, row for row. `series.data` hangs under a
  VIRTUAL ROOT named after the series, and the rows are that tree in
  pre-order: row 0 is the virtual root, row 1 is data[0], and so on down and
  across. Only data[0] -- the REAL root -- is laid out; any further roots
  are rows with no place. The virtual root is depth 0, the real root 1.

  WHAT IS SHOWN is decided once, when the option is read: a node written
  with `collapsed` takes it; any other is open when its depth is within
  `initialTreeDepth` (JS semantics throughout: null is 0, a word that is no
  number is "everything"). A collapsed node is a leaf for the layout and its
  descendants have no place at all.

  THE LAYOUT is layoutHelper.ts -- d3-hierarchy's tree -- over row indices
  rather than objects: firstWalk in post-order, secondWalk in pre-order,
  apportion's threads and ancestors as rows. The breadth coordinate it
  produces is then scaled into the series' box per orient, in upstream's
  exact order of operations.

  THE `leaves` MODEL: a node that is a leaf, or collapsed, reads its label,
  itemStyle and lineStyle through `leaves` before the series -- but never
  its symbol, which upstream reads shallow off the item and the series.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Series, tyControls.AdvChart.Builder,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Symbol,
  tyControls.AdvChart.Labels, tyControls.AdvChart.LabelOpt,
  tyControls.AdvChart.LinePath, tyControls.AdvChart.Calendar,
  tyControls.AdvChart.JsMath;

const
  TyTreeSeriesTypeName = 'tree';
  { a node symbol's z2 over its edges' -- Symbol.ts:85 }
  cTyTreeNodeZ2 = 100;

type
  { ---- the hierarchy (Tree.createTree) ---- }
  TTyHierNode = record
    Parent: Integer;             // -1 for the virtual root
    Children: TTyIntegerArray;   // rows, in written order
    Index: Integer;              // this node's place among its parent's children
    Depth, Height: Integer;      // virtual root depth 0; a leaf's height 1
    Item: TJSONData;             // BORROWED from the option; nil for the virtual root
    Expanded: Boolean;
  end;
  TTyHierarchy = record
    Nodes: array of TTyHierNode;
    { upstream would have thrown (a null child): nothing is drawn }
    Valid: Boolean;
  end;

  TTyTreeOrient = (troLR, troRL, troTB, troBT, troNone);

  TTyTreeSpec = record
    Box: TTyRawBox;
    Radial: Boolean;
    Orient: TTyTreeOrient;
    Curve: Boolean;              // edgeShape 'curve'
    Polyline: Boolean;           // edgeShape 'polyline'
    Curveness: Double;
    { edgeForkPosition as written, parsePercent against 1 }
    ForkPosition: TTyBoxRaw;
    Symbol: TTySymbolSpec;
    Series: TJSONObject;         // borrowed
    Leaves: TJSONObject;         // borrowed `leaves`, or nil
    Z, Z2: Integer;
  end;

  TTyTreePos = record
    Placed: Boolean;
    { local to the main group, as upstream's getItemLayout }
    X, Y: Double;
    { radial only: the angle-like and radius coordinates before
      radialCoordinate }
    RawX, RawY: Double;
    { device px }
    PX, PY: Double;
  end;

  TTyTreeSolved = record
    Valid: Boolean;
    Spec: TTyTreeSpec;
    Hier: TTyHierarchy;
    Box: TTyXYWH;
    { the main group's origin: the box's corner, or its centre when radial }
    GX, GY: Double;
    RealRoot: Integer;
    Pos: array of TTyTreePos;
    { by row: not (has children and expanded) -- reads through `leaves` }
    LeafModelled: TTyBoolArray;
  end;

  { Everything a THEME answers. }
  TTyTreeInk = record
    NodeColour: TTyChartColor;
    EdgeColour: TTyChartColor;
    EmptyFill: TTyChartColor;
    { the series' label spec (show, default text, fonts, ink bands) }
    Label_: TTyLabelSpec;
    { by row: item -> leaves -> series (TyTreeLabelSpecs) }
    ItemLabels: TTyLabelSpecArray;
    SeriesName: string;
    LabelValueDim: Integer;
  end;

function TyHierarchyOf(AOption: TTyChartOption; ASeriesIndex: Integer): TTyHierarchy;
{ The store: one row per hierarchy row, the value column parsed as a series'
  data item is, names and raw values and per-item overrides as any series. }
procedure TyTreeFillStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore);
function TyTreeSpecOf(AOption: TTyChartOption; ASeriesIndex: Integer): TTyTreeSpec;
{ TreeSeries.getInitialData's isExpand. }
procedure TyTreeApplyExpand(AOption: TTyChartOption; ASeriesIndex: Integer;
  var AHier: TTyHierarchy);
{ treeLayout.ts commonLayout over the container, device px at APPI. }
function TyTreeSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer): TTyTreeSolved;
{ One label spec per row: the item's `label` over `leaves.label` (for a
  leaf-modelled row) over the series' spec. }
function TyTreeLabelSpecs(const ASolved: TTyTreeSolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
{ Edges (z2 0), then symbols (z2 100) with their caption requests. }
function TyBuildTreeMarks(ASeriesIndex: Integer; const ASolved: TTyTreeSolved;
  const AInk: TTyTreeInk; AStore: TTyDataStore; AList: TTyPaintList;
  APPI: Integer = 96): Integer;

implementation

uses tyControls.AdvChart.Scale;

{ ==================== small readers ==================== }

function ObjIn(ANode: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtObject) then Result := TJSONObject(d);
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

{ JS `+v`: null 0, a boolean 0/1, a string Number(), anything else NaN }
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

{ Model.get along item -> leaves -> series: the first of the chain whose
  sub-object has the key with a value that is not null }
function ChainFind(const AChain: array of TJSONObject; const ASub, AKey: string): TJSONData;
var
  k: Integer;
  o: TJSONObject;
  d: TJSONData;
begin
  Result := nil;
  for k := 0 to High(AChain) do
  begin
    o := ObjIn(AChain[k], ASub);
    if o = nil then Continue;
    d := o.Find(AKey);
    if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
  end;
end;

{ ==================== the hierarchy ==================== }

function TyHierarchyOf(AOption: TTyChartOption; ASeriesIndex: Integer): TTyHierarchy;
type
  TPending = record
    Item: TJSONData;
    Parent: Integer;
  end;
var
  node, d, ch: TJSONData;
  stack: array of TPending;
  top, row, k, par, n: Integer;
  pend: TPending;
begin
  Result := Default(TTyHierarchy);
  Result.Valid := True;
  SetLength(Result.Nodes, 1);
  Result.Nodes[0].Parent := -1;
  Result.Nodes[0].Index := 0;
  Result.Nodes[0].Item := nil;
  if AOption = nil then Exit;
  node := AOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  { PRE-ORDER WITH AN EXPLICIT STACK: children pushed right to left, so they
    come off left to right, each under the row that was made for its parent }
  stack := nil;
  top := 0;
  SetLength(stack, 64);
  for k := d.Count - 1 downto 0 do
  begin
    if top > High(stack) then SetLength(stack, Length(stack) * 2);
    stack[top].Item := d.Items[k];
    stack[top].Parent := 0;
    Inc(top);
  end;
  while top > 0 do
  begin
    Dec(top);
    pend := stack[top];
    if (pend.Item = nil) or (pend.Item.JSONType = jtNull) then
    begin
      { upstream reads `dataNode.value` off null and the setOption throws }
      Result.Valid := False;
      Continue;
    end;
    row := Length(Result.Nodes);
    SetLength(Result.Nodes, row + 1);
    par := pend.Parent;
    Result.Nodes[row] := Default(TTyHierNode);
    Result.Nodes[row].Parent := par;
    Result.Nodes[row].Item := pend.Item;
    Result.Nodes[row].Depth := Result.Nodes[par].Depth + 1;
    n := Length(Result.Nodes[par].Children);
    SetLength(Result.Nodes[par].Children, n + 1);
    Result.Nodes[par].Children[n] := row;
    Result.Nodes[row].Index := n;
    if pend.Item.JSONType = jtObject then
    begin
      ch := TJSONObject(pend.Item).Find('children');
      if (ch <> nil) and (ch.JSONType = jtArray) then
        for k := ch.Count - 1 downto 0 do
        begin
          if top > High(stack) then SetLength(stack, Length(stack) * 2);
          stack[top].Item := ch.Items[k];
          stack[top].Parent := row;
          Inc(top);
        end;
    end;
  end;
  { heights, bottom up: in pre-order every child's row is after its parent's }
  for row := High(Result.Nodes) downto 0 do
  begin
    n := 0;
    for k := 0 to High(Result.Nodes[row].Children) do
      n := Max(n, Result.Nodes[Result.Nodes[row].Children[k]].Height);
    Result.Nodes[row].Height := n + 1;
  end;
end;

procedure TyTreeFillStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore);
var
  hier: TTyHierarchy;
  arr: TJSONArray;
  o: TJSONObject;
  node, nm: TJSONData;
  row, k: Integer;
  dims: TTySeriesDimArray;
begin
  if AStore = nil then Exit;
  hier := TyHierarchyOf(AOption, ASeriesIndex);
  AStore.AddDimension('value', ddtFloat);
  SetLength(dims, 1);
  dims[0] := Default(TTySeriesDim);
  dims[0].Name := 'value';
  dims[0].Kind := ddtFloat;
  { THE ROWS AS ITEMS: each node's own keys without its children -- a
    shallow copy per node, so a deep chain is not copied once per level }
  arr := TJSONArray.Create;
  try
    node := AOption.ComponentAt('series', ASeriesIndex);
    o := TJSONObject.Create;
    if (node <> nil) and (node.JSONType = jtObject) then
    begin
      nm := TJSONObject(node).Find('name');
      if nm <> nil then o.Add('name', nm.Clone);
    end;
    arr.Add(o);
    for row := 1 to High(hier.Nodes) do
    begin
      if hier.Nodes[row].Item.JSONType = jtObject then
      begin
        o := TJSONObject.Create;
        for k := 0 to TJSONObject(hier.Nodes[row].Item).Count - 1 do
          if TJSONObject(hier.Nodes[row].Item).Names[k] <> 'children' then
            o.Add(TJSONObject(hier.Nodes[row].Item).Names[k],
              TJSONObject(hier.Nodes[row].Item).Items[k].Clone);
        arr.Add(o);
      end
      else
        arr.Add(hier.Nodes[row].Item.Clone);
    end;
    TyFillSeriesStoreArray(AOption, ASeriesIndex, arr, dims, AStore);
  finally
    arr.Free;
  end;
end;

{ ==================== the spec ==================== }

function TyTreeSpecOf(AOption: TTyChartOption; ASeriesIndex: Integer): TTyTreeSpec;
const
  cBoxKey: array[0..5] of string = ('width', 'left', 'right', 'height', 'top', 'bottom');
var
  node, d: TJSONData;
  s: string;
  ls: TJSONObject;
  raw, target: TTyCalBoxKeys;
  k: Integer;
begin
  Result := Default(TTyTreeSpec);
  Result.Box.Left := TyBoxRawStr('12%');
  Result.Box.Top := TyBoxRawStr('12%');
  Result.Box.Right := TyBoxRawStr('12%');
  Result.Box.Bottom := TyBoxRawStr('12%');
  Result.Orient := troLR;
  Result.Curve := True;
  Result.Curveness := 0.5;
  Result.ForkPosition := TyBoxRawStr('50%');
  Result.Symbol := TySymbolDefault(TyTreeSeriesTypeName);
  Result.Z := 2;
  if AOption = nil then Exit;
  node := AOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  Result.Series := TJSONObject(node);
  { THE BOX, as mergeDefaultAndTheme leaves it for a `box` layout: the keys
    written, the 12% defaults under the ones that are not, then the
    count-based mergeLayoutParam -- so `left` and `width` written drop the
    default `right` rather than over-constraining the box }
  for k := 0 to 5 do
  begin
    raw[k] := Default(TTyCalBoxKey);
    d := Result.Series.Find(cBoxKey[k]);
    if d <> nil then
    begin
      raw[k].Own := True;
      raw[k].V := TyBoxRawOf(d);
    end;
  end;
  target := raw;
  for k := 0 to 5 do
    if (k in [1, 2, 4, 5]) and not target[k].Own then
    begin
      target[k].Own := True;
      target[k].V := TyBoxRawStr('12%');
    end;
  TyCalMergeLayoutParam(target, raw, False, False);
  Result.Box.Width := target[0].V;
  Result.Box.Left := target[1].V;
  Result.Box.Right := target[2].V;
  Result.Box.Height := target[3].V;
  Result.Box.Top := target[4].V;
  Result.Box.Bottom := target[5].V;
  d := Result.Series.Find('layout');
  Result.Radial := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'radial');
  d := Result.Series.Find('orient');
  if d <> nil then
  begin
    { getOrient: the two words, and the four codes }
    s := '';
    if d.JSONType = jtString then s := d.AsString;
    if s = 'horizontal' then s := 'LR' else if s = 'vertical' then s := 'TB';
    if s = 'LR' then Result.Orient := troLR
    else if s = 'RL' then Result.Orient := troRL
    else if s = 'TB' then Result.Orient := troTB
    else if s = 'BT' then Result.Orient := troBT
    else Result.Orient := troNone;
  end;
  d := Result.Series.Find('edgeShape');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.Curve := d.AsString = 'curve';
    Result.Polyline := d.AsString = 'polyline';
  end;
  d := Result.Series.Find('edgeForkPosition');
  if d <> nil then Result.ForkPosition := TyBoxRawOf(d);
  ls := ObjIn(Result.Series, 'lineStyle');
  if ls <> nil then
  begin
    d := ls.Find('curveness');
    if d <> nil then Result.Curveness := JsNum(d);
  end;
  Result.Symbol := TySymbolSpecOf(Result.Series, Result.Symbol);
  Result.Leaves := ObjIn(Result.Series, 'leaves');
  d := Result.Series.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Z := Round(d.AsFloat);
end;

procedure TyTreeApplyExpand(AOption: TTyChartOption; ASeriesIndex: Integer;
  var AHier: TTyHierarchy);
var
  node, d: TJSONData;
  eac: Boolean;
  depthLimit, treeDepth, itd: Double;
  row: Integer;
begin
  treeDepth := 0;
  for row := 0 to High(AHier.Nodes) do
    treeDepth := Max(treeDepth, AHier.Nodes[row].Depth);
  eac := True;
  itd := 2;
  node := nil;
  if AOption <> nil then node := AOption.ComponentAt('series', ASeriesIndex);
  if (node <> nil) and (node.JSONType = jtObject) then
  begin
    d := TJSONObject(node).Find('expandAndCollapse');
    if d <> nil then eac := Truthy(d);
    d := TJSONObject(node).Find('initialTreeDepth');
    if d <> nil then itd := JsNum(d);
  end;
  { `option.initialTreeDepth >= 0`: NaN fails it -- everything open }
  if eac and not IsNan(itd) and (itd >= 0) then depthLimit := itd
  else depthLimit := treeDepth;
  for row := 0 to High(AHier.Nodes) do
  begin
    d := nil;
    if (AHier.Nodes[row].Item <> nil) and (AHier.Nodes[row].Item.JSONType = jtObject) then
      d := TJSONObject(AHier.Nodes[row].Item).Find('collapsed');
    if (d <> nil) and (d.JSONType <> jtNull) then
      AHier.Nodes[row].Expanded := not Truthy(d)
    else
      AHier.Nodes[row].Expanded := AHier.Nodes[row].Depth <= depthLimit;
  end;
end;

{ ==================== the layout ==================== }

type
  TWalk = record
    Prelim, Modifier, Change, Shift: TTyDoubleArray;
    Ancestor, Thread, DefaultAncestor: TTyIntegerArray;
    X: TTyDoubleArray;
  end;

function VisibleChildCount(const AH: TTyHierarchy; ARow: Integer): Integer;
begin
  if AH.Nodes[ARow].Expanded then Result := Length(AH.Nodes[ARow].Children)
  else Result := 0;
end;

function NextRight(const AH: TTyHierarchy; const W: TWalk; ARow: Integer): Integer;
var n: Integer;
begin
  n := Length(AH.Nodes[ARow].Children);
  if (n > 0) and AH.Nodes[ARow].Expanded then Result := AH.Nodes[ARow].Children[n - 1]
  else Result := W.Thread[ARow];
end;

function NextLeft(const AH: TTyHierarchy; const W: TWalk; ARow: Integer): Integer;
begin
  if (Length(AH.Nodes[ARow].Children) > 0) and AH.Nodes[ARow].Expanded then
    Result := AH.Nodes[ARow].Children[0]
  else Result := W.Thread[ARow];
end;

function Separation(const AH: TTyHierarchy; ARadial: Boolean; A, B: Integer): Double;
begin
  if AH.Nodes[A].Parent = AH.Nodes[B].Parent then Result := 1 else Result := 2;
  if ARadial then Result := Result / AH.Nodes[A].Depth;
end;

procedure MoveSubtree(const AH: TTyHierarchy; var W: TWalk; WL, WR: Integer; AShift: Double);
var change: Double;
begin
  change := AShift / (AH.Nodes[WR].Index - AH.Nodes[WL].Index);
  W.Change[WR] := W.Change[WR] - change;
  W.Shift[WR] := W.Shift[WR] + AShift;
  W.Modifier[WR] := W.Modifier[WR] + AShift;
  W.Prelim[WR] := W.Prelim[WR] + AShift;
  W.Change[WL] := W.Change[WL] + change;
end;

procedure ExecuteShifts(const AH: TTyHierarchy; var W: TWalk; ARow: Integer);
var
  shift, change: Double;
  n, c: Integer;
begin
  shift := 0;
  change := 0;
  for n := High(AH.Nodes[ARow].Children) downto 0 do
  begin
    c := AH.Nodes[ARow].Children[n];
    W.Prelim[c] := W.Prelim[c] + shift;
    W.Modifier[c] := W.Modifier[c] + shift;
    change := change + W.Change[c];
    shift := shift + W.Shift[c] + change;
  end;
end;

function NextAncestor(const AH: TTyHierarchy; const W: TWalk; AVil, AV, AAnc: Integer): Integer;
begin
  if AH.Nodes[W.Ancestor[AVil]].Parent = AH.Nodes[AV].Parent then
    Result := W.Ancestor[AVil]
  else
    Result := AAnc;
end;

function Apportion(const AH: TTyHierarchy; var W: TWalk; ARadial: Boolean;
  AV, AW, AAncestor: Integer): Integer;
var
  vor, vir, vol, vil: Integer;
  sor, sir, sol, sil, shift: Double;
begin
  Result := AAncestor;
  if AW < 0 then Exit;
  vor := AV;
  vir := AV;
  vol := AH.Nodes[AH.Nodes[AV].Parent].Children[0];
  vil := AW;
  sor := W.Modifier[vor];
  sir := W.Modifier[vir];
  sol := W.Modifier[vol];
  sil := W.Modifier[vil];
  while True do
  begin
    vil := NextRight(AH, W, vil);
    vir := NextLeft(AH, W, vir);
    if (vil < 0) or (vir < 0) then Break;
    vor := NextRight(AH, W, vor);
    vol := NextLeft(AH, W, vol);
    W.Ancestor[vor] := AV;
    shift := W.Prelim[vil] + sil - W.Prelim[vir] - sir + Separation(AH, ARadial, vil, vir);
    if shift > 0 then
    begin
      MoveSubtree(AH, W, NextAncestor(AH, W, vil, AV, Result), AV, shift);
      sir := sir + shift;
      sor := sor + shift;
    end;
    sil := sil + W.Modifier[vil];
    sir := sir + W.Modifier[vir];
    sor := sor + W.Modifier[vor];
    sol := sol + W.Modifier[vol];
  end;
  if (vil >= 0) and (NextRight(AH, W, vor) < 0) then
  begin
    W.Thread[vor] := vil;
    W.Modifier[vor] := W.Modifier[vor] + sil - sor;
  end;
  if (vir >= 0) and (NextLeft(AH, W, vol) < 0) then
  begin
    W.Thread[vol] := vir;
    W.Modifier[vol] := W.Modifier[vol] + sir - sol;
    Result := AV;
  end;
end;

procedure FirstWalk(const AH: TTyHierarchy; var W: TWalk; ARadial: Boolean; ARow: Integer);
var
  par, prev, n, anc: Integer;
  mid: Double;
begin
  par := AH.Nodes[ARow].Parent;
  prev := -1;
  if AH.Nodes[ARow].Index > 0 then
    prev := AH.Nodes[par].Children[AH.Nodes[ARow].Index - 1];
  n := VisibleChildCount(AH, ARow);
  if n > 0 then
  begin
    ExecuteShifts(AH, W, ARow);
    mid := (W.Prelim[AH.Nodes[ARow].Children[0]]
      + W.Prelim[AH.Nodes[ARow].Children[n - 1]]) / 2;
    if prev >= 0 then
    begin
      W.Prelim[ARow] := W.Prelim[prev] + Separation(AH, ARadial, ARow, prev);
      W.Modifier[ARow] := W.Prelim[ARow] - mid;
    end
    else
      W.Prelim[ARow] := mid;
  end
  else if prev >= 0 then
    W.Prelim[ARow] := W.Prelim[prev] + Separation(AH, ARadial, ARow, prev);
  anc := W.DefaultAncestor[par];
  if anc < 0 then anc := AH.Nodes[par].Children[0];
  W.DefaultAncestor[par] := Apportion(AH, W, ARadial, ARow, prev, anc);
end;

{ The visible rows under ARoot in pre-order (eachBefore). }
function PreorderVisible(const AH: TTyHierarchy; ARoot: Integer): TTyIntegerArray;
var
  stack: TTyIntegerArray;
  top, n, row, k: Integer;
begin
  Result := nil;
  SetLength(stack, 16);
  top := 0;
  stack[0] := ARoot;
  top := 1;
  n := 0;
  while top > 0 do
  begin
    Dec(top);
    row := stack[top];
    if n >= Length(Result) then SetLength(Result, Max(16, 2 * Length(Result)));
    Result[n] := row;
    Inc(n);
    if AH.Nodes[row].Expanded then
      for k := High(AH.Nodes[row].Children) downto 0 do
      begin
        if top >= Length(stack) then SetLength(stack, 2 * Length(stack));
        stack[top] := AH.Nodes[row].Children[k];
        Inc(top);
      end;
  end;
  SetLength(Result, n);
end;

{ The same rows in post-order (eachAfter): each subtree, left to right,
  before its parent. }
function PostorderVisible(const AH: TTyHierarchy; ARoot: Integer): TTyIntegerArray;
var
  stack, outp: TTyIntegerArray;
  top, n, row, k: Integer;
begin
  { reverse of a pre-order that visits children right to left }
  SetLength(stack, 16);
  stack[0] := ARoot;
  top := 1;
  n := 0;
  outp := nil;
  while top > 0 do
  begin
    Dec(top);
    row := stack[top];
    if n >= Length(outp) then SetLength(outp, Max(16, 2 * Length(outp)));
    outp[n] := row;
    Inc(n);
    if AH.Nodes[row].Expanded then
      for k := 0 to High(AH.Nodes[row].Children) do
      begin
        if top >= Length(stack) then SetLength(stack, 2 * Length(stack));
        stack[top] := AH.Nodes[row].Children[k];
        Inc(top);
      end;
  end;
  SetLength(Result, n);
  for k := 0 to n - 1 do Result[k] := outp[n - 1 - k];
end;

function TyTreeSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer): TTyTreeSolved;
var
  mask: TFPUExceptionMask;
  W: TWalk;
  n, row, k, realRoot, left, right, bottom: Integer;
  pre, post: TTyIntegerArray;
  scale, width, height, delta, tx, kx, ky, x: Double;
  box: TTyRawBox;

  function Scaled(const R: TTyBoxRaw): TTyBoxRaw;
  begin
    Result := R;
    if R.Kind = brNumber then Result.Num := R.Num * scale;
  end;

begin
  Result := Default(TTyTreeSolved);
  Result.Spec := TyTreeSpecOf(AOption, ASeriesIndex);
  Result.Hier := TyHierarchyOf(AOption, ASeriesIndex);
  TyTreeApplyExpand(AOption, ASeriesIndex, Result.Hier);
  n := Length(Result.Hier.Nodes);
  SetLength(Result.Pos, n);
  SetLength(Result.LeafModelled, n);
  for row := 0 to n - 1 do
    Result.LeafModelled[row] := not ((Length(Result.Hier.Nodes[row].Children) > 0)
      and Result.Hier.Nodes[row].Expanded);
  if not Result.Hier.Valid then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  box.Left := Scaled(Result.Spec.Box.Left);
  box.Right := Scaled(Result.Spec.Box.Right);
  box.Top := Scaled(Result.Spec.Box.Top);
  box.Bottom := Scaled(Result.Spec.Box.Bottom);
  box.Width := Scaled(Result.Spec.Box.Width);
  box.Height := Scaled(Result.Spec.Box.Height);
  Result.Box := TyGetLayoutRect(box, AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top, []);
  Result.Valid := True;
  Result.RealRoot := -1;
  { the main group: the box's corner, or its centre for a radial tree }
  if Result.Spec.Radial then
  begin
    Result.GX := Result.Box.X + Result.Box.W / 2;
    Result.GY := Result.Box.Y + Result.Box.H / 2;
  end
  else
  begin
    Result.GX := Result.Box.X;
    Result.GY := Result.Box.Y;
  end;
  { only data[0] is laid out }
  if (n < 2) or (Length(Result.Hier.Nodes[0].Children) = 0) then Exit;
  if (not Result.Spec.Radial) and (Result.Spec.Orient = troNone) then Exit;
  realRoot := Result.Hier.Nodes[0].Children[0];
  Result.RealRoot := realRoot;

  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    SetLength(W.Prelim, n);
    SetLength(W.Modifier, n);
    SetLength(W.Change, n);
    SetLength(W.Shift, n);
    SetLength(W.Ancestor, n);
    SetLength(W.Thread, n);
    SetLength(W.DefaultAncestor, n);
    SetLength(W.X, n);
    for row := 0 to n - 1 do
    begin
      W.Ancestor[row] := row;
      W.Thread[row] := -1;
      W.DefaultAncestor[row] := -1;
      W.X[row] := NaN;
    end;
    post := PostorderVisible(Result.Hier, realRoot);
    for k := 0 to High(post) do
      FirstWalk(Result.Hier, W, Result.Spec.Radial, post[k]);
    W.Modifier[0] := -W.Prelim[realRoot];
    pre := PreorderVisible(Result.Hier, realRoot);
    for k := 0 to High(pre) do
    begin
      row := pre[k];
      W.X[row] := W.Prelim[row] + W.Modifier[Result.Hier.Nodes[row].Parent];
      W.Modifier[row] := W.Modifier[row] + W.Modifier[Result.Hier.Nodes[row].Parent];
    end;
    { the extremes, first in pre-order on a tie }
    left := realRoot;
    right := realRoot;
    bottom := realRoot;
    for k := 0 to High(pre) do
    begin
      row := pre[k];
      if W.X[row] < W.X[left] then left := row;
      if W.X[row] > W.X[right] then right := row;
      if Result.Hier.Nodes[row].Depth > Result.Hier.Nodes[bottom].Depth then bottom := row;
    end;
    { NB radial: the separation divides by the LEFT node's depth }
    if left = right then delta := 1
    else delta := Separation(Result.Hier, Result.Spec.Radial, left, right) / 2;
    tx := delta - W.X[left];
    width := Result.Box.W;
    height := Result.Box.H;
    k := Result.Hier.Nodes[bottom].Depth - 1;
    if k = 0 then k := 1;
    if Result.Spec.Radial then
    begin
      { the angle runs round a full turn from twelve o'clock, the radius to
        half the shorter side }
      width := 2 * Pi;
      height := Min(Result.Box.H, Result.Box.W) / 2;
      kx := width / (W.X[right] + delta + tx);
      ky := height / k;
      for k := 0 to High(pre) do
      begin
        row := pre[k];
        x := W.X[row];
        Result.Pos[row].RawX := (x + tx) * kx;
        Result.Pos[row].RawY := (Result.Hier.Nodes[row].Depth - 1) * ky;
        { radialCoordinate }
        Result.Pos[row].X := Result.Pos[row].RawY * TyJsCos(Result.Pos[row].RawX - Pi / 2);
        Result.Pos[row].Y := Result.Pos[row].RawY * TyJsSin(Result.Pos[row].RawX - Pi / 2);
        Result.Pos[row].Placed := True;
      end;
    end
    else if Result.Spec.Orient in [troLR, troRL] then
    begin
      ky := height / (W.X[right] + delta + tx);
      kx := width / k;
      for k := 0 to High(pre) do
      begin
        row := pre[k];
        x := W.X[row];
        Result.Pos[row].Y := (x + tx) * ky;
        if Result.Spec.Orient = troLR then
          Result.Pos[row].X := (Result.Hier.Nodes[row].Depth - 1) * kx
        else
          Result.Pos[row].X := width - (Result.Hier.Nodes[row].Depth - 1) * kx;
        Result.Pos[row].Placed := True;
      end;
    end
    else
    begin
      kx := width / (W.X[right] + delta + tx);
      ky := height / k;
      for k := 0 to High(pre) do
      begin
        row := pre[k];
        x := W.X[row];
        Result.Pos[row].X := (x + tx) * kx;
        if Result.Spec.Orient = troTB then
          Result.Pos[row].Y := (Result.Hier.Nodes[row].Depth - 1) * ky
        else
          Result.Pos[row].Y := height - (Result.Hier.Nodes[row].Depth - 1) * ky;
        Result.Pos[row].Placed := True;
      end;
    end;
    for k := 0 to High(pre) do
    begin
      row := pre[k];
      if IsNan(Result.Pos[row].X) or IsNan(Result.Pos[row].Y) then
      begin
        Result.Pos[row].Placed := False;
        Continue;
      end;
      Result.Pos[row].PX := Result.GX + Result.Pos[row].X;
      Result.Pos[row].PY := Result.GY + Result.Pos[row].Y;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== labels ==================== }

function TyTreeLabelSpecs(const ASolved: TTyTreeSolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
var
  leavesSpec, base: TTyLabelSpec;
  row: Integer;
  it: TJSONData;
begin
  Result := nil;
  SetLength(Result, Length(ASolved.Hier.Nodes));
  leavesSpec := TyLabelSpecOfNode(ObjIn(ASolved.Spec.Leaves, 'label'),
    ASolved.Spec.Series, ASeriesSpec);
  for row := 0 to High(ASolved.Hier.Nodes) do
  begin
    if ASolved.LeafModelled[row] then base := leavesSpec else base := ASeriesSpec;
    it := ASolved.Hier.Nodes[row].Item;
    if (it <> nil) and (it.JSONType = jtObject) then
      Result[row] := TyLabelSpecOfNode(ObjIn(TJSONObject(it), 'label'),
        ASolved.Spec.Series, base)
    else
      Result[row] := base;
  end;
end;

{ ==================== the marks ==================== }

function ItemObj(const ASolved: TTyTreeSolved; ARow: Integer): TJSONObject;
var it: TJSONData;
begin
  Result := nil;
  it := ASolved.Hier.Nodes[ARow].Item;
  if (it <> nil) and (it.JSONType = jtObject) then Result := TJSONObject(it);
end;

{ item -> leaves (for a leaf-modelled row) -> series }
procedure ChainOf(const ASolved: TTyTreeSolved; ARow: Integer;
  out AChain: array of TJSONObject; out ACount: Integer);
begin
  ACount := 0;
  AChain[ACount] := ItemObj(ASolved, ARow);
  Inc(ACount);
  if ASolved.LeafModelled[ARow] then
  begin
    AChain[ACount] := ASolved.Spec.Leaves;
    Inc(ACount);
  end;
  AChain[ACount] := ASolved.Spec.Series;
  Inc(ACount);
end;

function ChainColour(const AChain: array of TJSONObject; const ASub, AKey: string;
  ADefault: TTyChartColor): TTyChartColor;
var
  d: TJSONData;
  c: TTyChartColor;
begin
  Result := ADefault;
  d := ChainFind(AChain, ASub, AKey);
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    Result := c;
end;

function ChainNum(const AChain: array of TJSONObject; const ASub, AKey: string;
  ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  d := ChainFind(AChain, ASub, AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function ChainDash(const AChain: array of TJSONObject; const ASub, AKey: string;
  AWidth: Double): TTyDoubleArray;
var
  d: TJSONData;
  i: Integer;
begin
  Result := nil;
  d := ChainFind(AChain, ASub, AKey);
  if d = nil then Exit;
  if (d.JSONType = jtString) and (d.AsString = 'dashed') then
    Result := TyDashPattern(todDashed, nil, AWidth)
  else if (d.JSONType = jtString) and (d.AsString = 'dotted') then
    Result := TyDashPattern(todDotted, nil, AWidth)
  else if d.JSONType = jtArray then
  begin
    SetLength(Result, d.Count);
    for i := 0 to d.Count - 1 do Result[i] := JsNum(d.Items[i]);
  end;
end;

{ radialCoordinate, each coordinate `|| 0`: not-a-number and a negative
  zero both come out as a plain zero }
function Radial0(ARad, AR: Double): TTyPointF;
begin
  Result.X := AR * TyJsCos(ARad - Pi / 2);
  Result.Y := AR * TyJsSin(ARad - Pi / 2);
  if IsNan(Result.X) or (Result.X = 0) then Result.X := 0;
  if IsNan(Result.Y) or (Result.Y = 0) then Result.Y := 0;
end;

{ TreePath.buildPath: the stem from the parent to the fork, then each
  child's twig -- the first, the bar to the last, the last, then the ones
  between -- as one path of several pieces. The fork sits edgeForkPosition
  of the way to the LAST child. }
function PolylineEdge(const ASolved: TTyTreeSolved; ARow: Integer): TTyChartShape;
var
  kids: TTyIntegerArray;
  n, i: Integer;
  pp, first, last, ci: TTyPointF;
  f: Double;
  tmp: array[0..1] of Double;
  forkDim, otherDim: Integer;
  cmds: TTyPathCmdArray;
  r: TTyXYWH;

  function At(const P: TTyPointF; ADim: Integer): Double;
  begin
    if ADim = 0 then Result := P.X else Result := P.Y;
  end;

  procedure Add(AKind: TTyPathCmdKind; AX, AY: Double);
  begin
    SetLength(cmds, Length(cmds) + 1);
    cmds[High(cmds)] := Default(TTyPathCmd);
    cmds[High(cmds)].Kind := AKind;
    cmds[High(cmds)].X := ASolved.GX + AX;
    cmds[High(cmds)].Y := ASolved.GY + AY;
  end;

  function P(ARow2: Integer): TTyPointF;
  begin
    Result := TyPointF(ASolved.Pos[ARow2].X, ASolved.Pos[ARow2].Y);
  end;

begin
  Result := TyShapePolyline([]);
  cmds := nil;
  kids := ASolved.Hier.Nodes[ARow].Children;
  n := Length(kids);
  for i := 0 to n - 1 do
    if not ASolved.Pos[kids[i]].Placed then Exit;
  pp := P(ARow);
  if n = 1 then
  begin
    Add(pckMove, pp.X, pp.Y);
    Add(pckLine, P(kids[0]).X, P(kids[0]).Y);
  end
  else
  begin
    if ASolved.Spec.Orient in [troTB, troBT] then forkDim := 0 else forkDim := 1;
    otherDim := 1 - forkDim;
    f := TyBoxRawResolve(ASolved.Spec.ForkPosition, 1);
    first := P(kids[0]);
    last := P(kids[n - 1]);
    tmp[forkDim] := At(pp, forkDim);
    tmp[otherDim] := At(pp, otherDim) + (At(last, otherDim) - At(pp, otherDim)) * f;
    Add(pckMove, pp.X, pp.Y);
    Add(pckLine, tmp[0], tmp[1]);
    Add(pckMove, first.X, first.Y);
    tmp[forkDim] := At(first, forkDim);
    Add(pckLine, tmp[0], tmp[1]);
    tmp[forkDim] := At(last, forkDim);
    Add(pckLine, tmp[0], tmp[1]);
    Add(pckLine, last.X, last.Y);
    for i := 1 to n - 2 do
    begin
      ci := P(kids[i]);
      Add(pckMove, ci.X, ci.Y);
      tmp[forkDim] := At(ci, forkDim);
      Add(pckLine, tmp[0], tmp[1]);
    end;
  end;
  Result := TyShapePolyline([TyPointF(cmds[0].X, cmds[0].Y),
    TyPointF(cmds[High(cmds)].X, cmds[High(cmds)].Y)]);
  Result.Cmds := cmds;
  r := TyPathCmdsRect(cmds);
  Result.HasCmdBounds := True;
  Result.CmdBounds := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
end;

{ THE RADIAL LABEL (TreeView.ts:389-444): its side and its turn from the
  node's angle about the real root -- a leaf or a collapsed node reads
  outward, an open inner node toward the centre, and the root follows the
  middle of its first and last child. Placed on its box by the position,
  then turned about the box's centre, as zrender's getLocalTransform turns
  an element with an origin. }
procedure RadialLabel(const ASolved: TTyTreeSolved; ARow: Integer;
  const ASpec: TTyLabelSpec; const AChain: array of TJSONObject; AScale: Double;
  var ACaption: TTyElementCaption);
var
  root, t: TTyTreePos;
  kids: TTyIntegerArray;
  cx, cy, rad, rot, x, y, ox, oy, m4, m5, st, ct, atx, aty, d: Double;
  isLeft: Boolean;
  pos: TTyLabelPosition;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  dp: TJSONData;
  box: TTyXYWH;
begin
  if ASolved.RealRoot < 0 then Exit;
  root := ASolved.Pos[ASolved.RealRoot];
  t := ASolved.Pos[ARow];
  kids := ASolved.Hier.Nodes[ASolved.RealRoot].Children;
  if (t.X = root.X) and ASolved.Hier.Nodes[ARow].Expanded and (Length(kids) > 0) then
  begin
    cx := (ASolved.Pos[kids[0]].X + ASolved.Pos[kids[High(kids)]].X) / 2;
    cy := (ASolved.Pos[kids[0]].Y + ASolved.Pos[kids[High(kids)]].Y) / 2;
    rad := TyJsAtan2(cy - root.Y, cx - root.X);
    if rad < 0 then rad := Pi * 2 + rad;
    isLeft := cx < root.X;
    if isLeft then rad := rad - Pi;
  end
  else
  begin
    rad := TyJsAtan2(t.Y - root.Y, t.X - root.X);
    if rad < 0 then rad := Pi * 2 + rad;
    if (Length(ASolved.Hier.Nodes[ARow].Children) = 0)
      or not ASolved.Hier.Nodes[ARow].Expanded then
    begin
      isLeft := t.X < root.X;
      if isLeft then rad := rad - Pi;
    end
    else
    begin
      isLeft := t.X > root.X;
      if not isLeft then rad := rad - Pi;
    end;
  end;
  { the author's position and turn win }
  if ChainFind(AChain, 'label', 'position') <> nil then pos := ASpec.Position
  else if isLeft then pos := tlpLeft
  else pos := tlpRight;
  dp := ChainFind(AChain, 'label', 'rotate');
  if (dp <> nil) and (dp.JSONType = jtNumber) then rot := ASpec.RotationRad
  else rot := -rad;
  { the anchor on the box, as the position puts it }
  box := ACaption.HostBox;
  d := ASpec.DistanceLogical * AScale;
  TyLabelAnchorXYWH(box, pos, d, 0, 0, x, y, ah, av);
  { getLocalTransform with an origin at the box's centre }
  ox := box.X + box.W / 2 - x;
  oy := box.Y + box.H / 2 - y;
  if (ox <> 0) or (oy <> 0) then
  begin
    m4 := -ox;
    m5 := -oy;
  end
  else
  begin
    m4 := 0;
    m5 := 0;
  end;
  if rot <> 0 then
  begin
    st := TyJsSin(rot);
    ct := TyJsCos(rot);
    atx := m4;
    aty := m5;
    m4 := ct * atx + st * aty;
    m5 := ct * aty - st * atx;
  end;
  m4 := m4 + (ox + x);
  m5 := m5 + (oy + y);
  ACaption.HasFixedAnchor := True;
  ACaption.FixedX := m4;
  ACaption.FixedY := m5;
  ACaption.FixedInside := TyLabelIsInside(pos);
  ACaption.FixedAH := ah;
  ACaption.FixedAV := tavMiddle;
  ACaption.FixedRotationRad := rot;
end;

function TyBuildTreeMarks(ASeriesIndex: Integer; const ASolved: TTyTreeSolved;
  const AInk: TTyTreeInk; AStore: TTyDataStore; AList: TTyPaintList;
  APPI: Integer): Integer;
var
  AScale: Double;
  row, par, cnt: Integer;
  chain: array[0..2] of TJSONObject;
  s, t, cp1, cp2: TTyPointF;
  c: Double;
  el: TTyChartElement;
  shape: TTyChartShape;
  sym: TTySymbolSpec;
  colour: TTyChartColor;
  w: Double;
  collapsedParent, zeroSize: Boolean;
  spec: TTyLabelSpec;
  r: TTyXYWH;
begin
  Result := 0;
  if (AList = nil) or not ASolved.Valid then Exit;
  if APPI > 0 then AScale := APPI / 96 else AScale := 1;
  c := ASolved.Spec.Curveness;
  { ---- polyline edges: one per open parent, in the parent's lineStyle ----
    (orthogonal only: upstream's radial polyline throws, its production
    build draws no edges) }
  if ASolved.Spec.Polyline and not ASolved.Spec.Radial then
    for row := 1 to High(ASolved.Hier.Nodes) do
    begin
      if not ASolved.Pos[row].Placed then Continue;
      if not ASolved.Hier.Nodes[row].Expanded then Continue;
      if Length(ASolved.Hier.Nodes[row].Children) = 0 then Continue;
      shape := PolylineEdge(ASolved, row);
      if Length(shape.Cmds) = 0 then Continue;
      el := TyChartElement(shape);
      ChainOf(ASolved, row, chain, cnt);
      w := ChainNum(Slice(chain, cnt), 'lineStyle', 'width', 1.5);
      el.Style.HasFill := False;
      el.Style.StrokeColor := ChainColour(Slice(chain, cnt), 'lineStyle', 'color', AInk.EdgeColour);
      el.Style.StrokeWidthLogical := w;
      el.Style.DashLogical := ChainDash(Slice(chain, cnt), 'lineStyle', 'type', w);
      el.Style.Alpha := ChainNum(Slice(chain, cnt), 'lineStyle', 'opacity', 1);
      el.Z := ASolved.Spec.Z;
      el.Z2 := ASolved.Spec.Z2;
      el.Silent := True;
      el.Datum := TyChartDatum(ASeriesIndex, row, row);
      AList.Add(el);
      Inc(Result);
    end;

  { ---- curve edges: parent to child, in the child's lineStyle ---- }
  if ASolved.Spec.Curve then
    for row := 1 to High(ASolved.Hier.Nodes) do
    begin
      par := ASolved.Hier.Nodes[row].Parent;
      if par <= 0 then Continue;
      if not (ASolved.Pos[row].Placed and ASolved.Pos[par].Placed) then Continue;
      s := TyPointF(ASolved.Pos[par].X, ASolved.Pos[par].Y);
      t := TyPointF(ASolved.Pos[row].X, ASolved.Pos[row].Y);
      if ASolved.Spec.Radial then
      begin
        { in (angle, radius): every point re-derived from the raw pair, and
          each coordinate `|| 0` }
        s := Radial0(ASolved.Pos[par].RawX, ASolved.Pos[par].RawY);
        cp1 := Radial0(ASolved.Pos[par].RawX, ASolved.Pos[par].RawY
          + (ASolved.Pos[row].RawY - ASolved.Pos[par].RawY) * c);
        cp2 := Radial0(ASolved.Pos[row].RawX, ASolved.Pos[row].RawY
          + (ASolved.Pos[par].RawY - ASolved.Pos[row].RawY) * c);
        t := Radial0(ASolved.Pos[row].RawX, ASolved.Pos[row].RawY);
      end
      else if ASolved.Spec.Orient in [troLR, troRL] then
      begin
        cp1 := TyPointF(s.X + (t.X - s.X) * c, s.Y);
        cp2 := TyPointF(t.X + (s.X - t.X) * c, t.Y);
      end
      else
      begin
        cp1 := TyPointF(s.X, s.Y + (t.Y - s.Y) * c);
        cp2 := TyPointF(t.X, t.Y + (s.Y - t.Y) * c);
      end;
      { to device px, each point once }
      s := TyPointF(ASolved.GX + s.X, ASolved.GY + s.Y);
      t := TyPointF(ASolved.GX + t.X, ASolved.GY + t.Y);
      cp1 := TyPointF(ASolved.GX + cp1.X, ASolved.GY + cp1.Y);
      cp2 := TyPointF(ASolved.GX + cp2.X, ASolved.GY + cp2.Y);
      { a REAL cubic: the two end points for the hit test and the bounds to
        fall back on, the commands for the painter }
      shape := TyShapePolyline([s, t]);
      SetLength(shape.Cmds, 2);
      shape.Cmds[0] := Default(TTyPathCmd);
      shape.Cmds[0].Kind := pckMove;
      shape.Cmds[0].X := s.X;
      shape.Cmds[0].Y := s.Y;
      shape.Cmds[1] := Default(TTyPathCmd);
      shape.Cmds[1].Kind := pckCurve;
      shape.Cmds[1].X1 := cp1.X;
      shape.Cmds[1].Y1 := cp1.Y;
      shape.Cmds[1].X2 := cp2.X;
      shape.Cmds[1].Y2 := cp2.Y;
      shape.Cmds[1].X := t.X;
      shape.Cmds[1].Y := t.Y;
      r := TyPathCmdsRect(shape.Cmds);
      shape.HasCmdBounds := True;
      shape.CmdBounds := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
      el := TyChartElement(shape);
      ChainOf(ASolved, row, chain, cnt);
      w := ChainNum(Slice(chain, cnt), 'lineStyle', 'width', 1.5);
      el.Style.HasFill := False;
      el.Style.StrokeColor := ChainColour(Slice(chain, cnt), 'lineStyle', 'color', AInk.EdgeColour);
      el.Style.StrokeWidthLogical := w;
      el.Style.DashLogical := ChainDash(Slice(chain, cnt), 'lineStyle', 'type', w);
      el.Style.Alpha := ChainNum(Slice(chain, cnt), 'lineStyle', 'opacity', 1);
      el.Z := ASolved.Spec.Z;
      el.Z2 := ASolved.Spec.Z2;
      el.Silent := True;
      el.Datum := TyChartDatum(ASeriesIndex, row, row);
      AList.Add(el);
      Inc(Result);
    end;

  { ---- the nodes ---- }
  for row := 1 to High(ASolved.Hier.Nodes) do
  begin
    if not ASolved.Pos[row].Placed then Continue;
    ChainOf(ASolved, row, chain, cnt);
    { the symbol is read shallow: the item's own over the series' }
    sym := ASolved.Spec.Symbol;
    if ItemObj(ASolved, row) <> nil then sym := TySymbolSpecOf(ItemObj(ASolved, row), sym);
    sym := TySymbolResolveOffset(sym);
    if sym.Kind = tsyNone then Continue;
    shape := TyBuildSymbol(sym, ASolved.Pos[row].PX, ASolved.Pos[row].PY);
    { A NODE OF NO SIZE is still an element: it paints nothing and carries
      its label }
    zeroSize := (shape.Kind = cskRect) and not TyRectFIsValid(shape.Bounds)
      and ((sym.WidthPx = 0) or (sym.HeightPx = 0));
    if zeroSize then
      shape := TyShapeRect(TyRectF(ASolved.Pos[row].PX + sym.OffsetX,
        ASolved.Pos[row].PY + sym.OffsetY, ASolved.Pos[row].PX + sym.OffsetX,
        ASolved.Pos[row].PY + sym.OffsetY));
    if (shape.Kind = cskRect) and not TyRectFIsValid(shape.Bounds) then Continue;
    el := TyChartElement(shape);
    colour := ChainColour(Slice(chain, cnt), 'itemStyle', 'color', AInk.NodeColour);
    collapsedParent := (not ASolved.Hier.Nodes[row].Expanded)
      and (Length(ASolved.Hier.Nodes[row].Children) > 0);
    if sym.Empty then
    begin
      { symbolPathSetColor: the ring in the node's colour at 2px, whatever
        the border says; hollow, unless the node hides children }
      el.Style.StrokeColor := colour;
      el.Style.StrokeWidthLogical := 2;
      el.Style.HasFill := True;
      if collapsedParent then el.Style.FillColor := colour
      else el.Style.FillColor := AInk.EmptyFill;
    end
    else
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := colour;
      if ChainFind(Slice(chain, cnt), 'itemStyle', 'borderColor') <> nil then
      begin
        el.Style.StrokeColor := ChainColour(Slice(chain, cnt), 'itemStyle', 'borderColor', colour);
        el.Style.StrokeWidthLogical := ChainNum(Slice(chain, cnt), 'itemStyle', 'borderWidth', 1.5);
      end;
    end;
    el.Style.Alpha := ChainNum(Slice(chain, cnt), 'itemStyle', 'opacity', 1);
    { the rect its label is placed against, as zrender computes it }
    el.Caption.HasHostBox := True;
    el.Caption.HostBox := TySymbolLabelBox(sym, ASolved.Pos[row].PX, ASolved.Pos[row].PY,
      el.Style.StrokeWidthLogical,
      (el.Style.StrokeWidthLogical > 0) and (el.Style.StrokeColor <> 0),
      el.Style.HasFill);
    if zeroSize then el.Style.StrokeWidthLogical := 0;
    el.Z := ASolved.Spec.Z;
    el.Z2 := ASolved.Spec.Z2 + cTyTreeNodeZ2;
    el.HitSlopLogical := 4;
    el.Datum := TyChartDatum(ASeriesIndex, row, row);
    { the caption REQUEST: the row's own spec, through the expansion's table }
    el.Caption.Text := '';
    if row <= High(AInk.ItemLabels) then spec := AInk.ItemLabels[row]
    else spec := AInk.Label_;
    if (AStore <> nil) and spec.Show then
    begin
      el.Caption.Text := TyLabelText(spec.Formatter, spec.HasFormatter, spec.DefaultText,
        AStore, row, AInk.SeriesName, AInk.LabelValueDim, NaN, False);
      el.Caption.ItemSpec := row + 1;
      if ASolved.Spec.Radial then
        RadialLabel(ASolved, row, spec, Slice(chain, cnt), AScale, el.Caption);
    end;
    AList.Add(el);
    Inc(Result);
  end;
end;

end.
