{ Part of tyControls.AdvanceChart (included, not a unit): animation -- the enter
  animation, the axes' groupTransition, the pause, the bar race and the axis pointer's
  slide. Moved out of the unit only to keep it readable; what the control is and why it is
  built the way it is, see the unit header. }

{ ==================== the enter animation [Batch 89] ==================== }

function TTyAdvanceChart.AnimClock: Double;
begin
  if IsNan(FAnimNow) then Result := TyAnimClockMs else Result := FAnimNow;
end;

function TTyAdvanceChart.AnimAllowed: Boolean;
begin
  { the designer streams and repaints at will and runs no timer: never }
  if csDesigning in ComponentState then Exit(False);
  case FAnimMode of
    camAlways: Result := True;
    camOff: Result := False;
  else
    Result := FAnimWindow;
  end;
end;

procedure TTyAdvanceChart.SetAnimMode(AValue: TTyChartAnimationMode);
begin
  if FAnimMode = AValue then Exit;
  FAnimMode := AValue;
  { switched off mid-flight: the picture finishes at once }
  if AValue = camOff then
  begin
    AnimDropAll;
    FAnimPending := False;
    DropStatic;
    FZrDirty := True;
    inherited Invalidate;
  end;
  { the spinner stops under camOff and turns again out of it [Batch 106] }
  if FLoadShown then AnimArmTimer;
end;

