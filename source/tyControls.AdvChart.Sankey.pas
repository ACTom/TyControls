unit tyControls.AdvChart.Sankey;
{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}
{ The sankey series: nodes in columns, links as bands whose width is their
  value, the whole drawn in a box (5% round, 20% right for the labels).

  THE GRAPH: nodes keyed by id, else name, else index; a numeric link end
  is an INDEX into the nodes, a numeric string a key; links that miss are
  dropped. A duplicate key or a cycle makes upstream throw -- here the
  series is refused and draws nothing.

  THE LAYOUT is sankeyLayout.ts statement for statement: a node's value is
  the largest of its two link sums and its own; its depth the Kahn layer,
  moved by nodeAlign; columns grouped by the scaled breadth; ONE ky for the
  whole chart; collisions resolved with a stable in-place sort; then the
  relaxation -- alpha a running product of 0.99, Gauss-Seidel -- switched
  off entirely when any node's value is nought; links stacked by the other
  node's top. No rounding anywhere.

  THE COLOURS: each node's value mapped linearly over the palette (the
  series' colour list, the chart's, the theme's), as rgba; an itemStyle
  colour on the chain wins. A link is its lineStyle colour -- or its source
  or target node's, or a gradient between the two over its own box.

  THE LABELS: the node's id by default, placed by zrender's text position
  table against the rect grown by its stroke, z2 12.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Labels,
  tyControls.AdvChart.LabelOpt, tyControls.AdvChart.Calendar,
  tyControls.AdvChart.VisualMap;

const
  TySankeySeriesTypeName = 'sankey';

type
  TTySankeyNode = record
    Item: TJSONObject;                 // borrowed; nil for a non-object item
    Key: string;
    Value, Depth: Double;
    X, Y, DX, DY: Double;              // LOCAL to the box
    SkHeight: Integer;
    OutE, InE: TTyIntegerArray;        // edge indices
    HasColour: Boolean;
    IsString: Boolean;                 // upstream holds a string (mapped or written)
    Colour: TTyChartColor;
    { an itemStyle colour written as a gradient object: the rect's fill,
      and a 'source' / 'target' link's [Batch 79] }
    HasGradient: Boolean;
    Gradient: TTyChartGradient;
    { the label, placed }
    HasLabel: Boolean;
    LabelText: string;
    LabelX, LabelY: Double;
    LabelAH: TTyTextAnchorH;
    LabelAV: TTyTextAnchorV;
    LabelInside: Boolean;
  end;

  TTySankeyEdge = record
    Item: TJSONObject;
    Source, Target: Integer;
    Value: Double;
    DY, SY, TY: Double;
  end;

  TTySankeySolved = record
    Valid: Boolean;
    Series: TJSONObject;               // borrowed
    Box: TTyXYWH;
    HasT: Boolean;
    TX, TY: Double;
    Vertical: Boolean;
    NodeWidth, NodeGap: Double;
    Nodes: array of TTySankeyNode;
    Edges: array of TTySankeyEdge;
    LevelKeys: array of string;
    LevelObjs: array of TJSONObject;
    Z: Integer;
    Scale: Double;
  end;

  TTySankeyInk = record
    Label_: TTyLabelSpec;
    ItemLabels: TTyLabelSpecArray;
    { the link's default fill (upstream's neutral50) }
    LinkColour: TTyChartColor;
  end;

function TySankeySolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer): TTySankeySolved;
{ The node colours: AStops the palette as zrender parses it. }
procedure TySankeyColour(var ASolved: TTySankeySolved;
  const AStops: TTyVisualColorArray);
{ One label spec per node: item -> levels[layout depth] -> series. }
function TySankeyLabelSpecs(const ASolved: TTySankeySolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
{ The labels' words and anchors. }
procedure TySankeyLabels(var ASolved: TTySankeySolved; const ASeriesName: string);
{ The links (z2 0), then the nodes (z2 10) with their captions (z2 12). }
function TyBuildSankeyMarks(ASeriesIndex: Integer; const ASolved: TTySankeySolved;
  const AInk: TTySankeyInk; AList: TTyPaintList): Integer;

implementation

uses tyControls.AdvChart.Scale;

const
  cEps = 5e-5;
  cAlphaDecay: Double = 0.99;

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

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function Around0(V: Double): Boolean;
begin
  Result := not ((V > cEps) or (V < -cEps));
end;

function Present(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType <> jtNull);
end;

{ the level of a node by its LAYOUT depth, keyed as a JS object key }
function LevelOf(const S: TTySankeySolved; ADepth: Double): TJSONObject;
var k: Integer; key: string;
begin
  Result := nil;
  if IsNan(ADepth) then key := 'NaN' else key := TyJsNumberToString(ADepth);
  for k := High(S.LevelKeys) downto 0 do
    if S.LevelKeys[k] = key then Exit(S.LevelObjs[k]);
end;

{ Model.get along item -> level -> series: the whole path in each }
function ChainFind(const S: TTySankeySolved; AItem: TJSONObject; ADepth: Double;
  const ASub, AKey: string): TJSONData;
var
  k: Integer;
  chain: array[0..2] of TJSONObject;
  o: TJSONObject;
  d: TJSONData;
begin
  Result := nil;
  chain[0] := AItem;
  chain[1] := LevelOf(S, ADepth);
  chain[2] := S.Series;
  for k := 0 to 2 do
  begin
    if chain[k] = nil then Continue;
    if ASub <> '' then o := ObjIn(chain[k], ASub) else o := chain[k];
    if o = nil then Continue;
    d := o.Find(AKey);
    if Present(d) then Exit(d);
  end;
end;

{ ==================== the layout ==================== }

type
  TCmpFn = function(A, B: Integer): Double is nested;

{ insertion sort: moves only on > 0 -- NaN and ties stay put, as a stable
  sort with this comparator leaves them }
procedure StableSort(var A: TTyIntegerArray; ACmp: TCmpFn);
var i, j, v: Integer;
begin
  for i := 1 to High(A) do
  begin
    v := A[i];
    j := i - 1;
    while (j >= 0) and (ACmp(A[j], v) > 0) do
    begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := v;
  end;
end;

function TySankeySolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer): TTySankeySolved;
const
  cBoxKey: array[0..5] of string = ('width', 'left', 'right', 'height', 'top', 'bottom');
var
  mask: TFPUExceptionMask;
  node, d, arr, ln: TJSONData;
  S: ^TTySankeySolved;
  n, m, i, j, k, x, iterations, h, t, lo: Integer;
  keys: array of string;
  indeg, zero, next, rem, nsrc: TTyIntegerArray;
  remain: array of Boolean;
  maxNodeDepth, maxDepth, kx, minKy, sum, ky, viewWidth, alpha, sy, ty_,
    CW, CH, v1, v2, raw: Double;
  align: string;
  colKeys: TTyDoubleArray;
  cols, sorted: array of TTyIntegerArray;
  order: TTyIntegerArray;
  found: Boolean;
  raw6, target: TTyCalBoxKeys;
  box: TTyRawBox;
  scale: Double;

  function Scaled(const R: TTyBoxRaw): TTyBoxRaw;
  begin
    Result := R;
    if R.Kind = brNumber then Result.Num := R.Num * scale;
  end;

  { posd along the column, the size from the value, the breadth }
  function GetPos(ANode: Integer): Double;
  begin
    if S^.Vertical then Result := S^.Nodes[ANode].X else Result := S^.Nodes[ANode].Y;
  end;
  procedure SetPos(ANode: Integer; AV: Double);
  begin
    if S^.Vertical then S^.Nodes[ANode].X := AV else S^.Nodes[ANode].Y := AV;
  end;
  function GetSize(ANode: Integer): Double;
  begin
    if S^.Vertical then Result := S^.Nodes[ANode].DX else Result := S^.Nodes[ANode].DY;
  end;
  function GetBreadth(ANode: Integer): Double;
  begin
    if S^.Vertical then Result := S^.Nodes[ANode].Y else Result := S^.Nodes[ANode].X;
  end;
  function Center(ANode: Integer): Double;
  begin
    Result := GetPos(ANode) + GetSize(ANode) / 2;
  end;

  function ItemDepth(ANode: Integer; out AV: Double): Boolean;
  var dd: TJSONData;
  begin
    Result := False;
    AV := 0;
    if S^.Nodes[ANode].Item = nil then Exit;
    dd := S^.Nodes[ANode].Item.Find('depth');
    if (dd = nil) or (dd.JSONType <> jtNumber) then Exit;
    AV := dd.AsFloat;
    Result := AV >= 0;
  end;

  function SumOut(ANode: Integer): Double;
  var q: Integer; vv: Double;
  begin
    Result := 0;
    for q := 0 to High(S^.Nodes[ANode].OutE) do
    begin
      vv := S^.Edges[S^.Nodes[ANode].OutE[q]].Value;
      if not IsNan(vv) then Result := Result + vv;
    end;
  end;
  function SumIn(ANode: Integer): Double;
  var q: Integer; vv: Double;
  begin
    Result := 0;
    for q := 0 to High(S^.Nodes[ANode].InE) do
    begin
      vv := S^.Edges[S^.Nodes[ANode].InE[q]].Value;
      if not IsNan(vv) then Result := Result + vv;
    end;
  end;

  function CmpPos(A, B: Integer): Double;
  begin
    Result := GetPos(A) - GetPos(B);
  end;
  function CmpKey(A, B: Integer): Double;
  begin
    Result := colKeys[A] - colKeys[B];
  end;
  function CmpOut(A, B: Integer): Double;
  begin
    Result := GetPos(S^.Edges[A].Target) - GetPos(S^.Edges[B].Target);
  end;
  function CmpIn(A, B: Integer): Double;
  begin
    Result := GetPos(S^.Edges[A].Source) - GetPos(S^.Edges[B].Source);
  end;

  procedure ResolveCollisions;
  var c, q, cnt, nd: Integer; y0, dy: Double;
  begin
    for c := 0 to High(cols) do
    begin
      StableSort(cols[c], @CmpPos);
      y0 := 0;
      nd := -1;
      cnt := Length(cols[c]);
      for q := 0 to cnt - 1 do
      begin
        nd := cols[c][q];
        dy := y0 - GetPos(nd);
        if dy > 0 then SetPos(nd, GetPos(nd) + dy);
        y0 := GetPos(nd) + GetSize(nd) + S^.NodeGap;
      end;
      dy := y0 - S^.NodeGap - viewWidth;
      if (dy > 0) and (nd >= 0) then
      begin
        SetPos(nd, GetPos(nd) - dy);
        y0 := GetPos(nd);
        for q := cnt - 2 downto 0 do
        begin
          nd := cols[c][q];
          dy := GetPos(nd) + GetSize(nd) + S^.NodeGap - y0;
          if dy > 0 then SetPos(nd, GetPos(nd) - dy);
          y0 := GetPos(nd);
        end;
      end;
    end;
  end;

  { one relaxation pass over the columns in AOrder: toward the weighted
    mean of the other ends, each move seen by the nodes after it }
  procedure Relax(const AOrder: TTyIntegerArray; AOut: Boolean; AAlpha: Double);
  var c, q, r, nd, e, oth: Integer; num, den, y, vv, pp: Double;
      es: TTyIntegerArray;
  begin
    for c := 0 to High(AOrder) do
      for q := 0 to High(cols[AOrder[c]]) do
      begin
        nd := cols[AOrder[c]][q];
        if AOut then es := S^.Nodes[nd].OutE else es := S^.Nodes[nd].InE;
        if Length(es) = 0 then Continue;
        num := 0;
        den := 0;
        for r := 0 to High(es) do
        begin
          e := es[r];
          if AOut then oth := S^.Edges[e].Target else oth := S^.Edges[e].Source;
          pp := Center(oth) * S^.Edges[e].Value;
          if not IsNan(pp) then num := num + pp;
          vv := S^.Edges[e].Value;
          if not IsNan(vv) then den := den + vv;
        end;
        y := num / den;
        if IsNan(y) then
        begin
          num := 0;
          for r := 0 to High(es) do
          begin
            e := es[r];
            if AOut then oth := S^.Edges[e].Target else oth := S^.Edges[e].Source;
            pp := Center(oth);
            if not IsNan(pp) then num := num + pp;
          end;
          y := num / Length(es);
        end;
        SetPos(nd, GetPos(nd) + (y - Center(nd)) * AAlpha);
      end;
  end;

  function SameKey(A, B: Double): Boolean;
  begin
    Result := (A = B) or (IsNan(A) and IsNan(B));
  end;

begin
  Result := Default(TTySankeySolved);
  S := @Result;
  node := AOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  Result.Series := TJSONObject(node);
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  Result.Scale := scale;
  Result.Z := 2;
  d := Result.Series.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Z := Round(d.AsFloat);
  d := Result.Series.Find('orient');
  Result.Vertical := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'vertical');
  Result.NodeWidth := 20;
  d := Result.Series.Find('nodeWidth');
  if Present(d) then Result.NodeWidth := JsNum(d);
  Result.NodeWidth := Result.NodeWidth * scale;
  Result.NodeGap := 8;
  d := Result.Series.Find('nodeGap');
  if Present(d) then Result.NodeGap := JsNum(d);
  Result.NodeGap := Result.NodeGap * scale;
  iterations := 32;
  d := Result.Series.Find('layoutIterations');
  if Present(d) then iterations := Round(JsNum(d));
  { levels by depth, a later one of the same depth winning }
  d := Result.Series.Find('levels');
  if (d <> nil) and (d.JSONType = jtArray) then
    for k := 0 to d.Count - 1 do
      if d.Items[k].JSONType = jtObject then
      begin
        ln := TJSONObject(d.Items[k]).Find('depth');
        if (ln <> nil) and (ln.JSONType = jtNumber) and (ln.AsFloat >= 0) then
        begin
          SetLength(Result.LevelKeys, Length(Result.LevelKeys) + 1);
          SetLength(Result.LevelObjs, Length(Result.LevelObjs) + 1);
          Result.LevelKeys[High(Result.LevelKeys)] := TyJsNumberToString(ln.AsFloat);
          Result.LevelObjs[High(Result.LevelObjs)] := TJSONObject(d.Items[k]);
        end;
      end;

  { ---- the graph: data || nodes, edges || links, by JS truthiness ---- }
  arr := Result.Series.Find('data');
  if not Truthy(arr) then arr := Result.Series.Find('nodes');
  n := 0;
  if (arr <> nil) and (arr.JSONType = jtArray) then n := arr.Count;
  SetLength(Result.Nodes, n);
  SetLength(keys, n);
  for i := 0 to n - 1 do
  begin
    Result.Nodes[i] := Default(TTySankeyNode);
    if arr.Items[i].JSONType = jtObject then Result.Nodes[i].Item := TJSONObject(arr.Items[i]);
    d := nil;
    if Result.Nodes[i].Item <> nil then
    begin
      d := Result.Nodes[i].Item.Find('id');
      if not Present(d) then d := Result.Nodes[i].Item.Find('name');
      if not Present(d) then d := nil;
    end;
    if d <> nil then keys[i] := JsStr(d) else keys[i] := IntToStr(i);
    Result.Nodes[i].Key := keys[i];
    { a second node of a key: upstream throws }
    for j := 0 to i - 1 do
      if keys[j] = keys[i] then Exit;
  end;
  arr := Result.Series.Find('edges');
  if not Truthy(arr) then arr := Result.Series.Find('links');
  m := 0;
  if (arr <> nil) and (arr.JSONType = jtArray) then
    for i := 0 to arr.Count - 1 do
    begin
      if arr.Items[i].JSONType <> jtObject then Continue;
      v1 := -1;
      v2 := -1;
      for k := 0 to 1 do
      begin
        if k = 0 then d := TJSONObject(arr.Items[i]).Find('source')
        else d := TJSONObject(arr.Items[i]).Find('target');
        lo := -1;
        if (d <> nil) and (d.JSONType = jtNumber) then
        begin
          { a number is an index -- an integer in range, else nothing }
          if (Frac(d.AsFloat) = 0) and (d.AsFloat >= 0) and (d.AsFloat < n) then
            lo := Trunc(d.AsFloat);
        end
        else
          for j := 0 to n - 1 do
            if keys[j] = JsStr(d) then
            begin
              lo := j;
              Break;
            end;
        if k = 0 then v1 := lo else v2 := lo;
      end;
      if (v1 < 0) or (v2 < 0) then Continue;
      SetLength(Result.Edges, m + 1);
      Result.Edges[m] := Default(TTySankeyEdge);
      Result.Edges[m].Item := TJSONObject(arr.Items[i]);
      Result.Edges[m].Source := Round(v1);
      Result.Edges[m].Target := Round(v2);
      Result.Edges[m].Value := NumOrNaN(TJSONObject(arr.Items[i]).Find('value'));
      with Result.Nodes[Round(v1)] do
      begin
        SetLength(OutE, Length(OutE) + 1);
        OutE[High(OutE)] := m;
      end;
      with Result.Nodes[Round(v2)] do
      begin
        SetLength(InE, Length(InE) + 1);
        InE[High(InE)] := m;
      end;
      Inc(m);
    end;

  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    { ---- the box: 5% round, 20% right, merged count by count ---- }
    for k := 0 to 5 do
    begin
      raw6[k] := Default(TTyCalBoxKey);
      d := Result.Series.Find(cBoxKey[k]);
      if d <> nil then
      begin
        raw6[k].Own := True;
        raw6[k].V := TyBoxRawOf(d);
      end;
    end;
    target := raw6;
    for k := 0 to 5 do
      if (k in [1, 2, 4, 5]) and not target[k].Own then
      begin
        target[k].Own := True;
        if k = 2 then target[k].V := TyBoxRawStr('20%')
        else target[k].V := TyBoxRawStr('5%');
      end;
    TyCalMergeLayoutParam(target, raw6, False, False);
    box.Width := Scaled(target[0].V);
    box.Left := Scaled(target[1].V);
    box.Right := Scaled(target[2].V);
    box.Height := Scaled(target[3].V);
    box.Top := Scaled(target[4].V);
    box.Bottom := Scaled(target[5].V);
    CW := AContainer.Right - AContainer.Left;
    CH := AContainer.Bottom - AContainer.Top;
    Result.Box := TyGetLayoutRect(box, AContainer.Left, AContainer.Top, CW, CH, []);
    Result.HasT := not (Around0(Result.Box.X) and Around0(Result.Box.Y));
    if Result.HasT then
    begin
      Result.TX := Result.Box.X;
      Result.TY := Result.Box.Y;
    end;

    { ---- computeNodeValues ---- }
    for i := 0 to n - 1 do
    begin
      v1 := SumOut(i);
      v2 := SumIn(i);
      raw := NaN;
      if Result.Nodes[i].Item <> nil then raw := NumOrNaN(Result.Nodes[i].Item.Find('value'));
      if IsNan(raw) or (raw = 0) then raw := 0;
      Result.Nodes[i].Value := JsMax(JsMax(v1, v2), raw);
    end;
    for i := 0 to n - 1 do
      if Result.Nodes[i].Value = 0 then
      begin
        iterations := 0;
        Break;
      end;

    { ---- computeNodeBreadths: Kahn ---- }
    SetLength(indeg, n);
    zero := nil;
    for i := 0 to n - 1 do
    begin
      indeg[i] := Length(Result.Nodes[i].InE);
      if indeg[i] = 0 then
      begin
        SetLength(zero, Length(zero) + 1);
        zero[High(zero)] := i;
      end;
    end;
    SetLength(remain, m);
    for i := 0 to m - 1 do remain[i] := True;
    x := 0;
    maxNodeDepth := -1;
    next := nil;
    while Length(zero) > 0 do
    begin
      for i := 0 to High(zero) do
      begin
        t := zero[i];
        if ItemDepth(t, v1) then
        begin
          if v1 > maxNodeDepth then maxNodeDepth := v1;
          Result.Nodes[t].Depth := v1;
        end
        else
          Result.Nodes[t].Depth := x;
        if Result.Vertical then Result.Nodes[t].DY := Result.NodeWidth
        else Result.Nodes[t].DX := Result.NodeWidth;
        for j := 0 to High(Result.Nodes[t].OutE) do
        begin
          remain[Result.Nodes[t].OutE[j]] := False;
          h := Result.Edges[Result.Nodes[t].OutE[j]].Target;
          Dec(indeg[h]);
          if indeg[h] = 0 then
          begin
            found := False;
            for k := 0 to High(next) do if next[k] = h then found := True;
            if not found then
            begin
              SetLength(next, Length(next) + 1);
              next[High(next)] := h;
            end;
          end;
        end;
      end;
      Inc(x);
      zero := next;
      next := nil;
    end;
    for i := 0 to m - 1 do
      if remain[i] then Exit;   // a cycle: upstream throws
    if maxNodeDepth > x - 1 then maxDepth := maxNodeDepth else maxDepth := x - 1;
    { nodeAlign }
    align := 'justify';
    d := Result.Series.Find('nodeAlign');
    if d <> nil then
    begin
      if d.JSONType = jtString then align := d.AsString
      else if not Truthy(d) then align := ''
      else align := '?';
    end;
    if (align <> '') and (align <> 'left') then
    begin
      if align = 'right' then
      begin
        SetLength(rem, n);
        for i := 0 to n - 1 do rem[i] := i;
        h := 0;
        while Length(rem) > 0 do
        begin
          nsrc := nil;
          for i := 0 to High(rem) do
          begin
            Result.Nodes[rem[i]].SkHeight := h;
            for j := 0 to High(Result.Nodes[rem[i]].InE) do
            begin
              t := Result.Edges[Result.Nodes[rem[i]].InE[j]].Source;
              found := False;
              for k := 0 to High(nsrc) do if nsrc[k] = t then found := True;
              if not found then
              begin
                SetLength(nsrc, Length(nsrc) + 1);
                nsrc[High(nsrc)] := t;
              end;
            end;
          end;
          rem := nsrc;
          Inc(h);
        end;
        for i := 0 to n - 1 do
          if not ItemDepth(i, v1) then
            Result.Nodes[i].Depth := JsMax(0, maxDepth - Result.Nodes[i].SkHeight);
      end
      else if align = 'justify' then
        for i := 0 to n - 1 do
          if not ItemDepth(i, v1) and (Length(Result.Nodes[i].OutE) = 0) then
            Result.Nodes[i].Depth := maxDepth;
    end;
    { scaleNodeBreadths }
    if Result.Vertical then kx := (Result.Box.H - Result.NodeWidth) / maxDepth
    else kx := (Result.Box.W - Result.NodeWidth) / maxDepth;
    for i := 0 to n - 1 do
      if Result.Vertical then Result.Nodes[i].Y := Result.Nodes[i].Depth * kx
      else Result.Nodes[i].X := Result.Nodes[i].Depth * kx;

    { ---- columns, by the scaled breadth, keys ascending ---- }
    colKeys := nil;
    cols := nil;
    for i := 0 to n - 1 do
    begin
      k := -1;
      for j := 0 to High(colKeys) do
        if SameKey(colKeys[j], GetBreadth(i)) then
        begin
          k := j;
          Break;
        end;
      if k < 0 then
      begin
        SetLength(colKeys, Length(colKeys) + 1);
        colKeys[High(colKeys)] := GetBreadth(i);
        SetLength(cols, Length(cols) + 1);
        k := High(cols);
      end;
      SetLength(cols[k], Length(cols[k]) + 1);
      cols[k][High(cols[k])] := i;
    end;
    SetLength(order, Length(colKeys));
    for i := 0 to High(order) do order[i] := i;
    StableSort(order, @CmpKey);
    { the columns in their keys' order }
    SetLength(sorted, Length(order));
    for i := 0 to High(order) do sorted[i] := cols[order[i]];
    cols := sorted;
    if Result.Vertical then viewWidth := Result.Box.W else viewWidth := Result.Box.H;
    minKy := Infinity;
    for i := 0 to High(cols) do
    begin
      sum := 0;
      for j := 0 to High(cols[i]) do sum := sum + Result.Nodes[cols[i][j]].Value;
      if Result.Vertical then ky := (Result.Box.W - (Length(cols[i]) - 1) * Result.NodeGap) / sum
      else ky := (Result.Box.H - (Length(cols[i]) - 1) * Result.NodeGap) / sum;
      if ky < minKy then minKy := ky;
    end;
    for i := 0 to High(cols) do
      for j := 0 to High(cols[i]) do
      begin
        SetPos(cols[i][j], j);
        if Result.Vertical then Result.Nodes[cols[i][j]].DX := Result.Nodes[cols[i][j]].Value * minKy
        else Result.Nodes[cols[i][j]].DY := Result.Nodes[cols[i][j]].Value * minKy;
      end;
    for i := 0 to m - 1 do Result.Edges[i].DY := Result.Edges[i].Value * minKy;
    ResolveCollisions;
    SetLength(rem, Length(cols));
    for i := 0 to High(cols) do rem[i] := High(cols) - i;
    SetLength(order, Length(cols));
    for i := 0 to High(cols) do order[i] := i;
    alpha := 1;
    while iterations > 0 do
    begin
      alpha := alpha * cAlphaDecay;
      Relax(rem, True, alpha);
      ResolveCollisions;
      Relax(order, False, alpha);
      ResolveCollisions;
      Dec(iterations);
    end;

    { ---- computeEdgeDepths ---- }
    for i := 0 to n - 1 do
    begin
      StableSort(Result.Nodes[i].OutE, @CmpOut);
      StableSort(Result.Nodes[i].InE, @CmpIn);
    end;
    for i := 0 to n - 1 do
    begin
      sy := 0;
      for j := 0 to High(Result.Nodes[i].OutE) do
      begin
        Result.Edges[Result.Nodes[i].OutE[j]].SY := sy;
        sy := sy + Result.Edges[Result.Nodes[i].OutE[j]].DY;
      end;
      ty_ := 0;
      for j := 0 to High(Result.Nodes[i].InE) do
      begin
        Result.Edges[Result.Nodes[i].InE[j]].TY := ty_;
        ty_ := ty_ + Result.Edges[Result.Nodes[i].InE[j]].DY;
      end;
    end;
    Result.Valid := True;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the colours ==================== }

