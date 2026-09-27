unit tyControls.AdvChart.VisualMap;
{$mode objfpc}{$H+}
{ visualMap: a value on each datum turned into a colour, an opacity -- later a
  symbol and a size -- by a component that is not a series.

  WHAT THIS UNIT OWNS. The model -- which subtype, which series, which
  dimension, the extent and the range -- and the mapping arithmetic: the
  completed visual option, the order the visuals are applied in, the colour
  interpolation and the continuous visualMeta a line turns into a gradient.
  The component's own view (the bar, the handles, the texts) is not here yet.

  ZRENDER'S NUMBERS, NOT THE CHART'S. A mapped colour is kept as upstream
  keeps it -- four doubles, the alpha unquantised -- because the next mapping
  reads it back: a ramp between `rgba(80,112,221,0.1)` and `...0.5` is 0.3
  at its middle, not a byte. It becomes a TTyChartColor only where a mark is
  emitted. `undefined` is a real answer (a NaN value, a colour list written
  as null) and means NO FILL, which is not black.

  THE ORDER IS V8's. Upstream sorts the visual types with a comparator that
  is not a total order and so leaves the result to the engine's sort. For
  fewer than 64 items V8 runs its TimSort as one run plus a binary insertion
  sort, and that exact procedure is transcribed below; a "sensible" order
  disagrees with it on most lists, and the difference is visible -- whether
  an opacity survives as the gradient's alpha, whether a hue is lost.

  PURE apart from the axis the line gradient is measured on: JSON in,
  numbers out. }
interface
uses SysUtils, Math, fpjson,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Data,
     tyControls.AdvChart.Coord;

