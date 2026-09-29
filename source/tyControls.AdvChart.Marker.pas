unit tyControls.AdvChart.Marker;
{$mode objfpc}{$H+}
{ SERIES MARKERS -- markPoint, markLine and markArea -- as numbers: which
  items survive, where their ends and corners land, and what each one reads
  from the option chain. Nothing here paints.

  Upstream's pieces, transcribed: component/marker/markerHelper.ts
  (dataTransform, getAxisInfo, markerTypeCalculatorWithExtent, numCalculate,
  dataFilter, zoneFilter, the dim value getter), MarkPointView
  (updateMarkerLayout), MarkLineView (markLineTransform, markLineFilter,
  updateSingleMarkerEndLayout), MarkAreaView (markAreaTransform,
  markAreaFilter, getSingleMarkerEndPoint, the allClipped test),
  Cartesian2D.clampData / containData / containZone, and
  BaseBarSeries.getMarkerPosition (both branches).

  THE MODEL CHAIN. A series' marker option is a model whose parent is the
  ONE top-level marker component of its kind -- upstream's preprocessor makes
  `option.markLine` exist whenever any series has one -- and that component's
  option is merged with the marker defaults, the author's keys winning. So a
  key resolves item -> series.markX -> top-level markX -> default, and a
  top-level `markLine: {z: -100}` reaches every series' markLine.

  NOT MUTATING THE OPTION. Upstream's transform writes into the option it
  was given (a `coord` array for an item placed in pixels, numbers over the
  'min' / 'max' strings of a user coord), so a second render sees numbers.
  The port reads the option and keeps its answers here.

  AN ELEMENT UPSTREAM CANNOT HANDLE -- a 1D markLine item with no type and no
  xAxis / yAxis, a markArea element that is not a pair, anything that is not
  an object -- throws out of upstream's render. The port cannot mimic a crash;
  such an element is skipped: not survived, no data index. }
interface

uses SysUtils, Math, fpjson,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord;

