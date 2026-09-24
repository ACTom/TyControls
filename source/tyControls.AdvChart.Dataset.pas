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

    `dataset.transform`. Six of the fourteen corpus datasets use one, and it is
    a language rather than a setting -- a filter expression grammar, a sort, a
    boxplot reducer, and a chain of datasets feeding each other. Upstream itself
    ships builds with `dataset` and without `transform`, so the line is one it
    already draws.

    TYPED ARRAYS, which cannot survive a trip through JSON, and KEYED COLUMNS
    (`{ product: [...], 2015: [...] }`), which no corpus example uses. Both
    detect correctly and then answer no rows, which is what a chart with an
    unreadable source should draw.

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Math, fpjson,
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

{ How many `dataset` components the option carries. }
function TyDatasetCount(AOption: TTyChartOption): Integer;

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
  shape with no reader. }
function TySourceOf(AOption: TTyChartOption; AIndex: Integer;
  ASeriesIndex: Integer = -1): TTyChartSource;

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
  end;
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
  ASeriesIndex: Integer): TTyChartSource;
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
  for i := 0 to ACount - 1 do Result.Columns[i] := -1;
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
    if d <> nil then Result.Columns[i] := EncodeValue(d, ASource);
  end;
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
