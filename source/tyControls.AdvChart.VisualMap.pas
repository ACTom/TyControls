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

  { how a mapping turns a value into a place in its visual list }
  TTyVisualMethod = (tvmLinear, tvmPiecewise, tvmCategory);

  { one written visual value: a number or a string, or nothing }
  TTyVisualPieceVisual = record
    Kind: string;
    Defined: Boolean;
    IsNum: Boolean;
    Num: Double;
    Str: string;
  end;
  TTyVisualPieceVisualArray = array of TTyVisualPieceVisual;

  { one piece of a piecewise visualMap, as the model holds it }
  TTyVisualPiece = record
    HasInterval: Boolean;
    Lo, Hi: Double;
    Close0, Close1: Integer;
    HasValue: Boolean;
    Value: Double;
    { a category, or a value written as a string }
    ValueIsStr: Boolean;
    ValueStr: string;
    Text: string;
    { the original index; -1 for a category }
    Index: Integer;
    { the `selected` map's key }
    Key: string;
    { the piece's own visuals (`color`, `symbol`, ...) }
    Visuals: TTyVisualPieceVisualArray;
  end;
  TTyVisualPieceArray = array of TTyVisualPiece;

  TTyPiecewiseMode = (tpmSplitNumber, tpmPieces, tpmCategories);

  { One visual type of one state: its parsed colour stops, or its numbers. }
  TTyVisualMapping = record
    Kind: string;
    Colors: TTyVisualColorArray;
    Nums: TTyDoubleArray;
    { `symbol`: the names, not paired }
    Strs: TTyStringArray;
    Method: TTyVisualMethod;
    { tvmCategory: the visual at each category's index (Defined False where
      none was written -- such a category maps to the default slot), and the
      default slot itself }
    Cats: TTyStringArray;
    CatVals: TTyVisualPieceVisualArray;
    CatDefault: TTyVisualPieceVisual;
    { tvmPiecewise in range: a piece's own visual wins }
    UsePieces: Boolean;
  end;
  TTyVisualMappingArray = array of TTyVisualMapping;
  TTyVisualStateKeys = array[TTyVisualState] of TTyStringArray;
  TTyVisualStateMaps = array[TTyVisualState] of TTyVisualMappingArray;

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
    Keys: TTyVisualStateKeys;
    States: TTyVisualStateMaps;
    { THE CONTROLLER'S, which is what the component draws its own bar in: the
      same option states merged under `controller`, a missing state the
      inactive colour, and a symbol and a size appended -- which matters,
      because the order the types are applied in is V8's sort of the WHOLE
      key list. }
    ControllerKeys: TTyVisualStateKeys;
    Controller: TTyVisualStateMaps;
    { PIECEWISE: the pieces in the model's order, which are selected, the
      categories as written, and the precision after splitNumber's write-back }
    Mode: TTyPiecewiseMode;
    Pieces: TTyVisualPieceArray;
    Selected: array of Boolean;
    Categories: TTyStringArray;
    Precision: Integer;
    Formatter: string;
    { `!!option.categories`: the defaults' shape, and no visualMeta }
    IsCategory: Boolean;
  end;
  TTyVisualMapSpecArray = array of TTyVisualMapSpec;

  { What the visual pipeline wrote on one datum. }
  TTyVisualRow = record
    ColorSet: Boolean;
    Color: TTyVisualColor;
    OpacitySet: Boolean;
    Opacity: Double;
    { the symbol's name and size (CSS px), and liftZ }
    SymbolSet: Boolean;
    Symbol: string;
    SizeSet: Boolean;
    Size: Double;
    LiftZSet: Boolean;
    LiftZ: Double;
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
{ ARamp is the fallback gradient; a root `gradientColor` wins over it.
  AInactive is the controller's colour for a state it was given nothing
  for -- `inactiveColor`, written or the theme's. The three-argument form
  uses upstream's own #cfd2d7. }
function TyVisualMapSpecOf(AOption: TTyChartOption; AIndex: Integer;
  const ARamp: TTyVisualColorArray): TTyVisualMapSpec; overload;
function TyVisualMapSpecOf(AOption: TTyChartOption; AIndex: Integer;
  const ARamp: TTyVisualColorArray;
  const AInactive: TTyVisualColor): TTyVisualMapSpec; overload;
function TyVisualMapTargets(const ASpec: TTyVisualMapSpec;
  ASeriesIndex: Integer; const ASeriesId: string): Boolean;
function TyVisualMapDimFor(const ASpec: TTyVisualMapSpec;
  ASeriesIndex: Integer; const ASeriesId: string): TTyVisualDim;
function TyVisualValueState(const ASpec: TTyVisualMapSpec;
  AValue: Double): TTyVisualState; overload;
{ AText: the value as JavaScript prints it, which is what a category is
  matched against }
function TyVisualValueState(const ASpec: TTyVisualMapSpec; AValue: Double;
  const AText: string): TTyVisualState; overload;
{ Apply AState's mappings to ARow for AValue. AForMeta: the visualMeta's
  colour, where an opacity becomes the colour's alpha. }
procedure TyVisualApply(const ASpec: TTyVisualMapSpec; AState: TTyVisualState;
  AValue: Double; var ARow: TTyVisualRow; AForMeta: Boolean); overload;
procedure TyVisualApply(const ASpec: TTyVisualMapSpec; AState: TTyVisualState;
  AValue: Double; const AText: string; var ARow: TTyVisualRow;
  AForMeta: Boolean); overload;
{ VisualMapping.findPieceIndex: -1 for none }
function TyVisualFindPiece(const APieces: TTyVisualPieceArray; AValue: Double;
  const AText: string; AClosest: Boolean): Integer;
{ PiecewiseModel.getRepresentValue for a non-category piece }
function TyVisualRepresent(const APiece: TTyVisualPiece): Double;

{ ---- one series ---- }
{ The value each raw row is mapped by. AStoreCol is the store column read,
  or -1 when the dimension is not in the store and the raw cell is parsed;
  ADimIndex is upstream's dimension index, -1 when it resolves to none. }
function TyVisualSeriesValues(AStore: TTyDataStore; const ADim: TTyVisualDim;
  out AStoreCol, ADimIndex: Integer): TTyDoubleArray; overload;
{ and each value as JavaScript's String() of it -- a category's own text
  where the item wrote one }
function TyVisualSeriesValues(AStore: TTyDataStore; const ADim: TTyVisualDim;
  out AStoreCol, ADimIndex: Integer; out ATexts: TTyStringArray): TTyDoubleArray; overload;

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
     tyControls.AdvChart.Complete, tyControls.AdvChart.Handlers;

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

{ JavaScript's `x + ''` of an option value }
function JsStrOf(A: TJSONData): string;
begin
  Result := '';
  if A = nil then Exit;
  case A.JSONType of
    jtNumber: Result := TyJsNumberToString(A.AsFloat);
    jtString: Result := A.AsString;
    jtBoolean: if A.AsBoolean then Result := 'true' else Result := 'false';
    jtNull: Result := 'null';
  end;
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

{ ==================== piecewise ==================== }

{ the visual types in VisualMapping.visualHandlers order: what
  retrieveVisuals and listVisualTypes walk }
const
  cHandlerOrder: array[0..9] of string = ('color', 'colorHue',
    'colorSaturation', 'colorLightness', 'colorAlpha', 'decal', 'opacity',
    'liftZ', 'symbol', 'symbolSize');

function PieceVisualOf(AData: TJSONData): TTyVisualPieceVisual;
begin
  Result := Default(TTyVisualPieceVisual);
  Result.Num := NaN;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber:
      begin
        Result.Defined := True;
        Result.IsNum := True;
        Result.Num := AData.AsFloat;
      end;
    jtString:
      begin
        Result.Defined := True;
        Result.Str := AData.AsString;
        Result.Num := TyJsToNumber(AData.AsString);
      end;
  end;
end;

{ `a <= b` when the end is closed, `a < b` when it is open }
function LittleThan(AClose: Integer; A, B: Double): Boolean;
begin
  if AClose <> 0 then Result := Le(A, B) else Result := Lt(A, B);
end;

function TyVisualFindPiece(const APieces: TTyVisualPieceArray; AValue: Double;
  const AText: string; AClosest: Boolean): Integer;
var
  i, possible: Integer;
  best: Double;

  procedure Update(AEnd: Double; AIndex: Integer);
  var d: Double;
  begin
    d := Abs(AEnd - AValue);
    if Lt(d, best) then
    begin
      best := d;
      possible := AIndex;
    end;
  end;

begin
  possible := -1;
  best := Infinity;
  { a value piece first: the number, or a string equal to the value's }
  for i := 0 to High(APieces) do
    if APieces[i].HasValue then
    begin
      if APieces[i].ValueIsStr then
      begin
        if APieces[i].ValueStr = AText then Exit(i);
      end
      else if Le(APieces[i].Value, AValue) and Ge(APieces[i].Value, AValue) then
        Exit(i);
      { Math.abs(pieceValue - value): a string piece value coerced }
      if AClosest then
        Update(APieces[i].Value, i);
    end;
  for i := 0 to High(APieces) do
  begin
    if not APieces[i].HasInterval then Continue;
    with APieces[i] do
    begin
      if IsInfinite(Lo) and (Lo < 0) then
      begin
        if LittleThan(Close1, AValue, Hi) then Exit(i);
      end
      else if IsInfinite(Hi) and (Hi > 0) then
      begin
        if LittleThan(Close0, Lo, AValue) then Exit(i);
      end
      else if LittleThan(Close0, Lo, AValue) and LittleThan(Close1, AValue, Hi) then
        Exit(i);
    end;
    if AClosest then
    begin
      Update(APieces[i].Lo, i);
      Update(APieces[i].Hi, i);
    end;
  end;
  if not AClosest then Exit(-1);
  if IsInfinite(AValue) and (AValue > 0) then Exit(High(APieces));
  if IsInfinite(AValue) and (AValue < 0) then
  begin
    if Length(APieces) > 0 then Exit(0) else Exit(-1);
  end;
  Result := possible;
end;

{ reformIntervals' comparator: a before b }
function PieceLittle(const A, B: TTyVisualPiece; AEnd: Integer): Boolean;
var av, bv: Double; ac, bc: Integer;
begin
  if AEnd = 0 then
  begin
    av := A.Lo; bv := B.Lo; ac := A.Close0; bc := B.Close0;
  end
  else
  begin
    av := A.Hi; bv := B.Hi; ac := A.Close1; bc := B.Close1;
  end;
  if Lt(av, bv) then Exit(True);
  if not (Le(av, bv) and Ge(av, bv)) then Exit(False);
  if AEnd = 0 then
    Result := (ac - bc = 1) or PieceLittle(A, B, 1)
  else
    Result := ac - bc = -1;
end;

function PieceCmp(const A, B: TTyVisualPiece): Integer;
begin
  if PieceLittle(A, B, 0) then Result := -1 else Result := 1;
end;

{ Array.prototype.sort on V8 for a short list: one run from the start
  (reversed when it descends), then binary insertion -- the same procedure
  TyPrepareVisualTypes transcribes, here over pieces }
procedure V8SortPieces(var A: TTyVisualPieceArray);
var
  n, runEnd, lo, hi, left, right, mid, i: Integer;
  pivot, t: TTyVisualPiece;
begin
  n := Length(A);
  if n < 2 then Exit;
  runEnd := 2;
  if PieceCmp(A[1], A[0]) < 0 then
  begin
    while (runEnd < n) and (PieceCmp(A[runEnd], A[runEnd - 1]) < 0) do Inc(runEnd);
    lo := 0;
    hi := runEnd - 1;
    while lo < hi do
    begin
      t := A[lo];
      A[lo] := A[hi];
      A[hi] := t;
      Inc(lo);
      Dec(hi);
    end;
  end
  else
    while (runEnd < n) and (PieceCmp(A[runEnd], A[runEnd - 1]) >= 0) do Inc(runEnd);
  for i := runEnd to n - 1 do
  begin
    pivot := A[i];
    left := 0;
    right := i;
    while left < right do
    begin
      mid := left + ((right - left) shr 1);
      if PieceCmp(pivot, A[mid]) < 0 then right := mid else left := mid + 1;
    end;
    for mid := i downto left + 1 do A[mid] := A[mid - 1];
    A[left] := pivot;
  end;
end;

{ util/number reformIntervals: sorted, then swept -- an end at or behind
  the sweep is pulled up to it, and a point left without both ends closed is
  spliced out. The sweep keeps what a spliced piece set. }
procedure ReformIntervals(var APieces: TTyVisualPieceArray);
var
  curr: Double;
  currClose, i, lg, k: Integer;
  v: Double;
begin
  V8SortPieces(APieces);
  curr := NegInfinity;
  currClose := 1;
  i := 0;
  while i < Length(APieces) do
  begin
    for lg := 0 to 1 do
    begin
      if lg = 0 then v := APieces[i].Lo else v := APieces[i].Hi;
      if Le(v, curr) then
      begin
        if lg = 0 then
        begin
          APieces[i].Lo := curr;
          APieces[i].Close0 := 1 - currClose;
        end
        else
        begin
          APieces[i].Hi := curr;
          APieces[i].Close1 := 1;
        end;
      end;
      if lg = 0 then
      begin
        curr := APieces[i].Lo;
        currClose := APieces[i].Close0;
      end
      else
      begin
        curr := APieces[i].Hi;
        currClose := APieces[i].Close1;
      end;
    end;
    if Le(APieces[i].Lo, APieces[i].Hi) and Ge(APieces[i].Lo, APieces[i].Hi)
      and (APieces[i].Close0 * APieces[i].Close1 <> 1) then
    begin
      for k := i to High(APieces) - 1 do APieces[k] := APieces[k + 1];
      SetLength(APieces, Length(APieces) - 1);
    end
    else
      Inc(i);
  end;
end;

{ formatValueText: a number to its precision, the ends of the data bound
  as 'min' and 'max', an interval with its edge symbols, a string
  formatter's {value} and {value2} }
function FormatPieceText(AIsInterval: Boolean; A0, A1: Double;
  const ACategory: string; AIsCategory: Boolean; APrecision: Integer;
  const AFormatter: string; const AEdge0, AEdge1: string): string;

  function Fixed(V: Double): string;
  begin
    if IsInfinite(V) and (V < 0) then Exit('min');
    if IsInfinite(V) then Exit('max');
    Result := TyJsToFixedStr(V, Min(APrecision, 20));
  end;

var
  t0, t1: string;
  p: Integer;
  prm: TTyChartCallbackParams;
begin
  { A NAMED HANDLER is given the numbers, not their text: (lo, hi) for an
    interval -- an open end is an infinity -- (value) for a value, and the
    category for a category. }
  if TyChartIsHandlerRef(AFormatter) then
  begin
    prm := TyChartBlankParams;
    prm.ComponentType := 'visualMap';
    if AIsCategory then
    begin
      prm.Name := ACategory;
      prm.ValueText := ACategory;
    end
    else
    begin
      if AIsInterval then SetLength(prm.Values, 2) else SetLength(prm.Values, 1);
      prm.Values[0] := A0;
      if AIsInterval then prm.Values[1] := A1;
      prm.ValueText := TyChartValueText(A0);
    end;
    Exit(TyChartRunHandler(AFormatter, TyChartOneParams(prm)));
  end;
  if AIsCategory then
  begin
    t0 := ACategory;
    t1 := ACategory;
  end
  else if AIsInterval then
  begin
    t0 := Fixed(A0);
    t1 := Fixed(A1);
  end
  else
  begin
    t0 := Fixed(A0);
    t1 := t0;
  end;
  if AFormatter <> '' then
  begin
    Result := AFormatter;
    p := Pos('{value}', Result);
    if p > 0 then Result := Copy(Result, 1, p - 1) + t0 + Copy(Result, p + 7, MaxInt);
    p := Pos('{value2}', Result);
    if p > 0 then Result := Copy(Result, 1, p - 1) + t1 + Copy(Result, p + 8, MaxInt);
    Exit;
  end;
  if AIsInterval then
  begin
    if IsInfinite(A0) and (A0 < 0) then Result := AEdge0 + ' ' + t1
    else if IsInfinite(A1) and (A1 > 0) then Result := AEdge1 + ' ' + t0
    else Result := t0 + ' - ' + t1;
  end
  else
    Result := t0;
end;

{ parseInt(x, 10) of a number or a string }
function JsParseIntOf(A: TJSONData): Double;
var s: string; i: Integer; neg: Boolean; v: Double;
begin
  Result := NaN;
  if A = nil then Exit;
  if A.JSONType = jtNumber then s := TyJsNumberToString(A.AsFloat)
  else if A.JSONType = jtString then s := A.AsString
  else Exit;
  s := TyJsTrim(s);
  i := 1;
  neg := False;
  if (i <= Length(s)) and (s[i] in ['+', '-']) then
  begin
    neg := s[i] = '-';
    Inc(i);
  end;
  if (i > Length(s)) or not (s[i] in ['0'..'9']) then Exit;
  v := 0;
  while (i <= Length(s)) and (s[i] in ['0'..'9']) do
  begin
    v := v * 10 + (Ord(s[i]) - Ord('0'));
    Inc(i);
  end;
  if neg then v := -v;
  Result := v;
end;

procedure PushPiece(var APieces: TTyVisualPieceArray; ALo, AHi: Double;
  AClose0, AClose1: Integer);
var n: Integer;
begin
  n := Length(APieces);
  SetLength(APieces, n + 1);
  APieces[n] := Default(TTyVisualPiece);
  APieces[n].HasInterval := True;
  APieces[n].Lo := ALo;
  APieces[n].Hi := AHi;
  APieces[n].Close0 := AClose0;
  APieces[n].Close1 := AClose1;
  APieces[n].Index := -1;
  APieces[n].Value := NaN;
end;

{ visualMapPreprocessor: ec2's `splitList` is `pieces` when there is no
  `pieces` key at all }
function EffectivePieces(ANode: TJSONObject): TJSONData;
begin
  if (ANode.IndexOfName('splitList') >= 0) and (ANode.IndexOfName('pieces') < 0) then
    Result := ANode.Find('splitList')
  else
    Result := ANode.Find('pieces');
end;

{ the three resetMethods, into ASpec.Pieces }
procedure BuildPieces(ANode: TJSONObject; var ASpec: TTyVisualMapSpec);
var
  d, pd, e: TJSONData;
  arr: TJSONArray;
  po: TJSONObject;
  i, k, lg, n, prec: Integer;
  sn, step, curr, mx: Double;
  piece: TTyVisualPiece;
  names: array[0..1, 0..2] of string;
  edge0, edge1: string;
  useMinMax: array[0..1] of Boolean;
  found: Boolean;
  vertical, inverse: Boolean;

  procedure Reverse(var A: TTyVisualPieceArray);
  var a0, b0: Integer; t: TTyVisualPiece;
  begin
    a0 := 0;
    b0 := High(A);
    while a0 < b0 do
    begin
      t := A[a0];
      A[a0] := A[b0];
      A[b0] := t;
      Inc(a0);
      Dec(b0);
    end;
  end;

begin
  ASpec.Pieces := nil;
  { normalizeReverse: `orient === 'vertical' ? !inverse : inverse`, the
    orient 'vertical' by default }
  d := ANode.Find('orient');
  vertical := (d = nil) or (d.JSONType = jtNull)
    or ((d.JSONType = jtString) and (d.AsString = 'vertical'));
  inverse := Truthy(ANode.Find('inverse'));
  d := ANode.Find('precision');
  if (d <> nil) and (d.JSONType = jtNumber) then prec := Trunc(d.AsFloat) else prec := 0;
  d := ANode.Find('formatter');
  if (d <> nil) and (d.JSONType = jtString) then ASpec.Formatter := d.AsString;

  { _determineMode: pieces (a non-empty list), else categories, else
    splitNumber }
  pd := EffectivePieces(ANode);
  d := ANode.Find('categories');
  if (pd <> nil) and (pd.JSONType = jtArray) and (TJSONArray(pd).Count > 0) then
    ASpec.Mode := tpmPieces
  else if Truthy(d) then
    ASpec.Mode := tpmCategories
  else
    ASpec.Mode := tpmSplitNumber;

  case ASpec.Mode of
    tpmSplitNumber:
      begin
        prec := Min(prec, 20);
        d := ANode.Find('splitNumber');
        if (d = nil) or (d.JSONType = jtNull) then sn := 5 else sn := JsParseIntOf(d);
        if not IsNan(sn) then sn := Max(sn, 1);
        step := (ASpec.Extent1 - ASpec.Extent0) / sn;
        { the precision grows until the step survives toFixed, up to 5 }
        while (not (Le(TyJsToNumber(TyJsToFixedStr(step, prec)), step)
          and Ge(TyJsToNumber(TyJsToFixedStr(step, prec)), step))) and (prec < 5) do
          Inc(prec);
        step := TyJsToNumber(TyJsToFixedStr(step, prec));
        d := ANode.Find('minOpen');
        if (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean then
          PushPiece(ASpec.Pieces, NegInfinity, ASpec.Extent0, 0, 0);
        { ACCUMULATED: each end is the last plus the step }
        curr := ASpec.Extent0;
        i := 0;
        while (not IsNan(sn)) and (i < sn) do
        begin
          if i = sn - 1 then mx := ASpec.Extent1 else mx := curr + step;
          PushPiece(ASpec.Pieces, curr, mx, 1, 1);
          curr := curr + step;
          Inc(i);
        end;
        d := ANode.Find('maxOpen');
        if (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean then
          PushPiece(ASpec.Pieces, ASpec.Extent1, Infinity, 0, 0);
        ReformIntervals(ASpec.Pieces);
        for i := 0 to High(ASpec.Pieces) do
        begin
          ASpec.Pieces[i].Index := i;
          ASpec.Pieces[i].Key := IntToStr(i);
          ASpec.Pieces[i].Text := FormatPieceText(True, ASpec.Pieces[i].Lo,
            ASpec.Pieces[i].Hi, '', False, prec, ASpec.Formatter, '<', '>');
        end;
      end;
    tpmCategories:
      begin
        if d.JSONType = jtArray then
        begin
          arr := TJSONArray(d);
          SetLength(ASpec.Categories, arr.Count);
          for i := 0 to arr.Count - 1 do
          begin
            ASpec.Categories[i] := JsStrOf(arr.Items[i]);
            n := Length(ASpec.Pieces);
            SetLength(ASpec.Pieces, n + 1);
            ASpec.Pieces[n] := Default(TTyVisualPiece);
            ASpec.Pieces[n].HasValue := True;
            ASpec.Pieces[n].ValueIsStr := True;
            ASpec.Pieces[n].ValueStr := ASpec.Categories[i];
            ASpec.Pieces[n].Value := NaN;
            ASpec.Pieces[n].Index := -1;
            ASpec.Pieces[n].Key := ASpec.Categories[i];
            ASpec.Pieces[n].Text := FormatPieceText(False, 0, 0, ASpec.Categories[i],
              True, prec, ASpec.Formatter, '', '');
          end;
        end;
        { normalizeReverse }
        if vertical <> inverse then Reverse(ASpec.Pieces);
      end;
    tpmPieces:
      begin
        arr := TJSONArray(pd);
        names[0, 0] := 'gte'; names[0, 1] := 'gt'; names[0, 2] := 'min';
        names[1, 0] := 'lte'; names[1, 1] := 'lt'; names[1, 2] := 'max';
        for i := 0 to arr.Count - 1 do
        begin
          piece := Default(TTyVisualPiece);
          piece.Index := i;
          piece.Key := IntToStr(i);
          piece.Value := NaN;
          e := arr.Items[i];
          po := nil;
          if e.JSONType = jtObject then po := TJSONObject(e);
          if (po <> nil) and (po.Find('label') <> nil) and (po.Find('label').JSONType <> jtNull) then
            piece.Text := JsStrOf(po.Find('label'));
          if (po = nil) or (po.IndexOfName('value') >= 0) then
          begin
            { a value piece: [v, v], both ends closed }
            if po = nil then e := arr.Items[i] else e := po.Find('value');
            piece.HasValue := True;
            if e.JSONType = jtString then
            begin
              piece.ValueIsStr := True;
              piece.ValueStr := e.AsString;
              piece.Value := TyJsToNumber(e.AsString);
            end
            else if e.JSONType = jtNumber then
              piece.Value := e.AsFloat;
            piece.HasInterval := True;
            piece.Lo := piece.Value;
            piece.Hi := piece.Value;
            piece.Close0 := 1;
            piece.Close1 := 1;
          end
          else
          begin
            piece.HasInterval := True;
            for lg := 0 to 1 do
            begin
              { EVERY ATTEMPT sets the close flag and useMinMax, found or not:
                a missing bound ends on 'min'/'max' -- closed, useMinMax }
              useMinMax[lg] := False;
              mx := NaN;
              found := False;
              for k := 0 to 2 do
              begin
                e := po.Find(names[lg, k]);
                { the preprocessor: ec2's start / end are min / max when
                  there is no min / max key }
                if (k = 2) and (po.IndexOfName(names[lg, k]) < 0) then
                  if lg = 0 then e := po.Find('start') else e := po.Find('end');
                if lg = 0 then piece.Close0 := Ord(k <> 1) else piece.Close1 := Ord(k <> 1);
                useMinMax[lg] := k = 2;
                if (e <> nil) and (e.JSONType <> jtNull) then
                begin
                  if e.JSONType = jtNumber then mx := e.AsFloat
                  else mx := TyJsToNumber(e.AsString);
                  found := True;
                  Break;
                end;
              end;
              if not found then
              begin
                if lg = 0 then mx := NegInfinity else mx := Infinity;
              end;
              if lg = 0 then piece.Lo := mx else piece.Hi := mx;
            end;
            if useMinMax[0] and IsInfinite(piece.Hi) and (piece.Hi > 0) then piece.Close0 := 0;
            if useMinMax[1] and IsInfinite(piece.Lo) and (piece.Lo < 0) then piece.Close1 := 0;
            if Le(piece.Lo, piece.Hi) and Ge(piece.Lo, piece.Hi)
              and (piece.Close0 = 1) and (piece.Close1 = 1) then
            begin
              piece.HasValue := True;
              piece.Value := piece.Lo;
            end;
          end;
          { retrieveVisuals: the piece's own visual keys }
          if po <> nil then
            for k := 0 to High(cHandlerOrder) do
              if po.IndexOfName(cHandlerOrder[k]) >= 0 then
              begin
                n := Length(piece.Visuals);
                SetLength(piece.Visuals, n + 1);
                piece.Visuals[n] := PieceVisualOf(po.Find(cHandlerOrder[k]));
                piece.Visuals[n].Kind := cHandlerOrder[k];
              end;
          n := Length(ASpec.Pieces);
          SetLength(ASpec.Pieces, n + 1);
          ASpec.Pieces[n] := piece;
        end;
        if vertical <> inverse then Reverse(ASpec.Pieces);
        ReformIntervals(ASpec.Pieces);
        for i := 0 to High(ASpec.Pieces) do
          if ASpec.Pieces[i].Text = '' then
          begin
            if ASpec.Pieces[i].Close1 <> 0 then edge0 := '≤' else edge0 := '<';
            if ASpec.Pieces[i].Close0 <> 0 then edge1 := '≥' else edge1 := '>';
            { `+value`, a string value too }
            if ASpec.Pieces[i].HasValue then
              ASpec.Pieces[i].Text := FormatPieceText(False, ASpec.Pieces[i].Value, 0,
                '', False, prec, ASpec.Formatter, edge0, edge1)
            else
              ASpec.Pieces[i].Text := FormatPieceText(True, ASpec.Pieces[i].Lo,
                ASpec.Pieces[i].Hi, '', False, prec, ASpec.Formatter, edge0, edge1);
          end;
      end;
  end;
  ASpec.Precision := prec;
end;

{ _resetSelected: the written map, every missing key selected, and single
  mode keeping only the first selected }
procedure BuildSelected(ANode: TJSONObject; var ASpec: TTyVisualMapSpec);
var
  sel: TJSONObject;
  d: TJSONData;
  i: Integer;
  single, hasSel: Boolean;
begin
  SetLength(ASpec.Selected, Length(ASpec.Pieces));
  sel := ObjOf(ANode.Find('selected'));
  for i := 0 to High(ASpec.Pieces) do
  begin
    ASpec.Selected[i] := True;
    if sel <> nil then
    begin
      d := sel.Find(ASpec.Pieces[i].Key);
      if d <> nil then ASpec.Selected[i] := Truthy(d);
    end;
  end;
  d := ANode.Find('selectedMode');
  single := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'single');
  if single then
  begin
    hasSel := False;
    for i := 0 to High(ASpec.Pieces) do
      if ASpec.Selected[i] then
      begin
        if hasSel then ASpec.Selected[i] := False else hasSel := True;
      end;
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
function InactiveDefault(const AType: string; ACategory: Boolean = False): TJSONData;
begin
  if ACategory then
  begin
    { visualDefault.get(.., isCategory): the list's last element }
    if AType = 'color' then Exit(TJSONString.Create('rgba(0,0,0,0)'));
    if (AType = 'colorHue') or (AType = 'colorSaturation')
      or (AType = 'colorLightness') or (AType = 'colorAlpha')
      or (AType = 'opacity') or (AType = 'symbolSize') then
      Exit(TJSONIntegerNumber.Create(0));
    if AType = 'symbol' then Exit(TJSONString.Create('none'));
    Exit(nil);
  end;
  if AType = 'color' then Exit(TJSONArray.Create(['rgba(0,0,0,0)']));
  if (AType = 'colorHue') or (AType = 'colorSaturation')
    or (AType = 'colorLightness') or (AType = 'colorAlpha')
    or (AType = 'opacity') or (AType = 'symbolSize') then
    Exit(TJSONArray.Create([0, 0]));
  if AType = 'symbol' then Exit(TJSONArray.Create(['none']));
  Result := nil;
end;

{ visualDefault's `active` column, for a type a piece names that no state
  does }
function ActiveDefault(const AType: string; ACategory: Boolean): TJSONData;
var a: TJSONArray;
begin
  Result := nil;
  if AType = 'color' then a := TJSONArray.Create(['#006edd', '#e0ffff'])
  else if AType = 'colorHue' then a := TJSONArray.Create([0, 360])
  else if AType = 'colorSaturation' then a := TJSONArray.Create([0.3, 1])
  else if AType = 'colorLightness' then a := TJSONArray.Create([0.9, 0.5])
  else if (AType = 'colorAlpha') or (AType = 'opacity') then a := TJSONArray.Create([0.3, 1])
  else if AType = 'symbol' then a := TJSONArray.Create(['circle', 'roundRect', 'diamond'])
  else if AType = 'symbolSize' then a := TJSONArray.Create([10, 50])
  else Exit;
  if ACategory then
  begin
    Result := a.Items[a.Count - 1].Clone;
    a.Free;
  end
  else
    Result := a;
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

function MappingOf(const AType: string; AVisual: TJSONData;
  AMethod: TTyVisualMethod; const ACats: TTyStringArray): TTyVisualMapping;
var
  list: TJSONArray;
  i, k: Integer;
  o: TJSONObject;
begin
  Result := Default(TTyVisualMapping);
  Result.Kind := AType;
  Result.Method := AMethod;
  if AMethod = tvmCategory then
  begin
    { preprocessForSpecifiedCategory: an array by index, an object by
      category name (an unknown name to the default slot), a single value
      the default slot; a category with no visual is dropped from the map }
    Result.Cats := Copy(ACats);
    SetLength(Result.CatVals, Length(ACats));
    Result.CatDefault := PieceVisualOf(nil);
    if AVisual <> nil then
      case AVisual.JSONType of
        jtArray:
          for i := 0 to Min(TJSONArray(AVisual).Count, Length(ACats)) - 1 do
            Result.CatVals[i] := PieceVisualOf(TJSONArray(AVisual).Items[i]);
        jtObject:
          begin
            o := TJSONObject(AVisual);
            for i := 0 to o.Count - 1 do
            begin
              k := Length(ACats) - 1;
              while (k >= 0) and (ACats[k] <> o.Names[i]) do Dec(k);
              if k >= 0 then Result.CatVals[k] := PieceVisualOf(o.Items[i])
              else Result.CatDefault := PieceVisualOf(o.Items[i]);
            end;
          end;
        jtNull: ;
      else
        Result.CatDefault := PieceVisualOf(AVisual);
      end;
    for i := 0 to High(Result.CatVals) do Result.CatVals[i].Kind := AType;
    Result.CatDefault.Kind := AType;
    Exit;
  end;
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
    if AType = 'symbol' then
    begin
      SetLength(Result.Strs, list.Count);
      for i := 0 to list.Count - 1 do
        if list.Items[i].JSONType in [jtString, jtNumber] then
          Result.Strs[i] := list.Items[i].AsString;
      Exit;
    end;
    if list.Count = 1 then list.Add(list.Items[0].Clone);
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

const cStateNames: array[TTyVisualState] of string = ('inRange', 'outOfRange');

procedure ReadStates(ATarget: TJSONObject; var AKeys: TTyVisualStateKeys;
  var AStates: TTyVisualStateMaps; AMethod: TTyVisualMethod;
  const ACats: TTyStringArray);
var
  st: TTyVisualState;
  obj: TJSONObject;
  i, n: Integer;
  valid, order: TTyStringArray;
begin
  for st := Low(TTyVisualState) to High(TTyVisualState) do
  begin
    AKeys[st] := nil;
    AStates[st] := nil;
    obj := ObjOf(ATarget.Find(cStateNames[st]));
    if obj = nil then Continue;
    SetLength(AKeys[st], obj.Count);
    valid := nil;
    for i := 0 to obj.Count - 1 do
    begin
      AKeys[st][i] := obj.Names[i];
      if TyVisualIsValidType(obj.Names[i]) then
      begin
        n := Length(valid);
        SetLength(valid, n + 1);
        valid[n] := obj.Names[i];
      end;
    end;
    order := TyPrepareVisualTypes(valid);
    SetLength(AStates[st], Length(order));
    for i := 0 to High(order) do
    begin
      AStates[st][i] := MappingOf(order[i], obj.Find(order[i]), AMethod, ACats);
      { out of range, the pieces carry no visual of their own }
      AStates[st][i].UsePieces := (AMethod = tvmPiecewise) and (st = tvsInRange);
    end;
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
begin
  Result := TyVisualMapSpecOf(AOption, AIndex, ARamp,
    TyVisualRgba(207, 210, 215, 1));
end;

function TyVisualMapSpecOf(AOption: TTyChartOption; AIndex: Integer;
  const ARamp: TTyVisualColorArray;
  const AInactive: TTyVisualColor): TTyVisualMapSpec;
var
  node, target, controller, base, st, absent: TJSONObject;
  d: TJSONData;
  i: Integer;
  e0, e1, r0, r1, t: Double;
  defa: TJSONData;
  vs: TTyVisualState;
  symExists, sizeExists: TJSONData;
  itemW, mx: Double;
  isCat: Boolean;
  method: TTyVisualMethod;
  defSymbol: string;

  { PiecewiseModel.completeVisualOption: a visual type some piece writes
    that no state of the option or its target has gets visualDefault's
    active / inactive values in the OPTION's states -- which then exist, so
    completeSingle adds no default colour to a state made here }
  procedure CompletePieceTypes(ABase: TJSONObject);
  var
    pd, tg: TJSONData;
    types: TTyStringArray;
    k, j: Integer;
    exists: Boolean;
    s: TTyVisualState;
    so: TJSONObject;
    dv: TJSONData;

    function InTypes(const AType: string): Boolean;
    var q: Integer;
    begin
      for q := 0 to High(types) do
        if types[q] = AType then Exit(True);
      Result := False;
    end;

    function Has(AObj: TJSONObject; AState: TTyVisualState; const AType: string): Boolean;
    var o: TJSONObject;
    begin
      Result := False;
      if AObj = nil then Exit;
      o := ObjOf(AObj.Find(cStateNames[AState]));
      Result := (o <> nil) and (o.IndexOfName(AType) >= 0);
    end;

  begin
    pd := EffectivePieces(node);
    if (pd = nil) or (pd.JSONType <> jtArray) then Exit;
    types := nil;
    for k := 0 to TJSONArray(pd).Count - 1 do
    begin
      if TJSONArray(pd).Items[k].JSONType <> jtObject then Continue;
      for j := 0 to High(cHandlerOrder) do
        if (TJSONObject(TJSONArray(pd).Items[k]).IndexOfName(cHandlerOrder[j]) >= 0)
          and not InTypes(cHandlerOrder[j]) then
        begin
          SetLength(types, Length(types) + 1);
          types[High(types)] := cHandlerOrder[j];
        end;
    end;
    tg := node.Find('target');
    for k := 0 to High(types) do
    begin
      exists := False;
      for s := Low(TTyVisualState) to High(TTyVisualState) do
        exists := exists or Has(ABase, s, types[k]) or Has(ObjOf(tg), s, types[k]);
      if exists then Continue;
      for s := Low(TTyVisualState) to High(TTyVisualState) do
      begin
        so := ObjOf(ABase.Find(cStateNames[s]));
        if so = nil then
        begin
          so := TJSONObject.Create;
          SetKey(ABase, cStateNames[s], so);
        end;
        if s = tvsInRange then dv := ActiveDefault(types[k], isCat)
        else dv := InactiveDefault(types[k], isCat);
        { `undefined` for a type with no default }
        if dv = nil then dv := TJSONNull.Create;
        SetKey(so, types[k], dv);
      end;
    end;
  end;

  { mapVisual over an array's elements, an object's values, or the one value }
  procedure NoneToDefault(AState: TJSONObject);
  var dd: TJSONData; k: Integer;
  begin
    dd := AState.Find('symbol');
    if dd = nil then Exit;
    case dd.JSONType of
      jtArray:
        for k := 0 to TJSONArray(dd).Count - 1 do
          if (TJSONArray(dd).Items[k].JSONType = jtString)
            and (TJSONArray(dd).Items[k].AsString = 'none') then
            TJSONArray(dd).Items[k] := TJSONString.Create(defSymbol);
      jtObject:
        for k := 0 to TJSONObject(dd).Count - 1 do
          if (TJSONObject(dd).Items[k].JSONType = jtString)
            and (TJSONObject(dd).Items[k].AsString = 'none') then
            TJSONObject(dd).Items[k] := TJSONString.Create(defSymbol);
      jtString:
        if dd.AsString = 'none' then SetKey(AState, 'symbol', TJSONString.Create(defSymbol));
    end;
  end;

  { completeSingle: ec2's high-to-low `color`, then the gradient }
  procedure CompleteSingle(AObj: TJSONObject);
  var
    inRange, root, ramp, c: TJSONData;
    arr: TJSONArray;
    so: TJSONObject;
    k: Integer;
  begin
    inRange := AObj.Find('inRange');
    c := node.Find('color');
    if (c <> nil) and (c.JSONType = jtArray) and not Truthy(inRange) then
    begin
      arr := TJSONArray.Create;
      for k := TJSONArray(c).Count - 1 downto 0 do
        arr.Add(TJSONArray(c).Items[k].Clone);
      so := TJSONObject.Create;
      so.Add('color', arr);
      SetKey(AObj, 'inRange', so);
      inRange := so;
    end;
    if not Truthy(inRange) then
    begin
      root := AOption.Find('gradientColor');
      if root <> nil then
        ramp := root.Clone
      else
      begin
        arr := TJSONArray.Create;
        for k := 0 to High(ARamp) do arr.Add(TyVisualCss(ARamp[k]));
        ramp := arr;
      end;
      so := TJSONObject.Create;
      so.Add('color', ramp);
      SetKey(AObj, 'inRange', so);
    end;
  end;

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

  { PIECEWISE: the pieces, the selected map, and the mapping method --
    `category` in categories mode only, while every default follows
    `!!option.categories` }
  isCat := False;
  method := tvmLinear;
  defSymbol := 'roundRect';
  if Result.SubType = 'piecewise' then
  begin
    isCat := Truthy(node.Find('categories'));
    Result.IsCategory := isCat;
    BuildPieces(node, Result);
    BuildSelected(node, Result);
    if Result.Mode = tpmCategories then method := tvmCategory
    else method := tvmPiecewise;
    { getItemSymbol: the option's, 'roundRect' by default; `|| 'roundRect'` }
    d := node.Find('itemSymbol');
    if (d = nil) or (d.JSONType = jtNull) then defSymbol := 'roundRect'
    else if Truthy(d) then defSymbol := JsStrOf(d);
  end;
  { resetItemSize's width, for the controller's sizes }
  itemW := NaN;
  d := node.Find('itemWidth');
  if (d <> nil) and (d.JSONType = jtNumber) then itemW := d.AsFloat
  else if (d <> nil) and (d.JSONType = jtString) then itemW := TyJsParseFloat(d.AsString);
  if IsNan(itemW) then itemW := 20;

  { completeVisualOption, on a copy: target merged with the option's own
    states, per key and without overwriting }
  d := node.Find('target');
  if (d <> nil) and (d.JSONType = jtObject) then
    target := TJSONObject(d.Clone)
  else
    target := TJSONObject.Create;
  d := node.Find('controller');
  if (d <> nil) and (d.JSONType = jtObject) then
    controller := TJSONObject(d.Clone)
  else
    controller := TJSONObject.Create;
  base := TJSONObject.Create;
  try
    d := node.Find('inRange');
    if (d <> nil) then base.Add('inRange', d.Clone);
    d := node.Find('outOfRange');
    if (d <> nil) then base.Add('outOfRange', d.Clone);
    if Result.SubType = 'piecewise' then CompletePieceTypes(base);
    MergeKeep(target, base);
    MergeKeep(controller, base);
    CompleteSingle(target);
    CompleteSingle(controller);

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
        defa := InactiveDefault(st.Names[i], isCat);
        if defa = nil then Continue;
        SetKey(absent, st.Names[i], defa);
        if (st.Names[i] = 'color') and (absent.IndexOfName('opacity') < 0)
          and (absent.IndexOfName('colorAlpha') < 0) then
          absent.Add('opacity', TJSONArray.Create([0, 0]));
      end;
    end;
    ReadStates(target, Result.Keys, Result.States, method, Result.Categories);

    { completeController: a missing state is the inactive colour; a missing
      symbol or size is the other state's, else a round rect the item width
      square; `none` is the round rect; every size rescaled so the largest is
      the item width; and, continuous, a size pair that differs starts at a
      third of its end. What either state wrote is looked for BEFORE any
      state is filled in. }
    symExists := nil;
    sizeExists := nil;
    for vs := Low(TTyVisualState) to High(TTyVisualState) do
    begin
      st := ObjOf(controller.Find(cStateNames[vs]));
      if st = nil then Continue;
      if (symExists = nil) and Truthy(st.Find('symbol')) then
        symExists := st.Find('symbol');
      if (sizeExists = nil) and Truthy(st.Find('symbolSize')) then
        sizeExists := st.Find('symbolSize');
    end;
    if symExists <> nil then symExists := symExists.Clone;
    if sizeExists <> nil then sizeExists := sizeExists.Clone;
    try
      for vs := Low(TTyVisualState) to High(TTyVisualState) do
      begin
        if not Truthy(controller.Find(cStateNames[vs])) then
        begin
          st := TJSONObject.Create;
          if isCat then st.Add('color', TyVisualCss(AInactive))
          else st.Add('color', TJSONArray.Create([TyVisualCss(AInactive)]));
          SetKey(controller, cStateNames[vs], st);
        end;
        st := ObjOf(controller.Find(cStateNames[vs]));
        if st = nil then Continue;
        d := st.Find('symbol');
        if (d = nil) or (d.JSONType = jtNull) then
        begin
          if symExists <> nil then SetKey(st, 'symbol', symExists.Clone)
          else if isCat then SetKey(st, 'symbol', TJSONString.Create(defSymbol))
          else SetKey(st, 'symbol', TJSONArray.Create([defSymbol]));
        end;
        d := st.Find('symbolSize');
        if (d = nil) or (d.JSONType = jtNull) then
        begin
          if sizeExists <> nil then SetKey(st, 'symbolSize', sizeExists.Clone)
          else if isCat then SetKey(st, 'symbolSize', TJSONFloatNumber.Create(itemW))
          else SetKey(st, 'symbolSize', TJSONArray.Create([itemW, itemW]));
        end;
        { `none` filtered to the default symbol }
        NoneToDefault(st);
        { normalise the size to [0, itemW] by its largest value }
        d := st.Find('symbolSize');
        if d <> nil then
        begin
          mx := NegInfinity;
          if d.JSONType = jtArray then
          begin
            for i := 0 to TJSONArray(d).Count - 1 do
              if (TJSONArray(d).Items[i].JSONType = jtNumber)
                and (TJSONArray(d).Items[i].AsFloat > mx) then
                mx := TJSONArray(d).Items[i].AsFloat;
            for i := 0 to TJSONArray(d).Count - 1 do
              if TJSONArray(d).Items[i].JSONType = jtNumber then
                TJSONArray(d).Items[i] := TJSONFloatNumber.Create(TyVmLinearMap(
                  TJSONArray(d).Items[i].AsFloat, 0, mx, 0, itemW, True));
            { ContinuousModel: a pair that differs starts at a third }
            if (Result.SubType = 'continuous') and (TJSONArray(d).Count >= 2)
              and (TJSONArray(d).Items[0].JSONType = jtNumber)
              and (TJSONArray(d).Items[1].JSONType = jtNumber)
              and (TJSONArray(d).Items[0].AsFloat <> TJSONArray(d).Items[1].AsFloat) then
              TJSONArray(d).Items[0] := TJSONFloatNumber.Create(
                TJSONArray(d).Items[1].AsFloat / 3);
          end
          else if d.JSONType = jtObject then
          begin
            { a categories object: every value, by the largest }
            for i := 0 to TJSONObject(d).Count - 1 do
              if (TJSONObject(d).Items[i].JSONType = jtNumber)
                and (TJSONObject(d).Items[i].AsFloat > mx) then
                mx := TJSONObject(d).Items[i].AsFloat;
            for i := 0 to TJSONObject(d).Count - 1 do
              if TJSONObject(d).Items[i].JSONType = jtNumber then
                TJSONObject(d).Items[i] := TJSONFloatNumber.Create(TyVmLinearMap(
                  TJSONObject(d).Items[i].AsFloat, 0, mx, 0, itemW, True));
          end
          else if d.JSONType = jtNumber then
          begin
            mx := d.AsFloat;
            SetKey(st, 'symbolSize', TJSONFloatNumber.Create(
              TyVmLinearMap(mx, 0, mx, 0, itemW, True)));
          end;
        end;
      end;
    finally
      symExists.Free;
      sizeExists.Free;
    end;
    ReadStates(controller, Result.ControllerKeys, Result.Controller, method,
      Result.Categories);
  finally
    base.Free;
    target.Free;
    controller.Free;
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
  if ASpec.SubType = 'piecewise' then
    Exit(TyVisualValueState(ASpec, AValue, TyJsNumberToString(AValue)));
  ub := ASpec.Unbounded;
  if ((ub and Le(ASpec.Range0, ASpec.Extent0)) or Le(ASpec.Range0, AValue))
    and ((ub and Ge(ASpec.Range1, ASpec.Extent1)) or Le(AValue, ASpec.Range1)) then
    Result := tvsInRange
  else
    Result := tvsOutOfRange;
end;

function TyVisualValueState(const ASpec: TTyVisualMapSpec; AValue: Double;
  const AText: string): TTyVisualState;
var p: Integer;
begin
  if ASpec.SubType <> 'piecewise' then Exit(TyVisualValueState(ASpec, AValue));
  { PiecewiseModel.getValueState: the piece the value is in -- no closest --
    and whether its key is selected; no piece is out of range }
  p := TyVisualFindPiece(ASpec.Pieces, AValue, AText, False);
  if (p >= 0) and (p <= High(ASpec.Selected)) and ASpec.Selected[p] then
    Result := tvsInRange
  else
    Result := tvsOutOfRange;
end;

function TyVisualRepresent(const APiece: TTyVisualPiece): Double;
begin
  if APiece.HasValue then Exit(APiece.Value);
  if not APiece.HasInterval then Exit(NaN);
  { [-Infinity, Infinity] is 0; an open end stays infinite }
  if IsInfinite(APiece.Lo) and (APiece.Lo < 0) and IsInfinite(APiece.Hi)
    and (APiece.Hi > 0) then
    Result := 0
  else
    Result := (APiece.Lo + APiece.Hi) / 2;
end;

function PairAt(const ANums: TTyDoubleArray; AIndex: Integer): Double;
begin
  if AIndex <= High(ANums) then Result := ANums[AIndex] else Result := NaN;
end;

procedure TyVisualApply(const ASpec: TTyVisualMapSpec; AState: TTyVisualState;
  AValue: Double; var ARow: TTyVisualRow; AForMeta: Boolean);
begin
  if ASpec.SubType = 'piecewise' then
    TyVisualApply(ASpec, AState, AValue, TyJsNumberToString(AValue), ARow, AForMeta)
  else
    TyVisualApply(ASpec, AState, AValue, '', ARow, AForMeta);
end;

procedure TyVisualApply(const ASpec: TTyVisualMapSpec; AState: TTyVisualState;
  AValue: Double; const AText: string; var ARow: TTyVisualRow;
  AForMeta: Boolean);
var
  i, pIdx, sp, ci: Integer;
  n, v: Double;
  m: TTyVisualMapping;
  pv: TTyVisualPieceVisual;
  c: TTyVisualColor;

  { getSpecifiedVisual: the piece the value is in (no closest) and ITS
    visual of the mapping's type -- `colorAlpha` for the visualMeta's
    `__alphaForOpacity` stand-in }
  function Specified(const AKind: string): Boolean;
  var k: Integer;
  begin
    Result := False;
    if not m.UsePieces or (sp < 0) then Exit;
    for k := 0 to High(ASpec.Pieces[sp].Visuals) do
      if ASpec.Pieces[sp].Visuals[k].Kind = AKind then
      begin
        pv := ASpec.Pieces[sp].Visuals[k];
        Exit(pv.Defined);
      end;
  end;

  { the category normaliser: categoryMap[value], which the preprocess
    emptied of every category whose visual is null; -1 is the default slot }
  function CatIndex: Integer;
  var k: Integer;
  begin
    Result := -1;
    for k := High(m.Cats) downto 0 do
      if m.Cats[k] = AText then
      begin
        Result := k;
        Break;
      end;
    if Result < 0 then Exit;
    for k := 0 to High(m.Cats) do
      if (m.Cats[k] = AText) and not m.CatVals[k].Defined then Exit(-1);
  end;

  function ColorOf(const APv: TTyVisualPieceVisual): TTyVisualColor;
  begin
    if not APv.Defined or APv.IsNum or not TyVisualTryParse(APv.Str, Result) then
      Result := TyVisualUndefined;
  end;

begin
  n := NaN;
  sp := -1;
  if (ASpec.SubType = 'piecewise') and (ASpec.Mode <> tpmCategories) then
  begin
    { the piecewise normaliser: the piece index -- the CLOSEST piece when
      the value is in none -- spread over [0, 1] }
    pIdx := TyVisualFindPiece(ASpec.Pieces, AValue, AText, True);
    if pIdx >= 0 then
      n := TyVmLinearMap(pIdx, 0, Length(ASpec.Pieces) - 1, 0, 1, True);
    sp := TyVisualFindPiece(ASpec.Pieces, AValue, AText, False);
  end
  else if ASpec.SubType <> 'piecewise' then
    { the linear normaliser, clamped, over the EXTENT -- not the range }
    n := TyVmLinearMap(AValue, ASpec.Extent0, ASpec.Extent1, 0, 1, True);
  for i := 0 to High(ASpec.States[AState]) do
  begin
    m := ASpec.States[AState][i];
    if m.Method = tvmCategory then
    begin
      { doMapCategory: the visual at the index, the default slot for -1;
        liftZ is doMapFixed, the first element }
      ci := CatIndex;
      if m.Kind = 'liftZ' then
      begin
        if AForMeta or (Length(m.CatVals) = 0) or not m.CatVals[0].Defined then Continue;
        pv := m.CatVals[0];
      end
      else if ci >= 0 then pv := m.CatVals[ci]
      else pv := m.CatDefault;
      if m.Kind = 'color' then
      begin
        ARow.Color := ColorOf(pv);
        ARow.ColorSet := True;
        Continue;
      end;
      v := pv.Num;
      if not pv.Defined then v := NaN;
      if (m.Kind = 'opacity') or (m.Kind = 'colorAlpha') or (m.Kind = 'colorHue')
        or (m.Kind = 'colorSaturation') or (m.Kind = 'colorLightness') then
      begin
        if (m.Kind = 'opacity') and not AForMeta then
        begin
          { UNDEFINED IS STILL WRITTEN: the style's opacity becomes
            undefined, over a series default such as a scatter's 0.8, and
            the element draws at 1 }
          if IsNan(v) then v := 1;
          ARow.Opacity := v;
          ARow.OpacitySet := True;
        end
        else if not IsNan(v) then
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
        Continue;
      end;
      if AForMeta then Continue;
      if m.Kind = 'symbol' then
      begin
        ARow.SymbolSet := pv.Defined;
        if pv.IsNum then ARow.Symbol := TyJsNumberToString(pv.Num)
        else ARow.Symbol := pv.Str;
      end
      else if m.Kind = 'symbolSize' then
      begin
        ARow.Size := v;
        ARow.SizeSet := not IsNan(v);
      end
      else if m.Kind = 'liftZ' then
      begin
        ARow.LiftZ := v;
        ARow.LiftZSet := not IsNan(v);
      end;
      Continue;
    end;
    if m.Kind = 'color' then
    begin
      if Specified('color') then ARow.Color := ColorOf(pv)
      else ARow.Color := TyVisualFastLerp(n, m.Colors);
      ARow.ColorSet := True;
      Continue;
    end;
    if (m.Kind = 'opacity') or (m.Kind = 'colorAlpha') or (m.Kind = 'colorHue')
      or (m.Kind = 'colorSaturation') or (m.Kind = 'colorLightness') then
    begin
      if ((m.Kind = 'opacity') and AForMeta and Specified('colorAlpha'))
        or (not ((m.Kind = 'opacity') and AForMeta) and Specified(m.Kind)) then
        v := pv.Num
      else
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
    if AForMeta then Continue;
    if m.Kind = 'symbol' then
    begin
      if Specified('symbol') then
      begin
        if pv.IsNum then ARow.Symbol := TyJsNumberToString(pv.Num)
        else ARow.Symbol := pv.Str;
        ARow.SymbolSet := True;
        Continue;
      end;
      { doMapToArray: the name at Math.round of the normalised value spread
        over the list }
      if Length(m.Strs) = 0 then Continue;
      v := TyJsRound(TyVmLinearMap(n, 0, 1, 0, Length(m.Strs) - 1, True));
      if IsNan(v) or (v < 0) or (v > High(m.Strs)) then Continue;
      ARow.Symbol := m.Strs[Trunc(v)];
      ARow.SymbolSet := True;
    end
    else if m.Kind = 'symbolSize' then
    begin
      if Specified('symbolSize') then ARow.Size := pv.Num
      else ARow.Size := TyVmLinearMap(n, 0, 1, PairAt(m.Nums, 0), PairAt(m.Nums, 1), True);
      ARow.SizeSet := True;
    end
    else if m.Kind = 'liftZ' then
    begin
      { doMapFixed for every method: the first value, never interpolated;
        no value is no lift }
      if IsNan(PairAt(m.Nums, 0)) then Continue;
      ARow.LiftZ := PairAt(m.Nums, 0);
      ARow.LiftZSet := True;
    end;
    { decal is not drawn }
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

function TyVisualSeriesValues(AStore: TTyDataStore; const ADim: TTyVisualDim;
  out AStoreCol, ADimIndex: Integer; out ATexts: TTyStringArray): TTyDoubleArray;
var
  raw: Integer;
  cell: TTyDataValue;
begin
  Result := TyVisualSeriesValues(AStore, ADim, AStoreCol, ADimIndex);
  SetLength(ATexts, Length(Result));
  for raw := 0 to High(Result) do
  begin
    ATexts[raw] := TyJsNumberToString(Result[raw]);
    { AN ORDINAL COLUMN NO AXIS READS keeps the string as written -- what a
      category is matched against; an axis's column holds its ordinals }
    if (AStoreCol < 0) and (ADimIndex >= 0)
      and TTyDataStore.RawCell(AStore.RawItemByRaw(raw), ADimIndex, cell)
      and (cell.Kind = dvkText) then
      ATexts[raw] := cell.Text;
  end;
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

{ PiecewiseModel.getVisualMeta: none for categories; else the piece list
  supplemented with [-Infinity, first low] and [last high, Infinity], every
  gap an outOfRange pair, each interval coloured at its representative value
  -- a finite one as two stops, an open one as an outer colour }
function PiecewiseMeta(const ASpec: TTyVisualMapSpec;
  const ASeriesColor: TTyVisualColor): TTyVisualMeta;
var
  lows, highs: TTyDoubleArray;
  i, n: Integer;
  curr: Double;

  procedure Add(ALo, AHi: Double);
  var k: Integer;
  begin
    k := Length(lows);
    SetLength(lows, k + 1);
    SetLength(highs, k + 1);
    lows[k] := ALo;
    highs[k] := AHi;
  end;

  procedure SetStop(ALo, AHi: Double; AGiven: Boolean; AState: TTyVisualState);
  var
    p: TTyVisualPiece;
    rv: Double;
    row: TTyVisualRow;
    k: Integer;
  begin
    p := Default(TTyVisualPiece);
    p.HasInterval := True;
    p.Lo := ALo;
    p.Hi := AHi;
    rv := TyVisualRepresent(p);
    if not AGiven then AState := TyVisualValueState(ASpec, rv);
    row := Default(TTyVisualRow);
    row.Color := ASeriesColor;
    TyVisualApply(ASpec, AState, rv, row, True);
    if IsInfinite(ALo) and (ALo < 0) then
      Result.Outer0 := row.Color
    else if IsInfinite(AHi) and (AHi > 0) then
      Result.Outer1 := row.Color
    else
    begin
      k := Length(Result.Stops);
      SetLength(Result.Stops, k + 2);
      Result.Stops[k].Value := ALo;
      Result.Stops[k].Color := row.Color;
      Result.Stops[k + 1].Value := AHi;
      Result.Stops[k + 1].Color := row.Color;
    end;
  end;

begin
  Result := Default(TTyVisualMeta);
  Result.VisualMap := ASpec.Index;
  Result.Dimension := -1;
  { outerColors ['', '']: nothing }
  Result.Outer0 := TyVisualUndefined;
  Result.Outer1 := TyVisualUndefined;
  if ASpec.IsCategory then Exit;
  lows := nil;
  highs := nil;
  n := Length(ASpec.Pieces);
  if n = 0 then
    Add(NegInfinity, Infinity)
  else
  begin
    if not (IsInfinite(ASpec.Pieces[0].Lo) and (ASpec.Pieces[0].Lo < 0)) then
      Add(NegInfinity, ASpec.Pieces[0].Lo);
    for i := 0 to n - 1 do
      Add(ASpec.Pieces[i].Lo, ASpec.Pieces[i].Hi);
    if not (IsInfinite(ASpec.Pieces[n - 1].Hi) and (ASpec.Pieces[n - 1].Hi > 0)) then
      Add(ASpec.Pieces[n - 1].Hi, Infinity);
  end;
  curr := NegInfinity;
  for i := 0 to High(lows) do
  begin
    { fulfil the gap }
    if Gt(lows[i], curr) then SetStop(curr, lows[i], True, tvsOutOfRange);
    SetStop(lows[i], highs[i], False, tvsInRange);
    curr := highs[i];
  end;
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
  if ASpec.SubType = 'piecewise' then
  begin
    Result := PiecewiseMeta(ASpec, ASeriesColor);
    Exit;
  end;
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
