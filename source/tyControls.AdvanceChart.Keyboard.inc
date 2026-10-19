{ Part of tyControls.AdvanceChart (included, not a unit): the keyboard and the accessible
  tree. Moved out of the unit only to keep it readable; what the control is and why it is
  built the way it is, see the unit header. }

function TTyAdvanceChart.AccessibleSummary: string;
var
  facts: TTyAriaFacts;
begin
  Result := '';
  if (FOption = nil) or not (FOption.Root is TJSONObject) then Exit;
  { an option that writes aria says what it wants -- off, a hand-written
    description, its own templates }
  if TJSONObject(FOption.Root).Find('aria') <> nil then Exit(GetAriaDescription);
  ConvertReady;
  AriaGather(nil, facts);
  if facts.SeriesCount < 1 then Exit;
  Result := TyAriaLabel(TyAriaDefaultLocale, facts);
end;

{ ==================== the keyboard and the accessible tree [Batch 144] ====================

  UPSTREAM HAS NO KEYBOARD. ECharts' accessibility is the aria description
  (the canvas' aria-label) and the decals; a page that wants keys writes
  them itself, with dispatchAction. So this is the port's design, and it is
  built the way such a page would build it, out of upstream's own actions:

  - The focus item moves over the walked series' view rows
    (tyControls.AdvChart.KeyNav has the keys). A move DISPATCHES downplay
    for the old item and highlight for the new one -- type, seriesIndex
    and the RAW dataIndex, the payload a page would write -- so the
    emphasis, the blur a focus rule asks for, and the highlight / downplay
    events are exactly the actions'.
  - Its tooltip is upstream's showTip for that item: the tooltip and the
    axis pointer resolved at the element's centre, which is where
    findPointFromSeries puts the point for a mark with no tooltip position
    of its own; the tooltip's triggerOn is not asked, as showTip does not
    ask it.
  - Enter / Space dispatch what a click on the item dispatches -- select,
    or unselect when it is selected, isFromClick true -- but only when the
    series has a selectedMode: a click on a series without one still
    dispatches (and upstream's events fire with nothing selected), a key
    does nothing there and leaves Enter to the form.
  - The ring is the theme's TyAdvChartFocusItem outline around the item's
    element, in the dynamic layer, while the keyboard holds the item.

  THE TAB STOP IS UNCHANGED: False, as it was declared and constructed. A
  host that wants the keyboard sets TabStop := True; a click then focuses
  the chart (TTyCustomControl.MouseDown) and Tab reaches it. }

const
  { the accessible items a series lists at most: the tree is built on every
    new layout, and a hundred thousand LCL objects would make every one of
    them slow. The keyboard walks every row regardless. }
  cTyAccMaxItems = 1000;

{ [F5] a box the ring and the tree can use: every side a number (a time
  axis over strings puts a timeline's checkpoint at NaN) }
function KbRectFinite(const R: TTyRectF): Boolean;
begin
  Result := not (IsNan(R.Left) or IsNan(R.Top) or IsNan(R.Right) or IsNan(R.Bottom)
    or IsInfinite(R.Left) or IsInfinite(R.Top) or IsInfinite(R.Right) or IsInfinite(R.Bottom));
end;

{ a highlight / downplay a page would write for the item; [F5] a graph
  edge's with its data type }
function KbHdPayload(const AType: string; ASeries, ARaw: Integer; AEdge: Boolean): string;
begin
  Result := '{"type":"' + AType + '","seriesIndex":' + IntToStr(ASeries);
  if AEdge then Result := Result + ',"dataType":"edge"';
  Result := Result + ',"dataIndex":' + IntToStr(ARaw) + '}';
end;

function TTyAdvanceChart.KbSeriesList: TTyKbSeriesArray;
var
  si, slot, n, e: Integer;
begin
  Result := nil;
  if FOption = nil then Exit;
  for si := 0 to FOption.ComponentCount('series') - 1 do
  begin
    slot := SlotOfSeries(si);
    if (slot < 0) or (slot > High(FBindings)) or (slot > High(FStores))
      or (FStores[slot] = nil) or FBindings[slot].Hidden then Continue;
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n].SeriesIndex := si;
    Result[n].Count := FStores[slot].Count;
    Result[n].Edge := False;
    { [F5] a graph's edges: a list of their own after its nodes; [R2-G] a
      sankey's links and a chord's ribbons the same way }
    if KbEdgeKind(slot) > 0 then
    begin
      e := KbEdgeCount(slot);
      if e > 0 then
      begin
        SetLength(Result, n + 2);
        Result[n + 1].SeriesIndex := si;
        Result[n + 1].Count := e;
        Result[n + 1].Edge := True;
      end;
    end;
  end;
end;

function TTyAdvanceChart.KbRawOf(ASeries, ARow: Integer; AEdge: Boolean): Integer;
var slot, j: Integer;
begin
  Result := -1;
  slot := SlotOfSeries(ASeries);
  if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
  { [F5] an edge's raw index: its place among the links as written;
    [R2-G] a sankey's link and a chord's ribbon are their edge data's own
    index }
  if AEdge then
  begin
    j := KbEdgeOf(ASeries, ARow);
    if j < 0 then Exit;
    if KbEdgeKind(slot) = 1 then Result := FGraphEdges[slot][j].RawIndex
    else Result := j;
    Exit;
  end;
  if (ARow < 0) or (ARow >= FStores[slot].Count) then Exit;
  Result := FStores[slot].GetRawIndex(ARow);
end;

function TTyAdvanceChart.KbValid: Boolean;
var slot: Integer;
begin
  Result := False;
  if (FKbSeries < 0) or (FKbRow < 0) then Exit;
  slot := SlotOfSeries(FKbSeries);
  if (slot < 0) or (slot > High(FBindings)) or (slot > High(FStores))
    or (FStores[slot] = nil) or FBindings[slot].Hidden then Exit;
  if FKbEdge then Exit(KbEdgeOf(FKbSeries, FKbRow) >= 0);
  Result := FKbRow < FStores[slot].Count;
end;

function TTyAdvanceChart.KbList: TTyPaintList;
begin
  if FAnimLive or (Length(FAnimStBind) > 0) then Result := AnimFrame
  else Result := FPaintList;
end;

function TTyAdvanceChart.KbElementOf(ASeries, ARow: Integer; AEdge: Boolean): Integer;
var
  raw, i, h, j, row: Integer;
  el: TTyChartElement;
begin
  Result := -1;
  if (FPaintList = nil) or not FPaintListValid then Exit;
  { [F5] an edge: the state machine's line host, else the first element
    drawing that edge row }
  if AEdge then
  begin
    j := KbEdgeOf(ASeries, ARow);
    if j < 0 then Exit;
    { a sankey's and a chord's hosts are by the edge's index too [R2-G] }
    if (ASeries <= High(FSt)) and (FSt[ASeries].Kind in [sskGraph, sskSankey, sskChord])
      and (j <= High(FSt[ASeries].EdgeHostIdx)) then
    begin
      h := FSt[ASeries].EdgeHostIdx[j];
      if (h >= 0) and (h < FPaintList.Count) then Exit(h);
    end;
    if KbEdgeKind(SlotOfSeries(ASeries)) = 1 then
      row := FGraphEdges[SlotOfSeries(ASeries)][j].Row
    else
      row := j;
    for i := 0 to FPaintList.Count - 1 do
    begin
      el := FPaintList.Element(i);
      if (el.Datum.SeriesIndex = ASeries) and (el.Datum.DataIndex = row) and el.Datum.IsEdge
        and (el.Datum.Kind = ctkSeries) and not el.Ignore and (el.Caption.Text = '') then
        Exit(i);
    end;
    Exit;
  end;
  raw := KbRawOf(ASeries, ARow);
  if raw < 0 then Exit;
  { the state machine's host for the row, where the series has one }
  if (ASeries <= High(FSt)) and (FSt[ASeries].Kind <> sskNone)
    and (raw <= High(FSt[ASeries].HostIdx)) then
  begin
    h := FSt[ASeries].HostIdx[raw];
    if (h >= 0) and (h < FPaintList.Count) then Exit(h);
  end;
  for i := 0 to FPaintList.Count - 1 do
  begin
    el := FPaintList.Element(i);
    if (el.Datum.SeriesIndex <> ASeries) or (el.Datum.DataIndex <> ARow)
      or el.Datum.IsEdge or (el.Datum.Kind <> ctkSeries) or el.Ignore
      or el.ProgHidden or el.IsGuide or (el.Shape.Kind = cskLarge) then Continue;
    { the mark itself before its label }
    if (el.Caption.Text = '') and not el.Silent then Exit(i);
    if Result < 0 then Result := i;
  end;
end;

procedure TTyAdvanceChart.KbShowTip;
var raw, el: Integer;
begin
  { [F5] AN EDGE: showTip finds its point in the series' data (the nodes) and
    names no edge, so the tooltip is _tryShow on the edge's element at its
    centre -- what manuallyShowTip does with the element it found }
  if FKbEdge then
  begin
    el := KbElementOf(FKbSeries, FKbRow, True);
    if el < 0 then KbHideTip else KbTipAtElement(el);
    Exit;
  end;
  raw := KbRawOf(FKbSeries, FKbRow);
  if raw < 0 then
  begin
    KbHideTip;
    Exit;
  end;
  { THE showTip ACTION on the item [Batch 153], as a page would dispatch
    it: under an axis trigger the axis tooltip through updateAxisPointer at
    the item's point, else the item's own box below its element; triggerOn
    is not asked }
  DispatchAction(Format('{"type":"showTip","seriesIndex":%d,"dataIndex":%d}',
    [FKbSeries, raw]));
end;

procedure TTyAdvanceChart.KbHideTip;
begin
  { the pointer and the box: updateAxisPointer with currTrigger 'leave' hides
    the pointers and dispatches the hideTip; with no pointer up, the hideTip
    alone [Batch 153] }
  if Length(FTipHits) > 0 then
    DispatchAction('{"type":"updateAxisPointer","currTrigger":"leave"}')
  else
    DispatchAction('{"type":"hideTip"}');
end;

procedure TTyAdvanceChart.KbGo(ASeries, ARow: Integer; AEdge: Boolean);
var raw: Integer;
begin
  raw := KbRawOf(ASeries, ARow, AEdge);
  if raw < 0 then Exit;
  { [F5] the items' stop: a component's part lets go first }
  if FKbStop.Kind <> ksItems then
  begin
    KbStopLeave;
    FKbStop := TyKbStop(ksItems, 0, 0);
  end;
  if not (FKbActive and (ASeries = FKbSeries) and (ARow = FKbRow) and (AEdge = FKbEdge)) then
  begin
    if FKbActive and KbValid then
      DispatchAction(KbHdPayload('downplay', FKbSeries, KbRawOf(FKbSeries, FKbRow, FKbEdge), FKbEdge));
    FKbSeries := ASeries;
    FKbRow := ARow;
    FKbEdge := AEdge;
    FKbActive := True;
    DispatchAction(KbHdPayload('highlight', ASeries, raw, AEdge));
  end;
  KbShowTip;
  if (FAccLink <> nil) and FAccLink.InUse then
  begin
    AccessibleSync;
    FAccLink.NotifyFocus(AccessibleFocusedChild);
  end;
  InvalidateFrame;
end;

procedure TTyAdvanceChart.KbRelease(ADownplay: Boolean);
begin
  if not FKbActive then Exit;
  if ADownplay and KbValid then
    DispatchAction(KbHdPayload('downplay', FKbSeries, KbRawOf(FKbSeries, FKbRow, FKbEdge), FKbEdge));
  FKbActive := False;
  KbHideTip;
  if (FAccLink <> nil) and FAccLink.InUse and Focused then FAccLink.NotifyFocus(nil);
  InvalidateFrame;
end;

function TTyAdvanceChart.KbActivate: Boolean;
var
  slot, j: Integer;
  t: TTyChartEventTarget;
begin
  Result := False;
  if not (FKbActive and KbValid) then Exit;
  slot := SlotOfSeries(FKbSeries);
  SelEnsure(slot);
  if (FKbSeries > High(FSel)) or not FSelInit[FKbSeries]
    or (FSel[FKbSeries].Mode = ssmOff) then Exit;
  t := Default(TTyChartEventTarget);
  t.HdKind := 1;
  t.HdSeries := FKbSeries;
  t.HdRow := FKbRow;
  t.HdEdge := False;
  { [F5] an edge: its element's row, the edge flag -- the click's target;
    [R2-G] a sankey's link's and a chord's ribbon's is the edge's index }
  if FKbEdge then
  begin
    j := KbEdgeOf(FKbSeries, FKbRow);
    if j < 0 then Exit;
    t.HdEdge := True;
    if KbEdgeKind(slot) = 1 then t.HdRow := FGraphEdges[slot][j].Row
    else t.HdRow := j;
  end;
  StClickSelect(t);
  Result := True;
end;

procedure TTyAdvanceChart.PaintKbRing(APainter: TTyPainter);
var
  idx, off: Integer;
  b: TTyRectF;
  st: TTyStyleSet;
  r: TRect;
begin
  { [F5] a component's part: its own box }
  if FKbStopOn then
  begin
    if not KbPartRect(FKbStop, FKbPart, b) then Exit;
  end
  else
  begin
    if not (FKbActive and KbValid) then Exit;
    idx := KbElementOf(FKbSeries, FKbRow, FKbEdge);
    if idx < 0 then Exit;
    b := TyShapeBounds(KbList.Element(idx).Shape);
  end;
  if not KbRectFinite(b) then Exit;
  st := ActiveController.Model.ResolveStyle('TyAdvChartFocusItem', '', []);
  if not ((tpOutline in st.Present) and (st.OutlineWidth > 0)) then Exit;
  { the library's ring convention (TTyCustomControl.DrawFrame): the offset
    insets the ring, so the theme's negative one sets it off the mark }
  off := APainter.Scale(st.OutlineOffset);
  r := Rect(Floor(b.Left) + off, Floor(b.Top) + off, Ceil(b.Right) - off, Ceil(b.Bottom) - off);
  if (r.Right <= r.Left) or (r.Bottom <= r.Top) then Exit;
  APainter.StrokeBorder(r, TyEffectiveCorners(st), st.OutlineWidth, st.OutlineColor);
end;

procedure TTyAdvanceChart.KeyDown(var Key: Word; Shift: TShiftState);
var
  cmd: TTyKbCommand;
  list: TTyKbSeriesArray;
  pos, row, i, cur, nxt: Integer;
  stops: TTyKbStopArray;
begin
  inherited KeyDown(Key, Shift);
  if (Key = 0) or (csDesigning in ComponentState) then Exit;
  stops := KbStops;
  cur := KbCurPos(stops);
  { [F5] TAB: the next stop (Shift: the previous), as in a composite
    control; past the ends the key is the form's and the focus leaves }
  if TyKbIsTab(Key, Shift) then
  begin
    if TyKbTab(Length(stops), cur, ssShift in Shift, nxt) then
    begin
      KbSwitchStop(stops[nxt], 0);
      Key := 0;
    end;
    Exit;
  end;
  if (cur >= 0) and not TyKbSameStop(stops[cur], FKbStop) then
  begin
    { the stop the keyboard was on is gone: nothing of it to take back }
    FKbStopOn := False;
    FKbHoverHas := False;
    FKbGeoName := '';
    FKbStop := stops[cur];
    FKbPart := -1;
  end;
  { [F5] a component's stop: its keys }
  if (cur >= 0) and (FKbStop.Kind <> ksItems) then
  begin
    if KbComponentKey(Key, Shift) then Key := 0;
    Exit;
  end;
  cmd := TyKbCommandOf(Key, Shift);
  case cmd of
    kbcNone: ;
    kbcActivate:
      if KbActivate then Key := 0;
    kbcClear:
      if FKbActive then
      begin
        KbRelease(True);
        FKbSeries := -1;
        FKbRow := -1;
        FKbEdge := False;
        Key := 0;
      end;
  else
    { A MOVING KEY IS ALWAYS TAKEN, with or without an item to move to:
      left over, LCL's DoArrowKey would hand the focus to a sibling }
    Key := 0;
    { coming back: the first key takes up the item the exit let go }
    if not FKbActive and KbValid then
    begin
      KbGo(FKbSeries, FKbRow, FKbEdge);
      Exit;
    end;
    list := KbSeriesList;
    pos := -1;
    row := FKbRow;
    if KbValid then
      for i := 0 to High(list) do
        if (list[i].SeriesIndex = FKbSeries) and (list[i].Edge = FKbEdge) then pos := i;
    if TyKbMove(list, cmd, pos, row) then KbGo(list[pos].SeriesIndex, row, list[pos].Edge);
  end;
end;

procedure TTyAdvanceChart.DoExit;
begin
  KbRelease(True);
  { [F5] a component's part too; the stop and the part are kept }
  KbStopLeave;
  inherited DoExit;
end;

procedure TTyAdvanceChart.CreateWnd;
begin
  inherited CreateWnd;
  if FAccLink <> nil then FAccLink.Attach;
end;

procedure TTyAdvanceChart.DestroyWnd;
begin
  if FAccLink <> nil then FAccLink.Detach;
  inherited DestroyWnd;
end;

function TTyAdvanceChart.KeyboardItem: TTyChartDatumRef;
begin
  if FKbActive and KbValid then
  begin
    Result := TyChartDatum(FKbSeries, FKbRow, KbRawOf(FKbSeries, FKbRow, FKbEdge));
    Result.IsEdge := FKbEdge;
  end
  else
    Result := TyChartNoDatum;
end;

function TTyAdvanceChart.SetKeyboardItem(ASeriesIndex, ADataIndex: Integer;
  AEdge: Boolean): Boolean;
var
  slot, r: Integer;
begin
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FBindings)) or (slot > High(FStores))
    or (FStores[slot] = nil) or FBindings[slot].Hidden then Exit;
  { [F5] an edge by its raw index }
  if AEdge then
  begin
    for r := 0 to KbEdgeCount(slot) - 1 do
      if KbRawOf(ASeriesIndex, r, True) = ADataIndex then
      begin
        KbGo(ASeriesIndex, r, True);
        Exit(True);
      end;
    Exit;
  end;
  for r := 0 to FStores[slot].Count - 1 do
    if FStores[slot].GetRawIndex(r) = ADataIndex then
    begin
      KbGo(ASeriesIndex, r);
      Exit(True);
    end;
end;

procedure TTyAdvanceChart.ClearKeyboardItem;
begin
  KbRelease(True);
  FKbSeries := -1;
  FKbRow := -1;
  FKbEdge := False;
  { [F5] nothing held anywhere: the stop back to the items }
  KbStopLeave;
  FKbStop := TyKbStop(ksItems, 0, 0);
  FKbPart := -1;
end;

function TTyAdvanceChart.AccItemIndexOf(AObj: TLazAccessibleObject): Integer;
var i: Integer;
begin
  for i := 0 to High(FAccItemObjs) do
    if FAccItemObjs[i] = AObj then Exit(i);
  Result := -1;
end;

{ ==================== the component keyboard [F5] ====================

  ECHARTS HAS NO KEYBOARD FOR ITS COMPONENTS EITHER, so this is the port's
  design again, made as D11 made the data items' (Batch 144): every key
  does what a pointer on that component does, through the same handlers,
  so the actions and their payloads are upstream's.

  - THE STOPS (KeyNav): the data items, the markers, each geo's regions,
    each legend, each visualMap (a continuous one with handles: one stop
    per handle), each dataZoom, the timeline, each toolbox, each brush.
    Tab walks them, Shift+Tab walks back, and off either end the key is
    the form's and the focus leaves. Tab landing on a stop takes its part
    up at once; leaving the control lets it go and keeps the place, and the
    first key after coming back takes it up again (D11's rule).
  - TAKING A PART UP is what the pointer coming over it does: a legend
    item's mouseover highlight, a selector's emphasis, a thumb's emphasis,
    a piece's hover-link highlight, a slider's data labels, a toolbox
    icon's emphasis and title, a marker's lift and tooltip, a geo region's
    highlight and showTip ({geoIndex, name}). Letting it go is the pointer
    leaving.
  - THE KEYS dispatch what the component's own handlers dispatch: an
    item's click (downplay, legendToggleSelect, highlight), the pager's
    legendScroll, the selector's legendAllSelect / legendInverseSelect; a
    slider's dataZoom as a drag of its window (Shift: of its end handle)
    through _updateInterval, an inside's as its pan (makeMover) or as one
    wheel notch about the grid's centre; timelineChange as the prev and
    next buttons and a tick's click, timelinePlayChange as the play
    button; a toolbox icon's onclick; the brush's clear button
    (axisAreaSelect, then brush with no areas); a thumb's drag as
    selectDataRange (while it moves when realtime, at the release when
    not); a piece's click as selectDataRange; a region's click as
    geoToggleSelect. }

const
  { a visualMap handle's arrow: a fiftieth of the bar; its page key: a
    tenth }
  cTyKbVmStep = 50;
  cTyKbVmPage = 10;

{ an axis-aligned box over a rect through a matrix }
function KbXformRect(const M: TTyMat2D; const A: TTyXYWH): TTyRectF;
var
  xs, ys: array[0..3] of Double;
  k: Integer;
begin
  xs[0] := M[0] * A.X + M[2] * A.Y + M[4];
  ys[0] := M[1] * A.X + M[3] * A.Y + M[5];
  xs[1] := M[0] * (A.X + A.W) + M[2] * A.Y + M[4];
  ys[1] := M[1] * (A.X + A.W) + M[3] * A.Y + M[5];
  xs[2] := M[0] * A.X + M[2] * (A.Y + A.H) + M[4];
  ys[2] := M[1] * A.X + M[3] * (A.Y + A.H) + M[5];
  xs[3] := M[0] * (A.X + A.W) + M[2] * (A.Y + A.H) + M[4];
  ys[3] := M[1] * (A.X + A.W) + M[3] * (A.Y + A.H) + M[5];
  Result := TyRectF(xs[0], ys[0], xs[0], ys[0]);
  for k := 1 to 3 do
  begin
    if xs[k] < Result.Left then Result.Left := xs[k];
    if xs[k] > Result.Right then Result.Right := xs[k];
    if ys[k] < Result.Top then Result.Top := ys[k];
    if ys[k] > Result.Bottom then Result.Bottom := ys[k];
  end;
end;

procedure KbUnion(var AHas: Boolean; var AInto: TTyRectF; const B: TTyRectF);
begin
  if IsNan(B.Left) or IsNan(B.Top) or IsNan(B.Right) or IsNan(B.Bottom) then Exit;
  if not AHas then
  begin
    AInto := B;
    AHas := True;
    Exit;
  end;
  if B.Left < AInto.Left then AInto.Left := B.Left;
  if B.Top < AInto.Top then AInto.Top := B.Top;
  if B.Right > AInto.Right then AInto.Right := B.Right;
  if B.Bottom > AInto.Bottom then AInto.Bottom := B.Bottom;
end;

function KbJsonName(const AName: string): string;
begin
  Result := '"' + StringToJSONString(AName) + '"';
end;

function TTyAdvanceChart.KbEdgeKind(ASlot: Integer): Integer;
begin
  Result := 0;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FBindings[ASlot].SeriesType = TyGraphSeriesTypeName then Result := 1
  else if StSankeySlot(ASlot) then Result := 2
  else if StChordSlot(ASlot) then Result := 3;
end;

function TTyAdvanceChart.KbEdgeCount(ASlot: Integer): Integer;
var j: Integer;
begin
  Result := 0;
  case KbEdgeKind(ASlot) of
    1:
      begin
        if (ASlot > High(FGraphEdges)) or (ASlot > High(FGraphNodes)) then Exit;
        for j := 0 to High(FGraphEdges[ASlot]) do
          if GraphEdgeSurvives(FGraphNodes[ASlot], FGraphEdges[ASlot][j]) then Inc(Result);
      end;
    { [R2-G] a sankey's every link; a chord's ribbons between kept nodes }
    2: Result := Length(FSankeys[ASlot].Edges);
    3:
      for j := 0 to High(FChords[ASlot].Edges) do
        if FChords[ASlot].Edges[j].Kept then Inc(Result);
  end;
end;

function TTyAdvanceChart.KbEdgeOf(ASeries, ARow: Integer): Integer;
var slot, j, n: Integer;
begin
  Result := -1;
  slot := SlotOfSeries(ASeries);
  if ARow < 0 then Exit;
  case KbEdgeKind(slot) of
    1:
      begin
        if slot > High(FGraphNodes) then Exit;
        Result := StGraphEdgeOfInner(slot, ARow);
      end;
    2: if ARow <= High(FSankeys[slot].Edges) then Result := ARow;
    3:
      begin
        n := 0;
        for j := 0 to High(FChords[slot].Edges) do
          if FChords[slot].Edges[j].Kept then
          begin
            if n = ARow then Exit(j);
            Inc(n);
          end;
      end;
  end;
end;

function TTyAdvanceChart.KbIsSlider(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FZoomSpecs))
    and (FZoomSpecs[AIndex].SubType = 'slider')
    and (AIndex <= High(FDzLayouts)) and FDzLayouts[AIndex].Valid
    and (AIndex <= High(FDzState)) and (AIndex <= High(FDzInteract))
    and (AIndex <= High(FDzViews));
end;

function TTyAdvanceChart.KbIsInside(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FZoomSpecs))
    and (FZoomSpecs[AIndex].SubType = 'inside') and not FZoomSpecs[AIndex].NoTarget
    and (AIndex <= High(FDzInteract)) and not FDzInteract[AIndex].Disabled
    and (AIndex <= High(FDzInLo)) and not IsNan(FDzInLo[AIndex])
    and not IsNan(FDzInHi[AIndex]);
end;

{ a continuous visualMap a pointer can drag: calculable, laid out with its
  two handles }
function TTyAdvanceChart.KbVmHandles(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FVisualLayouts))
    and (AIndex <= High(FVisualViews)) and (AIndex <= High(FVmLive))
    and FVisualLayouts[AIndex].Valid and not FVisualLayouts[AIndex].Piecewise
    and VmContinuous(AIndex) and FVisualViews[AIndex].Calculable
    and (Length(FVisualLayouts[AIndex].Handles) >= 2);
end;

function TTyAdvanceChart.KbListReady: Boolean;
begin
  ConvertReady;
  if ((FPaintList = nil) or not FPaintListValid) and (FLastPPI > 0) and (FOption <> nil) then
    BuildSeriesList(NewTextMeasurer(FLastPPI), FLastPPI);
  Result := (FPaintList <> nil) and FPaintListValid;
end;

function TTyAdvanceChart.KbMarkerList(out ASeries, AKinds, AIndex,
  AEls: TTyIntegerArray): Integer;
var
  i, j, n, t: Integer;
  el: TTyChartElement;
  key, kj: Int64;

  function KeyOf(S, K, D: Integer): Int64;
  begin
    Result := (Int64(S) shl 34) + (Int64(K) shl 30) + D;
  end;

begin
  ASeries := nil;
  AKinds := nil;
  AIndex := nil;
  AEls := nil;
  Result := 0;
  if not KbListReady then Exit;
  n := 0;
  for i := 0 to FPaintList.Count - 1 do
  begin
    el := FPaintList.Element(i);
    if not (el.Datum.Kind in [ctkMarkPoint, ctkMarkLine, ctkMarkArea]) then Continue;
    if (el.Datum.ComponentIndex < 0) or (el.Datum.DataIndex < 0) then Continue;
    if el.Ignore or (el.Caption.Text <> '') then Continue;
    key := KeyOf(el.Datum.ComponentIndex, Ord(el.Datum.Kind), el.Datum.DataIndex);
    j := 0;
    while (j < n) and (KeyOf(ASeries[j], AKinds[j], AIndex[j]) <> key) do Inc(j);
    if j < n then
    begin
      { the first element that takes the pointer, else the first }
      if FPaintList.Element(AEls[j]).Silent and not el.Silent then AEls[j] := i;
      Continue;
    end;
    SetLength(ASeries, n + 1);
    SetLength(AKinds, n + 1);
    SetLength(AIndex, n + 1);
    SetLength(AEls, n + 1);
    { in key order: the host series, the kind, the data index }
    j := n;
    while j > 0 do
    begin
      kj := KeyOf(ASeries[j - 1], AKinds[j - 1], AIndex[j - 1]);
      if kj <= key then Break;
      ASeries[j] := ASeries[j - 1];
      AKinds[j] := AKinds[j - 1];
      AIndex[j] := AIndex[j - 1];
      AEls[j] := AEls[j - 1];
      Dec(j);
    end;
    ASeries[j] := el.Datum.ComponentIndex;
    AKinds[j] := Ord(el.Datum.Kind);
    AIndex[j] := el.Datum.DataIndex;
    AEls[j] := i;
    Inc(n);
  end;
  t := n;
  Result := t;
end;

function TTyAdvanceChart.KbGeoRegions(AGeo: Integer): TTyIntegerArray;
var g: Integer;
begin
  Result := nil;
  if (AGeo < 0) or (AGeo > High(FGeos)) or (FGeos[AGeo] = nil) then Exit;
  for g := 0 to FGeos[AGeo].GroupCount - 1 do
    if FGeos[AGeo].GroupName(g) <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := g;
    end;
end;

function TTyAdvanceChart.KbVmPieces(AIndex: Integer): TTyIntegerArray;
var j: Integer;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(FVisualLayouts)) or not FVisualLayouts[AIndex].Valid
    or not FVisualLayouts[AIndex].Piecewise then Exit;
  for j := 0 to High(FVisualLayouts[AIndex].Items) do
    if not FVisualLayouts[AIndex].Items[j].IsText then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := FVisualLayouts[AIndex].Items[j].PieceIndex;
    end;
end;

function TTyAdvanceChart.KbStops: TTyKbStopArray;
var
  list: TTyKbSeriesArray;
  i, k: Integer;
  mk: TTyMarkerKind;

  procedure Add(AKind: TTyKbStopKind; AIndex, ASub: Integer);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := TyKbStop(AKind, AIndex, ASub);
  end;

begin
  Result := nil;
  if FOption = nil then Exit;
  { a layout the option made stale is made first: the stops are its }
  ConvertReady;
  list := KbSeriesList;
  for i := 0 to High(list) do
    if list[i].Count > 0 then
    begin
      Add(ksItems, 0, 0);
      Break;
    end;
  { the markers: by the models, not the display list -- a key between two
    paints builds no list for a chart that has none }
  for k := 0 to High(FMarkers) do
  begin
    for mk := Low(TTyMarkerKind) to High(TTyMarkerKind) do
      if FMarkers[k].Blocks[mk].Present and (FMarkers[k].Blocks[mk].Count > 0) then
      begin
        Add(ksMarkers, 0, 0);
        Break;
      end;
    if (Length(Result) > 0) and (Result[High(Result)].Kind = ksMarkers) then Break;
  end;
  for k := 0 to Math.Min(High(FGeos), FOption.ComponentCount('geo') - 1) do
    if Length(KbGeoRegions(k)) > 0 then Add(ksGeo, k, 0);
  for k := 0 to High(FLegends) do
    if FLegends[k].Valid and (Length(FLegends[k].Items) > 0) then Add(ksLegend, k, 0);
  for k := 0 to High(FVisualLayouts) do
  begin
    if (k > High(FVisualViews)) or not FVisualLayouts[k].Valid then Continue;
    if FVisualLayouts[k].Piecewise then
    begin
      if (not FVisualViews[k].Silent) and (Length(KbVmPieces(k)) > 0) then Add(ksVisualMap, k, 0);
    end
    else if KbVmHandles(k) then
    begin
      Add(ksVisualMap, k, 0);
      Add(ksVisualMap, k, 1);
    end;
  end;
  for k := 0 to High(FZoomSpecs) do
    if KbIsSlider(k) or KbIsInside(k) then Add(ksDataZoom, k, 0);
  if (FTlView <> nil) and FTlView.Shown and (FTlView.Count > 0) then Add(ksTimeline, 0, 0);
  for k := 0 to High(FTbSpecs) do
    if (k <= High(FTbLayouts)) and FTbLayouts[k].Valid and (Length(FTbSpecs[k].Icons) > 0) then
      Add(ksToolbox, k, 0);
  for k := 0 to High(FBrushCtls) do
    if FBrushCtls[k] <> nil then Add(ksBrush, k, 0);
end;

function TTyAdvanceChart.KbCurPos(const AStops: TTyKbStopArray): Integer;
begin
  Result := TyKbStopPos(AStops, FKbStop);
  if Result >= 0 then Exit;
  Result := TyKbStopPos(AStops, TyKbStop(ksItems, 0, 0));
  if Result >= 0 then Exit;
  if Length(AStops) > 0 then Result := 0 else Result := -1;
end;

function TTyAdvanceChart.KbPartCount(const AStop: TTyKbStop): Integer;
var s, kd, ix, els: TTyIntegerArray;
begin
  Result := 1;
  case AStop.Kind of
    ksMarkers: Result := KbMarkerList(s, kd, ix, els);
    ksGeo: Result := Length(KbGeoRegions(AStop.Index));
    ksLegend:
      if (AStop.Index >= 0) and (AStop.Index <= High(FLegends)) then
        Result := Length(FLegends[AStop.Index].Items) + Length(FLegends[AStop.Index].Selector)
      else
        Result := 0;
    ksVisualMap:
      if (AStop.Index >= 0) and (AStop.Index <= High(FVisualLayouts))
        and FVisualLayouts[AStop.Index].Piecewise then
        Result := Length(KbVmPieces(AStop.Index));
    ksToolbox:
      if (AStop.Index >= 0) and (AStop.Index <= High(FTbSpecs)) then
        Result := Length(FTbSpecs[AStop.Index].Icons)
      else
        Result := 0;
  end;
end;

function TTyAdvanceChart.KbLegendTarget(ALegend, APart: Integer): TTyChartEventTarget;
var n, k: Integer;
begin
  Result := Default(TTyChartEventTarget);
  Result.Params := TyChartBlankParams;
  if (ALegend < 0) or (ALegend > High(FLegends)) or (APart < 0) then Exit;
  n := Length(FLegends[ALegend].Items);
  Result.HdSeries := ALegend;
  if APart < n then
  begin
    { the item group's own handlers: by the series the name is, else by
      the data (EventTargetAt) }
    Result.HdKind := 4;
    Result.HdRow := APart;
    Result.HdName := FLegends[ALegend].Items[APart].Name;
    for k := 0 to FOption.ComponentCount('series') - 1 do
      if SeriesModelName(k) = Result.HdName then
      begin
        Result.HdLegendSeries := True;
        Break;
      end;
  end
  else if APart - n <= High(FLegends[ALegend].Selector) then
  begin
    Result.HdKind := 5;
    Result.HdRow := APart - n;
  end;
end;

{ a scroll legend's item on the page shown: its centre inside the clip }
function TTyAdvanceChart.KbLegendVisible(ALegend, AItem: Integer): Boolean;
var b, c: TTyRectF; cx, cy: Double;
begin
  Result := True;
  if (ALegend < 0) or (ALegend > High(FLegends)) then Exit;
  if not (FLegends[ALegend].IsScroll and FLegends[ALegend].HasClip) then Exit;
  if (AItem < 0) or (AItem > High(FLegends[ALegend].Items)) then Exit;
  b := FLegends[ALegend].Items[AItem].Bounds;
  c := FLegends[ALegend].Clip;
  cx := (b.Left + b.Right) / 2;
  cy := (b.Top + b.Bottom) / 2;
  Result := (cx >= c.Left) and (cx <= c.Right) and (cy >= c.Top) and (cy <= c.Bottom);
end;

procedure TTyAdvanceChart.KbTipAtElement(AEl: Integer);
var
  ev: TTyTipEvent;
  b: TTyRectF;
begin
  if not KbListReady or (AEl < 0) or (AEl >= FPaintList.Count) then Exit;
  if not TyTooltipSpecOf(FOption, -1, -1).HasComponent then Exit;
  b := TyShapeBounds(KbList.Element(AEl).Shape);
  { the timers due fire first, as for a showTip }
  TipAdvance(TipClock);
  ev := TipEventBlank;
  ev.X := (b.Left + b.Right) / 2;
  ev.Y := (b.Top + b.Bottom) / 2;
  ev.Datum := FPaintList.Element(AEl).Datum;
  ev.Element := AEl;
  ev.PosDefault := True;
  TipTryShowEvent(ev, False);
  TipInvalidate;
  TipArmTimer;
end;

procedure TTyAdvanceChart.KbNotifyFocus;
begin
  if (FAccLink <> nil) and FAccLink.InUse then
  begin
    AccessibleSync;
    FAccLink.NotifyFocus(AccessibleFocusedChild);
  end;
end;

procedure TTyAdvanceChart.KbStopTake(APart: Integer);
var
  t: TTyChartEventTarget;
  s, kd, ix, els, regs, pcs: TTyIntegerArray;
  n, i: Integer;
  dzt: TTyDzTarget;
begin
  if FKbStopOn then KbStopLeave;
  FKbPart := APart;
  FKbStopOn := True;
  FKbHoverHas := False;
  i := FKbStop.Index;
  case FKbStop.Kind of
    ksMarkers:
      begin
        n := KbMarkerList(s, kd, ix, els);
        if (APart >= 0) and (APart < n) then
        begin
          { [R2-B] the pointer over it: the item's hover on the states (its
            own focus too), then its tooltip }
          FKbHoverT := MarkerEventTarget(els[APart]);
          FKbHoverHas := FKbHoverT.HdKind = 3;
          if FKbHoverHas then StHoverOver(FKbHoverT);
          KbTipAtElement(els[APart]);
        end;
      end;
    ksGeo:
      begin
        regs := KbGeoRegions(i);
        if (APart >= 0) and (APart <= High(regs)) then
        begin
          FKbGeoIndex := i;
          FKbGeoName := FGeos[i].GroupName(regs[APart]);
          DispatchAction('{"type":"highlight","geoIndex":' + IntToStr(i) + ',"name":'
            + KbJsonName(FKbGeoName) + '}');
          DispatchAction('{"type":"showTip","geoIndex":' + IntToStr(i) + ',"name":'
            + KbJsonName(FKbGeoName) + '}');
        end;
      end;
    ksLegend:
      begin
        t := KbLegendTarget(i, APart);
        if t.HdKind in [4, 5] then
        begin
          FKbHoverT := t;
          FKbHoverHas := True;
          StHoverOver(t);
        end;
      end;
    ksVisualMap:
      if (i <= High(FVisualLayouts)) and FVisualLayouts[i].Piecewise then
      begin
        pcs := KbVmPieces(i);
        if (APart >= 0) and (APart <= High(pcs)) then
        begin
          t := Default(TTyChartEventTarget);
          t.Params := TyChartBlankParams;
          t.HdKind := 7;
          t.HdSeries := i;
          t.HdRow := cVmPiece + 2 * pcs[APart];
          if i <= High(FVmLive) then t.HdGen := FVmLive[i].Gen;
          FKbHoverT := t;
          FKbHoverHas := True;
          VmElementEvent('mouseover', t, 0, 0);
        end;
      end
      else if KbVmHandles(i) then
      begin
        t := Default(TTyChartEventTarget);
        t.Params := TyChartBlankParams;
        t.HdKind := 7;
        t.HdSeries := i;
        t.HdRow := cVmThumb0 + FKbStop.Sub;
        t.HdGen := FVmLive[i].Gen;
        FKbHoverT := t;
        FKbHoverHas := True;
        StHoverOver(t);
        VmApplyStates;
      end;
    ksDataZoom:
      if KbIsSlider(i) then
      begin
        { the window's data labels, as over the filler }
        dzt := Default(TTyDzTarget);
        dzt.Kind := dtkSlider;
        dzt.Slider := i;
        dzt.Role := dzrFiller;
        DzMouseOver(dzt);
        DzViewUpdate;
      end;
    ksToolbox:
      if (i <= High(FTbSpecs)) and (APart >= 0) and (APart <= High(FTbSpecs[i].Icons)) then
      begin
        t := Default(TTyChartEventTarget);
        t.Params := TyChartBlankParams;
        t.HdKind := 8;
        t.HdSeries := i;
        t.HdRow := APart;
        t.HdGen := FTbGen;
        FKbHoverT := t;
        FKbHoverHas := True;
        TbMouseOver(t);
        TbFrame;
      end;
  end;
  KbNotifyFocus;
  InvalidateFrame;
end;

procedure TTyAdvanceChart.KbStopLeave;
var
  t: TTyChartEventTarget;
  dzt: TTyDzTarget;
  i: Integer;
begin
  if not FKbStopOn then Exit;
  FKbStopOn := False;
  i := FKbStop.Index;
  case FKbStop.Kind of
    ksMarkers:
      begin
        if FKbHoverHas then StHoverOut(FKbHoverT);
        KbHideTip;
      end;
    ksGeo:
      if FKbGeoName <> '' then
      begin
        DispatchAction('{"type":"downplay","geoIndex":' + IntToStr(FKbGeoIndex) + ',"name":'
          + KbJsonName(FKbGeoName) + '}');
        KbHideTip;
        FKbGeoName := '';
        FKbGeoIndex := -1;
      end;
    ksLegend:
      if FKbHoverHas then StHoverOut(FKbHoverT);
    ksVisualMap:
      if FKbHoverHas then
      begin
        t := FKbHoverT;
        { a view rebuilt since: its elements are the new ones }
        if (t.HdSeries >= 0) and (t.HdSeries <= High(FVmLive)) then t.HdGen := FVmLive[t.HdSeries].Gen;
        if t.HdRow >= cVmPiece then VmElementEvent('mouseout', t, 0, 0)
        else
        begin
          StHoverOut(t);
          VmApplyStates;
        end;
      end;
    ksDataZoom:
      if KbIsSlider(i) then
      begin
        dzt := Default(TTyDzTarget);
        dzt.Kind := dtkSlider;
        dzt.Slider := i;
        dzt.Role := dzrFiller;
        DzMouseOut(dzt);
        DzViewUpdate;
      end;
    ksToolbox:
      if FKbHoverHas then
      begin
        t := FKbHoverT;
        t.HdGen := FTbGen;
        TbMouseOut(t);
        TbFrame;
      end;
  end;
  FKbHoverHas := False;
  InvalidateFrame;
end;

function TTyAdvanceChart.KbTakeMarkerForTest(APart: Integer): Boolean;
var st: TTyKbStop;
begin
  st := Default(TTyKbStop);
  st.Kind := ksMarkers;
  Result := (APart >= 0) and (KbPartCount(st) > APart);
  if Result then KbSwitchStop(st, APart);
end;

procedure TTyAdvanceChart.KbLeaveForTest;
begin
  KbStopLeave;
end;

procedure TTyAdvanceChart.KbSwitchStop(const AStop: TTyKbStop; APart: Integer);
var i, n: Integer;
begin
  { what holds the keyboard now lets go -- an item keeps its place, as an
    exit keeps it }
  if FKbStop.Kind = ksItems then KbRelease(True) else KbStopLeave;
  FKbStop := AStop;
  if AStop.Kind = ksItems then
  begin
    FKbStopOn := False;
    FKbPart := -1;
    { the item it had, taken up again }
    if not FKbActive and KbValid then KbGo(FKbSeries, FKbRow, FKbEdge)
    else KbNotifyFocus;
    InvalidateFrame;
    Exit;
  end;
  n := KbPartCount(AStop);
  if (APart < 0) or (APart >= n) then APart := 0;
  { a scroll legend: an item on the page shown }
  if (AStop.Kind = ksLegend) and (APart < Length(FLegends[AStop.Index].Items))
    and not KbLegendVisible(AStop.Index, APart) then
    for i := 0 to High(FLegends[AStop.Index].Items) do
      if KbLegendVisible(AStop.Index, i) then
      begin
        APart := i;
        Break;
      end;
  KbStopTake(APart);
end;

procedure TTyAdvanceChart.KbDataZoomKey(AIndex: Integer; ACmd: TTyKbCommand);
var
  key: string;
  L, spanPx, step, page, d, mn, mx, span, sc: Double;
  hnd, lo, hi, t, g: Integer;
  moved: Boolean;
  r: array[0..1] of Double;
  a: TTyDzAction;
  dir: TTyDzDirection;
  gr: TTyXYWH;
  ax, axis: TTyAxis;
  gi: Integer;
begin
  key := DzStateKey;
  if KbIsSlider(AIndex) then
  begin
    { THE SLIDER: a drag of the window, or Shift a drag of an end hnd,
      by a tenth of the window (at least a hundredth of the slider), a
      page key by the window, Home / End to the ends -- through
      _updateInterval as the pointer's drag, then the slider's dispatch
      (the panel click's: no realtime animation) }
    L := FDzLayouts[AIndex].L;
    spanPx := Abs(FDzState[AIndex].Ends[1] - FDzState[AIndex].Ends[0]);
    step := spanPx / 10;
    if step < L / 100 then step := L / 100;
    page := spanPx;
    if page < step then page := step;
    if FDzState[AIndex].Ends[0] <= FDzState[AIndex].Ends[1] then lo := 0 else lo := 1;
    hi := 1 - lo;
    hnd := -1;
    case ACmd of
      kbcPrev, kbcNextSeries: d := -step;
      kbcNext, kbcPrevSeries: d := step;
      kbcPagePrev: d := -page;
      kbcPageNext: d := page;
      kbcFirst: d := -2 * L;
      kbcLast: d := 2 * L;
      kbcShrink:
        begin
          hnd := hi;
          d := -step;
        end;
      kbcGrow:
        begin
          hnd := hi;
          d := step;
        end;
      kbcGrowStart:
        begin
          hnd := lo;
          d := -2 * L;
        end;
      kbcGrowEnd:
        begin
          hnd := hi;
          d := 2 * L;
        end;
    else
      Exit;
    end;
    DzSpans(AIndex, mn, mx);
    { zoomLock: a hnd moves the whole window, as in the drag }
    if FDzInteract[AIndex].ZoomLock then hnd := -1;
    moved := TyDzUpdateInterval(FDzState[AIndex].Ends, L, d, hnd, mn, mx,
      FDzState[AIndex].Range, True);
    FDzState[AIndex].NonRealtime := False;
    if moved then DzRunSliderAction(AIndex, False, False);
  end
  else if KbIsInside(AIndex) then
  begin
    { THE INSIDE: its pan (makeMover) by a tenth of the window (at least
      one percent), a page key by the window, Home / End to the ends; Shift
      one wheel notch in or out about the grid's centre -- the roam's batch
      for this dataZoom }
    r[0] := FDzInLo[AIndex];
    r[1] := FDzInHi[AIndex];
    span := r[1] - r[0];
    step := span / 10;
    if step < 1 then step := 1;
    page := span;
    if page < step then page := step;
    moved := False;
    case ACmd of
      kbcPrev, kbcNextSeries: moved := TyDzInsideMove(r, -step);
      kbcNext, kbcPrevSeries: moved := TyDzInsideMove(r, step);
      kbcPagePrev: moved := TyDzInsideMove(r, -page);
      kbcPageNext: moved := TyDzInsideMove(r, page);
      kbcFirst: moved := TyDzInsideMove(r, -200);
      kbcLast: moved := TyDzInsideMove(r, 200);
      kbcShrink, kbcGrow:
        if not FDzInteract[AIndex].ZoomLock and (FBuild <> nil) then
        begin
          { the dataZoom's first target axis, and its grid }
          axis := nil;
          g := -1;
          for t := 0 to High(FZoomSpecs[AIndex].Targets) do
          begin
            ax := DzAxis(FZoomSpecs[AIndex].Targets[t].Dim, FZoomSpecs[AIndex].Targets[t].AxisIndex);
            if ax = nil then Continue;
            for gi := 0 to FBuild.GridCount - 1 do
              if FBuild.Grid(gi).ComponentIndex = ax.GridIndex then
              begin
                axis := ax;
                g := gi;
                Break;
              end;
            if axis <> nil then Break;
          end;
          if axis <> nil then
          begin
            gr := DzGridRect(g);
            dir := TyDzDirectionInfo(axis.Dim = 'x', axis.Inverse, gr, 0, 0,
              gr.X + gr.W / 2, gr.Y + gr.H / 2);
            DzSpans(AIndex, mn, mx);
            if ACmd = kbcShrink then sc := TyDzWheelScale(1) else sc := TyDzWheelScale(-1);
            moved := TyDzInsideZoom(r, dir, sc, mn, mx);
          end;
        end;
      { [R2-G] Shift+Home / Shift+End: the window's start out to the
        data's start, its end out to the data's end -- the slider's handle
        drags, through the same sliderMove and its span limits; nothing
        under zoomLock }
      kbcGrowStart, kbcGrowEnd:
        if not FDzInteract[AIndex].ZoomLock then
        begin
          DzSpans(AIndex, mn, mx);
          if ACmd = kbcGrowStart then TyDzSliderMove(-200, r, 0, 100, 0, mn, mx)
          else TyDzSliderMove(200, r, 0, 100, 1, mn, mx);
          moved := (r[0] <> FDzInLo[AIndex]) or (r[1] <> FDzInHi[AIndex]);
        end;
    end;
    if moved then
    begin
      FDzInLo[AIndex] := r[0];
      FDzInHi[AIndex] := r[1];
      a := Default(TTyDzAction);
      a.Batch := True;
      a.FromSlider := -1;
      SetLength(a.Items, 1);
      a.Items[0].DataZoomIndex := AIndex;
      a.Items[0].Start := r[0];
      a.Items[0].Stop := r[1];
      DzDispatch(a);
    end;
  end;
  if DzStateKey <> key then DzViewUpdate;
end;

procedure TTyAdvanceChart.KbVisualMapKey(AIndex, AHandle: Integer; ACmd: TTyKbCommand);
var i1, d, sgn: Double;
begin
  if not KbVmHandles(AIndex) then Exit;
  i1 := FVisualLayouts[AIndex].ItemH;
  { right and up raise the value: the bar's own direction is the
    extent's }
  if FVisualSpecs[AIndex].Extent1 >= FVisualSpecs[AIndex].Extent0 then sgn := 1 else sgn := -1;
  case ACmd of
    kbcNext, kbcPrevSeries: d := i1 / cTyKbVmStep;
    kbcPrev, kbcNextSeries: d := -i1 / cTyKbVmStep;
    kbcPageNext: d := i1 / cTyKbVmPage;
    kbcPagePrev: d := -i1 / cTyKbVmPage;
    kbcLast: d := 2 * i1;
    kbcFirst: d := -2 * i1;
  else
    Exit;
  end;
  { a whole drag: the move, then the release }
  VmDragHandleBar(AIndex, AHandle, False, sgn * d);
  VmDragHandleBar(AIndex, AHandle, True, 0);
end;

procedure TTyAdvanceChart.KbTimelineKey(ACmd: TTyKbCommand);
var cur, target: Double; n, step: Integer;
begin
  if FTlView = nil then Exit;
  cur := TlCurrentIndex;
  n := FTlView.Count;
  case ACmd of
    { the prev and next buttons' own clicks }
    kbcPrev, kbcPrevSeries:
      if FTlView.Inverse then TlChange(cur + 1, True) else TlChange(cur - 1, True);
    kbcNext, kbcNextSeries:
      if FTlView.Inverse then TlChange(cur - 1, True) else TlChange(cur + 1, True);
    { a tick's click: Home the first tick on the axis, End the last --
      an inverse timeline's first is its last item [R2-G] }
    kbcFirst:
      if FTlView.Inverse then TlChange(n - 1, True) else TlChange(0, True);
    kbcLast:
      if FTlView.Inverse then TlChange(0, True) else TlChange(n - 1, True);
    kbcPagePrev, kbcPageNext:
      begin
        step := TyKbPageStep(n);
        if IsNan(cur) then cur := 0;
        { the way the arrows go: an inverse timeline's back is up the
          items [R2-G] }
        if (ACmd = kbcPagePrev) <> FTlView.Inverse then target := cur - step
        else target := cur + step;
        if target < 0 then target := 0;
        if target > n - 1 then target := n - 1;
        TlChange(target, True);
      end;
  end;
end;

function TTyAdvanceChart.KbComponentKey(AKey: Word; AShift: TShiftState): Boolean;
var
  cmd: TTyKbCommand;
  i, n, p, k, firstVis, pages: Integer;
  multi: Boolean;
  t: TTyChartEventTarget;
  regs, pcs: TTyIntegerArray;
  mSer, mKind, mIdx, mEls: TTyIntegerArray;
  node: TJSONData;
begin
  Result := False;
  cmd := TyKbComponentCommandOf(AKey, AShift);
  if cmd = kbcNone then Exit;
  i := FKbStop.Index;
  { ESCAPE: the brush's clear button; elsewhere it lets the part go and
    forgets it -- the form's when nothing is held }
  if cmd = kbcClear then
  begin
    if FKbStop.Kind = ksBrush then
    begin
      if (i <= High(FBrushCtls)) and (FBrushCtls[i] <> nil)
        and (Length(FBrushCtls[i].Covers) > 0) then
      begin
        TbBrushClick('clear');
        Result := True;
      end;
      Exit;
    end;
    if not FKbStopOn then Exit;
    KbStopLeave;
    FKbPart := -1;
    Exit(True);
  end;
  multi := (FKbStop.Kind in [ksMarkers, ksGeo, ksLegend, ksToolbox])
    or ((FKbStop.Kind = ksVisualMap) and (i <= High(FVisualLayouts))
      and FVisualLayouts[i].Piecewise);
  { NOT TAKEN UP (after an exit, or Escape): a stop of parts takes its
    part up on the first moving key, and only that; a stop of one part is
    taken up and the key acts }
  if not FKbStopOn then
  begin
    if multi then
    begin
      if not TyKbIsComponentMove(cmd) then Exit;
      if FKbPart >= 0 then
      begin
        KbStopTake(FKbPart);
        Exit(True);
      end;
    end
    else
      KbStopTake(0);
  end;
  if multi then
  begin
    n := KbPartCount(FKbStop);
    if TyKbIsComponentMove(cmd) then
    begin
      Result := True;
      { A SCROLL LEGEND'S PAGE KEYS are its pager's buttons }
      if (FKbStop.Kind = ksLegend) and (cmd in [kbcPagePrev, kbcPageNext])
        and (i <= High(FLegends)) and FLegends[i].IsScroll and FLegends[i].ShowController then
      begin
        t := KbLegendTarget(i, 0);
        t.HdKind := 6;
        if cmd = kbcPagePrev then t.HdRow := 0 else t.HdRow := 1;
        LegendPagerClick(t);
        ConvertReady;
        p := FKbPart;
        if (p < 0) or (p >= Length(FLegends[i].Items)) or not KbLegendVisible(i, p) then
          for k := 0 to High(FLegends[i].Items) do
            if KbLegendVisible(i, k) then
            begin
              p := k;
              Break;
            end;
        KbStopTake(p);
        Exit;
      end;
      if FKbStopOn then p := FKbPart else p := -1;
      if not TyKbPartMove(n, cmd, p) then Exit;
      { an item off a scroll legend's page: the pager toward it first, a
        page at a time until it shows (End from the first page) }
      if (FKbStop.Kind = ksLegend) and (p < Length(FLegends[i].Items)) then
      begin
        pages := 0;
        while (i <= High(FLegends)) and FLegends[i].ShowController
          and not KbLegendVisible(i, p) and (pages <= Length(FLegends[i].Items)) do
        begin
          firstVis := -1;
          for k := 0 to High(FLegends[i].Items) do
            if (firstVis < 0) and KbLegendVisible(i, k) then firstVis := k;
          t := KbLegendTarget(i, 0);
          t.HdKind := 6;
          if (firstVis >= 0) and (p < firstVis) then t.HdRow := 0 else t.HdRow := 1;
          { _pageGo: nothing where that page is none }
          if (t.HdRow = 0) and (FLegends[i].PagePrevIndex < 0) then Break;
          if (t.HdRow = 1) and (FLegends[i].PageNextIndex < 0) then Break;
          LegendPagerClick(t);
          ConvertReady;
          Inc(pages);
        end;
      end;
      KbStopTake(p);
      Exit;
    end;
    if (cmd <> kbcActivate) or (FKbPart < 0) or (FKbPart >= n) then Exit;
    case FKbStop.Kind of
      ksLegend:
        begin
          t := KbLegendTarget(i, FKbPart);
          if t.HdKind = 4 then
          begin
            { a legend that selects nothing leaves the key to the form }
            if (i <= High(FLegendSpecs)) and (FLegendSpecs[i].SelectedMode = tlsOff) then Exit;
            LegendClick(t);
          end
          else if t.HdKind = 5 then
            LegendSelectorClick(t)
          else
            Exit;
          Result := True;
        end;
      ksToolbox:
        begin
          TbClick(i, FKbPart);
          Result := True;
        end;
      ksGeo:
        begin
          node := FOption.ComponentAt('geo', i);
          if not ((node is TJSONObject) and JsTruthy(TJSONObject(node).Find('selectedMode'))) then Exit;
          regs := KbGeoRegions(i);
          t := Default(TTyChartEventTarget);
          t.Params := TyChartBlankParams;
          t.HdKind := 14;
          t.HdSeries := i;
          t.HdRow := regs[FKbPart];
          t.HdGen := FGeos[i].Gen;
          t.HdName := FGeos[i].GroupName(regs[FKbPart]);
          GeoRegionClick(t);
          Result := True;
        end;
      ksVisualMap:
        begin
          if (i > High(FVisualViews)) or FVisualViews[i].Silent then Exit;
          pcs := KbVmPieces(i);
          VmPieceClick(i, pcs[FKbPart]);
          Result := True;
        end;
      { [R2-G] A MARKER'S CLICK: its ECData names the host series and the
        marker's own data index, and echarts' click handler dispatches
        select for that item of the host -- when the host selects at all
        (else the key is the form's, as on a data item) }
      ksMarkers:
        begin
          if KbMarkerList(mSer, mKind, mIdx, mEls) <= FKbPart then Exit;
          k := SlotOfSeries(mSer[FKbPart]);
          if k < 0 then Exit;
          SelEnsure(k);
          if (mSer[FKbPart] > High(FSel)) or not FSelInit[mSer[FKbPart]]
            or (FSel[mSer[FKbPart]].Mode = ssmOff) then Exit;
          t := Default(TTyChartEventTarget);
          t.Params := TyChartBlankParams;
          t.HdKind := 3;
          t.HdSeries := mSer[FKbPart];
          t.HdRow := mIdx[FKbPart];
          StClickSelect(t);
          Result := True;
        end;
    end;
    Exit;
  end;
  case FKbStop.Kind of
    ksVisualMap:
      if TyKbIsComponentMove(cmd) then
      begin
        KbVisualMapKey(i, FKbStop.Sub, cmd);
        Result := True;
      end;
    ksDataZoom:
      if TyKbIsComponentMove(cmd) then
      begin
        KbDataZoomKey(i, cmd);
        Result := True;
      end;
    ksTimeline:
      if TyKbIsComponentMove(cmd) then
      begin
        KbTimelineKey(cmd);
        Result := True;
      end
      else if (cmd = kbcActivate) and (AKey = VK_SPACE) and (FTlView <> nil) then
      begin
        { the play button's click (_handlePlayClick): the timer cleared }
        FTlDue := NaN;
        TlArmTimer;
        if FTlView.PlayState then
          DispatchAction('{"type":"timelinePlayChange","playState":false,"from":"' + FTlView.Uid + '"}')
        else
          DispatchAction('{"type":"timelinePlayChange","playState":true,"from":"' + FTlView.Uid + '"}');
        Result := True;
      end;
    ksBrush:
      { drawing is the pointer's: the moving keys only stay in the chart }
      Result := TyKbIsComponentMove(cmd);
  end;
  KbNotifyFocus;
  InvalidateFrame;
end;

function TTyAdvanceChart.KbPartRect(const AStop: TTyKbStop; APart: Integer;
  out R: TTyRectF): Boolean;
var
  s, kd, ix, els, regs, pcs: TTyIntegerArray;
  n, i, j, h, q: Integer;
  el: TTyChartElement;
  L: TTyVisualMapLayout;
  it: TTyVmItem;
  gx, gy, sc, ox, oy, x0, y0, x1, y1: Double;
  e: TTyDzElement;
  rr: TTyXYWH;
  b: TTyRectF;
  v: TTyBrushView;
  c: TTyBrushCover;
  ctx: TTyGfxPaintCtx;
  pe: TTyChartElement;
  meas: ITyTextMeasurer;
begin
  Result := False;
  R := TyRectF(0, 0, 0, 0);
  i := AStop.Index;
  case AStop.Kind of
    ksMarkers:
      begin
        n := KbMarkerList(s, kd, ix, els);
        if (APart < 0) or (APart >= n) then Exit;
        R := TyShapeBounds(KbList.Element(els[APart]).Shape);
        Result := True;
      end;
    ksGeo:
      begin
        regs := KbGeoRegions(i);
        if (APart < 0) or (APart > High(regs)) or (FPaintList = nil) or not FPaintListValid then Exit;
        for j := 0 to FPaintList.Count - 1 do
        begin
          el := FPaintList.Element(j);
          if (el.Datum.Kind <> ctkGeo) or (el.Datum.ComponentIndex <> i)
            or (el.Datum.DataIndex <> regs[APart]) or el.Ignore or (el.Caption.Text <> '') then Continue;
          KbUnion(Result, R, TyShapeBounds(KbList.Element(j).Shape));
        end;
      end;
    ksLegend:
      begin
        if (i < 0) or (i > High(FLegends)) or (APart < 0) then Exit;
        n := Length(FLegends[i].Items);
        if APart < n then R := FLegends[i].Items[APart].Bounds
        else if APart - n <= High(FLegends[i].Selector) then R := FLegends[i].Selector[APart - n].Box
        else Exit;
        Result := True;
      end;
    ksVisualMap:
      begin
        if (i < 0) or (i > High(FVisualLayouts)) then Exit;
        L := FVisualLayouts[i];
        gx := VmGroupX(i);
        gy := VmGroupY(i);
        if L.Piecewise then
        begin
          pcs := KbVmPieces(i);
          if (APart < 0) or (APart > High(pcs)) then Exit;
          for j := 0 to High(L.Items) do
          begin
            it := L.Items[j];
            if it.IsText or (it.PieceIndex <> pcs[APart]) then Continue;
            R := TyRectF(gx + it.X + it.Rect.X, gy + it.Y + it.Rect.Y,
              gx + it.X + it.Rect.X + it.Rect.W, gy + it.Y + it.Rect.Y + it.Rect.H);
            Exit(True);
          end;
        end
        else if KbVmHandles(i) then
        begin
          h := AStop.Sub;
          b := KbXformRect(L.Handles[h].Thumb, L.Handles[h].PathRect);
          R := TyRectF(gx + b.Left, gy + b.Top, gx + b.Right, gy + b.Bottom);
          Result := True;
        end;
      end;
    ksDataZoom:
      begin
        sc := DzScale;
        if KbIsSlider(i) then
        begin
          e := FDzLayouts[i].Kids[dzrFiller];
          if not e.Present then Exit;
          b := KbXformRect(TyDzGlobal(FDzLayouts[i], dzrFiller), e.Shape);
        end
        else if KbIsInside(i) and (FBuild <> nil) then
        begin
          b := TyRectF(NaN, NaN, NaN, NaN);
          for j := 0 to High(FZoomSpecs[i].Targets) do
          begin
            if DzAxis(FZoomSpecs[i].Targets[j].Dim, FZoomSpecs[i].Targets[j].AxisIndex) = nil then Continue;
            for q := 0 to FBuild.GridCount - 1 do
              if FBuild.Grid(q).ComponentIndex
                = DzAxis(FZoomSpecs[i].Targets[j].Dim, FZoomSpecs[i].Targets[j].AxisIndex).GridIndex then
              begin
                rr := DzGridRect(q);
                b := TyRectF(rr.X, rr.Y, rr.X + rr.W, rr.Y + rr.H);
                Break;
              end;
            if not IsNan(b.Left) then Break;
          end;
          if IsNan(b.Left) then Exit;
        end
        else
          Exit;
        R := TyRectF(b.Left * sc + FLastRect.Left, b.Top * sc + FLastRect.Top,
          b.Right * sc + FLastRect.Left, b.Bottom * sc + FLastRect.Top);
        Result := True;
      end;
    ksTimeline:
      begin
        if (FTlView = nil) or not FTlView.Shown or (FTlView.Checkpoint = nil) then Exit;
        FTlView.UpdateTransforms;
        meas := NewTextMeasurer(96);
        ctx := Default(TTyGfxPaintCtx);
        if FLastPPI > 0 then ctx.Scale := FLastPPI / 96 else ctx.Scale := 1;
        ctx.HasInk := False;
        for j := 0 to High(FTlView.Els) do
          if (FTlView.Els[j] = FTlView.Checkpoint) and not FTlView.Els[j].Ignore
            and FTlView.Drawable(j, meas) and TyGfxPaintElement(FTlView.Els[j], meas, ctx, pe) then
          begin
            R := TyShapeBounds(pe.Shape);
            Exit(True);
          end;
      end;
    ksToolbox:
      begin
        if (i < 0) or (i > High(FTbSpecs)) or (APart < 0) or (APart > High(FTbSpecs[i].Icons)) then Exit;
        rr := TyToolboxIconRect(FTbSpecs[i], FTbSpecs[i].Icons[APart], TbEmphasised(i, APart));
        TbIconOrigin(i, APart, ox, oy);
        if IsNan(rr.X) or IsNan(rr.Y) or IsNan(ox) or IsNan(oy) then Exit;
        sc := TbScale;
        R := TyRectF((ox + rr.X) * sc + FLastRect.Left, (oy + rr.Y) * sc + FLastRect.Top,
          (ox + rr.X + rr.W) * sc + FLastRect.Left, (oy + rr.Y + rr.H) * sc + FLastRect.Top);
        Result := True;
      end;
    ksBrush:
      begin
        if (i < 0) or (i > High(FBrushCtls)) or (FBrushCtls[i] = nil) then Exit;
        v := BrushViewOf;
        for j := 0 to High(FBrushCtls[i].Covers) do
        begin
          c := FBrushCtls[i].Covers[j];
          if Length(c.Points) > 0 then
          begin
            x0 := c.Points[0].X;
            y0 := c.Points[0].Y;
            x1 := x0;
            y1 := y0;
            for q := 1 to High(c.Points) do
            begin
              if c.Points[q].X < x0 then x0 := c.Points[q].X;
              if c.Points[q].X > x1 then x1 := c.Points[q].X;
              if c.Points[q].Y < y0 then y0 := c.Points[q].Y;
              if c.Points[q].Y > y1 then y1 := c.Points[q].Y;
            end;
          end
          else
          begin
            x0 := Math.Min(c.Main.X, c.Main.X + c.Main.W);
            x1 := Math.Max(c.Main.X, c.Main.X + c.Main.W);
            y0 := Math.Min(c.Main.Y, c.Main.Y + c.Main.H);
            y1 := Math.Max(c.Main.Y, c.Main.Y + c.Main.H);
          end;
          KbUnion(Result, R, TyRectF(x0 * v.S + v.OX, y0 * v.S + v.OY,
            x1 * v.S + v.OX, y1 * v.S + v.OY));
        end;
      end;
  end;
end;

{ ---- the accessible tree's components ---- }

function TTyAdvanceChart.AccValueOf(const AStop: TTyKbStop; APart: Integer): string;
var
  i, cur, n: Integer;
  lo, hi: Double;
  st: TTyDzSliderState;

  function Pct(A: Double): string;
  begin
    Result := TyChartValueText(Round(A * 100) / 100);
  end;

begin
  Result := '';
  i := AStop.Index;
  case AStop.Kind of
    ksDataZoom:
      begin
        if KbIsSlider(i) then
        begin
          st := FDzState[i];
          lo := st.Range[0];
          hi := st.Range[1];
        end
        else if KbIsInside(i) then
        begin
          lo := FDzInLo[i];
          hi := FDzInHi[i];
        end
        else
          Exit;
        Result := Format(rsTyChartAccPercentRange, [Pct(lo), Pct(hi)]);
      end;
    ksTimeline:
      if (FTlView <> nil) and not IsNan(TlCurrentIndex) then
      begin
        cur := Trunc(TlCurrentIndex);
        if (cur >= 0) and (cur <= High(FTlView.Names)) and (FTlView.Names[cur] <> '') then
          Result := FTlView.Names[cur]
        else
          Result := IntToStr(cur);
      end;
    ksVisualMap:
      if KbVmHandles(i) and FVmLive[i].Alive then
        Result := TyChartValueText(FVmLive[i].Interval[AStop.Sub]);
    ksBrush:
      if (i <= High(FBrushCtls)) and (FBrushCtls[i] <> nil) then
      begin
        n := Length(FBrushCtls[i].Covers);
        Result := Format(rsTyChartAccBrushAreas, [n]);
      end;
  end;
end;

{ the component nodes' values, every sync: a window, a time, a handle's
  value or a brush's areas change without a new layout's tree }
procedure TTyAdvanceChart.AccRefreshValues;
var k: Integer;
begin
  for k := 0 to High(FAccCompObjs) do
    if FAccCompParts[k] >= 0 then
      FAccCompObjs[k].AccessibleValue := AccValueOf(FAccCompStops[k], FAccCompParts[k]);
end;

function TTyAdvanceChart.AccCompIndexOf(AObj: TLazAccessibleObject): Integer;
var k: Integer;
begin
  for k := 0 to High(FAccCompObjs) do
    if FAccCompObjs[k] = AObj then Exit(k);
  Result := -1;
end;

{ [F5] a graph edge's words: its data name (the link's name), else the two
  node names as upstream's edge name is made, 'source > target' }
function TTyAdvanceChart.KbEdgeName(ASlot, AEdge: Integer): string;
var e: TTyGraphEdge;
begin
  Result := '';
  { [R2-G] a sankey's link and a chord's ribbon: the edge data's name -- its
    id, else 'source > target' }
  case KbEdgeKind(ASlot) of
    2:
      begin
        if (AEdge < 0) or (AEdge > High(FSankeys[ASlot].Edges)) then Exit;
        Exit(FSankeys[ASlot].Edges[AEdge].DataName);
      end;
    3:
      begin
        if (AEdge < 0) or (AEdge > High(FChords[ASlot].Edges)) then Exit;
        Exit(FChords[ASlot].Edges[AEdge].Name);
      end;
  end;
  if (ASlot < 0) or (ASlot > High(FGraphEdges)) or (AEdge < 0)
    or (AEdge > High(FGraphEdges[ASlot])) then Exit;
  e := FGraphEdges[ASlot][AEdge];
  if e.Name_ <> '' then Exit(e.Name_);
  if (e.Source >= 0) and (e.Source <= High(FGraphNodes[ASlot]))
    and (e.Target >= 0) and (e.Target <= High(FGraphNodes[ASlot])) then
    Result := FGraphNodes[ASlot][e.Source].Name_ + ' > ' + FGraphNodes[ASlot][e.Target].Name_;
end;

{ [F5] a marker's words: its kind, and a mark point's name or value when it
  has one, else its place }
function TTyAdvanceChart.KbMarkerName(ASeries, AKind, AIndex: Integer): string;
var
  m, q: Integer;
  kind: TTyMarkerKind;
  mk: TTyMkBlock;
  nm: string;
begin
  case TTyChartTargetKind(AKind) of
    ctkMarkPoint:
      begin
        Result := rsTyChartAccMarkPoint;
        kind := mkPoint;
      end;
    ctkMarkLine:
      begin
        Result := rsTyChartAccMarkLine;
        kind := mkLine;
      end;
  else
    Result := rsTyChartAccMarkArea;
    kind := mkArea;
  end;
  nm := '';
  if kind = mkPoint then
    for m := 0 to High(FMarkers) do
      if FMarkers[m].SeriesIndex = ASeries then
      begin
        mk := FMarkers[m].Blocks[kind];
        for q := 0 to High(mk.Points) do
          if mk.Points[q].DataIndex = AIndex then
          begin
            if mk.Points[q].E.Name.Kind = mvkStr then nm := mk.Points[q].E.Name.Str
            else if mk.Points[q].E.Name.Kind = mvkNum then nm := TyChartValueText(mk.Points[q].E.Name.Num);
            if (nm = '') and (mk.Points[q].E.Value.Kind = mvkNum) then
              nm := TyChartValueText(mk.Points[q].E.Value.Num)
            else if (nm = '') and (mk.Points[q].E.Value.Kind = mvkStr) then
              nm := mk.Points[q].E.Value.Str;
          end;
        Break;
      end;
  if nm <> '' then Result := Result + ': ' + nm
  else Result := Result + ' ' + IntToStr(AIndex + 1);
end;

{ [F5] the component part of the accessible tree: the stops in Tab order,
  each a node (a list, a group or a toolbar of its parts, or a slider of
  its own) }
function TTyAdvanceChart.AccPlan: TTyAccPlan;
var
  stops: TTyKbStopArray;
  k, j, n, tp: Integer;
  st: TTyKbStop;
  s, kd, ix, els, regs, pcs: TTyIntegerArray;
  node: TJSONData;
  nm: string;
  L: TTyVisualMapLayout;
  buf: TTyAccPlan;

  function Add(ARole: TLazAccessibilityRole; const AName: string;
    const AStop: TTyKbStop; APart, AParent: Integer): Integer;
  begin
    Result := Length(buf);
    SetLength(buf, Result + 1);
    buf[Result].Role := ARole;
    buf[Result].Name := AName;
    buf[Result].Stop := AStop;
    buf[Result].Part := APart;
    buf[Result].Parent := AParent;
  end;

begin
  buf := nil;
  stops := KbStops;
  for k := 0 to High(stops) do
  begin
    st := stops[k];
    case st.Kind of
      ksMarkers:
        begin
          tp := Add(larListBox, rsTyChartAccMarkers, st, -1, -1);
          n := KbMarkerList(s, kd, ix, els);
          for j := 0 to n - 1 do
            Add(larListItem, KbMarkerName(s[j], kd[j], ix[j]), st, j, tp);
        end;
      ksGeo:
        begin
          nm := '';
          node := FOption.ComponentAt('geo', st.Index);
          if node is TJSONObject then nm := TJSONObject(node).Get('map', '');
          if nm = '' then nm := rsTyChartTypeMap;
          tp := Add(larListBox, nm, st, -1, -1);
          regs := KbGeoRegions(st.Index);
          for j := 0 to High(regs) do
            Add(larListItem, FGeos[st.Index].GroupName(regs[j]), st, j, tp);
        end;
      ksLegend:
        begin
          tp := Add(larGroup, rsTyChartAccLegend, st, -1, -1);
          for j := 0 to High(FLegends[st.Index].Items) do
            Add(larCheckBox, FLegends[st.Index].Items[j].Name, st, j, tp);
          n := Length(FLegends[st.Index].Items);
          for j := 0 to High(FLegends[st.Index].Selector) do
            Add(larButton, FLegends[st.Index].Selector[j].Title, st, n + j, tp);
        end;
      ksVisualMap:
        begin
          L := FVisualLayouts[st.Index];
          if L.Piecewise then
          begin
            tp := Add(larGroup, rsTyChartAccVisualMap, st, -1, -1);
            pcs := KbVmPieces(st.Index);
            for j := 0 to High(pcs) do
            begin
              nm := '';
              if (st.Index <= High(FVisualSpecs)) and (pcs[j] >= 0)
                and (pcs[j] <= High(FVisualSpecs[st.Index].Pieces)) then
              begin
                nm := FVisualSpecs[st.Index].Pieces[pcs[j]].Text;
                if nm = '' then nm := FVisualSpecs[st.Index].Pieces[pcs[j]].Key;
              end;
              Add(larCheckBox, nm, st, j, tp);
            end;
          end
          else if st.Sub = 0 then
          begin
            { the two handles' stops under one node }
            tp := Add(larGroup, rsTyChartAccVisualMap, st, -1, -1);
            Add(larTrackBar, rsTyChartAccHandleStart, st, 0, tp);
            Add(larTrackBar, rsTyChartAccHandleEnd, TyKbStop(ksVisualMap, st.Index, 1), 0, tp);
          end;
        end;
      ksDataZoom: Add(larTrackBar, rsTyChartAccDataZoom, st, 0, -1);
      ksTimeline: Add(larTrackBar, rsTyChartAccTimeline, st, 0, -1);
      ksToolbox:
        begin
          tp := Add(larToolBar, rsTyChartAccToolbox, st, -1, -1);
          for j := 0 to High(FTbSpecs[st.Index].Icons) do
          begin
            nm := FTbSpecs[st.Index].Icons[j].Title;
            if not FTbSpecs[st.Index].Icons[j].HasTitle or (nm = '') then
              nm := FTbSpecs[st.Index].Icons[j].Name;
            Add(larToolBarButton, nm, st, j, tp);
          end;
        end;
      ksBrush: Add(larGroup, rsTyChartAccBrush, st, 0, -1);
    end;
  end;
  Result := buf;
end;

procedure TTyAdvanceChart.AccessibleSync;
var
  root, obj: TLazAccessibleObject;
  aria, d: TJSONData;
  facts: TTyAriaFacts;
  loc: TTyAriaLocale;
  sObjs, iObjs, kObjs: TTyAccObjectArray;
  i, j, n, cnt, idx, slot, ec, e, nTop, t, k, q, nk: Integer;
  b, u, ku: TTyRectF;
  has, khas: Boolean;
  nm: string;
  plan: TTyAccPlan;

  procedure Place(AObj: TLazAccessibleObject; const R: TTyRectF);
  begin
    if not KbRectFinite(R) then Exit;
    AObj.Position := Point(Floor(R.Left), Floor(R.Top));
    AObj.Size := Types.Size(Ceil(R.Right) - Floor(R.Left), Ceil(R.Bottom) - Floor(R.Top));
  end;

  procedure AddItem(AObj: TLazAccessibleObject; ASeries, ARow: Integer; AEdge: Boolean);
  var m: Integer;
  begin
    m := Length(FAccItemObjs);
    SetLength(FAccItemObjs, m + 1);
    SetLength(FAccItemSeries, m + 1);
    SetLength(FAccItemRows, m + 1);
    SetLength(FAccItemEdge, m + 1);
    FAccItemObjs[m] := AObj;
    FAccItemSeries[m] := ASeries;
    FAccItemRows[m] := ARow;
    FAccItemEdge[m] := AEdge;
  end;

  procedure AddComp(AObj: TLazAccessibleObject; const AStop: TTyKbStop; APart: Integer);
  var m: Integer;
  begin
    m := Length(FAccCompObjs);
    SetLength(FAccCompObjs, m + 1);
    SetLength(FAccCompStops, m + 1);
    SetLength(FAccCompParts, m + 1);
    FAccCompObjs[m] := AObj;
    FAccCompStops[m] := AStop;
    FAccCompParts[m] := APart;
  end;

begin
  if FAccSyncing or (FOption = nil) then Exit;
  FAccSyncing := True;
  try
    { a layout that is due is made first: the tree describes it }
    ConvertReady;
    if FAccGen = FStGen then
    begin
      { [F5] the same tree: only the components' values move }
      AccRefreshValues;
      Exit;
    end;
    FAccGen := FStGen;
    root := GetAccessibleObject;
    if root = nil then Exit;
    root.AccessibleRole := larChart;
    { the name: the first title, as getTitle reads it; else the word }
    nm := rsTyChartTypeChart;
    d := FOption.ComponentAt('title', 0);
    if d is TJSONObject then
    begin
      d := TJSONObject(d).Find('text');
      if TyDecalTruthy(d) then nm := TyJsonJsString(d);
    end;
    root.AccessibleName := nm;
    root.AccessibleDescription := AccessibleSummary;
    root.ClearChildAccessibleObjects;
    FAccItemObjs := nil;
    FAccItemSeries := nil;
    FAccItemRows := nil;
    FAccItemEdge := nil;
    FAccCompObjs := nil;
    FAccCompStops := nil;
    FAccCompParts := nil;
    { the phrases: the option's aria templates, when it writes aria }
    aria := nil;
    if FOption.Root is TJSONObject then aria := TJSONObject(FOption.Root).Find('aria');
    if not (aria is TJSONObject) then aria := nil;
    AriaGather(TJSONObject(aria), facts);
    loc := TyAriaLocaleOf(TJSONObject(aria), TyAriaDefaultLocale);
    { [F5] the components after the series, made with them: the AVL order
      is the order of one batch's addresses }
    plan := AccPlan;
    nTop := 0;
    for k := 0 to High(plan) do
      if plan[k].Parent < 0 then Inc(nTop);
    FAccSeriesCount := Length(facts.Series);
    sObjs := TyAccAddChildren(root, Length(facts.Series) + nTop);
    for i := 0 to High(facts.Series) do
    begin
      sObjs[i].AccessibleRole := larListBox;
      sObjs[i].AccessibleName := Trim(TyAriaSeriesPhrase(loc, facts, i));
      cnt := Length(facts.Series[i].Rows);
      if cnt > cTyAccMaxItems then cnt := cTyAccMaxItems;
      { [F5] a graph's edges after its nodes, in the same list }
      slot := SlotOfSeries(facts.Series[i].Index);
      ec := 0;
      if KbEdgeKind(slot) > 0 then
        ec := KbEdgeCount(slot);
      if cnt + ec > cTyAccMaxItems then ec := cTyAccMaxItems - cnt;
      iObjs := TyAccAddChildren(sObjs[i], cnt + ec);
      has := False;
      u := TyRectF(0, 0, 0, 0);
      for j := 0 to cnt + ec - 1 do
      begin
        if j < cnt then
        begin
          iObjs[j].AccessibleRole := larListItem;
          iObjs[j].AccessibleName := TyAriaRowPhrase(loc, facts.Series[i].Rows[j]);
          idx := KbElementOf(facts.Series[i].Index, j);
          AddItem(iObjs[j], facts.Series[i].Index, j, False);
        end
        else
        begin
          iObjs[j].AccessibleRole := larListItem;
          e := KbEdgeOf(facts.Series[i].Index, j - cnt);
          iObjs[j].AccessibleName := KbEdgeName(slot, e);
          idx := KbElementOf(facts.Series[i].Index, j - cnt, True);
          AddItem(iObjs[j], facts.Series[i].Index, j - cnt, True);
        end;
        if idx >= 0 then
        begin
          b := TyShapeBounds(FPaintList.Element(idx).Shape);
          Place(iObjs[j], b);
          KbUnion(has, u, b);
        end;
      end;
      if has then Place(sObjs[i], u);
    end;
    { [F5] the components }
    t := Length(facts.Series);
    for k := 0 to High(plan) do
    begin
      if plan[k].Parent >= 0 then Continue;
      obj := sObjs[t];
      Inc(t);
      obj.AccessibleRole := plan[k].Role;
      obj.AccessibleName := plan[k].Name;
      AddComp(obj, plan[k].Stop, plan[k].Part);
      if plan[k].Part >= 0 then
      begin
        obj.AccessibleValue := AccValueOf(plan[k].Stop, plan[k].Part);
        if KbPartRect(plan[k].Stop, plan[k].Part, b) then Place(obj, b);
        Continue;
      end;
      nk := 0;
      for q := k + 1 to High(plan) do
        if plan[q].Parent = k then Inc(nk);
      kObjs := TyAccAddChildren(obj, nk);
      n := 0;
      khas := False;
      ku := TyRectF(0, 0, 0, 0);
      for q := k + 1 to High(plan) do
      begin
        if plan[q].Parent <> k then Continue;
        kObjs[n].AccessibleRole := plan[q].Role;
        kObjs[n].AccessibleName := plan[q].Name;
        kObjs[n].AccessibleValue := AccValueOf(plan[q].Stop, plan[q].Part);
        AddComp(kObjs[n], plan[q].Stop, plan[q].Part);
        if KbPartRect(plan[q].Stop, plan[q].Part, b) then
        begin
          Place(kObjs[n], b);
          KbUnion(khas, ku, b);
        end;
        Inc(n);
      end;
      if khas then Place(obj, ku);
    end;
  finally
    FAccSyncing := False;
  end;
  if (FAccLink <> nil) and FAccLink.InUse then FAccLink.NotifyReorder;
end;

function TTyAdvanceChart.AccessibleItem(ASeriesIndex, ARow: Integer): TLazAccessibleObject;
var i: Integer;
begin
  Result := nil;
  for i := 0 to High(FAccItemObjs) do
    if (FAccItemSeries[i] = ASeriesIndex) and (FAccItemRows[i] = ARow) and not FAccItemEdge[i] then
      Exit(FAccItemObjs[i]);
end;

function TTyAdvanceChart.AccessibleEdgeItem(ASeriesIndex, ARow: Integer): TLazAccessibleObject;
var i: Integer;
begin
  Result := nil;
  for i := 0 to High(FAccItemObjs) do
    if (FAccItemSeries[i] = ASeriesIndex) and (FAccItemRows[i] = ARow) and FAccItemEdge[i] then
      Exit(FAccItemObjs[i]);
end;

function TTyAdvanceChart.AccessibleFocusedChild: TLazAccessibleObject;
var k: Integer;
begin
  Result := nil;
  if FKbStopOn then
  begin
    for k := 0 to High(FAccCompObjs) do
      if TyKbSameStop(FAccCompStops[k], FKbStop) and (FAccCompParts[k] = FKbPart) then
        Exit(FAccCompObjs[k]);
    Exit;
  end;
  if FKbActive and KbValid then
    if FKbEdge then Result := AccessibleEdgeItem(FKbSeries, FKbRow)
    else Result := AccessibleItem(FKbSeries, FKbRow);
end;

function TTyAdvanceChart.AccessibleSelected(AObj: TLazAccessibleObject): Boolean;
var
  i, k, s, slot, part, inner: Integer;
  st: TTyKbStop;
  pcs, regs: TTyIntegerArray;
  map: TJSONObject;
begin
  Result := False;
  k := AccCompIndexOf(AObj);
  if k >= 0 then
  begin
    st := FAccCompStops[k];
    part := FAccCompParts[k];
    if part < 0 then Exit;
    case st.Kind of
      ksLegend:
        if (st.Index <= High(FLegends)) and (part <= High(FLegends[st.Index].Items)) then
          Result := FLegends[st.Index].Items[part].Selected;
      ksVisualMap:
        begin
          pcs := KbVmPieces(st.Index);
          if (part <= High(pcs)) and (pcs[part] <= High(FVisualSpecs[st.Index].Pieces)) then
          begin
            map := VmSelectedMap(st.Index);
            try
              Result := JsTruthy(map.Find(FVisualSpecs[st.Index].Pieces[pcs[part]].Key));
            finally
              map.Free;
            end;
          end;
        end;
      ksGeo:
        begin
          regs := KbGeoRegions(st.Index);
          if part <= High(regs) then
            Result := GeoIsSelected(st.Index, FGeos[st.Index].GroupName(regs[part]));
        end;
    end;
    Exit;
  end;
  i := AccItemIndexOf(AObj);
  if i < 0 then Exit;
  s := FAccItemSeries[i];
  slot := SlotOfSeries(s);
  if slot < 0 then Exit;
  SelEnsure(slot);
  if (s > High(FSel)) or not FSelInit[s] then Exit;
  if FAccItemEdge[i] then
  begin
    { [F5] an edge: the edge data's own map, by its inner index; [R2-G] a
      chord's by its ribbon's index }
    inner := FAccItemRows[i];
    if KbEdgeKind(slot) = 3 then inner := KbEdgeOf(s, inner);
    Result := TySelIsSelected(FSel[s], SelEdgeData(slot), inner);
  end
  else
    Result := TySelIsSelected(FSel[s], SelData(slot), FAccItemRows[i]);
end;

function TTyAdvanceChart.AccessibleTakeFocus(AObj: TLazAccessibleObject): Boolean;
var i, k: Integer;
begin
  Result := False;
  k := AccCompIndexOf(AObj);
  if k >= 0 then
  begin
    if FAccCompParts[k] < 0 then Exit;
    KbSwitchStop(FAccCompStops[k], FAccCompParts[k]);
    Exit(FKbStopOn);
  end;
  i := AccItemIndexOf(AObj);
  if i < 0 then Exit;
  KbGo(FAccItemSeries[i], FAccItemRows[i], FAccItemEdge[i]);
  Result := FKbActive;
end;

function TTyAdvanceChart.AccessibleSeriesCount: Integer;
begin
  Result := FAccSeriesCount;
end;

function TTyAdvanceChart.AccessibleStopNode(const AStop: TTyKbStop;
  APart: Integer): TLazAccessibleObject;
var k: Integer;
begin
  Result := nil;
  for k := 0 to High(FAccCompObjs) do
    if TyKbSameStop(FAccCompStops[k], AStop) and (FAccCompParts[k] = APart) then
      Exit(FAccCompObjs[k]);
end;

{ ---- [F5] the stops, publicly ---- }

function TTyAdvanceChart.KeyboardStops: TTyKbStopArray;
begin
  Result := KbStops;
end;

function TTyAdvanceChart.KeyboardStop: TTyKbStop;
var stops: TTyKbStopArray; p: Integer;
begin
  stops := KbStops;
  p := KbCurPos(stops);
  if p >= 0 then Result := stops[p] else Result := TyKbStop(ksItems, 0, 0);
end;

function TTyAdvanceChart.KeyboardPart: Integer;
begin
  if FKbStopOn then Result := FKbPart else Result := -1;
end;

function TTyAdvanceChart.SetKeyboardStop(const AStop: TTyKbStop; APart: Integer): Boolean;
var stops: TTyKbStopArray;
begin
  Result := False;
  stops := KbStops;
  if TyKbStopPos(stops, AStop) < 0 then Exit;
  if (AStop.Kind <> ksItems) and ((APart < 0) or (APart >= KbPartCount(AStop))) then Exit;
  KbSwitchStop(AStop, APart);
  Result := True;
end;

procedure TTyAdvanceChart.DoEnter;
begin
  inherited DoEnter;
  if csDesigning in ComponentState then Exit;
  { [F5] Tab coming in starts at the first stop, Shift+Tab at the last, as
    a composite control does; a click keeps the stop the keyboard had }
  if LCLIntf.GetKeyState(VK_TAB) < 0 then KbEnter(LCLIntf.GetKeyState(VK_SHIFT) < 0);
end;

procedure TTyAdvanceChart.KbEnter(ABackward: Boolean);
var stops: TTyKbStopArray;
begin
  stops := KbStops;
  if Length(stops) = 0 then Exit;
  if FKbStopOn then KbStopLeave;
  if ABackward then FKbStop := stops[High(stops)] else FKbStop := stops[0];
  if FKbStop.Kind <> ksItems then FKbPart := -1;
end;
