unit tyControls.AdvChart.Treemap;
{$mode objfpc}{$H+}
{ The treemap series: a hierarchy drawn as nested rectangles, each node's
  area its share of its parent's inside.

  THE HIERARCHY IS THE TREE'S (TyHierarchyOf) and so are the completed
  values (TyTreeCompletedValues). Sorting never touches the rows: each node
  lays out a sorted, filtered COPY of its children (its view) -- desc by
  default, ties putting the LATER row first, the opposite of a sunburst's.

  THE LAYOUT is treemapLayout.ts's squarify, statement for statement: a
  running row area added on push and subtracted on pop, `<=` against the best
  score (`<` loops forever on a row of noughts), the last of a row taking
  what remains, and no rounding anywhere. A sorted parent drops the children
  whose share of its area falls under `visibleMin` (10 px2 by default) and
  the rest grow to fill it. Every coordinate is local to the parent; the
  global origin is accumulated as zrender's group transforms are -- a local
  offset under 5e-5 on both axes is DROPPED, not added.

  THE COLOURS: the chart palette goes into levels[0].color unless a level
  defines a colour of its own; a parent hands the k-th child of its view
  list[k mod n], and descendants inherit it unchanged. Only a node with no
  view children is filled. BORDERS ARE NOT STROKES: every visible node draws
  a background rect in its border colour and the children sit on top of it,
  inset.

  THE LABELS are zrender's: the name (or formatter) in the content rect's
  centre, lines dropped that the height cannot hold and each cut to the width
  with minChar 2 and '...'. Their z2 is a RUNNING MAXIMUM over the pre-order
  walk plus two, not the host's plus two.

  THE BREADCRUMB is on by default: the path to the node under the canvas
  centre, found on the first frame in UNTRANSFORMED coordinates -- so, in
  effect, descending into any node at least half the canvas wide and half as
  tall.

  THE VIEW [Batch 115]: a drill-down (treemapRootToNode, a leaf root's
  click) lays out only the VIEW ROOT's subtree; the nodes above it keep the
  view root's layout and draw nothing, their viewChildren whatever an
  earlier layout left (upstream never clears them). A zoomToNode lays the
  view root out at estimateRootSize's size and centres the target; a pan
  (treemapMove) only moves the root; the wheel (treemapRender) lays it out
  at the zoomed size, both at the payload's rootRect. The root's position
  is the tree root's layout x / y, under the container group.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  Classes, SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Labels,
  tyControls.AdvChart.LabelOpt, tyControls.AdvChart.Calendar,
  tyControls.AdvChart.VisualMap, tyControls.AdvChart.Tree;

const
  TyTreemapSeriesTypeName = 'treemap';

type
  TTyTreemapNode = record
    Value: Double;
    { false: removed by visibleMin, or never reached }
    HasLayout: Boolean;
    { LOCAL to the parent's origin, as upstream holds them }
    X, Y, W, H, Area: Double;
    BorderWidth, UpperHeight, UpperLabelHeight: Double;
    { the laid-out children, sorted and filtered -- a copy; the rows keep
      their order }
    View: TTyIntegerArray;
    InView, Invisible: Boolean;
    { the accumulated group origin; HasT false is zrender's null transform }
    HasT: Boolean;
    TX, TY: Double;
    { the children's value extent, sorted, BEFORE visibleMin cut any: what
      a saturation range maps over [Batch 78] }
    HasExtent: Boolean;
    ExtMin, ExtMax: Double;
    { the border colour, which is the background rect's fill; none when a
      borderColorSaturation has no colour to work from }
    HasStroke: Boolean;
    Stroke: TTyChartColor;
    { nodes with no view children only; false draws nothing }
    HasFill: Boolean;
    Fill: TTyChartColor;
    { the label after line drop and truncation; LabelText '' is none }
    HasLabel: Boolean;
    LabelText: string;
    LabelX, LabelY: Double;
    LabelAH: TTyTextAnchorH;
    LabelAV: TTyTextAnchorV;
    { cut by leafDepth: drawn as a leaf, its label behind the drill icon
      [Batch 80] }
    IsLeafRoot: Boolean;
    { upstream's data id: the item's, else its name (a repeat counted
      '__ec__k'), else generated }
    Id: string;
    { A PARENT'S HEADER, on its background's top strip [Batch 78] }
    HasUpper: Boolean;
    UpperText: string;
    UpperX, UpperY: Double;
    UpperCentre, UpperInside: Boolean;
    { [Batch 115] above the view root: laid out as the view root, drawing
      nothing but its group }
    AboveView: Boolean;
    { the label's words before the cut (the drill icon included): what a
      frame of the drill-down cuts again to the rect it has then }
    LabelRaw: string;
    HasLabelRaw: Boolean;
    { drawn although outside the canvas: an element kept from the last
      render while the drill-down moves it out (willInvisibleEls) }
    DrawInvisible: Boolean;
  end;

  { WHAT A RENDER IS FOR [Batch 115]: the payload's type, its target (a row,
    -1 for none or a node the tree does not hold) and its rootRect }
  TTyTreemapPayloadKind = (tpkNone, tpkZoomToNode, tpkRootToNode, tpkMove, tpkRender,
    { not rendered by an action that queries another treemap: the last
      layout and root kept as they are }
    tpkKeep);
  TTyTreemapView = record
    ViewRoot: Integer;
    Kind: TTyTreemapPayloadKind;
    Target: Integer;
    RootX, RootY, RootW, RootH: Double;
    { a rootToNode's direction against the view root before it: 0 none,
      1 drillDown, 2 rollUp }
    Direction: Integer;
  end;

  { UPSTREAM'S ELEMENT STORAGE, by row: a node group, a background, a
    content -- made once and kept while the node is rendered, invisible ones
    included [Batch 115] }
  TTyTreemapHave = record
    Group, Bg, Ct: array of Boolean;
  end;

  TTyTreemapCrumb = record
    Row: Integer;
    Text: string;
    { device px, the group offset already added }
    Points: array of TTyPointF;
    LabelX, LabelY: Double;
  end;

  TTyTreemapSolved = record
    Valid: Boolean;
    SeriesIndex: Integer;
    Hier: TTyHierarchy;
    Nodes: array of TTyTreemapNode;
    Series: TJSONObject;                 // borrowed
    Levels: array of TJSONObject;        // borrowed, by depth; nil where none
    { setDefault: levels[0] takes the palette }
    Level0Default: Boolean;
    Box: TTyXYWH;
    Z: Integer;
    Scale: Double;
    Crumbs: array of TTyTreemapCrumb;
    { the series' own leafDepth [Batch 80] }
    HasLeafDepth: Boolean;
    LeafDepth: Double;
    { the store's dimension count: the longest value array, the root's
      scalar counting one }
    DimMax: Integer;
    { THE VIEW [Batch 115]: the view root, the rows above it (root first),
      and the root's position under the container group }
    ViewRoot: Integer;
    AbovePath: TTyIntegerArray;
    { the container group's origin, device px }
    ContainerX, ContainerY: Double;
  end;

  TTyTreemapInk = record
    { the label spec by row (item -> level -> series); then the breadcrumb's
      text; then the headers', by row }
    Label_: TTyLabelSpec;
    ItemLabels: TTyLabelSpecArray;
    CrumbFill: TTyChartColor;
  end;

{ Layout and pruning over the container, device px at APPI. AView is what
  the render is for; APrev the last solve of the same tree (Valid False for
  none): a pan keeps its layout, and every render keeps the viewChildren of
  the nodes it does not lay out [Batch 115]. }
function TyTreemapSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer): TTyTreemapSolved; overload;
function TyTreemapSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer; const AView: TTyTreemapView;
  const APrev: TTyTreemapSolved): TTyTreemapSolved; overload;
{ SeriesData's ids of a hierarchy's rows (upstream's node.getId()): the
  item's own id, else its name -- the k-th repeat among the rows without an
  id '__ec__k', the root named after the series -- else generated
  ('e' + two NULs + the row) [Batch 115: from AssignIds, for a sunburst's
  getNodeById too] }
function TyHierIds(const AHier: TTyHierarchy; ASeries: TJSONObject): TTyStringArray;
{ The view of a render with no payload: the root, nothing targeted. }
function TyTreemapNoView: TTyTreemapView;
{ treemapClampZoom: the series' own scaleLimit (default min 0.2, max 5) }
function TyTreemapClampZoom(const ASolved: TTyTreemapSolved; AZoom: Double): Double;
{ calculateCurrentZoom: the width ratio, else the height's, else 1 }
function TyTreemapCurrentZoom(ABaseW, ABaseH, ACurW, ACurH: Double): Double;
{ The row under the view root that a click finds at the global point (AX,
  AY): findTarget, pre-order over the viewChildren, the last whose
  background (AHave) holds it through its group's transform; -1 for none. }
function TyTreemapFindTarget(const ASolved: TTyTreemapSolved; const AHave: TTyTreemapHave;
  AX, AY: Double): Integer;
{ The storage after a render: what was kept from APrev, and what is new
  (not made for a node outside the canvas) [Batch 115]. }
function TyTreemapHaveOf(const ASolved: TTyTreemapSolved;
  const APrev: TTyTreemapHave): TTyTreemapHave;
{ A content label's words and anchor on a content rect at (AX0, AY0) --
  shape x * 1 + the group's tx -- of ACW by ACH: zrender's cut and the
  position table, as a frame of the drill-down places it [Batch 115]. }
function TyTreemapLabelAt(const ASolved: TTyTreemapSolved; ARow: Integer;
  const ASpec: TTyLabelSpec; const AMeasurer: ITyTextMeasurer;
  AX0, AY0, ACW, ACH: Double; out AText: string; out ALX, ALY: Double): Boolean;
{ The colour visual: APalette into levels[0] unless a level has a colour;
  ABorder is the series' default border colour. }
procedure TyTreemapColour(var ASolved: TTyTreemapSolved;
  const APalette: TTyChartColorArray; ABorder: TTyChartColor);
{ One label spec per row: item -> levels[depth] -> series. }
function TyTreemapLabelSpecs(const ASolved: TTyTreemapSolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
{ One header spec per row: upperLabel on item -> level -> series over
  ABase (the chart's own label ink, so a header reads as outside text). }
function TyTreemapUpperSpecs(const ASolved: TTyTreemapSolved;
  const ABase: TTyLabelSpec): TTyLabelSpecArray;
{ The labels' words and anchors. }
procedure TyTreemapLabels(var ASolved: TTyTreemapSolved;
  const ASpecs: TTyLabelSpecArray; AStore: TTyDataStore; const ASeriesName: string;
  AValueDim: Integer; const AMeasurer: ITyTextMeasurer);
{ The parents' headers (upperLabel): ASpecs by row, the words cut to the
  strip. [Batch 78] }
procedure TyTreemapUpperLabels(var ASolved: TTyTreemapSolved;
  const ASpecs: TTyLabelSpecArray; AStore: TTyDataStore; const ASeriesName: string;
  AValueDim: Integer; const AMeasurer: ITyTextMeasurer);
{ The breadcrumb on the first frame, measured in ACrumbSpec's font. }
procedure TyTreemapBreadcrumb(var ASolved: TTyTreemapSolved;
  const ACrumbSpec: TTyLabelSpec; const AMeasurer: ITyTextMeasurer;
  const AContainer: TTyRectF); overload;
{ ATarget: the payload's target (-1 for none); otherwise, without a
  leafDepth, the node under the canvas centre as the backgrounds were LAST
  PAINTED -- APrev's transforms for the ones kept (AHave / APrevHave), none
  for the new [Batch 115]. }
procedure TyTreemapBreadcrumb(var ASolved: TTyTreemapSolved;
  const ACrumbSpec: TTyLabelSpec; const AMeasurer: ITyTextMeasurer;
  const AContainer: TTyRectF; ATarget: Integer; const AHave, APrevHave: TTyTreemapHave;
  const APrev: TTyTreemapSolved); overload;
{ The rects in pre-order, then the breadcrumb. }
function TyBuildTreemapMarks(ASeriesIndex: Integer; const ASolved: TTyTreemapSolved;
  const AInk: TTyTreemapInk; AList: TTyPaintList): Integer;

implementation

uses tyControls.AdvChart.Scale, tyControls.AdvChart.JsMath;

const
  cEps = 5e-5;

{ ==================== small readers ==================== }

function ObjIn(ANode: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtObject) then Result := TJSONObject(d);
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

{ JS truthiness }
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

{ Math.max / Math.min: NaN wins }
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

function Around0(V: Double): Boolean;
begin
  Result := not ((V > cEps) or (V < -cEps));
end;

function ItemOf(const ASolved: TTyTreemapSolved; ARow: Integer): TJSONObject;
var it: TJSONData;
begin
  Result := nil;
  it := ASolved.Hier.Nodes[ARow].Item;
  if (it <> nil) and (it.JSONType = jtObject) then Result := TJSONObject(it);
end;

function LevelOf(const ASolved: TTyTreemapSolved; ARow: Integer): TJSONObject;
var d: Integer;
begin
  Result := nil;
  d := ASolved.Hier.Nodes[ARow].Depth;
  if (d >= 0) and (d <= High(ASolved.Levels)) then Result := ASolved.Levels[d];
end;

{ Model.get along item -> level -> series: the first with the key and a
  value that is not null. (The designated layer the colour visual plugs in
  between level and series is the visual's own business.) }
function ChainFind(const ASolved: TTyTreemapSolved; ARow: Integer;
  const ASub, AKey: string): TJSONData;
var
  k: Integer;
  chain: array[0..2] of TJSONObject;
  o: TJSONObject;
  d: TJSONData;
begin
  Result := nil;
  chain[0] := ItemOf(ASolved, ARow);
  chain[1] := LevelOf(ASolved, ARow);
  chain[2] := ASolved.Series;
  for k := 0 to 2 do
  begin
    if chain[k] = nil then Continue;
    if ASub <> '' then o := ObjIn(chain[k], ASub) else o := chain[k];
    if o = nil then Continue;
    d := o.Find(AKey);
    if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
  end;
end;

{ `get(path)` as a number, with the series default ADefault }
function ChainNum(const ASolved: TTyTreemapSolved; ARow: Integer;
  const ASub, AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  d := ChainFind(ASolved, ARow, ASub, AKey);
  if d = nil then Result := ADefault else Result := JsNum(d);
end;

{ convertOptionIdName(get('name')): the item's name, else its level's, else
  the series'. The virtual root's item IS the series' name and its data. }
function ChainName(const ASolved: TTyTreemapSolved; ARow: Integer;
  out AText: string): Boolean;
var d: TJSONData; lv: TJSONObject;
begin
  AText := '';
  d := nil;
  if ARow = 0 then
  begin
    d := ASolved.Series.Find('name');
    if (d <> nil) and (d.JSONType = jtNull) then d := nil;
    if d = nil then
    begin
      lv := LevelOf(ASolved, 0);
      if lv <> nil then d := lv.Find('name');
      if (d <> nil) and (d.JSONType = jtNull) then d := nil;
    end;
  end
  else
    d := ChainFind(ASolved, ARow, '', 'name');
  if d = nil then Exit(False);
  Result := True;
  case d.JSONType of
    jtString: AText := d.AsString;
    jtNumber: AText := TyJsNumberToString(d.AsFloat);
    jtBoolean: if d.AsBoolean then AText := 'true' else AText := 'false';
  else
    AText := d.AsJSON;
  end;
end;

{ getValue(dim): 0, '' and 'value' the completed value; a dimension past
  the store NaN; an array's entry (null NaN); a scalar -- a completed sum
  included -- answers every dimension [Batch 80] }
function ValueAt(const S: TTyTreemapSolved; ARow, ADim: Integer): Double;
var d: TJSONData; it: TJSONObject;
begin
  if ADim <= 0 then Exit(S.Nodes[ARow].Value);
  if ADim >= S.DimMax then Exit(NaN);
  it := ItemOf(S, ARow);
  d := nil;
  if it <> nil then d := it.Find('value');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    if ADim >= d.Count then Exit(NaN);
    d := d.Items[ADim];
    if (d = nil) or (d.JSONType = jtNull) then Exit(NaN);
    if (d.JSONType = jtString) and (d.AsString = '') then Exit(NaN);
    Exit(JsNum(d));
  end;
  Result := S.Nodes[ARow].Value;
end;

{ the parent's visualDimension: 0 for none, '' and 'value' }
function DimOf(const S: TTyTreemapSolved; ARow: Integer): Integer;
var d: TJSONData;
begin
  Result := 0;
  d := ChainFind(S, ARow, '', 'visualDimension');
  if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat > 0) then
    Result := Trunc(d.AsFloat);
end;

{ ==================== the solve ==================== }

type
  TSolveCtx = record
    S: ^TTyTreemapSolved;
    SortMode: Integer;          // 0 none, 1 asc, 2 desc
    Ratio, Scale: Double;
  end;

{ the comparator: < 0 when A goes first }
function Cmp(const C: TSolveCtx; A, B: Integer): Double;
var diff: Double;
begin
  if C.SortMode = 1 then diff := C.S^.Nodes[A].Value - C.S^.Nodes[B].Value
  else diff := C.S^.Nodes[B].Value - C.S^.Nodes[A].Value;
  if diff = 0 then
  begin
    if C.SortMode = 1 then Result := A - B else Result := B - A;
  end
  else
    Result := diff;
end;

function InitChildren(const C: TSolveCtx; ARow: Integer; ATotalArea: Double;
  AHide: Boolean; ADepth: Integer): TTyIntegerArray;
var
  vc: TTyIntegerArray;
  k, j, tmp, len, del, dim: Integer;
  sum, v, vm, emin, emax: Double;
  over: Boolean;
begin
  Result := nil;
  { leafDepth outranks childrenVisibleMin -- at or past its depth only }
  over := C.S^.HasLeafDepth and (C.S^.LeafDepth <= ADepth);
  if AHide and not over then Exit;
  vc := Copy(C.S^.Hier.Nodes[ARow].Children, 0, Length(C.S^.Hier.Nodes[ARow].Children));
  if C.SortMode <> 0 then
    for k := 1 to High(vc) do
    begin
      tmp := vc[k];
      j := k - 1;
      while (j >= 0) and (Cmp(C, vc[j], tmp) > 0) do
      begin
        vc[j + 1] := vc[j];
        Dec(j);
      end;
      vc[j + 1] := tmp;
    end;
  sum := 0;
  for k := 0 to High(vc) do sum := sum + C.S^.Nodes[vc[k]].Value;
  { statistic(): over the sorted children, before the cut, by the
    parent's visualDimension; NaN never enters }
  dim := DimOf(C.S^, ARow);
  emin := Infinity;
  emax := NegInfinity;
  for k := 0 to High(vc) do
  begin
    v := ValueAt(C.S^, vc[k], dim);
    if v < emin then emin := v;
    if v > emax then emax := v;
  end;
  if sum = 0 then Exit;
  { filterByThreshold: smallest first, the sum shrinking as it goes, the
    last match the cut }
  if C.SortMode <> 0 then
  begin
    vm := ChainNum(C.S^, ARow, '', 'visibleMin', 10) * C.Scale * C.Scale;
    len := Length(vc);
    del := len;
    for k := len - 1 downto 0 do
    begin
      if C.SortMode = 1 then v := C.S^.Nodes[vc[len - k - 1]].Value
      else v := C.S^.Nodes[vc[k]].Value;
      if v / sum * ATotalArea < vm then
      begin
        del := k;
        sum := sum - v;
      end;
    end;
    if C.SortMode = 1 then vc := Copy(vc, len - del, del)
    else SetLength(vc, del);
  end;
  if sum = 0 then Exit;
  for k := 0 to High(vc) do
  begin
    C.S^.Nodes[vc[k]].HasLayout := True;
    C.S^.Nodes[vc[k]].X := 0;
    C.S^.Nodes[vc[k]].Y := 0;
    C.S^.Nodes[vc[k]].W := 0;
    C.S^.Nodes[vc[k]].H := 0;
    C.S^.Nodes[vc[k]].Area := C.S^.Nodes[vc[k]].Value / sum * ATotalArea;
  end;
  { past leafDepth: the children keep their area and nothing more }
  if over then
  begin
    if Length(vc) > 0 then C.S^.Nodes[ARow].IsLeafRoot := True;
    vc := nil;
  end;
  C.S^.Nodes[ARow].HasExtent := True;
  C.S^.Nodes[ARow].ExtMin := emin;
  C.S^.Nodes[ARow].ExtMax := emax;
  Result := vc;
end;

function Worst(const C: TSolveCtx; const ARow: TTyIntegerArray; ACount: Integer;
  ARowArea, ARfl: Double): Double;
var
  k: Integer;
  a, areaMax, areaMin, sq, f: Double;
begin
  areaMax := 0;
  areaMin := Infinity;
  for k := 0 to ACount - 1 do
  begin
    a := C.S^.Nodes[ARow[k]].Area;
    if (a <> 0) and not IsNan(a) then
    begin
      if a < areaMin then areaMin := a;
      if a > areaMax then areaMax := a;
    end;
  end;
  sq := ARowArea * ARowArea;
  f := ARfl * ARfl * C.Ratio;
  if (sq <> 0) and not IsNan(sq) then
    Result := JsMax((f * areaMax) / sq, sq / (f * areaMin))
  else
    Result := Infinity;
end;

{ position(): RP[0..1] is the rect's x, y and RS[0..1] its width, height }
procedure Position(const C: TSolveCtx; const ARow: TTyIntegerArray; ACount: Integer;
  ARowArea, ARfl: Double; var RP, RS: array of Double; AHalfGap: Double;
  AFlush: Boolean);
var
  h, o, k: Integer;
  last, rol, step, wh0, wh1, remain, modWH: Double;
  lp, ls: array[0..1] of Double;
begin
  if ARfl = RS[0] then h := 0 else h := 1;
  o := 1 - h;
  last := RP[h];
  if (ARfl <> 0) and not IsNan(ARfl) then rol := ARowArea / ARfl else rol := 0;
  if AFlush or (rol > RS[o]) then rol := RS[o];
  for k := 0 to ACount - 1 do
  begin
    if (rol <> 0) and not IsNan(rol) then step := C.S^.Nodes[ARow[k]].Area / rol
    else step := 0;
    wh1 := JsMax(rol - 2 * AHalfGap, 0);
    ls[o] := wh1;
    remain := RP[h] + RS[h] - last;
    if (k = ACount - 1) or (remain < step) then modWH := remain else modWH := step;
    wh0 := JsMax(modWH - 2 * AHalfGap, 0);
    ls[h] := wh0;
    lp[o] := RP[o] + JsMin(AHalfGap, wh1 / 2);
    lp[h] := last + JsMin(AHalfGap, wh0 / 2);
    last := last + modWH;
    C.S^.Nodes[ARow[k]].X := lp[0];
    C.S^.Nodes[ARow[k]].Y := lp[1];
    C.S^.Nodes[ARow[k]].W := ls[0];
    C.S^.Nodes[ARow[k]].H := ls[1];
  end;
  RP[o] := RP[o] + rol;
  RS[o] := RS[o] - rol;
end;

procedure Squarify(const C: TSolveCtx; ARow: Integer; AHide: Boolean; ADepth: Integer);
var
  width, height, bw, hg, ulh, uh, lo, lou, totalArea, rfl, best, score, rowArea, cvm: Double;
  vc, row: TTyIntegerArray;
  i, n, k: Integer;
  rp, rs: array[0..1] of Double;
  d: TJSONData;
begin
  width := C.S^.Nodes[ARow].W;
  height := C.S^.Nodes[ARow].H;
  bw := ChainNum(C.S^, ARow, 'itemStyle', 'borderWidth', 0) * C.Scale;
  hg := ChainNum(C.S^, ARow, 'itemStyle', 'gapWidth', 0) * C.Scale / 2;
  if Truthy(ChainFind(C.S^, ARow, 'upperLabel', 'show')) then
    ulh := ChainNum(C.S^, ARow, 'upperLabel', 'height', 20) * C.Scale
  else
    ulh := 0;
  uh := JsMax(bw, ulh);
  lo := bw - hg;
  lou := uh - hg;
  C.S^.Nodes[ARow].BorderWidth := bw;
  C.S^.Nodes[ARow].UpperHeight := uh;
  C.S^.Nodes[ARow].UpperLabelHeight := ulh;
  width := JsMax(width - 2 * lo, 0);
  height := JsMax(height - lo - lou, 0);
  totalArea := width * height;
  vc := InitChildren(C, ARow, totalArea, AHide, ADepth);
  C.S^.Nodes[ARow].View := vc;
  if Length(vc) = 0 then Exit;
  rp[0] := lo;
  rp[1] := lou;
  rs[0] := width;
  rs[1] := height;
  rfl := JsMin(width, height);
  best := Infinity;
  SetLength(row, Length(vc));
  n := 0;
  rowArea := 0;
  i := 0;
  while i < Length(vc) do
  begin
    row[n] := vc[i];
    Inc(n);
    rowArea := rowArea + C.S^.Nodes[vc[i]].Area;
    score := Worst(C, row, n, rowArea, rfl);
    { `<=`: a row of noughts scores Infinity, and `<` would retry it forever }
    if score <= best then
    begin
      Inc(i);
      best := score;
    end
    else
    begin
      Dec(n);
      rowArea := rowArea - C.S^.Nodes[row[n]].Area;
      Position(C, row, n, rowArea, rfl, rp, rs, hg, False);
      rfl := JsMin(rs[0], rs[1]);
      n := 0;
      rowArea := 0;
      best := Infinity;
    end;
  end;
  if n > 0 then Position(C, row, n, rowArea, rfl, rp, rs, hg, True);
  if not AHide then
  begin
    d := ChainFind(C.S^, ARow, '', 'childrenVisibleMin');
    if d <> nil then
    begin
      cvm := JsNum(d) * C.Scale * C.Scale;
      if totalArea < cvm then AHide := True;
    end;
  end;
  for k := 0 to High(vc) do Squarify(C, vc[k], AHide, ADepth + 1);
end;

{ zrender BoundingRect.intersect, touching counts }
function Intersects(AX, AY, AW, AH, BX, BY, BW, BH: Double): Boolean;
var ax0, ax1, ay0, ay1, bx0, bx1, by0, by1: Double;
begin
  ax0 := AX; ax1 := AX + AW; ay0 := AY; ay1 := AY + AH;
  if BW < 0 then begin BX := BX + BW; BW := -BW; end;
  if BH < 0 then begin BY := BY + BH; BH := -BH; end;
  bx0 := BX; bx1 := BX + BW; by0 := BY; by1 := BY + BH;
  if (ax0 > ax1) or (ay0 > ay1) or (bx0 > bx1) or (by0 > by1) then Exit(False);
  Result := not ((ax1 < bx0) or (bx1 < ax0) or (ay1 < by0) or (by1 < ay0));
end;

{ prunning(): the rows above the view root and its subtree are in view;
  a sibling of the path, or anything at the view root's depth that is not
  it, is not visited [Batch 115] }
procedure Prune(var S: TTyTreemapSolved; ARow: Integer; CX, CY, CW, CH: Double;
  ADepth: Integer);
var k: Integer; above: Boolean;
begin
  above := (ADepth <= High(S.AbovePath)) and (S.AbovePath[ADepth] = ARow);
  if ((ADepth <= High(S.AbovePath)) and not above)
    or ((ADepth = Length(S.AbovePath)) and (ARow <> S.ViewRoot)) then Exit;
  S.Nodes[ARow].InView := True;
  S.Nodes[ARow].AboveView := above;
  S.Nodes[ARow].Invisible := (not above) and not Intersects(CX, CY, CW, CH,
    S.Nodes[ARow].X, S.Nodes[ARow].Y, S.Nodes[ARow].W, S.Nodes[ARow].H);
  for k := 0 to High(S.Nodes[ARow].View) do
    Prune(S, S.Nodes[ARow].View[k], CX - S.Nodes[ARow].X, CY - S.Nodes[ARow].Y, CW, CH,
      ADepth + 1);
end;

{ zrender's group transforms, top down: a local offset under 5e-5 on both
  axes is no transform at all -- the parent's is copied }
procedure Compose(var S: TTyTreemapSolved; ARow: Integer; AHasT: Boolean; ATX, ATY: Double);
var k: Integer; x, y: Double;
begin
  { every node in view, the ones outside the canvas included: a kept
    element of one still moves while a drill-down runs [Batch 115] }
  if not S.Nodes[ARow].HasLayout or not S.Nodes[ARow].InView then Exit;
  x := S.Nodes[ARow].X;
  y := S.Nodes[ARow].Y;
  if IsNan(x) then x := 0;
  if IsNan(y) then y := 0;
  if Around0(x) and Around0(y) then
  begin
    S.Nodes[ARow].HasT := AHasT;
    S.Nodes[ARow].TX := ATX;
    S.Nodes[ARow].TY := ATY;
  end
  else if not AHasT then
  begin
    S.Nodes[ARow].HasT := True;
    S.Nodes[ARow].TX := 0 + (0 + x);
    S.Nodes[ARow].TY := 0 + (0 + y);
  end
  else
  begin
    S.Nodes[ARow].HasT := True;
    S.Nodes[ARow].TX := x + ATX;
    S.Nodes[ARow].TY := y + ATY;
  end;
  if not S.Nodes[ARow].HasT then
  begin
    S.Nodes[ARow].TX := 0;
    S.Nodes[ARow].TY := 0;
  end;
  for k := 0 to High(S.Nodes[ARow].View) do
    Compose(S, S.Nodes[ARow].View[k], S.Nodes[ARow].HasT, S.Nodes[ARow].TX,
      S.Nodes[ARow].TY);
end;

{ SeriesData's ids: the item's own (a number as its text), else its name
  -- counted among the id-less rows, the k-th repeat '__ec__k', the root
  named after the series -- else generated from the row }
function TyHierIds(const AHier: TTyHierarchy; ASeries: TJSONObject): TTyStringArray;
var
  row, k: Integer;
  counts: TStringList;
  d: TJSONData;
  nm: string;
  hasName: Boolean;

  function IdName(AData: TJSONData; out AText: string): Boolean;
  begin
    Result := False;
    AText := '';
    if AData = nil then Exit;
    if AData.JSONType = jtString then AText := AData.AsString
    else if AData.JSONType = jtNumber then AText := TyJsNumberToString(AData.AsFloat)
    else Exit;
    Result := True;
  end;

begin
  counts := TStringList.Create;
  try
    counts.Sorted := True;
    counts.CaseSensitive := True;
    SetLength(Result, Length(AHier.Nodes));
    for row := 0 to High(AHier.Nodes) do
    begin
      if row = 0 then
      begin
        if ASeries <> nil then hasName := IdName(ASeries.Find('name'), nm)
        else hasName := False;
        d := nil;
      end
      else if AHier.Nodes[row].Item is TJSONObject then
      begin
        hasName := IdName(TJSONObject(AHier.Nodes[row].Item).Find('name'), nm);
        d := TJSONObject(AHier.Nodes[row].Item).Find('id');
      end
      else
      begin
        hasName := False;
        d := nil;
      end;
      if IdName(d, Result[row]) then Continue;
      if hasName then
      begin
        if counts.Find(nm, k) then
          counts.Objects[k] := TObject(PtrInt(counts.Objects[k]) + 1)
        else
          k := counts.AddObject(nm, TObject(PtrInt(1)));
        if PtrInt(counts.Objects[k]) > 1 then
          Result[row] := nm + '__ec__' + IntToStr(PtrInt(counts.Objects[k]))
        else
          Result[row] := nm;
      end
      else
        Result[row] := 'e'#0#0 + IntToStr(row);
    end;
  finally
    counts.Free;
  end;
end;

procedure AssignIds(var S: TTyTreemapSolved);
var ids: TTyStringArray; row: Integer;
begin
  ids := TyHierIds(S.Hier, S.Series);
  for row := 0 to High(S.Nodes) do S.Nodes[row].Id := ids[row];
end;

function TyTreemapNoView: TTyTreemapView;
begin
  Result := Default(TTyTreemapView);
  Result.ViewRoot := 0;
  Result.Kind := tpkNone;
  Result.Target := -1;
end;

function TyTreemapSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer): TTyTreemapSolved;
begin
  Result := TyTreemapSolve(AOption, ASeriesIndex, AContainer, APPI, TyTreemapNoView,
    Default(TTyTreemapSolved));
end;

function TyTreemapCurrentZoom(ABaseW, ABaseH, ACurW, ACurH: Double): Double;
begin
  { (a / b) || (c / d) || 1: nought and not-a-number are false }
  Result := ACurW / ABaseW;
  if (Result = 0) or IsNan(Result) then Result := ACurH / ABaseH;
  if (Result = 0) or IsNan(Result) then Result := 1;
end;

function TyTreemapClampZoom(const ASolved: TTyTreemapSolved; AZoom: Double): Double;
var
  sl, d: TJSONData;
  lo, hi: Double;
begin
  Result := AZoom;
  if ASolved.Series = nil then Exit;
  { the default {max: 5, min: 0.2} merged under the series' own; written
    null, it is gone and nothing clamps }
  sl := ASolved.Series.Find('scaleLimit');
  if (sl <> nil) and (sl.JSONType = jtNull) then Exit;
  lo := 0.2;
  hi := 5;
  if sl is TJSONObject then
  begin
    d := TJSONObject(sl).Find('min');
    if d <> nil then lo := JsNum(d);
    d := TJSONObject(sl).Find('max');
    if d <> nil then hi := JsNum(d);
  end;
  { zoomLimit.min || 0, zoomLimit.max || Infinity }
  if (lo = 0) or IsNan(lo) then lo := 0;
  if (hi = 0) or IsNan(hi) then hi := Infinity;
  Result := JsMax(JsMin(hi, Result), lo);
end;

{ estimateRootSize: the area that gives the target zoomToNodeRatio of the
  view, grown up the ancestors by each one's share and its borders }
procedure EstimateRootSize(const S: TTyTreemapSolved; ATarget: Integer;
  ACW, ACH: Double; out AW, AH: Double);
var
  cur, par, k: Integer;
  viewArea, area, sum, v, ratio, bw, ulh, uh, sc, maxSafe: Double;
  d: TJSONData;
begin
  AW := ACW;
  AH := ACH;
  if (ATarget < 0) or (ATarget = S.ViewRoot) then Exit;
  viewArea := ACW * ACH;
  d := S.Series.Find('zoomToNodeRatio');
  if (d <> nil) and (d.JSONType = jtNumber) then ratio := d.AsFloat
  else
  begin
    { 0.32 * 0.32, multiplied at run time in doubles }
    ratio := 0.32;
    ratio := ratio * ratio;
  end;
  area := viewArea * ratio;
  maxSafe := 9007199254740991;
  cur := ATarget;
  par := S.Hier.Nodes[cur].Parent;
  while par >= 0 do
  begin
    sum := 0;
    for k := 0 to High(S.Hier.Nodes[par].Children) do
      sum := sum + S.Nodes[S.Hier.Nodes[par].Children[k]].Value;
    v := S.Nodes[cur].Value;
    if v = 0 then Exit;
    area := area * (sum / v);
    bw := ChainNum(S, par, 'itemStyle', 'borderWidth', 0) * S.Scale;
    if Truthy(ChainFind(S, par, 'upperLabel', 'show')) then
      ulh := ChainNum(S, par, 'upperLabel', 'height', 20) * S.Scale
    else
      ulh := 0;
    uh := JsMax(bw, ulh);
    area := area + (4 * bw * bw + (3 * bw + uh) * TyJsPow(area, 0.5));
    if area > maxSafe then area := maxSafe;
    cur := par;
    par := S.Hier.Nodes[cur].Parent;
  end;
  if area < viewArea then area := viewArea;
  sc := TyJsPow(area / viewArea, 0.5);
  AW := ACW * sc;
  AH := ACH * sc;
end;

function TyTreemapSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer; const AView: TTyTreemapView;
  const APrev: TTyTreemapSolved): TTyTreemapSolved;
const
  cBoxKey: array[0..5] of string = ('width', 'left', 'right', 'height', 'top', 'bottom');
var
  mask: TFPUExceptionMask;
  node, d: TJSONData;
  n, row, k, vr, p: Integer;
  done: TTyDoubleArray;
  C: TSolveCtx;
  raw, target: TTyCalBoxKeys;
  box: TTyRawBox;
  W, H, cx, cy, rw, rh, zoom, tcx, tcy: Double;
  lv: TJSONObject;
  hasColor, samePrev, relayout: Boolean;

  function Scaled(const R: TTyBoxRaw): TTyBoxRaw;
  begin
    Result := R;
    if R.Kind = brNumber then Result.Num := R.Num * C.Scale;
  end;

begin
  Result := Default(TTyTreemapSolved);
  Result.SeriesIndex := ASeriesIndex;
  Result.Hier := TyHierarchyOf(AOption, ASeriesIndex);
  if not Result.Hier.Valid then Exit;
  node := AOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  Result.Series := TJSONObject(node);
  if APPI > 0 then Result.Scale := APPI / 96 else Result.Scale := 1;
  Result.Z := 0;
  d := Result.Series.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Z := Round(d.AsFloat);
  d := Result.Series.Find('levels');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    SetLength(Result.Levels, d.Count);
    for k := 0 to d.Count - 1 do
      if d.Items[k].JSONType = jtObject then Result.Levels[k] := TJSONObject(d.Items[k])
      else Result.Levels[k] := nil;
  end;
  { setDefault: any level colour -- an itemStyle.color, or a color that is
    truthy and not 'none', an empty list included -- keeps the palette out }
  hasColor := False;
  for k := 0 to High(Result.Levels) do
  begin
    lv := Result.Levels[k];
    if lv = nil then Continue;
    if (ObjIn(lv, 'itemStyle') <> nil) and Truthy(ObjIn(lv, 'itemStyle').Find('color')) then
      hasColor := True;
    d := lv.Find('color');
    if Truthy(d) and not ((d.JSONType = jtString) and (d.AsString = 'none')) then
      hasColor := True;
  end;
  Result.Level0Default := not hasColor;
  { the series' OWN leafDepth }
  d := Result.Series.Find('leafDepth');
  Result.HasLeafDepth := (d <> nil) and (d.JSONType = jtNumber);
  if Result.HasLeafDepth then Result.LeafDepth := d.AsFloat;
  n := Length(Result.Hier.Nodes);
  SetLength(Result.Nodes, n);
  done := TyTreeCompletedValues(Result.Hier);
  for row := 0 to n - 1 do Result.Nodes[row].Value := done[row];
  { the store's dimensions: the longest value array; a scalar is one }
  Result.DimMax := 1;
  for row := 1 to n - 1 do
    if Result.Hier.Nodes[row].Item is TJSONObject then
    begin
      d := TJSONObject(Result.Hier.Nodes[row].Item).Find('value');
      if (d <> nil) and (d.JSONType = jtArray) and (d.Count > Result.DimMax) then
        Result.DimMax := d.Count;
    end;
  AssignIds(Result);
  { sort: absent is true; truthy is desc unless 'asc'; falsy none }
  d := Result.Series.Find('sort');
  if d = nil then C.SortMode := 2
  else if not Truthy(d) then C.SortMode := 0
  else if (d.JSONType = jtString) and (d.AsString = 'asc') then C.SortMode := 1
  else C.SortMode := 2;
  C.S := @Result;
  C.Scale := Result.Scale;
  d := Result.Series.Find('squareRatio');
  if (d <> nil) and (d.JSONType <> jtNull) then C.Ratio := JsNum(d)
  else C.Ratio := 0.5 * (1 + Sqrt(5));

  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    { THE BOX: the keys written, the defaults (20 across, 50 down) under the
      ones that are not, then mergeLayoutParam count by count }
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
        if k in [1, 2] then target[k].V := TyBoxRawNum(20)
        else target[k].V := TyBoxRawNum(50);
      end;
    TyCalMergeLayoutParam(target, raw, False, False);
    box.Width := Scaled(target[0].V);
    box.Left := Scaled(target[1].V);
    box.Right := Scaled(target[2].V);
    box.Height := Scaled(target[3].V);
    box.Top := Scaled(target[4].V);
    box.Bottom := Scaled(target[5].V);
    W := AContainer.Right - AContainer.Left;
    H := AContainer.Bottom - AContainer.Top;
    Result.Box := TyGetLayoutRect(box, AContainer.Left, AContainer.Top, W, H, []);
    { THE VIEW ROOT and the path above it, root first [Batch 115] }
    vr := AView.ViewRoot;
    if (vr < 0) or (vr >= n) then vr := 0;
    Result.ViewRoot := vr;
    Result.AbovePath := nil;
    p := Result.Hier.Nodes[vr].Parent;
    while p >= 0 do
    begin
      SetLength(Result.AbovePath, Length(Result.AbovePath) + 1);
      for k := High(Result.AbovePath) downto 1 do
        Result.AbovePath[k] := Result.AbovePath[k - 1];
      Result.AbovePath[0] := p;
      p := Result.Hier.Nodes[p].Parent;
    end;
    samePrev := APrev.Valid and (Length(APrev.Nodes) = n);
    { what an earlier layout left in the viewChildren of the nodes this one
      does not lay out }
    if samePrev then
      for row := 0 to n - 1 do Result.Nodes[row].View := APrev.Nodes[row].View;
    relayout := not ((AView.Kind in [tpkMove, tpkKeep]) and samePrev);
    if not relayout then
    begin
      { A PAN keeps the layout: only the root moves }
      for row := 0 to n - 1 do
      begin
        Result.Nodes[row].HasLayout := APrev.Nodes[row].HasLayout;
        Result.Nodes[row].X := APrev.Nodes[row].X;
        Result.Nodes[row].Y := APrev.Nodes[row].Y;
        Result.Nodes[row].W := APrev.Nodes[row].W;
        Result.Nodes[row].H := APrev.Nodes[row].H;
        Result.Nodes[row].Area := APrev.Nodes[row].Area;
        Result.Nodes[row].BorderWidth := APrev.Nodes[row].BorderWidth;
        Result.Nodes[row].UpperHeight := APrev.Nodes[row].UpperHeight;
        Result.Nodes[row].UpperLabelHeight := APrev.Nodes[row].UpperLabelHeight;
        Result.Nodes[row].HasExtent := APrev.Nodes[row].HasExtent;
        Result.Nodes[row].ExtMin := APrev.Nodes[row].ExtMin;
        Result.Nodes[row].ExtMax := APrev.Nodes[row].ExtMax;
        Result.Nodes[row].IsLeafRoot := APrev.Nodes[row].IsLeafRoot;
      end;
    end
    else
    begin
      { THE ROOT'S SIZE: the box; a zoomToNode's estimate, or a wheel's
        rootRect, clamped by scaleLimit }
      rw := Result.Box.W;
      rh := Result.Box.H;
      if AView.Kind = tpkZoomToNode then
      begin
        EstimateRootSize(Result, AView.Target, Result.Box.W, Result.Box.H, rw, rh);
        zoom := TyTreemapClampZoom(Result,
          TyTreemapCurrentZoom(Result.Box.W, Result.Box.H, rw, rh));
        rw := Result.Box.W * zoom;
        rh := Result.Box.H * zoom;
      end
      else if AView.Kind in [tpkRender, tpkMove] then
      begin
        zoom := TyTreemapClampZoom(Result,
          TyTreemapCurrentZoom(Result.Box.W, Result.Box.H, AView.RootW, AView.RootH));
        rw := Result.Box.W * zoom;
        rh := Result.Box.H * zoom;
      end;
      Result.Nodes[vr].HasLayout := True;
      Result.Nodes[vr].X := 0;
      Result.Nodes[vr].Y := 0;
      Result.Nodes[vr].W := rw;
      Result.Nodes[vr].H := rh;
      Result.Nodes[vr].Area := rw * rh;
      Squarify(C, vr, False, 0);
      { the rows above take the view root's layout (extend over it) }
      for k := 0 to High(Result.AbovePath) do
      begin
        row := Result.AbovePath[k];
        Result.Nodes[row].HasLayout := True;
        Result.Nodes[row].X := Result.Nodes[vr].X;
        Result.Nodes[row].Y := Result.Nodes[vr].Y;
        Result.Nodes[row].W := Result.Nodes[vr].W;
        Result.Nodes[row].H := Result.Nodes[vr].H;
        Result.Nodes[row].Area := Result.Nodes[vr].Area;
        Result.Nodes[row].BorderWidth := Result.Nodes[vr].BorderWidth;
        Result.Nodes[row].UpperHeight := Result.Nodes[vr].UpperHeight;
        Result.Nodes[row].UpperLabelHeight := Result.Nodes[vr].UpperLabelHeight;
        Result.Nodes[row].HasExtent := Result.Nodes[vr].HasExtent;
        Result.Nodes[row].ExtMin := Result.Nodes[vr].ExtMin;
        Result.Nodes[row].ExtMax := Result.Nodes[vr].ExtMax;
        Result.Nodes[row].IsLeafRoot := Result.Nodes[vr].IsLeafRoot;
      end;
    end;
    { THE ROOT'S POSITION: a rootRect's, else the target centred, else 0 }
    if (AView.Kind = tpkKeep) and samePrev then
    begin
      Result.Nodes[0].X := APrev.Nodes[0].X;
      Result.Nodes[0].Y := APrev.Nodes[0].Y;
    end
    else if AView.Kind in [tpkMove, tpkRender] then
    begin
      Result.Nodes[0].X := AView.RootX;
      Result.Nodes[0].Y := AView.RootY;
    end
    else if (AView.Kind in [tpkZoomToNode, tpkRootToNode]) and (AView.Target >= 0)
      and (AView.Target < n) and Result.Nodes[AView.Target].HasLayout then
    begin
      tcx := Result.Nodes[AView.Target].W / 2;
      tcy := Result.Nodes[AView.Target].H / 2;
      row := AView.Target;
      while row >= 0 do
      begin
        tcx := tcx + Result.Nodes[row].X;
        tcy := tcy + Result.Nodes[row].Y;
        row := Result.Hier.Nodes[row].Parent;
      end;
      Result.Nodes[0].X := Result.Box.W / 2 - tcx;
      Result.Nodes[0].Y := Result.Box.H / 2 - tcy;
    end
    else
    begin
      Result.Nodes[0].X := 0;
      Result.Nodes[0].Y := 0;
    end;
    { the canvas in root coordinates }
    Prune(Result, 0, -(Result.Box.X - AContainer.Left), -(Result.Box.Y - AContainer.Top), W, H, 0);
    { the container group at the box, then the nodes' own groups }
    cx := Result.Box.X;
    cy := Result.Box.Y;
    Result.ContainerX := cx;
    Result.ContainerY := cy;
    if Around0(cx) and Around0(cy) then
      Compose(Result, 0, False, 0, 0)
    else
      Compose(Result, 0, True, 0 + (0 + cx), 0 + (0 + cy));
    Result.Valid := True;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the colours ==================== }

type
  { the visuals a node carries: its colour -- none, a JSON value from the
    chain, or a palette entry -- and its saturation, inherited down }
  TTmColour = record
    Kind: Integer;              // 0 none, 1 json, 2 palette, 3 a mapped rgba
    Json: TJSONData;
    Pal: TTyChartColor;
    Vis: TTyVisualColor;
    HasSat: Boolean;
    Sat: Double;
    HasAlpha: Boolean;
    Alpha: Double;
  end;

{ getValueVisualDefine: null and 'none' are no colour }
function HasColourDefine(const V: TTmColour): Boolean;
begin
  case V.Kind of
    1: Result := (V.Json.JSONType <> jtNull)
         and not ((V.Json.JSONType = jtString) and (V.Json.AsString = 'none'));
    2: Result := True;
    3: Result := V.Vis.Defined;
  else
    Result := False;
  end;
end;

{ calculateColor: the colour, its lightness set by a truthy "saturation"
  (zrender's modifyHSL, whose fourth argument is L) }
function CalcColour(const V: TTmColour; out AColour: TTyVisualColor): Boolean;
begin
  Result := False;
  AColour := TyVisualUndefined;
  case V.Kind of
    1:
      if (V.Json.JSONType = jtString) and (V.Json.AsString <> 'none')
        and (V.Json.AsString <> '') then
        Result := TyVisualTryParse(V.Json.AsString, AColour);
    2:
      begin
        AColour := TyVisualFromChart(V.Pal);
        Result := True;
      end;
    3:
      begin
        AColour := V.Vis;
        Result := V.Vis.Defined;
      end;
  end;
  if Result and V.HasSat and (V.Sat <> 0) and not IsNan(V.Sat) then
    AColour := TyVisualModifyHSL(AColour, 0, 0, V.Sat, False, False, True);
  { then the alpha, a truthy one only: the channels kept [Batch 80] }
  if Result and V.HasAlpha and (V.Alpha <> 0) and not IsNan(V.Alpha) then
    AColour := TyVisualModifyAlpha(AColour, V.Alpha);
end;

{ util/number linearMap, clamped: the ends exact, a flat domain the middle }
function LinearMap(AVal, D0, D1, R0, R1: Double): Double;
var sd, sr: Double;
begin
  sd := D1 - D0;
  sr := R1 - R0;
  if sd = 0 then
  begin
    if sr = 0 then Exit(R0);
    Exit((R0 + R1) / 2);
  end;
  if sd > 0 then
  begin
    if AVal <= D0 then Exit(R0);
    if AVal >= D1 then Exit(R1);
  end
  else
  begin
    if AVal >= D0 then Exit(R0);
    if AVal <= D1 then Exit(R1);
  end;
  Result := (AVal - D0) / sd * sr + R0;
end;

procedure Travel(var S: TTyTreemapSolved; ARow: Integer; const ADv: TTmColour;
  const APalette: TTyChartColorArray; ABorder: TTyChartColor; AIds: TStringList);
var
  vis, cv: TTmColour;
  d, range, sr: TJSONData;
  it, lv: TJSONObject;
  k, len, dim, idx, mapKind: Integer;
  c: TTyChartColor;
  vc: TTyVisualColor;
  usePal, satMap, alphaMap: Boolean;
  r0, r1, n1, e0, e1: Double;
  by: string;
  stops: TTyVisualColorArray;

  { mapIdToIndex: one first-seen counter per series }
  function IdIndex(const AId: string): Integer;
  var q: Integer;
  begin
    if AIds.Find(AId, q) then Exit(PtrInt(AIds.Objects[q]));
    Result := AIds.Count;
    AIds.AddObject(AId, TObject(PtrInt(Result)));
  end;

  function Own(AObj: TJSONObject; const AKey: string = 'color'): TJSONData;
  var o: TJSONObject;
  begin
    Result := nil;
    o := ObjIn(AObj, 'itemStyle');
    if o = nil then Exit;
    Result := o.Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
  end;

begin
  if not S.Nodes[ARow].HasLayout or S.Nodes[ARow].Invisible
    or not S.Nodes[ARow].InView then Exit;
  vis := ADv;
  { item > level > the colour the parent designated > series }
  it := ItemOf(S, ARow);
  lv := LevelOf(S, ARow);
  d := Own(it);
  if d = nil then d := Own(lv);
  if (d = nil) and (ADv.Kind <> 0) then
    { the designated one: the visuals already carry it }
  else
  begin
    if d = nil then d := Own(S.Series);
    if d <> nil then
    begin
      vis.Kind := 1;
      vis.Json := d;
    end;
  end;
  { the saturation the same way: item > level > designated > series }
  d := Own(it, 'colorSaturation');
  if d = nil then d := Own(lv, 'colorSaturation');
  if (d = nil) and ADv.HasSat then
    { the designated one, already carried }
  else
  begin
    if d = nil then d := Own(S.Series, 'colorSaturation');
    if d <> nil then
    begin
      vis.HasSat := True;
      vis.Sat := JsNum(d);
    end;
  end;
  { and the alpha: item > level > designated > series [Batch 80] }
  d := Own(it, 'colorAlpha');
  if d = nil then d := Own(lv, 'colorAlpha');
  if (d = nil) and ADv.HasAlpha then
    { carried }
  else
  begin
    if d = nil then d := Own(S.Series, 'colorAlpha');
    if d <> nil then
    begin
      vis.HasAlpha := True;
      vis.Alpha := JsNum(d);
    end;
  end;
  { the border: the chain's, else the series default }
  S.Nodes[ARow].HasStroke := True;
  d := ChainFind(S, ARow, 'itemStyle', 'borderColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    S.Nodes[ARow].Stroke := c
  else
    S.Nodes[ARow].Stroke := ABorder;
  { borderColorSaturation, tested != null: the node's own colour (its
    saturation applied) re-lit; no colour, no border at all }
  d := ChainFind(S, ARow, 'itemStyle', 'borderColorSaturation');
  if d <> nil then
  begin
    S.Nodes[ARow].HasStroke := CalcColour(vis, vc);
    if S.Nodes[ARow].HasStroke then
      S.Nodes[ARow].Stroke := TyVisualToChart(
        TyVisualModifyHSL(vc, 0, 0, JsNum(d), False, False, True));
  end;
  { dataStyleTask, after the visual: the raw item's own border colour }
  d := Own(it, 'borderColor');
  if (d <> nil) and (d.JSONType = jtString) then
    S.Nodes[ARow].HasStroke := TyTryParseChartColor(d.AsString, S.Nodes[ARow].Stroke);
  if Length(S.Nodes[ARow].View) = 0 then
  begin
    S.Nodes[ARow].HasFill := CalcColour(vis, vc);
    S.Nodes[ARow].Fill := TyVisualToChart(vc);
    { and its own colour, over any saturation }
    d := Own(it);
    if (d <> nil) and (d.JSONType = jtString) then
      S.Nodes[ARow].HasFill := TyTryParseChartColor(d.AsString, S.Nodes[ARow].Fill);
    Exit;
  end;
  { the list this node maps its children by: item -> level (levels[0]
    holding the palette by setDefault) -> series }
  range := nil;
  usePal := False;
  if it <> nil then
  begin
    range := it.Find('color');
    if (range <> nil) and (range.JSONType = jtNull) then range := nil;
  end;
  if range = nil then
  begin
    if (S.Hier.Nodes[ARow].Depth = 0) and S.Level0Default then
      usePal := True
    else if lv <> nil then
    begin
      range := lv.Find('color');
      if (range <> nil) and (range.JSONType = jtNull) then range := nil;
    end;
  end;
  if (range = nil) and not usePal then
  begin
    range := S.Series.Find('color');
    if (range <> nil) and (range.JSONType = jtNull) then range := nil;
  end;
  if usePal then len := Length(APalette)
  else if (range <> nil) and (range.JSONType = jtArray) then len := range.Count
  else len := 0;
  { the extent a linear mapping reads: widened, never narrowed, by the
    chain's visualMin / visualMax [Batch 80] }
  e0 := S.Nodes[ARow].ExtMin;
  e1 := S.Nodes[ARow].ExtMax;
  d := ChainFind(S, ARow, '', 'visualMin');
  if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat < e0) then e0 := d.AsFloat;
  d := ChainFind(S, ARow, '', 'visualMax');
  if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat > e1) then e1 := d.AsFloat;
  dim := DimOf(S, ARow);
  { a colour list maps by index, by id, or -- anything else -- linearly }
  mapKind := 0;
  if len > 0 then
  begin
    d := ChainFind(S, ARow, '', 'colorMappingBy');
    if (d <> nil) and (d.JSONType = jtString) then by := d.AsString else by := 'index';
    if by = 'index' then mapKind := 0
    else if by = 'id' then mapKind := 1
    else
    begin
      mapKind := 2;
      SetLength(stops, len);
      for k := 0 to len - 1 do
        if usePal then stops[k] := TyVisualFromChart(APalette[k])
        else stops[k] := TyVisualParsedStop(range.Items[k]);
    end;
  end;
  { NO COLOUR LIST: an alpha range, else a saturation range, on this node's
    chain maps the children linearly -- if this node has a colour }
  satMap := False;
  alphaMap := False;
  r0 := 0;
  r1 := 0;
  if (len = 0) and HasColourDefine(vis) and S.Nodes[ARow].HasExtent then
  begin
    sr := ChainFind(S, ARow, '', 'colorAlpha');
    if (sr <> nil) and (sr.JSONType = jtArray) and (sr.Count > 0) then
      alphaMap := True
    else
    begin
      sr := ChainFind(S, ARow, '', 'colorSaturation');
      satMap := (sr <> nil) and (sr.JSONType = jtArray) and (sr.Count > 0);
    end;
    if alphaMap or satMap then
    begin
      r0 := JsNum(sr.Items[0]);
      if sr.Count > 1 then r1 := JsNum(sr.Items[1]) else r1 := r0;
    end;
  end;
  for k := 0 to High(S.Nodes[ARow].View) do
  begin
    cv := vis;
    if satMap or alphaMap then
    begin
      n1 := LinearMap(ValueAt(S, S.Nodes[ARow].View[k], dim), e0, e1, 0, 1);
      if alphaMap then
      begin
        cv.HasAlpha := True;
        cv.Alpha := LinearMap(n1, 0, 1, r0, r1);
      end
      else
      begin
        cv.HasSat := True;
        cv.Sat := LinearMap(n1, 0, 1, r0, r1);
      end;
    end;
    if len > 0 then
    begin
      if mapKind = 2 then
      begin
        { the value over the list: an rgba, or no colour at all }
        cv.Kind := 3;
        cv.Vis := TyVisualFastLerp(LinearMap(ValueAt(S, S.Nodes[ARow].View[k], dim),
          e0, e1, 0, 1), stops);
        if not cv.Vis.Defined then cv.Kind := 0;
      end
      else
      begin
        if mapKind = 1 then idx := IdIndex(S.Nodes[S.Nodes[ARow].View[k]].Id)
        else idx := k;
        if usePal then
        begin
          cv.Kind := 2;
          cv.Pal := APalette[idx mod len];
        end
        else
        begin
          cv.Kind := 1;
          cv.Json := range.Items[idx mod len];
          if cv.Json.JSONType = jtNull then cv.Kind := 0;
        end;
      end;
    end;
    Travel(S, S.Nodes[ARow].View[k], cv, APalette, ABorder, AIds);
  end;
end;

procedure TyTreemapColour(var ASolved: TTyTreemapSolved;
  const APalette: TTyChartColorArray; ABorder: TTyChartColor);
var none: TTmColour; ids: TStringList; mask: TFPUExceptionMask;
begin
  if not ASolved.Valid then Exit;
  none := Default(TTmColour);
  ids := TStringList.Create;
  { a NaN value -- a missing dimension -- maps to no colour, through
    comparisons that must not trap }
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    ids.Sorted := True;
    ids.CaseSensitive := True;
    Travel(ASolved, 0, none, APalette, ABorder, ids);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
    ids.Free;
  end;
end;

{ ==================== labels ==================== }

function TyTreemapLabelSpecs(const ASolved: TTyTreemapSolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
var
  row: Integer;
  base: TTyLabelSpec;
  lv, it: TJSONObject;
begin
  Result := nil;
  SetLength(Result, Length(ASolved.Hier.Nodes));
  for row := 0 to High(ASolved.Hier.Nodes) do
  begin
    base := ASeriesSpec;
    lv := LevelOf(ASolved, row);
    if lv <> nil then base := TyLabelSpecOfNode(ObjIn(lv, 'label'), ASolved.Series, base);
    it := ItemOf(ASolved, row);
    if it <> nil then base := TyLabelSpecOfNode(ObjIn(it, 'label'), ASolved.Series, base);
    { the mark places and cuts the words itself }
    base.OffsetXLogical := 0;
    base.OffsetYLogical := 0;
    base.Overflow := tloNone;
    Result[row] := base;
  end;
end;

function TyTreemapUpperSpecs(const ASolved: TTyTreemapSolved;
  const ABase: TTyLabelSpec): TTyLabelSpecArray;
var
  row: Integer;
  base: TTyLabelSpec;
  lv, it: TJSONObject;
begin
  Result := nil;
  SetLength(Result, Length(ASolved.Hier.Nodes));
  for row := 0 to High(ASolved.Hier.Nodes) do
  begin
    base := TyLabelSpecOfNode(ObjIn(ASolved.Series, 'upperLabel'), ASolved.Series, ABase);
    lv := LevelOf(ASolved, row);
    if lv <> nil then base := TyLabelSpecOfNode(ObjIn(lv, 'upperLabel'), ASolved.Series, base);
    it := ItemOf(ASolved, row);
    if it <> nil then base := TyLabelSpecOfNode(ObjIn(it, 'upperLabel'), ASolved.Series, base);
    { shown where the strip is; placed and cut by the mark }
    base.Show := True;
    base.OffsetXLogical := 0;
    base.OffsetYLogical := 0;
    base.Overflow := tloNone;
    Result[row] := base;
  end;
end;

{ THE CUT AND THE ANCHOR of a content label on a rect whose origin (shape x
  * 1 + the group's tx) is (ARX0, ARY0), ACW by ACH: padding (5, CSS
  shorthand), distance (0), position ('inside') by zrender's table; the
  words cut to the padded rect [Batch 115: from TyTreemapLabels, for the
  drill-down's frames too] }
function PlaceLabel(const ASolved: TTyTreemapSolved; ARow: Integer;
  const spec: TTyLabelSpec; const AText: string; ARX0, ARY0, ACW, ACH: Double;
  const AMeasurer: ITyTextMeasurer; out AWords: string; out ALX, ALY: Double;
  out AAH: TTyTextAnchorH; out AAV: TTyTextAnchorV): Boolean;
var
  k, j: Integer;
  pad, ps: string;
  rich: Boolean;
  cw, ch, rx, ry, dist, tw, th, ow, oh, bx, by, xl, lt, tokW, h_: Double;
  pd: array[0..3] of Double;
  lines: TStringArray;
  d: TJSONData;
begin
  cw := ACW;
  ch := ACH;
  for k := 0 to 3 do pd[k] := 5 * ASolved.Scale;
  d := ChainFind(ASolved, ARow, 'label', 'padding');
  if d <> nil then
  begin
    if d.JSONType = jtNumber then
      for k := 0 to 3 do pd[k] := d.AsFloat * ASolved.Scale
    else if (d.JSONType = jtArray) and (d.Count > 0) then
      for k := 0 to 3 do
      begin
        case d.Count of
          1: j := 0;
          2: j := k mod 2;
          3: if k = 3 then j := 1 else j := k;
        else
          j := k;
        end;
        pd[k] := JsNum(d.Items[j]) * ASolved.Scale;
      end;
  end;
  d := ChainFind(ASolved, ARow, 'label', 'distance');
  if d <> nil then dist := JsNum(d) * ASolved.Scale else dist := 0;
  d := ChainFind(ASolved, ARow, 'label', 'position');
  if (d <> nil) and (d.JSONType = jtString) then ps := d.AsString else ps := 'inside';
  rich := ChainFind(ASolved, ARow, 'label', 'rich') is TJSONObject;
  tw := JsMax(cw - pd[1] - pd[3], 0);
  th := JsMax(ch - pd[0] - pd[2], 0);
  lines := TyZrPlainTextLines(AText, tw, th, 2, '...', AMeasurer, spec.FontName,
    spec.FontSizeLogical, spec.FontWeight, rich);
  { the anchor in the content rect, by zrender's table }
  rx := ARX0;
  ry := ARY0;
  AAH := tahCentre;
  AAV := tavMiddle;
  if ps = 'insideLeft' then
  begin
    rx := rx + dist; ry := ry + ch / 2; AAH := tahLeft;
  end
  else if ps = 'insideRight' then
  begin
    rx := rx + (cw - dist); ry := ry + ch / 2; AAH := tahRight;
  end
  else if ps = 'insideTop' then
  begin
    rx := rx + cw / 2; ry := ry + dist; AAV := tavTop;
  end
  else if ps = 'insideBottom' then
  begin
    rx := rx + cw / 2; ry := ry + (ch - dist); AAV := tavBottom;
  end
  else if ps = 'insideTopLeft' then
  begin
    rx := rx + dist; ry := ry + dist;
    AAH := tahLeft; AAV := tavTop;
  end
  else if ps = 'insideTopRight' then
  begin
    rx := rx + (cw - dist); ry := ry + dist;
    AAH := tahRight; AAV := tavTop;
  end
  else if ps = 'insideBottomLeft' then
  begin
    rx := rx + dist; ry := ry + (ch - dist);
    AAH := tahLeft; AAV := tavBottom;
  end
  else if ps = 'insideBottomRight' then
  begin
    rx := rx + (cw - dist); ry := ry + (ch - dist);
    AAH := tahRight; AAV := tavBottom;
  end
  else
  begin
    rx := rx + cw / 2;
    ry := ry + ch / 2;
  end;
  if Around0(rx) and Around0(ry) then
  begin
    rx := 0;
    ry := 0;
  end;
  { where the words start from the anchor: the plain layout pads the
    side it is aligned to; the rich one places the OUTER box and puts
    the first line at its top }
  if rich and (Length(lines) > 0) then
  begin
    ow := tw + (pd[1] + pd[3]);
    oh := th + (pd[0] + pd[2]);
    case AAH of
      tahLeft: bx := 0;
      tahRight: bx := 0 - ow;
    else
      bx := 0 - ow / 2;
    end;
    case AAV of
      tavTop: by := 0;
      tavBottom: by := 0 - oh;
    else
      by := 0 - oh / 2;
    end;
    xl := bx + pd[3];
    lt := by + pd[0];
    AMeasurer.MeasureLine(lines[0], spec.FontName, spec.FontSizeLogical,
      spec.FontWeight, tokW, h_);
    case AAH of
      tahLeft: rx := rx + xl;
      tahRight: rx := rx + (xl + tw);
    else
      rx := rx + ((xl + (tw - (xl - xl) - ((xl + tw) - (xl + tw)) - tokW) / 2) + tokW / 2);
    end;
    ry := ry + lt;
    AAV := tavTop;
  end
  else
  begin
    case AAH of
      tahLeft: rx := rx + (0 + pd[3]);
      tahRight: rx := rx + (0 - pd[1]);
    else
      rx := rx + (0 + pd[3] / 2 - pd[1] / 2);
    end;
    case AAV of
      tavTop: ry := ry + pd[0];
      tavBottom: ry := ry - pd[2];
    end;
  end;
  Result := Length(lines) > 0;
  pad := '';
  AWords := '';
  for k := 0 to High(lines) do
  begin
    AWords := AWords + pad + lines[k];
    pad := #10;
  end;
  ALX := rx;
  ALY := ry;
end;

function TyTreemapLabelAt(const ASolved: TTyTreemapSolved; ARow: Integer;
  const ASpec: TTyLabelSpec; const AMeasurer: ITyTextMeasurer;
  AX0, AY0, ACW, ACH: Double; out AText: string; out ALX, ALY: Double): Boolean;
var
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  mask: TFPUExceptionMask;
begin
  AText := '';
  ALX := 0;
  ALY := 0;
  Result := False;
  if (AMeasurer = nil) or (ARow < 0) or (ARow > High(ASolved.Nodes))
    or not ASolved.Nodes[ARow].HasLabelRaw then Exit;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    Result := PlaceLabel(ASolved, ARow, ASpec, ASolved.Nodes[ARow].LabelRaw,
      AX0, AY0, JsMax(ACW, 0), JsMax(ACH, 0), AMeasurer, AText, ALX, ALY, ah, av);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

procedure TyTreemapLabels(var ASolved: TTyTreemapSolved;
  const ASpecs: TTyLabelSpecArray; AStore: TTyDataStore; const ASeriesName: string;
  AValueDim: Integer; const AMeasurer: ITyTextMeasurer);
var
  row, k, j: Integer;
  spec: TTyLabelSpec;
  text, pad, icon, ps: string;
  has, rich: Boolean;
  bw, cw, ch, rx, ry, dist, tw, th, ow, oh, bx, by, xl, lt, tokW, h_: Double;
  pd: array[0..3] of Double;
  lines: TStringArray;
  d: TJSONData;
  mask: TFPUExceptionMask;
begin
  if not ASolved.Valid or (AMeasurer = nil) then Exit;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    for row := 0 to High(ASolved.Nodes) do
    begin
      ASolved.Nodes[row].HasLabel := False;
      ASolved.Nodes[row].LabelText := '';
      ASolved.Nodes[row].HasLabelRaw := False;
      ASolved.Nodes[row].LabelRaw := '';
      if not ASolved.Nodes[row].HasLayout or not ASolved.Nodes[row].InView
        or ASolved.Nodes[row].Invisible or ASolved.Nodes[row].AboveView then Continue;
      if Length(ASolved.Nodes[row].View) > 0 then Continue;
      if row <= High(ASpecs) then spec := ASpecs[row] else Continue;
      if not spec.Show then Continue;
      { the formatter, else the chain's name }
      if spec.HasFormatter then
      begin
        text := TyLabelText(spec.Formatter, True, tldName, AStore, row,
          ASeriesName, AValueDim, NaN, False, ASolved.SeriesIndex, 'treemap');
        has := True;
      end
      else
        has := ChainName(ASolved, row, text);
      if not has then Continue;
      { a leaf root's words behind the series' OWN drill icon [Batch 80] }
      if ASolved.Nodes[row].IsLeafRoot then
      begin
        d := ASolved.Series.Find('drillDownIcon');
        if d = nil then icon := #$E2#$96#$B6
        else if (d.JSONType = jtString) then icon := d.AsString
        else icon := '';
        if icon <> '' then text := icon + ' ' + text;
      end;
      bw := ASolved.Nodes[row].BorderWidth;
      cw := JsMax(ASolved.Nodes[row].W - 2 * bw, 0);
      ch := JsMax(ASolved.Nodes[row].H - 2 * bw, 0);
      { the words before the cut, for a frame of the drill-down [Batch 115] }
      ASolved.Nodes[row].LabelRaw := text;
      ASolved.Nodes[row].HasLabelRaw := True;
      ASolved.Nodes[row].HasLabel := PlaceLabel(ASolved, row, spec, text,
        bw * 1 + ASolved.Nodes[row].TX, bw * 1 + ASolved.Nodes[row].TY, cw, ch,
        AMeasurer, ASolved.Nodes[row].LabelText, ASolved.Nodes[row].LabelX,
        ASolved.Nodes[row].LabelY, ASolved.Nodes[row].LabelAH, ASolved.Nodes[row].LabelAV);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ zrender's parsePercent: 'n%' of AMax, another string its number }
function ZrPct(AData: TJSONData; AMax: Double): Double;
var s: string;
begin
  Result := 0;
  if AData = nil then Exit;
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  if AData.JSONType = jtString then
  begin
    s := AData.AsString;
    if (s <> '') and (Pos('%', s) > 0) then
      Result := TyJsParseFloat(s) / 100 * AMax
    else
      Result := TyJsParseFloat(s);
  end;
end;

procedure TyTreemapUpperLabels(var ASolved: TTyTreemapSolved;
  const ASpecs: TTyLabelSpecArray; AStore: TTyDataStore; const ASeriesName: string;
  AValueDim: Integer; const AMeasurer: ITyTextMeasurer);
var
  row, k, j: Integer;
  spec: TTyLabelSpec;
  nd: TTyTreemapNode;
  d, pos: TJSONData;
  text, sep: string;
  has, inside: Boolean;
  rx, ry, rw, rh, w, h, ax, ay, tx: Double;
  pad: array[0..3] of Double;
  lines: TStringArray;
  mask: TFPUExceptionMask;
begin
  if not ASolved.Valid or (AMeasurer = nil) then Exit;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    for row := 0 to High(ASolved.Nodes) do
    begin
      ASolved.Nodes[row].HasUpper := False;
      nd := ASolved.Nodes[row];
      if not nd.HasLayout or not nd.InView or nd.Invisible or nd.AboveView then Continue;
      { A PARENT whose strip is reserved; a leaf never has one }
      if Length(nd.View) = 0 then Continue;
      if (nd.UpperLabelHeight = 0) or IsNan(nd.UpperLabelHeight) then Continue;
      if row <= High(ASpecs) then spec := ASpecs[row] else Continue;
      { upperLabel's formatter, else label's, else the chain's name }
      has := False;
      text := '';
      d := ChainFind(ASolved, row, 'upperLabel', 'formatter');
      if (d = nil) or (d.JSONType <> jtString) or (d.AsString = '') then
        d := ChainFind(ASolved, row, 'label', 'formatter');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
      begin
        text := TyLabelText(d.AsString, True, tldName, AStore, row, ASeriesName,
          AValueDim, NaN, False, ASolved.SeriesIndex, 'treemap');
        has := True;
      end
      else
        has := ChainName(ASolved, row, text);
      if not has or (text = '') then Continue;
      { the strip: the background's top, in its group's frame }
      rx := nd.BorderWidth * 1 + nd.TX;
      ry := 0 * 1 + nd.TY;
      rw := nd.W - 2 * nd.BorderWidth;
      rh := nd.UpperHeight;
      if not nd.HasT then
      begin
        rx := nd.BorderWidth;
        ry := 0;
      end
      else if rw < 0 then
      begin
        rx := rx + rw;
        rw := -rw;
      end;
      { padding: none by default, CSS shorthand }
      for k := 0 to 3 do pad[k] := 0;
      d := ChainFind(ASolved, row, 'upperLabel', 'padding');
      if d <> nil then
      begin
        if d.JSONType = jtNumber then
          for k := 0 to 3 do pad[k] := d.AsFloat * ASolved.Scale
        else if (d.JSONType = jtArray) and (d.Count > 0) then
        begin
          for k := 0 to 3 do
          begin
            case d.Count of
              1: j := 0;
              2: j := k mod 2;
              3: if k = 3 then j := 1 else j := k;
            else
              j := k;
            end;
            pad[k] := JsNum(d.Items[j]) * ASolved.Scale;
          end;
        end;
      end;
      w := JsMax(nd.W - 2 * nd.BorderWidth - pad[1] - pad[3], 0);
      h := JsMax(nd.UpperHeight - pad[0] - pad[2], 0);
      lines := TyZrPlainTextLines(text, w, h, 2, '...', AMeasurer, spec.FontName,
        spec.FontSizeLogical, spec.FontWeight);
      if Length(lines) = 0 then Continue;
      { [0, '50%'] by default: left, middle; 'inside' the centre }
      pos := ChainFind(ASolved, row, 'upperLabel', 'position');
      inside := (pos <> nil) and (pos.JSONType = jtString) and (pos.AsString = 'inside');
      if inside then
      begin
        ax := rx + rw / 2;
        ay := ry + rh / 2;
        tx := 0 + pad[3] / 2 - pad[1] / 2;
      end
      else
      begin
        if (pos <> nil) and (pos.JSONType = jtArray) and (pos.Count >= 2) then
        begin
          ax := rx + ZrPct(pos.Items[0], rw);
          ay := ry + ZrPct(pos.Items[1], rh);
        end
        else
        begin
          ax := rx + 0;
          ay := ry + 50 / 100 * rh;
        end;
        tx := 0 + pad[3];
      end;
      if Around0(ax) and Around0(ay) then
      begin
        ax := 0;
        ay := 0;
      end;
      sep := '';
      text := '';
      for k := 0 to High(lines) do
      begin
        text := text + sep + lines[k];
        sep := #10;
      end;
      if text = '' then Continue;
      ASolved.Nodes[row].HasUpper := True;
      ASolved.Nodes[row].UpperText := text;
      ASolved.Nodes[row].UpperX := tx + ax;
      ASolved.Nodes[row].UpperY := ay;
      ASolved.Nodes[row].UpperCentre := inside;
      ASolved.Nodes[row].UpperInside := inside;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the breadcrumb ==================== }

{ ==================== the storage and the hit ==================== }

function TyTreemapHaveOf(const ASolved: TTyTreemapSolved;
  const APrev: TTyTreemapHave): TTyTreemapHave;
var n: Integer;

  function Was(const A: array of Boolean; ARow: Integer): Boolean;
  begin
    Result := (ARow >= 0) and (ARow <= High(A)) and A[ARow];
  end;

  { renderNode: a group reused, or made where the node is not outside the
    canvas; none -- the subtree is not visited }
  procedure Visit(ARow: Integer);
  var k: Integer; inv: Boolean;
  begin
    if not ASolved.Nodes[ARow].HasLayout or not ASolved.Nodes[ARow].InView then Exit;
    inv := ASolved.Nodes[ARow].Invisible;
    if inv and not Was(APrev.Group, ARow) then Exit;
    Result.Group[ARow] := True;
    if not ASolved.Nodes[ARow].AboveView then
    begin
      Result.Bg[ARow] := (not inv) or Was(APrev.Bg, ARow);
      if Length(ASolved.Nodes[ARow].View) = 0 then
        Result.Ct[ARow] := (not inv) or Was(APrev.Ct, ARow);
    end;
    for k := 0 to High(ASolved.Nodes[ARow].View) do Visit(ASolved.Nodes[ARow].View[k]);
  end;

begin
  Result := Default(TTyTreemapHave);
  if not ASolved.Valid then Exit;
  n := Length(ASolved.Nodes);
  SetLength(Result.Group, n);
  SetLength(Result.Bg, n);
  SetLength(Result.Ct, n);
  Visit(0);
end;

type
  TTmTrans = record
    HasT: Boolean;
    TX, TY: Double;
  end;
  TTmTransArray = array of TTmTrans;

{ findTarget from the view root: pre-order over the viewChildren, a
  background holding the point continues into its children, one that does
  not stops there; a node without a background is passed through }
function FindIn(const ASolved: TTyTreemapSolved; const AHave: TTyTreemapHave;
  const ATrans: TTmTransArray; AX, AY: Double): Integer;
var found: Integer;

  procedure Visit(ARow: Integer);
  var k: Integer; lx, ly: Double;
  begin
    if (ARow <= High(AHave.Bg)) and AHave.Bg[ARow] then
    begin
      { transformCoordToLocal: through the inverse of the last transform }
      lx := AX;
      ly := AY;
      if (ARow <= High(ATrans)) and ATrans[ARow].HasT then
      begin
        lx := AX - ATrans[ARow].TX;
        ly := AY - ATrans[ARow].TY;
      end;
      if not ((0 <= lx) and (lx <= 0 + ASolved.Nodes[ARow].W)
        and (0 <= ly) and (ly <= 0 + ASolved.Nodes[ARow].H)) then Exit;
      found := ARow;
    end;
    for k := 0 to High(ASolved.Nodes[ARow].View) do Visit(ASolved.Nodes[ARow].View[k]);
  end;

begin
  found := -1;
  if ASolved.Valid then Visit(ASolved.ViewRoot);
  Result := found;
end;

function TyTreemapFindTarget(const ASolved: TTyTreemapSolved; const AHave: TTyTreemapHave;
  AX, AY: Double): Integer;
var
  tr: TTmTransArray;
  row: Integer;
begin
  tr := nil;
  SetLength(tr, Length(ASolved.Nodes));
  for row := 0 to High(ASolved.Nodes) do
  begin
    tr[row].HasT := ASolved.Nodes[row].HasT;
    tr[row].TX := ASolved.Nodes[row].TX;
    tr[row].TY := ASolved.Nodes[row].TY;
  end;
  Result := FindIn(ASolved, AHave, tr, AX, AY);
end;

procedure TyTreemapBreadcrumb(var ASolved: TTyTreemapSolved;
  const ACrumbSpec: TTyLabelSpec; const AMeasurer: ITyTextMeasurer;
  const AContainer: TTyRectF);
begin
  TyTreemapBreadcrumb(ASolved, ACrumbSpec, AMeasurer, AContainer, -1,
    TyTreemapHaveOf(ASolved, Default(TTyTreemapHave)), Default(TTyTreemapHave),
    Default(TTyTreemapSolved));
end;

procedure TyTreemapBreadcrumb(var ASolved: TTyTreemapSolved;
  const ACrumbSpec: TTyLabelSpec; const AMeasurer: ITyTextMeasurer;
  const AContainer: TTyRectF; ATarget: Integer; const AHave, APrevHave: TTyTreemapHave;
  const APrev: TTyTreemapSolved);
const
  cKey: array[0..3] of string = ('left', 'right', 'top', 'bottom');
var
  bc: TJSONObject;
  d: TJSONData;
  target, row, n, i, k, j: Integer;
  W, H, px, py, sc, total, iw, tw, lw, hh, emptyW, lastX, x, y, x0, y0, x1, y1,
    rx, ry, rw, rh, ux, uy, gx, gy, tx, ty: Double;
  path: TTyIntegerArray;
  texts: array of string;
  widths: array of Double;
  box: TTyRawBox;
  avail, pos: TTyXYWH;
  keys: array[0..3] of TTyBoxRaw;
  lines: TStringArray;
  head, tail, hasG: Boolean;
  pts: array of TTyPointF;
  bb: array of TTyXYWH;
  polys: array of array of TTyPointF;
  shown: array of string;
  mask: TFPUExceptionMask;
  tr: TTmTransArray;
  r2: Integer;

  function Measure(const AText: string): Double;
  var w_, h_: Double;
  begin
    if AText = '' then Exit(0);
    AMeasurer.MeasureLine(AText, ACrumbSpec.FontName, ACrumbSpec.FontSizeLogical,
      ACrumbSpec.FontWeight, w_, h_);
    Result := w_;
  end;

  function Scaled(const R: TTyBoxRaw): TTyBoxRaw;
  begin
    Result := R;
    if R.Kind = brNumber then Result.Num := R.Num * sc;
  end;

begin
  ASolved.Crumbs := nil;
  if not ASolved.Valid or (AMeasurer = nil) then Exit;
  bc := ObjIn(ASolved.Series, 'breadcrumb');
  if bc <> nil then
  begin
    d := bc.Find('show');
    if (d <> nil) and not Truthy(d) then Exit;
  end;
  sc := ASolved.Scale;
  hh := 22;
  emptyW := 25;
  if bc <> nil then
  begin
    d := bc.Find('height');
    if (d <> nil) and (d.JSONType = jtNumber) then hh := d.AsFloat;
    d := bc.Find('emptyItemWidth');
    if (d <> nil) and (d.JSONType = jtNumber) then emptyW := d.AsFloat;
  end;
  hh := hh * sc;
  emptyW := emptyW * sc;
  keys[0] := TyBoxRawStr('center');
  keys[1] := TyBoxRawOf(nil);
  keys[2] := TyBoxRawOf(nil);
  keys[3] := TyBoxRawNum(15);
  if bc <> nil then
    for k := 0 to 3 do
    begin
      d := bc.Find(cKey[k]);
      if d <> nil then keys[k] := TyBoxRawOf(d);
    end;
  W := AContainer.Right - AContainer.Left;
  H := AContainer.Bottom - AContainer.Top;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    { THE TARGET: the payload's; else, under a series leafDepth, the view
      root [Batch 80]; else the node under the canvas centre as the
      backgrounds were LAST PAINTED: a kept one through the transform of the
      last render, a new one through none -- on the first frame every one,
      so the centre is tested against each node's own (0, 0, w, h)
      [Batch 115] }
    px := W / 2;
    py := H / 2;
    target := -1;
    if (ATarget >= 0) and (ATarget <= High(ASolved.Nodes)) then target := ATarget
    else if ASolved.HasLeafDepth then target := ASolved.ViewRoot
    else
    begin
      tr := nil;
      SetLength(tr, Length(ASolved.Nodes));
      if APrev.Valid and (Length(APrev.Nodes) = Length(ASolved.Nodes)) then
        for r2 := 0 to High(ASolved.Nodes) do
          if (r2 <= High(APrevHave.Bg)) and APrevHave.Bg[r2]
            and (r2 <= High(AHave.Bg)) and AHave.Bg[r2] then
          begin
            tr[r2].HasT := APrev.Nodes[r2].HasT;
            tr[r2].TX := APrev.Nodes[r2].TX;
            tr[r2].TY := APrev.Nodes[r2].TY;
          end;
      target := FindIn(ASolved, AHave, tr, px, py);
    end;
    if target < 0 then target := 0;
    { the path, target first }
    path := nil;
    row := target;
    while row >= 0 do
    begin
      SetLength(path, Length(path) + 1);
      path[High(path)] := row;
      row := ASolved.Hier.Nodes[row].Parent;
    end;
    n := Length(path);
    SetLength(texts, n);
    SetLength(widths, n);
    total := 0;
    for i := 0 to n - 1 do
    begin
      if not ChainName(ASolved, path[i], texts[i]) then texts[i] := '';
      tw := 0;
      if texts[i] <> '' then
      begin
        lines := texts[i].Split([#10]);
        for j := 0 to High(lines) do
        begin
          lw := Measure(lines[j]);
          if (j = 0) or (lw > tw) then tw := lw;
        end;
      end;
      iw := JsMax(tw + 8 * sc * 2, emptyW);
      total := total + (iw + 8 * sc);
      widths[i] := iw;
    end;
    box := Default(TTyRawBox);
    box.Left := Scaled(keys[0]);
    box.Right := Scaled(keys[1]);
    box.Top := Scaled(keys[2]);
    box.Bottom := Scaled(keys[3]);
    box.Width := TyBoxRawOf(nil);
    box.Height := TyBoxRawOf(nil);
    avail := TyGetLayoutRect(box, 0, 0, W, H, []);
    lastX := 0;
    SetLength(polys, n);
    SetLength(bb, n);
    SetLength(shown, n);
    j := 0;
    for i := n - 1 downto 0 do
    begin
      iw := widths[i];
      shown[j] := texts[i];
      if total > avail.W then
      begin
        total := total - (iw - emptyW);
        iw := emptyW;
        shown[j] := '';
      end;
      head := i = n - 1;
      tail := i = 0;
      x := lastX;
      y := 0;
      pts := nil;
      if head then SetLength(pts, 4) else SetLength(pts, 4);
      if head then pts[0] := TyPointF(x, y) else pts[0] := TyPointF(x - 5 * sc, y);
      pts[1] := TyPointF(x + iw, y);
      pts[2] := TyPointF(x + iw, y + hh);
      if head then pts[3] := TyPointF(x, y + hh) else pts[3] := TyPointF(x - 5 * sc, y + hh);
      if not tail then
      begin
        SetLength(pts, Length(pts) + 1);
        for k := High(pts) downto 3 do pts[k] := pts[k - 1];
        pts[2] := TyPointF(x + iw + 5 * sc, y + hh / 2);
      end;
      if not head then
      begin
        SetLength(pts, Length(pts) + 1);
        pts[High(pts)] := TyPointF(x, y + hh / 2);
      end;
      polys[j] := pts;
      lastX := lastX + (iw + 8 * sc);
      Inc(j);
    end;
    { the group's rect: the polygons' boxes united as zrender unites them }
    rx := 0; ry := 0; rw := 0; rh := 0;
    for j := 0 to n - 1 do
    begin
      x0 := Infinity; y0 := Infinity; x1 := NegInfinity; y1 := NegInfinity;
      for k := 0 to High(polys[j]) do
      begin
        x0 := Min(x0, polys[j][k].X);
        y0 := Min(y0, polys[j][k].Y);
        x1 := Max(x1, polys[j][k].X);
        y1 := Max(y1, polys[j][k].Y);
      end;
      bb[j] := TyXYWH(x0 * 1 + 0, y0 * 1 + 0, (x1 - x0) * 1, (y1 - y0) * 1);
      if j = 0 then
      begin
        rx := bb[j].X; ry := bb[j].Y; rw := bb[j].W; rh := bb[j].H;
      end;
      ux := Min(bb[j].X, rx);
      uy := Min(bb[j].Y, ry);
      rw := Max(bb[j].X + bb[j].W, rx + rw) - ux;
      rh := Max(bb[j].Y + bb[j].H, ry + rh) - uy;
      rx := ux;
      ry := uy;
    end;
    box.Width := TyBoxRawNum(rw);
    box.Height := TyBoxRawNum(rh);
    pos := TyGetLayoutRect(box, 0, 0, W, H, []);
    gx := 0 + (pos.X - rx);
    gy := 0 + (pos.Y - ry);
    hasG := not (Around0(gx) and Around0(gy));
    if not hasG then
    begin
      gx := 0;
      gy := 0;
    end;
    SetLength(ASolved.Crumbs, n);
    for j := 0 to n - 1 do
    begin
      ASolved.Crumbs[j].Row := path[n - 1 - j];
      ASolved.Crumbs[j].Text := shown[j];
      SetLength(ASolved.Crumbs[j].Points, Length(polys[j]));
      for k := 0 to High(polys[j]) do
        ASolved.Crumbs[j].Points[k] := TyPointF(
          polys[j][k].X + gx + AContainer.Left, polys[j][k].Y + gy + AContainer.Top);
      tx := (bb[j].X * 1 + gx) + bb[j].W / 2;
      ty := (bb[j].Y * 1 + gy) + bb[j].H / 2;
      if Around0(tx) and Around0(ty) then
      begin
        tx := 0;
        ty := 0;
      end;
      ASolved.Crumbs[j].LabelX := tx + AContainer.Left;
      ASolved.Crumbs[j].LabelY := ty + AContainer.Top;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the marks ==================== }

function TyBuildTreemapMarks(ASeriesIndex: Integer; const ASolved: TTyTreemapSolved;
  const AInk: TTyTreemapInk; AList: TTyPaintList): Integer;
var
  maxZ2, cnt: Integer;

  procedure Walk(ARow, ADepth: Integer);
  var
    nd: TTyTreemapNode;
    el: TTyChartElement;
    k, z2: Integer;
    bw, cw, ch: Double;
  begin
    nd := ASolved.Nodes[ARow];
    if not nd.HasLayout or not nd.InView then Exit;
    { ABOVE THE VIEW ROOT: a group and nothing else; its (stale)
      viewChildren lead down the path [Batch 115] }
    if nd.AboveView then
    begin
      for k := 0 to High(nd.View) do Walk(nd.View[k], ADepth + 1);
      Exit;
    end;
    if nd.Invisible and not nd.DrawInvisible then Exit;
    { the background, in the border colour }
    z2 := ADepth * 100 + 20;
    el := TyChartElement(TyShapeRect(TyRectF(0 + nd.TX, 0 + nd.TY,
      (0 + nd.W) + nd.TX, (0 + nd.H) + nd.TY)));
    el.Style.HasFill := nd.HasStroke;
    el.Style.FillColor := nd.Stroke;
    el.Z := ASolved.Z;
    el.Z2 := z2;
    el.Datum := TyChartDatum(ASeriesIndex, ARow, ARow);
    { THE DRILL-DOWN'S VIEW: a background's local shape [Batch 115] }
    el.Anim.Role := carTmRect;
    el.Anim.Series := ASeriesIndex;
    el.Anim.Index := ARow;
    el.Anim.Sub := 0;
    el.Anim.G[0] := 0;
    el.Anim.G[1] := 0;
    el.Anim.G[2] := nd.W;
    el.Anim.G[3] := nd.H;
    { A UNIVERSAL TRANSITION'S VIEW [Batch 138]: G[4] 1 where the node is a
      leaf (its background is disableMorphing: the content is the item's
      path); G[5..7] its group's computed transform -- whether there is
      one, and the translation }
    el.Anim.G[4] := Ord(Length(nd.View) = 0);
    el.Anim.G[5] := Ord(nd.HasT);
    el.Anim.G[6] := nd.TX;
    el.Anim.G[7] := nd.TY;
    { the node takes the pointer -- TyChartElement starts silent [Batch 84] }
    el.Silent := False;
    if z2 > maxZ2 then maxZ2 := z2;
    { a parent's header hangs off its background [Batch 78] }
    if nd.HasUpper then
    begin
      el.Caption.Text := nd.UpperText;
      el.Caption.ItemSpec := Length(ASolved.Nodes) + 2 + ARow;
      el.Caption.HasFixedAnchor := True;
      el.Caption.FixedX := nd.UpperX;
      el.Caption.FixedY := nd.UpperY;
      el.Caption.FixedInside := nd.UpperInside;
      if nd.UpperCentre then el.Caption.FixedAH := tahCentre
      else el.Caption.FixedAH := tahLeft;
      el.Caption.FixedAV := tavMiddle;
      el.Caption.HasFixedZ2 := True;
      el.Caption.FixedZ2 := maxZ2 + 2;
    end;
    AList.Add(el);
    Inc(cnt);
    if Length(nd.View) = 0 then
    begin
      bw := nd.BorderWidth;
      cw := JsMax(nd.W - 2 * bw, 0);
      ch := JsMax(nd.H - 2 * bw, 0);
      z2 := ADepth * 100 + 30;
      el := TyChartElement(TyShapeRect(TyRectF(bw + nd.TX, bw + nd.TY,
        (bw + cw) + nd.TX, (bw + ch) + nd.TY)));
      el.Style.HasFill := nd.HasFill;
      el.Style.FillColor := nd.Fill;
      el.Z := ASolved.Z;
      el.Z2 := z2;
      el.Datum := TyChartDatum(ASeriesIndex, ARow, ARow);
      el.Silent := False;
      el.Anim.Role := carTmRect;
      el.Anim.Series := ASeriesIndex;
      el.Anim.Index := ARow;
      el.Anim.Sub := 1;
      el.Anim.G[0] := bw;
      el.Anim.G[1] := bw;
      el.Anim.G[2] := cw;
      el.Anim.G[3] := ch;
      el.Anim.G[4] := 0;
      el.Anim.G[5] := Ord(nd.HasT);
      el.Anim.G[6] := nd.TX;
      el.Anim.G[7] := nd.TY;
      if z2 > maxZ2 then maxZ2 := z2;
      if nd.HasLabel and (nd.LabelText <> '') then
      begin
        el.Caption.Text := nd.LabelText;
        el.Caption.ItemSpec := ARow + 1;
        el.Caption.HasFixedAnchor := True;
        el.Caption.FixedX := nd.LabelX;
        el.Caption.FixedY := nd.LabelY;
        el.Caption.FixedInside := True;
        el.Caption.FixedAH := nd.LabelAH;
        el.Caption.FixedAV := nd.LabelAV;
        el.Caption.HasFixedZ2 := True;
        el.Caption.FixedZ2 := maxZ2 + 2;
      end;
      AList.Add(el);
      Inc(cnt);
    end;
    for k := 0 to High(nd.View) do Walk(nd.View[k], ADepth + 1);
  end;

var
  j: Integer;
  el: TTyChartElement;
begin
  Result := 0;
  if (AList = nil) or not ASolved.Valid then Exit;
  maxZ2 := Low(Integer);
  cnt := 0;
  Walk(0, 0);
  Result := cnt;
  { the breadcrumb: pale arrows, their words over them; painted, not hit }
  for j := 0 to High(ASolved.Crumbs) do
  begin
    el := TyChartElement(TyShapePolygon(ASolved.Crumbs[j].Points));
    el.Style.HasFill := True;
    el.Style.FillColor := AInk.CrumbFill;
    el.Z := ASolved.Z;
    el.Z2 := 100000;
    el.Silent := True;
    el.Datum := TyChartDatum(ASeriesIndex, ASolved.Crumbs[j].Row, ASolved.Crumbs[j].Row);
    if ASolved.Crumbs[j].Text <> '' then
    begin
      el.Caption.Text := ASolved.Crumbs[j].Text;
      { the breadcrumb's own spec, after the rows' }
      el.Caption.ItemSpec := Length(ASolved.Nodes) + 1;
      el.Caption.HasFixedAnchor := True;
      el.Caption.FixedX := ASolved.Crumbs[j].LabelX;
      el.Caption.FixedY := ASolved.Crumbs[j].LabelY;
      el.Caption.FixedInside := True;
      el.Caption.FixedAH := tahCentre;
      el.Caption.FixedAV := tavMiddle;
      el.Caption.HasFixedZ2 := True;
      el.Caption.FixedZ2 := 100002;
    end;
    AList.Add(el);
    Inc(Result);
  end;
end;

end.
