{ Part of tyControls.AdvanceChart (included, not a unit): painting -- the axes, the static
  and the dynamic layers, the series, and the dirty rectangles. Moved out of the unit only
  to keep it readable; what the control is and why it is built the way it is, see the unit
  header. }

{ ==================== paint ==================== }

procedure TTyAdvanceChart.PaintAxis(APainter: TTyPainter; AAxis: TTyAxis;
  const APlot: TTyRectF; APPI: Integer; AGrid: TTyGridBuild;
  const AMeasurer: ITyTextMeasurer; ABelow: Boolean; AProxied: Boolean);
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
  horiz: Boolean;
  lblH, lblW: Integer;
  scaleTicks: TTyScaleTickArray;
  spec: PTyAxisLayoutSpec;
  places: TTyAxisLabelPlacementArray;
  furn: TTyAxisFurniture;
  areaS: TTyStyleSet;
  bandLo, bandHi: Double;
  { the split colours [Batch 101] }
  ink: Integer;
  areaFill: TTyFill;
  inkStyle: TTyStyleSet;
  view: TTyChartView;
  { [F3b] the proxied areas, minor ticks and name }
  areaR: TRect;
  majors: Integer;
  nx, ny, nrot: Double;

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

  { The width the theme asked for, LOGICAL -- StrokePath scales it itself.

    An undeclared width falls back to one logical pixel rather than to zero: a
    theme that names a colour and no width means "draw it", not "draw nothing",
    and StrokePath treats a width of zero as "no border". }
  function LineWidth(const AStyle: TTyStyleSet): Double;
  begin
    if tpBorderWidth in AStyle.Present then
      Result := AStyle.BorderWidth
    else
      Result := 1;
    if Result < 0.05 then Result := 0.05;
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
    const ALineStyle: TTyStyleSet);
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
      el.Style.StrokeColor := TTyChartColor(ALineStyle.BorderColor);
      el.Style.StrokeWidthLogical := 2;
    end
    else if t = 'line' then
    begin
      el.Style.StrokeColor := TTyChartColor(ALineStyle.BorderColor);
      el.Style.StrokeWidthLogical := 1;
    end
    else
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := TTyChartColor(ALineStyle.BorderColor);
    end;
    TyRenderElement(P, el);
  end;

  procedure BatchLine(AX1, AY1, AX2, AY2: Double; AWidthLogical: Double);
  begin
    TySubPixelLine(AX1, AY1, AX2, AY2, APainter.ScaleF(AWidthLogical));
    APainter.MoveTo(AX1, AY1);
    APainter.LineTo(AX2, AY2);
    Inc(batched);
  end;

  { Stroke what BatchLine collected, if anything. The count guards a stroke of
    an empty path, which a fully thinned-away set of minor ticks produces. }
  procedure StrokeBatch(const AStyle: TTyStyleSet);
  begin
    if batched > 0 then
      APainter.StrokePath(AStyle.BorderColor, LineWidth(AStyle));
    batched := 0;
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
  if AGrid <> nil then furn := AGrid.FurnitureFor(AAxis);

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
  { MINOR FIRST, so a major line drawn at the same place wins. The two theme
    keys have been in light.tycss since item 18 with nothing that could ever be
    drawn with them: every generator wrote Level 0. }
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
  if ABelow and furn.ShowSplitArea and (spec <> nil) then
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
      end
      else if (ink <> 0) or not (tpBackground in areaS.Present) then
        Continue;
      bandLo := spec^.SplitAreaMarks[i].Coord;
      bandHi := spec^.SplitAreaMarks[i + 1].Coord;
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

  { WHATEVER THE LABELS ARE DOING: upstream subdivides every interval.
    [Revised in batch 40: only while every major label was drawn.] }
  if ABelow and furn.ShowMinorSplitLine
    and (tpBorderColor in minorSplitS.Present) then
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
        BatchLine(along, APlot.Top, along, APlot.Bottom, LineWidth(minorSplitS))
      else
        BatchLine(APlot.Left, along, APlot.Right, along, LineWidth(minorSplitS));
    end;
    StrokeBatch(minorSplitS);
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
  if ABelow and furn.ShowSplitLine and (spec <> nil)
    and ((tpBorderColor in splitS.Present) or (Length(spec^.SplitLineInks) > 0)) then
  begin
    for ink := 0 to Max(0, High(spec^.SplitLineInks)) do
    begin
      inkStyle := splitS;
      if Length(spec^.SplitLineInks) > 0 then
      begin
        if not spec^.SplitLineInks[ink].Ok then Continue;
        inkStyle.BorderColor := TTyColor(spec^.SplitLineInks[ink].Colour);
      end;
      APainter.BeginPath;
      for i := 0 to High(spec^.SplitLineMarks) do
      begin
        if not spec^.SplitLineMarks[i].Drawn then Continue;
        if (Length(spec^.SplitLineInks) > 0)
          and (spec^.SplitLineMarks[i].ColourIndex <> ink) then Continue;
        if ProxLine('line_' + TyJsNumberToString(spec^.SplitLineMarks[i].Value)) then Continue;
        along := spec^.SplitLineMarks[i].Coord;
        if horiz then
          BatchLine(along, APlot.Top, along, APlot.Bottom, LineWidth(splitS))
        else
          BatchLine(APlot.Left, along, APlot.Right, along, LineWidth(splitS));
      end;
      StrokeBatch(inkStyle);
    end;
  end;

  { EVERYTHING ABOVE THIS LINE IS THE GRID and everything below it is the
    axis. The three grid blocks each test ABelow and this returns on it, so
    each pass paints its own half and neither repeats the other's -- the
    return alone was not enough, because the second pass would then draw the
    grid a second time, over the lines the first pass had just laid.

    THIS RETURN IS INVISIBLE ON ITS OWN. Delete it and the below pass also
    draws the lines, which the above pass then draws again on top -- same
    pixels, twice the work. A mutation that removes it survives, and it is
    the three ABelow tests above that carry the ordering; this one carries
    only the cost. }
  if ABelow then Exit;

  { The domain line. Present, not colour: an undeclared colour resolves to
    alpha zero, so testing the colour would draw an invisible line and call it
    drawn. }
  if furn.ShowLine and (tpBorderColor in lineS.Present) then
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
      BatchLine(APlot.Left, at, APlot.Right, at, LineWidth(lineS))
    else
      BatchLine(at, APlot.Top, at, APlot.Bottom, LineWidth(lineS));
    StrokeBatch(lineS);
    { THE ARROWS, over the line (z2 11 to its 1), in its colour: a symbol's
      setColor fills it -- strokes a `line`, rings an `empty` one round the
      skin's empty-symbol ground [Batch 101] }
    if spec <> nil then
      for i := 0 to High(spec^.Arrows) do
        PaintAxisArrow(APainter, spec^.Arrows[i], lineS);
  end;

  { ALIGNED WITH THE LABELS OR WITH THE BAND EDGES. On a banded category axis
    the two are half a band apart, and which one a tick means is exactly what
    the option exists to say -- the split lines above keep the edges either
    way, because a divider that pointed at a label would not divide anything. }
  { THE MARKS WHERE THE LAYOUT PUT THEM, on their own interval or the
    labels', a tick whose label was hidden gone with it.
    [Revised in batch 40: every tickStep-th tick, a hidden label's kept.] }
  if furn.ShowTicks and (tpBorderColor in tickStyle.Present) and (spec <> nil) then
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
      BatchLine(x1, y1, x2, y2, LineWidth(tickStyle));
    end;
    StrokeBatch(tickStyle);
  end;

  { Minor MARKS. The difference in LENGTH is what says which is which when both
    are the same colour family -- and how much shorter is the theme's call, not
    a fraction hardcoded here. --advchart-minor-tick-length, its constant and
    its default have all been in place since item 18 with nothing reading them,
    so a skin that set it changed nothing. }
  if furn.ShowMinorTick and (tpBorderColor in minorTickS.Present) then
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
      BatchLine(x1, y1, x2, y2, LineWidth(minorTickS));
    end;
    StrokeBatch(minorTickS);
  end;

  { THE AXIS NAME, WHERE THE LAYOUT PUT IT. The grid was shrunk for the
    name's box on its estimate pass and the name laid out again on the final
    rect -- at its location and gap, turned and aligned as upstream turns and
    aligns it, and moved clear of the labels -- so this draws that answer
    and works nothing out: a second route here is how the name used to land
    beside the band that was reserved for it. }
  if (spec <> nil) and spec^.NamePlacement.Shown
    and (tpTextColor in nameS.Present) then
  begin
    { where its groupTransition has it now [F3b] }
    nx := spec^.NamePlacement.X;
    ny := spec^.NamePlacement.Y;
    nrot := spec^.NamePlacement.RotationRad;
    ProxName(nx, ny, nrot);
    { A BLOCK DRAWS ITS PIECES, the skin's ink where no style gave one
      [Batch 86] }
    if Length(spec^.NamePlacement.Rt) > 0 then
      TyRenderRtPieces(APainter, spec^.NamePlacement.Rt, nx, ny, nrot, spec^.RtScale, 1,
        True, nameS.TextColor)
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

  if not (tpTextColor in labelS.Present) then Exit;

  { PHASE 3 PLACES THEM. It was written with item 12 and never called, so every
    label was drawn at a position worked out here and none was ever thinned --
    a crowded axis simply overlapped. The placement carries the anchor too, so
    layout and paint cannot disagree about where a label went. }
  if (spec <> nil) and (Length(spec^.Placements) > 0) then
  begin
    places := spec^.Placements;
    for i := 0 to High(places) do
    begin
      if not places[i].Shown then Continue;
      if places[i].Text = '' then Continue;
      { THE STYLE THE LAYOUT MEASURED IT IN. A time axis' heavier `Mar` in a
        run of day numbers is a `{primary|Mar}` tag, drawn from its pieces
        below in the weight the block was measured in. [Revised in batch
        104: a whole label marked emphasised and drawn in a second style.] }
      lblStyle := labelS;
      { where its groupTransition has it now [Batch 96] }
      lx := places[i].X;
      ly := places[i].Y;
      ProxLabel(i, lx, ly);
      { A BLOCK DRAWS ITS PIECES [Batch 86] }
      if Length(places[i].Rt) > 0 then
      begin
        TyRenderRtPieces(APainter, places[i].Rt, lx, ly,
          spec^.RotationRad, spec^.RtScale, 1, True, lblStyle.TextColor);
        Continue;
      end;
      TextSizeOf(places[i].Text, lblStyle, lblW, lblH);
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
        APainter.DrawTextRotated(places[i].Text, lblStyle.FontName,
          ResolveFontSize(lblStyle), lblStyle.FontWeight, lblStyle.TextColor,
          lx, ly, spec^.RotationRad,
          AnchorAlign(places[i].AnchorH), AnchorLayout(places[i].AnchorV));
        Continue;
      end;
      APainter.DrawText(
        AnchorBox(lx, ly, lblW, lblH,
                  places[i].AnchorH, places[i].AnchorV),
        places[i].Text, lblStyle.FontName, ResolveFontSize(lblStyle),
        lblStyle.FontWeight, lblStyle.TextColor, taCenter, tlCenter,
        { ELLIPSIS AND MULTI-LINE, both of which the painter has always had and
          this never asked for: a label was drawn as one clipped line whatever
          it contained, so a wrapped one lost every row after the first. }
        spec^.LabelOverflow = loTruncate, 0, False,
        Pos(#10, places[i].Text) > 0);
    end;
    Exit;
  end;

  { NO PLACEMENTS, NO LABELS. There used to be a second route here that
    formatted and positioned the ticks itself, for an axis laid out without a
    spec. None reaches it -- every grid axis gets a spec, and the placements
    are one per label -- so all it ever did was keep its own copy of the
    number format in step with the builder's, which it did not. The builder
    is the one place a label's text comes from. }
end;

procedure TTyAdvanceChart.RenderTo(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
var prev: TComponent;
begin
  prev := TyChartImageScopeEnter(Owner);
  try
    RenderToBody(ACanvas, ARect, APPI);
  finally
    TyChartImageScopeLeave(prev);
  end;
end;

procedure TTyAdvanceChart.RenderToBody(ACanvas: TCanvas; const ARect: TRect;
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
  P := TTyPainter.Create;
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

procedure TTyAdvanceChart.PaintStatic(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
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
  if FDirty or (plotF.Right <> FLastRect.Right)
    or (plotF.Bottom <> FLastRect.Bottom) then
  begin
    Relayout(APainter, plotF, APPI, AMeasurer);
    { the frame a lazy setOption waited for [Batch 97] }
    LazyUpdateDone;
    { its flush is `rendered` for a bar race [Batch 135] }
    if not FExporting then FRtAfterRelayout := True;
  end;

  { THE GRAPHIC COMPONENT, against the canvas; its elements at z 0 and
    under go beneath the axes, as upstream's group joins the root first
    [Batch 122] }
  GfxBuild(APPI);
  GfxPaintUnder(APainter);
  { WHILE THEIR groupTransition RUNS the axes are the dynamic layer's, as
    the series are [Batch 96] -- an export draws them at rest [Batch 106] }
  if FExporting or not AxesDynamic then PaintAxes(APainter, APPI, AMeasurer, False);
  { THE GROUND A REPAINTED RECT STARTS FROM: everything above, before the
    first series [Batch 142] }
  if FDrCapture and (APainter <> nil) then DrCaptureBase(APainter.Bitmap);

  { AFTER THE AXES, so a bar sits on the grid rather than under it. Within the
    series, the paint list decides the order. }
  PaintSeries(APainter, AMeasurer, APPI);
  { THE BREAK AREAS, zigzagZ over the series [Batch 132] -- the dynamic
    layer's while the series move there, over them and in their axes'
    groupTransition [F4a] }
  if FExporting or not FAnimLive or FAnimContinuous then PaintBreakAreas(APainter);
  { THE PARALLEL AXES OVER THEIR LINES: a parallelAxis is z 10, its series
    2 [Batch 128] }
  PaintParallels(APainter, APPI, AMeasurer);
  { AND THE TITLE LAST. It floats over the container rather than reserving
    room, so anything it overlaps it is meant to overlap. While the series
    move the title goes with them into the dynamic layer, so it stays over
    them [Batch 89]. }
  if FExporting or not FAnimLive or FAnimContinuous then PaintTitles(APainter);
end;

procedure TTyAdvanceChart.PaintAxes(APainter: TTyPainter; APPI: Integer;
  const AMeasurer: ITyTextMeasurer; AProxied: Boolean);
var
  g, a: Integer;
  gb: TTyGridBuild;
begin
  if FBuild = nil then Exit;
  { THE POLARS' GRIDS, then their axes [Batch 111] }
  PaintPolars(APainter, APPI, AMeasurer, True);
  PaintPolars(APainter, APPI, AMeasurer, False);
  { THE SINGLE AXES' GRIDS, then their axes [Batch 118] }
  PaintSingles(APainter, APPI, AMeasurer, True);
  PaintSingles(APainter, APPI, AMeasurer, False);
  for g := 0 to FBuild.GridCount - 1 do
  begin
    gb := FBuild.Grid(g);
    { EVERY AXIS' GRID FIRST, then every axis' line. Two passes over the
      same list rather than one, because the order that matters is
      between the LAYERS and not between the axes. }
    for a := 0 to gb.XAxisCount - 1 do
      PaintAxis(APainter, gb.XAxis(a), gb.PlotRect, APPI, gb, AMeasurer,
                True, AProxied);
    for a := 0 to gb.YAxisCount - 1 do
      PaintAxis(APainter, gb.YAxis(a), gb.PlotRect, APPI, gb, AMeasurer,
                True, AProxied);
    for a := 0 to gb.XAxisCount - 1 do
      PaintAxis(APainter, gb.XAxis(a), gb.PlotRect, APPI, gb, AMeasurer,
                False, AProxied);
    for a := 0 to gb.YAxisCount - 1 do
      PaintAxis(APainter, gb.YAxis(a), gb.PlotRect, APPI, gb, AMeasurer,
                False, AProxied);
  end;
end;

function TTyAdvanceChart.StackFor(ASlot: Integer): TTySeriesStack;
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

function TTyAdvanceChart.LabelStepFor(AAxis: TTyAxis): Integer;
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
function TTyAdvanceChart.SeriesIntIn(ASeriesIndex: Integer;
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

function TTyAdvanceChart.SymbolFor(ASlot: Integer): TTySymbolSpec;
var
  d: TJSONData;
  node: TJSONObject;
begin
  Result := TySymbolDefault('');
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  Result := TySymbolDefault(FBindings[ASlot].SeriesType);
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  Result := TySymbolSpecOf(node, Result);
end;

procedure TTyAdvanceChart.PaintSeries(APainter: TTyPainter;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
var
  drawn, i: Integer;
  built, prepped, layered: Boolean;
  frame: TTyPaintList;
begin
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
  built := not prepped and not (FProgReuse and FPaintListValid and (FPaintList <> nil)
    and not FExporting);
  FProgReuse := False;
  if built then drawn := BuildSeriesList(AMeasurer, APPI)
  else drawn := FPaintList.Count;
  { AN EXPORT DRAWS THE LIST AS LAID OUT: the finished chart, nothing armed,
    bound or stepped -- the proxies are the window's [Batch 106] }
  if FExporting then
  begin
    if drawn > 0 then TyRenderPaintList(APainter, FPaintList);
    Exit;
  end;
  if built then AnimAfterBuild;
  { the states on their proxies, then the armed option's flush [Batch 94] }
  if not prepped then
  begin
    StAnimSync;
    AnimFlushArmed;
  end;
  { IN MOTION, THE SERIES ARE THE DYNAMIC LAYER'S: a static layer holding
    them would freeze the first frame under every later one (Q7). }
  { ONLY LOOPS LEFT: everything but the ripples and their symbols stays
    here [Batch 92] }
  if FAnimContinuous then
  begin
    if (drawn > 0) and (FDrMode = 0) then TyRenderPaintList(APainter, AnimPart(False));
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
      if FDrMode = 0 then TyRenderPaintList(APainter, frame);
      FDrStaticList := frame;
    end
    else
    begin
      { a progressive run's chunks through their own layer [Batch 119] }
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
procedure TTyAdvanceChart.GlobalInk(var AName: string; var ASize,
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

{ backgroundColor as the option writes it, when it is a colour that paints:
  not 'transparent', not 'none', not unreadable, not fully clear }
function TTyAdvanceChart.AuthorBackground(out AColour: TTyChartColor): Boolean;
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

procedure TTyAdvanceChart.PaintDynamic(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
begin
  { AN EXPORT'S: the finished picture has no frame of an animation and no
    hover -- an option's own pointers, and the loading effect over all
    [Batch 106] }
  if FExporting then
  begin
    PaintAxisPointers(APainter, ARect, APPI, AMeasurer, OptionPointerHits);
    PaintLoading(APainter, ARect, APPI, AMeasurer);
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
    PaintTrail(APainter, AnimPart(True))
  else if FAnimLive then
  begin
    { the trail is the continuous phase's: an enter or an update in motion
      draws every series as it stands [Batch 121] }
    FreeAndNil(FTrailLayer);
    { the axes in their groupTransition under the series, as the static
      layer draws them [Batch 96] }
    if AxesDynamic then PaintAxes(APainter, APPI, AMeasurer, True);
    TyRenderPaintList(APainter, AnimFrame);
    { the break areas over the series in motion [F4a] }
    PaintBreakAreas(APainter);
    { the parallel axes over the lines in motion [Batch 128] }
    PaintParallels(APainter, APPI, AMeasurer);
    PaintTitles(APainter);
  end;
  { THE POINTER UNDER THE HIGHLIGHT UNDER THE BOX. A shadow band drawn over
    the bars is the layer debt showing -- series marks live in the static
    layer, so the band cannot go beneath them -- and re-drawing the hovered
    marks on top of the band is what hides it. }
  { and before any pointer event, the ones the option shows itself
    [Batch 100] }
  if Length(FTipHits) > 0 then
    PaintAxisPointers(APainter, ARect, APPI, AMeasurer, FTipHits)
  else
    PaintAxisPointers(APainter, ARect, APPI, AMeasurer, OptionPointerHits);
  PaintEmphasis(APainter, APPI, FTipHits);
  { THE KEYBOARD'S RING over the marks and under the box [Batch 144] }
  PaintKbRing(APainter);
  { THE POINTER FIRST, THE BOX OVER IT. A tooltip with the pointer's own line
    drawn across it would read as two things at one depth. }
  PaintTooltip(APainter, ARect, APPI, AMeasurer);
  { THE LOADING EFFECT OVER EVERYTHING: upstream's mask is z 10000
    [Batch 106] }
  PaintLoading(APainter, ARect, APPI, AMeasurer);
end;

function TTyAdvanceChart.HasDynamicContent: Boolean;
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
    or FKbStopOn;
end;

procedure TTyAdvanceChart.DropStatic;
begin
  StaticDrop;
  FProgReuse := False;
  { AND THE LIST WITH IT. The two describe the same frame: the list is what
    the static pass added up to, so a kept list beside a dropped cache would
    answer questions about a picture no longer on screen. Not freed -- the
    next build reuses the object and only the answer is stale. }
  FPaintListValid := False;
end;

procedure TTyAdvanceChart.DropStaticKeepList;
var had: Boolean;
begin
  had := (FPaintList <> nil) and FPaintListValid;
  DropStatic;
  if had and (FLastPPI > 0) and not FExporting then
  begin
    BuildSeriesList(NewTextMeasurer(FLastPPI), FLastPPI);
    StaticDrop;
  end;
end;

procedure TTyAdvanceChart.PointerStateChanged;
begin
  { [F4b] the base class' pointer bookkeeping: a repaint, nothing marked }
  InvalidateFrameQuiet;
end;

procedure TTyAdvanceChart.RenderCached(ACanvas: TCanvas; const ARect: TRect;
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
    FStaticPPI := APPI;
  end;
  { upstream's frame: the flags become state lists, and a changed element
    is a changed static layer [Batch 88] }
  if StApplyChanged then
  begin
    FStatic.Drop;
    { the states restyle the list: it is built again [Batch 119] -- or,
      where only they changed, patched where it stands [P2] }
    FProgReuse := StPatchList;
  end;

  { AND THE DEVICE SCALE: the cache holds S times the pixels and its canvas
    is a raster canvas a painter draws on at S; a change of S is a change of
    size, so it renders again (#83) }
  if FStatic.NeedsRender(w, h, sc) then
  begin
    measurer := NewTextMeasurer(APPI);
    P := TTyPainter.Create;
    try
      P.BeginPaint(FStatic.Canvas, R, APPI);
      PaintStatic(P, R, APPI, measurer);
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
    P := TTyPainter.Create;
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

procedure TTyAdvanceChart.Paint;
var prev: TComponent;
begin
  prev := TyChartImageScopeEnter(Owner);
  try
    PaintBody;
  finally
    TyChartImageScopeLeave(prev);
  end;
end;

procedure TTyAdvanceChart.PaintBody;
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
  (AdvChart.DirtyRect). What the port hit-tests apart from the list (the
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

procedure TTyAdvanceChart.StaticDrop;
begin
  if FStatic <> nil then FStatic.Drop;
  { the cache no longer holds what the snapshot says [Batch 142] }
  FDrSnapOk := False;
end;

procedure TTyAdvanceChart.SetUseDirtyRect(AValue: Boolean);
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

function TTyAdvanceChart.CoarseSize: Integer;
begin
  Result := TyCoarsePointerSize(FCoarsePointer, FPointerSize, TyTouchPlatform);
end;

function TTyAdvanceChart.ListHitAt(AX, AY: Double): Integer;
var
  L: TTyPaintList;
  sz: Integer;
begin
  Result := -1;
  if (FPaintList = nil) or not FPaintListValid then Exit;
  { IN MOTION, WHAT IS DRAWN IS WHAT IS HIT, and at rest on a state proxy
    (see HitTestAt) }
  if FAnimLive or (Length(FAnimStBind) > 0) then L := AnimFrame else L := FPaintList;
  sz := CoarseSize;
  if sz <= 0 then Exit(L.HitTestElement(AX, AY, FPaintListPPI));
  Result := L.HitTestElement(AX, AY, FPaintListPPI, False);
  if Result < 0 then Result := TyCoarseHitTest(L, AX, AY, FPaintListPPI, sz);
end;

function TTyAdvanceChart.LastRepaintFull: Boolean;
begin
  Result := FDrLastFull;
end;

function TTyAdvanceChart.LastRepaintRects: TTyZrRectArray;
begin
  Result := Copy(FDrLastRects);
end;

procedure TTyAdvanceChart.DrCaptureBase(ABmp: TBGRABitmap);
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

function TTyAdvanceChart.DrCanPartial(AW, AH: Integer): Boolean;
begin
  { the cache holds the snapshot's list over the captured ground, at this
    size, with nothing to lay out again and the series at rest in it }
  Result := FDrSnapOk and FDrBaseOk and (FDrWork <> nil) and (FDrBase <> nil)
    and (FDrWork.Width = AW * FDrScale) and (FDrWork.Height = AH * FDrScale)
    and (FDrBase.Width = AW * FDrScale) and (FDrBase.Height = AH * FDrScale)
    and not FDirty and (FLastRect.Right = AW) and (FLastRect.Bottom = AH)
    and not FExporting and not FAnimLive and not FAnimContinuous;
end;

procedure TTyAdvanceChart.DrStaticFull(const R: TRect; APPI: Integer);
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
  P := TTyPainter.Create;
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

function TTyAdvanceChart.DrStaticPartial(const R: TRect; APPI: Integer;
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
    static layer would not hold one list: everything }
  if FAnimLive or FAnimContinuous or (FDrStaticList = nil) then Exit;
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
  P := TTyPainter.Create;
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
      out. }
    box := TyRectToXYWH(TyRectF(px[0].Left, px[0].Top, px[0].Right, px[0].Bottom));
    for k := 1 to n - 1 do
      TyZrRectUnion(box, TyRectToXYWH(TyRectF(px[k].Left, px[k].Top, px[k].Right, px[k].Bottom)));
    FDrWork.ClipRect := DrRaster(Rect(Round(box.X), Round(box.Y), Round(box.X + box.W),
      Round(box.Y + box.H)));
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
        for k := 0 to n - 1 do
          if TyZrRectIntersect(snap[idx].Rect, zr[k]) then
          begin
            hit := True;
            Break;
          end;
        if not hit then Continue;
      end;
      TyRenderElement(P, snap[idx].El);
    end;
    { what the static paint draws over the series, as it draws it }
    PaintBreakAreas(P);
    PaintParallels(P, APPI, measurer);
    PaintTitles(P);
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

function TTyAdvanceChart.DrRaster(const R: TRect): TRect;
var
  s: Integer;
begin
  s := Max(1, FDrScale);
  Result := Rect(R.Left * s, R.Top * s, R.Right * s, R.Bottom * s);
end;

procedure TTyAdvanceChart.DrCopyStatic(ACanvas: TCanvas; const APx: TRect);
begin
  { the static layer at the canvas origin, as Blit puts it: its pixels from
    the cache, into the canvas's own units }
  ACanvas.CopyRect(TyCanvasRect(ACanvas, APx), FStatic.Canvas, DrRaster(APx));
end;

procedure TTyAdvanceChart.DrDrawDynamic(ACanvas: TCanvas; const APx: TRect;
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

procedure TTyAdvanceChart.DrDynamic(const R: TRect; APPI: Integer;
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
    AFull := True;
  end;
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
    P := TTyPainter.Create;
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
end;

procedure TTyAdvanceChart.DrPrepare(const ARect: TRect; APPI: Integer;
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

procedure TTyAdvanceChart.DrComposite(ACanvas: TCanvas; const ARect: TRect);
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

procedure TTyAdvanceChart.DrPaintWindow;
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

procedure TTyAdvanceChart.DrFlushAsync(AData: PtrInt);
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
