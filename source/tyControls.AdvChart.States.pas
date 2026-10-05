unit tyControls.AdvChart.States;
{$mode objfpc}{$H+}
{ Element states as ECharts 6.1 and zrender 6.1 run them, and the series
  selection model behind `select` [Batch 88].

  TWO LAYERS, AS UPSTREAM KEEPS THEM. Hover, the highlight actions and the
  selection only set FLAGS on an element -- hoverState (0 normal, 1 blur,
  2 emphasis), selected, and __highByOuter, the bits of whoever highlighted
  it by action. Once per frame applyElementStates turns the flags into a
  state LIST, always select first and then emphasis or blur, and zrender's
  useStates applies it: unchanged list, nothing happens; empty list, every
  key back to its rest value; otherwise the state objects merged in list
  order (the later wins on a shared key), each key a state sets taking that
  value and every other key returning to rest.

  THE DEFAULT STATE PROXY (util/states.ts:225-341) makes the state objects
  at the moment they are used, from the element's CURRENT values:
    emphasis -- the declared emphasis style; with no declared fill the fill
      to lift is the SELECT fill when select is in the same list and declares
      one, else the rest fill, lifted ten per cent; the stroke is lifted only
      when the fill was not; z2 = current z2 + 10 when the state exists;
    select -- the declared select state, z2 = current z2 + 9;
    blur -- the declared blur opacity, else the current opacity times 0.1
      (kept as is when blur is already applied).
  Because the lift is added to the CURRENT z2 at every switch, the z2 of an
  element that keeps a state creeps up; only an empty list puts it back.
  An element whose emphasis is disabled has no proxy: its states are the
  declared objects as they are, without any lift.

  THE SELECTION MODEL (model/Series.ts:602-741) is keyed by the item's
  NAME (its id when it has none), so two items of one name select together;
  selectedMap is null, the string 'all', or an object whose keys keep
  JavaScript's own order -- integer-like keys first, ascending, then the
  others in insertion order.

  PURE: SysUtils, Math, fpjson and the AdvChart value units. No LCL. }
interface
uses SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Style, tyControls.AdvChart.Color;

