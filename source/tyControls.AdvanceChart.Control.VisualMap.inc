{ Part of tyControls.AdvanceChart (included, not a unit): the visualMap components --
  their solve, views, interaction and actions. Moved out of the unit only to keep it
  readable; what the control is and why it is built the way it is, see the unit header. }

{ [Batch 116] below, by the visualMap interaction }
procedure VmApplySel(var ASpec: TTyVisualMapSpec; const AJson: string); forward;

procedure TTyCustomAdvanceChart.SolveVisualMaps;
var
  i, k, n, raw, col, dimIndex: Integer;
  spec: TTyVisualMapSpec;
  st: TTyDataStore;
  sid: string;
  d: TJSONData;
  baseColor: TTyVisualColor;
  values: TTyDoubleArray;
  texts: TTyStringArray;
  rows: TTyVisualRowArray;
  meta: TTyVisualMeta;
  offKey: Integer;
  ov: TTyDataValue;
  ramp: TTyVisualColorArray;
begin
  FVisualSpecs := nil;
  FVisualRows := nil;
  FVisualMetas := nil;
  FVisualLines := nil;
  n := TyVisualMapCount(FOption);
  { the views' own state follows the components [Batch 116] }
  VmEnsure(n);
  if n = 0 then Exit;
  { THE FALLBACK RAMP IS THE SKIN'S. Upstream derives it from its theme's
    first colour; the theme here is the .tycss accent, which is series slot
    one -- so an unconfigured visualMap is drawn in the skin's colour. A root
    `gradientColor` still wins. }
  ramp := TyVisualDefaultRamp(TTyChartColor(ThemeRampColor(0)));
  SetLength(FVisualSpecs, n);
  SetLength(FVisualViews, n);
  SetLength(FVisualLayouts, n);
  for k := 0 to n - 1 do
  begin
    FVisualViews[k] := TyVisualMapViewSpecOf(FOption, k);
    { a view the update does not rebuild keeps what it shows [Batch 116] }
    if not VmKeepNow(k) then FVisualLayouts[k] := Default(TTyVisualMapLayout);
    { the controller's colour for a state it was given nothing for:
      `inactiveColor` as written, the theme's otherwise }
    { [R3-B] the model's own visuals, as the merges left them }
    if FVisualViews[k].HasInactive then
      FVisualSpecs[k] := TyVisualMapSpecOf(FOption, k, ramp,
        FVisualViews[k].Inactive, VmModel(k))
    else
      FVisualSpecs[k] := TyVisualMapSpecOf(FOption, k, ramp,
        TyVisualFromChart(TTyChartColor(ActiveController.Model.ResolveStyle(
          'TyAdvChartVisualMapInactive', '', []).TextColor)), VmModel(k));
    { WHAT selectDataRange WROTE INTO THE MODEL [Batch 116]: a continuous
      one's range, a piecewise one's selected map }
    if (FVisualSpecs[k].SubType = 'continuous') and FVmRangeHas[k] then
    begin
      FVisualSpecs[k].Range0 := FVmRange0[k];
      FVisualSpecs[k].Range1 := FVmRange1[k];
      FVisualSpecs[k].RangeAuto := False;
    end
    else if (FVisualSpecs[k].SubType = 'piecewise') and (FVmSel[k] <> '') then
      VmApplySel(FVisualSpecs[k], FVmSel[k]);
    { [Batch 58: a piecewise one encodes now; its note went.] }
  end;
  SetLength(FVisualRows, Length(FBindings));
  SetLength(FVisualMetas, Length(FBindings));
  SetLength(FVisualLines, Length(FBindings));
  offKey := TyOverrideKey('visualMap');
  for i := 0 to High(FBindings) do
  begin
    if i > High(FStores) then Break;
    st := FStores[i];
    if st = nil then Continue;
    sid := '';
    d := FOption.ComponentAt('series', FBindings[i].SeriesIndex);
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      d := TJSONObject(d).Find('id');
      if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then sid := d.AsString;
    end;
    baseColor := TyVisualFromChart(TTyChartColor(
      SeriesColor(FBindings[i].SeriesIndex)));
    rows := nil;
    { IN COMPONENT ORDER: a second visualMap on the same series starts from
      what the first one wrote }
    for k := 0 to n - 1 do
    begin
      spec := FVisualSpecs[k];
      if not TyVisualMapTargets(spec, FBindings[i].SeriesIndex, sid) then Continue;
      { with each value's text: what a category or a string piece matches --
        [R2-L] and nothing else reads it: without either, no texts }
      if TyVisualSpecReadsText(spec) then
        values := TyVisualSeriesValues(st,
          TyVisualMapDimFor(spec, FBindings[i].SeriesIndex, sid), col, dimIndex,
          texts)
      else
      begin
        values := TyVisualSeriesValues(st,
          TyVisualMapDimFor(spec, FBindings[i].SeriesIndex, sid), col, dimIndex);
        texts := nil;
        SetLength(texts, Length(values));
      end;
      if rows = nil then
      begin
        SetLength(rows, st.RawCount);
        for raw := 0 to High(rows) do
        begin
          rows[raw] := Default(TTyVisualRow);
          rows[raw].Color := baseColor;
          rows[raw].Opacity := NaN;
        end;
      end;
      for raw := 0 to High(rows) do
      begin
        { `visualMap: false` on the item opts it out of every component }
        if st.HasOverrideByRaw(raw, offKey) then
        begin
          ov := st.GetOverrideByRaw(raw, offKey);
          if (ov.Kind = dvkBool) and (ov.Num = 0) then Continue;
        end;
        TyVisualApply(spec, TyVisualValueState(spec, values[raw], texts[raw]),
          values[raw], texts[raw], rows[raw], False);
      end;
      if dimIndex >= 0 then
      begin
        meta := TyVisualMetaOf(spec, baseColor);
        meta.Dimension := dimIndex;
        meta.CoordDim := '';
        if col >= 0 then
        begin
          meta.CoordDim := st.DimCoord(col);
          if meta.CoordDim = '' then meta.CoordDim := st.DimName(col);
          if (meta.CoordDim <> 'x') and (meta.CoordDim <> 'y') then
            meta.CoordDim := '';
        end;
        SetLength(FVisualMetas[i], Length(FVisualMetas[i]) + 1);
        FVisualMetas[i][High(FVisualMetas[i])] := meta;
      end;
    end;
    FVisualRows[i] := rows;
  end;
end;

procedure TTyCustomAdvanceChart.ApplyVisualMaps(var AVisual: TTySeriesVisual;
  ASlot, APPI: Integer);
var
  k: Integer;
  node: TJSONObject;
  d: TJSONData;
  axis: TTyAxis;
  metas: TTyVisualMetaArray;
  origin, len: Double;
begin
  { the per-datum palette and the datums' object colours ride along with the
    visual rows: every caller that asks for these asks for those [Batch 105] }
  AVisual.RowFills := SeriesRowFills(ASlot);
  { and the decals, which ride with them [Batch 131] }
  if (ASlot >= 0) and (ASlot <= High(FSeriesDecals)) then
  begin
    AVisual.Decal := FSeriesDecals[ASlot];
    AVisual.RowDecals := FRowDecals[ASlot];
    AVisual.RowDecalSet := FRowDecalSet[ASlot];
  end;
  if (ASlot < 0) or (ASlot > High(FVisualRows)) then Exit;
  AVisual.VisualRows := FVisualRows[ASlot];
  if APPI <= 0 then Exit;
  FVisualLines[ASlot] := Default(TTyVisualLineFill);
  { A LINE ONLY, and on a grid: LineView's getVisualGradient, from the LAST
    visualMeta whose dimension is x or y }
  if FBindings[ASlot].SeriesType <> 'line' then Exit;
  if not FBindings[ASlot].HasAxes then Exit;
  if (ASlot > High(FStores)) or (FStores[ASlot] = nil)
    or (FStores[ASlot].Count = 0) then Exit;
  metas := FVisualMetas[ASlot];
  k := High(metas);
  while (k >= 0) and (metas[k].CoordDim = '') do Dec(k);
  if k < 0 then Exit;
  axis := nil;
  if (FBindings[ASlot].BaseAxis <> nil)
    and (FBindings[ASlot].BaseAxis.Dim = metas[k].CoordDim) then
    axis := FBindings[ASlot].BaseAxis
  else if (FBindings[ASlot].ValueAxis <> nil)
    and (FBindings[ASlot].ValueAxis.Dim = metas[k].CoordDim) then
    axis := FBindings[ASlot].ValueAxis;
  if axis = nil then Exit;
  { CLIPPED TO THE CANVAS, not to the plot: api.getWidth() / getHeight() }
  if metas[k].CoordDim = 'x' then
  begin
    origin := FLastRect.Left;
    len := FLastRect.Right - FLastRect.Left;
  end
  else
  begin
    origin := FLastRect.Top;
    len := FLastRect.Bottom - FLastRect.Top;
  end;
  FVisualLines[ASlot] := TyVisualLineFillOf(metas[k], axis, origin, len,
    APPI / 96);
  AVisual.VisualLine := FVisualLines[ASlot];
  { the pen keeps an authored lineStyle.color, the area an authored
    areaStyle.color -- `defaults(style, {stroke: visualColor})` }
  AVisual.VisualLineStroke := True;
  AVisual.VisualLineArea := True;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    node := TJSONObject(d);
    AVisual.VisualLineStroke := not TyReadOptStyle(node, 'lineStyle').Color.Written;
    AVisual.VisualLineArea := not TyReadOptStyle(node, 'areaStyle').Color.Written;
  end;
end;

function TTyCustomAdvanceChart.VisualMapContent(const AView: TTyVmViewSpec): TTyVisualColor;
begin
  { `contentColor` as written; upstream's default is its first theme colour,
    which here is the skin's accent -- series slot one }
  if AView.HasContent then Exit(AView.Content);
  Result := TyVisualFromChart(TTyChartColor(ThemeRampColor(0)));
end;

function TTyCustomAdvanceChart.VisualMapInk(const AView: TTyVmViewSpec): TTyVisualMapInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartVisualMap', '', []);
  Result.FontName := st.FontName;
  Result.FontSizeLogical := ResolveFontSize(st);
  Result.FontWeight := st.FontWeight;
  Result.Text := TTyChartColor(st.TextColor);
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    Result.Text, [ttpSize, ttpWeight, ttpFamily]);
  if AView.FontSize > 0 then Result.FontSizeLogical := AView.FontSize;
  if AView.HasText_ then Result.Text := AView.TextColour;
  if AView.HasBorder then Result.Border := AView.BorderColour
  else Result.Border := TTyChartColor(
    model.ResolveStyle('TyAdvChartVisualMapBorder', '', []).BorderColor);
  if AView.HasBackground then Result.Background := AView.BackgroundColour
  else Result.Background := TTyChartColor(
    model.ResolveStyle('TyAdvChartVisualMapBackground', '', []).Background.Color);
  if AView.HasHandleStroke then Result.HandleStroke := AView.HandleStroke
  else Result.HandleStroke := TTyChartColor(
    model.ResolveStyle('TyAdvChartVisualMapHandle', '', []).BorderColor);
end;

procedure TTyCustomAdvanceChart.SolveVisualMapViews(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  k: Integer;
  keep: Boolean;
  ref: TTyXYWH;
begin
  for k := 0 to High(FVisualLayouts) do
  begin
    { THE VIEW THAT SENT THE selectDataRange IS NOT REBUILT (doRender's
      `payload.from === this.uid`): it shows what its drag made [Batch 116] }
    keep := VmKeepNow(k);
    if k <= High(FVmLive) then FVmLive[k].Keep := False;
    if keep then Continue;
    FVisualLayouts[k] := Default(TTyVisualMapLayout);
    if (k > High(FVisualSpecs)) or (k > High(FVisualViews)) then Break;
    { positionGroup in createBoxLayoutReference's container: a cell or a
      day for one in a host [Batch 154] }
    ComponentRefLocal('visualMap', FVisualSpecs[k].Index, ref);
    FVisualLayouts[k] := TyLayoutVisualMap(FVisualSpecs[k], FVisualViews[k],
      VisualMapContent(FVisualViews[k]), FLastRect.Right - FLastRect.Left,
      FLastRect.Bottom - FLastRect.Top, ref, APPI / 96, AMeasurer,
      VisualMapInk(FVisualViews[k]));
    VmBuilt(k);
  end;
end;

function TTyCustomAdvanceChart.BuildVisualMaps(AList: TTyPaintList): Integer;
var k: Integer;
begin
  Result := 0;
  for k := 0 to High(FVisualLayouts) do
    if (k <= High(FVisualViews)) and FVisualLayouts[k].Valid then
      Inc(Result, TyBuildVisualMapMarks(FVisualLayouts[k], FVisualViews[k],
        VisualMapInk(FVisualViews[k]), FLastRect.Left, FLastRect.Top, AList,
        VmLiveDraw(k)));
end;

function TTyCustomAdvanceChart.VisualMapLayout(AIndex: Integer): TTyVisualMapLayout;
begin
  Result := Default(TTyVisualMapLayout);
  if (AIndex >= 0) and (AIndex <= High(FVisualLayouts)) then
    Result := FVisualLayouts[AIndex];
end;

function TTyCustomAdvanceChart.VisualMapCount: Integer;
begin
  Result := Length(FVisualSpecs);
end;

{ ---- the models' own visuals [R3-B] ---- }

procedure TTyCustomAdvanceChart.VmModelsClear;
var k: Integer;
begin
  for k := 0 to High(FVmModels) do FreeAndNil(FVmModels[k]);
  FVmModels := nil;
end;

procedure TTyCustomAdvanceChart.VmModelsInitAll;
var k: Integer;
begin
  VmModelsClear;
  if FOption = nil then Exit;
  SetLength(FVmModels, FOption.ComponentCount('visualMap'));
  for k := 0 to High(FVmModels) do
  begin
    { init, then optionUpdated(null, true) }
    FVmModels[k] := TyVisualMapModelNew(FOption, k);
    TyVisualMapModelComplete(FOption, k, FVmModels[k]);
  end;
end;

procedure TTyCustomAdvanceChart.VmModelsPass(const AReport: TTyMergeReport);
var
  si, s, n, old: Integer;
  newOpt: TJSONObject;
begin
  if FOption = nil then Exit;
  si := TyMergeSlotsIndex(AReport, 'visualMap');
  if si < 0 then Exit;
  n := Length(AReport.Slots[si].Fate);
  if Length(FVmModels) < n then
  begin
    old := Length(FVmModels);
    SetLength(FVmModels, n);
    for s := old to n - 1 do FVmModels[s] := nil;
  end;
  for s := 0 to n - 1 do
    case AReport.Slots[si].Fate[s] of
      mfNew:
        begin
          FreeAndNil(FVmModels[s]);
          FVmModels[s] := TyVisualMapModelNew(FOption, s);
          TyVisualMapModelComplete(FOption, s, FVmModels[s]);
        end;
      mfMerged, mfKept:
        begin
          if FVmModels[s] = nil then
            FVmModels[s] := TyVisualMapModelNew(FOption, s)
          else if AReport.Slots[si].Fate[s] = mfMerged then
          begin
            { mergeOption, then optionUpdated's replaceVisualOption }
            newOpt := nil;
            if s <= High(AReport.Slots[si].NewOpt) then newOpt := AReport.Slots[si].NewOpt[s];
            TyVisualMapModelMerge(FVmModels[s], newOpt);
          end;
          { completeVisualOption: what is missing, again }
          TyVisualMapModelComplete(FOption, s, FVmModels[s]);
        end;
      mfRemoved, mfHole:
        FreeAndNil(FVmModels[s]);
    end;
  { slots past the report's are gone }
  for s := n to High(FVmModels) do FreeAndNil(FVmModels[s]);
  SetLength(FVmModels, n);
end;

function TTyCustomAdvanceChart.VmModel(AIndex: Integer): TJSONObject;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FVmModels)) then Result := FVmModels[AIndex];
end;

procedure TTyCustomAdvanceChart.VmThemeDefaults(AIndex: Integer; out ARamp: TTyVisualColorArray;
  out AInactive: TTyVisualColor);
var view: TTyVmViewSpec;
begin
  ARamp := TyVisualDefaultRamp(TTyChartColor(ThemeRampColor(0)));
  view := TyVisualMapViewSpecOf(FOption, AIndex);
  if view.HasInactive then AInactive := view.Inactive
  else
    AInactive := TyVisualFromChart(TTyChartColor(ActiveController.Model.ResolveStyle(
      'TyAdvChartVisualMapInactive', '', []).TextColor));
end;

function TTyCustomAdvanceChart.VisualMapVisualsJson(AIndex: Integer): string;
var
  ramp: TTyVisualColorArray;
  inact: TTyVisualColor;
  model, res: TJSONObject;
begin
  Result := '{}';
  if (FOption = nil) or (AIndex < 0) or (AIndex >= TyVisualMapCount(FOption)) then Exit;
  VmThemeDefaults(AIndex, ramp, inact);
  model := VmModel(AIndex);
  if model = nil then
  begin
    model := TyVisualMapModelNew(FOption, AIndex);
    TyVisualMapModelComplete(FOption, AIndex, model);
  end;
  try
    res := TyVisualMapModelResolved(FOption, model, ramp, inact);
    try
      Result := res.AsJSON;
    finally
      res.Free;
    end;
  finally
    if model <> VmModel(AIndex) then model.Free;
  end;
end;

function TTyCustomAdvanceChart.VisualMapSpec(AIndex: Integer): TTyVisualMapSpec;
begin
  Result := Default(TTyVisualMapSpec);
  if (AIndex >= 0) and (AIndex <= High(FVisualSpecs)) then
    Result := FVisualSpecs[AIndex];
end;

function TTyCustomAdvanceChart.VisualRow(ASeriesIndex, ARawIndex: Integer;
  out ARow: TTyVisualRow): Boolean;
var slot: Integer;
begin
  ARow := Default(TTyVisualRow);
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FVisualRows)) then Exit;
  if (ARawIndex < 0) or (ARawIndex > High(FVisualRows[slot])) then Exit;
  ARow := FVisualRows[slot][ARawIndex];
  Result := True;
end;

function TTyCustomAdvanceChart.VisualMetas(ASeriesIndex: Integer): TTyVisualMetaArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FVisualMetas)) then
    Result := FVisualMetas[slot];
end;

function TTyCustomAdvanceChart.VisualLineFill(ASeriesIndex: Integer): TTyVisualLineFill;
var slot: Integer;
begin
  Result := Default(TTyVisualLineFill);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FVisualLines)) then
    Result := FVisualLines[slot];