type
  TTyMarkerKind = (mkPoint, mkLine, mkArea);

  { A value of the option / transform world, as JavaScript sees it. Undefined
    and null are kept apart because a merge copies a key that is PRESENT, null
    or not; everything that reads a value treats the two alike. }
  TTyMkValKind = (mvkUndef, mvkNull, mvkNum, mvkStr, mvkOther);
  TTyMkVal = record
    Kind: TTyMkValKind;
    { mvkNum; for mvkOther a boolean's 0 / 1, anything else NaN }
    Num: Double;
    Str: string;
  end;
  TTyMkPair = array[0..1] of TTyMkVal;

  { What the chart knows about one cartesian series. Pixels are DEVICE
    pixels: the grid is laid out in them. Scale = PPI / 96 turns the
    option's CSS pixels (x / y) into them, OriginX / OriginY is the control
    rect's corner, Width / Height its size in CSS pixels (api.getWidth). }
  TTyMkContext = record
    Store: TTyDataStore;
    Cart: TTyCartesian2D;
    XAxis, YAxis: TTyAxis;
    { seriesModel.getBaseAxis().dim, and whether the COORDINATE SYSTEM's
      base axis is horizontal (the bar offset's direction) }
    BaseDim: string;
    CsBaseHorizontal: Boolean;
    { the stacked value column and its stack result, or -1 }
    StackedCol, StackResultCol: Integer;
    { bar / pictorialBar: getMarkerPosition, with the series' bar offset and
      width in its band }
    IsBar: Boolean;
    BarOffset, BarSize: Double;
    { axisTick.alignWithLabel of the x and the y axis }
    AlignWithLabel: array[0..1] of Boolean;
    SeriesSilent: Boolean;
    Scale, OriginX, OriginY, Width, Height: Double;
  end;

  { One end of a marker: a markPoint item, or either end of a markLine. }
  TTyMkEnd = record
    { the element's own option object; nil for the far end of a 1D line,
      which upstream builds as a bare {coord} }
    Src: TJSONObject;
    { item.coord after the transform, and the values the layout reads from
      them (parseDataValue by the coordinate's type: a category keeps what
      was written) }
    Coord, Values: TTyMkPair;
    Value, Name: TTyMkVal;
    Point: TTyPointF;
  end;

  TTyMkPoint = record
    Index, DataIndex: Integer;
    Survived: Boolean;
    E: TTyMkEnd;
  end;

  TTyMkLine = record
    Index, DataIndex: Integer;
    Survived: Boolean;
    From, To_: TTyMkEnd;
    { the merged line item: {type, valueIndex, value} for a 1D line, then the
      start item's keys, then the end item's, none overwriting }
    LineType, LineValue, LineName: TTyMkVal;
  end;

  TTyMkArea = record
    Index, DataIndex: Integer;
    Survived: Boolean;
    LtSrc, RbSrc: TJSONObject;
    { the corner coords after the transform and the +-Infinity fill }
    Lt, Rb: TTyMkPair;
    { x0, y0, x1, y1 as stored }
    Values: array[0..3] of TTyMkVal;
    { the merged item's: lt's when it has one, else rb's }
    Name: TTyMkVal;
    { [x0,y0], [x1,y0], [x1,y1], [x0,y1] }
    Points: array[0..3] of TTyPointF;
    { no overlap with the scales' extents: no polygon, no label }
    AllClipped: Boolean;
  end;

  TTyMkBlock = record
    { False: the series has no such marker (no `data`), or it is not drawn }
    Present: Boolean;
    Kind: TTyMarkerKind;
    { series.markX and the top-level markX (nil when there is none) }
    Own, Top: TJSONObject;
    { the series' grid axes, not owned: valid until the next rebuild }
    XAxis, YAxis: TTyAxis;
    Z, ZLevel: Double;
    Silent: Boolean;
    { survivors }
    Count: Integer;
    Points: array of TTyMkPoint;
    Lines: array of TTyMkLine;
    Areas: array of TTyMkArea;
  end;

  TTyMkSeries = record
    SeriesIndex: Integer;
    Blocks: array[TTyMarkerKind] of TTyMkBlock;
  end;
  TTyMkSeriesArray = array of TTyMkSeries;

const
  TyMarkerKey: array[TTyMarkerKind] of string = ('markPoint', 'markLine', 'markArea');

{ ---- values ---- }
function TyMkOf(A: TJSONData): TTyMkVal;
function TyMkNum(A: Double): TTyMkVal;
function TyMkUndef: TTyMkVal;
{ JavaScript's Number(v) / parseFloat(v) }
function TyMkJsNumber(const A: TTyMkVal): Double;
function TyMkJsParseFloat(const A: TTyMkVal): Double;
{ util/number parsePositionOption: presets, 'N%' of ABase, parseFloat, +v;
  null NaN }
function TyMkParsePercent(A: TJSONData; ABase: Double): Double;

{ ---- the model chain ---- }
{ the marker defaults (MarkPointModel / MarkLineModel / MarkAreaModel
  defaultOption) }
function TyMkDefaults(AKind: TTyMarkerKind): TJSONObject;
{ Model.get / getShallow: AItem -> AOwn -> the master (ATop merged with the
  defaults). AOwnOnly is get(key, true). nil for null or missing. }
function TyMkChainGet(AItem, AOwn, ATop: TJSONObject; AKind: TTyMarkerKind;
  const AKey: string; AOwnOnly: Boolean = False): TJSONData;
{ the item visuals: a markPoint's symbol / symbolSize / symbolRotate /
  symbolOffset / symbolKeepAspect (chain), a markLine end's (own only, then
  the series pair element; symbolSize and symbolKeepAspect through the chain) }
function TyMkPointVisual(const ABlock: TTyMkBlock; AItem: Integer;
  const AKey: string): TJSONData;
function TyMkLineVisual(const ABlock: TTyMkBlock; AItem: Integer;
  AIsFrom: Boolean; const AKey: string): TJSONData;

{ ---- statistics ---- }
{ numCalculate over the store's current view: 'average', 'median' (with
  DataStore.getMedian's count() quirk), 'min', 'max' }
function TyMkNumCalculate(AStore: TTyDataStore; ACol: Integer;
  const AType: string): Double;
{ Series.indicesOfNearest: the view rows whose value in ACol lies nearest
  AValue along AAxis, in the axis' LOCAL coordinates; ties to the side at or
  before the target, equal differences accumulating }
function TyMkNearestRows(AStore: TTyDataStore; ACol: Integer; AAxis: TTyAxis;
  AValue, AMaxDist: Double): TTyIntegerArray;

{ ---- the solve ---- }
{ One kind for one series. ASeries is the series' option object, ATop the
  first top-level component of the kind (or nil). }
function TyMarkerSolve(AKind: TTyMarkerKind; ASeries, ATop: TJSONObject;
  const ACtx: TTyMkContext): TTyMkBlock;

implementation

var
  GDefaults: array[TTyMarkerKind] of TJSONObject;

{ ============================ values ============================ }

function TyMkUndef: TTyMkVal;
begin
  Result.Kind := mvkUndef;
  Result.Num := NaN;
  Result.Str := '';
end;

function TyMkNum(A: Double): TTyMkVal;
begin
  Result.Kind := mvkNum;
  Result.Num := A;
  Result.Str := '';
end;

function TyMkOf(A: TJSONData): TTyMkVal;
begin
  Result := TyMkUndef;
  if A = nil then Exit;
  case A.JSONType of
    jtNull: Result.Kind := mvkNull;
    jtNumber:
      begin
        Result.Kind := mvkNum;
        Result.Num := A.AsFloat;
      end;
    jtString:
      begin
        Result.Kind := mvkStr;
        Result.Str := A.AsString;
      end;
    jtBoolean:
      begin
        Result.Kind := mvkOther;
        if A.AsBoolean then Result.Num := 1 else Result.Num := 0;
      end;
  else
    Result.Kind := mvkOther;
  end;
end;

function Nullish(const A: TTyMkVal): Boolean; inline;
begin
  Result := A.Kind in [mvkUndef, mvkNull];
end;

function JNull(A: TJSONData): Boolean; inline;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

function TyMkJsNumber(const A: TTyMkVal): Double;
begin
  case A.Kind of
    mvkUndef: Result := NaN;
    mvkNull: Result := 0;
    mvkNum: Result := A.Num;
    mvkStr: Result := TyJsToNumber(A.Str);
  else
    Result := A.Num;
  end;
end;

function TyMkJsParseFloat(const A: TTyMkVal): Double;
begin
  case A.Kind of
    mvkNum: Result := A.Num;
    mvkStr: Result := TyJsParseFloat(A.Str);
  else
    Result := NaN;
  end;
end;

{ !isNaN(v) && !isFinite(v) }
function JsIsInfinity(const A: TTyMkVal): Boolean;
var n: Double;
begin
  n := TyMkJsNumber(A);
  Result := (not IsNan(n)) and IsInfinite(n);
end;

{ === }
function StrictEq(const A, B: TTyMkVal): Boolean;
begin
  if A.Kind <> B.Kind then Exit(False);
  case A.Kind of
    mvkUndef, mvkNull: Result := True;
    mvkNum: Result := (not IsNan(A.Num)) and (not IsNan(B.Num)) and (A.Num = B.Num);
    mvkStr: Result := A.Str = B.Str;
  else
    Result := False;
  end;
end;

{ JavaScript's relational operators: false whenever a side is NaN }
function JsLt(A, B: Double): Boolean; inline;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A < B);
end;

function JsGt(A, B: Double): Boolean; inline;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A > B);
end;

function IsNegZero(A: Double): Boolean;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := q = QWord($8000000000000000);
end;

{ Math.max / Math.min: NaN wins, and +0 beats -0 }
function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Exit(A);
  if B > A then Exit(B);
  if IsNegZero(A) then Exit(B);
  Result := A;
end;

function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Exit(A);
  if B < A then Exit(B);
  if (A = 0) and not IsNegZero(A) then Exit(B);
  Result := A;
end;

function TyMkParsePercent(A: TJSONData; ABase: Double): Double;
var
  s, t: string;
begin
  if JNull(A) then Exit(NaN);
  case A.JSONType of
    jtString:
      begin
        s := A.AsString;
        if (s = 'center') or (s = 'middle') then s := '50%'
        else if (s = 'left') or (s = 'top') then s := '0%'
        else if (s = 'right') or (s = 'bottom') then s := '100%';
        t := TyJsTrim(s);
        if (t <> '') and (t[Length(t)] = '%') then
          Result := TyJsParseFloat(s) / 100 * ABase
        else
          Result := TyJsParseFloat(s);
      end;
    jtNumber: Result := A.AsFloat;
    jtBoolean: if A.AsBoolean then Result := 1 else Result := 0;
  else
    Result := NaN;
  end;
end;

{ zrUtil truthiness of an option value }
function Truthy(A: TJSONData): Boolean;
begin
  if JNull(A) then Exit(False);
  case A.JSONType of
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (not IsNan(A.AsFloat)) and (A.AsFloat <> 0);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

function JsNumberOf(A: TJSONData): Double;
begin
  Result := TyMkJsNumber(TyMkOf(A));
end;

{ ============================ the chain ============================ }

function TyMkDefaults(AKind: TTyMarkerKind): TJSONObject;
begin
  Result := GDefaults[AKind];
end;

function TyMkChainGet(AItem, AOwn, ATop: TJSONObject; AKind: TTyMarkerKind;
  const AKey: string; AOwnOnly: Boolean): TJSONData;
begin
  Result := nil;
  if AItem <> nil then Result := AItem.Find(AKey);
  if AOwnOnly then
  begin
    if JNull(Result) then Result := nil;
    Exit;
  end;
  if not JNull(Result) then Exit;
  Result := nil;
  if AOwn <> nil then Result := AOwn.Find(AKey);
  if not JNull(Result) then Exit;
  { the master: its own option merged with the defaults, never overwriting,
    so a key it HAS -- null or not -- keeps the default out }
  if (ATop <> nil) and (ATop.IndexOfName(AKey) >= 0) then
    Result := ATop.Find(AKey)
  else
    Result := GDefaults[AKind].Find(AKey);
  if JNull(Result) then Result := nil;
end;

function TyMkPointVisual(const ABlock: TTyMkBlock; AItem: Integer;
  const AKey: string): TJSONData;
begin
  Result := TyMkChainGet(ABlock.Points[AItem].E.Src, ABlock.Own, ABlock.Top,
    mkPoint, AKey, False);
end;

function TyMkLineVisual(const ABlock: TTyMkBlock; AItem: Integer;
  AIsFrom: Boolean; const AKey: string): TJSONData;
var
  src: TJSONObject;
  pair: TJSONData;
  k: Integer;
begin
  if AIsFrom then src := ABlock.Lines[AItem].From.Src
  else src := ABlock.Lines[AItem].To_.Src;
  if AKey = 'symbolKeepAspect' then
    Exit(TyMkChainGet(src, ABlock.Own, ABlock.Top, mkLine, AKey, False));
  { symbolSize WITH the parent (upstream's own comment: "when 2d array is
    supported, it should ignore parent") -- so the default [8, 16] reaches
    both ends whole }
  Result := TyMkChainGet(src, ABlock.Own, ABlock.Top, mkLine, AKey,
    AKey <> 'symbolSize');
  if Result <> nil then Exit;
  { the series-level option normalised to a pair }
  pair := TyMkChainGet(nil, ABlock.Own, ABlock.Top, mkLine, AKey, False);
  if pair = nil then Exit(nil);
  if pair.JSONType <> jtArray then Exit(pair);
  if AIsFrom then k := 0 else k := 1;
  if k >= pair.Count then Exit(nil);
  Result := pair.Items[k];
  if JNull(Result) then Result := nil;
end;

{ ============================ statistics ============================ }

function TyMkNumCalculate(AStore: TTyDataStore; ACol: Integer;
  const AType: string): Double;
var
  i, n, cnt, j, len: Integer;
  v, sum, lo, hi: Double;
  arr: array of Double;
begin
  if (AStore = nil) or (ACol < 0) or (ACol >= AStore.DimCount) then
  begin
    { a dimension that is not there reads NaN on every row }
    if AType = 'median' then
    begin
      if (AStore = nil) or (AStore.Count = 0) then Exit(0);
      Exit(NaN);
    end;
    if AType = 'min' then Exit(Infinity);
    if AType = 'max' then Exit(NegInfinity);
    Exit(NaN);
  end;
  n := AStore.Count;
  if AType = 'average' then
  begin
    sum := 0;
    cnt := 0;
    for i := 0 to n - 1 do
    begin
      v := AStore.Get(ACol, i);
      if IsNan(v) then Continue;
      sum := sum + v;
      Inc(cnt);
    end;
    if cnt = 0 then Exit(NaN);
    Exit(sum / cnt);
  end;
  if AType = 'median' then
  begin
    { DataStore.getMedian: the values that are numbers, sorted, indexed by
      count() -- the NaN rows included, so a gap shifts the median and enough
      gaps read past the array (undefined, and NaN out of the arithmetic) }
    arr := nil;
    SetLength(arr, n);
    cnt := 0;
    for i := 0 to n - 1 do
    begin
      v := AStore.Get(ACol, i);
      if IsNan(v) then Continue;
      { stable insertion, ascending }
      j := cnt;
      while (j > 0) and (arr[j - 1] > v) do
      begin
        arr[j] := arr[j - 1];
        Dec(j);
      end;
      arr[j] := v;
      Inc(cnt);
    end;
    len := n;
    if len = 0 then Exit(0);
    if Odd(len) then
    begin
      j := (len - 1) div 2;
      if j < cnt then Exit(arr[j]);
      Exit(NaN);
    end;
    j := len div 2;
    if j < cnt then Exit((arr[j] + arr[j - 1]) / 2);
    Exit(NaN);
  end;
  { getDataExtent: min and max over the view; an empty one is [Infinity,
    -Infinity] }
  lo := Infinity;
  hi := NegInfinity;
  for i := 0 to n - 1 do
  begin
    v := AStore.Get(ACol, i);
    if IsNan(v) then Continue;
    if v < lo then lo := v;
    if v > hi then hi := v;
  end;
  if AType = 'max' then Result := hi else Result := lo;
end;

function TyMkNearestRows(AStore: TTyDataStore; ACol: Integer; AAxis: TTyAxis;
  AValue, AMaxDist: Double): TTyIntegerArray;
var
  i, n: Integer;
  target, v, coord, diff, dist, minDist, minDiff: Double;
begin
  Result := nil;
  if (AStore = nil) or (AAxis = nil) or (ACol < 0) or (ACol >= AStore.DimCount) then
    Exit;
  { axis.dataToCoord: LOCAL, not global -- a tie between two rows is decided
    by the local difference, and adding the grid's offset to both sides can
    move the last bit of one of them }
  target := AAxis.DataToLocal(AValue);
  if IsNan(target) then Exit;
  minDist := Infinity;
  minDiff := -1;
  n := 0;
  SetLength(Result, AStore.Count);
  for i := 0 to AStore.Count - 1 do
  begin
    v := AStore.Get(ACol, i);
    if IsNan(v) then Continue;
    coord := AAxis.DataToLocal(v);
    if IsNan(coord) then Continue;
    diff := target - coord;
    if IsNan(diff) then Continue;
    dist := Abs(diff);
    if dist > AMaxDist then Continue;
    { at the same distance the row at or before the target wins; rows with
      the same signed difference accumulate }
    if (dist < minDist) or ((dist = minDist) and (diff >= 0) and (minDiff < 0)) then
    begin
      minDist := dist;
      minDiff := diff;
      n := 0;
    end;
    if diff = minDiff then
    begin
      Result[n] := i;
      Inc(n);
    end;
  end;
  SetLength(Result, n);
end;

{ ============================ the solver ============================ }

type
  { an item in flight through the transform }
  TMkItem = record
    Src: TJSONObject;
    { item.coord != null / isArray(item.coord) }
    CoordGiven, CoordArr: Boolean;
    Coord: TTyMkPair;
    Value, Name: TTyMkVal;
    { item.type when it is a string }
    TypeStr: string;
    X, Y: TTyMkVal;
  end;

  TMkAxisInfo = record
    Ok: Boolean;
    BaseAxis, ValueAxis: TTyAxis;
    BaseCol, ValueCol: Integer;
  end;

  TMkSolver = class
  private
    C: TTyMkContext;
    FKind: TTyMarkerKind;
    FOwn, FTop: TJSONObject;
    function AxisOf(const ADim: string): TTyAxis;
    function OtherAxis(AAxis: TTyAxis): TTyAxis;
    function CoordOfCol(ACol: Integer): string;
    function MapDim(const ACoordDim: string): Integer;
    function GetAt(ACol, ARow: Integer): Double;
    function IsCalc(const AType: string): Boolean;
    function ItemOf(AObj: TJSONObject): TMkItem;
    function HasXAndY(const AIt: TMkItem): Boolean;
    function HasXOrY(const AIt: TMkItem): Boolean;
    function AxisInfo(const AIt: TMkItem): TMkAxisInfo;
    procedure CalcWithExtent(const AType: string; const AInfo: TMkAxisInfo;
      out ACoord: TTyMkPair; out AValue: Double);
    procedure DataTransform(var AIt: TMkItem);
    function Parse(AAxis: TTyAxis; const AV: TTyMkVal): Double;
    function DimTypeOf(AIdx: Integer): TTyAxisType;
    function Stored(const AV: TTyMkVal; AType: TTyAxisType): TTyMkVal;
    function ContainAxis(AAxis: TTyAxis; const AV: TTyMkVal): Boolean;
    function ContainData(const ACoord: TTyMkPair): Boolean;
    function DataFilter(const AIt: TMkItem): Boolean;
    function DataToPoint(const A0, A1: TTyMkVal; AClamp: Boolean): TTyPointF;
    procedure ClampData(const A0, A1: TTyMkVal; out AX, AY: Double);
    function MarkerPosition(const A0, A1: TTyMkVal; ADims: Integer;
      AStartingAtTick: Boolean): TTyPointF;
    procedure TickSnap(AIdx: Integer; AAxis: TTyAxis; AClamped: Double;
      AIsEnd: Boolean; var APoint: TTyPointF);
    procedure InfinityToExtent(var APoint: TTyPointF; const AX, AY: TTyMkVal;
      AXFirst, AYFirst: Boolean);
    function PxOf(A: TJSONData; AIsX, ARelToCoord: Boolean): Double;
    procedure ReadBlock(var ABlock: TTyMkBlock);
    function EndOf(const AIt: TMkItem): TTyMkEnd;
    procedure SolvePoints(AData: TJSONArray; var ABlock: TTyMkBlock);
    procedure SolveLines(AData: TJSONArray; var ABlock: TTyMkBlock);
    procedure SolveAreas(AData: TJSONArray; var ABlock: TTyMkBlock);
  end;

function TMkSolver.AxisOf(const ADim: string): TTyAxis;
begin
  if ADim = 'x' then Result := C.XAxis
  else if ADim = 'y' then Result := C.YAxis
  else Result := nil;
end;

function TMkSolver.OtherAxis(AAxis: TTyAxis): TTyAxis;
begin
  if AAxis = C.XAxis then Result := C.YAxis
  else if AAxis = C.YAxis then Result := C.XAxis
  else Result := nil;
end;

function TMkSolver.CoordOfCol(ACol: Integer): string;
begin
  if (ACol < 0) or (ACol >= C.Store.DimCount) then Exit('');
  Result := C.Store.DimCoord(ACol);
  if Result = '' then Result := C.Store.DimName(ACol);
end;

{ data.mapDimension(coordDim): the first column on that coordinate }
function TMkSolver.MapDim(const ACoordDim: string): Integer;
var i: Integer;
begin
  for i := 0 to C.Store.DimCount - 1 do
    if CoordOfCol(i) = ACoordDim then Exit(i);
  Result := -1;
end;

{ data.get: NaN for a row or a dimension that is not there }
function TMkSolver.GetAt(ACol, ARow: Integer): Double;
begin
  if (ACol < 0) or (ACol >= C.Store.DimCount) or (ARow < 0)
    or (ARow >= C.Store.Count) then Exit(NaN);
  Result := C.Store.Get(ACol, ARow);
end;

function TMkSolver.IsCalc(const AType: string): Boolean;
begin
  Result := (AType = 'min') or (AType = 'max') or (AType = 'average')
    or (AType = 'median');
end;

function TMkSolver.ItemOf(AObj: TJSONObject): TMkItem;
var
  d: TJSONData;
  a: TJSONArray;
  i: Integer;
begin
  Result := Default(TMkItem);
  Result.Src := AObj;
  Result.Coord[0] := TyMkUndef;
  Result.Coord[1] := TyMkUndef;
  Result.Value := TyMkUndef;
  Result.Name := TyMkUndef;
  Result.X := TyMkUndef;
  Result.Y := TyMkUndef;
  if AObj = nil then Exit;
  Result.X := TyMkOf(AObj.Find('x'));
  Result.Y := TyMkOf(AObj.Find('y'));
  Result.Value := TyMkOf(AObj.Find('value'));
  Result.Name := TyMkOf(AObj.Find('name'));
  d := AObj.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then Result.TypeStr := d.AsString;
  d := AObj.Find('coord');
  Result.CoordGiven := not JNull(d);
  Result.CoordArr := (d <> nil) and (d.JSONType = jtArray);
  if Result.CoordArr then
  begin
    a := TJSONArray(d);
    for i := 0 to 1 do
      if i < a.Count then Result.Coord[i] := TyMkOf(a.Items[i]);
  end;
end;

function TMkSolver.HasXAndY(const AIt: TMkItem): Boolean;
begin
  Result := (not IsNan(TyMkJsParseFloat(AIt.X)))
    and (not IsNan(TyMkJsParseFloat(AIt.Y)));
end;

function TMkSolver.HasXOrY(const AIt: TMkItem): Boolean;
begin
  Result := not (IsNan(TyMkJsParseFloat(AIt.X))
    and IsNan(TyMkJsParseFloat(AIt.Y)));
end;

{ getAxisInfo }
function TMkSolver.AxisInfo(const AIt: TMkItem): TMkAxisInfo;
var
  vi, vd: TJSONData;
  col: Integer;
  n: Double;
begin
  Result := Default(TMkAxisInfo);
  Result.BaseCol := -1;
  Result.ValueCol := -1;
  vi := nil;
  vd := nil;
  if AIt.Src <> nil then
  begin
    vi := AIt.Src.Find('valueIndex');
    vd := AIt.Src.Find('valueDim');
  end;
  if (not JNull(vi)) or (not JNull(vd)) then
  begin
    col := -1;
    if not JNull(vi) then
    begin
      { data.getDimension(valueIndex) }
      n := JsNumberOf(vi);
      if (not IsNan(n)) and (n >= 0) and (n < C.Store.DimCount) and (Frac(n) = 0) then
        col := Trunc(n);
    end
    else if vd.JSONType = jtString then
      col := C.Store.DimIndexOf(vd.AsString);
    Result.ValueCol := col;
    Result.ValueAxis := AxisOf(CoordOfCol(col));
    Result.BaseAxis := OtherAxis(Result.ValueAxis);
    if Result.BaseAxis <> nil then Result.BaseCol := MapDim(Result.BaseAxis.Dim);
  end
  else
  begin
    Result.BaseAxis := AxisOf(C.BaseDim);
    Result.ValueAxis := OtherAxis(Result.BaseAxis);
    if Result.BaseAxis <> nil then Result.BaseCol := MapDim(Result.BaseAxis.Dim);
    if Result.ValueAxis <> nil then Result.ValueCol := MapDim(Result.ValueAxis.Dim);
  end;
  Result.Ok := (Result.BaseAxis <> nil) and (Result.ValueAxis <> nil);
end;

{ markerTypeCalculatorWithExtent: the statistic, then the datum nearest it --
  every type lands ON a datum. Stacked, the search and the position use the
  stack result and the value is the raw datum; the position is then rounded
  to the RAW datum's precision, which can move it off the stacked point. }
procedure TMkSolver.CalcWithExtent(const AType: string; const AInfo: TMkAxisInfo;
  out ACoord: TTyMkPair; out AValue: Double);
var
  calcCol, row, other, target, p: Integer;
  stat, t: Double;
  rows: TTyIntegerArray;
begin
  if (C.StackedCol >= 0) and (AInfo.ValueCol = C.StackedCol) then
    calcCol := C.StackResultCol
  else
    calcCol := AInfo.ValueCol;
  stat := TyMkNumCalculate(C.Store, calcCol, AType);
  rows := TyMkNearestRows(C.Store, calcCol, AInfo.ValueAxis, stat, Infinity);
  if Length(rows) > 0 then row := rows[0] else row := -1;
  if AInfo.BaseAxis = C.XAxis then
  begin
    other := 0;
    target := 1;
  end
  else
  begin
    other := 1;
    target := 0;
  end;
  ACoord[other] := TyMkNum(GetAt(AInfo.BaseCol, row));
  t := GetAt(calcCol, row);
  AValue := GetAt(AInfo.ValueCol, row);
  p := TyGetPrecision(AValue);
  if p > 20 then p := 20;
  if p >= 0 then t := TyJsToFixed(t, p);
  ACoord[target] := TyMkNum(t);
end;

procedure TMkSolver.DataTransform(var AIt: TMkItem);
var
  info: TMkAxisInfo;
  coord: TTyMkPair;
  v: Double;
  i: Integer;
  ax: TTyAxis;
  d: TJSONData;
begin
  if (not HasXAndY(AIt)) and (not AIt.CoordArr) then
  begin
    info := AxisInfo(AIt);
    if IsCalc(AIt.TypeStr) and info.Ok then
    begin
      CalcWithExtent(AIt.TypeStr, info, coord, v);
      AIt.Coord := coord;
      { "Force to use the value of calculated value" }
      AIt.Value := TyMkNum(v);
    end
    else
    begin
      AIt.Coord[0] := TyMkUndef;
      AIt.Coord[1] := TyMkUndef;
      if AIt.Src <> nil then
      begin
        d := AIt.Src.Find('xAxis');
        if JNull(d) then d := AIt.Src.Find('radiusAxis');
        AIt.Coord[0] := TyMkOf(d);
        d := AIt.Src.Find('yAxis');
        if JNull(d) then d := AIt.Src.Find('angleAxis');
        AIt.Coord[1] := TyMkOf(d);
      end;
    end;
    AIt.CoordGiven := True;
    AIt.CoordArr := True;
  end;
  if not AIt.CoordGiven then
  begin
    { x and y both in pixels }
    AIt.Coord[0] := TyMkUndef;
    AIt.Coord[1] := TyMkUndef;
    AIt.CoordGiven := True;
    AIt.CoordArr := True;
    ax := AxisOf(C.BaseDim);
    if (ax <> nil) and IsCalc(AIt.TypeStr) and (OtherAxis(ax) <> nil) then
      AIt.Value := TyMkNum(TyMkNumCalculate(C.Store, MapDim(OtherAxis(ax).Dim),
        AIt.TypeStr));
  end
  else if AIt.CoordArr then
  begin
    { a statistic written into the coord: numCalculate over that dimension,
      not stack-aware, not rounded, not the nearest datum }
    for i := 0 to 1 do
      if (AIt.Coord[i].Kind = mvkStr) and IsCalc(AIt.Coord[i].Str) then
        if i = 0 then
          AIt.Coord[i] := TyMkNum(TyMkNumCalculate(C.Store, MapDim('x'), AIt.Coord[i].Str))
        else
          AIt.Coord[i] := TyMkNum(TyMkNumCalculate(C.Store, MapDim('y'), AIt.Coord[i].Str));
  end;
end;

{ scale.parse }
function TMkSolver.Parse(AAxis: TTyAxis; const AV: TTyMkVal): Double;
var ms: Double;
begin
  if AAxis = nil then Exit(NaN);
  case AAxis.AxisType of
    atCategory:
      begin
        { OrdinalScale.parse: a name is its ordinal, a number rounded }
        if Nullish(AV) then Exit(NaN);
        if AV.Kind = mvkStr then
        begin
          if AAxis.Categories = nil then Exit(NaN);
          Result := AAxis.Categories.GetOrdinal(AV.Str);
          if Result < 0 then Result := NaN;
          Exit;
        end;
        Result := TyJsRound(TyMkJsNumber(AV));
      end;
    atTime:
      begin
        { TimeScale.parse: a number rounded, anything else parseDate }
        if AV.Kind = mvkNum then Exit(TyJsRound(AV.Num));
        if AV.Kind = mvkStr then
        begin
          if TyParseDateMs(AV.Str, ms, False) then Exit(ms);
          Exit(NaN);
        end;
        if Nullish(AV) then Exit(NaN);
        Result := TyJsRound(AV.Num);
      end;
  else
    { IntervalScale.parse (the log scale borrows it) }
    if Nullish(AV) or ((AV.Kind = mvkStr) and (AV.Str = '')) then Exit(NaN);
    Result := TyMkJsNumber(AV);
  end;
end;

function TMkSolver.DimTypeOf(AIdx: Integer): TTyAxisType;
var ax: TTyAxis;
begin
  if AIdx = 0 then ax := C.XAxis else ax := C.YAxis;
  if ax = nil then Exit(atValue);
  Result := ax.AxisType;
end;

{ parseDataValue by the coordinate dimension's type, then the store's chunk:
  a category keeps what was written (the marker dims carry no ordinal meta),
  a time is parseDate'd, anything else Number()'d }
function TMkSolver.Stored(const AV: TTyMkVal; AType: TTyAxisType): TTyMkVal;
var
  v: TTyMkVal;
  ms: Double;
begin
  if AType = atCategory then Exit(AV);
  v := AV;
  if (AType = atTime) and (v.Kind <> mvkNum) and (not Nullish(v))
    and not ((v.Kind = mvkStr) and (v.Str = '-')) then
  begin
    if v.Kind = mvkStr then
    begin
      if not TyParseDateMs(v.Str, ms, False) then ms := NaN;
    end
    else
      ms := TyJsRound(v.Num);
    v := TyMkNum(ms);
  end;
  if Nullish(v) or ((v.Kind = mvkStr) and (v.Str = '')) then Exit(TyMkNum(NaN));
  Result := TyMkNum(TyMkJsNumber(v));
end;

{ axis.containData: scale.contain(scale.parse(v)) -- the MAPPING extent }
function TMkSolver.ContainAxis(AAxis: TTyAxis; const AV: TTyMkVal): Boolean;
var p: Double;
begin
  if AAxis = nil then Exit(False);
  p := Parse(AAxis, AV);
  if IsNan(p) then Exit(False);
  Result := AAxis.Scale.Contain(p);
end;

function TMkSolver.ContainData(const ACoord: TTyMkPair): Boolean;
begin
  Result := ContainAxis(C.XAxis, ACoord[0]) and ContainAxis(C.YAxis, ACoord[1]);
end;

{ dataFilter: an item placed by x or y is never filtered }
function TMkSolver.DataFilter(const AIt: TMkItem): Boolean;
begin
  if HasXOrY(AIt) then Exit(True);
  Result := ContainData(AIt.Coord);
end;

{ Cartesian2D.dataToPoint: the matrix when both values are finite numbers
  and there is one, else axis by axis through the scale's parse }
function TMkSolver.DataToPoint(const A0, A1: TTyMkVal; AClamp: Boolean): TTyPointF;
var
  m: TTyMat2D;
  x, y: Double;
begin
  if C.Cart.Transform(m) and (not Nullish(A0)) and (not Nullish(A1)) then
  begin
    x := TyMkJsNumber(A0);
    y := TyMkJsNumber(A1);
    if not (IsNan(x) or IsInfinite(x) or IsNan(y) or IsInfinite(y)) then
      Exit(C.Cart.DataToPointClamped([x, y], AClamp));
  end;
  Result.X := C.XAxis.DataToCoord(Parse(C.XAxis, A0), AClamp);
  Result.Y := C.YAxis.DataToCoord(Parse(C.YAxis, A1), AClamp);
end;

{ Cartesian2D.clampData: parse, then into the EFFECTIVE extent }
procedure TMkSolver.ClampData(const A0, A1: TTyMkVal; out AX, AY: Double);
var e: TTyRange;
begin
  e := C.XAxis.Scale.GetExtent;
  AX := JMin(JMax(JMin(e.Start, e.Stop), Parse(C.XAxis, A0)), JMax(e.Start, e.Stop));
  e := C.YAxis.Scale.GetExtent;
  AY := JMin(JMax(JMin(e.Start, e.Stop), Parse(C.YAxis, A1)), JMax(e.Start, e.Stop));
end;

{ the corner of a bar markArea on a category axis: onto the tick coords, the
  far corner one tick on unless the ticks align with the labels }
procedure TMkSolver.TickSnap(AIdx: Integer; AAxis: TTyAxis; AClamped: Double;
  AIsEnd: Boolean; var APoint: TTyPointF);
var
  ticks: TTyScaleTickArray;
  coords, values: TTyDoubleArray;
  i, n: Integer;
  bw, targetId, tv, tc, step, leftCoord, coord, s0, s1: Double;
  hasLeft, hasCoord, align: Boolean;
  e: TTyRange;
begin
  align := C.AlignWithLabel[AIdx];
  { axis.getTicksCoords, local: the majors }
  ticks := TyDrawnTicks(AAxis.Scale);
  n := 0;
  for i := 0 to High(ticks) do
    if ticks[i].Level = 0 then
    begin
      ticks[n] := ticks[i];
      Inc(n);
    end;
  SetLength(ticks, n);
  SetLength(coords, n);
  SetLength(values, n);
  for i := 0 to n - 1 do
  begin
    coords[i] := AAxis.DataToLocal(ticks[i].Value);
    values[i] := ticks[i].Value;
  end;
  if AAxis.OnBand and (not align) and (n > 0) then
  begin
    bw := AAxis.BandWidth;
    if (bw <> 0) and not IsNan(bw) then
    begin
      for i := 0 to n - 1 do coords[i] := coords[i] - bw / 2;
      tc := coords[n - 1];
      if ticks[n - 1].OffInterval then Dec(n);
      e := AAxis.Scale.GetExtent;
      SetLength(coords, n + 1);
      SetLength(values, n + 1);
      coords[n] := tc + bw;
      values[n] := e.Stop + 1;
      Inc(n);
    end;
  end;
  targetId := AClamped;
  if AIsEnd and not align then targetId := targetId + 1;
  if n < 2 then Exit;
  if n = 2 then
  begin
    { one category: both ticks at one coord; the axis' own ends instead }
    AAxis.LocalExtent(s0, s1);
    if AIsEnd then coord := s1 else coord := s0;
    if AIdx = 0 then APoint.X := AAxis.ToGlobal(coord)
    else APoint.Y := AAxis.ToGlobal(coord);
    Exit;
  end;
  hasLeft := False;
  hasCoord := False;
  leftCoord := 0;
  coord := NaN;
  step := 1;
  for i := 0 to n - 1 do
  begin
    tc := coords[i];
    { the last one carries no tick value of its own }
    if i = n - 1 then tv := values[i - 1] + step else tv := values[i];
    if (not IsNan(tv)) and (not IsNan(targetId)) and (tv = targetId) then
    begin
      coord := tc;
      hasCoord := True;
      Break;
    end
    else if JsLt(tv, targetId) then
    begin
      leftCoord := tc;
      hasLeft := True;
    end
    else if hasLeft and JsGt(tv, targetId) then
    begin
      coord := (tc + leftCoord) / 2;
      hasCoord := True;
      Break;
    end;
    if i = 1 then step := tv - values[0];
  end;
  if not hasCoord then
  begin
    { `if (!leftCoord)`: unset, 0 or NaN all read as "left of every tick" --
      NaN then falls through both branches }
    if (not hasLeft) or (leftCoord = 0) then coord := coords[0]
    else if IsNan(leftCoord) then coord := NaN
    else coord := coords[n - 1];
  end;
  if AIdx = 0 then APoint.X := AAxis.ToGlobal(coord)
  else APoint.Y := AAxis.ToGlobal(coord);
end;

{ BaseBarSeries.getMarkerPosition. ADims: -1 for none, else the corner's
  permutation index (x0y0, x1y0, x1y1, x0y1). }
function TMkSolver.MarkerPosition(const A0, A1: TTyMkVal; ADims: Integer;
  AStartingAtTick: Boolean): TTyPointF;
var cx, cy: Double;
begin
  ClampData(A0, A1, cx, cy);
  Result := DataToPoint(TyMkNum(cx), TyMkNum(cy), False);
  if AStartingAtTick then
  begin
    if ADims < 0 then Exit;
    if C.XAxis.AxisType = atCategory then
      TickSnap(0, C.XAxis, cx, ADims in [1, 2], Result);
    if C.YAxis.AxisType = atCategory then
      TickSnap(1, C.YAxis, cy, ADims in [2, 3], Result);
  end
  else if C.CsBaseHorizontal then
    Result.X := Result.X + (C.BarOffset + C.BarSize / 2)
  else
    Result.Y := Result.Y + (C.BarOffset + C.BarSize / 2);
end;

{ an infinite end or corner onto the axis' own end: from / left / bottom
  takes extent[0], to / right / top extent[1] (inverse already applied); only
  one of the two -- x first }
procedure TMkSolver.InfinityToExtent(var APoint: TTyPointF; const AX, AY: TTyMkVal;
  AXFirst, AYFirst: Boolean);
var s0, s1: Double;
begin
  if JsIsInfinity(AX) then
  begin
    C.XAxis.LocalExtent(s0, s1);
    if AXFirst then APoint.X := C.XAxis.ToGlobal(s0)
    else APoint.X := C.XAxis.ToGlobal(s1);
  end
  else if JsIsInfinity(AY) then
  begin
    C.YAxis.LocalExtent(s0, s1);
    if AYFirst then APoint.Y := C.YAxis.ToGlobal(s0)
    else APoint.Y := C.YAxis.ToGlobal(s1);
  end;
end;

{ an x / y option in device pixels: parsePercent against the container (or,
  relativeTo 'coordinate', the grid's area, whose corner is added -- to a
  plain number too), NaN when not given }
function TMkSolver.PxOf(A: TJSONData; AIsX, ARelToCoord: Boolean): Double;
var
  area: TTyXYWH;
  v: Double;
begin
  if ARelToCoord then
  begin
    area := C.Cart.GetArea;
    if AIsX then
    begin
      v := TyMkParsePercent(A, area.W / C.Scale);
      Result := v * C.Scale + area.X;
    end
    else
    begin
      v := TyMkParsePercent(A, area.H / C.Scale);
      Result := v * C.Scale + area.Y;
    end;
    Exit;
  end;
  if AIsX then
    Result := C.OriginX + C.Scale * TyMkParsePercent(A, C.Width)
  else
    Result := C.OriginY + C.Scale * TyMkParsePercent(A, C.Height);
end;

function TMkSolver.EndOf(const AIt: TMkItem): TTyMkEnd;
begin
  Result.Src := AIt.Src;
  Result.Coord := AIt.Coord;
  Result.Values[0] := Stored(AIt.Coord[0], DimTypeOf(0));
  Result.Values[1] := Stored(AIt.Coord[1], DimTypeOf(1));
  Result.Value := AIt.Value;
  Result.Name := AIt.Name;
  Result.Point.X := NaN;
  Result.Point.Y := NaN;
end;

procedure TMkSolver.ReadBlock(var ABlock: TTyMkBlock);
var d: TJSONData;
begin
  { retrieveZInfo: get('z') || 0 }
  d := TyMkChainGet(nil, FOwn, FTop, FKind, 'z', False);
  if Truthy(d) then ABlock.Z := JsNumberOf(d) else ABlock.Z := 0;
  d := TyMkChainGet(nil, FOwn, FTop, FKind, 'zlevel', False);
  if Truthy(d) then ABlock.ZLevel := JsNumberOf(d) else ABlock.ZLevel := 0;
  ABlock.Silent := Truthy(TyMkChainGet(nil, FOwn, FTop, FKind, 'silent', False))
    or C.SeriesSilent;
end;

{ ---- markPoint ---- }

procedure TMkSolver.SolvePoints(AData: TJSONArray; var ABlock: TTyMkBlock);
var
  i: Integer;
  it: TMkItem;
  r: TTyMkPoint;
  rel: Boolean;
  d: TJSONData;
  xPx, yPx: Double;
begin
  SetLength(ABlock.Points, AData.Count);
  for i := 0 to AData.Count - 1 do
  begin
    r := Default(TTyMkPoint);
    r.Index := i;
    r.DataIndex := -1;
    r.E.Point.X := NaN;
    r.E.Point.Y := NaN;
    if AData.Items[i].JSONType = jtObject then
    begin
      it := ItemOf(TJSONObject(AData.Items[i]));
      DataTransform(it);
      r.E := EndOf(it);
      r.Survived := DataFilter(it);
      if r.Survived then
      begin
        r.DataIndex := ABlock.Count;
        Inc(ABlock.Count);
        d := TyMkChainGet(it.Src, FOwn, FTop, mkPoint, 'relativeTo', False);
        rel := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'coordinate');
        xPx := PxOf(TyMkChainGet(it.Src, FOwn, FTop, mkPoint, 'x', False), True, rel);
        yPx := PxOf(TyMkChainGet(it.Src, FOwn, FTop, mkPoint, 'y', False), False, rel);
        if (not IsNan(xPx)) and (not IsNan(yPx)) then
        begin
          r.E.Point.X := xPx;
          r.E.Point.Y := yPx;
        end
        else if C.IsBar then
          r.E.Point := MarkerPosition(r.E.Values[0], r.E.Values[1], -1, False)
        else
          r.E.Point := DataToPoint(r.E.Values[0], r.E.Values[1], False);
        if not IsNan(xPx) then r.E.Point.X := xPx;
        if not IsNan(yPx) then r.E.Point.Y := yPx;
      end;
    end;
    ABlock.Points[i] := r;
  end;
end;

{ ---- markLine ---- }

procedure TMkSolver.SolveLines(AData: TJSONArray; var ABlock: TTyMkBlock);
var
  i, valueIndex, baseIndex, p: Integer;
  el: TJSONData;
  n0, n1: TMkItem;
  r: TTyMkLine;
  ok, keep: Boolean;
  src: TJSONObject;
  t: string;
  d: TJSONData;
  value: TTyMkVal;
  valueAxis: TTyAxis;
  info: TMkAxisInfo;
  calcCol: Integer;
  prec: Double;

  function OnlyDim(ADim: Integer): Boolean;
  var o: Integer;
  begin
    o := 1 - ADim;
    Result := JsIsInfinity(n0.Coord[o]) and JsIsInfinity(n1.Coord[o])
      and StrictEq(n0.Coord[ADim], n1.Coord[ADim]);
    if Result then
      if ADim = 0 then Result := ContainAxis(C.XAxis, n0.Coord[0])
      else Result := ContainAxis(C.YAxis, n0.Coord[1]);
  end;

  function EndPoint(const AEnd: TTyMkEnd; AIsFrom: Boolean): TTyPointF;
  var xPx, yPx: Double;
  begin
    xPx := PxOf(TyMkChainGet(AEnd.Src, FOwn, FTop, mkLine, 'x', False), True, False);
    yPx := PxOf(TyMkChainGet(AEnd.Src, FOwn, FTop, mkLine, 'y', False), False, False);
    if (not IsNan(xPx)) and (not IsNan(yPx)) then
    begin
      Result.X := xPx;
      Result.Y := yPx;
      Exit;
    end;
    if C.IsBar then
      Result := MarkerPosition(AEnd.Values[0], AEnd.Values[1], -1, False)
    else
      Result := DataToPoint(AEnd.Values[0], AEnd.Values[1], False);
    InfinityToExtent(Result, AEnd.Values[0], AEnd.Values[1], AIsFrom, AIsFrom);
    if not IsNan(xPx) then Result.X := xPx;
    if not IsNan(yPx) then Result.Y := yPx;
  end;

begin
  SetLength(ABlock.Lines, AData.Count);
  for i := 0 to AData.Count - 1 do
  begin
    r := Default(TTyMkLine);
    r.Index := i;
    r.DataIndex := -1;
    r.LineType := TyMkUndef;
    r.LineValue := TyMkUndef;
    r.LineName := TyMkUndef;
    el := AData.Items[i];
    ok := False;
    if el.JSONType = jtArray then
    begin
      { a pair: its ends as written. The line item starts as {type: null}. }
      if (el.Count >= 2) and (el.Items[0].JSONType = jtObject)
        and (el.Items[1].JSONType = jtObject) then
      begin
        n0 := ItemOf(TJSONObject(el.Items[0]));
        n1 := ItemOf(TJSONObject(el.Items[1]));
        DataTransform(n0);
        DataTransform(n1);
        r.LineType.Kind := mvkNull;
        { merge(line, start), merge(line, end): a key already there stays }
        if n0.Value.Kind <> mvkUndef then r.LineValue := n0.Value
        else r.LineValue := n1.Value;
        if n0.Name.Kind <> mvkUndef then r.LineName := n0.Name
        else r.LineName := n1.Name;
        ok := True;
      end;
    end
    else if el.JSONType = jtObject then
    begin
      src := TJSONObject(el);
      n0 := ItemOf(src);
      t := n0.TypeStr;
      if IsCalc(t) or (not JNull(src.Find('xAxis'))) or (not JNull(src.Find('yAxis'))) then
      begin
        { markLineTransform, 1D: a line across the whole value axis }
        if (not JNull(src.Find('yAxis'))) or (not JNull(src.Find('xAxis'))) then
        begin
          if not JNull(src.Find('yAxis')) then
          begin
            valueAxis := C.YAxis;
            value := TyMkOf(src.Find('yAxis'));
          end
          else
          begin
            valueAxis := C.XAxis;
            value := TyMkOf(src.Find('xAxis'));
          end;
        end
        else
        begin
          info := AxisInfo(n0);
          valueAxis := info.ValueAxis;
          { STACK-AWARE: the statistic of the stacked totals }
          if (C.StackedCol >= 0) and (info.ValueCol = C.StackedCol) then
            calcCol := C.StackResultCol
          else
            calcCol := info.ValueCol;
          value := TyMkNum(TyMkNumCalculate(C.Store, calcCol, t));
        end;
        if valueAxis = C.XAxis then valueIndex := 0 else valueIndex := 1;
        baseIndex := 1 - valueIndex;
        d := TyMkChainGet(nil, FOwn, FTop, mkLine, 'precision', False);
        { `precision >= 0`: null compares as 0 }
        if d = nil then prec := 0 else prec := JsNumberOf(d);
        if (not IsNan(prec)) and (prec >= 0) and (value.Kind = mvkNum) then
        begin
          if prec > 20 then p := 20 else p := Trunc(prec);
          value := TyMkNum(TyJsToFixed(value.Num, p));
        end;
        { from = clone(item) with type null and a fresh coord; to = {coord} }
        n0.TypeStr := '';
        n0.CoordGiven := True;
        n0.CoordArr := True;
        n0.Coord[baseIndex] := TyMkNum(NegInfinity);
        n0.Coord[valueIndex] := value;
        n1 := ItemOf(nil);
        n1.CoordGiven := True;
        n1.CoordArr := True;
        n1.Coord[baseIndex] := TyMkNum(Infinity);
        n1.Coord[valueIndex] := value;
        DataTransform(n0);
        DataTransform(n1);
        { {type, valueIndex, value} first; then the start item's keys }
        if t <> '' then
        begin
          r.LineType.Kind := mvkStr;
          r.LineType.Str := t;
        end
        else
          r.LineType.Kind := mvkNull;
        r.LineValue := value;
        if n0.Name.Kind <> mvkUndef then r.LineName := n0.Name
        else r.LineName := n1.Name;
        ok := True;
      end;
    end;
    if ok then
    begin
      r.From := EndOf(n0);
      r.To_ := EndOf(n1);
      { markLineFilter }
      if OnlyDim(1) or OnlyDim(0) then keep := True
      else keep := DataFilter(n0) and DataFilter(n1);
      r.Survived := keep;
      if keep then
      begin
        r.DataIndex := ABlock.Count;
        Inc(ABlock.Count);
        r.From.Point := EndPoint(r.From, True);
        r.To_.Point := EndPoint(r.To_, False);
      end;
    end;
    ABlock.Lines[i] := r;
  end;
end;

{ ---- markArea ---- }

procedure TMkSolver.SolveAreas(AData: TJSONArray; var ABlock: TTyMkBlock);
const
  { dimPermutations: [x0,y0], [x1,y0], [x1,y1], [x0,y1] as indices into
    x0, y0, x1, y1 }
  cPermX: array[0..3] of Integer = (0, 2, 2, 0);
  cPermY: array[0..3] of Integer = (1, 1, 3, 3);
  cDimName: array[0..3] of string = ('x0', 'y0', 'x1', 'y1');
var
  i, k: Integer;
  el: TJSONData;
  lt, rb: TMkItem;
  r: TTyMkArea;
  keep: Boolean;
  e: TTyRange;
  xp0, xp1, yp0, yp1, ax0, ax1, ay0, ay1, bx, by, bw, bh: Double;
  d1, d2: TTyPointF;
  area: TTyXYWH;

  function Only(ADim: Integer): Boolean;
  begin
    Result := JsIsInfinity(lt.Coord[1 - ADim]) and JsIsInfinity(rb.Coord[1 - ADim]);
  end;

  { m.x0 = lt.x etc., then the series' and the master's x0 ... }
  function PxOption(ADim: Integer): TJSONData;
  var own: TJSONData;
  begin
    case ADim of
      0: own := TyMkChainGet(lt.Src, nil, nil, mkArea, 'x', True);
      1: own := TyMkChainGet(lt.Src, nil, nil, mkArea, 'y', True);
      2: own := TyMkChainGet(rb.Src, nil, nil, mkArea, 'x', True);
    else
      own := TyMkChainGet(rb.Src, nil, nil, mkArea, 'y', True);
    end;
    if own <> nil then Exit(own);
    Result := TyMkChainGet(nil, FOwn, FTop, mkArea, cDimName[ADim], False);
  end;

  function Corner(AK: Integer): TTyPointF;
  var
    xPx, yPx, c0x, c0y, c1x, c1y: Double;
    dx, dy: Integer;
    pv0, pv1: TTyMkVal;
    q0, q1: Double;
  begin
    dx := cPermX[AK];
    dy := cPermY[AK];
    xPx := PxOf(PxOption(dx), True, False);
    yPx := PxOf(PxOption(dy), False, False);
    if (not IsNan(xPx)) and (not IsNan(yPx)) then
    begin
      Result.X := xPx;
      Result.Y := yPx;
      Exit;
    end;
    if C.IsBar then
    begin
      { the corner value: compared CLAMPED, so reversed corners work }
      ClampData(r.Values[0], r.Values[1], c0x, c0y);
      ClampData(r.Values[2], r.Values[3], c1x, c1y);
      if dx = 0 then
      begin
        if JsGt(c0x, c1x) then pv0 := r.Values[2] else pv0 := r.Values[0];
      end
      else if JsGt(c0x, c1x) then pv0 := r.Values[0] else pv0 := r.Values[2];
      if dy = 1 then
      begin
        if JsGt(c0y, c1y) then pv1 := r.Values[3] else pv1 := r.Values[1];
      end
      else if JsGt(c0y, c1y) then pv1 := r.Values[1] else pv1 := r.Values[3];
      Result := MarkerPosition(pv0, pv1, AK, True);
    end
    else
    begin
      ClampData(r.Values[dx], r.Values[dy], q0, q1);
      Result := DataToPoint(TyMkNum(q0), TyMkNum(q1), True);
    end;
    InfinityToExtent(Result, r.Values[dx], r.Values[dy], dx = 0, dy = 1);
    if not IsNan(xPx) then Result.X := xPx;
    if not IsNan(yPx) then Result.Y := yPx;
  end;

  procedure Asc(var A, B: Double);
  var t, dd: Double;
  begin
    { [a, b].sort((a, b) => a - b): V8 moves b in front only when b - a < 0 }
    dd := B - A;
    if (not IsNan(dd)) and (dd < 0) then
    begin
      t := A;
      A := B;
      B := t;
    end;
  end;

begin
  SetLength(ABlock.Areas, AData.Count);
  for i := 0 to AData.Count - 1 do
  begin
    r := Default(TTyMkArea);
    r.Index := i;
    r.DataIndex := -1;
    r.Name := TyMkUndef;
    for k := 0 to 3 do
    begin
      r.Points[k].X := NaN;
      r.Points[k].Y := NaN;
      r.Values[k] := TyMkUndef;
    end;
    el := AData.Items[i];
    if (el.JSONType = jtArray) and (el.Count >= 2)
      and (el.Items[0].JSONType = jtObject) and (el.Items[1].JSONType = jtObject) then
    begin
      lt := ItemOf(TJSONObject(el.Items[0]));
      rb := ItemOf(TJSONObject(el.Items[1]));
      DataTransform(lt);
      DataTransform(rb);
      { the missing sides of the zone: to the axis' ends }
      for k := 0 to 1 do
      begin
        if Nullish(lt.Coord[k]) then lt.Coord[k] := TyMkNum(NegInfinity);
        if Nullish(rb.Coord[k]) then rb.Coord[k] := TyMkNum(Infinity);
      end;
      r.LtSrc := lt.Src;
      r.RbSrc := rb.Src;
      r.Lt := lt.Coord;
      r.Rb := rb.Coord;
      if lt.Name.Kind <> mvkUndef then r.Name := lt.Name else r.Name := rb.Name;
      { markAreaFilter }
      if Only(1) or Only(0) then keep := True
      else if HasXOrY(lt) or HasXOrY(rb) then keep := True
      else
      begin
        { zoneFilter: Cartesian2D.containZone, BoundingRect.intersect }
        d1 := DataToPoint(lt.Coord[0], lt.Coord[1], False);
        d2 := DataToPoint(rb.Coord[0], rb.Coord[1], False);
        area := C.Cart.GetArea;
        bx := d1.X;
        by := d1.Y;
        bw := d2.X - d1.X;
        bh := d2.Y - d1.Y;
        if JsLt(bw, 0) then
        begin
          bx := bx + bw;
          bw := -bw;
        end;
        if JsLt(bh, 0) then
        begin
          by := by + bh;
          bh := -bh;
        end;
        ax0 := area.X;
        ax1 := area.X + area.W;
        ay0 := area.Y;
        ay1 := area.Y + area.H;
        if JsGt(ax0, ax1) or JsGt(ay0, ay1) or JsGt(bx, bx + bw) or JsGt(by, by + bh) then
          keep := False
        else
          keep := not (JsLt(ax1, bx) or JsLt(bx + bw, ax0) or JsLt(ay1, by)
            or JsLt(by + bh, ay0));
      end;
      r.Survived := keep;
      if keep then
      begin
        r.DataIndex := ABlock.Count;
        Inc(ABlock.Count);
        r.Values[0] := Stored(lt.Coord[0], DimTypeOf(0));
        r.Values[1] := Stored(lt.Coord[1], DimTypeOf(1));
        r.Values[2] := Stored(rb.Coord[0], DimTypeOf(0));
        r.Values[3] := Stored(rb.Coord[1], DimTypeOf(1));
        for k := 0 to 3 do r.Points[k] := Corner(k);
        { allClipped: no overlap with the scales' EFFECTIVE extents }
        xp0 := Parse(C.XAxis, r.Values[0]);
        xp1 := Parse(C.XAxis, r.Values[2]);
        yp0 := Parse(C.YAxis, r.Values[1]);
        yp1 := Parse(C.YAxis, r.Values[3]);
        Asc(xp0, xp1);
        Asc(yp0, yp1);
        e := C.XAxis.Scale.GetExtent;
        r.AllClipped := JsGt(e.Start, xp1) or JsLt(e.Stop, xp0);
        e := C.YAxis.Scale.GetExtent;
        r.AllClipped := r.AllClipped or JsGt(e.Start, yp1) or JsLt(e.Stop, yp0);
      end;
    end;
    ABlock.Areas[i] := r;
  end;
end;

function TyMarkerSolve(AKind: TTyMarkerKind; ASeries, ATop: TJSONObject;
  const ACtx: TTyMkContext): TTyMkBlock;
var
  own: TJSONData;
  data: TJSONData;
  s: TMkSolver;
  mask: TFPUExceptionMask;
begin
  Result := Default(TTyMkBlock);
  Result.Kind := AKind;
  if (ASeries = nil) or (ACtx.Store = nil) or (ACtx.Cart = nil)
    or (ACtx.XAxis = nil) or (ACtx.YAxis = nil) then Exit;
  own := ASeries.Find(TyMarkerKey[AKind]);
  if (own = nil) or (own.JSONType <> jtObject) then Exit;
  { no `data`, no marker model for this series }
  data := TJSONObject(own).Find('data');
  if not Truthy(data) then Exit;
  Result.Present := True;
  Result.Own := TJSONObject(own);
  Result.Top := ATop;
  Result.XAxis := ACtx.XAxis;
  Result.YAxis := ACtx.YAxis;
  s := TMkSolver.Create;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow,
    exPrecision]);
  try
    s.C := ACtx;
    s.FKind := AKind;
    s.FOwn := Result.Own;
    s.FTop := ATop;
    s.ReadBlock(Result);
    if data.JSONType = jtArray then
      case AKind of
        mkPoint: s.SolvePoints(TJSONArray(data), Result);
        mkLine: s.SolveLines(TJSONArray(data), Result);
        mkArea: s.SolveAreas(TJSONArray(data), Result);
      end;
  finally
    SetExceptionMask(mask);
    s.Free;
  end;
end;

initialization
  GDefaults[mkPoint] := TJSONObject(GetJSON('{"z":5,"symbol":"pin","symbolSize":50,'
    + '"tooltip":{"trigger":"item"},"label":{"show":true,"position":"inside"},'
    + '"itemStyle":{"borderWidth":2},"emphasis":{"label":{"show":true}}}'));
  GDefaults[mkLine] := TJSONObject(GetJSON('{"z":5,"symbol":["circle","arrow"],'
    + '"symbolSize":[8,16],"symbolOffset":0,"precision":2,'
    + '"tooltip":{"trigger":"item"},"label":{"show":true,"position":"end","distance":5},'
    + '"lineStyle":{"type":"dashed"},'
    + '"emphasis":{"label":{"show":true},"lineStyle":{"width":3}},'
    + '"animationEasing":"linear"}'));
  GDefaults[mkArea] := TJSONObject(GetJSON('{"z":1,"tooltip":{"trigger":"item"},'
    + '"animation":false,"label":{"show":true,"position":"top"},'
    + '"itemStyle":{"borderWidth":0},'
    + '"emphasis":{"label":{"show":true,"position":"top"}}}'));

finalization
  GDefaults[mkPoint].Free;
  GDefaults[mkLine].Free;
  GDefaults[mkArea].Free;
end.
