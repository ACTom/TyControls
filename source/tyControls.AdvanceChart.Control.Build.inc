{ Part of tyControls.AdvanceChart (included, not a unit): the pipeline -- rebuild and
  relayout, axis breaks, the markers, decals and aria, palettes and colours, the titles,
  the series list and the full update. Moved out of the unit only to keep it readable;
  what the control is and why it is built the way it is, see the unit header. }

{ [F3c] the paths a series' view drew from AFrom on (no text): its view's,
  no item's -- faded in where a universal transition morphs }
procedure UtTagFade(AList: TTyPaintList; AFrom, ASeries: Integer);
var
  k, n: Integer;
  el: TTyChartElement;
begin
  n := 0;
  for k := AFrom to AList.Count - 1 do
  begin
    el := AList.Element(k);
    if (el.Caption.Text <> '') or (el.Anim.Role <> carNone) or (el.Anim.UtTag <> 0) then Continue;
    el.Anim.Series := ASeries;
    el.Anim.UtTag := 2;
    el.Anim.UtRow := -2 - n;
    Inc(n);
    AList.SetElement(k, el);
  end;
end;

{ [F3c] the graph nodes AList has from AFrom on: G[7..8] the node's layout
  place, G[9] the compensation scale, G[10] 1 }
procedure UtTagGraphNodes(AList: TTyPaintList; AFrom: Integer;
  const ANodes: TTyGraphNodeArray; ANodeScale: Double);
var
  k, q: Integer;
  el: TTyChartElement;
begin
  for k := AFrom to AList.Count - 1 do
  begin
    el := AList.Element(k);
    if el.Anim.Role <> carSymbol then Continue;
    for q := 0 to High(ANodes) do
      if ANodes[q].Row = el.Anim.Index then
      begin
        el.Anim.G[7] := ANodes[q].X;
        el.Anim.G[8] := ANodes[q].Y;
        el.Anim.G[9] := ANodeScale;
        el.Anim.G[10] := 1;
        AList.SetElement(k, el);
        Break;
      end;
  end;
end;

{ ==================== the pipeline ==================== }

procedure TTyCustomAdvanceChart.Rebuild;
var prev: TComponent; prevRes: TTyChartImageUrlResolver;
begin
  prev := TyChartImageScopeEnter(Owner);
  prevRes := TyChartImageResolverEnter(@ResolveImageUrl);
  try
    RebuildBody;
  finally
    TyChartImageResolverLeave(prevRes);
    TyChartImageScopeLeave(prev);
  end;
end;

procedure TTyCustomAdvanceChart.RebuildBody;
var
  d: TJSONData;
  lnRaws: TTyLinesRawArray;
  i, j, k, ds, cur: Integer;
  dims: TTySeriesDimArray;
  st: TTyDataStore;
  coord: TTyCoordDimArray;
  cursors: TTyEncodeCursorArray;
  enc: TTySeriesEncode;
  typeInfo: TTySeriesTypeInfo;
  radarSpec: TTyRadarSpec;
  polarMissing: TTyStringArray;
  ax: TTyAxis;
  { [R2-I6] }
  sig: string;
  pre: TTyIntegerArray;
begin
  DropBuild;
  FBuild := TyBuildGrids(FOption, FLastRect);
  { THE POLARS beside the grids: their axes, extents and centres
    [Batch 111] }
  FPolars := TyBuildPolars(FOption, FLastRect, polarMissing);
  for i := 0 to High(polarMissing) do
  begin
    j := Pos(':', polarMissing[i]);
    FBuild.Note(Format(rsTyChartPolarNoAxis, [StrToIntDef(Copy(polarMissing[i], 1, j - 1), -1),
      Copy(polarMissing[i], j + 1, MaxInt)]));
  end;
  { THE SINGLE AXES: their boxes, axes and extents along them [Batch 118] }
  FSingles := TyBuildSingles(FOption, FLastRect);
  { THE PARALLELS beside them: their axes, their boxes, and each axis' active
    intervals from its model [Batch 128] }
  FParallels := TyBuildParallels(FOption, FLastRect);
  for i := 0 to High(FParallels) do
    if FParallels[i] <> nil then
      for j := 0 to FParallels[i].AxisCount - 1 do
        if FParallels[i].AxisIndices[j] <= High(FParIntervals) then
          FParallels[i].Intervals[j] := Copy(FParIntervals[FParallels[i].AxisIndices[j]]);
  FBindings := TyBindSeries(FOption, FBuild);
  { A SERIES ON A POLAR takes the polar's axes [Batch 113] }
  TyAttachPolarSeries(FBindings, FPolars);
  { AND ONE ON A SINGLE AXIS its axis [Batch 118] }
  TyAttachSingleSeries(FBindings, FSingles);
  { and one on a parallel its parallel [Batch 128] }
  for i := 0 to High(FBindings) do
    if FBindings[i].Resolved and (FBindings[i].ParallelIndex >= 0)
      and (FBindings[i].ParallelIndex <= High(FParallels)) then
      FBindings[i].Parallel := FParallels[FBindings[i].ParallelIndex];
  { A TYPE THAT RESOLVED AND STILL DRAWS NOTHING HAS TO SAY SO. Binding knows
    the twenty-three names ECharts ships and says nothing about which of them
    this control can paint, so a `funnel` bound cleanly, laid out cleanly and
    came out blank with no diagnostic at all -- which is the one thing the
    control is not allowed to do. Said HERE rather than in the binder because
    the binder cannot see the renderer table: the unit that owns it uses the
    binder, and a second copy of the list over there is a second thing that
    drifts. }
  for i := 0 to High(FBindings) do
    if FBindings[i].Resolved and (FBindings[i].SeriesType <> '')
      and not TySeriesTypeHasRenderer(FBindings[i].SeriesType) then
      FBuild.Note(Format(rsTyChartSeriesNoRenderer,
        [FBindings[i].SeriesIndex, FBindings[i].SeriesType]));
  { THE MATRICES before the stores: a series on one parses its x and y by
    the header trees' category lists [Batch 145] }
  BuildMatrices;
  SetLength(FStores, Length(FBindings));
  { the previous build's sources go before the tables they borrow }
  FSources := nil;
  SetLength(FSources, Length(FBindings));
  SetLength(FSeriesDataset, Length(FBindings));
  SetLength(FEncodes, Length(FBindings));
  if FDatasetCache = nil then FDatasetCache := TTyDatasetCache.Create
  else FDatasetCache.Clear;
  { the transforms draw from the state their option's first build found
    [Batch 134] }
  if not FTransformSeedTaken then FTransformSeed := FAxisMemory.RandomState^;
  FTransformRandom := FTransformSeed;
  FDatasetCache.RandomState := @FTransformRandom;
  cursors := nil;
  StoreKeepBegin;
  for i := 0 to High(FBindings) do
  begin
    st := TTyDataStore.Create;
    FStores[i] := st;
    { A LINES SERIES' ROWS ARE ITS ITEMS: one `value` column and no
      coordinate at all -- its coords never reach an axis' extent
      (LinesSeries.getInitialData) [Batch 121] }
    if FBindings[i].SeriesType = TyLinesSeriesTypeName then
    begin
      FSeriesDataset[i] := -1;
      d := FOption.ComponentAt('series', FBindings[i].SeriesIndex);
      if d is TJSONObject then
      begin
        lnRaws := TyLinesRawsOf(TJSONObject(d));
        st.AddDimension(TyLinesValueDim, ddtFloat);
        for k := 0 to High(lnRaws) do
        begin
          st.AppendRow([lnRaws[k].Value]);
          if lnRaws[k].HasName then st.SetName(k, lnRaws[k].Name);
        end;
      end;
      Continue;
    end;
    { A PARALLEL SERIES' ROWS: a column per row element, 'dimN' where an axis
      of its parallel stands [Batch 128] }
    if FBindings[i].Parallel is TTyParallel then
    begin
      FSeriesDataset[i] := -1;
      ParallelStore(i, st);
      Continue;
    end;
    { WHICH TABLE, IF ANY. A series with its own `data` reads that and nothing
      else -- the table is there for the series that did not bring any. }
    FSeriesDataset[i] := TySeriesDatasetIndex(FOption, FBindings[i].SeriesIndex);
    if FSeriesDataset[i] >= 0 then
    begin
      FSources[i] := TySourceOf(FOption, FSeriesDataset[i],
        FBindings[i].SeriesIndex, FDatasetCache);
      if not FSources[i].Valid then FSeriesDataset[i] := -1;
    end;
    { A THEMERIVER'S ROWS ARE getInitialData's: the items with a name and
      fixData's zeros, time and value, the names the rows' [Batch 118] }
    if (FBindings[i].SeriesType = TyThemeRiverSeriesTypeName) then
    begin
      if FBindings[i].Single <> nil then
      begin
        { getDimensionTypeByAxis: a time axis' time, a value axis' float --
          and a category axis' 'ordinal', which with no categories of its
          own keeps the raw values: a name is not a number to dataToPoint
          ('+val'), a number is, as a float column reads them }
        ax := TTySingle(FBindings[i].Single).Axis;
        if ax.AxisType = atTime then
          TyThemeRiverFillStore(FOption, FBindings[i].SeriesIndex, ddtTime, nil, st)
        else
          TyThemeRiverFillStore(FOption, FBindings[i].SeriesIndex, ddtFloat, nil, st);
      end;
      Continue;
    end;
    if (not FBindings[i].HasAxes) and (FBindings[i].Polar = nil)
      and (FBindings[i].Single = nil) and not CustomOnNone(i) then
    begin
      { A SERIES OFF EVERY COORDINATE SYSTEM HAS DATA TOO, and until now
        only a pie got any: the columns below are the coordinate system's
        dimensions, and a series without a coordinate system has none, so
        the store stayed empty and the `data` array was never read. One
        float column, named the way ECharts names the dimension, and
        TyFillSeriesStore does the rest -- it already unwraps
        `{ value, name }`, records the name and collects the per-item
        overrides.

        THE TEST IS THE USAGE, NOT THE TYPE NAME. It read `= 'pie'` while
        the registry had said `scuBox` about a funnel and a gauge since the
        day it was written -- so both of them reached here, matched nothing,
        and left with a store of zero columns and zero rows. Nothing raised;
        their layout simply found no value dimension and drew nothing, which
        is indistinguishable from a type with no renderer. }
      { A RADAR SERIES IS NOT ON NO COORDINATE SYSTEM -- it is on one whose
        axes are spokes, and HasAxes says only that the cartesian pair is
        absent. One float column per indicator, named the way the coordinate
        system names its dimensions, and the store's own default of "column j
        takes element j of the row" is exactly a radar row. }
      { ON A MATRIX [Batch 145]: Matrix.getDimensionsInfo -- x and y are
        ordinal on the header trees' own category lists (a collecting tree
        takes the names as they come), then the value }
      { [Batch 147] not a pie or a funnel (their own value column) nor a
        graph (its nodes the graph's way; the points are MatrixGraphPoints') }
      if (FBindings[i].MatrixIndex >= 0) and (FBindings[i].MatrixIndex <= High(FMatrices))
        and not FBindings[i].MatrixBox
        and (FBindings[i].SeriesType <> TyPieSeriesTypeName)
        and (FBindings[i].SeriesType <> TyFunnelSeriesTypeName)
        and (FBindings[i].SeriesType <> TyGraphSeriesTypeName) then
      begin
        SetLength(dims, 3);
        for j := 0 to 2 do dims[j] := Default(TTySeriesDim);
        dims[0].Name := TyMatrixXDim;
        dims[0].Kind := ddtOrdinal;
        dims[1].Name := TyMatrixYDim;
        dims[1].Kind := ddtOrdinal;
        dims[2].Name := TyMatrixValueDim;
        dims[2].Kind := ddtFloat;
        for j := 0 to 2 do st.AddDimension(dims[j].Name, dims[j].Kind);
        st.UseOrdinalMeta(0, FMatrices[FBindings[i].MatrixIndex].Dims[0].Meta);
        st.UseOrdinalMeta(1, FMatrices[FBindings[i].MatrixIndex].Dims[1].Meta);
        { WITH NO DATA OF ITS OWN, ITS DATASET [Batch 149]: the columns its
          encode names (the rest from the next free ones), x and y parsed --
          and a collecting tree collecting -- by the trees' category lists,
          the way a series on axes reads a table }
        ds := FSeriesDataset[i];
        if ds >= 0 then
        begin
          SetLength(coord, Length(dims));
          for k := 0 to High(dims) do
          begin
            coord[k].Name := dims[k].Name;
            coord[k].Ordinal := dims[k].Kind = ddtOrdinal;
          end;
          enc := TyEncodeOf(FOption, FBindings[i].SeriesIndex, FSources[i], coord);
          if not enc.Given then
          begin
            cur := TyEncodeCursorFor(cursors, ds, FSources[i].LayoutBy);
            enc := TyDefaultEncodeAxis(cursors[cur], coord);
          end;
          if enc.Given then TyEncodeFillUnclaimed(enc, FSources[i].DimCount);
          FEncodes[i] := enc;
          TyFillStoreFromSource(FSources[i], enc, dims, st);
        end
        else
          TyFillSeriesStore(FOption, i, dims, st);
        { A SCATTER'S TOOLTIP HAS NO DIMENSION of its own there (its value is
          no coordinate dimension, x and y are ordinal: defaultedTooltip is
          empty), so it shows every element of the item [Batch 147] }
        if (FBindings[i].SeriesType = 'scatter') or (FBindings[i].SeriesType = 'effectScatter') then
          st.SetTooltipPositions(nil);
        Continue;
      end;
      if FBindings[i].RadarIndex >= 0 then
      begin
        radarSpec := TyRadarSpecOf(FOption, FBindings[i].RadarIndex);
        SetLength(dims, Length(radarSpec.Indicators));
        for j := 0 to High(dims) do
        begin
          st.AddDimension(TyRadarDimPrefix + IntToStr(j), ddtFloat);
          dims[j] := Default(TTySeriesDim);
          dims[j].Name := TyRadarDimPrefix + IntToStr(j);
          dims[j].Kind := ddtFloat;
        end;
        if Length(dims) > 0 then TyFillSeriesStore(FOption, i, dims, st);
        Continue;
      end;
      { A GRAPH IS NOT ON NO COORDINATE SYSTEM EITHER -- it is on a view, whose
        axes do not exist rather than being spokes -- and it is NOT scuBox:
        its usage says `data` because its nodes are data. So it matched
        neither branch and left with a store of no columns and no rows,
        which is the very failure the paragraph above records for the funnel
        and the gauge. The same trap, the third time.

        THE GRAPH UNIT BUILDS IT, the one way the suite builds it too: one
        value column, read from `data` or from `nodes`, its second name.
        A graph on AXES is not here at all -- it has the axes' columns, below. }
      if FBindings[i].SeriesType = TyGraphSeriesTypeName then
      begin
        TyGraphFillStore(FOption, i, st);
        Continue;
      end;
      { A CHORD'S NODES are its rows the graph's way too: `data || nodes`,
        one value column, the names the legend lists [Batch 120] }
      if FBindings[i].SeriesType = TyChordSeriesTypeName then
      begin
        TyGraphFillStore(FOption, i, st);
        Continue;
      end;
      { A TREE'S ROWS ARE ITS HIERARCHY IN PRE-ORDER under a virtual root --
        never the top-level `data` alone, which would lose every child. Before
        the calendar's branch: a tree on a calendar keeps its own rows.
        [Batch 73] }
      if (FBindings[i].SeriesType = TyTreeSeriesTypeName)
        or (FBindings[i].SeriesType = TySunburstSeriesTypeName)
        or (FBindings[i].SeriesType = TyTreemapSeriesTypeName) then
      begin
        { a sunburst's and a treemap's rows are the same hierarchy, their
          values completed [Batches 75, 76] }
        TyTreeFillStore(FOption, FBindings[i].SeriesIndex, st,
          FBindings[i].SeriesType <> TyTreeSeriesTypeName);
        Continue;
      end;
      { A MAP SERIES: a value per region name, and a row for every region
        its data leaves out [Batch 152, D14 GE4] }
      if FBindings[i].SeriesType = TyMapSeriesTypeName then
      begin
        MapFillStore(i, st);
        Continue;
      end;
      { ON A CALENDAR: the calendar's two dimensions, a time and a value --
        element 0 of the row is the date and element 1 the value, and any
        more are raw positions the store keeps for the label and the
        visualMap. [Batch 70] }
      if (FBindings[i].CalendarIndex >= 0)
        and (FBindings[i].SeriesType <> TyPieSeriesTypeName) then
      begin
        st.AddDimension(TyCalendarTimeDim, ddtTime);
        st.AddDimension(TyCalendarValueDim, ddtFloat);
        SetLength(dims, 2);
        dims[0] := Default(TTySeriesDim);
        dims[0].Name := TyCalendarTimeDim;
        dims[0].Kind := ddtTime;
        dims[1] := Default(TTySeriesDim);
        dims[1].Name := TyCalendarValueDim;
        dims[1].Kind := ddtFloat;
        TyFillSeriesStore(FOption, i, dims, st);
        Continue;
      end;
      { ON A GEO: the geo's two dimensions, lng and lat -- elements 0 and 1
        of the row; any more are raw positions the store keeps (a heatmap's
        value, a visualMap's dimension) [Batch 152, D14 GE4] }
      if (FBindings[i].GeoIndex >= 0)
        and (FBindings[i].SeriesType <> TyPieSeriesTypeName)
        and (FBindings[i].SeriesType <> TyMapSeriesTypeName) then
      begin
        st.AddDimension(TyGeoLngDim, ddtFloat);
        st.AddDimension(TyGeoLatDim, ddtFloat);
        SetLength(dims, 2);
        dims[0] := Default(TTySeriesDim);
        dims[0].Name := TyGeoLngDim;
        dims[0].Kind := ddtFloat;
        dims[1] := Default(TTySeriesDim);
        dims[1].Name := TyGeoLatDim;
        dims[1].Kind := ddtFloat;
        { a heatmap's third: its value (HeatmapView's mapDimension('value')) }
        if FBindings[i].SeriesType = 'heatmap' then
        begin
          st.AddDimension(TyPieValueDim, ddtFloat);
          SetLength(dims, 3);
          dims[2] := Default(TTySeriesDim);
          dims[2].Name := TyPieValueDim;
          dims[2].Kind := ddtFloat;
        end;
        TyFillSeriesStore(FOption, i, dims, st);
        Continue;
      end;
      if TySeriesFindType(FBindings[i].SeriesType, typeInfo)
        and (typeInfo.Usage = scuBox) and (Length(typeInfo.Dims) > 0) then
      begin
        st.AddDimension(typeInfo.Dims[0], ddtFloat);
        SetLength(dims, 1);
        dims[0].Name := typeInfo.Dims[0];
        dims[0].Kind := ddtFloat;
        dims[0].Axis := nil;
        ds := FSeriesDataset[i];
        if ds >= 0 then
        begin
          { A PIE NAMES ITS DATA RATHER THAN PLOTTING IT, so its default
            encode is the other one: a NAME dimension and a VALUE dimension,
            guessed from the table rather than counted off it. }
          SetLength(coord, 1);
          coord[0].Name := typeInfo.Dims[0];
          coord[0].Ordinal := False;
          enc := TyEncodeOf(FOption, FBindings[i].SeriesIndex,
            FSources[i], coord);
          if not enc.Given then
            enc := TyDefaultEncodeNameBased(FSources[i],
              FSources[i].DimCount);
          FEncodes[i] := enc;
          TyFillStoreFromSource(FSources[i], enc, dims, st);
        end
        else
          TyFillSeriesStore(FOption, i, dims, st);
      end;
      Continue;
    end;
    { ON A POLAR: its two axes' columns, radius then angle (polarDimensions),
      the store filled as a cartesian series' is [Batch 113] }
    if FBindings[i].Polar <> nil then
      dims := TySeriesCoordSysDims(TTyPolar(FBindings[i].Polar), 0)
    { ON A SINGLE AXIS: its one column, the single dimension [Batch 118] }
    else if FBindings[i].Single <> nil then
      dims := TySeriesCoordSysDims(TTySingle(FBindings[i].Single), 0)
    { A CUSTOM SERIES ON NO COORDINATE SYSTEM ('none'): getCoordSysDimDefs'
      last resort, the dimensions x and y, as floats; the rest of a row the
      store keeps by position [Batch 124] }
    else if FBindings[i].Cart = nil then
    begin
      SetLength(dims, 2);
      dims[0] := Default(TTySeriesDim);
      dims[0].Name := 'x';
      dims[0].Kind := ddtFloat;
      dims[1] := Default(TTySeriesDim);
      dims[1].Name := 'y';
      dims[1].Kind := ddtFloat;
    end
    else
      dims := TySeriesCartesianDims(FBindings[i].Cart, 0);
    { A SERIES WHOSE TYPE DECLARES MORE THAN A PAIR gets those columns
      instead. A candlestick is four numbers on ONE axis and a category that
      is nowhere in the row at all; a coordinate-per-column store cannot hold
      it, and the two-column version quietly kept the closes and threw the
      other three away. The axis then sized itself from a quarter of its own
      data and the renderer found no columns to read. }
    MultiValueDims(FBindings[i], dims);
    { a custom series' encode may spread one coordinate over several
      columns (a span's start and end) [Batch 123] }
    CustomDims(i, dims);
    for k := 0 to High(dims) do
    begin
      st.AddDimension(dims[k].Name, dims[k].Kind);
      { WHICH COORDINATE THIS COLUMN FEEDS. Only ever different from its own
        name for a multi-value series, and only that series' extent pass and
        tooltip look at it. }
      if dims[k].Coord <> '' then st.SetDimCoord(k, dims[k].Coord);
      { The axis owns the category list and every series on it borrows the SAME
        one -- that sharing is what makes two series agree about which name
        ordinal 0 is. }
      if dims[k].Axis <> nil then st.UseOrdinalMeta(k, dims[k].Axis.Categories);
    end;
    { A GRAPH ON AXES FILLS THE AXES' COLUMNS THE GRAPH'S WAY: `data` or
      `nodes`, the series' own `category` filed into every silent node, and
      never a dataset -- upstream builds a graph's nodes from its own option
      whatever tables the chart carries. The columns are the ones every other
      series here gets, which is what upstream does too: a bare number on a
      category axis is its row and its value, and the axes size themselves
      from these like from anything else. }
    if FBindings[i].SeriesType = TyGraphSeriesTypeName then
    begin
      TyGraphFillNodes(FOption, i, dims, st);
      Continue;
    end;
    ds := FSeriesDataset[i];
    if ds < 0 then
    begin
      SeriesDataEncode(i, dims, enc);
      { [R2-I6] the store the last build of this tree parsed, when it is
        the same recipe on the same lists }
      sig := StoreKeepSig(i, 0, -1, dims, enc);
      if StoreKeepTake(i, sig, dims) then Continue;
      StoreKeepPre(dims, pre);
      TyFillSeriesStore(FOption, i, dims, st);
      ResolveTextDims(enc, st, TySeriesDimsSource(FOption, FBindings[i].SeriesIndex));
      HeatmapTipDims(i, enc, st);
      StoreKeepPut(i, sig, dims, pre);
      Continue;
    end;
    { THE COORDINATES, AS THE ENCODE RULES SEE THEM: a name and whether the
      axis under it is a category one. The second is what chooses between the
      two ways of handing a table out, and it is not the same question as
      which axis is horizontal. }
    SetLength(coord, Length(dims));
    for k := 0 to High(dims) do
    begin
      coord[k].Name := dims[k].Name;
      coord[k].Ordinal := dims[k].Kind = ddtOrdinal;
    end;
    enc := TyEncodeOf(FOption, FBindings[i].SeriesIndex, FSources[i], coord);
    { THE CURSOR IS SHARED AND IT ADVANCES, which is why this has to happen
      inside the one loop that walks the series in order. Three bars on one
      table take columns 1, 2 and 3 because the second and third ask the same
      counter the first one moved. A series that brought its own encode --
      even a partial one -- does not ask, and so does not move it. }
    if not enc.Given then
    begin
      { THE INDEX FIRST, THEN THE SUBSCRIPT. `cursors[F(cursors)]` where F may
        SetLength is the repository's own recorded footgun: FPC takes the
        array's address before it evaluates the index, so a reallocation
        inside F leaves the write going to freed memory. }
      cur := TyEncodeCursorFor(cursors, ds, FSources[i].LayoutBy);
      enc := TyDefaultEncodeAxis(cursors[cur], coord);
    end;
    { A GIVEN ENCODE FILLS WHAT IT LEAVES OUT from the next free columns --
      `encode: {tooltip: [2]}` still draws x from 0 and y from 1. }
    if enc.Given then TyEncodeFillUnclaimed(enc, FSources[i].DimCount);
    FEncodes[i] := enc;
    { [R2-I6] kept, as above }
    sig := StoreKeepSig(i, 1, ds, dims, enc);
    if StoreKeepTake(i, sig, dims) then Continue;
    StoreKeepPre(dims, pre);
    TyFillStoreFromSource(FSources[i], enc, dims, st);
    ResolveTextDims(enc, st, FSources[i]);
    HeatmapTipDims(i, enc, st);
    StoreKeepPut(i, sig, dims, pre);
    Continue;
  end;
  StoreKeepEnd;
  { THE FIRST BUILD OF AN OPTION hands the chart's stream on past what its
    transforms drew; a later one leaves it where it is [Batch 134] }
  if not FTransformSeedTaken then
  begin
    FAxisMemory.RandomState^ := FTransformRandom;
    FTransformSeedTaken := True;
  end;
  { A MATRIX TREE WITH NO DATA takes the names its series collected, in
    series order (MatrixDim._initBySeriesData) [Batch 145] }
  for i := 0 to High(FMatrices) do
    if FMatrices[i] <> nil then
    begin
      FMatrices[i].Dims[0].TakeCollected;
      FMatrices[i].Dims[1].TakeCollected;
    end;
  { THE BOX HOSTS, LAID OUT HERE [Batch 151]: upstream creates the calendars
    and the matrices first (nonSeriesBoxCoordSysCreators) so a grid or a
    polar in one of their cells has its rect before the data is processed
    -- a sampling, a dataZoom window and a bar's extent all read the axes'
    pixel extents. Once the trees have collected their names. }
  SolveCalendars(FLastPPI);
  SolveMatrices(FLastPPI);
  PlaceBoxedCoordSys;
  { A DATASET WHOSE TRANSFORM FAILED has no table, and the series reading it
    draw nothing -- said here, once per dataset a series reached. Upstream
    throws out of setOption and draws nothing at all. [Batch 133] }
  for i := 0 to FDatasetCache.DatasetCount - 1 do
    if FDatasetCache.ErrorOf(i) <> '' then
      FBuild.Note(Format(rsTyChartDatasetNoTable, [i, FDatasetCache.ErrorOf(i)]));
  { AFTER THE STORES AND BEFORE EVERYTHING THAT COUNTS. A pie legend names
    DATA ITEMS, so the names have to be in the store before the legend can
    list them; and the filter the legend implies has to be in place before
    the index, the stacks and the extents, or a switched-off series would go
    on widening the axis it is not drawn on.

    This is upstream's order too, by its priorities: legendFilter is
    SERIES_FILTER (800), the stack pass is 900 and the axis statistics are
    920, with a comment at echarts.ts:163-165 saying the statistics must come
    after the filter for exactly this reason. Nothing here measures text, so
    none of it has to wait for Relayout. }
  SolveLegendData;
  ApplyLegendFilter;
  { THE MAP SERIES' STATISTIC (PRIORITY.PROCESSOR.STATISTIC), over the series
    the filter left, before the visual stage [Batch 152] }
  SolveMapSeries;
  { AFTER the filter, because a graph the legend switched off takes no slot of
    the shared category palette -- upstream's categoryVisual walks only the
    series the filter kept. }
  SolveGraphCategoryColours;
  { AFTER the filter but over EVERY series slot, hidden ones included --
    see SolveSeriesColors. The two are not in tension: the filter decides
    what is drawn, the palette decides what colour each series IS, and the
    second must not depend on the first or a legend click would repaint
    the whole chart. }
  SolveSeriesColors;
  { AFTER the colours, because a partial colour visual starts from the series
    colour, and BEFORE the stacks: the default dimension is the last one that
    is not a calculation, and the stack columns are calculations. }
  SolveVisualMaps;
  TyIndexSeries(FBindings, FIndex);
  { A PARALLEL SERIES IS ON EVERY AXIS OF ITS PARALLEL
    (associateSeriesWithAxis) [Batch 128] }
  for i := 0 to High(FBindings) do
    if (FBindings[i].Parallel is TTyParallel) and not FBindings[i].Hidden then
      for j := 0 to TTyParallel(FBindings[i].Parallel).AxisCount - 1 do
        FIndex.Associate(TTyParallel(FBindings[i].Parallel).Axis(j), nil, i,
          FBindings[i].SeriesType, TyParallelCoordSysName);
  { BEFORE THE EXTENTS, and that order is the whole point: a stacked chart
    whose axis was sized from the raw values draws off the top of its plot. }
  FStacks := TySolveStacks(FOption, FBindings, FStores);
  { AFTER THE STACKS AND BEFORE THE EXTENTS -- upstream's dataZoom runs at
    1000, after the stack (900): the sums are the unzoomed ones, and the
    axis not zoomed is sized from the rows the zoom left. }
  SolveDataZooms;
  { AFTER THE dataZoom FILTER AND BEFORE THE EXTENTS: upstream's dataSample
    runs at 5000, behind the stack (900) and the filter (1000), and the
    coordinate system is sized from what it leaves. [Batch 102] }
  SolveSampling;
  { EVERY RENDER IS A RENDER OF THE VIEWS: a slider rebuilds from the window
    unless the action was its own, an inside takes the window again }
  DzRenderStates;
  { appendData's frame does not update the coordinate systems: every axis
    takes the raw extent the last update measured [Batch 119] }
  if (FStreamRelayout or FExporting) and FFrozenOn then
    TyApplyAxisExtents(FOption, FBuild, FBindings, FStores, FStacks, FIndex,
      FLastPPI, FrozenZooms)
  else
    TyApplyAxisExtents(FOption, FBuild, FBindings, FStores, FStacks, FIndex,
      FLastPPI, FAxisZooms);
  { THE CATEGORY AXES' SORT (Grid.update after the extents): a bar race's
    order [Batch 135] }
  RtApplySortInfos;
  { AND THE POLARS' SCALES, the same nice step [Batch 111] -- over the
    series on them, the stacks and the dataZoom windows [Batch 113] }
  TyPolarApplyExtents(FOption, FPolars, FBindings, FStores, FStacks, FIndex,
    FAxisZooms);
  { AND THE SINGLES' [Batch 118] }
  TySingleApplyExtents(FOption, FSingles, FBindings, FStores, FStacks, FIndex,
    FAxisZooms);
  { AND THE PARALLELS' (Parallel.update) [Batch 128] }
  TyParallelApplyExtents(FOption, FParallels, FBindings, FStores, FStacks, FIndex);
  { LAST, ON THE VIEWS THE FILTERS LEFT: dataColorPaletteTask is a visual
    stage (4600), after every processor -- a row the legend or a dataZoom
    took out reads the series' colorFromPalette, a row still in reads its
    own. [Batch 105] }
  SolveDatumPalette;
  { AND THE DECALS: the aria visual (6000) and the decal visual (7000)
    come after every other visual stage [Batch 131] }
  SolveDecals;
  { [R2-J3] the series' visual callbacks: after the palette and the
    visualMaps are settled, before any layout (a graph's ring sizes its
    nodes by them) }
  SolveItemCallbacks;
end;

{ dataColorPaletteTask [Batch 105]. eachSeries -- the series the legend kept
  -- whose getColorBy() is not 'series', ONE SCOPE PER `type-colorBy` shared
  by every such series in the chart: a second pie continues where the first
  stopped, and a name the first one coloured comes out the same colour.
  Every RAW row in raw order, so a row a filter took out still takes its
  slot and the colours stay put across a legend click; a row asks only while
  its colour is the palette's -- the series' was unwritten (`auto` is
  written) and, while it is in view, neither its own itemStyle colour nor a
  visual channel coloured it. Out of view its own colour is not seen: the
  item style task only met the rows in view. The palette is the series' own
  `color` / `colorLayer`, else the chart's, both over the shared scope, asked
  with the RAW count. }
procedure TTyCustomAdvanceChart.SolveDatumPalette;
type
  TKeyedScope = record
    Key: string;
    Scope: TTyPaletteScope;
  end;
var
  scopes: array of TKeyedScope;
  i, j, k, si, rawN, sIdx: Integer;
  cb, typ, nm: string;
  chartPal, ownPal: TTyPalette;
  chartLayers, ownLayers: TTyPaletteLayers;
  sc: TTyPaletteScope;
  item: TJSONObject;
  d: TJSONData;
  own: Boolean;
begin
  FDatumPicks := nil;
  FDatumAsked := nil;
  FRowObjFills := nil;
  FRowObjDone := nil;
  FRowObjN := nil;
  SetLength(FDatumPicks, Length(FBindings));
  SetLength(FDatumAsked, Length(FBindings));
  if FOption = nil then Exit;
  chartPal := TyChartRootPalette(FOption);
  chartLayers := TyChartPaletteLayersOf(FOption, -1);
  scopes := nil;
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].Hidden then Continue;
    if (i > High(FStores)) or (FStores[i] = nil) then Continue;
    si := FBindings[i].SeriesIndex;
    typ := FBindings[i].SeriesType;
    { THE TYPES WHOSE ROWS THIS PORT PAINTS ONE BY ONE. A graph, a tree, a
      treemap, a sunburst and a sankey colour their own nodes; a candlestick's
      and a boxplot's defaults write the colour. }
    if not ((typ = 'bar') or (typ = 'line') or (typ = 'scatter')
      or (typ = 'effectScatter') or (typ = 'pictorialBar')
      or (typ = TyPieSeriesTypeName) or (typ = 'funnel') or (typ = 'gauge')
      or (typ = 'radar') or (typ = TyThemeRiverSeriesTypeName)
      { a chord's nodes, colorBy 'data' by default [Batch 120] }
      or (typ = TyChordSeriesTypeName)) then Continue;
    cb := TyChartColorByOf(FOption, si, typ);
    if cb = 'series' then Continue;
    { the scope first, whether or not a row asks: upstream hands every such
      series its scope before any of them picks }
    sIdx := -1;
    for j := 0 to High(scopes) do
      if scopes[j].Key = typ + '-' + cb then sIdx := j;
    if sIdx < 0 then
    begin
      SetLength(scopes, Length(scopes) + 1);
      sIdx := High(scopes);
      scopes[sIdx].Key := typ + '-' + cb;
      scopes[sIdx].Scope := Default(TTyPaletteScope);
    end;
    { a written series colour leaves no row from the palette }
    if (si < 0) or (si > High(FSeriesColorFromPalette))
      or not FSeriesColorFromPalette[si] then Continue;
    rawN := FStores[i].RawCount;
    SetLength(FDatumPicks[i], rawN);
    SetLength(FDatumAsked[i], rawN);
    ownPal := TySeriesOwnPalette(FOption, si);
    ownLayers := TyChartPaletteLayersOf(FOption, si);
    sc := scopes[sIdx].Scope;
    for k := 0 to rawN - 1 do
    begin
      if FStores[i].IndexOfRawIndex(k) >= 0 then
      begin
        { ITS OWN COLOUR: the key present and not null, an object included }
        item := RawItemNode(i, k);
        own := False;
        if item <> nil then
        begin
          d := item.Find(TyStyleAccessPath(typ));
          if d is TJSONObject then
          begin
            d := TJSONObject(d).Find('color');
            own := (d <> nil) and (d.JSONType <> jtNull);
          end;
        end;
        if own then Continue;
        { a visual channel's }
        if (i <= High(FVisualRows)) and (k <= High(FVisualRows[i]))
          and FVisualRows[i][k].ColorSet then Continue;
      end;
      nm := FStores[i].GetNameByRaw(k);
      if nm = '' then nm := IntToStr(k);
      FDatumPicks[i][k] := TySeriesPaletteFrom(ownPal, ownLayers, chartPal,
        chartLayers, nm, sc, sc, rawN);
      FDatumAsked[i][k] := True;
    end;
    scopes[sIdx].Scope := sc;
  end;
end;

function TTyCustomAdvanceChart.RawItemNode(ASlot, ARaw: Integer): TJSONObject;
var d: TJSONArray;
begin
  Result := nil;
  d := RawItemArray(ASlot);
  if d = nil then Exit;
  if (ARaw < 0) or (ARaw >= d.Count) then Exit;
  if d.Items[ARaw] is TJSONObject then Result := TJSONObject(d.Items[ARaw]);
end;

function TTyCustomAdvanceChart.RawItemArray(ASlot: Integer): TJSONArray;
var d: TJSONData;
begin
  Result := nil;
  if (FOption = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  { a dataset's rows are no option items }
  if (ASlot <= High(FSeriesDataset)) and (FSeriesDataset[ASlot] >= 0) then Exit;
  { nor a themeRiver's: its rows are the kept items and fixData's zeros
    [Batch 118] }
  if FBindings[ASlot].SeriesType = TyThemeRiverSeriesTypeName then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (d is TJSONObject) then Exit;
  { a chord's nodes are `data || nodes` [Batch 120] }
  if (FBindings[ASlot].SeriesType = TyChordSeriesTypeName)
    and ((TJSONObject(d).Find('data') = nil)
      or (TJSONObject(d).Find('data').JSONType = jtNull)) then
    d := TJSONObject(d).Find('nodes')
  else
    d := TJSONObject(d).Find('data');
  if d is TJSONArray then Result := TJSONArray(d);
end;

function TTyCustomAdvanceChart.RowObjectFill(ASlot, ARaw: Integer;
  out AColor: TTyOptColor): Boolean;
var st: TTyOptStyle;
begin
  AColor := Default(TTyOptColor);
  st := TyReadOptStyle(RawItemNode(ASlot, ARaw), 'itemStyle');
  Result := st.Color.Written
    and ((st.Color.Gradient.Kind <> cgkNone) or st.Color.Pattern.Present);
  if Result then AColor := st.Color;
end;

function TTyCustomAdvanceChart.DatumObjectFill(ASlot, ARaw: Integer): TTyChartObjFill;
var
  item: TJSONObject;
  d: TJSONData;
  st: TTyOptStyle;
begin
  Result := Default(TTyChartObjFill);
  if (ASlot < 0) or (ASlot > High(FBindings)) or (FOption = nil) then Exit;
  if (ASlot <= High(FVisualRows)) and (ARaw >= 0) and (ARaw <= High(FVisualRows[ASlot]))
    and FVisualRows[ASlot][ARaw].ColorSet then Exit;
  if (ASlot <= High(FDatumAsked)) and (ARaw >= 0) and (ARaw <= High(FDatumAsked[ASlot]))
    and FDatumAsked[ASlot][ARaw] then Exit;
  item := RawItemNode(ASlot, ARaw);
  if item <> nil then
  begin
    d := item.Find('itemStyle');
    if (d is TJSONObject) and (TJSONObject(d).Find('color') <> nil)
      and (TJSONObject(d).Find('color').JSONType <> jtNull) then
    begin
      { the datum wrote its own: an object is the fill, a string is not one }
      st := TyReadOptStyle(item, 'itemStyle');
      if (st.Color.Gradient.Kind <> cgkNone) or st.Color.Pattern.Present then
      begin
        Result.Present := True;
        Result.Gradient := st.Color.Gradient;
        Result.Pattern := st.Color.Pattern;
      end;
      Exit;
    end;
  end;
  Result := SeriesObjectFill(ASlot);
end;

function TTyCustomAdvanceChart.SeriesObjectFill(ASlot: Integer): TTyChartObjFill;
var
  d: TJSONData;
  st: TTyOptStyle;
begin
  Result := Default(TTyChartObjFill);
  if (ASlot < 0) or (ASlot > High(FBindings)) or (FOption = nil) then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (d is TJSONObject) then Exit;
  st := TyReadOptStyle(TJSONObject(d), 'itemStyle');
  if st.Color.IsAuto then Exit;
  if (st.Color.Gradient.Kind <> cgkNone) or st.Color.Pattern.Present then
  begin
    Result.Present := True;
    Result.Gradient := st.Color.Gradient;
    Result.Pattern := st.Color.Pattern;
  end;
end;

function TTyCustomAdvanceChart.SeriesRowFills(ASlot: Integer): TTyRowFillArray;
var
  k, n: Integer;
  oc: TTyOptColor;
  st: TTyOptStyle;
  items: TJSONArray;
  objs: Boolean;
begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  n := FStores[ASlot].RawCount;
  { the rows' own object colours: the option's, so read once a build }
  if Length(FRowObjDone) < Length(FStores) then
  begin
    SetLength(FRowObjDone, Length(FStores));
    SetLength(FRowObjFills, Length(FStores));
    SetLength(FRowObjN, Length(FStores));
  end;
  if not FRowObjDone[ASlot] or (FRowObjN[ASlot] <> n) then
  begin
    { [R2-L] kept only where a row has one: a row that is no object has
      none (RowObjectFill reads nothing from a nil item) }
    FRowObjFills[ASlot] := nil;
    items := RawItemArray(ASlot);
    if items <> nil then
      for k := 0 to n - 1 do
      begin
        if (k >= items.Count) or not (items.Items[k] is TJSONObject) then Continue;
        if RowObjectFill(ASlot, k, oc) then
        begin
          if FRowObjFills[ASlot] = nil then SetLength(FRowObjFills[ASlot], n);
          FRowObjFills[ASlot][k].ObjSet := True;
          FRowObjFills[ASlot][k].ObjSolid := oc.Color;
          FRowObjFills[ASlot][k].ObjGradient := oc.Gradient;
          FRowObjFills[ASlot][k].ObjPattern := oc.Pattern;
        end;
        { [R2-I4] and its own border colour when that is a gradient }
        st := TyReadOptStyle(RawItemNode(ASlot, k), 'itemStyle');
        if st.BorderColor.Written and not st.BorderColor.IsNone and not st.BorderColor.IsAuto
          and (st.BorderColor.Gradient.Kind <> cgkNone) then
        begin
          if FRowObjFills[ASlot] = nil then SetLength(FRowObjFills[ASlot], n);
          FRowObjFills[ASlot][k].StrokeObjSet := True;
          FRowObjFills[ASlot][k].StrokeObjSolid := st.BorderColor.Color;
          FRowObjFills[ASlot][k].StrokeObjGradient := st.BorderColor.Gradient;
        end;
      end;
    FRowObjN[ASlot] := n;
    FRowObjDone[ASlot] := True;
  end;
  { the fills only where a row has one; none at all reads as nil }
  objs := FRowObjFills[ASlot] <> nil;
  for k := 0 to n - 1 do
  begin
    if not ((ASlot <= High(FDatumAsked)) and (k <= High(FDatumAsked[ASlot])) and FDatumAsked[ASlot][k])
      and not (objs and (FRowObjFills[ASlot][k].ObjSet or FRowObjFills[ASlot][k].StrokeObjSet)) then Continue;
    if Result = nil then SetLength(Result, n);
    if (ASlot <= High(FDatumAsked)) and (k <= High(FDatumAsked[ASlot]))
      and FDatumAsked[ASlot][k] then
    begin
      Result[k].PaletteSet := True;
      Result[k].PaletteNone := FDatumPicks[ASlot][k].Kind = ppkNone;
      Result[k].Palette := TTyChartColor(PickColor(FDatumPicks[ASlot][k]));
    end;
    if objs and FRowObjFills[ASlot][k].ObjSet then
    begin
      Result[k].ObjSet := True;
      Result[k].ObjSolid := FRowObjFills[ASlot][k].ObjSolid;
      Result[k].ObjGradient := FRowObjFills[ASlot][k].ObjGradient;
      Result[k].ObjPattern := FRowObjFills[ASlot][k].ObjPattern;
    end;
    if objs and FRowObjFills[ASlot][k].StrokeObjSet then
    begin
      Result[k].StrokeObjSet := True;
      Result[k].StrokeObjSolid := FRowObjFills[ASlot][k].StrokeObjSolid;
      Result[k].StrokeObjGradient := FRowObjFills[ASlot][k].StrokeObjGradient;
    end;
  end;
end;

procedure TTyCustomAdvanceChart.SolveSampling;
var
  i: Integer;
  d: TJSONData;
  mode: TTySamplingMode;
  cols: TTyIntegerArray;
begin
  if FBuild = nil then Exit;
  for i := 0 to High(FBindings) do
  begin
    if (i > High(FStores)) or (FStores[i] = nil) then Continue;
    { dataSample is registered for 'line' and 'bar', and acts on cartesian2d
      alone }
    if (FBindings[i].SeriesType <> 'line') and (FBindings[i].SeriesType <> 'bar') then
      Continue;
    if FBindings[i].CoordSysName <> 'cartesian2d' then Continue;
    if (FBindings[i].BaseAxis = nil) or (FBindings[i].ValueAxis = nil) then Continue;
    d := FOption.ComponentAt('series', FBindings[i].SeriesIndex);
    if (d = nil) or (d.JSONType <> jtObject) then Continue;
    mode := TySamplingModeOf(TJSONObject(d).Find('sampling'));
    if mode = tsmNone then Continue;
    { data.mapDimension(valueAxis.dim): the value column itself, never a
      stack's sum }
    cols := TyAxisDataDims(FStores[i], FBindings[i].ValueAxis, FBindings[i],
      Default(TTySeriesStack));
    if Length(cols) = 0 then Continue;
    { THE SIZE IS THE GRID AS IT STANDS NOW: the raw grid rect, before the
      labels shrink it -- upstream's Grid.create sizes the axes before the
      data processing and dataSample reads them there. Device pixels are
      upstream's css pixels times its pixel ratio. }
    TySampleStore(mode, FStores[i], cols[0], Abs(FBindings[i].BaseAxis.PxLength));
  end;
end;

function TTyCustomAdvanceChart.WeakKeep(ARawIndex: Integer): Boolean;
var
  k: Integer;
  v: Double;
  hasValue, leftOut, rightOut: Boolean;
begin
  { weakFilter: in the window on some dimension, or straddling it; a row
    with no value at all goes }
  hasValue := False;
  leftOut := False;
  rightOut := False;
  for k := 0 to High(FWfCols) do
  begin
    v := FWfStore.GetByRaw(FWfCols[k], ARawIndex);
    if IsNan(v) then Continue;
    { a not-a-number window end compares false both ways, as in JavaScript }
    if (not IsNan(FWfLo)) and (not IsNan(FWfHi)) and (v >= FWfLo) and (v <= FWfHi) then
      Exit(True);
    hasValue := True;
    if (not IsNan(FWfLo)) and (v < FWfLo) then leftOut := True;
    if (not IsNan(FWfHi)) and (v > FWfHi) then rightOut := True;
  end;
  Result := hasValue and leftOut and rightOut;
end;

procedure TTyCustomAdvanceChart.Relayout(APainter: TTyPainter; const ARect: TTyRectF;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  txt: TTyAxisTextStyle;
  labelS: TTyStyleSet;
  lblHasCol: Boolean;
  lblCol: Cardinal;
  largeBars: TTyBoolArray;
  i: Integer;
begin
  { [R2-I9] a new layout: no list of the last one is drawn as it stands }
  FListFresh := False;
  { a resize renders every view [Batch 130] }
  if (ARect.Left <> FLastRect.Left) or (ARect.Top <> FLastRect.Top)
    or (ARect.Right <> FLastRect.Right) or (ARect.Bottom <> FLastRect.Bottom) then
  begin
    FParBrushSkip := -1;
    { A RESIZE IS AN UPDATE WITH A PAYLOAD (type 'resize'): the brush's
      visual stage dispatches brushSelect, and resize() triggers `updated`
      after it -- not for the first layout, an export's or a stream's
      [milestone D5-D8: a resize published nothing] }
    if (FLastPPI > 0) and not FExporting and not FStreamRelayout then
    begin
      FBrushPayload := True;
      FResizeDue := True;
    end;
  end;
  FLastRect := ARect;
  FLastPPI := APPI;
  { a new layout: a progress frame's list is not this one's [Batch 119] }
  FProgReuse := False;
  { A FULL UPDATE measures the axes again: what appendData froze goes
    [Batch 119] }
  if not FStreamRelayout and not FExporting then
  begin
    FFrozenOn := False;
    FFrozen := nil;
    FFrozenKeys := nil;
  end;
  { a full update: the next sync re-renders the states [Batch 88] }
  Inc(FStGen);
  { the legend is rendered anew: its buttons are new elements in no state
    [Batch 98] }
  FLegendSelHoverLegend := -1;
  FLegendSelHoverIdx := -1;
  { A NEW LAYOUT SNAPS: a resize, a theme -- upstream sets those directly
    ({duration: 0}) -- and a new option is armed again after the build
    [Batch 89]. A NEW OPTION UPDATES: the render before it is kept -- its
    list, its keys, its build -- for the render that arms it, and the
    proxies run on [Batch 90]. So does a full update of the same option, a
    legend toggle or a dataZoom (AnimFullBegin) [Batch 96]. }
  if FAnimPending and (FAnimMode <> camOff) and not (csDesigning in ComponentState) then
  begin
    if not FAnimPrev.Valid then AnimSnapshot;
  end
  else
    AnimDropAll;
  { a new option's data: the pieces the old one still named go with it
    [milestone D5-D8] }
  if FAnimPending and not FAnimFull then FUtStale := nil;
  { a render: the next list rolls the lines' history [F3b] }
  if not FStreamRelayout and not FExporting then FLineHistDue := True;
  Rebuild;
  { THE PIPELINES, from the counts the filters left -- before the bars ask
    which of them are large [Batch 119] }
  ProgUpdate;
  { The layout pass measures the labels the PAINT pass will draw, so it has to
    be handed the same font and the same gaps. Resolving them here rather than
    inside the builder keeps that unit free of the controller, which is the
    whole reason the measurer is injected too. }
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  txt := Default(TTyAxisTextStyle);
  txt.FontName := labelS.FontName;
  txt.FontSizeLogical := ResolveFontSize(labelS);
  txt.FontWeight := labelS.FontWeight;
  { THE TIME AXIS' `rich.primary` DEFAULT, from the skin's primary rule: its
    weight, and its colour where it has one [Batch 104] }
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisLabelPrimary', '', []);
  txt.EmphasisFontWeight := labelS.FontWeight;
  txt.HasEmphasisColour := tpTextColor in labelS.Present;
  txt.EmphasisColour := Cardinal(labelS.TextColor);
  txt.LabelMarginLogical := ActiveController.Metric(TyAdvChartLabelMarginVar,
    TyAdvChartLabelMargin);
  txt.TickLengthLogical := ActiveController.Metric(TyAdvChartTickLenVar,
    TyAdvChartTickLen);
  txt.NameGapLogical := ActiveController.Metric(TyAdvChartNameGapVar,
    TyAdvChartNameGap);
  { THE AXIS LINE'S WIDTH, which a line cut at its breaks is snapped by
    [Batch 132] -- PaintAxis' LineWidth }
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisLine', '', []);
  if tpBorderWidth in labelS.Present then txt.AxisLineWidthLogical := labelS.BorderWidth
  else txt.AxisLineWidthLogical := 1;
  if txt.AxisLineWidthLogical < 0.05 then txt.AxisLineWidthLogical := 0.05;
  { the name is measured in the font it is drawn in }
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisName', '', []);
  txt.NameFontName := labelS.FontName;
  txt.NameFontSizeLogical := ResolveFontSize(labelS);
  txt.NameFontWeight := labelS.FontWeight;
  { THE OPTION'S ROOT textStyle BETWEEN THE THEME AND THE AXIS: upstream's
    getFont falls back to it, and free-standing text takes its colour
    [Batch 83] }
  { labels: the family and weight only -- their 12px and their token colour
    are defaults of their own; the name has neither and takes all four }
  lblHasCol := False;
  lblCol := 0;
  GlobalTextOver(txt.FontName, txt.FontSizeLogical, txt.FontWeight,
    lblHasCol, lblCol, [ttpWeight, ttpFamily]);
  GlobalTextOver(txt.NameFontName, txt.NameFontSizeLogical, txt.NameFontWeight,
    txt.HasGlobalColour, txt.GlobalColour, [ttpSize, ttpWeight, ttpFamily, ttpColour]);
  txt.RtGlobal := RtGlobal;
  { Measuring goes through the painter behind an interface rather than being
    called directly, so the layout layer stays free of the painter and a test
    can hand it a deterministic measurer instead of this machine's fonts. }
  TyLayoutGrids(FBuild, FOption, AMeasurer, APPI, txt, FAxisMemory);
  { THE BREAK AREAS on the final rects, the zigzags from the axes' caches
    [Batch 132] }
  TyLayoutBreakAreas(FBuild, FOption, FAxisMemory);
  { THE POLAR AXIS VIEWS, in the same fonts and gaps [Batch 111] }
  TyLayoutPolars(FPolars, FOption, AMeasurer, APPI, txt,
    ActiveController.Metric(TyAdvChartMinorTickLenVar, TyAdvChartMinorTickLen),
    FAxisMemory);
  { THE SINGLE AXES' VIEWS, in the same fonts and gaps [Batch 118] }
  TyLayoutSingles(FSingles, FOption, AMeasurer, APPI, txt,
    ActiveController.Metric(TyAdvChartMinorTickLenVar, TyAdvChartMinorTickLen),
    ActiveController.Metric(TyAdvChartSingleTickLenVar, TyAdvChartSingleTickLen),
    FAxisMemory);
  { AND THE RIVERS ON THEM }
  SolveRivers(APPI);
  { THE PARALLEL AXES, the same AxisBuilder [Batch 128] }
  TyLayoutParallels(FParallels, FOption, AMeasurer, APPI, txt,
    ActiveController.Metric(TyAdvChartMinorTickLenVar, TyAdvChartMinorTickLen),
    FAxisMemory);
  { AFTER phase C, for the reason on FBarCols. }
  { a large bar's barMinWidth defaults to half a pixel [Batch 117] }
  SetLength(largeBars, Length(FBindings));
  for i := 0 to High(largeBars) do largeBars[i] := LargeKindOf(i) = lgkBar;
  FBarCols := TySolveBarLayout(FOption, FBuild, FBindings, FStores, FIndex, largeBars);
  { AND THE BARS ON A POLAR [Batch 113] }
  FPolarBars := TySolvePolarBars(FOption, FBindings, FStores, FStacks, FIndex, FPolars);
  { AND THE CANDLES AND BOXES, by the same band [Batch 108] }
  FWhiskers := TySolveWhiskerLayouts(FOption, FBindings, FStores, FIndex);
  { AFTER THE BARS: a marker on a bar series sits on its own bar }
  SolveMarkers(APPI);
  { THE CALENDARS AND THE MATRICES were laid out by Rebuild, before the
    grids in their cells [Batch 151; a pie on a calendar is laid out in a
    day's cell, Batch 72; the matrices on the canvas, Batch 145] }
  { THE GEOS: their maps and views [Batch 146] }
  SolveGeos(APPI);
  SolvePies;
  SolveFunnels;
  SolveGauges(APPI);
  SolveRadars(APPI);
  SolveGraphs(APPI);
  { the graph renders: the thumbnail's copy is taken at the next list
    [Batch 140] }
  FThumbSnapDue := True;
  SolveTrees(APPI);
  SolveSunbursts(APPI);
  SolveTreemaps(AMeasurer, APPI);
  SolveSankeys(APPI);
  SolveChords(APPI);
  { THE LINES, on the coordinate systems laid out above; an update's render
    clears a trail's layer (LinesView.render's layer.clear(true))
    [Batch 121] }
  SolveLines(APPI);
  FreeAndNil(FTrailLayer);
  { THE CUSTOM SERIES, on the coordinate systems laid out above: renderItem
    runs here, once per item shown [Batch 123] }
  SolveCustom(APPI);
  { THE PARALLEL ROWS, on their parallels [Batch 128] }
  SolveParallels(APPI);
  SolveTitles(AMeasurer, APPI);
  SolveLegends(AMeasurer, APPI);
  SolveVisualMapViews(AMeasurer, APPI);
  { AFTER THE GRIDS: a slider sits under (or beside) the grid it drives,
    by the rect the labels left it }
  SolveDataZoomViews(AMeasurer, APPI);
  { the timeline's view: its render, its play timer [Batch 129] }
  if not FStreamRelayout and not FExporting then SolveTimeline(APPI);
  { the toolbox, laid out last as its view renders last [Batch 125] }
  SolveToolboxes(AMeasurer, APPI);
  { the brush components: the visual stage's layoutCovers, then every brush
    view's render -- the covers laid from the model's areas [Batch 126] }
  if not FStreamRelayout and not FExporting then BrushPass;
  { every parallelAxis view's BrushController, its covers from the axis'
    active intervals [Batch 130] }
  if not FStreamRelayout and not FExporting then ParBrushPass;
  { THE BRUSH'S VISUAL STAGE [Batch 127]: what every brush selects, its
    inBrush / outOfBrush visuals over the rows the visual stages left, and
    -- for an action's update -- brushSelect through the throttle }
  if not FStreamRelayout then
  begin
    BrushVisCapture;
    BrushSelectRun(FBrushPayload and not FExporting, False);
    if FBrushActDepth = 0 then BrushFlush;
  end;
  FDirty := False;
  { [F3b] a force graph's iteration the render started runs on the timer }
  if GraphForceLive then AnimArmTimer;
  { [F4b] the axis pointers a re-render kept }
  TipKeepRestore;
  { the update's flush: `rendered` once it is painted [Batch 119] }
  if not FStreamRelayout and not FExporting then FFlushDue := True;
  { a resize's `updated`, after its brushselected [milestone D5-D8] }
  if FResizeDue and not FStreamRelayout and not FExporting then
  begin
    FResizeDue := False;
    EmitUpdated;
  end;
end;

{ ==================== axis breaks [Batch 132] ==================== }

function TTyCustomAdvanceChart.BreakAxisOf(AAxisKey: Integer; out AGrid: TTyGridBuild): TTyAxis;
var g, a: Integer;
begin
  Result := nil;
  AGrid := nil;
  { a singleAxis [F4a]: cBreakSingleKey + its index, no grid }
  if AAxisKey >= cBreakSingleKey then
  begin
    a := AAxisKey - cBreakSingleKey;
    if (a <= High(FSingles)) and (FSingles[a] <> nil) then Result := FSingles[a].Axis;
    Exit;
  end;
  if FBuild = nil then Exit;
  g := AAxisKey div 1000;
  a := AAxisKey mod 1000;
  if (g < 0) or (g >= FBuild.GridCount) then Exit;
  AGrid := FBuild.Grid(g);
  if a < AGrid.XAxisCount then Result := AGrid.XAxis(a)
  else if a - AGrid.XAxisCount < AGrid.YAxisCount then
    Result := AGrid.YAxis(a - AGrid.XAxisCount);
end;

{ zrender's hit test of a break group: the polygon's fill, or within half
  the strokeContainThreshold (5) of either polyline -- they have no fill }
function TTyCustomAdvanceChart.BreakAreaAt(AX, AY: Integer; out AAxisKey, AArea: Integer): Boolean;
var
  g, a, q, pass: Integer;
  gb: TTyGridBuild;
  axo: TTyAxis;
  spec: PTyAxisLayoutSpec;
  opt: TTyBreakAreaOpt;

  function NearLine(const P: TTyBreakPointArray): Boolean;
  var
    i: Integer;
    dx, dy, len2, t, px, py: Double;
  begin
    Result := False;
    for i := 1 to High(P) do
    begin
      dx := P[i].X - P[i - 1].X;
      dy := P[i].Y - P[i - 1].Y;
      len2 := dx * dx + dy * dy;
      if len2 = 0 then t := 0
      else t := ((AX - P[i - 1].X) * dx + (AY - P[i - 1].Y) * dy) / len2;
      if t < 0 then t := 0;
      if t > 1 then t := 1;
      px := P[i - 1].X + t * dx - AX;
      py := P[i - 1].Y + t * dy - AY;
      if px * px + py * py <= 2.5 * 2.5 then Exit(True);
    end;
  end;

  { nonzero winding over A, then B backwards }
  function InPolygon(const PA, PB: TTyBreakPointArray): Boolean;
  var
    pts: TTyBreakPointArray;
    i, j, w: Integer;
    x0, y0, x1, y1: Double;
  begin
    SetLength(pts, Length(PA) + Length(PB));
    for i := 0 to High(PA) do pts[i] := PA[i];
    for i := 0 to High(PB) do pts[Length(PA) + i] := PB[High(PB) - i];
    w := 0;
    for i := 0 to High(pts) do
    begin
      j := (i + 1) mod Length(pts);
      x0 := pts[i].X; y0 := pts[i].Y;
      x1 := pts[j].X; y1 := pts[j].Y;
      if y0 <= AY then
      begin
        if (y1 > AY) and ((x1 - x0) * (AY - y0) - (AX - x0) * (y1 - y0) > 0) then Inc(w);
      end
      else if (y1 <= AY) and ((x1 - x0) * (AY - y0) - (AX - x0) * (y1 - y0) < 0) then Dec(w);
    end;
    Result := w <> 0;
  end;

begin
  Result := False;
  AAxisKey := -1;
  AArea := -1;
  { THE SINGLES' first: drawn after the grids' [F4a] }
  for a := High(FSingles) downto 0 do
  begin
    if (FSingles[a] = nil) or (Length(FSingles[a].View.Spec.BreakAreas) = 0) then Continue;
    axo := FSingles[a].Axis;
    opt := TyBreakAreaOptOf(FOption.ComponentAt(axo.MainType, axo.ComponentIndex));
    if not opt.ExpandOnClick then Continue;
    spec := @FSingles[a].View.Spec;
    for q := High(spec^.BreakAreas) downto 0 do
      if (spec^.BreakAreas[q].HasB and InPolygon(spec^.BreakAreas[q].A, spec^.BreakAreas[q].B))
        or NearLine(spec^.BreakAreas[q].A)
        or (spec^.BreakAreas[q].HasB and NearLine(spec^.BreakAreas[q].B)) then
      begin
        AAxisKey := cBreakSingleKey + a;
        AArea := q;
        Exit(True);
      end;
  end;
  if FBuild = nil then Exit;
  { the x axes' areas are drawn over the y axes' (their views render
    later): asked first }
  for pass := 1 downto 0 do
    for g := FBuild.GridCount - 1 downto 0 do
    begin
      gb := FBuild.Grid(g);
      for a := gb.XAxisCount + gb.YAxisCount - 1 downto 0 do
      begin
        if (pass = 1) <> (a < gb.XAxisCount) then Continue;
        if a < gb.XAxisCount then axo := gb.XAxis(a) else axo := gb.YAxis(a - gb.XAxisCount);
        if axo = nil then Continue;
        spec := gb.SpecFor(axo);
        if (spec = nil) or (Length(spec^.BreakAreas) = 0) then Continue;
        opt := TyBreakAreaOptOf(FOption.ComponentAt(axo.MainType, axo.ComponentIndex));
        { silent unless it expands }
        if not opt.ExpandOnClick then Continue;
        for q := High(spec^.BreakAreas) downto 0 do
          if (spec^.BreakAreas[q].HasB and InPolygon(spec^.BreakAreas[q].A, spec^.BreakAreas[q].B))
            or NearLine(spec^.BreakAreas[q].A)
            or (spec^.BreakAreas[q].HasB and NearLine(spec^.BreakAreas[q].B)) then
          begin
            AAxisKey := g * 1000 + a;
            AArea := q;
            Exit(True);
          end;
      end;
    end;
end;

procedure TTyCustomAdvanceChart.BreakAreaClickAt(AAxisKey, AArea: Integer);
var
  gb: TTyGridBuild;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
begin
  ax := BreakAxisOf(AAxisKey, gb);
  if ax = nil then Exit;
  if AAxisKey >= cBreakSingleKey then
    spec := @FSingles[AAxisKey - cBreakSingleKey].View.Spec
  else
    spec := gb.SpecFor(ax);
  if (spec = nil) or (AArea < 0) or (AArea > High(spec^.BreakAreas)) then Exit;
  BreakExpandClick(AAxisKey, spec^.BreakAreas[AArea].BreakIndex);
end;

procedure TTyCustomAdvanceChart.BreakExpandClick(AAxisKey, ABreakIndex: Integer);
var
  gb: TTyGridBuild;
  ax: TTyAxis;
  brks: TTyAxisBreakArray;
begin
  ax := BreakAxisOf(AAxisKey, gb);
  if (ax = nil) or (ax.Scale.BreakMapper = nil) then Exit;
  brks := ax.Scale.BreakMapper.BreakList;
  if (ABreakIndex < 0) or (ABreakIndex > High(brks)) then Exit;
  { {type, breaks: [{start, end}]}, then `${dim}AxisIndex` }
  DispatchAction('{"type":"expandAxisBreak","breaks":[{"start":' + brks[ABreakIndex].StartJson
    + ',"end":' + brks[ABreakIndex].EndJson + '}],"' + ax.Dim + 'AxisIndex":'
    + IntToStr(ax.ComponentIndex) + '}');
end;

procedure TTyCustomAdvanceChart.DoAxisBreakAction(APayload: TJSONObject);
var
  t, evBreaks, payloadJson: string;
  m: Integer;
  idx: TTyIntegerArray;
  mains: array[0..2] of string;
  i, k, j: Integer;
  node, bo, inp: TJSONObject;
  arr, inputs: TJSONData;
  old, now_: Boolean;
  d: TJSONData;

  function JsonOrUndefined(AData: TJSONData): string;
  begin
    if AData = nil then Result := 'null' else Result := AData.AsJSON;
  end;

  function Identity(AObj: TJSONObject): string;
  begin
    Result := TyBreakJsText(AObj.Find('start')) + '_'#0'_' + TyBreakJsText(AObj.Find('end'));
  end;

  { parseFinder for one axis family: <main>Index (a number, a list,
    'all'), else <main>Id, else <main>Name; nothing named, no axis }
  function Query(const AMain: string): TTyIntegerArray;
  var
    q, n, c: Integer;
    dd: TJSONData;
    v: string;

    procedure Add(AIndex: Integer);
    var z: Integer;
    begin
      if not (FOption.ComponentAt(AMain, AIndex) is TJSONObject) then Exit;
      for z := 0 to High(Result) do
        if Result[z] = AIndex then Exit;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := AIndex;
    end;

    function Wanted(AData: TJSONData; const AText: string): Boolean;
    var z: Integer;
    begin
      Result := False;
      if AData is TJSONArray then
      begin
        for z := 0 to AData.Count - 1 do
          if (TJSONArray(AData).Items[z].JSONType in [jtString, jtNumber])
            and (TJSONArray(AData).Items[z].AsString = AText) then Exit(True);
      end
      else if AData.JSONType in [jtString, jtNumber] then
        Result := AData.AsString = AText;
    end;

  begin
    Result := nil;
    c := FOption.ComponentCount(AMain);
    dd := APayload.Find(AMain + 'Index');
    if (dd <> nil) and (dd.JSONType <> jtNull) then
    begin
      if (dd.JSONType = jtString) and (dd.AsString = 'all') then
        for q := 0 to c - 1 do Add(q)
      else if dd is TJSONArray then
      begin
        for q := 0 to dd.Count - 1 do
          if TJSONArray(dd).Items[q].JSONType = jtNumber then
          begin
            n := Trunc(TJSONArray(dd).Items[q].AsFloat);
            if (n >= 0) and (n < c) then Add(n);
          end;
      end
      else if dd.JSONType = jtNumber then
      begin
        n := Trunc(dd.AsFloat);
        if (n >= 0) and (n < c) then Add(n);
      end;
      Exit;
    end;
    dd := APayload.Find(AMain + 'Id');
    if (dd <> nil) and (dd.JSONType <> jtNull) then
    begin
      for q := 0 to c - 1 do
      begin
        v := ComponentModelId(AMain, q);
        if (v <> '') and Wanted(dd, v) then Add(q);
      end;
      Exit;
    end;
    dd := APayload.Find(AMain + 'Name');
    if (dd <> nil) and (dd.JSONType <> jtNull) then
      for q := 0 to c - 1 do
        if Wanted(dd, ComponentModelName(AMain, q)) then Add(q);
  end;

begin
  t := APayload.Strings['type'];
  { a batch item's own type: updateModelAxisBreak reads payload.type }
  if FBreakActAsSet then t := FBreakActAs;
  FBreakActAsSet := False;
  payloadJson := APayload.AsJSON;
  evBreaks := '';
  mains[0] := 'xAxis';
  mains[1] := 'yAxis';
  { and the singles' [F4a] }
  mains[2] := 'singleAxis';
  inputs := APayload.Find('breaks');
  for m := 0 to 2 do
  begin
    idx := Query(mains[m]);
    for i := 0 to High(idx) do
    begin
      node := TJSONObject(FOption.ComponentAt(mains[m], idx[i]));
      arr := node.Find('breaks');
      if not (inputs is TJSONArray) then Continue;
      for k := 0 to inputs.Count - 1 do
      begin
        if not (TJSONArray(inputs).Items[k] is TJSONObject) then Continue;
        inp := TJSONObject(TJSONArray(inputs).Items[k]);
        bo := nil;
        if arr is TJSONArray then
          for j := 0 to arr.Count - 1 do
            if (TJSONArray(arr).Items[j] is TJSONObject)
              and (Identity(TJSONObject(TJSONArray(arr).Items[j])) = Identity(inp)) then
            begin
              bo := TJSONObject(TJSONArray(arr).Items[j]);
              Break;
            end;
        if bo = nil then Continue;
        d := bo.Find('isExpanded');
        old := (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
          or ((d.JSONType = jtNumber) and (d.AsFloat <> 0) and not IsNan(d.AsFloat))
          or ((d.JSONType = jtString) and (d.AsString <> ''))
          or (d.JSONType in [jtArray, jtObject]));
        if t = 'expandAxisBreak' then now_ := True
        else if t = 'collapseAxisBreak' then now_ := False
        else if t = 'toggleAxisBreak' then now_ := not old
        { a type none of the three: the break as it is }
        else now_ := old;
        if (t = 'expandAxisBreak') or (t = 'collapseAxisBreak')
          or (t = 'toggleAxisBreak') then
        begin
          if d <> nil then bo.Delete('isExpanded');
          bo.Add('isExpanded', now_);
          { [R2-I6] a write into the tree outside a merge }
          FOption.Touch;
        end;
        if evBreaks <> '' then evBreaks := evBreaks + ',';
        evBreaks := evBreaks + '{"' + mains[m] + 'Index":' + IntToStr(idx[i])
          + ',"start":' + JsonOrUndefined(bo.Find('start'))
          + ',"end":' + JsonOrUndefined(bo.Find('end'))
          + ',"isExpanded":' + BoolToStr(now_, 'true', 'false')
          + ',"old":{"isExpanded":' + BoolToStr(old, 'true', 'false') + '}}';
      end;
    end;
  end;
  { the update renders with the new state, then the refined event }
  FullUpdate;
  FDirty := True;
  Invalidate;
  { THE NON-REFINED EVENT, which no handler hears but the connect listener:
    a copy of the payload, the type lowercased [Batch 141] }
  if (FEvSilent = 0) and (FBatchCapDepth = 0) then
    ConnectBroadcast(LowerCase(t), CopyWithType(APayload, LowerCase(t)), nil);
  EmitPayloadEvent('axisbreakchanged', '{"type":"axisbreakchanged","breaks":['
    + evBreaks + '],"fromAction":"' + StringToJSONString(t)
    + '","fromActionPayload":' + payloadJson + ',"escapeConnect":true}');
end;

procedure TTyCustomAdvanceChart.PaintBreakAreas(APainter: TTyPainter);
var
  pass, g, a, si: Integer;
  gb: TTyGridBuild;
  axo: TTyAxis;
  spec: PTyAxisLayoutSpec;
  prox_: Boolean;
  pa, pb, pc: TTyBreakPointArray;
  opt: TTyBreakAreaOpt;
  st: TTyStyleSet;
  stroke, fill: TTyColor;
  cc: TTyChartColor;
  lw, op: Double;
  hasStroke, hasFill: Boolean;

  { A BREAK LEAF IN ITS groupTransition [F4a]: its points where the axis
    proxy of its anid has them now, while the axes move }
  function Prox(const AAnid: string; const ADef: TTyBreakPointArray): TTyBreakPointArray;
  var
    p: TTyChartAnimProxy;
    v: TTyAnimValue;
    z: Integer;
  begin
    Result := ADef;
    if not prox_ then Exit;
    p := AxisProxyOf(TyAxisAnimKey(axo.MainType + IntToStr(axo.ComponentIndex), AAnid));
    if p = nil then Exit;
    v := p.GetAnimProp('shape.points');
    if (v.Kind <> avkArray) or (v.Stride <> 2) then Exit;
    SetLength(Result, Length(v.Arr) div 2);
    for z := 0 to High(Result) do
      Result[z] := TyPointF(v.Arr[2 * z], v.Arr[2 * z + 1]);
  end;

  procedure Line(const P: TTyBreakPointArray);
  var z: Integer;
  begin
    if (Length(P) = 0) or not hasStroke then Exit;
    APainter.BeginPath;
    APainter.MoveTo(P[0].X, P[0].Y);
    for z := 1 to High(P) do APainter.LineTo(P[z].X, P[z].Y);
    APainter.SetLineDash(opt.Dash);
    APainter.StrokePath(stroke, lw);
    APainter.SetLineDash([]);
  end;

  procedure Areas;
  var q, i: Integer;
  begin
    opt := TyBreakAreaOptOf(FOption.ComponentAt(axo.MainType, axo.ComponentIndex));
    { THE SKIN'S COLOURS unless the option writes its own; the skin's fill
      carries its opacity, an author's colour takes the option's (0.6
      unless written) }
    hasStroke := tpBorderColor in st.Present;
    stroke := st.BorderColor;
    if opt.HasBorderColor and TyTryParseChartColor(opt.BorderColor, cc) then
    begin
      stroke := TTyColor(cc);
      hasStroke := True;
    end;
    if not IsNan(opt.BorderWidth) then lw := opt.BorderWidth
    else if tpBorderWidth in st.Present then lw := st.BorderWidth
    else lw := 1;
    if lw <= 0 then hasStroke := False;
    hasFill := tpBackground in st.Present;
    fill := st.Background.Color;
    op := opt.Opacity;
    if opt.HasColor and TyTryParseChartColor(opt.Color, cc) then
    begin
      fill := TTyColor(cc);
      hasFill := True;
      if IsNan(op) then op := 0.6;
    end;
    if not IsNan(op) then
    begin
      if op < 0 then op := 0;
      if op > 1 then op := 1;
      fill := TTyColor((Cardinal(fill) and $00FFFFFF)
        or (Cardinal(Round(((Cardinal(fill) shr 24) and $FF) * op)) shl 24));
    end;
    for q := 0 to High(spec^.BreakAreas) do
    begin
      pa := Prox('break_a_' + spec^.BreakAreas[q].Id, spec^.BreakAreas[q].A);
      Line(pa);
      if not spec^.BreakAreas[q].HasB then Continue;
      pb := Prox('break_b_' + spec^.BreakAreas[q].Id, spec^.BreakAreas[q].B);
      Line(pb);
      { from A's end back along B: the band between them -- the polygon's
        own points while it moves }
      pc := nil;
      SetLength(pc, Length(spec^.BreakAreas[q].A) + Length(spec^.BreakAreas[q].B));
      for i := 0 to High(spec^.BreakAreas[q].A) do pc[i] := spec^.BreakAreas[q].A[i];
      for i := 0 to High(spec^.BreakAreas[q].B) do
        pc[Length(spec^.BreakAreas[q].A) + i] :=
          spec^.BreakAreas[q].B[High(spec^.BreakAreas[q].B) - i];
      pc := Prox('break_c_' + spec^.BreakAreas[q].Id, pc);
      if hasFill and (Length(pc) > 0) then
      begin
        APainter.BeginPath;
        APainter.MoveTo(pc[0].X, pc[0].Y);
        for i := 1 to High(pc) do APainter.LineTo(pc[i].X, pc[i].Y);
        APainter.FillPath(fill);
      end;
    end;
  end;

begin
  if FOption = nil then Exit;
  st := ActiveController.Model.ResolveStyle('TyAdvChartBreakArea', '', []);
  { the grids' break leaves from their proxies while the axes move }
  prox_ := AxesDynamic and not FExporting;
  { the y axes' views first, as upstream renders them }
  if FBuild <> nil then
    for pass := 0 to 1 do
      for g := 0 to FBuild.GridCount - 1 do
      begin
        gb := FBuild.Grid(g);
        for a := 0 to gb.XAxisCount + gb.YAxisCount - 1 do
        begin
          if (pass = 0) <> (a >= gb.XAxisCount) then Continue;
          if a < gb.XAxisCount then axo := gb.XAxis(a) else axo := gb.YAxis(a - gb.XAxisCount);
          if axo = nil then Continue;
          spec := gb.SpecFor(axo);
          if (spec = nil) or (Length(spec^.BreakAreas) = 0) then Continue;
          Areas;
        end;
      end;
  { the singles' [F4a]: in the view's group, out of the groupTransition }
  prox_ := False;
  for si := 0 to High(FSingles) do
  begin
    if FSingles[si] = nil then Continue;
    axo := FSingles[si].Axis;
    spec := @FSingles[si].View.Spec;
    if Length(spec^.BreakAreas) = 0 then Continue;
    Areas;
  end;
end;

procedure TTyCustomAdvanceChart.SolveSeriesColors;

  { An unnamed series is NOT nameless as far as the palette is concerned.
    Upstream builds `series` + NUL + index precisely so two unnamed series
    cannot collide in the memo, and its comment says so. Leaving it empty
    would give every unnamed series the first colour. }
  function NameFor(ASlot: Integer): string;
  begin
    Result := SeriesNameOf(ASlot);
    if Result = '' then Result := TyChartSeriesDefaultName(ASlot);
  end;

var
  i, n, count: Integer;
  chartScope, ownScope: TTyPaletteScope;
  chartPal, ownPal: TTyPalette;
  chartLayers, ownLayers: TTyPaletteLayers;
  node: TJSONObject;
  d: TJSONData;
  st: string;
  style: TTyOptStyle;
  key, other: TTyOptColor;
  hasAuto: Boolean;
  isCb: Boolean;
  sd: TJSONData;
begin
  FSeriesColors := nil;
  FSeriesColorKnown := nil;
  FSeriesColorNone := nil;
  FSeriesPick := nil;
  FSeriesPickAsked := nil;
  FSeriesFromPick := nil;
  FSeriesColorFromPalette := nil;
  if FOption = nil then Exit;
  n := FOption.ComponentCount('series');
  SetLength(FSeriesColors, n);
  SetLength(FSeriesColorKnown, n);
  SetLength(FSeriesColorNone, n);
  SetLength(FSeriesPick, n);
  SetLength(FSeriesPickAsked, n);
  SetLength(FSeriesFromPick, n);
  SetLength(FSeriesColorFromPalette, n);
  { THE THEME STANDS WHERE UPSTREAM'S DEFAULT PALETTE STANDS, through the same
    cursor: a written colour takes no slot from it and two series of one name
    share one, exactly as with an authored list. [Batch 105: the theme ramp
    was read by series index, so the series after a written colour skipped a
    slot.] }
  chartPal := TyChartRootPalette(FOption);
  chartLayers := TyChartPaletteLayersOf(FOption, -1);
  chartScope := Default(TTyPaletteScope);
  { getSeriesCount(): the series MODELS, so an index hole is not counted --
    the count is what chooses a colorLayer }
  count := 0;
  for i := 0 to n - 1 do
    if FOption.ComponentAt('series', i) is TJSONObject then Inc(count);

  { DECLARATION ORDER, AND EVERY SLOT. A series the legend switched off still
    takes its colour, and so does one whose type has no renderer -- that is the
    entire mechanism by which colours stay put across a legend click. Skipping
    the hidden ones would re-shuffle every colour after them. }
  for i := 0 to n - 1 do
  begin
    d := FOption.ComponentAt('series', i);
    node := nil;
    if (d <> nil) and (d.JSONType = jtObject) then node := TJSONObject(d);
    { AN INDEX HOLE takes no colour: eachSeries never meets it, so the
      series after it pick on from the palette [Batch 97] }
    if node = nil then Continue;
    st := '';
    d := node.Find('type');
    if (d <> nil) and (d.JSONType = jtString) then st := d.AsString;

    { WHICH KEY SUPPRESSES THE PALETTE depends on what the series draws with.
      Nearly everything fills, so it is `itemStyle.color`; a boxplot draws with
      its stroke, so it is `itemStyle.borderColor`; `lines` and `parallel` read
      a different block entirely. A line is NOT one of the exceptions -- writing
      `lineStyle.color` on a line does not stop it taking a palette slot. }
    style := TyReadOptStyle(node, TyStyleAccessPath(st));
    if TyStyleDrawsWithStroke(st) and (TyStyleAccessPath(st) = 'itemStyle') then
    begin
      key := style.BorderColor;
      other := style.Color;
    end
    else
    begin
      key := style.Color;
      other := style.BorderColor;
    end;
    { `auto` ON EITHER HALF OF THE PAIR sends this series to the palette,
      even when the other half names a colour -- upstream tests `fill` AND
      `stroke` for the word and consults the palette if either carries it.
      So `{ color: '#fff', borderColor: 'auto' }` is a white bar with a
      border in the palette colour, and it costs a slot. }
    hasAuto := key.IsAuto or other.IsAuto;
    { [R2-J3] A COLOUR CALLBACK AT THE KEY is the style task's third reason
      to ask the palette, whatever the type's defaults name: the series takes
      a slot and its callback's params carry that colour (a tree with one is
      the palette's, not lightsteelblue's) }
    isCb := False;
    sd := node.Find(TyStyleAccessPath(st));
    if sd is TJSONObject then
    begin
      if TyStyleDrawsWithStroke(st) and (TyStyleAccessPath(st) = 'itemStyle') then
        sd := TJSONObject(sd).Find('borderColor')
      else
        sd := TJSONObject(sd).Find('color');
      isCb := (sd <> nil) and (sd.JSONType = jtString) and TyChartIsHandlerRef(sd.AsString);
    end;
    if isCb then hasAuto := True;

    { A TYPE WHOSE DEFAULTS NAME THE COLOUR takes no slot either: the style
      task reads itemStyle through the series' defaultOption, and a
      candlestick's says '#eb5454' -- so a bar beside it takes the palette's
      FIRST colour, not its second. [Batch 65: the bar took the second, and
      its markers with it.] }
    if (st = 'candlestick') and (not key.Written) and (not hasAuto) then
    begin
      FSeriesColors[i] := TTyChartColor($FFEB5454);
      FSeriesColorKnown[i] := True;
      Continue;
    end;
    { A TREE'S DEFAULTS NAME ITS COLOUR TOO (lightsteelblue upstream), so it
      takes no slot and a series after it keeps its own; the colour is the
      theme's. [Batch 73] }
    if (st = TyTreeSeriesTypeName) and (not key.Written) and (not hasAuto) then
    begin
      FSeriesColors[i] := TTyChartColor(ActiveController.Model.ResolveStyle(
        'TyAdvChartTreeNode', '', []).Background.Color);
      FSeriesColorKnown[i] := True;
      Continue;
    end;

    if key.Written and not hasAuto then
    begin
      { AN AUTHORED COLOUR CONSUMES NO SLOT, and upstream says why in a comment:
        an author who paints one series transparent, or as a backdrop, did not
        mean to shift every other series' colour. `series: [{}, {color}, {}]` is
        palette[0], the authored one, palette[1]. }
      if not key.IsNone then
      begin
        FSeriesColors[i] := key.Color;
        FSeriesColorKnown[i] := True;
      end
      else
        { WRITTEN AS `none`: no fill at all -- which also makes an inside
          label an outside one. [Revised in batch 47: it fell through to the
          theme's colour.] }
        FSeriesColorNone[i] := True;
      Continue;
    end;

    { SeriesModel.getColorFromPalette(name, null, getSeriesCount()): the
      series' own `color` / `colorLayer` over a scope of its own, and when
      that answers nothing the chart's over the chart's scope. `auto` asks as
      surely as writing nothing does -- it means `the palette colour`, so it
      has to have one. [Batch 105: colorLayer] }
    ownPal := TySeriesOwnPalette(FOption, i);
    ownLayers := TyChartPaletteLayersOf(FOption, i);
    ownScope := Default(TTyPaletteScope);
    FSeriesPick[i] := TySeriesPaletteFrom(ownPal, ownLayers, chartPal,
      chartLayers, NameFor(i), ownScope, chartScope, count);
    FSeriesPickAsked[i] := True;
    { [R2-J3] a colour callback says the colour is not the palette's
      (seriesStyleTask: colorFromPalette false) -- no per-datum palette }
    FSeriesColorFromPalette[i] := (not key.Written) and not isCb;
    { THE PICK IS NOT ALWAYS THE FILL. It becomes the fill only when the
      fill was left unwritten, or was written as `auto`; a series that
      named its fill and asked for `auto` somewhere else keeps the name
      it gave. }
    if (not key.Written) or key.IsAuto then
      FSeriesFromPick[i] := True
    else if not key.IsNone then
    begin
      FSeriesColors[i] := key.Color;
      FSeriesColorKnown[i] := True;
    end
    else
      FSeriesColorNone[i] := True;
  end;
end;

function TTyCustomAdvanceChart.MarkerLayout(ASeriesIndex: Integer;
  AKind: TTyMarkerKind): TTyMkBlock;
var slot: Integer;
begin
  Result := Default(TTyMkBlock);
  Result.Kind := AKind;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FMarkers)) then Exit;
  Result := FMarkers[slot].Blocks[AKind];
end;

procedure TTyCustomAdvanceChart.SolveMarkers(APPI: Integer);
var
  i, k: Integer;
  b: TTySeriesBinding;
  ctx: TTyMkContext;
  node, nd: TJSONData;
  kind: TTyMarkerKind;
  ax: TTyAxis;
  scale: Double;
  pin: TTyMkPicInput;
  fpMask: TFPUExceptionMask;
begin
  FMarkers := nil;
  SetLength(FMarkers, Length(FBindings));
  FMarkLinePics := nil;
  SetLength(FMarkLinePics, Length(FBindings));
  FMarkPointPics := nil;
  SetLength(FMarkPointPics, Length(FBindings));
  FMarkAreaPics := nil;
  SetLength(FMarkAreaPics, Length(FBindings));
  if APPI <= 0 then APPI := 96;
  scale := APPI / 96;
  for i := 0 to High(FBindings) do
  begin
    b := FBindings[i];
    FMarkers[i] := Default(TTyMkSeries);
    FMarkers[i].SeriesIndex := b.SeriesIndex;
    for kind := Low(TTyMarkerKind) to High(TTyMarkerKind) do
      FMarkers[i].Blocks[kind].Kind := kind;
    { A SERIES THE LEGEND SWITCHED OFF DRAWS NO MARKERS -- upstream's
      marker views walk only the series the filter kept. [Batch 113: a
      polar's markers are; they were not ported.] }
    if (not b.Resolved) or ((b.Cart = nil) and (b.Polar = nil)) or b.Hidden
      or (i > High(FStores)) or (FStores[i] = nil) then Continue;
    node := FOption.ComponentAt('series', b.SeriesIndex);
    if (node = nil) or (node.JSONType <> jtObject) then Continue;
    ctx := Default(TTyMkContext);
    ctx.Store := FStores[i];
    ctx.Cart := b.Cart;
    { a polar's markers [Batch 113] }
    ctx.Polar := b.Polar;
    ctx.XAxis := b.XAxis;
    ctx.YAxis := b.YAxis;
    if b.Cart <> nil then ax := b.Cart.GetBaseAxis else ax := b.BaseAxis;
    if ax <> nil then
    begin
      ctx.BaseDim := ax.Dim;
      ctx.CsBaseHorizontal := ax.Horizontal;
    end;
    ctx.StackedCol := -1;
    ctx.StackResultCol := -1;
    if (i <= High(FStacks)) and FStacks[i].Stacked and (b.ValueAxis <> nil) then
    begin
      ctx.StackedCol := FStores[i].DimIndexOf(b.ValueAxis.Dim);
      ctx.StackResultCol := FStacks[i].ResultCol;
    end;
    ctx.IsBar := (b.SeriesType = 'bar') or (b.SeriesType = 'pictorialBar');
    ctx.BarOffset := NaN;
    ctx.BarSize := NaN;
    if ctx.IsBar and (i <= High(FBarCols)) then
    begin
      ctx.BarOffset := FBarCols[i].Offset;
      ctx.BarSize := FBarCols[i].Width;
    end;
    for k := 0 to 1 do
    begin
      if k = 0 then ax := ctx.XAxis else ax := ctx.YAxis;
      ctx.AlignWithLabel[k] := False;
      if ax = nil then Continue;
      nd := FOption.ComponentAt(ax.MainType, ax.ComponentIndex);
      if (nd <> nil) and (nd.JSONType = jtObject) then
      begin
        nd := TJSONObject(nd).Find('axisTick');
        if (nd <> nil) and (nd.JSONType = jtObject) then
        begin
          nd := TJSONObject(nd).Find('alignWithLabel');
          ctx.AlignWithLabel[k] := (nd <> nil) and (nd.JSONType = jtBoolean)
            and nd.AsBoolean;
        end;
      end;
    end;
    { seriesModel.get('silent'): a null or unwritten one climbs to the
      option root [F4c] }
    nd := TyGetShallowRoot(node, FOption.Root, 'silent');
    ctx.SeriesSilent := TyOptTruthy(nd);
    if FOption.Root is TJSONObject then ctx.Root := TJSONObject(FOption.Root)
    else ctx.Root := nil;
    ctx.Scale := scale;
    ctx.OriginX := FLastRect.Left;
    ctx.OriginY := FLastRect.Top;
    ctx.Width := (FLastRect.Right - FLastRect.Left) / scale;
    ctx.Height := (FLastRect.Bottom - FLastRect.Top) / scale;
    for kind := Low(TTyMarkerKind) to High(TTyMarkerKind) do
    begin
      { the ONE nd-level component of the kind is every series marker's
        parent; an array of them gives the first }
      nd := FOption.ComponentAt(TyMarkerKey[kind], 0);
      if (nd <> nil) and (nd.JSONType <> jtObject) then nd := nil;
      FMarkers[i].Blocks[kind] := TyMarkerSolve(kind, TJSONObject(node),
        TJSONObject(nd), ctx);
    end;
    { THE PICTURE of every marker, from the layout just solved }
    if FMarkers[i].Blocks[mkLine].Present or FMarkers[i].Blocks[mkPoint].Present
      or FMarkers[i].Blocks[mkArea].Present then
    begin
      pin := Default(TTyMkPicInput);
      pin.SeriesIndex := FMarkers[i].SeriesIndex;
      if SlotOfSeries(FMarkers[i].SeriesIndex) >= 0 then
        pin.SeriesType := FBindings[SlotOfSeries(FMarkers[i].SeriesIndex)].SeriesType;
      pin.SeriesColor := MarkerSeriesColorCss(i);
      pin.SeriesColorData := MarkerSeriesColorData(i);
      { [R2-V] THE HOST SERIES' NAME AS ITS MODEL HAS IT
        (MarkerModel.getDataParams: hostSeries.name) -- the written one, a
        number as its text, a dataset column's, or the generated
        'series' + NUL + index; the formatters' a and a handler's
        seriesName print it. [Was: undefined wherever the option wrote no
        string -- 'undefined' where upstream prints the name.] }
      pin.SeriesName := TyMkUndef;
      pin.SeriesName.Kind := mvkStr;
      pin.SeriesName.Str := SeriesModelName(FMarkers[i].SeriesIndex);
      nd := FOption.Find('textStyle');
      if (nd <> nil) and (nd.JSONType = jtObject) then pin.TextStyle := TJSONObject(nd);
      MarkerGround(pin.Background, pin.IsDark);
      pin.Scale := scale;
      pin.RtGlobal := RtGlobal;
      { [R2-J3] the itemName dimension: a category axis' coordinate }
      pin.NameDim := -1;
      if ctx.XAxis.AxisType = atCategory then pin.NameDim := 0
      else if ctx.YAxis.AxisType = atCategory then pin.NameDim := 1;
      { UNDER MASKED TRAPS: a corner of an unknown category is not a number,
        and upstream draws on regardless }
      fpMask := GetExceptionMask;
      SetExceptionMask(fpMask + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow,
        exPrecision]);
      try
      FMarkLinePics[i] := TyMkLinePictures(FMarkers[i].Blocks[mkLine], pin);
      { the default text reads the last coordinate dim a label may come
        from: not a category, not a time }
      FMarkPointPics[i] := TyMkPointPictures(FMarkers[i].Blocks[mkPoint], pin,
        not (ctx.XAxis.AxisType in [atCategory, atTime]),
        not (ctx.YAxis.AxisType in [atCategory, atTime]));
      FMarkAreaPics[i] := TyMkAreaPictures(FMarkers[i].Blocks[mkArea], pin);
      finally
        SetExceptionMask(fpMask);
      end;
    end;
  end;
end;

{ upstream's series style colour as a css string: what the author wrote in
  itemStyle.color, candlestick's own default, else the palette's }
function TTyCustomAdvanceChart.MarkerSeriesColorCss(ASlot: Integer): string;
var
  node, d: TJSONData;
  c: TTyColor;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (node <> nil) and (node.JSONType = jtObject) then
  begin
    d := TJSONObject(node).Find('itemStyle');
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      d := TJSONObject(d).Find('color');
      if (d <> nil) and (d.JSONType = jtString) then Exit(d.AsString);
    end;
  end;
  c := SeriesColor(FBindings[ASlot].SeriesIndex);
  if (c shr 24) = $FF then
    Result := '#' + LowerCase(IntToHex(c and $FFFFFF, 6))
  else
    Result := 'rgba(' + IntToStr((c shr 16) and $FF) + ',' + IntToStr((c shr 8) and $FF)
      + ',' + IntToStr(c and $FF) + ',' + TyJsNumberToString(TyChartColorAlpha(c)) + ')';
end;

{ the author's series colour when it is not a string: a gradient, used by a
  markArea as it is }
function TTyCustomAdvanceChart.MarkerSeriesColorData(ASlot: Integer): TJSONData;
var node, d: TJSONData;
begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('itemStyle');
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  d := TJSONObject(d).Find('color');
  if (d <> nil) and (d.JSONType = jtObject) then Result := d;
end;

{ THE GROUND upstream's marker label halo is made of: the option's
  backgroundColor, else 'transparent' -- and dark by the option's darkMode
  when it says, else by zrender's own luminance test }
procedure TTyCustomAdvanceChart.MarkerGround(out ABackground: string; out AIsDark: Boolean);
var
  d: TJSONData;
begin
  d := FOption.Find('backgroundColor');
  if (d <> nil) and (d.JSONType = jtString) then
    ABackground := d.AsString
  else
    { UPSTREAM'S GROUND, 'transparent', not the skin's: the picture is
      upstream's answer, and the paint takes the halo from the skin anyway }
    ABackground := 'transparent';
  d := FOption.Find('darkMode');
  if (d <> nil) and (d.JSONType = jtBoolean) then AIsDark := d.AsBoolean
  else AIsDark := TyMkGroundIsDark(ABackground);
end;

function TTyCustomAdvanceChart.MarkLinePictures(ASeriesIndex: Integer): TTyMkLinePicArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FMarkLinePics)) then Exit;
  Result := FMarkLinePics[slot];
end;

function TTyCustomAdvanceChart.MarkPointPictures(ASeriesIndex: Integer): TTyMkPointPicArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FMarkPointPics)) then Exit;
  Result := FMarkPointPics[slot];
end;

function TTyCustomAdvanceChart.DecalOfSeries(ASeriesIndex: Integer): TTyChartDecal;
var slot: Integer;
begin
  Result := Default(TTyChartDecal);
  slot := SlotOfSeries(ASeriesIndex);
  if (slot >= 0) and (slot <= High(FSeriesDecals)) then Result := FSeriesDecals[slot];
end;

function TTyCustomAdvanceChart.DecalOfRow(ASeriesIndex, ARawIndex: Integer): TTyChartDecal;
begin
  Result := RowDecalOf(SlotOfSeries(ASeriesIndex), ARawIndex);
end;

function TTyCustomAdvanceChart.RowDecalOf(ASlot, ARaw: Integer): TTyChartDecal;
begin
  Result := Default(TTyChartDecal);
  if (ASlot < 0) or (ASlot > High(FSeriesDecals)) then Exit;
  Result := FSeriesDecals[ASlot];
  if (ARaw >= 0) and (ARaw <= High(FRowDecalSet[ASlot]))
    and FRowDecalSet[ASlot][ARaw] then
    Result := FRowDecals[ASlot][ARaw];
end;

function TTyCustomAdvanceChart.RowDecalJson(ASlot, ARaw: Integer): TJSONData;
var
  r: TTyDecalRaw;
  k: TTyDecalKey;
begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FSeriesDecalRaws)) then Exit;
  r := FSeriesDecalRaws[ASlot];
  if (ARaw >= 0) and (ARaw <= High(FRowDecalSet[ASlot])) and FRowDecalSet[ASlot][ARaw]
    and (ARaw <= High(FRowDecalRaws[ASlot])) then
    r := FRowDecalRaws[ASlot][ARaw];
  if not r.Present then Exit;
  Result := TJSONObject.Create;
  for k := Low(TTyDecalKey) to High(TTyDecalKey) do
    if r.Keys[k] <> nil then
      TJSONObject(Result).Add(TyDecalKeyNames[k], r.Keys[k].Clone);
end;

function TTyCustomAdvanceChart.DecalGround: TTyChartColor;
begin
  Result := TTyChartColor(ActiveController.Model.ResolveStyle(TyDecalSkin, '',
    []).Background.Color);
end;

function TTyCustomAdvanceChart.RawRowDecals(ASlot: Integer): TTyChartDecalArray;
var k, n: Integer;
begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  n := FStores[ASlot].RawCount;
  SetLength(Result, n);
  for k := 0 to n - 1 do Result[k] := RowDecalOf(ASlot, k);
end;

function TTyCustomAdvanceChart.AriaDecalPalette(out APal: TJSONData;
  out APalN: Integer): Boolean;
var aria, d: TJSONData;
begin
  APal := nil;
  APalN := 0;
  Result := False;
  if (FOption = nil) or not (FOption.Root is TJSONObject) then Exit;
  aria := TJSONObject(FOption.Root).Find('aria');
  if not (AriaEnabled and (aria is TJSONObject)) then Exit;
  d := TJSONObject(aria).Find('decal');
  if not ((d is TJSONObject) and TyDecalTruthy(TJSONObject(d).Find('show'))) then Exit;
  APal := TyDecalPaletteOf(aria);
  APalN := TyDecalPaletteCount(APal);
  Result := True;
end;

{ THE TREES' DECALS [F4a]. decalVisual gives every node its item decal --
  dataStyleTask's own itemStyle.decal, else (getItemVisual's fallback) the
  series'. With aria.decal.show, setDecal leaves a treemap and a sunburst to
  enableAriaDecalForTree: over a scope new every call, every node in the
  tree's eachNode (pre-)order asks getDecalFromPalette for its depth-1
  ancestor's name, or that ancestor's data index -- the root asks for its
  own, the series' name as written -- and setVisual('decal') puts the
  palette's object in place of the node's, the node's own not merged. }
function TTyCustomAdvanceChart.TreeNodeDecals(ASlot: Integer; const AHier: TTyHierarchy;
  const AOrder: TTyIntegerArray): TTyChartDecalArray;
var
  n, r, k, cur, pick, palN: Integer;
  skin, ground: TTyChartColor;
  pal, d, node: TJSONData;
  scope: TTyDecalScope;
  nm: string;
begin
  Result := nil;
  n := Length(AHier.Nodes);
  SetLength(Result, n);
  if (ASlot < 0) or (ASlot > High(FBindings)) or FBindings[ASlot].Hidden then Exit;
  skin := TTyChartColor(ActiveController.Model.ResolveStyle(TyDecalSkin, '',
    []).TextColor);
  ground := DecalGround;
  if AriaDecalPalette(pal, palN) then
  begin
    scope := Default(TTyDecalScope);
    for k := 0 to High(AOrder) do
    begin
      r := AOrder[k];
      if (r < 0) or (r >= n) then Continue;
      cur := r;
      while (cur >= 0) and (AHier.Nodes[cur].Depth > 1) do cur := AHier.Nodes[cur].Parent;
      if cur < 0 then Continue;
      { convertOptionIdName(name, ''): a string, a number's text, else '' }
      if cur = 0 then node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex)
      else node := AHier.Nodes[cur].Item;
      nm := '';
      if node is TJSONObject then
      begin
        d := TJSONObject(node).Find('name');
        if d <> nil then
          case d.JSONType of
            jtString: nm := d.AsString;
            jtNumber: nm := TyJsonJsString(d);
          end;
      end;
      if nm = '' then nm := IntToStr(cur);
      pick := TyDecalFromPalette(scope, palN, nm);
      Result[r] := TyDecalResolve(TyDecalRawOf(TyDecalPaletteItem(pal, pick)), skin, ground);
    end;
    Exit;
  end;
  for r := 0 to n - 1 do
  begin
    Result[r] := DecalOfSeries(FBindings[ASlot].SeriesIndex);
    { a sunburst ignores the style on its data [F4a] }
    if FBindings[ASlot].SeriesType = TySunburstSeriesTypeName then Continue;
    node := AHier.Nodes[r].Item;
    if not (node is TJSONObject) then Continue;
    d := TJSONObject(node).Find('itemStyle');
    if not (d is TJSONObject) then Continue;
    d := TJSONObject(d).Find('decal');
    if TyDecalTruthy(d) and not TyDecalIsPrimitive(d) then
      Result[r] := TyDecalResolve(TyDecalRawOf(d), skin, ground);
  end;
end;

function TTyCustomAdvanceChart.AriaEnabled: Boolean;
var aria: TJSONData;
begin
  Result := False;
  if (FOption = nil) or not (FOption.Root is TJSONObject) then Exit;
  aria := TJSONObject(FOption.Root).Find('aria');
  { a merge that wrote enabled null leaves it null: off }
  Result := (aria is TJSONObject) and TyDecalTruthy(TJSONObject(aria).Find('enabled'));
end;

{ The aria visual's setDecal and the decal visual [Batch 131]:

  seriesStyleTask takes the series' style decal (itemStyle.decal, or the
  type's style path) as the series' `decal` visual and dataStyleTask a view
  row's own. With aria on and aria.decal.show truthy, every series the
  legend kept -- not a treemap or a sunburst, which decide their own --
  asks the decal palette: by its model NAME over the chart's scope when it
  is coloured by series, else every RAW row by its name (or its index) over
  a scope its TYPE shares with the others of the type, new each update; the
  palette's decal goes under the written one key by key. decalVisual then
  skips the series the legend filtered. A decal written as a string throws
  upstream (`dirty` set on a primitive): here it is none. }
procedure TTyCustomAdvanceChart.SolveDecals;
type
  TTypeScope = record
    Key: string;
    Scope: TTyDecalScope;
  end;
var
  scopes: array of TTypeScope;
  aria, pal, d: TJSONData;
  palN, si, slot, n, k, rawN, pick, t: Integer;
  useDecal, noItems: Boolean;
  skin, ground: TTyChartColor;
  node, item: TJSONObject;
  typ, path, nm: string;
  seriesRaw, palRaw: TTyDecalRaw;
  rows: array of TTyDecalRaw;
  rowSet: TTyBoolArray;
  st: TTyDataStore;
  dataScope: TTyDecalScope;
  items: TJSONArray;
  own: TTyDecalRaw;

  function OwnDecal(ANode: TJSONData): TTyDecalRaw;
  begin
    Result := Default(TTyDecalRaw);
    if not (ANode is TJSONObject) then Exit;
    ANode := TJSONObject(ANode).Find(path);
    { `rawItem[stylePath]` truthy, its decal truthy and no primitive }
    if not (ANode is TJSONObject) then Exit;
    ANode := TJSONObject(ANode).Find('decal');
    if TyDecalTruthy(ANode) and not TyDecalIsPrimitive(ANode) then
      Result := TyDecalRawOf(ANode);
  end;

begin
  n := Length(FBindings);
  FSeriesDecals := nil;
  FRowDecals := nil;
  FRowDecalSet := nil;
  FSeriesDecalRaws := nil;
  FRowDecalRaws := nil;
  SetLength(FSeriesDecals, n);
  SetLength(FRowDecals, n);
  SetLength(FRowDecalSet, n);
  SetLength(FSeriesDecalRaws, n);
  SetLength(FRowDecalRaws, n);
  if (FOption = nil) or not (FOption.Root is TJSONObject) then Exit;
  skin := TTyChartColor(ActiveController.Model.ResolveStyle(TyDecalSkin, '',
    []).TextColor);
  ground := DecalGround;
  aria := TJSONObject(FOption.Root).Find('aria');
  useDecal := AriaEnabled and (aria is TJSONObject);
  if useDecal then
  begin
    d := TJSONObject(aria).Find('decal');
    useDecal := (d is TJSONObject) and TyDecalTruthy(TJSONObject(d).Find('show'));
  end;
  pal := TyDecalPaletteOf(aria);
  palN := TyDecalPaletteCount(pal);
  scopes := nil;
  for si := 0 to FOption.ComponentCount('series') - 1 do
  begin
    slot := SlotOfSeries(si);
    if (slot < 0) or (slot > High(FBindings)) then Continue;
    if not (FOption.ComponentAt('series', si) is TJSONObject) then Continue;
    node := TJSONObject(FOption.ComponentAt('series', si));
    typ := FBindings[slot].SeriesType;
    path := TyStyleAccessPath(typ);
    seriesRaw := OwnDecal(node);
    { a sunburst and a tree say ignoreStyleOnData: dataStyleTask reads no
      item's style, so no item's decal [F4a] }
    noItems := (typ = TySunburstSeriesTypeName) or (typ = TyTreeSeriesTypeName);
    st := nil;
    if slot <= High(FStores) then st := FStores[slot];
    rows := nil;
    rowSet := nil;
    rawN := 0;
    if st <> nil then rawN := st.RawCount;
    { dataStyleTask: the view's rows only -- and only an object item has a
      decal of its own; the rows' arrays only once one has [R2-L] }
    items := nil;
    if not noItems then items := RawItemArray(slot);
    if items <> nil then
      for k := 0 to rawN - 1 do
        if (k < items.Count) and (items.Items[k] is TJSONObject)
          and (st.IndexOfRawIndex(k) >= 0) then
        begin
          own := OwnDecal(items.Items[k]);
          if not own.Present then Continue;
          if rows = nil then
          begin
            SetLength(rows, rawN);
            SetLength(rowSet, rawN);
          end;
          rows[k] := own;
          rowSet[k] := True;
        end;
    if useDecal and not FBindings[slot].Hidden and (typ <> TySunburstSeriesTypeName)
      and (typ <> TyTreemapSeriesTypeName) then
    begin
      if TyChartColorByOf(FOption, si, typ) = 'series' then
      begin
        nm := SeriesNameOf(si);
        if nm = '' then nm := TyChartSeriesDefaultName(si);
        pick := TyDecalFromPalette(FDecalScope, palN, nm);
        palRaw := TyDecalRawOf(TyDecalPaletteItem(pal, pick));
        seriesRaw := TyDecalMerge(palRaw, seriesRaw);
      end
      else
      begin
        { one scope per series type, new every update }
        t := -1;
        for k := 0 to High(scopes) do
          if scopes[k].Key = typ then t := k;
        if t < 0 then
        begin
          SetLength(scopes, Length(scopes) + 1);
          t := High(scopes);
          scopes[t].Key := typ;
          scopes[t].Scope := Default(TTyDecalScope);
        end;
        dataScope := scopes[t].Scope;
        if rows = nil then
        begin
          SetLength(rows, rawN);
          SetLength(rowSet, rawN);
        end;
        for k := 0 to rawN - 1 do
        begin
          nm := st.GetNameByRaw(k);
          if nm = '' then nm := IntToStr(k);
          pick := TyDecalFromPalette(dataScope, palN, nm);
          { a row out of the view asks and keeps nothing }
          if st.IndexOfRawIndex(k) < 0 then Continue;
          palRaw := TyDecalRawOf(TyDecalPaletteItem(pal, pick));
          if rowSet[k] then rows[k] := TyDecalMerge(palRaw, rows[k])
          else rows[k] := TyDecalMerge(palRaw, seriesRaw);
          rowSet[k] := rows[k].Present;
        end;
        scopes[t].Scope := dataScope;
      end;
    end;
    { decalVisual: nothing for a series the legend filtered }
    if FBindings[slot].Hidden then Continue;
    FSeriesDecals[slot] := TyDecalResolve(seriesRaw, skin, ground);
    FSeriesDecalRaws[slot] := seriesRaw;
    { no row of its own: the series' decal for every row, as an all-false
      set reads [R2-L] }
    if rowSet = nil then Continue;
    SetLength(FRowDecals[slot], rawN);
    SetLength(FRowDecalSet[slot], rawN);
    SetLength(FRowDecalRaws[slot], rawN);
    for k := 0 to rawN - 1 do
      if rowSet[k] then
      begin
        FRowDecalSet[slot][k] := True;
        FRowDecals[slot][k] := TyDecalResolve(rows[k], skin, ground);
        FRowDecalRaws[slot][k] := rows[k];
      end;
  end;
end;

function TTyCustomAdvanceChart.GetAriaDescription: string;
var
  aria, d: TJSONData;
  facts: TTyAriaFacts;
  loc: TTyAriaLocale;
begin
  Result := '';
  if (FOption = nil) or not (FOption.Root is TJSONObject) or not AriaEnabled then Exit;
  ConvertReady;
  aria := TJSONObject(FOption.Root).Find('aria');
  if not (aria is TJSONObject) then Exit;
  { label.enabled: the default option's true under the author's }
  d := TyAriaLabelKey(TJSONObject(aria), ['enabled']);
  if (d <> nil) and not TyDecalTruthy(d) then Exit;
  { the author's description is the whole label }
  d := TyAriaLabelKey(TJSONObject(aria), ['description']);
  if TyDecalTruthy(d) then Exit(TyJsonJsString(d));
  AriaGather(TJSONObject(aria), facts);
  if facts.SeriesCount < 1 then Exit;
  loc := TyAriaLocaleOf(TJSONObject(aria), TyAriaDefaultLocale);
  Result := TyAriaLabel(loc, facts);
end;

procedure TTyCustomAdvanceChart.AriaGather(AAria: TJSONObject; out AFacts: TTyAriaFacts);
var
  d, rd, ex: TJSONData;
  facts: TTyAriaFacts;
  si, slot, n, i, k, dim, pos: Integer;
  node: TJSONObject;
  st: TTyDataStore;
  vals: TTyStringArray;
  excl, read: Boolean;
  cell: TTyDataValue;

  { the value list's next entry, unless excludeDimensionId names it }
  procedure Push(const AText: string);
  var j: Integer;
  begin
    excl := False;
    if ex is TJSONArray then
      for j := 0 to ex.Count - 1 do
      begin
        rd := TJSONArray(ex).Items[j];
        if (rd.JSONType = jtNumber) and (rd.AsFloat = k) then excl := True;
      end;
    Inc(k);
    if excl then Exit;
    SetLength(vals, Length(vals) + 1);
    vals[High(vals)] := AText;
  end;

begin
  facts := Default(TTyAriaFacts);
  facts.MaxData := 10;
  facts.MaxDataText := '10';
  facts.MaxSeries := 10;
  AFacts := facts;
  if FOption = nil then Exit;
  for si := 0 to FOption.ComponentCount('series') - 1 do
    if FOption.ComponentAt('series', si) is TJSONObject then Inc(facts.SeriesCount);
  { getTitle: the first title's text, when truthy }
  d := FOption.ComponentAt('title', 0);
  if d is TJSONObject then
  begin
    d := TJSONObject(d).Find('text');
    if TyDecalTruthy(d) then
    begin
      facts.HasTitle := True;
      facts.Title := TyJsonJsString(d);
    end;
  end;
  { maxCount || 10 }
  d := TyAriaLabelKey(AAria, ['data', 'maxCount']);
  if TyDecalTruthy(d) then
  begin
    facts.MaxData := TyJsonToNumber(d);
    facts.MaxDataText := TyJsonJsString(d);
  end;
  d := TyAriaLabelKey(AAria, ['series', 'maxCount']);
  if TyDecalTruthy(d) then facts.MaxSeries := TyJsonToNumber(d);
  ex := TyAriaLabelKey(AAria, ['data', 'excludeDimensionId']);
  for si := 0 to FOption.ComponentCount('series') - 1 do
  begin
    if not (FOption.ComponentAt('series', si) is TJSONObject) then Continue;
    node := TJSONObject(FOption.ComponentAt('series', si));
    slot := SlotOfSeries(si);
    { eachSeries: the legend's filtered series are not met }
    if (slot >= 0) and (slot <= High(FBindings)) and FBindings[slot].Hidden then Continue;
    n := Length(facts.Series);
    SetLength(facts.Series, n + 1);
    facts.Series[n].Index := si;
    d := node.Find('type');
    if (d <> nil) and (d.JSONType = jtString) then
      facts.Series[n].TypeName := TyAriaTypeName(d.AsString)
    else
      facts.Series[n].TypeName := TyAriaTypeName('');
    { seriesModel.get('name') }
    d := node.Find('name');
    facts.Series[n].HasName := TyDecalTruthy(d);
    if facts.Series[n].HasName then facts.Series[n].Name := TyJsonJsString(d);
    st := nil;
    if (slot >= 0) and (slot <= High(FStores)) then st := FStores[slot];
    if st = nil then Continue;
    SetLength(facts.Series[n].Rows, st.Count);
    for i := 0 to st.Count - 1 do
    begin
      facts.Series[n].Rows[i].Name := st.GetItemName(i);
      { data.getValues(i): every dimension upstream's data has -- the
        store's own columns, then the item's positions no column reads (a
        scatter's third `value`, NaN where the item is short), then the
        stack's two calculated ones -- less the excluded ones }
      vals := nil;
      k := 0;
      for dim := 0 to st.DimCount - 1 do
        if Copy(st.DimName(dim), 1, 5) <> '__ty_' then
          Push(TyJsNumberToString(st.Get(dim, i)));
      for pos := 0 to st.RawWidth - 1 do
      begin
        read := False;
        for dim := 0 to st.DimCount - 1 do
          if (Copy(st.DimName(dim), 1, 5) <> '__ty_') and (st.RawDimPos(dim) = pos) then
            read := True;
        if read then Continue;
        { a position no column reads is a float dimension upstream; one it
          guessed ordinal is not modelled here (NaN) }
        if TTyDataStore.RawCell(st.RawItemByRaw(st.GetRawIndex(i)), pos, cell)
          and (st.RawPosType(pos) <> ddtOrdinal) then
          Push(TyJsNumberToString(TyParseDataValue(cell, ddtFloat)))
        else
          Push('NaN');
      end;
      for dim := 0 to st.DimCount - 1 do
        if (Copy(st.DimName(dim), 1, 16) = '__ty_stackresult')
          or (Copy(st.DimName(dim), 1, 16) = '__ty_stackedover') then
          Push(TyJsNumberToString(st.Get(dim, i)));
      facts.Series[n].Rows[i].Values := vals;
    end;
  end;
  AFacts := facts;
end;

function TTyCustomAdvanceChart.PaletteSeriesColour(ASeriesIndex: Integer): TTyChartColor;
begin
  Result := TTyChartColor(SeriesColor(ASeriesIndex));
end;

function TTyCustomAdvanceChart.PaletteDatumColour(ASeriesIndex,
  ARawIndex: Integer): TTyChartColor;
var
  slot, view: Integer;
  per: TTyChartColorArray;
  v: TTySeriesVisual;
  typ: string;
begin
  Result := 0;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
  typ := FBindings[slot].SeriesType;
  if (typ = TyPieSeriesTypeName) or (typ = 'funnel') or (typ = 'gauge')
    or (typ = 'radar') then
  begin
    per := PerDatumColours(slot);
    if (ARawIndex >= 0) and (ARawIndex <= High(per)) then Result := per[ARawIndex];
    Exit;
  end;
  v := TySeriesVisual(TTyChartColor(SeriesColor(ASeriesIndex)));
  ApplyOptStyle(v, ASeriesIndex);
  ApplyVisualMaps(v, slot, 0);
  view := FStores[slot].IndexOfRawIndex(ARawIndex);
  if view >= 0 then Result := TyRowFill(v, FStores[slot], view)
  else Result := v.Fill;
end;

function TTyCustomAdvanceChart.MarkAreaPictures(ASeriesIndex: Integer): TTyMkAreaPicArray;
var slot: Integer;
begin
  Result := nil;
  slot := SlotOfSeries(ASeriesIndex);
  if (slot < 0) or (slot > High(FMarkAreaPics)) then Exit;
  Result := FMarkAreaPics[slot];
end;

function TTyCustomAdvanceChart.BuildMarkers(const AMeasurer: ITyTextMeasurer;
  AList: TTyPaintList): Integer;
var
  i, n: Integer;
  ink: TTyMkInk;
  st: TTyStyleSet;
  dark: Boolean;
begin
  Result := 0;
  st := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  ink.FontName := st.FontName;
  ink.FontSizeLogical := ResolveFontSize(st);
  ink.FontWeight := st.FontWeight;
  ink.Text := TTyChartColor(st.TextColor);
  LabelGround(ink.Halo, dark);
  ink.Inside[0] := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight', '', []).TextColor);
  ink.Inside[1] := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []).TextColor);
  ink.Inside[2] := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '', []).TextColor);
  ink.RtGlobal := RtGlobal;
  { ONE VIEW PER MARKER TYPE, as upstream's -- excludeComponents hides all of
    a type at once [Batch 106] }
  n := 0;
  if not ViewHidden(cvMarkArea) then
    for i := 0 to High(FMarkAreaPics) do
      if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkArea].Present then
        Inc(n, TyBuildMarkAreas(FMarkAreaPics[i], FMarkers[i].Blocks[mkArea], ink,
          AMeasurer, AList, FMarkers[i].SeriesIndex));
  if n > 0 then ViewDrew(cvMarkArea);
  Inc(Result, n);
  n := 0;
  if not ViewHidden(cvMarkPoint) then
    for i := 0 to High(FMarkPointPics) do
      if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkPoint].Present then
        Inc(n, TyBuildMarkPoints(FMarkPointPics[i], FMarkers[i].Blocks[mkPoint], ink,
          AMeasurer, AList, FMarkers[i].SeriesIndex));
  if n > 0 then ViewDrew(cvMarkPoint);
  Inc(Result, n);
  n := 0;
  if not ViewHidden(cvMarkLine) then
    for i := 0 to High(FMarkLinePics) do
      if (i <= High(FMarkers)) and FMarkers[i].Blocks[mkLine].Present then
        Inc(n, TyBuildMarkLines(FMarkLinePics[i], FMarkers[i].Blocks[mkLine], ink,
          AMeasurer, AList, FMarkers[i].SeriesIndex));
  if n > 0 then ViewDrew(cvMarkLine);
  Inc(Result, n);
end;

function TTyCustomAdvanceChart.SeriesStore(ASeriesIndex: Integer): TTyDataStore;
var k: Integer;
begin
  Result := nil;
  for k := 0 to High(FBindings) do
    if (FBindings[k].SeriesIndex = ASeriesIndex) and (k <= High(FStores)) then
      Exit(FStores[k]);
end;

procedure TTyCustomAdvanceChart.ApplyOptStyle(var AVisual: TTySeriesVisual;
  ASlot: Integer);
var
  node: TJSONObject;
  d: TJSONData;
  st: string;
  item, line: TTyOptStyle;
begin
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASlot);
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('type');
  st := '';
  if (d <> nil) and (d.JSONType = jtString) then st := d.AsString;

  { THE FILL IS ALREADY DECIDED. SolveSeriesColors read the same key to
    settle whether this series took a palette slot, and SeriesColor handed
    the answer over -- reading it a second time here would be a second
    place that has to agree about `auto`. }
  item := TyReadOptStyle(node, 'itemStyle');
  line := TyReadOptStyle(node, 'lineStyle');

  { `itemStyle.borderColor` / `borderWidth`. `auto` on a border means the
    palette colour, the same as it does on a fill. }
  if item.BorderColor.Written and not item.BorderColor.IsNone then
  begin
    if item.BorderColor.IsAuto then
      AVisual.Stroke := TTyChartColor(SeriesPaletteColor(ASlot))
    else
      AVisual.Stroke := item.BorderColor.Color;
  end;
  if not IsNan(item.BorderWidthLogical) then
    AVisual.StrokeWidthLogical := item.BorderWidthLogical;
  { THE PEN'S DASH, carried as the option wrote it -- see TTySeriesVisual. }
  AVisual.Dash := item.Dash;
  AVisual.DashExplicit := item.DashLogical;
  { [R2-I2] and its phase (borderDashOffset) }
  AVisual.DashOffset := item.DashOffset;
  { [R2-I3] kept apart for a line's symbols, which the lineStyle's below
    does not reach }
  AVisual.ItemDash := item.Dash;
  AVisual.ItemDashExplicit := item.DashLogical;
  AVisual.ItemDashOffset := item.DashOffset;
  if not IsNan(item.Opacity) then
    AVisual.Alpha := Min(Double(1), Max(Double(0), item.Opacity))
  else if st = 'scatter' then
    { A SCATTER'S SYMBOLS ARE FOUR FIFTHS OPAQUE unless told otherwise --
      ScatterSeries' own default, which its labels inherit. [Revised in
      batch 47: they were opaque.] }
    AVisual.Alpha := 0.8;
  { THE RAMP, when the colour was an object rather than a string. The solid
    stays where it was -- SeriesColor already holds the first stop -- so a
    legend swatch and a tooltip marker go on working unchanged. }
  AVisual.FillGradient := item.Color.Gradient;
  AVisual.StrokeGradient := item.BorderColor.Gradient;
  AVisual.FillPattern := item.Color.Pattern;

  { A LINE READS ITS OWN BLOCK FOR THE PEN, and only for the pen. Its
    palette colour came from `itemStyle` -- that is the trap in this whole
    row -- and that colour still goes to its symbols and its area; the
    authored `lineStyle.color` wins the polyline's pixels and nothing else. }
  if (st = 'line') or TyStyleDrawsWithStroke(st) then
  begin
    if line.Color.Written and not line.Color.IsNone then
    begin
      if line.Color.IsAuto then
        AVisual.Stroke := TTyChartColor(SeriesPaletteColor(ASlot))
      else
        AVisual.Stroke := line.Color.Color;
    end;
    if not IsNan(line.BorderWidthLogical) then
      AVisual.StrokeWidthLogical := line.BorderWidthLogical;
    { AND IT REPLACES the itemStyle one rather than adding to it: for a shape
      drawn with a stroke, lineStyle IS the pen. `lineStyle: {}` with no type
      leaves todNone, which answers solid -- so a line series that writes only
      a width does not inherit a dash from its itemStyle. }
    AVisual.Dash := line.Dash;
    AVisual.DashExplicit := line.DashLogical;
    AVisual.DashOffset := line.DashOffset;
    if not IsNan(line.Opacity) then
      AVisual.Alpha := Min(Double(1), Max(Double(0), line.Opacity));
    if line.Color.Gradient.Kind <> cgkNone then
      AVisual.StrokeGradient := line.Color.Gradient;
  end;
end;

function TTyCustomAdvanceChart.ThemeRampColor(ASlot: Integer): TTyColor;
var
  st: TTyStyleSet;
begin
  { NINE SLOTS, CYCLED -- nine because upstream's own default palette is nine
    colours and the CYCLE LENGTH is observable: it decides which series comes
    round to share a colour with the first. Derived from --accent rather than
    written out, which is what makes a re-skinned chart come out in the skin's
    own colours; slot 1 IS the accent, so a single-series chart is drawn in
    the theme's own colour. }
  st := ActiveController.Model.ResolveStyle(
    'TyAdvChartSeries' + IntToStr((Abs(ASlot) mod 9) + 1), '', []);
  if tpBackground in st.Present then
    Exit(st.Background.Color);
  { The nine keys are in the BASE layer, so a theme cannot remove them -- it
    can only restyle them, and a skin that defines none of them inherits all
    nine. Reaching here means something is wrong with the theme rather than
    with the option, so the answer is the control's own foreground: visible
    against its own surface by construction, which is the one thing a fallback
    colour has to be. }
  st := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
    [tysNormal]);
  Result := st.TextColor;
end;

function TTyCustomAdvanceChart.PickColor(const APick: TTyPalettePick): TTyColor;
begin
  case APick.Kind of
    ppkColor: Result := TTyColor(APick.Color);
    ppkTheme: Result := ThemeRampColor(APick.Slot);
  else
    { undefined: no fill at all }
    Result := 0;
  end;
end;

function TTyCustomAdvanceChart.SeriesPaletteColor(ASeriesIndex: Integer): TTyColor;
begin
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesPickAsked))
    and FSeriesPickAsked[ASeriesIndex] then
    Exit(PickColor(FSeriesPick[ASeriesIndex]));
  Result := ThemeRampColor(ASeriesIndex);
end;

function TTyCustomAdvanceChart.SeriesColor(ASeriesIndex: Integer): TTyColor;
begin
  { THE AUTHOR'S PALETTE FIRST. `color: [...]` or an authored
    `itemStyle.color` is the author speaking about their own chart, and a
    skin has no business overruling it. }
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesColorKnown))
    and FSeriesColorKnown[ASeriesIndex] then
    Exit(TTyColor(FSeriesColors[ASeriesIndex]));
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesColorNone))
    and FSeriesColorNone[ASeriesIndex] then
    Exit(0);
  { the palette's answer, the theme's slot through the shared cursor
    included [Batch 105] }
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesFromPick))
    and FSeriesFromPick[ASeriesIndex] then
    Exit(PickColor(FSeriesPick[ASeriesIndex]));

  Result := ThemeRampColor(ASeriesIndex);
end;

function TTyCustomAdvanceChart.TitleFont(const AKey: string): TTyTitleFont;
var st: TTyStyleSet;
begin
  st := ActiveController.Model.ResolveStyle(AKey, '', []);
  Result.Name := st.FontName;
  Result.SizeLogical := ResolveFontSize(st);
  Result.Weight := st.FontWeight;
  Result.HasColour := False;
  Result.Colour := 0;
end;

{ A TITLE LINE'S FONT: the theme's, the root textStyle over it, the title's
  own textStyle or subtextStyle over that -- upstream's getFont order, and
  the colour free-standing text takes [Batch 83] }
function TTyCustomAdvanceChart.TitleFontOf(AIndex: Integer; const AKey,
  AStyleKey: string; APick: TTyTextPick): TTyTitleFont;
var
  node, st, d: TJSONData;
  col: TTyChartColor;
begin
  Result := TitleFont(AKey);
  GlobalTextOver(Result.Name, Result.SizeLogical, Result.Weight,
    Result.HasColour, Result.Colour, APick);
  node := FOption.ComponentAt('title', AIndex);
  if not (node is TJSONObject) then Exit;
  st := TJSONObject(node).Find(AStyleKey);
  if not (st is TJSONObject) then Exit;
  d := TJSONObject(st).Find('fontFamily');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
    Result.Name := d.AsString;
  Result.SizeLogical := TyOptFontSize(TJSONObject(st).Find('fontSize'),
    Result.SizeLogical);
  Result.Weight := TyFontWeightOf(TJSONObject(st).Find('fontWeight'), Result.Weight);
  d := TJSONObject(st).Find('color');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
  begin
    Result.HasColour := True;
    Result.Colour := col;
  end;
end;

procedure TTyCustomAdvanceChart.SolveTitles(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i, n, line: Integer;
  rts: array[0..1] of TTyRtBlockStyle;
  meters: array[0..1] of ITyTextMeasurer;
  node, st: TJSONData;
  glob: TTyRtGlobal;
  b: TTyRtBlockStyle;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  ref: TTyXYWH;
begin
  n := TyTitleCount(FOption);
  SetLength(FTitles, n);
  SetLength(FTitleSpecs, n);
  SetLength(FTitleFonts, n);
  SetLength(FTitleRt, n);
  glob := RtGlobal;
  for i := 0 to n - 1 do
  begin
    FTitleSpecs[i] := TyTitleSpecOf(FOption, i);
    { the title's 18px bold and both lines' colours are its own defaults;
      the subtitle's 12px is too, its weight is not }
    FTitleFonts[i][0] := TitleFontOf(i, 'TyAdvChartTitle', 'textStyle', [ttpFamily]);
    FTitleFonts[i][1] := TitleFontOf(i, 'TyAdvChartSubtitle', 'subtextStyle',
      [ttpWeight, ttpFamily]);
    { THE TWO LINES' TEXT BLOCKS: textStyle's and subtextStyle's `rich`, size
      and overflow -- never a box, which upstream disables for the title
      (install.ts:166-182) -- measured as the blocks they are and laid out
      about the anchors the layout gives them [Batch 86] }
    for line := 0 to 1 do
    begin
      rts[line] := Default(TTyRtBlockStyle);
      node := FOption.ComponentAt('title', i);
      if node is TJSONObject then
      begin
        if line = 0 then st := TJSONObject(node).Find('textStyle')
        else st := TJSONObject(node).Find('subtextStyle');
        if (st is TJSONObject) and TyRtNodeWantsBlock(TJSONObject(st)) then
          rts[line] := TyRtResolve([TJSONObject(st)], glob,
            TyRtResolveOpt(False, True));
      end;
      meters[line] := nil;
      if rts[line].Needed then
        meters[line] := TyRtBlockMeasurer(AMeasurer, rts[line], glob, APPI / 96);
    end;
    { IN A MATRIX CELL OR A CALENDAR DAY when it names one [Batch 151] }
    if ComponentBoxRef('title', i, ref) then
      FTitles[i] := TyLayoutTitle(FTitleSpecs[i], ref, AMeasurer,
        FTitleFonts[i][0], FTitleFonts[i][1], APPI, meters[0], meters[1])
    else
      FTitles[i] := TyLayoutTitle(FTitleSpecs[i], FLastRect, AMeasurer,
        FTitleFonts[i][0], FTitleFonts[i][1], APPI, meters[0], meters[1]);
    for line := 0 to 1 do
    begin
      FTitleRt[i][line] := Default(TTyRtDrawn);
      if not rts[line].Needed or not FTitles[i].Valid then Continue;
      if (line = 1) and not FTitles[i].HasSub then Continue;
      if (line = 0) and (FTitleSpecs[i].Text = '') then Continue;
      b := rts[line];
      TyRtFinish(b, FTitleFonts[i][line].Name, FTitleFonts[i][line].SizeLogical,
        FTitleFonts[i][line].Weight, glob, False, 0);
      { the line's own ink over the block, the skin's at paint time where
        none was written -- as the title's fixed fill is }
      b.Style.HasFill := FTitleFonts[i][line].HasColour;
      b.Style.FillNone := False;
      b.Style.Fill := FTitleFonts[i][line].Colour;
      case FTitles[i].Align of
        ttaCentre: ah := tahCentre;
        ttaRight: ah := tahRight;
      else
        ah := tahLeft;
      end;
      case FTitles[i].VAlign of
        ttvMiddle: av := tavMiddle;
        ttvBottom: av := tavBottom;
      else
        av := tavTop;
      end;
      if line = 0 then
        FTitleRt[i][line].Pieces := TyRtLay(FTitleSpecs[i].Text, b,
          TyRtDefaultOf(False, 0, False, 0, False, ah, av), APPI / 96, AMeasurer)
      else
        FTitleRt[i][line].Pieces := TyRtLay(FTitleSpecs[i].Subtext, b,
          TyRtDefaultOf(False, 0, False, 0, False, ah, av), APPI / 96, AMeasurer);
      if line = 0 then
      begin
        FTitleRt[i][line].X := FTitles[i].TextX;
        FTitleRt[i][line].Y := FTitles[i].TextY;
      end
      else
      begin
        FTitleRt[i][line].X := FTitles[i].SubX;
        FTitleRt[i][line].Y := FTitles[i].SubY;
      end;
      FTitleRt[i][line].RotationRad := 0;
      FTitleRt[i][line].Scale := APPI / 96;
    end;
  end;
end;

function TTyCustomAdvanceChart.TitleCount: Integer;
begin
  Result := Length(FTitles);
end;

function TTyCustomAdvanceChart.TitleLayoutOf(AIndex: Integer): TTyTitleLayout;
begin
  Result := Default(TTyTitleLayout);
  if (AIndex >= 0) and (AIndex <= High(FTitles)) then Result := FTitles[AIndex];
end;

function TTyCustomAdvanceChart.TitleFontUsed(AIndex, ALine: Integer): TTyTitleFont;
begin
  Result := Default(TTyTitleFont);
  if (AIndex >= 0) and (AIndex <= High(FTitleFonts)) and (ALine in [0, 1]) then
    Result := FTitleFonts[AIndex][ALine];
end;

function TTyCustomAdvanceChart.TitleRt(AIndex, ALine: Integer): TTyRtDrawn;
begin
  Result := Default(TTyRtDrawn);
  if (AIndex >= 0) and (AIndex <= High(FTitleRt)) and (ALine in [0, 1]) then
    Result := FTitleRt[AIndex][ALine];
end;

procedure TTyCustomAdvanceChart.PaintTitles(APainter: TTyPainter);
var
  i: Integer;
  st, subSt: TTyStyleSet;
  lay: TTyTitleLayout;
  f0, f1: TTyTitleFont;
  ink0, ink1: TTyColor;

  { The box DrawText wants, hung off an anchor with the title's alignment.
    The same job AnchorBox does for an axis label; kept local because the two
    take their alignment from different enums and one shared helper would take
    an argument nobody could read at the call site. }
  function Hang(AX, AY, AW, AH: Double; AAlign: TTyTitleAlign;
    AVAlign: TTyTitleVAlign): TRect;
  begin
    case AAlign of
      ttaCentre: Result.Left := Round(AX - AW / 2);
      ttaRight: Result.Left := Round(AX - AW);
    else
      Result.Left := Round(AX);
    end;
    Result.Right := Result.Left + Round(AW);
    case AVAlign of
      ttvMiddle: Result.Top := Round(AY - AH / 2);
      ttvBottom: Result.Top := Round(AY - AH);
    else
      Result.Top := Round(AY);
    end;
    Result.Bottom := Result.Top + Round(AH);
  end;

  function LclAlign(AAlign: TTyTitleAlign): TAlignment;
  begin
    case AAlign of
      ttaCentre: Result := taCenter;
      ttaRight: Result := taRightJustify;
    else
      Result := taLeftJustify;
    end;
  end;

begin
  if Length(FTitles) = 0 then Exit;
  if ViewHidden(cvTitle) then Exit;
  st := ActiveController.Model.ResolveStyle('TyAdvChartTitle', '', []);
  subSt := ActiveController.Model.ResolveStyle('TyAdvChartSubtitle', '',
    []);
  for i := 0 to High(FTitles) do
  begin
    lay := FTitles[i];
    if not lay.Valid then Continue;
    ViewDrew(cvTitle);
    { The frame first, and only when the option asked for one: ECharts gives
      the title a transparent background by default, and painting the surface
      colour instead would put a visible plate behind every title on an image
      theme. }
    if FTitleSpecs[i].HasBackground then
      APainter.FillBackground(
        Rect(Round(lay.Frame.Left), Round(lay.Frame.Top),
             Round(lay.Frame.Right), Round(lay.Frame.Bottom)),
        st.Background, Round(FTitleSpecs[i].BorderRadii[0]));
    { in the fonts the layout measured -- the author's where written }
    f0 := FTitleFonts[i][0];
    f1 := FTitleFonts[i][1];
    if f0.HasColour then ink0 := TTyColor(f0.Colour) else ink0 := st.TextColor;
    if f1.HasColour then ink1 := TTyColor(f1.Colour) else ink1 := subSt.TextColor;
    { A LINE THAT IS A BLOCK DRAWS ITS PIECES [Batch 86] }
    if (i <= High(FTitleRt)) and (Length(FTitleRt[i][0].Pieces) > 0) then
      TyRenderRtPieces(APainter, FTitleRt[i][0].Pieces, FTitleRt[i][0].X,
        FTitleRt[i][0].Y, 0, FTitleRt[i][0].Scale, 1, True, ink0)
    else if FTitleSpecs[i].Text <> '' then
      APainter.DrawText(
        Hang(lay.TextX, lay.TextY, lay.TextW, lay.TextH, lay.Align, lay.VAlign),
        FTitleSpecs[i].Text, f0.Name, f0.SizeLogical, f0.Weight,
        ink0, LclAlign(lay.Align), tlTop, False, 0, False,
        Pos(#10, FTitleSpecs[i].Text) > 0);
    if (i <= High(FTitleRt)) and (Length(FTitleRt[i][1].Pieces) > 0) then
      TyRenderRtPieces(APainter, FTitleRt[i][1].Pieces, FTitleRt[i][1].X,
        FTitleRt[i][1].Y, 0, FTitleRt[i][1].Scale, 1, True, ink1)
    else if lay.HasSub then
      APainter.DrawText(
        Hang(lay.SubX, lay.SubY, lay.SubW, lay.SubH, lay.Align, lay.VAlign),
        FTitleSpecs[i].Subtext, f1.Name, f1.SizeLogical,
        f1.Weight, ink1, LclAlign(lay.Align), tlTop, False,
        0, False, Pos(#10, FTitleSpecs[i].Subtext) > 0);
  end;
end;


function TTyCustomAdvanceChart.SeriesNameOf(ASlot: Integer): string;
var
  d: TJSONData;
  node: TJSONObject;
  i, ds: Integer;
begin
  Result := '';
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASlot);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('name');
  if (d <> nil) and (d.JSONType = jtString) then Exit(d.AsString);
  { A NUMBER IS A NAME TOO -- convertOptionIdName, `'' + name` -- so a
    series called 2015 is headed and listed as 2015, not as nobody. }
  if (d <> nil) and (d.JSONType = jtNumber) then
    Exit(TyJsNumberToString(d.AsFloat));

  { THE NAME THE MODEL KEPT [Batch 95]: a merge that writes no name keeps
    the model's (makeIdAndName's existing.name), and a type change rebuilds
    the series from an option without one -- isNameSpecified: not the dummy }
  Result := FOption.ComponentModelName('series', ASlot);
  if (Result <> '') and (Pos('series' + #0, Result) <> 1) then Exit;
  Result := '';

  { A SERIES READING A TABLE NAMES ITSELF AFTER THE COLUMN IT TOOK. That is
    how three bars on one dataset end up called 2015, 2016 and 2017 in a
    legend nobody wrote entries for -- and without it those three legends
    have nothing to list. The column is the one the encode put the series'
    own name on, which the default encode sets to whichever column is not
    the shared category. }
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].SeriesIndex <> ASlot then Continue;
    if i > High(FEncodes) then Exit;
    ds := -1;
    if i <= High(FSeriesDataset) then ds := FSeriesDataset[i];
    if (ds < 0) or (i > High(FSources)) then Exit;
    if FEncodes[i].SeriesName < 0 then Exit;
    Exit(TySourceDimName(FSources[i], FEncodes[i].SeriesName));
  end;
end;

{ `encode` ON A SERIES' OWN DATA: `encode: {x: 1, y: 0}` has x read element
  1 of each item and y element 0, exactly as it would pick table columns.
  Only the plain coordinate columns -- a multi-value series places its own,
  and a row-index column reads no element at all. }
procedure TTyCustomAdvanceChart.SeriesDataEncode(ASlot: Integer;
  var ADims: TTySeriesDimArray; out AEnc: TTySeriesEncode);
var
  coord: TTyCoordDimArray;
  k: Integer;
  plain: Boolean;
  node: TJSONObject;
  d: TJSONData;
begin
  plain := True;
  for k := 0 to High(ADims) do
    if (ADims[k].Coord <> '') or (ADims[k].SourceSlot > 0) then plain := False;
  coord := nil;
  SetLength(coord, Length(ADims));
  for k := 0 to High(ADims) do
  begin
    coord[k].Name := ADims[k].Name;
    coord[k].Ordinal := ADims[k].Kind = ddtOrdinal;
  end;
  { A NAME IN `encode` IS ONE OF THE SERIES' OWN `dimensions`. }
  AEnc := TyEncodeOf(FOption, FBindings[ASlot].SeriesIndex,
    TySeriesDimsSource(FOption, FBindings[ASlot].SeriesIndex), coord);
  if (not AEnc.Given) or not plain then Exit;
  { EVERY COORDINATE `encode` DOES NOT NAME takes the next element nobody
    holds, up to the width item 0 declares. }
  node := nil;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if d is TJSONObject then node := TJSONObject(d);
  d := nil;
  if node <> nil then d := node.Find('data');
  if (d <> nil) and (d is TJSONArray) then
    TyEncodeFillUnclaimed(AEnc, TySeriesDetectedDimCount(TJSONArray(d)));
  for k := 0 to High(ADims) do
    if (k <= High(AEnc.Columns)) and (AEnc.Columns[k] >= 0)
      and not ADims[k].FromRowIndex then
      ADims[k].SourceSlot := AEnc.Columns[k] + 1;
end;

function TTyCustomAdvanceChart.SeriesModelName(ASeriesIndex: Integer): string;
var
  d: TJSONData;
  node: TJSONObject;
begin
  Result := '';
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('name');
  { WRITTEN: as written, '' included -- only an unwritten name is replaced. }
  if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then
    Exit(SeriesNameOf(ASeriesIndex));
  Result := SeriesNameOf(ASeriesIndex);
  if Result = '' then Result := TyChartSeriesDefaultName(ASeriesIndex);
end;

procedure TTyCustomAdvanceChart.MultiValueDims(const ABinding: TTySeriesBinding;
  var ADims: TTySeriesDimArray);
var
  info: TTySeriesTypeInfo;
  i, n: Integer;
  prepend: Boolean;
  node: TJSONObject;
  d: TJSONData;
begin
  if (ABinding.BaseAxis = nil) or (ABinding.ValueAxis = nil) then Exit;
  if not TySeriesFindType(ABinding.SeriesType, info) then Exit;
  { `base` PLUS MORE THAN ONE VALUE is what makes a type multi-value, and the
    registry has said so since it was written -- a candlestick declares
    base/open/close/lowest/highest and a boxplot base/min/Q1/median/Q3/max.
    Anything declaring two or fewer is an ordinary pair and keeps the columns
    the coordinate system gave it. }
  n := Length(info.Dims);
  if (n < 3) or (info.Dims[0] <> 'base') then Exit;

  SetLength(ADims, n);
  { THE CATEGORY IS THE ROW NUMBER. Upstream's default encode for these types
    puts every element of the item on the value axis, which leaves the base
    axis nothing to read -- so it counts rows instead. The column keeps the
    base axis' own name and kind so category interning still works.

    [Batch 108: ONLY ON A CATEGORY BASE, and only when the series' encode
    says nothing about the base dimension -- whiskerBoxCommon's
    `addOrdinal = !this._hasEncodeRule(dim)`. On a value or a time base
    nothing is put in front: the base is the item's FIRST element and the
    values the ones after it. It read the row number there too, so a
    candlestick on a value axis stood its candles on 0, 1, 2 and took its
    open from the base.] }
  prepend := ABinding.BaseAxis.AxisType = atCategory;
  if prepend and (FOption <> nil) then
  begin
    node := nil;
    d := FOption.ComponentAt('series', ABinding.SeriesIndex);
    if d is TJSONObject then node := TJSONObject(d);
    if node <> nil then d := node.Find('encode') else d := nil;
    if (d is TJSONObject) then
    begin
      d := TJSONObject(d).Find(ABinding.BaseAxis.Dim);
      if (d <> nil) and (d.JSONType <> jtNull) then prepend := False;
    end;
  end;
  ADims[0].Name := ABinding.BaseAxis.Dim;
  if ABinding.BaseAxis.AxisType = atCategory then
  begin
    ADims[0].Kind := ddtOrdinal;
    ADims[0].Axis := ABinding.BaseAxis;
  end
  else if ABinding.BaseAxis.AxisType = atTime then
  begin
    ADims[0].Kind := ddtTime;
    ADims[0].Axis := nil;
  end
  else
  begin
    ADims[0].Kind := ddtFloat;
    ADims[0].Axis := nil;
  end;
  ADims[0].FromRowIndex := prepend;
  ADims[0].Coord := '';
  if prepend then ADims[0].SourceSlot := 0 else ADims[0].SourceSlot := 1;

  for i := 1 to n - 1 do
  begin
    ADims[i].Name := info.Dims[i];
    ADims[i].Kind := ddtFloat;
    ADims[i].Axis := nil;
    { ELEMENT i-1 OF THE ITEM: the base took no element at all, so the values
      start at the beginning of the row rather than one in from it -- or
      element i, past the base, when the base is in the row [Batch 108] }
    if prepend then ADims[i].SourceSlot := i else ADims[i].SourceSlot := i + 1;
    { AND EVERY ONE OF THEM FEEDS THE VALUE AXIS. This is the whole reason
      the store learned that a coordinate is a LIST of columns. }
    ADims[i].Coord := ABinding.ValueAxis.Dim;
  end;
end;

function TTyCustomAdvanceChart.AxisDimOf(AAxis: TTyAxis): string;
begin
  if AAxis = nil then Result := '' else Result := AAxis.Dim;
end;

{ an itemStyle's borderRadius: a number, or zrender's array forms; nil for
  none }
function RadiiOfStyle(AStyle: TJSONData; APPI: Integer; out ARadii: TTyCornerRadii): Boolean;
var
  d: TJSONData;
  vals: array of Double;
  k: Integer;
begin
  ARadii := Default(TTyCornerRadii);
  Result := False;
  if (AStyle = nil) or (AStyle.JSONType <> jtObject) then Exit;
  d := TJSONObject(AStyle).Find('borderRadius');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  vals := nil;
  if d.JSONType = jtNumber then
  begin
    SetLength(vals, 1);
    vals[0] := d.AsFloat;
  end
  else if d.JSONType = jtArray then
  begin
    SetLength(vals, d.Count);
    for k := 0 to d.Count - 1 do
      if d.Items[k].JSONType = jtNumber then vals[k] := d.Items[k].AsFloat
      else vals[k] := 0;
  end
  else Exit;
  Result := True;
  if Length(vals) = 0 then Exit;
  TyZrRadii(vals, ARadii[0], ARadii[1], ARadii[2], ARadii[3]);
  for k := 0 to 3 do ARadii[k] := ARadii[k] * APPI / 96;
end;

{ each data item's own itemStyle.borderRadius, by raw row }
procedure TTyCustomAdvanceChart.HeatmapItemRadii(ASeriesIndex, APPI: Integer;
  out ARadii: TTyCornerRadiiArray; out AHas: TTyBoolArray);
var
  node, d, it: TJSONData;
  k: Integer;
begin
  ARadii := nil;
  AHas := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  SetLength(ARadii, d.Count);
  SetLength(AHas, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    it := d.Items[k];
    if (it <> nil) and (it.JSONType = jtObject) then
      AHas[k] := RadiiOfStyle(TJSONObject(it).Find('itemStyle'), APPI, ARadii[k]);
  end;
end;

{ Each object data item's own symbol options over the series' spec. }
procedure TTyCustomAdvanceChart.SymbolItems(ASeriesIndex: Integer;
  const ABase: TTySymbolSpec; out ASpecs: TTySymbolSpecArray; out AHas: TTyBoolArray);
var
  node, d, it: TJSONData;
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
    AHas[k] := True;
    ASpecs[k] := TySymbolSpecOf(TJSONObject(it), ABase);
  end;
end;

{ [R2-J3] THE SERIES' PER-ITEM VISUAL CALLBACKS, every series'. Upstream:

    seriesStyleTask (visual/style.ts, every series): the colour key of the
    series' style path -- itemStyle's fill; the stroke of a series that
    draws with it, lineStyle.color for lines and parallel, a boxplot's
    itemStyle.borderColor -- when a function, is called as
    colorCallback(params) for each item; params.color is the palette's
    colour then (the series' colour key takes it).

    seriesSymbolTask (visual/symbol.ts, a series with hasSymbolVisual: line,
    scatter, effectScatter, graph, radar, tree, pictorialBar): every one of
    symbol, symbolSize, symbolRotate, symbolOffset that is a function is
    called as cb(rawValue, params) for each item -- after the style task, so
    params.color is the colour callback's answer for the item, else the
    series style's colour.

  params: the item's getDataParams (TyLabelParams: the series' name and
  index, the row and its raw index, the name, the raw item -- rawValue).
  A handler nobody registered answers undefined: the series' value stands. }
function TTyCustomAdvanceChart.ItemCallbacks(ASlot: Integer; AOnlyRow: Integer;
  ASymColour: TTyChartColor): TTyItemCallbacks;
const
  cSym: array[0..3] of string = ('symbol', 'symbolSize', 'symbolRotate',
    'symbolOffset');
var
  node, tmp: TJSONObject;
  d, ans: TJSONData;
  st: TTyDataStore;
  r, r0, r1, raw, k, n: Integer;
  specs: array[0..3] of string;
  anySym: Boolean;
  colorSpec, sname, t, styleKey, colorKey: string;
  prm: TTyChartCallbackParams;
  c, palette: TTyChartColor;

  function Ref(AData: TJSONData): string;
  begin
    Result := '';
    if (AData <> nil) and (AData.JSONType = jtString)
      and TyChartIsHandlerRef(AData.AsString) then Result := AData.AsString;
  end;

  { getRawValue of an item with no value (a lines row of coords alone): undefined }
  procedure NoValue(var AParams: TTyChartCallbackParams);
  begin
    if (AParams.ValueText = '') and (AParams.Raw.Shape = rshNone)
      and (Length(AParams.Values) = 0) then AParams.ValueText := 'undefined';
  end;

begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FBindings)) or (ASlot > High(FStores)) then Exit;
  st := FStores[ASlot];
  if (st = nil) or (FOption = nil) then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  t := FBindings[ASlot].SeriesType;
  anySym := False;
  for k := 0 to High(cSym) do
  begin
    specs[k] := '';
    if (t = 'line') or (t = 'scatter') or (t = 'effectScatter') or (t = 'graph')
      or (t = 'radar') or (t = 'tree') or (t = 'pictorialBar') then
      specs[k] := Ref(node.Find(cSym[k]));
    if specs[k] <> '' then anySym := True;
  end;
  { visualStyleAccessPath and the colour key of the draw type }
  styleKey := 'itemStyle';
  colorKey := 'color';
  if (t = 'lines') or (t = 'parallel') then styleKey := 'lineStyle'
  else if t = 'boxplot' then colorKey := 'borderColor';
  colorSpec := '';
  d := node.Find(styleKey);
  if d is TJSONObject then colorSpec := Ref(TJSONObject(d).Find(colorKey));
  if not anySym and (colorSpec = '') then Exit;
  Result := TTyItemCallbacks.Create;
  Result.HasSym := anySym;
  Result.HasCol := colorSpec <> '';
  n := st.RawCount;
  if n < st.Count then n := st.Count;
  SetLength(Result.Sym, n);
  SetLength(Result.Col, n);
  SetLength(Result.ColSet, n);
  sname := SeriesModelName(FBindings[ASlot].SeriesIndex);
  palette := TTyChartColor(SeriesColor(FBindings[ASlot].SeriesIndex));
  if AOnlyRow >= 0 then
  begin
    r0 := AOnlyRow;
    r1 := Min(AOnlyRow, st.Count - 1);
  end
  else
  begin
    r0 := 0;
    r1 := st.Count - 1;
  end;
  for r := r0 to r1 do
  begin
    raw := st.GetRawIndex(r);
    if (raw < 0) or (raw >= n) then Continue;
    { the style task first: its colour is the symbol callbacks' params.color }
    if colorSpec <> '' then
    begin
      prm := TyLabelParams(st, r, sname, -1, 0, False,
        FBindings[ASlot].SeriesIndex, t, palette, '');
      NoValue(prm);
      ans := TyChartRunVisualHandler(colorSpec, prm);
      try
        if (ans <> nil) and (ans.JSONType = jtString)
          and TyTryParseChartColor(ans.AsString, c) then
        begin
          Result.Col[raw] := c;
          Result.ColSet[raw] := True;
        end;
      finally
        ans.Free;
      end;
    end;
    if anySym then
    begin
      if Result.ColSet[raw] then c := Result.Col[raw] else c := ASymColour;
      prm := TyLabelParams(st, r, sname, -1, 0, False,
        FBindings[ASlot].SeriesIndex, t, c, '');
      NoValue(prm);
      tmp := TJSONObject.Create;
      for k := 0 to High(cSym) do
      begin
        if specs[k] = '' then Continue;
        ans := TyChartRunVisualHandler(specs[k], prm);
        if ans <> nil then tmp.Add(cSym[k], ans);
      end;
      Result.Sym[raw] := tmp;
    end;
  end;
end;

procedure TTyCustomAdvanceChart.FreeItemCbs;
var i: Integer;
begin
  for i := 0 to High(FItemCbs) do FreeAndNil(FItemCbs[i]);
  FItemCbs := nil;
end;

function TTyCustomAdvanceChart.ItemCbOf(ASlot: Integer): TTyItemCallbacks;
begin
  Result := nil;
  if (ASlot >= 0) and (ASlot <= High(FItemCbs)) then Result := FItemCbs[ASlot];
end;

{ the series style's colour a symbol callback is handed where no colour
  callback answered: the palette's, or the option's itemStyle.color }
procedure TTyCustomAdvanceChart.SolveItemCallbacks;
var
  i: Integer;
  v: TTySeriesVisual;
begin
  FreeItemCbs;
  SetLength(FItemCbs, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FItemCbs[i] := nil;
    if (i > High(FStores)) or (FStores[i] = nil) then Continue;
    v := TySeriesVisual(TTyChartColor(SeriesColor(FBindings[i].SeriesIndex)));
    ApplyOptStyle(v, FBindings[i].SeriesIndex);
    FItemCbs[i] := ItemCallbacks(i, -1, v.Fill);
  end;
end;

{ [R2-J2] the callbacks' answers on the series visual of the generic
  builders: the symbol spec of a scatter's, an effectScatter's and a line's
  items (SymItems, the item's own keys over the answers) [R2-J3: a line's
  too], and the colour callback's fill (CbFill: RowVisualEarly) }
procedure TTyCustomAdvanceChart.VisualCallbacks(ASlot: Integer;
  var AVisual: TTySeriesVisual; AOnlyRow: Integer);
var
  cb: TTyItemCallbacks;
  node, item: TJSONObject;
  d, data: TJSONData;
  raw: Integer;
  t: string;
  spec: TTySymbolSpec;
  c: TTyChartColor;
begin
  { [R2-J3] the rebuild's answers: a render does not call them again }
  if AOnlyRow < 0 then ;
  cb := ItemCbOf(ASlot);
  if cb = nil then Exit;
  begin
    t := FBindings[ASlot].SeriesType;
    d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
    node := nil;
    if d is TJSONObject then node := TJSONObject(d);
    data := nil;
    if node <> nil then data := node.Find('data');
    for raw := 0 to High(cb.Sym) do
    begin
      if cb.HasSym and ((t = 'scatter') or (t = 'effectScatter') or (t = 'line'))
        and (cb.Sym[raw] <> nil) then
      begin
        if raw > High(AVisual.SymItems) then
        begin
          SetLength(AVisual.SymItems, raw + 1);
          SetLength(AVisual.SymItemHas, raw + 1);
        end;
        spec := TySymbolSpecOf(cb.Sym[raw], AVisual.Symbol);
        { the item's own keys over the callbacks' }
        item := nil;
        if (data is TJSONArray) and (raw < TJSONArray(data).Count)
          and (TJSONArray(data).Items[raw] is TJSONObject) then
          item := TJSONObject(TJSONArray(data).Items[raw]);
        if item <> nil then spec := TySymbolSpecOf(item, spec);
        AVisual.SymItems[raw] := spec;
        AVisual.SymItemHas[raw] := True;
      end;
      { a series that draws with its stroke reads the answer itself }
      if (t <> 'boxplot') and (t <> 'lines') and (t <> 'parallel')
        and cb.ColOf(raw, c) then
      begin
        if raw > High(AVisual.CbFill) then
        begin
          SetLength(AVisual.CbFill, raw + 1);
          SetLength(AVisual.CbFillSet, raw + 1);
        end;
        AVisual.CbFill[raw] := c;
        AVisual.CbFillSet[raw] := True;
      end;
    end;
  end;
end;

{ AN effectScatter's rippleEffect and showEffectOn, upstream's defaults
  under them: ripples on render, three of them, filled. [Batch 71] }
procedure TTyCustomAdvanceChart.RippleOf(ASlot: Integer; var AVisual: TTySeriesVisual);
var
  node, re, d: TJSONData;
  c: TTyChartColor;
begin
  AVisual.RippleShow := True;
  AVisual.RippleNumber := 3;
  AVisual.RippleFill := True;
  AVisual.RippleHasColor := False;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('showEffectOn');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> 'render') then
    AVisual.RippleShow := False;
  re := TJSONObject(node).Find('rippleEffect');
  if (re = nil) or (re.JSONType <> jtObject) then Exit;
  d := TJSONObject(re).Find('number');
  if (d <> nil) and (d.JSONType = jtNumber) then
    AVisual.RippleNumber := Max(0, Trunc(d.AsFloat));
  { the loop's own [Batch 92] }
  d := TJSONObject(re).Find('period');
  if (d <> nil) and (d.JSONType = jtNumber) then AVisual.RipplePeriod := d.AsFloat;
  d := TJSONObject(re).Find('scale');
  if (d <> nil) and (d.JSONType = jtNumber) then AVisual.RippleScale := d.AsFloat;
  d := TJSONObject(re).Find('brushType');
  if (d <> nil) and (d.JSONType = jtString) then
    AVisual.RippleFill := d.AsString <> 'stroke';
  d := TJSONObject(re).Find('color');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
  begin
    AVisual.RippleHasColor := True;
    AVisual.RippleColor := c;
  end;
end;

{ a heatmap's itemStyle.borderRadius: a number, or zrender's array forms }
function TTyCustomAdvanceChart.HeatmapRadii(ASeriesIndex, APPI: Integer): TTyCornerRadii;
var
  node, d: TJSONData;
  vals: array of Double;
  k: Integer;
begin
  Result := Default(TTyCornerRadii);
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('itemStyle');
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  d := TJSONObject(d).Find('borderRadius');
  if d = nil then Exit;
  vals := nil;
  if d.JSONType = jtNumber then
  begin
    SetLength(vals, 1);
    vals[0] := d.AsFloat;
  end
  else if d.JSONType = jtArray then
  begin
    SetLength(vals, d.Count);
    for k := 0 to d.Count - 1 do
      if d.Items[k].JSONType = jtNumber then vals[k] := d.Items[k].AsFloat
      else vals[k] := 0;
  end
  else Exit;
  if Length(vals) = 0 then Exit;
  TyZrRadii(vals, Result[0], Result[1], Result[2], Result[3]);
  for k := 0 to 3 do Result[k] := Result[k] * APPI / 96;
end;

function TTyCustomAdvanceChart.BuildSeriesList(const AMeasurer: ITyTextMeasurer;
  APPI: Integer): Integer;
var
  list: TTyPaintList;
  i, drawn, furniture, n: Integer;
  v: TTySeriesVisual;
  pv: TTyPieVisual;
  fv: TTyFunnelVisual;
  rv: TTyRadarVisual;
  pls: TTyPieLabelSpec;
  pn, lo, hi: Integer;
  gv: TTyGaugeVisual;
  gi: TTyGraphInk;
  ti: TTyTreeInk;
  si2: TTySunburstInk;
  specs: TTyLabelSpecArray;
  itemSpecs: TTyLabelSpecTable;
  pk, gk, gq: Integer;
  tmOrder: TTyIntegerArray;
  gfxCount: Integer;
  utAt: Integer;
begin
  Result := 0;
  gfxCount := 0;
  Inc(GListBuilds);
  { ONE LIST FOR EVERY SERIES, not one per series: the ordering rule is (Z, Z2,
    insertion) ACROSS the chart, and a list per series would order each one
    against itself and leave the between-series order to the loop. }
  if FPaintList = nil then FPaintList := TTyPaintList.Create
  else FPaintList.Clear;
  list := FPaintList;
  FListTailAt := -1;
  { a new list: no entry is a custom element yet, and what the last render
    removed may go [Batch 123] }
  FCustomPaintEls := nil;
  for i := 0 to High(FCustomViews) do
    if FCustomViews[i] <> nil then FCustomViews[i].FreeGone;
  { THE GRAPHIC ELEMENTS FIRST: at an equal z they are under every series,
    the component's group joining the root before the series' [Batch 122] }
  for i := 0 to High(FGfxPaint) do list.Add(FGfxPaint[i]);
  gfxCount := Length(FGfxPaint);
  { a new list: the incremental layer holds none of it [Batch 119] }
  FProgLayerOk := False;
  { BEFORE THE EARLY EXIT, not after -- and not because a stale list would
    otherwise be read: Clear has already run, so the answer would be "nothing"
    either way. It is here because a render that drew no series is still a
    render, and marking it invalid would say the chart has not drawn yet. The
    two are the same answer today and stop being it the moment a caller wants
    to tell "there is nothing there" from "there is nothing yet". }
  FPaintListPPI := APPI;
  FPaintListValid := True;
  Result := gfxCount;
  { A NEW JITTER PASS: the seed again and no points placed [Batch 110] }
  if FJitter = nil then FJitter := TTyJitterPass.Create;
  FJitter.Reset;
  { THE RADAR'S OWN FURNITURE, ONCE PER RADAR AND BEFORE ANY SERIES. It is not
    a series' geometry -- several series share one radar -- and it is not a
    cartesian axis either, so the grid painter never sees it. It goes into the
    same list because the ordering rule is chart-wide.

    Above the `Length(FBindings) = 0` early-out: a radar with its indicators
    written and no series at all is a legitimate chart, and an empty one is
    the first thing anybody sees while they are still typing. }
  drawn := 0;
  { a view excludeComponents names is not built, and one that builds
    something is drawn [Batch 106] }
  if not ViewHidden(cvRadar) then
    for i := 0 to High(FRadars) do
      Inc(drawn, TyBuildRadarGrid(FRadars[i], RadarInk, AMeasurer, APPI, list));
  if drawn > 0 then ViewDrew(cvRadar);
  { THE CALENDARS' TOO, before any series: at the same z a series is drawn
    at, the order is decided by z2 -- day cell 0, heatmap cell 1, month line
    20, names 30 -- and ties by insertion, components first. [Batch 69] }
  furniture := drawn;
  if not ViewHidden(cvCalendar) then
    for i := 0 to High(FCalendars) do
      Inc(drawn, TyBuildCalendar(FCalendars[i], CalendarInk, AMeasurer, APPI, list));
  if drawn > furniture then ViewDrew(cvCalendar);
  furniture := drawn;
  { THE MATRICES' TOO, at their own z (-50 by default: under every series)
    [Batch 145] }
  if not ViewHidden(cvMatrix) then
    for i := 0 to High(FMatrices) do
      Inc(drawn, TyBuildMatrix(FMatrices[i], MatrixInk, RtGlobal, AMeasurer, APPI, list));
  if drawn > furniture then ViewDrew(cvMatrix);
  furniture := drawn;
  { THE GEOS' MAPS, a component group ahead of every series [Batch 146] --
    and where each went, a map series' data's flags taken first
    [Batch 152] }
  FGeoDraws := nil;
  FMapSyms := nil;
  for i := 0 to High(FGeos) do
  begin
    if FGeos[i] = nil then Continue;
    GeoSyncFromRows(FGeos[i]);
    n := list.Count;
    Inc(drawn, TyBuildGeo(FGeos[i], GeoInk, AMeasurer, APPI, list));
    SetLength(FGeoDraws, Length(FGeoDraws) + 1);
    FGeoDraws[High(FGeoDraws)].Geo := FGeos[i];
    FGeoDraws[High(FGeoDraws)].Series := -1;
    FGeoDraws[High(FGeoDraws)].Start := n;
    FGeoDraws[High(FGeoDraws)].Count := list.Count - n;
  end;
  furniture := drawn;
  { nothing is large until the loop below says so [Batch 117] }
  SetLength(FLargeKinds, Length(FBindings));
  for i := 0 to High(FLargeKinds) do FLargeKinds[i] := lgkNone;
  { [Batch 150] WHAT THE COMPONENTS BUILT COUNTS before the early exit: a
    map, a radar or a calendar with no series at all is drawn -- the answer
    used to be the graphic elements alone, and PaintSeries paints nothing
    for a nought, so a geo-only chart was blank }
  Result := drawn + gfxCount;
  if Length(FBindings) = 0 then Exit;
  begin
    for i := 0 to High(FBindings) do
    begin
      if i > High(FStores) then Break;
      { SWITCHED OFF, so nothing of it is drawn -- not its marks, not its
        labels (the expansion below only sees what reached the list), and
        not its wedges. The pie branch is inside this guard for the sake of
        the one case that can reach it: a `legend.data` entry naming the pie
        series itself. }
      if FBindings[i].Hidden then Continue;
      { A pie is not on a coordinate system, so it takes the other pass. It
        goes into the SAME list: the ordering rule is chart-wide, and a pie
        beside a bar has to sort against it like anything else. }
      { A FUNNEL IS NOT ON A COORDINATE SYSTEM EITHER, and like the pie it
        solves its own geometry in the layout pass and replays it here. }
      { A GRAPH IS ON A COORDINATE SYSTEM OF ITS OWN, and that system belongs
        to the series rather than to a component -- so it is solved in the
        layout pass like a pie's box and replayed here like a radar's. }
      { A CUSTOM SERIES: the elements its renderItem made, drawn from its
        view [Batch 123] }
      if FBindings[i].SeriesType = TyCustomSeriesType then
      begin
        Inc(drawn, CustomBuild(i, list, APPI));
        Continue;
      end;
      { A LINES SERIES: its rows laid out on their coordinate system in the
        layout pass, drawn here; the labels go through the expansion with a
        spec per row [Batch 121] }
      { A PARALLEL SERIES: a polyline per row, laid out in the layout pass
        [Batch 128] }
      if FBindings[i].SeriesType = TyParallelSeriesTypeName then
      begin
        if (i <= High(FParSolved)) and FParSolved[i].Valid then
          Inc(drawn, TyBuildParallelMarks(FParSolved[i], list));
        Continue;
      end;
      if FBindings[i].SeriesType = TyLinesSeriesTypeName then
      begin
        if (i <= High(FLines)) and FLines[i].Valid then
        begin
          if FLines[i].IsLarge then FLargeKinds[i] := lgkLines;
          Inc(drawn, TyBuildLinesMarks(FLines[i], TTyChartColor(
            ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
              [tysNormal]).Background.Color), list));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := LabelSpecFor(i);
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := FLinesSpecs[i];
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TyGraphSeriesTypeName then
      begin
        if (i <= High(FGraphLaidOut)) and FGraphLaidOut[i] then
        begin
          gi := GraphInk(i);
          { ON A VIEW THE SYMBOLS ARE SCALED as zrender composes them: the
            view's overall scale times the compensation scale. }
          if (i <= High(FGraphs)) and (FGraphs[i] <> nil) then
          begin
            utAt := list.Count;
            Inc(drawn, TyBuildGraphMarks(FBindings[i].SeriesIndex,
              FGraphSpecs[i], FGraphNodes[i], FGraphEdges[i],
              gi, FStores[i], list,
              FGraphs[i].OverallScaleX * FGraphNodeScale[i],
              FGraphs[i].OverallScaleY * FGraphNodeScale[i]));
            { [F3c] a node's symbol group in the main group: its place and
              the compensation scale, which a universal transition reads off
              a disposed view }
            UtTagGraphNodes(list, utAt, FGraphNodes[i], FGraphNodeScale[i]);
          end
          else
            Inc(drawn, TyBuildGraphMarks(FBindings[i].SeriesIndex,
              FGraphSpecs[i], FGraphNodes[i], FGraphEdges[i],
              gi, FStores[i], list));
          { AND ITS LABEL SPEC INTO THE TABLE THE EXPANSION READS. A mark
            carries only the WORDS; where they go and what they are drawn
            in is looked up by series index afterwards, so a branch that
            returns before filling this row stamps captions nothing ever
            places -- which looks exactly like a series with no labels. }
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := gi.Label_;
          { THE EDGE LABELS' specs, one per edge: an edge's caption names its
            own by ItemSpec = its index + 1 [Batch 114] }
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := gi.EdgeLabelSpecs;
          { and the nodes' own after them [F2a] }
          gk := Length(gi.EdgeLabelSpecs);
          SetLength(itemSpecs[FBindings[i].SeriesIndex], gk + Length(gi.NodeLabels));
          for gq := 0 to High(gi.NodeLabels) do
            itemSpecs[FBindings[i].SeriesIndex][gk + gq] := gi.NodeLabels[gq];
        end;
        Continue;
      end;
      { A TREE lays itself out in its box (SolveTrees) and draws its edges,
        its symbols and its label requests here -- BEFORE the expansion,
        whose per-row table carries the item -> leaves -> series chain.
        [Batch 73] }
      if FBindings[i].SeriesType = TySankeySeriesTypeName then
      begin
        if (i <= High(FSankeys)) and FSankeys[i].Valid then
        begin
          FSankeyInks[i].NodeDecals := RawRowDecals(i);
          Inc(drawn, TyBuildSankeyMarks(FBindings[i].SeriesIndex, FSankeys[i],
            FSankeyInks[i], list));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := FSankeyInks[i].Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := FSankeyInks[i].ItemLabels;
        end;
        Continue;
      end;
      { A CHORD: its sectors, its ribbons, its label requests [Batch 120] }
      if FBindings[i].SeriesType = TyChordSeriesTypeName then
      begin
        if (i <= High(FChords)) and FChords[i].Valid then
        begin
          FChordInks[i].NodeDecals := RawRowDecals(i);
          Inc(drawn, TyBuildChordMarks(FBindings[i].SeriesIndex, FChords[i],
            FChordInks[i], list));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := FChordInks[i].Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := FChordInks[i].ItemLabels;
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TyTreemapSeriesTypeName then
      begin
        if (i <= High(FTreemaps)) and FTreemaps[i].Valid then
        begin
          { eachNode's pre-order: the rows' own, as written }
          SetLength(tmOrder, Length(FTreemaps[i].Hier.Nodes));
          for gq := 0 to High(tmOrder) do tmOrder[gq] := gq;
          FTreemapInks[i].NodeDecals := TreeNodeDecals(i, FTreemaps[i].Hier, tmOrder);
          Inc(drawn, TyBuildTreemapMarks(FBindings[i].SeriesIndex, FTreemaps[i],
            FTreemapInks[i], list));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := FTreemapInks[i].Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := FTreemapInks[i].ItemLabels;
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TySunburstSeriesTypeName then
      begin
        if (i <= High(FSunbursts)) and FSunbursts[i].Valid then
        begin
          si2 := SunburstInk(i);
          { the layout sorted the children in place: eachNode walks them so }
          si2.NodeDecals := TreeNodeDecals(i, FSunbursts[i].Hier,
            TySunburstSubtree(FSunbursts[i], 0));
          Inc(drawn, TyBuildSunburstMarks(FBindings[i].SeriesIndex, FSunbursts[i], si2,
            FStores[i], list, APPI));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := si2.Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := si2.ItemLabels;
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TyTreeSeriesTypeName then
      begin
        if (i <= High(FTrees)) and FTrees[i].Valid then
        begin
          ti := TreeInk(i);
          Inc(drawn, TyBuildTreeMarks(FBindings[i].SeriesIndex, FTrees[i], ti,
            FStores[i], list, APPI));
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := ti.Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := ti.ItemLabels;
        end;
        Continue;
      end;
      if FBindings[i].RadarIndex >= 0 then
      begin
        if FBindings[i].RadarIndex <= High(FRadars) then
        begin
          rv := RadarVisual(i);
          Inc(drawn, TyBuildRadarMarks(FBindings[i],
            FRadars[FBindings[i].RadarIndex], rv, FStores[i],
            FRadarDims[i], APPI, list));
          { [R2-A] its points' labels go through the expansion, the item's
            own over the series' }
          if Length(specs) <= FBindings[i].SeriesIndex then
            SetLength(specs, FBindings[i].SeriesIndex + 1);
          specs[FBindings[i].SeriesIndex] := rv.Label_;
          if Length(itemSpecs) <= FBindings[i].SeriesIndex then
            SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
          itemSpecs[FBindings[i].SeriesIndex] := rv.ItemLabels;
        end;
        Continue;
      end;
      { A GAUGE IS NOT ON A COORDINATE SYSTEM EITHER, and it splits its
        drawing in two: the dial is the same whatever the data says, and only
        the needles, the arcs and the words depend on it. }
      if FBindings[i].SeriesType = TyGaugeSeriesTypeName then
      begin
        if i <= High(FGauges) then
        begin
          gv := GaugeVisual(i);
          utAt := list.Count;
          Inc(drawn, TyBuildGaugeAxis(FBindings[i], FGauges[i],
            FGaugeSpecs[i], gv, AMeasurer, APPI, list));
          { [F3c] the dial's paths (no text): its view's, faded in where a
            universal transition morphs }
          UtTagFade(list, utAt, FBindings[i].SeriesIndex);
          Inc(drawn, TyBuildGaugeValue(FBindings[i], FGauges[i],
            FGaugeSpecs[i], FGaugeItems[i], gv, FStores[i],
            FStores[i].DimIndexOf(TyGaugeValueDim), AMeasurer, APPI, list));
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TyFunnelSeriesTypeName then
      begin
        if i <= High(FFunnels) then
        begin
          fv := FunnelVisual(i);
          lo := list.Count;
          Inc(drawn, TyBuildFunnelMarks(FBindings[i], FFunnels[i], fv, list));
          hi := list.Count;
          { ITS OWN PASS, not TyExpandLabels -- for the same reason a pie's is.
            A band's words are placed from the trapezoid's CORNERS and from a
            guide line that has to be drawn with them; the box-placed
            expansion knows about neither, and a funnel's bounding box is not
            where its label goes. }
          Inc(drawn, TyBuildFunnelLabels(FBindings[i], FFunnels[i],
            TyFunnelLabelSpecOf(FOption, FBindings[i].SeriesIndex,
              TyFunnelLabelSpecDefault),
            FunnelLabelInk, fv.Fills, FStores[i], SeriesModelName(FBindings[i].SeriesIndex),
            FStores[i].DimIndexOf(TyPieValueDim), AMeasurer, APPI, list));
          OwnLabelOpacity(i, list, lo, hi);
        end;
        Continue;
      end;
      if FBindings[i].SeriesType = TyPieSeriesTypeName then
      begin
        if i <= High(FPies) then
        begin
          pv := PieVisual(i);
          lo := list.Count;
          Inc(drawn, TyBuildPieMarks(FBindings[i], FPies[i], FPieSpecs[i],
            pv, list));
          hi := list.Count;
          { ITS OWN PASS, not TyExpandLabels. A pie label is placed from the
            slice's ANGLES and the series radius, none of which survive into
            the sector's bounding box -- the box of a wedge is the whole
            outer disc, so a label placed from it would sit at the disc's
            centre for every slice. }
          { each item's own label and line over the series' [R2-A] }
          pls := TyPieLabelSpecOf(FOption, FBindings[i].SeriesIndex,
            TyPieLabelSpecDefault);
          pn := 0;
          if FStores[i] <> nil then pn := FStores[i].RawCount;
          Inc(drawn, TyBuildPieLabels(FBindings[i], FPies[i], pls,
            TyPieItemLabelSpecs(FOption, FBindings[i].SeriesIndex, pls, pn),
            PieLabelInk, pv.Fills, FStores[i], SeriesModelName(FBindings[i].SeriesIndex),
            FStores[i].DimIndexOf(TyPieValueDim),
            FPieSpecs[i].PercentPrecision, AMeasurer, APPI, list));
          OwnLabelOpacity(i, list, lo, hi);
        end;
        Continue;
      end;
      { A MAP SERIES: its group's map where it is the main one, its legend
        symbols [Batch 152, D14 GE4] }
      if FBindings[i].SeriesType = TyMapSeriesTypeName then
      begin
        Inc(drawn, BuildMapSeries(i, AMeasurer, APPI, list));
        Continue;
      end;
      { A THEMERIVER: a polygon per layer, its label at the layer's start
        [Batch 118] }
      if FBindings[i].SeriesType = TyThemeRiverSeriesTypeName then
      begin
        Inc(drawn, BuildRiverMarks(i, list, APPI));
        if Length(specs) <= FBindings[i].SeriesIndex then
          SetLength(specs, FBindings[i].SeriesIndex + 1);
        specs[FBindings[i].SeriesIndex] := RiverLabelSpec(i);
        Continue;
      end;
      v := TySeriesVisual(TTyChartColor(SeriesColor(FBindings[i].SeriesIndex)));
      ApplyOptStyle(v, FBindings[i].SeriesIndex);
      ApplyVisualMaps(v, i, APPI);
      if i <= High(FBarCols) then v.Bar := FBarCols[i];
      v.RealtimeSort := RtSortOf(i);
      if i <= High(FPolarBars) then v.PolarBar := FPolarBars[i];
      v.Line := TyLineSpecOf(FOption, FBindings[i].SeriesIndex);
      { the area's base is smoothed as the series it stands on is }
      if (i <= High(FStacks)) and (FStacks[i].OnSlot >= 0)
        and (FStacks[i].OnSlot <= High(FBindings)) then
        v.Line.StackedOnSmooth := TyLineSpecOf(FOption,
          FBindings[FStacks[i].OnSlot].SeriesIndex).Smooth;
      v.Candle := CandleVisual(FBindings[i].SeriesIndex);
      { The thinning the AXIS settled on. When markers would crowd, upstream
        falls back to the category axis' own label interval -- which the layout
        pass already computed, so it is fetched rather than re-derived. }
      v.Line.LabelStep := LabelStepFor(FBindings[i].BaseAxis);
      v.Symbol := SymbolFor(i);
      { LARGE MODE: one batch per style [Batch 117] }
      v.Large := LargeKindOf(i);
      FLargeKinds[i] := v.Large;
      { A PROGRESSIVE BATCH comes a chunk at a time: every planned chunk's
        rows, the frames show them [Batch 119] }
      if (v.Large <> lgkNone) and ProgOnOf(i) then
      begin
        SetLength(v.LargeChunks, Length(FProg[i].Starts));
        for pk := 0 to High(FProg[i].Starts) do
          v.LargeChunks[pk] := TyProgRowsOf(FProg[i], pk);
      end;
      if FBindings[i].SeriesType = 'effectScatter' then RippleOf(i, v);
      { [R2-J3] a line's items too: dataSymbolTask runs on every series
        with symbols }
      if (FBindings[i].SeriesType = 'scatter')
        or (FBindings[i].SeriesType = 'effectScatter')
        or (FBindings[i].SeriesType = 'line') then
        SymbolItems(FBindings[i].SeriesIndex, v.Symbol, v.SymItems, v.SymItemHas);
      { [R2-J2] symbolSize: '@Name', itemStyle.color: '@Name' }
      VisualCallbacks(i, v);
      v.ItemCb := ItemCbOf(i);
      JitterFor(i, APPI, v);
      { THE PICTORIAL OPTIONS, read for every series rather than only for the
        one type that uses them. The alternative is a branch on the type name
        here, and this file already has too many of those: the reader is
        cheap, the builder is the only thing that looks at the answer, and a
        series that is not a pictorialBar simply carries the defaults. }
      v.Pictorial := TyPictorialSpecOf(FOption, FBindings[i].SeriesIndex);
      { An `empty` symbol is filled with the chart's own surface, so it reads as
        a hole rather than as a white dot on a dark skin. Upstream fills it from
        a token too, so parity and this library's own rule agree. }
      v.EmptyFill := TTyChartColor(
        ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
          [tysNormal]).Background.Color);
      { A CANDLESTICK'S OR A BOXPLOT'S solved layout, and a boxplot's style:
        itemStyle.color over the theme's surface (upstream's
        tokens.color.neutral00), itemStyle.borderColor over the series
        colour -- a boxplot draws with its stroke -- and borderWidth over 1
        [Batch 108] }
      if i <= High(FWhiskers) then v.Whisker := FWhiskers[i];
      if FBindings[i].SeriesType = 'boxplot' then BoxplotStyle(i, v);

      { showBackground's strip. Its own key rather than the split area's: the
        two are faint for different reasons and a theme has to be able to move
        one without the other. }
      v.BackgroundFill := TTyChartColor(
        ActiveController.Model.ResolveStyle('TyAdvChartBarBackground', '',
          []).Background.Color);
      { `z` AND `z2`, the series default z UPSTREAM'S 2. [Batch 64: it was 0,
        on the grounds that nothing else here shared the scale. Markers do: a
        markArea sits at z 1, UNDER its series, and a markPoint or markLine at
        5, over it -- and only with the series at 2 do upstream's own numbers
        order them. The grid and the axes are still drawn outside the list.]

        READ RATHER THAN INVENTED because it decides a picture nobody can work
        around: `pictorialBar-body-fill` draws the same silhouette three times,
        a grey one last, and only `z: 10` on the two clipped series keeps the
        fill in front of it. Without this the chart is three grey bodies.

        zlevel IS NOT READ. It is a separate canvas upstream, not a deeper
        sort key, and pretending it is one would put a series in the right
        order for the wrong reason. }
      { [Batch 68: a LINE's default is 3, not 2 -- LineSeries.ts:161 --
        so a line over a bar of the same chart is drawn above it however
        the two are declared.] }
      if FBindings[i].SeriesType = 'line' then
        v.Z := SeriesIntIn(FBindings[i].SeriesIndex, 'z', 3)
      else
        v.Z := SeriesIntIn(FBindings[i].SeriesIndex, 'z', 2);
      v.Z2 := SeriesIntIn(FBindings[i].SeriesIndex, 'z2', 0);
      v.Label_ := LabelSpecFor(i);
      { A HEATMAP CELL is labelled with the third element of its raw row, and
        rounded by its series' itemStyle.borderRadius }
      v.HeatPadPx := 0.5 * APPI / 96;
      v.PxScale := APPI / 96;
      if FBindings[i].SeriesType = 'heatmap' then
      begin
        v.Label_.DefaultText := tldRawThird;
        v.Bar.Radii := HeatmapRadii(FBindings[i].SeriesIndex, APPI);
        HeatmapItemRadii(FBindings[i].SeriesIndex, APPI, v.HeatRadii, v.HeatHasRadii);
        ItemLabelSpecs(FBindings[i].SeriesIndex, v.Label_, v.ItemLabels, v.HasItemLabel);
        if Length(itemSpecs) <= FBindings[i].SeriesIndex then
          SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
        itemSpecs[FBindings[i].SeriesIndex] := v.ItemLabels;
      end
      else if (FBindings[i].SeriesType = 'scatter')
        or (FBindings[i].SeriesType = 'effectScatter')
        or (FBindings[i].SeriesType = 'bar') or (FBindings[i].SeriesType = 'line')
        or (FBindings[i].SeriesType = 'pictorialBar') then
      begin
        { a symbol's own label over its series' [Batch 71]; a bar's, a
          line point's and a pictorial bar's too [Batch 82] }
        ItemLabelSpecs(FBindings[i].SeriesIndex, v.Label_, v.ItemLabels, v.HasItemLabel);
        if Length(itemSpecs) <= FBindings[i].SeriesIndex then
          SetLength(itemSpecs, FBindings[i].SeriesIndex + 1);
        itemSpecs[FBindings[i].SeriesIndex] := v.ItemLabels;
      end;
      { `{c}` and the default text read the VALUE column -- whichever axis is
        not the base one. A label that read x on a bar chart would show the
        category ordinal, which is a number and looks like an answer. }
      v.LabelValueDim := -1;
      if (FBindings[i].ValueAxis <> nil) and (FStores[i] <> nil) then
        v.LabelValueDim := FStores[i].DimIndexOf(FBindings[i].ValueAxis.Dim)
      { on a single axis the one dimension is the label's (defaultedLabel)
        [Batch 118] }
      else if (FBindings[i].Single <> nil) and (FStores[i] <> nil) then
        v.LabelValueDim := FStores[i].DimIndexOf(TySingleDim);
      v.SeriesName := SeriesModelName(FBindings[i].SeriesIndex);
      v.SeriesIndex := FBindings[i].SeriesIndex;
      v.SeriesType := FBindings[i].SeriesType;
      if Length(specs) <= FBindings[i].SeriesIndex then
        SetLength(specs, FBindings[i].SeriesIndex + 1);
      specs[FBindings[i].SeriesIndex] := v.Label_;
      { ON A CALENDAR there is no cartesian to enter: the calendar is the
        coordinate system and only a heatmap draws on it yet. [Batch 70] }
      if FBindings[i].CalendarIndex >= 0 then
      begin
        if (FBindings[i].CalendarIndex <= High(FCalendars)) and (FStores[i] <> nil) then
        begin
          if FBindings[i].SeriesType = 'heatmap' then
            Inc(drawn, TyBuildCalendarHeatmap(FBindings[i],
              FCalendars[FBindings[i].CalendarIndex], FStores[i], v, list))
          else if (FBindings[i].SeriesType = 'scatter')
            or (FBindings[i].SeriesType = 'effectScatter') then
          begin
            { a symbol's default words are its value [Batch 71] }
            v.LabelValueDim := FStores[i].DimIndexOf(TyCalendarValueDim);
            Inc(drawn, TyBuildCalendarScatter(FBindings[i],
              FCalendars[FBindings[i].CalendarIndex], FStores[i], v, list));
          end;
        end;
        Continue;
      end;
      { ON A MATRIX: a heatmap's cells and a scatter's symbols on the
        matrix's cells [Batch 145] }
      if FBindings[i].MatrixIndex >= 0 then
      begin
        if (FBindings[i].MatrixIndex <= High(FMatrices)) and (FStores[i] <> nil) then
        begin
          if FBindings[i].SeriesType = 'heatmap' then
            Inc(drawn, TyBuildMatrixHeatmap(FBindings[i],
              FMatrices[FBindings[i].MatrixIndex], FStores[i],
              FStores[i].DimIndexOf(TyMatrixXDim), FStores[i].DimIndexOf(TyMatrixYDim), v, list))
          else
          begin
            { NO DEFAULT WORDS: the defaulted label is the last coordinate
              dimension a label can show, and on a matrix those are x and y
              -- ordinal, so none (the value is not one of them) }
            v.LabelValueDim := -1;
            Inc(drawn, TyBuildMatrixScatter(FBindings[i],
              FMatrices[FBindings[i].MatrixIndex], FStores[i],
              FStores[i].DimIndexOf(TyMatrixXDim), FStores[i].DimIndexOf(TyMatrixYDim), v, list));
          end;
        end;
        Continue;
      end;
      { ON A GEO: the points through the geo's dataToPoint, laid out at
        every build -- a roam moves them as updateTransform does
        [Batch 152, D14 GE4] }
      if FBindings[i].GeoIndex >= 0 then
      begin
        if (FStores[i] <> nil) and (GeoOfSlot(i) <> nil) then
        begin
          if (FBindings[i].SeriesType = 'scatter')
            or (FBindings[i].SeriesType = 'effectScatter') then
          begin
            v.LabelValueDim := FStores[i].DimIndexOf(TyGeoLatDim);
            Inc(drawn, TyBuildPointScatter(FBindings[i], FStores[i], v,
              GeoSeriesPoints(i), list));
          end
          else if FBindings[i].SeriesType = 'heatmap' then
            Inc(drawn, BuildGeoHeatmap(i, list));
        end;
        Continue;
      end;
      Inc(drawn, TyBuildSeriesMarks(FBindings[i], FStores[i],
        StackFor(i), v, list));
      { no end label on a polar (LineView warns and draws none) }
      if (FBindings[i].SeriesType = 'line') and (FBindings[i].Polar = nil) then
        Inc(drawn, BuildEndLabel(i, v, AMeasurer, APPI, list));
    end;
    { THE EXPANSION RUNS ONCE, HERE, AND NOTHING IS APPENDED AFTER IT. Each
      caption's geometry is frozen from its host at this moment and the list
      has no update path, so a mark added later would have no label and a mark
      moved later would leave its label behind. }
    if drawn > furniture then ViewDrew(cvSeries);
    if drawn > 0 then
      TyExpandLabels(list, specs, itemSpecs, AMeasurer, APPI);
    { THE LABEL LAYOUT, over the finished labels [Batch 103] }
    FLmItems := nil;
    FLmEls := nil;
    FLmGuides := nil;
    FLmRoute := nil;
    if drawn > 0 then
      LayoutSeriesLabels(list, specs, itemSpecs, AMeasurer, APPI);
    { the label lines, after the layout [Batch 112] }
    if drawn > 0 then
      RouteLabelLines(list, specs, itemSpecs, AMeasurer, APPI);
    { A SILENT SERIES TAKES NO POINTER: nothing of it -- marks, labels -- is
      hit, hovered or clicked (upstream's series `silent`) [Batch 84] }
    if drawn > 0 then SilenceSeries(list);
    { the cursors [F6a] }
    if drawn > 0 then StampCursors(list);
    { a treemap label's opacity, the node's [F2a] }
    if drawn > 0 then TmLabelOpacity(list);
    { THE CHUNKS: which frame draws each element of a progressive series,
      and which are still to come -- before the states, which an element
      with no data does not take [Batch 119] }
    if drawn > 0 then ProgTag(list);
    { THE STATES, onto the elements just built [Batch 88] -- and with
      nothing drawn too: a legend can switch every series off, and their
      records go with their elements [Batch 93] }
    StSync(list, APPI);
    { a hovered breadcrumb item [F2a] }
    TmCrumbStates(list);
    { a map picture's flags are its rows' -- the selection the sync just
      wrote among them [Batch 152] }
    MapRepatch(APPI);
    { THE LEGEND GOES IN AFTER THE EXPANSION, and it is allowed to because
      its captions are ANSWERS rather than requests -- they arrive with a
      font and an anchor already on them, which is what the expansion exists
      to supply. A MARK appended here would silently lose its label. }
    { MARKERS arrive as answers too: their labels are placed by Line.ts's own
      table, not by the expansion }
    Inc(drawn, BuildMarkers(AMeasurer, list));
    { the markers' blur, with their series' [F2b] }
    StSyncMarks(list);
    if not ViewHidden(cvLegend) then
    begin
      n := BuildLegends(APPI, list, AMeasurer);
      if n > 0 then ViewDrew(cvLegend);
      Inc(drawn, n);
    end;
    { the components from the visual maps on [R2-L: built by BuildListTail,
      which ListTailRebuild runs again on its own] }
    FListTailAt := list.Count;
    Inc(drawn, BuildListTail(list, AMeasurer));
    Result := drawn + gfxCount;
    UtStaleHarvest;
    if FLineHistDue then
    begin
      FLineHistDue := False;
      LineHistRoll;
    end;
    list.JournalClose;
  end;
end;

function TTyCustomAdvanceChart.BuildListTail(AList: TTyPaintList;
  const AMeasurer: ITyTextMeasurer): Integer;
var n: Integer;
begin
  Result := 0;
  if not ViewHidden(cvVisualMap) then
  begin
    n := BuildVisualMaps(AList);
    if n > 0 then ViewDrew(cvVisualMap);
    Inc(Result, n);
  end;
  if not ViewHidden(cvDataZoom) then
  begin
    n := BuildDataZooms(AList);
    if n > 0 then ViewDrew(cvDataZoom);
    Inc(Result, n);
  end;
  { the timeline, z 4 [Batch 129] }
  if not ViewHidden(cvTimeline) then
  begin
    n := BuildTimeline(AList);
    if n > 0 then ViewDrew(cvTimeline);
    Inc(Result, n);
  end;
  { [Batch 125] }
  if not ViewHidden(cvToolbox) then
  begin
    n := BuildToolboxes(AList, AMeasurer);
    if n > 0 then ViewDrew(cvToolbox);
    Inc(Result, n);
  end;
  { the parallel axes' covers, z 10000: their controllers' groups are
    zrender's, no view hides them [Batch 130] }
  Inc(Result, BuildParallelBrushes(AList));
  { the brush's covers, z 10000 [Batch 126]. Like the parallel axes',
    they are its controller's: BrushController.mount adds its group to
    zrender's root, outside the brush view's group, so
    `excludeComponents: ['brush']` cannot hide them and the brush view is
    never a view that drew (its group holds nothing) [milestone C14-C22] }
  Inc(Result, BuildBrushes(AList));
  { THE THUMBNAILS, z 10: the copy a full update takes of its graph (a
    roam only moves the window), then the box, the copy and the window
    as elements [Batch 140] }
  if FThumbSnapDue then ThumbRender;
  Inc(Result, BuildThumbnails(AList));
end;

{ THE COMPONENTS AT THE END OF THE LIST, built again where they stand
  [R2-L]. A visual map's indicator moving with the pointer (VmShowIndicator,
  VmHideIndicator) changes its elements and nothing before them: what a
  build puts before the visual maps reads none of their live state. Those
  elements stay; the rest is dropped and built again, as the build builds
  it. The list is then the one a whole build would give but for the
  states the pointer changed meanwhile, which the frame's own state pass
  writes (StApplyChanged / StPatchList, as for any hover) -- and the
  incremental layer is drawn again, as after a build. Not where an update
  is still to be laid out or armed, an export runs, or the journal keeps
  an element of the end (a rewind would put an old one back). }
function TTyCustomAdvanceChart.ListTailRebuild: Boolean;
begin
  Result := False;
  if GListTailOff or (FPaintList = nil) or not FPaintListValid or FDirty
    or FExporting or FAnimPending or (FLastPPI <= 0) or (FListTailAt < 0)
    or (FListTailAt > FPaintList.Count) or (FPaintListPPI <> FLastPPI)
    or FPaintList.JournalHoldsFrom(FListTailAt) then Exit;
  FPaintList.Truncate(FListTailAt);
  BuildListTail(FPaintList, NewTextMeasurer(FLastPPI));
  { the incremental layer holds none of the end: what a build would draw
    on it again it holds already where it is what a whole drawing in paint
    order gives -- else drawn again, as after a build }
  if FProgLayerInOrder and (Length(FProgPainted) >= FListTailAt) then
    SetLength(FProgPainted, FPaintList.Count)
  else
    FProgLayerOk := False;
  StaticDrop;
  FProgReuse := True;
  Inc(GListTails);
  Result := True;
end;

procedure TTyCustomAdvanceChart.ListTailRefresh;
begin
  if not ListTailRebuild then DropStaticKeepList;
end;

procedure TTyCustomAdvanceChart.FullUpdate;
begin
  FullUpdateWith(TyAnimNoOverride, False);
end;

procedure TTyCustomAdvanceChart.FullUpdateWith(const APayload: TTyAnimOverride;
  AHasPayload: Boolean);
var
  m: ITyTextMeasurer;
  hk, hs, hraw, slot, inner: Integer;
begin
  { [F4b] a batch's items: the update runs once, after the last }
  if FBatchDefer > 0 then
  begin
    FBatchDue := True;
    FBatchDuePayload := APayload;
    FBatchDueHas := AHasPayload;
    Exit;
  end;
  { an update renders every parallelAxis view -- but the one an
    axisAreaSelect names [Batch 130] }
  if not FParBrushInAas then FParBrushSkip := -1;
  { nothing laid out yet: the first paint does it all }
  if (FLastPPI <= 0) or (FBuild = nil) then
  begin
    FDirty := True;
    Invalidate;
    Exit;
  end;
  { THE UPDATE ANIMATES [Batch 96]: the render it starts from is kept }
  AnimFullBegin(APayload, AHasPayload);
  { THE HOVERED ELEMENT, by series and RAW row: a reused element keeps being
    the hovered one, whatever index the new list gives it }
  hk := FEvHover.HdKind;
  hs := FEvHover.HdSeries;
  hraw := -1;
  if (FEvHover.Id > 0) and (hk = 1) then hraw := StInnerRaw(hs, FEvHover.HdRow);
  m := NewTextMeasurer(FLastPPI);
  { renderSeries: clearStates, render, the previous states, then the flags
    (the generation Relayout moves) }
  Relayout(nil, FLastRect, FLastPPI, m);
  { AN ACTION THAT UPDATES does the lazy update waiting, and the dispatch
    publishes the one `updated` (echarts.ts doDispatchAction) [Batch 97] }
  FLazyPending := False;
  BuildSeriesList(m, FLastPPI);
  { [R2-I9] the paint draws this one (AnimFullEnd may drop it again) }
  FListFresh := True;
  AnimFullEnd;
  if FEvHover.Id > 0 then
  begin
    if (hk = 1) and (hraw >= 0) and (hs <= High(FSt)) and (FSt[hs].Kind <> sskNone)
      and (hraw <= High(FSt[hs].HostIdx)) and (FSt[hs].HostIdx[hraw] >= 0) then
    begin
      FEvHover := TargetOfElement(FSt[hs].HostIdx[hraw]);
      slot := SlotOfSeries(hs);
      inner := FStores[slot].IndexOfRawIndex(hraw);
      FEvHover.HdRow := inner;
    end
    else if (hk = 2) and (hs <= High(FSt)) and (FSt[hs].Kind <> sskNone)
      and (Length(FSt[hs].RunIdx) > 0) then
      FEvHover := TargetOfElement(FSt[hs].RunIdx[0])
    else
      { REMOVED BY THE RE-RENDER -- a legend item always is: zrender finds
        the hovered target again at the point it was found (#6198), with no
        out and no over }
      FEvHover := EventTargetAt(FEvLastX, FEvLastY);
  end;
  TipReset;
  { a racing view's first frame: its init sort, pending [Batch 135] }
  RtRenderPass;
  { the cached picture is the old render's; the list is the new one's }
  StaticDrop;
  FZrDirty := True;
  inherited Invalidate;
end;

{ ==================== [R2-I6] the parsed store kept between builds ==================== }

function TTyCustomAdvanceChart.StoreKeepSig(ASlot, ABranch, ADs: Integer;
  const ADims: TTySeriesDimArray; const AEnc: TTySeriesEncode): string;
var k: Integer;

  function Ints(const A: array of Integer): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to High(A) do Result := Result + IntToStr(A[j]) + ',';
  end;

begin
  Result := IntToStr(ASlot) + '|' + IntToStr(FBindings[ASlot].SeriesIndex) + '|'
    + FBindings[ASlot].SeriesType + '|' + IntToStr(ABranch) + '|' + IntToStr(ADs);
  if (ADs >= 0) and (ASlot <= High(FSources)) then
    Result := Result + '|' + IntToStr(Ord(FSources[ASlot].LayoutBy)) + ','
      + IntToStr(Ord(FSources[ASlot].Format)) + ',' + IntToStr(FSources[ASlot].StartIndex)
      + ',' + IntToStr(FSources[ASlot].DimCount);
  for k := 0 to High(ADims) do
    Result := Result + '|d' + ADims[k].Name + #1 + IntToStr(Ord(ADims[k].Kind)) + #1
      + IntToStr(ADims[k].SourceSlot) + #1 + ADims[k].Coord + #1
      + BoolToStr(ADims[k].FromRowIndex, '1', '0') + BoolToStr(ADims[k].Axis <> nil, '1', '0');
  Result := Result + '|e' + BoolToStr(AEnc.Given, '1', '0') + Ints(AEnc.Columns) + ';';
  for k := 0 to High(AEnc.Explicit) do Result := Result + BoolToStr(AEnc.Explicit[k], '1', '0');
  Result := Result + ';' + Ints(AEnc.Tooltip) + ';' + Ints(AEnc.Labels) + ';'
    + IntToStr(AEnc.ItemName) + ';' + IntToStr(AEnc.SeriesName);
end;

procedure TTyCustomAdvanceChart.StoreKeepPre(const ADims: TTySeriesDimArray;
  out APre: TTyIntegerArray);
var k: Integer;
begin
  APre := nil;
  SetLength(APre, Length(ADims));
  for k := 0 to High(ADims) do
    if (ADims[k].Axis <> nil) and (ADims[k].Axis.Categories <> nil) then
      APre[k] := ADims[k].Axis.Categories.Count
    else
      APre[k] := -1;
end;

{ every borrowed list a different object: a fill that interleaves two
  columns over one collecting list is not split into per-column runs }
function StoreKeepMetasDistinct(const ADims: TTySeriesDimArray): Boolean;
var j, k: Integer;
begin
  Result := False;
  for k := 0 to High(ADims) do
  begin
    if ADims[k].Axis = nil then Continue;
    if ADims[k].Axis.Categories = nil then Exit;
    for j := 0 to k - 1 do
      if (ADims[j].Axis <> nil) and (ADims[j].Axis.Categories = ADims[k].Axis.Categories) then
        Exit;
  end;
  Result := True;
end;

procedure TTyCustomAdvanceChart.StoreKeepBegin;
var i: Integer;
begin
  for i := 0 to High(FStoreKeep) do FStoreKeep[i].Used := False;
end;

procedure TTyCustomAdvanceChart.StoreKeepEnd;
var i: Integer;
begin
  for i := 0 to High(FStoreKeep) do
    if not FStoreKeep[i].Used then
    begin
      FreeAndNil(FStoreKeep[i].Store);
      FStoreKeep[i] := Default(TTyStoreKeep);
    end;
  if Length(FStoreKeep) > Length(FBindings) then
    SetLength(FStoreKeep, Length(FBindings));
end;

procedure TTyCustomAdvanceChart.StoreKeepDrop;
var i: Integer;
begin
  for i := 0 to High(FStoreKeep) do FreeAndNil(FStoreKeep[i].Store);
  FStoreKeep := nil;
end;

function TTyCustomAdvanceChart.StoreKeepTake(ASlot: Integer; const ASig: string;
  const ADims: TTySeriesDimArray): Boolean;
var
  e: ^TTyStoreKeep;
  k, q: Integer;
  m: TTyOrdinalMeta;
  metas: array of TTyOrdinalMeta;
begin
  Result := False;
  if (GStoreKeepMinRows < 0) or (ASlot > High(FStoreKeep)) or (FOption = nil) then Exit;
  e := @FStoreKeep[ASlot];
  if not e^.Valid or (e^.Store = nil) or (e^.Gen <> FOption.Generation)
    or (e^.Sig <> ASig) or not StoreKeepMetasDistinct(ADims) then Exit;
  { the lists the new axes hold: as they were when the store was kept }
  q := 0;
  for k := 0 to High(ADims) do
  begin
    if ADims[k].Axis = nil then Continue;
    if (q > High(e^.MetaDim)) or (e^.MetaDim[q] <> k) then Exit;
    m := ADims[k].Axis.Categories;
    if (m.NeedCollect <> e^.MetaCollect[q]) or (m.Deduplication <> e^.MetaDedup[q]) then Exit;
    if e^.MetaCollect[q] then
    begin
      if not m.StartsWith(e^.MetaList[q], e^.MetaPre[q], e^.MetaPre[q]) then Exit;
    end
    else if not m.StartsWith(e^.MetaList[q], Length(e^.MetaList[q]),
      Length(e^.MetaList[q])) then Exit;
    Inc(q);
  end;
  if q <> Length(e^.MetaDim) then Exit;
  { what the fill collected, in its order }
  q := 0;
  metas := nil;
  SetLength(metas, Length(ADims));
  for k := 0 to High(ADims) do
  begin
    if ADims[k].Axis = nil then Continue;
    m := ADims[k].Axis.Categories;
    metas[k] := m;
    if e^.MetaCollect[q] then
      m.AppendCollected(e^.MetaList[q], e^.MetaPre[q]);
    Inc(q);
  end;
  FStores[ASlot].Free;
  FStores[ASlot] := e^.Store.CloneWith(metas);
  e^.Used := True;
  Inc(GStoreKeeps);
  Result := True;
end;

procedure TTyCustomAdvanceChart.StoreKeepPut(ASlot: Integer; const ASig: string;
  const ADims: TTySeriesDimArray; const APre: TTyIntegerArray);
var
  e: TTyStoreKeep;
  st: TTyDataStore;
  k, q, total, i: Integer;
  m: TTyOrdinalMeta;
  metas: array of TTyOrdinalMeta;
begin
  if (GStoreKeepMinRows < 0) or (FOption = nil) or (ASlot > High(FStores)) then Exit;
  st := FStores[ASlot];
  if (st = nil) or (st.RawCount < GStoreKeepMinRows) then Exit;
  if not StoreKeepMetasDistinct(ADims) then Exit;
  total := st.RawCount;
  for i := 0 to High(FStoreKeep) do
    if (i <> ASlot) and FStoreKeep[i].Valid and FStoreKeep[i].Used
      and (FStoreKeep[i].Store <> nil) then
      Inc(total, FStoreKeep[i].Store.RawCount);
  if total > cStoreKeepMaxRows then Exit;
  e := Default(TTyStoreKeep);
  e.Valid := True;
  e.Used := True;
  e.Gen := FOption.Generation;
  e.Sig := ASig;
  metas := nil;
  SetLength(metas, Length(ADims));
  q := 0;
  for k := 0 to High(ADims) do
  begin
    if ADims[k].Axis = nil then Continue;
    m := ADims[k].Axis.Categories;
    SetLength(e.MetaDim, q + 1);
    SetLength(e.MetaCollect, q + 1);
    SetLength(e.MetaDedup, q + 1);
    SetLength(e.MetaPre, q + 1);
    SetLength(e.MetaList, q + 1);
    e.MetaDim[q] := k;
    e.MetaCollect[q] := m.NeedCollect;
    e.MetaDedup[q] := m.Deduplication;
    if (k <= High(APre)) and (APre[k] >= 0) then e.MetaPre[q] := APre[k]
    else e.MetaPre[q] := m.Count;
    e.MetaList[q] := m.Snapshot;
    { the kept copy borrows nothing it could reach: the axes go with the
      build }
    metas[k] := nil;
    Inc(q);
  end;
  e.Store := st.CloneWith(metas);
  if ASlot >= Length(FStoreKeep) then SetLength(FStoreKeep, ASlot + 1);
  FreeAndNil(FStoreKeep[ASlot].Store);
  FStoreKeep[ASlot] := e;
end;
