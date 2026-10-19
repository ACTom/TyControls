{ Part of tyControls.AdvanceChart (included, not a unit): large mode, progressive
  rendering and appendData. Moved out of the unit only to keep it readable; what the
  control is and why it is built the way it is, see the unit header. }

{ ==================== large mode [Batch 117] ==================== }

function TTyAdvanceChart.LargeKindOf(ASlot: Integer): TTyLargeKind;
var
  d: TJSONData;
  node: TJSONObject;
  st: string;
begin
  Result := lgkNone;
  if (FOption = nil) or (ASlot < 0) or (ASlot > High(FBindings))
    or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FBindings[ASlot].SeriesType;
  if TyLargeKindOfType(st) = lgkNone then Exit;
  { ON A CARTESIAN ONLY: barGrid's large layout returns early off one
    (createLarge would then read no points), and the polar and calendar
    scatters are left drawn one by one. LINES are batched on any of their
    systems: linesLayout's large branch is dataToPoint [Batch 121] }
  if (st <> TyLinesSeriesTypeName) and ((FBindings[ASlot].Cart = nil)
    or (FBindings[ASlot].Polar <> nil) or (FBindings[ASlot].CalendarIndex >= 0)) then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  { BarSeries.__preparePipelineContext: progressive rendering forces large
    [Batch 119] }
  if not TyLargeIsOn(st, node.Find('large'), node.Find('largeThreshold'),
    FStores[ASlot].Count) and not ((st = 'bar') and ProgOnOf(ASlot)) then Exit;
  { A path:// SYMBOL stays one element per row: upstream's batch would
    replay one fitted path, which this port does not model }
  if (st = 'scatter') and (SymbolFor(ASlot).Kind = tsyPath) then Exit;
  Result := TyLargeKindOfType(st);
end;

function TTyAdvanceChart.LargeRowAt(AElement, AX, AY: Integer): Integer;
var el: TTyChartElement;
begin
  Result := -1;
  if (FPaintList = nil) or (AElement < 0) or (AElement >= FPaintList.Count) then Exit;
  el := FPaintList.Element(AElement);
  if el.Shape.Kind <> cskLarge then Exit;
  { A LINES BATCH IS HOVERED WITH NO ROW: its handler writes null for row 0
    and dataIndex + an unset startIndex (not a number) for the rest --
    upstream's own, which the port does not carry into a datum [Batch 121] }
  if el.Shape.Large.Kind = lgkLines then Exit;
  Result := TyLargeIndexAt(el.Shape.Large, AX, AY);
end;

function TTyAdvanceChart.SeriesLargeKind(ASeriesIndex: Integer): TTyLargeKind;
var slot: Integer;
begin
  Result := lgkNone;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FLargeKinds)) then Result := FLargeKinds[slot];
end;

{ ==================== progressive rendering and appendData [Batch 119] ====================

  THE PIPELINE PER SLOT (FProg), made by every relayout from the counts the
  filters left: the context (progressiveRender, large, modDataCount), the
  chunks planned from row 0 by the step, how many are drawn, and the args
  the blocked data stage and the visual stage last ran with -- the two
  things that restart a run (see AdvChart.Progressive).

  A FULL UPDATE (setOption, a dispatch, a resize) starts every run again and
  draws its first chunk, as upstream's update does inside setOption. A FRAME
  (ProgressTick, the 16 ms timer) is _onframe: rows appendData left are
  taken in by a relayout that keeps the axes (FFrozen) and keeps the drawn
  chunks where the run may carry on; then each progressive series draws
  its next chunk, again while the 1 ms budget lasts.

  THE ELEMENTS are built for every row, as always; ProgTag marks the chunk
  that draws each (an element per datum by its row's first chunk, a batch
  by the chunk it was made for) and ProgApplyVisibility hides what is to
  come -- neither drawn nor hit. A progress frame changes nothing else, so
  the list it leaves is painted as it stands (FProgReuse). }

function TTyAdvanceChart.ProgOnOf(ASlot: Integer): Boolean;
begin
  Result := (ASlot >= 0) and (ASlot <= High(FProg)) and (ASlot <= High(FBindings))
    and FProg[ASlot].On and (FProg[ASlot].Series = FBindings[ASlot].SeriesIndex);
