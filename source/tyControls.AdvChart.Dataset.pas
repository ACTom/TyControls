unit tyControls.AdvChart.Dataset;
{$mode objfpc}{$H+}
{ `dataset` and `encode` -- the other way data reaches a chart.

  A series' `data` says WHAT the values are and, by position, which coordinate
  each one is. A `dataset` says only what the values are, in a table shared by
  every series, and `encode` says which COLUMN of that table feeds which
  coordinate. The table is the same shape a spreadsheet has, which is the point:
  it is what a chart's data usually looks like before someone reshapes it for a
  charting library.

  14 of the 244 converted examples carry a dataset and 21 carry an encode.

  WHAT THE COLUMN NAMES ARE FOR, and what they are NOT for. A source dimension's
  name is used for two things: looking up `encode: { x: 'product' }`, and naming
  a series that did not name itself. It does NOT rename the store's columns --
  those stay `x` and `y`, because seven places downstream find their column by
  looking the axis' own dimension name up in the store, and a store whose
  columns were called `product` and `2015` would be invisible to all of them.

  THE DEFAULT ENCODE IS A RUNNING COUNTER, not a function of the series index,
  and that is the single thing a port is most likely to get wrong. Upstream
  keeps one cursor per (dataset, seriesLayoutBy) pair, and each series that asks
  for a default advances it. A series that brought its OWN encode does not
  advance it -- and a series that brought a PARTIAL one does not either, because
  a partial encode disables the defaulter entirely rather than merging with it.

  PORTED FROM src/data/Source.ts, src/data/helper/sourceHelper.ts and
  src/data/helper/createDimensions.ts, ECharts 6.1.0.

  WHAT IS NOT HERE:

    `dataset.transform` BEYOND THE BOXPLOT REDUCER. Six of the fourteen corpus
    datasets use one, and it is a language rather than a setting -- a filter
    expression grammar, a sort, a boxplot reducer, and a chain of datasets
    feeding each other. [Batch 108: the chain (`fromDatasetIndex`,
    `fromDatasetId`, `fromTransformResult`, a piped list) and the one
    transform the boxplot series registers, 'boxplot', are here --
    TTyDatasetCache below; 'filter' and 'sort' are D2's, and a transform of a
    type nobody registered leaves the dataset without a source, where
    upstream throws.]

    TYPED ARRAYS, which cannot survive a trip through JSON, and KEYED COLUMNS
    (`{ product: [...], 2015: [...] }`), which no corpus example uses. Both
    detect correctly and then answer no rows, which is what a chart with an
    unreadable source should draw.

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option;

type
  { The five shapes a source can be in. `tsfOriginal` is not sniffed and never
    comes out of TyDetectSourceFormat: upstream decides it by PROVENANCE rather
    than by shape, so the same `[[1,2],[3,4]]` is a table under `dataset.source`
    and a series' own rows under `series.data`. It is named here because the
    distinction is the reason this unit exists. }
  TTySourceFormat = (tsfUnknown, tsfArrayRows, tsfObjectRows, tsfKeyedColumns,
                     tsfOriginal);

  { Which way the table runs. `column` -- the default -- means each COLUMN is a
    dimension and each row a record; `row` transposes that. }
  TTySeriesLayoutBy = (slbColumn, slbRow);

  { One dimension of a source: what to call it, and the type the option declared
    for it if it declared one. }
  TTySourceDim = record
    Name: string;
    { `dimensions: [{ name: 'x', type: 'time' }]`. '' when nobody said. }
    DimType: string;
    { `displayName`, or failing that the name: what a tooltip sub-row calls
      the dimension. '' only for a dimension with no name at all. }
    DisplayName: string;
  end;
  TTySourceDimArray = array of TTySourceDim;

  { A resolved `dataset`. Everything a filler needs to read a cell, and nothing
    that depends on which series is asking. }
  TTyChartSource = record
    Valid: Boolean;
    Format: TTySourceFormat;
    LayoutBy: TTySeriesLayoutBy;
    { The first line that is DATA. 1 when the table has a header. Only
      `tsfArrayRows` ever has one. }
    StartIndex: Integer;
    { The table itself, borrowed from the option's tree -- never owned. }
    Data: TJSONArray;
    { The same for `tsfKeyedColumns`, whose table is an object of columns;
      Data is nil then. }
    Keyed: TJSONObject;
    Dims: TTySourceDimArray;
    { How many dimensions the table has, which is not always Length(Dims): a
      table with no names still has columns. }
    DimCount: Integer;
  end;

  { Which source dimensions feed one series' coordinates.

    Columns[i] is the source dimension feeding coordinate dimension i, or -1
    for `there is none` -- which is what `encode: { x: -1 }` asks for and what
    an unclaimed coordinate gets. }
  TTySeriesEncode = record
    Given: Boolean;
    Columns: array of Integer;
    { Parallel to Columns: the coordinate was WRITTEN in `encode` -- even as
      -1, which asks for no mapping. An unwritten one takes the next unclaimed
      dimension (TyEncodeFillUnclaimed). }
    Explicit: array of Boolean;
    { `encode.tooltip` and `encode.label`, every entry resolved (unresolved
      ones dropped) -- upstream's defaultedTooltip / defaultedLabel when
      non-empty. }
    Tooltip, Labels: array of Integer;
    { `itemName` and `seriesName`: where a row's own name and the series' own
      name come from. -1 for neither. Only the FIRST entry of each is used --
      upstream reads slot 0 and ignores the rest. }
    ItemName: Integer;
    SeriesName: Integer;
  end;

  { One coordinate of a series, as this unit needs it: what it is called and
    whether its axis is a category one. Deliberately not the builder's own
    dimension record -- that unit reads this one, so it cannot also define what
    this one takes. }
  TTyCoordDim = record
    Name: string;
    Ordinal: Boolean;
  end;
  TTyCoordDimArray = array of TTyCoordDim;

  { The running cursor the default encode advances. ONE per (dataset,
    seriesLayoutBy) pair, held by whoever walks the series in order.

    CategoryStart is seeded by the FIRST series to ask -- upstream seeds the
    record from that series' own category dimension width and leaves it alone
    afterwards. }
  TTyEncodeCursor = record
    DatasetIndex: Integer;
    LayoutBy: TTySeriesLayoutBy;
    Seeded: Boolean;
    ValueWay: Integer;
    CategoryWay: Integer;
  end;
  TTyEncodeCursorArray = array of TTyEncodeCursor;

type
  { THE DATASETS THAT ARE COMPUTED RATHER THAN WRITTEN [Batch 108].

    A dataset with a `transform` (or a `fromTransformResult`) has no `source`
    of its own: it reads another dataset's result -- `fromDatasetIndex`, else
    `fromDatasetId`, else dataset 0 -- and runs it through the transform,
    which may answer SEVERAL results; a dataset naming `fromTransformResult`
    without a transform takes that one result of its upstream as it is.
    upstream's SourceManager, and the order is its order.

    WHAT THIS HOLDS is a JSON node per result in the shape TySourceOf already
    reads -- `source`, `dimensions`, `sourceHeader`, `seriesLayoutBy` -- so a
    computed table is read by exactly the code that reads a written one. A
    root dataset's result is its own node, borrowed; a transform's result is
    a node made here and freed with the cache; a `fromTransformResult` clone
    is the upstream's node again. The cache must therefore outlive every
    source read through it: the control holds one and clears it when it
    builds its stores again.

    A REGISTRY OF ONE. 'boxplot' is the only transform a stock ECharts build
    registers outside the transform component; D2's 'filter' and 'sort' join
    it in ApplyOne. Anything upstream throws on -- an unknown type, an empty
    pipe, an upstream that is not a table of arrays or is laid out by row, a
    result index that is not there, a dataset that reads itself -- answers
    nil here, and the series reading it draws nothing. }
  TTyJSONObjectArray = array of TJSONObject;

  TTyDatasetCache = class
  private
    FOption: TTyChartOption;
    { per dataset: its results (nil when it has none) }
    FResults: array of array of TJSONObject;
    { per dataset: 0 not looked at, 1 being resolved, 2 resolved }
    FState: array of Byte;
    FOwned: TFPList;
    procedure Reset(AOption: TTyChartOption);
    procedure Resolve(AIndex: Integer);
    function UpstreamOf(ANode: TJSONObject): Integer;
    function ApplyPipe(ATransform: TJSONData; AUp: TJSONObject;
      out AResults: TTyJSONObjectArray): Boolean;
    function ApplyOne(ATransform: TJSONData; const AUps: TTyJSONObjectArray;
      out AResults: TTyJSONObjectArray): Boolean;
    function Own(ANode: TJSONObject): TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { The node result AResult of dataset AIndex is read from, or nil. }
    function ResultNode(AOption: TTyChartOption; AIndex, AResult: Integer): TJSONObject;
  end;

{ How many `dataset` components the option carries. }
function TyDatasetCount(AOption: TTyChartOption): Integer;

{ JavaScript's truthiness of an option value: absent, null, false, 0, NaN
  and '' are false; every object and array, empty or not, is true. }
function TyDatasetTruthy(AData: TJSONData): Boolean;

{ upstream's quantile (util/number.ts) over a list ALREADY ASCENDING: the
  position H = (n - 1) p + 1, the value at floor(H) and, when H has a
  fraction, that much of the way to the next. A position past either end
  reads not-a-number -- an empty list answers not-a-number, as upstream's
  `undefined` arithmetic does. [Batch 108] }
function TyQuantile(const AAsc: array of Double; AP: Double): Double;

{ prepareBoxplotData: for every row of ARaw (a list of samples) the box
  [name, low, Q1, Q2, Q3, high] and, for every sample outside [low, high],
  an outlier [name, sample].

  boundIQR from AConfig: absent or null is 1.5; 'none' and 0 use the extremes
  (low and high are the minimum and maximum); anything else multiplies the
  interquartile range, coerced the way `*` coerces. itemNameFormatter: a
  string with its FIRST value placeholder replaced by the row index;
  anything else, the index. A sample is a number as JavaScript's subtraction reads it.

  False, with nothing made, when a row is not an array -- upstream's
  `.slice()` throws there. The two arrays are the caller's. [Batch 108] }
function TyPrepareBoxplotData(ARaw: TJSONArray; AConfig: TJSONObject;
  out ABoxes, AOutliers: TJSONArray): Boolean;

{ The shape of a `dataset.source`, by the rules in Source.ts:256-294: the
  container's runtime type, then the type of its FIRST NON-NULL item.

  A flat array of scalars is tsfUnknown and has no reader, which is upstream's
  answer too -- it throws there. }
function TyDetectSourceFormat(AData: TJSONData): TTySourceFormat;

{ Read dataset AIndex AS SERIES ASeriesIndex SEES IT.

  A TABLE IS NOT READ ONCE. `seriesLayoutBy`, `sourceHeader` and `dimensions`
  may all be written on the SERIES as well as on the dataset, and the series'
  answer wins -- so two series can read one table in two different
  directions, with two different header rules and two different sets of
  names. One corpus example does exactly that: seven bars over one table,
  three of them transposed, and the dataset says nothing about any of it.

  Pass ASeriesIndex < 0 for the dataset's own view, which is what the table
  looks like to anyone who did not ask for anything.

  Answers Valid = False when there is no such dataset or its source is a
  shape with no reader.

  [Batch 108] A dataset with a transform is read through ACache, which makes
  and keeps its table; without a cache such a dataset answers Valid = False. }
function TySourceOf(AOption: TTyChartOption; AIndex: Integer;
  ASeriesIndex: Integer = -1; ACache: TTyDatasetCache = nil): TTyChartSource;

{ How many rows of DATA the table has -- the header is already excluded. }
function TySourceRowCount(const ASource: TTyChartSource): Integer;

{ One cell, or nil. ARow counts data rows from 0; ADim counts dimensions. }
function TySourceCell(const ASource: TTyChartSource;
  ARow, ADim: Integer): TJSONData;

{ The name of dimension ADim, or '' when it has none. }
function TySourceDimName(const ASource: TTyChartSource; ADim: Integer): string;

{ The dimension called AName, or -1. Compared exactly, as upstream compares. }
function TySourceDimIndexOf(const ASource: TTyChartSource;
  const AName: string): Integer;

{ Which dataset this series reads. `datasetIndex` beats `datasetId`; with
  neither, the FIRST dataset. Answers -1 when the chart has no dataset, or when
  the series brought its own `data` -- which wins over any dataset, and an empty
  `data: []` counts as bringing some. }
function TySeriesDatasetIndex(AOption: TTyChartOption;
  ASeriesIndex: Integer): Integer;

{ `series.encode`, resolved against a source. Answers Given = False when the
  series carries no `encode` at all -- which is the signal to run a defaulter.

  A VALUE MAY BE AN INDEX, A NAME, OR A LIST OF EITHER, and only the first
  entry of a list reaches a coordinate. A name that matches nothing leaves the
  coordinate unclaimed rather than raising. }
function TyEncodeOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ASource: TTyChartSource;
  const ACoordDims: TTyCoordDimArray): TTySeriesEncode;

{ upstream's createDimensions for a GIVEN encode: every coordinate not
  written in it takes, in coordinate order, the first dimension below
  ADimCount that no coordinate holds yet. `encode: {y: 2}` on a table reads
  x from 0; `encode: {tooltip: [2]}` leaves x on 0 and y on 1. }
procedure TyEncodeFillUnclaimed(var AEnc: TTySeriesEncode; ADimCount: Integer);

{ A series' own `dimensions`, as a source that names things but holds
  nothing -- what an encode name on series data is looked up against. }
function TySeriesDimsSource(AOption: TTyChartOption;
  ASeriesIndex: Integer): TTyChartSource;

{ The default encode for a series on an axis coordinate system, and the pass
  that advances ACursor.

  TWO WAYS, and which one is used is decided by whether ANY of this series'
  coordinates is ordinal -- not by which axis it is:

    VALUE WAY, no category axis anywhere: each series takes the next
    Length(ACoordDims) dimensions. Three scatter series on a four-column table
    take (0,1), (2,3), (4,5).

    CATEGORY WAY, at least one: the FIRST ordinal coordinate takes dimension 0
    and every series shares it; the others take from a cursor that starts just
    past it. Three bars on a category axis take x=0 and y=1, 2, 3 -- which is
    the arrangement a spreadsheet has and the reason `dataset` is worth having.

  THE CATEGORY DIMENSION IS 0 WHATEVER AXIS IT IS ON. A chart with the CATEGORY
  on y still reads the category from dimension 0 and the value from 1, 2, 3 --
  the rule is about the order of the coordinate list, not about the screen. }
function TyDefaultEncodeAxis(var ACursor: TTyEncodeCursor;
  const ACoordDims: TTyCoordDimArray): TTySeriesEncode;

{ The default encode for a series that names its data rather than plotting it --
  a pie, a funnel. Answers a NAME dimension and a VALUE dimension.

  A dimension literally called `name` wins outright. Failing that the first
  dimension that looks purely numeric is the value and the first that does not
  is the name, both searched over at most the first five dimensions. }
function TyDefaultEncodeNameBased(const ASource: TTyChartSource;
  ADimCount: Integer): TTySeriesEncode;

{ Whether dimension ADim looks like a category. Reads the declared type first
  and sniffs at most five rows otherwise. }
function TySourceDimIsOrdinal(const ASource: TTyChartSource;
  ADim: Integer): Boolean;

{ The cursor for one dataset and layout, found or created in AList. }
function TyEncodeCursorFor(var AList: TTyEncodeCursorArray;
  ADatasetIndex: Integer; ALayoutBy: TTySeriesLayoutBy): Integer;

implementation

uses tyControls.AdvChart.Data;

const
  { Source.ts:351 -- `10 is an experience number, avoid long loop.` }
  cHeaderScan = 10;
  { sourceHelper.ts:225 -- `5 is an experience value.` }
  cGuessScan = 5;

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function ArrOf(AData: TJSONData): TJSONArray;
begin
  if (AData <> nil) and (AData is TJSONArray) then
    Result := TJSONArray(AData)
  else
    Result := nil;
end;

function TyDatasetCount(AOption: TTyChartOption): Integer;
begin
  Result := 0;
  if AOption = nil then Exit;
  Result := AOption.ComponentCount('dataset');
end;

function TyDatasetTruthy(AData: TJSONData): Boolean;
begin
  Result := False;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (not IsNan(AData.AsFloat)) and (AData.AsFloat <> 0);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

{ ==================== the boxplot reducer [Batch 108] ==================== }

{ A sample as `a - b` and `+x` read it. A string through Number(); true 1,
  false and null 0; an array or an object not-a-number (upstream's [] is 0
  and [5] is 5 -- tables of samples do not hold them). }
function SampleOf(AData: TJSONData): Double;
begin
  Result := NaN;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtString: Result := TyJsToNumber(AData.AsString);
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtNull: Result := 0;
  end;
end;

{ Math.max / Math.min: not-a-number wins, and +0 is above -0 }
function JsMax2(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A
  else if B > A then Result := B
  else if (A = 0) and (B = 0) then
  begin
    if (PQWord(@A)^ shr 63 = 0) then Result := A else Result := B;
  end
  else Result := A;
end;

function JsMin2(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A
  else if B < A then Result := B
  else if (A = 0) and (B = 0) then
  begin
    if (PQWord(@A)^ shr 63 = 1) then Result := A else Result := B;
  end
  else Result := A;
end;

{ asc(): Array.prototype.sort with (a, b) => a - b, which is STABLE -- a
  comparison that is not-a-number counts as equal. An insertion sort keeps
  equal samples (a -0 beside a 0) in the order they came. }
procedure SortAsc(var A: TTyDoubleArray);
var i, j: Integer; t, d: Double;
begin
  for i := 1 to High(A) do
  begin
    t := A[i];
    j := i - 1;
    while j >= 0 do
    begin
      d := A[j] - t;
      if IsNan(d) or not (d > 0) then Break;
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
end;

function TyQuantile(const AAsc: array of Double; AP: Double): Double;
var
  hh, e, v, nx: Double;
  h: Int64;

  function At(AIdx: Int64): Double;
  begin
    if (AIdx < 0) or (AIdx > High(AAsc)) then Result := NaN
    else Result := AAsc[AIdx];
  end;

begin
  hh := (Length(AAsc) - 1) * AP + 1;
  if IsNan(hh) or IsInfinite(hh) then Exit(NaN);
  h := Floor(hh);
  v := At(h - 1);
  e := hh - h;
  { `e ? v + e * (ascArr[h] - v) : v` -- a nought fraction is the value }
  if (e <> 0) and not IsNan(e) then
  begin
    nx := At(h);
    Result := v + e * (nx - v);
  end
  else
    Result := v;
end;

function TyPrepareBoxplotData(ARaw: TJSONArray; AConfig: TJSONObject;
  out ABoxes, AOutliers: TJSONArray): Boolean;
const
  cDefaultBound: Double = 1.5;
  cP1: Double = 0.25;
  cP2: Double = 0.5;
  cP3: Double = 0.75;
var
  i, j, k: Integer;
  row: TJSONArray;
  asc: TTyDoubleArray;
  q1, q2, q3, mn, mx, bound, lo, hi, boundIqr: Double;
  useExtreme, boundGiven: Boolean;
  d, fmt: TJSONData;
  name: string;
  box, outlier: TJSONArray;
begin
  Result := False;
  ABoxes := nil;
  AOutliers := nil;
  if ARaw = nil then Exit;
  { every row has to be a list before anything is made }
  for i := 0 to ARaw.Count - 1 do
    if not (ARaw.Items[i] is TJSONArray) then Exit;

  { boundIQR: 'none' and 0 (a NUMBER nought; '0' is not) use the extremes }
  d := nil;
  fmt := nil;
  if AConfig <> nil then
  begin
    d := AConfig.Find('boundIQR');
    fmt := AConfig.Find('itemNameFormatter');
  end;
  boundGiven := (d <> nil) and (d.JSONType <> jtNull);
  useExtreme := boundGiven and (((d.JSONType = jtString) and (d.AsString = 'none'))
    or ((d.JSONType = jtNumber) and (d.AsFloat = 0)));
  if boundGiven then boundIqr := SampleOf(d) else boundIqr := cDefaultBound;
  { an array or an object multiplies to not-a-number }
  if boundGiven and (d.JSONType in [jtArray, jtObject]) then boundIqr := NaN;

  ABoxes := TJSONArray.Create;
  AOutliers := TJSONArray.Create;
  for i := 0 to ARaw.Count - 1 do
  begin
    row := TJSONArray(ARaw.Items[i]);
    SetLength(asc, row.Count);
    for k := 0 to row.Count - 1 do asc[k] := SampleOf(row.Items[k]);
    SortAsc(asc);
    q1 := TyQuantile(asc, cP1);
    q2 := TyQuantile(asc, cP2);
    q3 := TyQuantile(asc, cP3);
    if Length(asc) > 0 then
    begin
      mn := asc[0];
      mx := asc[High(asc)];
    end
    else
    begin
      mn := NaN;
      mx := NaN;
    end;
    bound := boundIqr * (q3 - q1);
    if useExtreme then
    begin
      lo := mn;
      hi := mx;
    end
    else
    begin
      lo := JsMax2(mn, q1 - bound);
      hi := JsMin2(mx, q3 + bound);
    end;
    { the FIRST placeholder only -- String.prototype.replace with a string }
    if (fmt <> nil) and (fmt.JSONType = jtString) then
    begin
      name := fmt.AsString;
      k := Pos('{value}', name);
      if k > 0 then
        name := Copy(name, 1, k - 1) + IntToStr(i) + Copy(name, k + 7, MaxInt);
    end
    else
      name := IntToStr(i);
    box := TJSONArray.Create;
    box.Add(name);
    box.Add(TJSONFloatNumber.Create(lo));
    box.Add(TJSONFloatNumber.Create(q1));
    box.Add(TJSONFloatNumber.Create(q2));
    box.Add(TJSONFloatNumber.Create(q3));
    box.Add(TJSONFloatNumber.Create(hi));
    ABoxes.Add(box);
    { a comparison with not-a-number is false (and would raise here) }
    for j := 0 to High(asc) do
      if not IsNan(asc[j]) and ((not IsNan(lo) and (asc[j] < lo))
        or (not IsNan(hi) and (asc[j] > hi))) then
      begin
        outlier := TJSONArray.Create;
        outlier.Add(name);
        outlier.Add(TJSONFloatNumber.Create(asc[j]));
        AOutliers.Add(outlier);
      end;
  end;
  Result := True;
end;

{ ==================== the computed datasets [Batch 108] ==================== }

constructor TTyDatasetCache.Create;
begin
  inherited Create;
  FOwned := TFPList.Create;
end;

destructor TTyDatasetCache.Destroy;
begin
  Clear;
  FOwned.Free;
  inherited Destroy;
end;

procedure TTyDatasetCache.Clear;
var i: Integer;
begin
  for i := 0 to FOwned.Count - 1 do TObject(FOwned[i]).Free;
  FOwned.Clear;
  FResults := nil;
  FState := nil;
  FOption := nil;
end;

procedure TTyDatasetCache.Reset(AOption: TTyChartOption);
var n: Integer;
begin
  Clear;
  FOption := AOption;
  n := TyDatasetCount(AOption);
  SetLength(FResults, n);
  SetLength(FState, n);
end;

function TTyDatasetCache.Own(ANode: TJSONObject): TJSONObject;
begin
  FOwned.Add(ANode);
  Result := ANode;
end;

function TTyDatasetCache.ResultNode(AOption: TTyChartOption;
  AIndex, AResult: Integer): TJSONObject;
begin
  Result := nil;
  if AOption = nil then Exit;
  { A DIFFERENT OPTION, or one grown since, starts afresh }
  if (AOption <> FOption) or (Length(FResults) <> TyDatasetCount(AOption)) then
    Reset(AOption);
  if (AIndex < 0) or (AIndex > High(FResults)) then Exit;
  Resolve(AIndex);
  if (AResult < 0) or (AResult > High(FResults[AIndex])) then Exit;
  Result := FResults[AIndex][AResult];
end;

{ queryDatasetUpstreamDatasetModels: fromDatasetIndex, else fromDatasetId,
  else dataset 0 -- SINGLE_REFERRING's default; -1 for one naming nothing }
function TTyDatasetCache.UpstreamOf(ANode: TJSONObject): Integer;
var
  d, idd: TJSONData;
  i, n: Integer;
  ds: TJSONObject;
begin
  Result := -1;
  n := Length(FResults);
  d := ANode.Find('fromDatasetIndex');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result := TyRoundOpt(d.AsFloat);
    if (Result < 0) or (Result >= n) then Result := -1;
    Exit;
  end;
  d := ANode.Find('fromDatasetId');
  if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then
  begin
    for i := 0 to n - 1 do
    begin
      ds := ObjOf(FOption.ComponentAt('dataset', i));
      if ds = nil then Continue;
      idd := ds.Find('id');
      if (idd <> nil) and (idd.JSONType in [jtString, jtNumber])
        and (idd.AsString = d.AsString) then Exit(i);
    end;
    Exit(-1);
  end;
  Result := 0;
end;

procedure TTyDatasetCache.Resolve(AIndex: Integer);
var
  node, upNode: TJSONObject;
  tr, ftr: TJSONData;
  up, ri: Integer;
  outs: TTyJSONObjectArray;
  r: Double;
begin
  if FState[AIndex] <> 0 then Exit;
  FState[AIndex] := 1;
  try
    FResults[AIndex] := nil;
    node := ObjOf(FOption.ComponentAt('dataset', AIndex));
    if node = nil then Exit;
    tr := node.Find('transform');
    ftr := node.Find('fromTransformResult');
    { A ROOT DATASET: `!transform && !fromTransformResult` -- a
      fromTransformResult of 0 alone is a root one too }
    if not (TyDatasetTruthy(tr) or TyDatasetTruthy(ftr)) then
    begin
      SetLength(FResults[AIndex], 1);
      FResults[AIndex][0] := node;
      Exit;
    end;
    up := UpstreamOf(node);
    if (up < 0) or (up = AIndex) then Exit;
    Resolve(up);
    { getSource(fromTransformResult || 0) }
    ri := 0;
    if (ftr <> nil) and (ftr.JSONType <> jtNull) then
    begin
      r := SampleOf(ftr);
      if IsNan(r) or IsInfinite(r) or (Frac(r) <> 0) then Exit;
      if r <> 0 then ri := Trunc(r);
    end;
    if (ri < 0) or (ri > High(FResults[up])) then Exit;
    upNode := FResults[up][ri];
    if upNode = nil then Exit;
    if TyDatasetTruthy(tr) then
    begin
      if not ApplyPipe(tr, upNode, outs) then Exit;
      FResults[AIndex] := outs;
    end
    else
    begin
      { cloneSourceShallow: the upstream's own table and rules }
      SetLength(FResults[AIndex], 1);
      FResults[AIndex][0] := upNode;
    end;
  finally
    FState[AIndex] := 2;
  end;
end;

{ applyDataTransform: a list is a pipe, each step fed the one before's
  results (only its FIRST read by a single-input transform); an empty pipe
  throws }
function TTyDatasetCache.ApplyPipe(ATransform: TJSONData; AUp: TJSONObject;
  out AResults: TTyJSONObjectArray): Boolean;
var
  ups: TTyJSONObjectArray;
  i: Integer;
begin
  Result := False;
  AResults := nil;
  SetLength(ups, 1);
  ups[0] := AUp;
  if ATransform is TJSONArray then
  begin
    if TJSONArray(ATransform).Count = 0 then Exit;
    for i := 0 to TJSONArray(ATransform).Count - 1 do
    begin
      if not ApplyOne(TJSONArray(ATransform).Items[i], ups, AResults) then Exit;
      ups := AResults;
    end;
  end
  else if not ApplyOne(ATransform, ups, AResults) then Exit;
  Result := Length(AResults) > 0;
end;

{ applySingleDataTransform for the transforms this port registers: the
  upstream must be a table of arrays laid out by column (createExternalSource
  and boxplotTransform both throw otherwise); 'boxplot' answers the boxes,
  named, and the outliers, unnamed -- neither carries a header line }
function TTyDatasetCache.ApplyOne(ATransform: TJSONData;
  const AUps: TTyJSONObjectArray; out AResults: TTyJSONObjectArray): Boolean;
var
  t, up, box, outs: TJSONObject;
  d, src: TJSONData;
  boxes, outliers: TJSONArray;
begin
  Result := False;
  AResults := nil;
  if (Length(AUps) = 0) or (AUps[0] = nil) then Exit;
  t := ObjOf(ATransform);
  if t = nil then Exit;
  d := t.Find('type');
  if (d = nil) or (d.JSONType <> jtString) or (d.AsString <> 'boxplot') then Exit;
  up := AUps[0];
  d := up.Find('seriesLayoutBy');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'row') then Exit;
  src := up.Find('source');
  if TyDetectSourceFormat(src) <> tsfArrayRows then Exit;
  if not (src is TJSONArray) then Exit;
  d := t.Find('config');
  if not TyPrepareBoxplotData(TJSONArray(src), ObjOf(d), boxes, outliers) then Exit;
  box := Own(TJSONObject.Create);
  box.Add('source', boxes);
  box.Add('dimensions', TJSONArray.Create(['ItemName', 'Low', 'Q1', 'Q2', 'Q3', 'High']));
  box.Add('sourceHeader', 0);
  box.Add('seriesLayoutBy', 'column');
  outs := Own(TJSONObject.Create);
  outs.Add('source', outliers);
  outs.Add('sourceHeader', 0);
  outs.Add('seriesLayoutBy', 'column');
  SetLength(AResults, 2);
  AResults[0] := box;
  AResults[1] := outs;
  Result := True;
end;

{ ==================== the source ==================== }

function TyDetectSourceFormat(AData: TJSONData): TTySourceFormat;
var
  arr: TJSONArray;
  i: Integer;
  item: TJSONData;
  obj: TJSONObject;
begin
  Result := tsfUnknown;
  if AData = nil then Exit;

  if AData is TJSONArray then
  begin
    arr := TJSONArray(AData);
    { AN EMPTY TABLE IS A TABLE. Upstream says so in a comment of its own. }
    if arr.Count = 0 then Exit(tsfArrayRows);
    { THE FIRST NON-NULL ITEM DECIDES AND THE LOOP STOPS THERE. A table whose
      first row is an array and whose second is an object is read as a table of
      arrays; the mixture is not refused.

      AN EQUIVALENT MUTANT LIVES ON THE NULL GUARD and is recorded rather than
      chased: fpjson's null is a TJSONNull, which descends straight from
      TJSONData and is therefore neither of the two things the loop tests for,
      so a null falls through to the next item with or without the guard. It
      is kept because it says the rule out loud -- upstream skips nulls
      deliberately, and a reader should not have to know one library's class
      hierarchy to see that a leading null does not decide anything. }
    for i := 0 to arr.Count - 1 do
    begin
      item := arr.Items[i];
      if (item = nil) or (item.JSONType = jtNull) then Continue;
      if item is TJSONArray then Exit(tsfArrayRows);
      if item is TJSONObject then Exit(tsfObjectRows);
    end;
    { Nothing but scalars: no reader, the same answer upstream gives. }
    Exit(tsfUnknown);
  end;

  obj := ObjOf(AData);
  if obj = nil then Exit;
  for i := 0 to obj.Count - 1 do
    if obj.Items[i] is TJSONArray then Exit(tsfKeyedColumns);
end;

{ The first LINE of a table of arrays: its first row under `column` layout, its
  first column under `row` layout. Answers nil past the end. }
function FirstLineCell(AData: TJSONArray; ALayoutBy: TTySeriesLayoutBy;
  AIndex: Integer): TJSONData;
var row: TJSONArray;
begin
  Result := nil;
  if AData = nil then Exit;
  if ALayoutBy = slbRow then
  begin
    if AIndex >= AData.Count then Exit;
    row := ArrOf(AData.Items[AIndex]);
    if (row = nil) or (row.Count = 0) then Exit;
    Result := row.Items[0];
  end
  else
  begin
    if AData.Count = 0 then Exit;
    row := ArrOf(AData.Items[0]);
    if (row = nil) or (AIndex >= row.Count) then Exit;
    Result := row.Items[AIndex];
  end;
end;

function FirstLineLength(AData: TJSONArray;
  ALayoutBy: TTySeriesLayoutBy): Integer;
var row: TJSONArray;
begin
  Result := 0;
  if AData = nil then Exit;
  if ALayoutBy = slbRow then Exit(AData.Count);
  if AData.Count = 0 then Exit;
  row := ArrOf(AData.Items[0]);
  if row <> nil then Result := row.Count;
end;

{ `sourceHeader: 'auto'`, Source.ts:336-352 -- AND THE CODE DOES NOT DO WHAT THE
  COMMENT ABOVE IT SAYS. The comment reads `Most of the first line are string:
  it is header`, and then reasons about a line of five strings and one number.
  The code it annotates keeps a header only when EVERY examined cell is a
  string: a string sets the answer to `header` only if nothing has set it yet,
  while a non-string sets `no header` unconditionally, so one number anywhere in
  the window settles it.

  Nulls and the string `'-'` are skipped -- `-` is upstream's spelling of a gap.
  At most ten cells are looked at, and the cap counts the skipped ones, so a
  number in the twelfth column of a header row is invisible. }
function DetectStartIndex(AData: TJSONArray;
  ALayoutBy: TTySeriesLayoutBy): Integer;
var
  i, n: Integer;
  cell: TJSONData;
  decided: Boolean;
begin
  Result := 0;
  decided := False;
  n := FirstLineLength(AData, ALayoutBy);
  if n > cHeaderScan then n := cHeaderScan;
  for i := 0 to n - 1 do
  begin
    cell := FirstLineCell(AData, ALayoutBy, i);
    if (cell = nil) or (cell.JSONType = jtNull) then Continue;
    if (cell.JSONType = jtString) and (cell.AsString = '-') then Continue;
    if cell.JSONType = jtString then
    begin
      if not decided then
      begin
        Result := 1;
        decided := True;
      end;
    end
    else
    begin
      Result := 0;
      decided := True;
    end;
  end;
end;

{ `dimensions`, in either of the two forms an entry may take. Takes the VALUE
  rather than the node it came off, because the series and the dataset both
  carry one and the caller has already decided which wins. }
function ReadDimensions(AValue: TJSONData): TTySourceDimArray;
var
  arr: TJSONArray;
  i: Integer;
  item: TJSONData;
  obj: TJSONObject;
  nm: TJSONData;
begin
  Result := nil;
  arr := ArrOf(AValue);
  if arr = nil then Exit;
  SetLength(Result, arr.Count);
  for i := 0 to arr.Count - 1 do
  begin
    Result[i].Name := '';
    Result[i].DimType := '';
    item := arr.Items[i];
    if item = nil then Continue;
    if item.JSONType = jtString then
    begin
      Result[i].Name := item.AsString;
      Continue;
    end;
    obj := ObjOf(item);
    if obj = nil then Continue;
    nm := obj.Find('name');
    if (nm <> nil) and (nm.JSONType = jtString) then Result[i].Name := nm.AsString;
    nm := obj.Find('type');
    if (nm <> nil) and (nm.JSONType = jtString) then Result[i].DimType := nm.AsString;
    nm := obj.Find('displayName');
    if (nm <> nil) and (nm.JSONType = jtString) then Result[i].DisplayName := nm.AsString;
  end;
  { normalizeDimensionsOption: a named dimension's display name defaults to
    its name. }
  for i := 0 to High(Result) do
    if Result[i].DisplayName = '' then Result[i].DisplayName := Result[i].Name;
end;

{ The keys of the first object row, in order. Upstream collects from the first
  row only -- a second row with an extra key does not add a dimension. }
function ObjectRowDims(AData: TJSONArray): TTySourceDimArray;
var
  i, k, n: Integer;
  obj: TJSONObject;
begin
  Result := nil;
  if AData = nil then Exit;
  for i := 0 to AData.Count - 1 do
  begin
    obj := ObjOf(AData.Items[i]);
    if obj = nil then Continue;
    n := obj.Count;
    SetLength(Result, n);
    for k := 0 to n - 1 do
    begin
      Result[k].Name := obj.Names[k];
      Result[k].DimType := '';
    end;
    Exit;
  end;
end;

function TySourceOf(AOption: TTyChartOption; AIndex: Integer;
  ASeriesIndex: Integer; ACache: TTyDatasetCache): TTyChartSource;
var
  node, snode: TJSONObject;
  d: TJSONData;
  i, n: Integer;
  named: TTySourceDimArray;
  cell: TJSONData;

  { The series' answer, or the dataset's, or nothing -- in that order. }
  function Meta(const AKey: string): TJSONData;
  begin
    Result := nil;
    if snode <> nil then Result := snode.Find(AKey);
    if Result = nil then Result := node.Find(AKey);
  end;

begin
  Result := Default(TTyChartSource);
  Result.Format := tsfUnknown;
  Result.LayoutBy := slbColumn;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('dataset', AIndex));
  if node = nil then Exit;
  { A COMPUTED TABLE is read from the node its result is held in -- its own
    rows, dimensions and header rule, never the dataset's (upstream reads
    those off a root dataset only) [Batch 108] }
  if TyDatasetTruthy(node.Find('transform'))
    or TyDatasetTruthy(node.Find('fromTransformResult')) then
  begin
    if ACache = nil then Exit;
    node := ACache.ResultNode(AOption, AIndex, 0);
    if node = nil then Exit;
  end;
  snode := nil;
  if ASeriesIndex >= 0 then
    snode := ObjOf(AOption.ComponentAt('series', ASeriesIndex));

  d := node.Find('source');
  Result.Format := TyDetectSourceFormat(d);
  if Result.Format = tsfUnknown then Exit;
  if Result.Format = tsfKeyedColumns then
  begin
    { A TABLE OF COLUMNS BY NAME: its dimensions are the declared ones or,
      failing those, every key in order; a record is the i-th cell of each
      column; and there are as many as the FIRST dimension's column holds.
      No header and no layout -- both are questions about lines. }
    if not (d is TJSONObject) then Exit;
    Result.Keyed := TJSONObject(d);
    named := ReadDimensions(Meta('dimensions'));
    if named = nil then
    begin
      SetLength(named, Result.Keyed.Count);
      for i := 0 to Result.Keyed.Count - 1 do
      begin
        named[i].Name := Result.Keyed.Names[i];
        named[i].DimType := '';
        named[i].DisplayName := named[i].Name;
      end;
    end;
    Result.Dims := named;
    Result.DimCount := Length(named);
    Result.Valid := True;
    Exit;
  end;
  Result.Data := ArrOf(d);
  if Result.Data = nil then Exit;

  d := Meta('seriesLayoutBy');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'row') then
    Result.LayoutBy := slbRow;

  named := ReadDimensions(Meta('dimensions'));

  if Result.Format = tsfArrayRows then
  begin
    { THE HEADER, and only for a table of arrays. Every other shape carries its
      names elsewhere and reads from row 0. }
    d := Meta('sourceHeader');
    if d = nil then
      Result.StartIndex := DetectStartIndex(Result.Data, Result.LayoutBy)
    else if d.JSONType = jtNumber then
      Result.StartIndex := TyRoundOpt(d.AsFloat)
    else if d.JSONType = jtBoolean then
    begin
      if d.AsBoolean then Result.StartIndex := 1 else Result.StartIndex := 0;
    end
    else if (d.JSONType = jtString) and (d.AsString = 'auto') then
      Result.StartIndex := DetectStartIndex(Result.Data, Result.LayoutBy)
    else
      Result.StartIndex := 0;
    if Result.StartIndex < 0 then Result.StartIndex := 0;

    Result.DimCount := FirstLineLength(Result.Data, Result.LayoutBy);
    { THE NAMES COME OFF THE HEADER LINE ONLY WHEN THERE IS EXACTLY ONE HEADER
      ROW. `sourceHeader: 2` skips two rows and names nothing, which reads like
      an oversight and is what the code does. }
    if (named = nil) and (Result.StartIndex = 1) then
    begin
      n := FirstLineLength(Result.Data, Result.LayoutBy);
      SetLength(named, n);
      for i := 0 to n - 1 do
      begin
        cell := FirstLineCell(Result.Data, Result.LayoutBy, i);
        named[i].DimType := '';
        if (cell = nil) or (cell.JSONType = jtNull) then
          named[i].Name := ''
        else
          { A header cell can be anything JSON can hold, and `AsString`
            raises on the two that are not scalars. An unnameable dimension
            keeps its positional name. }
          if not (cell.JSONType in [jtObject, jtArray]) then
            named[i].Name := cell.AsString;
      end;
    end;
  end
  else if Result.Format = tsfObjectRows then
  begin
    if named = nil then named := ObjectRowDims(Result.Data);
    Result.DimCount := Length(named);
  end;

  Result.Dims := named;
  { A NAMED DIMENSION DISPLAYS AS ITS NAME, whoever named it -- the header,
    the object rows' keys, or `dimensions`. }
  for i := 0 to High(Result.Dims) do
    if Result.Dims[i].DisplayName = '' then
      Result.Dims[i].DisplayName := Result.Dims[i].Name;
  if Length(Result.Dims) > Result.DimCount then
    Result.DimCount := Length(Result.Dims);
  Result.Valid := True;
end;

function TySourceRowCount(const ASource: TTyChartSource): Integer;
var row: TJSONArray;
begin
  Result := 0;
  if not ASource.Valid then Exit;
  if ASource.Format = tsfKeyedColumns then
  begin
    if (ASource.Keyed = nil) or (Length(ASource.Dims) = 0) then Exit;
    row := ArrOf(ASource.Keyed.Find(ASource.Dims[0].Name));
    if row <> nil then Result := row.Count;
    Exit;
  end;
  if ASource.Data = nil then Exit;
  if ASource.Format = tsfObjectRows then Exit(ASource.Data.Count);
  { A table of arrays, minus its header. Under `row` layout a RECORD is a
    column, so the count is the length of the first row. }
  if ASource.LayoutBy = slbRow then
  begin
    if ASource.Data.Count = 0 then Exit;
    row := ArrOf(ASource.Data.Items[0]);
    if row = nil then Exit;
    Result := row.Count - ASource.StartIndex;
  end
  else
    Result := ASource.Data.Count - ASource.StartIndex;
  if Result < 0 then Result := 0;
end;

function TySourceCell(const ASource: TTyChartSource;
  ARow, ADim: Integer): TJSONData;
var
  row: TJSONArray;
  obj: TJSONObject;
  nm: string;
begin
  Result := nil;
  if not ASource.Valid then Exit;
  if (ARow < 0) or (ADim < 0) then Exit;
  if ASource.Format = tsfKeyedColumns then
  begin
    { The dimension's column, by name, and the record's cell in it. }
    if ASource.Keyed = nil then Exit;
    nm := TySourceDimName(ASource, ADim);
    if nm = '' then Exit;
    row := ArrOf(ASource.Keyed.Find(nm));
    if (row = nil) or (ARow >= row.Count) then Exit;
    Result := row.Items[ARow];
    Exit;
  end;
  if ASource.Data = nil then Exit;

  if ASource.Format = tsfObjectRows then
  begin
    { A CELL IS FETCHED BY NAME, not by position: an object row has no columns.
      A dimension the row does not carry is a gap, not a zero. }
    if ARow >= ASource.Data.Count then Exit;
    obj := ObjOf(ASource.Data.Items[ARow]);
    if obj = nil then Exit;
    nm := TySourceDimName(ASource, ADim);
    if nm = '' then Exit;
    Result := obj.Find(nm);
    Exit;
  end;

  if ASource.LayoutBy = slbRow then
  begin
    { Transposed: dimension ADim is a whole ROW, and the record is a column. }
    if ADim >= ASource.Data.Count then Exit;
    row := ArrOf(ASource.Data.Items[ADim]);
    if row = nil then Exit;
    if ARow + ASource.StartIndex >= row.Count then Exit;
    Result := row.Items[ARow + ASource.StartIndex];
    Exit;
  end;

  if ARow + ASource.StartIndex >= ASource.Data.Count then Exit;
  row := ArrOf(ASource.Data.Items[ARow + ASource.StartIndex]);
  if row = nil then Exit;
  if ADim >= row.Count then Exit;
  Result := row.Items[ADim];
end;

function TySourceDimName(const ASource: TTyChartSource; ADim: Integer): string;
begin
  Result := '';
  if (ADim < 0) or (ADim > High(ASource.Dims)) then Exit;
  Result := ASource.Dims[ADim].Name;
end;

function TySourceDimIndexOf(const ASource: TTyChartSource;
  const AName: string): Integer;
var i: Integer;
begin
  Result := -1;
  if AName = '' then Exit;
  for i := 0 to High(ASource.Dims) do
    if ASource.Dims[i].Name = AName then Exit(i);
end;

{ ==================== which dataset ==================== }

function TySeriesDatasetIndex(AOption: TTyChartOption;
  ASeriesIndex: Integer): Integer;
var
  node, ds: TJSONObject;
  d: TJSONData;
  i, n: Integer;
  wanted: string;
begin
  Result := -1;
  if AOption = nil then Exit;
  n := TyDatasetCount(AOption);
  if n = 0 then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if node = nil then Exit;

  { ITS OWN DATA WINS, and an EMPTY array still counts as its own data --
    `data: []` is a series that says it has none, not one that asks for the
    table. }
  d := node.Find('data');
  if (d <> nil) and (d is TJSONArray) then Exit;

  d := node.Find('datasetIndex');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result := TyRoundOpt(d.AsFloat);
    { AN INDEX NAMING NOTHING RESOLVES TO NOTHING. It does not fall back to the
      first dataset -- a chart that asked for dataset 3 and got dataset 0 would
      be drawing someone else's numbers. }
    if (Result < 0) or (Result >= n) then Result := -1;
    Exit;
  end;

  d := node.Find('datasetId');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    wanted := d.AsString;
    for i := 0 to n - 1 do
    begin
      ds := ObjOf(AOption.ComponentAt('dataset', i));
      if ds = nil then Continue;
      d := ds.Find('id');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString = wanted) then
        Exit(i);
    end;
    Exit(-1);
  end;

  { Neither: the first one. }
  Result := 0;
end;

{ ==================== encode ==================== }

function NewEncode(ACount: Integer): TTySeriesEncode;
var i: Integer;
begin
  Result := Default(TTySeriesEncode);
  SetLength(Result.Columns, ACount);
  SetLength(Result.Explicit, ACount);
  for i := 0 to ACount - 1 do
  begin
    Result.Columns[i] := -1;
    Result.Explicit[i] := False;
  end;
  Result.ItemName := -1;
  Result.SeriesName := -1;
end;

{ One `encode` value, resolved to a source dimension.

  A NUMBER IS AN INDEX AND A STRING IS A NAME -- including a string that looks
  like a number, which is looked up as a name and not parsed. A list hands back
  its first entry, because only slot 0 reaches a coordinate. }
function EncodeValue(AValue: TJSONData;
  const ASource: TTyChartSource): Integer;
var arr: TJSONArray;
begin
  Result := -1;
  if AValue = nil then Exit;
  if AValue is TJSONArray then
  begin
    arr := TJSONArray(AValue);
    if arr.Count = 0 then Exit;
    Exit(EncodeValue(arr.Items[0], ASource));
  end;
  if AValue.JSONType = jtNumber then Exit(TyRoundOpt(AValue.AsFloat));
  if AValue.JSONType = jtString then Exit(TySourceDimIndexOf(ASource, AValue.AsString));
end;

{ Every entry of an encode value, resolved: a number an index, a string a
  name; an entry that resolves to nothing, or a negative index, dropped. }
function EncodeList(AValue: TJSONData;
  const ASource: TTyChartSource): TTyIntegerArray;
var
  arr: TJSONArray;
  i, v: Integer;

  procedure One(AItem: TJSONData);
  begin
    v := -1;
    if AItem = nil then Exit;
    if AItem.JSONType = jtNumber then v := TyRoundOpt(AItem.AsFloat)
    else if AItem.JSONType = jtString then v := TySourceDimIndexOf(ASource, AItem.AsString);
    if v < 0 then Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := v;
  end;

begin
  Result := nil;
  if AValue = nil then Exit;
  if AValue is TJSONArray then
  begin
    arr := TJSONArray(AValue);
    for i := 0 to arr.Count - 1 do One(arr.Items[i]);
  end
  else
    One(AValue);
end;

procedure TyEncodeFillUnclaimed(var AEnc: TTySeriesEncode; ADimCount: Integer);
var
  i, j, avail: Integer;
  used: Boolean;
begin
  if not AEnc.Given then Exit;
  avail := 0;
  for i := 0 to High(AEnc.Columns) do
  begin
    if (i <= High(AEnc.Explicit)) and AEnc.Explicit[i] then Continue;
    if AEnc.Columns[i] >= 0 then Continue;
    repeat
      used := False;
      for j := 0 to High(AEnc.Columns) do
        if AEnc.Columns[j] = avail then used := True;
      if used then Inc(avail);
    until not used;
    if avail < ADimCount then
    begin
      AEnc.Columns[i] := avail;
      Inc(avail);
    end;
  end;
end;

function TySeriesDimsSource(AOption: TTyChartOption;
  ASeriesIndex: Integer): TTyChartSource;
var node: TJSONObject;
begin
  Result := Default(TTyChartSource);
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if node = nil then Exit;
  Result.Dims := ReadDimensions(node.Find('dimensions'));
  Result.DimCount := Length(Result.Dims);
end;

function TyEncodeOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ASource: TTyChartSource;
  const ACoordDims: TTyCoordDimArray): TTySeriesEncode;
var
  node, enc: TJSONObject;
  d: TJSONData;
  i: Integer;
begin
  Result := NewEncode(Length(ACoordDims));
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if node = nil then Exit;
  enc := ObjOf(node.Find('encode'));
  if enc = nil then Exit;

  { GIVEN AT ALL, which is the thing that matters: a partial encode does not
    merge with the defaulter, it REPLACES it. `encode: { x: 0 }` on the third
    series of a dataset leaves y to fall back positionally rather than to the
    column the first two series' counter would have handed it. }
  Result.Given := True;
  for i := 0 to High(ACoordDims) do
  begin
    d := enc.Find(ACoordDims[i].Name);
    if d <> nil then
    begin
      Result.Columns[i] := EncodeValue(d, ASource);
      Result.Explicit[i] := True;
    end;
  end;
  Result.Tooltip := EncodeList(enc.Find('tooltip'), ASource);
  Result.Labels := EncodeList(enc.Find('label'), ASource);
  d := enc.Find('itemName');
  if d <> nil then Result.ItemName := EncodeValue(d, ASource);
  d := enc.Find('seriesName');
  if d <> nil then Result.SeriesName := EncodeValue(d, ASource);
  { `value` is a pie's word for the number it draws, and it lands on the one
    coordinate a pie has. }
  if (Length(ACoordDims) = 1) and (Result.Columns[0] < 0) then
  begin
    d := enc.Find('value');
    if d <> nil then Result.Columns[0] := EncodeValue(d, ASource);
  end;
end;

function TyEncodeCursorFor(var AList: TTyEncodeCursorArray;
  ADatasetIndex: Integer; ALayoutBy: TTySeriesLayoutBy): Integer;
var i, n: Integer;
begin
  for i := 0 to High(AList) do
    if (AList[i].DatasetIndex = ADatasetIndex)
      and (AList[i].LayoutBy = ALayoutBy) then Exit(i);
  n := Length(AList);
  SetLength(AList, n + 1);
  AList[n] := Default(TTyEncodeCursor);
  AList[n].DatasetIndex := ADatasetIndex;
  AList[n].LayoutBy := ALayoutBy;
  Result := n;
end;

function TyDefaultEncodeAxis(var ACursor: TTyEncodeCursor;
  const ACoordDims: TTyCoordDimArray): TTySeriesEncode;
var
  i, baseCat: Integer;
begin
  Result := NewEncode(Length(ACoordDims));
  if Length(ACoordDims) = 0 then Exit;

  baseCat := -1;
  for i := 0 to High(ACoordDims) do
    if ACoordDims[i].Ordinal then
    begin
      baseCat := i;
      Break;
    end;

  { THE CURSOR IS SEEDED BY THE FIRST SERIES TO ASK and never re-seeded. Two
    series with different coordinate shapes on one dataset therefore share one
    starting point, which is upstream's arrangement rather than an oversight:
    the whole point of the counter is that the series divide the table between
    them. }
  if not ACursor.Seeded then
  begin
    ACursor.Seeded := True;
    ACursor.ValueWay := 0;
    if baseCat >= 0 then ACursor.CategoryWay := 1 else ACursor.CategoryWay := 0;
  end;

  for i := 0 to High(ACoordDims) do
  begin
    if baseCat < 0 then
    begin
      { VALUE WAY: every coordinate of every series takes the next dimension. }
      Result.Columns[i] := ACursor.ValueWay;
      if Result.SeriesName < 0 then Result.SeriesName := ACursor.ValueWay;
      Inc(ACursor.ValueWay);
    end
    else if i = baseCat then
    begin
      { The shared category, dimension 0 whichever axis it is on. }
      Result.Columns[i] := 0;
      Result.ItemName := 0;
    end
    else
    begin
      Result.Columns[i] := ACursor.CategoryWay;
      if Result.SeriesName < 0 then Result.SeriesName := ACursor.CategoryWay;
      Inc(ACursor.CategoryWay);
    end;
  end;
end;

{ Does this cell read as a category rather than a number? }
function CellIsOrdinal(ACell: TJSONData; out AKnown: Boolean): Boolean;
var s: string;
    v: Double;
    fs: TFormatSettings;
begin
  Result := False;
  AKnown := False;
  if (ACell = nil) or (ACell.JSONType = jtNull) then Exit;
  if ACell.JSONType = jtNumber then
  begin
    AKnown := True;
    Exit(False);
  end;
  if ACell.JSONType <> jtString then Exit;
  s := Trim(ACell.AsString);
  { `-` is a gap and says nothing either way. }
  if (s = '') or (s = '-') then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  AKnown := True;
  Result := not TryStrToFloat(s, v, fs);
end;

function TySourceDimIsOrdinal(const ASource: TTyChartSource;
  ADim: Integer): Boolean;
var
  i, n: Integer;
  known: Boolean;
  ord_: Boolean;
begin
  Result := False;
  if not ASource.Valid then Exit;
  { A DECLARED TYPE ENDS THE QUESTION. }
  if (ADim >= 0) and (ADim <= High(ASource.Dims))
    and (ASource.Dims[ADim].DimType <> '') then
    Exit(ASource.Dims[ADim].DimType = 'ordinal');
  n := TySourceRowCount(ASource);
  if n > cGuessScan then n := cGuessScan;
  for i := 0 to n - 1 do
  begin
    ord_ := CellIsOrdinal(TySourceCell(ASource, i, ADim), known);
    if known then Exit(ord_);
  end;
end;

function TyDefaultEncodeNameBased(const ASource: TTyChartSource;
  ADimCount: Integer): TTySeriesEncode;
var
  i, n, nameDim, valueDim, literalName: Integer;
begin
  Result := NewEncode(1);
  if not ASource.Valid then Exit;
  n := ADimCount;
  if n > cGuessScan then n := cGuessScan;

  { A DIMENSION LITERALLY CALLED `name` WINS OUTRIGHT, and only for the shapes
    that carry names of their own. }
  literalName := -1;
  if ASource.Format = tsfObjectRows then
    literalName := TySourceDimIndexOf(ASource, 'name');

  nameDim := -1;
  valueDim := -1;
  for i := 0 to n - 1 do
  begin
    if TySourceDimIsOrdinal(ASource, i) then
    begin
      if nameDim < 0 then nameDim := i;
    end
    else
      if (valueDim < 0) and (i <> literalName) then valueDim := i;
  end;
  if literalName >= 0 then nameDim := literalName;
  { Nothing looked like a name: the first dimension is one anyway, which is
    what a two-column table of `label, number` wants. }
  if (nameDim < 0) and (ADimCount > 1) then nameDim := 0;
  if valueDim < 0 then
  begin
    if (nameDim = 0) and (ADimCount > 1) then valueDim := 1 else valueDim := 0;
  end;

  Result.Given := False;
  Result.Columns[0] := valueDim;
  Result.ItemName := nameDim;
end;

end.