type
  { zrender's parsed colour, [r, g, b, a], with `undefined` beside it. }
  TTyVisualColor = record
    R, G, B, A: Double;
    Defined: Boolean;
  end;
  TTyVisualColorArray = array of TTyVisualColor;

  TTyVisualState = (tvsInRange, tvsOutOfRange);

  { One visual type of one state: its parsed colour stops, or its numbers. }
  TTyVisualMapping = record
    Kind: string;
    Colors: TTyVisualColorArray;
    Nums: TTyDoubleArray;
  end;
  TTyVisualMappingArray = array of TTyVisualMapping;

  { `dimension`: a store index or a dimension name. }
  TTyVisualDim = record
    Given: Boolean;
    IsName: Boolean;
    Num: Double;
    Name: string;
  end;

  TTyVisualSeriesTarget = record
    HasIndex: Boolean;
    SeriesIndex: Integer;
    HasId: Boolean;
    SeriesId: string;
    Dim: TTyVisualDim;
  end;

  TTyVisualMapSpec = record
    Index: Integer;
    { 'continuous' or 'piecewise' -- written, or what upstream's defaulter
      says; '' when the element is not a visualMap at all. }
    SubType: string;
    Show: Boolean;
    Extent0, Extent1: Double;
    Range0, Range1: Double;
    RangeAuto: Boolean;
    Unbounded: Boolean;
    { which series: seriesTargets, else seriesIndex / seriesId, else all }
    HasSeriesTargets: Boolean;
    SeriesTargets: array of TTyVisualSeriesTarget;
    AllSeries: Boolean;
    SeriesIndices: TTyIntegerArray;
    SeriesIds: TTyStringArray;
    Dim: TTyVisualDim;
    { the completed target, per state: the keys as the object holds them,
      and the mappings in the order they are applied }
    Keys: array[TTyVisualState] of TTyStringArray;
    States: array[TTyVisualState] of TTyVisualMappingArray;
  end;
  TTyVisualMapSpecArray = array of TTyVisualMapSpec;

  { What the visual pipeline wrote on one datum. }
  TTyVisualRow = record
    ColorSet: Boolean;
    Color: TTyVisualColor;
    OpacitySet: Boolean;
    Opacity: Double;
  end;
  TTyVisualRowArray = array of TTyVisualRow;

  TTyVisualStop = record
    Value: Double;
    Color: TTyVisualColor;
  end;
  TTyVisualStopArray = array of TTyVisualStop;

  { A continuous component's visualMeta for one series. }
  TTyVisualMeta = record
    VisualMap: Integer;
    Stops: TTyVisualStopArray;
    Outer0, Outer1: TTyVisualColor;
    { upstream's dimension index, and the coordinate it feeds ('x', 'y' or
      '' when it feeds none) }
    Dimension: Integer;
    CoordDim: string;
  end;
  TTyVisualMetaArray = array of TTyVisualMeta;

  TTyVisualGradStop = record
    Offset: Double;
    Coord: Double;
    Color: TTyVisualColor;
  end;
  TTyVisualGradStopArray = array of TTyVisualGradStop;

  { What a line's pen and area are painted with instead of the series colour:
    nothing (no visualMeta on x or y), one colour, or a global gradient. }
  TTyVisualLineFillKind = (vlfNone, vlfSolid, vlfGradient);
  TTyVisualLineFill = record
    Kind: TTyVisualLineFillKind;
    Solid: TTyVisualColor;
    { the gradient runs along y when Vertical, from Lo to Hi }
    Vertical: Boolean;
    Lo, Hi: Double;
    Stops: TTyVisualGradStopArray;
  end;

{ ---- colours ---- }
function TyVisualUndefined: TTyVisualColor;
function TyVisualRgba(AR, AG, AB, AA: Double): TTyVisualColor;
{ zrender's parse(); False when it answers undefined. }
function TyVisualTryParse(const AText: string; out AColor: TTyVisualColor): Boolean;
{ A visual list's stop: parsed, or [0,0,0,1] when it is not a colour. }
function TyVisualParsedStop(AData: TJSONData): TTyVisualColor;
function TyVisualFromChart(AColor: TTyChartColor): TTyVisualColor;
{ Quantised for a mark; undefined is 0, which paints nothing. }
function TyVisualToChart(const AColor: TTyVisualColor): TTyChartColor;
{ `rgba(r,g,b,a)` as zrender's stringify writes it. }
function TyVisualCss(const AColor: TTyVisualColor): string;
function TyVisualFastLerp(AN: Double;
  const AStops: TTyVisualColorArray): TTyVisualColor;
{ modifyHSL: the channels not flagged are kept. }
function TyVisualModifyHSL(const AColor: TTyVisualColor; AH, AS_, AL: Double;
  AHasH, AHasS, AHasL: Boolean): TTyVisualColor;
function TyVisualModifyAlpha(const AColor: TTyVisualColor;
  AAlpha: Double): TTyVisualColor;
{ The gradient a visualMap falls back on, from the theme's first series
  colour: [modifyHSL(accent, lightness 0.9), accent]. }
function TyVisualDefaultRamp(AAccent: TTyChartColor): TTyVisualColorArray;

{ ---- arithmetic ---- }
{ util/number linearMap, NaN passing through as NaN. }
function TyVmLinearMap(AValue, AD0, AD1, AR0, AR1: Double;
  AClamp: Boolean): Double;
function TyVisualIsValidType(const AType: string): Boolean;
{ VisualMapping.prepareVisualTypes on V8 -- see the unit header. }
function TyPrepareVisualTypes(const ATypes: TTyStringArray): TTyStringArray;

{ ---- the model ---- }
function TyVisualMapCount(AOption: TTyChartOption): Integer;
{ ARamp is the fallback gradient; a root `gradientColor` wins over it. }
function TyVisualMapSpecOf(AOption: TTyChartOption; AIndex: Integer;
  const ARamp: TTyVisualColorArray): TTyVisualMapSpec;
function TyVisualMapTargets(const ASpec: TTyVisualMapSpec;
  ASeriesIndex: Integer; const ASeriesId: string): Boolean;
function TyVisualMapDimFor(const ASpec: TTyVisualMapSpec;
  ASeriesIndex: Integer; const ASeriesId: string): TTyVisualDim;
function TyVisualValueState(const ASpec: TTyVisualMapSpec;
  AValue: Double): TTyVisualState;
{ Apply AState's mappings to ARow for AValue. AForMeta: the visualMeta's
  colour, where an opacity becomes the colour's alpha. }
procedure TyVisualApply(const ASpec: TTyVisualMapSpec; AState: TTyVisualState;
  AValue: Double; var ARow: TTyVisualRow; AForMeta: Boolean);

{ ---- one series ---- }
{ The value each raw row is mapped by. AStoreCol is the store column read,
  or -1 when the dimension is not in the store and the raw cell is parsed;
  ADimIndex is upstream's dimension index, -1 when it resolves to none. }
function TyVisualSeriesValues(AStore: TTyDataStore; const ADim: TTyVisualDim;
  out AStoreCol, ADimIndex: Integer): TTyDoubleArray;

{ ---- the continuous visualMeta ---- }
function TyVmStopValues(AE0, AE1: Double): TTyDoubleArray;
function TyVisualMetaOf(const ASpec: TTyVisualMapSpec;
  const ASeriesColor: TTyVisualColor): TTyVisualMeta;
{ LineView's getVisualGradient: AOrigin and ALength are the canvas along the
  axis, AScale device px per CSS px. }
function TyVisualLineFillOf(const AMeta: TTyVisualMeta; AAxis: TTyAxis;
  AOrigin, ALength, AScale: Double): TTyVisualLineFill;
function TyVisualLineGradient(const AFill: TTyVisualLineFill): TTyChartGradient;

implementation

uses tyControls.AdvChart.Color, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Complete;

{ JAVASCRIPT'S ORDERED COMPARISONS: false whenever either side is NaN. FPC's
  raise on a NaN instead, masked or not, so every comparison a NaN can reach
  goes through these. }
function Lt(A, B: Double): Boolean;
begin
  Result := not (IsNan(A) or IsNan(B)) and (A < B);
end;

function Le(A, B: Double): Boolean;
begin
  Result := not (IsNan(A) or IsNan(B)) and (A <= B);
end;

function Gt(A, B: Double): Boolean;
begin
  Result := Lt(B, A);
end;

function Ge(A, B: Double): Boolean;
begin
  Result := Le(B, A);
end;

{ ==================== colours ==================== }

function TyVisualUndefined: TTyVisualColor;
begin
  Result.R := 0;
  Result.G := 0;
  Result.B := 0;
  Result.A := 0;
  Result.Defined := False;
end;

function TyVisualRgba(AR, AG, AB, AA: Double): TTyVisualColor;
begin
  Result.R := AR;
  Result.G := AG;
  Result.B := AB;
  Result.A := AA;
  Result.Defined := True;
end;

function TyVisualTryParse(const AText: string; out AColor: TTyVisualColor): Boolean;
var r, g, b, a: Double;
begin
  AColor := TyVisualUndefined;
  Result := TyTryParseCssRgba(AText, r, g, b, a);
  if Result then AColor := TyVisualRgba(r, g, b, a);
end;

function TyVisualParsedStop(AData: TJSONData): TTyVisualColor;
begin
  { setVisualToOption: `parse(item) || [0, 0, 0, 1]`. A number is
    stringified first and is no colour either. }
  if (AData <> nil) and (AData.JSONType = jtString)
    and TyVisualTryParse(AData.AsString, Result) then Exit;
  Result := TyVisualRgba(0, 0, 0, 1);
end;

function TyVisualFromChart(AColor: TTyChartColor): TTyVisualColor;
begin
  Result := TyVisualRgba((AColor shr 16) and $FF, (AColor shr 8) and $FF,
    AColor and $FF, ((AColor shr 24) and $FF) / 255);
end;

function Byte255(AValue: Double): Cardinal;
begin
  if IsNan(AValue) then Exit(0);
  AValue := TyJsRound(AValue);
  if AValue < 0 then AValue := 0;
  if AValue > 255 then AValue := 255;
  Result := Cardinal(Trunc(AValue));
end;

function TyVisualToChart(const AColor: TTyVisualColor): TTyChartColor;
begin
  if not AColor.Defined then Exit(0);
  Result := TTyChartColor((Byte255(AColor.A * 255) shl 24)
    or (Byte255(AColor.R) shl 16) or (Byte255(AColor.G) shl 8)
    or Byte255(AColor.B));
end;

function TyVisualCss(const AColor: TTyVisualColor): string;
begin
  if not AColor.Defined then Exit('');
  Result := 'rgba(' + TyJsNumberToString(AColor.R) + ','
    + TyJsNumberToString(AColor.G) + ',' + TyJsNumberToString(AColor.B) + ','
    + TyJsNumberToString(AColor.A) + ')';
end;

{ clampCssByte: Math.round, then 0..255. NaN stays NaN, as it does upstream. }
function CssByte(AValue: Double): Double;
begin
  if IsNan(AValue) then Exit(AValue);
  Result := TyJsRound(AValue);
  if Result < 0 then Result := 0
  else if Result > 255 then Result := 255;
end;

function CssFloat01(AValue: Double): Double;
begin
  if Lt(AValue, 0) then Result := 0
  else if Gt(AValue, 1) then Result := 1
  else Result := AValue;
end;

function CssAngle(AValue: Double): Double;
begin
  if IsNan(AValue) then Exit(AValue);
  Result := TyJsRound(AValue);
  if Result < 0 then Result := 0
  else if Result > 360 then Result := 360;
end;

function LerpNumber(A, B, P: Double): Double;
begin
  Result := A + (B - A) * P;
end;

function TyVisualFastLerp(AN: Double;
  const AStops: TTyVisualColorArray): TTyVisualColor;
var
  v, dv: Double;
  li, ri: Integer;
  lc, rc: TTyVisualColor;
begin
  Result := TyVisualUndefined;
  { `!(n >= 0 && n <= 1)`: NaN and anything outside is undefined }
  if Length(AStops) = 0 then Exit;
  if not (Ge(AN, 0) and Le(AN, 1)) then Exit;
  v := AN * (Length(AStops) - 1);
  li := Floor(v);
  ri := Ceil(v);
  lc := AStops[li];
  rc := AStops[ri];
  dv := v - li;
  Result := TyVisualRgba(
    CssByte(LerpNumber(lc.R, rc.R, dv)),
    CssByte(LerpNumber(lc.G, rc.G, dv)),
    CssByte(LerpNumber(lc.B, rc.B, dv)),
    CssFloat01(LerpNumber(lc.A, rc.A, dv)));
end;

function HueToRgb(m1, m2, h: Double): Double;
begin
  if Lt(h, 0) then h := h + 1 else if Gt(h, 1) then h := h - 1;
  if Lt(h * 6, 1) then Exit(m1 + (m2 - m1) * h * 6);
  if Lt(h * 2, 1) then Exit(m2);
  if Lt(h * 3, 2) then Exit(m1 + (m2 - m1) * (2 / 3 - h) * 6);
  Result := m1;
end;

{ JavaScript's %: the sign of the dividend, exact. }
function JsMod(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) or IsInfinite(A) or (B = 0) then Exit(NaN);
  if IsInfinite(B) then Exit(A);
  Result := A - B * Int(A / B);
  { Int(A/B) can be off by one where A/B rounded across an integer }
  if (Result <> 0) and ((Result < 0) <> (A < 0)) then
  begin
    if A < 0 then Result := Result - Abs(B) else Result := Result + Abs(B);
  end
  else if Abs(Result) >= Abs(B) then
  begin
    if A < 0 then Result := Result + Abs(B) else Result := Result - Abs(B);
  end;
end;

function TyVisualModifyHSL(const AColor: TTyVisualColor; AH, AS_, AL: Double;
  AHasH, AHasS, AHasL: Boolean): TTyVisualColor;
var
  r, g, b, vmin, vmax, delta, l, h, s, dr, dg, db, m1, m2: Double;
begin
  if not AColor.Defined then Exit(TyVisualUndefined);
  { rgba2hsla }
  r := AColor.R / 255;
  g := AColor.G / 255;
  b := AColor.B / 255;
  vmin := Min(r, Min(g, b));
  vmax := Max(r, Max(g, b));
  delta := vmax - vmin;
  l := (vmax + vmin) / 2;
  h := 0;
  s := 0;
  if delta <> 0 then
  begin
    if l < 0.5 then s := delta / (vmax + vmin)
    else s := delta / (2 - vmax - vmin);
    dr := (((vmax - r) / 6) + (delta / 2)) / delta;
    dg := (((vmax - g) / 6) + (delta / 2)) / delta;
    db := (((vmax - b) / 6) + (delta / 2)) / delta;
    if r = vmax then h := db - dg
    else if g = vmax then h := (1 / 3) + dr - db
    else if b = vmax then h := (2 / 3) + dg - dr;
    if h < 0 then h := h + 1;
    if h > 1 then h := h - 1;
  end;
  h := h * 360;
  if AHasH then h := CssAngle(AH);
  if AHasS then s := CssFloat01(AS_);
  if AHasL then l := CssFloat01(AL);
  { hsla2rgba }
  h := JsMod(JsMod(h, 360) + 360, 360) / 360;
  s := CssFloat01(s);
  l := CssFloat01(l);
  if Le(l, 0.5) then m2 := l * (s + 1) else m2 := l + s - l * s;
  m1 := l * 2 - m2;
  Result := TyVisualRgba(CssByte(HueToRgb(m1, m2, h + 1 / 3) * 255),
    CssByte(HueToRgb(m1, m2, h) * 255),
    CssByte(HueToRgb(m1, m2, h - 1 / 3) * 255), AColor.A);
end;

function TyVisualModifyAlpha(const AColor: TTyVisualColor;
  AAlpha: Double): TTyVisualColor;
begin
  if not AColor.Defined then Exit(TyVisualUndefined);
  Result := AColor;
  Result.A := CssFloat01(AAlpha);
end;

function TyVisualDefaultRamp(AAccent: TTyChartColor): TTyVisualColorArray;
var c: TTyVisualColor;
begin
  c := TyVisualFromChart(AAccent);
  SetLength(Result, 2);
  Result[0] := TyVisualModifyHSL(c, 0, 0, 0.9, False, False, True);
  Result[1] := c;
end;

{ ==================== arithmetic ==================== }

function TyVmLinearMap(AValue, AD0, AD1, AR0, AR1: Double;
  AClamp: Boolean): Double;
var subDomain, subRange: Double;
begin
  subDomain := AD1 - AD0;
  subRange := AR1 - AR0;
  if (not IsNan(subDomain)) and (subDomain = 0) then
  begin
    if (not IsNan(subRange)) and (subRange = 0) then Exit(AR0);
    Exit((AR0 + AR1) / 2);
  end;
  if AClamp then
  begin
    if Gt(subDomain, 0) then
    begin
      if Le(AValue, AD0) then Exit(AR0)
      else if Ge(AValue, AD1) then Exit(AR1);
    end
    else
    begin
      if Ge(AValue, AD0) then Exit(AR0)
      else if Le(AValue, AD1) then Exit(AR1);
    end;
  end
  else
  begin
    if Le(AValue, AD0) and Ge(AValue, AD0) then Exit(AR0);
    if Le(AValue, AD1) and Ge(AValue, AD1) then Exit(AR1);
  end;
  Result := (AValue - AD0) / subDomain * subRange + AR0;
end;

const
  cValidTypes: array[0..9] of string = ('color', 'colorHue',
    'colorSaturation', 'colorLightness', 'colorAlpha', 'decal', 'opacity',
    'liftZ', 'symbol', 'symbolSize');

function TyVisualIsValidType(const AType: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(cValidTypes) do
    if cValidTypes[i] = AType then Exit(True);
  Result := False;
end;

{ The comparator: `(t2 === 'color' && t1 !== 'color' && t1 starts 'color')
  ? 1 : -1`. Never 0, and not antisymmetric. }
function VisualCmp(const T1, T2: string): Integer;
begin
  if (T2 = 'color') and (T1 <> 'color') and (Copy(T1, 1, 5) = 'color') then
    Result := 1
  else
    Result := -1;
end;

function TyPrepareVisualTypes(const ATypes: TTyStringArray): TTyStringArray;
var
  n, runEnd, lo, hi, left, right, mid, i: Integer;
  pivot, t: string;
  descending: Boolean;
begin
  n := Length(ATypes);
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := ATypes[i];
  if n < 2 then Exit;
  { CountAndMakeRun over the whole array: V8's TimSort with n < 64 is one run
    from the start, extended by binary insertion. A run is descending when
    the second element sorts strictly before the first. }
  runEnd := 2;
  descending := VisualCmp(Result[1], Result[0]) < 0;
  if descending then
  begin
    while (runEnd < n) and (VisualCmp(Result[runEnd], Result[runEnd - 1]) < 0) do
      Inc(runEnd);
    { reversed in place }
    lo := 0;
    hi := runEnd - 1;
    while lo < hi do
    begin
      t := Result[lo];
      Result[lo] := Result[hi];
      Result[hi] := t;
      Inc(lo);
      Dec(hi);
    end;
  end
  else
    while (runEnd < n) and (VisualCmp(Result[runEnd], Result[runEnd - 1]) >= 0) do
      Inc(runEnd);
  { BinaryInsertionSort from the end of the run }
  for i := runEnd to n - 1 do
  begin
    pivot := Result[i];
    left := 0;
    right := i;
    while left < right do
    begin
      mid := left + ((right - left) shr 1);
      if VisualCmp(pivot, Result[mid]) < 0 then
        right := mid
      else
        left := mid + 1;
    end;
    for mid := i downto left + 1 do Result[mid] := Result[mid - 1];
    Result[left] := pivot;
  end;
end;

{ ==================== the model ==================== }

{ JavaScript truthiness of an option value. }
function Truthy(A: TJSONData): Boolean;
begin
  if A = nil then Exit(False);
  case A.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

function ObjOf(A: TJSONData): TJSONObject;
begin
  if (A <> nil) and (A.JSONType = jtObject) then Result := TJSONObject(A)
  else Result := nil;
end;

function NumOf(A: TJSONData): Double;
begin
  Result := NaN;
  if A = nil then Exit;
  case A.JSONType of
    jtNumber: Result := A.AsFloat;
    jtString: Result := TyJsToNumber(A.AsString);
    jtBoolean: if A.AsBoolean then Result := 1 else Result := 0;
    jtNull: Result := 0;
  end;
end;

function TyVisualMapCount(AOption: TTyChartOption): Integer;
begin
  if AOption = nil then Exit(0);
  Result := AOption.ComponentCount('visualMap');
end;

function DimOf(A: TJSONData): TTyVisualDim;
begin
  Result := Default(TTyVisualDim);
  Result.Num := NaN;
  if (A = nil) or (A.JSONType = jtNull) then Exit;
  Result.Given := True;
  if A.JSONType = jtNumber then
    Result.Num := A.AsFloat
  else if A.JSONType = jtString then
  begin
    Result.IsName := True;
    Result.Name := A.AsString;
  end
  else
    Result.Given := False;
end;

{ zrUtil.merge(target, source) without overwriting: a key the target lacks
  is appended, a plain object on both sides is merged into, anything else
  the target already has stays. }
procedure MergeKeep(ATarget, ASource: TJSONObject);
var
  i, k: Integer;
  key: string;
  s, t: TJSONData;
begin
  for i := 0 to ASource.Count - 1 do
  begin
    key := ASource.Names[i];
    s := ASource.Items[i];
    k := ATarget.IndexOfName(key);
    if k < 0 then
    begin
      ATarget.Add(key, s.Clone);
      Continue;
    end;
    t := ATarget.Items[k];
    if (s.JSONType = jtObject) and (t.JSONType = jtObject) then
      MergeKeep(TJSONObject(t), TJSONObject(s));
  end;
end;

{ `inactive` in visualDefault; nil where there is none. }
function InactiveDefault(const AType: string): TJSONData;
begin
  if AType = 'color' then Exit(TJSONArray.Create(['rgba(0,0,0,0)']));
  if (AType = 'colorHue') or (AType = 'colorSaturation')
    or (AType = 'colorLightness') or (AType = 'colorAlpha')
    or (AType = 'opacity') or (AType = 'symbolSize') then
    Exit(TJSONArray.Create([0, 0]));
  if AType = 'symbol' then Exit(TJSONArray.Create(['none']));
  Result := nil;
end;

procedure SetKey(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
var k: Integer;
begin
  k := AObj.IndexOfName(AKey);
  if k >= 0 then AObj.Items[k] := AValue
  else AObj.Add(AKey, AValue);
end;

{ normalizeVisualRange: an object's values in order, or the one value that
  is not null. }
function VisualList(AVisual: TJSONData): TJSONArray;
var i: Integer;
begin
  Result := TJSONArray.Create;
  if AVisual = nil then Exit;
  case AVisual.JSONType of
    jtArray:
      for i := 0 to TJSONArray(AVisual).Count - 1 do
        Result.Add(TJSONArray(AVisual).Items[i].Clone);
    jtObject:
      for i := 0 to TJSONObject(AVisual).Count - 1 do
        Result.Add(TJSONObject(AVisual).Items[i].Clone);
    jtNull: ;
  else
    Result.Add(AVisual.Clone);
  end;
end;

function MappingOf(const AType: string; AVisual: TJSONData): TTyVisualMapping;
var
  list: TJSONArray;
  i: Integer;
begin
  Result := Default(TTyVisualMapping);
  Result.Kind := AType;
  list := VisualList(AVisual);
  try
    if AType = 'color' then
    begin
      { a single colour is NOT paired: one stop is that colour everywhere }
      SetLength(Result.Colors, list.Count);
      for i := 0 to list.Count - 1 do
        Result.Colors[i] := TyVisualParsedStop(list.Items[i]);
      Exit;
    end;
    if (list.Count = 1) and (AType <> 'symbol') then list.Add(list.Items[0].Clone);
    SetLength(Result.Nums, list.Count);
    for i := 0 to list.Count - 1 do
      if list.Items[i].JSONType = jtNumber then
        Result.Nums[i] := list.Items[i].AsFloat
      else
        Result.Nums[i] := NaN;
  finally
    list.Free;
  end;
end;

procedure ReadStates(ATarget: TJSONObject; var ASpec: TTyVisualMapSpec);
const cNames: array[TTyVisualState] of string = ('inRange', 'outOfRange');
var
  st: TTyVisualState;
  obj: TJSONObject;
  i, n: Integer;
  valid, order: TTyStringArray;
begin
  for st := Low(TTyVisualState) to High(TTyVisualState) do
  begin
    ASpec.Keys[st] := nil;
    ASpec.States[st] := nil;
    obj := ObjOf(ATarget.Find(cNames[st]));
    if obj = nil then Continue;
    SetLength(ASpec.Keys[st], obj.Count);
    valid := nil;
    for i := 0 to obj.Count - 1 do
    begin
      ASpec.Keys[st][i] := obj.Names[i];
      if TyVisualIsValidType(obj.Names[i]) then
      begin
        n := Length(valid);
        SetLength(valid, n + 1);
        valid[n] := obj.Names[i];
      end;
    end;
    order := TyPrepareVisualTypes(valid);
    SetLength(ASpec.States[st], Length(order));
    for i := 0 to High(order) do
      ASpec.States[st][i] := MappingOf(order[i], obj.Find(order[i]));
  end;
end;

procedure ReadTargets(ANode: TJSONObject; var ASpec: TTyVisualMapSpec);
var
  d, e: TJSONData;
  arr: TJSONArray;
  i, n: Integer;
  t: TTyVisualSeriesTarget;
begin
  d := ANode.Find('seriesTargets');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    ASpec.HasSeriesTargets := True;
    arr := TJSONArray(d);
    for i := 0 to arr.Count - 1 do
    begin
      t := Default(TTyVisualSeriesTarget);
      t.SeriesIndex := -1;
      if arr.Items[i].JSONType = jtObject then
      begin
        e := TJSONObject(arr.Items[i]).Find('seriesIndex');
        if (e <> nil) and (e.JSONType = jtNumber) then
        begin
          t.HasIndex := True;
          t.SeriesIndex := Trunc(e.AsFloat);
        end;
        e := TJSONObject(arr.Items[i]).Find('seriesId');
        if (e <> nil) and (e.JSONType in [jtString, jtNumber]) then
        begin
          t.HasId := True;
          t.SeriesId := e.AsString;
        end;
        t.Dim := DimOf(TJSONObject(arr.Items[i]).Find('dimension'));
      end;
      n := Length(ASpec.SeriesTargets);
      SetLength(ASpec.SeriesTargets, n + 1);
      ASpec.SeriesTargets[n] := t;
    end;
    Exit;
  end;
  d := ANode.Find('seriesIndex');
  e := ANode.Find('seriesId');
  if ((d = nil) or (d.JSONType = jtNull)) and ((e = nil) or (e.JSONType = jtNull)) then
  begin
    ASpec.AllSeries := True;
    Exit;
  end;
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if (d.JSONType = jtString) and (d.AsString = 'all') then
    begin
      ASpec.AllSeries := True;
      Exit;
    end;
    if d.JSONType = jtNumber then
    begin
      SetLength(ASpec.SeriesIndices, 1);
      ASpec.SeriesIndices[0] := Trunc(d.AsFloat);
    end
    else if d.JSONType = jtArray then
      for i := 0 to TJSONArray(d).Count - 1 do
        if TJSONArray(d).Items[i].JSONType = jtNumber then
        begin
          n := Length(ASpec.SeriesIndices);
          SetLength(ASpec.SeriesIndices, n + 1);
          ASpec.SeriesIndices[n] := Trunc(TJSONArray(d).Items[i].AsFloat);
        end;
    Exit;
  end;
  if e.JSONType in [jtString, jtNumber] then
  begin
    SetLength(ASpec.SeriesIds, 1);
    ASpec.SeriesIds[0] := e.AsString;
  end
  else if e.JSONType = jtArray then
    for i := 0 to TJSONArray(e).Count - 1 do
      if TJSONArray(e).Items[i].JSONType in [jtString, jtNumber] then
      begin
        n := Length(ASpec.SeriesIds);
        SetLength(ASpec.SeriesIds, n + 1);
        ASpec.SeriesIds[n] := TJSONArray(e).Items[i].AsString;
      end;
end;

function TyVisualMapSpecOf(AOption: TTyChartOption; AIndex: Integer;
  const ARamp: TTyVisualColorArray): TTyVisualMapSpec;
var
  node, target, base, st, absent: TJSONObject;
  d, root, ramp, inRange: TJSONData;
  arr: TJSONArray;
  i: Integer;
  e0, e1, r0, r1, t: Double;
  defa: TJSONData;
begin
  Result := Default(TTyVisualMapSpec);
  Result.Index := AIndex;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('visualMap', AIndex));
  if node = nil then Exit;
  Result.SubType := TyOptDefaultSubType('visualMap', node);
  d := node.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    if (d.AsString = 'continuous') or (d.AsString = 'piecewise') then
      Result.SubType := d.AsString
    else
      Result.SubType := '';
  end;
  if Result.SubType = '' then Exit;
  d := node.Find('show');
  Result.Show := not ((d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean);

  { resetExtent: asc([min, max]), 0 and 200 by default }
  e0 := 0;
  e1 := 200;
  d := node.Find('min');
  if (d <> nil) and (d.JSONType <> jtNull) then e0 := NumOf(d);
  d := node.Find('max');
  if (d <> nil) and (d.JSONType <> jtNull) then e1 := NumOf(d);
  if Gt(e0, e1) then
  begin
    t := e0;
    e0 := e1;
    e1 := t;
  end;
  Result.Extent0 := e0;
  Result.Extent1 := e1;

  { _resetRange: absent is the extent; otherwise ascending and clamped into
    it }
  d := node.Find('range');
  if (d <> nil) and (d.JSONType = jtArray) and (TJSONArray(d).Count >= 2) then
  begin
    r0 := NumOf(TJSONArray(d).Items[0]);
    r1 := NumOf(TJSONArray(d).Items[1]);
    if Gt(r0, r1) then
    begin
      t := r0;
      r0 := r1;
      r1 := t;
    end;
    { Math.max / Math.min: NaN wins }
    if IsNan(r0) or IsNan(e0) then r0 := NaN else r0 := Max(r0, e0);
    if IsNan(r1) or IsNan(e1) then r1 := NaN else r1 := Min(r1, e1);
    Result.Range0 := r0;
    Result.Range1 := r1;
  end
  else
  begin
    Result.RangeAuto := True;
    Result.Range0 := e0;
    Result.Range1 := e1;
  end;
  { retrieve2(unboundedRange, true), read for its truth }
  d := node.Find('unboundedRange');
  if (d = nil) or (d.JSONType = jtNull) then Result.Unbounded := True
  else Result.Unbounded := Truthy(d);

  ReadTargets(node, Result);
  Result.Dim := DimOf(node.Find('dimension'));

  { completeVisualOption, on a copy: target merged with the option's own
    states, per key and without overwriting }
  d := node.Find('target');
  if (d <> nil) and (d.JSONType = jtObject) then
    target := TJSONObject(d.Clone)
  else
    target := TJSONObject.Create;
  base := TJSONObject.Create;
  try
    d := node.Find('inRange');
    if (d <> nil) then base.Add('inRange', d.Clone);
    d := node.Find('outOfRange');
    if (d <> nil) then base.Add('outOfRange', d.Clone);
    MergeKeep(target, base);

    { completeSingle: ec2's high-to-low `color`, then the gradient }
    inRange := target.Find('inRange');
    d := node.Find('color');
    if (d <> nil) and (d.JSONType = jtArray) and not Truthy(inRange) then
    begin
      arr := TJSONArray.Create;
      for i := TJSONArray(d).Count - 1 downto 0 do
        arr.Add(TJSONArray(d).Items[i].Clone);
      st := TJSONObject.Create;
      st.Add('color', arr);
      SetKey(target, 'inRange', st);
      inRange := st;
    end;
    if not Truthy(inRange) then
    begin
      root := AOption.Find('gradientColor');
      if root <> nil then
        ramp := root.Clone
      else
      begin
        arr := TJSONArray.Create;
        for i := 0 to High(ARamp) do arr.Add(TyVisualCss(ARamp[i]));
        ramp := arr;
      end;
      st := TJSONObject.Create;
      st.Add('color', ramp);
      SetKey(target, 'inRange', st);
    end;

    { completeInactive: an absent outOfRange gets every inRange type's
      inactive value, and a colour an opacity of nought beside it }
    st := ObjOf(target.Find('inRange'));
    if (st <> nil) and not Truthy(target.Find('outOfRange')) then
    begin
      absent := TJSONObject.Create;
      SetKey(target, 'outOfRange', absent);
      for i := 0 to st.Count - 1 do
      begin
        if not TyVisualIsValidType(st.Names[i]) then Continue;
        defa := InactiveDefault(st.Names[i]);
        if defa = nil then Continue;
        SetKey(absent, st.Names[i], defa);
        if (st.Names[i] = 'color') and (absent.IndexOfName('opacity') < 0)
          and (absent.IndexOfName('colorAlpha') < 0) then
          absent.Add('opacity', TJSONArray.Create([0, 0]));
      end;
    end;
    ReadStates(target, Result);
  finally
    base.Free;
    target.Free;
  end;
end;

function TyVisualMapTargets(const ASpec: TTyVisualMapSpec;
  ASeriesIndex: Integer; const ASeriesId: string): Boolean;
var i: Integer;
begin
  Result := False;
  if ASpec.SubType = '' then Exit;
  if ASpec.HasSeriesTargets then
  begin
    for i := 0 to High(ASpec.SeriesTargets) do
      if ASpec.SeriesTargets[i].HasIndex then
      begin
        if ASpec.SeriesTargets[i].SeriesIndex = ASeriesIndex then Exit(True);
      end
      else if ASpec.SeriesTargets[i].HasId and (ASeriesId <> '')
        and (ASpec.SeriesTargets[i].SeriesId = ASeriesId) then Exit(True);
    Exit;
  end;
  if ASpec.AllSeries then Exit(True);
  for i := 0 to High(ASpec.SeriesIndices) do
    if ASpec.SeriesIndices[i] = ASeriesIndex then Exit(True);
  if Length(ASpec.SeriesIndices) > 0 then Exit;
  for i := 0 to High(ASpec.SeriesIds) do
    if (ASeriesId <> '') and (ASpec.SeriesIds[i] = ASeriesId) then Exit(True);
end;

function TyVisualMapDimFor(const ASpec: TTyVisualMapSpec;
  ASeriesIndex: Integer; const ASeriesId: string): TTyVisualDim;
var i: Integer;
begin
  { getDimension: the first seriesTargets entry naming this series, else the
    component's own }
  if ASpec.HasSeriesTargets then
    for i := 0 to High(ASpec.SeriesTargets) do
      if (ASpec.SeriesTargets[i].HasIndex
          and (ASpec.SeriesTargets[i].SeriesIndex = ASeriesIndex))
        or (ASpec.SeriesTargets[i].HasId and (ASeriesId <> '')
          and (ASpec.SeriesTargets[i].SeriesId = ASeriesId)) then
        Exit(ASpec.SeriesTargets[i].Dim);
  Result := ASpec.Dim;
end;

function TyVisualValueState(const ASpec: TTyVisualMapSpec;
  AValue: Double): TTyVisualState;
var ub: Boolean;
begin
  ub := ASpec.Unbounded;
  if ((ub and Le(ASpec.Range0, ASpec.Extent0)) or Le(ASpec.Range0, AValue))
    and ((ub and Ge(ASpec.Range1, ASpec.Extent1)) or Le(AValue, ASpec.Range1)) then
    Result := tvsInRange
  else
    Result := tvsOutOfRange;
end;

function PairAt(const ANums: TTyDoubleArray; AIndex: Integer): Double;
begin
  if AIndex <= High(ANums) then Result := ANums[AIndex] else Result := NaN;
end;

procedure TyVisualApply(const ASpec: TTyVisualMapSpec; AState: TTyVisualState;
  AValue: Double; var ARow: TTyVisualRow; AForMeta: Boolean);
var
  i: Integer;
  n, v: Double;
  m: TTyVisualMapping;
begin
  { the linear normaliser, clamped, over the EXTENT -- not the range }
  n := TyVmLinearMap(AValue, ASpec.Extent0, ASpec.Extent1, 0, 1, True);
  for i := 0 to High(ASpec.States[AState]) do
  begin
    m := ASpec.States[AState][i];
    if m.Kind = 'color' then
    begin
      ARow.Color := TyVisualFastLerp(n, m.Colors);
      ARow.ColorSet := True;
      Continue;
    end;
    if (m.Kind = 'opacity') or (m.Kind = 'colorAlpha') or (m.Kind = 'colorHue')
      or (m.Kind = 'colorSaturation') or (m.Kind = 'colorLightness') then
    begin
      v := TyVmLinearMap(n, 0, 1, PairAt(m.Nums, 0), PairAt(m.Nums, 1), True);
      { the visualMeta draws with a gradient, which has no opacity: the
        opacity becomes the colour's alpha (`__alphaForOpacity`) }
      if (m.Kind = 'opacity') and not AForMeta then
      begin
        ARow.Opacity := v;
        ARow.OpacitySet := True;
      end
      else
      begin
        if (m.Kind = 'colorAlpha') or (m.Kind = 'opacity') then
          ARow.Color := TyVisualModifyAlpha(ARow.Color, v)
        else if m.Kind = 'colorHue' then
          ARow.Color := TyVisualModifyHSL(ARow.Color, v, 0, 0, True, False, False)
        else if m.Kind = 'colorSaturation' then
          ARow.Color := TyVisualModifyHSL(ARow.Color, 0, v, 0, False, True, False)
        else
          ARow.Color := TyVisualModifyHSL(ARow.Color, 0, 0, v, False, False, True);
        ARow.ColorSet := True;
      end;
    end;
    { symbol, symbolSize, liftZ and decal are later batches }
  end;
end;

{ ==================== one series ==================== }

function TyVisualSeriesValues(AStore: TTyDataStore; const ADim: TTyVisualDim;
  out AStoreCol, ADimIndex: Integer): TTyDoubleArray;
var
  d, k, raw: Integer;
  pos: Double;
  cell: TTyDataValue;
  typ: TTyDimType;
begin
  Result := nil;
  AStoreCol := -1;
  ADimIndex := -1;
  if AStore = nil then Exit;
  if ADim.Given then
  begin
    if ADim.IsName then pos := AStore.RawPosOf(ADim.Name)
    else pos := ADim.Num;
    if IsNan(pos) or (pos < 0) or (Frac(pos) <> 0) then d := -1
    else d := Trunc(pos);
  end
  else
    { THE LAST DIMENSION that is not a calculation: the coordinates, or the
      row's own width when it is wider -- a scatter's third number, a
      table's last column. Asked before any stack column is added. }
    d := Max(AStore.DimCount, AStore.RawWidth) - 1;
  ADimIndex := d;
  SetLength(Result, AStore.RawCount);
  if d < 0 then
  begin
    for raw := 0 to High(Result) do Result[raw] := NaN;
    Exit;
  end;
  { A STORE COLUMN READ FROM THAT POSITION holds it as the axis does -- a
    category's ordinal, the value before any stack; any other position is
    parsed from the item as written }
  for k := 0 to AStore.DimCount - 1 do
    if AStore.RawDimPos(k) = d then
    begin
      AStoreCol := k;
      Break;
    end;
  if AStoreCol >= 0 then
  begin
    for raw := 0 to High(Result) do
      Result[raw] := AStore.GetByRaw(AStoreCol, raw);
    Exit;
  end;
  if AStore.RawPosType(d) = ddtTime then typ := ddtTime else typ := ddtFloat;
  for raw := 0 to High(Result) do
    if TTyDataStore.RawCell(AStore.RawItemByRaw(raw), d, cell) then
      Result[raw] := TyParseDataValue(cell, typ)
    else
      Result[raw] := NaN;
end;

{ ==================== the continuous visualMeta ==================== }

function TyVmStopValues(AE0, AE1: Double): TTyDoubleArray;
var
  i, n: Integer;
  step, v: Double;
begin
  if Le(AE0, AE1) and Ge(AE0, AE1) then
  begin
    SetLength(Result, 2);
    Result[0] := AE0;
    Result[1] := AE1;
    Exit;
  end;
  { ACCUMULATED, not multiplied: the 201st value is not e0 + step * 200 }
  step := (AE1 - AE0) / 200;
  v := AE0;
  Result := nil;
  i := 0;
  while (i <= 200) and Lt(v, AE1) do
  begin
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := v;
    v := v + step;
    Inc(i);
  end;
  n := Length(Result);
  SetLength(Result, n + 1);
  Result[n] := AE1;
end;

function TyVisualMetaOf(const ASpec: TTyVisualMapSpec;
  const ASeriesColor: TTyVisualColor): TTyVisualMeta;
var
  oVals, iVals: TTyDoubleArray;
  oIdx, iIdx, oLen, iLen: Integer;
  first: Boolean;

  procedure SetStop(AValue: Double; AState: TTyVisualState);
  var
    row: TTyVisualRow;
    n: Integer;
  begin
    row := Default(TTyVisualRow);
    row.Color := ASeriesColor;
    TyVisualApply(ASpec, AState, AValue, row, True);
    n := Length(Result.Stops);
    SetLength(Result.Stops, n + 1);
    Result.Stops[n].Value := AValue;
    Result.Stops[n].Color := row.Color;
  end;

begin
  Result := Default(TTyVisualMeta);
  Result.VisualMap := ASpec.Index;
  Result.Dimension := -1;
  oVals := TyVmStopValues(ASpec.Extent0, ASpec.Extent1);
  iVals := TyVmStopValues(ASpec.Range0, ASpec.Range1);
  oLen := Length(oVals);
  iLen := Length(iVals);
  iIdx := 0;
  oIdx := 0;
  while (oIdx < oLen) and ((iLen = 0) or Le(oVals[oIdx], iVals[0])) do
  begin
    if (iIdx < iLen) and Lt(oVals[oIdx], iVals[iIdx]) then
      SetStop(oVals[oIdx], tvsOutOfRange);
    Inc(oIdx);
  end;
  first := True;
  while iIdx < iLen do
  begin
    if first and (Length(Result.Stops) > 0) then
      SetStop(iVals[iIdx], tvsOutOfRange);
    SetStop(iVals[iIdx], tvsInRange);
    Inc(iIdx);
    first := False;
  end;
  first := True;
  while oIdx < oLen do
  begin
    if (iLen = 0) or Lt(iVals[iLen - 1], oVals[oIdx]) then
    begin
      if first then
      begin
        if Length(Result.Stops) > 0 then
          SetStop(Result.Stops[High(Result.Stops)].Value, tvsOutOfRange);
        first := False;
      end;
      SetStop(oVals[oIdx], tvsOutOfRange);
    end;
    Inc(oIdx);
  end;
  if Length(Result.Stops) > 0 then
  begin
    Result.Outer0 := Result.Stops[0].Color;
    Result.Outer1 := Result.Stops[High(Result.Stops)].Color;
  end
  else
  begin
    Result.Outer0 := TyVisualRgba(0, 0, 0, 0);
    Result.Outer1 := TyVisualRgba(0, 0, 0, 0);
  end;
end;

{ zrender's lerp between two stop colours -- parse, fastLerp, stringify. }
function LerpColor(AP: Double; const A, B: TTyVisualColor): TTyVisualColor;
var stops: TTyVisualColorArray;
begin
  SetLength(stops, 2);
  stops[0] := A;
  stops[1] := B;
  { an undefined stop has nothing to parse; upstream throws on it }
  if not A.Defined then stops[0] := TyVisualRgba(0, 0, 0, 1);
  if not B.Defined then stops[1] := TyVisualRgba(0, 0, 0, 1);
  Result := TyVisualFastLerp(AP, stops);
end;

function TyVisualLineFillOf(const AMeta: TTyVisualMeta; AAxis: TTyAxis;
  AOrigin, ALength, AScale: Double): TTyVisualLineFill;
var
  stops, kept: TTyVisualGradStopArray;
  o0, o1, transparent: TTyVisualColor;
  i, n, len: Integer;
  t: TTyVisualGradStop;
  tc: TTyVisualColor;
  havePrevOut, havePrevIn: Boolean;
  prevOut, prevIn: TTyVisualGradStop;
  tiny, lo, hi, span: Double;

  procedure Keep(const AStop: TTyVisualGradStop);
  var k: Integer;
  begin
    k := Length(kept);
    SetLength(kept, k + 1);
    kept[k] := AStop;
  end;

  function LerpStop(const S0, S1: TTyVisualGradStop;
    AClipped: Double): TTyVisualGradStop;
  begin
    Result := Default(TTyVisualGradStop);
    Result.Coord := AClipped;
    Result.Color := LerpColor((AClipped - S0.Coord) / (S1.Coord - S0.Coord),
      S0.Color, S1.Color);
  end;

begin
  Result := Default(TTyVisualLineFill);
  if AAxis = nil then Exit;
  len := Length(AMeta.Stops);
  if len = 0 then Exit;
  transparent := TyVisualRgba(0, 0, 0, 0);
  Result.Vertical := not AAxis.Horizontal;
  { on the canvas, measured from its own edge }
  SetLength(stops, len);
  for i := 0 to len - 1 do
  begin
    stops[i] := Default(TTyVisualGradStop);
    stops[i].Coord := AAxis.DataToCoord(AMeta.Stops[i].Value) - AOrigin;
    stops[i].Color := AMeta.Stops[i].Color;
  end;
  o0 := AMeta.Outer0;
  o1 := AMeta.Outer1;
  if Gt(stops[0].Coord, stops[len - 1].Coord) then
  begin
    for i := 0 to len div 2 - 1 do
    begin
      t := stops[i];
      stops[i] := stops[len - 1 - i];
      stops[len - 1 - i] := t;
    end;
    tc := o0;
    o0 := o1;
    o1 := tc;
  end;

  { clipColorStops, against the canvas rather than the plot }
  kept := nil;
  havePrevOut := False;
  havePrevIn := False;
  for i := 0 to len - 1 do
  begin
    if Lt(stops[i].Coord, 0) then
    begin
      prevOut := stops[i];
      havePrevOut := True;
    end
    else if Gt(stops[i].Coord, ALength) then
    begin
      if havePrevIn then
        Keep(LerpStop(prevIn, stops[i], ALength))
      else if havePrevOut then
      begin
        Keep(LerpStop(prevOut, stops[i], 0));
        Keep(LerpStop(prevOut, stops[i], ALength));
      end;
      Break;
    end
    else
    begin
      if havePrevOut then
      begin
        Keep(LerpStop(prevOut, stops[i], 0));
        havePrevOut := False;
      end;
      Keep(stops[i]);
      prevIn := stops[i];
      havePrevIn := True;
    end;
  end;

  n := Length(kept);
  if n = 0 then
  begin
    { every stop off the canvas: one colour }
    Result.Kind := vlfSolid;
    if Lt(stops[0].Coord, 0) then
    begin
      if o1.Defined then Result.Solid := o1 else Result.Solid := stops[len - 1].Color;
    end
    else if o0.Defined then Result.Solid := o0
    else Result.Solid := stops[0].Color;
    Exit;
  end;

  tiny := 10 * AScale;
  lo := kept[0].Coord - tiny;
  hi := kept[n - 1].Coord + tiny;
  span := hi - lo;
  if Lt(span, 1e-3 * AScale) then
  begin
    Result.Kind := vlfSolid;
    Result.Solid := transparent;
    Exit;
  end;
  for i := 0 to n - 1 do
    kept[i].Offset := (kept[i].Coord - lo) / span;
  { the outer colours, at the end offsets: a gradient paints its end stops
    beyond itself }
  SetLength(Result.Stops, n + 2);
  Result.Stops[0] := Default(TTyVisualGradStop);
  Result.Stops[0].Offset := kept[0].Offset;
  if o0.Defined then Result.Stops[0].Color := o0 else Result.Stops[0].Color := transparent;
  for i := 0 to n - 1 do Result.Stops[i + 1] := kept[i];
  Result.Stops[n + 1] := Default(TTyVisualGradStop);
  Result.Stops[n + 1].Offset := kept[n - 1].Offset;
  if o1.Defined then Result.Stops[n + 1].Color := o1 else Result.Stops[n + 1].Color := transparent;
  Result.Kind := vlfGradient;
  Result.Lo := lo + AOrigin;
  Result.Hi := hi + AOrigin;
end;

function TyVisualLineGradient(const AFill: TTyVisualLineFill): TTyChartGradient;
var i: Integer;
begin
  Result := Default(TTyChartGradient);
  if AFill.Kind <> vlfGradient then Exit;
  Result.Kind := cgkLinear;
  Result.Global := True;
  if AFill.Vertical then
  begin
    Result.Y := AFill.Lo;
    Result.Y2 := AFill.Hi;
  end
  else
  begin
    Result.X := AFill.Lo;
    Result.X2 := AFill.Hi;
  end;
  SetLength(Result.Stops, Length(AFill.Stops));
  for i := 0 to High(AFill.Stops) do
  begin
    Result.Stops[i].Offset := AFill.Stops[i].Offset;
    Result.Stops[i].Color := TyVisualToChart(AFill.Stops[i].Color);
  end;
end;

end.
