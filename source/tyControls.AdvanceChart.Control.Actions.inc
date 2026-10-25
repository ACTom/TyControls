{ Part of tyControls.AdvanceChart (included, not a unit): the coordinate conversions,
  dispatchAction, and echarts.connect's batch actions. Moved out of the unit only to keep
  it readable; what the control is and why it is built the way it is, see the unit header. }

function TTyCustomAdvanceChart.ConvertOnSingle(ASingle: TTySingle; AValue: TJSONData;
  AFrom: Boolean): TTyConvertResult;
begin
  if AFrom then Result := TySingleFromPixel(ASingle, AValue)
  else Result := TySingleToPixel(ASingle, AValue);
end;

{ ==================== the jitter [Batch 110] ==================== }

{ jitterLayout's gate: a scatter on a cartesian whose base axis is a
  category one with `jitter > 0` -- `jitterOverlap` true unless written
  falsy, `jitterMargin` 2 unless written (`|| 0` after that) }
procedure TTyCustomAdvanceChart.JitterFor(ASlot, APPI: Integer; var AVisual: TTySeriesVisual);
var
  base: TTyAxis;
  node: TJSONData;
  d: TJSONData;
  jit, margin, scale, band: Double;
  overlap, single, singleY: Boolean;
  s: TTySingle;

  function NumOf(AData: TJSONData): Double;
  begin
    case AData.JSONType of
      jtNumber: Result := AData.AsFloat;
      jtString: Result := TyJsToNumber(AData.AsString);
      jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    else
      Result := NaN;
    end;
  end;

begin
  AVisual.Jitter := nil;
  AVisual.JitterOnX := False;
  if (ASlot < 0) or (ASlot > High(FBindings)) or (FJitter = nil) then Exit;
  if FBindings[ASlot].SeriesType <> 'scatter' then Exit;
  { ON A SINGLE AXIS any type of axis jitters (needFixJitter's
    COORD_SYS_TYPE_SINGLE) [Batch 118] }
  single := FBindings[ASlot].Single <> nil;
  if single then
    base := FBindings[ASlot].BaseAxis
  else
  begin
    if (FBindings[ASlot].Cart = nil) or (FBindings[ASlot].CalendarIndex >= 0) then Exit;
    base := FBindings[ASlot].Cart.GetBaseAxis;
    if (base = nil) or (base.AxisType <> atCategory) then Exit;
  end;
  if base = nil then Exit;
  node := FOption.ComponentAt(base.MainType, base.ComponentIndex);
  if not (node is TJSONObject) then Exit;
  jit := 0;
  d := TJSONObject(node).Find('jitter');
  if (d <> nil) and (d.JSONType <> jtNull) then jit := NumOf(d);
  if IsNan(jit) or not (jit > 0) then Exit;
  overlap := True;
  d := TJSONObject(node).Find('jitterOverlap');
  if (d <> nil) and (d.JSONType <> jtNull) then overlap := TyJsTruthy(d);
  margin := 2;
  d := TJSONObject(node).Find('jitterMargin');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    margin := NumOf(d);
    if IsNan(margin) then margin := 0;
  end;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  if single then
  begin
    { a band only on a category axis: elsewhere nothing clamps (an
      infinite band is none) }
    if base.AxisType = atCategory then band := base.BandWidth
    else band := Infinity;
    AVisual.Jitter := FJitter.AxisFor(base.Uid, jit * scale, margin * scale,
      overlap, band);
    { isSingleY: a horizontal non-category axis or a vertical category one
      floats y }
    s := TTySingle(FBindings[ASlot].Single);
    singleY := (s.OrientHorizontal and (base.AxisType <> atCategory))
      or ((s.Orient = 'vertical') and (base.AxisType = atCategory));
    AVisual.JitterOnX := not singleY;
    Exit;
  end;
  AVisual.Jitter := FJitter.AxisFor(base.Uid, jit * scale, margin * scale,
    overlap, base.BandWidth);
  AVisual.JitterOnX := base.Horizontal;
end;

{ ==================== the coordinate conversions [Batch 110] ==================== }

procedure TTyCustomAdvanceChart.ConvertReady;
var m: ITyTextMeasurer;
begin
  { upstream's setOption lays the chart out before it returns: a layout
    the option has made stale is made again here, as a roam does }
  if FDirty and (FLastPPI > 0) then
  begin
    m := NewTextMeasurer(FLastPPI);
    Relayout(nil, FLastRect, FLastPPI, m);
    DropStatic;
    LazyUpdateDone;
    FZrDirty := True;
    inherited Invalidate;
  end;
end;

{ Grid.convertToPixel / convertFromPixel: _findConvertTarget -- the
  series' own cartesian when a series is named (and only if it is this
  grid's), else the cartesian of the x and y axes named, else the one axis
  named, else -- lowest -- the grid's first cartesian when the grid named is
  this one }
function TTyCustomAdvanceChart.ConvertOnGrid(AGrid: TTyGridBuild; const AF: TTyParsedFinder;
  AValue: TJSONData; AFrom: Boolean): TTyConvertResult;
var
  s, xm, ym, gm, slot, k: Integer;
  cart, own: TTyCartesian2D;
  axis: TTyAxis;
begin
  Result := TyConvertNone;
  cart := nil;
  axis := nil;
  s := TyFinderModel(AF, 'series');
  xm := TyFinderModel(AF, 'xAxis');
  ym := TyFinderModel(AF, 'yAxis');
  gm := TyFinderModel(AF, 'grid');
  if s >= 0 then
  begin
    slot := SlotOfSeries(s);
    if slot >= 0 then
    begin
      own := FBindings[slot].Cart;
      if own <> nil then
        for k := 0 to AGrid.CartesianCount - 1 do
          if AGrid.CartesianByIndex(k) = own then
          begin
            cart := own;
            Break;
          end;
    end;
  end
  else if (xm >= 0) and (ym >= 0) then
    cart := AGrid.CartesianAt(xm, ym)
  else if xm >= 0 then
  begin
    if AGrid.CartesianCount > 0 then
      for k := 0 to AGrid.XAxisCount - 1 do
        if AGrid.XAxis(k).ComponentIndex = xm then axis := AGrid.XAxis(k);
  end
  else if ym >= 0 then
  begin
    if AGrid.CartesianCount > 0 then
      for k := 0 to AGrid.YAxisCount - 1 do
        if AGrid.YAxis(k).ComponentIndex = ym then axis := AGrid.YAxis(k);
  end
  else if (gm >= 0) and (gm = AGrid.ComponentIndex) and (AGrid.CartesianCount > 0) then
    cart := AGrid.CartesianByIndex(0);
  if cart <> nil then
  begin
    if AFrom then Result := TyCartesianFromPixel(cart, AValue)
    else Result := TyCartesianToPixel(cart, AValue);
  end
  else if axis <> nil then
  begin
    if AFrom then Result := TyAxisFromPixel(axis, AValue)
    else Result := TyAxisToPixel(axis, AValue);
  end;
end;