procedure TySankeyColour(var ASolved: TTySankeySolved;
  const AStops: TTyVisualColorArray);
var
  i: Integer;
  mn, mx, nrm: Double;
  vc: TTyVisualColor;
  d: TJSONData;
  mask: TFPUExceptionMask;
begin
  if not ASolved.Valid or (Length(ASolved.Nodes) = 0) then Exit;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    mn := Infinity;
    mx := NegInfinity;
    for i := 0 to High(ASolved.Nodes) do
    begin
      if ASolved.Nodes[i].Value < mn then mn := ASolved.Nodes[i].Value;
      if ASolved.Nodes[i].Value > mx then mx := ASolved.Nodes[i].Value;
    end;
    for i := 0 to High(ASolved.Nodes) do
    begin
      { the value over the palette: a linear colour map, as rgba }
      nrm := TyVmLinearMap(ASolved.Nodes[i].Value, mn, mx, 0, 1, True);
      vc := TyVisualFastLerp(nrm, AStops);
      ASolved.Nodes[i].HasColour := vc.Defined;
      ASolved.Nodes[i].IsString := vc.Defined;
      ASolved.Nodes[i].Colour := TyVisualToChart(vc);
      { an itemStyle colour on the chain wins, verbatim }
      d := ChainFind(ASolved, ASolved.Nodes[i].Item, ASolved.Nodes[i].Depth,
        'itemStyle', 'color');
      if d <> nil then
      begin
        ASolved.Nodes[i].IsString := d.JSONType = jtString;
        if d.JSONType = jtObject then
        begin
          ASolved.Nodes[i].HasGradient := TyTryReadGradient(d, ASolved.Nodes[i].Gradient);
          ASolved.Nodes[i].HasColour := ASolved.Nodes[i].HasGradient;
          if ASolved.Nodes[i].HasGradient then
            ASolved.Nodes[i].Colour := TyGradientSolid(ASolved.Nodes[i].Gradient);
        end
        else
          ASolved.Nodes[i].HasColour := (d.JSONType = jtString)
            and TyTryParseChartColor(d.AsString, ASolved.Nodes[i].Colour);
      end;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== labels ==================== }

