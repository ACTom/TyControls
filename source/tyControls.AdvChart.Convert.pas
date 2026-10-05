unit tyControls.AdvChart.Convert;
{$mode objfpc}{$H+}
{ The public coordinate conversions' ground floor -- upstream's
  util/model.ts parseFinder and the JavaScript value rules the conversions
  read their input with. [Batch 110, C2]

  THE FINDER. A string `s` is an object whose one key `sIndex` is 0. An object's keys are read as
  `<mainType>(Index|Id|Name)` (the longest main type that leaves one of the
  three); `dataIndex` and `dataIndexInside` are kept aside and no
  conversion reads them. Each main type is then queried as
  queryReferringComponents with nothing assumed: no index, id or name
  given (or all three null) finds nothing; `'none'` and `false` find
  nothing; `'all'` finds every model there is. An index is a JavaScript
  property key into the model list -- so `'1'` and `[[1]]` are index 1 but
  `'01'`, `1.5` and `-1` are nothing -- and a list of them keeps its order
  (and its duplicates). An id or a name: a string is itself, a number its
  printed form, anything else nothing; IN A LIST only strings count,
  because upstream keys a native Map with the items as written and a model's
  id is always a string.

  THE VALUES. The conversions take whatever JSON the host wrote and read it
  as upstream's code reads a JavaScript value:
    - an element `v[i]`: an array's item, a string's character, an
      object's property "i", nothing on a number or a boolean -- and an
      error on null (upstream throws a TypeError there);
    - ToNumber: null 0, a boolean 0 or 1, a string as Number() reads it,
      an array as its comma-joined text, an object not a number;
    - scale.parse: on a value or log axis null and '' are not numbers and
      anything else is ToNumber; on a category axis a string is its
      category (or nothing) and anything else Math.round(ToNumber); on a
      time axis a number is Math.round, a string goes through the date
      parser (local time unless it names a zone), null is no time, and
      anything else is ToNumber rounded and clipped to the Date range.

  THE CARTESIAN (Cartesian2D.dataToPoint / pointToData): the affine matrix
  when the cartesian has one and both elements are non-null with a finite
  ToNumber -- the matrix takes them as ToNumber gives them, unparsed, so a
  time in milliseconds is not rounded there and '' is nought -- and the
  per-axis path with scale.parse otherwise. Back the other way the inverse
  matrix, or each axis' coordToData, over ToNumber of the two elements.
  One axis alone: toGlobalCoord(dataToCoord(parse(v))) and
  coordToData(toLocalCoord(ToNumber(v))).

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
  tyControls.AdvChart.OptionMerge;

type
  { WHAT A CONVERSION ANSWERED: nothing (upstream's undefined -- no
    coordinate system took the finder), one number (a single axis, a
    calendar's time), a point; or the error upstream raises when it indexes
    a null value. }
  TTyConvertKind = (cvkNone, cvkNumber, cvkArray, cvkError);
  TTyConvertResult = record
    Kind: TTyConvertKind;
    Values: TTyDoubleArray;
  end;

  { One main type the finder named, and the models it found, in order. }
  TTyFinderModels = record
    MainType: string;
    Models: TTyIntegerArray;
  end;

  TTyParsedFinder = record
    Types: array of TTyFinderModels;
    { kept aside, as upstream keeps them; nil where not written }
    HasDataIndex, HasDataIndexInside: Boolean;
  end;

  { Raised where upstream's code would index a null value. }
  ETyConvertNull = class(Exception);

{ ---- the finder ---- }

function TyParseFinder(AFinder: TJSONData; const AKeys: TTyOptionKeys): TTyParsedFinder;
{ the models found for AMainType, nil when the finder did not name it }
function TyFinderModels(const AFinder: TTyParsedFinder; const AMainType: string): TTyIntegerArray;
{ upstream's `<mainType>Model`: the first of them, or -1 }
function TyFinderModel(const AFinder: TTyParsedFinder; const AMainType: string): Integer;

{ ---- JavaScript values ---- }

{ String(v); nil is undefined }
function TyJsonJsString(AData: TJSONData): string;
{ Number(v); nil is undefined, which is not a number }
function TyJsonToNumber(AData: TJSONData): Double;
function TyJsonNullish(AData: TJSONData): Boolean;
{ v[i] -- nil for undefined. AOwned holds a value made for the answer (a
  string's character) and is the caller's to free. Raises ETyConvertNull
  on a null or undefined v. }
function TyJsonElement(AData: TJSONData; AIndex: Integer; out AOwned: TJSONData): TJSONData;
{ JavaScript's isArray }
function TyJsonIsArray(AData: TJSONData): Boolean;
{ AAxis' scale.parse of a JSON value }
function TyAxisParseJson(AAxis: TTyAxis; AData: TJSONData): Double;

{ ---- the conversions on a cartesian and on one of its axes ---- }

function TyConvertNone: TTyConvertResult;
function TyConvertNum(AValue: Double): TTyConvertResult;
function TyConvertXY(AX, AY: Double): TTyConvertResult;

function TyCartesianToPixel(ACart: TTyCartesian2D; AValue: TJSONData): TTyConvertResult;
function TyCartesianFromPixel(ACart: TTyCartesian2D; AValue: TJSONData): TTyConvertResult;
function TyAxisToPixel(AAxis: TTyAxis; AValue: TJSONData): TTyConvertResult;
function TyAxisFromPixel(AAxis: TTyAxis; AValue: TJSONData): TTyConvertResult;
{ Cartesian2D.containPoint over ToNumber of the two elements: each axis
  takes its coordinate into its own frame and asks whether it falls
  between the ends, both included. }
function TyCartesianContainJson(ACart: TTyCartesian2D; APoint: TJSONData): Boolean;
{ the two elements of a pixel as ToNumber reads them }
function TyJsonPoint(APoint: TJSONData): TTyPointF;

implementation

{ ==================== JavaScript values ==================== }

function TyJsonNullish(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function TyJsonIsArray(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType = jtArray);
end;

{ Array.prototype.join(','): null and undefined print as nothing }
function JoinText(AArr: TJSONArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to AArr.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    if AArr.Items[i].JSONType <> jtNull then
      Result := Result + TyJsonJsString(AArr.Items[i]);
  end;
end;

function TyJsonJsString(AData: TJSONData): string;
begin
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtString: Result := AData.AsString;
    jtArray: Result := JoinText(TJSONArray(AData));
  else
    Result := '[object Object]';
  end;
end;

function TyJsonToNumber(AData: TJSONData): Double;
begin
  if AData = nil then Exit(NaN);
  case AData.JSONType of
    jtNull: Result := 0;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtNumber: Result := AData.AsFloat;
    jtString: Result := TyJsToNumber(AData.AsString);
    jtArray: Result := TyJsToNumber(JoinText(TJSONArray(AData)));
  else
    Result := NaN;
  end;
end;

function TyJsonElement(AData: TJSONData; AIndex: Integer; out AOwned: TJSONData): TJSONData;
var
  u: UnicodeString;
  key: string;
begin
  AOwned := nil;
  Result := nil;
  if TyJsonNullish(AData) then
    raise ETyConvertNull.Create('a null value indexed');
  case AData.JSONType of
    jtArray:
      if (AIndex >= 0) and (AIndex < TJSONArray(AData).Count) then
        Result := TJSONArray(AData).Items[AIndex];
    jtString:
      begin
        { a UTF-16 code unit, as JavaScript indexes a string }
        u := UTF8Decode(AData.AsString);
        if (AIndex >= 0) and (AIndex < Length(u)) then
        begin
          AOwned := TJSONString.Create(UTF8Encode(u[AIndex + 1]));
          Result := AOwned;
        end;
      end;
    jtObject:
      begin
        key := IntToStr(AIndex);
        Result := TJSONObject(AData).Find(key);
      end;
  end;
end;

{ new Date(n).getTime(): the time value clipped to the Date range }
function TimeClip(AMs: Double): Double;
begin
  if IsNan(AMs) or IsInfinite(AMs) or (Abs(AMs) > 8.64e15) then Exit(NaN);
  Result := TyJsRound(AMs);
  if Result = 0 then Result := 0;
end;

function TyAxisParseJson(AAxis: TTyAxis; AData: TJSONData): Double;
var
  ord: Integer;
  ms: Double;
begin
  Result := NaN;
  if AAxis = nil then Exit;
  case AAxis.AxisType of
    atCategory:
      begin
        { OrdinalScale.parse: null is no category -- Math.round(null) would
          be nought -- a name its ordinal, anything else rounded }
        if TyJsonNullish(AData) then Exit(NaN);
        if AData.JSONType = jtString then
        begin
          if AAxis.Categories = nil then Exit(NaN);
          ord := AAxis.Categories.GetOrdinal(AData.AsString);
          if ord < 0 then Exit(NaN);
          Exit(ord);
        end;
        Result := TyJsRound(TyJsonToNumber(AData));
      end;
    atTime:
      begin
        { TimeScale.parse: a number rounded; anything else +parseDate(v) }
        if TyJsonNullish(AData) then Exit(NaN);
        case AData.JSONType of
          jtNumber: Result := TyJsRound(AData.AsFloat);
          jtString:
            if TyParseDateMs(AData.AsString, ms, False) then Result := ms
            else Result := NaN;
        else
          Result := TimeClip(TyJsonToNumber(AData));
        end;
      end;
  else
    { IntervalScale.parse, the log scale's too: null and '' are not
      numbers, the rest is Number(v) }
    if TyJsonNullish(AData) then Exit(NaN);
    if (AData.JSONType = jtString) and (AData.AsString = '') then Exit(NaN);
    Result := TyJsonToNumber(AData);
  end;
end;

{ ==================== the finder ==================== }

function IsWordChars(const S: string): Boolean;
var i: Integer;
begin
  Result := S <> '';
  for i := 1 to Length(S) do
    if not (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit(False);
end;

{ /^(\w+)(Index|Id|Name)$/: the whole key word characters, one of the three
  at the end, something before it. Greedy \w+ backtracks to the LONGEST
  main type, which is whatever stands before the one suffix that ends it. }
function SplitKey(const AKey: string; out AMainType, AQuery: string): Boolean;
  function Ends(const ASuffix: string): Boolean;
  begin
    Result := (Length(AKey) > Length(ASuffix))
      and (Copy(AKey, Length(AKey) - Length(ASuffix) + 1, Length(ASuffix)) = ASuffix);
  end;
begin
  Result := False;
  AMainType := '';
  AQuery := '';
  if not IsWordChars(AKey) then Exit;
  if Ends('Index') then AQuery := 'index'
  else if Ends('Id') then AQuery := 'id'
  else if Ends('Name') then AQuery := 'name'
  else Exit;
  AMainType := Copy(AKey, 1, Length(AKey) - Length(AQuery));
  Result := AMainType <> '';
end;

type
  TQuery = record
    MainType: string;
    Index, Id, Name: TJSONData;   // borrowed; nil is undefined
  end;

{ a JavaScript property key that names an array element: the canonical
  decimal form of a whole number }
function ArrayIndexOf(const AKey: string; out AIndex: Integer): Boolean;
var
  i: Integer;
  v: Int64;
begin
  Result := False;
  AIndex := -1;
  if (AKey = '') or (Length(AKey) > 10) then Exit;
  for i := 1 to Length(AKey) do
    if not (AKey[i] in ['0'..'9']) then Exit;
  if (Length(AKey) > 1) and (AKey[1] = '0') then Exit;
  v := StrToInt64(AKey);
  if v > MaxInt then Exit;
  AIndex := Integer(v);
  Result := True;
end;

function KeyList(const AKeys: TTyOptionKeys; const AMainType: string;
  out AItems: TTyOptionKeyArray): Boolean;
var k: Integer;
begin
  AItems := nil;
  k := TyOptionKeyIndex(AKeys, AMainType);
  Result := (k >= 0) and (Length(AKeys[k].Items) > 0);
  if Result then AItems := AKeys[k].Items;
end;

procedure Push(var A: TTyIntegerArray; AValue: Integer);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := AValue;
end;

{ convertOptionIdName: a string is itself, a number its printed form,
  anything else nothing }
function IdNameOf(AData: TJSONData; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  if TyJsonNullish(AData) then Exit;
  case AData.JSONType of
    jtString: AText := AData.AsString;
    jtNumber: AText := TyJsNumberToString(AData.AsFloat);
  else
    Exit;
  end;
  Result := True;
end;

function QueryModels(const AQ: TQuery; const AKeys: TTyOptionKeys): TTyIntegerArray;
var
  items: TTyOptionKeyArray;
  index, idName: TJSONData;
  byId: Boolean;
  i, k, idx: Integer;
  want: array of string;
  s: string;

  procedure ByIndex(AItem: TJSONData);
  var n: Integer;
  begin
    if not ArrayIndexOf(TyJsonJsString(AItem), n) then Exit;
    if (n <= High(items)) and items[n].Exists then Push(Result, n);
  end;

begin
  Result := nil;
  index := AQ.Index;
  if TyJsonNullish(index) then index := nil;
  { nothing specified: nothing found (no default is assumed) }
  if (index = nil) and TyJsonNullish(AQ.Id) and TyJsonNullish(AQ.Name) then Exit;
  { 'none' and false: nothing }
  if (index <> nil) and (((index.JSONType = jtString) and (index.AsString = 'none'))
    or ((index.JSONType = jtBoolean) and not index.AsBoolean)) then Exit;
  if not KeyList(AKeys, AQ.MainType, items) then Exit;
  { 'all': every model there is }
  if (index <> nil) and (index.JSONType = jtString) and (index.AsString = 'all') then
  begin
    for i := 0 to High(items) do
      if items[i].Exists then Push(Result, i);
    Exit;
  end;
  if index <> nil then
  begin
    if index.JSONType = jtArray then
    begin
      for k := 0 to index.Count - 1 do ByIndex(TJSONArray(index).Items[k]);
    end
    else
      ByIndex(index);
    Exit;
  end;
  byId := not TyJsonNullish(AQ.Id);
  if byId then idName := AQ.Id else idName := AQ.Name;
  want := nil;
  if idName.JSONType = jtArray then
  begin
    { a native Map keyed by the items as written: only a string can equal
      a model's id or name }
    for k := 0 to idName.Count - 1 do
      if TJSONArray(idName).Items[k].JSONType = jtString then
      begin
        SetLength(want, Length(want) + 1);
        want[High(want)] := TJSONArray(idName).Items[k].AsString;
      end;
  end
  else if IdNameOf(idName, s) then
  begin
    SetLength(want, 1);
    want[0] := s;
  end;
  for i := 0 to High(items) do
  begin
    if not items[i].Exists then Continue;
    if byId then s := items[i].Id else s := items[i].Name;
    for idx := 0 to High(want) do
      if want[idx] = s then
      begin
        Push(Result, i);
        Break;
      end;
  end;
end;

function QueryIndex(const AQs: array of TQuery; const AMainType: string): Integer;
var i: Integer;
begin
  for i := 0 to High(AQs) do
    if AQs[i].MainType = AMainType then Exit(i);
  Result := -1;
end;

function TyParseFinder(AFinder: TJSONData; const AKeys: TTyOptionKeys): TTyParsedFinder;
var
  qs: array of TQuery;
  obj: TJSONObject;
  i, q: Integer;
  key, mt, qt: string;
  tmp: TJSONObject;
begin
  Result := Default(TTyParsedFinder);
  qs := nil;
  if AFinder = nil then Exit;
  tmp := nil;
  try
    { 'series' is seriesIndex 0 }
    if AFinder.JSONType = jtString then
    begin
      tmp := TJSONObject.Create;
      tmp.Add(AFinder.AsString + 'Index', 0);
      obj := tmp;
    end
    else if AFinder.JSONType = jtObject then
      obj := TJSONObject(AFinder)
    else
      Exit;
    for i := 0 to obj.Count - 1 do
    begin
      key := obj.Names[i];
      if key = 'dataIndex' then
      begin
        Result.HasDataIndex := True;
        Continue;
      end;
      if key = 'dataIndexInside' then
      begin
        Result.HasDataIndexInside := True;
        Continue;
      end;
      if not SplitKey(key, mt, qt) then Continue;
      q := QueryIndex(qs, mt);
      if q < 0 then
      begin
        SetLength(qs, Length(qs) + 1);
        q := High(qs);
        qs[q] := Default(TQuery);
        qs[q].MainType := mt;
      end;
      if qt = 'index' then qs[q].Index := obj.Items[i]
      else if qt = 'id' then qs[q].Id := obj.Items[i]
      else qs[q].Name := obj.Items[i];
    end;
    SetLength(Result.Types, Length(qs));
    for q := 0 to High(qs) do
    begin
      Result.Types[q].MainType := qs[q].MainType;
      Result.Types[q].Models := QueryModels(qs[q], AKeys);
    end;
  finally
    tmp.Free;
  end;
end;

function TyFinderModels(const AFinder: TTyParsedFinder; const AMainType: string): TTyIntegerArray;
var i: Integer;
begin
  Result := nil;
  for i := 0 to High(AFinder.Types) do
    if AFinder.Types[i].MainType = AMainType then Exit(AFinder.Types[i].Models);
end;

function TyFinderModel(const AFinder: TTyParsedFinder; const AMainType: string): Integer;
var m: TTyIntegerArray;
begin
  m := TyFinderModels(AFinder, AMainType);
  if Length(m) = 0 then Result := -1 else Result := m[0];
end;

{ ==================== the conversions ==================== }

function TyConvertNone: TTyConvertResult;
begin
  Result.Kind := cvkNone;
  Result.Values := nil;
end;

function TyConvertNum(AValue: Double): TTyConvertResult;
begin
  Result.Kind := cvkNumber;
  SetLength(Result.Values, 1);
  Result.Values[0] := AValue;
end;

function TyConvertXY(AX, AY: Double): TTyConvertResult;
begin
  Result.Kind := cvkArray;
  SetLength(Result.Values, 2);
  Result.Values[0] := AX;
  Result.Values[1] := AY;
end;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  { the SSE flags too: ClearExceptions clears the x87 status word only, and
    a sticky invalid-operation flag would be reported by the next trap }
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

function Finite(A: Double): Boolean; inline;
begin
  Result := not (IsNan(A) or IsInfinite(A));
end;

function TyJsonPoint(APoint: TJSONData): TTyPointF;
var
  e0, e1, own0, own1: TJSONData;
begin
  e0 := TyJsonElement(APoint, 0, own0);
  try
    e1 := TyJsonElement(APoint, 1, own1);
    try
      Result.X := TyJsonToNumber(e0);
      Result.Y := TyJsonToNumber(e1);
    finally
      own1.Free;
    end;
  finally
    own0.Free;
  end;
end;

function AxisCoordJs(AAxis: TTyAxis; AValue: Double): Double; forward;

function TyCartesianToPixel(ACart: TTyCartesian2D; AValue: TJSONData): TTyConvertResult;
var
  xv, yv, own0, own1: TJSONData;
  ax, ay: TTyAxis;
  m: TTyMat2D;
  x, y: Double;
  p: TTyPointF;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  if ACart = nil then Exit;
  ax := ACart.AxisByDim('x');
  ay := ACart.AxisByDim('y');
  if (ax = nil) or (ay = nil) then Exit;
  xv := TyJsonElement(AValue, 0, own0);
  try
    yv := TyJsonElement(AValue, 1, own1);
    try
      mask := MaskFP;
      try
        { THE FAST PATH'S GATE is on the raw elements: non-null, and finite
          as global isFinite coerces them -- and the matrix then takes them
          as ToNumber gives them, unparsed }
        if ACart.Transform(m) and not TyJsonNullish(xv) and not TyJsonNullish(yv) then
        begin
          x := TyJsonToNumber(xv);
          y := TyJsonToNumber(yv);
          if Finite(x) and Finite(y) then
          begin
            p := ACart.DataToPoint([x, y]);
            Exit(TyConvertXY(p.X, p.Y));
          end;
        end;
        Result := TyConvertXY(AxisCoordJs(ax, TyAxisParseJson(ax, xv)),
          AxisCoordJs(ay, TyAxisParseJson(ay, yv)));
      finally
        UnmaskFP(mask);
      end;
    finally
      own1.Free;
    end;
  finally
    own0.Free;
  end;
end;

function TyCartesianFromPixel(ACart: TTyCartesian2D; AValue: TJSONData): TTyConvertResult;
var
  pt: TTyPointF;
  d: TTyDoubleArray;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  if ACart = nil then Exit;
  pt := TyJsonPoint(AValue);
  mask := MaskFP;
  try
    if not ACart.PointToData(pt, d) or (Length(d) < 2) then Exit;
    Result := TyConvertXY(d[0], d[1]);
  finally
    UnmaskFP(mask);
  end;
end;

{ toGlobalCoord(dataToCoord(v)), with Math.log's nought: on a log axis 0 is
  log 0 = -Infinity, normalised to an infinite fraction and mapped to an
  infinite pixel -- where the axis' own mapping, which the marks share,
  answers not-a-number }
function AxisCoordJs(AAxis: TTyAxis; AValue: Double): Double;
var a, b: Double;
begin
  if (AAxis.AxisType = atLog) and (AValue = 0) then
  begin
    AAxis.LocalExtent(a, b);
    if b - a = 0 then Exit(NaN);
    Exit(AAxis.ToGlobal(NegInfinity * (b - a) + a));
  end;
  Result := AAxis.DataToCoord(AValue);
end;

function TyAxisToPixel(AAxis: TTyAxis; AValue: TJSONData): TTyConvertResult;
var mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  if AAxis = nil then Exit;
  mask := MaskFP;
  try
    Result := TyConvertNum(AxisCoordJs(AAxis, TyAxisParseJson(AAxis, AValue)));
  finally
    UnmaskFP(mask);
  end;
end;

function TyAxisFromPixel(AAxis: TTyAxis; AValue: TJSONData): TTyConvertResult;
var mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  if AAxis = nil then Exit;
  mask := MaskFP;
  try
    Result := TyConvertNum(AAxis.CoordToData(TyJsonToNumber(AValue)));
  finally
    UnmaskFP(mask);
  end;
end;

function TyCartesianContainJson(ACart: TTyCartesian2D; APoint: TJSONData): Boolean;
var
  pt: TTyPointF;
  mask: TFPUExceptionMask;
begin
  Result := False;
  if ACart = nil then Exit;
  pt := TyJsonPoint(APoint);
  { a coordinate that is not a number is in no extent }
  if IsNan(pt.X) or IsNan(pt.Y) then Exit;
  mask := MaskFP;
  try
    Result := ACart.ContainPoint(pt);
  finally
    UnmaskFP(mask);
  end;
end;

end.
