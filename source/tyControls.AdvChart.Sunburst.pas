unit tyControls.AdvChart.Sunburst;
{$mode objfpc}{$H+}
{ The sunburst series: a hierarchy drawn as rings of sectors, the roots
  innermost, each node's angle its share of the whole.

  THE HIERARCHY IS THE TREE'S (TyHierarchyOf): a virtual root named after
  the series, the rows in pre-order. Unlike a tree, every root is drawn and
  nothing collapses.

  VALUES ARE COMPLETED FIRST, post-order: a node with no value takes the sum
  of its children's; one with a value keeps it, children or not -- so a
  parent can leave a gap in its ring, or its children spill past it.
  Negatives are nought.

  THE ORDER IS SORTED (desc by default, asc reversing ties, `null` none) and
  everything follows it: the layout, the drawing, and the palette.

  THE ANGLES are one unit radian for the whole chart times each value, a
  child starting where its parent starts and each next sibling at the
  parent's start plus the running sum of its elders' spans -- NOT at the
  previous one's end, which differs in the last bit.

  THE COLOURS: a node's own, its level's or the series' itemStyle colour;
  else its root ancestor's palette colour (taken lazily, in pre-order, keyed
  by the root's name, one cursor for every sunburst in the chart), lifted
  toward white by its depth.

  THE LABELS sit on the mid angle -- at the ring's middle, or at an edge by
  `align`, or past the rim `outside` -- turned radially or tangentially and
  flipped where they would read upside down. Placed here, not by the label
  expansion's table, which has no such position.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Labels,
  tyControls.AdvChart.LabelOpt, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.Tree;

const
  TySunburstSeriesTypeName = 'sunburst';

type
  TTySunNode = record
    Value: Double;
    { the children in the sorted order }
    Order: TTyIntegerArray;
    Placed: Boolean;
    StartRad, EndRad, R0, R: Double;
    Fill: TTyChartColor;
  end;

  TTySunburstSolved = record
    Valid: Boolean;
    Hier: TTyHierarchy;
    Nodes: array of TTySunNode;
    CX, CY: Double;
    Series: TJSONObject;         // borrowed
    Levels: array of TJSONObject; // borrowed, by depth; nil where none
    Z: Integer;
    RenderZero: Boolean;
  end;

  { Everything a theme answers. }
  TTySunburstInk = record
    { the palette the roots take from: the author's, else the theme's ramp }
    Palette: TTyChartColorArray;
    { the ring separator: upstream's white, the chart's own ground here }
    Border: TTyChartColor;
    Label_: TTyLabelSpec;
    ItemLabels: TTyLabelSpecArray;
    SeriesName: string;
    LabelValueDim: Integer;
  end;

function TySunburstSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer): TTySunburstSolved;
{ The colour visual over one series, with the cursor every sunburst in the
  chart shares. }
procedure TySunburstColour(var ASolved: TTySunburstSolved;
  const APalette: TTyChartColorArray; var ACursor: TTyPaletteCursor);
{ zrender's lift(color, level): each channel toward white by level,
  truncated; the alpha kept. }
function TySunburstLift(AColor: TTyChartColor; ALevel: Double): TTyChartColor;
{ One label spec per row: item -> levels[depth] -> series. }
function TySunburstLabelSpecs(const ASolved: TTySunburstSolved;
  const ASeriesSpec: TTyLabelSpec): TTyLabelSpecArray;
function TyBuildSunburstMarks(ASeriesIndex: Integer; const ASolved: TTySunburstSolved;
  const AInk: TTySunburstInk; AStore: TTyDataStore; AList: TTyPaintList;
  APPI: Integer): Integer;

implementation

uses tyControls.AdvChart.Scale;

const
  cRadian = Pi / 180;

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

function ItemOf(const ASolved: TTySunburstSolved; ARow: Integer): TJSONObject;
var it: TJSONData;
begin
  Result := nil;
  it := ASolved.Hier.Nodes[ARow].Item;
  if (it <> nil) and (it.JSONType = jtObject) then Result := TJSONObject(it);
end;

function LevelOf(const ASolved: TTySunburstSolved; ARow: Integer): TJSONObject;
var d: Integer;
begin
  Result := nil;
  d := ASolved.Hier.Nodes[ARow].Depth;
  if (d >= 0) and (d <= High(ASolved.Levels)) then Result := ASolved.Levels[d];
end;

{ Model.get along item -> level -> series: the first with the key and a
  value that is not null }
