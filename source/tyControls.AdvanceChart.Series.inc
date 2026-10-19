{ Part of tyControls.AdvanceChart (included, not a unit): the polars, the single axes,
  themeRivers, lines, parallels, radars, gauges, funnels and pies, and the per-series
  visuals. Moved out of the unit only to keep it readable; what the control is and why it
  is built the way it is, see the unit header. }

procedure TTyAdvanceChart.SolvePies;
var
  i, dim, k: Integer;
  cell: TTyXYWH;
  fromCentre: Boolean;
  cx, cy: Double;
begin
  SetLength(FPies, Length(FBindings));
  SetLength(FPieSpecs, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FPies[i] := Default(TTyPieLayout);
    FPieSpecs[i] := TyPieSpecDefault;
    if i > High(FStores) then Break;
    if not FBindings[i].Resolved then Continue;
    if FBindings[i].SeriesType <> TyPieSeriesTypeName then Continue;
    FPieSpecs[i] := TyPieSpecOf(FOption, FBindings[i].SeriesIndex);
    dim := FStores[i].DimIndexOf(TyPieValueDim);
    { FLastRect, not a grid: a pie is laid out against the CONTROL, and its
      own left/top/right/bottom shrink that. Handing it a grid rect would
      centre it on the plot instead of on the chart, which is not where
      ECharts puts it. }
    { A PIE IN A MATRIX CELL OR A CALENDAR DAY [Batches 72, 147, 151]:
      createBoxLayoutReference asks the host's dataToLayout for `coord`,
      else for `center` read as one (getCoord2); getCircleLayout's viewRect
      is getLayoutRect of the series' box in that rect (a calendar's content
      rect), the percentages of the centre and the radii against it, and
      the centre is the refPoint -- the rect's x + width / 2 -- when the
      coord came from `center`. A cell of no position draws nothing. }
    if SeriesBoxRef(i, True, cell, fromCentre) then
    begin
      FPies[i] := TyPieLayoutInView(FPieSpecs[i], TyGetLayoutRect(
        FPieSpecs[i].BoxRaw, cell.X, cell.Y, cell.W, cell.H, []),
        FStores[i], dim);
      if fromCentre then
      begin
        cx := cell.X + cell.W / 2;
        cy := cell.Y + cell.H / 2;
        FPies[i].CX := cx;
        FPies[i].CY := cy;
        for k := 0 to High(FPies[i].Sectors) do
        begin
          FPies[i].Sectors[k].CX := cx;
          FPies[i].Sectors[k].CY := cy;
        end;
      end;
      if IsNan(FPies[i].CX) or IsNan(FPies[i].CY) then FPies[i].Valid := False;
      Continue;
    end;
    { ON A GEO [Batch 152, D14 GE4] -- OR A CARTESIAN [Batch 154]: usage
      'box' (a pie's default) with a host of only a dataToPoint, the centre
      its point of the coord; usage 'data' leaves the pie on the canvas }
    if FBindings[i].BoxPoint then
    begin
      FPies[i] := GeoPieLayout(i, dim);
      Continue;
    end;
    FPies[i] := TyPieLayoutOf(FPieSpecs[i], FLastRect, FStores[i], dim);
  end;
end;

procedure TTyAdvanceChart.SolveFunnels;
var
  i, dim: Integer;
  cell: TTyXYWH;
  fromCentre: Boolean;
begin
  SetLength(FFunnels, Length(FBindings));
  SetLength(FFunnelSpecs, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FFunnels[i] := Default(TTyFunnelLayout);
    FFunnelSpecs[i] := TyFunnelSpecDefault;
    if i > High(FStores) then Break;
    if not FBindings[i].Resolved then Continue;
    if FBindings[i].SeriesType <> TyFunnelSeriesTypeName then Continue;
    FFunnelSpecs[i] := TyFunnelSpecOf(FOption, FBindings[i].SeriesIndex);
    dim := FStores[i].DimIndexOf(TyPieValueDim);
    { FLastRect, not a grid -- a funnel is laid out against the CONTROL and
      its own left/top/right/bottom shrink that, the same rule a pie follows
      and for the same reason. }
    { A FUNNEL IN A MATRIX CELL OR A CALENDAR DAY: its box against the cell
      its `coord` names (a funnel reads no `center`) [Batches 147, 151] }
    if SeriesBoxRef(i, False, cell, fromCentre) then
    begin
      { getLayoutRect of the series' box in the cell, as upstream holds both }
      FFunnels[i] := TyFunnelLayoutInView(FFunnelSpecs[i],
        TyGetLayoutRect(FFunnelSpecs[i].BoxRaw, cell.X, cell.Y, cell.W,
        cell.H, []), FStores[i], dim);
      { a cell of no size draws nothing; one of no place is at the canvas'
        edge (getLayoutRect's `x || 0`) [Batch 151] }
      if not TyXYWHHasSize(cell) then FFunnels[i].Valid := False;
      Continue;
    end;
    FFunnels[i] := TyFunnelLayoutOf(FFunnelSpecs[i], FLastRect,
      FStores[i], dim);
  end;
end;

procedure TTyAdvanceChart.FreeRadars;
var i: Integer;
begin
  for i := 0 to High(FRadars) do FreeAndNil(FRadars[i]);
  FRadars := nil;
end;

function TTyAdvanceChart.RadarLayout(AIndex: Integer): TTyRadar;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FRadars)) then Result := FRadars[AIndex];
end;

{ ==================== the polars [Batch 111] ==================== }

procedure TTyAdvanceChart.FreePolars;
var i: Integer;
begin
  for i := 0 to High(FPolars) do
    FPolars[i].Free;
  FPolars := nil;
end;

function TTyAdvanceChart.PolarCount: Integer;
begin
  Result := Length(FPolars);
end;

function TTyAdvanceChart.PolarLayout(AIndex: Integer): TTyPolar;
begin
  if (AIndex < 0) or (AIndex > High(FPolars)) then Exit(nil);
  Result := FPolars[AIndex];
end;

{ ==================== the single axes [Batch 118] ==================== }

procedure TTyAdvanceChart.FreeSingles;
var i: Integer;
begin
  for i := 0 to High(FSingles) do
    FSingles[i].Free;
  FSingles := nil;
end;

function TTyAdvanceChart.SingleCount: Integer;
begin
  Result := Length(FSingles);
end;

function TTyAdvanceChart.SingleLayout(AIndex: Integer): TTySingle;
begin
  if (AIndex < 0) or (AIndex > High(FSingles)) then Exit(nil);
  Result := FSingles[AIndex];
end;

{ WHAT A SINGLE AXIS VIEW DRAWS, in the skin's axis styles -- the same keys
  the grid's and the polar's axes are drawn in: upstream's single axis takes
  axisDefault like every other }
procedure TTyAdvanceChart.PaintSingles(APainter: TTyPainter; APPI: Integer;
  const AMeasurer: ITyTextMeasurer; ABelow: Boolean);
var
  i, q, ink: Integer;
  s: TTySingle;
  model: TTyStyleModel;
  lineS, tickS, splitS, areaS, minorTickS, labelS, nameS, inkStyle: TTyStyleSet;
  areaColour: TTyColor;
  lblW, lblH: Integer;
  v: TTySingleAxisView;
  sp: TTyAxisLayoutSpec;
  pl: TTyAxisNamePlacement;

  function LineWidth(const AStyle: TTyStyleSet): Double;
  begin
    if tpBorderWidth in AStyle.Present then Result := AStyle.BorderWidth
    else Result := 1;
    if Result < 0.05 then Result := 0.05;
  end;

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

  procedure TextSizeOf(const AText: string; const AStyle: TTyStyleSet;
    out AW, AH: Integer);
  var w, h: Double;
  begin
    AW := 0;
    AH := 0;
    if AMeasurer = nil then Exit;
    AMeasurer.MeasureLine(AText, AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, w, h);
    AW := Round(w);
    AH := Round(h);
  end;

  { a place that is a number: a frame of no position (a vertical orient
    at the default bottom) puts everything at none, which draws nothing }
  function Finite(AX, AY: Double): Boolean;
  begin
    Result := not (IsNan(AX) or IsNan(AY) or IsInfinite(AX) or IsInfinite(AY));
  end;

  { the lines of AInk (every one when AInk < 0), one path, one stroke }
  procedure StrokeLines(const ALines: TTySingleLineArray; const AStyle: TTyStyleSet;
    AInk: Integer);
  var k, n: Integer;
  begin
    if not (tpBorderColor in AStyle.Present) then Exit;
    n := 0;
    APainter.BeginPath;
    for k := 0 to High(ALines) do
    begin
      if not ALines[k].Drawn then Continue;
      if not (Finite(ALines[k].X1, ALines[k].Y1) and Finite(ALines[k].X2, ALines[k].Y2)) then
        Continue;
      if (AInk >= 0) and (ALines[k].ColourIndex <> AInk) then Continue;
      APainter.MoveTo(ALines[k].X1, ALines[k].Y1);
      APainter.LineTo(ALines[k].X2, ALines[k].Y2);
      Inc(n);
    end;
    if n > 0 then APainter.StrokePath(AStyle.BorderColor, LineWidth(AStyle));
  end;

  procedure PaintArrow(const AArrow: TTyAxisArrow);
  var
    el: TTyChartElement;
    path: TTyZrPath;
    t: string;
  begin
    { [F6a] a picture }
    if TyAxisArrowImage(AArrow, el) then
    begin
      TyRenderElement(APainter, el);
      Exit;
    end;
    t := AArrow.SymbolType;
    path := TyZrSymbol(t, -AArrow.W / 2, -AArrow.H / 2, AArrow.W, AArrow.H);
    if Length(path) = 0 then Exit;
    el := Default(TTyChartElement);
    el.Style.Alpha := 1;
    el.Shape := TyMkZrShape(path, TyZrLocal(1, 1, AArrow.Rotation, AArrow.X,
      AArrow.Y), True);
    if Copy(t, 1, 5) = 'empty' then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(model.ResolveStyle(
        'TyAdvChartEmptyCircle', '', []).Background.Color);
      el.Style.StrokeColor := TTyChartColor(lineS.BorderColor);
      el.Style.StrokeWidthLogical := 2;
    end
    else if t = 'line' then
    begin
      el.Style.StrokeColor := TTyChartColor(lineS.BorderColor);
      el.Style.StrokeWidthLogical := 1;
    end
    else
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(lineS.BorderColor);
    end;
    TyRenderElement(APainter, el);
  end;

begin
  if Length(FSingles) = 0 then Exit;
  { excludeComponents names the view [Batch 118] }
  if ViewHidden(cvSingleAxis) then Exit;
  model := ActiveController.Model;
  lineS := model.ResolveStyle('TyAdvChartAxisLine', '', []);
  tickS := model.ResolveStyle('TyAdvChartAxisTick', '', []);
  splitS := model.ResolveStyle('TyAdvChartSplitLine', '', []);
  areaS := model.ResolveStyle('TyAdvChartSplitArea', '', []);
  minorTickS := model.ResolveStyle('TyAdvChartMinorTick', '', []);
  for i := 0 to High(FSingles) do
  begin
    s := FSingles[i];
    if s = nil then Continue;
    v := s.View;
    if not v.Shown then Continue;
    ViewDrew(cvSingleAxis);
    if ABelow then
    begin
      { the split areas in their colours: the author's list, or the skin's
        colour and none in turn }
      for q := 0 to High(v.SplitAreas) do
      begin
        ink := v.SplitAreas[q].ColourIndex;
        if Length(v.Furn.SplitAreaInks) > 0 then
        begin
          if ink > High(v.Furn.SplitAreaInks) then ink := 0;
          if not v.Furn.SplitAreaInks[ink].Ok then Continue;
          areaColour := TTyColor(v.Furn.SplitAreaInks[ink].Colour);
        end
        else if (ink <> 0) or not (tpBackground in areaS.Present) then
          Continue
        else
          areaColour := areaS.Background.Color;
        APainter.BeginPath;
        APainter.MoveTo(v.SplitAreas[q].X, v.SplitAreas[q].Y);
        APainter.LineTo(v.SplitAreas[q].X + v.SplitAreas[q].W, v.SplitAreas[q].Y);
        APainter.LineTo(v.SplitAreas[q].X + v.SplitAreas[q].W,
          v.SplitAreas[q].Y + v.SplitAreas[q].H);
        APainter.LineTo(v.SplitAreas[q].X, v.SplitAreas[q].Y + v.SplitAreas[q].H);
        APainter.ClosePath;
        APainter.FillPath(areaColour);
      end;
      { the split lines in their colours }
      if (tpBorderColor in splitS.Present) or (Length(v.Furn.SplitLineInks) > 0) then
        for q := 0 to Math.Max(0, High(v.Furn.SplitLineInks)) do
        begin
          inkStyle := splitS;
          if Length(v.Furn.SplitLineInks) > 0 then
          begin
            if not v.Furn.SplitLineInks[q].Ok then Continue;
            inkStyle.BorderColor := TTyColor(v.Furn.SplitLineInks[q].Colour);
            Include(inkStyle.Present, tpBorderColor);
            StrokeLines(v.SplitLines, inkStyle, q);
          end
          else
            StrokeLines(v.SplitLines, inkStyle, -1);
        end;
      Continue;
    end;
    sp := v.Spec;
    if v.HasLine and (tpBorderColor in lineS.Present)
      and Finite(v.Line.X1, v.Line.Y1) and Finite(v.Line.X2, v.Line.Y2) then
    begin
      APainter.BeginPath;
      { cut at the breaks: a segment between each two [F4a] }
      if sp.HasBreakLine then
      begin
        for q := 0 to High(sp.BreakLineSegs) do
          if Finite(sp.BreakLineSegs[q].X1, sp.BreakLineSegs[q].Y1)
            and Finite(sp.BreakLineSegs[q].X2, sp.BreakLineSegs[q].Y2) then
          begin
            APainter.MoveTo(sp.BreakLineSegs[q].X1, sp.BreakLineSegs[q].Y1);
            APainter.LineTo(sp.BreakLineSegs[q].X2, sp.BreakLineSegs[q].Y2);
          end;
      end
      else
      begin
        APainter.MoveTo(v.Line.X1, v.Line.Y1);
        APainter.LineTo(v.Line.X2, v.Line.Y2);
      end;
      APainter.StrokePath(lineS.BorderColor, LineWidth(lineS));
      for q := 0 to High(sp.Arrows) do
        if Finite(sp.Arrows[q].X, sp.Arrows[q].Y) then PaintArrow(sp.Arrows[q]);
    end;
    StrokeLines(v.Ticks, tickS, -1);
    StrokeLines(v.MinorTicks, minorTickS, -1);
    AxisTextStyles(@sp, labelS, nameS);
    pl := sp.NamePlacement;
    if pl.Shown and (tpTextColor in nameS.Present) and Finite(pl.X, pl.Y) then
    begin
      if Length(pl.Rt) > 0 then
        TyRenderRtPieces(APainter, pl.Rt, pl.X, pl.Y, pl.RotationRad, sp.RtScale,
          1, True, nameS.TextColor)
      else if Abs(pl.RotationRad) < 1e-9 then
      begin
        TextSizeOf(pl.Text, nameS, lblW, lblH);
        APainter.DrawText(AnchorBox(pl.X, pl.Y, lblW, lblH, pl.AnchorH, pl.AnchorV),
          pl.Text, nameS.FontName, ResolveFontSize(nameS), nameS.FontWeight,
          nameS.TextColor, taCenter, tlCenter, False, 0, False, Pos(#10, pl.Text) > 0);
      end
      else
      begin
        TextSizeOf(pl.Text, nameS, lblW, lblH);
        DrawRotatedNameLines(APainter, pl.Text, nameS.FontName, ResolveFontSize(nameS),
          nameS.FontWeight, nameS.TextColor, pl.X, pl.Y, pl.RotationRad,
          AnchorAlign(pl.AnchorH), AnchorLayout(pl.AnchorV), lblH);
      end;
    end;
    if not (tpTextColor in labelS.Present) then Continue;
    for q := 0 to High(sp.Placements) do
    begin
      if not sp.Placements[q].Shown or (sp.Placements[q].Text = '') then Continue;
      if not Finite(sp.Placements[q].X, sp.Placements[q].Y) then Continue;
      if Length(sp.Placements[q].Rt) > 0 then
      begin
        TyRenderRtPieces(APainter, sp.Placements[q].Rt, sp.Placements[q].X,
          sp.Placements[q].Y, sp.RotationRad, sp.RtScale, 1, True, labelS.TextColor);
        Continue;
      end;
      if sp.RotationRad <> 0 then
      begin
        { every line of a label of several [R2-A] }
        TextSizeOf(sp.Placements[q].Text, labelS, lblW, lblH);
        DrawRotatedNameLines(APainter, sp.Placements[q].Text, labelS.FontName,
          ResolveFontSize(labelS), labelS.FontWeight, labelS.TextColor,
          sp.Placements[q].X, sp.Placements[q].Y, sp.RotationRad,
          AnchorAlign(sp.Placements[q].AnchorH), AnchorLayout(sp.Placements[q].AnchorV),
          lblH);
        Continue;
      end;
      TextSizeOf(sp.Placements[q].Text, labelS, lblW, lblH);
      APainter.DrawText(AnchorBox(sp.Placements[q].X, sp.Placements[q].Y, lblW,
        lblH, sp.Placements[q].AnchorH, sp.Placements[q].AnchorV),
        sp.Placements[q].Text, labelS.FontName, ResolveFontSize(labelS),
        labelS.FontWeight, labelS.TextColor, taCenter, tlCenter, False, 0, False,
        Pos(#10, sp.Placements[q].Text) > 0);
    end;
  end;
end;

function TTyAdvanceChart.SinglePointerGeometry(const AHit: TTyAxisHit;
  const ARect: TRect; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  out ADraw: TTySinglePointerDraw): Boolean;
var
  pv, px, margin, tw, th, padL, padT, padR, padB, x, y, vw, vh: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  labelS: TTyStyleSet;
  scale: Double;
begin
  ADraw := Default(TTySinglePointerDraw);
  ADraw.Shape.Kind := spkNone;
  Result := False;
  if (AHit.Single = nil) or (AHit.Axis = nil) then Exit;
  Result := True;
  pv := PointerValue(AHit);
  { coordSys.dataToPoint(value)[0] -- the x, whichever dimension the axis
    runs along: a vertical axis' pointer stays on the rect's centre column,
    upstream's }
  px := AHit.Single.ValueToPoint(pv).X;
  case AHit.Spec.PointerType of
    aptLine: ADraw.Shape := TySinglePointerShape(AHit.Single, px, 0, False);
    aptShadow: ADraw.Shape := TySinglePointerShape(AHit.Single, px,
      TyPolarPointerBand(AHit.Axis), True);
  end;
  if not AHit.Spec.LabelSpec.Show or (AMeasurer = nil) then Exit;
  ADraw.Text := PointerLabelText(AHit, pv);
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerLabel', '', []);
  AMeasurer.MeasureLine(ADraw.Text, labelS.FontName, ResolveFontSize(labelS),
    labelS.FontWeight, tw, th);
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  if AHit.Spec.LabelSpec.HasPadding then
  begin
    padL := AHit.Spec.LabelSpec.PadLeft * scale;
    padT := AHit.Spec.LabelSpec.PadTop * scale;
    padR := AHit.Spec.LabelSpec.PadRight * scale;
    padB := AHit.Spec.LabelSpec.PadBottom * scale;
  end
  else
  begin
    padL := labelS.Padding.Left * scale;
    padT := labelS.Padding.Top * scale;
    padR := labelS.Padding.Right * scale;
    padB := labelS.Padding.Bottom * scale;
  end;
  margin := ActiveController.Metric(TyAdvChartAxisPointerMarginVar,
    TyAdvChartAxisPointerMargin);
  if AHit.Spec.LabelSpec.MarginLogical <> 3 then
    margin := AHit.Spec.LabelSpec.MarginLogical;
  margin := margin * scale;
  { buildCartesianSingleLabelElOption: getTransformedPosition, then
    buildLabelElOption's align and confineInContainer }
  TySinglePointerLabelAnchor(AHit.Single, FOption, pv, margin, x, y, ah, av);
  ADraw.W := tw + padR + padL;
  ADraw.H := th + padT + padB;
  if ah = tahRight then x := x - ADraw.W;
  if ah = tahCentre then x := x - ADraw.W / 2;
  if av = tavBottom then y := y - ADraw.H;
  if av = tavMiddle then y := y - ADraw.H / 2;
  vw := ARect.Right - ARect.Left;
  vh := ARect.Bottom - ARect.Top;
  x := Math.Min(x + ADraw.W, vw) - ADraw.W;
  y := Math.Min(y + ADraw.H, vh) - ADraw.H;
  x := Math.Max(x, Double(0));
  y := Math.Max(y, Double(0));
  ADraw.X := x;
  ADraw.Y := y;
  ADraw.HasLabel := True;
end;

procedure TTyAdvanceChart.PaintSinglePointer(APainter: TTyPainter;
  const ARect: TRect; APPI: Integer; const AMeasurer: ITyTextMeasurer;
  const AHit: TTyAxisHit);
var
  d: TTySinglePointerDraw;
  lineS, shadowS, labelS: TTyStyleSet;
  colour: TTyColor;
  w: Double;
  dash: TTyDoubleArray;
  box: TRect;
  corners: TTyCorners;
  surface: TTyFill;
  ln: TTySingleLine;
begin
  if not SinglePointerGeometry(AHit, ARect, AMeasurer, APPI, d) then Exit;
  { a pointer at no number draws nothing (a frame of no position) }
  if IsNan(d.Shape.X1) or IsNan(d.Shape.Y1) or IsNan(d.Shape.X2) or IsNan(d.Shape.Y2) then
    d.Shape.Kind := spkNone;
  if IsNan(d.X) or IsNan(d.Y) or IsNan(d.W) or IsNan(d.H) then d.HasLabel := False;
  lineS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointer', '', []);
  shadowS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerShadow', '', []);
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerLabel', '', []);
  case d.Shape.Kind of
    spkLine:
      if tpBorderColor in lineS.Present then
      begin
        colour := lineS.BorderColor;
        if AHit.Spec.HasLineColour then colour := TTyColor(AHit.Spec.LineColour);
        w := lineS.BorderWidth;
        if AHit.Spec.HasLineWidth then w := AHit.Spec.LineWidthLogical;
        if w > 0 then
        begin
          { subPixelOptimize: true -- the line on the pixel grid as it is
            built }
          ln := Default(TTySingleLine);
          ln.X1 := d.Shape.X1;
          ln.Y1 := d.Shape.Y1;
          ln.X2 := d.Shape.X2;
          ln.Y2 := d.Shape.Y2;
          TySingleSubPixelLine(ln, APainter.ScaleF(w));
          dash := TyDashPattern(AHit.Spec.LineDash, AHit.Spec.LineDashExplicit, w);
          APainter.SetLineDash(dash);
          APainter.BeginPath;
          APainter.MoveTo(ln.X1, ln.Y1);
          APainter.LineTo(ln.X2, ln.Y2);
          APainter.StrokePath(colour, w);
          APainter.SetLineDash([]);
        end;
      end;
    spkRect:
      if tpBackground in shadowS.Present then
      begin
        colour := shadowS.Background.Color;
        if AHit.Spec.HasShadowColour then colour := TTyColor(AHit.Spec.ShadowColour);
        APainter.BeginPath;
        APainter.MoveTo(d.Shape.X1, d.Shape.Y1);
        APainter.LineTo(d.Shape.X1 + d.Shape.X2, d.Shape.Y1);
        APainter.LineTo(d.Shape.X1 + d.Shape.X2, d.Shape.Y1 + d.Shape.Y2);
        APainter.LineTo(d.Shape.X1, d.Shape.Y1 + d.Shape.Y2);
        APainter.ClosePath;
        APainter.FillPath(colour);
      end;
  end;
  if not d.HasLabel or (d.Text = '') then Exit;
  if not (tpBackground in labelS.Present) then Exit;
  box := Rect(Round(d.X), Round(d.Y), Round(d.X + d.W), Round(d.Y + d.H));
  corners := TyEffectiveCorners(labelS);
  if AHit.Spec.LabelSpec.HasBorderRadius then
    corners := TyCorners(Round(AHit.Spec.LabelSpec.BorderRadiusLogical),
      Round(AHit.Spec.LabelSpec.BorderRadiusLogical),
      Round(AHit.Spec.LabelSpec.BorderRadiusLogical),
      Round(AHit.Spec.LabelSpec.BorderRadiusLogical));
  surface := labelS.Background;
  if AHit.Spec.LabelSpec.HasBackground then
  begin
    surface.Kind := tfkSolid;
    surface.Color := TTyColor(AHit.Spec.LabelSpec.Background);
  end;
  APainter.FillBackground(box, surface, corners);
  if AHit.Spec.LabelSpec.HasBorderColour and AHit.Spec.LabelSpec.HasBorderWidth
    and (AHit.Spec.LabelSpec.BorderWidthLogical > 0) then
    APainter.StrokeBorder(box, corners,
      Round(AHit.Spec.LabelSpec.BorderWidthLogical),
      TTyColor(AHit.Spec.LabelSpec.BorderColour))
  else if TyBorderVisible(labelS) then
    APainter.StrokeBorder(box, corners, labelS.BorderWidth, labelS.BorderColor);
  colour := labelS.TextColor;
  if AHit.Spec.LabelSpec.HasColour then colour := TTyColor(AHit.Spec.LabelSpec.Colour);
  APainter.DrawText(box, d.Text, labelS.FontName, ResolveFontSize(labelS),
    labelS.FontWeight, colour, taCenter, tlCenter, False);
end;

{ ==================== the themeRivers [Batch 118] ==================== }

procedure TTyAdvanceChart.SolveRivers(APPI: Integer);
var
  i: Integer;
  scale, margin: Double;
  d: TJSONData;
  lab: TJSONData;
begin
  FRivers := nil;
  SetLength(FRivers, Length(FBindings));
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  for i := 0 to High(FBindings) do
  begin
    FRivers[i] := Default(TTyThemeRiverLayout);
    if FBindings[i].SeriesType <> TyThemeRiverSeriesTypeName then Continue;
    if (FBindings[i].Single = nil) or FBindings[i].Hidden then Continue;
    if (i > High(FStores)) or (FStores[i] = nil) then Continue;
    { label.margin, 4 unless written }
    margin := 4;
    d := FOption.ComponentAt('series', FBindings[i].SeriesIndex);
    if d is TJSONObject then
    begin
      lab := TJSONObject(d).Find('label');
      if lab is TJSONObject then
      begin
        lab := TJSONObject(lab).Find('margin');
        if (lab <> nil) and (lab.JSONType = jtNumber) then margin := lab.AsFloat;
      end;
    end;
    FRivers[i] := TyThemeRiverLayout(FOption, FBindings[i].SeriesIndex,
      TTySingle(FBindings[i].Single), FStores[i], margin * scale);
  end;
end;

function TTyAdvanceChart.RiverLayoutOf(ASeriesIndex: Integer): TTyThemeRiverLayout;
var slot: Integer;
begin
  Result := Default(TTyThemeRiverLayout);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FRivers)) then Result := FRivers[slot];
end;

{ emphasis.label.show written false on a themeRiver }
function TTyAdvanceChart.RiverEmphasisLabelOff(ASlot: Integer): Boolean;
var d: TJSONData;
begin
  Result := False;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (d is TJSONObject) then Exit;
  d := TJSONObject(d).Find('emphasis');
  if not (d is TJSONObject) then Exit;
  d := TJSONObject(d).Find('label');
  if not (d is TJSONObject) then Exit;
  d := TJSONObject(d).Find('show');
  Result := (d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean;
end;

function TTyAdvanceChart.RiverLabelSpec(ASlot: Integer): TTyLabelSpec;
var
  base: TTyLabelSpec;
  outS, lightS, midS, darkS: TTyStyleSet;
  hasCol: Boolean;
  col: Cardinal;
begin
  base := TyLabelSpecNone;
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight', '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '', []);
  base.FontName := outS.FontName;
  base.FontSizeLogical := ResolveFontSize(outS);
  base.FontWeight := outS.FontWeight;
  hasCol := False;
  col := 0;
  GlobalTextOver(base.FontName, base.FontSizeLogical, base.FontWeight,
    hasCol, col, [ttpSize, ttpWeight, ttpFamily]);
  { THE TYPE'S LABEL DEFAULTS (ThemeRiverSeries.ts): shown, 11 px, the
    name -- and shown under emphasis, unless that says otherwise }
  base.Show := True;
  base.StateShow := not RiverEmphasisLabelOff(ASlot);
  base.FontSizeLogical := 11;
  base.DefaultText := tldName;
  base.OutsideColour := TTyChartColor(outS.TextColor);
  base.InsideColour[0] := TTyChartColor(lightS.TextColor);
  base.InsideColour[1] := TTyChartColor(midS.TextColor);
  base.InsideColour[2] := TTyChartColor(darkS.TextColor);
  LabelGround(base.Ground, base.GroundDark);
  base.RtGlobal := RtGlobal;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit(base);
  Result := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
end;

function TTyAdvanceChart.BuildRiverMarks(ASlot: Integer; AList: TTyPaintList;
  APPI: Integer): Integer;
var
  L: TTyThemeRiverLayout;
  pg: TTyRiverPolygon;
  v: TTySeriesVisual;
  perRaw: TTyChartColorArray;
  spec: TTyLabelSpec;
  st: TTyDataStore;
  el: TTyChartElement;
  pts: TTyPointFArray;
  cmds: TTyPathCmdArray;
  k, j, n, m, raw, si: Integer;
  gy: Double;
  fill: TTyChartColor;

  function Legal(const AP: TTyPointF): Boolean;
  begin
    Result := not (IsNan(AP.X) or IsNan(AP.Y) or IsInfinite(AP.X) or IsInfinite(AP.Y));
  end;

begin
  Result := 0;
  if (ASlot < 0) or (ASlot > High(FRivers)) or not FRivers[ASlot].Valid then Exit;
  L := FRivers[ASlot];
  st := FStores[ASlot];
  si := FBindings[ASlot].SeriesIndex;
  v := TySeriesVisual(TTyChartColor(SeriesColor(si)));
  ApplyOptStyle(v, si);
  perRaw := PerDatumColours(ASlot);
  spec := RiverLabelSpec(ASlot);
  gy := L.GroupY;
  for k := 0 to High(L.Polygons) do
  begin
    pg := L.Polygons[k];
    if not pg.Valid then Continue;
    { A PATH OF NO LEGAL POINT draws nothing: upstream's drawSegment skips
      every point that is not a number (a category axis' names are not) }
    if not TyRiverPathDraws(pg.Cmds) then Continue;
    { the polygon in the canvas' frame: the group's y added -- a ring of the
      bottoms forward and the tops back for the hit test (its legal points),
      the path upstream builds for the ink }
    n := Length(pg.Bottoms);
    SetLength(pts, 2 * n);
    m := 0;
    for j := 0 to n - 1 do
      if Legal(pg.Bottoms[j]) then
      begin
        pts[m] := TyPointF(pg.Bottoms[j].X, pg.Bottoms[j].Y + gy);
        Inc(m);
      end;
    for j := n - 1 downto 0 do
      if Legal(pg.Tops[j]) then
      begin
        pts[m] := TyPointF(pg.Tops[j].X, pg.Tops[j].Y + gy);
        Inc(m);
      end;
    SetLength(pts, m);
    cmds := Copy(pg.Cmds);
    for j := 0 to High(cmds) do
    begin
      cmds[j].Y := cmds[j].Y + gy;
      cmds[j].Y1 := cmds[j].Y1 + gy;
      cmds[j].Y2 := cmds[j].Y2 + gy;
    end;
    el := TyChartElement(TyShapePolygon(pts));
    { a layer takes the pointer: its hover, its tooltip, its states }
    el.Silent := False;
    el.Shape.Cmds := cmds;
    el.Shape.HasCmdBounds := True;
    el.Shape.CmdBounds := TyRectF(pg.Box.X, pg.Box.Y + gy, pg.Box.X + pg.Box.W,
      pg.Box.Y + gy + pg.Box.H);
    { THE LAYER'S STYLE IS ITS LAST ROW'S: the palette's colour of that row
      (colorBy 'data', one colour a name), the series' item style over it }
    raw := st.GetRawIndex(pg.StyleRow);
    fill := v.Fill;
    if (raw >= 0) and (raw <= High(perRaw)) then fill := perRaw[raw];
    el.Style := TyChartStyle;
    el.Style.HasFill := True;
    el.Style.FillColor := fill;
    el.Style.Alpha := v.Alpha;
    if (v.Stroke <> 0) and (v.StrokeWidthLogical > 0) then
    begin
      el.Style.StrokeColor := v.Stroke;
      el.Style.StrokeWidthLogical := v.StrokeWidthLogical;
    end;
    { and that row's decal [F4a] }
    el.Style.Decal := RowDecalOf(ASlot, raw);
    { setItemGraphicEl(idx): the polygon is the LAYER's index's datum }
    if k < st.Count then
      el.Datum := TyChartDatum(si, k, st.GetRawIndex(k))
    else
      el.Datum := TyChartDatum(si, k);
    el.Z := SeriesIntIn(si, 'z', 2);
    el.Z2 := 0;
    { the label: the last row's name, at the first row less the margin,
      halfway up -- the style's align (left unless written) and middle }
    { (a label at a place that is no number draws nothing) }
    if (spec.Show or spec.StateShow) and not (IsNan(pg.LabelX) or IsNan(pg.LabelY)
      or IsInfinite(pg.LabelX) or IsInfinite(pg.LabelY)) then
    begin
      { THE NAME AND NOTHING ELSE: the view hands setLabelStyle no label
        fetcher, so a formatter is never asked -- the default text, the last
        row's name, is the label }
      el.Caption.Text := st.GetItemName(pg.StyleRow);
      el.Caption.HasFixedAnchor := True;
      el.Caption.FixedX := pg.LabelX;
      el.Caption.FixedY := pg.LabelY + gy;
      el.Caption.FixedInside := False;
      if spec.HasAlignH then el.Caption.FixedAH := spec.AlignH
      else el.Caption.FixedAH := tahLeft;
      el.Caption.FixedAV := tavMiddle;
      el.Caption.FixedRotationRad := 0;
    end;
    { the enter animation's clip is made from the path's own rect }
    el.Anim := Default(TTyChartAnim);
    el.Anim.Role := carRiver;
    el.Anim.Series := si;
    el.Anim.Index := k;
    el.Anim.G[0] := pg.Box.X;
    el.Anim.G[1] := pg.Box.Y;
    el.Anim.G[2] := pg.Box.W;
    el.Anim.G[3] := pg.Box.H;
    el.Anim.G[4] := gy;
    { [F3c] THE LAYER'S PATH for the universal transition -- at the layer's
      index among the data's items (setItemGraphicEl(idx), upstream's) --
      in the group, which sits at its y }
    el.Anim.UtTag := 1;
    el.Anim.UtRow := k;
    el.Anim.UtOrder := 0;
    el.Anim.UtData := TyUtCmdsData(pg.Cmds);
    el.Anim.UtHasM := gy <> 0;
    if el.Anim.UtHasM then
    begin
      el.Anim.UtM[0] := 1;
      el.Anim.UtM[3] := 1;
      el.Anim.UtM[5] := gy;
    end;
    AList.Add(el);
    Inc(Result);
  end;
end;

{ WHAT THE TWO VIEWS DRAW, in the skin's axis styles -- the same keys the
  grid's axes draw in, because upstream's polar axes share axisDefault with
  every other axis. The geometry is the layout's, already on the pixel grid
  where upstream puts it there (the radius line and ticks). }
procedure TTyAdvanceChart.PaintPolars(APainter: TTyPainter; APPI: Integer;
  const AMeasurer: ITyTextMeasurer; ABelow: Boolean);
var
  i, k, ink: Integer;
  p: TTyPolar;
  model: TTyStyleModel;
  lineS, tickS, splitS, areaS, minorTickS, minorSplitS, labelS, nameS,
    inkStyle: TTyStyleSet;
  areaColour: TTyColor;
  lblW, lblH: Integer;
  view: TTyChartView;

  function LineWidth(const AStyle: TTyStyleSet): Double;
  begin
    if tpBorderWidth in AStyle.Present then Result := AStyle.BorderWidth
    else Result := 1;
    if Result < 0.05 then Result := 0.05;
  end;

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

  procedure TextSizeOf(const AText: string; const AStyle: TTyStyleSet;
    out AW, AH: Integer);
  var w, h: Double;
  begin
    AW := 0;
    AH := 0;
    if AMeasurer = nil then Exit;
    AMeasurer.MeasureLine(AText, AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, w, h);
    AW := Round(w);
    AH := Round(h);
  end;

  { the lines of AInk (every one when AInk < 0), one path, one stroke }
  procedure StrokeLines(const ALines: TTyPolarLineArray; const AStyle: TTyStyleSet;
    AInk: Integer);
  var q, n: Integer;
  begin
    if not (tpBorderColor in AStyle.Present) then Exit;
    n := 0;
    APainter.BeginPath;
    for q := 0 to High(ALines) do
    begin
      if not ALines[q].Drawn then Continue;
      if (AInk >= 0) and (ALines[q].ColourIndex <> AInk) then Continue;
      APainter.MoveTo(ALines[q].X1, ALines[q].Y1);
      APainter.LineTo(ALines[q].X2, ALines[q].Y2);
      Inc(n);
    end;
    if n > 0 then APainter.StrokePath(AStyle.BorderColor, LineWidth(AStyle));
  end;

  { zrender's buildPath of a circle, an arc, a ring or a sector with no
    corners, onto the current path }
  procedure ArcPath(const A: TTyPolarArc);
  var r, r0, t, arcLen: Double;
  begin
    case A.Kind of
      pakCircle:
        begin
          APainter.MoveTo(A.CX + A.R, A.CY);
          APainter.ArcTo(A.CX, A.CY, A.R, 0, 2 * Pi, False);
        end;
      pakArc:
        begin
          r := Math.Max(A.R, 0);
          APainter.MoveTo(TyJsCos(A.StartAngle) * r + A.CX,
            TyJsSin(A.StartAngle) * r + A.CY);
          APainter.ArcTo(A.CX, A.CY, r, A.StartAngle, A.EndAngle, not A.Clockwise);
        end;
      pakRing:
        begin
          APainter.MoveTo(A.CX + A.R, A.CY);
          APainter.ArcTo(A.CX, A.CY, A.R, 0, 2 * Pi, False);
          APainter.MoveTo(A.CX + A.R0, A.CY);
          APainter.ArcTo(A.CX, A.CY, A.R0, 2 * Pi, 0, True);
        end;
      pakSector:
        begin
          r := Math.Max(A.R, 0);
          r0 := Math.Max(A.R0, 0);
          if (r <= 0) and (r0 <= 0) then Exit;
          if r <= 0 then
          begin
            r := r0;
            r0 := 0;
          end;
          if r0 > r then
          begin
            t := r0;
            r0 := r;
            r := t;
          end;
          if IsNan(A.StartAngle) or IsNan(A.EndAngle) then Exit;
          arcLen := Abs(A.EndAngle - A.StartAngle);
          APainter.MoveTo(A.CX + r * TyJsCos(A.StartAngle),
            A.CY + r * TyJsSin(A.StartAngle));
          APainter.ArcTo(A.CX, A.CY, r, A.StartAngle, A.EndAngle, not A.Clockwise);
          if arcLen > 2 * Pi - 1e-4 then
          begin
            if r0 > 1e-4 then
            begin
              APainter.MoveTo(A.CX + r0 * TyJsCos(A.EndAngle),
                A.CY + r0 * TyJsSin(A.EndAngle));
              APainter.ArcTo(A.CX, A.CY, r0, A.EndAngle, A.StartAngle, A.Clockwise);
            end;
          end
          else if r0 > 1e-4 then
          begin
            APainter.LineTo(A.CX + r0 * TyJsCos(A.EndAngle),
              A.CY + r0 * TyJsSin(A.EndAngle));
            APainter.ArcTo(A.CX, A.CY, r0, A.EndAngle, A.StartAngle, A.Clockwise);
          end
          else
            APainter.LineTo(A.CX, A.CY);
          APainter.ClosePath;
        end;
    end;
  end;

  procedure StrokeArcs(const AArcs: TTyPolarArcArray; const AStyle: TTyStyleSet;
    AInk: Integer);
  var q, n: Integer;
  begin
    if not (tpBorderColor in AStyle.Present) then Exit;
    n := 0;
    APainter.BeginPath;
    for q := 0 to High(AArcs) do
    begin
      if (AInk >= 0) and (AArcs[q].ColourIndex <> AInk) then Continue;
      ArcPath(AArcs[q]);
      Inc(n);
    end;
    if n > 0 then APainter.StrokePath(AStyle.BorderColor, LineWidth(AStyle));
  end;

  { the split areas in their colours: the author's list, or the skin's
    colour and none in turn }
  procedure FillAreas(const AView: TTyPolarAxisView);
  var q: Integer;
  begin
    for q := 0 to High(AView.SplitAreas) do
    begin
      ink := AView.SplitAreas[q].ColourIndex;
      if Length(AView.Furn.SplitAreaInks) > 0 then
      begin
        if ink > High(AView.Furn.SplitAreaInks) then ink := 0;
        if not AView.Furn.SplitAreaInks[ink].Ok then Continue;
        areaColour := TTyColor(AView.Furn.SplitAreaInks[ink].Colour);
      end
      else if (ink <> 0) or not (tpBackground in areaS.Present) then
        Continue
      else
        areaColour := areaS.Background.Color;
      APainter.BeginPath;
      ArcPath(AView.SplitAreas[q]);
      APainter.FillPath(areaColour);
    end;
  end;

  { the split lines (or circles) in their colours }
  procedure SplitLinesOf(const AView: TTyPolarAxisView; ACircles: Boolean);
  var q: Integer;
  begin
    if not ((tpBorderColor in splitS.Present)
      or (Length(AView.Furn.SplitLineInks) > 0)) then Exit;
    for q := 0 to Math.Max(0, High(AView.Furn.SplitLineInks)) do
    begin
      inkStyle := splitS;
      if Length(AView.Furn.SplitLineInks) > 0 then
      begin
        if not AView.Furn.SplitLineInks[q].Ok then Continue;
        inkStyle.BorderColor := TTyColor(AView.Furn.SplitLineInks[q].Colour);
        Include(inkStyle.Present, tpBorderColor);
        if ACircles then StrokeArcs(AView.SplitCircles, inkStyle, q)
        else StrokeLines(AView.SplitLines, inkStyle, q);
      end
      else if ACircles then StrokeArcs(AView.SplitCircles, inkStyle, -1)
      else StrokeLines(AView.SplitLines, inkStyle, -1);
    end;
  end;

  procedure PaintArrow(const AArrow: TTyAxisArrow);
  var
    el: TTyChartElement;
    path: TTyZrPath;
    t: string;
  begin
    { [F6a] a picture }
    if TyAxisArrowImage(AArrow, el) then
    begin
      TyRenderElement(APainter, el);
      Exit;
    end;
    t := AArrow.SymbolType;
    path := TyZrSymbol(t, -AArrow.W / 2, -AArrow.H / 2, AArrow.W, AArrow.H);
    if Length(path) = 0 then Exit;
    el := Default(TTyChartElement);
    el.Style.Alpha := 1;
    el.Shape := TyMkZrShape(path, TyZrLocal(1, 1, AArrow.Rotation, AArrow.X,
      AArrow.Y), True);
    if Copy(t, 1, 5) = 'empty' then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(model.ResolveStyle(
        'TyAdvChartEmptyCircle', '', []).Background.Color);
      el.Style.StrokeColor := TTyChartColor(lineS.BorderColor);
      el.Style.StrokeWidthLogical := 2;
    end
    else if t = 'line' then
    begin
      el.Style.StrokeColor := TTyChartColor(lineS.BorderColor);
      el.Style.StrokeWidthLogical := 1;
    end
    else
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(lineS.BorderColor);
    end;
    TyRenderElement(APainter, el);
  end;

  procedure PaintRadius(const AView: TTyPolarAxisView);
  var
    q: Integer;
    sp: TTyAxisLayoutSpec;
    pl: TTyAxisNamePlacement;
  begin
    sp := AView.Spec;
    if AView.HasLine and (tpBorderColor in lineS.Present) then
    begin
      APainter.BeginPath;
      APainter.MoveTo(AView.Line.X1, AView.Line.Y1);
      APainter.LineTo(AView.Line.X2, AView.Line.Y2);
      APainter.StrokePath(lineS.BorderColor, LineWidth(lineS));
      for q := 0 to High(sp.Arrows) do PaintArrow(sp.Arrows[q]);
    end;
    StrokeLines(AView.Ticks, tickS, -1);
    StrokeLines(AView.MinorTicks, minorTickS, -1);
    AxisTextStyles(@sp, labelS, nameS);
    pl := sp.NamePlacement;
    if pl.Shown and (tpTextColor in nameS.Present) then
    begin
      if Length(pl.Rt) > 0 then
        TyRenderRtPieces(APainter, pl.Rt, pl.X, pl.Y, pl.RotationRad, sp.RtScale,
          1, True, nameS.TextColor)
      else if Abs(pl.RotationRad) < 1e-9 then
      begin
        TextSizeOf(pl.Text, nameS, lblW, lblH);
        APainter.DrawText(AnchorBox(pl.X, pl.Y, lblW, lblH, pl.AnchorH, pl.AnchorV),
          pl.Text, nameS.FontName, ResolveFontSize(nameS), nameS.FontWeight,
          nameS.TextColor, taCenter, tlCenter, False, 0, False, Pos(#10, pl.Text) > 0);
      end
      else
      begin
        TextSizeOf(pl.Text, nameS, lblW, lblH);
        DrawRotatedNameLines(APainter, pl.Text, nameS.FontName, ResolveFontSize(nameS),
          nameS.FontWeight, nameS.TextColor, pl.X, pl.Y, pl.RotationRad,
          AnchorAlign(pl.AnchorH), AnchorLayout(pl.AnchorV), lblH);
      end;
    end;
    if not (tpTextColor in labelS.Present) then Exit;
    for q := 0 to High(sp.Placements) do
    begin
      if not sp.Placements[q].Shown or (sp.Placements[q].Text = '') then Continue;
      if Length(sp.Placements[q].Rt) > 0 then
      begin
        TyRenderRtPieces(APainter, sp.Placements[q].Rt, sp.Placements[q].X,
          sp.Placements[q].Y, sp.RotationRad, sp.RtScale, 1, True, labelS.TextColor);
        Continue;
      end;
      if sp.RotationRad <> 0 then
      begin
        { every line of a label of several [R2-A] }
        TextSizeOf(sp.Placements[q].Text, labelS, lblW, lblH);
        DrawRotatedNameLines(APainter, sp.Placements[q].Text, labelS.FontName,
          ResolveFontSize(labelS), labelS.FontWeight, labelS.TextColor,
          sp.Placements[q].X, sp.Placements[q].Y, sp.RotationRad,
          AnchorAlign(sp.Placements[q].AnchorH), AnchorLayout(sp.Placements[q].AnchorV),
          lblH);
        Continue;
      end;
      TextSizeOf(sp.Placements[q].Text, labelS, lblW, lblH);
      APainter.DrawText(AnchorBox(sp.Placements[q].X, sp.Placements[q].Y, lblW,
        lblH, sp.Placements[q].AnchorH, sp.Placements[q].AnchorV),
        sp.Placements[q].Text, labelS.FontName, ResolveFontSize(labelS),
        labelS.FontWeight, labelS.TextColor, taCenter, tlCenter, False, 0, False,
        Pos(#10, sp.Placements[q].Text) > 0);
    end;
  end;

  procedure PaintAngle(const AView: TTyPolarAxisView);
  var
    q: Integer;
    sp: TTyAxisLayoutSpec;
  begin
    sp := AView.Spec;
    if AView.HasLine and (tpBorderColor in lineS.Present) then
    begin
      APainter.BeginPath;
      ArcPath(AView.LineArc);
      APainter.StrokePath(lineS.BorderColor, LineWidth(lineS));
    end;
    StrokeLines(AView.Ticks, tickS, -1);
    StrokeLines(AView.MinorTicks, minorTickS, -1);
    AxisTextStyles(@sp, labelS, nameS);
    if not (tpTextColor in labelS.Present) then Exit;
    for q := 0 to High(AView.Labels) do
    begin
      if AView.Labels[q].Text = '' then Continue;
      if Length(AView.Labels[q].Rt) > 0 then
      begin
        TyRenderRtPieces(APainter, AView.Labels[q].Rt, AView.Labels[q].X,
          AView.Labels[q].Y, 0, sp.RtScale, 1, True, labelS.TextColor);
        Continue;
      end;
      TextSizeOf(AView.Labels[q].Text, labelS, lblW, lblH);
      APainter.DrawText(AnchorBox(AView.Labels[q].X, AView.Labels[q].Y, lblW,
        lblH, AView.Labels[q].AnchorH, AView.Labels[q].AnchorV),
        AView.Labels[q].Text, labelS.FontName, ResolveFontSize(labelS),
        labelS.FontWeight, labelS.TextColor, taCenter, tlCenter, False, 0, False,
        Pos(#10, AView.Labels[q].Text) > 0);
    end;
  end;

begin
  if Length(FPolars) = 0 then Exit;
  model := ActiveController.Model;
  lineS := model.ResolveStyle('TyAdvChartAxisLine', '', []);
  tickS := model.ResolveStyle('TyAdvChartAxisTick', '', []);
  splitS := model.ResolveStyle('TyAdvChartSplitLine', '', []);
  areaS := model.ResolveStyle('TyAdvChartSplitArea', '', []);
  minorTickS := model.ResolveStyle('TyAdvChartMinorTick', '', []);
  minorSplitS := model.ResolveStyle('TyAdvChartMinorSplitLine', '', []);
  for i := 0 to High(FPolars) do
  begin
    p := FPolars[i];
    if p = nil then Continue;
    for k := 0 to 1 do
    begin
      if k = 0 then view := cvAngleAxis else view := cvRadiusAxis;
      if ViewHidden(view) then Continue;
      if k = 0 then
      begin
        if not p.AngleView.Shown then Continue;
        ViewDrew(view);
        if ABelow then
        begin
          FillAreas(p.AngleView);
          StrokeLines(p.AngleView.MinorSplitLines, minorSplitS, -1);
          SplitLinesOf(p.AngleView, False);
        end
        else
          PaintAngle(p.AngleView);
      end
      else
      begin
        if not p.RadiusView.Shown then Continue;
        ViewDrew(view);
        if ABelow then
        begin
          FillAreas(p.RadiusView);
          StrokeArcs(p.RadiusView.MinorSplitCircles, minorSplitS, -1);
          SplitLinesOf(p.RadiusView, True);
        end
        else
          PaintRadius(p.RadiusView);
      end;
    end;
  end;
end;

function TTyAdvanceChart.PolarShadowBand(const AHit: TTyAxisHit): Double;
var
  ax, base: TTyAxis;
  k, s: Integer;
  t0, t1, px, span, gap, best, bw: Double;
  only: Boolean;
  ext: TTyRange;
begin
  ax := AHit.Axis;
  if (ax = nil) or (ax.Scale is TTyOrdinalScale) then Exit(TyPolarPointerBand(ax));
  ax.LocalExtent(t0, t1);
  px := Abs(t1 - t0);
  ext := ax.Scale.LinearExtent2(sekMapping);
  span := ext.Stop - ext.Start;
  best := NegInfinity;
  only := False;
  for k := 0 to High(AHit.Slots) do
  begin
    s := AHit.Slots[k];
    if (s < 0) or (s > High(FBindings)) then Continue;
    { on a polar only the bar keeps the statistic }
    if (FBindings[s].SeriesType <> 'bar') or (FBindings[s].Polar = nil) then Continue;
    base := FBindings[s].BaseAxis;
    if (base = nil) or (base.Scale is TTyOrdinalScale) then Continue;
    gap := TyLiPosMinGap(FStores,
      FIndex.SeriesOnAxisOfKey(base, TySeriesStatKey('bar', TyPolarCoordSysName)), base);
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
  if IsNan(bw) or IsInfinite(bw) then Result := 1
  else Result := Math.Max(Double(1), bw);
end;

function TTyAdvanceChart.PolarPointerGeometry(const AHit: TTyAxisHit;
  const ARect: TRect; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  out ADraw: TTyPolarPointerDraw): Boolean;
var
  pv, coord, margin, tw, th, padL, padT, padR, padB, x, y, vw, vh: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  labelS: TTyStyleSet;
  scale: Double;
begin
  ADraw := Default(TTyPolarPointerDraw);
  ADraw.Shape.Kind := plpkNone;
  Result := False;
  if (AHit.Polar = nil) or (AHit.Axis = nil) then Exit;
  Result := True;
  pv := PointerValue(AHit);
  { dataToCoord(value) -- no clamp: the value is one the axis contains }
  coord := AHit.Axis.DataToCoord(pv);
  case AHit.Spec.PointerType of
    aptLine: ADraw.Shape := TyPolarPointerShape(AHit.Polar, AHit.Axis, coord,
      TyPolarPointerBand(AHit.Axis), False);
    aptShadow: ADraw.Shape := TyPolarPointerShape(AHit.Polar, AHit.Axis, coord,
      PolarShadowBand(AHit), True);
  end;
  if not AHit.Spec.LabelSpec.Show or (AMeasurer = nil) then Exit;
  ADraw.Text := PointerLabelText(AHit, pv);
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerLabel', '', []);
  AMeasurer.MeasureLine(ADraw.Text, labelS.FontName, ResolveFontSize(labelS),
    labelS.FontWeight, tw, th);
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  if AHit.Spec.LabelSpec.HasPadding then
  begin
    padL := AHit.Spec.LabelSpec.PadLeft * scale;
    padT := AHit.Spec.LabelSpec.PadTop * scale;
    padR := AHit.Spec.LabelSpec.PadRight * scale;
    padB := AHit.Spec.LabelSpec.PadBottom * scale;
  end
  else
  begin
    padL := labelS.Padding.Left * scale;
    padT := labelS.Padding.Top * scale;
    padR := labelS.Padding.Right * scale;
    padB := labelS.Padding.Bottom * scale;
  end;
  margin := ActiveController.Metric(TyAdvChartAxisPointerMarginVar,
    TyAdvChartAxisPointerMargin);
  if AHit.Spec.LabelSpec.MarginLogical <> 3 then
    margin := AHit.Spec.LabelSpec.MarginLogical;
  margin := margin * scale;
  { getLabelPosition, then buildLabelElOption's align and confineInContainer }
  TyPolarPointerLabelAnchor(AHit.Polar, AHit.Axis, coord, margin,
    AHit.Polar.RadiusView.Furn.LabelRotateDeg * Pi / 180, x, y, ah, av);
  ADraw.W := tw + padR + padL;
  ADraw.H := th + padT + padB;
  if ah = tahRight then x := x - ADraw.W;
  if ah = tahCentre then x := x - ADraw.W / 2;
  if av = tavBottom then y := y - ADraw.H;
  if av = tavMiddle then y := y - ADraw.H / 2;
  vw := ARect.Right - ARect.Left;
  vh := ARect.Bottom - ARect.Top;
  x := Math.Min(x + ADraw.W, vw) - ADraw.W;
  y := Math.Min(y + ADraw.H, vh) - ADraw.H;
  x := Math.Max(x, Double(0));
  y := Math.Max(y, Double(0));
  ADraw.X := x;
  ADraw.Y := y;
  ADraw.HasLabel := True;
end;

procedure TTyAdvanceChart.PaintPolarPointer(APainter: TTyPainter;
  const ARect: TRect; APPI: Integer; const AMeasurer: ITyTextMeasurer;
  const AHit: TTyAxisHit);
var
  d: TTyPolarPointerDraw;
  lineS, shadowS, labelS: TTyStyleSet;
  colour: TTyColor;
  w: Double;
  dash: TTyDoubleArray;
  box: TRect;
  corners: TTyCorners;
  surface: TTyFill;
  s: TTyPolarPointerShape;
begin
  if not PolarPointerGeometry(AHit, ARect, AMeasurer, APPI, d) then Exit;
  lineS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointer', '', []);
  shadowS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerShadow', '', []);
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisPointerLabel', '', []);
  s := d.Shape;
  case s.Kind of
    plpkLine, plpkCircle:
      if tpBorderColor in lineS.Present then
      begin
        colour := lineS.BorderColor;
        if AHit.Spec.HasLineColour then colour := TTyColor(AHit.Spec.LineColour);
        w := lineS.BorderWidth;
        if AHit.Spec.HasLineWidth then w := AHit.Spec.LineWidthLogical;
        if w > 0 then
        begin
          dash := TyDashPattern(AHit.Spec.LineDash, AHit.Spec.LineDashExplicit, w);
          APainter.SetLineDash(dash);
          APainter.BeginPath;
          if s.Kind = plpkLine then
          begin
            APainter.MoveTo(s.X1, s.Y1);
            APainter.LineTo(s.X2, s.Y2);
          end
          else
          begin
            APainter.MoveTo(s.CX + s.R, s.CY);
            APainter.ArcTo(s.CX, s.CY, Math.Max(s.R, 0), 0, 2 * Pi, False);
          end;
          APainter.StrokePath(colour, w);
          APainter.SetLineDash([]);
        end;
      end;
    plpkSector:
      if tpBackground in shadowS.Present then
      begin
        colour := shadowS.Background.Color;
        if AHit.Spec.HasShadowColour then colour := TTyColor(AHit.Spec.ShadowColour);
        APainter.BeginPath;
        if Abs(s.EndAngle - s.StartAngle) > 2 * Pi - 1e-4 then
        begin
          APainter.MoveTo(s.CX + s.R, s.CY);
          APainter.ArcTo(s.CX, s.CY, Math.Max(s.R, 0), 0, 2 * Pi, False);
          if s.R0 > 1e-4 then
          begin
            APainter.MoveTo(s.CX + s.R0, s.CY);
            APainter.ArcTo(s.CX, s.CY, s.R0, 2 * Pi, 0, True);
          end;
        end
        else
        begin
          APainter.MoveTo(s.CX + s.R * TyJsCos(s.StartAngle),
            s.CY + s.R * TyJsSin(s.StartAngle));
          APainter.ArcTo(s.CX, s.CY, Math.Max(s.R, 0), s.StartAngle, s.EndAngle, False);
          if s.R0 > 1e-4 then
          begin
            APainter.LineTo(s.CX + s.R0 * TyJsCos(s.EndAngle),
              s.CY + s.R0 * TyJsSin(s.EndAngle));
            APainter.ArcTo(s.CX, s.CY, s.R0, s.EndAngle, s.StartAngle, True);
          end
          else
            APainter.LineTo(s.CX, s.CY);
          APainter.ClosePath;
        end;
        APainter.FillPath(colour);
      end;
  end;
  if not d.HasLabel or (d.Text = '') then Exit;
  if not (tpBackground in labelS.Present) then Exit;
  box := Rect(Round(d.X), Round(d.Y), Round(d.X + d.W), Round(d.Y + d.H));
  corners := TyEffectiveCorners(labelS);
  if AHit.Spec.LabelSpec.HasBorderRadius then
    corners := TyCorners(Round(AHit.Spec.LabelSpec.BorderRadiusLogical),
      Round(AHit.Spec.LabelSpec.BorderRadiusLogical),
      Round(AHit.Spec.LabelSpec.BorderRadiusLogical),
      Round(AHit.Spec.LabelSpec.BorderRadiusLogical));
  surface := labelS.Background;
  if AHit.Spec.LabelSpec.HasBackground then
  begin
    surface.Kind := tfkSolid;
    surface.Color := TTyColor(AHit.Spec.LabelSpec.Background);
  end;
  APainter.FillBackground(box, surface, corners);
  if AHit.Spec.LabelSpec.HasBorderColour and AHit.Spec.LabelSpec.HasBorderWidth
    and (AHit.Spec.LabelSpec.BorderWidthLogical > 0) then
    APainter.StrokeBorder(box, corners,
      Round(AHit.Spec.LabelSpec.BorderWidthLogical),
      TTyColor(AHit.Spec.LabelSpec.BorderColour))
  else if TyBorderVisible(labelS) then
    APainter.StrokeBorder(box, corners, labelS.BorderWidth, labelS.BorderColor);
  colour := labelS.TextColor;
  if AHit.Spec.LabelSpec.HasColour then colour := TTyColor(AHit.Spec.LabelSpec.Colour);
  APainter.DrawText(box, d.Text, labelS.FontName, ResolveFontSize(labelS),
    labelS.FontWeight, colour, taCenter, tlCenter, False);
end;

{ ==================== the lines series [Batch 121, C12] ====================

  LinesSeries, linesLayout, linesVisual and LinesView: the rows (any of the
  data forms), laid out through the coordinate hook on a cartesian, a polar
  or a calendar, their look (the visual style's per-key fallthrough from the
  row's lineStyle to the series', the end symbols linesVisual pairs up, the
  label Line.beforeUpdate places, the effect symbol EffectLine moves), the
  view group's clip, and -- large and over its threshold -- the one batch
  LargeLineDraw draws. The pure part is AdvChart.Lines. }

{ a colour written as a string, parsed }
function LnColour(AData: TJSONData; out AColor: TTyChartColor): Boolean;
begin
  Result := False;
  AColor := 0;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  Result := TyTryParseChartColor(AData.AsString, AColor);
end;

{ lineStyle.type as the dash enum }
procedure LnDashOf(AData: TJSONData; out ADash: TTyOptDash; out AExplicit: TTyDoubleArray);
var i: Integer;
begin
  ADash := todNone;
  AExplicit := nil;
  if AData = nil then Exit;
  if AData.JSONType = jtString then
  begin
    if AData.AsString = 'dashed' then ADash := todDashed
    else if AData.AsString = 'dotted' then ADash := todDotted
    else if AData.AsString = 'solid' then ADash := todSolid;
  end
  else if AData.JSONType = jtNumber then
  begin
    ADash := todExplicit;
    SetLength(AExplicit, 1);
    AExplicit[0] := AData.AsFloat;
  end
  else if AData is TJSONArray then
  begin
    ADash := todExplicit;
    SetLength(AExplicit, AData.Count);
    for i := 0 to AData.Count - 1 do AExplicit[i] := TyLinesJsNum(TJSONArray(AData).Items[i]);
  end;
end;

{ a symbol size as written: a number, or the first two of an array }
procedure LnSize(AData: TJSONData; AScale: Double; out AW, AH: Double);
begin
  AW := NaN;
  AH := NaN;
  if AData = nil then Exit;
  if AData is TJSONArray then
  begin
    if AData.Count > 0 then AW := TyLinesJsNum(TJSONArray(AData).Items[0]);
    if AData.Count > 1 then AH := TyLinesJsNum(TJSONArray(AData).Items[1]) else AH := AW;
  end
  else
  begin
    AW := TyLinesJsNum(AData);
    AH := AW;
  end;
  AW := AW * AScale;
  AH := AH * AScale;
end;

function TTyAdvanceChart.LinesProject(const AX, AY: TTyLinesValue;
  AClamp: Boolean): TTyPointF;
var
  b: TTySeriesBinding;
  pol: TTyPolar;
  cal: TTyCalendar;
  dv: TTyDataValue;

  { scale.parse of one written value on an axis (TyAxisParseJson's rules) }
  function Parse(AAxis: TTyAxis; const AV: TTyLinesValue): Double;
  var ord: Integer; ms: Double;
  begin
    Result := NaN;
    if AAxis = nil then Exit;
    if AV.Kind in [lvkNull, lvkOther] then Exit;
    case AAxis.AxisType of
      atCategory:
        if AV.Kind = lvkString then
        begin
          if AAxis.Categories = nil then Exit;
          ord := AAxis.Categories.GetOrdinal(AV.Str);
          if ord >= 0 then Result := ord;
        end
        else
          Result := TyJsRound(AV.Num);
      atTime:
        if AV.Kind = lvkString then
        begin
          if TyParseDateMs(AV.Str, ms, False) then Result := ms;
        end
        else
          Result := TyJsRound(AV.Num);
    else
      if AV.Kind = lvkString then
      begin
        if AV.Str = '' then Exit;
        Result := TyJsToNumber(AV.Str);
      end
      else
        Result := AV.Num;
    end;
  end;

begin
  Result := TyPointF(NaN, NaN);
  if (FLnSlot < 0) or (FLnSlot > High(FBindings)) then Exit;
  b := FBindings[FLnSlot];
  if b.Polar is TTyPolar then
  begin
    pol := TTyPolar(b.Polar);
    Exit(pol.DataToPoint([Parse(pol.RadiusAxis, AX), Parse(pol.AngleAxis, AY)]));
  end;
  if (b.CalendarIndex >= 0) and (b.CalendarIndex <= High(FCalendars)) then
  begin
    { Calendar.dataToPoint(coords): the date of the pair's first value, no
      range check unless asked }
    cal := FCalendars[b.CalendarIndex];
    case AX.Kind of
      lvkNumber: dv := TyDataNum(AX.Num);
      lvkString: dv := TyDataText(AX.Str);
    else
      dv := TyDataNone;
    end;
    Exit(cal.DatePoint(cal.ParseDate(dv), AClamp));
  end;
  if b.Cart <> nil then
    Result := b.Cart.DataToPoint([Parse(b.XAxis, AX), Parse(b.YAxis, AY)])
  { A GEO [Batch 152]: dataToPoint of the pair -- applyTransform's
    arithmetic turns a string into a number and a null into 0 }
  else if b.GeoIndex >= 0 then
    Result := GeoLinesPoint(AX, AY);
end;

function TTyAdvanceChart.LinesTrailAlpha(ASeriesIndex: Integer): Double;
var slot: Integer;
begin
  Result := 0;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FLines)) or not FLines[slot].Valid then Exit;
  Result := FLines[slot].TrailAlpha;
end;

function TTyAdvanceChart.LinesSolvedOf(ASeriesIndex: Integer): TTyLinesSolved;
var slot: Integer;
begin
  Result := Default(TTyLinesSolved);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FLines)) then Exit;
  Result := FLines[slot];
end;

function TTyAdvanceChart.LinesInk(ASlot: Integer; ANode: TJSONObject;
  const ASolved: TTyLinesSolved; ARow: Integer; AStroke: TTyChartColor;
  AScale: Double; out ASpec: TTyLabelSpec): TTyLinesInk;
var
  raw: TTyLinesRaw;
  d, own, fmt: TJSONData;
  c: TTyChartColor;
  dash: TTyOptDash;
  expl: TTyDoubleArray;
  e, cnt: Integer;
  w, h, speed, len, v: Double;
  word: string;
  has, isNum: Boolean;
  vars: array of TTyStringArray;
  prm: TTyChartCallbackParams;
  eff: TTyLinesEffect;
  sizes, syms: TJSONData;

  function Pair(AData: TJSONData; AIndex: Integer): TJSONData;
  begin
    if AData is TJSONArray then
    begin
      if AIndex < AData.Count then Result := TJSONArray(AData).Items[AIndex]
      else Result := nil;
    end
    else
      Result := AData;
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
  end;

  function SymName(AData: TJSONData): string;
  begin
    Result := '';
    if (AData <> nil) and (AData.JSONType = jtString) then Result := AData.AsString;
  end;

begin
  Result := Default(TTyLinesInk);
  raw := ASolved.Raws[ARow];
  { THE STYLE: each key the row's lineStyle, else the series', else the
    default (opacity 0.5, width 1); the colour the series' visual }
  Result.Stroke := AStroke;
  if LnColour(TyLinesItemFind(raw, ['lineStyle', 'color']), c) then Result.Stroke := c;
  d := TyLinesFind(raw, ANode, ['lineStyle', 'width']);
  if d = nil then Result.Width := 1 else Result.Width := TyLinesJsNum(d);
  d := TyLinesFind(raw, ANode, ['lineStyle', 'opacity']);
  if d = nil then Result.Opacity := 0.5 else Result.Opacity := TyLinesJsNum(d);
  LnDashOf(TyLinesFind(raw, ANode, ['lineStyle', 'type']), dash, expl);
  Result.Dash := TyDashPattern(dash, expl, Result.Width);
  { THE END SYMBOLS (linesVisual): the series' pair, the row's own where it
    is truthy -- a size of 0 keeps the series' }
  syms := LnNode(ANode, ['symbol']);
  sizes := LnNode(ANode, ['symbolSize']);
  for e := 0 to 1 do
  begin
    if syms = nil then Result.Sym[e].Name := 'none'
    else Result.Sym[e].Name := SymName(Pair(syms, e));
    if sizes = nil then
    begin
      Result.Sym[e].W := 10 * AScale;
      Result.Sym[e].H := 10 * AScale;
    end
    else
      LnSize(Pair(sizes, e), AScale, Result.Sym[e].W, Result.Sym[e].H);
    d := Pair(TyLinesItemFind(raw, ['symbol']), e);
    if (raw.Item <> nil) and (d <> nil) and TyLinesJsTruthy(d) then
      Result.Sym[e].Name := SymName(d);
    d := Pair(TyLinesItemFind(raw, ['symbolSize']), e);
    if (raw.Item <> nil) and (d <> nil) and TyLinesJsTruthy(d) then
      LnSize(d, AScale, Result.Sym[e].W, Result.Sym[e].H);
  end;
  { THE LABEL: the series' spec under the row's own label; placed by the
    line, `position || 'middle'` over the series' default 'end' }
  ASpec := LabelSpecFor(ASlot);
  own := TyLinesItemFind(raw, ['label']);
  if own is TJSONObject then ASpec := TyLabelSpecOfNode(TJSONObject(own), ANode, ASpec);
  ASpec.Position := tlpInside;
  ASpec.OffsetXLogical := 0;
  ASpec.OffsetYLogical := 0;
  ASpec.Overflow := tloNone;
  { an outside label inherits the line's colour (setLabelStyle's
    inheritColor) unless it wrote one }
  if ASpec.AutoColour then ASpec.InheritColour := True;
  Result.LabelShow := ASpec.Show;
  Result.LabelSpec := ARow + 1;
  d := TyLinesFind(raw, ANode, ['label', 'position']);
  if (d <> nil) and (d.JSONType = jtString) then word := d.AsString else word := 'end';
  Result.LabelPos := TyLinesLabelPosOf(word);
  { `distance`, one for both or a pair; none is nought (null * scale) }
  Result.DistX := 0;
  Result.DistY := 0;
  d := TyLinesFind(raw, ANode, ['label', 'distance']);
  if d is TJSONArray then
  begin
    Result.DistX := NaN;
    Result.DistY := NaN;
    if d.Count > 0 then Result.DistX := TyLinesJsNum(TJSONArray(d).Items[0]);
    if d.Count > 1 then Result.DistY := TyLinesJsNum(TJSONArray(d).Items[1]);
  end
  else if d <> nil then
  begin
    Result.DistX := TyLinesJsNum(d);
    Result.DistY := Result.DistX;
  end;
  Result.DistX := Result.DistX * AScale;
  Result.DistY := Result.DistY * AScale;
  if ASpec.HasAlignH then
  begin
    Result.AlignFlags := Result.AlignFlags or 1;
    Result.AlignH := ASpec.AlignH;
  end;
  if ASpec.HasAlignV then
  begin
    Result.AlignFlags := Result.AlignFlags or 2;
    Result.AlignV := ASpec.AlignV;
  end;
  { THE WORDS: the formatter over the row (a the series, b the name, c the
    raw value), else Line.ts' default -- the name when the raw value is
    undefined, the value rounded to 10 places when it is finite, else the
    value as text }
  fmt := TyLinesFind(raw, ANode, ['label', 'formatter']);
  if (fmt <> nil) and (fmt.JSONType = jtString) and TyChartIsHandlerRef(fmt.AsString) then
  begin
    prm := TyChartBlankParams;
    prm.ComponentType := 'series';
    prm.SeriesType := TyLinesSeriesTypeName;
    prm.SeriesIndex := ASolved.SeriesIndex;
    prm.SeriesName := SeriesModelName(ASolved.SeriesIndex);
    prm.DataIndex := ARow;
    prm.RawDataIndex := ARow;
    prm.Name := raw.Name;
    SetLength(prm.Values, 1);
    prm.Values[0] := raw.Value;
    Result.LabelText := TyChartRunHandler(fmt.AsString, TyChartOneParams(prm));
  end
  else if (fmt <> nil) and (fmt.JSONType = jtString) then
  begin
    vars := nil;
    SetLength(vars, 1);
    SetLength(vars[0], 3);
    vars[0][0] := SeriesModelName(ASolved.SeriesIndex);
    vars[0][1] := raw.Name;
    if raw.RawIsFlat then vars[0][2] := '0'
    else if raw.RawNone then vars[0][2] := 'undefined'
    else vars[0][2] := TyGraphJsText(raw.RawJson);
    Result.LabelText := TyJsFormatTpl(fmt.AsString, 3, vars);
  end
  else
  begin
    has := raw.RawIsFlat or ((not raw.RawNone) and (raw.RawJson <> nil));
    isNum := raw.RawIsFlat;
    v := 0;
    word := '0';
    if (not raw.RawIsFlat) and has then
    begin
      v := TyLinesJsNum(raw.RawJson);
      isNum := (raw.RawJson.JSONType <> jtObject)
        and not ((raw.RawJson is TJSONArray) and (raw.RawJson.Count > 1));
      word := TyGraphJsText(raw.RawJson);
    end;
    Result.LabelText := TyGraphEdgeDefaultText(has, isNum, v, word, raw.Name);
  end;
  { THE EFFECT (EffectLine): the row's effect over the series', over the
    defaults -- a circle of 3, period 4 s, loop -- and the period from the
    length at constantSpeed; the delay as written, else idx / count *
    period / 3 with that period }
  if not ASolved.Effect then Exit;
  d := TyLinesFind(raw, ANode, ['effect', 'symbol']);
  if (d <> nil) and (d.JSONType = jtString) then Result.EffName := d.AsString
  else Result.EffName := 'circle';
  d := TyLinesFind(raw, ANode, ['effect', 'symbolSize']);
  if d = nil then
  begin
    w := 3 * AScale;
    h := 3 * AScale;
  end
  else
    LnSize(d, AScale, w, h);
  Result.EffW := w;
  Result.EffH := h;
  Result.EffColor := Result.Stroke;
  if LnColour(TyLinesFind(raw, ANode, ['effect', 'color']), c) then Result.EffColor := c;
  d := TyLinesFind(raw, ANode, ['effect', 'opacity']);
  if d = nil then Result.EffOpacity := 1 else Result.EffOpacity := TyLinesJsNum(d);
  d := TyLinesFind(raw, ANode, ['effect', 'period']);
  if d = nil then Result.EffPeriod := 4 * 1000 else Result.EffPeriod := TyLinesJsNum(d) * 1000;
  d := TyLinesFind(raw, ANode, ['effect', 'loop']);
  Result.EffLoop := (d = nil) or TyLinesJsTruthy(d);
  Result.EffRoundTrip := TyLinesJsTruthy(TyLinesFind(raw, ANode, ['effect', 'roundTrip']));
  d := TyLinesFind(raw, ANode, ['effect', 'constantSpeed']);
  if d = nil then speed := 0 else speed := TyLinesJsNum(d);
  if speed > 0 then
  begin
    TyLinesEffectInit(eff, ASolved.Geoms[ARow], ASolved.Poly, Result.EffName, w, h);
    len := TyLinesEffectLength(eff);
    Result.EffPeriod := len / (speed * AScale) * 1000;
  end;
  cnt := Length(ASolved.Raws);
  d := TyLinesFind(raw, ANode, ['effect', 'delay']);
  if d <> nil then Result.EffDelay := TyLinesJsNum(d)
  else Result.EffDelay := ARow / cnt * Result.EffPeriod / 3;
end;

procedure TTyAdvanceChart.SolveLines(APPI: Integer);
var
  i, k, si, n: Integer;
  node: TJSONObject;
  d: TJSONData;
  sol: TTyLinesSolved;
  stroke, c: TTyChartColor;
  scale, lw, x, y, cw, ch, e0, e1, trail: Double;
  area: TTyXYWH;
  pol: TTyPolar;
  clipOn: Boolean;
  dash: TTyOptDash;
  expl: TTyDoubleArray;
  spec: TTyLabelSpec;
begin
  FLines := nil;
  FLinesSpecs := nil;
  SetLength(FLines, Length(FBindings));
  SetLength(FLinesSpecs, Length(FBindings));
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  for i := 0 to High(FBindings) do
  begin
    FLines[i] := Default(TTyLinesSolved);
    if FBindings[i].SeriesType <> TyLinesSeriesTypeName then Continue;
    if (not FBindings[i].Resolved) or FBindings[i].Hidden then Continue;
    if (FBindings[i].Cart = nil) and not (FBindings[i].Polar is TTyPolar)
      and ((FBindings[i].CalendarIndex < 0)
        or (FBindings[i].CalendarIndex > High(FCalendars)))
      { a geo's lines [Batch 152]: no clip (createClipPath has none) }
      and (GeoOfSlot(i) = nil) then Continue;
    si := FBindings[i].SeriesIndex;
    d := FOption.ComponentAt('series', si);
    if not (d is TJSONObject) then Continue;
    node := TJSONObject(d);
    sol := Default(TTyLinesSolved);
    sol.Valid := True;
    sol.SeriesIndex := si;
    sol.Raws := TyLinesRawsOf(node);
    sol.Poly := TyLinesJsTruthy(LnNode(node, ['polyline']));
    sol.Effect := TyLinesJsTruthy(LnNode(node, ['effect', 'show']));
    sol.Z := SeriesIntIn(si, 'z', 2);
    sol.Z2 := 0;
    { THE TRAIL: a canvas zlevel with motion blur at lastFrameAlpha }
    d := LnNode(node, ['effect', 'trailLength']);
    if d = nil then trail := 0.2 else trail := TyLinesJsNum(d);
    if sol.Effect and (trail > 0) then sol.TrailAlpha := TyLinesTrailAlpha(trail);
    { the series' visual colour: lineStyle.color, else the palette's }
    stroke := TTyChartColor(SeriesColor(si));
    if LnColour(LnNode(node, ['lineStyle', 'color']), c) then stroke := c;
    { THE CLIP: createGridClipPath widened by the series' lineStyle.width
      (or nothing), createPolarClipPath; none on a calendar }
    d := LnNode(node, ['clip']);
    clipOn := (d = nil) or TyLinesJsTruthy(d);
    if clipOn and (FBindings[i].Polar is TTyPolar) then
    begin
      pol := TTyPolar(FBindings[i].Polar);
      sol.HasClipSector := True;
      pol.AxisExtent(pol.RadiusAxis, e0, e1);
      sol.ClipCX := TyJsToFixed(pol.CX, 1);
      sol.ClipCY := TyJsToFixed(pol.CY, 1);
      sol.ClipR0 := TyJsToFixed(Min(e0, e1), 1);
      sol.ClipR1 := TyJsToFixed(Max(e0, e1), 1);
      pol.AxisExtent(pol.AngleAxis, e0, e1);
      sol.ClipSA := -e0 * (Pi / 180);
      sol.ClipEA := -e1 * (Pi / 180);
      sol.ClipCW := pol.AngleInverse;
    end
    else if clipOn and (FBindings[i].Cart <> nil) then
    begin
      area := FBindings[i].Cart.GetArea;
      lw := TyLinesJsNum(LnNode(node, ['lineStyle', 'width']));
      if IsNan(lw) or (lw = 0) then lw := 0;
      lw := lw * scale;
      x := area.X - lw / 2;
      y := area.Y - lw / 2;
      cw := area.W + lw;
      ch := area.H + lw;
      cw := Ceil(cw);
      if x <> Floor(x) then
      begin
        x := Floor(x);
        cw := cw + 1;
      end;
      sol.HasClip := True;
      sol.Clip := TyRectF(x, y, x + cw, y + ch);
    end;
    FLnSlot := i;
    n := Length(sol.Raws);
    { LARGE: the segs through the hook, the series' style, no per-row look }
    if LargeKindOf(i) = lgkLines then
    begin
      sol.IsLarge := True;
      sol.Large := Default(TTyLargeGeom);
      sol.Large.Kind := lgkLines;
      sol.Large.Pts := TyLinesLargeSegs(sol.Raws, sol.Poly, @LinesProject);
      sol.Large.LinesPoly := sol.Poly;
      sol.Large.LinesCurve := TyLinesJsNum(LnNode(node, ['lineStyle', 'curveness']));
      if IsNan(sol.Large.LinesCurve) then sol.Large.LinesCurve := 0;
      d := LnNode(node, ['lineStyle', 'width']);
      if d = nil then sol.LargeWidth := 1 else sol.LargeWidth := TyLinesJsNum(d);
      sol.Large.LineW := sol.LargeWidth * scale;
      TyLargeLinesIndex(sol.Large);
      TyLargeSetBox(sol.Large);
      if sol.HasClip then
      begin
        sol.Large.ClipOn := True;
        sol.Large.Clip := TyXYWH(sol.Clip.Left, sol.Clip.Top,
          sol.Clip.Right - sol.Clip.Left, sol.Clip.Bottom - sol.Clip.Top);
      end;
      sol.LargeStroke := stroke;
      d := LnNode(node, ['lineStyle', 'opacity']);
      if d = nil then sol.LargeOpacity := 0.5 else sol.LargeOpacity := TyLinesJsNum(d);
      LnDashOf(LnNode(node, ['lineStyle', 'type']), dash, expl);
      sol.LargeDash := TyDashPattern(dash, expl, sol.LargeWidth);
      FLines[i] := sol;
      Continue;
    end;
    SetLength(sol.Geoms, n);
    SetLength(sol.Inks, n);
    SetLength(FLinesSpecs[i], n);
    for k := 0 to n - 1 do
      sol.Geoms[k] := TyLinesLayoutRow(sol.Raws[k], k, sol.Poly,
        TyLinesCurvenessOf(sol.Raws[k], node), @LinesProject);
    for k := 0 to n - 1 do
    begin
      sol.Inks[k] := LinesInk(i, node, sol, k, stroke, scale, spec);
      FLinesSpecs[i][k] := spec;
    end;
    FLines[i] := sol;
  end;
  FLnSlot := -1;
end;

{ ==================== the parallels [Batch 128] ==================== }

procedure TTyAdvanceChart.FreeParallels;
var i: Integer;
begin
  for i := 0 to High(FParallels) do
    FParallels[i].Free;
  FParallels := nil;
end;

function TTyAdvanceChart.ParallelCount: Integer;
begin
  Result := Length(FParallels);
end;

function TTyAdvanceChart.ParallelLayout(AIndex: Integer): TTyParallel;
begin
  if (AIndex < 0) or (AIndex > High(FParallels)) then Exit(nil);
  Result := FParallels[AIndex];
end;

function TTyAdvanceChart.ParallelSolvedOf(ASeriesIndex: Integer): TTyParallelSolved;
var slot: Integer;
begin
  Result := Default(TTyParallelSolved);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FParSolved)) then Exit;
  Result := FParSolved[slot];
end;

function TTyAdvanceChart.ParallelIntervals(AAxisIndex: Integer): TTyParallelIntervalArray;
begin
  Result := nil;
  if (AAxisIndex >= 0) and (AAxisIndex <= High(FParIntervals)) then
    Result := Copy(FParIntervals[AAxisIndex]);
end;

function TTyAdvanceChart.ParallelOfAxis(AComponent: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to High(FParallels) do
    if (FParallels[i] <> nil) and (FParallels[i].AxisOfComponent(AComponent) >= 0) then
      Exit(i);
end;

{ createSeriesData for a parallel series: its own `data`, a column per row
  element up to the widest of the data and the highest 'dimN' (the data's
  dimensions, named and typed as upstream's schema names them); the label
  and the tooltip read the LAST coordinate a label suits -- not a category,
  not a time (summarizeDimensions' defaultedLabel, which is also its
  defaultedTooltip) -- or, with none, every element }
procedure TTyAdvanceChart.ParallelStore(ASlot: Integer; AStore: TTyDataStore);
var
  par: TTyParallel;
  node: TJSONObject;
  d: TJSONData;
  dims: TTySeriesDimArray;
  k, n, best: Integer;
  pos: TTyIntegerArray;
begin
  par := TTyParallel(FBindings[ASlot].Parallel);
  node := StSeriesNode(FBindings[ASlot].SeriesIndex);
  n := 0;
  d := nil;
  if node <> nil then d := node.Find('data');
  if d is TJSONArray then n := TySeriesDetectedDimCount(TJSONArray(d));
  dims := TyParallelSeriesDims(par, n);
  for k := 0 to High(dims) do
  begin
    AStore.AddDimension(dims[k].Name, dims[k].Kind);
    if dims[k].Axis <> nil then AStore.UseOrdinalMeta(k, dims[k].Axis.Categories);
  end;
  if Length(dims) > 0 then TyFillSeriesStore(FOption, ASlot, dims, AStore);
  best := -1;
  for k := 0 to High(dims) do
    if (Copy(dims[k].Name, 1, Length(TyParallelDimPrefix)) = TyParallelDimPrefix)
      and (dims[k].Kind = ddtFloat) then
      best := k;
  pos := nil;
  if best >= 0 then
  begin
    SetLength(pos, 1);
    pos[0] := best;
  end;
  AStore.SetTooltipPositions(pos);
  AStore.SetLabelPositions(pos);
end;

{ ParallelView and parallelVisual: each row's points (an empty value drops
  its point), its curve, its active state, and its style -- the series'
  colour (lineStyle.color or the palette's), a visualMap's (4000), an item's
  own lineStyle (4500); the width and the dash the same way; the opacity
  parallelVisual's (5000): lineStyle.opacity, or the item's own, while no
  axis is brushed, else activeOpacity / inactiveOpacity }
procedure TTyAdvanceChart.SolveParallels(APPI: Integer);
var
  i, a, r, raw, si: Integer;
  b: TTySeriesBinding;
  par: TTyParallel;
  st: TTyDataStore;
  node, item: TJSONObject;
  sol: TTyParallelSolved;
  row: TTyParallelRow;
  cols, poss: TTyIntegerArray;
  cats: array of Boolean;
  rawItem: TTyRawItem;
  cell: TTyDataValue;
  v, lsWidth, opN, opA, opI, w: Double;
  seen: TStringList;
  key: string;
  has, any, catHas: Boolean;
  base, c, ic: TTyChartColor;
  dash, idash: TTyOptDash;
  expl, iexpl: TTyDoubleArray;
  dashWord, iword: string;
  vrows: TTyVisualRowArray;
  d: TJSONData;
  mask: TFPUExceptionMask;

  function DashText(AData: TJSONData): string;
  begin
    if (AData = nil) or (AData.JSONType = jtNull) then Result := ''
    else if AData.JSONType = jtString then Result := AData.AsString
    else Result := AData.AsJSON;
  end;

begin
  FParSolved := nil;
  SetLength(FParSolved, Length(FBindings));
  seen := TStringList.Create;
  seen.CaseSensitive := True;
  { by bytes, as upstream keys a name: the locale compare took
    U+00C5 and U+212B for one letter, and whatever came after [P2] }
  seen.UseLocale := False;
  seen.Sorted := True;
  seen.Duplicates := dupIgnore;
  try
  for i := 0 to High(FBindings) do
  begin
    FParSolved[i] := Default(TTyParallelSolved);
    b := FBindings[i];
    if b.SeriesType <> TyParallelSeriesTypeName then Continue;
    { a view of a model still here, shown or not, has rendered }
    key := SeriesViewKey(b.SeriesIndex);
    if b.Resolved then seen.Add(key);
    if not b.Resolved or b.Hidden then Continue;
    if not (b.Parallel is TTyParallel) then Continue;
    if (i > High(FStores)) or (FStores[i] = nil) then Continue;
    par := TTyParallel(b.Parallel);
    st := FStores[i];
    si := b.SeriesIndex;
    node := StSeriesNode(si);
    sol := Default(TTyParallelSolved);
    sol.Valid := True;
    sol.SeriesIndex := si;
    sol.ParallelIndex := b.ParallelIndex;
    sol.Smooth := TyParallelSmoothOf(node);
    sol.Z := SeriesIntIn(si, 'z', 2);
    sol.Z2 := TyParallelLineZ2;
    sol.Horizontal := par.Horizontal;
    sol.Clip := par.Rect;
    { never an incremental view; the clip starts on the view's first
      render only }
    sol.EnterClip := not ProgOnOf(i);
    sol.NewView := (FParSeen = nil) or (FParSeen.IndexOf(key) < 0);
    SetLength(cols, par.AxisCount);
    SetLength(poss, par.AxisCount);
    SetLength(cats, par.AxisCount);
    for a := 0 to par.AxisCount - 1 do
    begin
      cols[a] := st.DimIndexOf(par.Dims[a]);
      poss[a] := par.DimNums[a];
      cats[a] := par.Axis(a).AxisType = atCategory;
    end;
    { the series' style }
    base := TTyChartColor(SeriesColor(si));
    d := LnNode(node, ['lineStyle', 'width']);
    if (d <> nil) and (d.JSONType = jtNumber) then lsWidth := d.AsFloat else lsWidth := 1;
    d := LnNode(node, ['lineStyle', 'type']);
    if d = nil then dashWord := 'solid' else dashWord := DashText(d);
    LnDashOf(d, dash, expl);
    if d = nil then dash := todSolid;
    d := LnNode(node, ['lineStyle', 'opacity']);
    if (d <> nil) and (d.JSONType = jtNumber) then opN := d.AsFloat else opN := 0.45;
    d := LnNode(node, ['activeOpacity']);
    if (d <> nil) and (d.JSONType = jtNumber) then opA := d.AsFloat else opA := 1;
    d := LnNode(node, ['inactiveOpacity']);
    if (d <> nil) and (d.JSONType = jtNumber) then opI := d.AsFloat else opI := 0.05;
    any := par.HasAxisBrushed;
    vrows := nil;
    if i <= High(FVisualRows) then vrows := FVisualRows[i];
    SetLength(sol.Rows, st.Count);
    mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
      exOverflow, exUnderflow, exPrecision]);
    try
      for r := 0 to st.Count - 1 do
      begin
        row := Default(TTyParallelRow);
        raw := st.GetRawIndex(r);
        row.Row := r;
        row.Raw := raw;
        rawItem := st.RawItem(r);
        if any then row.Active := ppaActive else row.Active := ppaNormal;
        for a := 0 to par.AxisCount - 1 do
        begin
          if cols[a] >= 0 then v := st.Get(cols[a], r) else v := NaN;
          { createLinePoints' isEmptyValue: a category value is empty when it
            is null, any other when it is null or not a number }
          catHas := TTyDataStore.RawCell(rawItem, poss[a], cell)
            and (cell.Kind <> dvkNone);
          if cats[a] then has := catHas else has := not IsNan(v);
          if has then
          begin
            SetLength(row.Pts, Length(row.Pts) + 1);
            row.Pts[High(row.Pts)] := par.DataToPoint(v, a);
          end;
          { eachActiveState: the first axis that rejects the value }
          if any and (row.Active = ppaActive) then
            if par.AxisActiveState(a, v, (not cats[a]) or catHas) = ppaInactive then
              row.Active := ppaInactive;
        end;
        { buildPath's `if (smooth)` }
        if (sol.Smooth <> 0) and not IsNan(sol.Smooth) and (Length(row.Pts) >= 2) then
          row.Cmds := TyParallelSmoothCmds(row.Pts, sol.Smooth);
        { the style: series, visualMap, the item's own }
        c := base;
        if (raw >= 0) and (raw <= High(vrows)) and vrows[raw].ColorSet then
          c := TyVisualToChart(vrows[raw].Color);
        w := lsWidth;
        iword := dashWord;
        idash := dash;
        iexpl := expl;
        row.Opacity := opN;
        item := StItemNode(si, raw);
        if item <> nil then
        begin
          if LnColour(LnNode(item, ['lineStyle', 'color']), ic) then c := ic;
          d := LnNode(item, ['lineStyle', 'width']);
          if (d <> nil) and (d.JSONType = jtNumber) then w := d.AsFloat;
          d := LnNode(item, ['lineStyle', 'type']);
          if d <> nil then
          begin
            iword := DashText(d);
            LnDashOf(d, idash, iexpl);
          end;
          { parallelVisual: the item's own opacity only while normal }
          d := LnNode(item, ['lineStyle', 'opacity']);
          if (d <> nil) and (d.JSONType = jtNumber) then row.Opacity := d.AsFloat;
        end;
        case row.Active of
          ppaActive: row.Opacity := opA;
          ppaInactive: row.Opacity := opI;
        end;
        row.Stroke := c;
        row.Width := w;
        row.DashWord := iword;
        row.Dash := TyDashPattern(idash, iexpl, w);
        sol.Rows[r] := row;
      end;
    finally
      ClearExceptions(False);
      SetExceptionMask(mask);
    end;
    FParSolved[i] := sol;
  end;
  finally
    FreeAndNil(FParSeen);
    FParSeen := seen;
  end;
end;

{ ParallelAxisView's AxisBuilder, in the skin's axis styles: the line and
  its arrows, the ticks and minor ticks, the name, the labels -- the keys
  every other axis draws in (a parallelAxis shares axisDefault) }
procedure TTyAdvanceChart.PaintParallels(APainter: TTyPainter; APPI: Integer;
  const AMeasurer: ITyTextMeasurer);
var
  i, a, q: Integer;
  par: TTyParallel;
  model: TTyStyleModel;
  lineS, tickS, minorTickS, labelS, nameS: TTyStyleSet;
  lblW, lblH: Integer;
  sp: TTyAxisLayoutSpec;
  pl: TTyAxisNamePlacement;

  function LineWidth(const AStyle: TTyStyleSet): Double;
  begin
    if tpBorderWidth in AStyle.Present then Result := AStyle.BorderWidth
    else Result := 1;
    if Result < 0.05 then Result := 0.05;
  end;

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

  procedure TextSizeOf(const AText: string; const AStyle: TTyStyleSet;
    out AW, AH: Integer);
  var w, h: Double;
  begin
    AW := 0;
    AH := 0;
    if AMeasurer = nil then Exit;
    AMeasurer.MeasureLine(AText, AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, w, h);
    AW := Round(w);
    AH := Round(h);
  end;

  { a coordinate a canvas would draw: neither infinite nor not a number }
  function Fin(A: Double): Boolean;
  begin
    Result := not (IsNan(A) or IsInfinite(A));
  end;

  procedure StrokeLines(const ALines: TTyPolarLineArray; const AStyle: TTyStyleSet);
  var k, n: Integer;
  begin
    if not (tpBorderColor in AStyle.Present) then Exit;
    n := 0;
    APainter.BeginPath;
    for k := 0 to High(ALines) do
    begin
      if not ALines[k].Drawn then Continue;
      if not (Fin(ALines[k].X1) and Fin(ALines[k].Y1) and Fin(ALines[k].X2)
        and Fin(ALines[k].Y2)) then Continue;
      APainter.MoveTo(ALines[k].X1, ALines[k].Y1);
      APainter.LineTo(ALines[k].X2, ALines[k].Y2);
      Inc(n);
    end;
    if n > 0 then APainter.StrokePath(AStyle.BorderColor, LineWidth(AStyle));
  end;

  procedure PaintArrow(const AArrow: TTyAxisArrow);
  var
    el: TTyChartElement;
    path: TTyZrPath;
    t: string;
  begin
    { [F6a] a picture }
    if TyAxisArrowImage(AArrow, el) then
    begin
      TyRenderElement(APainter, el);
      Exit;
    end;
    t := AArrow.SymbolType;
    path := TyZrSymbol(t, -AArrow.W / 2, -AArrow.H / 2, AArrow.W, AArrow.H);
    if Length(path) = 0 then Exit;
    el := Default(TTyChartElement);
    el.Style.Alpha := 1;
    el.Shape := TyMkZrShape(path, TyZrLocal(1, 1, AArrow.Rotation, AArrow.X,
      AArrow.Y), True);
    if Copy(t, 1, 5) = 'empty' then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(model.ResolveStyle(
        'TyAdvChartEmptyCircle', '', []).Background.Color);
      el.Style.StrokeColor := TTyChartColor(lineS.BorderColor);
      el.Style.StrokeWidthLogical := 2;
    end
    else if t = 'line' then
    begin
      el.Style.StrokeColor := TTyChartColor(lineS.BorderColor);
      el.Style.StrokeWidthLogical := 1;
    end
    else
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(lineS.BorderColor);
    end;
    TyRenderElement(APainter, el);
  end;

begin
  if Length(FParallels) = 0 then Exit;
  if ViewHidden(cvParallelAxis) then Exit;
  model := ActiveController.Model;
  lineS := model.ResolveStyle('TyAdvChartAxisLine', '', []);
  tickS := model.ResolveStyle('TyAdvChartAxisTick', '', []);
  minorTickS := model.ResolveStyle('TyAdvChartMinorTick', '', []);
  for i := 0 to High(FParallels) do
  begin
    par := FParallels[i];
    if par = nil then Continue;
    for a := 0 to High(par.Views) do
    begin
      if not par.Views[a].Shown then Continue;
      ViewDrew(cvParallelAxis);
      sp := par.Views[a].Spec;
      { a lone axis stands nowhere (its place is not a number) }
      if not (Fin(par.Layouts[a].PosX) and Fin(par.Layouts[a].PosY)) then Continue;
      if par.Views[a].HasLine and (tpBorderColor in lineS.Present) then
      begin
        APainter.BeginPath;
        APainter.MoveTo(par.Views[a].Line.X1, par.Views[a].Line.Y1);
        APainter.LineTo(par.Views[a].Line.X2, par.Views[a].Line.Y2);
        APainter.StrokePath(lineS.BorderColor, LineWidth(lineS));
        for q := 0 to High(sp.Arrows) do PaintArrow(sp.Arrows[q]);
      end;
      StrokeLines(par.Views[a].Ticks, tickS);
      StrokeLines(par.Views[a].MinorTicks, minorTickS);
      AxisTextStyles(@sp, labelS, nameS);
      pl := sp.NamePlacement;
      if pl.Shown and (tpTextColor in nameS.Present) then
      begin
        if Length(pl.Rt) > 0 then
          TyRenderRtPieces(APainter, pl.Rt, pl.X, pl.Y, pl.RotationRad, sp.RtScale,
            1, True, nameS.TextColor)
        else if Abs(pl.RotationRad) < 1e-9 then
        begin
          TextSizeOf(pl.Text, nameS, lblW, lblH);
          APainter.DrawText(AnchorBox(pl.X, pl.Y, lblW, lblH, pl.AnchorH, pl.AnchorV),
            pl.Text, nameS.FontName, ResolveFontSize(nameS), nameS.FontWeight,
            nameS.TextColor, taCenter, tlCenter, False, 0, False, Pos(#10, pl.Text) > 0);
        end
        else
        begin
          TextSizeOf(pl.Text, nameS, lblW, lblH);
          DrawRotatedNameLines(APainter, pl.Text, nameS.FontName, ResolveFontSize(nameS),
            nameS.FontWeight, nameS.TextColor, pl.X, pl.Y, pl.RotationRad,
            AnchorAlign(pl.AnchorH), AnchorLayout(pl.AnchorV), lblH);
        end;
      end;
      if not (tpTextColor in labelS.Present) then Continue;
      for q := 0 to High(sp.Placements) do
      begin
        if not sp.Placements[q].Shown or (sp.Placements[q].Text = '') then Continue;
        if Length(sp.Placements[q].Rt) > 0 then
        begin
          TyRenderRtPieces(APainter, sp.Placements[q].Rt, sp.Placements[q].X,
            sp.Placements[q].Y, sp.RotationRad, sp.RtScale, 1, True, labelS.TextColor);
          Continue;
        end;
        if sp.RotationRad <> 0 then
        begin
          { every line of a label of several [R2-A] }
          TextSizeOf(sp.Placements[q].Text, labelS, lblW, lblH);
          DrawRotatedNameLines(APainter, sp.Placements[q].Text, labelS.FontName,
            ResolveFontSize(labelS), labelS.FontWeight, labelS.TextColor,
            sp.Placements[q].X, sp.Placements[q].Y, sp.RotationRad,
            AnchorAlign(sp.Placements[q].AnchorH), AnchorLayout(sp.Placements[q].AnchorV),
            lblH);
          Continue;
        end;
        TextSizeOf(sp.Placements[q].Text, labelS, lblW, lblH);
        APainter.DrawText(AnchorBox(sp.Placements[q].X, sp.Placements[q].Y, lblW,
          lblH, sp.Placements[q].AnchorH, sp.Placements[q].AnchorV),
          sp.Placements[q].Text, labelS.FontName, ResolveFontSize(labelS),
          labelS.FontWeight, labelS.TextColor, taCenter, tlCenter, False, 0, False,
          Pos(#10, sp.Placements[q].Text) > 0);
      end;
    end;
  end;
end;

{ parallelAxisAction's axisAreaSelect: every parallelAxis the query names
  (parallelAxisIndex, else parallelAxisId, else parallelAxisName; none is
  all) whose parallel was built takes `intervals` (setActiveIntervals: a
  clone, each pair ascending) }
function TTyAdvanceChart.ParallelAreaSelect(APayload: TJSONObject;
  out AFirst: Integer; AWrite: Boolean): Boolean;
var
  n, k, j, q: Integer;
  hit: array of Boolean;
  d: TJSONData;
  iv: TTyParallelIntervalArray;

  procedure MarkIndex(AData: TJSONData);
  var j: Integer; v: Double;
  begin
    if AData is TJSONArray then
    begin
      for j := 0 to AData.Count - 1 do MarkIndex(TJSONArray(AData).Items[j]);
      Exit;
    end;
    { a property key: a whole number, or a string that is one }
    if AData.JSONType = jtNumber then v := AData.AsFloat
    else if (AData.JSONType = jtString) and (AData.AsString <> '')
      and (IntToStr(StrToIntDef(AData.AsString, -1)) = AData.AsString) then
      v := StrToInt(AData.AsString)
    else Exit;
    if IsNan(v) or (Frac(v) <> 0) or (v < 0) or (v >= n) then Exit;
    hit[Trunc(v)] := True;
  end;

  { cmpts[idx] of one item of the index list: -1 for no model there }
  function IndexOfItem(AData: TJSONData): Integer;
  var v: Double;
  begin
    Result := -1;
    if AData.JSONType = jtNumber then v := AData.AsFloat
    else if (AData.JSONType = jtString) and (AData.AsString <> '')
      and (IntToStr(StrToIntDef(AData.AsString, -1)) = AData.AsString) then
      v := StrToInt(AData.AsString)
    else Exit;
    if IsNan(v) or (Frac(v) <> 0) or (v < 0) or (v >= n) then Exit;
    if FOption.ComponentAt('parallelAxis', Trunc(v)) is TJSONObject then
      Result := Trunc(v);
  end;

  procedure MarkText(AData: TJSONData; AById: Boolean; AInList: Boolean);
  var j: Integer; t: string;
  begin
    if AData is TJSONArray then
    begin
      if AInList then Exit;
      for j := 0 to AData.Count - 1 do MarkText(TJSONArray(AData).Items[j], AById, True);
      Exit;
    end;
    { queryByIdOrName: a list matches its strings only, a single value as
      its text }
    if AData.JSONType = jtString then t := AData.AsString
    else if (AData.JSONType = jtNumber) and not AInList then
      t := TyJsNumberToString(AData.AsFloat)
    else Exit;
    for j := 0 to n - 1 do
      if AById and (ComponentModelId('parallelAxis', j) = t) then hit[j] := True
      else if (not AById) and (ComponentModelName('parallelAxis', j) = t) then hit[j] := True;
  end;

begin
  Result := False;
  AFirst := -1;
  if (FOption = nil) or (APayload = nil) then Exit;
  n := FOption.ComponentCount('parallelAxis');
  if n = 0 then Exit;
  SetLength(hit, n);
  for k := 0 to n - 1 do hit[k] := False;
  d := APayload.Find('parallelAxisIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    MarkIndex(d);
    { findComponents by index: the list's order [Batch 130] }
    if d is TJSONArray then
    begin
      for j := 0 to d.Count - 1 do
      begin
        q := IndexOfItem(TJSONArray(d).Items[j]);
        if q >= 0 then
        begin
          AFirst := q;
          Break;
        end;
      end;
    end
    else
      AFirst := IndexOfItem(d);
  end
  else
  begin
    d := APayload.Find('parallelAxisId');
    if (d <> nil) and (d.JSONType <> jtNull) then MarkText(d, True, False)
    else
    begin
      d := APayload.Find('parallelAxisName');
      if (d <> nil) and (d.JSONType <> jtNull) then MarkText(d, False, False)
      else
        for k := 0 to n - 1 do hit[k] := True;
    end;
    { by id, by name or all: the components' order [Batch 130] }
    for k := 0 to n - 1 do
      if hit[k] and (FOption.ComponentAt('parallelAxis', k) is TJSONObject) then
      begin
        AFirst := k;
        Break;
      end;
  end;
  { [R2-E] the query alone (fromAxisAreaSelect's findComponents) }
  if not AWrite then Exit;
  iv := TyParallelIntervalsOf(APayload.Find('intervals'));
  if Length(FParIntervals) < n then SetLength(FParIntervals, n);
  for k := 0 to n - 1 do
  begin
    if not hit[k] then Continue;
    if not (FOption.ComponentAt('parallelAxis', k) is TJSONObject) then Continue;
    { an axis on no parallel has no `axis` to set them through }
    if ParallelOfAxis(k) < 0 then Continue;
    FParIntervals[k] := Copy(iv);
    Result := True;
  end;
end;

{ THE CONTINUOUS PART, a lines series with a trail through its own layer:
  the canvas' motion blur -- the last frame drawn back at lastFrameAlpha,
  then the layer's elements over it -- here an alpha multiply of the kept
  layer before the series is drawn on it again. The rest of the part draws
  as it does without a trail, over it. [Batch 121] }
procedure TTyAdvanceChart.PaintTrail(APainter: TTyPainter; AList: TTyPaintList);
var
  bmp: TBGRABitmap;
  P: TTyPainter;
  i, idx: Integer;
  el: TTyChartElement;
  a: Double;
  any: Boolean;
  rest: TTyPaintList;
  sc: TTyCanvasScale;
begin
  if (AList = nil) or (APainter = nil) then Exit;
  bmp := APainter.Bitmap;
  any := False;
  a := 0;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Datum.Kind = ctkSeries) and (LinesTrailAlpha(el.Datum.SeriesIndex) > 0) then
    begin
      any := True;
      a := LinesTrailAlpha(el.Datum.SeriesIndex);
      Break;
    end;
  end;
  if (not any) or (bmp = nil) then
  begin
    FreeAndNil(FTrailLayer);
    TyRenderPaintList(APainter, AList);
    Exit;
  end;
  if (FTrailLayer = nil) or (FTrailLayer.Width <> bmp.Width)
    or (FTrailLayer.Height <> bmp.Height) then
  begin
    FreeAndNil(FTrailLayer);
    FTrailLayer := TBGRABitmap.Create(bmp.Width, bmp.Height, BGRAPixelTransparent);
  end
  else
    FTrailLayer.ApplyGlobalOpacity(Round(Max(0.0, Min(1.0, a)) * 255));
  rest := TTyPaintList.Create;
  P := TTyPainter.Create;
  try
    { the layer the size of the painter's bitmap, drawn at its device scale
      over the device-px rect (#83) }
    sc.Scale := APainter.DeviceScale;
    sc.DeviceUnits := False;
    P.BeginPaintOnScaled(nil, Rect(0, 0, bmp.Width div sc.Scale, bmp.Height div sc.Scale),
      FPaintListPPI, FTrailLayer, sc);
    for i := 0 to AList.Count - 1 do
    begin
      idx := AList.PaintOrder(i);
      el := AList.Element(idx);
      if (el.Datum.Kind = ctkSeries) and (LinesTrailAlpha(el.Datum.SeriesIndex) > 0) then
      begin
        if not el.Ignore then TyRenderElement(P, el);
      end;
    end;
    P.EndPaint;
    bmp.PutImage(0, 0, FTrailLayer, dmDrawWithTransparency);
    for i := 0 to AList.Count - 1 do
    begin
      el := AList.Element(i);
      if not ((el.Datum.Kind = ctkSeries) and (LinesTrailAlpha(el.Datum.SeriesIndex) > 0)) then
        rest.Add(el);
    end;
    if rest.Count > 0 then TyRenderPaintList(APainter, rest);
  finally
    P.Free;
    rest.Free;
  end;
end;

procedure TTyAdvanceChart.SolveRadars(APPI: Integer);
var
  i, j, k, n, dim, slot: Integer;
  ref: TTyXYWH;
  spec: TTyRadarSpec;
  lo, hi, v, dLo, dHi: Double;
  seen, fixLo, fixHi, incl0: Boolean;
begin
  FreeRadars;
  SetLength(FRadarDims, Length(FBindings));
  for i := 0 to High(FRadarDims) do FRadarDims[i] := nil;
  n := 0;
  if FOption <> nil then n := FOption.ComponentCount('radar');
  if n = 0 then Exit;
  SetLength(FRadars, n);
  for i := 0 to n - 1 do
  begin
    spec := TyRadarSpecOf(FOption, i);
    FRadars[i] := TTyRadar.Create(spec);
    { FLastRect, and there is nothing between it and the radar: a radar's
      option carries no left/top/right/bottom at all, so nothing can shrink
      the canvas under it. [Batch 154] Unless it is in a matrix cell or a
      calendar day: createBoxLayoutReference's container then. }
    if ComponentBoxRef('radar', i, ref) then FRadars[i].ResizeXYWH(ref, APPI)
    else FRadars[i].Resize(FLastRect, APPI);
  end;

  { ---- which store column feeds which spoke ---- }
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].RadarIndex < 0 then Continue;
    if FBindings[i].RadarIndex > High(FRadars) then Continue;
    if i > High(FStores) then Break;
    if FStores[i] = nil then Continue;
    SetLength(FRadarDims[i], FRadars[FBindings[i].RadarIndex].AxisCount);
    for j := 0 to High(FRadarDims[i]) do
      FRadarDims[i][j] := FStores[i].DimIndexOf(TyRadarDimPrefix + IntToStr(j));
  end;

  { ---- every spoke's value range ---- }
  for k := 0 to High(FRadars) do
  begin
    spec := FRadars[k].Spec;
    for j := 0 to FRadars[k].AxisCount - 1 do
    begin
      { THE UNION OVER EVERY SERIES ON THIS RADAR, and it is collected here
        because nothing else is in a position to: TyApplyAxisExtents walks the
        cartesian grids' axis lists and a spoke is in neither. }
      dLo := NaN;
      dHi := NaN;
      seen := False;
      for i := 0 to High(FBindings) do
      begin
        if FBindings[i].RadarIndex <> k then Continue;
        { AN EQUIVALENT MUTANT TODAY, recorded rather than removed. A radar's
          legend names its ROWS, so switching one off filters the store and
          the loop below never sees it -- `Hidden` is only ever set for a
          series whose legend entry is the series itself, which a radar's
          never is. The guard is what the rule SAYS, and it stops being
          equivalent the day anything else can hide a whole radar series. }
        if FBindings[i].Hidden then Continue;
        if i > High(FStores) then Break;
        if FStores[i] = nil then Continue;
        if j > High(FRadarDims[i]) then Continue;
        dim := FRadarDims[i][j];
        if (dim < 0) or (dim >= FStores[i].DimCount) then Continue;
        for slot := 0 to FStores[i].Count - 1 do
        begin
          v := FStores[i].Get(dim, slot);
          if IsNan(v) or IsInfinite(v) then Continue;
          if not seen then
          begin
            dLo := v;
            dHi := v;
            seen := True;
          end
          else
          begin
            if v < dLo then dLo := v;
            if v > dHi then dHi := v;
          end;
        end;
      end;
      { THE RAW RANGE, THEN ALIGNED to splitNumber segments -- upstream's
        radar runs every spoke through scaleCalcAlign. [Revised in batch 48:
        the raw range was the spoke's extent.] }
      TyRadarIndicatorExtent(spec.Indicators[j], dLo, dHi, spec.Scale_, lo, hi,
        fixLo, fixHi, incl0);
      FRadars[k].AlignAxis(j, lo, hi, fixLo, fixHi, incl0);
    end;
  end;
end;

function TTyAdvanceChart.RadarInk: TTyRadarInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  Result := TyRadarInk;
  model := ActiveController.Model;
  { THE SPOKES AND THE RINGS ARE AN AXIS AND ITS SPLIT LINES, whatever the
    option calls them, so they take the keys an axis already has. }
  Result.AxisLine := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisLine', '', []).BorderColor);
  Result.SplitLine := TTyChartColor(
    model.ResolveStyle('TyAdvChartSplitLine', '', []).BorderColor);
  Result.Tick := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisTick', '', []).BorderColor);
  { THE ALTERNATING BANDS. Upstream writes a pale tint and a transparent one,
    so every other band shows the ground through it -- the split-area key is
    already alpha over the ink and says exactly that, and its partner is
    nothing at all. }
  Result.SplitAreaA := TTyChartColor(
    model.ResolveStyle('TyAdvChartSplitArea', '', []).Background.Color);
  Result.SplitAreaB := 0;
  st := model.ResolveStyle('TyAdvChartAxisName', '', []);
  Result.NameColour := TTyChartColor(st.TextColor);
  Result.NameFontName := st.FontName;
  Result.NameFontSizeLogical := ResolveFontSize(st);
  Result.NameFontWeight := st.FontWeight;
  GlobalInk(Result.NameFontName, Result.NameFontSizeLogical,
    Result.NameFontWeight, Result.NameColour, [ttpSize, ttpWeight, ttpFamily]);
  st := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  Result.LabelFontName := st.FontName;
  Result.LabelFontSizeLogical := ResolveFontSize(st);
  Result.LabelFontWeight := st.FontWeight;
  GlobalInk(Result.LabelFontName, Result.LabelFontSizeLogical,
    Result.LabelFontWeight, Result.LabelColour, [ttpWeight, ttpFamily]);
  Result.Z := 0;
end;

function TTyAdvanceChart.RadarVisual(ASlot: Integer): TTyRadarVisual;
var
  k: Integer;
  node: TJSONObject;
  d: TJSONData;
  ls, ar: TJSONObject;
  c: TTyChartColor;
begin
  Result := TyRadarVisual(SeriesColor(ASlot));
  Result.Fills := PerDatumColours(ASlot);
  Result.Decals := RawRowDecals(ASlot);
  { a visualMap's symbolSize per ring }
  if (ASlot <= High(FVisualRows)) and (FVisualRows[ASlot] <> nil) then
  begin
    SetLength(Result.Sizes, Length(FVisualRows[ASlot]));
    for k := 0 to High(FVisualRows[ASlot]) do
      if FVisualRows[ASlot][k].SizeSet then
      begin
        { a size that is no number is nought, as normalizeSymbolSize has it
          [F4c]; a pair's width (the radar's symbols are round) }
        Result.Sizes[k] := FVisualRows[ASlot][k].Size;
        if IsNan(Result.Sizes[k]) then Result.Sizes[k] := 0;
      end
      else Result.Sizes[k] := NaN;
  end;
  Result.EmptyFill := TTyChartColor(
    ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
  Result.Symbol := SymbolFor(ASlot);
  if FOption = nil then Exit;
  { [R2-A] the points' labels: the series' and each item's own over it; each
    item's own symbol }
  Result.Label_ := LabelSpecFor(ASlot);
  ItemLabelSpecs(FBindings[ASlot].SeriesIndex, Result.Label_, Result.ItemLabels,
    Result.HasItemLabel);
  Result.SeriesName := SeriesModelName(FBindings[ASlot].SeriesIndex);
  SymbolItems(FBindings[ASlot].SeriesIndex, Result.Symbol, Result.RowSyms,
    Result.RowSymSet);
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('lineStyle');
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    ls := TJSONObject(d);
    d := ls.Find('width');
    if (d <> nil) and (d.JSONType = jtNumber) then
      Result.LineWidthLogical := d.AsFloat;
    d := ls.Find('color');
    if (d <> nil) and (d.JSONType = jtString)
      and TyTryParseChartColor(d.AsString, c) then Result.Fill := c;
  end;
  { AN AREA ONLY WHEN THE AUTHOR ASKED FOR ONE, and `areaStyle: {}` counts as
    asking -- upstream's test is whether the option object exists at all, not
    whether it has anything in it. That is why an empty object is the documented
    way to fill a radar. }
  d := node.Find('areaStyle');
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    Result.HasArea := True;
    Result.Area := Result.Fill;
    ar := TJSONObject(d);
    d := ar.Find('color');
    if (d <> nil) and (d.JSONType = jtString)
      and TyTryParseChartColor(d.AsString, c) then
    begin
      Result.Area := c;
      Result.AreaAuthored := True;
    end;
    d := ar.Find('opacity');
    if (d <> nil) and (d.JSONType = jtNumber) then
      Result.AreaOpacity := Max(Double(0), Min(Double(1), d.AsFloat));
  end;
  { AN ITEM'S OWN areaStyle [F4a]: Model.isEmpty is `option == null`, so any
    object an item writes shows its polygon; its colour and opacity over the
    series' }
  d := node.Find('data');
  if d is TJSONArray then
  begin
    SetLength(Result.RowArea, d.Count);
    SetLength(Result.RowAreaColourSet, d.Count);
    SetLength(Result.RowAreaColour, d.Count);
    SetLength(Result.RowAreaOpacitySet, d.Count);
    SetLength(Result.RowAreaOpacity, d.Count);
    for k := 0 to d.Count - 1 do
    begin
      if not (TJSONArray(d).Items[k] is TJSONObject) then Continue;
      ar := nil;
      if TJSONObject(TJSONArray(d).Items[k]).Find('areaStyle') is TJSONObject then
        ar := TJSONObject(TJSONObject(TJSONArray(d).Items[k]).Find('areaStyle'));
      if ar = nil then Continue;
      Result.RowArea[k] := True;
      if (ar.Find('color') <> nil) and (ar.Find('color').JSONType = jtString)
        and TyTryParseChartColor(ar.Find('color').AsString, c) then
      begin
        Result.RowAreaColourSet[k] := True;
        Result.RowAreaColour[k] := c;
      end;
      if (ar.Find('opacity') <> nil) and (ar.Find('opacity').JSONType = jtNumber) then
      begin
        Result.RowAreaOpacitySet[k] := True;
        Result.RowAreaOpacity[k] := Max(Double(0), Min(Double(1), ar.Find('opacity').AsFloat));
      end;
    end;
  end;
  { a state's areaStyle shows the polygon in that state [F2b] }
  for k := 0 to 2 do
  begin
    case k of
      0: d := node.Find('emphasis');
      1: d := node.Find('select');
    else
      d := node.Find('blur');
    end;
    if (d is TJSONObject) and (TJSONObject(d).Find('areaStyle') <> nil)
      and (TJSONObject(d).Find('areaStyle').JSONType <> jtNull) then
      Result.StateArea := True;
  end;
end;

procedure TTyAdvanceChart.SolveGauges(APPI: Integer);
var
  i: Integer;
begin
  SetLength(FGauges, Length(FBindings));
  SetLength(FGaugeSpecs, Length(FBindings));
  SetLength(FGaugeItems, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FGauges[i] := Default(TTyGaugeLayout);
    FGaugeSpecs[i] := TyGaugeSpecDefault;
    FGaugeItems[i] := nil;
    if i > High(FStores) then Break;
    if not FBindings[i].Resolved then Continue;
    if FBindings[i].SeriesType <> TyGaugeSeriesTypeName then Continue;
    FGaugeSpecs[i] := TyGaugeSpecOf(FOption, FBindings[i].SeriesIndex);
    FGaugeItems[i] := TyGaugeItemsOf(FOption, FBindings[i].SeriesIndex,
      FGaugeSpecs[i]);
    { FLastRect, and unlike the pie and the funnel there is no box between the
      two: a gauge resolves its centre against the CONTROL's width and height
      and its radius against half the shorter side. Its `center` is the only
      thing that moves it. }
    FGauges[i] := TyGaugeLayoutOf(FGaugeSpecs[i], FLastRect, APPI);
  end;
end;

function TTyAdvanceChart.GaugeVisual(ASlot: Integer): TTyGaugeVisual;
var
  dummyCol: TTyChartColor;
  model: TTyStyleModel;
  st: TTyStyleSet;
  f: TTyTitleFont;
begin
  Result := TyGaugeVisual;
  Result.Fills := PerDatumColours(ASlot);
  Result.Decals := RawRowDecals(ASlot);
  model := ActiveController.Model;
  { THE TRACK IS THE RING A PIE DRAWS WITH NO DATA. Upstream writes a literal
    pale grey, which is a pale grey ring on a dark skin; the same key the empty
    pie uses is alpha over the ink and follows either mode. }
  Result.Track := TTyChartColor(
    model.ResolveStyle('TyAdvChartEmptyCircle', '', []).Background.Color);
  { A GAUGE'S SPLIT LINE IS A MAJOR TICK and its axisTick is a minor one --
    which is what they ARE, whatever the option calls them, so they take the
    axis' own two keys rather than a pair of their own. }
  Result.SplitLine := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisTick', '', []).BorderColor);
  Result.Tick := TTyChartColor(
    model.ResolveStyle('TyAdvChartMinorTick', '', []).BorderColor);
  st := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  Result.LabelFontName := st.FontName;
  Result.LabelFontSizeLogical := ResolveFontSize(st);
  Result.LabelFontWeight := st.FontWeight;
  { a gauge's axis label (12px), title (16px) and detail (30px bold) have
    sizes of their own }
  GlobalInk(Result.LabelFontName, Result.LabelFontSizeLogical,
    Result.LabelFontWeight, dummyCol, [ttpWeight, ttpFamily]);
  f := TitleFont('TyAdvChartLabel');
  GlobalInk(f.Name, f.SizeLogical, f.Weight, dummyCol, [ttpWeight, ttpFamily]);
  st := model.ResolveStyle('TyAdvChartLabel', '', []);
  Result.TitleColour := TTyChartColor(st.TextColor);
  Result.TitleFontName := f.Name;
  Result.TitleFontSizeLogical := f.SizeLogical;
  Result.TitleFontWeight := f.Weight;
  { THE READING IS THE ONE NEW KEY THIS SERIES NEEDED. Nothing in the existing
    vocabulary is a big bold number: the chart's own title key is bold but is
    sized from the title scale, and a gauge's reading is the headline of the
    picture rather than a heading over it. }
  f := TitleFont('TyAdvChartGaugeDetail');
  GlobalInk(f.Name, f.SizeLogical, f.Weight, dummyCol, [ttpFamily]);
  st := model.ResolveStyle('TyAdvChartGaugeDetail', '', []);
  Result.DetailColour := TTyChartColor(st.TextColor);
  Result.DetailFontName := f.Name;
  Result.DetailFontSizeLogical := f.SizeLogical;
  Result.DetailFontWeight := f.Weight;
  { The hub is the chart's own ground with the accent around it, which is what
    upstream's white-on-theme-blue means said in this vocabulary. }
  Result.AnchorFill := TTyChartColor(
    model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]).Background.Color);
  Result.AnchorBorder := TTyChartColor(ThemeRampColor(0));
end;

function TTyAdvanceChart.FunnelVisual(ASlot: Integer): TTyFunnelVisual;
var st: TTyStyleSet; k: Integer;
begin
  Result := TyFunnelVisual;
  Result.Fills := PerDatumColours(ASlot);
  { the object fills by raw row [Batch 105] }
  SetLength(Result.Objs, Length(Result.Fills));
  for k := 0 to High(Result.Objs) do
    Result.Objs[k] := DatumObjectFill(ASlot, k);
  { the decals by raw row [Batch 131] }
  SetLength(Result.Decals, Length(Result.Fills));
  for k := 0 to High(Result.Decals) do
    Result.Decals[k] := RowDecalOf(ASlot, k);
  { THE BAND'S OUTLINE IS THE CHART'S OWN GROUND, which is what separates two
    adjacent bands of nearly the same colour. Upstream writes neutral00 -- its
    white -- and on a dark skin that is a white grid over a dark funnel; the
    surface colour is the same idea said in this vocabulary. }
  st := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
    [tysNormal]);
  Result.Stroke := TTyChartColor(st.Background.Color);
  Result.StrokeWidthLogical := 1;
end;

function TTyAdvanceChart.FunnelLabelInk: TTyFunnelLabelInk;
var
  dummyCol: TTyChartColor;
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartLabel', '', []);
  Result.FontName := st.FontName;
  Result.FontSizeLogical := ResolveFontSize(st);
  Result.FontWeight := st.FontWeight;
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    dummyCol, [ttpSize, ttpWeight, ttpFamily]);
  Result.OutsideColour := TTyChartColor(st.TextColor);
  { THE SAME THREE BANDS THE PIE AND THE MARKS USE. Not a second table: a
    label over a coloured shape is one question however the shape was made. }
  Result.InsideColour[0] := TTyChartColor(
    model.ResolveStyle('TyAdvChartLabelOnLight', '', []).TextColor);
  Result.InsideColour[1] := TTyChartColor(
    model.ResolveStyle('TyAdvChartLabelOnMid', '', []).TextColor);
  Result.InsideColour[2] := TTyChartColor(
    model.ResolveStyle('TyAdvChartLabelOnDark', '', []).TextColor);
  LabelGround(Result.Ground, Result.GroundDark);
end;

function TTyAdvanceChart.PerDatumColours(ASlot: Integer): TTyChartColorArray;
var
  k, rawN, si: Integer;
  c, base: TTyChartColor;
  ov: TTyDataValue;
begin
  { ONE COLOUR PER RAW ROW, in the order upstream's stages write it: the
    series' colour (its written one, its palette pick -- `auto` included --
    or none), then a visualMap's over it (4000), then the datum's own
    itemStyle colour (4500), then the per-datum palette for the rows still
    the palette's (4600, colorBy other than 'series'; SolveDatumPalette).
    [Batch 105: the palette ran from nought for every series, took a slot
    for rows that had their own colour, and a pie by series was still
    coloured by datum.] }
  Result := nil;
  rawN := 0;
  if (ASlot <= High(FStores)) and (FStores[ASlot] <> nil) then
    rawN := FStores[ASlot].RawCount;
  SetLength(Result, rawN);
  si := FBindings[ASlot].SeriesIndex;
  base := TTyChartColor(SeriesColor(si));
  for k := 0 to rawN - 1 do
  begin
    Result[k] := base;
    if (ASlot <= High(FVisualRows)) and (k <= High(FVisualRows[ASlot]))
      and FVisualRows[ASlot][k].ColorSet then
      Result[k] := TyVisualToChart(FVisualRows[ASlot][k].Color)
    else if (ASlot <= High(FDatumAsked)) and (k <= High(FDatumAsked[ASlot]))
      and FDatumAsked[ASlot][k] then
      Result[k] := TTyChartColor(PickColor(FDatumPicks[ASlot][k]));
  end;
  { AND A DATUM THAT NAMED ITS OWN COLOUR KEEPS IT. `data: [{ value: 5,
    itemStyle: { color: '#c23531' } }]` is the commonest thing anybody writes
    on either chart, and it beats the ramp -- the same rule a bar follows,
    reached through the same parked override. }
  for k := 0 to rawN - 1 do
    if FStores[ASlot].HasOverrideByRaw(k, TyOverrideKey('itemStyle.color')) then
    begin
      ov := FStores[ASlot].GetOverrideByRaw(k, TyOverrideKey('itemStyle.color'));
      if (ov.Kind = dvkText) and TyTryParseChartColor(ov.Text, c) then
        Result[k] := c;
    end;
end;

function TTyAdvanceChart.PieVisual(ASlot: Integer): TTyPieVisual;
var
  k, n, raw: Integer;
  perRaw: TTyChartColorArray;
  bst: TTyOptStyle;
  ov: TTyDataValue;
begin
  Result := TyPieVisual(0);
  { colorBy:''data''. Each SECTOR takes the next slot of the same nine-colour
    ramp a bar series cycles across series -- which is what makes a pie read
    at all, and what makes it re-skin with the accent like everything else.

    A SLICE THAT NAMED ITS OWN COLOUR KEEPS IT. `data: [{ value: 5,
    itemStyle: { color: ''#c23531'' } }]` is the commonest thing anybody
    writes on a pie, and it beats the ramp -- the same rule a bar follows,
    reached through the same parked override. }
  { ONE COLOUR PER RAW ROW, TAKEN IN RAW ORDER, before a single sector is
    looked at. A slice that was filtered out -- a negative value, a legend
    click -- still consumes its slot, which is the only way the surviving
    slices keep the colours they had. Upstream iterates its raw data here for
    the same reason and says so in a comment.

    Keyed on the slice's NAME, so two pies over the same categories agree
    about which category is which colour -- and so a repeated name inside one
    pie shares a colour rather than taking a second slot. }
  perRaw := PerDatumColours(ASlot);

  n := Length(FPies[ASlot].Sectors);
  if n < 1 then n := 1;
  SetLength(Result.Fills, n);
  { THE OBJECT FILLS, per sector by its raw row [Batch 105] }
  SetLength(Result.Objs, n);
  for k := 0 to n - 1 do
    if k <= High(FPies[ASlot].Sectors) then
      Result.Objs[k] := DatumObjectFill(ASlot, FPies[ASlot].Sectors[k].RawIndex);
  { the decals, per sector by its raw row [Batch 131] }
  SetLength(Result.Decals, n);
  for k := 0 to n - 1 do
    if k <= High(FPies[ASlot].Sectors) then
      Result.Decals[k] := RowDecalOf(ASlot, FPies[ASlot].Sectors[k].RawIndex);
  { AND THE BORDER the series wrote: PieSeries' itemStyle is borderWidth 1
    with no colour, so nothing is stroked until a colour is written [Batch
    105: it was never read] }
  bst := TyReadOptStyle(TJSONObject(FOption.ComponentAt('series',
    FBindings[ASlot].SeriesIndex)), 'itemStyle');
  if bst.BorderColor.Written and not bst.BorderColor.IsNone
    and not bst.BorderColor.IsAuto then
  begin
    Result.Stroke := bst.BorderColor.Color;
    if IsNan(bst.BorderWidthLogical) then Result.StrokeWidthLogical := 1
    else Result.StrokeWidthLogical := bst.BorderWidthLogical;
  end;
  if FLastPPI > 0 then Result.PxScale := FLastPPI / 96;
  { AND THE OPACITY, in the order upstream's stages write the item style:
    the series' itemStyle.opacity, a visualMap's over it (which a pie keeps,
    a funnel does not), then the row's own itemStyle.opacity over both
    (dataStyleTask, 4500). [Milestone D5-D8: only the visualMap's was
    drawn.] }
  SetLength(Result.Alphas, n);
  for k := 0 to n - 1 do
  begin
    Result.Alphas[k] := bst.Opacity;
    if k > High(FPies[ASlot].Sectors) then Continue;
    raw := FPies[ASlot].Sectors[k].RawIndex;
    if (ASlot <= High(FVisualRows)) and (raw >= 0)
      and (raw <= High(FVisualRows[ASlot])) and FVisualRows[ASlot][raw].OpacitySet then
      Result.Alphas[k] := FVisualRows[ASlot][raw].Opacity;
    if (raw >= 0) and (ASlot <= High(FStores)) and (FStores[ASlot] <> nil)
      and FStores[ASlot].HasOverrideByRaw(raw, TyOverrideKey('itemStyle.opacity')) then
    begin
      ov := FStores[ASlot].GetOverrideByRaw(raw, TyOverrideKey('itemStyle.opacity'));
      if (ov.Kind = dvkNumber) and not IsNan(ov.Num) then Result.Alphas[k] := ov.Num;
    end;
  end;
  for k := 0 to n - 1 do
  begin
    { KEYED ON THE RAW ROW, NOT THE SECTOR. The two are the same number only
      while nothing has been dropped -- and something already is: a negative
      value is filtered out before the layout runs, and now a legend can
      filter more. Key the ramp on the sector's position and every surviving
      slice changes colour the moment a neighbour leaves, which is the one
      failure of this commit a reader would notice immediately.

      Upstream says the same thing in a comment written for the same reason:
      `Iterate on data before filtered. To make sure color from palette can
      be consistent when toggling legend.` (visual/style.ts:207-208). }
    if k <= High(FPies[ASlot].Sectors) then
    begin
      raw := FPies[ASlot].Sectors[k].RawIndex;
      if (raw >= 0) and (raw <= High(perRaw)) then
        Result.Fills[k] := perRaw[raw]
      else
        Result.Fills[k] := TTyChartColor(ThemeRampColor(raw));
    end
    else
      Result.Fills[k] := TTyChartColor(ThemeRampColor(k));
  end;
  { The empty ring has its own token rather than borrowing the split area''s:
    they are faint for different reasons and a theme has to be able to move
    one without the other. }
  Result.EmptyFill := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartEmptyCircle', '',
      []).Background.Color);
end;

procedure TTyAdvanceChart.BoxplotStyle(ASlot: Integer; var AVisual: TTySeriesVisual);
var
  d: TJSONData;
  st: TTyOptStyle;
  si: Integer;
begin
  si := FBindings[ASlot].SeriesIndex;
  AVisual.Whisker.BoxFill := AVisual.EmptyFill;
  AVisual.Whisker.BoxStroke := TTyChartColor(SeriesColor(si));
  AVisual.Whisker.BoxLineWidthLogical := 1;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', si);
  if not (d is TJSONObject) then Exit;
  st := TyReadOptStyle(TJSONObject(d), 'itemStyle');
  if st.Color.Written then
  begin
    if st.Color.IsNone then AVisual.Whisker.BoxFill := 0
    else if st.Color.IsAuto then AVisual.Whisker.BoxFill := TTyChartColor(SeriesPaletteColor(si))
    else AVisual.Whisker.BoxFill := st.Color.Color;
  end;
  if st.BorderColor.Written then
  begin
    if st.BorderColor.IsNone then AVisual.Whisker.BoxStroke := 0
    else if st.BorderColor.IsAuto then
      AVisual.Whisker.BoxStroke := TTyChartColor(SeriesPaletteColor(si))
    else AVisual.Whisker.BoxStroke := st.BorderColor.Color;
  end;
  if not IsNan(st.BorderWidthLogical) then
    AVisual.Whisker.BoxLineWidthLogical := st.BorderWidthLogical;
end;

function TTyAdvanceChart.CandleVisual(ASlot: Integer): TTyCandleSpec;
var
  model: TTyStyleModel;
  up, down: TTyStyleSet;
  d: TTyCandleSpec;
begin
  model := ActiveController.Model;
  up := model.ResolveStyle('TyAdvChartCandleUp', '', []);
  down := model.ResolveStyle('TyAdvChartCandleDown', '', []);
  d := Default(TTyCandleSpec);
  d.Up := TTyChartColor(up.Background.Color);
  d.Down := TTyChartColor(down.Background.Color);
  { THE BORDER FOLLOWS THE BODY unless the theme said otherwise. Upstream's
    two defaults are the same pair of colours written twice, and a skin that
    wants an outlined candle sets `border-color` on these keys without having
    to restate the fill. }
  if tpBorderColor in up.Present then d.UpBorder := TTyChartColor(up.BorderColor)
  else d.UpBorder := d.Up;
  if tpBorderColor in down.Present then
    d.DownBorder := TTyChartColor(down.BorderColor)
  else d.DownBorder := d.Down;
  d.BorderWidthLogical := 1;
  if (tpBorderColor in up.Present) and (up.BorderWidth > 0) then
    d.BorderWidthLogical := up.BorderWidth;
  Result := TyCandleSpecOf(FOption, ASlot, d);
end;

function TTyAdvanceChart.PolarBarOf(ASeriesIndex: Integer): TTyPolarBarLayout;
var slot: Integer;
begin
  Result := Default(TTyPolarBarLayout);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FPolarBars)) then Result := FPolarBars[slot];
end;

function TTyAdvanceChart.BarColumnOf(ASeriesIndex: Integer): TTyBarColumn;
begin
  Result := Default(TTyBarColumn);
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FBarCols)) then
    Result := FBarCols[ASeriesIndex];
end;
