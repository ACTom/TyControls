unit tyControls.AdvChart.Timeline;
{$mode objfpc}{$H+}
{ The timeline component: its option, its model and its slider view, as
  ECharts 6.1's component/timeline makes them -- held to the real dist by
  tools/advchart-oracle/timeline.js. [Batch 129, C21]

  THE OPTION (preprocessor.ts compatibleEC2): ec2's `type: 'number' |
  'time'` becomes axisType; every object keeps an `itemStyle.emphasis`, a
  label written gets a `normal` copy of its keys, an emphasis label moves
  out of the item style; `controlPosition` moves into controlStyle.position
  ('none' is show false); an item with a name and no value takes the name.
  The writes stay in the option, as upstream's getOption shows them.

  THE MODEL (TimelineModel, SliderTimelineModel): the option merged over
  the slider's defaults (mergeDefaultAndTheme, the box by mergeLayoutParam),
  the skin's colours where upstream reads its tokens; the data -- a
  category axis' item is its index and its name a category, a time or value
  axis' its value; setCurrentIndex wraps with a loop and clamps without.

  THE VIEW (SliderTimelineView.render): the layout (_layout), the axis on
  the data's extent (an ordinal, a time or an interval scale, fixed at both
  ends), the axis line and the progress line, a symbol per data item, the
  three buttons, the checkpoint -- one element kept from render to render,
  sliding 300 ms quinticInOut to its tick -- the labels (a category axis'
  auto interval drops some), and _position: the main and label groups put
  against the view rect by their bounding rects, turned a quarter for a
  vertical timeline. A tick and a label are entered by the data VALUE --
  upstream's customised scale hands the value where an index is meant, so
  on a time or value axis a click asks for the value as an index.

  THE STATES: a tick before the current index and a label at or before it
  are in 'progress'; the pointer over a tick, a label or a button puts it in
  'emphasis' (z2 lifted ten) with the component's state transition.

  The elements are tyControls.AdvChart.GfxEl's: the chart steps their
  animations, paints them and asks for the hit.

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Anim,
  tyControls.AdvChart.GfxEl, tyControls.AdvChart.ZrPath;

const
  TyTlPlayIcon = 'path://M15 0C23.2843 0 30 6.71573 30 15C30 23.2843 23.2843 30 15 30C6.71573 30 0 23.2843 0 15C0 6.71573 6.71573 0 15 0ZM15 3C8.37258 3 3 8.37258 3 15C3 21.6274 8.37258 27 15 27C21.6274 27 27 21.6274 27 15C27 8.37258 21.6274 3 15 3ZM11.5 10.6699C11.5 9.90014 12.3333 9.41887 13 9.80371L20.5 14.1338C21.1667 14.5187 21.1667 15.4813 20.5 15.8662L13 20.1963C12.3333 20.5811 11.5 20.0999 11.5 19.3301V10.6699Z';
  TyTlStopIcon = 'path://M15 0C23.2843 0 30 6.71573 30 15C30 23.2843 23.2843 30 15 30C6.71573 30 0 23.2843 0 15C0 6.71573 6.71573 0 15 0ZM15 3C8.37258 3 3 8.37258 3 15C3 21.6274 8.37258 27 15 27C21.6274 27 27 21.6274 27 15C27 8.37258 21.6274 3 15 3ZM11.5 10C12.3284 10 13 10.6716 13 11.5V18.5C13 19.3284 12.3284 20 11.5 20C10.6716 20 10 19.3284 10 18.5V11.5C10 10.6716 10.6716 10 11.5 10ZM18.5 10C19.3284 10 20 10.6716 20 11.5V18.5C20 19.3284 19.3284 20 18.5 20C17.6716 20 17 19.3284 17 18.5V11.5C17 10.6716 17.6716 10 18.5 10Z';
  TyTlNextIcon = 'path://M0.838834 18.7383C0.253048 18.1525 0.253048 17.2028 0.838834 16.617L7.55635 9.89949L0.838834 3.18198C0.253048 2.59619 0.253048 1.64645 0.838834 1.06066C1.42462 0.474874 2.37437 0.474874 2.96015 1.06066L10.7383 8.83883L10.8412 8.95277C11.2897 9.50267 11.2897 10.2963 10.8412 10.8462L10.7383 10.9602L2.96015 18.7383C2.37437 19.3241 1.42462 19.3241 0.838834 18.7383Z';
  TyTlPrevIcon = 'path://M10.9602 1.06066C11.5459 1.64645 11.5459 2.59619 10.9602 3.18198L4.24264 9.89949L10.9602 16.617C11.5459 17.2028 11.5459 18.1525 10.9602 18.7383C10.3744 19.3241 9.42462 19.3241 8.83883 18.7383L1.06066 10.9602L0.957771 10.8462C0.509245 10.2963 0.509245 9.50267 0.957771 8.95277L1.06066 8.83883L8.83883 1.06066C9.42462 0.474874 10.3744 0.474874 10.9602 1.06066Z';

type
  { The skin's answers where upstream reads its design tokens: colours as
    CSS text, the label font. }
  TTyTimelineInk = record
    Line, Progress, Item, ItemEmphasis, ItemEmphasisBorder, ProgressItem,
      Checkpoint, CheckpointBorder, Control, ControlBorder, ControlEmphasis,
      ControlEmphasisBorder, LabelColour, LabelEmphasis, Border,
      { an empty symbol's inside (tokens.color.neutral00) }
      EmptyFill: string;
    FontFamily: string;
    { css px }
    FontPx: Double;
  end;

  TTyTlRoleKind = (tlrLine, tlrProgress, tlrTick, tlrLabel, tlrNext, tlrPrev,
    tlrPlay, tlrStop, tlrPointer);
  TTyTlRole = record
    Kind: TTyTlRoleKind;
    { a tick's or a label's data index (the tick's place in the data) }
    Index: Integer;
    { what its onclick hands _changeTimeline: the tick's VALUE }
    Value: Double;
  end;
  TTyTlRoleArray = array of TTyTlRole;

  { what a render hands its elements: the driver of their animations, and
    the state transition (updateStates: the component animates and
    stateAnimation's duration is above nought) }
  TTyTlAnimCfg = record
    Driver: TTyAnimation;
    { the chart animates at all: without it nothing slides }
    Allowed: Boolean;
    HasStateCfg: Boolean;
    StateCfg: TTyAnimCfg;
  end;

  TTyJsonObjArray = array of TJSONObject;

  { One timeline's view: SliderTimelineView, its elements and its state
    between renders. }
  TTyTimelineView = class
  private
    FFull: TJSONObject;
    { an empty option, for a sub-model written null }
    FEmpty: TJSONObject;
    FItems: TTyJsonObjArray;
    FAxisType: string;
    FExtent: array[0..1] of Double;
    FUseUTC: Boolean;
    FEmph, FProg: array of TTyAnimState;
    FHasEmph, FHasProg, FInProg: TTyBoolArray;
    { the label's value its progress is judged by }
    FLabelValue: TTyDoubleArray;
    { each element's z2 in its normal state: the emphasis lifts it ten }
    FBaseZ2: TTyDoubleArray;
    procedure DropGroups;
    function ItemAt(AValue: Double): TJSONObject;
    procedure AddEl(AEl: TTyGfxEl; AKind: TTyTlRoleKind; AIndex: Integer;
      AValue: Double);
    function StateOf(AIndex: Integer): TTyAnimState;
    procedure UseStatesOf(AIndex: Integer; ANoAnimation: Boolean);
  public
    Uid: string;
    { view.group, and the two groups a render makes in it }
    Root, MainGroup, LabelGroup: TTyGfxEl;
    { _currentPointer: one element from render to render; owned here while
      no group holds it }
    Checkpoint: TTyGfxEl;
    { the last render's progress line (nil when lineStyle.show is false) }
    ProgressLine: TTyGfxEl;
    { every displayable, in the tree's order; its role; its hoverState }
    Els: TTyGfxElArray;
    Roles: TTyTlRoleArray;
    Hover: TTyBoolArray;
    { the last render drew something (show) }
    Shown: Boolean;
    { a new set of elements (a render) }
    Gen: Integer;
    { ---- the model, as the last render read it ---- }
    Count: Integer;
    Values: TTyDoubleArray;
    Names: TTyStringArray;
    CurrentIndex: Double;
    PlayState, Loop, Rewind, Realtime, Inverse, Vertical: Boolean;
    PlayInterval: Double;
    Z, ZLevel: Double;
    { ---- the layout ---- }
    AxisExtent: array[0..1] of Double;
    { zrender's Draggable has the checkpoint }
    Dragging: Boolean;
    constructor Create(const AUid: string);
    destructor Destroy; override;
    { render(timelineModel): ANode the option (the raw tree's), ARoot the
      root option (its textStyle and stateAnimation), the chart's size in
      css px }
    procedure Render(ANode, ARoot: TJSONObject; AW, AH: Double;
      const AInk: TTyTimelineInk; const AMeasurer: ITyTextMeasurer;
      const AAnim: TTyTlAnimCfg; AUseUTC: Boolean);
    { remove(): the group emptied, the checkpoint kept }
    procedure Remove;
    { axis.dataToCoord }
    function DataToCoord(AValue: Double): Double;
    { every element's global transform (updateTransform) }
    procedure UpdateTransforms;
    { the display list's order: z2, then the tree's }
    function DisplayOrder: TTyIntegerArray;
    { findHover: the topmost element that is not silent under (AX, AY), css
      px; -1 for none }
    function HitAt(AX, AY: Double; const AMeasurer: ITyTextMeasurer): Integer;
    { an element is a high-down dispatcher (enableHoverEmphasis) }
    function IsDispatcher(AIndex: Integer): Boolean;
    { applyElementStates for one element: its kept states and the hover's }
    procedure ApplyStates(AIndex: Integer);
    { _toAxisCoord: the point in the main group's own frame, its x }
    function ToAxisCoord(AX, AY: Double): Double;
    { _findNearestTick: the data index nearest the axis coordinate; -1 for
      none }
    function NearestTick(ACoord: Double): Integer;
    { _pointerChangeTimeline's move: the coordinate clamped to the axis, the
      checkpoint and the progress line there; answers the coordinate }
    function DragTo(AX, AY: Double): Double;
    { the role of an element }
    function RoleOf(AIndex: Integer): TTyTlRole;
    { the merged option the last render read (nil before one) }
    property Full: TJSONObject read FFull;
  end;

{ ---- the option ---- }
{ compatibleEC2 over AOption.timeline (one or a list) }
procedure TyTimelinePreprocess(AOption: TJSONObject);
{ the slider's defaultOption with the skin's colours, as JSON text }
function TyTimelineDefaultsJson(const AInk: TTyTimelineInk): string;
{ the option merged over the defaults (mergeDefaultAndTheme with the box's
  mergeLayoutParam); the caller frees it }
function TyTimelineFullOption(ANode: TJSONObject; const AInk: TTyTimelineInk): TJSONObject;
{ _initData: the values (a category's are the indices), the category names
  and each item that is an object }
procedure TyTimelineData(AFull: TJSONObject; AUseUTC: Boolean;
  out AValues: TTyDoubleArray; out ANames: TTyStringArray; out AItems: TTyJsonObjArray);
{ setCurrentIndex: wrapped with a loop, clamped without }
function TyTimelineNormIndex(AIndex: Double; ACount: Integer; ALoop: Boolean): Double;
{ JavaScript's truthiness of a JSON value (nil is undefined) }
function TyTlTruthy(A: TJSONData): Boolean;
{ set AKey in place when the object has it, append it otherwise (a JS
  property write); AValue is taken over }
procedure TyTlPut(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
{ a number as a JSON value: an integer where it is one }
function TyTlNumJson(AValue: Double): TJSONData;
{ JavaScript's unary plus of a JSON value (nil is undefined: NaN) }
function TyTlJsNum(A: TJSONData): Double;

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Handlers, tyControls.AdvChart.Time,
  tyControls.AdvChart.AxisLabels, tyControls.FontUnits;

const
  { a DOUBLE: a bare real literal is a Single in FPC }
  cHalf: Double = 0.5;
  cDeg: Double = 180;

{ ==================== JSON ==================== }

function ObjOf(A: TJSONData): TJSONObject;
begin
  if (A <> nil) and (A.JSONType = jtObject) then Result := TJSONObject(A)
  else Result := nil;
end;

function Sub(AObj: TJSONObject; const AKey: string): TJSONObject;
begin
  if AObj = nil then Exit(nil);
  Result := ObjOf(AObj.Find(AKey));
end;

function NotNull(A: TJSONData): Boolean; inline;
begin
  Result := (A <> nil) and (A.JSONType <> jtNull);
end;

function TyTlTruthy(A: TJSONData): Boolean;
begin
  if A = nil then Exit(False);
  case A.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

{ Model.getShallow down a chain of options: the first that holds the key
  not null }
function ChainGet(const AChain: array of TJSONObject; const AKey: string): TJSONData;
var
  i: Integer;
  d: TJSONData;
begin
  for i := 0 to High(AChain) do
  begin
    if AChain[i] = nil then Continue;
    d := AChain[i].Find(AKey);
    if NotNull(d) then Exit(d);
  end;
  Result := nil;
end;

{ JavaScript's unary plus of a JSON value }
function JsNum(A: TJSONData): Double;
begin
  if A = nil then Exit(NaN);
  case A.JSONType of
    jtNumber: Result := A.AsFloat;
    jtBoolean: if A.AsBoolean then Result := 1 else Result := 0;
    jtNull: Result := 0;
    jtString: Result := TyJsToNumber(A.AsString);
  else
    Result := NaN;
  end;
end;

function TyTlJsNum(A: TJSONData): Double;
begin
  Result := JsNum(A);
end;

function StrOf(A: TJSONData): string;
begin
  if (A <> nil) and (A.JSONType = jtString) then Result := A.AsString
  else Result := '';
end;

procedure TyTlPut(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
begin
  { fpjson's Elements[]: in place (the old value freed) or appended }
  AObj.Elements[AKey] := AValue;
end;

function TyTlNumJson(AValue: Double): TJSONData;
var q: QWord;
begin
  { minus nought keeps its sign: the sign bit, not 1 / x (a trap) }
  Move(AValue, q, SizeOf(q));
  if (not IsNan(AValue)) and (not IsInfinite(AValue)) and (Frac(AValue) = 0)
    and (Abs(AValue) < 9.0E15) and not ((AValue = 0) and ((q shr 63) = 1)) then
    Result := TJSONInt64Number.Create(Trunc(AValue))
  else
    Result := TJSONFloatNumber.Create(AValue);
end;

{ zrUtil.merge on objects: a key both hold as plain objects merged into,
  else the source's value cloned in when overwriting or when the target
  has no such key }
procedure JsMerge(ATarget, ASource: TJSONObject; AOverwrite: Boolean);
var
  i, k: Integer;
  name: string;
  sv, tv: TJSONData;
begin
  if (ATarget = nil) or (ASource = nil) then Exit;
  for i := 0 to ASource.Count - 1 do
  begin
    name := ASource.Names[i];
    sv := ASource.Items[i];
    k := ATarget.IndexOfName(name);
    if k >= 0 then tv := ATarget.Items[k] else tv := nil;
    if (sv.JSONType = jtObject) and (tv <> nil) and (tv.JSONType = jtObject) then
      JsMerge(TJSONObject(tv), TJSONObject(sv), AOverwrite)
    else if AOverwrite or (k < 0) then
      TyTlPut(ATarget, name, sv.Clone);
  end;
end;

{ ==================== the preprocessor ==================== }

procedure TransferItem(AOpt: TJSONObject);
var
  d: TJSONData;
  itemStyle, emph, lbl, normal: TJSONObject;
  temp: TJSONObject;
  i, k: Integer;
  name: string;
begin
  { const itemStyle = opt.itemStyle || (opt.itemStyle = an empty object) }
  d := AOpt.Find('itemStyle');
  if TyTlTruthy(d) then itemStyle := ObjOf(d)
  else
  begin
    itemStyle := TJSONObject.Create;
    TyTlPut(AOpt, 'itemStyle', itemStyle);
  end;
  { a truthy item style that is no object: a primitive takes no property }
  if itemStyle = nil then Exit;
  d := itemStyle.Find('emphasis');
  if TyTlTruthy(d) then emph := ObjOf(d)
  else
  begin
    emph := TJSONObject.Create;
    TyTlPut(itemStyle, 'emphasis', emph);
  end;
  { const label = opt.label || (opt.label || an empty object): a label
    nobody wrote is a temporary the option never sees }
  temp := nil;
  d := AOpt.Find('label');
  if TyTlTruthy(d) then lbl := ObjOf(d) else lbl := nil;
  if lbl = nil then
  begin
    if TyTlTruthy(d) then Exit;
    temp := TJSONObject.Create;
    lbl := temp;
  end;
  try
    d := lbl.Find('normal');
    if TyTlTruthy(d) then normal := ObjOf(d)
    else
    begin
      normal := TJSONObject.Create;
      TyTlPut(lbl, 'normal', normal);
    end;
    if normal <> nil then
    begin
      i := 0;
      while i < lbl.Count do
      begin
        name := lbl.Names[i];
        if (name <> 'normal') and (name <> 'emphasis') and (normal.IndexOfName(name) < 0) then
          normal.Add(name, lbl.Items[i].Clone);
        Inc(i);
      end;
    end;
    { the emphasis label out of the item style }
    if (emph <> nil) and TyTlTruthy(emph.Find('label')) and (lbl.IndexOfName('emphasis') < 0) then
    begin
      k := emph.IndexOfName('label');
      lbl.Add('emphasis', emph.Extract(k));
    end;
  finally
    temp.Free;
  end;
end;

procedure CompatibleEC2(AOpt: TJSONObject);
var
  d, cp: TJSONData;
  cs: TJSONObject;
  t: string;
  i: Integer;
  item: TJSONObject;
begin
  d := AOpt.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    t := d.AsString;
    if (t = 'number') or (t = 'time') then
    begin
      if t = 'number' then TyTlPut(AOpt, 'axisType', TJSONString.Create('value'))
      else TyTlPut(AOpt, 'axisType', TJSONString.Create('time'));
      AOpt.Delete('type');
    end;
  end;
  TransferItem(AOpt);
  if AOpt.IndexOfName('controlPosition') >= 0 then
  begin
    cp := AOpt.Find('controlPosition');
    d := AOpt.Find('controlStyle');
    cs := nil;
    if TyTlTruthy(d) then cs := ObjOf(d)
    else
    begin
      cs := TJSONObject.Create;
      TyTlPut(AOpt, 'controlStyle', cs);
    end;
    if cs <> nil then
    begin
      if cs.IndexOfName('position') < 0 then cs.Add('position', cp.Clone);
      d := cs.Find('position');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'none')
        and (cs.IndexOfName('show') < 0) then
      begin
        cs.Add('show', False);
        cs.Delete('position');
      end;
    end;
    AOpt.Delete('controlPosition');
  end;
  d := AOpt.Find('data');
  if d is TJSONArray then
    for i := 0 to d.Count - 1 do
    begin
      item := ObjOf(d.Items[i]);
      if item = nil then Continue;
      if (item.IndexOfName('value') < 0) and (item.IndexOfName('name') >= 0) then
        item.Add('value', item.Find('name').Clone);
      TransferItem(item);
    end;
end;

procedure TyTimelinePreprocess(AOption: TJSONObject);
var
  d: TJSONData;
  i: Integer;
begin
  if AOption = nil then Exit;
  d := AOption.Find('timeline');
  if d is TJSONArray then
  begin
    for i := 0 to d.Count - 1 do
      if d.Items[i] is TJSONObject then CompatibleEC2(TJSONObject(d.Items[i]));
  end
  else if d is TJSONObject then
    CompatibleEC2(TJSONObject(d));
end;

{ ==================== the model ==================== }

function Q(const S: string): string;
begin
  Result := '"' + StringToJSONString(S) + '"';
end;

function TyTimelineDefaultsJson(const AInk: TTyTimelineInk): string;
begin
  { TimelineModel.defaultOption under SliderTimelineModel's
    (inheritDefaultOption): the parent's keys first }
  Result := '{"z":4,"show":true,"axisType":"time","realtime":true,'
    + '"left":"20%","top":null,"right":"20%","bottom":0,"width":null,"height":40,'
    + '"padding":15,"controlPosition":"left","autoPlay":false,"rewind":false,'
    + '"loop":true,"playInterval":2000,"currentIndex":0,'
    + '"itemStyle":{"color":' + Q(AInk.Item) + ',"borderWidth":0},'
    + '"label":{"color":' + Q(AInk.LabelColour) + ',"position":"auto","show":true,'
    + '"interval":"auto","rotate":0},'
    + '"data":[],'
    + '"backgroundColor":"rgba(0,0,0,0)","borderColor":' + Q(AInk.Border) + ',"borderWidth":0,'
    + '"orient":"horizontal","inverse":false,"tooltip":{"trigger":"item"},'
    + '"symbol":"circle","symbolSize":12,'
    + '"lineStyle":{"show":true,"width":2,"color":' + Q(AInk.Line) + '},'
    + '"checkpointStyle":{"symbol":"circle","symbolSize":15,"color":' + Q(AInk.Checkpoint)
    + ',"borderColor":' + Q(AInk.CheckpointBorder) + ',"borderWidth":0,"shadowBlur":0,'
    + '"shadowOffsetX":0,"shadowOffsetY":0,"shadowColor":"rgba(0, 0, 0, 0)",'
    + '"animation":true,"animationDuration":300,"animationEasing":"quinticInOut"},'
    + '"controlStyle":{"show":true,"showPlayBtn":true,"showPrevBtn":true,"showNextBtn":true,'
    + '"itemSize":24,"itemGap":12,"position":"left","playIcon":' + Q(TyTlPlayIcon)
    + ',"stopIcon":' + Q(TyTlStopIcon) + ',"nextIcon":' + Q(TyTlNextIcon)
    + ',"prevIcon":' + Q(TyTlPrevIcon) + ',"prevBtnSize":18,"nextBtnSize":18,'
    + '"color":' + Q(AInk.Control) + ',"borderColor":' + Q(AInk.ControlBorder)
    + ',"borderWidth":0},'
    + '"emphasis":{"label":{"show":true,"color":' + Q(AInk.LabelEmphasis) + '},'
    + '"itemStyle":{"color":' + Q(AInk.ItemEmphasis) + ',"borderColor":'
    + Q(AInk.ItemEmphasisBorder) + '},'
    + '"controlStyle":{"color":' + Q(AInk.ControlEmphasis) + ',"borderColor":'
    + Q(AInk.ControlEmphasisBorder) + '}},'
    + '"progress":{"lineStyle":{"color":' + Q(AInk.Progress) + '},'
    + '"itemStyle":{"color":' + Q(AInk.ProgressItem) + '}}}';
end;

{ hasValue: own, not null, not 'auto' }
function HasValue(AObj: TJSONObject; const AKey: string): Boolean;
var d: TJSONData;
begin
  if AObj = nil then Exit(False);
  d := AObj.Find(AKey);
  Result := NotNull(d) and not ((d.JSONType = jtString) and (d.AsString = 'auto'));
end;

{ layout.mergeLayoutParam for one direction of a box that does not ignore
  its size: ATarget the model's option, ANew the box the option wrote }
procedure MergeLayoutDir(ATarget, ANew: TJSONObject; const ANames: array of string);
var
  merged, params, res: TJSONObject;
  newCount, mergedCount, i: Integer;
  d: TJSONData;
begin
  merged := TJSONObject.Create;
  params := TJSONObject.Create;
  try
    newCount := 0;
    mergedCount := 0;
    for i := 0 to High(ANames) do
    begin
      d := ATarget.Find(ANames[i]);
      if d <> nil then merged.Add(ANames[i], d.Clone);
    end;
    for i := 0 to High(ANames) do
    begin
      d := ANew.Find(ANames[i]);
      if d <> nil then
      begin
        TyTlPut(params, ANames[i], d.Clone);
        TyTlPut(merged, ANames[i], d.Clone);
      end;
      if HasValue(params, ANames[i]) then Inc(newCount);
      if HasValue(merged, ANames[i]) then Inc(mergedCount);
    end;
    if (mergedCount = 2) or (newCount = 0) then res := merged
    else if newCount >= 2 then res := params
    else
    begin
      { the next by priority from the model's option }
      for i := 0 to High(ANames) do
        if (params.IndexOfName(ANames[i]) < 0) and (ATarget.IndexOfName(ANames[i]) >= 0) then
        begin
          params.Add(ANames[i], ATarget.Find(ANames[i]).Clone);
          Break;
        end;
      res := params;
    end;
    { copy: a name the result lacks is undefined -- no key }
    for i := 0 to High(ANames) do
    begin
      d := res.Find(ANames[i]);
      if d <> nil then TyTlPut(ATarget, ANames[i], d.Clone)
      else if ATarget.IndexOfName(ANames[i]) >= 0 then ATarget.Delete(ANames[i]);
    end;
  finally
    merged.Free;
    params.Free;
  end;
end;

function TyTimelineFullOption(ANode: TJSONObject; const AInk: TTyTimelineInk): TJSONObject;
var
  defs: TJSONData;
  own: TJSONObject;
  k: Integer;
const
  cBox: array[0..5] of string = ('left', 'top', 'right', 'bottom', 'width', 'height');
begin
  if ANode <> nil then Result := TJSONObject(ANode.Clone)
  else Result := TJSONObject.Create;
  defs := GetJSON(TyTimelineDefaultsJson(AInk));
  own := TJSONObject.Create;
  try
    { getLayoutParams: the box keys the option owns }
    if ANode <> nil then
      for k := 0 to High(cBox) do
        if ANode.IndexOfName(cBox[k]) >= 0 then own.Add(cBox[k], ANode.Find(cBox[k]).Clone);
    JsMerge(Result, TJSONObject(defs), False);
    MergeLayoutDir(Result, own, ['width', 'left', 'right']);
    MergeLayoutDir(Result, own, ['height', 'top', 'bottom']);
  finally
    own.Free;
    defs.Free;
  end;
end;

function DataValueOf(A: TJSONData): TTyDataValue;
begin
  if A = nil then Exit(TyDataNone);
  case A.JSONType of
    jtNumber: Result := TyDataNum(A.AsFloat);
    jtString: Result := TyDataText(A.AsString);
    jtBoolean: Result := TyDataBool(A.AsBoolean);
  else
    Result := TyDataNone;
  end;
end;

{ convertOptionIdName(v, ''): a string as it is, a number as it prints,
  anything else '' }
function IdNameOf(A: TJSONData): string;
begin
  Result := '';
  if A = nil then Exit;
  case A.JSONType of
    jtString: Result := A.AsString;
    jtNumber: Result := TyJsNumberToString(A.AsFloat);
  end;
end;

procedure TyTimelineData(AFull: TJSONObject; AUseUTC: Boolean;
  out AValues: TTyDoubleArray; out ANames: TTyStringArray; out AItems: TTyJsonObjArray);
var
  d, raw: TJSONData;
  i, n: Integer;
  axisType: string;
  ty: TTyDimType;
begin
  AValues := nil;
  ANames := nil;
  AItems := nil;
  if AFull = nil then Exit;
  d := AFull.Find('data');
  if not (d is TJSONArray) then Exit;
  n := d.Count;
  SetLength(AValues, n);
  SetLength(AItems, n);
  axisType := StrOf(AFull.Find('axisType'));
  if axisType = 'time' then ty := ddtTime else ty := ddtFloat;
  for i := 0 to n - 1 do
  begin
    raw := d.Items[i];
    AItems[i] := ObjOf(raw);
    { getDataItemValue: an object's value; a list's first cell (the one
      dimension) }
    if AItems[i] <> nil then raw := AItems[i].Find('value');
    if axisType = 'category' then
    begin
      SetLength(ANames, n);
      ANames[i] := IdNameOf(raw);
      AValues[i] := i;
      Continue;
    end;
    if (raw <> nil) and (raw.JSONType = jtArray) then
    begin
      if raw.Count > 0 then raw := raw.Items[0] else raw := nil;
    end;
    AValues[i] := TyParseDataValue(DataValueOf(raw), ty);
  end;
end;

function JsMod(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) or IsInfinite(A) or (B = 0) then Exit(NaN);
  if IsInfinite(B) then Exit(A);
  Result := A - B * Int(A / B);
end;

function TyTimelineNormIndex(AIndex: Double; ACount: Integer; ALoop: Boolean): Double;
begin
  Result := AIndex;
  if ALoop then
    Result := JsMod(JsMod(AIndex, ACount) + ACount, ACount)
  else
  begin
    if Result >= ACount then Result := ACount - 1;
    if Result < 0 then Result := 0;
  end;
end;

{ ==================== the styles ==================== }

const
  cItemKeys: array[0..12, 0..1] of string = (('fill', 'color'),
    ('stroke', 'borderColor'), ('lineWidth', 'borderWidth'), ('opacity', 'opacity'),
    ('shadowBlur', 'shadowBlur'), ('shadowOffsetX', 'shadowOffsetX'),
    ('shadowOffsetY', 'shadowOffsetY'), ('shadowColor', 'shadowColor'),
    ('lineDash', 'borderType'), ('lineDashOffset', 'borderDashOffset'),
    ('lineCap', 'borderCap'), ('lineJoin', 'borderJoin'),
    ('miterLimit', 'borderMiterLimit'));
  cLineKeys: array[0..11, 0..1] of string = (('lineWidth', 'width'),
    ('stroke', 'color'), ('opacity', 'opacity'), ('shadowBlur', 'shadowBlur'),
    ('shadowOffsetX', 'shadowOffsetX'), ('shadowOffsetY', 'shadowOffsetY'),
    ('shadowColor', 'shadowColor'), ('lineDash', 'type'),
    ('lineDashOffset', 'dashOffset'), ('lineCap', 'cap'), ('lineJoin', 'join'),
    ('miterLimit', 'miterLimit'));

{ getItemStyle(excludes): the keys a chain of item style options holds }
function ItemStyleOf(const AChain: array of TJSONObject; AExcludeColour: Boolean): TJSONObject;
var
  i: Integer;
  d: TJSONData;
begin
  Result := TJSONObject.Create;
  for i := 0 to High(cItemKeys) do
  begin
    if AExcludeColour and (cItemKeys[i, 1] = 'color') then Continue;
    d := ChainGet(AChain, cItemKeys[i, 1]);
    if d <> nil then Result.Add(cItemKeys[i, 0], d.Clone);
  end;
end;

function LineStyleOf(AModel: TJSONObject): TJSONObject;
var
  i: Integer;
  d: TJSONData;
begin
  Result := TJSONObject.Create;
  for i := 0 to High(cLineKeys) do
  begin
    d := ChainGet([AModel], cLineKeys[i, 1]);
    if d <> nil then Result.Add(cLineKeys[i, 0], d.Clone);
  end;
end;

{ createTextStyle(model, specified) as labelStyle.ts makes it for a plain
  label that is no state (setTextStyleCommon, setTokenTextStyle): AGlobal
  is the root's textStyle over the global default }
function TextStyleOf(const AChain: array of TJSONObject; AGlobal: TJSONObject): TJSONObject;
const
  cWithGlobal: array[0..7] of string = ('fontStyle', 'fontWeight', 'fontSize',
    'fontFamily', 'textShadowColor', 'textShadowBlur', 'textShadowOffsetX',
    'textShadowOffsetY');
  cSelf: array[0..6] of string = ('align', 'lineHeight', 'width', 'height', 'tag',
    'verticalAlign', 'ellipsis');
  cBox: array[0..9] of string = ('padding', 'borderWidth', 'borderRadius',
    'borderDashOffset', 'backgroundColor', 'borderColor', 'shadowColor',
    'shadowBlur', 'shadowOffsetX', 'shadowOffsetY');
var
  d, g: TJSONData;
  i: Integer;
  s: string;

  function Glob(const AKey: string): TJSONData;
  begin
    if AGlobal = nil then Exit(nil);
    Result := AGlobal.Find(AKey);
    if not NotNull(Result) then Result := nil;
  end;

begin
  Result := TJSONObject.Create;
  d := ChainGet(AChain, 'overflow');
  if TyTlTruthy(d) then Result.Add('overflow', d.Clone);
  d := ChainGet(AChain, 'lineOverflow');
  if TyTlTruthy(d) then Result.Add('lineOverflow', d.Clone);
  { the fill: 'inherit' and 'auto' are nothing without an inherit colour;
    a free text falls back to the global colour }
  d := ChainGet(AChain, 'color');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    s := d.AsString;
    if (s = 'inherit') or (s = 'auto') then d := nil;
  end;
  if not TyTlTruthy(d) then
  begin
    g := Glob('color');
    if TyTlTruthy(g) then d := g;
  end;
  if d <> nil then Result.Add('fill', d.Clone);
  d := ChainGet(AChain, 'textBorderColor');
  if (d <> nil) and (d.JSONType = jtString) and ((d.AsString = 'inherit') or (d.AsString = 'auto')) then
    d := nil;
  if not TyTlTruthy(d) then
  begin
    g := Glob('textBorderColor');
    if TyTlTruthy(g) then d := g;
  end;
  if d <> nil then Result.Add('stroke', d.Clone);
  d := ChainGet(AChain, 'textBorderWidth');
  if d = nil then d := Glob('textBorderWidth');
  if d <> nil then Result.Add('lineWidth', d.Clone);
  d := ChainGet(AChain, 'textBorderType');
  if d = nil then d := Glob('textBorderType');
  if d <> nil then Result.Add('lineDash', d.Clone);
  d := ChainGet(AChain, 'textBorderDashOffset');
  if d = nil then d := Glob('textBorderDashOffset');
  if d <> nil then Result.Add('lineDashOffset', d.Clone);
  d := ChainGet(AChain, 'opacity');
  if d = nil then d := Glob('opacity');
  if d <> nil then Result.Add('opacity', d.Clone);
  for i := 0 to High(cWithGlobal) do
  begin
    d := ChainGet(AChain, cWithGlobal[i]);
    if d = nil then d := Glob(cWithGlobal[i]);
    if d <> nil then Result.Add(cWithGlobal[i], d.Clone);
  end;
  for i := 0 to High(cSelf) do
  begin
    d := ChainGet(AChain, cSelf[i]);
    if d <> nil then Result.Add(cSelf[i], d.Clone);
  end;
  if Result.IndexOfName('verticalAlign') < 0 then
  begin
    d := ChainGet(AChain, 'baseline');
    if d <> nil then Result.Add('verticalAlign', d.Clone);
  end;
  for i := 0 to High(cBox) do
  begin
    d := ChainGet(AChain, cBox[i]);
    if d <> nil then Result.Add(cBox[i], d.Clone);
  end;
  d := ChainGet(AChain, 'borderType');
  if d <> nil then Result.Add('borderDash', d.Clone);
end;

{ a style object as a state's flattened props under 'style.' }
procedure StyleProps(AStyle: TJSONObject; var AState: TTyAnimState);
var i: Integer;
begin
  if AStyle = nil then Exit;
  AState.HasStyle := True;
  for i := 0 to AStyle.Count - 1 do
    TyAnimPropPut(AState.Props, 'style.' + AStyle.Names[i], TyGfxAnimOf(AStyle.Items[i]));
end;

{ echarts' parsePercent: the position words, a '%' text of AAll, other text
  parseFloat, null NaN, anything else its number }
function EcParsePercent(A: TJSONData; AAll: Double): Double;
var s: string;
begin
  if A = nil then Exit(NaN);
  if A.JSONType = jtString then
  begin
    s := A.AsString;
    if (s = 'center') or (s = 'middle') then s := '50%'
    else if (s = 'left') or (s = 'top') then s := '0%'
    else if (s = 'right') or (s = 'bottom') then s := '100%';
    if (Length(TyJsTrim(s)) > 0) and (TyJsTrim(s)[Length(TyJsTrim(s))] = '%') then
      Exit(TyJsParseFloat(s) / 100 * AAll);
    Exit(TyJsParseFloat(s));
  end;
  if A.JSONType = jtNull then Exit(NaN);
  Result := JsNum(A);
end;

{ zrender's parsePercent (contain/text) }
function ZrParsePercent(A: TJSONData; AMax: Double): Double;
var s: string;
begin
  if (A <> nil) and (A.JSONType = jtString) then
  begin
    s := A.AsString;
    if LastDelimiter('%', s) > 0 then Exit(TyJsParseFloat(s) / 100 * AMax);
    Exit(TyJsParseFloat(s));
  end;
  Result := JsNum(A);
end;

{ ==================== the view ==================== }

constructor TTyTimelineView.Create(const AUid: string);
begin
  inherited Create;
  Uid := AUid;
  Root := TyGfxCreate('group');
  CurrentIndex := NaN;
  FEmpty := TJSONObject.Create;
end;

destructor TTyTimelineView.Destroy;
begin
  DropGroups;
  FreeAndNil(Checkpoint);
  FreeAndNil(Root);
  FreeAndNil(FFull);
  FreeAndNil(FEmpty);
  inherited Destroy;
end;

procedure TTyTimelineView.DropGroups;
var i: Integer;
begin
  { the checkpoint outlives its group }
  if (Checkpoint <> nil) and (Checkpoint.Parent <> nil) then TyGfxRemoveChild(Checkpoint.Parent, Checkpoint);
  for i := High(Root.Children) downto 0 do
    Root.Children[i].Free;
  Root.Children := nil;
  MainGroup := nil;
  LabelGroup := nil;
  ProgressLine := nil;
  Els := nil;
  Roles := nil;
  Hover := nil;
  FEmph := nil;
  FProg := nil;
  FHasEmph := nil;
  FHasProg := nil;
  FInProg := nil;
  FLabelValue := nil;
  FBaseZ2 := nil;
end;

procedure TTyTimelineView.Remove;
begin
  DropGroups;
  Shown := False;
  Inc(Gen);
end;

function TTyTimelineView.ItemAt(AValue: Double): TJSONObject;
begin
  { data.getItemModel(idx): an index outside the data, or none, is no item }
  if IsNan(AValue) or IsInfinite(AValue) or (Frac(AValue) <> 0) or (AValue < 0)
    or (AValue >= Length(FItems)) then Exit(nil);
  Result := FItems[Trunc(AValue)];
end;

procedure TTyTimelineView.AddEl(AEl: TTyGfxEl; AKind: TTyTlRoleKind;
  AIndex: Integer; AValue: Double);
var n: Integer;
begin
  n := Length(Els);
  SetLength(Els, n + 1);
  SetLength(Roles, n + 1);
  SetLength(Hover, n + 1);
  SetLength(FEmph, n + 1);
  SetLength(FProg, n + 1);
  SetLength(FHasEmph, n + 1);
  SetLength(FHasProg, n + 1);
  SetLength(FInProg, n + 1);
  SetLength(FLabelValue, n + 1);
  SetLength(FBaseZ2, n + 1);
  Els[n] := AEl;
  FBaseZ2[n] := AEl.Z2;
  Roles[n].Kind := AKind;
  Roles[n].Index := AIndex;
  Roles[n].Value := AValue;
  Hover[n] := False;
  FEmph[n] := Default(TTyAnimState);
  FProg[n] := Default(TTyAnimState);
  FHasEmph[n] := False;
  FHasProg[n] := False;
  FInProg[n] := False;
  FLabelValue[n] := AValue;
end;

function TTyTimelineView.RoleOf(AIndex: Integer): TTyTlRole;
begin
  Result := Roles[AIndex];
end;

function TTyTimelineView.DataToCoord(AValue: Double): Double;
var n, e0, e1, d0, d1, r0, r1: Double;
begin
  { scale.parse: a time scale rounds a number }
  if FAxisType = 'time' then AValue := TyJsRound(AValue);
  e0 := FExtent[0];
  e1 := FExtent[1];
  { the linear mapper's normalize }
  if e1 = e0 then n := cHalf
  else n := (AValue - e0) / (e1 - e0);
  { linearMap(n, [0, 1], extent) }
  d0 := 0;
  d1 := 1;
  r0 := AxisExtent[0];
  r1 := AxisExtent[1];
  if n = d0 then Exit(r0);
  if n = d1 then Exit(r1);
  Result := (n - d0) / (d1 - d0) * (r1 - r0) + r0;
end;

function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

{ `x || 0` }
function OrZero(A: Double): Double;
begin
  if IsNan(A) or (A = 0) then Result := 0 else Result := A;
end;

function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

procedure TTyTimelineView.Render(ANode, ARoot: TJSONObject; AW, AH: Double;
  const AInk: TTyTimelineInk; const AMeasurer: ITyTextMeasurer;
  const AAnim: TTyTlAnimCfg; AUseUTC: Boolean);
type
  TLabelPos = (lpPlus, lpMinus, lpUndefined, lpNumber);
var
  fo, lbl, ctl, gtext, st, t: TJSONObject;
  d: TJSONData;
  orient, s, cPos, iconName, icon: string;
  i, k, n, nData: Integer;
  viewRect, r, mainR, labelR: TTyXYWH;
  box: TTyRawBox;
  pad: array[0..3] of Double;
  labelPos: TLabelPos;
  labelPosNum, controlSize, controlGap, sizePlusGap, labelRotation, rotation,
    xLeft, xRight, v, coord, iconSize, toCoord, dur: Double;
  showControl, showPlay, showPrev, showNext, hasPlay, hasPrev, hasNext: Boolean;
  playPos, prevPos, nextPos: Double;
  labelAlign, labelBaseline: string;
  line, el: TTyGfxEl;
  path: TTyZrPath;
  m: TTyMat2D;
  mainPos, labelsPos: array[0..1] of Double;
  vb, mb, lb: array[0..1, 0..1] of Double;
  rx, ry, aa, ac, atx, ab, ad, aty, sn, cs: Double;
  idx: Integer;
  lw: TTyAnimValue;
  tickValues: TTyDoubleArray;
  texts: TTyStringArray;
  off: TTyBoolArray;
  built: TTyIntegerArray;
  widths, heights: TTyDoubleArray;
  fontPx, interval: Double;
  fontName: string;
  w, h: Double;
  props: TTyAnimProps;
  cfg: TTyAnimCfg;

  function NumOr(A: TJSONData; ADefault: Double): Double;
  begin
    if (A <> nil) and (A.JSONType = jtNumber) then Result := A.AsFloat
    else Result := ADefault;
  end;

  function LabelOf(AValue: Double; AIndex: Integer): string;
  var fmt: TJSONData; lab: string; tf: TTyTimeLabelFormatter;
  begin
    fmt := lbl.Find('formatter');
    if not NotNull(fmt) then fmt := nil;
    if FAxisType = 'time' then
    begin
      { leveledFormat: a string a template for every unit; else the
        dictionary's entry of the value's own unit }
      if (fmt <> nil) and (fmt.JSONType = jtString) and TyChartIsHandlerRef(fmt.AsString) then
        fmt := nil;
      tf := TyTimeLabelFormatterOf(fmt);
      Exit(TyTimeLeveledLabel(tf, AValue, TyTimeUnitOf(AValue, AUseUTC), 0, AUseUTC));
    end;
    if FAxisType = 'category' then
    begin
      { OrdinalScale.getLabel }
      if (AValue >= 0) and (AValue < Length(Names)) and (Frac(AValue) = 0) then
        lab := Names[Trunc(AValue)]
      else
        lab := '';
    end
    else
      { IntervalScale.getLabel: the value's own precision, addCommas }
      lab := TyJsAddCommas(TyJsToFixedStr(AValue, TyGetPrecision(AValue)));
    if (fmt <> nil) and (fmt.JSONType = jtString) and not TyChartIsHandlerRef(fmt.AsString) then
      Result := TyJsReplaceFirst(fmt.AsString, '{value}', lab)
    else
      Result := lab;
  end;

  { pointerMoveTo }
  procedure PointerMoveTo(ANoAnimation: Boolean);
  var
    cp: TJSONObject;
    ci: Double;
    pr: TTyAnimProps;
  begin
    if Dragging then Exit;
    cp := Sub(fo, 'checkpointStyle');
    ci := CurrentIndex;
    if (not IsNan(ci)) and (Frac(ci) = 0) and (ci >= 0) and (ci < nData) then
      toCoord := DataToCoord(Values[Trunc(ci)])
    else
      toCoord := NaN;
    if ANoAnimation or not AAnim.Allowed or not TyTlTruthy(ChainGet([cp], 'animation')) then
    begin
      Checkpoint.X := toCoord;
      Checkpoint.Y := 0;
      if ProgressLine <> nil then
        TyTlPut(ProgressLine.Shape, 'x2', TJSONFloatNumber.Create(toCoord));
    end
    else
    begin
      dur := NumOr(cp.Find('animationDuration'), NaN);
      cfg := TyAnimCfg(dur, 0, StrOf(cp.Find('animationEasing')));
      cfg.HasDuration := NotNull(cp.Find('animationDuration'));
      { animateTo's delay is `cfg.delay || 0` }
      Checkpoint.StopAnimation('', True);
      pr := nil;
      TyAnimPropPut(pr, 'x', TyAnimNum(toCoord));
      TyAnimPropPut(pr, 'y', TyAnimNum(0));
      Checkpoint.AnimateTo(pr, cfg);
      if ProgressLine <> nil then
      begin
        pr := nil;
        TyAnimPropPut(pr, 'shape.x2', TyAnimNum(toCoord));
        ProgressLine.AnimateTo(pr, cfg);
      end;
    end;
  end;

  { giveSymbol: a new symbol, or the kept checkpoint updated }
  function GiveSymbol(const AHost, AStyle: array of TJSONObject; AGroup: TTyGfxEl;
    AHasX: Boolean; AX, AY: Double; AExisting: TTyGfxEl; AIsPointer: Boolean): TTyGfxEl;
  var
    colour, sym, sz, so, rot: TJSONData;
    stype: string;
    isEmpty: Boolean;
    sx, sy, ox, oy: Double;
    sty: TJSONObject;
  begin
    colour := ChainGet(AStyle, 'color');
    if AExisting = nil then
    begin
      sym := ChainGet(AHost, 'symbol');
      stype := StrOf(sym);
      Result := TTyGfxEl.Create(gkPath, 'path');
      isEmpty := Copy(stype, 1, 5) = 'empty';
      if isEmpty then stype := LowerCase(Copy(stype, 6, 1)) + Copy(stype, 7, MaxInt);
      if Copy(stype, 1, 7) = 'path://' then
        Result.PathData := TyZrMakePathCover(Copy(stype, 8, MaxInt), TyXYWH(-1, -1, 2, 2))
      else if (stype <> 'none') and (Copy(stype, 1, 8) <> 'image://') then
        Result.PathData := TyZrSymbol(stype, -1, -1, 2, 2);
      { the Path's own style: fill '#000' by its prototype; what setColor
        asks again -- __isEmptyBrush, shape.symbolType 'line' -- in the
        name }
      if isEmpty then Result.Name := 'empty'
      else if stype = 'line' then Result.Name := 'line';
      { setColor, when a colour was given }
      if TyTlTruthy(colour) then
      begin
        if isEmpty then
        begin
          TyTlPut(Result.Style, 'stroke', colour.Clone);
          TyTlPut(Result.Style, 'fill', TJSONString.Create(AInk.EmptyFill));
          TyTlPut(Result.Style, 'lineWidth', TJSONIntegerNumber.Create(2));
        end
        else if stype = 'line' then
          TyTlPut(Result.Style, 'stroke', colour.Clone)
        else
          TyTlPut(Result.Style, 'fill', colour.Clone);
      end;
      TyTlPut(Result.Style, 'strokeNoScale', TJSONBoolean.Create(True));
      TyGfxAddChild(AGroup, Result);
      Result.Animation := AAnim.Driver;
      { onCreate: the checkpoint put at its tick, no animation }
      if AIsPointer then
      begin
        Checkpoint := Result;
        PointerMoveTo(True);
      end;
    end
    else
    begin
      Result := AExisting;
      { setColor(color): a colour of undefined is written as one }
      if Result.Name = 'empty' then
      begin
        if colour <> nil then TyTlPut(Result.Style, 'stroke', colour.Clone)
        else TyTlPut(Result.Style, 'stroke', TJSONNull.Create);
        TyTlPut(Result.Style, 'fill', TJSONString.Create(AInk.EmptyFill));
        TyTlPut(Result.Style, 'lineWidth', TJSONIntegerNumber.Create(2));
      end
      else if Result.Name = 'line' then
      begin
        if colour <> nil then TyTlPut(Result.Style, 'stroke', colour.Clone)
        else TyTlPut(Result.Style, 'stroke', TJSONNull.Create);
      end
      else if colour <> nil then TyTlPut(Result.Style, 'fill', colour.Clone)
      else TyTlPut(Result.Style, 'fill', TJSONNull.Create);
      { Group may be new, also need to add }
      TyGfxAddChild(AGroup, Result);
      { onUpdate: to its tick, sliding }
      if AIsPointer then PointerMoveTo(False);
    end;
    { the item style without its colour }
    sty := ItemStyleOf(AStyle, True);
    try
      TyGfxSetStyle(Result, sty);
    finally
      sty.Free;
    end;
    Result.Z2 := 100;
    if AHasX then
    begin
      Result.X := AX;
      Result.Y := AY;
    end;
    { normalizeSymbolSize }
    sz := ChainGet(AHost, 'symbolSize');
    if sz is TJSONArray then
    begin
      if sz.Count > 0 then sx := JsNum(sz.Items[0]) else sx := NaN;
      if sz.Count > 1 then sy := JsNum(sz.Items[1]) else sy := NaN;
    end
    else
    begin
      sx := JsNum(sz);
      if sz = nil then sx := NaN;
      sy := sx;
    end;
    if IsNan(sx) then sx := 0;
    if IsNan(sy) then sy := 0;
    Result.ScaleX := sx / 2;
    Result.ScaleY := sy / 2;
    { normalizeSymbolOffset: written, the x / y moved by it }
    so := ChainGet(AHost, 'symbolOffset');
    if so <> nil then
    begin
      if so is TJSONArray then
      begin
        if so.Count > 0 then ox := EcParsePercent(so.Items[0], sx) else ox := NaN;
        if (so.Count > 1) and NotNull(so.Items[1]) then oy := EcParsePercent(so.Items[1], sy)
        else if so.Count > 0 then oy := EcParsePercent(so.Items[0], sy)
        else oy := NaN;
      end
      else
      begin
        ox := EcParsePercent(so, sx);
        oy := EcParsePercent(so, sy);
      end;
      if IsNan(ox) then ox := 0;
      if IsNan(oy) then oy := 0;
      { opt.x = (opt.x || 0) + offset }
      if AHasX then
      begin
        Result.X := OrZero(AX) + ox;
        Result.Y := OrZero(AY) + oy;
      end
      else
      begin
        Result.X := 0 + ox;
        Result.Y := 0 + oy;
      end;
    end;
    { rotation: (symbolRotate || 0) * PI / 180 || 0 }
    rot := ChainGet(AHost, 'symbolRotate');
    Result.Rotation := JsNum(rot);
    if (rot = nil) or IsNan(Result.Rotation) then Result.Rotation := 0;
    Result.Rotation := Result.Rotation * Pi / cDeg;
    if IsNan(Result.Rotation) then Result.Rotation := 0;
    Result.Animation := AAnim.Driver;
    { updateTransform with the new group's transform still null }
    TyGfxUpdateTransforms(Result);
  end;

  procedure MakeBtn(APos: Double; const AName: string; AKind: TTyTlRoleKind;
    AWillRotate: Boolean);
  var
    sty: TJSONObject;
    e: TTyAnimState;
  begin
    iconSize := ZrParsePercent(ChainGet([ctl], AName + 'BtnSize'), controlSize);
    if ChainGet([ctl], AName + 'BtnSize') = nil then iconSize := controlSize;
    icon := StrOf(ctl.Find(AName + 'Icon'));
    el := TTyGfxEl.Create(gkPath, 'path');
    { createIcon: an image draws nothing here; a path is fitted into the
      button's box, centred }
    if (icon <> '') and (Copy(icon, 1, 8) <> 'image://') then
      el.PathData := TyZrMakePathCenter(TyJsReplaceFirst(icon, 'path://', ''),
        TyXYWH(0, -iconSize / 2, iconSize, iconSize));
    el.X := APos;
    el.Y := 0;
    el.OriginX := controlSize / 2;
    el.OriginY := 0;
    if AWillRotate then el.Rotation := -rotation else el.Rotation := 0;
    el.Style.Add('strokeNoScale', True);
    sty := ItemStyleOf([ctl], False);
    try
      TyGfxSetStyle(el, sty);
    finally
      sty.Free;
    end;
    el.Animation := AAnim.Driver;
    TyGfxAddChild(MainGroup, el);
    AddEl(el, AKind, -1, NaN);
    sty := ItemStyleOf([Sub(Sub(fo, 'emphasis'), 'controlStyle')], False);
    try
      e := Default(TTyAnimState);
      StyleProps(sty, e);
      FEmph[High(Els)] := e;
      FHasEmph[High(Els)] := True;
    finally
      sty.Free;
    end;
  end;

  function GetBound(const R: TTyXYWH; ADim, AIdx: Integer): Double;
  begin
    if ADim = 0 then
    begin
      if AIdx = 0 then Result := R.X else Result := R.X + R.W;
    end
    else if AIdx = 0 then Result := R.Y
    else Result := R.Y + R.H;
  end;

begin
  DropGroups;
  Inc(Gen);
  FreeAndNil(FFull);
  FFull := TyTimelineFullOption(ANode, AInk);
  fo := FFull;
  FUseUTC := AUseUTC;
  FAxisType := StrOf(fo.Find('axisType'));
  if (FAxisType <> 'category') and (FAxisType <> 'time') then FAxisType := 'value';
  { the model the chart reads whatever is drawn }
  TyTimelineData(fo, AUseUTC, Values, Names, FItems);
  { _initData decides the names by the option's axisType as written }
  nData := Length(Values);
  Count := nData;
  d := fo.Find('currentIndex');
  if (d <> nil) and (d.JSONType = jtNumber) then CurrentIndex := d.AsFloat
  else CurrentIndex := NaN;
  PlayState := TyTlTruthy(fo.Find('autoPlay'));
  Loop := TyTlTruthy(fo.Find('loop'));
  Rewind := TyTlTruthy(fo.Find('rewind'));
  Realtime := TyTlTruthy(fo.Find('realtime'));
  Inverse := TyTlTruthy(fo.Find('inverse'));
  PlayInterval := JsNum(fo.Find('playInterval'));
  if (fo.Find('playInterval') = nil) or IsNan(PlayInterval) then PlayInterval := 0;
  { retrieveZInfo: `|| 0` }
  Z := JsNum(fo.Find('z'));
  if (fo.Find('z') = nil) or IsNan(Z) then Z := 0;
  ZLevel := JsNum(fo.Find('zlevel'));
  if (fo.Find('zlevel') = nil) or IsNan(ZLevel) then ZLevel := 0;
  Shown := TyTlTruthy(fo.Find('show'));
  if not Shown then Exit;

  { ---------------- _layout ---------------- }
  lbl := Sub(fo, 'label');
  { a label written null: nothing in it }
  if lbl = nil then lbl := FEmpty;
  orient := StrOf(fo.Find('orient'));
  Vertical := orient = 'vertical';
  box.Left := TyBoxRawOf(fo.Find('left'));
  box.Top := TyBoxRawOf(fo.Find('top'));
  box.Right := TyBoxRawOf(fo.Find('right'));
  box.Bottom := TyBoxRawOf(fo.Find('bottom'));
  box.Width := TyBoxRawOf(fo.Find('width'));
  box.Height := TyBoxRawOf(fo.Find('height'));
  { normalizeCssArray(padding || 0) }
  d := fo.Find('padding');
  if not TyTlTruthy(d) then
  begin
    for k := 0 to 3 do pad[k] := 0;
  end
  else if d.JSONType = jtNumber then
  begin
    for k := 0 to 3 do pad[k] := d.AsFloat;
  end
  else if d is TJSONArray then
  begin
    for k := 0 to 3 do pad[k] := NaN;
    if d.Count = 2 then
    begin
      pad[0] := JsNum(d.Items[0]); pad[1] := JsNum(d.Items[1]);
      pad[2] := pad[0]; pad[3] := pad[1];
    end
    else if d.Count = 3 then
    begin
      pad[0] := JsNum(d.Items[0]); pad[1] := JsNum(d.Items[1]);
      pad[2] := JsNum(d.Items[2]); pad[3] := pad[1];
    end
    else
      for k := 0 to Min(3, d.Count - 1) do pad[k] := JsNum(d.Items[k]);
  end
  else
    for k := 0 to 3 do pad[k] := NaN;
  viewRect := TyGetLayoutRect(box, 0, 0, AW, AH, pad);
  { the label's place }
  d := lbl.Find('position');
  labelPosNum := 0;
  if (d = nil) or (d.JSONType = jtNull) or ((d.JSONType = jtString) and (d.AsString = 'auto')) then
  begin
    if not Vertical then
    begin
      if viewRect.Y + viewRect.H / 2 < AH / 2 then labelPos := lpMinus else labelPos := lpPlus;
    end
    else if viewRect.X + viewRect.W / 2 < AW / 2 then labelPos := lpPlus
    else labelPos := lpMinus;
  end
  else if d.JSONType = jtString then
  begin
    s := d.AsString;
    labelPos := lpUndefined;
    if Vertical then
    begin
      if s = 'left' then labelPos := lpMinus
      else if s = 'right' then labelPos := lpPlus;
    end
    else if s = 'top' then labelPos := lpMinus
    else if s = 'bottom' then labelPos := lpPlus;
  end
  else
  begin
    labelPos := lpNumber;
    labelPosNum := JsNum(d);
  end;
  if Vertical then
  begin
    if (labelPos = lpPlus) or ((labelPos = lpNumber) and (labelPosNum >= 0)) then
      labelAlign := 'left'
    else
      labelAlign := 'right';
    labelBaseline := 'middle';
    rotation := Pi / 2;
  end
  else
  begin
    labelAlign := 'center';
    if (labelPos = lpPlus) or ((labelPos = lpNumber) and (labelPosNum >= 0)) then
      labelBaseline := 'top'
    else
      labelBaseline := 'bottom';
    rotation := 0;
  end;
  s := StrOf(lbl.Find('align'));
  if TyTlTruthy(lbl.Find('align')) then labelAlign := s;
  if TyTlTruthy(lbl.Find('verticalAlign')) then labelBaseline := StrOf(lbl.Find('verticalAlign'))
  else if TyTlTruthy(lbl.Find('baseline')) then labelBaseline := StrOf(lbl.Find('baseline'));
  { the controls }
  ctl := Sub(fo, 'controlStyle');
  if ctl = nil then ctl := FEmpty;
  showControl := TyTlTruthy(ctl.Find('show'));
  if showControl then
  begin
    controlSize := JsNum(ctl.Find('itemSize'));
    controlGap := JsNum(ctl.Find('itemGap'));
  end
  else
  begin
    controlSize := 0;
    controlGap := 0;
  end;
  sizePlusGap := controlSize + controlGap;
  labelRotation := JsNum(lbl.Find('rotate'));
  if not TyTlTruthy(lbl.Find('rotate')) then labelRotation := 0;
  labelRotation := labelRotation * Pi / cDeg;
  cPos := StrOf(ctl.Find('position'));
  showPlay := showControl and TyTlTruthy(ctl.Find('showPlayBtn'));
  showPrev := showControl and TyTlTruthy(ctl.Find('showPrevBtn'));
  showNext := showControl and TyTlTruthy(ctl.Find('showNextBtn'));
  if Vertical then xRight := viewRect.H else xRight := viewRect.W;
  xLeft := 0;
  hasPlay := False;
  hasPrev := False;
  hasNext := False;
  playPos := 0;
  prevPos := 0;
  nextPos := 0;
  if (cPos = 'left') or (cPos = 'bottom') then
  begin
    if showPlay then begin hasPlay := True; playPos := 0; xLeft := xLeft + sizePlusGap; end;
    if showPrev then begin hasPrev := True; prevPos := xLeft; xLeft := xLeft + sizePlusGap; end;
    if showNext then begin hasNext := True; nextPos := xRight - controlSize; xRight := xRight - sizePlusGap; end;
  end
  else
  begin
    if showPlay then begin hasPlay := True; playPos := xRight - controlSize; xRight := xRight - sizePlusGap; end;
    if showPrev then begin hasPrev := True; prevPos := 0; xLeft := xLeft + sizePlusGap; end;
    if showNext then begin hasNext := True; nextPos := xRight - controlSize; xRight := xRight - sizePlusGap; end;
  end;
  AxisExtent[0] := xLeft;
  AxisExtent[1] := xRight;
  if TyTlTruthy(fo.Find('inverse')) then
  begin
    AxisExtent[0] := xRight;
    AxisExtent[1] := xLeft;
  end;

  { ---------------- _createAxis: the scale on the data's extent ---------------- }
  FExtent[0] := Infinity;
  FExtent[1] := NegInfinity;
  for i := 0 to nData - 1 do
  begin
    v := Values[i];
    if IsNan(v) then Continue;
    if v < FExtent[0] then FExtent[0] := v;
    if v > FExtent[1] then FExtent[1] := v;
  end;
  if FAxisType = 'time' then
  begin
    { calcNiceForTimeScale: one instant spread a day each way }
    if FExtent[0] = FExtent[1] then
    begin
      FExtent[0] := FExtent[0] - 86400000;
      FExtent[1] := FExtent[1] + 86400000;
    end;
  end
  else if FAxisType = 'value' then
  begin
    { intervalScaleEnsureValidExtent with both ends fixed }
    if FExtent[0] = FExtent[1] then
    begin
      if FExtent[0] <> 0 then FExtent[0] := FExtent[0] - Abs(FExtent[0]) / 2
      else FExtent[1] := 1;
    end;
  end;
  SetLength(tickValues, nData);
  for i := 0 to nData - 1 do tickValues[i] := Values[i];

  { ---------------- the groups ---------------- }
  MainGroup := TyGfxCreate('group');
  LabelGroup := TyGfxCreate('group');
  TyGfxAddChild(Root, MainGroup);
  TyGfxAddChild(Root, LabelGroup);

  { ---------------- _renderAxisLine ---------------- }
  ProgressLine := nil;
  if TyTlTruthy(ChainGet([Sub(fo, 'lineStyle')], 'show')) then
  begin
    line := TyGfxCreate('line');
    TyTlPut(line.Shape, 'x1', TJSONFloatNumber.Create(AxisExtent[0]));
    TyTlPut(line.Shape, 'y1', TJSONIntegerNumber.Create(0));
    TyTlPut(line.Shape, 'x2', TJSONFloatNumber.Create(AxisExtent[1]));
    TyTlPut(line.Shape, 'y2', TJSONIntegerNumber.Create(0));
    st := TJSONObject.Create;
    try
      st.Add('lineCap', 'round');
      t := LineStyleOf(Sub(fo, 'lineStyle'));
      try
        JsMerge(st, t, True);
      finally
        t.Free;
      end;
      TyGfxSetStyle(line, st);
    finally
      st.Free;
    end;
    line.Silent := True;
    line.Z2 := 1;
    line.Animation := AAnim.Driver;
    TyGfxAddChild(MainGroup, line);
    AddEl(line, tlrLine, -1, NaN);
    el := TyGfxCreate('line');
    TyTlPut(el.Shape, 'x1', TJSONFloatNumber.Create(AxisExtent[0]));
    if Checkpoint <> nil then v := Checkpoint.X else v := AxisExtent[0];
    TyTlPut(el.Shape, 'x2', TJSONFloatNumber.Create(v));
    TyTlPut(el.Shape, 'y1', TJSONIntegerNumber.Create(0));
    TyTlPut(el.Shape, 'y2', TJSONIntegerNumber.Create(0));
    { defaults(lineCap and the line's lineWidth, the progress line style) }
    st := TJSONObject.Create;
    try
      st.Add('lineCap', 'round');
      lw := line.StyleValue('lineWidth');
      if lw.Kind <> avkNull then st.Add('lineWidth', TyGfxJsonOf(lw));
      t := LineStyleOf(Sub(Sub(fo, 'progress'), 'lineStyle'));
      try
        for k := 0 to t.Count - 1 do
          if not NotNull(st.Find(t.Names[k])) then TyTlPut(st, t.Names[k], t.Items[k].Clone);
      finally
        t.Free;
      end;
      TyGfxSetStyle(el, st);
    finally
      st.Free;
    end;
    el.Silent := True;
    el.Z2 := 1;
    el.Animation := AAnim.Driver;
    TyGfxAddChild(MainGroup, el);
    AddEl(el, tlrProgress, -1, NaN);
    ProgressLine := el;
  end;

  { ---------------- _renderAxisTick ---------------- }
  for i := 0 to nData - 1 do
  begin
    v := tickValues[i];
    coord := DataToCoord(v);
    t := ItemAt(v);
    el := GiveSymbol([t, fo], [Sub(t, 'itemStyle'), Sub(fo, 'itemStyle')],
      MainGroup, True, coord, 0, nil, False);
    AddEl(el, tlrTick, i, v);
    n := High(Els);
    st := ItemStyleOf([Sub(Sub(t, 'emphasis'), 'itemStyle'),
      Sub(Sub(fo, 'emphasis'), 'itemStyle')], False);
    try
      StyleProps(st, FEmph[n]);
      FHasEmph[n] := True;
    finally
      st.Free;
    end;
    st := ItemStyleOf([Sub(Sub(t, 'progress'), 'itemStyle'),
      Sub(Sub(fo, 'progress'), 'itemStyle')], False);
    try
      StyleProps(st, FProg[n]);
      FHasProg[n] := True;
    finally
      st.Free;
    end;
  end;

  { ---------------- _renderControl: next, prev, play ---------------- }
  if hasNext then MakeBtn(nextPos, 'next', tlrNext, False);
  if hasPrev then MakeBtn(prevPos, 'prev', tlrPrev, False);
  if hasPlay then
  begin
    if PlayState then MakeBtn(playPos, 'stop', tlrStop, True)
    else MakeBtn(playPos, 'play', tlrPlay, True);
  end;

  { ---------------- _renderCurrentPointer ---------------- }
  t := ItemAt(CurrentIndex);
  GiveSymbol([Sub(t, 'checkpointStyle'), Sub(fo, 'checkpointStyle')],
    [Sub(t, 'checkpointStyle'), Sub(fo, 'checkpointStyle')], MainGroup, False,
    0, 0, Checkpoint, True);
  AddEl(Checkpoint, tlrPointer, -1, NaN);

  { ---------------- _renderAxisLabel ---------------- }
  if TyTlTruthy(lbl.Find('show')) and (nData > 0) then
  begin
    { the global text style: the root's over the default }
    gtext := TJSONObject.Create;
    try
      gtext.Add('fontFamily', AInk.FontFamily);
      gtext.Add('fontSize', TJSONFloatNumber.Create(AInk.FontPx));
      gtext.Add('fontStyle', 'normal');
      gtext.Add('fontWeight', 'normal');
      if ARoot <> nil then
      begin
        t := Sub(ARoot, 'textStyle');
        if t <> nil then
          for k := 0 to t.Count - 1 do TyTlPut(gtext, t.Names[k], t.Items[k].Clone);
      end;
      { getViewLabels }
      built := nil;
      off := nil;
      if FAxisType = 'category' then
      begin
        d := lbl.Find('interval');
        if (d <> nil) and (d.JSONType = jtNumber) then
          interval := d.AsFloat
        else
        begin
          { calculateCategoryInterval: every label measured in the label
            model's font }
          d := ChainGet([lbl], 'fontSize');
          if d = nil then d := gtext.Find('fontSize');
          fontPx := JsNum(d);
          if (d = nil) or IsNan(fontPx) or (fontPx = 0) then fontPx := 12;
          d := ChainGet([lbl], 'fontFamily');
          if d = nil then d := gtext.Find('fontFamily');
          fontName := StrOf(d);
          SetLength(widths, nData);
          SetLength(heights, nData);
          n := 0;
          k := TyCategorySampleStep(nData);
          i := 0;
          while i <= nData - 1 do
          begin
            w := 0;
            h := 0;
            if AMeasurer <> nil then
              AMeasurer.MeasureLine(LabelOf(i, i), fontName, TyFontSizeFromPx(fontPx),
                400, w, h);
            widths[n] := w;
            heights[n] := h;
            Inc(n);
            Inc(i, k);
          end;
          SetLength(widths, n);
          SetLength(heights, n);
          if nData - 1 < 1 then interval := 0
          else
          begin
            if Vertical then v := 90 else v := 0;
            { labelModel.get('rotate') || 0 }
            if TyTlTruthy(lbl.Find('rotate')) then w := JsNum(lbl.Find('rotate')) else w := 0;
            interval := TyCategoryAutoInterval(widths, heights,
              DataToCoord(1) - DataToCoord(0), v, w, 7);
          end;
        end;
        TyCategoryBuiltList(0, nData, interval, built, off);
      end
      else
      begin
        SetLength(built, nData);
        SetLength(off, nData);
        for i := 0 to nData - 1 do
        begin
          built[i] := i;
          off[i] := False;
        end;
      end;
      for k := 0 to High(built) do
      begin
        if off[k] then Continue;
        i := built[k];
        { the tick's value is the data index on a category axis, the value
          on the others }
        if FAxisType = 'category' then v := i else v := tickValues[i];
        t := ItemAt(v);
        el := TyGfxCreate('text');
        el.X := DataToCoord(v);
        el.Y := 0;
        el.Rotation := labelRotation - rotation;
        el.Silent := False;
        st := TextStyleOf([Sub(t, 'label'), lbl], gtext);
        try
          TyTlPut(st, 'text', TJSONString.Create(LabelOf(v, k)));
          TyTlPut(st, 'align', TJSONString.Create(labelAlign));
          TyTlPut(st, 'verticalAlign', TJSONString.Create(labelBaseline));
          TyGfxSetStyle(el, st);
        finally
          st.Free;
        end;
        el.StatePath := False;
        el.StateText := True;
        el.Animation := AAnim.Driver;
        TyGfxAddChild(LabelGroup, el);
        AddEl(el, tlrLabel, i, v);
        n := High(Els);
        { the label's data index is the tick's value }
        FLabelValue[n] := v;
        st := TextStyleOf([Sub(Sub(t, 'emphasis'), 'label'),
          Sub(Sub(fo, 'emphasis'), 'label')], gtext);
        try
          StyleProps(st, FEmph[n]);
          FHasEmph[n] := True;
        finally
          st.Free;
        end;
        st := TextStyleOf([Sub(Sub(t, 'progress'), 'label'),
          Sub(Sub(fo, 'progress'), 'label')], gtext);
        try
          StyleProps(st, FProg[n]);
          FHasProg[n] := True;
        finally
          st.Free;
        end;
      end;
    finally
      gtext.Free;
    end;
  end;

  { ---------------- _position ---------------- }
  r := viewRect;
  if Vertical then
  begin
    { the rect turned back to horizontal about its bottom-left corner }
    rx := viewRect.X;
    ry := viewRect.Y + viewRect.H;
    m := TyMatIdentity;
    m[4] := m[4] + -rx;
    m[5] := m[5] + -ry;
    aa := m[0]; ac := m[2]; atx := m[4];
    ab := m[1]; ad := m[3]; aty := m[5];
    sn := TyJsSin(-Pi / 2);
    cs := TyJsCos(-Pi / 2);
    m[0] := aa * cs + ab * sn;
    m[1] := -aa * sn + ab * cs;
    m[2] := ac * cs + ad * sn;
    m[3] := -ac * sn + cs * ad;
    m[4] := cs * (atx - 0) + sn * (aty - 0) + 0;
    m[5] := cs * (aty - 0) - sn * (atx - 0) + 0;
    m[4] := m[4] + rx;
    m[5] := m[5] + ry;
    r := TyRectApplyMat(viewRect, m);
  end;
  mainR := TyGfxRect(MainGroup, AMeasurer);
  labelR := TyGfxRect(LabelGroup, AMeasurer);
  for k := 0 to 1 do
  begin
    vb[0, k] := GetBound(r, 0, k);
    vb[1, k] := GetBound(r, 1, k);
    mb[0, k] := GetBound(mainR, 0, k);
    mb[1, k] := GetBound(mainR, 1, k);
    lb[0, k] := GetBound(labelR, 0, k);
    lb[1, k] := GetBound(labelR, 1, k);
  end;
  mainPos[0] := MainGroup.X;
  mainPos[1] := MainGroup.Y;
  labelsPos[0] := LabelGroup.X;
  labelsPos[1] := LabelGroup.Y;
  mainPos[0] := vb[0, 0];
  labelsPos[0] := vb[0, 0];
  if labelPos <> lpNumber then
  begin
    if labelPos = lpPlus then idx := 0 else idx := 1;
    mainPos[1] := mainPos[1] + (vb[1, idx] - mb[1, idx]);
    labelsPos[1] := labelsPos[1] + (vb[1, 1 - idx] - lb[1, 1 - idx]);
  end
  else
  begin
    if labelPosNum >= 0 then idx := 0 else idx := 1;
    mainPos[1] := mainPos[1] + (vb[1, idx] - mb[1, idx]);
    labelsPos[1] := mainPos[1] + labelPosNum;
  end;
  MainGroup.X := mainPos[0];
  MainGroup.Y := mainPos[1];
  LabelGroup.X := labelsPos[0];
  LabelGroup.Y := labelsPos[1];
  MainGroup.Rotation := rotation;
  LabelGroup.Rotation := rotation;
  MainGroup.OriginX := vb[0, 0] - MainGroup.X;
  MainGroup.OriginY := vb[1, 0] - MainGroup.Y;
  LabelGroup.OriginX := vb[0, 0] - LabelGroup.X;
  LabelGroup.OriginY := vb[1, 0] - LabelGroup.Y;

  { ---------------- _updateTicksStatus ---------------- }
  for i := 0 to High(Els) do
  begin
    case Roles[i].Kind of
      tlrTick: FInProg[i] := Roles[i].Index < CurrentIndex;
      tlrLabel: FInProg[i] := FLabelValue[i] <= CurrentIndex;
    else
      FInProg[i] := False;
    end;
    if FInProg[i] then UseStatesOf(i, True);
  end;

  { ---------------- updateZ, updateStates ---------------- }
  for i := 0 to High(Els) do
  begin
    Els[i].Z := Z;
    Els[i].ZLevel := ZLevel;
    if FHasEmph[i] and AAnim.HasStateCfg then Els[i].SetStateTransition(AAnim.StateCfg);
  end;
  UpdateTransforms;
end;

function TTyTimelineView.StateOf(AIndex: Integer): TTyAnimState;
var
  i: Integer;
  e: TTyAnimState;
begin
  Result := Default(TTyAnimState);
  if FInProg[AIndex] and FHasProg[AIndex] then
  begin
    Result.HasStyle := FProg[AIndex].HasStyle;
    for i := 0 to High(FProg[AIndex].Props) do
      TyAnimPropPut(Result.Props, FProg[AIndex].Props[i].Key, FProg[AIndex].Props[i].Value);
  end;
  if Hover[AIndex] and FHasEmph[AIndex] then
  begin
    e := FEmph[AIndex];
    Result.HasStyle := Result.HasStyle or e.HasStyle;
    for i := 0 to High(e.Props) do
      TyAnimPropPut(Result.Props, e.Props[i].Key, e.Props[i].Value);
  end;
end;

procedure TTyTimelineView.UseStatesOf(AIndex: Integer; ANoAnimation: Boolean);
var name: string;
begin
  name := '';
  if FInProg[AIndex] and FHasProg[AIndex] then name := 'progress';
  if Hover[AIndex] and FHasEmph[AIndex] then
  begin
    if name <> '' then name := name + ',';
    name := name + 'emphasis';
  end;
  if name = '' then Els[AIndex].ClearStates(ANoAnimation)
  else Els[AIndex].UseStates(name, StateOf(AIndex), ANoAnimation);
  { z2, a primary state key of the Displayable's (set, never animated): the
    emphasis state's proxy lifts it ten from the normal state's, which
    leaving restores }
  if Hover[AIndex] and FHasEmph[AIndex] then Els[AIndex].Z2 := FBaseZ2[AIndex] + 10
  else Els[AIndex].Z2 := FBaseZ2[AIndex];
end;

procedure TTyTimelineView.ApplyStates(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(Els)) then Exit;
  if not FHasEmph[AIndex] then Exit;
  UseStatesOf(AIndex, False);
end;

function TTyTimelineView.IsDispatcher(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(Els)) and FHasEmph[AIndex];
end;

procedure TTyTimelineView.UpdateTransforms;
begin
  TyGfxUpdateTransforms(Root);
end;

function TTyTimelineView.DisplayOrder: TTyIntegerArray;
var
  i, j, t: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Els));
  for i := 0 to High(Els) do Result[i] := i;
  { a stable insertion sort by zlevel, z and z2 }
  for i := 1 to High(Result) do
  begin
    t := Result[i];
    j := i - 1;
    while (j >= 0) and ((Els[Result[j]].ZLevel > Els[t].ZLevel)
      or ((Els[Result[j]].ZLevel = Els[t].ZLevel) and ((Els[Result[j]].Z > Els[t].Z)
      or ((Els[Result[j]].Z = Els[t].Z) and (Els[Result[j]].Z2 > Els[t].Z2))))) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := t;
  end;
end;

function TTyTimelineView.HitAt(AX, AY: Double; const AMeasurer: ITyTextMeasurer): Integer;
var
  order: TTyIntegerArray;
  i, k: Integer;
  el: TTyGfxEl;
  inv: TTyMat2D;
  lx, ly: Double;
  r: TTyXYWH;
begin
  Result := -1;
  if not Shown then Exit;
  UpdateTransforms;
  order := DisplayOrder;
  for i := High(order) downto 0 do
  begin
    k := order[i];
    el := Els[k];
    if el.Ignore or el.Silent then Continue;
    if el.HasTransform then
    begin
      if not TyMatInvert(el.Transform, inv) then Continue;
      lx := inv[0] * AX + inv[2] * AY + inv[4];
      ly := inv[1] * AX + inv[3] * AY + inv[5];
    end
    else
    begin
      lx := AX;
      ly := AY;
    end;
    { rectHover, and a text's span: the bounding rect }
    r := TyGfxRect(el, AMeasurer);
    if (lx >= r.X) and (lx <= r.X + r.W) and (ly >= r.Y) and (ly <= r.Y + r.H) then
      Exit(k);
  end;
end;

function TTyTimelineView.ToAxisCoord(AX, AY: Double): Double;
var m, inv: TTyMat2D;
begin
  m := TyGfxLocalTransform(MainGroup);
  if not TyMatInvert(m, inv) then Exit(NaN);
  Result := inv[0] * AX + inv[2] * AY + inv[4];
end;

function TTyTimelineView.NearestTick(ACoord: Double): Integer;
var
  i: Integer;
  dist, d: Double;
begin
  Result := -1;
  dist := Infinity;
  for i := 0 to Count - 1 do
  begin
    d := Abs(DataToCoord(Values[i]) - ACoord);
    if d < dist then
    begin
      dist := d;
      Result := i;
    end;
  end;
end;

function TTyTimelineView.DragTo(AX, AY: Double): Double;
var lo, hi: Double;
begin
  Result := ToAxisCoord(AX, AY);
  lo := AxisExtent[0];
  hi := AxisExtent[1];
  if lo > hi then
  begin
    lo := AxisExtent[1];
    hi := AxisExtent[0];
  end;
  if Result > hi then Result := hi;
  if Result < lo then Result := lo;
  if Checkpoint <> nil then Checkpoint.X := Result;
  if ProgressLine <> nil then
    TyTlPut(ProgressLine.Shape, 'x2', TJSONFloatNumber.Create(Result));
end;

end.