function ChainFind(const ASolved: TTySunburstSolved; ARow: Integer;
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

{ ==================== the solve ==================== }

function ItemValue(AItem: TJSONData): Double;
var d: TJSONData;
begin
  Result := NaN;
  if (AItem = nil) or (AItem.JSONType <> jtObject) then Exit;
  d := TJSONObject(AItem).Find('value');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    if d.Count = 0 then Exit;
    d := d.Items[0];
  end;
  if d = nil then Exit;
  case d.JSONType of
    jtNumber: Result := d.AsFloat;
    jtString: Result := TyJsToNumber(d.AsString);
    jtBoolean: if d.AsBoolean then Result := 1 else Result := 0;
  end;
end;

function TySunburstSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  const AContainer: TTyRectF; APPI: Integer): TTySunburstSolved;
var
  mask: TFPUExceptionMask;
  node, d: TJSONData;
  n, row, k, j, depthCount, sortMode: Integer;
  sum, v, scale, W, H, size, r0, r, startA, minA, unitRad, rPerLevel, dir: Double;
  still, cw: Boolean;
  cx0, cx1, rad0, rad1: TTyBoxRaw;
  tmp: Integer;
  rootHeight: Integer;
  sol: ^TTySunburstSolved;
  done: TTyDoubleArray;

  function Scaled(const R: TTyBoxRaw): TTyBoxRaw;
  begin
    Result := R;
    if R.Kind = brNumber then Result.Num := R.Num * scale;
  end;

  { the sort comparator: < 0 when A goes first }
  function Cmp(A, B: Integer): Double;
  var diff: Double;
  begin
    if sortMode = 1 then diff := (sol^.Nodes[A].Value - sol^.Nodes[B].Value)
    else diff := (sol^.Nodes[A].Value - sol^.Nodes[B].Value) * -1;
    if IsNan(diff) or (diff = 0) then
    begin
      if sortMode = 1 then Result := (A - B) * -1 else Result := A - B;
    end
    else
      Result := diff;
  end;

  function RenderNode(ARow: Integer; AStart: Double): Double;
  var
    endA, angle, rStart, rEnd, sib: Double;
    depth, c: Integer;
    lv: TJSONObject;
    rv, lr0, lr: TJSONData;
  begin
    endA := AStart;
    if ARow <> 0 then
    begin
      v := sol^.Nodes[ARow].Value;
      if (sum = 0) and still then angle := unitRad
      else angle := v * unitRad;
      if angle < minA then angle := minA;
      endA := AStart + dir * angle;
      depth := sol^.Hier.Nodes[ARow].Depth - 0 - 1;
      rStart := r0 + rPerLevel * depth;
      rEnd := r0 + rPerLevel * (depth + 1);
      { a level's own radius: `radius`, else the older r0 / r }
      lv := LevelOf(sol^, ARow);
      if lv <> nil then
      begin
        lr0 := lv.Find('r0');
        lr := lv.Find('r');
        rv := lv.Find('radius');
        if (rv <> nil) and (rv.JSONType <> jtNull) then
        begin
          lr0 := nil;
          lr := nil;
          if rv.JSONType = jtArray then
          begin
            if rv.Count > 0 then lr0 := rv.Items[0];
            if rv.Count > 1 then lr := rv.Items[1];
          end;
        end;
        if (lr0 <> nil) and (lr0.JSONType <> jtNull) then
          rStart := TyBoxRawResolve(Scaled(TyBoxRawOf(lr0)), size / 2);
        if (lr <> nil) and (lr.JSONType <> jtNull) then
          rEnd := TyBoxRawResolve(Scaled(TyBoxRawOf(lr)), size / 2);
      end;
      sol^.Nodes[ARow].Placed := True;
      sol^.Nodes[ARow].StartRad := AStart;
      sol^.Nodes[ARow].EndRad := endA;
      sol^.Nodes[ARow].R0 := rStart;
      sol^.Nodes[ARow].R := rEnd;
    end;
    sib := 0;
    for c := 0 to High(sol^.Nodes[ARow].Order) do
      sib := sib + RenderNode(sol^.Nodes[ARow].Order[c], AStart + sib);
    Result := endA - AStart;
  end;

begin
  Result := Default(TTySunburstSolved);
  sol := @Result;
  Result.Hier := TyHierarchyOf(AOption, ASeriesIndex);
  if not Result.Hier.Valid then Exit;
  node := AOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  Result.Series := TJSONObject(node);
  Result.Z := 2;
  d := Result.Series.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Z := Round(d.AsFloat);
  d := Result.Series.Find('renderLabelForZeroData');
  Result.RenderZero := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
  d := Result.Series.Find('levels');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    SetLength(Result.Levels, d.Count);
    for k := 0 to d.Count - 1 do
      if d.Items[k].JSONType = jtObject then Result.Levels[k] := TJSONObject(d.Items[k])
      else Result.Levels[k] := nil;
  end;
  n := Length(Result.Hier.Nodes);
  SetLength(Result.Nodes, n);
  { ---- completeTreeValue ---- }
  done := TyTreeCompletedValues(Result.Hier);
  for row := 0 to n - 1 do Result.Nodes[row].Value := done[row];
  { ---- the sort: absent 'desc', null none, 'asc' asc, anything else desc ---- }
  d := Result.Series.Find('sort');
  if d = nil then sortMode := 2
  else if d.JSONType = jtNull then sortMode := 0
  else if (d.JSONType = jtString) and (d.AsString = 'asc') then sortMode := 1
  else sortMode := 2;
  for row := 0 to n - 1 do
  begin
    Result.Nodes[row].Order := Copy(Result.Hier.Nodes[row].Children, 0,
      Length(Result.Hier.Nodes[row].Children));
    if sortMode = 0 then Continue;
    { insertion sort: the comparator is total, so any correct sort agrees }
    for k := 1 to High(Result.Nodes[row].Order) do
    begin
      tmp := Result.Nodes[row].Order[k];
      j := k - 1;
      while (j >= 0) and (Cmp(Result.Nodes[row].Order[j], tmp) > 0) do
      begin
        Result.Nodes[row].Order[j + 1] := Result.Nodes[row].Order[j];
        Dec(j);
      end;
      Result.Nodes[row].Order[j + 1] := tmp;
    end;
  end;

  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    if APPI > 0 then scale := APPI / 96 else scale := 1;
    W := AContainer.Right - AContainer.Left;
    H := AContainer.Bottom - AContainer.Top;
    size := Min(W, H);
    { centre and radius: a scalar centre is both, a scalar radius the outer }
    cx0 := TyBoxRawStr('50%');
    cx1 := TyBoxRawStr('50%');
    d := Result.Series.Find('center');
    if d <> nil then
    begin
      if d.JSONType = jtArray then
      begin
        if d.Count > 0 then cx0 := TyBoxRawOf(d.Items[0]) else cx0 := TyBoxRawOf(nil);
        if d.Count > 1 then cx1 := TyBoxRawOf(d.Items[1]) else cx1 := TyBoxRawOf(nil);
      end
      else
      begin
        cx0 := TyBoxRawOf(d);
        cx1 := cx0;
      end;
    end;
    rad0 := TyBoxRawNum(0);
    rad1 := TyBoxRawStr('75%');
    d := Result.Series.Find('radius');
    if d <> nil then
    begin
      if d.JSONType = jtArray then
      begin
        if d.Count > 0 then rad0 := TyBoxRawOf(d.Items[0]) else rad0 := TyBoxRawOf(nil);
        if d.Count > 1 then rad1 := TyBoxRawOf(d.Items[1]) else rad1 := TyBoxRawOf(nil);
      end
      else
      begin
        rad0 := TyBoxRawNum(0);
        rad1 := TyBoxRawOf(d);
      end;
    end;
    Result.CX := AContainer.Left + TyBoxRawResolve(Scaled(cx0), W);
    Result.CY := AContainer.Top + TyBoxRawResolve(Scaled(cx1), H);
    r0 := TyBoxRawResolve(Scaled(rad0), size / 2);
    r := TyBoxRawResolve(Scaled(rad1), size / 2);
    d := Result.Series.Find('startAngle');
    if d <> nil then startA := -JsNum(d) * cRadian else startA := -90 * cRadian;
    d := Result.Series.Find('minAngle');
    if d <> nil then minA := JsNum(d) * cRadian else minA := 0 * cRadian;
    d := Result.Series.Find('clockwise');
    cw := (d = nil) or ((d.JSONType = jtBoolean) and d.AsBoolean)
      or ((d.JSONType <> jtBoolean) and (d.JSONType <> jtNull)
        and not ((d.JSONType = jtNumber) and (d.AsFloat = 0))
        and not ((d.JSONType = jtString) and (d.AsString = '')));
    d := Result.Series.Find('stillShowZeroSum');
    still := (d = nil) or not ((d.JSONType = jtBoolean) and not d.AsBoolean);
    sum := Result.Nodes[0].Value;
    depthCount := Length(Result.Hier.Nodes[0].Children);
    if sum <> 0 then unitRad := Pi / sum * 2
    else unitRad := Pi / depthCount * 2;
    rootHeight := Result.Hier.Nodes[0].Height;
    k := rootHeight - 1;
    if k = 0 then k := 1;
    rPerLevel := (r - r0) / k;
    if cw then dir := 1 else dir := -1;
    RenderNode(0, startA);
    Result.Valid := True;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the colours ==================== }

