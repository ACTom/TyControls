{ Part of tyControls.AdvanceChart (included, not a unit): graph, tree, treemap, sunburst,
  sankey and chord -- layout, roam, node drags, drill-downs and gestures. Moved out of the
  unit only to keep it readable; what the control is and why it is built the way it is,
  see the unit header. }

function TTyAdvanceChart.GraphLayout(ASeriesIndex: Integer;
  out ANodes: TTyGraphNodeArray; out AEdges: TTyGraphEdgeArray;
  out AFills: TTyChartColorArray): Boolean;
var slot: Integer;
begin
  ANodes := nil;
  AEdges := nil;
  AFills := nil;
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FGraphLaidOut)) or not FGraphLaidOut[slot] then
    Exit;
  ANodes := Copy(FGraphNodes[slot]);
  AEdges := Copy(FGraphEdges[slot]);
  AFills := GraphInk(slot).NodeFills;
  Result := True;
end;

function TTyAdvanceChart.GraphInkOf(ASeriesIndex: Integer;
  out AInk: TTyGraphInk; out ASpec: TTyGraphSpec): Boolean;
var slot: Integer;
begin
  AInk := Default(TTyGraphInk);
  ASpec := Default(TTyGraphSpec);
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FGraphLaidOut)) or not FGraphLaidOut[slot] then
    Exit;
  AInk := GraphInk(slot);
  ASpec := FGraphSpecs[slot];
  Result := True;
end;

function TTyAdvanceChart.GraphView(ASeriesIndex: Integer): TTyGraphView;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FGraphs)) then Exit;
  Result := FGraphs[slot];
end;

function TTyAdvanceChart.GraphNodeScale(ASeriesIndex: Integer): Double;
var slot: Integer;
begin
  Result := NaN;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FGraphNodeScale)) then Exit;
  Result := FGraphNodeScale[slot];
end;

function TTyAdvanceChart.GraphRoamState(ASeriesIndex: Integer;
  out ACentre: TTyGraphCentre; out AZoom: Double): Boolean;
var slot: Integer;
begin
  ACentre := Default(TTyGraphCentre);
  AZoom := NaN;
  slot := SlotOfSeries(ASeriesIndex);
  Result := (slot >= 0) and (slot <= High(FGraphs)) and (FGraphs[slot] <> nil);
  if not Result then Exit;
  if (ASeriesIndex <= High(FGraphRoam)) and FGraphRoam[ASeriesIndex].Valid then
  begin
    ACentre := FGraphRoam[ASeriesIndex].Centre;
    AZoom := FGraphRoam[ASeriesIndex].Zoom;
  end
  else
  begin
    ACentre := FGraphSpecs[slot].Centre;
    AZoom := FGraphSpecs[slot].Zoom;
  end;
end;

function TTyAdvanceChart.GraphRoam(ASeriesIndex: Integer;
  ADX, ADY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasPan := True;
  p.DX := ADX;
  p.DY := ADY;
  Result := GraphDispatchRoam(p);
end;

function TTyAdvanceChart.GraphZoom(ASeriesIndex: Integer; AScale, AOriginX,
  AOriginY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasZoom := True;
  p.Zoom := AScale;
  p.OriginX := AOriginX;
  p.OriginY := AOriginY;
  Result := GraphDispatchRoam(p);
end;

function TTyAdvanceChart.GraphDispatchRoam(
  const APayload: TTyGraphRoamPayload): Boolean;
var
  i, si: Integer;
  p: TTyGraphRoamPayload;
begin
  Result := False;
  { A NEGATIVE OR NON-FINITE ZOOM IS REFUSED. Upstream mirrors the picture
    through a rotation and then flips the sign back on the next step; that is
    not a thing anybody asks for on purpose. }
  if APayload.HasZoom and (IsNan(APayload.Zoom) or IsInfinite(APayload.Zoom)
    or (APayload.Zoom <= 0)) then Exit;
  if APayload.HasPan and (IsNan(APayload.DX) or IsNan(APayload.DY)) then Exit;
  for i := 0 to High(FGraphs) do
  begin
    if FGraphs[i] = nil then Continue;
    if (i > High(FGraphLaidOut)) or not FGraphLaidOut[i] then Continue;
    si := FBindings[i].SeriesIndex;
    if (APayload.SeriesIndex >= 0) and (si <> APayload.SeriesIndex) then
      Continue;
    if Length(FGraphRoam) <= si then SetLength(FGraphRoam, si + 1);
    TyGraphRoamStep(FGraphs[i], FGraphSpecs[i], APayload, FGraphRoam[si]);
    TyGraphRemap(FGraphNodes[i], FGraphEdges[i], FGraphSpecs[i], FGraphs[i],
      APayload.HasZoom, FGraphNodeScale[i]);
    Result := True;
    if Assigned(FOnGraphRoam) then
    begin
      p := APayload;
      p.SeriesIndex := si;
      FOnGraphRoam(Self, p);
    end;
  end;
  if not Result then Exit;
  { __updateOnOwnRoam: the thumbnail's window follows [Batch 140] }
  ThumbUpdateWindows;
  { [F4b] as an action, the dispatch publishes its event and `updated` }
  { A NEW PICTURE, NOT A NEW LAYOUT: the static layer goes, the build and
    the force answer stay. The hover names an element of a list about to be
    rebuilt. The list is built again at once [Milestone D9-D14]: the next
    pointer event -- this drag's release, the next move's hover -- finds the
    picture where it moved, as zrender's storage holds it.
    [R2-E] A roam (update none) renders no tooltip view: nothing kept. }
  TipResetQuiet;
  DropStaticKeepList;
  FZrDirty := True;
  inherited Invalidate;
  { the dispatch's triggerUpdatedEvent [Batch 97] }
  if FViewActionDepth = 0 then EmitUpdated;
end;

function TTyAdvanceChart.RoamSeriesAt(AX, AY: Integer; AZoom: Boolean): Integer;
var z, zl: Integer;
begin
  Result := RoamSeriesAtZ(AX, AY, AZoom, z, zl);
end;

function TTyAdvanceChart.RoamSeriesAtZ(AX, AY: Integer; AZoom: Boolean;
  out AZ, AZLevel: Integer): Integer;
var
  i, best: Integer;
  sp, bs: TTyGraphSpec;
  ok: Boolean;
begin
  Result := -1;
  AZ := 0;
  AZLevel := 0;
  best := -1;
  bs := Default(TTyGraphSpec);
  for i := 0 to High(FGraphs) do
  begin
    if FGraphs[i] = nil then Continue;
    if (i > High(FGraphLaidOut)) or not FGraphLaidOut[i] then Continue;
    sp := FGraphSpecs[i];
    if AZoom then ok := sp.Roam in [grmZoom, grmBoth]
    else ok := sp.Roam in [grmPan, grmBoth];
    if not ok then Continue;
    if not (sp.RoamGlobal or FGraphs[i].ContainTrigger(AX, AY)) then Continue;
    { HIGHER zlevel, THEN HIGHER z; A TIE GOES TO THE ONE FOUND FIRST. }
    if (best < 0) or (sp.ZLevel > bs.ZLevel)
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z > bs.Z))
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z = bs.Z)
        and (FBindings[i].SeriesIndex < FBindings[best].SeriesIndex)) then
    begin
      best := i;
      bs := sp;
    end;
  end;
  { THE TREES, on the same terms: a tree's view is the same View [Batch 82] }
  for i := 0 to High(FTreeViews) do
  begin
    if FTreeViews[i] = nil then Continue;
    sp := FTreeSpecs[i];
    if AZoom then ok := sp.Roam in [grmZoom, grmBoth]
    else ok := sp.Roam in [grmPan, grmBoth];
    if not ok then Continue;
    if not (sp.RoamGlobal or FTreeViews[i].ContainTrigger(AX, AY)) then Continue;
    if (best < 0) or (sp.ZLevel > bs.ZLevel)
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z > bs.Z))
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z = bs.Z)
        and (FBindings[i].SeriesIndex < FBindings[best].SeriesIndex)) then
    begin
      best := i;
      bs := sp;
    end;
  end;
  { AND THE SANKEYS [Batch 114]: roamTrigger 'global' by default; any other
    word takes the view's area here (upstream: the main group's own box) }
  for i := 0 to High(FSankeyViews) do
  begin
    if FSankeyViews[i] = nil then Continue;
    sp := FSankeySpecs[i];
    if AZoom then ok := sp.Roam in [grmZoom, grmBoth]
    else ok := sp.Roam in [grmPan, grmBoth];
    if not ok then Continue;
    if not (sp.RoamGlobal or FSankeyViews[i].ContainTrigger(AX, AY)) then Continue;
    if (best < 0) or (sp.ZLevel > bs.ZLevel)
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z > bs.Z))
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z = bs.Z)
        and (FBindings[i].SeriesIndex < FBindings[best].SeriesIndex)) then
    begin
      best := i;
      bs := sp;
    end;
  end;
  { AND THE TREEMAPS [Batch 115]: roam true by default, roamTrigger 'global'
    by default; 'selfRect' the container group's rect -- the root's }
  for i := 0 to High(FTreemaps) do
  begin
    if not FTreemaps[i].Valid then Continue;
    if not TreemapRoamOk(i, AZoom) then Continue;
    sp := Default(TTyGraphSpec);
    sp.Z := 2;
    if (FTreemaps[i].Series.Find('z') <> nil)
      and (FTreemaps[i].Series.Find('z').JSONType = jtNumber) then
      sp.Z := Round(FTreemaps[i].Series.Find('z').AsFloat);
    if (FTreemaps[i].Series.Find('zlevel') <> nil)
      and (FTreemaps[i].Series.Find('zlevel').JSONType = jtNumber) then
      sp.ZLevel := Round(FTreemaps[i].Series.Find('zlevel').AsFloat);
    ok := (FTreemaps[i].Series.Find('roamTrigger') = nil)
      or (FTreemaps[i].Series.Find('roamTrigger').JSONType <> jtString)
      or (FTreemaps[i].Series.Find('roamTrigger').AsString <> 'selfRect');
    if not ok then
      ok := (AX - FTreemaps[i].Box.X >= FTreemaps[i].Nodes[0].X)
        and (AX - FTreemaps[i].Box.X <= FTreemaps[i].Nodes[0].X + FTreemaps[i].Nodes[0].W)
        and (AY - FTreemaps[i].Box.Y >= FTreemaps[i].Nodes[0].Y)
        and (AY - FTreemaps[i].Box.Y <= FTreemaps[i].Nodes[0].Y + FTreemaps[i].Nodes[0].H);
    if not ok then Continue;
    if (best < 0) or (sp.ZLevel > bs.ZLevel)
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z > bs.Z))
      or ((sp.ZLevel = bs.ZLevel) and (sp.Z = bs.Z)
        and (FBindings[i].SeriesIndex < FBindings[best].SeriesIndex)) then
    begin
      best := i;
      bs := sp;
    end;
  end;
  if best >= 0 then
  begin
    Result := FBindings[best].SeriesIndex;
    AZ := bs.Z;
    AZLevel := bs.ZLevel;
  end;
end;

function TTyAdvanceChart.IsTreeSeries(ASeriesIndex: Integer): Boolean;
var slot: Integer;
begin
  slot := SlotOfSeries(ASeriesIndex);
  Result := (slot >= 0) and (FBindings[slot].SeriesType = TyTreeSeriesTypeName);
end;

function TTyAdvanceChart.IsTreemapSeries(ASeriesIndex: Integer): Boolean;
var slot: Integer;
begin
  slot := SlotOfSeries(ASeriesIndex);
  Result := (slot >= 0) and (FBindings[slot].SeriesType = TyTreemapSeriesTypeName);
end;

function TTyAdvanceChart.IsSankeySeries(ASeriesIndex: Integer): Boolean;
var slot: Integer;
begin
  slot := SlotOfSeries(ASeriesIndex);
  Result := (slot >= 0) and (FBindings[slot].SeriesType = TySankeySeriesTypeName);
end;

{ ==================== node drags [Batch 114] ==================== }

procedure TTyAdvanceChart.GraphDragMove(AX, AY: Integer);
var
  st: TTyGraphDragStep;
  slot, si: Integer;
  was: Boolean;
begin
  slot := FGraphDragSlot;
  if (slot < 0) or (slot > High(FGraphs))
    or (slot > High(FGraphNodes)) or (FGraphDragNode > High(FGraphNodes[slot])) then
  begin
    FGraphDragSlot := -1;
    Exit;
  end;
  si := FBindings[slot].SeriesIndex;
  st := Default(TTyGraphDragStep);
  st.Node := FGraphDragNode;
  st.DX := AX - FGraphDragX;
  st.DY := AY - FGraphDragY;
  st.PX := AX;
  st.PY := AY;
  st.First := FGraphDragFirst;
  FGraphDragX := AX;
  FGraphDragY := AY;
  FGraphDragFirst := False;
  if Length(FGraphForce) <= si then SetLength(FGraphForce, si + 1);
  { [F3b] a graph off a view: the drift on the canvas, the edges again }
  if FGraphs[slot] = nil then
    TyGraphDragOffView(FGraphNodes[slot], FGraphEdges[slot], st)
  else
  begin
    was := FGraphForce[si].Layouting;
    TyGraphDragStep(FGraphNodes[slot], FGraphEdges[slot], FGraphSpecs[slot],
      FGraphs[slot], FGraphForce[si], st, FGraphNodeScale[slot]);
    { [F3b] an iteration the drag started: its first step renders the
      thumbnail, and the timer runs it on }
    if FGraphForce[si].Layouting and not was then
    begin
      FThumbSnapDue := True;
      AnimArmTimer;
    end;
  end;
  { A NEW PICTURE, NOT A NEW LAYOUT -- as a roam step [R2-E: nothing
    kept] }
  TipResetQuiet;
  DropStatic;
  FZrDirty := True;
  inherited Invalidate;
end;

function TTyAdvanceChart.GraphForceLive: Boolean;
var slot, si: Integer;
begin
  Result := False;
  for slot := 0 to Min(High(FBindings), High(FGraphs)) do
  begin
    if FGraphs[slot] = nil then Continue;
    si := FBindings[slot].SeriesIndex;
    if (si >= 0) and (si <= High(FGraphForce)) and FGraphForce[si].Layouting then
      Exit(True);
  end;
end;

function TTyAdvanceChart.GraphForceFrame: Boolean;
var slot, si: Integer;
begin
  Result := False;
  for slot := 0 to Min(High(FBindings), High(FGraphs)) do
  begin
    if (FGraphs[slot] = nil) or (slot > High(FGraphNodes)) then Continue;
    si := FBindings[slot].SeriesIndex;
    if (si < 0) or (si > High(FGraphForce)) or not FGraphForce[si].Layouting then Continue;
    if TyGraphForceFrame(FGraphNodes[slot], FGraphEdges[slot], FGraphSpecs[slot],
      FGraphs[slot], FGraphForce[si]) then
    begin
      Result := True;
      { _renderThumbnail once the iteration stops }
      if not FGraphForce[si].Layouting then FThumbSnapDue := True;
    end;
  end;
  if not Result then Exit;
  { A NEW PICTURE, NOT A NEW LAYOUT -- as a drag step }
  DropStatic;
  FZrDirty := True;
  inherited Invalidate;
end;

procedure TTyAdvanceChart.GraphDragEnd;
var slot, si: Integer;
begin
  slot := FGraphDragSlot;
  FGraphDragSlot := -1;
  if (slot < 0) or (slot > High(FBindings)) then Exit;
  si := FBindings[slot].SeriesIndex;
  { dragend: setUnfixed on a force graph's instance }
  if (slot <= High(FGraphSpecs)) and (FGraphSpecs[slot].Layout = glForce)
    and (si >= 0) and (si <= High(FGraphForce)) then
    TyGraphDragEnd(FGraphForce[si], FGraphDragNode);
end;

function TTyAdvanceChart.SankeyDragStart(ASlot, ANode, AX, AY: Integer): Boolean;
var x, y, w, h: Double;
begin
  Result := False;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FBindings[ASlot].SeriesType <> TySankeySeriesTypeName then Exit;
  if (ASlot > High(FSankeys)) or not FSankeys[ASlot].Valid then Exit;
  if (ANode < 0) or (ANode > High(FSankeys[ASlot].Nodes)) then Exit;
  if not TySankeyDraggable(FSankeys[ASlot], ANode) then Exit;
  TySankeyNodeRect(FSankeys[ASlot], ANode, x, y, w, h);
  FSankeyDragSlot := ASlot;
  FSankeyDragNode := ANode;
  FSankeyDragX := AX;
  FSankeyDragY := AY;
  FSankeyDragShapeX := x;
  FSankeyDragShapeY := y;
  FSankeyDragW := FSankeys[ASlot].Box.W;
  FSankeyDragH := FSankeys[ASlot].Box.H;
  Result := True;
end;

procedure TTyAdvanceChart.SankeyDragMove(AX, AY: Integer);
var si: Integer; mask: TFPUExceptionMask;
begin
  if (FSankeyDragSlot < 0) or (FSankeyDragSlot > High(FBindings)) then
  begin
    FSankeyDragSlot := -1;
    Exit;
  end;
  si := FBindings[FSankeyDragSlot].SeriesIndex;
  { the rect's drift: its own shape moved by the pointer's delta, local to
    the main group -- a zoom does not scale it -- and the action with the
    shape over the box its render had }
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    FSankeyDragShapeX := FSankeyDragShapeX + (AX - FSankeyDragX);
    FSankeyDragShapeY := FSankeyDragShapeY + (AY - FSankeyDragY);
    FSankeyDragX := AX;
    FSankeyDragY := AY;
    SankeyDragNode(si, FSankeyDragNode, True, FSankeyDragShapeX / FSankeyDragW,
      True, FSankeyDragShapeY / FSankeyDragH);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

function TTyAdvanceChart.SankeyDragNode(ASeriesIndex, ADataIndex: Integer;
  AHasX: Boolean; ALocalX: Double; AHasY: Boolean; ALocalY: Double): Boolean;
var
  i, si, n: Integer;
  ev: TJSONObject;
begin
  Result := False;
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].SeriesType <> TySankeySeriesTypeName then Continue;
    si := FBindings[i].SeriesIndex;
    if (ASeriesIndex >= 0) and (si <> ASeriesIndex) then Continue;
    if (i > High(FSankeys)) or not FSankeys[i].Valid then Continue;
    n := Length(FSankeys[i].Nodes);
    { setNodePosition indexes the option's node list: past its end upstream
      throws }
    if (ADataIndex < 0) or (ADataIndex >= n) then Continue;
    if Length(FSankeyLocal) <= si then SetLength(FSankeyLocal, si + 1);
    if Length(FSankeyLocal[si]) < n then SetLength(FSankeyLocal[si], n);
    FSankeyLocal[si][ADataIndex].HasX := AHasX;
    FSankeyLocal[si][ADataIndex].X := ALocalX;
    FSankeyLocal[si][ADataIndex].HasY := AHasY;
    FSankeyLocal[si][ADataIndex].Y := ALocalY;
    Result := True;
    { the action's event, 'dragnode', with the payload }
    ev := TJSONObject.Create;
    try
      ev.Strings['type'] := 'dragNode';
      ev.Integers['seriesIndex'] := si;
      ev.Integers['dataIndex'] := ADataIndex;
      if AHasX then ev.Floats['localX'] := ALocalX;
      if AHasY then ev.Floats['localY'] := ALocalY;
      { [F4b] the action publishes its own (a copy of its payload) }
      if FViewActionDepth = 0 then EmitPayloadEvent('dragnode', ev.AsJSON);
    finally
      ev.Free;
    end;
  end;
  if not Result then Exit;
  { update: 'update' -- the whole chart laid out again }
  Invalidate;
  if FViewActionDepth = 0 then EmitUpdated;
end;

function TTyAdvanceChart.SankeySolved(ASeriesIndex: Integer): TTySankeySolved;
var slot: Integer;
begin
  Result := Default(TTySankeySolved);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FSankeys)) then Exit;
  Result := FSankeys[slot];
end;

function TTyAdvanceChart.TreeSolved(ASeriesIndex: Integer): TTyTreeSolved;
var slot: Integer;
begin
  Result := Default(TTyTreeSolved);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FTrees)) then Exit;
  Result := FTrees[slot];
end;

function TTyAdvanceChart.ChordSolved(ASeriesIndex: Integer): TTyChordSolved;
var slot: Integer;
begin
  Result := Default(TTyChordSolved);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FChords)) then Exit;
  Result := FChords[slot];