function TySankeyLabelSpecs(const ASolved: TTySankeySolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
var
  i: Integer;
  base: TTyLabelSpec;
  lv: TJSONObject;
begin
  Result := nil;
  SetLength(Result, Length(ASolved.Nodes));
  for i := 0 to High(ASolved.Nodes) do
  begin
    base := ASeriesSpec;
    lv := LevelOf(ASolved, ASolved.Nodes[i].Depth);
    if lv <> nil then base := TyLabelSpecOfNode(ObjIn(lv, 'label'), ASolved.Series, base);
    if ASolved.Nodes[i].Item <> nil then
      base := TyLabelSpecOfNode(ObjIn(ASolved.Nodes[i].Item, 'label'), ASolved.Series, base);
    { the mark places the words itself }
    base.OffsetXLogical := 0;
    base.OffsetYLogical := 0;
    base.Overflow := tloNone;
    Result[i] := base;
  end;
end;

function Finite(const A: array of Double): Boolean;
var k: Integer;
begin
  Result := False;
  for k := 0 to High(A) do
    if IsNan(A[k]) or IsInfinite(A[k]) then Exit;
  Result := True;
end;

function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

{ zrender's parsePercent }
function ZrPct(AData: TJSONData; AMax: Double): Double;
var s: string;
begin
  Result := 0;
  if AData = nil then Exit;
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  if AData.JSONType = jtString then
  begin
    s := AData.AsString;
    if Pos('%', s) > 0 then Result := TyJsParseFloat(s) / 100 * AMax
    else Result := TyJsParseFloat(s);
  end;
end;

{ String.replace with a string pattern: the first occurrence only }
function ReplaceFirst(const AText, APat, AWith: string): string;
var p: Integer;
begin
  p := Pos(APat, AText);
  if p = 0 then Exit(AText);
  Result := Copy(AText, 1, p - 1) + AWith + Copy(AText, p + Length(APat), MaxInt);
end;

{ The rect a node is drawn as, local: localX/localY are box fractions }
procedure NodeRect(const S: TTySankeySolved; ANode: Integer; out AX, AY, AW, AH: Double);
var d: TJSONData;
begin
  d := ChainFind(S, S.Nodes[ANode].Item, S.Nodes[ANode].Depth, '', 'localX');
  if d <> nil then AX := JsNum(d) * S.Box.W else AX := S.Nodes[ANode].X;
  d := ChainFind(S, S.Nodes[ANode].Item, S.Nodes[ANode].Depth, '', 'localY');
  if d <> nil then AY := JsNum(d) * S.Box.H else AY := S.Nodes[ANode].Y;
  AW := S.Nodes[ANode].DX;
  AH := S.Nodes[ANode].DY;
end;

{ the node's border: its colour, its width (1 when only a colour is
  written), and whether there is one at all }
function NodeStroke(const S: TTySankeySolved; ANode: Integer;
  out AColour: TTyChartColor; out AWidth: Double): Boolean;
var d: TJSONData;
begin
  AColour := 0;
  AWidth := 1;
  d := ChainFind(S, S.Nodes[ANode].Item, S.Nodes[ANode].Depth, 'itemStyle', 'borderWidth');
  if d <> nil then AWidth := JsNum(d);
  d := ChainFind(S, S.Nodes[ANode].Item, S.Nodes[ANode].Depth, 'itemStyle', 'borderColor');
  Result := (d <> nil) and (d.JSONType = jtString) and (d.AsString <> 'none')
    and (AWidth > 0) and TyTryParseChartColor(d.AsString, AColour);
end;

procedure TySankeyLabels(var ASolved: TTySankeySolved; const ASeriesName: string);
var
  i: Integer;
  d, posd, it: TJSONData;
  text, ps: string;
  x, y, w, h, hx, hy, hw, hh, sw, ax, ay, dist: Double;
  sc: TTyChartColor;
  mask: TFPUExceptionMask;
begin
  if not ASolved.Valid then Exit;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    for i := 0 to High(ASolved.Nodes) do
    begin
      ASolved.Nodes[i].HasLabel := False;
      d := ChainFind(ASolved, ASolved.Nodes[i].Item, ASolved.Nodes[i].Depth, 'label', 'show');
      if (d <> nil) and not Truthy(d) then Continue;
      // the formatter, the first of each placeholder replaced; else the node's id
      d := ChainFind(ASolved, ASolved.Nodes[i].Item, ASolved.Nodes[i].Depth, 'label', 'formatter');
      if (d <> nil) and (d.JSONType = jtString) then
      begin
        text := ReplaceFirst(d.AsString, '{a}', ASeriesName);
        it := nil;
        if ASolved.Nodes[i].Item <> nil then it := ASolved.Nodes[i].Item.Find('name');
        if Present(it) then text := ReplaceFirst(text, '{b}', JsStr(it))
        else text := ReplaceFirst(text, '{b}', '');
        it := nil;
        if ASolved.Nodes[i].Item <> nil then it := ASolved.Nodes[i].Item.Find('value');
        if Present(it) then text := ReplaceFirst(text, '{c}', JsStr(it))
        else text := ReplaceFirst(text, '{c}', TyJsNumberToString(ASolved.Nodes[i].Value));
      end
      else
        text := ASolved.Nodes[i].Key;
      if text = '' then Continue;
      { the host: the rect's own box, grown by its stroke, moved by the group }
      NodeRect(ASolved, i, x, y, w, h);
      hx := JsMin(x, x + w);
      hy := JsMin(y, y + h);
      hw := JsMax(x, x + w) - hx;
      hh := JsMax(y, y + h) - hy;
      if NodeStroke(ASolved, i, sc, sw) then
      begin
        sw := sw * ASolved.Scale;
        if not ASolved.Nodes[i].HasColour then sw := JsMax(sw, 5 * ASolved.Scale);
        hx := hx - sw / 1 / 2;
        hy := hy - sw / 1 / 2;
        hw := hw + sw / 1;
        hh := hh + sw / 1;
      end;
      if ASolved.HasT then
      begin
        hx := hx * 1 + ASolved.TX;
        hy := hy * 1 + ASolved.TY;
        hw := hw * 1;
        hh := hh * 1;
        if hw < 0 then
        begin
          hx := hx + hw;
          hw := -hw;
        end;
        if hh < 0 then
        begin
          hy := hy + hh;
          hh := -hh;
        end;
      end;
      posd := ChainFind(ASolved, ASolved.Nodes[i].Item, ASolved.Nodes[i].Depth, 'label', 'position');
      d := ChainFind(ASolved, ASolved.Nodes[i].Item, ASolved.Nodes[i].Depth, 'label', 'distance');
      if d <> nil then dist := JsNum(d) else dist := 5;
      dist := dist * ASolved.Scale;
      ax := hx;
      ay := hy;
      ASolved.Nodes[i].LabelAH := tahLeft;
      ASolved.Nodes[i].LabelAV := tavTop;
      ASolved.Nodes[i].LabelInside := False;
      if (posd <> nil) and (posd.JSONType = jtArray) and (posd.Count >= 2) then
      begin
        ax := ax + ZrPct(posd.Items[0], hw);
        ay := ay + ZrPct(posd.Items[1], hh);
      end
      else
      begin
        if (posd <> nil) and (posd.JSONType = jtString) then ps := posd.AsString
        else ps := 'right';
        ASolved.Nodes[i].LabelInside := Pos('inside', ps) > 0;
        if ps = 'left' then
        begin
          ax := ax - dist; ay := ay + hh / 2;
          ASolved.Nodes[i].LabelAH := tahRight; ASolved.Nodes[i].LabelAV := tavMiddle;
        end
        else if ps = 'top' then
        begin
          ax := ax + hw / 2; ay := ay - dist;
          ASolved.Nodes[i].LabelAH := tahCentre; ASolved.Nodes[i].LabelAV := tavBottom;
        end
        else if ps = 'bottom' then
        begin
          ax := ax + hw / 2; ay := ay + (hh + dist);
          ASolved.Nodes[i].LabelAH := tahCentre;
        end
        else if ps = 'inside' then
        begin
          ax := ax + hw / 2; ay := ay + hh / 2;
          ASolved.Nodes[i].LabelAH := tahCentre; ASolved.Nodes[i].LabelAV := tavMiddle;
        end
        else if ps = 'insideLeft' then
        begin
          ax := ax + dist; ay := ay + hh / 2;
          ASolved.Nodes[i].LabelAV := tavMiddle;
        end
        else if ps = 'insideRight' then
        begin
          ax := ax + (hw - dist); ay := ay + hh / 2;
          ASolved.Nodes[i].LabelAH := tahRight; ASolved.Nodes[i].LabelAV := tavMiddle;
        end
        else if ps = 'insideTop' then
        begin
          ax := ax + hw / 2; ay := ay + dist;
          ASolved.Nodes[i].LabelAH := tahCentre;
        end
        else if ps = 'insideBottom' then
        begin
          ax := ax + hw / 2; ay := ay + (hh - dist);
          ASolved.Nodes[i].LabelAH := tahCentre; ASolved.Nodes[i].LabelAV := tavBottom;
        end
        else
        begin
          { 'right', the default }
          ax := ax + (dist + hw); ay := ay + hh / 2;
          ASolved.Nodes[i].LabelAV := tavMiddle;
        end;
      end;
      if Around0(ax) and Around0(ay) then
      begin
        ax := 0;
        ay := 0;
      end;
      ASolved.Nodes[i].HasLabel := True;
      ASolved.Nodes[i].LabelText := text;
      ASolved.Nodes[i].LabelX := ax;
      ASolved.Nodes[i].LabelY := ay;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the marks ==================== }

{ zrender's cubic bbox pieces (curve.ts cubicExtrema/cubicAt, bbox.ts
  fromCubic): a double root is found and NOT counted }
