{ Part of tyControls.AdvanceChart (included, not a unit): the timeline. Moved out of the
  unit only to keep it readable; what the control is and why it is built the way it is,
  see the unit header. }

{ ==================== the timeline [Batch 129, C21] ====================

  SliderTimelineView's render and handlers, and the two actions. The
  option, the model and the view's elements are tyControls.AdvChart.Timeline;
  this is what upstream keeps outside them:
  - FTlView: the first timeline model's view, from render to render (its
    checkpoint element lives in it); a notMerge, or the model going, makes
    a new one -- upstream's view is disposed with its model;
  - FTlDue: the play timer _doPlayStop sets at every render (setTimeout
    with playInterval), NaN for none; TimelineTick fires it on the clock
    TimelineNow says, the machine's when that is NaN;
  - FTlAnim: the driver the checkpoint's slide, the progress line's and the
    hover transitions run on;
  - FTlDragging: zrender's Draggable holds the checkpoint;
  - FTlStatesDirty: a hover changed a hoverState -- the next frame applies
    it (applyChangedStates). }

function TlCss(AColour: TTyChartColor): string;
begin
  Result := 'rgba(' + IntToStr((AColour shr 16) and $FF) + ','
    + IntToStr((AColour shr 8) and $FF) + ',' + IntToStr(AColour and $FF) + ','
    + TyJsNumberToString(TyChartColorAlpha(AColour)) + ')';
end;

function TTyAdvanceChart.TlInk: TTyTimelineInk;
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

function TTyAdvanceChart.TlClock: Double;
begin
  if IsNan(FTlNow) then Result := TyAnimClockMs else Result := FTlNow;
end;

function TTyAdvanceChart.TlLive: Boolean;
begin
  Result := (FTlAnim <> nil) and (FTlAnim.ClipCount > 0);
end;

function TTyAdvanceChart.TlNode: TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if FOption = nil then Exit;
  { getComponent('timeline'): the first slot }
  d := FOption.ComponentAt('timeline', 0);
  if d is TJSONObject then Result := TJSONObject(d);
end;

{ getCurrentIndex: the model's option -- its default nought where nothing
  was written; NaN for what is no number }
function TTyAdvanceChart.TlCurrentIndex: Double;
var
  n: TJSONObject;
  d: TJSONData;
begin
  Result := NaN;
  n := TlNode;
  if n = nil then Exit;
  d := n.Find('currentIndex');
  if d = nil then Result := 0
  else if d.JSONType = jtNumber then Result := d.AsFloat;
end;

