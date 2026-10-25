unit tyControls.AdvanceChart.BackwardCompat;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the old option spellings, rewritten as ECharts 6.1
  rewrites them. [R3-A]

  Upstream registers three preprocessors that turn ECharts 2 / 3 / 4
  spellings into today's, and runs them -- with every other preprocessor --
  over the base option, every timeline frame and every media unit with a
  query, never over the media default (parseRawOption's doPreprocess):

  backwardCompat (preprocessor/backwardCompat.ts), registered first:
    compatStyle (preprocessor/helper/compatStyle.ts)
      - ec2: itemStyle.normal.X and itemStyle.emphasis.X for X in areaStyle,
        lineStyle, nodeStyle, linkStyle, chordStyle, label, labelLine move to
        X.normal / X.emphasis (merged into one already there) and are left
        null (compatEC2ItemStyle) -- on a series, its markPoint, its markLine;
      - ec3: S.normal replaces S, S.emphasis becomes emphasis.S (its focus
        and blurScope lifted into emphasis) for S in itemStyle, lineStyle,
        areaStyle, label, labelLine, upperLabel, edgeLabel
        (convertNormalEmphasis / removeEC3NormalStatus) -- on a series, its
        markers, data items, graph nodes, links and categories, marker data,
        treemap levels, tree leaves, geo and its regions, the timeline and
        its data, a calendar's and a breadcrumb's itemStyle, a toolbox's
        iconStyle and every feature's, a timeline's controlStyle (where the
        normal's keys only fill what is missing);
      - ec2: a label's `textStyle` keys copied up into it (compatTextStyle),
        wherever upstream calls it;
      - a radar's `name` becomes axisName, `nameGap` axisNameGap.
    per series: a line's clipOverflow, a pie's or gauge's clockWise, a pie
    label's margin as edgeDistance (alignTo 'edge'), a bar's barBorderRadius
    / Color / Width, a sunburst's highlightPolicy and downplay, a graph's or
    sankey's focusNodeAdjacency, a map's mapType and mapLocation, any
    series' hoverAnimation, x / y / x2 / y2 as left / top / right / bottom;
    a pie's or gauge's hoverOffset writes emphasis.scaleSize NULL (upstream
    assigns where it compares: `if (seriesOpt.emphasis.scaleSize = null)`),
    and a gauge's pointer.color is never read (its branch is unreachable);
    `dataRange` is the visualMap; x / y / x2 / y2 on grid, geo, parallel,
    legend, toolbox, title, visualMap, dataZoom and timeline.
  the radar chart's (chart/radar/backwardCompat.ts), after the grid's: a
    polar with an indicator is a radar (its type its shape), a radar series'
    polarIndex its radarIndex;
  the candlestick's (chart/candlestick/preprocessor.ts): type 'k' is
    'candlestick'.

  THE ORDER. tyControls.AdvanceChart.Media's TyParseRawOption runs
  TyLegacyPreprocess on every option it preprocesses, before the graphic
  and timeline preprocessors (upstream registers both after these); the
  rest of the chain (parallel, brush, visualMap, aria) follows in
  tyControls.AdvanceChart.Option's PreprocessOne, which ends with
  TyBackwardCompatSettle.

  ONE OBJECT IN TWO PLACES. JavaScript moves objects by reference; three
  of upstream's moves leave the same object in two places of one option,
  and what a later preprocessor does to one is seen in the other. JSON
  trees cannot share, so each is a copy kept equal by hand:
  - an S that has an emphasis and no normal keeps S.emphasis beside the
    new emphasis.S: compatTextStyle on emphasis.label is done to
    label.emphasis too, and the timeline preprocessor's move of the label
    out of an itemStyle.emphasis is done to emphasis.itemStyle beforehand
    (the timeline preprocessor knows nothing of the copy);
  - `dataRange` is the visualMap object: TyBackwardCompatSettle copies the
    visualMap back over it once the visualMap preprocessor has run.

  WHERE UPSTREAM THROWS -- a property set on a truthy primitive in strict
  mode (`emphasis: true` with hoverAnimation, `label: 5` with
  itemStyle.normal.label), `'x' in 5` for a component written as a number,
  a null polar or radar, a null timeline or toolbox -- setOption fails
  upstream. Here the step is skipped and the rest goes on. A property set
  on an ARRAY is one JSON cannot hold, and nothing reads it: skipped too.

  The keys rewritten stay where they were written (as upstream leaves
  them): tyControls.AdvanceChart.Complete knows them as legacy keys, so
  the diagnostics do not report them unknown.

  PURE: SysUtils, Math and fpjson. }
interface
uses SysUtils, Math, fpjson;

{ globalBackwardCompat(option) on AOption, in place }
procedure TyBackwardCompat(AOption: TJSONObject);
{ the radar chart's ec2 compatibility }
procedure TyRadarBackwardCompat(AOption: TJSONObject);
{ the candlestick's: type 'k' }
procedure TyCandlestickPreprocess(AOption: TJSONObject);
{ the three, in the order upstream registers them }
procedure TyLegacyPreprocess(AOption: TJSONObject);
{ after the visualMap preprocessor: `dataRange` is the visualMap object }
procedure TyBackwardCompatSettle(AOption: TJSONObject);

implementation

const
  { compatStyle.ts POSSIBLE_STYLES }
  cPossibleStyles: array[0..6] of string = ('areaStyle', 'lineStyle',
    'nodeStyle', 'linkStyle', 'chordStyle', 'label', 'labelLine');
  { removeEC3NormalStatus, in its order }
  cNormalStatus: array[0..6] of string = ('itemStyle', 'lineStyle',
    'areaStyle', 'label', 'labelLine', 'upperLabel', 'edgeLabel');
  cStItemStyle = 0;
  cStLabel = 3;
  cStUpperLabel = 5;
  cStEdgeLabel = 6;
  { util/model.ts TEXT_STYLE_OPTIONS, in its order }
  cTextStyleOptions: array[0..27] of string = (
    'fontStyle', 'fontWeight', 'fontSize', 'fontFamily',
    'rich', 'tag', 'color', 'textBorderColor', 'textBorderWidth',
    'width', 'height', 'lineHeight', 'align', 'verticalAlign', 'baseline',
    'shadowColor', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY',
    'textShadowColor', 'textShadowBlur', 'textShadowOffsetX', 'textShadowOffsetY',
    'backgroundColor', 'borderColor', 'borderWidth', 'borderRadius', 'padding');
  { backwardCompat.ts LAYOUT_PROPERTIES }
  cLayoutFrom: array[0..3] of string = ('x', 'y', 'x2', 'y2');
  cLayoutTo: array[0..3] of string = ('left', 'top', 'right', 'bottom');
  { COMPATITABLE_COMPONENTS }
  cLayoutComponents: array[0..8] of string = ('grid', 'geo', 'parallel',
    'legend', 'toolbox', 'title', 'visualMap', 'dataZoom', 'timeline');
  { BAR_ITEM_STYLE_MAP: new, old }
  cBarNew: array[0..2] of string = ('borderRadius', 'borderColor', 'borderWidth');
  cBarOld: array[0..2] of string = ('barBorderRadius', 'barBorderColor', 'barBorderWidth');

type
  { which of cNormalStatus kept an emphasis in two places }
  TAliasSet = set of 0..6;

{ ==================== JavaScript, on JSON ==================== }

function Truthy(D: TJSONData): Boolean;
var v: Double;
begin
  if D = nil then Exit(False);
  case D.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := D.AsBoolean;
    jtNumber:
      begin
        v := D.AsFloat;
        Result := (v <> 0) and not IsNan(v);
      end;
    jtString: Result := D.AsString <> '';
  else
    Result := True;
  end;
end;

{ `== null` }
function IsNil(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

{ a property read: an object's own key; an array or a primitive has none
  that JSON can write }
function Prop(D: TJSONData; const AKey: string): TJSONData;
begin
  if D is TJSONObject then Result := TJSONObject(D).Find(AKey)
  else Result := nil;
end;

function IsStr(D: TJSONData; const AValue: string): Boolean;
begin
  Result := (D <> nil) and (D.JSONType = jtString) and (D.AsString = AValue);
end;

{ an assignment: a key there keeps its place, a new one goes last. AValue
  is owned, and must not be a part of what it replaces. }
procedure Put(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
var k: Integer;
begin
  k := AObj.IndexOfName(AKey);
  if k >= 0 then AObj.Items[k] := AValue
  else AObj.Add(AKey, AValue);
end;

{ `o.k = o.k || an empty object`: the object there, or a new one; nil where the value is
  a truthy primitive or an array (no property to set) }
function EnsureObj(AObj: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  d := AObj.Find(AKey);
  if not Truthy(d) then
  begin
    Result := TJSONObject.Create;
    Put(AObj, AKey, Result);
  end
  else if d is TJSONObject then
    Result := TJSONObject(d)
  else
    Result := nil;
end;

{ zrUtil.each's items: an array's, an object's values, nothing else }
function EachCount(D: TJSONData): Integer;
begin
  if (D is TJSONArray) or (D is TJSONObject) then Result := D.Count
  else Result := 0;
end;

function EachItem(D: TJSONData; AIndex: Integer): TJSONData;
begin
  if D is TJSONArray then Result := TJSONArray(D).Items[AIndex]
  else Result := TJSONObject(D).Items[AIndex];
end;

{ toArr / normalizeToArray: an array's items, a truthy value as one item }
function ArrCount(D: TJSONData): Integer;
begin
  if D is TJSONArray then Result := D.Count
  else if Truthy(D) then Result := 1
  else Result := 0;
end;

function ArrItem(D: TJSONData; AIndex: Integer): TJSONData;
begin
  if D is TJSONArray then Result := TJSONArray(D).Items[AIndex]
  else Result := D;
end;

{ toObj: an array's first item (nothing for an empty one), else the value }
function ToObj(D: TJSONData): TJSONData;
begin
  if D is TJSONArray then
  begin
    if D.Count > 0 then Result := TJSONArray(D).Items[0] else Result := nil;
  end
  else
    Result := D;
end;

{ a `for (i < data.length)` over a list: an array's items (a string's
  characters change nothing, anything else has no length) }
function ListCount(D: TJSONData): Integer;
begin
  if D is TJSONArray then Result := D.Count else Result := 0;
end;

{ zrUtil.merge(target, source) -- overwrite false: plain objects are merged
  deeply, a key the target lacks is given a copy }
procedure ZrMerge(T, S: TJSONData);
var
  i: Integer;
  key: string;
  sv, tv: TJSONData;
begin
  if not (((S is TJSONObject) or (S is TJSONArray))
    and ((T is TJSONObject) or (T is TJSONArray))) then Exit;
  for i := 0 to S.Count - 1 do
  begin
    if S is TJSONObject then
    begin
      key := TJSONObject(S).Names[i];
      sv := TJSONObject(S).Items[i];
    end
    else
    begin
      key := IntToStr(i);
      sv := TJSONArray(S).Items[i];
    end;
    if T is TJSONObject then
    begin
      tv := TJSONObject(T).Find(key);
      if (sv is TJSONObject) and (tv is TJSONObject) then ZrMerge(tv, sv)
      else if tv = nil then TJSONObject(T).Add(key, sv.Clone);
    end
    else if S is TJSONArray then
    begin
      { an array onto an array, index by index }
      if i < T.Count then
      begin
        tv := TJSONArray(T).Items[i];
        if (sv is TJSONObject) and (tv is TJSONObject) then ZrMerge(tv, sv);
      end
      else
        TJSONArray(T).Add(sv.Clone);
    end;
    { a named key onto an array: a property JSON cannot hold }
  end;
end;

{ ==================== compatStyle ==================== }

{ compatTextStyle(opt, propName) }
procedure CompatTextStyle(AOpt: TJSONData; const AProp: string);
var
  lab, ts: TJSONData;
  i, k: Integer;
begin
  lab := Prop(AOpt, AProp);
  if not (lab is TJSONObject) then Exit;
  ts := TJSONObject(lab).Find('textStyle');
  { isObject(labelOptSingle) && labelOptSingle.textStyle, truthy; an
    array's or a primitive's hasOwnProperty finds no text style key }
  if not (ts is TJSONObject) then Exit;
  for i := 0 to High(cTextStyleOptions) do
  begin
    k := TJSONObject(ts).IndexOfName(cTextStyleOptions[i]);
    if k >= 0 then Put(TJSONObject(lab), cTextStyleOptions[i], TJSONObject(ts).Items[k].Clone);
  end;
end;

{ compatTextStyle(host.emphasis, prop), and on the copy of it that
  host[prop].emphasis is when AAliased }
procedure CompatTextStyleEm(AHost: TJSONData; const AProp: string; AAliased: Boolean);
begin
  CompatTextStyle(Prop(AHost, 'emphasis'), AProp);
  if AAliased then CompatTextStyle(Prop(AHost, AProp), 'emphasis');
end;

{ defaults(target, source): every key of the source the target holds as
  null or not at all }
procedure Defaults(T: TJSONObject; S: TJSONData);
var
  i: Integer;
  key: string;
begin
  if not ((S is TJSONObject) or (S is TJSONArray)) then Exit;
  for i := 0 to S.Count - 1 do
  begin
    if S is TJSONObject then key := TJSONObject(S).Names[i] else key := IntToStr(i);
    if IsNil(T.Find(key)) then
      if S is TJSONObject then Put(T, key, TJSONObject(S).Items[i].Clone)
      else Put(T, key, TJSONArray(S).Items[i].Clone);
  end;
end;

{ convertNormalEmphasis(opt, optType, useExtend). True when the emphasis
  object now stands in two places: opt[optType].emphasis and
  opt.emphasis[optType]. }
function ConvertNormalEmphasis(AOpt: TJSONData; const AType: string;
  AUseExtend: Boolean): Boolean;
var
  c, n, e, em, f: TJSONData;
  o, co, emo: TJSONObject;
  nv, ev: TJSONData;
  aliased: Boolean;
begin
  Result := False;
  c := Prop(AOpt, AType);
  if not Truthy(c) then Exit;
  n := Prop(c, 'normal');
  e := Prop(c, 'emphasis');
  if not (Truthy(n) or Truthy(e)) then Exit;
  { both read: AOpt and the container are objects }
  o := TJSONObject(AOpt);
  co := TJSONObject(c);
  ev := nil;
  aliased := Truthy(e);
  if aliased then ev := e.Clone;
  if Truthy(n) then
  begin
    nv := n.Clone;
    if AUseExtend then
    begin
      { opt[optType].normal = opt[optType].emphasis = null -- the emphasis
        first; then the normal's keys where the container has none }
      Put(co, 'emphasis', TJSONNull.Create);
      Put(co, 'normal', TJSONNull.Create);
      Defaults(co, nv);
      nv.Free;
    end
    else
      { the container goes, and its emphasis with it }
      Put(o, AType, nv);
    aliased := False;
  end;
  if ev = nil then Exit;
  em := o.Find('emphasis');
  if not Truthy(em) then
  begin
    em := TJSONObject.Create;
    Put(o, 'emphasis', em);
  end;
  if not (em is TJSONObject) then
  begin
    { a truthy primitive (upstream throws) or an array }
    ev.Free;
    Exit;
  end;
  emo := TJSONObject(em);
  Put(emo, AType, ev);
  { the ec3 mix of style and focus: emphasisOpt.focus / blurScope, truthy }
  f := Prop(ev, 'focus');
  if Truthy(f) then Put(emo, 'focus', f.Clone);
  f := Prop(ev, 'blurScope');
  if Truthy(f) then Put(emo, 'blurScope', f.Clone);
  Result := aliased;
end;

function RemoveEC3NormalStatus(AOpt: TJSONData): TAliasSet;
var i: Integer;
begin
  Result := [];
  for i := 0 to High(cNormalStatus) do
    if ConvertNormalEmphasis(AOpt, cNormalStatus[i], False) then Include(Result, i);
end;

{ one move of compatEC2ItemStyle: itemStyle[AState][AName] (AValue, truthy)
  to opt[AName][AState]. False where upstream throws before it nulls the
  source. }
function MoveEC2Style(AOpt: TJSONObject; const AName, AState: string;
  AValue: TJSONData): Boolean;
var t, tn: TJSONData;
begin
  t := AOpt.Find(AName);
  if not Truthy(t) then
  begin
    t := TJSONObject.Create;
    Put(AOpt, AName, t);
  end;
  if t is TJSONArray then Exit(True);
  if not (t is TJSONObject) then Exit(False);
  tn := TJSONObject(t).Find(AState);
  if not Truthy(tn) then Put(TJSONObject(t), AState, AValue.Clone)
  else ZrMerge(tn, AValue);
  Result := True;
end;

procedure CompatEC2ItemStyle(AOpt: TJSONData);
var
  ist, nis, eis, v: TJSONData;
  i: Integer;
begin
  ist := Prop(AOpt, 'itemStyle');
  if not Truthy(ist) then Exit;
  for i := 0 to High(cPossibleStyles) do
  begin
    nis := Prop(ist, 'normal');
    eis := Prop(ist, 'emphasis');
    v := Prop(nis, cPossibleStyles[i]);
    if Truthy(v) then
      if MoveEC2Style(TJSONObject(AOpt), cPossibleStyles[i], 'normal', v) then
        Put(TJSONObject(nis), cPossibleStyles[i], TJSONNull.Create);
    v := Prop(eis, cPossibleStyles[i]);
    if Truthy(v) then
      if MoveEC2Style(TJSONObject(AOpt), cPossibleStyles[i], 'emphasis', v) then
        Put(TJSONObject(eis), cPossibleStyles[i], TJSONNull.Create);
  end;
end;

function CompatEC3CommonStyles(AOpt: TJSONData): TAliasSet;
begin
  Result := [];
  if not Truthy(AOpt) then Exit;
  Result := RemoveEC3NormalStatus(AOpt);
  CompatTextStyle(AOpt, 'label');
  if Truthy(Prop(AOpt, 'emphasis')) then
    CompatTextStyleEm(AOpt, 'label', cStLabel in Result);
end;

procedure EachCommon(AList: TJSONData);
var i: Integer;
begin
  for i := 0 to ListCount(AList) - 1 do CompatEC3CommonStyles(TJSONArray(AList).Items[i]);
end;

procedure ProcessSeries(ASeries: TJSONObject);
var
  al: TAliasSet;
  d, ed, mk, it, cat: TJSONData;
  i: Integer;
  isGraph: Boolean;
begin
  CompatEC2ItemStyle(ASeries);
  al := RemoveEC3NormalStatus(ASeries);
  CompatTextStyle(ASeries, 'label');
  CompatTextStyle(ASeries, 'upperLabel');
  CompatTextStyle(ASeries, 'edgeLabel');
  if Truthy(ASeries.Find('emphasis')) then
  begin
    CompatTextStyleEm(ASeries, 'label', cStLabel in al);
    CompatTextStyleEm(ASeries, 'upperLabel', cStUpperLabel in al);
    CompatTextStyleEm(ASeries, 'edgeLabel', cStEdgeLabel in al);
  end;
  mk := ASeries.Find('markPoint');
  if Truthy(mk) then
  begin
    CompatEC2ItemStyle(mk);
    CompatEC3CommonStyles(mk);
  end;
  mk := ASeries.Find('markLine');
  if Truthy(mk) then
  begin
    CompatEC2ItemStyle(mk);
    CompatEC3CommonStyles(mk);
  end;
  mk := ASeries.Find('markArea');
  if Truthy(mk) then CompatEC3CommonStyles(mk);

  d := ASeries.Find('data');
  isGraph := IsStr(ASeries.Find('type'), 'graph');
  if isGraph then
  begin
    if not Truthy(d) then d := ASeries.Find('nodes');
    ed := ASeries.Find('links');
    if not Truthy(ed) then ed := ASeries.Find('edges');
    EachCommon(ed);
    cat := ASeries.Find('categories');
    for i := 0 to EachCount(cat) - 1 do RemoveEC3NormalStatus(EachItem(cat, i));
  end;
  EachCommon(d);

  { the markers' data, read again }
  mk := ASeries.Find('markPoint');
  if Truthy(mk) then EachCommon(Prop(mk, 'data'));
  mk := ASeries.Find('markLine');
  if Truthy(mk) then
  begin
    d := Prop(mk, 'data');
    for i := 0 to ListCount(d) - 1 do
    begin
      it := TJSONArray(d).Items[i];
      if it is TJSONArray then
      begin
        if it.Count > 0 then CompatEC3CommonStyles(TJSONArray(it).Items[0]);
        if it.Count > 1 then CompatEC3CommonStyles(TJSONArray(it).Items[1]);
      end
      else
        CompatEC3CommonStyles(it);
    end;
  end;

  if IsStr(ASeries.Find('type'), 'gauge') then
  begin
    CompatTextStyle(ASeries, 'axisLabel');
    CompatTextStyle(ASeries, 'title');
    CompatTextStyle(ASeries, 'detail');
  end
  else if IsStr(ASeries.Find('type'), 'treemap') then
  begin
    ConvertNormalEmphasis(ASeries.Find('breadcrumb'), 'itemStyle', False);
    d := ASeries.Find('levels');
    for i := 0 to EachCount(d) - 1 do RemoveEC3NormalStatus(EachItem(d, i));
  end
  else if IsStr(ASeries.Find('type'), 'tree') then
    RemoveEC3NormalStatus(ASeries.Find('leaves'));
end;

{ what the timeline preprocessor will do to an itemStyle.emphasis that also
  stands as emphasis.itemStyle (transferItem): its label moves out to the
  label, where the label (an object, or nothing yet) has no emphasis }
procedure ForeseeTransferItem(AOpt: TJSONData);
var ist, ise, lb, sec: TJSONData;
begin
  ist := Prop(AOpt, 'itemStyle');
  ise := Prop(ist, 'emphasis');
  if not Truthy(Prop(ise, 'label')) then Exit;
  lb := Prop(AOpt, 'label');
  if Truthy(lb) and not (lb is TJSONObject) then Exit;
  if (lb is TJSONObject) and (TJSONObject(lb).IndexOfName('emphasis') >= 0) then Exit;
  sec := Prop(Prop(AOpt, 'emphasis'), 'itemStyle');
  if (sec is TJSONObject) and (TJSONObject(sec).IndexOfName('label') >= 0) then
    TJSONObject(sec).Delete('label');
end;

procedure GlobalCompatStyle(AOption: TJSONObject);
const
  cAxes: array[0..6] of string = ('xAxis', 'yAxis', 'radiusAxis', 'angleAxis',
    'singleAxis', 'parallelAxis', 'radar');
var
  list, it, def, data, item, feat: TJSONData;
  i, k, j: Integer;
  al: TAliasSet;
begin
  list := AOption.Find('series');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it := ArrItem(list, i);
    if it is TJSONObject then ProcessSeries(TJSONObject(it));
  end;

  for k := 0 to High(cAxes) do
  begin
    list := AOption.Find(cAxes[k]);
    for i := 0 to ArrCount(list) - 1 do
    begin
      it := ArrItem(list, i);
      if not Truthy(it) then Continue;
      CompatTextStyle(it, 'axisLabel');
      CompatTextStyle(Prop(it, 'axisPointer'), 'label');
    end;
  end;

  list := AOption.Find('parallel');
  for i := 0 to ArrCount(list) - 1 do
  begin
    def := Prop(ArrItem(list, i), 'parallelAxisDefault');
    CompatTextStyle(def, 'axisLabel');
    CompatTextStyle(Prop(def, 'axisPointer'), 'label');
  end;

  list := AOption.Find('calendar');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it := ArrItem(list, i);
    ConvertNormalEmphasis(it, 'itemStyle', False);
    CompatTextStyle(it, 'dayLabel');
    CompatTextStyle(it, 'monthLabel');
    CompatTextStyle(it, 'yearLabel');
  end;

  { radar.name.textStyle; name -> axisName, nameGap -> axisNameGap. A null
    radar throws upstream. }
  list := AOption.Find('radar');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it := ArrItem(list, i);
    CompatTextStyle(it, 'name');
    if not (it is TJSONObject) then Continue;
    if Truthy(TJSONObject(it).Find('name')) and IsNil(TJSONObject(it).Find('axisName')) then
    begin
      Put(TJSONObject(it), 'axisName', TJSONObject(it).Find('name').Clone);
      TJSONObject(it).Delete('name');
    end;
    if not IsNil(TJSONObject(it).Find('nameGap')) and IsNil(TJSONObject(it).Find('axisNameGap')) then
    begin
      Put(TJSONObject(it), 'axisNameGap', TJSONObject(it).Find('nameGap').Clone);
      TJSONObject(it).Delete('nameGap');
    end;
  end;

  list := AOption.Find('geo');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it := ArrItem(list, i);
    if not (it is TJSONObject) then Continue;
    CompatEC3CommonStyles(it);
    def := TJSONObject(it).Find('regions');
    for j := 0 to ArrCount(def) - 1 do CompatEC3CommonStyles(ArrItem(def, j));
  end;

  { the timeline: a null one throws upstream (timelineOpt.data) }
  list := AOption.Find('timeline');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it := ArrItem(list, i);
    al := CompatEC3CommonStyles(it);
    if ConvertNormalEmphasis(it, 'label', False) then Include(al, cStLabel);
    if ConvertNormalEmphasis(it, 'itemStyle', False) then Include(al, cStItemStyle);
    ConvertNormalEmphasis(it, 'controlStyle', True);
    if cStItemStyle in al then ForeseeTransferItem(it);
    data := Prop(it, 'data');
    if data is TJSONArray then
      for j := 0 to data.Count - 1 do
      begin
        item := TJSONArray(data).Items[j];
        if not (item is TJSONObject) then Continue;
        ConvertNormalEmphasis(item, 'label', False);
        if ConvertNormalEmphasis(item, 'itemStyle', False) then ForeseeTransferItem(item);
      end;
  end;

  { the toolbox: a null one throws upstream (toolboxOpt.feature) }
  list := AOption.Find('toolbox');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it := ArrItem(list, i);
    ConvertNormalEmphasis(it, 'iconStyle', False);
    feat := Prop(it, 'feature');
    for j := 0 to EachCount(feat) - 1 do
      ConvertNormalEmphasis(EachItem(feat, j), 'iconStyle', False);
  end;

  { toObj: an array's first, else the value }
  CompatTextStyle(ToObj(AOption.Find('axisPointer')), 'label');
  CompatTextStyle(Prop(ToObj(AOption.Find('tooltip')), 'axisPointer'), 'label');
end;

{ ==================== backwardCompat ==================== }

procedure CompatLayoutProperties(AOpt: TJSONData);
var
  k: Integer;
  o: TJSONObject;
begin
  if not (AOpt is TJSONObject) then Exit;
  o := TJSONObject(AOpt);
  for k := 0 to High(cLayoutFrom) do
    if (o.IndexOfName(cLayoutFrom[k]) >= 0) and (o.IndexOfName(cLayoutTo[k]) < 0) then
      o.Add(cLayoutTo[k], o.Find(cLayoutFrom[k]).Clone);
end;

procedure CompatBarItemStyle(AOpt: TJSONData);
var
  ist, old: TJSONData;
  k: Integer;
begin
  ist := Prop(AOpt, 'itemStyle');
  if not (ist is TJSONObject) then Exit;
  for k := 0 to High(cBarOld) do
  begin
    old := TJSONObject(ist).Find(cBarOld[k]);
    if not IsNil(old) then Put(TJSONObject(ist), cBarNew[k], old.Clone);
  end;
end;

procedure CompatPieLabel(AOpt: TJSONData);
var o: TJSONObject;
begin
  if not (AOpt is TJSONObject) then Exit;
  o := TJSONObject(AOpt);
  if IsStr(o.Find('alignTo'), 'edge') and not IsNil(o.Find('margin'))
    and IsNil(o.Find('edgeDistance')) then
    Put(o, 'edgeDistance', o.Find('margin').Clone);
end;

procedure CompatSunburstState(AOpt: TJSONData);
var o: TJSONObject;
begin
  if not (AOpt is TJSONObject) then Exit;
  o := TJSONObject(AOpt);
  if Truthy(o.Find('downplay')) and not Truthy(o.Find('blur')) then
    Put(o, 'blur', o.Find('downplay').Clone);
end;

procedure TraverseTree(AData: TJSONData);
var
  i: Integer;
  it: TJSONData;
begin
  for i := 0 to ListCount(AData) - 1 do
  begin
    it := TJSONArray(AData).Items[i];
    CompatSunburstState(it);
    if Truthy(it) then TraverseTree(Prop(it, 'children'));
  end;
end;

procedure CompatGraphFocus(ASeries: TJSONObject);
var em: TJSONObject;
begin
  if IsNil(ASeries.Find('focusNodeAdjacency')) then Exit;
  em := EnsureObj(ASeries, 'emphasis');
  if (em <> nil) and IsNil(em.Find('focus')) then
    Put(em, 'focus', TJSONString.Create('adjacency'));
end;

procedure CompatSeries(S: TJSONObject);
var
  t: string;
  d, v: TJSONData;
  em: TJSONObject;
  i: Integer;
begin
  d := S.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then t := d.AsString else t := '';
  if t = 'line' then
  begin
    v := S.Find('clipOverflow');
    if not IsNil(v) then Put(S, 'clip', v.Clone);
  end
  else if (t = 'pie') or (t = 'gauge') then
  begin
    v := S.Find('clockWise');
    if not IsNil(v) then Put(S, 'clockwise', v.Clone);
    CompatPieLabel(S.Find('label'));
    { the data items themselves -- not their labels -- as upstream calls it }
    d := S.Find('data');
    for i := 0 to ListCount(d) - 1 do CompatPieLabel(TJSONArray(d).Items[i]);
    if not IsNil(S.Find('hoverOffset')) then
    begin
      em := EnsureObj(S, 'emphasis');
      { `if (seriesOpt.emphasis.scaleSize = null)`: written null, never true }
      if em <> nil then Put(em, 'scaleSize', TJSONNull.Create);
    end;
  end
  { the gauge's pointer.color branch: unreachable upstream }
  else if t = 'bar' then
  begin
    CompatBarItemStyle(S);
    CompatBarItemStyle(S.Find('backgroundStyle'));
    CompatBarItemStyle(S.Find('emphasis'));
    d := S.Find('data');
    for i := 0 to ListCount(d) - 1 do
    begin
      v := TJSONArray(d).Items[i];
      CompatBarItemStyle(v);
      CompatBarItemStyle(Prop(v, 'emphasis'));
    end;
  end
  else if t = 'sunburst' then
  begin
    v := S.Find('highlightPolicy');
    if Truthy(v) then
    begin
      em := EnsureObj(S, 'emphasis');
      if (em <> nil) and not Truthy(em.Find('focus')) then
        Put(em, 'focus', v.Clone);
    end;
    CompatSunburstState(S);
    TraverseTree(S.Find('data'));
  end
  else if (t = 'graph') or (t = 'sankey') then
    CompatGraphFocus(S)
  else if t = 'map' then
  begin
    v := S.Find('mapType');
    if Truthy(v) and not Truthy(S.Find('map')) then Put(S, 'map', v.Clone);
    v := S.Find('mapLocation');
    if Truthy(v) then
    begin
      v := v.Clone;
      try
        Defaults(S, v);
      finally
        v.Free;
      end;
    end;
  end;

  v := S.Find('hoverAnimation');
  if not IsNil(v) then
  begin
    em := EnsureObj(S, 'emphasis');
    if (em <> nil) and IsNil(em.Find('scale')) then
      Put(em, 'scale', S.Find('hoverAnimation').Clone);
  end;

  CompatLayoutProperties(S);
end;

procedure TyBackwardCompat(AOption: TJSONObject);
var
  list, it: TJSONData;
  i, k: Integer;
begin
  if AOption = nil then Exit;
  GlobalCompatStyle(AOption);
  { option.series = normalizeToArray(option.series): the port reads a bare
    series object as the list of one, and every option visits the series
    (tyControls.AdvanceChart.OptionMerge), so nothing is written }
  list := AOption.Find('series');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it := ArrItem(list, i);
    if it is TJSONObject then CompatSeries(TJSONObject(it));
  end;
  { dataRange has changed to visualMap -- one object in two places, made
    one again by TyBackwardCompatSettle }
  it := AOption.Find('dataRange');
  if Truthy(it) then Put(AOption, 'visualMap', it.Clone);
  for k := 0 to High(cLayoutComponents) do
  begin
    list := AOption.Find(cLayoutComponents[k]);
    for i := 0 to ArrCount(list) - 1 do CompatLayoutProperties(ArrItem(list, i));
  end;
end;

procedure TyRadarBackwardCompat(AOption: TJSONObject);
var
  polar, it, radar, ty: TJSONData;
  notRadar, radars: TJSONArray;
  list, it2: TJSONData;
  i: Integer;
begin
  if AOption = nil then Exit;
  polar := AOption.Find('polar');
  if Truthy(polar) then
  begin
    notRadar := TJSONArray.Create;
    try
      for i := 0 to ArrCount(polar) - 1 do
      begin
        it := ArrItem(polar, i);
        { a null polar throws upstream (polarOpt.indicator); kept here }
        if Truthy(Prop(it, 'indicator')) then
        begin
          it := it.Clone;
          ty := Prop(it, 'type');
          if Truthy(ty) and not Truthy(Prop(it, 'shape')) then
            Put(TJSONObject(it), 'shape', ty.Clone);
          radar := AOption.Find('radar');
          if not Truthy(radar) then
          begin
            radar := TJSONArray.Create;
            Put(AOption, 'radar', radar);
          end
          else if not (radar is TJSONArray) then
          begin
            radars := TJSONArray.Create;
            radars.Add(radar.Clone);
            Put(AOption, 'radar', radars);
            radar := radars;
          end;
          TJSONArray(radar).Add(it);
        end
        else
          notRadar.Add(it.Clone);
      end;
    except
      notRadar.Free;
      raise;
    end;
    { the polars without an indicator, always as a list }
    Put(AOption, 'polar', notRadar);
  end;
  list := AOption.Find('series');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it2 := ArrItem(list, i);
    if (it2 is TJSONObject) and IsStr(TJSONObject(it2).Find('type'), 'radar')
      and Truthy(TJSONObject(it2).Find('polarIndex')) then
      Put(TJSONObject(it2), 'radarIndex', TJSONObject(it2).Find('polarIndex').Clone);
  end;
end;

procedure TyCandlestickPreprocess(AOption: TJSONObject);
var
  list, it: TJSONData;
  i: Integer;
begin
  if AOption = nil then Exit;
  list := AOption.Find('series');
  for i := 0 to ArrCount(list) - 1 do
  begin
    it := ArrItem(list, i);
    if (it is TJSONObject) and IsStr(TJSONObject(it).Find('type'), 'k') then
      Put(TJSONObject(it), 'type', TJSONString.Create('candlestick'));
  end;
end;

procedure TyLegacyPreprocess(AOption: TJSONObject);
begin
  if AOption = nil then Exit;
  TyBackwardCompat(AOption);
  { the grid's preprocessor comes between: its models are kept out of the
    tree (tyControls.AdvanceChart.OptionMerge) }
  TyRadarBackwardCompat(AOption);
  { the parallel preprocessor comes between (PreprocessOne) }
  TyCandlestickPreprocess(AOption);
end;

procedure TyBackwardCompatSettle(AOption: TJSONObject);
var vm: TJSONData;
begin
  if AOption = nil then Exit;
  if not Truthy(AOption.Find('dataRange')) then Exit;
  vm := AOption.Find('visualMap');
  if vm <> nil then Put(AOption, 'dataRange', vm.Clone);
end;

end.
