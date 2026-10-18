unit tyControls.AdvChart.Graphic;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- THE GRAPHIC COMPONENT: free elements over the chart.
  [Batch 122, C13]

  Three parts, each upstream's:

    THE PREPROCESSOR (component/graphic/install.ts): `graphic` as a bare
      element, an array of elements or an array of objects with `elements`
      becomes one such component; of several components only the first
      stays.

    THE MODEL (GraphicModel.ts): the element options flattened -- a group's
      children after it, each with its parentId -- mapped onto the list
      already there by id, name and index (mappingToExists, normalMerge,
      makeIdAndName's ids), and $action applied: merge (zrUtil.merge, then
      mergeLayoutParam with ignoreSize, the layout and the transition keys
      copied back), replace, remove. The new options are what the view
      updates from; the list is what it places from (and getOption shows).

    THE VIEW (GraphicView.ts): the elements by id (AdvChart.GfxEl), each
      update applied the way applyUpdateTransition applies it -- the final
      props set, then the enter transition from enterFrom or the update
      transition from the old values of what `transition` names -- the
      textContent attached, the ec4 style converted, z / zlevel / z2 /
      cursor / handlers / draggable / name, ECData's eventData; then every
      element placed bottom-up by positionElement against the chart or its
      parent group's size, `bounding` 'all' or 'raw'. A removed element
      runs its leaveTo with the UPDATE timing (customGraphicTransition's
      applyLeaveTransition asks for 'update') and is detached when done.

  KEYFRAME ANIMATIONS [Batch 139, D6] (customGraphicKeyframeAnimation.ts):
  an element's `keyframeAnimation` -- one object or an array of them -- runs
  after its update; an element updated again first has its keyframe
  animations stopped and what they saved put back. TyGfxApplyKeyframes and
  TyGfxStopKeyframes are shared with the custom series. `extra`, the free
  object beside the shape, is set, transitions, enters and leaves the way
  the shape does.

  What upstream throws on -- a type with no class (`compoundPath`, `path`,
  an unknown word), a parent that is gone -- stops the update where it is,
  as the throw does, and Error says why; nothing is raised.

  PURE: SysUtils, Classes, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvChart.Types,
  tyControls.AdvChart.Anim, tyControls.AdvChart.GfxEl;