end;

function TTyAdvanceChart.SankeyView(ASeriesIndex: Integer): TTyGraphView;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FSankeyViews)) then Exit;
  Result := FSankeyViews[slot];
end;

procedure TTyAdvanceChart.FreeSankeyViews;
var i: Integer;
begin
  for i := 0 to High(FSankeyViews) do FreeAndNil(FSankeyViews[i]);
  FSankeyViews := nil;
  FSankeySpecs := nil;
end;

{ THE SANKEY'S VIEW (SankeyView._updateViewCoordSys): data rect and view
  rect both the box, the roam options read as a graph's -- `roam` false and
  `roamTrigger` 'global' by default -- the roam's write-back over the
  option's centre and zoom; and the main group's frame from it. }
procedure TTyAdvanceChart.SankeyViewOf(ASlot: Integer);
var
  si: Integer;
  node: TJSONData;
  root: TJSONObject;
  spec: TTyGraphSpec;
  centre: TTyGraphCentre;
  zoom: Double;
  v: TTyGraphView;
begin
  si := FBindings[ASlot].SeriesIndex;
  spec := TyGraphSpecDefault;
  node := FOption.ComponentAt('series', si);
  root := nil;
  if FOption.Root is TJSONObject then root := TJSONObject(FOption.Root);
  if node is TJSONObject then
  begin
    TyGraphReadRoamOptions(TJSONObject(node), root, spec);
    if TJSONObject(node).Find('roamTrigger') = nil then spec.RoamGlobal := True;
  end;
  spec.Z := FSankeys[ASlot].Z;
  FSankeySpecs[ASlot] := spec;
  v := TTyGraphView.CreateXYWH(FSankeys[ASlot].Box, FSankeys[ASlot].Box);
  FSankeyViews[ASlot] := v;
  if (si <= High(FSankeyRoam)) and FSankeyRoam[si].Valid then
  begin
    centre := FSankeyRoam[si].Centre;
    zoom := FSankeyRoam[si].Zoom;
  end
  else
  begin
    centre := spec.Centre;
    zoom := spec.Zoom;
  end;
  v.SetRoam(centre, zoom, spec.HasLimit, spec.LimitMin, spec.LimitMax);
  TySankeyFrame(FSankeys[ASlot], v.OverallScaleX, v.OverallScaleY, v.OverallX,
    v.OverallY);
end;

function TTyAdvanceChart.SankeyDispatchRoam(const APayload: TTyGraphRoamPayload): Boolean;
var
  i, si: Integer;
  p: TTyGraphRoamPayload;
begin
  Result := False;
  if APayload.HasZoom and (IsNan(APayload.Zoom) or IsInfinite(APayload.Zoom)
    or (APayload.Zoom <= 0)) then Exit;
  if APayload.HasPan and (IsNan(APayload.DX) or IsNan(APayload.DY)) then Exit;
  for i := 0 to High(FSankeyViews) do
  begin
    if FSankeyViews[i] = nil then Continue;
    si := FBindings[i].SeriesIndex;
    if (APayload.SeriesIndex >= 0) and (si <> APayload.SeriesIndex) then Continue;
    if Length(FSankeyRoam) <= si then SetLength(FSankeyRoam, si + 1);
    TyGraphRoamStep(FSankeyViews[i], FSankeySpecs[i], APayload, FSankeyRoam[si]);
    Result := True;
    if Assigned(FOnSankeyRoam) then
    begin
      p := APayload;
      p.SeriesIndex := si;
      FOnSankeyRoam(Self, p);
    end;
  end;
  if not Result then Exit;
  { the series group's transform changes; everything on the canvas follows
    it -- laid out again here, as the tree's roam is }
  Invalidate;
  if FViewActionDepth = 0 then EmitUpdated;
end;

function TTyAdvanceChart.SankeyRoam(ASeriesIndex: Integer; ADX, ADY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasPan := True;
  p.DX := ADX;
  p.DY := ADY;
  Result := SankeyDispatchRoam(p);
end;

function TTyAdvanceChart.SankeyZoom(ASeriesIndex: Integer; AScale, AOriginX,
  AOriginY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasZoom := True;
  p.Zoom := AScale;
  p.OriginX := AOriginX;
  p.OriginY := AOriginY;
  Result := SankeyDispatchRoam(p);
end;

{ ==================== the drill-downs [Batch 115] ====================

  A SUNBURST drills by sunburstRootToNode -- a click on a piece of the view
  (its nodeClick 'rootToNode'), on the return circle (the view root's
  parent), or the action -- and the view root lives until a new tree. A
  TREEMAP zooms (treemapZoomToNode: a click, nodeClick 'zoomToNode' by
  default; a breadcrumb item below the view root), drills
  (treemapRootToNode: a click on a leaf root under leafDepth; a breadcrumb
  item above the view root), pans (treemapMove: a drag of more than 3 px
  between two moves) and zooms about the pointer (treemapRender: the wheel).
  Each is an updateView: the chart renders again (FullUpdate) and the
  action's event follows. }

procedure TTyTmWrap.Hit;
begin
  Dec(Pending);
  if Pending <= 0 then Live := False;
end;

procedure TTyAdvanceChart.HierDrillReset;
begin
  { [R2-C] the treemaps as last drawn, for the merge's transition from the
    old tree (the first reset since a render keeps them) }
  if Length(FTmPrev) > 0 then
  begin
    FTmOld := FTmPrev;
    FTmOldHave := FTmHave;
    FTmOldKeys := FTmViewKeys;
  end;
  FSunRoot := nil;
  FSunVirt := nil;
  FSunHandlers := nil;
  FTmView := nil;
  FTmPrev := nil;
  FTmHave := nil;
  FHierDrill := nil;
  TmAnimDropAll;
end;

function TTyAdvanceChart.HierIdOfRow(ASlot, ARow: Integer): string;
var
  ids: TTyStringArray;
  ser: TJSONData;
  hier: TTyHierarchy;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if (ASlot <= High(FSunbursts)) and FSunbursts[ASlot].Valid then hier := FSunbursts[ASlot].Hier
  else if (ASlot <= High(FTreemaps)) and FTreemaps[ASlot].Valid then hier := FTreemaps[ASlot].Hier
  else Exit;
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if ser is TJSONObject then ids := TyHierIds(hier, TJSONObject(ser))
  else ids := TyHierIds(hier, nil);
  if (ARow >= 0) and (ARow <= High(ids)) then Result := ids[ARow];
end;

function TTyAdvanceChart.HierRowOfId(ASlot: Integer; const AId: string): Integer;
var
  ids: TTyStringArray;
  ser: TJSONData;
  hier: TTyHierarchy;
  k: Integer;
begin
  Result := -1;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if (ASlot <= High(FSunbursts)) and FSunbursts[ASlot].Valid then hier := FSunbursts[ASlot].Hier
  else if (ASlot <= High(FTreemaps)) and FTreemaps[ASlot].Valid then hier := FTreemaps[ASlot].Hier
  else Exit;
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if ser is TJSONObject then ids := TyHierIds(hier, TJSONObject(ser))
  else ids := TyHierIds(hier, nil);
  { getNodeById: the root first, then down -- the ids are one each }
  for k := 0 to High(ids) do
    if ids[k] = AId then Exit(k);
end;

{ treeHelper.retrieveTargetInfo: a targetNode string by getNodeById (the
  tree holds every node it finds), else a targetNodeId -- getNodeById
  compares with ===, so only a string ever matches }
function TTyAdvanceChart.HierTarget(ASlot: Integer; APayload: TJSONObject): Integer;
var d: TJSONData;
begin
  Result := -1;
  d := APayload.Find('targetNode');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result := HierRowOfId(ASlot, d.AsString);
    if Result >= 0 then Exit;
  end;
  d := APayload.Find('targetNodeId');
  if (d <> nil) and (d.JSONType = jtString) then
    Result := HierRowOfId(ASlot, d.AsString);
end;

function TTyAdvanceChart.HierQuery(APayload: TJSONObject; const AType: string): TTyIntegerArray;
var
  ser: TTyIntegerArray;
  k, slot: Integer;
  queried: Boolean;
begin
  Result := nil;
  queried := (APayload.Find('seriesIndex') <> nil) or (APayload.Find('seriesId') <> nil)
    or (APayload.Find('seriesName') <> nil);
  if queried then
  begin
    ser := MatchSeries(APayload);
    for k := 0 to High(ser) do
    begin
      slot := SlotOfSeries(ser[k]);
      if (slot >= 0) and (FBindings[slot].SeriesType = AType) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := slot;
      end;
    end;
  end
  else
    for slot := 0 to High(FBindings) do
      if FBindings[slot].SeriesType = AType then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := slot;
      end;
end;

{ aboveViewRoot: the node is among the view root's ancestors }
function HierAbove(const AHier: TTyHierarchy; AViewRoot, ARow: Integer): Boolean;
var p: Integer;
begin
  Result := False;
  if (AViewRoot < 0) or (AViewRoot > High(AHier.Nodes)) then Exit;
  p := AHier.Nodes[AViewRoot].Parent;
  while p >= 0 do
  begin
    if p = ARow then Exit(True);
    p := AHier.Nodes[p].Parent;
  end;
end;

procedure TTyAdvanceChart.HierUpdate(const AEventType, APayloadJson: string);
var
  txt: string;
  p, a, b: Integer;
begin
  { updateView: the layout, the visuals and the render again }
  FullUpdate;
  { THE EVENT OBJECT'S type IS THE ACTION'S EVENT NAME (doDispatchAction:
    eventObj.type = actionInfo.event), in its place -- rewritten in the
    text, which a parse would lose the NULs of a generated id in [F2a] }
  txt := APayloadJson;
  p := Pos('"type"', txt);
  if p > 0 then
  begin
    a := p + 6;
    while (a <= Length(txt)) and (txt[a] <> '"') do Inc(a);
    b := a + 1;
    while (b <= Length(txt)) and (txt[b] <> '"') do Inc(b);
    if b <= Length(txt) then
      txt := Copy(txt, 1, a) + AEventType + Copy(txt, b, MaxInt);
  end;
  EmitPayloadEvent(AEventType, txt);
end;

function TTyAdvanceChart.DoSunAction(APayload: TJSONObject): Boolean;
var
  slots: TTyIntegerArray;
  k, slot, si, row, old: Integer;
  dir: string;
begin
  Result := True;
  slots := HierQuery(APayload, TySunburstSeriesTypeName);
  dir := '';
  for k := 0 to High(slots) do
  begin
    slot := slots[k];
    if (slot > High(FSunbursts)) or not FSunbursts[slot].Valid then Continue;
    row := HierTarget(slot, APayload);
    if row < 0 then Continue;
    si := FBindings[slot].SeriesIndex;
    old := FSunbursts[slot].ViewRoot;
    if HierAbove(FSunbursts[slot].Hier, old, row) then dir := 'rollUp'
    else dir := 'drillDown';
    if Length(FSunRoot) <= si then SetLength(FSunRoot, si + 1);
    FSunRoot[si] := row;
    if Length(FHierDrill) <= si then SetLength(FHierDrill, si + 1);
    FHierDrill[si] := True;
  end;
  { the payload, as dispatched, gains the last series' direction }
  if dir <> '' then APayload.Strings['direction'] := dir;
  try
    HierUpdate('sunburstroottonode', APayload.AsJSON);
  finally
    FHierDrill := nil;
  end;
end;

function TTyAdvanceChart.DoTreemapAction(const AType: string; APayload: TJSONObject;
  const AEventJson: string): Boolean;
var
  slots: TTyIntegerArray;
  k, slot, si, row: Integer;
  dir: string;
  v: TTyTreemapView;
  rr: TJSONData;

  function RectNum(const AKey: string): Double;
  var dd: TJSONData;
  begin
    Result := NaN;
    if not (rr is TJSONObject) then Exit;
    dd := TJSONObject(rr).Find(AKey);
    if (dd <> nil) and (dd.JSONType = jtNumber) then Result := dd.AsFloat;
  end;

begin
  Result := True;
  slots := HierQuery(APayload, TyTreemapSeriesTypeName);
  dir := '';
  rr := APayload.Find('rootRect');
  for k := 0 to High(slots) do
  begin
    slot := slots[k];
    if (slot > High(FTreemaps)) or not FTreemaps[slot].Valid then Continue;
    si := FBindings[slot].SeriesIndex;
    if Length(FTmView) <= si then
    begin
      SetLength(FTmView, si + 1);
      FTmView[si] := TyTreemapNoView;
    end;
    v := FTmView[si];
    v.ViewRoot := FTreemaps[slot].ViewRoot;
    v.Target := -1;
    v.Direction := 0;
    if AType = 'treemapRootToNode' then
    begin
      v.Kind := tpkRootToNode;
      row := HierTarget(slot, APayload);
      if row >= 0 then
      begin
        if HierAbove(FTreemaps[slot].Hier, FTreemaps[slot].ViewRoot, row) then
        begin
          dir := 'rollUp';
          v.Direction := 2;
        end
        else
        begin
          dir := 'drillDown';
          v.Direction := 1;
        end;
        v.ViewRoot := row;
        v.Target := row;
      end;
    end
    else if AType = 'treemapZoomToNode' then
    begin
      v.Kind := tpkZoomToNode;
      v.Target := HierTarget(slot, APayload);
    end
    else if AType = 'treemapMove' then
    begin
      { the root to the rect's x, y; none: back to 0 }
      v.Kind := tpkMove;
      v.RootX := RectNum('x');
      v.RootY := RectNum('y');
      if not (rr is TJSONObject) then
      begin
        v.RootX := 0;
        v.RootY := 0;
      end;
      v.RootW := RectNum('width');
      v.RootH := RectNum('height');
    end
    else
    begin
      { treemapRender: a rect zooms and places the root; none is a plain
        render }
      if rr is TJSONObject then
      begin
        v.Kind := tpkRender;
        v.RootX := RectNum('x');
        v.RootY := RectNum('y');
        v.RootW := RectNum('width');
        v.RootH := RectNum('height');
      end
      else
        v.Kind := tpkNone;
    end;
    FTmView[si] := v;
  end;
  { THE OTHER TREEMAPS are not rendered (TreemapView.render's query): they
    keep their picture }
  for slot := 0 to High(FBindings) do
  begin
    if FBindings[slot].SeriesType <> TyTreemapSeriesTypeName then Continue;
    if (slot > High(FTreemaps)) or not FTreemaps[slot].Valid then Continue;
    row := 0;
    for k := 0 to High(slots) do
      if slots[k] = slot then row := 1;
    if row = 1 then Continue;
    si := FBindings[slot].SeriesIndex;
    if Length(FTmView) <= si then
    begin
      SetLength(FTmView, si + 1);
      FTmView[si] := TyTreemapNoView;
    end;
    FTmView[si].ViewRoot := FTreemaps[slot].ViewRoot;
    FTmView[si].Kind := tpkKeep;
  end;
  if dir <> '' then APayload.Strings['direction'] := dir;
  if AEventJson <> '' then HierUpdate(LowerCase(AType), AEventJson)
  else HierUpdate(LowerCase(AType), APayload.AsJSON);
end;

function TTyAdvanceChart.SunburstRootToNode(ASeriesIndex, ARow: Integer): Boolean;
var
  p: TJSONObject;
  slot: Integer;
begin
  Result := False;
  p := TJSONObject.Create;
  try
    p.Strings['type'] := 'sunburstRootToNode';
    slot := SlotOfSeries(ASeriesIndex);
    if (slot < 0) or (FBindings[slot].SeriesType <> TySunburstSeriesTypeName) then Exit;
    p.Integers['seriesIndex'] := ASeriesIndex;
    p.Strings['targetNode'] := HierIdOfRow(slot, ARow);
    Result := DoSunAction(p);
    EmitUpdated;
  finally
    p.Free;
  end;
end;

function TTyAdvanceChart.SunburstViewRoot(ASeriesIndex: Integer): Integer;
var slot: Integer;
begin
  Result := 0;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FSunbursts)) and FSunbursts[slot].Valid then
    Result := FSunbursts[slot].ViewRoot;
end;

function TTyAdvanceChart.SunburstSolved(ASeriesIndex: Integer): TTySunburstSolved;
var slot: Integer;
begin
  Result := Default(TTySunburstSolved);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FSunbursts)) then Result := FSunbursts[slot];
end;

function TTyAdvanceChart.TreemapSolved(ASeriesIndex: Integer): TTyTreemapSolved;
var slot: Integer;
begin
  Result := Default(TTyTreemapSolved);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FTreemaps)) then Result := FTreemaps[slot];
end;

function TTyAdvanceChart.TreemapHave(ASeriesIndex: Integer): TTyTreemapHave;
begin
  Result := Default(TTyTreemapHave);
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FTmHave)) then Result := FTmHave[ASeriesIndex];
end;

function TreemapPayload(const AType: string; ASeries: Integer; const AId: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Strings['type'] := AType;
  Result.Integers['seriesIndex'] := ASeries;
  Result.Strings['targetNode'] := AId;
end;

{ [R2-B] THE VIEW'S OWN DISPATCH (TreemapView._zoomToNode / _rootToNode, for
  a click on a node and a breadcrumb item's onclick alike): {type, from: the
  view's uid, seriesId: the series model's id, targetNode} -- the TreeNode
  as its id, which the action resolves the same way (retrieveTargetInfo
  takes a string targetNode to getNodeById) [was: seriesIndex and
  targetNode, the public methods' payload] }
function TTyAdvanceChart.TreemapViewPayload(const AType: string; ASeries: Integer;
  const AId: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Strings['type'] := AType;
  Result.Strings['from'] := 'ec_' + IntToStr(FInstanceNo) + '_treemap' + IntToStr(ASeries);
  Result.Strings['seriesId'] := SeriesModelId(ASeries);
  Result.Strings['targetNode'] := AId;
end;

{ [R2-I1] THE VIEW'S OWN ROAM DISPATCH (TreemapView._onPan's treemapMove,
  _onZoom's treemapRender): {type, from: the view's uid, seriesId, rootRect}
  -- and AJs, the same as the event prints it (JavaScript's numbers) [was:
  {type, seriesIndex, rootRect}, the public method's] }
function TTyAdvanceChart.TreemapRoamPayload(const AType: string; ASeries: Integer;
  AX, AY, AW, AH: Double; out AJs: string): TJSONObject;
var r: TJSONObject; from: string;
begin
  from := 'ec_' + IntToStr(FInstanceNo) + '_treemap' + IntToStr(ASeries);
  Result := TJSONObject.Create;
  Result.Strings['type'] := AType;
  Result.Strings['from'] := from;
  Result.Strings['seriesId'] := SeriesModelId(ASeries);
  r := TJSONObject.Create;
  r.Floats['x'] := AX;
  r.Floats['y'] := AY;
  r.Floats['width'] := AW;
  r.Floats['height'] := AH;
  Result.Objects['rootRect'] := r;
  AJs := '{"type":"' + AType + '","from":"' + StringToJSONString(from)
    + '","seriesId":"' + StringToJSONString(SeriesModelId(ASeries))
    + '","rootRect":{"x":' + TyJsNumberToString(AX) + ',"y":' + TyJsNumberToString(AY)
    + ',"width":' + TyJsNumberToString(AW) + ',"height":' + TyJsNumberToString(AH) + '}}';
end;

function TTyAdvanceChart.TreemapZoomToNode(ASeriesIndex, ARow: Integer): Boolean;
var p: TJSONObject; slot: Integer;
begin
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if slot < 0 then Exit;
  p := TreemapPayload('treemapZoomToNode', ASeriesIndex, HierIdOfRow(slot, ARow));
  try
    Result := DoTreemapAction('treemapZoomToNode', p);
    EmitUpdated;
  finally
    p.Free;
  end;
end;

function TTyAdvanceChart.TreemapRootToNode(ASeriesIndex, ARow: Integer): Boolean;
var p: TJSONObject; slot: Integer;
begin
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if slot < 0 then Exit;
  p := TreemapPayload('treemapRootToNode', ASeriesIndex, HierIdOfRow(slot, ARow));
  try
    Result := DoTreemapAction('treemapRootToNode', p);
    EmitUpdated;
  finally
    p.Free;
  end;
end;

function TTyAdvanceChart.TreemapMoveTo(ASeriesIndex: Integer; AX, AY, AW, AH: Double;
  AZoom: Boolean): Boolean;
var
  p, r: TJSONObject;
  t: string;
begin
  if AZoom then t := 'treemapRender' else t := 'treemapMove';
  p := TJSONObject.Create;
  try
    p.Strings['type'] := t;
    p.Integers['seriesIndex'] := ASeriesIndex;
    r := TJSONObject.Create;
    r.Floats['x'] := AX;
    r.Floats['y'] := AY;
    r.Floats['width'] := AW;
    r.Floats['height'] := AH;
    p.Objects['rootRect'] := r;
    Result := DoTreemapAction(t, p);
    EmitUpdated;
  finally
    p.Free;
  end;
end;

function TTyAdvanceChart.TmRowsOf(ASeries: Integer; out ASlot: Integer): Boolean;
begin
  ASlot := SlotOfSeries(ASeries);
  Result := (ASlot >= 0) and (ASlot <= High(FTreemaps)) and FTreemaps[ASlot].Valid;
end;

function TTyAdvanceChart.TreemapAnimating(ASeriesIndex: Integer): Boolean;
begin
  Result := (ASeriesIndex >= 0) and (ASeriesIndex <= High(FTmAnim))
    and (FTmAnim[ASeriesIndex].Wrap <> nil) and FTmAnim[ASeriesIndex].Wrap.Live;
end;

function TTyAdvanceChart.TreemapAnimProxy(ASeriesIndex, ARow: Integer;
  const AKind: string): TTyChartAnimProxy;
begin
  Result := nil;
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FTmAnim)) then Exit;
  if ARow < 0 then Exit;
  if (AKind = 'group') and (ARow <= High(FTmAnim[ASeriesIndex].Groups)) then
    Result := FTmAnim[ASeriesIndex].Groups[ARow]
  { [R2-C] a deleted group by its OLD row }
  else if AKind = 'delGroup' then
  begin
    if FTmAnim[ASeriesIndex].Map <> nil then
    begin
      if ARow <= High(FTmAnim[ASeriesIndex].OldGroups) then
        Result := FTmAnim[ASeriesIndex].OldGroups[ARow];
    end
    else if (ARow <= High(FTmAnim[ASeriesIndex].GhostGroup))
      and FTmAnim[ASeriesIndex].GhostGroup[ARow] then
      Result := FTmAnim[ASeriesIndex].Groups[ARow];
  end
  else if (AKind = 'bg') and (ARow <= High(FTmAnim[ASeriesIndex].Rects)) then
    Result := FTmAnim[ASeriesIndex].Rects[ARow][0]
  else if (AKind = 'ct') and (ARow <= High(FTmAnim[ASeriesIndex].Rects)) then
    Result := FTmAnim[ASeriesIndex].Rects[ARow][1]
  else if (AKind = 'label') and (ARow <= High(FTmAnim[ASeriesIndex].Labels)) then
    Result := FTmAnim[ASeriesIndex].Labels[ARow][0]
  else if (AKind = 'upper') and (ARow <= High(FTmAnim[ASeriesIndex].Labels)) then
    Result := FTmAnim[ASeriesIndex].Labels[ARow][1];
end;

function TTyAdvanceChart.TreemapGhostCount(ASeriesIndex: Integer): Integer;
begin
  Result := 0;
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FTmAnim)) then
    Result := Length(FTmAnim[ASeriesIndex].Ghosts);