{ the component's state transition (updateStates): its animation enabled,
  stateAnimation's duration above nought }
function TTyAdvanceChart.TlAnimCfg: TTyTlAnimCfg;
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
  node := TlNode;
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

procedure TTyAdvanceChart.SolveTimeline(APPI: Integer);
var
  node, root: TJSONObject;
  s, w, h, interval: Double;
  meas: ITyTextMeasurer;
begin
  node := TlNode;
  if node = nil then
  begin
    { the model went: its view too -- remove() and dispose() clear the timer }
    FreeAndNil(FTlView);
    FTlDue := NaN;
    FTlDragging := False;
    TlArmTimer;
    Exit;
  end;
  if FTlAnim = nil then FTlAnim := NewAnimDriver;
  if FTlView = nil then
  begin
    Inc(FTlUidSeq);
    FTlView := TTyTimelineView.Create('ec_tl_' + IntToStr(FTlUidSeq));
    FTlView.Dragging := FTlDragging;
  end;
  if APPI <= 0 then APPI := 96;
  s := APPI / 96;
  w := (FLastRect.Right - FLastRect.Left) / s;
  h := (FLastRect.Bottom - FLastRect.Top) / s;
  root := nil;
  if FOption.Root is TJSONObject then root := TJSONObject(FOption.Root);
  { the layout measures in css px }
  meas := NewTextMeasurer(96);
  { getViewRect in createBoxLayoutReference's container [Batch 154]; a cell
    of no size far off the canvas (upstream's not-a-number view rect draws
    nothing, and an axis of no length is no number to compare here) }
  FTlView.HasRef := ComponentRefCss('timeline', 0, FTlView.Ref);
  if FTlView.HasRef and not TyXYWHHasSize(FTlView.Ref) then
    FTlView.Ref := TyXYWH(TyBoxNowhere, TyBoxNowhere, TyBoxNowhereSize, TyBoxNowhereSize);
  FTlView.Render(node, root, w, h, TlInk, meas, TlAnimCfg,
    FOption.GetBool('useUTC', False));
  { _doPlayStop: the timer cleared, and set again while playing --
    setTimeout(fn, playInterval) from now }
  FTlDue := NaN;
  if FTlView.PlayState then
  begin
    interval := FTlView.PlayInterval;
    if IsNan(interval) then interval := 0;
    FTlDue := TlClock + interval;
  end;
  TlArmTimer;
  FTlStatesDirty := False;
  { the flush: what the render started takes its start now }
  FTlAnim.Update(AnimClock, True);
  AnimArmTimer;
end;

function TTyAdvanceChart.BuildTimeline(AList: TTyPaintList): Integer;
var
  i: Integer;
  ctx: TTyGfxPaintCtx;
  pe: TTyChartElement;
  meas: ITyTextMeasurer;
  el: TTyGfxEl;
begin
  Result := 0;
  if (FTlView = nil) or not FTlView.Shown then Exit;
  FTlView.UpdateTransforms;
  meas := NewTextMeasurer(96);
  ctx := Default(TTyGfxPaintCtx);
  if FLastPPI > 0 then ctx.Scale := FLastPPI / 96 else ctx.Scale := 1;
  ctx.HasInk := False;
  for i := 0 to High(FTlView.Els) do
  begin
    el := FTlView.Els[i];
    if el.Ignore then Continue;
    if not FTlView.Drawable(i, meas) then Continue;
    if not TyGfxPaintElement(el, meas, ctx, pe) then Continue;
    { the pointer is the timeline's own: nothing in the paint list answers
      for it }
    pe.Silent := True;
    pe.Datum := TyChartDatum(-1, -1);
    pe.Z := Round(el.ZLevel) * 100000 + Round(el.Z);
    pe.Z2 := Round(el.Z2);
    AList.Add(pe);
    Inc(Result);
  end;
end;

function TTyAdvanceChart.TlHitAt(AX, AY: Integer; out AEl: Integer): Boolean;
var
  s, x, y: Double;
begin
  Result := False;
  AEl := -1;
  if (FTlView = nil) or not FTlView.Shown or (csDesigning in ComponentState) then Exit;
  if FLastPPI > 0 then s := FLastPPI / 96 else s := 1;
  x := AX / s;
  y := AY / s;
  { zrender's Handler hit-tests nothing outside the canvas }
  if (x < 0) or (y < 0) or (x > (FLastRect.Right - FLastRect.Left) / s)
    or (y > (FLastRect.Bottom - FLastRect.Top) / s) then Exit;
  AEl := FTlView.HitAt(x, y, NewTextMeasurer(96));
  Result := AEl >= 0;
end;

procedure TTyAdvanceChart.TlArmTimer;
var ms: Double;
begin
  if IsNan(FTlNow) and not IsNan(FTlDue) and not (csDesigning in ComponentState) then
  begin
    if FTlTimer = nil then
    begin
      FTlTimer := TTimer.Create(nil);
      FTlTimer.Enabled := False;
      FTlTimer.OnTimer := @TlTimerFired;
    end;
    ms := FTlDue - TyAnimClockMs;
    if ms < 1 then ms := 1;
    if ms > MaxInt then ms := MaxInt;
    FTlTimer.Enabled := False;
    FTlTimer.Interval := Ceil(ms);
    FTlTimer.Enabled := True;
  end
  else if FTlTimer <> nil then
    FTlTimer.Enabled := False;
end;

procedure TTyAdvanceChart.TlTimerFired(Sender: TObject);
begin
  if FTlTimer <> nil then FTlTimer.Enabled := False;
  TimelineTick(TlClock);
end;

procedure TTyAdvanceChart.TimelineTick(ANowMs: Double);
var
  t, cur: Double;
  node: TJSONObject;
begin
  while (not IsNan(FTlDue)) and (FTlDue <= ANowMs) do
  begin
    t := FTlDue;
    FTlDue := NaN;
    { the clock is the timer's due while it runs }
    if not IsNan(FTlNow) then FTlNow := t;
    node := TlNode;
    if node = nil then Break;
    { _changeTimeline(current +/- 1), the model read now }
    cur := TlCurrentIndex;
    if TyTlTruthy(node.Find('rewind')) then TlChange(cur - 1, True)
    else TlChange(cur + 1, True);
  end;
  TlArmTimer;
end;

{ _changeTimeline: the timelineChange action from the view }
procedure TTyAdvanceChart.TlChange(AIndex: Double; AHasIndex: Boolean);
var p: string;
begin
  if FTlView = nil then Exit;
  p := '{"type":"timelineChange"';
  if AHasIndex and not (IsNan(AIndex) or IsInfinite(AIndex)) then
    p := p + ',"currentIndex":' + TyJsNumberToString(AIndex);
  p := p + ',"from":"' + FTlView.Uid + '"}';
  DispatchAction(p);
end;

procedure TTyAdvanceChart.TlClick(AEl: Integer);
var
  r: TTyTlRole;
  cur: Double;
begin
  if (FTlView = nil) or (AEl < 0) or (AEl > High(FTlView.Els)) then Exit;
  r := FTlView.RoleOf(AEl);
  cur := TlCurrentIndex;
  case r.Kind of
    tlrTick, tlrLabel: TlChange(r.Value, True);
    tlrNext: if FTlView.Inverse then TlChange(cur - 1, True) else TlChange(cur + 1, True);
    tlrPrev: if FTlView.Inverse then TlChange(cur + 1, True) else TlChange(cur - 1, True);
    tlrPlay, tlrStop:
      begin
        { _handlePlayClick(!playState): the timer cleared first }
        FTlDue := NaN;
        TlArmTimer;
        if r.Kind = tlrPlay then
          DispatchAction('{"type":"timelinePlayChange","playState":true,"from":"' + FTlView.Uid + '"}')
        else
          DispatchAction('{"type":"timelinePlayChange","playState":false,"from":"' + FTlView.Uid + '"}');
      end;
  end;
end;

procedure TTyAdvanceChart.TlMouseOver(const ATarget: TTyChartEventTarget);
begin
  if (ATarget.HdKind <> 10) or (FTlView = nil) or (ATarget.HdGen <> FTlView.Gen) then Exit;
  if not FTlView.IsDispatcher(ATarget.HdRow) then Exit;
  { singleEnterEmphasis: the flag; the frame applies it }
  FTlView.Hover[ATarget.HdRow] := True;
  FTlStatesDirty := True;
end;

procedure TTyAdvanceChart.TlMouseOut(const ATarget: TTyChartEventTarget);
begin
  if (ATarget.HdKind <> 10) or (FTlView = nil) or (ATarget.HdGen <> FTlView.Gen) then Exit;
  if not FTlView.IsDispatcher(ATarget.HdRow) then Exit;
  if not FTlView.Hover[ATarget.HdRow] then Exit;
  FTlView.Hover[ATarget.HdRow] := False;
  FTlStatesDirty := True;
end;

procedure TTyAdvanceChart.TlApplyStates;
var i: Integer;
begin
  if not FTlStatesDirty then Exit;
  FTlStatesDirty := False;
  if FTlView = nil then Exit;
  for i := 0 to High(FTlView.Els) do FTlView.ApplyStates(i);
  DropStatic;
  InvalidateFrame;
  AnimArmTimer;
end;

procedure TTyAdvanceChart.TlDragStart(const ATarget: TTyChartEventTarget);
begin
  if (ATarget.HdKind <> 10) or (FTlView = nil) or (ATarget.HdGen <> FTlView.Gen) then Exit;
  if (ATarget.HdRow < 0) or (ATarget.HdRow > High(FTlView.Els)) then Exit;
  if FTlView.RoleOf(ATarget.HdRow).Kind <> tlrPointer then Exit;
  FTlDragging := True;
  FTlView.Dragging := True;
end;

{ _pointerChangeTimeline }
procedure TTyAdvanceChart.TlPointerChange(AX, AY: Integer; ATrigger: Boolean);
var
  s, coord: Double;
  target: Integer;
begin
  if (FTlView = nil) or not FTlView.Shown then Exit;
  if FLastPPI > 0 then s := FLastPPI / 96 else s := 1;
  coord := FTlView.DragTo(AX / s, AY / s);
  target := FTlView.NearestTick(coord);
  DropStatic;
  InvalidateFrame;
  if ATrigger or ((target <> TlCurrentIndex) and FTlView.Realtime) then
    TlChange(target, target >= 0);
end;

procedure TTyAdvanceChart.TlDragMove(AX, AY: Integer);
begin
  if not FTlDragging then Exit;
  { _handlePointerDrag: the timer cleared, the checkpoint moved }
  FTlDue := NaN;
  TlArmTimer;
  TlPointerChange(AX, AY, False);
end;

procedure TTyAdvanceChart.TlDragEnd(AX, AY: Integer);
begin
  if not FTlDragging then Exit;
  FTlDragging := False;
  if FTlView <> nil then FTlView.Dragging := False;
  { _handlePointerDragend: a change whatever the index }
  TlPointerChange(AX, AY, True);
end;

{ resetOption('timeline') with the timeline's replaceMerge, and the update
  after it }
procedure TTyAdvanceChart.TlMerge;
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
    FAnimPending := True;
    FDirty := True;
    Invalidate;
    { and rendered now, inside the dispatch, as prepareAndUpdate does: the
      brushSelect its visual stage dispatches goes with the action
      [milestone D5-D8: the render waited for the next frame] }
    ConvertReady;
  end
  else
    FullUpdate;
end;

procedure TTyAdvanceChart.DoTimelineChange(APayload: TJSONObject);
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

procedure TTyAdvanceChart.DoTimelinePlayChange(APayload: TJSONObject);
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

function TTyAdvanceChart.TimelineView: TTyTimelineView;
begin
  Result := FTlView;
end;

function TTyAdvanceChart.TimelineDue: Double;
begin
  Result := FTlDue;
end;
