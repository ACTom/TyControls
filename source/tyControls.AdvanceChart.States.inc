{ Part of tyControls.AdvanceChart (included, not a unit): element states, state
  transitions, focus and blur, and the selection. Moved out of the unit only to keep it
  readable; what the control is and why it is built the way it is, see the unit header. }

{ ==================== element states and the selection [Batch 88] ==================== }

const
  cStNames: array[TTyStName] of string = ('select', 'emphasis', 'blur');

function StSameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := A = B;
end;

procedure StPush(var AArr: TTyIntegerArray; AValue: Integer);
begin
  SetLength(AArr, Length(AArr) + 1);
  AArr[High(AArr)] := AValue;
end;

{ [F3d] the rest colour of AKey as the option's gradient object at APath,
  when that is one }
procedure StRestGradient(var ARest: TTyStObject; const ANodes: array of TJSONObject;
  const APath: array of string; AKey: TTyStKey);
var d: TJSONData;
begin
  d := TyStFind(ANodes, APath);
  if TyStIsGradient(d) then
    TyStSetGradient(ARest, AKey, d.AsJSON, ARest.Color[AKey]);
end;

{ a label's: its anchor (the Text's own x / y), its paint order, whether it
  shows; its fill stays absent -- the automatic ink is the port's }
function StLabelRestOf(const AEl: TTyChartElement): TTyStObject;
begin
  Result := TyStNoObject;
  { the label's own opacity: the host's at build, as defaultOpacity hands it
    over [Batch 90] }
  TyStSetNum(Result, stkOpacity, AEl.Style.Alpha);
  TyStSetNum(Result, stkZ2, AEl.Z2);
  TyStSetNum(Result, stkX, AEl.Caption.X);
  TyStSetNum(Result, stkY, AEl.Caption.Y);
  TyStSetNum(Result, stkR, 0);
  TyStSetNum(Result, stkScale, 1);
  TyStSetNum(Result, stkIgnore, Ord(AEl.Ignore));
end;

