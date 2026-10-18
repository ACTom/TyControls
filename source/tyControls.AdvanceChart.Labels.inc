{ Part of tyControls.AdvanceChart (included, not a unit): the series labels -- their
  specs, text measurement and the label layout. Moved out of the unit only to keep it
  readable; what the control is and why it is built the way it is, see the unit header. }

procedure TTyAdvanceChart.ResolveTextDims(const AEnc: TTySeriesEncode;
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
    for k := 0 to AStore.DimCount - 1 do
      if (AStore.DimCoord(k) <> '') and (AStore.RawDimPos(k) >= 0)
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
function TTyAdvanceChart.BuildEndLabel(ASlot: Integer; const AVisual: TTySeriesVisual;
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
begin
  Result := 0;
  if (AList = nil) or (AMeasurer = nil) or (ASlot > High(FStores)) then Exit;
  store := FStores[ASlot];
  if store = nil then Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (node is TJSONObject) then Exit;
  en := TJSONObject(node).Find('endLabel');
  if not (en is TJSONObject) then Exit;
  d := TJSONObject(en).Find('show');
  if not ((d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean) then Exit;
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
  spec := TyLabelSpecOfNode(TJSONObject(en), nil, spec);
  horiz := (Round(run.Anim.G[5]) and 2) <> 0;
  inverse := (Round(run.Anim.G[5]) and 4) <> 0;
  connect := run.Anim.G[10] <> 0;
  { each row's raw value, a number or none }
  SetLength(vals, store.Count);
  for row := 0 to store.Count - 1 do
  begin
    vals[row] := NaN;
    it := store.RawItem(row);
    case it.Shape of
      rshNone:
        if (AVisual.LabelValueDim >= 0) and (AVisual.LabelValueDim < store.DimCount) then
          vals[row] := store.Get(AVisual.LabelValueDim, row);
      rshScalar:
        if it.Scalar.Kind = dvkNumber then vals[row] := it.Scalar.Num;
    end;
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
  if (tpl <> '') then
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
  AMeasurer.MeasureLine(words, spec.FontName, spec.FontSizeLogical, spec.FontWeight, w, h);
  el := TyChartElement(TyShapeRect(TyAnchorBox(x, y, w, h, ah, av)));
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
  el.Anim.G[1] := flags;
  el.Anim.G[2] := spec.Precision;
  el.Anim.G[3] := run.Anim.G[8];
  AList.Add(el);
  Result := 1;
end;

{ each data item's own `label`, read over its series' spec, by raw row }
procedure TTyAdvanceChart.ItemLabelSpecs(ASeriesIndex: Integer; const ABase: TTyLabelSpec;
  out ASpecs: TTyLabelSpecArray; out AHas: TTyBoolArray);
var
  node, d, it, lb: TJSONData;
  k: Integer;
begin
  ASpecs := nil;
  AHas := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  SetLength(ASpecs, d.Count);
  SetLength(AHas, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    it := d.Items[k];
    if (it = nil) or (it.JSONType <> jtObject) then Continue;
    lb := TJSONObject(it).Find('label');
    if (lb = nil) or (lb.JSONType <> jtObject) then Continue;
    ASpecs[k] := TyLabelSpecOfNode(TJSONObject(lb), TJSONObject(node), ABase);
    AHas[k] := True;
  end;
end;

function TTyAdvanceChart.LabelSpecFor(ASlot: Integer): TTyLabelSpec;
begin
  Result := LabelSpecFor(ASlot, '');
end;

{ THE THEME HALF OF A LABEL SPEC: fonts, the outside ink and the three
  inside bands, the ground -- everything but what the option says. }
function TTyAdvanceChart.LabelBaseFor(ASlot: Integer): TTyLabelSpec;
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

function TTyAdvanceChart.LabelSpecFor(ASlot: Integer;
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
  Result := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
end;

function TTyAdvanceChart.PieLabelInk: TTyPieLabelInk;
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

function TTyAdvanceChart.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
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

procedure TTyAdvanceChart.LayoutSeriesLabels(AList: TTyPaintList;
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
  fsz: Integer;
  it: TTyLabelLayoutItem;
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
      it := Default(TTyLabelLayoutItem);
      if Length(c.RtPieces) = 0 then
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
      if refs[r].Relaid then
        el.Caption.RtEmph := TyRtReink(refs[r].Pieces, el.Caption.EmphColour, True,
          el.Caption.EmphStrokeColour, el.Caption.EmphStrokeWidthLogical);
      el.Shape := TyShapeRect(TyRtDeviceBox(refs[r].Pieces, el.Caption.X,
        el.Caption.Y, el.Caption.RotationRad, el.Caption.RtScale));
    end
    else
      el.Shape := TyShapeRect(TyAnchorBox(el.Caption.X, el.Caption.Y,
        refs[r].TextW, refs[r].TextH, refs[r].AH, refs[r].AV));
    el.Ignore := items[r].Ignore;
    el.Caption.LmOverlapHidden := items[r].Ignore and not items[r].DefIgnore;
    el.Caption.LmEmphShow := items[r].EmphShow;
    { PLACED AT label.x / y, it no longer rides its host }
    if items[r].Free then
    begin
      el.Caption.LmFree := True;
      el.Anim.HostPlus1 := 0;
    end;
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

procedure TTyAdvanceChart.RouteLabelLines(AList: TTyPaintList;
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
      copies [P2] }
    if AList.Ref(e)^.Caption.LmKind <> 1 then Continue;
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
    { lineStyle over the item's colour (the visual's, by its draw type) }
    col := host.Caption.LgColor;
    txt := TyStReadString(nodes, ['labelLine', 'lineStyle', 'color'], has);
    if has then TyTryParseChartColor(txt, col);
    guide.Style.HasFill := False;
    guide.Style.StrokeColor := col;
    w := TyStReadNumber(nodes, ['labelLine', 'lineStyle', 'width'], has);
    if not has or IsNan(w) then w := 1;
    guide.Style.StrokeWidthLogical := w;
    w := TyStReadNumber(nodes, ['labelLine', 'lineStyle', 'opacity'], has);
    if has and not IsNan(w) then guide.Style.Alpha := w;
    d := TyStFind(nodes, ['labelLine', 'lineStyle', 'type']);
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'dashed') then
      guide.Style.DashLogical := TyDashPattern(todDashed, nil, guide.Style.StrokeWidthLogical)
    else if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'dotted') then
      guide.Style.DashLogical := TyDashPattern(todDotted, nil, guide.Style.StrokeWidthLogical)
    else if (d <> nil) and (d.JSONType = jtArray) then
    begin
      SetLength(guide.Style.DashLogical, d.Count);
      for j := 0 to d.Count - 1 do
        guide.Style.DashLogical[j] := TyGuideJsNumber(d.Items[j], NaN);
    end;
    { a pointer at its datum, never a target }
    guide.Silent := True;
    guide.IsGuide := True;
    guide.Datum := el.Datum;
    guide.Anim.Role := carGuide;
    guide.Anim.Series := si;
    guide.Anim.Index := el.Datum.DataIndex;
    { updateZ: under its host, or over it with showAbove }
    above := TyStReadBool(nodes, ['labelLine', 'showAbove'], has) and has;
    guide.Z := host.Z;
    if above then guide.Z2 := host.Z2 + 1 else guide.Z2 := host.Z2 - 1;
    { hidden where its label is, or where the normal labelLine does not show }
    guide.Ignore := el.Ignore or not showN;
    AList.Add(guide);
  end;
end;

procedure TTyAdvanceChart.LabelGround(out AGround: TTyChartColor;
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