end;

{ ==================== visualMap interaction [Batch 116, C7] ====================

  ContinuousView's and PiecewiseView's pointer handlers, the hover link both
  ways and the selectDataRange action. The view's own fields live in FVmLive
  (TTyVmLive) between renders, as the view object keeps them upstream: a
  rebuild (_buildView, on every update but the view's own selectDataRange)
  resets the interval from the model, makes new elements (no hover, no blur,
  the indicator hidden and never shown) and keeps the drag and hover flags
  and the last hover link's items.

  THE ORDER OF ONE POINTER EVENT is zrender's: an out to the element left
  (its own handlers, bubbled through the bar group), echarts' mouseout, the
  chart event, then the visualMaps' zr-level mouseout (_hideIndicator); the
  move on the new element (the bar group's mousemove: the hover link), then
  zrender's Draggable (a drift is _dragHandle), then the chart event; an
  over to the new element (a piece's highlight), echarts' mouseover (a
  thumb's emphasis), the chart event, then the visualMaps' zr-level
  mouseover (the indicator for the hovered datum). After the event, the
  frame: a flag that changed becomes a state, which saves the style a state
  leaves -- and restores it when the state ends (a label blurred while its
  handle moved reads the old value again until the next update). }

function VmJsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function VmJsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

{ Number() of a payload value, as Math.max coerces it }
function VmJsNum(AData: TJSONData): Double;
begin
  if AData = nil then Exit(NaN);
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtNull: Result := 0;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtString: Result := TyJsToNumber(AData.AsString);
  else
    Result := NaN;
  end;
end;

{ setSelected of a piecewise model: the map as the action gave it -- a key
  it does not name is not selected (no `not specified means true` here) }
procedure VmApplySel(var ASpec: TTyVisualMapSpec; const AJson: string);
var
  d: TJSONData;
  i: Integer;
begin
  try
    d := GetJSON(AJson);
  except
    d := nil;
  end;
  try
    if not (d is TJSONObject) then Exit;
    SetLength(ASpec.Selected, Length(ASpec.Pieces));
    for i := 0 to High(ASpec.Pieces) do
      ASpec.Selected[i] := JsTruthy(TJSONObject(d).Find(ASpec.Pieces[i].Key));
  finally
    d.Free;
  end;
end;

procedure TTyCustomAdvanceChart.VmEnsure(ACount: Integer);
var i, old: Integer;
begin
  old := Length(FVmLive);
  for i := ACount to old - 1 do
  begin
    if i <= High(FVmIndBag) then FreeAndNil(FVmIndBag[i]);
    if i <= High(FVmLabBag) then FreeAndNil(FVmLabBag[i]);
  end;
  SetLength(FVmLive, ACount);
  SetLength(FVmIndBag, ACount);
  SetLength(FVmLabBag, ACount);
  SetLength(FVmRangeHas, ACount);
  SetLength(FVmRange0, ACount);
  SetLength(FVmRange1, ACount);
  SetLength(FVmSel, ACount);
  for i := old to ACount - 1 do
  begin
    FVmLive[i] := Default(TTyVmLive);
    FVmIndBag[i] := nil;
    FVmLabBag[i] := nil;
    FVmRangeHas[i] := False;
    FVmSel[i] := '';
  end;
  if (FVmDragVm >= ACount) then FVmDragVm := -1;
end;

function TTyCustomAdvanceChart.VmKeepNow(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FVmLive)) and FVmLive[AIndex].Keep
    and FVmLive[AIndex].Alive and (AIndex <= High(FVisualLayouts))
    and FVisualLayouts[AIndex].Valid and not FVisualLayouts[AIndex].Piecewise;
end;

function TTyCustomAdvanceChart.VmContinuous(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FVisualLayouts))
    and (AIndex <= High(FVisualViews)) and (AIndex <= High(FVisualSpecs))
    and (AIndex <= High(FVmLive)) and FVmLive[AIndex].Alive
    and FVisualLayouts[AIndex].Valid and not FVisualLayouts[AIndex].Piecewise;
end;

function TTyCustomAdvanceChart.VmScale: Double;
begin
  if FLastPPI > 0 then Result := FLastPPI / 96 else Result := 1;
end;

function TTyCustomAdvanceChart.VmGroupX(AIndex: Integer): Double;
begin
  Result := FVisualLayouts[AIndex].GroupX + FLastRect.Left;
end;

function TTyCustomAdvanceChart.VmGroupY(AIndex: Integer): Double;
begin
  Result := FVisualLayouts[AIndex].GroupY + FLastRect.Top;
end;

{ _buildView: new elements, the interval from the model }
procedure TTyCustomAdvanceChart.VmBuilt(AIndex: Integer);
var
  L: TTyVisualMapLayout;
  h: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FVmLive)) then Exit;
  Inc(FVmLive[AIndex].Gen);
  L := FVisualLayouts[AIndex];
  FreeAndNil(FVmIndBag[AIndex]);
  FreeAndNil(FVmLabBag[AIndex]);
  if not L.Valid then
  begin
    FVmLive[AIndex].Alive := False;
    Exit;
  end;
  FVmLive[AIndex].Alive := True;
  if FVmLive[AIndex].Uid = '' then
  begin
    Inc(FVmUidSeq);
    FVmLive[AIndex].Uid := 'ec_vm_' + IntToStr(FVmUidSeq);
  end;
  if L.Piecewise then Exit;
  FVmLive[AIndex].Interval[0] := L.Interval[0];
  FVmLive[AIndex].Interval[1] := L.Interval[1];
  FVmLive[AIndex].Ends[0] := L.HandleEnds[0];
  FVmLive[AIndex].Ends[1] := L.HandleEnds[1];
  FVmLive[AIndex].FirstShow := True;
  FVmLive[AIndex].IndVisible := False;
  FVmLive[AIndex].IndLabelVisible := False;
  FVmLive[AIndex].IndLabel := Default(TTyVmText);
  for h := 0 to 1 do
  begin
    FVmLive[AIndex].ThumbHover[h] := 0;
    FVmLive[AIndex].ThumbEmph[h] := False;
    FVmLive[AIndex].LabelBlur[h] := False;
    FVmLive[AIndex].LabelBlurOn[h] := False;
    if h <= High(L.Handles) then
    begin
      FVmLive[AIndex].ThumbFill[h] := L.Handles[h].Fill;
      FVmLive[AIndex].Labels[h] := L.Handles[h].Label_;
    end
    else
    begin
      FVmLive[AIndex].ThumbFill[h] := TyVisualUndefined;
      FVmLive[AIndex].Labels[h] := Default(TTyVmText);
    end;
    FVmLive[AIndex].ThumbSaved[h] := FVmLive[AIndex].ThumbFill[h];
    FVmLive[AIndex].LabelsSaved[h] := FVmLive[AIndex].Labels[h];
  end;
  { the indicator as _createIndicator makes it: at half the item, at 0,
    zrender's default fill; its label at the origin }
  if FVmAnim = nil then FVmAnim := NewAnimDriver;
  FVmIndBag[AIndex] := TTyAnimBag.Create;
  FVmIndBag[AIndex].Animation := FVmAnim;
  FVmIndBag[AIndex].Attr(TyAnimProps([TyAnimProp('x', TyAnimNum(L.ItemW / 2)),
    TyAnimProp('y', TyAnimNum(0)), TyAnimProp('style.fill', TyAnimStr('#000'))]));
  FVmLabBag[AIndex] := TTyAnimBag.Create;
  FVmLabBag[AIndex].Animation := FVmAnim;
  FVmLabBag[AIndex].Attr(TyAnimProps([TyAnimProp('style.x', TyAnimNum(0)),
    TyAnimProp('style.y', TyAnimNum(0))]));
end;

{ ContinuousView.dispose: _clearHoverLinkToSeries dispatches its downplay
  with the very array it then empties -- dispatched inside the update that
  removes the view, the action waits, and runs with nothing in it: an event
  with an empty batch, and every highlight it held stays }
procedure TTyCustomAdvanceChart.VmDispose(AIndex: Integer);
var hadLinks: Boolean;
begin
  if (AIndex < 0) or (AIndex > High(FVmLive)) then Exit;
  hadLinks := FVmLive[AIndex].Alive and (AIndex <= High(FVisualLayouts))
    and FVisualLayouts[AIndex].Valid and not FVisualLayouts[AIndex].Piecewise
    and (AIndex <= High(FVisualViews)) and FVisualViews[AIndex].HoverLink
    and (Length(FVmLive[AIndex].HoverIdx) > 0);
  FVmLive[AIndex] := Default(TTyVmLive);
  FreeAndNil(FVmIndBag[AIndex]);
  FreeAndNil(FVmLabBag[AIndex]);
  if FVmDragVm = AIndex then FVmDragVm := -1;
  if hadLinks then
  begin
    StAllLeaveBlur;
    EmitPayloadEvent('downplay', '{"type":"downplay","batch":[]}');
  end;
end;

procedure TTyCustomAdvanceChart.VmDisposeAll;
var k: Integer;
begin
  for k := 0 to High(FVmLive) do VmDispose(k);
  VmEnsure(0);
  FVmDragVm := -1;
end;

{ zrender's hit test over the visualMaps: the last component on top; in a
  continuous one the ends texts, the thumbs, the bar under its rounded clip,
  then the handle labels (added to the group before the bar group); in a
  piecewise one each child from the last, a label over its symbol. Silent
  things -- the indicator, the background, a piece when nothing selects --
  are not hit. }
function TTyCustomAdvanceChart.VmHitAt(AX, AY: Integer; out AIndex, APart: Integer): Boolean;
var
  k, h, j, part: Integer;
  L: TTyVisualMapLayout;
  gx, gy, ix, iy: Double;
  it: TTyVmItem;
  fill: Boolean;
  lbl: TTyVmText;
begin
  Result := False;
  AIndex := -1;
  APart := 0;
  for k := High(FVisualLayouts) downto 0 do
  begin
    L := FVisualLayouts[k];
    if (not L.Valid) or (k > High(FVisualViews)) then Continue;
    gx := AX - VmGroupX(k);
    gy := AY - VmGroupY(k);
    if L.Piecewise then
    begin
      for j := High(L.Items) downto 0 do
      begin
        it := L.Items[j];
        ix := gx - it.X;
        iy := gy - it.Y;
        if it.IsText then
        begin
          if TyVmTextContains(it.Label_, ix, iy) then
          begin
            AIndex := k;
            if j = 0 then APart := cVmEnds else APart := cVmEnds + 1;
            Exit(True);
          end;
          Continue;
        end;
        if FVisualViews[k].Silent then Continue;
        if it.HasLabel and TyVmTextContains(it.Label_, ix, iy) then
        begin
          AIndex := k;
          APart := cVmPiece + 2 * it.PieceIndex + 1;
          Exit(True);
        end;
        if TyVmSymbolContains(it, ix, iy) then
        begin
          AIndex := k;
          APart := cVmPiece + 2 * it.PieceIndex;
          Exit(True);
        end;
      end;
      Continue;
    end;
    for h := High(L.Texts) downto 0 do
      if TyVmTextContains(L.Texts[h], gx, gy) then
      begin
        AIndex := k;
        APart := cVmText0 + h;
        Exit(True);
      end;
    for h := High(L.Handles) downto 0 do
    begin
      if (k <= High(FVmLive)) and FVmLive[k].Alive and (h <= 1) then
        fill := FVmLive[k].ThumbFill[h].Defined
      else
        fill := L.Handles[h].Fill.Defined;
      if TyVmThumbContains(L, FVisualViews[k], h, fill, gx, gy) then
      begin
        AIndex := k;
        APart := cVmThumb0 + h;
        Exit(True);
      end;
    end;
    part := TyVmBarPartAt(L, gx, gy);
    if part > 0 then
    begin
      AIndex := k;
      APart := part;
      Exit(True);
    end;
    for h := High(L.Handles) downto 0 do
    begin
      if (k <= High(FVmLive)) and FVmLive[k].Alive and (h <= 1) then
        lbl := FVmLive[k].Labels[h]
      else
        lbl := L.Handles[h].Label_;
      if TyVmTextContains(lbl, gx, gy) then
      begin
        AIndex := k;
        APart := cVmLabel0 + h;
        Exit(True);
      end;
    end;
  end;
end;

function TTyCustomAdvanceChart.VmRoleOf(AIndex, APart: Integer): string;
var p: Integer;
begin
  Result := 'vm' + IntToStr(AIndex) + '.';
  case APart of
    cVmOut: Result := Result + 'outOfRange';
    cVmIn: Result := Result + 'inRange';
    cVmThumb0, cVmThumb0 + 1: Result := Result + 'handle' + IntToStr(APart - cVmThumb0);
    cVmLabel0, cVmLabel0 + 1: Result := Result + 'label' + IntToStr(APart - cVmLabel0);
  else
    if (APart >= cVmPiece) and (APart < cVmEnds) then
    begin
      p := (APart - cVmPiece) div 2;
      Result := Result + 'item' + IntToStr(p);
      if (APart - cVmPiece) mod 2 = 1 then Result := Result + '.label'
      else Result := Result + '.symbol';
    end
    else
      { an ends text: no handler of its own }
      Result := Result + 'other';
  end;
end;

{ getTargetSeriesIndices: seriesTargets in their order, else every series,
  else seriesIndex then seriesId }
function TTyCustomAdvanceChart.VmTargetSeries(AIndex: Integer): TTyIntegerArray;
var
  spec: TTyVisualMapSpec;
  i, j, n: Integer;

  procedure Add(ASer: Integer);
  begin
    if (ASer < 0) or (ASer >= n) then Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ASer;
  end;

begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(FVisualSpecs)) then Exit;
  spec := FVisualSpecs[AIndex];
  n := FOption.ComponentCount('series');
  if spec.HasSeriesTargets then
  begin
    for i := 0 to High(spec.SeriesTargets) do
      if spec.SeriesTargets[i].HasIndex then Add(spec.SeriesTargets[i].SeriesIndex)
      else if spec.SeriesTargets[i].HasId then
        for j := 0 to n - 1 do
          if SeriesModelId(j) = spec.SeriesTargets[i].SeriesId then Add(j);
    Exit;
  end;
  if spec.AllSeries then
  begin
    for i := 0 to n - 1 do Add(i);
    Exit;
  end;
  for i := 0 to High(spec.SeriesIndices) do Add(spec.SeriesIndices[i]);
  for i := 0 to High(spec.SeriesIds) do
    for j := 0 to n - 1 do
      if SeriesModelId(j) = spec.SeriesIds[i] then Add(j);
