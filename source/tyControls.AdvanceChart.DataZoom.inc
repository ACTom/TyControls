{ Part of tyControls.AdvanceChart (included, not a unit): the dataZoom components -- their
  solve, views, interaction and actions. Moved out of the unit only to keep it readable;
  what the control is and why it is built the way it is, see the unit header. }

{ A dataZoom target's axis: the grid's x / y, or a polar's radius / angle
  -- the polar whose axis that component is [Batch 113] }
function TTyAdvanceChart.DzAxis(const ADim: string; AIndex: Integer): TTyAxis;
var
  p: Integer;
  ax: TTyAxis;
begin
  Result := nil;
  if (ADim = TyPolarRadiusDim) or (ADim = TyPolarAngleDim) then
  begin
    for p := 0 to High(FPolars) do
    begin
      if FPolars[p] = nil then Continue;
      if ADim = TyPolarRadiusDim then ax := FPolars[p].RadiusAxis
      else ax := FPolars[p].AngleAxis;
      if ax.ComponentIndex = AIndex then Exit(ax);
    end;
    Exit;
  end;
  { a single axis: the component's own [Batch 118] }
  if ADim = TySingleDim then
  begin
    if (AIndex >= 0) and (AIndex <= High(FSingles)) and (FSingles[AIndex] <> nil) then
      Result := FSingles[AIndex].Axis;
    Exit;
  end;
  if FBuild <> nil then Result := FBuild.Axis(ADim + 'Axis', AIndex);
end;

{ setRawRange's window on a dataZoom: both ends as percents, the values
  cleared -- or, from a value action (the toolbox's brush and history),
  both as values, the percents cleared [Batch 125] }
procedure DzApplyRaw(var ASpec: TTyDataZoomSpec; AIsValue: Boolean; A, B: Double);
var k: Integer;
begin
  for k := 0 to 1 do
  begin
    ASpec.Percent[k] := Default(TTyDzArg);
    ASpec.Value[k] := Default(TTyDzArg);
    ASpec.Percent[k].Num := NaN;
    ASpec.Value[k].Num := NaN;
    if AIsValue then
    begin
      ASpec.Value[k].Given := True;
      if k = 0 then ASpec.Value[k].Num := A else ASpec.Value[k].Num := B;
      ASpec.Mode[k] := dzmValue;
    end
    else
    begin
      ASpec.Percent[k].Given := True;
      if k = 0 then ASpec.Percent[k].Num := A else ASpec.Percent[k].Num := B;
      ASpec.Mode[k] := dzmPercent;
    end;
  end;
end;

procedure TTyAdvanceChart.SolveDataZooms;
var
  n, i, t, k, c, si, first: Integer;
  spec: TTyDataZoomSpec;
  ax: TTyAxis;
  z: TTyAxisZoom;
  win: TTyDzWindow;
  any, hosted: Boolean;
  px: Double;
  feeders, cols: TTyIntegerArray;
  ranges: array of TTyDimRange;
  sel: TTyDataZoomSpecArray;
  pass: Integer;
  alignTo: TTyAxis;
  alignWin: Integer;
  use: TTyDataZoomSpec;
begin
  FZoomSpecs := nil;
  FAxisZooms := nil;
  FZoomWindows := nil;
  FZoomHost := nil;
  if FBuild = nil then Exit;
  n := TyDataZoomCount(FOption);
  SetLength(FZoomSpecs, n);
  { setRawRange's windows survive a rebuild; a count that changed drops
    them }
  if Length(FDzRawHas) <> n then
  begin
    SetLength(FDzRawHas, n);
    SetLength(FDzRawStart, n);
    SetLength(FDzRawStop, n);
    for i := 0 to n - 1 do FDzRawHas[i] := False;
  end;
  if Length(FDzRawValue) <> n then
  begin
    SetLength(FDzRawValue, n);
    for i := 0 to n - 1 do FDzRawValue[i] := False;
  end;
  for i := 0 to n - 1 do
  begin
    FZoomSpecs[i] := TyDataZoomSpecOf(FOption, i, FBuild);
    { AN ACTION'S WINDOW: both ends as percents, the values cleared, so
      both ends read in percent mode }
    if FDzRawHas[i] then
      DzApplyRaw(FZoomSpecs[i], FDzRawValue[i], FDzRawStart[i], FDzRawStop[i]);
  end;
  { the toolbox's select dataZooms after the author's -- with the windows
    their actions set [Batch 125] }
  sel := TyDataZoomSelectSpecs(FOption, FBuild, n);
  if Length(sel) > 0 then
  begin
    SetLength(FZoomSpecs, n + Length(sel));
    for i := 0 to High(sel) do
    begin
      FZoomSpecs[n + i] := sel[i];
      if Length(sel[i].Targets) > 0 then
        for k := 0 to High(FTbSel) do
          if FTbSel[k].Key = sel[i].Targets[0].Dim + IntToStr(sel[i].Targets[0].AxisIndex) then
            DzApplyRaw(FZoomSpecs[n + i], FTbSel[k].IsValue, FTbSel[k].A, FTbSel[k].B);
    end;
    n := Length(FZoomSpecs);
  end;
  if n = 0 then Exit;
  { IN COMPONENT ORDER: each dataZoom resets the axes it hosts -- the FIRST
    dataZoom to target an axis owns it; a later one on the same axis shows
    the owner's window and has its own ignored -- then filters them, and the
    next one measures the rows this one left. }
  for i := 0 to n - 1 do
  begin
    spec := FZoomSpecs[i];
    if (spec.SubType = '') or spec.NoTarget then Continue;
    first := Length(FAxisZooms);
    { TWO PASSES: an axis that aligns its ticks to another this dataZoom
      also drives is reset last, from that one's percentInverted window --
      which wins over its own start / end (zrender's defaults keeps the
      target's keys) }
    for pass := 0 to 1 do
    for t := 0 to High(spec.Targets) do
    begin
      ax := DzAxis(spec.Targets[t].Dim, spec.Targets[t].AxisIndex);
      if ax = nil then Continue;
      alignTo := TyAxisAlignTo(FOption, FBuild, ax);
      if (alignTo <> nil) and not TyDzTargets(spec, alignTo.Dim, alignTo.ComponentIndex) then
        alignTo := nil;
      if (alignTo <> nil) <> (pass = 1) then Continue;
      hosted := False;
      for k := 0 to High(FAxisZooms) do
        if FAxisZooms[k].Axis = ax then hosted := True;
      if hosted then Continue;
      use := spec;
      if alignTo <> nil then
      begin
        alignWin := -1;
        for k := 0 to High(FAxisZooms) do
          if FAxisZooms[k].Axis = alignTo then alignWin := k;
        if alignWin >= 0 then
          for k := 0 to 1 do
          begin
            use.Percent[k].Given := True;
            use.Percent[k].IsStr := False;
            use.Percent[k].Num := FZoomWindows[alignWin].PercentInverted[k];
          end;
      end;
      z := Default(TTyAxisZoom);
      z.Axis := ax;
      z.Raw := TyAxisNoZoomExtent(FOption, FBindings, FStores, FStacks, FIndex,
        ax, spec.Targets[t].Dim + 'Axis', any);
      z.Any := any;
      { the axis' pixel span as the grid's own box lays it out, CSS px -- an
        angle axis' extent is degrees, which no PPI scales [Batch 113] }
      px := ax.PxLength;
      if (FLastPPI > 0) and (ax.MainType <> 'angleAxis') then px := px * 96 / FLastPPI;
      win := TyDzCalculateWindow(use, ax, z.Raw.Lo, z.Raw.Hi, px);
      z.ZoomLo := NaN;
      z.ZoomHi := NaN;
      { an end at exactly 0% or 100% is left to nice freely (`!== 0`: a
        not-a-number pins, and pins nothing but a blank) }
      if IsNan(win.Percent[0]) or (win.Percent[0] <> 0) then z.ZoomLo := win.Value[0];
      if IsNan(win.Percent[1]) or (win.Percent[1] <> 100) then z.ZoomHi := win.Value[1];
      k := Length(FAxisZooms);
      SetLength(FAxisZooms, k + 1);
      SetLength(FZoomWindows, k + 1);
      SetLength(FZoomHost, k + 1);
      FAxisZooms[k] := z;
      FZoomWindows[k] := win;
      FZoomHost[k] := i;
    end;
    { then filter what it hosts, with the window's values }
    for k := first to High(FAxisZooms) do
    begin
      if spec.FilterMode = dzfNone then Continue;
      ax := FAxisZooms[k].Axis;
      win := FZoomWindows[k];
      feeders := FIndex.SeriesOnAxis(ax);
      for c := 0 to High(feeders) do
      begin
        si := feeders[c];
        if (si < 0) or (si > High(FStores)) or (FStores[si] = nil) then Continue;
        { a polar's series too [Batch 113], and a single axis' [Batch 118] }
        if (FBindings[si].CoordSysName <> 'cartesian2d')
          and (FBindings[si].Polar = nil) and (FBindings[si].Single = nil) then Continue;
        if si <= High(FStacks) then
          cols := TyAxisDataDims(FStores[si], ax, FBindings[si], FStacks[si])
        else
          cols := TyAxisDataDims(FStores[si], ax, FBindings[si], Default(TTySeriesStack));
        if Length(cols) = 0 then Continue;
        case spec.FilterMode of
          dzfFilter:
            begin
              { dimension by dimension: a row stays when every one is in the
                window or not a number }
              SetLength(ranges, Length(cols));
              for t := 0 to High(cols) do
              begin
                ranges[t].Dim := cols[t];
                ranges[t].Min := win.Value[0];
                ranges[t].Max := win.Value[1];
              end;
              FStores[si].SelectRange(ranges);
            end;
          dzfWeakFilter:
            begin
              FWfStore := FStores[si];
              FWfCols := cols;
              FWfLo := win.Value[0];
              FWfHi := win.Value[1];
              try
                FStores[si].FilterSelf(@WeakKeep);
              finally
                FWfStore := nil;
              end;
            end;
          dzfEmpty:
            { the other axis is NOT resized: only this axis' values go }
            for t := 0 to High(cols) do
              FStores[si].EmptyOutside(cols[t], win.Value[0], win.Value[1]);
        end;
      end;
    end;
  end;
end;

function TTyAdvanceChart.DataZoomInk(const ASpec: TTyDzSliderSpec): TTyDzInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartDataZoom', '', []);
  Result.FontName := st.FontName;
  Result.FontSizeLogical := ResolveFontSize(st);
  Result.FontWeight := st.FontWeight;
  Result.Text := TTyChartColor(st.TextColor);
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    Result.Text, [ttpSize, ttpWeight, ttpFamily]);
  if ASpec.FontSize > 0 then Result.FontSizeLogical := ASpec.FontSize;
  Result.Filler := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomFiller', '', []).Background.Color);
  Result.Frame := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomBorder', '', []).BorderColor);
  Result.Background := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomBackground', '', []).Background.Color);
  st := model.ResolveStyle('TyAdvChartDataZoomHandle', '', []);
  Result.HandleFill := TTyChartColor(st.Background.Color);
  Result.HandleStroke := TTyChartColor(st.BorderColor);
  st := model.ResolveStyle('TyAdvChartDataZoomMoveHandle', '', []);
  Result.MoveHandle := TTyChartColor(st.Background.Color);
  Result.MoveIcon := TTyChartColor(st.TextColor);
  st := model.ResolveStyle('TyAdvChartDataZoomShadow', '', []);
  Result.ShadowArea[0] := TTyChartColor(st.Background.Color);
  Result.ShadowLine[0] := TTyChartColor(st.BorderColor);
  st := model.ResolveStyle('TyAdvChartDataZoomShadowSelected', '', []);
  Result.ShadowArea[1] := TTyChartColor(st.Background.Color);
  Result.ShadowLine[1] := TTyChartColor(st.BorderColor);
  st := model.ResolveStyle('TyAdvChartDataZoomHandle', '', [tysHover]);
  Result.HandleHoverFill := TTyChartColor(st.Background.Color);
  Result.HandleHoverStroke := TTyChartColor(st.BorderColor);
  Result.MoveHandleHover := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomMoveHandle', '', [tysHover]).Background.Color);
  Result.Brush := TTyChartColor(
    model.ResolveStyle('TyAdvChartDataZoomBrush', '', []).Background.Color);
end;

function TTyAdvanceChart.DataZoomInput(AIndex: Integer;
  out AIn: TTyDzSliderInput): Boolean;
var
  spec, hostSpec: TTyDataZoomSpec;
  view: TTyDzSliderSpec;
  scale, v, px: Double;
  t, k, rep, c, slot, thisCol, otherCol, r, g: Integer;
  st: TTyDzSliderState;
  nrWin: TTyDzWindow;
  ax, first, other: TTyAxis;
  feeders, cols: TTyIntegerArray;
  b: TTySeriesBinding;
  store: TTyDataStore;
  otherDim: string;
  grid: TTyGridBuild;
  found: Boolean;
begin
  Result := False;
  AIn := Default(TTyDzSliderInput);
  if (FBuild = nil) or (AIndex > High(FZoomSpecs)) or (AIndex > High(FDzViews)) then Exit;
  spec := FZoomSpecs[AIndex];
  view := FDzViews[AIndex];
  if (spec.SubType <> 'slider') or spec.NoTarget then Exit;
  if FLastPPI > 0 then scale := FLastPPI / 96 else scale := 1;
  AIn.CanvasW := (FLastRect.Right - FLastRect.Left) / scale;
  AIn.CanvasH := (FLastRect.Bottom - FLastRect.Top) / scale;
  { _resetLocation's refContainer: a cell or a day [Batch 154] }
  AIn.HasRef := ComponentRefCss('dataZoom', AIndex, AIn.Ref);
  AIn.Horizontal := spec.Orient <> 'vertical';
  first := nil;
  for t := 0 to High(spec.Targets) do
  begin
    ax := DzAxis(spec.Targets[t].Dim, spec.Targets[t].AxisIndex);
    if ax = nil then Continue;
    first := ax;
    Break;
  end;
  rep := DzRepresentative(AIndex);
  if (first = nil) or (rep < 0) then Exit;
  AIn.Inverse := first.Inverse;
  { a polar axis keeps inverse on its polar; the slider reads the model's
    option (targetAxisModel.get('inverse')) [Batch 113] }
  if (first.MainType = 'radiusAxis') or (first.MainType = 'angleAxis') then
    AIn.Inverse := (FOption.ComponentAt(first.MainType, first.ComponentIndex) is TJSONObject)
      and (TJSONObject(FOption.ComponentAt(first.MainType, first.ComponentIndex)).Find('inverse') <> nil)
      and (TJSONObject(FOption.ComponentAt(first.MainType, first.ComponentIndex)).Find('inverse').JSONType = jtBoolean)
      and TJSONObject(FOption.ComponentAt(first.MainType, first.ComponentIndex)).Booleans['inverse'];
  { a single axis' rect: its getRect [Batch 118] }
  if (first.MainType = TySingleCoordSysName) and (first.ComponentIndex <= High(FSingles))
    and (FSingles[first.ComponentIndex] <> nil) then
  begin
    AIn.HasCoordRect := True;
    AIn.CoordRect.X := (FSingles[first.ComponentIndex].Rect.X - FLastRect.Left) / scale;
    AIn.CoordRect.Y := (FSingles[first.ComponentIndex].Rect.Y - FLastRect.Top) / scale;
    AIn.CoordRect.W := FSingles[first.ComponentIndex].Rect.W / scale;
    AIn.CoordRect.H := FSingles[first.ComponentIndex].Rect.H / scale;
  end;
  { the first target's grid, as the labels left it }
  for g := 0 to FBuild.GridCount - 1 do
  begin
    grid := FBuild.Grid(g);
    if grid.ComponentIndex = first.GridIndex then
    begin
      AIn.HasCoordRect := True;
      AIn.CoordRect.X := (grid.PlotXYWH.X - FBuild.Viewport.Left) / scale;
      AIn.CoordRect.Y := (grid.PlotXYWH.Y - FBuild.Viewport.Top) / scale;
      AIn.CoordRect.W := grid.PlotXYWH.W / scale;
      AIn.CoordRect.H := grid.PlotXYWH.H / scale;
      Break;
    end;
  end;
  for k := 0 to 1 do
  begin
    AIn.Percent[k] := FZoomWindows[rep].Percent[k];
    AIn.Value[k] := FZoomWindows[rep].Value[k];
  end;
  AIn.ValuePrecision := FZoomWindows[rep].Precision;
  ax := FAxisZooms[rep].Axis;
  { THE VIEW'S OWN STATE }
  if AIndex <= High(FDzState) then
  begin
    st := FDzState[AIndex];
    if st.Built then
    begin
      AIn.HasEnds := True;
      for k := 0 to 1 do
      begin
        AIn.Ends[k] := st.Ends[k];
        AIn.ViewRange[k] := st.Range[k];
      end;
    end;
    AIn.HasLabelState := True;
    AIn.LabelsShown := st.LabelsShown;
    AIn.HandleHover[0] := st.HandleHover[0];
    AIn.HandleHover[1] := st.HandleHover[1];
    AIn.MoveHover := st.MoveBits <> 0;
    AIn.HasBrush := st.HasBrush and not st.BrushIgnored;
    AIn.BrushX := st.BrushX;
    AIn.BrushW := st.BrushW;
    { _updateView(nonRealtime): the labels say the window the view's range
      WOULD give, worked out with the host's range modes }
    if st.NonRealtime and st.Built and (FZoomHost[rep] >= 0)
      and (FZoomHost[rep] <= High(FZoomSpecs)) then
    begin
      { calculateDataWindow({start, end}): no startValue / endValue, so an
        end the host reads in value mode falls back to the data's end }
      hostSpec := FZoomSpecs[FZoomHost[rep]];
      for k := 0 to 1 do
      begin
        hostSpec.Percent[k] := Default(TTyDzArg);
        hostSpec.Percent[k].Given := True;
        hostSpec.Percent[k].Num := st.Range[k];
        hostSpec.Value[k] := Default(TTyDzArg);
        hostSpec.Value[k].Num := NaN;
      end;
      px := ax.PxLength;
      if FLastPPI > 0 then px := px * 96 / FLastPPI;
      nrWin := TyDzCalculateWindow(hostSpec, ax, FAxisZooms[rep].Raw.Lo,
        FAxisZooms[rep].Raw.Hi, px);
      AIn.Value[0] := nrWin.Value[0];
      AIn.Value[1] := nrWin.Value[1];
      AIn.ValuePrecision := nrWin.Precision;
    end;
  end;
  { a category or time axis says its ends in the scale's own words }
  if ax.AxisType = atCategory then
  begin
    AIn.LabelIsScale := True;
    for k := 0 to 1 do
    begin
      v := AIn.Value[k];
      if IsNan(v) then Continue;
      v := TyJsRound(v);
      if (v >= 0) and (v < ax.Categories.Count) then
        AIn.ScaleLabel[k] := ax.Categories.CategoryAt(Trunc(v));
    end;
  end
  else if (ax.AxisType = atTime) and (ax.Scale is TTyTimeScale) then
  begin
    AIn.LabelIsScale := True;
    for k := 0 to 1 do
      if not IsNan(AIn.Value[k]) then
        AIn.ScaleLabel[k] := TTyTimeScale(ax.Scale).GetLabel(TyJsRound(AIn.Value[k]));
  end;
  { THE DATA SHADOW: the first series on a target axis that can cast one --
    a line, bar, candlestick or scatter, or any when showDataShadow is true
    -- read RAW, before any dataZoom filtered or emptied it }
  if view.ShowShadow = 0 then Exit(True);
  found := False;
  for t := 0 to High(spec.Targets) do
  begin
    if found then Break;
    ax := DzAxis(spec.Targets[t].Dim, spec.Targets[t].AxisIndex);
    if ax = nil then Continue;
    feeders := FIndex.SeriesOnAxis(ax);
    for c := 0 to High(feeders) do
    begin
      slot := feeders[c];
      if (slot < 0) or (slot > High(FBindings)) or (slot > High(FStores)) then Continue;
      b := FBindings[slot];
      if (view.ShowShadow <> 1) and (b.SeriesType <> 'line') and (b.SeriesType <> 'bar')
        and (b.SeriesType <> 'candlestick') and (b.SeriesType <> 'scatter') then Continue;
      found := True;
      if ax.Dim = 'x' then otherDim := 'y'
      else if ax.Dim = 'y' then otherDim := 'x'
      else otherDim := '';
      other := nil;
      if otherDim <> '' then
        if ax = b.XAxis then other := b.YAxis else other := b.XAxis;
      AIn.OtherAxisInverse := (other <> nil) and other.Inverse;
      store := FStores[slot];
      if store = nil then Break;
      cols := store.DimsOfCoord(ax.Dim);
      if Length(cols) > 0 then thisCol := cols[0] else thisCol := -1;
      otherCol := -1;
      { a candlestick's shadow is its open }
      if b.SeriesType = 'candlestick' then otherCol := store.DimIndexOf('open');
      if (otherCol < 0) and (otherDim <> '') then
      begin
        cols := store.DimsOfCoord(otherDim);
        if Length(cols) > 0 then otherCol := cols[0];
      end;
      if otherCol < 0 then Break;
      AIn.HasShadow := True;
      AIn.IsTime := ax.AxisType = atTime;
      SetLength(AIn.ThisVals, store.RawCount);
      SetLength(AIn.OtherVals, store.RawCount);
      for r := 0 to store.RawCount - 1 do
      begin
        if thisCol >= 0 then AIn.ThisVals[r] := store.GetOriginalByRaw(thisCol, r)
        else AIn.ThisVals[r] := r;
        AIn.OtherVals[r] := store.GetOriginalByRaw(otherCol, r);
      end;
      Break;
    end;
  end;
  Result := True;
end;

procedure TTyAdvanceChart.SolveDataZoomViews(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  n, k: Integer;
  inp: TTyDzSliderInput;
begin
  n := TyDataZoomCount(FOption);
  SetLength(FDzViews, n);
  SetLength(FDzLayouts, n);
  for k := 0 to n - 1 do
  begin
    FDzLayouts[k] := Default(TTyDzSliderLayout);
    FDzViews[k] := TyDzSliderSpecOf(FOption, k);
  end;
  for k := 0 to n - 1 do
    if DataZoomInput(k, inp) then
    begin
      FDzLayouts[k] := TyLayoutDzSlider(FDzViews[k], inp, AMeasurer,
        DataZoomInk(FDzViews[k]));
      { _resetInterval, once: the view keeps these until it is rebuilt }
      if (k <= High(FDzState)) and FDzLayouts[k].Valid and not FDzState[k].Built then
      begin
        FDzState[k].Built := True;
        FDzState[k].Ends[0] := FDzLayouts[k].HandleEnds[0];
        FDzState[k].Ends[1] := FDzLayouts[k].HandleEnds[1];
        FDzState[k].Range[0] := FDzLayouts[k].Range[0];
        FDzState[k].Range[1] := FDzLayouts[k].Range[1];
      end;
    end;
end;

function TTyAdvanceChart.BuildDataZooms(AList: TTyPaintList): Integer;
var
  k: Integer;
  scale: Double;
begin
  Result := 0;
  if FLastPPI > 0 then scale := FLastPPI / 96 else scale := 1;
  for k := 0 to High(FDzLayouts) do
    if (k <= High(FDzViews)) and FDzLayouts[k].Valid then
      Inc(Result, TyBuildDzSliderMarks(FDzLayouts[k], FDzViews[k],
        DataZoomInk(FDzViews[k]), FLastRect.Left, FLastRect.Top, scale, AList));
end;

{ ==================== dataZoom interaction ==================== }

{ findRepresentativeAxisProxy: the first target this dataZoom hosts, else
  the first target at all -- as an index into the hosted axes }
function TTyAdvanceChart.DzRepresentative(AIndex: Integer): Integer;
var
  spec: TTyDataZoomSpec;
  t, k, firstRec: Integer;
  ax: TTyAxis;
begin
  Result := -1;
  if (FBuild = nil) or (AIndex < 0) or (AIndex > High(FZoomSpecs)) then Exit;
  spec := FZoomSpecs[AIndex];
  firstRec := -1;
  for t := 0 to High(spec.Targets) do
  begin
    ax := DzAxis(spec.Targets[t].Dim, spec.Targets[t].AxisIndex);
    if ax = nil then Continue;
    for k := 0 to High(FAxisZooms) do
      if FAxisZooms[k].Axis = ax then
      begin
        if (Result < 0) and (FZoomHost[k] = AIndex) then Result := k;
        if firstRec < 0 then firstRec := k;
      end;
  end;
  if Result < 0 then Result := firstRec;
end;

{ Every view rendered: a slider not the source of this action is rebuilt --
  its ends from the window again, the brush gone, the labels back to
  handleLabel.show, no emphasis; the drag and the pointer's place survive --
  and every inside takes its range from the window. }
procedure TTyAdvanceChart.DzRenderStates;
var
  n, i, rep: Integer;
  keepDrag, keepOver: Boolean;
  keepThrottle: TTyDzThrottle;
  keepPending: Boolean;
begin
  n := TyDataZoomCount(FOption);
  if Length(FDzState) <> n then SetLength(FDzState, n);
  SetLength(FDzInteract, n);
  SetLength(FDzInLo, n);
  SetLength(FDzInHi, n);
  for i := 0 to n - 1 do
  begin
    FDzInteract[i] := TyDzInteractSpecOf(FOption, i);
    if i <> FDzFrom then
    begin
      keepDrag := FDzState[i].Dragging;
      keepOver := FDzState[i].OverArea;
      keepThrottle := FDzState[i].Throttle;
      keepPending := FDzState[i].PendingRealtime;
      FDzState[i] := Default(TTyDzSliderState);
      FDzState[i].Dragging := keepDrag;
      FDzState[i].OverArea := keepOver;
      FDzState[i].Throttle := keepThrottle;
      FDzState[i].PendingRealtime := keepPending;
      FDzState[i].LabelsShown := TyDzSliderSpecOf(FOption, i).LabelShow;
    end;
    FDzInLo[i] := NaN;
    FDzInHi[i] := NaN;
    rep := DzRepresentative(i);
    if rep >= 0 then
    begin
      FDzInLo[i] := FZoomWindows[rep].Percent[0];
      FDzInHi[i] := FZoomWindows[rep].Percent[1];
    end;
  end;
  if (FBuild <> nil) and (Length(FDzRoamThrottle) <> FBuild.GridCount) then
  begin
    SetLength(FDzRoamThrottle, FBuild.GridCount);
    SetLength(FDzRoamBatch, FBuild.GridCount);
  end;
end;

function TTyAdvanceChart.DzScale: Double;
begin
  if FLastPPI > 0 then Result := FLastPPI / 96 else Result := 1;
end;

function TTyAdvanceChart.DzClock: Double;
begin
  if IsNan(FDzNow) then Result := GetTickCount64 else Result := FDzNow;
end;

function TTyAdvanceChart.DzGridRect(AGrid: Integer): TTyXYWH;
var g: TTyGridBuild; s: Double;
begin
  g := FBuild.Grid(AGrid);
  s := DzScale;
  Result.X := (g.PlotXYWH.X - FBuild.Viewport.Left) / s;
  Result.Y := (g.PlotXYWH.Y - FBuild.Viewport.Top) / s;
  Result.W := g.PlotXYWH.W / s;
  Result.H := g.PlotXYWH.H / s;
end;

{ Cartesian2D.containPoint: each axis' closed extent, the y one measured
  from the bottom }
function TTyAdvanceChart.DzGridContains(AGrid: Integer; AX, AY: Double): Boolean;
var r: TTyXYWH; lx, ly: Double;
begin
  r := DzGridRect(AGrid);
  lx := AX - r.X;
  ly := r.H - AY + r.Y;
  Result := (lx >= 0) and (lx <= r.W) and (ly >= 0) and (ly <= r.H);
end;

{ the inside dataZooms with an axis on this grid, in component order }
function TTyAdvanceChart.DzGridInsides(AGrid: Integer): TTyIntegerArray;
var
  i, t: Integer;
  ax: TTyAxis;
  gi: Integer;
begin
  Result := nil;
  if (FBuild = nil) or (AGrid < 0) or (AGrid >= FBuild.GridCount) then Exit;
  gi := FBuild.Grid(AGrid).ComponentIndex;
  for i := 0 to Min(High(FZoomSpecs), High(FDzInteract)) do
  begin
    if (FZoomSpecs[i].SubType <> 'inside') or FZoomSpecs[i].NoTarget then Continue;
    for t := 0 to High(FZoomSpecs[i].Targets) do
    begin
      ax := DzAxis(FZoomSpecs[i].Targets[t].Dim, FZoomSpecs[i].Targets[t].AxisIndex);
      if (ax <> nil) and (ax.GridIndex = gi) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := i;
        Break;
      end;
    end;
  end;
end;

{ mergeControllerParams: the strongest of the insides -- 2 zooms and moves,
  1 moves only (zoomLock), 0 disabled -- or -1 for no controller }
function TTyAdvanceChart.DzControlType(AGrid: Integer): Integer;
var ins: TTyIntegerArray; k, v: Integer;
begin
  Result := -1;
  ins := DzGridInsides(AGrid);
  for k := 0 to High(ins) do
  begin
    if FDzInteract[ins[k]].Disabled then v := 0
    else if FDzInteract[ins[k]].ZoomLock then v := 1
    else v := 2;
    if v > Result then Result := v;
  end;
end;

{ a point on the canvas (CSS px) into the slider group's own coordinates:
  transformCoordToLocal, the inverse of its global matrix }
procedure TTyAdvanceChart.DzToSlider(ASlider: Integer; AX, AY: Double;
  out LX, LY: Double);
var
  L: TTyDzSliderLayout;
  G, inv: TTyMat2D;
begin
  L := FDzLayouts[ASlider];
  G := TyMatMul(TyZrLocal(1, 1, 0, L.GroupX, L.GroupY), TyMatMul(L.SG, TyMatIdentity));
  if not TyMatInvert(G, inv) then
  begin
    LX := NaN;
    LY := NaN;
    Exit;
  end;
  LX := inv[0] * AX + inv[2] * AY + inv[4];
  LY := inv[1] * AX + inv[3] * AY + inv[5];
end;

function TTyAdvanceChart.DzHits(ASlider: Integer; ARole: TTyDzRole; AX, AY: Double): Boolean;
var
  L: TTyDzSliderLayout;
  e: TTyDzElement;
  M, inv: TTyMat2D;
  lx, ly, lw: Double;
  r: TTyXYWH;
begin
  Result := False;
  L := FDzLayouts[ASlider];
  e := L.Kids[ARole];
  if not e.Present then Exit;
  M := TyDzGlobal(L, ARole);
  if not TyMatInvert(M, inv) then Exit;
  lx := inv[0] * AX + inv[2] * AY + inv[4];
  ly := inv[1] * AX + inv[3] * AY + inv[5];
  if ARole in [dzrHandle0, dzrHandle1] then
  begin
    { rectHover: the bounding rect, the stroke grown by strokeNoScale's line
      scale -- the handle's own now it has a global transform }
    if IsNan(FDzViews[ASlider].Handle.LineWidth) then lw := 1
    else lw := FDzViews[ASlider].Handle.LineWidth;
    r := TyZrStrokeRect(e.PathRect, e.DataLen, True, True, lw,
      Sqrt(Abs(M[0] * M[3] - M[2] * M[1])));
  end
  else
    r := e.Shape;
  Result := (lx >= r.X) and (lx <= r.X + r.W) and (ly >= r.Y) and (ly <= r.Y + r.H);
end;

{ findHover over the sliders' non-silent elements, topmost first: the
  handles (a hovered one raised above the other), the move zone, the filler
  when it is the move zone, the click panel; then any other element of the
  chart }
function TTyAdvanceChart.DzFindTarget(AX, AY: Double): TTyDzTarget;
var
  res: TTyDzTarget;
  i, el: Integer;
  st: TTyDzSliderState;
  order: array[0..1] of TTyDzRole;
  k: Integer;
  d: TTyChartDatumRef;
  s: Double;

  function Hit(ARole: TTyDzRole): Boolean;
  begin
    Result := DzHits(i, ARole, AX, AY);
    if Result then
    begin
      res.Kind := dtkSlider;
      res.Slider := i;
      res.Role := ARole;
    end;
  end;

begin
  Result := Default(TTyDzTarget);
  res := Default(TTyDzTarget);
  s := DzScale;
  if (AX < 0) or (AY < 0) or (AX > (FLastRect.Right - FLastRect.Left) / s)
    or (AY > (FLastRect.Bottom - FLastRect.Top) / s) then Exit;
  for i := High(FDzLayouts) downto 0 do
  begin
    if not FDzLayouts[i].Valid then Continue;
    if i <= High(FDzState) then st := FDzState[i] else st := Default(TTyDzSliderState);
    if st.HandleHover[0] and not st.HandleHover[1] then
    begin
      order[0] := dzrHandle0;
      order[1] := dzrHandle1;
    end
    else
    begin
      order[0] := dzrHandle1;
      order[1] := dzrHandle0;
    end;
    for k := 0 to 1 do
      if Hit(order[k]) then Exit(res);
  end;
  for i := High(FDzLayouts) downto 0 do
  begin
    if not FDzLayouts[i].Valid then Continue;
    if FDzViews[i].BrushSelect then
    begin
      if Hit(dzrMoveZone) then Exit(res);
    end
    else if Hit(dzrFiller) then Exit(res);
    if Hit(dzrClickPanel) then Exit(res);
  end;
  d := HitTestAt(Round(AX * s + FLastRect.Left), Round(AY * s + FLastRect.Top), el);
  { a line's own path is no dataZoom 'other' (triggerLineEvent false): only
    its symbols are -- [F6a] nor is its area, hoverable since }
  if TyChartDatumValid(d) and not ((FPaintList <> nil) and (el >= 0)
    and (el < FPaintList.Count) and ((FPaintList.Element(el).Shape.Kind = cskPolyline)
      or (FPaintList.Element(el).Anim.Role = carLineArea))) then
    Result.Kind := dtkOther;
end;

function SameDzTarget(const A, B: TTyDzTarget): Boolean;
begin
  Result := (A.Kind = B.Kind) and ((A.Kind <> dtkSlider)
    or ((A.Slider = B.Slider) and (A.Role = B.Role)));
end;

{ the axis proxy's spans: the HOST dataZoom's options, in percent }
function TTyAdvanceChart.DzSpans(AIndex: Integer; out AMin, AMax: Double): Boolean;
var
  rep, host: Integer;
  sp: TTyDzSpans;
begin
  AMin := NaN;
  AMax := NaN;
  rep := DzRepresentative(AIndex);
  Result := rep >= 0;
  if not Result then Exit;
  host := FZoomHost[rep];
  if (host < 0) or (host > High(FZoomSpecs)) then Exit;
  sp := TyDzSpansOf(FZoomSpecs[host], FAxisZooms[rep].Axis, FAxisZooms[rep].Raw.Lo,
    FAxisZooms[rep].Raw.Hi);
  AMin := sp.MinSpan;
  AMax := sp.MaxSpan;
end;

{ _showDataInfo: on a hover or while dragging the emphasis label setting,
  else the normal one; the move bar is highlighted with them }
procedure TTyAdvanceChart.DzShowDataInfo(AIndex: Integer; AEmphasis: Boolean);
var toShow: Boolean;
begin
  if AEmphasis or FDzState[AIndex].Dragging then
    toShow := FDzInteract[AIndex].EmphasisLabelShow
  else
    toShow := FDzViews[AIndex].LabelShow;
  FDzState[AIndex].LabelsShown := toShow;
  if FDzViews[AIndex].BrushSelect then
    if toShow then FDzState[AIndex].MoveBits := FDzState[AIndex].MoveBits or 2
    else FDzState[AIndex].MoveBits := FDzState[AIndex].MoveBits and not 2;
end;

procedure TTyAdvanceChart.DzMouseOut(const ATarget: TTyDzTarget);
var i: Integer;
begin
  if ATarget.Kind <> dtkSlider then Exit;
  i := ATarget.Slider;
  if i > High(FDzState) then Exit;
  case ATarget.Role of
    dzrHandle0, dzrHandle1:
      begin
        FDzState[i].OverArea := False;
        DzShowDataInfo(i, False);
        FDzState[i].HandleHover[Ord(ATarget.Role) - Ord(dzrHandle0)] := False;
      end;
    dzrMoveZone, dzrFiller:
      begin
        FDzState[i].OverArea := False;
        DzShowDataInfo(i, False);
        if ATarget.Role = dzrMoveZone then
          FDzState[i].MoveBits := FDzState[i].MoveBits and not 1;
      end;
  end;
end;

procedure TTyAdvanceChart.DzMouseOver(const ATarget: TTyDzTarget);
var i: Integer;
begin
  if ATarget.Kind <> dtkSlider then Exit;
  i := ATarget.Slider;
  if i > High(FDzState) then Exit;
  case ATarget.Role of
    dzrHandle0, dzrHandle1:
      begin
        FDzState[i].OverArea := True;
        DzShowDataInfo(i, True);
        FDzState[i].HandleHover[Ord(ATarget.Role) - Ord(dzrHandle0)] := True;
      end;
    dzrMoveZone, dzrFiller:
      begin
        FDzState[i].OverArea := True;
        DzShowDataInfo(i, True);
        if ATarget.Role = dzrMoveZone then
          FDzState[i].MoveBits := FDzState[i].MoveBits or 1;
      end;
  end;
end;

{ _onDragMove: the screen delta through the INVERSE of the slider group's
  local matrix, then _updateInterval; realtime dispatches }
procedure TTyAdvanceChart.DzDragMove(AIndex, AHandle: Integer; ADX, ADY: Double);
var
  inv: TTyMat2D;
  v, mn, mx: Double;
  moved: Boolean;
begin
  FDzState[AIndex].Dragging := True;
  if not TyMatInvert(FDzLayouts[AIndex].SG, inv) then Exit;
  v := inv[0] * ADX + inv[2] * ADY + inv[4];
  DzSpans(AIndex, mn, mx);
  if FDzInteract[AIndex].ZoomLock then AHandle := -1;
  moved := TyDzUpdateInterval(FDzState[AIndex].Ends, FDzLayouts[AIndex].L, v,
    AHandle, mn, mx, FDzState[AIndex].Range, True);
  FDzState[AIndex].NonRealtime := not FDzInteract[AIndex].Realtime;
  if moved and FDzInteract[AIndex].Realtime then DzSliderDispatch(AIndex, True);
end;

{ _onDragEnd }
procedure TTyAdvanceChart.DzDragEnd(AIndex: Integer);
begin
  FDzState[AIndex].Dragging := False;
  if not FDzState[AIndex].OverArea then DzShowDataInfo(AIndex, False);
  if not FDzInteract[AIndex].Realtime then DzSliderDispatch(AIndex, False);
end;

{ _onClickPanel: the window's centre to the click, keeping the span }
procedure TTyAdvanceChart.DzClickPanel(AIndex: Integer; AX, AY: Double);
var
  lx, ly, centre, mn, mx: Double;
  moved: Boolean;
begin
  DzToSlider(AIndex, AX, AY, lx, ly);
  if (lx < 0) or (lx > FDzLayouts[AIndex].L) or (ly < 0) or (ly > FDzLayouts[AIndex].T) then Exit;
  centre := (FDzState[AIndex].Ends[0] + FDzState[AIndex].Ends[1]) / 2;
  DzSpans(AIndex, mn, mx);
  moved := TyDzUpdateInterval(FDzState[AIndex].Ends, FDzLayouts[AIndex].L,
    lx - centre, -1, mn, mx, FDzState[AIndex].Range, True);
  FDzState[AIndex].NonRealtime := False;
  if moved then DzSliderDispatch(AIndex, False);
end;

{ _updateBrushRect }
procedure TTyAdvanceChart.DzBrushMove(AIndex: Integer; AX, AY: Double);
var ex, ey, sx, sy: Double;
begin
  FDzState[AIndex].HasBrush := True;
  FDzState[AIndex].BrushIgnored := False;
  DzToSlider(AIndex, AX, AY, ex, ey);
  DzToSlider(AIndex, FDzState[AIndex].BrushStartX, FDzState[AIndex].BrushStartY, sx, sy);
  { max(min(size, x), 0) on the double: Math.Max of a double and an
    integer literal takes the Single overload }
  if ex > FDzLayouts[AIndex].L then ex := FDzLayouts[AIndex].L;
  if ex < 0 then ex := 0;
  FDzState[AIndex].BrushX := sx;
  FDzState[AIndex].BrushW := ex - sx;
end;

{ _onBrushEnd: a short quick brush is a click; else the brush is the new
  window -- from the LAST brush rect, which a new press never cleared }
procedure TTyAdvanceChart.DzBrushEnd(AIndex: Integer);
var
  mn, mx, mnPx, mxPx, L: Double;
begin
  if not FDzState[AIndex].Brushing then Exit;
  FDzState[AIndex].Brushing := False;
  if not FDzState[AIndex].HasBrush then Exit;
  FDzState[AIndex].BrushIgnored := True;
  if (DzClock - FDzState[AIndex].BrushStartTime < 200)
    and (Abs(FDzState[AIndex].BrushW) < 5) then Exit;
  L := FDzLayouts[AIndex].L;
  FDzState[AIndex].Ends[0] := FDzState[AIndex].BrushX;
  FDzState[AIndex].Ends[1] := FDzState[AIndex].BrushX + FDzState[AIndex].BrushW;
  DzSpans(AIndex, mn, mx);
  mnPx := NaN;
  mxPx := NaN;
  if not IsNan(mn) then mnPx := TyDzLinearMap(mn, 0, 100, 0, L, True);
  if not IsNan(mx) then mxPx := TyDzLinearMap(mx, 0, 100, 0, L, True);
  TyDzSliderMove(0, FDzState[AIndex].Ends, 0, L, 0, mnPx, mxPx);
  TyDzRangeOfEnds(FDzState[AIndex].Ends, L, FDzState[AIndex].Range[0],
    FDzState[AIndex].Range[1]);
  FDzState[AIndex].NonRealtime := False;
  DzSliderDispatch(AIndex, False);
end;

{ _dispatchZoomAction, through the view's throttle }
procedure TTyAdvanceChart.DzSliderDispatch(AIndex: Integer; ARealtime: Boolean);
begin
  if TyDzThrottleCall(FDzState[AIndex].Throttle, DzClock, FDzInteract[AIndex].Throttle) then
    DzRunSliderAction(AIndex, False, ARealtime)
  else
  begin
    FDzState[AIndex].PendingRealtime := ARealtime;
    DzArmTimer;
  end;
end;

procedure TTyAdvanceChart.DzRunSliderAction(AIndex: Integer; ADeferred, ARealtime: Boolean);
var a: TTyDzAction;
begin
  a := Default(TTyDzAction);
  a.Deferred := ADeferred;
  a.Realtime := ARealtime;
  a.FromSlider := AIndex;
  SetLength(a.Items, 1);
  a.Items[0].DataZoomIndex := AIndex;
  { the range as it is when the call runs }
  a.Items[0].Start := FDzState[AIndex].Range[0];
  a.Items[0].Stop := FDzState[AIndex].Range[1];
  DzDispatch(a);
end;

{ One roam event on a grid: every inside of it that the behaviour allows
  works out its range from its own view range; the ones not disabled that
  moved go in the batch. AKind 'zoom', 'pan' or 'scrollMove'. }
function TTyAdvanceChart.DzRoam(AGrid: Integer; const AKind: string;
  AShift: TShiftState; AOldX, AOldY, ANewX, ANewY, AScale, AScroll: Double): Boolean;
var
  ins: TTyIntegerArray;
  k, d, t: Integer;
  setting: string;
  ax, axis: TTyAxis;
  dir: TTyDzDirection;
  r: array[0..1] of Double;
  mn, mx: Double;
  moved: Boolean;
  items: TTyDzActionItemArray;
begin
  Result := False;
  items := nil;
  ins := DzGridInsides(AGrid);
  for k := 0 to High(ins) do
  begin
    d := ins[k];
    if AKind = 'zoom' then setting := FDzInteract[d].ZoomOnMouseWheel
    else if AKind = 'pan' then setting := FDzInteract[d].MoveOnMouseMove
    else setting := FDzInteract[d].MoveOnMouseWheel;
    if not TyDzBehaviour(setting, ssShift in AShift, ssCtrl in AShift,
      ssAlt in AShift, ssMeta in AShift) then Continue;
    { the dataZoom's first target axis on this grid }
    axis := nil;
    for t := 0 to High(FZoomSpecs[d].Targets) do
    begin
      ax := DzAxis(FZoomSpecs[d].Targets[t].Dim, FZoomSpecs[d].Targets[t].AxisIndex);
      if (ax <> nil) and (ax.GridIndex = FBuild.Grid(AGrid).ComponentIndex) then
      begin
        axis := ax;
        Break;
      end;
    end;
    if axis = nil then Continue;
    r[0] := FDzInLo[d];
    r[1] := FDzInHi[d];
    if AKind = 'zoom' then
    begin
      dir := TyDzDirectionInfo(axis.Dim = 'x', axis.Inverse, DzGridRect(AGrid),
        0, 0, ANewX, ANewY);
      DzSpans(d, mn, mx);
      moved := TyDzInsideZoom(r, dir, AScale, mn, mx);
    end
    else
    begin
      dir := TyDzDirectionInfo(axis.Dim = 'x', axis.Inverse, DzGridRect(AGrid),
        AOldX, AOldY, ANewX, ANewY);
      if AKind = 'pan' then moved := TyDzInsideMove(r, TyDzPanDelta(r, dir))
      else moved := TyDzInsideMove(r, TyDzScrollMoveDelta(r, dir, AScroll));
    end;
    FDzInLo[d] := r[0];
    FDzInHi[d] := r[1];
    if moved and not FDzInteract[d].Disabled then
    begin
      SetLength(items, Length(items) + 1);
      items[High(items)].DataZoomIndex := d;
      items[High(items)].Start := r[0];
      items[High(items)].Stop := r[1];
    end;
  end;
  if Length(items) > 0 then
  begin
    DzRoamDispatch(AGrid, items);
    Result := True;
  end;
end;

{ the roam's dispatch, through the grid's throttle at the first inside's
  rate; a deferred one sends the latest batch }
procedure TTyAdvanceChart.DzRoamDispatch(AGrid: Integer; const AItems: TTyDzActionItemArray);
var
  ins: TTyIntegerArray;
  rate: Double;
  a: TTyDzAction;
begin
  ins := DzGridInsides(AGrid);
  rate := 100;
  if Length(ins) > 0 then rate := FDzInteract[ins[0]].Throttle;
  FDzRoamBatch[AGrid] := AItems;
  if TyDzThrottleCall(FDzRoamThrottle[AGrid], DzClock, rate) then
  begin
    a := Default(TTyDzAction);
    a.Batch := True;
    a.FromSlider := -1;
    a.Items := AItems;
    DzDispatch(a);
  end
  else
    DzArmTimer;
end;

{ THE ACTION: setRawRange on the named dataZooms and every one linked to
  them through a shared axis, then one update, the views rendered with the
  payload -- the source slider keeps its view }
procedure TTyAdvanceChart.DzDispatch(const AAction: TTyDzAction; AJson: TJSONObject);
var
  savedAction: string;
  n, it, i, j, t, u: Integer;
  pay: TTyAnimOverride;
  hasPay: Boolean;
  found: array of Boolean;
  keys: array of string;
  more, linked: Boolean;
  built, items: TJSONData;
  an, x: TJSONData;
  evJson: string;
  own: Boolean;

  procedure Mark(AIdx: Integer);
  var tt: Integer;
  begin
    found[AIdx] := True;
    for tt := 0 to High(FZoomSpecs[AIdx].Targets) do
    begin
      SetLength(keys, Length(keys) + 1);
      keys[High(keys)] := FZoomSpecs[AIdx].Targets[tt].Dim
        + IntToStr(FZoomSpecs[AIdx].Targets[tt].AxisIndex);
    end;
  end;

begin
  { the author's dataZooms and, after them, the toolbox's select ones
    [Batch 125] }
  n := Length(FZoomSpecs);
  for it := 0 to High(AAction.Items) do
  begin
    i := AAction.Items[it].DataZoomIndex;
    if (i < 0) or (i >= n) then Continue;
    { findEffectedDataZooms }
    SetLength(found, n);
    for j := 0 to n - 1 do found[j] := False;
    keys := nil;
    Mark(i);
    repeat
      more := False;
      for j := 0 to n - 1 do
      begin
        if found[j] then Continue;
        linked := False;
        for t := 0 to High(FZoomSpecs[j].Targets) do
          for u := 0 to High(keys) do
            if keys[u] = FZoomSpecs[j].Targets[t].Dim
              + IntToStr(FZoomSpecs[j].Targets[t].AxisIndex) then linked := True;
        if linked then
        begin
          Mark(j);
          more := True;
        end;
      end;
    until not more;
    for j := 0 to n - 1 do
      if found[j] then
      begin
        if j <= High(FDzRawHas) then
        begin
          FDzRawHas[j] := True;
          FDzRawStart[j] := AAction.Items[it].Start;
          FDzRawStop[j] := AAction.Items[it].Stop;
          if j <= High(FDzRawValue) then FDzRawValue[j] := AAction.Items[it].IsValue;
        end
        else if (FZoomSpecs[j].SubType = 'select') and (Length(FZoomSpecs[j].Targets) > 0) then
          TbSelPut(FZoomSpecs[j].Targets[0].Dim + IntToStr(FZoomSpecs[j].Targets[0].AxisIndex),
            AAction.Items[it].IsValue, AAction.Items[it].Start, AAction.Items[it].Stop);
      end;
  end;
  if AAction.Batch then FDzFrom := -1 else FDzFrom := AAction.FromSlider;
  { THE PAYLOAD'S animation [Batch 96]: the inside roam's {cubicOut, 100}
    (roams.ts), a realtime slider's {cubicOut, 100, delay 0}
    (SliderZoomView's REALTIME_ANIMATION_CONFIG); none for the slider's other
    dispatches (`animation: null`) and for the API's }
  pay := TyAnimNoOverride;
  hasPay := False;
  { A DISPATCHED PAYLOAD'S animation [Batch 141]: an object's duration,
    easing and delay }
  if AJson <> nil then
  begin
    an := AJson.Find('animation');
    if an is TJSONObject then
    begin
      hasPay := True;
      x := TJSONObject(an).Find('duration');
      if (x <> nil) and (x.JSONType = jtNumber) then
      begin
        pay.HasDuration := True;
        pay.Duration := x.AsFloat;
      end;
      x := TJSONObject(an).Find('easing');
      if (x <> nil) and (x.JSONType = jtString) then
      begin
        pay.HasEasing := True;
        pay.Easing := x.AsString;
      end;
      x := TJSONObject(an).Find('delay');
      if (x <> nil) and (x.JSONType = jtNumber) then
      begin
        pay.HasDelay := True;
        pay.Delay := x.AsFloat;
      end;
    end;
  end
  { the toolbox's batch carries no animation of its own [Batch 125] }
  else if (AAction.Batch and not AAction.FromToolbox)
    or ((AAction.FromSlider >= 0) and AAction.Realtime) then
  begin
    hasPay := True;
    pay.HasDuration := True;
    pay.Duration := 100;
    pay.HasEasing := True;
    pay.Easing := 'cubicOut';
    if not AAction.Batch then
    begin
      pay.HasDelay := True;
      pay.Delay := 0;
    end;
  end;
  { the update is a dataZoom action's, whoever dispatched it [Batch 123] }
  savedAction := FCustomAction;
  FCustomAction := 'dataZoom';
  { the dataZoom action's update runs the visual stage with a payload: the
    brush's brushSelect [Batch 127] }
  FBrushPayload := True;
  Inc(FBrushActDepth);
  try
    try
      DzSyncLayout(pay, hasPay);
    finally
      FDzFrom := -1;
      FCustomAction := savedAction;
    end;
    { THE ACTION'S EVENT, after its update [Batch 141]: the payload's copy
      (a batch's items over it), as the dispatcher's payload -- the one it
      carried, or the one upstream's view would have built }
    built := nil;
    own := AJson = nil;
    try
      if own then
      begin
        built := DzPayloadOf(AAction);
        AJson := TJSONObject(built);
      end;
      if TyJsTruthy(AJson.Find('batch')) then
      begin
        items := BatchItemsOf(AJson);
        try
          evJson := BatchEventHead(AJson, 'datazoom');
          for i := 0 to items.Count - 1 do
          begin
            TJSONObject(TJSONArray(items).Items[i]).Strings['type'] := 'datazoom';
            if i > 0 then evJson := evJson + ',';
            evJson := evJson + VmJsJson(TJSONArray(items).Items[i]);
          end;
          evJson := evJson + ']}';
          EmitPayloadEvent('datazoom', evJson);
        finally
          items.Free;
        end;
      end
      else
        EmitPayloadEvent('datazoom', CopyWithType(AJson, 'datazoom'));
    finally
      built.Free;
    end;
    if Assigned(FOnDataZoom) then FOnDataZoom(Self, AAction);
  finally
    Dec(FBrushActDepth);
  end;
  { a dispatched payload's flush and updated are its dispatch's }
  if not own then Exit;
  if FBrushActDepth = 0 then BrushFlush;
  { the dispatch's triggerUpdatedEvent [Batch 97] }
  EmitUpdated;
end;

{ what the views draw from the slider states: a pointer event that leaves
  it unchanged repaints nothing }
function TTyAdvanceChart.DzStateKey: string;
var
  i: Integer;
  s: TTyDzSliderState;
begin
  Result := '';
  for i := 0 to High(FDzState) do
  begin
    s := FDzState[i];
    Result := Result + Format('%g,%g,%g,%g,%d%d%d%d%d,%d,%d%d,%g,%g;', [s.Ends[0],
      s.Ends[1], s.Range[0], s.Range[1], Ord(s.LabelsShown), Ord(s.NonRealtime),
      Ord(s.HandleHover[0]), Ord(s.HandleHover[1]), Ord(s.Dragging), s.MoveBits,
      Ord(s.HasBrush), Ord(s.BrushIgnored), s.BrushX, s.BrushW]);
  end;
end;

{ the views again, from the state and the window as they are }
procedure TTyAdvanceChart.DzViewUpdate;
begin
  if (FBuild = nil) or (FLastPPI <= 0) then Exit;
  SolveDataZoomViews(NewTextMeasurer(FLastPPI), FLastPPI);
  TipReset;
  DropStatic;
  FZrDirty := True;
  inherited Invalidate;
end;

{ AN ACTION IS SYNCHRONOUS upstream: the model, the axes and every view are
  new before dispatchAction returns -- so the click that follows a brush
  finds the handles where the brush put them }
procedure TTyAdvanceChart.DzSyncLayout(const APayload: TTyAnimOverride;
  AHasPayload: Boolean);
begin
  if FLastPPI <= 0 then
  begin
    FDirty := True;
    FZrDirty := True;
    inherited Invalidate;
    Exit;
  end;
  { A FULL UPDATE, animated with the action's payload: the list built now,
    the hovered element found again (zrender #6198) [Batch 96] }
  FullUpdateWith(APayload, AHasPayload);
  TipReset;
  DropStatic;
end;

procedure TTyAdvanceChart.DzArmTimer;
var
  due, now_: Double;
  i: Integer;
  any: Boolean;
begin
  { a test drives the clock itself }
  if not IsNan(FDzNow) then Exit;
  any := False;
  due := MaxDouble;
  for i := 0 to High(FDzState) do
    if FDzState[i].Throttle.Armed then
    begin
      any := True;
      due := Math.Min(due, FDzState[i].Throttle.Due);
    end;
  for i := 0 to High(FDzRoamThrottle) do
    if FDzRoamThrottle[i].Armed then
    begin
      any := True;
      due := Math.Min(due, FDzRoamThrottle[i].Due);
    end;
  if not any then
  begin
    if FDzTimer <> nil then FDzTimer.Enabled := False;
    Exit;
  end;
  if FDzTimer = nil then
  begin
    FDzTimer := TTimer.Create(nil);
    FDzTimer.OnTimer := @DzTimerFired;
  end;
  now_ := DzClock;
  FDzTimer.Enabled := False;
  FDzTimer.Interval := Math.Max(1, Ceil(due - now_));
  FDzTimer.Enabled := True;
end;

procedure TTyAdvanceChart.DzTimerFired(Sender: TObject);
begin
  FDzTimer.Enabled := False;
  DataZoomTick(DzClock);
end;

procedure TTyAdvanceChart.DataZoomTick(ANow: Double);
var
  i, best, kind: Integer;
  due: Double;
  a: TTyDzAction;
begin
  { every run due by now, the earliest first }
  repeat
    best := -1;
    kind := 0;
    due := MaxDouble;
    for i := 0 to High(FDzState) do
      if FDzState[i].Throttle.Armed and (FDzState[i].Throttle.Due <= ANow)
        and (FDzState[i].Throttle.Due < due) then
      begin
        best := i;
        kind := 0;
        due := FDzState[i].Throttle.Due;
      end;
    for i := 0 to High(FDzRoamThrottle) do
      if FDzRoamThrottle[i].Armed and (FDzRoamThrottle[i].Due <= ANow)
        and (FDzRoamThrottle[i].Due < due) then
      begin
        best := i;
        kind := 1;
        due := FDzRoamThrottle[i].Due;
      end;
    if best < 0 then Break;
    if kind = 0 then
    begin
      TyDzThrottleFire(FDzState[best].Throttle, ANow);
      DzRunSliderAction(best, True, FDzState[best].PendingRealtime);
    end
    else
    begin
      TyDzThrottleFire(FDzRoamThrottle[best], ANow);
      a := Default(TTyDzAction);
      a.Batch := True;
      a.Deferred := True;
      a.FromSlider := -1;
      a.Items := FDzRoamBatch[best];
      DzDispatch(a);
    end;
  until False;
  DzArmTimer;
end;

function TTyAdvanceChart.DispatchDataZoom(AIndex: Integer; AStart, AEnd: Double): Boolean;
var a: TTyDzAction;
begin
  Result := (AIndex >= 0) and (AIndex < Length(FDzRawHas)) and not IsNan(AStart)
    and not IsNan(AEnd);
  if not Result then Exit;
  a := Default(TTyDzAction);
  a.FromSlider := -1;
  SetLength(a.Items, 1);
  a.Items[0].DataZoomIndex := AIndex;
  a.Items[0].Start := AStart;
  a.Items[0].Stop := AEnd;
  DzDispatch(a);
end;

function TTyAdvanceChart.DataZoomPointer(AKind: TTyDzPointer; AX, AY: Double;
  AShift: TShiftState; AZrDelta: Double): Boolean;
var
  x, y, s, dx, dy: Double;
  t: TTyDzTarget;
  g, i, ct: Integer;
  any: Boolean;
  key: string;
begin
  Result := False;
  if (FBuild = nil) or (csDesigning in ComponentState) then Exit;
  any := False;
  for i := 0 to High(FZoomSpecs) do
    if (FZoomSpecs[i].SubType = 'slider') or (FZoomSpecs[i].SubType = 'inside') then
      any := True;
  if not any or (Length(FDzState) = 0) then Exit;
  s := DzScale;
  x := (AX - FLastRect.Left) / s;
  y := (AY - FLastRect.Top) / s;
  FDzLastX := AX;
  FDzLastY := AY;
  key := DzStateKey;
  case AKind of
    dpMove:
      begin
        t := DzFindTarget(x, y);
        { the Handler's own cursor: the target's, else the default }
        FDzCursor := 'default';
        if (t.Kind = dtkSlider) then
          case t.Role of
            dzrHandle0, dzrHandle1:
              if FDzLayouts[t.Slider].Horizontal then FDzCursor := 'ew-resize'
              else FDzCursor := 'ns-resize';
            dzrMoveZone, dzrFiller:
              if FDzState[t.Slider].Dragging and (FDzDrag.Kind = dtkSlider)
                and (FDzDrag.Role in [dzrMoveZone, dzrFiller]) then FDzCursor := 'grabbing'
              else FDzCursor := 'grab';
            dzrClickPanel:
              { zrender's own default for an element that answers the
                pointer }
              if FDzViews[t.Slider].BrushSelect then FDzCursor := 'crosshair'
              else FDzCursor := 'pointer';
          end
        else if t.Kind = dtkOther then
          FDzCursor := 'pointer';
        { mouseout to the old target, then the move -- Draggable, the roam,
          the brush -- then mouseover to the new one }
        if not SameDzTarget(t, FDzHover) then DzMouseOut(FDzHover);
        if FDzDrag.Kind = dtkSlider then
        begin
          dx := x - FDzDragX;
          dy := y - FDzDragY;
          FDzDragX := x;
          FDzDragY := y;
          if FDzDrag.Role in [dzrHandle0, dzrHandle1] then
            DzDragMove(FDzDrag.Slider, Ord(FDzDrag.Role) - Ord(dzrHandle0), dx, dy)
          else
          begin
            DzDragMove(FDzDrag.Slider, -1, dx, dy);
            FDzCursor := 'grabbing';
          end;
          Result := True;
        end;
        if FDzPanGrid >= 0 then
        begin
          FDzCursor := 'grabbing';
          if FDzPanGrid < FBuild.GridCount then
          begin
            ct := FDzPanGrid;
            dx := FDzPanX;
            dy := FDzPanY;
            FDzPanX := x;
            FDzPanY := y;
            { preventDefaultMouseMove: every inside of the grid must allow it }
            Result := True;
            for i in DzGridInsides(ct) do
              if not FDzInteract[i].PreventDefaultMouseMove then Result := False;
            DzRoam(ct, 'pan', AShift, dx, dy, x, y, 1, 0);
          end;
        end
        else if t.Kind = dtkNone then
          for g := 0 to FBuild.GridCount - 1 do
            if (DzControlType(g) >= 1) and DzGridContains(g, x, y) then
            begin
              FDzCursor := 'grab';
              Break;
            end;
        for i := 0 to High(FDzState) do
          if FDzState[i].Brushing then
          begin
            DzBrushMove(i, x, y);
            Result := True;
          end;
        if not SameDzTarget(t, FDzHover) then DzMouseOver(t);
        FDzHover := t;
        if DzStateKey <> key then DzViewUpdate;
      end;
    dpDown:
      begin
        t := DzFindTarget(x, y);
        FDzDownTarget := t;
        FDzUpTarget := t;
        FDzHasDown := True;
        FDzDownX := x;
        FDzDownY := y;
        { the click panel's mousedown starts a brush }
        if (t.Kind = dtkSlider) and (t.Role = dzrClickPanel)
          and FDzViews[t.Slider].BrushSelect then
        begin
          FDzState[t.Slider].BrushStartX := x;
          FDzState[t.Slider].BrushStartY := y;
          FDzState[t.Slider].Brushing := True;
          FDzState[t.Slider].BrushStartTime := DzClock;
        end;
        { Draggable: a handle, or the move zone }
        FDzDrag := Default(TTyDzTarget);
        if (t.Kind = dtkSlider) and ((t.Role in [dzrHandle0, dzrHandle1, dzrMoveZone])
          or ((t.Role = dzrFiller) and not FDzViews[t.Slider].BrushSelect)) then
        begin
          FDzDrag := t;
          FDzDragX := x;
          FDzDragY := y;
          if t.Role in [dzrMoveZone, dzrFiller] then DzShowDataInfo(t.Slider, True);
        end;
        { the roam controller: not on a draggable element, inside a grid
          that moves }
        FDzPanGrid := -1;
        if FDzDrag.Kind = dtkNone then
          for g := 0 to FBuild.GridCount - 1 do
            if (DzControlType(g) >= 1) and DzGridContains(g, x, y) then
            begin
              FDzPanGrid := g;
              FDzPanX := x;
              FDzPanY := y;
              Break;
            end;
        if DzStateKey <> key then DzViewUpdate;
      end;
    dpUp:
      begin
        FDzUpTarget := DzFindTarget(x, y);
        if FDzDrag.Kind = dtkSlider then
        begin
          i := FDzDrag.Slider;
          FDzDrag := Default(TTyDzTarget);
          DzDragEnd(i);
        end;
        FDzPanGrid := -1;
        for i := 0 to High(FDzState) do
          if FDzState[i].Brushing then DzBrushEnd(i);
        if DzStateKey <> key then DzViewUpdate;
      end;
    dpClick:
      begin
        { zrender's click rule: the press and the release on one element,
          the click within four pixels of the press }
        if not FDzHasDown then Exit;
        FDzHasDown := False;
        if not SameDzTarget(FDzDownTarget, FDzUpTarget) then Exit;
        if Sqrt(Sqr(x - FDzDownX) + Sqr(y - FDzDownY)) > 4 then Exit;
        t := DzFindTarget(x, y);
        if (t.Kind = dtkSlider) and (t.Role = dzrClickPanel) then
        begin
          DzClickPanel(t.Slider, x, y);
          if DzStateKey <> key then DzViewUpdate;
        end;
      end;
    dpWheel:
      begin
        if AZrDelta = 0 then Exit;
        for g := 0 to FBuild.GridCount - 1 do
        begin
          if DzControlType(g) < 2 then Continue;
          if not DzGridContains(g, x, y) then Continue;
          { stopped whether or not anything zooms }
          Result := True;
          DzRoam(g, 'zoom', AShift, 0, 0, x, y, TyDzWheelScale(AZrDelta), 0);
          if (g < FBuild.GridCount) then
            DzRoam(g, 'scrollMove', AShift, 0, 0, x, y, 1, TyDzScrollDelta(AZrDelta));
        end;
      end;
  end;
end;

function TTyAdvanceChart.DataZoomSliderState(AIndex: Integer): TTyDzSliderState;
begin
  Result := Default(TTyDzSliderState);
  if (AIndex >= 0) and (AIndex <= High(FDzState)) then Result := FDzState[AIndex];
end;

function TTyAdvanceChart.DataZoomInsideRange(AIndex: Integer; out ALo, AHi: Double): Boolean;
begin
  ALo := NaN;
  AHi := NaN;
  Result := (AIndex >= 0) and (AIndex <= High(FDzInLo));
  if not Result then Exit;
  ALo := FDzInLo[AIndex];
  AHi := FDzInHi[AIndex];
end;

function TTyAdvanceChart.DataZoomHoverName: string;
const
  cNames: array[TTyDzRole] of string = ('background', 'clickPanel', 'filler',
    'frame', 'handle0', 'handle1', 'moveHandle', 'moveHandleIcon', 'moveZone',
    'shadow0', 'shadow1', 'shadow2', 'shadowPolygon0', 'shadowPolygon1',
    'shadowPolygon2', 'shadowPolyline0', 'shadowPolyline1', 'shadowPolyline2',
    'label0', 'label1');
begin
  case FDzHover.Kind of
    dtkSlider: Result := 'dz' + IntToStr(FDzHover.Slider) + '.' + cNames[FDzHover.Role];
    dtkOther: Result := 'other';
  else
    Result := '';
  end;
end;


function TTyAdvanceChart.DataZoomSliderLayout(AIndex: Integer): TTyDzSliderLayout;
begin
  Result := Default(TTyDzSliderLayout);
  if (AIndex >= 0) and (AIndex <= High(FDzLayouts)) then
    Result := FDzLayouts[AIndex];
end;

function TTyAdvanceChart.DataZoomCount: Integer;
begin
  Result := Length(FZoomSpecs);
end;

function TTyAdvanceChart.DataZoomSpec(AIndex: Integer): TTyDataZoomSpec;
begin
  Result := Default(TTyDataZoomSpec);
  if (AIndex >= 0) and (AIndex <= High(FZoomSpecs)) then Result := FZoomSpecs[AIndex];
end;

function TTyAdvanceChart.AxisZoom(const AMainType: string; AAxisIndex: Integer;
  out AZoom: TTyAxisZoom; out AWindow: TTyDzWindow; out AHost: Integer): Boolean;
var
  ax: TTyAxis;
  k: Integer;
begin
  Result := False;
  AZoom := Default(TTyAxisZoom);
  AWindow := Default(TTyDzWindow);
  AHost := -1;
  if FBuild = nil then Exit;
  ax := FBuild.Axis(AMainType, AAxisIndex);
  if ax = nil then Exit;
  for k := 0 to High(FAxisZooms) do
    if FAxisZooms[k].Axis = ax then
    begin
      AZoom := FAxisZooms[k];
      AWindow := FZoomWindows[k];
      AHost := FZoomHost[k];
      Exit(True);
    end;
end;

function TTyAdvanceChart.DzModelId(AIndex: Integer): string;
var n: Integer;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(FZoomSpecs)) then Exit;
  n := TyDataZoomCount(FOption);
  if AIndex < n then Exit(FOption.ComponentId('dataZoom', AIndex));
  { the toolbox's own: makeInternalComponentId('toolbox-dataZoom_') + the
    axis' main type and index }
  if Length(FZoomSpecs[AIndex].Targets) = 0 then Exit;
  Result := #0'_ec_'#0'toolbox-dataZoom_' + FZoomSpecs[AIndex].Targets[0].Dim
    + 'Axis' + IntToStr(FZoomSpecs[AIndex].Targets[0].AxisIndex);
end;

function TTyAdvanceChart.DzQuery(APayload: TJSONObject): TTyIntegerArray;
var
  n, k, j: Integer;
  d: TJSONData;

  procedure Add(AIndex: Integer);
  var q: Integer;
  begin
    for q := 0 to High(Result) do
      if Result[q] = AIndex then Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AIndex;
  end;

  procedure AddIndex(AData: TJSONData);
  var v: Double;
  begin
    if AData.JSONType <> jtNumber then Exit;
    v := AData.AsFloat;
    if (v >= 0) and (v < n) and (Frac(v) = 0) then Add(Trunc(v));
  end;

  { queryByIdOrName: an id or a name as a string (a number is its text) }
  function Wanted(AData: TJSONData; const AValue: string): Boolean;
  var q: Integer;
  begin
    Result := False;
    if AData is TJSONArray then
    begin
      for q := 0 to AData.Count - 1 do
        if (TJSONArray(AData).Items[q].JSONType in [jtString, jtNumber])
          and (TJSONArray(AData).Items[q].AsString = AValue) then Exit(True);
    end
    else if AData.JSONType in [jtString, jtNumber] then
      Result := AData.AsString = AValue;
  end;

begin
  Result := nil;
  n := Length(FZoomSpecs);
  d := APayload.Find('dataZoomIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
      for k := 0 to d.Count - 1 do AddIndex(TJSONArray(d).Items[k])
    else
      AddIndex(d);
    Exit;
  end;
  d := APayload.Find('dataZoomId');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    for j := 0 to n - 1 do
      if Wanted(d, DzModelId(j)) then Add(j);
    Exit;
  end;
  d := APayload.Find('dataZoomName');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    for j := 0 to n - 1 do
      if (j < TyDataZoomCount(FOption))
        and Wanted(d, FOption.ComponentModelName('dataZoom', j)) then Add(j);
    Exit;
  end;
  { no query: every dataZoom }
  for j := 0 to n - 1 do Add(j);
end;

procedure TTyAdvanceChart.DzItemsOf(AItem: TJSONObject; var AAction: TTyDzAction);
var
  idx: TTyIntegerArray;
  k, n, host: Integer;
  s0, s1, v0, v1: TJSONData;
  isVal: Boolean;
  lo, hi: Double;
  z: TTyAxisZoom;
  w: TTyDzWindow;

  function Given(AData: TJSONData): Boolean;
  begin
    Result := (AData <> nil) and (AData.JSONType <> jtNull);
  end;

  function Num(AData: TJSONData): Double;
  begin
    if (AData <> nil) and (AData.JSONType = jtNumber) then Result := AData.AsFloat
    else Result := NaN;
  end;

begin
  idx := DzQuery(AItem);
  s0 := AItem.Find('start');
  s1 := AItem.Find('end');
  v0 := AItem.Find('startValue');
  v1 := AItem.Find('endValue');
  { setRawRange: a value end given makes the range a value one }
  isVal := Given(v0) or Given(v1);
  for k := 0 to High(idx) do
  begin
    if isVal then
    begin
      lo := Num(v0);
      hi := Num(v1);
    end
    else
    begin
      lo := Num(s0);
      hi := Num(s1);
    end;
    { an end the payload leaves out keeps the window's }
    if (IsNan(lo) or IsNan(hi)) and (Length(FZoomSpecs[idx[k]].Targets) > 0)
      and AxisZoom(FZoomSpecs[idx[k]].Targets[0].Dim + 'Axis',
        FZoomSpecs[idx[k]].Targets[0].AxisIndex, z, w, host) then
    begin
      if isVal then
      begin
        if IsNan(lo) then lo := w.Value[0];
        if IsNan(hi) then hi := w.Value[1];
      end
      else
      begin
        if IsNan(lo) then lo := w.Percent[0];
        if IsNan(hi) then hi := w.Percent[1];
      end;
    end;
    if IsNan(lo) or IsNan(hi) then Continue;
    n := Length(AAction.Items);
    SetLength(AAction.Items, n + 1);
    AAction.Items[n].DataZoomIndex := idx[k];
    AAction.Items[n].IsValue := isVal;
    AAction.Items[n].Start := lo;
    AAction.Items[n].Stop := hi;
  end;
end;

{ the payload the port's own dispatcher stands for, as upstream's builds it:
  the inside roams' batch {dataZoomId, start, end} with the animation; the
  toolbox's batch with its `from`; a slider's own {from, dataZoomId,
  animation, start, end}; the API's {dataZoomIndex, start, end} }
function TTyAdvanceChart.DzPayloadOf(const AAction: TTyDzAction): TJSONObject;
var
  arr: TJSONArray;
  o, an: TJSONObject;
  i: Integer;

  function Anim(ADelay: Boolean): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.Add('easing', 'cubicOut');
    Result.Add('duration', 100);
    if ADelay then Result.Add('delay', 0);
  end;

begin
  Result := TJSONObject.Create;
  Result.Add('type', 'dataZoom');
  if AAction.Batch then
  begin
    if AAction.FromToolbox then
      Result.Add('from', 'ec_' + IntToStr(FInstanceNo) + '_toolbox_dataZoom')
    else
      Result.Add('animation', Anim(False));
    arr := TJSONArray.Create;
    for i := 0 to High(AAction.Items) do
    begin
      o := TJSONObject.Create;
      o.Add('dataZoomId', DzModelId(AAction.Items[i].DataZoomIndex));
      if AAction.Items[i].IsValue then
      begin
        o.Add('startValue', TJSONFloat(AAction.Items[i].Start));
        o.Add('endValue', TJSONFloat(AAction.Items[i].Stop));
      end
      else
      begin
        o.Add('start', TJSONFloat(AAction.Items[i].Start));
        o.Add('end', TJSONFloat(AAction.Items[i].Stop));
      end;
      arr.Add(o);
    end;
    Result.Add('batch', arr);
    Exit;
  end;
  if (AAction.FromSlider >= 0) and (Length(AAction.Items) > 0) then
  begin
    Result.Add('from', 'ec_' + IntToStr(FInstanceNo) + '_dataZoom'
      + IntToStr(AAction.FromSlider));
    Result.Add('dataZoomId', DzModelId(AAction.Items[0].DataZoomIndex));
    if AAction.Realtime then
    begin
      an := Anim(True);
      Result.Add('animation', an);
    end
    else
      Result.Add('animation', TJSONNull.Create);
    Result.Add('start', TJSONFloat(AAction.Items[0].Start));
    Result.Add('end', TJSONFloat(AAction.Items[0].Stop));
    Exit;
  end;
  if Length(AAction.Items) > 0 then
  begin
    Result.Add('dataZoomIndex', AAction.Items[0].DataZoomIndex);
    Result.Add('start', TJSONFloat(AAction.Items[0].Start));
    Result.Add('end', TJSONFloat(AAction.Items[0].Stop));
  end;
end;

function TTyAdvanceChart.DoDataZoomAction(APayload: TJSONObject): Boolean;
var
  a: TTyDzAction;
  items: TJSONArray;
  i: Integer;
begin
  a := Default(TTyDzAction);
  a.FromSlider := -1;
  if TyJsTruthy(APayload.Find('batch')) then
  begin
    items := BatchItemsOf(APayload);
    try
      for i := 0 to items.Count - 1 do DzItemsOf(TJSONObject(items.Items[i]), a);
    finally
      items.Free;
    end;
  end
  else
    DzItemsOf(APayload, a);
  DzDispatch(a, APayload);
  Result := True;
end;

{ an inside dataZoom's RoamController would grab here: a grid one controls
  holds the point }
function TTyAdvanceChart.DzGrabAt(AX, AY: Integer): Boolean;
var
  s, x, y: Double;
  g: Integer;
begin
  Result := False;
  if (FBuild = nil) or (Length(FDzState) = 0) or (csDesigning in ComponentState) then Exit;
  s := DzScale;
  x := (AX - FLastRect.Left) / s;
  y := (AY - FLastRect.Top) / s;
  for g := 0 to FBuild.GridCount - 1 do
    if (DzControlType(g) >= 1) and DzGridContains(g, x, y) then Exit(True);
end;