end;

function TTyAdvanceChart.TreemapGhost(ASeriesIndex, AIndex: Integer;
  out ARow, AKind: Integer): TTyChartAnimProxy;
begin
  Result := nil;
  ARow := -1;
  AKind := -1;
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FTmAnim)) then Exit;
  if (AIndex < 0) or (AIndex > High(FTmAnim[ASeriesIndex].Ghosts)) then Exit;
  ARow := FTmAnim[ASeriesIndex].Ghosts[AIndex].Row;
  AKind := FTmAnim[ASeriesIndex].Ghosts[AIndex].Kind;
  Result := FTmAnim[ASeriesIndex].Ghosts[AIndex].P;
end;

{ ---- the gestures ---- }

procedure TTyAdvanceChart.SunburstClick(ASeries, ARow: Integer);
var
  slot, vr, target, k: Integer;
  p: TJSONObject;
  nc: string;
  hs: TTyIntegerArray;
begin
  slot := SlotOfSeries(ASeries);
  if (slot < 0) or (slot > High(FSunbursts)) or not FSunbursts[slot].Valid then Exit;
  vr := FSunbursts[slot].ViewRoot;
  target := -1;
  if ARow = 0 then
  begin
    { THE RETURN CIRCLE: every handler its renders added, in order, each to
      the parent it was bound to -- unless that is the view root by then }
    if vr <= 0 then Exit;
    hs := nil;
    if ASeries <= High(FSunHandlers) then hs := Copy(FSunHandlers[ASeries]);
    for k := 0 to High(hs) do
    begin
      slot := SlotOfSeries(ASeries);
      if (slot < 0) or (slot > High(FSunbursts)) or not FSunbursts[slot].Valid then Exit;
      if (hs[k] < 0) or (hs[k] = FSunbursts[slot].ViewRoot) then Continue;
      p := TJSONObject.Create;
      try
        p.Strings['type'] := 'sunburstRootToNode';
        p.Integers['seriesIndex'] := ASeries;
        p.Strings['targetNode'] := HierIdOfRow(slot, hs[k]);
        DoSunAction(p);
        EmitUpdated;
      finally
        p.Free;
      end;
    end;
    Exit;
  end
  else
  begin
    { a piece of the view: its nodeClick, item -> level -> series }
    if (ARow > High(FSunbursts[slot].Nodes)) or not FSunbursts[slot].Nodes[ARow].Placed then Exit;
    nc := TySunburstNodeClick(FSunbursts[slot], ARow);
    { 'link' opens a window upstream: nothing here }
    if nc <> 'rootToNode' then Exit;
    target := ARow;
  end;
  { _rootToNode: not to the view root itself }
  if (target < 0) or (target = vr) then Exit;
  p := TJSONObject.Create;
  try
    p.Strings['type'] := 'sunburstRootToNode';
    p.Integers['seriesIndex'] := ASeries;
    p.Strings['targetNode'] := HierIdOfRow(slot, target);
    DoSunAction(p);
    EmitUpdated;
  finally
    p.Free;
  end;
end;

procedure TTyAdvanceChart.TreemapClick(ASeries, AX, AY: Integer);
var
  slot, target: Integer;
  d: TJSONData;
  nc: string;
  p: TJSONObject;
begin
  if not TmRowsOf(ASeries, slot) then Exit;
  { _state 'animating': a click does nothing }
  if TreemapAnimating(ASeries) then Exit;
  { nodeClick is the series' own (get(.., true)): absent 'zoomToNode';
    falsy, nothing }
  nc := 'zoomToNode';
  d := FTreemaps[slot].Series.Find('nodeClick');
  if d <> nil then
  begin
    if d.JSONType = jtString then nc := d.AsString
    else if (d.JSONType = jtBoolean) and d.AsBoolean then nc := 'true'
    else if (d.JSONType = jtNumber) and (d.AsFloat <> 0) and not IsNan(d.AsFloat) then nc := 'true'
    else if d.JSONType in [jtObject, jtArray] then nc := 'true'
    else nc := '';
  end;
  if nc = '' then Exit;
  if ASeries > High(FTmHave) then Exit;
  target := TyTreemapFindTarget(FTreemaps[slot], FTmHave[ASeries], AX, AY);
  if target < 0 then Exit;
  if FTreemaps[slot].Nodes[target].IsLeafRoot then
    p := TreemapViewPayload('treemapRootToNode', ASeries, HierIdOfRow(slot, target))
  else if nc = 'zoomToNode' then
    p := TreemapViewPayload('treemapZoomToNode', ASeries, HierIdOfRow(slot, target))
  else
    { 'link' opens a window upstream: nothing here }
    Exit;
  try
    DoTreemapAction(p.Strings['type'], p);
    EmitUpdated;
  finally
    p.Free;
  end;
end;

procedure TTyAdvanceChart.TreemapCrumbSelect(ASeries, AIndex: Integer);
var
  slot, row: Integer;
  p: TJSONObject;
begin
  if not TmRowsOf(ASeries, slot) then Exit;
  if TreemapAnimating(ASeries) then Exit;
  if (AIndex < 0) or (AIndex > High(FTreemaps[slot].Crumbs)) then Exit;
  row := FTreemaps[slot].Crumbs[AIndex].Row;
  if HierAbove(FTreemaps[slot].Hier, FTreemaps[slot].ViewRoot, row) then
    p := TreemapViewPayload('treemapRootToNode', ASeries, HierIdOfRow(slot, row))
  else
    p := TreemapViewPayload('treemapZoomToNode', ASeries, HierIdOfRow(slot, row));
  try
    DoTreemapAction(p.Strings['type'], p);
    EmitUpdated;
  finally
    p.Free;
  end;
end;

function TTyAdvanceChart.TreemapRoamOk(ASlot: Integer; AZoom: Boolean): Boolean;
var d: TJSONData; s: string;
begin
  Result := False;
  if (ASlot > High(FTreemaps)) or not FTreemaps[ASlot].Valid then Exit;
  { roam: true by default -- both; 'scale' / 'zoom' the wheel, 'move' /
    'pan' the drag; anything else neither }
  d := FTreemaps[ASlot].Series.Find('roam');
  if d = nil then Exit(True);
  if (d.JSONType = jtBoolean) then Exit(d.AsBoolean);
  if d.JSONType <> jtString then Exit;
  s := d.AsString;
  if AZoom then Result := (s = 'scale') or (s = 'zoom')
  else Result := (s = 'move') or (s = 'pan');
end;

{ RoamController's pan: dx, dy since the last move; past 3 px the root moves
  by them (treemapMove), else they are lost }
function TTyAdvanceChart.TreemapPan(ASeries, ADX, ADY: Integer): Boolean;
var
  slot: Integer;
  nd: TTyTreemapNode;
  js: string;
  p: TJSONObject;
begin
  Result := False;
  if not TmRowsOf(ASeries, slot) then Exit;
  if TreemapAnimating(ASeries) then Exit;
  if not ((Abs(ADX) > 3) or (Abs(ADY) > 3)) then Exit;
  nd := FTreemaps[slot].Nodes[0];
  { the view's own payload, the event's numbers as JavaScript prints them }
  p := TreemapRoamPayload('treemapMove', ASeries, nd.X + ADX, nd.Y + ADY, nd.W, nd.H, js);
  try
    DoTreemapAction(p.Strings['type'], p, js);
    Result := True;
    EmitUpdated;
  finally
    p.Free;
  end;
end;

{ RoamController's zoom: the root rect scaled about the pointer, in the
  container's coordinates, by the clamped zoom over the current one
  (treemapRender) }
function TTyAdvanceChart.TreemapWheel(ASeries: Integer; AScale: Double; AX, AY: Integer): Boolean;
var
  slot: Integer;
  nd: TTyTreemapNode;
  bx: TTyXYWH;
  cur, nz, zs, mx, my, m4, m5, x, y, w, h: Double;
  js: string;
  p: TJSONObject;
begin
  Result := False;
  if not TmRowsOf(ASeries, slot) then Exit;
  if TreemapAnimating(ASeries) then Exit;
  nd := FTreemaps[slot].Nodes[0];
  bx := FTreemaps[slot].Box;
  cur := TyTreemapCurrentZoom(bx.W, bx.H, nd.W, nd.H);
  nz := TyTreemapClampZoom(FTreemaps[slot], cur * AScale);
  zs := nz / cur;
  mx := AX - bx.X;
  my := AY - bx.Y;
  { translate(-m), scale, translate(m); BoundingRect.applyTransform }
  m4 := (-mx) * zs + mx;
  m5 := (-my) * zs + my;
  x := nd.X * zs + m4;
  y := nd.Y * zs + m5;
  w := nd.W * zs;
  h := nd.H * zs;
  if w < 0 then
  begin
    x := x + w;
    w := -w;
  end;
  if h < 0 then
  begin
    y := y + h;
    h := -h;
  end;
  p := TreemapRoamPayload('treemapRender', ASeries, x, y, w, h, js);
  try
    DoTreemapAction(p.Strings['type'], p, js);
    Result := True;
    EmitUpdated;
  finally
    p.Free;
  end;
end;

