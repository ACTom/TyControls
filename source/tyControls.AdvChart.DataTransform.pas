unit tyControls.AdvChart.DataTransform;
{$mode objfpc}{$H+}{$goto on}
{ `dataset.transform` -- the registry, the two transforms ECharts installs
  with its transform component ('filter' and 'sort'), and the one the boxplot
  series installs ('boxplot'). [Batch 133, roadmap D2]

  PORTED FROM src/data/helper/transform.ts (registerExternalTransform,
  applyDataTransform, applySingleDataTransform, createExternalSource),
  component/transform/filterTransform.ts, sortTransform.ts,
  util/conditionalExpression.ts and data/helper/dataValueHelper.ts of the
  ECharts 6.1 dist.

  THE CHAIN of datasets is tyControls.AdvChart.Dataset's (TTyDatasetCache);
  it hands this unit the upstream results and keeps the nodes made here.
  A RESULT IS A NODE in the shape a dataset is: `source`, `sourceHeader`,
  `seriesLayoutBy` ('column') and, when there are any, `dimensions` -- so a
  computed table is read by exactly the code that reads a written one.

  REGISTERING A TRANSFORM is one call: TyRegisterDataTransform('ns:name',
  @Proc). The procedure reads its upstream through TTyExternalSource (the
  methods upstream's ExternalSource has), reads AParams.Config, appends its
  results with TyAddTransformResult and raises ETyTransformError when the
  config is wrong -- the dataset then has no table, and the message is the
  diagnostic. A name in the 'echarts' namespace is a built-in and is called
  without it ('filter', not 'echarts:filter'); only a built-in may read raw
  rows (RawItem, RawData).

  WHAT IS NOT HERE: the filter's `reg` operator (a regular expression) --
  the port refuses the condition, where upstream matches; and `print`.

  ERRORS: upstream throws out of setOption on every one of them; here the
  dataset (and every dataset reading it) has no table, and the control says
  why in its diagnostics. }
interface

uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Dataset;

type
  { What a transform raises when its config cannot be honoured. }
  ETyTransformError = class(Exception);

  { One dimension of an upstream as a transform sees it (upstream's
    ExternalDimensionDefinition): its index, and its name and display name
    when it has them. }
  TTyTransformDim = record
    Index: Integer;
    HasName: Boolean;
    Name: string;
    HasDisplayName: Boolean;
    DisplayName: string;
  end;
  TTyTransformDimArray = array of TTyTransformDim;

  { A JavaScript value, as far as a condition or a sort needs one: what
    `typeof` would say, and the value. Data is the borrowed node of a list
    or an object. }
  TTyJsKind = (jkUndefined, jkNull, jkBool, jkNumber, jkString, jkArray, jkObject);
  TTyJsValue = record
    Kind: TTyJsKind;
    Bool: Boolean;
    Num: Double;
    Str: string;
    Data: TJSONData;
  end;

  { getRawValueParser: 'number' (parseFloat), 'time' (+parseDate), 'trim'. }
  TTyRawParser = (rpNone, rpNumber, rpTime, rpTrim);

  { UPSTREAM'S ExternalSource: one upstream table, read by column, its header
    lines hidden. Made for one call of one transform. }
  TTyExternalSource = class
  private
    FFields: TTySourceFields;
    FDims: TTyTransformDimArray;
    FBuiltIn: Boolean;
    FMade: TFPList;
    function NameIndex(const AName: string): Integer;
    function ItemAt(AIndex: Integer): TJSONData;
  public
    { Raises ETyTransformError where createExternalSource throws: a table
      laid out by row, a dimension name used twice, a source that is no
      table. }
    constructor Create(const AFields: TTySourceFields; ABuiltIn: Boolean);
    destructor Destroy; override;
    function SourceFormat: TTySourceFormat;
    function BuiltIn: Boolean;
    { count(): the rows below the header. }
    function Count: Integer;
    { getRawDataItem(i): the row itself (a made one for a table of columns,
      owned here). A built-in's only -- anything else raises. }
    function RawItem(AIndex: Integer): TJSONData;
    { getRawData(): the whole table, header lines included. A built-in's
      only, and only of a table of arrays or of objects. }
    function RawData: TJSONData;
    { cloneRawData(): a copy of the table; the caller owns it. }
    function CloneRawData: TJSONArray;
    { retrieveValueFromItem(item, dim): the cell, or nil for undefined. }
    function ValueOfItem(AItem: TJSONData; ADim: Integer): TJSONData;
    { retrieveValue(i, dim). }
    function RetrieveValue(AIndex, ADim: Integer): TJSONData;
    { getDimensionInfo(dim): a number is an index; a string is a name, or an
      index when it reads as a number and names nothing. -1 for none. }
    function DimensionOf(ADim: TJSONData): Integer;
    { cloneAllDimensionInfo(). }
    function DimCount: Integer;
    function Dim(AIndex: Integer): TTyTransformDim;
  end;
  TTyExternalSourceArray = array of TTyExternalSource;

  TTyTransformParams = record
    Upstream: TTyExternalSource;
    Upstreams: TTyExternalSourceArray;
    { the transform's `config`, borrowed; nil when it wrote none }
    Config: TJSONData;
    { THE CHART'S Math.random [Batch 134]: the xorshift32 state a transform
      that draws (ecStat's k-means) advances with TyJitterRandom. Never
      nil inside a transform. }
    Random: PLongWord;
  end;

  { One result: a table (a list of arrays or of objects) and, when the
    transform names its columns, their `dimensions`. A first result without
    dimensions inherits the upstream's header lines and names. Owned by the
    result list until the registry takes them. }
  TTyTransformResult = record
    Data: TJSONData;
    Dimensions: TJSONData;
  end;
  TTyTransformResultArray = array of TTyTransformResult;

  TTyDataTransformFunc = procedure(const AParams: TTyTransformParams;
    var AResults: TTyTransformResultArray);

  { Array.prototype.sort's comparator over indices: negative, 0, positive. }
  TTyJsCompare = function(A, B: Integer): Integer of object;

{ registerExternalTransform: AType must be 'namespace:name'; the 'echarts'
  namespace registers a built-in under its bare name. A second registration
  of a name replaces the first. False for a name without exactly one ':'. }
function TyRegisterDataTransform(const AType: string;
  AFunc: TTyDataTransformFunc): Boolean;
function TyFindDataTransform(const AType: string;
  out AFunc: TTyDataTransformFunc; out ABuiltIn: Boolean): Boolean;

{ Append one result; the list owns AData and ADimensions from here. }
procedure TyAddTransformResult(var AResults: TTyTransformResultArray;
  AData: TJSONData; ADimensions: TJSONData = nil);

{ applyDataTransform: ATransform (one transform, or a list of them piped)
  over the upstream results AUps. The result nodes are added to AOwner.
  False with the reason in AError where upstream throws. ARandom is the
  Math.random state the transforms draw from [Batch 134]; nil gives them
  one of their own, seeded with TyJitterSeed for this call. }
function TyApplyDataTransform(ATransform: TJSONData;
  const AUps: TTySourceRefArray; AOwner: TFPList;
  out AResults: TTySourceRefArray; out AError: string;
  ARandom: PLongWord = nil): Boolean;

{ ---- the value rules (dataValueHelper.ts) ---- }

function TyJsValueOf(AData: TJSONData): TTyJsValue;
function TyJsNumValue(AValue: Double): TTyJsValue;
{ numericToNumber: a number itself (minus nought nought), a numeric string
  its number, a list its text's when parseFloat and Number agree; anything
  else not-a-number. }
function TyJsNumericOf(const AValue: TTyJsValue): Double;
{ The parser called AName, False when there is none. }
function TyRawParserByName(const AName: string; out AParser: TTyRawParser): Boolean;
function TyApplyRawParser(AParser: TTyRawParser; const AValue: TTyJsValue): TTyJsValue;
{ JavaScript's `<` between strings: UTF-16 code units. }
function TyCompareJsStrings(const A, B: string): Integer;
{ SortOrderComparator.evaluate. AIncomparable is -Infinity or Infinity,
  AResultLT -1 (asc) or 1 (desc). }
function TySortOrderCompare(const L, R: TTyJsValue; AResultLT: Integer;
  AIncomparable: Double): Integer;

{ V8's Array.prototype.sort (TimSort: runs, binary insertion, galloping
  merges), on a list of indices -- the same order V8 gives whatever the
  comparator does, a comparator that is not consistent included. }
procedure TyJsArraySort(var AItems: TTyIntegerArray; ACompare: TTyJsCompare);

implementation

uses
  tyControls.AdvChart.Data, tyControls.AdvChart.Scale, tyControls.AdvChart.Jitter,
  tyControls.StrConsts;

{ ==================== JavaScript values ==================== }

function TyJsValueOf(AData: TJSONData): TTyJsValue;
begin
  Result := Default(TTyJsValue);
  Result.Kind := jkUndefined;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNull: Result.Kind := jkNull;
    jtBoolean:
      begin
        Result.Kind := jkBool;
        Result.Bool := AData.AsBoolean;
      end;
    jtNumber:
      begin
        Result.Kind := jkNumber;
        Result.Num := AData.AsFloat;
      end;
    jtString:
      begin
        Result.Kind := jkString;
        Result.Str := AData.AsString;
      end;
    jtArray:
      begin
        Result.Kind := jkArray;
        Result.Data := AData;
      end;
  else
    Result.Kind := jkObject;
    Result.Data := AData;
  end;
end;

function TyJsNumValue(AValue: Double): TTyJsValue;
begin
  Result := Default(TTyJsValue);
  Result.Kind := jkNumber;
  Result.Num := AValue;
end;

function StrValue(const AText: string): TTyJsValue;
begin
  Result := Default(TTyJsValue);
  Result.Kind := jkString;
  Result.Str := AText;
end;

{ String(v) }
function JsText(const V: TTyJsValue): string;
begin
  case V.Kind of
    jkUndefined: Result := 'undefined';
    jkNull: Result := 'null';
    jkBool: if V.Bool then Result := 'true' else Result := 'false';
    jkNumber: Result := TyJsNumberToString(V.Num);
    jkString: Result := V.Str;
  else
    Result := TyJsTextOf(V.Data);
  end;
end;

{ Number(v) }
function JsNumber(const V: TTyJsValue): Double;
begin
  case V.Kind of
    jkNull: Result := 0;
    jkBool: if V.Bool then Result := 1 else Result := 0;
    jkNumber: Result := V.Num;
    jkString: Result := TyJsToNumber(V.Str);
    jkArray: Result := TyJsToNumber(TyJsTextOf(V.Data));
  else
    Result := NaN;
  end;
end;

function TyJsNumericOf(const AValue: TTyJsValue): Double;
var f, n: Double; s: string;
begin
  case AValue.Kind of
    jkNumber:
      begin
        { parseFloat(String(x)) == x: minus nought comes back as nought }
        Result := AValue.Num;
        if (not IsNan(Result)) and (Result = 0) then Result := 0;
      end;
    jkString: Result := TyJsNumericToNumber(TyDataText(AValue.Str));
    jkArray:
      begin
        { `parseFloat(val) == val` -- the list compares as its text }
        s := TyJsTextOf(AValue.Data);
        f := TyJsParseFloat(s);
        n := TyJsToNumber(s);
        if IsNan(f) or IsNan(n) or (f <> n) then Result := NaN else Result := f;
      end;
  else
    Result := NaN;
  end;
end;

function TyRawParserByName(const AName: string; out AParser: TTyRawParser): Boolean;
begin
  Result := True;
  if AName = 'number' then AParser := rpNumber
  else if AName = 'time' then AParser := rpTime
  else if AName = 'trim' then AParser := rpTrim
  else
  begin
    AParser := rpNone;
    Result := False;
  end;
end;

function TyApplyRawParser(AParser: TTyRawParser; const AValue: TTyJsValue): TTyJsValue;
var ms, t: Double;
begin
  case AParser of
    { parseFloat(val): the value as text, its longest decimal prefix }
    rpNumber: Result := TyJsNumValue(TyJsParseFloat(JsText(AValue)));
    rpTime:
      begin
        { +parseDate(val): TIME_REG on a string; null and undefined are an
          invalid date; anything else new Date(Math.round(+val)), which
          TimeClip takes past 8.64e15 to not-a-number and minus nought to
          nought }
        case AValue.Kind of
          jkString:
            if TyParseDateMs(AValue.Str, ms) then t := ms else t := NaN;
          jkUndefined, jkNull: t := NaN;
        else
          t := TyJsRound(JsNumber(AValue));
          if IsNan(t) or IsInfinite(t) or (Abs(t) > 8.64e15) then t := NaN
          else if t = 0 then t := 0;
        end;
        Result := TyJsNumValue(t);
      end;
    rpTrim:
      if AValue.Kind = jkString then Result := StrValue(TyJsTrim(AValue.Str))
      else Result := AValue;
  else
    Result := AValue;
  end;
end;

function TyCompareJsStrings(const A, B: string): Integer;
var
  ua, ub: UnicodeString;
  i, n: Integer;
begin
  if A = B then Exit(0);
  ua := UTF8Decode(A);
  ub := UTF8Decode(B);
  n := Min(Length(ua), Length(ub));
  for i := 1 to n do
    if ua[i] <> ub[i] then
    begin
      if Ord(ua[i]) < Ord(ub[i]) then Exit(-1) else Exit(1);
    end;
  if Length(ua) < Length(ub) then Result := -1
  else if Length(ua) > Length(ub) then Result := 1
  else Result := 0;
end;

function TySortOrderCompare(const L, R: TTyJsValue; AResultLT: Integer;
  AIncomparable: Double): Integer;
var
  lf, rf: Double;
  lNot, rNot: Boolean;
begin
  if L.Kind = jkNumber then lf := L.Num else lf := TyJsNumericOf(L);
  if R.Kind = jkNumber then rf := R.Num else rf := TyJsNumericOf(R);
  lNot := IsNan(lf);
  rNot := IsNan(rf);
  if lNot then lf := AIncomparable;
  if rNot then rf := AIncomparable;
  if lNot and rNot then
  begin
    { two words compare as words; a word against anything else that is not
      a number is nought against the incomparable }
    if (L.Kind = jkString) and (R.Kind = jkString) then
    begin
      case TyCompareJsStrings(L.Str, R.Str) of
        -1: Exit(AResultLT);
        1: Exit(-AResultLT);
      else
        Exit(0);
      end;
    end;
    if L.Kind = jkString then lf := 0;
    if R.Kind = jkString then rf := 0;
  end;
  { neither side is not-a-number here }
  if lf < rf then Result := AResultLT
  else if lf > rf then Result := -AResultLT
  else Result := 0;
end;

{ ==================== V8's TimSort ==================== }

type
  TTyTimSort = class
  private
    FWork: TTyIntegerArray;
    FTemp: TTyIntegerArray;
    FCmp: TTyJsCompare;
    FMinGallop: Integer;
    FRunBase, FRunLen: TTyIntegerArray;
    FRuns: Integer;
    procedure BinaryInsertionSort(ALow, AStartArg, AHigh: Integer);
    function CountAndMakeRun(ALowArg, AHigh: Integer): Integer;
    function GallopLeft(const A: TTyIntegerArray; AKey, ABase, ALength, AHint: Integer): Integer;
    function GallopRight(const A: TTyIntegerArray; AKey, ABase, ALength, AHint: Integer): Integer;
    procedure MergeAt(I: Integer);
    procedure MergeLow(ABaseA, ALengthA, ABaseB, ALengthB: Integer);
    procedure MergeHigh(ABaseA, ALengthA, ABaseB, ALengthB: Integer);
    procedure MergeCollapse;
    procedure MergeForceCollapse;
    procedure PushRun(ABase, ALength: Integer);
  public
    procedure Sort(var AItems: TTyIntegerArray; ACompare: TTyJsCompare);
  end;

const
  cMinGallopWins = 7;

procedure CopyRange(const ASrc: TTyIntegerArray; ASrcPos: Integer;
  var ADst: TTyIntegerArray; ADstPos, ALength: Integer);
var i: Integer;
begin
  { the source and the destination may be one array: copy in the safe
    direction }
  if (Pointer(ASrc) = Pointer(ADst)) and (ASrcPos < ADstPos) then
    for i := ALength - 1 downto 0 do ADst[ADstPos + i] := ASrc[ASrcPos + i]
  else
    for i := 0 to ALength - 1 do ADst[ADstPos + i] := ASrc[ASrcPos + i];
end;

function ComputeMinRunLength(N: Integer): Integer;
var r: Integer;
begin
  r := 0;
  while N >= 64 do
  begin
    r := r or (N and 1);
    N := N shr 1;
  end;
  Result := N + r;
end;

procedure TTyTimSort.BinaryInsertionSort(ALow, AStartArg, AHigh: Integer);
var start, left, right, mid, pivot, p: Integer;
begin
  if ALow = AStartArg then start := AStartArg + 1 else start := AStartArg;
  while start < AHigh do
  begin
    left := ALow;
    right := start;
    pivot := FWork[start];
    while left < right do
    begin
      mid := left + ((right - left) shr 1);
      if FCmp(pivot, FWork[mid]) < 0 then right := mid else left := mid + 1;
    end;
    p := start;
    while p > left do
    begin
      FWork[p] := FWork[p - 1];
      Dec(p);
    end;
    FWork[left] := pivot;
    Inc(start);
  end;
end;

function TTyTimSort.CountAndMakeRun(ALowArg, AHigh: Integer): Integer;
var
  low, idx, a, b, t, prev: Integer;
  desc: Boolean;
begin
  low := ALowArg + 1;
  if low = AHigh then Exit(1);
  Result := 2;
  desc := FCmp(FWork[low], FWork[low - 1]) < 0;
  prev := FWork[low];
  idx := low + 1;
  while idx < AHigh do
  begin
    if desc then
    begin
      if FCmp(FWork[idx], prev) >= 0 then Break;
    end
    else if FCmp(FWork[idx], prev) < 0 then Break;
    prev := FWork[idx];
    Inc(Result);
    Inc(idx);
  end;
  if desc then
  begin
    a := ALowArg;
    b := ALowArg + Result - 1;
    while a < b do
    begin
      t := FWork[a];
      FWork[a] := FWork[b];
      FWork[b] := t;
      Inc(a);
      Dec(b);
    end;
  end;
end;

function TTyTimSort.GallopLeft(const A: TTyIntegerArray;
  AKey, ABase, ALength, AHint: Integer): Integer;
var lastOfs, offset, maxOfs, tmp, m: Integer;
begin
  lastOfs := 0;
  offset := 1;
  if FCmp(A[ABase + AHint], AKey) < 0 then
  begin
    maxOfs := ALength - AHint;
    while offset < maxOfs do
    begin
      if FCmp(A[ABase + AHint + offset], AKey) >= 0 then Break;
      lastOfs := offset;
      offset := (offset shl 1) + 1;
      if offset <= 0 then offset := maxOfs;
    end;
    if offset > maxOfs then offset := maxOfs;
    lastOfs := lastOfs + AHint;
    offset := offset + AHint;
  end
  else
  begin
    maxOfs := AHint + 1;
    while offset < maxOfs do
    begin
      if FCmp(A[ABase + AHint - offset], AKey) < 0 then Break;
      lastOfs := offset;
      offset := (offset shl 1) + 1;
      if offset <= 0 then offset := maxOfs;
    end;
    if offset > maxOfs then offset := maxOfs;
    tmp := lastOfs;
    lastOfs := AHint - offset;
    offset := AHint - tmp;
  end;
  Inc(lastOfs);
  while lastOfs < offset do
  begin
    m := lastOfs + ((offset - lastOfs) shr 1);
    if FCmp(A[ABase + m], AKey) < 0 then lastOfs := m + 1 else offset := m;
  end;
  Result := offset;
end;

function TTyTimSort.GallopRight(const A: TTyIntegerArray;
  AKey, ABase, ALength, AHint: Integer): Integer;
var lastOfs, offset, maxOfs, tmp, m: Integer;
begin
  lastOfs := 0;
  offset := 1;
  if FCmp(AKey, A[ABase + AHint]) < 0 then
  begin
    maxOfs := AHint + 1;
    while offset < maxOfs do
    begin
      if FCmp(AKey, A[ABase + AHint - offset]) >= 0 then Break;
      lastOfs := offset;
      offset := (offset shl 1) + 1;
      if offset <= 0 then offset := maxOfs;
    end;
    if offset > maxOfs then offset := maxOfs;
    tmp := lastOfs;
    lastOfs := AHint - offset;
    offset := AHint - tmp;
  end
  else
  begin
    maxOfs := ALength - AHint;
    while offset < maxOfs do
    begin
      if FCmp(AKey, A[ABase + AHint + offset]) < 0 then Break;
      lastOfs := offset;
      offset := (offset shl 1) + 1;
      if offset <= 0 then offset := maxOfs;
    end;
    if offset > maxOfs then offset := maxOfs;
    lastOfs := lastOfs + AHint;
    offset := offset + AHint;
  end;
  Inc(lastOfs);
  while lastOfs < offset do
  begin
    m := lastOfs + ((offset - lastOfs) shr 1);
    if FCmp(AKey, A[ABase + m]) < 0 then offset := m else lastOfs := m + 1;
  end;
  Result := offset;
end;

procedure TTyTimSort.MergeLow(ABaseA, ALengthA, ABaseB, ALengthB: Integer);
label Succeed, CopyB, Done;
var
  lengthA, lengthB, dest, cursorTemp, cursorB, minGallop, winsA, winsB: Integer;
  first: Boolean;
begin
  lengthA := ALengthA;
  lengthB := ALengthB;
  if Length(FTemp) < lengthA then SetLength(FTemp, lengthA);
  CopyRange(FWork, ABaseA, FTemp, 0, lengthA);
  dest := ABaseA;
  cursorTemp := 0;
  cursorB := ABaseB;
  FWork[dest] := FWork[cursorB];
  Inc(dest);
  Inc(cursorB);
  Dec(lengthB);
  if lengthB = 0 then goto Succeed;
  if lengthA = 1 then goto CopyB;
  minGallop := FMinGallop;
  while True do
  begin
    winsA := 0;
    winsB := 0;
    while True do
    begin
      if FCmp(FWork[cursorB], FTemp[cursorTemp]) < 0 then
      begin
        FWork[dest] := FWork[cursorB];
        Inc(dest);
        Inc(cursorB);
        Inc(winsB);
        Dec(lengthB);
        winsA := 0;
        if lengthB = 0 then goto Succeed;
        if winsB >= minGallop then Break;
      end
      else
      begin
        FWork[dest] := FTemp[cursorTemp];
        Inc(dest);
        Inc(cursorTemp);
        Inc(winsA);
        Dec(lengthA);
        winsB := 0;
        if lengthA = 1 then goto CopyB;
        if winsA >= minGallop then Break;
      end;
    end;
    Inc(minGallop);
    first := True;
    while (winsA >= cMinGallopWins) or (winsB >= cMinGallopWins) or first do
    begin
      first := False;
      minGallop := Max(1, minGallop - 1);
      FMinGallop := minGallop;
      winsA := GallopRight(FTemp, FWork[cursorB], cursorTemp, lengthA, 0);
      if winsA > 0 then
      begin
        CopyRange(FTemp, cursorTemp, FWork, dest, winsA);
        dest := dest + winsA;
        cursorTemp := cursorTemp + winsA;
        lengthA := lengthA - winsA;
        if lengthA = 1 then goto CopyB;
        if lengthA = 0 then goto Succeed;
      end;
      FWork[dest] := FWork[cursorB];
      Inc(dest);
      Inc(cursorB);
      Dec(lengthB);
      if lengthB = 0 then goto Succeed;
      winsB := GallopLeft(FWork, FTemp[cursorTemp], cursorB, lengthB, 0);
      if winsB > 0 then
      begin
        CopyRange(FWork, cursorB, FWork, dest, winsB);
        dest := dest + winsB;
        cursorB := cursorB + winsB;
        lengthB := lengthB - winsB;
        if lengthB = 0 then goto Succeed;
      end;
      FWork[dest] := FTemp[cursorTemp];
      Inc(dest);
      Inc(cursorTemp);
      Dec(lengthA);
      if lengthA = 1 then goto CopyB;
    end;
    Inc(minGallop);
    FMinGallop := minGallop;
  end;
Succeed:
  if lengthA > 0 then CopyRange(FTemp, cursorTemp, FWork, dest, lengthA);
  goto Done;
CopyB:
  { the last element of run A belongs at the end of the merge }
  CopyRange(FWork, cursorB, FWork, dest, lengthB);
  FWork[dest + lengthB] := FTemp[cursorTemp];
Done:
end;

procedure TTyTimSort.MergeHigh(ABaseA, ALengthA, ABaseB, ALengthB: Integer);
label Succeed, CopyA, Done;
var
  lengthA, lengthB, dest, cursorTemp, cursorA, minGallop, winsA, winsB, k: Integer;
  first: Boolean;
begin
  lengthA := ALengthA;
  lengthB := ALengthB;
  if Length(FTemp) < lengthB then SetLength(FTemp, lengthB);
  CopyRange(FWork, ABaseB, FTemp, 0, lengthB);
  dest := ABaseB + lengthB - 1;
  cursorTemp := lengthB - 1;
  cursorA := ABaseA + lengthA - 1;
  FWork[dest] := FWork[cursorA];
  Dec(dest);
  Dec(cursorA);
  Dec(lengthA);
  if lengthA = 0 then goto Succeed;
  if lengthB = 1 then goto CopyA;
  minGallop := FMinGallop;
  while True do
  begin
    winsA := 0;
    winsB := 0;
    while True do
    begin
      if FCmp(FTemp[cursorTemp], FWork[cursorA]) < 0 then
      begin
        FWork[dest] := FWork[cursorA];
        Dec(dest);
        Dec(cursorA);
        Inc(winsA);
        Dec(lengthA);
        winsB := 0;
        if lengthA = 0 then goto Succeed;
        if winsA >= minGallop then Break;
      end
      else
      begin
        FWork[dest] := FTemp[cursorTemp];
        Dec(dest);
        Dec(cursorTemp);
        Inc(winsB);
        Dec(lengthB);
        winsA := 0;
        if lengthB = 1 then goto CopyA;
        if winsB >= minGallop then Break;
      end;
    end;
    Inc(minGallop);
    first := True;
    while (winsA >= cMinGallopWins) or (winsB >= cMinGallopWins) or first do
    begin
      first := False;
      minGallop := Max(1, minGallop - 1);
      FMinGallop := minGallop;
      k := GallopRight(FWork, FTemp[cursorTemp], ABaseA, lengthA, lengthA - 1);
      winsA := lengthA - k;
      if winsA > 0 then
      begin
        dest := dest - winsA;
        cursorA := cursorA - winsA;
        CopyRange(FWork, cursorA + 1, FWork, dest + 1, winsA);
        lengthA := lengthA - winsA;
        if lengthA = 0 then goto Succeed;
      end;
      FWork[dest] := FTemp[cursorTemp];
      Dec(dest);
      Dec(cursorTemp);
      Dec(lengthB);
      if lengthB = 1 then goto CopyA;
      k := GallopLeft(FTemp, FWork[cursorA], 0, lengthB, lengthB - 1);
      winsB := lengthB - k;
      if winsB > 0 then
      begin
        dest := dest - winsB;
        cursorTemp := cursorTemp - winsB;
        CopyRange(FTemp, cursorTemp + 1, FWork, dest + 1, winsB);
        lengthB := lengthB - winsB;
        if lengthB = 1 then goto CopyA;
        { impossible for a consistent comparator, and V8 does not assume one }
        if lengthB = 0 then goto Succeed;
      end;
      FWork[dest] := FWork[cursorA];
      Dec(dest);
      Dec(cursorA);
      Dec(lengthA);
      if lengthA = 0 then goto Succeed;
    end;
    Inc(minGallop);
    FMinGallop := minGallop;
  end;
Succeed:
  if lengthB > 0 then CopyRange(FTemp, 0, FWork, dest - (lengthB - 1), lengthB);
  goto Done;
CopyA:
  { the first element of run B belongs at the front of the merge }
  dest := dest - lengthA;
  cursorA := cursorA - lengthA;
  CopyRange(FWork, cursorA + 1, FWork, dest + 1, lengthA);
  FWork[dest] := FTemp[cursorTemp];
Done:
end;

procedure TTyTimSort.MergeAt(I: Integer);
var baseA, lengthA, baseB, lengthB, k: Integer;
begin
  baseA := FRunBase[I];
  lengthA := FRunLen[I];
  baseB := FRunBase[I + 1];
  lengthB := FRunLen[I + 1];
  FRunLen[I] := lengthA + lengthB;
  if I = FRuns - 3 then
  begin
    FRunBase[I + 1] := FRunBase[I + 2];
    FRunLen[I + 1] := FRunLen[I + 2];
  end;
  Dec(FRuns);
  k := GallopRight(FWork, FWork[baseB], baseA, lengthA, 0);
  baseA := baseA + k;
  lengthA := lengthA - k;
  if lengthA = 0 then Exit;
  lengthB := GallopLeft(FWork, FWork[baseA + lengthA - 1], baseB, lengthB, lengthB - 1);
  if lengthB = 0 then Exit;
  if lengthA <= lengthB then MergeLow(baseA, lengthA, baseB, lengthB)
  else MergeHigh(baseA, lengthA, baseB, lengthB);
end;

procedure TTyTimSort.MergeCollapse;
var n: Integer;

  function Established(AN: Integer): Boolean;
  begin
    if AN < 2 then Exit(True);
    Result := FRunLen[AN - 2] > FRunLen[AN - 1] + FRunLen[AN];
  end;

begin
  while FRuns > 1 do
  begin
    n := FRuns - 2;
    if not Established(n + 1) or not Established(n) then
    begin
      if FRunLen[n - 1] < FRunLen[n + 1] then Dec(n);
      MergeAt(n);
    end
    else if FRunLen[n] <= FRunLen[n + 1] then
      MergeAt(n)
    else
      Break;
  end;
end;

procedure TTyTimSort.MergeForceCollapse;
var n: Integer;
begin
  while FRuns > 1 do
  begin
    n := FRuns - 2;
    if (n > 0) and (FRunLen[n - 1] < FRunLen[n + 1]) then Dec(n);
    MergeAt(n);
  end;
end;

procedure TTyTimSort.PushRun(ABase, ALength: Integer);
begin
  if FRuns >= Length(FRunBase) then
  begin
    SetLength(FRunBase, FRuns + 16);
    SetLength(FRunLen, FRuns + 16);
  end;
  FRunBase[FRuns] := ABase;
  FRunLen[FRuns] := ALength;
  Inc(FRuns);
end;

procedure TTyTimSort.Sort(var AItems: TTyIntegerArray; ACompare: TTyJsCompare);
var remaining, low, minRun, runLen, forced: Integer;
begin
  FWork := AItems;
  FCmp := ACompare;
  FMinGallop := cMinGallopWins;
  FRuns := 0;
  remaining := Length(FWork);
  if remaining < 2 then Exit;
  low := 0;
  minRun := ComputeMinRunLength(remaining);
  while remaining <> 0 do
  begin
    runLen := CountAndMakeRun(low, low + remaining);
    if runLen < minRun then
    begin
      forced := Min(minRun, remaining);
      BinaryInsertionSort(low, low + runLen, low + forced);
      runLen := forced;
    end;
    PushRun(low, runLen);
    MergeCollapse;
    low := low + runLen;
    remaining := remaining - runLen;
  end;
  MergeForceCollapse;
  AItems := FWork;
end;

procedure TyJsArraySort(var AItems: TTyIntegerArray; ACompare: TTyJsCompare);
var s: TTyTimSort;
begin
  s := TTyTimSort.Create;
  try
    s.Sort(AItems, ACompare);
  finally
    s.Free;
  end;
end;

{ ==================== the external source ==================== }

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then Result := TJSONObject(AData)
  else Result := nil;
end;

{ An array index as a property key: '0', or digits not starting with '0' }
function IndexKey(const AKey: string; out AIndex: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  AIndex := -1;
  if (AKey = '') or (Length(AKey) > 9) then Exit;
  if (Length(AKey) > 1) and (AKey[1] = '0') then Exit;
  for i := 1 to Length(AKey) do
    if not (AKey[i] in ['0'..'9']) then Exit;
  AIndex := StrToInt(AKey);
  Result := True;
end;

constructor TTyExternalSource.Create(const AFields: TTySourceFields;
  ABuiltIn: Boolean);
var i: Integer;
begin
  inherited Create;
  FMade := TFPList.Create;
  FFields := AFields;
  FBuiltIn := ABuiltIn;
  if AFields.LayoutBy <> slbColumn then
    raise ETyTransformError.Create(rsTyDsUpstreamByRow);
  if AFields.DimsDefined then
  begin
    SetLength(FDims, Length(AFields.Dims));
    for i := 0 to High(FDims) do
    begin
      FDims[i].Index := i;
      FDims[i].HasName := AFields.Dims[i].HasName;
      FDims[i].Name := AFields.Dims[i].Name;
      FDims[i].HasDisplayName := AFields.Dims[i].HasDisplayName;
      FDims[i].DisplayName := AFields.Dims[i].DisplayName;
      { a name used twice is refused, not renamed }
      if FDims[i].HasName and (NameIndex(FDims[i].Name) < i) then
        raise ETyTransformError.CreateFmt(rsTyDsDuplicateDim, [FDims[i].Name]);
    end;
  end
  else
  begin
    SetLength(FDims, Max(0, AFields.DetectedCount));
    for i := 0 to High(FDims) do
    begin
      FDims[i] := Default(TTyTransformDim);
      FDims[i].Index := i;
    end;
  end;
  if not (AFields.Format in [tsfArrayRows, tsfObjectRows, tsfKeyedColumns]) then
    raise ETyTransformError.Create(rsTyDsUpstreamFormat);
end;

destructor TTyExternalSource.Destroy;
var i: Integer;
begin
  if FMade <> nil then
    for i := 0 to FMade.Count - 1 do TObject(FMade[i]).Free;
  FMade.Free;
  inherited Destroy;
end;

function TTyExternalSource.NameIndex(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(FDims) do
    if FDims[i].HasName and (FDims[i].Name = AName) then Exit(i);
  Result := -1;
end;

function TTyExternalSource.SourceFormat: TTySourceFormat;
begin
  Result := FFields.Format;
end;

function TTyExternalSource.BuiltIn: Boolean;
begin
  Result := FBuiltIn;
end;

function TTyExternalSource.Count: Integer;
var col: TJSONData;
begin
  Result := 0;
  case FFields.Format of
    tsfArrayRows: Result := Max(0, TJSONArray(FFields.Data).Count - FFields.StartIndex);
    tsfObjectRows: Result := TJSONArray(FFields.Data).Count;
    tsfKeyedColumns:
      begin
        { the first dimension's column -- with no dimension at all upstream
          reads a property of undefined }
        if Length(FDims) = 0 then
          raise ETyTransformError.Create(rsTyDsKeyedNoDims);
        if not FDims[0].HasName then Exit;
        col := TJSONObject(FFields.Data).Find(FDims[0].Name);
        if col is TJSONArray then Result := TJSONArray(col).Count;
      end;
  end;
end;

function TTyExternalSource.ItemAt(AIndex: Integer): TJSONData;
var
  arr, made: TJSONArray;
  col: TJSONData;
  i, k: Integer;
begin
  Result := nil;
  case FFields.Format of
    tsfArrayRows:
      begin
        arr := TJSONArray(FFields.Data);
        k := AIndex + FFields.StartIndex;
        if (k >= 0) and (k < arr.Count) then Result := arr.Items[k];
      end;
    tsfObjectRows:
      begin
        arr := TJSONArray(FFields.Data);
        if (AIndex >= 0) and (AIndex < arr.Count) then Result := arr.Items[AIndex];
      end;
    tsfKeyedColumns:
      begin
        { a row made of the i-th cell of every dimension's column }
        made := TJSONArray.Create;
        FMade.Add(made);
        for i := 0 to High(FDims) do
        begin
          col := nil;
          if FDims[i].HasName then col := TJSONObject(FFields.Data).Find(FDims[i].Name);
          if (col is TJSONArray) and (AIndex >= 0) and (AIndex < TJSONArray(col).Count) then
            made.Add(TJSONArray(col).Items[AIndex].Clone)
          else
            made.Add(TJSONNull.Create);
        end;
        Result := made;
      end;
  end;
end;

function TTyExternalSource.RawItem(AIndex: Integer): TJSONData;
begin
  if not FBuiltIn then
    raise ETyTransformError.CreateFmt(rsTyDsNotSupported, ['getRawDataItem']);
  Result := ItemAt(AIndex);
end;

function TTyExternalSource.RawData: TJSONData;
begin
  if not FBuiltIn then
    raise ETyTransformError.CreateFmt(rsTyDsNotSupported, ['getRawData']);
  if not (FFields.Format in [tsfArrayRows, tsfObjectRows]) then
    raise ETyTransformError.Create(rsTyDsUpstreamFormat);
  Result := FFields.Data;
end;

function TTyExternalSource.CloneRawData: TJSONArray;
var
  arr: TJSONArray;
  i: Integer;
  item: TJSONData;
begin
  if not (FFields.Format in [tsfArrayRows, tsfObjectRows]) then
    raise ETyTransformError.Create(rsTyDsUpstreamFormat);
  arr := TJSONArray(FFields.Data);
  Result := TJSONArray.Create;
  try
    for i := 0 to arr.Count - 1 do
    begin
      item := arr.Items[i];
      if FFields.Format = tsfArrayRows then
      begin
        { `data[i].slice()` -- a row that is not a list has no slice }
        if not (item is TJSONArray) then
          raise ETyTransformError.Create(rsTyDsRowNotList);
        Result.Add(item.Clone);
      end
      else if item is TJSONObject then
        Result.Add(item.Clone)
      else
        Result.Add(TJSONObject.Create);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TTyExternalSource.ValueOfItem(AItem: TJSONData; ADim: Integer): TJSONData;
var
  key: string;
  k: Integer;
begin
  Result := nil;
  if (AItem = nil) or (AItem.JSONType = jtNull) then Exit;
  if (ADim < 0) or (ADim > High(FDims)) then Exit;
  if FFields.Format = tsfObjectRows then
  begin
    { `dataItem[dimName]` -- an unnamed dimension looks up 'undefined' }
    if FDims[ADim].HasName then key := FDims[ADim].Name else key := 'undefined';
    if AItem is TJSONObject then Result := TJSONObject(AItem).Find(key)
    else if (AItem is TJSONArray) and IndexKey(key, k) and (k < TJSONArray(AItem).Count) then
      Result := TJSONArray(AItem).Items[k];
    Exit;
  end;
  { `dataItem[dimIndex]` }
  if AItem is TJSONArray then
  begin
    if ADim < TJSONArray(AItem).Count then Result := TJSONArray(AItem).Items[ADim];
  end
  else if AItem is TJSONObject then
    Result := TJSONObject(AItem).Find(IntToStr(ADim));
end;

function TTyExternalSource.RetrieveValue(AIndex, ADim: Integer): TJSONData;
begin
  Result := ValueOfItem(ItemAt(AIndex), ADim);
end;

function TTyExternalSource.DimensionOf(ADim: TJSONData): Integer;
var
  text: string;
  named, k: Integer;
  numeric: Boolean;
begin
  Result := -1;
  if (ADim = nil) or (ADim.JSONType = jtNull) then Exit;
  if ADim.JSONType = jtNumber then
  begin
    { `dimensions[dim]`: the number as a property key }
    if IsNan(ADim.AsFloat) then Exit;
    text := TyJsNumberToString(ADim.AsFloat);
    if IndexKey(text, k) and (k <= High(FDims)) then Result := k;
    Exit;
  end;
  text := TyJsTextOf(ADim);
  named := NameIndex(text);
  { `!isNaN(dim) && !hasOwn(dimsByName, dim)`: a value that reads as a
    number and names nothing is an index, as a key }
  numeric := not IsNan(JsNumber(TyJsValueOf(ADim)));
  if numeric and (named < 0) then
  begin
    if IndexKey(text, k) and (k <= High(FDims)) then Result := k;
  end
  else if named >= 0 then
    Result := FDims[named].Index;
end;

function TTyExternalSource.DimCount: Integer;
begin
  Result := Length(FDims);
end;

function TTyExternalSource.Dim(AIndex: Integer): TTyTransformDim;
begin
  Result := FDims[AIndex];
end;

{ ==================== the registry ==================== }

type
  TTyTransformEntry = record
    Key: string;
    Func: TTyDataTransformFunc;
    BuiltIn: Boolean;
  end;

var
  GTransforms: array of TTyTransformEntry;

function TyRegisterDataTransform(const AType: string;
  AFunc: TTyDataTransformFunc): Boolean;
var
  p, i: Integer;
  key: string;
  builtIn: Boolean;
begin
  Result := False;
  if (AType = '') or (AFunc = nil) then Exit;
  { `type.split(':')` must give exactly two parts }
  p := Pos(':', AType);
  if (p = 0) or (Pos(':', Copy(AType, p + 1, MaxInt)) > 0) then Exit;
  builtIn := Copy(AType, 1, p - 1) = 'echarts';
  if builtIn then key := Copy(AType, p + 1, MaxInt) else key := AType;
  for i := 0 to High(GTransforms) do
    if GTransforms[i].Key = key then
    begin
      GTransforms[i].Func := AFunc;
      GTransforms[i].BuiltIn := builtIn;
      Exit(True);
    end;
  SetLength(GTransforms, Length(GTransforms) + 1);
  GTransforms[High(GTransforms)].Key := key;
  GTransforms[High(GTransforms)].Func := AFunc;
  GTransforms[High(GTransforms)].BuiltIn := builtIn;
  Result := True;
end;

function TyFindDataTransform(const AType: string;
  out AFunc: TTyDataTransformFunc; out ABuiltIn: Boolean): Boolean;
var i: Integer;
begin
  AFunc := nil;
  ABuiltIn := False;
  for i := 0 to High(GTransforms) do
    if GTransforms[i].Key = AType then
    begin
      AFunc := GTransforms[i].Func;
      ABuiltIn := GTransforms[i].BuiltIn;
      Exit(True);
    end;
  Result := False;
end;

procedure TyAddTransformResult(var AResults: TTyTransformResultArray;
  AData: TJSONData; ADimensions: TJSONData);
var n: Integer;
begin
  n := Length(AResults);
  SetLength(AResults, n + 1);
  AResults[n].Data := AData;
  AResults[n].Dimensions := ADimensions;
end;

{ applySingleDataTransform }
function ApplySingle(AOpt: TJSONData; const AUps: TTySourceRefArray;
  AOwner: TFPList; ARandom: PLongWord; out AOut: TTySourceRefArray;
  out AError: string): Boolean;
var
  func: TTyDataTransformFunc;
  builtIn: Boolean;
  ext: TTyExternalSourceArray;
  params: TTyTransformParams;
  res: TTyTransformResultArray;
  i, k: Integer;
  tp, upDims: TJSONData;
  node: TJSONObject;
  data, upArr: TJSONArray;
  fields: TTySourceFields;
begin
  Result := False;
  AOut := nil;
  AError := '';
  res := nil;
  ext := nil;
  if Length(AUps) = 0 then
  begin
    AError := rsTyDsUpstreamMissing;
    Exit;
  end;
  { isObject: an object or a list }
  if (AOpt = nil) or not (AOpt.JSONType in [jtObject, jtArray]) then
  begin
    AError := rsTyDsNotObject;
    Exit;
  end;
  tp := nil;
  if AOpt is TJSONObject then tp := TJSONObject(AOpt).Find('type');
  if (tp = nil) or (tp.JSONType <> jtString)
    or not TyFindDataTransform(tp.AsString, func, builtIn) then
  begin
    AError := Format(rsTyDsUnknownType, [TyJsTextOf(tp)]);
    Exit;
  end;
  try
    try
      SetLength(ext, Length(AUps));
      for i := 0 to High(AUps) do
      begin
        if AUps[i].Node = nil then
          raise ETyTransformError.Create(rsTyDsUpstreamMissing);
        ext[i] := TTyExternalSource.Create(TySourceFieldsOf(AUps[i].Node), builtIn);
      end;
      params.Upstream := ext[0];
      params.Upstreams := ext;
      params.Config := nil;
      if AOpt is TJSONObject then params.Config := TJSONObject(AOpt).Find('config');
      params.Random := ARandom;
      func(params, res);
      SetLength(AOut, Length(res));
      for k := 0 to High(res) do
      begin
        if not TyDatasetTruthy(res[k].Data)
          or not (TyDetectSourceFormat(res[k].Data) in [tsfArrayRows, tsfObjectRows]) then
          raise ETyTransformError.Create(rsTyDsBadResult);
        node := TJSONObject.Create;
        AOwner.Add(node);
        data := TJSONArray(res[k].Data);
        res[k].Data := nil;
        node.Add('source', data);
        { THE FIRST RESULT WITHOUT DIMENSIONS INHERITS: the upstream's header
          lines go in front of it and its raw dimensions come along -- a
          copy has none, and upstream reads them off undefined }
        if (k = 0) and not TyDatasetTruthy(res[k].Dimensions) then
        begin
          if AUps[0].IsClone then
            raise ETyTransformError.Create(rsTyDsCopyHasNoMeta);
          fields := TySourceFieldsOf(AUps[0].Node);
          if (fields.StartIndex > 0) and (fields.Data is TJSONArray) then
          begin
            upArr := TJSONArray(fields.Data);
            for i := Min(fields.StartIndex, upArr.Count) - 1 downto 0 do
              data.Insert(0, upArr.Items[i].Clone);
          end;
          node.Add('sourceHeader', fields.StartIndex);
          upDims := AUps[0].Node.Find('dimensions');
          if (upDims <> nil) and (upDims.JSONType <> jtNull) then
            node.Add('dimensions', upDims.Clone);
        end
        else
        begin
          node.Add('sourceHeader', 0);
          if res[k].Dimensions <> nil then
          begin
            node.Add('dimensions', res[k].Dimensions);
            res[k].Dimensions := nil;
          end;
        end;
        node.Add('seriesLayoutBy', 'column');
        AOut[k].Node := node;
        AOut[k].IsClone := False;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        AError := E.Message;
        AOut := nil;
      end;
    end;
  finally
    for i := 0 to High(ext) do ext[i].Free;
    for k := 0 to High(res) do
    begin
      res[k].Data.Free;
      res[k].Dimensions.Free;
    end;
  end;
end;

function TyApplyDataTransform(ATransform: TJSONData;
  const AUps: TTySourceRefArray; AOwner: TFPList;
  out AResults: TTySourceRefArray; out AError: string;
  ARandom: PLongWord): Boolean;
var
  steps: array of TJSONData;
  ups, outs: TTySourceRefArray;
  i: Integer;
  mask: TFPUExceptionMask;
  ownRandom: LongWord;
begin
  ownRandom := TyJitterSeed;
  if ARandom = nil then ARandom := @ownRandom;
  Result := False;
  AResults := nil;
  AError := '';
  { normalizeToArray }
  steps := nil;
  if ATransform is TJSONArray then
  begin
    SetLength(steps, TJSONArray(ATransform).Count);
    for i := 0 to High(steps) do steps[i] := TJSONArray(ATransform).Items[i];
  end
  else if (ATransform <> nil) and (ATransform.JSONType <> jtNull) then
  begin
    SetLength(steps, 1);
    steps[0] := ATransform;
  end;
  if Length(steps) = 0 then
  begin
    AError := rsTyDsEmptyPipe;
    Exit;
  end;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exUnderflow, exPrecision, exZeroDivide]);
  try
    ups := AUps;
    for i := 0 to High(steps) do
    begin
      if not ApplySingle(steps[i], ups, AOwner, ARandom, outs, AError) then Exit;
      { a step before the last hands on one result at least -- a missing
        one is undefined, which the next step cannot read }
      if (i < High(steps)) and (Length(outs) = 0) then SetLength(outs, 1);
      ups := outs;
    end;
    AResults := ups;
    Result := True;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== filter ==================== }

type
  TTyCondKind = (ckConst, ckAnd, ckOr, ckNot, ckRel);
  TTyRelOp = (roLt, roLte, roGt, roGte, roEq, roNe);
  TTyRelCmp = record
    Op: TTyRelOp;
    RVal: TTyJsValue;
    RFloat: Double;
  end;

  TTyCond = class
  public
    Kind: TTyCondKind;
    Value: Boolean;
    Kids: array of TTyCond;
    Dim: Integer;
    Parser: TTyRawParser;
    Cmps: array of TTyRelCmp;
    destructor Destroy; override;
    function Eval(ASrc: TTyExternalSource; AItem: TJSONData): Boolean;
  end;

destructor TTyCond.Destroy;
var i: Integer;
begin
  for i := 0 to High(Kids) do Kids[i].Free;
  inherited Destroy;
end;

function JsTypeOf(const V: TTyJsValue): Integer;
begin
  case V.Kind of
    jkUndefined: Result := 0;
    jkBool: Result := 1;
    jkNumber: Result := 2;
    jkString: Result := 3;
  else
    Result := 4;   // 'object': null, a list, an object
  end;
end;

{ `===`: the same kind and the same value; a list or an object is only
  itself, and no cell is the condition's own }
function JsStrictEq(const L, R: TTyJsValue): Boolean;
begin
  Result := False;
  if L.Kind <> R.Kind then Exit;
  case L.Kind of
    jkUndefined, jkNull: Result := True;
    jkBool: Result := L.Bool = R.Bool;
    jkNumber: Result := (not IsNan(L.Num)) and (not IsNan(R.Num)) and (L.Num = R.Num);
    jkString: Result := L.Str = R.Str;
  else
    Result := L.Data = R.Data;
  end;
end;

function SameNum(A, B: Double): Boolean;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A = B);
end;

function CmpEval(const C: TTyRelCmp; const V: TTyJsValue): Boolean;
var l: Double; eq: Boolean;
begin
  case C.Op of
    roEq, roNe:
      begin
        { FilterEqualityComparator: `===`, and failing that, when the types
          differ and one is a number, the numbers numericToNumber reads }
        eq := JsStrictEq(V, C.RVal);
        if (not eq) and (JsTypeOf(V) <> JsTypeOf(C.RVal))
          and ((V.Kind = jkNumber) or (C.RVal.Kind = jkNumber)) then
          eq := SameNum(TyJsNumericOf(V), C.RFloat);
        Result := eq = (C.Op = roEq);
      end;
  else
    { FilterOrderComparator: a number as it is, anything else through
      numericToNumber; not-a-number on either side is false }
    if V.Kind = jkNumber then l := V.Num else l := TyJsNumericOf(V);
    if IsNan(l) or IsNan(C.RFloat) then Exit(False);
    case C.Op of
      roLt: Result := l < C.RFloat;
      roLte: Result := l <= C.RFloat;
      roGt: Result := l > C.RFloat;
    else
      Result := l >= C.RFloat;
    end;
  end;
end;

function TTyCond.Eval(ASrc: TTyExternalSource; AItem: TJSONData): Boolean;
var
  i: Integer;
  v: TTyJsValue;
begin
  case Kind of
    ckConst: Result := Value;
    ckAnd:
      begin
        for i := 0 to High(Kids) do
          if not Kids[i].Eval(ASrc, AItem) then Exit(False);
        Result := True;
      end;
    ckOr:
      begin
        for i := 0 to High(Kids) do
          if Kids[i].Eval(ASrc, AItem) then Exit(True);
        Result := False;
      end;
    ckNot: Result := not Kids[0].Eval(ASrc, AItem);
  else
    v := TyJsValueOf(ASrc.ValueOfItem(AItem, Dim));
    if Parser <> rpNone then v := TyApplyRawParser(Parser, v);
    for i := 0 to High(Cmps) do
      if not CmpEval(Cmps[i], v) then Exit(False);
    Result := True;
  end;
end;

{ isObject(val) && !isArrayLike(val): an object with no numeric `length` }
function IsObjectNotArray(AData: TJSONData): Boolean;
var len: TJSONData;
begin
  Result := False;
  if not (AData is TJSONObject) then Exit;
  len := TJSONObject(AData).Find('length');
  Result := not ((len <> nil) and (len.JSONType = jtNumber));
end;

function ParseCond(AOpt: TJSONData; ASrc: TTyExternalSource): TTyCond; forward;

function ParseAndOr(AObj: TJSONObject; const AOp: string;
  ASrc: TTyExternalSource): TTyCond;
var
  sub: TJSONData;
  i: Integer;
begin
  sub := AObj.Find(AOp);
  if not (sub is TJSONArray) or (TJSONArray(sub).Count = 0) then
    raise ETyTransformError.CreateFmt(rsTyDsCondAndOr, [AOp]);
  Result := TTyCond.Create;
  try
    if AOp = 'and' then Result.Kind := ckAnd else Result.Kind := ckOr;
    SetLength(Result.Kids, TJSONArray(sub).Count);
    for i := 0 to TJSONArray(sub).Count - 1 do
      Result.Kids[i] := ParseCond(TJSONArray(sub).Items[i], ASrc);
  except
    Result.Free;
    raise;
  end;
end;

function ParseRelational(AObj: TJSONObject; ASrc: TTyExternalSource): TTyCond;
var
  i, n: Integer;
  key, op: string;
  pd: TJSONData;
  cmp: TTyRelCmp;
begin
  { prepareGetValue first: the dimension, then the operators }
  if AObj.IndexOfName('dimension') < 0 then
    raise ETyTransformError.Create(rsTyDsCondNoDimension);
  Result := TTyCond.Create;
  try
    Result.Kind := ckRel;
    Result.Dim := ASrc.DimensionOf(AObj.Find('dimension'));
    if Result.Dim < 0 then
      raise ETyTransformError.CreateFmt(rsTyDsNoDimension, [TyJsTextOf(AObj.Find('dimension'))]);
    { an unknown parser name parses nothing }
    Result.Parser := rpNone;
    pd := AObj.Find('parser');
    if TyDatasetTruthy(pd) and (pd.JSONType = jtString) then
      TyRawParserByName(pd.AsString, Result.Parser);
    for i := 0 to AObj.Count - 1 do
    begin
      key := AObj.Names[i];
      if (key = 'parser') or (key = 'dimension') then Continue;
      if key = 'value' then op := 'eq'
      else if key = '<' then op := 'lt'
      else if key = '<=' then op := 'lte'
      else if key = '>' then op := 'gt'
      else if key = '>=' then op := 'gte'
      else if key = '=' then op := 'eq'
      else if (key = '!=') or (key = '<>') then op := 'ne'
      else op := key;
      cmp := Default(TTyRelCmp);
      cmp.RVal := TyJsValueOf(AObj.Items[i]);
      if Result.Parser <> rpNone then cmp.RVal := TyApplyRawParser(Result.Parser, cmp.RVal);
      if (op = 'eq') or (op = 'ne') then
      begin
        if op = 'eq' then cmp.Op := roEq else cmp.Op := roNe;
      end
      else if (op = 'lt') or (op = 'lte') or (op = 'gt') or (op = 'gte') then
      begin
        if op = 'lt' then cmp.Op := roLt
        else if op = 'lte' then cmp.Op := roLte
        else if op = 'gt' then cmp.Op := roGt
        else cmp.Op := roGte;
        if cmp.RVal.Kind <> jkNumber then
          raise ETyTransformError.CreateFmt(rsTyDsCondNeedsNumber, [key]);
      end
      else if op = 'reg' then
        raise ETyTransformError.Create(rsTyDsCondReg)
      else
        raise ETyTransformError.CreateFmt(rsTyDsCondBadOperator, [key]);
      cmp.RFloat := TyJsNumericOf(cmp.RVal);
      n := Length(Result.Cmps);
      SetLength(Result.Cmps, n + 1);
      Result.Cmps[n] := cmp;
    end;
    if Length(Result.Cmps) = 0 then
      raise ETyTransformError.Create(rsTyDsCondNoOperator);
  except
    Result.Free;
    raise;
  end;
end;

function ParseCond(AOpt: TJSONData; ASrc: TTyExternalSource): TTyCond;
var obj: TJSONObject;
begin
  if (AOpt <> nil) and (AOpt.JSONType = jtBoolean) then
  begin
    Result := TTyCond.Create;
    Result.Kind := ckConst;
    Result.Value := AOpt.AsBoolean;
    Exit;
  end;
  if not IsObjectNotArray(AOpt) then
    raise ETyTransformError.Create(rsTyDsCondNotObject);
  obj := TJSONObject(AOpt);
  if TyDatasetTruthy(obj.Find('and')) then Exit(ParseAndOr(obj, 'and', ASrc));
  if TyDatasetTruthy(obj.Find('or')) then Exit(ParseAndOr(obj, 'or', ASrc));
  if TyDatasetTruthy(obj.Find('not')) then
  begin
    if not IsObjectNotArray(obj.Find('not')) then
      raise ETyTransformError.Create(rsTyDsCondNot);
    Result := TTyCond.Create;
    try
      Result.Kind := ckNot;
      SetLength(Result.Kids, 1);
      Result.Kids[0] := ParseCond(obj.Find('not'), ASrc);
    except
      Result.Free;
      raise;
    end;
    Exit;
  end;
  Result := ParseRelational(obj, ASrc);
end;

{ filterTransform: the rows the condition keeps, in order, header lines
  inherited }
procedure FilterTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var
  cond: TTyCond;
  outRows: TJSONArray;
  i: Integer;
  item: TJSONData;
  up: TTyExternalSource;
begin
  up := AParams.Upstream;
  cond := ParseCond(AParams.Config, up);
  try
    outRows := TJSONArray.Create;
    try
      for i := 0 to up.Count - 1 do
      begin
        item := up.RawItem(i);
        if cond.Eval(up, item) then
        begin
          if item = nil then outRows.Add(TJSONNull.Create)
          else outRows.Add(item.Clone);
        end;
      end;
    except
      outRows.Free;
      raise;
    end;
    TyAddTransformResult(AResults, outRows);
  finally
    cond.Free;
  end;
end;

{ ==================== sort ==================== }

type
  TTySortKey = record
    Dim: Integer;
    Parser: TTyRawParser;
    ResultLT: Integer;
    Incomparable: Double;
  end;

  TTySortCtx = class
  public
    Keys: array of TTySortKey;
    { per key, per row: the parsed value }
    Vals: array of array of TTyJsValue;
    function Compare(A, B: Integer): Integer;
  end;

function TTySortCtx.Compare(A, B: Integer): Integer;
var k: Integer;
begin
  for k := 0 to High(Keys) do
  begin
    Result := TySortOrderCompare(Vals[k][A], Vals[k][B], Keys[k].ResultLT,
      Keys[k].Incomparable);
    if Result <> 0 then Exit;
  end;
  Result := 0;
end;

procedure SortTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var
  up: TTyExternalSource;
  exprs: array of TJSONData;
  i, k, n: Integer;
  o: TJSONObject;
  d, order, inc, pd: TJSONData;
  key: TTySortKey;
  ctx: TTySortCtx;
  rows: array of TJSONData;
  idx: TTyIntegerArray;
  outRows: TJSONArray;
  isDesc: Boolean;
begin
  up := AParams.Upstream;
  { normalizeToArray(config) }
  exprs := nil;
  d := AParams.Config;
  if d is TJSONArray then
  begin
    SetLength(exprs, TJSONArray(d).Count);
    for i := 0 to High(exprs) do exprs[i] := TJSONArray(d).Items[i];
  end
  else if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    SetLength(exprs, 1);
    exprs[0] := d;
  end;
  if Length(exprs) = 0 then
    raise ETyTransformError.Create(rsTyDsSortEmpty);
  ctx := TTySortCtx.Create;
  try
    for i := 0 to High(exprs) do
    begin
      o := ObjOf(exprs[i]);
      d := nil;
      if o <> nil then d := o.Find('dimension');
      if (d = nil) or (d.JSONType = jtNull) then
        raise ETyTransformError.Create(rsTyDsSortNoDimension);
      order := o.Find('order');
      if (order = nil) or (order.JSONType <> jtString)
        or ((order.AsString <> 'asc') and (order.AsString <> 'desc')) then
        raise ETyTransformError.Create(rsTyDsSortOrder);
      inc := o.Find('incomparable');
      if TyDatasetTruthy(inc) and not ((inc.JSONType = jtString)
        and ((inc.AsString = 'min') or (inc.AsString = 'max'))) then
        raise ETyTransformError.Create(rsTyDsSortIncomparable);
      key := Default(TTySortKey);
      key.Dim := up.DimensionOf(d);
      if key.Dim < 0 then
        raise ETyTransformError.CreateFmt(rsTyDsNoDimension, [TyJsTextOf(d)]);
      key.Parser := rpNone;
      pd := o.Find('parser');
      if TyDatasetTruthy(pd) then
        if (pd.JSONType <> jtString) or not TyRawParserByName(pd.AsString, key.Parser) then
          raise ETyTransformError.CreateFmt(rsTyDsSortParser, [TyJsTextOf(pd)]);
      { SortOrderComparator: incomparable defaults to the tail -- max for asc,
        min for desc -- only when it is null; any other value but 'min' is
        max }
      isDesc := order.AsString = 'desc';
      if isDesc then key.ResultLT := 1 else key.ResultLT := -1;
      if (inc = nil) or (inc.JSONType = jtNull) then
      begin
        if isDesc then key.Incomparable := NegInfinity else key.Incomparable := Infinity;
      end
      else if (inc.JSONType = jtString) and (inc.AsString = 'min') then
        key.Incomparable := NegInfinity
      else
        key.Incomparable := Infinity;
      n := Length(ctx.Keys);
      SetLength(ctx.Keys, n + 1);
      ctx.Keys[n] := key;
    end;
    if not (up.SourceFormat in [tsfArrayRows, tsfObjectRows]) then
      raise ETyTransformError.Create(rsTyDsSortFormat);
    n := up.Count;
    SetLength(rows, n);
    SetLength(idx, n);
    for i := 0 to n - 1 do
    begin
      rows[i] := up.RawItem(i);
      idx[i] := i;
    end;
    { the parsers are pure: parse every cell once }
    SetLength(ctx.Vals, Length(ctx.Keys));
    for k := 0 to High(ctx.Keys) do
    begin
      SetLength(ctx.Vals[k], n);
      for i := 0 to n - 1 do
      begin
        ctx.Vals[k][i] := TyJsValueOf(up.ValueOfItem(rows[i], ctx.Keys[k].Dim));
        if ctx.Keys[k].Parser <> rpNone then
          ctx.Vals[k][i] := TyApplyRawParser(ctx.Keys[k].Parser, ctx.Vals[k][i]);
      end;
    end;
    TyJsArraySort(idx, @ctx.Compare);
    outRows := TJSONArray.Create;
    try
      for i := 0 to n - 1 do
        if rows[idx[i]] = nil then outRows.Add(TJSONNull.Create)
        else outRows.Add(rows[idx[i]].Clone);
    except
      outRows.Free;
      raise;
    end;
    TyAddTransformResult(AResults, outRows);
  finally
    ctx.Free;
  end;
end;

{ ==================== boxplot ==================== }

{ boxplotTransform: a table of arrays, read whole (header lines too) by
  prepareBoxplotData; the boxes named, the outliers not }
procedure BoxplotTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var
  raw: TJSONData;
  boxes, outliers: TJSONArray;
begin
  if AParams.Upstream.SourceFormat <> tsfArrayRows then
    raise ETyTransformError.Create(rsTyDsBoxplotRows);
  raw := AParams.Upstream.RawData;
  if not TyPrepareBoxplotData(TJSONArray(raw), ObjOf(AParams.Config), boxes, outliers) then
    raise ETyTransformError.Create(rsTyDsRowNotList);
  TyAddTransformResult(AResults, boxes,
    TJSONArray.Create(['ItemName', 'Low', 'Q1', 'Q2', 'Q3', 'High']));
  TyAddTransformResult(AResults, outliers);
end;

initialization
  TyRegisterDataTransform('echarts:filter', @FilterTransform);
  TyRegisterDataTransform('echarts:sort', @SortTransform);
  TyRegisterDataTransform('echarts:boxplot', @BoxplotTransform);
end.
