unit tyControls.AdvanceChart.ThemeRiver;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the themeRiver series. [Batch 118, C10]

  UPSTREAM'S chart/themeRiver (ThemeRiverSeries.ts, themeRiverLayout.ts,
  ThemeRiverView.ts), transcribed.

  THE DATA. Each item is [time, value, name]; an item whose third element is
  undefined is dropped. fixData then makes every layer -- the items of one
  name -- cover every time any layer has: for each layer in order, a zero
  item [time, 0, name] for every time it lacks, appended after the data, the
  times walked in a JavaScript object's own key order (array-index keys
  ascending first, then the rest as they came) and written as that key, a
  STRING. A string time then goes through the time dimension's parse like
  any other -- so a numeric timestamp on a time axis comes back from its
  key as not a time at all, as upstream's does.

  THE LAYERS (getLayerSeries): the view's rows grouped by name in the order
  the names first appear, each layer's rows sorted by time with V8's
  Array.prototype.sort -- a not-a-number comparison is a tie.

  THE LAYOUT (themeRiverLayout, computeBaseline): boundaryGap's two ends
  against the rect's height (its width on a vertical orient); per time j the
  layers' sum, the largest sum, each time's baseline (max - sum) / 2, the
  largest of sum + baseline, ky = (length less the gaps) / that; layer 0
  starts at its baseline times ky and each layer stands on the one below.
  x is dataToPoint(time)[0] -- the rect's centre column on a vertical axis,
  upstream's -- and the layout is in the view group's frame, which sits at
  the rect's top plus the first gap.

  THE VIEW: one polygon per layer, ECPolygon over the bottoms (x, y0) and,
  backwards, the tops (x, y0 + y), both smoothed 0.4; the layer's style is
  its LAST row's; its label (the last row's name by default) hangs at the
  first row, `margin` to its left, halfway up, left-aligned and middle, its
  host's ECData dataIndex being the LAYER's index (setItemGraphicEl(idx)).

  PURE: SysUtils, Math, fpjson and the AdvanceChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
  tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.Data,
  tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Single;