function CubicAt(P0, P1, P2, P3, T: Double): Double;
var o: Double;
begin
  o := 1 - T;
  Result := o * o * (o * P0 + 3 * T * P1) + T * T * (T * P3 + 3 * o * P2);
end;

function CubicExtrema(P0, P1, P2, P3: Double; out E0, E1: Double): Integer;
var a, b, c, disc, s, t1, t2: Double;
  function AZ(V: Double): Boolean;
  begin
    Result := (V > -1e-8) and (V < 1e-8);
  end;
begin
  Result := 0;
  E0 := 0;
  E1 := 0;
  b := 6 * P2 - 12 * P1 + 6 * P0;
  a := 9 * P1 + 3 * P3 - 3 * P0 - 9 * P2;
  c := 3 * P1 - 3 * P0;
  if AZ(a) then
  begin
    if not AZ(b) then
    begin
      t1 := -c / b;
      if (t1 >= 0) and (t1 <= 1) then
      begin
        E0 := t1;
        Result := 1;
      end;
    end;
  end
  else
  begin
    disc := b * b - 4 * a * c;
    if AZ(disc) then
      E0 := -b / (2 * a)
    else if disc > 0 then
    begin
      s := Sqrt(disc);
      t1 := (-b + s) / (2 * a);
      t2 := (-b - s) / (2 * a);
      if (t1 >= 0) and (t1 <= 1) then
      begin
        E0 := t1;
        Result := 1;
      end;
      if (t2 >= 0) and (t2 <= 1) then
      begin
        if Result = 0 then E0 := t2 else E1 := t2;
        Inc(Result);
      end;
    end;
  end;
