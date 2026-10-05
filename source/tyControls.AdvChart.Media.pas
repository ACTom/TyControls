unit tyControls.AdvChart.Media;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- upstream's media queries. [Batch 107, B12]

  An option may carry `media`: a list of `(query, option)` units, plus one
  unit without a query, the DEFAULT. Upstream's OptionManager
  (model/OptionManager.ts) keeps them beside the models; every setOption
  merges its base option and then, in the list's order, every unit whose
  query the chart's size meets -- or the default when none does; a resize
  merges the units again only when the set that applies has changed.

  THE RAW OPTION (parseRawOption): with a truthy `baseOption` the base is
  that, and of the root only `media` (and `timeline`, copied into a base
  without one) is read; without one the root is the base, and `media` and
  `options` are taken off it when it has media or a timeline. The units: of
  a `media` ARRAY, each with a truthy `option`; with a truthy `query` it is
  listed, else the first such is the default. The preprocessors run over
  the base and the listed units -- never over the default.

  THE QUERY (applyMediaQuery): every key `^(min|max)?(.+)$` WITH a prefix,
  the rest lowercased and looked up in width, height and aspectratio; `min`
  is >=, `max` is <=, against the value as JavaScript's relational
  comparison converts it (a string by Number(), null 0, true 1, an array by
  its join). A key without the prefix is ignored -- `width: 500` holds
  whatever the width, the equality branch is unreachable -- and a prefixed
  key of anything else never holds (undefined against a number). The
  prefix is case-sensitive: `MinWidth` is ignored, `minWIDTH` is width.
  So SIX keys: min/max Width, Height and AspectRatio. Width and height
  are the chart's in CSS px; the aspect ratio is width / height.

  THE ORDER (getMediaOption): the indices of the units that apply,
  ascending, or [-1] -- the default -- when none does and there is one.
  Merged only when non-empty and different from the indices last merged;
  the indices are kept either way. A setOption forgets them first
  (mountOption), so every setOption merges what applies.

  A MERGE (setOption without notMerge) replaces the list when its option
  has units, and the default when it has one -- never merges them; a
  notMerge starts a new manager.

  LCL-free: SysUtils, Math, fcl-json and the data unit's Number(). }
interface
uses SysUtils, Math, fpjson;

type
  TTyMediaUnit = record
    { owned; nil for the default }
    Query: TJSONData;
    { owned }
    Option: TJSONObject;
  end;
  TTyMediaUnits = array of TTyMediaUnit;
  TTyMediaIndices = array of Integer;

  { what parseRawOption reads off one raw option }
  TTyMediaSet = record
    Units: TTyMediaUnits;
    { owned; nil: none }
    DefaultOpt: TJSONObject;
  end;

  { one option getMediaOption hands over: a clone the caller frees }
  TTyMediaPending = record
    Option: TJSONObject;
    { the default: the preprocessors never saw it }
    IsDefault: Boolean;
  end;
  TTyMediaPendingArray = array of TTyMediaPending;

  { THE MANAGER's media half: the list, the default, the indices last
    merged }
  TTyMediaManager = class
  private
    FSet: TTyMediaSet;
    FCurrent: TTyMediaIndices;
  public
    destructor Destroy; override;
    procedure Clear;
    { a fresh option (notMerge, the first setOption): ASet's, which is taken
      over and left empty }
    procedure Reset(var ASet: TTyMediaSet);
    { a merge: the list replaced when ASet has units, the default when it
      has one; ASet is taken over and left empty }
    procedure Adopt(var ASet: TTyMediaSet);
    { mountOption: the indices forgotten }
    procedure Mount;
    { getMediaOption at AWidth x AHeight (CSS px): the options to merge now,
      in order (clones the caller frees); empty when nothing applies or the
      same set did last time. The indices are kept. }
    function Take(AWidth, AHeight: Double): TTyMediaPendingArray;
    function UnitCount: Integer;
    function UnitQuery(AIndex: Integer): TJSONData;
    function UnitOption(AIndex: Integer): TJSONObject;
    function HasDefault: Boolean;
    property Current: TTyMediaIndices read FCurrent;
  end;