const
  TyThemeRiverSeriesTypeName = 'themeRiver';
  TyThemeRiverTimeDim = 'time';
  TyThemeRiverValueDim = 'value';
  { ECPolygon's smooth and stackedOnSmooth }
  TyThemeRiverSmooth = 0.4;

type
  { One layer: its name and its view rows, sorted by time. }
  TTyRiverLayer = record
    Name: string;
    Rows: TTyIntegerArray;
  end;
  TTyRiverLayerArray = array of TTyRiverLayer;

  { One row's item layout: x, y0 and y in the view group's frame. }
  TTyRiverRow = record
    Has: Boolean;
    LayerIndex: Integer;
    X, Y0, Y: Double;
  end;
  TTyRiverRowArray = array of TTyRiverRow;

  { What one layer's polygon is: the bottoms and the tops (the shape's points
    and stackedOnPoints), the path upstream builds from them, its bounding
    rect, all in the group's frame; the label's place there. }
  TTyRiverPolygon = record
    Valid: Boolean;
    Bottoms, Tops: TTyPointFArray;
    Cmds: TTyPathCmdArray;
    Box: TTyXYWH;
    { the row whose style and label words the layer takes: its last }
    StyleRow: Integer;
    { the row whose place the label takes: its first }
    LabelRow: Integer;
    LabelX, LabelY: Double;
  end;
  TTyRiverPolygonArray = array of TTyRiverPolygon;

  { One series laid out. Valid False: nothing is drawn (no single, no rows,
    or layers of unequal length -- where upstream's layout throws). }
  TTyThemeRiverLayout = record
    Valid: Boolean;
    Single: TTySingle;
    Rect: TTyXYWH;
    Gap: array[0..1] of Double;
    GroupY: Double;
    Layers: TTyRiverLayerArray;
    Rows: TTyRiverRowArray;
    Polygons: TTyRiverPolygonArray;
  end;
  TTyThemeRiverLayoutArray = array of TTyThemeRiverLayout;

{ getInitialData into AStore: the kept items and fixData's zeros, as two
  columns (time -- its coordinate the single dimension, its type the axis'
  -- and value), the names as the rows' names and each item as its raw
  value. ATimeType is the axis' dimension type; AMeta its categories on a
  category axis (nil otherwise). }
procedure TyThemeRiverFillStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  ATimeType: TTyDimType; AMeta: TTyOrdinalMeta; AStore: TTyDataStore);

{ getLayerSeries over the store's view }
function TyThemeRiverLayers(AStore: TTyDataStore): TTyRiverLayerArray;

{ themeRiverLayout and the view's polygons. AMarginPx is label.margin in
  device px. }
function TyThemeRiverLayout(AOption: TTyChartOption; ASeriesIndex: Integer;
  ASingle: TTySingle; AStore: TTyDataStore; AMarginPx: Double): TTyThemeRiverLayout;

{ whether a polygon's path draws anything: a command beside its closes }
function TyRiverPathDraws(const ACmds: TTyPathCmdArray): Boolean;

{ ---- the arithmetic, exported for the tests ---- }

{ The order a JavaScript object walks its own string keys: array-index keys
  (canonical integers below 2^32 - 1) ascending, then the rest in the order
  they were added. }
function TyRiverKeyOrder(const AKeys: TTyStringArray): TTyIntegerArray;
{ V8's Array.prototype.sort of AItems by AKey ascending (a - b, a
  not-a-number difference a tie): stable; a run under 64 by its
  binary-insertion path exactly }
procedure TyV8SortBy(var AItems: TTyIntegerArray; const AKey: TTyDoubleArray);

implementation

uses tyControls.AdvanceChart.Scale, tyControls.AdvanceChart.Layout,
  tyControls.AdvanceChart.LinePath;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData.JSONType = jtObject) then Result := TJSONObject(AData)
  else Result := nil;
end;

{ JavaScript's String() of a JSON value }
function JsText(AData: TJSONData): string;
begin
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtString: Result := AData.AsString;
    jtObject: Result := '[object Object]';
  else
    Result := '';
  end;
end;

{ a JSON value on its way into the store }
function CellOf(AData: TJSONData): TTyDataValue;
begin
  Result := Default(TTyDataValue);
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := TyDataNum(AData.AsFloat);
    jtString: Result := TyDataText(AData.AsString);
    jtBoolean:
      begin
        Result.Kind := dvkBool;
        if AData.AsBoolean then Result.Num := 1 else Result.Num := 0;
      end;
  end;
end;

function TyRiverPathDraws(const ACmds: TTyPathCmdArray): Boolean;
var i: Integer;
begin
  for i := 0 to High(ACmds) do
    if ACmds[i].Kind <> pckClose then Exit(True);
  Result := False;
end;

{ ==================== the key order ==================== }

{ whether AKey is an array index: canonical, below 2^32 - 1 }
function IsArrayIndex(const AKey: string; out AValue: QWord): Boolean;
var i: Integer;
begin
  Result := False;
  AValue := 0;
  if (AKey = '') or (Length(AKey) > 10) then Exit;
  if (Length(AKey) > 1) and (AKey[1] = '0') then Exit;
  for i := 1 to Length(AKey) do
  begin
    if not (AKey[i] in ['0'..'9']) then Exit;
    AValue := AValue * 10 + QWord(Ord(AKey[i]) - Ord('0'));
  end;
  Result := AValue < QWord(4294967295);
end;

function TyRiverKeyOrder(const AKeys: TTyStringArray): TTyIntegerArray;
var
  idx: array of QWord;
  isIdx: array of Boolean;
  i, j, n, k: Integer;
  t: Integer;
begin
  n := Length(AKeys);
  Result := nil;
  SetLength(Result, n);
  SetLength(idx, n);
  SetLength(isIdx, n);
  for i := 0 to n - 1 do
    isIdx[i] := IsArrayIndex(AKeys[i], idx[i]);
  k := 0;
  for i := 0 to n - 1 do
    if isIdx[i] then
    begin
      Result[k] := i;
      Inc(k);
    end;
  { the index keys ascending (insertion sort: the keys are unique) }
  for i := 1 to k - 1 do
  begin
    t := Result[i];
    j := i - 1;
    while (j >= 0) and (idx[Result[j]] > idx[t]) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := t;
  end;
  for i := 0 to n - 1 do
    if not isIdx[i] then
    begin
      Result[k] := i;
      Inc(k);
    end;
end;

{ ==================== V8's sort ==================== }

{ sortCompare: the comparator's number, not-a-number a tie }
function Cmp(const AKey: TTyDoubleArray; A, B: Integer): Double;
begin
  Result := AKey[A] - AKey[B];
  if IsNan(Result) then Result := 0;
end;

procedure TyV8SortBy(var AItems: TTyIntegerArray; const AKey: TTyDoubleArray);
var
  n, runLen, i, left, right, mid, start, p, pivot, t: Integer;
  desc: Boolean;
  tmp: TTyIntegerArray;
  mask: TFPUExceptionMask;

  procedure MergeSort(ALo, AHi: Integer);
  var m, a, b, k: Integer;
  begin
    if AHi - ALo < 2 then Exit;
    m := (ALo + AHi) div 2;
    MergeSort(ALo, m);
    MergeSort(m, AHi);
    a := ALo;
    b := m;
    k := ALo;
    while (a < m) and (b < AHi) do
    begin
      { stable: the right one first only when strictly before }
      if Cmp(AKey, AItems[b], AItems[a]) < 0 then
      begin
        tmp[k] := AItems[b];
        Inc(b);
      end
      else
      begin
        tmp[k] := AItems[a];
        Inc(a);
      end;
      Inc(k);
    end;
    while a < m do
    begin
      tmp[k] := AItems[a];
      Inc(a);
      Inc(k);
    end;
    while b < AHi do
    begin
      tmp[k] := AItems[b];
      Inc(b);
      Inc(k);
    end;
    for k := ALo to AHi - 1 do AItems[k] := tmp[k];
  end;

begin
  n := Length(AItems);
  if n < 2 then Exit;
  mask := MaskFP;
  try
    if n >= 64 then
    begin
      SetLength(tmp, n);
      MergeSort(0, n);
      Exit;
    end;
    { CountAndMakeRun from 0 }
    runLen := 2;
    desc := Cmp(AKey, AItems[1], AItems[0]) < 0;
    i := 2;
    while i < n do
    begin
      if desc then
      begin
        if Cmp(AKey, AItems[i], AItems[i - 1]) >= 0 then Break;
      end
      else if Cmp(AKey, AItems[i], AItems[i - 1]) < 0 then Break;
      Inc(runLen);
      Inc(i);
    end;
    if desc then
      for i := 0 to runLen div 2 - 1 do
      begin
        t := AItems[i];
        AItems[i] := AItems[runLen - 1 - i];
        AItems[runLen - 1 - i] := t;
      end;
    { BinaryInsertionSort(0, runLen, n): the minimum run is the whole }
    start := runLen;
    while start < n do
    begin
      left := 0;
      right := start;
      pivot := AItems[right];
      while left < right do
      begin
        mid := left + ((right - left) shr 1);
        if Cmp(AKey, pivot, AItems[mid]) < 0 then right := mid
        else left := mid + 1;
      end;
      for p := start downto left + 1 do AItems[p] := AItems[p - 1];
      AItems[left] := pivot;
      Inc(start);
    end;
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== the data ==================== }

procedure TyThemeRiverFillStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  ATimeType: TTyDimType; AMeta: TTyOrdinalMeta; AStore: TTyDataStore);
type
  TItem = record
    Time: TTyDataValue;
    Value: TTyDataValue;
    Name: string;
    { the bucket key: the name's JSON type and text }
    KeyKind: TJSONtype;
    { the time's key, item[0] + '' }
    TimeKey: string;
  end;
var
  node: TJSONObject;
  d, it: TJSONData;
  arr: TJSONArray;
  items: array of TItem;
  n, i, k, j, b, layerN: Integer;
  keys: TTyStringArray;
  keyLayer: TTyIntegerArray;
  order: TTyIntegerArray;
  bucketNames: TTyStringArray;
  bucketKinds: array of TJSONtype;
  itemBucket: TTyIntegerArray;
  tkey: string;
  row: array[0..1] of TTyDataValue;
  raw: Integer;
  ri: TTyRawItem;

  function KeyIndex(const AKey: string): Integer;
  var q: Integer;
  begin
    for q := 0 to High(keys) do
      if keys[q] = AKey then Exit(q);
    Result := -1;
  end;

  procedure Add(const ATime: TTyDataValue; const AValue: TTyDataValue;
    const AName: string; AKind: TJSONtype; const AKey: string);
  begin
    SetLength(items, Length(items) + 1);
    items[High(items)].TimeKey := AKey;
    items[High(items)].Time := ATime;
    items[High(items)].Value := AValue;
    items[High(items)].Name := AName;
    items[High(items)].KeyKind := AKind;
  end;

begin
  if (AOption = nil) or (AStore = nil) then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if node = nil then Exit;
  AStore.AddDimension(TyThemeRiverTimeDim, ATimeType);
  AStore.AddDimension(TyThemeRiverValueDim, ddtFloat);
  AStore.SetDimCoord(0, TySingleDim);
  if (ATimeType = ddtOrdinal) and (AMeta <> nil) then AStore.UseOrdinalMeta(0, AMeta);
  AStore.SetRawDimPos(0, 0);
  AStore.SetRawDimPos(1, 1);
  AStore.SetRawDimName(0, TyThemeRiverTimeDim);
  AStore.SetRawDimName(1, TyThemeRiverValueDim);
  AStore.SetRawDimName(2, 'name');
  AStore.RawWidth := 3;
  items := nil;
  keys := nil;
  { filter(option.data, item => item[2] !== undefined): an array's third
    element, null included [arrays only -- see the batch's deviations] }
  d := node.Find('data');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    arr := TJSONArray(d);
    for i := 0 to arr.Count - 1 do
    begin
      it := arr.Items[i];
      if (it.JSONType <> jtArray) or (it.Count < 3) then Continue;
      { the time key, item[0] + '', in the order the items meet it }
      tkey := JsText(it.Items[0]);
      Add(CellOf(it.Items[0]), CellOf(it.Items[1]), JsText(it.Items[2]),
        it.Items[2].JSONType, tkey);
      if KeyIndex(tkey) < 0 then
      begin
        SetLength(keys, Length(keys) + 1);
        keys[High(keys)] := tkey;
      end;
    end;
  end;
  n := Length(items);
  { groupData by item[2]: the buckets in the order their keys first appear }
  bucketNames := nil;
  bucketKinds := nil;
  SetLength(itemBucket, n);
  for i := 0 to n - 1 do
  begin
    b := -1;
    for k := 0 to High(bucketNames) do
      if (bucketNames[k] = items[i].Name) and (bucketKinds[k] = items[i].KeyKind) then
      begin
        b := k;
        Break;
      end;
    if b < 0 then
    begin
      SetLength(bucketNames, Length(bucketNames) + 1);
      SetLength(bucketKinds, Length(bucketKinds) + 1);
      b := High(bucketNames);
      bucketNames[b] := items[i].Name;
      bucketKinds[b] := items[i].KeyKind;
    end;
    itemBucket[i] := b;
  end;
  layerN := Length(bucketNames);
  { fixData: every time a layer lacks, a zero row of that layer, its time
    the key as a string }
  SetLength(keyLayer, Length(keys));
  for k := 0 to High(keyLayer) do keyLayer[k] := -1;
  order := TyRiverKeyOrder(keys);
  for k := 0 to layerN - 1 do
  begin
    for i := 0 to n - 1 do
      if itemBucket[i] = k then
      begin
        j := KeyIndex(items[i].TimeKey);
        if j >= 0 then keyLayer[j] := k;
      end;
    for j := 0 to High(order) do
      if keyLayer[order[j]] <> k then
      begin
        keyLayer[order[j]] := k;
        Add(TyDataText(keys[order[j]]), TyDataNum(0), bucketNames[k], bucketKinds[k],
          keys[order[j]]);
      end;
  end;
  { initData }
  for i := 0 to High(items) do
  begin
    row[0] := items[i].Time;
    row[1] := items[i].Value;
    raw := AStore.AppendRow(row);
    AStore.SetName(raw, items[i].Name);
    ri := Default(TTyRawItem);
    ri.Shape := rshArray;
    SetLength(ri.Cells, 3);
    ri.Cells[0] := items[i].Time;
    ri.Cells[1] := items[i].Value;
    ri.Cells[2] := TyDataText(items[i].Name);
    AStore.SetRawItem(raw, ri);
  end;
end;

function TyThemeRiverLayers(AStore: TTyDataStore): TTyRiverLayerArray;
var
  i, k, b, n: Integer;
  nm: string;
  times: TTyDoubleArray;
begin
  Result := nil;
  if AStore = nil then Exit;
  n := AStore.Count;
  SetLength(times, n);
  for i := 0 to n - 1 do
  begin
    nm := AStore.GetNameByRaw(AStore.GetRawIndex(i));
    times[i] := AStore.Get(0, i);
    b := -1;
    for k := 0 to High(Result) do
      if Result[k].Name = nm then
      begin
        b := k;
        Break;
      end;
    if b < 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      b := High(Result);
      Result[b].Name := nm;
      Result[b].Rows := nil;
    end;
    SetLength(Result[b].Rows, Length(Result[b].Rows) + 1);
    Result[b].Rows[High(Result[b].Rows)] := i;
  end;
  for k := 0 to High(Result) do
    TyV8SortBy(Result[k].Rows, times);
end;

{ ==================== the layout ==================== }

function TyThemeRiverLayout(AOption: TTyChartOption; ASeriesIndex: Integer;
  ASingle: TTySingle; AStore: TTyDataStore; AMarginPx: Double): TTyThemeRiverLayout;
var
  node: TJSONObject;
  d, g0, g1: TJSONData;
  len, height, max_, ky, base, t: Double;
  i, j, n, m, k, r: Integer;
  px: array of array of Double;
  vy: array of array of Double;
  sums, y0: TTyDoubleArray;
  pg: TTyRiverPolygon;
  mask: TFPUExceptionMask;
begin
  Result := Default(TTyThemeRiverLayout);
  if (ASingle = nil) or (AStore = nil) then Exit;
  Result.Single := ASingle;
  Result.Rect := ASingle.Rect;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  { boundaryGap, ['10%', '10%'] unless written, each through parsePercent
    against the rect's height -- its width on a vertical orient }
  g0 := nil;
  g1 := nil;
  d := nil;
  if node <> nil then d := node.Find('boundaryGap');
  if ASingle.OrientHorizontal then len := Result.Rect.H else len := Result.Rect.W;
  if d = nil then
  begin
    Result.Gap[0] := TyBoxRawResolve(TyBoxRawStr('10%'), len);
    Result.Gap[1] := TyBoxRawResolve(TyBoxRawStr('10%'), len);
  end
  else
  begin
    if (d.JSONType = jtArray) and (d.Count > 0) then g0 := d.Items[0];
    if (d.JSONType = jtArray) and (d.Count > 1) then g1 := d.Items[1];
    Result.Gap[0] := TyBoxRawResolve(TyBoxRawOf(g0), len);
    Result.Gap[1] := TyBoxRawResolve(TyBoxRawOf(g1), len);
  end;
  mask := MaskFP;
  try
    height := len - Result.Gap[0] - Result.Gap[1];
    Result.GroupY := Result.Rect.Y + Result.Gap[0];
    Result.Layers := TyThemeRiverLayers(AStore);
    SetLength(Result.Rows, AStore.Count);
    n := Length(Result.Layers);
    Result.Valid := True;
    if AStore.Count = 0 then Exit;
    m := Length(Result.Layers[0].Rows);
    { a layer shorter than the first leaves upstream's computeBaseline
      reading past it (it throws); one longer has rows nobody lays out }
    for i := 1 to n - 1 do
      if Length(Result.Layers[i].Rows) < m then
      begin
        Result.Valid := False;
        Exit;
      end;
    SetLength(px, n);
    SetLength(vy, n);
    for i := 0 to n - 1 do
    begin
      SetLength(px[i], Length(Result.Layers[i].Rows));
      SetLength(vy[i], Length(Result.Layers[i].Rows));
      for j := 0 to High(Result.Layers[i].Rows) do
      begin
        r := Result.Layers[i].Rows[j];
        px[i][j] := ASingle.ValueToPoint(AStore.Get(0, r)).X;
        vy[i][j] := AStore.Get(1, r);
      end;
    end;
    { computeBaseline }
    SetLength(sums, m);
    SetLength(y0, m);
    max_ := 0;
    for i := 0 to m - 1 do
    begin
      t := 0;
      for j := 0 to n - 1 do t := t + vy[j][i];
      if t > max_ then max_ := t;
      sums[i] := t;
    end;
    for k := 0 to m - 1 do y0[k] := (max_ - sums[k]) / 2;
    max_ := 0;
    for k := 0 to m - 1 do
    begin
      t := sums[k] + y0[k];
      if t > max_ then max_ := t;
    end;
    ky := height / max_;
    for j := 0 to m - 1 do
    begin
      base := y0[j] * ky;
      r := Result.Layers[0].Rows[j];
      Result.Rows[r].Has := True;
      Result.Rows[r].LayerIndex := 0;
      Result.Rows[r].X := px[0][j];
      Result.Rows[r].Y0 := base;
      Result.Rows[r].Y := vy[0][j] * ky;
      for i := 1 to n - 1 do
      begin
        base := base + vy[i - 1][j] * ky;
        r := Result.Layers[i].Rows[j];
        Result.Rows[r].Has := True;
        Result.Rows[r].LayerIndex := i;
        Result.Rows[r].X := px[i][j];
        Result.Rows[r].Y0 := base;
        Result.Rows[r].Y := vy[i][j] * ky;
      end;
    end;
    { the view: a polygon per layer }
    SetLength(Result.Polygons, n);
    for i := 0 to n - 1 do
    begin
      pg := Default(TTyRiverPolygon);
      pg.Valid := True;
      SetLength(pg.Bottoms, Length(Result.Layers[i].Rows));
      SetLength(pg.Tops, Length(Result.Layers[i].Rows));
      for j := 0 to High(Result.Layers[i].Rows) do
      begin
        r := Result.Layers[i].Rows[j];
        if not Result.Rows[r].Has then
        begin
          pg.Valid := False;
          Break;
        end;
        pg.Bottoms[j] := TyPointF(Result.Rows[r].X, Result.Rows[r].Y0);
        pg.Tops[j] := TyPointF(Result.Rows[r].X, Result.Rows[r].Y0 + Result.Rows[r].Y);
      end;
      if pg.Valid then
      begin
        pg.Cmds := TyPolygonPath(pg.Bottoms, pg.Tops, TyThemeRiverSmooth,
          TyThemeRiverSmooth, '', False);
        pg.Box := TyPathCmdsRect(pg.Cmds);
        { BoundingRect's constructor turns a negative size round: a path of
          no point (its extremes still the sentinels) comes out from minus
          infinity, infinitely wide }
        if pg.Box.W < 0 then
        begin
          pg.Box.X := pg.Box.X + pg.Box.W;
          pg.Box.W := -pg.Box.W;
        end;
        if pg.Box.H < 0 then
        begin
          pg.Box.Y := pg.Box.Y + pg.Box.H;
          pg.Box.H := -pg.Box.H;
        end;
        pg.StyleRow := Result.Layers[i].Rows[High(Result.Layers[i].Rows)];
        pg.LabelRow := Result.Layers[i].Rows[0];
        pg.LabelX := Result.Rows[pg.LabelRow].X - AMarginPx;
        pg.LabelY := Result.Rows[pg.LabelRow].Y0 + Result.Rows[pg.LabelRow].Y / 2;
      end;
      Result.Polygons[i] := pg;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

end.