end;

function TTyCustomAdvanceChart.VmSeriesValues(AIndex, ASeries: Integer;
  out AStore: TTyDataStore; out AValues: TTyDoubleArray;
  out ATexts: TTyStringArray): Boolean;
var
  slot, col, dimIndex: Integer;
  sid: string;
  d: TJSONData;
begin
  Result := False;
  AStore := nil;
  AValues := nil;
  ATexts := nil;
  slot := SlotOfSeries(ASeries);
  if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
  AStore := FStores[slot];
  sid := '';
  d := FOption.ComponentAt('series', ASeries);
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    d := TJSONObject(d).Find('id');
    if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then sid := d.AsString;
  end;
  AValues := TyVisualSeriesValues(AStore,
    TyVisualMapDimFor(FVisualSpecs[AIndex], ASeries, sid), col, dimIndex, ATexts);
  Result := True;
end;

{ ContinuousModel.findTargetDataIndices: per target series, the inner
  indices whose value is in [ALo, AHi] }
function TTyCustomAdvanceChart.VmFindRange(AIndex: Integer; ALo, AHi: Double): TTyVmHoverBatches;
var
  targets: TTyIntegerArray;
  t, i, raw, n: Integer;
  st: TTyDataStore;
  vals: TTyDoubleArray;
  texts: TTyStringArray;
  v: Double;