end;

procedure FromCubic(X0, Y0, X1, Y1, X2, Y2, X3, Y3: Double; var MN, MX: array of Double);
var n, k: Integer; e: array[0..1] of Double; v: Double;
begin
  n := CubicExtrema(X0, X1, X2, X3, e[0], e[1]);
  MN[0] := Infinity; MN[1] := Infinity; MX[0] := NegInfinity; MX[1] := NegInfinity;
  for k := 0 to n - 1 do
  begin
    v := CubicAt(X0, X1, X2, X3, e[k]);
    MN[0] := JsMin(v, MN[0]); MX[0] := JsMax(v, MX[0]);
  end;
  n := CubicExtrema(Y0, Y1, Y2, Y3, e[0], e[1]);
  for k := 0 to n - 1 do
  begin
    v := CubicAt(Y0, Y1, Y2, Y3, e[k]);
    MN[1] := JsMin(v, MN[1]); MX[1] := JsMax(v, MX[1]);
  end;
  MN[0] := JsMin(X0, MN[0]); MX[0] := JsMax(X0, MX[0]);
  MN[0] := JsMin(X3, MN[0]); MX[0] := JsMax(X3, MX[0]);
  MN[1] := JsMin(Y0, MN[1]); MX[1] := JsMax(Y0, MX[1]);
  MN[1] := JsMin(Y3, MN[1]); MX[1] := JsMax(Y3, MX[1]);
