{ Part of tyControls.AdvanceChart (included, not a unit): painting -- the axes, the static
  and the dynamic layers, the series, and the dirty rectangles. Moved out of the unit only
  to keep it readable; what the control is and why it is built the way it is, see the unit
  header. }

{ ==================== paint ==================== }

{ THE AUTHOR'S PEN OVER THE SKIN'S [R5-B]: the skin's colour and width where
  the pen wrote none. The width the theme asked for is LOGICAL --
  StrokePath scales it itself -- and an undeclared one falls back to one
  logical pixel rather than to zero: a theme that names a colour and no
  width means "draw it", not "draw nothing". Under 0.05 it is 0.05. }
function TyAxisSkinStroke(const APen: TTyAxisPen; const ASkin: TTyStyleSet;
  ACap: TTyAxisCap): TTyAxisStroke;
var w: Double;
begin
  if tpBorderWidth in ASkin.Present then w := ASkin.BorderWidth else w := 1;
  if w < 0.05 then w := 0.05;
  Result := TyAxisStrokeOf(APen, tpBorderColor in ASkin.Present,
    TTyChartColor(ASkin.BorderColor), w, ACap);
end;

{ ONE PIECE OF AN AXIS, its lines already in the painter's path [R5-B]:
  stroked as zrender strokes a path of that style -- the colour and width,
  the dash and its phase, the cap, the opacity as the canvas' globalAlpha --
  inside a saved state, so nothing leaks onto the next piece }
procedure TyStrokeAxisPath(P: TTyPainter; const AStroke: TTyAxisStroke);
var
  bx, by, bw, bh, gx1, gy1, gx2, gy2, gr: Double;
  box: TTyXYWH;
  stops: array of TTyGradStop;
  k: Integer;