begin
  Result := nil;
  targets := VmTargetSeries(AIndex);
  for t := 0 to High(targets) do
  begin
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n].SeriesIndex := targets[t];
    Result[n].Inner := nil;
    if not VmSeriesValues(AIndex, targets[t], st, vals, texts) then Continue;
    for i := 0 to st.Count - 1 do
    begin
      raw := st.GetRawIndex(i);
      if (raw < 0) or (raw > High(vals)) then v := NaN else v := vals[raw];
      if IsNan(v) or IsNan(ALo) or IsNan(AHi) then Continue;
      if (ALo <= v) and (v <= AHi) then
      begin
        SetLength(Result[n].Inner, Length(Result[n].Inner) + 1);
        Result[n].Inner[High(Result[n].Inner)] := i;
      end;
    end;
  end;
end;

{ PiecewiseModel.findTargetDataIndices: the inner indices whose value's
  piece (no closest) is APiece }
function TTyCustomAdvanceChart.VmFindPiece(AIndex, APiece: Integer): TTyVmHoverBatches;
var
  targets: TTyIntegerArray;
  t, i, raw, n: Integer;
  st: TTyDataStore;
  vals: TTyDoubleArray;
  texts: TTyStringArray;
  v: Double;
  tx: string;
begin
  Result := nil;
  targets := VmTargetSeries(AIndex);
  for t := 0 to High(targets) do
  begin
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n].SeriesIndex := targets[t];
    Result[n].Inner := nil;
    if not VmSeriesValues(AIndex, targets[t], st, vals, texts) then Continue;
    for i := 0 to st.Count - 1 do
    begin
      raw := st.GetRawIndex(i);
      if (raw < 0) or (raw > High(vals)) then Continue;
      v := vals[raw];
      if raw <= High(texts) then tx := texts[raw] else tx := TyJsNumberToString(v);
      if TyVisualFindPiece(FVisualSpecs[AIndex].Pieces, v, tx, False) = APiece then
      begin
        SetLength(Result[n].Inner, Length(Result[n].Inner) + 1);
        Result[n].Inner[High(Result[n].Inner)] := i;
      end;
    end;
  end;
end;

type
  TVmMapEntry = record
    S: Integer;
    Idx: TTyIntegerArray;
    Alive: array of Boolean;
  end;
  TVmMap = array of TVmMapEntry;

