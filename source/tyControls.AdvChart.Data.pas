unit tyControls.AdvChart.Data;
{$mode objfpc}{$H+}
{ The columnar data store -- one array per dimension, not one record per datum.

  WHY COLUMNAR. Twenty of ECharts' twenty-three series types cannot be expressed
  by a list of (x, y) pairs. A candlestick datum has five numbers, a boxplot six,
  a radar one per indicator, a heatmap three, a scatter as many as the data has
  columns. Anything narrower than "N dimensions per point" has to be widened
  later, and widening it means touching every series renderer that was written
  against the narrow shape. So the store is N-dimensional from the first line.

  ONE COLUMN TYPE, FOUR DIMENSION TYPES. Every column is `array of Double`,
  whatever the dimension's declared type is. ECharts backs `int` and `ordinal`
  with Int32Array to save memory, and pays for it with a wart: an Int32Array
  cannot hold NaN, so a missing value in an `int` dimension silently becomes 0
  rather than a gap. Double represents every Int32 and every ordinal index
  exactly, so the only thing that costs is four bytes per value -- and it buys
  NaN as the SINGLE spelling of "no data" across all four types, which is the
  contract this layer is built on. The dimension type therefore governs PARSING
  and INTERPRETATION, never storage.

  Four types, not ECharts' five: its `number` differs from `float` only in being
  a plain JS Array instead of a typed one, a distinction with no meaning here.

  TWO INDEX SPACES. A raw index addresses the original input row and never
  changes. A data index addresses the current, filtered view. dataZoom moves the
  second while the first stands still, and the pair is exactly what the v6.1
  callback record already promises with its DataIndex and RawDataIndex fields.
  Filtering never moves a value: it builds an index vector, and GetRawIndex
  reads through it.

  DIVERGENCE FROM ECharts, DELIBERATE. ECharts clones the store on every filter
  and shares the columns by reference, because in JS several series read one
  parsed table. FPC dynamic arrays are reference-counted but NOT copy-on-write
  for element writes, so the same trick here would alias two stores onto one
  buffer and corrupt both. This store filters IN PLACE instead: one store, one
  index vector, RestoreAll to undo. Sharing a parsed table across series is a
  later question and needs its own answer.

  This unit is PURE: SysUtils, Classes, Math and AdvChart.Types. No LCL, no
  JSON. Reading option text into TTyDataValue is the caller's job, which is what
  keeps the store testable without an option tree. }
interface
uses SysUtils, Classes, Math, DateUtils, tyControls.AdvChart.Types;