begin
  if not AStroke.Drawn then Exit;
  P.SaveState;
  try
    if AStroke.Opacity < 1 then P.SetElementAlpha(AStroke.Opacity);
    P.SetLineDash(AStroke.Dash, AStroke.DashOffset);
    case AStroke.Cap of
      acRound: P.SetLineCap(tlcRound);
      acSquare: P.SetLineCap(tlcSquare);
    else
      P.SetLineCap(tlcButt);
    end;
    { [R7-AA] ITS JOIN, MITERLIMIT AND SHADOW, as getLineStyle hands them to
      the element [was: never drawn] }
    case AStroke.Join of
      1: P.SetLineJoin(tljRound, AStroke.Miter);
      2: P.SetLineJoin(tljBevel, AStroke.Miter);
    else
      P.SetLineJoin(tljMiter, AStroke.Miter);
    end;
    if AStroke.HasShadow and ((AStroke.Shadow.Color shr 24) <> 0)
      and ((AStroke.Shadow.Blur > 0) or (AStroke.Shadow.OffsetX <> 0) or (AStroke.Shadow.OffsetY <> 0)) then
      P.SetShadow(TTyColor(AStroke.Shadow.Color), AStroke.Shadow.Blur, AStroke.Shadow.OffsetX,
        AStroke.Shadow.OffsetY);
    { [R5-G] A GRADIENT PEN: zrender's canvas gradient against the stroked
      element's getBoundingRect -- the path's rect grown by the stroke, a
      fill-less path by max(width, 5) (TyGrowByStroke, as an element's) --
      the whole ramp, not its first stop [was: the first stop] }
    if (AStroke.Gradient.Kind <> cgkNone) and (Length(AStroke.Gradient.Stops) > 0)
      and P.PathBounds(bx, by, bw, bh) then
    begin
      box.X := bx;
      box.Y := by;
      box.W := bw;
      box.H := bh;
      box := TyGrowByStroke(box, False, AStroke.WidthLogical * P.PPI / 96);
      TyResolveGradientXYWH(AStroke.Gradient, box, gx1, gy1, gx2, gy2, gr);
      stops := nil;
      SetLength(stops, Length(AStroke.Gradient.Stops));
      for k := 0 to High(stops) do
      begin
        stops[k].Color := TTyColor(AStroke.Gradient.Stops[k].Color);
        stops[k].Pos := AStroke.Gradient.Stops[k].Offset;
      end;
      P.StrokePathGradient(stops, gx1, gy1, gx2, gy2, gr, AStroke.WidthLogical);
    end
    else
      P.StrokePath(TTyColor(AStroke.Colour), AStroke.WidthLogical);
  finally
    P.RestoreState;
  end;
end;

{ [R5-J] A SPLIT AREA'S GRADIENT, its path already in the painter: the
  canvas gradient over ABox -- the band's own rect where the axis adds a
  Rect per band (cartesian, single), the merged path's box where it merges
  the bands of one colour (polar) -- at AOpacity (areaStyle.opacity, NaN for
  none) as the canvas' globalAlpha }
procedure TyFillAxisGradient(P: TTyPainter; const AGrad: TTyChartGradient;
  const ABox: TTyXYWH; AOpacity: Double);
var
  gx1, gy1, gx2, gy2, gr: Double;
  stops: array of TTyGradStop;
  k: Integer;
begin
  if (AGrad.Kind = cgkNone) or (Length(AGrad.Stops) = 0) then Exit;
  TyResolveGradientXYWH(AGrad, ABox, gx1, gy1, gx2, gy2, gr);
  stops := nil;
  SetLength(stops, Length(AGrad.Stops));
  for k := 0 to High(stops) do
  begin
    stops[k].Color := TTyColor(AGrad.Stops[k].Color);
    stops[k].Pos := AGrad.Stops[k].Offset;
  end;
  P.SaveState;
  try
    if not IsNan(AOpacity) and (AOpacity < 1) then P.SetElementAlpha(Max(0.0, AOpacity));
    P.FillPathGradient(stops, gx1, gy1, gx2, gy2, gr);
  finally
    P.RestoreState;
  end;
end;

{ a fill's colour at AOpacity more (areaStyle.opacity over a band whose
  colour has an alpha of its own), NaN for none written [R5-B] }
function TyAxisAreaAlpha(AColour: TTyColor; AOpacity: Double): TTyColor;
var a: Integer;
begin
  Result := AColour;
  if IsNan(AOpacity) or (AOpacity >= 1) then Exit;
  if AOpacity < 0 then AOpacity := 0;
  a := Round((AColour shr 24) * AOpacity);
  Result := (AColour and $00FFFFFF) or (TTyColor(a) shl 24);
end;

{ [R7-AA] AN AXIS LABEL'S z2: AxisBuilder's `10 + (tick.time?.level || 0)`
  -- a time axis' coarser labels over its finer [was: 10 for every one] }
function TyAxisLabelZ2(AAxis: TTyAxis; ASpec: PTyAxisLayoutSpec; AIndex: Integer): Integer;
var t: TTyScaleTickArray; k: Integer; v: Double;
begin
  Result := 10;
  if (AAxis = nil) or (ASpec = nil) or (AAxis.AxisType <> atTime) then Exit;
  if (AIndex < 0) or (AIndex > High(ASpec^.TickValues)) then Exit;
  v := ASpec^.TickValues[AIndex];
  t := TyDrawnTicks(AAxis.Scale);
  for k := 0 to High(t) do
    if (t[k].Level = 0) and (t[k].Value = v) then
      Exit(10 + Max(0, t[k].TimeLevel));
end;

{ [R7-AA] A PIECE'S PEN BEYOND ITS COLOUR AND WIDTH onto an element's style:
  its shadow, join, miterLimit and gradient. ARun: for the paint order's
  pass (CompRun), a value the canvas refuses written as the pass reads one
  (a join cTyCanvasWordLeft, a miterLimit -1; a shadowColor and a blur are
  so already); else the settled values. }
procedure TyCompStrokeLook(var AStyle: TTyChartElementStyle; const K: TTyAxisStroke;
  ARun: Boolean = False);
begin
  if K.HasShadow then
  begin
    AStyle.ShadowColor := K.Shadow.Color;
    AStyle.ShadowBlur := K.Shadow.Blur;
    AStyle.ShadowOffsetX := K.Shadow.OffsetX;
    AStyle.ShadowOffsetY := K.Shadow.OffsetY;
  end;
  AStyle.LineJoin := K.Join;
  AStyle.MiterLimit := K.Miter;
  if ARun and ((K.Left and cTyCanvasJoinLeft) <> 0) then AStyle.LineJoin := cTyCanvasWordLeft;
  if ARun and ((K.Left and cTyCanvasMiterLeft) <> 0) then AStyle.MiterLimit := -1;
  AStyle.StrokeGradient := K.Gradient;
end;

procedure TTyCustomAdvanceChart.PaintAxis(APainter: TTyPainter; AAxis: TTyAxis;
  const APlot: TTyRectF; APPI: Integer; AGrid: TTyGridBuild;
  const AMeasurer: ITyTextMeasurer; const AZ2: TTyAxisZ2Set; AProxied: Boolean);
var
  akey: string;
  lx, ly: Double;
  model: TTyStyleModel;
  lineS, tickStyle, labelS, splitS: TTyStyleSet;
  lblStyle: TTyStyleSet;
  minorTickS, minorSplitS, nameS: TTyStyleSet;
  i: Integer;
  tickLen, minorLen, at, along, x1, y1, x2, y2: Double;
  maxW, batched: Integer;
  { [R7-AB] the Lines of the batch, where they lie, and their pen; the font
    a text part is drawn in (CompDrawn) }
  pend: TTyZrRectArray;
  pendW: Double;
  drewFont: TTyStyleSet;
  { [R7-AB after R7-AA] the mark of the split line BatchLine draws (-1 for
    another kind), each pending Line's }
  lineIx: Integer;
  pendIx: TTyIntegerArray;
  horiz: Boolean;
  lblH, lblW: Integer;
  scaleTicks: TTyScaleTickArray;
  spec: PTyAxisLayoutSpec;
  places: TTyAxisLabelPlacementArray;
  furn: TTyAxisFurniture;
  areaS: TTyStyleSet;
  bandLo, bandHi: Double;
  { [R5-J] a gradient band's rect }
  gbox: TTyXYWH;
  { the split colours [Batch 101] }
  ink: Integer;
  areaFill: TTyFill;
  view: TTyChartView;
  { [F3b] the proxied areas, minor ticks and name }
  areaR: TRect;
  majors: Integer;
  nx, ny, nrot: Double;
  { the author's pens over the skin [R5-B] }
  lineK, tickK, minorTickK, splitK, minorSplitK, inkK: TTyAxisStroke;
  { [R7-Z] }
  arrowInk: TTyChartColor;
  { [R7-AD] }
  pcs: TTyRtPieceArray;

  { THE BOX IS THE TRANSLATION. The layout layer says "this point, with the
    text hanging off it this way"; the painter aligns text INSIDE a rectangle.
    Building a box that is exactly the text's size around the anchor makes the
    two agree, and makes the alignment argument irrelevant.

    Mapping anchors to LCL alignments instead was the first attempt and it was
    wrong in a way worth remembering: a right-anchored label kept the old
    symmetric box, so right-justifying inside it put the text's right edge a
    whole width PAST the anchor -- straight through the tick marks. }
  { The same two anchors DrawTextRotated wants, which takes the point and the
    alignments rather than a rectangle. }
  function AnchorAlign(AH2: TTyTextAnchorH): TAlignment;
  begin
    case AH2 of
      tahLeft: Result := taLeftJustify;
      tahRight: Result := taRightJustify;
    else Result := taCenter;
    end;
  end;

  function AnchorLayout(AV: TTyTextAnchorV): TTextLayout;
  begin
    case AV of
      tavTop: Result := tlTop;
      tavBottom: Result := tlBottom;
    else Result := tlCenter;
    end;
  end;

  function AnchorBox(AX, AY: Double; AW, AH: Integer;
    AH2: TTyTextAnchorH; AV: TTyTextAnchorV): TRect;
  begin
    case AH2 of
      tahLeft: begin Result.Left := Round(AX); Result.Right := Round(AX) + AW; end;
      tahRight: begin Result.Left := Round(AX) - AW; Result.Right := Round(AX); end;
    else
      begin
        Result.Left := Round(AX - AW / 2);
        Result.Right := Result.Left + AW;
      end;
    end;
    case AV of
      tavTop: begin Result.Top := Round(AY); Result.Bottom := Round(AY) + AH; end;
      tavBottom: begin Result.Top := Round(AY) - AH; Result.Bottom := Round(AY); end;
    else
      begin
        Result.Top := Round(AY - AH / 2);
        Result.Bottom := Result.Top + AH;
      end;
    end;
  end;

  { THE LAYOUT'S OWN MEASURER, not the painter's TextSize. They are two
    different rasterisers -- Measure.pas' header says they disagree by about a
    pixel and that a size floor feeding a clip must take the LARGER, which is
    what the layout does -- so measuring here with the other one made the
    reserved gutter and the drawn box two different numbers. It is also the one
    path that misses the painter's measurement memo. }
  procedure TextSizeOf(const AText: string; const AStyle: TTyStyleSet;
    out AW, AH: Integer);
  var w, h: Double;
  begin
    if AMeasurer = nil then
    begin
      AW := APainter.MeasureText(TyInkText(AText), AStyle.FontName,
        ResolveFontSize(AStyle), AStyle.FontWeight).cx;
      AH := APainter.MeasureText('Wg', AStyle.FontName,
        ResolveFontSize(AStyle), AStyle.FontWeight).cy;
      Exit;
    end;
    AMeasurer.MeasureLine(AText, AStyle.FontName, ResolveFontSize(AStyle),
                          AStyle.FontWeight, w, h);
    AW := Round(w);
    AH := Round(h);
  end;

  { ONE SUBPATH PER LINE, ONE STROKE PER STYLE.

    Every line an axis draws shares a style with its neighbours by
    construction, and a path can hold as many subpaths as it likes -- each
    MoveTo starts a new one -- so a whole set of split lines is one BeginPath, N
    MoveTo/LineTo pairs and one StrokePath. Stroking them one at a time is what
    made a 600-point frame cost 110 ms when the same frame without axes costs
    13: the bill was never pixels, it was the per-call setup, and quartering the
    area did not quarter the time. ECharts survives 100k elements on the same
    trick (canPathBatch: consecutive same-style elements accumulate into one
    beginPath and one fill/stroke).

    SNAPPED as it is added. A stroke whose outer edge falls between two pixel
    rows lights both at half alpha, which is what makes a 1 px grid read grey
    and soft next to the crisp control chrome around it.

    TWO UNITS, DELIBERATELY. The snap works in DEVICE px -- the pixel grid the
    ink lands on is the device one, so snapping a logical coordinate would mean
    nothing -- while StrokePath wants the LOGICAL width and scales it itself.
    Handing the scaled width to both is a double scale that 96 DPI hides
    completely, which is how the first version of this passed. }
  { one arrow of the axis line: the symbol in its box about (0, 0), turned
    and moved as the element is [Batch 101] }
  procedure PaintAxisArrow(P: TTyPainter; const AArrow: TTyAxisArrow;
    AColour: TTyChartColor);
  var
    el: TTyChartElement;
    path: TTyZrPath;
    t: string;
    empty: Boolean;
  begin
    if TyAxisArrowImage(AArrow, el) then
    begin
      TyRenderElement(P, el);
      Exit;
    end;
    t := AArrow.SymbolType;
    empty := Copy(t, 1, 5) = 'empty';
    path := TyZrSymbol(t, -AArrow.W / 2, -AArrow.H / 2, AArrow.W, AArrow.H);
    if Length(path) = 0 then Exit;
    el := Default(TTyChartElement);
    el.Style.Alpha := 1;
    el.Shape := TyMkZrShape(path, TyZrLocal(1, 1, AArrow.Rotation, AArrow.X,
      AArrow.Y), True);
    if empty then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(model.ResolveStyle(
        'TyAdvChartEmptyCircle', '', []).Background.Color);
      el.Style.StrokeColor := AColour;
      el.Style.StrokeWidthLogical := 2;
    end
    else if t = 'line' then
    begin
      el.Style.StrokeColor := AColour;
      el.Style.StrokeWidthLogical := 1;
    end
    else
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := AColour;
    end;
    TyRenderElement(P, el);
  end;

  procedure BatchLine(AX1, AY1, AX2, AY2: Double; AWidthLogical: Double);
  var n: Integer;
  begin
    { ([R7-AG] at another PPI on the css px grid [was: the device px
      grid]) }
    if APainter.ScaleF(1) <> 1 then
    begin
      if APainter.ScaleF(AWidthLogical) > 0 then
        TyZrSubPixelLineAt(AX1, AY1, AX2, AY2, APainter.ScaleF(AWidthLogical), APainter.ScaleF(1));
    end
    else
      TySubPixelLine(AX1, AY1, AX2, AY2, APainter.ScaleF(AWidthLogical));
    APainter.MoveTo(AX1, AY1);
    APainter.LineTo(AX2, AY2);
    Inc(batched);
    { [R7-AB] a Line each: where it lies }
    n := Length(pend);
    SetLength(pend, n + 1);
    pend[n] := TyRectToXYWH(TyRectF(Min(AX1, AX2), Min(AY1, AY2), Max(AX1, AX2), Max(AY1, AY2)));
    pendW := APainter.ScaleF(AWidthLogical);
    SetLength(pendIx, n + 1);
    pendIx[n] := lineIx;
  end;

  { [R7-Z] a part as it is drawn (CompDrawn): its pen, or its text's fill }
  procedure Drew(AKind: Byte; AZ2: Integer; const AStroke: TTyAxisStroke;
    AText: Boolean; AFill: TTyChartColor);
  var e: TTyChartElement;
  begin
    e := Default(TTyChartElement);
    e.Style.Alpha := 1;
    if AText then
    begin
      e.Caption.FontSizeLogical := 1;
      e.Caption.Text := 'x';
      e.Caption.Colour := AFill;
      { [R7-AB] and the font it is drawn in }
      e.Caption.FontName := drewFont.FontName;
      e.Caption.FontSizeLogical := ResolveFontSize(drewFont);
      e.Caption.FontWeight := drewFont.FontWeight;
    end
    else if AKind in [cpkSplitArea, cpkArrow] then
    begin
      e.Style.HasFill := True;
      e.Style.FillColor := AFill;
    end
    else
    begin
      e.Style.StrokeColor := AStroke.Colour;
      e.Style.StrokeWidthLogical := AStroke.WidthLogical;
      e.Style.DashLogical := Copy(AStroke.Dash, 0, Length(AStroke.Dash));
      e.Style.DashOffsetLogical := AStroke.DashOffset;
      e.Style.LineCap := Ord(AStroke.Cap);
      { [R7-AA] its shadow, join, miterLimit and gradient }
      TyCompStrokeLook(e.Style, AStroke);
    end;
    CompDrew(AAxis, AAxis.MainType + IntToStr(AAxis.ComponentIndex), AKind, AZ2, AText, e);
  end;

  { Stroke what BatchLine collected, if anything. The count guards a stroke of
    an empty path, which a fully thinned-away set of minor ticks produces.
    In the piece's own pen [R5-B: in the skin's colour and width]. }
  procedure StrokeBatch(const AStroke: TTyAxisStroke; AKind: Byte; AZ2: Integer);
  var k: Integer; sb, sx, sy: Double;
  begin
    if batched > 0 then
    begin
      TyStrokeAxisPath(APainter, AStroke);
      if AStroke.Drawn then Drew(AKind, AZ2, AStroke, False, 0);
      { [R7-AB] where its Lines are -- [R7-AB after R7-AA] each its mark, and
        the shadow its pen casts (getPaintRect grows by it) }
      sb := 0;
      sx := 0;
      sy := 0;
      if AStroke.HasShadow then
      begin
        if not (IsNan(AStroke.Shadow.Blur) or IsInfinite(AStroke.Shadow.Blur)) then
          sb := APainter.ScaleF(AStroke.Shadow.Blur);
        if not (IsNan(AStroke.Shadow.OffsetX) or IsInfinite(AStroke.Shadow.OffsetX)
          or TyPhaseLeft(AStroke.Shadow.OffsetX)) then
          sx := APainter.ScaleF(AStroke.Shadow.OffsetX);
        if not (IsNan(AStroke.Shadow.OffsetY) or IsInfinite(AStroke.Shadow.OffsetY)
          or TyPhaseLeft(AStroke.Shadow.OffsetY)) then
          sy := APainter.ScaleF(AStroke.Shadow.OffsetY);
      end;
      for k := 0 to High(pend) do CompRect(AAxis, AKind, pend[k], pendW, False, pendIx[k], sb, sx, sy);
    end;
    batched := 0;
    pend := nil;
    pendIx := nil;
  end;

  { [R7-AB] a text of AW x AH at (AX, AY) as anchored, turned by ARot about
    its anchor: the box round it }
  procedure TextRect(AKind: Byte; AX, AY: Double; AW, AH: Integer; AH2: TTyTextAnchorH;
    AV: TTyTextAnchorV; ARot: Double);
  var b: TRect; r: TTyXYWH; c, s, x, y: Double; k: Integer;
    xs, ys: array[0..3] of Double;
  begin
    b := AnchorBox(AX, AY, AW, AH, AH2, AV);
    if Abs(ARot) < 1e-9 then
      r := TyRectToXYWH(TyRectF(b.Left, b.Top, b.Right, b.Bottom))
    else
    begin
      c := Cos(ARot);
      s := Sin(ARot);
      xs[0] := b.Left; ys[0] := b.Top;
      xs[1] := b.Right; ys[1] := b.Top;
      xs[2] := b.Right; ys[2] := b.Bottom;
      xs[3] := b.Left; ys[3] := b.Bottom;
      r := TyRectToXYWH(TyRectF(AX, AY, AX, AY));
      for k := 0 to 3 do
      begin
        { counter-clockwise on the screen }
        x := AX + (xs[k] - AX) * c + (ys[k] - AY) * s;
        y := AY - (xs[k] - AX) * s + (ys[k] - AY) * c;
        TyZrRectUnion(r, TyRectToXYWH(TyRectF(x, y, x, y)));
      end;
    end;
    CompRect(AAxis, AKind, r, 0, True);
  end;

  { A LEAF IN ITS groupTransition [Batch 96]: the line where its proxy is
    now -- upstream's shape, already on the pixel grid at its ends and drawn
    as it is in between -- when the axis is drawn from its proxies }
  function ProxLine(const AAnid: string): Boolean;
  var p: TTyChartAnimProxy;
  begin
    Result := False;
    if not AProxied then Exit;
    p := AxisProxyOf(TyAxisAnimKey(akey, AAnid));
    if p = nil then Exit;
    APainter.MoveTo(p.Num('shape.x1'), p.Num('shape.y1'));
    APainter.LineTo(p.Num('shape.x2'), p.Num('shape.y2'));
    Inc(batched);
    Result := True;
  end;

  { ... a split area's rect [F3b] }
  function ProxArea(const AAnid: string; out ARect: TRect): Boolean;
  var p: TTyChartAnimProxy;
  begin
    Result := False;
    if not AProxied then Exit;
    p := AxisProxyOf(TyAxisAnimKey(akey, AAnid));
    if p = nil then Exit;
    ARect := Rect(Round(p.Num('shape.x')), Round(p.Num('shape.y')),
      Round(p.Num('shape.x') + p.Num('shape.width')),
      Round(p.Num('shape.y') + p.Num('shape.height')));
    Result := True;
  end;

  { ... the name's anchor and turn [F3b] }
  procedure ProxName(var AX, AY, ARot: Double);
  var p: TTyChartAnimProxy;
  begin
    if not AProxied then Exit;
    p := AxisProxyOf(TyAxisAnimKey(akey, 'name'));
    if p = nil then Exit;
    AX := p.Num('x');
    AY := p.Num('y');
    ARot := p.Num('rotation');
  end;

  { ... and a label's anchor }
  procedure ProxLabel(AIndex: Integer; var AX, AY: Double);
  var p: TTyChartAnimProxy;
  begin
    if not AProxied or (spec = nil) or (AIndex > High(spec^.TickValues)) then Exit;
    p := AxisProxyOf(TyAxisAnimKey(akey,
      TyAxisLabelAnid(spec^.TickValues[AIndex], AxisByTick(AAxis))));
    if p = nil then Exit;
    AX := p.Num('x');
    AY := p.Num('y');
  end;

begin
  if AAxis = nil then Exit;
  { [R5-J] on the zlevel PaintZLevels draws now }
  if not ApartIn(AxisModelZLevel(AAxis)) then Exit;
  akey := AAxis.MainType + IntToStr(AAxis.ComponentIndex);
  { `show: false` means "do not draw me". The axis still exists and its series
    still map to pixels; only the domain, ticks, labels and split lines go. }
  if not AAxis.Visible then Exit;
  { a cartesian axis' view: hidden by excludeComponents, else drawn
    [Batch 106] }
  if TyChartViewOf(AAxis.MainType, view) and (view in [cvXAxis, cvYAxis]) then
  begin
    if ViewHidden(view) then Exit;
    ViewDrew(view);
  end;
  model := ActiveController.Model;
  { A foreign typeKey is resolved by asking the model directly -- there is no
    per-part helper in this library and inventing one here would be a second
    idiom for the same thing. }
  lineS := model.ResolveStyle('TyAdvChartAxisLine', '', []);
  minorTickS := model.ResolveStyle('TyAdvChartMinorTick', '', []);
  minorSplitS := model.ResolveStyle('TyAdvChartMinorSplitLine', '', []);
  tickStyle := model.ResolveStyle('TyAdvChartAxisTick', '', []);
  splitS := model.ResolveStyle('TyAdvChartSplitLine', '', []);
  areaS := model.ResolveStyle('TyAdvChartSplitArea', '', []);

  horiz := AAxis.Horizontal;
  { WHERE THE AXIS SITS, asked of the build rather than worked out here: the
    plot's edge, that edge pushed out by `offset`, or the other family's zero
    when `axisLine.onZero` applies. Three alternatives and one answer.

    THE LABELS DO NOT FOLLOW IT TO ZERO. Upstream carries a `labelOffset`
    back to the raw edge precisely so that a chart with negative values has
    its axis line through the middle and its category names still along the
    bottom. The offset, by contrast, DOES move them -- that offset survives
    into labelOffset. }
  if horiz then at := APlot.Bottom else at := APlot.Left;
  if AAxis.Side = asTop then at := APlot.Top;
  if AAxis.Side = asRight then at := APlot.Right;
  if AGrid <> nil then at := AGrid.AxisLineCoord(AAxis, APPI);


  { THE THINNING STEP, READ FROM THE LAYOUT. It used to be computed halfway
    down this procedure, after the split lines had already been drawn -- so the
    ticks thinned with the labels and the lines behind them did not, which is an
    axis wearing a grid and a set of numbers that disagree about how many
    divisions it has.

    And it used to be computed AT ALL here: TyAxisLabelStep measures every
    label, so a frame spent ten thousand measurements at 5,000 categories to
    choose the twenty it would draw. Phase C already measured them to shrink the
    plot rect; it records what it decided and this reads it. }
  spec := nil;
  if AGrid <> nil then spec := AGrid.SpecFor(AAxis);
  { DRAWN IN WHAT IT WAS MEASURED IN [Batch 83] }
  AxisTextStyles(spec, labelS, nameS);
  { WHAT THIS AXIS ACTUALLY DRAWS. Resolved once by the builder, from the
    option AND from upstream's per-type defaults -- which is where most of
    the answers come from: on a chart with no axis option written at all, the
    category axis draws its domain line and nothing else, and the value axis
    draws its split lines and nothing else. }
  furn := Default(TTyAxisFurniture);
  furn.ShowLine := True;
  furn.ShowTicks := True;
  furn.ShowLabels := True;
  furn.LinePen.Cap := -1;
  furn.LinePen.Width := NaN;
  furn.LinePen.Opacity := NaN;
  furn.TickPen := furn.LinePen;
  furn.MinorTickPen := furn.LinePen;
  furn.SplitPen := furn.LinePen;
  furn.MinorSplitPen := furn.LinePen;
  furn.AreaOpacity := NaN;
  if AGrid <> nil then furn := AGrid.FurnitureFor(AAxis);
  { EACH PIECE IN ITS OWN PEN: the author's along upstream's chain, the
    skin's where the author wrote nothing [R5-B: the skin's, whatever the
    option said] }
  lineK := TyAxisSkinStroke(furn.LinePen, lineS, acRound);
  tickK := TyAxisSkinStroke(furn.TickPen, tickStyle, acButt);
  minorTickK := TyAxisSkinStroke(furn.MinorTickPen, minorTickS, acButt);
  splitK := TyAxisSkinStroke(furn.SplitPen, splitS, acButt);
  minorSplitK := TyAxisSkinStroke(furn.MinorSplitPen, minorSplitS, acButt);
  { [R7-Z] WHAT THE CANVAS REFUSES OF EACH -- a colour no parser reads, an
    infinite width, a phase that is no number, a word that is not a cap --
    it strokes with what it had there, in upstream's paint order (CompRun)
    [was: not stroked, or the skin's] }
  CompSettlePen(AAxis, cpkLine, lineK);
  CompSettlePen(AAxis, cpkTick, tickK);
  CompSettlePen(AAxis, cpkMinorTick, minorTickK);
  CompSettlePen(AAxis, cpkSplit, splitK);
  CompSettlePen(AAxis, cpkMinorSplit, minorSplitK);
  labelS.TextColor := TTyColor(CompSettleFill(AAxis, cpkLabel, TTyChartColor(labelS.TextColor)));
  nameS.TextColor := TTyColor(CompSettleFill(AAxis, cpkName, TTyChartColor(nameS.TextColor)));

  { THE TICK'S LENGTH, and it has to be asked AFTER the two lines above. It
    used to be asked first -- reading `spec` and `furn` before either was
    resolved, so an authored `axisTick.length` and `axisTick.inside` were both
    decided by whatever was on the stack. The layout half was right and the
    paint half was reading uninitialised memory, which is a difference no
    assertion about the plot rectangle could ever see. }
  { THE SPEC'S LENGTH, not the theme metric over again: FillSpec has already
    laid the option over the theme, and the layout reserved the gutter from
    exactly that number. Asking the theme a second time here is how the
    reserved band and the drawn mark come to disagree. }
  tickLen := APainter.ScaleF(ActiveController.Metric(TyAdvChartTickLenVar,
    TyAdvChartTickLen));
  if spec <> nil then tickLen := APainter.ScaleF(spec^.TickLengthLogical);
  minorLen := APainter.ScaleF(ActiveController.Metric(TyAdvChartMinorTickLenVar,
    TyAdvChartMinorTickLen));
  if not IsNan(furn.MinorTickLengthLogical) then
    minorLen := APainter.ScaleF(furn.MinorTickLengthLogical);
  { INSIDE TURNS THEM ROUND -- BOTH OF THEM. A negative length points the mark
    into the plot, which is the whole of what the option does, and the layout
    has already stopped reserving room outside for it. There is no
    `minorTick.inside`: upstream flips one tickDirection and every mark on the
    axis follows it, so majors pointing in with minors still pointing out is
    not a state upstream can reach. }
  if furn.TickInside then
  begin
    tickLen := -tickLen;
    minorLen := -minorLen;
  end;
  { THE FURNITURE FOLLOWS THE LABELS UNLESS IT WAS TOLD OTHERWISE -- and
    where each tick, split line and split-area edge goes, and whether it is
    drawn, the layout has already decided (spec^.TickMarks and the rest).
    This draws that answer. }
  batched := 0;

  { Split lines first, so the domain and the ticks sit on top of them.

    TickCoords' default, NOT AAlignWithLabel: a split line divides the bands, it
    does not point at a label. On a banded category axis the two differ by half
    a band, which is exactly the width the whole parameter exists to express. }
  { THE MINOR ONES AFTER THE MAJOR ONES, as upstream adds them. The two theme
    keys have been in light.tycss since item 18 with nothing that could ever be
    drawn with them: every generator wrote Level 0.
    [Revised in R7-AA: minor first.] }
  { MINORS ONLY WHILE THE MAJORS ARE ALL THERE. A minor tick subdivides the
    interval between two majors, so once the majors are being hidden the
    subdivisions of an interval nobody can see are noise -- and they are the
    densest thing on the axis, which makes them the worst noise to keep. }
  { SPLIT AREAS FIRST, because everything else is drawn ON them. Alternating
    bands between consecutive divisions -- so N divisions give N-1 bands, and
    the ones the theme paints are every other one. The key has been in
    light.tycss since item 18 with nothing that could draw with it.

    THE BANDS RUN BETWEEN THE SPLIT LINES, which on a banded category axis
    means between the band EDGES: one shaded band per category, which is what
    makes the alternating stripe line up with the bars rather than straddle
    them. }
  { BETWEEN THE EDGES THE LAYOUT PUT -- on the split area's own interval,
    the labels' unless it says otherwise.
    [Revised in batch 40: between every band edge, whatever the labels
    were doing.] }
  { IN THE COLOUR THE LAYOUT GAVE EACH BAND [Batch 101]: the author's list
    in turn, or the skin's colour and none in turn -- upstream's default is
    a tint and a transparent -- and a band keeps the colour it had at the
    last render, so the stripes do not swap under a zoom.
    [Revised in batch 101: every other band in the skin's colour, from the
    first band of each render.] }
  if (0 in AZ2) and furn.ShowSplitArea and (spec <> nil) then
  begin
    for i := 0 to High(spec^.SplitAreaMarks) - 1 do
    begin
      if not spec^.SplitAreaMarks[i].Drawn then Continue;
      ink := spec^.SplitAreaMarks[i].ColourIndex;
      areaFill := areaS.Background;
      if Length(spec^.SplitAreaInks) > 0 then
      begin
        { a string is one colour for every band, whatever its count says }
        if ink > High(spec^.SplitAreaInks) then ink := 0;
        if not spec^.SplitAreaInks[ink].Ok then Continue;
        areaFill.Kind := tfkSolid;
        areaFill.Color := TTyColor(spec^.SplitAreaInks[ink].Colour);
        { [R7-Z] a colour the canvas refuses: the fill it had at the band }
        if spec^.SplitAreaInks[ink].Colour = cTyCanvasColourLeft then
          areaFill.Color := TTyColor(CompBandInk(AAxis, cpkSplitArea, i));
      end
      else if (ink <> 0) or not (tpBackground in areaS.Present) then
        Continue;
      { ([R7-AA] the band as drawn: CompDrawn) }
      CompDrewArea(AAxis, TTyChartColor(areaFill.Color));
      { [R7-AB after R7-AA] where the band's Rect lies (its part's index) }
      if ProxArea('area_' + TyJsNumberToString(spec^.SplitAreaMarks[i].Value), areaR) then
        CompRect(AAxis, cpkSplitArea, TyRectToXYWH(TyRectF(areaR.Left, areaR.Top, areaR.Right,
          areaR.Bottom)), 0, False, i)
      else if horiz then
        CompRect(AAxis, cpkSplitArea, TyRectToXYWH(TyRectF(
          Min(spec^.SplitAreaMarks[i].Coord, spec^.SplitAreaMarks[i + 1].Coord), APlot.Top,
          Max(spec^.SplitAreaMarks[i].Coord, spec^.SplitAreaMarks[i + 1].Coord), APlot.Bottom)), 0, False, i)
      else
        CompRect(AAxis, cpkSplitArea, TyRectToXYWH(TyRectF(APlot.Left,
          Min(spec^.SplitAreaMarks[i].Coord, spec^.SplitAreaMarks[i + 1].Coord), APlot.Right,
          Max(spec^.SplitAreaMarks[i].Coord, spec^.SplitAreaMarks[i + 1].Coord))), 0, False, i);
      { areaStyle.opacity over the band's own alpha [R5-B] }
      areaFill.Color := TyAxisAreaAlpha(areaFill.Color, furn.AreaOpacity);
      bandLo := spec^.SplitAreaMarks[i].Coord;
      bandHi := spec^.SplitAreaMarks[i + 1].Coord;
      { [R5-J] A GRADIENT: rectCoordAxisBuildSplitArea adds a Rect per band,
        so the ramp spans the band's own rect -- at the band's float edges,
        the grid's rect across [was: the first stop, every band] }
      if (Length(spec^.SplitAreaInks) > 0)
        and (spec^.SplitAreaInks[ink].Grad.Kind <> cgkNone) then
      begin
        if ProxArea('area_' + TyJsNumberToString(spec^.SplitAreaMarks[i].Value), areaR) then
          gbox := TyRectToXYWH(TyRectF(areaR.Left, areaR.Top, areaR.Right, areaR.Bottom))
        else if horiz then
        begin
          gbox.X := bandLo;
          gbox.Y := APlot.Top;
          gbox.W := bandHi - bandLo;
          gbox.H := APlot.Bottom - APlot.Top;
        end
        else
        begin
          gbox.X := APlot.Left;
          gbox.Y := bandLo;
          gbox.W := APlot.Right - APlot.Left;
          gbox.H := bandHi - bandLo;
        end;
        APainter.BeginPath;
        APainter.MoveTo(gbox.X, gbox.Y);
        APainter.LineTo(gbox.X + gbox.W, gbox.Y);
        APainter.LineTo(gbox.X + gbox.W, gbox.Y + gbox.H);
        APainter.LineTo(gbox.X, gbox.Y + gbox.H);
        APainter.ClosePath;
        { a rect of a negative extent (an inverse axis): its box is the
          normalised one, as the canvas fills it }
        TyFillAxisGradient(APainter, spec^.SplitAreaInks[ink].Grad,
          TyRectToXYWH(TyRectF(Min(gbox.X, gbox.X + gbox.W), Min(gbox.Y, gbox.Y + gbox.H),
            Max(gbox.X, gbox.X + gbox.W), Max(gbox.Y, gbox.Y + gbox.H))), furn.AreaOpacity);
        Continue;
      end;
      { where its groupTransition has it now [F3b] }
      if ProxArea('area_' + TyJsNumberToString(spec^.SplitAreaMarks[i].Value), areaR) then
        APainter.FillBackground(areaR, areaFill, 0)
      else if horiz then
        APainter.FillBackground(
          Rect(Round(bandLo), Round(APlot.Top),
               Round(bandHi), Round(APlot.Bottom)), areaFill, 0)
      else
        APainter.FillBackground(
          Rect(Round(APlot.Left), Round(bandLo),
               Round(APlot.Right), Round(bandHi)), areaFill, 0);
    end;
  end;

  { WHERE THE LAYOUT PUT THEM: the split line's own interval, the labels'
    unless it says otherwise, on the band edges of a banded axis with the
    closing edge; the two on the ends separately deniable -- a grid line on
    the axis' own extreme doubles whatever border is already there.
    [Revised in batch 40: every tickStep-th band edge, the stride of
    axisTick.interval when there was one, and no closing edge unless the
    count suited it.] }
  { ONE STROKE PER COLOUR OF THE AUTHOR'S LIST, each line in the colour its
    count among the drawn lines gives it; the skin's one colour when none
    was written [Batch 101] }
  if (0 in AZ2) and furn.ShowSplitLine and (spec <> nil)
    and (splitK.Drawn or ((Length(spec^.SplitLineInks) > 0)
      and (splitK.WidthLogical > 0))) then
  begin
    for ink := 0 to Max(0, High(spec^.SplitLineInks)) do
    begin
      inkK := splitK;
      if Length(spec^.SplitLineInks) > 0 then
      begin
        if not spec^.SplitLineInks[ink].Ok then Continue;
        inkK.Colour := spec^.SplitLineInks[ink].Colour;
        inkK.Gradient := spec^.SplitLineInks[ink].Grad;
        inkK.Drawn := True;
        { [R7-Z] a colour the canvas refuses: the one it had at its first line }
        if inkK.Colour = cTyCanvasColourLeft then inkK.Colour := CompInkOf(AAxis, cpkSplit, ink);
      end;
      APainter.BeginPath;
      for i := 0 to High(spec^.SplitLineMarks) do
      begin
        if not spec^.SplitLineMarks[i].Drawn then Continue;
        if (Length(spec^.SplitLineInks) > 0)
          and (spec^.SplitLineMarks[i].ColourIndex <> ink) then Continue;
        if ProxLine('line_' + TyJsNumberToString(spec^.SplitLineMarks[i].Value)) then Continue;
        along := spec^.SplitLineMarks[i].Coord;
        { ([R7-AB after R7-AA] its mark: the part it is) }
        lineIx := i;
        if horiz then
          BatchLine(along, APlot.Top, along, APlot.Bottom, splitK.WidthLogical)
        else
          BatchLine(APlot.Left, along, APlot.Right, along, splitK.WidthLogical);
        lineIx := -1;
        { [R5-G] a Line per split line too (CartesianAxisView, not merged) }
        if (inkK.Gradient.Kind <> cgkNone) or inkK.HasShadow then
        begin
          StrokeBatch(inkK, cpkSplit, 0);
          APainter.BeginPath;
        end;
      end;
      StrokeBatch(inkK, cpkSplit, 0);
    end;
  end
  { [R7-AD] A WIDTH OF NOUGHT that hands on its colour (a part, Inked):
    nothing stroked, its Line's paint rect the line itself -- a dirty block
    counts it where the line crosses it only [was: every block] }
  else if (0 in AZ2) and furn.ShowSplitLine and (spec <> nil)
    and (splitK.Inked or (Length(spec^.SplitLineInks) > 0)) then
    for i := 0 to High(spec^.SplitLineMarks) do
    begin
      if not spec^.SplitLineMarks[i].Drawn then Continue;
      along := spec^.SplitLineMarks[i].Coord;
      if horiz then
        CompPenRect(APainter, AAxis, cpkSplit, splitK, TyRectToXYWH(TyRectF(along, APlot.Top,
          along, APlot.Bottom)), False, i)
      else
        CompPenRect(APainter, AAxis, cpkSplit, splitK, TyRectToXYWH(TyRectF(APlot.Left, along,
          APlot.Right, along)), False, i);
    end;

  { [R7-AA] THE MINOR SPLIT LINES AFTER THE SPLIT LINES, as
    CartesianAxisView's builders run (splitArea, splitLine, minorSplitLine)
    [was: before them] }
  { WHATEVER THE LABELS ARE DOING: upstream subdivides every interval.
    [Revised in batch 40: only while every major label was drawn.] }
  if (0 in AZ2) and furn.ShowMinorSplitLine and minorSplitK.Drawn then
  begin
    scaleTicks := TyDrawnTicks(AAxis.Scale);
    APainter.BeginPath;
    for i := 0 to High(scaleTicks) do
    begin
      if scaleTicks[i].Level = 0 then Continue;
      { [F3b] }
      if ProxLine('minor_line_' + TyJsNumberToString(scaleTicks[i].Value)) then Continue;
      along := AAxis.DataToCoord(scaleTicks[i].Value);
      if horiz then
        BatchLine(along, APlot.Top, along, APlot.Bottom, minorSplitK.WidthLogical)
      else
        BatchLine(APlot.Left, along, APlot.Right, along, minorSplitK.WidthLogical);
      { [R5-G] CartesianAxisView: a Line per minor split line -- a gradient
        over each one's box; [R7-AA] a shadow under each one }
      if (minorSplitK.Gradient.Kind <> cgkNone) or minorSplitK.HasShadow then
      begin
        StrokeBatch(minorSplitK, cpkMinorSplit, 0);
        APainter.BeginPath;
      end;
    end;
    StrokeBatch(minorSplitK, cpkMinorSplit, 0);
  end
  { [R7-AD] (of no width: where its Lines lie) }
  else if (0 in AZ2) and furn.ShowMinorSplitLine and minorSplitK.Inked then
  begin
    scaleTicks := TyDrawnTicks(AAxis.Scale);
    for i := 0 to High(scaleTicks) do
    begin
      if scaleTicks[i].Level = 0 then Continue;
      along := AAxis.DataToCoord(scaleTicks[i].Value);
      if horiz then
        CompPenRect(APainter, AAxis, cpkMinorSplit, minorSplitK, TyRectToXYWH(TyRectF(along,
          APlot.Top, along, APlot.Bottom)), False)
      else
        CompPenRect(APainter, AAxis, cpkMinorSplit, minorSplitK, TyRectToXYWH(TyRectF(APlot.Left,
          along, APlot.Right, along)), False);
    end;
  end;

  { THE AXIS NAME, WHERE THE LAYOUT PUT IT. The grid was shrunk for the
    name's box on its estimate pass and the name laid out again on the final
    rect -- at its location and gap, turned and aligned as upstream turns and
    aligns it, and moved clear of the labels -- so this draws that answer
    and works nothing out: a second route here is how the name used to land
    beside the band that was reserved for it. }
  { [R7-AD] the name before the line (z2 1 both, the name added first)
    [was: after the ticks] }
  if (1 in AZ2) and (spec <> nil) and spec^.NamePlacement.Shown
    and (tpTextColor in nameS.Present) then
  begin
    { where its groupTransition has it now [F3b] }
    nx := spec^.NamePlacement.X;
    ny := spec^.NamePlacement.Y;
    nrot := spec^.NamePlacement.RotationRad;
    ProxName(nx, ny, nrot);
    { [R7-AB] a font the canvas refused: the one the paint order settled }
    CompFont(AAxis, cpkName, nameS);
    drewFont := nameS;
    Drew(cpkName, 1, lineK, True, TTyChartColor(nameS.TextColor));
    { [R7-AB] where it lies }
    TextSizeOf(spec^.NamePlacement.Text, nameS, lblW, lblH);
    TextRect(cpkName, nx, ny, lblW, lblH, spec^.NamePlacement.AnchorH,
      spec^.NamePlacement.AnchorV, nrot);
    { A BLOCK DRAWS ITS PIECES, the skin's ink where no style gave one
      [Batch 86] }
    if Length(spec^.NamePlacement.Rt) > 0 then
    begin
      { [R7-AD] its spans as the paint order settled them }
      pcs := CompPieces(AAxis, cpkName, -1);
      if Length(pcs) <> Length(spec^.NamePlacement.Rt) then pcs := spec^.NamePlacement.Rt;
      TyRenderRtPieces(APainter, pcs, nx, ny, nrot, spec^.RtScale, 1,
        True, nameS.TextColor);
    end
    { LEVEL IS LEVEL: a y axis' end name comes out of the matrices a few
      hundred quadrillionths of a radian off, and the flat path is the one
      that sets a name of several lines }
    else if Abs(nrot) < 1e-9 then
    begin
      TextSizeOf(spec^.NamePlacement.Text, nameS, lblW, lblH);
      APainter.DrawText(
        AnchorBox(nx, ny, lblW, lblH,
          spec^.NamePlacement.AnchorH, spec^.NamePlacement.AnchorV),
        spec^.NamePlacement.Text, nameS.FontName, ResolveFontSize(nameS),
        nameS.FontWeight, nameS.TextColor, taCenter, tlCenter, False, 0, False,
        Pos(#10, spec^.NamePlacement.Text) > 0);
    end
    else
    begin
      TextSizeOf(spec^.NamePlacement.Text, nameS, lblW, lblH);
      DrawRotatedNameLines(APainter, spec^.NamePlacement.Text, nameS.FontName,
        ResolveFontSize(nameS), nameS.FontWeight, nameS.TextColor,
        nx, ny, nrot,
        AnchorAlign(spec^.NamePlacement.AnchorH),
        AnchorLayout(spec^.NamePlacement.AnchorV), lblH);
    end;
  end;

  { The domain line. Present, not colour: an undeclared colour resolves to
    alpha zero, so testing the colour would draw an invisible line and call it
    drawn. }
  if (1 in AZ2) and furn.ShowLine and (lineK.Drawn or (spec <> nil) and (Length(spec^.Arrows) > 0)) then
  begin
    APainter.BeginPath;
    { CUT AT THE BREAKS, each segment already on the pixel grid [Batch 132] }
    if (spec <> nil) and spec^.HasBreakLine then
    begin
      for i := 0 to High(spec^.BreakLineSegs) do
        if not ProxLine(spec^.BreakLineSegs[i].Anid) then
        begin
          APainter.MoveTo(spec^.BreakLineSegs[i].X1, spec^.BreakLineSegs[i].Y1);
          APainter.LineTo(spec^.BreakLineSegs[i].X2, spec^.BreakLineSegs[i].Y2);
          Inc(batched);
        end;
    end
    else if ProxLine('line') then
    else if horiz then
      BatchLine(APlot.Left, at, APlot.Right, at, lineK.WidthLogical)
    else
      BatchLine(at, APlot.Top, at, APlot.Bottom, lineK.WidthLogical);
    StrokeBatch(lineK, cpkLine, 1);
  end
  { [R7-AD] (of no width: where it lies) }
  else if (1 in AZ2) and furn.ShowLine and lineK.Inked then
  begin
    if (spec <> nil) and spec^.HasBreakLine then
    begin
      for i := 0 to High(spec^.BreakLineSegs) do
        CompPenRect(APainter, AAxis, cpkLine, lineK, TyRectToXYWH(TyRectF(
          Min(spec^.BreakLineSegs[i].X1, spec^.BreakLineSegs[i].X2),
          Min(spec^.BreakLineSegs[i].Y1, spec^.BreakLineSegs[i].Y2),
          Max(spec^.BreakLineSegs[i].X1, spec^.BreakLineSegs[i].X2),
          Max(spec^.BreakLineSegs[i].Y1, spec^.BreakLineSegs[i].Y2))), False);
    end
    else if horiz then
      CompPenRect(APainter, AAxis, cpkLine, lineK, TyRectToXYWH(TyRectF(APlot.Left, at,
        APlot.Right, at)), False)
    else
      CompPenRect(APainter, AAxis, cpkLine, lineK, TyRectToXYWH(TyRectF(at, APlot.Top,
        at, APlot.Bottom)), False);
  end;

  { ALIGNED WITH THE LABELS OR WITH THE BAND EDGES. On a banded category axis
    the two are half a band apart, and which one a tick means is exactly what
    the option exists to say -- the split lines above keep the edges either
    way, because a divider that pointed at a label would not divide anything. }
  { THE MARKS WHERE THE LAYOUT PUT THEM, on their own interval or the
    labels', a tick whose label was hidden gone with it.
    [Revised in batch 40: every tickStep-th tick, a hidden label's kept.] }
  if (2 in AZ2) and furn.ShowTicks and tickK.Drawn and (spec <> nil) then
  begin
    APainter.BeginPath;
    for i := 0 to High(spec^.TickMarks) do
    begin
      if not spec^.TickMarks[i].Drawn then Continue;
      if ProxLine('ticks_' + TyJsNumberToString(spec^.TickMarks[i].Value)) then Continue;
      along := spec^.TickMarks[i].Coord;
      if horiz then
      begin
        x1 := along; x2 := along;
        y1 := at;
        if AAxis.Side = asTop then y2 := at - tickLen else y2 := at + tickLen;
      end
      else
      begin
        y1 := along; y2 := along;
        x1 := at;
        if AAxis.Side = asRight then x2 := at + tickLen else x2 := at - tickLen;
      end;
      BatchLine(x1, y1, x2, y2, tickK.WidthLogical);
      { [R5-G] a gradient's box is each tick's own: createTicks makes a
        Line per tick; [R7-AA] so is a shadow }
      if (tickK.Gradient.Kind <> cgkNone) or tickK.HasShadow then
      begin
        StrokeBatch(tickK, cpkTick, 2);
        APainter.BeginPath;
      end;
    end;
    StrokeBatch(tickK, cpkTick, 2);
  end
  { [R7-AD] (of no width: where its Lines lie) }
  else if (2 in AZ2) and furn.ShowTicks and tickK.Inked and (spec <> nil) then
    for i := 0 to High(spec^.TickMarks) do
    begin
      if not spec^.TickMarks[i].Drawn then Continue;
      along := spec^.TickMarks[i].Coord;
      if horiz then
      begin
        if AAxis.Side = asTop then y2 := at - tickLen else y2 := at + tickLen;
        CompPenRect(APainter, AAxis, cpkTick, tickK, TyRectToXYWH(TyRectF(along, Min(at, y2),
          along, Max(at, y2))), False);
      end
      else
      begin
        if AAxis.Side = asRight then x2 := at + tickLen else x2 := at - tickLen;
        CompPenRect(APainter, AAxis, cpkTick, tickK, TyRectToXYWH(TyRectF(Min(at, x2), along,
          Max(at, x2), along)), False);
      end;
    end;

  { Minor MARKS. The difference in LENGTH is what says which is which when both
    are the same colour family -- and how much shorter is the theme's call, not
    a fraction hardcoded here. --advchart-minor-tick-length, its constant and
    its default have all been in place since item 18 with nothing reading them,
    so a skin that set it changed nothing. }
  if (2 in AZ2) and furn.ShowMinorTick and minorTickK.Drawn then
  begin
    scaleTicks := TyDrawnTicks(AAxis.Scale);
    APainter.BeginPath;
    majors := 0;
    for i := 0 to High(scaleTicks) do
    begin
      if scaleTicks[i].Level = 0 then
      begin
        Inc(majors);
        Continue;
      end;
      { [F3b] the interval it subdivides names it }
      if ProxLine('minorticks_' + IntToStr(majors - 1) + '_'
        + TyJsNumberToString(scaleTicks[i].Value)) then Continue;
      along := AAxis.DataToCoord(scaleTicks[i].Value);
      if horiz then
      begin
        x1 := along; x2 := along;
        y1 := at;
        if AAxis.Side = asTop then y2 := at - minorLen
        else y2 := at + minorLen;
      end
      else
      begin
        y1 := along; y2 := along;
        x1 := at;
        if AAxis.Side = asRight then x2 := at + minorLen
        else x2 := at - minorLen;
      end;
      BatchLine(x1, y1, x2, y2, minorTickK.WidthLogical);
      { [R5-G] a Line per minor tick too }
      if (minorTickK.Gradient.Kind <> cgkNone) or minorTickK.HasShadow then
      begin
        StrokeBatch(minorTickK, cpkMinorTick, 2);
        APainter.BeginPath;
      end;
    end;
    StrokeBatch(minorTickK, cpkMinorTick, 2);
  end;


  { PHASE 3 PLACES THEM. It was written with item 12 and never called, so every
    label was drawn at a position worked out here and none was ever thinned --
    a crowded axis simply overlapped. The placement carries the anchor too, so
    layout and paint cannot disagree about where a label went. }
  if (tpTextColor in labelS.Present) and (spec <> nil) and (Length(spec^.Placements) > 0) then
  begin
    places := spec^.Placements;
    for i := 0 to High(places) do
    begin
      if not places[i].Shown then Continue;
      if places[i].Text = '' then Continue;
      { [R7-AD] the labels of the z2 drawn now }
      if not (Min(31, TyAxisLabelZ2(AAxis, spec, i)) in AZ2) then Continue;
      { THE STYLE THE LAYOUT MEASURED IT IN. A time axis' heavier `Mar` in a
        run of day numbers is a `{primary|Mar}` tag, drawn from its pieces
        below in the weight the block was measured in. [Revised in batch
        104: a whole label marked emphasised and drawn in a second style.] }
      lblStyle := labelS;
      { [R7-AB] a font the canvas refused: the one the paint order settled }
      CompFont(AAxis, cpkLabel, lblStyle);
      { where its groupTransition has it now [Batch 96] }
      lx := places[i].X;
      ly := places[i].Y;
      ProxLabel(i, lx, ly);
      drewFont := lblStyle;
      Drew(cpkLabel, TyAxisLabelZ2(AAxis, spec, i), lineK, True, TTyChartColor(lblStyle.TextColor));
      { A BLOCK DRAWS ITS PIECES [Batch 86] }
      if Length(places[i].Rt) > 0 then
      begin
        { [R7-AD] its spans as the paint order settled them (and as drawn:
          CompDrawn) }
        pcs := CompPieces(AAxis, cpkLabel, i);
        if Length(pcs) <> Length(places[i].Rt) then pcs := places[i].Rt;
        if Length(FCompDrawn) > 0 then
          FCompDrawn[High(FCompDrawn)].El.Caption.RtPieces := Copy(pcs, 0, MaxInt);
        TyRenderRtPieces(APainter, pcs, lx, ly,
          spec^.RotationRad, spec^.RtScale, 1, True, lblStyle.TextColor);
        Continue;
      end;
      TextSizeOf(places[i].Text, lblStyle, lblW, lblH);
      { [R7-AB] where it lies }
      TextRect(cpkLabel, lx, ly, lblW, lblH, places[i].AnchorH, places[i].AnchorV,
        spec^.RotationRad);
      { BOUNDED BY axisLabel.width WHEN TRUNCATING, and only then: with no
        bound the box is exactly the text's size, so the ellipsis fitter has
        nothing to bite on and `overflow` would silently do nothing.

        The other two modes need no bound here. `break` arrives already broken
        -- the builder wrapped it, so the box is the wrapped block's size and
        the multi-line flag lays it out -- and `none` is the old behaviour. }
      if (spec^.LabelOverflow = loTruncate)
        and (spec^.LabelWidthLogical > 0) then
      begin
        maxW := Round(APainter.ScaleF(spec^.LabelWidthLogical));
        if maxW < lblW then lblW := maxW;
      end;
      { TURNED, WHEN THE AUTHOR ASKED FOR IT. The layout has measured the
        turned extent since item 12 and nothing ever drew the turn, so an
        `axisLabel: { rotate: 45 }` bought a deeper gutter and put flat text in
        it. Counter-clockwise positive on both sides -- upstream's and the
        painter's -- so the angle passes straight through.

        DrawTextRotated takes the anchor as a POINT plus the alignments that
        say where in the text box it sits, which is what the placement already
        carries; AnchorBox exists only because the flat path needs a rect. }
      if spec^.RotationRad <> 0 then
      begin
        { every line of a label of several, the block as the layout
          measured it [R2-A: the first line only] }
        DrawRotatedNameLines(APainter, places[i].Text, lblStyle.FontName,
          ResolveFontSize(lblStyle), lblStyle.FontWeight, lblStyle.TextColor,
          lx, ly, spec^.RotationRad,
          AnchorAlign(places[i].AnchorH), AnchorLayout(places[i].AnchorV), lblH);
        Continue;
      end;
      APainter.DrawText(
        AnchorBox(lx, ly, lblW, lblH,
                  places[i].AnchorH, places[i].AnchorV),
        places[i].Text, lblStyle.FontName, ResolveFontSize(lblStyle),
        lblStyle.FontWeight, lblStyle.TextColor,
        LevelLinesAlign(places[i].Text, places[i].AnchorH), tlCenter,
        { ELLIPSIS AND MULTI-LINE, both of which the painter has always had and
          this never asked for: a label was drawn as one clipped line whatever
          it contained, so a wrapped one lost every row after the first. }
        spec^.LabelOverflow = loTruncate, 0, False,
        Pos(#10, places[i].Text) > 0);
    end;
  end;

  { [R7-AD] THE ARROWS LAST (z2 11), after the labels [was: with the line] }
  if (11 in AZ2) and furn.ShowLine and (lineK.Drawn or (spec <> nil) and (Length(spec^.Arrows) > 0)) then
  begin
    { THE ARROWS, over the line (z2 11 to its 1), in its colour: a symbol's
      setColor fills it -- strokes a `line`, rings an `empty` one round the
      skin's empty-symbol ground [Batch 101]. The line's colour, the
      author's where written, without its opacity: createSymbol is handed
      lineStyle.stroke alone [R5-B] }
    if (spec <> nil) and not furn.LinePen.ColourNone
      and (furn.LinePen.HasColour or (tpBorderColor in lineS.Present)) then
      for i := 0 to High(spec^.Arrows) do
      begin
        { [R7-Z] a colour the canvas refuses: the fill it had there }
        arrowInk := CompSettleFill(AAxis, cpkArrow, lineK.Colour);
        PaintAxisArrow(APainter, spec^.Arrows[i], arrowInk);
        Drew(cpkArrow, 11, lineK, False, arrowInk);
        { [R7-AB] (its box, turned any way) }
        CompRect(AAxis, cpkArrow, TyRectToXYWH(TyRectF(
          spec^.Arrows[i].X - Max(spec^.Arrows[i].W, spec^.Arrows[i].H) * 0.75,
          spec^.Arrows[i].Y - Max(spec^.Arrows[i].W, spec^.Arrows[i].H) * 0.75,
          spec^.Arrows[i].X + Max(spec^.Arrows[i].W, spec^.Arrows[i].H) * 0.75,
          spec^.Arrows[i].Y + Max(spec^.Arrows[i].W, spec^.Arrows[i].H) * 0.75)), 0, False);
      end;
  end;

  { NO PLACEMENTS, NO LABELS. There used to be a second route here that
    formatted and positioned the ticks itself, for an axis laid out without a
    spec. None reaches it -- every grid axis gets a spec, and the placements
    are one per label -- so all it ever did was keep its own copy of the
    number format in step with the builder's, which it did not. The builder
    is the one place a label's text comes from. }
end;

procedure TTyCustomAdvanceChart.RenderTo(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
var prev: TComponent; prevRes: TTyChartImageUrlResolver;
begin
  prev := TyChartImageScopeEnter(Owner);
  prevRes := TyChartImageResolverEnter(@ResolveImageUrl);
  try
    RenderToBody(ACanvas, ARect, APPI);
  finally
    TyChartImageResolverLeave(prevRes);
    TyChartImageScopeLeave(prev);
  end;
end;

procedure TTyCustomAdvanceChart.RenderToBody(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
var
  P: TTyPainter;
  R: TRect;
  boxStyle: TTyStyleSet;
  plotF: TTyRectF;
  g, a: Integer;
  gb: TTyGridBuild;
  measurer: ITyTextMeasurer;
begin
  { ONE measurer, held in an interface variable, for the whole render.

    Not `TTyPainterTextMeasurer.Create(APPI)` at each call site: the parameter
    is declared `const ITyTextMeasurer`, and a const interface parameter does
    not get the reference-counting temporary -- so an object passed straight in
    stays at a refcount of zero and is never freed. Two axes times two calls
    times every repaint is a leak the heap test found within thirty renders.

    Holding it here also means the layout pass and the paint pass measure with
    the same instance, which is what they are supposed to agree about. }
  { [F4b] the flush's start, for `rendered`'s elapsedTime }
  FPaintT0 := AnimClock;
  measurer := NewTextMeasurer(APPI);
  P := NewPainter;
  try
    { LOCAL space. EndPaint blits at ARect's origin, so everything below is
      measured from zero. }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    { upstream's frame: the flags become state lists [Batch 88] -- the list
      patched where only they changed [P2] }
    if StApplyChanged then FProgReuse := StPatchList;
    P.BeginPaint(ACanvas, ARect, APPI);
    PaintStatic(P, R, APPI, measurer);
    PaintDynamic(P, R, APPI, measurer);
    P.EndPaint;
  finally
    P.Free;
  end;
  { the update painted: `rendered` [Batch 119] }
  EmitFlush;
  { THE BAR RACE after setOption's flush: the init sorts the render left,
    the `rendered` listeners, then the pending dispatches [Batch 135] }
  if FRtAfterRelayout then
  begin
    FRtAfterRelayout := False;
    RtRenderPass;
    RtRendered;
  end;
  RtFlushQueue;
end;

procedure TTyCustomAdvanceChart.PaintStatic(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  axesHere: Boolean;
  boxStyle: TTyStyleSet;
  plotF: TTyRectF;
  bg: TTyChartColor;
  fill: TTyFill;
begin
  { Resolved at REST on purpose. The plot rect is measured from the label
    font, and a geometry that read the focused style would move the whole
    chart the moment it took focus. }
  boxStyle := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
    [tysNormal]);
  { what this render draws, view by view [Batch 106] }
  FViewsDrawn := [];
  { AN EXPORT WHOSE OPTIONS CHOSE THE BACKGROUND has painted it already, over
    the whole image: no frame [Batch 106] }
  if not FExportBare then
  begin
    { Mandatory first draw, and it does more than a fill: parent backdrop,
      opacity, shadow, background, border, and the corner gaps a windowed
      control cannot get from a shadow it is not allowed to cast. }
    DrawFrame(APainter, ARect, boxStyle);
    { THE OPTION'S backgroundColor OVER THE SKIN'S GROUND, inside the frame's
      corners -- 'transparent' and anything unreadable leave the skin's
      [Batch 83] }
    if AuthorBackground(bg) then
    begin
      fill := Default(TTyFill);
      fill.Kind := tfkSolid;
      fill.Color := TTyColor(bg);
      APainter.FillBackground(ARect, fill, boxStyle.Radius);
    end;
  end;

  plotF := TyRectF(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  { [R5-G] A PPI OF ITS OWN IS A NEW LAYOUT TOO: every px of the option is
    scaled by PPI / 96, so a chart moved to a monitor of another DPI at the
    same pixel size is a chart of another CSS size -- upstream's resize() }
  if FDirty or (plotF.Right <> FLastRect.Right)
    or (plotF.Bottom <> FLastRect.Bottom) or (APPI <> FLastPPI) then
  begin
    Relayout(APainter, plotF, APPI, AMeasurer);
    { the frame a lazy setOption waited for [Batch 97] }
    LazyUpdateDone;
    { its flush is `rendered` for a bar race [Batch 135] }
    if not FExporting then FRtAfterRelayout := True;
  end
  else if FLaidAhead then
  begin
    { [R5-J] laid out ahead (DiagReady): the rest of that update here }
    LazyUpdateDone;
    if not FExporting then FRtAfterRelayout := True;
  end;
  FLaidAhead := False;

  { THE GRAPHIC COMPONENT, against the canvas; its elements at z 0 and
    under go beneath the axes, as upstream's group joins the root first
    [Batch 122] }
  GfxBuild(APPI);
  { [R5-J] COMPONENTS ON SEVERAL ZLEVELS (a title's, an axis' own), or the
    list under theirs: canvas by canvas, in level order -- no dirty-rect
    ground, no fast progressive frame [was: every component on the root's
    zlevel, whatever it wrote] }
  FZMixed := ZMixedNow(FZLevels);
  { WHILE THEIR groupTransition RUNS the axes are the dynamic layer's, as
    the series are [Batch 96] -- an export draws them at rest [Batch 106] }
  axesHere := not FZMixed and (FExporting or not AxesDynamic);
  { [R7-AD] the graphic's elements under the axes drawn among their parts
    where the axes are drawn here (PaintAxes) }
  GfxPaintUnder(APainter, not axesHere);
  if FZMixed then
  begin
    PaintZLevels(APainter, APPI, AMeasurer, FZLevels, False, nil);
    Exit;
  end;
  { [R7-AD] THE LIST BEFORE THE AXES: what of it falls among their parts --
    a radar's, a geo's, a matrix's furniture, a series of a lower z -- is
    drawn with them (CompRun's order); in motion it is the dynamic layer's
    [was: the list built after the axes, all of it over them] }
  TySetZBand(-MaxInt, ZBase);
  try
    PrepareSeries(AMeasurer, APPI);
  finally
    TyClearZBand;
  end;
  if axesHere then
  begin
    if FAnimLive and not FExporting then PaintAxes(APainter, APPI, AMeasurer, False, nil, True)
    else PaintAxes(APainter, APPI, AMeasurer, False, FPaintList, True);
  end;
  { THE GROUND A REPAINTED RECT STARTS FROM: everything above, before the
    first series [Batch 142] }
  if FDrCapture and (APainter <> nil) then DrCaptureBase(APainter.Bitmap);

  { AFTER THE AXES, so a bar sits on the grid rather than under it. Within the
    series, the paint list decides the order. [R5-G] Only what stands on the
    components' zlevel or under it: a higher zlevel is a canvas over them. }
  TySetZBand(-MaxInt, ZBase);
  try
    RenderSeries(APainter, AMeasurer, APPI);
  finally
    TyClearZBand;
  end;
  { THE BREAK AREAS, zigzagZ over the series [Batch 132] -- the dynamic
    layer's while the series move there, over them and in their axes'
    groupTransition [F4a] }
  { [R5-I] and in the continuous phase too: over the series that move there
    [was: under the ripples] }
  if FExporting or not FAnimLive then PaintBreakAreas(APainter);
  { THE PARALLEL AXES OVER THEIR LINES: a parallelAxis is z 10, its series
    2 [Batch 128] }
  if FExporting or not FAnimContinuous then PaintParallels(APainter, APPI, AMeasurer);
  { AND THE TITLE LAST. It floats over the container rather than reserving
    room, so anything it overlaps it is meant to overlap. While the series
    move the title goes with them into the dynamic layer, so it stays over
    them [Batch 89]. }
  if FExporting or not FAnimLive then PaintTitles(APainter);
  { [R5-G] AND OVER THEM, an element of a higher zlevel -- up to the loading
    mask's, when it shows over the chart }
  if FExporting or not FAnimLive then
    PaintAboveComponents(APainter, FZList);
end;

function TTyCustomAdvanceChart.ComponentZLevel: Integer;
var d: TJSONData; v: Double;
begin
  Result := 0;
  if (FOption = nil) or not (FOption.Root is TJSONObject) then Exit;
  d := TJSONObject(FOption.Root).Find('zlevel');
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  v := d.AsFloat;
  if IsNan(v) or IsInfinite(v) then Exit;
  Result := Round(Max(Double(-100000), Min(Double(100000), v)));
end;

function TTyCustomAdvanceChart.ZStaticTop: Integer;
var v: Double;
begin
  Result := MaxInt;
  if not FLoadShown or (csDesigning in ComponentState) then Exit;
  v := FLoadCfg.ZLevel;
  if IsNan(v) or IsInfinite(v) then Exit;
  Result := Max(ZBase, Round(Max(Double(-100000), Min(Double(100000), v))));
end;

{ [R5-G] the elements of AList over the components' zlevel and up to the
  static layer's top -- drawn after the components, as zrender draws a
  canvas of a higher zlevel over the one they stand on.
  [R5-J] A progressive run among them through its layer (RenderZList): its
  chunks were blitted with the components' level whatever their own
  [was: the layer under the components, the chunks again over them]. }
procedure TTyCustomAdvanceChart.PaintAboveComponents(APainter: TTyPainter;
  AList: TTyPaintList);
var zc: Integer;
begin
  if AList = nil then Exit;
  zc := ZBase;
  if TyMaxZLevelOf(AList) <= zc then Exit;
  TySetZBand(zc, ZStaticTop);
  try
    RenderZList(APainter, AList, FLastPPI);
  finally
    TyClearZBand;
  end;
end;

function TTyCustomAdvanceChart.TrailZLevel(AList: TTyPaintList): Integer;
var i: Integer; pe: PTyChartElement;
begin
  Result := -MaxInt;
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    pe := AList.Ref(i);
    if (pe^.Datum.Kind = ctkSeries) and (LinesTrailAlpha(pe^.Datum.SeriesIndex) > 0) then
      Result := Max(Result, pe^.ZLevel);
  end;
end;

procedure TTyCustomAdvanceChart.PaintTrailAbove(APainter: TTyPainter; AList: TTyPaintList);
var zc: Integer;
begin
  if AList = nil then Exit;
  zc := ZBase;
  if TyMaxZLevelOf(AList) <= zc then Exit;
  TySetZBand(zc, ZStaticTop);
  try
    PaintTrail(APainter, AList);
  finally
    TyClearZBand;
  end;
end;

function TTyCustomAdvanceChart.ModelZLevel(const AMainType: string;
  AIndex: Integer): Integer;
var
  node, d: TJSONData;
  v: Double;
begin
  Result := 0;
  if FOption = nil then Exit;
  d := nil;
  node := FOption.ComponentAt(AMainType, AIndex);
  if node is TJSONObject then d := TJSONObject(node).Find('zlevel');
  { Model.get climbs where the value is null or not written }
  if ((d = nil) or (d.JSONType = jtNull)) and (FOption.Root is TJSONObject) then
    d := TJSONObject(FOption.Root).Find('zlevel');
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  v := d.AsFloat;
  if IsNan(v) or IsInfinite(v) then Exit;
  Result := Round(Max(Double(-100000), Min(Double(100000), v)));
end;

function TTyCustomAdvanceChart.AxisModelZLevel(AAxis: TTyAxis): Integer;
var mt: string;
begin
  Result := ComponentZLevel;
  if AAxis = nil then Exit;
  mt := AAxis.MainType;
  if mt = '' then mt := AAxis.Dim + 'Axis';
  Result := ModelZLevel(mt, AAxis.ComponentIndex);
end;

function TTyCustomAdvanceChart.ApartIn(AZLevel: Integer): Boolean;
begin
  Result := not FZApartOn or (AZLevel = FZApartLevel);
end;

function TTyCustomAdvanceChart.ApartLevels: TTyIntegerArray;
var
  g, a, i: Integer;
  gb: TTyGridBuild;

  procedure Add(AZ: Integer);
  var k, j: Integer;
  begin
    k := 0;
    while (k <= High(Result)) and (Result[k] < AZ) do Inc(k);
    if (k <= High(Result)) and (Result[k] = AZ) then Exit;
    SetLength(Result, Length(Result) + 1);
    for j := High(Result) downto k + 1 do Result[j] := Result[j - 1];
    Result[k] := AZ;
  end;

begin
  Result := nil;
  if FOption = nil then Exit;
  if FBuild <> nil then
    for g := 0 to FBuild.GridCount - 1 do
    begin
      gb := FBuild.Grid(g);
      for a := 0 to gb.XAxisCount - 1 do
        if gb.XAxis(a) <> nil then Add(AxisModelZLevel(gb.XAxis(a)));
      for a := 0 to gb.YAxisCount - 1 do
        if gb.YAxis(a) <> nil then Add(AxisModelZLevel(gb.YAxis(a)));
    end;
  for i := 0 to High(FPolars) do
    if FPolars[i] <> nil then
    begin
      if FPolars[i].AngleAxis <> nil then Add(AxisModelZLevel(FPolars[i].AngleAxis));
      if FPolars[i].RadiusAxis <> nil then Add(AxisModelZLevel(FPolars[i].RadiusAxis));
    end;
  for i := 0 to High(FSingles) do
    if (FSingles[i] <> nil) and (FSingles[i].Axis <> nil) then
      Add(AxisModelZLevel(FSingles[i].Axis));
  for i := 0 to High(FParallels) do
    if FParallels[i] <> nil then
      for a := 0 to High(FParallels[i].AxisIndices) do
        Add(ModelZLevel('parallelAxis', FParallels[i].AxisIndices[a]));
  for i := 0 to High(FTitles) do
    if FTitles[i].Valid then Add(ModelZLevel('title', i));
end;

function TTyCustomAdvanceChart.ListMinZLevel: Integer;
const
  cTypes: array[0..9] of string = ('series', 'legend', 'toolbox', 'dataZoom',
    'visualMap', 'timeline', 'thumbnail', 'geo', 'matrix', 'radar');
var
  t, i, k, z: Integer;
  node, mk, d: TJSONData;
begin
  Result := MaxInt;
  if FOption = nil then Exit;
  for t := 0 to High(cTypes) do
    for i := 0 to FOption.ComponentCount(cTypes[t]) - 1 do
    begin
      z := ModelZLevel(cTypes[t], i);
      if z < Result then Result := z;
      { a series' markers: their own, else the series' }
      if t <> 0 then Continue;
      node := FOption.ComponentAt('series', i);
      if not (node is TJSONObject) then Continue;
      for k := 0 to 2 do
      begin
        case k of
          0: mk := TJSONObject(node).Find('markPoint');
          1: mk := TJSONObject(node).Find('markLine');
        else
          mk := TJSONObject(node).Find('markArea');
        end;
        if not (mk is TJSONObject) then Continue;
        d := TJSONObject(mk).Find('zlevel');
        if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat)
          and not IsInfinite(d.AsFloat) then
          if Round(Max(Double(-100000), Min(Double(100000), d.AsFloat))) < Result then
            Result := Round(Max(Double(-100000), Min(Double(100000), d.AsFloat)));
      end;
    end;
end;

function TTyCustomAdvanceChart.ZMixedNow(out ALevels: TTyIntegerArray): Boolean;
begin
  ALevels := ApartLevels;
  Result := (Length(ALevels) > 1)
    or ((Length(ALevels) = 1) and (ListMinZLevel < ALevels[0]));
end;

function TTyCustomAdvanceChart.ZBase: Integer;
var lv: TTyIntegerArray;
begin
  lv := ApartLevels;
  if Length(lv) = 0 then Result := ComponentZLevel
  else Result := lv[High(lv)];
end;

procedure TTyCustomAdvanceChart.RenderZList(APainter: TTyPainter; AList: TTyPaintList;
  APPI: Integer);
begin
  if (AList = nil) or (APainter = nil) then Exit;
  if (AList = FPaintList) and not FExporting then ProgRenderList(APainter, AList, APPI)
  else TyRenderPaintList(APainter, AList);
end;

function TTyCustomAdvanceChart.AxesInDynamic: Boolean;
begin
  Result := AxesDynamic or (FAnimLive and not FAnimContinuous and FZMixed);
end;

procedure TTyCustomAdvanceChart.PaintZLevels(APainter: TTyPainter; APPI: Integer;
  const AMeasurer: ITyTextMeasurer; const ALevels: TTyIntegerArray;
  ADynamic: Boolean; AFrame: TTyPaintList);
var
  i, lv, prev: Integer;
  over: Boolean;

  procedure ListBand(ALo, AHi: Integer; AFirst: Boolean);
  begin
    TySetZBand(ALo, AHi);
    try
      if ADynamic then TyRenderPaintList(APainter, AFrame)
      { the static layer's first: the series pass builds the list }
      else if AFirst then PaintSeries(APainter, AMeasurer, APPI)
      else RenderZList(APainter, FZList, APPI);
    finally
      TyClearZBand;
    end;
  end;

begin
  { what the static layer draws over the series: not while they move in the
    dynamic layer (it draws them there) }
  over := ADynamic or FExporting or not FAnimLive or FAnimContinuous;
  prev := -MaxInt;
  for i := 0 to High(ALevels) do
  begin
    lv := ALevels[i];
    ListBand(prev, lv - 1, (i = 0) and not ADynamic);
    FZApartOn := True;
    FZApartLevel := lv;
    try
      if ADynamic then
      begin
        if AxesInDynamic then PaintAxes(APainter, APPI, AMeasurer, AxesDynamic);
      end
      else if FExporting or not AxesInDynamic then
        PaintAxes(APainter, APPI, AMeasurer, False);
      ListBand(lv - 1, lv, False);
      if over then PaintBreakAreas(APainter);
      PaintParallels(APainter, APPI, AMeasurer);
      if over then PaintTitles(APainter);
    finally
      FZApartOn := False;
    end;
    prev := lv;
  end;
  if ADynamic then
  begin
    TySetZBand(prev, MaxInt);
    try
      TyRenderPaintList(APainter, AFrame);
    finally
      TyClearZBand;
    end;
  end
  else if over then
  begin
    TySetZBand(prev, ZStaticTop);
    try
      RenderZList(APainter, FZList, APPI);
    finally
      TyClearZBand;
    end;
  end;
end;

procedure TTyCustomAdvanceChart.LevelTail(AList: TTyPaintList; AFrom: Integer;
  const AMainType: string; AIndex: Integer);
var
  k, z: Integer;
  el: TTyChartElement;
begin
  if (AList = nil) or (AFrom < 0) then Exit;
  z := ModelZLevel(AMainType, AIndex);
  for k := AFrom to AList.Count - 1 do
    if AList.Ref(k)^.ZLevel <> z then
    begin
      el := AList.Element(k);
      el.ZLevel := z;
      AList.SetElement(k, el);
    end;
end;

function TTyCustomAdvanceChart.ProgRunZLevel: Integer;
var k: Integer;
begin
  Result := -MaxInt;
  if FPaintList = nil then Exit;
  for k := 0 to FPaintList.Count - 1 do
    if FPaintList.Ref(k)^.ProgChunk > 0 then Exit(FPaintList.Ref(k)^.ZLevel);
end;

{ [R7-Z] THE PARTS OF ONE CARTESIAN AXIS as upstream's AxisBuilder and
  CartesianAxisView add them, each a pseudo-element of what it hands the
  canvas: the split areas and lines (z2 0), the name and the line (z2 1,
  the name first), the ticks (2), the labels (10), the arrows (11). The
  pens are resolved as PaintAxis resolves them (keep the two in step). }
procedure TTyCustomAdvanceChart.CompAxisParts(AAxis: TTyAxis; AGrid: TTyGridBuild;
  AView: Integer; var AParts: TTyCompPartArray);
var
  model: TTyStyleModel;
  lineS, tickStyle, splitS, minorTickS, minorSplitS, areaS, labelS, nameS: TTyStyleSet;
  furn: TTyAxisFurniture;
  spec: PTyAxisLayoutSpec;
  lineK, tickK, minorTickK, splitK, minorSplitK: TTyAxisStroke;
  key: string;
  z, seq, i, ink: Integer;
  scaleTicks: TTyScaleTickArray;
  minors: Boolean;
  e: TTyChartElement;
  col: TTyChartColor;
  view: TTyChartView;
  node, d: TJSONData;
  { [R7-AA] a gradient line's box }
  lineAt: Double;
  gb: TTyXYWH;
  { [R7-AC] a tick's, a split line's }
  j: Integer;
  at, len: Double;

  function APlotOf(G: TTyGridBuild): TTyRectF;
  begin
    Result := G.PlotRect;
  end;

  { [R7-AC] A LINE'S GRADIENT BOX: its ends on the pixel grid
    (subPixelOptimize), the path's bounds grown by its pen -- no fill:
    max(width, 5) (Path.getBoundingRect) }
  procedure LineBox(var AEl: TTyChartElement; AX1, AY1, AX2, AY2, AW: Double);
  var sc: Double;
  begin
    if FLastPPI > 0 then sc := FLastPPI / 96 else sc := 1;
    { ([R7-AG] on the css px grid, as drawn) }
    if sc <> 1 then
    begin
      if AW * sc > 0 then TyZrSubPixelLineAt(AX1, AY1, AX2, AY2, AW * sc, sc);
    end
    else
      TySubPixelLine(AX1, AY1, AX2, AY2, AW * sc);
    AEl.Style.GradBoxSet := True;
    AEl.Style.GradBox := TyGrowByStroke(TyRectToXYWH(TyRectF(Math.Min(AX1, AX2),
      Math.Min(AY1, AY2), Math.Max(AX1, AX2), Math.Max(AY1, AY2))), False, AW);
  end;

  { [R7-AC] a tick's (PaintAxis' line: from the axis line, its length out
    or -- inside -- in) }
  procedure TickBox(var AEl: TTyChartElement; AAlong, ALenLogical, AW: Double);
  var sc, lat, ln, x1, y1, x2, y2: Double;
  begin
    if FLastPPI > 0 then sc := FLastPPI / 96 else sc := 1;
    lat := AGrid.AxisLineCoord(AAxis, FLastPPI);
    ln := ALenLogical * sc;
    if furn.TickInside then ln := -ln;
    if AAxis.Horizontal then
    begin
      x1 := AAlong;
      x2 := AAlong;
      y1 := lat;
      if AAxis.Side = asTop then y2 := lat - ln else y2 := lat + ln;
    end
    else
    begin
      y1 := AAlong;
      y2 := AAlong;
      x1 := lat;
      if AAxis.Side = asRight then x2 := lat + ln else x2 := lat - ln;
    end;
    LineBox(AEl, x1, y1, x2, y2, AW);
  end;

  procedure Add(AKind: Byte; AZ2: Integer; AText: Boolean; const AEl: TTyChartElement);
  var n: Integer;
  begin
    n := Length(AParts);
    SetLength(AParts, n + 1);
    AParts[n].Owner := AAxis;
    AParts[n].Key := key;
    AParts[n].Kind := AKind;
    AParts[n].Z := z;
    AParts[n].Z2 := AZ2;
    AParts[n].View := AView;
    AParts[n].Seq := seq;
    Inc(seq);
    AParts[n].IsText := AText;
    AParts[n].El := AEl;
    { [R7-AB] a text's font, as it hands the canvas one }
    if AText then
      if AKind = cpkName then CompTextFont(AAxis, 'nameTextStyle', nameS, AParts[n].El)
      else CompTextFont(AAxis, 'axisLabel', labelS, AParts[n].El);
  end;

  function Pen(const K: TTyAxisStroke): TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Style.Alpha := K.Opacity;
    Result.Style.StrokeColor := K.Colour;
    Result.Style.StrokeWidthLogical := K.WidthLogical;
    Result.Style.DashLogical := Copy(K.Dash, 0, Length(K.Dash));
    Result.Style.DashOffsetLogical := K.DashOffset;
    if (K.Left and cTyCanvasCapLeft) <> 0 then Result.Style.LineCap := cTyCanvasWordLeft
    else Result.Style.LineCap := Ord(K.Cap);
    if (K.Left and cTyCanvasWidthLeft) <> 0 then Result.CanvasFlags := cTyCanvasWidthLeft;
    { [R7-AA] its shadow, join, miterLimit and gradient; a width of nought
      still hands its stroke colour (the run takes a colour of no width:
      R7-Y) }
    TyCompStrokeLook(Result.Style, K, True);
    if not K.Drawn then Result.Style.StrokeWidthLogical := 0;
  end;

  function Txt(AColour: TTyChartColor; const AM: TTyMat2D): TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Style.Alpha := 1;
    Result.Caption.FontSizeLogical := 1;
    Result.Caption.Text := 'x';
    Result.Caption.Colour := AColour;
    Result.CanvasM := TTyDoubleArray.Create(AM[0], AM[1], AM[2], AM[3], AM[4], AM[5]);
  end;

begin
  if (AAxis = nil) or not AAxis.Visible then Exit;
  { (another zlevel is another canvas) }
  if AxisModelZLevel(AAxis) <> 0 then Exit;
  if TyChartViewOf(AAxis.MainType, view) and (view in [cvXAxis, cvYAxis]) and ViewHidden(view) then Exit;
  key := AAxis.MainType + IntToStr(AAxis.ComponentIndex);
  seq := 0;
  { the axis' z (its model's default 0) }
  z := 0;
  node := nil;
  if FOption <> nil then node := FOption.ComponentAt(AAxis.MainType, AAxis.ComponentIndex);
  if node is TJSONObject then
  begin
    d := TJSONObject(node).Find('z');
    if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat) and not IsInfinite(d.AsFloat) then
      z := Round(Max(Double(-100000), Min(Double(100000), d.AsFloat)));
  end;
  { THE PENS, as PaintAxis resolves them }
  model := ActiveController.Model;
  lineS := model.ResolveStyle('TyAdvChartAxisLine', '', []);
  minorTickS := model.ResolveStyle('TyAdvChartMinorTick', '', []);
  minorSplitS := model.ResolveStyle('TyAdvChartMinorSplitLine', '', []);
  tickStyle := model.ResolveStyle('TyAdvChartAxisTick', '', []);
  splitS := model.ResolveStyle('TyAdvChartSplitLine', '', []);
  areaS := model.ResolveStyle('TyAdvChartSplitArea', '', []);
  spec := nil;
  if AGrid <> nil then spec := AGrid.SpecFor(AAxis);
  AxisTextStyles(spec, labelS, nameS);
  furn := Default(TTyAxisFurniture);
  furn.ShowLine := True;
  furn.ShowTicks := True;
  furn.ShowLabels := True;
  furn.LinePen.Cap := -1;
  furn.LinePen.Width := NaN;
  furn.LinePen.Opacity := NaN;
  furn.TickPen := furn.LinePen;
  furn.MinorTickPen := furn.LinePen;
  furn.SplitPen := furn.LinePen;
  furn.MinorSplitPen := furn.LinePen;
  furn.AreaOpacity := NaN;
  if AGrid <> nil then furn := AGrid.FurnitureFor(AAxis);
  lineK := TyAxisSkinStroke(furn.LinePen, lineS, acRound);
  tickK := TyAxisSkinStroke(furn.TickPen, tickStyle, acButt);
  minorTickK := TyAxisSkinStroke(furn.MinorTickPen, minorTickS, acButt);
  splitK := TyAxisSkinStroke(furn.SplitPen, splitS, acButt);
  minorSplitK := TyAxisSkinStroke(furn.MinorSplitPen, minorSplitS, acButt);
  minors := False;
  if furn.ShowMinorSplitLine or furn.ShowMinorTick then
  begin
    scaleTicks := TyDrawnTicks(AAxis.Scale);
    for i := 0 to High(scaleTicks) do
      if scaleTicks[i].Level <> 0 then
      begin
        minors := True;
        Break;
      end;
  end;
  { z2 0: the split areas, a rect a band; the split lines, a line each (the
    last one's colour is the one left); the minor split lines }
  if furn.ShowSplitArea and (spec <> nil) then
    for i := 0 to High(spec^.SplitAreaMarks) - 1 do
    begin
      if not spec^.SplitAreaMarks[i].Drawn then Continue;
      ink := spec^.SplitAreaMarks[i].ColourIndex;
      if Length(spec^.SplitAreaInks) > 0 then
      begin
        if ink > High(spec^.SplitAreaInks) then ink := 0;
        if not spec^.SplitAreaInks[ink].Ok then Continue;
        col := spec^.SplitAreaInks[ink].Colour;
      end
      else if (ink <> 0) or not (tpBackground in areaS.Present) then Continue
      else col := TTyChartColor(areaS.Background.Color);
      e := Default(TTyChartElement);
      e.Style.Alpha := 1;
      e.Style.HasFill := True;
      e.Style.FillColor := col;
      e.Datum.DataIndex := ink;
      { [R7-AA] the band (a Rect a band: each settles its own) }
      e.Datum.RawDataIndex := i;
      Add(cpkSplitArea, 0, False, e);
    end;
  { ([R7-AA] a width of nought among them: the stroke colour handed on) }
  if furn.ShowSplitLine and (spec <> nil)
    and (splitK.Drawn or splitK.Inked or (Length(spec^.SplitLineInks) > 0)) then
    for i := 0 to High(spec^.SplitLineMarks) do
    begin
      if not spec^.SplitLineMarks[i].Drawn then Continue;
      e := Pen(splitK);
      if Length(spec^.SplitLineInks) > 0 then
      begin
        ink := spec^.SplitLineMarks[i].ColourIndex;
        if (ink < 0) or (ink > High(spec^.SplitLineInks)) or not spec^.SplitLineInks[ink].Ok then Continue;
        e.Style.StrokeColor := spec^.SplitLineInks[ink].Colour;
        e.Style.StrokeGradient := spec^.SplitLineInks[ink].Grad;
        e.Datum.DataIndex := ink;
        if not (splitK.WidthLogical > 0) then e.Style.StrokeWidthLogical := 0;
      end;
      { [R7-AC] a gradient pen: made over this line's box (a Line each) }
      if (e.Style.StrokeGradient.Kind <> cgkNone) and (AGrid <> nil) then
        if AAxis.Horizontal then
          LineBox(e, spec^.SplitLineMarks[i].Coord, APlotOf(AGrid).Top,
            spec^.SplitLineMarks[i].Coord, APlotOf(AGrid).Bottom, splitK.WidthLogical)
        else
          LineBox(e, APlotOf(AGrid).Left, spec^.SplitLineMarks[i].Coord,
            APlotOf(AGrid).Right, spec^.SplitLineMarks[i].Coord, splitK.WidthLogical);
      { [R7-AB after R7-AA] the Line's mark (a dirty block brushes the ones
        meeting it) }
      e.Datum.RawDataIndex := i;
      Add(cpkSplit, 0, False, e);
    end;
  if furn.ShowMinorSplitLine and (minorSplitK.Drawn or minorSplitK.Inked) and minors then
  begin
    e := Pen(minorSplitK);
    { [R7-AC] the last minor split line's box }
    if (e.Style.StrokeGradient.Kind <> cgkNone) and (AGrid <> nil) then
      for i := High(scaleTicks) downto 0 do
        if scaleTicks[i].Level <> 0 then
        begin
          at := AAxis.DataToCoord(scaleTicks[i].Value);
          if AAxis.Horizontal then
            LineBox(e, at, APlotOf(AGrid).Top, at, APlotOf(AGrid).Bottom, minorSplitK.WidthLogical)
          else
            LineBox(e, APlotOf(AGrid).Left, at, APlotOf(AGrid).Right, at, minorSplitK.WidthLogical);
          Break;
        end;
    Add(cpkMinorSplit, 0, False, e);
  end;
  { z2 1: the name, then the line }
  if (spec <> nil) and spec^.NamePlacement.Shown and (tpTextColor in nameS.Present) then
  begin
    e := Txt(TTyChartColor(nameS.TextColor),
      TyZrLocal(1, 1, spec^.NamePlacement.RotationRad, spec^.NamePlacement.X, spec^.NamePlacement.Y));
    { [R7-AD] (a rich name's spans) }
    e.Datum.RawDataIndex := -1;
    if Length(spec^.NamePlacement.Rt) > 0 then
      e.Caption.RtPieces := Copy(spec^.NamePlacement.Rt, 0, MaxInt);
    Add(cpkName, 1, True, e);
  end;
  if furn.ShowLine and (lineK.Drawn or lineK.Inked) then
  begin
    e := Pen(lineK);
    { [R7-AA] a gradient pen: the canvas keeps the CanvasGradient made over
      the line's getBoundingRect (a path of no fill: grown by max(width, 5)) }
    if (lineK.Gradient.Kind <> cgkNone) and (AGrid <> nil) then
    begin
      lineAt := AGrid.AxisLineCoord(AAxis, FLastPPI);
      if AAxis.Horizontal then
        gb := TyRectToXYWH(TyRectF(APlotOf(AGrid).Left, lineAt, APlotOf(AGrid).Right, lineAt))
      else
        gb := TyRectToXYWH(TyRectF(lineAt, APlotOf(AGrid).Top, lineAt, APlotOf(AGrid).Bottom));
      e.Style.GradBoxSet := True;
      e.Style.GradBox := TyGrowByStroke(gb, False, lineK.WidthLogical);
    end;
    Add(cpkLine, 1, False, e);
  end;
  { z2 2: the ticks, then the minor ones -- [R7-AC] a gradient pen made
    over the last one's box (a Line each: the canvas keeps the last one's
    CanvasGradient) [was: no box] }
  if furn.ShowTicks and (tickK.Drawn or tickK.Inked) and (spec <> nil) then
    for i := 0 to High(spec^.TickMarks) do
      if spec^.TickMarks[i].Drawn then
      begin
        e := Pen(tickK);
        if (e.Style.StrokeGradient.Kind <> cgkNone) and (AGrid <> nil) then
          for j := High(spec^.TickMarks) downto 0 do
            if spec^.TickMarks[j].Drawn then
            begin
              TickBox(e, spec^.TickMarks[j].Coord, spec^.TickLengthLogical, tickK.WidthLogical);
              Break;
            end;
        Add(cpkTick, 2, False, e);
        Break;
      end;
  if furn.ShowMinorTick and (minorTickK.Drawn or minorTickK.Inked) and minors then
  begin
    e := Pen(minorTickK);
    if (e.Style.StrokeGradient.Kind <> cgkNone) and (AGrid <> nil) then
      for i := High(scaleTicks) downto 0 do
        if scaleTicks[i].Level <> 0 then
        begin
          if not IsNan(furn.MinorTickLengthLogical) then len := furn.MinorTickLengthLogical
          else len := ActiveController.Metric(TyAdvChartMinorTickLenVar, TyAdvChartMinorTickLen);
          TickBox(e, AAxis.DataToCoord(scaleTicks[i].Value), len, minorTickK.WidthLogical);
          Break;
        end;
    Add(cpkMinorTick, 2, False, e);
  end;
  { z2 10: the labels, each its fill and transform }
  if (tpTextColor in labelS.Present) and (spec <> nil) then
    for i := 0 to High(spec^.Placements) do
    begin
      if not spec^.Placements[i].Shown or (spec^.Placements[i].Text = '') then Continue;
      { ([R7-AA] a time axis' label at 10 plus its tick's level) }
      if spec^.Placements[i].HasM then
        e := Txt(TTyChartColor(labelS.TextColor), spec^.Placements[i].M)
      else
        e := Txt(TTyChartColor(labelS.TextColor),
          TyZrLocal(1, 1, spec^.RotationRad, spec^.Placements[i].X, spec^.Placements[i].Y));
      { [R7-AD] a rich label's spans, each its font and fill (settled in the
        run, drawn so: PaintAxis) [was: the label's own font and fill] }
      e.Datum.RawDataIndex := i;
      if Length(spec^.Placements[i].Rt) > 0 then
        e.Caption.RtPieces := Copy(spec^.Placements[i].Rt, 0, MaxInt);
      Add(cpkLabel, TyAxisLabelZ2(AAxis, spec, i), True, e);
    end;
  { z2 11: the arrows, filled in the line's colour (lineStyle.stroke alone) }
  if furn.ShowLine and (spec <> nil) and not furn.LinePen.ColourNone
    and (furn.LinePen.HasColour or (tpBorderColor in lineS.Present)) then
    for i := 0 to High(spec^.Arrows) do
    begin
      e := Default(TTyChartElement);
      e.Style.Alpha := 1;
      e.Style.HasFill := True;
      e.Style.FillColor := lineK.Colour;
      e.CanvasM := TTyDoubleArray.Create(1, 0, 0, 1, spec^.Arrows[i].X, spec^.Arrows[i].Y);
      Add(cpkArrow, 11, False, e);
    end;
end;

{ [R7-Z] THE PARTS OF A POLAR'S OR A SINGLE AXIS' VIEW, as upstream's views
  add them: a radius axis' and a single axis' are AxisBuilder's (split
  lines at z2 0 -- a single axis' merged into one path filled '#000', a
  radius axis' circles unfilled --, the name and the line 1, the ticks 2,
  the labels 10, the arrows 11); an angle axis' labels, merged ticks and
  merged split lines at z2 0 (the merged paths filled '#000'), its line 1.
  The split areas are not among them. }
procedure TTyCustomAdvanceChart.CompViewParts(AAxis: TTyAxis; AView, AShape: Integer;
  const AFurn: TTyAxisFurniture; const ASpec: TTyAxisLayoutSpec; AHasLine: Boolean;
  const ASplitInks: TTyIntegerArray; ATicks, AMinorTicks: Boolean;
  const ALabels: TTyPolarLabelArray; var AParts: TTyCompPartArray;
  const AAreaInks: TTyIntegerArray);
var
  model: TTyStyleModel;
  lineS, tickStyle, splitS, minorTickS, labelS, nameS, areaS: TTyStyleSet;
  lineK, tickK, minorTickK, splitK: TTyAxisStroke;
  key: string;
  z, seq, i: Integer;
  e: TTyChartElement;
  sp: TTyAxisLayoutSpec;
  angle: Boolean;

  procedure Add(AKind: Byte; AZ2: Integer; AText: Boolean; const AEl: TTyChartElement);
  var n: Integer;
  begin
    n := Length(AParts);
    SetLength(AParts, n + 1);
    AParts[n].Owner := AAxis;
    AParts[n].Key := key;
    AParts[n].Kind := AKind;
    AParts[n].Z := z;
    AParts[n].Z2 := AZ2;
    AParts[n].View := AView;
    AParts[n].Seq := seq;
    Inc(seq);
    AParts[n].IsText := AText;
    AParts[n].El := AEl;
    { [R7-AB] a text's font, as it hands the canvas one }
    if AText then
      if AKind = cpkName then CompTextFont(AAxis, 'nameTextStyle', nameS, AParts[n].El)
      else CompTextFont(AAxis, 'axisLabel', labelS, AParts[n].El);
  end;

  function Pen(const K: TTyAxisStroke; AMerged: Boolean): TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Style.Alpha := K.Opacity;
    Result.Style.StrokeColor := K.Colour;
    Result.Style.StrokeWidthLogical := K.WidthLogical;
    Result.Style.DashLogical := Copy(K.Dash, 0, Length(K.Dash));
    Result.Style.DashOffsetLogical := K.DashOffset;
    if (K.Left and cTyCanvasCapLeft) <> 0 then Result.Style.LineCap := cTyCanvasWordLeft
    else Result.Style.LineCap := Ord(K.Cap);
    if (K.Left and cTyCanvasWidthLeft) <> 0 then Result.CanvasFlags := cTyCanvasWidthLeft;
    { [R7-AA] its shadow, join, miterLimit and gradient; a width of nought
      still hands its stroke colour (the run takes a colour of no width:
      R7-Y) }
    TyCompStrokeLook(Result.Style, K, True);
    if not K.Drawn then Result.Style.StrokeWidthLogical := 0;
    { a merged path: Path's own default fill }
    if AMerged then
    begin
      Result.Style.HasFill := True;
      Result.Style.FillColor := TTyChartColor($FF000000);
    end;
  end;

  function Txt(AColour: TTyChartColor; AX, AY, ARot: Double): TTyChartElement;
  var m: TTyMat2D;
  begin
    Result := Default(TTyChartElement);
    Result.Style.Alpha := 1;
    Result.Caption.FontSizeLogical := 1;
    Result.Caption.Text := 'x';
    Result.Caption.Colour := AColour;
    m := TyZrLocal(1, 1, ARot, AX, AY);
    Result.CanvasM := TTyDoubleArray.Create(m[0], m[1], m[2], m[3], m[4], m[5]);
  end;

  { [R7-AA] THE SPLIT AREAS: a single axis' Rect a band, a polar axis'
    merged path a colour (AAreaInks in order: an ink of the author's list,
    -1 the skin's colour), each filled as written at areaStyle.opacity }
  procedure AreaParts;
  var q: Integer; e2: TTyChartElement;
  begin
    for q := 0 to High(AAreaInks) do
    begin
      e2 := Default(TTyChartElement);
      e2.Style.Alpha := 1;
      if not IsNan(AFurn.AreaOpacity) then e2.Style.Alpha := AFurn.AreaOpacity;
      e2.Style.HasFill := True;
      if AAreaInks[q] >= 0 then
      begin
        if (AAreaInks[q] > High(AFurn.SplitAreaInks)) or not AFurn.SplitAreaInks[AAreaInks[q]].Ok then
          Continue;
        e2.Style.FillColor := AFurn.SplitAreaInks[AAreaInks[q]].Colour;
        e2.Datum.DataIndex := AAreaInks[q];
      end
      else
      begin
        e2.Style.FillColor := TTyChartColor(areaS.Background.Color);
        e2.Datum.DataIndex := 0;
      end;
      e2.Datum.RawDataIndex := q;
      Add(cpkSplitArea, 0, False, e2);
    end;
  end;

begin
  if (AAxis = nil) or (AxisModelZLevel(AAxis) <> 0) then Exit;
  key := AAxis.MainType + IntToStr(AAxis.ComponentIndex);
  angle := AShape = 2;
  seq := 0;
  z := 0;
  model := ActiveController.Model;
  lineS := model.ResolveStyle('TyAdvChartAxisLine', '', []);
  tickStyle := model.ResolveStyle('TyAdvChartAxisTick', '', []);
  splitS := model.ResolveStyle('TyAdvChartSplitLine', '', []);
  minorTickS := model.ResolveStyle('TyAdvChartMinorTick', '', []);
  areaS := model.ResolveStyle('TyAdvChartSplitArea', '', []);
  sp := ASpec;
  AxisTextStyles(@sp, labelS, nameS);
  if angle then lineK := TyAxisSkinStroke(AFurn.LinePen, lineS, acButt)
  else lineK := TyAxisSkinStroke(AFurn.LinePen, lineS, acRound);
  tickK := TyAxisSkinStroke(AFurn.TickPen, tickStyle, acButt);
  minorTickK := TyAxisSkinStroke(AFurn.MinorTickPen, minorTickS, acButt);
  splitK := TyAxisSkinStroke(AFurn.SplitPen, splitS, acButt);
  if angle then
  begin
    { z2 0: the labels, the ticks, the minor ticks, the split lines }
    if tpTextColor in labelS.Present then
      for i := 0 to High(ALabels) do
        if ALabels[i].Text <> '' then
        begin
          e := Txt(TTyChartColor(labelS.TextColor), ALabels[i].X, ALabels[i].Y, 0);
          { [R7-AD] its placement, a rich one's spans }
          e.Datum.RawDataIndex := i;
          if Length(ALabels[i].Rt) > 0 then e.Caption.RtPieces := Copy(ALabels[i].Rt, 0, MaxInt);
          Add(cpkLabel, 0, True, e);
        end;
    if ATicks and (tickK.Drawn or tickK.Inked) then Add(cpkTick, 0, False, Pen(tickK, True));
    if AMinorTicks and (minorTickK.Drawn or minorTickK.Inked) then
      Add(cpkMinorTick, 0, False, Pen(minorTickK, True));
  end;
  { [R7-AA] a single axis' split areas before its split lines (its axis
    group's, added first) }
  if AShape = 0 then AreaParts;
  { the split lines, a path a colour of the author's list (-1: the pen's) }
  if splitK.Drawn or splitK.Inked or (Length(AFurn.SplitLineInks) > 0) then
    for i := 0 to High(ASplitInks) do
    begin
      e := Pen(splitK, AShape <> 1);
      if ASplitInks[i] >= 0 then
      begin
        if (ASplitInks[i] > High(AFurn.SplitLineInks)) or not AFurn.SplitLineInks[ASplitInks[i]].Ok then
          Continue;
        e.Style.StrokeColor := AFurn.SplitLineInks[ASplitInks[i]].Colour;
        e.Style.StrokeGradient := AFurn.SplitLineInks[ASplitInks[i]].Grad;
        e.Datum.DataIndex := ASplitInks[i];
        { ([R7-AA] a width of nought: the stroke colour handed on) }
        if not (splitK.WidthLogical > 0) then e.Style.StrokeWidthLogical := 0;
      end;
      { [R7-AD] its path's colour (-1 the pen's): the rects of its lines
        (CanvasGroundIn) }
      e.Datum.RawDataIndex := ASplitInks[i];
      Add(cpkSplit, 0, False, e);
    end;
  { [R7-AA] a polar axis' after them (the radius view's after its split
    lines, the angle view's after its minor split lines too) }
  if AShape <> 0 then AreaParts;
  if angle then
  begin
    if AHasLine and (lineK.Drawn or lineK.Inked) then Add(cpkLine, 1, False, Pen(lineK, False));
    Exit;
  end;
  { z2 1: the name, the line; 2: the ticks; 10: the labels; 11: the arrows }
  if sp.NamePlacement.Shown and (tpTextColor in nameS.Present) then
    Add(cpkName, 1, True, Txt(TTyChartColor(nameS.TextColor), sp.NamePlacement.X,
      sp.NamePlacement.Y, sp.NamePlacement.RotationRad));
  if AHasLine and (lineK.Drawn or lineK.Inked) then Add(cpkLine, 1, False, Pen(lineK, False));
  if ATicks and (tickK.Drawn or tickK.Inked) then Add(cpkTick, 2, False, Pen(tickK, False));
  if AMinorTicks and (minorTickK.Drawn or minorTickK.Inked) then
    Add(cpkMinorTick, 2, False, Pen(minorTickK, False));
  if tpTextColor in labelS.Present then
    for i := 0 to High(sp.Placements) do
    begin
      if not sp.Placements[i].Shown or (sp.Placements[i].Text = '') then Continue;
      if sp.Placements[i].HasM then
      begin
        e := Txt(TTyChartColor(labelS.TextColor), 0, 0, 0);
        e.CanvasM := TTyDoubleArray.Create(sp.Placements[i].M[0], sp.Placements[i].M[1],
          sp.Placements[i].M[2], sp.Placements[i].M[3], sp.Placements[i].M[4], sp.Placements[i].M[5]);
      end
      else
        e := Txt(TTyChartColor(labelS.TextColor), sp.Placements[i].X,
          sp.Placements[i].Y, sp.RotationRad);
      { [R7-AD] its placement, a rich one's spans }
      e.Datum.RawDataIndex := i;
      if Length(sp.Placements[i].Rt) > 0 then e.Caption.RtPieces := Copy(sp.Placements[i].Rt, 0, MaxInt);
      Add(cpkLabel, 10, True, e);
    end;
  if AHasLine and not AFurn.LinePen.ColourNone
    and (AFurn.LinePen.HasColour or (tpBorderColor in lineS.Present)) then
    for i := 0 to High(sp.Arrows) do
    begin
      e := Default(TTyChartElement);
      e.Style.Alpha := 1;
      e.Style.HasFill := True;
      e.Style.FillColor := lineK.Colour;
      e.CanvasM := TTyDoubleArray.Create(1, 0, 0, 1, sp.Arrows[i].X, sp.Arrows[i].Y);
      Add(cpkArrow, 11, False, e);
    end;
end;

{ the split lines' colours in the order their paths are added: each colour
  of the author's list a drawn line has (-1, the pen's, without one) }
function CompInksOf(AInkCount: Integer; const AIdx: TTyIntegerArray): TTyIntegerArray;
var k, q: Integer; has: Boolean;
begin
  Result := nil;
  if AInkCount = 0 then
  begin
    if Length(AIdx) > 0 then Result := TTyIntegerArray.Create(-1);
    Exit;
  end;
  for k := 0 to AInkCount - 1 do
  begin
    has := False;
    for q := 0 to High(AIdx) do
      if AIdx[q] = k then has := True;
    if has then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := k;
    end;
  end;
end;

procedure TTyCustomAdvanceChart.CompPolarSingleParts(var AParts: TTyCompPartArray);
var
  i, k, q, g, ink, n0: Integer;
  idx, aidx: TTyIntegerArray;
  ticks, minors, has: Boolean;
  v: TTySingleAxisView;
  pv: TTyPolarAxisView;
  none: TTyPolarLabelArray;
  { [R7-AC] the lines of a view as boxes: their rects, inks, drawn }
  bl: array of TTyRectF;
  bi: TTyIntegerArray;
  bd: array of Boolean;

  procedure Take(ADrawn: Boolean; AInk: Integer);
  begin
    if not ADrawn then Exit;
    SetLength(idx, Length(idx) + 1);
    idx[High(idx)] := AInk;
  end;

  procedure LinesOfS(const AL: TTySingleLineArray);
  var j: Integer;
  begin
    SetLength(bl, Length(AL));
    SetLength(bi, Length(AL));
    SetLength(bd, Length(AL));
    for j := 0 to High(AL) do
    begin
      bl[j] := TyRectF(Math.Min(AL[j].X1, AL[j].X2), Math.Min(AL[j].Y1, AL[j].Y2),
        Math.Max(AL[j].X1, AL[j].X2), Math.Max(AL[j].Y1, AL[j].Y2));
      bi[j] := AL[j].ColourIndex;
      bd[j] := AL[j].Drawn;
    end;
  end;

  procedure LinesOfP(const AL: TTyPolarLineArray);
  var j: Integer;
  begin
    SetLength(bl, Length(AL));
    SetLength(bi, Length(AL));
    SetLength(bd, Length(AL));
    for j := 0 to High(AL) do
    begin
      bl[j] := TyRectF(Math.Min(AL[j].X1, AL[j].X2), Math.Min(AL[j].Y1, AL[j].Y2),
        Math.Max(AL[j].X1, AL[j].X2), Math.Max(AL[j].Y1, AL[j].Y2));
      bi[j] := AL[j].ColourIndex;
      bd[j] := AL[j].Drawn;
    end;
  end;

  procedure CirclesOf(const AL: TTyPolarArcArray);
  var j: Integer;
  begin
    SetLength(bl, Length(AL));
    SetLength(bi, Length(AL));
    SetLength(bd, Length(AL));
    for j := 0 to High(AL) do
    begin
      bl[j] := TyRectF(AL[j].CX - AL[j].R, AL[j].CY - AL[j].R, AL[j].CX + AL[j].R, AL[j].CY + AL[j].R);
      bi[j] := AL[j].ColourIndex;
      bd[j] := True;
    end;
  end;

  { [R7-AC] A GRADIENT PEN'S BOX on a part: the last of its Lines (AMerged
    False: a Line each, the canvas keeping the last one's gradient), else
    the merged path's bounds -- the lines of AInk (-1 all) --, grown by the
    pen (a merged path is filled '#000': half the width; a Line or a
    radius axis' unfilled circles: max(width, 5)) }
  procedure BoxOn(var AEl: TTyChartElement; AMerged, AFilled: Boolean; AInk: Integer);
  var j: Integer; u: TTyRectF; any: Boolean;
  begin
    if AEl.Style.StrokeGradient.Kind = cgkNone then Exit;
    any := False;
    u := TyRectF(0, 0, 0, 0);
    for j := High(bl) downto 0 do
    begin
      if not bd[j] then Continue;
      if (AInk >= 0) and (bi[j] <> AInk) then Continue;
      if not any then u := bl[j]
      else
        u := TyRectF(Math.Min(u.Left, bl[j].Left), Math.Min(u.Top, bl[j].Top),
          Math.Max(u.Right, bl[j].Right), Math.Max(u.Bottom, bl[j].Bottom));
      any := True;
      if not AMerged then Break;
    end;
    if not any then Exit;
    AEl.Style.GradBoxSet := True;
    AEl.Style.GradBox := TyGrowByStroke(TyRectToXYWH(u), AFilled, AEl.Style.StrokeWidthLogical);
  end;

  { [R7-AE] A GRADIENT AXIS LINE'S BOX: the Line's (a single axis', a
    radius axis') ends, the angle axis' Circle, Arc or Ring through its
    path -- no fill, grown by max(width, 5) [was: none, the gradient made
    over the box of whatever took it next] }
  procedure LineBoxOn(var AEl: TTyChartElement; AShape: Integer; const ASLine: TTySingleLine;
    const APLine: TTyPolarLine; const AArc: TTyPolarArc);
  var bx: TTyXYWH; path: TTyZrPath;
  begin
    if AEl.Style.StrokeGradient.Kind = cgkNone then Exit;
    case AShape of
      0: bx := TyRectToXYWH(TyRectF(Math.Min(ASLine.X1, ASLine.X2), Math.Min(ASLine.Y1, ASLine.Y2),
        Math.Max(ASLine.X1, ASLine.X2), Math.Max(ASLine.Y1, ASLine.Y2)));
      1: bx := TyRectToXYWH(TyRectF(Math.Min(APLine.X1, APLine.X2), Math.Min(APLine.Y1, APLine.Y2),
        Math.Max(APLine.X1, APLine.X2), Math.Max(APLine.Y1, APLine.Y2)));
    else
      begin
        { Circle: moveTo(cx + r, cy), the whole turn; Arc: moveTo its start,
          the arc; Ring: the outer circle and the inner (the outer bounds) }
        path := nil;
        if AArc.Kind = pakArc then
        begin
          TyZrMoveTo(path, Cos(AArc.StartAngle) * AArc.R + AArc.CX, Sin(AArc.StartAngle) * AArc.R + AArc.CY);
          TyZrArc(path, AArc.CX, AArc.CY, AArc.R, AArc.StartAngle, AArc.EndAngle, not AArc.Clockwise);
        end
        else
        begin
          TyZrMoveTo(path, AArc.CX + AArc.R, AArc.CY);
          TyZrArc(path, AArc.CX, AArc.CY, AArc.R, 0, 2 * Pi, False);
        end;
        bx := TyZrBBox(path);
      end;
    end;
    AEl.Style.GradBoxSet := True;
    AEl.Style.GradBox := TyGrowByStroke(bx, False, AEl.Style.StrokeWidthLogical);
  end;

  { the parts a view added from AFrom: their boxes }
  procedure Boxes(AFrom, AShape: Integer; const ATicks, AMinors: TTyPolarLineArray;
    const ASTicks, ASMinors, ASSplits: TTySingleLineArray; const APSplits: TTyPolarLineArray;
    const ACircles: TTyPolarArcArray; AHasInks: Boolean; const ASLine: TTySingleLine;
    const APLine: TTyPolarLine; const AArc: TTyPolarArc);
  var j, ink2: Integer;
  begin
    for j := AFrom to High(AParts) do
    begin
      if AParts[j].El.Style.StrokeGradient.Kind = cgkNone then Continue;
      if AParts[j].Kind = cpkLine then
      begin
        LineBoxOn(AParts[j].El, AShape, ASLine, APLine, AArc);
        Continue;
      end;
      ink2 := -1;
      if (AParts[j].Kind = cpkSplit) and AHasInks then ink2 := AParts[j].El.Datum.DataIndex;
      case AShape of
        0:
          case AParts[j].Kind of
            cpkTick: begin LinesOfS(ASTicks); BoxOn(AParts[j].El, False, False, -1); end;
            cpkMinorTick: begin LinesOfS(ASMinors); BoxOn(AParts[j].El, False, False, -1); end;
            cpkSplit: begin LinesOfS(ASSplits); BoxOn(AParts[j].El, True, True, ink2); end;
          end;
        1:
          case AParts[j].Kind of
            cpkTick: begin LinesOfP(ATicks); BoxOn(AParts[j].El, False, False, -1); end;
            cpkMinorTick: begin LinesOfP(AMinors); BoxOn(AParts[j].El, False, False, -1); end;
            cpkSplit: begin CirclesOf(ACircles); BoxOn(AParts[j].El, True, False, ink2); end;
          end;
      else
        case AParts[j].Kind of
          cpkTick: begin LinesOfP(ATicks); BoxOn(AParts[j].El, True, True, -1); end;
          cpkMinorTick: begin LinesOfP(AMinors); BoxOn(AParts[j].El, True, True, -1); end;
          cpkSplit: begin LinesOfP(APSplits); BoxOn(AParts[j].El, True, True, ink2); end;
        end;
      end;
    end;
  end;

begin
  none := nil;
  { THE SINGLE AXES (their view first) }
  for i := 0 to High(FSingles) do
  begin
    if (FSingles[i] = nil) or ViewHidden(cvSingleAxis) then Continue;
    v := FSingles[i].View;
    if not v.Shown then Continue;
    idx := nil;
    for q := 0 to High(v.SplitLines) do Take(v.SplitLines[q].Drawn, v.SplitLines[q].ColourIndex);
    ticks := False;
    for q := 0 to High(v.Ticks) do if v.Ticks[q].Drawn then ticks := True;
    minors := False;
    for q := 0 to High(v.MinorTicks) do if v.MinorTicks[q].Drawn then minors := True;
    { a band each, in its colour (the skin's on the first of each pair) }
    aidx := nil;
    for q := 0 to High(v.SplitAreas) do
    begin
      ink := v.SplitAreas[q].ColourIndex;
      if Length(v.Furn.SplitAreaInks) > 0 then
      begin
        if ink > High(v.Furn.SplitAreaInks) then ink := 0;
      end
      else if ink <> 0 then Continue
      else ink := -1;
      SetLength(aidx, Length(aidx) + 1);
      aidx[High(aidx)] := ink;
    end;
    if not v.Furn.ShowSplitArea then aidx := nil;
    n0 := Length(AParts);
    CompViewParts(FSingles[i].Axis, 2000 + i, 0, v.Furn, v.Spec, v.HasLine,
      CompInksOf(Length(v.Furn.SplitLineInks), idx), ticks, minors, none, AParts, aidx);
    Boxes(n0, 0, nil, nil, v.Ticks, v.MinorTicks, v.SplitLines, nil, nil,
      Length(v.Furn.SplitLineInks) > 0, v.Line, Default(TTyPolarLine), Default(TTyPolarArc));
  end;
  { THE POLARS: the radius axes' view, then the angle axes' }
  for k := 0 to 1 do
    for i := 0 to High(FPolars) do
    begin
      if FPolars[i] = nil then Continue;
      if k = 0 then
      begin
        if ViewHidden(cvRadiusAxis) then Continue;
        pv := FPolars[i].RadiusView;
      end
      else
      begin
        if ViewHidden(cvAngleAxis) then Continue;
        pv := FPolars[i].AngleView;
      end;
      if not pv.Shown then Continue;
      idx := nil;
      if k = 0 then
        for q := 0 to High(pv.SplitCircles) do Take(True, pv.SplitCircles[q].ColourIndex)
      else
        for q := 0 to High(pv.SplitLines) do Take(pv.SplitLines[q].Drawn, pv.SplitLines[q].ColourIndex);
      ticks := False;
      for q := 0 to High(pv.Ticks) do if pv.Ticks[q].Drawn then ticks := True;
      minors := False;
      for q := 0 to High(pv.MinorTicks) do if pv.MinorTicks[q].Drawn then minors := True;
      { the merged split areas, a path a colour that has a band }
      aidx := nil;
      for g := 0 to Math.Max(0, High(pv.Furn.SplitAreaInks)) do
      begin
        has := False;
        for q := 0 to High(pv.SplitAreas) do
        begin
          ink := pv.SplitAreas[q].ColourIndex;
          if (Length(pv.Furn.SplitAreaInks) > 0) and (ink > High(pv.Furn.SplitAreaInks)) then ink := 0;
          if ink = g then has := True;
        end;
        if not has then Continue;
        SetLength(aidx, Length(aidx) + 1);
        if Length(pv.Furn.SplitAreaInks) > 0 then aidx[High(aidx)] := g
        else aidx[High(aidx)] := -1;
      end;
      n0 := Length(AParts);
      if k = 0 then
        CompViewParts(FPolars[i].RadiusAxis, 3000 + i, 1, pv.Furn, pv.Spec, pv.HasLine,
          CompInksOf(Length(pv.Furn.SplitLineInks), idx), ticks, minors, none, AParts, aidx)
      else
        CompViewParts(FPolars[i].AngleAxis, 4000 + i, 2, pv.Furn, pv.Spec, pv.HasLine,
          CompInksOf(Length(pv.Furn.SplitLineInks), idx), ticks, minors, pv.Labels, AParts, aidx);
      Boxes(n0, k + 1, pv.Ticks, pv.MinorTicks, nil, nil, nil, pv.SplitLines, pv.SplitCircles,
        Length(pv.Furn.SplitLineInks) > 0, Default(TTySingleLine), pv.Line, pv.LineArc);
    end;
end;

function TTyCustomAdvanceChart.CompPen(AOwner: TTyAxis; AKind: Byte;
  const K: TTyAxisStroke): TTyAxisStroke;
var i: Integer; e: TTyChartElement;
begin
  Result := K;
  CompSettlePen(AOwner, AKind, Result);
  for i := 0 to High(FCompParts) do
    if (FCompParts[i].Owner = AOwner) and (FCompParts[i].Kind = AKind) then
    begin
      e := FCompParts[i].El;
      e.CanvasFlags := 0;
      e.Style.StrokeColor := Result.Colour;
      e.Style.StrokeWidthLogical := Result.WidthLogical;
      e.Style.DashLogical := Copy(Result.Dash, 0, Length(Result.Dash));
      e.Style.DashOffsetLogical := Result.DashOffset;
      e.Style.LineCap := Ord(Result.Cap);
      TyCompStrokeLook(e.Style, Result);
      CompDrew(AOwner, FCompParts[i].Key, AKind, FCompParts[i].Z2, False, e);
      Exit;
    end;
end;

function TTyCustomAdvanceChart.CompText(AOwner: TTyAxis; AKind: Byte; AColour: TTyColor): TTyColor;
var i: Integer; e: TTyChartElement;
begin
  Result := TTyColor(CompSettleFill(AOwner, AKind, TTyChartColor(AColour)));
  for i := 0 to High(FCompParts) do
    if (FCompParts[i].Owner = AOwner) and (FCompParts[i].Kind = AKind) then
    begin
      e := FCompParts[i].El;
      e.Caption.Colour := TTyChartColor(Result);
      CompDrew(AOwner, FCompParts[i].Key, AKind, FCompParts[i].Z2, True, e);
      Exit;
    end;
end;

procedure TTyCustomAdvanceChart.CompTextDrawn(AOwner: TTyAxis; AKind: Byte;
  var AStyle: TTyStyleSet);
var n: Integer;
begin
  n := Length(FCompDrawn);
  AStyle.TextColor := CompText(AOwner, AKind, AStyle.TextColor);
  CompFont(AOwner, AKind, AStyle);
  { (the font it is drawn in, on the log CompText made) }
  if Length(FCompDrawn) > n then
  begin
    FCompDrawn[High(FCompDrawn)].El.Caption.FontName := AStyle.FontName;
    FCompDrawn[High(FCompDrawn)].El.Caption.FontSizeLogical := ResolveFontSize(AStyle);
    FCompDrawn[High(FCompDrawn)].El.Caption.FontWeight := AStyle.FontWeight;
  end;
end;

procedure TTyCustomAdvanceChart.CompRun(APPI: Integer);
var
  parts: TTyCompPartArray;
  g, a: Integer;
  gb: TTyGridBuild;
begin
  parts := nil;
  FCompDrawn := nil;
  { THE VIEWS IN UPSTREAM'S ORDER at an equal z and z2: the graphic's
    group, the grids' backgrounds (FGfxUnder, in its own order), the single
    axes, the radius axes, the angle axes, the y axes, the x axes --
    [R7-AD] each axis a view of its own (CompViewOf's numbers), so one x
    axis' parts of a z2 are all before the next one's [was: one view for
    every x axis, their parts interleaved by their count] }
  CompPolarSingleParts(parts);
  if FBuild <> nil then
    for g := 0 to FBuild.GridCount - 1 do
    begin
      gb := FBuild.Grid(g);
      for a := 0 to gb.YAxisCount - 1 do
        if gb.YAxis(a) <> nil then
          CompAxisParts(gb.YAxis(a), gb, 5000 + Max(0, gb.YAxis(a).ComponentIndex), parts);
      for a := 0 to gb.XAxisCount - 1 do
        if gb.XAxis(a) <> nil then
          CompAxisParts(gb.XAxis(a), gb, 6000 + Max(0, gb.XAxis(a).ComponentIndex), parts);
    end;
  FCompParts := parts;
  FCompBase := Length(parts);
  FCompNp := Length(parts);
  FCompRunOk := True;
  CompSettle(APPI, True);
end;

function TTyCustomAdvanceChart.CompViewOf(const AEl: TTyChartElement): Integer;
begin
  if AEl.CompView > 0 then Exit(AEl.CompView);
  case AEl.Datum.Kind of
    ctkGraphic: Result := 0;
    ctkMatrix: Result := 1500 + Max(0, AEl.Datum.ComponentIndex);
    ctkGeo: Result := 4600 + Max(0, AEl.Datum.ComponentIndex);
    ctkSeries:
      if AEl.Datum.SeriesIndex >= 0 then Result := 100000 + AEl.Datum.SeriesIndex
      else Result := 80000;
    ctkMarkPoint, ctkMarkLine, ctkMarkArea: Result := 90000;
  else
    Result := 80000;
  end;
end;

procedure TTyCustomAdvanceChart.CompViewSet(AList: TTyPaintList; AFrom, AView: Integer);
var k: Integer;
begin
  if AList = nil then Exit;
  for k := Max(0, AFrom) to AList.Count - 1 do AList.Ref(k)^.CompView := AView;
end;

{ two keys of the components' sort: z, z2, the view's place, the count }
function CompKeyLess(AZ, AZ2, AV, AQ, BZ, BZ2, BV, BQ: Integer): Boolean;
begin
  if AZ <> BZ then Exit(AZ < BZ);
  if AZ2 <> BZ2 then Exit(AZ2 < BZ2);
  if AV <> BV then Exit(AV < BV);
  Result := AQ < BQ;
end;

procedure TTyCustomAdvanceChart.CompBandMark;
var
  i, k, ng, h, lz, lz2, lv, lq, firstCont, lastCand: Integer;
  pe: PTyChartElement;
  lvs, cand: TTyIntegerArray;
  has: Boolean;

  { an element the continuous phase draws in its dynamic layer (AnimPartOf):
    a ripple, an effect symbol, a label hanging off one, a lines series'
    with a trail }
  function Cont(AIdx: Integer): Boolean;
  var q: PTyChartElement; hh: Integer;
  begin
    q := FPaintList.Ref(AIdx);
    Result := q^.Anim.Role in [carRipple, carEffectSymbol, carLinesEffect];
    if (not Result) and (q^.Datum.Kind = ctkSeries)
      and (LinesTrailAlpha(q^.Datum.SeriesIndex) > 0) then Result := True;
    if (not Result) and (q^.Anim.Role = carLabel) then
    begin
      hh := q^.Anim.HostPlus1 - 1;
      Result := (hh >= 0) and (hh < FPaintList.Count)
        and (FPaintList.Ref(hh)^.Anim.Role = carEffectSymbol);
    end;
  end;

begin
  { the marks of the last time off }
  if FPaintList <> nil then
    for k := 0 to High(FCompBand) do
      if (FCompBand[k] >= 0) and (FCompBand[k] < FPaintList.Count) then
      begin
        pe := FPaintList.Ref(FCompBand[k]);
        if pe^.CompBand then
        begin
          pe^.CompBand := False;
          pe^.GfxUnder := False;
        end;
      end;
  FCompBand := nil;
  if (FPaintList = nil) or not FPaintListValid or (FPaintList.Count = 0) then Exit;
  { (the levels drawn canvas by canvas: no band) }
  if ZMixedNow(lvs) then Exit;
  { THE LAST OF THE COMPONENTS' PARTS and of the graphic's elements under
    them (zlevel 0) }
  has := False;
  lz := 0; lz2 := 0; lv := 0; lq := 0;
  ng := 0;
  if FGfxUnder <> nil then ng := FGfxUnder.Count;
  for i := 0 to ng - 1 do
  begin
    pe := FGfxUnder.Ref(FGfxUnder.PaintOrder(i));
    if pe^.ZLevel <> 0 then Continue;
    if not has or CompKeyLess(lz, lz2, lv, lq, pe^.Z, pe^.Z2, 0, i) then
    begin
      lz := pe^.Z; lz2 := pe^.Z2; lv := 0; lq := i;
      has := True;
    end;
  end;
  for i := 0 to FCompNp - 1 do
    if not has or CompKeyLess(lz, lz2, lv, lq, FCompParts[i].Z, FCompParts[i].Z2,
      FCompParts[i].View, FCompParts[i].Seq) then
    begin
      lz := FCompParts[i].Z; lz2 := FCompParts[i].Z2;
      lv := FCompParts[i].View; lq := FCompParts[i].Seq;
      has := True;
    end;
  if not has then Exit;
  { THE LIST'S ELEMENTS SORTED BEFORE IT, in paint order (zlevel, z, z2,
    insertion: past its z and z2 nothing is) -- not a progressive run's
    (its own layer upstream), not the continuous phase's dynamic part }
  cand := nil;
  lastCand := -1;
  for i := 0 to FPaintList.Count - 1 do
  begin
    k := FPaintList.PaintOrder(i);
    pe := FPaintList.Ref(k);
    if pe^.ZLevel < 0 then Continue;
    if pe^.ZLevel > 0 then Break;
    if (pe^.Z > lz) or ((pe^.Z = lz) and (pe^.Z2 > lz2)) then Break;
    { (the graphic's: FGfxUnder's already) }
    if pe^.GfxUnder then Continue;
    if not CompKeyLess(pe^.Z, pe^.Z2, CompViewOf(pe^), k, lz, lz2, lv, lq) then Continue;
    if ProgIsLayered(pe^) then Continue;
    SetLength(cand, Length(cand) + 1);
    cand[High(cand)] := k;
    if k > lastCand then lastCand := k;
  end;
  if Length(cand) = 0 then Exit;
  { (AnimPartOf: from the first of the continuous phase's elements on,
    everything is its dynamic layer's) }
  firstCont := MaxInt;
  for i := 0 to lastCand do
    if Cont(i) then
    begin
      firstCont := i;
      Break;
    end;
  h := 0;
  for i := 0 to High(cand) do
    if cand[i] < firstCont then
    begin
      pe := FPaintList.Ref(cand[i]);
      pe^.GfxUnder := True;
      pe^.CompBand := True;
      cand[h] := cand[i];
      Inc(h);
    end;
  SetLength(cand, h);
  FCompBand := cand;
end;

procedure TTyCustomAdvanceChart.CompSettle(APPI: Integer; AList: Boolean);
var
  ng, np, n, i, j, t: Integer;
  ord: TTyIntegerArray;
  run: TTyCanvasRun;
  any, had: Boolean;
  pe: PTyChartElement;

  procedure KeyOf(AIdx: Integer; out AZ, AZ2, AView, ASeq: Integer);
  var q: PTyChartElement;
  begin
    if AIdx < ng then
    begin
      q := FGfxUnder.Ref(FGfxUnder.PaintOrder(AIdx));
      AZ := q^.Z;
      AZ2 := q^.Z2;
      AView := 0;
      ASeq := AIdx;
    end
    else if AIdx < ng + np then
    begin
      AZ := FCompParts[AIdx - ng].Z;
      AZ2 := FCompParts[AIdx - ng].Z2;
      AView := FCompParts[AIdx - ng].View;
      ASeq := FCompParts[AIdx - ng].Seq;
    end
    else
    begin
      { [R7-AD] a list element in the band: its view's place, its count }
      q := FPaintList.Ref(FCompBand[AIdx - ng - np]);
      AZ := q^.Z;
      AZ2 := q^.Z2;
      AView := CompViewOf(q^);
      ASeq := FCompBand[AIdx - ng - np];
    end;
  end;

  function Less(A, B: Integer): Boolean;
  var az, az2, av, aq, bz, bz2, bv, bq: Integer;
  begin
    KeyOf(A, az, az2, av, aq);
    KeyOf(B, bz, bz2, bv, bq);
    Result := CompKeyLess(az, az2, av, aq, bz, bz2, bv, bq);
  end;

begin
  had := Length(FCompBand) > 0;
  { [R7-AD] the list's elements among them }
  CompBandMark;
  ng := 0;
  if FGfxUnder <> nil then ng := FGfxUnder.Count;
  np := Min(FCompNp, Length(FCompParts));
  n := ng + np + Length(FCompBand);
  SetLength(ord, n);
  for i := 0 to n - 1 do ord[i] := i;
  { (a stable insertion sort: a few dozen) }
  for i := 1 to n - 1 do
  begin
    t := ord[i];
    j := i - 1;
    while (j >= 0) and Less(t, ord[j]) do
    begin
      ord[j + 1] := ord[j];
      Dec(j);
    end;
    ord[j + 1] := t;
  end;
  { [R7-AB] (the order, for a dirty block's own run) }
  FCompOrder := ord;
  FCompNg := ng;
  FCompNp := np;
  { FROM THE CANVAS' OWN STATE (a transparent shadow, black fill and
    stroke, a width of 1), in that order -- each settled where it stands }
  TyCanvasRunStart(run, TyCanvasGroundOf(0), APPI);
  any := False;
  for i := 0 to n - 1 do
  begin
    if ord[i] < ng then
    begin
      pe := FGfxUnder.Ref(FGfxUnder.PaintOrder(ord[i]));
      if pe^.ZLevel <> 0 then Continue;
      TyCanvasRunStep(run, pe^);
    end
    else if ord[i] < ng + np then
      TyCanvasRunStep(run, FCompParts[ord[i] - ng].El)
    else
      TyCanvasRunStep(run, FPaintList.Ref(FCompBand[ord[i] - ng - np])^);
    any := True;
  end;
  FCanvasGroundOk := any;
  if any then FCanvasGround := TyCanvasGroundOfRun(run);
  { [R7-AD] the rest of the list from the ground that leaves (the build
    settles its own: AList False) }
  if AList and (had or (Length(FCompBand) > 0)) and (FPaintList <> nil) and FPaintListValid
    and TyLinesCanvasLeftoversDue(FPaintList) then
    TyLinesCanvasLeftovers(FPaintList, CanvasGroundState, APPI);
end;

procedure TTyCustomAdvanceChart.ParRun;
var
  parts: TTyCompPartArray;
  i, a, q, j, t, n, z: Integer;
  par: TTyParallel;
  ticks, minors: Boolean;
  ord: array of Integer;
  run: TTyCanvasRun;
  none: TTyPolarLabelArray;
  node, d: TJSONData;

  function Less(A, B: Integer): Boolean;
  begin
    if parts[A].Z <> parts[B].Z then Exit(parts[A].Z < parts[B].Z);
    if parts[A].Z2 <> parts[B].Z2 then Exit(parts[A].Z2 < parts[B].Z2);
    if parts[A].View <> parts[B].View then Exit(parts[A].View < parts[B].View);
    Result := parts[A].Seq < parts[B].Seq;
  end;

begin
  SetLength(FCompParts, Min(FCompBase, Length(FCompParts)));
  if (Length(FParallels) = 0) or ViewHidden(cvParallelAxis) then Exit;
  parts := nil;
  none := nil;
  z := 10;
  for i := 0 to High(FParallels) do
  begin
    par := FParallels[i];
    if par = nil then Continue;
    for a := 0 to High(par.Views) do
    begin
      if not par.Views[a].Shown or (a >= par.AxisCount) then Continue;
      ticks := False;
      for q := 0 to High(par.Views[a].Ticks) do if par.Views[a].Ticks[q].Drawn then ticks := True;
      minors := False;
      for q := 0 to High(par.Views[a].MinorTicks) do
        if par.Views[a].MinorTicks[q].Drawn then minors := True;
      n := Length(parts);
      { a ParallelAxisView an axis, in the axes' order }
      CompViewParts(par.Axis(a), 1000 * (i + 1) + a, 0, par.Views[a].Furn, par.Views[a].Spec,
        par.Views[a].HasLine, nil, ticks, minors, none, parts, nil);
      { [R7-AE] A GRADIENT LINE'S BOX: the Line's ends grown by the pen, at
        least the strokeContainThreshold ParallelAxisView gives the builder
        -- areaSelectStyle's width [was: none] }
      for q := n to High(parts) do
        if (parts[q].Kind = cpkLine) and (parts[q].El.Style.StrokeGradient.Kind <> cgkNone)
          and (parts[q].El.Style.StrokeWidthLogical > 0)
          and (a <= High(par.AxisIndices)) then
        begin
          parts[q].El.Style.GradBoxSet := True;
          parts[q].El.Style.GradBox := TyGrowByStroke(TyRectToXYWH(TyRectF(
            Math.Min(par.Views[a].Line.X1, par.Views[a].Line.X2), Math.Min(par.Views[a].Line.Y1, par.Views[a].Line.Y2),
            Math.Max(par.Views[a].Line.X1, par.Views[a].Line.X2), Math.Max(par.Views[a].Line.Y1, par.Views[a].Line.Y2))),
            False, Math.Max(parts[q].El.Style.StrokeWidthLogical,
              TyParallelSelectStyleOf(FOption.ComponentAt('parallelAxis', par.AxisIndices[a])).Width));
        end;
      { the axis' z (its model's default 10) }
      if a <= High(par.AxisIndices) then
      begin
        node := FOption.ComponentAt('parallelAxis', par.AxisIndices[a]);
        z := 10;
        if node is TJSONObject then
        begin
          d := TJSONObject(node).Find('z');
          if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat) and not IsInfinite(d.AsFloat) then
            z := Round(Max(Double(-100000), Min(Double(100000), d.AsFloat)));
        end;
        for q := n to High(parts) do parts[q].Z := z;
      end;
    end;
  end;
  if Length(parts) = 0 then Exit;
  SetLength(ord, Length(parts));
  for i := 0 to High(ord) do ord[i] := i;
  for i := 1 to High(ord) do
  begin
    t := ord[i];
    j := i - 1;
    while (j >= 0) and Less(t, ord[j]) do
    begin
      ord[j + 1] := ord[j];
      Dec(j);
    end;
    ord[j + 1] := t;
  end;
  { FROM WHERE THE LIST'S RUN REACHES THE FIRST AXIS' z }
  CompRunTo(parts[ord[0]].Z, -MaxInt, run);
  for i := 0 to High(ord) do TyCanvasRunStep(run, parts[ord[i]].El);
  n := Length(FCompParts);
  SetLength(FCompParts, n + Length(parts));
  for i := 0 to High(parts) do FCompParts[n + i] := parts[i];
end;

procedure TTyCustomAdvanceChart.CompRunTo(AZ, AZ2: Integer; out ARun: TTyCanvasRun);
var
  i: Integer;
  pe: PTyChartElement;
begin
  TyCanvasRunStart(ARun, CanvasGroundState, FLastPPI);
  if FPaintList = nil then Exit;
  for i := 0 to FPaintList.Count - 1 do
  begin
    pe := FPaintList.Ref(FPaintList.PaintOrder(i));
    { (the list's zlevel 0 first: another is another canvas; [R7-AA] the
      graphic's elements under the axes are the ground's already) }
    if (pe^.ZLevel <> 0) or pe^.GfxUnder then Continue;
    if (pe^.Z > AZ) or ((pe^.Z = AZ) and (pe^.Z2 > AZ2)) then Break;
    TyCanvasRunStep(ARun, pe^);
  end;
end;

procedure TTyCustomAdvanceChart.CompTextFont(AAxis: TTyAxis; const ABlock: string;
  const AStyle: TTyStyleSet; var AEl: TTyChartElement);
var node, blk, ts: TJSONData; parts: array[0..2] of TJSONData; k: Integer;
const cKeys: array[0..2] of string = ('fontStyle', 'fontWeight', 'fontSize');
begin
  AEl.Caption.FontName := AStyle.FontName;
  AEl.Caption.FontSizeLogical := ResolveFontSize(AStyle);
  AEl.Caption.FontWeight := AStyle.FontWeight;
  if (AAxis = nil) or (FOption = nil) then Exit;
  node := FOption.ComponentAt(AAxis.MainType, AAxis.ComponentIndex);
  blk := nil;
  if node is TJSONObject then blk := TJSONObject(node).Find(ABlock);
  ts := nil;
  if FOption.Root is TJSONObject then ts := TJSONObject(FOption.Root).Find('textStyle');
  for k := 0 to 2 do
  begin
    parts[k] := nil;
    if blk is TJSONObject then parts[k] := TJSONObject(blk).Find(cKeys[k]);
    if ((parts[k] = nil) or (parts[k].JSONType = jtNull)) and (ts is TJSONObject) then
      parts[k] := TJSONObject(ts).Find(cKeys[k]);
  end;
  if TyCssFontRefused(parts[0], parts[1], parts[2]) then
    AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasFontLeft;
end;

procedure TTyCustomAdvanceChart.CompFont(AOwner: TObject; AKind: Byte; var AStyle: TTyStyleSet);
var i: Integer;
begin
  for i := 0 to High(FCompParts) do
    if (FCompParts[i].Owner = AOwner) and (FCompParts[i].Kind = AKind)
      and ((FCompParts[i].El.CanvasFlags and cTyCanvasFontLeft) <> 0) then
    begin
      AStyle.FontName := FCompParts[i].El.Caption.FontName;
      AStyle.FontSize := FCompParts[i].El.Caption.FontSizeLogical;
      Include(AStyle.Present, tpFontSize);
      AStyle.FontWeight := FCompParts[i].El.Caption.FontWeight;
      Exit;
    end;
end;

function TTyCustomAdvanceChart.FontRefusedOf(const ANodes: array of TJSONData): Boolean;
var parts: array[0..2] of TJSONData; k, j: Integer; ts: TJSONData;
const cKeys: array[0..2] of string = ('fontStyle', 'fontWeight', 'fontSize');
begin
  ts := nil;
  if (FOption <> nil) and (FOption.Root is TJSONObject) then ts := TJSONObject(FOption.Root).Find('textStyle');
  for k := 0 to 2 do
  begin
    parts[k] := nil;
    for j := 0 to High(ANodes) do
      if ANodes[j] is TJSONObject then
      begin
        parts[k] := TJSONObject(ANodes[j]).Find(cKeys[k]);
        if (parts[k] <> nil) and (parts[k].JSONType <> jtNull) then Break;
        parts[k] := nil;
      end;
    if ((parts[k] = nil) or (parts[k].JSONType = jtNull)) and (ts is TJSONObject) then
      parts[k] := TJSONObject(ts).Find(cKeys[k]);
  end;
  Result := TyCssFontRefused(parts[0], parts[1], parts[2]);
end;

procedure TTyCustomAdvanceChart.FontLeftFrom(AList: TTyPaintList; AFrom: Integer; ARefused: Boolean);
var k: Integer; pe: PTyChartElement;
begin
  if not ARefused or (AList = nil) then Exit;
  for k := Max(0, AFrom) to AList.Count - 1 do
  begin
    pe := AList.Ref(k);
    if (pe^.Caption.Text <> '') and (Length(pe^.Caption.RtPieces) = 0) then
      pe^.CanvasFlags := pe^.CanvasFlags or cTyCanvasFontLeft;
  end;
end;

function TTyCustomAdvanceChart.CompPieces(AOwner: TObject; AKind: Byte; AIndex: Integer): TTyRtPieceArray;
var i: Integer;
begin
  Result := nil;
  for i := 0 to Min(FCompNp, Length(FCompParts)) - 1 do
    if (FCompParts[i].Owner = AOwner) and (FCompParts[i].Kind = AKind)
      and (FCompParts[i].El.Datum.RawDataIndex = AIndex)
      and (Length(FCompParts[i].El.Caption.RtPieces) > 0) then
      Exit(Copy(FCompParts[i].El.Caption.RtPieces, 0, MaxInt));
end;

procedure TTyCustomAdvanceChart.CompRect(AOwner: TObject; AKind: Byte; const AR: TTyXYWH;
  APen: Double; AText: Boolean; AIndex: Integer; ABlur, AOffX, AOffY: Double);
var n: Integer; r: TTyXYWH; w: Double;
begin
  r := AR;
  { getPaintRect: a stroked path's getBoundingRect grows by its width (a
    path of no fill by max(width, strokeContainThreshold 5)), then floored
    and ceiled and one more -- a text span's by its dirtyRectTolerance (10)
    on every side }
  if APen > 0 then
  begin
    w := Max(APen, 5);
    r.X := r.X - w / 2;
    r.Y := r.Y - w / 2;
    r.W := r.W + w;
    r.H := r.H + w;
  end;
  { ([R7-AB after R7-AA] and by the shadow it casts: the blur on every side,
    the offsets) }
  if AText then r := TyZrPaintRect(r, ABlur, AOffX, AOffY, cTyTextDirtyTolerance)
  else r := TyZrPaintRect(r, ABlur, AOffX, AOffY, 0);
  n := Length(FCompRects);
  SetLength(FCompRects, n + 1);
  FCompRects[n].Owner := AOwner;
  FCompRects[n].Kind := AKind;
  FCompRects[n].R := r;
  FCompRects[n].Index := AIndex;
end;

procedure TTyCustomAdvanceChart.CompPenRect(APainter: TTyPainter; AOwner: TObject;
  AKind: Byte; const K: TTyAxisStroke; const AR: TTyXYWH; AFilled: Boolean; AIndex: Integer);
var r: TTyXYWH; w, sb, sx, sy: Double;
begin
  if APainter = nil then Exit;
  r := AR;
  w := 0;
  if K.Drawn and (K.WidthLogical > 0) then w := APainter.ScaleF(K.WidthLogical);
  sb := 0;
  sx := 0;
  sy := 0;
  if K.HasShadow then
  begin
    if not (IsNan(K.Shadow.Blur) or IsInfinite(K.Shadow.Blur)) then sb := APainter.ScaleF(K.Shadow.Blur);
    if not (IsNan(K.Shadow.OffsetX) or IsInfinite(K.Shadow.OffsetX) or TyPhaseLeft(K.Shadow.OffsetX)) then
      sx := APainter.ScaleF(K.Shadow.OffsetX);
    if not (IsNan(K.Shadow.OffsetY) or IsInfinite(K.Shadow.OffsetY) or TyPhaseLeft(K.Shadow.OffsetY)) then
      sy := APainter.ScaleF(K.Shadow.OffsetY);
  end;
  if AFilled then
  begin
    if w > 0 then
    begin
      r.X := r.X - w / 2;
      r.Y := r.Y - w / 2;
      r.W := r.W + w;
      r.H := r.H + w;
    end;
    CompRect(AOwner, AKind, r, 0, False, AIndex, sb, sx, sy);
  end
  else
    CompRect(AOwner, AKind, r, w, False, AIndex, sb, sx, sy);
end;

procedure TTyCustomAdvanceChart.CompTextRect(AOwner: TObject; AKind: Byte; AX, AY: Double;
  AW, AH: Integer; AH2: TTyTextAnchorH; AV: TTyTextAnchorV; ARot: Double);
var b: TRect; r: TTyXYWH; c, s, x, y: Double; k: Integer;
  xs, ys: array[0..3] of Double;
begin
  case AH2 of
    tahLeft: begin b.Left := Round(AX); b.Right := Round(AX) + AW; end;
    tahRight: begin b.Left := Round(AX) - AW; b.Right := Round(AX); end;
  else
    begin
      b.Left := Round(AX - AW / 2);
      b.Right := b.Left + AW;
    end;
  end;
  case AV of
    tavTop: begin b.Top := Round(AY); b.Bottom := Round(AY) + AH; end;
    tavBottom: begin b.Top := Round(AY) - AH; b.Bottom := Round(AY); end;
  else
    begin
      b.Top := Round(AY - AH / 2);
      b.Bottom := b.Top + AH;
    end;
  end;
  if Abs(ARot) < 1e-9 then
    r := TyRectToXYWH(TyRectF(b.Left, b.Top, b.Right, b.Bottom))
  else
  begin
    c := Cos(ARot);
    s := Sin(ARot);
    xs[0] := b.Left; ys[0] := b.Top;
    xs[1] := b.Right; ys[1] := b.Top;
    xs[2] := b.Right; ys[2] := b.Bottom;
    xs[3] := b.Left; ys[3] := b.Bottom;
    r := TyRectToXYWH(TyRectF(AX, AY, AX, AY));
    for k := 0 to 3 do
    begin
      x := AX + (xs[k] - AX) * c + (ys[k] - AY) * s;
      y := AY - (xs[k] - AX) * s + (ys[k] - AY) * c;
      TyZrRectUnion(r, TyRectToXYWH(TyRectF(x, y, x, y)));
    end;
  end;
  CompRect(AOwner, AKind, r, 0, True);
end;

function TTyCustomAdvanceChart.CanvasGroundIn(const ABlock: TTyXYWH; APPI: Integer): TTyCanvasGround;
var
  run: TTyCanvasRun;
  i, k, p, ix: Integer;
  pe: PTyChartElement;
  el: TTyChartElement;
  r: TTyXYWH;
  any, meets, drawn: Boolean;
begin
  if not FCompRunOk or (Length(FCompOrder) = 0) then Exit(CanvasGroundState);
  TyCanvasRunStart(run, TyCanvasGroundOf(0), APPI);
  any := False;
  for i := 0 to High(FCompOrder) do
  begin
    p := FCompOrder[i];
    if p < FCompNg then
    begin
      if (FGfxUnder = nil) or (p >= FGfxUnder.Count) then Continue;
      pe := FGfxUnder.Ref(FGfxUnder.PaintOrder(p));
      if pe^.ZLevel <> 0 then Continue;
      if TyElementPaintRect(pe^, APPI, r) and not TyZrRectIntersect(r, ABlock) then Continue;
      el := pe^;
    end
    else if p >= FCompNg + FCompNp then
    begin
      { [R7-AD] a list element in the components' band }
      p := p - FCompNg - FCompNp;
      if (p > High(FCompBand)) or (FPaintList = nil) or (FCompBand[p] >= FPaintList.Count) then Continue;
      pe := FPaintList.Ref(FCompBand[p]);
      if not pe^.CompBand then Continue;
      if TyElementPaintRect(pe^, APPI, r) and not TyZrRectIntersect(r, ABlock) then Continue;
      el := pe^;
      SetLength(el.Caption.RtPieces, Length(el.Caption.RtPieces));
    end
    else
    begin
      p := p - FCompNg;
      if p > High(FCompParts) then Continue;
      { the rects its kind was drawn at: one meeting the block; none
        recorded, every block -- [R7-AB after R7-AA] a split line and a
        split area band (a Line a mark, a Rect a band) its own }
      ix := -1;
      if FCompParts[p].Kind in [cpkSplit, cpkSplitArea] then ix := FCompParts[p].El.Datum.RawDataIndex;
      meets := False;
      drawn := False;
      for k := 0 to High(FCompRects) do
        if (FCompRects[k].Owner = FCompParts[p].Owner) and (FCompRects[k].Kind = FCompParts[p].Kind)
          and ((ix < 0) or (FCompRects[k].Index < 0) or (FCompRects[k].Index = ix)) then
        begin
          drawn := True;
          if TyZrRectIntersect(FCompRects[k].R, ABlock) then
          begin
            meets := True;
            Break;
          end;
        end;
      if drawn and not meets then Continue;
      el := FCompParts[p].El;
    end;
    TyCanvasRunStep(run, el);
    any := True;
  end;
  if any then Result := TyCanvasGroundOfRun(run)
  else Result := TyCanvasGroundOf(0);
end;

function TTyCustomAdvanceChart.CompPartOf(AOwner: TObject; AKind: Byte): PTyChartElement;
var i: Integer;
begin
  Result := nil;
  for i := 0 to High(FCompParts) do
    if (FCompParts[i].Owner = AOwner) and (FCompParts[i].Kind = AKind) then
      Exit(@FCompParts[i].El);
end;

procedure TTyCustomAdvanceChart.CompSettlePen(AOwner: TObject; AKind: Byte;
  var K: TTyAxisStroke);
var p: PTyChartElement;
begin
  if K.Left = 0 then Exit;
  p := CompPartOf(AOwner, AKind);
  if p = nil then
  begin
    { not run (on a canvas of its own, first there): the canvas' defaults }
    if (K.Left and cTyCanvasStrokeLeft) <> 0 then K.Colour := TTyChartColor($FF000000);
    if (K.Left and cTyCanvasWidthLeft) <> 0 then K.WidthLogical := 1;
    if (K.Left and cTyCanvasPhaseLeftFlag) <> 0 then K.DashOffset := 0;
    if (K.Left and cTyCanvasCapLeft) <> 0 then K.Cap := acButt;
    { [R7-AA] }
    if (K.Left and cTyCanvasShadowLeft) <> 0 then K.Shadow.Color := 0;
    if (K.Left and cTyCanvasBlurLeft) <> 0 then K.Shadow.Blur := 0;
    if (K.Left and cTyCanvasJoinLeft) <> 0 then K.Join := 0;
    if (K.Left and cTyCanvasMiterLeft) <> 0 then K.Miter := 10;
  end
  else
  begin
    if (K.Left and cTyCanvasStrokeLeft) <> 0 then
    begin
      K.Colour := p^.Style.StrokeColor;
      { [R7-AA] a gradient the canvas holds (in its own frame) }
      K.Gradient := p^.Style.StrokeGradient;
    end;
    if (K.Left and cTyCanvasWidthLeft) <> 0 then K.WidthLogical := p^.Style.StrokeWidthLogical;
    { [R7-AA] a shadowColor, a blur, a join, a miterLimit refused }
    if (K.Left and cTyCanvasShadowLeft) <> 0 then K.Shadow.Color := p^.Style.ShadowColor;
    if (K.Left and cTyCanvasBlurLeft) <> 0 then K.Shadow.Blur := p^.Style.ShadowBlur;
    if (K.Left and cTyCanvasJoinLeft) <> 0 then K.Join := p^.Style.LineJoin;
    if (K.Left and cTyCanvasMiterLeft) <> 0 then K.Miter := p^.Style.MiterLimit;
    if (K.Left and cTyCanvasPhaseLeftFlag) <> 0 then K.DashOffset := p^.Style.DashOffsetLogical;
    if (K.Left and cTyCanvasCapLeft) <> 0 then
      case p^.Style.LineCap of
        1: K.Cap := acRound;
        2: K.Cap := acSquare;
      else
        K.Cap := acButt;
      end;
  end;
  K.Left := 0;
end;

function TTyCustomAdvanceChart.CompInkOf(AOwner: TObject; AKind: Byte;
  AInk: Integer): TTyChartColor;
var i: Integer;
begin
  for i := 0 to High(FCompParts) do
    if (FCompParts[i].Owner = AOwner) and (FCompParts[i].Kind = AKind)
      and (FCompParts[i].El.Datum.DataIndex = AInk) then
    begin
      if FCompParts[i].El.Style.HasFill then Exit(FCompParts[i].El.Style.FillColor);
      Exit(FCompParts[i].El.Style.StrokeColor);
    end;
  Result := TTyChartColor($FF000000);
end;

function TTyCustomAdvanceChart.CompBandInk(AOwner: TObject; AKind: Byte;
  ABand: Integer): TTyChartColor;
var i: Integer;
begin
  for i := 0 to High(FCompParts) do
    if (FCompParts[i].Owner = AOwner) and (FCompParts[i].Kind = AKind)
      and (FCompParts[i].El.Datum.RawDataIndex = ABand) then
      Exit(FCompParts[i].El.Style.FillColor);
  Result := TTyChartColor($FF000000);
end;

function TTyCustomAdvanceChart.CompSettleFill(AOwner: TObject; AKind: Byte;
  AColour: TTyChartColor): TTyChartColor;
var p: PTyChartElement;
begin
  Result := AColour;
  if AColour <> cTyCanvasColourLeft then Exit;
  p := CompPartOf(AOwner, AKind);
  if p = nil then Exit(TTyChartColor($FF000000));
  if p^.Caption.FontSizeLogical <> 0 then Result := p^.Caption.Colour
  else Result := p^.Style.FillColor;
end;

procedure TTyCustomAdvanceChart.CompDrew(AOwner: TObject; const AKey: string; AKind: Byte;
  AZ2: Integer; AText: Boolean; const AEl: TTyChartElement);
var n: Integer;
begin
  { (a log for the tests: a frame's worth, not a history) }
  if Length(FCompDrawn) >= 4096 then FCompDrawn := nil;
  n := Length(FCompDrawn);
  SetLength(FCompDrawn, n + 1);
  FCompDrawn[n].Owner := AOwner;
  FCompDrawn[n].Key := AKey;
  FCompDrawn[n].Kind := AKind;
  FCompDrawn[n].Z2 := AZ2;
  FCompDrawn[n].IsText := AText;
  FCompDrawn[n].El := AEl;
end;

procedure TTyCustomAdvanceChart.CompDrewArea(AOwner: TTyAxis; AColour: TTyChartColor);
var e: TTyChartElement;
begin
  if AOwner = nil then Exit;
  e := Default(TTyChartElement);
  e.Style.Alpha := 1;
  e.Style.HasFill := True;
  e.Style.FillColor := AColour;
  CompDrew(AOwner, AOwner.MainType + IntToStr(AOwner.ComponentIndex), cpkSplitArea, 0, False, e);
end;

function TTyCustomAdvanceChart.CompDrawn: TTyCompPartArray;
begin
  Result := FCompDrawn;
end;

function TTyCustomAdvanceChart.CompRectsDrawn: TTyCompRectArray;
begin
  Result := FCompRects;
end;

procedure TTyCustomAdvanceChart.PaintAxes(APainter: TTyPainter; APPI: Integer;
  const AMeasurer: ITyTextMeasurer; AProxied: Boolean; AList: TTyPaintList; AGfx: Boolean);
var
  g, a, i, p, k, n, z2: Integer;
  gb: TTyGridBuild;
  pe: PTyChartElement;
  el: TTyChartElement;
  axes: array of TTyAxis;
  grids: array of TTyGridBuild;
  done: array of TTyAxisZ2Set;
  sinGrid, sinAxes, polGrid, polAxes: Boolean;
  v: Integer;

  function AxisAt(AAxis: TObject): Integer;
  var q: Integer;
  begin
    for q := 0 to High(axes) do
      if axes[q] = AAxis then Exit(q);
    Result := -1;
  end;

begin
  if FBuild = nil then Exit;
  { [R7-AB] where the parts are drawn, afresh }
  FCompRects := nil;
  { [R7-Z] the parts settled in upstream's order (a layer drawn without the
    static one's GfxPaintUnder: the last ones) }
  if not FCompRunOk then CompRun(APPI);
  { the cartesian axes, grid by grid (x then y, as they were drawn) }
  n := 0;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    for a := 0 to gb.XAxisCount - 1 do
    begin
      SetLength(axes, n + 1);
      SetLength(grids, n + 1);
      axes[n] := gb.XAxis(a);
      grids[n] := gb;
      Inc(n);
    end;
    for a := 0 to gb.YAxisCount - 1 do
    begin
      SetLength(axes, n + 1);
      SetLength(grids, n + 1);
      axes[n] := gb.YAxis(a);
      grids[n] := gb;
      Inc(n);
    end;
  end;
  SetLength(done, n);
  for i := 0 to n - 1 do done[i] := [];
  sinGrid := False;
  sinAxes := False;
  polGrid := False;
  polAxes := False;
  { [R7-AD] IN CompRun'S ORDER: zrender sorts the display list by z, z2 and
    insertion (the root's views in turn), so a radar's or a geo's parts, a
    series of a lower z, the graphic's elements fall among the axes' parts
    -- a cartesian axis' drawn z2 by z2 where its parts come, a polar's or
    a single axis' views at their first part (the grid pass, then the
    axes' at the first part above z2 0).
    [Was: the polars, the single axes, then every x axis' grid, every y
    axis' grid, every x axis, every y axis; the graphic's elements before
    them all, the list after.] }
  for i := 0 to High(FCompOrder) do
  begin
    p := FCompOrder[i];
    if p < FCompNg then
    begin
      if not AGfx or (FGfxUnder = nil) or (p >= FGfxUnder.Count) then Continue;
      el := FGfxUnder.Element(FGfxUnder.PaintOrder(p));
      if el.Ignore or not ApartIn(el.ZLevel) then Continue;
      TyRenderElement(APainter, el);
      { [R7-Z] (CompDrawn) }
      if el.Datum.Kind = ctkGraphic then
        CompDrew(nil, 'graphic0', 0, el.Z2, el.Caption.FontSizeLogical <> 0, el);
      Continue;
    end;
    if p >= FCompNg + FCompNp then
    begin
      if AList = nil then Continue;
      k := p - FCompNg - FCompNp;
      if k > High(FCompBand) then Continue;
      k := FCompBand[k];
      if (k < 0) or (k >= AList.Count) then Continue;
      pe := AList.Ref(k);
      if pe^.CompBand and not pe^.Ignore and not pe^.ProgHidden then TyRenderElement(APainter, pe^);
      Continue;
    end;
    p := p - FCompNg;
    if p > High(FCompParts) then Continue;
    v := FCompParts[p].View;
    if (v >= 2000) and (v < 3000) then
    begin
      if not sinGrid then PaintSingles(APainter, APPI, AMeasurer, True);
      sinGrid := True;
      if (FCompParts[p].Z2 > 0) and not sinAxes then
      begin
        PaintSingles(APainter, APPI, AMeasurer, False);
        sinAxes := True;
      end;
      Continue;
    end;
    if (v >= 3000) and (v < 5000) then
    begin
      if not polGrid then PaintPolars(APainter, APPI, AMeasurer, True);
      polGrid := True;
      if (FCompParts[p].Z2 > 0) and not polAxes then
      begin
        PaintPolars(APainter, APPI, AMeasurer, False);
        polAxes := True;
      end;
      Continue;
    end;
    a := AxisAt(FCompParts[p].Owner);
    if a < 0 then Continue;
    z2 := Max(0, Min(31, FCompParts[p].Z2));
    if z2 in done[a] then Continue;
    Include(done[a], z2);
    PaintAxis(APainter, axes[a], grids[a].PlotRect, APPI, grids[a], AMeasurer, [z2], AProxied);
  end;
  { WHAT NO PART ASKED FOR, as it was drawn: a view whose parts the run
    does not hold, an axis' pieces of no part }
  if not sinGrid then PaintSingles(APainter, APPI, AMeasurer, True);
  if not sinAxes then PaintSingles(APainter, APPI, AMeasurer, False);
  if not polGrid then PaintPolars(APainter, APPI, AMeasurer, True);
  if not polAxes then PaintPolars(APainter, APPI, AMeasurer, False);
  for a := 0 to n - 1 do
    if done[a] <> [0..31] then
      PaintAxis(APainter, axes[a], grids[a].PlotRect, APPI, grids[a], AMeasurer,
        [0..31] - done[a], AProxied);
end;

function TTyCustomAdvanceChart.StackFor(ASlot: Integer): TTySeriesStack;
begin
  if (ASlot >= 0) and (ASlot <= High(FStacks)) then
    Result := FStacks[ASlot]
  else
  begin
    Result := Default(TTySeriesStack);
    Result.ResultCol := -1;
    Result.OverCol := -1;
  end;
end;

function TTyCustomAdvanceChart.LabelStepFor(AAxis: TTyAxis): Integer;
var
  g: Integer;
  spec: PTyAxisLayoutSpec;
begin
  Result := 1;
  if (AAxis = nil) or (FBuild = nil) then Exit;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    spec := FBuild.Grid(g).SpecFor(AAxis);
    if spec <> nil then
    begin
      if spec^.LabelStep > 1 then Result := spec^.LabelStep;
      Exit;
    end;
  end;
end;

{ One whole number off a series node, ADefault when it is absent or is not a
  number. Rounded rather than truncated: `z: 1.5` is somebody's mistake, and
  the two neighbouring answers are both defensible -- the nearer one is the
  one the author was closer to meaning. }
function TTyCustomAdvanceChart.SeriesIntIn(ASeriesIndex: Integer;
  const AKey: string; ADefault: Integer): Integer;
var
  d: TJSONData;
  node: TJSONObject;
  v: Double;
begin
  Result := ADefault;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find(AKey);
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  v := d.AsFloat;
  if IsNan(v) or IsInfinite(v) then Exit;
  { CLAMPED, because Round targets an Int64 and the paint list's key is an
    Integer -- a z of 1e18 is not an order, it is an overflow. }
  v := Max(Double(-100000), Min(Double(100000), v));
  Result := Round(v);
end;

function TTyCustomAdvanceChart.SymbolFor(ASlot: Integer): TTySymbolSpec;
const
  cRootKeys: array[0..3] of string = ('symbol', 'symbolRotate', 'symbolKeepAspect',
    'symbolOffset');
var
  d, own: TJSONData;
  node, under: TJSONObject;
  k: Integer;
  t: string;
  empty: Boolean;
  path: string;

  { a series key written as a callback ('@Name'): the series' own value is
    the function }
  function IsCb(const AKey: string): Boolean;
  begin
    own := node.Find(AKey);
    Result := (own <> nil) and (own.JSONType = jtString) and TyChartIsHandlerRef(own.AsString);
  end;

begin
  Result := TySymbolDefault('');
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  t := FBindings[ASlot].SeriesType;
  Result := TySymbolDefault(t);
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  { THE OPTION ROOT UNDER THE SERIES [R2-G]: the series model's parent is
    the GlobalModel, so a root symbolRotate, symbolKeepAspect or
    symbolOffset reaches every series (no type has a default), and a root
    symbol a scatter's (whose circle is seriesSymbolTask's fallback, not a
    default); symbolSize every such type has }
  if FOption.Root is TJSONObject then
  begin
    under := TJSONObject.Create;
    try
      for k := 0 to High(cRootKeys) do
      begin
        if (k = 0) and (t <> 'scatter') and (t <> 'effectScatter') then Continue;
        { [r2v] NOT UNDER A CALLBACK: seriesModel.get(key) answers the
          series' function, never the root's -- an item the callback leaves
          undefined has no value of the key (symbol.ts' seriesSymbolTask
          sets no series visual for it) }
        if IsCb(cRootKeys[k]) then Continue;
        d := TJSONObject(FOption.Root).Find(cRootKeys[k]);
        if (d <> nil) and (d.JSONType <> jtNull) then under.Add(cRootKeys[k], d.Clone);
      end;
      if under.Count > 0 then Result := TySymbolSpecOf(under, Result);
    finally
      under.Free;
    end;
  end;
  Result := TySymbolSpecOf(node, Result);
  { [r2v] a symbol callback: the series visual is seriesModel.defaultSymbol
    ('circle' for every series that reads it here), not the type's own
    default -- a line's emptyCircle is its defaultOption, which the
    function replaced }
  if IsCb('symbol') then
  begin
    Result.Kind := TySymbolKindOf('circle', empty, path);
    Result.Empty := empty;
    Result.PathData := path;
  end;
end;

procedure TTyCustomAdvanceChart.PaintSeries(APainter: TTyPainter;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
begin
  PrepareSeries(AMeasurer, APPI);
  RenderSeries(APainter, AMeasurer, APPI);
end;

procedure TTyCustomAdvanceChart.PrepareSeries(const AMeasurer: ITyTextMeasurer; APPI: Integer);
var
  drawn: Integer;
  built, prepped, fresh: Boolean;
begin
  FZList := nil;
  { WHAT THE STATIC LAYER HOLDS, for the dirty-rect path: one list at rest,
    or nil [Batch 142] }
  FDrStaticList := nil;
  { A DIRTY-RECT FALLBACK after the partial repaint's preparation: the list
    is built and prepared for this frame already [Batch 142] }
  prepped := FDrPrepDone and (FPaintList <> nil) and FPaintListValid and not FExporting;
  FDrPrepDone := False;
  { BUILD, THEN DRAW. The list stays afterwards -- see FPaintList. A
    PROGRESS FRAME changed which elements are shown and nothing else: its
    list is drawn as it stands [Batch 119] }
  { [R2-I9] AN UPDATE'S LIST, built when the update ran and untouched since
    (anything that changes it drops the flag: a relayout, a dropped list, a
    state the patch did not take): drawn as it stands. A second build would
    be the same list -- its sync no re-render (FStRerender), its proxies the
    same (FStProxied) -- so where the latter would differ it is built. }
  fresh := FListFresh and not GListFreshOff and not prepped and FPaintListValid
    and (FPaintList <> nil) and not FExporting and not FProgReuse
    and (FStProxied = (AnimAllowed or ((FAnimSet <> nil) and (FAnimSet.Count > 0)
      and not FAnimPending)));
  FListFresh := False;
  if fresh then
  begin
    FStRerender := False;
    Inc(GListFreshes);
  end;
  built := not prepped and not fresh and not (FProgReuse and FPaintListValid
    and (FPaintList <> nil) and not FExporting);
  FProgReuse := False;
  if built then drawn := BuildSeriesList(AMeasurer, APPI)
  else drawn := FPaintList.Count;
  FSerDrawn := drawn;
  { AN EXPORT DRAWS THE LIST AS LAID OUT: the finished chart, nothing armed,
    bound or stepped -- the proxies are the window's [Batch 106] }
  if FExporting then Exit;
  if built or fresh then AnimAfterBuild;
  { the states on their proxies, then the armed option's flush [Batch 94] }
  if not prepped then
  begin
    StAnimSync;
    AnimFlushArmed;
  end;
end;

procedure TTyCustomAdvanceChart.RenderSeries(APainter: TTyPainter;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
var
  drawn, i: Integer;
  layered: Boolean;
  frame: TTyPaintList;
begin
  drawn := FSerDrawn;
  if FExporting then
  begin
    FZList := FPaintList;
    if drawn > 0 then TyRenderPaintList(APainter, FPaintList);
    Exit;
  end;
  { IN MOTION, THE SERIES ARE THE DYNAMIC LAYER'S: a static layer holding
    them would freeze the first frame under every later one (Q7). }
  { ONLY LOOPS LEFT: everything but the ripples and their symbols stays
    here [Batch 92] }
  if FAnimContinuous then
  begin
    FZList := AnimPart(False);
    if (drawn > 0) and (FDrMode = 0) then TyRenderPaintList(APainter, FZList);
    Exit;
  end;
  if FAnimLive then Exit;
  if drawn > 0 then
  begin
    { AT REST, a proxy may still hold a value a unit in the last place off
      the layout -- the frame draws where upstream's element rests }
    if (Length(FAnimBind) > 0) or (Length(FAnimStBind) > 0) or TmAnimAny then
    begin
      frame := AnimFrame;
      FZList := frame;
      if FDrMode = 0 then TyRenderPaintList(APainter, frame);
      FDrStaticList := frame;
    end
    else
    begin
      { a progressive run's chunks through their own layer [Batch 119] }
      FZList := FPaintList;
      if FDrMode = 0 then ProgRenderList(APainter, FPaintList, APPI);
      { ...which is not one list the rects could be drawn from }
      layered := False;
      for i := 0 to FPaintList.Count - 1 do
        if ProgIsLayered(FPaintList.Ref(i)^) then
        begin
          layered := True;
          Break;
        end;
      if not layered then FDrStaticList := FPaintList;
    end;
  end
  else
    FDrStaticList := FPaintList;
end;

{ THE ROOT textStyle OVER A THEME FONT: always its font, and its colour where
  the text stands free rather than on a mark [Batch 83] }
procedure TTyCustomAdvanceChart.GlobalInk(var AName: string; var ASize,
  AWeight: Integer; var AColour: TTyChartColor; APick: TTyTextPick);
var
  has: Boolean;
  col: Cardinal;
begin
  has := False;
  col := 0;
  GlobalTextOver(AName, ASize, AWeight, has, col, APick);
  if has then AColour := TTyChartColor(col);
end;

{ [R5-G] GridView.render: when the grid model's `show` is truthy, one silent
  Rect over coordinateSystem.getRect() at z2 -1, its style
  defaults({fill: backgroundColor}, getItemStyle()) -- so the fill is the
  backgroundColor (default transparent), the stroke borderColor (default
  tokens.color.neutral30: the skin's TyAdvChartGridBorder), the lineWidth
  borderWidth (default 1), the dash, the opacity and the shadow the grid's
  own item-style keys. [Was: not drawn -- an option without effect.] }
procedure TTyCustomAdvanceChart.AddGridBackgrounds(AList: TTyPaintList);
var
  g: Integer;
  gb: TTyGridBuild;
  d: TJSONData;
  node: TJSONObject;
  st: TTyOptStyle;
  fill: TTyOptColor;
  el: TTyChartElement;
  r: TTyXYWH;
  lw, v: Double;
  bs: TTyStyleSet;
begin
  if (FBuild = nil) or (FOption = nil) or ViewHidden(cvGrid) then Exit;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    d := FOption.ComponentAt('grid', gb.ComponentIndex);
    if not (d is TJSONObject) then Continue;
    node := TJSONObject(d);
    if not TyJsTruthy(node.Find('show')) then Continue;
    st := TyReadOptItemStyleOf(node);
    fill := TyReadOptColorOf(node, 'backgroundColor');
    r := gb.PlotXYWH;
    el := TyChartElement(TyShapeRect(TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H)));
    el.Style.HasFill := fill.Written and not fill.IsNone and not fill.IsAuto
      and (((fill.Color shr 24) <> 0) or (fill.Gradient.Kind <> cgkNone)
        or fill.Pattern.Present);
    el.Style.FillColor := fill.Color;
    el.Style.FillGradient := fill.Gradient;
    el.Style.FillPattern := fill.Pattern;
    if not IsNan(st.BorderWidthLogical) then lw := st.BorderWidthLogical
    else lw := 1;
    if st.BorderColor.Written then
    begin
      if st.BorderColor.IsNone or st.BorderColor.IsAuto then lw := 0;
      el.Style.StrokeColor := st.BorderColor.Color;
      el.Style.StrokeGradient := st.BorderColor.Gradient;
    end
    else
    begin
      bs := ActiveController.Model.ResolveStyle('TyAdvChartGridBorder', '', []);
      el.Style.StrokeColor := TTyChartColor(bs.BorderColor);
    end;
    if (lw > 0) and not IsInfinite(lw) then el.Style.StrokeWidthLogical := lw
    else el.Style.StrokeWidthLogical := 0;
    el.Style.DashLogical := TyDashPattern(st.Dash, st.DashLogical, lw);
    el.Style.DashOffsetLogical := st.DashOffset;
    d := node.Find('borderCap');
    if (d <> nil) and (d.JSONType = jtString) then el.Style.LineCap := TyCapOfWord(d.AsString);
    d := node.Find('borderJoin');
    if (d <> nil) and (d.JSONType = jtString) then el.Style.LineJoin := TyJoinOfWord(d.AsString);
    d := node.Find('borderMiterLimit');
    if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat > 0) then
      el.Style.MiterLimit := d.AsFloat;
    { [R7-V] as written (the canvas clamps it) }
    if not IsNan(st.Opacity) then el.Style.Alpha := st.Opacity
    else el.Style.Alpha := 1;
    TyStyleSetShadow(el.Style, st.Shadow);
    { the grid's z (0) and zlevel (its own, else the root's) }
    el.Z := 0;
    d := node.Find('z');
    if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat) then
      el.Z := Round(Max(Double(-100000), Min(Double(100000), d.AsFloat)));
    el.Z2 := -1;
    d := node.Find('zlevel');
    if ((d = nil) or (d.JSONType <> jtNumber)) and (FOption.Root is TJSONObject) then
      d := TJSONObject(FOption.Root).Find('zlevel');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      v := d.AsFloat;
      if not IsNan(v) and not IsInfinite(v) then
        el.ZLevel := Round(Max(Double(-100000), Min(Double(100000), v)));
    end;
    el.Silent := True;
    AList.Add(el);
    ViewDrew(cvGrid);
  end;
end;

{ backgroundColor as the option writes it, when it is a colour that paints:
  not 'transparent', not 'none', not unreadable, not fully clear }
function TTyCustomAdvanceChart.AuthorBackground(out AColour: TTyChartColor): Boolean;
var d: TJSONData;
begin
  Result := False;
  AColour := 0;
  if FOption = nil then Exit;
  d := FOption.Find('backgroundColor');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  if not TyTryParseChartColor(d.AsString, AColour) then Exit;
  Result := (AColour shr 24) > 0;
end;

procedure TTyCustomAdvanceChart.PaintDynamic(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  ptrHits: TTyAxisHitArray;
  frame: TTyPaintList;
begin
  { AN EXPORT'S: the finished picture has no frame of an animation and no
    hover -- an option's own pointers, and the loading effect over all
    [Batch 106] }
  if FExporting then
  begin
    { [R5-D] THE STORAGE AS IT STANDS: the axis pointers and the emphasis a
      pointer put on the marks are zrender elements, so getDataURL draws
      them; the box (html) and the keyboard's ring (the port's) it does
      not. At another size or PPI the export is laid out anew and the
      pointer's state is not carried into it.
      [Was: the option's own pointers only, no emphasis.] }
    if FExportSameView and (Length(FTipHits) > 0) then
    begin
      PaintAxisPointers(APainter, ARect, APPI, AMeasurer,
        Concat(FTipHits, HdExtraHits(FTipHits)));
      PaintEmphasis(APainter, APPI, FTipHits);
    end
    else
    begin
      ptrHits := OptionPointerHits;
      PaintAxisPointers(APainter, ARect, APPI, AMeasurer,
        Concat(ptrHits, HdExtraHits(ptrHits)));
      if FExportSameView then PaintEmphasis(APainter, APPI, nil);
    end;
    { [R5-D] the handles, zr elements too }
    PaintHandles(APainter);
    { [R2-I9] getRenderedCanvas draws every built-in layer, the hover
      layer too }
    PaintHoverLayer(APainter);
    PaintLoading(APainter, ARect, APPI, AMeasurer);
    PaintOverLoading(APainter);
    Exit;
  end;
  { WHAT IS DRAWN HERE IS COMPOSITED OVER the blitted static layer: BeginPaint
    fills its bitmap transparent and EndPaint blends it (TBGRABitmap.Draw with
    AOpaque = False), so an overlay painter adds ink without erasing what is
    underneath. That is what makes two painters onto one canvas correct.

    ANYTHING ADDED HERE MUST BE VISIBLE TO HasDynamicContent, or RenderCached
    skips the whole pass and the new thing is written, compiled and never
    drawn. That is the failure this body's empty version was left here to
    prevent, and the tooltip is the first thing to test it. }
  { THE SERIES IN MOTION, and the title over them: this frame's values,
    read from the proxies [Batch 89] }
  if FAnimContinuous then
  begin
    { [R5-I] the part over the first ripple, then what the static layer
      draws over the series: the title (z 6) over the ripples (z 2) as the
      one display list has it [was: the ripples over the title, the break
      areas and the parallel axes] }
    frame := AnimFrame;
    FZList := frame;
    TySetZBand(-MaxInt, ComponentZLevel);
    try
      { [R7-AB] a trail on a zlevel above the components' is that level's
        layer (PaintTrailAbove) [was: drawn there with no trail at all] }
      if TrailZLevel(frame) > ComponentZLevel then
        TyRenderPaintList(APainter, AnimPartOf(frame, True))
      else
        PaintTrail(APainter, AnimPartOf(frame, True));
    finally
      TyClearZBand;
    end;
    PaintBreakAreas(APainter);
    PaintParallels(APainter, APPI, AMeasurer);
    PaintTitles(APainter);
    if TrailZLevel(frame) > ComponentZLevel then PaintTrailAbove(APainter, frame)
    else PaintAboveComponents(APainter, frame);
  end
  else if FAnimLive then
  begin
    { the trail is the continuous phase's: an enter or an update in motion
      draws every series as it stands [Batch 121] }
    FreeAndNil(FTrailLayer);
    frame := AnimFrame;
    FZList := frame;
    { [R5-J] the levels in order, the axes with them }
    if FZMixed then
      PaintZLevels(APainter, APPI, AMeasurer, FZLevels, True, frame)
    else
    begin
    { the axes in their groupTransition under the series, as the static
      layer draws them [Batch 96] }
    { [R7-AD] and the list's elements among their parts, the frame's }
    if AxesDynamic then PaintAxes(APainter, APPI, AMeasurer, True, frame);
    TySetZBand(-MaxInt, ZBase);
    try
      TyRenderPaintList(APainter, frame);
    finally
      TyClearZBand;
    end;
    { the break areas over the series in motion [F4a] }
    PaintBreakAreas(APainter);
    { the parallel axes over the lines in motion [Batch 128] }
    PaintParallels(APainter, APPI, AMeasurer);
    PaintTitles(APainter);
    { [R5-G] a higher zlevel over them }
    PaintAboveComponents(APainter, frame);
    end;
  end;
  { THE POINTER UNDER THE HIGHLIGHT UNDER THE BOX. A shadow band drawn over
    the bars is the layer debt showing -- series marks live in the static
    layer, so the band cannot go beneath them -- and re-drawing the hovered
    marks on top of the band is what hides it. }
  { and before any pointer event, the ones the option shows itself
    [Batch 100] }
  { [R5-D] and the pointers a handle keeps shown, then the handles }
  if Length(FTipHits) > 0 then ptrHits := FTipHits
  else ptrHits := OptionPointerHits;
  PaintAxisPointers(APainter, ARect, APPI, AMeasurer,
    Concat(ptrHits, HdExtraHits(ptrHits)));
  PaintHandles(APainter);
  PaintEmphasis(APainter, APPI, FTipHits);
  { [R2-I9] THE HOVER LAYER over every layer of the canvas (zlevel 1e5):
    the paths on it in their hover style -- the box, HTML upstream, over it }
  PaintHoverLayer(APainter);
  { THE KEYBOARD'S RING over the marks and under the box [Batch 144] }
  PaintKbRing(APainter);
  { THE POINTER FIRST, THE BOX OVER IT. A tooltip with the pointer's own line
    drawn across it would read as two things at one depth. }
  { THE LOADING EFFECT OVER THE CHART: upstream's mask is z 10000
    [Batch 106] -- [R5-D] under the box, which is html over the canvas
    there [was: over the box too] }
  PaintLoading(APainter, ARect, APPI, AMeasurer);
  { [R5-G] AN ELEMENT OF A HIGHER ZLEVEL THAN THE MASK'S is a canvas over it:
    the static layer left it out (ZStaticTop), drawn here over the mask }
  PaintOverLoading(APainter);
  PaintTooltip(APainter, ARect, APPI, AMeasurer);
end;

procedure TTyCustomAdvanceChart.PaintOverLoading(APainter: TTyPainter);
var zTop: Integer;
begin
  zTop := ZStaticTop;
  if (zTop = MaxInt) or (FZList = nil) then Exit;
  if TyMaxZLevelOf(FZList) <= zTop then Exit;
  TySetZBand(zTop, MaxInt);
  try
    TyRenderPaintList(APainter, FZList);
  finally
    TyClearZBand;
  end;
end;

function TTyCustomAdvanceChart.HasDynamicContent: Boolean;
begin
  { A REAL QUESTION NOW: is anything hovered. A second painter means allocating
    a BGRA bitmap the size of the control, filling it, blending it and freeing
    it -- roughly the 13 ms floor a frame has even with no axes -- so the
    answer has to be cheap and it has to be exact. It is deliberately not
    "would the tooltip draw": resolving the option cascade and the theme to
    find out costs more than the pass it would save. }
  Result := TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0)
    or FAnimLive or FTipShown or FLoadShown
    or (Length(OptionPointerHits) > 0)
    { the keyboard's ring [Batch 144] }
    or FKbActive
    { a component's part [F5] }
    or FKbStopOn
    { [R2-I9] the hover layer's copies }
    or StHoverAny
    { [R5-D] an axis pointer's handle }
    or (Length(FHandles) > 0) or HdConfigured;
end;

procedure TTyCustomAdvanceChart.DropStatic;
begin
  StaticDrop;
  FProgReuse := False;
  { AND THE LIST WITH IT. The two describe the same frame: the list is what
    the static pass added up to, so a kept list beside a dropped cache would
    answer questions about a picture no longer on screen. Not freed -- the
    next build reuses the object and only the answer is stale. }
  FPaintListValid := False;
  FListFresh := False;
  { [R2-I9] the hover layer's copies are of that list }
  FHoverDirty := True;
end;

procedure TTyCustomAdvanceChart.DropStaticKeepList;
var had: Boolean;
begin
  had := (FPaintList <> nil) and FPaintListValid;
  DropStatic;
  if had and (FLastPPI > 0) and not FExporting then
  begin
    BuildSeriesList(NewTextMeasurer(FLastPPI), FLastPPI);
    StaticDrop;
    { [R2-I9] the paint draws this one }
    FListFresh := True;
  end;
end;

procedure TTyCustomAdvanceChart.PointerStateChanged;
begin
  { [F4b] the base class' pointer bookkeeping: a repaint, nothing marked }
  InvalidateFrameQuiet;
end;

procedure TTyCustomAdvanceChart.RenderCached(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
var
  P: TTyPainter;
  R: TRect;
  w, h: Integer;
  measurer: ITyTextMeasurer;
  sc: TTyCanvasScale;
begin
  { [F4b] the flush's start, for `rendered`'s elapsedTime }
  FPaintT0 := AnimClock;
  { THE DIRTY-RECT PATH [Batch 142]: the canvas holds the last frame, and
    only what changed is drawn on it }
  { the layers at the device scale of the canvas they go onto (#83) }
  sc := TyCanvasDeviceScale(ACanvas);
  if FUseDirtyRect then
  begin
    DrPrepare(ARect, APPI, sc);
    DrComposite(ACanvas, ARect);
    Exit;
  end;
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;
  R := Rect(0, 0, w, h);

  if FStatic = nil then FStatic := TTyPaintCache.Create;
  { PPI IS PART OF THE KEY and TTyPaintCache does not know it: NeedsRender only
    notices a size change, and a per-monitor DPI move can hand back the same
    size at a different PPI -- a chart drawn for 96 blitted onto a 192 window. }
  if APPI <> FStaticPPI then
  begin
    FStatic.Drop;
    FProgFastFrame := False;
    FStaticPPI := APPI;
  end;
  { upstream's frame: the flags become state lists, and a changed element
    is a changed static layer [Batch 88] }
  if StApplyChanged then
  begin
    FStatic.Drop;
    FProgFastFrame := False;
    { the states restyle the list: it is built again [Batch 119] -- or,
      where only they changed, patched where it stands [P2] }
    FProgReuse := StPatchList;
  end;

  { AND THE DEVICE SCALE: the cache holds S times the pixels and its canvas
    is a raster canvas a painter draws on at S; a change of S is a change of
    size, so it renders again (#83) }
  if FStatic.NeedsRender(w, h, sc) and not ProgFastPaint(R, APPI, sc) then
  begin
    measurer := NewTextMeasurer(APPI);
    P := NewPainter;
    try
      P.BeginPaint(FStatic.Canvas, R, APPI);
      { [R2-L] the bitmap kept for the progress frames to come, where a run
        is blitted in it and the paint blends it as it stands }
      FProgCapOk := False;
      FProgCapUnder := False;
      FProgCap := not GProgFastOff;
      try
        PaintStatic(P, R, APPI, measurer);
      finally
        FProgCap := False;
      end;
      if FProgCapUnder and (P.Bitmap <> nil) and (P.Opacity = 1.0) then
      begin
        if FProgWork = nil then FProgWork := TBGRABitmap.Create(P.Bitmap.Width, P.Bitmap.Height)
        else FProgWork.SetSize(P.Bitmap.Width, P.Bitmap.Height);
        FProgWork.PutImage(0, 0, P.Bitmap, dmSet);
        FProgCapW := w;
        FProgCapH := h;
        FProgCapPPI := APPI;
        FProgCapScale := P.DeviceScale;
        FProgCapOk := True;
      end;
      FProgFastFrame := False;
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  FStatic.Blit(ACanvas);

  { A SECOND PAINTER ONLY WHEN THERE IS SOMETHING TO PUT IN IT. Creating one
    means allocating a BGRA bitmap the size of the control, filling it,
    blending it and freeing it -- roughly the 13 ms floor a frame has even with
    no axes, so paying it to draw nothing would give back most of what the
    cache just saved. }
  if HasDynamicContent then
  begin
    measurer := NewTextMeasurer(APPI);
    P := NewPainter;
    try
      P.BeginPaint(ACanvas, ARect, APPI);
      PaintDynamic(P, R, APPI, measurer);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  { the update painted: `rendered` [Batch 119] }
  EmitFlush;
  { the bar race, as RenderTo's [Batch 135] }
  if FRtAfterRelayout then
  begin
    FRtAfterRelayout := False;
    RtRenderPass;
    RtRendered;
  end;
  RtFlushQueue;
end;

{ [R2-J2] the scope's URL resolver: OnResolveImage, asked once a URL }
function TTyCustomAdvanceChart.ResolveImageUrl(const AUrl: string): TBGRABitmap;
var i: Integer;
begin
  Result := nil;
  if FResolvedImages <> nil then
  begin
    i := FResolvedImages.IndexOf(AUrl);
    if i >= 0 then Exit(TBGRABitmap(FResolvedImages.Objects[i]));
  end;
  if not Assigned(FOnResolveImage) then Exit;
  if FResolvedImages = nil then
  begin
    FResolvedImages := TStringList.Create;
    FResolvedImages.OwnsObjects := True;
    FResolvedImages.UseLocale := False;
    FResolvedImages.CaseSensitive := True;
    FResolvedImages.Sorted := True;
    FResolvedImages.Duplicates := dupIgnore;
  end;
  FOnResolveImage(Self, AUrl, Result);
  FResolvedImages.AddObject(AUrl, Result);
end;

procedure TTyCustomAdvanceChart.ForgetResolvedImages;
begin
  FreeAndNil(FResolvedImages);
  Invalidate;
end;

procedure TTyCustomAdvanceChart.Paint;
var prev: TComponent; prevRes: TTyChartImageUrlResolver;
begin
  prev := TyChartImageScopeEnter(Owner);
  prevRes := TyChartImageResolverEnter(@ResolveImageUrl);
  try
    PaintBody;
  finally
    TyChartImageResolverLeave(prevRes);
    TyChartImageScopeLeave(prev);
  end;
end;

procedure TTyCustomAdvanceChart.PaintBody;
begin
  { a paint is a frame: the toolbox's hover states land [Batch 125] -- a
    dirty-rect window's frame is its flush, and a paint that only
    composites is not one [Batch 142] }
  if not (csDesigning in ComponentState) and not FUseDirtyRect then TbFrame;
  { THE DESIGNER RENDERS STRAIGHT THROUGH, as TTyPanel's does: it repaints
    rarely and streams while it does, so a cache buys nothing there and is one
    more thing that can be holding a frame from before the last property
    change. }
  if csDesigning in ComponentState then
  begin
    RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  { A WINDOW'S PAINT: the one render camAuto animates [Batch 89] }
  FAnimWindow := True;
  try
    { the dirty-rect window: the clip composited [Batch 142] }
    if FUseDirtyRect then DrPaintWindow
    else RenderCached(Canvas, ClientRect, Font.PixelsPerInch);
  finally
    FAnimWindow := False;
  end;
  { THE ACCESSIBLE TREE follows a new layout -- only while somebody reads it:
    a client has asked for it, or the keyboard is in the chart [Batch 144] }
  if (FAccGen <> FStGen) and ((FAccLink <> nil) and FAccLink.InUse or Focused) then
    AccessibleSync;
end;

{ ==================== the coarse pointer and the dirty rectangles [Batch 142] ====================

  THE COARSE POINTER is a fallback of the display list's hit test: the
  direct test first -- without the port's pad, so it answers what
  upstream's Path.contain answers -- and only when it finds nothing,
  zrender's rings of samples over the candidates near the pointer
  (AdvanceChart.DirtyRect). What the port hit-tests apart from the list (the
  brush covers, break areas, titles, the toolbox, the timeline, the
  visualMaps, the dataZoom handles) stays direct: in upstream they are
  display-list elements and candidates like any other.

  THE DIRTY RECTANGLES keep both layers and make each cheaper, never
  different: what the dirty path puts on the canvas is, pixel for pixel,
  what the full path puts there.

  - THE STATIC LAYER, when only states changed (a hover's emphasis, a
    selection: StApplyChanged): the list is built and prepared exactly as a
    full static paint builds it, but not drawn; it is compared element by
    element with the list the cache holds (FDrSnap) and createRepaintRects
    makes the rects. Each rect starts from the ground captured before the
    series (FDrBase), the elements whose rects meet one are drawn in paint
    order, then what the static paint draws after the series (break areas,
    parallel axes, titles) -- on the static painter's own surface, which is
    then copied into the cache in those rects only. Anything else that
    drops the static layer -- a relayout, a roam step, a legend selector's
    hover, an animation leaving the static layer -- repaints it whole, and
    so does a change the rects cannot hold (see TyDirtyDiff).
  - THE DYNAMIC LAYER is kept from frame to frame and transparent outside
    the tiles it inked last (FDrDynTiles): those are cleared, the layer is
    painted as always, and its ink is found again. Its old and new tiles
    join the static rects in createRepaintRects' pool, so a frame of a
    moving tooltip costs the tooltip's area, not the control's -- the
    control-sized bitmap the full path allocates, fills and blends every
    frame (Q7's floor) is gone.
  - THE WINDOW: InvalidateFrame queues one flush (QueueAsyncCall); the
    flush prepares the frame and invalidates its rects only, and the paint
    composites the clip it was given. A paint nobody flushed for (an
    Invalidate, a window uncovered) prepares the frame itself. }

procedure TTyCustomAdvanceChart.StaticDrop;
begin
  if FStatic <> nil then FStatic.Drop;
  { not a progress frame's own drop (ProgFrame says so after it) [R2-L] }
  FProgFastFrame := False;
  { the cache no longer holds what the snapshot says [Batch 142] }
  FDrSnapOk := False;
end;

procedure TTyCustomAdvanceChart.SetUseDirtyRect(AValue: Boolean);
begin
  if FUseDirtyRect = AValue then Exit;
  FUseDirtyRect := AValue;
  StaticDrop;
  FDrDynTiles := nil;
  FreeAndNil(FDrDyn);
  FDrPending := True;
  FZrDirty := True;
  inherited Invalidate;
end;

procedure TTyCustomAdvanceChart.SetExactRendering(AValue: Boolean);
begin
  if FExactRendering = AValue then Exit;
  FExactRendering := AValue;
  { everything drawn the other way: the static cache, the progressive
    layer and its fast frames, the dynamic layer }
  StaticDrop;
  FProgLayerOk := False;
  ProgFastDrop;
  FDrDynTiles := nil;
  FreeAndNil(FDrDyn);
  FDrPending := True;
  FZrDirty := True;
  inherited Invalidate;
end;

function TTyCustomAdvanceChart.NewPainter: TTyPainter;
begin
  Result := TTyPainter.Create;
  Result.FastStrokes := not FExactRendering;
end;

function TTyCustomAdvanceChart.CoarseSize: Integer;
begin
  Result := TyCoarsePointerSize(FCoarsePointer, FPointerSize, TyTouchPlatform);
end;

function TTyCustomAdvanceChart.ListHitAt(AX, AY: Double): Integer;
var
  L: TTyPaintList;
  sz, lo, hi: Integer;
begin
  Result := -1;
  if (FPaintList = nil) or not FPaintListValid then Exit;
  { [R5-D] the loading mask over it all -- [R5-J] over what stands on its
    zlevel or under it: an element of a higher one is over the mask; and on
    the canvas searched now }
  lo := -MaxInt;
  hi := MaxInt;
  if FHitBandOn then
  begin
    lo := FHitLo;
    hi := FHitHi;
  end;
  if LoadMasks then lo := Max(lo, MaskZLevel);
  if lo >= hi then Exit;
  { IN MOTION, WHAT IS DRAWN IS WHAT IS HIT, and at rest on a state proxy
    (see HitTestAt) }
  if FAnimLive or (Length(FAnimStBind) > 0) then L := AnimFrame else L := FPaintList;
  sz := CoarseSize;
  if (lo > -MaxInt) or (hi < MaxInt) then TySetHitBand(lo, hi);
  try
    if sz <= 0 then Result := L.HitTestElement(AX, AY, FPaintListPPI)
    else
    begin
      Result := L.HitTestElement(AX, AY, FPaintListPPI, False);
      if Result < 0 then Result := TyCoarseHitTest(L, AX, AY, FPaintListPPI, sz);
    end;
  finally
    TyClearHitBand;
  end;
  { [R6-C] a combining host's child past the list: the host is the one hit
    (its ecData, the child's parent's) }
  if (Result >= 0) and (Result < L.Count) and (L.Element(Result).Anim.PieceOf > 0) then
    Result := L.Element(Result).Anim.PieceOf - 1;
end;

function TTyCustomAdvanceChart.LastRepaintFull: Boolean;
begin
  Result := FDrLastFull;
end;

function TTyCustomAdvanceChart.LastRepaintRects: TTyZrRectArray;
begin
  Result := Copy(FDrLastRects);
end;

procedure TTyCustomAdvanceChart.DrCaptureBase(ABmp: TBGRABitmap);
begin
  if ABmp = nil then Exit;
  if (FDrBase = nil) or (FDrBase.Width <> ABmp.Width) or (FDrBase.Height <> ABmp.Height) then
  begin
    FreeAndNil(FDrBase);
    FDrBase := TBGRABitmap.Create(ABmp.Width, ABmp.Height);
  end;
  FDrBase.PutImage(0, 0, ABmp, dmSet);
  FDrBaseOk := True;
end;

function TTyCustomAdvanceChart.DrCanPartial(AW, AH: Integer): Boolean;
begin
  { the cache holds the snapshot's list over the captured ground, at this
    size, with nothing to lay out again and the series at rest in it }
  Result := FDrSnapOk and FDrBaseOk and (FDrWork <> nil) and (FDrBase <> nil)
    and (FDrWork.Width = AW * FDrScale) and (FDrWork.Height = AH * FDrScale)
    and (FDrBase.Width = AW * FDrScale) and (FDrBase.Height = AH * FDrScale)
    and not FDirty and (FLastRect.Right = AW) and (FLastRect.Bottom = AH)
    and not FExporting and not FAnimLive and not FAnimContinuous;
end;

procedure TTyCustomAdvanceChart.DrStaticFull(const R: TRect; APPI: Integer);
var
  P: TTyPainter;
  measurer: ITyTextMeasurer;
begin
  { the static painter's surface at the frame's device scale: the cache's
    raster canvas is drawn on at that scale (#83) }
  if (FDrWork = nil) or (FDrWork.Width <> R.Right * FDrScale)
    or (FDrWork.Height <> R.Bottom * FDrScale) then
  begin
    FreeAndNil(FDrWork);
    FDrWork := TBGRABitmap.Create(R.Right * FDrScale, R.Bottom * FDrScale);
  end;
  { what BeginPaint's own bitmap starts as }
  FDrWork.Fill(BGRAPixelTransparent);
  FDrBaseOk := False;
  FDrSnapOk := False;
  FDrSnap := nil;
  measurer := NewTextMeasurer(APPI);
  P := NewPainter;
  try
    P.BeginPaintOn(FStatic.Canvas, R, APPI, FDrWork);
    FDrCapture := True;
    try
      PaintStatic(P, R, APPI, measurer);
    finally
      FDrCapture := False;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
  if FDrBaseOk and (FDrStaticList <> nil) then
  begin
    FDrSnap := TyDirtySnapshot(FDrStaticList, APPI);
    FDrSnapOk := True;
  end;
end;

function TTyCustomAdvanceChart.DrStaticPartial(const R: TRect; APPI: Integer;
  var APool: TTyRepaintPool): Boolean;
var
  measurer: ITyTextMeasurer;
  snap: TTyDirtySnap;
  rects, zr: TTyZrRectArray;
  px: array of TRect;
  pr, oldClip, rp: TRect;
  box: TTyXYWH;
  i, k, n, idx: Integer;
  hit: Boolean;
  P: TTyPainter;
  sc: TTyCanvasScale;
  zc, pass: Integer;
  { [R5-J] }
  lvs: TTyIntegerArray;
  { [R7-W] }
  carries: Boolean;
  blk, b0, b1: Integer;
  run: TTyCanvasRun;
  ground: TTyCanvasGround;
  el: TTyChartElement;
begin
  Result := False;
  measurer := NewTextMeasurer(APPI);
  { THE LIST AS A FULL STATIC PAINT WOULD BUILD AND PREPARE IT -- the
    graphic component's elements, the states, the proxies -- and not drawn }
  GfxBuild(APPI);
  FDrMode := 1;
  try
    PaintSeries(nil, measurer, APPI);
  finally
    FDrMode := 0;
  end;
  { from here a fallback must not build it again }
  FDrPrepDone := True;
  { a state's transition took the series into the dynamic layer, or the
    static layer would not hold one list: everything -- [R5-J] and the
    levels drawn canvas by canvas: the ground is no one canvas }
  if FAnimLive or FAnimContinuous or (FDrStaticList = nil) then Exit;
  if ZMixedNow(lvs) then Exit;
  snap := TyDirtySnapshot(FDrStaticList, APPI);
  if not TyDirtyDiff(FDrSnap, snap, rects) then Exit;
  FDrPrepDone := False;
  FDrSnap := snap;
  Result := True;
  n := 0;
  SetLength(px, Length(rects));
  SetLength(zr, Length(rects));
  for i := 0 to High(rects) do
    if TyZrRectToPixels(rects[i], R.Right, R.Bottom, pr) then
    begin
      px[n] := pr;
      zr[n] := rects[i];
      Inc(n);
    end;
  if n = 0 then Exit;
  { EACH RECT FROM THE GROUND, then what meets it in paint order -- the
    layers' pixels are FDrScale times the rects' (#83) }
  for i := 0 to n - 1 do
  begin
    rp := DrRaster(px[i]);
    FDrWork.PutImagePart(rp.Left, rp.Top, FDrBase, rp, dmSet);
    box.X := px[i].Left;
    box.Y := px[i].Top;
    box.W := px[i].Right - px[i].Left;
    box.H := px[i].Bottom - px[i].Top;
    TyRepaintPoolAdd(APool, box);
  end;
  P := NewPainter;
  oldClip := FDrWork.ClipRect;
  try
    sc.Scale := FDrScale;
    sc.DeviceUnits := False;
    P.BeginPaintOnScaled(nil, R, APPI, FDrWork, sc);
    { ONE PASS UNDER THE RECTS' BOUNDS: the bitmap's clip is the box round
      every rect, and an element is drawn once when it meets any of them.
      zrender clips and draws rect by rect; drawn that way here an element
      crossing several rects -- a line's polyline across the plot -- is
      stroked once per rect, and stroking a long polyline costs the same
      however small the clip. What lands outside the rects is never copied
      out.
      [R7-W] EXCEPT WHERE THE CANVAS CARRIES A VALUE: each of zrender's
      blocks saves the context, starts its brushes afresh (prevEl null) and
      restores it, so an element whose colour, width, shadow or transform
      the canvas refuses takes what the element before it IN THAT BLOCK
      left -- rect by rect then, each block settled anew (TyCanvasRunStep
      on a copy) [was: the whole list's order everywhere] }
    carries := False;
    for i := 0 to High(snap) do
      if TyCanvasElementCarries(snap[i].El) then
      begin
        carries := True;
        Break;
      end;
    if carries then
    begin
      b0 := 0;
      b1 := n - 1;
    end
    else
    begin
      b0 := -1;
      b1 := -1;
    end;
    for blk := b0 to b1 do
    begin
    if blk < 0 then
    begin
      box := TyRectToXYWH(TyRectF(px[0].Left, px[0].Top, px[0].Right, px[0].Bottom));
      for k := 1 to n - 1 do
        TyZrRectUnion(box, TyRectToXYWH(TyRectF(px[k].Left, px[k].Top, px[k].Right, px[k].Bottom)));
    end
    else
    begin
      box := TyRectToXYWH(TyRectF(px[blk].Left, px[blk].Top, px[blk].Right, px[blk].Bottom));
      { [R7-AB] from the canvas' own state through the components that meet
        the block [was: what every component left] }
      ground := CanvasGroundIn(zr[blk], APPI);
      TyCanvasRunStart(run, ground, APPI);
    end;
    FDrWork.ClipRect := DrRaster(Rect(Round(box.X), Round(box.Y), Round(box.X + box.W),
      Round(box.Y + box.H)));
    { [R5-G] in two passes as the full paint draws: the list up to the
      components' zlevel, the components, the rest over them }
    zc := ZBase;
    for pass := 0 to 1 do
    begin
      if pass = 0 then
        TySetZBand(-MaxInt, zc)
      else
      begin
        { what the static paint draws over the series, as it draws it }
        PaintBreakAreas(P);
        PaintParallels(P, APPI, measurer);
        PaintTitles(P);
        if TyMaxZLevelOf(FDrStaticList) <= zc then Break;
        TySetZBand(zc, ZStaticTop);
      end;
      try
        for i := 0 to FDrStaticList.Count - 1 do
        begin
          idx := FDrStaticList.PaintOrder(i);
          if (idx < 0) or (idx > High(snap)) then Continue;
          { TyRenderPaintList's own skips }
          if snap[idx].El.Ignore or snap[idx].El.ProgHidden or snap[idx].El.GfxUnder then
            Continue;
          { an element nothing bounds is drawn wherever it is: unchanged, it may
            still be under a rect }
          if snap[idx].Bounded then
          begin
            hit := False;
            if blk >= 0 then hit := TyZrRectIntersect(snap[idx].Rect, zr[blk])
            else
              for k := 0 to n - 1 do
                if TyZrRectIntersect(snap[idx].Rect, zr[k]) then
                begin
                  hit := True;
                  Break;
                end;
            if not hit then Continue;
          end;
          if blk >= 0 then
          begin
            el := snap[idx].El;
            { (its pieces its own: the block settles them afresh) }
            SetLength(el.Caption.RtPieces, Length(el.Caption.RtPieces));
            TyCanvasRunStep(run, el);
            TyRenderElement(P, el);
          end
          else
            TyRenderElement(P, snap[idx].El);
        end;
      finally
        TyClearZBand;
      end;
    end;
    end;
    FDrWork.ClipRect := oldClip;
    P.EndPaint;
  finally
    FDrWork.ClipRect := oldClip;
    P.Free;
  end;
  { INTO THE CACHE, those rects only, blended as EndPaint blends -- the
    cache holds the layers' pixels }
  for i := 0 to n - 1 do
  begin
    rp := DrRaster(px[i]);
    FDrWork.DrawPart(rp, FStatic.Canvas, rp.Left, rp.Top, False);
  end;
end;

function TTyCustomAdvanceChart.DrRaster(const R: TRect): TRect;
var
  s: Integer;
begin
  s := Max(1, FDrScale);
  Result := Rect(R.Left * s, R.Top * s, R.Right * s, R.Bottom * s);
end;

procedure TTyCustomAdvanceChart.DrCopyStatic(ACanvas: TCanvas; const APx: TRect);
begin
  { the static layer at the canvas origin, as Blit puts it: its pixels from
    the cache, into the canvas's own units }
  ACanvas.CopyRect(TyCanvasRect(ACanvas, APx), FStatic.Canvas, DrRaster(APx));
end;

procedure TTyCustomAdvanceChart.DrDrawDynamic(ACanvas: TCanvas; const APx: TRect;
  ADstX, ADstY: Integer);
var
  src, dst: TRect;
  piece: TBGRACustomBitmap;
begin
  src := DrRaster(APx);
  dst := TyCanvasRect(ACanvas, Rect(ADstX, ADstY, ADstX + APx.Right - APx.Left,
    ADstY + APx.Bottom - APx.Top));
  if (dst.Right - dst.Left = src.Right - src.Left) and (dst.Bottom - dst.Top = src.Bottom - src.Top) then
    FDrDyn.DrawPart(src, ACanvas, dst.Left, dst.Top, False)
  else
  begin
    { a canvas in device px at a device scale (a Retina window): the layer's
      pixels into the device-px rect }
    piece := FDrDyn.GetPart(src);
    try
      piece.Draw(ACanvas, dst, False);
    finally
      piece.Free;
    end;
  end;
end;

const
  { the dynamic layer's ink is found in tiles this many px square }
  cDrInkTile = 32;

procedure TTyCustomAdvanceChart.DrDynamic(const R: TRect; APPI: Integer;
  var APool: TTyRepaintPool; var AFull: Boolean);
var
  i: Integer;
  pr: TRect;
  cur: TTyZrRectArray;
  P: TTyPainter;
  measurer: ITyTextMeasurer;
  sc: TTyCanvasScale;
begin
  { the layer at the frame's device scale; its tiles in device px (#83) }
  if (FDrDyn = nil) or (FDrDyn.Width <> R.Right * FDrScale)
    or (FDrDyn.Height <> R.Bottom * FDrScale) then
  begin
    FreeAndNil(FDrDyn);
    FDrDyn := TBGRABitmap.Create(R.Right * FDrScale, R.Bottom * FDrScale, BGRAPixelTransparent);
    FDrDynTiles := nil;
    FDrAnimSnapOk := False;
    AFull := True;
  end
  { [R7-Y] a frame in motion that carries a value the canvas refuses: the
    blocks round what moved only, as zrender repaints it }
  else if DrDynamicBlocks(R, APPI, APool) then
    Exit;
  { THE LAST INK GOES: the layer is transparent again everywhere }
  for i := 0 to High(FDrDynTiles) do
  begin
    if TyZrRectToPixels(FDrDynTiles[i], R.Right, R.Bottom, pr) then
      FDrDyn.FillRect(DrRaster(pr), BGRAPixelTransparent, dmSet);
    TyRepaintPoolAdd(APool, FDrDynTiles[i]);
  end;
  cur := nil;
  { A PAINTER ONLY WHEN THERE IS SOMETHING TO PUT IN IT -- as the full path }
  if HasDynamicContent then
  begin
    measurer := NewTextMeasurer(APPI);
    P := NewPainter;
    try
      sc.Scale := FDrScale;
      sc.DeviceUnits := False;
      P.BeginPaintOnScaled(nil, R, APPI, FDrDyn, sc);
      PaintDynamic(P, R, APPI, measurer);
      P.EndPaint;
    finally
      P.Free;
    end;
    { tiles of cDrInkTile device px: FDrScale times that on the layer, and
      back to device px -- exactly, the tiles start on multiples of it }
    TyInkTiles(FDrDyn, cDrInkTile * FDrScale, cur);
    for i := 0 to High(cur) do
    begin
      cur[i].X := cur[i].X / FDrScale;
      cur[i].Y := cur[i].Y / FDrScale;
      cur[i].W := cur[i].W / FDrScale;
      cur[i].H := cur[i].H / FDrScale;
      TyRepaintPoolAdd(APool, cur[i]);
    end;
  end;
  FDrDynTiles := cur;
  { [R7-Y] the frame the next one's blocks are found against: only while a
    continuous animation's frame carries a value the canvas refuses (the
    one case where a block's paint differs from the whole paint) }
  FDrAnimSnapOk := False;
  FDrAnimSnap := nil;
  if FAnimContinuous and not FExporting and (FZList <> nil)
    and TyLinesCanvasLeftoversDue(FZList) then
  begin
    FDrAnimSnap := TyDirtySnapshot(FZList, APPI);
    FDrAnimSnapOk := True;
  end;
end;

function TTyCustomAdvanceChart.DrDynamicBlocks(const R: TRect; APPI: Integer;
  var APool: TTyRepaintPool): Boolean;
var
  frame: TTyPaintList;
  snap: TTyDirtySnap;
  rects, zr, cur: TTyZrRectArray;
  px: array of TRect;
  pr, oldClip, rp: TRect;
  box: TTyXYWH;
  i, n, blk, idx: Integer;
  P: TTyPainter;
  sc: TTyCanvasScale;
  measurer: ITyTextMeasurer;
  run: TTyCanvasRun;
  ground: TTyCanvasGround;
  el: TTyChartElement;
  lvs: TTyIntegerArray;
begin
  Result := False;
  { A FRAME OF THE LOOPS ALONE, over a ground the static layer captured,
    and nothing else in the dynamic layer: zrender's useDirtyRect repaints
    the blocks round the elements that changed -- each block cleared,
    clipped, its brushes started afresh (prevEl null) from the canvas' own
    state, only the elements meeting it brushed -- and keeps every other
    pixel of the last frame. Where nothing carries a value the canvas
    refuses, a block's paint is the whole paint's (the port's full frame
    then); where something does, the element before it differs block by
    block: the blocks here, each settled anew (TyCanvasRunStep on a copy)
    over the ground, the static layer's elements meeting it among them, the
    layer opaque there so it stands for the whole picture [was: the frame
    drawn whole, the list's order everywhere] }
  if not FAnimContinuous or FExporting or not FDrAnimSnapOk then Exit;
  if (FDrDyn = nil) or (FDrBase = nil) or not FDrBaseOk
    or (FDrBase.Width <> FDrDyn.Width) or (FDrBase.Height <> FDrDyn.Height) then Exit;
  { what else the dynamic layer draws (HasDynamicContent's own terms) }
  if TyChartDatumValid(FTipDatum) or (Length(FTipHits) > 0) or FTipShown or FLoadShown
    or (Length(OptionPointerHits) > 0) or FKbActive or FKbStopOn or StHoverAny
    or (Length(FHandles) > 0) or HdConfigured then Exit;
  if ZMixedNow(lvs) then Exit;
  frame := AnimFrame;
  if (frame = nil) or not TyLinesCanvasLeftoversDue(frame) then Exit;
  if TyMaxZLevelOf(frame) > ComponentZLevel then Exit;
  { a trail is a layer of its own, faded whole every frame }
  for i := 0 to frame.Count - 1 do
    if (frame.Element(i).Datum.Kind = ctkSeries)
      and (LinesTrailAlpha(frame.Element(i).Datum.SeriesIndex) > 0) then Exit;
  snap := TyDirtySnapshot(frame, APPI);
  if not TyDirtyDiff(FDrAnimSnap, snap, rects) then Exit;
  Result := True;
  FZList := frame;
  FDrAnimSnap := snap;
  n := 0;
  SetLength(px, Length(rects));
  SetLength(zr, Length(rects));
  for i := 0 to High(rects) do
    if TyZrRectToPixels(rects[i], R.Right, R.Bottom, pr) then
    begin
      px[n] := pr;
      zr[n] := rects[i];
      Inc(n);
    end;
  { EACH BLOCK FROM THE GROUND: everything the static layer drew before the
    series, opaque, so the block stands for the whole canvas there }
  for i := 0 to n - 1 do
  begin
    rp := DrRaster(px[i]);
    FDrDyn.PutImagePart(rp.Left, rp.Top, FDrBase, rp, dmSet);
    box.X := px[i].Left;
    box.Y := px[i].Top;
    box.W := px[i].Right - px[i].Left;
    box.H := px[i].Bottom - px[i].Top;
    TyRepaintPoolAdd(APool, box);
  end;
  if n > 0 then
  begin
    measurer := NewTextMeasurer(APPI);
    P := NewPainter;
    oldClip := FDrDyn.ClipRect;
    try
      sc.Scale := FDrScale;
      sc.DeviceUnits := False;
      P.BeginPaintOnScaled(nil, R, APPI, FDrDyn, sc);
      for blk := 0 to n - 1 do
      begin
        FDrDyn.ClipRect := DrRaster(px[blk]);
        { [R7-AB] from the canvas' own state through the components that
          meet the block [was: what every component left] }
        ground := CanvasGroundIn(zr[blk], APPI);
        TyCanvasRunStart(run, ground, APPI);
        TySetZBand(-MaxInt, ComponentZLevel);
        try
          for i := 0 to frame.Count - 1 do
          begin
            idx := frame.PaintOrder(i);
            if (idx < 0) or (idx > High(snap)) then Continue;
            { TyRenderPaintList's own skips }
            if snap[idx].El.Ignore or snap[idx].El.ProgHidden or snap[idx].El.GfxUnder then
              Continue;
            { an element nothing bounds is drawn wherever it is }
            if snap[idx].Bounded and not TyZrRectIntersect(snap[idx].Rect, zr[blk]) then
              Continue;
            el := snap[idx].El;
            { (its pieces its own: the block settles them afresh) }
            SetLength(el.Caption.RtPieces, Length(el.Caption.RtPieces));
            TyCanvasRunStep(run, el);
            TyRenderElement(P, el);
          end;
        finally
          TyClearZBand;
        end;
        { what the dynamic layer draws over the loops, as it draws it }
        PaintBreakAreas(P);
        PaintParallels(P, APPI, measurer);
        PaintTitles(P);
      end;
      FDrDyn.ClipRect := oldClip;
      P.EndPaint;
    finally
      FDrDyn.ClipRect := oldClip;
      P.Free;
    end;
  end;
  { the layer's ink found again (the blocks are opaque) }
  cur := nil;
  TyInkTiles(FDrDyn, cDrInkTile * FDrScale, cur);
  for i := 0 to High(cur) do
  begin
    cur[i].X := cur[i].X / FDrScale;
    cur[i].Y := cur[i].Y / FDrScale;
    cur[i].W := cur[i].W / FDrScale;
    cur[i].H := cur[i].H / FDrScale;
  end;
  FDrDynTiles := cur;
end;

procedure TTyCustomAdvanceChart.DrPrepare(const ARect: TRect; APPI: Integer;
  const AScale: TTyCanvasScale);
var
  w, h: Integer;
  R: TRect;
  pool: TTyRepaintPool;
  full, partial: Boolean;
begin
  { [F4b] the flush's start, for `rendered`'s elapsedTime }
  FPaintT0 := AnimClock;
  FDrLastRects := nil;
  FDrLastFull := True;
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;
  R := Rect(0, 0, w, h);
  FDrScale := Max(1, AScale.Scale);
  if FStatic = nil then FStatic := TTyPaintCache.Create;
  { PPI IS PART OF THE KEY -- see RenderCached }
  if APPI <> FStaticPPI then
  begin
    StaticDrop;
    FStaticPPI := APPI;
  end;
  TyRepaintPoolInit(pool);
  full := False;
  { upstream's frame: the flags become state lists [Batch 88] -- and a
    change of them is repainted in rects where it can be }
  if StApplyChanged then
  begin
    { built again, or patched where only the states changed [P2] }
    FProgReuse := StPatchList;
    partial := DrCanPartial(w, h) and DrStaticPartial(R, APPI, pool);
    if not partial then StaticDrop;
  end;
  { and the device scale, as RenderCached's (#83) }
  if FStatic.NeedsRender(w, h, AScale) then
  begin
    DrStaticFull(R, APPI);
    full := True;
  end;
  DrDynamic(R, APPI, pool, full);
  FDrLastFull := full;
  if not full then FDrLastRects := TyRepaintPoolFinish(pool);
  { the update painted: `rendered` [Batch 119] }
  EmitFlush;
  { the bar race, as RenderTo's [Batch 135] }
  if FRtAfterRelayout then
  begin
    FRtAfterRelayout := False;
    RtRenderPass;
    RtRendered;
  end;
  RtFlushQueue;
end;

procedure TTyCustomAdvanceChart.DrComposite(ACanvas: TCanvas; const ARect: TRect);
var
  i, k, w, h: Integer;
  px: TRect;
  ink: Boolean;
begin
  if (FStatic = nil) or (ACanvas = nil) then Exit;
  if FDrLastFull then
  begin
    FStatic.Blit(ACanvas);
    if (FDrDyn <> nil) and (Length(FDrDynTiles) > 0) then
      TyDrawRasterBitmap(ACanvas, ARect, FDrDyn, False);
    Exit;
  end;
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  for i := 0 to High(FDrLastRects) do
  begin
    if not TyZrRectToPixels(FDrLastRects[i], w, h, px) then Continue;
    { the static layer at the canvas origin, as Blit puts it }
    DrCopyStatic(ACanvas, px);
    ink := False;
    if FDrDyn <> nil then
      for k := 0 to High(FDrDynTiles) do
        if TyZrRectIntersect(FDrDynTiles[k], FDrLastRects[i]) then
        begin
          ink := True;
          Break;
        end;
    if ink then
      DrDrawDynamic(ACanvas, px, ARect.Left + px.Left, ARect.Top + px.Top);
  end;
end;

procedure TTyCustomAdvanceChart.DrPaintWindow;
var
  clip, px, client, ink: TRect;
  i: Integer;
  prepared: Boolean;
  sc: TTyCanvasScale;
begin
  client := ClientRect;
  clip := Canvas.ClipRect;
  { a canvas in raster units clips in its pixels: the clip in client px (#83) }
  sc := TyCanvasDeviceScale(Canvas);
  if sc.DeviceUnits and (sc.Scale > 1) then
    clip := Rect(clip.Left div sc.Scale, clip.Top div sc.Scale,
      (clip.Right + sc.Scale - 1) div sc.Scale, (clip.Bottom + sc.Scale - 1) div sc.Scale);
  if (clip.Right <= clip.Left) or (clip.Bottom <= clip.Top) then clip := client;
  { A PAINT NOBODY FLUSHED FOR prepares its own frame: an Invalidate, a
    window uncovered, a flush overtaken by a newer request }
  prepared := not FDrFlushed or FDrPending or (FStatic = nil);
  if prepared then
  begin
    TbFrame;
    DrPrepare(client, Font.PixelsPerInch, sc);
  end;
  FDrFlushed := False;
  FDrPending := False;
  if FStatic = nil then Exit;
  { THE CLIP, whatever invalidated it }
  DrCopyStatic(Canvas, clip);
  if (FDrDyn <> nil) and (Length(FDrDynTiles) > 0) then
  begin
    ink := Rect(MaxInt, MaxInt, -MaxInt, -MaxInt);
    for i := 0 to High(FDrDynTiles) do
      if TyZrRectToPixels(FDrDynTiles[i], client.Right, client.Bottom, px) then
      begin
        if px.Left < ink.Left then ink.Left := px.Left;
        if px.Top < ink.Top then ink.Top := px.Top;
        if px.Right > ink.Right then ink.Right := px.Right;
        if px.Bottom > ink.Bottom then ink.Bottom := px.Bottom;
      end;
    if IntersectRect(px, ink, clip) then
      DrDrawDynamic(Canvas, px, px.Left, px.Top);
  end;
  { A FRAME LARGER THAN THE CLIP is invalidated again where the clip did
    not reach; that paint only composites }
  if prepared and HandleAllocated then
  begin
    if FDrLastFull then
    begin
      if (clip.Left > 0) or (clip.Top > 0) or (clip.Right < client.Right)
        or (clip.Bottom < client.Bottom) then
      begin
        FDrFlushed := True;
        LCLIntf.InvalidateRect(Handle, nil, False);
      end;
    end
    else
      for i := 0 to High(FDrLastRects) do
        if TyZrRectToPixels(FDrLastRects[i], client.Right, client.Bottom, px)
          and not ((px.Left >= clip.Left) and (px.Top >= clip.Top)
            and (px.Right <= clip.Right) and (px.Bottom <= clip.Bottom)) then
        begin
          FDrFlushed := True;
          LCLIntf.InvalidateRect(Handle, @px, False);
        end;
  end;
end;

procedure TTyCustomAdvanceChart.DrFlushAsync(AData: PtrInt);
var
  i: Integer;
  px: TRect;
begin
  FDrQueued := False;
  if not FUseDirtyRect or not FDrPending or not HandleAllocated
    or (csDestroying in ComponentState) then Exit;
  { the window's frame: camAuto animates it, the toolbox's hover lands }
  FAnimWindow := True;
  try
    TbFrame;
    { no canvas to hand over: the window's own says its device scale }
    DrPrepare(ClientRect, Font.PixelsPerInch, TyCanvasDeviceScale(Canvas));
  finally
    FAnimWindow := False;
  end;
  FDrPending := False;
  FDrFlushed := True;
  if FDrLastFull then
    LCLIntf.InvalidateRect(Handle, nil, False)
  else
    for i := 0 to High(FDrLastRects) do
      if TyZrRectToPixels(FDrLastRects[i], ClientWidth, ClientHeight, px) then
        LCLIntf.InvalidateRect(Handle, @px, False);
end;