{ util/model compressBatches: what the old batch has and the new one has not
  (to downplay), and the reverse (to highlight); a series in the order it was
  first met, its indices ascending }
procedure VmCompress(const A, B: TTyVmHoverBatches; out ADown, AUp: TTyVmHoverBatches);
var
  mapA, mapB: TVmMap;
  i, j: Integer;

  function EntryOf(var M: TVmMap; ASer: Integer; AMake: Boolean): Integer;
  var q: Integer;
  begin
    for q := 0 to High(M) do
      if M[q].S = ASer then Exit(q);
    if not AMake then Exit(-1);
    q := Length(M);
    SetLength(M, q + 1);
    M[q].S := ASer;
    M[q].Idx := nil;
    M[q].Alive := nil;
    Result := q;
  end;

  procedure Put(var M: TVmMap; ASer, AI: Integer);
  var e, q: Integer;
  begin
    e := EntryOf(M, ASer, True);
    for q := 0 to High(M[e].Idx) do
      if M[e].Idx[q] = AI then
      begin
        M[e].Alive[q] := True;
        Exit;
      end;
    q := Length(M[e].Idx);
    SetLength(M[e].Idx, q + 1);
    SetLength(M[e].Alive, q + 1);
    M[e].Idx[q] := AI;
    M[e].Alive[q] := True;
  end;

  function Take(var M: TVmMap; ASer, AI: Integer): Boolean;
  var e, q: Integer;
  begin
    Result := False;
    e := EntryOf(M, ASer, False);
    if e < 0 then Exit;
    for q := 0 to High(M[e].Idx) do
      if (M[e].Idx[q] = AI) and M[e].Alive[q] then
      begin
        M[e].Alive[q] := False;
        Exit(True);
      end;
  end;

  function ToArray(const M: TVmMap): TTyVmHoverBatches;
  var e, q, r, t, n: Integer; list: TTyIntegerArray;
  begin
    Result := nil;
    for e := 0 to High(M) do
    begin
      list := nil;
      for q := 0 to High(M[e].Idx) do
        if M[e].Alive[q] then
        begin
          SetLength(list, Length(list) + 1);
          list[High(list)] := M[e].Idx[q];
        end;
      { integer keys come out ascending }
      for r := 1 to High(list) do
      begin
        t := list[r];
        q := r - 1;
        while (q >= 0) and (list[q] > t) do
        begin
          list[q + 1] := list[q];
          Dec(q);
        end;
        list[q + 1] := t;
      end;
      if Length(list) = 0 then Continue;
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n].SeriesIndex := M[e].S;
      Result[n].Inner := list;
    end;
  end;

begin
  mapA := nil;
  mapB := nil;
  for i := 0 to High(A) do
    for j := 0 to High(A[i].Inner) do Put(mapA, A[i].SeriesIndex, A[i].Inner[j]);
  for i := 0 to High(B) do
    for j := 0 to High(B[i].Inner) do
      if not Take(mapA, B[i].SeriesIndex, B[i].Inner[j]) then
        Put(mapB, B[i].SeriesIndex, B[i].Inner[j]);
  ADown := ToArray(mapA);
  AUp := ToArray(mapB);
end;