function TySunburstLift(AColor: TTyChartColor; ALevel: Double): TTyChartColor;
var
  a, r, g, b: Integer;
  function Up(ACh: Integer): Integer;
  var v: Double;
  begin
    v := (255 - ACh) * ALevel + ACh;
    Result := Trunc(v);
    if Result < 0 then Result := 0;
    if Result > 255 then Result := 255;
  end;
begin
  a := (AColor shr 24) and $FF;
  r := (AColor shr 16) and $FF;
  g := (AColor shr 8) and $FF;
  b := AColor and $FF;
  Result := TTyChartColor((Cardinal(a) shl 24) or (Cardinal(Up(r)) shl 16)
    or (Cardinal(Up(g)) shl 8) or Cardinal(Up(b)));
end;

procedure TySunburstColour(var ASolved: TTySunburstSolved;
  const APalette: TTyChartColorArray; var ACursor: TTyPaletteCursor);
var
  stack: TTyIntegerArray;
  top, row, k, cur: Integer;
  d: TJSONData;
  c: TTyChartColor;
  key: string;
  treeHeight: Integer;
begin
  if not ASolved.Valid then Exit;
  ACursor.Colors := APalette;
  treeHeight := ASolved.Hier.Nodes[0].Height;
  { pre-order over the SORTED tree, every node }
  SetLength(stack, 16);
  stack[0] := 0;
  top := 1;
  while top > 0 do
  begin
    Dec(top);
    row := stack[top];
    for k := High(ASolved.Nodes[row].Order) downto 0 do
    begin
      if top >= Length(stack) then SetLength(stack, 2 * Length(stack));
      stack[top] := ASolved.Nodes[row].Order[k];
      Inc(top);
    end;
    if row = 0 then Continue;
    d := ChainFind(ASolved, row, 'itemStyle', 'color');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      ASolved.Nodes[row].Fill := c;
      Continue;
    end;
    { the depth-1 ancestor's palette colour, by its name }
    cur := row;
    while ASolved.Hier.Nodes[cur].Depth > 1 do cur := ASolved.Hier.Nodes[cur].Parent;
    key := '';
    if (ASolved.Hier.Nodes[cur].Item <> nil)
      and (ASolved.Hier.Nodes[cur].Item.JSONType = jtObject) then
    begin
      d := TJSONObject(ASolved.Hier.Nodes[cur].Item).Find('name');
      if (d <> nil) and (d.JSONType = jtString) then key := d.AsString
      else if (d <> nil) and (d.JSONType = jtNumber) then key := TyJsNumberToString(d.AsFloat);
    end;
    if key = '' then key := IntToStr(cur);
    c := 0;
    TyPaletteTake(ACursor, key, c);
    if (ASolved.Hier.Nodes[row].Depth > 1) and (treeHeight > 1) then
      c := TySunburstLift(c, (ASolved.Hier.Nodes[row].Depth - 1) / (treeHeight - 1) * 0.5);
    ASolved.Nodes[row].Fill := c;
  end;
end;

{ ==================== labels ==================== }

function TySunburstLabelSpecs(const ASolved: TTySunburstSolved;
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
    { a sunburst ignores a label's offset }
    base.OffsetXLogical := 0;
    base.OffsetYLogical := 0;
    Result[row] := base;
  end;
end;

{ ==================== the marks ==================== }

function NormalizeRadian(A: Double): Double;
begin
  Result := TyJsFMod(A, Pi * 2);
  if Result < 0 then Result := Result + Pi * 2;
end;

function AroundZero(V: Double): Boolean;
begin
  Result := (V > -1e-4) and (V < 1e-4);
end;

function Corners(const ASolved: TTySunburstSolved; ARow: Integer;
  AR0, AR: Double): TTyDoubleArray;
var
  d: TJSONData;
  dr: Double;
  k: Integer;

  function One(AData: TJSONData): Double;
  var s: string;
  begin
    Result := 0;
    if AData = nil then Exit;
    if AData.JSONType = jtNumber then Exit(AData.AsFloat);
    if AData.JSONType = jtString then
    begin
      s := Trim(AData.AsString);
      if (s <> '') and (s[Length(s)] = '%') then
        Result := TyJsToNumber(Copy(s, 1, Length(s) - 1)) / 100 * dr
      else
        Result := TyJsToNumber(s);
      if IsNan(Result) then Result := 0;
    end;
  end;

begin
  Result := nil;
  d := ChainFind(ASolved, ARow, 'itemStyle', 'borderRadius');
  if d = nil then Exit;
  { `Math.abs(shape.r || 0 - shape.r0 || 0)` -- r, else -r0, else 0 }
  if AR <> 0 then dr := Abs(AR)
  else if AR0 <> 0 then dr := Abs(AR0)
  else dr := 0;
  if d.JSONType = jtArray then
  begin
    SetLength(Result, d.Count);
    for k := 0 to d.Count - 1 do Result[k] := One(d.Items[k]);
  end
  else
  begin
    SetLength(Result, 1);
    Result[0] := One(d);
    { a scalar is all four -- zrender's [c, c, c, c] }
    SetLength(Result, 4);
    Result[1] := Result[0];
    Result[2] := Result[0];
    Result[3] := Result[0];
  end;
end;

procedure PlaceLabel(const ASolved: TTySunburstSolved; ARow: Integer;
  AScale: Double; var ACaption: TTyElementCaption);
var
  nd: TTySunNode;
  mid, dx, dy, pad, rr, angle, midN, rotate: Double;
  d: TJSONData;
  pos, align, rotType, vAlign: string;
  flip: Boolean;
  rotNum: Double;
  hasRotNum: Boolean;
begin
  nd := ASolved.Nodes[ARow];
  mid := (nd.StartRad + nd.EndRad) / 2;
  dx := TyJsCos(mid);
  dy := TyJsSin(mid);
  d := ChainFind(ASolved, ARow, 'label', 'position');
  if (d <> nil) and (d.JSONType = jtString) then pos := d.AsString else pos := 'inside';
  d := ChainFind(ASolved, ARow, 'label', 'distance');
  if d <> nil then pad := JsNum(d) else pad := 5;
  if IsNan(pad) or (pad = 0) then pad := 0;
  pad := pad * AScale;
  d := ChainFind(ASolved, ARow, 'label', 'align');
  if (d <> nil) and (d.JSONType = jtString) then align := d.AsString else align := 'center';
  rotType := 'radial';
  hasRotNum := False;
  rotNum := 0;
  d := ChainFind(ASolved, ARow, 'label', 'rotate');
  if d <> nil then
  begin
    if d.JSONType = jtString then rotType := d.AsString
    else if d.JSONType = jtNumber then
    begin
      rotType := '';
      hasRotNum := True;
      rotNum := d.AsFloat;
    end
    else rotType := '';
  end;
  angle := nd.EndRad - nd.StartRad;
  if rotType = 'tangential' then midN := NormalizeRadian(Pi / 2 - mid)
  else midN := NormalizeRadian(mid);
  flip := (midN > Pi * 0.5) and not AroundZero(midN - Pi * 0.5) and (midN < Pi * 1.5);
  rr := NaN;
  if pos = 'outside' then
  begin
    rr := nd.R + pad;
    if flip then align := 'right' else align := 'left';
  end
  else if (align = '') or (align = 'center') then
  begin
    if (nd.R0 = 0) and AroundZero(angle - 2 * Pi) then rr := 0
    else rr := (nd.R + nd.R0) / 2;
    align := 'center';
  end
  else if align = 'left' then
  begin
    rr := nd.R0 + pad;
    if flip then align := 'right' else align := 'left';
  end
  else if align = 'right' then
  begin
    rr := nd.R - pad;
    if flip then align := 'left' else align := 'right';
  end;
  d := ChainFind(ASolved, ARow, 'label', 'verticalAlign');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then vAlign := d.AsString
  else vAlign := 'middle';
  rotate := 0;
  if rotType = 'radial' then
  begin
    rotate := NormalizeRadian(-mid);
    if flip then rotate := rotate + Pi;
  end
  else if rotType = 'tangential' then
  begin
    rotate := NormalizeRadian(Pi / 2 - mid);
    if flip then rotate := rotate + Pi;
  end
  else if hasRotNum then
    rotate := rotNum * Pi / 180;
  ACaption.HasFixedAnchor := True;
  ACaption.FixedX := rr * dx + ASolved.CX;
  ACaption.FixedY := rr * dy + ASolved.CY;
  ACaption.FixedInside := pos <> 'outside';
  if align = 'left' then ACaption.FixedAH := tahLeft
  else if align = 'right' then ACaption.FixedAH := tahRight
  else ACaption.FixedAH := tahCentre;
  if (vAlign = 'top') then ACaption.FixedAV := tavTop
  else if (vAlign = 'bottom') then ACaption.FixedAV := tavBottom
  else ACaption.FixedAV := tavMiddle;
  ACaption.FixedRotationRad := NormalizeRadian(rotate);
end;

function TyBuildSunburstMarks(ASeriesIndex: Integer; const ASolved: TTySunburstSolved;
  const AInk: TTySunburstInk; AStore: TTyDataStore; AList: TTyPaintList;
  APPI: Integer): Integer;
var
  stack: TTyIntegerArray;
  top, row, k: Integer;
  nd: TTySunNode;
  el: TTyChartElement;
  s0, s1, scale, lmin, w: Double;
  d: TJSONData;
  spec: TTyLabelSpec;
  c: TTyChartColor;
  show: Boolean;
begin
  Result := 0;
  if (AList = nil) or not ASolved.Valid then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  SetLength(stack, 16);
  stack[0] := 0;
  top := 1;
  while top > 0 do
  begin
    Dec(top);
    row := stack[top];
    for k := High(ASolved.Nodes[row].Order) downto 0 do
    begin
      if top >= Length(stack) then SetLength(stack, 2 * Length(stack));
      stack[top] := ASolved.Nodes[row].Order[k];
      Inc(top);
    end;
    if row = 0 then Continue;
    nd := ASolved.Nodes[row];
    if not nd.Placed then Continue;
    { a node of no value is not drawn }
    if (not ASolved.RenderZero) and ((nd.Value = 0) or IsNan(nd.Value)) then Continue;
    s0 := Min(nd.StartRad, nd.EndRad);
    s1 := Max(nd.StartRad, nd.EndRad);
    el := TyChartElement(TyShapeSector(ASolved.CX, ASolved.CY, nd.R0, nd.R, s0, s1,
      Corners(ASolved, row, nd.R0, nd.R)));
    el.Style.HasFill := True;
    el.Style.FillColor := nd.Fill;
    d := ChainFind(ASolved, row, 'itemStyle', 'borderColor');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
      el.Style.StrokeColor := c
    else
      el.Style.StrokeColor := AInk.Border;
    d := ChainFind(ASolved, row, 'itemStyle', 'borderWidth');
    if (d <> nil) and (d.JSONType = jtNumber) then w := d.AsFloat else w := 1;
    el.Style.StrokeWidthLogical := w;
    d := ChainFind(ASolved, row, 'itemStyle', 'opacity');
    if (d <> nil) and (d.JSONType = jtNumber) then el.Style.Alpha := d.AsFloat
    else el.Style.Alpha := 1;
    el.Z := ASolved.Z;
    el.Z2 := 2;
    el.Datum := TyChartDatum(ASeriesIndex, row, row);
    { the sector takes the pointer -- TyChartElement starts silent [Batch 84] }
    el.Silent := False;
    { the label }
    if row <= High(AInk.ItemLabels) then spec := AInk.ItemLabels[row]
    else spec := AInk.Label_;
    show := spec.Show;
    d := ChainFind(ASolved, row, 'label', 'minAngle');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      lmin := d.AsFloat / 180 * Pi;
      if Abs(nd.EndRad - nd.StartRad) < lmin then show := False;
    end;
    if show and (AStore <> nil) then
    begin
      el.Caption.Text := TyLabelText(spec.Formatter, spec.HasFormatter, spec.DefaultText,
        AStore, row, AInk.SeriesName, AInk.LabelValueDim, NaN, False,
        ASeriesIndex, 'sunburst');
      if el.Caption.Text <> '' then
      begin
        el.Caption.ItemSpec := row + 1;
        PlaceLabel(ASolved, row, scale, el.Caption);
        { an align upstream does not know leaves the radius undefined and
          the anchor NaN: nothing to draw }
        if IsNan(el.Caption.FixedX) or IsNan(el.Caption.FixedY) then
        begin
          el.Caption.Text := '';
          el.Caption.HasFixedAnchor := False;
        end;
      end;
    end;
    AList.Add(el);
    Inc(Result);
  end;
end;

end.
