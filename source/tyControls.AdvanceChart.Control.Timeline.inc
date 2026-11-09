{ Part of tyControls.AdvanceChart (included, not a unit): the timeline. Moved out of the
  unit only to keep it readable; what the control is and why it is built the way it is,
  see the unit header. }

{ ==================== the timeline [Batch 129, C21] ====================

  SliderTimelineView's render and handlers, and the two actions. The
  option, the model and the view's elements are tyControls.AdvanceChart.Timeline;
  this is what upstream keeps outside them:
  - FTlViews: every timeline model's view by its slot, from render to
    render (its checkpoint element lives in it); a notMerge, or the model
    going, makes a new one -- upstream's view is disposed with its model
    [R5-G: one view per model, not only the first's];
  - FTlDues: each view's play timer _doPlayStop sets at every render
    (setTimeout with ITS model's playInterval), NaN for none; TimelineTick
    fires them in due order on the clock TimelineNow says, the machine's
    when that is NaN;
  - FTlAnim: the driver the checkpoints' slides, the progress lines' and the
    hover transitions run on;
  - FTlDragAt: the view whose checkpoint zrender's Draggable holds (-1);
  The two actions apply to the FIRST model whichever view dispatched them
  (timelineAction.ts: ecModel.getComponent('timeline')), while a view's
  '+' / '-', its timer's step and its drag's "no change" read its own.
  - FTlStatesDirty: a hover changed a hoverState -- the next frame applies
    it (applyChangedStates). }

function TlCss(AColour: TTyChartColor): string;
begin
  Result := 'rgba(' + IntToStr((AColour shr 16) and $FF) + ','
    + IntToStr((AColour shr 8) and $FF) + ',' + IntToStr(AColour and $FF) + ','
    + TyJsNumberToString(TyChartColorAlpha(AColour)) + ')';
end;

function TTyCustomAdvanceChart.TlInk: TTyTimelineInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  Result := Default(TTyTimelineInk);
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartTimeline', '', []);
  Result.Line := TlCss(TTyChartColor(st.BorderColor));
  Result.EmptyFill := TlCss(TTyChartColor(st.Background.Color));
  Result.Border := Result.Line;
  st := model.ResolveStyle('TyAdvChartTimelineProgress', '', []);
  Result.Progress := TlCss(TTyChartColor(st.BorderColor));
  Result.ProgressItem := TlCss(TTyChartColor(st.Background.Color));
  st := model.ResolveStyle('TyAdvChartTimelineItem', '', []);
  Result.Item := TlCss(TTyChartColor(st.Background.Color));
  st := model.ResolveStyle('TyAdvChartTimelineItem', '', [tysHover]);
  Result.ItemEmphasis := TlCss(TTyChartColor(st.Background.Color));
  Result.ItemEmphasisBorder := TlCss(TTyChartColor(st.BorderColor));
  st := model.ResolveStyle('TyAdvChartTimelineCheckpoint', '', []);
  Result.Checkpoint := TlCss(TTyChartColor(st.Background.Color));
  Result.CheckpointBorder := TlCss(TTyChartColor(st.BorderColor));
  st := model.ResolveStyle('TyAdvChartTimelineControl', '', []);
  Result.Control := TlCss(TTyChartColor(st.Background.Color));
  Result.ControlBorder := TlCss(TTyChartColor(st.BorderColor));
  st := model.ResolveStyle('TyAdvChartTimelineControl', '', [tysHover]);
  Result.ControlEmphasis := TlCss(TTyChartColor(st.Background.Color));
  Result.ControlEmphasisBorder := TlCss(TTyChartColor(st.BorderColor));
  st := model.ResolveStyle('TyAdvChartTimelineLabel', '', []);
  Result.LabelColour := TlCss(TTyChartColor(st.TextColor));
  Result.FontFamily := st.FontName;
  Result.FontPx := TyFontPxOf(ResolveFontSize(st));
  if Result.FontPx <= 0 then Result.FontPx := 12;
  st := model.ResolveStyle('TyAdvChartTimelineLabel', '', [tysHover]);
  Result.LabelEmphasis := TlCss(TTyChartColor(st.TextColor));
end;

function TTyCustomAdvanceChart.TlClock: Double;
begin
  if IsNan(FTlNow) then Result := TyAnimClockMs else Result := FTlNow;
end;

function TTyCustomAdvanceChart.TlLive: Boolean;
begin
  Result := (FTlAnim <> nil) and (FTlAnim.ClipCount > 0);
end;

function TTyCustomAdvanceChart.TlNode: TJSONObject;
begin
  { getComponent('timeline'): the first slot }
  Result := TlNodeOf(0);
end;

function TTyCustomAdvanceChart.TlNodeOf(AIndex: Integer): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('timeline', AIndex);
  if d is TJSONObject then Result := TJSONObject(d);
end;

{ getCurrentIndex: the model's option -- its default nought where nothing
  was written; NaN for what is no number }
function TTyCustomAdvanceChart.TlCurrentIndex: Double;
begin
  Result := TlCurrentIndexOf(0);
end;

{ [R5-G] the same of the model in slot AIndex }
function TTyCustomAdvanceChart.TlCurrentIndexOf(AIndex: Integer): Double;
var
  n: TJSONObject;
  d: TJSONData;
begin
  Result := NaN;
  n := TlNodeOf(AIndex);
  if n = nil then Exit;
  d := n.Find('currentIndex');
  if d = nil then Result := 0
  else if d.JSONType = jtNumber then Result := d.AsFloat;
end;

{ the component's state transition (updateStates): its animation enabled,
  stateAnimation's duration above nought -- of the model in slot AIndex }
function TTyCustomAdvanceChart.TlAnimCfg(AIndex: Integer): TTyTlAnimCfg;
var
  node, root, sa, rsa: TJSONObject;
  d: TJSONData;
  on: Boolean;
  dur, delay: Double;
  easing: string;

  function Get(const AKey: string): TJSONData;
  begin
    Result := nil;
    if sa <> nil then Result := sa.Find(AKey);
    if ((Result = nil) or (Result.JSONType = jtNull)) and (rsa <> nil) then
      Result := rsa.Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
  end;

begin
  Result := Default(TTyTlAnimCfg);
  Result.Driver := FTlAnim;
  Result.Allowed := AnimAllowed;
  node := TlNodeOf(AIndex);
  root := nil;
  if (FOption <> nil) and (FOption.Root is TJSONObject) then root := TJSONObject(FOption.Root);
  { isAnimationEnabled: the timeline's own `animation`, else the root's
    ('auto' when nothing is written) }
  on := Result.Allowed;
  d := nil;
  if node <> nil then d := node.Find('animation');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    if root <> nil then d := root.Find('animation') else d := nil;
    if (d <> nil) and not TyTlTruthy(d) then on := False;
  end
  else if not TyTlTruthy(d) then on := False;
  if not on then Exit;
  sa := nil;
  rsa := nil;
  if node <> nil then
  begin
    d := node.Find('stateAnimation');
    if d is TJSONObject then sa := TJSONObject(d);
  end;
  if root <> nil then
  begin
    d := root.Find('stateAnimation');
    if d is TJSONObject then rsa := TJSONObject(d);
  end;
  d := Get('duration');
  if d = nil then dur := 300
  else if d.JSONType = jtNumber then dur := d.AsFloat
  else dur := NaN;
  { duration > 0, a comparison NaN fails }
  if not (dur > 0) then Exit;
  d := Get('delay');
  if (d <> nil) and (d.JSONType = jtNumber) then delay := d.AsFloat else delay := 0;
  d := Get('easing');
  if (d <> nil) and (d.JSONType = jtString) then easing := d.AsString
  else if d = nil then easing := 'cubicOut'
  else easing := '';
  Result.HasStateCfg := True;
  Result.StateCfg := TyAnimCfg(dur, delay, easing);
end;

procedure TTyCustomAdvanceChart.SolveTimeline(APPI: Integer);
var
  node, root: TJSONObject;
  s, w, h, interval: Double;
  meas: ITyTextMeasurer;
  n, k: Integer;
  v: TTyTimelineView;
begin
  { [R5-G] A VIEW FOR EVERY TIMELINE MODEL, by its slot (upstream's
    component views: each renders its own model, each sets its own play
    timer). A slot no model holds -- a hole, a model gone -- has no view:
    remove() and dispose() clear its timer. }
  n := 0;
  if FOption <> nil then n := FOption.ComponentCount('timeline');
  for k := n to High(FTlViews) do FreeAndNil(FTlViews[k]);
  SetLength(FTlViews, n);
  SetLength(FTlDues, n);
  if (FTlDragAt >= n) then FTlDragAt := -1;
  if APPI <= 0 then APPI := 96;
  s := APPI / 96;
  w := (FLastRect.Right - FLastRect.Left) / s;
  h := (FLastRect.Bottom - FLastRect.Top) / s;
  root := nil;
  if (FOption <> nil) and (FOption.Root is TJSONObject) then root := TJSONObject(FOption.Root);
  { the layout measures in css px }
  meas := NewTextMeasurer(96);
  for k := 0 to n - 1 do
  begin
    node := TlNodeOf(k);
    if node = nil then
    begin
      FreeAndNil(FTlViews[k]);
      FTlDues[k] := NaN;
      if FTlDragAt = k then FTlDragAt := -1;
      Continue;
    end;
    if FTlAnim = nil then FTlAnim := NewAnimDriver;
    if FTlViews[k] = nil then
    begin
      Inc(FTlUidSeq);
      FTlViews[k] := TTyTimelineView.Create('ec_tl_' + IntToStr(FTlUidSeq));
      FTlViews[k].Dragging := FTlDragAt = k;
    end;
    v := FTlViews[k];
    { getViewRect in createBoxLayoutReference's container [Batch 154]; a cell
      of no size far off the canvas (upstream's not-a-number view rect draws
      nothing, and an axis of no length is no number to compare here) }
    v.HasRef := ComponentRefCss('timeline', k, v.Ref);
    if v.HasRef and not TyXYWHHasSize(v.Ref) then
      v.Ref := TyXYWH(TyBoxNowhere, TyBoxNowhere, TyBoxNowhereSize, TyBoxNowhereSize);
    v.Render(node, root, w, h, TlInk, meas, TlAnimCfg(k),
      FOption.GetBool('useUTC', False));
    { _doPlayStop: the timer cleared, and set again while ITS model plays --
      setTimeout(fn, playInterval) from now }
    FTlDues[k] := NaN;
    if v.PlayState then
    begin
      interval := v.PlayInterval;
      if IsNan(interval) then interval := 0;
      FTlDues[k] := TlClock + interval;
    end;
  end;
  if (FTlDragAt >= 0) and (FTlViews[FTlDragAt] = nil) then FTlDragAt := -1;
  TlArmTimer;
  FTlStatesDirty := False;
  { the flush: what the render started takes its start now }
  if FTlAnim <> nil then
  begin
    FTlAnim.Update(AnimClock, True);
    AnimArmTimer;
  end;
end;

function TTyCustomAdvanceChart.BuildTimeline(AList: TTyPaintList): Integer;
var
  i, k, lt, lk: Integer;
  ctx: TTyGfxPaintCtx;
  pe: TTyChartElement;
  meas: ITyTextMeasurer;
  el: TTyGfxEl;
  v: TTyTimelineView;
begin
  Result := 0;
  meas := nil;
  { [R5-G] every view, in the models' order: at an equal z a later
    component's group joins the root later and is drawn over }
  lk := -1;
  lt := 0;
  for k := 0 to High(FTlViews) do
  begin
    { [R5-J] the elements the last one added take its zlevel }
    if lk >= 0 then LevelTail(AList, lt, 'timeline', lk);
    lt := AList.Count;
    lk := k;
    v := FTlViews[k];
    if (v = nil) or not v.Shown then Continue;
    v.UpdateTransforms;
    if meas = nil then meas := NewTextMeasurer(96);
    ctx := Default(TTyGfxPaintCtx);
    if FLastPPI > 0 then ctx.Scale := FLastPPI / 96 else ctx.Scale := 1;
    ctx.HasInk := False;
    for i := 0 to High(v.Els) do
    begin
      el := v.Els[i];
      if el.Ignore then Continue;
      if not v.Drawable(i, meas) then Continue;
      if not TyGfxPaintElement(el, meas, ctx, pe) then Continue;
      { the pointer is the timeline's own: nothing in the paint list answers
        for it }
      pe.Silent := True;
      pe.Datum := TyChartDatum(-1, -1);
      { [R5-J] z here, the zlevel the element's own (LevelTail: the
        timeline's, else the root's) [was: the zlevel folded into z] }
      pe.Z := Round(el.Z);
      pe.Z2 := Round(el.Z2);
      AList.Add(pe);
      Inc(Result);
    end;
  end;
  if lk >= 0 then LevelTail(AList, lt, 'timeline', lk);
end;

function TTyCustomAdvanceChart.TlView(AIndex: Integer): TTyTimelineView;
begin
  if (AIndex >= 0) and (AIndex <= High(FTlViews)) then Result := FTlViews[AIndex]
  else Result := nil;
end;

function TTyCustomAdvanceChart.TlHitAt(AX, AY: Integer; out ATl, AEl: Integer): Boolean;
var
  s, x, y: Double;
  k: Integer;
  v: TTyTimelineView;
  meas: ITyTextMeasurer;
begin
  Result := False;
  ATl := -1;
  AEl := -1;
  if (Length(FTlViews) = 0) or (csDesigning in ComponentState) then Exit;
  { [R5-D] under the loading mask -- [R5-J] by its zlevel (below) }
  if FLastPPI > 0 then s := FLastPPI / 96 else s := 1;
  x := AX / s;
  y := AY / s;
  { zrender's Handler hit-tests nothing outside the canvas }
  if (x < 0) or (y < 0) or (x > (FLastRect.Right - FLastRect.Left) / s)
    or (y > (FLastRect.Bottom - FLastRect.Top) / s) then Exit;
  meas := NewTextMeasurer(96);
  { [R5-G] the views top down: a later one is drawn over an earlier }
  for k := High(FTlViews) downto 0 do
  begin
    { [R5-J] its zlevel: under the mask, or not the canvas searched }
    if MaskOver(ModelZLevel('timeline', k)) or not HitIn(ModelZLevel('timeline', k)) then Continue;
    v := FTlViews[k];
    if (v = nil) or not v.Shown then Continue;
    AEl := v.HitAt(x, y, meas);
    if AEl >= 0 then
    begin
      ATl := k;
      Exit(True);
    end;
  end;
  AEl := -1;
end;

{ the first due of the views' timers, NaN for none; AAt the view (the lower
  slot of two due at once: every render sets the timers in the models' order,
  and the queue fires an equal due in the order it was set) }
function TTyCustomAdvanceChart.TlNextDue(out AAt: Integer): Double;
var k: Integer;
begin
  Result := NaN;
  AAt := -1;
  for k := 0 to High(FTlDues) do
    if (not IsNan(FTlDues[k])) and (IsNan(Result) or (FTlDues[k] < Result)) then
    begin
      Result := FTlDues[k];
      AAt := k;
    end;
end;

procedure TTyCustomAdvanceChart.TlArmTimer;
var ms, due: Double; at: Integer;
begin
  due := TlNextDue(at);
  if IsNan(FTlNow) and not IsNan(due) and not (csDesigning in ComponentState) then
  begin
    if FTlTimer = nil then
    begin
      FTlTimer := TTimer.Create(nil);
      FTlTimer.Enabled := False;
      FTlTimer.OnTimer := @TlTimerFired;
    end;
    ms := due - TyAnimClockMs;
    if ms < 1 then ms := 1;
    if ms > MaxInt then ms := MaxInt;
    FTlTimer.Enabled := False;
    FTlTimer.Interval := Ceil(ms);
    FTlTimer.Enabled := True;
  end
  else if FTlTimer <> nil then
    FTlTimer.Enabled := False;
end;

procedure TTyCustomAdvanceChart.TlTimerFired(Sender: TObject);
begin
  if FTlTimer <> nil then FTlTimer.Enabled := False;
  TimelineTick(TlClock);
end;

procedure TTyCustomAdvanceChart.TimelineTick(ANowMs: Double);
var
  t, cur, due: Double;
  node: TJSONObject;
  k: Integer;
begin
  repeat
    due := TlNextDue(k);
    if IsNan(due) or (due > ANowMs) then Break;
    t := due;
    FTlDues[k] := NaN;
    { the clock is the timer's due while it runs }
    if not IsNan(FTlNow) then FTlNow := t;
    node := TlNodeOf(k);
    if node = nil then Continue;
    { _changeTimeline(current +/- 1), ITS model read now [R5-G] }
    cur := TlCurrentIndexOf(k);
    if TyTlTruthy(node.Find('rewind')) then TlChange(k, cur - 1, True)
    else TlChange(k, cur + 1, True);
  until False;
  TlArmTimer;
end;

{ _changeTimeline: the timelineChange action from view ATl -- which the
  action applies to the first model [R5-G] }
procedure TTyCustomAdvanceChart.TlChange(ATl: Integer; AIndex: Double; AHasIndex: Boolean);
var
  p: string;
  v: TTyTimelineView;
begin
  v := TlView(ATl);
  if v = nil then Exit;
  p := '{"type":"timelineChange"';
  if AHasIndex and not (IsNan(AIndex) or IsInfinite(AIndex)) then
    p := p + ',"currentIndex":' + TyJsNumberToString(AIndex);
  p := p + ',"from":"' + v.Uid + '"}';
  DispatchAction(p);
end;

{ _handlePlayClick(!playState) of view ATl: its timer cleared first; the
  action plays or stops the first model [R5-G] }
procedure TTyCustomAdvanceChart.TlPlayClick(ATl: Integer; APlay: Boolean);
var v: TTyTimelineView;
begin
  v := TlView(ATl);
  if v = nil then Exit;
  FTlDues[ATl] := NaN;
  TlArmTimer;
  if APlay then
    DispatchAction('{"type":"timelinePlayChange","playState":true,"from":"' + v.Uid + '"}')
  else
    DispatchAction('{"type":"timelinePlayChange","playState":false,"from":"' + v.Uid + '"}');
end;

procedure TTyCustomAdvanceChart.TlClick(ATl, AEl: Integer);
var
  r: TTyTlRole;
  cur: Double;
  v: TTyTimelineView;
begin
  v := TlView(ATl);
  if (v = nil) or (AEl < 0) or (AEl > High(v.Els)) then Exit;
  r := v.RoleOf(AEl);
  { '+' and '-' from the view's own model [R5-G] }
  cur := TlCurrentIndexOf(ATl);
  case r.Kind of
    tlrTick, tlrLabel: TlChange(ATl, r.Value, True);
    tlrNext: if v.Inverse then TlChange(ATl, cur - 1, True) else TlChange(ATl, cur + 1, True);
    tlrPrev: if v.Inverse then TlChange(ATl, cur + 1, True) else TlChange(ATl, cur - 1, True);
    tlrPlay: TlPlayClick(ATl, True);
    tlrStop: TlPlayClick(ATl, False);
  end;
end;

{ the view a timeline target names, nil when that view has been rendered
  again since (or is gone) }
function TTyCustomAdvanceChart.TlTargetView(const ATarget: TTyChartEventTarget): TTyTimelineView;
begin
  Result := nil;
  if ATarget.HdKind <> 10 then Exit;
  Result := TlView(ATarget.HdSeries);
  if (Result <> nil) and (ATarget.HdGen <> Result.Gen) then Result := nil;
end;

{ [R5-I] A TIMELINE TICK AS A DATA ITEM (SliderTimelineView._renderAxisTick):
  where its item model says tooltip -- the item's own key (null falls
  through), the timeline's, the model's default {trigger: 'item'} -- the
  tick's ecData has its value as the dataIndex and the timeline as its
  dataModel: the tooltip's data item, and the chart's mouse events carry
  the timeline's getDataParams. A category timeline's data: the value its
  index, the name the item's value as a string; any other, the value as
  written and no name. }
function TTyCustomAdvanceChart.TlTickData(ATl, AEl: Integer;
  out AParams: TTyChartCallbackParams; out AModel: TTyEventModel): Boolean;
var
  v: TTyTimelineView;
  r: TTyTlRole;
  node: TJSONObject;
  d, data, item: TJSONData;
  want, cat: Boolean;
  nm: string;
begin
  Result := False;
  AParams := TyChartBlankParams;
  AModel := Default(TTyEventModel);
  v := TlView(ATl);
  if (v = nil) or (AEl < 0) or (AEl > High(v.Els)) then Exit;
  r := v.RoleOf(AEl);
  if r.Kind <> tlrTick then Exit;
  node := TlNodeOf(ATl);
  if node = nil then Exit;
  want := True;
  d := node.Find('tooltip');
  if (d <> nil) and (d.JSONType <> jtNull) then want := JsTruthy(d);
  data := node.Find('data');
  item := nil;
  if (data is TJSONArray) and (r.Index >= 0) and (r.Index < data.Count) then
    item := data.Items[r.Index];
  if item is TJSONObject then
  begin
    d := TJSONObject(item).Find('tooltip');
    if (d <> nil) and (d.JSONType <> jtNull) then want := JsTruthy(d);
  end;
  if not want then Exit;
  d := node.Find('axisType');
  cat := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'category');
  nm := '';
  if cat then
  begin
    { getDataItemValue: an object's value, else the item }
    if item is TJSONObject then d := TJSONObject(item).Find('value') else d := item;
    if d <> nil then
      case d.JSONType of
        jtString: nm := d.AsString;
        jtNumber: nm := TyJsNumberToString(d.AsFloat);
        jtBoolean: if d.AsBoolean then nm := 'true' else nm := 'false';
      end;
  end;
  AParams.ComponentType := 'timeline';
  AParams.ComponentSubType := 'slider';
  AParams.ComponentIndex := ATl;
  AParams.SeriesIndex := -1;
  AParams.Name := nm;
  AParams.DataIndex := r.Index;
  AParams.RawDataIndex := r.Index;
  if cat then SetLength(AParams.Values, 1) else SetLength(AParams.Values, 1);
  if cat then AParams.Values[0] := r.Index else AParams.Values[0] := r.Value;
  AParams.ValueText := TyChartValueText(AParams.Values[0]);
  AModel.Valid := True;
  AModel.MainType := 'timeline';
  AModel.SubType := 'slider';
  AModel.Index := ATl;
  AModel.Name := nm;
  Result := True;
end;

function TTyCustomAdvanceChart.TlTipItem(AX, AY: Integer; out ATl, ATick: Integer): Boolean;
var
  k, q: Integer;
  prm: TTyChartCallbackParams;
  mdl: TTyEventModel;
begin
  Result := False;
  ATl := -1;
  ATick := -1;
  if not TlHitAt(AX, AY, k, q) then Exit;
  if not TlTickData(k, q, prm, mdl) then Exit;
  ATl := k;
  ATick := prm.DataIndex;
  Result := True;
end;

{ _showSeriesItemTooltip's cascade over a timeline's data item: [the
  item's model, the timeline's (its default tooltip {trigger: 'item'})]
  over the global component }
function TTyCustomAdvanceChart.TipTlSpec(ATl, ATick: Integer): TTyTooltipSpec;
var
  node: TJSONObject;
  d, data: TJSONData;
  lvItem, lvTl: TJSONObject;
  k: Integer;
begin
  lvItem := nil;
  lvTl := TJSONObject.Create(['trigger', 'item']);
  try
    node := TlNodeOf(ATl);
    if node <> nil then
    begin
      d := node.Find('tooltip');
      if d is TJSONObject then
        for k := 0 to d.Count - 1 do
          lvTl.Elements[TJSONObject(d).Names[k]] := d.Items[k].Clone;
      data := node.Find('data');
      if (data is TJSONArray) and (ATick >= 0) and (ATick < data.Count)
        and (data.Items[ATick] is TJSONObject) then
      begin
        d := TJSONObject(data.Items[ATick]).Find('tooltip');
        if d is TJSONObject then lvItem := TJSONObject(d.Clone);
      end;
    end;
    Result := TyTooltipSpecOfLevels(FOption, [lvItem, lvTl]);
  finally
    lvTl.Free;
    lvItem.Free;
  end;
end;

{ its text: a formatter over the timeline's getDataParams (formatTpl: {a}
  the series' name, undefined here; {b} the name; {c} the value), else
  formatTooltip's nameValue with no name -- the tick's axis label }
function TTyCustomAdvanceChart.TipTlText(ATl, ATick: Integer;
  const ASpec: TTyTooltipSpec): string;
var
  prm: TTyChartCallbackParams;
  mdl: TTyEventModel;
  v: TTyTimelineView;
  k: Integer;
  params: TTyChartParams;
begin
  Result := '';
  v := TlView(ATl);
  if v = nil then Exit;
  for k := 0 to High(v.Els) do
    if (v.RoleOf(k).Kind = tlrTick) and (v.RoleOf(k).Index = ATick) then
    begin
      if not TlTickData(ATl, k, prm, mdl) then Exit;
      if ASpec.HasFormatter then
      begin
        prm.SeriesName := 'undefined';
        SetLength(params, 1);
        params[0] := prm;
        TyChartResolveText(ASpec.Formatter, params, Result, True);
      end
      { axis.scale.getLabel of the tick: a category's name (another
        axis' value as a number prints) }
      else if prm.Name <> '' then Result := prm.Name
      else Result := prm.ValueText;
      Exit;
    end;
end;

procedure TTyCustomAdvanceChart.TlMouseOver(const ATarget: TTyChartEventTarget);
var v: TTyTimelineView;
begin
  v := TlTargetView(ATarget);
  if v = nil then Exit;
  if not v.IsDispatcher(ATarget.HdRow) then Exit;
  { singleEnterEmphasis: the flag; the frame applies it }
  v.Hover[ATarget.HdRow] := True;
  FTlStatesDirty := True;
end;

procedure TTyCustomAdvanceChart.TlMouseOut(const ATarget: TTyChartEventTarget);
var v: TTyTimelineView;
begin
  v := TlTargetView(ATarget);
  if v = nil then Exit;
  if not v.IsDispatcher(ATarget.HdRow) then Exit;
  if not v.Hover[ATarget.HdRow] then Exit;
  v.Hover[ATarget.HdRow] := False;
  FTlStatesDirty := True;
end;

procedure TTyCustomAdvanceChart.TlApplyStates;
var i, k: Integer;
begin
  if not FTlStatesDirty then Exit;
  FTlStatesDirty := False;
  if Length(FTlViews) = 0 then Exit;
  for k := 0 to High(FTlViews) do
    if FTlViews[k] <> nil then
      for i := 0 to High(FTlViews[k].Els) do FTlViews[k].ApplyStates(i);
  DropStatic;
  InvalidateFrame;
  AnimArmTimer;
end;

procedure TTyCustomAdvanceChart.TlDragStart(const ATarget: TTyChartEventTarget);
var v: TTyTimelineView;
begin
  v := TlTargetView(ATarget);
  if v = nil then Exit;
  if (ATarget.HdRow < 0) or (ATarget.HdRow > High(v.Els)) then Exit;
  if v.RoleOf(ATarget.HdRow).Kind <> tlrPointer then Exit;
  FTlDragAt := ATarget.HdSeries;
  v.Dragging := True;
end;

{ _pointerChangeTimeline of view ATl: its checkpoint, its nearest tick, and
  the "no change" its own model's index answers [R5-G] }
procedure TTyCustomAdvanceChart.TlPointerChange(ATl: Integer; AX, AY: Integer; ATrigger: Boolean);
var
  s, coord: Double;
  target: Integer;
  v: TTyTimelineView;
begin
  v := TlView(ATl);
  if (v = nil) or not v.Shown then Exit;
  if FLastPPI > 0 then s := FLastPPI / 96 else s := 1;
  coord := v.DragTo(AX / s, AY / s);
  target := v.NearestTick(coord);
  DropStatic;
  InvalidateFrame;
  if ATrigger or ((target <> TlCurrentIndexOf(ATl)) and v.Realtime) then
    TlChange(ATl, target, target >= 0);
end;

procedure TTyCustomAdvanceChart.TlDragMove(AX, AY: Integer);
var k: Integer;
begin
  k := FTlDragAt;
  if (k < 0) or (k > High(FTlDues)) then Exit;
  { _handlePointerDrag: the view's timer cleared, the checkpoint moved }
  FTlDues[k] := NaN;
  TlArmTimer;
  TlPointerChange(k, AX, AY, False);
end;

procedure TTyCustomAdvanceChart.TlDragEnd(AX, AY: Integer);
var
  k: Integer;
  v: TTyTimelineView;
begin
  k := FTlDragAt;
  if k < 0 then Exit;
  FTlDragAt := -1;
  v := TlView(k);
  if v <> nil then v.Dragging := False;
  { _handlePointerDragend: a change whatever the index }
  TlPointerChange(k, AX, AY, True);
end;

{ every view and its timer, as a notMerge or the control's end takes them }
procedure TTyCustomAdvanceChart.TlDropViews;
var k: Integer;
begin
  for k := 0 to High(FTlViews) do FreeAndNil(FTlViews[k]);
  FTlViews := nil;
  FTlDues := nil;
  FTlDragAt := -1;
end;

{ resetOption('timeline') with the timeline's replaceMerge, and the update
  after it }
procedure TTyCustomAdvanceChart.TlMerge;
var
  node: TJSONObject;
  d: TJSONData;
  rep: array of string;
  k: Integer;

  procedure AddType(A: TJSONData);
  begin
    if (A = nil) or (A.JSONType <> jtString) then Exit;
    if not TyOptionIsComponentType(A.AsString) then Exit;
    SetLength(rep, Length(rep) + 1);
    rep[High(rep)] := A.AsString;
  end;

begin
  rep := nil;
  node := TlNode;
  if node <> nil then
  begin
    d := node.Find('replaceMerge');
    if d is TJSONArray then
    begin
      for k := 0 to d.Count - 1 do AddType(d.Items[k]);
    end
    else
      AddType(d);
  end;
  FMergeOldKeys := AnimViewKeys;
  FMergeOldUtKeys := AnimUtKeys;
  FMergeOldAxes := AxisViewKeys;
  FMergeFirst := True;
  FMergeResize := False;
  MediaViewSize;
  { prepareAndUpdate: an update whose models were merged -- armed as a
    merge's when a frame was merged; without one the same models render
    again, every series updating from where it stands }
  if FOption.TimelineReset(rep, @MergeBefore, @MergePass) then
  begin
    { [R7-AH] prepareAndUpdate's prepare: the views the frame's new models
      make, after every one there is [was: none recorded] }
    ViewsPrepare(False);
    FAnimPending := True;
    FDirty := True;
    { its update renders every parallelAxis view: the payload is no
      axisAreaSelect (fromAxisAreaSelect) }
    FParBrushSkip := -1;
    Invalidate;
    { and rendered now, inside the dispatch, as prepareAndUpdate does: the
      brushSelect its visual stage dispatches goes with the action
      [milestone D5-D8: the render waited for the next frame]
      [R2-E: a batch's item resets the option and no more -- the update
      renders once, after the last item, from the render before the batch
      (DoBatchGeneric)] }
    if FBatchDefer > 0 then FBatchConvertDue := True
    else ConvertReady;
  end
  else
    FullUpdate;
end;

procedure TTyCustomAdvanceChart.DoTimelineChange(APayload: TJSONObject);
var
  node, full, ev: TJSONObject;
  d: TJSONData;
  idx: Double;
  values: TTyDoubleArray;
  names: TTyStringArray;
  items: TTyJsonObjArray;
  stop: Boolean;
  k: Integer;
  pp: string;
begin
  node := TlNode;
  { upstream reads the model's replaceMerge whatever there is: without a
    timeline it throws, and nothing happens here }
  if node = nil then Exit;
  stop := False;
  d := APayload.Find('currentIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    full := TyTimelineFullOption(node, TlInk);
    try
      TyTimelineData(full, FOption.GetBool('useUTC', False), values, names, items);
      { setCurrentIndex: `this.option.loop` }
      idx := TyTimelineNormIndex(TyTlJsNum(d), Length(values), TyTlTruthy(full.Find('loop')));
      TyTlPut(node, 'currentIndex', TyTlNumJson(idx));
      { played to the end without a loop: the play stops, and says so }
      if (not TyTlTruthy(full.Find('loop'))) and (idx >= Length(values) - 1)
        and TyTlTruthy(full.Find('autoPlay')) then
      begin
        TyTlPut(node, 'autoPlay', TJSONBoolean.Create(False));
        stop := True;
        pp := '{"type":"timelinePlayChange","playState":false';
        d := APayload.Find('from');
        if d <> nil then pp := pp + ',"from":' + d.AsJSON;
        pp := pp + '}';
        DispatchActionObject(TJSONObject(GetJSON(pp)));
      end;
    finally
      full.Free;
    end;
  end;
  TlMerge;
  { the event: defaults(the model's currentIndex, payload) }
  ev := TJSONObject.Create;
  try
    d := node.Find('currentIndex');
    if d <> nil then ev.Add('currentIndex', d.Clone)
    else ev.Add('currentIndex', TJSONIntegerNumber.Create(0));
    for k := 0 to APayload.Count - 1 do
    begin
      if ev.IndexOfName(APayload.Names[k]) >= 0 then
      begin
        if ev.Find(APayload.Names[k]).JSONType <> jtNull then Continue;
        ev.Delete(APayload.Names[k]);
      end;
      ev.Add(APayload.Names[k], APayload.Items[k].Clone);
    end;
    ev.Elements['type'] := TJSONString.Create('timelinechanged');
    EmitPayloadEvent('timelinechanged', ev.AsJSON);
  finally
    ev.Free;
  end;
  { the action the end dispatched waits for this one -- and this one's
    render came first (TlMerge renders inside the dispatch): the checkpoint
    the second render meets is already sliding, and its
    stopAnimation(forward) puts it at its tick [milestone D5-D8: a merged
    frame waited for the next frame, so the timeline was rendered here]
    [F4b: it is dispatched where the action decides it (api.dispatchAction
    while IN_EC_CYCLE) and waits in the one queue -- after this action's
    update and event, before the brushSelect the update dispatched.] }
end;

procedure TTyCustomAdvanceChart.DoTimelinePlayChange(APayload: TJSONObject);
var
  node, ev: TJSONObject;
  d: TJSONData;
begin
  node := TlNode;
  d := APayload.Find('playState');
  if (node <> nil) and (d <> nil) and (d.JSONType <> jtNull) then
    TyTlPut(node, 'autoPlay', TJSONBoolean.Create(TyTlTruthy(d)));
  { update: every view renders again now (the timer with them), the series
    updating from where they stand }
  FullUpdate;
  ev := TJSONObject(APayload.Clone);
  try
    ev.Elements['type'] := TJSONString.Create('timelineplaychanged');
    EmitPayloadEvent('timelineplaychanged', ev.AsJSON);
  finally
    ev.Free;
  end;
end;

function TTyCustomAdvanceChart.TimelineView: TTyTimelineView;
begin
  Result := TlView(0);
end;

function TTyCustomAdvanceChart.TimelineDue: Double;
begin
  Result := TimelineDueAt(0);
end;

function TTyCustomAdvanceChart.TimelineViewCount: Integer;
begin
  Result := Length(FTlViews);
end;

function TTyCustomAdvanceChart.TimelineViewAt(AIndex: Integer): TTyTimelineView;
begin
  Result := TlView(AIndex);
end;

function TTyCustomAdvanceChart.TimelineDueAt(AIndex: Integer): Double;
begin
  if (AIndex >= 0) and (AIndex <= High(FTlDues)) then Result := FTlDues[AIndex]
  else Result := NaN;
end;