{ parseRawOption: ARaw becomes the base -- the declared `baseOption` (the old
  object freed) or the root itself with `media` / `options` taken off -- and
  ASet the units read off it. A unit whose option carries one id twice in a
  main type is dropped (upstream asserts when it merges it). }
procedure TyParseRawOption(var ARaw: TJSONObject; out ASet: TTyMediaSet);
procedure TyMediaSetFree(var ASet: TTyMediaSet);

{ applyMediaQuery }
function TyMediaQueryApplies(AQuery: TJSONData; AWidth, AHeight: Double): Boolean;
{ the indices getMediaOption computes, before it compares them }
function TyMediaIndicesOf(const ASet: TTyMediaSet; AWidth, AHeight: Double): TTyMediaIndices;
function TyMediaIndicesEqual(const A, B: TTyMediaIndices): Boolean;
{ JavaScript's ToNumber of a JSON value, as a relational comparison makes it }
function TyMediaJsNumber(AData: TJSONData): Double;

implementation

uses tyControls.AdvChart.Data, tyControls.AdvChart.OptionMerge;

function JsTruthy(AData: TJSONData): Boolean;
var v: Double;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber:
      begin
        v := AData.AsFloat;
        Result := (v <> 0) and not IsNan(v);
      end;
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

procedure TyMediaSetFree(var ASet: TTyMediaSet);
var i: Integer;
begin
  for i := 0 to High(ASet.Units) do
  begin
    ASet.Units[i].Query.Free;
    ASet.Units[i].Option.Free;
  end;
  ASet.Units := nil;
  FreeAndNil(ASet.DefaultOpt);
end;

{ ==================== parseRawOption ==================== }

{ the unit's option as an object: a truthy one that is no object merges as
  nothing -- an empty object }
function OptionObject(AData: TJSONData): TJSONObject;
begin
  if AData is TJSONObject then Result := TJSONObject(AData.Clone)
  else Result := TJSONObject.Create;
end;

procedure TyParseRawOption(var ARaw: TJSONObject; out ASet: TTyMediaSet);
var
  declared, timelineRoot, mediaRoot, d, q, o: TJSONData;
  hasMedia, hasTimeline: Boolean;
  base: TJSONObject;
  i, n: Integer;
  opt: TJSONObject;
begin
  ASet := Default(TTyMediaSet);
  if ARaw = nil then Exit;
  declared := ARaw.Find('baseOption');
  timelineRoot := ARaw.Find('timeline');
  mediaRoot := ARaw.Find('media');
  hasMedia := JsTruthy(mediaRoot);
  hasTimeline := JsTruthy(ARaw.Find('options')) or JsTruthy(timelineRoot)
    or (JsTruthy(declared) and (declared is TJSONObject)
      and JsTruthy(TJSONObject(declared).Find('timeline')));

  { ---- the units, read before the root is touched ---- }
  if hasMedia and (mediaRoot is TJSONArray) then
    for i := 0 to mediaRoot.Count - 1 do
    begin
      d := mediaRoot.Items[i];
      if not (d is TJSONObject) then Continue;
      o := TJSONObject(d).Find('option');
      if not JsTruthy(o) then Continue;
      q := TJSONObject(d).Find('query');
      if JsTruthy(q) then
      begin
        opt := OptionObject(o);
        if TyOptionHasDuplicateId(opt) then
        begin
          opt.Free;
          Continue;
        end;
        n := Length(ASet.Units);
        SetLength(ASet.Units, n + 1);
        ASet.Units[n].Query := q.Clone;
        ASet.Units[n].Option := opt;
      end
      else if ASet.DefaultOpt = nil then
      begin
        { the first media default }
        opt := OptionObject(o);
        if TyOptionHasDuplicateId(opt) then opt.Free
        else ASet.DefaultOpt := opt;
      end;
    end;

  { ---- the base ---- }
  if JsTruthy(declared) then
  begin
    if declared is TJSONObject then
      base := TJSONObject(ARaw.Extract('baseOption'))
    else
      { upstream writes `timeline` into it and throws; an empty base here }
      base := TJSONObject.Create;
    { compat ec2: `timeline` beside baseOption, for a base without one }
    if not JsTruthy(base.Find('timeline')) then
    begin
      if timelineRoot <> nil then base.Elements['timeline'] := timelineRoot.Clone
      else if base.Find('timeline') <> nil then base.Delete('timeline');
    end;
    ARaw.Free;
    ARaw := base;
  end
  else if hasTimeline or hasMedia then
  begin
    { `rawOption.options = rawOption.media = null`: a root null is never
      merged, so they go }
    if ARaw.Find('options') <> nil then ARaw.Delete('options');
    if ARaw.Find('media') <> nil then ARaw.Delete('media');
  end;
end;

{ ==================== applyMediaQuery ==================== }

function TyMediaJsNumber(AData: TJSONData): Double;
begin
  if AData = nil then Exit(NaN);
  case AData.JSONType of
    jtNull: Result := 0;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtNumber: Result := AData.AsFloat;
    jtString: Result := TyJsToNumber(AData.AsString);
    jtArray:
      { ToPrimitive is the join: nothing is '' (nought), one entry is that
        entry's string, two or more carry a comma and read as nothing }
      case AData.Count of
        0: Result := 0;
        1:
          case AData.Items[0].JSONType of
            jtNull: Result := 0;
            jtNumber, jtString, jtArray: Result := TyMediaJsNumber(AData.Items[0]);
          else
            { 'true' / 'false' / '[object Object]' }
            Result := NaN;
          end;
      else
        Result := NaN;
      end;
  else
    { '[object Object]' }
    Result := NaN;
  end;
end;

function HasLineTerminator(const AText: string): Boolean;
begin
  Result := (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0)
    or (Pos(#$E2#$80#$A8, AText) > 0) or (Pos(#$E2#$80#$A9, AText) > 0);
end;

{ ASCII lowercasing: no other character lowers into width, height or
  aspectratio }
function AsciiLower(const AText: string): string;
var i: Integer;
begin
  Result := AText;
  for i := 1 to Length(Result) do
    if Result[i] in ['A'..'Z'] then Result[i] := Chr(Ord(Result[i]) + 32);
end;

function KeyHolds(const AKey: string; AValue: TJSONData; AWidth, AHeight: Double;
  out AIgnored: Boolean): Boolean;
var
  op, attr: string;
  real, expect: Double;
begin
  Result := True;
  AIgnored := True;
  { `.+` stops at a line terminator: no match, nothing compared }
  if (Length(AKey) < 4) or HasLineTerminator(AKey) then Exit;
  op := Copy(AKey, 1, 3);
  if (op <> 'min') and (op <> 'max') then Exit;
  AIgnored := False;
  attr := AsciiLower(Copy(AKey, 4, MaxInt));
  if attr = 'width' then real := AWidth
  else if attr = 'height' then real := AHeight
  else if attr = 'aspectratio' then
  begin
    { ecWidth / ecHeight, as JavaScript divides }
    if AHeight <> 0 then real := AWidth / AHeight
    else if IsNan(AWidth) or (AWidth = 0) then real := NaN
    else if AWidth > 0 then real := Infinity
    else real := NegInfinity;
  end
  else
    { realMap[attr] is undefined: NaN against anything }
    real := NaN;
  expect := TyMediaJsNumber(AValue);
  { any NaN fails both comparisons -- tested first, FPC's <= with a NaN is
    not to be trusted }
  if IsNan(real) or IsNan(expect) then Exit(False);
  if op = 'min' then Result := real >= expect
  else Result := real <= expect;
end;

function TyMediaQueryApplies(AQuery: TJSONData; AWidth, AHeight: Double): Boolean;
var
  i: Integer;
  ignored: Boolean;
  len: TJSONData;
begin
  Result := True;
  if AQuery = nil then Exit;
  case AQuery.JSONType of
    jtObject:
      begin
        { zrender's each takes an object with a numeric `length` for an
          array: none of its keys is read, and an index is no string to
          match -- a TypeError upstream, never applying here }
        len := TJSONObject(AQuery).Find('length');
        if (len <> nil) and (len.JSONType = jtNumber) then
          Exit(len.AsFloat <= 0);
        for i := 0 to AQuery.Count - 1 do
          if not KeyHolds(TJSONObject(AQuery).Names[i], AQuery.Items[i],
            AWidth, AHeight, ignored) then Result := False;
      end;
    jtArray:
      { indices again: a TypeError upstream unless there is none }
      Result := AQuery.Count = 0;
    jtString:
      { each character's index: the same }
      Result := AQuery.AsString = '';
  else
    { a number or a boolean has no keys }
    Result := True;
  end;
end;

function TyMediaIndicesOf(const ASet: TTyMediaSet; AWidth, AHeight: Double): TTyMediaIndices;
var i, n: Integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(ASet.Units) do
    if TyMediaQueryApplies(ASet.Units[i].Query, AWidth, AHeight) then
    begin
      SetLength(Result, n + 1);
      Result[n] := i;
      Inc(n);
    end;
  if (n = 0) and (ASet.DefaultOpt <> nil) then
  begin
    SetLength(Result, 1);
    Result[0] := -1;
  end;
end;

function TyMediaIndicesEqual(const A, B: TTyMediaIndices): Boolean;
var i: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for i := 0 to High(A) do
    if A[i] <> B[i] then Exit(False);
end;

{ ==================== the manager ==================== }

destructor TTyMediaManager.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TTyMediaManager.Clear;
begin
  TyMediaSetFree(FSet);
  FCurrent := nil;
end;

procedure TTyMediaManager.Reset(var ASet: TTyMediaSet);
begin
  Clear;
  FSet := ASet;
  ASet := Default(TTyMediaSet);
end;

procedure TTyMediaManager.Adopt(var ASet: TTyMediaSet);
var keep: TTyMediaSet;
begin
  { "timeline options and media options do not support merge": a new list
    substitutes the old one, a new default the old default }
  if Length(ASet.Units) > 0 then
  begin
    keep := Default(TTyMediaSet);
    keep.Units := FSet.Units;
    TyMediaSetFree(keep);
    FSet.Units := ASet.Units;
    ASet.Units := nil;
  end;
  if ASet.DefaultOpt <> nil then
  begin
    FSet.DefaultOpt.Free;
    FSet.DefaultOpt := ASet.DefaultOpt;
    ASet.DefaultOpt := nil;
  end;
  TyMediaSetFree(ASet);
end;

procedure TTyMediaManager.Mount;
begin
  FCurrent := nil;
end;

function TTyMediaManager.Take(AWidth, AHeight: Double): TTyMediaPendingArray;
var
  idx: TTyMediaIndices;
  i: Integer;
begin
  Result := nil;
  { no media defined }
  if (Length(FSet.Units) = 0) and (FSet.DefaultOpt = nil) then Exit;
  idx := TyMediaIndicesOf(FSet, AWidth, AHeight);
  if (Length(idx) > 0) and not TyMediaIndicesEqual(idx, FCurrent) then
  begin
    SetLength(Result, Length(idx));
    for i := 0 to High(idx) do
    begin
      Result[i].IsDefault := idx[i] = -1;
      if idx[i] = -1 then Result[i].Option := TJSONObject(FSet.DefaultOpt.Clone)
      else Result[i].Option := TJSONObject(FSet.Units[idx[i]].Option.Clone);
    end;
  end;
  FCurrent := idx;
end;

function TTyMediaManager.UnitCount: Integer;
begin
  Result := Length(FSet.Units);
end;

function TTyMediaManager.UnitQuery(AIndex: Integer): TJSONData;
begin
  Result := FSet.Units[AIndex].Query;
end;

function TTyMediaManager.UnitOption(AIndex: Integer): TJSONObject;
begin
  Result := FSet.Units[AIndex].Option;
end;

function TTyMediaManager.HasDefault: Boolean;
begin
  Result := FSet.DefaultOpt <> nil;
end;

end.
