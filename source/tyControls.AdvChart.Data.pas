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

  The numeric text rules are ECharts' parseDataValue: an empty string and a
  string that is not a number both give NaN, so the '-' that ECharts documents
  as "no data" needs no special case. Parsing uses a FIXED decimal point, never
  the locale's -- data text arrives from option text, where the separator is
  always '.', and reading it through a comma locale would turn 1.5 into NaN. }
function TyParseDataValue(const AValue: TTyDataValue; AType: TTyDimType): Double;

{ ---- time ---- }
{ ECharts' TIME_REG subset: yyyy, optionally -MM, -dd, then T or space and
  HH:mm:ss.fff, then Z or a +hh:mm offset. Slashes are accepted where dashes are.

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
  not. }
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
        Meta: TTyOrdinalMeta;       // owned; ordinal dimensions only
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
    FOvrHead: array of Integer;   // per raw row, -1 = no overrides
    FOvr: array of TOvr;
    FOvrCount: Integer;
    procedure Grow(AWanted: Integer);
    procedure InvalidateExtents;
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
    function GetName(AIndex: Integer): string;
    function HasIds: Boolean;
    function HasNames: Boolean;

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

function FixedFloatSettings: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := #0;
end;

function TextToNumber(const AText: string; out AValue: Double): Boolean;
var
  s: string;
begin
  AValue := NaN;
  s := Trim(AText);
  if s = '' then Exit(False);
  Result := TryStrToFloat(s, AValue, FixedFloatSettings);
  if not Result then AValue := NaN;
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
          dvkBool: Exit(NaN);   // a boolean names no instant
          { Round, then let the Int64 widen on the way out. Writing it as
            `Round(x) * 1.0` looks equivalent and is not: FPC types the untyped
            constant 1.0 as SINGLE, and the product loses everything below
            131,072 ms at epoch scale -- about half a day per year of drift. }
          dvkNumber: Exit(Round(AValue.Num));
          dvkText:
            if TyParseDateMs(AValue.Text, n) then Exit(n) else Exit(NaN);
        end;
        Exit(NaN);
      end;
  end;

  case AValue.Kind of
    dvkNone: n := NaN;
    dvkNumber, dvkBool: n := AValue.Num;
    dvkText: if not TextToNumber(AValue.Text, n) then n := NaN;
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

function TyParseDateMs(const AText: string; out AMs: Double;
  AAssumeUTC: Boolean): Boolean;
var
  s: string;
  p, y, mo, d, h, mi, sec, ms, n, offMin, offH, offM: Integer;
  days, total: Int64;
  sign: Integer;
  haveZone: Boolean;
