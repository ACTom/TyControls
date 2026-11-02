{ Part of tyControls.AdvanceChart (included, not a unit): the series labels -- their
  specs, text measurement and the label layout. Moved out of the unit only to keep it
  readable; what the control is and why it is built the way it is, see the unit header. }

procedure TTyCustomAdvanceChart.ResolveTextDims(const AEnc: TTySeriesEncode;
  AStore: TTyDataStore; const ASource: TTyChartSource);
var
  k, p, best: Integer;
  lab, tip: TTyIntegerArray;
  t: TTyDimType;

  procedure AddSorted(var A: TTyIntegerArray; AValue: Integer);
  var i: Integer;
  begin
    for i := 0 to High(A) do if A[i] = AValue then Exit;
    SetLength(A, Length(A) + 1);
    i := High(A);
    while (i > 0) and (A[i - 1] > AValue) do
    begin
      A[i] := A[i - 1];
      Dec(i);
    end;
    A[i] := AValue;
  end;

begin
  if AStore = nil then Exit;
  { THE LABEL: `encode.label` when it names anything; otherwise the LAST
    coordinate column, by position, whose type a label suits -- neither a
    category nor a time. Upstream's comment: y is what people look at. A
    category-category chart has none, and its label is empty. }
  lab := nil;
  if Length(AEnc.Labels) > 0 then lab := Copy(AEnc.Labels)
  else
  begin
    best := -1;
    for k := 0 to AStore.DimCount - 1 do
    begin
      p := AStore.RawDimPos(k);
      if p < 0 then Continue;
      t := AStore.DimType(k);
      if (t = ddtOrdinal) or (t = ddtTime) then Continue;
      if p > best then best := p;
    end;
    { [spec 255] a key no coordinate system asks for is a coordinate too
      (`value` on a scatter): its dimension may be the last, typed as the
      source declares or guesses it }
    for k := 0 to High(AEnc.Others) do
    begin
      p := AEnc.Others[k];
      if (p >= 0) and (p <= High(ASource.Dims))
        and ((ASource.Dims[p].DimType = 'time') or (ASource.Dims[p].DimType = 'ordinal')) then
        Continue;
      if (p <= High(ASource.Dims)) and (ASource.Dims[p].DimType = '')
        and TySourceDimIsOrdinal(ASource, p) then Continue;
      if p > best then best := p;
    end;
    if best >= 0 then
    begin
      SetLength(lab, 1);
      lab[0] := best;
    end;
  end;
  { THE TOOLTIP: `encode.tooltip`; else the columns a type marks as its
    tooltip -- a candlestick's four values; else the label's.
    [Batch 108: a column the table or the series' `dimensions` NAMED is not
    one of the type's: createDimensions gives a dimension its defaultTooltip
    only with the type's own name, when nobody named it. A boxplot read from
    the transform's ItemName / Low / ... / High says only its High.] }
  tip := nil;
  if Length(AEnc.Tooltip) > 0 then tip := Copy(AEnc.Tooltip)
  else
  begin
    { (an extra entry of an encode list is no column of the type's
      [spec 255]) }
    for k := 0 to AStore.DimCount - 1 do
      if (AStore.DimCoord(k) <> '') and (AStore.RawDimPos(k) >= 0)
        and not TyIsSpreadDim(AStore.DimName(k))
        and (TySourceDimName(ASource, AStore.RawDimPos(k)) = '') then
        AddSorted(tip, AStore.RawDimPos(k));
    if Length(tip) = 0 then tip := Copy(lab);
  end;
  AStore.SetLabelPositions(lab);
  AStore.SetTooltipPositions(tip);
end;

{ A LINE'S END LABEL (LineView._initOrUpdateEndLabel and, for its place
  and words, _endLabelOnDuring at percent 1 -- the call createLineClipPath
  makes to "set to the final frame"): on the last legal point, pushed
  `distance` along the base axis, aligned off it; the value as the words
  ({c} the value, valueAnimation true by default), coloured as the series.
  Its datum is none (the expansion must not take it for a host: it is the
  label), and its tag carries what the clip's during needs.
  NOT HERE: a state's endLabel.show, a rich end label (one run), a step
  line's path (the unstepped one is walked), a line of one point (no run).
  [Batch 92, AN4] }
function TTyCustomAdvanceChart.BuildEndLabel(ASlot: Integer; const AVisual: TTySeriesVisual;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList): Integer;
var
  node, en, d: TJSONData;
  run, el: TTyChartElement;
  i, last, flags, lfi, row: Integer;
  spec: TTyLabelSpec;
  st: TTyEndLabelStep;
  pts: TTyPointFArray;
  cmds: TTyPathCmdArray;
  vals: TTyDoubleArray;
  store: TTyDataStore;
  it: TTyRawItem;
  horiz, inverse, connect, found: Boolean;
  xOrY, dist, dX, dY, x, y, v, w, h: Double;
  tpl, words: string;
  ink, stroke: TTyChartColor;
  strokeW: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  normalShow, anyShow, isFn: Boolean;
  k: Integer;
  stepped: TTyPointFArray;
  turn: TTyStepTurn;
  scale: Double;
  pieces: TTyRtPieceArray;
begin
  Result := 0;
  if (AList = nil) or (AMeasurer = nil) or (ASlot > High(FStores)) then Exit;
  store := FStores[ASlot];
  if store = nil then Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (node is TJSONObject) then Exit;
  { anyStateShowEndLabel: the label is there where any state shows it, and
    hidden at rest unless the normal one does [R5-C: was the normal only] }
  en := TJSONObject(node).Find('endLabel');
  normalShow := (en is TJSONObject) and TyOptTruthy(TJSONObject(en).Find('show'));
  anyShow := normalShow;
  for k := 0 to 2 do
  begin
    case k of
      0: d := TJSONObject(node).Find('emphasis');
      1: d := TJSONObject(node).Find('blur');
    else
      d := TJSONObject(node).Find('select');
    end;
    if d is TJSONObject then
    begin
      d := TJSONObject(d).Find('endLabel');
      if (d is TJSONObject) and TyOptTruthy(TJSONObject(d).Find('show')) then anyShow := True;
    end;
  end;
  if not anyShow then Exit;
  if not (en is TJSONObject) then en := nil;
  { the series' line: its points and its clip }
  found := False;
  run := Default(TTyChartElement);
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = carLineRun)
      and (AList.Element(i).Anim.Series = FBindings[ASlot].SeriesIndex) then
    begin
      run := AList.Element(i);
      found := True;
      Break;
    end;
  if not found then Exit;
  last := TyLastLegalRow(run.Anim.Pts);
  if last < 0 then Exit;
  { the end label's own model over the theme: no series label leaks in;
    distance 8, valueAnimation on (LineSeries' defaults) }
  spec := LabelBaseFor(ASlot);
  spec.Show := True;
  spec.DistanceLogical := 8;
  spec.ValueAnim := True;
  if en <> nil then spec := TyLabelSpecOfNode(TJSONObject(en), nil, spec);
  horiz := (Round(run.Anim.G[5]) and 2) <> 0;
  inverse := (Round(run.Anim.G[5]) and 4) <> 0;
  connect := run.Anim.G[10] <> 0;
  { each row's raw value, a number or none }
  SetLength(vals, store.Count);
  for row := 0 to store.Count - 1 do
  begin
    vals[row] := NaN;
    it := store.RawItem(row);
    { a scalar as it is; an item of several values (or none) the label's
      value dimension -- interpolateRawValues runs over each dimension and
      the default text prints the label's [R5-C: arrays did not count] }
    if it.Shape = rshScalar then
    begin
      if it.Scalar.Kind = dvkNumber then vals[row] := it.Scalar.Num;
    end
    else if (AVisual.LabelValueDim >= 0) and (AVisual.LabelValueDim < store.DimCount) then
      vals[row] := store.Get(AVisual.LabelValueDim, row);
  end;
  { the words: the value's template for the last row, else its text }
  tpl := '';
  if spec.ValueAnim then
    tpl := TyLabelValueTemplate(spec.Formatter, spec.HasFormatter, tldValue,
      store, last, AVisual.SeriesName, AVisual.LabelValueDim,
      FBindings[ASlot].SeriesIndex, 'line', AVisual.Fill);
  words := TyLabelText(spec.Formatter, spec.HasFormatter, tldValue, store, last,
    AVisual.SeriesName, AVisual.LabelValueDim, 0, False,
    FBindings[ASlot].SeriesIndex, 'line', AVisual.Fill);
  { the final frame: the clip's leading edge at rest }
  if inverse then
  begin
    if horiz then xOrY := run.Anim.G[0] else xOrY := run.Anim.G[1] + run.Anim.G[3];
  end
  else if horiz then xOrY := run.Anim.G[0] + run.Anim.G[2]
  else xOrY := run.Anim.G[1];
  SetLength(pts, Length(run.Anim.Pts) div 2);
  for i := 0 to High(pts) do
    pts[i] := TyPointF(run.Anim.Pts[i * 2], run.Anim.Pts[i * 2 + 1]);
  { [R5-C] A STEP LINE's polyline is the stepped one (getPointOn), its
    index range the layout's points }
  stepped := nil;
  if run.Anim.G[7] <> 0 then
  begin
    case Round(run.Anim.G[7]) of
      2: turn := sttMiddle;
      3: turn := sttEnd;
    else
      turn := sttStart;
    end;
    stepped := TyTurnPointsIntoStep(pts, nil, False, horiz, turn, connect);
    cmds := TyPolylinePath(stepped, run.Anim.G[8], run.Anim.Mono, connect);
  end
  else
    cmds := TyPolylinePath(pts, run.Anim.G[8], run.Anim.Mono, connect);
  lfi := 0;
  st := TyEndLabelStep(run.Anim.Pts, cmds, xOrY, horiz, connect, True, lfi);
  if not st.HasPoint then Exit;
  dist := spec.DistanceLogical * APPI / 96;
  if horiz then dX := dist else dX := 0;
  if horiz then dY := 0 else dY := -dist;
  if inverse then
  begin
    dX := dX * -1;
    dY := dY * -1;
  end;
  x := st.X + dX;
  y := st.Y + dY;
  { [R5-C] what a frame needs to word the label again: its spec, its row,
    its value dimension, its ink and alignment, the measurer }
  k := -1;
  for i := 0 to High(FEndLbls) do
    if FEndLbls[i].Series = FBindings[ASlot].SeriesIndex then k := i;
  if k < 0 then
  begin
    k := Length(FEndLbls);
    SetLength(FEndLbls, k + 1);
  end;
  FEndLbls[k].Series := FBindings[ASlot].SeriesIndex;
  FEndLbls[k].Last := last;
  FEndLbls[k].ValueDim := AVisual.LabelValueDim;
  FEndLbls[k].Name := AVisual.SeriesName;
  FEndLbls[k].Spec := spec;
  FEndLbls[k].Ink := AVisual.Fill;
  FEndLbls[k].Scale := APPI / 96;
  FEndLbls[k].Measurer := AMeasurer;
  { [R5-C] a named formatter counts too: called with the value there }
  isFn := spec.ValueAnim and spec.HasFormatter and TyChartIsHandlerRef(spec.Formatter);
  if isFn then
  begin
    if st.Interp then
      v := TyAnimInterpolateValue(vals[st.Row0], vals[st.Row1], st.T,
        spec.HasPrecision, spec.Precision)
    else
      v := vals[st.Row0];
    if not IsNan(v) then words := EndLabelTextOf(FBindings[ASlot].SeriesIndex, v);
  end
  else if (tpl <> '') then
  begin
    if st.Interp then
      v := TyAnimInterpolateValue(vals[st.Row0], vals[st.Row1], st.T,
        spec.HasPrecision, spec.Precision)
    else
      v := vals[st.Row0];
    if not IsNan(v) then words := StringReplace(tpl, #1, TyJsNumberToString(v), [rfReplaceAll]);
  end;
  if words = '' then Exit;
  { getEndLabelStateSpecified: off the line along the base axis }
  if horiz then
  begin
    if inverse then ah := tahRight else ah := tahLeft;
    av := tavMiddle;
  end
  else
  begin
    ah := tahCentre;
    if inverse then av := tavTop else av := tavBottom;
  end;
  if spec.HasAlignH then ah := spec.AlignH;
  if spec.HasAlignV then av := spec.AlignV;
  scale := APPI / 96;
  pieces := nil;
  FEndLbls[k].AH := ah;
  FEndLbls[k].AV := av;
  { [R5-C] A RICH END LABEL is a block, laid out about its anchor [was: one
    run] }
  if spec.Rt.Needed then
  begin
    pieces := TyLabelBlockPieces(spec, words, AVisual.Fill, True, False, False,
      ah, av, scale, AMeasurer);
    el := TyChartElement(TyShapeRect(TyRtDeviceBox(pieces, x, y, 0, scale)));
    el.Caption.RtPieces := pieces;
    el.Caption.RtScale := scale;
  end
  else
  begin
    AMeasurer.MeasureLine(words, spec.FontName, spec.FontSizeLogical, spec.FontWeight, w, h);
    el := TyChartElement(TyShapeRect(TyAnchorBox(x, y, w, h, ah, av)));
  end;
  el.Caption.Text := words;
  el.Caption.FontName := spec.FontName;
  el.Caption.FontSizeLogical := spec.FontSizeLogical;
  el.Caption.FontWeight := spec.FontWeight;
  TyLabelInk(spec, AVisual.Fill, True, False, False, ink, stroke, strokeW);
  el.Caption.Colour := ink;
  el.Caption.StrokeColour := stroke;
  el.Caption.StrokeWidthLogical := strokeW;
  el.Caption.X := x;
  el.Caption.Y := y;
  el.Caption.AnchorH := ah;
  el.Caption.AnchorV := av;
  el.Caption.ValTpl := tpl;
  el.Z := AVisual.Z;
  el.Z2 := 200;
  el.Silent := True;
  { hidden at rest where only a state shows it [R5-C] }
  el.Ignore := not normalShow;
  el.Datum := TyChartDatum(-1, -1);
  el.Anim.Role := carEndLabel;
  el.Anim.Series := FBindings[ASlot].SeriesIndex;
  el.Anim.Index := -1;
  el.Anim.Pts := run.Anim.Pts;
  el.Anim.Vals := vals;
  el.Anim.Mono := run.Anim.Mono;
  el.Anim.G[0] := dist;
  flags := 0;
  if horiz then flags := flags or 1;
  if inverse then flags := flags or 2;
  if connect then flags := flags or 4;
  if tpl <> '' then flags := flags or 8;
  if spec.HasPrecision then flags := flags or 16;
  { [R5-C] 32 a named formatter counts (EndLabelTextOf), 64 its words are a
    block (EndLabelPiecesOf) }
  if isFn then flags := flags or 32 or 8;
  if spec.Rt.Needed then flags := flags or 64;
  el.Anim.G[1] := flags;
  el.Anim.G[2] := spec.Precision;
  el.Anim.G[3] := run.Anim.G[8];
  { the stepped polyline the label rides, flattened (none: the layout's) }
  SetLength(el.Anim.Base, Length(stepped) * 2);
  for i := 0 to High(stepped) do
  begin
    el.Anim.Base[i * 2] := stepped[i].X;
    el.Anim.Base[i * 2 + 1] := stepped[i].Y;
  end;
  AList.Add(el);
  Result := 1;
end;

function TTyCustomAdvanceChart.EndLabelTextOf(ASeriesIndex: Integer; AValue: Double): string;
var
  i, slot, k: Integer;
  prm: TTyChartCallbackParams;
begin
  Result := '';
  for i := 0 to High(FEndLbls) do
  begin
    if FEndLbls[i].Series <> ASeriesIndex then Continue;
    slot := SlotOfSeries(ASeriesIndex);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
    if not (FEndLbls[i].Spec.HasFormatter and TyChartIsHandlerRef(FEndLbls[i].Spec.Formatter)) then Exit;
    { getFormattedLabel(dataIndex, 'normal', ..., {interpolatedValue}): the
      last row's params, the value the interpolated one }
    prm := TyLabelParams(FStores[slot], FEndLbls[i].Last, FEndLbls[i].Name,
      FEndLbls[i].ValueDim, NaN, False, ASeriesIndex, 'line', 0, '');
    if Length(prm.Values) > 0 then
    begin
      k := High(prm.Values);
      if (FEndLbls[i].ValueDim >= 0) and (FEndLbls[i].ValueDim <= High(prm.Values)) then
        k := FEndLbls[i].ValueDim;
      prm.Values[k] := AValue;
    end;
    prm.ValueText := TyJsNumberToString(AValue);
    Exit(TyChartRunHandler(FEndLbls[i].Spec.Formatter, TyChartOneParams(prm)));
  end;
end;

function TTyCustomAdvanceChart.EndLabelPiecesOf(ASeriesIndex: Integer;
  const AText: string): TTyRtPieceArray;
var i: Integer;
begin
  Result := nil;
  for i := 0 to High(FEndLbls) do
    if (FEndLbls[i].Series = ASeriesIndex) and (FEndLbls[i].Measurer <> nil) then
      Exit(TyLabelBlockPieces(FEndLbls[i].Spec, AText, FEndLbls[i].Ink, True, False,
        False, FEndLbls[i].AH, FEndLbls[i].AV, FEndLbls[i].Scale, FEndLbls[i].Measurer));
end;

{ each data item's own `label`, read over its series' spec, by raw row }
procedure TTyCustomAdvanceChart.ItemLabelSpecs(ASeriesIndex: Integer; const ABase: TTyLabelSpec;
  out ASpecs: TTyLabelSpecArray; out AHas: TTyBoolArray);
var
  node, d, it, lb, em: TJSONData;
  k, j: Integer;
  emph: TJSONObject;
  objRows: TTyIntegerArray;
begin
  ASpecs := nil;
  AHas := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  { [R5-G] the object items only, in order: no other has a label }
  objRows := ObjectRowsOf(TJSONArray(d));
  for j := 0 to High(objRows) do
  begin
    k := objRows[j];
    it := d.Items[k];
    lb := TJSONObject(it).Find('label');
    if (lb <> nil) and (lb.JSONType <> jtObject) then lb := nil;
    { [R5-F] its own emphasis.label, where it lays the text out again: an
      item of its own too, over the series' label }
    emph := nil;
    em := TJSONObject(it).Find('emphasis');
    if (em <> nil) and (em.JSONType = jtObject) then
    begin
      em := TJSONObject(em).Find('label');
      if (em <> nil) and (em.JSONType = jtObject)
        and TyLabelEmphWantsBlock(TJSONObject(em)) then emph := TJSONObject(em);
    end;
    { [R6-A] or a state's textConfig of its own }
    if (lb = nil) and (emph = nil)
      and not TyLabelNodeWritesStateCfg(TJSONObject(it)) then Continue;
    { [R2-L] the tables only once an item has its own: none reads as nil }
    if ASpecs = nil then
    begin
      SetLength(ASpecs, d.Count);
      SetLength(AHas, d.Count);
    end;
    if lb <> nil then
      ASpecs[k] := TyLabelSpecOfNode(TJSONObject(lb), TJSONObject(node), ABase)
    else
      ASpecs[k] := ABase;
    if emph <> nil then ASpecs[k].EmphItemNode := emph.AsJSON;
    { [R6-A] the states' textConfig along the item's model chain }
    TyLabelReadStateCfg([TJSONObject(it), TJSONObject(node)], ASpecs[k]);
    AHas[k] := True;
  end;
end;

function TTyCustomAdvanceChart.LabelSpecFor(ASlot: Integer): TTyLabelSpec;
begin
  Result := LabelSpecFor(ASlot, '');
end;

{ THE THEME HALF OF A LABEL SPEC: fonts, the outside ink and the three
  inside bands, the ground -- everything but what the option says. }
function TTyCustomAdvanceChart.LabelBaseFor(ASlot: Integer): TTyLabelSpec;
var
  outS, lightS, midS, darkS: TTyStyleSet;
  hasCol: Boolean;
  col: Cardinal;
begin
  Result := TyLabelSpecNone;
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight',
    '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '',
    []);
  Result.FontName := outS.FontName;
  Result.FontSizeLogical := ResolveFontSize(outS);
  Result.FontWeight := outS.FontWeight;
  { the root textStyle's font; not its colour, which a label attached to its
    mark never takes [Batch 83] }
  hasCol := False;
  col := 0;
  GlobalTextOver(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    hasCol, col, [ttpSize, ttpWeight, ttpFamily]);
  Result.OutsideColour := TTyChartColor(outS.TextColor);
  Result.InsideColour[0] := TTyChartColor(lightS.TextColor);
  Result.InsideColour[1] := TTyChartColor(midS.TextColor);
  Result.InsideColour[2] := TTyChartColor(darkS.TextColor);
  LabelGround(Result.Ground, Result.GroundDark);
  Result.RtGlobal := RtGlobal;
end;

function TTyCustomAdvanceChart.LabelSpecFor(ASlot: Integer;
  const ADefaultFormatter: string): TTyLabelSpec;
var
  base: TTyLabelSpec;
  outS, lightS, midS, darkS: TTyStyleSet;
  hasCol: Boolean;
  col: Cardinal;
begin
  base := TyLabelSpecNone;
  if ADefaultFormatter <> '' then
  begin
    base.Formatter := ADefaultFormatter;
    base.HasFormatter := True;
  end;
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight',
    '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '',
    []);
  base.FontName := outS.FontName;
  base.FontSizeLogical := ResolveFontSize(outS);
  base.FontWeight := outS.FontWeight;
  hasCol := False;
  col := 0;
  GlobalTextOver(base.FontName, base.FontSizeLogical, base.FontWeight,
    hasCol, col, [ttpSize, ttpWeight, ttpFamily]);
  base.OutsideColour := TTyChartColor(outS.TextColor);
  base.InsideColour[0] := TTyChartColor(lightS.TextColor);
  base.InsideColour[1] := TTyChartColor(midS.TextColor);
  base.InsideColour[2] := TTyChartColor(darkS.TextColor);
  LabelGround(base.Ground, base.GroundDark);
  base.RtGlobal := RtGlobal;
  if ASlot > High(FBindings) then Exit(base);
  { A LINE'S LABEL GOES ABOVE ITS POINT -- the one series type that declares
    a default position; every other falls to `inside`. [Revised in batch 47:
    a line's label sat inside its symbol.] }
  if FBindings[ASlot].SeriesType = 'line' then base.Position := tlpTop;
  { a radar's too (RadarSeries' label.position) [R2-A] }
  if FBindings[ASlot].SeriesType = 'radar' then base.Position := tlpTop;
  Result := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
end;

function TTyCustomAdvanceChart.PieLabelInk: TTyPieLabelInk;
var
  dummyCol: TTyChartColor;
  outS, lightS, midS, darkS: TTyStyleSet;
begin
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight',
    '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '',
    []);
  Result.FontName := outS.FontName;
  Result.FontSizeLogical := ResolveFontSize(outS);
  Result.FontWeight := outS.FontWeight;
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    dummyCol, [ttpSize, ttpWeight, ttpFamily]);
  Result.InsideColour[0] := TTyChartColor(lightS.TextColor);
  Result.InsideColour[1] := TTyChartColor(midS.TextColor);
  Result.InsideColour[2] := TTyChartColor(darkS.TextColor);
  Result.OutsideColour := TTyChartColor(outS.TextColor);
  LabelGround(Result.Ground, Result.GroundDark);
  { labelLine.lineStyle.width, PieSeries.ts:299 -- one logical pixel. }
  Result.LineWidthLogical := 1;
end;

function TTyCustomAdvanceChart.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  Result := TTyPainterTextMeasurer.Create(APPI);
end;

{ ==================== the label layout [Batch 103] ==================== }

{ what a label's style holds, as zrender prints it }
function LmAlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahCentre: Result := 'center';
    tahRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function LmVAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavMiddle: Result := 'middle';
    tavBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

{ a written align, as Text's normalizeStyle reads it }
function LmAlignOf(const S: string): TTyTextAnchorH;
begin
  if (S = 'center') or (S = 'middle') then Result := tahCentre
  else if S = 'right' then Result := tahRight
  else Result := tahLeft;
end;

function LmVAlignOf(const S: string): TTyTextAnchorV;
begin
  if (S = 'middle') or (S = 'center') then Result := tavMiddle
  else if S = 'bottom' then Result := tavBottom
  else Result := tavTop;
end;

{ A ONE-RUN LABEL'S BOX in its own frame: the TSpan's (adjustTextX /
  adjustTextY about nought, a written border round it) unioned with itself,
  as ZRText.getBoundingRect unions its children }
function LmPlainRect(AW, AH, AStroke: Double; AAH: TTyTextAnchorH;
  AAV: TTyTextAnchorV): TTyXYWH;
var x, y, w, h: Double;
begin
  x := 0;
  case AAH of
    tahRight: x := 0 - AW;
    tahCentre: x := 0 - AW / 2;
  end;
  y := 0;
  case AAV of
    tavBottom: y := 0 - AH;
    tavMiddle: y := 0 - AH / 2;
  end;
  w := AW;
  h := AH;
  if AStroke > 0 then
  begin
    x := x - AStroke / 2;
    y := y - AStroke / 2;
    w := w + AStroke;
    h := h + AStroke;
  end;
  Result := TyXYWH(x, y, (x + w) - x, (y + h) - y);
end;

{ a block's box in its own frame, device px }
function LmBlockRect(const APieces: TTyRtPieceArray; AScale: Double): TTyXYWH;
var b: TTyXYWH;
begin
  b := TyRtBounds(APieces);
  if AScale = 1 then Exit(b);
  Result := TyXYWH(b.X * AScale, b.Y * AScale, b.W * AScale, b.H * AScale);
end;

{ the element of a role for one datum: a pie label's slice and line }
function LmFindRole(AList: TTyPaintList; ARole: TTyChartAnimRole;
  ASeries, AIndex: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = ARole) and (AList.Element(i).Anim.Series = ASeries)
      and (AList.Element(i).Anim.Index = AIndex) then
      Exit(i);
  Result := -1;
end;

procedure TTyCustomAdvanceChart.LayoutSeriesLabels(AList: TTyPaintList;
  const ASpecs: TTyLabelSpecArray; const AItemSpecs: TTyLabelSpecTable;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
type
  TLmRef = record
    El, Guide: Integer;
    Layout: TTyChartLabelLayout;
    AH: TTyTextAnchorH;
    AV: TTyTextAnchorV;
    FontSize: Integer;
    TextW, TextH: Double;
    Pieces: TTyRtPieceArray;
    Relaid: Boolean;
    { [R5-F] the scale a re-laid block was laid out at (a pie label had
      none of its own) }
    Scale: Double;
    { [R5-F] the hovered block laid out again under the layout's alignment,
      size and font (the spec at hand) }
    EmphRelay: Boolean;
    EmphSpec: TTyLabelSpec;
    EmphOver: TTyLabelEmphOver;
  end;
var
  scale, ox, oy, cssW, cssH, defX, defY, defRot, defSx, defSy: Double;
  lx, ly, offX, offY, rot, sw, w, h, x, y: Double;
  slots, cand, keys: array of Integer;
  i, j, k, n, e, hi, gi, slot, si, r, t: Integer;
  d: TJSONData;
  node: TJSONObject;
  lay: TTyLabelLayoutSpec;
  refs: array of TLmRef;
  items: TTyLabelLayoutItemArray;
  el, host, guide: TTyChartElement;
  c: TTyElementCaption;
  m0, m: TTyMat2D;
  hasM0, hasM, isFree, hasHost, isPie, styleHasH, styleHasV: Boolean;
  raw0, hostRect, labelRect: TTyXYWH;
  args: TTyChartLabelLayoutArgs;
  lo: TTyChartLabelLayout;
  styleAH, ah: TTyTextAnchorH;
  styleAV, av: TTyTextAnchorV;
  spec: TTyLabelSpec;
  emp: TTyRtPieceArray;
  lmText: string;
  fsz: Integer;
  it: TTyLabelLayoutItem;
  px0, py0: Double;
  pah: TTyTextAnchorH;
  pav: TTyTextAnchorV;
  sized: Boolean;
  ddx, ddy: Double;
  drifted: Boolean;

  { [R6-A] THE STATES' TWINS UNDER THE LAYOUT, laid out again:
    updateLayoutConfig gives the host's textConfig the layout's offset
    [dx || 0, dy || 0], its rotation where it writes one, and no position
    where it puts the label at an x / y of its own (or where it was
    dragged: the label stands where it is); the layout's align,
    verticalAlign, fontSize, width and height are the label's style. A
    state's textConfig goes over that as anywhere (updateInnerText): a
    state position puts the label on its host's rect, a shift or an x / y
    of the layout's no matter. }
  procedure RebuildTwins(AR: Integer; var AEl: TTyChartElement; ADrifted: Boolean);
  var
    tin: TTyLabelTwinIn;
    tw: TTyEmphTwin;
    twins: TTyEmphTwinArray;
    sp: TTyLabelSpec;
    lo2: TTyChartLabelLayout;
    cfg: TTyLabelStateCfg;
    code: Byte;
    hi2, si2, n2: Integer;
  begin
    hi2 := AEl.Caption.LmHostPlus1 - 1;
    si2 := AEl.Datum.SeriesIndex;
    if (hi2 < 0) or (hi2 >= AList.Count) or (si2 < 0) or (si2 > High(ASpecs)) then
    begin
      AEl.EmphTwin := nil;
      Exit;
    end;
    sp := ASpecs[si2];
    if (AEl.Caption.ItemSpec > 0) and (si2 <= High(AItemSpecs))
      and (AEl.Caption.ItemSpec - 1 <= High(AItemSpecs[si2])) then
      sp := AItemSpecs[si2][AEl.Caption.ItemSpec - 1];
    lo2 := refs[AR].Layout;
    sp.FontSizeLogical := refs[AR].FontSize;
    if (lo2.HasWidth and not IsNan(lo2.Width)) or (lo2.HasHeight and not IsNan(lo2.Height)) then
    begin
      sp.Rt.Style.Align := rtaNone;
      sp.Rt.Style.VAlign := rtvNone;
      if lo2.HasWidth and not IsNan(lo2.Width) then
      begin
        sp.Rt.Style.WidthKind := rtwNumber;
        sp.Rt.Style.Width := lo2.Width;
      end;
      if lo2.HasHeight and not IsNan(lo2.Height) then
      begin
        sp.Rt.Style.HasHeight := True;
        sp.Rt.Style.Height := lo2.Height;
      end;
      sp.Rt.Needed := True;
    end
    else if sp.Rt.Needed then
    begin
      sp.Rt.Style.Align := rtaNone;
      sp.Rt.Style.VAlign := rtvNone;
    end;
    tin := Default(TTyLabelTwinIn);
    tin.Spec := sp;
    tin.Normal := TyLabelStateCfgNormal(sp);
    tin.Normal.OffsetXLogical := 0;
    tin.Normal.OffsetYLogical := 0;
    if lo2.HasDx and not IsNan(lo2.Dx) then tin.Normal.OffsetXLogical := lo2.Dx;
    if lo2.HasDy and not IsNan(lo2.Dy) then tin.Normal.OffsetYLogical := lo2.Dy;
    tin.Normal.RotationRad := items[AR].Rotation;
    tin.Normal.HasPosition := not items[AR].Free and not ADrifted;
    tin.Host := AList.Element(hi2);
    tin.Base := AEl.Caption;
    tin.Text := AEl.Caption.Text;
    if AEl.Caption.LmText <> '' then tin.Text := AEl.Caption.LmText;
    if tin.Host.Caption.HasHostBox then
    begin
      tin.HBox := tin.Host.Caption.HostBox;
      tin.HasBox := True;
    end
    else if tin.Host.Caption.HasSymBox then
    begin
      tin.HBox := tin.Host.Caption.SymBox;
      tin.HasBox := True;
    end
    else
      tin.Bounds := TyRectF(AEl.Caption.LmHostRect.X, AEl.Caption.LmHostRect.Y,
        AEl.Caption.LmHostRect.X + AEl.Caption.LmHostRect.W,
        AEl.Caption.LmHostRect.Y + AEl.Caption.LmHostRect.H);
    tin.W := refs[AR].TextW;
    tin.H := refs[AR].TextH;
    if AEl.Caption.RtScale > 0 then tin.Scale := AEl.Caption.RtScale else tin.Scale := scale;
    tin.HostFill := AEl.Caption.LmInkFill;
    tin.HostHasFill := AEl.Caption.LmInkHasFill;
    { where it stands with no position: label.x / y (the layout's), or where
      it was dragged to }
    if ADrifted then
    begin
      tin.FreeX := AEl.Caption.X;
      tin.FreeY := AEl.Caption.Y;
      tin.Normal.OffsetXLogical := 0;
      tin.Normal.OffsetYLogical := 0;
    end
    else
    begin
      tin.FreeX := items[AR].LabelX;
      tin.FreeY := items[AR].LabelY;
    end;
    tin.FreeAH := refs[AR].AH;
    tin.FreeAV := refs[AR].AV;
    tin.FreeInside := AEl.Caption.LmInkInside;
    tin.StyleHasAH := AEl.Caption.LmStyleHasAH;
    tin.StyleAH := AEl.Caption.LmStyleAH;
    tin.StyleHasAV := AEl.Caption.LmStyleHasAV;
    tin.StyleAV := AEl.Caption.LmStyleAV;
    if lo2.HasAlign then
    begin
      tin.StyleHasAH := True;
      tin.StyleAH := LmAlignOf(lo2.Align);
    end;
    if lo2.HasVerticalAlign then
    begin
      tin.StyleHasAV := True;
      tin.StyleAV := LmVAlignOf(lo2.VerticalAlign);
    end;
    twins := nil;
    for code := TyTwinEmphasis to TyTwinSelectBlur do
      if TyLabelStateCfgOf(sp, code, cfg) and TyLabelLayTwin(tin, code, cfg, AMeasurer, tw) then
      begin
        { the layout's own size, not the twin's spec's }
        tw.Caption.FontSizeLogical := refs[AR].FontSize;
        n2 := Length(twins);
        SetLength(twins, n2 + 1);
        twins[n2] := tw;
      end;
    AEl.EmphTwin := twins;
  end;

begin
  if (AList = nil) or (FOption = nil) or (AMeasurer = nil) then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  ox := FLastRect.Left;
  oy := FLastRect.Top;
  cssW := (FLastRect.Right - FLastRect.Left) / scale;
  cssH := (FLastRect.Bottom - FLastRect.Top) / scale;
  { THE SERIES IN SERIES ORDER -- updatedSeries is eachSeries' }
  SetLength(slots, Length(FBindings));
  n := 0;
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].Hidden then Continue;
    j := n - 1;
    while (j >= 0) and (FBindings[slots[j]].SeriesIndex > FBindings[i].SeriesIndex) do
    begin
      slots[j + 1] := slots[j];
      Dec(j);
    end;
    slots[j + 1] := i;
    Inc(n);
  end;
  SetLength(slots, n);
  refs := nil;
  items := nil;
  for k := 0 to High(slots) do
  begin
    slot := slots[k];
    si := FBindings[slot].SeriesIndex;
    d := FOption.ComponentAt('series', si);
    if (d = nil) or (d.JSONType <> jtObject) then Continue;
    node := TJSONObject(d);
    isPie := FBindings[slot].SeriesType = TyPieSeriesTypeName;
    { `labelLayout`, a pie's default merged under it }
    lay := TyLabelLayoutSpecOf(node.Find('labelLayout'),
      node.IndexOfName('labelLayout') >= 0, isPie);
    if lay.Kind = tlkNone then Continue;
    { THE SERIES' LABELS IN THEIR HOSTS' ORDER -- the group's traverse }
    cand := nil;
    keys := nil;
    for e := 0 to AList.Count - 1 do
    begin
      el := AList.Element(e);
      if (el.Caption.LmKind = 0) or (el.Datum.SeriesIndex <> si) then Continue;
      hi := el.Caption.LmHostPlus1 - 1;
      if hi < 0 then hi := LmFindRole(AList, carSector, si, el.Anim.Index);
      if hi < 0 then hi := e;
      n := Length(cand);
      SetLength(cand, n + 1);
      SetLength(keys, n + 1);
      j := n - 1;
      while (j >= 0) and (keys[j] > hi) do
      begin
        cand[j + 1] := cand[j];
        keys[j + 1] := keys[j];
        Dec(j);
      end;
      cand[j + 1] := e;
      keys[j + 1] := hi;
    end;
    for t := 0 to High(cand) do
    begin
      e := cand[t];
      el := AList.Element(e);
      c := el.Caption;
      hi := keys[t];
      gi := -1;
      if isPie then gi := LmFindRole(AList, carGuide, si, el.Anim.Index);
      { ---- what LabelManager keeps when it adds the label ---- }
      hasHost := False;
      hostRect := TyXYWH(0, 0, 0, 0);
      if isPie then
      begin
        if (hi >= 0) and (hi <> e) and (slot <= High(FPies)) then
        begin
          host := AList.Element(hi);
          hostRect := TySectorPathRect(host.Anim.G[0], host.Anim.G[1], host.Anim.G[2],
            host.Anim.G[3], host.Anim.G[4], host.Anim.G[5], FPies[slot].Clockwise);
          if (host.Style.StrokeWidthLogical > 0) and (host.Style.StrokeColor <> 0) then
          begin
            sw := host.Style.StrokeWidthLogical;
            if not host.Style.HasFill then sw := Max(sw, 5.0);
            sw := sw * scale;
            hostRect.W := hostRect.W + sw;
            hostRect.H := hostRect.H + sw;
            hostRect.X := hostRect.X - sw / 2;
            hostRect.Y := hostRect.Y - sw / 2;
          end;
          hasHost := True;
        end;
      end
      else
      begin
        hasHost := c.LmHasHostRect;
        hostRect := c.LmHostRect;
      end;
      { the label's first transform, decomposed }
      hasM0 := TyLabelLocalTransform(c.LmBaseX + c.LmOffX, c.LmBaseY + c.LmOffY,
        -c.LmOffX, -c.LmOffY, c.RotationRad, 1, 1, m0);
      TyLabelDecompose(m0, hasM0, defX, defY, defRot, defSx, defSy);
      if Length(c.RtPieces) > 0 then raw0 := LmBlockRect(c.RtPieces, c.RtScale)
      else raw0 := LmPlainRect(c.LmTextW, c.LmTextH, c.LmStrokeW, c.AnchorH, c.AnchorV);
      if hasM0 then labelRect := TyRectApplyMat(raw0, m0) else labelRect := raw0;
      { ---- the layout for this label: the object, or the function's answer ---- }
      if lay.Kind = tlkHandler then
      begin
        args := Default(TTyChartLabelLayoutArgs);
        args.DataIndex := el.Datum.DataIndex;
        args.SeriesIndex := si;
        args.DataType := '';
        if c.LmText <> '' then args.Text := c.LmText else args.Text := c.Text;
        args.HasRect := hasHost;
        args.RectX := hostRect.X;
        args.RectY := hostRect.Y;
        args.RectW := hostRect.W;
        args.RectH := hostRect.H;
        args.LabelRectX := labelRect.X;
        args.LabelRectY := labelRect.Y;
        args.LabelRectW := labelRect.W;
        args.LabelRectH := labelRect.H;
        if c.LmStyleHasAH then args.Align := LmAlignName(c.LmStyleAH);
        if c.LmStyleHasAV then args.VerticalAlign := LmVAlignName(c.LmStyleAV);
        if gi >= 0 then args.LabelLinePoints := Copy(AList.Element(gi).Shape.Points);
        args.ChartWidth := cssW;
        args.ChartHeight := cssH;
        args.Scale := scale;
        TyChartRunLabelLayoutHandler(lay.Handler, args, lo);
      end
      else
        lo := lay.Obj;
      { ---- updateLayoutConfig ---- }
      isFree := (lo.X.Kind <> cpvAbsent) or (lo.Y.Kind <> cpvAbsent) or (c.LmKind = 2);
      if lo.X.Kind <> cpvAbsent then lx := ox + scale * TyLabelLayoutPos(lo.X, cssW)
      else lx := defX;
      if lo.Y.Kind <> cpvAbsent then ly := oy + scale * TyLabelLayoutPos(lo.Y, cssH)
      else ly := defY;
      { [dx || 0, dy || 0] replaces the host's offset }
      offX := 0;
      if lo.HasDx and not IsNan(lo.Dx) and (lo.Dx <> 0) then offX := lo.Dx * scale;
      offY := 0;
      if lo.HasDy and not IsNan(lo.Dy) and (lo.Dy <> 0) then offY := lo.Dy * scale;
      if lo.HasRotate then rot := TyLabelLayoutRad(lo.Rotate)
      else if c.LmHasAttachedRot then rot := c.LmAttachedRot
      else rot := defRot;
      styleHasH := c.LmStyleHasAH;
      styleAH := c.LmStyleAH;
      if lo.HasAlign then
      begin
        styleHasH := True;
        styleAH := LmAlignOf(lo.Align);
      end;
      styleHasV := c.LmStyleHasAV;
      styleAV := c.LmStyleAV;
      if lo.HasVerticalAlign then
      begin
        styleHasV := True;
        styleAV := LmVAlignOf(lo.VerticalAlign);
      end;
      { style.align || the position's || left }
      if styleHasH then ah := styleAH
      else if isFree then ah := tahLeft
      else ah := c.LmPosAH;
      if styleHasV then av := styleAV
      else if isFree then av := tavTop
      else av := c.LmPosAV;
      fsz := c.FontSizeLogical;
      if lo.HasFontSize and (lo.FontSize > 0) then fsz := TyFontSizeFromPx(lo.FontSize);
      r := Length(refs);
      SetLength(refs, r + 1);
      refs[r].El := e;
      refs[r].Guide := gi;
      refs[r].Layout := lo;
      refs[r].AH := ah;
      refs[r].AV := av;
      refs[r].FontSize := fsz;
      refs[r].Relaid := False;
      refs[r].Pieces := c.RtPieces;
      refs[r].Scale := c.RtScale;
      { [R5-F] A HOVERED BLOCK whose alignment, size or font the layout
        changed: laid out again with them (an emphasis key over them wins)
        [was: the hovered block kept the alignment it was built with] }
      refs[r].EmphRelay := False;
      if (c.LmKind = 1) and (si <= High(ASpecs)) then
      begin
        spec := ASpecs[si];
        if (c.ItemSpec > 0) and (si <= High(AItemSpecs))
          and (c.ItemSpec - 1 <= High(AItemSpecs[si])) then
          spec := AItemSpecs[si][c.ItemSpec - 1];
        if ((spec.EmphRtNode <> '') or (spec.EmphItemNode <> ''))
          and ((ah <> c.AnchorH) or (av <> c.AnchorV) or (fsz <> c.FontSizeLogical)
            or (lo.HasWidth and not IsNan(lo.Width))
            or (lo.HasHeight and not IsNan(lo.Height))) then
        begin
          refs[r].EmphRelay := True;
          refs[r].EmphSpec := spec;
          refs[r].EmphOver := TyLabelEmphOverNone;
          refs[r].EmphOver.NoStyleAlign := True;
          if fsz <> c.FontSizeLogical then refs[r].EmphOver.FontSize := fsz;
          if lo.HasWidth and not IsNan(lo.Width) then
          begin
            refs[r].EmphOver.HasWidth := True;
            refs[r].EmphOver.Width := lo.Width;
          end;
          if lo.HasHeight and not IsNan(lo.Height) then
          begin
            refs[r].EmphOver.HasHeight := True;
            refs[r].EmphOver.Height := lo.Height;
          end;
        end;
      end;
      it := Default(TTyLabelLayoutItem);
      { [R5-C] THE LAYOUT'S width / height ON THE LABEL'S STYLE
        (LABEL_OPTION_TO_STYLE_KEYS): the text block sized so -- an
        overflow cut or wrapped at the width, lines past the height dropped
        under lineOverflow, a box drawn at that size -- laid out again for a
        label of a series (its spec at hand) [was: read, not applied] }
      { [R5-F] a label placed at x / y (a pie's) too [was: a series label
        its host places only] }
      sized := ((lo.HasWidth and not IsNan(lo.Width)) or (lo.HasHeight and not IsNan(lo.Height)))
        and (c.LmKind >= 1) and (si <= High(ASpecs));
      if sized then
      begin
        spec := ASpecs[si];
        if (c.ItemSpec > 0) and (si <= High(AItemSpecs))
          and (c.ItemSpec - 1 <= High(AItemSpecs[si])) then
          spec := AItemSpecs[si][c.ItemSpec - 1];
        spec.FontSizeLogical := fsz;
        spec.Rt.Style.Align := rtaNone;
        spec.Rt.Style.VAlign := rtvNone;
        if lo.HasWidth and not IsNan(lo.Width) then
        begin
          spec.Rt.Style.WidthKind := rtwNumber;
          spec.Rt.Style.Width := lo.Width;
        end;
        if lo.HasHeight and not IsNan(lo.Height) then
        begin
          spec.Rt.Style.HasHeight := True;
          spec.Rt.Style.Height := lo.Height;
        end;
        spec.Rt.Needed := True;
        { the label's own text, not what a width cut it to (a pie's) }
        if c.LmText <> '' then lmText := c.LmText else lmText := c.Text;
        if c.RtScale <= 0 then c.RtScale := scale;
        refs[r].Pieces := TyLabelBlockPieces(spec, lmText, c.LmInkFill,
          c.LmInkHasFill, c.LmInkGradient, c.LmInkInside, ah, av, c.RtScale, AMeasurer);
        refs[r].Relaid := True;
        refs[r].Scale := c.RtScale;
        it.RawLocal := LmBlockRect(refs[r].Pieces, c.RtScale);
      end
      else if Length(c.RtPieces) = 0 then
      begin
        w := c.LmTextW;
        h := c.LmTextH;
        if fsz <> c.FontSizeLogical then
          AMeasurer.MeasureLine(c.Text, c.FontName, fsz, c.FontWeight, w, h);
        refs[r].TextW := w;
        refs[r].TextH := h;
        it.RawLocal := LmPlainRect(w, h, c.LmStrokeW, ah, av);
      end
      else
      begin
        { A BLOCK IS LAID OUT AGAIN where its alignment or size changed (a
          series label's: the spec is at hand) }
        if ((ah <> c.AnchorH) or (av <> c.AnchorV) or (fsz <> c.FontSizeLogical))
          and (c.LmKind = 1) and (si <= High(ASpecs)) then
        begin
          spec := ASpecs[si];
          if (c.ItemSpec > 0) and (si <= High(AItemSpecs))
            and (c.ItemSpec - 1 <= High(AItemSpecs[si])) then
            spec := AItemSpecs[si][c.ItemSpec - 1];
          spec.FontSizeLogical := fsz;
          spec.Rt.Style.Align := rtaNone;
          spec.Rt.Style.VAlign := rtvNone;
          refs[r].Pieces := TyLabelBlockPieces(spec, c.Text, c.LmInkFill,
            c.LmInkHasFill, c.LmInkGradient, c.LmInkInside, ah, av, c.RtScale, AMeasurer);
          refs[r].Relaid := True;
        end;
        it.RawLocal := LmBlockRect(refs[r].Pieces, c.RtScale);
      end;
      { ---- the item ---- }
      if hasHost then it.Priority := hostRect.W * hostRect.H else it.Priority := 0;
      it.DefIgnore := el.Ignore;
      it.HasGuide := gi >= 0;
      if gi >= 0 then it.DefGuideIgnore := AList.Element(gi).Ignore;
      it.Move := TyLabelMoveOf(lo);
      it.HideOverlap := lo.HideOverlap;
      it.Free := isFree;
      it.MarginType := c.LmMarginType;
      for j := 0 to 3 do it.Margin[j] := c.LmMargin[j];
      if isFree then
      begin
        it.InnerX := lx + offX;
        it.InnerY := ly + offY;
      end
      else
      begin
        { the position puts it at its anchor again; label.x / y are the
          decomposed ones, which nothing draws }
        it.InnerX := c.LmBaseX + offX;
        it.InnerY := c.LmBaseY + offY;
        lx := defX;
        ly := defY;
      end;
      it.OriginX := -offX;
      it.OriginY := -offY;
      { [R5-C] A HOST THAT SET ITS OWN ORIGIN -- a radial tree's
        textConfig.origin 'center' -- keeps it where the layout gives no x
        or y: updateInnerText places the label by the position again, adds
        the offset to the place and leaves the origin at the box's centre
        (relative to the place before the offset). The offset is then not
        turned with the label. }
      if c.HasFixedPos and c.HasHostBox and (lo.X.Kind = cpvAbsent)
        and (lo.Y.Kind = cpvAbsent) then
      begin
        TyLabelAnchorXYWH(c.HostBox, TTyLabelPosition(c.FixedPos), c.FixedDist,
          0, 0, px0, py0, pah, pav);
        it.Free := False;
        it.InnerX := px0 + offX;
        it.InnerY := py0 + offY;
        it.OriginX := (-px0 + c.HostBox.W * 0.5) + c.HostBox.X;
        it.OriginY := (-py0 + c.HostBox.H * 0.5) + c.HostBox.Y;
        { its turn is the host's textConfig.rotation as set, not one read
          back off the matrix }
        if not lo.HasRotate then rot := c.RotationRad;
        lx := defX;
        ly := defY;
      end;
      it.Rotation := rot;
      it.ScaleX := defSx;
      it.ScaleY := defSy;
      it.OffX := offX;
      it.OffY := offY;
      it.LabelX := lx;
      it.LabelY := ly;
      n := Length(items);
      SetLength(items, n + 1);
      items[n] := it;
    end;
  end;
  if Length(items) = 0 then Exit;

  { ---- layout(): the shifts, then hideOverlap ---- }
  TyLayoutLabels(items, ox, oy, FLastRect.Right, FLastRect.Bottom);

  { ---- the answers onto the elements ---- }
  SetLength(FLmEls, Length(refs));
  SetLength(FLmGuides, Length(refs));
  SetLength(FLmRoute, Length(refs));
  for r := 0 to High(refs) do
  begin
    FLmEls[r] := refs[r].El;
    { needsUpdateLabelLine: an x or a y, unless labelLinePoints set the line
      that is there [Batch 112] }
    FLmGuides[r] := refs[r].Guide;
    FLmRoute[r] := ((refs[r].Layout.X.Kind <> cpvAbsent) or (refs[r].Layout.Y.Kind <> cpvAbsent))
      and not (refs[r].Layout.HasLabelLinePoints and (refs[r].Guide >= 0));
    el := AList.Element(refs[r].El);
    if items[r].Free then
    begin
      x := items[r].LabelX + items[r].OffX;
      y := items[r].LabelY + items[r].OffY;
    end
    else
    begin
      x := items[r].InnerX;
      y := items[r].InnerY;
    end;
    hasM := TyLabelLocalTransform(x, y, items[r].OriginX, items[r].OriginY,
      items[r].Rotation, items[r].ScaleX, items[r].ScaleY, m);
    { [R5-C] A DRAGGED LABEL the layout placed: its drift on its transform
      (Element.drift), its line routed again from where it is now; one its
      host places by its position is put back there by updateInnerText }
    drifted := False;
    if items[r].Free and refs[r].Layout.Draggable
      and LbDriftOf(el.Datum.SeriesIndex, el.Datum.DataIndex, ddx, ddy) then
    begin
      drifted := True;
      if not hasM then
      begin
        m[0] := 1; m[1] := 0; m[2] := 0; m[3] := 1; m[4] := 0; m[5] := 0;
      end;
      hasM := True;
      m[4] := m[4] + ddx;
      m[5] := m[5] + ddy;
      FLmRoute[r] := True;
    end;
    el.Caption.LmDraggable := refs[r].Layout.Draggable;
    if refs[r].Layout.Draggable then el.Cursor := 'move';
    if hasM then
    begin
      el.Caption.X := m[4];
      el.Caption.Y := m[5];
    end
    else
    begin
      el.Caption.X := 0;
      el.Caption.Y := 0;
    end;
    el.Caption.LmHasM := hasM;
    el.Caption.LmM := m;
    el.Caption.RotationRad := items[r].Rotation;
    el.Caption.AnchorH := refs[r].AH;
    el.Caption.AnchorV := refs[r].AV;
    el.Caption.FontSizeLogical := refs[r].FontSize;
    if Length(refs[r].Pieces) > 0 then
    begin
      el.Caption.RtPieces := refs[r].Pieces;
      if refs[r].Scale > 0 then el.Caption.RtScale := refs[r].Scale;
      if refs[r].Relaid then
        el.Caption.RtEmph := TyRtReink(refs[r].Pieces, el.Caption.EmphColour, True,
          el.Caption.EmphStrokeColour, el.Caption.EmphStrokeWidthLogical);
      el.Shape := TyShapeRect(TyRtDeviceBox(refs[r].Pieces, el.Caption.X,
        el.Caption.Y, el.Caption.RotationRad, el.Caption.RtScale));
    end
    else
      el.Shape := TyShapeRect(TyAnchorBox(el.Caption.X, el.Caption.Y,
        refs[r].TextW, refs[r].TextH, refs[r].AH, refs[r].AV));
    if refs[r].EmphRelay then
    begin
      if el.Caption.RtScale <= 0 then el.Caption.RtScale := scale;
      emp := TyLabelEmphPiecesOver(refs[r].EmphSpec, el.Caption.Text,
        el.Caption.LmInkFill, el.Caption.LmInkHasFill, el.Caption.EmphColour,
        el.Caption.EmphStrokeColour, el.Caption.EmphStrokeWidthLogical,
        refs[r].AH, refs[r].AV, el.Caption.RtScale, AMeasurer, refs[r].EmphOver);
      if Length(emp) > 0 then el.Caption.RtEmph := emp;
    end;
    el.Ignore := items[r].Ignore;
    el.Caption.LmOverlapHidden := items[r].Ignore and not items[r].DefIgnore;
    el.Caption.LmEmphShow := items[r].EmphShow;
    { PLACED AT label.x / y, it no longer rides its host }
    if items[r].Free then
    begin
      el.Caption.LmFree := True;
      el.Anim.HostPlus1 := 0;
    end;
    { [R6-A] the states' twins, under the layout }
    if (el.Caption.LmKind = 1) and (Length(el.EmphTwin) > 0) then
      RebuildTwins(r, el, drifted);
    AList.SetElement(refs[r].El, el);
    if refs[r].Guide >= 0 then
    begin
      guide := AList.Element(refs[r].Guide);
      guide.Ignore := items[r].GuideIgnore;
      guide.Caption.LmOverlapHidden := items[r].GuideIgnore and not items[r].DefGuideIgnore;
      guide.Caption.LmEmphShow := items[r].GuideEmphShow;
      { labelLinePoints set the line as given }
      if refs[r].Layout.HasLabelLinePoints then
      begin
        SetLength(guide.Shape.Points, Length(refs[r].Layout.LabelLinePoints));
        for j := 0 to High(refs[r].Layout.LabelLinePoints) do
        begin
          guide.Shape.Points[j].X := refs[r].Layout.LabelLinePoints[j].X;
          guide.Shape.Points[j].Y := refs[r].Layout.LabelLinePoints[j].Y;
        end;
      end;
      AList.SetElement(refs[r].Guide, guide);
    end;
  end;
  FLmItems := items;
end;

procedure TTyCustomAdvanceChart.RouteLabelLines(AList: TTyPaintList;
  const ASpecs: TTyLabelSpecArray; const AItemSpecs: TTyLabelSpecTable;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
const
  cStNamesLg: array[TTyStName] of string = ('select', 'emphasis', 'blur');
var
  scale, len, minTurn, smooth, w: Double;
  lmOf: TTyIntegerArray;
  count, e, r, hi, slot, si, raw, j: Integer;
  el, host, guide: TTyChartElement;
  c: TTyElementCaption;
  gh: TTyGuideHost;
  pts: TTyGuidePoints;
  rawRect: TTyXYWH;
  m: TTyMat2D;
  hasM, showN, showAny, has, above: Boolean;
  nodes: TTyStNodeArray;
  n: TTyStName;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  spec: TTyLabelSpec;
  pieces: TTyRtPieceArray;
  txt: string;
  col: TTyChartColor;
  d: TJSONData;
begin
  if AList = nil then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  { ONLY WHAT WAS BUILT: the lines appended below are no labels }
  count := AList.Count;
  SetLength(lmOf, count);
  for e := 0 to count - 1 do lmOf[e] := -1;
  for r := 0 to High(FLmEls) do
    if (FLmEls[r] >= 0) and (FLmEls[r] < count) then lmOf[FLmEls[r]] := r;

  { ---- A PIE given an x or a y: its line routed again, from the anchor its
    layout left (the line's first point) to the moved label ---- }
  for r := 0 to High(FLmEls) do
  begin
    if (r > High(FLmRoute)) or not FLmRoute[r] or (FLmGuides[r] < 0) then Continue;
    el := AList.Element(FLmEls[r]);
    guide := AList.Element(FLmGuides[r]);
    if Length(guide.Shape.Points) < 1 then Continue;
    slot := SlotOfSeries(el.Datum.SeriesIndex);
    if (slot < 0) or (FBindings[slot].SeriesType <> TyPieSeriesTypeName) then Continue;
    nodes := StNodes(el.Datum.SeriesIndex, el.Datum.RawDataIndex);
    gh := Default(TTyGuideHost);
    gh.HasAnchor := True;
    gh.AnchorX := guide.Shape.Points[0].X;
    gh.AnchorY := guide.Shape.Points[0].Y;
    { a pie's labelLine defaults: length2 30, minTurnAngle 90 }
    len := TyGuideLength2(TyStFind(nodes, ['labelLine', 'length2']), 30) * scale;
    minTurn := TyGuideJsNumber(TyStFind(nodes, ['labelLine', 'minTurnAngle']), 90);
    TyLabelLineRoute(FLmItems[r].RawLocal, el.Caption.LmHasM, el.Caption.LmM, gh, len, pts);
    TyLimitTurnAngle(pts, minTurn);
    SetLength(guide.Shape.Points, 3);
    for j := 0 to 2 do guide.Shape.Points[j] := pts[j];
    guide.Shape.Cmds := TyLabelLineCmds(pts, guide.Caption.LgSmooth);
    AList.SetElement(FLmGuides[r], guide);
  end;

  { ---- EVERY OTHER LABEL on a symbol or a bar: _updateLabelLine creates its
    line where some state shows it, and routes it ---- }
  for e := 0 to count - 1 do
  begin
    { most elements are not such a label: asked by reference before the
      copies [P2]; a mark that fixed its own anchor (a tree's, a sunburst's,
      a sankey's) hangs its label on its host as well [R5-C] }
    if not (AList.Ref(e)^.Caption.LmKind in [1, 2]) then Continue;
    el := AList.Element(e);
    c := el.Caption;
    hi := c.LmHostPlus1 - 1;
    if (hi < 0) or (hi >= count) then Continue;
    host := AList.Element(hi);
    if not TyGuideHostOf(host.Caption, gh) then Continue;
    si := el.Datum.SeriesIndex;
    slot := SlotOfSeries(si);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    if el.Datum.DataIndex < 0 then Continue;
    raw := FStores[slot].GetRawIndex(el.Datum.DataIndex);
    nodes := StNodes(si, raw);
    { setLabelLineStyle: a line where the normal labelLine shows, or any
      state's (the normal one by default) }
    showN := TyStReadBool(nodes, ['labelLine', 'show'], has) and has;
    showAny := showN;
    for n := Low(TTyStName) to High(TTyStName) do
      if TyStReadBool(nodes, [cStNamesLg[n], 'labelLine', 'show'], has) and has then
        showAny := True;
    if not showAny then Continue;

    { ---- THE LABEL'S RECT AS IT IS READ, before getComputedTransform
      hands the label its host's alignment: a laid-out label's own (the
      layout already gave it), a label the layout never saw only its
      style's -- left / top otherwise -- and one ignored at rest the one its
      host gave it when it was listed ---- }
    r := lmOf[e];
    if (r >= 0) and not FLmItems[r].DefIgnore then
      rawRect := FLmItems[r].RawLocal
    else
    begin
      if c.LmStyleHasAH then ah := c.LmStyleAH
      else if r >= 0 then ah := c.LmPosAH
      else ah := tahLeft;
      if c.LmStyleHasAV then av := c.LmStyleAV
      else if r >= 0 then av := c.LmPosAV
      else av := tavTop;
      if Length(c.RtPieces) = 0 then
        rawRect := LmPlainRect(c.LmTextW, c.LmTextH, c.LmStrokeW, ah, av)
      else if (ah = c.AnchorH) and (av = c.AnchorV) then
        rawRect := LmBlockRect(c.RtPieces, c.RtScale)
      else
      begin
        { the block laid out again at that alignment }
        if si > High(ASpecs) then Continue;
        spec := ASpecs[si];
        if (c.ItemSpec > 0) and (si <= High(AItemSpecs))
          and (c.ItemSpec - 1 <= High(AItemSpecs[si])) then
          spec := AItemSpecs[si][c.ItemSpec - 1];
        spec.Rt.Style.Align := rtaNone;
        spec.Rt.Style.VAlign := rtvNone;
        pieces := TyLabelBlockPieces(spec, c.Text, c.LmInkFill, c.LmInkHasFill,
          c.LmInkGradient, c.LmInkInside, ah, av, c.RtScale, AMeasurer);
        rawRect := LmBlockRect(pieces, c.RtScale);
      end;
    end;
    { its transform: the layout's, or the attached label's own }
    if r >= 0 then
    begin
      hasM := c.LmHasM;
      m := c.LmM;
    end
    else
      hasM := TyLabelLocalTransform(c.LmBaseX + c.LmOffX, c.LmBaseY + c.LmOffY,
        -c.LmOffX, -c.LmOffY, c.RotationRad, 1, 1, m);

    { ---- route, limit ---- }
    len := TyGuideLength2(TyStFind(nodes, ['labelLine', 'length2']), 0) * scale;
    minTurn := TyGuideJsNumber(TyStFind(nodes, ['labelLine', 'minTurnAngle']), NaN);
    smooth := TyLabelLineSmoothOf(TyStFind(nodes, ['labelLine', 'smooth']));
    TyLabelLineRoute(rawRect, hasM, m, gh, len, pts);
    TyLimitTurnAngle(pts, minTurn);

    { ---- the line ---- }
    guide := TyChartElement(TyShapePolyline(pts));
    guide.Shape.Cmds := TyLabelLineCmds(pts, smooth);
    guide.Caption.LgSmooth := smooth;
    { lineStyle over the item's colour (the visual's, by its draw type) and
      zrender's width of 1 [R5-C: every key getLineStyle reads] }
    guide.Style.HasFill := False;
    guide.Style.StrokeColor := host.Caption.LgColor;
    guide.Style.StrokeWidthLogical := 1;
    GuideLineStyle(nodes, ['labelLine', 'lineStyle'], guide.Style);
    { a pointer at its datum, never a target }
    guide.Silent := True;
    guide.IsGuide := True;
    guide.Datum := el.Datum;
    guide.Anim.Role := carGuide;
    guide.Anim.Series := si;
    guide.Anim.Index := el.Datum.DataIndex;
    { [R2-I1] one of the datum's several labels' (a radar item's points):
      its own proxy and its own states }
    guide.Anim.Sub := el.Anim.Sub;
    { updateZ: under its host, or over it with showAbove }
    above := TyStReadBool(nodes, ['labelLine', 'showAbove'], has) and has;
    guide.Z := host.Z;
    if above then guide.Z2 := host.Z2 + 1 else guide.Z2 := host.Z2 - 1;
    { hidden where its label is, or where the normal labelLine does not show }
    guide.Ignore := el.Ignore or not showN;
    AList.Add(guide);
  end;
end;

procedure TTyCustomAdvanceChart.OwnLabelOpacity(ASlot: Integer; AList: TTyPaintList;
  ALo, AHi: Integer);
var
  k, j, si, raw: Integer;
  pe: PTyChartElement;
  nodes: TTyStNodeArray;
  op, glob: Double;
  has, hasGlob: Boolean;
  d: TJSONData;
begin
  if (AList = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  si := FBindings[ASlot].SeriesIndex;
  { the global textStyle.opacity, under every label's own }
  hasGlob := False;
  glob := 1;
  if (FOption <> nil) and (FOption.Root is TJSONObject) then
  begin
    d := TJSONObject(FOption.Root).Find('textStyle');
    if d is TJSONObject then
    begin
      d := TJSONObject(d).Find('opacity');
      if (d <> nil) and (d.JSONType = jtNumber) then
      begin
        hasGlob := True;
        glob := d.AsFloat;
      end;
    end;
  end;
  for k := AHi to AList.Count - 1 do
  begin
    pe := AList.Ref(k);
    if (pe^.Caption.FontSizeLogical <= 0) or pe^.IsGuide then Continue;
    if (pe^.Datum.Kind <> ctkSeries) or (pe^.Datum.SeriesIndex <> si) then Continue;
    raw := pe^.Datum.RawDataIndex;
    if raw < 0 then raw := pe^.Datum.DataIndex;
    nodes := StNodes(si, raw);
    op := TyStReadNumber(nodes, ['label', 'opacity'], has);
    if has and not IsNan(op) then
    begin
      pe^.Style.Alpha := op;
      Continue;
    end;
    if hasGlob then
    begin
      pe^.Style.Alpha := glob;
      Continue;
    end;
    { the mark's: the slice or band of the same datum }
    for j := ALo to AHi - 1 do
      if (AList.Ref(j)^.Datum.Kind = ctkSeries) and (AList.Ref(j)^.Datum.SeriesIndex = si)
        and (AList.Ref(j)^.Datum.DataIndex = pe^.Datum.DataIndex)
        and (AList.Ref(j)^.Caption.FontSizeLogical <= 0) and not AList.Ref(j)^.IsGuide then
      begin
        pe^.Style.Alpha := AList.Ref(j)^.Style.Alpha;
        Break;
      end;
  end;
end;

procedure TTyCustomAdvanceChart.LbDragStart(const ATarget: TTyChartEventTarget;
  AX, AY: Integer);
var pe: PTyChartElement;
begin
  FLbDragOn := False;
  if (FPaintList = nil) or (ATarget.Id <= 0) or (ATarget.Id > FPaintList.Count) then Exit;
  pe := FPaintList.Ref(ATarget.Id - 1);
  if not pe^.Caption.LmDraggable or (pe^.Anim.Role = carGuide) then Exit;
  FLbDragOn := True;
  FLbDragS := pe^.Datum.SeriesIndex;
  FLbDragD := pe^.Datum.DataIndex;
  FLbDragX := AX;
  FLbDragY := AY;
end;

procedure TTyCustomAdvanceChart.LbDragMove(AX, AY: Integer);
var
  k, n: Integer;
  dx, dy: Integer;
begin
  if not FLbDragOn then Exit;
  dx := AX - FLbDragX;
  dy := AY - FLbDragY;
  FLbDragX := AX;
  FLbDragY := AY;
  { drift(dx, dy): the label's translation, whatever then draws it }
  n := -1;
  for k := 0 to High(FLbDrifts) do
    if (FLbDrifts[k].S = FLbDragS) and (FLbDrifts[k].D = FLbDragD) then n := k;
  if n < 0 then
  begin
    n := Length(FLbDrifts);
    SetLength(FLbDrifts, n + 1);
    FLbDrifts[n].S := FLbDragS;
    FLbDrifts[n].D := FLbDragD;
    FLbDrifts[n].DX := 0;
    FLbDrifts[n].DY := 0;
  end;
  FLbDrifts[n].DX := FLbDrifts[n].DX + dx;
  FLbDrifts[n].DY := FLbDrifts[n].DY + dy;
  FLbDriftW := Width;
  FLbDriftH := Height;
  DropStatic;
  InvalidateFrame;
end;

function TTyCustomAdvanceChart.LbDriftOf(ASeries, AData: Integer; out ADX,
  ADY: Double): Boolean;
var k: Integer;
begin
  ADX := 0;
  ADY := 0;
  Result := False;
  { another size lays every label out again (resize's update) }
  if (Length(FLbDrifts) > 0) and ((FLbDriftW <> Width) or (FLbDriftH <> Height)) then
    FLbDrifts := nil;
  for k := 0 to High(FLbDrifts) do
    if (FLbDrifts[k].S = ASeries) and (FLbDrifts[k].D = AData) then
    begin
      ADX := FLbDrifts[k].DX;
      ADY := FLbDrifts[k].DY;
      Exit(True);
    end;
end;

procedure TTyCustomAdvanceChart.GuideLineStyle(const ANodes: TTyStNodeArray;
  const APath: array of string; var AStyle: TTyChartElementStyle);
var
  p: array of string;
  i, j: Integer;
  d, typ: TJSONData;
  c: TTyChartColor;
  v: Double;

  function At(const AKey: string): TJSONData;
  begin
    p[High(p)] := AKey;
    Result := TyStFind(ANodes, p);
  end;

  function NumOf(D: TJSONData; out V: Double): Boolean;
  begin
    Result := (D <> nil) and (D.JSONType = jtNumber);
    if Result then V := D.AsFloat else V := NaN;
    if Result and IsNan(V) then Result := False;
  end;

begin
  SetLength(p, Length(APath) + 1);
  for i := 0 to High(APath) do p[i] := APath[i];
  d := At('color');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    AStyle.StrokeColor := c;
  if NumOf(At('width'), v) then AStyle.StrokeWidthLogical := v;
  if NumOf(At('opacity'), v) then AStyle.Alpha := v;
  if NumOf(At('dashOffset'), v) then AStyle.DashOffsetLogical := v;
  if NumOf(At('miterLimit'), v) then AStyle.MiterLimit := v;
  d := At('cap');
  if (d <> nil) and (d.JSONType = jtString) then AStyle.LineCap := TyCapOfWord(d.AsString);
  d := At('join');
  if (d <> nil) and (d.JSONType = jtString) then AStyle.LineJoin := TyJoinOfWord(d.AsString);
  { type: normalizeLineDash against the width the line strokes at -- the
    words as multiples of it (kept as the word, so a state's width carries
    the dash along), a number or an array as lengths }
  typ := At('type');
  if typ = nil then Exit;
  AStyle.DashWord := 0;
  AStyle.DashLogical := nil;
  if typ.JSONType = jtString then
  begin
    if typ.AsString = 'dashed' then AStyle.DashWord := 1
    else if typ.AsString = 'dotted' then AStyle.DashWord := 2;
    if AStyle.DashWord > 0 then
      AStyle.DashLogical := TyDashOfWord(AStyle.DashWord, AStyle.StrokeWidthLogical);
  end
  else if (typ.JSONType = jtNumber) and (AStyle.StrokeWidthLogical > 0) then
  begin
    SetLength(AStyle.DashLogical, 1);
    AStyle.DashLogical[0] := typ.AsFloat;
  end
  else if (typ.JSONType = jtArray) and (AStyle.StrokeWidthLogical > 0) then
  begin
    SetLength(AStyle.DashLogical, typ.Count);
    for j := 0 to typ.Count - 1 do
      AStyle.DashLogical[j] := TyGuideJsNumber(typ.Items[j], NaN);
  end;
end;

procedure TTyCustomAdvanceChart.StyleOwnGuides(ASlot: Integer; AList: TTyPaintList;
  AFrom: Integer);
var
  k, si, raw: Integer;
  pe: PTyChartElement;
  st: TTyChartElementStyle;
begin
  if (AList = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  si := FBindings[ASlot].SeriesIndex;
  for k := AFrom to AList.Count - 1 do
  begin
    pe := AList.Ref(k);
    if (pe^.Anim.Role <> carGuide) or (pe^.Datum.SeriesIndex <> si) then Continue;
    raw := pe^.Datum.RawDataIndex;
    if raw < 0 then raw := pe^.Datum.DataIndex;
    { the item's colour and the theme's width under what the chain writes;
      the opacity is the line's own (zrender's default 1 already stands, so
      defaults() never hands it the item's) }
    st := pe^.Style;
    GuideLineStyle(StNodes(si, raw), ['labelLine', 'lineStyle'], st);
    pe^.Style := st;
  end;
end;

procedure TTyCustomAdvanceChart.LabelGround(out AGround: TTyChartColor;
  out ADark: Boolean);
var
  a, l: Double;
  d: TJSONData;
  authored, forced: Boolean;
  k: Integer;
  ch: array[0..2] of Double;
begin
  { the option's ground where it paints one, else the skin's [Batch 83] }
  authored := AuthorBackground(AGround);
  if not authored then
    AGround := TTyChartColor(ActiveController.Model.ResolveStyle(GetStyleTypeKey,
      StyleClass, [tysNormal]).Background.Color);
  { zrender's lum with a background of ONE: what shows through a translucent
    ground counts as white. Dark under 0.4. }
  a := TyChartColorAlpha(AGround);
  l := TyLabelLuminance(AGround) + (1 - a);
  ADark := l < 0.4;
  { darkMode FORCES THE ANSWER when it is a boolean: upstream's
    zr.setDarkMode after the ground set it -- null and 'auto' keep the
    luminance's [Batch 83] }
  forced := False;
  if FOption <> nil then
  begin
    d := FOption.Find('darkMode');
    if (d <> nil) and (d.JSONType = jtBoolean) then
    begin
      ADark := d.AsBoolean;
      forced := True;
    end;
  end;
  { THE GROUND AN OUTSIDE LABEL IS HALOED IN is getOutsideStroke's: the
    background over black when dark, over white when not, made opaque. With
    no background written upstream's is transparent -- black or white
    outright -- which the skin's own ground stands in for unless darkMode was
    forced. [Batch 83] }
  if not authored and forced then AGround := 0;
  if authored or forced then
  begin
    a := TyChartColorAlpha(AGround);
    ch[0] := (AGround shr 16) and $FF;
    ch[1] := (AGround shr 8) and $FF;
    ch[2] := AGround and $FF;
    for k := 0 to 2 do
      if ADark then ch[k] := ch[k] * a
      else ch[k] := ch[k] * a + 255 * (1 - a);
    { the channels as zrender's parse reads the rgba() text the blend makes:
      parseInt, so 127.5 is 127 -- with the alpha as written a half-grey
      ground gives a half channel [F4c] }
    AGround := TTyChartColor($FF000000 or (Cardinal(Trunc(ch[0])) shl 16)
      or (Cardinal(Trunc(ch[1])) shl 8) or Cardinal(Trunc(ch[2])));
  end;
end;