function StGuideRestOf(const AEl: TTyChartElement): TTyStObject;
begin
  Result := TyStNoObject;
  { the line's ink, width and smooth at rest [Batch 112] }
  TyStSetColor(Result, stkStroke, AEl.Style.StrokeColor);
  TyStSetNum(Result, stkLineWidth, AEl.Style.StrokeWidthLogical);
  TyStSetNum(Result, stkSmooth, AEl.Caption.LgSmooth);
  TyStSetNum(Result, stkOpacity, AEl.Style.Alpha);
  TyStSetNum(Result, stkZ2, AEl.Z2);
  TyStSetNum(Result, stkX, 0);
  TyStSetNum(Result, stkY, 0);
  TyStSetNum(Result, stkR, 0);
  TyStSetNum(Result, stkScale, 1);
  TyStSetNum(Result, stkIgnore, Ord(AEl.Ignore));
end;

{ A MARKER ELEMENT'S NAME [F2b], as states-misc.js names it: mp<k> a
  markPoint's symbol, ml<k> a markLine's segment and ml<k>.from / .to its
  end symbols, ma<k> a markArea's polygon; '#label' after the item's name for
  its words. k is the marker's data index. }
function StMarkPartOf(const AEl: TTyChartElement): string;
begin
  case AEl.Datum.Kind of
    ctkMarkPoint: Result := 'mp';
    ctkMarkLine: Result := 'ml';
  else
    Result := 'ma';
  end;
  Result := Result + IntToStr(AEl.Datum.DataIndex);
  if AEl.Caption.FontSizeLogical > 0 then Result := Result + '#label'
  else if AEl.Anim.Role = carMarkLineFrom then Result := Result + '.from'
  else if AEl.Anim.Role = carMarkLineTo then Result := Result + '.to';
end;

procedure StShiftShape(var AShape: TTyChartShape; ADX, ADY: Double);
var i: Integer;
begin
  if (ADX = 0) and (ADY = 0) then Exit;
  AShape.Bounds.Left := AShape.Bounds.Left + ADX;
  AShape.Bounds.Right := AShape.Bounds.Right + ADX;
  AShape.Bounds.Top := AShape.Bounds.Top + ADY;
  AShape.Bounds.Bottom := AShape.Bounds.Bottom + ADY;
  AShape.CX := AShape.CX + ADX;
  AShape.CY := AShape.CY + ADY;
  AShape.RotCX := AShape.RotCX + ADX;
  AShape.RotCY := AShape.RotCY + ADY;
  for i := 0 to High(AShape.Points) do
  begin
    AShape.Points[i].X := AShape.Points[i].X + ADX;
    AShape.Points[i].Y := AShape.Points[i].Y + ADY;
  end;
  for i := 0 to High(AShape.Cmds) do
  begin
    AShape.Cmds[i].X1 := AShape.Cmds[i].X1 + ADX;
    AShape.Cmds[i].Y1 := AShape.Cmds[i].Y1 + ADY;
    AShape.Cmds[i].X2 := AShape.Cmds[i].X2 + ADX;
    AShape.Cmds[i].Y2 := AShape.Cmds[i].Y2 + ADY;
    AShape.Cmds[i].X := AShape.Cmds[i].X + ADX;
    AShape.Cmds[i].Y := AShape.Cmds[i].Y + ADY;
  end;
  if AShape.HasCmdBounds then
  begin
    AShape.CmdBounds.Left := AShape.CmdBounds.Left + ADX;
    AShape.CmdBounds.Right := AShape.CmdBounds.Right + ADX;
    AShape.CmdBounds.Top := AShape.CmdBounds.Top + ADY;
    AShape.CmdBounds.Bottom := AShape.CmdBounds.Bottom + ADY;
  end;
end;

function SameColourKey(const A, B: TTyStObject; AKey: TTyStKey): Boolean;
begin
  Result := (A.Has[AKey] = B.Has[AKey]) and (A.None[AKey] = B.None[AKey])
    and (A.None[AKey] or ((A.Color[AKey] = B.Color[AKey])
      { [F3d] a gradient is the same only as itself, lifted or not }
      and (A.GradJson[AKey] = B.GradJson[AKey])
      and ((A.GradJson[AKey] = '') or (A.Lifted[AKey] = B.Lifted[AKey]))));
end;

function StColourValue(const AObj: TTyStObject; AKey: TTyStKey): TTyAnimValue; forward;

{ [F3d] a state object's gradient key as the painter draws it }
function StGradientOf(const AObj: TTyStObject; AKey: TTyStKey;
  out AGrad: TTyChartGradient): Boolean;
begin
  Result := (AObj.GradJson[AKey] <> '') and not AObj.None[AKey]
    and TyAnimGradientOfValue(StColourValue(AObj, AKey), AGrad);
end;

{ THE CURRENT VALUES ONTO A MARK. A colour a state did not change is left as
  the build drew it -- a gradient stays a gradient; a lifted colour over a
  gradient fill leaves the gradient too (the port does not lift a ramp). }
procedure StWriteHost(var AEl: TTyChartElement; const AState: TTyStElement;
  AProxied: Boolean);
var c, r: TTyStObject; g: TTyChartGradient;
begin
  c := AState.Cur;
  r := AState.Rest;
  { ON A PROXY the animatable keys are the frame's: the list keeps the rest
    values, and only the paint order and the visibility are written
    [Batch 94] }
  if AProxied then
  begin
    AEl.Z2 := Round(c.Num[stkZ2]);
    AEl.Ignore := c.Num[stkIgnore] <> 0;
    Exit;
  end;
  if not SameColourKey(c, r, stkFill) then
  begin
    if c.None[stkFill] then AEl.Style.HasFill := False
    { [F3d] a state's gradient -- declared, inherited or lifted }
    else if StGradientOf(c, stkFill, g) then
    begin
      AEl.Style.HasFill := True;
      AEl.Style.FillColor := c.Color[stkFill];
      AEl.Style.FillGradient := g;
    end
    else if not (c.Lifted[stkFill] and (AEl.Style.FillGradient.Kind <> cgkNone)) then
    begin
      AEl.Style.HasFill := True;
      AEl.Style.FillColor := c.Color[stkFill];
      AEl.Style.FillGradient := Default(TTyChartGradient);
    end;
  end;
  if not SameColourKey(c, r, stkStroke) then
  begin
    if c.None[stkStroke] then AEl.Style.StrokeColor := 0
    else if StGradientOf(c, stkStroke, g) then
    begin
      AEl.Style.StrokeColor := c.Color[stkStroke];
      AEl.Style.StrokeGradient := g;
    end
    else if not (c.Lifted[stkStroke] and (AEl.Style.StrokeGradient.Kind <> cgkNone)) then
    begin
      AEl.Style.StrokeColor := c.Color[stkStroke];
      AEl.Style.StrokeGradient := Default(TTyChartGradient);
    end;
  end;
  { the width wherever a stroke is drawn -- zrender's own 1 where the build
    had none -- and a changed one anyway }
  if TyStHasColour(c, stkStroke)
    or not StSameNum(c.Num[stkLineWidth], r.Num[stkLineWidth]) then
    AEl.Style.StrokeWidthLogical := c.Num[stkLineWidth];
  if not StSameNum(c.Num[stkOpacity], r.Num[stkOpacity]) then AEl.Style.Alpha := c.Num[stkOpacity];
  AEl.Z2 := Round(c.Num[stkZ2]);
  StShiftShape(AEl.Shape, c.Num[stkX] - r.Num[stkX], c.Num[stkY] - r.Num[stkY]);
  if (AEl.Shape.Kind = cskSector) and not StSameNum(c.Num[stkR], r.Num[stkR]) then
    AEl.Shape.R1 := c.Num[stkR];
  if not StSameNum(c.Num[stkScale], 1) and StPositive(c.Num[stkScale]) then
    AEl.Shape := TyScaleShape(AEl.Shape, c.Num[stkScale]);
  AEl.Ignore := c.Num[stkIgnore] <> 0;
end;

{ A FOLLOWER: another stretch of the host's own path (a candlestick's
  wicks) -- the colours the states changed, the host's opacity and its
  paint order, the same translation [Batch 90] }
procedure StWriteFollower(var AEl: TTyChartElement; const AHost: TTyStElement;
  AProxied: Boolean);
var c, r: TTyStObject;
begin
  c := AHost.Cur;
  r := AHost.Rest;
  if AProxied then
  begin
    AEl.Z2 := AEl.Z2 + Round(c.Num[stkZ2] - r.Num[stkZ2]);
    AEl.Ignore := c.Num[stkIgnore] <> 0;
    Exit;
  end;
  if not SameColourKey(c, r, stkFill) and AEl.Style.HasFill then
  begin
    if c.None[stkFill] then AEl.Style.HasFill := False
    else AEl.Style.FillColor := c.Color[stkFill];
  end;
  if not SameColourKey(c, r, stkStroke) and (AEl.Style.StrokeColor <> 0) then
  begin
    if c.None[stkStroke] then AEl.Style.StrokeColor := 0
    else AEl.Style.StrokeColor := c.Color[stkStroke];
  end;
  if not StSameNum(c.Num[stkLineWidth], r.Num[stkLineWidth]) then
    AEl.Style.StrokeWidthLogical := c.Num[stkLineWidth];
  if not StSameNum(c.Num[stkOpacity], r.Num[stkOpacity]) then
    AEl.Style.Alpha := c.Num[stkOpacity];
  AEl.Z2 := AEl.Z2 + Round(c.Num[stkZ2] - r.Num[stkZ2]);
  StShiftShape(AEl.Shape, c.Num[stkX] - r.Num[stkX], c.Num[stkY] - r.Num[stkY]);
  AEl.Ignore := c.Num[stkIgnore] <> 0;
end;

procedure StWriteLabel(var AEl: TTyChartElement; const AState: TTyStElement;
  AProxied: Boolean);
var c, r: TTyStObject; dx, dy: Double;
begin
  c := AState.Cur;
  r := AState.Rest;
  { on a proxy the place and the opacity are the frame's; the ink is not
    animated (a Text's style animates its opacity only) [Batch 94] }
  if not AProxied then
  begin
    dx := c.Num[stkX] - r.Num[stkX];
    dy := c.Num[stkY] - r.Num[stkY];
    AEl.Caption.X := c.Num[stkX];
    AEl.Caption.Y := c.Num[stkY];
    StShiftShape(AEl.Shape, dx, dy);
  end;
  AEl.Z2 := Round(c.Num[stkZ2]);
  AEl.Ignore := c.Num[stkIgnore] <> 0;
  { blur: the label's opacity, a tenth of it by default [Batch 90] }
  if not AProxied and not StSameNum(c.Num[stkOpacity], r.Num[stkOpacity]) then
    AEl.Style.Alpha := c.Num[stkOpacity];
  { the ink: a colour a state declares, else the hover's own under emphasis }
  if TyStHasColour(c, stkFill) then
  begin
    AEl.Caption.Colour := c.Color[stkFill];
    if Length(AEl.Caption.RtPieces) > 0 then
      AEl.Caption.RtPieces := TyRtReink(AEl.Caption.RtPieces, c.Color[stkFill],
        False, AEl.Caption.StrokeColour, AEl.Caption.StrokeWidthLogical);
  end
  else if stnEmphasis in AState.States then
    TyCaptionToEmphasis(AEl.Caption);
end;

procedure StWriteGuide(var AEl: TTyChartElement; const AState: TTyStElement;
  AProxied: Boolean);
var c, r: TTyStObject;
begin
  c := AState.Cur;
  r := AState.Rest;
  if not AProxied then
    StShiftShape(AEl.Shape, c.Num[stkX] - r.Num[stkX], c.Num[stkY] - r.Num[stkY]);
  AEl.Z2 := Round(c.Num[stkZ2]);
  AEl.Ignore := c.Num[stkIgnore] <> 0;
  if not AProxied and not StSameNum(c.Num[stkOpacity], r.Num[stkOpacity]) then
    AEl.Style.Alpha := c.Num[stkOpacity];
  { the state's lineStyle and smooth (a state that does not say draws it
    straight) [Batch 112] }
  if c.Has[stkStroke] then AEl.Style.StrokeColor := c.Color[stkStroke];
  if c.Has[stkLineWidth] then AEl.Style.StrokeWidthLogical := c.Num[stkLineWidth];
  if c.Has[stkSmooth] and not StSameNum(c.Num[stkSmooth], r.Num[stkSmooth]) then
    AEl.Shape.Cmds := TyLabelLineCmds(AEl.Shape.Points, c.Num[stkSmooth]);
end;

{ AN ITEM'S emphasis.label.show AS THE MODEL HOLDS IT [F2b]: the first
  node that writes it, a data item that writes a label.show of its own
  having it copied (Series.fillDataTextStyle's defaultEmphasis); the series'
  default its type's (ADefault: a funnel's true) or else its normal show
  (mergeDefaultAndTheme's defaultEmphasis -- the same as normal, so no
  change). AHas False when nothing says. }
function StEmphLabelShow(const ANodes: array of TJSONObject; ADefaultTrue: Boolean;
  out AHas: Boolean): Boolean;
var i: Integer; d: TJSONData;
begin
  Result := False;
  AHas := False;
  for i := 0 to High(ANodes) do
  begin
    if ANodes[i] = nil then Continue;
    d := TyStFind([ANodes[i]], ['emphasis', 'label', 'show']);
    if d <> nil then
    begin
      AHas := True;
      Exit(TyStReadBool([ANodes[i]], ['emphasis', 'label', 'show'], AHas));
    end;
    { a data item's own label.show is its emphasis one too }
    if (i = 0) and (High(ANodes) > 0) and (TyStFind([ANodes[i]], ['label', 'show']) <> nil) then
      Exit(TyStReadBool([ANodes[i]], ['label', 'show'], AHas));
  end;
  if ADefaultTrue then
  begin
    AHas := True;
    Result := True;
  end;
end;

function TTyAdvanceChart.StKindOf(ASlot: Integer): TTyStKind;
var t: string;
begin
  Result := sskNone;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  { a radar's items, drawn by a builder of its own [F2b; on the overlay
    before]; a calendar's scatter and heatmap are the cartesian ones'
    elements [Batch 90] }
  if FBindings[ASlot].RadarIndex >= 0 then
  begin
    if FBindings[ASlot].SeriesType = 'radar' then Result := sskRadar;
    Exit;
  end;
  t := FBindings[ASlot].SeriesType;
  if t = 'bar' then Result := sskBar
  else if t = TyPieSeriesTypeName then Result := sskPie
  else if (t = 'line') or (t = 'scatter') or (t = 'effectScatter') then
    Result := sskSymbol
  else if t = 'heatmap' then Result := sskRect
  else if t = 'funnel' then Result := sskFunnel
  else if t = 'candlestick' then Result := sskCandle
  else if t = TyPictorialSeriesTypeName then Result := sskPictorial
  else if t = TySunburstSeriesTypeName then Result := sskSunburst
  else if t = 'boxplot' then Result := sskBox
  else if t = TySankeySeriesTypeName then Result := sskSankey
  else if t = TyThemeRiverSeriesTypeName then Result := sskRiver
  else if t = TyChordSeriesTypeName then Result := sskChord
  { a lines series' rows, not in large mode (a batch has no states)
    [Batch 121] }
  else if (t = TyLinesSeriesTypeName) and not ((ASlot <= High(FLines))
    and FLines[ASlot].IsLarge) then Result := sskLines
  { a custom series' items [Batch 123] }
  else if t = TyCustomSeriesType then Result := sskCustom
  { a parallel row's polyline [Batch 128] }
  else if (t = TyParallelSeriesTypeName) and (FBindings[ASlot].Parallel <> nil) then
    Result := sskParallel
  { a map series' regions [Batch 152] }
  else if t = TyMapSeriesTypeName then
    Result := sskMap
  { [F2a] a laid-out graph, a solved tree, a solved treemap }
  else if (t = TyGraphSeriesTypeName) and (ASlot <= High(FGraphLaidOut))
    and FGraphLaidOut[ASlot] then Result := sskGraph
  else if (t = TyTreeSeriesTypeName) and (ASlot <= High(FTrees)) and FTrees[ASlot].Valid then
    Result := sskTree
  else if (t = TyTreemapSeriesTypeName) and (ASlot <= High(FTreemaps))
    and FTreemaps[ASlot].Valid then Result := sskTreemap
  { a gauge's pointers and arcs [F2b; on the overlay before] }
  else if t = TyGaugeSeriesTypeName then
    Result := sskGauge;
  { a line on a calendar is not drawn at all }
  if (FBindings[ASlot].CalendarIndex >= 0) and (t = 'line') then Result := sskNone;
end;

function TTyAdvanceChart.StSeriesNode(ASeriesIndex: Integer): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASeriesIndex);
  if d is TJSONObject then Result := TJSONObject(d);
end;

function TTyAdvanceChart.StItemNode(ASeriesIndex, ARaw: Integer): TJSONObject;
var s: TJSONObject; d: TJSONData; slot: Integer;
begin
  Result := nil;
  { A SUNBURST'S DATA IS ITS TREE: the row's own node [Batch 90] }
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FSunbursts)) and FSunbursts[slot].Valid then
  begin
    if (ARaw >= 0) and (ARaw <= High(FSunbursts[slot].Hier.Nodes))
      and (FSunbursts[slot].Hier.Nodes[ARaw].Item is TJSONObject) then
      Result := TJSONObject(FSunbursts[slot].Hier.Nodes[ARaw].Item);
    Exit;
  end;
  { [F2a] A TREE'S AND A TREEMAP'S DATA IS THEIR HIERARCHY: the row's own
    node; a graph's nodes are `data || nodes` }
  if (slot >= 0) and (FBindings[slot].SeriesType = TyTreeSeriesTypeName)
    and (slot <= High(FTrees)) and FTrees[slot].Valid then
  begin
    if (ARaw >= 0) and (ARaw <= High(FTrees[slot].Hier.Nodes))
      and (FTrees[slot].Hier.Nodes[ARaw].Item is TJSONObject) then
      Result := TJSONObject(FTrees[slot].Hier.Nodes[ARaw].Item);
    Exit;
  end;
  if (slot >= 0) and (FBindings[slot].SeriesType = TyTreemapSeriesTypeName)
    and (slot <= High(FTreemaps)) and FTreemaps[slot].Valid then
  begin
    if (ARaw >= 0) and (ARaw <= High(FTreemaps[slot].Hier.Nodes))
      and (FTreemaps[slot].Hier.Nodes[ARaw].Item is TJSONObject) then
      Result := TJSONObject(FTreemaps[slot].Hier.Nodes[ARaw].Item);
    Exit;
  end;
  if (slot >= 0) and (FBindings[slot].SeriesType = TyGraphSeriesTypeName) then
  begin
    s := StSeriesNode(ASeriesIndex);
    if s = nil then Exit;
    d := s.Find('data');
    if (d = nil) or (d.JSONType = jtNull) then d := s.Find('nodes');
    if (d is TJSONArray) and (ARaw >= 0) and (ARaw < d.Count)
      and (TJSONArray(d).Items[ARaw] is TJSONObject) then
      Result := TJSONObject(TJSONArray(d).Items[ARaw]);
    Exit;
  end;
  { A CHORD'S NODE: its item of `data || nodes` [Batch 120] }
  if (slot >= 0) and (slot <= High(FChords)) and FChords[slot].Valid then
  begin
    if (ARaw >= 0) and (ARaw <= High(FChords[slot].Nodes)) then
      Result := FChords[slot].Nodes[ARaw].Obj;
    Exit;
  end;
  s := StSeriesNode(ASeriesIndex);
  if s = nil then Exit;
  d := s.Find('data');
  if not (d is TJSONArray) then Exit;
  if (ARaw < 0) or (ARaw >= TJSONArray(d).Count) then Exit;
  d := TJSONArray(d).Items[ARaw];
  if d is TJSONObject then Result := TJSONObject(d);
end;

{ tokens.color.primary -- the ink a title is written in, which is how the
  skin says it }
function TTyAdvanceChart.StMemoMatches(ASeries: Integer;
  const ANodes: TTyStNodeArray; const ABlock: string): Boolean;
var k: Integer;
begin
  Result := False;
  if not FStMemoOk or (ASeries <> FStMemoS) or (Length(ANodes) = 0) or (ANodes[0] <> nil)
    or (Length(ANodes) <> Length(FStMemoNodes)) or (ABlock <> FStMemoBlk) then Exit;
  for k := 1 to High(ANodes) do
    if ANodes[k] <> FStMemoNodes[k] then Exit;
  Result := True;
end;

function TTyAdvanceChart.StPrimaryInk: TTyChartColor;
begin
  { ONCE PER SYNC: every row of a bar or a scatter asked the theme for it
    [P2]; outside a sync it is asked afresh }
  if FStInkHeld then Exit(FStInk);
  Result := TTyChartColor(ActiveController.Model.ResolveStyle('TyAdvChartTitle',
    '', []).TextColor);
  if FStInkHold then
  begin
    FStInk := Result;
    FStInkHeld := True;
  end;
end;

procedure TTyAdvanceChart.StDeclareItem(ASlot, ARaw: Integer;
  AList: TTyPaintList; APPI: Integer);
var
  blk: string;
  s, idx, labIdx: Integer;
  lineShow, labRest, labIgn, ownLine, emphLine, seriesLine, labShow, emphLab: Boolean;
  item: PTyStItem;
  ph, pc, pg, pp: PTyChartElement;
  nodes: TTyStNodeArray;
  scale, off, mid, dx, dy, ss, half: Double;
  has, bolder, disabled, was, normalShow, stShow, doScale: Boolean;
  base, obj: TTyStObject;
  spec: TTyChartEmphasisSpec;
  n: TTyStName;
  txt: string;
  c: TTyChartColor;
  k: Integer;
begin
  s := FBindings[ASlot].SeriesIndex;
  if FSt[s].Kind = sskCustom then
  begin
    StDeclareCustom(ASlot, ARaw, AList);
    Exit;
  end;
  { a treemap's rects [F2a] }
  if FSt[s].Kind = sskTreemap then
  begin
    StDeclareTreemap(ASlot, ARaw, AList);
    Exit;
  end;
  { A MAP REGION'S ROW: only its flags matter here -- the region group's
    paths take them through the geo [Batch 152] }
  if FSt[s].Kind = sskMap then
  begin
    item := @FSt[s].Rows[ARaw];
    item^.Host.Exists := True;
    item^.Host.IsPath := True;
    nodes := StNodes(s, ARaw);
    item^.Host.Proxy := not TyStReadBool(nodes, ['emphasis', 'disabled'], has);
    for n := Low(TTyStName) to High(TTyStName) do item^.Host.HasState[n] := True;
    Exit;
  end;
  item := @FSt[s].Rows[ARaw];
  ph := AList.Ref(FSt[s].HostIdx[ARaw]);
  nodes := StNodes(s, ARaw);
  if APPI > 0 then scale := APPI / 96 else scale := 1;

  { ---- the mark ---- }
  item^.Host.Exists := True;
  item^.Host.IsPath := True;
  { a symbol (a line's, a scatter's): the group dispatches, the path draws
    [Batch 90] }
  item^.HasGroup := FSt[s].Kind in [sskSymbol, sskGraph, sskTree];
  { a gauge's pointer: z2EmphasisLift 0 [F2b] }
  item^.Host.NoEmphLift := FSt[s].Kind = sskGauge;
  { emphasis.disabled: no hover dispatcher and no default proxy }
  disabled := TyStReadBool(nodes, ['emphasis', 'disabled'], has);
  item^.Host.Proxy := not disabled;
  for n := Low(TTyStName) to High(TTyStName) do item^.Host.HasState[n] := True;
  item^.Host.Rest := StRestOf(ph^);
  { THE SELECT LOOK the series type brings under what is declared: a bar's
    and a scatter's border in the primary ink (BarSeries.ts:165,
    ScatterSeries.ts:151); a pie's and a line's nothing }
  base := TyStNoObject;
  case FSt[s].Kind of
    sskBar:
      begin
        TyStSetColor(base, stkStroke, StPrimaryInk);
        TyStSetNum(base, stkLineWidth, 2);
      end;
    sskSymbol:
      if not FSt[s].IsLine then TyStSetColor(base, stkStroke, StPrimaryInk);
    { a heatmap's, a funnel's and a pictorial bar's: the border only
      (HeatmapSeries.ts:130, FunnelSeries.ts:200, PictorialBarSeries.ts:173)
      [Batch 90] }
    sskRect, sskFunnel, sskPictorial,
    { a sankey node's: select.itemStyle.borderColor (SankeySeries.ts)
      [Batch 114]; a graph node's (GraphSeries.ts select.itemStyle) [F2a] }
    sskSankey, sskGraph:
      TyStSetColor(base, stkStroke, StPrimaryInk);
  end;
  { a lines row's: its lineStyle's (Line._updateCommonStl) [Batch 121] }
  { [F2b] a radar's polyline: setStatesStylesFromModel(polyline, itemModel,
    'lineStyle') }
  if FSt[s].Kind in [sskLines, sskParallel, sskRadar] then blk := 'lineStyle'
  else blk := 'itemStyle';
  { A ROW WITH NO OBJECT OF ITS OWN reads its states from the rest of its
    chain alone -- as the last such row did, when the chain and the block
    are the same: those three asked once per series in a sync [P2] }
  if FStInkHold and StMemoMatches(s, nodes, blk) then
  begin
    item^.Host.Decl[stnSelect] := FStMemoDecl[0];
    item^.Host.Decl[stnEmphasis] := FStMemoDecl[1];
    item^.Host.Decl[stnBlur] := FStMemoDecl[2];
  end
  else
  begin
    item^.Host.Decl[stnSelect] := TyStOverlay(base,
      TyStReadStyle(nodes, 'select', blk, bolder));
    item^.Host.Decl[stnEmphasis] := TyStReadStyle(nodes, 'emphasis', blk, bolder);
    item^.Host.Decl[stnBlur] := TyStReadStyle(nodes, 'blur', blk, bolder);
    if FStInkHold and (Length(nodes) > 0) and (nodes[0] = nil) then
    begin
      FStMemoOk := True;
      FStMemoS := s;
      FStMemoBlk := blk;
      FStMemoNodes := Copy(nodes, 0, Length(nodes));
      FStMemoDecl[0] := item^.Host.Decl[stnSelect];
      FStMemoDecl[1] := item^.Host.Decl[stnEmphasis];
      FStMemoDecl[2] := item^.Host.Decl[stnBlur];
    end;
  end;
  { [F3d] A GRADIENT AT REST is the option's object (the element's
    style.fill is it): the state's tween starts from it, and the emphasis
    lifts it }
  if blk = 'itemStyle' then
  begin
    if ph^.Style.FillGradient.Kind <> cgkNone then
      StRestGradient(item^.Host.Rest, nodes, ['itemStyle', 'color'], stkFill);
    if ph^.Style.StrokeGradient.Kind <> cgkNone then
      StRestGradient(item^.Host.Rest, nodes, ['itemStyle', 'borderColor'], stkStroke);
  end;
  if FSt[s].Kind = sskCandle then StDeclareCandle(ASlot, ARaw, nodes, item^.Host);
  { a boxplot's emphasis border is 2 wide unless declared (BoxplotSeries.ts
    emphasis.itemStyle); its shadow is not drawn here [Batch 108] }
  if (FSt[s].Kind = sskBox) and not item^.Host.Decl[stnEmphasis].Has[stkLineWidth] then
    TyStSetNum(item^.Host.Decl[stnEmphasis], stkLineWidth, 2);
  { a sunburst blurs to 0.2 unless told (SunburstSeries.ts:274-279) [Batch 90] }
  if (FSt[s].Kind = sskSunburst) and not item^.Host.Decl[stnBlur].Has[stkOpacity] then
    TyStSetNum(item^.Host.Decl[stnBlur], stkOpacity, 0.2);
  dx := 0;
  dy := 0;
  case FSt[s].Kind of
    sskPie:
      begin
        { PieView.ts:128-150: the SERIES' selectedOffset along the mid angle,
          and the emphasis radius the layout's plus scaleSize }
        off := TyStReadNumber([nodes[1]], ['selectedOffset'], has);
        if not has or IsNan(off) then off := 10;
        mid := (ph^.Shape.StartRad + ph^.Shape.EndRad) / 2;
        if IsNan(mid) or IsNan(off) then mid := 0;
        dx := TyJsCos(mid) * (off * scale);
        dy := TyJsSin(mid) * (off * scale);
        TyStSetNum(item^.Host.Decl[stnSelect], stkX, dx);
        TyStSetNum(item^.Host.Decl[stnSelect], stkY, dy);
        doScale := TyStReadBool(nodes, ['emphasis', 'scale'], has);
        if not has then doScale := True;
        if doScale then
        begin
          ss := TyStReadNumber(nodes, ['emphasis', 'scaleSize'], has);
          if not has then ss := 5
          else if IsNan(ss) then ss := 0;
          TyStSetNum(item^.Host.Decl[stnEmphasis], stkR, ph^.Shape.R1 + ss * scale);
        end;
      end;
    sskSymbol:
      begin
        { Symbol.ts:218-357: the path grows by the emphasis ratio -- the
          series' spec read once per sync [P2] }
        if FStInkHold and (FStMemoSpecNode <> nil) and (FStMemoSpecNode = nodes[1]) then
          spec := FStMemoSpec
        else
        begin
          spec := TyChartReadEmphasis(nodes[1]);
          if FStInkHold and (nodes[1] <> nil) then
          begin
            FStMemoSpecNode := nodes[1];
            FStMemoSpec := spec;
          end;
        end;
        if nodes[0] <> nil then
          spec := TyChartMergeEmphasis(spec, TyChartReadEmphasis(nodes[0]));
        half := (ph^.Shape.Bounds.Bottom - ph^.Shape.Bounds.Top) / 2;
        if ph^.Shape.Kind in [cskCircle, cskEllipse] then half := ph^.Shape.R1;
        { a symbol of no size or a NaN one keeps its size }
        if StPositive(half) then
          TyStSetNum(item^.Host.Decl[stnEmphasis], stkScale,
            TyChartSymbolScaleRatio(spec, half / scale));
      end;
    sskPictorial:
      { emphasis.scale (default false): every glyph a tenth larger about its
        own origin (PictorialBarView.ts:920-924) [Batch 90] }
      if TyStReadBool(nodes, ['emphasis', 'scale'], has) then
        TyStSetNum(item^.Host.Decl[stnEmphasis], stkScale, 1.1);
    { [F2a] A GRAPH'S AND A TREE'S NODE IS A Symbol: emphasis.scale along
      item -> category / leaves -> series over its own half size
      (`this._sizeY`, the symbol size as written, before any view scale) }
    sskGraph, sskTree:
      begin
        if FSt[s].Kind = sskGraph then
        begin
          k := StGraphNodeOfRaw(ASlot, ARaw);
          spec := GraphEmphasisOf(ASlot, False, k);
          half := NaN;
          if k >= 0 then
          begin
            if FGraphNodes[ASlot][k].HasSize then half := FGraphNodes[ASlot][k].SizeH / 2
            else half := FGraphSpecs[ASlot].Symbol.HeightPx / 2;
          end;
        end
        else
        begin
          spec := TreeEmphasisOf(ASlot, ARaw);
          half := (ph^.Shape.Bounds.Bottom - ph^.Shape.Bounds.Top) / 2;
          if ph^.Shape.Kind in [cskCircle, cskEllipse] then half := ph^.Shape.R1;
          if FTrees[ASlot].HasView and StPositive(FTrees[ASlot].VZ * FTrees[ASlot].VNS) then
            half := half / (FTrees[ASlot].VZ * FTrees[ASlot].VNS);
        end;
        if StPositive(half) then
          TyStSetNum(item^.Host.Decl[stnEmphasis], stkScale,
            TyChartSymbolScaleRatio(spec, half));
      end;
  end;

  { ---- the other glyphs: the host's declared states on their own rest
    values; a new one takes the host's list [Batch 90] ---- }
  if Length(item^.Parts) <> Length(FSt[s].PartIdx[ARaw]) then
    SetLength(item^.Parts, 0);
  was := Length(item^.Parts) > 0;
  SetLength(item^.Parts, Length(FSt[s].PartIdx[ARaw]));
  for k := 0 to High(item^.Parts) do
  begin
    item^.Parts[k].Exists := True;
    item^.Parts[k].IsPath := True;
    item^.Parts[k].Proxy := item^.Host.Proxy;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      item^.Parts[k].HasState[n] := True;
      item^.Parts[k].Decl[n] := item^.Host.Decl[n];
    end;
    item^.Parts[k].Rest := StRestOf(AList.Element(FSt[s].PartIdx[ARaw][k]));
    { A LINES END SYMBOL: each state's the line's stroke as its fill (its
      stroke when it is empty) and the line's opacity, where the line's
      state says them; its own proxy lifts and blurs the rest [Batch 121] }
    if FSt[s].Kind = sskLines then
      for n := Low(TTyStName) to High(TTyStName) do
      begin
        obj := TyStNoObject;
        if item^.Host.Decl[n].Has[stkStroke] then
        begin
          if AList.Element(FSt[s].PartIdx[ARaw][k]).Anim.G[10] <> 0 then
            obj.Has[stkStroke] := True
          else
            obj.Has[stkFill] := True;
          if obj.Has[stkStroke] then
          begin
            obj.Color[stkStroke] := item^.Host.Decl[n].Color[stkStroke];
            obj.None[stkStroke] := item^.Host.Decl[n].None[stkStroke];
          end
          else
          begin
            obj.Color[stkFill] := item^.Host.Decl[n].Color[stkStroke];
            obj.None[stkFill] := item^.Host.Decl[n].None[stkStroke];
          end;
        end;
        if item^.Host.Decl[n].Has[stkOpacity] then
          TyStSetNum(obj, stkOpacity, item^.Host.Decl[n].Num[stkOpacity]);
        item^.Parts[k].Decl[n] := obj;
      end;
    { A RADAR ITEM'S OTHER PATHS [F2b] (RadarView.ts:212-229): the polygon
      reads areaStyle and every state its own ignore -- hidden only where
      the polygon is at rest and the state's areaStyle is written nowhere
      (item, series); a symbol reads itemStyle }
    if FSt[s].Kind = sskRadar then
    begin
      pp := AList.Ref(FSt[s].PartIdx[ARaw][k]);
      for n := Low(TTyStName) to High(TTyStName) do
        if pp^.Anim.Role = carRadarArea then
        begin
          obj := TyStReadStyle(nodes, cStNames[n], 'areaStyle', bolder);
          TyStSetNum(obj, stkIgnore, Ord(pp^.Ignore
            and (TyStFind(nodes, [cStNames[n], 'areaStyle']) = nil)));
          item^.Parts[k].Decl[n] := obj;
        end
        else
          item^.Parts[k].Decl[n] := TyStReadStyle(nodes, cStNames[n], 'itemStyle', bolder);
    end;
    if not was then
    begin
      item^.Parts[k].Cur := item^.Parts[k].Rest;
      item^.Parts[k].States := [];
      if item^.Host.States <> [] then
        TyStUseStates(item^.Parts[k], item^.Host.States);
    end;
  end;

  { ---- its label: the host's states, its own select / emphasis / blur
    label style (labelStyle.ts:255-273) ---- }
  idx := FSt[s].LabelIdx[ARaw];
  was := item^.Label_.Exists;
  if (idx < 0) and (FSt[s].Kind = sskPie) then
  begin
    { A PIE ALWAYS OWNS A TEXT (PieView.ts:49-51), hidden when no state shows
      it: it takes its slice's list, a select state of its own (the offset)
      and -- with no emphasis or blur object unless some state's label.show
      created the text's states -- no emphasis lift, but the blur proxy's
      opacity all the same. Nothing of it is drawn. [Batch 90] }
    normalShow := False;
    stShow := False;
    for n := Low(TTyStName) to High(TTyStName) do
      if TyStReadBool(nodes, [cStNames[n], 'label', 'show'], has) and has then
        stShow := True;
    item^.Label_.Exists := True;
    item^.Label_.IsPath := False;
    item^.Label_.Proxy := not disabled;
    item^.Label_.HasState[stnSelect] := True;
    item^.Label_.HasState[stnEmphasis] := stShow;
    item^.Label_.HasState[stnBlur] := stShow;
    obj := TyStNoObject;
    TyStSetNum(obj, stkOpacity, 1);
    TyStSetNum(obj, stkZ2, ph^.Z2 + 2);
    TyStSetNum(obj, stkX, 0);
    TyStSetNum(obj, stkY, 0);
    TyStSetNum(obj, stkR, 0);
    TyStSetNum(obj, stkScale, 1);
    TyStSetNum(obj, stkIgnore, 1);
    item^.Label_.Rest := obj;
    for n := Low(TTyStName) to High(TTyStName) do
      item^.Label_.Decl[n] := TyStNoObject;
    TyStSetNum(item^.Label_.Decl[stnSelect], stkX, dx);
    TyStSetNum(item^.Label_.Decl[stnSelect], stkY, dy);
    if not was then
    begin
      item^.Label_.Cur := item^.Label_.Rest;
      item^.Label_.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Label_, item^.Host.States);
    end;
  end
  else if idx < 0 then
    item^.Label_ := Default(TTyStElement)
  else
  begin
    pc := AList.Ref(idx);
    item^.Label_.Exists := True;
    item^.Label_.IsPath := False;
    item^.Label_.Proxy := not disabled;
    for n := Low(TTyStName) to High(TTyStName) do item^.Label_.HasState[n] := True;
    item^.Label_.Rest := StLabelRestOf(pc^);
    { NORMAL SHOW AS THE LABEL WAS STYLED: hideOverlap hides it later, and
      that is no `show: false` [Batch 103] }
    normalShow := (not pc^.Ignore) or pc^.Caption.LmOverlapHidden;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      obj := TyStNoObject;
      { ignore = !show only when the state's show differs from the normal one }
      stShow := TyStReadBool(nodes, [cStNames[n], 'label', 'show'], has);
      { a themeRiver's model shows the emphasis label unless told
        (ThemeRiverSeries.ts emphasis.label.show) [Batch 118]; a funnel's
        too (FunnelSeries.defaultOption) [F2b]; a graph's by
        GraphSeries.ts emphasis.label.show [F2a] }
      if (n = stnEmphasis) and (FSt[s].Kind in [sskRiver, sskFunnel]) then
        stShow := StEmphLabelShow(nodes, True, has)
      else if (n = stnEmphasis) and (FSt[s].Kind = sskGraph) then
      begin
        stShow := GraphEmLabelShow(nodes[0], nodes[1], nodes[2]);
        has := True;
      end
      else if n = stnEmphasis then
        stShow := StEmphLabelShow(nodes, False, has);
      if has and (stShow <> normalShow) then TyStSetNum(obj, stkIgnore, Ord(not stShow));
      { hideOverlap's hideEl: a label it hid shows again under emphasis,
        unless that state already says (LabelLayoutHelper.ts hideOverlap)
        [Batch 103] }
      if (n = stnEmphasis) and pc^.Caption.LmEmphShow and not obj.Has[stkIgnore] then
        TyStSetNum(obj, stkIgnore, 0);
      txt := TyStReadString(nodes, [cStNames[n], 'label', 'color'], has);
      if has and (txt <> 'inherit') and (txt <> 'auto')
        and TyTryParseChartColor(txt, c) then
        TyStSetColor(obj, stkFill, c);
      { a declared opacity, the blur proxy's tenth otherwise [Batch 90] }
      ss := TyStReadNumber(nodes, [cStNames[n], 'label', 'opacity'], has);
      if has and not IsNan(ss) then TyStSetNum(obj, stkOpacity, ss)
      { a sunburst's label blurs to 0.1 by its series' default }
      else if (n = stnBlur) and (FSt[s].Kind = sskSunburst) then
        TyStSetNum(obj, stkOpacity, 0.1);
      { a pie's label rides with its slice: the laid-out place plus the offset
        (pie/labelLayout.ts:541-544) }
      if (n = stnSelect) and (FSt[s].Kind = sskPie) then
      begin
        TyStSetNum(obj, stkX, pc^.Caption.X + dx);
        TyStSetNum(obj, stkY, pc^.Caption.Y + dy);
      end;
      item^.Label_.Decl[n] := obj;
    end;
    if not was then
    begin
      item^.Label_.Cur := item^.Label_.Rest;
      item^.Label_.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Label_, item^.Host.States);
    end;
  end;

  { ---- a pie's label line: translated with the slice ---- }
  idx := FSt[s].GuideIdx[ARaw];
  was := item^.Guide.Exists;
  if idx < 0 then
    item^.Guide := Default(TTyStElement)
  else
  begin
    pg := AList.Ref(idx);
    item^.Guide.Exists := True;
    item^.Guide.IsPath := False;
    item^.Guide.Proxy := not disabled;
    for n := Low(TTyStName) to High(TTyStName) do item^.Guide.HasState[n] := True;
    item^.Guide.Rest := StGuideRestOf(pg^);
    { setLabelLineStyle: EVERY STATE ITS OWN IGNORE -- hidden where the label
      is, or where the state's labelLine.show (the normal one by default) is
      false -- its smooth (nought unless the state says) and its lineStyle.
      The label as the line was styled: a pie's before hideOverlap (PieView
      styles it; a line hideOverlap hid with its label then comes back with
      it [Batch 103]), any other's after it. [Batch 112] }
    { a pie's and a funnel's labelLine show by default, and their views style
      the line before the label layout runs }
    ownLine := FSt[s].Kind in [sskPie, sskFunnel];
    lineShow := TyStReadBool(nodes, ['labelLine', 'show'], has);
    if not has then lineShow := ownLine;
    { PieSeries / FunnelSeries _defaultLabelLine [F2b]: the series'
      labelLine.show is ANDed with its label.show, and the emphasis one --
      the normal one unless written -- with its emphasis label.show }
    emphLine := lineShow;
    if ownLine then
    begin
      seriesLine := TyStReadBool([nodes[High(nodes)]], ['labelLine', 'show'], has);
      if not has then seriesLine := True;
      emphLine := TyStReadBool([nodes[High(nodes)]], ['emphasis', 'labelLine', 'show'], has);
      if not has then emphLine := seriesLine;
      labShow := TyStReadBool([nodes[High(nodes)]], ['label', 'show'], has);
      if not has then labShow := True;
      { the series' emphasis label.show: written, the funnel's default, else
        the normal one (defaultEmphasis) }
      emphLab := StEmphLabelShow([nodes[High(nodes)]], FSt[s].Kind = sskFunnel, has);
      if not has then emphLab := labShow;
      emphLine := emphLine and emphLab;
      seriesLine := seriesLine and labShow;
      lineShow := TyStReadBool([nodes[0]], ['labelLine', 'show'], has);
      if not has then lineShow := seriesLine;
      stShow := TyStReadBool([nodes[0]], ['emphasis', 'labelLine', 'show'], has);
      if has then emphLine := stShow;
    end;
    labIdx := FSt[s].LabelIdx[ARaw];
    if labIdx >= 0 then
    begin
      pc := AList.Ref(labIdx);
      if ownLine then
        labRest := pc^.Ignore and not pc^.Caption.LmOverlapHidden
      else
        labRest := pc^.Ignore;
    end
    else
      labRest := True;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      obj := TyStNoObject;
      stShow := TyStReadBool(nodes, [cStNames[n], 'labelLine', 'show'], has);
      if not has then stShow := lineShow;
      if ownLine and (n = stnEmphasis) then stShow := emphLine;
      if item^.Label_.Exists and item^.Label_.Decl[n].Has[stkIgnore] then
        labIgn := item^.Label_.Decl[n].Num[stkIgnore] <> 0
      else
        labIgn := labRest;
      TyStSetNum(obj, stkIgnore, Ord(labIgn or not stShow));
      TyStSetNum(obj, stkSmooth,
        TyLabelLineSmoothOf(TyStFind(nodes, [cStNames[n], 'labelLine', 'smooth'])));
      txt := TyStReadString(nodes, [cStNames[n], 'labelLine', 'lineStyle', 'color'], has);
      if has and TyTryParseChartColor(txt, c) then TyStSetColor(obj, stkStroke, c);
      ss := TyStReadNumber(nodes, [cStNames[n], 'labelLine', 'lineStyle', 'width'], has);
      if has and not IsNan(ss) then TyStSetNum(obj, stkLineWidth, ss);
      item^.Guide.Decl[n] := obj;
    end;
    TyStSetNum(item^.Guide.Decl[stnSelect], stkX, dx);
    TyStSetNum(item^.Guide.Decl[stnSelect], stkY, dy);
    if not was then
    begin
      item^.Guide.Cur := item^.Guide.Rest;
      item^.Guide.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Guide, item^.Host.States);
    end;
  end;
end;

{ CandlestickView.setBoxCommon (CandlestickView.ts:298-325): every state
  takes the colour of the candle's sign from its own itemStyle -- color or
  color0, borderColor or borderColor0, the colour again for a missing border
  -- and the emphasis border is 2 wide unless declared
  (CandlestickSeries.ts:130-134) [Batch 90] }
procedure TTyAdvanceChart.StDeclareCandle(ASlot, ARaw: Integer;
  const ANodes: array of TJSONObject; var AHost: TTyStElement);
var
  st: TTyDataStore;
  inner, cO, cC, sign: Integer;
  o, c, prev: Double;
  n: TTyStName;
  fill, stroke: string;
  hasF, hasS: Boolean;
  col: TTyChartColor;
begin
  if (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  inner := st.IndexOfRawIndex(ARaw);
  cO := st.DimIndexOf('open');
  cC := st.DimIndexOf('close');
  if (inner < 0) or (cO < 0) or (cC < 0) then Exit;
  { the sign as the layout gives it: a doji takes the previous close's }
  o := st.Get(cO, inner);
  c := st.Get(cC, inner);
  if o > c then sign := -1
  else if o < c then sign := 1
  else
  begin
    sign := 1;
    if inner > 0 then
    begin
      prev := st.Get(cC, inner - 1);
      if not IsNan(prev) and (prev > c) then sign := -1;
    end;
  end;
  for n := Low(TTyStName) to High(TTyStName) do
  begin
    if sign > 0 then
    begin
      fill := TyStReadString(ANodes, [cStNames[n], 'itemStyle', 'color'], hasF);
      stroke := TyStReadString(ANodes, [cStNames[n], 'itemStyle', 'borderColor'], hasS);
    end
    else
    begin
      fill := TyStReadString(ANodes, [cStNames[n], 'itemStyle', 'color0'], hasF);
      stroke := TyStReadString(ANodes, [cStNames[n], 'itemStyle', 'borderColor0'], hasS);
    end;
    if not hasS then
    begin
      stroke := fill;
      hasS := hasF;
    end;
    if hasF and TyTryParseChartColor(fill, col) then TyStSetColor(AHost.Decl[n], stkFill, col);
    if hasS and TyTryParseChartColor(stroke, col) then TyStSetColor(AHost.Decl[n], stkStroke, col);
  end;
  if not AHost.Decl[stnEmphasis].Has[stkLineWidth] then
    TyStSetNum(AHost.Decl[stnEmphasis], stkLineWidth, 2);
end;

{ A GAUGE'S PROGRESS ARC [F2b]: setStatesStylesFromModel(progress,
  itemModel) and toggleHoverEmphasis with the item's emphasis, z2EmphasisLift
  0 (GaugeView.ts:566-573) -- the pointer's own states, on a dispatcher of
  its own. A render makes it anew: no flag survives a full update. }
procedure TTyAdvanceChart.StDeclarePeer(ASlot, ARaw: Integer; AList: TTyPaintList);
var
  s: Integer;
  item: PTyStItem;
  nodes: TTyStNodeArray;
  has, bolder, was: Boolean;
  n: TTyStName;
begin
  s := FBindings[ASlot].SeriesIndex;
  item := @FSt[s].PeerRows[ARaw];
  nodes := StNodes(s, ARaw);
  was := item^.Host.Exists;
  item^.Host.Exists := True;
  item^.Host.IsPath := True;
  item^.Host.NoEmphLift := True;
  item^.Host.Proxy := not TyStReadBool(nodes, ['emphasis', 'disabled'], has);
  for n := Low(TTyStName) to High(TTyStName) do
  begin
    item^.Host.HasState[n] := True;
    item^.Host.Decl[n] := TyStReadStyle(nodes, cStNames[n], 'itemStyle', bolder);
  end;
  item^.Host.Rest := StRestOf(AList.Element(FSt[s].PeerHostIdx[ARaw]));
  item^.Label_ := Default(TTyStElement);
  item^.Guide := Default(TTyStElement);
  if not was or FStRerender then
  begin
    TyStClearItem(item^);
    item^.Host.Cur := item^.Host.Rest;
    item^.Host.States := [];
    item^.Host.HoverState := TyStHoverNormal;
    item^.Host.HighByOuter := 0;
    item^.Host.Selected := False;
  end;
  TyStApplyItem(item^);
end;

function TTyAdvanceChart.StMarkNode(ASeriesIndex: Integer;
  AKind: TTyChartTargetKind): TJSONObject;
var s: TJSONObject; d: TJSONData;
begin
  Result := nil;
  s := StSeriesNode(ASeriesIndex);
  if s = nil then Exit;
  case AKind of
    ctkMarkPoint: d := s.Find('markPoint');
    ctkMarkLine: d := s.Find('markLine');
  else
    d := s.Find('markArea');
  end;
  if d is TJSONObject then Result := TJSONObject(d);
end;

{ THE MARKERS OF A SERIES [F2b] (MarkerView.ts:77-92, util/states.ts):
  blurSeries hands the series it blurred to every component view, and a
  marker view enters blur on all its elements of those series -- the
  markPoint's Symbol (its path and its words), the markLine's Line (the
  segment, the end symbols, the words), the markArea's polygon and words;
  allLeaveBlur takes them out again. Each element's blur state is its
  model's (`blur.itemStyle`, a markLine's `blur.lineStyle`, the end symbols
  taking that line's stroke and opacity, `blur.label`), under the default
  proxy's tenth of its opacity -- unless the marker's emphasis is disabled:
  no proxy, the declared state alone. Markers have no stateTransition
  (MarkerModel.isAnimationEnabled is false here): the list is written. Their
  own hover and the select / emphasis states stay as they were. }
procedure TTyAdvanceChart.StDeclareMarks(ASeriesIndex: Integer; AList: TTyPaintList);
var
  k: Integer;
  el: TTyChartElement;
  node: TJSONObject;
  nodes: array[0..0] of TJSONObject;
  has, bolder, proxy: Boolean;
  line, obj: TTyStObject;
  ss: Double;
  m: ^TTyStElement;
begin
  SetLength(FSt[ASeriesIndex].Marks, Length(FSt[ASeriesIndex].MarkIdx));
  for k := 0 to High(FSt[ASeriesIndex].MarkIdx) do
  begin
    el := AList.Element(FSt[ASeriesIndex].MarkIdx[k]);
    node := StMarkNode(ASeriesIndex, el.Datum.Kind);
    nodes[0] := node;
    proxy := not TyStReadBool(nodes, ['emphasis', 'disabled'], has);
    m := @FSt[ASeriesIndex].Marks[k];
    begin
      m^ := Default(TTyStElement);
      m^.Exists := True;
      m^.Proxy := proxy;
      m^.HasState[stnBlur] := True;
      obj := TyStNoObject;
      if el.Caption.FontSizeLogical > 0 then
      begin
        m^.IsPath := False;
        m^.Rest := StLabelRestOf(el);
        ss := TyStReadNumber(nodes, ['blur', 'label', 'opacity'], has);
        if has and not IsNan(ss) then TyStSetNum(obj, stkOpacity, ss);
      end
      else
      begin
        m^.IsPath := True;
        m^.Rest := StRestOf(el);
        if el.Datum.Kind = ctkMarkLine then
        begin
          line := TyStReadStyle(nodes, 'blur', 'lineStyle', bolder);
          if el.Anim.Role in [carMarkLineFrom, carMarkLineTo] then
          begin
            { Line.ts:267-290: the line's stroke as the symbol's fill (its
              stroke for an empty one), the line's opacity }
            if line.Has[stkStroke] then
            begin
              if el.Style.HasFill then
              begin
                obj.Has[stkFill] := True;
                obj.Color[stkFill] := line.Color[stkStroke];
                obj.None[stkFill] := line.None[stkStroke];
              end
              else
              begin
                obj.Has[stkStroke] := True;
                obj.Color[stkStroke] := line.Color[stkStroke];
                obj.None[stkStroke] := line.None[stkStroke];
              end;
            end;
            if line.Has[stkOpacity] then TyStSetNum(obj, stkOpacity, line.Num[stkOpacity]);
          end
          else
            obj := line;
        end
        else
          obj := TyStReadStyle(nodes, 'blur', 'itemStyle', bolder);
      end;
      m^.Decl[stnBlur] := obj;
      m^.Cur := m^.Rest;
      m^.States := [];
    end;
  end;
  StApplyMarks(ASeriesIndex);
end;

procedure TTyAdvanceChart.StSyncMarks(AList: TTyPaintList);
var
  s, k: Integer;
  el: TTyChartElement;
  pe: PTyChartElement;
begin
  if AList = nil then Exit;
  for s := 0 to High(FSt) do
  begin
    FSt[s].MarkIdx := nil;
    FSt[s].MarkPart := nil;
  end;
  for k := 0 to AList.Count - 1 do
  begin
    pe := AList.Ref(k);
    if not (pe^.Datum.Kind in [ctkMarkPoint, ctkMarkLine, ctkMarkArea]) then Continue;
    s := pe^.Datum.ComponentIndex;
    if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    StPush(FSt[s].MarkIdx, k);
    SetLength(FSt[s].MarkPart, Length(FSt[s].MarkIdx));
    FSt[s].MarkPart[High(FSt[s].MarkPart)] := StMarkPartOf(pe^);
  end;
  for s := 0 to High(FSt) do
  begin
    if FSt[s].Kind = sskNone then
    begin
      FSt[s].Marks := nil;
      Continue;
    end;
    StDeclareMarks(s, AList);
    { no transition: the list itself -- a state write, journaled [P2] }
    AList.JournalRecord(True);
    try
      for k := 0 to Min(High(FSt[s].MarkIdx), High(FSt[s].Marks)) do
      begin
        if FSt[s].Marks[k].States = [] then Continue;
        el := AList.Element(FSt[s].MarkIdx[k]);
        if FSt[s].Marks[k].IsPath then StWriteHost(el, FSt[s].Marks[k], False)
        else StWriteLabel(el, FSt[s].Marks[k], False);
        AList.SetElement(FSt[s].MarkIdx[k], el);
      end;
    finally
      AList.JournalRecord(False);
    end;
  end;
end;

function TTyAdvanceChart.StApplyMarks(ASeriesIndex: Integer): Boolean;
var k: Integer;
begin
  Result := False;
  for k := 0 to High(FSt[ASeriesIndex].Marks) do
  begin
    if FSt[ASeriesIndex].IsBlured then
      FSt[ASeriesIndex].Marks[k].HoverState := TyStHoverBlur
    else
      FSt[ASeriesIndex].Marks[k].HoverState := TyStHoverNormal;
    if TyStUseStates(FSt[ASeriesIndex].Marks[k],
      TyStTargetStates(FSt[ASeriesIndex].Marks[k])) then Result := True;
  end;
end;

procedure TTyAdvanceChart.StDeclareLine(ASlot: Integer; AList: TTyPaintList);

  procedure One(var AItem: TTyStItem; const AIdx: TTyIntegerArray;
    const ABlock: string);
  var
    s: Integer;
    nodes: array[0..0] of TJSONObject;
    was, has, bolder: Boolean;
    prev: TTyStNames;
    n: TTyStName;
    obj: TTyStObject;
  begin
    if Length(AIdx) = 0 then
    begin
      AItem := Default(TTyStItem);
      Exit;
    end;
    s := FBindings[ASlot].SeriesIndex;
    nodes[0] := StSeriesNode(s);
    was := AItem.Host.Exists;
    prev := AItem.Host.States;
    AItem.Host.Exists := True;
    AItem.Host.IsPath := True;
    AItem.Host.Proxy := not TyStReadBool(nodes, ['emphasis', 'disabled'], has);
    for n := Low(TTyStName) to High(TTyStName) do AItem.Host.HasState[n] := True;
    AItem.Host.Rest := StRestOf(AList.Element(AIdx[0]));
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      obj := TyStReadStyle(nodes, cStNames[n], ABlock, bolder);
      { LineView.ts:844-847: 'bolder' is the rest width plus one }
      if bolder then
        TyStSetNum(obj, stkLineWidth, AItem.Host.Rest.Num[stkLineWidth] + 1);
      AItem.Host.Decl[n] := obj;
    end;
    if not was then
    begin
      AItem.Host.Cur := AItem.Host.Rest;
      AItem.Host.States := [];
    end
    else if FStRerender then
    begin
      TyStClearItem(AItem);
      if prev <> [] then TyStUseStates(AItem.Host, prev);
    end;
    TyStUseStates(AItem.Host, TyStTargetStates(AItem.Host));
  end;

var s: Integer;
begin
  s := FBindings[ASlot].SeriesIndex;
  One(FSt[s].Run, FSt[s].RunIdx, 'lineStyle');
  One(FSt[s].Area, FSt[s].AreaIdx, 'areaStyle');
end;

procedure TTyAdvanceChart.StSync(AList: TTyPaintList; APPI: Integer);
var
  slot, s, k, raw, n, i, hoverS: Integer;
  ed: TTySelData;
  el: TTyChartElement;
  pe: PTyChartElement;
  gel: TTyGfxEl;
  item: PTyStItem;
  prev: TTyStNames;
  was: Boolean;
begin
  if AList = nil then Exit;
  { a full update since the last sync re-renders: rest, the previous list,
    then the flags (echarts.ts:2667-2748) }
  FStRerender := FStBuiltGen <> FStGen;
  FStBuiltGen := FStGen;
  { THE STATES RUN ON PROXIES [Batch 94] where the render animates, or
    where proxies are bound -- a list that waits for its arming is drawn as
    laid out }
  FStProxied := AnimAllowed or ((FAnimSet <> nil) and (FAnimSet.Count > 0)
    and not FAnimPending);
  { renderSeries' clearStates comes before the render: the proxies back to
    normal at once, the lists kept, before an update's animators exist }
  if FStRerender then StAnimClearAll;
  { a notMerge option's first sync: the reused rows keep their records
    [Batch 96] }
  hoverS := -1;
  if FStCarry <> nil then
  begin
    StCarryApply;
    if FStCarryHoverSeries <= -2 then hoverS := -2 - FStCarryHoverSeries;
  end;
  { the render the records were taken for is this one [Batch 99] }
  FStCarryHeld := False;
  n := 0;
  for slot := 0 to High(FBindings) do
    if FBindings[slot].SeriesIndex >= n then n := FBindings[slot].SeriesIndex + 1;
  if Length(FSt) < n then SetLength(FSt, n);
  for s := 0 to High(FSt) do
  begin
    FSt[s].Kind := sskNone;
    FSt[s].HostIdx := nil;
    FSt[s].LabelIdx := nil;
    FSt[s].GuideIdx := nil;
    FSt[s].RunIdx := nil;
    FSt[s].AreaIdx := nil;
    FSt[s].FollowIdx := nil;
    FSt[s].PartIdx := nil;
    FSt[s].EdgeHostIdx := nil;
    FSt[s].EdgeLabelIdx := nil;
    FSt[s].EdgePartIdx := nil;
    FSt[s].PeerHostIdx := nil;
    FSt[s].PeerFollowIdx := nil;
  end;
  for slot := 0 to High(FBindings) do
  begin
    if slot > High(FStores) then Break;
    if FBindings[slot].Hidden then Continue;
    { a sankey's rows are its nodes, whatever its store holds [Batch 114] }
    if (FStores[slot] = nil) and (StKindOf(slot) <> sskSankey) then Continue;
    s := FBindings[slot].SeriesIndex;
    if s < 0 then Continue;
    FSt[s].Kind := StKindOf(slot);
    FSt[s].IsLine := FBindings[slot].SeriesType = 'line';
    if FSt[s].Kind = sskNone then Continue;
    if FSt[s].Kind = sskSankey then
    begin
      if (slot > High(FSankeys)) or not FSankeys[slot].Valid then
      begin
        FSt[s].Kind := sskNone;
        Continue;
      end;
      k := Length(FSankeys[slot].Nodes);
      n := Length(FSankeys[slot].Edges);
      if Length(FSt[s].EdgeRows) < n then SetLength(FSt[s].EdgeRows, n);
      SetLength(FSt[s].EdgeHostIdx, n);
      SetLength(FSt[s].EdgeLabelIdx, n);
      for i := 0 to n - 1 do
      begin
        FSt[s].EdgeHostIdx[i] := -1;
        FSt[s].EdgeLabelIdx[i] := -1;
      end;
    end
    else
      k := FStores[slot].RawCount;
    { A CHORD: its nodes the store's rows, its ribbons by raw link index
      [Batch 120] }
    if FSt[s].Kind = sskChord then
    begin
      if (slot > High(FChords)) or not FChords[slot].Valid then
      begin
        FSt[s].Kind := sskNone;
        Continue;
      end;
      n := Length(FChords[slot].Edges);
      if Length(FSt[s].EdgeRows) < n then SetLength(FSt[s].EdgeRows, n);
      SetLength(FSt[s].EdgeHostIdx, n);
      SetLength(FSt[s].EdgeLabelIdx, n);
      for i := 0 to n - 1 do
      begin
        FSt[s].EdgeHostIdx[i] := -1;
        FSt[s].EdgeLabelIdx[i] := -1;
      end;
    end;
    { [F2a] A GRAPH'S EDGES by their place in the solved list; A TREE'S by
      the node that draws them }
    if FSt[s].Kind in [sskGraph, sskTree] then
    begin
      if FSt[s].Kind = sskGraph then n := Length(FGraphEdges[slot]) else n := k;
      if Length(FSt[s].EdgeRows) < n then SetLength(FSt[s].EdgeRows, n);
      SetLength(FSt[s].EdgeHostIdx, n);
      SetLength(FSt[s].EdgeLabelIdx, n);
      SetLength(FSt[s].EdgePartIdx, n);
      for i := 0 to n - 1 do
      begin
        FSt[s].EdgeHostIdx[i] := -1;
        FSt[s].EdgeLabelIdx[i] := -1;
        FSt[s].EdgePartIdx[i] := nil;
      end;
    end;
    if Length(FSt[s].Rows) < k then SetLength(FSt[s].Rows, k);
    SetLength(FSt[s].HostIdx, k);
    SetLength(FSt[s].LabelIdx, k);
    SetLength(FSt[s].GuideIdx, k);
    SetLength(FSt[s].FollowIdx, k);
    SetLength(FSt[s].PartIdx, k);
    for i := 0 to k - 1 do
    begin
      FSt[s].HostIdx[i] := -1;
      FSt[s].LabelIdx[i] := -1;
      FSt[s].GuideIdx[i] := -1;
    end;
    { a gauge's arcs [F2b] }
    if FSt[s].Kind = sskGauge then
    begin
      if Length(FSt[s].PeerRows) < k then SetLength(FSt[s].PeerRows, k);
      SetLength(FSt[s].PeerHostIdx, k);
      SetLength(FSt[s].PeerFollowIdx, k);
      for i := 0 to k - 1 do FSt[s].PeerHostIdx[i] := -1;
    end;
  end;
  { A SERIES NOT DRAWN HAS NO ELEMENTS: a legend that switched it off took
    its view's group away, and switched back on it is drawn by new elements
    -- no flags, no states (render's `chart.remove`) [Batch 93] }
  for s := 0 to High(FSt) do
    if FSt[s].Kind = sskNone then
    begin
      FSt[s].Rows := nil;
      FSt[s].EdgeRows := nil;
      FSt[s].Run := Default(TTyStItem);
      FSt[s].Area := Default(TTyStItem);
      FSt[s].IsBlured := False;
      FSt[s].PeerRows := nil;
      FSt[s].Marks := nil;
    end;
  { WHICH ELEMENT IS WHICH: the mark, its label (a placed caption), its
    label line, and a line's polyline and area }
  for k := 0 to AList.Count - 1 do
  begin
    pe := AList.Ref(k);
    if pe^.Datum.Kind <> ctkSeries then Continue;
    s := pe^.Datum.SeriesIndex;
    if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    { A SANKEY: its links by link index, its nodes by node index [Batch 114] }
    if FSt[s].Kind = sskSankey then
    begin
      raw := pe^.Datum.DataIndex;
      if pe^.Datum.IsEdge then
      begin
        if (raw < 0) or (raw > High(FSt[s].EdgeHostIdx)) then Continue;
        if pe^.Caption.FontSizeLogical > 0 then
        begin
          if FSt[s].EdgeLabelIdx[raw] < 0 then FSt[s].EdgeLabelIdx[raw] := k;
        end
        else if not pe^.Silent and (FSt[s].EdgeHostIdx[raw] < 0) then
          FSt[s].EdgeHostIdx[raw] := k;
        Continue;
      end;
      if (raw < 0) or (raw > High(FSt[s].HostIdx)) then Continue;
      if pe^.Caption.FontSizeLogical > 0 then
      begin
        if FSt[s].LabelIdx[raw] < 0 then FSt[s].LabelIdx[raw] := k;
      end
      else if not pe^.Silent and (FSt[s].HostIdx[raw] < 0) then
        FSt[s].HostIdx[raw] := k;
      Continue;
    end;
    { [F2a] A GRAPH'S EDGE: its line hosts, its arrows (silent) are parts,
      its caption the label }
    if pe^.Datum.IsEdge and (FSt[s].Kind = sskGraph) then
    begin
      raw := StGraphEdgeOfRow(SlotOfSeries(s), pe^.Datum.DataIndex);
      if (raw < 0) or (raw > High(FSt[s].EdgeHostIdx)) then Continue;
      if pe^.Caption.FontSizeLogical > 0 then
      begin
        if FSt[s].EdgeLabelIdx[raw] < 0 then FSt[s].EdgeLabelIdx[raw] := k;
      end
      else if pe^.Silent then
        StPush(FSt[s].EdgePartIdx[raw], k)
      else if FSt[s].EdgeHostIdx[raw] < 0 then
        FSt[s].EdgeHostIdx[raw] := k;
      Continue;
    end;
    { a chord's ribbon, by its raw link index [Batch 120] }
    if pe^.Datum.IsEdge and (FSt[s].Kind = sskChord) then
    begin
      raw := pe^.Datum.RawDataIndex;
      if (raw < 0) or (raw > High(FSt[s].EdgeHostIdx)) then Continue;
      if (pe^.Caption.FontSizeLogical = 0) and not pe^.Silent
        and (FSt[s].EdgeHostIdx[raw] < 0) then
        FSt[s].EdgeHostIdx[raw] := k;
      Continue;
    end;
    if pe^.Datum.IsEdge then Continue;
    if pe^.Datum.DataIndex < 0 then
    begin
      if not FSt[s].IsLine then Continue;
      if pe^.Shape.Kind = cskPolyline then
      begin
        SetLength(FSt[s].RunIdx, Length(FSt[s].RunIdx) + 1);
        FSt[s].RunIdx[High(FSt[s].RunIdx)] := k;
      end
      else if pe^.Shape.Kind = cskPolygon then
      begin
        SetLength(FSt[s].AreaIdx, Length(FSt[s].AreaIdx) + 1);
        FSt[s].AreaIdx[High(FSt[s].AreaIdx)] := k;
      end;
      Continue;
    end;
    slot := SlotOfSeries(s);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    raw := FStores[slot].GetRawIndex(pe^.Datum.DataIndex);
    if (raw < 0) or (raw > High(FSt[s].HostIdx)) then Continue;
    { A GAUGE: the pointer hosts, the progress arc is the peer, its round
      caps (added just before it) follow it; the title and the reading are
      no label of either -- they have no states [F2b] }
    if FSt[s].Kind = sskGauge then
    begin
      if pe^.Anim.Role = carGaugePointer then
      begin
        if FSt[s].HostIdx[raw] < 0 then FSt[s].HostIdx[raw] := k;
      end
      else if (pe^.Anim.Role = carGaugeProgress) and (FSt[s].PeerHostIdx[raw] < 0) then
      begin
        FSt[s].PeerHostIdx[raw] := k;
        { the end cap rides the arc's end, the start cap is before it }
        if (k >= 1) and (AList.Element(k - 1).Anim.Role = carGaugeCap) then
        begin
          StPush(FSt[s].PeerFollowIdx[raw], k - 1);
          if (k >= 2) and (AList.Element(k - 2).Anim.Role = carNone)
            and (AList.Element(k - 2).Shape.Kind = cskCircle)
            and AList.Element(k - 2).Silent then
            StPush(FSt[s].PeerFollowIdx[raw], k - 2);
        end;
      end;
      Continue;
    end;
    { A RADAR ITEM: its polyline hosts, its polygon and its symbols are
      parts of the same dispatcher, in the order they were built [F2b] }
    if FSt[s].Kind = sskRadar then
    begin
      if pe^.Caption.FontSizeLogical > 0 then Continue;
      if pe^.Anim.Role = carRadarLine then
      begin
        if FSt[s].HostIdx[raw] < 0 then FSt[s].HostIdx[raw] := k;
      end
      else
        StPush(FSt[s].PartIdx[raw], k);
      Continue;
    end;
    { A MAP REGION: the first path of the group is the row's; the geo keeps
      the paths' and the texts' states [Batch 152] }
    if FSt[s].Kind = sskMap then
    begin
      if not pe^.Silent and (pe^.Caption.FontSizeLogical = 0)
        and (FSt[s].HostIdx[raw] < 0) then FSt[s].HostIdx[raw] := k;
      Continue;
    end;
    { A CUSTOM ITEM'S PATHS, in the order its tree draws them: the first
      hosts, the rest are parts with states of their own; a text, an image
      and a textContent take no state here [Batch 123] }
    if FSt[s].Kind = sskCustom then
    begin
      gel := CustomPaintSource(k);
      if (gel = nil) or not gel.StatePath or (gel.Host <> nil) then Continue;
      if FSt[s].HostIdx[raw] < 0 then FSt[s].HostIdx[raw] := k
      else StPush(FSt[s].PartIdx[raw], k);
      Continue;
    end;
    { [F2a] A TREE'S EDGE: under its node's paint order, the node's datum }
    if (FSt[s].Kind = sskTree) and (pe^.Caption.FontSizeLogical = 0)
      and (pe^.Z2 < FTrees[slot].Spec.Z2 + cTyTreeNodeZ2) then
    begin
      if FSt[s].EdgeHostIdx[raw] < 0 then FSt[s].EdgeHostIdx[raw] := k;
      Continue;
    end;
    { [F2a] A TREEMAP'S RECTS: a leaf's content hosts and its background is
      a part, a parent's background hosts; a label is the one its rect
      carries (the content's, a parent's header); a breadcrumb item is no
      row's }
    if FSt[s].Kind = sskTreemap then
    begin
      if pe^.Caption.FontSizeLogical > 0 then
      begin
        i := pe^.Caption.LmHostPlus1 - 1;
        if (i >= 0) and (i < AList.Count) and (AList.Element(i).Anim.Role = carTmRect)
          and (FSt[s].LabelIdx[raw] < 0) then FSt[s].LabelIdx[raw] := k;
      end
      else if pe^.Anim.Role = carTmRect then
      begin
        if (pe^.Anim.Sub = 1) or (pe^.Anim.G[4] = 0) then FSt[s].HostIdx[raw] := k
        else StPush(FSt[s].PartIdx[raw], k);
      end;
      Continue;
    end;
    if pe^.Caption.FontSizeLogical > 0 then
    begin
      if FSt[s].LabelIdx[raw] < 0 then FSt[s].LabelIdx[raw] := k;
    end
    else if pe^.IsGuide then
      FSt[s].GuideIdx[raw] := k
    else if FSt[s].Kind = sskLines then
    begin
      { THE LINE HOSTS, the end symbols after it are parts; the effect
        symbol is no part of the Line group's states [Batch 121] }
      if pe^.Silent then Continue;
      if FSt[s].HostIdx[raw] < 0 then FSt[s].HostIdx[raw] := k
      else StPush(FSt[s].PartIdx[raw], k);
    end
    else if FSt[s].Kind = sskPictorial then
    begin
      { THE GLYPHS ARE THE PATHS, the first the host, the rest parts; the
        inkless bar rect has no states [Batch 90] }
      if pe^.Caption.HostTransparent then Continue;
      if FSt[s].HostIdx[raw] < 0 then FSt[s].HostIdx[raw] := k
      else StPush(FSt[s].PartIdx[raw], k);
    end
    else if FSt[s].Kind = sskCandle then
    begin
      { ONE PATH upstream, body and wicks: the body hosts, the wicks follow
        [Batch 90] }
      if pe^.Silent then Continue;
      if pe^.Anim.Role = carCandleBody then
      begin
        if FSt[s].HostIdx[raw] >= 0 then StPush(FSt[s].FollowIdx[raw], FSt[s].HostIdx[raw]);
        FSt[s].HostIdx[raw] := k;
      end
      else if FSt[s].HostIdx[raw] < 0 then FSt[s].HostIdx[raw] := k
      else StPush(FSt[s].FollowIdx[raw], k);
    end
    else if not pe^.Silent and (FSt[s].HostIdx[raw] < 0) then
      FSt[s].HostIdx[raw] := k;
  end;
  { [F2a] a treemap leaf drawn with no content: its background hosts }
  for s := 0 to High(FSt) do
    if FSt[s].Kind = sskTreemap then
      for raw := 0 to High(FSt[s].HostIdx) do
        if (FSt[s].HostIdx[raw] < 0) and (Length(FSt[s].PartIdx[raw]) > 0) then
        begin
          FSt[s].HostIdx[raw] := FSt[s].PartIdx[raw][0];
          FSt[s].PartIdx[raw] := Copy(FSt[s].PartIdx[raw], 1, Length(FSt[s].PartIdx[raw]) - 1);
        end;
  { the primary ink asked once for every row below (StPrimaryInk), and what
    rows with no object of their own read alike (StDeclareItem) [P2] }
  FStInkHold := True;
  FStInkHeld := False;
  FStMemoOk := False;
  FStMemoSpecNode := nil;
  for slot := 0 to High(FBindings) do
  begin
    s := FBindings[slot].SeriesIndex;
    if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    SelEnsure(slot);
    for raw := 0 to High(FSt[s].Rows) do
    begin
      item := @FSt[s].Rows[raw];
      if (raw > High(FSt[s].HostIdx)) or (FSt[s].HostIdx[raw] < 0) then
      begin
        { gone from the picture: a NEW element if it comes back }
        item^ := Default(TTyStItem);
        Continue;
      end;
      was := item^.Host.Exists;
      prev := item^.Host.States;
      StDeclareItem(slot, raw, AList, APPI);
      if not was then
      begin
        item^.Host.Cur := item^.Host.Rest;
        item^.Host.States := [];
      end
      else if FStRerender then
      begin
        TyStClearItem(item^);
        { A MAP'S REGION GROUPS ARE NEW after a render (MapDraw removes
          them all): no hover is carried, the selection comes back from the
          model below [Batch 152] }
        { [F2b] nor a gauge's: GaugeView makes its pointers and arcs anew
          on every render (createPointer / createProgress in the update) }
        if FSt[s].Kind in [sskMap, sskGauge] then
        begin
          item^.Host.HoverState := TyStHoverNormal;
          item^.Host.HighByOuter := 0;
        end
        else if prev <> [] then TyStUseItemStates(item^, prev);
      end;
    end;
    { updateSeriesElementSelection, then applyElementStates }
    SelSyncFlags(slot);
    for raw := 0 to High(FSt[s].Rows) do
      if FSt[s].Rows[raw].Host.Exists then TyStApplyItem(FSt[s].Rows[raw]);
    if FSt[s].IsLine then StDeclareLine(slot, AList);
    { a sankey's links [Batch 114]; their selection from the series' one
      map [F3a] }
    if FSt[s].Kind = sskSankey then
    begin
      ed := SelEdgeData(slot);
      for raw := 0 to High(FSt[s].EdgeRows) do
        if (raw > High(FSt[s].EdgeHostIdx)) or (FSt[s].EdgeHostIdx[raw] < 0) then
          FSt[s].EdgeRows[raw] := Default(TTyStItem)
        else
        begin
          StDeclareEdge(slot, raw, AList);
          FSt[s].EdgeRows[raw].Host.Selected := (s <= High(FSel)) and FSelInit[s]
            and TySelIsSelected(FSel[s], ed, raw);
          TyStApplyItem(FSt[s].EdgeRows[raw]);
        end;
    end;
    { a chord's ribbons [Batch 120] }
    if FSt[s].Kind = sskChord then
      for raw := 0 to High(FSt[s].EdgeRows) do
        if (raw > High(FSt[s].EdgeHostIdx)) or (FSt[s].EdgeHostIdx[raw] < 0) then
          FSt[s].EdgeRows[raw] := Default(TTyStItem)
        else
          StDeclareChordEdge(slot, raw, AList);
    { [F2a] a graph's edges (their selection from the series' one map) and
      a tree's }
    if FSt[s].Kind in [sskGraph, sskTree] then
    begin
      if FSt[s].Kind = sskGraph then ed := SelEdgeData(slot);
      for raw := 0 to High(FSt[s].EdgeRows) do
        if (raw > High(FSt[s].EdgeHostIdx)) or (FSt[s].EdgeHostIdx[raw] < 0) then
          FSt[s].EdgeRows[raw] := Default(TTyStItem)
        else
        begin
          if FSt[s].Kind = sskGraph then
          begin
            StDeclareGraphEdge(slot, raw, AList);
            i := StGraphEdgeInner(slot, raw);
            FSt[s].EdgeRows[raw].Host.Selected := (s <= High(FSel)) and FSelInit[s]
              and (i >= 0) and TySelIsSelected(FSel[s], ed, i);
          end
          else
            StDeclareTreeEdge(slot, raw, AList);
          TyStApplyItem(FSt[s].EdgeRows[raw]);
        end;
    end;
    { a gauge's arcs [F2b] }
    for raw := 0 to High(FSt[s].PeerRows) do
      if (raw > High(FSt[s].PeerHostIdx)) or (FSt[s].PeerHostIdx[raw] < 0) then
        FSt[s].PeerRows[raw] := Default(TTyStItem)
      else
        StDeclarePeer(slot, raw, AList);
  end;
  FStInkHold := False;
  FStInkHeld := False;
  FStMemoOk := False;
  FStMemoNodes := nil;
  FStMemoSpecNode := nil;
  FStDirty := False;
  { WHAT THE STATES ARE WRITTEN OVER, kept from here to the end of the
    build: a frame whose states alone change puts it back and writes them
    again (StPatchList) [P2] }
  AList.JournalOpen;
  StWrite(AList);
  { THE POINTER STILL OVER A REUSED ELEMENT: zrender's hover target is the
    same element, so the next move sends neither an out nor an over }
  if (hoverS >= 0) and (hoverS <= High(FSt)) and (FSt[hoverS].Kind <> sskNone)
    and (FStCarryHoverRaw <= High(FSt[hoverS].HostIdx))
    and (FSt[hoverS].HostIdx[FStCarryHoverRaw] >= 0) then
  begin
    FEvHover := TargetOfElement(FSt[hoverS].HostIdx[FStCarryHoverRaw]);
    slot := SlotOfSeries(hoverS);
    FEvHover.HdRow := FStores[slot].IndexOfRawIndex(FStCarryHoverRaw);
  end;
end;

procedure TTyAdvanceChart.StCarryTake(const AViewKeys: TTyStringArray);
var
  slot, si: Integer;
  vk: TTyStringArray;
begin
  { ONE TAKE A RENDER: a second setOption before the render finds FSt
    gone already, and the records are still the last render's [Batch 99] }
  if FStCarryHeld then Exit;
  FStCarryHeld := True;
  FStCarry := FSt;
  FStCarryKeys := nil;
  FStCarryHover := False;
  { -2 - the NEW series index once StCarryApply found the hovered row }
  FStCarryHoverSeries := -1;
  FStCarryHoverRaw := -1;
  if Length(FSt) = 0 then Exit;
  vk := AViewKeys;
  SetLength(FStCarryKeys, Length(FSt));
  for slot := 0 to High(FBindings) do
  begin
    si := FBindings[slot].SeriesIndex;
    if (si < 0) or (si > High(FSt)) or FBindings[slot].Hidden then Continue;
    if (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    if FSt[si].Kind = sskNone then Continue;
    FStCarryKeys[si].Present := True;
    if si <= High(vk) then FStCarryKeys[si].ViewKey := vk[si]
    else FStCarryKeys[si].ViewKey := 'x:' + IntToStr(si);
    FStCarryKeys[si].SeriesType := FBindings[slot].SeriesType;
    AnimRowKeys(FStores[slot], FStCarryKeys[si].Keys, FStCarryKeys[si].Raws);
  end;
  { the hovered data item, which the pointer keeps hovering if it is reused }
  if (FEvHover.Id > 0) and (FEvHover.HdKind = 1) then
  begin
    FStCarryHoverSeries := FEvHover.HdSeries;
    FStCarryHoverRaw := StInnerRaw(FEvHover.HdSeries, FEvHover.HdRow);
    FStCarryHover := FStCarryHoverRaw >= 0;
  end;
end;

procedure TTyAdvanceChart.StCarryApply;
var
  slot, s, o, k, n, oldRaw, newRaw: Integer;
  vk, keys: TTyStringArray;
  raws: TTyIntegerArray;
  cmds: TTyDataDiffCmdArray;
begin
  vk := AnimViewKeys;
  n := 0;
  for slot := 0 to High(FBindings) do
    if FBindings[slot].SeriesIndex >= n then n := FBindings[slot].SeriesIndex + 1;
  if Length(FSt) < n then SetLength(FSt, n);
  for slot := 0 to High(FBindings) do
  begin
    s := FBindings[slot].SeriesIndex;
    if (s < 0) or FBindings[slot].Hidden then Continue;
    if (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    { a brand new model asks for a new view: new elements [Batch 99] }
    if (s <= High(FAnimFresh)) and FAnimFresh[s] then Continue;
    { the view upstream keeps: the same model id and type }
    o := -1;
    for k := 0 to High(FStCarryKeys) do
      if FStCarryKeys[k].Present and (k <= High(vk)) and (s <= High(vk))
        and (FStCarryKeys[k].ViewKey = vk[s])
        and (FStCarryKeys[k].SeriesType = FBindings[slot].SeriesType) then
      begin
        o := k;
        Break;
      end;
    if (o < 0) or (o > High(FStCarry)) then Continue;
    AnimRowKeys(FStores[slot], keys, raws);
    cmds := TyDataDiff(FStCarryKeys[o].Keys, keys);
    if Length(FSt[s].Rows) < FStores[slot].RawCount then
      SetLength(FSt[s].Rows, FStores[slot].RawCount);
    for k := 0 to High(cmds) do
    begin
      if cmds[k].Kind <> ddkUpdate then Continue;
      oldRaw := FStCarryKeys[o].Raws[cmds[k].OldIdx];
      newRaw := raws[cmds[k].NewIdx];
      if (oldRaw < 0) or (oldRaw > High(FStCarry[o].Rows)) then Continue;
      if (newRaw < 0) or (newRaw > High(FSt[s].Rows)) then Continue;
      { THE SAME ELEMENT: its flags and its lists }
      FSt[s].Rows[newRaw] := FStCarry[o].Rows[oldRaw];
      if FStCarryHover and (o = FStCarryHoverSeries) and (oldRaw = FStCarryHoverRaw) then
      begin
        { found: re-targeted after the sync }
        FStCarryHover := False;
        FStCarryHoverSeries := -2 - s;
        FStCarryHoverRaw := newRaw;
      end;
    end;
    { a line's polyline and area are kept with the view }
    FSt[s].Run := FStCarry[o].Run;
    FSt[s].Area := FStCarry[o].Area;
  end;
  FStCarryHover := False;
  FStCarry := nil;
  FStCarryKeys := nil;
end;

procedure TTyAdvanceChart.StWrite(AList: TTyPaintList);
begin
  { a state write: journaled, where a build's session is open [P2] }
  AList.JournalRecord(True);
  try
    StWriteRows(AList);
  finally
    AList.JournalRecord(False);
  end;
end;

procedure TTyAdvanceChart.StWriteRows(AList: TTyPaintList);
var
  s, raw, k: Integer;
  el: TTyChartElement;
  item: PTyStItem;
begin
  for s := 0 to High(FSt) do
  begin
    if FSt[s].Kind = sskNone then Continue;
    { a map region's elements are the geo's to write [Batch 152] }
    if FSt[s].Kind = sskMap then Continue;
    for raw := 0 to High(FSt[s].HostIdx) do
    begin
      if FSt[s].HostIdx[raw] < 0 then Continue;
      item := @FSt[s].Rows[raw];
      if item^.Host.States <> [] then
      begin
        el := AList.Element(FSt[s].HostIdx[raw]);
        StWriteHost(el, item^.Host, FStProxied);
        AList.SetElement(FSt[s].HostIdx[raw], el);
        { the rest of the same path: the host's changes [Batch 90] }
        if raw <= High(FSt[s].FollowIdx) then
          for k := 0 to High(FSt[s].FollowIdx[raw]) do
          begin
            el := AList.Element(FSt[s].FollowIdx[raw][k]);
            StWriteFollower(el, item^.Host, FStProxied);
            AList.SetElement(FSt[s].FollowIdx[raw][k], el);
          end;
      end;
      { the other paths, their own values [Batch 90] }
      if raw <= High(FSt[s].PartIdx) then
        for k := 0 to Min(High(FSt[s].PartIdx[raw]), High(item^.Parts)) do
          if item^.Parts[k].States <> [] then
          begin
            el := AList.Element(FSt[s].PartIdx[raw][k]);
            StWriteHost(el, item^.Parts[k], FStProxied);
            AList.SetElement(FSt[s].PartIdx[raw][k], el);
          end;
      if (FSt[s].LabelIdx[raw] >= 0) and item^.Label_.Exists
        and (item^.Label_.States <> []) then
      begin
        el := AList.Element(FSt[s].LabelIdx[raw]);
        StWriteLabel(el, item^.Label_, FStProxied);
        AList.SetElement(FSt[s].LabelIdx[raw], el);
      end;
      if (FSt[s].GuideIdx[raw] >= 0) and item^.Guide.Exists
        and (item^.Guide.States <> []) then
      begin
        el := AList.Element(FSt[s].GuideIdx[raw]);
        StWriteGuide(el, item^.Guide, FStProxied);
        AList.SetElement(FSt[s].GuideIdx[raw], el);
      end;
    end;
    if FSt[s].Run.Host.Exists and (FSt[s].Run.Host.States <> []) then
      for k := 0 to High(FSt[s].RunIdx) do
      begin
        el := AList.Element(FSt[s].RunIdx[k]);
        StWriteHost(el, FSt[s].Run.Host, FStProxied);
        AList.SetElement(FSt[s].RunIdx[k], el);
      end;
    if FSt[s].Area.Host.Exists and (FSt[s].Area.Host.States <> []) then
      for k := 0 to High(FSt[s].AreaIdx) do
      begin
        el := AList.Element(FSt[s].AreaIdx[k]);
        StWriteHost(el, FSt[s].Area.Host, FStProxied);
        AList.SetElement(FSt[s].AreaIdx[k], el);
      end;
    { a gauge's arcs and their caps [F2b] }
    for raw := 0 to Min(High(FSt[s].PeerHostIdx), High(FSt[s].PeerRows)) do
    begin
      if FSt[s].PeerHostIdx[raw] < 0 then Continue;
      item := @FSt[s].PeerRows[raw];
      if item^.Host.States = [] then Continue;
      el := AList.Element(FSt[s].PeerHostIdx[raw]);
      StWriteHost(el, item^.Host, FStProxied);
      AList.SetElement(FSt[s].PeerHostIdx[raw], el);
      for k := 0 to High(FSt[s].PeerFollowIdx[raw]) do
      begin
        el := AList.Element(FSt[s].PeerFollowIdx[raw][k]);
        StWriteFollower(el, item^.Host, FStProxied);
        AList.SetElement(FSt[s].PeerFollowIdx[raw][k], el);
      end;
    end;
    { a sankey's links and their labels [Batch 114] }
    for raw := 0 to Min(High(FSt[s].EdgeHostIdx), High(FSt[s].EdgeRows)) do
    begin
      if FSt[s].EdgeHostIdx[raw] < 0 then Continue;
      item := @FSt[s].EdgeRows[raw];
      if item^.Host.States <> [] then
      begin
        el := AList.Element(FSt[s].EdgeHostIdx[raw]);
        StWriteHost(el, item^.Host, FStProxied);
        AList.SetElement(FSt[s].EdgeHostIdx[raw], el);
      end;
      { a graph edge's arrows, their own values [F2a] }
      if raw <= High(FSt[s].EdgePartIdx) then
        for k := 0 to Min(High(FSt[s].EdgePartIdx[raw]), High(item^.Parts)) do
          if item^.Parts[k].States <> [] then
          begin
            el := AList.Element(FSt[s].EdgePartIdx[raw][k]);
            StWriteHost(el, item^.Parts[k], FStProxied);
            AList.SetElement(FSt[s].EdgePartIdx[raw][k], el);
          end;
      if (FSt[s].EdgeLabelIdx[raw] >= 0) and item^.Label_.Exists
        and (item^.Label_.States <> []) then
      begin
        el := AList.Element(FSt[s].EdgeLabelIdx[raw]);
        StWriteLabel(el, item^.Label_, FStProxied);
        AList.SetElement(FSt[s].EdgeLabelIdx[raw], el);
      end;
    end;
  end;
end;

{ A FRAME WHOSE STATES ALONE CHANGED [P2]: the list back to what the last
  build's state writes went over (its journal), and those writes again --
  StWrite, the breadcrumb's, the maps', the markers' -- in the build's order.
  Not where a geo's flags changed (only TyBuildGeo draws those), a relayout
  or an update is pending, or anything else wrote to the list since the
  build: then it is built again, as before. }
function TTyAdvanceChart.StPatchList: Boolean;
begin
  Result := False;
  if GStPatchOff or FStGeoApplied or (FPaintList = nil) or not FPaintListValid
    or FDirty or FAnimPending or FExporting or not FPaintList.JournalReady then Exit;
  FPaintList.JournalRewind;
  { the incremental layer holds the chunks as they were written: drawn
    again, as after a build [Batch 119] }
  FProgLayerOk := False;
  StWrite(FPaintList);
  TmCrumbStates(FPaintList);
  MapRepatch(FPaintListPPI, True);
  StSyncMarks(FPaintList);
  FPaintList.JournalClose;
  Inc(GStPatches);
  Result := True;
end;

function TTyAdvanceChart.StApplyChanged: Boolean;
var s, raw: Integer;
begin
  Result := False;
  { the geos' flags too [Batch 148] -- which only a build draws [P2] }
  FStGeoApplied := GeoApplyChanged;
  if FStGeoApplied then Result := True;
  { and a map picture's, which are its series' rows' [Batch 152] }
  if MapApplyChanged then Result := True;
  { a breadcrumb item's hover [F2a] }
  if FTmCrumbDirty then Result := True;
  if not FStDirty then Exit;
  FStDirty := False;
  for s := 0 to High(FSt) do
  begin
    if FSt[s].Kind = sskNone then Continue;
    for raw := 0 to High(FSt[s].Rows) do
      if FSt[s].Rows[raw].Host.Exists and TyStApplyItem(FSt[s].Rows[raw]) then
        Result := True;
    if FSt[s].Run.Host.Exists
      and TyStUseStates(FSt[s].Run.Host, TyStTargetStates(FSt[s].Run.Host)) then
      Result := True;
    if FSt[s].Area.Host.Exists
      and TyStUseStates(FSt[s].Area.Host, TyStTargetStates(FSt[s].Area.Host)) then
      Result := True;
    for raw := 0 to High(FSt[s].EdgeRows) do
      if FSt[s].EdgeRows[raw].Host.Exists and TyStApplyItem(FSt[s].EdgeRows[raw]) then
        Result := True;
    { a gauge's arcs and the markers [F2b] }
    for raw := 0 to High(FSt[s].PeerRows) do
      if FSt[s].PeerRows[raw].Host.Exists and TyStApplyItem(FSt[s].PeerRows[raw]) then
        Result := True;
    if StApplyMarks(s) then Result := True;
  end;
end;

{ ==================== state transitions [Batch 94, AN3b] ====================

  updateStates (echarts.ts:2697-2747) gives every element with an emphasis
  state -- and its label and label line -- the series' stateAnimation as its
  stateTransition when the series animates; zrender's useStates then
  transitions the transform keys, the animatable style keys and the shape's
  primitive keys (Anim.pas, TTyAnimElement.UseStates). Here the element is
  its proxy: the role's where upstream's element is the one the enter and
  update animations run on, else one of the states' own. The state machine
  (States.pas) still decides the lists and the merged objects; this turns a
  merged object into the proxy's keys and lets the engine run it. }

const
  { the element kinds a proxy's state keys are seeded for }
  cStPxPath = 0;
  cStPxLabel = 1;
  cStPxGuide = 2;
  cStPxPart = 3;
  cStPxLine = 4;

function StNamesOf(const AText: string): TTyStNames;
var n: TTyStName; parts: TStringArray; i: Integer;
begin
  Result := [];
  parts := AText.Split([',']);
  for i := 0 to High(parts) do
    for n := Low(TTyStName) to High(TTyStName) do
      if parts[i] = cStNames[n] then Include(Result, n);
end;

{ a colour key of a state object as the engine takes it: 'none', null for
  no stroke, a lifted colour as liftColor's rgba() string }
function StColourValue(const AObj: TTyStObject; AKey: TTyStKey): TTyAnimValue;
var d: TJSONData;
begin
  if AObj.None[AKey] then
  begin
    if AKey = stkStroke then Result := TyAnimNull
    else Result := TyAnimStr('none');
  end
  { [F3d] A GRADIENT: the object as written -- its track interpolates it
    against another gradient, and against a colour it is discrete (set at
    once); lifted, every stop (liftColor) }
  else if AObj.GradJson[AKey] <> '' then
  begin
    d := GetJSON(AObj.GradJson[AKey]);
    try
      Result := TyGfxAnimOf(d);
    finally
      d.Free;
    end;
    if AObj.Lifted[AKey] then Result := TyAnimLiftGradient(Result);
  end
  else
    Result := TyAnimColorValue(AObj.Color[AKey], AObj.Lifted[AKey]);
end;

{ A MERGED STATE OBJECT as the proxy's keys: the style keys, and the place,
  the scale and the radius where the proxy carries them }
function StAnimStateOf(const AEl: TTyStElement; const AM: TTyStObject;
  AKind: Integer; P: TTyChartAnimProxy): TTyAnimState;
var
  rx, ry: TTyAnimValue;
  f: Double;
begin
  Result := Default(TTyAnimState);
  { setStatesStylesFromModel gives every state a style object }
  Result.HasStyle := True;
  if AKind = cStPxLabel then
  begin
    { a label's opacity is a factor over its own (as its fade's) -- or, on a
      proxy of the states' own, upstream's [F3a] }
    if AM.Has[stkOpacity] then
    begin
      f := AM.Num[stkOpacity];
      if StPositive(AEl.Rest.Num[stkOpacity]) and not P.StAbsOpacity then
        f := f / AEl.Rest.Num[stkOpacity];
      TyAnimPropPut(Result.Props, 'style.opacity', TyAnimNum(f));
    end;
  end
  else
  begin
    if AM.Has[stkFill] and P.HasStKey('style.fill') then
      TyAnimPropPut(Result.Props, 'style.fill', StColourValue(AM, stkFill));
    if AM.Has[stkStroke] and P.HasStKey('style.stroke') then
      TyAnimPropPut(Result.Props, 'style.stroke', StColourValue(AM, stkStroke));
    if AM.Has[stkLineWidth] and P.HasStKey('style.lineWidth') then
      TyAnimPropPut(Result.Props, 'style.lineWidth', TyAnimNum(AM.Num[stkLineWidth]));
    if AM.Has[stkOpacity] then
      TyAnimPropPut(Result.Props, 'style.opacity', TyAnimNum(AM.Num[stkOpacity]));
  end;
  if AM.Has[stkX] and P.HasStKey('x') then
    TyAnimPropPut(Result.Props, 'x', TyAnimNum(AM.Num[stkX]));
  if AM.Has[stkY] and P.HasStKey('y') then
    TyAnimPropPut(Result.Props, 'y', TyAnimNum(AM.Num[stkY]));
  { Symbol.ts: emphasisState.scaleX = this._sizeX * scaleRatio }
  if AM.Has[stkScale] and P.HasStKey('scaleX') and P.StRestOf('scaleX', rx)
    and P.StRestOf('scaleY', ry) then
  begin
    TyAnimPropPut(Result.Props, 'scaleX', TyAnimNum(rx.Num * AM.Num[stkScale]));
    TyAnimPropPut(Result.Props, 'scaleY', TyAnimNum(ry.Num * AM.Num[stkScale]));
  end;
  { PieView: the emphasis shape is r = layout.r + scaleSize }
  if AM.Has[stkR] and P.HasStKey('shape.r') then
  begin
    TyAnimPropPut(Result.Props, 'shape.r', TyAnimNum(AM.Num[stkR]));
    Result.HasShape := True;
  end;
end;

procedure TTyAdvanceChart.StAnimClearAll;
var
  i: Integer;
  p: TTyChartAnimProxy;
begin
  if FAnimSet = nil then Exit;
  for i := 0 to FAnimSet.Count - 1 do
  begin
    p := FAnimSet.Item(i);
    if p.CurrentStates = '' then Continue;
    { clearStates (echarts.ts:2667-2695): the transition nulled, prevStates
      kept, back to normal without one }
    p.StPrev := p.CurrentStates;
    p.ClearStateTransition;
    p.ClearStates(True);
  end;
end;

function TTyAdvanceChart.StAnimCfg(ASeriesIndex: Integer; out ACfg: TTyAnimCfg): Boolean;
var
  slot, n: Integer;
  model: TTyAnimModel;
  own, root: TJSONObject;
  dur, delay: Double;
  easing: string;

  { stateAnimation.<key>: the series', the root's, the global default }
  function Find(const AKey: string): TJSONData;
  var d: TJSONData;
  begin
    Result := nil;
    if own <> nil then
    begin
      d := own.Find(AKey);
      if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
    end;
    if root <> nil then
    begin
      d := root.Find(AKey);
      if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
    end;
  end;

var d: TJSONData;
begin
  ACfg := Default(TTyAnimCfg);
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  n := 0;
  if (slot >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil) then
    n := FStores[slot].Count;
  model := TyAnimSeriesModel(FOption.Root, ASeriesIndex, n);
  { model.isAnimationEnabled(): `animation` and the threshold }
  if not TyAnimIsEnabled(model) then Exit;
  own := nil;
  root := nil;
  if model.Own is TJSONObject then
  begin
    d := TJSONObject(model.Own).Find('stateAnimation');
    if d is TJSONObject then own := TJSONObject(d);
  end;
  if FOption.Root is TJSONObject then
  begin
    d := TJSONObject(FOption.Root).Find('stateAnimation');
    if d is TJSONObject then root := TJSONObject(d);
  end;
  d := Find('duration');
  if d = nil then dur := 300
  else if d.JSONType = jtNumber then dur := d.AsFloat
  else dur := NaN;
  d := Find('easing');
  if (d <> nil) and (d.JSONType = jtString) then easing := d.AsString
  else easing := 'cubicOut';
  d := Find('delay');
  if (d <> nil) and (d.JSONType = jtNumber) then delay := d.AsFloat
  else delay := 0;
  { a duration above 0 makes a stateTransition, anything else none }
  if IsNan(dur) or not (dur > 0) then Exit;
  ACfg := TyAnimCfg(dur, delay, easing);
  Result := True;
end;

procedure TTyAdvanceChart.StAnimEl(var AEl: TTyStElement; AListIdx, ASeries,
  ARaw: Integer; const AName: string; AKind: Integer; const ACfg: TTyAnimCfg;
  AHasCfg, AOver: Boolean);
var
  el: TTyChartElement;
  p, role: TTyChartAnimProxy;
  isPie: Boolean;
  tmp: TTyStElement;
  want: string;
  noAnim: Boolean;
  st: TTyAnimState;

  { a state key at rest: re-seeded on a full update unless the role's own
    animation holds it }
  procedure Seed(const AKey: string; const AValue: TTyAnimValue);
  begin
    p.StSeed(AKey, AValue, FStRerender and (p.FinalOf(AKey).Kind = avkNull));
  end;

begin
  if (AListIdx < 0) or (AListIdx >= FPaintList.Count) then Exit;
  el := FPaintList.Element(AListIdx);
  role := nil;
  if AListIdx <= High(FAnimBind) then role := FAnimBind[AListIdx];
  { UPSTREAM'S SAME ELEMENT: the proxy its enter and update animations run
    on; anything else (a line symbol's group is not its path, a clip is not
    its polyline) a proxy of the states' own }
  if (role <> nil) and (el.Anim.Role in [carBar, carPolarBar, carSymbol, carSector, carFunnel,
    carCandleBody, carCandleWickHigh, carCandleWickLow, carLabel, carGuide,
    carBoxplot, carTreeNode,
    { [F3a] a gauge's pointer and arc, a radar's polyline and polygon: the
      paths their enter turns and grows }
    carGaugePointer, carGaugeProgress, carRadarLine, carRadarArea,
    { and a graph edge's label, the text its fade runs on }
    carGraphEdgeLabel]) then
    p := role
  else
  begin
    p := FAnimSet.Find(ASeries, ARaw, 'st:' + AName);
    if p = nil then p := FAnimSet.MakeState(ASeries, ARaw, 'st:' + AName);
  end;
  FAnimStBind[AListIdx] := p;
  { a Text's style animates only its opacity }
  p.StatePath := AKind <> cStPxLabel;
  { [F3a] a label on a proxy of the states' own: no fade shares its
    opacity, which is upstream's own }
  p.StAbsOpacity := (AKind = cStPxLabel)
    and ((p <> role) or (el.Anim.Role = carGraphEdgeLabel));
  isPie := FSt[ASeries].Kind = sskPie;
  { ---- the rest values ---- }
  if AKind = cStPxLabel then
  begin
    if p.StAbsOpacity then Seed('style.opacity', TyAnimNum(AEl.Rest.Num[stkOpacity]))
    else Seed('style.opacity', TyAnimNum(1));
    { a pie's label is placed by its layout: x / y are its anchor }
    if isPie then
    begin
      Seed('x', TyAnimNum(AEl.Rest.Num[stkX]));
      Seed('y', TyAnimNum(AEl.Rest.Num[stkY]));
    end;
  end
  else
  begin
    if AKind <> cStPxGuide then
    begin
      Seed('style.fill', StColourValue(AEl.Rest, stkFill));
      Seed('style.stroke', StColourValue(AEl.Rest, stkStroke));
      Seed('style.lineWidth', TyAnimNum(AEl.Rest.Num[stkLineWidth]));
    end;
    Seed('style.opacity', TyAnimNum(AEl.Rest.Num[stkOpacity]));
    if isPie and (AKind in [cStPxPath, cStPxGuide]) then
    begin
      Seed('x', TyAnimNum(0));
      Seed('y', TyAnimNum(0));
    end;
    if isPie and (AKind = cStPxPath) and (el.Shape.Kind = cskSector) then
      Seed('shape.r', TyAnimNum(AEl.Rest.Num[stkR]));
    { a symbol path's scale is half its size; a pictorial glyph's its own }
    if AKind = cStPxPath then
      case el.Anim.Role of
        { [F3a] a graph's node is a carSymbol, a tree's a carTreeNode: the
          Symbol path's own scale, its half size }
        carSymbol, carEffectSymbol, carTreeNode:
          begin
            Seed('scaleX', TyAnimNum(el.Anim.G[2]));
            Seed('scaleY', TyAnimNum(el.Anim.G[3]));
          end;
        carLineSymbol:
          begin
            Seed('scaleX', TyAnimNum(el.Anim.G[7]));
            Seed('scaleY', TyAnimNum(el.Anim.G[8]));
          end;
      else
        { a pictorial glyph's emphasis.scale: a factor over its own scale;
          a graph's and a tree's Symbol path too (the port's factor over the
          size it drew) [F2a] }
        if (FSt[ASeries].Kind in [sskPictorial, sskGraph, sskTree])
          and AEl.Decl[stnEmphasis].Has[stkScale] then
        begin
          Seed('scaleX', TyAnimNum(1));
          Seed('scaleY', TyAnimNum(1));
        end;
      end
    else if (AKind = cStPxPart) and (FSt[ASeries].Kind = sskPictorial)
      and AEl.Decl[stnEmphasis].Has[stkScale] then
    begin
      Seed('scaleX', TyAnimNum(1));
      Seed('scaleY', TyAnimNum(1));
    end;
  end;
  { ---- a full update: the previous list back at once (no transition: the
    render nulled it), the merged object made on the new element ---- }
  if p.StPrev <> '' then
  begin
    tmp := AEl;
    tmp.Cur := tmp.Rest;
    tmp.States := [];
    TyStUseStates(tmp, StNamesOf(p.StPrev));
    p.UseStates(p.StPrev, StAnimStateOf(tmp, tmp.Merged, AKind, p), True);
    p.StPrev := '';
  end;
  { ---- the series' stateTransition, only when it animates ---- }
  if AHasCfg then p.SetStateTransition(ACfg) else p.ClearStateTransition;
  want := TyStNamesText(AEl.States);
  if want = p.CurrentStates then Exit;
  { no timer, no transition; and an element in the hover layer has none }
  noAnim := not AnimAllowed or (AOver and ((Pos('emphasis', want) > 0)
    or (Pos('emphasis', p.CurrentStates) > 0)));
  if want = '' then p.ClearStates(noAnim)
  else
  begin
    st := StAnimStateOf(AEl, AEl.Merged, AKind, p);
    p.UseStates(want, st, noAnim);
    { a pie label's select place, for the next update's move from it }
    if (AKind = cStPxLabel) and (stnSelect in AEl.States)
      and (TyAnimPropIndex(st.Props, 'x') >= 0) and (TyAnimPropIndex(st.Props, 'y') >= 0) then
      p.StNoteSelect(st.Props[TyAnimPropIndex(st.Props, 'x')].Value.Num,
        st.Props[TyAnimPropIndex(st.Props, 'y')].Value.Num);
  end;
end;

procedure TTyAdvanceChart.StAnimSync;
var
  s, raw, k, clips: Integer;
  item: PTyStItem;
  cfg: TTyAnimCfg;
  hasCfg, over: Boolean;
  hostP: TTyChartAnimProxy;
  d: TJSONData;
  threshold: Double;
begin
  if not FStProxied or (FPaintList = nil) then Exit;
  if FAnim = nil then FAnim := NewAnimDriver;
  if FAnimSet = nil then FAnimSet := TTyChartAnimSet.Create(FAnim);
  SetLength(FAnimStBind, FPaintList.Count);
  for k := 0 to High(FAnimStBind) do FAnimStBind[k] := nil;
  clips := FAnim.ClipCount;
  { THE HOVER LAYER: past hoverLayerThreshold elements upstream's canvas
    hovers an element in a layer of its own, where it never transitions
    (canTransition, __inHover) }
  threshold := 3000;
  if FOption.Root is TJSONObject then
  begin
    d := TJSONObject(FOption.Root).Find('hoverLayerThreshold');
    if (d <> nil) and (d.JSONType = jtNumber) then threshold := d.AsFloat;
  end;
  over := FPaintList.Count > threshold;
  for s := 0 to High(FSt) do
  begin
    if FSt[s].Kind = sskNone then Continue;
    hasCfg := StAnimCfg(s, cfg);
    for raw := 0 to High(FSt[s].HostIdx) do
    begin
      if FSt[s].HostIdx[raw] < 0 then Continue;
      if raw > High(FSt[s].Rows) then Continue;
      item := @FSt[s].Rows[raw];
      if not item^.Host.Exists then Continue;
      StAnimEl(item^.Host, FSt[s].HostIdx[raw], s, raw, 'host', cStPxPath,
        cfg, hasCfg, over);
      { the rest of the same path: the host's proxy }
      hostP := FAnimStBind[FSt[s].HostIdx[raw]];
      if raw <= High(FSt[s].FollowIdx) then
        for k := 0 to High(FSt[s].FollowIdx[raw]) do
          FAnimStBind[FSt[s].FollowIdx[raw][k]] := hostP;
      if raw <= High(FSt[s].PartIdx) then
        for k := 0 to Min(High(FSt[s].PartIdx[raw]), High(item^.Parts)) do
          StAnimEl(item^.Parts[k], FSt[s].PartIdx[raw][k], s, raw,
            'part' + IntToStr(k), cStPxPart, cfg, hasCfg, over);
      if (FSt[s].LabelIdx[raw] >= 0) and item^.Label_.Exists then
        StAnimEl(item^.Label_, FSt[s].LabelIdx[raw], s, raw, 'label', cStPxLabel,
          cfg, hasCfg, over);
      if (FSt[s].GuideIdx[raw] >= 0) and item^.Guide.Exists then
        StAnimEl(item^.Guide, FSt[s].GuideIdx[raw], s, raw, 'guide', cStPxGuide,
          cfg, hasCfg, over);
    end;
    { A GAUGE'S ARC: its own proxy, its caps drawn from it [F2b] }
    for raw := 0 to Min(High(FSt[s].PeerHostIdx), High(FSt[s].PeerRows)) do
      if (FSt[s].PeerHostIdx[raw] >= 0) and FSt[s].PeerRows[raw].Host.Exists then
      begin
        StAnimEl(FSt[s].PeerRows[raw].Host, FSt[s].PeerHostIdx[raw], s, raw,
          'peer', cStPxPath, cfg, hasCfg, over);
        hostP := FAnimStBind[FSt[s].PeerHostIdx[raw]];
        for k := 0 to High(FSt[s].PeerFollowIdx[raw]) do
          FAnimStBind[FSt[s].PeerFollowIdx[raw][k]] := hostP;
      end;
    { [F3a] A SANKEY'S BANDS and their labels: states of their own, each its
      own proxy (the main group's clip is their role) }
    if FSt[s].Kind = sskSankey then
      for raw := 0 to Min(High(FSt[s].EdgeHostIdx), High(FSt[s].EdgeRows)) do
      begin
        if (FSt[s].EdgeHostIdx[raw] < 0) or not FSt[s].EdgeRows[raw].Host.Exists then Continue;
        item := @FSt[s].EdgeRows[raw];
        StAnimEl(item^.Host, FSt[s].EdgeHostIdx[raw], s, raw, 'edge', cStPxPath,
          cfg, hasCfg, over);
        if (raw <= High(FSt[s].EdgeLabelIdx)) and (FSt[s].EdgeLabelIdx[raw] >= 0)
          and item^.Label_.Exists then
          StAnimEl(item^.Label_, FSt[s].EdgeLabelIdx[raw], s, raw, 'edgelabel', cStPxLabel,
            cfg, hasCfg, over);
      end;
    { A CHORD'S RIBBONS have states of their own, each its own proxy
      (the series' view group is their role) [Batch 120] }
    if FSt[s].Kind = sskChord then
      for raw := 0 to Min(High(FSt[s].EdgeHostIdx), High(FSt[s].EdgeRows)) do
        if (FSt[s].EdgeHostIdx[raw] >= 0) and FSt[s].EdgeRows[raw].Host.Exists then
          StAnimEl(FSt[s].EdgeRows[raw].Host, FSt[s].EdgeHostIdx[raw], s, raw,
            'edge', cStPxPath, cfg, hasCfg, over);
    { [F2a] A GRAPH'S EDGES (the Line group's path, its arrows, its label)
      and A TREE'S (the edge path): states of their own, proxies of their
      own -- their stateTransition the series' as every other element's }
    if FSt[s].Kind in [sskGraph, sskTree] then
      for raw := 0 to Min(High(FSt[s].EdgeHostIdx), High(FSt[s].EdgeRows)) do
      begin
        if (FSt[s].EdgeHostIdx[raw] < 0) or not FSt[s].EdgeRows[raw].Host.Exists then Continue;
        item := @FSt[s].EdgeRows[raw];
        StAnimEl(item^.Host, FSt[s].EdgeHostIdx[raw], s, raw, 'edge', cStPxPath,
          cfg, hasCfg, over);
        if raw <= High(FSt[s].EdgePartIdx) then
          for k := 0 to Min(High(FSt[s].EdgePartIdx[raw]), High(item^.Parts)) do
            StAnimEl(item^.Parts[k], FSt[s].EdgePartIdx[raw][k], s, raw,
              'edgepart' + IntToStr(k), cStPxPart, cfg, hasCfg, over);
        if (FSt[s].EdgeLabelIdx[raw] >= 0) and item^.Label_.Exists then
          StAnimEl(item^.Label_, FSt[s].EdgeLabelIdx[raw], s, raw, 'edgelabel', cStPxLabel,
            cfg, hasCfg, over);
      end;
    { a line's polyline and area: one element each upstream, its runs here }
    if FSt[s].Run.Host.Exists and (Length(FSt[s].RunIdx) > 0) then
    begin
      StAnimEl(FSt[s].Run.Host, FSt[s].RunIdx[0], s, -1, 'poly', cStPxLine,
        cfg, hasCfg, over);
      for k := 1 to High(FSt[s].RunIdx) do
        FAnimStBind[FSt[s].RunIdx[k]] := FAnimStBind[FSt[s].RunIdx[0]];
    end;
    if FSt[s].Area.Host.Exists and (Length(FSt[s].AreaIdx) > 0) then
    begin
      StAnimEl(FSt[s].Area.Host, FSt[s].AreaIdx[0], s, -1, 'area', cStPxLine,
        cfg, hasCfg, over);
      for k := 1 to High(FSt[s].AreaIdx) do
        FAnimStBind[FSt[s].AreaIdx[k]] := FAnimStBind[FSt[s].AreaIdx[0]];
    end;
  end;
  { A TRANSITION BEGAN: the series go to the dynamic layer until it ends
    (an armed option's flush decides that itself) }
  if (FAnim.ClipCount > clips) and not FAnimFlush then
  begin
    FAnimLive := True;
    FAnimContinuous := AnimLoopOnly;
    AnimArmTimer;
  end;
end;

function TTyAdvanceChart.StPeerAt(ASeriesIndex, AInnerRow: Integer): PTyStItem;
var raw: Integer;
begin
  Result := nil;
  raw := StInnerRaw(ASeriesIndex, AInnerRow);
  if (raw < 0) or (ASeriesIndex > High(FSt)) then Exit;
  if (raw > High(FSt[ASeriesIndex].PeerRows)) or not FSt[ASeriesIndex].PeerRows[raw].Host.Exists then Exit;
  Result := @FSt[ASeriesIndex].PeerRows[raw];
end;

function TTyAdvanceChart.StItemAt(ASeriesIndex, AInnerRow: Integer): PTyStItem;
var slot, raw: Integer;
begin
  Result := nil;
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSt)) then Exit;
  if FSt[ASeriesIndex].Kind = sskNone then Exit;
  slot := SlotOfSeries(ASeriesIndex);
  if FSt[ASeriesIndex].Kind = sskSankey then
    raw := AInnerRow
  else
  begin
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
    if (AInnerRow < 0) or (AInnerRow >= FStores[slot].Count) then Exit;
    raw := FStores[slot].GetRawIndex(AInnerRow);
  end;
  if (raw < 0) or (raw > High(FSt[ASeriesIndex].Rows)) then Exit;
  if not FSt[ASeriesIndex].Rows[raw].Host.Exists then Exit;
  Result := @FSt[ASeriesIndex].Rows[raw];
end;

{ ---- focus and blur [Batch 90] ---- }

function TTyAdvanceChart.StPolyOf(ASeriesIndex: Integer): Integer;
begin
  Result := -1;
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSt)) then Exit;
  if FSt[ASeriesIndex].IsLine and FSt[ASeriesIndex].Run.Host.Exists then
    Result := FSt[ASeriesIndex].Run.Host.HoverState;
end;

{ LineView._changePolyState: setStatesFlag on the polyline and the area }
procedure TTyAdvanceChart.StPolyTo(ASeriesIndex, AState: Integer);
begin
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSt)) then Exit;
  if not FSt[ASeriesIndex].IsLine then Exit;
  FSt[ASeriesIndex].Run.Host.HoverState := AState;
  FSt[ASeriesIndex].Area.Host.HoverState := AState;
  FStDirty := True;
end;

function TTyAdvanceChart.StCoordKey(ASlot: Integer): string;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  { coordinateSystem.master: a cartesian's is its GRID, so two axis pairs
    of one grid are one system }
  if FBindings[ASlot].Cart <> nil then
  begin
    if FBindings[ASlot].XAxis <> nil then
      Result := 'grid' + IntToStr(FBindings[ASlot].XAxis.GridIndex)
    else
      Result := 'cart' + IntToStr(PtrUInt(FBindings[ASlot].Cart));
  end
  else if FBindings[ASlot].Polar <> nil then
    { a polar is its own master [Batch 113] }
    Result := 'polar' + IntToStr(FBindings[ASlot].PolarIndex)
  { a single axis is too [Batch 118] }
  else if FBindings[ASlot].Single <> nil then
    Result := 'single' + IntToStr(FBindings[ASlot].SingleIndex)
  else if FBindings[ASlot].CalendarIndex >= 0 then
    Result := 'calendar' + IntToStr(FBindings[ASlot].CalendarIndex)
  else if FBindings[ASlot].MatrixIndex >= 0 then
    Result := 'matrix' + IntToStr(FBindings[ASlot].MatrixIndex)
  { the geo component [Batch 152] }
  else if FBindings[ASlot].GeoIndex >= 0 then
    Result := 'geo' + IntToStr(FBindings[ASlot].GeoIndex)
  else if FBindings[ASlot].RadarIndex >= 0 then
    Result := 'radar' + IntToStr(FBindings[ASlot].RadarIndex)
  { the parallel the series is on [Batch 128] }
  else if FBindings[ASlot].ParallelIndex >= 0 then
    Result := 'parallel' + IntToStr(FBindings[ASlot].ParallelIndex);
end;

{ an item's model chain: the item, a sunburst row's level, the series }
function TTyAdvanceChart.StNodes(ASeriesIndex, ARaw: Integer): TTyStNodeArray;
var slot, d: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FSunbursts)) and FSunbursts[slot].Valid
    and (ARaw >= 0) and (ARaw <= High(FSunbursts[slot].Hier.Nodes)) then
  begin
    SetLength(Result, 3);
    Result[0] := StItemNode(ASeriesIndex, ARaw);
    d := FSunbursts[slot].Hier.Nodes[ARaw].Depth;
    Result[1] := nil;
    if (d >= 0) and (d <= High(FSunbursts[slot].Levels)) then
      Result[1] := FSunbursts[slot].Levels[d];
    Result[2] := StSeriesNode(ASeriesIndex);
    Exit;
  end;
  { A SANKEY NODE'S CHAIN: its item, the level of its layout depth, the
    series (SankeySeries' wrapped getItemModel) [Batch 114] }
  if (slot >= 0) and (slot <= High(FSankeys)) and FSankeys[slot].Valid
    and (FBindings[slot].SeriesType = TySankeySeriesTypeName) then
  begin
    SetLength(Result, 3);
    Result[0] := nil;
    Result[1] := nil;
    if (ARaw >= 0) and (ARaw <= High(FSankeys[slot].Nodes)) then
    begin
      Result[0] := FSankeys[slot].Nodes[ARaw].Item;
      Result[1] := TySankeyLevel(FSankeys[slot], FSankeys[slot].Nodes[ARaw].Depth);
    end;
    Result[2] := StSeriesNode(ASeriesIndex);
    Exit;
  end;
  { [F2a] A GRAPH NODE'S CHAIN: its item, the category it names by index,
    the series (GraphSeries' wrapped getItemModel) }
  if (slot >= 0) and (FBindings[slot].SeriesType = TyGraphSeriesTypeName) then
  begin
    SetLength(Result, 3);
    Result[0] := StItemNode(ASeriesIndex, ARaw);
    Result[1] := nil;
    d := StGraphNodeOfRaw(slot, ARaw);
    if d >= 0 then Result[1] := GraphCategoryNode(slot, FGraphNodes[slot][d].ModelCategory);
    Result[2] := StSeriesNode(ASeriesIndex);
    Exit;
  end;
  { A TREE NODE'S: its item, `leaves` for a leaf-modelled one, the series }
  if (slot >= 0) and (FBindings[slot].SeriesType = TyTreeSeriesTypeName)
    and (slot <= High(FTrees)) and FTrees[slot].Valid then
  begin
    SetLength(Result, 3);
    Result[0] := StItemNode(ASeriesIndex, ARaw);
    Result[1] := nil;
    if (ARaw >= 0) and (ARaw <= High(FTrees[slot].LeafModelled))
      and FTrees[slot].LeafModelled[ARaw] then Result[1] := FTrees[slot].Spec.Leaves;
    Result[2] := StSeriesNode(ASeriesIndex);
    Exit;
  end;
  { A TREEMAP NODE'S: its item, the level of its depth, the series }
  if (slot >= 0) and (FBindings[slot].SeriesType = TyTreemapSeriesTypeName)
    and (slot <= High(FTreemaps)) and FTreemaps[slot].Valid then
  begin
    SetLength(Result, 3);
    Result[0] := StItemNode(ASeriesIndex, ARaw);
    Result[1] := nil;
    if (ARaw >= 0) and (ARaw <= High(FTreemaps[slot].Hier.Nodes)) then
    begin
      d := FTreemaps[slot].Hier.Nodes[ARaw].Depth;
      if (d >= 0) and (d <= High(FTreemaps[slot].Levels)) then
        Result[1] := FTreemaps[slot].Levels[d];
    end;
    Result[2] := StSeriesNode(ASeriesIndex);
    Exit;
  end;
  SetLength(Result, 2);
  Result[0] := StItemNode(ASeriesIndex, ARaw);
  Result[1] := StSeriesNode(ASeriesIndex);
end;

{ A SANKEY LINK'S CHAIN: its item, the level of its SOURCE's depth, the
  series [Batch 114] }
function TTyAdvanceChart.StEdgeNodes(ASeriesIndex, AEdge: Integer): TTyStNodeArray;
var slot: Integer; sNode: TJSONObject; links: TJSONData;
begin
  Result := nil;
  SetLength(Result, 3);
  slot := SlotOfSeries(ASeriesIndex);
  { [F2a] A GRAPH EDGE'S CHAIN: its link, the series }
  if (slot >= 0) and (FBindings[slot].SeriesType = TyGraphSeriesTypeName)
    and (slot <= High(FGraphEdges)) then
  begin
    sNode := StSeriesNode(ASeriesIndex);
    Result[2] := sNode;
    if (sNode = nil) or (AEdge < 0) or (AEdge > High(FGraphEdges[slot])) then Exit;
    links := sNode.Find('edges');
    if (links = nil) or (links.JSONType = jtNull) then links := sNode.Find('links');
    if (links is TJSONArray) and (FGraphEdges[slot][AEdge].Row >= 0)
      and (FGraphEdges[slot][AEdge].Row < links.Count)
      and (TJSONArray(links).Items[FGraphEdges[slot][AEdge].Row] is TJSONObject) then
      Result[0] := TJSONObject(TJSONArray(links).Items[FGraphEdges[slot][AEdge].Row]);
    Exit;
  end;
  { A CHORD LINK'S CHAIN: its item, the series (no levels) [Batch 120] }
  if (slot >= 0) and (slot <= High(FChords)) and FChords[slot].Valid then
  begin
    if (AEdge >= 0) and (AEdge <= High(FChords[slot].Edges)) then
      Result[0] := FChords[slot].Edges[AEdge].Item;
    Result[2] := StSeriesNode(ASeriesIndex);
    Exit;
  end;
  if (slot >= 0) and (slot <= High(FSankeys)) and FSankeys[slot].Valid
    and (AEdge >= 0) and (AEdge <= High(FSankeys[slot].Edges)) then
  begin
    Result[0] := FSankeys[slot].Edges[AEdge].Item;
    Result[1] := TySankeyLevel(FSankeys[slot],
      FSankeys[slot].Nodes[FSankeys[slot].Edges[AEdge].Source].Depth);
  end;
  Result[2] := StSeriesNode(ASeriesIndex);
end;

function TTyAdvanceChart.StIsSankey(ASeriesIndex: Integer): Boolean;
begin
  Result := (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt))
    and (FSt[ASeriesIndex].Kind = sskSankey);
end;

function TTyAdvanceChart.StIsChord(ASeriesIndex: Integer): Boolean;
begin
  Result := (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt))
    and (FSt[ASeriesIndex].Kind = sskChord);
end;

function TTyAdvanceChart.StHasEdges(ASeriesIndex: Integer): Boolean;
begin
  Result := StIsSankey(ASeriesIndex) or StIsChord(ASeriesIndex)
    { a graph's edge data [F2a] }
    or ((ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt))
      and (FSt[ASeriesIndex].Kind = sskGraph));
end;

{ ONE CHORD RIBBON INTO THE STATE MACHINE [Batch 120]: a path whose states
  are setStatesStylesFromModel(el, edgeModel, 'lineStyle') -- getLineStyle
  of [state].lineStyle along link -> series: the colour a STROKE, the width
  its width -- the series' emphasis opacity 0.5 under what is declared. It
  has no label. }
procedure TTyAdvanceChart.StDeclareChordEdge(ASlot, AEdge: Integer; AList: TTyPaintList);
var
  s: Integer;
  item: PTyStItem;
  ph: PTyChartElement;
  nodes: TTyStNodeArray;
  has, bolder, disabled, prevWas: Boolean;
  prev: TTyStNames;
  n: TTyStName;
begin
  s := FBindings[ASlot].SeriesIndex;
  item := @FSt[s].EdgeRows[AEdge];
  ph := AList.Ref(FSt[s].EdgeHostIdx[AEdge]);
  nodes := StEdgeNodes(s, AEdge);
  prevWas := item^.Host.Exists;
  prev := item^.Host.States;
  item^.Host.Exists := True;
  item^.Host.IsPath := True;
  disabled := TyStReadBool(nodes, ['emphasis', 'disabled'], has);
  item^.Host.Proxy := not disabled;
  for n := Low(TTyStName) to High(TTyStName) do item^.Host.HasState[n] := True;
  item^.Host.Rest := StRestOf(ph^);
  for n := Low(TTyStName) to High(TTyStName) do
    item^.Host.Decl[n] := TyStReadStyle(nodes, cStNames[n], 'lineStyle', bolder);
  { ChordSeries' defaultOption: emphasis.lineStyle.opacity 0.5 }
  if not item^.Host.Decl[stnEmphasis].Has[stkOpacity] then
    TyStSetNum(item^.Host.Decl[stnEmphasis], stkOpacity, 0.5);
  item^.Label_ := Default(TTyStElement);
  if not prevWas then
  begin
    item^.Host.Cur := item^.Host.Rest;
    item^.Host.States := [];
  end
  else if FStRerender then
  begin
    TyStClearItem(item^);
    if prev <> [] then TyStUseItemStates(item^, prev);
  end;
  TyStApplyItem(item^);
end;

function TTyAdvanceChart.EdgeStates(ASeriesIndex, AIndex: Integer;
  out AItem: TTyStItem): Boolean;
begin
  AItem := Default(TTyStItem);
  Result := (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt)) and (AIndex >= 0)
    and (AIndex <= High(FSt[ASeriesIndex].EdgeRows))
    and FSt[ASeriesIndex].EdgeRows[AIndex].Host.Exists;
  if Result then AItem := FSt[ASeriesIndex].EdgeRows[AIndex];
end;

function TTyAdvanceChart.ChordEdgeStates(ASeriesIndex, AEdge: Integer;
  out AItem: TTyStItem): Boolean;
begin
  AItem := Default(TTyStItem);
  Result := StIsChord(ASeriesIndex) and (AEdge >= 0)
    and (AEdge <= High(FSt[ASeriesIndex].EdgeRows))
    and FSt[ASeriesIndex].EdgeRows[AEdge].Host.Exists;
  if Result then AItem := FSt[ASeriesIndex].EdgeRows[AEdge];
end;

{ applyCurveStyle on a state's style: 'source' / 'target' take that end
  node's colour [Batch 114] }
procedure TTyAdvanceChart.StSankeyCurveFill(ASlot, AEdge: Integer;
  const ANodes: TTyStNodeArray; const AState: string; var AObj: TTyStObject);
var w: string; has: Boolean; n: Integer;
begin
  w := TyStReadString(ANodes, [AState, 'lineStyle', 'color'], has);
  if not has then Exit;
  if (w <> 'source') and (w <> 'target') then Exit;
  if w = 'source' then n := FSankeys[ASlot].Edges[AEdge].Source
  else n := FSankeys[ASlot].Edges[AEdge].Target;
  if FSankeys[ASlot].Nodes[n].HasColour then
    TyStSetColor(AObj, stkFill, FSankeys[ASlot].Nodes[n].Colour);
end;

{ ONE SANKEY LINK INTO THE STATE MACHINE [Batch 114]: the band a path whose
  states are setStatesStylesFromModel(curve, edgeModel, 'lineStyle') --
  getItemStyle of [state].lineStyle, the words through applyCurveStyle --
  the series' emphasis opacity 0.5 under what is declared; its label the
  band's list. }
procedure TTyAdvanceChart.StDeclareEdge(ASlot, AEdge: Integer; AList: TTyPaintList);
var
  s, idx: Integer;
  item: PTyStItem;
  cap: TTyChartElement;
  ph: PTyChartElement;
  nodes: TTyStNodeArray;
  has, bolder, disabled, was, prevWas: Boolean;
  prev: TTyStNames;
  n: TTyStName;
  ss: Double;
  obj: TTyStObject;
begin
  s := FBindings[ASlot].SeriesIndex;
  item := @FSt[s].EdgeRows[AEdge];
  ph := AList.Ref(FSt[s].EdgeHostIdx[AEdge]);
  nodes := StEdgeNodes(s, AEdge);
  prevWas := item^.Host.Exists;
  prev := item^.Host.States;
  item^.Host.Exists := True;
  item^.Host.IsPath := True;
  disabled := TyStReadBool(nodes, ['emphasis', 'disabled'], has);
  item^.Host.Proxy := not disabled;
  for n := Low(TTyStName) to High(TTyStName) do item^.Host.HasState[n] := True;
  item^.Host.Rest := StRestOf(ph^);
  for n := Low(TTyStName) to High(TTyStName) do
  begin
    obj := TyStReadStyle(nodes, cStNames[n], 'lineStyle:item', bolder);
    StSankeyCurveFill(ASlot, AEdge, nodes, cStNames[n], obj);
    item^.Host.Decl[n] := obj;
  end;
  { SankeySeries' defaultOption: emphasis.lineStyle.opacity 0.5 }
  if not item^.Host.Decl[stnEmphasis].Has[stkOpacity] then
    TyStSetNum(item^.Host.Decl[stnEmphasis], stkOpacity, 0.5);
  { the label: the band's list, the blur proxy's tenth }
  idx := FSt[s].EdgeLabelIdx[AEdge];
  was := item^.Label_.Exists;
  if idx < 0 then
    item^.Label_ := Default(TTyStElement)
  else
  begin
    cap := AList.Element(idx);
    item^.Label_.Exists := True;
    item^.Label_.IsPath := False;
    item^.Label_.Proxy := not disabled;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      item^.Label_.HasState[n] := True;
      obj := TyStNoObject;
      ss := TyStReadNumber(nodes, [cStNames[n], 'edgeLabel', 'opacity'], has);
      if has and not IsNan(ss) then TyStSetNum(obj, stkOpacity, ss);
      item^.Label_.Decl[n] := obj;
    end;
    item^.Label_.Rest := StLabelRestOf(cap);
    if not was then
    begin
      item^.Label_.Cur := item^.Label_.Rest;
      item^.Label_.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Label_, item^.Host.States);
    end;
  end;
  if not prevWas then
  begin
    item^.Host.Cur := item^.Host.Rest;
    item^.Host.States := [];
  end
  else if FStRerender then
  begin
    TyStClearItem(item^);
    if prev <> [] then TyStUseItemStates(item^, prev);
  end;
  TyStApplyItem(item^);
end;

{ ==================== graph, tree and treemap states [F2a] ==================== }

function TTyAdvanceChart.StGraphNodeOfRaw(ASlot, ARaw: Integer): Integer;
var j: Integer;
begin
  Result := -1;
  if (ASlot < 0) or (ASlot > High(FGraphNodes)) then Exit;
  for j := 0 to High(FGraphNodes[ASlot]) do
    if FGraphNodes[ASlot][j].RawRow = ARaw then Exit(j);
end;

function TTyAdvanceChart.StGraphEdgeOfRow(ASlot, ARow: Integer): Integer;
var j: Integer;
begin
  Result := -1;
  if (ASlot < 0) or (ASlot > High(FGraphEdges)) then Exit;
  for j := 0 to High(FGraphEdges[ASlot]) do
    if FGraphEdges[ASlot][j].Row = ARow then Exit(j);
end;

function TTyAdvanceChart.StGraphEdgeInner(ASlot, AEdge: Integer): Integer;
var j: Integer;
begin
  Result := -1;
  if (ASlot < 0) or (ASlot > High(FGraphEdges)) then Exit;
  if (AEdge < 0) or (AEdge > High(FGraphEdges[ASlot])) then Exit;
  if not GraphEdgeSurvives(FGraphNodes[ASlot], FGraphEdges[ASlot][AEdge]) then Exit;
  Result := 0;
  for j := 0 to AEdge - 1 do
    if GraphEdgeSurvives(FGraphNodes[ASlot], FGraphEdges[ASlot][j]) then Inc(Result);
end;

function TTyAdvanceChart.StGraphEdgeOfInner(ASlot, AInner: Integer): Integer;
var j, n: Integer;
begin
  Result := -1;
  if (ASlot < 0) or (ASlot > High(FGraphEdges)) or (AInner < 0) then Exit;
  n := 0;
  for j := 0 to High(FGraphEdges[ASlot]) do
    if GraphEdgeSurvives(FGraphNodes[ASlot], FGraphEdges[ASlot][j]) then
    begin
      if n = AInner then Exit(j);
      Inc(n);
    end;
end;

{ [F3a] the slot holds a solved sankey }
function TTyAdvanceChart.StSankeySlot(ASlot: Integer): Boolean;
begin
  Result := (ASlot >= 0) and (ASlot <= High(FBindings)) and (ASlot <= High(FSankeys))
    and FSankeys[ASlot].Valid and (FBindings[ASlot].SeriesType = TySankeySeriesTypeName);
end;

function TTyAdvanceChart.StChordSlot(ASlot: Integer): Boolean;
begin
  Result := (ASlot >= 0) and (ASlot <= High(FBindings)) and (ASlot <= High(FChords))
    and FChords[ASlot].Valid and (FBindings[ASlot].SeriesType = TyChordSeriesTypeName);
end;

function TTyAdvanceChart.SelEdgeData(ASlot: Integer): TTySelData;
var
  j, n, s: Integer;
  links: TJSONData;
  sNode, item: TJSONObject;
  has: Boolean;
begin
  Result := Default(TTySelData);
  { [F3b] A CHORD'S EDGE DATA: every link the graph took, keyed by its name
    (createGraphFromNodeEdge's: the id, else 'source > target'), its index
    its own }
  if StChordSlot(ASlot) then
  begin
    s := FBindings[ASlot].SeriesIndex;
    sNode := StSeriesNode(s);
    n := Length(FChords[ASlot].Edges);
    SetLength(Result.Keys, n);
    SetLength(Result.Raws, n);
    SetLength(Result.Disabled, n);
    for j := 0 to n - 1 do
    begin
      Result.Keys[j] := FChords[ASlot].Edges[j].Name;
      if Result.Keys[j] = '' then Result.Keys[j] := 'e'#0#0 + IntToStr(j);
      Result.Raws[j] := j;
      Result.Disabled[j] := TyStReadBool([FChords[ASlot].Edges[j].Item, sNode],
        ['select', 'disabled'], has);
    end;
    Exit;
  end;
  { [F3a] A SANKEY'S EDGE DATA: every link of the solve, keyed by its name
    (the link's id, else 'source > target'), its raw index its own }
  if StSankeySlot(ASlot) then
  begin
    s := FBindings[ASlot].SeriesIndex;
    sNode := StSeriesNode(s);
    n := Length(FSankeys[ASlot].Edges);
    SetLength(Result.Keys, n);
    SetLength(Result.Raws, n);
    SetLength(Result.Disabled, n);
    for j := 0 to n - 1 do
    begin
      Result.Keys[j] := FSankeys[ASlot].Edges[j].DataName;
      if Result.Keys[j] = '' then Result.Keys[j] := 'e'#0#0 + IntToStr(j);
      Result.Raws[j] := j;
      Result.Disabled[j] := TyStReadBool([FSankeys[ASlot].Edges[j].Item, sNode],
        ['select', 'disabled'], has);
    end;
    Exit;
  end;
  if (ASlot < 0) or (ASlot > High(FGraphEdges)) then Exit;
  s := FBindings[ASlot].SeriesIndex;
  sNode := StSeriesNode(s);
  links := nil;
  if sNode <> nil then
  begin
    links := sNode.Find('edges');
    if (links = nil) or (links.JSONType = jtNull) then links := sNode.Find('links');
  end;
  n := 0;
  for j := 0 to High(FGraphEdges[ASlot]) do
    if GraphEdgeSurvives(FGraphNodes[ASlot], FGraphEdges[ASlot][j]) then Inc(n);
  SetLength(Result.Keys, n);
  SetLength(Result.Raws, n);
  SetLength(Result.Disabled, n);
  n := 0;
  for j := 0 to High(FGraphEdges[ASlot]) do
  begin
    if not GraphEdgeSurvives(FGraphNodes[ASlot], FGraphEdges[ASlot][j]) then Continue;
    { the edge data's name: the link's id, else 'source > target' }
    Result.Keys[n] := FGraphEdges[ASlot][j].DataName;
    if Result.Keys[n] = '' then Result.Keys[n] := 'e'#0#0 + IntToStr(FGraphEdges[ASlot][j].RawIndex);
    Result.Raws[n] := FGraphEdges[ASlot][j].RawIndex;
    item := nil;
    if (links is TJSONArray) and (FGraphEdges[ASlot][j].Row >= 0)
      and (FGraphEdges[ASlot][j].Row < links.Count)
      and (TJSONArray(links).Items[FGraphEdges[ASlot][j].Row] is TJSONObject) then
      item := TJSONObject(TJSONArray(links).Items[FGraphEdges[ASlot][j].Row]);
    Result.Disabled[n] := TyStReadBool([item, sNode], ['select', 'disabled'], has);
    Inc(n);
  end;
end;

{ queryDataIndex on the edge data (dataIndexInside as it is, dataIndex raw,
  else the edge data's name), as solved edge indices }
function TTyAdvanceChart.QueryEdgeIndex(ASlot: Integer; APayload: TJSONObject;
  out AEdges: TTyIntegerArray): Boolean;
var
  d: TJSONData;
  mode, k: Integer;

  function One(AItem: TJSONData): Integer;
  var j: Integer;
  begin
    Result := -1;
    { [F3a] a sankey's edge data is every link: an index as it is }
    if StSankeySlot(ASlot) then
    begin
      if mode = 2 then
      begin
        if not (AItem.JSONType in [jtString, jtNumber]) then Exit;
        for j := 0 to High(FSankeys[ASlot].Edges) do
          if FSankeys[ASlot].Edges[j].DataName = AItem.AsString then Exit(j);
        Exit;
      end;
      if (AItem.JSONType <> jtNumber) or (Frac(AItem.AsFloat) <> 0) then Exit;
      j := Trunc(AItem.AsFloat);
      if (j >= 0) and (j <= High(FSankeys[ASlot].Edges)) then Result := j;
      Exit;
    end;
    { [F3b] a chord's too }
    if StChordSlot(ASlot) then
    begin
      if mode = 2 then
      begin
        if not (AItem.JSONType in [jtString, jtNumber]) then Exit;
        for j := 0 to High(FChords[ASlot].Edges) do
          if FChords[ASlot].Edges[j].Name = AItem.AsString then Exit(j);
        Exit;
      end;
      if (AItem.JSONType <> jtNumber) or (Frac(AItem.AsFloat) <> 0) then Exit;
      j := Trunc(AItem.AsFloat);
      if (j >= 0) and (j <= High(FChords[ASlot].Edges)) then Result := j;
      Exit;
    end;
    if mode = 2 then
    begin
      if not (AItem.JSONType in [jtString, jtNumber]) then Exit;
      for j := 0 to High(FGraphEdges[ASlot]) do
        if GraphEdgeSurvives(FGraphNodes[ASlot], FGraphEdges[ASlot][j])
          and (FGraphEdges[ASlot][j].DataName = AItem.AsString) then Exit(j);
      Exit;
    end;
    if (AItem.JSONType <> jtNumber) or (Frac(AItem.AsFloat) <> 0) then Exit;
    if mode = 0 then Exit(StGraphEdgeOfInner(ASlot, Trunc(AItem.AsFloat)));
    for j := 0 to High(FGraphEdges[ASlot]) do
      if (FGraphEdges[ASlot][j].RawIndex = Trunc(AItem.AsFloat))
        and GraphEdgeSurvives(FGraphNodes[ASlot], FGraphEdges[ASlot][j]) then Exit(j);
  end;

begin
  AEdges := nil;
  Result := False;
  if not (StSankeySlot(ASlot) or StChordSlot(ASlot))
    and ((ASlot < 0) or (ASlot > High(FGraphEdges))) then Exit;
  mode := 0;
  d := APayload.Find('dataIndexInside');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    mode := 1;
    d := APayload.Find('dataIndex');
  end;
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    mode := 2;
    d := APayload.Find('name');
  end;
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  Result := True;
  if d is TJSONArray then
  begin
    SetLength(AEdges, d.Count);
    for k := 0 to d.Count - 1 do AEdges[k] := One(d.Items[k]);
  end
  else
  begin
    SetLength(AEdges, 1);
    AEdges[0] := One(d);
  end;
end;

{ A GRAPH'S EDGE (Line.ts _updateCommonStl): the line's states are its
  lineStyle's along link -> series; the arrows take the line's state stroke
  as their fill and its opacity; the label's states are the link's `label`,
  the series' `edgeLabel` (resolveParentPath), its emphasis show defaulting
  to the normal one (defaultEmphasis). emphasis.disabled: no dispatcher, no
  proxy on any of them. }
procedure TTyAdvanceChart.StDeclareGraphEdge(ASlot, AEdge: Integer; AList: TTyPaintList);
var
  s, idx, k: Integer;
  item: PTyStItem;
  cap: TTyChartElement;
  ph: PTyChartElement;
  nodes: TTyStNodeArray;
  has, bolder, disabled, was, prevWas, normalShow, stShow: Boolean;
  prev: TTyStNames;
  n: TTyStName;
  obj: TTyStObject;
  d: TJSONData;
  ss: Double;
  c: TTyChartColor;

  function EdgeLab(const AState, AKey: string): TJSONData;
  begin
    Result := TyStFind([nodes[0]], [AState, 'label', AKey]);
    if Result = nil then Result := TyStFind([nodes[2]], [AState, 'edgeLabel', AKey]);
  end;

begin
  s := FBindings[ASlot].SeriesIndex;
  item := @FSt[s].EdgeRows[AEdge];
  ph := AList.Ref(FSt[s].EdgeHostIdx[AEdge]);
  nodes := StEdgeNodes(s, AEdge);
  prevWas := item^.Host.Exists;
  prev := item^.Host.States;
  item^.Host.Exists := True;
  item^.Host.IsPath := True;
  disabled := TyStReadBool(nodes, ['emphasis', 'disabled'], has);
  item^.Host.Proxy := not disabled;
  for n := Low(TTyStName) to High(TTyStName) do item^.Host.HasState[n] := True;
  item^.Host.Rest := StRestOf(ph^);
  for n := Low(TTyStName) to High(TTyStName) do
    item^.Host.Decl[n] := TyStReadStyle(nodes, cStNames[n], 'lineStyle', bolder);
  { ---- the arrows ---- }
  if Length(item^.Parts) <> Length(FSt[s].EdgePartIdx[AEdge]) then SetLength(item^.Parts, 0);
  was := Length(item^.Parts) > 0;
  SetLength(item^.Parts, Length(FSt[s].EdgePartIdx[AEdge]));
  for k := 0 to High(item^.Parts) do
  begin
    item^.Parts[k].Exists := True;
    item^.Parts[k].IsPath := True;
    item^.Parts[k].Proxy := not disabled;
    item^.Parts[k].Rest := StRestOf(AList.Element(FSt[s].EdgePartIdx[AEdge][k]));
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      item^.Parts[k].HasState[n] := True;
      obj := TyStNoObject;
      if item^.Host.Decl[n].Has[stkStroke] then
      begin
        obj.Has[stkFill] := True;
        obj.Color[stkFill] := item^.Host.Decl[n].Color[stkStroke];
        obj.None[stkFill] := item^.Host.Decl[n].None[stkStroke];
      end;
      if item^.Host.Decl[n].Has[stkOpacity] then
        TyStSetNum(obj, stkOpacity, item^.Host.Decl[n].Num[stkOpacity]);
      item^.Parts[k].Decl[n] := obj;
    end;
    if not was then
    begin
      item^.Parts[k].Cur := item^.Parts[k].Rest;
      item^.Parts[k].States := [];
      if item^.Host.States <> [] then TyStUseStates(item^.Parts[k], item^.Host.States);
    end;
  end;
  { ---- the label ---- }
  idx := FSt[s].EdgeLabelIdx[AEdge];
  was := item^.Label_.Exists;
  if idx < 0 then
    item^.Label_ := Default(TTyStElement)
  else
  begin
    cap := AList.Element(idx);
    item^.Label_.Exists := True;
    item^.Label_.IsPath := False;
    item^.Label_.Proxy := not disabled;
    item^.Label_.Rest := StLabelRestOf(cap);
    normalShow := not cap.Ignore;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      item^.Label_.HasState[n] := True;
      obj := TyStNoObject;
      d := EdgeLab(cStNames[n], 'show');
      if (d = nil) and (n = stnEmphasis) then stShow := normalShow
      else if d <> nil then stShow := (d.JSONType = jtBoolean) and d.AsBoolean
      else stShow := normalShow;
      if stShow <> normalShow then TyStSetNum(obj, stkIgnore, Ord(not stShow));
      d := EdgeLab(cStNames[n], 'color');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> 'inherit')
        and (d.AsString <> 'auto') and TyTryParseChartColor(d.AsString, c) then
        TyStSetColor(obj, stkFill, c);
      d := EdgeLab(cStNames[n], 'opacity');
      if (d <> nil) and (d.JSONType = jtNumber) then
      begin
        ss := d.AsFloat;
        if not IsNan(ss) then TyStSetNum(obj, stkOpacity, ss);
      end;
      item^.Label_.Decl[n] := obj;
    end;
    if not was then
    begin
      item^.Label_.Cur := item^.Label_.Rest;
      item^.Label_.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Label_, item^.Host.States);
    end;
  end;
  if not prevWas then
  begin
    item^.Host.Cur := item^.Host.Rest;
    item^.Host.States := [];
  end
  else if FStRerender then
  begin
    TyStClearItem(item^);
    if prev <> [] then TyStUseItemStates(item^, prev);
  end;
end;

{ A TREE'S EDGE (TreeView.ts drawEdge): setStatesStylesFromModel(edge,
  itemModel, 'lineStyle') along the node's chain and the default proxy --
  installed whatever the node's emphasis says; no label, no dispatcher }
procedure TTyAdvanceChart.StDeclareTreeEdge(ASlot, ARaw: Integer; AList: TTyPaintList);
var
  s: Integer;
  item: PTyStItem;
  nodes: TTyStNodeArray;
  bolder, prevWas: Boolean;
  prev: TTyStNames;
  n: TTyStName;
begin
  s := FBindings[ASlot].SeriesIndex;
  item := @FSt[s].EdgeRows[ARaw];
  nodes := StNodes(s, ARaw);
  prevWas := item^.Host.Exists;
  prev := item^.Host.States;
  item^.Host.Exists := True;
  item^.Host.IsPath := True;
  item^.Host.Proxy := True;
  item^.NoDispatch := True;
  for n := Low(TTyStName) to High(TTyStName) do
  begin
    item^.Host.HasState[n] := True;
    item^.Host.Decl[n] := TyStReadStyle(nodes, cStNames[n], 'lineStyle', bolder);
  end;
  item^.Host.Rest := StRestOf(AList.Element(FSt[s].EdgeHostIdx[ARaw]));
  item^.Label_ := Default(TTyStElement);
  if not prevWas then
  begin
    item^.Host.Cur := item^.Host.Rest;
    item^.Host.States := [];
  end
  else if FStRerender then
  begin
    TyStClearItem(item^);
    if prev <> [] then TyStUseItemStates(item^, prev);
  end;
end;

{ A TREEMAP NODE (TreemapView.ts renderNode): every state's style is
  getStateItemStyle of [state].itemStyle -- color the fill, strokeColor the
  stroke, strokeWidth the width, never an opacity -- and a background's
  fill is the state's borderColor, written whether or not it is declared (an
  undeclared one takes the fill away). The proxy always; a disabled
  emphasis only stops the dispatcher. A leaf's group dispatches (its content
  hosts, its background is a part with states of its own); a parent's
  background alone. The labels: the content's `label`, a header's
  `upperLabel` (shown under emphasis by default). }
procedure TTyAdvanceChart.StDeclareTreemap(ASlot, ARaw: Integer; AList: TTyPaintList);
var
  s, idx, k: Integer;
  item: PTyStItem;
  cap: TTyChartElement;
  ph: PTyChartElement;
  nodes: TTyStNodeArray;
  has, was, normalShow, stShow, isBg: Boolean;
  n: TTyStName;
  obj: TTyStObject;
  key, txt: string;
  ss: Double;
  c: TTyChartColor;

  function StateStyle(AIsBg: Boolean; AState: TTyStName): TTyStObject;
  var t: string; h: Boolean; col: TTyChartColor; v: Double;
  begin
    Result := TyStNoObject;
    if AIsBg then
    begin
      t := TyStReadString(nodes, [cStNames[AState], 'itemStyle', 'borderColor'], h);
      if h and TyTryParseChartColor(t, col) then TyStSetColor(Result, stkFill, col)
      else TyStSetNone(Result, stkFill);
    end
    else
    begin
      t := TyStReadString(nodes, [cStNames[AState], 'itemStyle', 'color'], h);
      if h and TyTryParseChartColor(t, col) then TyStSetColor(Result, stkFill, col);
    end;
    t := TyStReadString(nodes, [cStNames[AState], 'itemStyle', 'strokeColor'], h);
    if h and TyTryParseChartColor(t, col) then TyStSetColor(Result, stkStroke, col);
    v := TyStReadNumber(nodes, [cStNames[AState], 'itemStyle', 'strokeWidth'], h);
    if h and not IsNan(v) then TyStSetNum(Result, stkLineWidth, v);
  end;

  procedure Declare(var AEl: TTyStElement; const AFrom: TTyChartElement);
  var m: TTyStName;
  begin
    AEl.Exists := True;
    AEl.IsPath := True;
    AEl.Proxy := True;
    AEl.Rest := StRestOf(AFrom);
    for m := Low(TTyStName) to High(TTyStName) do
    begin
      AEl.HasState[m] := True;
      AEl.Decl[m] := StateStyle(AFrom.Anim.Sub = 0, m);
    end;
  end;

begin
  s := FBindings[ASlot].SeriesIndex;
  item := @FSt[s].Rows[ARaw];
  ph := AList.Ref(FSt[s].HostIdx[ARaw]);
  nodes := StNodes(s, ARaw);
  item^.NoDispatch := TyStReadBool(nodes, ['emphasis', 'disabled'], has);
  { a leaf's node group dispatches: its content (or its lone background)
    hosts; a parent's background alone }
  item^.HasGroup := (ph^.Anim.Sub = 1) or (ph^.Anim.G[4] <> 0);
  Declare(item^.Host, ph^);
  if Length(item^.Parts) <> Length(FSt[s].PartIdx[ARaw]) then SetLength(item^.Parts, 0);
  was := Length(item^.Parts) > 0;
  SetLength(item^.Parts, Length(FSt[s].PartIdx[ARaw]));
  for k := 0 to High(item^.Parts) do
  begin
    Declare(item^.Parts[k], AList.Element(FSt[s].PartIdx[ARaw][k]));
    if not was then
    begin
      item^.Parts[k].Cur := item^.Parts[k].Rest;
      item^.Parts[k].States := [];
      if item^.Host.States <> [] then TyStUseStates(item^.Parts[k], item^.Host.States);
    end;
  end;
  item^.Guide := Default(TTyStElement);
  { the label of the host: a content's `label`, a background's `upperLabel` }
  idx := FSt[s].LabelIdx[ARaw];
  was := item^.Label_.Exists;
  if idx < 0 then
    item^.Label_ := Default(TTyStElement)
  else
  begin
    cap := AList.Element(idx);
    isBg := ph^.Anim.Sub = 0;
    if isBg then key := 'upperLabel' else key := 'label';
    item^.Label_.Exists := True;
    item^.Label_.IsPath := False;
    item^.Label_.Proxy := True;
    item^.Label_.Rest := StLabelRestOf(cap);
    normalShow := not cap.Ignore;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      item^.Label_.HasState[n] := True;
      obj := TyStNoObject;
      stShow := TyStReadBool(nodes, [cStNames[n], key, 'show'], has);
      { TreemapSeries' emphasis.upperLabel.show }
      if (n = stnEmphasis) and isBg and not has then
      begin
        stShow := True;
        has := True;
      end;
      if has and (stShow <> normalShow) then TyStSetNum(obj, stkIgnore, Ord(not stShow));
      txt := TyStReadString(nodes, [cStNames[n], key, 'color'], has);
      if has and (txt <> 'inherit') and (txt <> 'auto') and TyTryParseChartColor(txt, c) then
        TyStSetColor(obj, stkFill, c);
      ss := TyStReadNumber(nodes, [cStNames[n], key, 'opacity'], has);
      if has and not IsNan(ss) then TyStSetNum(obj, stkOpacity, ss);
      item^.Label_.Decl[n] := obj;
    end;
    if not was then
    begin
      item^.Label_.Cur := item^.Label_.Rest;
      item^.Label_.States := [];
      if item^.Host.Exists and (item^.Host.States <> []) then
        TyStUseStates(item^.Label_, item^.Host.States);
    end;
  end;
end;

procedure TTyAdvanceChart.StTreeFollow(ASeriesIndex, ARaw, AOld: Integer);
var
  slot, par, nw: Integer;
begin
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSt)) then Exit;
  if FSt[ASeriesIndex].Kind <> sskTree then Exit;
  if (ARaw < 0) or (ARaw > High(FSt[ASeriesIndex].Rows)) then Exit;
  nw := FSt[ASeriesIndex].Rows[ARaw].GroupHover;
  if (nw = AOld) or (nw = TyStHoverBlur) then Exit;
  if (ARaw > High(FSt[ASeriesIndex].EdgeRows))
    or not FSt[ASeriesIndex].EdgeRows[ARaw].Host.Exists then Exit;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FTrees)) or not FTrees[slot].Valid then Exit;
  if ARaw > High(FTrees[slot].Hier.Nodes) then Exit;
  par := FTrees[slot].Hier.Nodes[ARaw].Parent;
  { the parent's symbol blurred at this moment: the edge stays }
  if (par >= 0) and (par <= High(FSt[ASeriesIndex].Rows))
    and FSt[ASeriesIndex].Rows[par].Host.Exists
    and (FSt[ASeriesIndex].Rows[par].GroupHover = TyStHoverBlur) then Exit;
  FSt[ASeriesIndex].EdgeRows[ARaw].Host.HoverState := nw;
  FStDirty := True;
end;

function TTyAdvanceChart.StItemFocus(ASeriesIndex, ARaw: Integer;
  out AScope: TTyStScope): TTyStFocus;
var
  nodes: TTyStNodeArray;
  d, legacy: TJSONData;
  w: string;
  slot, i, p: Integer;
  anc, ns, es: TTyIntegerArray;
  adj: Boolean;
  hier: TTyHierarchy;
  info: TTyCustomElInfo;
  txt: TJSONString;

  procedure Add(AIndex: Integer);
  begin
    SetLength(Result.Indices, Length(Result.Indices) + 1);
    Result.Indices[High(Result.Indices)] := AIndex;
  end;

begin
  nodes := StNodes(ASeriesIndex, ARaw);
  d := TyStFind(nodes, ['emphasis', 'focus']);
  AScope := TyStScopeOf(TyStFind(nodes, ['emphasis', 'blurScope']));
  slot := SlotOfSeries(ASeriesIndex);
  { A CUSTOM ITEM'S focus and blurScope are its root option's
    (toggleHoverEmphasis(el, elOption.focus, elOption.blurScope)), never the
    series' emphasis: none written is no focus [Batch 124] }
  if (slot >= 0) and (FBindings[slot].SeriesType = TyCustomSeriesType) then
  begin
    Result := Default(TTyStFocus);
    AScope := TyStScopeOf(nil);
    info := nil;
    if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FCustomViews))
      and (FCustomViews[ASeriesIndex] <> nil)
      and (FCustomViews[ASeriesIndex].ElOfRaw(ARaw) <> nil)
      and (FCustomViews[ASeriesIndex].ElOfRaw(ARaw).Custom is TTyCustomElInfo) then
      info := TTyCustomElInfo(FCustomViews[ASeriesIndex].ElOfRaw(ARaw).Custom);
    if (info = nil) or (info.Focus = '') then Exit;
    txt := TJSONString.Create(info.Focus);
    try
      Result := TyStFocusOf(txt);
    finally
      txt.Free;
    end;
    if info.BlurScope <> '' then
    begin
      txt := TJSONString.Create(info.BlurScope);
      try
        AScope := TyStScopeOf(txt);
      finally
        txt.Free;
      end;
    end;
    Exit;
  end;
  { A SANKEY'S WORDS ARE TWO INDEX SETS (SankeyView: adjacency and
    trajectory become getAdjacentDataIndices / getTrajectoryDataIndices)
    [Batch 114] }
  if StIsSankey(ASeriesIndex) and (d <> nil) and (d.JSONType = jtString)
    and ((d.AsString = 'adjacency') or (d.AsString = 'trajectory')) then
  begin
    Result := Default(TTyStFocus);
    Result.Kind := sfkIndices;
    TySankeyFocusSets(FSankeys[slot], False, ARaw, d.AsString = 'trajectory',
      Result.Indices, Result.EdgeIndices);
    Exit;
  end;
  { A CHORD NODE'S 'adjacency' -- the series' default -- is getAdjacentData-
    Indices: its kept links and their ends (ChordPiece) [Batch 120] }
  if StIsChord(ASeriesIndex) then
  begin
    if (d = nil) or ((d.JSONType = jtString) and (d.AsString = 'adjacency')) then
    begin
      Result := Default(TTyStFocus);
      Result.Kind := sfkIndices;
      TyChordFocusSets(FChords[slot], False, ARaw, Result.Indices, Result.EdgeIndices);
      Exit;
    end;
    Exit(TyStFocusOf(d));
  end;
  { [F2a] A GRAPH NODE'S 'adjacency' (the legacy focusNodeAdjacency where no
    focus is written, any value but null): getAdjacentDataIndices -- its
    edges and both ends of each -- in two index sets }
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt))
    and (FSt[ASeriesIndex].Kind = sskGraph) then
  begin
    adj := False;
    if d = nil then
    begin
      legacy := nil;
      if nodes[2] <> nil then legacy := nodes[2].Find('focusNodeAdjacency');
      adj := (legacy <> nil) and (legacy.JSONType <> jtNull);
    end
    else
      adj := (d.JSONType = jtString) and (d.AsString = 'adjacency');
    if not adj then Exit(TyStFocusOf(d));
    Result := Default(TTyStFocus);
    Result.Kind := sfkIndices;
    TyGraphFocusSets(FGraphNodes[slot], FGraphEdges[slot], False,
      StGraphNodeOfRaw(slot, ARaw), ns, es);
    for i := 0 to High(ns) do
      if (ns[i] >= 0) and (ns[i] <= High(FGraphNodes[slot]))
        and (FGraphNodes[slot][ns[i]].Row >= 0) then Add(FGraphNodes[slot][ns[i]].Row);
    Result.EdgeIndices := es;
    Exit;
  end;
  { [F2a] A TREE'S WORDS (TreeView.ts:447-457): ancestor, descendant,
    relative as data indices -- the virtual root and the node itself among
    them; A TREEMAP'S (TreemapView.ts:822-825) ancestor and descendant only }
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt))
    and (FSt[ASeriesIndex].Kind in [sskTree, sskTreemap]) then
  begin
    if (d <> nil) and (d.JSONType = jtString) then w := d.AsString else w := '';
    if (w <> 'ancestor') and (w <> 'descendant')
      and not ((w = 'relative') and (FSt[ASeriesIndex].Kind = sskTree)) then
      Exit(TyStFocusOf(d));
    Result := Default(TTyStFocus);
    Result.Kind := sfkIndices;
    if FSt[ASeriesIndex].Kind = sskTree then hier := FTrees[slot].Hier
    else hier := FTreemaps[slot].Hier;
    if (ARaw < 0) or (ARaw > High(hier.Nodes)) then Exit;
    if (w = 'ancestor') or (w = 'relative') then
    begin
      anc := nil;
      p := ARaw;
      while p >= 0 do
      begin
        SetLength(anc, Length(anc) + 1);
        anc[High(anc)] := p;
        p := hier.Nodes[p].Parent;
      end;
      for i := High(anc) downto 0 do Add(anc[i]);
    end;
    if (w = 'descendant') or (w = 'relative') then
    begin
      Add(ARaw);
      i := ARaw + 1;
      while (i <= High(hier.Nodes)) and (hier.Nodes[i].Depth > hier.Nodes[ARaw].Depth) do
      begin
        Add(i);
        Inc(i);
      end;
    end;
    Exit;
  end;
  if not ((slot >= 0) and (slot <= High(FSunbursts)) and FSunbursts[slot].Valid
    and (ARaw >= 0) and (ARaw <= High(FSunbursts[slot].Hier.Nodes))) then
    Exit(TyStFocusOf(d));
  { A SUNBURST'S WORDS ARE INDICES (SunburstPiece.ts:152-160), its default
    'descendant' (SunburstSeries.ts:271): the row's ancestors from the root
    down, its subtree in pre-order, or both [Batch 90] }
  if d = nil then w := 'descendant'
  else if d.JSONType = jtString then w := d.AsString
  else w := '';
  if (w <> 'descendant') and (w <> 'ancestor') and (w <> 'relative') then
    Exit(TyStFocusOf(d));
  Result := Default(TTyStFocus);
  Result.Kind := sfkIndices;
  if (w = 'ancestor') or (w = 'relative') then
  begin
    anc := nil;
    p := ARaw;
    while p >= 0 do
    begin
      SetLength(anc, Length(anc) + 1);
      anc[High(anc)] := p;
      p := FSunbursts[slot].Hier.Nodes[p].Parent;
    end;
    { the root's index finds no element (the return circle is not
      registered under it) [Batch 115] }
    for i := High(anc) downto 0 do
      if anc[i] <> 0 then Add(anc[i]);
  end;
  if (w = 'descendant') or (w = 'relative') then
    for i := 0 to High(FSunbursts[slot].Hier.Nodes) do
    begin
      p := i;
      while (p >= 0) and (p <> ARaw) do p := FSunbursts[slot].Hier.Nodes[p].Parent;
      if (p = ARaw) and (i <> 0) then Add(i);
    end;
end;

{ A SANKEY LINK'S focus: along link -> level -> series, the two words its
  index sets [Batch 114] }
function TTyAdvanceChart.StEdgeFocus(ASeriesIndex, AEdge: Integer;
  out AScope: TTyStScope): TTyStFocus;
var
  nodes: TTyStNodeArray;
  d, legacy: TJSONData;
  slot: Integer;
  adj: Boolean;
begin
  nodes := StEdgeNodes(ASeriesIndex, AEdge);
  d := TyStFind(nodes, ['emphasis', 'focus']);
  AScope := TyStScopeOf(TyStFind(nodes, ['emphasis', 'blurScope']));
  slot := SlotOfSeries(ASeriesIndex);
  { [F2a] A GRAPH EDGE'S 'adjacency': itself and its two ends (GraphView) }
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt))
    and (FSt[ASeriesIndex].Kind = sskGraph) then
  begin
    adj := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'adjacency');
    if (d = nil) and (nodes[2] <> nil) then
    begin
      legacy := nodes[2].Find('focusNodeAdjacency');
      adj := (legacy <> nil) and (legacy.JSONType <> jtNull);
    end;
    if not adj or (AEdge < 0) or (AEdge > High(FGraphEdges[slot])) then Exit(TyStFocusOf(d));
    Result := Default(TTyStFocus);
    Result.Kind := sfkIndices;
    SetLength(Result.EdgeIndices, 1);
    Result.EdgeIndices[0] := AEdge;
    SetLength(Result.Indices, 2);
    Result.Indices[0] := FGraphNodes[slot][FGraphEdges[slot][AEdge].Source].Row;
    Result.Indices[1] := FGraphNodes[slot][FGraphEdges[slot][AEdge].Target].Row;
    Exit;
  end;
  { A CHORD RIBBON'S 'adjacency' -- the series' default -- itself and its two
    ends (ChordEdge) [Batch 120] }
  if StIsChord(ASeriesIndex) then
  begin
    if (d = nil) or ((d.JSONType = jtString) and (d.AsString = 'adjacency')) then
    begin
      Result := Default(TTyStFocus);
      Result.Kind := sfkIndices;
      TyChordFocusSets(FChords[slot], True, AEdge, Result.Indices, Result.EdgeIndices);
      Exit;
    end;
    Exit(TyStFocusOf(d));
  end;
  if (d <> nil) and (d.JSONType = jtString)
    and ((d.AsString = 'adjacency') or (d.AsString = 'trajectory')) then
  begin
    Result := Default(TTyStFocus);
    Result.Kind := sfkIndices;
    TySankeyFocusSets(FSankeys[slot], True, AEdge, d.AsString = 'trajectory',
      Result.Indices, Result.EdgeIndices);
    Exit;
  end;
  Result := TyStFocusOf(d);
end;

function TTyAdvanceChart.StSeriesFocus(ASeriesIndex: Integer;
  out AScope: TTyStScope): TTyStFocus;
var nodes: array[0..0] of TJSONObject;
begin
  nodes[0] := StSeriesNode(ASeriesIndex);
  Result := TyStFocusOf(TyStFind(nodes, ['emphasis', 'focus']));
  AScope := TyStScopeOf(TyStFind(nodes, ['emphasis', 'blurScope']));
end;

function TTyAdvanceChart.StInnerRaw(ASeriesIndex, AInner: Integer): Integer;
var slot: Integer;
begin
  Result := -1;
  if StIsSankey(ASeriesIndex) then Exit(AInner);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
  if (AInner < 0) or (AInner >= FStores[slot].Count) then Exit;
  Result := FStores[slot].GetRawIndex(AInner);
end;

{ blurSeries (util/states.ts:429-517): every SHOWN series the scope reaches
  -- by series, by coordinate system (a series with none matches only
  itself), or all -- except the target itself under focus 'series': every
  element enters blur, but one held by an action stays in the target series
  under focus 'self'; data indices of a focus list leave the blur again. }
procedure TTyAdvanceChart.StBlurSeries(ATarget: Integer; const AFocus: TTyStFocus;
  AScope: TTyStScope);
var
  slot, s, raw, k, poly, tslot, old: Integer;
  tkey, key: string;
  same, sameCoord, spare: Boolean;
  item: PTyStItem;
begin
  if ATarget < 0 then Exit;
  if AFocus.Kind = sfkNone then Exit;
  tslot := SlotOfSeries(ATarget);
  if tslot < 0 then Exit;
  tkey := StCoordKey(tslot);
  for slot := 0 to High(FBindings) do
  begin
    if FBindings[slot].Hidden then Continue;
    s := FBindings[slot].SeriesIndex;
    if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    same := s = ATarget;
    key := StCoordKey(slot);
    if (key <> '') and (tkey <> '') then sameCoord := key = tkey
    else sameCoord := same;
    if not TyStBlursSeries(AFocus, AScope, same, sameCoord) then Continue;
    spare := same and (AFocus.Kind = sfkSelf);
    poly := StPolyOf(s);
    { the polyline and the area are elements of the group too }
    if poly >= 0 then poly := TyStHoverBlur;
    for raw := 0 to High(FSt[s].Rows) do
      if FSt[s].Rows[raw].Host.Exists then
        TyStItemEnterBlur(FSt[s].Rows[raw], spare, poly);
    if poly >= 0 then StPolyTo(s, poly);
    { the view group holds the links as well [Batch 114], a gauge's arcs
      too [F2b] }
    for raw := 0 to High(FSt[s].EdgeRows) do
      if FSt[s].EdgeRows[raw].Host.Exists then
      begin
        poly := -1;
        TyStItemEnterBlur(FSt[s].EdgeRows[raw], spare, poly);
      end;
    for raw := 0 to High(FSt[s].PeerRows) do
      if FSt[s].PeerRows[raw].Host.Exists then
      begin
        poly := -1;
        TyStItemEnterBlur(FSt[s].PeerRows[raw], spare, poly);
      end;
    if AFocus.Kind = sfkIndices then
    begin
      for k := 0 to High(AFocus.Indices) do
      begin
        item := StItemAt(s, AFocus.Indices[k]);
        if item = nil then Continue;
        poly := StPolyOf(s);
        old := item^.GroupHover;
        TyStItemLeaveBlur(item^, poly);
        if poly >= 0 then StPolyTo(s, poly);
        StTreeFollow(s, StInnerRaw(s, AFocus.Indices[k]), old);
      end;
      { the edge data's, by the same indices in every series blurred }
      for k := 0 to High(AFocus.EdgeIndices) do
        if (AFocus.EdgeIndices[k] >= 0) and (AFocus.EdgeIndices[k] <= High(FSt[s].EdgeRows))
          and FSt[s].EdgeRows[AFocus.EdgeIndices[k]].Host.Exists then
        begin
          poly := -1;
          TyStItemLeaveBlur(FSt[s].EdgeRows[AFocus.EdgeIndices[k]], poly);
        end;
    end;
    FSt[s].IsBlured := True;
    FStDirty := True;
  end;
end;

{ allLeaveBlur (util/states.ts:404-427): every series blurSeries reached
  leaves blur, whole; none is blured after }
procedure TTyAdvanceChart.StAllLeaveBlur;
var s, raw, poly, old: Integer;
begin
  for s := 0 to High(FSt) do
  begin
    if FSt[s].IsBlured then
    begin
      poly := StPolyOf(s);
      if poly = TyStHoverBlur then poly := TyStHoverNormal;
      for raw := 0 to High(FSt[s].Rows) do
        if FSt[s].Rows[raw].Host.Exists then
        begin
          old := FSt[s].Rows[raw].GroupHover;
          TyStItemLeaveBlur(FSt[s].Rows[raw], poly);
          StTreeFollow(s, raw, old);
        end;
      if poly >= 0 then StPolyTo(s, poly);
      for raw := 0 to High(FSt[s].EdgeRows) do
        if FSt[s].EdgeRows[raw].Host.Exists then
        begin
          poly := -1;
          TyStItemLeaveBlur(FSt[s].EdgeRows[raw], poly);
        end;
      for raw := 0 to High(FSt[s].PeerRows) do
        if FSt[s].PeerRows[raw].Host.Exists then
        begin
          poly := -1;
          TyStItemLeaveBlur(FSt[s].PeerRows[raw], poly);
        end;
      { the area on its own, should it be blurred apart from the polyline }
      if FSt[s].Area.Host.HoverState = TyStHoverBlur then
        FSt[s].Area.Host.HoverState := TyStHoverNormal;
      FStDirty := True;
    end;
    FSt[s].IsBlured := False;
  end;
  { [Batch 148] and every geo blurComponent reached }
  for s := 0 to High(FGeos) do
    if (FGeos[s] <> nil) and FGeos[s].IsBlured then
    begin
      if FGeos[s].LeaveBlurAll then
      begin
        FGeoDirty := True;
        FStDirty := True;
      end;
      FGeos[s].IsBlured := False;
    end;
end;

function TTyAdvanceChart.StDispatcher(const ATarget: TTyChartEventTarget;
  out AItem: PTyStItem; out APart: Integer): Boolean;
var
  s, idx, k: Integer;
  info: TTyCustomElInfo;
begin
  Result := False;
  AItem := nil;
  APart := -1;
  s := ATarget.HdSeries;
  if ATarget.HdKind = 1 then
  begin
    if ATarget.HdEdge then
    begin
      { a sankey link is a dispatcher of its own [Batch 114]; a chord
        ribbon too [Batch 120] }
      if not StHasEdges(s) then Exit;
      k := ATarget.HdRow;
      { a graph's elements carry the link's row [F2a] }
      if FSt[s].Kind = sskGraph then k := StGraphEdgeOfRow(SlotOfSeries(s), k);
      if (k < 0) or (k > High(FSt[s].EdgeRows)) then Exit;
      AItem := @FSt[s].EdgeRows[k];
      if not TyStItemDispatches(AItem^) then Exit;
      APart := 0;
      Exit(True);
    end;
    { a gauge's progress arc: the row's second dispatcher [F2b] }
    if ATarget.HdPeer then
    begin
      AItem := StPeerAt(s, ATarget.HdRow);
      if (AItem = nil) or not AItem^.Host.Proxy then Exit;
      APart := 0;
      Exit(True);
    end;
    AItem := StItemAt(s, ATarget.HdRow);
    { emphasis.disabled: not a highDownDispatcher at all }
    if (AItem = nil) or not TyStItemDispatches(AItem^) then Exit;
    { a custom item whose root option says emphasisDisabled
      (disableHoverEmphasis: no dispatcher) [Batch 124] }
    if (s >= 0) and (s <= High(FSt)) and (FSt[s].Kind = sskCustom) then
    begin
      info := CustomRootInfo(s, ATarget.HdRow);
      if (info <> nil) and info.EmphasisDisabled then Exit;
    end;
    APart := 0;
    Exit(True);
  end;
  if ATarget.HdKind <> 2 then Exit;
  if (s < 0) or (s > High(FSt)) or (FSt[s].Kind = sskNone) or not FSt[s].IsLine then Exit;
  idx := Integer(ATarget.Id) - 1;
  for k := 0 to High(FSt[s].RunIdx) do
    if FSt[s].RunIdx[k] = idx then
    begin
      AItem := @FSt[s].Run;
      APart := 1;
    end;
  for k := 0 to High(FSt[s].AreaIdx) do
    if FSt[s].AreaIdx[k] = idx then
    begin
      AItem := @FSt[s].Area;
      APart := 2;
    end;
  Result := (AItem <> nil) and AItem^.Host.Exists and AItem^.Host.Proxy;
end;

{ handleGlobalMouseOutForHighDown: allLeaveBlur, then the dispatcher leaves
  emphasis unless an action holds it }
procedure TTyAdvanceChart.StHoverOut(const ATarget: TTyChartEventTarget);
var item: PTyStItem; part, s, poly, old: Integer;
begin
  { [Batch 148] a geo region's group }
  if ATarget.HdKind = 14 then
  begin
    GeoHoverOut(ATarget);
    Exit;
  end;
  { [Batch 116] a visualMap's thumb is a highDownDispatcher of no series:
    allLeaveBlur, and it leaves emphasis; nothing else of it has states }
  if ATarget.HdKind = 7 then
  begin
    if (ATarget.HdRow in [3, 4]) and VmContinuous(ATarget.HdSeries) then
    begin
      StAllLeaveBlur;
      if ATarget.HdGen = FVmLive[ATarget.HdSeries].Gen then
        FVmLive[ATarget.HdSeries].ThumbHover[ATarget.HdRow - 3] := 0;
      if FStDirty then InvalidateFrame;
    end;
    Exit;
  end;
  { a legend item's own mouseout: the downplay action [Batch 93] }
  if ATarget.HdKind = 4 then
  begin
    LegendHighDown(ATarget, 'downplay');
    Exit;
  end;
  { [Batch 98] a selector button: allLeaveBlur, and it leaves emphasis;
    a page button has no states }
  if ATarget.HdKind = 5 then
  begin
    StAllLeaveBlur;
    LegendSelHover(-1, -1);
    if FStDirty then InvalidateFrame;
    Exit;
  end;
  if ATarget.HdKind = 6 then Exit;
  { [F2a] a breadcrumb item: allLeaveBlur, and it leaves emphasis }
  if ATarget.HdKind = 15 then
  begin
    StAllLeaveBlur;
    if (FTmCrumbHoverS = ATarget.HdSeries) and (FTmCrumbHoverK = ATarget.HdRow)
      and (FTmCrumbHoverGen = ATarget.HdGen) then
    begin
      FTmCrumbHoverS := -1;
      FTmCrumbHoverK := -1;
      FTmCrumbDirty := True;
    end;
    if FStDirty or FTmCrumbDirty then InvalidateFrame;
    Exit;
  end;
  if not StDispatcher(ATarget, item, part) then Exit;
  s := ATarget.HdSeries;
  StAllLeaveBlur;
  if part = 0 then
  begin
    poly := StPolyOf(s);
    old := item^.GroupHover;
    if TyStItemHoverLeave(item^, poly) then FStDirty := True;
    if poly >= 0 then StPolyTo(s, poly);
    if not ATarget.HdEdge then StTreeFollow(s, StInnerRaw(s, ATarget.HdRow), old);
  end
  else if (item^.Host.HighByOuter = 0) and (item^.Host.HoverState = TyStHoverEmphasis) then
  begin
    { the polyline's own change carries the area; the area is alone }
    if part = 1 then StPolyTo(s, TyStHoverNormal)
    else item^.Host.HoverState := TyStHoverNormal;
    FStDirty := True;
  end;
  if FStDirty then InvalidateFrame;
end;

{ handleGlobalMouseOverForHighDown: blurSeries by the dispatcher's focus,
  then it enters emphasis unless an action holds it }
procedure TTyAdvanceChart.StHoverOver(const ATarget: TTyChartEventTarget);
begin
  { [Batch 148] a geo region's group }
  if ATarget.HdKind = 14 then
  begin
    GeoHoverOver(ATarget);
    Exit;
  end;
  { [Batch 116] a thumb enters emphasis (no series to blur) }
  if ATarget.HdKind = 7 then
  begin
    if (ATarget.HdRow in [3, 4]) and VmContinuous(ATarget.HdSeries)
      and (ATarget.HdGen = FVmLive[ATarget.HdSeries].Gen) then
      FVmLive[ATarget.HdSeries].ThumbHover[ATarget.HdRow - 3] := 2;
    Exit;
  end;
  StHoverOverSeries(ATarget);
end;

procedure TTyAdvanceChart.StHoverOverSeries(const ATarget: TTyChartEventTarget);
var
  item: PTyStItem;
  part, s, poly, old: Integer;
  focus: TTyStFocus;
  scope: TTyStScope;
begin
  { a legend item's own mouseover: the highlight action [Batch 93] }
  if ATarget.HdKind = 4 then
  begin
    LegendHighDown(ATarget, 'highlight');
    Exit;
  end;
  { [Batch 98] a selector button enters emphasis (enableHoverEmphasis) }
  if ATarget.HdKind = 5 then
  begin
    LegendSelHover(ATarget.HdSeries, ATarget.HdRow);
    Exit;
  end;
  if ATarget.HdKind = 6 then Exit;
  { [F2a] a breadcrumb item enters emphasis (its ecData has no series: no
    blur) }
  if ATarget.HdKind = 15 then
  begin
    FTmCrumbHoverS := ATarget.HdSeries;
    FTmCrumbHoverK := ATarget.HdRow;
    FTmCrumbHoverGen := ATarget.HdGen;
    FTmCrumbDirty := True;
    InvalidateFrame;
    Exit;
  end;
  if not StDispatcher(ATarget, item, part) then Exit;
  s := ATarget.HdSeries;
  if (part = 0) and ATarget.HdEdge and (FSt[s].Kind = sskGraph) then
    focus := StEdgeFocus(s, StGraphEdgeOfRow(SlotOfSeries(s), ATarget.HdRow), scope)
  else if (part = 0) and ATarget.HdEdge then
    focus := StEdgeFocus(s, ATarget.HdRow, scope)
  else if part = 0 then
    focus := StItemFocus(s, StInnerRaw(s, ATarget.HdRow), scope)
  else
    focus := StSeriesFocus(s, scope);
  StBlurSeries(s, focus, scope);
  if part = 0 then
  begin
    poly := StPolyOf(s);
    old := item^.GroupHover;
    if TyStItemHoverEnter(item^, poly) then FStDirty := True;
    if poly >= 0 then StPolyTo(s, poly);
    if not ATarget.HdEdge then StTreeFollow(s, StInnerRaw(s, ATarget.HdRow), old);
  end
  else if item^.Host.HighByOuter = 0 then
  begin
    if part = 1 then StPolyTo(s, TyStHoverEmphasis)
    else item^.Host.HoverState := TyStHoverEmphasis;
    FStDirty := True;
  end;
  if FStDirty then InvalidateFrame;
end;

function TTyAdvanceChart.StOwnsElement(AIndex: Integer): Boolean;
var d: TTyChartDatumRef;
begin
  Result := False;
  if (FPaintList = nil) or (AIndex < 0) or (AIndex >= FPaintList.Count) then Exit;
  d := FPaintList.Element(AIndex).Datum;
  if (d.Kind <> ctkSeries) or (d.SeriesIndex < 0) or (d.SeriesIndex > High(FSt)) then Exit;
  Result := FSt[d.SeriesIndex].Kind <> sskNone;
end;

function TTyAdvanceChart.StEmphasised(AIndex: Integer): Boolean;
var d: TTyChartDatumRef; item: PTyStItem; k: Integer;
begin
  Result := False;
  if not StOwnsElement(AIndex) then Exit;
  d := FPaintList.Element(AIndex).Datum;
  if d.IsEdge then
  begin
    k := d.DataIndex;
    if FSt[d.SeriesIndex].Kind = sskGraph then
      k := StGraphEdgeOfRow(SlotOfSeries(d.SeriesIndex), k);
    Result := StHasEdges(d.SeriesIndex) and (k >= 0)
      and (k <= High(FSt[d.SeriesIndex].EdgeRows))
      and (stnEmphasis in FSt[d.SeriesIndex].EdgeRows[k].Host.States);
    Exit;
  end;
  item := StItemAt(d.SeriesIndex, d.DataIndex);
  Result := (item <> nil) and (stnEmphasis in item^.Host.States);
end;

{ ---- the selection model ---- }

function TTyAdvanceChart.SelData(ASlot: Integer): TTySelData;
var
  st: TTyDataStore;
  i, n, raw, s: Integer;
  key: string;
  has: Boolean;
begin
  Result := Default(TTySelData);
  if (ASlot < 0) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  s := FBindings[ASlot].SeriesIndex;
  n := st.Count;
  SetLength(Result.Keys, n);
  SetLength(Result.Raws, n);
  SetLength(Result.Disabled, n);
  for i := 0 to n - 1 do
  begin
    raw := st.GetRawIndex(i);
    Result.Raws[i] := raw;
    { getSelectionKey: the name, else the id (SeriesData's own 'e\0\0' + raw
      for an item that has neither) }
    key := st.GetItemName(i);
    if key = '' then key := st.GetId(i);
    if key = '' then key := 'e'#0#0 + IntToStr(raw);
    Result.Keys[i] := key;
    { the item model's select.disabled: the item's, else the series' }
    Result.Disabled[i] := TyStReadBool([StItemNode(s, raw), StSeriesNode(s)],
      ['select', 'disabled'], has);
  end;
end;

procedure TTyAdvanceChart.SelEnsure(ASlot: Integer);
var
  s, i: Integer;
  tb: TJSONBoolean;
  node: TJSONObject;
  data: TTySelData;
  flags: TTyBoolArray;
  has: Boolean;
begin
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  s := FBindings[ASlot].SeriesIndex;
  if s < 0 then Exit;
  if Length(FSel) <= s then
  begin
    SetLength(FSel, s + 1);
    SetLength(FSelInit, s + 1);
  end;
  if FSelInit[s] then Exit;
  if (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  node := StSeriesNode(s);
  { a map series' selectedMode is true unless written (MapSeries.
    defaultOption) [Batch 152] }
  if (node <> nil) and (node.Find('selectedMode') = nil)
    and (FBindings[ASlot].SeriesType = TyMapSeriesTypeName) then
  begin
    tb := TJSONBoolean.Create(True);
    try
      FSel[s] := TySelNew(TySelModeOf(tb));
    finally
      tb.Free;
    end;
  end
  { [R2-G] the series' own, never the root's: a root selectedMode reaches
    get(), but Series._innerSelect reads `option.selectedMode` and selects
    nothing (root-inherit c-select) }
  else if node <> nil then FSel[s] := TySelNew(TySelModeOf(node.Find('selectedMode')))
  else FSel[s] := TySelNew(ssmOff);
  FSelInit[s] := True;
  { _initSelectedMapFromData: `selected: true` on a data item }
  data := SelData(ASlot);
  flags := nil;
  SetLength(flags, Length(data.Raws));
  for i := 0 to High(data.Raws) do
    flags[i] := TyStReadBool([StItemNode(s, data.Raws[i])], ['selected'], has);
  TySelInitFromData(FSel[s], data, flags);
end;

procedure TTyAdvanceChart.SelSyncFlags(ASlot: Integer);
var
  s, raw, inner, k: Integer;
  data: TTySelData;
  st: TTyDataStore;
  was: Boolean;
begin
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  s := FBindings[ASlot].SeriesIndex;
  if (s < 0) or (s > High(FSt)) or (s > High(FSel)) or not FSelInit[s] then Exit;
  if (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  data := SelData(ASlot);
  for raw := 0 to High(FSt[s].Rows) do
  begin
    if not FSt[s].Rows[raw].Host.Exists then Continue;
    inner := st.IndexOfRawIndex(raw);
    was := FSt[s].Rows[raw].Host.Selected;
    FSt[s].Rows[raw].Host.Selected := (inner >= 0)
      and TySelIsSelected(FSel[s], data, inner);
    if was <> FSt[s].Rows[raw].Host.Selected then FStDirty := True;
    { the rest of the group: enterSelect traverses it [F2a] }
    for k := 0 to High(FSt[s].Rows[raw].Parts) do
      FSt[s].Rows[raw].Parts[k].Selected := FSt[s].Rows[raw].Host.Selected;
  end;
  { a graph's edges, from the same map [F2a]; a sankey's [F3a]; a chord's
    [F3b] }
  if FSt[s].Kind in [sskGraph, sskSankey, sskChord] then
  begin
    data := SelEdgeData(ASlot);
    for raw := 0 to High(FSt[s].EdgeRows) do
    begin
      if not FSt[s].EdgeRows[raw].Host.Exists then Continue;
      if FSt[s].Kind in [sskSankey, sskChord] then inner := raw
      else inner := StGraphEdgeInner(ASlot, raw);
      was := FSt[s].EdgeRows[raw].Host.Selected;
      FSt[s].EdgeRows[raw].Host.Selected := (inner >= 0)
        and TySelIsSelected(FSel[s], data, inner);
      if was <> FSt[s].EdgeRows[raw].Host.Selected then FStDirty := True;
    end;
  end;
end;

{ makeQueryConditionKindA + findComponents: seriesIndex (a number or a
  list, in its order), else seriesId, else seriesName (in series order);
  none of them is every series }
function TTyAdvanceChart.MatchSeries(APayload: TJSONObject): TTyIntegerArray;
var
  d: TJSONData;
  i, k, n, cnt: Integer;
  want: TTyStringArray;
  byId: Boolean;
  v: string;

  procedure Add(AIndex: Integer);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AIndex;
  end;

  function KeyText(AData: TJSONData; out AText: string): Boolean;
  begin
    Result := (AData <> nil) and (AData.JSONType in [jtString, jtNumber]);
    if Result then AText := AData.AsString;
  end;

begin
  Result := nil;
  cnt := FOption.ComponentCount('series');
  d := APayload.Find('seriesIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
    begin
      for k := 0 to TJSONArray(d).Count - 1 do
        if TJSONArray(d).Items[k].JSONType = jtNumber then
        begin
          n := Trunc(TJSONArray(d).Items[k].AsFloat);
          if (n >= 0) and (n < cnt) then Add(n);
        end;
    end
    else if d.JSONType = jtNumber then
    begin
      n := Trunc(d.AsFloat);
      if (n >= 0) and (n < cnt) then Add(n);
    end;
    Exit;
  end;
  byId := True;
  d := APayload.Find('seriesId');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    byId := False;
    d := APayload.Find('seriesName');
  end;
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    for i := 0 to cnt - 1 do Add(i);
    Exit;
  end;
  want := nil;
  if d is TJSONArray then
  begin
    for k := 0 to TJSONArray(d).Count - 1 do
      if KeyText(TJSONArray(d).Items[k], v) then
      begin
        SetLength(want, Length(want) + 1);
        want[High(want)] := v;
      end;
  end
  else if KeyText(d, v) then
  begin
    SetLength(want, 1);
    want[0] := v;
  end;
  for i := 0 to cnt - 1 do
  begin
    if byId then v := SeriesModelId(i) else v := SeriesModelName(i);
    for k := 0 to High(want) do
      if want[k] = v then
      begin
        Add(i);
        Break;
      end;
  end;
end;

{ queryDataIndex (util/model.ts:704-726): dataIndexInside as it is, else
  dataIndex (raw) through indexOfRawIndex, else name -- the first inner index
  of that name. False when the payload names no item at all. }
function TTyAdvanceChart.QueryDataIndex(ASlot: Integer; APayload: TJSONObject;
  out AInner: TTyIntegerArray): Boolean;
var
  d: TJSONData;
  st: TTyDataStore;
  mode, k: Integer;

  function One(AItem: TJSONData): Integer;
  var i: Integer; nm: string;
  begin
    Result := -1;
    if mode = 2 then
    begin
      if not (AItem.JSONType in [jtString, jtNumber]) then Exit;
      nm := AItem.AsString;
      for i := 0 to st.Count - 1 do
        if st.GetItemName(i) = nm then Exit(i);
      Exit;
    end;
    if AItem.JSONType <> jtNumber then Exit;
    if Frac(AItem.AsFloat) <> 0 then Exit;
    i := Trunc(AItem.AsFloat);
    if mode = 0 then Result := i
    else Result := st.IndexOfRawIndex(i);
  end;

begin
  AInner := nil;
  Result := False;
  if (ASlot < 0) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  mode := 0;
  d := APayload.Find('dataIndexInside');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    mode := 1;
    d := APayload.Find('dataIndex');
  end;
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    mode := 2;
    d := APayload.Find('name');
  end;
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  Result := True;
  if d is TJSONArray then
  begin
    SetLength(AInner, TJSONArray(d).Count);
    for k := 0 to TJSONArray(d).Count - 1 do
      AInner[k] := One(TJSONArray(d).Items[k]);
  end
  else
  begin
    SetLength(AInner, 1);
    AInner[0] := One(d);
  end;
end;

{ model/Series.ts's id: the written one, else '\0' + name + '\0' + n, n the
  first number no earlier series took (util/model.ts:500-525) }
function TTyAdvanceChart.SeriesModelId(ASeriesIndex: Integer): string;
var
  ids: TTyStringArray;
  i, k, num: Integer;
  n, d: TJSONData;
  taken: Boolean;
  cand: string;
begin
  { THE MODEL'S, which a merge keeps [Batch 95]; made afresh below only
    where there is no model }
  Result := FOption.ComponentId('series', ASeriesIndex);
  if Result <> '' then Exit;
  ids := nil;
  SetLength(ids, ASeriesIndex + 1);
  { the written ids first: they are reserved before any is generated }
  for i := 0 to FOption.ComponentCount('series') - 1 do
  begin
    n := FOption.ComponentAt('series', i);
    if not (n is TJSONObject) then Continue;
    d := TJSONObject(n).Find('id');
    if (d <> nil) and (d.JSONType in [jtString, jtNumber]) and (i <= ASeriesIndex) then
      ids[i] := d.AsString;
  end;
  for i := 0 to ASeriesIndex do
  begin
    if ids[i] <> '' then Continue;
    num := 0;
    repeat
      cand := #0 + SeriesModelName(i) + #0 + IntToStr(num);
      Inc(num);
      taken := False;
      for k := 0 to High(ids) do
        if ids[k] = cand then taken := True;
    until not taken;
    ids[i] := cand;
  end;
  Result := ids[ASeriesIndex];
end;

function TTyAdvanceChart.HasChartHandler(const AType: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(FEventRegs) do
    if FEventRegs[i].EventType = AType then Exit(True);
  Result := False;
end;

{ an action's event: no params, no pointer, the object as JSON; a query
  never filters it (upstream's eventInfo is empty for these) }
procedure TTyAdvanceChart.EmitPayloadEvent(const AType, APayloadJson: string;
  AObj: TJSONObject);
var
  ev: TTyChartEvent;
  regs: array of TTyChartEventReg;
  i, saved: Integer;
begin
  { a silent dispatch publishes nothing -- and so sends nothing to its
    group [Batch 141] }
  if FEvSilent > 0 then Exit;
  { [F4b] A BATCH'S ITEMS publish nothing of their own: their events (and
    a refined action's refined ones) are the batch's }
  if FBatchCapDepth > 0 then
  begin
    if AType = FBatchCapType then
    begin
      SetLength(FBatchCapList, Length(FBatchCapList) + 1);
      FBatchCapList[High(FBatchCapList)] := APayloadJson;
      Exit;
    end;
    if (FBatchCapRefined <> '') and (AType = FBatchCapRefined) then
    begin
      SetLength(FBatchCapRef, Length(FBatchCapRef) + 1);
      FBatchCapRef[High(FBatchCapRef)] := APayloadJson;
      Exit;
    end;
  end;
  ev := Default(TTyChartEvent);
  ev.EventType := AType;
  ev.HasParams := False;
  ev.Params := TyChartBlankParams;
  ev.HasOffset := False;
  ev.Payload := APayloadJson;
  { [F4b] THE EVENT IS OUTSIDE THE CYCLE: doDispatchAction clears
    IN_EC_CYCLE before it triggers, so what a handler (or the group a
    connect sends it to) dispatches runs at once -- and flushes the
    actions this one left pending }
  saved := FActCycle;
  FActCycle := 0;
  try
    if Assigned(FOnChartEvent) then FOnChartEvent(Self, ev);
    regs := Copy(FEventRegs);
    for i := 0 to High(regs) do
      if regs[i].EventType = AType then regs[i].Handler(Self, ev);
    { THE CONNECT LISTENER, registered after the chart's own forwarders
      (_initEvents runs in the constructor, enableConnect after init): the
      chart's handlers hear the event first [Batch 141] }
    ConnectBroadcast(AType, APayloadJson, AObj);
  finally
    FActCycle := saved;
  end;
end;

procedure TTyAdvanceChart.DoSelectAction(APayload: TJSONObject);
var ev: TJSONObject;
begin
  SelApply(APayload, APayload.Strings['type']);
  { the action's own event: a copy of the payload, the type lowercased }
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := LowerCase(APayload.Strings['type']);
    SelPublish(APayload, ev.AsJSON);
  finally
    ev.Free;
  end;
end;

procedure TTyAdvanceChart.SelApply(APayload: TJSONObject; const AType: string);
var
  t: string;
  series, inner: TTyIntegerArray;
  i, slot, s, kind, k: Integer;
  data: TTySelData;
  d: TJSONData;
begin
  { toggleSelectionFromPayload reads the ITEM's type -- a batch item keeps
    its own over the action's (defaults of a copy of the item over the
    payload) -- and
    does nothing for one that is no select type: the lowercased
    'toggleselect' a connected chart's event hands its items, say.
    [Milestone D5-D8: the action's type was read for every item.] }
  t := AType;
  d := APayload.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then t := d.AsString;
  if t = 'select' then kind := 0
  else if t = 'unselect' then kind := 1
  else if t = 'toggleSelect' then kind := 2
  else Exit;
  { updateDirectly: every series the query names }
  series := MatchSeries(APayload);
  for i := 0 to High(series) do
  begin
    slot := SlotOfSeries(series[i]);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    SelEnsure(slot);
    s := series[i];
    if (s > High(FSel)) or not FSelInit[s] then Continue;
    { A GRAPH'S LINKS share the series' one map, keyed by the edge data's
      names (Series.select(dataIndex, dataType)) [F2a]; any other series'
      edge data is not this model's }
    d := APayload.Find('dataType');
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'edge') then
    begin
      { [F3b] and a chord's }
      if not ((s <= High(FSt)) and (FSt[s].Kind in [sskGraph, sskSankey, sskChord])) then Continue;
      if not QueryEdgeIndex(slot, APayload, inner) then Continue;
      if FSt[s].Kind = sskGraph then
        for k := 0 to High(inner) do inner[k] := StGraphEdgeInner(slot, inner[k]);
      data := SelEdgeData(slot);
    end
    else
    begin
      if not QueryDataIndex(slot, APayload, inner) then Continue;
      data := SelData(slot);
    end;
    case kind of
      0: TySelSelect(FSel[s], data, inner);
      1: TySelUnselect(FSel[s], data, inner);
    else
      TySelToggle(FSel[s], data, inner);
    end;
    SelSyncFlags(slot);
  end;
  if FStDirty then InvalidateFrame;
end;

procedure TTyAdvanceChart.SelPublish(APayload: TJSONObject; const AOwnEvent: string);
var
  t, lt, sel, selMap, nm: string;
  inner: TTyIntegerArray;
  k, slot, s, q, nd: Integer;
  dts: array[0..1] of string;
  idx: TTyIntegerArray;
  fromPayload: TJSONObject;
  d: TJSONData;
  legacy: array[0..1] of string;
  post: string;
begin
  t := APayload.Strings['type'];
  { THE EVENTS. First the action's own, a copy of the payload with the type
    lowercased (a batch's: see DoBatchAction); then selectchanged }
  lt := LowerCase(t);
  EmitPayloadEvent(lt, AOwnEvent);
  { getAllSelectedIndices: the shown series with a selection, in order }
  sel := '';
  for slot := 0 to High(FBindings) do
  begin
    if FBindings[slot].Hidden then Continue;
    s := FBindings[slot].SeriesIndex;
    if (s < 0) or (s > High(FSel)) or not FSelInit[s] then Continue;
    idx := TySelIndices(FSel[s], SelData(slot));
    if Length(idx) = 0 then Continue;
    { getAllSelectedIndices: one entry per data of getAllData -- a graph's
      node and edge data (the same indices, the map is one), a tree's and a
      treemap's 'main' [F2a] }
    { [F3a] a sankey's too: its node and edge data; [F3b] and a chord's
      (createGraphFromNodeEdge links them) }
    if (FBindings[slot].SeriesType = TyGraphSeriesTypeName)
      or (FBindings[slot].SeriesType = TySankeySeriesTypeName)
      or (FBindings[slot].SeriesType = TyChordSeriesTypeName) then
    begin
      dts[0] := 'node';
      dts[1] := 'edge';
      nd := 2;
    end
    else if (FBindings[slot].SeriesType = TyTreeSeriesTypeName)
      or (FBindings[slot].SeriesType = TyTreemapSeriesTypeName) then
    begin
      dts[0] := 'main';
      nd := 1;
    end
    else
    begin
      dts[0] := '';
      nd := 1;
    end;
    for q := 0 to nd - 1 do
    begin
      if sel <> '' then sel := sel + ',';
      sel := sel + '{"dataIndex":[';
      for k := 0 to High(idx) do
      begin
        if k > 0 then sel := sel + ',';
        sel := sel + IntToStr(idx[k]);
      end;
      sel := sel + '],"seriesIndex":' + IntToStr(s);
      if dts[q] <> '' then sel := sel + ',"dataType":"' + dts[q] + '"';
      sel := sel + '}';
    end;
  end;
  d := APayload.Find('isFromClick');
  if JsTruthy(d) then post := d.AsJSON else post := 'false';
  EmitPayloadEvent('selectchanged', '{"type":"selectchanged","selected":[' + sel
    + '],"isFromClick":' + post + ',"fromAction":' + '"' + StringToJSONString(t)
    + '","fromActionPayload":' + APayload.AsJSON + ',"escapeConnect":true}');

  { THE LEGACY EVENTS (legacy/dataSelectAction.ts), only to a handler that
    asked: a click -> map/pie selectchanged, an action select -> selected,
    unselect -> unselected; once per PIE series in the selection, the map
    variant included }
  if JsTruthy(APayload.Find('isFromClick')) then post := 'selectchanged'
  else if t = 'select' then post := 'selected'
  else if t = 'unselect' then post := 'unselected'
  else post := '';
  if post = '' then Exit;
  legacy[0] := 'map' + post;
  legacy[1] := 'pie' + post;
  for k := 0 to 1 do
  begin
    if not HasChartHandler(legacy[k]) then Continue;
    for slot := 0 to High(FBindings) do
    begin
      if FBindings[slot].SeriesType <> TyPieSeriesTypeName then Continue;
      if FBindings[slot].Hidden then Continue;
      s := FBindings[slot].SeriesIndex;
      if (s < 0) or (s > High(FSel)) or not FSelInit[s] then Continue;
      if Length(TySelIndices(FSel[s], SelData(slot))) = 0 then Continue;
      nm := '';
      fromPayload := APayload;
      if QueryDataIndex(slot, fromPayload, inner) and (Length(inner) > 0)
        and (inner[0] >= 0) and (inner[0] < FStores[slot].Count) then
        nm := FStores[slot].GetItemName(inner[0]);
      selMap := TySelMapJson(FSel[s]);
      EmitPayloadEvent(legacy[k], '{"type":"' + legacy[k] + '","seriesId":"'
        + StringToJSONString(SeriesModelId(s)) + '","name":"'
        + StringToJSONString(nm) + '","selected":' + selMap + '}');
    end;
  end;
end;

{ highlight / downplay (echarts.ts:2178-2205, 1792-1865): allLeaveBlur once;
  for a highlight without notBlur, every queried series whose emphasis is
  not disabled blurs by the focus of the element the payload names (its
  first, the first element there is when that one is missing); then each
  series' view enters / leaves emphasis on the queried items (all of them
  when none) with highlightKey's bit -- a line's one-point highlight on the
  symbol PATH, with the polyline (LineView.ts:937-1026). [Batch 90] }
procedure TTyAdvanceChart.DoHighDownAction(APayload: TJSONObject; ABatchItem: Boolean);
var
  t, key: string;
  series, inner, kept: TTyIntegerArray;
  excl: TTyStringArray;
  i, k, slot, s, digit, raw, q, poly: Integer;
  d: TJSONData;
  item: PTyStItem;
  skip, has, isArr, single, isHigh: Boolean;
  ev: TJSONObject;
  focus: TTyStFocus;
  scope: TTyStScope;
  nodes: array[0..0] of TJSONObject;

  procedure Apply(var AItem: TTyStItem; AOnPath: Boolean; ARaw: Integer);
  var old: Integer;
  begin
    poly := StPolyOf(s);
    old := AItem.GroupHover;
    if isHigh then
    begin
      if TyStItemEnterEmphasisBy(AItem, digit, AOnPath, poly) then FStDirty := True;
    end
    else if TyStItemLeaveEmphasisBy(AItem, digit, AOnPath, poly) then
      FStDirty := True;
    if poly >= 0 then StPolyTo(s, poly);
    { a tree node's edge [F2a] }
    if ARaw >= 0 then StTreeFollow(s, ARaw, old);
  end;

  { A SANKEY'S EDGE DATA [Batch 114]: `dataType: 'edge'` makes queryDataIndex
    read the links -- dataIndex as given, a number or a list }
  function EdgeQuery(ASeries: Integer; out AIdx: TTyIntegerArray): Boolean;
  var x: TJSONData; j: Integer;
  begin
    AIdx := nil;
    Result := False;
    { a chord's links too, by their raw index [Batch 120] }
    if not StHasEdges(ASeries) then Exit;
    x := APayload.Find('dataType');
    if not ((x <> nil) and (x.JSONType = jtString) and (x.AsString = 'edge')) then Exit;
    { a graph's: queryDataIndex on its edge data [F2a] }
    if FSt[ASeries].Kind = sskGraph then
    begin
      QueryEdgeIndex(SlotOfSeries(ASeries), APayload, AIdx);
      Exit(True);
    end;
    Result := True;
    x := APayload.Find('dataIndex');
    if x is TJSONArray then
    begin
      for j := 0 to x.Count - 1 do
        if (x.Items[j].JSONType = jtNumber) and (Frac(x.Items[j].AsFloat) = 0) then
        begin
          SetLength(AIdx, Length(AIdx) + 1);
          AIdx[High(AIdx)] := Trunc(x.Items[j].AsFloat);
        end;
    end
    else if (x <> nil) and (x.JSONType = jtNumber) and (Frac(x.AsFloat) = 0) then
    begin
      SetLength(AIdx, 1);
      AIdx[0] := Trunc(x.AsFloat);
    end;
  end;

  { which field queryDataIndex reads, and whether it is a list }
  function QueryIsArray: Boolean;
  var x: TJSONData;
  begin
    x := APayload.Find('dataIndexInside');
    if (x = nil) or (x.JSONType = jtNull) then x := APayload.Find('dataIndex');
    if (x = nil) or (x.JSONType = jtNull) then x := APayload.Find('name');
    Result := x is TJSONArray;
  end;

begin
  t := APayload.Strings['type'];
  isHigh := t = 'highlight';
  { getHighlightDigit: in order of first use, 1 to 32, then bit 0 }
  digit := 0;
  d := APayload.Find('highlightKey');
  if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then
  begin
    key := d.AsString;
    digit := -1;
    for i := 0 to High(FHighlightKeys) do
      if FHighlightKeys[i] = key then digit := i + 1;
    if (digit < 0) and (Length(FHighlightKeys) < 32) then
    begin
      SetLength(FHighlightKeys, Length(FHighlightKeys) + 1);
      FHighlightKeys[High(FHighlightKeys)] := key;
      digit := Length(FHighlightKeys);
    end;
    if digit < 0 then digit := 0;
  end;
  excl := nil;
  d := APayload.Find('excludeSeriesId');
  if d is TJSONArray then
  begin
    for k := 0 to TJSONArray(d).Count - 1 do
      if TJSONArray(d).Items[k].JSONType in [jtString, jtNumber] then
      begin
        SetLength(excl, Length(excl) + 1);
        excl[High(excl)] := TJSONArray(d).Items[k].AsString;
      end;
  end
  else if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then
  begin
    SetLength(excl, 1);
    excl[0] := d.AsString;
  end;

  { ONCE PER DISPATCH, before anything: every blur goes -- a batch did it
    already, once for all its items [Batch 116] }
  if not ABatchItem then StAllLeaveBlur;

  series := MatchSeries(APayload);
  kept := nil;
  for i := 0 to High(series) do
  begin
    s := series[i];
    skip := False;
    for k := 0 to High(excl) do
      if excl[k] = SeriesModelId(s) then skip := True;
    if skip then Continue;
    if (s > High(FSt)) or (FSt[s].Kind = sskNone) then Continue;
    SetLength(kept, Length(kept) + 1);
    kept[High(kept)] := s;
  end;

  { THE BLUR, a pass of its own before any series highlights }
  if isHigh and not JsTruthy(APayload.Find('notBlur')) then
    for i := 0 to High(kept) do
    begin
      s := kept[i];
      nodes[0] := StSeriesNode(s);
      if TyStReadBool(nodes, ['emphasis', 'disabled'], has) then Continue;
      slot := SlotOfSeries(s);
      { a sankey's links: the first named link's focus [Batch 114] }
      if EdgeQuery(s, inner) then
      begin
        q := 0;
        if Length(inner) > 0 then q := inner[0];
        if (q >= 0) and (q <= High(FSt[s].EdgeRows)) and FSt[s].EdgeRows[q].Host.Exists then
          focus := StEdgeFocus(s, q, scope)
        else
        begin
          if TyStFind(nodes, ['emphasis', 'focus']) = nil then Continue;
          focus := StSeriesFocus(s, scope);
        end;
        StBlurSeries(s, focus, scope);
        Continue;
      end;
      { the first index of a list; || 0 }
      q := 0;
      if QueryDataIndex(slot, APayload, inner) and (Length(inner) > 0) then q := inner[0];
      item := StItemAt(s, q);
      if item = nil then
      begin
        q := 0;
        while (item = nil) and (slot >= 0) and (slot <= High(FStores))
          and (FStores[slot] <> nil) and (q < FStores[slot].Count) do
        begin
          item := StItemAt(s, q);
          if item = nil then Inc(q);
        end;
      end;
      if item <> nil then
        focus := StItemFocus(s, StInnerRaw(s, q), scope)
      else
      begin
        { no element at all: the series' own option, only when written }
        if TyStFind(nodes, ['emphasis', 'focus']) = nil then Continue;
        focus := StSeriesFocus(s, scope);
      end;
      StBlurSeries(s, focus, scope);
    end;

  { THE EMPHASIS }
  for i := 0 to High(kept) do
  begin
    s := kept[i];
    slot := SlotOfSeries(s);
    { a sankey's links by their own indices [Batch 114] }
    if EdgeQuery(s, inner) then
    begin
      for k := 0 to High(inner) do
        if (inner[k] >= 0) and (inner[k] <= High(FSt[s].EdgeRows))
          and TyStItemDispatches(FSt[s].EdgeRows[inner[k]]) then
          Apply(FSt[s].EdgeRows[inner[k]], False, -1);
      Continue;
    end;
    has := QueryDataIndex(slot, APayload, inner);
    isArr := QueryIsArray;
    if FSt[s].IsLine then
    begin
      { _changePolyState first, whatever the payload names }
      if isHigh then StPolyTo(s, TyStHoverEmphasis) else StPolyTo(s, TyStHoverNormal);
      { one index (`dataIndex >= 0`: a list of one coerces on the downplay
        side only) -> Symbol.highlight / downplay: the path, bit 0 }
      if has and (Length(inner) > 0) then
      begin
        if isHigh then single := not isArr and (inner[0] >= 0)
        else single := (not isArr or (Length(inner) = 1)) and (inner[0] >= 0);
      end
      else
        single := False;
      if single then
      begin
        item := StItemAt(s, inner[0]);
        if item <> nil then
        begin
          if isHigh then
          begin
            if TyStItemEnterEmphasisBy(item^, 0, True, poly) then FStDirty := True;
          end
          else if TyStItemLeaveEmphasisBy(item^, 0, True, poly) then
            FStDirty := True;
        end;
        Continue;
      end;
    end;
    if not has then
    begin
      for raw := 0 to High(FSt[s].Rows) do
        { only a highDownDispatcher: emphasis not disabled }
        if TyStItemDispatches(FSt[s].Rows[raw]) then
          Apply(FSt[s].Rows[raw], False, raw);
    end
    else
      for k := 0 to High(inner) do
      begin
        item := StItemAt(s, inner[k]);
        if (item <> nil) and TyStItemDispatches(item^) then
          Apply(item^, False, StInnerRaw(s, inner[k]));
      end;
  end;
  if FStDirty then InvalidateFrame;
  if ABatchItem then Exit;
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := t;
    EmitPayloadEvent(t, ev.AsJSON);
  finally
    ev.Free;
  end;
end;

{ echarts.ts:2341-2357: the first element on the chain with a dataIndex --
  a data item, a label for its host -- dispatches unselect when it is
  selected, select otherwise, whatever selectedMode says }
procedure TTyAdvanceChart.StClickSelect(const ATarget: TTyChartEventTarget);
var
  slot, s, inner: Integer;
  selected: Boolean;
  p: string;
begin
  { [F2b] a large batch's row too: its ECData carries the row its handler
    found (BarView largePathUpdateDataIndex, LargeSymbolDraw) }
  if not (ATarget.HdKind in [1, 3, 16]) then Exit;
  s := ATarget.HdSeries;
  slot := SlotOfSeries(s);
  if slot < 0 then Exit;
  selected := False;
  inner := ATarget.HdRow;
  { a marker's element is never flagged selected: always select; nor is a
    large batch, nor a gauge's arc (updateSeriesElementSelection reaches
    the item graphic elements only) [F2b] }
  if (ATarget.HdKind = 1) and not ATarget.HdEdge and not ATarget.HdPeer then
  begin
    SelEnsure(slot);
    if (s <= High(FSel)) and FSelInit[s] then
      selected := TySelIsSelected(FSel[s], SelData(slot), ATarget.HdRow);
  end;
  { A GRAPH'S EDGE: the edge data's own inner index, selected by the one
    map [F2a] }
  if (ATarget.HdKind = 1) and ATarget.HdEdge
    and ((FBindings[slot].SeriesType = TyGraphSeriesTypeName)
      or (FBindings[slot].SeriesType = TySankeySeriesTypeName)
      or (FBindings[slot].SeriesType = TyChordSeriesTypeName)) then
  begin
    { [F3a] a sankey's link: its index is the edge data's; [R2-G] and a
      chord's ribbon's (ChordEdge's ECData: dataType 'edge') }
    if FBindings[slot].SeriesType <> TyGraphSeriesTypeName then inner := ATarget.HdRow
    else inner := StGraphEdgeInner(slot, StGraphEdgeOfRow(slot, ATarget.HdRow));
    SelEnsure(slot);
    if (s <= High(FSel)) and FSelInit[s] and (inner >= 0) then
      selected := TySelIsSelected(FSel[s], SelEdgeData(slot), inner);
  end;
  if selected then p := '{"type":"unselect"' else p := '{"type":"select"';
  { a graph's data type rides along (and a sankey's [F3a]); a tree's and a
    treemap's data is 'main' [F2a] }
  if (ATarget.HdKind = 1) and ((FBindings[slot].SeriesType = TyGraphSeriesTypeName)
    or (FBindings[slot].SeriesType = TySankeySeriesTypeName)
    or (FBindings[slot].SeriesType = TyChordSeriesTypeName)) then
  begin
    { a chord's too: ChordPiece 'node', ChordEdge 'edge' [R2-G] }
    if ATarget.HdEdge then p := p + ',"dataType":"edge"'
    else p := p + ',"dataType":"node"';
  end
  else if (ATarget.HdKind = 1) and ((FBindings[slot].SeriesType = TyTreeSeriesTypeName)
    or (FBindings[slot].SeriesType = TyTreemapSeriesTypeName)) then
    p := p + ',"dataType":"main"';
  p := p + ',"dataIndexInside":' + IntToStr(inner) + ',"seriesIndex":'
    + IntToStr(s) + ',"isFromClick":true}';
  DispatchAction(p);
end;

function TTyAdvanceChart.SelectedDataIndices(ASeriesIndex: Integer): TTyIntegerArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if slot < 0 then Exit;
  SelEnsure(slot);
  if (ASeriesIndex > High(FSel)) or not FSelInit[ASeriesIndex] then Exit;
  Result := TySelIndices(FSel[ASeriesIndex], SelData(slot));
end;

function TTyAdvanceChart.SelectedMapText(ASeriesIndex: Integer): string;
var slot: Integer;
begin
  Result := 'null';
  slot := SlotOfSeries(ASeriesIndex);
  if slot >= 0 then SelEnsure(slot);
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSel)) or not FSelInit[ASeriesIndex] then Exit;
  Result := TySelMapJson(FSel[ASeriesIndex]);
end;

function TTyAdvanceChart.TargetOfElement(AIndex: Integer): TTyChartEventTarget;
var d: TTyChartDatumRef;
begin
  d := FPaintList.Element(AIndex).Datum;
  Result := SeriesEventTarget(d, AIndex);
  Result.HdSeries := d.SeriesIndex;
  Result.HdRow := d.DataIndex;
  Result.HdEdge := d.IsEdge;
  Result.HdPeer := FPaintList.Element(AIndex).Anim.Role = carGaugeProgress;
  if d.DataIndex >= 0 then Result.HdKind := 1 else Result.HdKind := 2;
end;

function TTyAdvanceChart.ItemStates(ASeriesIndex, ADataIndex: Integer;
  out AItem: TTyStItem): Boolean;
var item: PTyStItem;
begin
  AItem := Default(TTyStItem);
  item := StItemAt(ASeriesIndex, ADataIndex);
  Result := item <> nil;
  if Result then AItem := item^;
end;

function TTyAdvanceChart.PeerStates(ASeriesIndex, ADataIndex: Integer;
  out AItem: TTyStItem): Boolean;
var item: PTyStItem;
begin
  AItem := Default(TTyStItem);
  item := StPeerAt(ASeriesIndex, ADataIndex);
  Result := item <> nil;
  if Result then AItem := item^;
end;

function TTyAdvanceChart.MarkerStates(ASeriesIndex: Integer; const APart: string;
  out AEl: TTyStElement; out AListIndex: Integer): Boolean;
var k: Integer;
begin
  AEl := Default(TTyStElement);
  AListIndex := -1;
  Result := False;
  if (ASeriesIndex < 0) or (ASeriesIndex > High(FSt)) then Exit;
  for k := 0 to Min(High(FSt[ASeriesIndex].MarkPart), High(FSt[ASeriesIndex].Marks)) do
    if FSt[ASeriesIndex].MarkPart[k] = APart then
    begin
      AEl := FSt[ASeriesIndex].Marks[k];
      AListIndex := FSt[ASeriesIndex].MarkIdx[k];
      Exit(True);
    end;
end;

function TTyAdvanceChart.SankeyEdgeStates(ASeriesIndex, AEdge: Integer;
  out AItem: TTyStItem): Boolean;
begin
  AItem := Default(TTyStItem);
  Result := StIsSankey(ASeriesIndex) and (AEdge >= 0)
    and (AEdge <= High(FSt[ASeriesIndex].EdgeRows))
    and FSt[ASeriesIndex].EdgeRows[AEdge].Host.Exists;
  if Result then AItem := FSt[ASeriesIndex].EdgeRows[AEdge];
end;

function TTyAdvanceChart.GraphForceState(ASeriesIndex: Integer): TTyGraphForceState;
begin
  Result := Default(TTyGraphForceState);
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FGraphForce)) then
    Result := FGraphForce[ASeriesIndex];
end;

function TTyAdvanceChart.LineStates(ASeriesIndex: Integer; out ARun,
  AArea: TTyStItem): Boolean;
begin
  ARun := Default(TTyStItem);
  AArea := Default(TTyStItem);
  Result := (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSt))
    and FSt[ASeriesIndex].IsLine and FSt[ASeriesIndex].Run.Host.Exists;
  if not Result then Exit;
  ARun := FSt[ASeriesIndex].Run;
  AArea := FSt[ASeriesIndex].Area;
end;

{ a tree row's emphasis: the series', `leaves` over it for a leaf-modelled
  row, the item over both }
function TTyAdvanceChart.TreeEmphasisOf(ASlot, ARow: Integer): TTyChartEmphasisSpec;
var ser, lv: TJSONData;
begin
  Result := TyChartEmphasisDefault;
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (ser is TJSONObject) then Exit;
  Result := TyChartReadEmphasis(ser);
  if (ARow <= High(FTrees[ASlot].LeafModelled)) and FTrees[ASlot].LeafModelled[ARow] then
  begin
    lv := TJSONObject(ser).Find('leaves');
    if lv is TJSONObject then
      Result := TyChartMergeEmphasis(Result, TyChartReadEmphasis(lv));
  end;
  if (ARow > 0) and (ARow <= High(FTrees[ASlot].Hier.Nodes))
    and (FTrees[ASlot].Hier.Nodes[ARow].Item is TJSONObject) then
    Result := TyChartMergeEmphasis(Result,
      TyChartReadEmphasis(FTrees[ASlot].Hier.Nodes[ARow].Item));
end;

{ `emphasis.focus` along item -> leaves -> series, as the word it is: the
  tree reads three more than any other series }
function TTyAdvanceChart.TreeFocusOf(ASlot, ARow: Integer): string;
var
  ser, d: TJSONData;
  k: Integer;
  chain: array[0..2] of TJSONData;
begin
  Result := 'none';
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (ser is TJSONObject) then Exit;
  chain[0] := nil;
  if (ARow > 0) and (ARow <= High(FTrees[ASlot].Hier.Nodes)) then
    chain[0] := FTrees[ASlot].Hier.Nodes[ARow].Item;
  chain[1] := nil;
  if (ARow <= High(FTrees[ASlot].LeafModelled)) and FTrees[ASlot].LeafModelled[ARow] then
    chain[1] := TJSONObject(ser).Find('leaves');
  chain[2] := ser;
  for k := 0 to 2 do
  begin
    if not (chain[k] is TJSONObject) then Continue;
    d := TJSONObject(chain[k]).Find('emphasis');
    if not (d is TJSONObject) then Continue;
    d := TJSONObject(d).Find('focus');
    if (d <> nil) and (d.JSONType = jtString) then Exit(d.AsString);
    if (d <> nil) and (d.JSONType <> jtNull) then Exit('none');
  end;
end;


function TTyAdvanceChart.GraphEmphasisOf(ASlot: Integer; AIsEdge: Boolean;
  AIndex: Integer): TTyChartEmphasisSpec;
var
  ser, d: TJSONData;
  arr: TJSONArray;
  sobj: TJSONObject;
  cat, raw: Integer;

  function ArrayOf(const AKey, AAlt: string): TJSONArray;
  var x: TJSONData;
  begin
    Result := nil;
    x := sobj.Find(AKey);
    if not (x is TJSONArray) then x := sobj.Find(AAlt);
    if x is TJSONArray then Result := TJSONArray(x);
  end;

begin
  Result := TyChartEmphasisDefault;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  ser := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (ser is TJSONObject) then Exit;
  sobj := TJSONObject(ser);
  Result := TyChartReadEmphasis(ser);
  { THE OLD SPELLING, only where the new one is silent. Any value but null
    turns it on -- even `false`. }
  if not Result.HasFocus then
  begin
    d := sobj.Find('focusNodeAdjacency');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      Result.Focus := cfAdjacency;
      Result.HasFocus := True;
    end;
  end;
  if AIsEdge then
  begin
    if (AIndex < 0) or (AIndex > High(FGraphEdges[ASlot])) then Exit;
    arr := ArrayOf('links', 'edges');
    raw := FGraphEdges[ASlot][AIndex].Row;
    if (arr <> nil) and (raw >= 0) and (raw < arr.Count) then
      Result := TyChartMergeEmphasis(Result, TyChartReadEmphasis(arr.Items[raw]));
    Exit;
  end;
  if (AIndex < 0) or (AIndex > High(FGraphNodes[ASlot])) then Exit;
  { THE CATEGORY IS A MODEL PARENT of its nodes. }
  cat := FGraphNodes[ASlot][AIndex].ModelCategory;
  arr := ArrayOf('categories', 'categories');
  if (arr <> nil) and (cat >= 0) and (cat < arr.Count) then
    Result := TyChartMergeEmphasis(Result, TyChartReadEmphasis(arr.Items[cat]));
  arr := ArrayOf('data', 'nodes');
  raw := FGraphNodes[ASlot][AIndex].RawRow;
  if (arr <> nil) and (raw >= 0) and (raw < arr.Count) then
    Result := TyChartMergeEmphasis(Result, TyChartReadEmphasis(arr.Items[raw]));
end;

function TTyAdvanceChart.EmphasiseElement(AIndex: Integer; APPI: Integer;
  out AElement: TTyChartElement): Boolean;
var
  spec: TTyChartEmphasisSpec;
  slot: Integer;
  ratio, half: Double;
  st: TTyChartStyle;
  normal: TTyChartStyle;
  states: TTyChartStateList;
begin
  Result := False;
  AElement := Default(TTyChartElement);
  if (FPaintList = nil) or not FPaintListValid then Exit;
  if (AIndex < 0) or (AIndex >= FPaintList.Count) then Exit;
  AElement := FPaintList.Element(AIndex);
  if AElement.Datum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(AElement.Datum.SeriesIndex);
  if slot < 0 then Exit;

  { THE SERIES' emphasis BLOCK. A data item can carry one of its own and this
    does not read it yet -- one more cascade level for a key almost nobody
    writes per datum, and the level that IS written is this one. Recorded
    rather than silently missing. }
  spec := TyChartReadEmphasis(FOption.ComponentAt('series',
    AElement.Datum.SeriesIndex));
  if spec.Disabled then Exit;

  { ---- the style ---- }
  normal := TyChartNoStyle;
  if AElement.Style.HasFill then
    TyChartSetColor(normal, cskFill, AElement.Style.FillColor);
  if AElement.Style.StrokeColor <> 0 then
    TyChartSetColor(normal, cskStroke, AElement.Style.StrokeColor);
  if AElement.Style.StrokeWidthLogical > 0 then
    TyChartSetNum(normal, cskLineWidth, AElement.Style.StrokeWidthLogical);
  TyChartSetNum(normal, cskOpacity, AElement.Style.Alpha);

  states := Default(TTyChartStateList);
  states.Emphasis := True;
  { WITH NOTHING DECLARED, AN EMPHASIS IS THE NORMAL COLOUR LIFTED -- ten per
    cent brighter. That is the default hover appearance of every bar, slice
    and symbol in ECharts, and a port that treated "no emphasis style" as "no
    change" would draw a hover that does nothing. }
  st := TyChartResolveStyle(normal,
    TyChartOverlay(spec.Item, spec.Line), states);

  if TyChartStyleHas(st, cskFill) then
  begin
    AElement.Style.HasFill := True;
    AElement.Style.FillColor := st.Color[cskFill];
  end;
  if TyChartStyleHas(st, cskStroke) then
    AElement.Style.StrokeColor := st.Color[cskStroke];
  if TyChartStyleHas(st, cskLineWidth) then
    AElement.Style.StrokeWidthLogical := st.Num[cskLineWidth];
  if TyChartStyleHas(st, cskOpacity) then
    AElement.Style.Alpha := st.Num[cskOpacity];
  { A GRADIENT IS NOT LIFTED. Upstream lifts a colour, and a ramp has no single
    colour to lift -- so a gradient-filled mark keeps its ramp and gains only
    whatever the option declared. }

  { ---- and the geometry ---- }
  case AElement.Shape.Kind of
    cskSector:
      { A SLICE GROWS ITS OUTER RADIUS BY PIXELS, not by a ratio: scaling it
        about the disc centre would lift its inner edge off the hole. }
      if spec.ScaleAuto or (spec.Scale <> 1) then
        AElement.Shape.R1 := AElement.Shape.R1
          + spec.ScaleSizePx * APPI / 96;
    cskRect, cskRoundRect, cskPolygon, cskPolyline:
      { A BAR DOES NOT GROW. Upstream scales SYMBOLS and sectors and leaves a
        bar's rectangle alone -- a bar that jumped a tenth larger under the
        pointer would look like the data had moved. }
      ;
  else
    begin
      half := (AElement.Shape.Bounds.Bottom - AElement.Shape.Bounds.Top) / 2;
      if AElement.Shape.Kind in [cskCircle, cskEllipse] then
        half := AElement.Shape.R1;
      ratio := TyChartSymbolScaleRatio(spec, half);
      AElement.Shape := TyScaleShape(AElement.Shape, ratio);
    end;
  end;
  Result := True;
end;

procedure TTyAdvanceChart.PaintEmphasis(APainter: TTyPainter; APPI: Integer;
  const AHits: TTyAxisHitArray);
var
  list: TTyPaintList;
  el: TTyChartElement;
  i, j, k, slot: Integer;
  kmS, kmK, kmI, kmE: TTyIntegerArray;

  procedure Lift(AIndex: Integer);
  var j: Integer; cap: TTyChartElement;
  begin
    if AIndex < 0 then Exit;
    { A GRAPH'S HOVER IS IN THE STATIC LAYER ALREADY -- see
      ApplyGraphHover. }
    if IsGraphDatum(FPaintList.Element(AIndex).Datum) then Exit;
    if IsTreeDatum(FPaintList.Element(AIndex).Datum) then Exit;
    { nor a treemap's [Batch 115] }
    if IsTreemapDatum(FPaintList.Element(AIndex).Datum) then Exit;
    if not EmphasiseElement(AIndex, APPI, el) then Exit;
    { THE CAPTION IS DROPPED. A mark's words were expanded once, into a
      SEPARATE element, and the copy drawn here carries the request rather
      than the answer -- rendering it would draw unplaced text at the origin. }
    el.Caption := Default(TTyElementCaption);
    list.Add(el);
    { AND ITS ANSWER IS DRAWN AGAIN OVER IT, in the hover's ink -- otherwise
      the lifted host covers its own inside label. [Revised in batch 47.] }
    for j := 0 to FPaintList.Count - 1 do
    begin
      cap := FPaintList.Element(j);
      if (cap.Caption.FontSizeLogical <= 0) or not cap.Caption.HasEmph then
        Continue;
      if (cap.Datum.SeriesIndex <> el.Datum.SeriesIndex)
        or (cap.Datum.DataIndex <> el.Datum.DataIndex)
        or (cap.Datum.IsEdge <> el.Datum.IsEdge) then Continue;
      { the block's pieces too [Batch 86] }
      TyCaptionToEmphasis(cap.Caption);
      cap.Z2 := el.Z2 + 1;
      list.Add(cap);
    end;
  end;

begin
  if (FPaintList = nil) or not FPaintListValid then Exit;
  list := TTyPaintList.Create;
  try
    { AN AXIS TRIGGER HIGHLIGHTS THE WHOLE COLUMN. Upstream calls it
      triggerEmphasis and has it on by default: the rows the tooltip is
      describing are the rows that light up, which is what ties the two
      together. }
    for i := 0 to High(AHits) do
      for k := 0 to High(AHits[i].Slots) do
      begin
        slot := AHits[i].Slots[k];
        if (slot < 0) or (slot > High(FBindings)) then Continue;
        j := FPaintList.IndexOfDatum(FBindings[slot].SeriesIndex,
          AHits[i].Rows[k]);
        { a row the states already show in emphasis is drawn so in the static
          layer [Batch 88] }
        if not StEmphasised(j) then Lift(j);
      end;
    { And an item hover highlights the one thing under the pointer -- unless
      it is one the states draw, whose hover is its flag [Batch 88]. }
    if (Length(AHits) = 0) and not StOwnsElement(FTipElement) then
      Lift(FTipElement);
    { [F5] THE KEYBOARD'S MARKER, lifted as the pointer's would be }
    if FKbStopOn and (FKbStop.Kind = ksMarkers) then
    begin
      if (KbMarkerList(kmS, kmK, kmI, kmE) > FKbPart) and (FKbPart >= 0)
        and (kmE[FKbPart] <> FTipElement) and not StOwnsElement(kmE[FKbPart]) then
        Lift(kmE[FKbPart]);
    end;
    if list.Count > 0 then TyRenderPaintList(APainter, list);
  finally
    list.Free;
  end;
end;