end;

function TTyAdvanceChart.ProgCtxOf(ASlot: Integer): TTyProgRun;
var
  d: TJSONData;
  node: TJSONObject;
  st: string;
  n: Integer;
begin
  Result := Default(TTyProgRun);
  Result.Series := -1;
  Result.ModCount := -1;
  Result.Block.ModBy := 1;
  Result.Visual.ModBy := 1;
  if (FOption = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  st := FBindings[ASlot].SeriesType;
  Result.Series := FBindings[ASlot].SeriesIndex;
  Result.SeriesType := st;
  d := FOption.ComponentAt('series', Result.Series);
  if d is TJSONObject then node := TJSONObject(d) else node := nil;
  { the option root: a progressive the series and its type do not set is
    the root's (the global default 400 under it) [F4c] }
  if FOption.Root is TJSONObject then
    Result.Spec := TyProgSpecOf(st, node, TJSONObject(FOption.Root))
  else
    Result.Spec := TyProgSpecOf(st, node);
  if (ASlot <= High(FStores)) and (FStores[ASlot] <> nil) then n := FStores[ASlot].Count
  else n := 0;
  Result.Count := n;
  { a series the legend switched off is not in the pipeline at all }
  Result.On := (not FBindings[ASlot].Hidden) and TyProgRenderOn(Result.Spec, st, n);
  if node <> nil then
    Result.Large := TyLargeIsOn(st, node.Find('large'), node.Find('largeThreshold'), n)
  else
    Result.Large := TyLargeIsOn(st, nil, nil, n);
  { BarSeries.__preparePipelineContext }
  if (st = 'bar') and Result.On then Result.Large := True;
  if Result.Spec.ModMode then Result.ModCount := n;
end;

procedure TTyAdvanceChart.ProgUpdate;
var
  i: Integer;
  old: TTyProgRunArray;
  r, o: TTyProgRun;
  haveOld, restart: Boolean;
  a: TTyProgArgs;
begin
  { an export's own layout keeps the window's runs }
  if FExporting then Exit;
  old := FProg;
  FProg := nil;
  SetLength(FProg, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    r := ProgCtxOf(i);
    haveOld := (i <= High(old)) and (old[i].Series = r.Series)
      and (old[i].SeriesType = r.SeriesType);
    if haveOld then o := old[i] else o := Default(TTyProgRun);
    if FStreamRelayout and haveOld then
    begin
      { THE FRAME'S FIRST ITERATION, data stage first: the blocked tasks run
        with the context they had, then the stream modes, then the visual
        tasks with the new one }
      r.Starts := o.Starts;
      r.Ends := o.Ends;
      r.Done := o.Done;
      r.Block := o.Block;
      restart := False;
      if TyProgHasBlockTask(r.SeriesType) then
      begin
        a := TyProgBlockArgs(o, False);
        if not TyProgArgsSame(a, o.Block) then restart := True;
        r.Block := a;
      end;
      a := TyProgVisualArgs(r);
      { createRenderPlanner: a large or a progressive switch resets too }
      if (not TyProgArgsSame(a, o.Visual)) or (r.On <> o.On) or (r.Large <> o.Large) then
        restart := True;
      r.Visual := a;
      if not r.On then
      begin
        r.Starts := nil;
        r.Ends := nil;
        r.Done := 0;
      end
      else if restart or not o.On then
      begin
        r.Done := 0;
        TyProgReplan(r, 0);
      end
      else
        { the chunks drawn stay, the rows appended come after them }
        TyProgReplan(r, r.Done);
    end
    else
    begin
      { AN UPDATE: everything from row 0, the first chunk drawn by it. Its
        blocked stage ran with the context the pipeline had -- none after a
        setOption }
      if haveOld and not FProgFresh then r.Block := TyProgBlockArgs(o, False)
      else
      begin
        r.Block.ModBy := 1;
        r.Block.ModCount := 0;
      end;
      r.Visual := TyProgVisualArgs(r);
      r.Done := 0;
      TyProgReplan(r, 0);
      if Length(r.Starts) > 0 then r.Done := 1;
    end;
    FProg[i] := r;
  end;
  if not FStreamRelayout then FProgFresh := False;
  FProgUnfinished := ProgAnyUnfinished;
end;

{ A frame's later iteration: the blocked data stage with the context as it
  stands. Where its args moved -- the first frame after a setOption, the
  frame after appendData moved a 'mod' count -- the run starts over. }
procedure TTyAdvanceChart.ProgStage;
var
  i: Integer;
  a: TTyProgArgs;
begin
  for i := 0 to High(FProg) do
  begin
    if not TyProgHasBlockTask(FProg[i].SeriesType) then Continue;
    a := TyProgBlockArgs(FProg[i], False);
    if TyProgArgsSame(a, FProg[i].Block) then Continue;
    FProg[i].Block := a;
    if FProg[i].On then
    begin
      FProg[i].Done := 0;
      TyProgReplan(FProg[i], 0);
    end;
  end;
end;

procedure TTyAdvanceChart.ProgStep;
var i: Integer;
begin
  for i := 0 to High(FProg) do
    if TyProgUnfinished(FProg[i]) then Inc(FProg[i].Done);
end;

function TTyAdvanceChart.ProgAnyUnfinished: Boolean;
var i: Integer;
begin
  for i := 0 to High(FProg) do
    if TyProgUnfinished(FProg[i]) then Exit(True);
  Result := False;
end;

procedure TTyAdvanceChart.ProgTag(AList: TTyPaintList);
var
  k, slot, r: Integer;
  el: TTyChartElement;
  rows: array of TTyIntegerArray;
  any: Boolean;
begin
  any := False;
  for slot := 0 to High(FProg) do
    if FProg[slot].On then any := True;
  if not any then Exit;
  SetLength(rows, Length(FProg));
  for k := 0 to AList.Count - 1 do
  begin
    el := AList.Element(k);
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex < 0) then Continue;
    slot := SlotOfSeries(el.Datum.SeriesIndex);
    if not ProgOnOf(slot) then Continue;
    if el.Shape.Kind = cskLarge then
    begin
      { the builder made it for its chunk }
      if el.ProgChunk <= 0 then Continue;
    end
    else
    begin
      if (el.Datum.DataIndex < 0) or el.Datum.IsEdge then Continue;
      if rows[slot] = nil then rows[slot] := TyProgRowChunks(FProg[slot]);
      r := el.Datum.DataIndex;
      { a row no chunk visits -- the 'mod' walk misses some -- never comes }
      if (r < Length(rows[slot])) and (rows[slot][r] >= 0) then
        el.ProgChunk := rows[slot][r] + 1
      else
        el.ProgChunk := MaxInt;
      el.ProgRow := r;
      { AN INCREMENTAL CANDLE HAS NO DATA: _incrementalRenderNormal never
        calls setItemGraphicEl, so its box is hovered and names nothing --
        no event, no item tooltip, no state }
      if FProg[slot].SeriesType = 'candlestick' then el.Datum := TyChartNoDatum;
    end;
    el.ProgSlot := slot;
    AList.SetElement(k, el);
  end;
  ProgApplyVisibility(AList);
end;

procedure TTyAdvanceChart.ProgApplyVisibility(AList: TTyPaintList);
var
  k, done, j, shown: Integer;
  el: TTyChartElement;
  hid, moved: Boolean;
begin
  if AList = nil then Exit;
  for k := 0 to AList.Count - 1 do
  begin
    el := AList.Element(k);
    if el.ProgChunk <= 0 then Continue;
    if (el.ProgSlot >= 0) and (el.ProgSlot <= High(FProg)) then done := FProg[el.ProgSlot].Done
    else done := MaxInt;
    hid := el.ProgChunk > done;
    moved := hid <> el.ProgHidden;
    { A GROWING SCATTER BATCH holds the rows of its chunks drawn so far }
    if (el.Shape.Kind = cskLarge) and (el.Shape.Large.Kind = lgkSymbol)
      and (Length(el.Shape.Large.ChunkEnds) > 0) then
    begin
      j := done - el.Shape.Large.ChunkFirst;
      if j > Length(el.Shape.Large.ChunkEnds) then j := Length(el.Shape.Large.ChunkEnds);
      if j < 1 then j := 1;
      shown := el.Shape.Large.ChunkEnds[j - 1];
      if shown <> el.Shape.Large.Shown then
      begin
        el.Shape.Large.Shown := shown;
        TyLargeSetBox(el.Shape.Large);
        el.Shape.Bounds := TyLargeBounds(el.Shape.Large);
        moved := True;
      end;
    end;
    if moved then
    begin
      el.ProgHidden := hid;
      AList.SetElement(k, el);
    end;
  end;
end;

function TTyAdvanceChart.ProgClock: Double;
begin
  if IsNan(FAnimNow) then Result := TyProgNowMs else Result := FAnimNow;
end;

{ drawn through the incremental layer: an element a chunk of a run draws }
function TTyAdvanceChart.ProgIsLayered(const AEl: TTyChartElement): Boolean;
begin
  Result := (AEl.ProgChunk > 0) and not AEl.ProgHidden and not AEl.Ignore;
end;

procedure TTyAdvanceChart.ProgLayerBuild(AW, AH, APPI, AScale: Integer);
var
  P: TTyPainter;
  i, idx: Integer;
  el: TTyChartElement;
  sc: TTyCanvasScale;
begin
  if (FProgLayer = nil) or (FProgLayer.Width <> AW) or (FProgLayer.Height <> AH) then
  begin
    FreeAndNil(FProgLayer);
    FProgLayer := TBGRABitmap.Create(AW, AH, BGRAPixelTransparent);
  end
  else
    FProgLayer.Fill(BGRAPixelTransparent);
  FProgLayerPPI := APPI;
  { the layer the size of the painter's bitmap, AScale of its pixels per
    device px: drawn at that scale over the device-px rect (#83) }
  FProgLayerScale := Max(1, AScale);
  FProgPainted := nil;
  SetLength(FProgPainted, FPaintList.Count);
  P := TTyPainter.Create;
  try
    sc.Scale := FProgLayerScale;
    sc.DeviceUnits := False;
    P.BeginPaintOnScaled(nil, Rect(0, 0, AW div FProgLayerScale, AH div FProgLayerScale), APPI,
      FProgLayer, sc);
    for i := 0 to FPaintList.Count - 1 do
    begin
      idx := FPaintList.PaintOrder(i);
      el := FPaintList.Element(idx);
      if not ProgIsLayered(el) then Continue;
      TyRenderElement(P, el);
      if el.Shape.Kind = cskLarge then FProgPainted[idx] := Max(1, TyLargeRows(el.Shape.Large))
      else FProgPainted[idx] := 1;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
  FProgLayerOk := True;
end;

{ A FRAME'S CHUNK onto the layer: what was not on it, in paint order, and
  the rows a growing scatter batch took on since -- on top of everything
  already there, as the canvas' incremental layer adds it }
procedure TTyAdvanceChart.ProgLayerDelta;
var
  P: TTyPainter;
  i, idx, have, rows: Integer;
  el, part: TTyChartElement;
  started: Boolean;
  sc: TTyCanvasScale;
begin
  if not FProgLayerOk or (FProgLayer = nil) or (FPaintList = nil) then Exit;
  if Length(FProgPainted) <> FPaintList.Count then
  begin
    FProgLayerOk := False;
    Exit;
  end;
  P := nil;
  started := False;
  try
    for i := 0 to FPaintList.Count - 1 do
    begin
      idx := FPaintList.PaintOrder(i);
      el := FPaintList.Element(idx);
      if not ProgIsLayered(el) then Continue;
      have := FProgPainted[idx];
      if el.Shape.Kind = cskLarge then rows := Max(1, TyLargeRows(el.Shape.Large))
      else rows := 1;
      if have >= rows then Continue;
      if not started then
      begin
        P := TTyPainter.Create;
        sc.Scale := FProgLayerScale;
        sc.DeviceUnits := False;
        P.BeginPaintOnScaled(nil, Rect(0, 0, FProgLayer.Width div FProgLayerScale,
          FProgLayer.Height div FProgLayerScale), FProgLayerPPI, FProgLayer, sc);
        started := True;
      end;
      if (have > 0) and (el.Shape.Kind = cskLarge) and (el.Shape.Large.Kind = lgkSymbol) then
      begin
        { only the rows the batch grew by }
        part := el;
        part.Shape.Large.Pts := Copy(el.Shape.Large.Pts, have * 2, (rows - have) * 2);
        part.Shape.Large.Shown := 0;
        part.Shape.Large.ChunkEnds := nil;
        TyRenderElement(P, part);
      end
      else
        TyRenderElement(P, el);
      FProgPainted[idx] := rows;
    end;
  finally
    if started then
    begin
      P.EndPaint;
      P.Free;
    end;
  end;
end;

{ The series in paint order, a run's chunks as the incremental layer where
  the first of them stands: what comes before it below, what comes after it
  above (zrender's EL_AFTER_INCREMENTAL_INC) }
procedure TTyAdvanceChart.ProgRenderList(APainter: TTyPainter; AList: TTyPaintList;
  APPI: Integer);
var
  i, idx: Integer;
  pe: PTyChartElement;
  any, blitted: Boolean;
  bmp: TBGRABitmap;
begin
  if (AList = nil) or (APainter = nil) then Exit;
  bmp := APainter.Bitmap;
  any := False;
  if (bmp <> nil) and (AList = FPaintList) then
    for i := 0 to AList.Count - 1 do
      if ProgIsLayered(AList.Ref(i)^) then
      begin
        any := True;
        Break;
      end;
  if not any then
  begin
    TyRenderPaintList(APainter, AList);
    Exit;
  end;
  if not FProgLayerOk or (FProgLayer = nil) or (FProgLayer.Width <> bmp.Width)
    or (FProgLayer.Height <> bmp.Height) or (FProgLayerPPI <> APPI)
    or (FProgLayerScale <> APainter.DeviceScale) then
    ProgLayerBuild(bmp.Width, bmp.Height, APPI, APainter.DeviceScale);
  blitted := False;
  for i := 0 to AList.Count - 1 do
  begin
    idx := AList.PaintOrder(i);
    pe := AList.Ref(idx);
    { a graphic element under the axes is painted before them [Batch 122] }
    if pe^.Ignore or pe^.ProgHidden or pe^.GfxUnder then Continue;
    if pe^.ProgChunk > 0 then
    begin
      if not blitted then
      begin
        bmp.PutImage(0, 0, FProgLayer, dmDrawWithTransparency);
        blitted := True;
      end;
      Continue;
    end;
    TyRenderElement(APainter, pe^);
  end;
end;

function TTyAdvanceChart.ProgLive: Boolean;
begin
  Result := FProgUnfinished or FStreamPending;
end;

{ the `finished` test: the animation finished, no update pending, the
  scheduler finished }
function TTyAdvanceChart.ProgIdle: Boolean;
begin
  { [F4b] and no action pending (bindRenderedEvent's _pendingActions) }
  Result := not ProgLive and not FAnimLive and not FLazyPending
    and (Length(FActPending) = 0);
end;

function TTyAdvanceChart.ProgFrame(AEmit: Boolean): Boolean;
var
  remain, t0: Double;
  relaid: Boolean;
  m: ITyTextMeasurer;
begin
  Result := False;
  if not ProgLive then Exit;
  { nothing laid out yet, or an update still to lay out: the update draws
    first }
  if (FOption = nil) or (FLastPPI <= 0) or FDirty
    or (csDestroying in ComponentState) then Exit;
  Result := True;
  remain := TyProgFrameBudgetMs;
  relaid := False;
  repeat
    t0 := ProgClock;
    if FStreamPending then
    begin
      { performSeriesTasks and the data stage take the appended rows in;
        the coordinate systems are not updated }
      FStreamPending := False;
      m := NewTextMeasurer(FLastPPI);
      FStreamRelayout := True;
      try
        Relayout(nil, FLastRect, FLastPPI, m);
      finally
        FStreamRelayout := False;
      end;
      relaid := True;
    end
    else
      ProgStage;
    ProgStep;
    FProgUnfinished := ProgAnyUnfinished;
    { THE CHUNK IS DRAWN IN THE STEP, onto the incremental layer: the time
      the budget measures is the drawing's }
    if not relaid and (FPaintList <> nil) and FPaintListValid then
    begin
      ProgApplyVisibility(FPaintList);
      ProgLayerDelta;
    end;
    if IsNan(FProgStepCost) then remain := remain - (ProgClock - t0)
    else remain := remain - FProgStepCost;
  until (remain <= 0) or not FProgUnfinished;
  if relaid or (FPaintList = nil) or not FPaintListValid then
    DropStatic
  else
  begin
    { THE SAME LIST, more of it shown -- and on the layer already }
    StaticDrop;
    FProgReuse := True;
  end;
  InvalidateFrame;
  if AEmit then
  begin
    { [F4b] the frame's flush: what it drew is no longer dirty }
    FZrDirty := False;
    FTipPaintedKey := TipStateKey;
    EmitRendered(0);
    if ProgIdle then EmitPlain('finished');
    AnimArmTimer;
  end;
end;

procedure TTyAdvanceChart.ProgressTick;
begin
  ProgFrame(True);
end;

function TTyAdvanceChart.ProgressiveUnfinished: Boolean;
begin
  Result := ProgLive;
end;

function TTyAdvanceChart.SeriesProgress(ASeriesIndex: Integer): TTyProgRun;
var slot: Integer;
begin
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FProg)) then Result := FProg[slot]
  else
  begin
    Result := Default(TTyProgRun);
    Result.Series := -1;
    Result.ModCount := -1;
  end;
end;

{ THE AXES AS THE LAST UPDATE MEASURED THEM: every grid axis' raw extent
  (a dataZoom's hold where it has one), keyed by main type and index -- the
  build's axes are new objects every relayout }
procedure TTyAdvanceChart.FrozenCapture;
var
  g, a: Integer;
  gb: TTyGridBuild;

  procedure Take(AAxis: TTyAxis);
  var k, zi: Integer; z: TTyAxisZoom; any: Boolean;
  begin
    if AAxis = nil then Exit;
    zi := -1;
    for k := 0 to High(FAxisZooms) do
      if FAxisZooms[k].Axis = AAxis then zi := k;
    if zi >= 0 then z := FAxisZooms[zi]
    else
    begin
      z := Default(TTyAxisZoom);
      z.Raw := TyAxisNoZoomExtent(FOption, FBindings, FStores, FStacks, FIndex,
        AAxis, AAxis.MainType, any);
      z.Any := any;
      z.ZoomLo := NaN;
      z.ZoomHi := NaN;
    end;
    z.Axis := nil;
    SetLength(FFrozen, Length(FFrozen) + 1);
    FFrozen[High(FFrozen)] := z;
    SetLength(FFrozenKeys, Length(FFrozenKeys) + 1);
    FFrozenKeys[High(FFrozenKeys)] := AAxis.MainType + ':' + IntToStr(AAxis.ComponentIndex);
  end;

begin
  FFrozen := nil;
  FFrozenKeys := nil;
  FFrozenOn := True;
  if FBuild = nil then Exit;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    for a := 0 to gb.XAxisCount - 1 do Take(gb.XAxis(a));
    for a := 0 to gb.YAxisCount - 1 do Take(gb.YAxis(a));
  end;
end;

function TTyAdvanceChart.FrozenZooms: TTyAxisZoomArray;
var
  j, g, a, k, hit: Integer;
  gb: TTyGridBuild;
  ax, cand: TTyAxis;
begin
  Result := Copy(FAxisZooms);
  if FBuild = nil then Exit;
  for j := 0 to High(FFrozen) do
  begin
    ax := nil;
    for g := 0 to FBuild.GridCount - 1 do
    begin
      gb := FBuild.Grid(g);
      for a := 0 to gb.XAxisCount + gb.YAxisCount - 1 do
      begin
        if a < gb.XAxisCount then cand := gb.XAxis(a)
        else cand := gb.YAxis(a - gb.XAxisCount);
        if (cand <> nil) and (cand.MainType + ':' + IntToStr(cand.ComponentIndex) = FFrozenKeys[j]) then
          ax := cand;
      end;
    end;
    if ax = nil then Continue;
    hit := -1;
    for k := 0 to High(Result) do
      if Result[k].Axis = ax then hit := k;
    if hit < 0 then
    begin
      hit := Length(Result);
      SetLength(Result, hit + 1);
    end;
    Result[hit] := FFrozen[j];
    Result[hit].Axis := ax;
  end;
end;

{ An event with no params and no payload, to the handlers registered for
  it -- the catch-all OnChartEvent does not count as asking, as with
  `updated` }
procedure TTyAdvanceChart.EmitPlain(const AType: string);
var
  ev: TTyChartEvent;
  regs: array of TTyChartEventReg;
  i, saved: Integer;
begin
  if not HasChartHandler(AType) then Exit;
  ev := Default(TTyChartEvent);
  ev.EventType := AType;
  ev.Params := TyChartBlankParams;
  regs := Copy(FEventRegs);
  { [F4b] outside the cycle }
  saved := FActCycle;
  FActCycle := 0;
  try
    for i := 0 to High(regs) do
      if regs[i].EventType = AType then regs[i].Handler(Self, ev);
  finally
    FActCycle := saved;
  end;
end;

{ bindRenderedEvent over a flush: `rendered`, and `finished` when nothing
  animates, nothing is to draw, no update waits and no action is pending.
  [F4b] Every flush that had something to draw -- zrender's
  _needsRefresh: an update's (FFlushDue) or any repaint asked for since the
  last (FZrDirty: a hover, the tooltip, the pointer...), not only an
  update's -- with the paint's elapsedTime on the chart's clock. }
procedure TTyAdvanceChart.EmitFlush;
var elapsed: Double;
begin
  if not FFlushDue and not FZrDirty then Exit;
  FFlushDue := False;
  FZrDirty := False;
  FTipPaintedKey := TipStateKey;
  elapsed := AnimClock - FPaintT0;
  if IsNan(elapsed) or (elapsed < 0) then elapsed := 0;
  EmitRendered(elapsed);
  if ProgIdle then EmitPlain('finished');
end;

procedure TTyAdvanceChart.EmitRendered(AElapsed: Double);
var
  ev: TTyChartEvent;
  regs: array of TTyChartEventReg;
  i, saved: Integer;
begin
  if not HasChartHandler('rendered') then Exit;
  ev := Default(TTyChartEvent);
  ev.EventType := 'rendered';
  ev.Params := TyChartBlankParams;
  ev.Payload := '{"elapsedTime":' + TyJsNumberToString(AElapsed) + '}';
  regs := Copy(FEventRegs);
  { a handler is outside any dispatch (IN_EC_CYCLE is false) }
  saved := FActCycle;
  FActCycle := 0;
  try
    for i := 0 to High(regs) do
      if regs[i].EventType = 'rendered' then regs[i].Handler(Self, ev);
  finally
    FActCycle := saved;
  end;
end;

{ ==================== appendData [Batch 119] ==================== }

function TTyAdvanceChart.AppendData(ASeriesIndex: Integer;
  const ADataJson: string): Boolean;
var
  d, node, arr: TJSONData;
  nLine, nCol, k: Integer;
begin
  Result := False;
  if (FOption = nil) or not (FOption.Root is TJSONObject) then Exit;
  { too deep is refused before fpjson can recurse into it }
  if TyJsonNestingExceeds(ADataJson, TyOptionMaxNesting, nLine, nCol) then Exit;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if not (node is TJSONObject) then Exit;
  { THE SERIES' OWN ARRAY: upstream's provider pushes into it; a series
    reading a dataset is not taken (upstream would push into the table) }
  arr := TJSONObject(node).Find('data');
  if not (arr is TJSONArray) then Exit;
  try
    d := GetJSON(NulSafeJson(ADataJson));
    NulRestore(d);
  except
    d := nil;
  end;
  if not (d is TJSONArray) then
  begin
    d.Free;
    Exit;
  end;
  try
    { THE UPDATE BEFORE IT: upstream's setOption has laid the chart out by
      the time appendData can run }
    ConvertReady;
    if (FLastPPI > 0) and not FDirty and not FFrozenOn then FrozenCapture;
    for k := 0 to d.Count - 1 do
      TJSONArray(arr).Add(d.Items[k].Clone);
  finally
    d.Free;
  end;
  Result := True;
  if (FLastPPI <= 0) or FDirty then
  begin
    { nothing laid out yet: the first update takes every row }
    FDirty := True;
    Invalidate;
    Exit;
  end;
  { scheduler.unfinished = true; zr.wakeUp() }
  FStreamPending := True;
  AnimArmTimer;
end;