{ ---- a treemap's drill-down (TreemapView._doRender / _doAnimation) ---- }

function TmProxy(AAnim: TTyAnimation; ASeries, ARow: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  Result := TTyChartAnimProxy.Create(ASeries, ARow, ARole);
  Result.Animation := AAnim;
end;

function TmNum(const AKey: string; AValue: Double): TTyAnimProp;
begin
  Result := TyAnimProp(AKey, TyAnimNum(AValue));
end;

{ a group's x: `thisLayout.x || 0` }
function TmOr0(AValue: Double): Double;
begin
  if IsNan(AValue) then Result := 0 else Result := AValue;
end;

procedure TTyAdvanceChart.TmAnimDrop(ASeries: Integer);
var k, j: Integer;
begin
  if (ASeries < 0) or (ASeries > High(FTmAnim)) then Exit;
  { the proxies before their wrap: a proxy freed stops its animators, and a
    stopped one counts down on the wrap }
  for k := 0 to High(FTmAnim[ASeries].Groups) do FreeAndNil(FTmAnim[ASeries].Groups[k]);
  for k := 0 to High(FTmAnim[ASeries].OldGroups) do FreeAndNil(FTmAnim[ASeries].OldGroups[k]);
  for k := 0 to High(FTmAnim[ASeries].Rects) do
    for j := 0 to 1 do FreeAndNil(FTmAnim[ASeries].Rects[k][j]);
  for k := 0 to High(FTmAnim[ASeries].Labels) do
    for j := 0 to 1 do FreeAndNil(FTmAnim[ASeries].Labels[k][j]);
  for k := 0 to High(FTmAnim[ASeries].Ghosts) do
  begin
    FreeAndNil(FTmAnim[ASeries].Ghosts[k].P);
    FreeAndNil(FTmAnim[ASeries].Ghosts[k].LP);
  end;
  FreeAndNil(FTmAnim[ASeries].Wrap);
  FTmAnim[ASeries] := Default(TTyTmAnim);
end;

procedure TTyAdvanceChart.TmAnimDropAll;
var k: Integer;
begin
  for k := 0 to High(FTmAnim) do TmAnimDrop(k);
  FTmAnim := nil;
end;

function TTyAdvanceChart.TmAnimAny: Boolean;
var k: Integer;
begin
  Result := False;
  for k := 0 to High(FTmAnim) do
    if (Length(FTmAnim[k].Groups) > 0) or (Length(FTmAnim[k].Ghosts) > 0) then Exit(True);
end;

{ THE WRAP'S END: renderFinally -- the deleted elements leave, the ones
  moved out of the canvas become invisible -- and _state is 'ready' again.
  The proxies stay: an element rests where its last step put it. }
procedure TTyAdvanceChart.TmWrapCheck;
var si, slot, row: Integer; anyChange: Boolean;
begin
  anyChange := False;
  for si := 0 to High(FTmAnim) do FTmAnim[si].Stepped := True;
  for si := 0 to High(FTmAnim) do
  begin
    if (FTmAnim[si].Wrap = nil) or FTmAnim[si].Wrap.Live then Continue;
    if Length(FTmAnim[si].Ghosts) = 0 then
    begin
      for row := 0 to High(FTmAnim[si].OldGroups) do FreeAndNil(FTmAnim[si].OldGroups[row]);
      slot := SlotOfSeries(si);
      if (slot < 0) or (slot > High(FTreemaps)) then Continue;
      { invisible from now on }
      row := 0;
      while row <= High(FTreemaps[slot].Nodes) do
      begin
        if FTreemaps[slot].Nodes[row].DrawInvisible then
        begin
          FTreemaps[slot].Nodes[row].DrawInvisible := False;
          anyChange := True;
        end;
        Inc(row);
      end;
      Continue;
    end;
    for row := 0 to High(FTmAnim[si].Ghosts) do
    begin
      FreeAndNil(FTmAnim[si].Ghosts[row].P);
      FreeAndNil(FTmAnim[si].Ghosts[row].LP);
    end;
    FTmAnim[si].Ghosts := nil;
    for row := 0 to High(FTmAnim[si].GhostGroup) do
      if FTmAnim[si].GhostGroup[row] then
      begin
        FreeAndNil(FTmAnim[si].Groups[row]);
        FTmAnim[si].GhostGroup[row] := False;
      end;
    for row := 0 to High(FTmAnim[si].OldGroups) do FreeAndNil(FTmAnim[si].OldGroups[row]);
    slot := SlotOfSeries(si);
    if (slot >= 0) and (slot <= High(FTreemaps)) then
      for row := 0 to High(FTreemaps[slot].Nodes) do
        FTreemaps[slot].Nodes[row].DrawInvisible := False;
    anyChange := True;
  end;
  if anyChange then DropStatic;
end;

{ [R2-H] A TREEMAP RENDERED AGAIN (a drill, a zoom, a roam, a setOption, a
  plain render) styles every kept element's words anew -- prepareText ->
  setLabelStyle -> useStyle -- unless the node has moved out of the view
  (thisInvisible: processInvisible, its words left alone). A fade still
  running on those words (the first render's, LabelManager's initProps on
  the text's style) writes into the style the render replaced: the words
  stand at their rest at once. So the set's fades of the rows the render
  styles again end here, before the update carries them; a deleted row's
  goes on with its ghost (TmAnimArm). The set keys a row's words by the
  row alone: a content's words where the old render had them and the
  content is kept, a header's where it had one and the background is kept.
  AMap: a new tree's old row of each new row (nil: the same rows). }
procedure TTyAdvanceChart.TmStrandLabelFades(ASlot: Integer; const AOld: TTyTreemapSolved;
  const AOldHave, AHave: TTyTreemapHave; const AMap: TTyIntegerArray);
var
  si, row, o: Integer;
  p: TTyChartAnimProxy;

  function Was(const AArr: TTyBoolArray; ARow: Integer): Boolean;
  begin
    Result := (ARow >= 0) and (ARow <= High(AArr)) and AArr[ARow];
  end;

begin
  if FAnimSet = nil then Exit;
  si := FBindings[ASlot].SeriesIndex;
  for row := 0 to High(FTreemaps[ASlot].Nodes) do
  begin
    if FTreemaps[ASlot].Nodes[row].Invisible then Continue;
    if AMap = nil then o := row
    else if row <= High(AMap) then o := AMap[row]
    else o := -1;
    if (o < 0) or (o > High(AOld.Nodes)) then Continue;
    if not ((AOld.Nodes[o].HasLabel and Was(AHave.Ct, row) and Was(AOldHave.Ct, o))
      or (AOld.Nodes[o].HasUpper and Was(AHave.Bg, row) and Was(AOldHave.Bg, o))) then Continue;
    p := FAnimSet.DetachProxy(si, o, 'label');
    p.Free;
  end;
end;

procedure TTyAdvanceChart.TmAnimArm(ASlot: Integer; const AView: TTyTreemapView;
  const AOld: TTyTreemapSolved; const AOldHave: TTyTreemapHave; ADirection: Integer;
  const AMap: TTyIntegerArray);
type
  TTask = record
    P: TTyChartAnimProxy;
    Props: TTyAnimProps;
  end;
var
  si, nn, row, k, par, cnt, kind: Integer;
  have: TTyTreemapHave;
  model: TTyAnimModel;
  wrapOn, labelsOn, reRoot, drill, parDel: Boolean;
  v: TTyAnimOptValue;
  dur, pw, ph, tx, ty, ox, oy: Double;
  easing: string;
  cfg: TTyAnimCfg;
  A: TTyTmAnim;
  lastHas: TTyBoolArray;
  lastW, lastH: TTyDoubleArray;
  p: TTyChartAnimProxy;
  tasks: array of TTask;
  TS: ^TTyTreemapSolved;
  oldLabels: array of TTyTmProxyPair;
  el, lel: TTyChartElement;
  props: TTyAnimProps;
  { [R2-C] old -> new rows of a new tree }
  o2n: TTyIntegerArray;
  no: Integer;

  function Was(const AArr: TTyBoolArray; ARow: Integer): Boolean;
  begin
    Result := (ARow >= 0) and (ARow <= High(AArr)) and AArr[ARow];
  end;

  { [R2-C] a new row's old row and an old row's new one: the same row on
    the same tree }
  function OldOf(ARow: Integer): Integer;
  begin
    if AMap = nil then Exit(ARow);
    if (ARow >= 0) and (ARow <= High(AMap)) then Result := AMap[ARow] else Result := -1;
  end;

  function NewOf(ARow: Integer): Integer;
  begin
    if AMap = nil then Exit(ARow);
    if (ARow >= 0) and (ARow <= High(o2n)) then Result := o2n[ARow] else Result := -1;
  end;

  procedure Task(AP: TTyChartAnimProxy; const AProps: TTyAnimProps);
  begin
    SetLength(tasks, Length(tasks) + 1);
    tasks[High(tasks)].P := AP;
    tasks[High(tasks)].Props := AProps;
  end;

  function OldShape(ARow, AKind: Integer): TTyAnimProps;
  var bw: Double;
  begin
    if AKind = 1 then
      Result := TyAnimProps([TmNum('shape.x', 0), TmNum('shape.y', 0),
        TmNum('shape.width', AOld.Nodes[ARow].W), TmNum('shape.height', AOld.Nodes[ARow].H)])
    else
    begin
      bw := AOld.Nodes[ARow].BorderWidth;
      Result := TyAnimProps([TmNum('shape.x', bw), TmNum('shape.y', bw),
        TmNum('shape.width', Math.Max(AOld.Nodes[ARow].W - 2 * bw, Double(0))),
        TmNum('shape.height', Math.Max(AOld.Nodes[ARow].H - 2 * bw, Double(0)))]);
    end;
  end;

  function NewShape(ARow, AKind: Integer): TTyAnimProps;
  var bw: Double;
  begin
    if AKind = 1 then
      Result := TyAnimProps([TmNum('shape.x', 0), TmNum('shape.y', 0),
        TmNum('shape.width', TS^.Nodes[ARow].W), TmNum('shape.height', TS^.Nodes[ARow].H)])
    else
    begin
      bw := TS^.Nodes[ARow].BorderWidth;
      Result := TyAnimProps([TmNum('shape.x', bw), TmNum('shape.y', bw),
        TmNum('shape.width', Math.Max(TS^.Nodes[ARow].W - 2 * bw, Double(0))),
        TmNum('shape.height', Math.Max(TS^.Nodes[ARow].H - 2 * bw, Double(0)))]);
    end;
  end;

  function With1(const AProps: TTyAnimProps; const AKey: string; AValue: Double): TTyAnimProps;
  begin
    Result := Copy(AProps, 0, Length(AProps));
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := TmNum(AKey, AValue);
  end;

  { the old element of a row and kind, and its words, in the list the last
    render built }
  function FindOld(ARow, AKind: Integer; out AEl, ALabel: TTyChartElement;
    out AHasLabel: Boolean): Boolean;
  var j, spec: Integer; e: TTyChartElement;
  begin
    Result := False;
    AHasLabel := False;
    AEl := Default(TTyChartElement);
    ALabel := Default(TTyChartElement);
    if FPaintList = nil then Exit;
    if AKind = 2 then spec := ARow + 1 else spec := Length(AOld.Nodes) + 2 + ARow;
    for j := 0 to FPaintList.Count - 1 do
    begin
      e := FPaintList.Element(j);
      if (e.Anim.Role = carTmRect) and (e.Anim.Series = si) and (e.Anim.Index = ARow)
        and (e.Anim.Sub = AKind - 1) then
      begin
        AEl := e;
        Result := True;
      end
      else if (e.Anim.Role = carLabel) and (e.Datum.SeriesIndex = si)
        and (e.Anim.Index = ARow) and (e.Caption.ItemSpec = spec) then
      begin
        ALabel := e;
        AHasLabel := True;
      end;
    end;
    { a ghost is drawn, never hit }
    AEl.Silent := True;
    ALabel.Silent := True;
  end;

  procedure Visit(ARow: Integer);
  var c, pr: Integer; q: TTyChartAnimProxy;
  begin
    if not Was(have.Group, ARow) then Exit;
    pr := TS^.Hier.Nodes[ARow].Parent;
    { the group }
    if Was(AOldHave.Group, OldOf(ARow)) then
    begin
      q := TmProxy(FAnim, si, ARow, 'tmGroup');
      q.Attr(TyAnimProps([TmNum('x', TmOr0(AOld.Nodes[OldOf(ARow)].X)),
        TmNum('y', TmOr0(AOld.Nodes[OldOf(ARow)].Y))]));
      A.Groups[ARow] := q;
      Task(q, TyAnimProps([TmNum('x', TmOr0(TS^.Nodes[ARow].X)), TmNum('y', TmOr0(TS^.Nodes[ARow].Y))]));
    end
    else if (pr >= 0) and ((not reRoot) or drill) then
    begin
      { new: in from the parent's old corner -- x 0, y its height }
      oy := 0;
      if (not reRoot) and lastHas[pr] then oy := lastH[pr];
      q := TmProxy(FAnim, si, ARow, 'tmGroup');
      q.Attr(TyAnimProps([TmNum('x', 0), TmNum('y', oy)]));
      A.Groups[ARow] := q;
      Task(q, TyAnimProps([TmNum('x', TmOr0(TS^.Nodes[ARow].X)), TmNum('y', TmOr0(TS^.Nodes[ARow].Y))]));
    end
    else
      Task(nil, nil);
    { the background and the content }
    for c := 1 to 2 do
    begin
      if (c = 1) and not Was(have.Bg, ARow) then Continue;
      if (c = 2) and not Was(have.Ct, ARow) then Continue;
      q := TmProxy(FAnim, si, ARow, 'tmRect');
      if ((c = 1) and Was(AOldHave.Bg, OldOf(ARow))) or ((c = 2) and Was(AOldHave.Ct, OldOf(ARow))) then
      begin
        { kept: from its old shape }
        q.Attr(With1(OldShape(OldOf(ARow), c), 'style.opacity', 1));
        if c = 1 then
        begin
          lastHas[ARow] := True;
          lastW[ARow] := AOld.Nodes[OldOf(ARow)].W;
          lastH[ARow] := AOld.Nodes[OldOf(ARow)].H;
        end;
        Task(q, NewShape(ARow, c));
      end
      else if (pr >= 0) and ((not reRoot) or drill) then
      begin
        { new: out of the parent's old corner, fading in }
        ox := 0;
        oy := 0;
        if (not reRoot) and lastHas[pr] then
        begin
          ox := lastW[pr];
          oy := lastH[pr];
        end;
        q.Attr(TyAnimProps([TmNum('shape.x', ox), TmNum('shape.y', oy),
          TmNum('shape.width', 0), TmNum('shape.height', 0), TmNum('style.opacity', 0)]));
        if c = 1 then
        begin
          lastHas[ARow] := True;
          lastW[ARow] := 0;
          lastH[ARow] := 0;
        end;
        Task(q, With1(NewShape(ARow, c), 'style.opacity', 1));
      end
      else
      begin
        { new with no start: it fades in where it is }
        q.Attr(With1(NewShape(ARow, c), 'style.opacity', 0));
        Task(q, TyAnimProps([TmNum('style.opacity', 1)]));
      end;
      A.Rects[ARow][c - 1] := q;
    end;
    for c := 0 to High(TS^.Nodes[ARow].View) do Visit(TS^.Nodes[ARow].View[c]);
  end;

begin
  si := FBindings[ASlot].SeriesIndex;
  { a label's fade is its Text's style's: a deleted element's goes on, a
    kept one's ends with the render's new style (LabelManager starts none
    for a kept one) }
  oldLabels := nil;
  if si <= High(FTmAnim) then
  begin
    oldLabels := FTmAnim[si].Labels;
    FTmAnim[si].Labels := nil;
  end;
  TmAnimDrop(si);
  try
  if not AnimAllowed then Exit;
  TS := @FTreemaps[ASlot];
  nn := Length(TS^.Nodes);
  no := Length(AOld.Nodes);
  if not AOld.Valid then Exit;
  if (AMap = nil) and (no <> nn) then Exit;
  o2n := nil;
  if AMap <> nil then
  begin
    SetLength(o2n, no);
    for row := 0 to no - 1 do o2n[row] := -1;
    for row := 0 to High(AMap) do
      if (AMap[row] >= 0) and (AMap[row] < no) then o2n[AMap[row]] := row;
  end;
  have := TyTreemapHaveOf(TS^, AOldHave, AMap);
  cnt := nn;
  if (ASlot <= High(FStores)) and (FStores[ASlot] <> nil) then cnt := FStores[ASlot].Count;
  model := TyAnimSeriesModel(FOption.Root, si, cnt);
  { hasAnimation is `get('animation')` -- no threshold -- and only a zoom or
    a drill transitions; LabelManager fades a new label whenever the series
    animates }
  { [R2-C] and a setOption's render (no payload), from the old tree }
  wrapOn := ((AView.Kind in [tpkZoomToNode, tpkRootToNode]) or (AMap <> nil))
    and TyAnimOptTruthy(TyAnimGetShallow(model, 'animation'));
  labelsOn := TyAnimIsEnabled(model);
  if not (wrapOn or labelsOn) then Exit;
  if FAnim = nil then FAnim := NewAnimDriver;
  A := Default(TTyTmAnim);
  SetLength(A.Groups, nn);
  SetLength(A.Rects, nn);
  SetLength(A.Labels, nn);
  SetLength(A.GhostGroup, nn);
  A.Old := AOld;
  A.OldHave := AOldHave;
  A.Map := AMap;
  A.O2N := o2n;
  if AMap <> nil then SetLength(A.OldGroups, no);
  if wrapOn then
  begin
    { the duration the series' update one, a function none; the easing its
      animationEasing, else cubicOut }
    v := TyAnimGetShallow(model, 'animationDurationUpdate');
    if v.Kind in [aokNumber, aokBool] then dur := v.Num
    else if v.Kind = aokString then dur := TyJsToNumber(v.Str)
    else dur := 0;
    if IsNan(dur) then dur := 0;
    v := TyAnimGetShallow(model, 'animationEasing');
    if (v.Kind = aokString) and (v.Str <> '') then easing := v.Str else easing := 'cubicOut';
    A.Wrap := TTyTmWrap.Create;
    A.Wrap.Live := True;
    cfg := TyAnimCfg(dur, 0, easing);
    cfg.SetToFinal := True;
    cfg.Done := @A.Wrap.Hit;
    cfg.Aborted := @A.Wrap.Hit;
    reRoot := (AView.Kind = tpkRootToNode) and (AView.Target >= 0);
    drill := reRoot and (ADirection = 1);
    tasks := nil;
    { THE DELETED, first: groups, backgrounds, contents of the old storage
      the render did not take }
    for kind := 0 to 2 do
      for row := 0 to no - 1 do
      begin
        case kind of
          0: if not (Was(AOldHave.Group, row) and not Was(have.Group, NewOf(row))) then Continue;
          1: if not (Was(AOldHave.Bg, row) and not Was(have.Bg, NewOf(row))) then Continue;
        else
          if not (Was(AOldHave.Ct, row) and not Was(have.Ct, NewOf(row))) then Continue;
        end;
        { an element already invisible leaves at the end, unanimated }
        if (kind > 0) and AOld.Nodes[row].Invisible then Continue;
        { the parent group's store: its node's size at its last render }
        if kind = 0 then par := AOld.Hier.Nodes[row].Parent else par := row;
        if par < 0 then Continue;
        parDel := not Was(have.Group, NewOf(par));
        if parDel then
        begin
          pw := AOld.Nodes[par].W;
          ph := AOld.Nodes[par].H;
        end
        else
        begin
          pw := TS^.Nodes[NewOf(par)].W;
          ph := TS^.Nodes[NewOf(par)].H;
        end;
        if kind = 0 then
        begin
          p := TmProxy(FAnim, si, row, 'tmGroup');
          p.Attr(TyAnimProps([TmNum('x', TmOr0(AOld.Nodes[row].X)), TmNum('y', TmOr0(AOld.Nodes[row].Y))]));
          { [R2-C] a new tree's deleted group, by its old row }
          if AMap <> nil then A.OldGroups[row] := p
          else
          begin
            A.GhostGroup[row] := True;
            A.Groups[row] := p;
          end;
          { a drill fades a group's style, which a group has not: it stays }
          if drill then Task(nil, nil)
          else
          begin
            if parDel then
            begin
              tx := 0;
              ty := 0;
            end
            else
            begin
              tx := pw / 2;
              ty := ph / 2;
            end;
            Task(p, TyAnimProps([TmNum('x', tx), TmNum('y', ty)]));
          end;
          Continue;
        end;
        SetLength(A.Ghosts, Length(A.Ghosts) + 1);
        A.Ghosts[High(A.Ghosts)].Row := row;
        A.Ghosts[High(A.Ghosts)].Kind := kind - 1;
        FindOld(row, kind, el, lel, A.Ghosts[High(A.Ghosts)].HasLabel);
        A.Ghosts[High(A.Ghosts)].El := el;
        A.Ghosts[High(A.Ghosts)].LabelEl := lel;
        p := TmProxy(FAnim, si, row, 'tmGhost');
        p.Attr(With1(OldShape(row, kind), 'style.opacity', 1));
        A.Ghosts[High(A.Ghosts)].P := p;
        if (row <= High(oldLabels)) and (oldLabels[row][2 - kind] <> nil) then
        begin
          A.Ghosts[High(A.Ghosts)].LP := oldLabels[row][2 - kind];
          oldLabels[row][2 - kind] := nil;
        end
        { [R2-H] or the first render's fade (LabelManager's, on the set): a
          deleted element is not rendered again, so its words go on fading
          in while it fades out }
        else if A.Ghosts[High(A.Ghosts)].HasLabel and (FAnimSet <> nil) then
          A.Ghosts[High(A.Ghosts)].LP := FAnimSet.DetachProxy(si, row, 'label');
        if drill then
        begin
          if (row = AView.Target) and Was(AOldHave.Group, AView.Target) then
            props := TyAnimProps([TmNum('shape.x', 0), TmNum('shape.y', 0),
              TmNum('shape.width', pw), TmNum('shape.height', ph), TmNum('style.opacity', 0)])
          else
            props := TyAnimProps([TmNum('style.opacity', 0)]);
        end
        else
        begin
          if parDel then
          begin
            tx := 0;
            ty := 0;
          end
          else
          begin
            tx := pw / 2;
            ty := ph / 2;
          end;
          props := TyAnimProps([TmNum('shape.x', tx), TmNum('shape.y', ty),
            TmNum('shape.width', 0), TmNum('shape.height', 0), TmNum('style.opacity', 0)]);
        end;
        Task(p, props);
      end;
    { THE STORAGE, in the render's order }
    SetLength(lastHas, nn);
    SetLength(lastW, nn);
    SetLength(lastH, nn);
    Visit(0);
    { the wrap: done when every element added has finished }
    A.Wrap.Pending := Length(tasks);
    for k := 0 to High(tasks) do
      if (tasks[k].P = nil) or (Length(tasks[k].Props) = 0) then A.Wrap.Hit
      else tasks[k].P.AnimateTo(tasks[k].Props, cfg);
    { THE ELEMENTS MOVED OUT OF THE CANVAS are drawn until the end, in their
      old visual (processInvisible sets none) }
    for row := 0 to nn - 1 do
      if TS^.Nodes[row].Invisible and (Was(have.Bg, row) or Was(have.Ct, row))
        and (OldOf(row) >= 0) and not AOld.Nodes[OldOf(row)].Invisible
        and AOld.Nodes[OldOf(row)].HasLayout then
      begin
        TS^.Nodes[row].DrawInvisible := True;
        TS^.Nodes[row].HasStroke := AOld.Nodes[OldOf(row)].HasStroke;
        TS^.Nodes[row].Stroke := AOld.Nodes[OldOf(row)].Stroke;
        TS^.Nodes[row].HasFill := AOld.Nodes[OldOf(row)].HasFill;
        TS^.Nodes[row].Fill := AOld.Nodes[OldOf(row)].Fill;
        TS^.Nodes[row].HasLabel := AOld.Nodes[OldOf(row)].HasLabel;
        TS^.Nodes[row].LabelText := AOld.Nodes[OldOf(row)].LabelText;
        TS^.Nodes[row].LabelX := AOld.Nodes[OldOf(row)].LabelX - AOld.Nodes[OldOf(row)].TX + TS^.Nodes[row].TX;
        TS^.Nodes[row].LabelY := AOld.Nodes[OldOf(row)].LabelY - AOld.Nodes[OldOf(row)].TY + TS^.Nodes[row].TY;
        TS^.Nodes[row].LabelAH := AOld.Nodes[OldOf(row)].LabelAH;
        TS^.Nodes[row].LabelAV := AOld.Nodes[OldOf(row)].LabelAV;
        TS^.Nodes[row].LabelRaw := AOld.Nodes[OldOf(row)].LabelRaw;
        TS^.Nodes[row].HasLabelRaw := AOld.Nodes[OldOf(row)].HasLabelRaw;
        TS^.Nodes[row].HasUpper := AOld.Nodes[OldOf(row)].HasUpper;
        TS^.Nodes[row].UpperText := AOld.Nodes[OldOf(row)].UpperText;
        TS^.Nodes[row].UpperX := AOld.Nodes[OldOf(row)].UpperX - AOld.Nodes[OldOf(row)].TX + TS^.Nodes[row].TX;
        TS^.Nodes[row].UpperY := AOld.Nodes[OldOf(row)].UpperY - AOld.Nodes[OldOf(row)].TY + TS^.Nodes[row].TY;
        TS^.Nodes[row].UpperCentre := AOld.Nodes[OldOf(row)].UpperCentre;
        TS^.Nodes[row].UpperInside := AOld.Nodes[OldOf(row)].UpperInside;
      end;
  end;
  { [R2-H] A KEPT ELEMENT'S FADE GOES ON ONLY WHERE THE RENDER LEAVES ITS
    WORDS ALONE -- a node moved out of the view (renderNode's thisInvisible:
    processInvisible, no prepareText). Anywhere else the render styles the
    words anew (prepareText -> setLabelStyle -> useStyle), the fade's tween
    writes into the style it replaced and the words are at their rest at
    once: the old proxy goes in the finally below (TmStrandLabelFades does
    the same to the first render's fades on the set). }
  for row := 0 to nn - 1 do
  begin
    if not TS^.Nodes[row].Invisible then Continue;
    par := OldOf(row);
    if (par < 0) or (par > High(oldLabels)) then Continue;
    if Was(have.Ct, row) and Was(AOldHave.Ct, par) and (oldLabels[par][0] <> nil) then
    begin
      A.Labels[row][0] := oldLabels[par][0];
      oldLabels[par][0] := nil;
    end;
    if Was(have.Bg, row) and Was(AOldHave.Bg, par) and (oldLabels[par][1] <> nil) then
    begin
      A.Labels[row][1] := oldLabels[par][1];
      oldLabels[par][1] := nil;
    end;
  end;
  { LabelManager: a label on an element this render made fades in, the
    series' enter timing at its row }
  if labelsOn then
    for row := 0 to nn - 1 do
    begin
      if Was(have.Ct, row) and not Was(AOldHave.Ct, OldOf(row)) and TS^.Nodes[row].HasLabel then
      begin
        p := TmProxy(FAnim, si, row, 'tmLabel');
        p.Attr(TyAnimProps([TmNum('style.opacity', 0)]));
        TyInitProps(p, TyAnimProps([TmNum('style.opacity', 1)]), model, TyAnimCallAt(row));
        A.Labels[row][0] := p;
      end;
      if Was(have.Bg, row) and not Was(AOldHave.Bg, OldOf(row)) and TS^.Nodes[row].HasUpper then
      begin
        p := TmProxy(FAnim, si, row, 'tmUpper');
        p.Attr(TyAnimProps([TmNum('style.opacity', 0)]));
        TyInitProps(p, TyAnimProps([TmNum('style.opacity', 1)]), model, TyAnimCallAt(row));
        A.Labels[row][1] := p;
      end;
    end;
  if Length(FTmAnim) <= si then SetLength(FTmAnim, si + 1);
  FTmAnim[si] := A;
  finally
    for row := 0 to High(oldLabels) do
    begin
      FreeAndNil(oldLabels[row][0]);
      FreeAndNil(oldLabels[row][1]);
    end;
  end;
end;

{ A FRAME OF THE DRILL-DOWN: every node's group where its proxy has it,
  composed down the tree as zrender composes the groups (a local offset
  under 5e-5 is none); every rect's shape and opacity on its group; a
  content's words placed and cut again on the rect it has now, an upper
  label carried by its group; and the deleted elements drawn after the rest }
procedure TTyAdvanceChart.TreemapFrame(AFrame: TTyPaintList);
type
  TTmT = record
    Done, HasT: Boolean;
    TX, TY: Double;
  end;
var
  si, slot, nn, i, row, sub: Integer;
  T: array of TTmT;
  { [R2-C] a new tree's deleted elements: composed down the OLD tree }
  OT: array of TTmT;
  A: ^TTyTmAnim;
  TS: ^TTyTreemapSolved;
  m: ITyTextMeasurer;
  el: TTyChartElement;
  sx, sy, sw, sh, op, lx, ly, ox0, oy0: Double;
  p: TTyChartAnimProxy;
  wtext: string;
  spec: TTyLabelSpec;

  function GroupXY(ARow: Integer; out AX, AY: Double): Boolean;
  begin
    Result := True;
    if (ARow <= High(A^.Groups)) and (A^.Groups[ARow] <> nil) then
    begin
      AX := A^.Groups[ARow].Num('x');
      AY := A^.Groups[ARow].Num('y');
    end
    else if (ARow <= High(A^.GhostGroup)) and A^.GhostGroup[ARow] then
    begin
      AX := TmOr0(A^.Old.Nodes[ARow].X);
      AY := TmOr0(A^.Old.Nodes[ARow].Y);
    end
    else
    begin
      AX := TmOr0(TS^.Nodes[ARow].X);
      AY := TmOr0(TS^.Nodes[ARow].Y);
    end;
  end;

  procedure Compose(ARow: Integer);
  var par: Integer; x, y, ptx, pty: Double; pHas: Boolean;
  begin
    if T[ARow].Done then Exit;
    par := TS^.Hier.Nodes[ARow].Parent;
    if par >= 0 then
    begin
      Compose(par);
      pHas := T[par].HasT;
      ptx := T[par].TX;
      pty := T[par].TY;
    end
    else
    begin
      { the container group at the box }
      pHas := not ((not ((TS^.ContainerX > 5e-5) or (TS^.ContainerX < -5e-5)))
        and (not ((TS^.ContainerY > 5e-5) or (TS^.ContainerY < -5e-5))));
      if pHas then
      begin
        ptx := 0 + (0 + TS^.ContainerX);
        pty := 0 + (0 + TS^.ContainerY);
      end
      else
      begin
        ptx := 0;
        pty := 0;
      end;
    end;
    GroupXY(ARow, x, y);
    if (not ((x > 5e-5) or (x < -5e-5))) and (not ((y > 5e-5) or (y < -5e-5))) then
    begin
      T[ARow].HasT := pHas;
      T[ARow].TX := ptx;
      T[ARow].TY := pty;
    end
    else if not pHas then
    begin
      T[ARow].HasT := True;
      T[ARow].TX := 0 + (0 + x);
      T[ARow].TY := 0 + (0 + y);
    end
    else
    begin
      T[ARow].HasT := True;
      T[ARow].TX := x + ptx;
      T[ARow].TY := y + pty;
    end;
    if not T[ARow].HasT then
    begin
      T[ARow].TX := 0;
      T[ARow].TY := 0;
    end;
    T[ARow].Done := True;
  end;

  { [R2-C] an OLD row's group as a merge's frame has it: the group a new row
    took over (its own composition), else the deleted group itself under
    its old parent -- zrender's composition as Compose's }
  procedure OCompose(ARow: Integer);
  var par, nr: Integer; x, y, ptx, pty: Double; pHas: Boolean;
  begin
    if OT[ARow].Done then Exit;
    nr := -1;
    if ARow <= High(A^.O2N) then nr := A^.O2N[ARow];
    if (nr >= 0) and (nr < nn) and (si <= High(FTmHave)) and (nr <= High(FTmHave[si].Group))
      and FTmHave[si].Group[nr] then
    begin
      Compose(nr);
      OT[ARow] := T[nr];
      Exit;
    end;
    par := A^.Old.Hier.Nodes[ARow].Parent;
    if (par >= 0) and (par <= High(OT)) then
    begin
      OCompose(par);
      pHas := OT[par].HasT;
      ptx := OT[par].TX;
      pty := OT[par].TY;
    end
    else
    begin
      pHas := not ((not ((TS^.ContainerX > 5e-5) or (TS^.ContainerX < -5e-5)))
        and (not ((TS^.ContainerY > 5e-5) or (TS^.ContainerY < -5e-5))));
      if pHas then
      begin
        ptx := 0 + (0 + TS^.ContainerX);
        pty := 0 + (0 + TS^.ContainerY);
      end
      else
      begin
        ptx := 0;
        pty := 0;
      end;
    end;
    if (ARow <= High(A^.OldGroups)) and (A^.OldGroups[ARow] <> nil) then
    begin
      x := A^.OldGroups[ARow].Num('x');
      y := A^.OldGroups[ARow].Num('y');
    end
    else
    begin
      x := TmOr0(A^.Old.Nodes[ARow].X);
      y := TmOr0(A^.Old.Nodes[ARow].Y);
    end;
    if (not ((x > 5e-5) or (x < -5e-5))) and (not ((y > 5e-5) or (y < -5e-5))) then
    begin
      OT[ARow].HasT := pHas;
      OT[ARow].TX := ptx;
      OT[ARow].TY := pty;
    end
    else if not pHas then
    begin
      OT[ARow].HasT := True;
      OT[ARow].TX := 0 + (0 + x);
      OT[ARow].TY := 0 + (0 + y);
    end
    else
    begin
      OT[ARow].HasT := True;
      OT[ARow].TX := x + ptx;
      OT[ARow].TY := y + pty;
    end;
    if not OT[ARow].HasT then
    begin
      OT[ARow].TX := 0;
      OT[ARow].TY := 0;
    end;
    OT[ARow].Done := True;
  end;

  procedure RectOf(AP: TTyChartAnimProxy; const AEl: TTyChartElement);
  begin
    if AP <> nil then
    begin
      sx := AP.Num('shape.x');
      sy := AP.Num('shape.y');
      sw := AP.Num('shape.width');
      sh := AP.Num('shape.height');
      op := AP.Num('style.opacity');
    end
    else
    begin
      sx := AEl.Anim.G[0];
      sy := AEl.Anim.G[1];
      sw := AEl.Anim.G[2];
      sh := AEl.Anim.G[3];
      op := AEl.Style.Alpha;
    end;
  end;

  procedure Place(var AEl: TTyChartElement; ARow: Integer);
  begin
    Compose(ARow);
    AEl.Shape.Bounds := TyRectF(sx + T[ARow].TX, sy + T[ARow].TY,
      (sx + sw) + T[ARow].TX, (sy + sh) + T[ARow].TY);
    AEl.Style.Alpha := op;
  end;

  procedure Words(var ALabel: TTyChartElement; const ASolved: TTyTreemapSolved; ARow: Integer);
  var dx, dy: Double;
  begin
    if (ARow <= High(FTreemapInks[slot].ItemLabels)) then
      spec := FTreemapInks[slot].ItemLabels[ARow]
    else
      spec := FTreemapInks[slot].Label_;
    if m = nil then m := NewTextMeasurer(FLastPPI);
    Compose(ARow);
    dx := ALabel.Caption.X - ALabel.Caption.FixedX;
    dy := ALabel.Caption.Y - ALabel.Caption.FixedY;
    if TyTreemapLabelAt(ASolved, ARow, spec, m, sx * 1 + T[ARow].TX, sy * 1 + T[ARow].TY,
      sw, sh, wtext, lx, ly) and (wtext <> '') then
    begin
      ALabel.Caption.Text := wtext;
      ALabel.Caption.X := lx + dx;
      ALabel.Caption.Y := ly + dy;
    end
    else
      ALabel.Ignore := True;
  end;

begin
  if AFrame = nil then Exit;
  m := nil;
  for si := 0 to High(FTmAnim) do
  begin
    if (Length(FTmAnim[si].Groups) = 0) and (Length(FTmAnim[si].Ghosts) = 0) then Continue;
    slot := SlotOfSeries(si);
    if (slot < 0) or (slot > High(FTreemaps)) or not FTreemaps[slot].Valid then Continue;
    A := @FTmAnim[si];
    TS := @FTreemaps[slot];
    nn := Length(TS^.Nodes);
    if Length(A^.Groups) <> nn then Continue;
    T := nil;
    SetLength(T, nn);
    OT := nil;
    SetLength(OT, Length(A^.Old.Nodes));
    for i := 0 to AFrame.Count - 1 do
    begin
      el := AFrame.Element(i);
      if (el.Anim.Role = carTmRect) and (el.Anim.Series = si) then
      begin
        row := el.Anim.Index;
        sub := el.Anim.Sub;
        if (row < 0) or (row >= nn) or (sub < 0) or (sub > 1) then Continue;
        RectOf(A^.Rects[row][sub], el);
        Place(el, row);
        AFrame.SetElement(i, el);
      end
      else if (el.Anim.Role = carLabel) and (el.Datum.SeriesIndex = si) then
      begin
        row := el.Anim.Index;
        if (row < 0) or (row >= nn) then Continue;
        if el.Caption.ItemSpec = row + 1 then
        begin
          { a content's wtext on the content as it is now }
          if not ((row <= High(TS^.Nodes)) and (Length(TS^.Nodes[row].View) = 0)) then Continue;
          RectOf(A^.Rects[row][1], el);
          if A^.Rects[row][1] = nil then
          begin
            sx := TS^.Nodes[row].BorderWidth;
            sy := sx;
            sw := Math.Max(TS^.Nodes[row].W - 2 * sx, Double(0));
            sh := Math.Max(TS^.Nodes[row].H - 2 * sx, Double(0));
          end;
          Words(el, TS^, row);
          if A^.Labels[row][0] <> nil then el.Style.Alpha := A^.Labels[row][0].Num('style.opacity');
        end
        else if el.Caption.ItemSpec = nn + 2 + row then
        begin
          { a header rides its group }
          Compose(row);
          el.Caption.X := el.Caption.X + (T[row].TX - TS^.Nodes[row].TX);
          el.Caption.Y := el.Caption.Y + (T[row].TY - TS^.Nodes[row].TY);
          if A^.Labels[row][1] <> nil then el.Style.Alpha := A^.Labels[row][1].Num('style.opacity');
        end;
        AFrame.SetElement(i, el);
      end;
    end;
    { THE DELETED, still leaving }
    for i := 0 to High(A^.Ghosts) do
    begin
      if A^.Ghosts[i].El.Anim.Role <> carTmRect then Continue;
      row := A^.Ghosts[i].Row;
      el := A^.Ghosts[i].El;
      RectOf(A^.Ghosts[i].P, el);
      if A^.Map <> nil then
      begin
        { [R2-C] a merge's deleted rect, under the old tree's groups; its
          words ride the rect's corner (the old option is gone: they are
          not cut again) }
        if (row < 0) or (row > High(OT)) then Continue;
        OCompose(row);
        ox0 := el.Shape.Bounds.Left;
        oy0 := el.Shape.Bounds.Top;
        el.Shape.Bounds := TyRectF(sx + OT[row].TX, sy + OT[row].TY,
          (sx + sw) + OT[row].TX, (sy + sh) + OT[row].TY);
        el.Style.Alpha := op;
        AFrame.Add(el);
        if A^.Ghosts[i].HasLabel then
        begin
          ox0 := el.Shape.Bounds.Left - ox0;
          oy0 := el.Shape.Bounds.Top - oy0;
          el := A^.Ghosts[i].LabelEl;
          if A^.Stepped then
          begin
            el.Caption.X := el.Caption.X + ox0;
            el.Caption.Y := el.Caption.Y + oy0;
          end;
          if A^.Ghosts[i].LP <> nil then el.Style.Alpha := A^.Ghosts[i].LP.Num('style.opacity');
          AFrame.Add(el);
        end;
        Continue;
      end;
      Place(el, row);
      AFrame.Add(el);
      if A^.Ghosts[i].HasLabel then
      begin
        el := A^.Ghosts[i].LabelEl;
        if (A^.Ghosts[i].Kind = 1) and not A^.Stepped then
        begin
          { not dirty yet: the words cut to the rect it has, where they were }
          ox0 := el.Caption.X;
          oy0 := el.Caption.Y;
          Words(el, A^.Old, row);
          if not el.Ignore then
          begin
            el.Caption.X := ox0;
            el.Caption.Y := oy0;
          end;
        end
        else if A^.Ghosts[i].Kind = 1 then
          Words(el, A^.Old, row)
        else if not A^.Stepped then
        else
        begin
          Compose(row);
          el.Caption.X := el.Caption.X + (T[row].TX - A^.Old.Nodes[row].TX);
          el.Caption.Y := el.Caption.Y + (T[row].TY - A^.Old.Nodes[row].TY);
        end;
        if A^.Ghosts[i].LP <> nil then el.Style.Alpha := A^.Ghosts[i].LP.Num('style.opacity');
        AFrame.Add(el);
      end;
    end;
  end;
end;

{ ---- a treemap's hover: in place, in the static list ---- }

function TTyAdvanceChart.IsTreemapDatum(const ADatum: TTyChartDatumRef): Boolean;
var slot: Integer;
begin
  Result := False;
  if (ADatum.SeriesIndex < 0) or (ADatum.DataIndex < 0) or ADatum.IsEdge then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  Result := (slot >= 0) and (FBindings[slot].SeriesType = TyTreemapSeriesTypeName);
end;

{ [F2a] A HOVERED BREADCRUMB ITEM: the item's emphasis state -- its declared
  fill (Breadcrumb.ts:189, the skin's hover tone by default), its words'
  declared ink, both up by ten (the default proxy's z2 lift); a solve draws
  new items, and the hover of an older one is gone }
procedure TTyAdvanceChart.TmCrumbStates(AList: TTyPaintList);
begin
  FTmCrumbDirty := False;
  if AList = nil then Exit;
  { a state write: journaled [P2] }
  AList.JournalRecord(True);
  try
    TmCrumbWrite(AList);
  finally
    AList.JournalRecord(False);
  end;
end;

procedure TTyAdvanceChart.TmCrumbWrite(AList: TTyPaintList);
var
  i, k, hi, slot: Integer;
  el, cap: TTyChartElement;
begin
  if (FTmCrumbHoverS < 0) or (FTmCrumbHoverGen <> FTmCrumbGen) then Exit;
  slot := SlotOfSeries(FTmCrumbHoverS);
  if (slot < 0) or (slot > High(FTreemapInks)) then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Anim.Role <> carTmCrumb) or (el.Anim.Series <> FTmCrumbHoverS)
      or (el.Anim.Index <> FTmCrumbHoverK) then Continue;
    el.Style.HasFill := True;
    el.Style.FillColor := FTreemapInks[slot].CrumbEmphFill;
    el.Z2 := el.Z2 + TyStZ2EmphasisLift;
    AList.SetElement(i, el);
    { its words: the caption hung off it }
    for k := 0 to AList.Count - 1 do
    begin
      cap := AList.Element(k);
      if cap.Caption.FontSizeLogical <= 0 then Continue;
      hi := cap.Caption.LmHostPlus1 - 1;
      if hi <> i then Continue;
      cap.Z2 := cap.Z2 + TyStZ2EmphasisLift;
      if FTreemapInks[slot].CrumbEmphHasText then
        cap.Caption.Colour := FTreemapInks[slot].CrumbEmphText;
      AList.SetElement(k, cap);
    end;
  end;
end;

{ [F2a, old deferral #36] the labels' opacity, the node's style.opacity }
procedure TTyAdvanceChart.TmLabelOpacity(AList: TTyPaintList);
var
  i, hi, slot, s, row: Integer;
  el: TTyChartElement;
  pe, host: PTyChartElement;
  item, ser: TJSONObject;
  v: Double;
  has: Boolean;
begin
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    pe := AList.Ref(i);
    if pe^.Caption.FontSizeLogical <= 0 then Continue;
    hi := pe^.Caption.LmHostPlus1 - 1;
    if (hi < 0) or (hi >= AList.Count) then Continue;
    host := AList.Ref(hi);
    if host^.Anim.Role <> carTmRect then Continue;
    s := host^.Anim.Series;
    slot := SlotOfSeries(s);
    if (slot < 0) or (slot > High(FTreemaps)) or not FTreemaps[slot].Valid then Continue;
    row := host^.Anim.Index;
    item := nil;
    if (row >= 0) and (row <= High(FTreemaps[slot].Hier.Nodes))
      and (FTreemaps[slot].Hier.Nodes[row].Item is TJSONObject) then
      item := TJSONObject(FTreemaps[slot].Hier.Nodes[row].Item);
    ser := StSeriesNode(s);
    { the raw item's style over the series' -- never a level's }
    v := TyStReadNumber([item, ser], ['itemStyle', 'opacity'], has);
    if not has or IsNan(v) then Continue;
    el := pe^;
    el.Style.Alpha := v;
    AList.SetElement(i, el);
  end;
end;

procedure TTyAdvanceChart.SolveGraphCategoryColours;
var
  shown: array of Boolean;
  fallback: TTyChartColorArray;
  i, n: Integer;
begin
  FGraphCatColours := nil;
  if FOption = nil then Exit;
  n := FOption.ComponentCount('series');
  SetLength(shown, n);
  for i := 0 to n - 1 do shown[i] := True;
  for i := 0 to High(FBindings) do
    if (FBindings[i].SeriesIndex >= 0) and (FBindings[i].SeriesIndex < n) then
      shown[FBindings[i].SeriesIndex] := not FBindings[i].Hidden;
  { THE THEME'S NINE, standing where upstream's default palette stands -- the
    same nine every series colour falls back to. }
  SetLength(fallback, 9);
  for i := 0 to 8 do fallback[i] := TTyChartColor(ThemeRampColor(i));
  FGraphCatColours := TyGraphCategoryColours(FOption, shown, fallback);
end;

{ THE TREES: each laid out in its box on the whole canvas, as a pie is.
  [Batch 73] }
procedure TTyAdvanceChart.SolveTrees(APPI: Integer);
var
  i: Integer;
  ref: TTyXYWH;
  fc: Boolean;
  tog: TTyBoolArray;
begin
  FTrees := nil;
  SetLength(FTrees, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FTrees[i] := Default(TTyTreeSolved);
    if FBindings[i].SeriesType <> TyTreeSeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    { IN A MATRIX CELL OR A CALENDAR DAY [Batch 151]: commonLayout's box in
      the refContainer; a cell of no position draws nothing }
    if SeriesBoxRef(i, False, ref, fc) then
    begin
      if not TyXYWHHasSize(ref) then Continue;
      tog := nil;
      if FBindings[i].SeriesIndex <= High(FTreeToggled) then
        tog := FTreeToggled[FBindings[i].SeriesIndex];
      FTrees[i] := TyTreeSolve(FOption, FBindings[i].SeriesIndex, ref, APPI, tog);
    end
    else if FBindings[i].SeriesIndex <= High(FTreeToggled) then
      FTrees[i] := TyTreeSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI,
        FTreeToggled[FBindings[i].SeriesIndex])
    else
      FTrees[i] := TyTreeSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI);
    if FTrees[i].Valid then SolveTreeView(i, APPI);
  end;
end;

procedure TTyAdvanceChart.SolveTreeView(ASlot, APPI: Integer);
var
  si, row: Integer;
  node: TJSONData;
  root: TJSONObject;
  spec: TTyGraphSpec;
  mnX, mnY, mxX, mxY, one: Double;
  box: TTyXYWH;
  any: Boolean;
  centre: TTyGraphCentre;
  zoom: Double;
begin
  si := FBindings[ASlot].SeriesIndex;
  if Length(FTreeViews) < Length(FBindings) then
  begin
    SetLength(FTreeViews, Length(FBindings));
    SetLength(FTreeSpecs, Length(FBindings));
  end;
  FreeAndNil(FTreeViews[ASlot]);
  { the view's options, read as a graph's; a tree's nodeScaleRatio is 0.4 }
  spec := TyGraphSpecDefault;
  spec.NodeScaleRatio := 0.4;
  node := FOption.ComponentAt('series', si);
  root := nil;
  if FOption.Root is TJSONObject then root := TJSONObject(FOption.Root);
  if (node <> nil) and (node.JSONType = jtObject) then
  begin
    TyGraphReadRoamOptions(TJSONObject(node), root, spec);
    { a tree's roamTrigger defaults to 'global': a drag anywhere pans }
    if TJSONObject(node).Find('roamTrigger') = nil then spec.RoamGlobal := True;
  end;
  spec.Z := FTrees[ASlot].Spec.Z;
  FTreeSpecs[ASlot] := spec;
  { the bounding box of the placed nodes, local to the main group }
  any := False;
  mnX := Infinity; mnY := Infinity; mxX := NegInfinity; mxY := NegInfinity;
  for row := 0 to High(FTrees[ASlot].Pos) do
    if FTrees[ASlot].Pos[row].Placed then
    begin
      any := True;
      if FTrees[ASlot].Pos[row].X < mnX then mnX := FTrees[ASlot].Pos[row].X;
      if FTrees[ASlot].Pos[row].X > mxX then mxX := FTrees[ASlot].Pos[row].X;
      if FTrees[ASlot].Pos[row].Y < mnY then mnY := FTrees[ASlot].Pos[row].Y;
      if FTrees[ASlot].Pos[row].Y > mxY then mxY := FTrees[ASlot].Pos[row].Y;
    end;
  if not any then Exit;
  if APPI > 0 then one := APPI / 96 else one := 1;
  { no extent on an axis: the box the view last had there, else one either
    side }
  if mxX - mnX = 0 then
  begin
    if (si <= High(FTreeBoxHas)) and FTreeBoxHas[si] then
    begin
      mnX := FTreeBox[si].X;
      mxX := FTreeBox[si].X + FTreeBox[si].W;
    end
    else
    begin
      mnX := mnX - one;
      mxX := mxX + one;
    end;
  end;
  if mxY - mnY = 0 then
  begin
    if (si <= High(FTreeBoxHas)) and FTreeBoxHas[si] then
    begin
      mnY := FTreeBox[si].Y;
      mxY := FTreeBox[si].Y + FTreeBox[si].H;
    end
    else
    begin
      mnY := mnY - one;
      mxY := mxY + one;
    end;
  end;
  box := TyXYWH(mnX, mnY, mxX - mnX, mxY - mnY);
  if si > High(FTreeBox) then
  begin
    SetLength(FTreeBox, si + 1);
    SetLength(FTreeBoxHas, si + 1);
  end;
  FTreeBox[si] := box;
  FTreeBoxHas[si] := True;
  FTreeViews[ASlot] := TTyGraphView.CreateXYWH(box, box);
  { the roam's write-back, else the option's }
  if (si <= High(FTreeRoam)) and FTreeRoam[si].Valid then
  begin
    centre := FTreeRoam[si].Centre;
    zoom := FTreeRoam[si].Zoom;
  end
  else
  begin
    centre := spec.Centre;
    zoom := spec.Zoom;
  end;
  FTreeViews[ASlot].SetRoam(centre, zoom, spec.HasLimit, spec.LimitMin, spec.LimitMax);
  TyTreeApplyView(FTrees[ASlot], FTreeViews[ASlot].OverallScaleX,
    FTreeViews[ASlot].OverallX, FTreeViews[ASlot].OverallY,
    FTreeViews[ASlot].NodeScale(spec.NodeScaleRatio));
end;

function TTyAdvanceChart.TreeDispatchRoam(const APayload: TTyGraphRoamPayload): Boolean;
var
  i, si: Integer;
  p: TTyGraphRoamPayload;
  m: ITyTextMeasurer;
begin
  Result := False;
  if APayload.HasZoom and (IsNan(APayload.Zoom) or IsInfinite(APayload.Zoom)
    or (APayload.Zoom <= 0)) then Exit;
  if APayload.HasPan and (IsNan(APayload.DX) or IsNan(APayload.DY)) then Exit;
  for i := 0 to High(FTreeViews) do
  begin
    if FTreeViews[i] = nil then Continue;
    si := FBindings[i].SeriesIndex;
    if (APayload.SeriesIndex >= 0) and (si <> APayload.SeriesIndex) then Continue;
    if Length(FTreeRoam) <= si then SetLength(FTreeRoam, si + 1);
    TyGraphRoamStep(FTreeViews[i], FTreeSpecs[i], APayload, FTreeRoam[si]);
    Result := True;
    if Assigned(FOnTreeRoam) then
    begin
      p := APayload;
      p.SeriesIndex := si;
      FOnTreeRoam(Self, p);
    end;
  end;
  if not Result then Exit;
  { A NEW LAYOUT, AND AT ONCE: the transform is re-derived from what the roam
    wrote back, and the release that ends a short drag must find the node
    where the pan put it -- upstream's elements are the same objects,
    moved. }
  if FLastPPI <= 0 then
  begin
    Invalidate;
    EmitUpdated;
    Exit;
  end;
  m := NewTextMeasurer(FLastPPI);
  Relayout(nil, FLastRect, FLastPPI, m);
  DropStatic;
  BuildSeriesList(m, FLastPPI);
  { [R2-E] a roam renders no tooltip view: nothing kept }
  TipResetQuiet;
  FZrDirty := True;
  inherited Invalidate;
  { the dispatch's triggerUpdatedEvent [Batch 97] }
  EmitUpdated;
end;

function TTyAdvanceChart.TreeRoam(ASeriesIndex: Integer; ADX, ADY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasPan := True;
  p.DX := ADX;
  p.DY := ADY;
  Result := TreeDispatchRoam(p);
end;

function TTyAdvanceChart.TreeZoom(ASeriesIndex: Integer; AScale, AOriginX,
  AOriginY: Double): Boolean;
var p: TTyGraphRoamPayload;
begin
  p := Default(TTyGraphRoamPayload);
  p.SeriesIndex := ASeriesIndex;
  p.HasZoom := True;
  p.Zoom := AScale;
  p.OriginX := AOriginX;
  p.OriginY := AOriginY;
  Result := TreeDispatchRoam(p);
end;

function TTyAdvanceChart.TreeFlip(ASlot, ADataIndex: Integer): Boolean;
var s: Integer;
begin
  Result := False;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FBindings[ASlot].SeriesType <> TyTreeSeriesTypeName then Exit;
  s := FBindings[ASlot].SeriesIndex;
  if (ASlot > High(FTrees)) or not FTrees[ASlot].Hier.Valid then Exit;
  if (ADataIndex <= 0) or (ADataIndex > High(FTrees[ASlot].Hier.Nodes)) then Exit;
  if s > High(FTreeToggled) then SetLength(FTreeToggled, s + 1);
  if ADataIndex > High(FTreeToggled[s]) then
    SetLength(FTreeToggled[s], Length(FTrees[ASlot].Hier.Nodes));
  FTreeToggled[s][ADataIndex] := not FTreeToggled[s][ADataIndex];
  { the solved flag too, so TreeExpanded answers before the relayout }
  FTrees[ASlot].Hier.Nodes[ADataIndex].Expanded :=
    not FTrees[ASlot].Hier.Nodes[ADataIndex].Expanded;
  Result := True;
  if Assigned(FOnTreeToggle) then FOnTreeToggle(Self, s, ADataIndex);
end;

function TTyAdvanceChart.TreeToggle(ASeriesIndex, ADataIndex: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(FBindings) do
  begin
    if (ASeriesIndex >= 0) and (FBindings[i].SeriesIndex <> ASeriesIndex) then Continue;
    if TreeFlip(i, ADataIndex) then Result := True;
  end;
  if Result then
  begin
    { [F3d] THE ACTION'S UPDATE (update: 'update'): a full update of the
      same option -- the kept nodes slide, the shown ones grow out of their
      parent, the hidden ones shrink into it. [Was: a relayout that snapped.] }
    FullUpdate;
    { the dispatch's triggerUpdatedEvent [Batch 97] }
    EmitUpdated;
  end;
end;

function TTyAdvanceChart.DoTreeToggleAction(APayload: TJSONObject): Boolean;
var
  slots: TTyIntegerArray;
  k: Integer;
  d: TJSONData;
  di: Integer;
begin
  Result := True;
  d := APayload.Find('dataIndex');
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  di := Round(d.AsFloat);
  slots := HierQuery(APayload, TyTreeSeriesTypeName);
  for k := 0 to High(slots) do
    if TreeFlip(slots[k], di) then Result := True;
  FullUpdate;
  EmitUpdated;
end;

function TTyAdvanceChart.TreeExpanded(ASeriesIndex, ADataIndex: Integer): Boolean;
var slot: Integer;
begin
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FTrees)) or not FTrees[slot].Hier.Valid then Exit;
  if (ADataIndex < 0) or (ADataIndex > High(FTrees[slot].Hier.Nodes)) then Exit;
  Result := FTrees[slot].Hier.Nodes[ADataIndex].Expanded;
end;

{ THE SUNBURSTS: laid out on the whole canvas, then coloured in one pass
  whose palette cursor every sunburst in the chart shares -- a second
  sunburst's first root takes the palette's NEXT colour. [Batch 75] }
procedure TTyAdvanceChart.SolveSunbursts(APPI: Integer);
var
  i, k: Integer;
  cur: TTyPaletteCursor;
  pal, ramp: TTyChartColorArray;
  declared: Boolean;
begin
  FSunbursts := nil;
  SetLength(FSunbursts, Length(FBindings));
  cur := TyPaletteStart(nil);
  SetLength(ramp, 9);
  for k := 0 to 8 do ramp[k] := TTyChartColor(ThemeRampColor(k));
  for i := 0 to High(FBindings) do
  begin
    FSunbursts[i] := Default(TTySunburstSolved);
    if FBindings[i].SeriesType <> TySunburstSeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    { THE VIEW ROOT a drill left [Batch 115] }
    k := 0;
    if FBindings[i].SeriesIndex <= High(FSunRoot) then k := FSunRoot[FBindings[i].SeriesIndex];
    FSunbursts[i] := TySunburstSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI, k);
    { renderRollUp: one more handler on the kept piece, or none at the
      root }
    if FSunbursts[i].Valid then
    begin
      if Length(FSunHandlers) <= FBindings[i].SeriesIndex then
        SetLength(FSunHandlers, FBindings[i].SeriesIndex + 1);
      if FSunbursts[i].Nodes[0].Placed and (FSunbursts[i].ViewRoot > 0) then
      begin
        SetLength(FSunHandlers[FBindings[i].SeriesIndex],
          Length(FSunHandlers[FBindings[i].SeriesIndex]) + 1);
        FSunHandlers[FBindings[i].SeriesIndex][High(FSunHandlers[FBindings[i].SeriesIndex])] :=
          FSunbursts[i].Hier.Nodes[FSunbursts[i].ViewRoot].Parent;
      end
      else
        FSunHandlers[FBindings[i].SeriesIndex] := nil;
    end;
    { the return circle's layout outlives a roll-up: containPixel reads it }
    if FSunbursts[i].Valid and FSunbursts[i].Nodes[0].Placed then
    begin
      if Length(FSunVirt) <= FBindings[i].SeriesIndex then
        SetLength(FSunVirt, FBindings[i].SeriesIndex + 1);
      FSunVirt[FBindings[i].SeriesIndex].Has := True;
      FSunVirt[FBindings[i].SeriesIndex].CX := FSunbursts[i].CX;
      FSunVirt[FBindings[i].SeriesIndex].CY := FSunbursts[i].CY;
      FSunVirt[FBindings[i].SeriesIndex].R0 := FSunbursts[i].Nodes[0].R0;
      FSunVirt[FBindings[i].SeriesIndex].R := FSunbursts[i].Nodes[0].R;
    end;
    { the series' own palette, else the chart's, else the theme's ramp }
    pal := TyChartPaletteOf(FOption, FBindings[i].SeriesIndex, declared);
    if not declared then pal := TyChartPaletteOf(FOption, -1, declared);
    if not declared then pal := ramp;
    TySunburstColour(FSunbursts[i], pal, cur);
    { A VISUALMAP RUNS AFTER the sunburst's own visual and overwrites the
      fill of every node it maps -- the label's ink follows the new fill.
      [Batch 77] }
    if (i <= High(FVisualRows)) and (FVisualRows[i] <> nil) then
      for k := 0 to Min(High(FSunbursts[i].Nodes), High(FVisualRows[i])) do
        if FVisualRows[i][k].ColorSet then
          FSunbursts[i].Nodes[k].Fill := TyVisualToChart(FVisualRows[i][k].Color);
  end;
end;

{ THE TREEMAPS: each laid out in its box on the whole canvas, coloured from
  the CHART's palette (a treemap's own `color` is a list its levels map by,
  not a palette), its labels cut to their cells and its breadcrumb found --
  all of which needs the measurer. [Batch 76] }
procedure TTyAdvanceChart.SolveTreemaps(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i, k, dim, si, target: Integer;
  pal: TTyChartColorArray;
  declared: Boolean;
  border: TTyChartColor;
  view: TTyTreemapView;
  prev: TTyTreemapSolved;
  prevHave, have: TTyTreemapHave;
  ref: TTyXYWH;
  boxed, fc: Boolean;
  { [R2-C] a setOption's new tree over the old one }
  keys: TTyStringArray;
  fromOld: Boolean;
  map: TTyIntegerArray;
begin
  FTreemaps := nil;
  FTreemapInks := nil;
  keys := AnimViewKeys;
  for k := 0 to High(keys) do
    if (k <= High(FAnimFresh)) and FAnimFresh[k] then keys[k] := 'n:' + keys[k];
  SetLength(FTreemaps, Length(FBindings));
  SetLength(FTreemapInks, Length(FBindings));
  pal := TyChartPaletteOf(FOption, -1, declared);
  if not declared then
  begin
    SetLength(pal, 9);
    for k := 0 to 8 do pal[k] := TTyChartColor(ThemeRampColor(k));
  end;
  border := TTyChartColor(ActiveController.Model.ResolveStyle(GetStyleTypeKey,
    StyleClass, [tysNormal]).Background.Color);
  for i := 0 to High(FBindings) do
  begin
    FTreemaps[i] := Default(TTyTreemapSolved);
    FTreemapInks[i] := Default(TTyTreemapInk);
    if FBindings[i].SeriesType <> TyTreemapSeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    { [Batch 115] THE VIEW a drill or a roam left, and what this render is
      for (consumed by it); the last solve and storage of the same tree }
    si := FBindings[i].SeriesIndex;
    view := TyTreemapNoView;
    if si <= High(FTmView) then view := FTmView[si];
    prev := Default(TTyTreemapSolved);
    if si <= High(FTmPrev) then prev := FTmPrev[si];
    prevHave := Default(TTyTreemapHave);
    if si <= High(FTmHave) then prevHave := FTmHave[si];
    { IN A MATRIX CELL OR A CALENDAR DAY [Batch 151]: the box in the
      refContainer, the pruning still on the canvas; a cell of no position
      draws nothing }
    boxed := SeriesBoxRef(i, False, ref, fc);
    if boxed then
    begin
      if not TyXYWHHasSize(ref) then Continue;
      FTreemaps[i] := TyTreemapSolve(FOption, si, ref, FLastRect, APPI, view, prev);
    end
    else
      FTreemaps[i] := TyTreemapSolve(FOption, si, FLastRect, APPI, view, prev);
    if not FTreemaps[i].Valid then Continue;
    { [R2-C] A RENDER WITH NO PAYLOAD AFTER A setOption: the same view, a new
      tree -- _doRender's dualTravel pairs its rows with the old tree's by
      getId, the storage it takes is the old render's, and _doAnimation
      transitions it (a view a new id or type made anew has no old tree) }
    fromOld := (not prev.Valid) and (si <= High(FTmOld)) and FTmOld[si].Valid
      and (si <= High(FTmOldHave)) and (si <= High(FTmOldKeys)) and (si <= High(keys))
      and (FTmOldKeys[si] = keys[si]);
    map := nil;
    if fromOld then
    begin
      map := TyTreemapPairRows(FTmOld[si], FTreemaps[i]);
      prevHave := FTmOldHave[si];
    end;
    have := TyTreemapHaveOf(FTreemaps[i], prevHave, map);
    TyTreemapColour(FTreemaps[i], pal, border);
    FTreemapInks[i] := TreemapInk(i);
    dim := -1;
    if FStores[i] <> nil then dim := FStores[i].DimIndexOf('value');
    TyTreemapLabels(FTreemaps[i], FTreemapInks[i].ItemLabels, FStores[i],
      SeriesModelName(FBindings[i].SeriesIndex), dim, AMeasurer);
    { the headers' specs follow the rows' and the breadcrumb's [Batch 78] }
    TyTreemapUpperLabels(FTreemaps[i], Copy(FTreemapInks[i].ItemLabels,
      Length(FTreemaps[i].Nodes) + 1, Length(FTreemaps[i].Nodes)), FStores[i],
      SeriesModelName(FBindings[i].SeriesIndex), dim, AMeasurer);
    { the breadcrumb: on the payload's target, else as found; a picture
      kept keeps its own }
    target := -1;
    if view.Kind in [tpkZoomToNode, tpkRootToNode] then target := view.Target;
    if (view.Kind = tpkKeep) and prev.Valid then FTreemaps[i].Crumbs := prev.Crumbs
    else if boxed then
      TyTreemapBreadcrumb(FTreemaps[i],
        FTreemapInks[i].ItemLabels[Length(FTreemaps[i].Nodes)], AMeasurer,
        ref, FLastRect, target, have, prevHave, prev)
    else
      TyTreemapBreadcrumb(FTreemaps[i],
        FTreemapInks[i].ItemLabels[Length(FTreemaps[i].Nodes)], AMeasurer,
        FLastRect, target, have, prevHave, prev);
    { [R2-H] a render again ends the running fades of the words it styles }
    if (view.Kind <> tpkKeep) and prev.Valid then
      TmStrandLabelFades(i, prev, prevHave, have, nil)
    else if fromOld then
      TmStrandLabelFades(i, FTmOld[si], FTmOldHave[si], have, map);
    { THE DRILL-DOWN of a render for a gesture or an action [Batch 115] }
    if view.Kind = tpkKeep then
    else if prev.Valid and (view.Kind <> tpkNone) then
      TmAnimArm(i, view, prev, prevHave, view.Direction, nil)
    else if fromOld then
      TmAnimArm(i, view, FTmOld[si], FTmOldHave[si], 0, map)
    else
      TmAnimDrop(si);
    if si <= High(FTmOld) then FTmOld[si] := Default(TTyTreemapSolved);
    if Length(FTmView) <= si then
    begin
      k := Length(FTmView);
      SetLength(FTmView, si + 1);
      while k <= si do
      begin
        FTmView[k] := TyTreemapNoView;
        Inc(k);
      end;
    end;
    FTmView[si].ViewRoot := FTreemaps[i].ViewRoot;
    FTmView[si].Kind := tpkNone;
    FTmView[si].Target := -1;
    FTmView[si].Direction := 0;
    if Length(FTmPrev) <= si then SetLength(FTmPrev, si + 1);
    FTmPrev[si] := FTreemaps[i];
    { its own nodes: a node of this solve is changed later (the drill-down's
      DrawInvisible) }
    FTmPrev[si].Nodes := Copy(FTreemaps[i].Nodes, 0, Length(FTreemaps[i].Nodes));
    if Length(FTmHave) <= si then SetLength(FTmHave, si + 1);
    FTmHave[si] := have;
  end;
  { new breadcrumb items: no hover on them [F2a] }
  Inc(FTmCrumbGen);
  { [R2-C] a stash no solve took is stale from now on }
  FTmOld := nil;
  FTmOldHave := nil;
  FTmOldKeys := nil;
  FTmViewKeys := keys;
end;

{ THE SANKEYS: each laid out in its box on the whole canvas, its nodes
  coloured by value over the palette -- the series' `color`, else the
  chart's, else the theme's -- read as zrender parses them, so an alpha
  survives; then the labels placed. [Batch 79] }
procedure TTyAdvanceChart.SolveSankeys(APPI: Integer);
var
  i, k, q: Integer;
  stops: TTyVisualColorArray;
  d, node: TJSONData;
  base, lk: TTyLabelSpec;
  edgeSpecs: TTyLabelSpecArray;
  ls: TTyStyleSet;
  ref: TTyXYWH;
  fc: Boolean;

  procedure StopsOf(AData: TJSONData);
  var q: Integer;
  begin
    stops := nil;
    if AData.JSONType = jtArray then
    begin
      SetLength(stops, AData.Count);
      for q := 0 to AData.Count - 1 do stops[q] := TyVisualParsedStop(AData.Items[q]);
    end
    else
    begin
      SetLength(stops, 1);
      stops[0] := TyVisualParsedStop(AData);
    end;
  end;

begin
  FSankeys := nil;
  FSankeyInks := nil;
  FreeSankeyViews;
  SetLength(FSankeys, Length(FBindings));
  SetLength(FSankeyInks, Length(FBindings));
  SetLength(FSankeyViews, Length(FBindings));
  SetLength(FSankeySpecs, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FSankeys[i] := Default(TTySankeySolved);
    FSankeyInks[i] := Default(TTySankeyInk);
    if FBindings[i].SeriesType <> TySankeySeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    { IN A MATRIX CELL OR A CALENDAR DAY [Batch 151]: the box in the
      refContainer; a cell of no position draws nothing }
    if SeriesBoxRef(i, False, ref, fc) then
    begin
      if not TyXYWHHasSize(ref) then Continue;
      FSankeys[i] := TySankeySolve(FOption, FBindings[i].SeriesIndex, ref, APPI);
    end
    else
      FSankeys[i] := TySankeySolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI);
    if not FSankeys[i].Valid then Continue;
    { the drags' positions, and the view with its roam [Batch 114] }
    if FBindings[i].SeriesIndex <= High(FSankeyLocal) then
      FSankeys[i].Local := Copy(FSankeyLocal[FBindings[i].SeriesIndex]);
    SankeyViewOf(i);
    { the palette: series.get('color') falls through to the chart's }
    d := nil;
    node := FOption.ComponentAt('series', FBindings[i].SeriesIndex);
    if (node <> nil) and (node.JSONType = jtObject) then d := TJSONObject(node).Find('color');
    if ((d = nil) or (d.JSONType = jtNull)) and (FOption.Root is TJSONObject) then
      d := TJSONObject(FOption.Root).Find('color');
    if (d <> nil) and (d.JSONType <> jtNull) then
      StopsOf(d)
    else
    begin
      SetLength(stops, 9);
      for k := 0 to 8 do stops[k] := TyVisualFromChart(TTyChartColor(ThemeRampColor(k)));
    end;
    TySankeyColour(FSankeys[i], stops);
    { the labels: outside by default, the chart's own label ink }
    base := LabelBaseFor(i);
    base.Show := True;
    base.DefaultText := tldName;
    FSankeyInks[i].Label_ := TyLabelSpecOf(FOption, FBindings[i].SeriesIndex, base);
    FSankeyInks[i].ItemLabels := TySankeyLabelSpecs(FSankeys[i], FSankeyInks[i].Label_);
    { THE EDGE LABELS' specs after the nodes': an edge caption's ItemSpec is
      the node count + its index + 1 [Batch 114] }
    lk := LabelBaseFor(i);
    edgeSpecs := TySankeyEdgeLabelSpecs(FSankeys[i], lk);
    k := Length(FSankeyInks[i].ItemLabels);
    SetLength(FSankeyInks[i].ItemLabels, k + Length(edgeSpecs));
    for q := 0 to High(edgeSpecs) do FSankeyInks[i].ItemLabels[k + q] := edgeSpecs[q];
    ls := ActiveController.Model.ResolveStyle('TyAdvChartSankeyLink', '', []);
    FSankeyInks[i].LinkColour := TTyChartColor(ls.Background.Color);
    TySankeyLabels(FSankeys[i], SeriesModelName(FBindings[i].SeriesIndex));
    TySankeyEdgeLabels(FSankeys[i], SeriesModelName(FBindings[i].SeriesIndex));
  end;
end;

{ THE CHORDS [Batch 120]: each laid out on the whole canvas over the nodes
  the legend kept (the store's view), its nodes coloured by the per-datum
  palette -- an object fill where the datum wrote one -- and labelled. }
procedure TTyAdvanceChart.SolveChords(APPI: Integer);
var
  i, k: Integer;
  kept: TTyBoolArray;
  st: TTyDataStore;
  perRaw: TTyChartColorArray;
  obj: TTyChartObjFill;
  base: TTyLabelSpec;
  ref: TTyXYWH;
  fc: Boolean;
  pt: TTyPointF;
begin
  FChords := nil;
  FChordInks := nil;
  SetLength(FChords, Length(FBindings));
  SetLength(FChordInks, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FChords[i] := Default(TTyChordSolved);
    FChordInks[i] := Default(TTyChordInk);
    if FBindings[i].SeriesType <> TyChordSeriesTypeName then Continue;
    if FBindings[i].Hidden then Continue;
    st := nil;
    if i <= High(FStores) then st := FStores[i];
    kept := nil;
    if st <> nil then
    begin
      SetLength(kept, st.RawCount);
      for k := 0 to st.RawCount - 1 do kept[k] := st.IndexOfRawIndex(k) >= 0;
    end;
    { coordinateSystemUsage 'box' IN A MATRIX CELL OR A CALENDAR DAY
      [Batch 151]: getCircleLayout's viewRect in the refContainer; a cell of
      no position draws nothing }
    if SeriesBoxRef(i, False, ref, fc) then
    begin
      if not TyXYWHHasSize(ref) then Continue;
      FChords[i] := TyChordSolve(FOption, FBindings[i].SeriesIndex, FLastRect, ref,
        APPI, kept);
    end
    { usage 'box' on a cartesian or a geo: centred on its point of `coord`,
      none drawing nothing [Batch 154] }
    else if FBindings[i].BoxPoint then
    begin
      if not BoxPointOf(i, pt) then Continue;
      FChords[i] := TyChordSolveAt(FOption, FBindings[i].SeriesIndex, FLastRect,
        pt.X, pt.Y, APPI, kept);
    end
    else
      FChords[i] := TyChordSolve(FOption, FBindings[i].SeriesIndex, FLastRect, APPI, kept);
    if not FChords[i].Valid then Continue;
    { the colour visual: the palette's pick or the datum's own colour, a
      gradient where one was written (not a string: no gradient ribbon) }
    perRaw := PerDatumColours(i);
    for k := 0 to High(FChords[i].Nodes) do
    begin
      if k <= High(perRaw) then
      begin
        FChords[i].Nodes[k].HasColour := True;
        FChords[i].Nodes[k].IsString := True;
        FChords[i].Nodes[k].Colour := perRaw[k];
      end;
      obj := DatumObjectFill(i, k);
      if obj.Present then
      begin
        FChords[i].Nodes[k].IsString := False;
        if obj.Gradient.Kind <> cgkNone then
        begin
          FChords[i].Nodes[k].HasGradient := True;
          FChords[i].Nodes[k].Gradient := obj.Gradient;
          FChords[i].Nodes[k].Colour := TyGradientSolid(obj.Gradient);
        end;
      end;
    end;
    { the labels: shown and outside by default, the chart's label font }
    base := LabelBaseFor(i);
    base.Show := True;
    base.DefaultText := tldName;
    FChordInks[i].Label_ := TyLabelSpecOf(FOption, FBindings[i].SeriesIndex, base);
    FChordInks[i].ItemLabels := TyChordLabelSpecs(FChords[i], FChordInks[i].Label_);
    TyChordLabels(FChords[i], SeriesModelName(FBindings[i].SeriesIndex));
  end;
end;

{ A TREEMAP'S INK: its labels in their own key's ink -- white over the
  palette in every mode, never the auto bands -- read item -> level ->
  series; after the rows, the breadcrumb's words, and its chip. }
function TTyAdvanceChart.TreemapInk(ASlot: Integer): TTyTreemapInk;
var
  dummyCol, col: TTyChartColor;
  sNode: TJSONObject;
  has: Boolean;
  base, crumb: TTyLabelSpec;
  ls, cs: TTyStyleSet;
  hs: TTyLabelSpecArray;
  j, k: Integer;
begin
  Result := Default(TTyTreemapInk);
  ls := ActiveController.Model.ResolveStyle('TyAdvChartTreemapLabel', '', []);
  base := LabelBaseFor(ASlot);
  base.Show := True;
  base.DefaultText := tldName;
  base.AutoColour := False;
  base.Colour := TTyChartColor(ls.TextColor);
  base.FontName := ls.FontName;
  base.FontSizeLogical := ResolveFontSize(ls);
  base.FontWeight := ls.FontWeight;
  GlobalInk(base.FontName, base.FontSizeLogical, base.FontWeight, dummyCol, [ttpSize, ttpWeight, ttpFamily]);
  Result.Label_ := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
  Result.ItemLabels := TyTreemapLabelSpecs(FTreemaps[ASlot], Result.Label_);
  cs := ActiveController.Model.ResolveStyle('TyAdvChartBreadcrumb', '', []);
  crumb := TyLabelSpecNone;
  crumb.Show := True;
  crumb.AutoColour := False;
  crumb.Colour := TTyChartColor(cs.TextColor);
  crumb.FontName := cs.FontName;
  crumb.FontSizeLogical := ResolveFontSize(cs);
  crumb.FontWeight := cs.FontWeight;
  GlobalInk(crumb.FontName, crumb.FontSizeLogical, crumb.FontWeight, dummyCol, [ttpSize, ttpWeight, ttpFamily]);
  Result.CrumbFill := TTyChartColor(cs.Background.Color);
  { THE AUTHOR'S breadcrumb colours over the skin's: itemStyle.color, its
    textStyle.color, and the hover's (Breadcrumb.ts:150-189) [F2a] }
  sNode := StSeriesNode(FBindings[ASlot].SeriesIndex);
  if TyTryParseChartColor(TyStReadString([sNode], ['breadcrumb', 'itemStyle', 'color'], has), col) and has then
    Result.CrumbFill := col;
  if TyTryParseChartColor(TyStReadString([sNode], ['breadcrumb', 'itemStyle', 'textStyle', 'color'], has), col) and has then
    crumb.Colour := col;
  Result.CrumbEmphFill := TTyChartColor(ActiveController.Model.ResolveStyle(
    'TyAdvChartBreadcrumb', '', [tysHover]).Background.Color);
  if TyTryParseChartColor(TyStReadString([sNode], ['breadcrumb', 'emphasis', 'itemStyle', 'color'], has), col) and has then
    Result.CrumbEmphFill := col;
  Result.CrumbEmphHasText := TyTryParseChartColor(TyStReadString([sNode],
    ['breadcrumb', 'emphasis', 'itemStyle', 'textStyle', 'color'], has), col) and has;
  if Result.CrumbEmphHasText then Result.CrumbEmphText := col;
  SetLength(Result.ItemLabels, Length(Result.ItemLabels) + 1);
  Result.ItemLabels[High(Result.ItemLabels)] := crumb;
  { the parents' headers: outside text in the chart's label ink, a halo of
    the ground [Batch 78] }
  base := LabelBaseFor(ASlot);
  base.Show := True;
  base.DefaultText := tldName;
  hs := TyTreemapUpperSpecs(FTreemaps[ASlot], base);
  k := Length(Result.ItemLabels);
  SetLength(Result.ItemLabels, k + Length(hs));
  for j := 0 to High(hs) do Result.ItemLabels[k + j] := hs[j];
end;

{ A SUNBURST'S INK: the ring separator is the chart's own ground (upstream's
  white), and the labels are shown by default with the node's name, read
  item -> level -> series. }
function TTyAdvanceChart.SunburstInk(ASlot: Integer): TTySunburstInk;
var
  base: TTyLabelSpec;
  muted: TTyStyleSet;
  a, r, g, b: Cardinal;
  over: TTyChartColor;

  function Mix(AFore, ABack: Cardinal): Cardinal;
  begin
    Result := (AFore * a + ABack * (255 - a) + 127) div 255;
  end;

begin
  Result := Default(TTySunburstInk);
  Result.Border := TTyChartColor(
    ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
  { THE RETURN CIRCLE'S FILL [Batch 115]: upstream's neutral50, a mid grey
    -- here the muted ink a sankey's links take, laid on the chart's ground
    so the circle is opaque in every skin }
  muted := ActiveController.Model.ResolveStyle('TyAdvChartSankeyLink', '', []);
  over := TTyChartColor(muted.Background.Color);
  a := (Cardinal(over) shr 24) and $FF;
  r := Mix((Cardinal(over) shr 16) and $FF, (Cardinal(Result.Border) shr 16) and $FF);
  g := Mix((Cardinal(over) shr 8) and $FF, (Cardinal(Result.Border) shr 8) and $FF);
  b := Mix(Cardinal(over) and $FF, Cardinal(Result.Border) and $FF);
  Result.RootFill := TTyChartColor($FF000000 or (r shl 16) or (g shl 8) or b);
  base := LabelBaseFor(ASlot);
  base.Show := True;
  base.DefaultText := tldName;
  Result.Label_ := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
  Result.ItemLabels := TySunburstLabelSpecs(FSunbursts[ASlot], Result.Label_);
  Result.SeriesName := SeriesModelName(FBindings[ASlot].SeriesIndex);
  Result.LabelValueDim := -1;
  if FStores[ASlot] <> nil then
    Result.LabelValueDim := FStores[ASlot].DimIndexOf('value');
end;

{ A TREE'S INK: the node colour the palette pass settled (the theme's, or
  the series' own), the edge colour from its key, a ring's hole from the
  chart's own ground, and the labels -- shown by default, the node's name
  their words, read item -> leaves -> series. }
function TTyAdvanceChart.TreeInk(ASlot: Integer): TTyTreeInk;
var
  base: TTyLabelSpec;
begin
  Result := Default(TTyTreeInk);
  Result.NodeColour := TTyChartColor(SeriesColor(FBindings[ASlot].SeriesIndex));
  Result.EdgeColour := TTyChartColor(ActiveController.Model.ResolveStyle(
    'TyAdvChartTreeEdge', '', []).BorderColor);
  Result.EmptyFill := TTyChartColor(
    ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
  base := LabelBaseFor(ASlot);
  base.Show := True;
  base.DefaultText := tldName;
  Result.Label_ := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
  Result.ItemLabels := TyTreeLabelSpecs(FTrees[ASlot], Result.Label_);
  Result.SeriesName := SeriesModelName(FBindings[ASlot].SeriesIndex);
  Result.LabelValueDim := -1;
  if FStores[ASlot] <> nil then
    Result.LabelValueDim := FStores[ASlot].DimIndexOf('value');
  { [R2-J3] }
  Result.ItemCb := ItemCbOf(ASlot);
end;

procedure TTyAdvanceChart.FreeTreeViews;
var i: Integer;
begin
  for i := 0 to High(FTreeViews) do FreeAndNil(FTreeViews[i]);
  FreeSankeyViews;
  FTreeViews := nil;
  FTreeSpecs := nil;
end;

procedure TTyAdvanceChart.FreeGraphs;
var i: Integer;
begin
  for i := 0 to High(FGraphs) do FreeAndNil(FGraphs[i]);
  FGraphs := nil;
  FGraphLaidOut := nil;
  FGraphSpecs := nil;
  FGraphNodes := nil;
  FGraphEdges := nil;
  FGraphCats := nil;
  FGraphNodeScale := nil;
end;

procedure TTyAdvanceChart.SolveGraphs(APPI: Integer);
var
  i, si, colX, colY: Integer;
  solved: TTyGraphSolved;
  store: TTyDataStore;
  cols: TTyIntegerArray;
  ref: TTyXYWH;
  boxed, fc: Boolean;
begin
  FreeGraphs;
  SetLength(FGraphs, Length(FBindings));
  SetLength(FGraphLaidOut, Length(FBindings));
  SetLength(FGraphSpecs, Length(FBindings));
  SetLength(FGraphNodes, Length(FBindings));
  SetLength(FGraphEdges, Length(FBindings));
  SetLength(FGraphCats, Length(FBindings));
  SetLength(FGraphNodeScale, Length(FBindings));
  { [R2-J3] each slot's visual callbacks in the graph unit's scope while its
    nodes are read }
  try
  for i := 0 to High(FBindings) do
  begin
    FGraphs[i] := nil;
    FGraphLaidOut[i] := False;
    FGraphNodeScale[i] := 1;
    if FBindings[i].SeriesType <> TyGraphSeriesTypeName then Continue;
    TyGraphItemCallbacks := ItemCbOf(i);
    if not FBindings[i].Resolved then Continue;
    { A GRAPH THE LEGEND SWITCHED OFF IS NOT LAID OUT AT ALL -- upstream's
      legendFilter takes the series out before any layout runs -- and for a
      force graph of five hundred nodes that is a second and a half nobody
      would see. }
    if FBindings[i].Hidden then Continue;
    si := FBindings[i].SeriesIndex;
    if si < 0 then Continue;
    store := nil;
    if i <= High(FStores) then store := FStores[i];
    { A GRAPH ON AXES IS LAID OUT BY THE AXES IT NAMED, here, after the grids
      have their final pixels: every node at the grid's dataToPoint of its two
      columns, whatever `layout` says. Upstream skips the ring, the force
      simulation and the view alike for any coordinate system that is not a
      view, so this keeps no force state either. The columns are the first
      each axis owns, the same lookup every other renderer makes. }
    if (FBindings[i].CoordSysName = 'cartesian2d') and (FBindings[i].Cart <> nil)
      and (store <> nil) then
    begin
      colX := -1;
      colY := -1;
      if FBindings[i].XAxis <> nil then
      begin
        cols := store.DimsOfCoord(FBindings[i].XAxis.Dim);
        if Length(cols) > 0 then colX := cols[0];
      end;
      if FBindings[i].YAxis <> nil then
      begin
        cols := store.DimsOfCoord(FBindings[i].YAxis.Dim);
        if Length(cols) > 0 then colY := cols[0];
      end;
      solved := TyGraphSolveOnCoordSys(FOption, si, store, FBindings[i].Cart,
        colX, colY);
      FGraphLaidOut[i] := True;
      FGraphSpecs[i] := solved.Spec;
      FGraphNodes[i] := solved.Nodes;
      FGraphEdges[i] := solved.Edges;
      FGraphCats[i] := solved.Cats;
      Continue;
    end;
    { A GRAPH ON A CALENDAR: each node where the calendar puts its date,
      under upstream's own rule for which nodes are placed at all -- see
      CalendarGraphPoints. [Batch 72] }
    boxed := SeriesBoxRef(i, False, ref, fc);
    if (FBindings[i].CalendarIndex >= 0)
      and (FBindings[i].CalendarIndex <= High(FCalendars)) and (store <> nil) then
    begin
      solved := TyGraphSolveAtPoints(FOption, si, store,
        CalendarGraphPoints(si, FCalendars[FBindings[i].CalendarIndex]));
      FGraphLaidOut[i] := True;
      FGraphSpecs[i] := solved.Spec;
      FGraphNodes[i] := solved.Nodes;
      FGraphEdges[i] := solved.Edges;
      FGraphCats[i] := solved.Cats;
      Continue;
    end;
    { A GRAPH ON A MATRIX: each node at dataToPoint of its x and y, under
      the simple layout's rule for which nodes are placed [Batch 147] }
    if (FBindings[i].MatrixIndex >= 0) and not FBindings[i].MatrixBox
      and (FBindings[i].MatrixIndex <= High(FMatrices))
      and (FMatrices[FBindings[i].MatrixIndex] <> nil) and (store <> nil) then
    begin
      solved := TyGraphSolveAtPoints(FOption, si, store,
        MatrixGraphPoints(si, FMatrices[FBindings[i].MatrixIndex]));
      FGraphLaidOut[i] := True;
      FGraphSpecs[i] := solved.Spec;
      FGraphNodes[i] := solved.Nodes;
      FGraphEdges[i] := solved.Edges;
      FGraphCats[i] := solved.Cats;
      Continue;
    end;
    { A GRAPH ON A GEO [Batch 152] }
    if (FBindings[i].GeoIndex >= 0) and (store <> nil) then
    begin
      SolveGeoGraph(i);
      Continue;
    end;
    { ANY OTHER SYSTEM BUT A VIEW IS NOT PORTED -- polar --
      and a graph on one resolves and draws nothing rather than being quietly
      given a view it did not ask for. }
    { coordinateSystemUsage 'box' on a matrix or a calendar: the internal
      view laid out in the cell (createView's getViewRect on the
      refContainer); a cell of no position draws nothing [Batch 151] }
    if (FBindings[i].CoordSysName <> 'view') and not boxed then Continue;
    if boxed and not TyXYWHHasSize(ref) then Continue;
    if Length(FGraphForce) <= si then SetLength(FGraphForce, si + 1);
    if Length(FGraphRoam) <= si then SetLength(FGraphRoam, si + 1);
    { THE WHOLE PASS IS THE PURE UNIT'S, so the suite drives the same path this
      does rather than a copy of it. }
    if boxed then
      solved := TyGraphSolve(FOption, si, store, ref, FGraphForce[si],
        FGraphRoam[si])
    else
      solved := TyGraphSolve(FOption, si, store, FLastRect, FGraphForce[si],
        FGraphRoam[si]);
    FGraphs[i] := solved.View;
    FGraphNodeScale[i] := solved.NodeScale;
    FGraphLaidOut[i] := True;
    FGraphSpecs[i] := solved.Spec;
    FGraphNodes[i] := solved.Nodes;
    FGraphEdges[i] := solved.Edges;
    FGraphCats[i] := solved.Cats;
  end;
  finally
    TyGraphItemCallbacks := nil;
  end;
  { [F3d] the edges' keys for the next update }
  SetLength(FGraphEdgeKeys, Length(FBindings));
  for i := 0 to High(FBindings) do FGraphEdgeKeys[i] := AnimGraphEdgeKeys(i);
  if APPI < 0 then ;
end;

function TTyAdvanceChart.GraphNodeName(ASlot, ANode: Integer): string;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FGraphNodes)) or (ASlot > High(FStores))
    or (FStores[ASlot] = nil) then Exit;
  if (ANode < 0) or (ANode > High(FGraphNodes[ASlot])) then Exit;
  if FGraphNodes[ASlot][ANode].Row < 0 then Exit;
  Result := FStores[ASlot].GetItemName(FGraphNodes[ASlot][ANode].Row);
end;

function TTyAdvanceChart.GraphInk(ASlot: Integer): TTyGraphInk;
var
  i, si, raw: Integer;
  base, cbBase: TTyChartColor;
  cols: TTyGraphCatColours;
  store: TTyDataStore;
begin
  Result := Default(TTyGraphInk);
  Result.LabelValueDim := -1;
  if (ASlot < 0) or (ASlot > High(FGraphNodes)) then Exit;
  base := TTyChartColor(SeriesColor(FBindings[ASlot].SeriesIndex));
  Result.EdgeColour := FGraphSpecs[ASlot].LineColour;
  if not FGraphSpecs[ASlot].HasLineColour then
    { THE THEME'S OWN LINE, not the grey the option tree carries. Upstream's
      default is a fixed token and this library's rule is that a visual value
      comes from the theme -- so the token is replaced here, where a theme can
      be seen, rather than in the pure unit. }
    Result.EdgeColour := TTyChartColor(
      ActiveController.Model.ResolveStyle('TyAdvChartSplitLine', '',
        []).BorderColor);

  { THREE SOURCES, NEAREST FIRST: what the node wrote, then its category's
    colour, then the series' own. The category's comes from the ONE table the
    legend's chips read too -- it used to index a per-NODE palette by the
    CATEGORY number, which agreed with the chips by coincidence and let the
    first few nodes' own colours leak into whole categories. }
  si := FBindings[ASlot].SeriesIndex;
  cols := Default(TTyGraphCatColours);
  if (si >= 0) and (si <= High(FGraphCatColours)) then
    cols := FGraphCatColours[si];
  store := nil;
  if ASlot <= High(FStores) then store := FStores[ASlot];
  SetLength(Result.NodeFills, Length(FGraphNodes[ASlot]));
  SetLength(Result.EdgeEndFills, Length(FGraphNodes[ASlot]));
  for i := 0 to High(FGraphNodes[ASlot]) do
  begin
    { [R2-J3] the series' colour callback is the node's base: its category's
      and its own colour over it }
    cbBase := base;
    if ItemCbOf(ASlot) <> nil then
      if not ItemCbOf(ASlot).ColOf(FGraphNodes[ASlot][i].RawRow, cbBase) then cbBase := base;
    Result.NodeFills[i] := TyGraphNodeFill(FGraphNodes[ASlot][i], cols,
      Length(FGraphCats[ASlot]), cbBase, store, Result.EdgeEndFills[i]);
    { A visualMap's colour over the category's and the series' -- the
      category visual runs before the encoding -- and under the node's own }
    raw := FGraphNodes[ASlot][i].RawRow;
    if (ASlot <= High(FVisualRows)) and (raw >= 0)
      and (raw <= High(FVisualRows[ASlot])) and FVisualRows[ASlot][raw].ColorSet
      and not ((store <> nil) and store.HasOverrideByRaw(raw,
        TyOverrideKey('itemStyle.color'))) then
    begin
      Result.NodeFills[i] := TyVisualToChart(FVisualRows[ASlot][raw].Color);
      Result.EdgeEndFills[i] := Result.NodeFills[i];
    end;
  end;

  { A NODE'S LABEL IS ITS NAME, and the graph is the only series here whose
    default formatter says so: `label.formatter: '{b}'` is in its own
    defaultOption -- a TEMPLATE, so a name is read the way formatTpl reads it.
    Being a default, the option can take it away: `formatter: null` stays
    null through upstream's merge, and a node then shows what every other
    series shows, its VALUE (on a cartesian graph, the value axis' column). }
  Result.Label_ := LabelSpecFor(ASlot, '{b}');
  Result.Label_.DefaultText := tldValue;
  Result.SeriesName := SeriesModelName(FBindings[ASlot].SeriesIndex);
  GraphNodeLooks(ASlot, Result);
  { THE c PLACEHOLDER IS THE VALUE COLUMN on a view and the value AXIS' column on axes,
    where there is no column called value at all. }
  if (ASlot <= High(FStores)) and (FStores[ASlot] <> nil) then
  begin
    if FBindings[ASlot].ValueAxis <> nil then
      Result.LabelValueDim :=
        FStores[ASlot].DimIndexOf(FBindings[ASlot].ValueAxis.Dim)
    else
      Result.LabelValueDim := FStores[ASlot].DimIndexOf('value');
  end;
  GraphEdgeLabels(ASlot, Result);
end;

{ [F2a] A GRAPH NODE'S OWN LOOK: its opacity (style.opacity -- the node's
  itemStyle over its category's over the series', categoryVisual and
  dataStyleTask), and its own label -- the node's `label` over its
  category's over the series' (the wrapped getItemModel), built hidden when
  only a state shows it (GraphSeries' emphasis.label.show is true unless
  told) }
procedure TTyAdvanceChart.GraphNodeLooks(ASlot: Integer; var AInk: TTyGraphInk);
var
  i, raw, j: Integer;
  sNode, item, cat, styleCat: TJSONObject;
  arr, d: TJSONData;
  spec: TTyLabelSpec;
  has, emShow: Boolean;
  v: Double;
  chain: array[0..2] of TJSONObject;
  one, b: TTyOptStyle;
begin
  AInk.NodeOpacity := nil;
  AInk.NodeLabels := nil;
  AInk.NodeBorder := nil;
  if (ASlot < 0) or (ASlot > High(FGraphNodes)) then Exit;
  SetLength(AInk.NodeOpacity, Length(FGraphNodes[ASlot]));
  SetLength(AInk.NodeLabels, Length(FGraphNodes[ASlot]));
  SetLength(AInk.NodeBorder, Length(FGraphNodes[ASlot]));
  { the ground an empty symbol's hole takes, the skin's own (as a scatter's) }
  AInk.EmptyFill := TTyChartColor(
    ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
  sNode := StSeriesNode(FBindings[ASlot].SeriesIndex);
  arr := nil;
  if sNode <> nil then
  begin
    arr := sNode.Find('data');
    if (arr = nil) or (arr.JSONType = jtNull) then arr := sNode.Find('nodes');
  end;
  for i := 0 to High(FGraphNodes[ASlot]) do
  begin
    raw := FGraphNodes[ASlot][i].RawRow;
    item := nil;
    if (arr is TJSONArray) and (raw >= 0) and (raw < arr.Count)
      and (TJSONArray(arr).Items[raw] is TJSONObject) then
      item := TJSONObject(TJSONArray(arr).Items[raw]);
    cat := GraphCategoryNode(ASlot, FGraphNodes[ASlot][i].ModelCategory);
    { [R2-I3] THE STYLE'S CATEGORY, which categoryVisual finds by its name
      as well as by its index -- unlike the model's parent above }
    styleCat := GraphCategoryNode(ASlot, FGraphNodes[ASlot][i].Category);
    v := TyStReadNumber([item, styleCat, sNode], ['itemStyle', 'opacity'], has);
    if not has or IsNan(v) then v := 1;
    AInk.NodeOpacity[i] := v;
    { [R2-I3] its border, key by key down the same three }
    chain[0] := item;
    chain[1] := styleCat;
    chain[2] := sNode;
    b := Default(TTyOptStyle);
    b.BorderWidthLogical := NaN;
    b.Opacity := NaN;
    b.Dash := todNone;
    for j := 2 downto 0 do
    begin
      if chain[j] = nil then Continue;
      one := TyReadOptStyle(chain[j], 'itemStyle');
      if one.BorderColor.Written then b.BorderColor := one.BorderColor;
      if not IsNan(one.BorderWidthLogical) then b.BorderWidthLogical := one.BorderWidthLogical;
      if one.Dash <> todNone then
      begin
        b.Dash := one.Dash;
        b.DashLogical := one.DashLogical;
      end;
      if one.DashOffsetHas then
      begin
        b.DashOffsetHas := True;
        b.DashOffset := one.DashOffset;
      end;
    end;
    AInk.NodeBorder[i] := b;
    spec := AInk.Label_;
    if cat <> nil then
    begin
      d := cat.Find('label');
      if d is TJSONObject then spec := TyLabelSpecOfNode(TJSONObject(d), sNode, spec);
    end;
    if item <> nil then
    begin
      d := item.Find('label');
      if d is TJSONObject then spec := TyLabelSpecOfNode(TJSONObject(d), sNode, spec);
    end;
    emShow := GraphEmLabelShow(item, cat, sNode);
    if emShow then spec.StateShow := True;
    AInk.NodeLabels[i] := spec;
  end;
end;

{ THE EDGE LABELS of one graph [Batch 114]: per edge, the spec (the series'
  `edgeLabel` under the edge's own `label` -- an edge item's `label` resolves
  to the series' `edgeLabel`, GraphSeries' resolveParentPath), whether it
  shows, its words, its position and distance; and the line's frame. }
procedure TTyAdvanceChart.GraphEdgeLabels(ASlot: Integer; var AInk: TTyGraphInk);
var
  i, n, raw: Integer;
  sNode, item, lab, own: TJSONObject;
  links, d, fmt, nd, nv: TJSONData;
  base, spec: TTyLabelSpec;
  scale, dx, dy: Double;
  posWord: string;
  prm: TTyChartCallbackParams;
  vars: array of TTyStringArray;
  nodeHas, nodeNum: Boolean;
  nodeVal: Double;
  nodeText: string;

  { the first of the edge's own label and the series' edgeLabel that holds
    the key (null falls through) }
  function LabKey(const AKey: string): TJSONData;
  begin
    Result := nil;
    if own <> nil then Result := own.Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
    if (Result = nil) and (lab <> nil) then Result := lab.Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
  end;

  function JsNumOf(AData: TJSONData): Double;
  begin
    Result := NaN;
    if AData = nil then Exit;
    case AData.JSONType of
      jtNumber: Result := AData.AsFloat;
      jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
      jtString: Result := TyJsToNumber(AData.AsString);
      jtNull: Result := 0;
      jtArray:
        if AData.Count = 0 then Result := 0
        else if AData.Count = 1 then Result := JsNumOf(AData.Items[0]);
    end;
  end;

begin
  n := 0;
  if (ASlot >= 0) and (ASlot <= High(FGraphEdges)) then n := Length(FGraphEdges[ASlot]);
  SetLength(AInk.EdgeLabelShow, n);
  SetLength(AInk.EdgeLabelText, n);
  SetLength(AInk.EdgeLabelPos, n);
  SetLength(AInk.EdgeLabelDistX, n);
  SetLength(AInk.EdgeLabelDistY, n);
  SetLength(AInk.EdgeLabelSpecs, n);
  SetLength(AInk.EdgeLabelRot, n);
  SetLength(AInk.EdgeLabelOffX, n);
  SetLength(AInk.EdgeLabelOffY, n);
  if FLastPPI > 0 then scale := FLastPPI / 96 else scale := 1;
  { the line's frame: the view's overall transform, the label scaled back by
    1 / its scaleX (every ancestor's scaleX, and only the main group has one) }
  AInk.HasFrame := (ASlot <= High(FGraphs)) and (FGraphs[ASlot] <> nil);
  if AInk.HasFrame then
  begin
    AInk.Frame.SX := FGraphs[ASlot].OverallScaleX;
    AInk.Frame.SY := FGraphs[ASlot].OverallScaleY;
    AInk.Frame.X := FGraphs[ASlot].OverallX;
    AInk.Frame.Y := FGraphs[ASlot].OverallY;
    if (AInk.Frame.SX = 0) or IsNan(AInk.Frame.SX) then AInk.Frame.InvScale := 1
    else AInk.Frame.InvScale := 1 / AInk.Frame.SX;
  end;
  if n = 0 then Exit;
  sNode := nil;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if d is TJSONObject then sNode := TJSONObject(d);
  if sNode = nil then Exit;
  lab := nil;
  d := sNode.Find('edgeLabel');
  if d is TJSONObject then lab := TJSONObject(d);
  links := sNode.Find('edges');
  if (links = nil) or (links.JSONType = jtNull) or ((links.JSONType = jtBoolean) and not links.AsBoolean)
    or ((links.JSONType = jtString) and (links.AsString = '')) then
    links := sNode.Find('links');
  base := LabelBaseFor(ASlot);
  base.Show := False;
  for i := 0 to n - 1 do
  begin
    own := nil;
    item := nil;
    if (links is TJSONArray) and (FGraphEdges[ASlot][i].Row >= 0)
      and (FGraphEdges[ASlot][i].Row < links.Count)
      and (TJSONArray(links).Items[FGraphEdges[ASlot][i].Row] is TJSONObject) then
      item := TJSONObject(TJSONArray(links).Items[FGraphEdges[ASlot][i].Row]);
    if item <> nil then
    begin
      d := item.Find('label');
      if d is TJSONObject then own := TJSONObject(d);
    end;
    spec := base;
    if lab <> nil then spec := TyLabelSpecOfNode(lab, sNode, spec);
    if own <> nil then spec := TyLabelSpecOfNode(own, sNode, spec);
    { the edge places its own words: no table position, no offset }
    spec.Position := tlpInside;
    spec.OffsetXLogical := 0;
    spec.OffsetYLogical := 0;
    spec.Overflow := tloNone;
    AInk.EdgeLabelSpecs[i] := spec;
    AInk.EdgeLabelShow[i] := spec.Show;
    { `position || 'middle'`; `distance`, a pair or one for both (default 5) }
    d := LabKey('position');
    if (d <> nil) and (d.JSONType = jtString) then posWord := d.AsString
    else posWord := '';
    AInk.EdgeLabelPos[i] := TyGraphLabelPosOf(posWord);
    dx := 5;
    dy := 5;
    d := LabKey('distance');
    if d is TJSONArray then
    begin
      dx := NaN;
      dy := NaN;
      if (d.Count > 0) and (d.Items[0].JSONType = jtNumber) then dx := d.Items[0].AsFloat;
      if (d.Count > 1) and (d.Items[1].JSONType = jtNumber) then dy := d.Items[1].AsFloat;
    end
    else if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      dx := d.AsFloat;
      dy := dx;
    end;
    AInk.EdgeLabelDistX[i] := dx * scale;
    AInk.EdgeLabelDistY[i] := dy * scale;
    { `rotate` and `offset` (createTextConfig): the turn replaces the one
      Line.beforeUpdate gave, the offset moves the anchor in the label's own
      turned frame [F2a] }
    AInk.EdgeLabelRot[i] := NaN;
    d := LabKey('rotate');
    if (d <> nil) and (d.JSONType = jtNumber) then AInk.EdgeLabelRot[i] := d.AsFloat * (Pi / 180);
    AInk.EdgeLabelOffX[i] := NaN;
    AInk.EdgeLabelOffY[i] := NaN;
    d := LabKey('offset');
    if (d is TJSONArray) and (d.Count >= 2) and (d.Items[0].JSONType = jtNumber)
      and (d.Items[1].JSONType = jtNumber) then
    begin
      AInk.EdgeLabelOffX[i] := d.Items[0].AsFloat * scale;
      AInk.EdgeLabelOffY[i] := d.Items[1].AsFloat * scale;
    end;
    { THE WORDS: the formatter (a handler or a template over the EDGE's data:
      a the series, b the edge data's name, c its value), else the default
      text -- the NODE value at the edge's index (TyGraphEdgeDefaultText) }
    fmt := LabKey('formatter');
    if (fmt <> nil) and (fmt.JSONType = jtString) and TyChartIsHandlerRef(fmt.AsString) then
    begin
      prm := TyChartBlankParams;
      prm.ComponentType := 'series';
      prm.SeriesType := TyGraphSeriesTypeName;
      prm.SeriesIndex := FBindings[ASlot].SeriesIndex;
      prm.SeriesName := SeriesModelName(FBindings[ASlot].SeriesIndex);
      prm.DataType := 'edge';
      prm.Status := 'normal';
      prm.DataIndex := i;
      prm.RawDataIndex := i;
      prm.Name := FGraphEdges[ASlot][i].DataName;
      prm.ValueText := FGraphEdges[ASlot][i].ValueText;
      SetLength(prm.Values, 1);
      prm.Values[0] := FGraphEdges[ASlot][i].Value;
      AInk.EdgeLabelText[i] := TyChartRunHandler(fmt.AsString, TyChartOneParams(prm));
    end
    else if (fmt <> nil) and (fmt.JSONType = jtString) then
    begin
      vars := nil;
      SetLength(vars, 1);
      SetLength(vars[0], 3);
      vars[0][0] := SeriesModelName(FBindings[ASlot].SeriesIndex);
      vars[0][1] := FGraphEdges[ASlot][i].DataName;
      vars[0][2] := FGraphEdges[ASlot][i].ValueText;
      AInk.EdgeLabelText[i] := TyJsFormatTpl(fmt.AsString, 3, vars);
    end
    else
    begin
      { getRawValue(idx) of the NODE data: the node at the edge's own index
        among the survivors, its raw `value` (the item itself when it is not
        an object) }
      nodeHas := False;
      nodeNum := False;
      nodeVal := NaN;
      nodeText := '';
      if i <= High(FGraphNodes[ASlot]) then
      begin
        raw := FGraphNodes[ASlot][i].RawRow;
        { `data || nodes` -- an empty array is truthy }
        nd := sNode.Find('data');
        if (nd = nil) or (nd.JSONType = jtNull) then nd := sNode.Find('nodes');
        if (nd is TJSONArray) and (raw >= 0) and (raw < nd.Count) then
        begin
          nv := TJSONArray(nd).Items[raw];
          if nv is TJSONObject then nv := TJSONObject(nv).Find('value');
          nodeHas := (nv <> nil) and (nv.JSONType <> jtNull);
          if nodeHas then
          begin
            nodeVal := JsNumOf(nv);
            nodeNum := (nv.JSONType <> jtObject)
              and not ((nv is TJSONArray) and (nv.Count > 1));
            nodeText := TyGraphJsText(nv);
          end;
        end;
      end;
      AInk.EdgeLabelText[i] := TyGraphEdgeDefaultText(nodeHas, nodeNum, nodeVal,
        nodeText, FGraphEdges[ASlot][i].DataName);
    end;
  end;
end;

{ the category model a graph node names by index (nil: none) }
function TTyAdvanceChart.GraphCategoryNode(ASlot, ACategory: Integer): TJSONObject;
var sNode: TJSONObject; d: TJSONData;
begin
  Result := nil;
  if ACategory < 0 then Exit;
  sNode := StSeriesNode(FBindings[ASlot].SeriesIndex);
  if sNode = nil then Exit;
  d := sNode.Find('categories');
  if (d is TJSONArray) and (ACategory < d.Count) and (TJSONArray(d).Items[ACategory] is TJSONObject) then
    Result := TJSONObject(TJSONArray(d).Items[ACategory]);
end;

function TTyAdvanceChart.IsGraphDatum(const ADatum: TTyChartDatumRef): Boolean;
var slot: Integer;
begin
  Result := False;
  if ADatum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  Result := (slot >= 0) and (slot <= High(FGraphLaidOut)) and FGraphLaidOut[slot];
end;

function TTyAdvanceChart.IsTreeDatum(const ADatum: TTyChartDatumRef): Boolean;
var slot: Integer;
begin
  Result := False;
  if ADatum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  Result := (slot >= 0) and (slot <= High(FTrees)) and FTrees[slot].Valid
    and (FBindings[slot].SeriesType = TyTreeSeriesTypeName);
end;
