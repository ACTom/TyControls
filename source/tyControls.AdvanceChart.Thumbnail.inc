{ Part of tyControls.AdvanceChart (included, not a unit): the thumbnails. Moved out of the
  unit only to keep it readable; what the control is and why it is built the way it is,
  see the unit header. }

{ ==================== the thumbnails [Batch 140] ==================== }

{ ThumbnailModel.optionUpdated -> _updateBridge: the target forgotten,
  every series' bridge cleared, then -- when it shows -- getTarget and its
  bridge injected into the target (none when there is no graph) }
procedure TTyAdvanceChart.ThumbOptionUpdated(AIndex: Integer);
var
  m: TTyThumbModel;
  d: TJSONData;
begin
  if (AIndex < 0) or (AIndex > High(FThumbs)) then Exit;
  d := FOption.ComponentAt(TyThumbnailComponent, AIndex);
  if d is TJSONObject then m := TyThumbModelOf(TJSONObject(d))
  else m := TyThumbModelOf(nil);
  FThumbs[AIndex].Model := m;
  FThumbs[AIndex].Target := -1;
  FThumbOwner := -1;
  if not m.Show then Exit;
  FThumbs[AIndex].Target := ThumbResolveTarget(m);
  if FThumbs[AIndex].Target >= 0 then FThumbOwner := AIndex;
end;

