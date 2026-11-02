{ Part of tyControls.AdvanceChart (included, not a unit): the mouse, the chart's events,
  hit testing and the cursor. Moved out of the unit only to keep it readable; what the
  control is and why it is built the way it is, see the unit header. }

procedure TTyCustomAdvanceChart.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  d: TTyChartDatumRef;
  el, slot, k: Integer;
begin
  TbFrame;
  FPressEl := -1;
  inherited MouseDown(Button, Shift, X, Y);
  if csDesigning in ComponentState then Exit;
  EventDown(Button, X, Y);
  { ParallelView's zrender mousedown, whatever the button: the press a
    click trigger judges the release against [Batch 140] }
  ParExpDown(X, Y);
  { A MIDDLE OR RIGHT PRESS NEITHER ARMS NOR DISARMS. }
  if Button <> mbLeft then Exit;
  FRoamSeries := -1;
  FRoamGeo := -1;
  { THE THUMBNAIL'S RoamController, the first roam listener (z 10): a press
    in its content rect arms it; the graph's own controller arms beside it,
    and the thumbnail consumes the moves [Batch 140] }
  ThumbDown(X, Y);
  { THE PRESS A CLICK IS JUDGED AGAINST, before anything else claims it }
  FPressDatum := HitTestAt(X, Y, el);
  { zrender's _downEl [Batch 153] }
  FPressEl := el;
  FPressCaption := (el >= 0) and (FPaintList <> nil)
    and (FPaintList.Element(el).Caption.FontSizeLogical > 0);
  FPressX := X;
  FPressY := Y;
  FPressArmed := True;
  FGraphDragSlot := -1;
  FSankeyDragSlot := -1;
  { [R5-D] AN AXIS POINTER'S HANDLE (z 50, draggable): zrender's Draggable
    takes the press -- its onmousedown dispatches at once -- and nothing
    under it hears it }
  FHdDrag := HdAt(X, Y);
  if FHdDrag >= 0 then
  begin
    FHdDragX := X;
    FHdDragY := Y;
    HdDragMove(FHdDrag, 0, 0);
    Exit;
  end;
  { A BREADCRUMB ITEM: its own click [Batch 115]; [R2-B] where it is the
    element under the pointer, not under what is drawn over it }
  FCrumbPressed := CrumbOfElement(el, FCrumbPressSeries, FCrumbPressIndex);
  FCrumbPressX := X;
  FCrumbPressY := Y;
  { A PRESS ON A BRUSH COVER'S PIECE is zrender's Draggable's: the cover
    moves or resizes, and nothing under it hears the press [Batch 126] }
  if BrushDragStart(X, Y) then Exit;
  { A PRESS ON A visualMap's thumb, handle label or in-range bar is zrender's
    Draggable's: no node drag, no pan under it [Batch 116] }
  if VmDragStart(X, Y) then Exit;
  { A PRESS ON A DRAGGABLE NODE IS THE NODE'S, not the view's: zrender's
    Draggable takes it (dragstart), and the RoamController walks up from the
    target and finds `draggable` -- a node's label is its node's. }
  d := HitTestAt(X, Y, el);
  if (d.SeriesIndex >= 0) and not d.IsEdge then
  begin
    slot := SlotOfSeries(d.SeriesIndex);
    if (slot >= 0) and (slot <= High(FGraphNodes))
      and (slot <= High(FGraphLaidOut)) and FGraphLaidOut[slot] then
      for k := 0 to High(FGraphNodes[slot]) do
        if (FGraphNodes[slot][k].Row = d.DataIndex)
          and FGraphNodes[slot][k].Draggable then
        begin
          { a graph on a view, and [F3b] one off a view (cartesian2d, a
            calendar, a matrix, a geo): Draggable drifts the symbol on the
            canvas there }
          if slot <= High(FGraphs) then
          begin
            FGraphDragSlot := slot;
            FGraphDragNode := k;
            FGraphDragX := X;
            FGraphDragY := Y;
            FGraphDragFirst := True;
          end;
          Exit;
        end;
    { a sankey's node, `draggable` along item -> level -> series (default
      true) [Batch 114] }
    if SankeyDragStart(slot, d.DataIndex, X, Y) then Exit;
  end;
  { A PRESS ON A dataZoom (a handle, the move bar, the slider body, a
    zooming grid) is the dataZoom's }
  DataZoomPointer(dpDown, X, Y, Shift, 0);
  { THE BRUSH COMPONENTS' controllers: a press in a panel starts a track,
    not on a draggable element (a slider's handle) [Batch 126] }
  BrushCtlDown(X, Y, FDzDrag.Kind <> dtkNone);
  { THE TOOLBOX'S SELECT BRUSH, a BrushController [Batch 127] }
  TbCtlDown(X, Y, FDzDrag.Kind <> dtkNone);
  { globalPan HELD -- by the toolbox's brush while the zoom is on, by a
    brush component's controller while it draws [Batch 127]: no roam pans
    under it, the inside dataZoom's nor a graph's [Batch 125] }
  if PanTaken then
  begin
    FDzPanGrid := -1;
    Exit;
  end;
  if (FDzDrag.Kind = dtkSlider) or (FDzPanGrid >= 0)
    or ((FDzDownTarget.Kind = dtkSlider) and (FDzDownTarget.Role = dzrClickPanel)) then Exit;
  { the graphs' and [Batch 150] the geos' RoamControllers: the first that
    holds the press arms }
  FRoamSeries := RoamTargetAt(X, Y, False, FRoamGeo);
  FRoamX := X;
  FRoamY := Y;
end;

procedure TTyCustomAdvanceChart.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  d: TTyChartDatumRef;
  el, slot: Integer;
  cap, zrClick: Boolean;
  n: TJSONData;
begin
  TbFrame;
  zrClick := False;
  d := TyChartNoDatum;
  el := -1;
  if Button = mbLeft then
  begin
    FRoamSeries := -1;
    FRoamGeo := -1;
    { dragend [Batch 114] }
    GraphDragEnd;
    FSankeyDragSlot := -1;
    { [R5-D] a handle's dragend: onto the value, a hideTip }
    if FHdDrag >= 0 then HdDragEnd;
    { the target under the release, before anything moves }
    d := HitTestAt(X, Y, el);
    cap := (el >= 0) and (FPaintList <> nil)
      and (FPaintList.Element(el).Caption.FontSizeLogical > 0);
    { zrender's click: pressed and released on the same element, within
      4 px [Batch 153] -- nothing under both is the same too (_downEl ===
      _upEl, both null): the click still reaches the listeners [F4b] }
    zrClick := FPressArmed and (el = FPressEl)
      and (Sqrt(Sqr(X - FPressX) + Sqr(Y - FPressY)) <= 4);
    { zrender's Draggable ends first: a dragged cover's dragend [Batch 126] }
    BrushDragEnd;
    { zrender's mouseup, then the DOM click at the same point }
    DataZoomPointer(dpUp, X, Y, Shift, 0);
    { the brush ends on zrender's mouseup [Batch 125] }
    TbCtlUp(X, Y);
    { and the brush components' controllers [Batch 126] }
    BrushCtlUp(X, Y);
    { the thumbnail's controller lets go; ParallelView's mouseup, after
      the axes' controllers (their views render before it) [Batch 140] }
    FThumbDrag := -1;
    ParExpUp(X, Y);
    DataZoomPointer(dpClick, X, Y, Shift, 0);
    { [F6a] the RoamControllers' mouseup: the pan's cursor given back }
    if not (csDesigning in ComponentState) then CursorAfterUp(X, Y);
    { A CLICK: pressed and released on the same thing -- the same datum, a
      node's disc and its label being different things -- within 4 px. On a
      tree node whose series says `expandAndCollapse: true`, it toggles.
      [Batch 81] }
    if FPressArmed and (d.SeriesIndex >= 0) and not d.IsEdge
      and (d.SeriesIndex = FPressDatum.SeriesIndex)
      and (d.DataIndex = FPressDatum.DataIndex) and not FPressDatum.IsEdge
      and (cap = FPressCaption)
      and (Sqrt(Sqr(X - FPressX) + Sqr(Y - FPressY)) <= 4) then
    begin
      slot := SlotOfSeries(d.SeriesIndex);
      { [Batch 115] a sunburst's piece or return circle; never outside the
        canvas (zrender's isOutsideBoundary hovers nothing there). [R2-B] A
        treemap's container is EventUp's: its onclick before the chart's own
        click, which still names what was pressed. }
      if (X < FLastRect.Left) or (X > FLastRect.Right) or (Y < FLastRect.Top)
        or (Y > FLastRect.Bottom) then
      else if (slot >= 0) and (FBindings[slot].SeriesType = TySunburstSeriesTypeName) then
        SunburstClick(d.SeriesIndex, d.DataIndex)
      else if (slot >= 0) and (FBindings[slot].SeriesType = TyTreemapSeriesTypeName) then
      else if (slot >= 0) and (FBindings[slot].SeriesType = TyTreeSeriesTypeName) then
      begin
        n := FOption.ComponentAt('series', d.SeriesIndex);
        if (n <> nil) and (n.JSONType = jtObject) then
        begin
          n := TJSONObject(n).Find('expandAndCollapse');
          { absent is the default, true; anything but JSON true is off }
          if (n = nil) or ((n.JSONType = jtBoolean) and n.AsBoolean) then
            { [R5-J] the action TreeView dispatches, its event too }
            TreeClickToggle(d.SeriesIndex, d.DataIndex);
        end;
      end;
    end;
    FPressArmed := False;
    { A BREADCRUMB ITEM: pressed and released on it, within 4 px }
    { its click is the item's own onclick, in EventUp [F2a] }
    FCrumbPressed := False;
  end;
  { ParallelView's mouseup hears every button [Batch 140] }
  if (Button <> mbLeft) and not (csDesigning in ComponentState) then ParExpUp(X, Y);
  FEvClickDue := False;
  FEvClickDefer := True;
  try
    if not (csDesigning in ComponentState) then EventUp(Button, X, Y);
  finally
    FEvClickDefer := False;
  end;
  { the click through the pointer's listener [Batch 153] -- [R5-D] before
    the chart's own click event, which is called at last }
  if zrClick and not (csDesigning in ComponentState) then
    PtrListener('click', X, Y, d, el);
  if FEvClickDue then
  begin
    FEvClickDue := False;
    EmitChartEvent('click', FEvClickT, FEvClickX, FEvClickY);
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TTyCustomAdvanceChart.CaptureChanged;
begin
  { THE BUTTON CAME UP SOMEWHERE THIS CONTROL WILL NOT HEAR OF, or another
    window took the mouse. Either way the drag is over. A dataZoom's ends as
    a mouseup where the pointer was last would end it -- its commit and all;
    the widgetset's own mouseup, when it follows, finds nothing to end. }
  FRoamSeries := -1;
  FRoamGeo := -1;
  FThumbDrag := -1;
  GraphDragEnd;
  FSankeyDragSlot := -1;
  { [R5-D] a handle's drag ends as a release would end it }
  if FHdDrag >= 0 then HdDragEnd;
  FPressArmed := False;
  { a visualMap drag ends as a release would end it [Batch 116] }
  VmDragEnd;
  if (FDzDrag.Kind <> dtkNone) or (FDzPanGrid >= 0) then
    DataZoomPointer(dpUp, FDzLastX, FDzLastY, [], 0);
  { a brush ends as a release would end it [Batch 125] }
  TbCtlUp(FEvLastX, FEvLastY);
  { a cover's drag and a brush component's track too [Batch 126] }
  BrushDragEnd;
  BrushCtlUp(FEvLastX, FEvLastY);
  { and the timeline's checkpoint [Batch 129] }
  TlDragEnd(FEvLastX, FEvLastY);
  inherited CaptureChanged;
end;

function TTyCustomAdvanceChart.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  wd: TTyChartDatumRef;
  wel: Integer;
begin
  { THE HOST'S HANDLER FIRST, and one that takes the wheel keeps it. }
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if csDesigning in ComponentState then Exit;
  try
    Result := WheelRoam(Shift, WheelDelta, MousePos);
  finally
    { the pointer's global listener hears the wheel too, after the roams
      [Batch 153] }
    wd := HitTestAt(MousePos.X, MousePos.Y, wel);
    PtrListener('mousewheel', MousePos.X, MousePos.Y, wd, wel);
  end;
end;

function TTyCustomAdvanceChart.WheelRoam(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  s: Double;
  si, gi: Integer;
begin
  Result := False;
  { THE THUMBNAIL'S wheel, the first roam listener (z 10): in its content
    rect it zooms its graph and is consumed [Batch 140] }
  if ThumbWheel(MousePos.X, MousePos.Y, WheelDelta) then Exit(True);
  { a wheel in a zooming grid is the dataZoom's, and stopped there }
  if DataZoomPointer(dpWheel, MousePos.X, MousePos.Y, Shift,
    TyDzZrDelta(WheelDelta)) then Exit(True);
  s := TyGraphWheelScale(WheelDelta);
  if s = 0 then Exit;
  si := RoamTargetAt(MousePos.X, MousePos.Y, True, gi);
  { [Batch 150] a geo's RoamController took it: a geoRoam zoom about the
    pointer, the wheel consumed }
  if gi >= 0 then
  begin
    GeoGesture(gi, False, 0, 0, True, s, MousePos.X, MousePos.Y);
    Exit(True);
  end;
  if si < 0 then Exit;
  { [R5-J] the series' RoamController dispatches its roam: the event too }
  FRoamEvSrc := 1;
  try
    if IsTreeSeries(si) then Result := TreeZoom(si, s, MousePos.X, MousePos.Y)
    else if IsSankeySeries(si) then Result := SankeyZoom(si, s, MousePos.X, MousePos.Y)
    { [Batch 115] }
    else if IsTreemapSeries(si) then Result := TreemapWheel(si, s, MousePos.X, MousePos.Y)
    else Result := GraphZoom(si, s, MousePos.X, MousePos.Y);
  finally
    FRoamEvSrc := 0;
  end;
end;

function TTyCustomAdvanceChart.SlotOfSeries(ASeriesIndex: Integer): Integer;
var i: Integer;
begin
  for i := 0 to High(FBindings) do
    if FBindings[i].SeriesIndex = ASeriesIndex then Exit(i);
  Result := -1;
end;

function TTyCustomAdvanceChart.NearestRowOn(ASlot: Integer; AX, AY: Double): Integer;
var
  axis: TTyAxis;
  st: TTyDataStore;
  col, i: Integer;
  want, v, d, best: Double;
begin
  Result := -1;
  if (ASlot < 0) or (ASlot > High(FBindings)) or (ASlot > High(FStores)) then Exit;
  axis := FBindings[ASlot].BaseAxis;
  st := FStores[ASlot];
  if (axis = nil) or (st = nil) then Exit;
  col := st.DimIndexOf(axis.Dim);
  if col < 0 then Exit;
  { WHICH COORDINATE THE BASE AXIS READS. Not "x for a line": on a horizontal
    bar chart the spine runs vertically, and asking a y axis about an x pixel
    answers a number that is the right shape and the wrong measurement. The
    binding already knows which of its two axes is the base one. }
  if axis = FBindings[ASlot].XAxis then want := AX else want := AY;
  { CoordToData extrapolates rather than failing, and has no NaN guard of its
    own -- a degenerate axis can hand back one. }
  want := axis.CoordToData(want);
  if IsNan(want) then Exit;
  best := NaN;
  for i := 0 to st.Count - 1 do
  begin
    v := st.Get(col, i);
    if IsNan(v) then Continue;
    d := Abs(v - want);
    if IsNan(best) or (d < best) then
    begin
      best := d;
      Result := i;
    end;
  end;
end;

function TTyCustomAdvanceChart.HitTestAt(AX, AY: Integer): TTyChartDatumRef;
var ignored: Integer;
begin
  Result := HitTestAt(AX, AY, ignored);
end;

{ [R5-J] canvas by canvas from the highest, as EventTargetAt }
function TTyCustomAdvanceChart.HitTestAt(AX, AY: Integer;
  out AElement: Integer): TTyChartDatumRef;
var
  lv: TTyIntegerArray;
  i: Integer;
  blocked: Boolean;
begin
  lv := HitLevels;
  if Length(lv) <= 1 then Exit(HitTestIn(AX, AY, AElement, blocked));
  for i := High(lv) downto 0 do
  begin
    FHitBandOn := True;
    FHitLo := lv[i] - 1;
    FHitHi := lv[i];
    try
      Result := HitTestIn(AX, AY, AElement, blocked);
    finally
      FHitBandOn := False;
    end;
    if (AElement >= 0) or blocked then Exit;
  end;
  Result := TyChartNoDatum;
  AElement := -1;
end;

function TTyCustomAdvanceChart.HitTestIn(AX, AY: Integer; out AElement: Integer;
  out ABlocked: Boolean): TTyChartDatumRef;
var
  idx, slot, row, bb, bi: Integer;
  bp: TTyBrushPiece;
  axT: TTyChartEventTarget;
begin
  Result := TyChartNoDatum;
  AElement := -1;
  ABlocked := False;
  if (FPaintList = nil) or not FPaintListValid then Exit;
  { [R5-D] the loading mask over everything -- [R5-J] on its own canvas }
  if LoadMasks and HitIn(MaskZLevel) then
  begin
    ABlocked := True;
    Exit;
  end;
  { A BRUSH COVER over the item is the target: nothing beneath it is
    hovered or pressed [Batch 126] -- [R5-J] on zlevel 0 }
  if HitIn(0) and BrushPieceAt(AX, AY, bb, bi, bp) then
  begin
    ABlocked := True;
    Exit;
  end;
  { [R5-D] an axis pointer's handle (z 50) over the series -- [R5-J] the
    axes' level }
  if HitIn(ComponentZLevel) and (HdAt(AX, AY) >= 0) then
  begin
    ABlocked := True;
    Exit;
  end;
  { IN MOTION, WHAT IS DRAWN IS WHAT IS HIT: the frame keeps the list's
    insertion indices, so the element named is the list's [Batch 89] }
  { and AT REST ON A STATE PROXY, where the list keeps the rest values (a
    selected slice is out, a hovered symbol larger) [Batch 94] }
  { the direct test, then the coarse pointer's fallback [Batch 142] }
  idx := ListHitAt(AX, AY);
  if idx < 0 then Exit;
  { [R7-G] AN AXIS' PART that is not silent, above the element in z, takes
    the pointer: nothing under it is hovered or pressed }
  if AxisPartAt(AX, AY, FPaintList.Element(idx).Z, FPaintList.Element(idx).Z2,
    True, axT) then
  begin
    ABlocked := True;
    Exit;
  end;
  AElement := idx;
  { [R2-B] a breadcrumb item names no datum (its ecData has no dataIndex):
    no tooltip, no select, and nothing under it either; [R2-I1] nor does a
    tree's edge }
  if CrumbOfElement(idx, slot, row) then Exit;
  if FPaintList.Element(idx).Anim.Role = carTreeEdge then Exit;
  Result := FPaintList.Element(idx).Datum;
  if Result.SeriesIndex < 0 then Exit;
  { A LARGE BATCH: the row is its own scan's, and a hit without one (a
    candle's path, a bar's clip letting a gap through) names the element
    and no datum [Batch 117] }
  if FPaintList.Element(idx).Shape.Kind = cskLarge then
  begin
    row := LargeRowAt(idx, AX, AY);
    slot := SlotOfSeries(Result.SeriesIndex);
    if (row < 0) or (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then
      Exit(TyChartNoDatum);
    Exit(TyChartDatum(Result.SeriesIndex, row, FStores[slot].GetRawIndex(row)));
  end;
  { A RUN ELEMENT -- one element standing for a whole series, which is what a
    line's stroke is. The list reports it as `(series, -1)`, which
    TyChartDatumValid rejects, and because the hit test answers with the
    topmost element rather than falling through, a hit there would otherwise
    name nothing at all. }
  if Result.DataIndex < 0 then
  begin
    slot := SlotOfSeries(Result.SeriesIndex);
    row := NearestRowOn(slot, AX, AY);
    if row < 0 then
    begin
      AElement := -1;
      Exit(TyChartNoDatum);
    end;
    Result := TyChartDatum(Result.SeriesIndex, row,
      FStores[slot].GetRawIndex(row));
  end;
end;

{ ==================== the chart's mouse events [Batch 84] ==================== }

function TTyCustomAdvanceChart.ChartOn(const AType: string;
  AHandler: TTyChartEventHandler; const AQuery: string): Integer;
var
  t: string;
  i: Integer;
begin
  Result := -1;
  t := TyChartEventTypeOf(AType);
  if (t = '') or not Assigned(AHandler) then Exit;
  { THE SAME FUNCTION TWICE FOR ONE TYPE IS KEPT ONCE, whatever the second
    query -- zrender's Eventful.on }
  for i := 0 to High(FEventRegs) do
    if (FEventRegs[i].EventType = t)
      and (TMethod(FEventRegs[i].Handler).Code = TMethod(AHandler).Code)
      and (TMethod(FEventRegs[i].Handler).Data = TMethod(AHandler).Data) then
      Exit(FEventRegs[i].Id);
  Inc(FEventNextId);
  SetLength(FEventRegs, Length(FEventRegs) + 1);
  FEventRegs[High(FEventRegs)].Id := FEventNextId;
  FEventRegs[High(FEventRegs)].EventType := t;
  FEventRegs[High(FEventRegs)].Query := TyEventQueryOf(AQuery);
  FEventRegs[High(FEventRegs)].Handler := AHandler;
  Result := FEventNextId;
end;

procedure TTyCustomAdvanceChart.ChartOff(AId: Integer);
var i, k: Integer;
begin
  for i := 0 to High(FEventRegs) do
    if FEventRegs[i].Id = AId then
    begin
      for k := i to High(FEventRegs) - 1 do FEventRegs[k] := FEventRegs[k + 1];
      SetLength(FEventRegs, Length(FEventRegs) - 1);
      Exit;
    end;
end;

procedure TTyCustomAdvanceChart.SilenceSeries(AList: TTyPaintList);
var
  silent: array of Boolean;
  i, k: Integer;
  n, d: TJSONData;
  el: TTyChartElement;
  any: Boolean;
begin
  silent := nil;
  SetLength(silent, FOption.ComponentCount('series'));
  any := False;
  for i := 0 to High(silent) do
  begin
    n := FOption.ComponentAt('series', i);
    { `!!seriesModel.get('silent')`: the series' own, or -- null or not
      written -- the option root's, through the model's parent [F4c] }
    d := TyGetShallowRoot(n, FOption.Root, 'silent');
    silent[i] := TyOptTruthy(d);
    any := any or silent[i];
  end;
  if not any then Exit;
  for k := 0 to AList.Count - 1 do
  begin
    el := AList.Element(k);
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex < 0)
      or (el.Datum.SeriesIndex > High(silent)) or not silent[el.Datum.SeriesIndex] then
      Continue;
    el.Silent := True;
    AList.SetElement(k, el);
  end;
end;

procedure TTyCustomAdvanceChart.StampCursors(AList: TTyPaintList);
var
  k, si, slot, raw, depth: Integer;
  pe: PTyChartElement;
  st, c: string;
  root, series, item, lvl: TJSONObject;
  rootCur: string;

  function CurOf(AObj: TJSONObject; out AValue: string): Boolean;
  var x: TJSONData;
  begin
    Result := False;
    AValue := '';
    if AObj = nil then Exit;
    x := AObj.Find('cursor');
    if (x = nil) or (x.JSONType = jtNull) then Exit;
    Result := True;
    if x.JSONType = jtString then AValue := x.AsString
    else AValue := x.AsJSON;
  end;

  { getShallow('cursor') up the item model's parents: the item, its level
    (treemap, sunburst) or category (graph), the series, the root; '' none }
  function Chain(AItem, AMid, ASeries: TJSONObject): string;
  begin
    if CurOf(AItem, Result) then Exit;
    if CurOf(AMid, Result) then Exit;
    if CurOf(ASeries, Result) then Exit;
    Result := rootCur;
  end;

  function LevelOf(ASeries: TJSONObject; ADepth: Integer): TJSONObject;
  var x: TJSONData;
  begin
    Result := nil;
    if (ASeries = nil) or (ADepth < 0) then Exit;
    x := ASeries.Find('levels');
    if (x is TJSONArray) and (ADepth < TJSONArray(x).Count)
      and (TJSONArray(x).Items[ADepth] is TJSONObject) then
      Result := TJSONObject(TJSONArray(x).Items[ADepth]);
  end;

  function CategoryOf(ASeries, AItem: TJSONObject): TJSONObject;
  var x, cats: TJSONData; ci: Integer;
  begin
    Result := nil;
    if (ASeries = nil) or (AItem = nil) then Exit;
    x := AItem.Find('category');
    if (x = nil) or (x.JSONType <> jtNumber) then Exit;
    ci := Trunc(x.AsFloat);
    cats := ASeries.Find('categories');
    if (cats is TJSONArray) and (ci >= 0) and (ci < TJSONArray(cats).Count)
      and (TJSONArray(cats).Items[ci] is TJSONObject) then
      Result := TJSONObject(TJSONArray(cats).Items[ci]);
  end;

  function GraphDraggable(ASlot, ARow: Integer): Boolean;
  var q: Integer;
  begin
    Result := False;
    if (ASlot < 0) or (ASlot > High(FGraphNodes)) then Exit;
    for q := 0 to High(FGraphNodes[ASlot]) do
      if FGraphNodes[ASlot][q].Row = ARow then Exit(FGraphNodes[ASlot][q].Draggable);
  end;

begin
  if (FOption = nil) or (AList = nil) then Exit;
  root := nil;
  if FOption.Root is TJSONObject then root := TJSONObject(FOption.Root);
  rootCur := '';
  CurOf(root, rootCur);
  for k := 0 to AList.Count - 1 do
  begin
    pe := AList.Ref(k);
    if (pe^.Datum.Kind <> ctkSeries) or (pe^.Datum.SeriesIndex < 0) then Continue;
    if pe^.Silent or pe^.IsGuide then Continue;
    { a label is a text of its own: the prototype's pointer }
    if pe^.Caption.FontSizeLogical > 0 then Continue;
    { [R2-I1] so is a tree's edge (no item cursor: the Symbol's path takes
      that) }
    if pe^.Anim.Role = carTreeEdge then Continue;
    si := pe^.Datum.SeriesIndex;
    slot := SlotOfSeries(si);
    if slot < 0 then Continue;
    st := FBindings[slot].SeriesType;
    series := StSeriesNode(si);
    c := '';
    { A LARGE BATCH: LargeSymbolDraw's and LargeLineDraw's 'default'; a
      large candlestick takes its series' cursor }
    if pe^.Shape.Kind = cskLarge then
    begin
      if (st = 'scatter') or (st = 'effectScatter') or (st = TyLinesSeriesTypeName) then
        c := 'default'
      else if st = 'candlestick' then
      begin
        if not CurOf(series, c) then c := rootCur;
      end;
    end
    else if pe^.Datum.DataIndex >= 0 then
    begin
      raw := pe^.Datum.RawDataIndex;
      if raw < 0 then raw := pe^.Datum.DataIndex;
      if (st = 'bar') or (st = 'pictorialBar') or (st = 'candlestick')
        or (st = 'scatter') or (st = 'effectScatter') or (st = 'line')
        or (st = 'pie') or (st = TyTreeSeriesTypeName) then
      begin
        { a line's polyline and area have no row; its symbols do }
        item := StItemNode(si, raw);
        c := Chain(item, nil, series);
      end
      else if st = TySunburstSeriesTypeName then
      begin
        item := StItemNode(si, raw);
        depth := -1;
        if (slot <= High(FSunbursts)) and FSunbursts[slot].Valid
          and (raw <= High(FSunbursts[slot].Hier.Nodes)) then
          depth := FSunbursts[slot].Hier.Nodes[raw].Depth;
        c := Chain(item, LevelOf(series, depth), series);
      end
      else if st = TyTreemapSeriesTypeName then
      begin
        { only a leaf's content rect (TreemapView.renderNode) }
        if (pe^.Anim.Role = carTmRect) and (pe^.Anim.Sub = 1) then
        begin
          item := StItemNode(si, raw);
          depth := -1;
          if (slot <= High(FTreemaps)) and FTreemaps[slot].Valid
            and (raw <= High(FTreemaps[slot].Hier.Nodes)) then
            depth := FTreemaps[slot].Hier.Nodes[raw].Depth;
          c := Chain(item, LevelOf(series, depth), series);
        end;
      end
      else if (st = TyGraphSeriesTypeName) and not pe^.Datum.IsEdge then
      begin
        { setDraggable(draggable, !!itemModel.get('cursor')): 'move' on a
          draggable node with no cursor anywhere up its chain }
        item := StItemNode(si, raw);
        lvl := CategoryOf(series, item);
        c := Chain(item, lvl, series);
        if (c = '') and GraphDraggable(slot, pe^.Datum.DataIndex) then c := 'move';
      end
      else if (st = TySankeySeriesTypeName) and not pe^.Datum.IsEdge then
      begin
        { SankeyView: a draggable node's rect is 'move', whatever else }
        if (slot <= High(FSankeys)) and FSankeys[slot].Valid
          and (pe^.Datum.DataIndex <= High(FSankeys[slot].Nodes))
          and TySankeyDraggable(FSankeys[slot], pe^.Datum.DataIndex) then
          c := 'move';
      end;
    end;
    if c = '' then Continue;
    { the cursor does not decide the paint order: written in place [P2] }
    pe^.Cursor := c;
  end;
end;

function TTyCustomAdvanceChart.SeriesEventModel(ASeriesIndex: Integer): TTyEventModel;
var slot: Integer;
begin
  Result := Default(TTyEventModel);
  slot := SlotOfSeries(ASeriesIndex);
  if slot < 0 then Exit;
  Result.Valid := True;
  Result.MainType := 'series';
  Result.SubType := FBindings[slot].SeriesType;
  Result.Index := ASeriesIndex;
  Result.Name := SeriesModelName(ASeriesIndex);
  Result.Id := SeriesIdOf(FOption, ASeriesIndex);
end;

{ A SERIES ITEM'S params: upstream's getDataParams -- the raw index, the value
  as String() prints it (absent when undefined), 'main' for the tree family's
  data type -- or, for the one element that stands for a whole line, the
  series' own params with selfType 'line', and then only when the series
  says triggerEvent. }
function TTyCustomAdvanceChart.SeriesEventTarget(const ADatum: TTyChartDatumRef;
  AElement: Integer): TTyChartEventTarget;
var
  gel: TTyGfxEl;
  slot: Integer;
  p: TTyChartCallbackParams;
  n, d: TJSONData;
  st: string;
  cv: Double;
  cvText: string;
begin
  Result := Default(TTyChartEventTarget);
  Result.Id := AElement + 1;
  if ADatum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if slot < 0 then Exit;
  st := FBindings[slot].SeriesType;
  if ADatum.DataIndex < 0 then
  begin
    n := FOption.ComponentAt('series', ADatum.SeriesIndex);
    d := nil;
    if n is TJSONObject then d := TJSONObject(n).Find('triggerEvent');
    { [F6a] A LINE'S POLYLINE AND ITS AREA (LineView.packEventData): the
      polyline's eventData with triggerEvent true or 'line', the area's
      with true or 'area' -- either with the deprecated triggerLineEvent
      true -- selfType saying which }
    if (st = 'line') and (FPaintList <> nil) and (AElement >= 0)
      and (AElement < FPaintList.Count) then
    begin
      p := TyChartBlankParams;
      if FPaintList.Element(AElement).Anim.Role = carLineArea then p.SelfType := 'area'
      else p.SelfType := 'line';
      if not (((d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean)
        or ((d <> nil) and (d.JSONType = jtString) and (d.AsString = p.SelfType))) then
      begin
        d := nil;
        if n is TJSONObject then d := TJSONObject(n).Find('triggerLineEvent');
        if not ((d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean) then Exit;
      end;
    end
    else
    begin
      if not ((d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean) then Exit;
      p := TyChartBlankParams;
      p.SelfType := st;
    end;
  end
  else
  begin
    p := TooltipParams(ADatum);
    if ADatum.IsEdge then
    begin
      if Length(p.Values) > 0 then p.ValueText := TyChartValueText(p.Values[0]);
    end
    else if p.Raw.Shape <> rshNone then
      p.ValueText := TyRawItemText(p.Raw);
    if p.ValueText = 'undefined' then p.ValueText := '';
    { a chord node's getDataParams: `params.value == null` takes the
      layout's value [Batch 120] }
    if (not ADatum.IsEdge) and (st = TyChordSeriesTypeName)
      and (slot <= High(FChords)) and FChords[slot].Valid
      and TyChordNodeValue(FChords[slot], ADatum.RawDataIndex, cv, cvText) then
      p.ValueText := cvText;
    if (st = TyTreemapSeriesTypeName) or (st = TySunburstSeriesTypeName)
      or (st = TyTreeSeriesTypeName) then
      p.DataType := 'main';
  end;
  p.ComponentType := 'series';
  p.ComponentSubType := st;
  p.ComponentIndex := ADatum.SeriesIndex;
  p.SeriesType := st;
  p.SeriesIndex := ADatum.SeriesIndex;
  p.SeriesName := SeriesModelName(ADatum.SeriesIndex);
  p.SeriesId := SeriesIdOf(FOption, ADatum.SeriesIndex);
  { A CUSTOM ELEMENT'S info rides the event: CustomSeries.getDataParams
    reads the target element's own [Batch 123] }
  gel := CustomPaintSource(AElement);
  if (gel <> nil) and (gel.Info <> nil) then p.Info := gel.Info.AsJSON;
  Result.HasData := True;
  Result.Params := p;
  Result.Model := SeriesEventModel(ADatum.SeriesIndex);
end;

function TriggersEvent(ANode: TJSONData): Boolean;
var d: TJSONData;
begin
  Result := False;
  if not (ANode is TJSONObject) then Exit;
  d := TJSONObject(ANode).Find('triggerEvent');
  Result := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
end;

{ [R2-B] THE TARGET A MARKER ELEMENT IS (EventTargetAt's marker branch, by
  list index): the marker model's own index among its kind and its HOST's
  series fields; HdKind 3 }
function TTyCustomAdvanceChart.MarkerEventTarget(AIdx: Integer): TTyChartEventTarget;
const
  cKindWord: array[TTyChartTargetKind] of string = ('series', 'markPoint',
    'markLine', 'markArea', 'legend', 'legend', 'legend', 'graphic', 'matrix', 'geo',
    'axis');
var
  k, q, slot, nth: Integer;
  d: TTyChartDatumRef;
  kind: TTyMarkerKind;
  mk: TTyMkBlock;
begin
  Result := Default(TTyChartEventTarget);
  Result.Params := TyChartBlankParams;
  if (FPaintList = nil) or (AIdx < 0) or (AIdx >= FPaintList.Count) then Exit;
  d := FPaintList.Element(AIdx).Datum;
  if not (d.Kind in [ctkMarkPoint, ctkMarkLine, ctkMarkArea]) then Exit;
  Result.Id := AIdx + 1;
  slot := SlotOfSeries(d.ComponentIndex);
  if slot < 0 then Exit;
  if d.Kind = ctkMarkPoint then kind := mkPoint
  else if d.Kind = ctkMarkLine then kind := mkLine
  else kind := mkArea;
  { THE MARKER MODEL'S OWN INDEX among its kind, and its HOST's
    series fields: MarkerModel.getDataParams }
  nth := 0;
  for k := 0 to High(FMarkers) do
  begin
    if FMarkers[k].SeriesIndex = d.ComponentIndex then Break;
    if FMarkers[k].Blocks[kind].Present then Inc(nth);
  end;
  Result.HasData := True;
  Result.Params.ComponentType := cKindWord[d.Kind];
  Result.Params.ComponentSubType := '';
  Result.Params.ComponentIndex := nth;
  Result.Params.SeriesType := FBindings[slot].SeriesType;
  Result.Params.SeriesIndex := d.ComponentIndex;
  Result.Params.SeriesName := SeriesModelName(d.ComponentIndex);
  Result.Params.SeriesId := SeriesIdOf(FOption, d.ComponentIndex);
  Result.Params.DataIndex := d.DataIndex;
  Result.Params.RawDataIndex := d.DataIndex;
  for k := 0 to High(FMarkers) do
    if FMarkers[k].SeriesIndex = d.ComponentIndex then
    begin
      mk := FMarkers[k].Blocks[kind];
      if kind = mkPoint then
      begin
        for q := 0 to High(mk.Points) do
          if mk.Points[q].DataIndex = d.DataIndex then
          begin
            if mk.Points[q].E.Name.Kind = mvkStr then
              Result.Params.Name := mk.Points[q].E.Name.Str
            else if mk.Points[q].E.Name.Kind = mvkNum then
              Result.Params.Name := TyChartValueText(mk.Points[q].E.Name.Num);
            if mk.Points[q].E.Value.Kind = mvkNum then
              Result.Params.ValueText := TyChartValueText(mk.Points[q].E.Value.Num)
            else if mk.Points[q].E.Value.Kind = mvkStr then
              Result.Params.ValueText := mk.Points[q].E.Value.Str;
          end;
      end;
      Break;
    end;
  { a query is matched against the host series }
  Result.Model := SeriesEventModel(d.ComponentIndex);
  { ITS ECData HAS A dataIndex, the marker's, and the host's
    seriesIndex: a click on it dispatches select for the HOST
    series' item at that index [Batch 88] }
  Result.HdKind := 3;
  Result.HdSeries := d.ComponentIndex;
  Result.HdRow := d.DataIndex;
end;

{ [R2-B] the breadcrumb item the list element at AIdx is (its polygon, or its
  words hung off it) }
function TTyCustomAdvanceChart.CrumbOfElement(AIdx: Integer; out ASeries, AIndex: Integer): Boolean;
var el: PTyChartElement; h: Integer;
begin
  Result := False;
  ASeries := -1;
  AIndex := -1;
  if (FPaintList = nil) or (AIdx < 0) or (AIdx >= FPaintList.Count) then Exit;
  el := FPaintList.Ref(AIdx);
  if (el^.Anim.Role <> carTmCrumb) and (el^.Caption.FontSizeLogical > 0) then
  begin
    h := el^.Caption.LmHostPlus1 - 1;
    if (h < 0) or (h >= FPaintList.Count) then Exit;
    el := FPaintList.Ref(h);
  end;
  if el^.Anim.Role <> carTmCrumb then Exit;
  ASeries := el^.Anim.Series;
  AIndex := el^.Anim.Index;
  Result := True;
end;

{ [F2a] A TREEMAP'S BREADCRUMB ITEM: a highDownDispatcher whose ecData holds
  only eventData -- componentType 'series', selfType 'breadcrumb', nodeData
  (Breadcrumb.ts packEventData) -- no dataIndex, so no select and no
  tooltip; HdGen the solve that drew it }
function TTyCustomAdvanceChart.CrumbTarget(ASeries, AIndex: Integer): TTyChartEventTarget;
var slot, i: Integer; nm: string;
begin
  Result := Default(TTyChartEventTarget);
  Result.Params := TyChartBlankParams;
  slot := SlotOfSeries(ASeries);
  Result.Id := -(11000000000 + Int64(FTmCrumbGen) * 1000000 + Int64(ASeries) * 1000 + AIndex);
  Result.HdKind := 15;
  Result.HdSeries := ASeries;
  Result.HdRow := AIndex;
  Result.HdGen := FTmCrumbGen;
  Result.HasData := True;
  Result.Params.ComponentType := 'series';
  Result.Params.ComponentSubType := TyTreemapSeriesTypeName;
  Result.Params.ComponentIndex := ASeries;
  Result.Params.SeriesType := TyTreemapSeriesTypeName;
  Result.Params.SeriesIndex := ASeries;
  Result.Params.SeriesName := SeriesModelName(ASeries);
  Result.Params.SelfType := 'breadcrumb';
  if (slot >= 0) and (slot <= High(FTreemaps)) and (AIndex <= High(FTreemaps[slot].Crumbs)) then
  begin
    i := FTreemaps[slot].Crumbs[AIndex].Row;
    nm := '';
    if (i >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil)
      and (i < FStores[slot].Count) then nm := FStores[slot].GetItemName(i);
    Result.Params.NodeData := '{"dataIndex":' + IntToStr(i) + ',"name":"'
      + StringToJSONString(nm) + '"}';
  end;
  Result.Model := SeriesEventModel(ASeries);
end;

{ [R5-J] THE POINTER FINDS THE TOP CANVAS FIRST: zrender's handler walks
  the display list sorted by zlevel, then z. Where everything stands on one
  zlevel the search is the one it always was; else canvas by canvas from
  the highest, each with the order of its own -- a title of zlevel 2 over a
  series of 1, a series of 1 over the loading mask of 0 [was: the
  components apart from the list first, the mask over everything] }
function TTyCustomAdvanceChart.EventTargetAt(AX, AY: Integer): TTyChartEventTarget;
var
  lv: TTyIntegerArray;
  i: Integer;
  blocked: Boolean;
begin
  lv := HitLevels;
  if Length(lv) <= 1 then Exit(EventTargetIn(AX, AY, blocked));
  for i := High(lv) downto 0 do
  begin
    FHitBandOn := True;
    FHitLo := lv[i] - 1;
    FHitHi := lv[i];
    try
      Result := EventTargetIn(AX, AY, blocked);
    finally
      FHitBandOn := False;
    end;
    if (Result.Id <> 0) or blocked then Exit;
  end;
  Result := Default(TTyChartEventTarget);
  Result.Params := TyChartBlankParams;
end;

function TTyCustomAdvanceChart.EventTargetIn(AX, AY: Integer;
  out ABlocked: Boolean): TTyChartEventTarget;
var
  i, k, q, idx, slot: Integer;
  lay: TTyTitleLayout;
  r: TTyRectF;
  el: TTyChartElement;
  d: TTyChartDatumRef;
  node: TJSONData;
  nm: string;
  gel: TTyGfxEl;
  piece: TTyBrushPiece;
  mxc: TTyMatrix;
  mxInfo: TTyMatrixCellInfo;
  geo: TTyGeo;
  axT: TTyChartEventTarget;

  function Inside(const AR: TTyRectF): Boolean;
  begin
    Result := (AX >= AR.Left) and (AX <= AR.Right) and (AY >= AR.Top)
      and (AY <= AR.Bottom);
  end;

  function Hung(AXa, AYa, AW, AH: Double; AAlign: TTyTitleAlign;
    AVAlign: TTyTitleVAlign): TTyRectF;
  var l, t: Double;
  begin
    case AAlign of
      ttaCentre: l := AXa - AW / 2;
      ttaRight: l := AXa - AW;
    else
      l := AXa;
    end;
    case AVAlign of
      ttvMiddle: t := AYa - AH / 2;
      ttvBottom: t := AYa - AH;
    else
      t := AYa;
    end;
    Result := TyRectF(l, t, l + AW, t + AH);
  end;

begin
  Result := Default(TTyChartEventTarget);
  Result.Params := TyChartBlankParams;
  ABlocked := False;
  { [R5-D] the loading mask: no ECData, no event -- [R5-J] on its own
    canvas: nothing under it is found }
  if LoadMasks and HitIn(MaskZLevel) then
  begin
    ABlocked := True;
    Exit;
  end;
  { THE BRUSH'S COVERS, z 10000 over everything [Batch 126]: no data, only
    zrender's Draggable -- [R5-J] its controller's group: zlevel 0 }
  if HitIn(0) and BrushPieceAt(AX, AY, k, q, piece) then
  begin
    Result.Id := -((Int64(9) shl 44) + (Int64(k) shl 36)
      + Int64(BrushCtlOf(k).Covers[q].Serial) * 16 + Ord(piece));
    Result.HdKind := 9;
    Result.HdSeries := k;
    Result.HdRow := BrushCtlOf(k).Covers[q].Serial;
    Result.HdGen := Ord(piece);
    Exit;
  end;
  { A BREAK AREA THAT EXPANDS ON A CLICK, zigzagZ (100) over the rest: no
    data, only its group's click [Batch 132] -- [R5-J] the axes' level }
  if HitIn(ComponentZLevel) and BreakAreaAt(AX, AY, k, q) then
  begin
    Result.Id := -((Int64(10) shl 44) + Int64(k) * 1000 + q);
    Result.HdKind := 12;
    Result.HdSeries := k;
    Result.HdRow := q;
    Exit;
  end;
  { [R5-D] AN AXIS POINTER'S HANDLE (z 50): a target without ECData -- no
    event -- its cursor 'move' }
  if HitIn(ComponentZLevel) then k := HdAt(AX, AY) else k := -1;
  if k >= 0 then
  begin
    Result.Id := -((Int64(17) shl 44) + k);
    Result.HdKind := 17;
    Result.HdRow := k;
    Exit;
  end;
  { THE TITLES, over everything but the tooltip: the text and the subtext are
    two targets }
  for i := 0 to High(FTitles) do
  begin
    lay := FTitles[i];
    if not lay.Valid then Continue;
    { [R5-J] on its own zlevel's canvas, the mask over a lower one }
    if not HitIn(ModelZLevel('title', i)) or MaskOver(ModelZLevel('title', i)) then Continue;
    for k := 0 to 1 do
    begin
      if (k = 1) and not lay.HasSub then Continue;
      if (k = 0) and ((i > High(FTitleSpecs)) or (FTitleSpecs[i].Text = '')) then Continue;
      if k = 0 then r := Hung(lay.TextX, lay.TextY, lay.TextW, lay.TextH, lay.Align, lay.VAlign)
      else r := Hung(lay.SubX, lay.SubY, lay.SubW, lay.SubH, lay.Align, lay.VAlign);
      if not Inside(r) then Continue;
      { [F6a] `textEl.silent = !link && !triggerEvent` (the subtext's by
        sublink): a silent title is no target -- the pointer goes on to
        what is under it }
      if not TriggersEvent(FOption.ComponentAt('title', i)) then
      begin
        node := FOption.ComponentAt('title', i);
        if not (node is TJSONObject) then Continue;
        if k = 0 then node := TJSONObject(node).Find('link')
        else node := TJSONObject(node).Find('sublink');
        if (node = nil) or not (((node.JSONType = jtString) and (node.AsString <> ''))
          or ((node.JSONType = jtNumber) and (node.AsFloat <> 0))
          or ((node.JSONType = jtBoolean) and node.AsBoolean)
          or (node.JSONType in [jtObject, jtArray])) then Continue;
      end;
      Result.Id := -(1000 + 2 * i + k);
      if TriggersEvent(FOption.ComponentAt('title', i)) then
      begin
        Result.HasData := True;
        Result.Params.ComponentType := 'title';
        Result.Params.ComponentIndex := i;
        Result.Model.Valid := True;
        Result.Model.MainType := 'title';
        Result.Model.Index := i;
      end;
      Exit;
    end;
  end;
  { THE TOOLBOX, z 6 [Batch 125]: no data, only its icons' own handlers }
  if TbHitAt(AX, AY, k, q) then
  begin
    Result.Id := -(8000000 + Int64(k) * 10000 + q);
    Result.HdKind := 8;
    Result.HdSeries := k;
    Result.HdRow := q;
    Result.HdGen := FTbGen;
    Exit;
  end;
  { THE TIMELINES, z 4 [Batch 129]: no data, only their elements' own
    handlers; HdRow the element, HdGen the render that made it, HdSeries
    the timeline's slot [R5-G] }
  if TlHitAt(AX, AY, k, q) then
  begin
    if k = 0 then Result.Id := -(10000000 + Int64(q))
    else Result.Id := -((Int64(19) shl 44) + (Int64(k) shl 30) + q);
    Result.HdKind := 10;
    Result.HdSeries := k;
    Result.HdRow := q;
    Result.HdGen := TlView(k).Gen;
    { [R5-I] a tick that is a data item: the timeline's params }
    if TlTickData(k, q, Result.Params, Result.Model) then Result.HasData := True;
    Exit;
  end;
  { THE visualMaps, over the series (z 4) [Batch 116]: no data, only their
    own handlers }
  if VmHitAt(AX, AY, k, q) then
  begin
    Result.Id := -(7000000 + Int64(k) * 10000 + q);
    Result.HdKind := 7;
    Result.HdSeries := k;
    Result.HdRow := q;
    if k <= High(FVmLive) then Result.HdGen := FVmLive[k].Gen;
    Exit;
  end;
  { THE DISPLAY LIST: series items, their labels, markers, legend items --
    as DRAWN: in motion, or on a state proxy, the frame (its insertion
    indices are the list's) [Batch 94] }
  { the direct test, then the coarse pointer's fallback [Batch 142] }
  idx := ListHitAt(AX, AY);
  if idx >= 0 then
  begin
    { [R7-G] AN AXIS' PART ABOVE THE ELEMENT IN z -- a label that is not
      silent over a series of z below the axis' -- takes the pointer }
    if AxisPartAt(AX, AY, FPaintList.Element(idx).Z, FPaintList.Element(idx).Z2,
      True, axT) then Exit(axT);
    { [R2-B] A BREADCRUMB ITEM is in the treemap view's own group (its z,
      z2 1e5): what is drawn over it -- a legend, a marker -- takes the
      pointer first [F2a: it was tested before the whole list] }
    if CrumbOfElement(idx, k, q) then Exit(CrumbTarget(k, q));
    el := FPaintList.Element(idx);
    d := el.Datum;
    Result.Id := idx + 1;
    { [R2-I1] A TREE'S EDGE: a target of no data (no ecData): no event, no
      dispatcher, the prototype's pointer cursor, and nothing under it }
    if el.Anim.Role = carTreeEdge then Exit;
    { A LARGE BATCH is one element: the pointer moving from row to row in
      it is no out and no over; the row is the element's handler's (its
      scan), and with none there is no data at all -- no event, no states
      (a large element has none) [Batch 117] }
    if (d.Kind = ctkSeries) and (d.SeriesIndex >= 0) and (el.Shape.Kind = cskLarge) then
    begin
      k := LargeRowAt(idx, AX, AY);
      slot := SlotOfSeries(d.SeriesIndex);
      if (k >= 0) and (slot >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil) then
      begin
        Result := SeriesEventTarget(TyChartDatum(d.SeriesIndex, k,
          FStores[slot].GetRawIndex(k)), idx);
        { a select dispatcher, no highlight one [F2b] }
        Result.HdKind := 16;
        Result.HdSeries := d.SeriesIndex;
        Result.HdRow := k;
      end;
      Exit;
    end;
    case d.Kind of
      ctkSeries:
        if d.SeriesIndex >= 0 then
        begin
          Result := SeriesEventTarget(d, idx);
          { the dispatcher behind it [Batch 88] }
          Result.HdSeries := d.SeriesIndex;
          Result.HdRow := d.DataIndex;
          Result.HdEdge := d.IsEdge;
          { a gauge's arc is a dispatcher of its own [F2b] }
          Result.HdPeer := el.Anim.Role = carGaugeProgress;
          if d.DataIndex >= 0 then Result.HdKind := 1 else Result.HdKind := 2;
          { [spec 242] a lines effect symbol: the row's events and tooltip,
            a click selects (its `selected` is the row's), no emphasis }
          if el.Anim.Role = carLinesEffect then Result.HdKind := 31;
        end;
      ctkMarkPoint, ctkMarkLine, ctkMarkArea:
        { [R2-B] its own function: the keyboard's marker stop takes it too }
        Result := MarkerEventTarget(idx);
      ctkLegend:
        begin
          if (d.ComponentIndex > High(FLegends))
            or (d.DataIndex > High(FLegends[d.ComponentIndex].Items)) then Exit;
          nm := FLegends[d.ComponentIndex].Items[d.DataIndex].Name;
          { THE ITEM GROUP'S OWN HANDLERS, whatever triggerEvent says: a
            series legend when getSeriesByName finds one -- filtered or not --
            a data legend otherwise (LegendView.ts:208-292) [Batch 93] }
          Result.HdKind := 4;
          Result.HdSeries := d.ComponentIndex;
          Result.HdRow := d.DataIndex;
          Result.HdName := nm;
          for k := 0 to FOption.ComponentCount('series') - 1 do
            if SeriesModelName(k) = nm then
            begin
              Result.HdLegendSeries := True;
              Break;
            end;
          node := FOption.ComponentAt('legend', d.ComponentIndex);
          if not TriggersEvent(node) then Exit;
          Result.HasData := True;
          Result.Params.ComponentType := 'legend';
          Result.Params.ComponentIndex := d.ComponentIndex;
          Result.Params.DataIndex := d.DataIndex;
          Result.Params.RawDataIndex := d.DataIndex;
          Result.Params.ValueText := nm;
          { the series the name is, the first that answers to it }
          for k := 0 to High(FBindings) do
            if SeriesModelName(FBindings[k].SeriesIndex) = nm then
            begin
              Result.Params.SeriesIndex := FBindings[k].SeriesIndex;
              Break;
            end;
          Result.Model.Valid := True;
          Result.Model.MainType := 'legend';
          Result.Model.SubType := 'plain';
          if (node is TJSONObject) and (TJSONObject(node).Get('type', '') = 'scroll') then
            Result.Model.SubType := 'scroll';
          Result.Model.Index := d.ComponentIndex;
        end;
      ctkGraphic:
        begin
          { [Batch 122] a graphic element: its handlers by its id (a label's
            are its host's), and the event data findEventDispatcher finds --
            its own, else the nearest ancestor's }
          Result.HdKind := 8;
          Result.HdRow := d.DataIndex;
          if (d.DataIndex >= 0) and (d.DataIndex <= High(FGfxPaintEl)) then
          begin
            gel := FGfxPaintEl[d.DataIndex];
            if gel.Host <> nil then gel := gel.Host;
            Result.HdName := gel.Id;
            while (gel <> nil) and not gel.HasEventData do gel := gel.Parent;
            if gel <> nil then
            begin
              Result.HasData := True;
              Result.Params.ComponentType := 'graphic';
              Result.Params.ComponentIndex := d.ComponentIndex;
              Result.Params.Name := gel.EventName;
              if gel.Info <> nil then Result.Params.Info := gel.Info.AsJSON;
              Result.Model.Valid := True;
              Result.Model.MainType := 'graphic';
              Result.Model.Index := d.ComponentIndex;
              Result.Model.Id := FOption.ComponentId('graphic', d.ComponentIndex);
            end;
          end;
        end;
      ctkMatrix:
        begin
          { [Batch 147] A MATRIX CELL, its rect or its label: the cell's
            eventData when the matrix says triggerEvent -- componentType,
            matrixIndex, targetType, the label's text as name, the cell's
            value, its locator pair as coord }
          if not MatrixCellOf(d, mxc, mxInfo) then Exit;
          if not mxc.TriggerEvent then Exit;
          Result.HasData := True;
          Result.Params.ComponentType := 'matrix';
          Result.Params.ComponentIndex := d.ComponentIndex;
          Result.Params.TargetType := mxInfo.Target;
          if mxInfo.HasName then Result.Params.Name := mxInfo.Name;
          if mxInfo.HasText then Result.Params.ValueText := mxInfo.Value;
          { [spec 244] a number stays a number }
          if mxInfo.HasNum then
          begin
            SetLength(Result.Params.Values, 1);
            Result.Params.Values[0] := mxInfo.Num;
          end;
          SetLength(Result.Params.Coord, 2);
          Result.Params.Coord[0] := mxInfo.Loc[0];
          Result.Params.Coord[1] := mxInfo.Loc[1];
          Result.Model.Valid := True;
          Result.Model.MainType := 'matrix';
          Result.Model.Index := d.ComponentIndex;
          Result.Model.Id := FOption.ComponentId('matrix', d.ComponentIndex);
        end;
      ctkGeo:
        begin
          { [Batch 148] a region group's eventData (resetEventTriggerForRegion)
            -- a path's or its text's -- and the group the dispatcher of its
            hover and its click }
          if (d.ComponentIndex < 0) or (d.ComponentIndex > High(FGeos))
            or (FGeos[d.ComponentIndex] = nil) then Exit;
          geo := FGeos[d.ComponentIndex];
          Result.HdKind := 14;
          Result.HdSeries := d.ComponentIndex;
          { [F6b] the hover's group: the raw index (on an SVG map the
            outermost dispatcher over the element; the region's own else) }
          Result.HdRow := d.RawDataIndex;
          Result.HdGen := geo.Gen;
          Result.HdName := geo.GroupName(d.DataIndex);
          Result.HasData := True;
          Result.Params.ComponentType := 'geo';
          Result.Params.ComponentIndex := d.ComponentIndex;
          Result.Params.Name := Result.HdName;
          Result.Params.Region := geo.GroupRegionJson(d.DataIndex);
          Result.Model.Valid := True;
          Result.Model.MainType := 'geo';
          Result.Model.Index := d.ComponentIndex;
          Result.Model.Id := FOption.ComponentId('geo', d.ComponentIndex);
        end;
      ctkLegendSelector, ctkLegendPager:
        begin
          { [Batch 98] no ECData: an identity and a handler, no event }
          if (d.ComponentIndex < 0) or (d.ComponentIndex > High(FLegends)) then Exit;
          if d.Kind = ctkLegendSelector then Result.HdKind := 5
          else Result.HdKind := 6;
          Result.HdSeries := d.ComponentIndex;
          Result.HdRow := d.DataIndex;
        end;
    end;
    Exit;
  end;
  { [R7-G] THE AXES' PARTS THAT ANSWER THE POINTER, under every element of
    the list (an axis is z 0, a series 2): AxisPartAt [was: a grid's and a
    single axis' texts, only where triggerEvent was written] }
  if AxisPartAt(AX, AY, 0, 0, False, axT) then Result := axT;
end;

{ [R7-G] AN AXIS' PART UNDER THE POINT, AS UPSTREAM'S ARE SILENT OR NOT.
  AxisBuilder (a grid's axes, a single axis, a polar's radius axis, a
  parallel axis) makes its line and ticks silent and its labels and name
  AxisBuilder.isLabelSilent -- `silent`, or neither `triggerEvent` nor
  `tooltip.show` (a single axis' tooltip shows by default, its model the
  tooltip's parent); AngleAxisView's labels the same, its ticks and minor
  ticks NOT silent (two merged paths: the default fill keeps them to half
  their width, no strokeContainThreshold); split lines and areas silent.
  A part that is not silent is a target -- the pointer's cursor, no series
  hovered under it -- and it carries eventData (componentType, the axis'
  index, targetType, the name or the label's value) only where
  triggerEvent is written. (A radar's indicator names are list elements:
  TyBuildRadarGrid.) AOnlyAbove: only a part above (AZ, AZ2) -- the axis
  model's z, then the part's z2 (a label 10, the name 1, an angle axis'
  texts and ticks 0) -- for the list's element found first. }
function TTyCustomAdvanceChart.AxisPartAt(AX, AY: Integer; AZ, AZ2: Integer;
  AOnlyAbove: Boolean; out ATarget: TTyChartEventTarget): Boolean;
var
  g, a, q, k, ai: Integer;
  gb: TTyGridBuild;
  axObj: TTyAxis;
  spec: PTyAxisLayoutSpec;
  meas: ITyTextMeasurer;
  lblS, nameS: TTyStyleSet;
  fw, fh, w: Double;
  node: TJSONData;
  mainT: string;
  z: Integer;
  pol: TTyPolar;
  par: TTyParallel;
  ln: TTyPolarLine;

  function Inside(const AR: TTyRectF): Boolean;
  begin
    Result := (AX >= AR.Left) and (AX <= AR.Right) and (AY >= AR.Top)
      and (AY <= AR.Bottom);
  end;

  function Boxed(AXa, AYa, AW, AH: Double; AAH: TTyTextAnchorH;
    AAV: TTyTextAnchorV): TTyRectF;
  var l, t: Double;
  begin
    case AAH of
      tahLeft: l := AXa;
      tahRight: l := AXa - AW;
    else
      l := AXa - AW / 2;
    end;
    case AAV of
      tavTop: t := AYa;
      tavBottom: t := AYa - AH;
    else
      t := AYa - AH / 2;
    end;
    Result := TyRectF(l, t, l + AW, t + AH);
  end;

  { the part's place in z over the element found first }
  function Above(AZp, AZ2p: Integer): Boolean;
  begin
    Result := (not AOnlyAbove) or (AZp > AZ) or ((AZp = AZ) and (AZ2p > AZ2));
  end;

  { the axis model's z (axisDefault: 0; a parallel axis' 10) }
  function ZOf(ANode: TJSONData; ADefault: Integer = 0): Integer;
  var d: TJSONData;
  begin
    Result := ADefault;
    if not (ANode is TJSONObject) then Exit;
    d := TJSONObject(ANode).Find('z');
    if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat)
      and (Abs(d.AsFloat) < MaxInt) then Result := Trunc(d.AsFloat);
  end;

  { a text box of a measured line }
  function TextBox(const AText: string; const AStyle: TTyStyleSet;
    AXa, AYa: Double; AAH: TTyTextAnchorH; AAV: TTyTextAnchorV): TTyRectF;
  begin
    if meas = nil then meas := NewTextMeasurer(FPaintListPPI);
    fw := 0;
    fh := 0;
    if meas <> nil then
      meas.MeasureLine(AText, AStyle.FontName, ResolveFontSize(AStyle),
        AStyle.FontWeight, fw, fh);
    Result := Boxed(AXa, AYa, fw, fh, AAH, AAV);
  end;

  { the text of an AxisBuilder spec under the point: -1 its name, a
    placement's index, -2 none }
  function SpecTextAt(ASpec: PTyAxisLayoutSpec; AZm: Integer): Integer;
  var i: Integer;
  begin
    Result := -2;
    AxisTextStyles(ASpec, lblS, nameS);
    if ASpec^.NamePlacement.Shown and Above(AZm, 1)
      and Inside(TyRectF(ASpec^.NamePlacement.Rect.X, ASpec^.NamePlacement.Rect.Y,
        ASpec^.NamePlacement.Rect.X + ASpec^.NamePlacement.Rect.W,
        ASpec^.NamePlacement.Rect.Y + ASpec^.NamePlacement.Rect.H)) then Exit(-1);
    if not Above(AZm, 10) then Exit;
    for i := 0 to High(ASpec^.Placements) do
    begin
      if not ASpec^.Placements[i].Shown then Continue;
      { A BLOCK IS HIT WHERE ITS PIECES ARE: measuring the text of a
        rich label would box the tag as well [Batch 104] }
      if Length(ASpec^.Placements[i].Rt) > 0 then
      begin
        if Inside(TyRtDeviceBox(ASpec^.Placements[i].Rt, ASpec^.Placements[i].X,
          ASpec^.Placements[i].Y, ASpec^.RotationRad, ASpec^.RtScale)) then Exit(i);
      end
      else if Inside(TextBox(ASpec^.Placements[i].Text, lblS, ASpec^.Placements[i].X,
        ASpec^.Placements[i].Y, ASpec^.Placements[i].AnchorH,
        ASpec^.Placements[i].AnchorV)) then Exit(i);
    end;
  end;

  { the label's value as its rawLabel: scale.getLabel(tick) }
  function LabelValue(AAxis: TTyAxis; AValue: Double): string;
  begin
    if AAxis.Scale is TTyOrdinalScale then
      Result := TTyOrdinalScale(AAxis.Scale).GetLabel(AValue)
    else if AAxis.Scale is TTyTimeScale then
      Result := TTyTimeScale(AAxis.Scale).GetLabel(AValue)
    else
      Result := TyAxisTickLabel(AAxis, AValue, False, '');
  end;

  { makeAxisEventDataBase, where the axis says triggerEvent }
  procedure Base(AAxis: TTyAxis; const AMain, ADim: string; AIndex: Integer);
  begin
    ATarget.HasData := True;
    ATarget.Model.Valid := True;
    ATarget.Model.MainType := AMain;
    case AAxis.AxisType of
      atCategory: ATarget.Model.SubType := 'category';
      atTime: ATarget.Model.SubType := 'time';
      atLog: ATarget.Model.SubType := 'log';
    else
      ATarget.Model.SubType := 'value';
    end;
    ATarget.Model.Index := AIndex;
    ATarget.Params.ComponentType := AMain;
    ATarget.Params.ComponentIndex := AIndex;
    ATarget.Params.AxisIndex := AIndex;
    ATarget.Params.AxisDimension := ADim;
  end;

  { an AxisBuilder spec's name (AQ -1) or label AQ as the target AId names;
    ABreakKey the key a break label's click expands by (-1: none) }
  procedure SpecTarget(AAxis: TTyAxis; ASpec: PTyAxisLayoutSpec; ANode: TJSONData;
    const AMain, ADim: string; AIndex, AQ: Integer; AId: Int64; ABreakKey: Integer);
  begin
    ATarget.Id := AId;
    if not TriggersEvent(ANode) then Exit;
    Base(AAxis, AMain, ADim, AIndex);
    if AQ < 0 then
    begin
      ATarget.Params.TargetType := 'axisName';
      ATarget.Params.Name := ASpec^.NamePlacement.Text;
      Exit;
    end;
    ATarget.Params.TargetType := 'axisLabel';
    ATarget.Params.TickIndex := AQ;
    { A BREAK'S LABEL expands its break on a click [Batch 132] }
    if (ABreakKey >= 0) and (AQ <= High(ASpec^.LabelBreakKind))
      and (ASpec^.LabelBreakKind[AQ] <> 0) then
    begin
      { eventData.break: the break's start and end [F4a] }
      if ASpec^.LabelBreakKind[AQ] = 1 then ATarget.Params.BreakType := 'start'
      else ATarget.Params.BreakType := 'end';
      if AQ <= High(ASpec^.LabelBreakLo) then
      begin
        ATarget.Params.BreakStart := ASpec^.LabelBreakLo[AQ];
        ATarget.Params.BreakEnd := ASpec^.LabelBreakHi[AQ];
      end;
      ATarget.HdKind := 13;
      ATarget.HdSeries := ABreakKey;
      ATarget.HdRow := ASpec^.LabelBreakIndex[AQ];
    end;
    if AAxis.Scale is TTyOrdinalScale then
    begin
      ATarget.Params.ValueText := TTyOrdinalScale(AAxis.Scale).GetLabel(ASpec^.TickValues[AQ]);
      ATarget.Params.DataIndex := Round(TTyOrdinalScale(AAxis.Scale).TickToOrdinal(ASpec^.TickValues[AQ]));
      ATarget.Params.RawDataIndex := ATarget.Params.DataIndex;
    end
    else
      { eventData.value is the label's rawLabel: scale.getLabel(tick),
        grouped as the label is [F4a] }
      ATarget.Params.ValueText := LabelValue(AAxis, ASpec^.TickValues[AQ]);
  end;

  { a merged path of tick lines (AngleAxisView): its pen, the default fill
    -- so half its own width, not strokeContainThreshold }
  function TicksAt(const ALines: TTyPolarLineArray; const APen: TTyAxisPen): Boolean;
  var i: Integer;
  begin
    Result := False;
    if APen.ColourNone then Exit;
    w := APen.Width;
    if IsNan(w) then w := 1;
    w := w * FPaintListPPI / 96;
    if not (w > 0) then Exit;
    for i := 0 to High(ALines) do
    begin
      ln := ALines[i];
      if not ln.Drawn then Continue;
      if (AX < Min(ln.X1, ln.X2) - w / 2) or (AX > Max(ln.X1, ln.X2) + w / 2)
        or (AY < Min(ln.Y1, ln.Y2) - w / 2) or (AY > Max(ln.Y1, ln.Y2) + w / 2) then
        Continue;
      if TyLinesContainLine(ln.X1, ln.Y1, ln.X2, ln.Y2, w, AX, AY) then Exit(True);
    end;
  end;

begin
  Result := False;
  ATarget := Default(TTyChartEventTarget);
  ATarget.Params := TyChartBlankParams;
  if FOption = nil then Exit;
  meas := nil;

  { ---- a grid's axes ---- }
  if FBuild <> nil then
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    for a := 0 to gb.XAxisCount + gb.YAxisCount - 1 do
    begin
      if a < gb.XAxisCount then axObj := gb.XAxis(a)
      else axObj := gb.YAxis(a - gb.XAxisCount);
      if axObj = nil then Continue;
      { [R5-J] on its own zlevel's canvas }
      if not HitIn(AxisModelZLevel(axObj)) or MaskOver(AxisModelZLevel(axObj)) then Continue;
      mainT := axObj.MainType;
      if mainT = '' then mainT := axObj.Dim + 'Axis';
      node := FOption.ComponentAt(mainT, axObj.ComponentIndex);
      if AxisTextSilent(node, FOption.Root) then Continue;
      spec := gb.SpecFor(axObj);
      if spec = nil then Continue;
      q := SpecTextAt(spec, ZOf(node));
      if q = -2 then Continue;
      if q = -1 then
        SpecTarget(axObj, spec, node, mainT, axObj.Dim, axObj.ComponentIndex, q,
          -(200000 + g * 100 + a), -1)
      else
        SpecTarget(axObj, spec, node, mainT, axObj.Dim, axObj.ComponentIndex, q,
          -(100000 + g * 10000 + a * 1000 + q), g * 1000 + a);
      Exit(True);
    end;
  end;

  { ---- the single axes (their tooltip shows unless written off) ---- }
  for a := 0 to High(FSingles) do
  begin
    if (FSingles[a] = nil) or not FSingles[a].View.Shown then Continue;
    axObj := FSingles[a].Axis;
    if axObj = nil then Continue;
    node := FOption.ComponentAt('singleAxis', a);
    if AxisTextSilent(node, FOption.Root, True) then Continue;
    spec := @FSingles[a].View.Spec;
    q := SpecTextAt(spec, ZOf(node));
    if q = -2 then Continue;
    if q = -1 then
      SpecTarget(axObj, spec, node, 'singleAxis', 'single', a, q,
        -((Int64(12) shl 44) + Int64(a) * 100000 + 99999), -1)
    else
      SpecTarget(axObj, spec, node, 'singleAxis', 'single', a, q,
        -((Int64(12) shl 44) + Int64(a) * 100000 + q), cBreakSingleKey + a);
    Exit(True);
  end;

  { ---- the polars: the radius axis an AxisBuilder, the angle axis its
    own view ---- }
  for k := 0 to High(FPolars) do
  begin
    pol := FPolars[k];
    if pol = nil then Continue;
    { the radius axis }
    axObj := pol.RadiusAxis;
    if (axObj <> nil) and pol.RadiusView.Shown
      and HitIn(AxisModelZLevel(axObj)) and not MaskOver(AxisModelZLevel(axObj)) then
    begin
      node := FOption.ComponentAt('radiusAxis', axObj.ComponentIndex);
      if not AxisTextSilent(node, FOption.Root) then
      begin
        q := SpecTextAt(@pol.RadiusView.Spec, ZOf(node));
        if q <> -2 then
        begin
          if q = -1 then
            SpecTarget(axObj, @pol.RadiusView.Spec, node, 'radiusAxis', 'radius',
              axObj.ComponentIndex, q, -((Int64(47) shl 44) + Int64(k) * 1000000 + 99999), -1)
          else
            SpecTarget(axObj, @pol.RadiusView.Spec, node, 'radiusAxis', 'radius',
              axObj.ComponentIndex, q, -((Int64(47) shl 44) + Int64(k) * 1000000 + q), -1);
          Exit(True);
        end;
      end;
    end;
    { the angle axis: its labels (z2 0), then its ticks and minor ticks }
    axObj := pol.AngleAxis;
    if (axObj = nil) or not pol.AngleView.Shown then Continue;
    if not HitIn(AxisModelZLevel(axObj)) or MaskOver(AxisModelZLevel(axObj)) then Continue;
    node := FOption.ComponentAt('angleAxis', axObj.ComponentIndex);
    z := ZOf(node);
    if not Above(z, 0) then Continue;
    if not AxisTextSilent(node, FOption.Root) then
    begin
      AxisTextStyles(@pol.AngleView.Spec, lblS, nameS);
      for q := 0 to High(pol.AngleView.Labels) do
      begin
        if pol.AngleView.Labels[q].Text = '' then Continue;
        if Length(pol.AngleView.Labels[q].Rt) > 0 then
        begin
          if not Inside(TyRtDeviceBox(pol.AngleView.Labels[q].Rt, pol.AngleView.Labels[q].X,
            pol.AngleView.Labels[q].Y, 0, pol.AngleView.Spec.RtScale)) then Continue;
        end
        else if not Inside(TextBox(pol.AngleView.Labels[q].Text, lblS,
          pol.AngleView.Labels[q].X, pol.AngleView.Labels[q].Y,
          pol.AngleView.Labels[q].AnchorH, pol.AngleView.Labels[q].AnchorV)) then Continue;
        ATarget.Id := -((Int64(47) shl 44) + Int64(k) * 1000000 + 200000 + q);
        if TriggersEvent(node) then
        begin
          Base(axObj, 'angleAxis', 'angle', axObj.ComponentIndex);
          ATarget.Params.TargetType := 'axisLabel';
          ATarget.Params.ValueText := LabelValue(axObj, pol.AngleView.Labels[q].Value);
        end;
        Exit(True);
      end;
    end;
    if TicksAt(pol.AngleView.Ticks, pol.AngleView.Furn.TickPen) then
    begin
      ATarget.Id := -((Int64(47) shl 44) + Int64(k) * 1000000 + 300000);
      Exit(True);
    end;
    if TicksAt(pol.AngleView.MinorTicks, pol.AngleView.Furn.MinorTickPen) then
    begin
      ATarget.Id := -((Int64(47) shl 44) + Int64(k) * 1000000 + 300001);
      Exit(True);
    end;
  end;

  { ---- the parallel axes: AxisBuilders ---- }
  for k := 0 to High(FParallels) do
  begin
    par := FParallels[k];
    if par = nil then Continue;
    for ai := 0 to Min(par.AxisCount, Length(par.Views)) - 1 do
    begin
      if not par.Views[ai].Shown then Continue;
      axObj := par.Axis(ai);
      if axObj = nil then Continue;
      if not HitIn(AxisModelZLevel(axObj)) or MaskOver(AxisModelZLevel(axObj)) then Continue;
      node := FOption.ComponentAt('parallelAxis', axObj.ComponentIndex);
      if AxisTextSilent(node, FOption.Root) then Continue;
      q := SpecTextAt(@par.Views[ai].Spec, ZOf(node, 10));
      if q = -2 then Continue;
      if q = -1 then
        SpecTarget(axObj, @par.Views[ai].Spec, node, 'parallelAxis', 'parallel',
          axObj.ComponentIndex, q, -((Int64(47) shl 44) + (Int64(1) shl 40)
          + Int64(k) * 1000000 + Int64(ai) * 1000 + 999), -1)
      else
        SpecTarget(axObj, @par.Views[ai].Spec, node, 'parallelAxis', 'parallel',
          axObj.ComponentIndex, q, -((Int64(47) shl 44) + (Int64(1) shl 40)
          + Int64(k) * 1000000 + Int64(ai) * 1000 + q), -1);
      Exit(True);
    end;
  end;

  { ---- a radar's indicator names and labels: an AxisBuilder each, on a
    model with no parent -- only triggerEvent wakes them ---- }
  for k := 0 to High(FRadarTexts) do
  begin
    node := FOption.ComponentAt('radar', FRadarTexts[k].Radar);
    if not TriggersEvent(node) then Continue;
    if not HitIn(ModelZLevel('radar', FRadarTexts[k].Radar))
      or MaskOver(ModelZLevel('radar', FRadarTexts[k].Radar)) then Continue;
    if not Above(FRadarTexts[k].Z, FRadarTexts[k].Z2) then Continue;
    if not Inside(FRadarTexts[k].Box) then Continue;
    ATarget.Id := -((Int64(47) shl 44) + (Int64(2) shl 40) + k);
    ATarget.HasData := True;
    ATarget.Model.Valid := True;
    ATarget.Model.MainType := 'radar';
    ATarget.Model.Index := FRadarTexts[k].Radar;
    ATarget.Params.ComponentType := 'radar';
    ATarget.Params.ComponentIndex := FRadarTexts[k].Radar;
    ATarget.Params.AxisIndex := FRadarTexts[k].Radar;
    ATarget.Params.AxisDimension := 'radar';
    if FRadarTexts[k].IsName then
    begin
      ATarget.Params.TargetType := 'axisName';
      ATarget.Params.Name := FRadarTexts[k].Text;
    end
    else
    begin
      ATarget.Params.TargetType := 'axisLabel';
      ATarget.Params.ValueText := FRadarTexts[k].Text;
    end;
    Exit(True);
  end;
end;

procedure TTyCustomAdvanceChart.EmitChartEvent(const AType: string;
  const ATarget: TTyChartEventTarget; AX, AY: Integer; AHasOffset: Boolean);
var
  ev: TTyChartEvent;
  regs: array of TTyChartEventReg;
  model: TTyEventModel;
  i: Integer;
begin
  ev := Default(TTyChartEvent);
  ev.EventType := AType;
  ev.HasParams := ATarget.HasData;
  if ev.HasParams then ev.Params := ATarget.Params
  else ev.Params := TyChartBlankParams;
  ev.HasOffset := AHasOffset;
  if AHasOffset then
  begin
    ev.OffsetX := AX;
    ev.OffsetY := AY;
  end;
  if ATarget.HasData then model := ATarget.Model
  else model := Default(TTyEventModel);
  if Assigned(FOnChartEvent) then FOnChartEvent(Self, ev);
  { a copy: a handler may register or unregister }
  regs := Copy(FEventRegs);
  for i := 0 to High(regs) do
    if (regs[i].EventType = AType) and TyEventQueryMatches(regs[i].Query, model, ev) then
      regs[i].Handler(Self, ev);
end;

{ zrender's mousemove: an out to what was hovered when the target changes,
  a move to the new one, an over when it changed -- each only where the
  target carries data }
procedure TTyCustomAdvanceChart.EventMove(AX, AY: Integer);
begin
  EventMoveOnly(AX, AY);
  EventOver;
end;

procedure TTyCustomAdvanceChart.EventMoveOnly(AX, AY: Integer);
var
  t: TTyChartEventTarget;
  cancel: Boolean;
begin
  FEvLastX := AX;
  FEvLastY := AY;
  { a label dragged [R5-C] }
  LbDragMove(AX, AY);
  { zrender #6198: a hovered element an update removed (a visualMap view
    rebuilt) is looked for again where it was hovered [Batch 116] }
  if (FEvHover.Id <> 0) and (FEvHover.HdKind = 7)
    and ((FEvHover.HdSeries > High(FVmLive))
      or (FEvHover.HdGen <> FVmLive[FEvHover.HdSeries].Gen)) then
    FEvHover := EventTargetAt(FEvHoverX, FEvHoverY);
  { a toolbox icon a render replaced: the same [Batch 125] }
  if (FEvHover.Id <> 0) and (FEvHover.HdKind = 8) and (FEvHover.HdGen <> FTbGen) then
    FEvHover := EventTargetAt(FEvHoverX, FEvHoverY);
  { and a timeline element [Batch 129] }
  if (FEvHover.Id <> 0) and (FEvHover.HdKind = 10)
    and (TlTargetView(FEvHover) = nil) then
    FEvHover := EventTargetAt(FEvHoverX, FEvHoverY);
  { and a geo region a render replaced [Batch 148] }
  if (FEvHover.Id <> 0) and (FEvHover.HdKind = 14) and (GeoOfTarget(FEvHover) = nil) then
    FEvHover := EventTargetAt(FEvHoverX, FEvHoverY);
  { and a breadcrumb item a solve replaced [F2a] }
  if (FEvHover.Id <> 0) and (FEvHover.HdKind = 15) and (FEvHover.HdGen <> FTmCrumbGen) then
    FEvHover := EventTargetAt(FEvHoverX, FEvHoverY);
  { [R5-D] and the loading mask, gone }
  if FEvHoverMask and not LoadMasks then
    FEvHover := EventTargetAt(FEvHoverX, FEvHoverY);
  FEvHoverMask := False;
  if FEvPreset then t := FEvPresetT
  else t := EventTargetAt(AX, AY);
  FEvPreset := False;
  { zrender's isOutsideBoundary: a point off the canvas hovers nothing
    [F2a: the treemap's own hover said so; every hover is the state
    machine's now] }
  if (AX < FLastRect.Left) or (AY < FLastRect.Top) or (AX > FLastRect.Right)
    or (AY > FLastRect.Bottom) then
  begin
    t := Default(TTyChartEventTarget);
    t.Params := TyChartBlankParams;
  end;
  if (FEvHover.Id <> 0) and (t.Id <> FEvHover.Id) then
  begin
    { the element's own mouseout, bubbled [Batch 116] }
    VmElementEvent('mouseout', FEvHover, AX, AY);
    { a graphic element's handlers; a true answer stops the rest [Batch 122] }
    cancel := GfxElementEvent('mouseout', FEvHover, AX, AY);
    TbMouseOut(FEvHover);
    TlMouseOut(FEvHover);
    { echarts' own mouseout first: the dispatcher leaves emphasis [Batch 88] }
    if not cancel then StHoverOut(FEvHover);
    if FEvHover.HasData and not cancel then EmitChartEvent('mouseout', FEvHover, AX, AY);
    { the visualMaps' zr.on('mouseout') }
    VmZrMouseOut;
  end;
  { the element's mousemove, then zrender's Draggable [Batch 116] }
  VmElementEvent('mousemove', t, AX, AY);
  cancel := GfxElementEvent('mousemove', t, AX, AY);
  VmDragMove(AX, AY);
  { [spec 242] a graphic element dragged: the Handler-level listener the
    element's handlers can stop, after them [Batch 122: before everything] }
  if not cancel then GfxDragMove(AX, AY);
  { [Batch 150] zrender's zr-level mousemove: a geo's RoamController pans
    here -- after the out, before echarts' own mousemove (registered
    zrEventfulCallAtLast) and before the over, both of which name what was
    found under the pointer before the picture moved }
  if not cancel then GeoRoamMove(AX, AY);
  if t.HasData and not cancel then EmitChartEvent('mousemove', t, AX, AY);
  { [R2-E] THE OVER WAITS for the zr-level mousemove listeners -- the
    pointer's global one (updateAxisPointer, the tooltip's), the brush's,
    the parallel's: Handler.mousemove dispatches the move (its zr-level
    trigger with it) before the over. A legend item's highlight, a
    chart's mouseover come after the pointer's actions (EventOver). }
  FEvOverDue := (t.Id <> 0) and (t.Id <> FEvHover.Id);
  FEvOverT := t;
  FEvOverX := AX;
  FEvOverY := AY;
  FEvHover := t;
  FEvHoverX := AX;
  FEvHoverY := AY;
  { [R5-D] over the canvas while the mask shows, the mask is what is
    hovered }
  FEvHoverMask := LoadMasks and (t.Id = 0) and (AX >= FLastRect.Left)
    and (AY >= FLastRect.Top) and (AX <= FLastRect.Right) and (AY <= FLastRect.Bottom);
end;

procedure TTyCustomAdvanceChart.EventOver;
var
  t: TTyChartEventTarget;
  cancel: Boolean;
begin
  if FEvOverDue then
  begin
    FEvOverDue := False;
    t := FEvOverT;
    VmElementEvent('mouseover', t, FEvOverX, FEvOverY);
    TbMouseOver(t);
    TlMouseOver(t);
    cancel := GfxElementEvent('mouseover', t, FEvOverX, FEvOverY);
    if not cancel then StHoverOver(t);
    if t.HasData and not cancel then EmitChartEvent('mouseover', t, FEvOverX, FEvOverY);
    VmZrMouseOver(t);
  end;
  { zrender's Draggable on the timeline's checkpoint, after the hover was
    found [Batch 129] }
  TlDragMove(FEvOverX, FEvOverY);
  { the frame's states [Batch 116] }
  VmApplyStates;
  TlApplyStates;
end;

procedure TTyCustomAdvanceChart.EventDown(AButton: TMouseButton; AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  FEvLastX := AX;
  FEvLastY := AY;
  t := EventTargetAt(AX, AY);
  { ANY BUTTON: zrender records the press whichever it was }
  FEvDownId := t.Id;
  FEvUpId := t.Id;
  FEvDownArmed := True;
  FEvDownX := AX;
  FEvDownY := AY;
  if AButton = mbLeft then LbDragStart(t, AX, AY);
  { the timeline's checkpoint is draggable [Batch 129] }
  if AButton = mbLeft then TlDragStart(t);
  { [spec 242] the element's handlers first: one that stops the climb stops
    the Handler-level listeners too -- no drag starts }
  if GfxElementEvent('mousedown', t, AX, AY) then
  begin
    FGfxDragOn := False;
    Exit;
  end;
  GfxDragStart(t, AX, AY);
  if t.HasData then EmitChartEvent('mousedown', t, AX, AY);
end;

{ zrender's mouseup, then -- for the left button, as a browser follows it --
  the click: the same target pressed and released, a press point to judge
  it against, within 4 px of it. A click that passes clears the point; one
  that fails does not. }
procedure TTyCustomAdvanceChart.EventUp(AButton: TMouseButton; AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  t := EventTargetAt(AX, AY);
  FEvUpId := t.Id;
  { zrender's Draggable ends before echarts' own handlers [Batch 116] }
  if AButton = mbLeft then VmDragEnd;
  { the timeline's checkpoint: its dragend changes the index [Batch 129] }
  if AButton = mbLeft then TlDragEnd(AX, AY);
  FLbDragOn := False;
  { [spec 242] the element's mouseup, then Draggable._dragEnd (dragend,
    drop), then echarts' -- a handler that stops the climb leaves the drag
    going, as upstream's Draggable never hears the release }
  if not GfxElementEvent('mouseup', t, AX, AY) then
  begin
    GfxDragEnd(AX, AY);
    if t.HasData then EmitChartEvent('mouseup', t, AX, AY);
  end;
  if AButton <> mbLeft then
  begin
    VmApplyStates;
    Exit;
  end;
  if (FEvDownId <> FEvUpId) or not FEvDownArmed
    or (Sqrt(Sqr(AX - FEvDownX) + Sqr(AY - FEvDownY)) > 4) then
  begin
    VmApplyStates;
    Exit;
  end;
  FEvDownArmed := False;
  { a piece's item group: its onclick [Batch 116] }
  if (t.HdKind = 7) and (t.HdRow >= 100) and (t.HdRow < 1000) then
    VmPieceClick(t.HdSeries, (t.HdRow - 100) div 2);
  { THE ELEMENT'S OWN HANDLER BEFORE ANY zr-LEVEL ONE: a legend item's click
    is downplay, legendToggleSelect, highlight [Batch 93] }
  if t.HdKind = 8 then TbClick(t.HdSeries, t.HdRow)
  { [Batch 129] a timeline element's onclick }
  else if t.HdKind = 10 then TlClick(t.HdSeries, t.HdRow)
  { a break area's group, a break label's text: expandAxisBreak [Batch 132] }
  else if t.HdKind = 12 then BreakAreaClickAt(t.HdSeries, t.HdRow)
  else if t.HdKind = 13 then BreakExpandClick(t.HdSeries, t.HdRow)
  { [Batch 148] the geo's map group: GeoView._handleRegionClick }
  else if t.HdKind = 14 then GeoRegionClick(t)
  { [F2a] a breadcrumb item's onclick: the zoom or the drill, before the
    chart's own click }
  else if t.HdKind = 15 then TreemapCrumbSelect(t.HdSeries, t.HdRow)
  { [R2-B] a treemap's container group's onclick (TreemapView._initEvents:
    the zoom or the drill at the point), before the chart's own click and
    select -- which name the element pressed, the render between them
    notwithstanding [was: in MouseUp, before EventUp, whose target the
    zoom's new render had already replaced: no select, no click] }
  else if (t.HdKind = 1) and not t.HdEdge and IsTreemapSeries(t.HdSeries)
    and (AX >= FLastRect.Left) and (AX <= FLastRect.Right) and (AY >= FLastRect.Top)
    and (AY <= FLastRect.Bottom) then
    TreemapClick(t.HdSeries, AX, AY)
  else if t.HdKind = 4 then LegendClick(t)
  { [Batch 98] the selector's and the pager's own onclick }
  else if t.HdKind = 5 then LegendSelectorClick(t)
  else if t.HdKind = 6 then LegendPagerClick(t);
  { A GRAPHIC ELEMENT'S onclick, up its groups; a true answer stops
    everything at the zrender root [Batch 122] }
  if GfxElementEvent('click', t, AX, AY) then
  begin
    VmApplyStates;
    Exit;
  end;
  { ECHARTS' OWN CLICK HANDLER FIRST: an item click dispatches select or
    unselect, whatever selectedMode says [Batch 88] }
  StClickSelect(t);
  { [R5-D] THE CHART'S click WAITS for the zr-level click listeners -- the
    pointer's global one among them: echarts' mouse event handlers are
    zrEventfulCallAtLast (MouseUp emits it) [was: here, before them] }
  if FEvClickDefer then
  begin
    FEvClickDue := t.HasData;
    FEvClickT := t;
    FEvClickX := AX;
    FEvClickY := AY;
  end
  else if t.HasData then EmitChartEvent('click', t, AX, AY);
  VmApplyStates;
  TlApplyStates;
end;

procedure TTyCustomAdvanceChart.EventDblClick(AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  t := EventTargetAt(AX, AY);
  if GfxElementEvent('dblclick', t, AX, AY) then Exit;
  if t.HasData then EmitChartEvent('dblclick', t, AX, AY);
end;

procedure TTyCustomAdvanceChart.EventContextMenu(AX, AY: Integer);
var t: TTyChartEventTarget;
begin
  t := EventTargetAt(AX, AY);
  if GfxElementEvent('contextmenu', t, AX, AY) then Exit;
  if t.HasData then EmitChartEvent('contextmenu', t, AX, AY);
end;

{ THE POINTER LEFT THE CANVAS: an out to what it was over, at the last point
  it was seen, then globalout with nothing -- and what was hovered is
  remembered, so coming back onto it is no over }
procedure TTyCustomAdvanceChart.EventLeave(AX, AY: Integer);
var
  none: TTyChartEventTarget;
  cancel: Boolean;
begin
  cancel := False;
  if FEvHover.Id <> 0 then
  begin
    VmElementEvent('mouseout', FEvHover, AX, AY);
    cancel := GfxElementEvent('mouseout', FEvHover, AX, AY);
    TbMouseOut(FEvHover);
    TlMouseOut(FEvHover);
    if not cancel then StHoverOut(FEvHover);
  end;
  if (FEvHover.Id <> 0) and FEvHover.HasData and not cancel then
    EmitChartEvent('mouseout', FEvHover, AX, AY);
  { zr-level: fired with or without a target [Batch 116] }
  VmZrMouseOut;
  VmApplyStates;
  TlApplyStates;
  none := Default(TTyChartEventTarget);
  none.Params := TyChartBlankParams;
  EmitChartEvent('globalout', none, 0, 0, False);
end;

procedure TTyCustomAdvanceChart.DblClick;
begin
  inherited DblClick;
  if not (csDesigning in ComponentState) then EventDblClick(FEvLastX, FEvLastY);
end;

procedure TTyCustomAdvanceChart.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
begin
  if not (csDesigning in ComponentState) then
    EventContextMenu(MousePos.X, MousePos.Y);
  inherited DoContextPopup(MousePos, Handled);
end;

procedure TTyCustomAdvanceChart.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  d, preD: TTyChartDatumRef;
  spec: TTyTooltipSpec;
  el, preEl: Integer;
  wasOn, tipWas, pre, roamed: Boolean;
  dx, dy, pdx, pdy: Double;
begin
  { the frame between two pointer events [Batch 125] }
  TbFrame;
  inherited MouseMove(Shift, X, Y);
  if csDesigning in ComponentState then Exit;
  { THE HOVER BEFORE THE PAN [Milestone D9-D14]: zrender's Handler finds
    the element under the pointer first; the RoamController (and the
    thumbnail's) listens on the zr-level mousemove and moves the picture
    after, so this move's events and tooltip name what was under the
    pointer before it moved -- a region the graph slides over, a node it
    slides away from }
  pre := ((FThumbDrag >= 0) and (FThumbDrag <= High(FThumbs))) or (FRoamSeries >= 0);
  roamed := False;
  if pre then
  begin
    preD := HitTestAt(X, Y, preEl);
    FEvPresetT := EventTargetAt(X, Y);
  end;
  { THE DRAG FIRST: the delta from where the pointer was last, wherever it is
    now -- a drag that leaves the control keeps panning. }
  if (FThumbDrag >= 0) and (FThumbDrag <= High(FThumbs)) then
  begin
    { THE THUMBNAIL'S PAN consumes the move: the graph's controller, armed
      beside it, hears nothing [Batch 140] }
    if not PanTaken then
    begin
      dx := X - FThumbDragX;
      dy := Y - FThumbDragY;
      if FThumbs[FThumbDrag].View.Valid and FThumbs[FThumbDrag].Enabled then
      begin
        TyThumbPanPayload(FThumbs[FThumbDrag].View, FThumbDragX, FThumbDragY,
          dx, dy, pdx, pdy);
        FThumbDragX := X;
        FThumbDragY := Y;
        { [R5-J] the thumbnail's dispatch publishes graphroam }
        FRoamEvSrc := 2;
        try
          roamed := GraphRoam(FThumbs[FThumbDrag].Target, pdx, pdy);
        finally
          FRoamEvSrc := 0;
        end;
      end
      else
      begin
        FThumbDragX := X;
        FThumbDragY := Y;
      end;
    end;
  end
  else if FRoamSeries >= 0 then
  begin
    dx := X - FRoamX;
    dy := Y - FRoamY;
    FRoamX := X;
    FRoamY := Y;
    { [R5-J] the series' RoamController dispatches its roam: the event too }
    FRoamEvSrc := 1;
    try
      if IsTreeSeries(FRoamSeries) then TreeRoam(FRoamSeries, dx, dy)
      else if IsSankeySeries(FRoamSeries) then SankeyRoam(FRoamSeries, dx, dy)
      { a treemap's pan: past 3 px, else the delta is lost [Batch 115] }
      else if IsTreemapSeries(FRoamSeries) then TreemapPan(FRoamSeries, Round(dx), Round(dy))
      else roamed := GraphRoam(FRoamSeries, dx, dy);
    finally
      FRoamEvSrc := 0;
    end;
  end;
  { A NODE DRAG: one 'drag' per move, the delta from the last move [Batch 114] }
  if FGraphDragSlot >= 0 then GraphDragMove(X, Y);
  if FSankeyDragSlot >= 0 then SankeyDragMove(X, Y);
  DataZoomPointer(dpMove, X, Y, Shift, 0);
  { the toolbox's brush [Batch 125] }
  TbCtlMove(X, Y);
  { NOTHING ABOUT THE TOOLTIP IS CHECKED HERE, and that is the point. What is
    under the pointer is a fact about geometry; whether a BOX is drawn for it
    is a question for the tooltip's own listener (below). A chart with
    a tooltip with show false still highlights the mark under the cursor --
    upstream highlights from zrender's own hover and the tooltip is a
    separate listener -- and gating the hover on the tooltip made switching
    the box off switch the highlight off too. }

  wasOn := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0);
  if pre then
  begin
    d := preD;
    el := preEl;
    { A GRAPH'S ROAM RENDERS ITS VIEW AGAIN: its symbols and edges are new
      elements, none of them in the emphasis the hovered one had }
    if roamed and IsGraphDatum(d) then
    begin
      d := TyChartNoDatum;
      el := -1;
    end;
  end
  else
    d := HitTestAt(X, Y, el);
  { [F2a] a graph's, a tree's and a treemap's hover are the state machine's
    flags (StHoverOver / StHoverOut, from EventMove): the frame applies
    them }
  FTipDatum := d;
  FTipElement := el;
  FTipX := X;
  FTipY := Y;
  tipWas := FTipShown;
  { the chart's own mouse events [Batch 84] -- zrender hears the chart's
    listeners before the pointer's global one }
  FEvPreset := pre;
  EventMoveOnly(X, Y);
  { THE AXIS POINTER AND THE BOX THROUGH THEIR ACTIONS [Batch 153]: the
    global listener turns the move into updateAxisPointer (the pointer's
    hits, an independent piece of state held in FTipHits -- live whenever
    the point is in a coordinate system and something asks for an axis
    pointer, a mark under it or not -- that DropBuild clears because it
    holds axis POINTERS into the build) and the item tooltip's _tryShow,
    then the last showTip or hideTip. The box's own state machine
    [Batch 100] takes them as requests: a show now or after showDelay, a
    hide after hideDelay. }
  { [R5-D] zrender's Draggable on a pointer's handle: its drift -- the
    handle along the axis and a throttled dispatch -- before the global
    listener hears the move }
  if FHdDrag >= 0 then
  begin
    HdDragMove(FHdDrag, X - FHdDragX, Y - FHdDragY);
    FHdDragX := X;
    FHdDragY := Y;
  end;
  PtrListener('mousemove', X, Y, FTipDatum, FTipElement);
  { zrender's Draggable on a brush cover -- the hover above was found before
    it moved -- then the brush controllers' own mousemove [Batch 126] }
  BrushPointerMove(X, Y);
  { ParallelView's mousemove, after the axes' controllers [Batch 140] }
  ParExpMove(X, Y);
  { [R2-E] then zrender's mouseover }
  EventOver;
  { an icon's pointer, the brush's crosshair [Batch 125] }
  TbApplyCursor(X, Y);
  { [F6a] the chart's cursor, all of it }
  CursorAfterMove(X, Y);
  { REPAINT ON MOVEMENT, not only when the datum changes. The box is anchored
    to the CURSOR -- upstream positions against the raw pointer offsets and
    never against the snapped datum -- so a repaint gated on the datum would
    leave it standing still while the pointer walked away from it. The frame
    this asks for is a blit of the static layer plus one box; the gate the old
    TTyChart needed was compensating for a control that re-rendered everything
    from scratch each paint, and that is what the cache removed. }
  if wasOn or TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0)
    or tipWas or FTipShown then
    HoverInvalidate;
end;

procedure TTyCustomAdvanceChart.MouseLeave;
var wasOn: Boolean;
begin
  TbFrame;
  if not (csDesigning in ComponentState) then EventLeave(FEvLastX, FEvLastY);
  wasOn := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0) or FTipShown;
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  { globalout through the pointer's listener [Batch 153]: the axis
    pointer's updateAxisPointer with currTrigger 'leave' hides the pointers
    (unless its triggerOn is 'none'), the tooltip's _hide the box -- after
    hideDelay, or never under alwaysShowContent }
  if not (csDesigning in ComponentState) then
  begin
    if Length(OptionPointerHits) > 0 then wasOn := True;
    PtrListener('leave', 0, 0, TyChartNoDatum, -1);
  end;
  { the pointer left the canvas: a mouseout to what it was over }
  if FDzHover.Kind <> dtkNone then
  begin
    DzMouseOut(FDzHover);
    FDzHover := Default(TTyDzTarget);
    DzViewUpdate;
  end;
  { [F6a] the host's own cursor back: the canvas' style keeps the last
    name upstream, but a cursor matters only over the control }
  if not (csDesigning in ComponentState) then ApplyCursorName('default');
  { INHERITED LAST. The base class ends in PointerStateChanged, which this
    control answers with a repaint -- and a repaint before the hover was
    cleared would draw the tooltip one more time on the way out. }
  inherited MouseLeave;
  if wasOn then HoverInvalidate;
end;

{ ==================== the chart's cursor [F6a] ==================== }

{ THE ELEMENT'S OWN cursor (Displayable.cursor, 'pointer' unless something
  set another): what zrender's Handler.mousemove hands setCursor for the
  hovered target; 'default' for no target }
function TTyCustomAdvanceChart.TargetCursor(const ATarget: TTyChartEventTarget): string;
var idx: Integer;
begin
  Result := 'default';
  if ATarget.Id = 0 then Exit;
  Result := 'pointer';
  { [R5-D] a pointer's handle }
  if ATarget.HdKind = 17 then Exit('move');
  case ATarget.HdKind of
    { a brush cover's piece: its own (move, the eight resizes) }
    9:
      if (ATarget.HdGen >= 0) and (ATarget.HdGen <= Ord(High(TTyBrushPiece))) then
      begin
        if BrushCtlOf(ATarget.HdSeries) <> nil then
          Result := BrushCtlOf(ATarget.HdSeries).PieceCursor(TTyBrushPiece(ATarget.HdGen), True)
        else
          Result := TyBrushPieceCursor(TTyBrushPiece(ATarget.HdGen), True);
        if Result = '' then Result := 'default';
        Exit;
      end;
    7:
      begin
        Result := VmCursor(ATarget.HdSeries, ATarget.HdRow);
        Exit;
      end;
  end;
  { an element of the display list: its own }
  if (ATarget.Id > 0) and (FPaintList <> nil) then
  begin
    idx := ATarget.Id - 1;
    if (idx < FPaintList.Count) and (FPaintList.Element(idx).Cursor <> '') then
      Result := FPaintList.Element(idx).Cursor;
  end;
end;

{ a graph's, a tree's, a sankey's, a treemap's, a geo's or a map's
  RoamController would grab here (its _checkPointer) }
function TTyCustomAdvanceChart.RoamGrabAt(AX, AY: Integer): Boolean;
var g: Integer;
begin
  Result := RoamTargetAt(AX, AY, False, g) >= 0;
  if not Result then Result := g >= 0;
end;

{ [R2-E] THE RELEASE IS THE LAST CONTROLLER'S. RoamController's zr
  listeners run as addRoamZrListener sorted them: zlevel, then z,
  descending -- and on a tie the comparison is NaN (z2 is -Infinity on both
  sides), so the one enabled later goes after. Every pan controller's
  mouseup sets the cursor (grab where nothing is hovered inside its area,
  else the target's or default), so the last one's stands: the lowest, and
  among equals the one enabled last. Enabled in this order: an inside
  dataZoom's (coordsys:aftercreate, its grid's z), then the components'
  (a geo's), then the series' (a graph's, a tree's, a sankey's, a
  treemap's, a map's), each in its index order. }
function TTyCustomAdvanceChart.RoamReleaseArea(AX, AY: Integer): Integer;
var
  found, bestIn: Boolean;
  bestZL, bestZ, bestSeq: Integer;
  i, g, zl, z: Integer;
  sp: TTyGraphSpec;
  gg: TTyGeo;
  node, d: TJSONData;
  s, x, y: Double;
  inArea: Boolean;

  procedure Consider(AZL, AZ, ASeq: Integer; AIn: Boolean);
  begin
    if (not found) or (AZL < bestZL) or ((AZL = bestZL) and (AZ < bestZ))
      or ((AZL = bestZL) and (AZ = bestZ) and (ASeq > bestSeq)) then
    begin
      found := True;
      bestZL := AZL;
      bestZ := AZ;
      bestSeq := ASeq;
      bestIn := AIn;
    end;
  end;

  function NumOr(AObj: TJSONData; const AKey: string; ADefault: Integer): Integer;
  var v: TJSONData;
  begin
    Result := ADefault;
    if not (AObj is TJSONObject) then Exit;
    v := TJSONObject(AObj).Find(AKey);
    if (v <> nil) and (v.JSONType = jtNumber) then Result := Round(v.AsFloat);
  end;

begin
  found := False;
  bestIn := False;
  bestZL := 0;
  bestZ := 0;
  bestSeq := -1;
  { the inside dataZooms' controllers: one per grid, its z and zlevel }
  if (FBuild <> nil) and (Length(FDzState) > 0) then
  begin
    s := DzScale;
    x := (AX - FLastRect.Left) / s;
    y := (AY - FLastRect.Top) / s;
    { [R5-D] and the polars' and single axes' }
    for g := 0 to DzRecCount - 1 do
      if DzControlType(g) >= 1 then
      begin
        node := DzRecNode(g);
        Consider(NumOr(node, 'zlevel', 0), NumOr(node, 'z', 0), g, DzRecContains(g, x, y));
      end;
  end;
  { the geos' }
  for i := 0 to High(FGeos) do
  begin
    gg := FGeos[i];
    if (gg = nil) or not gg.Valid or not gg.Spec.Show then Continue;
    if not (gg.Spec.Roam in [grmPan, grmBoth]) then Continue;
    inArea := gg.RoamPointerIn(AX, AY) and not GeoIrrelevant(i, AX, AY);
    Consider(gg.Spec.ZLevel, gg.Spec.Z, 1000 + i, inArea);
  end;
  { the series': by their index }
  for i := 0 to High(FGraphs) do
  begin
    if (FGraphs[i] = nil) or (i > High(FGraphLaidOut)) or not FGraphLaidOut[i] then Continue;
    sp := FGraphSpecs[i];
    if not (sp.Roam in [grmPan, grmBoth]) then Continue;
    Consider(sp.ZLevel, sp.Z, 100000 + FBindings[i].SeriesIndex,
      (sp.RoamGlobal or FGraphs[i].ContainTrigger(AX, AY))
      and not SeriesRoamIrrelevant(i, AX, AY, sp.Z, sp.ZLevel));
  end;
  for i := 0 to High(FTreeViews) do
  begin
    if FTreeViews[i] = nil then Continue;
    sp := FTreeSpecs[i];
    if not (sp.Roam in [grmPan, grmBoth]) then Continue;
    Consider(sp.ZLevel, sp.Z, 100000 + FBindings[i].SeriesIndex,
      (sp.RoamGlobal or FTreeViews[i].ContainTrigger(AX, AY))
      and not SeriesRoamIrrelevant(i, AX, AY, sp.Z, sp.ZLevel));
  end;
  for i := 0 to High(FSankeyViews) do
  begin
    if FSankeyViews[i] = nil then Continue;
    sp := FSankeySpecs[i];
    if not (sp.Roam in [grmPan, grmBoth]) then Continue;
    Consider(sp.ZLevel, sp.Z, 100000 + FBindings[i].SeriesIndex,
      (sp.RoamGlobal or SankeySelfAt(i, AX, AY))
      and not SeriesRoamIrrelevant(i, AX, AY, sp.Z, sp.ZLevel));
  end;
  for i := 0 to High(FTreemaps) do
  begin
    if not FTreemaps[i].Valid or not TreemapRoamOk(i, False) then Continue;
    z := NumOr(FTreemaps[i].Series, 'z', 2);
    zl := NumOr(FTreemaps[i].Series, 'zlevel', 0);
    d := FTreemaps[i].Series.Find('roamTrigger');
    inArea := (d = nil) or (d.JSONType <> jtString) or (d.AsString <> 'selfRect');
    if not inArea then
      inArea := (AX - FTreemaps[i].Box.X >= FTreemaps[i].Nodes[0].X)
        and (AX - FTreemaps[i].Box.X <= FTreemaps[i].Nodes[0].X + FTreemaps[i].Nodes[0].W)
        and (AY - FTreemaps[i].Box.Y >= FTreemaps[i].Nodes[0].Y)
        and (AY - FTreemaps[i].Box.Y <= FTreemaps[i].Nodes[0].Y + FTreemaps[i].Nodes[0].H);
    Consider(zl, z, 100000 + FBindings[i].SeriesIndex, inArea);
  end;
  for i := 0 to High(FMapGeos) do
  begin
    if (i > High(FMapGroups)) or (FMapGroups[i].Main < 0) then Continue;
    gg := FMapGeos[i];
    if (gg = nil) or not gg.Valid or not gg.Spec.Show then Continue;
    if not (gg.Spec.Roam in [grmPan, grmBoth]) then Continue;
    Consider(gg.Spec.ZLevel, gg.Spec.Z, 100000 + FBindings[FMapGroups[i].Main].SeriesIndex,
      gg.RoamPointerIn(AX, AY));
  end;
  if not found then Result := -1
  else if bestIn then Result := 1
  else Result := 0;
end;

{ some RoamController listens to the release: one that pans }
function TTyCustomAdvanceChart.AnyPanRoam: Boolean;
var
  i: Integer;
  gg: TTyGeo;
begin
  Result := True;
  for i := 0 to High(FGraphs) do
    if (FGraphs[i] <> nil) and (i <= High(FGraphSpecs))
      and (FGraphSpecs[i].Roam in [grmPan, grmBoth]) then Exit;
  for i := 0 to High(FTreeViews) do
    if (FTreeViews[i] <> nil) and (i <= High(FTreeSpecs))
      and (FTreeSpecs[i].Roam in [grmPan, grmBoth]) then Exit;
  for i := 0 to High(FSankeyViews) do
    if (FSankeyViews[i] <> nil) and (i <= High(FSankeySpecs))
      and (FSankeySpecs[i].Roam in [grmPan, grmBoth]) then Exit;
  for i := 0 to High(FTreemaps) do
    if FTreemaps[i].Valid and TreemapRoamOk(i, False) then Exit;
  for i := 0 to High(FGeos) + Length(FMapGeos) do
  begin
    if i <= High(FGeos) then gg := FGeos[i]
    else gg := FMapGeos[i - Length(FGeos)];
    if (gg <> nil) and gg.Valid and gg.Spec.Show and (gg.Spec.Roam in [grmPan, grmBoth]) then Exit;
  end;
  if (FBuild <> nil) and (Length(FDzState) > 0) then
    for i := 0 to DzRecCount - 1 do
      if DzControlType(i) >= 1 then Exit;
  Result := False;
end;

{ AFTER zrender's mousemove and its listeners: the hovered element's
  cursor (a dataZoom slider's part above the rest), then the
  RoamControllers' -- 'grabbing' while one pans, else 'grab' over the area
  of one where nothing is hovered (the lowest precedence:
  _decideCursorStyle) -- none of it while the brush holds globalPan; then
  the brush's own (its crosshair, TbApplyCursor) }
procedure TTyCustomAdvanceChart.CursorAfterMove(AX, AY: Integer);
var
  c: string;
  none: Boolean;
begin
  if csDesigning in ComponentState then Exit;
  none := FEvHover.Id = 0;
  if (FDzHover.Kind = dtkSlider) or (FDzDrag.Kind = dtkSlider) then
  begin
    c := FDzCursor;
    none := False;
  end
  else
    c := TargetCursor(FEvHover);
  if not PanTaken then
  begin
    if (FRoamSeries >= 0) or (FRoamGeo >= 0) or (FDzPanGrid >= 0)
      or ((FThumbDrag >= 0) and (FThumbDrag <= High(FThumbs))) then
      c := 'grabbing'
    else if none and (RoamGrabAt(AX, AY) or DzGrabAt(AX, AY)) then
      c := 'grab';
  end;
  if FTbCursor <> '' then c := FTbCursor;
  { [R5-D] the loading mask's own cursor, unless a pan holds the pointer --
    [R5-J] or something of a higher zlevel is hovered over it }
  if LoadMasks and (FEvHover.Id = 0) and (c <> 'grabbing') then c := 'pointer';
  ApplyCursorName(c);
end;

{ RoamController._mouseupHandler, with a pan controller in the chart: 'grab'
  where nothing is hovered inside a roam area, else the released-on
  element's own cursor -- the pan's 'grabbing' given back.
  [R2-E] The last controller's word (RoamReleaseArea), and whatever holds
  globalPan: the mouseup handler does not ask. }
procedure TTyCustomAdvanceChart.CursorAfterUp(AX, AY: Integer);
var
  t: TTyChartEventTarget;
  d: TTyDzTarget;
  s: Double;
  c: string;
begin
  if csDesigning in ComponentState then Exit;
  if not AnyPanRoam then Exit;
  t := Default(TTyChartEventTarget);
  if (AX >= FLastRect.Left) and (AY >= FLastRect.Top) and (AX <= FLastRect.Right)
    and (AY <= FLastRect.Bottom) then
    t := EventTargetAt(AX, AY);
  d := Default(TTyDzTarget);
  if (FBuild <> nil) and (Length(FDzState) > 0) then
  begin
    s := DzScale;
    d := DzFindTarget((AX - FLastRect.Left) / s, (AY - FLastRect.Top) / s);
  end;
  if d.Kind = dtkSlider then
  begin
    case d.Role of
      dzrHandle0, dzrHandle1:
        if FDzLayouts[d.Slider].Horizontal then c := 'ew-resize' else c := 'ns-resize';
      dzrMoveZone, dzrFiller: c := 'grab';
      dzrClickPanel:
        if FDzViews[d.Slider].BrushSelect then c := 'crosshair' else c := 'pointer';
    else
      c := 'pointer';
    end;
  end
  else if (t.Id = 0) and (RoamReleaseArea(AX, AY) = 1) then
    c := 'grab'
  else
    c := TargetCursor(t);
  { [R5-D] released on the loading mask: its own cursor }
  if LoadMasks and (t.Id = 0) and (AX >= FLastRect.Left) and (AY >= FLastRect.Top)
    and (AX <= FLastRect.Right) and (AY <= FLastRect.Bottom) then c := 'pointer';
  ApplyCursorName(c);
end;

{ THE NAME ONTO THE CONTROL: a CSS cursor with an LCL counterpart replaces
  the control's Cursor, the host's own kept; 'default' (or a name with no
  counterpart) gives it back. A Cursor the host set while the chart showed
  its own is the host's new one. }
procedure TTyCustomAdvanceChart.ApplyCursorName(const AName: string);
var c: TCursor;
begin
  FCursorName := AName;
  if csDesigning in ComponentState then Exit;
  if TyChartCssCursor(AName, c) then
  begin
    if not FHasHostCursor then
    begin
      FHostCursor := Cursor;
      FHasHostCursor := True;
    end
    else if Cursor <> FCursorSet then
      FHostCursor := Cursor;
    FCursorSet := c;
    if Cursor <> c then Cursor := c;
  end
  else if FHasHostCursor then
  begin
    if Cursor = FCursorSet then Cursor := FHostCursor;
    FHasHostCursor := False;
  end;
end;