type
  { The three special states, in the order applyElementStates lists them. }
  TTyStName = (stnSelect, stnEmphasis, stnBlur);
  TTyStNames = set of TTyStName;

  { What a state can change on an element, as far as this port draws it:
    the style keys, the paint order, a translation (a selected slice), a
    sector's outer radius, a symbol's scale and whether a label shows.
    Geometry is in DEVICE px, colours packed. }
  TTyStKey = (stkFill, stkStroke, stkLineWidth, stkOpacity, stkZ2, stkX, stkY,
    stkR, stkScale, stkIgnore,
    { a label line's shape.smooth: every state sets it, nought unless the
      state's labelLine says (setLabelLineState) [Batch 112] }
    stkSmooth);

  { A state object, sparse: a key the state does not set is absent. A colour
    key can be the word 'none' (None) -- zrender's hasFillOrStroke reads it as
    no colour. Lifted marks a colour the proxy made, not one declared. }
  TTyStObject = record
    Has: array[TTyStKey] of Boolean;
    Num: array[TTyStKey] of Double;
    Color: array[TTyStKey] of TTyChartColor;
    None: array[TTyStKey] of Boolean;
    Lifted: array[TTyStKey] of Boolean;
    { an emphasis fill of 'inherit': the fill the lift would start from }
    FillInherit: Boolean;
  end;

  { ONE zrender ELEMENT: a bar, a slice, a symbol path, a polyline, a label,
    a label line. }
  TTyStElement = record
    Exists: Boolean;
    { a Path: the emphasis proxy lifts its colours (a label is Text and
      does not) }
    IsPath: Boolean;
    { echarts' default state proxy is installed: emphasis not disabled }
    Proxy: Boolean;
    { the flags }
    HoverState: Integer;
    Selected: Boolean;
    HighByOuter: Cardinal;
    { which state objects exist (el.states.select ...), and what they say }
    HasState: array[TTyStName] of Boolean;
    Decl: array[TTyStName] of TTyStObject;
    { every key at rest, and every key now }
    Rest, Cur: TTyStObject;
    { el.currentStates }
    States: TTyStNames;
    { the merged state object the last useStates applied (what the proxies'
      transitions aim at) [Batch 94] }
    Merged: TTyStObject;
  end;

  { A data item's element and what is attached to it: the label, which
    always takes its host's state list, and a pie's label line.

    A LINE'S SYMBOL IS TWO ELEMENTS upstream: the Symbol group, which is the
    hover dispatcher, and its path (childAt(0)), which carries the states.
    traverseUpdateState walks both, so their hoverStates move together --
    except that Symbol.highlight, the line's one-point highlight action,
    enters emphasis on the PATH alone and sets the path's __highByOuter
    (Symbol.ts:125-134). The group's own flags are kept apart here; the
    Host is the path. [Batch 90] }
  TTyStItem = record
    Host, Label_, Guide: TTyStElement;
    { MORE PATHS OF THE SAME DISPATCHER, each with states of its own (a
      pictorial bar's glyphs): traverseUpdateState gives them the host's
      flags, so they take the host's list like the label does }
    Parts: array of TTyStElement;
    HasGroup: Boolean;
    GroupHover: Integer;
    GroupHbo: Cardinal;
  end;
  PTyStItem = ^TTyStItem;

  { emphasis.focus as blurSeries reads it (util/states.ts:429-517): a falsy
    value or 'none' does nothing, 'series' spares the hovered series, 'self'
    spares an element held by an action in it; any other truthy value blurs
    everything the scope reaches. The tree family turns its words into the
    data indices that leave the blur again (Indices, inner). }
  TTyStFocusKind = (sfkNone, sfkSelf, sfkSeries, sfkOther, sfkIndices);
  TTyStFocus = record
    Kind: TTyStFocusKind;
    Indices: TTyIntegerArray;
    { A SECOND DATA TYPE'S INDICES [Batch 114]: a sankey's focus is an
      object of two lists, node and edge -- blurSeries leaves the blur for
      each data type's elements. Indices are the node data's then. }
    EdgeIndices: TTyIntegerArray;
  end;
  { blurScope: falsy is 'coordinateSystem'; anything but the two words acts
    as 'global' }
  TTyStScope = (sbsCoordinateSystem, sbsSeries, sbsGlobal);

const
  TyStZ2EmphasisLift = 10;
  TyStZ2SelectLift = 9;
  TyStHoverNormal = 0;
  TyStHoverBlur = 1;
  TyStHoverEmphasis = 2;

{ ---- state objects ---- }
function TyStNoObject: TTyStObject;
procedure TyStSetNum(var AObj: TTyStObject; AKey: TTyStKey; AValue: Double);
procedure TyStSetColor(var AObj: TTyStObject; AKey: TTyStKey; AColor: TTyChartColor);
procedure TyStSetNone(var AObj: TTyStObject; AKey: TTyStKey);
{ ATop's keys over ABase's (zrender's extend of one state over another) }
function TyStOverlay(const ABase, ATop: TTyStObject): TTyStObject;
{ hasFillOrStroke: set, and not 'none' }
function TyStHasColour(const AObj: TTyStObject; AKey: TTyStKey): Boolean;

{ ---- the machine ---- }
{ applyElementStates: the list the flags ask for -- select when selected
  and a select state exists, then emphasis (hoverState 2) or blur (1) when
  that state exists. }
function TyStTargetStates(const AEl: TTyStElement): TTyStNames;
{ The state object useStates would get for AName with the list ANew --
  through the default proxy when it is installed. False: no object. }
function TyStStateObject(const AEl: TTyStElement; AName: TTyStName;
  ANew: TTyStNames; out AObj: TTyStObject): Boolean;
{ zrender's useStates. True when the list changed (and so the values). }
function TyStUseStates(var AEl: TTyStElement; ANew: TTyStNames): Boolean;
{ applyElementStates on a data item: the host's list from its flags, and
  the label and the label line take the same list when the host's changed.
  True when anything changed. }
function TyStApplyItem(var AItem: TTyStItem): Boolean;
{ useStates on the whole item with a given list (the host's, then the label
  and line with it), whatever the flags -- the re-render's useStates of the
  previous list. }
function TyStUseItemStates(var AItem: TTyStItem; ANew: TTyStNames): Boolean;
{ A full update's clearStates: every key at rest, no state. }
procedure TyStClearItem(var AItem: TTyStItem);
{ 'select,emphasis' }
function TyStNamesText(ANames: TTyStNames): string;

{ ---- hover and highlight flags (util/states.ts:111-147, 360-382) ---- }
procedure TyStEnterEmphasis(var AEl: TTyStElement);
procedure TyStLeaveEmphasis(var AEl: TTyStElement);
{ the highlight action's digit: 0 without a highlightKey }
procedure TyStEnterEmphasisBy(var AEl: TTyStElement; ADigit: Integer);
procedure TyStLeaveEmphasisBy(var AEl: TTyStElement; ADigit: Integer);

{ ---- an item's flags as the actions and the pointer move them [Batch 90] ----
  APoly is the hoverState of a line's polyline (and area), -1 when there is
  none: every change of a symbol group's hoverState carries it along
  (LineView.ts:893-899, onHoverStateChange -> _changePolyState). }
{ the dispatcher's __highByOuter: the group's on a line symbol }
function TyStDispatcherHbo(const AItem: TTyStItem): Cardinal;
{ enterEmphasisWhenMouseOver / leaveEmphasisWhenMouseOut: nothing while the
  dispatcher is held by an action }
function TyStItemHoverEnter(var AItem: TTyStItem; var APoly: Integer): Boolean;
function TyStItemHoverLeave(var AItem: TTyStItem; var APoly: Integer): Boolean;
{ enterEmphasis / leaveEmphasis with a highlight digit; AOnPath: the bit and
  the emphasis on the path only (Symbol.highlight) }
function TyStItemEnterEmphasisBy(var AItem: TTyStItem; ADigit: Integer;
  AOnPath: Boolean; var APoly: Integer): Boolean;
function TyStItemLeaveEmphasisBy(var AItem: TTyStItem; ADigit: Integer;
  AOnPath: Boolean; var APoly: Integer): Boolean;
{ blurSeries' singleEnterBlur on every element of the item, except one with
  a __highByOuter when ASpareHeld (the hovered series under focus 'self') }
function TyStItemEnterBlur(var AItem: TTyStItem; ASpareHeld: Boolean;
  var APoly: Integer): Boolean;
{ singleLeaveBlur: blur back to normal, nothing else }
function TyStItemLeaveBlur(var AItem: TTyStItem; var APoly: Integer): Boolean;

{ ---- focus and scope ---- }
function TyStFocusOf(AValue: TJSONData): TTyStFocus;
function TyStScopeOf(AValue: TJSONData): TTyStScope;
{ blurSeries' filter: is series T blurred when the target's focus and scope
  say so; ASame T is the target, ASameCoord they share a coordinate system
  (a series with none shares only with itself) }
function TyStBlursSeries(const AFocus: TTyStFocus; AScope: TTyStScope;
  ASame, ASameCoord: Boolean): Boolean;

{ ---- reading what the option declares ---- }
{ `[state].[block]` read nearest node first (a data item, then its series):
  itemStyle -> color fill, borderColor stroke, borderWidth lineWidth,
  opacity; lineStyle -> color stroke, width lineWidth (AWidthBolder True when
  the width is 'bolder'), opacity; areaStyle -> color fill, opacity;
  'lineStyle:item' -> the lineStyle block read with itemStyle's keys (a
  sankey link: getItemStyle of its lineStyle model) [Batch 114]. AState ''
  reads the block at the node itself. }
function TyStReadStyle(const ANodes: array of TJSONObject; const AState,
  ABlock: string; out AWidthBolder: Boolean): TTyStObject;
{ The first node that writes the path (a boolean, or a truthy value):
  AHas False when none writes it. }
function TyStReadBool(const ANodes: array of TJSONObject;
  const APath: array of string; out AHas: Boolean): Boolean;
function TyStReadNumber(const ANodes: array of TJSONObject;
  const APath: array of string; out AHas: Boolean): Double;
function TyStReadString(const ANodes: array of TJSONObject;
  const APath: array of string; out AHas: Boolean): string;
{ the value the first node writes at APath (null falls through), or nil }
function TyStFind(const ANodes: array of TJSONObject;
  const APath: array of string): TJSONData;

{ ==================== the selection model ==================== }

type
  TTySelMode = (ssmOff, ssmSingle, ssmMultiple, ssmSeries,
    { a truthy value that is none of the three: _innerSelect does nothing,
      but unselect and isSelected still read the map }
    ssmOther);
  TTySelMapKind = (smkNull, smkAll, smkObject);

  TTySelModel = record
    Mode: TTySelMode;
    MapKind: TTySelMapKind;
    { option.selectedMap, in JavaScript key order }
    MapKeys: TTyStringArray;
    MapVals: TTyBoolArray;
    { _selectedDataIndicesMap: key -> raw index, -1 once unselected }
    IdxKeys: TTyStringArray;
    IdxVals: TTyIntegerArray;
  end;

  { The series' data as the selection reads it, per INNER index. }
  TTySelData = record
    Keys: TTyStringArray;
    Raws: TTyIntegerArray;
    Disabled: TTyBoolArray;
  end;

{ selectedMode as written: false / null / absent off, true single, the three
  words, any other truthy value ssmOther }
function TySelModeOf(AValue: TJSONData): TTySelMode;
function TySelNew(AMode: TTySelMode): TTySelModel;
{ select / unselect / toggleSelect with inner indices }
procedure TySelSelect(var AModel: TTySelModel; const AData: TTySelData;
  const AInner: array of Integer);
procedure TySelUnselect(var AModel: TTySelModel; const AData: TTySelData;
  const AInner: array of Integer);
procedure TySelToggle(var AModel: TTySelModel; const AData: TTySelData;
  const AInner: array of Integer);
function TySelIsSelected(const AModel: TTySelModel; const AData: TTySelData;
  AInner: Integer): Boolean;
{ getSelectedDataIndices: RAW indices }
function TySelIndices(const AModel: TTySelModel; const AData: TTySelData): TTyIntegerArray;
{ _initSelectedMapFromData: the items whose data says `selected: true`,
  unless a map exists already }
procedure TySelInitFromData(var AModel: TTySelModel; const AData: TTySelData;
  const ASelected: TTyBoolArray);
{ option.selectedMap as JSON: null, "all" or an object }
function TySelMapJson(const AModel: TTySelModel): string;
{ JavaScript's own key order: is this key an array index }
function TyJsIsIndexKey(const AKey: string): Boolean;

implementation

{ ==================== state objects ==================== }

function TyStNoObject: TTyStObject;
begin
  Result := Default(TTyStObject);
end;

procedure TyStSetNum(var AObj: TTyStObject; AKey: TTyStKey; AValue: Double);
begin
  AObj.Has[AKey] := True;
  AObj.Num[AKey] := AValue;
end;

procedure TyStSetColor(var AObj: TTyStObject; AKey: TTyStKey; AColor: TTyChartColor);
begin
  AObj.Has[AKey] := True;
  AObj.None[AKey] := False;
  AObj.Lifted[AKey] := False;
  AObj.Color[AKey] := AColor;
end;

procedure TyStSetNone(var AObj: TTyStObject; AKey: TTyStKey);
begin
  AObj.Has[AKey] := True;
  AObj.None[AKey] := True;
  AObj.Lifted[AKey] := False;
  AObj.Color[AKey] := 0;
end;

procedure CopyKey(var ADst: TTyStObject; const ASrc: TTyStObject; AKey: TTyStKey);
begin
  ADst.Has[AKey] := ASrc.Has[AKey];
  ADst.Num[AKey] := ASrc.Num[AKey];
  ADst.Color[AKey] := ASrc.Color[AKey];
  ADst.None[AKey] := ASrc.None[AKey];
  ADst.Lifted[AKey] := ASrc.Lifted[AKey];
end;

function TyStOverlay(const ABase, ATop: TTyStObject): TTyStObject;
var k: TTyStKey;
begin
  Result := ABase;
  for k := Low(TTyStKey) to High(TTyStKey) do
    if ATop.Has[k] then CopyKey(Result, ATop, k);
  if ATop.Has[stkFill] then Result.FillInherit := ATop.FillInherit
  else Result.FillInherit := ABase.FillInherit or ATop.FillInherit;
end;

function TyStHasColour(const AObj: TTyStObject; AKey: TTyStKey): Boolean;
begin
  Result := AObj.Has[AKey] and not AObj.None[AKey];
end;

{ ==================== the machine ==================== }

function TyStTargetStates(const AEl: TTyStElement): TTyStNames;
begin
  Result := [];
  if AEl.Selected and AEl.HasState[stnSelect] then Include(Result, stnSelect);
  if (AEl.HoverState = TyStHoverEmphasis) and AEl.HasState[stnEmphasis] then
    Include(Result, stnEmphasis)
  else if (AEl.HoverState = TyStHoverBlur) and AEl.HasState[stnBlur] then
    Include(Result, stnBlur);
end;

{ createEmphasisDefaultState (states.ts:225-279) }
function EmphasisProxy(const AEl: TTyStElement; ANew: TTyStNames;
  out AObj: TTyStObject): Boolean;
var
  exists, hasSelect: Boolean;
  fromFill, fromStroke: TTyStObject;
  fillKey: Boolean;
begin
  exists := AEl.HasState[stnEmphasis];
  if exists then AObj := AEl.Decl[stnEmphasis] else AObj := TyStNoObject;
  if AEl.IsPath then
  begin
    { savePathStates: the rest fill and stroke, and the DECLARED select ones }
    hasSelect := stnSelect in ANew;
    fromFill := TyStNoObject;
    fromStroke := TyStNoObject;
    if hasSelect and AEl.HasState[stnSelect]
      and TyStHasColour(AEl.Decl[stnSelect], stkFill) then
      CopyKey(fromFill, AEl.Decl[stnSelect], stkFill)
    else
      CopyKey(fromFill, AEl.Rest, stkFill);
    if hasSelect and AEl.HasState[stnSelect]
      and TyStHasColour(AEl.Decl[stnSelect], stkStroke) then
      CopyKey(fromStroke, AEl.Decl[stnSelect], stkStroke)
    else
      CopyKey(fromStroke, AEl.Rest, stkStroke);
    if TyStHasColour(fromFill, stkFill) or TyStHasColour(fromStroke, stkStroke) then
    begin
      exists := True;
      fillKey := AObj.FillInherit;
      if fillKey then
      begin
        { 'inherit': the colour the lift would start from, as it is }
        TyStSetColor(AObj, stkFill, fromFill.Color[stkFill]);
        if not TyStHasColour(fromFill, stkFill) then TyStSetNone(AObj, stkFill);
        AObj.FillInherit := False;
      end
      else if not TyStHasColour(AObj, stkFill) and TyStHasColour(fromFill, stkFill) then
      begin
        TyStSetColor(AObj, stkFill, TyChartLiftColor(fromFill.Color[stkFill]));
        AObj.Lifted[stkFill] := True;
      end
      else if not TyStHasColour(AObj, stkStroke) and TyStHasColour(fromStroke, stkStroke) then
      begin
        TyStSetColor(AObj, stkStroke, TyChartLiftColor(fromStroke.Color[stkStroke]));
        AObj.Lifted[stkStroke] := True;
      end;
    end;
  end;
  { only when there is a state at all: a label with no emphasis object gets
    no lift }
  if exists and not AObj.Has[stkZ2] then
    TyStSetNum(AObj, stkZ2, AEl.Cur.Num[stkZ2] + TyStZ2EmphasisLift);
  Result := exists;
end;

function TyStStateObject(const AEl: TTyStElement; AName: TTyStName;
  ANew: TTyStNames; out AObj: TTyStObject): Boolean;
begin
  AObj := TyStNoObject;
  if not AEl.Proxy then
  begin
    Result := AEl.HasState[AName];
    if Result then AObj := AEl.Decl[AName];
    Exit;
  end;
  case AName of
    stnEmphasis: Result := EmphasisProxy(AEl, ANew, AObj);
    stnSelect:
      begin
        { createSelectDefaultState: only when the state exists }
        Result := AEl.HasState[stnSelect];
        if not Result then Exit;
        AObj := AEl.Decl[stnSelect];
        if not AObj.Has[stkZ2] then
          TyStSetNum(AObj, stkZ2, AEl.Cur.Num[stkZ2] + TyStZ2SelectLift);
      end;
  else
    begin
      { createBlurDefaultState: always a state; the current opacity, a
        tenth of it unless blur is applied already }
      Result := True;
      if AEl.HasState[stnBlur] then AObj := AEl.Decl[stnBlur];
      if not AObj.Has[stkOpacity] then
      begin
        if stnBlur in AEl.States then
          TyStSetNum(AObj, stkOpacity, AEl.Cur.Num[stkOpacity])
        else
          TyStSetNum(AObj, stkOpacity, AEl.Cur.Num[stkOpacity] * 0.1);
      end;
    end;
  end;
end;

function TyStUseStates(var AEl: TTyStElement; ANew: TTyStNames): Boolean;
var
  n: TTyStName;
  merged, obj: TTyStObject;
  k: TTyStKey;
begin
  Result := False;
  if not AEl.Exists then Exit;
  { the same list: nothing at all happens, not even the proxies }
  if ANew = AEl.States then Exit;
  Result := True;
  if ANew = [] then
  begin
    { clearStates: every saved key back to rest }
    AEl.Cur := AEl.Rest;
    AEl.States := [];
    AEl.Merged := TyStNoObject;
    Exit;
  end;
  merged := TyStNoObject;
  { in list order, select first: the later state wins a shared key }
  for n := Low(TTyStName) to High(TTyStName) do
  begin
    if not (n in ANew) then Continue;
    if TyStStateObject(AEl, n, ANew, obj) then
      merged := TyStOverlay(merged, obj);
  end;
  for k := Low(TTyStKey) to High(TTyStKey) do
    if merged.Has[k] then CopyKey(AEl.Cur, merged, k)
    else CopyKey(AEl.Cur, AEl.Rest, k);
  AEl.States := ANew;
  AEl.Merged := merged;
end;

function TyStUseItemStates(var AItem: TTyStItem; ANew: TTyStNames): Boolean;
var i: Integer;
begin
  Result := TyStUseStates(AItem.Host, ANew);
  { the attached text and line get useStates(sameList) only from inside the
    host's own, so only when the host's list changed }
  if not Result then Exit;
  TyStUseStates(AItem.Label_, ANew);
  TyStUseStates(AItem.Guide, ANew);
  for i := 0 to High(AItem.Parts) do TyStUseStates(AItem.Parts[i], ANew);
end;

function TyStApplyItem(var AItem: TTyStItem): Boolean;
begin
  if not AItem.Host.Exists then Exit(False);
  Result := TyStUseItemStates(AItem, TyStTargetStates(AItem.Host));
end;

procedure ClearEl(var AEl: TTyStElement);
begin
  AEl.Cur := AEl.Rest;
  AEl.States := [];
  AEl.Merged := TyStNoObject;
end;

procedure TyStClearItem(var AItem: TTyStItem);
var i: Integer;
begin
  ClearEl(AItem.Host);
  ClearEl(AItem.Label_);
  ClearEl(AItem.Guide);
  for i := 0 to High(AItem.Parts) do ClearEl(AItem.Parts[i]);
end;

function TyStNamesText(ANames: TTyStNames): string;
const cNames: array[TTyStName] of string = ('select', 'emphasis', 'blur');
var n: TTyStName;
begin
  Result := '';
  for n := Low(TTyStName) to High(TTyStName) do
    if n in ANames then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + cNames[n];
    end;
end;

{ ==================== flags ==================== }

procedure TyStEnterEmphasis(var AEl: TTyStElement);
begin
  AEl.HoverState := TyStHoverEmphasis;
end;

procedure TyStLeaveEmphasis(var AEl: TTyStElement);
begin
  if AEl.HoverState = TyStHoverEmphasis then AEl.HoverState := TyStHoverNormal;
end;

function DigitBit(ADigit: Integer): Cardinal;
begin
  { JavaScript's 1 << n takes n mod 32 }
  Result := Cardinal(1) shl (ADigit and 31);
end;

procedure TyStEnterEmphasisBy(var AEl: TTyStElement; ADigit: Integer);
begin
  AEl.HighByOuter := AEl.HighByOuter or DigitBit(ADigit);
  TyStEnterEmphasis(AEl);
end;

procedure TyStLeaveEmphasisBy(var AEl: TTyStElement; ADigit: Integer);
begin
  AEl.HighByOuter := AEl.HighByOuter and not DigitBit(ADigit);
  if AEl.HighByOuter = 0 then TyStLeaveEmphasis(AEl);
end;

{ ==================== an item's flags [Batch 90] ==================== }

function TyStDispatcherHbo(const AItem: TTyStItem): Cardinal;
begin
  if AItem.HasGroup then Result := AItem.GroupHbo
  else Result := AItem.Host.HighByOuter;
end;

{ doChangeHoverState on the group: a change carries the polyline }
function GroupTo(var AItem: TTyStItem; AValue: Integer; var APoly: Integer): Boolean;
begin
  Result := AItem.GroupHover <> AValue;
  if Result and (APoly >= 0) then APoly := AValue;
  AItem.GroupHover := AValue;
end;

function HostTo(var AItem: TTyStItem; AValue: Integer): Boolean;
begin
  Result := AItem.Host.HoverState <> AValue;
  AItem.Host.HoverState := AValue;
end;

{ traverseUpdateState: the group first, then the path }
function AllTo(var AItem: TTyStItem; AValue: Integer; var APoly: Integer): Boolean;
begin
  Result := False;
  if AItem.HasGroup and GroupTo(AItem, AValue, APoly) then Result := True;
  if HostTo(AItem, AValue) then Result := True;
end;

{ every element whose hoverState is AFrom to ATo }
function AllFromTo(var AItem: TTyStItem; AFrom, ATo: Integer; var APoly: Integer): Boolean;
begin
  Result := False;
  if AItem.HasGroup and (AItem.GroupHover = AFrom) and GroupTo(AItem, ATo, APoly) then
    Result := True;
  if (AItem.Host.HoverState = AFrom) and HostTo(AItem, ATo) then Result := True;
end;

function TyStItemHoverEnter(var AItem: TTyStItem; var APoly: Integer): Boolean;
begin
  Result := False;
  if not AItem.Host.Exists or (TyStDispatcherHbo(AItem) <> 0) then Exit;
  Result := AllTo(AItem, TyStHoverEmphasis, APoly);
end;

function TyStItemHoverLeave(var AItem: TTyStItem; var APoly: Integer): Boolean;
begin
  Result := False;
  if not AItem.Host.Exists or (TyStDispatcherHbo(AItem) <> 0) then Exit;
  Result := AllFromTo(AItem, TyStHoverEmphasis, TyStHoverNormal, APoly);
end;

function TyStItemEnterEmphasisBy(var AItem: TTyStItem; ADigit: Integer;
  AOnPath: Boolean; var APoly: Integer): Boolean;
begin
  Result := False;
  if not AItem.Host.Exists then Exit;
  if AOnPath or not AItem.HasGroup then
    AItem.Host.HighByOuter := AItem.Host.HighByOuter or DigitBit(ADigit)
  else
    AItem.GroupHbo := AItem.GroupHbo or DigitBit(ADigit);
  if AOnPath then Result := HostTo(AItem, TyStHoverEmphasis)
  else Result := AllTo(AItem, TyStHoverEmphasis, APoly);
end;

function TyStItemLeaveEmphasisBy(var AItem: TTyStItem; ADigit: Integer;
  AOnPath: Boolean; var APoly: Integer): Boolean;
var left: Cardinal;
begin
  Result := False;
  if not AItem.Host.Exists then Exit;
  if AOnPath or not AItem.HasGroup then
  begin
    AItem.Host.HighByOuter := AItem.Host.HighByOuter and not DigitBit(ADigit);
    left := AItem.Host.HighByOuter;
  end
  else
  begin
    AItem.GroupHbo := AItem.GroupHbo and not DigitBit(ADigit);
    left := AItem.GroupHbo;
  end;
  { only when every bit is gone }
  if left <> 0 then Exit;
  if AOnPath then
  begin
    if AItem.Host.HoverState = TyStHoverEmphasis then
      Result := HostTo(AItem, TyStHoverNormal);
  end
  else
    Result := AllFromTo(AItem, TyStHoverEmphasis, TyStHoverNormal, APoly);
end;

function TyStItemEnterBlur(var AItem: TTyStItem; ASpareHeld: Boolean;
  var APoly: Integer): Boolean;
begin
  Result := False;
  if not AItem.Host.Exists then Exit;
  if AItem.HasGroup and not (ASpareHeld and (AItem.GroupHbo <> 0))
    and GroupTo(AItem, TyStHoverBlur, APoly) then Result := True;
  if not (ASpareHeld and (AItem.Host.HighByOuter <> 0))
    and HostTo(AItem, TyStHoverBlur) then Result := True;
end;

function TyStItemLeaveBlur(var AItem: TTyStItem; var APoly: Integer): Boolean;
begin
  Result := False;
  if not AItem.Host.Exists then Exit;
  Result := AllFromTo(AItem, TyStHoverBlur, TyStHoverNormal, APoly);
end;

function JsTruthyValue(AValue: TJSONData): Boolean;
begin
  if (AValue = nil) or (AValue.JSONType = jtNull) then Exit(False);
  case AValue.JSONType of
    jtBoolean: Result := AValue.AsBoolean;
    jtNumber: Result := (AValue.AsFloat <> 0) and not IsNan(AValue.AsFloat);
    jtString: Result := AValue.AsString <> '';
  else
    Result := True;
  end;
end;

function TyStFocusOf(AValue: TJSONData): TTyStFocus;
var s: string;
begin
  Result := Default(TTyStFocus);
  Result.Kind := sfkNone;
  if not JsTruthyValue(AValue) then Exit;
  Result.Kind := sfkOther;
  if AValue.JSONType <> jtString then Exit;
  s := AValue.AsString;
  if s = 'none' then Result.Kind := sfkNone
  else if s = 'self' then Result.Kind := sfkSelf
  else if s = 'series' then Result.Kind := sfkSeries;
end;

function TyStScopeOf(AValue: TJSONData): TTyStScope;
begin
  Result := sbsCoordinateSystem;
  if not JsTruthyValue(AValue) then Exit;
  Result := sbsGlobal;
  if AValue.JSONType <> jtString then Exit;
  if AValue.AsString = 'series' then Result := sbsSeries
  else if AValue.AsString = 'coordinateSystem' then Result := sbsCoordinateSystem;
end;

function TyStBlursSeries(const AFocus: TTyStFocus; AScope: TTyStScope;
  ASame, ASameCoord: Boolean): Boolean;
begin
  Result := False;
  if AFocus.Kind = sfkNone then Exit;
  if (AScope = sbsSeries) and not ASame then Exit;
  if (AScope = sbsCoordinateSystem) and not ASameCoord then Exit;
  if (AFocus.Kind = sfkSeries) and ASame then Exit;
  Result := True;
end;

{ ==================== reading the option ==================== }

function Walk(ANode: TJSONObject; const APath: array of string): TJSONData;
var i: Integer; d: TJSONData;
begin
  Result := nil;
  d := ANode;
  for i := 0 to High(APath) do
  begin
    if not (d is TJSONObject) then Exit;
    d := TJSONObject(d).Find(APath[i]);
    if d = nil then Exit;
  end;
  Result := d;
end;

function TyStFind(const ANodes: array of TJSONObject;
  const APath: array of string): TJSONData;
var i: Integer; d: TJSONData;
begin
  Result := nil;
  for i := 0 to High(ANodes) do
  begin
    if ANodes[i] = nil then Continue;
    d := Walk(ANodes[i], APath);
    if (d = nil) or (d.JSONType = jtNull) then Continue;
    Exit(d);
  end;
end;

function TyStReadBool(const ANodes: array of TJSONObject;
  const APath: array of string; out AHas: Boolean): Boolean;
var i: Integer; d: TJSONData;
begin
  Result := False;
  AHas := False;
  for i := 0 to High(ANodes) do
  begin
    if ANodes[i] = nil then Continue;
    d := Walk(ANodes[i], APath);
    { null is not written: the model's get falls through to the next level }
    if (d = nil) or (d.JSONType = jtNull) then Continue;
    AHas := True;
    case d.JSONType of
      jtBoolean: Result := d.AsBoolean;
      jtNumber: Result := (d.AsFloat <> 0) and not IsNan(d.AsFloat);
      jtString: Result := d.AsString <> '';
    else
      Result := True;
    end;
    Exit;
  end;
end;

function TyStReadNumber(const ANodes: array of TJSONObject;
  const APath: array of string; out AHas: Boolean): Double;
var i: Integer; d: TJSONData;
begin
  Result := NaN;
  AHas := False;
  for i := 0 to High(ANodes) do
  begin
    if ANodes[i] = nil then Continue;
    d := Walk(ANodes[i], APath);
    if (d = nil) or (d.JSONType = jtNull) then Continue;
    AHas := True;
    if d.JSONType = jtNumber then Result := d.AsFloat;
    Exit;
  end;
end;

function TyStReadString(const ANodes: array of TJSONObject;
  const APath: array of string; out AHas: Boolean): string;
var i: Integer; d: TJSONData;
begin
  Result := '';
  AHas := False;
  for i := 0 to High(ANodes) do
  begin
    if ANodes[i] = nil then Continue;
    d := Walk(ANodes[i], APath);
    if (d = nil) or (d.JSONType = jtNull) then Continue;
    AHas := True;
    if d.JSONType = jtString then Result := d.AsString;
    Exit;
  end;
end;

procedure ReadColour(const ANodes: array of TJSONObject; const AState, ABlock,
  AName: string; AKey: TTyStKey; AAllowInherit: Boolean; var AObj: TTyStObject);
var
  s: string;
  has: Boolean;
  c: TTyChartColor;
begin
  if AState = '' then s := TyStReadString(ANodes, [ABlock, AName], has)
  else s := TyStReadString(ANodes, [AState, ABlock, AName], has);
  if not has then Exit;
  if s = 'none' then
    TyStSetNone(AObj, AKey)
  else if (s = 'inherit') and AAllowInherit then
  begin
    AObj.Has[AKey] := True;
    AObj.None[AKey] := True;
    AObj.FillInherit := True;
  end
  else if TyTryParseChartColor(s, c) then
    TyStSetColor(AObj, AKey, c);
end;

procedure ReadNum(const ANodes: array of TJSONObject; const AState, ABlock,
  AName: string; AKey: TTyStKey; var AObj: TTyStObject);
var v: Double; has: Boolean;
begin
  if AState = '' then v := TyStReadNumber(ANodes, [ABlock, AName], has)
  else v := TyStReadNumber(ANodes, [AState, ABlock, AName], has);
  if has and not IsNan(v) then TyStSetNum(AObj, AKey, v);
end;

function TyStReadStyle(const ANodes: array of TJSONObject; const AState,
  ABlock: string; out AWidthBolder: Boolean): TTyStObject;
var s: string; has: Boolean;
begin
  Result := TyStNoObject;
  AWidthBolder := False;
  if ABlock = 'lineStyle:item' then
  begin
    ReadColour(ANodes, AState, 'lineStyle', 'color', stkFill, AState = 'emphasis', Result);
    ReadColour(ANodes, AState, 'lineStyle', 'borderColor', stkStroke, False, Result);
    ReadNum(ANodes, AState, 'lineStyle', 'borderWidth', stkLineWidth, Result);
    ReadNum(ANodes, AState, 'lineStyle', 'opacity', stkOpacity, Result);
  end
  else if ABlock = 'lineStyle' then
  begin
    ReadColour(ANodes, AState, ABlock, 'color', stkStroke, False, Result);
    if AState = '' then s := TyStReadString(ANodes, [ABlock, 'width'], has)
    else s := TyStReadString(ANodes, [AState, ABlock, 'width'], has);
    if has and (s = 'bolder') then AWidthBolder := True
    else ReadNum(ANodes, AState, ABlock, 'width', stkLineWidth, Result);
    ReadNum(ANodes, AState, ABlock, 'opacity', stkOpacity, Result);
  end
  else if ABlock = 'areaStyle' then
  begin
    ReadColour(ANodes, AState, ABlock, 'color', stkFill, AState = 'emphasis', Result);
    ReadNum(ANodes, AState, ABlock, 'opacity', stkOpacity, Result);
  end
  else
  begin
    ReadColour(ANodes, AState, ABlock, 'color', stkFill, AState = 'emphasis', Result);
    ReadColour(ANodes, AState, ABlock, 'borderColor', stkStroke, False, Result);
    ReadNum(ANodes, AState, ABlock, 'borderWidth', stkLineWidth, Result);
    ReadNum(ANodes, AState, ABlock, 'opacity', stkOpacity, Result);
  end;
end;

{ ==================== the selection model ==================== }

function TyJsIsIndexKey(const AKey: string): Boolean;
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
  { an array index is below 2^32 - 1 }
  Result := v < QWord(4294967295);
end;

function KeyIndexOf(const AKeys: TTyStringArray; const AKey: string): Integer;
var i: Integer;
begin
  for i := 0 to High(AKeys) do
    if AKeys[i] = AKey then Exit(i);
  Result := -1;
end;

{ where a NEW key goes in JavaScript's own order: an index key among the
  index keys by value, any other key at the end }
function InsertPos(const AKeys: TTyStringArray; const AKey: string): Integer;
var i: Integer; v: QWord;
begin
  Result := Length(AKeys);
  if not TyJsIsIndexKey(AKey) then Exit;
  v := StrToQWord(AKey);
  for i := 0 to High(AKeys) do
    if not TyJsIsIndexKey(AKeys[i]) or (StrToQWord(AKeys[i]) > v) then Exit(i);
end;

procedure MapSetBool(var AKeys: TTyStringArray; var AVals: TTyBoolArray;
  const AKey: string; AValue: Boolean);
var i, p: Integer;
begin
  i := KeyIndexOf(AKeys, AKey);
  if i >= 0 then
  begin
    AVals[i] := AValue;
    Exit;
  end;
  p := InsertPos(AKeys, AKey);
  SetLength(AKeys, Length(AKeys) + 1);
  SetLength(AVals, Length(AVals) + 1);
  for i := High(AKeys) downto p + 1 do
  begin
    AKeys[i] := AKeys[i - 1];
    AVals[i] := AVals[i - 1];
  end;
  AKeys[p] := AKey;
  AVals[p] := AValue;
end;

procedure MapSetInt(var AKeys: TTyStringArray; var AVals: TTyIntegerArray;
  const AKey: string; AValue: Integer);
var i, p: Integer;
begin
  i := KeyIndexOf(AKeys, AKey);
  if i >= 0 then
  begin
    AVals[i] := AValue;
    Exit;
  end;
  p := InsertPos(AKeys, AKey);
  SetLength(AKeys, Length(AKeys) + 1);
  SetLength(AVals, Length(AVals) + 1);
  for i := High(AKeys) downto p + 1 do
  begin
    AKeys[i] := AKeys[i - 1];
    AVals[i] := AVals[i - 1];
  end;
  AKeys[p] := AKey;
  AVals[p] := AValue;
end;

function TySelModeOf(AValue: TJSONData): TTySelMode;
var s: string;
begin
  Result := ssmOff;
  if AValue = nil then Exit;
  case AValue.JSONType of
    jtBoolean:
      if AValue.AsBoolean then Result := ssmSingle;
    jtNumber:
      if (AValue.AsFloat <> 0) and not IsNan(AValue.AsFloat) then Result := ssmOther;
    jtString:
      begin
        s := AValue.AsString;
        if s = 'single' then Result := ssmSingle
        else if s = 'multiple' then Result := ssmMultiple
        else if s = 'series' then Result := ssmSeries
        else if s <> '' then Result := ssmOther;
      end;
    jtObject, jtArray: Result := ssmOther;
  end;
end;

function TySelNew(AMode: TTySelMode): TTySelModel;
begin
  Result := Default(TTySelModel);
  Result.Mode := AMode;
  Result.MapKind := smkNull;
end;

function ValidInner(const AData: TTySelData; AInner: Integer): Boolean;
begin
  Result := (AInner >= 0) and (AInner <= High(AData.Keys));
end;

{ _innerSelect (Series.ts:685-719) }
procedure TySelSelect(var AModel: TTySelModel; const AData: TTySelData;
  const AInner: array of Integer);
var
  i, last: Integer;
  key: string;
begin
  if Length(AInner) = 0 then Exit;
  case AModel.Mode of
    ssmSeries:
      AModel.MapKind := smkAll;
    ssmMultiple:
      begin
        if AModel.MapKind <> smkObject then
        begin
          AModel.MapKind := smkObject;
          AModel.MapKeys := nil;
          AModel.MapVals := nil;
        end;
        for i := 0 to High(AInner) do
        begin
          if not ValidInner(AData, AInner[i]) then Continue;
          key := AData.Keys[AInner[i]];
          MapSetBool(AModel.MapKeys, AModel.MapVals, key, True);
          MapSetInt(AModel.IdxKeys, AModel.IdxVals, key, AData.Raws[AInner[i]]);
        end;
      end;
    ssmSingle:
      begin
        { THE LAST ONE, and the map is replaced }
        last := AInner[High(AInner)];
        if not ValidInner(AData, last) then Exit;
        key := AData.Keys[last];
        AModel.MapKind := smkObject;
        SetLength(AModel.MapKeys, 1);
        SetLength(AModel.MapVals, 1);
        AModel.MapKeys[0] := key;
        AModel.MapVals[0] := True;
        SetLength(AModel.IdxKeys, 1);
        SetLength(AModel.IdxVals, 1);
        AModel.IdxKeys[0] := key;
        AModel.IdxVals[0] := AData.Raws[last];
      end;
  end;
end;

procedure TySelUnselect(var AModel: TTySelModel; const AData: TTySelData;
  const AInner: array of Integer);
var
  i: Integer;
  key: string;
begin
  if AModel.MapKind = smkNull then Exit;
  { series mode, or a map that is 'all': everything goes }
  if (AModel.Mode = ssmSeries) or (AModel.MapKind = smkAll) then
  begin
    AModel.MapKind := smkObject;
    AModel.MapKeys := nil;
    AModel.MapVals := nil;
    AModel.IdxKeys := nil;
    AModel.IdxVals := nil;
    Exit;
  end;
  for i := 0 to High(AInner) do
  begin
    if not ValidInner(AData, AInner[i]) then Continue;
    key := AData.Keys[AInner[i]];
    MapSetBool(AModel.MapKeys, AModel.MapVals, key, False);
    MapSetInt(AModel.IdxKeys, AModel.IdxVals, key, -1);
  end;
end;

procedure TySelToggle(var AModel: TTySelModel; const AData: TTySelData;
  const AInner: array of Integer);
var i: Integer;
begin
  for i := 0 to High(AInner) do
    if TySelIsSelected(AModel, AData, AInner[i]) then
      TySelUnselect(AModel, AData, [AInner[i]])
    else
      TySelSelect(AModel, AData, [AInner[i]]);
end;

function TySelIsSelected(const AModel: TTySelModel; const AData: TTySelData;
  AInner: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if not ValidInner(AData, AInner) then Exit;
  case AModel.MapKind of
    smkNull: Exit;
    smkAll: Result := True;
  else
    begin
      i := KeyIndexOf(AModel.MapKeys, AData.Keys[AInner]);
      Result := (i >= 0) and AModel.MapVals[i];
    end;
  end;
  { select.disabled: in the map, never shown selected }
  if Result and (AInner <= High(AData.Disabled)) and AData.Disabled[AInner] then
    Result := False;
end;

function TySelIndices(const AModel: TTySelModel; const AData: TTySelData): TTyIntegerArray;
var i, n: Integer;
begin
  Result := nil;
  if AModel.MapKind = smkAll then
  begin
    { getData().getIndices(): the raw indices of the shown data }
    Result := Copy(AData.Raws);
    Exit;
  end;
  n := 0;
  SetLength(Result, Length(AModel.IdxVals));
  for i := 0 to High(AModel.IdxVals) do
    if AModel.IdxVals[i] >= 0 then
    begin
      Result[n] := AModel.IdxVals[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

procedure TySelInitFromData(var AModel: TTySelModel; const AData: TTySelData;
  const ASelected: TTyBoolArray);
var
  idx: TTyIntegerArray;
  i, n: Integer;
begin
  if AModel.MapKind <> smkNull then Exit;
  idx := nil;
  n := 0;
  SetLength(idx, Length(ASelected));
  for i := 0 to High(ASelected) do
    if ASelected[i] then
    begin
      idx[n] := i;
      Inc(n);
    end;
  SetLength(idx, n);
  if n > 0 then TySelSelect(AModel, AData, idx);
end;

function TySelMapJson(const AModel: TTySelModel): string;
var i: Integer;
begin
  case AModel.MapKind of
    smkNull: Result := 'null';
    smkAll: Result := '"all"';
  else
    begin
      Result := '{';
      for i := 0 to High(AModel.MapKeys) do
      begin
        if i > 0 then Result := Result + ',';
        Result := Result + '"' + StringToJSONString(AModel.MapKeys[i]) + '":'
          + BoolToStr(AModel.MapVals[i], 'true', 'false');
      end;
      Result := Result + '}';
    end;
  end;
end;

end.