procedure TTyAdvanceChart.AnimDropAll;
var i: Integer;
begin
  if FAnimSet <> nil then FAnimSet.Clear;
  { the graphic elements at their last frames [Batch 122] }
  if FGfxView <> nil then FGfxView.Snap;
  { and the custom series' [Batch 124] }
  for i := 0 to High(FCustomViews) do
    if FCustomViews[i] <> nil then FCustomViews[i].Snap;
  AxisAnimDrop;
  { a treemap's drill-down snaps with the rest [Batch 115] }
  TmAnimDropAll;
  FAnimBind := nil;
  FAnimStBind := nil;
  FAnimFlush := False;
  FAnimLive := False;
  FAnimContinuous := False;
  AnimDropPrev;
  AnimArmTimer;
end;

{ ==================== the axes' groupTransition [Batch 96] ==================== }

procedure TTyAdvanceChart.AxisAnimDrop;
var i: Integer;
begin
  if FAxisList = nil then Exit;
  { the proxies free their clips off the driver }
  for i := 0 to FAxisList.Count - 1 do TObject(FAxisList[i]).Free;
  FAxisList.Clear;
  FAxisProxies.Clear;
end;

function TTyAdvanceChart.AxisProxyOf(const AKey: string): TTyChartAnimProxy;
begin
  if FAxisProxies = nil then Exit(nil);
  Result := TTyChartAnimProxy(FAxisProxies.Find(AKey));
end;

function TTyAdvanceChart.AnimAxisProxyCount: Integer;
begin
  if FAxisList = nil then Result := 0 else Result := FAxisList.Count;
end;

function TTyAdvanceChart.AnimAxisProxy(const AAxisKey, AAnid: string): TTyChartAnimProxy;
begin
  Result := AxisProxyOf(TyAxisAnimKey(AAxisKey, AAnid));
end;

function TTyAdvanceChart.AxesDynamic: Boolean;
begin
  Result := FAnimLive and not FAnimContinuous and (AnimAxisProxyCount > 0);
end;

{ Axis.getMinorTicksCoords, flat: each minor tick with the major interval
  it subdivides (the count of majors before it, less one) [F3b] }
function AxisMinorTicks(AAxis: TTyAxis): TTyAxisMinorTickArray;
var
  ticks: TTyScaleTickArray;
  i, n, majors: Integer;
begin
  Result := nil;
  if AAxis = nil then Exit;
  ticks := TyDrawnTicks(AAxis.Scale);
  SetLength(Result, Length(ticks));
  n := 0;
  majors := 0;
  for i := 0 to High(ticks) do
  begin
    if ticks[i].Level = 0 then
    begin
      Inc(majors);
      Continue;
    end;
    Result[n].Value := ticks[i].Value;
    Result[n].Local := AAxis.DataToLocal(ticks[i].Value);
    Result[n].Global := AAxis.DataToCoord(ticks[i].Value);
    Result[n].Interval := majors - 1;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TTyAdvanceChart.AxisAnimElementsOf(ABuild: TTyChartBuild; APPI: Integer;
  out AKeys: TTyStringArray; out AAxisKeys: TTyStringArray): TTyAxisAnimElArray;
var
  g, a, k, n: Integer;
  gb: TTyGridBuild;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  furn: TTyAxisFurniture;
  inp: TTyAxisAnimInput;
  els, all_: TTyAxisAnimElArray;
  keys, axKeys: TTyStringArray;
  akey: string;
  model: TTyStyleModel;
  scale: Double;

  { the width a pen is drawn in, device px (PaintAxis' LineWidth) }
  function PenWidth(const AKey: string): Double;
  var st: TTyStyleSet;
  begin
    st := model.ResolveStyle(AKey, '', []);
    if tpBorderWidth in st.Present then Result := st.BorderWidth else Result := 1;
    if Result < 0.05 then Result := 0.05;
    Result := Result * scale;
  end;

  procedure Take(AAxis: TTyAxis);
  var i: Integer;
  begin
    if (AAxis = nil) or not AAxis.Visible then Exit;
    spec := gb.SpecFor(AAxis);
    if spec = nil then Exit;
    furn := gb.FurnitureFor(AAxis);
    inp := Default(TTyAxisAnimInput);
    inp.ShowLine := furn.ShowLine;
    inp.ShowTicks := furn.ShowTicks and not AAxis.Scale.Blank;
    inp.ShowLabels := furn.ShowLabels and spec^.ShowLabels;
    inp.ShowSplitLine := furn.ShowSplitLine;
    inp.TickInside := furn.TickInside;
    inp.TickLength := spec^.TickLengthLogical * scale;
    inp.LineWidth := PenWidth('TyAdvChartAxisLine');
    inp.TickWidth := PenWidth('TyAdvChartAxisTick');
    inp.SplitWidth := PenWidth('TyAdvChartSplitLine');
    inp.Horizontal := AAxis.Horizontal;
    inp.Plot := gb.PlotXYWH;
    inp.ByTick := AxisByTick(AAxis);
    { [F3b] the minor ticks (not on a blank scale), the minor split lines,
      the split areas, the name }
    inp.ShowMinorTicks := furn.ShowMinorTick and not AAxis.Scale.Blank;
    inp.ShowMinorSplitLine := furn.ShowMinorSplitLine;
    inp.ShowSplitArea := furn.ShowSplitArea;
    inp.ShowName := True;
    if not IsNan(furn.MinorTickLengthLogical) then
      inp.MinorTickLength := furn.MinorTickLengthLogical * scale
    else
      inp.MinorTickLength := ActiveController.Metric(TyAdvChartMinorTickLenVar,
        TyAdvChartMinorTickLen) * scale;
    inp.MinorTickWidth := PenWidth('TyAdvChartMinorTick');
    inp.MinorSplitWidth := PenWidth('TyAdvChartMinorSplitLine');
    if inp.ShowMinorTicks or inp.ShowMinorSplitLine then
      inp.MinorTicks := AxisMinorTicks(AAxis);
    els := TyAxisAnimElements(spec^, inp);
    akey := AAxis.MainType + IntToStr(AAxis.ComponentIndex);
    SetLength(all_, n + Length(els));
    SetLength(keys, n + Length(els));
    SetLength(axKeys, n + Length(els));
    for i := 0 to High(els) do
    begin
      all_[n] := els[i];
      keys[n] := TyAxisAnimKey(akey, els[i].Anid);
      axKeys[n] := akey;
      Inc(n);
    end;
  end;

begin
  Result := nil;
  AKeys := nil;
  AAxisKeys := nil;
  all_ := nil;
  keys := nil;
  axKeys := nil;
  n := 0;
  if ABuild = nil then Exit;
  model := ActiveController.Model;
  scale := APPI / 96;
  for g := 0 to ABuild.GridCount - 1 do
  begin
    gb := ABuild.Grid(g);
    for a := 0 to gb.XAxisCount - 1 do Take(gb.XAxis(a));
    for a := 0 to gb.YAxisCount - 1 do Take(gb.YAxis(a));
  end;
  k := n;
  SetLength(all_, k);
  Result := all_;
  AKeys := keys;
  AAxisKeys := axKeys;
end;

procedure TTyAdvanceChart.AxisAnimArm(AOldBuild, ANewBuild: TTyChartBuild);
var
  oldEls, newEls: TTyAxisAnimElArray;
  oldKeys, newKeys, oldAx, newAx, nowAxes: TTyStringArray;
  kept: TStringList;
  oldIdx, oldMap: TFPHashList;
  oldList: TFPList;
  i, k: Integer;
  p, q: TTyChartAnimProxy;
  props, from: TTyAnimProps;
  model: TTyAnimModel;
  v: Pointer;
  ak: string;
begin
  if FAnim = nil then Exit;
  if FAxisList = nil then
  begin
    FAxisList := TFPList.Create;
    FAxisProxies := TFPHashList.Create;
  end;
  oldEls := AxisAnimElementsOf(AOldBuild, FLastPPI, oldKeys, oldAx);
  newEls := AxisAnimElementsOf(ANewBuild, FLastPPI, newKeys, newAx);
  oldList := FAxisList;
  oldMap := FAxisProxies;
  FAxisList := TFPList.Create;
  FAxisProxies := TFPHashList.Create;
  oldIdx := TFPHashList.Create;
  { WHICH AXIS VIEWS ARE KEPT [Batch 99]: prepareView's '_ec_' + model id +
    '_' + type is the same and the model does not ask for a new view. A
    replaced axis, or one whose type changed, is a new view: its leaves
    appear where they are. }
  kept := TStringList.Create;
  nowAxes := AxisViewKeys;
  for i := 0 to High(nowAxes) do
  begin
    ak := Copy(nowAxes[i], 1, Pos('=', nowAxes[i]) - 1);
    v := nil;
    for k := 0 to High(FAnimFreshAxes) do
      if FAnimFreshAxes[k] = ak then v := Pointer(1);
    if v <> nil then Continue;
    for k := 0 to High(FAnimOldAxisKeys) do
      if FAnimOldAxisKeys[k] = nowAxes[i] then kept.Add(ak);
  end;
  try
    { the old group's leaves by anid (getElMap) }
    for i := 0 to High(oldEls) do
      if oldIdx.Find(oldKeys[i]) = nil then
        oldIdx.Add(oldKeys[i], Pointer(PtrInt(i + 1)));
    for i := 0 to High(newEls) do
    begin
      props := TyAxisAnimProps(newEls[i]);
      p := TTyChartAnimProxy.Create(-1, -1, newKeys[i]);
      p.Animation := FAnim;
      FAxisList.Add(p);
      if FAxisProxies.Find(newKeys[i]) = nil then FAxisProxies.Add(newKeys[i], p);
      v := oldIdx.Find(newKeys[i]);
      if kept.IndexOf(newAx[i]) < 0 then v := nil;
      if v = nil then
      begin
        { NO OLD LEAF OF THAT ANID: it appears where it is }
        p.Attr(props);
        p.SetFinal(props);
        Continue;
      end;
      { the old leaf's props as they are NOW: its proxy's, while it moves }
      from := TyAxisAnimProps(oldEls[PtrInt(v) - 1]);
      q := TTyChartAnimProxy(oldMap.Find(newKeys[i]));
      if q <> nil then
        for k := 0 to High(from) do
          { a break leaf's points too: getAnimatableProps clones the shape
            as it is now [F4a] }
          if q.GetAnimProp(from[k].Key).Kind in [avkNumber, avkArray] then
            from[k].Value := TyAnimClone(q.GetAnimProp(from[k].Key));
      p.Attr(from);
      p.SetFinal(props);
      { updateProps on the axis model, at no data index }
      ak := newAx[i];
      model := TyAnimComponentModel(FOption.ComponentAt(Copy(ak, 1, 5),
        StrToIntDef(Copy(ak, 6, MaxInt), 0)), FOption.Root, 'axis');
      model.Payload := FAnimPayload;
      model.HasPayload := FAnimHasPayload;
      TyUpdateProps(p, props, model, TyAnimCallNoIndex);
    end;
  finally
    kept.Free;
    oldIdx.Free;
    for i := 0 to oldList.Count - 1 do TObject(oldList[i]).Free;
    oldList.Free;
    oldMap.Free;
  end;
end;

{ a render's sunburst pieces (not the return circle, which no item is
  morphed from), each replacing the one its row had [milestone D5-D8] }
procedure TTyAdvanceChart.UtStaleHarvest;
var
  i, k: Integer;
  pe: PTyChartElement;
  idx: TFPHashList;
  key: string;
  v: Pointer;
begin
  if FPaintList = nil then Exit;
  idx := nil;
  try
    for i := 0 to FPaintList.Count - 1 do
    begin
      pe := FPaintList.Ref(i);
      if (pe^.Anim.Role <> carSunPiece) or (pe^.Anim.Index <= 0) then Continue;
      if idx = nil then
      begin
        idx := TFPHashList.Create;
        for k := 0 to High(FUtStale) do
          idx.Add(IntToStr(FUtStale[k].Anim.Series) + ':' + IntToStr(FUtStale[k].Anim.Index),
            Pointer(PtrInt(k + 1)));
      end;
      key := IntToStr(pe^.Anim.Series) + ':' + IntToStr(pe^.Anim.Index);
      v := idx.Find(key);
      if v <> nil then
        FUtStale[PtrInt(v) - 1] := pe^
      else
      begin
        SetLength(FUtStale, Length(FUtStale) + 1);
        FUtStale[High(FUtStale)] := pe^;
        idx.Add(key, Pointer(PtrInt(Length(FUtStale))));
      end;
    end;
  finally
    idx.Free;
  end;
end;

procedure TTyAdvanceChart.AnimDropPrev;
begin
  FAnimPrev := Default(TTyChartAnimPrev);
  FreeAndNil(FAnimOldBuild);
  FAnimOldBindings := nil;
end;

function TTyAdvanceChart.AnimViewKeys: TTyStringArray;
var
  i, n: Integer;
  id: string;
begin
  { the view id is '_ec_' + model.id + '_' + type, the type compared apart:
    makeIdAndName's id -- the written one, else from the name, else the
    dummy name -- which a merge never changes [Batch 95] }
  Result := nil;
  n := FOption.ComponentCount('series');
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    id := FOption.ComponentId('series', i);
    if id <> '' then Result[i] := 'i:' + id
    else Result[i] := 'x:' + IntToStr(i);
  end;
end;

function TTyAdvanceChart.AnimUtKeys: TTyUtSeriesKeysArray;
var
  i, n: Integer;
  own, t: TJSONData;
  typ: string;
begin
  Result := nil;
  if FOption = nil then Exit;
  n := FOption.ComponentCount('series');
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    own := TyAnimSeriesModel(FOption.Root, i, 0).Own;
    typ := '';
    if own is TJSONObject then
    begin
      t := TJSONObject(own).Find('type');
      if (t <> nil) and (t.JSONType = jtString) then typ := t.AsString;
    end;
    Result[i] := TyUtSeriesKeysOf(own, FOption.Root, typ, FOption.ComponentId('series', i));
  end;
end;

function TTyAdvanceChart.AnimUtNamed(ASeries: Integer): Boolean;
var
  i, k: Integer;
  id: string;
begin
  Result := False;
  if not FAnimUtHas then Exit;
  id := FOption.ComponentId('series', ASeries);
  for i := 0 to High(FAnimUtTrans) do
    for k := 0 to High(FAnimUtTrans[i].To_) do
      if TyUtFinderMatches(FAnimUtTrans[i].To_[k], ASeries, id) then Exit(True);
end;

function TTyAdvanceChart.AxisViewKeys: TTyStringArray;
var
  t, i, n: Integer;
  mt: string;
begin
  Result := nil;
  for t := 0 to 1 do
  begin
    if t = 0 then mt := 'xAxis' else mt := 'yAxis';
    n := FOption.ComponentCount(mt);
    for i := 0 to n - 1 do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := mt + IntToStr(i) + '=' + FOption.ComponentId(mt, i) + #1
        + FOption.ComponentSubType(mt, i);
    end;
  end;
end;

function TTyAdvanceChart.AnimAliveKeys: TTyStringArray;
var
  slot, si: Integer;
  vk: TTyStringArray;
  k: string;
begin
  Result := nil;
  vk := AnimViewKeys;
  for slot := 0 to High(FBindings) do
  begin
    si := FBindings[slot].SeriesIndex;
    if si < 0 then Continue;
    if si <= High(vk) then k := vk[si] else k := 'x:' + IntToStr(si);
    if (si <= High(FAnimFresh)) and FAnimFresh[si] then k := 'n:' + k;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := k + #1 + FBindings[slot].SeriesType;
  end;
end;

{ [F3d] THE EDGE DATA'S KEYS, per edge row (the links that resolved, in
  order, past the legend's filter): createGraphFromNodeEdge names an edge by
  the link's id, else `source + ' > ' + target` as written; getId takes the
  name, '__ec__' and its count from the second time on (as AnimRowKeys) }
function TTyAdvanceChart.AnimGraphEdgeKeys(ASlot: Integer): TTyStringArray;
var
  ser, links, item, d: TJSONData;
  k, c, j: Integer;
  nm: string;
  names: TTyStringArray;
begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FBindings)) or (ASlot > High(FGraphEdges)) then Exit;
  if FBindings[ASlot].SeriesType <> 'graph' then Exit;
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (ser is TJSONObject) then Exit;
  links := TJSONObject(ser).Find('edges');
  if (links = nil) or not JsTruthy(links) then links := TJSONObject(ser).Find('links');
  if not (links is TJSONArray) then Exit;
  SetLength(Result, Length(FGraphEdges[ASlot]));
  SetLength(names, Length(FGraphEdges[ASlot]));
  for k := 0 to High(FGraphEdges[ASlot]) do
  begin
    nm := '';
    j := FGraphEdges[ASlot][k].Row;
    if (j >= 0) and (j < links.Count) and (links.Items[j] is TJSONObject) then
    begin
      item := links.Items[j];
      d := TJSONObject(item).Find('id');
      if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then nm := TyGraphJsText(d)
      else
        nm := TyGraphJsText(TJSONObject(item).Find('source')) + ' > '
          + TyGraphJsText(TJSONObject(item).Find('target'));
    end;
    names[k] := nm;
    c := 0;
    for j := 0 to k do
      if names[j] = nm then Inc(c);
    if c > 1 then Result[k] := nm + '__ec__' + IntToStr(c)
    else Result[k] := nm;
  end;
end;

procedure TTyAdvanceChart.AnimRowKeys(AStore: TTyDataStore; out AKeys: TTyStringArray;
  out ARaws: TTyIntegerArray);
var
  rawKeys: TTyStringArray;
  counts: TStringList;
  d, ord_, raw, k, c: Integer;
  id, nm: string;
  v: Double;
begin
  AKeys := nil;
  ARaws := nil;
  if AStore = nil then Exit;
  { the first category dimension names a row that has no name of its own
    (createSeriesData gives it the item-name role) }
  ord_ := -1;
  for d := 0 to AStore.DimCount - 1 do
    if AStore.DimType(d) = ddtOrdinal then
    begin
      ord_ := d;
      Break;
    end;
  { getId over the raw rows, in order: an id; else the name, '__ec__' and
    its count from the second time on; else 'e\0\0' + the raw index }
  SetLength(rawKeys, AStore.RawCount);
  counts := TStringList.Create;
  try
    { THE NAMES AS JAVASCRIPT KEYS: compared byte for byte, and looked up by
      halves. [Milestone D5-D8: an unsorted list compared through the
      locale -- UTF-16 conversions per comparison, every name against every
      earlier one -- made the gallery's grid-multiple (two series of 3,079
      categories) spend a minute and a half here on each update.] }
    counts.CaseSensitive := True;
    counts.UseLocale := False;
    counts.Sorted := True;
    for raw := 0 to AStore.RawCount - 1 do
    begin
      id := AStore.GetIdByRaw(raw);
      if id <> '' then
      begin
        rawKeys[raw] := id;
        Continue;
      end;
      nm := AStore.GetNameByRaw(raw);
      if (nm = '') and (ord_ >= 0) then
      begin
        v := AStore.GetByRaw(ord_, raw);
        if (not IsNan(v)) and (Frac(v) = 0) and (v >= 0)
          and (v < AStore.CategoryCount(ord_)) then
          nm := AStore.CategoryAt(ord_, Trunc(v));
      end;
      if nm = '' then
      begin
        rawKeys[raw] := 'e'#0#0 + IntToStr(raw);
        Continue;
      end;
      k := counts.IndexOf(nm);
      if k < 0 then
      begin
        counts.AddObject(nm, TObject(PtrInt(1)));
        c := 1;
      end
      else
      begin
        c := PtrInt(counts.Objects[k]) + 1;
        counts.Objects[k] := TObject(PtrInt(c));
      end;
      if c > 1 then rawKeys[raw] := nm + '__ec__' + IntToStr(c)
      else rawKeys[raw] := nm;
    end;
  finally
    counts.Free;
  end;
  SetLength(AKeys, AStore.Count);
  SetLength(ARaws, AStore.Count);
  for k := 0 to AStore.Count - 1 do
  begin
    raw := AStore.GetRawIndex(k);
    ARaws[k] := raw;
    if (raw >= 0) and (raw <= High(rawKeys)) then AKeys[k] := rawKeys[raw]
    else AKeys[k] := 'e'#0#0 + IntToStr(raw);
  end;
end;

procedure TTyAdvanceChart.AnimFullBegin(const APayload: TTyAnimOverride;
  AHasPayload: Boolean);
begin
  { off, or the designer: the layout snaps (Relayout drops every proxy) }
  if (FAnimMode = camOff) or (csDesigning in ComponentState) then Exit;
  { AN UPDATE ALREADY WAITS for its arming: that render is still the one it
    starts from -- a new option's stays notMerge, a full update takes the
    latest payload }
  if FAnimPending then
  begin
    if FAnimFull then
    begin
      FAnimPayload := APayload;
      FAnimHasPayload := AHasPayload;
    end;
    { A LAZY UPDATE STILL WAITING is the action's render: doDispatchAction
      runs `update` with the action's payload and drops the pending one
      ("Still dirty"), so a hand-dispatched init sort lays a lazily added
      bar out at once. Its option's models stay the merge's (or the
      notMerge's). [Milestone D1-D4: the payload and the changeAxisOrder
      flag were dropped and the merge armed at the next paint.] }
    if FLazyPending then
    begin
      FAnimPayload := APayload;
      FAnimHasPayload := AHasPayload;
      FAnimRtChange := FRtChange;
      FAnimLazyTaken := True;
    end;
    Exit;
  end;
  { the same option: its series views are the ones there are now, its axis
    views too [Batch 99] }
  FAnimOldViewKeys := AnimViewKeys;
  FAnimOldUtKeys := AnimUtKeys;
  FAnimOldAxisKeys := AxisViewKeys;
  FAnimFreshAxes := nil;
  FAnimPayload := APayload;
  FAnimHasPayload := AHasPayload;
  FAnimFull := True;
  FAnimPending := True;
  { a changeAxisOrder's render [Batch 135] }
  FAnimRtChange := FRtChange;
end;

procedure TTyAdvanceChart.AnimFullEnd;
var lazyTaken: Boolean;
begin
  lazyTaken := FAnimLazyTaken;
  FAnimLazyTaken := False;
  if not (FAnimPending and (FAnimFull or lazyTaken)) then Exit;
  { a chart that animates only in its window's paint is armed there }
  if not AnimAllowed then Exit;
  AnimAfterBuild;
  StAnimSync;
  { NO FLUSH: dispatchAction renders and returns, and the clips the render
    made take their first step on the next frame }
  FAnimFlush := False;
  FAnimLive := (FAnim <> nil) and (FAnim.ClipCount > 0);
  FAnimContinuous := FAnimLive and AnimLoopOnly;
  AnimArmTimer;
end;

procedure TTyAdvanceChart.AnimSnapshot;
var
  slot, si, i, n, k: Integer;
  r: TTyChartAnimSeries;
  el: TTyChartElement;
  drawnNow: Boolean;
begin
  AnimDropPrev;
  { NOTHING DRAWN BEFORE: the option enters }
  if FPaintList = nil then Exit;
  FAnimPrev.Valid := True;
  FAnimPrev.FullUpdate := FAnimFull;
  FAnimPrev.Merge := FAnimMerge;
  for slot := 0 to High(FBindings) do
  begin
    si := FBindings[slot].SeriesIndex;
    if si < 0 then Continue;
    { A SERIES THE LEGEND SWITCHED OFF drew nothing: switched back on it
      enters, its view having kept no data (BarView._clear nulls _data)
      [Batch 96] }
    if FBindings[slot].Hidden then Continue;
    if si > High(FAnimPrev.Series) then SetLength(FAnimPrev.Series, si + 1);
    r := Default(TTyChartAnimSeries);
    r.Present := True;
    r.SeriesType := FBindings[slot].SeriesType;
    { the same option, or a merge -- the same model object, its option
      merged: its model, for the view's remove() [Batch 99] }
    if FAnimFull or FAnimMerge then
    begin
      n := 0;
      if (slot <= High(FStores)) and (FStores[slot] <> nil) then n := FStores[slot].Count;
      r.Model := TyAnimSeriesModel(FOption.Root, si, n);
      r.Model.Payload := FAnimPayload;
      r.Model.HasPayload := FAnimHasPayload;
      r.Enabled := TyAnimIsEnabled(r.Model);
    end;
    if si <= High(FAnimOldViewKeys) then r.ViewKey := FAnimOldViewKeys[si]
    else r.ViewKey := 'x:' + IntToStr(si);
    { the line's last render, init or update [F3b] }
    r.LineInit := LineHistInit(r.ViewKey);
    if (slot <= High(FStores)) and (FStores[slot] <> nil) then
      AnimRowKeys(FStores[slot], r.Keys, r.Raws);
    { [F3d] a graph's edges }
    if slot <= High(FGraphEdgeKeys) then r.EdgeKeys := FGraphEdgeKeys[slot];
    { its universal transition, read off the old option [Batch 136]: the
      key, a list's items, its divideShape, its rows' groups [Batch 137]
      and child groups [Batch 138] }
    if (si <= High(FAnimOldUtKeys)) and (FAnimOldUtKeys[si].Key <> '') then
    begin
      r.UtKeyList := FAnimOldUtKeys[si].List;
      r.UtKey := FAnimOldUtKeys[si].Key;
      r.UtKeyItems := FAnimOldUtKeys[si].Items;
      r.UtDivide := FAnimOldUtKeys[si].Divide;
      r.UtGroupIds := TyUtRowGroups(FAnimOldUtKeys[si], r.Raws);
      r.UtChildGroupIds := TyUtRowChildGroups(FAnimOldUtKeys[si], r.Raws);
      { [F3c] the model id and the groups a transition option reads }
      r.UtModelId := FAnimOldUtKeys[si].ModelId;
      r.UtGroupOwn := TyUtRowGroupsOwn(FAnimOldUtKeys[si], r.Raws);
      r.UtDataGroup := FAnimOldUtKeys[si].DataGroup;
    end;
    FAnimPrev.Series[si] := r;
  end;
  n := 0;
  SetLength(FAnimPrev.Elements, FPaintList.Count);
  for i := 0 to FPaintList.Count - 1 do
  begin
    el := FPaintList.Element(i);
    { [F3c] an item path a universal transition reads, whatever its role }
    if (el.Anim.Role = carNone) and (el.Anim.UtTag = 0) then Continue;
    FAnimPrev.Elements[n] := el;
    Inc(n);
  end;
  SetLength(FAnimPrev.Elements, n);
  { the pieces the data still names that the last render did not draw
    [milestone D5-D8] }
  FAnimPrev.UtStale := nil;
  if not FAnimFull then
    for i := 0 to High(FUtStale) do
    begin
      drawnNow := False;
      for k := 0 to n - 1 do
        if (FAnimPrev.Elements[k].Anim.Role = carSunPiece)
          and (FAnimPrev.Elements[k].Anim.Series = FUtStale[i].Anim.Series)
          and (FAnimPrev.Elements[k].Anim.Index = FUtStale[i].Anim.Index) then
        begin
          drawnNow := True;
          Break;
        end;
      if drawnNow then Continue;
      SetLength(FAnimPrev.UtStale, Length(FAnimPrev.UtStale) + 1);
      FAnimPrev.UtStale[High(FAnimPrev.UtStale)] := FUtStale[i];
    end;
  FAnimPrev.ToOldPoint := @AnimToOldPoint;
  { [R2-C] the map views as drawn }
  FAnimPrev.GeoOld := AnimGeoViews(False);
  { THE OLD BUILD STAYS ALIVE for its coordinate systems; Rebuild's
    DropBuild finds nothing to free }
  FAnimOldBuild := FBuild;
  FBuild := nil;
  FAnimOldBindings := Copy(FBindings, 0, Length(FBindings));
end;

function TTyAdvanceChart.AnimGeoViews(ANew: Boolean): TTyChartGeoViewArray;
var
  k, n, slot: Integer;
  geo: TTyGeo;
  rt: TTyGeoTrans;
  r: TTyChartGeoView;
begin
  Result := nil;
  for k := 0 to High(FGeoDraws) do
  begin
    geo := TTyGeo(FGeoDraws[k].Geo);
    { MapDraw's isFirstDraw: a view that drew nothing has no group to tween }
    if (geo = nil) or (FGeoDraws[k].Count <= 0) then Continue;
    rt := geo.RoamTrans;
    if (rt.Rotation <> 0) or (rt.SkewX <> 0) or (rt.SkewY <> 0) then Continue;
    r := Default(TTyChartGeoView);
    r.Key := TyGeoViewKey(geo);
    r.X := rt.X;
    r.Y := rt.Y;
    r.SX := rt.ScaleX;
    r.SY := rt.ScaleY;
    if ANew then
    begin
      if geo.Kind = gkComponent then
      begin
        { a merge keeps the geo model and its view; a notMerge makes both
          anew (their first draw) }
        if not FAnimPrev.Merge then Continue;
        r.Model := TyAnimComponentModel(FOption.ComponentAt('geo', geo.Index),
          FOption.Root, 'geo');
      end
      else
      begin
        slot := SlotOfSeries(FGeoDraws[k].Series);
        n := 0;
        if (slot >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil) then
          n := FStores[slot].Count;
        r.Model := TyAnimSeriesModel(FOption.Root, FGeoDraws[k].Series, n);
      end;
      r.Model.Payload := FAnimPayload;
      r.Model.HasPayload := FAnimHasPayload;
    end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := r;
  end;
end;

function TTyAdvanceChart.AnimToOldPoint(AOldSeries: Integer; AX, AY: Double): TTyPointF;
var i: Integer;
begin
  Result := TyPointF(NaN, NaN);
  for i := 0 to High(FAnimOldBindings) do
    if (FAnimOldBindings[i].SeriesIndex = AOldSeries)
      and (FAnimOldBindings[i].Cart <> nil) then
      Exit(FAnimOldBindings[i].Cart.DataToPoint([AX, AY]));
end;

function TTyAdvanceChart.AnimSeriesInfo: TTyChartAnimSeriesArray;
var
  slot, si, n, k: Integer;
  r: TTyChartAnimSeries;
  t: string;
  ser, lbl, va, mk: TJSONData;
  v: TTyAnimOptValue;
  viewKeys: TTyStringArray;
  utk: TTyUtSeriesKeys;
begin
  Result := nil;
  viewKeys := AnimViewKeys;
  for slot := 0 to High(FBindings) do
  begin
    si := FBindings[slot].SeriesIndex;
    if si < 0 then Continue;
    { switched off by the legend: no view content [Batch 96] }
    if FBindings[slot].Hidden then Continue;
    if si > High(Result) then SetLength(Result, si + 1);
    r := Default(TTyChartAnimSeries);
    r.Present := True;
    n := 0;
    if (slot <= High(FStores)) and (FStores[slot] <> nil) then
      n := FStores[slot].Count;
    r.Model := TyAnimSeriesModel(FOption.Root, si, n);
    { the update payload's animation, every timing of this render [Batch 96] }
    r.Model.Payload := FAnimPayload;
    r.Model.HasPayload := FAnimHasPayload;
    r.Enabled := TyAnimIsEnabled(r.Model);
    r.On_ := TyAnimOptTruthy(TyAnimGetShallow(r.Model, 'animation'));
    t := FBindings[slot].SeriesType;
    { THE TYPES WHOSE LABELS FADE IN HERE: the ones this batch animates,
      and the heatmap, whose cells never move but whose labels upstream's
      LabelManager fades all the same }
    { [F3d] a force graph's iteration stops its groups' and lines' tweens }
    if (t = 'graph') and (slot <= High(FGraphSpecs)) and FGraphLaidOut[slot] then
      r.GraphForce := FGraphSpecs[slot].Layout = glForce;
    r.LabelFade := (t = 'bar') or (t = 'scatter') or (t = 'heatmap')
      or (t = TyPieSeriesTypeName) or (t = TyFunnelSeriesTypeName)
      or (t = 'effectScatter') or (t = TyThemeRiverSeriesTypeName)
      { a chord's node labels [Batch 120] }
      or (t = TyChordSeriesTypeName)
      { [F3a] a sunburst's, a treemap's (its first render: its own wrap
        fades a drill's), a pictorial bar's, a graph's nodes' and a tree's }
      or (t = TySunburstSeriesTypeName) or (t = TyTreemapSeriesTypeName)
      or (t = TyPictorialSeriesTypeName) or (t = TyGraphSeriesTypeName)
      or (t = TyTreeSeriesTypeName)
      { [R2-A] a radar's point labels }
      or (t = TyRadarSeriesTypeName);
    { A SUNBURST'S DRILL-DOWN: its pieces transition, its new labels fade
      [Batch 115] }
    r.HierDrill := (si <= High(FHierDrill)) and FHierDrill[si];
    if r.HierDrill then r.LabelFade := True;
    { [R2-C] the data rebuilt since the render this one updates }
    r.DataFresh := FAnimDataFresh;
    ser := r.Model.Own;
    if ser is TJSONObject then
    begin
      lbl := TJSONObject(ser).Find('label');
      if lbl is TJSONObject then
      begin
        va := TJSONObject(lbl).Find('valueAnimation');
        { only a bar counts (BarView's setLabelValueAnimation): every other
          series' labels fade whatever the key says [Batch 92] }
        r.LabelValueAnim := (t = 'bar') and (va <> nil)
          and (va.JSONType = jtBoolean) and va.AsBoolean;
      end;
      { THE MARKERS' MODELS: MarkerModel.isAnimationEnabled is the marker's
        `animation` and the host's isAnimationEnabled [Batch 92] }
      r.MarkLine := TyAnimNoModel;
      r.MarkPoint := TyAnimNoModel;
      if r.Enabled then
      begin
        mk := TJSONObject(ser).Find('markLine');
        if mk is TJSONObject then
        begin
          r.MarkLine := TyAnimComponentModel(mk, FOption.Root, 'markLine');
          r.MarkLine.Payload := FAnimPayload;
          r.MarkLine.HasPayload := FAnimHasPayload;
        end;
        mk := TJSONObject(ser).Find('markPoint');
        if mk is TJSONObject then
        begin
          r.MarkPoint := TyAnimComponentModel(mk, FOption.Root, 'markPoint');
          r.MarkPoint.Payload := FAnimPayload;
          r.MarkPoint.HasPayload := FAnimHasPayload;
        end;
      end;
    end;
    r.BaseHoriz := (FBindings[slot].BaseAxis = nil)
      or FBindings[slot].BaseAxis.Horizontal;
    { A BAR RACE: the base axis' model for the place along it, and the
      render's changeAxisOrder for every bar [Batch 135] }
    r.RtSort := RtSortOf(slot);
    if r.RtSort then
    begin
      r.RtAxis := TyAnimComponentModel(FOption.ComponentAt(
        FBindings[slot].BaseAxis.MainType, FBindings[slot].BaseAxis.ComponentIndex),
        FOption.Root, 'axis');
      r.RtAxis.Payload := FAnimPayload;
      r.RtAxis.HasPayload := FAnimHasPayload;
    end;
    r.ChangeOrder := FAnimRtChange;
    { AN UPDATE'S VIEW [Batch 90] }
    r.SeriesType := t;
    { the universal transition [Batch 136] }
    TyUtSeriesInfo(r, FOption.Root, FOption.ComponentId('series', si));
    if si <= High(viewKeys) then r.ViewKey := viewKeys[si]
    else r.ViewKey := 'x:' + IntToStr(si);
    { brand new: a key no old view has [Batch 97] }
    if (si <= High(FAnimFresh)) and FAnimFresh[si] then r.ViewKey := 'n:' + r.ViewKey;
    if (slot <= High(FStores)) and (FStores[slot] <> nil) then
      AnimRowKeys(FStores[slot], r.Keys, r.Raws);
    { [F3d] a graph's edges }
    if slot <= High(FGraphEdgeKeys) then r.EdgeKeys := FGraphEdgeKeys[slot];
    { the groups of its rows [Batch 137] and their child groups [Batch 138] }
    utk := TyUtSeriesKeysOf(r.Model.Own, FOption.Root, t, FOption.ComponentId('series', si));
    r.UtGroupIds := TyUtRowGroups(utk, r.Raws);
    r.UtChildGroupIds := TyUtRowChildGroups(utk, r.Raws);
    { [F3c] the model id, the groups a transition option reads, and
      whether that option's `to` names the series }
    r.UtModelId := utk.ModelId;
    r.UtGroupOwn := TyUtRowGroupsOwn(utk, r.Raws);
    r.UtDataGroup := utk.DataGroup;
    r.UtNamed := AnimUtNamed(si);
    if t = TyPieSeriesTypeName then
    begin
      v := TyAnimGetShallow(r.Model, 'animationTypeUpdate');
      r.PieExpandAlways := (v.Kind = aokString) and (v.Str = 'expansion');
      v := TyAnimGetShallow(r.Model, 'animationType');
      r.PieScale := (v.Kind = aokString) and (v.Str = 'scale');
      { A FIRST RENDER'S SHARED START: the first slice's whose start is a
        number (PieView.ts:248-256) }
      if (slot <= High(FPies)) and FPies[slot].Valid then
        for k := 0 to High(FPies[slot].Sectors) do
          if not IsNan(FPies[slot].Sectors[k].StartRad) then
          begin
            r.HasPieStart := True;
            r.PieStart := FPies[slot].Sectors[k].StartRad;
            Break;
          end;
    end;
    Result[si] := r;
  end;
end;

procedure TTyAdvanceChart.AnimAfterBuild;
begin
  if FAnimPending then
  begin
    if AnimAllowed then
    begin
      FAnimPending := False;
      if FAnim = nil then FAnim := NewAnimDriver;
      if FAnimSet = nil then FAnimSet := TTyChartAnimSet.Create(FAnim);
      FAnimSet.OnUtStop := @AnimUtStopCustom;
      { AN UPDATE when there was a render before, an entry otherwise
        [Batch 90] }
      if FAnimPrev.Valid then
      begin
        { the views alive after it: an old one that is not among them was
          disposed [Batch 99] }
        FAnimPrev.AliveKeys := AnimAliveKeys;
        { [F3c] the setOption's transition option }
        FAnimPrev.UtHasTransition := FAnimUtHas;
        FAnimPrev.UtTransition := FAnimUtTrans;
        { [R2-C] an action's render (a payload) sets the map groups at once;
          a setOption's tweens them }
        if FAnimPrev.FullUpdate then FAnimPrev.GeoNew := nil
        else FAnimPrev.GeoNew := AnimGeoViews(True);
        FCustomUtStopped := False;
        FAnimSet.ArmUpdate(FPaintList, AnimSeriesInfo, FAnimPrev);
        { [R2-D] a custom item the transition stopped is drawn where it rests:
          the list is built again }
        if FCustomUtStopped then
        begin
          FCustomUtStopped := False;
          DropStatic;
        end;
      end
      else
      begin
        FAnimSet.Clear;
        FAnimSet.Arm(FPaintList, AnimSeriesInfo);
      end;
      { series:transition resets the flag of the series it named }
      FAnimUtHas := False;
      FAnimUtTrans := nil;
      { THE AXES: a full update of the same option renders the same axis
        views again and groupTransitions them; a new option's are new views,
        which never do (probed: under notMerge only the series move)
        [Batch 96] }
      { A MERGE keeps its axis models and their views: the same groupTransition,
        an axis whose model is new (replaced, its type changed) excepted
        [Batch 99] }
      { THE INIT SORT'S RENDER is laid out as it lands, no groupTransition
        (CartesianAxisView: isInitialSortFromBarRacing) [Batch 135] }
      if FAnimPrev.Valid and (FAnimPrev.FullUpdate or FAnimPrev.Merge)
        and (FAnimOldBuild <> nil) and (FAnimRtChange <> 2) then
        AxisAnimArm(FAnimOldBuild, FBuild)
      else
        AxisAnimDrop;
      FAnimRtChange := 0;
      FAnimFull := False;
      FAnimMerge := False;
      FAnimDataFresh := False;
      FAnimHasPayload := False;
      AnimDropPrev;
      { the views are paired: __requireNewView works once }
      FAnimFresh := nil;
      FAnimFreshAxes := nil;
      { THE FLUSH: upstream's setOption ends with a synchronous update, so
        every clip it made starts NOW and this same paint shows the from
        values. A step on the next tick would shift every timeline by up
        to 16 ms. It waits for the states (AnimFlushArmed). }
      FAnimFlush := True;
    end
    else if FAnimMode = camOff then
    begin
      FAnimPending := False;
      FAnimFull := False;
      FAnimMerge := False;
      FAnimDataFresh := False;
      FAnimHasPayload := False;
      AnimDropPrev;
      FAnimFresh := nil;
      FAnimFreshAxes := nil;
    end;
  end;
  FAnimStBind := nil;
  { A LIST WAITING FOR ITS ARMING is drawn as laid out: the proxies are the
    old render's, keyed by the old rows [Batch 90] }
  if FAnimPending then
    FAnimBind := nil
  else if (FAnimSet <> nil) and (FAnimSet.Count > 0) then
    FAnimBind := FAnimSet.Bind(FPaintList)
  else
    FAnimBind := nil;
end;

procedure TTyAdvanceChart.AnimFlushArmed;
begin
  if not FAnimFlush then Exit;
  FAnimFlush := False;
  if FAnim = nil then Exit;
  FAnim.Update(AnimClock, True);
  AnimFlushOthers(FAnim);
  FAnimLive := FAnim.ClipCount > 0;
  FAnimContinuous := FAnimLive and AnimLoopOnly;
  AnimArmTimer;
end;

procedure TTyAdvanceChart.AnimArmTimer;
begin
  if (((FAnimLive or PtrLive or LegLive or LoadLive or VmLive_ or ProgLive or GfxLive
    or CuLive or TlLive) and not AnimPaused)
    { [F3b] a force iteration is a timer of its own, which no pause holds }
    or GraphForceLive)
    and IsNan(FAnimNow)
    and not (csDesigning in ComponentState) then
  begin
    if FAnimTimer = nil then
    begin
      FAnimTimer := TTimer.Create(nil);
      FAnimTimer.Enabled := False;
      FAnimTimer.Interval := 16;
      FAnimTimer.OnTimer := @AnimTimerFired;
    end;
    FAnimTimer.Enabled := True;
  end
  else if FAnimTimer <> nil then
    FAnimTimer.Enabled := False;
end;

procedure TTyAdvanceChart.AnimTimerFired(Sender: TObject);
begin
  { [F3b] the force iterations' 16 ms step }
  if GraphForceLive then
  begin
    GraphForceFrame;
    if not GraphForceLive then AnimArmTimer;
  end;
  AnimTick(AnimClock);
end;

{ ==================== the pause [F3b] ====================

  Animation.pause / resume (zrender/src/animation/Animation.ts): the clock a
  driver steps its clips at is the wall clock less every paused stretch;
  the frame loop skips update() while paused, and only a flush steps. The
  chart has one driver upstream; here each part has its own, so they pause
  together and a flush while paused steps them all. }

function TTyAdvanceChart.NewAnimDriver: TTyAnimation;
begin
  Result := TTyAnimation.Create;
  Result.AdoptPause(FPauseClock);
end;

function TTyAdvanceChart.AnimDrivers: TFPList;

  procedure Put(A: TTyAnimation);
  begin
    if A <> nil then Result.Add(A);
  end;

begin
  Result := TFPList.Create;
  Put(FAnim);
  Put(FPtrAnim);
  Put(FLegAnim);
  Put(FLoadAnim);
  Put(FGfxAnim);
  Put(FCuAnim);
  Put(FTlAnim);
  Put(FVmAnim);
end;

procedure TTyAdvanceChart.AnimFlushOthers(AOwn: TTyAnimation);
var
  list: TFPList;
  i: Integer;
  now_: Double;
begin
  if not AnimPaused then Exit;
  now_ := AnimClock;
  list := AnimDrivers;
  try
    for i := 0 to list.Count - 1 do
      if TTyAnimation(list[i]) <> AOwn then TTyAnimation(list[i]).Update(now_, True);
  finally
    list.Free;
  end;
  InvalidateFrame;
end;

procedure TTyAdvanceChart.AnimPause;
var
  list: TFPList;
  i: Integer;
  now_: Double;
begin
  if AnimPaused then Exit;
  now_ := AnimClock;
  FPauseClock.Pause(now_);
  list := AnimDrivers;
  try
    for i := 0 to list.Count - 1 do TTyAnimation(list[i]).Pause(now_);
  finally
    list.Free;
  end;
  AnimArmTimer;
end;

procedure TTyAdvanceChart.AnimResume;
var
  list: TFPList;
  i: Integer;
  now_: Double;
begin
  if not AnimPaused then Exit;
  now_ := AnimClock;
  FPauseClock.Resume(now_);
  list := AnimDrivers;
  try
    for i := 0 to list.Count - 1 do TTyAnimation(list[i]).Resume(now_);
  finally
    list.Free;
  end;
  AnimArmTimer;
end;

function TTyAdvanceChart.AnimPaused: Boolean;
begin
  Result := (FPauseClock <> nil) and FPauseClock.Paused;
end;

{ ==================== a line view's history [F3b] ====================

  LineView.render takes its INIT branch when it has no polyline yet (its
  first render, or the first after remove() -- a legend switched it off),
  or the coordinate system's type or the step changed; there a step line
  turns its local points into steps before it saves them as _points and
  _stackedOnPoints. The next update reads those. }

procedure TTyAdvanceChart.LineHistRoll;
var
  hist: TStringList;
  i, k: Integer;
  el: TTyChartElement;
  key, sig, old: string;
  init: Boolean;
begin
  if FPaintList = nil then Exit;
  hist := TStringList.Create;
  hist.NameValueSeparator := #1;
  try
    for i := 0 to FPaintList.Count - 1 do
    begin
      el := FPaintList.Element(i);
      if not (el.Anim.Role in [carLineRun, carLineArea]) then Continue;
      key := SeriesViewKey(el.Anim.Series);
      if hist.IndexOfName(key) >= 0 then Continue;
      sig := IntToStr(Round(el.Anim.G[7])) + '/' + IntToStr(Round(el.Anim.G[5]) and 8);
      k := FLineHist.IndexOfName(key);
      if k >= 0 then old := FLineHist.ValueFromIndex[k] else old := '';
      init := Copy(old, 1, Length(sig) + 1) <> sig + '|';
      if init then hist.Add(key + #1 + sig + '|1') else hist.Add(key + #1 + sig + '|0');
    end;
    FLineHist.Clear;
    FLineHist.AddStrings(hist);
  finally
    hist.Free;
  end;
end;

function TTyAdvanceChart.LineHistInit(const AViewKey: string): Boolean;
var k: Integer; v: string;
begin
  Result := False;
  if FLineHist = nil then Exit;
  k := FLineHist.IndexOfName(AViewKey);
  if k < 0 then Exit;
  v := FLineHist.ValueFromIndex[k];
  Result := Copy(v, Length(v), 1) = '1';
end;

{ ==================== the bar race (realtimeSort) [Batch 135] ==================== }

function TTyAdvanceChart.RtSortOf(ASlot: Integer): Boolean;
var s: TJSONObject;
begin
  Result := False;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  { shouldRealtimeSort: realtimeSort (the series' own, ignoreParent), a
    category base axis, a cartesian2d }
  if (FBindings[ASlot].SeriesType <> 'bar') or not FBindings[ASlot].Resolved
    or not FBindings[ASlot].HasAxes or (FBindings[ASlot].Cart = nil)
    or (FBindings[ASlot].BaseAxis = nil) or (FBindings[ASlot].ValueAxis = nil) then Exit;
  if not (FBindings[ASlot].BaseAxis.Scale is TTyOrdinalScale) then Exit;
  { _renderLarge has no race }
  if LargeKindOf(ASlot) <> lgkNone then Exit;
  s := StSeriesNode(FBindings[ASlot].SeriesIndex);
  Result := (s <> nil) and JsTruthy(s.Find('realtimeSort'));
end;

function TTyAdvanceChart.RtKeyOf(ASlot: Integer; const AViewKeys: TTyStringArray): string;
var si: Integer;
begin
  si := FBindings[ASlot].SeriesIndex;
  if (si >= 0) and (si <= High(AViewKeys)) then Result := AViewKeys[si]
  else Result := 'x:' + IntToStr(si);
  Result := Result + #1 + FBindings[ASlot].SeriesType;
end;

function TTyAdvanceChart.AxisByTick(AAxis: TTyAxis): TTyIntegerArray;
begin
  Result := nil;
  if (AAxis <> nil) and (AAxis.Scale is TTyOrdinalScale)
    and TTyOrdinalScale(AAxis.Scale).Sorted then
    Result := TTyOrdinalScale(AAxis.Scale).ByTick;
end;

procedure TTyAdvanceChart.RtApplySortInfos;
var
  g, a: Integer;
  gb: TTyGridBuild;

  procedure Apply(AAxis: TTyAxis);
  var
    node, si, arr: TJSONData;
    ords: TTyIntegerArray;
    k: Integer;
  begin
    if (AAxis = nil) or not (AAxis.Scale is TTyOrdinalScale) then Exit;
    node := FOption.ComponentAt(AAxis.MainType, AAxis.ComponentIndex);
    si := nil;
    if node is TJSONObject then si := TJSONObject(node).Find('categorySortInfo');
    { setSortInfo(axis.model.get('categorySortInfo')): none drops it }
    if not (si is TJSONObject) then
    begin
      TTyOrdinalScale(AAxis.Scale).SetSortInfo(nil, False);
      Exit;
    end;
    ords := nil;
    arr := TJSONObject(si).Find('ordinalNumbers');
    if arr is TJSONArray then
    begin
      SetLength(ords, arr.Count);
      for k := 0 to arr.Count - 1 do
        if (TJSONArray(arr).Items[k].JSONType = jtNumber)
          and not IsNan(TJSONArray(arr).Items[k].AsFloat) then
          ords[k] := Trunc(TJSONArray(arr).Items[k].AsFloat)
        else
          ords[k] := -1;
    end;
    TTyOrdinalScale(AAxis.Scale).SetSortInfo(ords, True);
  end;

begin
  if (FBuild = nil) or (FOption = nil) then Exit;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    for a := 0 to gb.XAxisCount - 1 do Apply(gb.XAxis(a));
    for a := 0 to gb.YAxisCount - 1 do Apply(gb.YAxis(a));
  end;
end;

function TTyAdvanceChart.CategorySortInfoText(const AMainType: string;
  AIndex: Integer): string;
var node, si, arr: TJSONData;
begin
  Result := 'null';
  if FOption = nil then Exit;
  node := FOption.ComponentAt(AMainType, AIndex);
  if not (node is TJSONObject) then Exit;
  si := TJSONObject(node).Find('categorySortInfo');
  if not (si is TJSONObject) then Exit;
  arr := TJSONObject(si).Find('ordinalNumbers');
  if arr <> nil then Result := arr.AsJSON;
end;

function TTyAdvanceChart.RtCompare(A, B: Integer): Integer;
var d: Double;
begin
  { b.mappedValue - a.mappedValue: not a number is 0 to V8's sort }
  d := FRtLens[B] - FRtLens[A];
  if d < 0 then Result := -1
  else if d > 0 then Result := 1
  else Result := 0;
end;

{ the payload's ordinalNumbers: the rows' ordinals in the order of
  _dataSort -- every row by its mapped value, descending, V8's stable sort }
function RtOrdinalsJson(const AOrds: TTyDoubleArray; const AIdx: TTyIntegerArray): string;
var k: Integer;
begin
  Result := '';
  for k := 0 to High(AIdx) do
  begin
    if k > 0 then Result := Result + ',';
    if IsNan(AOrds[AIdx[k]]) then Result := Result + 'null'
    else Result := Result + TyJsNumberToString(AOrds[AIdx[k]]);
  end;
end;

procedure TTyAdvanceChart.RtRenderPass;
var
  slot, k, n, baseCol, valCol: Integer;
  keys, live: TTyStringArray;
  key: string;
  st: TTyDataStore;
  ords: TTyDoubleArray;
  idx: TTyIntegerArray;
  base: TTyAxis;
  queued: Boolean;
begin
  if (FBuild = nil) or (FOption = nil) then Exit;
  keys := AnimViewKeys;
  live := nil;
  for slot := 0 to High(FBindings) do
  begin
    if FBindings[slot].SeriesType <> 'bar' then Continue;
    key := RtKeyOf(slot, keys);
    { a view the legend took away: _clear, its first frame again }
    if FBindings[slot].Hidden then Continue;
    SetLength(live, Length(live) + 1);
    live[High(live)] := key;
    if not RtSortOf(slot) then Continue;
    st := nil;
    if slot <= High(FStores) then st := FStores[slot];
    { no data yet: it waits for some }
    if (st = nil) or (st.Count = 0) then Continue;
    queued := False;
    for k := 0 to High(FRtInit) do
      if FRtInit[k] = key then queued := True;
    for k := 0 to High(FRtQueueInit) do
      if FRtQueueInit[k] = key then queued := True;
    if queued then Continue;
    { _dispatchInitSort: the rows by the value on the other axis }
    base := FBindings[slot].BaseAxis;
    baseCol := -1;
    valCol := -1;
    if Length(st.DimsOfCoord(base.Dim)) > 0 then baseCol := st.DimsOfCoord(base.Dim)[0];
    if Length(st.DimsOfCoord(FBindings[slot].ValueAxis.Dim)) > 0 then
      valCol := st.DimsOfCoord(FBindings[slot].ValueAxis.Dim)[0];
    if (baseCol < 0) or (valCol < 0) then Continue;
    n := st.Count;
    SetLength(ords, n);
    SetLength(FRtLens, n);
    SetLength(idx, n);
    for k := 0 to n - 1 do
    begin
      ords[k] := st.Get(baseCol, k);
      FRtLens[k] := st.Get(valCol, k);
      idx[k] := k;
    end;
    TyJsArraySort(idx, @RtCompare);
    SetLength(FRtQueue, Length(FRtQueue) + 1);
    FRtQueue[High(FRtQueue)] := '{"type":"changeAxisOrder","componentType":"'
      + base.MainType + '","isInitSort":true,"axisId":' + IntToStr(base.ComponentIndex)
      + ',"sortInfo":{"ordinalNumbers":[' + RtOrdinalsJson(ords, idx) + ']}}';
    SetLength(FRtQueueInit, Length(FRtQueue));
    FRtQueueInit[High(FRtQueueInit)] := key;
  end;
  { the views still shown keep their state; the rest start over }
  n := 0;
  for k := 0 to High(FRtInit) do
  begin
    queued := False;
    for slot := 0 to High(live) do
      if live[slot] = FRtInit[k] then queued := True;
    if not queued then Continue;
    FRtInit[n] := FRtInit[k];
    Inc(n);
  end;
  SetLength(FRtInit, n);
end;

procedure TTyAdvanceChart.RtRendered;
var
  slot, k, n, i, cats, baseCol, rawIdx, row, si: Integer;
  keys: TTyStringArray;
  key, ordJson: string;
  st: TTyDataStore;
  base: TTyAxis;
  sc: TTyOrdinalScale;
  ords, byRow: TTyDoubleArray;
  idx, elAt: TTyIntegerArray;
  el: TTyChartElement;
  p: TTyChartAnimProxy;
  last, v, t, tMax: Double;
  known, ordMoved, differs: Boolean;
  e: TTyRange;
  minValue: Double;
  minBits: Int64;
begin
  { a layout still to come reads its own frame }
  if (FBuild = nil) or (FOption = nil) or (FPaintList = nil) or FDirty then Exit;
  { Number.MIN_VALUE, the least subnormal }
  minBits := 1;
  Move(minBits, minValue, SizeOf(Double));
  keys := nil;
  for slot := 0 to High(FBindings) do
  begin
    if FBindings[slot].Hidden or not RtSortOf(slot) then Continue;
    if keys = nil then keys := AnimViewKeys;
    key := RtKeyOf(slot, keys);
    { a first frame has no listener yet }
    known := False;
    for k := 0 to High(FRtInit) do
      if FRtInit[k] = key then known := True;
    if not known then Continue;
    st := nil;
    if slot <= High(FStores) then st := FStores[slot];
    if (st = nil) or (st.Count = 0) then Continue;
    base := FBindings[slot].BaseAxis;
    sc := TTyOrdinalScale(base.Scale);
    if Length(st.DimsOfCoord(base.Dim)) = 0 then Continue;
    baseCol := st.DimsOfCoord(base.Dim)[0];
    si := FBindings[slot].SeriesIndex;
    n := st.Count;
    { orderMapping: the bar's CURRENT length -- |height| on a horizontal
      base axis, |width| on a vertical one -- its proxy's while it moves;
      no bar, or not a number, is 0 }
    SetLength(elAt, n);
    for i := 0 to n - 1 do elAt[i] := -1;
    for i := 0 to FPaintList.Count - 1 do
    begin
      el := FPaintList.Element(i);
      if (el.Anim.Role = carBar) and (el.Anim.Series = si)
        and (el.Anim.Index >= 0) and (el.Anim.Index < n) then
        elAt[el.Anim.Index] := i;
    end;
    SetLength(byRow, n);
    for i := 0 to n - 1 do
    begin
      byRow[i] := 0;
      if elAt[i] < 0 then Continue;
      el := FPaintList.Element(elAt[i]);
      p := nil;
      if FAnimSet <> nil then p := FAnimSet.Find(si, i, 'bar');
      if base.Horizontal then
      begin
        if p <> nil then v := p.Num('shape.height') else v := el.Anim.G[3];
      end
      else
      begin
        if p <> nil then v := p.Num('shape.width') else v := el.Anim.G[2];
      end;
      if IsNan(v) then v := 0;
      byRow[i] := Abs(v);
    end;
    { _isOrderChangedWithinSameData: tick by tick, a value above the one
      before; a tick with no bar is Number.MIN_VALUE }
    ordMoved := False;
    last := MaxDouble;
    cats := sc.CategoryCount;
    for k := 0 to cats - 1 do
    begin
      v := sc.TickToOrdinal(k);
      rawIdx := -1;
      if not IsNan(v) then rawIdx := st.RawIndexOfOrdinal(baseCol, Trunc(v));
      if rawIdx < 0 then v := minValue
      else
      begin
        row := st.IndexOfRawIndex(rawIdx);
        if row < 0 then v := 0 else v := byRow[row];
      end;
      if v > last then
      begin
        ordMoved := True;
        Break;
      end;
      last := v;
    end;
    if not ordMoved then Continue;
    { _dataSort over the rows }
    SetLength(ords, n);
    SetLength(FRtLens, n);
    SetLength(idx, n);
    for i := 0 to n - 1 do
    begin
      ords[i] := st.Get(baseCol, i);
      FRtLens[i] := byRow[i];
      idx[i] := i;
    end;
    TyJsArraySort(idx, @RtCompare);
    { _isOrderDifferentInView: inside the extent, a tick whose ordinal
      changed }
    differs := False;
    e := sc.GetExtent;
    t := Math.Max(Double(0), e.Start);
    tMax := Math.Min(e.Stop, Double(cats - 1));
    while t <= tMax do
    begin
      if (Frac(t) <> 0) or (t >= n) then
      begin
        differs := True;
        Break;
      end;
      v := sc.TickToOrdinal(t);
      if IsNan(ords[idx[Trunc(t)]]) or IsNan(v) or (ords[idx[Trunc(t)]] <> v) then
      begin
        differs := True;
        Break;
      end;
      t := t + 1;
    end;
    if not differs then Continue;
    ordJson := RtOrdinalsJson(ords, idx);
    SetLength(FRtQueue, Length(FRtQueue) + 1);
    FRtQueue[High(FRtQueue)] := '{"type":"changeAxisOrder","componentType":"'
      + base.MainType + '","axisId":' + IntToStr(base.ComponentIndex)
      + ',"sortInfo":{"ordinalNumbers":[' + ordJson + ']}}';
    SetLength(FRtQueueInit, Length(FRtQueue));
    FRtQueueInit[High(FRtQueueInit)] := '';
  end;
end;

procedure TTyAdvanceChart.RtFlushQueue;
var
  payload, key: string;
begin
  if FRtFlushing then Exit;
  FRtFlushing := True;
  try
    while Length(FRtQueue) > 0 do
    begin
      payload := FRtQueue[0];
      key := FRtQueueInit[0];
      Delete(FRtQueue, 0, 1);
      Delete(FRtQueueInit, 0, 1);
      { the view's first frame is over: its listener is on from this render }
      if key <> '' then
      begin
        SetLength(FRtInit, Length(FRtInit) + 1);
        FRtInit[High(FRtInit)] := key;
      end;
      DispatchAction(payload);
    end;
  finally
    FRtFlushing := False;
  end;
end;

procedure TTyAdvanceChart.DoChangeAxisOrder(APayload: TJSONObject);
var
  main: string;
  d, si: TJSONData;
  ev: TJSONObject;
  idx: TTyIntegerArray;
  i, n, c: Integer;
  ax: TTyAxis;
  node: TJSONData;

  procedure Add(AIndex: Integer);
  var z: Integer;
  begin
    if (AIndex < 0) or (AIndex >= c) then Exit;
    for z := 0 to High(idx) do
      if idx[z] = AIndex then Exit;
    SetLength(idx, Length(idx) + 1);
    idx[High(idx)] := AIndex;
  end;

  function Wanted(AData: TJSONData; const AText: string): Boolean;
  var z: Integer;
  begin
    Result := False;
    if AData is TJSONArray then
    begin
      for z := 0 to AData.Count - 1 do
        if (TJSONArray(AData).Items[z].JSONType in [jtString, jtNumber])
          and (TJSONArray(AData).Items[z].AsString = AText) then Exit(True);
    end
    else if AData.JSONType in [jtString, jtNumber] then
      Result := AData.AsString = AText;
  end;

begin
  { payload.componentType || 'series' }
  main := 'series';
  d := APayload.Find('componentType');
  if JsTruthy(d) and (d.JSONType = jtString) then main := d.AsString;
  si := APayload.Find('sortInfo');
  { eachComponent with the payload as the query: <main>Index, else <main>Id,
    else <main>Name when one is written -- the payload's axisId is none of
    them -- else every component of the type }
  idx := nil;
  c := FOption.ComponentCount(main);
  d := APayload.Find(main + 'Index');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
    begin
      for i := 0 to d.Count - 1 do
        if TJSONArray(d).Items[i].JSONType = jtNumber then
          Add(Trunc(TJSONArray(d).Items[i].AsFloat));
    end
    else if d.JSONType = jtNumber then Add(Trunc(d.AsFloat));
  end
  else
  begin
    d := APayload.Find(main + 'Id');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      for i := 0 to c - 1 do
        if (ComponentModelId(main, i) <> '') and Wanted(d, ComponentModelId(main, i)) then Add(i);
    end
    else
    begin
      d := APayload.Find(main + 'Name');
      if (d <> nil) and (d.JSONType <> jtNull) then
      begin
        for i := 0 to c - 1 do
          if Wanted(d, ComponentModelName(main, i)) then Add(i);
      end
      else
        for i := 0 to c - 1 do Add(i);
    end;
  end;
  { axis.setCategorySortInfo: a category axis only, its model's option
    takes the info as it is }
  if JsTruthy(si) and ((main = 'xAxis') or (main = 'yAxis')) and (FBuild <> nil) then
    for n := 0 to High(idx) do
    begin
      ax := FBuild.Axis(main, idx[n]);
      if (ax = nil) or not (ax.Scale is TTyOrdinalScale) then Continue;
      node := FOption.ComponentAt(main, idx[n]);
      if not (node is TJSONObject) then Continue;
      if TJSONObject(node).Find('categorySortInfo') <> nil then
        TJSONObject(node).Delete('categorySortInfo');
      TJSONObject(node).Add('categorySortInfo', si.Clone);
    end;
  { the update renders for the order: 2 for the init sort }
  if JsTruthy(APayload.Find('isInitSort')) then FRtChange := 2 else FRtChange := 1;
  try
    FullUpdate;
  finally
    FRtChange := 0;
  end;
  { the event: the payload, its type the event's }
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := 'changeaxisorder';
    EmitPayloadEvent('changeaxisorder', ev.AsJSON);
  finally
    ev.Free;
  end;
end;

procedure TTyAdvanceChart.AnimTick(ANowMs: Double);
var ran, was: Boolean;
begin
  { THE LOOP OF A PAUSED ANIMATION steps nothing (`!self._paused &&
    self.update()`): no clip, no chunk, no frame event [F3b] }
  if AnimPaused then Exit;
  { ONE FRAME: zrender's clips step, then the chart's _onframe draws its
    chunks, then the flush -- `rendered` once for the frame, and `finished`
    when nothing is left moving or to draw [Batch 119] }
  ran := ProgFrame(False);
  was := FAnimLive;
  AnimTickBody(ANowMs);
  if ran then AnimArmTimer;
  if ran or was then
  begin
    { [F4b] the frame's flush: what it drew is no longer dirty }
    FZrDirty := False;
    FTipPaintedKey := TipStateKey;
    EmitRendered(0);
    if ProgIdle then EmitPlain('finished');
    { the bar race's `rendered` listeners read the frame [Batch 135] }
    RtRendered;
    RtFlushQueue;
  end;
end;

procedure TTyAdvanceChart.AnimTickBody(ANowMs: Double);
var ptrWas: Boolean;
begin
  { the pointer's own driver first [Batch 92] }
  if FPtrAnim <> nil then
  begin
    ptrWas := FPtrAnim.ClipCount > 0;
    FPtrAnim.Update(ANowMs);
    if ptrWas then
    begin
      InvalidateFrame;
      if (FPtrAnim.ClipCount = 0) and not FAnimLive then AnimArmTimer;
    end;
  end;
  { the legend's scroll [Batch 98]: a frame of the static layer }
  if LegLive then
  begin
    FLegAnim.Update(ANowMs);
    DropStatic;
    InvalidateFrame;
    if not LegLive and not FAnimLive then AnimArmTimer;
  end;
  { the spinner's own driver: a frame of the dynamic layer [Batch 106] }
  if LoadLive then
  begin
    FLoadAnim.Update(ANowMs);
    InvalidateFrame;
  end;
  { the graphic elements' transitions: frames of the static layer
    [Batch 122] }
  if GfxLive then
  begin
    FGfxAnim.Update(ANowMs);
    DropStatic;
    InvalidateFrame;
    if not GfxLive and not FAnimLive then AnimArmTimer;
  end;
  { the custom elements' transitions: frames of the static layer
    [Batch 124] }
  if CuLive then
  begin
    FCuAnim.Update(ANowMs);
    DropStatic;
    InvalidateFrame;
    if not CuLive and not FAnimLive then AnimArmTimer;
  end;
  { the timeline's checkpoint, its progress line and its hover
    transitions: frames of the static layer [Batch 129] }
  if TlLive then
  begin
    FTlAnim.Update(ANowMs);
    DropStatic;
    InvalidateFrame;
    if not TlLive and not FAnimLive then AnimArmTimer;
  end;
  { the visualMap indicator's slide: a frame of the static layer [Batch 116] }
  if VmLive_ then
  begin
    FVmAnim.Update(ANowMs);
    DropStatic;
    InvalidateFrame;
    if not VmLive_ and not FAnimLive then AnimArmTimer;
  end;
  if FAnim = nil then Exit;
  FAnim.Update(ANowMs);
  { a fade that ended removed its element [Batch 90] }
  if FAnimSet <> nil then FAnimSet.Purge;
  { a treemap's wrap that ended: renderFinally [Batch 115] }
  TmWrapCheck;
  if FAnimLive and (FAnim.ClipCount = 0) then
  begin
    { AT REST: the series go back into the static layer, drawn once more
      at the values they rest at }
    FAnimLive := False;
    FAnimContinuous := False;
    AnimArmTimer;
    DropStatic;
  end
  else if FAnimLive and not FAnimContinuous and AnimLoopOnly then
  begin
    { ONLY LOOPS LEFT: the rest settles into the static layer [Batch 92] }
    FAnimContinuous := True;
    DropStatic;
  end;
  InvalidateFrame;
end;

{ ==================== the axis pointer's slide [Batch 92] ====================

  BaseAxisPointer.render: the first show is direct; a move -- the pointer's
  props differing from the last ones (propsEqual) -- is updateProps on the
  pointer's model when determineAnimation says so, else a stop and attr.
  The model is the axis' axisPointer over the tooltip's (makeAxisPointerModel:
  animation 'auto', 200 ms, exponentialOut), the root below. A hidden pointer
  keeps its place: the next show slides from it. The label goes with the
  pointer (upstream tweens its x / y with the same timing). }

function TTyAdvanceChart.PtrLive: Boolean;
begin
  Result := (FPtrAnim <> nil) and (FPtrAnim.ClipCount > 0);
end;

function TTyAdvanceChart.PtrKeyOf(AAxis: TTyAxis): string;
begin
  Result := AAxis.MainType + IntToStr(AAxis.ComponentIndex);
end;

procedure TTyAdvanceChart.PtrAnimDrop;
var i: Integer;
begin
  if FPtrProxies <> nil then
  begin
    for i := 0 to FPtrProxies.Count - 1 do TObject(FPtrProxies[i]).Free;
    FPtrProxies.Clear;
  end;
end;

{ propsEqual: every key of AProps at the value AFinal holds }
function PtrPropsSame(const AFinal, AProps: TTyAnimProps): Boolean;
var i, k: Integer; hit: Boolean;
begin
  Result := False;
  for i := 0 to High(AProps) do
  begin
    hit := False;
    for k := 0 to High(AFinal) do
      if AFinal[k].Key = AProps[i].Key then
      begin
        if not TyAnimValueSame(AFinal[k].Value, AProps[i].Value) then Exit;
        hit := True;
        Break;
      end;
    if not hit then Exit;
  end;
  Result := True;
end;

function TTyAdvanceChart.PtrModelOf(const AHit: TTyAxisHit; out AOwn: TJSONObject): TTyAnimModel;
const
  cKeys: array[0..3] of string = ('animation', 'animationDurationUpdate',
    'animationEasingUpdate', 'animationDelayUpdate');
var
  axisNode, tip, ap, tap, d: TJSONData;
  k: Integer;
begin
  { the axis' own axisPointer over the tooltip's, key by key }
  AOwn := TJSONObject.Create;
  ap := nil;
  tap := nil;
  axisNode := FOption.ComponentAt(AHit.Axis.MainType, AHit.Axis.ComponentIndex);
  if axisNode is TJSONObject then ap := TJSONObject(axisNode).Find('axisPointer');
  if FOption.Root is TJSONObject then
  begin
    tip := TJSONObject(FOption.Root).Find('tooltip');
    if (tip is TJSONArray) and (tip.Count > 0) then tip := tip.Items[0];
    if tip is TJSONObject then tap := TJSONObject(tip).Find('axisPointer');
  end;
  for k := 0 to High(cKeys) do
  begin
    d := nil;
    if ap is TJSONObject then d := TJSONObject(ap).Find(cKeys[k]);
    if ((d = nil) or (d.JSONType = jtNull)) and (tap is TJSONObject) then
      d := TJSONObject(tap).Find(cKeys[k]);
    if (d <> nil) and (d.JSONType <> jtNull) then AOwn.Add(cKeys[k], d.Clone);
  end;
  Result := TyAnimComponentModel(AOwn, FOption.Root, 'tooltip.axisPointer');
end;

function TTyAdvanceChart.PtrMoves(const AHit: TTyAxisHit; const AModel: TTyAnimModel): Boolean;
var
  v: TTyAnimOptValue;
  isCat: Boolean;
  s, cnt: Integer;
begin
  { determineAnimation (BaseAxisPointer.ts:211-242) }
  isCat := AHit.Axis.Scale is TTyOrdinalScale;
  if (not AHit.Spec.Snap) and not isCat then Exit(False);
  v := TyAnimGetShallow(AModel, 'animation');
  if (v.Kind in [aokUndefined, aokNull]) or ((v.Kind = aokString) and (v.Str = 'auto')) then
  begin
    if isCat and (AHit.Axis.BandWidth > 15) then Exit(True);
    if AHit.Spec.Snap then
    begin
      { the series on the axis' coordinate system, all their data }
      cnt := 0;
      for s := 0 to High(FBindings) do
        if (s <= High(FStores)) and (FStores[s] <> nil)
          and ((FBindings[s].XAxis = AHit.Axis) or (FBindings[s].YAxis = AHit.Axis)) then
          Inc(cnt, FStores[s].Count);
      Exit(Abs(AHit.Axis.PxStart - AHit.Axis.PxStop) / cnt > 15);
    end;
    Exit(False);
  end;
  Result := (v.Kind = aokBool) and (v.Num <> 0);
end;

function TTyAdvanceChart.PtrProps(const AHit: TTyAxisHit; AAt: Double): TTyAnimProps;
var sh: TTyXYWH;
begin
  { CartesianAxisPointer's shapes: a line across the other axis' extent, or
    the band -- clamped to the axis, across the other axis as its extent
    runs [Batch 101]
    [Revised in batch 101: a category's band about the value, unclamped,
    from the plot's bottom (left) edge.] }
  if AHit.Spec.PointerType = aptShadow then
  begin
    if not PointerShadowShapeAt(AHit, AAt, sh) then sh := Default(TTyXYWH);
    Result := TyAnimProps([TyAnimProp('shape.x', TyAnimNum(sh.X)),
      TyAnimProp('shape.y', TyAnimNum(sh.Y)),
      TyAnimProp('shape.width', TyAnimNum(sh.W)),
      TyAnimProp('shape.height', TyAnimNum(sh.H))]);
  end
  else if AHit.Axis.Horizontal then
    Result := TyAnimProps([TyAnimProp('shape.x1', TyAnimNum(AAt)),
      TyAnimProp('shape.y1', TyAnimNum(AHit.Plot.Bottom)),
      TyAnimProp('shape.x2', TyAnimNum(AAt)),
      TyAnimProp('shape.y2', TyAnimNum(AHit.Plot.Top))])
  else
    Result := TyAnimProps([TyAnimProp('shape.x1', TyAnimNum(AHit.Plot.Left)),
      TyAnimProp('shape.y1', TyAnimNum(AAt)),
      TyAnimProp('shape.x2', TyAnimNum(AHit.Plot.Right)),
      TyAnimProp('shape.y2', TyAnimNum(AAt))]);
end;

procedure TTyAdvanceChart.PtrAnimSync;
var
  i, k: Integer;
  hit: TTyAxisHit;
  at: Double;
  key: string;
  p: TTyChartAnimProxy;
  props: TTyAnimProps;
  model: TTyAnimModel;
  own: TJSONObject;
begin
  { a mouse moves only over a live window: every mode but camOff }
  if (FAnimMode = camOff) or (csDesigning in ComponentState) then Exit;
  for i := 0 to High(FTipHits) do
  begin
    hit := FTipHits[i];
    if (hit.Axis = nil) or (hit.Spec.PointerType = aptNone) then Continue;
    { a polar pointer does not slide [Batch 111], nor a single's
      [Batch 118] }
    if (hit.Polar <> nil) or (hit.Single <> nil) then Continue;
    at := hit.Axis.DataToCoord(PointerValue(hit), True);
    if IsNan(at) then Continue;
    key := PtrKeyOf(hit.Axis);
    props := PtrProps(hit, at);
    if FPtrProxies = nil then FPtrProxies := TFPList.Create;
    if FPtrAnim = nil then FPtrAnim := NewAnimDriver;
    p := nil;
    for k := 0 to FPtrProxies.Count - 1 do
      if TTyChartAnimProxy(FPtrProxies[k]).Role = key then
      begin
        p := TTyChartAnimProxy(FPtrProxies[k]);
        Break;
      end;
    if p = nil then
    begin
      { THE FIRST SHOW IS DIRECT }
      p := TTyChartAnimProxy.Create(-1, -1, key);
      p.Animation := FPtrAnim;
      p.Attr(props);
      p.SetFinal(props);
      FPtrProxies.Add(p);
      Continue;
    end;
    { propsEqual: nothing new, nothing done }
    if PtrPropsSame(p.Final, props) then Continue;
    model := PtrModelOf(hit, own);
    try
      p.SetFinal(props);
      if PtrMoves(hit, model) then
        TyUpdateProps(p, props, model, TyAnimCallNoIndex)
      else
      begin
        p.StopAnimation;
        p.Attr(props);
      end;
    finally
      own.Free;
    end;
  end;
  AnimArmTimer;
end;

function TTyAdvanceChart.PtrShadowNow(const AHit: TTyAxisHit;
  out AShape: TTyXYWH): Boolean;
var
  k: Integer;
  p: TTyChartAnimProxy;
  key: string;
begin
  { an export draws the pointer where it rests [Batch 106] }
  if (FPtrProxies <> nil) and (AHit.Axis <> nil) and not FExporting then
  begin
    key := PtrKeyOf(AHit.Axis);
    for k := 0 to FPtrProxies.Count - 1 do
    begin
      p := TTyChartAnimProxy(FPtrProxies[k]);
      if p.Role <> key then Continue;
      if p.AtFinal then Break;
      AShape.X := p.Num('shape.x');
      AShape.Y := p.Num('shape.y');
      AShape.W := p.Num('shape.width');
      AShape.H := p.Num('shape.height');
      if not (IsNan(AShape.X) or IsNan(AShape.Y) or IsNan(AShape.W)
        or IsNan(AShape.H)) then Exit(True);
      Break;
    end;
  end;
  Result := PointerShadowShape(AHit, AShape);
end;

function TTyAdvanceChart.PtrAt(const AHit: TTyAxisHit; AAt: Double): Double;
var
  k: Integer;
  p: TTyChartAnimProxy;
  key: string;
begin
  Result := AAt;
  if (FPtrProxies = nil) or (AHit.Axis = nil) or FExporting then Exit;
  key := PtrKeyOf(AHit.Axis);
  for k := 0 to FPtrProxies.Count - 1 do
  begin
    p := TTyChartAnimProxy(FPtrProxies[k]);
    if p.Role <> key then Continue;
    if p.AtFinal then Exit;
    if AHit.Spec.PointerType = aptShadow then
    begin
      if AHit.Axis.Horizontal then Result := p.Num('shape.x') + p.Num('shape.width') / 2
      else Result := p.Num('shape.y') + p.Num('shape.height') / 2;
    end
    else if AHit.Axis.Horizontal then Result := p.Num('shape.x1')
    else Result := p.Num('shape.y1');
    if IsNan(Result) then Result := AAt;
    Exit;
  end;
end;

function TTyAdvanceChart.AnimPointerClipCount: Integer;
begin
  if FPtrAnim = nil then Result := 0 else Result := FPtrAnim.ClipCount;
end;

function TTyAdvanceChart.AnimPointerProxy(const AKey: string): TTyChartAnimProxy;
var k: Integer;
begin
  Result := nil;
  if FPtrProxies = nil then Exit;
  for k := 0 to FPtrProxies.Count - 1 do
    if TTyChartAnimProxy(FPtrProxies[k]).Role = AKey then
      Exit(TTyChartAnimProxy(FPtrProxies[k]));
end;

function TTyAdvanceChart.AnimLoopOnly: Boolean;
var i: Integer;
begin
  Result := (FAnim <> nil) and (FAnim.ClipCount > 0);
  if not Result then Exit;
  for i := 0 to FAnim.ClipCount - 1 do
    if not FAnim.ClipAt(i).Loop then Exit(False);
end;

function TTyAdvanceChart.AnimPart(AContinuous: Boolean): TTyPaintList;
var
  frame: TTyPaintList;
  i, h: Integer;
  pe: PTyChartElement;
  cont: Boolean;
begin
  frame := AnimFrame;
  if FAnimSplit = nil then FAnimSplit := TTyPaintList.Create;
  FAnimSplit.Clear;
  Result := FAnimSplit;
  if frame = nil then Exit;
  { read in place, copied only into the half it goes to [P2] }
  for i := 0 to frame.Count - 1 do
  begin
    pe := frame.Ref(i);
    { a ripple, an effect symbol, and a label hanging off one; a lines
      effect symbol, and every element of a lines series with a trail
      (its layer is redrawn every frame) [Batch 121] }
    cont := pe^.Anim.Role in [carRipple, carEffectSymbol, carLinesEffect];
    if (not cont) and (pe^.Datum.Kind = ctkSeries)
      and (LinesTrailAlpha(pe^.Datum.SeriesIndex) > 0) then cont := True;
    if (not cont) and (pe^.Anim.Role = carLabel) then
    begin
      h := pe^.Anim.HostPlus1 - 1;
      cont := (h >= 0) and (h < frame.Count)
        and (frame.Ref(h)^.Anim.Role = carEffectSymbol);
    end;
    if cont = AContinuous then FAnimSplit.Add(pe^);
  end;
end;

function TTyAdvanceChart.AnimClipCount: Integer;
begin
  if FAnim = nil then Result := 0 else Result := FAnim.ClipCount;
end;

function TTyAdvanceChart.AnimLoopClipCount: Integer;
var i: Integer;
begin
  Result := 0;
  if FAnim = nil then Exit;
  for i := 0 to FAnim.ClipCount - 1 do
    if FAnim.ClipAt(i).Loop then Inc(Result);
end;

{ the states' own proxies ('st:' roles) are not the animations' [Batch 94] }
function IsStateOnlyProxy(P: TTyChartAnimProxy): Boolean;
begin
  Result := Copy(P.Role, 1, 3) = 'st:';
end;

function TTyAdvanceChart.AnimProxyCount: Integer;
var i: Integer;
begin
  Result := 0;
  if FAnimSet = nil then Exit;
  for i := 0 to FAnimSet.Count - 1 do
    if not IsStateOnlyProxy(FAnimSet.Item(i)) then Inc(Result);
end;

function TTyAdvanceChart.AnimProxy(AIndex: Integer): TTyChartAnimProxy;
var i, n: Integer;
begin
  Result := nil;
  if (FAnimSet = nil) or (AIndex < 0) then Exit;
  n := 0;
  for i := 0 to FAnimSet.Count - 1 do
  begin
    if IsStateOnlyProxy(FAnimSet.Item(i)) then Continue;
    if n = AIndex then Exit(FAnimSet.Item(i));
    Inc(n);
  end;
end;

function TTyAdvanceChart.AnimFindProxy(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  if FAnimSet = nil then Exit(nil);
  Result := FAnimSet.Find(ASeries, AIndex, ARole);
end;

function TTyAdvanceChart.AnimFindGhost(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  if FAnimSet = nil then Exit(nil);
  Result := FAnimSet.FindGhost(ASeries, AIndex, ARole);
end;

function TTyAdvanceChart.AnimStateProxy(ASeries, ARow: Integer;
  const APart: string): TTyChartAnimProxy;
var idx: Integer;
begin
  Result := nil;
  idx := StatePartIndex(ASeries, ARow, APart);
  if (idx >= 0) and (idx <= High(FAnimStBind)) then Result := FAnimStBind[idx];
end;

function TTyAdvanceChart.StatePartRecord(ASeries, ARow: Integer;
  const APart: string; out AEl: TTyStElement): Boolean;
var
  item: TTyStItem;
  idx, k: Integer;
begin
  AEl := Default(TTyStElement);
  Result := False;
  if APart = 'peer' then
  begin
    if not PeerStates(ASeries, ARow, item) then Exit;
    AEl := item.Host;
    Exit(True);
  end;
  { [F3a] the second set of rows: an edge, its label, its k-th part }
  if Copy(APart, 1, 4) = 'edge' then
  begin
    if not EdgeStates(ASeries, ARow, item) then Exit;
    if APart = 'edge' then AEl := item.Host
    else if APart = 'edgelabel' then AEl := item.Label_
    else if Copy(APart, 1, 8) = 'edgepart' then
    begin
      k := StrToIntDef(Copy(APart, 9, MaxInt), -1);
      if (k < 0) or (k > High(item.Parts)) then Exit;
      AEl := item.Parts[k];
    end;
    Exit(AEl.Exists);
  end;
  if not ItemStates(ASeries, ARow, item) then Exit;
  if APart = 'host' then AEl := item.Host
  else if APart = 'label' then AEl := item.Label_
  else if APart = 'guide' then AEl := item.Guide
  else
  begin
    { a part: the one whose list index is the part's }
    idx := StatePartIndex(ASeries, ARow, APart);
    if idx < 0 then Exit;
    k := StInnerRaw(ASeries, ARow);
    if (k < 0) or (k > High(FSt[ASeries].PartIdx)) then Exit;
    for k := 0 to Min(High(FSt[ASeries].PartIdx[StInnerRaw(ASeries, ARow)]), High(item.Parts)) do
      if FSt[ASeries].PartIdx[StInnerRaw(ASeries, ARow)][k] = idx then
      begin
        AEl := item.Parts[k];
        Exit(True);
      end;
    Exit;
  end;
  Result := AEl.Exists;
end;

function TTyAdvanceChart.StatePartIndex(ASeries, ARow: Integer;
  const APart: string): Integer;
var slot, raw, idx, k, j, n: Integer;
begin
  Result := -1;
  if (ASeries < 0) or (ASeries > High(FSt)) or (FSt[ASeries].Kind = sskNone) then Exit;
  idx := -1;
  if APart = 'poly' then
  begin
    if Length(FSt[ASeries].RunIdx) > 0 then idx := FSt[ASeries].RunIdx[0];
  end
  else if APart = 'area' then
  begin
    if Length(FSt[ASeries].AreaIdx) > 0 then idx := FSt[ASeries].AreaIdx[0];
  end
  { [F2a] the second set of rows by its own index: 'edge', 'edgelabel',
    'edgepart<k>' }
  else if Copy(APart, 1, 4) = 'edge' then
  begin
    if (ARow < 0) or (ARow > High(FSt[ASeries].EdgeHostIdx)) then Exit;
    if APart = 'edge' then idx := FSt[ASeries].EdgeHostIdx[ARow]
    else if APart = 'edgelabel' then idx := FSt[ASeries].EdgeLabelIdx[ARow]
    else if (Copy(APart, 1, 8) = 'edgepart') and (ARow <= High(FSt[ASeries].EdgePartIdx)) then
    begin
      raw := StrToIntDef(Copy(APart, 9, MaxInt), -1);
      if (raw >= 0) and (raw <= High(FSt[ASeries].EdgePartIdx[ARow])) then
        idx := FSt[ASeries].EdgePartIdx[ARow][raw];
    end;
  end
  else
  begin
    slot := SlotOfSeries(ASeries);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
    if (ARow < 0) or (ARow >= FStores[slot].Count) then Exit;
    raw := FStores[slot].GetRawIndex(ARow);
    if (raw < 0) or (raw > High(FSt[ASeries].HostIdx)) then Exit;
    if APart = 'host' then idx := FSt[ASeries].HostIdx[raw]
    else if APart = 'label' then idx := FSt[ASeries].LabelIdx[raw]
    else if APart = 'guide' then idx := FSt[ASeries].GuideIdx[raw]
    { [F2b] a gauge's arc; the k-th other path; a radar's polygon and its
      j-th symbol }
    else if APart = 'peer' then
    begin
      if raw <= High(FSt[ASeries].PeerHostIdx) then idx := FSt[ASeries].PeerHostIdx[raw];
    end
    else if (Copy(APart, 1, 4) = 'part') and (raw <= High(FSt[ASeries].PartIdx)) then
    begin
      k := StrToIntDef(Copy(APart, 5, MaxInt), -1);
      if (k >= 0) and (k <= High(FSt[ASeries].PartIdx[raw])) then
        idx := FSt[ASeries].PartIdx[raw][k];
    end
    { [R2-I1] 'rsym<j>#label' / 'rsym<j>#guide': point j's label and its
      line, by the point (the label's LabelSub) }
    else if (Copy(APart, 1, 4) = 'rsym') and (Pos('#', APart) > 0)
      and (raw <= High(FSt[ASeries].PartIdx)) and (FPaintList <> nil) then
    begin
      j := StrToIntDef(Copy(APart, 5, Pos('#', APart) - 5), -1);
      for k := 0 to High(FSt[ASeries].PartIdx[raw]) do
        with FPaintList.Ref(FSt[ASeries].PartIdx[raw][k])^ do
          if (Anim.Sub = j + 1) and (((Copy(APart, Pos('#', APart), MaxInt) = '#label')
            and (Caption.FontSizeLogical > 0))
            or ((Copy(APart, Pos('#', APart), MaxInt) = '#guide') and IsGuide)) then
            idx := FSt[ASeries].PartIdx[raw][k];
    end
    else if ((APart = 'rarea') or (Copy(APart, 1, 4) = 'rsym')
      or (Copy(APart, 1, 4) = 'rlab'))
      and (raw <= High(FSt[ASeries].PartIdx)) and (FPaintList <> nil) then
    begin
      { [R2-A] 'rlab<j>': its j-th point label, which the symbols do not count }
      j := StrToIntDef(Copy(APart, 5, MaxInt), -1);
      n := 0;
      for k := 0 to High(FSt[ASeries].PartIdx[raw]) do
        if FPaintList.Element(FSt[ASeries].PartIdx[raw][k]).Anim.Role = carRadarArea then
        begin
          if APart = 'rarea' then idx := FSt[ASeries].PartIdx[raw][k];
        end
        { [R2-I1] a label line is neither }
        else if FPaintList.Element(FSt[ASeries].PartIdx[raw][k]).IsGuide then
        else if (FPaintList.Element(FSt[ASeries].PartIdx[raw][k]).Caption.FontSizeLogical > 0)
          = (Copy(APart, 1, 4) = 'rlab') then
        begin
          if n = j then idx := FSt[ASeries].PartIdx[raw][k];
          Inc(n);
        end;
    end;
  end;
  Result := idx;
end;

function TTyAdvanceChart.AnimGhostCount: Integer;
begin
  if FAnimSet = nil then Result := 0 else Result := FAnimSet.LiveGhostCount;
end;

function TTyAdvanceChart.AnimFrame: TTyPaintList;
begin
  if (FPaintList = nil) or ((Length(FAnimBind) = 0) and (Length(FAnimStBind) = 0)
    and ((FAnimSet = nil) or (FAnimSet.GhostCount = 0)) and not TmAnimAny) then
    Exit(FPaintList);
  if FAnimFrame = nil then FAnimFrame := TTyPaintList.Create;
  TyAnimBuildFrame(FPaintList, FAnimFrame, FAnimBind, FAnimSet, FAnimStBind);
  { a treemap's drill-down, its own wrap [Batch 115] }
  if TmAnimAny then TreemapFrame(FAnimFrame);
  Result := FAnimFrame;
end;