end;

function TyBuildSankeyMarks(ASeriesIndex: Integer; const ASolved: TTySankeySolved;
  const AInk: TTySankeyInk; AList: TTyPaintList): Integer;
var
  i, n1, n2: Integer;
  el: TTyChartElement;
  shape: TTyChartShape;
  d: TJSONData;
  cv, e, x1, y1, x2, y2, cpx1, cpy1, cpx2, cpy2, lx, ly, sw, x, y, w, h, r: Double;
  mn, mx, m2, x2_: array[0..1] of Double;
  tx, ty: Double;
  lv: TJSONObject;
  chainItem: TJSONObject;
  srcDepth: Double;
  fillS: string;
  sc: TTyChartColor;
  mask: TFPUExceptionMask;

  { the link's chain: item -> level of its SOURCE's depth -> series }
  function EdgeFind(const ASub, AKey: string): TJSONData;
  begin
    Result := ChainFind(ASolved, chainItem, srcDepth, ASub, AKey);
  end;

  procedure Cmd(AKind: TTyPathCmdKind; AX1, AY1, AX2, AY2, AX, AY: Double);
  var k: Integer;
  begin
    k := Length(shape.Cmds);
    SetLength(shape.Cmds, k + 1);
    shape.Cmds[k] := Default(TTyPathCmd);
    shape.Cmds[k].Kind := AKind;
    shape.Cmds[k].X1 := AX1 + tx;
    shape.Cmds[k].Y1 := AY1 + ty;
    shape.Cmds[k].X2 := AX2 + tx;
    shape.Cmds[k].Y2 := AY2 + ty;
    shape.Cmds[k].X := AX + tx;
    shape.Cmds[k].Y := AY + ty;
  end;

  procedure Uni;
  begin
    mn[0] := JsMin(mn[0], m2[0]); mn[1] := JsMin(mn[1], m2[1]);
    mx[0] := JsMax(mx[0], x2_[0]); mx[1] := JsMax(mx[1], x2_[1]);
  end;