begin
  AMs := NaN;
  Result := False;
  s := Trim(AText);
  if s = '' then Exit;

  p := 1;
  if not ScanInt(s, p, 4, y) then Exit;
  if p - 1 <> 4 then Exit;         // the year is exactly four digits

  mo := 1; d := 1; h := 0; mi := 0; sec := 0; ms := 0;
  offMin := 0;
  haveZone := False;

  if p <= Length(s) then
  begin
    if not (s[p] in ['-', '/']) then Exit;
    Inc(p);
    if not ScanInt(s, p, 2, mo) then Exit;
  end;

  if p <= Length(s) then
  begin
    if not (s[p] in ['-', '/']) then Exit;
    Inc(p);
    if not ScanInt(s, p, 2, d) then Exit;
  end;

  if (p <= Length(s)) and (s[p] in ['T', 't', ' ']) then
  begin
    Inc(p);
    if not ScanInt(s, p, 2, h) then Exit;
    if (p <= Length(s)) and (s[p] = ':') then
    begin
      Inc(p);
      if not ScanInt(s, p, 2, mi) then Exit;
      if (p <= Length(s)) and (s[p] = ':') then
      begin
        Inc(p);
        if not ScanInt(s, p, 2, sec) then Exit;
        if (p <= Length(s)) and (s[p] in ['.', ',']) then
        begin
          Inc(p);
          { Only the first three digits are milliseconds. The rest is finer than
            this store's resolution and is dropped rather than rounded, which is
            what ECharts does when it takes substring(0, 3). Fewer than three is
            padded, so .5 is half a second and not five milliseconds. }
          n := 0;
          ms := 0;
          while (p <= Length(s)) and (s[p] >= '0') and (s[p] <= '9') do
          begin
            if n < 3 then ms := ms * 10 + (Ord(s[p]) - Ord('0'));
            Inc(n);
            Inc(p);
          end;
          if n = 0 then Exit;
          while n < 3 do
          begin
            ms := ms * 10;
            Inc(n);
          end;
        end;
      end;
    end;
  end;

  if p <= Length(s) then
  begin
    if s[p] in ['Z', 'z'] then
    begin
      haveZone := True;
      Inc(p);
    end
    else if s[p] in ['+', '-'] then
    begin
      if s[p] = '-' then sign := -1 else sign := 1;
      Inc(p);
      if not ScanInt(s, p, 2, offH) then Exit;
      if (p <= Length(s)) and (s[p] = ':') then Inc(p);
      if not ScanInt(s, p, 2, offM) then Exit;
      if (offH > 23) or (offM > 59) then Exit;
      offMin := sign * (offH * 60 + offM);
      haveZone := True;
    end;
  end;

  if p <= Length(s) then Exit;     // trailing junk

  if (mo < 1) or (mo > 12) or (d < 1) or (h > 23) or (mi > 59) or (sec > 59) then Exit;
  if d > DaysInAMonth(y, mo) then Exit;

  { Integer arithmetic from here on. Building the instant as a TDateTime and
    scaling it by 86,400,000 would put the answer a fraction of a millisecond
    off the integer it should be, and every equality test downstream would then
    depend on which side it landed. }
  days := Round(EncodeDate(y, mo, d) - UnixEpochDT);
  total := days * Int64(86400000) + h * 3600000 + mi * 60000 + sec * 1000 + ms;
  if haveZone then
    total := total - Int64(offMin) * 60000
  else if not AAssumeUTC then
    { GetLocalTimeOffset is UTC-minus-local in minutes, which is the same sign
      convention LocalTimeToUniversal uses one indirection further down. }
    total := total + Int64(GetLocalTimeOffset) * 60000;
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
    FDims[Result].Meta := TTyOrdinalMeta.Create;
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
  FDims[ADim].Meta.SetCategories(A);
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
  if FOvrHead <> nil then
  begin
    SetLength(FOvrHead, cap);
    for i := FCapacity to cap - 1 do
      FOvrHead[i] := -1;
  end;
  FCapacity := cap;
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
  fs: TFormatSettings;
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
          fs := FixedFloatSettings;
          ord_ := meta.ParseAndCollect(FloatToStr(AValue.Num, fs));
        end
        else
        begin
          { A fixed category list gives a number its other meaning: the INDEX of
            a category, which is ECharts' documented shorthand. Out of range
            names no category, so it is a gap rather than a point drawn past the
            end of the axis. }
          if (AValue.Num < 0) or (AValue.Num >= meta.Count)
             or (Frac(AValue.Num) <> 0) then Exit(NaN);
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
  if IsNan(AValue) or IsInfinite(AValue) then Exit;
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
  FOvrHead := nil;
  FOvr := nil;
  FOvrCount := 0;
  for i := 0 to High(FDims) do
  begin
    FDims[i].RawMin := Infinity;
    FDims[i].RawMax := NegInfinity;
    FDims[i].HasInverted := False;
    FDims[i].Inverted := nil;
    if FDims[i].Meta <> nil then
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

function TTyDataStore.GetName(AIndex: Integer): string;
var
  raw: Integer;
begin
  if FNames = nil then Exit('');
  raw := GetRawIndex(AIndex);
  if raw < 0 then Exit('');
  Result := FNames[raw];
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

  if (not FFiltered) and (AFilter = defNone) then
  begin
    { Maintained during append, so the common case costs nothing. }
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
    if IsNan(v) or IsInfinite(v) then Continue;
    if (AFilter = defPositive) and (v <= 0) then Continue;
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
  if not FDims[ADim].HasInverted then
    raise EInvalidOperation.CreateFmt(
      'RawIndexOfOrdinal: no inverted index on "%s"', [FDims[ADim].Name]);
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