{ a new option: every thumbnail model's init and optionUpdated, in order }
procedure TTyAdvanceChart.ThumbInitAll;
var k, n: Integer;
begin
  FThumbFresh := False;
  FThumbOwner := -1;
  n := FOption.ComponentCount(TyThumbnailComponent);
  SetLength(FThumbs, n);
  for k := 0 to n - 1 do
  begin
    FThumbs[k] := Default(TTyThumbState);
    FThumbs[k].Target := -1;
  end;
  for k := 0 to n - 1 do
    if FOption.ComponentAt(TyThumbnailComponent, k) is TJSONObject then
      ThumbOptionUpdated(k);
end;

{ getTarget: the series seriesIndex names (else seriesId), which must be a
  graph; with neither, the first graph series. (A named series that is no
  graph: upstream's dev build throws on it; here there is no target.) }
function TTyAdvanceChart.ThumbResolveTarget(const AModel: TTyThumbModel): Integer;
var n, i, s: Integer;
begin
  Result := -1;
  n := FOption.ComponentCount('series');
  s := -1;
  if AModel.HasSeriesIndex then
  begin
    if (AModel.SeriesIndex >= 0) and (AModel.SeriesIndex < n)
      and (FOption.ComponentAt('series', AModel.SeriesIndex) is TJSONObject) then
      s := AModel.SeriesIndex;
  end
  else if AModel.HasSeriesId then
  begin
    for i := 0 to n - 1 do
      if (FOption.ComponentAt('series', i) is TJSONObject)
        and (ComponentModelId('series', i) = AModel.SeriesId) then
      begin
        s := i;
        Break;
      end;
  end;
  if s >= 0 then
  begin
    if FOption.ComponentSubType('series', s) = TyGraphSeriesTypeName then Result := s;
    Exit;
  end;
  for i := 0 to n - 1 do
    if (FOption.ComponentAt('series', i) is TJSONObject)
      and (FOption.ComponentSubType('series', i) = TyGraphSeriesTypeName) then
      Exit(i);
end;

function TTyAdvanceChart.ThumbTargetMatrix(ASlot: Integer): TTyMat2D;
begin
  Result := TyMatIdentity;
  if (ASlot < 0) or (ASlot > High(FGraphs)) or (FGraphs[ASlot] = nil) then Exit;
  { viewCoordSysCopyOverallMatrix: the overall transform's local matrix --
    no turn, so its off-diagonal is nought }
  Result[0] := FGraphs[ASlot].OverallScaleX;
  Result[1] := 0;
  Result[2] := 0;
  Result[3] := FGraphs[ASlot].OverallScaleY;
  Result[4] := FGraphs[ASlot].OverallX;
  Result[5] := FGraphs[ASlot].OverallY;
end;

{ GraphView._renderThumbnail: every drawn node's symbol sub-path with its
  shape at half the symbol size round the node, every edge's line path,
  their styles as the list drew them }
function TTyAdvanceChart.ThumbCopy(ASlot: Integer): TTyThumbItemArray;
var
  si, i, n, idx, row: Integer;
  nodeEl, edgeEl: array of Integer;
  el: TTyChartElement;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  spec: TTyGraphSpec;
  it: TTyThumbItem;
  symName: string;
  w, h: Double;
  ser: TJSONObject;
  ink: TTyGraphInk;
  haveInk: Boolean;
  dataArr, cats: TJSONData;
  op: Double;

  { the item model's itemStyle key: the node's own, its category's, the
    series' (getItemModel's parent chain); nil when none writes it }
  function NodeStyle(ANode: Integer; const AKey: string): TJSONData;
  var o: TJSONData;

    function KeyIn(AHost: TJSONData): TJSONData;
    var st: TJSONData;
    begin
      Result := nil;
      if not (AHost is TJSONObject) then Exit;
      st := TJSONObject(AHost).Find('itemStyle');
      if st is TJSONObject then Result := TJSONObject(st).Find(AKey);
      if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
    end;

  begin
    Result := nil;
    o := nil;
    if (dataArr is TJSONArray) and (nodes[ANode].RawRow >= 0)
      and (nodes[ANode].RawRow < dataArr.Count) then
      o := TJSONArray(dataArr).Items[nodes[ANode].RawRow];
    Result := KeyIn(o);
    if Result <> nil then Exit;
    { [R2-I4] the style's category, which categoryVisual finds by name as
      well as by index [was: the model's, by index alone] }
    if (cats is TJSONArray) and (nodes[ANode].Category >= 0)
      and (nodes[ANode].Category < cats.Count) then
      Result := KeyIn(TJSONArray(cats).Items[nodes[ANode].Category]);
    if Result <> nil then Exit;
    Result := KeyIn(ser);
  end;

  procedure StyleFrom(AIdx: Integer; var AItem: TTyThumbItem);
  var e: TTyChartElement;
  begin
    e := FPaintList.Element(AIdx);
    AItem.HasFill := e.Style.HasFill;
    AItem.Fill := e.Style.FillColor;
    AItem.HasStroke := e.Style.StrokeWidthLogical > 0;
    AItem.Stroke := e.Style.StrokeColor;
    if e.Style.StrokeWidthLogical > 0 then AItem.LineWidth := e.Style.StrokeWidthLogical
    else AItem.LineWidth := 0;
    AItem.Opacity := e.Style.Alpha;
    AItem.Dash := Copy(e.Style.DashLogical);
    AItem.DashOffset := e.Style.DashOffsetLogical;
  end;

begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FGraphNodes)) or (FPaintList = nil) then Exit;
  si := FBindings[ASlot].SeriesIndex;
  nodes := FGraphNodes[ASlot];
  edges := FGraphEdges[ASlot];
  spec := FGraphSpecs[ASlot];
  ser := nil;
  if FOption.ComponentAt('series', si) is TJSONObject then
    ser := TJSONObject(FOption.ComponentAt('series', si));
  dataArr := nil;
  cats := nil;
  if ser <> nil then
  begin
    dataArr := ser.Find('data');
    if dataArr = nil then dataArr := ser.Find('nodes');
    cats := ser.Find('categories');
  end;
  { the elements the list holds for this series: a node's by its row, an
    edge's line (not its arrows, which are silent) by its row }
  SetLength(nodeEl, Length(nodes) + 1);
  for i := 0 to High(nodeEl) do nodeEl[i] := -1;
  SetLength(edgeEl, Length(edges) + 1);
  for i := 0 to High(edgeEl) do edgeEl[i] := -1;
  for idx := 0 to FPaintList.Count - 1 do
  begin
    el := FPaintList.Element(idx);
    if (el.Datum.SeriesIndex <> si) or (el.Datum.Kind <> ctkSeries) then Continue;
    row := el.Datum.DataIndex;
    if el.Datum.IsEdge then
    begin
      if el.Silent or (row < 0) or (row > High(edgeEl)) then Continue;
      if edgeEl[row] < 0 then edgeEl[row] := idx;
    end
    else
    begin
      if (row < 0) or (row > High(nodeEl)) then Continue;
      if nodeEl[row] < 0 then nodeEl[row] := idx;
    end;
  end;
  n := 0;
  SetLength(Result, Length(nodes) + Length(edges));
  { symbolDraw's children: the nodes drawn, in data order }
  for i := 0 to High(nodes) do
  begin
    row := nodes[i].Row;
    if (row < 0) or IsNan(nodes[i].X) or IsNan(nodes[i].Y) then Continue;
    if (row > High(nodeEl)) or (nodeEl[row] < 0) then Continue;
    symName := nodes[i].SymbolName;
    if (symName = '') and (ser <> nil) and (ser.Find('symbol') <> nil)
      and (ser.Find('symbol').JSONType = jtString) then
      symName := ser.Find('symbol').AsString;
    if symName = '' then symName := 'circle';
    if symName = 'none' then Continue;
    if nodes[i].HasSize then
    begin
      w := nodes[i].SizeW;
      h := nodes[i].SizeH;
    end
    else
    begin
      w := spec.Symbol.WidthPx;
      h := spec.Symbol.HeightPx;
    end;
    it := Default(TTyThumbItem);
    it.Kind := tikSymbol;
    it.SymbolType := TyThumbSymbolType(symName);
    { the sub-path's scaleX / scaleY: half the symbol size }
    it.W := w / 2;
    it.H := h / 2;
    it.X := nodes[i].X - it.W / 2;
    it.Y := nodes[i].Y - it.H / 2;
    it.CPX := NaN;
    it.CPY := NaN;
    { THE SUB-PATH'S OWN STYLE, cloned (GraphView._renderThumbnail): the pen
      the list's node draws -- the visual's borderColor at its borderWidth,
      zrender's 1 where only a colour is written, its dash and phase; an
      `empty` symbol's ring in its colour, 2 px wide, over the ground
      (R2-I3's NodeBorder) -- and the opacity, the style category's (found by
      name too). [R2-I4; was: a rim only where borderWidth > 0, no dash, an
      opacity by the model's category, the empty ring made again here.] }
    StyleFrom(nodeEl[row], it);
    op := 1;
    if NodeStyle(i, 'opacity') is TJSONNumber then op := NodeStyle(i, 'opacity').AsFloat;
    it.Opacity := op;
    Result[n] := it;
    Inc(n);
  end;
  { lineDraw's children: the edges whose ends are points }
  haveInk := False;
  for i := 0 to High(edges) do
  begin
    if not edges[i].HasEnds then Continue;
    if (edges[i].Source < 0) or (edges[i].Source > High(nodes))
      or (edges[i].Target < 0) or (edges[i].Target > High(nodes)) then Continue;
    if IsNan(edges[i].TX1) or IsNan(edges[i].TY1) or IsNan(edges[i].TX2)
      or IsNan(edges[i].TY2) then Continue;
    it := Default(TTyThumbItem);
    it.Kind := tikLine;
    it.X1 := edges[i].TX1;
    it.Y1 := edges[i].TY1;
    it.X2 := edges[i].TX2;
    it.Y2 := edges[i].TY2;
    if edges[i].Curved then
    begin
      it.CPX := edges[i].TCPX;
      it.CPY := edges[i].TCPY;
    end
    else
    begin
      it.CPX := NaN;
      it.CPY := NaN;
    end;
    row := edges[i].Row;
    if (row >= 0) and (row <= High(edgeEl)) and (edgeEl[row] >= 0) then
      StyleFrom(edgeEl[row], it)
    else
    begin
      { an edge the list did not draw (no length): its style as the builder
        would have given it }
      if not haveInk then
      begin
        ink := GraphInk(ASlot);
        haveInk := True;
      end;
      it.Stroke := TyGraphEdgeStroke(spec, edges, ink, i);
      it.LineWidth := TyGraphEdgeWidth(spec, edges[i]);
      it.Opacity := TyGraphEdgeOpacity(spec, edges[i]);
      it.Dash := TyGraphEdgeDash(spec, edges[i]);
      it.DashOffset := TyGraphEdgeDashOffset(spec, edges[i]);
    end;
    { a line has no fill and always a stroke }
    it.HasFill := False;
    it.HasStroke := True;
    Result[n] := it;
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ ThumbnailView.render with the bridge's content: every thumbnail's model,
  enabled or not, its box and content rect; the one the target graph
  renders into takes the copy, its view and its window }
procedure TTyAdvanceChart.ThumbRender;
var
  k, slot: Integer;
  d: TJSONData;
  node, ser: TJSONObject;
  w, h: Double;
  tm: TTyMat2D;
  ref: TTyXYWH;
begin
  FThumbSnapDue := False;
  w := FLastRect.Right - FLastRect.Left;
  h := FLastRect.Bottom - FLastRect.Top;
  for k := 0 to High(FThumbs) do
  begin
    d := FOption.ComponentAt(TyThumbnailComponent, k);
    if d is TJSONObject then node := TJSONObject(d) else node := nil;
    FThumbs[k].Model := TyThumbModelOf(node);
    FThumbs[k].Items := nil;
    FThumbs[k].View := Default(TTyThumbView);
    FThumbs[k].Window := Default(TTyXYWH);
    FThumbs[k].Enabled := (node <> nil) and FThumbs[k].Model.Show
      and (FThumbs[k].Target >= 0)
      and (FOption.ComponentAt('series', FThumbs[k].Target) is TJSONObject);
    if not FThumbs[k].Enabled then Continue;
    { getLayoutRect in createBoxLayoutReference's container: the canvas, or
      a cell or a day [Batch 154] }
    ComponentBoxRef(TyThumbnailComponent, k, ref);
    FThumbs[k].Box := TyThumbBox(node, ref);
    FThumbs[k].Content := TyThumbContent(FThumbs[k].Box, FThumbs[k].Model.BorderWidth);
    ser := TJSONObject(FOption.ComponentAt('series', FThumbs[k].Target));
    TyThumbRoamOf(ser.Find('roam'), FThumbs[k].RoamText, FThumbs[k].RoamOn,
      FThumbs[k].RoamPan, FThumbs[k].RoamZoom);
    { only the bridge's owner gets the copy, and only from a graph that
      rendered on a view }
    if k <> FThumbOwner then Continue;
    slot := SlotOfSeries(FThumbs[k].Target);
    if (slot < 0) or (slot > High(FGraphs)) or (FGraphs[slot] = nil)
      or (slot > High(FGraphLaidOut)) or not FGraphLaidOut[slot] then Continue;
    FThumbs[k].Items := ThumbCopy(slot);
    tm := ThumbTargetMatrix(slot);
    FThumbs[k].View := TyThumbFit(FThumbs[k].Items, FThumbs[k].Content, tm);
    TyThumbUpdateWindow(FThumbs[k].View, tm, w, h, FThumbs[k].Window);
  end;
end;

{ the graph's __updateOnOwnRoam -> updateWindow }
procedure TTyAdvanceChart.ThumbUpdateWindows;
var k, slot: Integer;
begin
  k := FThumbOwner;
  if (k < 0) or (k > High(FThumbs)) or not FThumbs[k].View.Valid then Exit;
  slot := SlotOfSeries(FThumbs[k].Target);
  if (slot < 0) or (slot > High(FGraphs)) or (FGraphs[slot] = nil) then Exit;
  TyThumbUpdateWindow(FThumbs[k].View, ThumbTargetMatrix(slot),
    FLastRect.Right - FLastRect.Left, FLastRect.Bottom - FLastRect.Top,
    FThumbs[k].Window);
end;

{ the thumbnails' elements, at the model's z: the background (z2 141, not
  silent -- nothing under it is hovered), the copy clipped to the content
  rect (151, silent) and the window (161, in the clip) }
function TTyAdvanceChart.BuildThumbnails(AList: TTyPaintList): Integer;
var
  k, i: Integer;
  st: TTyThumbState;
  el: TTyChartElement;
  path: TTyZrPath;
  r1, r2, r3, r4: Double;
  m: TTyMat2D;
  skin, skinWin: TTyStyleSet;
  haveSkin: Boolean;
  clip: TTyRectF;
  c: TTyChartColor;
  d: TJSONData;

  function RectPath(const R: TTyXYWH; const ARadius: TTyDoubleArray): TTyZrPath;
  begin
    Result := nil;
    if Length(ARadius) = 0 then
    begin
      TyZrRect(Result, R.X, R.Y, R.W, R.H);
      Exit;
    end;
    TyZrRadii(ARadius, r1, r2, r3, r4);
    if (r1 = 0) and (r2 = 0) and (r3 = 0) and (r4 = 0) then
      TyZrRect(Result, R.X, R.Y, R.W, R.H)
    else
      TyZrRoundRect(Result, R.X, R.Y, R.W, R.H, r1, r2, r3, r4);
  end;

  { a colour the option wrote: 'none' or one that does not parse paints
    nothing }
  function Ink(const AInk: TTyThumbInk; out AColor: TTyChartColor): Boolean;
  begin
    AColor := 0;
    Result := (not TyChartColorIsNone(AInk.Text)) and TyTryParseChartColor(AInk.Text, AColor);
  end;

begin
  Result := 0;
  haveSkin := False;
  for k := 0 to High(FThumbs) do
  begin
    st := FThumbs[k];
    if not st.Enabled then Continue;
    if not haveSkin then
    begin
      skin := ActiveController.Model.ResolveStyle('TyAdvChartThumbnail', '', []);
      skinWin := ActiveController.Model.ResolveStyle('TyAdvChartThumbnailWindow', '', []);
      haveSkin := True;
    end;
    { the box: itemStyle.color, else the option's backgroundColor, else the
      skin's ground; the rim itemStyle's, else the skin's }
    el := Default(TTyChartElement);
    el.Shape := TyMkZrShape(RectPath(st.Box, st.Model.Radius), TyMatIdentity, False);
    if st.Model.Fill.Written then
      el.Style.HasFill := Ink(st.Model.Fill, el.Style.FillColor)
    else
    begin
      d := FOption.Find('backgroundColor');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
        el.Style.HasFill := (not TyChartColorIsNone(d.AsString))
          and TyTryParseChartColor(d.AsString, el.Style.FillColor)
      else
      begin
        el.Style.HasFill := True;
        el.Style.FillColor := TTyChartColor(skin.Background.Color);
      end;
    end;
    if st.Model.BorderWidth > 0 then
    begin
      if st.Model.Border.Written then
      begin
        if Ink(st.Model.Border, c) then
        begin
          el.Style.StrokeColor := c;
          el.Style.StrokeWidthLogical := st.Model.BorderWidth;
        end;
      end
      else
      begin
        el.Style.StrokeColor := TTyChartColor(skin.BorderColor);
        el.Style.StrokeWidthLogical := st.Model.BorderWidth;
      end;
    end;
    el.Style.Alpha := st.Model.Opacity;
    el.Z := Round(st.Model.Z);
    el.Z2 := TyThumbItemZ2 - 10;
    el.Silent := False;
    el.Datum := TyChartNoDatum;
    { ThumbnailView's _bgRect: cursor 'grab' [F6a] }
    el.Cursor := 'grab';
    AList.Add(el);
    Inc(Result);
    if not st.View.Valid then Continue;
    clip := TyRectF(st.Content.X, st.Content.Y, st.Content.X + st.Content.W,
      st.Content.Y + st.Content.H);
    { the copy through the group's raw transform; its strokes keep their
      width (strokeNoScale) }
    m := TyMatIdentity;
    m[0] := st.View.TransSX;
    m[3] := st.View.TransSY;
    m[4] := st.View.TransX;
    m[5] := st.View.TransY;
    for i := 0 to High(st.Items) do
    begin
      path := TyThumbItemPath(st.Items[i]);
      if Length(path) = 0 then Continue;
      el := Default(TTyChartElement);
      el.Shape := TyMkZrShape(path, m, True);
      el.Style.HasFill := st.Items[i].HasFill;
      el.Style.FillColor := st.Items[i].Fill;
      if st.Items[i].HasStroke then
      begin
        el.Style.StrokeColor := st.Items[i].Stroke;
        el.Style.StrokeWidthLogical := st.Items[i].LineWidth;
        el.Style.DashLogical := Copy(st.Items[i].Dash);
        el.Style.DashOffsetLogical := st.Items[i].DashOffset;
      end;
      el.Style.Alpha := st.Items[i].Opacity;
      el.Z := Round(st.Model.Z);
      el.Z2 := TyThumbItemZ2;
      el.Silent := True;
      el.Datum := TyChartNoDatum;
      el.HasClip := True;
      el.ClipRect := clip;
      AList.Add(el);
      Inc(Result);
    end;
    { the window }
    el := Default(TTyChartElement);
    el.Shape := TyMkZrShape(RectPath(st.Window, st.Model.WinRadius), TyMatIdentity, False);
    if st.Model.WinFill.Written then
      el.Style.HasFill := Ink(st.Model.WinFill, el.Style.FillColor)
    else
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(skinWin.Background.Color);
    end;
    if st.Model.WinBorderWidth > 0 then
    begin
      if st.Model.WinBorder.Written then
      begin
        if Ink(st.Model.WinBorder, c) then
        begin
          el.Style.StrokeColor := c;
          el.Style.StrokeWidthLogical := st.Model.WinBorderWidth;
        end;
      end
      else
      begin
        el.Style.StrokeColor := TTyChartColor(skinWin.BorderColor);
        el.Style.StrokeWidthLogical := st.Model.WinBorderWidth;
      end;
    end;
    el.Style.Alpha := st.Model.WinOpacity;
    el.Z := Round(st.Model.Z);
    el.Z2 := TyThumbItemZ2 + 10;
    el.Silent := False;
    el.Datum := TyChartNoDatum;
    { and its _windowRect [F6a] }
    el.Cursor := 'grab';
    el.HasClip := True;
    el.ClipRect := clip;
    AList.Add(el);
    Inc(Result);
  end;
end;

{ the thumbnail's RoamController mousedown: the owner with a copy, a roam
  that pans, the press in its content rect }
procedure TTyAdvanceChart.ThumbDown(AX, AY: Integer);
var k: Integer;
begin
  FThumbDrag := -1;
  k := FThumbOwner;
  if (k < 0) or (k > High(FThumbs)) then Exit;
  if not (FThumbs[k].Enabled and FThumbs[k].View.Valid and FThumbs[k].RoamPan) then Exit;
  if not TyThumbRectContains(FThumbs[k].Content, AX, AY) then Exit;
  FThumbDrag := k;
  FThumbDragX := AX;
  FThumbDragY := AY;
end;

{ its mousewheel: a roam that zooms, the pointer in the content rect: the
  graph zooms by 1 / the factor about the pointer carried into its canvas }
function TTyAdvanceChart.ThumbWheel(AX, AY, AWheelDelta: Integer): Boolean;
var
  k: Integer;
  s, z, ox, oy: Double;
begin
  Result := False;
  k := FThumbOwner;
  if (k < 0) or (k > High(FThumbs)) then Exit;
  if not (FThumbs[k].Enabled and FThumbs[k].View.Valid and FThumbs[k].RoamZoom) then Exit;
  s := TyGraphWheelScale(AWheelDelta);
  if s = 0 then Exit;
  if not TyThumbRectContains(FThumbs[k].Content, AX, AY) then Exit;
  TyThumbZoomPayload(FThumbs[k].View, s, AX, AY, z, ox, oy);
  GraphZoom(FThumbs[k].Target, z, ox, oy);
  Result := True;
end;

function TTyAdvanceChart.ThumbnailCount: Integer;
begin
  Result := Length(FThumbs);
end;

function TTyAdvanceChart.ThumbnailState(AIndex: Integer): TTyThumbState;
begin
  Result := Default(TTyThumbState);
  Result.Target := -1;
  if (AIndex >= 0) and (AIndex <= High(FThumbs)) then Result := FThumbs[AIndex];
end;

function TTyAdvanceChart.ThumbnailOwner: Integer;
begin
  Result := FThumbOwner;
end;

function TTyAdvanceChart.ThumbnailHitAt(AX, AY: Double): Integer;
var
  k: Integer;
  e: Double;
  r: TTyXYWH;
begin
  for k := High(FThumbs) downto 0 do
  begin
    if not FThumbs[k].Enabled then Continue;
    r := FThumbs[k].Box;
    e := Math.Max(0, FThumbs[k].Model.BorderWidth) / 2;
    r.X := r.X - e;
    r.Y := r.Y - e;
    r.W := r.W + 2 * e;
    r.H := r.H + 2 * e;
    if TyThumbRectContains(r, AX, AY) then Exit(k);
  end;
  Result := -1;
end;