begin
  Result := 0;
  if (AList = nil) or not ASolved.Valid then Exit;
  tx := ASolved.TX;
  ty := ASolved.TY;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    { ---- the links, in their order ---- }
    for i := 0 to High(ASolved.Edges) do
    begin
      n1 := ASolved.Edges[i].Source;
      n2 := ASolved.Edges[i].Target;
      chainItem := ASolved.Edges[i].Item;
      srcDepth := ASolved.Nodes[n1].Depth;
      d := EdgeFind('lineStyle', 'curveness');
      if d <> nil then cv := JsNum(d) else cv := 0.5;
      e := JsMax(1, ASolved.Edges[i].DY);
      NodeRect(ASolved, n1, x, y, w, h);
      NodeRect(ASolved, n2, lx, ly, r, sw);
      if ASolved.Vertical then
      begin
        x1 := x + ASolved.Edges[i].SY;
        y1 := y + ASolved.Nodes[n1].DY;
        x2 := lx + ASolved.Edges[i].TY;
        y2 := ly;
        cpx1 := x1;
        cpy1 := y1 * (1 - cv) + y2 * cv;
        cpx2 := x2;
        cpy2 := y1 * cv + y2 * (1 - cv);
      end
      else
      begin
        x1 := x + ASolved.Nodes[n1].DX;
        y1 := y + ASolved.Edges[i].SY;
        x2 := lx;
        y2 := ly + ASolved.Edges[i].TY;
        cpx1 := x1 * (1 - cv) + x2 * cv;
        cpy1 := y1;
        cpx2 := x1 * cv + x2 * (1 - cv);
        cpy2 := y2;
      end;
      shape := TyShapePolygon([TyPointF(x1 + tx, y1 + ty), TyPointF(x2 + tx, y2 + ty)]);
      Cmd(pckMove, 0, 0, 0, 0, x1, y1);
      Cmd(pckCurve, cpx1, cpy1, cpx2, cpy2, x2, y2);
      { the band's zrender box, local }
      mn[0] := MaxDouble; mn[1] := MaxDouble; mx[0] := -MaxDouble; mx[1] := -MaxDouble;
      m2[0] := x1; x2_[0] := x1; m2[1] := y1; x2_[1] := y1; Uni;
      FromCubic(x1, y1, cpx1, cpy1, cpx2, cpy2, x2, y2, m2, x2_); Uni;
      if ASolved.Vertical then
      begin
        Cmd(pckLine, 0, 0, 0, 0, x2 + e, y2);
        Cmd(pckCurve, cpx2 + e, cpy2, cpx1 + e, cpy1, x1 + e, y1);
        m2[0] := JsMin(x2, x2 + e); m2[1] := JsMin(y2, y2);
        x2_[0] := JsMax(x2, x2 + e); x2_[1] := JsMax(y2, y2); Uni;
        FromCubic(x2 + e, y2, cpx2 + e, cpy2, cpx1 + e, cpy1, x1 + e, y1, m2, x2_); Uni;
      end
      else
      begin
        Cmd(pckLine, 0, 0, 0, 0, x2, y2 + e);
        Cmd(pckCurve, cpx2, cpy2 + e, cpx1, cpy1 + e, x1, y1 + e);
        m2[0] := JsMin(x2, x2); m2[1] := JsMin(y2, y2 + e);
        x2_[0] := JsMax(x2, x2); x2_[1] := JsMax(y2, y2 + e); Uni;
        FromCubic(x2, y2 + e, cpx2, cpy2 + e, cpx1, cpy1 + e, x1, y1 + e, m2, x2_); Uni;
      end;
      Cmd(pckClose, 0, 0, 0, 0, 0, 0);
      { A BAND UPSTREAM CANNOT SEE -- a NaN or infinite end, a link of no
        breadth -- is not emitted: the painter has nothing to draw it with }
      if not Finite([x1, x2, y1, y2, cpx1, cpx2, cpy1, cpy2, e]) then Continue;
      shape.HasCmdBounds := True;
      shape.CmdBounds := TyRectF(mn[0] + tx, mn[1] + ty, mx[0] + tx, mx[1] + ty);
      el := TyChartElement(shape);
      { the fill: the colour written, a node's, or a gradient between them }
      el.Style.HasFill := False;
      d := EdgeFind('lineStyle', 'color');
      if d = nil then
      begin
        el.Style.HasFill := True;
        el.Style.FillColor := AInk.LinkColour;
      end
      else if d.JSONType = jtString then
      begin
        fillS := d.AsString;
        if fillS = 'source' then
        begin
          el.Style.HasFill := ASolved.Nodes[n1].HasColour;
          el.Style.FillColor := ASolved.Nodes[n1].Colour;
          if ASolved.Nodes[n1].HasGradient then
            el.Style.FillGradient := ASolved.Nodes[n1].Gradient;
        end
        else if fillS = 'target' then
        begin
          el.Style.HasFill := ASolved.Nodes[n2].HasColour;
          el.Style.FillColor := ASolved.Nodes[n2].Colour;
          if ASolved.Nodes[n2].HasGradient then
            el.Style.FillGradient := ASolved.Nodes[n2].Gradient;
        end
        else if fillS = 'gradient' then
        begin
          if ASolved.Nodes[n1].IsString and ASolved.Nodes[n2].IsString then
          begin
            el.Style.HasFill := True;
            el.Style.FillColor := ASolved.Nodes[n1].Colour;
            el.Style.FillGradient := Default(TTyChartGradient);
            el.Style.FillGradient.Kind := cgkLinear;
            el.Style.FillGradient.X := 0;
            el.Style.FillGradient.Y := 0;
            if ASolved.Vertical then
            begin
              el.Style.FillGradient.X2 := 0;
              el.Style.FillGradient.Y2 := 1;
            end
            else
            begin
              el.Style.FillGradient.X2 := 1;
              el.Style.FillGradient.Y2 := 0;
            end;
            SetLength(el.Style.FillGradient.Stops, 2);
            el.Style.FillGradient.Stops[0].Offset := 0;
            el.Style.FillGradient.Stops[0].Color := ASolved.Nodes[n1].Colour;
            el.Style.FillGradient.Stops[1].Offset := 1;
            el.Style.FillGradient.Stops[1].Color := ASolved.Nodes[n2].Colour;
          end;
        end
        else
          el.Style.HasFill := TyTryParseChartColor(fillS, el.Style.FillColor);
      end;
      { lineStyle speaks itemStyle's keys: borderColor / borderWidth stroke it }
      d := EdgeFind('lineStyle', 'borderColor');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> 'none')
        and TyTryParseChartColor(d.AsString, sc) then
      begin
        sw := 1;
        d := EdgeFind('lineStyle', 'borderWidth');
        if d <> nil then sw := JsNum(d);
        if sw > 0 then
        begin
          el.Style.StrokeColor := sc;
          el.Style.StrokeWidthLogical := sw;
        end;
      end;
      d := EdgeFind('lineStyle', 'opacity');
      if d <> nil then el.Style.Alpha := JsNum(d) else el.Style.Alpha := 0.2;
      el.Z := ASolved.Z;
      el.Z2 := 0;
      el.Datum := TyChartEdgeDatum(ASeriesIndex, i);
      AList.Add(el);
      Inc(Result);
    end;
    { ---- the nodes, their captions riding on them ---- }
    for i := 0 to High(ASolved.Nodes) do
    begin
      NodeRect(ASolved, i, x, y, w, h);
      { nor a rect with a NaN or infinite side: upstream's is invisible }
      if not Finite([x, y, w, h]) then Continue;
      d := ChainFind(ASolved, ASolved.Nodes[i].Item, ASolved.Nodes[i].Depth,
        'itemStyle', 'borderRadius');
      r := 0;
      if (d <> nil) and (d.JSONType = jtNumber) then r := d.AsFloat * ASolved.Scale;
      if r > 0 then
        el := TyChartElement(TyShapeRoundRect(TyRectF(x + tx, y + ty,
          (x + w) + tx, (y + h) + ty), r))
      else
        el := TyChartElement(TyShapeRect(TyRectF(x + tx, y + ty,
          (x + w) + tx, (y + h) + ty)));
      el.Style.HasFill := ASolved.Nodes[i].HasColour;
      el.Style.FillColor := ASolved.Nodes[i].Colour;
      if ASolved.Nodes[i].HasGradient then
        el.Style.FillGradient := ASolved.Nodes[i].Gradient;
      if NodeStroke(ASolved, i, sc, sw) then
      begin
        el.Style.StrokeColor := sc;
        el.Style.StrokeWidthLogical := sw;
      end;
      d := ChainFind(ASolved, ASolved.Nodes[i].Item, ASolved.Nodes[i].Depth,
        'itemStyle', 'opacity');
      if d <> nil then el.Style.Alpha := JsNum(d) else el.Style.Alpha := 1;
      el.Z := ASolved.Z;
      el.Z2 := 10;
      el.Datum := TyChartDatum(ASeriesIndex, i, i);
      if ASolved.Nodes[i].HasLabel and Finite([ASolved.Nodes[i].LabelX, ASolved.Nodes[i].LabelY]) then
      begin
        el.Caption.Text := ASolved.Nodes[i].LabelText;
        el.Caption.ItemSpec := i + 1;
        el.Caption.HasFixedAnchor := True;
        el.Caption.FixedX := ASolved.Nodes[i].LabelX;
        el.Caption.FixedY := ASolved.Nodes[i].LabelY;
        el.Caption.FixedInside := ASolved.Nodes[i].LabelInside;
        el.Caption.FixedAH := ASolved.Nodes[i].LabelAH;
        el.Caption.FixedAV := ASolved.Nodes[i].LabelAV;
        el.Caption.HasFixedZ2 := True;
        el.Caption.FixedZ2 := 12;
      end;
      AList.Add(el);
      Inc(Result);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

end.
