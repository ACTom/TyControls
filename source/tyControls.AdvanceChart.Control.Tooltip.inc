{ Part of tyControls.AdvanceChart (included, not a unit): the tooltip and the axis pointer
  -- content, the box, the timers, and the actions that drive them. Moved out of the unit
  only to keep it readable; what the control is and why it is built the way it is, see the
  unit header. }

{ ==================== an axis' texts as tooltip targets [F4c] ==================== }

function TTyAdvanceChart.IsAxisTextDatum(const ADatum: TTyChartDatumRef): Boolean;
begin
  Result := (ADatum.Kind = ctkAxisText) and (FBuild <> nil)
    and (ADatum.ComponentIndex >= 0);
end;

{ isLabelSilent: `axisModel.get('silent')` (the axis defaults have
  `silent: false`, so the root is never reached) or neither triggerEvent
  nor a tooltip with show }
function AxisTextSilent(ANode, ARoot: TJSONData): Boolean;
var tip: TJSONData;
begin
  Result := TyOptTruthy(TyGetShallowRoot(ANode, nil, 'silent'));
  if Result then Exit;
  if TyOptTruthy(TyGetShallowRoot(ANode, nil, 'triggerEvent')) then Exit(False);
  tip := nil;
  if ANode is TJSONObject then tip := TJSONObject(ANode).Find('tooltip');
  Result := not ((tip is TJSONObject) and TyOptTruthy(TJSONObject(tip).Find('show')));
end;

function TTyAdvanceChart.AxisTextAt(AX, AY: Integer;
  out ADatum: TTyChartDatumRef): Boolean;
var
  g, a, q: Integer;
  gb: TTyGridBuild;
  axObj: TTyAxis;
  spec: PTyAxisLayoutSpec;
  meas: ITyTextMeasurer;
  lblS, nameS: TTyStyleSet;
  fw, fh: Double;
  mainT: string;
  r: TTyRectF;

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

begin
  ADatum := TyChartNoDatum;
  Result := False;
  if (FBuild = nil) or (FOption = nil) then Exit;
  meas := nil;
  { the same boxes the chart's mouse events find (EventTargetAt) }
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    for a := 0 to gb.XAxisCount + gb.YAxisCount - 1 do
    begin
      if a < gb.XAxisCount then axObj := gb.XAxis(a)
      else axObj := gb.YAxis(a - gb.XAxisCount);
      if axObj = nil then Continue;
      mainT := axObj.MainType;
      if mainT = '' then mainT := axObj.Dim + 'Axis';
      if AxisTextSilent(FOption.ComponentAt(mainT, axObj.ComponentIndex),
        FOption.Root) then Continue;
      spec := gb.SpecFor(axObj);
      if spec = nil then Continue;
      AxisTextStyles(spec, lblS, nameS);
      if spec^.NamePlacement.Shown then
      begin
        r := TyRectF(spec^.NamePlacement.Rect.X, spec^.NamePlacement.Rect.Y,
          spec^.NamePlacement.Rect.X + spec^.NamePlacement.Rect.W,
          spec^.NamePlacement.Rect.Y + spec^.NamePlacement.Rect.H);
        if Inside(r) then
        begin
          ADatum.Kind := ctkAxisText;
          ADatum.ComponentIndex := g * 1000 + a;
          ADatum.DataIndex := -1;
          Exit(True);
        end;
      end;
      for q := 0 to High(spec^.Placements) do
      begin
        if not spec^.Placements[q].Shown then Continue;
        if Length(spec^.Placements[q].Rt) > 0 then
          r := TyRtDeviceBox(spec^.Placements[q].Rt, spec^.Placements[q].X,
            spec^.Placements[q].Y, spec^.RotationRad, spec^.RtScale)
        else
        begin
          if meas = nil then meas := NewTextMeasurer(FPaintListPPI);
          fw := 0;
          fh := 0;
          if meas <> nil then
            meas.MeasureLine(spec^.Placements[q].Text, lblS.FontName,
              ResolveFontSize(lblS), lblS.FontWeight, fw, fh);
          r := Boxed(spec^.Placements[q].X, spec^.Placements[q].Y, fw, fh,
            spec^.Placements[q].AnchorH, spec^.Placements[q].AnchorV);
        end;
        if not Inside(r) then Continue;
        ADatum.Kind := ctkAxisText;
        ADatum.ComponentIndex := g * 1000 + a;
        ADatum.DataIndex := q;
        Exit(True);
      end;
    end;
  end;
end;

{ the axis of the datum: its main type and index, the text (the name, or
  the label as drawn -- the formattedLabel) and the label's rawLabel
  (scale.getLabel of its tick) }
function TTyAdvanceChart.AxisTextOf(const ADatum: TTyChartDatumRef; out AMainType,
  AName, AValue: string; out AIndex: Integer): Boolean;
var
  g, a: Integer;
  gb: TTyGridBuild;
  axObj: TTyAxis;
  spec: PTyAxisLayoutSpec;
begin
  Result := False;
  AMainType := '';
  AName := '';
  AValue := '';
  AIndex := -1;
  if not IsAxisTextDatum(ADatum) then Exit;
  g := ADatum.ComponentIndex div 1000;
  a := ADatum.ComponentIndex mod 1000;
  if g >= FBuild.GridCount then Exit;
  gb := FBuild.Grid(g);
  if a >= gb.XAxisCount + gb.YAxisCount then Exit;
  if a < gb.XAxisCount then axObj := gb.XAxis(a)
  else axObj := gb.YAxis(a - gb.XAxisCount);
  if axObj = nil then Exit;
  spec := gb.SpecFor(axObj);
  if spec = nil then Exit;
  AMainType := axObj.MainType;
  if AMainType = '' then AMainType := axObj.Dim + 'Axis';
  AIndex := axObj.ComponentIndex;
  if ADatum.DataIndex < 0 then
  begin
    if not spec^.NamePlacement.Shown then Exit;
    AName := spec^.NamePlacement.Text;
  end
  else
  begin
    if ADatum.DataIndex > High(spec^.Placements) then Exit;
    AName := spec^.Placements[ADatum.DataIndex].Text;
    if (axObj.Scale is TTyOrdinalScale) and (ADatum.DataIndex <= High(spec^.TickValues)) then
      AValue := TTyOrdinalScale(axObj.Scale).GetLabel(spec^.TickValues[ADatum.DataIndex])
    else
      AValue := AName;
  end;
  Result := True;
end;

function TTyAdvanceChart.AxisTipSpec(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
var
  mainT, nm, v: string;
  idx: Integer;
  node, tip: TJSONData;
begin
  if not AxisTextOf(ADatum, mainT, nm, v, idx) then
    Exit(TyTooltipSpecOf(FOption, -1, -1));
  { [R2-I8] the content, encodeHTML'd in html mode (setTooltipConfig) }
  Result := TyTooltipSpecOfItem(FOption, mainT, idx, nil, TipContentName(nm));
  { the axis' defaults: `tooltip: {show: false}` under what it writes -- a
    show it does not write is false, before the global's is asked (a null
    one is no value, and the global's stands) }
  node := FOption.ComponentAt(mainT, idx);
  tip := nil;
  if node is TJSONObject then tip := TJSONObject(node).Find('tooltip');
  if not ((tip is TJSONObject) and (TJSONObject(tip).IndexOfName('show') >= 0)) then
    Result.Show := False;
end;

{ setTooltipConfig's formatterParams: componentType, name, <mainType>Index;
  a label's value (rawLabel) and tickIndex besides }
function TTyAdvanceChart.AxisTipParams(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
var
  mainT, nm, v: string;
  idx: Integer;
begin
  Result := TyChartBlankParams;
  if not AxisTextOf(ADatum, mainT, nm, v, idx) then Exit;
  Result.ComponentType := mainT;
  Result.ComponentIndex := idx;
  Result.AxisIndex := idx;
  Result.Name := nm;
  if ADatum.DataIndex >= 0 then
  begin
    Result.ValueText := v;
    Result.TickIndex := ADatum.DataIndex;
    Result.TargetType := 'axisLabel';
  end
  else
    Result.TargetType := 'axisName';
end;

{ the formatter through formatTpl with the item's $vars -- the name's
  ['name'], a label's ['name', 'isTruncated', 'value', 'tickIndex'],
  HTML-encoded -- else the content (the text) }
function TTyAdvanceChart.AxisTipText(const ADatum: TTyChartDatumRef;
  const ASpec: TTyTooltipSpec): string;
var
  mainT, nm, v, tpl: string;
  idx: Integer;
  params: TTyChartParams;
begin
  Result := '';
  if not AxisTextOf(ADatum, mainT, nm, v, idx) then Exit;
  if not ASpec.HasFormatter then Exit(TipContentName(nm));
  if TyChartIsHandlerRef(ASpec.Formatter) then
  begin
    SetLength(params, 1);
    params[0] := AxisTipParams(ADatum);
    TyChartResolveText(ASpec.Formatter, params, Result);
    Exit;
  end;
  tpl := TyJsReplaceFirst(ASpec.Formatter, '{a}', '{a0}');
  if ADatum.DataIndex >= 0 then
  begin
    tpl := TyJsReplaceFirst(tpl, '{b}', '{b0}');
    tpl := TyJsReplaceFirst(tpl, '{c}', '{c0}');
    tpl := TyJsReplaceFirst(tpl, '{d}', '{d0}');
  end;
  tpl := TyJsReplaceFirst(tpl, '{a0}', GeoEncodeHtml(nm));
  if ADatum.DataIndex >= 0 then
  begin
    { isTruncated is a function upstream: its text is not modelled -- the
      port's labels are never truncated, so `false` }
    tpl := TyJsReplaceFirst(tpl, '{b0}', 'false');
    tpl := TyJsReplaceFirst(tpl, '{c0}', GeoEncodeHtml(v));
    tpl := TyJsReplaceFirst(tpl, '{d0}', IntToStr(ADatum.DataIndex));
  end;
  Result := tpl;
end;

{ LinesSeries.formatTooltip: one bare row, the item's name -- `name` read
  through the item model, so a named series lends its name to an unnamed
  item -- else 'from > to', and the raw value unless it is not a number }
function TTyAdvanceChart.LinesTooltip(const ADatum: TTyChartDatumRef;
  out ABlock: TTyTooltipBlock): Boolean;
var
  slot: Integer;
  raw: TTyLinesRaw;
  nm, vt: string;
  d: TJSONData;
  node: TJSONObject;
  noValue: Boolean;
  v: Double;
begin
  ABlock := nil;
  Result := False;
  if (ADatum.Kind <> ctkSeries) or ADatum.IsEdge then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if (slot < 0) or (slot > High(FLines)) or not FLines[slot].Valid then Exit;
  if (ADatum.DataIndex < 0) or (ADatum.DataIndex > High(FLines[slot].Raws)) then Exit;
  Result := True;
  raw := FLines[slot].Raws[ADatum.DataIndex];
  node := nil;
  d := FOption.ComponentAt('series', ADatum.SeriesIndex);
  if d is TJSONObject then node := TJSONObject(d);
  if raw.HasName then nm := raw.Name
  else
  begin
    nm := '';
    d := LnNode(node, ['name']);
    if (d <> nil) and (d.JSONType = jtString) then nm := d.AsString
    else if (d <> nil) and (d.JSONType = jtNumber) then nm := TyJsNumberToString(d.AsFloat);
  end;
  if nm = '' then
  begin
    if raw.HasFromName then nm := raw.FromName;
    if raw.HasToName then
    begin
      if raw.HasFromName then nm := nm + ' > ' + raw.ToName
      else nm := raw.ToName;
    end;
  end;
  { makeValueReadable of the name: nothing is '-' }
  if Trim(nm) = '' then nm := '-';
  noValue := True;
  vt := '';
  if raw.RawIsFlat then
  begin
    noValue := False;
    vt := TyTooltipValueText(0);
  end
  else if (not raw.RawNone) and (raw.RawJson <> nil) then
  begin
    v := TyLinesJsNum(raw.RawJson);
    if (raw.RawJson is TJSONArray) and (raw.RawJson.Count <> 1) then v := NaN;
    if raw.RawJson.JSONType = jtObject then v := NaN;
    noValue := IsNan(v);
    if not noValue then
    begin
      if raw.RawJson.JSONType = jtString then vt := raw.RawJson.AsString
      else vt := TyTooltipValueText(v);
    end;
  end;
  ABlock := TTyTooltipBlock.CreateSection('', True);
  ABlock.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, nm, False, vt, noValue));
end;

procedure TTyAdvanceChart.HeatmapTipDims(ASlot: Integer;
  const AEnc: TTySeriesEncode; AStore: TTyDataStore);
var tip: TTyIntegerArray;
begin
  if (AStore = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FBindings[ASlot].SeriesType <> 'heatmap' then Exit;
  { encode.tooltip, then encode.label, as for any series }
  if Length(AEnc.Tooltip) > 0 then Exit;
  if Length(AEnc.Labels) > 0 then tip := Copy(AEnc.Labels)
  else
  begin
    { createSeriesData(generateCoord: 'value'): the element past x and y is
      a coordinate of its own, not extra, a float -- the last one a label
      suits, and so the tooltip's }
    SetLength(tip, 1);
    tip[0] := 2;
  end;
  AStore.SetTooltipPositions(tip);
end;

function TTyAdvanceChart.TipStateKey: string;
var
  i, k: Integer;

  function H(A: Double): string;
  begin
    Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
  end;

begin
  Result := BoolToStr(FTipShown, '1', '0') + '|' + H(FTipSnap.X) + ',' + H(FTipSnap.Y)
    + '|' + IntToStr(Ord(FTipSnap.Datum.Kind)) + ',' + IntToStr(FTipSnap.Datum.SeriesIndex)
    + ',' + IntToStr(FTipSnap.Datum.DataIndex) + ',' + IntToStr(FTipSnap.Datum.ComponentIndex)
    + ',' + BoolToStr(FTipSnap.Datum.IsEdge, '1', '0') + ',' + IntToStr(FTipSnap.Element)
    + '|' + FTipSnap.DbcJson + '|' + BoolToStr(FTipSnap.Frozen, '1', '0') + H(FTipSnap.FrozenX)
    + ',' + H(FTipSnap.FrozenY) + '|' + FTipSnap.PosJson;
  for i := 0 to High(FTipSnap.Hits) do
  begin
    Result := Result + '|s' + IntToHex(PtrUInt(FTipSnap.Hits[i].Axis), 16) + H(FTipSnap.Hits[i].Value)
      + ',' + H(FTipSnap.Hits[i].SnapValue);
    for k := 0 to High(FTipSnap.Hits[i].Rows) do
      Result := Result + ',' + IntToStr(FTipSnap.Hits[i].Slots[k]) + ':' + IntToStr(FTipSnap.Hits[i].Rows[k]);
  end;
  for i := 0 to High(FTipHits) do
  begin
    Result := Result + '|p' + IntToHex(PtrUInt(FTipHits[i].Axis), 16) + H(FTipHits[i].Value)
      + ',' + H(FTipHits[i].SnapValue) + BoolToStr(FTipHits[i].Cross, 'c', '');
    for k := 0 to High(FTipHits[i].Rows) do
      Result := Result + ',' + IntToStr(FTipHits[i].Slots[k]) + ':' + IntToStr(FTipHits[i].Rows[k]);
  end;
end;

procedure TTyAdvanceChart.TipInvalidate;
begin
  { zrender marks what changed: a box or a pointer that is where it was
    marks nothing (the frame is asked for as before) }
  if TipStateKey <> FTipPaintedKey then FZrDirty := True;
  InvalidateFrameQuiet;
end;

{ ==================== the tooltip ==================== }

function TTyAdvanceChart.TooltipSpecFor(
  const ADatum: TTyChartDatumRef): TTyTooltipSpec;
var
  kind: TTyMarkerKind;
  blk: TTyMkBlock;
  it, opt: Integer;
  mx: TTyMatrix;
  info: TTyMatrixCellInfo;
begin
  { A MATRIX CELL'S: the matrix's tooltip, the matrix, its name as the
    formatter [Batch 147] }
  if TipIsMatrix(ADatum) then
  begin
    MatrixCellOf(ADatum, mx, info);
    Exit(TyTooltipSpecOfMatrix(FOption, ADatum.ComponentIndex,
      TipContentName(info.TipName)));
  end;
  { A MARKER'S CASCADE IS ITS OWN [Batch 100]: its data item, the marker,
    the global -- never the host series' }
  { [Batch 148] a geo region's: the component item's cascade }
  if IsGeoDatum(ADatum) then Exit(GeoTipSpec(ADatum));
  { [F4c] an axis' name or label: the axis' cascade }
  if IsAxisTextDatum(ADatum) then Exit(AxisTipSpec(ADatum));
  if TipIsMarker(ADatum) then
  begin
    opt := -1;
    if MarkerItemOf(ADatum, kind, blk, it) then
      case kind of
        mkPoint: opt := blk.Points[it].Index;
        mkLine: opt := blk.Lines[it].Index;
        mkArea: opt := blk.Areas[it].Index;
      end
    else
      case ADatum.Kind of
        ctkMarkLine: kind := mkLine;
        ctkMarkArea: kind := mkArea;
      else
        kind := mkPoint;
      end;
    Exit(TyTooltipSpecOfMarker(FOption, ADatum.ComponentIndex,
      TyMarkerKey[kind], opt));
  end;
  { THE RAW ROW, not the view row. A data-item tooltip is written beside the
    datum in the option text, and the option text is the raw order -- a filter
    is a view for readers and has never moved anything in the tree. }
  { A GRAPH LINK has a row of its own, in the LINK list, and a node's tooltip
    written at that position is somebody else's -- so a link takes the
    series'. }
  if ADatum.IsEdge then
    Result := TyTooltipSpecOf(FOption, ADatum.SeriesIndex, -1)
  else
    Result := TyTooltipSpecOf(FOption, ADatum.SeriesIndex, ADatum.RawDataIndex);
end;

function TTyAdvanceChart.TooltipInk(
  const ASpec: TTyTooltipSpec): TTyTooltipInk;
var
  nameS, valueS: TTyStyleSet;
  model: TTyStyleModel;
begin
  model := ActiveController.Model;
  nameS := model.ResolveStyle('TyAdvChartTooltip', StyleClass, [tysNormal]);
  valueS := model.ResolveStyle('TyAdvChartTooltipValue', '', []);

  Result.NameFontName := nameS.FontName;
  Result.NameSizeLogical := ResolveFontSize(nameS);
  Result.NameWeight := nameS.FontWeight;
  Result.NameColour := TTyChartColor(nameS.TextColor);

  Result.ValueFontName := valueS.FontName;
  if Result.ValueFontName = '' then Result.ValueFontName := nameS.FontName;
  Result.ValueSizeLogical := ResolveFontSize(valueS);
  Result.ValueWeight := valueS.FontWeight;
  Result.ValueColour := TTyChartColor(valueS.TextColor);

  { THE OPTION LAST, over whatever the theme said. ECharts' textStyle is one
    object for both roles, so a written colour or size takes BOTH -- the
    hierarchy a theme drew with two keys collapses into one, which is exactly
    what writing `tooltip.textStyle` asks for. }
  if ASpec.HasTextColour then
  begin
    Result.NameColour := ASpec.TextColour;
    Result.ValueColour := ASpec.TextColour;
  end;
  if ASpec.HasTextSize then
  begin
    Result.NameSizeLogical := TyFontSizeFromPx(ASpec.TextSizeLogical);  // CSS px [Batch 83]
    Result.ValueSizeLogical := Result.NameSizeLogical;
  end;

  { UPSTREAM'S OWN HTML RULE -- round(fontSize * 3 / 2) -- and NOT its richText
    one, which is a flat 22 whatever the font is. A library whose themes change
    the type scale cannot carry a constant here: a dense skin at 11px would get
    a box of double-spaced rows and a display skin at 20px would get overlapping
    ones. Recorded as a deliberate divergence. }
  { in the point units the sizes were always given in: a pixel size is
    brought back to its point equivalent first [Batch 83] }
  Result.LineHeightLogical :=
    Round(Max(TyFontPxOf(Result.NameSizeLogical),
      TyFontPxOf(Result.ValueSizeLogical)) * 72 / 96 * 3 / 2);

  Result.MarkerSizeLogical := ActiveController.Metric(
    TyAdvChartTooltipMarkerVar, TyAdvChartTooltipMarker);
  Result.MarkerGapLogical := ActiveController.Metric(
    TyAdvChartTooltipMarkerGapVar, TyAdvChartTooltipMarkerGap);
  Result.GutterLogical := ActiveController.Metric(
    TyAdvChartTooltipGutterVar, TyAdvChartTooltipGutter);
  { The narrow gutter is half the wide one upstream (10 against 20), so it
    follows a skin that retuned the wide one instead of being a fifth metric
    nobody would think to change. }
  Result.GutterCloseLogical := Result.GutterLogical / 2;
  if Result.MarkerSizeLogical < 0 then Result.MarkerSizeLogical := 0;
  if Result.MarkerGapLogical < 0 then Result.MarkerGapLogical := 0;
  if Result.GutterLogical < 0 then Result.GutterLogical := 0;
end;

function TTyAdvanceChart.DatumColour(
  const ADatum: TTyChartDatumRef): TTyChartColor;
var
  slot, idx: Integer;
  perDatum: Boolean;
  el: TTyChartElement;
  v: TTySeriesVisual;
  gi: TTyGraphInk;
begin
  Result := 0;
  { THE SERIES' COLOUR WITH THE ROW'S OVERRIDE, which is what upstream's marker
    is: it reads `style[series.visualDrawType]`, and drawType names the colour
    the visual pipeline WROTE -- not whichever slot a symbol later painted it
    into.

    ASKING THE DRAWN ELEMENT LOOKED RIGHT AND WAS WRONG. A line's default
    marker is an `emptyCircle`: a ring in the series colour over the chart's
    own ground, so its element's FILL is the background, and a tooltip reading
    it drew an invisible white dot on a white box. Falling back to the stroke
    is no answer either, because a bar carries its colour in the fill. What
    the marker names is a SERIES and a ROW, so that is what it asks. }
  { [Batch 100] A MARKER'S is its own visual: the symbol's fill, the line's
    stroke, the area's fill }
  if TipIsMarker(ADatum) then Exit(MarkerColour(ADatum));
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if slot < 0 then Exit;
  { [Batch 100] A SUNBURST SECTOR, A TREEMAP RECTANGLE, A SANKEY NODE: the
    node's colour visual; a sankey link has none (upstream's params.color is
    undefined there) }
  if (FBindings[slot].SeriesType = TySunburstSeriesTypeName)
    and (slot <= High(FSunbursts)) and FSunbursts[slot].Valid then
  begin
    if (ADatum.DataIndex >= 0) and (ADatum.DataIndex <= High(FSunbursts[slot].Nodes)) then
      Result := FSunbursts[slot].Nodes[ADatum.DataIndex].Fill;
    { the return circle's own colour, the theme's where none is named
      [Batch 115] }
    if (ADatum.DataIndex = 0) and not FSunbursts[slot].HasRootFill then
      Result := SunburstInk(slot).RootFill;
    Exit;
  end;
  if (FBindings[slot].SeriesType = TyTreemapSeriesTypeName)
    and (slot <= High(FTreemaps)) and FTreemaps[slot].Valid then
  begin
    if (ADatum.DataIndex >= 0) and (ADatum.DataIndex <= High(FTreemaps[slot].Nodes))
      and FTreemaps[slot].Nodes[ADatum.DataIndex].HasFill then
      Result := FTreemaps[slot].Nodes[ADatum.DataIndex].Fill;
    Exit;
  end;
  if (FBindings[slot].SeriesType = TySankeySeriesTypeName)
    and (slot <= High(FSankeys)) and FSankeys[slot].Valid then
  begin
    if (not ADatum.IsEdge) and (ADatum.DataIndex >= 0)
      and (ADatum.DataIndex <= High(FSankeys[slot].Nodes))
      and FSankeys[slot].Nodes[ADatum.DataIndex].HasColour then
      Result := FSankeys[slot].Nodes[ADatum.DataIndex].Colour;
    Exit;
  end;
  { A CHORD NODE: its colour visual; a ribbon has none (params.color is
    undefined for the edge data) [Batch 120] }
  if (FBindings[slot].SeriesType = TyChordSeriesTypeName)
    and (slot <= High(FChords)) and FChords[slot].Valid then
  begin
    if (not ADatum.IsEdge) and (ADatum.RawDataIndex >= 0)
      and (ADatum.RawDataIndex <= High(FChords[slot].Nodes))
      and FChords[slot].Nodes[ADatum.RawDataIndex].HasColour then
      Result := FChords[slot].Nodes[ADatum.RawDataIndex].Colour;
    Exit;
  end;
  { A PARALLEL ROW'S IS ITS STROKE: drawType 'stroke' [Batch 128] }
  if (FBindings[slot].SeriesType = TyParallelSeriesTypeName)
    and (slot <= High(FParSolved)) and FParSolved[slot].Valid then
  begin
    if (ADatum.DataIndex >= 0) and (ADatum.DataIndex <= High(FParSolved[slot].Rows)) then
      Exit(FParSolved[slot].Rows[ADatum.DataIndex].Stroke);
    Exit(TTyChartColor(SeriesColor(ADatum.SeriesIndex)));
  end;
  { A GRAPH LINK'S COLOUR IS ITS STROKE, found by its own row. }
  if ADatum.IsEdge then
  begin
    if (FBindings[slot].SeriesType = TyGraphSeriesTypeName)
      and (slot <= High(FGraphEdges)) and (slot <= High(FGraphSpecs)) then
    begin
      gi := GraphInk(slot);
      for idx := 0 to High(FGraphEdges[slot]) do
        if FGraphEdges[slot][idx].Row = ADatum.DataIndex then
          Exit(TyGraphEdgeStroke(FGraphSpecs[slot], FGraphEdges[slot], gi, idx));
    end;
    Exit;
  end;
  { A GRAPH NODE'S MARKER IS THE NODE'S FILL -- its category's colour, or its
    own -- found by the node's VIEW row. Not through the paint list: a graph's
    edges number their data in the same space as its nodes, so the first
    element carrying a datum could be an edge. }
  if (FBindings[slot].SeriesType = TyGraphSeriesTypeName)
    and (slot <= High(FGraphNodes)) then
  begin
    gi := GraphInk(slot);
    for idx := 0 to High(FGraphNodes[slot]) do
      if (FGraphNodes[slot][idx].Row = ADatum.DataIndex)
        and (idx <= High(gi.NodeFills)) then
        Exit(gi.NodeFills[idx]);
  end;
  v := TySeriesVisual(TTyChartColor(SeriesColor(ADatum.SeriesIndex)));
  ApplyOptStyle(v, ADatum.SeriesIndex);
  { the marker is the ITEM's colour, so what a visualMap wrote on it too }
  ApplyVisualMaps(v, slot, 0);
  Result := v.Fill;
  if (slot <= High(FStores)) and (FStores[slot] <> nil)
    and (ADatum.DataIndex >= 0) and (ADatum.DataIndex < FStores[slot].Count) then
  begin
    { [R2-J2] and what the series' colour callback answered for it }
    VisualCallbacks(slot, v, ADatum.DataIndex);
    Result := TyRowFill(v, FStores[slot], ADatum.DataIndex);
  end;

  { SOME SERIES HAVE NO SINGLE COLOUR. A pie's slices take consecutive palette
    slots; a candlestick's bodies are red or green by the datum's own two
    numbers. Asking the SERIES paints every marker of those alike, so for them
    the answer is read off the drawn element -- right here for the same reason
    it was wrong above, because both are FILLED shapes and a filled shape's
    fill IS its colour.

    FOUND BY DATUM, not taken from the hovered element: under an axis trigger
    the pointer is usually nowhere near the mark being described, and the
    element it happens to be over belongs to something else or to nothing. }
  { THE SAME LIST THE LEGEND ASKS. It read `= 'pie'` while a funnel and a
    radar colour by datum in exactly the same way, so their markers took the
    flat series colour and disagreed with the band or the ring under the
    pointer. }
  perDatum := TySeriesLegendByDatum(FBindings[slot].SeriesType)
    or (Length(FStores[slot].DimsOfCoord(
      AxisDimOf(FBindings[slot].ValueAxis))) > 1);
  if perDatum and (FPaintList <> nil) and FPaintListValid then
  begin
    idx := FPaintList.IndexOfDatumInk(ADatum.SeriesIndex, ADatum.DataIndex);
    if idx >= 0 then
    begin
      el := FPaintList.Element(idx);
      if el.Style.HasFill and (el.Style.FillColor <> 0) then
        Result := el.Style.FillColor
      { A RING HAS NO FILL. A radar's row is a stroked polyline, so the colour
        that stands for it is its STROKE -- and a filled-shape-only rule left
        every radar marker on the series colour, which is the one thing a
        series colouring by datum does not have. }
      else if (not el.Style.HasFill) and (el.Style.StrokeColor <> 0)
        and (el.Style.StrokeWidthLogical > 0) then
        Result := el.Style.StrokeColor;
    end;
  end;
end;

function TTyAdvanceChart.TooltipParams(
  const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
var
  mx: TTyMatrix;
  info: TTyMatrixCellInfo;
  slot, i, n: Integer;
  cols: TTyIntegerArray;
  st: TTyDataStore;
  pct: TTyDoubleArray;
  tv: Double;
  tvText: string;
begin
  if TipIsMarker(ADatum) then Exit(MarkerTooltipParams(ADatum));
  { a matrix cell's formatterParams: componentType, name, matrixIndex and
    xyLocator [Batch 147] }
  if MatrixCellOf(ADatum, mx, info) then
  begin
    Result := TyChartBlankParams;
    Result.ComponentType := 'matrix';
    Result.ComponentIndex := ADatum.ComponentIndex;
    Result.Name := info.TipName;
    SetLength(Result.Coord, 2);
    Result.Coord[0] := info.Loc[0];
    Result.Coord[1] := info.Loc[1];
    Exit;
  end;
  Result := TyChartBlankParams;
  Result.ComponentType := 'series';
  Result.SeriesIndex := ADatum.SeriesIndex;
  Result.DataIndex := ADatum.DataIndex;
  Result.RawDataIndex := ADatum.RawDataIndex;
  Result.Color := DatumColour(ADatum);
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if slot < 0 then Exit;
  Result.SeriesType := FBindings[slot].SeriesType;
  Result.SeriesName := SeriesModelName(ADatum.SeriesIndex);
  { [R2-E] a sunburst's, a treemap's and a sankey's own getDataParams }
  if HierTipParams(ADatum, slot, Result) then Exit;
  if slot > High(FStores) then Exit;
  st := FStores[slot];
  if st = nil then Exit;
  if (Result.SeriesType = TyGraphSeriesTypeName)
    or (Result.SeriesType = TyChordSeriesTypeName) then
  begin
    if ADatum.IsEdge then Result.DataType := 'edge'
    else Result.DataType := 'node';
  end;
  { A CHORD LINK: the edge data's params -- its name (the link's id, else
    `source > target` as written) and its own value [Batch 120] }
  if ADatum.IsEdge and (Result.SeriesType = TyChordSeriesTypeName) then
  begin
    if (slot > High(FChords)) or not FChords[slot].Valid then Exit;
    if (ADatum.RawDataIndex < 0) or (ADatum.RawDataIndex > High(FChords[slot].Edges)) then Exit;
    Result.Name := FChords[slot].Edges[ADatum.RawDataIndex].Name;
    if TyChordEdgeRawValue(FChords[slot], ADatum.RawDataIndex, tv, tvText)
      and not IsNan(tv) then
    begin
      SetLength(Result.Values, 1);
      Result.Values[0] := tv;
    end;
    Exit;
  end;
  { A GRAPH LINK IS NAMED BY ITS TWO ENDS, `source > target`, each the name
    upstream's getName answers -- so a link between two bare numbers on a
    category axis reads 'Mon > Tue'. Its value is the link's own, and most
    links have none. }
  if ADatum.IsEdge then
  begin
    if slot > High(FGraphEdges) then Exit;
    for i := 0 to High(FGraphEdges[slot]) do
      if FGraphEdges[slot][i].Row = ADatum.DataIndex then
      begin
        Result.Name := GraphNodeName(slot, FGraphEdges[slot][i].Source)
          + ' > ' + GraphNodeName(slot, FGraphEdges[slot][i].Target);
        if not IsNan(FGraphEdges[slot][i].Value) then
        begin
          SetLength(Result.Values, 1);
          Result.Values[0] := FGraphEdges[slot][i].Value;
        end;
        Break;
      end;
    Exit;
  end;
  if (ADatum.DataIndex < 0) or (ADatum.DataIndex >= st.Count) then Exit;

  { THE NAME UPSTREAM CALLS `data.getName(dataIndex)`. On a category axis it is
    the category; on two value axes there is none, because the default encode
    only assigns an item name "the category way". A line on a value x axis
    therefore shows a dot and a number and no words -- which is upstream's
    picture, not a gap in this. The store answers it, by the same rule the
    label's b placeholder asks. }
  Result.Name := st.GetItemName(ADatum.DataIndex);
  Result.Raw := st.RawItem(ADatum.DataIndex);

  { THE d LETTER, which only a pie and a funnel have: the pie's seats (the
    largest-remainder shares, to percentPrecision) and the funnel's two-place
    share, both over the slices there are. Everywhere else `{d}` is no
    letter at all and a template leaves it as written. }
  if (Result.SeriesType = TyPieSeriesTypeName) and (slot <= High(FPies)) then
  begin
    Result.HasPercent := True;
    pct := TyPieSectorPercents(FPies[slot], FPieSpecs[slot].PercentPrecision);
    for i := 0 to High(FPies[slot].Sectors) do
      if FPies[slot].Sectors[i].Index = ADatum.DataIndex then
        Result.Percent := pct[i];
  end
  else if (Result.SeriesType = TyFunnelSeriesTypeName)
    and (slot <= High(FFunnels)) then
  begin
    Result.HasPercent := True;
    pct := TyFunnelPercents(FFunnels[slot]);
    for i := 0 to High(FFunnels[slot].Items) do
      if FFunnels[slot].Items[i].Index = ADatum.DataIndex then
        Result.Percent := pct[i];
  end;

  { WHICH VALUES, PLURAL. Upstream's `tooltipDims` is every data dimension
    mapped onto the value coordinate -- one for a bar, a line or a pie, and
    FOUR for a candlestick, which is why `mapDimensionsAll` is the plural
    spelling there and `mapDimension` is not. A port that took one column
    showed a candle's highest and called it the value. }
  cols := nil;
  if FBindings[slot].ValueAxis <> nil then
    cols := st.DimsOfCoord(FBindings[slot].ValueAxis.Dim);
  if Length(cols) = 0 then
  begin
    { A pie has no axes at all; its one dimension is the value. }
    n := st.DimCount;
    for i := n - 1 downto 0 do
      if st.DimType(i) <> ddtOrdinal then
      begin
        SetLength(cols, 1);
        cols[0] := i;
        Break;
      end;
  end;
  if Length(cols) = 0 then Exit;
  SetLength(Result.Values, Length(cols));
  SetLength(Result.DimensionNames, Length(cols));
  for i := 0 to High(cols) do
  begin
    Result.Values[i] := st.Get(cols[i], ADatum.DataIndex);
    Result.DimensionNames[i] := st.DimName(cols[i]);
  end;
  { EACH VALUE'S RAW CELL, at the position its dimension was read from. }
  if Result.Raw.Shape = rshNone then Exit;
  SetLength(Result.RawCells, Length(cols));
  SetLength(Result.RawTypes, Length(cols));
  for i := 0 to High(cols) do
  begin
    if not TTyDataStore.RawCell(Result.Raw, st.RawDimPos(cols[i]),
      Result.RawCells[i]) then
      Result.RawCells[i] := Default(TTyDataValue);
    Result.RawTypes[i] := st.DimType(cols[i]);
  end;
end;

type
  { One series' tooltip cells, upstream's defaultSeriesFormatTooltip: the
    texts (inline, joined by two spaces, or one per sub-row), the sub-rows'
    names, and what `order` sorts the series by. Valid False: the store kept
    no raw item or chose no tooltip dimensions, and the caller keeps its own
    rule. }
  TTyTipCells = record
    Valid, MultiLine: Boolean;
    Texts, Names: TTyStringArray;
    { each cell as String() prints it, for a valueFormatter handler }
    Raws: TTyStringArray;
    Sort: TTyDataValue;
  end;

{ makeValueReadable with a type: a TIME is formatted
  `yyyy-MM-dd HH:mm:ss`, in UTC under `useUTC` -- a number as epoch ms, text
  through the date parser (local unless it says otherwise) -- and anything
  that is no date falls to the untyped rules. }
function TipReadable(const ACell: TTyDataValue; AType: TTyDimType;
  AUTC: Boolean): string;
var ms: Double; ok: Boolean;
begin
  if AType = ddtTime then
  begin
    ok := False;
    ms := NaN;
    case ACell.Kind of
      dvkNumber, dvkBool:
        if not (IsNan(ACell.Num) or IsInfinite(ACell.Num)) then
        begin
          ms := TyJsRound(ACell.Num);
          ok := True;
        end;
      dvkText:
        ok := TyParseDateMs(ACell.Text, ms, False);
    end;
    if ok and not IsNan(ms) then
      Exit(TyFormatTime(ms, '{yyyy}-{MM}-{dd} {HH}:{mm}:{ss}', AUTC));
    AType := ddtFloat;
  end;
  Result := TyReadableCell(ACell, AType);
end;

function TipCellsOf(AStore: TTyDataStore; ARow: Integer;
  AUTC: Boolean): TTyTipCells;
var
  raw: TTyRawItem;
  pos: TTyIntegerArray;
  n, i: Integer;
  info: TTyRawDimInfo;
  c: TTyDataValue;
  haveFirst: Boolean;

  procedure Put(APos: Integer; const ACell: TTyDataValue);
  var k: Integer;
  begin
    info := AStore.RawDimInfo(APos);
    k := Length(Result.Texts);
    SetLength(Result.Texts, k + 1);
    SetLength(Result.Names, k + 1);
    SetLength(Result.Raws, k + 1);
    Result.Raws[k] := TyJsValueText(ACell, '');
    Result.Texts[k] := TipReadable(ACell, AStore.RawPosType(APos), AUTC);
    Result.Names[k] := '';
    if info.HasDisplay then Result.Names[k] := info.Display;
    if not haveFirst then
    begin
      Result.Sort := ACell;
      haveFirst := True;
    end;
  end;

begin
  Result := Default(TTyTipCells);
  if (AStore = nil) or not AStore.HasTooltipPositions then Exit;
  raw := AStore.RawItem(ARow);
  if raw.Shape = rshNone then Exit;
  Result.Valid := True;
  haveFirst := False;
  pos := AStore.TooltipPositions;
  n := Length(pos);
  if (n > 1) or ((raw.Shape = rshArray) and (n = 0)) then
  begin
    { SUB-ROWS WHEN ANY POSITION OF THE ITEM HAS A DISPLAY NAME -- every
      position the item has, shown or not; one a short item lacks does not
      count. }
    if raw.Shape = rshArray then
      for i := 0 to Min(High(raw.Cells), AStore.RawWidth - 1) do
      begin
        info := AStore.RawDimInfo(i);
        if info.HasDisplay then Result.MultiLine := True;
      end;
    if n > 0 then
      for i := 0 to n - 1 do
      begin
        if not TTyDataStore.RawCell(raw, pos[i], c) then c := Default(TTyDataValue);
        Put(pos[i], c);
      end
    else
      { NO TOOLTIP DIMENSION: every element the data has a dimension for. }
      for i := 0 to Min(High(raw.Cells), AStore.RawWidth - 1) do
        Put(i, raw.Cells[i]);
    { upstream sorts on the first INLINE value -- which a sub-row series has
      none of. }
    if Result.MultiLine then Result.Sort := Default(TTyDataValue);
  end
  else if n = 1 then
  begin
    if not TTyDataStore.RawCell(raw, pos[0], c) then c := Default(TTyDataValue);
    SetLength(Result.Texts, 1);
    SetLength(Result.Names, 1);
    Result.Texts[0] := TipReadable(c, AStore.RawPosType(pos[0]), AUTC);
    Result.Sort := c;
  end
  else
  begin
    { NOTHING TO CHOOSE FROM and no array: the value itself, untyped. }
    c := Default(TTyDataValue);
    if raw.Shape = rshScalar then c := raw.Scalar;
    SetLength(Result.Texts, 1);
    SetLength(Result.Names, 1);
    Result.Texts[0] := TipReadable(c, ddtFloat, AUTC);
    Result.Sort := c;
  end;
end;

function TipInline(const ACells: TTyTipCells): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(ACells.Texts) do
  begin
    if i > 0 then Result := Result + '  ';
    Result := Result + ACells.Texts[i];
  end;
end;

{ A sub-row's name as upstream prints it: makeValueReadable(name, 'ordinal'),
  so a dimension with no display name reads '-'. }
function TipRowName(const AName: string): string;
begin
  Result := TyReadableCell(TyDataText(AName), ddtOrdinal);
end;

function TTyAdvanceChart.RadarTooltip(ASlot, ARow: Integer;
  const AColor: TTyChartColor; const ASpec: TTyTooltipSpec): TTyTooltipBlock;
var
  st: TTyDataStore;
  spec: TTyRadarSpec;
  nm: string;
  j: Integer;
  v: Double;
begin
  st := FStores[ASlot];
  { HEADED BY THE ITEM, or the series when the item has no name -- the
    model's name, auto name included -- and never hidden: a blank reads '-'. }
  nm := st.GetItemName(ARow);
  if nm = '' then nm := SeriesModelName(FBindings[ASlot].SeriesIndex);
  nm := TipRowName(nm);
  Result := TTyTooltipBlock.CreateSection(nm, False);
  { A ROW PER INDICATOR, the PARSED value, sorted by `order` even in an item
    tooltip -- the radar's section asks for it. }
  spec := TyRadarSpecOf(FOption, FBindings[ASlot].RadarIndex);
  for j := 0 to High(spec.Indicators) do
  begin
    if j >= st.DimCount then Break;
    v := st.Get(j, ARow);
    Result.Add(TTyTooltipBlock.CreateNameValue(ttmSubItem, AColor,
      TipRowName(spec.Indicators[j].Name), False, TyTooltipValueText(v),
      False)).SortParam := v;
  end;
  if ASpec.HasOrder then Result.SortBlocks(ASpec.Order);
end;

{ a tree row's name as upstream converts it: a string, a number's text, or
  nothing }
function TTyAdvanceChart.TreeRowName(ASlot, ARow: Integer): string;
var it, d: TJSONData;
begin
  Result := '';
  it := FTrees[ASlot].Hier.Nodes[ARow].Item;
  if not (it is TJSONObject) then Exit;
  d := TJSONObject(it).Find('name');
  if d = nil then Exit;
  if d.JSONType = jtString then Result := d.AsString
  else if d.JSONType = jtNumber then Result := TyJsNumberToString(d.AsFloat);
end;

{ its value: the first of an array; NaN unless a number }
function TTyAdvanceChart.TreeRowValue(ASlot, ARow: Integer): Double;
var it, d: TJSONData;
begin
  Result := NaN;
  it := FTrees[ASlot].Hier.Nodes[ARow].Item;
  if not (it is TJSONObject) then Exit;
  d := TJSONObject(it).Find('value');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    if d.Count = 0 then Exit;
    d := d.Items[0];
  end;
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function TTyAdvanceChart.TooltipContent(const ADatum: TTyChartDatumRef;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
var
  p: TTyChartCallbackParams;
  seriesName, inlineName, valueText: string;
  haveValue: Boolean;
  slot, i: Integer;
  tv: Double;
  cells: TTyTipCells;
begin
  Result := nil;
  { [Batch 100] a marker's own formatTooltip; a sunburst's, a treemap's and
    a sankey's }
  if TipIsMarker(ADatum) then Exit(MarkerTooltipContent(ADatum));
  { a matrix cell has no content but its formatter's [Batch 147] }
  if ADatum.Kind = ctkMatrix then Exit;
  if HierTooltipContent(ADatum, DatumColour(ADatum), Result) then Exit;
  { a lines row: LinesSeries.formatTooltip [Batch 121] }
  if LinesTooltip(ADatum, Result) then Exit;
  { a map region: MapSeries.formatTooltip [Batch 152] }
  if MapTooltip(ADatum, Result) then Exit;
  p := TooltipParams(ADatum);
  { The DISPLAY name heads the section: an unnamed series has none. }
  seriesName := SeriesNameOf(ADatum.SeriesIndex);
  inlineName := p.Name;
  haveValue := Length(p.Values) > 0;
  valueText := ValuesText(p);
  if haveValue and (valueText = '') then haveValue := False;
  { A GRAPH LINK IS ONE BARE ROW -- upstream's formatTooltip hands back a
    nameValue with no marker and no section, so no series header either,
    named or not. }
  if ADatum.IsEdge then
  begin
    { A LINK WITH NO VALUE HAS NO VALUE CELL -- upstream's noValue is
      `value == null` here -- where a node or a bar with a missing value
      shows '-'. Nothing to decide here: TooltipParams gives a link a value
      only when it has one, so haveValue is already False. }
    if (Trim(inlineName) = '') and not haveValue then Exit;
    Result := TTyTooltipBlock.CreateSection('', True);
    Result.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0,
      inlineName, False, valueText, not haveValue));
    Exit;
  end;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  { A TREE NODE IS ONE BARE ROW too: its name the path from the real root,
    dotted; its value the first value, and none unless it is a number.
    [Batch 83] }
  if IsTreeDatum(ADatum) and (ADatum.DataIndex > 0)
    and (ADatum.DataIndex <= High(FTrees[slot].Hier.Nodes)) then
  begin
    inlineName := '';
    i := ADatum.DataIndex;
    while i > 0 do
    begin
      if inlineName = '' then inlineName := TreeRowName(slot, i)
      else inlineName := TreeRowName(slot, i) + '.' + inlineName;
      i := FTrees[slot].Hier.Nodes[i].Parent;
    end;
    tv := TreeRowValue(slot, ADatum.DataIndex);
    Result := TTyTooltipBlock.CreateSection('', True);
    Result.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, inlineName, False,
      TyTooltipValueText(tv), IsNan(tv)));
    Exit;
  end;
  if (slot >= 0) and (FBindings[slot].RadarIndex >= 0) and (slot <= High(FStores))
    and (FStores[slot] <> nil) and (ADatum.DataIndex >= 0)
    and (ADatum.DataIndex < FStores[slot].Count) then
    Exit(RadarTooltip(slot, ADatum.DataIndex, p.Color, ASpec));
  { A THEMERIVER'S ROW IS ONE BARE ROW: its formatTooltip is a nameValue of
    the row's name and value, no marker, no section -- for the row the
    datum names, which over a layer's polygon is the LAYER'S index, as
    upstream's setItemGraphicEl(idx) leaves it [Batch 118] }
  if (slot >= 0) and (FBindings[slot].SeriesType = TyThemeRiverSeriesTypeName)
    and (slot <= High(FStores)) and (FStores[slot] <> nil) then
  begin
    Result := TTyTooltipBlock.CreateSection('', True);
    if (ADatum.DataIndex >= 0) and (ADatum.DataIndex < FStores[slot].Count) then
    begin
      tv := FStores[slot].Get(1, ADatum.DataIndex);
      Result.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0,
        FStores[slot].GetItemName(ADatum.DataIndex), False,
        TyTooltipValueText(tv), IsNan(tv)));
    end;
    Exit;
  end;
  cells := Default(TTyTipCells);
  if (slot >= 0) and (slot <= High(FStores)) and (ADatum.DataIndex >= 0)
    and (FStores[slot] <> nil) and (ADatum.DataIndex < FStores[slot].Count) then
    cells := TipCellsOf(FStores[slot], ADatum.DataIndex,
      (FOption <> nil) and FOption.GetBool('useUTC', False));
  if cells.Valid then
  begin
    { SUB-ROWS: the item's own row keeps its name and an EMPTY value -- a
      value cell with nothing in it, not no value cell. }
    if cells.MultiLine then valueText := '' else valueText := TipInline(cells);
    haveValue := True;
  end;
  if (Trim(inlineName) = '') and not haveValue and (Trim(seriesName) = '') then
    Exit;

  { ONE SECTION HOLDING ONE ROW, which is the whole of upstream's default for
    a bar, a line, a scatter and a pie. `noHeader` is decided by whether the
    series was NAMED -- an auto-generated name counts as unnamed upstream, and
    SeriesNameOf answers '' for exactly that case -- and it is a different
    LAYOUT, not a wording change: without a header the section's gap level
    drops from 1 to 0 and the box loses a row. }
  { A NAME OF BLANKS IS STILL A NAME: upstream's isNameSpecified asks only
    whether one was written, and the header then goes through
    makeValueReadable, which never shows nothing -- so it reads '-'. }
  if (seriesName <> '') and (Trim(seriesName) = '') then seriesName := '-';
  { valueFormatter REPLACES THE VALUE CELL: upstream calls it in place of
    makeValueReadable, with the value and the raw index. [Batch 82] }
  if (ASpec.ValueFormatter <> '') and haveValue then
  begin
    { SUB-ROWS ARE FORMATTED ONE BY ONE, each with its own value and NO
      index -- upstream's sub-row fragments carry none -- and the item's own
      row gets the empty list. }
    if cells.MultiLine then
    begin
      valueText := TipValueFormatted(ASpec.ValueFormatter, p, '', True);
      for i := 0 to High(cells.Texts) do
        cells.Texts[i] := TipValueFormatted(ASpec.ValueFormatter, p,
          cells.Raws[i], False);
    end
    else
      valueText := TipValueFormatted(ASpec.ValueFormatter, p);
  end;
  Result := TTyTooltipBlock.CreateSection(seriesName, False);
  Result.Add(TTyTooltipBlock.CreateNameValue(ttmItem, p.Color,
    inlineName, False, valueText, not haveValue));
  { THE SUB-ROWS ARE SIBLINGS of the item row, after it, small-dotted in the
    series' colour. }
  if cells.MultiLine then
    for i := 0 to High(cells.Texts) do
      Result.Add(TTyTooltipBlock.CreateNameValue(ttmSubItem, p.Color,
        TipRowName(cells.Names[i]), False, cells.Texts[i], False));
end;

{ valueFormatter's (value, dataIndex): the value as String() prints the
  row's tooltip dimensions -- one scalar, or several joined -- and the RAW
  index, which is what 6.1 passes. }
function TTyAdvanceChart.TipValueFormatted(const AHandler: string;
  const AParams: TTyChartCallbackParams): string;
var
  prm: TTyChartCallbackParams;
  i: Integer;
begin
  prm := AParams;
  prm.ValueText := '';
  if Length(prm.RawCells) > 0 then
    for i := 0 to High(prm.RawCells) do
    begin
      if i > 0 then prm.ValueText := prm.ValueText + ',';
      prm.ValueText := prm.ValueText + TyJsValueText(prm.RawCells[i], '');
    end
  else
    for i := 0 to High(prm.Values) do
    begin
      if i > 0 then prm.ValueText := prm.ValueText + ',';
      prm.ValueText := prm.ValueText + TyChartValueText(prm.Values[i]);
    end;
  Result := TyChartRunHandler(AHandler, TyChartOneParams(prm));
end;

{ the same with the value text given -- a sub-row's own cell, or the empty
  list an item row with sub-rows gets -- and the index only where upstream
  passes one }
function TTyAdvanceChart.TipValueFormatted(const AHandler: string;
  const AParams: TTyChartCallbackParams; const AValueText: string;
  AWithIndex: Boolean): string;
var prm: TTyChartCallbackParams;
begin
  prm := AParams;
  prm.ValueText := AValueText;
  if not AWithIndex then
  begin
    prm.DataIndex := -1;
    prm.RawDataIndex := -1;
  end;
  Result := TyChartRunHandler(AHandler, TyChartOneParams(prm));
end;

{ The root textStyle over a font the theme resolved: family, size (CSS px),
  weight, and the colour free-standing text takes -- each where written. }
procedure TTyAdvanceChart.GlobalTextOver(var AName: string; var ASize,
  AWeight: Integer; var AHasColour: Boolean; var AColour: Cardinal;
  APick: TTyTextPick);
var
  ts, d: TJSONData;
  col: TTyChartColor;
begin
  if FOption = nil then Exit;
  ts := FOption.Find('textStyle');
  if not (ts is TJSONObject) then Exit;
  d := TJSONObject(ts).Find('fontFamily');
  if (ttpFamily in APick) and (d <> nil) and (d.JSONType = jtString)
    and (d.AsString <> '') then
    AName := d.AsString;
  if ttpSize in APick then
    ASize := TyOptFontSize(TJSONObject(ts).Find('fontSize'), ASize);
  if ttpWeight in APick then
    AWeight := TyFontWeightOf(TJSONObject(ts).Find('fontWeight'), AWeight);
  d := TJSONObject(ts).Find('color');
  if (ttpColour in APick) and (d <> nil) and (d.JSONType = jtString)
    and TyTryParseChartColor(d.AsString, col) then
  begin
    AHasColour := True;
    AColour := col;
  end;
end;

function TTyAdvanceChart.RtGlobal: TTyRtGlobal;
var
  st: TTyStyleSet;
  fname: string;
  fsize, fweight: Integer;
  hasCol: Boolean;
  col: Cardinal;
  root: TJSONObject;
begin
  st := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  fname := st.FontName;
  fsize := ResolveFontSize(st);
  fweight := st.FontWeight;
  hasCol := False;
  col := 0;
  GlobalTextOver(fname, fsize, fweight, hasCol, col, [ttpSize, ttpWeight, ttpFamily]);
  root := nil;
  if (FOption <> nil) and (FOption.Root is TJSONObject) then
    root := TJSONObject(FOption.Root);
  Result := TyRtGlobalOf(root, fname, fsize, fweight);
end;

{ An axis text style made what the layout measured: its family and size, its
  weight (an emphasised label keeps the theme's heavier one), and the
  author's colour where one was written. }
procedure TTyAdvanceChart.AxisTextOver(var AStyle: TTyStyleSet;
  const AName: string; ASize, AWeight: Integer; AHasColour: Boolean;
  AColour: Cardinal; AKeepWeight: Boolean);
begin
  AStyle.FontName := AName;
  AStyle.FontSize := ASize;
  Include(AStyle.Present, tpFontSize);
  if not AKeepWeight then AStyle.FontWeight := AWeight;
  if AHasColour then AStyle.TextColor := TTyColor(AColour);
end;

procedure TTyAdvanceChart.AxisTextStyles(ASpec: PTyAxisLayoutSpec;
  out ALabel, AName: TTyStyleSet);
var model: TTyStyleModel;
begin
  model := ActiveController.Model;
  ALabel := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  AName := model.ResolveStyle('TyAdvChartAxisName', '', []);
  if ASpec = nil then Exit;
  AxisTextOver(ALabel, ASpec^.FontName, ASpec^.FontSizeLogical, ASpec^.FontWeight,
    ASpec^.HasLabelColour, ASpec^.LabelColour, False);
  AxisTextOver(AName, ASpec^.NameFontName, ASpec^.NameFontSizeLogical,
    ASpec^.NameFontWeight, ASpec^.HasNameColour, ASpec^.NameColour, False);
end;

function TTyAdvanceChart.PointerAt(AAxis: TTyAxis; AValue: Double): Double;
var ext: TTyRange;
begin
  Result := AValue;
  if (AAxis = nil) or IsNan(AValue) then Exit;
  if not (AAxis.Scale is TTyIntervalScale) then Exit;
  ext := AAxis.Scale.GetExtent;
  if Result > ext.Stop then Result := ext.Stop;
  if Result < ext.Start then Result := ext.Start;
end;

function TTyAdvanceChart.SlotSeriesIndex(ASlot: Integer): Integer;
begin
  if (ASlot < 0) or (ASlot > High(FBindings)) then Result := -1
  else Result := FBindings[ASlot].SeriesIndex;
end;

function TTyAdvanceChart.PointerValue(const AHit: TTyAxisHit): Double;
begin
  { a linked axis never snaps [Batch 141]; nor onto a value off the axis:
    processOnAxis snaps only when axis.containData(snapToValue) -- the
    nearest point of a series may lie past a written min or max, and the
    pointer then stays where it is [milestone D5-D8: it went to the
    point, clamped to the axis end] }
  if AHit.Spec.Snap and not AHit.Linked and not IsNan(AHit.SnapValue)
    and AHit.Axis.Scale.Contain(AHit.SnapValue) then Result := AHit.SnapValue
  else Result := AHit.Value;
  Result := PointerAt(AHit.Axis, Result);
end;

function TTyAdvanceChart.PointerShadowShape(const AHit: TTyAxisHit;
  out AShape: TTyXYWH): Boolean;
begin
  AShape := Default(TTyXYWH);
  if AHit.Axis = nil then Exit(False);
  { CLAMPED, as the pointer asks the axis: dataToCoord(value, true) }
  Result := PointerShadowShapeAt(AHit,
    AHit.Axis.DataToCoord(PointerValue(AHit), True), AShape);
end;

function TTyAdvanceChart.PointerShadowShapeAt(const AHit: TTyAxisHit;
  AAt: Double; out AShape: TTyXYWH): Boolean;
var
  ax, other, base: TTyAxis;
  bw, px, span, gap, best, lo, hi, t0, t1, o0, o1: Double;
  ext: TTyRange;
  g, j, k, s: Integer;
  gb: TTyGridBuild;
  cart: TTyCartesian2D;
  only: Boolean;
  typ: string;
begin
  Result := False;
  AShape := Default(TTyXYWH);
  ax := AHit.Axis;
  if (ax = nil) or IsNan(AAt) or (FBuild = nil) then Exit;
  { THE BAND (calcAxisPointerShadowBandWidth, at least 1px). A category's
    own; on any other axis upstream asks the axis statistics -- the
    smallest positive gap between the values of the bars (pictorial bars,
    candlesticks, boxplots) sharing a hovered series' key on its BASE axis,
    the largest such gap over the hovered series -- and spans it over this
    axis' mapping extent, even when this is not the axis it was measured
    on. One value alone is four fifths of the axis; nothing at all, 1px. }
  { getExtent, upstream's order: an inverse axis runs from its far end }
  ax.LocalExtent(t0, t1);
  px := Abs(t1 - t0);
  if ax.Scale is TTyOrdinalScale then
    bw := ax.BandWidth
  else
  begin
    ext := ax.Scale.LinearExtent2(sekMapping);
    span := ext.Stop - ext.Start;
    best := NegInfinity;
    only := False;
    for k := 0 to High(AHit.Slots) do
    begin
      s := AHit.Slots[k];
      if (s < 0) or (s > High(FBindings)) then Continue;
      typ := FBindings[s].SeriesType;
      if (typ <> 'bar') and (typ <> 'pictorialBar') and (typ <> 'candlestick')
        and (typ <> 'boxplot') then Continue;
      if FBindings[s].CoordSysName <> 'cartesian2d' then Continue;
      base := FBindings[s].BaseAxis;
      if (base = nil) or (base.Scale is TTyOrdinalScale) then Continue;
      gap := TyLiPosMinGap(FStores,
        FIndex.SeriesOnAxisOfKey(base, TySeriesStatKey(typ, 'cartesian2d')), base);
      if gap > 0 then
      begin
        if gap > best then best := gap;
        only := False;
      end
      else if gap = cTyMinGapSingle then
        only := True;
    end;
    bw := NaN;
    if (not IsNan(span)) and (not IsInfinite(span)) and (span > 0)
      and (not IsInfinite(best)) and (not IsNan(best)) then
      bw := px / span * best
    else if only then
      bw := px * 0.8;
  end;
  if IsNan(bw) or IsInfinite(bw) then bw := 1
  else bw := Math.Max(Double(1), bw);
  { THE ENDS, each clamped to the axis on its own (calcAxisPointerShadowEnds) }
  t0 := ax.ToGlobal(t0);
  t1 := ax.ToGlobal(t1);
  lo := Math.Max(Math.Min(t0, t1), AAt - bw / 2);
  hi := Math.Min(AAt + bw / 2, Math.Max(t0, t1));
  { ACROSS THE OTHER AXIS of the first cartesian holding this one, from its
    first end as its extent runs }
  other := nil;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    for j := 0 to gb.CartesianCount - 1 do
    begin
      cart := gb.CartesianByIndex(j);
      if cart.AxisByDim(ax.Dim) = ax then
      begin
        other := cart.GetOtherAxis(ax);
        Break;
      end;
    end;
    if other <> nil then Break;
  end;
  if other = nil then Exit;
  other.LocalExtent(o0, o1);
  o0 := other.ToGlobal(o0);
  o1 := other.ToGlobal(o1);
  if ax.Dim = 'x' then
  begin
    AShape.X := lo;
    AShape.Y := o0;
    AShape.W := hi - lo;
    AShape.H := o1 - o0;
  end
  else
  begin
    AShape.X := o0;
    AShape.Y := lo;
    AShape.W := o1 - o0;
    AShape.H := hi - lo;
  end;
  Result := True;
end;

{ THE POINTER'S LABEL, and the axis tooltip's header. A named handler is
  given upstream's getValueLabel params: first the axis itself (its dimension,
  index and the value), then one entry per series the pointer collected --
  params.seriesData, in the order the hit holds them. }
function TTyAdvanceChart.PointerLabelText(const AHit: TTyAxisHit;
  AValue: Double): string;
var
  prm: TTyChartParams;
  k, n, slot: Integer;
begin
  if (AHit.Axis = nil) or not AHit.Spec.LabelSpec.HasFormatter
    or not TyChartIsHandlerRef(AHit.Spec.LabelSpec.Formatter) then
    Exit(AxisValueText(AHit.Axis, AValue, AHit.Spec.LabelSpec));
  prm := nil;
  SetLength(prm, 1);
  prm[0] := TyChartBlankParams;
  prm[0].ComponentType := AHit.Axis.Dim + 'Axis';
  prm[0].AxisDimension := AHit.Axis.Dim;
  prm[0].AxisIndex := AHit.Axis.ComponentIndex;
  SetLength(prm[0].Values, 1);
  prm[0].Values[0] := AValue;
  prm[0].ValueText := TyChartValueText(AValue);
  { a category axis hands over the category, not its ordinal }
  if AHit.Axis.Scale is TTyOrdinalScale then
  begin
    prm[0].Name := TTyOrdinalScale(AHit.Axis.Scale).GetLabel(AValue);
    prm[0].ValueText := prm[0].Name;
  end;
  prm[0].DefaultText := AxisValueText(AHit.Axis, AValue,
    Default(TTyAxisPointerLabelSpec));
  n := 1;
  for k := 0 to High(AHit.Slots) do
  begin
    slot := AHit.Slots[k];
    if (slot < 0) or (slot > High(FBindings)) or (slot > High(FStores))
      or (FStores[slot] = nil) then Continue;
    SetLength(prm, n + 1);
    prm[n] := TooltipParams(TyChartDatum(FBindings[slot].SeriesIndex,
      AHit.Rows[k], FStores[slot].GetRawIndex(AHit.Rows[k])));
    Inc(n);
  end;
  Result := TyChartRunHandler(AHit.Spec.LabelSpec.Formatter, prm);
end;

function PtrMemoKey(AAxis: TTyAxis): string;
begin
  Result := AAxis.Dim + '/' + IntToStr(AAxis.ComponentIndex);
end;

function TTyAdvanceChart.PointerDrawLabelText(const AHit: TTyAxisHit;
  AValue: Double): string;
var
  i, k: Integer;
  key: string;
  forced: Boolean;
begin
  if (AHit.Axis = nil) or not AHit.Spec.LabelSpec.HasFormatter
    or not TyChartIsHandlerRef(AHit.Spec.LabelSpec.Formatter) then
    Exit(PointerLabelText(AHit, AValue));
  key := PtrMemoKey(AHit.Axis);
  k := -1;
  for i := 0 to High(FPtrMemo) do
    if FPtrMemo[i].Key = key then
    begin
      k := i;
      Break;
    end;
  if k < 0 then
  begin
    { a new BaseAxisPointer: nothing remembered, and a render it is }
    k := Length(FPtrMemo);
    SetLength(FPtrMemo, k + 1);
    FPtrMemo[k] := Default(TTyPtrMemoEntry);
    FPtrMemo[k].Key := key;
    FPtrMemo[k].Gen := FStGen;
    FPtrMemo[k].UpdGen := FPtrUpdGen - 1;
  end;
  { forceRender: AxisView.render on a full update }
  forced := FPtrMemo[k].Gen <> FStGen;
  { render() RUNS ON AN ACTION, NOT ON A PAINT: a second paint of the same
    update draws what the first one rendered }
  if (not forced) and (FPtrMemo[k].UpdGen = FPtrUpdGen) then
    Exit(FPtrMemo[k].Text);
  FPtrMemo[k].UpdGen := FPtrUpdGen;
  { `!forceRender && _lastValue === value && _lastStatus === status`:
    nothing to render, the label drawn stands }
  if (not forced) and FPtrMemo[k].HasLast and FPtrMemo[k].LastShown
    and (FPtrMemo[k].LastValue = AValue) then
    Exit(FPtrMemo[k].Text);
  FPtrMemo[k].HasLast := True;
  FPtrMemo[k].LastShown := True;
  FPtrMemo[k].LastValue := AValue;
  FPtrMemo[k].Gen := FStGen;
  { makeElOption: the label's text }
  FPtrMemo[k].Text := PointerLabelText(AHit, AValue);
  { a graphicKey other than the last one clears the pointer -- _lastValue
    and _lastStatus with it, AFTER they were set: the render after the
    first show (or after the pointer's type changed) is never skipped }
  if not FPtrMemo[k].HasGraphicKey
    or (FPtrMemo[k].GraphicKey <> AHit.Spec.PointerType) then
    FPtrMemo[k].HasLast := False;
  FPtrMemo[k].HasGraphicKey := True;
  FPtrMemo[k].GraphicKey := AHit.Spec.PointerType;
  Result := FPtrMemo[k].Text;
end;

procedure TTyAdvanceChart.PointerMemoHideOthers(const AHits: TTyAxisHitArray);
var
  i, j: Integer;
  seen: Boolean;
begin
  for i := 0 to High(FPtrMemo) do
  begin
    seen := False;
    for j := 0 to High(AHits) do
      if (AHits[j].Axis <> nil) and AHits[j].Spec.LabelSpec.Show
        and (PtrMemoKey(AHits[j].Axis) = FPtrMemo[i].Key) then
      begin
        seen := True;
        Break;
      end;
    { status 'hide': `_lastStatus = status` with the value kept }
    if not seen and FPtrMemo[i].HasLast then FPtrMemo[i].LastShown := False;
  end;
end;

function TTyAdvanceChart.PointerLabelDrawn(const AHit: TTyAxisHit): string;
var i: Integer; key: string;
begin
  Result := '';
  if AHit.Axis = nil then Exit;
  if not AHit.Spec.LabelSpec.HasFormatter
    or not TyChartIsHandlerRef(AHit.Spec.LabelSpec.Formatter) then
    Exit(PointerLabelText(AHit, PointerValue(AHit)));
  key := PtrMemoKey(AHit.Axis);
  for i := 0 to High(FPtrMemo) do
    if FPtrMemo[i].Key = key then Exit(FPtrMemo[i].Text);
end;

function TTyAdvanceChart.AxisValueText(AAxis: TTyAxis; AValue: Double;
  const ALabel: TTyAxisPointerLabelSpec): string;
begin
  Result := '';
  if AAxis = nil then Exit;
  if AAxis.Scale is TTyOrdinalScale then
    Result := TTyOrdinalScale(AAxis.Scale).GetLabel(AValue)
  else if AAxis.Scale is TTyTimeScale then
    { getValueLabel asks the scale's getLabel: the full date, to the day
      over years and months and to the second below -- never the axis'
      short level template, which would head a tooltip with a bare `2`.
      [Revised in batch 104: TyTimeLabel, the label seed of the tick's
      unit.] }
    Result := TTyTimeScale(AAxis.Scale).GetLabel(AValue)
  else if ALabel.HasPrecision then
    Result := TyScaleValueLabel(AAxis.Scale, AValue, ALabel.Precision)
  else
    { 'AUTO' IS NOT "every digit the number has": it is the scale's interval
      precision -- the step's decimals plus two -- PADDED, as toFixed pads.
      An axis stepping by twenty labels its pointer 37.25 and one stepping by
      one 3.00. It was the step's own decimals, unpadded, and read 37 and 3. }
    Result := TyScaleValueLabel(AAxis.Scale, AValue, TyLabelPrecision(lpAuto));
  { FIRST OCCURRENCE ONLY, which is upstream's `.replace('{value}', text)` --
    a plain string pattern, not a global one. An empty formatter was never
    taken, as upstream ignores a falsy one. }
  if ALabel.HasFormatter then
    Result := StringReplace(ALabel.Formatter, '{value}', Result, []);
end;

function TTyAdvanceChart.NearestOnAxis(ASlot: Integer; AAxis: TTyAxis;
  AValue: Double; AMaxDistPx: Double; out ARows: TTyIntegerArray): Boolean;
var
  st: TTyDataStore;
  col: Integer;
begin
  ARows := nil;
  Result := False;
  if (AAxis = nil) or (ASlot < 0) or (ASlot > High(FStores)) then Exit;
  st := FStores[ASlot];
  if st = nil then Exit;
  col := st.DimIndexOf(AAxis.Dim);
  if col < 0 then Exit;
  { IN VIEW COORDINATE SPACE -- pixels, not data. The 0.5 a category axis is
    given is HALF A PIXEL, which after the value has already been rounded to a
    band centre means "the same band"; its purpose is to drop a series whose
    data is shorter than the axis, not to widen the search. ECharts 5.x
    compared in data space and 6.x changed it, so this is one to read rather
    than remember.

    THE SIDE TIE-BREAK. When the pointer falls exactly between two rows, the
    one at or before it wins -- otherwise both land in the list and every
    midpoint shows two rows of the same series. Rows with the SAME signed
    difference still accumulate, which is how two rows holding one value are
    both reported.

    [Batch 64: the loop moved to TyMkNearestRows, which the markers search a
    GIVEN column with, and it now measures in the axis' LOCAL coordinates as
    upstream's axis.dataToCoord does -- the grid's offset added to both sides
    of a difference could move a tie's last bit.] }
  ARows := TyMkNearestRows(st, col, AAxis, AValue, AMaxDistPx);
  Result := Length(ARows) > 0;
end;

function TTyAdvanceChart.PtrInfoOf(const AInfos: TTyPtrAxisInfoArray;
  AAxis: TTyAxis): Integer;
var k: Integer;
begin
  for k := 0 to High(AInfos) do
    if AInfos[k].Axis = AAxis then Exit(k);
  Result := -1;
end;

function TTyAdvanceChart.PtrCollect: TTyPtrAxisInfoArray;
var
  tipSpec: TTyTooltipSpec;
  tipOn, crossType, triggerAxis: Boolean;
  wantAxis, wantPolar: string;
  g, c, k: Integer;
  gb: TTyGridBuild;
  cart: TTyCartesian2D;
  base: TTyAxis;
  pol: TTyPolar;
  sgl: TTySingle;
  bases, others: array of TTyAxis;

  procedure AddUnique(var AList: array of TTyAxis; var ACount: Integer; AAxis: TTyAxis);
  var j: Integer;
  begin
    if AAxis = nil then Exit;
    for j := 0 to ACount - 1 do
      if AList[j] = AAxis then Exit;
    AList[ACount] := AAxis;
    Inc(ACount);
  end;

  { saveTooltipAxisInfo(fromTooltip, triggerTooltip, axis) }
  procedure Save(AAxis: TTyAxis; const APlot: TTyRectF; APolar: TTyPolar;
    ASingle: TTySingle; const ACsKey: string; AFromTooltip, ACrossFrom,
    ATrigger: Boolean);
  var
    info: TTyPtrAxisInfo;
    own: TTyAxisPointerSpec;
    isCat: Boolean;
    at_, n: Integer;
  begin
    if AAxis = nil then Exit;
    isCat := AAxis.Scale is TTyOrdinalScale;
    { the axis' own model (its block over the root) decides whether it is
      collected at all: show falsy never, 'auto' only from the tooltip (a
      handle is not modelled) }
    own := TyAxisPointerSpecOf(FOption, AAxis.MainType, AAxis.ComponentIndex,
      isCat, False, False, False);
    if own.Show = apsNo then Exit;
    if (own.Show = apsAuto) and not AFromTooltip then Exit;
    info := Default(TTyPtrAxisInfo);
    info.Axis := AAxis;
    info.Plot := APlot;
    info.Polar := APolar;
    info.Single := ASingle;
    info.CsKey := ACsKey;
    info.FromTooltip := AFromTooltip;
    info.CrossArm := ACrossFrom and not ATrigger;
    if AFromTooltip then
    begin
      info.TriggerTooltip := ATrigger;
      info.Spec := TyAxisPointerSpecOf(FOption, AAxis.MainType,
        AAxis.ComponentIndex, isCat, True, ATrigger, ACrossFrom);
    end
    else
    begin
      { triggerTooltip == null: the axis' own model's }
      info.TriggerTooltip := own.TriggerTooltip;
      info.Spec := own;
    end;
    info.InvolveSeries := info.TriggerTooltip or info.Spec.Snap or isCat;
    { an axis already there is replaced where it stands (the tooltip has the
      higher priority; the key keeps its place) }
    at_ := PtrInfoOf(Result, AAxis);
    if at_ >= 0 then
      Result[at_] := info
    else
    begin
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := info;
    end;
  end;

  procedure SaveTooltipAxes(const ABases, AOthers: array of TTyAxis;
    ANb, ANo: Integer; const APlot: TTyRectF; APolar: TTyPolar;
    ASingle: TTySingle; const ACsKey: string);
  var j: Integer;
  begin
    if not tipOn or not (triggerAxis or crossType) then Exit;
    for j := 0 to ANb - 1 do
      Save(ABases[j], APlot, APolar, ASingle, ACsKey, True, crossType, triggerAxis);
    if crossType then
      for j := 0 to ANo - 1 do
        Save(AOthers[j], APlot, APolar, ASingle, ACsKey, True, True, False);
  end;

var
  nb, no_: Integer;
begin
  Result := nil;
  if (FBuild = nil) or (FOption = nil) then Exit;
  tipSpec := TyTooltipSpecOf(FOption, -1, -1);
  { the tooltip's axes: a tooltip component that shows (showContent false
    still draws the pointer) }
  tipOn := tipSpec.HasComponent and tipSpec.Show;
  crossType := TyTooltipAxisPointerType(FOption) = aptCross;
  triggerAxis := tipSpec.Trigger = tttAxis;
  wantAxis := TyTooltipAxisPointerAxis(FOption);
  wantPolar := TyTooltipPolarPointerAxis(FOption);
  { THE GRIDS: grid.getAxes() is every x axis, then every y axis, in their
    component order; getTooltipAxes every cartesian's base axis (or the one
    `tooltip.axisPointer.axis` names), then every other one, each once }
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    if gb.CartesianCount = 0 then Continue;
    for k := 0 to gb.XAxisCount - 1 do
      Save(gb.XAxis(k), gb.PlotRect, nil, nil, 'g' + IntToStr(g), False, False, False);
    for k := 0 to gb.YAxisCount - 1 do
      Save(gb.YAxis(k), gb.PlotRect, nil, nil, 'g' + IntToStr(g), False, False, False);
    SetLength(bases, gb.CartesianCount);
    SetLength(others, gb.CartesianCount);
    nb := 0;
    no_ := 0;
    for c := 0 to gb.CartesianCount - 1 do
    begin
      cart := gb.CartesianByIndex(c);
      if cart = nil then Continue;
      if wantAxis <> '' then base := cart.AxisByDim(wantAxis)
      else base := cart.GetBaseAxis;
      if base = nil then Continue;
      AddUnique(bases, nb, base);
      AddUnique(others, no_, cart.GetOtherAxis(base));
    end;
    SaveTooltipAxes(bases, others, nb, no_, gb.PlotRect, nil, nil, 'g' + IntToStr(g));
  end;
  { THE POLARS: getAxes() is the radius, then the angle }
  for g := 0 to High(FPolars) do
  begin
    pol := FPolars[g];
    if pol = nil then Continue;
    Save(pol.AxisByDim('radius'), Default(TTyRectF), pol, nil, 'p' + IntToStr(g), False, False, False);
    Save(pol.AxisByDim('angle'), Default(TTyRectF), pol, nil, 'p' + IntToStr(g), False, False, False);
    if wantPolar <> '' then base := pol.AxisByDim(wantPolar)
    else base := pol.BaseAxis;
    if base = nil then Continue;
    SetLength(bases, 1);
    SetLength(others, 1);
    bases[0] := base;
    others[0] := pol.OtherAxis(base);
    no_ := 1;
    if others[0] = nil then no_ := 0;
    SaveTooltipAxes(bases, others, 1, no_, Default(TTyRectF), pol, nil, 'p' + IntToStr(g));
  end;
  { THE SINGLE AXES: their only axis, no other one }
  for g := 0 to High(FSingles) do
  begin
    sgl := FSingles[g];
    if sgl = nil then Continue;
    Save(sgl.Axis, sgl.GetRect, nil, sgl, 's' + IntToStr(g), False, False, False);
    SetLength(bases, 1);
    bases[0] := sgl.Axis;
    SaveTooltipAxes(bases, others, 1, 0, sgl.GetRect, nil, sgl, 's' + IntToStr(g));
  end;
end;

function TTyAdvanceChart.ResolveAxisPointers(AX, AY: Double;
  AInput: TJSONArray): TTyAxisHitArray;
var
  infos: TTyPtrAxisInfoArray;
  groups: array of Integer;
  g: Integer;
  gb: TTyGridBuild;
  links: array of TJSONData;
  lkVal: TTyDoubleArray;
  lkHas: array of Boolean;
  t, s, h, n0, at_, j: Integer;
  v: Double;
  mapperSpec: string;
  mapper: TTyChartAxisPointerMapper;
  hold: TTyAxisHit;
  appended: Boolean;
  contains: array of Boolean;

  { One axis, resolved and appended when it has something to say. On a
    polar the value is the axis' own half of pointToData [Batch 111]. }
  { ThemeRiverSeries.getAxisTooltipData: per layer the row nearest AValue
    in time -- the last of a tie -- and the nearest value of the LAST layer }
  function RiverNearest(ASlot: Integer; AValue: Double; out ARows: TTyIntegerArray;
    out ANearest: Double): Boolean;
  var
    layers: TTyRiverLayerArray;
    li, j, idx: Integer;
    md, t, dd: Double;
  begin
    ARows := nil;
    ANearest := NaN;
    Result := False;
    if (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
    layers := TyThemeRiverLayers(FStores[ASlot]);
    SetLength(ARows, Length(layers));
    for li := 0 to High(layers) do
    begin
      md := MaxDouble;
      idx := -1;
      for j := 0 to High(layers[li].Rows) do
      begin
        t := FStores[ASlot].Get(0, layers[li].Rows[j]);
        dd := Abs(t - AValue);
        if (not IsNan(dd)) and (dd <= md) then
        begin
          ANearest := t;
          md := dd;
          idx := layers[li].Rows[j];
        end;
      end;
      ARows[li] := idx;
    end;
    Result := Length(layers) > 0;
  end;

  { `appended` says whether a hit went in. ALinked: axisPointer.link's
    pass, the value given (AGivenValue) and the axis taken whether or not
    the first pass looked at it [Batch 141] }
  procedure Consider(const AInfo: TTyPtrAxisInfo; ALinked: Boolean = False;
    AGivenValue: Double = 0);
  var
    hit: TTyAxisHit;
    coord, value, snapTo, v, diff, dist, minDist, minDiff, maxDist: Double;
    rows: TTyIntegerArray;
    s, r, m: Integer;
    isCat, given: Boolean;
    inp: TJSONObject;
    iv: TJSONData;
    AAxis: TTyAxis;
    APolar: TTyPolar;
    ASingle: TTySingle;
  begin
    appended := False;
    AAxis := AInfo.Axis;
    APolar := AInfo.Polar;
    ASingle := AInfo.Single;
    if AAxis = nil then Exit;
    isCat := AAxis.Scale is TTyOrdinalScale;
    { [Batch 153] THE PAYLOAD'S axesInfo restricts the first pass to the
      axes it names (dim and index), and a value it writes stands in for
      the point's; null leaves the point's }
    given := False;
    if (AInput <> nil) and not ALinked then
    begin
      inp := nil;
      for s := 0 to AInput.Count - 1 do
        if (AInput.Items[s] is TJSONObject)
          and (TJSONObject(AInput.Items[s]).Get('axisDim', '') = AAxis.Dim)
          and (TJSONObject(AInput.Items[s]).Find('axisIndex') <> nil)
          and (TJSONObject(AInput.Items[s]).Find('axisIndex').JSONType = jtNumber)
          and (TJSONObject(AInput.Items[s]).Find('axisIndex').AsFloat = AAxis.ComponentIndex) then
        begin
          inp := TJSONObject(AInput.Items[s]);
          Break;
        end;
      if inp = nil then Exit;
      iv := inp.Find('value');
      if (iv <> nil) and (iv.JSONType <> jtNull) then
      begin
        given := True;
        AGivenValue := NaN;
        if iv.JSONType = jtNumber then AGivenValue := iv.AsFloat
        else if (iv.JSONType = jtString) and isCat and (AAxis.Categories <> nil) then
        begin
          m := AAxis.Categories.GetOrdinal(iv.AsString);
          if m >= 0 then AGivenValue := m;
        end;
      end;
    end;
    hit := Default(TTyAxisHit);
    hit.Axis := AAxis;
    hit.Plot := AInfo.Plot;
    hit.Cross := AInfo.CrossArm;
    hit.NoTip := not AInfo.TriggerTooltip;
    hit.Polar := APolar;
    hit.Single := ASingle;
    hit.Linked := ALinked;
    { [R2-I7] the axisInfo's model: the tooltip's volatile layer for a
      tooltip axis, the axis' own block over the root for one collected for
      its own show }
    hit.Spec := AInfo.Spec;

    if ALinked or given then
      value := AGivenValue
    else if APolar <> nil then
      value := APolar.AxisPointToData(AAxis, AX, AY)
    { SingleAxis.pointToData: the orient's coordinate [Batch 118] }
    else if ASingle <> nil then
      value := ASingle.PointXYToData(AX, AY)
    else
    begin
      if AAxis.Horizontal then coord := AX else coord := AY;
      value := AAxis.CoordToData(coord);
    end;
    if IsNan(value) then Exit;
    { THE CONTAINMENT TEST IS WHAT REJECTS AN OUT-OF-RANGE POINT, not a clamp.
      CoordToData extrapolates on purpose, so a pointer forty pixels past the
      last category answers an ordinal nobody has -- and pulling it back onto
      the edge would put a tooltip on the last bar for a pointer that is not
      over it.

      AN EQUIVALENT MUTANT LIVES HERE, recorded rather than chased. Deleting
      this line changes nothing TODAY, because the caller has already required
      the point to be inside the grid's plot rect and every axis' pixel extent
      is currently that rect. It stops being equivalent the moment an axis is
      narrower than the plot -- an `offset`, or a second pair sharing the
      grid -- and a guard that is redundant only by coincidence is still the
      guard that has to be there when the coincidence ends. }
    { OVER THE MAPPING EXTENT on a value or time axis, as upstream's
      scale.contain: a bar's half width that containShape added is part of
      the axis a pointer can stand on [Batch 101]
      [Revised in batch 101: the effective extent, so the outer half of the
      first and last bar on a value axis took no pointer.] }
    if AAxis.AxisType in [atValue, atTime] then
    begin
      if not TyRangeContains(AAxis.Scale.GetExtent2(sekMapping), value) then Exit;
    end
    else if not TyRangeContains(AAxis.Scale.GetExtent2(sekEffective), value) then Exit;
    { AND ON A CATEGORY AXIS, A CATEGORY: upstream's contain asks for one
      that exists, so a min or max reaching past the list leaves positions
      that take no pointer; and a blank axis takes none anywhere. }
    if AAxis.Scale.Blank then Exit;
    if isCat and not AAxis.Scale.Contain(value) then Exit;

    { ---- the nearest series, and only the nearest ---- }
    snapTo := value;
    minDist := Infinity;
    minDiff := -1;
    if isCat then maxDist := 0.5 else maxDist := Infinity;
    { [R2-I7] involveSeries -- triggerTooltip, snap or a category axis --
      not "anything but a cross arm": an axis that neither triggers nor snaps
      shows its pointer at the value with no rows, and a category cross arm
      has its rows
      [Revised in R2-I7: `if not ACross`.] }
    if AInfo.InvolveSeries then
      for s := 0 to High(FBindings) do
      begin
        if FBindings[s].Hidden then Continue;
        { EVERY SERIES ON THIS AXIS, base or not: upstream's collectSeriesInfo
          takes a series into an axis' list when its coordinate system's axis
          of that dimension is this one -- so a pointer on a bar chart's value
          axis finds the bar nearest in value [Batch 101]
          [Revised in batch 101: only the series whose base axis this is.] }
        if (FBindings[s].XAxis <> AAxis) and (FBindings[s].YAxis <> AAxis) then Continue;
        { NOT A SERIES WHOSE OWN TOOLTIP SAYS item / none / false or show
          false, nor one whose own axisPointer says show false:
          collectSeriesInfo leaves them out [Batch 153] }
        if not TipSeriesOnAxis(FBindings[s].SeriesIndex) then Continue;
        { a themeRiver answers by its own getAxisTooltipData [Batch 118] }
        if FBindings[s].SeriesType = TyThemeRiverSeriesTypeName then
        begin
          if not RiverNearest(s, value, rows, v) then Continue;
        end
        else
        begin
          if not NearestOnAxis(s, AAxis, value, maxDist, rows) then Continue;
          v := FStores[s].Get(FStores[s].DimIndexOf(AAxis.Dim), rows[0]);
        end;
        if IsNan(v) or IsInfinite(v) then Continue;
        diff := value - v;
        dist := Abs(diff);
        { AN AXIS TRIGGER IS NOT "EVERY SERIES IN THIS COLUMN". Upstream empties
          the batch the moment a closer series appears, so what survives is the
          series NEAREST the hovered value -- and equal-distance ones
          accumulate, because the push sits outside the test that empties it. }
        if dist <= minDist then
        begin
          if (dist < minDist) or ((diff >= 0) and (minDiff < 0)) then
          begin
            minDist := dist;
            minDiff := diff;
            snapTo := v;
            SetLength(hit.Slots, 0);
            SetLength(hit.Rows, 0);
          end;
          m := Length(hit.Slots);
          SetLength(hit.Slots, m + Length(rows));
          SetLength(hit.Rows, m + Length(rows));
          for r := 0 to High(rows) do
          begin
            hit.Slots[m + r] := s;
            hit.Rows[m + r] := rows[r];
          end;
        end;
      end;
    hit.Value := value;
    hit.SnapValue := snapTo;
    { NOTHING TO SAY AND NOTHING TO DRAW. A pointer type of `none` still
      reaches here, because its LABEL can be shown on its own. }
    if (hit.Spec.PointerType = aptNone) and not hit.Spec.LabelSpec.Show
      and (Length(hit.Slots) = 0) then Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := hit;
    appended := True;
  end;

  { modelHelper's checkPropInLink: 'all', a list holding the axis' own value
    (strictly: a number never matches a string), or that value itself }
  function InLink(AProp: TJSONData; const AStr: string; ANum: Integer;
    AIsNum: Boolean): Boolean;
  var
    k: Integer;
    e: TJSONData;
  begin
    Result := False;
    if AProp = nil then Exit;
    if (AProp.JSONType = jtString) and (AProp.AsString = 'all') then Exit(True);
    if AProp is TJSONArray then
    begin
      for k := 0 to AProp.Count - 1 do
      begin
        e := TJSONArray(AProp).Items[k];
        if AIsNum then
        begin
          if (e.JSONType = jtNumber) and (e.AsFloat = ANum) then Exit(True);
        end
        else if (e.JSONType = jtString) and (e.AsString = AStr) then Exit(True);
      end;
      Exit;
    end;
    if AIsNum then Result := (AProp.JSONType = jtNumber) and (AProp.AsFloat = ANum)
    else Result := (AProp.JSONType = jtString) and (AProp.AsString = AStr);
  end;

  { getLinkGroupIndex: the first link entry naming the axis by id, index or
    name (dim + 'AxisId' and so on) }
  function LinkGroupOf(AAxis: TTyAxis): Integer;
  var
    k: Integer;
    o: TJSONObject;
    id, nm: string;
  begin
    Result := -1;
    id := FOption.ComponentId(AAxis.MainType, AAxis.ComponentIndex);
    nm := FOption.ComponentModelName(AAxis.MainType, AAxis.ComponentIndex);
    for k := 0 to High(links) do
    begin
      if not (links[k] is TJSONObject) then Continue;
      o := TJSONObject(links[k]);
      if InLink(o.Find(AAxis.Dim + 'AxisId'), id, 0, False)
        or InLink(o.Find(AAxis.Dim + 'AxisIndex'), '', AAxis.ComponentIndex, True)
        or InLink(o.Find(AAxis.Dim + 'AxisName'), nm, 0, False) then Exit(k);
    end;
  end;

  function HitOf(const AHits: TTyAxisHitArray; AAxis: TTyAxis): Integer;
  var k: Integer;
  begin
    for k := 0 to High(AHits) do
      if AHits[k].Axis = AAxis then Exit(k);
    Result := -1;
  end;

  function KeyOf(AAxis: TTyAxis): string;
  var k: Integer;
  begin
    k := PtrInfoOf(infos, AAxis);
    if k >= 0 then Result := infos[k].CsKey else Result := '';
  end;

  { showValueMap's value: the snapped one when the axis snaps and the
    snapped value is on it, else the pointer's own }
  function SourceValue(const AHit: TTyAxisHit): Double;
  begin
    Result := AHit.Value;
    if AHit.Spec.Snap and not IsNan(AHit.SnapValue)
      and AHit.Axis.Scale.Contain(AHit.SnapValue) then Result := AHit.SnapValue;
  end;

  function MapperParam(AAxis: TTyAxis): TTyChartMapperAxis;
  begin
    Result.AxisDim := AAxis.Dim;
    Result.AxisIndex := AAxis.ComponentIndex;
    Result.AxisName := FOption.ComponentModelName(AAxis.MainType, AAxis.ComponentIndex);
    Result.AxisId := FOption.ComponentId(AAxis.MainType, AAxis.ComponentIndex);
  end;

  procedure ReadLinks;
  var
    ap, lk: TJSONData;
    k: Integer;
  begin
    links := nil;
    ap := FOption.ComponentAt('axisPointer', 0);
    if not (ap is TJSONObject) then Exit;
    lk := TJSONObject(ap).Find('link');
    { the preprocessor wraps one that is not a list; null and absent are
      none }
    if (lk = nil) or (lk.JSONType = jtNull) then Exit;
    if lk is TJSONArray then
    begin
      SetLength(links, lk.Count);
      for k := 0 to lk.Count - 1 do links[k] := TJSONArray(lk).Items[k];
    end
    else if TyJsTruthy(lk) then
    begin
      SetLength(links, 1);
      links[0] := lk;
    end;
  end;

begin
  Result := nil;
  links := nil;
  if (FBuild = nil) or (FOption = nil) then Exit;
  { [R2-I7] THE AXES OF THE axisPointer MODEL, not the tooltip's alone:
    collectAxesInfo takes an axis whose own pointer says `show` whatever the
    tooltip is (scatter-nutrients-matrix: a none trigger and the root's
    show), then the tooltip's axes -- trigger 'axis' or a cross -- in their
    place. The tooltip's own trigger decides nothing else: an axis that
    triggers the tooltip puts its rows into dataByCoordSys, and TooltipView
    shows those whatever it says.
    [Revised in R2-I7: only the tooltip's axes, and nothing at all without
    trigger 'axis' or a cross.] }
  infos := PtrCollect;
  if Length(infos) = 0 then Exit;
  { WHICH COORDINATE SYSTEMS HOLD THE POINT: a grid CLOSED ON EVERY EDGE, as
    upstream's containPoint -- a pointer on the plot's right or bottom edge
    still points at the last category (its first cartesian's); a polar
    (Polar.containPoint); a single axis (Single.containPoint)
    [Revised in batch 44: this was the half-open cell rule.] }
  SetLength(contains, Length(infos));
  for t := 0 to High(infos) do
  begin
    contains[t] := False;
    if infos[t].Polar <> nil then
      contains[t] := infos[t].Polar.ContainXY(AX, AY)
    else if infos[t].Single <> nil then
      contains[t] := infos[t].Single.ContainXY(AX, AY)
    else
    begin
      g := StrToIntDef(Copy(infos[t].CsKey, 2, MaxInt), -1);
      if (g < 0) or (g >= FBuild.GridCount) then Continue;
      gb := FBuild.Grid(g);
      contains[t] := (gb.CartesianCount > 0)
        and gb.CartesianByIndex(0).ContainPoint(TyPointF(AX, AY));
    end;
  end;
  { ---- the first pass: every axisInfo of a coordinate system that holds
    the point, in the order they were collected ---- }
  for t := 0 to High(infos) do
    if contains[t] then Consider(infos[t]);

  { ---- axisPointer.link [Batch 141] ----
    Every axisInfo of every coordinate system, the point in it or not, in
    the order they were collected. An axis the first pass did not show
    takes, from each shown axis of its link group in turn (the last one
    wins), that axis' value -- through the group's mapper and the target
    scale's parse -- and then goes through processOnAxis with no snap. Its
    hit goes after the hits of its own coordinate system, as dataByCoordSys
    lists them. }
  ReadLinks;
  if Length(links) = 0 then Exit;
  SetLength(groups, Length(infos));
  for t := 0 to High(infos) do groups[t] := LinkGroupOf(infos[t].Axis);
  SetLength(lkVal, Length(infos));
  SetLength(lkHas, Length(infos));
  for t := 0 to High(infos) do
  begin
    lkHas[t] := False;
    lkVal[t] := NaN;
    if (groups[t] < 0) or (HitOf(Result, infos[t].Axis) >= 0) then Continue;
    for s := 0 to High(infos) do
    begin
      if (s = t) or (groups[s] <> groups[t]) then Continue;
      h := HitOf(Result, infos[s].Axis);
      if h < 0 then Continue;
      v := SourceValue(Result[h]);
      mapperSpec := '';
      if links[groups[t]] is TJSONObject then
        mapperSpec := TJSONObject(links[groups[t]]).Get('mapper', '');
      { a mapper that is not a registered handler maps nothing (upstream
        would throw calling it) }
      if TyChartIsHandlerRef(mapperSpec)
        and TyChartFindAxisPointerMapper(Copy(mapperSpec, 2, MaxInt), mapper) then
      begin
        v := mapper(v, MapperParam(infos[s].Axis), MapperParam(infos[t].Axis));
        { the target scale's parse: a category or a time axis rounds }
        if ((infos[t].Axis.Scale is TTyOrdinalScale)
          or (infos[t].Axis.AxisType = atTime)) and not IsNan(v)
          and not IsInfinite(v) then v := Floor(v + 0.5);
      end;
      lkVal[t] := v;
      lkHas[t] := True;
    end;
  end;
  for t := 0 to High(infos) do
  begin
    if not lkHas[t] then Continue;
    n0 := Length(Result);
    Consider(infos[t], True, lkVal[t]);
    if not appended then Continue;
    { after the last hit of its own coordinate system, when it has one }
    at_ := -1;
    for j := 0 to n0 - 1 do
      if KeyOf(Result[j].Axis) = infos[t].CsKey then at_ := j;
    if (at_ < 0) or (at_ = n0 - 1) then Continue;
    hold := Result[n0];
    for j := n0 downto at_ + 2 do Result[j] := Result[j - 1];
    Result[at_ + 1] := hold;
  end;
end;

procedure TTyAdvanceChart.PaintAxisPointers(APainter: TTyPainter;
  const ARect: TRect; APPI: Integer; const AMeasurer: ITyTextMeasurer;
  const AHits: TTyAxisHitArray);
var
  i: Integer;
  lineS, shadowS, labelS: TTyStyleSet;
  hit: TTyAxisHit;
  at, lo, hi, w, pv: Double;
  colour: TTyColor;
  band: TTyRectF;
  dash: TTyDoubleArray;
  txt: string;
  tw, th, margin, padL, padT, padR, padB: Double;
  box: TRect;
  corners: TTyCorners;
  surface: TTyFill;
  sh: TTyXYWH;
begin
  lineS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointer', '', []);
  shadowS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerShadow',
    '', []);
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerLabel',
    '', []);
  { [R2-I8] a pointer this paint does not draw is hidden }
  PointerMemoHideOthers(AHits);
  for i := 0 to High(AHits) do
  begin
    hit := AHits[i];
    if hit.Axis = nil then Continue;
    { a polar's pointer is its own shape [Batch 111] }
    if hit.Polar <> nil then
    begin
      PaintPolarPointer(APainter, ARect, APPI, AMeasurer, hit);
      Continue;
    end;
    { and a single axis' [Batch 118] }
    if hit.Single <> nil then
    begin
      PaintSinglePointer(APainter, ARect, APPI, AMeasurer, hit);
      Continue;
    end;
    { SNAP MOVES THE POINTER, not the content. With snap off the line stays
      under the cursor while the tooltip still describes the nearest row --
      upstream splits them at exactly this branch. }
    { THE POINTER'S OWN VALUE: the snapped row with snap on, the cursor with
      it off -- and inside the scale's extent, which upstream's fixValue
      clamps it to before drawing the line or writing the label. A row past
      a written max puts the pointer on the max, not off the plot. }
    pv := PointerValue(hit);
    { CLAMPED, as upstream's pointer asks the axis: dataToCoord(value, true)
      hands the end back as itself at or past it }
    at := hit.Axis.DataToCoord(pv, True);
    if IsNan(at) then Continue;
    { ON ITS WAY THERE: the pointer, and the label with it [Batch 92] }
    at := PtrAt(hit, at);

    case hit.Spec.PointerType of
      aptShadow:
        begin
          { THE BAND upstream draws [Batch 101]: a category's, or on a value,
            log or time axis the hovered bars' gap -- 1px for a line --
            clamped to the axis and across the other one. While its proxy
            moves, the proxy's rect.
            [Revised in batch 101: nothing at all on a value axis, the
            statistic having no port.] }
          if not (tpBackground in shadowS.Present) then Continue;
          if not PtrShadowNow(hit, sh) then Continue;
          band := TyRectF(Math.Min(sh.X, sh.X + sh.W), Math.Min(sh.Y, sh.Y + sh.H),
            Math.Max(sh.X, sh.X + sh.W), Math.Max(sh.Y, sh.Y + sh.H));
          if (band.Right - band.Left <= 0) or (band.Bottom - band.Top <= 0) then
            Continue;
          colour := shadowS.Background.Color;
          if hit.Spec.HasShadowColour then colour := TTyColor(hit.Spec.ShadowColour);
          surface := shadowS.Background;
          surface.Kind := tfkSolid;
          surface.Color := colour;
          APainter.FillBackground(
            Rect(Round(band.Left), Round(band.Top),
                 Round(band.Right), Round(band.Bottom)), surface,
            TyCorners(0, 0, 0, 0));
        end;
      aptLine:
        begin
          if not (tpBorderColor in lineS.Present) then Continue;
          colour := lineS.BorderColor;
          if hit.Spec.HasLineColour then colour := TTyColor(hit.Spec.LineColour);
          w := lineS.BorderWidth;
          if hit.Spec.HasLineWidth then w := hit.Spec.LineWidthLogical;
          if w <= 0 then Continue;
          dash := TyDashPattern(hit.Spec.LineDash, hit.Spec.LineDashExplicit, w);
          APainter.SetLineDash(dash);
          APainter.BeginPath;
          if hit.Axis.Horizontal then
          begin
            APainter.MoveTo(at, hit.Plot.Top);
            APainter.LineTo(at, hit.Plot.Bottom);
          end
          else
          begin
            APainter.MoveTo(hit.Plot.Left, at);
            APainter.LineTo(hit.Plot.Right, at);
          end;
          APainter.StrokePath(colour, w);
          { AND THE DASH IS PUT BACK. SetLineDash is painter state, not an
            argument -- leaving it set dashes whatever is drawn next, which is
            the same class of leak as forgetting BeginPath and just as invisible
            until something downstream comes out wrong. }
          APainter.SetLineDash([]);
        end;
    end;

    { ---- the label ---- }
    if not hit.Spec.LabelSpec.Show then Continue;
    if not (tpBackground in labelS.Present) then Continue;
    { The value the line is at -- the cursor's with snap off, where it used to
      be the nearest row's while the line stood under the cursor.
      [R2-I8] through the axis' memo: a function runs as upstream runs it }
    txt := PointerDrawLabelText(hit, pv);
    if txt = '' then Continue;
    AMeasurer.MeasureLine(txt, labelS.FontName, ResolveFontSize(labelS),
      labelS.FontWeight, tw, th);
    if (tw <= 0) or (th <= 0) then Continue;
    if hit.Spec.LabelSpec.HasPadding then
    begin
      padL := APainter.ScaleF(hit.Spec.LabelSpec.PadLeft);
      padT := APainter.ScaleF(hit.Spec.LabelSpec.PadTop);
      padR := APainter.ScaleF(hit.Spec.LabelSpec.PadRight);
      padB := APainter.ScaleF(hit.Spec.LabelSpec.PadBottom);
    end
    else
    begin
      padL := APainter.Scale(labelS.Padding.Left);
      padT := APainter.Scale(labelS.Padding.Top);
      padR := APainter.Scale(labelS.Padding.Right);
      padB := APainter.Scale(labelS.Padding.Bottom);
    end;
    margin := APainter.ScaleF(ActiveController.Metric(
      TyAdvChartAxisPointerMarginVar, TyAdvChartAxisPointerMargin));
    if hit.Spec.LabelSpec.MarginLogical <> 3 then
      margin := APainter.ScaleF(hit.Spec.LabelSpec.MarginLogical);
    { OUTSIDE THE PLOT, on the axis' own side. Not on the axis LINE: an
      on-zero axis floats in the middle of the plot and its labels do not
      follow it there. }
    if hit.Axis.Horizontal then
    begin
      box.Left := Round(at - (tw + padL + padR) / 2);
      if hit.Axis.Side = asTop then
        box.Top := Round(hit.Plot.Top - margin - th - padT - padB)
      else
        box.Top := Round(hit.Plot.Bottom + margin);
    end
    else
    begin
      box.Top := Round(at - (th + padT + padB) / 2);
      if hit.Axis.Side = asRight then
        box.Left := Round(hit.Plot.Right + margin)
      else
        box.Left := Round(hit.Plot.Left - margin - tw - padL - padR);
    end;
    box.Right := box.Left + Round(tw + padL + padR);
    box.Bottom := box.Top + Round(th + padT + padB);
    { Clamped into the CONTROL, far edge first -- the same rule the tooltip
      box follows, and for the same reason: what falls outside is not clipped,
      it is not drawn. }
    if box.Right > ARect.Right then OffsetRect(box, ARect.Right - box.Right, 0);
    if box.Bottom > ARect.Bottom then OffsetRect(box, 0, ARect.Bottom - box.Bottom);
    if box.Left < ARect.Left then OffsetRect(box, ARect.Left - box.Left, 0);
    if box.Top < ARect.Top then OffsetRect(box, 0, ARect.Top - box.Top);

    corners := TyEffectiveCorners(labelS);
    if hit.Spec.LabelSpec.HasBorderRadius then
      corners := TyCorners(Round(hit.Spec.LabelSpec.BorderRadiusLogical),
        Round(hit.Spec.LabelSpec.BorderRadiusLogical),
        Round(hit.Spec.LabelSpec.BorderRadiusLogical),
        Round(hit.Spec.LabelSpec.BorderRadiusLogical));
    surface := labelS.Background;
    if hit.Spec.LabelSpec.HasBackground then
    begin
      surface.Kind := tfkSolid;
      surface.Color := TTyColor(hit.Spec.LabelSpec.Background);
    end;
    APainter.FillBackground(box, surface, corners);
    if hit.Spec.LabelSpec.HasBorderColour and hit.Spec.LabelSpec.HasBorderWidth
      and (hit.Spec.LabelSpec.BorderWidthLogical > 0) then
      APainter.StrokeBorder(box, corners,
        Round(hit.Spec.LabelSpec.BorderWidthLogical),
        TTyColor(hit.Spec.LabelSpec.BorderColour))
    else if TyBorderVisible(labelS) then
      APainter.StrokeBorder(box, corners, labelS.BorderWidth, labelS.BorderColor);
    colour := labelS.TextColor;
    if hit.Spec.LabelSpec.HasColour then colour := TTyColor(hit.Spec.LabelSpec.Colour);
    APainter.DrawText(box, txt, labelS.FontName, ResolveFontSize(labelS),
      labelS.FontWeight, colour, taCenter, tlCenter, False);
  end;
end;

function TTyAdvanceChart.ValuesText(
  const AParams: TTyChartCallbackParams): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(AParams.Values) do
  begin
    if i > 0 then Result := Result + '  ';
    { makeValueReadable ON THE RAW CELL: 'abc' is 'abc', true is true,
      '0x10' is '0x10' -- where the parsed Double would say '-' or 1. A
      time is still the number's (its formatting is local time). }
    if (i <= High(AParams.RawCells)) and (i <= High(AParams.RawTypes))
      and (AParams.RawTypes[i] <> ddtTime) then
      Result := Result + TyReadableCell(AParams.RawCells[i], AParams.RawTypes[i])
    else
      Result := Result + TyTooltipValueText(AParams.Values[i]);
  end;
end;

function TTyAdvanceChart.AxisTooltipParams(
  const AHits: TTyAxisHitArray): TTyChartParams;
var
  i, k, n, slot, row: Integer;
  d: TTyChartDatumRef;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(AHits) do
  begin
    { The cross' other arm carries no series -- see AxisTooltipContent. }
    if AHits[i].NoTip then Continue;
    for k := 0 to High(AHits[i].Slots) do
    begin
      slot := AHits[i].Slots[k];
      row := AHits[i].Rows[k];
      if (slot < 0) or (slot > High(FBindings)) then Continue;
      d := TyChartDatum(FBindings[slot].SeriesIndex, row,
        FStores[slot].GetRawIndex(row));
      SetLength(Result, n + 1);
      Result[n] := TooltipParams(d);
      { [R2-I7] _showAxisTooltip's cbParams.axisDim / axisIndex: the axis of
        the section -- what scatter-nutrients-matrix's formatter files its
        points by (it drew nothing without them) }
      if AHits[i].Axis <> nil then
      begin
        Result[n].AxisDimension := AHits[i].Axis.Dim;
        Result[n].AxisIndex := AHits[i].Axis.ComponentIndex;
      end;
      Inc(n);
    end;
  end;
end;

function TTyAdvanceChart.AxisTooltipContent(const AHits: TTyAxisHitArray;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
var
  i, k, slot, row: Integer;
  section: TTyTooltipBlock;
  header, valueText, vf: string;
  d: TTyChartDatumRef;
  p: TTyChartCallbackParams;
  rows, j: Integer;
  cells: TTyTipCells;
  sub: TTyTooltipBlock;
begin
  { A HEADERLESS ROOT HOLDING ONE SECTION PER AXIS, each holding one row per
    surviving series. Three layers, and the shape is what decides the spacing
    -- two axis sections space themselves further apart than one does, and
    that falls out of the tree rather than being written anywhere. }
  Result := TTyTooltipBlock.CreateSection('', True);
  rows := 0;
  for i := 0 to High(AHits) do
  begin
    { THE SECOND ARM OF A CROSS NEVER CONTRIBUTES A SECTION. Upstream hard-codes
      its triggerTooltip to false, which is why a cross shows one tooltip and
      not two. }
    if AHits[i].NoTip then Continue;
    { THE SAME ROUTINE AS THE POINTER'S LABEL, formatter and precision and
      all -- upstream's header is getValueLabel with the pointer's label
      options -- at the snapped row, which the tooltip always describes. A
      header left blank by the formatter is no header. }
    header := PointerLabelText(AHits[i], AHits[i].SnapValue);
    section := TTyTooltipBlock.CreateSection(header, False);
    for k := 0 to High(AHits[i].Slots) do
    begin
      slot := AHits[i].Slots[k];
      row := AHits[i].Rows[k];
      if (slot < 0) or (slot > High(FBindings)) then Continue;
      d := TyChartDatum(FBindings[slot].SeriesIndex, row,
        FStores[slot].GetRawIndex(row));
      p := TooltipParams(d);
      if Length(p.Values) = 0 then Continue;
      cells := TipCellsOf(FStores[slot], row,
        (FOption <> nil) and FOption.GetBool('useUTC', False));
      if not cells.Valid then valueText := ValuesText(p)
      else if cells.MultiLine then valueText := ''
      else valueText := TipInline(cells);
      { THE SERIES' OWN valueFormatter, else the global one: upstream builds
        each row's from the series and the component, never the item. }
      vf := TyTooltipSpecOf(FOption, FBindings[slot].SeriesIndex, -1).ValueFormatter;
      if (vf <> '') and cells.MultiLine then
      begin
        { as in an item tooltip: each sub-row by itself and without an
          index, the row itself with the empty list }
        valueText := TipValueFormatted(vf, p, '', True);
        for j := 0 to High(cells.Texts) do
          cells.Texts[j] := TipValueFormatted(vf, p, cells.Raws[j], False);
      end
      else if vf <> '' then
        valueText := TipValueFormatted(vf, p);
      { EACH SERIES IS ITS OWN HEADERLESS SECTION -- its row and its sub-rows
        together, so `order` and `seriesDesc` move them as one. It is what
        `order` sorts, keyed on the series' first inline RAW value. }
      sub := TTyTooltipBlock.CreateSection('', True);
      if cells.Valid then sub.SortCell := cells.Sort
      else sub.SortParam := p.Values[0];
      { UNDER AN AXIS TRIGGER THE INLINE NAME IS THE SERIES NAME, not the item
        name -- upstream passes `multipleSeries = true`, which both suppresses
        the per-series header AND switches the name. The item name is already
        the section's header, so repeating it on every row would say the
        category once per series. It is the DISPLAY name: an unnamed series'
        row has none. }
      sub.Add(TTyTooltipBlock.CreateNameValue(ttmItem, p.Color,
        SeriesNameOf(FBindings[slot].SeriesIndex), False, valueText, False));
      if cells.MultiLine then
        for j := 0 to High(cells.Texts) do
          sub.Add(TTyTooltipBlock.CreateNameValue(ttmSubItem, p.Color,
            TipRowName(cells.Names[j]), False, cells.Texts[j], False));
      section.Add(sub);
      Inc(rows);
    end;
    { `order` SORTS THE ROWS WITHIN ONE SECTION and nothing else. Upstream sets
      `sortBlocks` on the AXIS SECTION -- never on the root -- so a port that
      sorted the root would reorder the AXES and leave every row where it was.
      It runs after the reverse, and the reverse is unconditional. }
    if ASpec.HasOrder then section.SortBlocks(ASpec.Order);
    { THE SECTION IS ADDED WHETHER OR NOT ANY SERIES SURVIVED. Upstream pushes
      it before the series loop runs, so an axis with nothing on it still
      contributes its header line. }
    Result.Add(section);
  end;
  { THE SECTIONS ARE REVERSED, unconditionally and across coordinate systems
    rather than within one -- upstream's own comment is that the second axis
    displays above the first. }
  Result.Reverse;
  if rows = 0 then FreeAndNil(Result);
end;

{ ==================== the tooltip's box and timers [Batch 100] ====================

  UPSTREAM'S MACHINE, two objects of it: TooltipView._showOrMove (a show now,
  or after showDelay -- every new request replaces the waiting one) and
  TooltipRichContent (show() cancels a waiting hide; hideLater() arms one
  only while `_show` is set, and never under alwaysShowContent). The two
  global listeners that drive it are folded into one decision per pointer
  event: an axis hit shows the axis tooltip; an item whose cascade says
  `trigger: 'item'` shows its own; anything else is a hide -- the axis
  pointer's hideTip, which upstream dispatches on every move that finds no
  axis data. }

function TTyAdvanceChart.TipClock: Double;
begin
  if IsNan(FTipNow) then Result := TyAnimClockMs else Result := FTipNow;
end;

function TTyAdvanceChart.TipSnapNow: TTyTipSnap;
begin
  Result := Default(TTyTipSnap);
  Result.Datum := FTipDatum;
  Result.Hits := Copy(FTipHits, 0, Length(FTipHits));
  Result.Element := FTipElement;
  Result.X := FTipX;
  Result.Y := FTipY;
end;

function TTyAdvanceChart.TipIsMarker(const ADatum: TTyChartDatumRef): Boolean;
begin
  Result := (ADatum.Kind in [ctkMarkPoint, ctkMarkLine, ctkMarkArea])
    and (ADatum.ComponentIndex >= 0) and (ADatum.DataIndex >= 0);
end;

function TTyAdvanceChart.TipTargetValid(const ADatum: TTyChartDatumRef): Boolean;
begin
  Result := TyChartDatumValid(ADatum) or TipIsMarker(ADatum) or TipIsMatrix(ADatum)
    or IsGeoDatum(ADatum) or IsAxisTextDatum(ADatum);
end;

function TTyAdvanceChart.MatrixCellOf(const ADatum: TTyChartDatumRef;
  out AMatrix: TTyMatrix; out AInfo: TTyMatrixCellInfo): Boolean;
begin
  AMatrix := nil;
  AInfo := Default(TTyMatrixCellInfo);
  Result := False;
  if (ADatum.Kind <> ctkMatrix) or (ADatum.ComponentIndex < 0)
    or (ADatum.ComponentIndex > High(FMatrices)) then Exit;
  AMatrix := FMatrices[ADatum.ComponentIndex];
  if (AMatrix = nil) or (ADatum.DataIndex < 0)
    or (ADatum.DataIndex >= AMatrix.CellInfoCount) then Exit;
  AInfo := AMatrix.CellInfo(ADatum.DataIndex);
  Result := True;
end;

{ setTooltipConfig is called for a cell with a textValue only }
function TTyAdvanceChart.TipIsMatrix(const ADatum: TTyChartDatumRef): Boolean;
var
  m: TTyMatrix;
  info: TTyMatrixCellInfo;
begin
  Result := MatrixCellOf(ADatum, m, info) and info.HasText;
end;

{ formatTpl over a component item's params: $vars ['name', 'xyLocator'], so
  the placeholders a / a0 are the cell's name and b / b0 its locator pair as
  String() prints it -- each replaced at its first occurrence, as a string
  pattern is (values are not HTML-encoded: the port draws text, not markup) }
function TTyAdvanceChart.MatrixTipText(const AFormatter: string;
  const ADatum: TTyChartDatumRef): string;
var
  m: TTyMatrix;
  info: TTyMatrixCellInfo;

  procedure First(const AFind, AWith: string);
  var p: Integer;
  begin
    p := Pos(AFind, Result);
    if p > 0 then
      Result := Copy(Result, 1, p - 1) + AWith + Copy(Result, p + Length(AFind), MaxInt);
  end;

begin
  Result := AFormatter;
  if not MatrixCellOf(ADatum, m, info) then Exit;
  First('{a}', '{a0}');
  First('{b}', '{b0}');
  { [R2-I8] formatTpl(.., true): the name encodeHTML'd }
  First('{a0}', TyChartEncodeHtml(info.TipName));
  First('{b0}', IntToStr(info.Loc[0]) + ',' + IntToStr(info.Loc[1]));
end;

function TTyAdvanceChart.TipSpecOf(const ASnap: TTyTipSnap): TTyTooltipSpec;
var
  d: TJSONData;
  nLine, nCol: Integer;
begin
  if Length(ASnap.Hits) > 0 then Result := TyTooltipSpecOf(FOption, -1, -1)
  else Result := TooltipSpecFor(ASnap.Datum);
  { [Batch 153] a manual show: the payload's position before the
    cascade's (positionExpr || model.get('position')); else, for an item
    shown on its element, a default model of position 'bottom' under the
    cascade }
  if ASnap.PosJson <> '' then
  begin
    d := nil;
    if not TyJsonNestingExceeds(ASnap.PosJson, TyOptionMaxNesting, nLine, nCol) then
      try
        d := GetJSON(ASnap.PosJson);
      except
        d := nil;
      end;
    try
      if d <> nil then
        TyTooltipReadPosition(d, Result.Position, Result.PositionHandler);
    finally
      d.Free;
    end;
  end
  else if ASnap.PosDefault and (Result.Position.Kind = ctpDefault)
    and (Result.PositionHandler = '') then
  begin
    Result.Position.Kind := ctpSide;
    Result.Position.Side := 'bottom';
  end;
end;

procedure TTyAdvanceChart.TipTryShow(const ASnap: TTyTipSnap;
  const ASpec: TTyTooltipSpec);
var snap: TTyTipSnap;
begin
  { [R2-I7] the default markup first, as _showAxisTooltip and
    _showSeriesItemTooltip build it before _showOrMove }
  snap := ASnap;
  TipMarkup(snap);
  { _showOrMove: clearTimeout first, whatever the delay -- a show waiting
    is replaced by this one, or dropped when this one is immediate }
  FTipShowAt := NaN;
  if ASpec.ShowDelayMs > 0 then
  begin
    FTipPend := snap;
    FTipShowAt := TipClock + ASpec.ShowDelayMs;
    Inc(FTipSeq);
    FTipShowSeq := FTipSeq;
  end
  else
    TipApplyShow(snap);
end;

procedure TTyAdvanceChart.TipMarkup(var ASnap: TTyTipSnap);
var
  spec: TTyTooltipSpec;
  block: TTyTooltipBlock;
begin
  ASnap.MarkupHas := False;
  ASnap.Markup := nil;
  if FDirty or (FBuild = nil) or ASnap.Stale then Exit;
  { an axis tooltip's sections, or a series item's (a marker's) rows: what
    formatTooltip and buildTooltipMarkup make -- a valueFormatter runs here.
    A component item (a geo region, an axis' text, a matrix cell) has none. }
  if Length(ASnap.Hits) = 0 then
  begin
    if not TipTargetValid(ASnap.Datum) or IsGeoDatum(ASnap.Datum)
      or IsAxisTextDatum(ASnap.Datum) or TipIsMatrix(ASnap.Datum) then Exit;
  end;
  spec := TipSpecOf(ASnap);
  if not spec.HasComponent then Exit;
  if Length(ASnap.Hits) > 0 then block := AxisTooltipContent(ASnap.Hits, spec)
  else block := TooltipContent(ASnap.Datum, spec);
  try
    ASnap.MarkupHas := True;
    if block <> nil then ASnap.Markup := TyTooltipFlatten(block, TooltipInk(spec));
  finally
    block.Free;
  end;
end;

function TTyAdvanceChart.TipRowSig(ASlot, ARow: Integer): string;
var
  prm: TTyChartCallbackParams;
  k: Integer;
begin
  { cbParams.data, as `!==` sees it: a number or a string by its value, an
    array or an object by its cells (upstream: by identity -- the same
    cells written again by a setOption are new objects there and the same
    data here) }
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) or (ASlot > High(FStores))
    or (FStores[ASlot] = nil) or (ARow < 0) or (ARow >= FStores[ASlot].Count) then Exit;
  prm := TooltipParams(TyChartDatum(FBindings[ASlot].SeriesIndex, ARow,
    FStores[ASlot].GetRawIndex(ARow)));
  case prm.Raw.Shape of
    rshScalar: Result := 's:' + TyJsValueText(prm.Raw.Scalar, '');
    rshArray, rshObject:
      begin
        Result := 'o:';
        for k := 0 to High(prm.Raw.Cells) do
          Result := Result + TyJsValueText(prm.Raw.Cells[k], '') + #1;
      end;
  else
    Result := 'n:' + prm.ValueText;
  end;
end;

procedure TTyAdvanceChart.TipApplyShow(const ASnap: TTyTipSnap);
var
  spec: TTyTooltipSpec;
  arr: TJSONArray;
  prevDbc: string;
  tips: TTyAxisHitArray;
  sigs: TTyStringArray;
  sigSeries: TTyIntegerArray;
  unchanged: Boolean;
  i, k, n, s: Integer;
begin
  { [F4b] _showAxisTooltip's callback: _updateContentNotChangedOnAxis keeps
    the dataByCoordSys first, whatever the content then does }
  prevDbc := FTipLastDbc;
  unchanged := False;
  if Length(ASnap.Hits) > 0 then
  begin
    tips := TipAxesHits(ASnap.Hits);
    arr := TipDbcJson(tips);
    try
      FTipLastDbc := arr.AsJSON;
    finally
      arr.Free;
    end;
    { [R2-I7] _cbParamsList's data, one per row in the order the params
      were pushed }
    sigs := nil;
    sigSeries := nil;
    for i := 0 to High(tips) do
      for k := 0 to High(tips[i].Slots) do
      begin
        n := Length(sigs);
        SetLength(sigs, n + 1);
        SetLength(sigSeries, n + 1);
        sigs[n] := TipRowSig(tips[i].Slots[k], tips[i].Rows[k]);
        sigSeries[n] := SlotSeriesIndex(tips[i].Slots[k]);
      end;
    { THE SAME CONTENT: the same axes, values and rows, and no row whose
      data changed -- read, as upstream reads it, at the params of each
      row's SERIES INDEX in the pushed order }
    unchanged := (prevDbc <> '') and (prevDbc = FTipLastDbc);
    if unchanged then
      for i := 0 to High(sigSeries) do
      begin
        s := sigSeries[i];
        if (s >= 0) and (s <= High(sigs)) and (s <= High(FTipLastSigs))
          and (sigs[s] <> FTipLastSigs[s]) then unchanged := False;
      end;
    FTipLastSigs := sigs;
    FTipLastSigSeries := sigSeries;
  end
  else if ASnap.DbcJson <> '' then
    FTipLastDbc := ASnap.DbcJson;
  spec := TipSpecOf(ASnap);
  { [R2-I7] the content unchanged: _updatePosition alone -- no formatter,
    the box keeps what it says; a position function runs again }
  if unchanged and FTipShown and FTipCur.Has then
  begin
    FTipSnap := ASnap;
    Inc(FTipShowGen);
    Exit;
  end;
  { _showTooltipContent returns before anything for `show: false` or
    `showContent: false` -- and a box already up stays as it was }
  if not spec.HasComponent or not spec.Show or not spec.ShowContent then Exit;
  { show(): the waiting hide is cancelled }
  FTipHideAt := NaN;
  FTipShown := True;
  FTipShowFlag := True;
  FTipSnap := ASnap;
  { [R2-I7] setContent: once, here (the build standing), else at the next
    paint; and a position function asked again }
  Inc(FTipShowGen);
  FTipCurDue := True;
  if not FDirty and (FBuild <> nil) then
  begin
    TipSnapRefresh;
    FTipCurDue := False;
    TipBuildContent(FTipSnap, FTipCur);
  end;
end;

procedure TTyAdvanceChart.TipHide(const AGlobal: TTyTooltipSpec);
begin
  { hideLater(hideDelay), the GLOBAL model's: nothing unless `_show` is
    still set, nothing under alwaysShowContent; a delay arms a timer and
    clears `_show` at once (the box stays up), none hides now }
  if (not FTipShowFlag) or AGlobal.AlwaysShowContent then Exit;
  FTipShowFlag := False;
  if AGlobal.HideDelayMs > 0 then
  begin
    FTipHideAt := TipClock + AGlobal.HideDelayMs;
    Inc(FTipSeq);
    FTipHideSeq := FTipSeq;
  end
  else
    FTipShown := False;
end;

function TTyAdvanceChart.TipAdvance(ANow: Double): Boolean;
var
  showDue, hideDue, keepDue, showFirst: Boolean;
  bestAt: Double;
  bestSeq, which: Integer;

  procedure Consider(ADue: Boolean; AAt: Double; ASeq, AWhich: Integer);
  begin
    if not ADue then Exit;
    if (which < 0) or (AAt < bestAt) or ((AAt = bestAt) and (ASeq < bestSeq)) then
    begin
      bestAt := AAt;
      bestSeq := ASeq;
      which := AWhich;
    end;
  end;

begin
  Result := False;
  if IsNan(ANow) then Exit;
  { [F4b] one timeout at a time: a timer's work (the keep timer's
    dispatches) does not fire the others inside it }
  if FTipAdvancing then Exit;
  FTipAdvancing := True;
  try
  repeat
    showDue := (not IsNan(FTipShowAt)) and (FTipShowAt <= ANow);
    hideDue := (not IsNan(FTipHideAt)) and (FTipHideAt <= ANow);
    { [F4b] the keep timer never fires inside a dispatch }
    keepDue := (not IsNan(FTipKeepAt)) and (FTipKeepAt <= ANow) and (FActCycle = 0);
    if not (showDue or hideDue or keepDue) then Break;
    { in the order the timeouts would have fired: by time, then by
      creation }
    which := -1;
    bestAt := 0;
    bestSeq := 0;
    Consider(showDue, FTipShowAt, FTipShowSeq, 0);
    Consider(hideDue, FTipHideAt, FTipHideSeq, 1);
    Consider(keepDue, FTipKeepAt, FTipKeepSeq, 2);
    if which = 2 then
    begin
      FTipKeepAt := NaN;
      TipKeepFire;
      Result := True;
      Continue;
    end;
    showFirst := which = 0;
    if showFirst then
    begin
      FTipShowAt := NaN;
      TipApplyShow(FTipPend);
      FTipPend := Default(TTyTipSnap);
      FTipPend.Datum := TyChartNoDatum;
      FTipPend.Element := -1;
    end
    else
    begin
      FTipHideAt := NaN;
      FTipShown := False;
    end;
    Result := True;
  until False;
  finally
    FTipAdvancing := False;
  end;
end;

procedure TTyAdvanceChart.TipArmTimer;
var due, ms: Double;
begin
  due := NaN;
  if not IsNan(FTipShowAt) then due := FTipShowAt;
  if (not IsNan(FTipHideAt)) and (IsNan(due) or (FTipHideAt < due)) then
    due := FTipHideAt;
  { [F4b] the keep timer }
  if (not IsNan(FTipKeepAt)) and (IsNan(due) or (FTipKeepAt < due)) then
    due := FTipKeepAt;
  { only on the machine's clock: a test steps TooltipTick itself }
  if IsNan(due) or (not IsNan(FTipNow)) or (csDesigning in ComponentState) then
  begin
    if FTipTimer <> nil then FTipTimer.Enabled := False;
    Exit;
  end;
  if FTipTimer = nil then
  begin
    FTipTimer := TTimer.Create(nil);
    FTipTimer.Enabled := False;
    FTipTimer.OnTimer := @TipTimerFired;
  end;
  ms := due - TipClock;
  if ms < 1 then ms := 1;
  if ms > 600000 then ms := 600000;
  FTipTimer.Enabled := False;
  FTipTimer.Interval := Cardinal(Ceil(ms));
  FTipTimer.Enabled := True;
end;

procedure TTyAdvanceChart.TipTimerFired(Sender: TObject);
begin
  if FTipTimer <> nil then FTipTimer.Enabled := False;
  if TipAdvance(TipClock) then TipInvalidate;
  TipArmTimer;
end;

procedure TTyAdvanceChart.TooltipTick(ANowMs: Double);
begin
  if TipAdvance(ANowMs) then TipInvalidate;
  TipArmTimer;
end;

{ ==================== the tooltip and the pointer driven by actions [Batch 153] ====================

  UPSTREAM'S FLOW, carried over whole. A zrender mousemove / click /
  mousewheel / globalout goes through the global listener's two records in
  the order they were registered: the axis pointer's (AxisPointerView: under
  its triggerOn -- or any leave -- an updateAxisPointer (currTrigger, x, y)
  whose dispatchAction is the listener's) and the item tooltip's
  (TooltipView: under the tooltip's triggerOn, _tryShow on the hovered
  target; a leave its triggerOn does not name, _hide). Both hand their
  showTip / hideTip to the listener, which dispatches the last show, else the
  last hide, once they are done (dispatchTooltipFinally).

  updateAxisPointer is axisTrigger: the pointer state (the hits), its event
  (a sample row and the axes shown), then a showTip with dataByCoordSys or a
  hideTip. showTip and hideTip are noop actions whose update is the view's
  manuallyShowTip / manuallyHideTip; whatever those dispatch through the
  chart waits for the action to finish (IN_EC_CYCLE) and is flushed before
  `updated`. A connected chart is sent each event as its action: the showTip
  axisTrigger dispatches says escapeConnect, so a chart in the group follows
  through updateAxisPointer and finds its own point (findPointFromSeries). }

function TTyAdvanceChart.TipUid: string;
begin
  Result := 'ec_' + IntToStr(FInstanceNo) + '_tooltip';
end;

function TTyAdvanceChart.ApTriggerOn(const AGlobal: TTyTooltipSpec): string;
var ap, d: TJSONData;
begin
  Result := '';
  if FOption <> nil then
  begin
    ap := FOption.ComponentAt('axisPointer', 0);
    if ap is TJSONObject then
    begin
      d := TJSONObject(ap).Find('triggerOn');
      if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
    end;
  end;
  if (Result = '') and AGlobal.HasComponent then Result := AGlobal.TriggerOn;
  if Result = '' then Result := 'mousemove|click|mousewheel';
end;

function TTyAdvanceChart.TipSeriesOnAxis(ASeriesIndex: Integer): Boolean;
var n, t, d: TJSONData;
begin
  Result := True;
  if FOption = nil then Exit;
  n := FOption.ComponentAt('series', ASeriesIndex);
  if not (n is TJSONObject) then Exit;
  t := TJSONObject(n).Find('tooltip');
  if t is TJSONObject then
  begin
    d := TJSONObject(t).Find('trigger');
    if (d <> nil) and (((d.JSONType = jtString)
      and ((d.AsString = 'none') or (d.AsString = 'item')))
      or ((d.JSONType = jtBoolean) and not d.AsBoolean)) then Exit(False);
    d := TJSONObject(t).Find('show');
    if (d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean then Exit(False);
  end;
  t := TJSONObject(n).Find('axisPointer');
  if t is TJSONObject then
  begin
    d := TJSONObject(t).Find('show');
    if (d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean then Exit(False);
  end;
end;

{ `payload.from === this.uid` }
function TipFromIs(APayload: TJSONObject; const AUid: string): Boolean;
var d: TJSONData;
begin
  d := APayload.Find('from');
  Result := (d <> nil) and (d.JSONType = jtString) and (d.AsString = AUid);
end;

{ x and y, numbers both and neither NaN (illegalPoint's other side) }
function TipPayloadXY(APayload: TJSONObject; out AX, AY: Double): Boolean;
var dx, dy: TJSONData;
begin
  AX := NaN;
  AY := NaN;
  dx := APayload.Find('x');
  dy := APayload.Find('y');
  Result := (dx <> nil) and (dx.JSONType = jtNumber) and (dy <> nil)
    and (dy.JSONType = jtNumber);
  if not Result then Exit;
  AX := dx.AsFloat;
  AY := dy.AsFloat;
  Result := not IsNan(AX) and not IsNan(AY);
end;

{ the payload's `position` as JSON when it is truthy (e.position ||
  model.get('position')) }
function TipPositionJson(APayload: TJSONObject): string;
var d: TJSONData;
begin
  Result := '';
  d := APayload.Find('position');
  if JsTruthy(d) then Result := d.AsJSON;
end;

procedure TTyAdvanceChart.TipDispatch(APayload: TJSONObject;
  const AHits: TTyAxisHitArray; AHasHits, AViaListener: Boolean);
var
  t: string;
  n: Integer;
begin
  t := APayload.Get('type', '');
  { the listener's makeDispatchAction: a showTip or a hideTip waits, the
    last of each }
  if AViaListener and FGlActive and ((t = 'showTip') or (t = 'hideTip')) then
  begin
    if t = 'showTip' then
    begin
      FGlShow.Payload.Free;
      FGlShow.Payload := APayload;
      FGlShow.Hits := Copy(AHits, 0, Length(AHits));
      FGlShow.HasHits := AHasHits;
    end
    else
    begin
      FGlHide.Payload.Free;
      FGlHide.Payload := APayload;
      FGlHide.Hits := nil;
      FGlHide.HasHits := False;
    end;
    Exit;
  end;
  { IN_EC_CYCLE: after the action that dispatched it }
  if FActCycle > 0 then
  begin
    n := Length(FActPending);
    SetLength(FActPending, n + 1);
    FActPending[n].Payload := APayload;
    FActPending[n].Hits := Copy(AHits, 0, Length(AHits));
    FActPending[n].HasHits := AHasHits;
    Exit;
  end;
  FActHits.Hits := Copy(AHits, 0, Length(AHits));
  FActHits.HasHits := AHasHits;
  DispatchActionObject(APayload);
end;

procedure TTyAdvanceChart.ActFlushPending;
var
  a: TTyTipAct;
  i: Integer;
begin
  { flushPendingActions: in order, each a doDispatchAction of its own --
    whatever it dispatches joins the end of the queue }
  while Length(FActPending) > 0 do
  begin
    a := FActPending[0];
    for i := 0 to High(FActPending) - 1 do FActPending[i] := FActPending[i + 1];
    SetLength(FActPending, Length(FActPending) - 1);
    { [F4b] a brushSelect waiting: its event, nothing to update }
    if a.Payload = nil then
    begin
      if a.EventJson <> '' then EmitPayloadEvent('brushselected', a.EventJson);
      Continue;
    end;
    FActHits.Hits := a.Hits;
    FActHits.HasHits := a.HasHits;
    DispatchActionCore(a.Payload);
    FActHits.Hits := nil;
    FActHits.HasHits := False;
  end;
end;

procedure TTyAdvanceChart.ActForgetHits;
var i: Integer;
begin
  for i := 0 to High(FActPending) do
  begin
    FActPending[i].Hits := nil;
    FActPending[i].HasHits := False;
  end;
  FGlShow.Hits := nil;
  FGlShow.HasHits := False;
  FActHits.Hits := nil;
  FActHits.HasHits := False;
end;

procedure TTyAdvanceChart.ActDropPending;
var i: Integer;
begin
  for i := 0 to High(FActPending) do FActPending[i].Payload.Free;
  FActPending := nil;
  FreeAndNil(FGlShow.Payload);
  FGlShow.Hits := nil;
  FreeAndNil(FGlHide.Payload);
  FGlHide.Hits := nil;
  FActHits.Hits := nil;
  FActHits.HasHits := False;
end;

procedure TTyAdvanceChart.PtrListener(const ATrigger: string; AX, AY: Integer;
  const ADatum: TTyChartDatumRef; AElement: Integer);
var
  g: TTyTooltipSpec;
  apOn: string;
  uap, fin: TJSONObject;
  ev: TTyTipEvent;
  hits: TTyAxisHitArray;
  hasHits: Boolean;
begin
  if (FOption = nil) or (csDesigning in ComponentState) then Exit;
  g := TyTooltipSpecOf(FOption, -1, -1);
  { NO TOOLTIP COMPONENT, NO TOOLTIP VIEW: upstream builds none, whatever a
    series or a data item writes -- the axis pointer's record still runs }
  if not g.HasComponent then TipDropDisplay
  { the timers that fell due before this event fire first }
  else TipAdvance(TipClock);
  FreeAndNil(FGlShow.Payload);
  FreeAndNil(FGlHide.Payload);
  FGlShow.Hits := nil;
  FGlActive := True;
  try
    { AxisPointerView's record: 'none' is no record at all; a leave always
      reaches it }
    apOn := ApTriggerOn(g);
    if (apOn <> 'none') and ((ATrigger = 'leave') or (Pos(ATrigger, apOn) > 0)) then
    begin
      uap := TJSONObject.Create(['type', 'updateAxisPointer', 'currTrigger', ATrigger]);
      if ATrigger <> 'leave' then
      begin
        uap.Add('x', AX);
        uap.Add('y', AY);
      end;
      FUapListener := True;
      try
        DispatchActionObject(uap);
      finally
        FUapListener := False;
      end;
    end;
    { TooltipView's record: only with a tooltip component; 'none' hears
      nothing; a trigger its triggerOn names is _tryShow on the hovered
      target, any other leave is _hide }
    if g.HasComponent and (g.TriggerOn <> 'none') then
    begin
      if Pos(ATrigger, g.TriggerOn) > 0 then
      begin
        ev := TipEventBlank;
        ev.X := AX;
        ev.Y := AY;
        if ATrigger <> 'leave' then
        begin
          ev.Datum := ADatum;
          ev.Element := AElement;
          { [F4c] no item: an axis' name or label that is not silent }
          if not TipTargetValid(ADatum) and AxisTextAt(AX, AY, ev.Datum) then
            ev.Element := -1;
        end;
        TipTryShowEvent(ev, True);
      end
      else if ATrigger = 'leave' then
        TipHideVia(True);
    end;
  finally
    FGlActive := False;
  end;
  { dispatchTooltipFinally: the last showTip, else the last hideTip, its
    dispatchAction null }
  fin := nil;
  hits := nil;
  hasHits := False;
  if FGlShow.Payload <> nil then
  begin
    fin := FGlShow.Payload;
    FGlShow.Payload := nil;
    hits := FGlShow.Hits;
    hasHits := FGlShow.HasHits;
  end
  else if FGlHide.Payload <> nil then
  begin
    fin := FGlHide.Payload;
    FGlHide.Payload := nil;
  end;
  FreeAndNil(FGlShow.Payload);
  FreeAndNil(FGlHide.Payload);
  FGlShow.Hits := nil;
  if fin <> nil then
  begin
    fin.Add('dispatchAction', TJSONNull.Create);
    FActHits.Hits := hits;
    FActHits.HasHits := hasHits;
    DispatchActionObject(fin);
  end;
  TipArmTimer;
end;

function TTyAdvanceChart.TipElementRect(AIndex, APPI: Integer): TTyRectF;
var
  el: TTyChartElement;
  w: Double;
begin
  Result := TyInvalidRectF;
  if (FPaintList = nil) or (AIndex < 0) or (AIndex >= FPaintList.Count) then Exit;
  el := FPaintList.Element(AIndex);
  Result := TyShapeBounds(el.Shape);
  if not TyRectFIsValid(Result) or (el.Style.StrokeWidthLogical <= 0) then Exit;
  w := el.Style.StrokeWidthLogical;
  if not el.Style.HasFill then w := Max(w, Double(4));
  w := w * APPI / 96;
  Result.Left := Result.Left - w / 2;
  Result.Top := Result.Top - w / 2;
  Result.Right := Result.Right + w / 2;
  Result.Bottom := Result.Bottom + w / 2;
end;

function TTyAdvanceChart.TipAxesHits(const AHits: TTyAxisHitArray): TTyAxisHitArray;
var i, n: Integer;
begin
  Result := nil;
  if FOption = nil then Exit;
  { showTooltip: axisInfo.triggerTooltip -- the base axis of an axis
    trigger, never a cross arm, and an axis collected for its own show that
    triggers -- and a payload batch
    [Revised in R2-I7: none at all unless the tooltip's trigger was
    'axis'.] }
  for i := 0 to High(AHits) do
    if not AHits[i].NoTip and (Length(AHits[i].Slots) > 0) then
    begin
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := AHits[i];
    end;
end;

function TyAxisTypeName(AType: TTyAxisType): string;
begin
  case AType of
    atCategory: Result := 'category';
    atTime: Result := 'time';
    atLog: Result := 'log';
  else
    Result := 'value';
  end;
end;

function TTyAdvanceChart.TipDbcJson(const AHits: TTyAxisHitArray): TJSONArray;
var
  i, k, n, gi, s, raw: Integer;
  keys: array of string;
  key, mt: string;
  cs, ax, lab, it: TJSONObject;
  sdi: TJSONArray;
  h: TTyAxisHit;
begin
  Result := TJSONArray.Create;
  keys := nil;
  for i := 0 to High(AHits) do
  begin
    h := AHits[i];
    if h.Axis = nil then Continue;
    { the coordinate system's model: the grid, the polar, the single axis }
    gi := -1;
    if h.Polar <> nil then
    begin
      mt := 'polar';
      for k := 0 to High(FPolars) do
        if FPolars[k] = h.Polar then gi := k;
    end
    else if h.Single <> nil then
    begin
      mt := 'singleAxis';
      gi := h.Axis.ComponentIndex;
    end
    else
    begin
      mt := 'grid';
      gi := h.Axis.GridIndex;
    end;
    key := mt + #1 + IntToStr(gi);
    cs := nil;
    for k := 0 to High(keys) do
      if keys[k] = key then cs := TJSONObject(Result.Items[k]);
    if cs = nil then
    begin
      cs := TJSONObject.Create;
      cs.Add('coordSysId', FOption.ComponentId(mt, gi));
      cs.Add('coordSysIndex', gi);
      cs.Add('coordSysType', mt);
      cs.Add('coordSysMainType', mt);
      cs.Add('dataByAxis', TJSONArray.Create);
      Result.Add(cs);
      n := Length(keys);
      SetLength(keys, n + 1);
      keys[n] := key;
    end;
    ax := TJSONObject.Create;
    ax.Add('axisDim', h.Axis.Dim);
    ax.Add('axisIndex', h.Axis.ComponentIndex);
    ax.Add('axisType', h.Axis.MainType + '.' + TyAxisTypeName(h.Axis.AxisType));
    ax.Add('axisId', FOption.ComponentId(h.Axis.MainType, h.Axis.ComponentIndex));
    { the tooltip says snapToValue }
    ax.Add('value', TJSONFloatNumber.Create(h.SnapValue));
    lab := TJSONObject.Create;
    if h.Spec.LabelSpec.HasPrecision and (h.Spec.LabelSpec.Precision.Kind = lpDigits) then
      lab.Add('precision', TJSONFloatNumber.Create(h.Spec.LabelSpec.Precision.Digits))
    else
      lab.Add('precision', 'auto');
    { a template; a function is no JSON }
    if h.Spec.LabelSpec.HasFormatter and not TyChartIsHandlerRef(h.Spec.LabelSpec.Formatter) then
      lab.Add('formatter', h.Spec.LabelSpec.Formatter);
    ax.Add('valueLabelOpt', lab);
    sdi := TJSONArray.Create;
    for k := 0 to High(h.Slots) do
    begin
      s := h.Slots[k];
      raw := h.Rows[k];
      if (s >= 0) and (s <= High(FStores)) and (FStores[s] <> nil) then
        raw := FStores[s].GetRawIndex(h.Rows[k]);
      it := TJSONObject.Create;
      it.Add('seriesIndex', SlotSeriesIndex(s));
      it.Add('dataIndexInside', h.Rows[k]);
      it.Add('dataIndex', raw);
      sdi.Add(it);
    end;
    ax.Add('seriesDataIndices', sdi);
    cs.Arrays['dataByAxis'].Add(ax);
  end;
end;

function TTyAdvanceChart.TipAxisAt(const ADim: string; AIndex: Integer;
  out APlot: TTyRectF; out APolar: TTyPolar; out ASingle: TTySingle): TTyAxis;
var
  g, c: Integer;
  gb: TTyGridBuild;
  cart: TTyCartesian2D;
  ax: TTyAxis;

  procedure Take(AAxis: TTyAxis);
  begin
    if (ax = nil) and (AAxis <> nil) and (AAxis.Dim = ADim)
      and (AAxis.ComponentIndex = AIndex) then ax := AAxis;
  end;

begin
  ax := nil;
  APlot := Default(TTyRectF);
  APolar := nil;
  ASingle := nil;
  if FBuild <> nil then
    for g := 0 to FBuild.GridCount - 1 do
    begin
      gb := FBuild.Grid(g);
      for c := 0 to gb.CartesianCount - 1 do
      begin
        cart := gb.CartesianByIndex(c);
        if cart = nil then Continue;
        if ax = nil then
        begin
          Take(cart.AxisByDim('x'));
          Take(cart.AxisByDim('y'));
          if ax <> nil then APlot := gb.PlotRect;
        end;
      end;
    end;
  if ax = nil then
    for g := 0 to High(FPolars) do
      if (ax = nil) and (FPolars[g] <> nil) then
      begin
        Take(FPolars[g].AxisByDim('radius'));
        Take(FPolars[g].AxisByDim('angle'));
        if ax <> nil then APolar := FPolars[g];
      end;
  if ax = nil then
    for g := 0 to High(FSingles) do
      if (ax = nil) and (FSingles[g] <> nil) then
      begin
        Take(FSingles[g].Axis);
        if ax <> nil then
        begin
          ASingle := FSingles[g];
          APlot := ASingle.GetRect;
        end;
      end;
  Result := ax;
end;

function TTyAdvanceChart.TipHitsOfDbc(ADbc: TJSONArray; AByRaw: Boolean): TTyAxisHitArray;
var
  i, j, k, n, slot, row, m: Integer;
  cs, ai, it: TJSONObject;
  dba, sdi: TJSONArray;
  d: TJSONData;
  dim: string;
  idx: Integer;
  v: Double;
  ax: TTyAxis;
  hit: TTyAxisHit;
  plot: TTyRectF;
  pol: TTyPolar;
  sgl: TTySingle;
  crossType, isCat: Boolean;
  infos: TTyPtrAxisInfoArray;
begin
  Result := nil;
  if (ADbc = nil) or (FBuild = nil) or (FOption = nil) then Exit;
  crossType := TyTooltipAxisPointerType(FOption) = aptCross;
  infos := PtrCollect;
  for i := 0 to ADbc.Count - 1 do
  begin
    if not (ADbc.Items[i] is TJSONObject) then Continue;
    cs := TJSONObject(ADbc.Items[i]);
    d := cs.Find('dataByAxis');
    if not (d is TJSONArray) then Continue;
    dba := TJSONArray(d);
    for j := 0 to dba.Count - 1 do
    begin
      if not (dba.Items[j] is TJSONObject) then Continue;
      ai := TJSONObject(dba.Items[j]);
      dim := ai.Get('axisDim', '');
      d := ai.Find('axisIndex');
      if (d = nil) or (d.JSONType <> jtNumber) then Continue;
      idx := Trunc(d.AsFloat);
      { the axis' model by dimension and index, wherever it lives }
      ax := TipAxisAt(dim, idx, plot, pol, sgl);
      if ax = nil then Continue;
      { axisValue == null: nothing for this axis }
      d := ai.Find('value');
      if (d = nil) or (d.JSONType = jtNull) then Continue;
      isCat := ax.Scale is TTyOrdinalScale;
      v := NaN;
      if d.JSONType = jtNumber then v := d.AsFloat
      else if (d.JSONType = jtString) and isCat and (ax.Categories <> nil) then
      begin
        m := ax.Categories.GetOrdinal(d.AsString);
        if m >= 0 then v := m;
      end;
      hit := Default(TTyAxisHit);
      hit.Axis := ax;
      hit.Plot := plot;
      hit.Polar := pol;
      hit.Single := sgl;
      { [R2-I7] the axisInfo's model when the axis is collected (an axis of
        its own show reads its own label), else the tooltip's }
      m := PtrInfoOf(infos, ax);
      if m >= 0 then hit.Spec := infos[m].Spec
      else
        hit.Spec := TyAxisPointerSpecOf(FOption, ax.MainType, ax.ComponentIndex,
          isCat, True, True, crossType);
      hit.Value := v;
      hit.SnapValue := v;
      d := ai.Find('seriesDataIndices');
      if d is TJSONArray then
      begin
        sdi := TJSONArray(d);
        for k := 0 to sdi.Count - 1 do
        begin
          if not (sdi.Items[k] is TJSONObject) then Continue;
          it := TJSONObject(sdi.Items[k]);
          d := it.Find('seriesIndex');
          if (d = nil) or (d.JSONType <> jtNumber) then Continue;
          slot := SlotOfSeries(Trunc(d.AsFloat));
          if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
          if AByRaw then
          begin
            { [F4b] the row that raw index is in the build standing now }
            d := it.Find('dataIndex');
            if (d = nil) or (d.JSONType <> jtNumber) then Continue;
            row := FStores[slot].IndexOfRawIndex(Trunc(d.AsFloat));
          end
          else
          begin
            d := it.Find('dataIndexInside');
            if (d = nil) or (d.JSONType <> jtNumber) then Continue;
            row := Trunc(d.AsFloat);
          end;
          { getDataParams of a row that is not there: no data, skipped }
          if (row < 0) or (row >= FStores[slot].Count) then Continue;
          n := Length(hit.Slots);
          SetLength(hit.Slots, n + 1);
          SetLength(hit.Rows, n + 1);
          hit.Slots[n] := slot;
          hit.Rows[n] := row;
        end;
      end;
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := hit;
    end;
  end;
end;

function TTyAdvanceChart.TipCollectionOrder: TTyAxisArray;
var
  infos: TTyPtrAxisInfoArray;
  k: Integer;
begin
  { [R2-I7] the axisPointer model's axes as collectAxesInfo collected them }
  infos := PtrCollect;
  SetLength(Result, Length(infos));
  for k := 0 to High(infos) do Result[k] := infos[k].Axis;
end;

function TTyAdvanceChart.TipSeriesPoint(APayload: TJSONObject; AFull: Boolean;
  out AX, AY: Double; out ADatum: TTyChartDatumRef;
  out AElement: Integer): Boolean;
var
  d: TJSONData;
  s, slot, row, i, ix, iy: Integer;
  st: TTyDataStore;
  nm: string;
  pt: TTyPointF;
  b: TTyRectF;

  function Val_(ADimIndex: Integer): Double;
  begin
    if ADimIndex < 0 then Result := NaN
    else Result := st.Get(ADimIndex, row);
  end;

begin
  Result := False;
  AX := NaN;
  AY := NaN;
  ADatum := TyChartNoDatum;
  AElement := -1;
  if (FOption = nil) or (FBuild = nil) then Exit;
  d := APayload.Find('seriesIndex');
  if (d = nil) or (d.JSONType <> jtNumber) or (Frac(d.AsFloat) <> 0) then Exit;
  s := Trunc(d.AsFloat);
  slot := SlotOfSeries(s);
  if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
  st := FStores[slot];
  row := -1;
  { queryDataIndex: dataIndexInside, else dataIndex (a raw index), else
    name -- a list of them is no point }
  d := nil;
  if AFull then d := APayload.Find('dataIndexInside');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d.JSONType <> jtNumber then Exit;
    row := Trunc(d.AsFloat);
    { a row this chart does not have: getValues answers nothing, the
      point is NaN and there is no element }
    if row >= st.Count then
    begin
      Result := True;
      Exit;
    end;
  end
  else
  begin
    d := APayload.Find('dataIndex');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      if d.JSONType <> jtNumber then Exit;
      row := st.IndexOfRawIndex(Trunc(d.AsFloat));
    end
    else
    begin
      if AFull then d := APayload.Find('name') else d := nil;
      if (d = nil) or (d.JSONType <> jtString) then Exit;
      nm := d.AsString;
      { data.getName: the item's name, else its category's }
      for i := 0 to st.Count - 1 do
        if st.GetItemName(i) = nm then
        begin
          row := i;
          Break;
        end;
    end;
  end;
  if row < 0 then Exit;
  ADatum := TyChartDatum(s, row, st.GetRawIndex(row));
  AElement := KbElementOf(s, row);
  Result := True;
  { coordSys.dataToPoint of the row's values on the coordinate system's
    dimensions -- not stacked: findPointFromSeries is not asked isStacked }
  if (FBindings[slot].XAxis <> nil) and (FBindings[slot].YAxis <> nil) then
  begin
    ix := st.DimIndexOf(FBindings[slot].XAxis.Dim);
    iy := st.DimIndexOf(FBindings[slot].YAxis.Dim);
    { [R2-J3] Cartesian2D.dataToPoint: through the affine matrix when both
      axes are value or time and both values are finite (its last bits are
      not the per-axis answer's), else axis by axis [was: always per axis] }
    if FBindings[slot].Cart <> nil then
    begin
      pt := FBindings[slot].Cart.DataToPoint([Val_(ix), Val_(iy)]);
      AX := pt.X;
      AY := pt.Y;
    end
    else
    begin
      AX := FBindings[slot].XAxis.DataToCoord(Val_(ix));
      AY := FBindings[slot].YAxis.DataToCoord(Val_(iy));
    end;
  end
  else if FBindings[slot].Polar <> nil then
  begin
    pt := TTyPolar(FBindings[slot].Polar).DataToPoint([Val_(st.DimIndexOf('radius')),
      Val_(st.DimIndexOf('angle'))]);
    AX := pt.X;
    AY := pt.Y;
  end
  else if FBindings[slot].Single <> nil then
  begin
    pt := TTySingle(FBindings[slot].Single).DataToPoint([Val_(st.DimIndexOf('single'))]);
    AX := pt.X;
    AY := pt.Y;
  end
  { no coordinate system: the element's bounding rect, its centre }
  else if (AElement >= 0) and (FPaintList <> nil) then
  begin
    b := TyShapeBounds(FPaintList.Element(AElement).Shape);
    AX := b.Left + (b.Right - b.Left) / 2;
    AY := b.Top + (b.Bottom - b.Top) / 2;
  end
  else
    Result := False;
end;

function TTyAdvanceChart.TipComponentRef(APayload: TJSONObject;
  out ADatum: TTyChartDatumRef; out AElement: Integer; out AX, AY: Double): Boolean;
const
  cSuffixes: array[0..2] of string = ('Index', 'Id', 'Name');
var
  i, k, mx, cnt, grp: Integer;
  key, mt, nm: string;
  d: TJSONData;
  el: TTyChartElement;
  m: TTyMatrix;
  info: TTyMatrixCellInfo;
  b, u: TTyRectF;
  any: Boolean;

  function WordChars(const S: string): Boolean;
  var j: Integer;
  begin
    Result := S <> '';
    for j := 1 to Length(S) do
      if not (S[j] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit(False);
  end;

begin
  Result := False;
  ADatum := TyChartNoDatum;
  AElement := -1;
  AX := NaN;
  AY := NaN;
  if (FOption = nil) or (FPaintList = nil) or not FPaintListValid then Exit;
  { preParseFinder: the first key of the form <mainType>Index / Id / Name
    names the main type }
  mt := '';
  for i := 0 to APayload.Count - 1 do
  begin
    key := APayload.Names[i];
    if (key = 'dataIndex') or (key = 'dataIndexInside') then Continue;
    for k := 0 to High(cSuffixes) do
      if (Length(key) > Length(cSuffixes[k]))
        and (Copy(key, Length(key) - Length(cSuffixes[k]) + 1, MaxInt) = cSuffixes[k])
        and WordChars(Copy(key, 1, Length(key) - Length(cSuffixes[k]))) then
      begin
        mt := Copy(key, 1, Length(key) - Length(cSuffixes[k]));
        Break;
      end;
    if mt <> '' then Break;
  end;
  if (mt = '') or (mt = 'series') then Exit;
  { the port's component tooltips are a matrix's cells and a geo's regions }
  if mt = TyMatrixCoordSysName then cnt := Length(FMatrices)
  else if mt = 'geo' then cnt := Length(FGeos)
  else Exit;
  mx := -1;
  d := APayload.Find(mt + 'Index');
  if (d <> nil) and (d.JSONType = jtNumber) then mx := Trunc(d.AsFloat)
  else
  begin
    d := APayload.Find(mt + 'Id');
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      for k := 0 to cnt - 1 do
        if (mx < 0) and (FOption.ComponentId(mt, k) = d.AsString) then mx := k;
    end
    else
    begin
      d := APayload.Find(mt + 'Name');
      if (d <> nil) and (d.JSONType = jtString) then
        for k := 0 to cnt - 1 do
          if (mx < 0) and (FOption.ComponentModelName(mt, k) = d.AsString) then mx := k;
    end;
  end;
  if (mx < 0) or (mx >= cnt) then Exit;
  if (mt = 'geo') and (FGeos[mx] = nil) then Exit;
  if (mt = TyMatrixCoordSysName) and (FMatrices[mx] = nil) then Exit;
  { the element whose tooltip config names the payload's name }
  d := APayload.Find('name');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  nm := d.AsString;
  if mt = 'geo' then
  begin
    { A GEO REGION: the tooltip config is on the region group
      (resetTooltipForRegion, only where the geo draws no series' data --
      there the group's elements carry the series' datum instead); its
      bounding rect is its compound paths' union -- a path's label is its
      text content, not a child -- and the centre of that is the point }
    grp := FGeos[mx].GroupIndexOf(nm);
    if grp < 0 then Exit;
    any := False;
    u := TyRectF(0, 0, 0, 0);
    for k := 0 to FPaintList.Count - 1 do
    begin
      el := FPaintList.Element(k);
      if (el.Datum.Kind <> ctkGeo) or (el.Datum.ComponentIndex <> mx)
        or (el.Datum.DataIndex <> grp) then Continue;
      if not (el.Shape.Kind in [cskPolygon, cskPolyline]) then Continue;
      b := TyShapeBounds(el.Shape);
      if not any then
      begin
        u := b;
        ADatum := el.Datum;
        AElement := k;
        any := True;
      end
      else
      begin
        if b.Left < u.Left then u.Left := b.Left;
        if b.Top < u.Top then u.Top := b.Top;
        if b.Right > u.Right then u.Right := b.Right;
        if b.Bottom > u.Bottom then u.Bottom := b.Bottom;
      end;
    end;
    if not any then Exit;
    AX := u.Left + (u.Right - u.Left) / 2;
    AY := u.Top + (u.Bottom - u.Top) / 2;
    Exit(True);
  end;
  for k := 0 to FPaintList.Count - 1 do
  begin
    el := FPaintList.Element(k);
    if (el.Datum.Kind <> ctkMatrix) or (el.Datum.ComponentIndex <> mx) then Continue;
    if not MatrixCellOf(el.Datum, m, info) or not info.HasText then Continue;
    if info.TipName <> nm then Continue;
    b := TyShapeBounds(el.Shape);
    AX := b.Left + (b.Right - b.Left) / 2;
    AY := b.Top + (b.Bottom - b.Top) / 2;
    ADatum := el.Datum;
    AElement := k;
    Exit(True);
  end;
end;

procedure TTyAdvanceChart.TipHideVia(AViaListener: Boolean);
begin
  { [F4b] _hide forgets the axis tooltip it kept }
  FTipLastDbc := '';
  { _hide: a hideTip from the view }
  TipDispatch(TJSONObject.Create(['type', 'hideTip', 'from', TipUid]), nil,
    False, AViaListener);
end;

procedure TTyAdvanceChart.TipTryShowEvent(const AEv: TTyTipEvent;
  AViaListener: Boolean);
var
  g, spec: TTyTooltipSpec;
  snap: TTyTipSnap;
  p: TJSONObject;
  s, raw: Integer;
begin
  g := TyTooltipSpecOf(FOption, -1, -1);
  if not g.HasComponent then Exit;
  { [F4b] _lastX / _lastY: so a re-render can show the tip again }
  FTipLastX := AEv.X;
  FTipLastY := AEv.Y;
  snap := Default(TTyTipSnap);
  snap.X := AEv.X;
  snap.Y := AEv.Y;
  snap.PosJson := AEv.PosJson;
  snap.PosDefault := AEv.PosDefault;
  snap.Datum := TyChartNoDatum;
  snap.Element := -1;
  { an axis tooltip: _showAxisTooltip, no event of its own }
  if AEv.HasDbc then
  begin
    snap.Hits := Copy(AEv.Hits, 0, Length(AEv.Hits));
    TipTryShow(snap, g);
    Exit;
  end;
  snap.Datum := AEv.Datum;
  snap.Element := AEv.Element;
  { [F4b] a target, or none: no axis tooltip to keep }
  FTipLastDbc := '';
  { findEventDispatcher: tooltipDisabled on the way up is no dispatcher }
  if CustomTipDisabled(AEv.Element) then
  begin
    TipHideVia(AViaListener);
    Exit;
  end;
  { a component's tooltip config: _showComponentItemTooltip -- whatever the
    trigger says -- and a showTip from the view; a matrix cell's, a geo
    region's }
  if TipIsMatrix(AEv.Datum) or IsGeoDatum(AEv.Datum) or IsAxisTextDatum(AEv.Datum) then
  begin
    TipTryShow(snap, TipSpecOf(snap));
    TipDispatch(TJSONObject.Create(['type', 'showTip', 'from', TipUid]), nil,
      False, AViaListener);
    Exit;
  end;
  { an element with data: _showSeriesItemTooltip -- the cascade's trigger
    must be 'item', else nothing at all (no hide either) }
  if TipTargetValid(AEv.Datum) then
  begin
    spec := TipSpecOf(snap);
    if spec.Trigger <> tttItem then Exit;
    TipTryShow(snap, spec);
    if TipIsMarker(AEv.Datum) then
    begin
      s := AEv.Datum.ComponentIndex;
      raw := AEv.Datum.DataIndex;
    end
    else
    begin
      s := AEv.Datum.SeriesIndex;
      raw := AEv.Datum.RawDataIndex;
      if raw < 0 then raw := AEv.Datum.DataIndex;
    end;
    p := TJSONObject.Create(['type', 'showTip']);
    p.Add('dataIndexInside', AEv.Datum.DataIndex);
    p.Add('dataIndex', raw);
    p.Add('seriesIndex', s);
    p.Add('from', TipUid);
    TipDispatch(p, nil, False, AViaListener);
    Exit;
  end;
  TipHideVia(AViaListener);
end;

procedure TTyAdvanceChart.DoUpdateAxisPointer(APayload: TJSONObject);
var
  via, ok: Boolean;
  trig: string;
  px, py: Double;
  d: TJSONData;
  inp, none_, arr: TJSONArray;
  hits, tips: TTyAxisHitArray;
  order: TTyAxisArray;
  datum: TTyChartDatumRef;
  el, i, k, slot: Integer;
  ev, ax, tip: TJSONObject;
  done: array of Boolean;

  function ModelValue(const AHit: TTyAxisHit): Double;
  begin
    { showValueMap's value: snapped where the axis snaps and the snapped
      value is on it, never on a linked axis }
    Result := AHit.Value;
    if AHit.Spec.Snap and not AHit.Linked and not IsNan(AHit.SnapValue)
      and AHit.Axis.Scale.Contain(AHit.SnapValue) then Result := AHit.SnapValue;
  end;

  procedure Sample(const AHit: TTyAxisHit);
  begin
    slot := AHit.Slots[0];
    ev.Add('seriesIndex', SlotSeriesIndex(slot));
    ev.Add('dataIndexInside', AHit.Rows[0]);
    if (slot >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil) then
      ev.Add('dataIndex', FStores[slot].GetRawIndex(AHit.Rows[0]))
    else
      ev.Add('dataIndex', AHit.Rows[0]);
  end;

begin
  { [R2-I8] an action: each axis' pointer renders (PointerDrawLabelText) }
  Inc(FPtrUpdGen);
  via := FUapListener;
  FUapListener := False;
  hits := nil;
  none_ := nil;
  ev := TJSONObject.Create;
  try
    Inc(FActCycle);
    try
      d := APayload.Find('currTrigger');
      trig := '';
      if (d <> nil) and (d.JSONType = jtString) then trig := d.AsString;
      { the point: x and y, else the sample series' -- findPointFromSeries
        by seriesIndex and dataIndex alone (a dataIndexInside from another
        chart means nothing here) }
      ok := TipPayloadXY(APayload, px, py);
      if not ok then
        ok := TipSeriesPoint(APayload, False, px, py, datum, el)
          and not IsNan(px) and not IsNan(py);
      { axesInfo: a list names the axes, anything else truthy names none }
      d := APayload.Find('axesInfo');
      inp := nil;
      if d is TJSONArray then inp := TJSONArray(d)
      else if JsTruthy(d) then
      begin
        none_ := TJSONArray.Create;
        inp := none_;
      end;
      { shouldHide: a leave, or no point }
      if (trig <> 'leave') and ok then hits := ResolveAxisPointers(px, py, inp);
      { updateModelActually: what is not shown hides }
      FTipHits := hits;
      FOptPtrGone := True;
      FOptPtrBack := nil;
      PtrAnimSync;
      TipInvalidate;
      { the event: the first row a processed axis took (the first pass's,
        then the linked ones'), then the axes shown in the model's order }
      for i := 0 to High(hits) do
        if not hits[i].Linked and (Length(hits[i].Slots) > 0) then
        begin
          Sample(hits[i]);
          Break;
        end;
      if ev.IndexOfName('seriesIndex') < 0 then
        for i := 0 to High(hits) do
          if hits[i].Linked and (Length(hits[i].Slots) > 0) then
          begin
            Sample(hits[i]);
            Break;
          end;
      arr := TJSONArray.Create;
      ev.Add('axesInfo', arr);
      order := TipCollectionOrder;
      SetLength(done, Length(hits));
      for i := 0 to High(done) do done[i] := False;
      for k := 0 to High(order) do
        for i := 0 to High(hits) do
          if not done[i] and (hits[i].Axis = order[k]) then
          begin
            done[i] := True;
            ax := TJSONObject.Create;
            ax.Add('axisDim', hits[i].Axis.Dim);
            ax.Add('axisIndex', hits[i].Axis.ComponentIndex);
            ax.Add('value', TJSONFloatNumber.Create(ModelValue(hits[i])));
            arr.Add(ax);
          end;
      ev.Add('type', 'updateaxispointer');
      { dispatchTooltipActually: a showTip when an axis has something for
        the tooltip, else a hideTip }
      tips := TipAxesHits(hits);
      if (not ok) or (Length(tips) = 0) then
        TipDispatch(TJSONObject.Create(['type', 'hideTip']), nil, False, via)
      else
      begin
        tip := TJSONObject.Create(['type', 'showTip']);
        tip.Add('escapeConnect', True);
        tip.Add('x', TJSONFloatNumber.Create(px));
        tip.Add('y', TJSONFloatNumber.Create(py));
        if APayload.IndexOfName('tooltipOption') >= 0 then
          tip.Add('tooltipOption', APayload.Find('tooltipOption').Clone);
        if APayload.IndexOfName('position') >= 0 then
          tip.Add('position', APayload.Find('position').Clone);
        slot := tips[0].Slots[0];
        tip.Add('dataIndexInside', tips[0].Rows[0]);
        if (slot >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil) then
          tip.Add('dataIndex', FStores[slot].GetRawIndex(tips[0].Rows[0]))
        else
          tip.Add('dataIndex', tips[0].Rows[0]);
        tip.Add('seriesIndex', SlotSeriesIndex(slot));
        tip.Add('dataByCoordSys', TipDbcJson(tips));
        TipDispatch(tip, hits, True, via);
      end;
    finally
      Dec(FActCycle);
      none_.Free;
    end;
    { the action's return is its event }
    EmitPayloadEvent('updateaxispointer', VmJsJson(ev), ev);
  finally
    ev.Free;
  end;
end;

procedure TTyAdvanceChart.DoShowTip(APayload: TJSONObject);
var
  hits: TTyAxisHitArray;
  hasHits: Boolean;
begin
  hits := FActHits.Hits;
  hasHits := FActHits.HasHits;
  FActHits.Hits := nil;
  FActHits.HasHits := False;
  Inc(FActCycle);
  try
    { the timers due fire first -- a view that is there, a show not its own }
    if TyTooltipSpecOf(FOption, -1, -1).HasComponent and not TipFromIs(APayload, TipUid) then
      TipAdvance(TipClock);
    TipManualShow(APayload, hits, hasHits);
  finally
    Dec(FActCycle);
  end;
  EmitPayloadEvent('showtip', CopyWithType(APayload, 'showtip'));
  TipArmTimer;
end;

procedure TTyAdvanceChart.TipManualShow(APayload: TJSONObject;
  const AHits: TTyAxisHitArray; AHasHits: Boolean);
var
  g: TTyTooltipSpec;
  ev: TTyTipEvent;
  d: TJSONData;
  hits: TTyAxisHitArray;
  hasHits, isAxis: Boolean;
  px, py: Double;
  uap: TJSONObject;
  datum: TTyChartDatumRef;
  el, sIdx, raw: Integer;
begin
  hits := AHits;
  hasHits := AHasHits;
  begin
    g := TyTooltipSpecOf(FOption, -1, -1);
    { manuallyShowTip is the view's: no tooltip component, no view; the
      view's own showTip comes back to it and is done }
    if g.HasComponent and not TipFromIs(APayload, TipUid) then
    begin
      ev := TipEventBlank;
      ev.PosJson := TipPositionJson(APayload);
      if TipComponentRef(APayload, ev.Datum, ev.Element, ev.X, ev.Y) then
      begin
        { on the element, the box below it unless placed otherwise }
        ev.PosDefault := True;
        TipTryShowEvent(ev, False);
      end
      else if JsTruthy(APayload.Find('tooltip')) and (APayload.Find('x') <> nil)
        and (APayload.Find('y') <> nil) then
        { a proxy element carrying the payload's own tooltip option: not
          modelled }
      else if JsTruthy(APayload.Find('dataByCoordSys')) then
      begin
        { from axisTrigger: the axes and their rows at the point }
        if not TipPayloadXY(APayload, ev.X, ev.Y) then
        begin
          d := APayload.Find('x');
          if (d <> nil) and (d.JSONType = jtNumber) then ev.X := d.AsFloat;
          d := APayload.Find('y');
          if (d <> nil) and (d.JSONType = jtNumber) then ev.Y := d.AsFloat;
        end;
        d := APayload.Find('dataByCoordSys');
        if not hasHits then
        begin
          if d is TJSONArray then hits := TipHitsOfDbc(TJSONArray(d))
          else hits := nil;
        end;
        ev.Hits := hits;
        ev.HasDbc := (d is TJSONArray) and (d.Count > 0);
        TipTryShowEvent(ev, False);
      end
      else if (APayload.Find('seriesIndex') <> nil)
        and (APayload.Find('seriesIndex').JSONType <> jtNull) then
      begin
        { _manuallyAxisShowTip: an item whose cascade says 'axis' shows the
          axis tooltip through updateAxisPointer at its row }
        isAxis := False;
        d := APayload.Find('dataIndex');
        if (APayload.Find('seriesIndex').JSONType = jtNumber) and (d <> nil)
          and (d.JSONType = jtNumber) then
        begin
          sIdx := Trunc(APayload.Find('seriesIndex').AsFloat);
          raw := Trunc(d.AsFloat);
          if SlotOfSeries(sIdx) >= 0 then
            isAxis := TyTooltipSpecOf(FOption, sIdx, raw).Trigger = tttAxis;
        end;
        if isAxis then
        begin
          uap := TJSONObject.Create(['type', 'updateAxisPointer']);
          uap.Add('seriesIndex', APayload.Find('seriesIndex').Clone);
          uap.Add('dataIndex', d.Clone);
          if APayload.IndexOfName('position') >= 0 then
            uap.Add('position', APayload.Find('position').Clone);
          TipDispatch(uap, nil, False, False);
        end
        else if TipSeriesPoint(APayload, True, px, py, datum, el) then
        begin
          { findPointFromSeries, the target its element (no element: no
            target), the box below it unless placed otherwise }
          ev.X := px;
          ev.Y := py;
          if el >= 0 then
          begin
            ev.Datum := FPaintList.Element(el).Datum;
            ev.Element := el;
          end;
          ev.PosDefault := True;
          TipTryShowEvent(ev, False);
        end;
      end
      else if (APayload.Find('x') <> nil) and (APayload.Find('x').JSONType <> jtNull)
        and (APayload.Find('y') <> nil) and (APayload.Find('y').JSONType <> jtNull) then
      begin
        { a point: updateAxisPointer there, and _tryShow on what is under it }
        uap := TJSONObject.Create(['type', 'updateAxisPointer']);
        uap.Add('x', APayload.Find('x').Clone);
        uap.Add('y', APayload.Find('y').Clone);
        TipDispatch(uap, nil, False, False);
        TipPayloadXY(APayload, ev.X, ev.Y);
        if not (IsNan(ev.X) or IsNan(ev.Y)) then
        begin
          datum := HitTestAt(Round(ev.X), Round(ev.Y), el);
          ev.Datum := datum;
          ev.Element := el;
        end;
        TipTryShowEvent(ev, False);
      end;
      TipInvalidate;
    end;
  end;
end;

procedure TTyAdvanceChart.DoHideTip(APayload: TJSONObject);
var g: TTyTooltipSpec;
begin
  Inc(FActCycle);
  try
    g := TyTooltipSpecOf(FOption, -1, -1);
    if g.HasComponent then
    begin
      TipAdvance(TipClock);
      { hideLater(hideDelay); then _hide unless the view sent it }
      TipHide(g);
      { [F4b] _lastX = _lastY = _lastDataByCoordSys = null: nothing for a
        re-render to keep }
      FTipLastX := NaN;
      FTipLastY := NaN;
      FTipLastDbc := '';
      if not TipFromIs(APayload, TipUid) then TipHideVia(False);
      TipInvalidate;
    end;
  finally
    Dec(FActCycle);
  end;
  EmitPayloadEvent('hidetip', CopyWithType(APayload, 'hidetip'));
  TipArmTimer;
end;

procedure TTyAdvanceChart.TipDropDisplay;
begin
  FTipFrozenHas := False;
  FTipShown := False;
  FTipShowFlag := False;
  FTipShowAt := NaN;
  FTipHideAt := NaN;
  FTipKeepAt := NaN;
  FTipSnap := Default(TTyTipSnap);
  FTipSnap.Datum := TyChartNoDatum;
  FTipSnap.Element := -1;
  FTipPend := FTipSnap;
  if FTipTimer <> nil then FTipTimer.Enabled := False;
end;

procedure TTyAdvanceChart.TipReset;
begin
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  { [F4b] A RE-RENDER IS NOT A HIDE. TooltipView.render resets its group,
    not its content: the box stays up as it was -- alwaysShowContent or
    not -- and _keepShow shows the tip again at the last point a tick
    later. The snapshots lose their pointers into the build here (it is
    about to be rebuilt), not their meaning. }
  TipFreeze;
  TipRendered;
end;

procedure TTyAdvanceChart.TipResetQuiet;
begin
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  { the build is about to be new: the snapshots lose their pointers into
    it -- and the view does not render, so nothing is kept for a tick
    later and the last dataByCoordSys stays }
  TipFreeze;
end;

procedure TTyAdvanceChart.TipForget;
begin
  TipDropDisplay;
  FTipLastX := NaN;
  FTipLastY := NaN;
  FTipLastDbc := '';
  FTipKeepPtr := nil;
  FTipKeepPtrDue := False;
  { the hits point into a build about to be freed: never kept }
  FTipHits := nil;
end;

procedure TTyAdvanceChart.TipFreeze;

  procedure Freeze(var ASnap: TTyTipSnap; AShown: Boolean);
  var
    tips: TTyAxisHitArray;
    i, n: Integer;
    arr: TJSONArray;
  begin
    { a show since the last paint: setContent and _updatePosition ran at
      the show upstream -- the box is laid out now, on the build it was
      shown on, before it is held }
    if AShown and not ASnap.Frozen and (FTipPaintGen <> FTipShowGen) then TipLayoutNow;
    { the box where the last paint put it: held there until a show places
      it again (the content element keeps its position) }
    if AShown and not ASnap.Frozen and TyRectFIsValid(FTipBox) then
    begin
      ASnap.Frozen := True;
      ASnap.FrozenX := FTipBox.Left;
      ASnap.FrozenY := FTipBox.Top;
      { [R2-E] and what it said: the content stays the last show's }
      FTipFrozenHas := FTipLastHas;
      FTipFrozenSpec := FTipLastSpec;
      FTipFrozenInk := FTipLastInk;
      FTipFrozenLines := FTipLastLines;
      FTipFrozenOnAxis := FTipLastOnAxis;
      FTipFrozenFmt := FTipLastFmt;
      FTipFrozenBorder := FTipLastBorder;
    end;
    ASnap.Stale := True;
    ASnap.Element := -1;
    if Length(ASnap.Hits) = 0 then Exit;
    { the tooltip's axes, as a dataByCoordSys: never a cross arm }
    tips := nil;
    for i := 0 to High(ASnap.Hits) do
      if not ASnap.Hits[i].NoTip and (ASnap.Hits[i].Axis <> nil) then
      begin
        n := Length(tips);
        SetLength(tips, n + 1);
        tips[n] := ASnap.Hits[i];
      end;
    arr := TipDbcJson(tips);
    try
      ASnap.DbcJson := arr.AsJSON;
    finally
      arr.Free;
    end;
    ASnap.Hits := nil;
    ASnap.Stale := True;
  end;

begin
  if FOption = nil then Exit;
  Freeze(FTipSnap, FTipShown);
  Freeze(FTipPend, False);
end;

procedure TTyAdvanceChart.TipLayoutNow;
var
  P: TTyPainter;
  bmp: TBGRABitmap;
  R: TRect;
  m: ITyTextMeasurer;
begin
  if (FLastPPI <= 0) or (FBuild = nil) or (csDesigning in ComponentState) then Exit;
  { the paint's local rect, which the layout was made on }
  R := Rect(Round(FLastRect.Left), Round(FLastRect.Top), Round(FLastRect.Right),
    Round(FLastRect.Bottom));
  if (R.Right <= 0) or (R.Bottom <= 0) then Exit;
  m := NewTextMeasurer(FLastPPI);
  bmp := TBGRABitmap.Create(R.Right, R.Bottom);
  P := TTyPainter.Create;
  try
    P.BeginPaintOn(nil, R, FLastPPI, bmp);
    PaintTooltip(P, R, FLastPPI, m);
    P.EndPaint;
  finally
    P.Free;
    bmp.Free;
  end;
end;

procedure TTyAdvanceChart.TipRendered;
var g: TTyTooltipSpec;
begin
  if (FOption = nil) or (csDesigning in ComponentState) then Exit;
  g := TyTooltipSpecOf(FOption, -1, -1);
  { no tooltip component, no view to render }
  if not g.HasComponent then Exit;
  { TooltipRichContent.update: under alwaysShowContent _moveIfResized puts
    the box at its ratios of the view again -- (y / h) * h, which need not
    be y }
  if g.AlwaysShowContent and FTipSnap.Frozen and (ClientWidth > 0)
    and (ClientHeight > 0) then
  begin
    FTipSnap.FrozenX := (FTipSnap.FrozenX / ClientWidth) * ClientWidth;
    FTipSnap.FrozenY := (FTipSnap.FrozenY / ClientHeight) * ClientHeight;
  end;
  { _lastDataByCoordSys is the axis tooltip's only }
  if g.Trigger <> tttAxis then FTipLastDbc := '';
  { try to keep the tooltip shown when refreshing -- not when the API
    drives it alone ('none'), nor under exactly 'click' }
  if IsNan(FTipLastX) or IsNan(FTipLastY) or (g.TriggerOn = 'none')
    or (g.TriggerOn = 'click') then Exit;
  { clearTimeout(_refreshUpdateTimeout); setTimeout(...) with no delay }
  FTipKeepAt := TipClock;
  Inc(FTipSeq);
  FTipKeepSeq := FTipSeq;
  TipArmTimer;
end;

procedure TTyAdvanceChart.TipSnapRefresh;

  procedure Refresh(var ASnap: TTyTipSnap);
  var
    d: TJSONData;
    nLine, nCol, slot, row, el: Integer;
  begin
    if not ASnap.Stale then Exit;
    if ASnap.DbcJson <> '' then
    begin
      d := nil;
      if not TyJsonNestingExceeds(ASnap.DbcJson, TyOptionMaxNesting, nLine, nCol) then
        try
          d := GetJSON(ASnap.DbcJson);
        except
          d := nil;
        end;
      try
        if d is TJSONArray then ASnap.Hits := TipHitsOfDbc(TJSONArray(d), True);
      finally
        d.Free;
      end;
    end
    else if TyChartDatumValid(ASnap.Datum) and (ASnap.Datum.RawDataIndex >= 0) then
    begin
      { a series item: its row again by its raw index }
      slot := SlotOfSeries(ASnap.Datum.SeriesIndex);
      if (slot >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil) then
      begin
        row := FStores[slot].IndexOfRawIndex(ASnap.Datum.RawDataIndex);
        if row >= 0 then ASnap.Datum.DataIndex := row;
      end;
    end;
    { a series item's element (its dispatcher): the one the list now holds
      for that row }
    if (ASnap.Element < 0) and (Length(ASnap.Hits) = 0) and (FPaintList <> nil)
      and FPaintListValid and (ASnap.Datum.Kind = ctkSeries) and not ASnap.Datum.IsEdge
      and TyChartDatumValid(ASnap.Datum) then
    begin
      el := FPaintList.IndexOfDatum(ASnap.Datum.SeriesIndex, ASnap.Datum.DataIndex);
      ASnap.Element := el;
    end;
    ASnap.Stale := False;
  end;

begin
  { only against a build that stands }
  if FDirty or (FBuild = nil) then Exit;
  Refresh(FTipSnap);
  Refresh(FTipPend);
end;

function TTyAdvanceChart.GetTipSnapShown: TTyTipSnap;
begin
  TipSnapRefresh;
  Result := FTipSnap;
end;

procedure TTyAdvanceChart.TipKeepPointer;
var
  i, k, n: Integer;
  kp: TTyPtrKeep;
begin
  if Length(FTipHits) = 0 then Exit;
  FTipKeepPtr := nil;
  for i := 0 to High(FTipHits) do
  begin
    if FTipHits[i].Axis = nil then Continue;
    kp := Default(TTyPtrKeep);
    kp.Dim := FTipHits[i].Axis.Dim;
    kp.Index := FTipHits[i].Axis.ComponentIndex;
    kp.Cross := FTipHits[i].Cross;
    kp.NoTip := FTipHits[i].NoTip;
    kp.Linked := FTipHits[i].Linked;
    kp.Value := FTipHits[i].Value;
    kp.SnapValue := FTipHits[i].SnapValue;
    SetLength(kp.Series, Length(FTipHits[i].Slots));
    SetLength(kp.Rows, Length(FTipHits[i].Slots));
    for k := 0 to High(FTipHits[i].Slots) do
    begin
      kp.Series[k] := SlotSeriesIndex(FTipHits[i].Slots[k]);
      kp.Rows[k] := FTipHits[i].Rows[k];
    end;
    n := Length(FTipKeepPtr);
    SetLength(FTipKeepPtr, n + 1);
    FTipKeepPtr[n] := kp;
  end;
  FTipKeepPtrDue := Length(FTipKeepPtr) > 0;
end;

procedure TTyAdvanceChart.TipKeepRestore;
var
  i, k, n, slot: Integer;
  hit: TTyAxisHit;
  ax: TTyAxis;
  plot: TTyRectF;
  pol: TTyPolar;
  sgl: TTySingle;
  infos: TTyPtrAxisInfoArray;
  m: Integer;
begin
  if not FTipKeepPtrDue then Exit;
  FTipKeepPtrDue := False;
  if (FOption = nil) or (FBuild = nil) then
  begin
    FTipKeepPtr := nil;
    Exit;
  end;
  FTipHits := nil;
  { the axes the new models collect a pointer on (collectAxesInfo): a
    setOption that made the tooltip an item one, with no cross and no axis
    of its own show, took the pointers with their axisInfo
    [Revised in R2-I7: the tooltip's gate alone.] }
  infos := PtrCollect;
  for i := 0 to High(FTipKeepPtr) do
  begin
    ax := TipAxisAt(FTipKeepPtr[i].Dim, FTipKeepPtr[i].Index, plot, pol, sgl);
    if ax = nil then Continue;
    m := PtrInfoOf(infos, ax);
    if m < 0 then Continue;
    hit := Default(TTyAxisHit);
    hit.Axis := ax;
    hit.Plot := plot;
    hit.Polar := pol;
    hit.Single := sgl;
    { [R2-I7] the new axisInfo's model and its trigger }
    hit.Cross := infos[m].CrossArm;
    hit.NoTip := not infos[m].TriggerTooltip;
    hit.Linked := FTipKeepPtr[i].Linked;
    hit.Spec := infos[m].Spec;
    hit.Value := FTipKeepPtr[i].Value;
    hit.SnapValue := FTipKeepPtr[i].SnapValue;
    { seriesDataIndices as the model holds them: the rows that are still
      there }
    for k := 0 to High(FTipKeepPtr[i].Series) do
    begin
      slot := SlotOfSeries(FTipKeepPtr[i].Series[k]);
      if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil)
        or (FTipKeepPtr[i].Rows[k] < 0)
        or (FTipKeepPtr[i].Rows[k] >= FStores[slot].Count) then Continue;
      n := Length(hit.Slots);
      SetLength(hit.Slots, n + 1);
      SetLength(hit.Rows, n + 1);
      hit.Slots[n] := slot;
      hit.Rows[n] := FTipKeepPtr[i].Rows[k];
    end;
    n := Length(FTipHits);
    SetLength(FTipHits, n + 1);
    FTipHits[n] := hit;
  end;
  FTipKeepPtr := nil;
end;

procedure TTyAdvanceChart.TipKeepFire;
var
  p: TJSONObject;
  d: TJSONData;
  nLine, nCol: Integer;
begin
  { manuallyShowTip(tooltipModel, ecModel, api, payload) with the payload
    x: _lastX, y: _lastY, dataByCoordSys: _lastDataByCoordSys -- the view's
    method, called
    straight from the timeout: what it dispatches is dispatched at once }
  if IsNan(FTipLastX) or IsNan(FTipLastY) or (FOption = nil) then Exit;
  p := TJSONObject.Create;
  try
    p.Add('x', TJSONFloatNumber.Create(FTipLastX));
    p.Add('y', TJSONFloatNumber.Create(FTipLastY));
    if FTipLastDbc <> '' then
    begin
      d := nil;
      if not TyJsonNestingExceeds(FTipLastDbc, TyOptionMaxNesting, nLine, nCol) then
        try
          d := GetJSON(FTipLastDbc);
        except
          d := nil;
        end;
      if d <> nil then p.Add('dataByCoordSys', d);
    end;
    TipManualShow(p, nil, False);
  finally
    p.Free;
  end;
  TipInvalidate;
end;

procedure TTyAdvanceChart.TooltipContentSize(var AW, AH: Double);
begin
end;

function TTyAdvanceChart.OptionPointerHits: TTyAxisHitArray;
var
  g, c, k: Integer;
  gb: TTyGridBuild;
  cart: TTyCartesian2D;
  infos: TTyPtrAxisInfoArray;
  seen: array of TTyAxis;

  function Seen_(AAxis: TTyAxis): Boolean;
  var j: Integer;
  begin
    for j := 0 to High(seen) do
      if seen[j] = AAxis then Exit(True);
    SetLength(seen, Length(seen) + 1);
    seen[High(seen)] := AAxis;
    Result := False;
  end;

  { one axis: its own status 'show' with a value, through its scale's
    parse [R2-E: an ordinal's name its ordinal and a number rounded, a
    time's date string parsed (a number rounded), a value's string as `+`
    reads it] }
  procedure TryAxis(AAxis, ABase: TTyAxis; const APlot: TTyRectF;
    APolar: TTyPolar; ASingle: TTySingle);
  var
    node, ap, d, st: TJSONData;
    isCat: Boolean;
    v, ms: Double;
    n, m: Integer;
    hit: TTyAxisHit;
  begin
    if (AAxis = nil) or Seen_(AAxis) then Exit;
    { a pointer event rewrote every status: back only where a setOption
      wrote one since [R2-E] }
    if FOptPtrGone and not OptPtrIsBack(AAxis.MainType, AAxis.ComponentIndex) then Exit;
    node := FOption.ComponentAt(AAxis.MainType, AAxis.ComponentIndex);
    if not (node is TJSONObject) then Exit;
    ap := TJSONObject(node).Find('axisPointer');
    if not (ap is TJSONObject) then Exit;
    st := TJSONObject(ap).Find('status');
    if (st = nil) or (st.JSONType <> jtString) or (st.AsString <> 'show') then Exit;
    d := TJSONObject(ap).Find('value');
    if (d = nil) or not (d.JSONType in [jtNumber, jtString]) then Exit;
    { [R2-I7] an axis the axisPointer model collected (collectAxesInfo: its
      own show, or the tooltip's) -- AxisView asks its axisInfo
      [Revised in R2-I7: its own boolean show, or the base axis of an
      axis-triggered tooltip.] }
    m := PtrInfoOf(infos, AAxis);
    if m < 0 then Exit;
    isCat := AAxis.Scale is TTyOrdinalScale;
    v := NaN;
    if isCat then
    begin
      if d.JSONType = jtNumber then v := TyJsRound(d.AsFloat)
      else if AAxis.Categories <> nil then
      begin
        n := AAxis.Categories.GetOrdinal(d.AsString);
        if n >= 0 then v := n;
      end;
    end
    else if AAxis.Scale is TTyTimeScale then
    begin
      if d.JSONType = jtNumber then v := TyJsRound(d.AsFloat)
      else if TyParseDateMs(d.AsString, ms, False) then v := ms;
    end
    else if d.JSONType = jtNumber then v := d.AsFloat
    else if d.AsString <> '' then v := TyJsToNumber(d.AsString);
    if IsNan(v) or IsInfinite(v) then Exit;
    hit := Default(TTyAxisHit);
    hit.Axis := AAxis;
    hit.Plot := APlot;
    hit.Polar := APolar;
    hit.Single := ASingle;
    hit.Spec := infos[m].Spec;
    hit.Cross := infos[m].CrossArm;
    hit.NoTip := not infos[m].TriggerTooltip;
    hit.Value := v;
    hit.SnapValue := v;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := hit;
  end;

begin
  { BaseAxisPointer.render reads `status` and `value` off the axis'
    axisPointer model: an axis that HAS a pointer (its own `show: true`, or
    the base axis of an axis-triggered tooltip) and whose option writes
    status 'show' with a value is drawn there before anything moves. Its
    seriesDataIndices are empty -- no series data for a label formatter.
    [R2-E] Every coordinate system's axes: a grid's, a polar's, a single
    axis. }
  Result := nil;
  seen := nil;
  if (FBuild = nil) or (FOption = nil) then Exit;
  if FOptPtrGone and (Length(FOptPtrBack) = 0) then Exit;
  infos := PtrCollect;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    for c := 0 to gb.CartesianCount - 1 do
    begin
      cart := gb.CartesianByIndex(c);
      if cart = nil then Continue;
      for k := 0 to 1 do
        if k = 0 then TryAxis(cart.AxisByDim('x'), cart.GetBaseAxis, gb.PlotRect, nil, nil)
        else TryAxis(cart.AxisByDim('y'), cart.GetBaseAxis, gb.PlotRect, nil, nil);
    end;
  end;
  for g := 0 to High(FPolars) do
    if FPolars[g] <> nil then
    begin
      TryAxis(FPolars[g].AxisByDim('radius'), FPolars[g].BaseAxis, Default(TTyRectF), FPolars[g], nil);
      TryAxis(FPolars[g].AxisByDim('angle'), FPolars[g].BaseAxis, Default(TTyRectF), FPolars[g], nil);
    end;
  for g := 0 to High(FSingles) do
    if FSingles[g] <> nil then
      TryAxis(FSingles[g].Axis, FSingles[g].Axis, FSingles[g].GetRect, nil, FSingles[g]);
end;

{ [R2-E] an axis a merged setOption wrote `axisPointer.status` on since a
  pointer event rewrote every status }
function TTyAdvanceChart.OptPtrIsBack(const AMainType: string; AIndex: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(FOptPtrBack) do
    if FOptPtrBack[i] = AMainType + '#' + IntToStr(AIndex) then Exit(True);
end;

{ [R2-E] the merge's piece: every axis component it writes a status on
  (an object is index 0, a list each its own) takes the option's status
  again -- the rest keep what the pointer wrote }
procedure TTyAdvanceChart.OptPtrTakePiece(APiece: TJSONData);
const
  cMain: array[0..4] of string = ('xAxis', 'yAxis', 'angleAxis', 'radiusAxis', 'singleAxis');
var
  m, i: Integer;
  d: TJSONData;

  procedure Take(AItem: TJSONData; AIndex: Integer);
  var ap: TJSONData; key: string; n: Integer;
  begin
    if not (AItem is TJSONObject) then Exit;
    ap := TJSONObject(AItem).Find('axisPointer');
    if not (ap is TJSONObject) or (TJSONObject(ap).Find('status') = nil) then Exit;
    key := cMain[m] + '#' + IntToStr(AIndex);
    if OptPtrIsBack(cMain[m], AIndex) then Exit;
    n := Length(FOptPtrBack);
    SetLength(FOptPtrBack, n + 1);
    FOptPtrBack[n] := key;
  end;

begin
  if not FOptPtrGone or not (APiece is TJSONObject) then Exit;
  for m := 0 to High(cMain) do
  begin
    d := TJSONObject(APiece).Find(cMain[m]);
    if d is TJSONArray then
    begin
      for i := 0 to d.Count - 1 do Take(d.Items[i], i);
    end
    else
      Take(d, 0);
  end;
end;

function TTyAdvanceChart.TooltipShown: Boolean;
begin
  Result := FTipShown;
end;

function TTyAdvanceChart.TooltipLines: TTyTooltipLineArray;
begin
  if TyRectFIsValid(FTipBox) then Result := FTipLastLines else Result := nil;
end;

function TTyAdvanceChart.TooltipFormatterText: string;
begin
  Result := FTipFormatterText;
end;

function TTyAdvanceChart.TooltipBorderColour: TTyColor;
begin
  Result := FTipBorderPainted;
end;

function TTyAdvanceChart.TooltipShownWhich: string;
const
  cMk: array[TTyChartTargetKind] of string = ('item', 'markPoint', 'markLine',
    'markArea', 'legend', 'legend', 'legend', 'graphic', 'matrix', 'geo', 'axis');
var block: TTyTooltipBlock;
begin
  Result := '';
  if not FTipShown then Exit;
  TipSnapRefresh;
  if Length(FTipSnap.Hits) > 0 then
  begin
    block := AxisTooltipContent(FTipSnap.Hits, TyTooltipSpecOf(FOption, -1, -1));
    try
      Result := 'axis:';
      if (block <> nil) and (block.BlockCount > 0) then
        Result := Result + block.Blocks[0].Header;
    finally
      block.Free;
    end;
    Exit;
  end;
  { [Batch 148] a geo region: 'geo:<geoIndex>:<name>' }
  if IsGeoDatum(FTipSnap.Datum) then
    Result := 'geo:' + IntToStr(FTipSnap.Datum.ComponentIndex) + ':'
      + FGeos[FTipSnap.Datum.ComponentIndex].GroupName(FTipSnap.Datum.DataIndex)
  else if TipIsMarker(FTipSnap.Datum) or TipIsMatrix(FTipSnap.Datum)
    or IsAxisTextDatum(FTipSnap.Datum) then
    Result := cMk[FTipSnap.Datum.Kind] + ':'
      + IntToStr(FTipSnap.Datum.ComponentIndex) + ':'
      + IntToStr(FTipSnap.Datum.DataIndex)
  else if FTipSnap.Datum.IsEdge then
    Result := 'edge:' + IntToStr(FTipSnap.Datum.SeriesIndex) + ':'
      + IntToStr(FTipSnap.Datum.DataIndex)
  else
    Result := 'item:' + IntToStr(FTipSnap.Datum.SeriesIndex) + ':'
      + IntToStr(FTipSnap.Datum.DataIndex);
end;

function TTyAdvanceChart.TooltipShownDatum: TTyChartDatumRef;
begin
  if FTipShown and (Length(FTipSnap.Hits) = 0) then Result := FTipSnap.Datum
  else Result := TyChartNoDatum;
end;

function TTyAdvanceChart.TooltipAnchor: TPoint;
begin
  if IsNan(FTipSnap.X) or IsNan(FTipSnap.Y) then Result := Point(0, 0)
  else Result := Point(Round(FTipSnap.X), Round(FTipSnap.Y));
end;

function TTyAdvanceChart.TooltipAnchorF: TTyPointF;
begin
  Result := TyPointF(FTipSnap.X, FTipSnap.Y);
end;

function TTyAdvanceChart.TooltipShowFlag: Boolean;
begin
  Result := FTipShowFlag;
end;

function TTyAdvanceChart.TooltipBox: TTyRectF;
begin
  Result := FTipBox;
end;

function TTyAdvanceChart.TooltipTargetRect: TTyRectF;
begin
  Result := FTipRect;
end;

{ ---- the markers' own tooltip [Batch 100] ---- }

function TTyAdvanceChart.MarkerItemOf(const ADatum: TTyChartDatumRef;
  out AKind: TTyMarkerKind; out ABlock: TTyMkBlock; out AItem: Integer): Boolean;
var k, q: Integer;
begin
  Result := False;
  AItem := -1;
  ABlock := Default(TTyMkBlock);
  case ADatum.Kind of
    ctkMarkPoint: AKind := mkPoint;
    ctkMarkLine: AKind := mkLine;
    ctkMarkArea: AKind := mkArea;
  else
    AKind := mkPoint;
    Exit;
  end;
  for k := 0 to High(FMarkers) do
    if FMarkers[k].SeriesIndex = ADatum.ComponentIndex then
    begin
      ABlock := FMarkers[k].Blocks[AKind];
      case AKind of
        mkPoint:
          for q := 0 to High(ABlock.Points) do
            if ABlock.Points[q].DataIndex = ADatum.DataIndex then
            begin
              AItem := q;
              Exit(True);
            end;
        mkLine:
          for q := 0 to High(ABlock.Lines) do
            if ABlock.Lines[q].DataIndex = ADatum.DataIndex then
            begin
              AItem := q;
              Exit(True);
            end;
        mkArea:
          for q := 0 to High(ABlock.Areas) do
            if ABlock.Areas[q].DataIndex = ADatum.DataIndex then
            begin
              AItem := q;
              Exit(True);
            end;
      end;
      Exit;
    end;
end;

function MkValName(const AV: TTyMkVal): string;
begin
  case AV.Kind of
    mvkStr: Result := AV.Str;
    mvkNum: Result := TyJsNumberToString(AV.Num);
  else
    Result := '';
  end;
end;

procedure TTyAdvanceChart.MarkerNameValue(const ADatum: TTyChartDatumRef;
  out AName: string; out AValue: TTyMkVal);
var
  kind: TTyMarkerKind;
  blk: TTyMkBlock;
  it, k, n: Integer;
  e: TTyMkEnd;
  ax: TTyAxis;
  v: TTyMkVal;
  d: TJSONData;
begin
  AName := '';
  AValue := TyMkUndef;
  if not MarkerItemOf(ADatum, kind, blk, it) then Exit;
  case kind of
    mkPoint:
      begin
        e := blk.Points[it].E;
        AValue := e.Value;
        AName := MkValName(e.Name);
        { getName: the item's own name, else the data's NAME DIMENSION --
          its first category coordinate, read through the axis' categories
          (a coord ['B', 70] is named 'B') }
        if not (e.Name.Kind in [mvkStr, mvkNum]) then
          for k := 0 to 1 do
          begin
            if k = 0 then ax := blk.XAxis else ax := blk.YAxis;
            if (ax = nil) or (ax.Categories = nil) then Continue;
            v := e.Values[k];
            if (v.Kind = mvkStr) and (ax.Categories.GetOrdinal(v.Str) >= 0) then
              AName := v.Str
            else if (v.Kind = mvkNum) and not IsNan(v.Num)
              and not IsInfinite(v.Num) then
            begin
              n := Round(v.Num);
              if (n = v.Num) and (n >= 0) and (n < ax.Categories.Count) then
                AName := ax.Categories.CategoryAt(n);
            end;
            Break;
          end;
      end;
    mkLine:
      begin
        AName := MkValName(blk.Lines[it].LineName);
        AValue := blk.Lines[it].LineValue;
      end;
    mkArea:
      begin
        AName := MkValName(blk.Areas[it].Name);
        { the merged item's value: the first corner's, else the second's }
        d := nil;
        if blk.Areas[it].LtSrc <> nil then d := blk.Areas[it].LtSrc.Find('value');
        if (d = nil) and (blk.Areas[it].RbSrc <> nil) then
          d := blk.Areas[it].RbSrc.Find('value');
        if d <> nil then AValue := TyMkOf(d);
      end;
  end;
end;

function TTyAdvanceChart.MarkerTooltipContent(
  const ADatum: TTyChartDatumRef): TTyTooltipBlock;
var
  nm, header, valueText: string;
  v: TTyMkVal;
  noValue: Boolean;
begin
  MarkerNameValue(ADatum, nm, v);
  { MarkerModel.formatTooltip: a section headed by the marker model's name
    -- its HOST's model name, an auto name included, and no noHeader: a
    blank one reads '-' -- holding one marker-less row }
  header := SeriesModelName(ADatum.ComponentIndex);
  if Trim(header) = '' then header := '-';
  noValue := v.Kind in [mvkUndef, mvkNull];
  case v.Kind of
    mvkNum: valueText := TyReadableCell(TyDataNum(v.Num), ddtFloat);
    mvkStr: valueText := TyReadableCell(TyDataText(v.Str), ddtFloat);
  else
    valueText := '-';
  end;
  { noName is `!itemName`; any other name goes through makeValueReadable }
  if nm <> '' then nm := TipRowName(nm);
  Result := TTyTooltipBlock.CreateSection(header, False);
  Result.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, nm, nm = '',
    valueText, noValue));
end;

function TTyAdvanceChart.MarkerTooltipParams(
  const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
var
  nm: string;
  v: TTyMkVal;
  kind: TTyMarkerKind;
  blk: TTyMkBlock;
  it, slot: Integer;
begin
  Result := TyChartBlankParams;
  MarkerNameValue(ADatum, nm, v);
  if not MarkerItemOf(ADatum, kind, blk, it) then
    case ADatum.Kind of
      ctkMarkLine: kind := mkLine;
      ctkMarkArea: kind := mkArea;
    else
      kind := mkPoint;
    end;
  { MarkerModel.getDataParams: the marker's own, with the HOST's series
    fields }
  Result.ComponentType := TyMarkerKey[kind];
  Result.SeriesIndex := ADatum.ComponentIndex;
  slot := SlotOfSeries(ADatum.ComponentIndex);
  if slot >= 0 then Result.SeriesType := FBindings[slot].SeriesType;
  Result.SeriesName := SeriesModelName(ADatum.ComponentIndex);
  Result.SeriesId := SeriesIdOf(FOption, ADatum.ComponentIndex);
  Result.DataIndex := ADatum.DataIndex;
  Result.RawDataIndex := ADatum.DataIndex;
  Result.Name := nm;
  { the colour the box's border takes: one answer, DatumColour's }
  Result.Color := DatumColour(ADatum);
  case v.Kind of
    mvkNum:
      begin
        SetLength(Result.Values, 1);
        Result.Values[0] := v.Num;
        Result.ValueText := TyJsNumberToString(v.Num);
      end;
    mvkStr:
      begin
        Result.Raw.Shape := rshScalar;
        Result.Raw.Scalar := TyDataText(v.Str);
        Result.ValueText := v.Str;
      end;
  else
    Result.Raw.Shape := rshAbsent;
  end;
end;

function TTyAdvanceChart.MarkerColour(const ADatum: TTyChartDatumRef): TTyChartColor;
var
  kind: TTyMarkerKind;
  blk: TTyMkBlock;
  it, q: Integer;
  c: TTyChartColor;
  pp: TTyMkPointPicArray;
  lp: TTyMkLinePicArray;
  ap: TTyMkAreaPicArray;
begin
  Result := 0;
  if not MarkerItemOf(ADatum, kind, blk, it) then Exit;
  case kind of
    mkPoint:
      begin
        pp := MarkPointPictures(ADatum.ComponentIndex);
        for q := 0 to High(pp) do
          if (pp[q].Item = it) and TyTryParseChartColor(pp[q].Fill, c) then
            Exit(c);
      end;
    mkLine:
      begin
        lp := MarkLinePictures(ADatum.ComponentIndex);
        for q := 0 to High(lp) do
          if (lp[q].Item = it) and TyTryParseChartColor(lp[q].Stroke, c) then
            Exit(c);
      end;
    mkArea:
      begin
        ap := MarkAreaPictures(ADatum.ComponentIndex);
        for q := 0 to High(ap) do
          if (ap[q].Item = it) and ap[q].HasFill
            and TyTryParseChartColor(ap[q].Fill, c) then
            Exit(c);
      end;
  end;
end;

{ ---- the hierarchies' tooltip [Batch 100] ---- }

{ a node's `name` as upstream's getName answers it: a string, a number's
  text, or nothing }
function HierItemName(AItem: TJSONData): string;
begin
  Result := TyHierItemName(AItem);
end;

{ JavaScript's String() of an option value, for `source + ' -- ' + target` }
function TipJsString(AData: TJSONData): string;
begin
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtString: Result := AData.AsString;
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNull: Result := 'null';
    jtObject: Result := '[object Object]';
  else
    Result := '';
  end;
end;

{ makeValueReadable of one raw cell, no type }
function TipCellText(AData: TJSONData): string;
begin
  if AData = nil then Exit('-');
  case AData.JSONType of
    jtNumber: Result := TyReadableCell(TyDataNum(AData.AsFloat), ddtFloat);
    jtString: Result := TyReadableCell(TyDataText(AData.AsString), ddtFloat);
    jtBoolean: Result := TyReadableCell(TyDataBool(AData.AsBoolean), ddtFloat);
  else
    Result := '-';
  end;
end;

{ getDataParams of the three series whose rows are nodes [R2-E]:
  SeriesModel's -- the component's type, subtype and index, the series'
  id, the node's name, its dataIndex and value -- and then the series'
  own: a sunburst's and a treemap's treePathInfo (wrapTreePathInfo: from
  the virtual root, named as the series, down to the node; each value
  getRawValue, the value completeTreeValue settled), a sankey node's
  value its layout value when it wrote none, an edge's name `source >
  target` (the edge data's) and its value. False: not one of them. }
function TTyAdvanceChart.HierTipParams(const ADatum: TTyChartDatumRef;
  ASlot: Integer; var AParams: TTyChartCallbackParams): Boolean;
var
  st: string;
  row, k: Integer;
  v: Double;
  d: TJSONData;
  hier: TTyHierarchy;
  vals: TTyDoubleArray;
begin
  Result := False;
  st := FBindings[ASlot].SeriesType;
  row := ADatum.DataIndex;
  hier := Default(TTyHierarchy);
  vals := nil;
  if (st = TySunburstSeriesTypeName) and (ASlot <= High(FSunbursts))
    and FSunbursts[ASlot].Valid then
  begin
    hier := FSunbursts[ASlot].Hier;
    SetLength(vals, Length(FSunbursts[ASlot].Nodes));
    for k := 0 to High(vals) do vals[k] := FSunbursts[ASlot].Nodes[k].Value;
  end
  else if (st = TyTreemapSeriesTypeName) and (ASlot <= High(FTreemaps))
    and FTreemaps[ASlot].Valid then
  begin
    hier := FTreemaps[ASlot].Hier;
    SetLength(vals, Length(FTreemaps[ASlot].Nodes));
    for k := 0 to High(vals) do vals[k] := FTreemaps[ASlot].Nodes[k].Value;
  end
  else if not ((st = TySankeySeriesTypeName) and (ASlot <= High(FSankeys))
    and FSankeys[ASlot].Valid) then
    Exit;
  Result := True;
  AParams.ComponentSubType := st;
  AParams.ComponentIndex := ADatum.SeriesIndex;
  if (FOption <> nil) and (FOption.ComponentAt('series', ADatum.SeriesIndex) is TJSONObject) then
  begin
    d := TJSONObject(FOption.ComponentAt('series', ADatum.SeriesIndex)).Find('id');
    if (d <> nil) and (d.JSONType = jtString) then AParams.SeriesId := d.AsString
    else if (d <> nil) and (d.JSONType = jtNumber) then
      AParams.SeriesId := TyJsNumberToString(d.AsFloat);
  end;
  v := NaN;
  if st = TySankeySeriesTypeName then
  begin
    if ADatum.IsEdge then
    begin
      AParams.DataType := 'edge';
      if (row < 0) or (row > High(FSankeys[ASlot].Edges)) then Exit;
      AParams.Name := FSankeys[ASlot].Edges[row].DataName;
      v := FSankeys[ASlot].Edges[row].Value;
    end
    else
    begin
      AParams.DataType := 'node';
      if (row < 0) or (row > High(FSankeys[ASlot].Nodes)) then Exit;
      AParams.Name := HierItemName(FSankeys[ASlot].Nodes[row].Item);
      { `params.value == null`: the layout value }
      d := nil;
      if FSankeys[ASlot].Nodes[row].Item <> nil then
        d := FSankeys[ASlot].Nodes[row].Item.Find('value');
      if (d <> nil) and (d.JSONType = jtNumber) then v := d.AsFloat
      else v := FSankeys[ASlot].Nodes[row].Value;
    end;
  end
  else
  begin
    if (row < 0) or (row > High(hier.Nodes)) or (row > High(vals)) then Exit;
    if row = 0 then
      AParams.Name := HierItemName(FOption.ComponentAt('series', ADatum.SeriesIndex))
    else
      AParams.Name := HierItemName(hier.Nodes[row].Item);
    v := vals[row];
    { the node and its ancestors, from the virtual root down [R2-J2: the
      one a label's params carry too] }
    AParams.TreePathInfo := TyHierTreePathJson(hier, vals, row,
      HierItemName(FOption.ComponentAt('series', ADatum.SeriesIndex)));
  end;
  SetLength(AParams.Values, 1);
  AParams.Values[0] := v;
  AParams.ValueText := TyChartValueText(v);
end;

function TTyAdvanceChart.HierTooltipContent(const ADatum: TTyChartDatumRef;
  const AColour: TTyChartColor; out ABlock: TTyTooltipBlock): Boolean;
var
  slot, row, k: Integer;
  st, nm, valueText: string;
  item, d: TJSONData;
  v: Double;
  has: Boolean;
begin
  ABlock := nil;
  Result := False;
  if ADatum.SeriesIndex < 0 then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if slot < 0 then Exit;
  row := ADatum.DataIndex;
  st := FBindings[slot].SeriesType;

  { SUNBURST: upstream's default series tooltip -- headed by the series'
    name when it was written, one row with the item marker, the node's
    name and its value (a parent's is the sum completeTreeValue wrote) }
  if (st = TySunburstSeriesTypeName) and (slot <= High(FSunbursts))
    and FSunbursts[slot].Valid then
  begin
    { the virtual root only as the return circle [Batch 115] }
    if (row < 0) or (row > High(FSunbursts[slot].Nodes)) then Exit;
    if (row = 0) and (FSunbursts[slot].ViewRoot = 0) then Exit;
    Result := True;
    nm := SeriesNameOf(ADatum.SeriesIndex);
    if (nm <> '') and (Trim(nm) = '') then nm := '-';
    ABlock := TTyTooltipBlock.CreateSection(nm, False);
    if row = 0 then nm := HierItemName(FOption.ComponentAt('series', ADatum.SeriesIndex))
    else nm := HierItemName(FSunbursts[slot].Hier.Nodes[row].Item);
    v := FSunbursts[slot].Nodes[row].Value;
    ABlock.Add(TTyTooltipBlock.CreateNameValue(ttmItem, AColour, nm, False,
      TyTooltipValueText(v), False));
    Exit;
  end;

  { TREEMAP: one bare nameValue -- no marker, no section; a missing name
    reads '-' (no noName); the value is the raw one, an array's cells joined
    by two spaces, the first being the value completeTreeValue settled }
  if (st = TyTreemapSeriesTypeName) and (slot <= High(FTreemaps))
    and FTreemaps[slot].Valid then
  begin
    { the root's background takes the pointer too, named after the series
      [Batch 115] }
    if (row < 0) or (row > High(FTreemaps[slot].Nodes)) then Exit;
    Result := True;
    if row = 0 then item := FOption.ComponentAt('series', ADatum.SeriesIndex)
    else item := FTreemaps[slot].Hier.Nodes[row].Item;
    nm := TipRowName(HierItemName(item));
    v := FTreemaps[slot].Nodes[row].Value;
    valueText := TyTooltipValueText(v);
    d := nil;
    if item is TJSONObject then d := TJSONObject(item).Find('value');
    if (d <> nil) and (d.JSONType = jtArray) and (d.Count > 1) then
      for k := 1 to d.Count - 1 do
        valueText := valueText + '  ' + TipCellText(d.Items[k]);
    ABlock := TTyTooltipBlock.CreateSection('', True);
    ABlock.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, nm, False,
      valueText, False));
    Exit;
  end;

  { SANKEY: a bare nameValue too. A node: its `name` ('-' without one) and
    its LAYOUT value -- the larger of its own and its flow; a link: the
    written `source -- target` and its value. NaN is no value. }
  if (st = TySankeySeriesTypeName) and (slot <= High(FSankeys))
    and FSankeys[slot].Valid then
  begin
    if ADatum.IsEdge then
    begin
      if (row < 0) or (row > High(FSankeys[slot].Edges)) then Exit;
      item := FSankeys[slot].Edges[row].Item;
      if item is TJSONObject then
        nm := TipJsString(TJSONObject(item).Find('source')) + ' -- '
          + TipJsString(TJSONObject(item).Find('target'))
      else
        nm := 'undefined -- undefined';
      v := FSankeys[slot].Edges[row].Value;
    end
    else
    begin
      if (row < 0) or (row > High(FSankeys[slot].Nodes)) then Exit;
      nm := TipRowName(HierItemName(FSankeys[slot].Nodes[row].Item));
      v := FSankeys[slot].Nodes[row].Value;
    end;
    Result := True;
    ABlock := TTyTooltipBlock.CreateSection('', True);
    ABlock.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, nm, False,
      TyTooltipValueText(v), IsNan(v)));
    Exit;
  end;

  { CHORD: a bare nameValue (ChordSeries.formatTooltip). A node: its name
    ('-' without one) and its value -- the raw one, else the layout's; a
    link: its two nodes' names joined by ' > ' and its own value, none when
    it has none [Batch 120] }
  if (st = TyChordSeriesTypeName) and (slot <= High(FChords))
    and FChords[slot].Valid then
  begin
    if ADatum.IsEdge then
    begin
      row := ADatum.RawDataIndex;
      if (row < 0) or (row > High(FChords[slot].Edges)) then Exit;
      nm := FChords[slot].Nodes[FChords[slot].Edges[row].Source].Name + ' > '
        + FChords[slot].Nodes[FChords[slot].Edges[row].Target].Name;
      has := TyChordEdgeRawValue(FChords[slot], row, v, valueText);
    end
    else
    begin
      row := ADatum.RawDataIndex;
      if (row < 0) or (row > High(FChords[slot].Nodes)) then Exit;
      nm := FChords[slot].Nodes[row].Name;
      has := TyChordNodeValue(FChords[slot], row, v, valueText);
    end;
    { makeValueReadable: a number grouped, a string as it is ('-' blank) }
    if has and not IsNan(v) then valueText := TyTooltipValueText(v)
    else if has and (Trim(valueText) = '') then valueText := '-';
    Result := True;
    ABlock := TTyTooltipBlock.CreateSection('', True);
    ABlock.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, TipRowName(nm), False,
      valueText, not has));
  end;
end;

function TTyAdvanceChart.TipHtmlMode: Boolean;
begin
  Result := TyTooltipRenderModeIsHtml(FOption, FTooltipAutoRichText);
end;

function TTyAdvanceChart.TipContentName(const AName: string): string;
begin
  if TipHtmlMode then Result := TyChartEncodeHtml(AName) else Result := AName;
end;

function TTyAdvanceChart.TooltipHtmlLines(const AHtml: string;
  const AInk: TTyTooltipInk): TTyTooltipLineArray;
var handled: Boolean;
begin
  { THE USER'S HANDLER FIRST, the built-in reading after it -- the rule
    every extension point of this control keeps }
  Result := nil;
  handled := False;
  if Assigned(FOnTooltipHtml) then
    FOnTooltipHtml(Self, AHtml, AInk, Result, handled);
  if not handled then Result := TyTooltipHtmlLines(AHtml, AInk);
end;

procedure TTyAdvanceChart.TipBuildContent(const ASnap: TTyTipSnap;
  out AContent: TTyTipContent);
var
  onAxis: Boolean;
  spec: TTyTooltipSpec;
  ink: TTyTooltipInk;
  block, dflt: TTyTooltipBlock;
  lines: TTyTooltipLineArray;
  params: TTyChartParams;
  tipText, fmtText: string;
  k, m: Integer;
  hasSeries: Boolean;
  { [R2-J3] the formatter's markers: the names its params were handed and
    their colours }
  mkNames: array of string;
  mkColours: array of TTyChartColor;
  snap: TTyTipSnap;
  { [R2-I8] the box reads its text as html; the lines that text gave }
  html, htmlHas: Boolean;
  htmlLines: TTyTooltipLineArray;
begin
  { [R2-I7] _showTooltipContent, ONCE PER SHOW: what was drawn on every
    paint -- the formatter run, the default markup built -- is built here
    when a show sets the box, and a paint draws it
    [Revised in R2-I7: PaintTooltip built it, the formatter running on
    every paint.] }
  AContent := Default(TTyTipContent);
  snap := ASnap;
  onAxis := Length(snap.Hits) > 0;
  if not TipTargetValid(snap.Datum) and not onAxis then Exit;
  { UNDER AN AXIS TRIGGER THERE IS NO CASCADE. Upstream builds the axis
    tooltip's model from the global component and a positioning hint and
    nothing else -- no series level, no data item -- so every option but
    valueFormatter is global there. }
  spec := TipSpecOf(snap);
  if not spec.HasComponent then Exit;
  if not spec.Show or not spec.ShowContent then Exit;
  { AN AXIS HIT OUTRANKS AN ITEM ONE. Upstream routes on the payload's
    SHAPE -- if a coordinate system reported axes, the axis path runs and
    the item trigger is never consulted. }
  if not onAxis and (spec.Trigger <> tttItem) and not IsGeoDatum(snap.Datum)
    and not IsAxisTextDatum(snap.Datum) then Exit;
  ink := TooltipInk(spec);
  mkNames := nil;
  mkColours := nil;
  block := nil;
  html := TipHtmlMode;
  htmlHas := False;
  htmlLines := nil;
  try
    if (not onAxis) and IsGeoDatum(snap.Datum) then
    begin
      { [Batch 148] A GEO REGION'S TEXT: the formatter through formatTpl
        with the component's params, else the content (the name) }
      tipText := GeoTipText(snap.Datum, spec);
      AContent.Fmt := tipText;
      if tipText = '' then Exit;
      if html then
      begin
        htmlLines := TooltipHtmlLines(tipText, ink);
        htmlHas := True;
      end
      else
      begin
        block := TTyTooltipBlock.CreateSection('', True);
        block.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, tipText, False,
          '', True));
      end;
    end
    else if (not onAxis) and IsAxisTextDatum(snap.Datum) then
    begin
      { [F4c] AN AXIS' NAME OR LABEL: its formatter through formatTpl, else
        the content -- the text itself }
      tipText := AxisTipText(snap.Datum, spec);
      AContent.Fmt := tipText;
      if tipText = '' then Exit;
      if html then
      begin
        htmlLines := TooltipHtmlLines(tipText, ink);
        htmlHas := True;
      end
      else
      begin
        block := TTyTooltipBlock.CreateSection('', True);
        block.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, tipText, False,
          '', True));
      end;
    end
    else if spec.HasFormatter then
    begin
      { A FORMATTER REPLACES THE CONTENT, it does not decorate it -- but
        upstream builds the default markup first and then throws it away,
        so a valueFormatter with side effects still runs: the tried show
        built it (TipMarkup), and a show nobody tried builds it here
        [Revised in R2-I7: the default was not built under a formatter.] }
      if not snap.MarkupHas then
      begin
        if onAxis then dflt := AxisTooltipContent(snap.Hits, spec)
        else dflt := TooltipContent(snap.Datum, spec);
        dflt.Free;
      end;
      SetLength(params, 1);
      { A FORMATTER UNDER AN AXIS TRIGGER IS GIVEN EVERY SERIES, in the order
        the sections hold them -- which is what makes `{a1}` and `{c2}` mean
        anything at all. }
      if onAxis then params := AxisTooltipParams(snap.Hits)
      else params[0] := TooltipParams(snap.Datum);
      if Length(params) = 0 then Exit;
      { [R2-J3] params.marker: one marker per series' params, numbered in
        their order (makeTooltipMarker, richText) -- a series' item and a
        marker component's, not a component item's (a geo region's, a
        matrix cell's have no marker) }
      for k := 0 to High(params) do
        if (params[k].ComponentType = 'series') or (params[k].ComponentType = 'markPoint')
          or (params[k].ComponentType = 'markLine') or (params[k].ComponentType = 'markArea') then
        begin
          { [R2-I8] html mode's marker is getTooltipMarker's span, in the
            params' colour -- the html reading draws it as the dot; no
            colour, no marker }
          if html then
          begin
            if params[k].Color <> 0 then
              params[k].Marker := TyTooltipHtmlMarker(
                TyTooltipColourText(params[k].Color), False)
            else
              params[k].Marker := '';
            Continue;
          end;
          params[k].Marker := TyTooltipRichMarker(Length(mkNames));
          SetLength(mkNames, Length(mkNames) + 1);
          SetLength(mkColours, Length(mkNames));
          mkNames[High(mkNames)] := TyTooltipMarkerName(High(mkNames));
          mkColours[High(mkColours)] := params[k].Color;
        end;
      fmtText := spec.Formatter;
      { A TEMPLATE UNDER A TIME AXIS IS A TIME TEMPLATE FIRST: TooltipView
        runs the string through util/time.ts format at the first series'
        axis value before formatTpl sees it -- so `{a}` there is am / pm and
        `{d}` the day, never the series name or the percent. Only an axis
        trigger's params carry an axis type, and only an axis trigger has
        sections to walk: an item tooltip is left alone. [Batch 104] }
      if not TyChartIsHandlerRef(fmtText) then
        for k := 0 to High(snap.Hits) do
        begin
          { params[0] is the first series of the first section that has one }
          hasSeries := False;
          for m := 0 to High(snap.Hits[k].Slots) do
            if (snap.Hits[k].Slots[m] >= 0)
              and (snap.Hits[k].Slots[m] <= High(FBindings)) then hasSeries := True;
          if snap.Hits[k].NoTip or not hasSeries then Continue;
          if (snap.Hits[k].Axis <> nil) and (snap.Hits[k].Axis.Scale is TTyTimeScale) then
            fmtText := TyFormatTime(snap.Hits[k].SnapValue, fmtText,
              TTyTimeScale(snap.Hits[k].Axis.Scale).UTC);
          Break;
        end;
      { a matrix cell's template is formatTpl over its own $vars [Batch 147] }
      { [R2-I8] formatTpl(html, params, TRUE): every value a template takes
        is encodeHTML'd, in both render modes }
      if TipIsMatrix(snap.Datum) and not TyChartIsHandlerRef(fmtText) then
        tipText := MatrixTipText(fmtText, snap.Datum)
      else if not TyChartResolveText(fmtText, params, tipText, True) then
        { A named handler that is not registered says so rather than drawing
          nothing -- TyChartResolveText puts the message in the text. }
        ;
      AContent.Fmt := tipText;
      if Trim(tipText) = '' then Exit;
      if html then
      begin
        { [R2-I8] HTML MODE: the string is innerHTML -- read it as a
          browser would }
        htmlLines := TooltipHtmlLines(tipText, ink);
        htmlHas := True;
      end
      else
      begin
        block := TTyTooltipBlock.CreateSection('', True);
        { THE WHOLE STRING AS ONE NAME. A formatter's output is words, not a
          name/value pair, so it takes the name ink and no gutter -- and with
          neither marker nor name flag set the row is the third case upstream
          has and most ports do not: no marker, no right-alignment. }
        block.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, tipText, False,
          '', True));
      end;
    end
    else if snap.MarkupHas then
    begin
      { the default markup the tried show built }
      AContent.Has := Length(snap.Markup) > 0;
      AContent.Spec := spec;
      AContent.Ink := ink;
      AContent.Lines := snap.Markup;
      AContent.OnAxis := onAxis;
      Exit;
    end
    else if onAxis then
      block := AxisTooltipContent(snap.Hits, spec)
    else
      block := TooltipContent(snap.Datum, spec);
    if htmlHas then
    begin
      AContent.Has := Length(htmlLines) > 0;
      AContent.Spec := spec;
      AContent.Ink := ink;
      AContent.Lines := htmlLines;
      AContent.OnAxis := onAxis;
      Exit;
    end;
    if block = nil then Exit;
    lines := TyTooltipFlatten(block, ink);
    { [R2-J3] the dots a formatter's text names by params.marker }
    TyTooltipSplitMarkers(lines, mkNames, mkColours, ink);
    AContent.Has := Length(lines) > 0;
    AContent.Spec := spec;
    AContent.Ink := ink;
    AContent.Lines := lines;
    AContent.OnAxis := onAxis;
  finally
    block.Free;
  end;
end;

procedure TTyAdvanceChart.PaintTooltip(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  onAxis: Boolean;
  spec: TTyTooltipSpec;
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  st: TTyStyleSet;
  w, h, lineH, gap, cx, cy: Double;
  padL, padT, padR, padB, radius, borderW: Double;
  box: TTyRectF;
  r: TRect;
  i, j, row, lineTop: Integer;
  corners: TTyCorners;
  surface: TTyFill;
  borderCol: TTyColor;
  snap: TTyTipSnap;
  pin: TTyTooltipPlaceIn;
  at: TTyPointF;
  elRect: TTyRectF;
  frozenPic: Boolean;
  pspec: TTyTooltipSpec;
  { [R2-I8] html's lines: a line's own top and height, a rule, a box run }
  lineTopF, hPx, ruleY, bx, by, bw, bh, br: Double;
  k: Integer;
begin
  FTipBox := TyInvalidRectF;
  FTipRect := TyInvalidRectF;
  FTipFormatterText := '';
  FTipBorderPainted := 0;
  { [Batch 100] WHAT IS SHOWN, NOT WHAT IS HOVERED: the box's own state
    decides -- a show waiting out showDelay is not drawn yet, a hide waiting
    out hideDelay still is, at the place and with the content of the show }
  if not FTipShown then Exit;
  { [F4b] a box that outlived a re-render: its axes and element from the
    build standing now }
  TipSnapRefresh;
  snap := FTipSnap;
  onAxis := Length(snap.Hits) > 0;
  { [R2-E] A FROZEN BOX SAYS WHAT IT SAID: TooltipView.render does not
    touch the content element -- a row gone, a value changed, the box keeps
    the last show's text, ink and border until a show sets them again }
  frozenPic := snap.Frozen and FTipFrozenHas;
  if frozenPic then
  begin
    spec := FTipFrozenSpec;
    ink := FTipFrozenInk;
    onAxis := FTipFrozenOnAxis;
    FTipFormatterText := FTipFrozenFmt;
    lines := FTipFrozenLines;
  end
  else
  begin
    { [R2-I7] THE LAST SHOW'S CONTENT: built when the show set it (a show
      whose build was not standing: now, once) }
    if FTipCurDue then
    begin
      FTipCurDue := False;
      TipBuildContent(snap, FTipCur);
    end;
    FTipFormatterText := FTipCur.Fmt;
    if not FTipCur.Has then Exit;
    spec := FTipCur.Spec;
    ink := FTipCur.Ink;
    onAxis := FTipCur.OnAxis;
    lines := FTipCur.Lines;
    { WHERE IT GOES IS THE LAST SHOW'S, what it says may be an earlier
      one's: an axis show whose content did not change is _updatePosition
      alone, under its own model and position (a showTip's `position`) }
    pspec := TipSpecOf(snap);
    spec.Position := pspec.Position;
    spec.PositionHandler := pspec.PositionHandler;
    spec.Align := pspec.Align;
    spec.VerticalAlign := pspec.VerticalAlign;
    spec.Confine := pspec.Confine;
    spec.ConfineSet := pspec.ConfineSet;
  end;

  st := ActiveController.Model.ResolveStyle('TyAdvChartTooltip', StyleClass,
    [tysNormal]);
  { NO BOX WITHOUT A BACKGROUND. A theme that defines no tooltip surface gets
    no tooltip -- never a hard-coded colour, which is the rule the old chart
    already follows and the reason the key lives in the base layer where every
    theme inherits it. }
  if not (tpBackground in st.Present) then Exit;

  begin
    if Length(lines) = 0 then Exit;

    if spec.HasPadding then
    begin
      padL := APainter.ScaleF(spec.PadLeft);
      padT := APainter.ScaleF(spec.PadTop);
      padR := APainter.ScaleF(spec.PadRight);
      padB := APainter.ScaleF(spec.PadBottom);
    end
    else
    begin
      padL := APainter.Scale(st.Padding.Left);
      padT := APainter.Scale(st.Padding.Top);
      padR := APainter.Scale(st.Padding.Right);
      padB := APainter.Scale(st.Padding.Bottom);
    end;

    TyTooltipMeasure(lines, ink, AMeasurer, APPI, padL, padT, padR, padB, w, h);
    TooltipContentSize(w, h);
    if (w <= 0) or (h <= 0) then Exit;

    borderW := st.BorderWidth;
    if spec.HasBorderWidth then borderW := spec.BorderWidthLogical;

    { [Batch 100] WHERE IT GOES: TooltipView._updatePosition -- the option's
      position (a handler's answer read the same way), align, confine -- in
      the control's own coordinates, the pointer of the SHOW and, for an item,
      the element it was over. The gap is the theme's (upstream's 20). }
    gap := APainter.ScaleF(ActiveController.Metric(TyAdvChartTooltipGapVar,
      TyAdvChartTooltipGap));
    pin := Default(TTyTooltipPlaceIn);
    pin.PointX := snap.X - ARect.Left;
    pin.PointY := snap.Y - ARect.Top;
    pin.ContentW := w;
    pin.ContentH := h;
    pin.ViewW := ARect.Right - ARect.Left;
    pin.ViewH := ARect.Bottom - ARect.Top;
    pin.Gap := gap;
    pin.BorderWidth := APainter.ScaleF(borderW);
    pin.IsAxis := onAxis;
    elRect := TyInvalidRectF;
    if (not onAxis) and (FPaintList <> nil) and FPaintListValid
      and (snap.Element >= 0) and (snap.Element < FPaintList.Count) then
      elRect := TipElementRect(snap.Element, APPI);
    if TyRectFIsValid(elRect) then
    begin
      pin.HasRect := True;
      pin.Rect := TyXYWH(elRect.Left - ARect.Left, elRect.Top - ARect.Top,
        elRect.Right - elRect.Left, elRect.Bottom - elRect.Top);
      FTipRect := elRect;
    end;
    { [R2-I7] A POSITION FUNCTION RUNS ONCE PER SHOW (_updatePosition):
      its answer is kept for the paints until the next show
      [Revised in R2-I7: it ran on every paint.] }
    if (spec.PositionHandler <> '') and not snap.Frozen then
    begin
      if FTipPosGen <> FTipShowGen then
      begin
        if onAxis then pin.Params := AxisTooltipParams(snap.Hits)
        else if IsGeoDatum(snap.Datum) then
          pin.Params := TyChartOneParams(GeoTipParams(snap.Datum))
        else if IsAxisTextDatum(snap.Datum) then
          pin.Params := TyChartOneParams(AxisTipParams(snap.Datum))
        else pin.Params := TyChartOneParams(TooltipParams(snap.Datum));
        TyTooltipRunPosition(spec, pin, FTipPosAns);
        FTipPosGen := FTipShowGen;
      end;
      spec.Position := FTipPosAns;
      spec.PositionHandler := '';
    end;
    { [F4b] the box a re-render left up stays where it was until a show
      places it again [R2-E: the position is not asked again] }
    if snap.Frozen then
    begin
      at.X := snap.FrozenX - ARect.Left;
      at.Y := snap.FrozenY - ARect.Top;
    end
    else
      at := TyTooltipPlace(spec, pin);
    box := TyRectF(ARect.Left + at.X, ARect.Top + at.Y,
      ARect.Left + at.X + w, ARect.Top + at.Y + h);
    FTipBox := box;
    r := Rect(Round(box.Left), Round(box.Top),
              Round(box.Right), Round(box.Bottom));

    corners := TyEffectiveCorners(st);
    if spec.HasBorderRadius then
    begin
      radius := spec.BorderRadiusLogical;
      corners.TL := Round(radius);
      corners.TR := corners.TL;
      corners.BR := corners.TL;
      corners.BL := corners.TL;
    end;

    { NOT DrawFrame. That is the CONTROL's frame path and it pushes tpOpacity
      onto the painter, which EndPaint then applies to the WHOLE bitmap -- a
      tooltip style carrying an opacity would fade the entire chart. So the
      box paints its own surface, and a translucent panel has to arrive as an
      alpha-bearing background colour rather than as an opacity. }
    if (tpShadow in st.Present) and (TyAlphaOf(st.ShadowColor) > 0) then
      APainter.DropShadow(r, st.BorderRadius, st.ShadowColor, st.ShadowBlur,
        st.ShadowOffset);
    { THE THEME'S FILL, with only its COLOUR replaced when the option named
      one -- so a skin that made the tooltip a gradient or an image keeps that
      treatment for every chart whose author did not overrule it. }
    surface := st.Background;
    if spec.HasBackground then
    begin
      surface.Kind := tfkSolid;
      surface.Color := TTyColor(spec.Background);
    end;
    APainter.FillBackground(r, surface, corners);

    { THE BORDER IS TINTED WITH THE HOVERED ITEM'S COLOUR, which is the
      signature ECharts 6 look and is easy to miss: the grey token is the
      fallback for an AXIS tooltip, and an item tooltip takes the datum's own
      colour. A written borderColor still wins over both. }
    if frozenPic then borderCol := FTipFrozenBorder
    else if spec.HasBorderColour then borderCol := TTyColor(spec.BorderColour)
    else if not onAxis and not IsGeoDatum(snap.Datum) and not IsAxisTextDatum(snap.Datum)
      and (DatumColour(snap.Datum) <> 0) then
      borderCol := TTyColor(DatumColour(snap.Datum))
    else
      { THE GREY IS THE AXIS TOOLTIP'S ANSWER, not a chart-wide default: a box
        describing several series cannot take one of their colours. }
      borderCol := st.BorderColor;
    FTipBorderPainted := borderCol;
    { [R2-E] what this show says, for a re-render to freeze }
    if not frozenPic then
    begin
      FTipPaintGen := FTipShowGen;
      FTipLastHas := True;
      FTipLastSpec := spec;
      FTipLastInk := ink;
      FTipLastLines := lines;
      FTipLastOnAxis := onAxis;
      FTipLastFmt := FTipFormatterText;
      FTipLastBorder := borderCol;
    end;
    if (borderW > 0) and (TyAlphaOf(borderCol) > 0) then
      APainter.StrokeBorder(r, corners, Round(borderW), borderCol);

    lineH := APainter.ScaleF(ink.LineHeightLogical);
    row := 0;
    for i := 0 to High(lines) do
    begin
      row := row + lines[i].BlankLinesBefore;
      { [R2-I8] html's gaps and taller lines: ExtraTopPx and HPx, nought and
        the line height for the default markup -- the same arithmetic }
      lineTopF := box.Top + padT + row * lineH + lines[i].ExtraTopPx;
      lineTop := Round(lineTopF);
      hPx := lines[i].HPx;
      if hPx <= 0 then hPx := lineH;
      { a block's border: a rule across the content, where it fell }
      for k := 0 to High(lines[i].Rules) do
        if (lines[i].Rules[k].WidthLogical > 0)
          and (TyAlphaOf(TTyColor(lines[i].Rules[k].Colour)) > 0) then
        begin
          ruleY := lineTopF + APainter.ScaleF(lines[i].Rules[k].OffsetLogical);
          APainter.BeginPath;
          APainter.RectPath(box.Left + padL, ruleY, box.Right - padR,
            ruleY + Max(1, APainter.ScaleF(lines[i].Rules[k].WidthLogical)));
          APainter.FillPath(TTyColor(lines[i].Rules[k].Colour));
        end;
      if lines[i].Spacer then Continue;
      for j := 0 to High(lines[i].Runs) do
        if lines[i].Runs[j].Kind = ttrBox then
        begin
          { [R2-I8] an html box -- the marker span: its own size between its
            margins, centred in the line, corners as written (a radius of
            half the side or more is a circle, as CSS clamps it) }
          bw := APainter.ScaleF(lines[i].Runs[j].BoxWLogical);
          bh := APainter.ScaleF(lines[i].Runs[j].BoxHLogical);
          br := APainter.ScaleF(lines[i].Runs[j].BoxRadiusLogical);
          if (bw <= 0) or (bh <= 0)
            or (TyAlphaOf(TTyColor(lines[i].Runs[j].Colour)) = 0) then Continue;
          bx := box.Left + padL + lines[i].Runs[j].X
            + APainter.ScaleF(lines[i].Runs[j].MarginLLogical);
          by := lineTop + hPx / 2 - bh / 2;
          APainter.BeginPath;
          if (Abs(bw - bh) < 1e-9) and (br * 2 >= bw) then
            APainter.CirclePath(bx + bw / 2, by + bh / 2, bw / 2)
          else if br > 0 then
            APainter.RoundRectPath(bx, by, bx + bw, by + bh,
              Min(lines[i].Runs[j].BoxRadiusLogical,
                Min(lines[i].Runs[j].BoxWLogical, lines[i].Runs[j].BoxHLogical) / 2))
          else
            APainter.RectPath(bx, by, bx + bw, by + bh);
          APainter.FillPath(TTyColor(lines[i].Runs[j].Colour));
        end
        else if lines[i].Runs[j].Kind = ttrMarker then
        begin
          cx := box.Left + padL + lines[i].Runs[j].X
                + lines[i].Runs[j].W / 2;
          cy := lineTop + lineH / 2;
          { BeginPath FIRST. CirclePath APPENDS to the canvas' current path,
            it does not start one -- so without this the fill takes in
            whatever the static pass left half-built and paints it in the
            marker's colour. It drew a blue rectangle over a legend label,
            and the pixel test that counts what changed between two frames
            went green on it, because the wrong pixels are still pixels. }
          APainter.BeginPath;
          APainter.CirclePath(cx, cy, lines[i].Runs[j].W / 2);
          APainter.FillPath(TTyColor(lines[i].Runs[j].Colour));
        end
        else
        begin
          { NO ELLIPSIS. The box was measured to fit these exact runs, and
            upstream never wraps or truncates a tooltip in either mode -- its
            width is content-driven and its CSS says `white-space: nowrap`. }
          APainter.DrawText(
            Rect(Round(box.Left + padL + lines[i].Runs[j].X), lineTop,
                 Round(box.Left + padL + lines[i].Runs[j].X
                       + lines[i].Runs[j].W) + 1,
                 Round(lineTop + hPx)),
            TyInkText(lines[i].Runs[j].Text), lines[i].Runs[j].FontName,
            lines[i].Runs[j].FontSizeLogical, lines[i].Runs[j].FontWeight,
            TTyColor(lines[i].Runs[j].Colour), taLeftJustify, tlCenter, False);
        end;
      Inc(row);
    end;
  end;
end;
