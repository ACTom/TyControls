unit tyControls.AdvChart.StatTransform;
{$mode objfpc}{$H+}
{ ECSTAT'S DATASET TRANSFORMS -- 'ecStat:regression', 'ecStat:histogram'
  and 'ecStat:clustering', the three echarts-stat ships for
  echarts.registerTransform. [Batch 134, roadmap D3]

  PORTED FROM the built echarts-stat in ECharts' own test folder
  (test/lib/ecStat.min.js -- its source is not checked out), module by
  module: dataPreprocess, normalizeDimensions, the regression methods and
  their Gaussian elimination, the histogram with its bin rules, the nice
  step and the tick range, the bisect, the statistics it leans on
  (max, min, sum, mean, sampleVariance, deviation, quantile), the bisecting
  k-means, and the three transform wrappers with their dimension helpers.

  REGISTERED BY THIS UNIT'S INITIALIZATION. Upstream registers nothing:
  every page that uses them calls echarts.registerTransform(ecStat.transform
  .xxx) first, and an option naming one that was not registered throws. The
  port has no script to make that call from -- an option is text -- so the
  three are always there; TyRegisterEcStatTransforms puts them back after a
  program registered something else under one of the names.

  A NUMBER IS A JSON NUMBER. ecStat's isNumber is `+v` is a number, so a
  numeric string, a boolean and '' pass its row check and then take part
  in `+=` -- a string concatenates. The port keeps a row only when every
  cell it checks is a JSON number.

  RANDOM: k-means draws its initial centroids from Math.random -- here the
  state AParams.Random points at (the chart's, through the dataset cache).

  ERRORS are ETyTransformError: the dataset has no table and the control
  says why. }
interface

uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.DataTransform;

{ Register the three under their 'ecStat:' names (again). }
procedure TyRegisterEcStatTransforms;

implementation

uses
  tyControls.AdvChart.Data, tyControls.AdvChart.Scale, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.Dataset, tyControls.AdvChart.Jitter, tyControls.StrConsts;

const
  { past these the port refuses where upstream would run (and run) }
  cMaxPolyOrder = 64;
  cMaxTicks = 100000;
  cMaxClusters = 1000;
  cMaxKMeansPasses = 100000;
  cMaxNewIndex = 100000;

var
  { Math.LN10, Math.LN2, Math.E, -1/3 and the three square roots, as bits }
  GLn10, GLn2, GE, GMinusThird, GSqrt50, GSqrt10, GSqrt2: Double;

function FromBits(AQ: QWord): Double;
begin
  Move(AQ, Result, SizeOf(Result));
end;

type
  TRowList = array of TJSONArray;
  TDoubleRows = array of TTyDoubleArray;

{ ==================== JavaScript values ==================== }

{ Number(v) of an option value; nil (undefined) is not-a-number }
function JsNum(AData: TJSONData): Double;
begin
  if AData = nil then Exit(NaN);
  case AData.JSONType of
    jtNull: Result := 0;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtNumber: Result := AData.AsFloat;
    jtString: Result := TyJsToNumber(AData.AsString);
    jtArray: Result := TyJsToNumber(TyJsTextOf(AData));
  else
    Result := NaN;
  end;
end;

{ ecStat's isNumber: `null === v ? NaN : +v`, a number that is not NaN }
function JsIsNumber(AData: TJSONData): Boolean;
begin
  if (AData <> nil) and (AData.JSONType = jtNull) then Exit(False);
  Result := not IsNan(JsNum(AData));
end;

{ A cell that counts as a number here: a JSON number (see the header) }
function CellIsNumber(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType = jtNumber) and not IsNan(AData.AsFloat);
end;

function CellAt(ARow: TJSONData; AIndex: Integer): TJSONData;
begin
  Result := nil;
  if AIndex < 0 then Exit;
  if (ARow is TJSONArray) and (AIndex < TJSONArray(ARow).Count) then
    Result := TJSONArray(ARow).Items[AIndex]
  else if ARow is TJSONObject then
    Result := TJSONObject(ARow).Find(IntToStr(AIndex));
end;

{ `row[d]` in arithmetic over a row the transform checked: the number, or
  not-a-number (undefined, or a column nobody checked) }
function CellNum(ARow: TJSONData; AIndex: Integer): Double;
var c: TJSONData;
begin
  c := CellAt(ARow, AIndex);
  if CellIsNumber(c) then Result := c.AsFloat else Result := NaN;
end;

{ `row[d] = v`: a write past the end leaves holes (null here); an index
  that is no array index (undefined, negative) writes nothing one can see }
procedure SetCell(ARow: TJSONArray; AIndex: Integer; AValue: TJSONData);
begin
  if AIndex < 0 then
  begin
    AValue.Free;
    Exit;
  end;
  while ARow.Count < AIndex do ARow.Add(TJSONNull.Create);
  if AIndex < ARow.Count then
  begin
    ARow.Delete(AIndex);
    ARow.Insert(AIndex, AValue);
  end
  else
    ARow.Add(AValue);
end;

function NumStr(AValue: Double): string;
begin
  Result := TyJsNumberToString(AValue);
end;

{ +(x).toFixed(p). [Milestone D1-D4: this turned every nought into +0,
  for TyJsToFixed gave -0 back as -0; it answers +0 for it itself now, and
  -0.001 to two places is -0 here as it is upstream ('-0.00').] }
function FixedNum(AValue: Double; APrecision: Integer): Double;
begin
  Result := TyJsToFixed(AValue, APrecision);
end;

function ConfigOf(const AParams: TTyTransformParams): TJSONObject;
begin
  { `params.config` or an empty object -- and a property of anything but an object is
    undefined }
  if AParams.Config is TJSONObject then Result := TJSONObject(AParams.Config)
  else Result := nil;
end;

function Get(AObj: TJSONObject; const AKey: string): TJSONData;
begin
  if AObj = nil then Result := nil else Result := AObj.Find(AKey);
end;

function IsNullish(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

{ ==================== dimensions ==================== }

type
  { normalizeExistingDimensions: undefined, one index, or a list }
  TDimSpec = record
    Given: Boolean;
    IsList: Boolean;
    Items: TTyIntegerArray;
  end;

{ normalizeExistingDimensions(params, dims): every one found by
  getDimensionInfo, or the transform throws }
function ExistingDims(ASrc: TTyExternalSource; ADims: TJSONData): TDimSpec;
var
  i, d: Integer;
  arr: TJSONArray;
begin
  Result := Default(TDimSpec);
  if IsNullish(ADims) then Exit;
  Result.Given := True;
  if ADims is TJSONArray then
  begin
    Result.IsList := True;
    arr := TJSONArray(ADims);
    SetLength(Result.Items, arr.Count);
    for i := 0 to arr.Count - 1 do
    begin
      d := ASrc.DimensionOf(arr.Items[i]);
      if d < 0 then
        raise ETyTransformError.CreateFmt(rsTyDsNoDimension, [TyJsTextOf(arr.Items[i])]);
      Result.Items[i] := d;
    end;
    Exit;
  end;
  d := ASrc.DimensionOf(ADims);
  if d < 0 then
    raise ETyTransformError.CreateFmt(rsTyDsNoDimension, [TyJsTextOf(ADims)]);
  SetLength(Result.Items, 1);
  Result.Items[0] := d;
end;

{ normalizeDimensions(dims, default): one index is a list of one; undefined
  is the default (Given False when there is none) }
function NormalizeDims(const ASpec: TDimSpec; const ADefault: array of Integer;
  AHasDefault: Boolean): TDimSpec;
var i: Integer;
begin
  Result := ASpec;
  if ASpec.Given then
  begin
    Result.IsList := True;
    Exit;
  end;
  if not AHasDefault then Exit;
  Result.Given := True;
  Result.IsList := True;
  SetLength(Result.Items, Length(ADefault));
  for i := 0 to High(ADefault) do Result.Items[i] := ADefault[i];
end;

{ The i-th dimension of a list, -1 (undefined) past its end }
function DimItem(const ASpec: TDimSpec; AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex <= High(ASpec.Items)) then Result := ASpec.Items[AIndex]
  else Result := -1;
end;

{ ==================== dataPreprocess ==================== }

{ size(data): the lengths down the first elements -- 1 for a list of
  objects (or nothing), 2 for a table, 3 or more when a cell is a list }
function DataDepth(ARows: TJSONArray; out AWidth: Integer): Integer;
var first: TJSONData;
begin
  AWidth := 0;
  Result := 1;
  if ARows.Count = 0 then Exit;
  first := ARows.Items[0];
  if not (first is TJSONArray) then Exit;
  Result := 2;
  AWidth := TJSONArray(first).Count;
  if (AWidth > 0) and (TJSONArray(first).Items[0] is TJSONArray) then Result := 3;
end;

{ dataPreprocess(data, dimensions): the rows whose every checked cell (a
  column of the first row's width that the dimensions name, or every
  column when none are given) is a number. A list that is not a table
  keeps its numbers -- the port's rows are never numbers, so nothing. }
function PreprocessRows(ARows: TJSONArray; const ADims: TDimSpec): TRowList;
var
  depth, width, i, p, n: Integer;
  row: TJSONData;
  ok: Boolean;
  checked: array of Boolean;
begin
  Result := nil;
  depth := DataDepth(ARows, width);
  if depth <> 2 then Exit;
  SetLength(checked, width);
  for p := 0 to width - 1 do checked[p] := not ADims.Given;
  if ADims.Given then
    for i := 0 to High(ADims.Items) do
      if (ADims.Items[i] >= 0) and (ADims.Items[i] < width) then checked[ADims.Items[i]] := True;
  n := 0;
  SetLength(Result, ARows.Count);
  for i := 0 to ARows.Count - 1 do
  begin
    row := ARows.Items[i];
    { cloneRawData made every row of a table of arrays a list }
    if not (row is TJSONArray) then Continue;
    ok := True;
    for p := 0 to width - 1 do
      if checked[p] and not CellIsNumber(CellAt(row, p)) then
      begin
        ok := False;
        Break;
      end;
    if ok then
    begin
      Result[n] := TJSONArray(row);
      Inc(n);
    end;
  end;
  SetLength(Result, n);
end;

{ dataPreprocess with toOneDimensionArray: the value of each kept row in the
  first dimension (0 when none are given) }
function PreprocessValues(ARows: TJSONArray; const ADims: TDimSpec): TTyDoubleArray;
var
  rows: TRowList;
  i, s: Integer;
begin
  rows := PreprocessRows(ARows, ADims);
  if ADims.Given then s := DimItem(ADims, 0) else s := 0;
  Result := nil;
  SetLength(Result, Length(rows));
  for i := 0 to High(rows) do Result[i] := CellNum(rows[i], s);
end;

{ ==================== regression ==================== }

type
  TRegMethod = (rmLinear, rmLinearThroughOrigin, rmExponential, rmLogarithmic,
    rmPolynomial);

  TRegFit = record
    Points: TJSONArray;
    Expression: string;
  end;

function R2(AValue: Double): string;
begin
  { Math.round(100 * v) / 100 }
  Result := NumStr(TyJsRound(100 * AValue) / 100);
end;

{ the point for row ARow: a copy with y replaced }
function PointOf(ARow: TJSONArray; AX, AY: Integer; AFit: Double): TJSONArray;
begin
  Result := TJSONArray(ARow.Clone);
  { `d[x] = f[x]`: the x written back -- undefined past the row }
  if (AX >= 0) and (AX >= Result.Count) then SetCell(Result, AX, TJSONNull.Create);
  SetCell(Result, AY, TJSONFloatNumber.Create(AFit));
end;

{ Gaussian elimination over AM, a list of columns: AM[col][row], the last
  column the right-hand side }
function Gaussian(var AM: TDoubleRows; AN: Integer): TTyDoubleArray;
var
  t, e, o, i, u, s, f, len: Integer;
  a: Double;
begin
  len := Length(AM);
  for t := 0 to len - 2 do
  begin
    e := t;
    for o := t + 1 to len - 2 do
      if Abs(AM[t][o]) > Abs(AM[t][e]) then e := o;
    for i := t to len - 1 do
    begin
      a := AM[i][t];
      AM[i][t] := AM[i][e];
      AM[i][e] := a;
    end;
    for u := t + 1 to len - 2 do
      for s := len - 1 downto t do
        AM[s][u] := AM[s][u] - AM[s][t] / AM[t][t] * AM[t][u];
  end;
  Result := nil;
  SetLength(Result, AN);
  for i := 0 to AN - 1 do Result[i] := NaN;
  f := len - 1;
  for o := len - 2 downto 0 do
  begin
    a := 0;
    for t := o + 1 to len - 2 do a := a + AM[t][o] * Result[t];
    Result[o] := (AM[f][o] - a) / AM[o][o];
  end;
end;

function FitRegression(AMethod: TRegMethod; const ARows: TRowList; AX, AY: Integer;
  AOrder: Double): TRegFit;
var
  n, k, l, p, c, s: Integer;
  o, i, a, u, sl, f, x, y, gr, ic, lg, v, h, ix, m: Double;
  mat: TDoubleRows;
  rhs, g: TTyDoubleArray;
  row: TJSONArray;
  sz: Double;
begin
  Result.Points := TJSONArray.Create;
  Result.Expression := '';
  try
    n := Length(ARows);
    case AMethod of
      rmLinear:
        begin
          o := 0; i := 0; a := 0; u := 0;
          for k := 0 to n - 1 do
          begin
            x := CellNum(ARows[k], AX);
            y := CellNum(ARows[k], AY);
            o := o + x;
            i := i + y;
            a := a + x * y;
            u := u + x * x;
          end;
          gr := (n * a - o * i) / (n * u - o * o);
          ic := i / n - gr * o / n;
          for k := 0 to n - 1 do
          begin
            x := CellNum(ARows[k], AX);
            Result.Points.Add(PointOf(ARows[k], AX, AY, gr * x + ic));
          end;
          Result.Expression := 'y = ' + R2(gr) + 'x + ' + R2(ic);
        end;
      rmLinearThroughOrigin:
        begin
          o := 0; i := 0;
          for k := 0 to n - 1 do
          begin
            x := CellNum(ARows[k], AX);
            y := CellNum(ARows[k], AY);
            o := o + x * x;
            i := i + x * y;
          end;
          gr := i / o;
          for k := 0 to n - 1 do
          begin
            x := CellNum(ARows[k], AX);
            Result.Points.Add(PointOf(ARows[k], AX, AY, x * gr));
          end;
          Result.Expression := 'y = ' + R2(gr) + 'x';
        end;
      rmExponential:
        begin
          o := 0; i := 0; a := 0; u := 0; sl := 0; f := 0;
          for k := 0 to n - 1 do
          begin
            x := CellNum(ARows[k], AX);
            y := CellNum(ARows[k], AY);
            o := o + x;
            i := i + y;
            f := f + x * y;
            a := a + x * x * y;
            u := u + y * TyJsLog(y);
            sl := sl + x * y * TyJsLog(y);
          end;
          v := i * a - f * f;
          h := TyJsPow(GE, (a * u - f * sl) / v);
          ix := (i * sl - f * u) / v;
          for k := 0 to n - 1 do
          begin
            x := CellNum(ARows[k], AX);
            Result.Points.Add(PointOf(ARows[k], AX, AY, h * TyJsPow(GE, ix * x)));
          end;
          Result.Expression := 'y = ' + R2(h) + 'e^(' + R2(ix) + 'x)';
        end;
      rmLogarithmic:
        begin
          o := 0; i := 0; a := 0; u := 0;
          for k := 0 to n - 1 do
          begin
            x := CellNum(ARows[k], AX);
            y := CellNum(ARows[k], AY);
            o := o + TyJsLog(x);
            i := i + y * TyJsLog(x);
            a := a + y;
            u := u + TyJsPow(TyJsLog(x), 2);
          end;
          gr := (n * i - a * o) / (n * u - o * o);
          ic := (a - gr * o) / n;
          for k := 0 to n - 1 do
          begin
            x := CellNum(ARows[k], AX);
            Result.Points.Add(PointOf(ARows[k], AX, AY, gr * TyJsLog(x) + ic));
          end;
          Result.Expression := 'y = ' + R2(ic) + ' + ' + R2(gr) + 'ln(x)';
        end;
      rmPolynomial:
        begin
          { s = order + 1 columns; `new Array(s)` throws for a fraction or a
            negative length }
          sz := AOrder + 1;
          s := Trunc(sz);
          mat := nil;
          SetLength(rhs, 0);
          for l := 0 to s - 1 do
          begin
            f := 0;
            for c := 0 to n - 1 do
            begin
              row := ARows[c];
              f := f + CellNum(row, AY) * TyJsPow(CellNum(row, AX), l);
            end;
            SetLength(rhs, Length(rhs) + 1);
            rhs[High(rhs)] := f;
            SetLength(mat, Length(mat) + 1);
            SetLength(mat[High(mat)], s);
            for p := 0 to s - 1 do
            begin
              m := 0;
              for c := 0 to n - 1 do m := m + TyJsPow(CellNum(ARows[c], AX), l + p);
              mat[High(mat)][p] := m;
            end;
          end;
          SetLength(mat, Length(mat) + 1);
          mat[High(mat)] := rhs;
          g := Gaussian(mat, s);
          for l := 0 to n - 1 do
          begin
            row := ARows[l];
            m := 0;
            for c := 0 to High(g) do m := m + g[c] * TyJsPow(CellNum(row, AX), c);
            Result.Points.Add(PointOf(row, AX, AY, m));
          end;
          Result.Expression := 'y = ';
          for l := High(g) downto 0 do
            if l > 1 then
            begin
              lg := TyJsPow(10, l + 1);
              Result.Expression := Result.Expression
                + NumStr(TyJsRound(g[l] * lg) / lg) + 'x^' + IntToStr(l) + ' + ';
            end
            else if l = 1 then
              Result.Expression := Result.Expression + R2(g[l]) + 'x + '
            else
              Result.Expression := Result.Expression + R2(g[l]);
        end;
    end;
  except
    Result.Points.Free;
    raise;
  end;
end;

type
  { the points' sort: `a[x] - b[x]`, not-a-number as nought }
  TPointSort = class
    Keys: TTyDoubleArray;
    function Compare(A, B: Integer): Integer;
  end;

function TPointSort.Compare(A, B: Integer): Integer;
var d: Double;
begin
  d := Keys[A] - Keys[B];
  if d < 0 then Result := -1
  else if d > 0 then Result := 1
  else Result := 0;
end;

{ The upstream's dimensions as cloneAllDimensionInfo hands them on }
function DimInfoObject(const ADim: TTyTransformDim): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('index', ADim.Index);
  if ADim.HasName then Result.Add('name', ADim.Name);
  if ADim.HasDisplayName then Result.Add('displayName', ADim.DisplayName);
end;

procedure RegressionTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var
  up: TTyExternalSource;
  cfg: TJSONObject;
  md, ord, fo: TJSONData;
  key, formulaOn: string;
  method: TRegMethod;
  order: Double;
  raw: TJSONArray;
  dims: TDimSpec;
  rows: TRowList;
  fit: TRegFit;
  sorter: TPointSort;
  idx: TTyIntegerArray;
  sorted: TJSONArray;
  i, xd, yd, last: Integer;
  dimsOut: TJSONArray;
  hasFormula, onIt: Boolean;
begin
  up := AParams.Upstream;
  cfg := ConfigOf(AParams);
  { `config.method || 'linear'`, then `methods[method]` }
  md := Get(cfg, 'method');
  if TyDatasetTruthy(md) then key := TyJsTextOf(md) else key := 'linear';
  if key = 'linear' then method := rmLinear
  else if key = 'linearThroughOrigin' then method := rmLinearThroughOrigin
  else if key = 'exponential' then method := rmExponential
  else if key = 'logarithmic' then method := rmLogarithmic
  else if key = 'polynomial' then method := rmPolynomial
  else raise ETyTransformError.CreateFmt(rsTyStatRegMethod, [key]);
  raw := up.CloneRawData;
  fit.Points := nil;
  dimsOut := nil;
  try
    dims := NormalizeDims(ExistingDims(up, Get(cfg, 'dimensions')), [0, 1], True);
    order := 2;
    if method = rmPolynomial then
    begin
      ord := Get(cfg, 'order');
      if not IsNullish(ord) then
      begin
        if ord.JSONType <> jtNumber then
          raise ETyTransformError.CreateFmt(rsTyStatPolyOrder, [cMaxPolyOrder]);
        order := ord.AsFloat;
      end;
      { `new Array(order + 1)`: a whole length; the port stops at an order
        it cannot finish }
      if IsNan(order) or (Frac(order) <> 0) or (order < -1) or (order > cMaxPolyOrder) then
        raise ETyTransformError.CreateFmt(rsTyStatPolyOrder, [cMaxPolyOrder]);
    end;
    rows := PreprocessRows(raw, dims);
    xd := DimItem(dims, 0);
    yd := DimItem(dims, 1);
    fit := FitRegression(method, rows, xd, yd, order);
    { the points sorted by x, as V8 sorts them }
    sorter := TPointSort.Create;
    try
      SetLength(sorter.Keys, fit.Points.Count);
      SetLength(idx, fit.Points.Count);
      for i := 0 to fit.Points.Count - 1 do
      begin
        sorter.Keys[i] := CellNum(fit.Points.Items[i], xd);
        idx[i] := i;
      end;
      TyJsArraySort(idx, @sorter.Compare);
    finally
      sorter.Free;
    end;
    sorted := TJSONArray.Create;
    for i := 0 to High(idx) do
      sorted.Add(fit.Points.Items[idx[i]].Clone);
    fit.Points.Free;
    fit.Points := sorted;
    { formulaOn: null is 'end'; anything but 'none' writes column 2 }
    fo := Get(cfg, 'formulaOn');
    hasFormula := True;
    formulaOn := 'end';
    if not IsNullish(fo) then
    begin
      if fo.JSONType = jtString then formulaOn := fo.AsString
      else formulaOn := #0;
    end;
    if formulaOn = 'none' then hasFormula := False;
    if hasFormula then
    begin
      last := sorted.Count - 1;
      for i := 0 to sorted.Count - 1 do
      begin
        onIt := ((formulaOn = 'start') and (i = 0)) or (formulaOn = 'all')
          or ((formulaOn = 'end') and (i = last));
        if onIt then SetCell(TJSONArray(sorted.Items[i]), 2, TJSONString.Create(fit.Expression))
        else SetCell(TJSONArray(sorted.Items[i]), 2, TJSONString.Create(''));
      end;
      { cloneAllDimensionInfo() with [2] an empty object -- an upstream of fewer than
        two dimensions leaves a hole, which createSource reads `.type` of }
      if up.DimCount < 2 then
        raise ETyTransformError.Create(rsTyStatDimHole);
      dimsOut := TJSONArray.Create;
      for i := 0 to up.DimCount - 1 do
        if i = 2 then dimsOut.Add(TJSONObject.Create)
        else dimsOut.Add(DimInfoObject(up.Dim(i)));
      if up.DimCount = 2 then dimsOut.Add(TJSONObject.Create);
    end;
    TyAddTransformResult(AResults, fit.Points, dimsOut);
    fit.Points := nil;
    dimsOut := nil;
  finally
    raw.Free;
    fit.Points.Free;
    dimsOut.Free;
  end;
end;

{ ==================== histogram ==================== }

{ module 10 / 12: max and min over the numbers }
function MaxOf(const AV: TTyDoubleArray): Double;
var i: Integer;
begin
  Result := NegInfinity;
  for i := 0 to High(AV) do
    if (not IsNan(AV[i])) and (AV[i] > Result) then Result := AV[i];
end;

function MinOf(const AV: TTyDoubleArray): Double;
var i: Integer;
begin
  Result := Infinity;
  for i := 0 to High(AV) do
    if (not IsNan(AV[i])) and (AV[i] < Result) then Result := AV[i];
end;

{ sum (numbers only), mean (over every entry), sampleVariance, deviation }
function SumOf(const AV: TTyDoubleArray): Double;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(AV) do
    if not IsNan(AV[i]) then Result := Result + AV[i];
end;

function DeviationOf(const AV: TTyDoubleArray): Double;
var
  i: Integer;
  mean, t, a: Double;
begin
  if Length(AV) < 2 then Exit(0);
  mean := SumOf(AV) / Length(AV);
  a := 0;
  for i := 0 to High(AV) do
    if not IsNan(AV[i]) then
    begin
      t := AV[i] - mean;
      a := a + t * t;
    end;
  a := a / (Length(AV) - 1);
  { `v ? Math.sqrt(v) : v` }
  if IsNan(a) or (a = 0) then Result := a else Result := Sqrt(a);
end;

{ quantile over an ascending list }
function QuantileOf(const AV: TTyDoubleArray; AP: Double): Double;
var
  t, o: Integer;
  e, i, a: Double;
begin
  t := Length(AV);
  if t = 0 then Exit(0);
  if (AP <= 0) or (t < 2) then Exit(AV[0]);
  if AP >= 1 then Exit(AV[t - 1]);
  e := (t - 1) * AP;
  o := Trunc(JsFloor(e));
  i := AV[o];
  a := AV[o + 1];
  Result := i + (a - i) * (e - o);
end;

type
  TValueSort = class
    Values: TTyDoubleArray;
    function Compare(A, B: Integer): Integer;
  end;

function TValueSort.Compare(A, B: Integer): Integer;
begin
  { ascending: 1, -1, 0 -- and not-a-number, read as nought }
  if Values[A] > Values[B] then Result := 1
  else if Values[A] < Values[B] then Result := -1
  else Result := 0;
end;

procedure SortValues(var AV: TTyDoubleArray);
var
  s: TValueSort;
  idx: TTyIntegerArray;
  i: Integer;
  out_: TTyDoubleArray;
begin
  s := TValueSort.Create;
  try
    s.Values := AV;
    SetLength(idx, Length(AV));
    for i := 0 to High(idx) do idx[i] := i;
    TyJsArraySort(idx, @s.Compare);
    SetLength(out_, Length(AV));
    for i := 0 to High(idx) do out_[i] := AV[idx[i]];
    AV := out_;
  finally
    s.Free;
  end;
end;

type
  TBinMethod = (bmSquareRoot, bmScott, bmFreedmanDiaconis, bmSturges);

function BinCount(AMethod: TBinMethod; var AV: TTyDoubleArray; AMin, AMax: Double): Double;
var n: Integer;
begin
  n := Length(AV);
  case AMethod of
    bmSquareRoot:
      begin
        Result := JsCeil(Sqrt(n));
        if Result > 50 then Result := 50;
      end;
    bmScott:
      Result := JsCeil((AMax - AMin) / (3.5 * DeviationOf(AV) * TyJsPow(n, GMinusThird)));
    bmFreedmanDiaconis:
      begin
        SortValues(AV);
        Result := JsCeil((AMax - AMin)
          / (2 * (QuantileOf(AV, 0.75) - QuantileOf(AV, 0.25)) * TyJsPow(n, GMinusThird)));
      end;
  else
    Result := JsCeil(TyJsLog(n) / GLn2) + 1;
  end;
end;

{ ecStat's quantityExponent }
function QuantityExponent(AValue: Double): Double;
begin
  if AValue = 0 then Exit(0);
  Result := JsFloor(TyJsLog(AValue) / GLn10);
  if AValue / TyJsPow(10, Result) >= 10 then Result := Result + 1;
end;

{ the nice step: a power of ten times 1, 2, 5 or 10, and its decimals }
procedure NiceStep(AMin, AMax, ACount: Double; out AStep: Double; out APrec: Integer);
var o, i, a, u, s: Double;
begin
  o := Abs(AMax - AMin) / ACount;
  i := QuantityExponent(o);
  a := TyJsPow(10, i);
  u := o / a;
  if u >= GSqrt50 then a := a * 10
  else if u >= GSqrt10 then a := a * 5
  else if u >= GSqrt2 then a := a * 2;
  if i < 0 then s := -i else s := 0;
  { toFixed past 20 places: the port's toFixed stops at 20 }
  if s > 20 then raise ETyTransformError.Create(rsTyStatBinPrecision);
  APrec := Trunc(s);
  if AMax >= AMin then AStep := FixedNum(a, APrec) else AStep := FixedNum(-a, APrec);
end;

{ range(start, end, step, precision) }
function TickRange(AStart, AEnd, AStep: Double; APrec: Integer): TTyDoubleArray;
var
  a: Double;
  n, s: Integer;
begin
  a := JsCeil(FixedNum((AEnd - AStart) / AStep, APrec));
  { `new Array(a + 1)`: a length or a RangeError }
  if IsNan(a) or IsInfinite(a) or (a + 1 < 0) then
    raise ETyTransformError.Create(rsTyStatBinLayout);
  if a + 1 > cMaxTicks then
    raise ETyTransformError.CreateFmt(rsTyStatTooManyBins, [cMaxTicks]);
  n := Trunc(a) + 1;
  Result := nil;
  SetLength(Result, n);
  for s := 0 to n - 1 do Result[s] := FixedNum(AStart + s * AStep, APrec);
end;

function TickAt(const ATicks: TTyDoubleArray; AIndex: Integer): Double;
begin
  if (AIndex >= 0) and (AIndex <= High(ATicks)) then Result := ATicks[AIndex]
  else Result := NaN;
end;

{ bisect(ticks, v, 0, n): a value on a tick goes to the bin after it }
function Bisect(const ATicks: TTyDoubleArray; AValue: Double; ALo, AHi: Integer): Integer;
var mid: Integer;
begin
  while ALo < AHi do
  begin
    mid := (ALo + AHi) div 2;
    if ATicks[mid] > AValue then AHi := mid
    else if ATicks[mid] < AValue then ALo := mid + 1
    else Exit(mid + 1);
  end;
  Result := ALo;
end;

procedure HistogramTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var
  up: TTyExternalSource;
  cfg: TJSONObject;
  md: TJSONData;
  key: string;
  method: TBinMethod;
  raw: TJSONArray;
  values, ticks: TTyDoubleArray;
  vmax, vmin, count, step: Double;
  prec, b, e, k: Integer;
  x0, x1: TTyDoubleArray;
  counts: TTyIntegerArray;
  data, custom, row: TJSONArray;
begin
  up := AParams.Upstream;
  cfg := ConfigOf(AParams);
  md := Get(cfg, 'method');
  method := bmSquareRoot;
  if not IsNullish(md) then
  begin
    key := TyJsTextOf(md);
    if key = 'squareRoot' then method := bmSquareRoot
    else if key = 'scott' then method := bmScott
    else if key = 'freedmanDiaconis' then method := bmFreedmanDiaconis
    else if key = 'sturges' then method := bmSturges
    else raise ETyTransformError.CreateFmt(rsTyStatBinMethod, [key]);
  end;
  raw := up.CloneRawData;
  try
    values := PreprocessValues(raw,
      NormalizeDims(ExistingDims(up, Get(cfg, 'dimensions')), [], False));
  finally
    raw.Free;
  end;
  vmax := MaxOf(values);
  vmin := MinOf(values);
  count := BinCount(method, values, vmin, vmax);
  NiceStep(vmin, vmax, count, step, prec);
  ticks := TickRange(FixedNum(JsCeil(vmin / step) * step, prec),
    FixedNum(JsFloor(vmax / step) * step, prec), step, prec);
  b := Length(ticks);
  SetLength(x0, b + 1);
  SetLength(x1, b + 1);
  SetLength(counts, b + 1);
  for e := 0 to b do
  begin
    if e > 0 then x0[e] := TickAt(ticks, e - 1)
    else if TickAt(ticks, e) - vmin = step then x0[e] := vmin
    else x0[e] := TickAt(ticks, e) - step;
    if e < b then x1[e] := TickAt(ticks, e)
    else if vmax - TickAt(ticks, e - 1) = step then x1[e] := vmax
    else x1[e] := TickAt(ticks, e - 1) + step;
    counts[e] := 0;
  end;
  for k := 0 to High(values) do
    if (vmin <= values[k]) and (values[k] <= vmax) then
      Inc(counts[Bisect(ticks, values[k], 0, b)]);
  data := TJSONArray.Create;
  custom := TJSONArray.Create;
  try
    for e := 0 to b do
    begin
      row := TJSONArray.Create;
      data.Add(row);
      row.Add(TJSONFloatNumber.Create(FixedNum((x0[e] + x1[e]) / 2, prec)));
      row.Add(counts[e]);
      row.Add(TJSONFloatNumber.Create(x0[e]));
      row.Add(TJSONFloatNumber.Create(x1[e]));
      row.Add(NumStr(x0[e]) + ' - ' + NumStr(x1[e]));
      row := TJSONArray.Create;
      custom.Add(row);
      row.Add(TJSONFloatNumber.Create(x0[e]));
      row.Add(TJSONFloatNumber.Create(x1[e]));
      row.Add(counts[e]);
    end;
  except
    data.Free;
    custom.Free;
    raise;
  end;
  TyAddTransformResult(AResults, data,
    TJSONArray.Create(['MeanOfV0V1', 'VCount', 'V0', 'V1', 'DisplayableName']));
  TyAddTransformResult(AResults, custom);
end;

{ ==================== clustering ==================== }

type
  { normalizeNewDimensions: one index-and-name, or a list of them }
  TNewDim = record
    Index: Double;
    Name: TJSONData;   // borrowed; nil for undefined
  end;
  TNewDims = record
    Given: Boolean;
    IsList: Boolean;
    Items: array of TNewDim;
  end;

function NewDimOf(AData: TJSONData): TNewDim;
var ix: TJSONData;
begin
  Result.Name := nil;
  { a number, or an object whose index is one }
  if not (AData is TJSONObject) then
  begin
    if not JsIsNumber(AData) then raise ETyTransformError.Create(rsTyStatNewDim);
    if AData.JSONType <> jtNumber then raise ETyTransformError.Create(rsTyStatIndexNotNumber);
    Result.Index := AData.AsFloat;
    Exit;
  end;
  ix := TJSONObject(AData).Find('index');
  if not JsIsNumber(ix) then raise ETyTransformError.Create(rsTyStatNewDim);
  if ix.JSONType <> jtNumber then raise ETyTransformError.Create(rsTyStatIndexNotNumber);
  Result.Index := ix.AsFloat;
  Result.Name := TJSONObject(AData).Find('name');
end;

function NewDims(AData: TJSONData): TNewDims;
var i: Integer;
begin
  Result := Default(TNewDims);
  if IsNullish(AData) then Exit;
  Result.Given := True;
  if AData is TJSONArray then
  begin
    Result.IsList := True;
    SetLength(Result.Items, TJSONArray(AData).Count);
    for i := 0 to High(Result.Items) do
      Result.Items[i] := NewDimOf(TJSONArray(AData).Items[i]);
    Exit;
  end;
  SetLength(Result.Items, 1);
  Result.Items[0] := NewDimOf(AData);
end;

{ The array index a write to key AValue lands on: a whole number from
  nought below 2^32 - 1; -1 when the write lands on a property instead.
  The port stops at cMaxNewIndex, where upstream would make a row (or a
  list of names) of that many holes. }
function ElementIndex(AValue: Double): Integer;
begin
  if IsNan(AValue) or (AValue < 0) or (Frac(AValue) <> 0) or (AValue >= 4294967295.0) then
    Exit(-1);
  if AValue >= cMaxNewIndex then
    raise ETyTransformError.CreateFmt(rsTyStatIndexTooFar, [cMaxNewIndex]);
  Result := Trunc(AValue);
end;

type
  TExtent = record
    Min, Max, Span: Double;
  end;
  TExtentArray = array of TExtent;

  TKMeans = class
  public
    { the points' values in the clustered dimensions, by position }
    Vals: TDoubleRows;
    Spans: TTyDoubleArray;
    DimCount: Integer;
    Random: PLongWord;
    function Dist(const APoint, ACentre: TTyDoubleArray): Double;
    function Mean(const AMembers: TTyIntegerArray): TTyDoubleArray;
    procedure Run(const AMembers: TTyIntegerArray; out ACentres: TDoubleRows;
      out AAssign: TTyIntegerArray; out ADist: TTyDoubleArray);
  end;

{ the distance: the squares of the differences over each dimension's span
  (the whole table's), a dimension with no span left out }
function TKMeans.Dist(const APoint, ACentre: TTyDoubleArray): Double;
var
  a: Integer;
  u, l: Double;
begin
  Result := 0;
  for a := 0 to DimCount - 1 do
  begin
    u := Spans[a];
    if IsNan(u) or (u = 0) then Continue;
    l := (APoint[a] - ACentre[a]) / u;
    Result := Result + TyJsPow(l, 2);
  end;
end;

function TKMeans.Mean(const AMembers: TTyIntegerArray): TTyDoubleArray;
var
  a, u: Integer;
  t: Double;
begin
  Result := nil;
  SetLength(Result, DimCount);
  for a := 0 to DimCount - 1 do
  begin
    t := 0;
    for u := 0 to High(AMembers) do t := t + Vals[AMembers[u]][a];
    Result[a] := t / Length(AMembers);
  end;
end;

{ kMeans(points, 2): two random centres in the members' own extents, then
  assign and recentre until no point moves }
procedure TKMeans.Run(const AMembers: TTyIntegerArray; out ACentres: TDoubleRows;
  out AAssign: TTyIntegerArray; out ADist: TTyDoubleArray);
var
  n, a, i, p, d, best, passes: Integer;
  mn, mx, span, s, o: Double;
  changed: Boolean;
  members: TTyIntegerArray;
begin
  n := Length(AMembers);
  SetLength(AAssign, n);
  SetLength(ADist, n);
  for p := 0 to n - 1 do
  begin
    AAssign[p] := 0;
    ADist[p] := 0;
  end;
  SetLength(ACentres, 2);
  SetLength(ACentres[0], DimCount);
  SetLength(ACentres[1], DimCount);
  for a := 0 to DimCount - 1 do
  begin
    mn := Infinity;
    mx := NegInfinity;
    for p := 0 to n - 1 do
    begin
      s := Vals[AMembers[p]][a];
      if mn > s then mn := s;
      if mx < s then mx := s;
    end;
    span := mx - mn;
    for i := 0 to 1 do
      ACentres[i][a] := mn + span * TyJitterRandom(Random^);
  end;
  changed := True;
  passes := 0;
  while changed do
  begin
    Inc(passes);
    if passes > cMaxKMeansPasses then raise ETyTransformError.Create(rsTyStatNoConverge);
    changed := False;
    for p := 0 to n - 1 do
    begin
      o := Infinity;
      best := -1;
      for d := 0 to 1 do
      begin
        s := Dist(Vals[AMembers[p]], ACentres[d]);
        if s < o then
        begin
          o := s;
          best := d;
        end;
      end;
      if AAssign[p] <> best then changed := True;
      AAssign[p] := best;
      ADist[p] := o;
    end;
    for d := 0 to 1 do
    begin
      members := nil;
      for p := 0 to n - 1 do
        if AAssign[p] = d then
        begin
          SetLength(members, Length(members) + 1);
          members[High(members)] := AMembers[p];
        end;
      ACentres[d] := Mean(members);
    end;
  end;
end;

procedure ClusteringTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var
  up: TTyExternalSource;
  cfg: TJSONObject;
  cc, cell: TJSONData;
  count: Double;
  idxDim, centDims: TNewDims;
  dimSpec, dims: TDimSpec;
  raw, data, centroids, row, dimsOut: TJSONArray;
  rows: TRowList;
  width, depth, i, a, n, o, k, f, l, chosen, ci, rowCi: Integer;
  ext: TExtentArray;
  v: Double;
  km: TKMeans;
  cl: TTyIntegerArray;
  errs: TTyDoubleArray;
  cents: TDoubleRows;
  members: TTyIntegerArray;
  others: TTyDoubleArray;
  kc: TDoubleRows;
  ka: TTyIntegerArray;
  kd: TTyDoubleArray;
  bestC: TDoubleRows;
  bestA: TTyIntegerArray;
  bestD: TTyDoubleArray;
  s, t, j, tj: Double;
  splits: Integer;
  named: array of Boolean;

  { `names[index] = name`: past the end, holes first }
  procedure Name(AIndex: Double; AValue: TJSONData);
  var e: Integer;
  begin
    e := ElementIndex(AIndex);
    if e < 0 then Exit;
    while dimsOut.Count <= e do
    begin
      dimsOut.Add(TJSONNull.Create);
      SetLength(named, Length(named) + 1);
      named[High(named)] := False;
    end;
    dimsOut.Delete(e);
    if IsNullish(AValue) then dimsOut.Insert(e, TJSONNull.Create)
    else dimsOut.Insert(e, AValue.Clone);
    named[e] := True;
  end;

begin
  up := AParams.Upstream;
  cfg := ConfigOf(AParams);
  cc := Get(cfg, 'clusterCount');
  if not JsIsNumber(cc) or (JsNum(cc) <= 0) then
    raise ETyTransformError.Create(rsTyStatClusterCount);
  { `clusterCount === 1`: an empty object and an empty table -- a first
    result with no data }
  if (cc.JSONType = jtNumber) and (cc.AsFloat = 1) then
  begin
    TyAddTransformResult(AResults, nil);
    TyAddTransformResult(AResults, TJSONArray.Create);
    Exit;
  end;
  count := JsNum(cc);
  idxDim := NewDims(Get(cfg, 'outputClusterIndexDimension'));
  centDims := NewDims(Get(cfg, 'outputCentroidDimensions'));
  if not idxDim.Given then raise ETyTransformError.Create(rsTyStatClusterIndex);
  { a list here is a list's index, which isNumber reads through `+[...]` --
    the port asks for one index }
  if idxDim.IsList then raise ETyTransformError.Create(rsTyStatIndexNotNumber);
  raw := up.CloneRawData;
  data := nil;
  centroids := nil;
  dimsOut := nil;
  km := TKMeans.Create;
  try
    dimSpec := ExistingDims(up, Get(cfg, 'dimensions'));
    { hierarchicalKMeans: under two clusters there is no result }
    if count < 2 then raise ETyTransformError.Create(rsTyStatClusterCount);
    if count > cMaxClusters then
      raise ETyTransformError.CreateFmt(rsTyStatTooManyClusters, [cMaxClusters]);
    { the dimensions: every column of the first row when none are given }
    depth := DataDepth(raw, width);
    if (depth >= 2) and not dimSpec.Given then
    begin
      SetLength(dims.Items, width);
      for i := 0 to width - 1 do dims.Items[i] := i;
      dims.Given := True;
      dims.IsList := True;
    end
    else if not dimSpec.Given then
    begin
      dims := Default(TDimSpec);
      dims.Given := True;
      dims.IsList := True;
    end
    else
      dims := NormalizeDims(dimSpec, [], False);
    { the extents over the WHOLE table, every row as it stands: a null
      reads as nought, a word as nothing }
    SetLength(ext, Length(dims.Items));
    for a := 0 to High(ext) do
    begin
      ext[a].Min := Infinity;
      ext[a].Max := NegInfinity;
    end;
    for i := 0 to raw.Count - 1 do
      for a := 0 to High(ext) do
      begin
        if dims.Items[a] < 0 then cell := nil
        else cell := CellAt(raw.Items[i], dims.Items[a]);
        v := JsNum(cell);
        if ext[a].Min > v then ext[a].Min := v;
        if ext[a].Max < v then ext[a].Max := v;
      end;
    km.DimCount := Length(dims.Items);
    SetLength(km.Spans, km.DimCount);
    for a := 0 to High(ext) do
    begin
      ext[a].Span := ext[a].Max - ext[a].Min;
      km.Spans[a] := ext[a].Span;
    end;
    km.Random := AParams.Random;
    rows := PreprocessRows(raw, dims);
    n := Length(rows);
    SetLength(km.Vals, n);
    for i := 0 to n - 1 do
    begin
      SetLength(km.Vals[i], km.DimCount);
      for a := 0 to km.DimCount - 1 do km.Vals[i][a] := CellNum(rows[i], dims.Items[a]);
    end;
    { every point in cluster 0, its error the distance to the mean }
    SetLength(cl, n);
    SetLength(errs, n);
    SetLength(members, n);
    for i := 0 to n - 1 do
    begin
      cl[i] := 0;
      members[i] := i;
    end;
    SetLength(cents, 1);
    cents[0] := km.Mean(members);
    for i := 0 to n - 1 do errs[i] := km.Dist(km.Vals[i], cents[0]);
    { split the cluster whose split leaves the least error, until there are
      enough }
    splits := 1;
    while splits < count do
    begin
      s := Infinity;
      chosen := -1;
      bestC := nil;
      bestA := nil;
      bestD := nil;
      for o := 0 to High(cents) do
      begin
        members := nil;
        others := nil;
        for i := 0 to n - 1 do
          if cl[i] = o then
          begin
            SetLength(members, Length(members) + 1);
            members[High(members)] := i;
          end
          else
          begin
            SetLength(others, Length(others) + 1);
            others[High(others)] := errs[i];
          end;
        km.Run(members, kc, ka, kd);
        t := 0;
        for i := 0 to High(kd) do t := t + kd[i];
        j := 0;
        for i := 0 to High(others) do j := j + others[i];
        tj := t + j;
        if tj < s then
        begin
          s := j + t;
          chosen := o;
          bestC := kc;
          bestA := ka;
          bestD := kd;
        end;
      end;
      if chosen < 0 then raise ETyTransformError.Create(rsTyStatNoSplit);
      for i := 0 to High(bestA) do
        if bestA[i] = 0 then bestA[i] := chosen
        else if bestA[i] = 1 then bestA[i] := Length(cents);
      cents[chosen] := bestC[0];
      SetLength(cents, Length(cents) + 1);
      cents[High(cents)] := bestC[1];
      k := 0;
      i := 0;
      while (i < n) and (k <= High(bestA)) do
      begin
        if cl[i] = chosen then
        begin
          cl[i] := bestA[k];
          errs[i] := bestD[k];
          Inc(k);
        end;
        Inc(i);
      end;
      Inc(splits);
    end;
    { the rows out: each point's copy with its cluster at the index, and
      the centroid's values at the centroid dimensions }
    ci := ElementIndex(idxDim.Items[0].Index);
    data := TJSONArray.Create;
    for i := 0 to n - 1 do
    begin
      row := TJSONArray(rows[i].Clone);
      data.Add(row);
      if ci >= 0 then SetCell(row, ci, TJSONIntegerNumber.Create(cl[i]));
    end;
    if centDims.Given then
      for i := 0 to n - 1 do
      begin
        rowCi := cl[i];
        { `centroids[cluster].length`: a point in no cluster has none }
        if (rowCi < 0) or (rowCi > High(cents)) then
          raise ETyTransformError.Create(rsTyStatUnassigned);
        if not centDims.IsList then Continue;
        l := Min(Length(cents[rowCi]), Length(centDims.Items));
        for f := 0 to l - 1 do
        begin
          k := ElementIndex(centDims.Items[f].Index);
          if k >= 0 then
            SetCell(TJSONArray(data.Items[i]), k, TJSONFloatNumber.Create(cents[rowCi][f]));
        end;
      end;
    centroids := TJSONArray.Create;
    for o := 0 to High(cents) do
    begin
      row := TJSONArray.Create;
      centroids.Add(row);
      for a := 0 to High(cents[o]) do row.Add(TJSONFloatNumber.Create(cents[o][a]));
    end;
    { the names: the upstream's, the cluster index's, the centroids' --
      a hole left between them is a dimension createSource cannot read }
    dimsOut := TJSONArray.Create;
    SetLength(named, up.DimCount);
    for i := 0 to up.DimCount - 1 do
    begin
      if up.Dim(i).HasName then dimsOut.Add(up.Dim(i).Name)
      else dimsOut.Add(TJSONNull.Create);
      named[i] := True;
    end;
    Name(idxDim.Items[0].Index, idxDim.Items[0].Name);
    if centDims.IsList then
      for f := 0 to High(centDims.Items) do
        if not IsNullish(centDims.Items[f].Name) then
          Name(centDims.Items[f].Index, centDims.Items[f].Name);
    for i := 0 to High(named) do
      if not named[i] then raise ETyTransformError.Create(rsTyStatDimHole);
    TyAddTransformResult(AResults, data, dimsOut);
    data := nil;
    dimsOut := nil;
    TyAddTransformResult(AResults, centroids);
    centroids := nil;
  finally
    km.Free;
    raw.Free;
    data.Free;
    centroids.Free;
    dimsOut.Free;
  end;
end;

{ ==================== registration ==================== }

procedure TyRegisterEcStatTransforms;
begin
  TyRegisterDataTransform('ecStat:regression', @RegressionTransform);
  TyRegisterDataTransform('ecStat:histogram', @HistogramTransform);
  TyRegisterDataTransform('ecStat:clustering', @ClusteringTransform);
end;

initialization
  GLn10 := FromBits(QWord($40026BB1BBB55516));
  GLn2 := FromBits(QWord($3FE62E42FEFA39EF));
  GE := FromBits(QWord($4005BF0A8B145769));
  GMinusThird := FromBits(QWord($BFD5555555555555));
  GSqrt50 := FromBits(QWord($401C48C6001F0AC0));
  GSqrt10 := FromBits(QWord($40094C583ADA5B53));
  GSqrt2 := FromBits(QWord($3FF6A09E667F3BCD));
  TyRegisterEcStatTransforms;
end.