{ install.ts' preprocessor, on one option (the base, a media unit) }
procedure TyGraphicPreprocess(AOption: TJSONObject);

type
  { GraphicComponentModel: the list, and the options the next render
    updates from }
  TTyGfxModel = class
  private
    FElements: TJSONArray;
    FToUpdate: TJSONArray;
    FParents: array of Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { optionUpdated: ANewElements the new option's `elements` (on init the
      merged option's) }
    procedure OptionUpdated(ANewElements: TJSONData; AIsInit: Boolean);
    { useElOptionsToUpdate: the pending options, handed over (nil: none) }
    function UseToUpdate: TJSONArray;
    function HasPending: Boolean;
    { option.elements as it stands (owned by the model) }
    property Elements: TJSONArray read FElements;
  end;

  { the animation a graphic model resolves to: its own option over the
    root's over globalDefault }
  TTyGfxAnimSettings = record
    Enabled: Boolean;
    Duration, Delay, DurationUpdate, DelayUpdate: Double;
    Easing, EasingUpdate: string;
  end;

  TTyGfxView = class
  private
    FRoot: TTyGfxEl;
    FMap: TStringList;
    FLast: TTyGfxModel;
    FHasLast: Boolean;
    FGone: TFPList;
    FAnimation: TTyAnimation;
    FAnim: TTyGfxAnimSettings;
    FError: string;
    function CreateEl(const AId: string; AParent: TTyGfxEl; const AType: string): TTyGfxEl;
    procedure RemoveEl(AEl: TTyGfxEl; AOpt: TJSONObject);
    procedure ApplyLeave(AEl: TTyGfxEl; AOpt: TJSONObject);
    procedure ApplyUpdateTransition(AEl: TTyGfxEl; AOpt: TJSONObject; AIsInit: Boolean);
    procedure UpdateCommonAttrs(AEl: TTyGfxEl; AOpt: TJSONObject; AZ, AZLevel: Double);
    function ElementCfg(const AType: string; AOpt: TJSONObject): TTyAnimCfg;
    procedure UpdateProps(AEl: TTyGfxEl; const AProps: TTyAnimProps);
    function UpdateElements(AModel: TTyGfxModel; AZ, AZLevel: Double): Boolean;
    procedure Relocate(AModel: TTyGfxModel; AW, AH: Double;
      const AMeasurer: ITyTextMeasurer);
  public
    constructor Create;
    destructor Destroy; override;
    { render: a new model clears the old one's elements (with their leave
      transitions); the pending options update; everything is placed.
      AZ / AZLevel: the component's own z / zlevel (NaN: none). }
    procedure Render(AModel: TTyGfxModel; AW, AH: Double;
      const AMeasurer: ITyTextMeasurer; const AAnim: TTyGfxAnimSettings;
      AZ, AZLevel: Double);
    { the placement alone (a resize, a full update with nothing pending) }
    procedure Place(AW, AH: Double; const AMeasurer: ITyTextMeasurer);
    { every element removed, with its leave transition }
    procedure Clear;
    { a new model is coming: the next render clears this one's elements
      (the old model may be freed now) }
    procedure ForgetModel;
    { every animation at its last frame, the leaving elements gone -- an
      animation switched off }
    procedure Snap;
    function Find(const AId: string): TTyGfxEl;
    { the transforms and the textContents' places, before a paint }
    procedure Prepare(const AMeasurer: ITyTextMeasurer; const AGround: TTyGfxGround);
    { the elements whose leave transition ended, freed }
    procedure FreeGone;
    property Root: TTyGfxEl read FRoot;
    property Animation: TTyAnimation read FAnimation write FAnimation;
    property Error: string read FError;
    property Model: TTyGfxModel read FLast;
  end;

{ convertOptionIdName(x, null): a string, a number as JavaScript prints it,
  else '' (AHas False) }
function TyGfxIdOf(AData: TJSONData; out AHas: Boolean): string;

{ the element ids as the oracle writes them: \0 as '~' }
function TyGfxIdText(const AId: string): string;

{ ---- shared with the custom series [Batch 123, C14] ---- }

{ applyPropsDirectly and applyMiscProps (customGraphicTransition.ts): the
  final props set at once -- the style (with AClearStyle, the custom
  series' clearStyle, the element's style replaced: useStyle({}) before
  setStyle), the legacy position / scale / origin arrays, every transform
  prop the option gives a value, the shape (setShape); silent, ignore and
  (not on a group) invisible where the option has the key. No animation. }
procedure TyGfxApplyDirect(AEl: TTyGfxEl; AOpt: TJSONObject; AClearStyle: Boolean);

{ isEC4CompatibleStyle (util/styleCompat.ts): `legacy: true`, or -- legacy
  not false -- no textConfig, no textContent, not a tspan and a text element
  or a style with a `text` }
function TyGfxIsEC4(AStyle: TJSONObject; const AType: string;
  AHasCfg, AHasContent: Boolean): Boolean;

{ convertFromEC4CompatibleStyle: a text's own style renamed in place (no
  config, no content); any other type's makes a silent textContent and a
  textConfig -- its position the style's textPosition, else (AIsNormal) 
  'inside'. AConfig / AContent are the caller's to free (nil when none). }
procedure TyGfxConvertEC4(AStyle: TJSONObject; const AType: string;
  AIsNormal: Boolean; out AConfig, AContent: TJSONObject);

{ ---- the transitions, shared with the custom series [Batch 124, C15] ---- }

{ applyUpdateTransition's FROM props for an update
  (prepareTransformTransitionFrom, prepareShapeOrExtraTransitionFrom on the
  shape and on extra, prepareStyleTransitionFrom): the element's values NOW
  of what the option's transitions name -- `transition` 'all' every
  transform prop, a list (or one word) its own keys, the words 'shape',
  'extra' and 'style' the option's numeric shape / extra keys and
  animatable style keys, the shape's, extra's and the style's own
  `transition` their keys -- appended to AFrom. Call it before the final
  props are set. [Batch 139: extra] }
procedure TyGfxTransitionFrom(AEl: TTyGfxEl; AOpt: TJSONObject; var AFrom: TTyAnimProps);
{ the root's, the style's, the shape's and extra's enterFrom, flattened,
  appended to AEnter }
procedure TyGfxEnterFrom(AOpt: TJSONObject; var AEnter: TTyAnimProps);
{ updateLeaveTo: the root's, the style's, the shape's and extra's leaveTo
  merged into what the element keeps for its leave (HasLeaveTo,
  LeaveToProps) }
procedure TyGfxUpdateLeaveTo(AEl: TTyGfxEl; AOpt: TJSONObject);

{ ---- keyframe animations, shared with the custom series [Batch 139, D6] ---- }

{ stopPreviousKeyframeAnimationAndRestore: the element's 'keyframe'
  animators stopped where they are, then every value a keyframe animation
  ever saved on it put back (attr) }
procedure TyGfxStopKeyframes(AEl: TTyGfxEl);
{ applyKeyframeAnimation: AOpt is the option's `keyframeAnimation` -- an
  object, or an array of them applied in turn. Nothing when AEnabled is
  False (the model does not animate, or the element has no driver) or AOpt
  is falsy. `duration` (null: ADefaultDuration, the model's enter duration)
  and `keyframes` must be truthy. The keyframes are sorted by `percent`
  (stably); for '' (the element: every key but percent, easing, shape,
  style and extra), 'style', 'shape' and 'extra' -- each the element has --
  one animator, Element.animate(name, loop, allowDiscrete), scoped
  'keyframe': per keyframe the other animators of the same target stop
  their tracks on its keys, the element's values of those keys are saved
  for TyGfxStopKeyframes, and the keyframe goes in at duration x percent
  with its own easing; then the delay (`|| 0`), the duration and the
  clip's easing, and it starts. }
procedure TyGfxApplyKeyframes(AEl: TTyGfxEl; AOpt: TJSONData; AEnabled: Boolean;
  ADefaultDuration: Double);

implementation

uses
  tyControls.AdvChart.Scale, tyControls.AdvChart.Layout;

const
  cLocation: array[0..5] of string = ('left', 'right', 'top', 'bottom', 'width', 'height');
  cTransformable: array[0..10] of string = ('x', 'y', 'originX', 'originY',
    'anchorX', 'anchorY', 'rotation', 'scaleX', 'scaleY', 'skewX', 'skewY');
  cPathAnimStyle: array[0..12] of string = ('fill', 'stroke', 'strokePercent',
    'fillOpacity', 'strokeOpacity', 'lineDashOffset', 'lineWidth', 'miterLimit',
    'shadowBlur', 'shadowOffsetX', 'shadowOffsetY', 'shadowColor', 'opacity');
  cTextAnimStyle: array[0..22] of string = ('fill', 'stroke', 'fillOpacity',
    'strokeOpacity', 'lineWidth', 'fontSize', 'lineHeight', 'width', 'height',
    'textShadowColor', 'textShadowBlur', 'textShadowOffsetX', 'textShadowOffsetY',
    'backgroundColor', 'padding', 'borderColor', 'borderWidth', 'borderRadius',
    'shadowBlur', 'shadowOffsetX', 'shadowOffsetY', 'shadowColor', 'opacity');
  cImageAnimStyle: array[0..12] of string = ('x', 'y', 'width', 'height', 'sx',
    'sy', 'sWidth', 'sHeight', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY',
    'shadowColor', 'opacity');

{ ==================== JSON ==================== }

function JNull(A: TJSONData): Boolean; inline;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

function StrOf(A: TJSONData): string;
begin
  if (A <> nil) and (A.JSONType = jtString) then Result := A.AsString
  else Result := '';
end;

{ JavaScript truthiness }
function Truthy(A: TJSONData): Boolean;
var v: Double;
begin
  if A = nil then Exit(False);
  case A.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := A.AsBoolean;
    jtNumber:
      begin
        v := A.AsFloat;
        Result := (v <> 0) and not IsNan(v);
      end;
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

function ObjOf(AObj: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if AObj = nil then Exit;
  d := AObj.Find(AKey);
  if d is TJSONObject then Result := TJSONObject(d);
end;

procedure PutKey(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
var i: Integer;
begin
  i := AObj.IndexOfName(AKey);
  if i >= 0 then AObj.Items[i] := AValue
  else AObj.Add(AKey, AValue);
end;

procedure DropKey(AObj: TJSONObject; const AKey: string);
var i: Integer;
begin
  i := AObj.IndexOfName(AKey);
  if i >= 0 then AObj.Delete(i);
end;

function JsNumOf(A: TJSONData): Double;
var fs: TFormatSettings; s: string;
begin
  if A = nil then Exit(NaN);
  case A.JSONType of
    jtNumber: Result := A.AsFloat;
    jtBoolean: if A.AsBoolean then Result := 1 else Result := 0;
    jtNull: Result := 0;
    jtString:
      begin
        fs := DefaultFormatSettings;
        fs.DecimalSeparator := '.';
        s := Trim(A.AsString);
        if s = '' then Result := 0
        else if not TryStrToFloat(s, Result, fs) then Result := NaN;
      end;
  else
    Result := NaN;
  end;
end;

function TyGfxIdOf(AData: TJSONData; out AHas: Boolean): string;
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
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
  else
    AHas := False;
  end;
end;

function TyGfxIdText(const AId: string): string;
begin
  Result := StringReplace(AId, #0, '~', [rfReplaceAll]);
end;

{ ==================== the preprocessor ==================== }

procedure TyGraphicPreprocess(AOption: TJSONObject);
var
  g, first: TJSONData;
  wrap, comp: TJSONObject;
  arr: TJSONArray;
  i: Integer;
begin
  if AOption = nil then Exit;
  i := AOption.IndexOfName('graphic');
  if i < 0 then Exit;
  g := AOption.Items[i];
  if g is TJSONArray then
  begin
    first := nil;
    if g.Count > 0 then first := g.Items[0];
    if not Truthy(first) or not (first is TJSONObject)
      or not Truthy(TJSONObject(first).Find('elements')) then
    begin
      { one component whose elements are the array }
      comp := TJSONObject.Create;
      comp.Add('elements', g.Clone);
      arr := TJSONArray.Create;
      arr.Add(comp);
      AOption.Items[i] := arr;
    end
    else
    begin
      { only one instance: the first }
      arr := TJSONArray.Create;
      arr.Add(first.Clone);
      AOption.Items[i] := arr;
    end;
  end
  else if Truthy(g) and (g is TJSONObject) and not Truthy(TJSONObject(g).Find('elements')) then
  begin
    wrap := TJSONObject.Create;
    arr := TJSONArray.Create;
    arr.Add(g.Clone);
    wrap.Add('elements', arr);
    arr := TJSONArray.Create;
    arr.Add(wrap);
    AOption.Items[i] := arr;
  end;
end;

{ ==================== the model ==================== }

constructor TTyGfxModel.Create;
begin
  inherited Create;
  FElements := TJSONArray.Create;
end;

destructor TTyGfxModel.Destroy;
begin
  FreeAndNil(FElements);
  FreeAndNil(FToUpdate);
  inherited Destroy;
end;

function TTyGfxModel.UseToUpdate: TJSONArray;
begin
  Result := FToUpdate;
  FToUpdate := nil;
end;

function TTyGfxModel.HasPending: Boolean;
begin
  Result := FToUpdate <> nil;
end;

type
  TMapItem = record
    Existing: TJSONObject;     // the list's entry, or nil
    NewIdx: Integer;           // into the flattened list, -1 none
    Id, Name: string;
    HasName: Boolean;
  end;
  TMapItemArray = array of TMapItem;

function HasValue(AObj: TJSONObject; const AKey: string): Boolean;
var d: TJSONData;
begin
  d := AObj.Find(AKey);
  Result := not JNull(d) and not ((d.JSONType = jtString) and (d.AsString = 'auto'));
end;

{ isSetLoc }
function IsSetLoc(AObj: TJSONObject; const A, B: string): Boolean;
begin
  Result := HasValue(AObj, A) or HasValue(AObj, B);
end;

{ mergeLayoutParam(target, new) with ignoreSize, for one dimension }
procedure MergeLayoutDim(ATarget, ANew: TJSONObject; const ANames: array of string);
begin
  { the size is ignored: only one of the two sides may stay }
  if HasValue(ANew, ANames[1]) then PutKey(ATarget, ANames[2], TJSONNull.Create)
  else if HasValue(ANew, ANames[2]) then PutKey(ATarget, ANames[1], TJSONNull.Create);
end;

procedure CopyTransitionInfo(ATarget, ASource: TJSONObject; const AProp: string);
const
  cProps: array[0..5] of string = ('transition', 'enterFrom', 'leaveTo',
    'enterAnimation', 'updateAnimation', 'leaveAnimation');
var
  t, s: TJSONObject;
  k, n: Integer;
  d: TJSONData;
begin
  t := ATarget;
  s := ASource;
  if AProp <> '' then
  begin
    if not Truthy(ATarget.Find(AProp)) and Truthy(ASource.Find(AProp)) then
      PutKey(ATarget, AProp, TJSONObject.Create);
    t := ObjOf(ATarget, AProp);
    s := ObjOf(ASource, AProp);
  end;
  if (t = nil) or (s = nil) then Exit;
  if AProp <> '' then n := 2 else n := 5;
  for k := 0 to n do
  begin
    d := s.Find(cProps[k]);
    if JNull(t.Find(cProps[k])) and not JNull(d) then PutKey(t, cProps[k], d.Clone);
  end;
end;

procedure TTyGfxModel.OptionUpdated(ANewElements: TJSONData; AIsInit: Boolean);
var
  flat: array of TJSONObject;
  exist: array of TJSONObject;
  items: TMapItemArray;
  ids: TStringList;
  i, j, k, n, p: Integer;
  d, nm: TJSONData;
  key, action, cand: string;
  has, has2: Boolean;
  opt, copy_, ex: TJSONObject;
  arr: TJSONArray;

  { keyExistAndEqual: both an id or a name, the same text }
  function KeyEq(A, B: TJSONData): Boolean;
  var ka, kb: string; ha, hb: Boolean;
  begin
    ka := TyGfxIdOf(A, ha);
    kb := TyGfxIdOf(B, hb);
    Result := ha and hb and (ka = kb);
  end;

  procedure Flatten(AList: TJSONData; AParent: Integer);
  var q, idx: Integer; o: TJSONData; ch: TJSONData;
  begin
    if not (AList is TJSONArray) then Exit;
    for q := 0 to AList.Count - 1 do
    begin
      o := AList.Items[q];
      if not Truthy(o) then Continue;
      if not (o is TJSONObject) then Continue;
      idx := Length(flat);
      SetLength(flat, idx + 1);
      SetLength(FParents, idx + 1);
      flat[idx] := TJSONObject(o.Clone);
      FParents[idx] := AParent;
      ch := TJSONObject(o).Find('children');
      DropKey(flat[idx], 'children');
      if (ch is TJSONArray) and (ch.Count > 0) then Flatten(ch, idx);
    end;
  end;

begin
  flat := nil;
  FParents := nil;
  Flatten(ANewElements, -1);
  { the list there was, a slot per entry }
  if AIsInit then FElements.Clear;
  exist := nil;
  SetLength(exist, FElements.Count);
  for i := 0 to FElements.Count - 1 do
    if FElements.Items[i] is TJSONObject then
      exist[i] := TJSONObject(FElements.Items[i].Clone)
    else
      exist[i] := nil;
  { mappingToExists, normalMerge: prepareResult }
  items := nil;
  SetLength(items, Length(exist));
  for i := 0 to High(exist) do
  begin
    items[i] := Default(TMapItem);
    items[i].Existing := exist[i];
    items[i].NewIdx := -1;
  end;
  { by id }
  for j := 0 to High(flat) do
  begin
    d := flat[j].Find('id');
    key := TyGfxIdOf(d, has);
    if not has then Continue;
    for i := 0 to High(items) do
      if (items[i].Existing <> nil) then
      begin
        cand := TyGfxIdOf(items[i].Existing.Find('id'), has2);
        if has2 and (cand = key) and (items[i].NewIdx < 0) then
        begin
          items[i].NewIdx := j;
          flat[j].Add('__mapped', True);
          Break;
        end;
      end;
  end;
  { by name: an option without an id, onto the first unmapped existing of
    that name with no id or none asked }
  for j := 0 to High(flat) do
  begin
    if flat[j].Find('__mapped') <> nil then Continue;
    nm := flat[j].Find('name');
    key := TyGfxIdOf(nm, has);
    if not has then Continue;
    for i := 0 to High(items) do
    begin
      ex := items[i].Existing;
      if (items[i].NewIdx >= 0) or (ex = nil) then Continue;
      if not (JNull(ex.Find('id')) or JNull(flat[j].Find('id'))) then Continue;
      cand := TyGfxIdOf(ex.Find('name'), has2);
      if has2 and (cand = key) then
      begin
        items[i].NewIdx := j;
        flat[j].Add('__mapped', True);
        Break;
      end;
    end;
  end;
  { by index: the first slot with no option -- not one whose id differs }
  for j := 0 to High(flat) do
  begin
    if flat[j].Find('__mapped') <> nil then Continue;
    d := flat[j].Find('id');
    i := 0;
    while (i <= High(items)) and ((items[i].NewIdx >= 0)
      or ((items[i].Existing <> nil) and not JNull(d)
        and not KeyEq(d, items[i].Existing.Find('id')))) do
      Inc(i);
    if i > High(items) then
    begin
      SetLength(items, i + 1);
      items[i] := Default(TMapItem);
      items[i].NewIdx := -1;
    end;
    items[i].NewIdx := j;
  end;
  for j := 0 to High(flat) do DropKey(flat[j], '__mapped');
  { makeIdAndName }
  ids := TStringList.Create;
  try
    { by bytes, as upstream keys a name: the locale compare took
      U+00C5 and U+212B for one letter, and whatever came after [P2] }
    ids.UseLocale := False;
    ids.Sorted := True;
    ids.Duplicates := dupIgnore;
    ids.CaseSensitive := True;
    for i := 0 to High(items) do
      if items[i].Existing <> nil then
      begin
        key := TyGfxIdOf(items[i].Existing.Find('id'), has);
        if has then ids.Add(key);
      end;
    for i := 0 to High(items) do
      if items[i].NewIdx >= 0 then
      begin
        key := TyGfxIdOf(flat[items[i].NewIdx].Find('id'), has);
        if has then ids.Add(key);
      end;
    for i := 0 to High(items) do
    begin
      if items[i].NewIdx < 0 then Continue;
      opt := flat[items[i].NewIdx];
      key := TyGfxIdOf(opt.Find('name'), has);
      if not JNull(opt.Find('name')) and has then items[i].Name := key
      else if not JNull(opt.Find('name')) then items[i].Name := ''
      else if items[i].Existing <> nil then items[i].Name := TyGfxIdOf(items[i].Existing.Find('name'), has)
      else items[i].Name := 'series' + #0 + IntToStr(i);
      if items[i].Existing <> nil then
        items[i].Id := TyGfxIdOf(items[i].Existing.Find('id'), has)
      else if not JNull(opt.Find('id')) then
        items[i].Id := TyGfxIdOf(opt.Find('id'), has)
      else
      begin
        n := 0;
        repeat
          cand := #0 + items[i].Name + #0 + IntToStr(n);
          Inc(n);
        until ids.IndexOf(cand) < 0;
        items[i].Id := cand;
      end;
      ids.Add(items[i].Id);
    end;
  finally
    ids.Free;
  end;

  { the options to update, in the mapping's order }
  FreeAndNil(FToUpdate);
  FToUpdate := TJSONArray.Create;
  if Length(exist) < Length(items) then
  begin
    k := Length(exist);
    SetLength(exist, Length(items));
    for i := k to High(exist) do exist[i] := nil;
  end;
  for i := 0 to High(items) do
  begin
    if items[i].NewIdx < 0 then Continue;
    opt := flat[items[i].NewIdx];
    { setKeyInfoToNewElOption }
    PutKey(opt, 'id', TJSONString.Create(items[i].Id));
    if not Truthy(opt.Find('type')) and (exist[i] <> nil) and (exist[i].Find('type') <> nil) then
      PutKey(opt, 'type', exist[i].Find('type').Clone);
    if JNull(opt.Find('parentId')) then
    begin
      p := FParents[items[i].NewIdx];
      if p >= 0 then
      begin
        d := flat[p].Find('id');
        if d <> nil then PutKey(opt, 'parentId', d.Clone)
        else DropKey(opt, 'parentId');
      end
      else if (exist[i] <> nil) and (exist[i].Find('parentId') <> nil) then
        PutKey(opt, 'parentId', exist[i].Find('parentId').Clone);
    end;
    { mergeNewElOptionToExist }
    copy_ := TJSONObject(opt.Clone);
    action := StrOf(opt.Find('$action'));
    if not Truthy(opt.Find('$action')) then action := 'merge';
    if action = 'merge' then
    begin
      if exist[i] <> nil then
      begin
        TyGfxMerge(exist[i], copy_);
        MergeLayoutDim(exist[i], copy_, ['width', 'left', 'right']);
        MergeLayoutDim(exist[i], copy_, ['height', 'top', 'bottom']);
        { copyLayoutParams(new, exist) }
        for k := 0 to High(cLocation) do
          if exist[i].Find(cLocation[k]) <> nil then
            PutKey(opt, cLocation[k], exist[i].Find(cLocation[k]).Clone);
        CopyTransitionInfo(opt, exist[i], '');
        CopyTransitionInfo(opt, exist[i], 'shape');
        CopyTransitionInfo(opt, exist[i], 'style');
        CopyTransitionInfo(opt, exist[i], 'extra');
        copy_.Free;
      end
      else
        exist[i] := copy_;
    end
    else if action = 'replace' then
    begin
      FreeAndNil(exist[i]);
      exist[i] := copy_;
    end
    else if action = 'remove' then
    begin
      FreeAndNil(exist[i]);
      copy_.Free;
    end
    else
      copy_.Free;
    { setLayoutInfoToExist }
    if exist[i] <> nil then
    begin
      arr := TJSONArray.Create;
      if IsSetLoc(opt, 'left', 'right') then arr.Add(True) else arr.Add(TJSONNull.Create);
      if IsSetLoc(opt, 'top', 'bottom') then arr.Add(True) else arr.Add(TJSONNull.Create);
      PutKey(opt, 'hv', arr);
      PutKey(exist[i], 'hv', arr.Clone);
      if StrOf(exist[i].Find('type')) = 'group' then
      begin
        if JNull(exist[i].Find('width')) then
        begin
          PutKey(exist[i], 'width', TJSONIntegerNumber.Create(0));
          PutKey(opt, 'width', TJSONIntegerNumber.Create(0));
        end;
        if JNull(exist[i].Find('height')) then
        begin
          PutKey(exist[i], 'height', TJSONIntegerNumber.Create(0));
          PutKey(opt, 'height', TJSONIntegerNumber.Create(0));
        end;
      end;
    end;
    FToUpdate.Add(opt.Clone);
  end;
  { the list: no holes, no $action }
  FElements.Clear;
  for i := 0 to High(exist) do
    if exist[i] <> nil then
    begin
      DropKey(exist[i], '$action');
      FElements.Add(exist[i]);
    end;
  for j := 0 to High(flat) do flat[j].Free;
end;

{ ==================== the view ==================== }

constructor TTyGfxView.Create;
begin
  inherited Create;
  FRoot := TTyGfxEl.Create(gkGroup, 'group');
  FMap := TStringList.Create;
  FMap.CaseSensitive := True;
  FGone := TFPList.Create;
end;

destructor TTyGfxView.Destroy;
begin
  FreeGone;
  FreeAndNil(FRoot);
  FreeAndNil(FMap);
  FreeAndNil(FGone);
  inherited Destroy;
end;

procedure TTyGfxView.FreeGone;
var i: Integer;
begin
  for i := 0 to FGone.Count - 1 do TTyGfxEl(FGone[i]).Free;
  FGone.Clear;
end;

function TTyGfxView.Find(const AId: string): TTyGfxEl;
var i: Integer;
begin
  i := FMap.IndexOf(AId);
  if i >= 0 then Result := TTyGfxEl(FMap.Objects[i]) else Result := nil;
end;

procedure MapRemove(AMap: TStringList; const AId: string);
var i: Integer;
begin
  i := AMap.IndexOf(AId);
  if i >= 0 then AMap.Delete(i);
end;

function TTyGfxView.CreateEl(const AId: string; AParent: TTyGfxEl;
  const AType: string): TTyGfxEl;
begin
  Result := TyGfxCreate(AType);
  if Result = nil then Exit;
  Result.Animation := FAnimation;
  Result.GoneList := FGone;
  TyGfxAddChild(AParent, Result);
  MapRemove(FMap, AId);
  FMap.AddObject(AId, Result);
  Result.Id := AId;
  Result.IsNew := True;
end;

function TTyGfxView.ElementCfg(const AType: string; AOpt: TJSONObject): TTyAnimCfg;
var
  ext: TJSONObject;
  d: TJSONData;
  dur: Double;
begin
  Result := Default(TTyAnimCfg);
  Result.HasDuration := False;
  if FAnim.Enabled then
  begin
    if AType = 'update' then
    begin
      dur := FAnim.DurationUpdate;
      Result.Easing := FAnim.EasingUpdate;
      Result.Delay := FAnim.DelayUpdate;
    end
    else
    begin
      dur := FAnim.Duration;
      Result.Easing := FAnim.Easing;
      Result.Delay := FAnim.Delay;
    end;
    if IsNan(dur) then dur := 0;
    Result.Duration := dur;
    Result.HasDuration := True;
    if IsNan(Result.Delay) then Result.Delay := 0;
    if dur > 0 then
    begin
      Result.SetToFinal := True;
      Result.Scope := AType;
    end;
  end;
  ext := ObjOf(AOpt, AType + 'Animation');
  if ext <> nil then
  begin
    d := ext.Find('duration');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      Result.Duration := d.AsFloat;
      Result.HasDuration := True;
    end;
    d := ext.Find('easing');
    if (d <> nil) and (d.JSONType = jtString) then Result.Easing := d.AsString;
    d := ext.Find('delay');
    if (d <> nil) and (d.JSONType = jtNumber) then Result.Delay := d.AsFloat;
    { extend copies every key: `additive` too [Batch 139] }
    d := ext.Find('additive');
    if d <> nil then Result.Additive := Truthy(d);
  end;
end;

procedure TTyGfxView.ApplyLeave(AEl: TTyGfxEl; AOpt: TJSONObject);
var cfg: TTyAnimCfg;
begin
  if AEl = nil then Exit;
  if AEl.HasLeaveTo and (AEl.Animation <> nil) then
  begin
    cfg := ElementCfg('update', AOpt);
    cfg.Done := @AEl.LeaveDone;
    AEl.Leaving := True;
    AEl.AnimateTo(AEl.LeaveToProps, cfg);
  end
  else
    AEl.LeaveDone;
end;

procedure TTyGfxView.RemoveEl(AEl: TTyGfxEl; AOpt: TJSONObject);
var
  list: TTyGfxElArray;
  i: Integer;
begin
  if (AEl = nil) or (AEl.Parent = nil) then Exit;
  if AEl.IsGroup then
  begin
    list := nil;
    TyGfxTraverse(AEl, list);
    for i := 0 to High(list) do RemoveEl(list[i], AOpt);
  end;
  MapRemove(FMap, AEl.Id);
  ApplyLeave(AEl, AOpt);
end;

procedure TyGfxUpdateLeaveTo(AEl: TTyGfxEl; AOpt: TJSONObject);
var
  sub: TJSONObject;
  k: Integer;
  lt: TJSONObject;
const
  cParts: array[0..3] of string = ('', 'style', 'shape', 'extra');
begin
  if (AEl = nil) or (AOpt = nil) then Exit;
  for k := 0 to 3 do
  begin
    if cParts[k] = '' then sub := AOpt else sub := ObjOf(AOpt, cParts[k]);
    if sub = nil then Continue;
    lt := ObjOf(sub, 'leaveTo');
    if lt = nil then Continue;
    AEl.HasLeaveTo := True;
    TyGfxPropsOf(lt, cParts[k], AEl.LeaveToProps);
  end;
end;

{ zrUtil.indexOf: an array's own, a string's substring }
function TransitionHas(ATrans: TJSONData; const AKey: string): Boolean;
var i: Integer;
begin
  Result := False;
  if ATrans = nil then Exit;
  if ATrans.JSONType = jtString then Exit(Pos(AKey, ATrans.AsString) > 0);
  if ATrans is TJSONArray then
    for i := 0 to ATrans.Count - 1 do
      if StrOf(ATrans.Items[i]) = AKey then Exit(True);
end;

function TransitionAll(ATrans: TJSONData): Boolean;
begin
  Result := (ATrans <> nil) and (ATrans.JSONType = jtString) and (ATrans.AsString = 'all');
end;

function InList(const AList: array of string; const AKey: string): Boolean;
var k: Integer;
begin
  for k := 0 to High(AList) do
    if AList[k] = AKey then Exit(True);
  Result := False;
end;

{ zrUtil.isArrayLike: an array -- a string is not one [Batch 124: it was
  taken for one, so a text shape value always transitioned] }
function IsArrayLike(A: TJSONData): Boolean;
begin
  Result := A is TJSONArray;
end;

{ isNonStyleTransitionEnabled(optVal, elVal): an array-like option value
  always (the element holds a clone, never the option's own array), else a
  value JavaScript's isFinite takes -- a finite number, a boolean, a numeric
  text; null, undefined and an object never }
function NonStyleTransition(A: TJSONData): Boolean;
var v: Double;
begin
  if IsArrayLike(A) then Exit(True);
  if JNull(A) then Exit(False);
  case A.JSONType of
    jtNumber, jtBoolean, jtString:
      begin
        v := JsNumOf(A);
        Result := not IsNan(v) and not IsInfinite(v);
      end;
  else
    Result := False;
  end;
end;

procedure TyGfxApplyDirect(AEl: TTyGfxEl; AOpt: TJSONObject; AClearStyle: Boolean);
var
  styleOpt, shapeOpt, extraOpt: TJSONObject;
  d: TJSONData;
  k: Integer;
begin
  if (AEl = nil) or (AOpt = nil) then Exit;
  styleOpt := ObjOf(AOpt, 'style');
  shapeOpt := ObjOf(AOpt, 'shape');
  if not AEl.IsGroup and (styleOpt <> nil) then
  begin
    if AClearStyle then AEl.Style.Clear;
    TyGfxSetStyle(AEl, styleOpt);
  end;
  { legacy position / scale / origin, then the transformable props }
  d := AOpt.Find('position');
  if (d is TJSONArray) and (d.Count >= 2) then
  begin
    AEl.X := JsNumOf(d.Items[0]);
    AEl.Y := JsNumOf(d.Items[1]);
  end;
  d := AOpt.Find('scale');
  if (d is TJSONArray) and (d.Count >= 2) then
  begin
    AEl.ScaleX := JsNumOf(d.Items[0]);
    AEl.ScaleY := JsNumOf(d.Items[1]);
  end;
  d := AOpt.Find('origin');
  if (d is TJSONArray) and (d.Count >= 2) then
  begin
    AEl.OriginX := JsNumOf(d.Items[0]);
    AEl.OriginY := JsNumOf(d.Items[1]);
  end;
  for k := 0 to High(cTransformable) do
  begin
    d := AOpt.Find(cTransformable[k]);
    if JNull(d) then Continue;
    TyGfxSetTransformProp(AEl, cTransformable[k], JsNumOf(d));
  end;
  if shapeOpt <> nil then TyGfxSetShape(AEl, shapeOpt);
  { extra: attr makes it (an empty object) when there is none, then extends it, with clones
    [Batch 139] }
  extraOpt := ObjOf(AOpt, 'extra');
  if extraOpt <> nil then
  begin
    if AEl.Extra = nil then AEl.Extra := TJSONObject.Create;
    TyGfxExtend(AEl.Extra, extraOpt);
  end;
  { applyMiscProps }
  if AOpt.Find('silent') <> nil then AEl.Silent := Truthy(AOpt.Find('silent'));
  if AOpt.Find('ignore') <> nil then AEl.Ignore := Truthy(AOpt.Find('ignore'));
  if not AEl.IsGroup and (AOpt.Find('invisible') <> nil) then
    AEl.Invisible := Truthy(AOpt.Find('invisible'));
end;

procedure TyGfxTransitionFrom(AEl: TTyGfxEl; AOpt: TJSONObject; var AFrom: TTyAnimProps);
var
  styleOpt, shapeOpt: TJSONObject;
  trans, attrTrans, d: TJSONData;
  keys: array of string;
  k, i: Integer;
  key: string;

  procedure AddKeysOf(AT: TJSONData);
  var q: Integer;
  begin
    keys := nil;
    if AT = nil then Exit;
    if AT.JSONType = jtString then
    begin
      SetLength(keys, 1);
      keys[0] := AT.AsString;
    end
    else if AT is TJSONArray then
    begin
      SetLength(keys, AT.Count);
      for q := 0 to AT.Count - 1 do keys[q] := StrOf(AT.Items[q]);
    end;
  end;

  { prepareShapeOrExtraTransitionFrom: AAttrOpt the option's object, AOwn
    the element's (nil: none, nothing) [Batch 139: extra] }
  procedure ShapeOrExtra(const AMain: string; AAttrOpt, AOwn: TJSONObject);
  var
    q: Integer;
    at: TJSONData;
    nm: string;
  begin
    if (AAttrOpt = nil) or (AOwn = nil) then Exit;
    at := AAttrOpt.Find('transition');
    if Truthy(at) then
    begin
      if TransitionAll(at) then
      begin
        for q := 0 to AOwn.Count - 1 do
          TyAnimPropPut(AFrom, AMain + '.' + AOwn.Names[q], TyGfxAnimOf(AOwn.Items[q]));
      end
      else
      begin
        AddKeysOf(at);
        for q := 0 to High(keys) do
          TyAnimPropPut(AFrom, AMain + '.' + keys[q], AEl.GetAnimProp(AMain + '.' + keys[q]));
      end;
    end
    else if TransitionAll(trans) or TransitionHas(trans, AMain) then
    begin
      for q := 0 to AOwn.Count - 1 do
      begin
        nm := AOwn.Names[q];
        if NonStyleTransition(AAttrOpt.Find(nm)) then
          TyAnimPropPut(AFrom, AMain + '.' + nm, TyGfxAnimOf(AOwn.Items[q]));
      end;
    end;
  end;

  function StyleAnimates(const AKey: string): Boolean;
  begin
    case AEl.Kind of
      gkText: Result := InList(cTextAnimStyle, AKey);
      gkImage: Result := InList(cImageAnimStyle, AKey);
      gkGroup: Result := False;
    else
      Result := InList(cPathAnimStyle, AKey);
    end;
  end;

begin
  if (AEl = nil) or (AOpt = nil) then Exit;
  styleOpt := ObjOf(AOpt, 'style');
  shapeOpt := ObjOf(AOpt, 'shape');
  trans := AOpt.Find('transition');
  { the transform keys `transition` names, at their old values }
  if TransitionAll(trans) then
  begin
    SetLength(keys, Length(cTransformable));
    for k := 0 to High(cTransformable) do keys[k] := cTransformable[k];
  end
  else
    AddKeysOf(trans);
  for k := 0 to High(keys) do
  begin
    if (keys[k] = 'style') or (keys[k] = 'shape') or (keys[k] = 'extra') then Continue;
    TyAnimPropPut(AFrom, keys[k], AEl.GetAnimProp(keys[k]));
  end;
  { the shape's, then extra's (prepareShapeOrExtraTransitionFrom) }
  ShapeOrExtra('shape', shapeOpt, AEl.Shape);
  ShapeOrExtra('extra', ObjOf(AOpt, 'extra'), AEl.Extra);
  { the style's }
  if styleOpt <> nil then
  begin
    attrTrans := styleOpt.Find('transition');
    if Truthy(attrTrans) and not TransitionAll(attrTrans) then
    begin
      AddKeysOf(attrTrans);
      for k := 0 to High(keys) do
        TyAnimPropPut(AFrom, 'style.' + keys[k], AEl.StyleValue(keys[k]));
    end
    else if not AEl.IsGroup and (TransitionAll(trans) or TransitionAll(attrTrans)
      or TransitionHas(trans, 'style')) then
    begin
      for i := 0 to styleOpt.Count - 1 do
      begin
        key := styleOpt.Names[i];
        if StyleAnimates(key) then
          TyAnimPropPut(AFrom, 'style.' + key, AEl.StyleValue(key));
      end;
    end;
  end;
end;

procedure TyGfxEnterFrom(AOpt: TJSONObject; var AEnter: TTyAnimProps);
var
  sub, ef: TJSONObject;
  k: Integer;
begin
  if AOpt = nil then Exit;
  for k := 0 to 3 do
  begin
    case k of
      0: sub := AOpt;
      1: sub := ObjOf(AOpt, 'style');
      2: sub := ObjOf(AOpt, 'shape');
    else
      sub := ObjOf(AOpt, 'extra');
    end;
    if sub = nil then Continue;
    ef := ObjOf(sub, 'enterFrom');
    if ef = nil then Continue;
    case k of
      0: TyGfxPropsOf(ef, '', AEnter);
      1: TyGfxPropsOf(ef, 'style', AEnter);
      2: TyGfxPropsOf(ef, 'shape', AEnter);
    else
      { [Batch 139] }
      TyGfxPropsOf(ef, 'extra', AEnter);
    end;
  end;
end;

{ ==================== keyframe animations [Batch 139, D6] ==================== }

procedure TyGfxStopKeyframes(AEl: TTyGfxEl);
begin
  if AEl = nil then Exit;
  AEl.StopAnimation('keyframe');
  if Length(AEl.KfRestore) > 0 then AEl.Attr(AEl.KfRestore);
end;

procedure TyGfxApplyKeyframes(AEl: TTyGfxEl; AOpt: TJSONData; AEnabled: Boolean;
  ADefaultDuration: Double);
const
  cTargets: array[0..3] of string = ('', 'style', 'shape', 'extra');
  cExclude: array[0..4] of string = ('percent', 'easing', 'shape', 'style', 'extra');
var
  o, kf, vals: TJSONObject;
  d: TJSONData;
  kfs: array of TJSONObject;
  pcts: array of Double;
  i, j, t, k, n: Integer;
  duration, delay, p: Double;
  loop: Boolean;
  anim, other: TTyAnimator;
  keys: array of string;
  values: array of TTyAnimValue;
  others: array of TTyAnimator;
  full, target, easing: string;
begin
  if (AEl = nil) or not AEnabled or not Truthy(AOpt) then Exit;
  if AOpt is TJSONArray then
  begin
    for i := 0 to AOpt.Count - 1 do
      TyGfxApplyKeyframes(AEl, AOpt.Items[i], AEnabled, ADefaultDuration);
    Exit;
  end;
  if not (AOpt is TJSONObject) then Exit;
  o := TJSONObject(AOpt);
  d := o.Find('duration');
  { the enter animation's duration when none is written }
  if JNull(d) then duration := ADefaultDuration else duration := JsNumOf(d);
  { `!keyframes || !duration` }
  d := o.Find('keyframes');
  if not (d is TJSONArray) or (duration = 0) or IsNan(duration) then Exit;
  { keyframes.sort((a, b) => a.percent - b.percent): stable; an item that
    is not an object has nothing to animate and is left out }
  kfs := nil;
  pcts := nil;
  for i := 0 to d.Count - 1 do
  begin
    if not (d.Items[i] is TJSONObject) then Continue;
    kf := TJSONObject(d.Items[i]);
    p := JsNumOf(kf.Find('percent'));
    n := Length(kfs);
    SetLength(kfs, n + 1);
    SetLength(pcts, n + 1);
    j := n - 1;
    while (j >= 0) and (pcts[j] - p > 0) do
    begin
      kfs[j + 1] := kfs[j];
      pcts[j + 1] := pcts[j];
      Dec(j);
    end;
    kfs[j + 1] := kf;
    pcts[j + 1] := p;
  end;
  loop := Truthy(o.Find('loop'));
  for t := 0 to High(cTargets) do
  begin
    target := cTargets[t];
    if not AEl.HasAnimTarget(target) then Continue;
    anim := nil;
    for i := 0 to High(kfs) do
    begin
      if target = '' then vals := kfs[i] else vals := ObjOf(kfs[i], target);
      if vals = nil then Continue;
      keys := nil;
      values := nil;
      for k := 0 to vals.Count - 1 do
      begin
        if (target = '') and InList(cExclude, vals.Names[k]) then Continue;
        n := Length(keys);
        SetLength(keys, n + 1);
        SetLength(values, n + 1);
        keys[n] := vals.Names[k];
        values[n] := TyGfxAnimOf(vals.Items[k]);
      end;
      if Length(keys) = 0 then Continue;
      if anim = nil then
      begin
        anim := AEl.Animate(target, loop, True);
        anim.Scope := 'keyframe';
      end;
      { every other animator of the same target stops its tracks on these
        keys (an Element.animate('') one matches only another such) }
      others := nil;
      for k := 0 to AEl.AnimatorCount - 1 do
      begin
        other := AEl.AnimatorAt(k);
        if (other <> anim) and (other.TargetName = anim.TargetName)
          and (other.NoTargetName = anim.NoTargetName) then
        begin
          SetLength(others, Length(others) + 1);
          others[High(others)] := other;
        end;
      end;
      for k := 0 to High(others) do others[k].StopTracks(keys);
      { the values before: what TyGfxStopKeyframes puts back }
      for k := 0 to High(keys) do
      begin
        if target = '' then full := keys[k] else full := target + '.' + keys[k];
        TyAnimPropPut(AEl.KfRestore, full, AEl.GetAnimProp(full));
      end;
      easing := StrOf(kfs[i].Find('easing'));
      anim.WhenWithKeys(duration * pcts[i], keys, values, easing);
    end;
    if anim = nil then Continue;
    { animationOpts.delay || 0 }
    delay := JsNumOf(o.Find('delay'));
    if IsNan(delay) then delay := 0;
    anim.Delay(delay).Duration(duration).Start(StrOf(o.Find('easing')));
  end;
end;

procedure TTyGfxView.ApplyUpdateTransition(AEl: TTyGfxEl; AOpt: TJSONObject;
  AIsInit: Boolean);
var
  from_, enter: TTyAnimProps;
  cfg: TTyAnimCfg;
begin
  from_ := nil;
  if not AIsInit and FAnim.Enabled then TyGfxTransitionFrom(AEl, AOpt, from_);
  { the final props, directly }
  TyGfxApplyDirect(AEl, AOpt, False);
  if FAnim.Enabled and (AEl.Animation <> nil) then
  begin
    if AIsInit then
    begin
      enter := nil;
      TyGfxEnterFrom(AOpt, enter);
      cfg := ElementCfg('enter', AOpt);
      if cfg.Duration > 0 then AEl.AnimateFrom(enter, cfg);
    end
    else
    begin
      cfg := ElementCfg('update', AOpt);
      if cfg.Duration > 0 then AEl.AnimateFrom(from_, cfg);
    end;
  end;
  TyGfxUpdateLeaveTo(AEl, AOpt);
end;

procedure TTyGfxView.UpdateCommonAttrs(AEl: TTyGfxEl; AOpt: TJSONObject;
  AZ, AZLevel: Double);
var
  i: Integer;
  key: string;
  d: TJSONData;
  has: Boolean;

  function OrDefault(A: TJSONData; ADef: Double): Double;
  begin
    if JNull(A) then Result := ADef else Result := JsNumOf(A);
  end;

begin
  if not AEl.IsGroup then
  begin
    d := AOpt.Find('cursor');
    if d <> nil then
    begin
      if JNull(d) then AEl.Cursor := 'pointer' else AEl.Cursor := d.AsString;
    end;
    if AOpt.Find('zlevel') <> nil then
    begin
      if IsNan(AZLevel) or (AZLevel = 0) then AEl.ZLevel := OrDefault(AOpt.Find('zlevel'), 0)
      else AEl.ZLevel := OrDefault(AOpt.Find('zlevel'), AZLevel);
    end;
    if AOpt.Find('z') <> nil then
    begin
      if IsNan(AZ) or (AZ = 0) then AEl.Z := OrDefault(AOpt.Find('z'), 0)
      else AEl.Z := OrDefault(AOpt.Find('z'), AZ);
    end;
    if AOpt.Find('z2') <> nil then AEl.Z2 := OrDefault(AOpt.Find('z2'), 0);
  end;
  { handlers: a named handler; anything else none }
  for i := 0 to AOpt.Count - 1 do
  begin
    key := AOpt.Names[i];
    if Copy(key, 1, 2) <> 'on' then Continue;
    d := AOpt.Items[i];
    if (d.JSONType = jtString) and (Copy(d.AsString, 1, 1) = '@') then
      AEl.Handlers.Values[key] := d.AsString
    else if AEl.Handlers.IndexOfName(key) >= 0 then
      AEl.Handlers.Delete(AEl.Handlers.IndexOfName(key));
  end;
  d := AOpt.Find('draggable');
  if d <> nil then
  begin
    if not Truthy(d) then AEl.Draggable := ''
    else if d.JSONType = jtString then AEl.Draggable := d.AsString
    else AEl.Draggable := 'true';
  end;
  d := AOpt.Find('name');
  if not JNull(d) then
  begin
    if d.JSONType = jtString then AEl.Name := d.AsString
    else if d.JSONType = jtNumber then AEl.Name := TyJsNumberToString(d.AsFloat)
    else if d.JSONType = jtBoolean then
    begin
      if d.AsBoolean then AEl.Name := 'true' else AEl.Name := 'false';
    end;
  end;
  if not JNull(AOpt.Find('id')) then AEl.Id := TyGfxIdOf(AOpt.Find('id'), has);
end;

{ the ec4 style: isEC4CompatibleStyle and convertFromEC4CompatibleStyle }
function TyGfxIsEC4(AStyle: TJSONObject; const AType: string;
  AHasCfg, AHasContent: Boolean): Boolean;
var d: TJSONData;
begin
  Result := False;
  if AStyle = nil then Exit;
  d := AStyle.Find('legacy');
  if Truthy(d) then Exit(True);
  if (d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean then Exit(False);
  Result := not AHasCfg and not AHasContent and (AType <> 'tspan')
    and ((AType = 'text') or (AStyle.Find('text') <> nil));
end;

procedure EC4RichItem(AOut, AItem: TJSONObject);
const
  cMap: array[0..15, 0..1] of string = (
    ('textStrokeWidth', 'lineWidth'), ('textAlign', 'align'),
    ('textVerticalAlign', 'verticalAlign'), ('textLineHeight', 'lineHeight'),
    ('textWidth', 'width'), ('textHeight', 'height'),
    ('textBackgroundColor', 'backgroundColor'), ('textPadding', 'padding'),
    ('textBorderColor', 'borderColor'), ('textBorderWidth', 'borderWidth'),
    ('textBorderRadius', 'borderRadius'), ('textBoxShadowColor', 'shadowColor'),
    ('textBoxShadowBlur', 'shadowBlur'), ('textBoxShadowOffsetX', 'shadowOffsetX'),
    ('textBoxShadowOffsetY', 'shadowOffsetY'), ('', ''));
var
  k: Integer;
  d: TJSONData;
begin
  if AItem = nil then Exit;
  { richItem.font = richItem.textFont || richItem.font }
  d := AItem.Find('textFont');
  if not Truthy(d) then d := AItem.Find('font');
  if Truthy(d) then PutKey(AItem, 'font', d.Clone)
  else PutKey(AItem, 'font', TJSONNull.Create);
  for k := 0 to 14 do
  begin
    d := AItem.Find(cMap[k, 0]);
    if d <> nil then PutKey(AOut, cMap[k, 1], d.Clone);
  end;
end;

procedure TyGfxConvertEC4(AStyle: TJSONObject; const AType: string;
  AIsNormal: Boolean; out AConfig, AContent: TJSONObject);
var
  ts, rich, cs: TJSONObject;
  i: Integer;
  d: TJSONData;

  procedure CopyAs(const AFrom, ATo: string);
  begin
    d := AStyle.Find(AFrom);
    if d <> nil then PutKey(ts, ATo, d.Clone);
  end;

begin
  AConfig := nil;
  AContent := nil;
  if AType = 'text' then ts := AStyle
  else
  begin
    ts := TJSONObject.Create;
    CopyAs('text', 'text');
    CopyAs('rich', 'rich');
    CopyAs('textFill', 'fill');
    CopyAs('textStroke', 'stroke');
    CopyAs('fontFamily', 'fontFamily');
    CopyAs('fontSize', 'fontSize');
    CopyAs('fontStyle', 'fontStyle');
    CopyAs('fontWeight', 'fontWeight');
    AContent := TJSONObject.Create;
    AContent.Add('type', 'text');
    AContent.Add('style', ts);
    AContent.Add('silent', True);
    AConfig := TJSONObject.Create;
    d := AStyle.Find('textPosition');
    if d <> nil then AConfig.Add('position', d.Clone)
    else if AIsNormal then AConfig.Add('position', 'inside');
    d := AStyle.Find('textOffset');
    if d <> nil then PutKey(AConfig, 'offset', d.Clone);
    d := AStyle.Find('textRotation');
    if d <> nil then PutKey(AConfig, 'rotation', d.Clone);
    d := AStyle.Find('textDistance');
    if d <> nil then PutKey(AConfig, 'distance', d.Clone);
  end;
  EC4RichItem(ts, AStyle);
  rich := ObjOf(ts, 'rich');
  if rich <> nil then
    for i := 0 to rich.Count - 1 do
      if rich.Items[i] is TJSONObject then
      begin
        cs := TJSONObject(rich.Items[i]);
        EC4RichItem(cs, cs);
      end;
end;

{ attr() of a Text from its option: style set, the rest assigned }
procedure AttrText(AText: TTyGfxEl; AOpt: TJSONObject);
var
  i: Integer;
  key: string;
  d: TJSONData;
begin
  if (AText = nil) or (AOpt = nil) then Exit;
  for i := 0 to AOpt.Count - 1 do
  begin
    key := AOpt.Names[i];
    d := AOpt.Items[i];
    if key = 'style' then
    begin
      if d is TJSONObject then TyGfxSetStyle(AText, TJSONObject(d));
    end
    else if TyGfxIsTransformProp(key) then
      TyGfxSetTransformProp(AText, key, JsNumOf(d))
    else if key = 'silent' then AText.Silent := Truthy(d)
    else if key = 'ignore' then AText.Ignore := Truthy(d)
    else if key = 'invisible' then AText.Invisible := Truthy(d)
    else if key = 'z' then AText.Z := JsNumOf(d)
    else if key = 'z2' then AText.Z2 := JsNumOf(d)
    else if key = 'zlevel' then AText.ZLevel := JsNumOf(d)
    else if (key = 'name') and (d.JSONType = jtString) then AText.Name := d.AsString;
  end;
end;

function TTyGfxView.UpdateElements(AModel: TTyGfxModel; AZ, AZLevel: Double): Boolean;
var
  list: TJSONArray;
  i: Integer;
  opt, style, tcOpt, tcCfg, cleaned, convCfg, convContent, ownContent: TJSONObject;
  id, parentId, elType, action: string;
  has, hasParent: Boolean;
  existing, parentEl, el, tc: TTyGfxEl;
  hv, d: TJSONData;
  k: Integer;
const
  cClean: array[0..12] of string = ('id', 'parentId', '$action', 'hv', 'bounding',
    'textContent', 'clipPath', 'left', 'right', 'top', 'bottom', 'width', 'height');
begin
  Result := True;
  list := AModel.UseToUpdate;
  if list = nil then Exit;
  try
    for i := 0 to list.Count - 1 do
    begin
      if not (list.Items[i] is TJSONObject) then Continue;
      opt := TJSONObject(list.Items[i]);
      id := TyGfxIdOf(opt.Find('id'), has);
      existing := nil;
      if has then existing := Find(id);
      parentId := TyGfxIdOf(opt.Find('parentId'), hasParent);
      if hasParent then parentEl := Find(parentId) else parentEl := FRoot;
      elType := StrOf(opt.Find('type'));
      style := ObjOf(opt, 'style');
      if (elType = 'text') and (style <> nil) then
      begin
        hv := opt.Find('hv');
        if (hv is TJSONArray) and (hv.Count > 1) and Truthy(hv.Items[1]) then
        begin
          PutKey(style, 'textVerticalAlign', TJSONNull.Create);
          PutKey(style, 'textBaseline', TJSONNull.Create);
          PutKey(style, 'verticalAlign', TJSONNull.Create);
          PutKey(style, 'align', TJSONNull.Create);
        end;
      end;
      tcOpt := ObjOf(opt, 'textContent');
      tcCfg := ObjOf(opt, 'textConfig');
      ownContent := nil;
      if (style <> nil) and TyGfxIsEC4(style, elType, tcCfg <> nil, tcOpt <> nil) then
      begin
        TyGfxConvertEC4(style, elType, True, convCfg, convContent);
        if (tcCfg = nil) and (convCfg <> nil) then
        begin
          PutKey(opt, 'textConfig', convCfg);
          tcCfg := convCfg;
        end
        else
          convCfg.Free;
        if (tcOpt = nil) and (convContent <> nil) then
        begin
          ownContent := convContent;
          tcOpt := convContent;
        end
        else
          convContent.Free;
      end;
      try
        cleaned := TJSONObject(opt.Clone);
        try
          for k := 0 to High(cClean) do DropKey(cleaned, cClean[k]);
          action := StrOf(opt.Find('$action'));
          if not Truthy(opt.Find('$action')) then action := 'merge';
          if action = 'merge' then
          begin
            el := existing;
            if el = nil then
            begin
              if parentEl = nil then
              begin
                FError := 'the parent ' + TyGfxIdText(parentId) + ' of ' + TyGfxIdText(id) + ' is gone';
                Exit(False);
              end;
              el := CreateEl(id, parentEl, elType);
              if el = nil then
              begin
                FError := 'graphic type ' + elType + ' can not be found';
                Exit(False);
              end;
              ApplyUpdateTransition(el, cleaned, True);
            end
            else
            begin
              el.IsNew := False;
              { stop and restore before any other attribute [Batch 139] }
              TyGfxStopKeyframes(el);
              ApplyUpdateTransition(el, cleaned, False);
            end;
            UpdateCommonAttrs(el, opt, AZ, AZLevel);
          end
          else if action = 'replace' then
          begin
            RemoveEl(existing, opt);
            if parentEl = nil then
            begin
              FError := 'the parent ' + TyGfxIdText(parentId) + ' of ' + TyGfxIdText(id) + ' is gone';
              Exit(False);
            end;
            el := CreateEl(id, parentEl, elType);
            if el = nil then
            begin
              FError := 'graphic type ' + elType + ' can not be found';
              Exit(False);
            end;
            ApplyUpdateTransition(el, cleaned, True);
            UpdateCommonAttrs(el, opt, AZ, AZLevel);
          end
          else if action = 'remove' then
          begin
            TyGfxUpdateLeaveTo(existing, opt);
            RemoveEl(existing, opt);
          end;
        finally
          cleaned.Free;
        end;
        el := Find(id);
        if (el <> nil) and (tcOpt <> nil) then
        begin
          if (action = 'merge') and (el.TextContent <> nil) then
            AttrText(el.TextContent, tcOpt)
          else if (action = 'merge') or (action = 'replace') then
          begin
            FreeAndNil(el.TextContent);
            tc := TTyGfxEl.Create(gkText, 'text');
            tc.Host := el;
            tc.Animation := FAnimation;
            el.TextContent := tc;
            AttrText(tc, tcOpt);
          end;
        end;
        if el <> nil then
        begin
          { setTextConfig: extended }
          if tcCfg <> nil then
          begin
            if el.TextConfig = nil then el.TextConfig := TJSONObject.Create;
            TyGfxExtend(el.TextConfig, tcCfg);
          end;
          { the inner option: a group's size }
          FreeAndNil(el.InnerOptW);
          FreeAndNil(el.InnerOptH);
          el.InnerOptW := TyGfxClone(opt.Find('width'));
          el.InnerOptH := TyGfxClone(opt.Find('height'));
          { setEventData }
          if not el.Silent and not el.Ignore and not el.HasEventData then
          begin
            el.HasEventData := True;
            el.EventName := el.Name;
          end;
          if el.HasEventData then
          begin
            FreeAndNil(el.Info);
            d := opt.Find('info');
            if d <> nil then el.Info := d.Clone;
          end;
          { applyKeyframeAnimation, last [Batch 139] }
          TyGfxApplyKeyframes(el, opt.Find('keyframeAnimation'),
            FAnim.Enabled and (el.Animation <> nil), FAnim.Duration);
        end;
      finally
        ownContent.Free;
      end;
    end;
  finally
    list.Free;
  end;
end;

procedure TTyGfxView.UpdateProps(AEl: TTyGfxEl; const AProps: TTyAnimProps);
var cfg: TTyAnimCfg;
begin
  AEl.StopAnimation('leave');
  if FAnim.Enabled and (FAnim.DurationUpdate > 0) and (AEl.Animation <> nil) then
  begin
    cfg := TyAnimCfg(FAnim.DurationUpdate, FAnim.DelayUpdate, FAnim.EasingUpdate);
    if IsNan(cfg.Delay) then cfg.Delay := 0;
    cfg.SetToFinal := True;
    cfg.Scope := 'update';
    AEl.AnimateTo(AProps, cfg);
  end
  else
  begin
    AEl.StopAnimation;
    AEl.Attr(AProps);
  end;
end;

procedure TTyGfxView.Relocate(AModel: TTyGfxModel; AW, AH: Double;
  const AMeasurer: ITyTextMeasurer);
var
  opts: TJSONArray;
  i: Integer;
  opt: TJSONObject;
  el, parentEl: TTyGfxEl;
  id: string;
  has, h, v, raw, isRoot: Boolean;
  cw, ch, outX, outY, dx, dy: Double;
  rect, lr: TTyXYWH;
  box: TTyRawBox;
  hv, trans: TJSONData;
  props: TTyAnimProps;

  function SizeOf_(A: TJSONData; ABase: Double): Double;
  begin
    if A = nil then Exit(0);
    Result := TyBoxRawResolve(TyBoxRawOf(A), ABase);
    if IsNan(Result) or (Result = 0) then Result := 0;
  end;

begin
  if AModel = nil then Exit;
  opts := AModel.Elements;
  { top-down: a group's size against its parent's }
  for i := 0 to opts.Count - 1 do
  begin
    if not (opts.Items[i] is TJSONObject) then Continue;
    opt := TJSONObject(opts.Items[i]);
    id := TyGfxIdOf(opt.Find('id'), has);
    if not has then Continue;
    el := Find(id);
    if (el = nil) or not el.IsGroup then Continue;
    parentEl := el.Parent;
    isRoot := parentEl = FRoot;
    if isRoot then
    begin
      el.InnerW := SizeOf_(el.InnerOptW, AW);
      el.InnerH := SizeOf_(el.InnerOptH, AH);
    end
    else if parentEl <> nil then
    begin
      el.InnerW := SizeOf_(el.InnerOptW, parentEl.InnerW);
      el.InnerH := SizeOf_(el.InnerOptH, parentEl.InnerH);
    end;
  end;
  { bottom-up: each element placed }
  for i := opts.Count - 1 downto 0 do
  begin
    if not (opts.Items[i] is TJSONObject) then Continue;
    opt := TJSONObject(opts.Items[i]);
    id := TyGfxIdOf(opt.Find('id'), has);
    if not has then Continue;
    el := Find(id);
    if el = nil then Continue;
    parentEl := el.Parent;
    if (parentEl = FRoot) or (parentEl = nil) then
    begin
      cw := AW;
      ch := AH;
    end
    else
    begin
      cw := parentEl.InnerW;
      ch := parentEl.InnerH;
    end;
    { positionElement }
    hv := opt.Find('hv');
    if hv is TJSONArray then
    begin
      h := (hv.Count > 0) and Truthy(hv.Items[0]);
      v := (hv.Count > 1) and Truthy(hv.Items[1]);
    end
    else
    begin
      h := True;
      v := True;
    end;
    outX := el.X;
    outY := el.Y;
    if not h and not v then Continue;
    raw := StrOf(opt.Find('bounding')) = 'raw';
    if raw then
    begin
      if el.IsGroup then
      begin
        rect.X := 0;
        rect.Y := 0;
        rect.W := JsNumOf(opt.Find('width'));
        if JNull(opt.Find('width')) or IsNan(rect.W) or (rect.W = 0) then rect.W := 0;
        rect.H := JsNumOf(opt.Find('height'));
        if JNull(opt.Find('height')) or IsNan(rect.H) or (rect.H = 0) then rect.H := 0;
      end
      else
        rect := TyGfxRect(el, AMeasurer);
    end
    else
    begin
      rect := TyGfxRect(el, AMeasurer);
      if TyGfxNeedLocal(el) then rect := TyRectApplyMat(rect, TyGfxLocalTransform(el));
    end;
    box.Left := TyBoxRawOf(opt.Find('left'));
    box.Right := TyBoxRawOf(opt.Find('right'));
    box.Top := TyBoxRawOf(opt.Find('top'));
    box.Bottom := TyBoxRawOf(opt.Find('bottom'));
    box.Width := TyBoxRawNum(rect.W);
    box.Height := TyBoxRawNum(rect.H);
    lr := TyGetLayoutRect(box, 0, 0, cw, ch, []);
    if h then dx := lr.X - rect.X else dx := 0;
    if v then dy := lr.Y - rect.Y else dy := 0;
    if raw then
    begin
      outX := dx;
      outY := dy;
    end
    else
    begin
      outX := outX + dx;
      outY := outY + dy;
    end;
    if not el.IsNew then
    begin
      trans := opt.Find('transition');
      props := nil;
      if TransitionAll(trans) or TransitionHas(trans, 'x') then
        TyAnimPropPut(props, 'x', TyAnimNum(outX))
      else
        el.X := outX;
      if TransitionAll(trans) or TransitionHas(trans, 'y') then
        TyAnimPropPut(props, 'y', TyAnimNum(outY))
      else
        el.Y := outY;
      UpdateProps(el, props);
    end
    else
    begin
      el.X := outX;
      el.Y := outY;
    end;
  end;
end;

procedure TTyGfxView.Clear;
var
  i: Integer;
  list: TTyGfxElArray;
begin
  list := nil;
  for i := 0 to FMap.Count - 1 do
  begin
    SetLength(list, Length(list) + 1);
    list[High(list)] := TTyGfxEl(FMap.Objects[i]);
  end;
  for i := 0 to High(list) do
    if not list[i].Gone and (FMap.IndexOfObject(list[i]) >= 0) then
      RemoveEl(list[i], nil);
  FMap.Clear;
end;

procedure TTyGfxView.ForgetModel;
begin
  FLast := nil;
  FHasLast := False;
end;

procedure TTyGfxView.Snap;
var
  list, leaving: TTyGfxElArray;
  i: Integer;
begin
  list := nil;
  TyGfxTraverse(FRoot, list);
  leaving := nil;
  for i := 0 to High(list) do
  begin
    list[i].StopAnimation('', True);
    if list[i].TextContent <> nil then list[i].TextContent.StopAnimation('', True);
    if list[i].Leaving then
    begin
      SetLength(leaving, Length(leaving) + 1);
      leaving[High(leaving)] := list[i];
    end;
  end;
  for i := 0 to High(leaving) do leaving[i].LeaveDone;
end;

procedure TTyGfxView.Render(AModel: TTyGfxModel; AW, AH: Double;
  const AMeasurer: ITyTextMeasurer; const AAnim: TTyGfxAnimSettings;
  AZ, AZLevel: Double);
begin
  FError := '';
  if (AModel <> FLast) or not FHasLast then
  begin
    { the last model's elements leave as its settings say }
    Clear;
  end;
  FAnim := AAnim;
  FLast := AModel;
  FHasLast := True;
  if AModel = nil then Exit;
  if not UpdateElements(AModel, AZ, AZLevel) then Exit;
  Relocate(AModel, AW, AH, AMeasurer);
end;

procedure TTyGfxView.Place(AW, AH: Double; const AMeasurer: ITyTextMeasurer);
begin
  if FLast = nil then Exit;
  Relocate(FLast, AW, AH, AMeasurer);
end;

procedure TTyGfxView.Prepare(const AMeasurer: ITyTextMeasurer;
  const AGround: TTyGfxGround);

  procedure Walk(AEl: TTyGfxEl);
  var i: Integer;
  begin
    if AEl.TextContent <> nil then
    begin
      TyGfxInnerText(AEl, AMeasurer, AGround);
      TyGfxLabelTransform(AEl.TextContent, AEl.TextContent.HasTransform,
        AEl.TextContent.Transform);
    end;
    for i := 0 to High(AEl.Children) do Walk(AEl.Children[i]);
  end;

begin
  TyGfxUpdateTransforms(FRoot);
  Walk(FRoot);
end;

end.