{ Calendar.convertToPixel: dataToPoint of the value (its first element when
  it is an array), clamped to the range; convertFromPixel: the time of the
  day under the point, nothing off the range }
{ Geo.convertToPixel / convertFromPixel: dataToPoint of a region's name or
  a [lng, lat] pair, pointToData of a pixel; upstream's undefined (a name no
  region has, a projection's null point) answers nothing [Batch 146] }
function TTyCustomAdvanceChart.ConvertOnGeo(AGeo: TTyGeo; AValue: TJSONData;
  AFrom: Boolean): TTyConvertResult;
var
  p: TTyPointF;
  q: TTyGeoPt;
begin
  Result := TyConvertNone;
  if AFrom then
  begin
    if TyJsonNullish(AValue) then Exit;
    if AGeo.FromPixelJson(AValue, q) then Result := TyConvertXY(q.X, q.Y);
    Exit;
  end;
  if AGeo.ToPixelJson(AValue, p) then Result := TyConvertXY(p.X, p.Y);
end;

function TTyCustomAdvanceChart.ConvertOnCalendar(ACal: TTyCalendar; AValue: TJSONData;
  AFrom: Boolean): TTyConvertResult;
var
  v, own: TJSONData;
  dv: TTyDataValue;
  p: TTyPointF;
  d: TTyDoubleArray;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  own := nil;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    if AFrom then
    begin
      p := TyJsonPoint(AValue);
      if ACal.PointToData(p, d) and (Length(d) > 0) then
        Result := TyConvertNum(d[0]);
      Exit;
    end;
    v := AValue;
    if TyJsonIsArray(AValue) then v := TyJsonElement(AValue, 0, own);
    { getDateInfo's parseDate: a string through TIME_REG, nothing for null
      and undefined, anything else new Date(Math.round(v)) }
    dv := Default(TTyDataValue);
    dv.Kind := dvkNone;
    if not TyJsonNullish(v) then
    begin
      if v.JSONType = jtString then dv := TyDataText(v.AsString)
      else dv := TyDataNum(TyJsonToNumber(v));
    end;
    p := ACal.DatePoint(ACal.ParseDate(dv), True);
    Result := TyConvertXY(p.X, p.Y);
  finally
    own.Free;
    ConvertUnmask(mask);
  end;
end;

{ View.convertToPixel / convertFromPixel: the overall matrix -- whose zero
  terms carry a not-a-number or an infinity across, as zrender's
  applyTransform does -- or its inverse }
function TTyCustomAdvanceChart.ConvertOnView(AView: TTyGraphView; AValue: TJSONData;
  AFrom: Boolean): TTyConvertResult;
var
  pt, p: TTyPointF;
  d: TTyDoubleArray;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  pt := TyJsonPoint(AValue);
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    if not AFrom then
    begin
      p := AView.DataToPoint([pt.X, pt.Y]);
      Exit(TyConvertXY(p.X, p.Y));
    end;
    { no inverse: vectorCopy }
    if not AView.PointToData(pt, d) or (Length(d) < 2) then
      Exit(TyConvertXY(pt.X, pt.Y));
    if IsNan(pt.Y) or IsInfinite(pt.Y) then d[0] := NaN;
    if IsNan(pt.X) or IsInfinite(pt.X) then d[1] := NaN;
    Result := TyConvertXY(d[0], d[1]);
  finally
    ConvertUnmask(mask);
  end;
end;

{ doConvertPixel: every coordinate system in the manager's order -- the
  grids, the radars (which answer nothing), the graphs' views, then the
  parallels (which have no convertToPixel / convertFromPixel at all
  [Batch 128]), the polars and (were it here) singleAxis, then the
  calendars -- and the first answer that is not null/undefined }
function TTyCustomAdvanceChart.ConvertDispatch(AFinder, AValue: TJSONData;
  AFrom: Boolean; AOpt: TJSONData): TTyConvertResult;
var
  pf: TTyParsedFinder;
  g, slot, s, c, target: Integer;
begin
  Result := TyConvertNone;
  ConvertReady;
  if (FBuild = nil) or (FOption = nil) then Exit;
  pf := TyParseFinder(AFinder, FOption.Keys);
  try
    for g := 0 to FBuild.GridCount - 1 do
    begin
      Result := ConvertOnGrid(FBuild.Grid(g), pf, AValue, AFrom);
      if Result.Kind <> cvkNone then Exit;
    end;
    { THE GEOS [Batch 146], registered before the graph's view: the geo the
      finder names -- [Batch 152] or the geo the series it names is on
      (Geo's getCoordSys: geoModel, else seriesModel.coordinateSystem) }
    target := TyFinderModel(pf, 'geo');
    if (target >= 0) and (target <= High(FGeos)) and (FGeos[target] <> nil) then
    begin
      Result := ConvertOnGeo(FGeos[target], AValue, AFrom);
      if Result.Kind <> cvkNone then Exit;
    end
    else if target < 0 then
    begin
      slot := SlotOfSeries(TyFinderModel(pf, 'series'));
      if (slot >= 0) and (GeoOfSlot(slot) <> nil) then
      begin
        Result := ConvertOnGeo(GeoOfSlot(slot), AValue, AFrom);
        if Result.Kind <> cvkNone then Exit;
      end
      else if (slot >= 0) and (MapGeoOfSlot(slot) <> nil) and MapGeoOfSlot(slot).Valid then
      begin
        Result := ConvertOnGeo(MapGeoOfSlot(slot), AValue, AFrom);
        if Result.Kind <> cvkNone then Exit;
      end;
    end;
    { the graphs' views: one per graph series laid out on 'view', in series
      order; each answers only for its own series }
    s := TyFinderModel(pf, 'series');
    for slot := 0 to High(FGraphs) do
      if (FGraphs[slot] <> nil) and (slot <= High(FBindings))
        and (FBindings[slot].SeriesIndex = s) then
      begin
        Result := ConvertOnView(FGraphs[slot], AValue, AFrom);
        if Result.Kind <> cvkNone then Exit;
      end;
    { THE POLARS [Batch 111]: getCoordSys -- the polar named, else the
      series' own [Batch 113: a series on a polar] }
    for c := 0 to High(FPolars) do
    begin
      if FPolars[c] = nil then Continue;
      target := TyFinderModel(pf, 'polar');
      if (target < 0) and (s >= 0) then
      begin
        slot := SlotOfSeries(s);
        if (slot >= 0) and (FBindings[slot].Polar <> nil) then
          target := FBindings[slot].PolarIndex;
      end;
      if target <> c then Continue;
      Result := ConvertOnPolar(FPolars[c], AValue, AFrom);
      if Result.Kind <> cvkNone then Exit;
    end;
    { THE SINGLE AXES [Batch 118]: getCoordSys -- the single named, else
      the series' own }
    for c := 0 to High(FSingles) do
    begin
      if FSingles[c] = nil then Continue;
      target := TyFinderModel(pf, TySingleCoordSysName);
      if (target < 0) and (s >= 0) then
      begin
        slot := SlotOfSeries(s);
        if (slot >= 0) and (FBindings[slot].Single <> nil) then
          target := FBindings[slot].SingleIndex;
      end;
      if target <> c then Continue;
      Result := ConvertOnSingle(FSingles[c], AValue, AFrom);
      if Result.Kind <> cvkNone then Exit;
    end;
    { THE PARALLELS answer nothing: Parallel has no convertToPixel or
      convertFromPixel [Batch 128] }
    for c := 0 to High(FCalendars) do
    begin
      if FCalendars[c] = nil then Continue;
      { getCoordSys: the calendar named, else the series' own }
      target := TyFinderModel(pf, 'calendar');
      if (target < 0) and (s >= 0) then
      begin
        slot := SlotOfSeries(s);
        if slot >= 0 then target := FBindings[slot].CalendarIndex;
      end;
      if target <> c then Continue;
      Result := ConvertOnCalendar(FCalendars[c], AValue, AFrom);
      if Result.Kind <> cvkNone then Exit;
    end;
    { THE MATRICES, last (registered after the calendar, both non-series
      box creators) [Batch 147] }
    target := FinderMatrix(pf);
    if (target >= 0) and (target <= High(FMatrices)) and (FMatrices[target] <> nil) then
    begin
      Result := ConvertOnMatrix(FMatrices[target], AValue, AOpt, AFrom);
      if Result.Kind <> cvkNone then Exit;
    end;
  except
    on ETyConvertNull do
    begin
      Result.Kind := cvkError;
      Result.Values := nil;
    end;
  end;
end;

{ containPixel for a series: its coordinate system's containPoint -- a
  cartesian's area, a graph's, tree's or sankey's view; a calendar's and a
  radar's are always false -- or, with none, its view's: a pie's ring of
  its first item }
{ Polar.convertToPixel / convertFromPixel: dataToPoint of [radius, angle],
  or pointToData of a pixel [Batch 111] }
function TTyCustomAdvanceChart.ConvertOnPolar(APolar: TTyPolar; AValue: TJSONData;
  AFrom: Boolean): TTyConvertResult;
begin
  if AFrom then Result := TyPolarFromPixel(APolar, AValue)
  else Result := TyPolarToPixel(APolar, AValue);
end;

function TTyCustomAdvanceChart.ContainSeries(ASeriesIndex: Integer; APoint: TJSONData): Boolean;
var
  slot, k: Integer;
  b: TTySeriesBinding;
  pt: TTyPointF;
  bx: TTyXYWH;
  dx, dy, r: Double;
begin
  Result := False;
  slot := SlotOfSeries(ASeriesIndex);
  if slot < 0 then Exit;
  b := FBindings[slot];
  if b.Cart <> nil then Exit(TyCartesianContainJson(b.Cart, APoint));
  { a polar's containPoint [Batch 113] }
  if b.Polar <> nil then Exit(TyPolarContainJson(TTyPolar(b.Polar), APoint));
  { a single axis' [Batch 118] }
  if b.Single <> nil then Exit(TySingleContainJson(TTySingle(b.Single), APoint));
  { a parallel's containPoint [Batch 128] }
  if b.Parallel is TTyParallel then
    Exit(TyParallelContainJson(TTyParallel(b.Parallel), APoint));
  { A SERIES ON A MATRIX per item: the matrix's containPoint, its rect
    edges included; a pie or a funnel laid out in a cell has no coordinate
    system and its view answers [Batch 147] }
  if (b.MatrixIndex >= 0) and not b.MatrixBox then
  begin
    if (b.MatrixIndex <= High(FMatrices)) and (FMatrices[b.MatrixIndex] <> nil) then
      Exit(FMatrices[b.MatrixIndex].ContainPoint(TyJsonPoint(APoint)));
    Exit;
  end;
  if (b.CalendarIndex >= 0) or (b.RadarIndex >= 0) then Exit;
  pt := TyJsonPoint(APoint);
  if IsNan(pt.X) or IsNan(pt.Y) then Exit;
  if (b.SeriesType = TyGraphSeriesTypeName) and (slot <= High(FGraphs))
    and (FGraphs[slot] <> nil) then
    Exit(FGraphs[slot].ContainPoint(pt));
  if (b.SeriesType = TyTreeSeriesTypeName) and (slot <= High(FTreeViews))
    and (FTreeViews[slot] <> nil) then
    Exit(FTreeViews[slot].ContainPoint(pt));
  { a sankey's View: its box through the roam's overall transform [Batch 114:
    the box itself before -- there was no sankey roam] }
  if (b.SeriesType = TySankeySeriesTypeName) and (slot <= High(FSankeyViews))
    and (FSankeyViews[slot] <> nil) then
    Exit(FSankeyViews[slot].ContainPoint(pt));
  if (b.SeriesType = TySankeySeriesTypeName) and (slot <= High(FSankeys))
    and FSankeys[slot].Valid then
  begin
    bx := FSankeys[slot].Box;
    Exit((pt.X >= bx.X) and (pt.X <= bx.X + bx.W) and (pt.Y >= bx.Y)
      and (pt.Y <= bx.Y + bx.H));
  end;
  { A SUNBURST: the virtual root's layout, set by a drill and kept after
    it -- none before the first [Batch 115: never before] }
  if b.SeriesType = TySunburstSeriesTypeName then
  begin
    if (ASeriesIndex > High(FSunVirt)) or not FSunVirt[ASeriesIndex].Has then Exit;
    dx := pt.X - FSunVirt[ASeriesIndex].CX;
    dy := pt.Y - FSunVirt[ASeriesIndex].CY;
    r := Sqrt(dx * dx + dy * dy);
    Exit((r <= FSunVirt[ASeriesIndex].R) and (r >= FSunVirt[ASeriesIndex].R0));
  end;
  if (b.SeriesType = TyPieSeriesTypeName) and (slot <= High(FPies))
    and FPies[slot].Valid then
    for k := 0 to High(FPies[slot].Sectors) do
      if FPies[slot].Sectors[k].Index = 0 then
      begin
        { PieView.containPoint: the first item's layout, r0 <= d <= r }
        dx := pt.X - FPies[slot].Sectors[k].CX;
        dy := pt.Y - FPies[slot].Sectors[k].CY;
        if IsNan(dx) or IsNan(dy) then Exit;
        r := Sqrt(dx * dx + dy * dy);
        Exit((r <= FPies[slot].Sectors[k].R1) and (r >= FPies[slot].Sectors[k].R0));
      end;
end;

function TTyCustomAdvanceChart.ContainPixelData(AFinder, APoint: TJSONData): Boolean;
var
  pf: TTyParsedFinder;
  t, k, g: Integer;
  mt: string;
  gb: TTyGridBuild;
begin
  Result := False;
  ConvertReady;
  if (FBuild = nil) or (FOption = nil) then Exit;
  pf := TyParseFinder(AFinder, FOption.Keys);
  try
    for t := 0 to High(pf.Types) do
    begin
      mt := pf.Types[t].MainType;
      for k := 0 to High(pf.Types[t].Models) do
      begin
        if mt = 'series' then
        begin
          if ContainSeries(pf.Types[t].Models[k], APoint) then Exit(True);
        end
        else if mt = 'grid' then
        begin
          { Grid.containPoint: its first cartesian's }
          for g := 0 to FBuild.GridCount - 1 do
          begin
            gb := FBuild.Grid(g);
            if (gb.ComponentIndex = pf.Types[t].Models[k]) and (gb.CartesianCount > 0)
              and TyCartesianContainJson(gb.CartesianByIndex(0), APoint) then
              Exit(True);
          end;
        end
        { Polar.containPoint: the radius and the angle each in their
          extent [Batch 111] }
        else if mt = 'polar' then
        begin
          g := pf.Types[t].Models[k];
          if (g >= 0) and (g <= High(FPolars)) and (FPolars[g] <> nil)
            and TyPolarContainJson(FPolars[g], APoint) then
            Exit(True);
        end
        { Single.containPoint [Batch 118] }
        else if mt = TySingleCoordSysName then
        begin
          g := pf.Types[t].Models[k];
          if (g >= 0) and (g <= High(FSingles)) and (FSingles[g] <> nil)
            and TySingleContainJson(FSingles[g], APoint) then
            Exit(True);
        end
        { Parallel.containPoint, asked by the parallel and by each of its
          axes (the axis model carries its coordinate system) [Batch 128] }
        else if mt = 'parallel' then
        begin
          g := pf.Types[t].Models[k];
          if (g >= 0) and (g <= High(FParallels)) and (FParallels[g] <> nil)
            and TyParallelContainJson(FParallels[g], APoint) then
            Exit(True);
        end
        else if mt = 'parallelAxis' then
        begin
          g := ParallelOfAxis(pf.Types[t].Models[k]);
          if (g >= 0) and TyParallelContainJson(FParallels[g], APoint) then
            Exit(True);
        end
        { Matrix.containPoint: its rect, edges included [Batch 147] }
        else if mt = TyMatrixCoordSysName then
        begin
          g := pf.Types[t].Models[k];
          if (g >= 0) and (g <= High(FMatrices)) and (FMatrices[g] <> nil)
            and FMatrices[g].ContainPoint(TyJsonPoint(APoint)) then
            Exit(True);
        end
        { Geo.containPoint: the data rect through the overall matrix
          [Batch 146] }
        else if mt = 'geo' then
        begin
          g := pf.Types[t].Models[k];
          if (g >= 0) and (g <= High(FGeos)) and (FGeos[g] <> nil)
            and FGeos[g].ContainPoint(TyJsonPoint(APoint)) then
            Exit(True);
        end;
        { a calendar's and a radar's containPoint are not implemented
          upstream (false); an axis has no coordinate system }
      end;
    end;
  except
    { upstream throws where it indexes a null point }
    on ETyConvertNull do Result := False;
  end;
end;

function TTyCustomAdvanceChart.ConvertToPixelData(AFinder, AValue: TJSONData;
  AOpt: TJSONData): TTyConvertResult;
begin
  Result := ConvertDispatch(AFinder, AValue, False, AOpt);
end;

function TTyCustomAdvanceChart.ConvertFromPixelData(AFinder, AValue: TJSONData;
  AOpt: TJSONData): TTyConvertResult;
begin
  Result := ConvertDispatch(AFinder, AValue, True, AOpt);
end;

function TTyCustomAdvanceChart.FinderMatrix(const AF: TTyParsedFinder): Integer;
var s, slot: Integer;
begin
  Result := TyFinderModel(AF, TyMatrixCoordSysName);
  if Result >= 0 then Exit;
  s := TyFinderModel(AF, 'series');
  if s < 0 then Exit;
  slot := SlotOfSeries(s);
  if (slot >= 0) and (FBindings[slot].MatrixIndex >= 0) and not FBindings[slot].MatrixBox then
    Result := FBindings[slot].MatrixIndex
  { a canvas type with usage 'data': the matrix is its coordinateSystem all
    the same [Batch 154] }
  else if (slot >= 0) and FBindings[slot].HasDataMatrix then
    Result := FBindings[slot].DataMatrix;
end;

function TTyCustomAdvanceChart.ConvertOnMatrix(AMatrix: TTyMatrix; AValue, AOpt: TJSONData;
  AFrom: Boolean): TTyConvertResult;
var
  clamp: TTyMatrixClamp;
  pt: TTyPointF;
  x, y: Double;
  r: TTyXYWH;
  loc: TTyMatrixLocRange;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  clamp := TyMatrixClampOfOpt(AOpt);
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    if AFrom then
    begin
      { pointToData: each coordinate on its own -- upstream indexes the
        pixel, so a null pixel throws }
      pt := TyJsonPoint(AValue);
      AMatrix.PointToDataClamp(pt, clamp, x, y);
      Exit(TyConvertXY(x, y));
    end;
    { dataToPoint: the centre of dataToLayout; never nothing, [NaN, NaN]
      at worst }
    TyMatrixLayoutJson(AMatrix, AValue, clamp, r, loc, TyMatrixIgnoreMergeOfOpt(AOpt));
    Result := TyConvertXY(r.X + r.W / 2, r.Y + r.H / 2);
  finally
    ConvertUnmask(mask);
  end;
end;

function TTyCustomAdvanceChart.ConvertToLayoutData(AFinder, AValue: TJSONData;
  AOpt: TJSONData): TTyConvertLayout;
var
  pf: TTyParsedFinder;
  s, slot, c, target: Integer;
  v, own: TJSONData;
  dv: TTyDataValue;
  rc, cc: TTyXYWH;
  loc: TTyMatrixLocRange;
  mask: TFPUExceptionMask;
begin
  Result := Default(TTyConvertLayout);
  ConvertReady;
  if (FBuild = nil) or (FOption = nil) then Exit;
  pf := TyParseFinder(AFinder, FOption.Keys);
  own := nil;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
  try
    s := TyFinderModel(pf, 'series');
    { THE CALENDARS: dataToLayout of the value (its first element when an
      array), clamped to the range -- a day's cell and its content rect }
    for c := 0 to High(FCalendars) do
    begin
      if FCalendars[c] = nil then Continue;
      target := TyFinderModel(pf, 'calendar');
      if (target < 0) and (s >= 0) then
      begin
        slot := SlotOfSeries(s);
        if slot >= 0 then target := FBindings[slot].CalendarIndex;
      end;
      if target <> c then Continue;
      v := AValue;
      if TyJsonIsArray(AValue) then v := TyJsonElement(AValue, 0, own);
      dv := Default(TTyDataValue);
      dv.Kind := dvkNone;
      if not TyJsonNullish(v) then
      begin
        if v.JSONType = jtString then dv := TyDataText(v.AsString)
        else dv := TyDataNum(TyJsonToNumber(v));
      end;
      FCalendars[c].DateLayoutXYWH(FCalendars[c].ParseDate(dv), True, rc, cc);
      Result.Valid := True;
      Result.Rect := rc;
      Result.HasContentRect := True;
      Result.ContentRect := cc;
      Exit;
    end;
    { THE MATRICES: the cells the coord covers }
    target := FinderMatrix(pf);
    if (target >= 0) and (target <= High(FMatrices)) and (FMatrices[target] <> nil) then
    begin
      TyMatrixLayoutJson(FMatrices[target], AValue, TyMatrixClampOfOpt(AOpt), rc, loc,
        TyMatrixIgnoreMergeOfOpt(AOpt));
      Result.Valid := True;
      Result.Rect := rc;
      Result.HasLocatorRange := True;
      Result.LocatorRange[0][0] := loc[0][0];
      Result.LocatorRange[0][1] := loc[0][1];
      Result.LocatorRange[1][0] := loc[1][0];
      Result.LocatorRange[1][1] := loc[1][1];
    end;
  except
    on ETyConvertNull do Result := Default(TTyConvertLayout);
  end;
  finally
    own.Free;
    ConvertUnmask(mask);
  end;
end;

{ The finder text: JSON, or -- written bare -- a main type's name }
function ConvertParse(const AText: string; ABareWord: Boolean): TJSONData;
var
  nLine, nCol: Integer;
  t: string;
begin
  Result := nil;
  if TyJsonNestingExceeds(AText, TyOptionMaxNesting, nLine, nCol) then Exit;
  try
    Result := GetJSON(NulSafeJson(AText));
    NulRestore(Result);
  except
    Result := nil;
  end;
  if (Result = nil) and ABareWord then
  begin
    t := Trim(AText);
    if t <> '' then Result := TJSONString.Create(t);
  end;
end;

{ JSON.stringify of a number: null where it is not finite }
function ConvertNumJson(A: Double): string;
begin
  if IsNan(A) or IsInfinite(A) then Result := 'null'
  else Result := TyJsNumberToString(A);
end;

function ConvertResultJson(const AR: TTyConvertResult): string;
var i: Integer;
begin
  case AR.Kind of
    cvkNumber: Result := ConvertNumJson(AR.Values[0]);
    cvkArray:
      begin
        Result := '[';
        for i := 0 to High(AR.Values) do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + ConvertNumJson(AR.Values[i]);
        end;
        Result := Result + ']';
      end;
  else
    Result := '';
  end;
end;

function TTyCustomAdvanceChart.ConvertToPixel(const AFinderJson, AValueJson: string): string;
var f, v: TJSONData;
begin
  Result := '';
  f := ConvertParse(AFinderJson, True);
  v := ConvertParse(AValueJson, False);
  try
    if (f = nil) or (v = nil) then Exit;
    Result := ConvertResultJson(ConvertToPixelData(f, v));
  finally
    f.Free;
    v.Free;
  end;
end;

function TTyCustomAdvanceChart.ConvertToPixel(const AFinderJson, AValueJson,
  AOptJson: string): string;
var f, v, o: TJSONData;
begin
  Result := '';
  f := ConvertParse(AFinderJson, True);
  v := ConvertParse(AValueJson, False);
  o := ConvertParse(AOptJson, False);
  try
    if (f = nil) or (v = nil) then Exit;
    Result := ConvertResultJson(ConvertToPixelData(f, v, o));
  finally
    f.Free;
    v.Free;
    o.Free;
  end;
end;

function TTyCustomAdvanceChart.ConvertFromPixel(const AFinderJson, APixelJson,
  AOptJson: string): string;
var f, v, o: TJSONData;
begin
  Result := '';
  f := ConvertParse(AFinderJson, True);
  v := ConvertParse(APixelJson, False);
  o := ConvertParse(AOptJson, False);
  try
    if (f = nil) or (v = nil) then Exit;
    Result := ConvertResultJson(ConvertFromPixelData(f, v, o));
  finally
    f.Free;
    v.Free;
    o.Free;
  end;
end;

function TTyCustomAdvanceChart.ConvertToLayout(const AFinderJson, AValueJson: string;
  const AOptJson: string): string;
var
  f, v, o: TJSONData;
  r: TTyConvertLayout;

  function RectJson(const R_: TTyXYWH): string;
  begin
    Result := '{"x":' + ConvertNumJson(R_.X) + ',"y":' + ConvertNumJson(R_.Y)
      + ',"width":' + ConvertNumJson(R_.W) + ',"height":' + ConvertNumJson(R_.H) + '}';
  end;

begin
  Result := '';
  f := ConvertParse(AFinderJson, True);
  v := ConvertParse(AValueJson, False);
  o := ConvertParse(AOptJson, False);
  try
    if (f = nil) or (v = nil) then Exit;
    r := ConvertToLayoutData(f, v, o);
    if not r.Valid then Exit;
    Result := '{"rect":' + RectJson(r.Rect);
    if r.HasContentRect then Result := Result + ',"contentRect":' + RectJson(r.ContentRect);
    if r.HasLocatorRange then
      Result := Result + ',"matrixXYLocatorRange":[[' + ConvertNumJson(r.LocatorRange[0][0])
        + ',' + ConvertNumJson(r.LocatorRange[0][1]) + '],[' + ConvertNumJson(r.LocatorRange[1][0])
        + ',' + ConvertNumJson(r.LocatorRange[1][1]) + ']]';
    Result := Result + '}';
  finally
    f.Free;
    v.Free;
    o.Free;
  end;
end;

function TTyCustomAdvanceChart.ConvertToPixel(const AFinderJson: string;
  const AValue: array of Double): TTyConvertResult;
var
  f: TJSONData;
  v: TJSONArray;
  i: Integer;
begin
  Result := TyConvertNone;
  f := ConvertParse(AFinderJson, True);
  v := TJSONArray.Create;
  try
    if f = nil then Exit;
    for i := 0 to High(AValue) do v.Add(TJSONFloatNumber.Create(AValue[i]));
    Result := ConvertToPixelData(f, v);
  finally
    f.Free;
    v.Free;
  end;
end;

function TTyCustomAdvanceChart.ConvertToPixel(const AFinderJson: string;
  AValue: Double): TTyConvertResult;
var f, v: TJSONData;
begin
  Result := TyConvertNone;
  f := ConvertParse(AFinderJson, True);
  v := TJSONFloatNumber.Create(AValue);
  try
    if f = nil then Exit;
    Result := ConvertToPixelData(f, v);
  finally
    f.Free;
    v.Free;
  end;
end;

function TTyCustomAdvanceChart.ConvertFromPixel(const AFinderJson, APixelJson: string): string;
var f, v: TJSONData;
begin
  Result := '';
  f := ConvertParse(AFinderJson, True);
  v := ConvertParse(APixelJson, False);
  try
    if (f = nil) or (v = nil) then Exit;
    Result := ConvertResultJson(ConvertFromPixelData(f, v));
  finally
    f.Free;
    v.Free;
  end;
end;

function TTyCustomAdvanceChart.ConvertFromPixel(const AFinderJson: string;
  AX, AY: Double): TTyConvertResult;
var
  f: TJSONData;
  v: TJSONArray;
begin
  Result := TyConvertNone;
  f := ConvertParse(AFinderJson, True);
  v := TJSONArray.Create;
  try
    if f = nil then Exit;
    v.Add(TJSONFloatNumber.Create(AX));
    v.Add(TJSONFloatNumber.Create(AY));
    Result := ConvertFromPixelData(f, v);
  finally
    f.Free;
    v.Free;
  end;
end;

function TTyCustomAdvanceChart.ConvertFromPixel(const AFinderJson: string;
  AValue: Double): TTyConvertResult;
var f, v: TJSONData;
begin
  Result := TyConvertNone;
  f := ConvertParse(AFinderJson, True);
  v := TJSONFloatNumber.Create(AValue);
  try
    if f = nil then Exit;
    Result := ConvertFromPixelData(f, v);
  finally
    f.Free;
    v.Free;
  end;
end;

function TTyCustomAdvanceChart.ContainPixel(const AFinderJson, APointJson: string): Boolean;
var f, v: TJSONData;
begin
  Result := False;
  f := ConvertParse(AFinderJson, True);
  v := ConvertParse(APointJson, False);
  try
    if (f = nil) or (v = nil) then Exit;
    Result := ContainPixelData(f, v);
  finally
    f.Free;
    v.Free;
  end;
end;

function TTyCustomAdvanceChart.ContainPixel(const AFinderJson: string; AX, AY: Double): Boolean;
var
  f: TJSONData;
  v: TJSONArray;
begin
  Result := False;
  f := ConvertParse(AFinderJson, True);
  v := TJSONArray.Create;
  try
    if f = nil then Exit;
    v.Add(TJSONFloatNumber.Create(AX));
    v.Add(TJSONFloatNumber.Create(AY));
    Result := ContainPixelData(f, v);
  finally
    f.Free;
    v.Free;
  end;
end;

{ dragNode, sankeyRoam, graphRoam [Batch 114]: the series the payload's
  query names (seriesIndex / seriesId / seriesName; none: every series of the
  type), each the action's own handler }
function TTyCustomAdvanceChart.DoViewAction(const AType: string; APayload: TJSONObject): Boolean;
var
  series: TTyIntegerArray;
  ev, anim: TJSONObject;
  k, n: Integer;
  d: TJSONData;
  rp: TTyGraphRoamPayload;
  hasX, hasY, hasIdx: Boolean;
  lx, ly: Double;
  idx: Integer;

  function Num(const AKey: string; out AV: Double): Boolean;
  var dd: TJSONData;
  begin
    dd := APayload.Find(AKey);
    Result := (dd <> nil) and (dd.JSONType = jtNumber);
    if Result then AV := dd.AsFloat else AV := NaN;
  end;

  function Queried: Boolean;
  begin
    Result := (APayload.Find('seriesIndex') <> nil) or (APayload.Find('seriesId') <> nil)
      or (APayload.Find('seriesName') <> nil);
  end;

begin
  Result := False;
  if Queried then series := MatchSeries(APayload)
  else
  begin
    SetLength(series, 1);
    series[0] := -1;
  end;
  n := Length(series);
  { [F4b] AS AN ACTION: the helpers' own event and `updated` are the
    dispatch's -- one event, a copy of the payload (a roam's with the
    animation payloadDisableAnimation wrote), then the tail's `updated` }
  Inc(FViewActionDepth);
  try
    if AType = 'dragNode' then
    begin
      hasX := Num('localX', lx);
      hasY := Num('localY', ly);
      d := APayload.Find('dataIndex');
      hasIdx := (d <> nil) and (d.JSONType = jtNumber) and (Frac(d.AsFloat) = 0);
      if not hasIdx then Exit;
      idx := Trunc(d.AsFloat);
      for k := 0 to n - 1 do
        if SankeyDragNode(series[k], idx, hasX, lx, hasY, ly) then Result := True;
      { update: 'update', inside the dispatch -- its visual stage's
        brushSelect waits with the rest }
      if Result then FullUpdate;
    end
    else
    begin
      rp := Default(TTyGraphRoamPayload);
      rp.HasPan := Num('dx', rp.DX) and Num('dy', rp.DY);
      rp.HasZoom := Num('zoom', rp.Zoom);
      Num('originX', rp.OriginX);
      Num('originY', rp.OriginY);
      if not (rp.HasPan or rp.HasZoom) then Exit;
      for k := 0 to n - 1 do
      begin
        rp.SeriesIndex := series[k];
        if AType = 'sankeyRoam' then
        begin
          if SankeyDispatchRoam(rp) then Result := True;
        end
        else if GraphDispatchRoam(rp) then Result := True;
      end;
    end;
  finally
    Dec(FViewActionDepth);
  end;
  if not Result then Exit;
  ev := TJSONObject(APayload.Clone);
  try
    if AType <> 'dragNode' then
    begin
      anim := TJSONObject.Create;
      anim.Add('duration', 0);
      if ev.Find('animation') <> nil then ev.Elements['animation'] := anim
      else ev.Add('animation', anim);
    end;
    ev.Strings['type'] := LowerCase(AType);
    EmitPayloadEvent(LowerCase(AType), VmJsJson(ev), ev);
  finally
    ev.Free;
  end;
end;

function TTyCustomAdvanceChart.DispatchAction(const APayloadJson: string;
  ASilent: Boolean): Boolean;
begin
  if not ASilent then Exit(DispatchAction(APayloadJson));
  Inc(FEvSilent);
  try
    Result := DispatchAction(APayloadJson);
  finally
    Dec(FEvSilent);
  end;
end;

function TTyCustomAdvanceChart.DispatchAction(const APayloadJson: string): Boolean;
var
  d: TJSONData;
  nLine, nCol: Integer;
begin
  Result := False;
  TbFrame;
  { too deep is no payload: refused before fpjson can recurse into it }
  if TyJsonNestingExceeds(APayloadJson, TyOptionMaxNesting, nLine, nCol) then Exit;
  try
    d := GetJSON(NulSafeJson(APayloadJson));
    NulRestore(d);
  except
    d := nil;
  end;
  if not (d is TJSONObject) then
  begin
    d.Free;
    Exit;
  end;
  Result := DispatchActionObject(TJSONObject(d));
end;

{ the dispatch itself, of a payload parsed or built (a view's own action
  keeps its numbers as they are -- no text in between) [Batch 130]; the
  actions dispatched while it ran, then `updated` [Batch 153] }
function TTyCustomAdvanceChart.DispatchActionObject(APayload: TJSONObject): Boolean;
var n: Integer;
  tp: TJSONData;
begin
  { [F4b] dispatchAction in the rendering procedure (IN_EC_CYCLE): the
    payload waits in _pendingActions and runs after the action that is
    running, its event before `updated` -- whatever the action }
  if FActCycle > 0 then
  begin
    tp := APayload.Find('type');
    Result := (tp <> nil) and (tp.JSONType = jtString);
    n := Length(FActPending);
    SetLength(FActPending, n + 1);
    FActPending[n] := Default(TTyTipAct);
    FActPending[n].Payload := APayload;
    Exit;
  end;
  Result := DispatchActionCore(APayload);
  { the pending brushSelect, then triggerUpdatedEvent [Batch 127] }
  if FBrushActDepth = 0 then BrushFlush;
  { flushPendingActions: what the actions dispatched while they ran
    [Batch 153] -- [F4b] also from a dispatch a handler made: its flush
    takes what the outer one left waiting }
  if FActCycle = 0 then ActFlushPending;
  FActHits.Hits := nil;
  FActHits.HasHits := False;
  { every dispatch ends with triggerUpdatedEvent [Batch 97] }
  if Result then EmitUpdated;
  { the actions the update's render left pending: a bar race's init sort
    [Batch 135] }
  RtFlushQueue;
end;

function TTyCustomAdvanceChart.DispatchActionCore(APayload: TJSONObject): Boolean;
var
  tp: TJSONData;
  p: TJSONObject;
  t, savedAction: string;
begin
  Result := False;
  p := APayload;
  { an action's brushselected comes after its own event [Batch 127] }
  Inc(FBrushActDepth);
  { [F4b] IN_EC_CYCLE for every action, its update included: what it
    dispatches waits (DispatchActionObject queues it); its event is
    published outside the cycle (EmitPayloadEvent) }
  Inc(FActCycle);
  try
    tp := p.Find('type');
    if (tp = nil) or (tp.JSONType <> jtString) then Exit;
    t := tp.AsString;
    { the update this action runs renders for it: renderItem's actionType
      [Batch 123] }
    savedAction := FCustomAction;
    FCustomAction := t;
    { THE ACTIONS WHOSE UPDATE RUNS THE VISUAL STAGE with a payload: the
      brush's brushSelect is dispatched by it [Batch 127] }
    if (t = 'selectDataRange') or (t = 'legendToggleSelect') or (t = 'legendSelect')
      or (t = 'legendUnSelect') or (t = 'legendAllSelect') or (t = 'legendInverseSelect')
      or (t = 'legendScroll') or (t = 'dragNode') or (t = 'restore')
      or (t = 'changeMagicType') or (t = 'changeDataView')
      { the timeline's two (prepareAndUpdate, update) [milestone D5-D8] }
      or (t = 'timelineChange') or (t = 'timelinePlayChange')
      { [F4b] updateView (sunburst, treemap), the axis breaks' and the
        legacy selects' update }
      or (t = 'sunburstRootToNode') or (t = 'treemapZoomToNode')
      or (t = 'treemapRootToNode') or (t = 'treemapMove') or (t = 'treemapRender')
      or (t = 'expandAxisBreak') or (t = 'collapseAxisBreak') or (t = 'toggleAxisBreak')
      or (t = 'mapToggleSelect') or (t = 'pieToggleSelect') or (t = 'mapSelect')
      or (t = 'pieSelect') or (t = 'mapUnSelect') or (t = 'pieUnSelect')
      { [F3d] }
      or (t = 'treeExpandAndCollapse') then
      FBrushPayload := True;
    { A BATCH -- `if (payload.batch)`, a truthy one -- of highlight /
      downplay [Batch 116]: each item over the payload, one event; of the
      types DoBatchAction takes [Batch 141]; any other batch is not taken }
    if JsTruthy(p.Find('batch')) then
    begin
      if (t = 'highlight') or (t = 'downplay') then
      begin
        DoHighDownBatch(p);
        Result := True;
      end
      else Result := DoBatchAction(p);
    end
    { the dataZoom action as a payload [Batch 141] }
    else if t = 'dataZoom' then
      Result := DoDataZoomAction(p)
    { brushSelect: no update, its event a copy of the payload [Batch 141] }
    else if t = 'brushSelect' then
    begin
      EmitPayloadEvent('brushselected', CopyWithType(p, 'brushselected'));
      Result := True;
    end
    { the axis pointer's and the tooltip's [Batch 153] }
    else if t = 'updateAxisPointer' then
    begin
      DoUpdateAxisPointer(p);
      Result := True;
    end
    else if t = 'showTip' then
    begin
      DoShowTip(p);
      Result := True;
    end
    else if t = 'hideTip' then
    begin
      DoHideTip(p);
      Result := True;
    end
    else if t = 'selectDataRange' then
    begin
      { [Batch 116] }
      DoSelectDataRange(p);
      Result := True;
    end
    else if (t = 'select') or (t = 'unselect') or (t = 'toggleSelect') then
    begin
      DoSelectAction(p);
      Result := True;
    end
    { the legacy data selection actions [Batch 152] }
    else if (t = 'mapToggleSelect') or (t = 'pieToggleSelect') then
    begin
      DoLegacySelect(p, Copy(t, 1, 3), 'toggleSelect');
      Result := True;
    end
    else if (t = 'mapSelect') or (t = 'pieSelect') then
    begin
      DoLegacySelect(p, Copy(t, 1, 3), 'select');
      Result := True;
    end
    else if (t = 'mapUnSelect') or (t = 'pieUnSelect') then
    begin
      DoLegacySelect(p, Copy(t, 1, 3), 'unselect');
      Result := True;
    end
    else if (t = 'highlight') or (t = 'downplay') then
    begin
      { [Batch 148] a finder naming a geo first: the component's own
        highlight (findComponentHighDownDispatchers) }
      if GeoFinderFirst(p) then DoGeoHighDown(p)
      else DoHighDownAction(p);
      Result := True;
    end
    { the geo's select actions [Batch 148] }
    else if (t = 'geoToggleSelect') or (t = 'geoSelect') or (t = 'geoUnSelect') then
    begin
      DoGeoSelectAction(p, t);
      Result := True;
    end
    else if (t = 'legendToggleSelect') or (t = 'legendSelect')
      or (t = 'legendUnSelect') or (t = 'legendAllSelect')
      or (t = 'legendInverseSelect') then
    begin
      DoLegendAction(p);
      Result := True;
    end
    else if t = 'legendScroll' then
    begin
      { [Batch 98] }
      DoLegendScroll(p);
      Result := True;
    end
    else if t = 'sunburstRootToNode' then
      { [Batch 115] }
      Result := DoSunAction(p)
    { [F3d] the tree's expand and collapse }
    else if t = 'treeExpandAndCollapse' then
      Result := DoTreeToggleAction(p)
    else if (t = 'treemapZoomToNode') or (t = 'treemapRootToNode')
      or (t = 'treemapMove') or (t = 'treemapRender') then
      Result := DoTreemapAction(t, p)
    else if (t = 'dragNode') or (t = 'sankeyRoam') or (t = 'graphRoam') then
      { [Batch 114] }
      Result := DoViewAction(t, p)
    { the geo's roam [Batch 150] }
    else if t = 'geoRoam' then
      Result := DoGeoRoamAction(p)
    { the toolbox's actions [Batch 125] }
    else if t = 'restore' then
    begin
      TbDoRestore(p);
      Result := True;
    end
    else if t = 'changeMagicType' then
    begin
      TbDoMagic(p);
      Result := True;
    end
    else if t = 'changeDataView' then
    begin
      TbDoDataView(p);
      Result := True;
    end
    else if t = 'takeGlobalCursor' then
    begin
      TbDoTakeCursor(p);
      Result := True;
    end
    { the brush's actions [Batch 126] }
    else if t = 'brush' then
    begin
      BrushDoAction(p);
      Result := True;
    end
    else if t = 'brushEnd' then
    begin
      BrushDoEnd(p);
      Result := True;
    end
    { the timeline's actions [Batch 129] }
    else if t = 'timelineChange' then
    begin
      DoTimelineChange(p);
      Result := True;
    end
    else if t = 'timelinePlayChange' then
    begin
      DoTimelinePlayChange(p);
      Result := True;
    end
    { the parallel axes' area select, which the brush feature's clear
      dispatches: the update and the event [Batch 127], and the queried
      parallelAxis models' active intervals [Batch 128] }
    else if t = 'axisAreaSelect' then
    begin
      BrushDoAxisAreaSelect(p);
      Result := True;
    end
    { the parallel axis expansion: the queried parallel models take the
      keys the payload owns [Batch 140] }
    else if t = 'parallelAxisExpand' then
    begin
      DoParallelAxisExpand(p);
      Result := True;
    end
    { the axis breaks' actions [Batch 132] }
    else if (t = 'expandAxisBreak') or (t = 'collapseAxisBreak')
      or (t = 'toggleAxisBreak') then
    begin
      DoAxisBreakAction(p);
      Result := True;
    end
    { a bar race's [Batch 135] }
    else if t = 'changeAxisOrder' then
    begin
      DoChangeAxisOrder(p);
      Result := True;
    end;
  finally
    p.Free;
    FCustomAction := savedAction;
    Dec(FBrushActDepth);
    Dec(FActCycle);
  end;
end;

{ ==================== echarts.connect, batch actions [Batch 141] ==================== }

procedure TTyCustomAdvanceChart.ConnectBroadcast(const AEventType, APayloadJson: string;
  AObj: TJSONObject);
var
  act: string;
  d: TJSONData;
  ev: TJSONObject;
  others: array of TTyCustomAdvanceChart;
  ch: TTyCustomAdvanceChart;
  i, n, nLine, nCol: Integer;
begin
  { connectedGroups[chart.group] and not pending }
  if (FGroup = '') or (GTyCharts = nil) or not TyChartGroupConnected(FGroup) then Exit;
  if FConnectStatus = cConnectPending then Exit;
  act := TyConnectActionOf(AEventType);
  if act = '' then Exit;
  if AObj <> nil then
    ev := TJSONObject(AObj.Clone)
  else
  begin
    if TyJsonNestingExceeds(APayloadJson, TyOptionMaxNesting, nLine, nCol) then Exit;
    try
      d := GetJSON(NulSafeJson(APayloadJson));
      NulRestore(d);
    except
      d := nil;
    end;
    if not (d is TJSONObject) then
    begin
      d.Free;
      Exit;
    end;
    ev := TJSONObject(d);
  end;
  try
    if JsTruthy(ev.Find('escapeConnect')) then Exit;
    { makeActionFromEvent: the event's copy, its type the action's }
    ev.Strings['type'] := act;
    others := nil;
    for i := 0 to GTyCharts.Count - 1 do
    begin
      ch := TTyCustomAdvanceChart(GTyCharts[i]);
      if (ch = Self) or (ch.FGroup <> FGroup) then Continue;
      n := Length(others);
      SetLength(others, n + 1);
      others[n] := ch;
    end;
    { every other chart pending first, so none of them sends its own event
      of this action on; then each dispatches the action; then all updated }
    for i := 0 to High(others) do others[i].FConnectStatus := cConnectPending;
    for i := 0 to High(others) do
    begin
      others[i].TbFrame;
      others[i].DispatchActionObject(TJSONObject(ev.Clone));
    end;
    for i := 0 to High(others) do others[i].FConnectStatus := cConnectUpdated;
  finally
    ev.Free;
  end;
end;

function TTyCustomAdvanceChart.DoBatchAction(APayload: TJSONObject): Boolean;
var
  t, lt, ev, js, one: string;
  items: TJSONArray;
  i: Integer;
  o: TJSONObject;
begin
  Result := False;
  t := APayload.Strings['type'];
  if (t = 'legendToggleSelect') or (t = 'legendSelect') or (t = 'legendUnSelect')
    or (t = 'legendAllSelect') or (t = 'legendInverseSelect') then
  begin
    { each item's action and its own result; ONE update; one event }
    if t = 'legendToggleSelect' then ev := 'legendselectchanged'
    else if t = 'legendSelect' then ev := 'legendselected'
    else if t = 'legendUnSelect' then ev := 'legendunselected'
    else if t = 'legendAllSelect' then ev := 'legendselectall'
    else ev := 'legendinverseselect';
    js := '';
    items := BatchItemsOf(APayload);
    try
      for i := 0 to items.Count - 1 do
      begin
        one := LegendActionApply(TJSONObject(items.Items[i]), t, ev);
        if i > 0 then js := js + ',';
        js := js + one;
      end;
    finally
      items.Free;
    end;
    FullUpdate;
    EmitPayloadEvent(ev, BatchEventHead(APayload, ev) + js + ']}');
    Exit(True);
  end;
  if (t = 'select') or (t = 'unselect') or (t = 'toggleSelect') then
  begin
    lt := LowerCase(t);
    js := '';
    items := BatchItemsOf(APayload);
    try
      for i := 0 to items.Count - 1 do SelApply(TJSONObject(items.Items[i]), t);
      { THE REFINE QUIRK: with a refineEvent the action result is not the
        event, and eventObj -- the first item's copy -- is never reset, so
        every entry of the batch is that one object }
      if items.Count > 0 then
      begin
        o := TJSONObject(items.Items[0].Clone);
        try
          o.Strings['type'] := lt;
          one := VmJsJson(o);
        finally
          o.Free;
        end;
        for i := 0 to items.Count - 1 do
        begin
          if i > 0 then js := js + ',';
          js := js + one;
        end;
      end;
    finally
      items.Free;
    end;
    SelPublish(APayload, BatchEventHead(APayload, lt) + js + ']}');
    Exit(True);
  end;
  if t = 'dataZoom' then Exit(DoDataZoomAction(APayload));
  if t = 'brushSelect' then
  begin
    js := BatchEventHead(APayload, 'brushselected');
    items := BatchItemsOf(APayload);
    try
      for i := 0 to items.Count - 1 do
      begin
        TJSONObject(items.Items[i]).Strings['type'] := 'brushselected';
        if i > 0 then js := js + ',';
        js := js + VmJsJson(items.Items[i]);
      end;
    finally
      items.Free;
    end;
    EmitPayloadEvent('brushselected', js + ']}');
    Exit(True);
  end;
  { [F4b] every other action }
  Result := DoBatchGeneric(APayload, t);
end;

{ [R2-E] the actions whose update is 'none' or a component's own
  (`component:method`, updateDirectly per item): doDispatchAction runs no
  update after the items, a batch of none included }
function TyBatchRunsNoUpdate(const AType: string): Boolean;
begin
  Result := (AType = 'brushEnd') or (AType = 'brushSelect') or (AType = 'graphRoam')
    or (AType = 'sankeyRoam') or (AType = 'treeRoam') or (AType = 'sunburstHighlight')
    or (AType = 'focusNodeAdjacency') or (AType = 'unfocusNodeAdjacency')
    or (AType = 'updateAxisPointer') or (AType = 'showTip') or (AType = 'hideTip')
    or (AType = 'geoToggleSelect') or (AType = 'geoSelect') or (AType = 'geoUnSelect');
end;

function TTyCustomAdvanceChart.DoBatchGeneric(APayload: TJSONObject;
  const AType: string): Boolean;
var
  ev, act, js, first: string;
  items: TJSONArray;
  i, k, before: Integer;
  refine: Boolean;
  savedType, savedRef: string;
  savedList, savedRefList, entries, refs: TTyStringArray;
  d: TJSONData;
  brk: TJSONArray;
  nLine, nCol: Integer;
  it: TJSONObject;
  tp: TJSONData;
  aasFirst: Integer;
begin
  Result := False;
  { the action's non-refined event: its entry in the connect table }
  ev := '';
  for i := 0 to TyConnectEventCount - 1 do
    if (TyConnectEventAt(i, act) <> '') and (act = AType) then
    begin
      ev := TyConnectEventAt(i, act);
      Break;
    end;
  if ev = '' then Exit;
  { the axis breaks' refineEvent: eventObj is never reset, every entry is
    the first item's copy; one refined event of every item's breaks }
  refine := (AType = 'expandAxisBreak') or (AType = 'collapseAxisBreak')
    or (AType = 'toggleAxisBreak');
  items := BatchItemsOf(APayload);
  savedType := FBatchCapType;
  savedRef := FBatchCapRefined;
  savedList := FBatchCapList;
  savedRefList := FBatchCapRef;
  entries := nil;
  refs := nil;
  FBatchCapType := ev;
  if refine then FBatchCapRefined := 'axisbreakchanged' else FBatchCapRefined := '';
  FBatchCapList := nil;
  FBatchCapRef := nil;
  Inc(FBatchCapDepth);
  Inc(FBatchDefer);
  FBatchDue := False;
  FBatchConvertDue := False;
  FBatchBrushHas := False;
  FBatchBrushJson := '';
  { no item at all: the update still runs (with the payload) -- here the
    one whose visual stage the brush hears
    [R2-E: and every other action's whose update is not none nor a
    component's own; its visual stage dispatches brushSelect too, but for
    geoRoam's updateTransform] }
  if (items.Count = 0) and (FBrushPayload or not TyBatchRunsNoUpdate(AType)) then
  begin
    if not FBrushPayload then FBrushPayload := AType <> 'geoRoam';
    FBatchDue := True;
    FBatchDuePayload := TyAnimNoOverride;
    FBatchDueHas := False;
  end;
  try
    first := '';
    if items.Count > 0 then first := CopyWithType(TJSONObject(items.Items[0]), ev);
    for i := 0 to items.Count - 1 do
    begin
      before := Length(FBatchCapList);
      { each item through the action, as doDispatchAction's map hands it:
        a copy of the item over the payload, its batch null }
      it := TJSONObject(items.Items[i].Clone);
      { the batch's action runs on every item, whatever type the item
        names -- a connected chart is sent items typed with the event's
        name ('expandaxisbreak'): the axis breaks' handler reads the item's
        type, and one it does not know changes no break (still reported) }
      if refine then
      begin
        tp := it.Find('type');
        if (tp <> nil) and (tp.JSONType = jtString) then FBreakActAs := tp.AsString
        else FBreakActAs := '';
        FBreakActAsSet := True;
        it.Strings['type'] := AType;
      end;
      try
        DispatchActionCore(it);
      finally
        FBreakActAsSet := False;
      end;
      { eventObj = actionResult || a copy of the batch item }
      SetLength(entries, Length(entries) + 1);
      if Length(FBatchCapList) > before then
        entries[High(entries)] := FBatchCapList[High(FBatchCapList)]
      else
        entries[High(entries)] := CopyWithType(TJSONObject(items.Items[i]), ev);
    end;
    refs := FBatchCapRef;
  finally
    Dec(FBatchCapDepth);
    Dec(FBatchDefer);
    FBatchCapType := savedType;
    FBatchCapRefined := savedRef;
    FBatchCapList := savedList;
    FBatchCapRef := savedRefList;
    items.Free;
  end;
  { THE UPDATE, once: updateMethods[update](payload) }
  FBatchBrushQueued := False;
  { [R2-E] the items' timeline merges: prepareAndUpdate renders once, from
    the render before the batch }
  if FBatchConvertDue and (FBatchDefer = 0) then
  begin
    FBatchConvertDue := False;
    FBatchDue := False;
    ConvertReady;
  end;
  if FBatchDue and (FBatchDefer = 0) then
  begin
    FBatchDue := False;
    if AType = 'axisAreaSelect' then
    begin
      { [R2-E] fromAxisAreaSelect with the OUTER payload: the update
        renders every parallelAxis view but the first that payload's query
        finds -- that one keeps the covers it had }
      ParallelAreaSelect(APayload, aasFirst, False);
      FParBrushSkip := aasFirst;
      FParBrushInAas := True;
      try
        FullUpdateWith(FBatchDuePayload, FBatchDueHas);
      finally
        FParBrushInAas := False;
      end;
    end
    else
      FullUpdateWith(FBatchDuePayload, FBatchDueHas);
  end;
  { the brushSelect the items' own updates asked for, when the one above
    gave none }
  if FBatchBrushHas and not FBatchBrushQueued and (FBatchDefer = 0) then
  begin
    SetLength(FActPending, Length(FActPending) + 1);
    FActPending[High(FActPending)] := Default(TTyTipAct);
    FActPending[High(FActPending)].EventJson := FBatchBrushJson;
  end;
  FBatchBrushHas := False;
  FBatchBrushJson := '';
  Result := True;
  if FEvSilent > 0 then Exit;
  js := BatchEventHead(APayload, ev);
  for i := 0 to High(entries) do
  begin
    if i > 0 then js := js + ',';
    if refine then js := js + first else js := js + entries[i];
  end;
  js := js + ']}';
  if not refine then
  begin
    EmitPayloadEvent(ev, js);
    Exit;
  end;
  { a refined action: the batch event goes to the connect listener only;
    the refined event once, its breaks every item's, fromActionPayload the
    batch's payload }
  ConnectBroadcast(ev, js, nil);
  js := '';
  for k := 0 to High(refs) do
  begin
    if TyJsonNestingExceeds(refs[k], TyOptionMaxNesting, nLine, nCol) then Continue;
    d := nil;
    try
      d := GetJSON(NulSafeJson(refs[k]));
      NulRestore(d);
    except
      d := nil;
    end;
    try
      if (d is TJSONObject) and (TJSONObject(d).Find('breaks') is TJSONArray) then
      begin
        brk := TJSONArray(TJSONObject(d).Find('breaks'));
        for i := 0 to brk.Count - 1 do
        begin
          if js <> '' then js := js + ',';
          js := js + VmJsJson(brk.Items[i]);
        end;
      end;
    finally
      d.Free;
    end;
  end;
  EmitPayloadEvent('axisbreakchanged', '{"type":"axisbreakchanged","breaks":['
    + js + '],"fromAction":"' + StringToJSONString(AType)
    + '","fromActionPayload":' + APayload.AsJSON + ',"escapeConnect":true}');
end;

function TTyCustomAdvanceChart.ConnectedRect: TTyConnectedRect;
var
  o: TPoint;
  s: Double;
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  s := 96 / ppi;
  { getBoundingClientRect: the place on the screen once there is a window,
    else the place in the top-level form }
  o := ClientOrigin;
  Result.Left := o.X * s;
  Result.Top := o.Y * s;
  Result.Width := Width * s;
  Result.Height := Height * s;
end;

function TTyCustomAdvanceChart.RenderConnectedToBitmap(const AOptsJson: string): TBGRABitmap;
var
  o: TTyChartExportOpts;
  charts: array of TTyCustomAdvanceChart;
  rects: TTyConnectedRectArray;
  bmps: array of TBGRABitmap;
  lay: TTyConnectedLayout;
  dpr: Double;
  i, n, w, h, ppi, nLine, nCol: Integer;
  root, cb: TJSONData;
  bg: TTyExportBg;
  P: TTyPainter;
  el: TTyChartElement;
begin
  ExportOptsOrRaise(AOptsJson, o);
  if (FGroup = '') or (GTyCharts = nil) or not TyChartGroupConnected(FGroup) then
    Exit(RenderExport(o));
  Result := nil;
  charts := nil;
  for i := 0 to GTyCharts.Count - 1 do
    if TTyCustomAdvanceChart(GTyCharts[i]).FGroup = FGroup then
    begin
      n := Length(charts);
      SetLength(charts, n + 1);
      charts[n] := TTyCustomAdvanceChart(GTyCharts[i]);
    end;
  n := Length(charts);
  { `opts.pixelRatio || this.getDevicePixelRatio()` }
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  if o.PixelRatio > 0 then dpr := o.PixelRatio else dpr := ppi / 96;
  SetLength(rects, n);
  SetLength(bmps, n);
  for i := 0 to n - 1 do bmps[i] := nil;
  try
    { each chart's renderToCanvas(clone(opts)), its own background and all }
    for i := 0 to n - 1 do
    begin
      rects[i] := charts[i].ConnectedRect;
      bmps[i] := charts[i].RenderExport(o);
    end;
    lay := TyConnectedLayoutOf(rects, dpr);
    { the canvas truncates the sizes it is given }
    if IsNan(lay.Width) or IsNan(lay.Height) or (lay.Width < 1) or (lay.Height < 1)
      or (lay.Width > TyExportMaxSide) or (lay.Height > TyExportMaxSide) then Exit;
    w := Trunc(lay.Width);
    h := Trunc(lay.Height);
    Result := TBGRABitmap.Create(w, h, BGRAPixelTransparent);
    { the background between the charts: a rect over the whole canvas,
      filled as zrender fills it -- 'none' is no fill }
    cb := nil;
    root := nil;
    if (Trim(AOptsJson) <> '')
      and not TyJsonNestingExceeds(AOptsJson, TyOptionMaxNesting, nLine, nCol) then
    begin
      try
        root := GetJSON(AOptsJson);
      except
        root := nil;
      end;
      if root is TJSONObject then cb := TJSONObject(root).Find('connectedBackgroundColor');
    end;
    try
      if TyJsTruthy(cb) and not ((cb.JSONType = jtString) and (cb.AsString = 'none')) then
      begin
        bg := TyExportBackgroundOf(cb);
        P := NewPainter;
        try
          P.BeginPaintOn(nil, Rect(0, 0, w, h), 96, Result);
          case bg.Kind of
            ebkSolid, ebkBlack:
              begin
                if bg.Kind = ebkBlack then bg.Color := $FF000000;
                P.BeginPath;
                P.RectPath(0, 0, w, h);
                P.FillPath(TTyColor(bg.Color));
              end;
            ebkGradient, ebkPattern:
              begin
                el := TyChartElement(TyShapeRect(TyRectF(0, 0, w, h)));
                el.Style.HasFill := True;
                el.Style.Alpha := 1;
                if bg.Kind = ebkGradient then el.Style.FillGradient := bg.Gradient
                else el.Style.FillPattern := bg.Pattern;
                TyRenderElement(P, el);
              end;
          end;
          P.EndPaint;
        finally
          P.Free;
        end;
      end;
    finally
      root.Free;
    end;
    { each image at its place, on the nearest pixel }
    for i := 0 to n - 1 do
      if bmps[i] <> nil then
        Result.PutImage(Floor(lay.X[i] + 0.5), Floor(lay.Y[i] + 0.5), bmps[i],
          dmDrawWithTransparency);
  finally
    for i := 0 to n - 1 do bmps[i].Free;
  end;
end;

procedure TTyCustomAdvanceChart.SaveConnectedToStream(AStream: TStream; const AOptsJson: string);
var
  o: TTyChartExportOpts;
  bmp: TBGRABitmap;
begin
  ExportOptsOrRaise(AOptsJson, o);
  bmp := RenderConnectedToBitmap(AOptsJson);
  if bmp = nil then Exit;
  try
    WriteExport(AStream, bmp, o.ImageType);
  finally
    bmp.Free;
  end;
end;

procedure TTyCustomAdvanceChart.SaveConnectedToFile(const AFileName: string;
  const AOptsJson: string);
var
  o: TTyChartExportOpts;
  bmp: TBGRABitmap;
  fs: TFileStream;
  ext: string;
begin
  ExportOptsOrRaise(AOptsJson, o);
  if not o.HasType then
  begin
    ext := LowerCase(ExtractFileExt(AFileName));
    if (ext = '.jpg') or (ext = '.jpeg') then o.ImageType := eitJpeg;
  end;
  bmp := RenderConnectedToBitmap(AOptsJson);
  if bmp = nil then Exit;
  try
    fs := TFileStream.Create(AFileName, fmCreate);
    try
      WriteExport(fs, bmp, o.ImageType);
    finally
      fs.Free;
    end;
  finally
    bmp.Free;
  end;
end;

function TTyCustomAdvanceChart.GetConnectedDataURL(const AOptsJson: string): string;
var
  o: TTyChartExportOpts;
  bmp: TBGRABitmap;
  ms: TMemoryStream;
  raw: RawByteString;
begin
  ExportOptsOrRaise(AOptsJson, o);
  bmp := RenderConnectedToBitmap(AOptsJson);
  if bmp = nil then Exit('data:,');
  ms := TMemoryStream.Create;
  try
    WriteExport(ms, bmp, o.ImageType);
    SetLength(raw, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, raw[1], ms.Size);
  finally
    ms.Free;
    bmp.Free;
  end;
  if o.ImageType = eitJpeg then Result := 'data:image/jpeg;base64,'
  else Result := 'data:image/png;base64,';
  Result := Result + EncodeStringBase64(raw);
end;