{ _dispatchHighDown / onHoverLink: the batch through makeHighDownBatch --
  dataIndex null, dataIndexInside the indices, highlightKey 'visualMap' +
  the component's index; nothing when the batch is empty }
procedure TTyCustomAdvanceChart.VmDispatchHighDown(const AType: string; AIndex: Integer;
  const ABatches: TTyVmHoverBatches);
var
  s: string;
  i, j: Integer;
begin
  if Length(ABatches) = 0 then Exit;
  s := '{"type":"' + AType + '","batch":[';
  for i := 0 to High(ABatches) do
  begin
    if i > 0 then s := s + ',';
    s := s + '{"seriesId":"' + StringToJSONString(SeriesModelId(ABatches[i].SeriesIndex))
      + '","dataIndex":null,"dataIndexInside":[';
    for j := 0 to High(ABatches[i].Inner) do
    begin
      if j > 0 then s := s + ',';
      s := s + IntToStr(ABatches[i].Inner[j]);
    end;
    s := s + '],"highlightKey":"visualMap' + IntToStr(AIndex) + '"}';
  end;
  s := s + ']}';
  DispatchAction(s);
end;

procedure TTyCustomAdvanceChart.VmShowIndicator(AIndex: Integer; ACursor, AText: Double;
  const APrefix: string);
var
  ind: TTyVmIndicator;
  cfg: TTyAnimCfg;
  fill: string;
  h: Integer;
  animOn: Boolean;
begin
  if not VmContinuous(AIndex) or (FVmIndBag[AIndex] = nil) then Exit;
  ind := TyVmIndicatorAt(FVisualLayouts[AIndex], FVisualSpecs[AIndex],
    FVisualViews[AIndex], VisualMapContent(FVisualViews[AIndex]), VmScale,
    NewTextMeasurer(FLastPPI), VisualMapInk(FVisualViews[AIndex]), ACursor, AText,
    APrefix);
  FVmLive[AIndex].IndVisible := True;
  FVmLive[AIndex].IndLabelVisible := True;
  FVmLive[AIndex].IndSize := ind.Size;
  FVmLive[AIndex].IndLabel := ind.Label_;
  fill := TyVisualCss(ind.Fill);
  { ecModel.isAnimationEnabled(), and not the first show: a 100 ms
    cubicInOut slide, ADDITIVE -- a move while one runs adds to it }
  animOn := AnimAllowed and TyAnimIsEnabled(TyAnimComponentModel(nil, FOption.Root, ''));
  if animOn and not FVmLive[AIndex].FirstShow then
  begin
    cfg := TyAnimCfg(100, 0, 'cubicInOut');
    cfg.Additive := True;
    FVmIndBag[AIndex].AnimateTo(TyAnimProps([TyAnimProp('x', TyAnimNum(ind.X)),
      TyAnimProp('y', TyAnimNum(ind.Y)), TyAnimProp('style.fill', TyAnimStr(fill))]), cfg);
    FVmLabBag[AIndex].AnimateTo(TyAnimProps([TyAnimProp('style.x', TyAnimNum(ind.Label_.X)),
      TyAnimProp('style.y', TyAnimNum(ind.Label_.Y))]), cfg);
    AnimArmTimer;
  end
  else
  begin
    FVmIndBag[AIndex].Attr(TyAnimProps([TyAnimProp('x', TyAnimNum(ind.X)),
      TyAnimProp('y', TyAnimNum(ind.Y)), TyAnimProp('style.fill', TyAnimStr(fill))]));
    FVmLabBag[AIndex].Attr(TyAnimProps([TyAnimProp('style.x', TyAnimNum(ind.Label_.X)),
      TyAnimProp('style.y', TyAnimNum(ind.Label_.Y))]));
  end;
  FVmLive[AIndex].FirstShow := False;
  { the handle labels fade: api.enterBlur }
  if FVisualViews[AIndex].Calculable then
    for h := 0 to 1 do FVmLive[AIndex].LabelBlur[h] := True;
  { [R2-L] the visual maps and what follows them, not the whole list }
  ListTailRefresh;
  FZrDirty := True;
  inherited Invalidate;
end;

{ _hideIndicator: both invisible, the handle labels out of the blur }
procedure TTyCustomAdvanceChart.VmHideIndicator(AIndex: Integer);
var h: Integer;
begin
  if not VmContinuous(AIndex) then Exit;
  FVmLive[AIndex].IndVisible := False;
  FVmLive[AIndex].IndLabelVisible := False;
  for h := 0 to 1 do FVmLive[AIndex].LabelBlur[h] := False;
  ListTailRefresh;
  FZrDirty := True;
  inherited Invalidate;
end;

procedure TTyCustomAdvanceChart.VmClearHoverLink(AIndex: Integer);
var idx: TTyVmHoverBatches;
begin
  VmHideIndicator(AIndex);
  if not VmContinuous(AIndex) then Exit;
  idx := FVmLive[AIndex].HoverIdx;
  FVmLive[AIndex].HoverIdx := nil;
  VmDispatchHighDown('downplay', AIndex, idx);
end;

{ _doHoverLinkToSeries: ACursor along the bar (device px) }
procedure TTyCustomAdvanceChart.VmDoHoverLink(AIndex: Integer; ACursor: Double; AOnBar: Boolean);
var
  L: TTyVisualMapLayout;
  spec: TTyVisualMapSpec;
  view: TTyVmViewSpec;
  i1, half, hr0, hr1, cv, v0, v1: Double;
  old, nb, down, up: TTyVmHoverBatches;
  onHandle: Boolean;
begin
  if not VmContinuous(AIndex) then Exit;
  view := FVisualViews[AIndex];
  if not view.HoverLink then Exit;
  L := FVisualLayouts[AIndex];
  spec := FVisualSpecs[AIndex];
  i1 := L.ItemH;
  ACursor := VmJsMin(VmJsMax(0, ACursor), i1);
  half := 6 * VmScale;
  if view.HoverLinkDataSize <> 0 then
    half := TyVmLinearMap(view.HoverLinkDataSize, spec.Extent0, spec.Extent1, 0, i1, True) / 2;
  hr0 := ACursor - half;
  hr1 := ACursor + half;
  cv := TyVmLinearMap(ACursor, 0, i1, spec.Extent0, spec.Extent1, True);
  v0 := TyVmLinearMap(hr0, 0, i1, spec.Extent0, spec.Extent1, True);
  v1 := TyVmLinearMap(hr1, 0, i1, spec.Extent0, spec.Extent1, True);
  { beyond the bar: the range is open on that side }
  if (not IsNan(hr0)) and (hr0 < 0) then v0 := NegInfinity;
  if (not IsNan(hr1)) and (hr1 > i1) then v1 := Infinity;
  if AOnBar then
  begin
    if IsInfinite(v0) and (v0 < 0) then VmShowIndicator(AIndex, cv, v1, '< ')
    else if IsInfinite(v1) and (v1 > 0) then VmShowIndicator(AIndex, cv, v0, '> ')
    else VmShowIndicator(AIndex, cv, cv, cVmAbout);
  end;
  old := FVmLive[AIndex].HoverIdx;
  nb := nil;
  if view.HasHoverLinkOnHandle then onHandle := view.HoverLinkOnHandle
  else onHandle := view.Realtime;
  if AOnBar or onHandle then
  begin
    nb := VmFindRange(AIndex, v0, v1);
    FVmLive[AIndex].HoverIdx := nb;
  end;
  VmCompress(old, nb, down, up);
  VmDispatchHighDown('downplay', AIndex, down);
  VmDispatchHighDown('highlight', AIndex, up);
end;

{ _updateView on the live interval: the in-range bar and the handles; the
  thumbs' fills and the labels are written onto what the elements show }
procedure TTyCustomAdvanceChart.VmUpdateView(AIndex: Integer);
var h: Integer;
begin
  if not VmContinuous(AIndex) then Exit;
  TyVmContinuousUpdate(FVisualLayouts[AIndex], FVisualSpecs[AIndex],
    FVisualViews[AIndex], VisualMapContent(FVisualViews[AIndex]), VmScale,
    NewTextMeasurer(FLastPPI), VisualMapInk(FVisualViews[AIndex]),
    FVmLive[AIndex].Interval[0], FVmLive[AIndex].Interval[1],
    FVmLive[AIndex].Ends[0], FVmLive[AIndex].Ends[1]);
  for h := 0 to Min(1, High(FVisualLayouts[AIndex].Handles)) do
  begin
    FVmLive[AIndex].ThumbFill[h] := FVisualLayouts[AIndex].Handles[h].Fill;
    FVmLive[AIndex].Labels[h] := FVisualLayouts[AIndex].Handles[h].Label_;
  end;
  { [R2-I9] the view alone moved: the visual maps and what follows them }
  ListTailRefresh;
  FZrDirty := True;
  inherited Invalidate;
end;

{ _dragHandle (the 6.1 build's: the handle index bound in, 2 is 'all') }
procedure TTyCustomAdvanceChart.VmDragHandle(AIndex, AHandle: Integer; AIsEnd: Boolean;
  ADX, ADY: Double);
var vx, vy: Double;
begin
  if not VmContinuous(AIndex) then Exit;
  vy := 0;
  { the delta into the bar group: its transform inverted }
  if not AIsEnd then TyVmToBar(FVisualLayouts[AIndex], ADX, ADY, vx, vy);
  VmDragHandleBar(AIndex, AHandle, AIsEnd, vy);
end;

procedure TTyCustomAdvanceChart.VmDragHandleBar(AIndex, AHandle: Integer; AIsEnd: Boolean;
  AVy: Double);
var
  vy, pos: Double;
  ends: array[0..1] of Double;
  view: TTyVmViewSpec;
  spec: TTyVisualMapSpec;
  i1: Double;
  p: TJSONObject;
  arr: TJSONArray;
  onHandle: Boolean;
begin
  if not VmContinuous(AIndex) then Exit;
  view := FVisualViews[AIndex];
  if not view.Calculable then Exit;
  FVmLive[AIndex].Dragging := not AIsEnd;
  if not AIsEnd then
  begin
    vy := AVy;
    spec := FVisualSpecs[AIndex];
    i1 := FVisualLayouts[AIndex].ItemH;
    ends[0] := FVmLive[AIndex].Ends[0];
    ends[1] := FVmLive[AIndex].Ends[1];
    { sliderMove, cross forbidden (minSpan 0) }
    if AHandle = 2 then TyDzSliderMove(vy, ends, 0, i1, -1, 0, NaN)
    else TyDzSliderMove(vy, ends, 0, i1, AHandle, 0, NaN);
    FVmLive[AIndex].Ends[0] := ends[0];
    FVmLive[AIndex].Ends[1] := ends[1];
    FVmLive[AIndex].Interval[0] := TyVmLinearMap(ends[0], 0, i1, spec.Extent0, spec.Extent1, True);
    FVmLive[AIndex].Interval[1] := TyVmLinearMap(ends[1], 0, i1, spec.Extent0, spec.Extent1, True);
    VmHideIndicator(AIndex);
    { the view first, then the action }
    VmUpdateView(AIndex);
  end;
  { the release of a realtime drag dispatches nothing; a drag that is not
    realtime dispatches only there }
  if AIsEnd = not view.Realtime then
  begin
    p := TJSONObject.Create;
    try
      p.Strings['type'] := 'selectDataRange';
      p.Strings['from'] := FVmLive[AIndex].Uid;
      p.Strings['visualMapId'] := ComponentModelId('visualMap', AIndex);
      arr := TJSONArray.Create;
      arr.Add(FVmLive[AIndex].Interval[0]);
      arr.Add(FVmLive[AIndex].Interval[1]);
      p.Arrays['selected'] := arr;
      DoSelectDataRange(p);
    finally
      p.Free;
    end;
    EmitUpdated;
  end;
  if not VmContinuous(AIndex) then Exit;
  if AIsEnd then
  begin
    if not FVmLive[AIndex].Hovering then VmClearHoverLink(AIndex);
  end
  else
  begin
    if view.HasHoverLinkOnHandle then onHandle := view.HoverLinkOnHandle
    else onHandle := view.Realtime;
    if onHandle then
    begin
      { _handleEnds['all'] is undefined: a NaN cursor, nothing in range }
      if AHandle = 2 then pos := NaN else pos := FVmLive[AIndex].Ends[AHandle];
      VmDoHoverLink(AIndex, pos, False);
    end;
  end;
end;

{ zrender's Draggable on mousedown: the target or the first ancestor that is
  draggable -- a thumb, a handle label, the in-range bar (always draggable
  in the 6.1 build; its drift does nothing without calculable) }
function TTyCustomAdvanceChart.VmDragStart(AX, AY: Integer): Boolean;
var t: TTyChartEventTarget;
begin
  Result := False;
  t := EventTargetAt(AX, AY);
  if t.HdKind <> 7 then Exit;
  if not VmContinuous(t.HdSeries) then Exit;
  case t.HdRow of
    cVmIn: FVmDragIdx := 2;
    cVmThumb0, cVmLabel0: FVmDragIdx := 0;
    cVmThumb0 + 1, cVmLabel0 + 1: FVmDragIdx := 1;
  else
    Exit;
  end;
  FVmDragVm := t.HdSeries;
  FVmDragX := AX;
  FVmDragY := AY;
  Result := True;
end;

procedure TTyCustomAdvanceChart.VmDragMove(AX, AY: Integer);
var dx, dy: Integer;
begin
  if FVmDragVm < 0 then Exit;
  dx := AX - FVmDragX;
  dy := AY - FVmDragY;
  FVmDragX := AX;
  FVmDragY := AY;
  VmDragHandle(FVmDragVm, FVmDragIdx, False, dx, dy);
end;

procedure TTyCustomAdvanceChart.VmDragEnd;
var k: Integer;
begin
  if FVmDragVm < 0 then Exit;
  k := FVmDragVm;
  FVmDragVm := -1;
  VmDragHandle(k, FVmDragIdx, True, 0, 0);
end;

{ the element's own handlers, bubbled: the bar group's mousemove and
  mouseout (a continuous view), an item group's mouseover and mouseout (a
  piecewise one) }
procedure TTyCustomAdvanceChart.VmElementEvent(const AType: string;
  const ATarget: TTyChartEventTarget; AX, AY: Integer);
var
  k, part, piece: Integer;
  bx, by: Double;
  L: TTyVisualMapLayout;
begin
  if ATarget.HdKind <> 7 then Exit;
  k := ATarget.HdSeries;
  part := ATarget.HdRow;
  if VmContinuous(k) then
  begin
    if not (part in [cVmOut, cVmIn, cVmThumb0, cVmThumb0 + 1]) then Exit;
    if AType = 'mousemove' then
    begin
      FVmLive[k].Hovering := True;
      if not FVmLive[k].Dragging then
      begin
        L := FVisualLayouts[k];
        TyVmGlobalToBar(L, VmGroupX(k), VmGroupY(k), AX, AY, bx, by);
        by := VmJsMin(VmJsMax(0, by), L.ItemH);
        VmDoHoverLink(k, by, (not IsNan(bx)) and (0 <= bx) and (bx <= L.ItemW));
      end;
    end
    else if AType = 'mouseout' then
    begin
      FVmLive[k].Hovering := False;
      if not FVmLive[k].Dragging then VmClearHoverLink(k);
    end;
    Exit;
  end;
  if (k < 0) or (k > High(FVisualLayouts)) or not FVisualLayouts[k].Piecewise then Exit;
  if (part < cVmPiece) or (part >= cVmEnds) then Exit;
  if (k > High(FVisualViews)) or not FVisualViews[k].HoverLink then Exit;
  piece := (part - cVmPiece) div 2;
  if AType = 'mouseover' then
    VmDispatchHighDown('highlight', k, VmFindPiece(k, piece))
  else if AType = 'mouseout' then
    VmDispatchHighDown('downplay', k, VmFindPiece(k, piece));
end;

{ zr.on('mouseout', _hideIndicator) of every continuous view with hoverLink }
procedure TTyCustomAdvanceChart.VmZrMouseOut;
var k: Integer;
begin
  for k := 0 to High(FVisualLayouts) do
    if VmContinuous(k) and FVisualViews[k].HoverLink then VmHideIndicator(k);
end;

{ zr.on('mouseover', _hoverLinkFromSeriesMouseOver): the hovered element's
  datum -- a series item or a marker (whose index reads its HOST's data) --
  when its series is a target: the indicator at its value }
procedure TTyCustomAdvanceChart.VmZrMouseOver(const ATarget: TTyChartEventTarget);
var
  k, t, raw, slot: Integer;
  targets: TTyIntegerArray;
  st: TTyDataStore;
  v: Double;
  isTarget: Boolean;
  sid: string;
  d: TJSONData;
begin
  if not (ATarget.HdKind in [1, 3]) or ATarget.HdEdge then Exit;
  for k := 0 to High(FVisualLayouts) do
  begin
    if not (VmContinuous(k) and FVisualViews[k].HoverLink) then Continue;
    targets := VmTargetSeries(k);
    isTarget := False;
    for t := 0 to High(targets) do
      if targets[t] = ATarget.HdSeries then isTarget := True;
    if not isTarget then Continue;
    { [R2-L] the hovered row's value alone, as VmSeriesValues reads every
      row's (the texts it adds are not read here) }
    slot := SlotOfSeries(ATarget.HdSeries);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    st := FStores[slot];
    if (ATarget.HdRow < 0) or (ATarget.HdRow >= st.Count) then Continue;
    raw := st.GetRawIndex(ATarget.HdRow);
    if (raw < 0) or (raw >= st.RawCount) then Continue;
    sid := '';
    d := FOption.ComponentAt('series', ATarget.HdSeries);
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      d := TJSONObject(d).Find('id');
      if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then sid := d.AsString;
    end;
    v := TyVisualSeriesValueAt(st, TyVisualMapDimFor(FVisualSpecs[k],
      ATarget.HdSeries, sid), raw);
    if not IsNan(v) then VmShowIndicator(k, v, v, '');
  end;
end;

{ the frame: a flag that changed becomes a state -- a thumb's emphasis, a
  label's blur. Entering one saves the style it has; leaving it puts that
  style back. }
procedure TTyCustomAdvanceChart.VmApplyStates;
var
  k, h: Integer;
  want, anyChange: Boolean;
begin
  anyChange := False;
  for k := 0 to High(FVmLive) do
  begin
    if not VmContinuous(k) then Continue;
    for h := 0 to 1 do
    begin
      want := FVmLive[k].ThumbHover[h] = 2;
      if want <> FVmLive[k].ThumbEmph[h] then
      begin
        if want then FVmLive[k].ThumbSaved[h] := FVmLive[k].ThumbFill[h]
        else FVmLive[k].ThumbFill[h] := FVmLive[k].ThumbSaved[h];
        FVmLive[k].ThumbEmph[h] := want;
        anyChange := True;
      end;
      want := FVmLive[k].LabelBlur[h];
      if want <> FVmLive[k].LabelBlurOn[h] then
      begin
        if want then FVmLive[k].LabelsSaved[h] := FVmLive[k].Labels[h]
        else FVmLive[k].Labels[h] := FVmLive[k].LabelsSaved[h];
        FVmLive[k].LabelBlurOn[h] := want;
        anyChange := True;
      end;
    end;
  end;
  if anyChange then
  begin
    { [R2-I9] the thumbs and the labels are the visual map's own elements:
      the visual maps and what follows them, not the whole list [was:
      DropStatic -- the first hover over a heatmap built every cell again,
      the indicator's first show blurring the handle labels] }
    ListTailRefresh;
    FZrDirty := True;
    inherited Invalidate;
  end;
end;

{ option.selected as the model holds it: what an action wrote, else the
  option's own completed as _resetSelected completes it -- a piece it does
  not name is selected, and 'single' keeps only the first }
function TTyCustomAdvanceChart.VmSelectedMap(AIndex: Integer): TJSONObject;
var
  d, node, x: TJSONData;
  i: Integer;
  single, hasSel: Boolean;
  spec: TTyVisualMapSpec;
begin
  Result := nil;
  if (AIndex <= High(FVmSel)) and (FVmSel[AIndex] <> '') then
  begin
    try
      d := GetJSON(FVmSel[AIndex]);
    except
      d := nil;
    end;
    if d is TJSONObject then Exit(TJSONObject(d));
    d.Free;
  end;
  Result := TJSONObject.Create;
  if (AIndex < 0) or (AIndex > High(FVisualSpecs)) then Exit;
  spec := FVisualSpecs[AIndex];
  node := FOption.ComponentAt('visualMap', AIndex);
  single := False;
  if node is TJSONObject then
  begin
    x := TJSONObject(node).Find('selected');
    if x is TJSONObject then
    begin
      Result.Free;
      Result := TJSONObject(x.Clone);
    end;
    x := TJSONObject(node).Find('selectedMode');
    single := (x <> nil) and (x.JSONType = jtString) and (x.AsString = 'single');
  end;
  for i := 0 to High(spec.Pieces) do
    if Result.Find(spec.Pieces[i].Key) = nil then
      Result.Booleans[spec.Pieces[i].Key] := True;
  if single then
  begin
    hasSel := False;
    for i := 0 to High(spec.Pieces) do
      if JsTruthy(Result.Find(spec.Pieces[i].Key)) then
      begin
        if hasSel then Result.Booleans[spec.Pieces[i].Key] := False
        else hasSel := True;
      end;
  end;
end;

{ _onItemClick: the map cloned, the piece's key set (single: only it), the
  action from the view }
procedure TTyCustomAdvanceChart.VmPieceClick(AIndex, APiece: Integer);
var
  map: TJSONObject;
  key: string;
  i: Integer;
  p: TJSONObject;
  names: TTyStringArray;
begin
  if (AIndex < 0) or (AIndex > High(FVisualViews)) or (AIndex > High(FVisualSpecs)) then Exit;
  if FVisualViews[AIndex].Silent then Exit;
  if (APiece < 0) or (APiece > High(FVisualSpecs[AIndex].Pieces)) then Exit;
  map := VmSelectedMap(AIndex);
  key := FVisualSpecs[AIndex].Pieces[APiece].Key;
  if FVisualViews[AIndex].SelectSingle then
  begin
    map.Booleans[key] := True;
    SetLength(names, map.Count);
    for i := 0 to map.Count - 1 do names[i] := map.Names[i];
    for i := 0 to High(names) do map.Booleans[names[i]] := names[i] = key;
  end
  else
    map.Booleans[key] := not JsTruthy(map.Find(key));
  p := TJSONObject.Create;
  try
    p.Strings['type'] := 'selectDataRange';
    if AIndex <= High(FVmLive) then p.Strings['from'] := FVmLive[AIndex].Uid;
    p.Strings['visualMapId'] := ComponentModelId('visualMap', AIndex);
    p.Objects['selected'] := map;
    DoSelectDataRange(p);
  finally
    p.Free;
  end;
  EmitUpdated;
end;

{ setSelected on one model: a continuous one's range (reversed when
  descending, clamped into the extent -- Math.max / min, a NaN wins), a
  piecewise one's map as given; the view that sent it is not rebuilt }
procedure TTyCustomAdvanceChart.VmSelectRange(AIndex: Integer; const APayloadFrom: string;
  ASel: TJSONData);
var
  r0, r1, t: Double;
  spec: TTyVisualMapSpec;
begin
  if (AIndex < 0) or (AIndex > High(FVisualSpecs)) then Exit;
  VmEnsure(Max(Length(FVmLive), Length(FVisualSpecs)));
  spec := FVisualSpecs[AIndex];
  if spec.SubType = 'continuous' then
  begin
    if not (ASel is TJSONArray) then Exit;
    if TJSONArray(ASel).Count > 0 then r0 := VmJsNum(TJSONArray(ASel).Items[0]) else r0 := NaN;
    if TJSONArray(ASel).Count > 1 then r1 := VmJsNum(TJSONArray(ASel).Items[1]) else r1 := NaN;
    if (not IsNan(r0)) and (not IsNan(r1)) and (r0 > r1) then
    begin
      t := r0;
      r0 := r1;
      r1 := t;
    end;
    FVmRangeHas[AIndex] := True;
    FVmRange0[AIndex] := VmJsMax(r0, spec.Extent0);
    FVmRange1[AIndex] := VmJsMin(r1, spec.Extent1);
    if (APayloadFrom <> '') and (FVmLive[AIndex].Uid = APayloadFrom) then
      FVmLive[AIndex].Keep := True;
  end
  else if spec.SubType = 'piecewise' then
  begin
    if not (ASel is TJSONObject) then Exit;
    FVmSel[AIndex] := ASel.AsJSON;
  end;
end;

{ visualMapAction: every visualMap the query names (visualMapIndex, then
  visualMapId, then visualMapName; none is all) takes `selected`, the chart
  updates, then the event }
procedure TTyCustomAdvanceChart.DoSelectDataRange(APayload: TJSONObject);
var
  d: TJSONData;
  n, k, i: Integer;
  from: string;
  hit: array of Boolean;
  ev: TJSONObject;

  procedure Mark(AData: TJSONData; AKind: Integer);
  var v: string; j: Integer;
  begin
    if AData is TJSONArray then
    begin
      for j := 0 to TJSONArray(AData).Count - 1 do Mark(TJSONArray(AData).Items[j], AKind);
      Exit;
    end;
    if AKind = 0 then
    begin
      if (AData.JSONType = jtNumber) and (Frac(AData.AsFloat) = 0) then
      begin
        j := Trunc(AData.AsFloat);
        if (j >= 0) and (j < n) then hit[j] := True;
      end;
      Exit;
    end;
    if not (AData.JSONType in [jtString, jtNumber]) then Exit;
    v := AData.AsString;
    for j := 0 to n - 1 do
      if (AKind = 1) and (ComponentModelId('visualMap', j) = v) then hit[j] := True
      else if (AKind = 2) and (ComponentModelName('visualMap', j) = v) then hit[j] := True;
  end;

begin
  n := Length(FVisualSpecs);
  SetLength(hit, n);
  for k := 0 to n - 1 do hit[k] := False;
  d := APayload.Find('visualMapIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then Mark(d, 0)
  else
  begin
    d := APayload.Find('visualMapId');
    if (d <> nil) and (d.JSONType <> jtNull) then Mark(d, 1)
    else
    begin
      d := APayload.Find('visualMapName');
      if (d <> nil) and (d.JSONType <> jtNull) then Mark(d, 2)
      else
        for k := 0 to n - 1 do hit[k] := True;
    end;
  end;
  from := '';
  d := APayload.Find('from');
  if (d <> nil) and (d.JSONType = jtString) then from := d.AsString;
  for i := 0 to n - 1 do
    if hit[i] then VmSelectRange(i, from, APayload.Find('selected'));
  { update: 'update' -- the visual encoding again; a view rebuilt unless it
    sent the action }
  FullUpdate;
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := 'datarangeselected';
    EmitPayloadEvent('datarangeselected', VmJsJson(ev));
  finally
    ev.Free;
  end;
end;

{ doDispatchAction's batch: allLeaveBlur once, each item as its own payload
  over the outer one's keys (defaults: where the item has none or null),
  `batch` null; one event: its type, and the items as its batch }
procedure TTyCustomAdvanceChart.DoHighDownBatch(APayload: TJSONObject);
var
  t, nm, js: string;
  arr: TJSONArray;
  evs: TJSONArray;
  item, ev: TJSONObject;
  i, j: Integer;
  x: TJSONData;
begin
  t := APayload.Strings['type'];
  { a batch that is no list maps to no item [Batch 141] }
  if APayload.Find('batch') is TJSONArray then
    arr := TJSONArray(APayload.Find('batch'))
  else
    arr := nil;
  StAllLeaveBlur;
  evs := TJSONArray.Create;
  try
    if arr <> nil then
    for i := 0 to arr.Count - 1 do
    begin
      if not (arr.Items[i] is TJSONObject) then Continue;
      item := TJSONObject(arr.Items[i].Clone);
      try
        for j := 0 to APayload.Count - 1 do
        begin
          nm := APayload.Names[j];
          x := item.Find(nm);
          if (x = nil) or (x.JSONType = jtNull) then
            item.Elements[nm] := APayload.Items[j].Clone;
        end;
        item.Elements['batch'] := TJSONNull.Create;
        DoHighDownAction(item, True);
        ev := TJSONObject(item.Clone);
        ev.Strings['type'] := t;
        evs.Add(ev);
      finally
        item.Free;
      end;
    end;
    if FStDirty then InvalidateFrame;
    { the escapeConnect rides on the event [Batch 141] }
    js := BatchEventHead(APayload, t);
    for i := 0 to evs.Count - 1 do
    begin
      if i > 0 then js := js + ',';
      js := js + VmJsJson(evs.Items[i]);
    end;
    EmitPayloadEvent(t, js + ']}');
  finally
    evs.Free;
  end;
end;

function TTyCustomAdvanceChart.VmLive_: Boolean;
begin
  Result := (FVmAnim <> nil) and (FVmAnim.ClipCount > 0);
end;

function TTyCustomAdvanceChart.VmLiveDraw(AIndex: Integer): TTyVmLiveDraw;
var
  h: Integer;
  c: TTyChartColor;
  v: TTyAnimValue;
  dx, dy: Double;
begin
  Result := Default(TTyVmLiveDraw);
  if not VmContinuous(AIndex) then Exit;
  Result.Has := True;
  for h := 0 to 1 do
  begin
    Result.HandleFill[h] := FVmLive[AIndex].ThumbFill[h];
    Result.Labels[h] := FVmLive[AIndex].Labels[h];
    if FVmLive[AIndex].LabelBlurOn[h] then Result.LabelOpacity[h] := 0.1
    else Result.LabelOpacity[h] := 1;
  end;
  Result.IndVisible := FVmLive[AIndex].IndVisible and (FVmIndBag[AIndex] <> nil);
  if Result.IndVisible then
  begin
    Result.IndX := FVmIndBag[AIndex].Num('x');
    Result.IndY := FVmIndBag[AIndex].Num('y');
    Result.IndSize := FVmLive[AIndex].IndSize;
    v := FVmIndBag[AIndex].GetAnimProp('style.fill');
    if (v.Kind = avkString) and TyTryParseChartColor(v.Str, c) then Result.IndFill := c
    else Result.IndFill := 0;
  end;
  Result.IndLabelVisible := FVmLive[AIndex].IndLabelVisible and (FVmLabBag[AIndex] <> nil);
  if Result.IndLabelVisible then
  begin
    Result.IndLabel := FVmLive[AIndex].IndLabel;
    dx := FVmLabBag[AIndex].Num('style.x') - Result.IndLabel.X;
    dy := FVmLabBag[AIndex].Num('style.y') - Result.IndLabel.Y;
    Result.IndLabel.X := Result.IndLabel.X + dx;
    Result.IndLabel.Y := Result.IndLabel.Y + dy;
    Result.IndLabel.Rect.X := Result.IndLabel.Rect.X + dx;
    Result.IndLabel.Rect.Y := Result.IndLabel.Rect.Y + dy;
  end;
end;

function TTyCustomAdvanceChart.VisualMapLive(AIndex: Integer): TTyVmLive;
var v: TTyAnimValue;
begin
  Result := Default(TTyVmLive);
  if (AIndex < 0) or (AIndex > High(FVmLive)) then Exit;
  Result := FVmLive[AIndex];
  if (AIndex <= High(FVmIndBag)) and (FVmIndBag[AIndex] <> nil) then
  begin
    Result.IndX := FVmIndBag[AIndex].Num('x');
    Result.IndY := FVmIndBag[AIndex].Num('y');
    v := FVmIndBag[AIndex].GetAnimProp('style.fill');
    if v.Kind = avkString then Result.IndFill := v.Str;
  end;
  if (AIndex <= High(FVmLabBag)) and (FVmLabBag[AIndex] <> nil) then
  begin
    Result.IndLabel.X := FVmLabBag[AIndex].Num('style.x');
    Result.IndLabel.Y := FVmLabBag[AIndex].Num('style.y');
  end;
end;

function TTyCustomAdvanceChart.VisualMapRoleAt(AX, AY: Integer): string;
var k, part: Integer;
begin
  Result := '';
  if VmHitAt(AX, AY, k, part) then Result := VmRoleOf(k, part);
end;

function TTyCustomAdvanceChart.VisualMapSelectedText(AIndex: Integer): string;
var m: TJSONObject;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(FVisualSpecs))
    or (FVisualSpecs[AIndex].SubType <> 'piecewise') then Exit;
  m := VmSelectedMap(AIndex);
  try
    Result := VmJsJson(m);
  finally
    m.Free;
  end;
end;

{ a visualMap's part: a continuous one's handle thumb and handle label are
  getCursor(orient) -- ns-resize standing, ew-resize lying; its in-range bar
  the same when calculable and none ('default') otherwise, its out-of-range
  bar none; the end texts and a piecewise one's items keep 'pointer' }
function TTyCustomAdvanceChart.VmCursor(AIndex, APart: Integer): string;
var orient: string;
begin
  Result := 'pointer';
  if (AIndex < 0) or (AIndex > High(FVisualViews)) or (AIndex > High(FVisualLayouts)) then Exit;
  if FVisualLayouts[AIndex].Piecewise then Exit;
  if FVisualViews[AIndex].Horizontal then orient := 'ew-resize' else orient := 'ns-resize';
  if APart = cVmOut then Result := 'default'
  else if APart = cVmIn then
  begin
    if FVisualViews[AIndex].Calculable then Result := orient else Result := 'default';
  end
  else if (APart >= cVmThumb0) and (APart < cVmText0) then Result := orient;
end;
