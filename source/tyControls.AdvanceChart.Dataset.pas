unit tyControls.AdvanceChart.Dataset;
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
    upstream throws.] [Batch 133: the registry, 'filter' and 'sort' are in
    tyControls.AdvanceChart.DataTransform; this unit keeps the chain. A dataset
    whose transform fails has no table and a reason (ErrorOf), which the
    control reports as a diagnostic -- upstream throws out of setOption.]

    TYPED ARRAYS, which cannot survive a trip through JSON, and KEYED COLUMNS
    (`{ product: [...], 2015: [...] }`), which no corpus example uses. Both
    detect correctly and then answer no rows, which is what a chart with an
    unreadable source should draw.

  PURE: SysUtils, Math, fpjson and the AdvanceChart units. }
interface
uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option;

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
    { [spec 255] a table of lines whose `dimensions` are written: upstream
      counts those (dimensionsDetectedCount is their length, [] none), not
      the line's cells -- what an encode index is held against }
    DimsWritten: Boolean;
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
    { `encode.tooltip` and `encode.label` as createDimensions leaves them
      (summarizeDimensions' encode.tooltip / encode.label): each dimension at
      the LAST place the list names it, -1 for a place nothing reached -- a
      name the table does not have, or a dimension named again further on.
      `[1, 'b', 3]` is (1, -1, 3), `[1, 3, 1]` is (-1, 3, 1). A tooltip skips
      a gap but counts it; a label prints the whole raw item there.
      [spec 255: was every entry resolved, the unresolved ones dropped] }
    Tooltip, Labels: array of Integer;
    { `itemName`: the dimension the list names FIRST and not again
      (SeriesData's `otherDims.itemName === 0`), -1 for none. `['nope', 'g']`
      names none. HasNameEncode: the list reached any dimension at all, which
      takes the category's name away from the rows (injectOrdinalMeta's
      hasNameEncode) [spec 255]. }
    ItemName: Integer;
    HasNameEncode: Boolean;
    { A DEFAULT encode's series name dimension, -1 for none; a written one is
      SeriesNames: every dimension the list reaches, in its order, gaps
      dropped -- the series is named their display names joined by a space
      (getSeriesAutoName) [spec 255: was the first entry alone]. }
    SeriesName: Integer;
    SeriesNames: array of Integer;
    { [spec 255] A COORDINATE WRITTEN AS A LIST holds every dimension it
      reaches: entry 0 is Columns' (-1 when it reached none -- mapDimension
      answers nothing then), and every one past the coordinate system's own
      columns is an extra one here: ExtraDim the source dimension, ExtraCoord
      the column of the coordinate it belongs to, ExtraIndex its place in the
      list. They size the axis, can be the series' label and the stacked
      dimension, and collect categories. }
    ExtraCoord, ExtraDim, ExtraIndex: array of Integer;
    { Per source dimension: some coordinate of the encode -- written in it,
      not a tooltip, label or name -- holds it, so no unwritten coordinate is
      filled from it. }
    Claimed: array of Boolean;
    { The dimensions a key no coordinate system asks for holds (`value` on a
      scatter, any other word): coordinates all the same, so the label may
      be one of them. }
    Others: array of Integer;
  end;

  { One coordinate of a series, as this unit needs it: what it is called and
    whether its axis is a category one. Deliberately not the builder's own
    dimension record -- that unit reads this one, so it cannot also define what
    this one takes. }
  TTyCoordDim = record
    Name: string;
    Ordinal: Boolean;
    { [spec 255] the encode key this column answers to and its place in that
      key's list: a candlestick's open, close, lowest and highest are 'y' 0
      to 3. '' (and 0) is the column's own name. }
    Key: string;
    Index: Integer;
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
    nil here, and the series reading it draws nothing.
    [Batch 133: the registry is tyControls.AdvanceChart.DataTransform's
    (TyRegisterDataTransform; 'filter', 'sort' and 'boxplot' are built in).
    A dataset upstream throws on keeps the reason (ErrorOf), and so does
    every dataset reading it; an upstream reference that finds nothing makes
    the dataset a root one, as the source manager does; a result index past
    a dataset's own results is its upstream's (getSource's fallback).] }
  TTyJSONObjectArray = array of TJSONObject;

  { ONE RESULT OF A DATASET [Batch 133]: the node its table is read from and
    whether it is a `fromTransformResult` COPY. upstream's cloneSourceShallow
    keeps the table, its header count and its names, and drops the raw
    `seriesLayoutBy` / `sourceHeader` / `dimensions` -- so a series reading
    a copy guesses the header again, and a transform whose first result
    would inherit the copy's dimensions throws. Node nil is no result. }
  TTySourceRef = record
    Node: TJSONObject;
    IsClone: Boolean;
  end;
  TTySourceRefArray = array of TTySourceRef;

  TTyDatasetCache = class
  private
    FOption: TTyChartOption;
    { per dataset: its results (nil when it has none) }
    FResults: array of TTySourceRefArray;
    { per dataset: the datasets it reads (queryDatasetUpstreamDatasetModels;
      none for a root) -- getSource's fallback walks the first }
    FUps: array of TTyIntegerArray;
    { per dataset: why it has no table, '' when it has one [Batch 133] }
    FErrors: array of string;
    { per dataset: 0 not looked at, 1 being resolved, 2 resolved }
    FState: array of Byte;
    FOwned: TFPList;
    { THE Math.random the transforms draw from [Batch 134]: FRandom when
      nobody lent one, reseeded with TyJitterSeed on every reset }
    FRandom: LongWord;
    FRandomPtr: PLongWord;
    function GetRandomState: PLongWord;
    procedure Reset(AOption: TTyChartOption);
    procedure Resolve(AIndex: Integer);
    function UpstreamsOf(ANode: TJSONObject): TTyIntegerArray;
    function SourceAt(AIndex, AResult: Integer): TTySourceRef;
    procedure Sync(AOption: TTyChartOption);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { The node result AResult of dataset AIndex is read from, or nil. }
    function ResultNode(AOption: TTyChartOption; AIndex, AResult: Integer): TJSONObject;
    { Whether that result is a fromTransformResult copy [Batch 133]. }
    function ResultIsClone(AOption: TTyChartOption; AIndex, AResult: Integer): Boolean;
    { The node a SERIES reading dataset AIndex reads: getSource(0), which
      falls back to the upstream's when the dataset has no result 0. }
    function SeriesNode(AOption: TTyChartOption; AIndex: Integer;
      out AIsClone: Boolean): TJSONObject;
    { How many results dataset AIndex has (resolving it). }
    function ResultCount(AOption: TTyChartOption; AIndex: Integer): Integer;
    { Why dataset AIndex has no table -- '' when it has one or has not been
      resolved yet. Does not resolve. [Batch 133] }
    function ErrorOf(AIndex: Integer): string;
    { How many datasets the cache was last reset for. }
    function DatasetCount: Integer;
    { THE STATE THE TRANSFORMS DRAW FROM [Batch 134] -- ecStat's k-means
      calls Math.random. Lend the chart's (the control does, so a
      clustering draws where upstream's setOption would); nil, the default,
      is the cache's own, seeded with TyJitterSeed whenever the cache starts
      afresh. Clear leaves a lent state lent. }
    property RandomState: PLongWord read GetRandomState write FRandomPtr;
  end;

  { ONE NAMED DIMENSION as createSource leaves it (normalizeDimensionsOption):
    a name made a string, a display name defaulting to it, and a name used
    twice given a '-1', '-2' suffix. [Batch 133] }
  TTyNormDim = record
    HasName: Boolean;
    Name: string;
    HasDisplayName: Boolean;
    DisplayName: string;
  end;
  TTyNormDimArray = array of TTyNormDim;

  { WHAT createSource MAKES OF A NODE (Source.ts, determineSourceDimensions)
    -- the fields a transform's upstream is built from. DimsDefined is
    upstream's `dimensionsDefine` being there at all: an empty list is
    defined. DetectedCount is -1 for null. Data is borrowed. [Batch 133] }
  TTySourceFields = record
    Format: TTySourceFormat;
    LayoutBy: TTySeriesLayoutBy;
    StartIndex: Integer;
    DimsDefined: Boolean;
    Dims: TTyNormDimArray;
    DetectedCount: Integer;
    Data: TJSONData;
  end;

{ How many `dataset` components the option carries. }
function TyDatasetCount(AOption: TTyChartOption): Integer;

{ JavaScript's String() of an option value: a number as it prints, a
  boolean as its word, null 'null', a list joined by commas (a null or an
  absent element as nothing), an object '[object Object]'. nil is
  'undefined'. [Batch 133] }
function TyJsTextOf(AData: TJSONData): string;

{ normalizeDimensionsOption over a `dimensions` value: nil when it is not a
  list. [Batch 133] }
function TyNormalizeDims(AValue: TJSONData): TTyNormDimArray;

{ The fields createSource computes for a node holding `source`,
  `seriesLayoutBy`, `sourceHeader` and `dimensions` -- a root dataset, or a
  transform's result. [Batch 133] }
function TySourceFieldsOf(ANode: TJSONObject): TTySourceFields;

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
  string with its FIRST value placeholder replaced by the row index; [R2-J2]
  a '@Name' -- upstream's function -- the registered formatter handed
  `{value: i}` (params.Values [i]); anything else, the index. A sample is a number as JavaScript's subtraction reads it.

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

  A VALUE MAY BE AN INDEX, A NAME, OR A LIST OF EITHER, and every entry of a
  list is resolved, as createDimensions resolves them [spec 255: was the
  first entry alone]. An entry reaches a dimension when it is a name the
  source has or a whole index below the dimension count -- Max(the source's,
  ADimCount, the coordinates', 1); one that reaches none is a gap. A
  coordinate whose list reaches nothing is not written (the next free
  dimension fills it); a lone negative number asks for no mapping. }
function TyEncodeOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ASource: TTyChartSource;
  const ACoordDims: TTyCoordDimArray; ADimCount: Integer = -1): TTySeriesEncode;

{ [spec 255] The dimension a visual encode list (itemName, itemGroupId,
  itemChildGroupId) gives slot 0 -- its first entry, unless that entry is
  -1 or its dimension is named again further on (the last place wins) --
  from the entries resolved, -1 for each that reaches nothing. }
function TyEncodeFirstSlot(const AEntries: array of Integer): Integer;

{ upstream's createDimensions for a GIVEN encode: every coordinate not
  written in it takes, in coordinate order, the first dimension below
  ADimCount that no coordinate holds yet. `encode: {y: 2}` on a table reads
  x from 0; `encode: {tooltip: [2]}` leaves x on 0 and y on 1. }
procedure TyEncodeFillUnclaimed(var AEnc: TTySeriesEncode; ADimCount: Integer);
{ [spec 242] createDimensions over a default encode: an index past the
  table's dimensions is no dimension, and a coordinate left with none takes
  the first one no coordinate holds (the second of two series on a
  three-column table: x the third column, y the first) }
procedure TyEncodeDropPast(var AEnc: TTySeriesEncode; ADimCount: Integer);

{ [spec 255] The dimensions createDimensions counts for a source:
  `dimensions` written on a table of lines, their number; else DimCount. }
function TySourceEncodeDimCount(const ASource: TTyChartSource): Integer;

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

uses tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Scale,
  tyControls.AdvanceChart.DataTransform, tyControls.AdvanceChart.Jitter,
  tyControls.AdvanceChart.Handlers, tyControls.StrConsts;

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

function TyJsTextOf(AData: TJSONData): string;
var i: Integer;
begin
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtString: Result := AData.AsString;
    jtArray:
      begin
        Result := '';
        for i := 0 to TJSONArray(AData).Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          if TJSONArray(AData).Items[i].JSONType <> jtNull then
            Result := Result + TyJsTextOf(TJSONArray(AData).Items[i]);
        end;
      end;
  else
    Result := '[object Object]';
  end;
end;

function TyNormalizeDims(AValue: TJSONData): TTyNormDimArray;
var
  arr: TJSONArray;
  i, j, k: Integer;
  item, nm, dn: TJSONData;
  seenNames: TStringList;
begin
  Result := nil;
  arr := ArrOf(AValue);
  if arr = nil then Exit;
  SetLength(Result, arr.Count);
  { nameMap: how many times an ORIGINAL name was seen -- a suffixed name is
    not entered, so ['a', 'a', 'a-1'] ends with two 'a-1' }
  seenNames := TStringList.Create;
  try
    { by bytes, as upstream keys a name: the locale compare took
      U+00C5 and U+212B for one letter, and whatever came after [P2] }
    seenNames.UseLocale := False;
    seenNames.Sorted := True;
    seenNames.Duplicates := dupIgnore;
    seenNames.CaseSensitive := True;
    for i := 0 to arr.Count - 1 do
    begin
      Result[i] := Default(TTyNormDim);
      item := arr.Items[i];
      { an object is the definition and anything else is its name -- a list
        is an object too, and has no name }
      if item.JSONType in [jtObject, jtArray] then
      begin
        nm := nil;
        dn := nil;
        if item is TJSONObject then
        begin
          nm := TJSONObject(item).Find('name');
          dn := TJSONObject(item).Find('displayName');
        end;
      end
      else
      begin
        nm := item;
        dn := nil;
      end;
      if (dn <> nil) and (dn.JSONType <> jtNull) then
      begin
        Result[i].HasDisplayName := True;
        Result[i].DisplayName := TyJsTextOf(dn);
      end;
      if (nm = nil) or (nm.JSONType = jtNull) then Continue;
      Result[i].HasName := True;
      Result[i].Name := TyJsTextOf(nm);
      if not Result[i].HasDisplayName then
      begin
        Result[i].HasDisplayName := True;
        Result[i].DisplayName := Result[i].Name;
      end;
      if seenNames.Find(Result[i].Name, j) then
      begin
        k := PtrInt(seenNames.Objects[j]);
        seenNames.Objects[j] := TObject(PtrInt(k + 1));
        Result[i].Name := Result[i].Name + '-' + IntToStr(k);
      end
      else
        seenNames.AddObject(Result[i].Name, TObject(PtrInt(1)));
    end;
  finally
    seenNames.Free;
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

type
  { (a, b) => a - b over the samples, a not-a-number difference a tie }
  TAscCompare = class
    Vals: TTyDoubleArray;
    function Compare(A, B: Integer): Integer;
  end;

function TAscCompare.Compare(A, B: Integer): Integer;
var d: Double;
begin
  d := Vals[A] - Vals[B];
  if IsNan(d) then Result := 0
  else if d < 0 then Result := -1
  else if d > 0 then Result := 1
  else Result := 0;
end;

{ asc(): Array.prototype.sort with (a, b) => a - b -- V8's TimSort
  (TyJsArraySort), so a sample that is no number lands where V8 leaves it:
  its comparisons are ties, and the binary insertion and the runs place it
  [R5-G: was a linear insertion sort, the same order only while every
  comparison is a number] }
procedure SortAsc(var A: TTyDoubleArray);
var
  cmp: TAscCompare;
  idx: TTyIntegerArray;
  i: Integer;
  mask: TFPUExceptionMask;
begin
  if Length(A) < 2 then Exit;
  idx := nil;
  SetLength(idx, Length(A));
  for i := 0 to High(idx) do idx[i] := i;
  cmp := TAscCompare.Create;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    cmp.Vals := Copy(A);
    TyJsArraySort(idx, @cmp.Compare);
    for i := 0 to High(idx) do A[i] := cmp.Vals[idx[i]];
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
    cmp.Free;
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
  prm: TTyChartCallbackParams;
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
    { [R2-J2] isFunction(itemNameFormatter): itemNameFormatter({value: i}) --
      boxplot-light-velocity2 names its boxes 'expr 0' ... that way }
    if (fmt <> nil) and (fmt.JSONType = jtString) and TyChartIsHandlerRef(fmt.AsString) then
    begin
      prm := TyChartBlankParams;
      SetLength(prm.Values, 1);
      prm.Values[0] := i;
      prm.ValueText := IntToStr(i);
      name := TyChartRunHandler(fmt.AsString, TyChartOneParams(prm));
    end
    { the FIRST placeholder only -- String.prototype.replace with a string }
    else if (fmt <> nil) and (fmt.JSONType = jtString) then
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
  FRandom := TyJitterSeed;
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
  FUps := nil;
  FErrors := nil;
  FState := nil;
  FOption := nil;
end;

procedure TTyDatasetCache.Reset(AOption: TTyChartOption);
var n: Integer;
begin
  Clear;
  FOption := AOption;
  FRandom := TyJitterSeed;
  n := TyDatasetCount(AOption);
  SetLength(FResults, n);
  SetLength(FUps, n);
  SetLength(FErrors, n);
  SetLength(FState, n);
end;

{ A DIFFERENT OPTION, or one grown since, starts afresh }
procedure TTyDatasetCache.Sync(AOption: TTyChartOption);
begin
  if (AOption <> FOption) or (Length(FResults) <> TyDatasetCount(AOption)) then
    Reset(AOption);
end;

function TTyDatasetCache.ResultNode(AOption: TTyChartOption;
  AIndex, AResult: Integer): TJSONObject;
begin
  Result := nil;
  if AOption = nil then Exit;
  Sync(AOption);
  if (AIndex < 0) or (AIndex > High(FResults)) then Exit;
  Resolve(AIndex);
  if (AResult < 0) or (AResult > High(FResults[AIndex])) then Exit;
  Result := FResults[AIndex][AResult].Node;
end;

function TTyDatasetCache.ResultIsClone(AOption: TTyChartOption;
  AIndex, AResult: Integer): Boolean;
begin
  Result := False;
  if ResultNode(AOption, AIndex, AResult) = nil then Exit;
  Result := FResults[AIndex][AResult].IsClone;
end;

function TTyDatasetCache.SeriesNode(AOption: TTyChartOption; AIndex: Integer;
  out AIsClone: Boolean): TJSONObject;
var r: TTySourceRef;
begin
  Result := nil;
  AIsClone := False;
  if AOption = nil then Exit;
  Sync(AOption);
  if (AIndex < 0) or (AIndex > High(FResults)) then Exit;
  Resolve(AIndex);
  if FErrors[AIndex] <> '' then Exit;
  r := SourceAt(AIndex, 0);
  Result := r.Node;
  AIsClone := r.IsClone;
end;

function TTyDatasetCache.ResultCount(AOption: TTyChartOption;
  AIndex: Integer): Integer;
begin
  Result := 0;
  if AOption = nil then Exit;
  Sync(AOption);
  if (AIndex < 0) or (AIndex > High(FResults)) then Exit;
  Resolve(AIndex);
  Result := Length(FResults[AIndex]);
end;

function TTyDatasetCache.ErrorOf(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(FErrors)) then Exit;
  if FState[AIndex] <> 2 then Exit;
  Result := FErrors[AIndex];
end;

function TTyDatasetCache.DatasetCount: Integer;
begin
  Result := Length(FResults);
end;

function TTyDatasetCache.GetRandomState: PLongWord;
begin
  if FRandomPtr <> nil then Result := FRandomPtr else Result := @FRandom;
end;

{ queryDatasetUpstreamDatasetModels through queryReferringComponents with
  SINGLE_REFERRING: `fromDatasetIndex` when it is not null -- a number, a
  list of them, a string naming an index -- else `fromDatasetId` (a string
  or a number compared as text, or a list of them), else dataset 0. An
  index naming nothing is left out, so a list can shrink to nothing.
  [Batch 133: a list and a string index were read as nothing.] }
function TTyDatasetCache.UpstreamsOf(ANode: TJSONObject): TTyIntegerArray;
var
  d, idd: TJSONData;
  i, k, n: Integer;
  ds: TJSONObject;

  procedure Push(AIdx: Integer);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AIdx;
  end;

  { `cmpts[idx]`: a number that is a whole index, or a string that is an
    array index as written }
  procedure ByIndex(AItem: TJSONData);
  var v: Double; s: string; c: Integer;
  begin
    if AItem = nil then Exit;
    if AItem.JSONType = jtNumber then
    begin
      v := AItem.AsFloat;
      if IsNan(v) or (v < 0) or (v >= n) or (Frac(v) <> 0) then Exit;
      Push(Trunc(v));
    end
    else if AItem.JSONType = jtString then
    begin
      s := AItem.AsString;
      if (s = '') or (Length(s) > 9) then Exit;
      if (Length(s) > 1) and (s[1] = '0') then Exit;
      for c := 1 to Length(s) do
        if not (s[c] in ['0'..'9']) then Exit;
      if StrToInt(s) < n then Push(StrToInt(s));
    end;
  end;

  function IdMatches(const AWant: string): Integer;
  var j: Integer;
  begin
    for j := 0 to n - 1 do
    begin
      ds := ObjOf(FOption.ComponentAt('dataset', j));
      if ds = nil then Continue;
      idd := ds.Find('id');
      if (idd <> nil) and (idd.JSONType in [jtString, jtNumber])
        and (TyJsTextOf(idd) = AWant) then Exit(j);
    end;
    Result := -1;
  end;

begin
  Result := nil;
  n := Length(FResults);
  d := ANode.Find('fromDatasetIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
      for k := 0 to TJSONArray(d).Count - 1 do ByIndex(TJSONArray(d).Items[k])
    else
      ByIndex(d);
    Exit;
  end;
  d := ANode.Find('fromDatasetId');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
    begin
      { a filter over the components: each once, in component order }
      for i := 0 to n - 1 do
        for k := 0 to TJSONArray(d).Count - 1 do
          if (TJSONArray(d).Items[k].JSONType in [jtString, jtNumber])
            and (IdMatches(TyJsTextOf(TJSONArray(d).Items[k])) = i) then
          begin
            Push(i);
            Break;
          end;
    end
    else if d.JSONType in [jtString, jtNumber] then
    begin
      k := IdMatches(TyJsTextOf(d));
      if k >= 0 then Push(k);
    end;
    Exit;
  end;
  if n > 0 then Push(0);
end;

{ SourceManager.getSource(k): this dataset's k-th result, or -- when it has
  none -- its first upstream's k-th, and so on up the chain }
function TTyDatasetCache.SourceAt(AIndex, AResult: Integer): TTySourceRef;
var guard: Integer;
begin
  Result := Default(TTySourceRef);
  guard := 0;
  while (AIndex >= 0) and (AIndex <= High(FResults)) and (guard <= Length(FResults)) do
  begin
    if (AResult >= 0) and (AResult <= High(FResults[AIndex]))
      and (FResults[AIndex][AResult].Node <> nil) then
      Exit(FResults[AIndex][AResult]);
    if Length(FUps[AIndex]) = 0 then Exit;
    AIndex := FUps[AIndex][0];
    Inc(guard);
  end;
end;

procedure TTyDatasetCache.Resolve(AIndex: Integer);
var
  node: TJSONObject;
  tr, ftr: TJSONData;
  ups: TTyIntegerArray;
  i, ri: Integer;
  ftrGiven: Boolean;
  r: Double;
  s, err: string;
  upSrcs, outs: TTySourceRefArray;
  one: TTySourceRef;

  procedure Fail(const AWhy: string);
  begin
    FResults[AIndex] := nil;
    FErrors[AIndex] := AWhy;
  end;

begin
  if FState[AIndex] <> 0 then Exit;
  FState[AIndex] := 1;
  try
    FResults[AIndex] := nil;
    FErrors[AIndex] := '';
    FUps[AIndex] := nil;
    node := ObjOf(FOption.ComponentAt('dataset', AIndex));
    if node = nil then Exit;
    tr := node.Find('transform');
    ftr := node.Find('fromTransformResult');
    one.Node := node;
    one.IsClone := False;
    { A ROOT DATASET: `!transform && !fromTransformResult` -- a
      fromTransformResult of 0 alone is a root one too }
    if not (TyDatasetTruthy(tr) or TyDatasetTruthy(ftr)) then
    begin
      SetLength(FResults[AIndex], 1);
      FResults[AIndex][0] := one;
      Exit;
    end;
    ups := UpstreamsOf(node);
    { NO UPSTREAM FOUND IS NO UPSTREAM AT ALL: the source manager treats the
      dataset as a root one and reads its own `source` [Batch 133] }
    if Length(ups) = 0 then
    begin
      SetLength(FResults[AIndex], 1);
      FResults[AIndex][0] := one;
      Exit;
    end;
    FUps[AIndex] := ups;
    ftrGiven := (ftr <> nil) and (ftr.JSONType <> jtNull);
    if ftrGiven and (Length(ups) <> 1) then
    begin
      Fail(rsTyDsOneUpstream);
      Exit;
    end;
    { getSource(fromTransformResult || 0): a whole number, or a string that
      is an index as written; anything else names no result }
    ri := 0;
    if TyDatasetTruthy(ftr) then
    begin
      ri := -1;
      if ftr.JSONType = jtNumber then
      begin
        r := ftr.AsFloat;
        if (r >= 0) and (Frac(r) = 0) and (r < MaxInt) then ri := Trunc(r);
      end
      else if ftr.JSONType = jtString then
      begin
        s := ftr.AsString;
        if (s <> '') and (Length(s) <= 9) and not ((Length(s) > 1) and (s[1] = '0')) then
        begin
          ri := 0;
          for i := 1 to Length(s) do
            if not (s[i] in ['0'..'9']) then ri := -1;
          if ri = 0 then ri := StrToInt(s);
        end;
      end;
    end;
    SetLength(upSrcs, Length(ups));
    for i := 0 to High(ups) do
    begin
      { A CYCLE: upstream recurses until the stack runs out }
      if (ups[i] = AIndex) or (FState[ups[i]] = 1) then
      begin
        Fail(rsTyDsReadsItself);
        Exit;
      end;
      Resolve(ups[i]);
      if FErrors[ups[i]] <> '' then
      begin
        Fail(Format(rsTyDsUpstreamFailed, [ups[i]]));
        Exit;
      end;
      upSrcs[i] := SourceAt(ups[i], ri);
      if ftrGiven and (upSrcs[i].Node = nil) then
      begin
        Fail(Format(rsTyDsNoResult, [TyJsTextOf(ftr)]));
        Exit;
      end;
    end;
    if TyDatasetTruthy(tr) then
    begin
      if not TyApplyDataTransform(tr, upSrcs, FOwned, outs, err, GetRandomState) then
      begin
        Fail(err);
        Exit;
      end;
      FResults[AIndex] := outs;
    end
    else
    begin
      { cloneSourceShallow: the upstream's table, header count and names,
        without its raw meta }
      SetLength(FResults[AIndex], 1);
      FResults[AIndex][0].Node := upSrcs[0].Node;
      FResults[AIndex][0].IsClone := True;
    end;
  finally
    FState[AIndex] := 2;
  end;
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
  ownMeta, isClone, dimsGiven: Boolean;

  { The series' answer, or the dataset's, or nothing -- in that order. A
    series reading a fromTransformResult COPY has only its own: the copy
    carries no raw meta, so upstream builds the series' source from the
    series' answers alone [Batch 133]. A null is no answer (retrieve2's
    `!= null`): the dataset's is asked then [was: the series' null won]. }
  function Meta(const AKey: string): TJSONData;
  begin
    Result := nil;
    if snode <> nil then Result := snode.Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
    if (Result = nil) and ownMeta then Result := node.Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
  end;

begin
  Result := Default(TTyChartSource);
  Result.Format := tsfUnknown;
  Result.LayoutBy := slbColumn;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('dataset', AIndex));
  if node = nil then Exit;
  ownMeta := True;
  { A COMPUTED TABLE is read from the node its result is held in -- its own
    rows, dimensions and header rule, never the dataset's (upstream reads
    those off a root dataset only) [Batch 108] }
  if TyDatasetTruthy(node.Find('transform'))
    or TyDatasetTruthy(node.Find('fromTransformResult')) then
  begin
    if ACache = nil then Exit;
    node := ACache.SeriesNode(AOption, AIndex, isClone);
    if node = nil then Exit;
    if ASeriesIndex >= 0 then ownMeta := not isClone;
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
    if not TyDatasetTruthy(Meta('dimensions')) then
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
  { WRITTEN IS `dimensionsDefine` TRUTHY (Source.ts' `!dimensionsDefine`):
    an empty list is written and names nothing -- the header names nothing
    then, nor do the object rows' keys [was: an empty list, read to no
    names, was as none written] }
  dimsGiven := TyDatasetTruthy(Meta('dimensions'));

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
    else if d.JSONType = jtNull then
      Result.StartIndex := DetectStartIndex(Result.Data, Result.LayoutBy)
    else if TyDatasetTruthy(d) then
      { `sourceHeader ? 1 : 0` -- any other truthy value is one line
        [Batch 133: a string other than 'auto' was none] }
      Result.StartIndex := 1
    else
      Result.StartIndex := 0;
    if Result.StartIndex < 0 then Result.StartIndex := 0;

    Result.DimCount := FirstLineLength(Result.Data, Result.LayoutBy);
    Result.DimsWritten := dimsGiven;
    { THE NAMES COME OFF THE HEADER LINE ONLY WHEN THERE IS EXACTLY ONE HEADER
      ROW. `sourceHeader: 2` skips two rows and names nothing, which reads like
      an oversight and is what the code does. }
    if (not dimsGiven) and (Result.StartIndex = 1) then
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
    if not dimsGiven then named := ObjectRowDims(Result.Data);
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

function TySourceFieldsOf(ANode: TJSONObject): TTySourceFields;
var
  d, dimsOpt, first: TJSONData;
  arr: TJSONArray;
  obj: TJSONObject;
  i, n: Integer;
  raw: TJSONArray;
begin
  Result := Default(TTySourceFields);
  Result.Format := tsfUnknown;
  Result.LayoutBy := slbColumn;
  Result.DetectedCount := -1;
  if ANode = nil then Exit;
  Result.Data := ANode.Find('source');
  Result.Format := TyDetectSourceFormat(Result.Data);
  d := ANode.Find('seriesLayoutBy');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'row') then
    Result.LayoutBy := slbRow;
  dimsOpt := ANode.Find('dimensions');
  { `!dimensionsDefine`: only a list (or a truthy non-list, which names
    nothing) counts as given }
  if not TyDatasetTruthy(dimsOpt) then dimsOpt := nil;
  case Result.Format of
    tsfArrayRows:
      begin
        arr := TJSONArray(Result.Data);
        d := ANode.Find('sourceHeader');
        if (d = nil) or (d.JSONType = jtNull)
          or ((d.JSONType = jtString) and (d.AsString = 'auto')) then
        begin
          Result.StartIndex := DetectStartIndex(arr, Result.LayoutBy);
        end
        else if d.JSONType = jtNumber then
          Result.StartIndex := TyRoundOpt(d.AsFloat)
        else if TyDatasetTruthy(d) then
          Result.StartIndex := 1
        else
          Result.StartIndex := 0;
        if Result.StartIndex < 0 then Result.StartIndex := 0;
        if dimsOpt <> nil then
        begin
          Result.DimsDefined := True;
          Result.Dims := TyNormalizeDims(dimsOpt);
        end
        else if Result.StartIndex = 1 then
        begin
          { every cell of the first line, `val != null ? val + '' : ''` }
          raw := TJSONArray.Create;
          try
            n := FirstLineLength(arr, Result.LayoutBy);
            for i := 0 to n - 1 do
            begin
              first := FirstLineCell(arr, Result.LayoutBy, i);
              if (first = nil) or (first.JSONType = jtNull) then raw.Add('')
              else raw.Add(TyJsTextOf(first));
            end;
            Result.DimsDefined := True;
            Result.Dims := TyNormalizeDims(raw);
          finally
            raw.Free;
          end;
        end;
        if Result.DimsDefined then
          Result.DetectedCount := Length(Result.Dims)
        else if Result.LayoutBy = slbRow then
          Result.DetectedCount := arr.Count
        else if (arr.Count > 0) and (arr.Items[0] is TJSONArray) then
          Result.DetectedCount := TJSONArray(arr.Items[0]).Count;
      end;
    tsfObjectRows:
      begin
        if dimsOpt <> nil then
        begin
          Result.DimsDefined := True;
          Result.Dims := TyNormalizeDims(dimsOpt);
        end
        else
        begin
          { the keys of the first TRUTHY row (Source.ts in the 6.1 dist) }
          arr := TJSONArray(Result.Data);
          for i := 0 to arr.Count - 1 do
            if TyDatasetTruthy(arr.Items[i]) then
            begin
              raw := TJSONArray.Create;
              try
                if arr.Items[i] is TJSONObject then
                begin
                  obj := TJSONObject(arr.Items[i]);
                  for n := 0 to obj.Count - 1 do raw.Add(obj.Names[n]);
                end
                else if arr.Items[i] is TJSONArray then
                  for n := 0 to TJSONArray(arr.Items[i]).Count - 1 do raw.Add(IntToStr(n));
                Result.DimsDefined := True;
                Result.Dims := TyNormalizeDims(raw);
              finally
                raw.Free;
              end;
              Break;
            end;
        end;
      end;
    tsfKeyedColumns:
      begin
        Result.DimsDefined := True;
        if dimsOpt <> nil then
          Result.Dims := TyNormalizeDims(dimsOpt)
        else
        begin
          obj := TJSONObject(Result.Data);
          raw := TJSONArray.Create;
          try
            for n := 0 to obj.Count - 1 do raw.Add(obj.Names[n]);
            Result.Dims := TyNormalizeDims(raw);
          finally
            raw.Free;
          end;
        end;
      end;
  else
    if dimsOpt <> nil then
    begin
      Result.DimsDefined := True;
      Result.Dims := TyNormalizeDims(dimsOpt);
    end;
  end;
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

{ [spec 255] One entry of an encode list, resolved: a string a name the
  source has, a number an index -- a whole one from nought below ADimCount;
  -1 for anything else. A NUMBER IS AN INDEX AND A STRING IS A NAME,
  including a string that looks like a number. (Upstream throws on a
  negative or a fractional index in a list of several -- getResultItem
  answers undefined -- and here it reaches nothing.) }
function EncodeEntry(AItem: TJSONData; const ASource: TTyChartSource;
  ADimCount: Integer): Integer;
var v: Double;
begin
  Result := -1;
  if AItem = nil then Exit;
  if AItem.JSONType = jtString then
    Result := TySourceDimIndexOf(ASource, AItem.AsString)
  else if AItem.JSONType = jtNumber then
  begin
    v := AItem.AsFloat;
    if (Frac(v) = 0) and (v >= 0) and (v < MaxInt) then Result := Trunc(v);
  end;
  { past the dimensions: none (`resultDimIdx < dimCount`) }
  if Result >= ADimCount then Result := -1;
end;

{ normalizeToArray, each entry resolved: a list its entries, null none, any
  other value one; the trailing gaps dropped -- validDataDims is as long as
  its last entry that reached a dimension }
function EncodeEntries(AValue: TJSONData; const ASource: TTyChartSource;
  ADimCount: Integer): TTyIntegerArray;
var i, n: Integer;
begin
  Result := nil;
  if (AValue = nil) or (AValue.JSONType = jtNull) then Exit;
  if AValue is TJSONArray then
  begin
    SetLength(Result, AValue.Count);
    for i := 0 to AValue.Count - 1 do
      Result[i] := EncodeEntry(AValue.Items[i], ASource, ADimCount);
  end
  else
  begin
    SetLength(Result, 1);
    Result[0] := EncodeEntry(AValue, ASource, ADimCount);
  end;
  n := Length(Result);
  while (n > 0) and (Result[n - 1] < 0) do Dec(n);
  SetLength(Result, n);
end;

function TySourceEncodeDimCount(const ASource: TTyChartSource): Integer;
begin
  if ASource.DimsWritten then Result := Length(ASource.Dims)
  else Result := ASource.DimCount;
end;

function TyEncodeFirstSlot(const AEntries: array of Integer): Integer;
var i: Integer;
begin
  Result := -1;
  if Length(AEntries) = 0 then Exit;
  Result := AEntries[0];
  if Result < 0 then Exit;
  for i := 1 to High(AEntries) do
    if AEntries[i] = Result then Exit(-1);
end;

procedure FillUnclaimed(var AEnc: TTySeriesEncode; ADimCount: Integer);
var
  i, j, avail: Integer;
  used: Boolean;
begin
  avail := 0;
  for i := 0 to High(AEnc.Columns) do
  begin
    if (i <= High(AEnc.Explicit)) and AEnc.Explicit[i] then Continue;
    if AEnc.Columns[i] >= 0 then Continue;
    { a dimension any written coordinate holds is taken, an extra entry of
      a list and a key no coordinate system asks for among them [spec 255] }
    repeat
      used := (avail <= High(AEnc.Claimed)) and AEnc.Claimed[avail];
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

procedure TyEncodeFillUnclaimed(var AEnc: TTySeriesEncode; ADimCount: Integer);
begin
  if not AEnc.Given then Exit;
  FillUnclaimed(AEnc, ADimCount);
end;

procedure TyEncodeDropPast(var AEnc: TTySeriesEncode; ADimCount: Integer);
var
  i: Integer;
  dropped: Boolean;
begin
  dropped := False;
  for i := 0 to High(AEnc.Columns) do
    if AEnc.Columns[i] >= ADimCount then
    begin
      AEnc.Columns[i] := -1;
      dropped := True;
    end;
  if dropped then FillUnclaimed(AEnc, ADimCount);
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
  const ACoordDims: TTyCoordDimArray; ADimCount: Integer): TTySeriesEncode;
const
  cVisual: array[0..6] of string = ('tooltip', 'label', 'itemName', 'itemId',
    'itemGroupId', 'itemChildGroupId', 'seriesName');
var
  node, enc: TJSONObject;
  d: TJSONData;
  i, j, k, n, dimCount, vk, keyCount: Integer;
  key: string;
  keys: array of string;
  lists: array of TTyIntegerArray;
  noMap, isSys, done: array of Boolean;
  owner, slot: TTyIntegerArray;
  vis: array[0..6] of TTyIntegerArray;
  entries: TTyIntegerArray;

  { createDimensions' `false`: a lone number below nought (normalizeToArray
    of it, one entry, no string) asks for no mapping }
  function NoMapping(AValue: TJSONData): Boolean;
  begin
    if (AValue is TJSONArray) and (AValue.Count = 1) then AValue := AValue.Items[0];
    Result := (AValue.JSONType = jtNumber) and (AValue.AsFloat < 0);
  end;

  function KeyOf(const ACoord: TTyCoordDim): string;
  begin
    if ACoord.Key <> '' then Result := ACoord.Key else Result := ACoord.Name;
  end;

  function KeyIndex(const AKey: string): Integer;
  var q: Integer;
  begin
    for q := 0 to keyCount - 1 do
      if keys[q] = AKey then Exit(q);
    Result := keyCount;
    Inc(keyCount);
    SetLength(keys, keyCount);
    SetLength(lists, keyCount);
    SetLength(noMap, keyCount);
    SetLength(isSys, keyCount);
    SetLength(done, keyCount);
    keys[Result] := AKey;
    lists[Result] := nil;
    noMap[Result] := False;
    isSys[Result] := False;
    done[Result] := False;
  end;

  function VisualIndex(const AKey: string): Integer;
  var q: Integer;
  begin
    for q := 0 to High(cVisual) do
      if cVisual[q] = AKey then Exit(q);
    Result := -1;
  end;

  { applyDim: the dimension now feeds that key at that place -- the last
    application wins }
  procedure Assign(ADim, AKey, AIndex: Integer);
  begin
    owner[ADim] := AKey;
    slot[ADim] := AIndex;
  end;

  { summarizeDimensions' encode[key]: each dimension at its place, -1 a gap }
  function ListOf(AKey: Integer): TTyIntegerArray;
  var q, m: Integer;
  begin
    Result := nil;
    m := 0;
    for q := 0 to dimCount - 1 do
      if (owner[q] = AKey) and (slot[q] + 1 > m) then m := slot[q] + 1;
    SetLength(Result, m);
    for q := 0 to m - 1 do Result[q] := -1;
    for q := 0 to dimCount - 1 do
      if owner[q] = AKey then Result[slot[q]] := q;
  end;

  function VisualList(AVis: Integer): TTyIntegerArray;
  var q, m: Integer;
  begin
    Result := nil;
    m := 0;
    for q := 0 to dimCount - 1 do
      if vis[AVis][q] + 1 > m then m := vis[AVis][q] + 1;
    SetLength(Result, m);
    for q := 0 to m - 1 do Result[q] := -1;
    for q := 0 to dimCount - 1 do
      if vis[AVis][q] >= 0 then Result[vis[AVis][q]] := q;
  end;

  procedure Push(var A: TTyIntegerArray; AValue: Integer);
  begin
    SetLength(A, Length(A) + 1);
    A[High(A)] := AValue;
  end;

var
  fin, cols: TTyIntegerArray;
  first: Integer;
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
  dimCount := Max(Max(TySourceEncodeDimCount(ASource), ADimCount), Max(Length(ACoordDims), 1));
  SetLength(owner, dimCount);
  SetLength(slot, dimCount);
  SetLength(Result.Claimed, dimCount);
  for i := 0 to dimCount - 1 do
  begin
    owner[i] := -1;
    slot[i] := -1;
    Result.Claimed[i] := False;
  end;
  for vk := 0 to High(cVisual) do
  begin
    SetLength(vis[vk], dimCount);
    for i := 0 to dimCount - 1 do vis[vk][i] := -1;
  end;
  keyCount := 0;
  keys := nil;
  { THE INDEX FIRST: KeyIndex grows the arrays it is subscripted into }
  for i := 0 to High(ACoordDims) do
  begin
    k := KeyIndex(KeyOf(ACoordDims[i]));
    isSys[k] := True;
  end;

  { THE ENCODE, key by key in its own order (encodeDefMap.each): every entry
    a dimension reaches feeds that key at its place; a visual key (tooltip,
    label, the names) marks the dimension's otherDims instead and holds
    nothing }
  for i := 0 to enc.Count - 1 do
  begin
    key := enc.Names[i];
    d := enc.Items[i];
    vk := VisualIndex(key);
    if vk >= 0 then
    begin
      if NoMapping(d) then Continue;
      entries := EncodeEntries(d, ASource, dimCount);
      for j := 0 to High(entries) do
        if entries[j] >= 0 then vis[vk][entries[j]] := j;
      Continue;
    end;
    k := KeyIndex(key);
    if NoMapping(d) then
    begin
      noMap[k] := True;
      Continue;
    end;
    lists[k] := EncodeEntries(d, ASource, dimCount);
    for j := 0 to High(lists[k]) do
      if lists[k][j] >= 0 then
      begin
        Assign(lists[k][j], k, j);
        Result.Claimed[lists[k][j]] := True;
      end;
  end;

  { THE COORDINATE SYSTEM'S OWN, in its order: each list applied again, so a
    dimension two of them name ends on the later one (x: 1, y: 1 leaves x
    with nothing) and one a coordinate and another key both name on the
    coordinate }
  for i := 0 to High(ACoordDims) do
  begin
    k := KeyIndex(KeyOf(ACoordDims[i]));
    if done[k] then Continue;
    done[k] := True;
    if noMap[k] then Continue;
    for j := 0 to High(lists[k]) do
      if lists[k][j] >= 0 then Assign(lists[k][j], k, j);
  end;

  { WRITTEN IS REACHING A DIMENSION, or asking for none: a list that reaches
    none -- a name the table does not have, [], null -- leaves the
    coordinate to the next free dimension, as one not written
    (createDimensions: its validDataDims are empty). A list that reached
    one keeps what the dimensions say now, a gap included. }
  for i := 0 to High(ACoordDims) do
  begin
    k := KeyIndex(KeyOf(ACoordDims[i]));
    Result.Explicit[i] := noMap[k] or (Length(lists[k]) > 0);
    if noMap[k] or (Length(lists[k]) = 0) then Continue;
    fin := ListOf(k);
    if (ACoordDims[i].Index >= 0) and (ACoordDims[i].Index <= High(fin)) then
      Result.Columns[i] := fin[ACoordDims[i].Index];
  end;
  { the entries past the coordinate system's columns: extra columns of the
    key's first one }
  for k := 0 to keyCount - 1 do
  begin
    if not isSys[k] or noMap[k] or (Length(lists[k]) = 0) then Continue;
    first := -1;
    n := 0;
    for i := 0 to High(ACoordDims) do
      if KeyOf(ACoordDims[i]) = keys[k] then
      begin
        if first < 0 then first := i;
        if ACoordDims[i].Index + 1 > n then n := ACoordDims[i].Index + 1;
      end;
    fin := ListOf(k);
    for j := n to High(fin) do
      if fin[j] >= 0 then
      begin
        Push(Result.ExtraCoord, first);
        Push(Result.ExtraDim, fin[j]);
        Push(Result.ExtraIndex, j);
      end;
  end;
  { a key nobody's coordinate system asks for holds its dimensions all the
    same }
  for i := 0 to dimCount - 1 do
    if (owner[i] >= 0) and not isSys[owner[i]] then Push(Result.Others, i);

  Result.Tooltip := VisualList(0);
  Result.Labels := VisualList(1);
  cols := VisualList(2);
  Result.HasNameEncode := Length(cols) > 0;
  if Length(cols) > 0 then Result.ItemName := cols[0];
  cols := VisualList(6);
  for j := 0 to High(cols) do
    if cols[j] >= 0 then Push(Result.SeriesNames, cols[j]);
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
  { [spec 242] encode.seriesName = [nameDimIndex]: the series is named after
    the name column }
  Result.SeriesName := nameDim;
end;

end.