type
  { What a dimension MEANS. Storage is Double regardless -- see the unit header. }
  TTyDimType = (
    ddtFloat,     // any real number
    ddtInt,       // truncated toward zero on parse
    ddtOrdinal,   // a category, interned to its index in the category list
    ddtTime       // epoch milliseconds, so NaN stays available as the gap
  );

  { A raw value on its way into the store. The option reader builds these; the
    store parses them per the destination dimension's type.

    dvkNone is "the key was absent, or the value was null" and is NOT the same
    as dvkText with an empty string: on an ordinal dimension the empty string is
    a legitimate category name, while dvkNone is a gap. }
  TTyDataValueKind = (dvkNone, dvkNumber, dvkText, dvkBool);

  TTyDataValue = record
    Kind: TTyDataValueKind;
    Num: Double;
    Text: string;
  end;
  TTyDataValueArray = array of TTyDataValue;

  { WHAT A DATA ITEM WAS, as written -- upstream's getRawValue, for the text a
    label or a tooltip prints. rshNone is "nothing kept", and every reader
    then falls back to the parsed Double. An item written as null, or as an
    object with no `value`, is ABSENT (`undefined`); `{value: null}` is NULL.
    A scalar answers every dimension; an array or a row answers by position,
    and an objectRows row by its source dimension's position. }
  TTyRawShape = (rshNone, rshAbsent, rshNull, rshScalar, rshArray, rshObject);
  TTyRawItem = record
    Shape: TTyRawShape;
    Scalar: TTyDataValue;
    Cells: TTyDataValueArray;
  end;

  { What upstream's dimension record says about ONE POSITION of the raw item,
    beyond its name. A DISPLAY NAME exists only where somebody DECLARED the
    dimension -- series `dimensions`, a dataset header or `dimensions`, a
    candlestick's open/close/lowest/highest -- never for a generated `value`
    or a coordinate's own name; its presence is what turns a tooltip into
    sub-rows. A TYPE is the declared one, or `ordinal` where upstream's
    guessOrdinal would say so.

    Not kept: upstream's `otherDims.tooltip: false` on a whisker box's row
    index. It hides a dimension only from the tooltip dimensions -- which for
    a whisker box are its four or five value columns unless `encode.tooltip`
    names them, and a named one is shown. So it can never hide anything. }
  TTyRawDimInfo = record
    Display: string;
    HasDisplay: Boolean;
    DimType: TTyDimType;
    HasType: Boolean;
  end;

  { Which values an extent is allowed to see. defPositive is the log axis'
    requirement -- zero and negatives have no logarithm, and an extent that
    included them would hand the log mapper a domain it cannot map. }
  TTyExtentFilter = (defNone, defPositive);

  { A range test on one dimension, as dataZoom applies it. }
  TTyDimRange = record
    Dim: Integer;
    Min, Max: Double;
  end;

  { Answers "keep this raw row?". A method pointer rather than a plain procedure
    so the predicate can carry the state it filters against. }
  TTyDataFilterFunc = function(ARawIndex: Integer): Boolean of object;

{ ---- raw values ---- }
function TyDataNone: TTyDataValue;
function TyDataNum(AValue: Double): TTyDataValue;
function TyDataText(const AText: string): TTyDataValue;
function TyDataBool(AValue: Boolean): TTyDataValue;

{ Parse for the three numeric dimension types. Ordinal is NOT handled here
  because interning needs the dimension's category list; it returns NaN, and the
  store routes ordinal values through TTyOrdinalMeta instead.

  The numeric text rules are ECharts' parseDataValue: the empty string is
  NaN, and any other text is JavaScript's Number() of it -- so '   ' is
  nought, '0x10' sixteen, 'Infinity' infinite, and '-' (ECharts' documented
  "no data") and '12px' NaN. Never the locale's decimal point.
  [Batch 53: this was Trim + TryStrToFloat, which read '   ' and '0x10' as
  NaN, 'Infinity' as NaN and 'Inf' as infinite -- all four the other way
  round from upstream.]

  A TIME is a number as written, a boolean as its 0 or 1 (new Date(true)),
  and text through the date parser as written -- no trimming. }
function TyParseDataValue(const AValue: TTyDataValue; AType: TTyDimType): Double;
{ Number() of a data text the way parseDataValue takes it: '' is NaN. }
function TyParseNumberText(const AText: string): Double;

{ ---- JavaScript's numbers from text ---- }

{ AText with JavaScript's white space taken off both ends -- which is wider
  than Trim's: no-break space, U+FEFF, the line and paragraph separators and
  every space separator, as UTF-8. }
function TyJsTrim(const AText: string): string;
{ `Number(text)`: the whole string, trimmed, as a decimal literal, `Infinity`,
  or a 0x / 0o / 0b integer; nothing at all is nought; anything else is
  not-a-number. }
function TyJsToNumber(const AText: string): Double;
{ `parseFloat(text)`: the longest decimal prefix after the white space, or
  `Infinity`; not-a-number when there is none. }
function TyJsParseFloat(const AText: string): Double;
{ upstream's numericToNumber: a number is itself (minus nought is nought); a
  string is its parseFloat when that equals its Number -- and is not a nought
  read off something with an `x` past the first character; anything else is
  not-a-number. }
function TyJsNumericToNumber(const AValue: TTyDataValue): Double;
{ JavaScript's String() of one value: a number as it prints, text verbatim,
  a boolean as its word, a gap as ANone. }
function TyJsValueText(const AValue: TTyDataValue; const ANone: string): string;
{ String() of a whole raw item: the scalar; the cells joined by commas, a gap
  as nothing; `[object Object]`; `null`; `undefined`. }
function TyRawItemText(const AItem: TTyRawItem): string;
{ One raw cell as a tooltip prints it -- upstream's makeValueReadable for
  everything but a time: an ordinal's text as written ('-' when blank) or its
  number without commas; otherwise the number numericToNumber reads, grouped
  by addCommas, and failing that the text, the boolean's word, or '-'. }
function TyReadableCell(const ACell: TTyDataValue; AType: TTyDimType): string;

{ ---- time ---- }
{ ECharts' parseDate on a string: TIME_REG exactly -- yyyy, optionally -MM,
  -dd, then T or space and HH:mm:ss.fff, then Z or a +hh:mm offset, nothing
  trimmed; slashes where dashes are -- and the fields handed on the way
  Date.UTC / new Date take them.

  With no zone designator the timestamp is LOCAL, which is ECharts' documented
  choice and deliberately unlike JavaScript's own Date parser. AAssumeUTC forces
  the other reading, for data that is known to be UTC and for tests that must
  not depend on the machine's zone.

  LIMIT, stated rather than hidden: the local conversion uses the machine's
  CURRENT UTC offset, because FPC 3.2.2 exposes no offset-at-a-given-date. A
  timestamp on the far side of a daylight-saving switch is therefore an hour
  out. Data that cares should carry an explicit designator.

  Out-of-range components are REJECTED, where JavaScript would wrap them: month
  13 is a typo, and a gap shows it while silently becoming next January does
  not.
  [Batch 53: overturned -- upstream wraps (month 13 is next January, minute
  61 the next hour), takes a two-digit year as 19xx, reads '.5' as 5 ms and
  a zone as its whole hours only, and so does this now. Parity is the rule
  the whole port holds itself to; a gap where upstream draws a point is a
  different chart, not a kinder one.] }
function TyParseDateMs(const AText: string; out AMs: Double;
  AAssumeUTC: Boolean = False): Boolean;
function TyDateTimeToMs(ADateTime: TDateTime; AIsUTC: Boolean = True): Double;
function TyMsToDateTime(AMs: Double; AWantUTC: Boolean = True): TDateTime;

type
  { A category list plus the interning that turns names into ordinal indices.

    Two modes, and the difference is what an unknown name does:

      COLLECTING   the category list is built from the data as it arrives, which
                   is a category axis that declares no data of its own.
      FIXED        the list came from `xAxis.data`, and a name that is not in it
                   is NOT a new category -- it is a gap, so it parses to NaN.

    The lookup map is built on first use and not before. A fixed axis of 50,000
    categories that is only ever read by index never pays for the map at all,
    which is ECharts' optimisation and worth keeping. }
  TTyOrdinalMeta = class
  private
    FCategories: TTyStringArray;
    FCount: Integer;
    FMap: TStringList;          // sorted; Objects hold the ordinal
    FNeedCollect: Boolean;
    FDeduplication: Boolean;
    procedure EnsureMap;
    procedure Add(const ACategory: string);
  public
    constructor Create;
    destructor Destroy; override;
    { Fixed categories. Switches off collection. }
    procedure SetCategories(const A: array of string);
    function Count: Integer;
    function CategoryAt(AOrdinal: Integer): string;
    { The ordinal of a known category, or NaN's integer stand-in -1. }
    function GetOrdinal(const ACategory: string): Integer;
    { The ordinal, collecting the category first when collecting is on.
      Returns -1 when the category is unknown and cannot be collected. }
    function ParseAndCollect(const ACategory: string): Integer;
    { Drops the collected categories. A FIXED list is left alone: it came from
      the axis, not from the data, and must survive the data being replaced. }
    procedure ResetCollected;
    { Off makes every appended value a new category even when it repeats, which
      is ECharts' axis.deduplication = false: it exists for large ordered data
      that is known not to repeat, and skips the map entirely. }
    property Deduplication: Boolean read FDeduplication write FDeduplication;
    property NeedCollect: Boolean read FNeedCollect;
  end;

  TTyDataStore = class
  private
    type
      TDim = record
        Name: string;
        Kind: TTyDimType;
        { WHICH COORDINATE THIS COLUMN FEEDS, when that is not its own name.

          ONE AXIS CAN HAVE SEVERAL COLUMNS. A candlestick puts open, close,
          lowest and highest all on the value axis; a boxplot puts five there.
          Upstream models this as `mapDimensionsAll(coordDim)` -- a coordinate
          is a LIST of data dimensions, not one -- and the port had only
          `DimIndexOf(axis.Dim)`, which can answer with one column and
          therefore sized such an axis from a quarter of its own data.

          Empty means the column feeds the coordinate of its own name, which
          is every column of every series written before this existed. }
        Coord: string;
        Meta: TTyOrdinalMeta;       // ordinal dimensions only; see MetaOwned
        { False means the AXIS owns this list and hands the same instance to
          every series bound to it. That sharing is not an optimisation -- it
          IS the mechanism by which a category collected off one series' data
          reaches the axis and every other series on it. Two series with
          private lists disagree about which name ordinal 0 is, and render
          offset from each other on an axis they supposedly share. }
        MetaOwned: Boolean;
        { Set once SetCalculated has written into this dimension. RawMin and
          RawMax below are maintained during APPEND only, so for a column that
          was computed rather than appended they are still the empty range --
          and DataExtent's fast path would answer "no data" for a column full
          of numbers. }
        HasCalculated: Boolean;
        RawMin, RawMax: Double;     // maintained during append, so the
                                    // unfiltered extent is O(1)
        CacheMin, CacheMax: array[TTyExtentFilter] of Double;
        CacheOk: array[TTyExtentFilter] of Boolean;
        Inverted: array of Integer; // ordinal -> raw index, -1 = absent
        HasInverted: Boolean;
      end;
      TOvr = record
        Key: Integer;
        Next: Integer;
        Value: TTyDataValue;
      end;
  private
    FDims: array of TDim;
    FCols: array of TTyDoubleArray;
    FRawCount: Integer;
    FCapacity: Integer;
    FIndices: array of Integer;
    { Separate from `FIndices <> nil`, because a filter that keeps NOTHING has
      an empty index vector, and an empty dynamic array in FPC IS nil. Without
      this flag that case would read as unfiltered and the extent would answer
      from the whole input. }
    FFiltered: Boolean;
    FCount: Integer;
    FIds, FNames: TTyStringArray; // lazily sized; empty until first written
    FRawItems: array of TTyRawItem; // lazily sized, like the names
    FRawDimNames: TTyStringArray;
    FRawDimPos: array of Integer; // per store dimension; -1 = no position
    FRawDimInfo: array of TTyRawDimInfo; // per raw position
    FTipPos, FLabelPos: array of Integer;
    FHasTipPos, FHasLabelPos: Boolean;
    FRawWidth: Integer;
    FOvrHead: array of Integer;   // per raw row, -1 = no overrides
    FOvr: array of TOvr;
    FOvrCount: Integer;
    procedure GrowRawDimInfo(APos: Integer);
    procedure Grow(AWanted: Integer);
    procedure InvalidateExtents;
    { Any append retires the inverted index: it is sized to the category count
      and filled from the rows that existed when it was built, so a later row
      leaves it short of a newly interned category and blind to the row just
      added -- and RawIndexOfOrdinal answered out of it without noticing.
      Retiring costs one rebuild on the next lookup and cannot go stale.

      Filtering does NOT retire it: the index maps an ordinal to a RAW index,
      and a filter changes the view rather than the rows. }
    procedure RetireInverted;
    function ParseCell(ADim: Integer; const AValue: TTyDataValue): Double;
    procedure NoteValue(ADim: Integer; AValue: Double);
    procedure SetIndices(const A: array of Integer; ACount: Integer);
    procedure CheckAppendable;
  public
    constructor Create;
    destructor Destroy; override;

    { ---- schema ---- }
    function AddDimension(const AName: string; AType: TTyDimType): Integer;
    function DimCount: Integer;
    function DimIndexOf(const AName: string): Integer;
    { EVERY column feeding one coordinate, in column order.

      Falls back to the single column named ACoord when nothing was mapped, so
      a store built the ordinary way answers exactly what DimIndexOf does and
      a caller never has to ask which kind of store it has. }
    function DimsOfCoord(const ACoord: string): TTyIntegerArray;
    { Say that ADim feeds ACoord. }
    procedure SetDimCoord(ADim: Integer; const ACoord: string);
    { The coordinate SetDimCoord gave the column; '' for an ordinary one. }
    function DimCoord(ADim: Integer): string;
    function DimName(ADim: Integer): string;
    function DimType(ADim: Integer): TTyDimType;
    { The category list of an ordinal dimension, from an axis' `data`.

      MUST be called before the first row is appended. ECharts fills first and
      rewrites the column in place when the axis' categories turn up later; that
      rewrite exists because its Model layer resolves in an order it does not
      control. Ours does control it -- axes are read before series -- so the
      rewrite is replaced by a rule, and calling this late raises rather than
      silently reinterpreting a column that has already been parsed. }
    procedure SetCategories(ADim: Integer; const A: array of string);
    { Borrow the AXIS' category list instead of keeping a private one.

      Must be called before the first row, for the same reason SetCategories
      must: this store controls the order -- axes are read before series -- so
      the in-place column rewrite ECharts needs is replaced by a rule, and a
      rule that is not enforced is a comment. }
    procedure UseOrdinalMeta(ADim: Integer; AMeta: TTyOrdinalMeta);
    function CategoryCount(ADim: Integer): Integer;
    function CategoryAt(ADim, AOrdinal: Integer): string;
    function OrdinalMeta(ADim: Integer): TTyOrdinalMeta;

    { ---- filling ---- }
    { Raw values, parsed per the destination dimension's type. }
    function AppendRow(const AValues: array of TTyDataValue): Integer; overload;
    { Values that are ALREADY parsed, which for an ordinal dimension means
      already an ordinal index -- nothing is interned and no category list is
      consulted. This is the overload a calculated column is written through,
      and the wrong one for anything that came from option text. }
    function AppendRow(const AValues: array of Double): Integer; overload;
    { Drops every row but keeps the schema, the categories and the dimension
      types, so a store can be refilled without rebuilding its shape. }
    procedure Clear;

    { ---- calculated columns ---- }
    { Write one cell of a dimension that was added AFTER filling.

      The only way to put a value into such a column: AddDimension fills it with
      NaN and AppendRow writes whole rows, so a calculation over existing rows
      has no other door. Addressed by RAW index, because a calculation walks the
      rows as they were given -- a filter is a view for readers, and writing
      through a view would put the value in a different row once the filter
      moved.

      Refuses a dimension that predates the rows. That is not tidiness: the raw
      columns are parsed from option text through the dimension's own type, and
      a back door that skipped parsing would let an ordinal column hold
      something that is not an ordinal index. }
    procedure SetCalculated(ADim, ARawIndex: Integer; AValue: Double);

    { ---- reading ---- }
    { Rows in the current view. }
    function Count: Integer;
    { Rows as input, whatever the filter is doing. }
    function RawCount: Integer;
    function GetRawIndex(AIndex: Integer): Integer;
    { The inverse. -1 when that row is filtered out. Binary search over the
      ascending index vector, with the identity guess ECharts makes first. }
    function IndexOfRawIndex(ARawIndex: Integer): Integer;
    function Get(ADim, AIndex: Integer): Double;
    function GetByRaw(ADim, ARawIndex: Integer): Double;
    { The category name behind an ordinal value; '' for a gap or a dimension
      that is not ordinal. }
    function GetOrdinalText(ADim, AIndex: Integer): string;

    { ---- identity ---- }
    procedure SetId(ARawIndex: Integer; const AId: string);
    procedure SetName(ARawIndex: Integer; const AName: string);
    function GetId(AIndex: Integer): string;
    function GetIdByRaw(ARawIndex: Integer): string;
    function GetName(AIndex: Integer): string;
    { WHAT UPSTREAM'S getName ANSWERS: the item's own name, and without one
      the category behind the FIRST ordinal dimension -- createSeriesData
      hands that dimension the item-name role. So a bare 842 on a category
      axis is called 'Mon', and a label's b placeholder says so.
      '' when there is neither.

      NOT what identifies a row. A graph keys its nodes by the name the
      author wrote, and a node written as a bare number is keyed by its
      position -- a link to 'Mon' finds nothing upstream either. }
    function GetItemName(AIndex: Integer): string;
    { The same name in RAW space. FilterSelf hands its predicate a raw
      index -- it is deciding which raw rows survive, so it cannot speak
      the view's language -- and a predicate that wants to test the name
      would otherwise have to go the long way round through
      IndexOfRawIndex, which answers -1 for a row an earlier filter has
      already dropped. }
    function GetNameByRaw(ARawIndex: Integer): string;
    function HasIds: Boolean;
    function HasNames: Boolean;

    { ---- the raw items ---- }
    procedure SetRawItem(ARawIndex: Integer; const AItem: TTyRawItem);
    { rshNone when nothing was kept for the row. }
    function RawItem(AIndex: Integer): TTyRawItem;
    function RawItemByRaw(ARawIndex: Integer): TTyRawItem;
    function HasRawItems: Boolean;
    { upstream's dimension NAMES by position -- not the store's coordinate
      names: the encoded coordinate names at their positions, `value`,
      `value0`, ... past them, or a dataset's own header. }
    procedure SetRawDimName(APos: Integer; const AName: string);
    { WHERE IN THE RAW ITEM a store dimension was read from -- its encoded
      position, which is not its own index once `encode` or a prepended row
      index moves it. Unset, a dimension is at its own index; -1 is none. }
    procedure SetRawDimPos(ADim, APos: Integer);
    function RawDimPos(ADim: Integer): Integer;
    { ---- what each raw position is (see TTyRawDimInfo) ---- }
    procedure SetRawDimDisplay(APos: Integer; const AName: string);
    procedure SetRawDimType(APos: Integer; AType: TTyDimType);
    function RawDimInfo(APos: Integer): TTyRawDimInfo;
    { The type a position prints by: the store column reading it, else the
      declared or guessed one, else a number. }
    function RawPosType(APos: Integer): TTyDimType;
    { upstream's guessOrdinal for every position no column reads and nobody
      typed: `ordinal` when the first telling value among the first five
      items is text that is no number and not '-'. AOriginal: a series' own
      data, where an item that is not an array ends the guess. }
    procedure GuessRawOrdinals(AOriginal: Boolean);
    { upstream's defaultedTooltip and defaultedLabel, as raw positions. Unset,
      a consumer keeps its own rule; set EMPTY, there are none. }
    procedure SetTooltipPositions(const APos: TTyIntegerArray);
    procedure SetLabelPositions(const APos: TTyIntegerArray);
    function TooltipPositions: TTyIntegerArray;
    function LabelPositions: TTyIntegerArray;
    function HasTooltipPositions: Boolean;
    function HasLabelPositions: Boolean;
    { How many positions upstream's data HAS dimensions for -- item 0's
      width, or the table's; a cell past it belongs to no dimension. }
    property RawWidth: Integer read FRawWidth write FRawWidth;
    function RawDimName(APos: Integer): string;
    { `{@key}` to a position (getDimensionIndex): `[n]` as a number, a
      declared name, a numeric-looking key as a number; not-a-number when
      none of them. }
    function RawPosOf(const AKey: string): Double;
    { The cell at APos of an item: a scalar answers any position; an array or
      object by an in-range whole position; anything else is no cell. }
    class function RawCell(const AItem: TTyRawItem; APos: Double;
      out ACell: TTyDataValue): Boolean; static;

    { ---- per-point overrides ----
      The native answer to ECharts' getItemModel, which wraps a datum in a Model
      whose prototype chain falls back to the series. There is no prototype
      chain here, so "set" and "not set" have to be told apart explicitly: a
      symbolSize of 0 is a real instruction and cannot be signalled by absence,
      and NaN cannot stand in for an absent string or boolean.

      Sparse by construction. A row with no overrides costs one Integer, and a
      store where nothing is overridden costs nothing at all. }
    procedure SetOverride(ARawIndex, AKey: Integer; const AValue: TTyDataValue);
    function HasOverride(AIndex, AKey: Integer): Boolean;
    function GetOverride(AIndex, AKey: Integer): TTyDataValue;
    function HasOverrideByRaw(ARawIndex, AKey: Integer): Boolean;
    function GetOverrideByRaw(ARawIndex, AKey: Integer): TTyDataValue;
    { How many override entries exist in total. The sparsity guarantee is
      testable rather than merely claimed. }
    function OverrideCount: Integer;

    { ---- extent ---- }
    { False when the dimension holds no value the filter admits, and then AMin
      and AMax are NaN. Returning a range would need an "empty range" spelling,
      and every caller would have to remember which way round the empty one is;
      ECharts uses [+Inf, -Inf] and it is a recurring source of confusion. }
    function DataExtent(ADim: Integer; out AMin, AMax: Double;
      AFilter: TTyExtentFilter = defNone): Boolean;

    { ---- inverted index ---- }
    { Ordinal -> raw index, for stack-by-category and for finding the row that
      belongs to a category without a scan. Built on demand over the RAW rows,
      so a filter does not invalidate it. Last row wins when a category repeats,
      which is ECharts' behaviour and the reason it documents the index as
      supporting distinct values only. }
    procedure BuildInvertedIndex(ADim: Integer);
    function RawIndexOfOrdinal(ADim, AOrdinal: Integer): Integer;

    { ---- filtering ---- }
    { Every row back. }
    procedure RestoreAll;
    { Keep the rows inside every given range.

      NaN SURVIVES. ECharts is explicit about this and it is not an oversight: a
      line chart draws a gap where a value is missing, and dropping the row
      would close the gap and draw a line through it. A scatter point with a
      missing coordinate is not drawn either way. }
    procedure SelectRange(const ARanges: array of TTyDimRange); overload;
    procedure SelectRange(ADim: Integer; AMin, AMax: Double); overload;
    { Narrows the CURRENT view, so filters compose. }
    procedure FilterSelf(AFunc: TTyDataFilterFunc);
    { True when the view is narrower than the input. }
    function IsFiltered: Boolean;
  end;

{ ---- override keys ----
  Interned so a key is an Integer in the inner loops that read it, and so a
  design-time editor can enumerate what is overridable. Case-sensitive, because
  option keys are. }
function TyOverrideKey(const AName: string): Integer;
function TyOverrideKeyName(AKey: Integer): string;
function TyOverrideKeyCount: Integer;

implementation

uses tyControls.AdvChart.Scale;

const
  MsPerDay = 86400000.0;
  { 1970-01-01 as a TDateTime. }
  UnixEpochDT = 25569.0;

var
  GOverrideKeys: TTyStringArray = nil;

{ ==================== raw values ==================== }

function TyDataNone: TTyDataValue;
begin
  Result.Kind := dvkNone;
  Result.Num := NaN;
  Result.Text := '';
end;

function TyDataNum(AValue: Double): TTyDataValue;
begin
  Result.Kind := dvkNumber;
  Result.Num := AValue;
  Result.Text := '';
end;

function TyDataText(const AText: string): TTyDataValue;
begin
  Result.Kind := dvkText;
  Result.Num := NaN;
  Result.Text := AText;
end;

function TyDataBool(AValue: Boolean): TTyDataValue;
begin
  Result.Kind := dvkBool;
  if AValue then Result.Num := 1 else Result.Num := 0;
  Result.Text := '';
end;


{ ==================== JavaScript's numbers from text ==================== }

{ The code point at AText[AAt], and how many bytes it takes. }
function CodePointAt(const AText: string; AAt: Integer; out ALen: Integer): LongWord;
var b: Byte;
begin
  b := Ord(AText[AAt]);
  ALen := 1;
  Result := b;
  if b < $80 then Exit;
  if (b and $E0 = $C0) and (AAt + 1 <= Length(AText)) then
  begin
    ALen := 2;
    Result := ((b and $1F) shl 6) or (Ord(AText[AAt + 1]) and $3F);
  end
  else if (b and $F0 = $E0) and (AAt + 2 <= Length(AText)) then
  begin
    ALen := 3;
    Result := ((b and $0F) shl 12) or ((Ord(AText[AAt + 1]) and $3F) shl 6)
      or (Ord(AText[AAt + 2]) and $3F);
  end
  else if (b and $F8 = $F0) and (AAt + 3 <= Length(AText)) then
  begin
    ALen := 4;
    Result := ((b and $07) shl 18) or ((Ord(AText[AAt + 1]) and $3F) shl 12)
      or ((Ord(AText[AAt + 2]) and $3F) shl 6) or (Ord(AText[AAt + 3]) and $3F);
  end;
end;

{ WhiteSpace and LineTerminator, as the specification lists them. }
function IsJsSpace(ACode: LongWord): Boolean;
begin
  case ACode of
    9, 10, 11, 12, 13, 32, $A0, $1680, $2000..$200A, $2028, $2029, $202F,
    $205F, $3000, $FEFF: Result := True;
  else
    Result := False;
  end;
end;

function TyJsTrim(const AText: string): string;
var i, j, n, len, cpLen: Integer; cp: LongWord;
begin
  n := Length(AText);
  i := 1;
  while i <= n do
  begin
    cp := CodePointAt(AText, i, len);
    if not IsJsSpace(cp) then Break;
    Inc(i, len);
  end;
  if i > n then Exit('');
  { From the end: step back to a code point's first byte. }
  j := n;
  while j >= i do
  begin
    len := j;
    while (len > i) and ((Ord(AText[len]) and $C0) = $80) do Dec(len);
    cp := CodePointAt(AText, len, cpLen);
    if not IsJsSpace(cp) then Break;
    j := len - 1;
  end;
  Result := Copy(AText, i, j - i + 1);
end;

{ A decimal literal's digits and exponent to the nearest Double, the sign
  last so a nought keeps it. }
function DecimalToDouble(const AIntPart, AFracPart: string; AExp: Int64;
  ANeg: Boolean): Double;
begin
  Result := TyJsDecimalToDouble(AIntPart + AFracPart, AExp - Length(AFracPart));
  if ANeg then Result := -Result;
end;

{ The longest decimal literal at AText[AAt..]: sign, digits, a point, digits,
  an exponent with digits. Answers how many bytes were read -- nought when
  there is no digit at all. }
function ScanDecimal(const AText: string; AAt: Integer; out AValue: Double): Integer;
var
  i, n, start, e: Integer;
  neg, expNeg: Boolean;
  intPart, fracPart, expDigits: string;
  expo: Int64;
begin
  AValue := NaN;
  n := Length(AText);
  i := AAt;
  neg := False;
  if (i <= n) and (AText[i] in ['+', '-']) then
  begin
    neg := AText[i] = '-';
    Inc(i);
  end;
  start := i;
  while (i <= n) and (AText[i] in ['0'..'9']) do Inc(i);
  intPart := Copy(AText, start, i - start);
  fracPart := '';
  if (i <= n) and (AText[i] = '.') then
  begin
    start := i + 1;
    e := start;
    while (e <= n) and (AText[e] in ['0'..'9']) do Inc(e);
    fracPart := Copy(AText, start, e - start);
    { A point with no digit on either side is no number. }
    if (intPart <> '') or (fracPart <> '') then i := e;
  end;
  if (intPart = '') and (fracPart = '') then Exit(0);
  expo := 0;
  if (i <= n) and (AText[i] in ['e', 'E']) then
  begin
    e := i + 1;
    expNeg := False;
    if (e <= n) and (AText[e] in ['+', '-']) then
    begin
      expNeg := AText[e] = '-';
      Inc(e);
    end;
    start := e;
    while (e <= n) and (AText[e] in ['0'..'9']) do Inc(e);
    expDigits := Copy(AText, start, e - start);
    { AN EXPONENT ONLY WITH DIGITS: in `1e` the `e` is not read. }
    if expDigits <> '' then
    begin
      if Length(expDigits) > 9 then expo := 1000000
      else expo := StrToInt(expDigits);
      if expNeg then expo := -expo;
      i := e;
    end;
  end;
  AValue := DecimalToDouble(intPart, fracPart, expo, neg);
  Result := i - AAt;
end;

function TyJsToNumber(const AText: string): Double;
var
  s, body: string;
  i, radix, d: Integer;
  used: Integer;
  mask: TFPUExceptionMask;
begin
  s := TyJsTrim(AText);
  if s = '' then Exit(0);
  if (s = 'Infinity') or (s = '+Infinity') then Exit(Infinity);
  if s = '-Infinity' then Exit(NegInfinity);
  { 0x / 0o / 0b: no sign, at least one digit, every digit of the radix. }
  if (Length(s) > 2) and (s[1] = '0') and (s[2] in ['x', 'X', 'o', 'O', 'b', 'B']) then
  begin
    case s[2] of
      'x', 'X': radix := 16;
      'o', 'O': radix := 8;
    else
      radix := 2;
    end;
    body := Copy(s, 3, MaxInt);
    Result := 0;
    mask := GetExceptionMask;
    SetExceptionMask(mask + [exOverflow, exPrecision]);
    try
      for i := 1 to Length(body) do
      begin
        case body[i] of
          '0'..'9': d := Ord(body[i]) - Ord('0');
          'a'..'f': d := Ord(body[i]) - Ord('a') + 10;
          'A'..'F': d := Ord(body[i]) - Ord('A') + 10;
        else
          d := 99;
        end;
        if d >= radix then Exit(NaN);
        Result := Result * radix + d;
      end;
    finally
      ClearExceptions(False);
      SetExceptionMask(mask);
    end;
    Exit;
  end;
  used := ScanDecimal(s, 1, Result);
  { The WHOLE string must be the literal. }
  if (used = 0) or (used <> Length(s)) then Result := NaN;
end;

function TyJsParseFloat(const AText: string): Double;
var s: string; used: Integer;
begin
  { Only the leading white space goes; the tail is simply not read. }
  s := TyJsTrim(AText + 'x');
  Delete(s, Length(s), 1);
  if Copy(s, 1, 8) = 'Infinity' then Exit(Infinity);
  if Copy(s, 1, 9) = '+Infinity' then Exit(Infinity);
  if Copy(s, 1, 9) = '-Infinity' then Exit(NegInfinity);
  used := ScanDecimal(s, 1, Result);
  if used = 0 then Result := NaN;
end;

function TyJsNumericToNumber(const AValue: TTyDataValue): Double;
var f, n: Double; p: Integer;
begin
  case AValue.Kind of
    dvkNumber:
      begin
        { parseFloat(String(x)): minus nought comes back as nought. }
        Result := AValue.Num;
        if (not IsNan(Result)) and (Result = 0) then Result := 0;
      end;
    dvkText:
      begin
        f := TyJsParseFloat(AValue.Text);
        n := TyJsToNumber(AValue.Text);
        { `valFloat == val`: a not-a-number is never equal. }
        if IsNan(f) or IsNan(n) or (f <> n) then Exit(NaN);
        { `val.indexOf('x') <= 0` for a nought: ' 0x0 ' is not nought. }
        p := Pos('x', AValue.Text);
        if (f = 0) and (p > 1) then Exit(NaN);
        Result := f;
      end;
  else
    Result := NaN;
  end;
end;

function TyJsValueText(const AValue: TTyDataValue; const ANone: string): string;
begin
  case AValue.Kind of
    dvkNumber: Result := TyJsNumberToString(AValue.Num);
    dvkText: Result := AValue.Text;
    dvkBool: if AValue.Num <> 0 then Result := 'true' else Result := 'false';
  else
    Result := ANone;
  end;
end;

function TyRawItemText(const AItem: TTyRawItem): string;
var i: Integer;
begin
  case AItem.Shape of
    rshScalar: Result := TyJsValueText(AItem.Scalar, '');
    rshArray:
      begin
        Result := '';
        for i := 0 to High(AItem.Cells) do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + TyJsValueText(AItem.Cells[i], '');
        end;
      end;
    rshObject: Result := '[object Object]';
    rshNull: Result := 'null';
    rshAbsent: Result := 'undefined';
  else
    Result := '';
  end;
end;

function TyReadableCell(const ACell: TTyDataValue; AType: TTyDimType): string;
var n: Double; mask: TFPUExceptionMask;
begin
  if AType = ddtOrdinal then
  begin
    case ACell.Kind of
      dvkText:
        if TyJsTrim(ACell.Text) <> '' then Exit(ACell.Text) else Exit('-');
      dvkNumber:
        if IsNan(ACell.Num) or IsInfinite(ACell.Num) then Exit('-')
        else Exit(TyJsNumberToString(ACell.Num));
    else
      Exit('-');
    end;
  end;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exUnderflow, exPrecision]);
  try
    n := TyJsNumericToNumber(ACell);
    if not (IsNan(n) or IsInfinite(n)) then
      Exit(TyJsAddCommas(TyJsNumberToString(n)));
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
  case ACell.Kind of
    dvkText:
      if TyJsTrim(ACell.Text) <> '' then Result := ACell.Text else Result := '-';
    dvkBool:
      if ACell.Num <> 0 then Result := 'true' else Result := 'false';
  else
    Result := '-';
  end;
end;

function TyParseNumberText(const AText: string): Double;
var mask: TFPUExceptionMask;
begin
  { `value === ''` exactly -- a string of blanks is Number()'s nought. }
  if AText = '' then Exit(NaN);
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exUnderflow, exPrecision]);
  try
    Result := TyJsToNumber(AText);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

function TyParseDataValue(const AValue: TTyDataValue; AType: TTyDimType): Double;
var
  n: Double;
begin
  case AType of
    ddtOrdinal: Exit(NaN);   // the store interns instead; see the declaration
    ddtTime:
      begin
        case AValue.Kind of
          dvkNone: Exit(NaN);
          { new Date(Math.round(true)): the first millisecond. }
          dvkBool: Exit(AValue.Num);
          { A NUMBER IS KEPT AS WRITTEN: upstream's parseDataValue parses only
            what is not a number, so half a millisecond stays in the store and
            in the extent. The time scale rounds -- Math.round, half up -- only
            where it places a value on the axis.
            [Revised in batch 42: this rounded, banker's way, as it read.] }
          dvkNumber:
            if IsNan(AValue.Num) or IsInfinite(AValue.Num) then
              Exit(NaN)
            else
              Exit(AValue.Num);
          dvkText:
            if TyParseDateMs(AValue.Text, n) then Exit(n) else Exit(NaN);
        end;
        Exit(NaN);
      end;
  end;

  case AValue.Kind of
    dvkNone: n := NaN;
    dvkNumber, dvkBool: n := AValue.Num;
    dvkText: n := TyParseNumberText(AValue.Text);
  else
    n := NaN;
  end;

  if (AType = ddtInt) and (not IsNan(n)) and (not IsInfinite(n)) then
    n := Trunc(n);
  Result := n;
end;

{ ==================== time ==================== }

function TyDateTimeToMs(ADateTime: TDateTime; AIsUTC: Boolean): Double;
begin
  if not AIsUTC then
    ADateTime := LocalTimeToUniversal(ADateTime);
  { Whole milliseconds. A TDateTime is a count of DAYS, so scaling it lands a
    fraction of a millisecond either side of the integer, and two timestamps
    that name the same instant then fail to compare equal. }
  Result := Round((ADateTime - UnixEpochDT) * MsPerDay);
end;

function TyMsToDateTime(AMs: Double; AWantUTC: Boolean): TDateTime;
begin
  Result := UnixEpochDT + AMs / MsPerDay;
  if not AWantUTC then
    Result := UniversalTimeToLocal(Result);
end;

{ Reads AMax digits at most, and at least one. }
function ScanInt(const S: string; var P: Integer; AMax: Integer;
  out AValue: Integer): Boolean;
var
  n: Integer;
begin
  AValue := 0;
  n := 0;
  while (P <= Length(S)) and (S[P] >= '0') and (S[P] <= '9') and (n < AMax) do
  begin
    AValue := AValue * 10 + (Ord(S[P]) - Ord('0'));
    Inc(P);
    Inc(n);
  end;
  Result := n > 0;
end;

{ Days from 1970-01-01 to the first of AMonth (1..12) of AYear, proleptic
  Gregorian -- MakeDay's arithmetic without a calendar that stops at year 1. }
function DaysFromCivil(AYear: Int64; AMonth: Integer): Int64;
var y, era, yoe, doy, doe, m: Int64;
begin
  y := AYear;
  m := AMonth;
  if m <= 2 then Dec(y);
  if y >= 0 then era := y div 400 else era := (y - 399) div 400;
  yoe := y - era * 400;
  if m > 2 then doy := (153 * (m - 3) + 2) div 5 else doy := (153 * (m + 9) + 2) div 5;
  doe := yoe * 365 + yoe div 4 - yoe div 100 + doy;
  Result := era * 146097 + doe - 719468;
end;

function TyParseDateMs(const AText: string; out AMs: Double;
  AAssumeUTC: Boolean): Boolean;
var
  s: string;
  p, n, sign: Integer;
  fY, fMo, fD, fH, fMi, fS, fMs, fZ: string;
  haveMo, haveD, haveH, haveMi, haveS, haveMs, haveZone, zoneZ: Boolean;
  zoneH: Integer;
  y, mo, d, h, mi, sec, ms: Int64;
  days, total: Int64;

  function Digits(AMin, AMax: Integer; out AText_: string): Boolean;
  var start: Integer;
  begin
    start := p;
    while (p <= Length(s)) and (s[p] in ['0'..'9']) and (p - start < AMax) do Inc(p);
    AText_ := Copy(s, start, p - start);
    Result := Length(AText_) >= AMin;
  end;

  function Num(const AText_: string): Int64;
  begin
    if AText_ = '' then Exit(0);
    Result := StrToInt64(AText_);
  end;

begin
  AMs := NaN;
  Result := False;
  { AS WRITTEN: upstream's TIME_REG is anchored and nothing trims first, so
    ' 2020' is no date. [Batch 53: this trimmed.] }
  s := AText;
  if s = '' then Exit;

  { ---- TIME_REG, token for token ----
    ^(\d{4})([-/](\d{1,2})([-/](\d{1,2})([T ](\d{1,2})(:(\d{1,2})(:(\d{1,2})
    ([.,](\d+))?)?)?(Z|[+-]\d\d:?\d\d)?)?)?)?$ -- every group after the year
    optional, and a zone only after an hour. }
  p := 1;
  haveMo := False; haveD := False; haveH := False; haveMi := False;
  haveS := False; haveMs := False; haveZone := False; zoneZ := False;
  zoneH := 0;
  if not Digits(4, 4, fY) then Exit;
  if (p <= Length(s)) and (s[p] in ['-', '/']) then
  begin
    Inc(p);
    if not Digits(1, 2, fMo) then Exit;
    haveMo := True;
    if (p <= Length(s)) and (s[p] in ['-', '/']) then
    begin
      Inc(p);
      if not Digits(1, 2, fD) then Exit;
      haveD := True;
      if (p <= Length(s)) and (s[p] in ['T', ' ']) then
      begin
        Inc(p);
        if not Digits(1, 2, fH) then Exit;
        haveH := True;
        if (p <= Length(s)) and (s[p] = ':') then
        begin
          Inc(p);
          if not Digits(1, 2, fMi) then Exit;
          haveMi := True;
          if (p <= Length(s)) and (s[p] = ':') then
          begin
            Inc(p);
            if not Digits(1, 2, fS) then Exit;
            haveS := True;
            if (p <= Length(s)) and (s[p] in ['.', ',']) then
            begin
              Inc(p);
              if not Digits(1, MaxInt, fMs) then Exit;
              haveMs := True;
            end;
          end;
        end;
        if (p <= Length(s)) and (s[p] = 'Z') then
        begin
          Inc(p);
          haveZone := True;
          zoneZ := True;
        end
        else if (p <= Length(s)) and (s[p] in ['+', '-']) then
        begin
          if s[p] = '-' then sign := -1 else sign := 1;
          Inc(p);
          { `[+-]\d\d:?\d\d`, and only the sign and the hours are read:
            `hour -= +match[8].slice(0, 3)` }
          if not Digits(2, 2, fZ) then Exit;
          zoneH := sign * StrToInt(fZ);
          if (p <= Length(s)) and (s[p] = ':') then Inc(p);
          { the zone's minutes are matched and never read }
          if not Digits(2, 2, fZ) then Exit;
          haveZone := True;
        end;
      end;
    end;
  end;
  if p <= Length(s) then Exit;     // `$`: anything left is no match

  { ---- the fields, as parseDate reads them ----
    [Batch 53: this REJECTED out-of-range fields, took '.5' as half a
    second and read the zone's minutes. Upstream hands the fields to
    Date.UTC / new Date, which carries them over (month 13 is next January),
    takes `+fraction.substring(0, 3)` (so '.5' is 5 ms) and reads the offset
    as `+match[8].slice(0, 3)` (whole hours only).] }
  y := Num(fY);
  { `+(match[2] || 1) - 1`: a month written 0 is the December before }
  if haveMo then mo := Num(fMo) - 1 else mo := 0;
  { `+match[3] || 1`: a day of nought is falsy and becomes the first }
  d := 0;
  if haveD then d := Num(fD);
  if d = 0 then d := 1;
  h := 0;
  if haveH then h := Num(fH);
  mi := 0;
  if haveMi then mi := Num(fMi);
  sec := 0;
  if haveS then sec := Num(fS);
  ms := 0;
  if haveMs then ms := Num(Copy(fMs, 1, 3));
  if haveZone and not zoneZ then h := h - zoneH;
  { Date.UTC and new Date: a year 0..99 is 1900 + it }
  if (y >= 0) and (y <= 99) then y := y + 1900;
  { MakeDay: the month carries into the year }
  if mo >= 0 then
  begin
    y := y + mo div 12;
    mo := mo mod 12;
  end
  else
  begin
    y := y + (mo - 11) div 12;
    mo := mo - ((mo - 11) div 12) * 12;
  end;
  days := DaysFromCivil(y, mo + 1) + (d - 1);
  total := days * Int64(86400000) + ((h * 60 + mi) * 60 + sec) * 1000 + ms;
  if (not haveZone) and (not AAssumeUTC) then
    { LOCAL: new Date(...). GetLocalTimeOffset is UTC-minus-local in
      minutes -- today's, since FPC 3.2.2 has no offset-at-a-date. }
    total := total + Int64(GetLocalTimeOffset) * 60000;
  { No TimeClip: a four-digit year and two-digit fields reach year 10007 at
    most, nowhere near the +-8.64e15 ms a Date can hold. }
  AMs := total;
  Result := True;
end;

{ ==================== TTyOrdinalMeta ==================== }

constructor TTyOrdinalMeta.Create;
begin
  inherited Create;
  FNeedCollect := True;
  FDeduplication := True;
end;

destructor TTyOrdinalMeta.Destroy;
begin
  FreeAndNil(FMap);
  inherited Destroy;
end;

procedure TTyOrdinalMeta.EnsureMap;
var
  i: Integer;
begin
  if FMap <> nil then Exit;
  FMap := TStringList.Create;
  FMap.CaseSensitive := True;
  FMap.Duplicates := dupIgnore;
  FMap.Sorted := True;
  for i := 0 to FCount - 1 do
    FMap.AddObject(FCategories[i], TObject(PtrInt(i)));
end;

procedure TTyOrdinalMeta.Add(const ACategory: string);
begin
  if FCount = Length(FCategories) then
    SetLength(FCategories, 8 + Length(FCategories) * 2);
  FCategories[FCount] := ACategory;
  if FMap <> nil then
    FMap.AddObject(ACategory, TObject(PtrInt(FCount)));
  Inc(FCount);
end;

procedure TTyOrdinalMeta.SetCategories(const A: array of string);
var
  i: Integer;
begin
  FreeAndNil(FMap);
  SetLength(FCategories, Length(A));
  for i := 0 to High(A) do
    FCategories[i] := A[i];
  FCount := Length(A);
  FNeedCollect := False;
end;

function TTyOrdinalMeta.Count: Integer;
begin
  Result := FCount;
end;

function TTyOrdinalMeta.CategoryAt(AOrdinal: Integer): string;
begin
  if (AOrdinal < 0) or (AOrdinal >= FCount) then Exit('');
  Result := FCategories[AOrdinal];
end;

function TTyOrdinalMeta.GetOrdinal(const ACategory: string): Integer;
var
  i: Integer;
begin
  EnsureMap;
  i := FMap.IndexOf(ACategory);
  if i < 0 then Exit(-1);
  Result := PtrInt(FMap.Objects[i]);
end;

procedure TTyOrdinalMeta.ResetCollected;
begin
  if not FNeedCollect then Exit;
  FCategories := nil;
  FCount := 0;
  FreeAndNil(FMap);
end;

function TTyOrdinalMeta.ParseAndCollect(const ACategory: string): Integer;
begin
  if FNeedCollect and (not FDeduplication) then
  begin
    { Appends blind, which is the point: no map is built and no comparison is
      made. Only legitimate when the caller knows the values are distinct. }
    Result := FCount;
    Add(ACategory);
    Exit;
  end;
  Result := GetOrdinal(ACategory);
  if Result >= 0 then Exit;
  if not FNeedCollect then Exit(-1);
  Result := FCount;
  Add(ACategory);
end;

{ ==================== override keys ==================== }

function TyOverrideKey(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(GOverrideKeys) do
    if GOverrideKeys[i] = AName then Exit(i);
  i := Length(GOverrideKeys);
  SetLength(GOverrideKeys, i + 1);
  GOverrideKeys[i] := AName;
  Result := i;
end;

function TyOverrideKeyName(AKey: Integer): string;
begin
  if (AKey < 0) or (AKey > High(GOverrideKeys)) then Exit('');
  Result := GOverrideKeys[AKey];
end;

function TyOverrideKeyCount: Integer;
begin
  Result := Length(GOverrideKeys);
end;

{ ==================== TTyDataStore ==================== }

constructor TTyDataStore.Create;
begin
  inherited Create;
end;

destructor TTyDataStore.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FDims) do
    if FDims[i].MetaOwned then
      FDims[i].Meta.Free;
  inherited Destroy;
end;

function TTyDataStore.AddDimension(const AName: string; AType: TTyDimType): Integer;
var
  i: Integer;
begin
  Result := Length(FDims);
  SetLength(FDims, Result + 1);
  SetLength(FCols, Result + 1);
  FDims[Result].Name := AName;
  FDims[Result].Kind := AType;
  FDims[Result].RawMin := Infinity;
  FDims[Result].RawMax := NegInfinity;
  if AType = ddtOrdinal then
  begin
    FDims[Result].Meta := TTyOrdinalMeta.Create;
    FDims[Result].MetaOwned := True;
  end;
  if FCapacity > 0 then
  begin
    SetLength(FCols[Result], FCapacity);
    { A dimension added after filling -- a stacking calculation appends two --
      has no data for the rows already there, and no data is NaN, not zero. }
    for i := 0 to FRawCount - 1 do
      FCols[Result][i] := NaN;
  end;
end;

function TTyDataStore.DimCount: Integer;
begin
  Result := Length(FDims);
end;

function TTyDataStore.DimIndexOf(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FDims) do
    if FDims[i].Name = AName then Exit(i);
  Result := -1;
end;

function TTyDataStore.DimsOfCoord(const ACoord: string): TTyIntegerArray;
var i, n: Integer;
begin
  Result := nil;
  if ACoord = '' then Exit;
  n := 0;
  SetLength(Result, Length(FDims));
  for i := 0 to High(FDims) do
    if FDims[i].Coord = ACoord then
    begin
      Result[n] := i;
      Inc(n);
    end;
  SetLength(Result, n);
  if n > 0 then Exit;
  { NOTHING WAS MAPPED, so the coordinate is the column of that name -- which
    is every store the port built before a series needed more than one. }
  i := DimIndexOf(ACoord);
  if i < 0 then Exit;
  SetLength(Result, 1);
  Result[0] := i;
end;

procedure TTyDataStore.SetDimCoord(ADim: Integer; const ACoord: string);
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit;
  FDims[ADim].Coord := ACoord;
end;

function TTyDataStore.DimCoord(ADim: Integer): string;
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit('');
  Result := FDims[ADim].Coord;
end;

function TTyDataStore.DimName(ADim: Integer): string;
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit('');
  Result := FDims[ADim].Name;
end;

function TTyDataStore.DimType(ADim: Integer): TTyDimType;
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit(ddtFloat);
  Result := FDims[ADim].Kind;
end;

procedure TTyDataStore.SetCategories(ADim: Integer; const A: array of string);
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit;
  if FDims[ADim].Meta = nil then
    raise EInvalidOperation.CreateFmt(
      'SetCategories: dimension "%s" is not ordinal', [FDims[ADim].Name]);
  if FRawCount > 0 then
    raise EInvalidOperation.CreateFmt(
      'SetCategories: dimension "%s" already holds %d rows', [FDims[ADim].Name, FRawCount]);
  { A series telling the axis what its categories are is backwards. The builder
    sets them on the axis' own list; a store that borrowed one must not
    overwrite what every other series on that axis is reading. }
  if not FDims[ADim].MetaOwned then
    raise EInvalidOperation.CreateFmt(
      'SetCategories: dimension "%s" borrows its category list from the axis',
      [FDims[ADim].Name]);
  FDims[ADim].Meta.SetCategories(A);
end;

procedure TTyDataStore.UseOrdinalMeta(ADim: Integer; AMeta: TTyOrdinalMeta);
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit;
  if FDims[ADim].Kind <> ddtOrdinal then
    raise EInvalidOperation.CreateFmt(
      'UseOrdinalMeta: dimension "%s" is not ordinal', [FDims[ADim].Name]);
  if FRawCount > 0 then
    raise EInvalidOperation.CreateFmt(
      'UseOrdinalMeta: dimension "%s" already holds %d rows', [FDims[ADim].Name, FRawCount]);
  if AMeta = nil then Exit;
  if FDims[ADim].MetaOwned then
    FreeAndNil(FDims[ADim].Meta);
  FDims[ADim].Meta := AMeta;
  FDims[ADim].MetaOwned := False;
end;

function TTyDataStore.CategoryCount(ADim: Integer): Integer;
begin
  if (ADim < 0) or (ADim > High(FDims)) or (FDims[ADim].Meta = nil) then Exit(0);
  Result := FDims[ADim].Meta.Count;
end;

function TTyDataStore.CategoryAt(ADim, AOrdinal: Integer): string;
begin
  if (ADim < 0) or (ADim > High(FDims)) or (FDims[ADim].Meta = nil) then Exit('');
  Result := FDims[ADim].Meta.CategoryAt(AOrdinal);
end;

function TTyDataStore.OrdinalMeta(ADim: Integer): TTyOrdinalMeta;
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit(nil);
  Result := FDims[ADim].Meta;
end;

procedure TTyDataStore.CheckAppendable;
begin
  { ECharts asserts the same thing. A row appended while a filter is active
    would land outside the index vector and be invisible until the filter was
    lifted, which looks exactly like data loss. }
  if FFiltered then
    raise EInvalidOperation.Create('AppendRow: the store is filtered; call RestoreAll first');
end;

procedure TTyDataStore.Grow(AWanted: Integer);
var
  i, cap: Integer;
begin
  if AWanted <= FCapacity then Exit;
  cap := FCapacity;
  if cap = 0 then cap := 16;
  while cap < AWanted do cap := cap * 2;
  for i := 0 to High(FCols) do
    SetLength(FCols[i], cap);
  if FIds <> nil then SetLength(FIds, cap);
  if FNames <> nil then SetLength(FNames, cap);
  if FRawItems <> nil then SetLength(FRawItems, cap);
  if FOvrHead <> nil then
  begin
    SetLength(FOvrHead, cap);
    for i := FCapacity to cap - 1 do
      FOvrHead[i] := -1;
  end;
  FCapacity := cap;
end;

procedure TTyDataStore.RetireInverted;
var i: Integer;
begin
  for i := 0 to High(FDims) do
    FDims[i].HasInverted := False;
end;

procedure TTyDataStore.SetCalculated(ADim, ARawIndex: Integer; AValue: Double);
begin
  if (ADim < 0) or (ADim > High(FDims)) then
    raise EInvalidOperation.CreateFmt(
      'SetCalculated: no dimension %d', [ADim]);
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then
    raise EInvalidOperation.CreateFmt(
      'SetCalculated: row %d is outside the %d rows there are',
      [ARawIndex, FRawCount]);
  if FDims[ADim].Kind = ddtOrdinal then
    raise EInvalidOperation.CreateFmt(
      'SetCalculated: dimension "%s" is ordinal; a calculated column holds a '
      + 'number, and writing an ordinal index without interning it would make '
      + 'the category list disagree with the column', [FDims[ADim].Name]);
  FCols[ADim][ARawIndex] := AValue;
  { TWO THINGS GO STALE, and only one of them is the cache.

    The cache is per filter and keyed by nothing else, so a write that left it
    alone would be invisible exactly where it matters most: the value axis is
    sized from DataExtent, and a stacked series that did not widen the axis
    draws off the top of the plot with nothing raising.

    The other is DataExtent's FAST PATH, which answers the unfiltered case --
    the one the value axis asks -- from RawMin/RawMax. Those are maintained
    during append, and this column was never appended to: AddDimension leaves
    them as the empty range, so the fast path would report no data at all.

    Marked rather than widened. Widening them here is right only while every
    cell is written exactly once; a public setter cannot promise that, and an
    overwrite with a smaller value would leave a monotone RawMin too wide for
    good. Skipping the fast path is correct whatever the write order. }
  FDims[ADim].HasCalculated := True;
  InvalidateExtents;
end;

procedure TTyDataStore.InvalidateExtents;
var
  i: Integer;
  f: TTyExtentFilter;
begin
  for i := 0 to High(FDims) do
    for f := Low(TTyExtentFilter) to High(TTyExtentFilter) do
      FDims[i].CacheOk[f] := False;
end;

function TTyDataStore.ParseCell(ADim: Integer; const AValue: TTyDataValue): Double;
var
  meta: TTyOrdinalMeta;
  ord_: Integer;
begin
  if FDims[ADim].Kind <> ddtOrdinal then
    Exit(TyParseDataValue(AValue, FDims[ADim].Kind));

  meta := FDims[ADim].Meta;
  ord_ := -1;
  case AValue.Kind of
    dvkNone:
      Exit(NaN);
    dvkNumber:
      begin
        { A number that is not a number names no category either way. Without
          this the collecting branch would intern a category called 'Nan'. }
        if IsNan(AValue.Num) or IsInfinite(AValue.Num) then Exit(NaN);
        if meta.NeedCollect then
        begin
          { A number arriving at a collecting dimension is a category LABEL --
            years in `[[2001, 12], [2002, 15]]` are categories, not indices. }
          { as JavaScript names it -- 0.30000000000000004, 1e+21 -- where
            FloatToStr kept fifteen digits and wrote 1E21 }
          ord_ := meta.ParseAndCollect(TyJsNumberToString(AValue.Num));
        end
        else
        begin
          { A fixed category list gives a number its other meaning: the INDEX of
            a category, which is ECharts' documented shorthand -- and taken as
            it is, as upstream's parseAndCollect returns it: an index past the
            list is still a place on the axis, which a max or 'dataMax' can
            reach, and which the plot clips otherwise.
            [Revised in batch 44: out of range, or fractional, was a gap.] }
          Exit(AValue.Num);
        end;
      end;
    dvkBool:
      Exit(NaN);
  else
    { Text, verbatim. An ordinal dimension does NOT treat '-' or the empty
      string as no-data: on a category axis they are category names like any
      other, which is what ECharts does by returning early for ordinal before
      its no-data rules run. }
    ord_ := meta.ParseAndCollect(AValue.Text);
  end;
  if ord_ < 0 then Exit(NaN);
  Result := ord_;
end;

procedure TTyDataStore.NoteValue(ADim: Integer; AValue: Double);
begin
  { AN INFINITY IS AN EXTENT END, as upstream's store keeps it: it is the
    AXIS that then drops a series whose extent is not finite. }
  if IsNan(AValue) then Exit;
  if AValue < FDims[ADim].RawMin then FDims[ADim].RawMin := AValue;
  if AValue > FDims[ADim].RawMax then FDims[ADim].RawMax := AValue;
end;

function TTyDataStore.AppendRow(const AValues: array of TTyDataValue): Integer;
var
  i: Integer;
  v: Double;
begin
  CheckAppendable;
  Grow(FRawCount + 1);
  Result := FRawCount;
  for i := 0 to High(FCols) do
  begin
    if i <= High(AValues) then
      v := ParseCell(i, AValues[i])
    else
      v := NaN;
    FCols[i][Result] := v;
    NoteValue(i, v);
  end;
  Inc(FRawCount);
  FCount := FRawCount;
  InvalidateExtents;
  RetireInverted;
end;

function TTyDataStore.AppendRow(const AValues: array of Double): Integer;
var
  i: Integer;
  v: Double;
begin
  CheckAppendable;
  Grow(FRawCount + 1);
  Result := FRawCount;
  for i := 0 to High(FCols) do
  begin
    if i <= High(AValues) then
    begin
      v := AValues[i];
      if (FDims[i].Kind = ddtInt) and (not IsNan(v)) and (not IsInfinite(v)) then
        v := Trunc(v);
    end
    else
      v := NaN;
    FCols[i][Result] := v;
    NoteValue(i, v);
  end;
  Inc(FRawCount);
  FCount := FRawCount;
  InvalidateExtents;
  RetireInverted;
end;

procedure TTyDataStore.Clear;
var
  i: Integer;
begin
  FRawCount := 0;
  FCount := 0;
  FIndices := nil;
  FFiltered := False;
  FIds := nil;
  FNames := nil;
  FRawItems := nil;
  FRawDimNames := nil;
  FRawDimPos := nil;
  FRawDimInfo := nil;
  FTipPos := nil;
  FLabelPos := nil;
  FHasTipPos := False;
  FHasLabelPos := False;
  FRawWidth := 0;
  FOvrHead := nil;
  FOvr := nil;
  FOvrCount := 0;
  for i := 0 to High(FDims) do
  begin
    FDims[i].RawMin := Infinity;
    FDims[i].RawMax := NegInfinity;
    FDims[i].HasInverted := False;
    FDims[i].Inverted := nil;
    { Only the OWNER resets. A borrowed list belongs to the axis, and wiping
      it here would drop the categories another series had already
      contributed -- leaving that series' ordinal column pointing at names
      that no longer exist. The builder resets each axis' list once, before
      refilling any store. }
    if (FDims[i].Meta <> nil) and FDims[i].MetaOwned then
      FDims[i].Meta.ResetCollected;
  end;
  InvalidateExtents;
end;

function TTyDataStore.Count: Integer;
begin
  Result := FCount;
end;

function TTyDataStore.RawCount: Integer;
begin
  Result := FRawCount;
end;

function TTyDataStore.GetRawIndex(AIndex: Integer): Integer;
begin
  { ECharts swaps a method pointer between identity and indirection here. That
    is a JS engine optimisation -- a monomorphic call site beats a branch. In
    compiled code the branch is cheaper than the indirect call, so this stays a
    branch. }
  if (AIndex < 0) or (AIndex >= FCount) then Exit(-1);
  if not FFiltered then Exit(AIndex);
  Result := FIndices[AIndex];
end;

function TTyDataStore.IndexOfRawIndex(ARawIndex: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then Exit(-1);
  if not FFiltered then Exit(ARawIndex);
  { The rows kept are ascending, so if the row at this position IS this row, no
    search is needed -- which is the common case for the unfiltered head of a
    window. }
  if (ARawIndex < FCount) and (FIndices[ARawIndex] = ARawIndex) then Exit(ARawIndex);
  lo := 0;
  hi := FCount - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if FIndices[mid] < ARawIndex then lo := mid + 1
    else if FIndices[mid] > ARawIndex then hi := mid - 1
    else Exit(mid);
  end;
  Result := -1;
end;

function TTyDataStore.Get(ADim, AIndex: Integer): Double;
var
  raw: Integer;
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit(NaN);
  raw := GetRawIndex(AIndex);
  if raw < 0 then Exit(NaN);
  Result := FCols[ADim][raw];
end;

function TTyDataStore.GetByRaw(ADim, ARawIndex: Integer): Double;
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit(NaN);
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then Exit(NaN);
  Result := FCols[ADim][ARawIndex];
end;

function TTyDataStore.GetOrdinalText(ADim, AIndex: Integer): string;
var
  v: Double;
begin
  if (ADim < 0) or (ADim > High(FDims)) or (FDims[ADim].Meta = nil) then Exit('');
  v := Get(ADim, AIndex);
  if IsNan(v) then Exit('');
  Result := FDims[ADim].Meta.CategoryAt(Trunc(v));
end;

{ ---- identity ---- }

procedure TTyDataStore.SetId(ARawIndex: Integer; const AId: string);
begin
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then Exit;
  if FIds = nil then SetLength(FIds, FCapacity);
  FIds[ARawIndex] := AId;
end;

procedure TTyDataStore.SetName(ARawIndex: Integer; const AName: string);
begin
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then Exit;
  if FNames = nil then SetLength(FNames, FCapacity);
  FNames[ARawIndex] := AName;
end;

function TTyDataStore.GetId(AIndex: Integer): string;
var
  raw: Integer;
begin
  if FIds = nil then Exit('');
  raw := GetRawIndex(AIndex);
  if raw < 0 then Exit('');
  Result := FIds[raw];
end;

function TTyDataStore.GetIdByRaw(ARawIndex: Integer): string;
begin
  if FIds = nil then Exit('');
  if (ARawIndex < 0) or (ARawIndex > High(FIds)) then Exit('');
  Result := FIds[ARawIndex];
end;

function TTyDataStore.GetName(AIndex: Integer): string;
var
  raw: Integer;
begin
  if FNames = nil then Exit('');
  raw := GetRawIndex(AIndex);
  if raw < 0 then Exit('');
  Result := FNames[raw];
end;

function TTyDataStore.GetItemName(AIndex: Integer): string;
var i: Integer;
begin
  Result := GetName(AIndex);
  if Result <> '' then Exit;
  for i := 0 to High(FDims) do
    if FDims[i].Kind = ddtOrdinal then
      Exit(GetOrdinalText(i, AIndex));
end;

function TTyDataStore.GetNameByRaw(ARawIndex: Integer): string;
begin
  if FNames = nil then Exit('');
  if (ARawIndex < 0) or (ARawIndex > High(FNames)) then Exit('');
  Result := FNames[ARawIndex];
end;

procedure TTyDataStore.SetRawItem(ARawIndex: Integer; const AItem: TTyRawItem);
begin
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then Exit;
  if FRawItems = nil then SetLength(FRawItems, FCapacity);
  FRawItems[ARawIndex] := AItem;
end;

function TTyDataStore.RawItemByRaw(ARawIndex: Integer): TTyRawItem;
begin
  Result := Default(TTyRawItem);
  if FRawItems = nil then Exit;
  if (ARawIndex < 0) or (ARawIndex > High(FRawItems)) or (ARawIndex >= FRawCount) then
    Exit;
  Result := FRawItems[ARawIndex];
end;

function TTyDataStore.RawItem(AIndex: Integer): TTyRawItem;
var raw: Integer;
begin
  Result := Default(TTyRawItem);
  if FRawItems = nil then Exit;
  raw := GetRawIndex(AIndex);
  if raw < 0 then Exit;
  Result := RawItemByRaw(raw);
end;

function TTyDataStore.HasRawItems: Boolean;
begin
  Result := FRawItems <> nil;
end;

procedure TTyDataStore.SetRawDimPos(ADim, APos: Integer);
var i: Integer;
begin
  if ADim < 0 then Exit;
  if ADim > High(FRawDimPos) then
  begin
    i := Length(FRawDimPos);
    SetLength(FRawDimPos, ADim + 1);
    for i := i to ADim do FRawDimPos[i] := i;
  end;
  FRawDimPos[ADim] := APos;
end;

procedure TTyDataStore.GrowRawDimInfo(APos: Integer);
var i: Integer;
begin
  if APos <= High(FRawDimInfo) then Exit;
  i := Length(FRawDimInfo);
  SetLength(FRawDimInfo, APos + 1);
  for i := i to APos do FRawDimInfo[i] := Default(TTyRawDimInfo);
end;

procedure TTyDataStore.SetRawDimDisplay(APos: Integer; const AName: string);
begin
  if APos < 0 then Exit;
  GrowRawDimInfo(APos);
  FRawDimInfo[APos].Display := AName;
  FRawDimInfo[APos].HasDisplay := True;
end;

procedure TTyDataStore.SetRawDimType(APos: Integer; AType: TTyDimType);
begin
  if APos < 0 then Exit;
  GrowRawDimInfo(APos);
  FRawDimInfo[APos].DimType := AType;
  FRawDimInfo[APos].HasType := True;
end;

function TTyDataStore.RawDimInfo(APos: Integer): TTyRawDimInfo;
begin
  if (APos >= 0) and (APos <= High(FRawDimInfo)) then Result := FRawDimInfo[APos]
  else Result := Default(TTyRawDimInfo);
end;

function TTyDataStore.RawPosType(APos: Integer): TTyDimType;
var k: Integer;
begin
  { A COLUMN READING IT decides -- the coordinate system's type outranks
    the source's, as upstream's createDimensions has it. }
  for k := 0 to DimCount - 1 do
    if RawDimPos(k) = APos then Exit(DimType(k));
  if (APos >= 0) and (APos <= High(FRawDimInfo)) and FRawDimInfo[APos].HasType then
    Exit(FRawDimInfo[APos].DimType);
  Result := ddtFloat;
end;

procedure TTyDataStore.GuessRawOrdinals(AOriginal: Boolean);
var
  width, p, i, k, n: Integer;
  it: TTyRawItem;
  c: TTyDataValue;
  read, verdict, decided: Boolean;
  num: Double;
  mask: TFPUExceptionMask;
begin
  if FRawItems = nil then Exit;
  n := Min(5, FRawCount);
  width := Length(FRawDimNames);
  for i := 0 to n - 1 do
  begin
    it := RawItemByRaw(i);
    if Length(it.Cells) > width then width := Length(it.Cells);
  end;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exPrecision]);
  try
    for p := 0 to width - 1 do
    begin
      read := False;
      for k := 0 to DimCount - 1 do
        if RawDimPos(k) = p then read := True;
      if read or RawDimInfo(p).HasType then Continue;
      verdict := False;
      decided := False;
      for i := 0 to n - 1 do
      begin
        it := RawItemByRaw(i);
        if it.Shape in [rshArray, rshObject] then
        begin
          if p > High(it.Cells) then Continue;
          c := it.Cells[p];
        end
        else if AOriginal then
          Break // a non-array item: upstream answers "not ordinal"
        else
          Continue;
        { detectValue: a finite Number() that is not '' -- not ordinal;
          other text but '-' -- ordinal; anything else tells nothing. }
        case c.Kind of
          dvkNumber:
            if not (IsNan(c.Num) or IsInfinite(c.Num)) then decided := True;
          dvkBool:
            decided := True;
          dvkText:
            begin
              num := TyJsToNumber(c.Text);
              if (c.Text <> '') and not (IsNan(num) or IsInfinite(num)) then
                decided := True
              else if c.Text <> '-' then
              begin
                decided := True;
                verdict := True;
              end;
            end;
        end;
        if decided then Break;
      end;
      if verdict then SetRawDimType(p, ddtOrdinal);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

procedure TTyDataStore.SetTooltipPositions(const APos: TTyIntegerArray);
begin
  FTipPos := Copy(APos);
  FHasTipPos := True;
end;

procedure TTyDataStore.SetLabelPositions(const APos: TTyIntegerArray);
begin
  FLabelPos := Copy(APos);
  FHasLabelPos := True;
end;

function TTyDataStore.TooltipPositions: TTyIntegerArray;
begin
  Result := Copy(FTipPos);
end;

function TTyDataStore.LabelPositions: TTyIntegerArray;
begin
  Result := Copy(FLabelPos);
end;

function TTyDataStore.HasTooltipPositions: Boolean;
begin
  Result := FHasTipPos;
end;

function TTyDataStore.HasLabelPositions: Boolean;
begin
  Result := FHasLabelPos;
end;

function TTyDataStore.RawDimPos(ADim: Integer): Integer;
begin
  if (ADim >= 0) and (ADim <= High(FRawDimPos)) then Result := FRawDimPos[ADim]
  else Result := ADim;
end;

procedure TTyDataStore.SetRawDimName(APos: Integer; const AName: string);
var i: Integer;
begin
  if APos < 0 then Exit;
  if APos > High(FRawDimNames) then
  begin
    i := Length(FRawDimNames);
    SetLength(FRawDimNames, APos + 1);
    for i := i to APos do FRawDimNames[i] := '';
  end;
  FRawDimNames[APos] := AName;
end;

function TTyDataStore.RawDimName(APos: Integer): string;
begin
  Result := '';
  if (APos >= 0) and (APos <= High(FRawDimNames)) then Result := FRawDimNames[APos];
end;

function TTyDataStore.RawPosOf(const AKey: string): Double;
var i: Integer; mask: TFPUExceptionMask;
begin
  Result := NaN;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow]);
  try
    { `[n]`: the inside as a JavaScript number -- `[]` is nought. }
    if (Length(AKey) >= 2) and (AKey[1] = '[') and (AKey[Length(AKey)] = ']') then
      Exit(TyJsToNumber(Copy(AKey, 2, Length(AKey) - 2)));
    for i := 0 to High(FRawDimNames) do
      if (FRawDimNames[i] <> '') and (FRawDimNames[i] = AKey) then Exit(i);
    { `!isNaN(key)`: a numeric-looking name is a position. }
    Result := TyJsToNumber(AKey);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

class function TTyDataStore.RawCell(const AItem: TTyRawItem; APos: Double;
  out ACell: TTyDataValue): Boolean;
var p: Integer;
begin
  ACell := Default(TTyDataValue);
  Result := False;
  case AItem.Shape of
    rshScalar:
      begin
        ACell := AItem.Scalar;
        Result := True;
      end;
    rshArray, rshObject:
      begin
        if IsNan(APos) or IsInfinite(APos) or (Frac(APos) <> 0) then Exit;
        if (APos < 0) or (APos > High(AItem.Cells)) then Exit;
        p := Trunc(APos);
        ACell := AItem.Cells[p];
        Result := True;
      end;
  end;
end;

function TTyDataStore.HasIds: Boolean;
begin
  Result := FIds <> nil;
end;

function TTyDataStore.HasNames: Boolean;
begin
  Result := FNames <> nil;
end;

{ ---- overrides ---- }

procedure TTyDataStore.SetOverride(ARawIndex, AKey: Integer; const AValue: TTyDataValue);
var
  i, slot: Integer;
begin
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then Exit;
  if AKey < 0 then Exit;
  if FOvrHead = nil then
  begin
    SetLength(FOvrHead, FCapacity);
    for i := 0 to FCapacity - 1 do
      FOvrHead[i] := -1;
  end;
  i := FOvrHead[ARawIndex];
  while i >= 0 do
  begin
    if FOvr[i].Key = AKey then
    begin
      FOvr[i].Value := AValue;
      Exit;
    end;
    i := FOvr[i].Next;
  end;
  if FOvrCount = Length(FOvr) then
    SetLength(FOvr, 16 + Length(FOvr) * 2);
  slot := FOvrCount;
  Inc(FOvrCount);
  FOvr[slot].Key := AKey;
  FOvr[slot].Value := AValue;
  FOvr[slot].Next := FOvrHead[ARawIndex];
  FOvrHead[ARawIndex] := slot;
end;

function TTyDataStore.HasOverrideByRaw(ARawIndex, AKey: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  if FOvrHead = nil then Exit;
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then Exit;
  i := FOvrHead[ARawIndex];
  while i >= 0 do
  begin
    if FOvr[i].Key = AKey then Exit(True);
    i := FOvr[i].Next;
  end;
end;

function TTyDataStore.GetOverrideByRaw(ARawIndex, AKey: Integer): TTyDataValue;
var
  i: Integer;
begin
  Result := TyDataNone;
  if FOvrHead = nil then Exit;
  if (ARawIndex < 0) or (ARawIndex >= FRawCount) then Exit;
  i := FOvrHead[ARawIndex];
  while i >= 0 do
  begin
    if FOvr[i].Key = AKey then Exit(FOvr[i].Value);
    i := FOvr[i].Next;
  end;
end;

function TTyDataStore.HasOverride(AIndex, AKey: Integer): Boolean;
begin
  Result := HasOverrideByRaw(GetRawIndex(AIndex), AKey);
end;

function TTyDataStore.GetOverride(AIndex, AKey: Integer): TTyDataValue;
begin
  Result := GetOverrideByRaw(GetRawIndex(AIndex), AKey);
end;

function TTyDataStore.OverrideCount: Integer;
begin
  Result := FOvrCount;
end;

{ ---- extent ---- }

function TTyDataStore.DataExtent(ADim: Integer; out AMin, AMax: Double;
  AFilter: TTyExtentFilter): Boolean;
var
  i, raw: Integer;
  v, lo, hi: Double;
begin
  AMin := NaN;
  AMax := NaN;
  if (ADim < 0) or (ADim > High(FDims)) then Exit(False);

  if (not FFiltered) and (AFilter = defNone)
     and (not FDims[ADim].HasCalculated) then
  begin
    { Maintained during append, so the common case costs nothing -- and skipped
      entirely for a calculated column, which was never appended to and whose
      RawMin/RawMax are therefore still the empty range. }
    if FDims[ADim].RawMin > FDims[ADim].RawMax then Exit(False);
    AMin := FDims[ADim].RawMin;
    AMax := FDims[ADim].RawMax;
    Exit(True);
  end;

  if FDims[ADim].CacheOk[AFilter] then
  begin
    if FDims[ADim].CacheMin[AFilter] > FDims[ADim].CacheMax[AFilter] then Exit(False);
    AMin := FDims[ADim].CacheMin[AFilter];
    AMax := FDims[ADim].CacheMax[AFilter];
    Exit(True);
  end;

  lo := Infinity;
  hi := NegInfinity;
  for i := 0 to FCount - 1 do
  begin
    if FFiltered then raw := FIndices[i] else raw := i;
    v := FCols[ADim][raw];
    if IsNan(v) then Continue;
    { a log axis' filter is 0 < v < Infinity: it drops +Inf too }
    if (AFilter = defPositive) and ((v <= 0) or (v = Infinity)) then Continue;
    if v < lo then lo := v;
    if v > hi then hi := v;
  end;
  FDims[ADim].CacheMin[AFilter] := lo;
  FDims[ADim].CacheMax[AFilter] := hi;
  FDims[ADim].CacheOk[AFilter] := True;
  if lo > hi then Exit(False);
  AMin := lo;
  AMax := hi;
  Result := True;
end;

{ ---- inverted index ---- }

procedure TTyDataStore.BuildInvertedIndex(ADim: Integer);
var
  i, n, o: Integer;
  v: Double;
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit;
  if FDims[ADim].Meta = nil then
    raise EInvalidOperation.CreateFmt(
      'BuildInvertedIndex: dimension "%s" is not ordinal', [FDims[ADim].Name]);
  n := FDims[ADim].Meta.Count;
  SetLength(FDims[ADim].Inverted, n);
  for i := 0 to n - 1 do
    FDims[ADim].Inverted[i] := -1;
  for i := 0 to FRawCount - 1 do
  begin
    v := FCols[ADim][i];
    if IsNan(v) then Continue;
    o := Trunc(v);
    if (o >= 0) and (o < n) then
      FDims[ADim].Inverted[o] := i;
  end;
  FDims[ADim].HasInverted := True;
end;

function TTyDataStore.RawIndexOfOrdinal(ADim, AOrdinal: Integer): Integer;
begin
  if (ADim < 0) or (ADim > High(FDims)) then Exit(-1);
  { BUILT ON DEMAND, which is what the declaration has always promised. It used
    to raise instead, so a caller had to build the index explicitly AND know to
    rebuild it after every append -- and since an append did not even retire the
    old one, the two failure modes were "an exception" and "a confidently wrong
    row". An index is a cache; a cache nobody can forget to refresh is the only
    kind worth having. }
  if not FDims[ADim].HasInverted then
    BuildInvertedIndex(ADim);
  if (AOrdinal < 0) or (AOrdinal > High(FDims[ADim].Inverted)) then Exit(-1);
  Result := FDims[ADim].Inverted[AOrdinal];
end;

{ ---- filtering ---- }

procedure TTyDataStore.SetIndices(const A: array of Integer; ACount: Integer);
var
  i: Integer;
begin
  if ACount >= FRawCount then
  begin
    FIndices := nil;
    FFiltered := False;
    FCount := FRawCount;
  end
  else
  begin
    SetLength(FIndices, ACount);
    for i := 0 to ACount - 1 do
      FIndices[i] := A[i];
    FFiltered := True;
    FCount := ACount;
  end;
  InvalidateExtents;
end;

procedure TTyDataStore.RestoreAll;
begin
  FIndices := nil;
  FFiltered := False;
  FCount := FRawCount;
  InvalidateExtents;
end;

procedure TTyDataStore.SelectRange(const ARanges: array of TTyDimRange);
var
  keep: array of Integer;
  i, k, raw, n: Integer;
  v: Double;
  ok: Boolean;
begin
  if Length(ARanges) = 0 then Exit;
  SetLength(keep, FCount);
  n := 0;
  for i := 0 to FCount - 1 do
  begin
    if FFiltered then raw := FIndices[i] else raw := i;
    ok := True;
    for k := 0 to High(ARanges) do
    begin
      if (ARanges[k].Dim < 0) or (ARanges[k].Dim > High(FDims)) then Continue;
      v := FCols[ARanges[k].Dim][raw];
      { NaN passes. See the declaration: a gap is data. }
      if IsNan(v) then Continue;
      if (v < ARanges[k].Min) or (v > ARanges[k].Max) then
      begin
        ok := False;
        Break;
      end;
    end;
    if ok then
    begin
      keep[n] := raw;
      Inc(n);
    end;
  end;
  SetIndices(keep, n);
end;

procedure TTyDataStore.SelectRange(ADim: Integer; AMin, AMax: Double);
var
  r: TTyDimRange;
begin
  r.Dim := ADim;
  r.Min := AMin;
  r.Max := AMax;
  SelectRange([r]);
end;

procedure TTyDataStore.FilterSelf(AFunc: TTyDataFilterFunc);
var
  keep: array of Integer;
  i, raw, n: Integer;
begin
  if AFunc = nil then Exit;
  SetLength(keep, FCount);
  n := 0;
  for i := 0 to FCount - 1 do
  begin
    if FFiltered then raw := FIndices[i] else raw := i;
    if AFunc(raw) then
    begin
      keep[n] := raw;
      Inc(n);
    end;
  end;
  SetIndices(keep, n);
end;

function TTyDataStore.IsFiltered: Boolean;
begin
  Result := FFiltered;
end;

end.
