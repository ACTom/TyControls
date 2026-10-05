unit tyControls.AdvChart.OptionMerge;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- upstream's MERGE setOption, on the option tree.
  [Batch 95, A10 / MG1]

  A second setOption without notMerge does not replace the option: it maps
  each component and series it carries onto the models that already exist
  and merges it into them (Global.ts _mergeOption). This unit is that, done
  on the port's tree -- the RAW merge, what the author wrote merged by
  upstream's rules -- because the port applies defaults when it reads, where
  upstream merged them into the models' options at init.

  THE MODELS' IDENTITY lives beside the tree, in TTyOptionKeys: per main type
  the slots upstream's component list has, each with the model's id, name
  and subType, or a hole. An id never changes once made; a merge reads the
  existing ids and names to map by, so the keys have to survive every merge
  -- the tree alone cannot say which series a renamed one was.

  THE RULES, each from its source line:
  - mappingToExists (util/model.ts): normalMerge maps by id, then by name
    (only an option without an id, onto the first unmapped model of that
    name), then by index (the first unmapped slot from 0, a hole included,
    never a model with a DIFFERENT id when the option has one), and appends
    what is left; a main type seen for the first time is replaceAll, holes
    kept. makeIdAndName names and ids what was mapped.
  - a model of the same class merges (zrender merge: objects deeply,
    everything else -- arrays, null -- written as it is); a different class,
    or no model, is built from the new option ALONE and keeps the slot's id.
  - root keys that are no component: null ignored, absent cloned, else
    zrender's merge on the root value -- arrays merged index by index.
  - every option visits the series and the axisPointer (the backwardCompat
    and axisPointer preprocessors write both into every option), and with
    them every main type that depends on a visited one.
  - THE PREPROCESSORS' MODELS: `axisPointer: {}` in every option, `grid: {}`
    in one with an xAxis and a yAxis and no grid. They are models upstream
    and nothing the author wrote, so they are in the keys and not in the
    tree; a later option that writes one merges into it -- the node made
    then, empty, as the model's raw option was.
  - mergeLayoutParam for the box-layout models the port lays out (grid,
    title, legend, visualMap, the tree / sankey / treemap series): the three
    keys of a direction the new option touches are WRITTEN, null where
    upstream leaves undefined, so the reader's init merge gives back exactly
    what upstream holds.
  - dataZoom: a pair written in value mode nulls its percent (_doInit);
    dataset: transform is replaced, never merged.

  REPLACEMERGE [Batch 97, A11]: the main types a setOption names in
  `replaceMerge` keep no model but those its options name by id; every other
  model of the type is REMOVED and leaves a hole at its index -- indices
  never move -- and the options mapped by index are BRAND NEW (a new view
  even where the id they make was a removed model's): they fill the first
  slot no id took, a removed model's or an older hole, and append after.
  A named type the option leaves out is merged as `[]`: all removed.

  NOTMERGE COMPACTS THE SERIES: upstream seeds the series' list at init, so
  a fresh option's series are a normalMerge over nothing -- a null entry
  takes no index (TyOptionCompactSeries). The other main types are seen
  for the first time there: replaceAll, holes kept.

  AN OPTION THE PREPROCESSORS NEVER SAW [Batch 107]: parseRawOption runs
  them over the base and over every media option with a query -- but not
  over the media DEFAULT. Merged with APreprocessed False, an option visits
  only what it writes and what depends on that, and makes no preprocessor
  model.

  WHAT IT DOES NOT DO: timeline (and with it the replaceAll of a whole
  option, which without it is the notMerge; media and baseOption are
  tyControls.AdvChart.Media's [Batch 107]); the box merge of calendar, singleAxis, geo, parallel, matrix, timeline,
  thumbnail, the slider dataZoom and the map series; upstream's
  preprocessors otherwise.

  LCL-free: SysUtils, Math, fcl-json and the scale's number printer. }
interface
uses SysUtils, Math, fpjson;

type
  { ONE MODEL'S IDENTITY: upstream's keyInfo, as the model keeps it. }
  TTyOptionKey = record
    { a model sits at this index; False is a hole }
    Exists: Boolean;
    Id, Name, SubType: string;
  end;
  TTyOptionKeyArray = array of TTyOptionKey;

  { One main type's component list. A main type is listed once upstream has
    a list for it -- visited by some setOption -- even when it is empty: the
    next merge of that type is then a normalMerge, not a replaceAll. }
  TTyOptionKeyList = record
    MainType: string;
    Items: TTyOptionKeyArray;
  end;
  TTyOptionKeys = array of TTyOptionKeyList;

  { What a merge did to one slot. }
  TTyMergeFate = (
    mfHole,    // no model before or after
    mfKept,    // the model stayed, nothing written for it
    mfMerged,  // the model stayed and the new option was merged into it
    mfNew,     // a new model: none was there, or its class changed
    mfRemoved  // replaceMerge: the model went, the index is a hole now
  );

  TTyMergeFateArray = array of TTyMergeFate;
  TTyMergeOptArray = array of TJSONObject;
  TTyMergeBoolArray = array of Boolean;

  TTyMergeSlots = record
    MainType: string;
    Fate: TTyMergeFateArray;
    { the new option merged into the slot, BORROWED from the merged-in
      option (alive while the caller keeps it); nil where none }
    NewOpt: TTyMergeOptArray;
    { a new model replaceMerge mapped by index: upstream's brandNew, which
      asks for a new view whatever its id (__requireNewView) }
    Brand: TTyMergeBoolArray;
  end;

  TTyMergeReport = record
    Visited: TStringArray;
    Slots: array of TTyMergeSlots;
  end;

  { Called for an existing model of the same class just before the new
    option is merged into its node -- where the control writes back what it
    keeps outside the tree and upstream keeps in the model's option. }
  TTyMergeBeforeComponent = procedure(const AMainType: string; AIndex: Integer;
    ANode, ANew: TJSONObject) of object;

{ upstream's component main types, ComponentModel.getAllClassMainTypes() }
function TyOptionMainTypeCount: Integer;
function TyOptionMainType(AIndex: Integer): string;
function TyOptionIsComponentType(const AKey: string): Boolean;
{ the main types AMainType depends on (its classes' `dependencies`) }
function TyOptionDependencies(const AMainType: string): string;
{ whether AMainType's classes are per subType (an axis, a dataZoom ...) }
function TyOptionHasSubTypes(const AMainType: string): Boolean;

{ The main types a setOption writing AWritten visits: those, the series and
  the axisPointer, and every main type that depends on a visited one. }
function TyOptionVisited(const AWritten: array of string): TStringArray;

{ THE KEYS OF A FRESH OPTION -- a notMerge setOption, or the first one: every
  written main type replaceAll over the tree's own indices (a non-object
  entry is a hole), every other visited one an empty list. }
procedure TyOptionKeysOfTree(ARoot: TJSONData; out AKeys: TTyOptionKeys);

{ THE MERGE. ARoot is changed in place; AKeys follows. AReplaceMerge: the
  main types merged in replaceMerge mode [Batch 97]. False, with nothing
  changed, when two of the new option's components of one main type carry
  the same id, or AReplaceMerge names no component main type (upstream
  asserts). }
function TyOptionMerge(ARoot: TJSONObject; var AKeys: TTyOptionKeys;
  ANew: TJSONObject; ABefore: TTyMergeBeforeComponent;
  out AReport: TTyMergeReport; out AError: string): Boolean; overload;
function TyOptionMerge(ARoot: TJSONObject; var AKeys: TTyOptionKeys;
  ANew: TJSONObject; const AReplaceMerge: array of string;
  ABefore: TTyMergeBeforeComponent;
  out AReport: TTyMergeReport; out AError: string): Boolean; overload;

{ THE SAME, for an option the preprocessors did not see -- the media
  default [Batch 107]: APreprocessed False visits only the written main types
  and their dependents, and makes no preprocessor model. }
function TyOptionMerge(ARoot: TJSONObject; var AKeys: TTyOptionKeys;
  ANew: TJSONObject; const AReplaceMerge: array of string; APreprocessed: Boolean;
  ABefore: TTyMergeBeforeComponent;
  out AReport: TTyMergeReport; out AError: string): Boolean; overload;

{ whether two of ANew's components of one main type carry the same id --
  the merge upstream asserts on [Batch 107] }
function TyOptionHasDuplicateId(ANew: TJSONObject): Boolean;

{ '' when every name is a component main type, else the first that is not }
function TyOptionBadReplaceType(const AReplaceMerge: array of string): string;

{ A FRESH OPTION'S SERIES, as initBase's seeded list maps them: a normalMerge
  over no model, so an entry that is no object takes no index -- dropped,
  the ones after it move up. A series value that is neither an array, an
  object nor null becomes `[]`. [Batch 97] }
procedure TyOptionCompactSeries(ARoot: TJSONData);

{ whether a model was there after the merge }
function TyMergeHasModel(AFate: TTyMergeFate): Boolean;

{ the list of AMainType in AKeys, or -1 }
function TyOptionKeyIndex(const AKeys: TTyOptionKeys; const AMainType: string): Integer;
{ the slots of AMainType in AReport, or -1 }
function TyMergeSlotsIndex(const AReport: TTyMergeReport; const AMainType: string): Integer;

{ THE MERGED OPTION AS upstream's getOption SHAPES IT: every component main
  type an array (a bare object is one, a non-object entry null, trailing
  nulls trimmed), null root keys left out, every object in JavaScript's key
  order, numbers as JavaScript prints them (NaN and the infinities null). }
function TyOptionToJson(ARoot: TJSONData): string;

{ an object's keys in JavaScript's order: index keys ascending, then the
  rest as inserted }
function TyJsOrderedKeys(AObj: TJSONObject): TStringArray;
{ JSON.stringify of one string }
function TyJsonQuote(const AText: string): string;

implementation

uses tyControls.AdvChart.Scale, tyControls.StrConsts;

const
  cMainTypes: array[0..29] of string = ('series', 'grid', 'xAxis', 'yAxis',
    'radar', 'geo', 'parallel', 'component', 'parallelAxis', 'axisPointer',
    'polar', 'angleAxis', 'radiusAxis', 'singleAxis', 'calendar', 'matrix',
    'graphic', 'toolbox', 'dataZoom', 'tooltip', 'brush', 'title', 'timeline',
    'markPoint', 'markLine', 'markArea', 'legend', 'visualMap', 'thumbnail',
    'dataset');
  { the `dependencies` of every class of a main type, space separated }
  cDeps: array[0..29] of string = (
    'calendar geo grid matrix parallel polar radar singleAxis xAxis yAxis',
    'xAxis yAxis', '', '', '', '', 'parallelAxis', '', '', '',
    'angleAxis radiusAxis', '', '', '', '', '', '', '',
    'angleAxis radiusAxis series singleAxis toolbox xAxis yAxis',
    'axisPointer', 'geo grid parallel series xAxis yAxis', '', '',
    'geo grid polar series', 'geo grid polar series', 'geo grid polar series',
    'series', 'series', 'geo series', '');
  cSubTyped: array[0..10] of string = ('series', 'xAxis', 'yAxis',
    'parallelAxis', 'angleAxis', 'radiusAxis', 'singleAxis', 'dataZoom',
    'timeline', 'legend', 'visualMap');
  cBoxNames: array[0..5] of string = ('width', 'left', 'right',
    'height', 'top', 'bottom');

type
  TNodeArray = array of TJSONData;

function TyOptionMainTypeCount: Integer;
begin
  Result := Length(cMainTypes);
end;

function TyOptionMainType(AIndex: Integer): string;
begin
  Result := cMainTypes[AIndex];
end;

function MainTypeIndex(const AKey: string): Integer;
var i: Integer;
begin
  for i := 0 to High(cMainTypes) do
    if cMainTypes[i] = AKey then Exit(i);
  Result := -1;
end;

function TyOptionIsComponentType(const AKey: string): Boolean;
begin
  Result := MainTypeIndex(AKey) >= 0;
end;

function TyOptionDependencies(const AMainType: string): string;
var i: Integer;
begin
  i := MainTypeIndex(AMainType);
  if i < 0 then Exit('');
  Result := cDeps[i];
end;

function TyOptionHasSubTypes(const AMainType: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(cSubTyped) do
    if cSubTyped[i] = AMainType then Exit(True);
  Result := False;
end;

function InList(const AList: TStringArray; const AKey: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(AList) do
    if AList[i] = AKey then Exit(True);
  Result := False;
end;

procedure AddTo(var AList: TStringArray; const AKey: string);
begin
  if InList(AList, AKey) then Exit;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AKey;
end;

{ the words of a space separated list }
function Words(const AText: string): TStringArray;
var
  i, s: Integer;
begin
  Result := nil;
  s := 1;
  for i := 1 to Length(AText) + 1 do
    if (i > Length(AText)) or (AText[i] = ' ') then
    begin
      if i > s then AddTo(Result, Copy(AText, s, i - s));
      s := i + 1;
    end;
end;

function VisitedOf(const AWritten: array of string; ASeeded: Boolean): TStringArray;
var
  i: Integer;
  grew: Boolean;
  deps: TStringArray;
  d: string;
begin
  Result := nil;
  for i := 0 to High(AWritten) do AddTo(Result, AWritten[i]);
  { backwardCompat writes `series`, the axisPointer preprocessor
    `axisPointer`, into every option they see }
  if ASeeded then
  begin
    AddTo(Result, 'series');
    AddTo(Result, 'axisPointer');
  end;
  repeat
    grew := False;
    for i := 0 to High(cMainTypes) do
    begin
      if InList(Result, cMainTypes[i]) then Continue;
      deps := Words(cDeps[i]);
      for d in deps do
        if InList(Result, d) then
        begin
          AddTo(Result, cMainTypes[i]);
          grew := True;
          Break;
        end;
    end;
  until not grew;
end;

function TyOptionVisited(const AWritten: array of string): TStringArray;
begin
  Result := VisitedOf(AWritten, True);
end;

{ ==================== small JavaScript ==================== }

function IsIndexKey(const AKey: string): Boolean;
var i: Integer; v: QWord;
begin
  Result := False;
  if (AKey = '') or (Length(AKey) > 10) then Exit;
  if (Length(AKey) > 1) and (AKey[1] = '0') then Exit;
  v := 0;
  for i := 1 to Length(AKey) do
  begin
    if not (AKey[i] in ['0'..'9']) then Exit;
    v := v * 10 + QWord(Ord(AKey[i]) - Ord('0'));
  end;
  Result := v < QWord(4294967295);
end;

function TyJsOrderedKeys(AObj: TJSONObject): TStringArray;
var
  i, j, n: Integer;
  idx: array of QWord;
  t: string;
  v: QWord;
begin
  Result := nil;
  if AObj = nil then Exit;
  SetLength(Result, AObj.Count);
  SetLength(idx, AObj.Count);
  n := 0;
  for i := 0 to AObj.Count - 1 do
  begin
    t := AObj.Names[i];
    if not IsIndexKey(t) then Continue;
    v := StrToQWord(t);
    j := n;
    while (j > 0) and (idx[j - 1] > v) do
    begin
      idx[j] := idx[j - 1];
      Result[j] := Result[j - 1];
      Dec(j);
    end;
    idx[j] := v;
    Result[j] := t;
    Inc(n);
  end;
  for i := 0 to AObj.Count - 1 do
  begin
    t := AObj.Names[i];
    if IsIndexKey(t) then Continue;
    Result[n] := t;
    Inc(n);
  end;
end;

{ a number as `'' + x` prints it }
function JsNumText(AData: TJSONData): string;
var v: Double;
begin
  if (AData is TJSONIntegerNumber) or (AData is TJSONInt64Number) then
  begin
    if Abs(AData.AsInt64) < Int64(9007199254740992) then Exit(IntToStr(AData.AsInt64));
  end;
  v := AData.AsFloat;
  Result := TyJsNumberToString(v);
end;

{ `x != null` }
function Given(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType <> jtNull);
end;

{ JavaScript truthiness of an option value }
function Truthy(AData: TJSONData): Boolean;
var v: Double;
begin
  if (AData = nil) then Exit(False);
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

{ convertOptionIdName(x, ADefault): a string as it is, a number as
  JavaScript prints it, anything else ADefault (AHas False) }
function IdNameKey(AData: TJSONData; out AHas: Boolean): string;
begin
  AHas := True;
  Result := '';
  if AData = nil then
  begin
    AHas := False;
    Exit;
  end;
  case AData.JSONType of
    jtString: Result := AData.AsString;
    jtNumber: Result := JsNumText(AData);
  else
    AHas := False;
  end;
end;

{ makeComparableKey: convertOptionIdName(x, '') }
function ComparableKey(AData: TJSONData): string;
var has: Boolean;
begin
  Result := IdNameKey(AData, has);
end;

function TyJsonQuote(const AText: string): string;
const cHex = '0123456789abcdef';
var
  i: Integer;
  c: Char;
begin
  Result := '"';
  for i := 1 to Length(AText) do
  begin
    c := AText[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
      #0..#7, #11, #14..#31:
        Result := Result + '\u00' + cHex[(Ord(c) shr 4) + 1] + cHex[(Ord(c) and 15) + 1];
    else
      Result := Result + c;
    end;
  end;
  Result := Result + '"';
end;

{ ==================== the subType and the class ==================== }

{ the subType a new option names, when its `type` is truthy }
function WrittenType(ANew: TJSONObject; out AType: string): Boolean;
var d: TJSONData;
begin
  AType := '';
  d := ANew.Find('type');
  Result := Truthy(d);
  if not Result then Exit;
  if d.JSONType = jtString then AType := d.AsString
  else if d.JSONType = jtNumber then AType := JsNumText(d)
  else if d.JSONType = jtBoolean then AType := 'true'
  else AType := '[object]';
end;

{ ComponentModel.determineSubType: the registered defaulters }
function DefaultSubType(const AMainType: string; ANew: TJSONObject): string;
var
  d, p: TJSONData;
  piecewise: Boolean;
begin
  Result := '';
  if (AMainType = 'xAxis') or (AMainType = 'yAxis') or (AMainType = 'angleAxis')
    or (AMainType = 'radiusAxis') or (AMainType = 'singleAxis')
    or (AMainType = 'parallelAxis') then
  begin
    { getAxisType: `option.data ? 'category' : 'value'` }
    if Truthy(ANew.Find('data')) then Result := 'category' else Result := 'value';
  end
  else if AMainType = 'dataZoom' then Result := 'slider'
  else if AMainType = 'legend' then Result := 'plain'
  else if AMainType = 'timeline' then Result := 'slider'
  else if AMainType = 'visualMap' then
  begin
    { piecewise when categories, or pieces with an item, or (no pieces) a
      splitNumber above 0 and not calculable }
    piecewise := Truthy(ANew.Find('categories'));
    if not piecewise then
    begin
      p := ANew.Find('pieces');
      if Truthy(p) then
        piecewise := (p.JSONType = jtArray) and (p.Count > 0)
      else
      begin
        d := ANew.Find('splitNumber');
        piecewise := (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat > 0);
      end;
      if piecewise and Truthy(ANew.Find('calculable')) then piecewise := False;
    end;
    if piecewise then Result := 'piecewise' else Result := 'continuous';
  end;
end;

{ the class a subType picks: one per subType where the main type has them,
  else the one class }
function ClassOf(const AMainType, ASubType: string): string;
begin
  if TyOptionHasSubTypes(AMainType) then Result := ASubType else Result := '';
end;

{ ==================== zrender's merge ==================== }

function PlainObject(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType = jtObject);
end;

function Container(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType in [jtObject, jtArray]);
end;

{ merge(target, source, true) with both plain objects: a plain object over a
  plain object recurses, everything else is written as a clone. ANoRecurse
  names a top-level key that is always written (a dataset's transform,
  marked primitive upstream). }
procedure MergeObject(ATarget, ASource: TJSONObject; const ANoRecurse: string);
var
  i: Integer;
  k: string;
  sp, tp: TJSONData;
begin
  for i := 0 to ASource.Count - 1 do
  begin
    k := ASource.Names[i];
    sp := ASource.Items[i];
    tp := ATarget.Find(k);
    if (k <> ANoRecurse) and PlainObject(sp) and PlainObject(tp) then
      MergeObject(TJSONObject(tp), TJSONObject(sp), '')
    else
      ATarget.Elements[k] := sp.Clone;
  end;
end;

{ one index of an array target, as `target[i] = ...` or a recursion }
procedure MergeArrayAt(ATarget: TJSONArray; AIndex: Integer; ASource: TJSONData);
var tp: TJSONData;
begin
  tp := nil;
  if AIndex < ATarget.Count then tp := ATarget.Items[AIndex];
  if PlainObject(ASource) and PlainObject(tp) then
  begin
    MergeObject(TJSONObject(tp), TJSONObject(ASource), '');
    Exit;
  end;
  { past the end: the holes between read back as null }
  while ATarget.Count < AIndex do ATarget.Add(TJSONNull.Create);
  if AIndex < ATarget.Count then
  begin
    ATarget.Delete(AIndex);
    ATarget.Insert(AIndex, ASource.Clone);
  end
  else
    ATarget.Add(ASource.Clone);
end;

{ zrender's merge(target, source, true) on a ROOT value: two containers
  merge in place (an array by index -- `for (key in source)` walks an
  array's indices too) and the target is the answer; otherwise a clone of
  the source is. A key an array cannot hold (not an index) is lost, as it
  would be to JSON. }
function MergeRootValue(ATarget, ASource: TJSONData): TJSONData;
var
  i: Integer;
  k: string;
begin
  if not (Container(ATarget) and Container(ASource)) then
    Exit(ASource.Clone);
  Result := ATarget;
  if ATarget.JSONType = jtObject then
  begin
    if ASource.JSONType = jtObject then
      MergeObject(TJSONObject(ATarget), TJSONObject(ASource), '')
    else
      for i := 0 to ASource.Count - 1 do
      begin
        k := IntToStr(i);
        if PlainObject(ASource.Items[i]) and PlainObject(TJSONObject(ATarget).Find(k)) then
          MergeObject(TJSONObject(TJSONObject(ATarget).Find(k)), TJSONObject(ASource.Items[i]), '')
        else
          TJSONObject(ATarget).Elements[k] := ASource.Items[i].Clone;
      end;
  end
  else if ASource.JSONType = jtArray then
  begin
    for i := 0 to ASource.Count - 1 do
      MergeArrayAt(TJSONArray(ATarget), i, ASource.Items[i]);
  end
  else
    for i := 0 to ASource.Count - 1 do
    begin
      k := TJSONObject(ASource).Names[i];
      if IsIndexKey(k) and (StrToQWord(k) < QWord(MaxInt)) then
        MergeArrayAt(TJSONArray(ATarget), StrToInt(k), ASource.Items[i]);
    end;
end;

{ ==================== mergeLayoutParam ==================== }

type
  { one of the six keys: whether the option object OWNS it, and its value
    (nil: undefined) }
  TBoxKey = record
    Own: Boolean;
    V: TJSONData;
  end;
  TBoxKeys = array[0..5] of TBoxKey;   // width left right height top bottom

  { the values the box merge borrows and owns for the length of one merge }
  TBoxPool = class
  private
    FItems: array of TJSONData;
  public
    destructor Destroy; override;
    function Keep(AData: TJSONData): TJSONData;
  end;

destructor TBoxPool.Destroy;
var i: Integer;
begin
  for i := 0 to High(FItems) do FItems[i].Free;
  inherited Destroy;
end;

function TBoxPool.Keep(AData: TJSONData): TJSONData;
begin
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := AData;
  Result := AData;
end;

{ `!= null && !== 'auto'` on an owned key }
function BoxHasValue(const K: TBoxKey): Boolean;
begin
  Result := K.Own and Given(K.V)
    and not ((K.V.JSONType = jtString) and (K.V.AsString = 'auto'));
end;

{ the box a model of this kind is laid out by, its ignoreSize per direction
  and the defaults its defaultOption merges under the written keys. False:
  no box the port merges. The values are the readers' own (Builder,
  Title, Legend, VisualMapView, Tree, Sankey, Treemap). }
function BoxOf(const AMainType, ASubType: string; APool: TBoxPool;
  out AIgnoreW, AIgnoreH: Boolean; out ADefaults: TBoxKeys): Boolean;

  procedure Def(AIndex: Integer; AData: TJSONData);
  begin
    ADefaults[AIndex].Own := True;
    ADefaults[AIndex].V := APool.Keep(AData);
  end;

var k: Integer;
begin
  Result := True;
  AIgnoreW := False;
  AIgnoreH := False;
  for k := 0 to 5 do ADefaults[k] := Default(TBoxKey);
  if AMainType = 'grid' then
  begin
    Def(1, TJSONString.Create('15%'));
    Def(2, TJSONString.Create('10%'));
    Def(4, TJSONIntegerNumber.Create(65));
    Def(5, TJSONIntegerNumber.Create(80));
  end
  else if AMainType = 'title' then
  begin
    AIgnoreW := True;
    AIgnoreH := True;
    Def(1, TJSONString.Create('center'));
    Def(4, TJSONIntegerNumber.Create(15));
  end
  else if AMainType = 'legend' then
  begin
    AIgnoreW := True;
    AIgnoreH := True;
    Def(1, TJSONString.Create('center'));
    Def(5, TJSONIntegerNumber.Create(15));
  end
  else if AMainType = 'visualMap' then
  begin
    AIgnoreW := True;
    AIgnoreH := True;
    Def(1, TJSONIntegerNumber.Create(0));
    Def(2, TJSONNull.Create);
    Def(4, TJSONNull.Create);
    Def(5, TJSONIntegerNumber.Create(0));
  end
  else if (AMainType = 'series') and (ASubType = 'tree') then
  begin
    Def(1, TJSONString.Create('12%'));
    Def(2, TJSONString.Create('12%'));
    Def(4, TJSONString.Create('12%'));
    Def(5, TJSONString.Create('12%'));
  end
  else if (AMainType = 'series') and (ASubType = 'sankey') then
  begin
    Def(1, TJSONString.Create('5%'));
    Def(2, TJSONString.Create('20%'));
    Def(4, TJSONString.Create('5%'));
    Def(5, TJSONString.Create('5%'));
  end
  else if (AMainType = 'series') and (ASubType = 'treemap') then
  begin
    Def(1, TJSONIntegerNumber.Create(20));
    Def(2, TJSONIntegerNumber.Create(20));
    Def(4, TJSONIntegerNumber.Create(50));
    Def(5, TJSONIntegerNumber.Create(50));
  end
  else
    Result := False;
end;

{ layout.ts mergeLayoutParam, one direction (ABase 0: width left right, 3:
  height top bottom); every key of the direction is owned afterwards }
procedure MergeBoxDirection(var ATarget: TBoxKeys; const ANew: TBoxKeys;
  ABase: Integer; AIgnore: Boolean; ANull: TJSONData);
var
  merged, params, res: array[0..2] of TBoxKey;
  k, newCount, mergedCount: Integer;
begin
  newCount := 0;
  mergedCount := 0;
  for k := 0 to 2 do
  begin
    merged[k] := ATarget[ABase + k];
    params[k] := Default(TBoxKey);
  end;
  for k := 0 to 2 do
  begin
    if ANew[ABase + k].Own then
    begin
      params[k] := ANew[ABase + k];
      merged[k] := ANew[ABase + k];
    end;
    if BoxHasValue(params[k]) then Inc(newCount);
    if BoxHasValue(merged[k]) then Inc(mergedCount);
  end;
  if AIgnore then
  begin
    { only one of left / right may exist }
    if BoxHasValue(ANew[ABase + 1]) then
    begin
      merged[2].Own := True;
      merged[2].V := ANull;
    end
    else if BoxHasValue(ANew[ABase + 2]) then
    begin
      merged[1].Own := True;
      merged[1].V := ANull;
    end;
    res := merged;
  end
  else if (mergedCount = 2) or (newCount = 0) then
    res := merged
  else if newCount >= 2 then
    res := params
  else
  begin
    { another one from the target, by priority }
    for k := 0 to 2 do
      if (not params[k].Own) and ATarget[ABase + k].Own then
      begin
        params[k] := ATarget[ABase + k];
        Break;
      end;
    res := params;
  end;
  { copy(): all three written, undefined where the result has none }
  for k := 0 to 2 do
  begin
    ATarget[ABase + k].Own := True;
    if res[k].Own then ATarget[ABase + k].V := res[k].V
    else ATarget[ABase + k].V := nil;
  end;
end;

{ the six keys an object owns, values cloned into APool when AClone (the
  node is about to be merged over) }
function OwnBox(AObj: TJSONObject; APool: TBoxPool; AClone: Boolean): TBoxKeys;
var
  k: Integer;
  d: TJSONData;
begin
  for k := 0 to 5 do
  begin
    Result[k] := Default(TBoxKey);
    d := AObj.Find(cBoxNames[k]);
    if d = nil then Continue;
    Result[k].Own := True;
    if AClone then Result[k].V := APool.Keep(d.Clone) else Result[k].V := d;
  end;
end;

{ ==================== keyInfo ==================== }

type
  TSlot = record
    HasExisting: Boolean;
    Existing: TTyOptionKey;
    ExNode: TJSONData;          // the existing model's node in the tree
    NewOpt: TJSONObject;        // borrowed from the new option
    Info: TTyOptionKey;         // keyInfo
    Brand: Boolean;             // brandNew: replaceMerge mapped it by index
  end;
  TSlotArray = array of TSlot;

function IdTaken(const AIds: TStringArray; const AId: string): Boolean;
begin
  Result := InList(AIds, AId);
end;

{ makeIdAndName (util/model.ts:449-534) }
procedure MakeIdAndName(var ASlots: TSlotArray);
var
  ids: TStringArray;
  i, n: Integer;
  d: TJSONData;
  cand: string;
begin
  ids := nil;
  for i := 0 to High(ASlots) do
    if ASlots[i].HasExisting then AddTo(ids, ASlots[i].Existing.Id);
  for i := 0 to High(ASlots) do
  begin
    if ASlots[i].NewOpt = nil then Continue;
    d := ASlots[i].NewOpt.Find('id');
    if Given(d) then AddTo(ids, ComparableKey(d));
  end;
  for i := 0 to High(ASlots) do
  begin
    if ASlots[i].NewOpt = nil then Continue;
    ASlots[i].Info := Default(TTyOptionKey);
    ASlots[i].Info.Exists := True;
    d := ASlots[i].NewOpt.Find('name');
    if Given(d) then ASlots[i].Info.Name := ComparableKey(d)
    else if ASlots[i].HasExisting then ASlots[i].Info.Name := ASlots[i].Existing.Name
    else ASlots[i].Info.Name := 'series' + #0 + IntToStr(i);
    d := ASlots[i].NewOpt.Find('id');
    if ASlots[i].HasExisting then ASlots[i].Info.Id := ASlots[i].Existing.Id
    else if Given(d) then ASlots[i].Info.Id := ComparableKey(d)
    else
    begin
      n := 0;
      repeat
        cand := #0 + ASlots[i].Info.Name + #0 + IntToStr(n);
        Inc(n);
      until not IdTaken(ids, cand);
      ASlots[i].Info.Id := cand;
    end;
    AddTo(ids, ASlots[i].Info.Id);
  end;
end;

{ the components a main type's value holds: an array's entries, a bare
  object as one; a non-object entry is nil }
function ComponentsOf(AValue: TJSONData): TNodeArray;
var i: Integer;
begin
  Result := nil;
  if AValue = nil then Exit;
  if AValue.JSONType = jtArray then
  begin
    SetLength(Result, AValue.Count);
    for i := 0 to AValue.Count - 1 do
      if AValue.Items[i].JSONType = jtObject then Result[i] := AValue.Items[i]
      else Result[i] := nil;
  end
  else if AValue.JSONType = jtObject then
  begin
    SetLength(Result, 1);
    Result[0] := AValue;
  end
  else if AValue.JSONType <> jtNull then
  begin
    { normalizeToArray(5) is [5], and 5 is no component }
    SetLength(Result, 1);
    Result[0] := nil;
  end;
end;

function TyOptionKeyIndex(const AKeys: TTyOptionKeys; const AMainType: string): Integer;
var i: Integer;
begin
  for i := 0 to High(AKeys) do
    if AKeys[i].MainType = AMainType then Exit(i);
  Result := -1;
end;

function TyMergeSlotsIndex(const AReport: TTyMergeReport; const AMainType: string): Integer;
var i: Integer;
begin
  for i := 0 to High(AReport.Slots) do
    if AReport.Slots[i].MainType = AMainType then Exit(i);
  Result := -1;
end;

procedure SetKeys(var AKeys: TTyOptionKeys; const AMainType: string;
  const AItems: TTyOptionKeyArray);
var i: Integer;
begin
  i := TyOptionKeyIndex(AKeys, AMainType);
  if i < 0 then
  begin
    i := Length(AKeys);
    SetLength(AKeys, i + 1);
    AKeys[i].MainType := AMainType;
  end;
  AKeys[i].Items := AItems;
end;

{ A PREPROCESSOR'S `{}` for AMainType: mapped by index, it takes slot 0 --
  merged into the model there (nothing changes) or, in a hole or an empty
  list, a new model with an id of its own. }
procedure EnsureFirstSlot(var AKeys: TTyOptionKeys; const AMainType: string);
var
  i, n: Integer;
  slots: TSlotArray;
  items: TTyOptionKeyArray;
  blank: TJSONObject;
begin
  i := TyOptionKeyIndex(AKeys, AMainType);
  if i < 0 then
  begin
    SetKeys(AKeys, AMainType, nil);
    i := TyOptionKeyIndex(AKeys, AMainType);
  end;
  items := AKeys[i].Items;
  if (Length(items) > 0) and items[0].Exists then Exit;
  { makeIdAndName over the list with the new option in slot 0 }
  slots := nil;
  SetLength(slots, Max(1, Length(items)));
  for n := 0 to High(slots) do
  begin
    slots[n] := Default(TSlot);
    if (n <= High(items)) and items[n].Exists then
    begin
      slots[n].HasExisting := True;
      slots[n].Existing := items[n];
    end;
  end;
  blank := TJSONObject.Create;
  try
    slots[0].NewOpt := blank;
    MakeIdAndName(slots);
    if Length(items) = 0 then SetLength(items, 1);
    items[0] := slots[0].Info;
    items[0].SubType := '';
  finally
    blank.Free;
  end;
  AKeys[i].Items := items;
end;

{ the preprocessors' models an option makes: `axisPointer: {}` unless it has
  one (an empty array is none), `grid: {}` with an xAxis and a yAxis and no
  grid }
procedure PreprocessorModels(AOption: TJSONObject; var AKeys: TTyOptionKeys);
var d: TJSONData;
begin
  if AOption = nil then Exit;
  d := AOption.Find('axisPointer');
  if (not Truthy(d)) or ((d.JSONType = jtArray) and (d.Count = 0)) then
    EnsureFirstSlot(AKeys, 'axisPointer');
  if Truthy(AOption.Find('xAxis')) and Truthy(AOption.Find('yAxis'))
    and not Truthy(AOption.Find('grid')) then
    EnsureFirstSlot(AKeys, 'grid');
end;

{ the subType a fresh model of this option takes }
function FreshSubType(const AMainType: string; ANew: TJSONObject): string;
begin
  if not WrittenType(ANew, Result) then Result := DefaultSubType(AMainType, ANew);
end;

procedure TyOptionKeysOfTree(ARoot: TJSONData; out AKeys: TTyOptionKeys);
var
  written, visited: TStringArray;
  i, j: Integer;
  k: string;
  d: TJSONData;
  comps: TNodeArray;
  slots: TSlotArray;
  items: TTyOptionKeyArray;
begin
  AKeys := nil;
  written := nil;
  if ARoot is TJSONObject then
    for i := 0 to ARoot.Count - 1 do
    begin
      k := TJSONObject(ARoot).Names[i];
      if TyOptionIsComponentType(k) and Given(ARoot.Items[i]) then AddTo(written, k);
    end;
  visited := TyOptionVisited(written);
  for k in visited do
  begin
    d := nil;
    if ARoot is TJSONObject then d := TJSONObject(ARoot).Find(k);
    comps := ComponentsOf(d);
    { replaceAll: one slot per entry, a hole where it is no object }
    slots := nil;
    SetLength(slots, Length(comps));
    for j := 0 to High(comps) do
    begin
      slots[j] := Default(TSlot);
      if comps[j] <> nil then slots[j].NewOpt := TJSONObject(comps[j]);
    end;
    MakeIdAndName(slots);
    items := nil;
    SetLength(items, Length(slots));
    for j := 0 to High(slots) do
    begin
      items[j] := Default(TTyOptionKey);
      if slots[j].NewOpt = nil then Continue;
      items[j] := slots[j].Info;
      items[j].SubType := FreshSubType(k, slots[j].NewOpt);
    end;
    SetKeys(AKeys, k, items);
  end;
  if ARoot is TJSONObject then PreprocessorModels(TJSONObject(ARoot), AKeys);
end;

{ ==================== the merge ==================== }

type
  TMapMode = (mmNormal, mmReplaceMerge, mmReplaceAll);

{ mappingToExists in one of its three modes }
function MapSlots(const AExisting: TTyOptionKeyArray; const AExNodes: TNodeArray;
  const ANew: TNodeArray; AMode: TMapMode): TSlotArray;
var
  opts: array of TJSONObject;
  i, j: Integer;
  d, nm: TJSONData;
  key: string;
  has: Boolean;
begin
  Result := nil;
  SetLength(opts, Length(ANew));
  for i := 0 to High(ANew) do
    if (ANew[i] <> nil) and (ANew[i].JSONType = jtObject) then opts[i] := TJSONObject(ANew[i])
    else opts[i] := nil;

  if AMode = mmReplaceAll then
  begin
    SetLength(Result, Length(opts));
    for i := 0 to High(opts) do
    begin
      Result[i] := Default(TSlot);
      Result[i].NewOpt := opts[i];
    end;
    MakeIdAndName(Result);
    Exit;
  end;

  { prepareResult: a slot per existing index, holes too -- and in
    replaceMerge none keeps its model until an id maps it back }
  SetLength(Result, Length(AExisting));
  for i := 0 to High(AExisting) do
  begin
    Result[i] := Default(TSlot);
    Result[i].HasExisting := AExisting[i].Exists and (AMode = mmNormal);
    if Result[i].HasExisting then
    begin
      Result[i].Existing := AExisting[i];
      if i <= High(AExNodes) then Result[i].ExNode := AExNodes[i];
    end;
  end;

  { by id: in both modes the option merges into the model of its id }
  for i := 0 to High(opts) do
  begin
    if opts[i] = nil then Continue;
    d := opts[i].Find('id');
    if not Given(d) then Continue;
    key := ComparableKey(d);
    for j := 0 to High(AExisting) do
      if AExisting[j].Exists and (AExisting[j].Id = key) then
      begin
        Result[j].NewOpt := opts[i];
        Result[j].HasExisting := True;
        Result[j].Existing := AExisting[j];
        if j <= High(AExNodes) then Result[j].ExNode := AExNodes[j];
        opts[i] := nil;
        Break;
      end;
  end;

  { by name: only an option without an id, onto the first unmapped model
    of that name -- normalMerge only }
  if AMode = mmNormal then
  for i := 0 to High(opts) do
  begin
    if opts[i] = nil then Continue;
    nm := opts[i].Find('name');
    if not Given(nm) then Continue;
    if Given(opts[i].Find('id')) then Continue;
    key := IdNameKey(nm, has);
    if not has then Continue;
    for j := 0 to High(Result) do
      if (Result[j].NewOpt = nil) and Result[j].HasExisting
        and (Result[j].Existing.Name = key) then
      begin
        Result[j].NewOpt := opts[i];
        opts[i] := nil;
        Break;
      end;
  end;

  { by index: the first slot from 0 with no option yet -- a hole is one --
    skipping a model whose id differs from the option's. In replaceMerge
    every slot no id took is free, and what lands is brand new. }
  for i := 0 to High(opts) do
  begin
    if opts[i] = nil then Continue;
    d := opts[i].Find('id');
    j := 0;
    while (j <= High(Result))
      and ((Result[j].NewOpt <> nil)
        or (Result[j].HasExisting and Given(d)
          and not ((IdNameKey(d, has) = Result[j].Existing.Id) and has))) do
      Inc(j);
    if j > High(Result) then
    begin
      SetLength(Result, j + 1);
      Result[j] := Default(TSlot);
    end;
    Result[j].NewOpt := opts[i];
    Result[j].Brand := AMode = mmReplaceMerge;
  end;

  MakeIdAndName(Result);
end;

{ two of the new option's components on one id: upstream asserts }
function DuplicateId(const ANew: TNodeArray; out AId: string): Boolean;
var
  ids: TStringArray;
  i: Integer;
  d: TJSONData;
  k: string;
begin
  Result := False;
  ids := nil;
  for i := 0 to High(ANew) do
  begin
    if (ANew[i] = nil) or (ANew[i].JSONType <> jtObject) then Continue;
    d := TJSONObject(ANew[i]).Find('id');
    if not Given(d) then Continue;
    k := ComparableKey(d);
    if InList(ids, k) then
    begin
      AId := k;
      Exit(True);
    end;
    AddTo(ids, k);
  end;
end;

{ DataZoomModel._doInit after a merge: a pair whose mode is 'value' has its
  percent set to null -- the value written alone, or rangeMode saying so
  when both or neither were written }
procedure DataZoomRangeModes(ANode, ANew: TJSONObject);
const
  cPct: array[0..1] of string = ('start', 'end');
  cVal: array[0..1] of string = ('startValue', 'endValue');
var
  k: Integer;
  p, v, valueMode: Boolean;
  rm, it: TJSONData;
begin
  for k := 0 to 1 do
  begin
    p := Given(ANew.Find(cPct[k]));
    v := Given(ANew.Find(cVal[k]));
    if p and not v then Continue;
    if v and not p then valueMode := True
    else
    begin
      valueMode := False;
      rm := ANode.Find('rangeMode');
      if Truthy(rm) and (rm.JSONType = jtArray) and (k < rm.Count) then
      begin
        it := rm.Items[k];
        valueMode := (it.JSONType = jtString) and (it.AsString = 'value');
      end;
    end;
    if valueMode then ANode.Elements[cPct[k]] := TJSONNull.Create;
  end;
end;

{ merge ANew into the existing model's node: zrender's merge, then the
  model's own mergeOption rules }
procedure MergeComponent(const AMainType, ASubType: string; ANode, ANew: TJSONObject;
  APool: TBoxPool);
var
  ignW, ignH, touched: Boolean;
  defs, own, f, g, nk: TBoxKeys;
  k, dir: Integer;
  nul: TJSONData;
begin
  { the box, as upstream's full option holds it now: the init merge of the
    node's own keys over the defaults -- every key owned after it }
  touched := False;
  if BoxOf(AMainType, ASubType, APool, ignW, ignH, defs) then
  begin
    nk := OwnBox(ANew, APool, False);
    for k := 0 to 5 do if nk[k].Own then touched := True;
  end;
  if touched then
  begin
    nul := APool.Keep(TJSONNull.Create);
    own := OwnBox(ANode, APool, True);
    f := defs;
    for k := 0 to 5 do if own[k].Own then f[k] := own[k];
    MergeBoxDirection(f, own, 0, ignW, nul);
    MergeBoxDirection(f, own, 3, ignH, nul);
  end;

  if AMainType = 'dataset' then MergeObject(ANode, ANew, 'transform')
  else MergeObject(ANode, ANew, '');

  if touched then
  begin
    { the merge: the full box overlaid by the new option's own keys, then
      mergeLayoutParam against the new option; the directions it touched
      are written whole }
    g := f;
    for k := 0 to 5 do if nk[k].Own then g[k] := nk[k];
    { A SERIES MERGES ITS BOX AGAINST ITSELF: SeriesModel.mergeOption hands
      mergeLayoutParam merge()'s return, which is this.option, as the new
      option -- every key owned, so nothing is dropped and the box is just
      the deep merge (Series.ts:302-311) }
    if AMainType <> 'series' then
    begin
      MergeBoxDirection(g, nk, 0, ignW, nul);
      MergeBoxDirection(g, nk, 3, ignH, nul);
    end;
    for dir := 0 to 1 do
    begin
      if not (nk[dir * 3].Own or nk[dir * 3 + 1].Own or nk[dir * 3 + 2].Own) then Continue;
      for k := dir * 3 to dir * 3 + 2 do
        if g[k].V = nil then ANode.Elements[cBoxNames[k]] := TJSONNull.Create
        else ANode.Elements[cBoxNames[k]] := g[k].V.Clone;
    end;
  end;

  if AMainType = 'dataZoom' then DataZoomRangeModes(ANode, ANew);
end;

function TyMergeHasModel(AFate: TTyMergeFate): Boolean;
begin
  Result := AFate in [mfKept, mfMerged, mfNew];
end;

function TyOptionBadReplaceType(const AReplaceMerge: array of string): string;
var i: Integer;
begin
  for i := 0 to High(AReplaceMerge) do
    if not TyOptionIsComponentType(AReplaceMerge[i]) then Exit(AReplaceMerge[i]);
  Result := '';
end;

procedure TyOptionCompactSeries(ARoot: TJSONData);
var
  d: TJSONData;
  i: Integer;
begin
  if not (ARoot is TJSONObject) then Exit;
  d := TJSONObject(ARoot).Find('series');
  if d = nil then Exit;
  case d.JSONType of
    jtNull, jtObject: ;
    jtArray:
      for i := d.Count - 1 downto 0 do
        if d.Items[i].JSONType <> jtObject then TJSONArray(d).Delete(i);
  else
    TJSONObject(ARoot).Elements['series'] := TJSONArray.Create;
  end;
end;

function TyOptionMerge(ARoot: TJSONObject; var AKeys: TTyOptionKeys;
  ANew: TJSONObject; ABefore: TTyMergeBeforeComponent;
  out AReport: TTyMergeReport; out AError: string): Boolean;
begin
  Result := TyOptionMerge(ARoot, AKeys, ANew, [], ABefore, AReport, AError);
end;

function TyOptionMerge(ARoot: TJSONObject; var AKeys: TTyOptionKeys;
  ANew: TJSONObject; const AReplaceMerge: array of string;
  ABefore: TTyMergeBeforeComponent;
  out AReport: TTyMergeReport; out AError: string): Boolean;
begin
  Result := TyOptionMerge(ARoot, AKeys, ANew, AReplaceMerge, True, ABefore,
    AReport, AError);
end;

function TyOptionHasDuplicateId(ANew: TJSONObject): Boolean;
var
  i: Integer;
  k, dupId: string;
begin
  Result := False;
  if ANew = nil then Exit;
  for i := 0 to ANew.Count - 1 do
  begin
    k := ANew.Names[i];
    if TyOptionIsComponentType(k) and Given(ANew.Items[i])
      and DuplicateId(ComponentsOf(ANew.Items[i]), dupId) then Exit(True);
  end;
end;

function TyOptionMerge(ARoot: TJSONObject; var AKeys: TTyOptionKeys;
  ANew: TJSONObject; const AReplaceMerge: array of string; APreprocessed: Boolean;
  ABefore: TTyMergeBeforeComponent;
  out AReport: TTyMergeReport; out AError: string): Boolean;
var
  i, j, ki, si: Integer;
  k, mt, sub, dupId: string;
  v, old, oldVal: TJSONData;
  written, visited: TStringArray;
  newComps, exNodes: TNodeArray;
  existing, items: TTyOptionKeyArray;
  slots: TSlotArray;
  wasBare, newBare, sameClass, writeTree, replacing: Boolean;
  mode: TMapMode;
  pool: TBoxPool;
  arr: TJSONArray;
  node: TJSONData;
  fates: TTyMergeFateArray;
  opts: TTyMergeOptArray;
  brands: TTyMergeBoolArray;
  reused, virt: array of Boolean;
  exObj: TJSONObject;
  replace: TStringArray;
begin
  AReport := Default(TTyMergeReport);
  AError := '';
  Result := False;

  { normalizeSetOptionInput asserts every name is a component main type }
  k := TyOptionBadReplaceType(AReplaceMerge);
  if k <> '' then
  begin
    AError := Format(rsTyOptReplaceMergeBadType, [k]);
    Exit;
  end;
  replace := nil;
  for i := 0 to High(AReplaceMerge) do AddTo(replace, AReplaceMerge[i]);

  written := nil;
  for i := 0 to ANew.Count - 1 do
  begin
    k := ANew.Names[i];
    if TyOptionIsComponentType(k) and Given(ANew.Items[i]) then AddTo(written, k);
  end;
  { A REPLACEMERGE TYPE THE OPTION LEAVES OUT is merged as `{xxx: []}`:
    every model of it goes }
  for k in replace do AddTo(written, k);
  { THE ASSERT FIRST, so a refused merge changes nothing }
  for k in written do
    if DuplicateId(ComponentsOf(ANew.Find(k)), dupId) then
    begin
      AError := Format(rsTyOptDuplicateId, [k, StringReplace(dupId, #0, '\0', [rfReplaceAll])]);
      Exit;
    end;

  { ---- the root keys that are no component ---- }
  for i := 0 to ANew.Count - 1 do
  begin
    k := ANew.Names[i];
    v := ANew.Items[i];
    if TyOptionIsComponentType(k) or not Given(v) then Continue;
    old := ARoot.Find(k);
    if not Given(old) then ARoot.Elements[k] := v.Clone
    else
    begin
      node := MergeRootValue(old, v);
      if node <> old then ARoot.Elements[k] := node;
    end;
  end;

  { ---- the components ---- }
  visited := VisitedOf(written, APreprocessed);
  AReport.Visited := visited;
  pool := TBoxPool.Create;
  try
    for mt in cMainTypes do
    begin
      if not InList(visited, mt) then Continue;
      ki := TyOptionKeyIndex(AKeys, mt);
      replacing := InList(replace, mt);
      { no list yet is init's replaceAll; then replaceMerge where named }
      if ki < 0 then mode := mmReplaceAll
      else if replacing then mode := mmReplaceMerge
      else mode := mmNormal;
      if ki < 0 then existing := nil else existing := AKeys[ki].Items;
      oldVal := ARoot.Find(mt);
      exNodes := ComponentsOf(oldVal);
      newComps := ComponentsOf(ANew.Find(mt));
      slots := MapSlots(existing, exNodes, newComps, mode);

      SetLength(fates, Length(slots));
      SetLength(opts, Length(slots));
      SetLength(items, Length(slots));
      SetLength(reused, Length(slots));
      SetLength(virt, Length(slots));
      SetLength(brands, Length(slots));
      for j := 0 to High(slots) do
      begin
        opts[j] := slots[j].NewOpt;
        reused[j] := False;
        brands[j] := False;
        { A MODEL THE TREE HAS NO NODE FOR -- a preprocessor's: its node is
          made, empty, when anything needs it }
        virt[j] := slots[j].HasExisting and (slots[j].ExNode = nil);
        if slots[j].NewOpt = nil then
        begin
          if slots[j].HasExisting then
          begin
            fates[j] := mfKept;
            items[j] := slots[j].Existing;
            reused[j] := True;
          end
          else
          begin
            { a model replaceMerge did not map by id goes; an older hole
              stays one }
            if (j <= High(existing)) and existing[j].Exists then fates[j] := mfRemoved
            else fates[j] := mfHole;
            items[j] := Default(TTyOptionKey);
          end;
          Continue;
        end;
        if not WrittenType(slots[j].NewOpt, sub) then
        begin
          if slots[j].HasExisting then sub := slots[j].Existing.SubType
          else sub := DefaultSubType(mt, slots[j].NewOpt);
        end;
        exObj := nil;
        if virt[j] then exObj := TJSONObject.Create
        else if slots[j].ExNode is TJSONObject then exObj := TJSONObject(slots[j].ExNode);
        sameClass := slots[j].HasExisting and (exObj <> nil)
          and (ClassOf(mt, sub) = ClassOf(mt, slots[j].Existing.SubType));
        if virt[j] then
        begin
          if sameClass then slots[j].ExNode := exObj
          else
          begin
            exObj.Free;
            virt[j] := False;
          end;
        end;
        if sameClass then
        begin
          { componentModel.name = keyInfo.name; mergeOption }
          if Assigned(ABefore) then
            ABefore(mt, j, TJSONObject(slots[j].ExNode), slots[j].NewOpt);
          MergeComponent(mt, slots[j].Existing.SubType, TJSONObject(slots[j].ExNode),
            slots[j].NewOpt, pool);
          fates[j] := mfMerged;
          items[j] := slots[j].Existing;
          items[j].Name := slots[j].Info.Name;
          reused[j] := True;
        end
        else
        begin
          { a new model, from the new option alone, in the slot's id }
          fates[j] := mfNew;
          items[j] := slots[j].Info;
          items[j].SubType := sub;
          brands[j] := slots[j].Brand;
        end;
      end;

      { ---- the tree: only where the author wrote this main type ---- }
      wasBare := oldVal is TJSONObject;
      newBare := (oldVal = nil) and (ANew.Find(mt) is TJSONObject);
      writeTree := Given(ANew.Find(mt)) or (oldVal <> nil) or replacing;
      if writeTree and (Length(slots) = 1) and (wasBare or newBare)
        and TyMergeHasModel(fates[0]) then
      begin
        { still one component, written bare: kept bare, merged in place }
        if fates[0] = mfNew then ARoot.Elements[mt] := slots[0].NewOpt.Clone
        else if virt[0] then
        begin
          if slots[0].ExNode = nil then slots[0].ExNode := TJSONObject.Create;
          ARoot.Elements[mt] := slots[0].ExNode;
        end;
      end
      else if writeTree then
      begin
        arr := TJSONArray.Create;
        for j := 0 to High(slots) do
        begin
          if reused[j] and virt[j] then
          begin
            if slots[j].ExNode = nil then slots[j].ExNode := TJSONObject.Create;
            arr.Add(slots[j].ExNode);
          end
          else if reused[j] then
          begin
            { detached from the old value before it goes }
            if oldVal is TJSONArray then TJSONArray(oldVal).Extract(slots[j].ExNode)
            else ARoot.Extract(mt);
            arr.Add(slots[j].ExNode);
          end
          else if fates[j] = mfNew then arr.Add(slots[j].NewOpt.Clone)
          else arr.Add(TJSONNull.Create);
        end;
        if ARoot.Find(mt) <> nil then ARoot.Elements[mt] := arr
        else ARoot.Add(mt, arr);
      end;

      SetKeys(AKeys, mt, items);
      si := Length(AReport.Slots);
      SetLength(AReport.Slots, si + 1);
      AReport.Slots[si].MainType := mt;
      AReport.Slots[si].Fate := Copy(fates);
      AReport.Slots[si].NewOpt := Copy(opts);
      AReport.Slots[si].Brand := Copy(brands);
    end;
  finally
    pool.Free;
  end;
  if APreprocessed then PreprocessorModels(ANew, AKeys);
  Result := True;
end;

{ ==================== getOption's shape ==================== }

procedure WriteValue(AData: TJSONData; var AOut: string);
var
  i: Integer;
  keys: TStringArray;
  v: Double;
begin
  case AData.JSONType of
    jtNull: AOut := AOut + 'null';
    jtBoolean: if AData.AsBoolean then AOut := AOut + 'true' else AOut := AOut + 'false';
    jtNumber:
      begin
        if (AData is TJSONIntegerNumber) or (AData is TJSONInt64Number) then
          AOut := AOut + JsNumText(AData)
        else
        begin
          v := AData.AsFloat;
          if IsNan(v) or IsInfinite(v) then AOut := AOut + 'null'
          else AOut := AOut + TyJsNumberToString(v);
        end;
      end;
    jtString: AOut := AOut + TyJsonQuote(AData.AsString);
    jtArray:
      begin
        AOut := AOut + '[';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then AOut := AOut + ',';
          WriteValue(AData.Items[i], AOut);
        end;
        AOut := AOut + ']';
      end;
    jtObject:
      begin
        keys := TyJsOrderedKeys(TJSONObject(AData));
        AOut := AOut + '{';
        for i := 0 to High(keys) do
        begin
          if i > 0 then AOut := AOut + ',';
          AOut := AOut + TyJsonQuote(keys[i]) + ':';
          WriteValue(TJSONObject(AData).Find(keys[i]), AOut);
        end;
        AOut := AOut + '}';
      end;
  else
    AOut := AOut + 'null';
  end;
end;

function TyOptionToJson(ARoot: TJSONData): string;
var
  i, j, n: Integer;
  k: string;
  v: TJSONData;
  comps: TNodeArray;
  first: Boolean;
begin
  if not (ARoot is TJSONObject) then Exit('{}');
  Result := '{';
  first := True;
  for i := 0 to ARoot.Count - 1 do
  begin
    k := TJSONObject(ARoot).Names[i];
    v := ARoot.Items[i];
    if not Given(v) then Continue;
    if not first then Result := Result + ',';
    first := False;
    Result := Result + TyJsonQuote(k) + ':';
    if not TyOptionIsComponentType(k) then
    begin
      WriteValue(v, Result);
      Continue;
    end;
    comps := ComponentsOf(v);
    n := Length(comps);
    while (n > 0) and (comps[n - 1] = nil) do Dec(n);
    Result := Result + '[';
    for j := 0 to n - 1 do
    begin
      if j > 0 then Result := Result + ',';
      if comps[j] = nil then Result := Result + 'null'
      else WriteValue(comps[j], Result);
    end;
    Result := Result + ']';
  end;
  Result := Result + '}';
end;

end.
