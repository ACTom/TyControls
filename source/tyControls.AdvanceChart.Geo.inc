{ Part of tyControls.AdvanceChart (included, not a unit): the box layout reference, the
  geos and the map series (roam, selection, the regions' interaction, the tooltip), the
  calendars and the matrices. Moved out of the unit only to keep it readable; what the
  control is and why it is built the way it is, see the unit header. }

{ ==================== createBoxLayoutReference [Batch 151] ==================== }

function TTyAdvanceChart.CanvasXYWH: TTyXYWH;
begin
  Result := TyXYWHOfRect(FLastRect);
end;

{ the date a calendar's dataToPoint reads from `coord`: an array's first
  element (`isArray(data) && (data = data[0])`), a number or a string;
  anything else no date at all -- a cell of no position }
function CalendarCoordValue(AData: TJSONData): TTyDataValue;
begin
  Result := Default(TTyDataValue);
  if (AData <> nil) and (AData.JSONType = jtArray) then
  begin
    if AData.Count = 0 then Exit;
    AData := AData.Items[0];
  end;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := TyDataNum(AData.AsFloat);
    jtString:
      begin
        Result.Kind := dvkText;
        Result.Text := AData.AsString;
      end;
  end;
end;

{ the host's dataToLayout of ACoord, no clamp asked (a calendar's own
  default clamps): a matrix's rect -- it has no contentRect, so its cell's
  border is inside the reference -- or a calendar day's content rect;
  `contentRect || rect` }
function TTyAdvanceChart.HostRefAt(const ASys: string; AIndex: Integer;
  ACoord: TJSONData; out ARef: TTyXYWH): Boolean;
var
  loc: TTyMatrixLocRange;
  rc: TTyXYWH;
begin
  Result := False;
  ARef := TyXYWH(NaN, NaN, NaN, NaN);
  if ASys = TyMatrixSysName then
  begin
    if (AIndex < 0) or (AIndex > High(FMatrices)) or (FMatrices[AIndex] = nil) then Exit;
    TyMatrixLayoutJson(FMatrices[AIndex], ACoord, mclNone, ARef, loc);
    Result := True;
  end
  else if ASys = TyCalendarSysName then
  begin
    if (AIndex < 0) or (AIndex > High(FCalendars)) or (FCalendars[AIndex] = nil) then Exit;
    FCalendars[AIndex].DateLayoutXYWH(FCalendars[AIndex].ParseDate(
      CalendarCoordValue(ACoord)), True, rc, ARef);
    Result := True;
  end;
end;

{ A COMPONENT'S REFERENCE: decideCoordSysUsageKind for a component (a
  matrix or a calendar, usage 'box' unwritten), the host by its index or id
  (SINGLE_REFERRING: neither written is the first; one not there leaves the
  component on the canvas, as injectCoordSysByOption leaves it), and the
  host's dataToLayout of `coord` }
function TTyAdvanceChart.ComponentBoxRef(const AMain: string; AIndex: Integer;
  out ARef: TTyXYWH): Boolean;
var
  node, coord: TJSONData;
  sys: string;
  k: Integer;
begin
  ARef := CanvasXYWH;
  Result := False;
  if FOption = nil then Exit;
  node := FOption.ComponentAt(AMain, AIndex);
  if not (node is TJSONObject) then Exit;
  sys := TyComponentBoxSysOf(node);
  if sys = '' then Exit;
  if sys = TyMatrixSysName then
    k := TyResolveComponentRef(TJSONObject(node), 'matrixIndex', 'matrixId',
      FOption.ComponentCount(TyMatrixSysName), TyMainIds(FOption, TyMatrixSysName),
      TyMainHoles(FOption, TyMatrixSysName))
  else
    k := TyResolveComponentRef(TJSONObject(node), 'calendarIndex', 'calendarId',
      FOption.ComponentCount(TyCalendarSysName), TyMainIds(FOption, TyCalendarSysName),
      TyMainHoles(FOption, TyCalendarSysName));
  coord := TJSONObject(node).Find('coord');
  Result := HostRefAt(sys, k, coord, ARef);
  if not Result then ARef := CanvasXYWH;
end;

function TTyAdvanceChart.ComponentRefLocal(const AMain: string; AIndex: Integer;
  out ARef: TTyXYWH): Boolean;
begin
  Result := ComponentBoxRef(AMain, AIndex, ARef);
  ARef.X := ARef.X - FLastRect.Left;
  ARef.Y := ARef.Y - FLastRect.Top;
end;

function TTyAdvanceChart.ComponentRefCss(const AMain: string; AIndex: Integer;
  out ARef: TTyXYWH): Boolean;
var s: Double;
begin
  Result := ComponentRefLocal(AMain, AIndex, ARef);
  if FLastPPI > 0 then s := FLastPPI / 96 else s := 1;
  ARef.X := ARef.X / s;
  ARef.Y := ARef.Y / s;
  ARef.W := ARef.W / s;
  ARef.H := ARef.H / s;
end;

{ A SERIES' REFERENCE: getCoordForCoordSysUsageKindBox -- `coord` when
  written (not null), else (a pie's getCoord2) `center` -- in the host the
  binding found [Batch 147: a pie and a funnel in a matrix cell] }
function TTyAdvanceChart.SeriesBoxRef(ASlot: Integer; ACentre: Boolean;
  out ARef: TTyXYWH; out AFromCentre: Boolean): Boolean;
var
  node, d: TJSONData;
  sys: string;
  k: Integer;
begin
  ARef := CanvasXYWH;
  AFromCentre := False;
  Result := False;
  if (FOption = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FBindings[ASlot].MatrixBox and (FBindings[ASlot].MatrixIndex >= 0) then
  begin
    sys := TyMatrixSysName;
    k := FBindings[ASlot].MatrixIndex;
  end
  else if FBindings[ASlot].CalendarBoxIndex >= 0 then
  begin
    sys := TyCalendarSysName;
    k := FBindings[ASlot].CalendarBoxIndex;
  end
  else
    Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  d := nil;
  if node is TJSONObject then
  begin
    d := TJSONObject(node).Find('coord');
    if ((d = nil) or (d.JSONType = jtNull)) and ACentre then
    begin
      d := TJSONObject(node).Find('center');
      AFromCentre := True;
    end;
  end;
  if (d <> nil) and (d.JSONType = jtNull) then d := nil;
  Result := HostRefAt(sys, k, d, ARef);
  if not Result then
  begin
    ARef := CanvasXYWH;
    AFromCentre := False;
  end;
end;

function TTyAdvanceChart.MapSeriesBoxRef(ASeriesIndex: Integer;
  out ARef: TTyXYWH): Boolean;
var
  node, d, coord: TJSONData;
  sys: string;
  k: Integer;
begin
  ARef := CanvasXYWH;
  Result := False;
  if FOption = nil then Exit;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if not (node is TJSONObject) then Exit;
  d := TJSONObject(node).Find('coordinateSystem');
  if not ((d <> nil) and (d.JSONType = jtString)) then Exit;
  sys := d.AsString;
  if (sys <> TyMatrixSysName) and (sys <> TyCalendarSysName) then Exit;
  d := TJSONObject(node).Find('coordinateSystemUsage');
  if not ((d <> nil) and (d.JSONType = jtString) and (d.AsString = 'box')) then Exit;
  if sys = TyMatrixSysName then
    k := TyResolveComponentRef(TJSONObject(node), 'matrixIndex', 'matrixId',
      FOption.ComponentCount(TyMatrixSysName), TyMainIds(FOption, TyMatrixSysName),
      TyMainHoles(FOption, TyMatrixSysName))
  else
    k := TyResolveComponentRef(TJSONObject(node), 'calendarIndex', 'calendarId',
      FOption.ComponentCount(TyCalendarSysName), TyMainIds(FOption, TyCalendarSysName),
      TyMainHoles(FOption, TyCalendarSysName));
  coord := TJSONObject(node).Find('coord');
  if (coord <> nil) and (coord.JSONType = jtNull) then coord := nil;
  Result := HostRefAt(sys, k, coord, ARef);
  if not Result then ARef := CanvasXYWH;
end;

procedure TTyAdvanceChart.PlaceBoxedCoordSys;
var
  g, p: Integer;
  ref: TTyXYWH;
begin
  if FBuild <> nil then
    for g := 0 to FBuild.GridCount - 1 do
      if ComponentBoxRef('grid', FBuild.Grid(g).ComponentIndex, ref) then
        TyPlaceGridIn(FBuild, g, ref);
  for p := 0 to High(FPolars) do
    if (FPolars[p] <> nil) and ComponentBoxRef('polar', p, ref) then
    begin
      { a coord naming no cell: no position, far off the canvas (see
        TyBoxNowhere) }
      if not TyXYWHIsValid(ref) then
        ref := TyXYWH(TyBoxNowhere, TyBoxNowhere, TyBoxNowhereSize, TyBoxNowhereSize);
      TyPolarResize(FOption, FPolars[p], ref);
    end;
  { the single axes and the parallels, resized in their cells [Batch 154]
    -- before anything reads their pixel extents }
  for p := 0 to High(FSingles) do
    if (FSingles[p] <> nil) and ComponentBoxRef(TySingleCoordSysName, p, ref) then
      TySingleResizeIn(FOption, FSingles[p], ref);
  for p := 0 to High(FParallels) do
    if (FParallels[p] <> nil) and ComponentBoxRef('parallel', p, ref) then
      TyParallelResizeIn(FOption, FParallels[p], ref);
end;

procedure TTyAdvanceChart.FreeCalendars;
var i: Integer;
begin
  for i := 0 to High(FCalendars) do FreeAndNil(FCalendars[i]);
  FCalendars := nil;
end;

{ THE CALENDARS: each laid out on the whole canvas, as upstream's is -- its
  box is getLayoutRect against the chart's width and height, with no margin
  and nothing else shrinking it. [Batch 69] }
procedure TTyAdvanceChart.FreeGeos;
var i: Integer;
begin
  { [F6b] an SVG map's elements live on through a render (MapDraw keeps its
    graphic while the map stays): their flags, for the next geo of the slot }
  if Length(FSvgKeepGeo) < Length(FGeos) then SetLength(FSvgKeepGeo, Length(FGeos));
  for i := 0 to High(FGeos) do
    if FGeos[i] <> nil then FSvgKeepGeo[i] := FGeos[i].SvgSaveFlags;
  if Length(FSvgKeepMap) < Length(FMapGeos) then SetLength(FSvgKeepMap, Length(FMapGeos));
  for i := 0 to High(FMapGeos) do
    if FMapGeos[i] <> nil then FSvgKeepMap[i] := FMapGeos[i].SvgSaveFlags;
  for i := 0 to High(FGeos) do FreeAndNil(FGeos[i]);
  FGeos := nil;
  for i := 0 to High(FMapGeos) do FreeAndNil(FMapGeos[i]);
  FMapGeos := nil;
  FGeoDraws := nil;
  FMapSyms := nil;
end;

procedure TTyAdvanceChart.SolveGeos(APPI: Integer);
var
  i, n: Integer;
  ref: TTyXYWH;
  missing: TTyGeoMissingMapArray;
begin
  FreeGeos;
  { A MAP NOBODY REGISTERED draws an empty view, and upstream says so in its
    console; here the build says so [F1b] }
  if FBuild <> nil then
  begin
    missing := TyGeoUnregisteredMaps(FOption);
    for i := 0 to High(missing) do
      FBuild.Note(Format(rsTyChartMapNotRegistered,
        [missing[i].Path, missing[i].MapName]));
  end;
  n := 0;
  if FOption <> nil then n := FOption.ComponentCount('geo');
  { [Batch 148] a render makes new region elements: a hover found on the
    last ones is stale }
  Inc(FGeoGen);
  SetLength(FGeos, n);
  FGeoSvgMeas := nil;
  for i := 0 to n - 1 do
  begin
    FGeos[i] := TTyGeo.Create(FOption, i);
    FGeos[i].SvgMeasure := @GeoSvgMeasure;
    { [Batch 150] the model's option holds what a roam wrote back }
    if (i <= High(FGeoRoam)) and FGeoRoam[i].Valid then
      FGeos[i].SetRoamOption(FGeoRoam[i].Centre, FGeoRoam[i].Zoom);
    { resizeGeo in createBoxLayoutReference's container: a matrix cell or a
      calendar day for a geo in one [Batch 154] }
    if ComponentBoxRef('geo', i, ref) then FGeos[i].ResizeXYWH(ref, APPI)
    else FGeos[i].Resize(FLastRect, APPI);
    if i <= High(FSvgKeepGeo) then FGeos[i].SvgRestoreFlags(FSvgKeepGeo[i]);
    FGeos[i].Gen := FGeoGen;
    { GeoView.render's updateSelectStatus }
    GeoSyncSelected(i);
  end;
  { [Batch 152] the map series' geos and the data drawn with them }
  SolveMapGeos(APPI);
end;

{ THE GEO'S INK: the area and its rim from the skin's geo keys, the labels
  from the geo label key. Upstream's tokens are backgroundTint (a pale tint at
  half), border and tertiary. }
function TTyAdvanceChart.GeoInk: TTyGeoInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  Result := Default(TTyGeoInk);
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartGeoArea', '', []);
  Result.AreaFill := TTyChartColor(st.Background.Color);
  Result.Border := TTyChartColor(st.BorderColor);
  st := model.ResolveStyle('TyAdvChartGeoLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  Result.LabelFontName := st.FontName;
  Result.LabelFontSizeLogical := ResolveFontSize(st);
  Result.LabelFontWeight := st.FontWeight;
  { [Batch 148] emphasis and select: upstream's highlight and primary }
  st := model.ResolveStyle('TyAdvChartGeoArea', '', [tysHover]);
  Result.HighlightFill := TTyChartColor(st.Background.Color);
  st := model.ResolveStyle('TyAdvChartGeoLabel', '', [tysHover]);
  Result.LabelHighlight := TTyChartColor(st.TextColor);
  { [Batch 152] a map series' area: upstream's background token }
  st := model.ResolveStyle('TyAdvChartMapArea', '', []);
  Result.MapAreaFill := TTyChartColor(st.Background.Color);
end;

{ ==================== the geo regions' interaction [Batch 148] ====================

  GeoView and MapDraw's handlers over the pure TTyGeo: the region group is
  the highDownDispatcher of its paths and texts (toggleHoverEmphasis), its
  hover is handleGlobalMouseOverForHighDown with the component's own
  dispatchers -- a 'self' focus blurs the whole component first -- its out
  allLeaveBlur and the leave; a click dispatches geoToggleSelect, whatever
  selectedMode says (GeoModel.select asks it); the select actions run
  GeoModel.select / unSelect / toggleSelected on every geo their query
  names and update the select flags (updateSelectStatus); highlight and
  downplay with a geo finder go to findComponentHighDownDispatchers. The
  flags are applied in the frame, as the series' are (StApplyChanged). }

{ ==================== roam on the geos [Batch 150] ====================

  MapDraw's RoamController (updateRoamControllerSimply: roam false by
  default, roamTrigger, isInSelf containPoint, isInClip the view rect when
  it clips) and the geoRoam action (component/geo/install.ts). A press
  arms the first controller -- by zlevel, then z, a tie to the one added
  first, and a geo's is added before any series' -- that holds it and is
  not under an irrelevant element; every move then pans by the delta from
  the last point, wherever the pointer is; the wheel zooms by 1.1, 1.2 or
  1.4 about the pointer. Each is a geoRoam action: the view is synced back
  and worked out again, the picture is not rebuilt (__updateOnOwnRoam),
  and the static layer is drawn again in full. }

{ onIrrelevantElement: the topmost element under the pointer, a silent one
  too, belongs to another component with a coordinate system that stands
  above the geo -- its zlevel, then its z, higher }
function TTyAdvanceChart.GeoIrrelevant(AGeo, AX, AY: Integer): Boolean;
var
  idx, oi, si, slot, oz, ozl, diff: Integer;
  el: TTyChartElement;
  hasCoord: Boolean;
begin
  Result := False;
  if (FPaintList = nil) or not FPaintListValid then Exit;
  if (AGeo < 0) or (AGeo > High(FGeos)) or (FGeos[AGeo] = nil) then Exit;
  idx := FPaintList.TopElementAt(AX, AY, FPaintListPPI);
  if idx < 0 then Exit;
  el := FPaintList.Element(idx);
  if el.Datum.Kind = ctkGeo then
  begin
    { another geo: its own coordinate system, its own model }
    oi := el.Datum.ComponentIndex;
    if (oi = AGeo) or (oi < 0) or (oi > High(FGeos)) or (FGeos[oi] = nil) then Exit;
    oz := FGeos[oi].Spec.Z;
    ozl := FGeos[oi].Spec.ZLevel;
  end
  else if (el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex >= 0) then
  begin
    { a series on a coordinate system; one on this very geo has the geo
      for its coordinate system's model [Batch 152] }
    si := el.Datum.SeriesIndex;
    slot := SlotOfSeries(si);
    if (slot < 0) or (slot > High(FBindings)) then Exit;
    if (FBindings[slot].GeoIndex = AGeo)
      and (FBindings[slot].SeriesType <> TyMapSeriesTypeName) then Exit;
    hasCoord := (FBindings[slot].Cart <> nil) or (FBindings[slot].Polar <> nil)
      or (FBindings[slot].CalendarIndex >= 0) or (FBindings[slot].GeoIndex >= 0)
      or (FBindings[slot].SeriesType = TyMapSeriesTypeName)
      or (FBindings[slot].SeriesType = TyGraphSeriesTypeName)
      or (FBindings[slot].SeriesType = TyTreeSeriesTypeName)
      or (FBindings[slot].SeriesType = 'radar');
    if not hasCoord then Exit;
    if FBindings[slot].SeriesType = 'line' then oz := SeriesIntIn(si, 'z', 3)
    else oz := SeriesIntIn(si, 'z', 2);
    ozl := SeriesIntIn(si, 'zlevel', 0);
  end
  else
    Exit;
  { equal is relevant }
  diff := ozl - FGeos[AGeo].Spec.ZLevel;
  if diff = 0 then diff := oz - FGeos[AGeo].Spec.Z;
  Result := diff > 0;
end;

{ [Batch 152] the geo a roam host index names: a geo component's, or past
  cMapRoamBase a map series group's own }
function TTyAdvanceChart.RoamGeoOf(AIndex: Integer): TTyGeo;
begin
  Result := nil;
  if AIndex >= cMapRoamBase then
  begin
    if AIndex - cMapRoamBase <= High(FMapGeos) then Result := FMapGeos[AIndex - cMapRoamBase];
  end
  else if (AIndex >= 0) and (AIndex <= High(FGeos)) then Result := FGeos[AIndex];
end;

function TTyAdvanceChart.GeoRoamPick(AX, AY: Integer; AZoom: Boolean): Integer;
var
  i: Integer;
  g: TTyGeo;
  ok: Boolean;
begin
  Result := -1;
  if csDesigning in ComponentState then Exit;
  for i := 0 to High(FGeos) + Length(FMapGeos) do
  begin
    if i <= High(FGeos) then g := FGeos[i]
    else
    begin
      { a map series' own MapDraw: a group's main series draws it [Batch 152] }
      if (i - Length(FGeos) > High(FMapGroups))
        or (FMapGroups[i - Length(FGeos)].Main < 0) then Continue;
      g := FMapGeos[i - Length(FGeos)];
    end;
    { a geo that draws nothing has no MapDraw, so no controller }
    if (g = nil) or not g.Valid or not g.Spec.Show then Continue;
    if AZoom then ok := g.Spec.Roam in [grmZoom, grmBoth]
    else ok := g.Spec.Roam in [grmPan, grmBoth];
    if not ok then Continue;
    if not g.RoamPointerIn(AX, AY) then Continue;
    if (i <= High(FGeos)) and GeoIrrelevant(i, AX, AY) then Continue;
    { HIGHER zlevel, THEN HIGHER z; a tie to the first (z2 -Infinity on
      both sides makes the comparison NaN: the one added later goes after) }
    if (Result < 0) or (g.Spec.ZLevel > RoamGeoOf(Result).Spec.ZLevel)
      or ((g.Spec.ZLevel = RoamGeoOf(Result).Spec.ZLevel)
        and (g.Spec.Z > RoamGeoOf(Result).Spec.Z)) then
    begin
      if i <= High(FGeos) then Result := i
      else Result := cMapRoamBase + i - Length(FGeos);
    end;
  end;
end;

function TTyAdvanceChart.RoamTargetAt(AX, AY: Integer; AZoom: Boolean;
  out AGeo: Integer): Integer;
var gi, sz, szl: Integer;
begin
  AGeo := -1;
  Result := RoamSeriesAtZ(AX, AY, AZoom, sz, szl);
  gi := GeoRoamPick(AX, AY, AZoom);
  if gi < 0 then Exit;
  { the components render before the series: on a tie the geo's listener
    is the earlier one }
  if (Result < 0) or (RoamGeoOf(gi).Spec.ZLevel > szl)
    or ((RoamGeoOf(gi).Spec.ZLevel = szl) and (RoamGeoOf(gi).Spec.Z >= sz)) then
  begin
    AGeo := gi;
    Result := -1;
  end;
end;

{ updateRoamControllerSimply's dispatchAction: the type 'geoRoam', the
  pan's dx and dy or the zoom's zoom, originX and originY,
  payloadDisableAnimation's animation, componentType 'geo'
  (geoBackwardCompat) and the geo's id }
procedure TTyAdvanceChart.GeoGesture(AGeo: Integer; AHasPan: Boolean; ADX, ADY: Double;
  AHasZoom: Boolean; AScale, AOriginX, AOriginY: Double);
var p, anim: TJSONObject; g: Integer;
begin
  if FOption = nil then Exit;
  { a map series' own controller: componentType 'series' and its id
    [Batch 152] }
  if AGeo >= cMapRoamBase then
  begin
    g := AGeo - cMapRoamBase;
    if (g > High(FMapGroups)) or (FMapGroups[g].Main < 0) then Exit;
    p := TJSONObject.Create;
    p.Add('type', 'geoRoam');
    if AHasPan then
    begin
      p.Add('dx', ADX);
      p.Add('dy', ADY);
    end;
    if AHasZoom then
    begin
      p.Add('zoom', AScale);
      p.Add('originX', AOriginX);
      p.Add('originY', AOriginY);
    end;
    anim := TJSONObject.Create;
    anim.Add('duration', 0);
    p.Add('animation', anim);
    p.Add('componentType', 'series');
    p.Add('seriesId', FOption.ComponentId('series', FBindings[FMapGroups[g].Main].SeriesIndex));
    DispatchActionObject(p);
    Exit;
  end;
  if (AGeo < 0) or (AGeo >= FOption.ComponentCount('geo')) then Exit;
  p := TJSONObject.Create;
  p.Add('type', 'geoRoam');
  if AHasPan then
  begin
    p.Add('dx', ADX);
    p.Add('dy', ADY);
  end;
  if AHasZoom then
  begin
    p.Add('zoom', AScale);
    p.Add('originX', AOriginX);
    p.Add('originY', AOriginY);
  end;
  anim := TJSONObject.Create;
  anim.Add('duration', 0);
  p.Add('animation', anim);
  p.Add('componentType', 'geo');
  p.Add('geoId', FOption.ComponentId('geo', AGeo));
  { api.dispatchAction: the payload is the dispatch's (freed there) }
  DispatchActionObject(p);
end;

{ RoamController._mousemoveHandler while a left press holds it: nothing
  while globalPan is taken (the last point stays where it was), else the
  delta from the last point }
procedure TTyAdvanceChart.GeoRoamMove(AX, AY: Integer);
var dx, dy: Double;
begin
  if FRoamGeo < 0 then Exit;
  if PanTaken then Exit;
  dx := AX - FRoamX;
  dy := AY - FRoamY;
  FRoamX := AX;
  FRoamY := AY;
  GeoGesture(FRoamGeo, True, dx, dy, False, 0, 0, 0);
end;

{ the geoRoam action: the main type is the payload's componentType, else
  'geo' where a geo key is written, else the map series' ([Batch 152] the
  map series' own geos: DoMapRoamAction);
  each queried geo is synced back and laid out again from what that wrote
  (ownRoamModelCoordSysUpdateInAction), and its view moves without a
  rebuild (ownRoamViewUpdateDirectlyInAction, which also gives the
  payload its animation); the event is the payload as it then stands,
  'georoam' }
function TTyAdvanceChart.DoGeoRoamAction(APayload: TJSONObject): Boolean;
var
  ct, d: TJSONData;
  mainType: string;
  geos: TTyIntegerArray;
  k, gi, n: Integer;
  hasPan, hasZoom, reached, ok, dep: Boolean;
  dx, dy, z, ox, oy, zw: Double;
  c: TTyGraphCentre;
  ev, anim: TJSONObject;

  function Written(const AKey: string): Boolean;
  var x: TJSONData;
  begin
    x := APayload.Find(AKey);
    Result := (x <> nil) and (x.JSONType <> jtNull);
  end;

  function Num(const AKey: string; out AV: Double): Boolean;
  var x: TJSONData;
  begin
    x := APayload.Find(AKey);
    Result := (x <> nil) and (x.JSONType = jtNumber);
    if Result then AV := x.AsFloat else AV := NaN;
  end;

begin
  Result := True;
  FGeoRoamHits := 0;
  reached := False;
  ct := APayload.Find('componentType');
  if JsTruthy(ct) then mainType := TyJsonJsString(ct)
  else if Written('geoId') or Written('geoName') or Written('geoIndex') then mainType := 'geo'
  else mainType := 'series';
  { the map series' own geos [Batch 152] }
  if (mainType = 'series') and (FOption <> nil) then DoMapRoamAction(APayload, reached);
  if (mainType = 'geo') and (FOption <> nil) then
  begin
    hasPan := Num('dx', dx) and Num('dy', dy);
    hasZoom := Num('zoom', z);
    Num('originX', ox);
    Num('originY', oy);
    { NOT TAKEN: a zoom that is not a positive finite number, or about a
      point that is not finite (upstream turns the view NaN or mirrors it) }
    ok := not (hasZoom and (IsNan(z) or IsInfinite(z) or (z <= 0)
      or IsNan(ox) or IsInfinite(ox) or IsNan(oy) or IsInfinite(oy)));
    geos := GeoMatch(APayload);
    n := FOption.ComponentCount('geo');
    for k := 0 to High(geos) do
    begin
      gi := geos[k];
      if (gi < 0) or (gi >= n) then Continue;
      reached := True;
      if not ok or (gi > High(FGeos)) or (FGeos[gi] = nil) then Continue;
      if not FGeos[gi].RoamBy(hasPan, dx, dy, hasZoom, z, ox, oy, c, zw) then Continue;
      if Length(FGeoRoam) <= gi then SetLength(FGeoRoam, gi + 1);
      FGeoRoam[gi].Valid := True;
      FGeoRoam[gi].Centre := c;
      FGeoRoam[gi].Zoom := zw;
      Inc(FGeoRoamHits);
    end;
  end;
  if FGeoRoamHits > 0 then
  begin
    { A NEW PICTURE, NOT A NEW LAYOUT: the geos keep their elements and
      their states. The standing list takes each moved geo's elements again
      in place -- the next pointer event finds what is under it now, as
      zrender's finds the moved elements -- and the static layer is drawn
      again in full (the dirty-rect path does not take a roam) }
    for k := 0 to High(geos) do
      if (geos[k] >= 0) and (geos[k] <= High(FGeos)) and (FGeos[geos[k]] <> nil) then
        GeoPatchList(geos[k]);
    { updateTransform [Batch 152, D14 GE4]: a series on a moved geo is laid
      out again (scatter, effectScatter and lines in place; the rest
      rendered again, renderItem too), and the list built anew -- the
      records of the states stay, as upstream's elements keep theirs }
    dep := False;
    for k := 0 to High(geos) do
      if (geos[k] >= 0) and (geos[k] <= High(FGeos)) and (FGeos[geos[k]] <> nil)
        and GeoRoamHasDependents(FGeos[geos[k]]) then dep := True;
    if dep then
    begin
      GeoDependentsRelayout;
      DropStatic;
      { at once, as upstream renders in the dispatch: the next pointer
        event finds the series where the roam put them }
      if FLastPPI > 0 then BuildSeriesList(NewTextMeasurer(FLastPPI), FLastPPI);
    end;
    StaticDrop;
    FProgReuse := False;
    FZrDirty := True;
    inherited Invalidate;
  end;
  { the event: the payload, its animation where a geo was reached (in
    place when the gesture wrote one), its type the event's }
  ev := TJSONObject(APayload.Clone);
  try
    if reached then
    begin
      anim := TJSONObject.Create;
      anim.Add('duration', 0);
      d := ev.Find('animation');
      if d <> nil then ev.Elements['animation'] := anim
      else ev.Add('animation', anim);
    end;
    ev.Strings['type'] := 'georoam';
    EmitPayloadEvent('georoam', TyGeoJsJson(ev), ev);
  finally
    ev.Free;
  end;
end;

{ the geo's elements of the standing list built again on its kept picture
  (no states applied: the frame does that) and put back where they stand;
  a list that cannot take them is dropped }
procedure TTyAdvanceChart.DoMapRoamAction(APayload: TJSONObject; var AReached: Boolean);
var
  idx: TTyIntegerArray;
  k, slot, g, r, si, raw: Integer;
  hasPan, hasZoom, ok, own, moved: Boolean;
  dx, dy, z, ox, oy, zw: Double;
  c: TTyGraphCentre;
  ct, sid: TJSONData;

  function Num(const AKey: string; out AV: Double): Boolean;
  var x: TJSONData;
  begin
    x := APayload.Find(AKey);
    Result := (x <> nil) and (x.JSONType = jtNumber);
    if Result then AV := x.AsFloat else AV := NaN;
  end;

begin
  hasPan := Num('dx', dx) and Num('dy', dy);
  hasZoom := Num('zoom', z);
  Num('originX', ox);
  Num('originY', oy);
  ok := not (hasZoom and (IsNan(z) or IsInfinite(z) or (z <= 0)
    or IsNan(ox) or IsInfinite(ox) or IsNan(oy) or IsInfinite(oy)));
  moved := False;
  { makeQueryConditionKindA over the map series, those that draw the map }
  idx := MatchSeries(APayload);
  for k := 0 to High(idx) do
  begin
    slot := SlotOfSeries(idx[k]);
    if (slot < 0) or (FBindings[slot].SeriesType <> TyMapSeriesTypeName) then Continue;
    if (slot > High(FMapGroupOf)) or (FMapGroupOf[slot] < 0) then Continue;
    g := FMapGroupOf[slot];
    if not FMapGroups[g].Own or (FMapGroups[g].Main <> slot) then Continue;
    if (g > High(FMapGeos)) or (FMapGeos[g] = nil) then Continue;
    AReached := True;
    if not ok then Continue;
    if not FMapGeos[g].RoamBy(hasPan, dx, dy, hasZoom, z, ox, oy, c, zw) then Continue;
    { the write-back, synced over the group's series }
    r := -1;
    for si := 0 to High(FMapRoam) do
      if FMapRoam[si].Key = FMapGroups[g].Key then r := si;
    if r < 0 then
    begin
      r := Length(FMapRoam);
      SetLength(FMapRoam, r + 1);
      FMapRoam[r].Key := FMapGroups[g].Key;
    end;
    FMapRoam[r].State.Valid := True;
    FMapRoam[r].State.Centre := c;
    FMapRoam[r].State.Zoom := zw;
    moved := True;
    { MapView.render: a roam that is not the series' own (componentType
      'series' and its id) draws the map again -- new region groups, no
      hover }
    ct := APayload.Find('componentType');
    sid := APayload.Find('seriesId');
    own := (ct <> nil) and (ct.JSONType = jtString) and (ct.AsString = 'series')
      and (sid <> nil) and (sid.JSONType in [jtString, jtNumber])
      and (sid.AsString = FOption.ComponentId('series', FBindings[slot].SeriesIndex));
    if not own and (FBindings[slot].SeriesIndex <= High(FSt)) then
      for raw := 0 to High(FSt[FBindings[slot].SeriesIndex].Rows) do
      begin
        FSt[FBindings[slot].SeriesIndex].Rows[raw].Host.HoverState := TyStHoverNormal;
        FSt[FBindings[slot].SeriesIndex].Rows[raw].Host.HighByOuter := 0;
      end;
  end;
  if moved then
  begin
    GeoDependentsRelayout;
    DropStatic;
    FStDirty := True;
    if FLastPPI > 0 then BuildSeriesList(NewTextMeasurer(FLastPPI), FLastPPI);
    StaticDrop;
    FProgReuse := False;
    FZrDirty := True;
    inherited Invalidate;
  end;
end;

procedure TTyAdvanceChart.GeoPatchList(AGeo: Integer);
var
  tmp: TTyPaintList;
  idx: TTyIntegerArray;
  i, n: Integer;
  el: TTyChartElement;
begin
  if (FPaintList = nil) or not FPaintListValid then Exit;
  if (AGeo < 0) or (AGeo > High(FGeos)) or (FGeos[AGeo] = nil)
    or not FGeos[AGeo].ItemsReady then
  begin
    DropStatic;
    Exit;
  end;
  idx := nil;
  if FGeos[AGeo].IsSvg then
  begin
    { [F6b] an SVG map's elements are not all the geo's datum (the unnamed
      ones carry none, a map series' its rows): where the build put them }
    for i := 0 to High(FGeoDraws) do
      if (FGeoDraws[i].Geo = FGeos[AGeo]) and (FGeoDraws[i].Start >= 0)
        and (FGeoDraws[i].Start + FGeoDraws[i].Count <= FPaintList.Count) then
      begin
        SetLength(idx, FGeoDraws[i].Count);
        for n := 0 to FGeoDraws[i].Count - 1 do idx[n] := FGeoDraws[i].Start + n;
        Break;
      end;
  end
  else
  for i := 0 to FPaintList.Count - 1 do
  begin
    el := FPaintList.Element(i);
    if (el.Datum.Kind = ctkGeo) and (el.Datum.ComponentIndex = AGeo) then
    begin
      SetLength(idx, Length(idx) + 1);
      idx[High(idx)] := i;
    end;
  end;
  tmp := TTyPaintList.Create;
  try
    n := TyBuildGeo(FGeos[AGeo], GeoInk, NewTextMeasurer(FPaintListPPI),
      FPaintListPPI, tmp, False);
    if n <> Length(idx) then
    begin
      DropStatic;
      Exit;
    end;
    for i := 0 to n - 1 do FPaintList.SetElement(idx[i], tmp.Element(i));
  finally
    tmp.Free;
  end;
end;

{ ==================== [Batch 152, D14 GE4] series on a geo ====================

  A series on a geo is laid out through the geo's dataToPoint -- the projection
  and the overall matrix, the roam in it -- so its points move with every roam
  (updateTransform). Upstream lays a scatter, an effectScatter and the lines
  out again in place and renders every other series again; here the solvers a
  geo's view feeds run again and the list is built anew, the state records
  kept (renderSeries' clearStates and the prevStates it restores). }

function TTyAdvanceChart.GeoOfSlot(ASlot: Integer): TTyGeo;
var gi: Integer;
begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  gi := FBindings[ASlot].GeoIndex;
  if (gi >= 0) and (gi <= High(FGeos)) then Result := FGeos[gi];
  if (Result <> nil) and not Result.Valid then Result := nil;
end;

function TTyAdvanceChart.GeoSeriesPoints(ASlot: Integer): TTyPointFArray;
var
  geo: TTyGeo;
  st: TTyDataStore;
  i, cx, cy: Integer;
  p: TTyPointF;
  clip: Boolean;
  r: TTyXYWH;
  tol: Double;
  node, d: TJSONData;
  mask: TFPUExceptionMask;
begin
  Result := nil;
  geo := GeoOfSlot(ASlot);
  if (geo = nil) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  cx := st.DimIndexOf(TyGeoLngDim);
  cy := st.DimIndexOf(TyGeoLatDim);
  SetLength(Result, st.Count);
  { createCoordSysClipAreaSimply: the series' own clip (true by default for
    a scatter and an effectScatter) and the geo's shouldClip, the area the
    view rect grown by 0.1 }
  clip := True;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if node is TJSONObject then
  begin
    d := TJSONObject(node).Find('clip');
    if d <> nil then clip := JsTruthy(d);
  end;
  clip := clip and geo.Spec.Clip;
  r := geo.ViewRect;
  tol := 0.1 * FLastPPI / 96;
  mask := GeoMaskFpu;
  try
    for i := 0 to st.Count - 1 do
    begin
      Result[i].X := NaN;
      Result[i].Y := NaN;
      if (cx < 0) or (cy < 0) then Continue;
      if not geo.PointOf(st.Get(cx, i), st.Get(cy, i), p) then Continue;
      if IsNan(p.X) or IsNan(p.Y) then Continue;
      { BoundingRect.contain, both edges in }
      if clip and not ((p.X >= r.X - tol) and (p.X <= r.X - tol + (r.W + 2 * tol))
        and (p.Y >= r.Y - tol) and (p.Y <= r.Y - tol + (r.H + 2 * tol))) then Continue;
      Result[i] := p;
    end;
  finally
    GeoUnmaskFpu(mask);
  end;
end;

function TTyAdvanceChart.BuildGeoHeatmap(ASlot: Integer; AList: TTyPaintList): Integer;
var
  geo: TTyGeo;
  st: TTyDataStore;
  si, k, vm, i, cx, cy, cv, n, pIdx, z: Integer;
  node, d: TJSONData;
  sid, key: string;
  spec: TTyVisualMapSpec;
  pointSize, blurSize, minOp, maxOp, scale, x, y, x2, y2, w, h, val, al, cw, ch: Double;
  rr: TTyXYWH;
  pts: TTyHeatPointArray;
  p: TTyPointF;
  gin, gout: TTyHeatGradient;
  rng: TTyHeatRange;
  lay: TTyHeatLayer;
  lo, hi: array of Double;
  sel: array of Boolean;
  bmp: TBGRABitmap;
  px: PBGRAPixel;
  el: TTyChartElement;
  hash: QWord;
  mask: TFPUExceptionMask;

  function Num(const AKey: string; ADefault: Double): Double;
  var x0: TJSONData;
  begin
    Result := ADefault;
    if not (node is TJSONObject) then Exit;
    x0 := TJSONObject(node).Find(AKey);
    if (x0 <> nil) and (x0.JSONType = jtNumber) then Result := x0.AsFloat;
  end;

  function ColorsOf(AState: TTyVisualState): TTyVisualColorArray;
  var q: Integer;
  begin
    Result := nil;
    for q := 0 to High(spec.States[AState]) do
      if spec.States[AState][q].Kind = 'color' then Exit(spec.States[AState][q].Colors);
  end;

begin
  Result := 0;
  if Length(FHeatLayers) < Length(FBindings) then SetLength(FHeatLayers, Length(FBindings));
  FHeatLayers[ASlot] := Default(TTyHeatLayer);
  geo := GeoOfSlot(ASlot);
  if (geo = nil) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  si := FBindings[ASlot].SeriesIndex;
  node := FOption.ComponentAt('series', si);
  { the visualMap of the series: the last one targeting it (upstream throws
    without one) }
  sid := '';
  if node is TJSONObject then
  begin
    d := TJSONObject(node).Find('id');
    if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then sid := d.AsString;
  end;
  vm := -1;
  for k := 0 to High(FVisualSpecs) do
    if TyVisualMapTargets(FVisualSpecs[k], si, sid) then vm := k;
  if vm < 0 then Exit;
  spec := FVisualSpecs[vm];
  pointSize := Num('pointSize', 20);
  blurSize := Num('blurSize', 30);
  minOp := Num('minOpacity', 0);
  maxOp := Num('maxOpacity', 1);
  if FLastPPI > 0 then scale := FLastPPI / 96 else scale := 1;
  lay := Default(TTyHeatLayer);
  mask := GeoMaskFpu;
  try
    { the view rect through the roam, on the viewport, in CSS px }
    rr := geo.RoamViewRect;
    cw := (FLastRect.Right - FLastRect.Left) / scale;
    ch := (FLastRect.Bottom - FLastRect.Top) / scale;
    x := Max(rr.X / scale, 0);
    y := Max(rr.Y / scale, 0);
    x2 := Min(rr.W / scale + rr.X / scale, cw);
    y2 := Min(rr.H / scale + rr.Y / scale, ch);
    w := x2 - x;
    h := y2 - y;
    cx := st.DimIndexOf(TyGeoLngDim);
    cy := st.DimIndexOf(TyGeoLatDim);
    cv := st.DimIndexOf(TyPieValueDim);
    SetLength(pts, st.Count);
    for i := 0 to st.Count - 1 do
    begin
      pts[i].X := NaN;
      pts[i].Y := NaN;
      pts[i].Alpha := NaN;
      if (cx < 0) or (cy < 0) or (cv < 0) then Continue;
      if geo.PointOf(st.Get(cx, i), st.Get(cy, i), p) then
      begin
        pts[i].X := p.X / scale - x;
        pts[i].Y := p.Y / scale - y;
      end;
      { the in-range colour's normalizer: linear over the extent, or the
        piece index over the pieces }
      val := st.Get(cv, i);
      if spec.SubType = 'piecewise' then
      begin
        pIdx := TyVisualFindPiece(spec.Pieces, val, TyJsNumberToString(val), True);
        if pIdx >= 0 then al := TyVmLinearMap(pIdx, 0, Length(spec.Pieces) - 1, 0, 1, True)
        else al := NaN;
      end
      else
        al := TyVmLinearMap(val, spec.Extent0, spec.Extent1, 0, 1, True);
      pts[i].Alpha := al;
    end;
    lay.Valid := True;
    lay.X := x;
    lay.Y := y;
    lay.W := w;
    lay.H := h;
    { the canvas' width and height attributes: whole pixels }
    if w > 0 then lay.PixW := Trunc(w) else lay.PixW := 0;
    if h > 0 then lay.PixH := Trunc(h) else lay.PixH := 0;
    SetLength(lay.DrawX, Length(pts));
    SetLength(lay.DrawY, Length(pts));
    SetLength(lay.DrawAlpha, Length(pts));
    for i := 0 to High(pts) do
    begin
      lay.DrawX[i] := pts[i].X - (pointSize + blurSize);
      lay.DrawY[i] := pts[i].Y - (pointSize + blurSize);
      lay.DrawAlpha[i] := pts[i].Alpha;
    end;
    gin := TyHeatGradientOf(ColorsOf(tvsInRange));
    gout := TyHeatGradientOf(ColorsOf(tvsOutOfRange));
    if spec.SubType = 'piecewise' then
    begin
      SetLength(lo, Length(spec.Pieces));
      SetLength(hi, Length(spec.Pieces));
      SetLength(sel, Length(spec.Pieces));
      for k := 0 to High(spec.Pieces) do
      begin
        lo[k] := spec.Pieces[k].Lo;
        hi[k] := spec.Pieces[k].Hi;
        sel[k] := (k <= High(spec.Selected)) and spec.Selected[k];
      end;
      rng := TyHeatPiecewiseRange(spec.Extent0, spec.Extent1, lo, hi, sel);
    end
    else if spec.RangeAuto then
      rng := TyHeatContinuousRange(spec.Extent0, spec.Extent1, spec.Extent0, spec.Extent1)
    else
      rng := TyHeatContinuousRange(spec.Extent0, spec.Extent1, spec.Range0, spec.Range1);
    if (lay.PixW > 0) and (lay.PixH > 0) then
      lay.Bytes := TyHeatRender(pts, lay.PixW, lay.PixH, pointSize, blurSize, minOp, maxOp,
        gin, gout, rng);
  finally
    GeoUnmaskFpu(mask);
  end;
  FHeatLayers[ASlot] := lay;
  if (lay.PixW <= 0) or (lay.PixH <= 0) or (Length(lay.Bytes) = 0) then Exit;
  { the image: the bytes under a key of their own (FNV-1a over them) }
  hash := QWord($cbf29ce484222325);
  for k := 0 to High(lay.Bytes) do
    hash := (hash xor lay.Bytes[k]) * QWord($100000001b3);
  key := Format('data:image/x-ty-heatmap;base64,%dx%d-%s', [lay.PixW, lay.PixH,
    IntToHex(hash, 16)]);
  bmp := TBGRABitmap.Create(lay.PixW, lay.PixH);
  n := 0;
  for i := 0 to lay.PixH - 1 do
  begin
    px := bmp.ScanLine[i];
    for k := 0 to lay.PixW - 1 do
    begin
      px^.red := lay.Bytes[n];
      px^.green := lay.Bytes[n + 1];
      px^.blue := lay.Bytes[n + 2];
      px^.alpha := lay.Bytes[n + 3];
      Inc(px);
      Inc(n, 4);
    end;
  end;
  bmp.InvalidateBitmap;
  TyPatternRegisterImage(key, bmp);
  z := SeriesIntIn(si, 'z', 2);
  el := TyChartElement(TyShapeRect(TyRectF(lay.X * scale, lay.Y * scale,
    (lay.X + lay.W) * scale, (lay.Y + lay.H) * scale)));
  el.Style.HasFill := True;
  el.Style.FillColor := 0;
  el.Style.FillPattern.Present := True;
  el.Style.FillPattern.Image := key;
  el.Style.FillPattern.Repetition := 'no-repeat';
  el.Style.FillPattern.HasMatrix := True;
  el.Style.FillPattern.UnitImage := True;
  el.Style.FillPattern.Matrix[0] := lay.W;
  el.Style.FillPattern.Matrix[1] := 0;
  el.Style.FillPattern.Matrix[2] := 0;
  el.Style.FillPattern.Matrix[3] := lay.H;
  el.Style.FillPattern.Matrix[4] := lay.X;
  el.Style.FillPattern.Matrix[5] := lay.Y;
  el.Silent := True;
  el.Z := z;
  el.Z2 := 0;
  el.Datum := TyChartNoDatum;
  AList.Add(el);
  Result := 1;
end;

function TTyAdvanceChart.GeoHeatLayer(ASeriesIndex: Integer; out ALayer: TTyHeatLayer): Boolean;
var slot: Integer;
begin
  ALayer := Default(TTyHeatLayer);
  slot := SlotOfSeries(ASeriesIndex);
  Result := (slot >= 0) and (slot <= High(FHeatLayers)) and FHeatLayers[slot].Valid;
  if Result then ALayer := FHeatLayers[slot];
end;

function TTyAdvanceChart.GeoBrushLayouts(ASlot: Integer): TTyBrushItemLayoutArray;
var
  geo: TTyGeo;
  st: TTyDataStore;
  i, cx, cy: Integer;
  p: TTyPointF;
begin
  Result := nil;
  geo := GeoOfSlot(ASlot);
  if (geo = nil) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  if (FBindings[ASlot].SeriesType <> 'scatter') and (FBindings[ASlot].SeriesType <> 'effectScatter') then Exit;
  st := FStores[ASlot];
  cx := st.DimIndexOf(TyGeoLngDim);
  cy := st.DimIndexOf(TyGeoLatDim);
  SetLength(Result, st.Count);
  for i := 0 to st.Count - 1 do
  begin
    Result[i] := Default(TTyBrushItemLayout);
    Result[i].Kind := blkPoint;
    Result[i].X := NaN;
    Result[i].Y := NaN;
    if (cx < 0) or (cy < 0) then Continue;
    if geo.PointOf(st.Get(cx, i), st.Get(cy, i), p) then
    begin
      Result[i].X := p.X;
      Result[i].Y := p.Y;
    end;
  end;
end;

function TTyAdvanceChart.GeoPointOfJson(AGeo: TTyGeo; AValue: TJSONData;
  out APt: TTyPointF): Boolean;
var x, y: Double;
begin
  APt.X := NaN;
  APt.Y := NaN;
  Result := False;
  if (AGeo = nil) or (AValue = nil) then Exit;
  if AValue.JSONType = jtString then Exit(AGeo.PointOfName(AValue.AsString, APt));
  if AValue.JSONType <> jtArray then Exit;
  if AValue.Count > 0 then x := TyJsonToNumber(TJSONArray(AValue).Items[0]) else x := NaN;
  if AValue.Count > 1 then y := TyJsonToNumber(TJSONArray(AValue).Items[1]) else y := NaN;
  Result := AGeo.PointOf(x, y, APt);
end;

function TTyAdvanceChart.BoxPointOf(ASlot: Integer; out APt: TTyPointF): Boolean;
var
  node, d: TJSONData;
  cv: TTyConvertResult;
begin
  APt := TyPointF(NaN, NaN);
  Result := False;
  if (FOption = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  d := nil;
  if node is TJSONObject then
  begin
    d := TJSONObject(node).Find('coord');
    if ((d = nil) or (d.JSONType = jtNull))
      and (FBindings[ASlot].SeriesType = TyPieSeriesTypeName) then
      d := TJSONObject(node).Find('center');
  end;
  if (d <> nil) and (d.JSONType = jtNull) then d := nil;
  if FBindings[ASlot].BoxCart <> nil then
  begin
    if d = nil then Exit;
    cv := TyCartesianToPixel(FBindings[ASlot].BoxCart, d);
    if (cv.Kind <> cvkArray) or (Length(cv.Values) < 2) then Exit;
    APt := TyPointF(cv.Values[0], cv.Values[1]);
  end
  else if not GeoPointOfJson(GeoOfSlot(ASlot), d, APt) then
    Exit;
  Result := not (IsNan(APt.X) or IsNan(APt.Y));
end;

function TTyAdvanceChart.GeoPieLayout(ASlot, ADim: Integer): TTyPieLayout;
var
  p: TTyPointF;
  k: Integer;
begin
  { getLayoutRect(the box, the chart): the radius' reference }
  Result := TyPieLayoutOf(FPieSpecs[ASlot], FLastRect, FStores[ASlot], ADim);
  { the default centre ['50%', '50%'] read as a coordinate is no point
    [Batch 154: a cartesian's point too] }
  if not BoxPointOf(ASlot, p) then
  begin
    Result.Valid := False;
    Exit;
  end;
  Result.CX := p.X;
  Result.CY := p.Y;
  for k := 0 to High(Result.Sectors) do
  begin
    Result.Sectors[k].CX := p.X;
    Result.Sectors[k].CY := p.Y;
  end;
end;

function TTyAdvanceChart.GeoRoamHasDependents(AGeo: TTyGeo): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].SeriesType = TyCustomSeriesType then Exit(True);
    if (FBindings[i].GeoIndex >= 0) and (FBindings[i].GeoIndex <= High(FGeos))
      and (FGeos[FBindings[i].GeoIndex] = AGeo) then Exit(True);
  end;
end;

procedure TTyAdvanceChart.GeoDependentsRelayout;
var ppi, i: Integer;
begin
  ppi := FLastPPI;
  if ppi <= 0 then ppi := 96;
  SolvePies;
  SolveLines(ppi);
  SolveCustom(ppi);
  for i := 0 to High(FBindings) do
    if (FBindings[i].SeriesType = TyGraphSeriesTypeName) and (FBindings[i].GeoIndex >= 0) then
      SolveGeoGraph(i);
  { a chord centred on a geo's point [Batch 154] }
  for i := 0 to High(FBindings) do
    if (FBindings[i].SeriesType = TyChordSeriesTypeName) and FBindings[i].BoxPoint
      and (FBindings[i].GeoIndex >= 0) then
    begin
      SolveChords(ppi);
      Break;
    end;
end;

function TTyAdvanceChart.GeoGraphPoints(ASeriesIndex: Integer; AGeo: TTyGeo): TTyPointFArray;
var
  node, d, it, v: TJSONData;
  k: Integer;
  x, y: Double;
  p: TTyPointF;

  function NumOf(AData: TJSONData): Double;
  begin
    Result := NaN;
    if AData = nil then Exit;
    case AData.JSONType of
      jtNumber: Result := AData.AsFloat;
      jtString:
        if (AData.AsString <> '') and (AData.AsString <> '-') then
          Result := TyJsToNumber(AData.AsString);
    end;
  end;

begin
  Result := nil;
  if AGeo = nil then Exit;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if not (node is TJSONObject) then Exit;
  d := TJSONObject(node).Find('data');
  if not (d is TJSONArray) then d := TJSONObject(node).Find('nodes');
  if not (d is TJSONArray) then Exit;
  SetLength(Result, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    Result[k] := TyPointF(NaN, NaN);
    it := d.Items[k];
    v := it;
    if v is TJSONObject then v := TJSONObject(v).Find('value');
    if not (v is TJSONArray) then Continue;
    if v.Count > 0 then x := NumOf(v.Items[0]) else x := NaN;
    if v.Count > 1 then y := NumOf(v.Items[1]) else y := NaN;
    { simpleLayout: one number is enough to lay a node out -- and a pair
      with a NaN in it is no point }
    if IsNan(x) and IsNan(y) then Continue;
    if AGeo.PointOf(x, y, p) then Result[k] := p;
  end;
end;

procedure TTyAdvanceChart.SolveGeoGraph(ASlot: Integer);
var
  solved: TTyGraphSolved;
  geo: TTyGeo;
  si: Integer;
begin
  if (ASlot > High(FGraphLaidOut)) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  geo := GeoOfSlot(ASlot);
  if geo = nil then Exit;
  si := FBindings[ASlot].SeriesIndex;
  solved := TyGraphSolveAtPoints(FOption, si, FStores[ASlot], GeoGraphPoints(si, geo));
  FGraphLaidOut[ASlot] := True;
  FGraphSpecs[ASlot] := solved.Spec;
  FGraphNodes[ASlot] := solved.Nodes;
  FGraphEdges[ASlot] := solved.Edges;
  FGraphCats[ASlot] := solved.Cats;
end;

{ ==================== [Batch 152, D14 GE4] the map series ====================

  MapSeries.getInitialData fills a series' data with a row for every region
  its map has and its data does not name; buildAllMapSeriesGroups puts the
  map series that share a geo component -- or, with none, a `map` -- into one
  group, and mapDataStatistic gives every series the group's statistic over
  the series the legend left (sum, average, max or min of the first one's
  mapValueCalculation), each row the main series'. The original data stays
  for the legend symbols and the tooltip's names (FMapOrig); FStores holds
  the statistic, which is what the visual stage, the labels, the tooltip and
  the selection read.

  A group with no geo component has a geo of its own, laid out from the
  first map series declared; its main series (the first the legend left)
  draws the map -- MapDraw with the series' data -- and every series of it
  its legend symbols. A geo component a map series names draws the regions
  with the first such series' data. Either way a region group is the item's
  graphic element: its events, its tooltip and its states are the series'
  (sskMap rows), and the geo takes the rows' flags for its paths. }

function TTyAdvanceChart.MapTypeOf(ASlot: Integer): string;
var node, d: TJSONData;
begin
  Result := '';
  if (FOption = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FBindings[ASlot].GeoIndex >= 0 then
    node := FOption.ComponentAt('geo', FBindings[ASlot].GeoIndex)
  else
    node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (node is TJSONObject) then Exit;
  d := TJSONObject(node).Find('map');
  if (d <> nil) and (d.JSONType <> jtNull) then Result := TyJsonJsString(d);
end;

procedure TTyAdvanceChart.MapFillStore(ASlot: Integer; AStore: TTyDataStore);
var
  dims: TTySeriesDimArray;
  node, d: TJSONData;
  nameMap: TJSONObject;
  nameProp, nm: string;
  src: TTyGeoSource;
  i, k, n0, r: Integer;
  found: Boolean;
begin
  AStore.AddDimension(TyPieValueDim, ddtFloat);
  SetLength(dims, 1);
  dims[0] := Default(TTySeriesDim);
  dims[0].Name := TyPieValueDim;
  dims[0].Kind := ddtFloat;
  TyFillSeriesStore(FOption, ASlot, dims, AStore);
  node := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (node is TJSONObject) then Exit;
  nameMap := nil;
  d := TJSONObject(node).Find('nameMap');
  if d is TJSONObject then nameMap := TJSONObject(d);
  nameProp := 'name';
  d := TJSONObject(node).Find('nameProperty');
  if (d <> nil) and JsTruthy(d) then nameProp := TyJsonJsString(d);
  src := TyGeoLoadMap(MapTypeOf(ASlot), nameMap, nameProp);
  if src = nil then Exit;
  try
    { the names the data had before any region was appended }
    n0 := AStore.RawCount;
    for i := 0 to High(src.Regions) do
    begin
      nm := src.Regions[i].Name;
      found := False;
      for k := 0 to n0 - 1 do
        if AStore.GetNameByRaw(k) = nm then
        begin
          found := True;
          Break;
        end;
      if found then Continue;
      r := AStore.AppendRow([NaN]);
      AStore.SetName(r, nm);
    end;
  finally
    src.Free;
  end;
end;

function TTyAdvanceChart.MapOrigStore(ASlot: Integer): TTyDataStore;
begin
  Result := nil;
  if (ASlot >= 0) and (ASlot <= High(FMapOrig)) then Result := FMapOrig[ASlot];
  if (Result = nil) and (ASlot >= 0) and (ASlot <= High(FStores)) then Result := FStores[ASlot];
end;

procedure TTyAdvanceChart.SolveMapSeries;
var
  i, g, k, raw, dimV, idx, li, n: Integer;
  key, calc, nm: string;
  names: TStringList;
  lists: array of TTyDoubleArray;
  st, ns: TTyDataStore;
  v, sum, mn, mx: Double;
  stats: TTyDoubleArray;
  node, d: TJSONData;
begin
  for i := 0 to High(FMapOrig) do FreeAndNil(FMapOrig[i]);
  FMapOrig := nil;
  SetLength(FMapOrig, Length(FBindings));
  FMapGroups := nil;
  FMapGroupOf := nil;
  SetLength(FMapGroupOf, Length(FBindings));
  for i := 0 to High(FMapGroupOf) do FMapGroupOf[i] := -1;
  { buildAllMapSeriesGroups: a geo component's id, else the map's name }
  for i := 0 to High(FBindings) do
  begin
    if i > High(FStores) then Break;
    if (FBindings[i].SeriesType <> TyMapSeriesTypeName) or not FBindings[i].Resolved then Continue;
    if FBindings[i].GeoIndex >= 0 then key := 'o' + IntToStr(FBindings[i].GeoIndex)
    else key := 'i' + MapTypeOf(i);
    g := -1;
    for k := 0 to High(FMapGroups) do
      if FMapGroups[k].Key = key then g := k;
    if g < 0 then
    begin
      g := Length(FMapGroups);
      SetLength(FMapGroups, g + 1);
      FMapGroups[g] := Default(TTyMapGroup);
      FMapGroups[g].Key := key;
      FMapGroups[g].Own := FBindings[i].GeoIndex < 0;
      FMapGroups[g].HostGeo := FBindings[i].GeoIndex;
      FMapGroups[g].MapType := MapTypeOf(i);
      FMapGroups[g].Main := -1;
    end;
    FMapGroupOf[i] := g;
    SetLength(FMapGroups[g].R, Length(FMapGroups[g].R) + 1);
    FMapGroups[g].R[High(FMapGroups[g].R)] := i;
    if not FBindings[i].Hidden then
    begin
      SetLength(FMapGroups[g].F, Length(FMapGroups[g].F) + 1);
      FMapGroups[g].F[High(FMapGroups[g].F)] := i;
    end;
  end;
  { mapDataStatistic, per group with a main series }
  for g := 0 to High(FMapGroups) do
  begin
    if Length(FMapGroups[g].F) = 0 then Continue;
    FMapGroups[g].Main := FMapGroups[g].F[0];
    calc := '';
    node := FOption.ComponentAt('series', FBindings[FMapGroups[g].Main].SeriesIndex);
    if node is TJSONObject then
    begin
      d := TJSONObject(node).Find('mapValueCalculation');
      if (d <> nil) and (d.JSONType = jtString) then calc := d.AsString;
    end;
    { every name's numbers, over the series in order ('ec-' + name) }
    names := TStringList.Create;
    try
      names.CaseSensitive := True;
      { by bytes, as upstream keys a name: the locale compare took
        U+00C5 and U+212B for one letter, and whatever came after [P2] }
      names.UseLocale := False;
      names.Sorted := True;
      lists := nil;
      for k := 0 to High(FMapGroups[g].F) do
      begin
        st := FStores[FMapGroups[g].F[k]];
        if st = nil then Continue;
        dimV := st.DimIndexOf(TyPieValueDim);
        for raw := 0 to st.RawCount - 1 do
        begin
          nm := st.GetNameByRaw(raw);
          idx := names.IndexOf(nm);
          if idx < 0 then
          begin
            li := Length(lists);
            SetLength(lists, li + 1);
            names.AddObject(nm, TObject(PtrInt(li)));
          end
          else
            li := PtrInt(names.Objects[idx]);
          if dimV >= 0 then v := st.GetByRaw(dimV, raw) else v := NaN;
          if not IsNan(v) then
          begin
            n := Length(lists[li]);
            SetLength(lists[li], n + 1);
            lists[li][n] := v;
          end;
        end;
      end;
      { the main series' rows, each its name's statistic }
      st := FStores[FMapGroups[g].Main];
      dimV := st.DimIndexOf(TyPieValueDim);
      SetLength(stats, st.RawCount);
      for raw := 0 to st.RawCount - 1 do
      begin
        idx := names.IndexOf(st.GetNameByRaw(raw));
        stats[raw] := NaN;
        if idx < 0 then Continue;
        li := PtrInt(names.Objects[idx]);
        n := Length(lists[li]);
        if n = 0 then Continue;
        sum := 0;
        mn := Infinity;
        mx := -Infinity;
        for k := 0 to n - 1 do
        begin
          if lists[li][k] < mn then mn := lists[li][k];
          if lists[li][k] > mx then mx := lists[li][k];
          sum := sum + lists[li][k];
        end;
        if calc = 'min' then stats[raw] := mn
        else if calc = 'max' then stats[raw] := mx
        else if calc = 'average' then stats[raw] := sum / n
        else stats[raw] := sum;
      end;
    finally
      names.Free;
    end;
    { every series of the group takes the statistic: the main series' rows
      (setData(data.cloneShallow())), its own data kept }
    for k := 0 to High(FMapGroups[g].F) do
    begin
      i := FMapGroups[g].F[k];
      ns := TTyDataStore.Create;
      MapFillStore(FMapGroups[g].Main, ns);
      dimV := ns.DimIndexOf(TyPieValueDim);
      for raw := 0 to Min(ns.RawCount, Length(stats)) - 1 do
        ns.SetCalculated(dimV, raw, stats[raw]);
      FMapOrig[i] := FStores[i];
      FStores[i] := ns;
    end;
  end;
end;

function TTyAdvanceChart.MapGeoOfSlot(ASlot: Integer): TTyGeo;
var g: Integer;
begin
  Result := nil;
  if (ASlot < 0) or (ASlot > High(FMapGroupOf)) then Exit;
  g := FMapGroupOf[ASlot];
  if (g < 0) or (g > High(FMapGroups)) then Exit;
  if FMapGroups[g].Own then
  begin
    if g <= High(FMapGeos) then Result := FMapGeos[g];
  end
  else if (FMapGroups[g].HostGeo >= 0) and (FMapGroups[g].HostGeo <= High(FGeos)) then
    Result := FGeos[FMapGroups[g].HostGeo];
end;

function TTyAdvanceChart.GeoDataOf(AGeo: TTyGeo; ASlot: Integer; AMap: Boolean): TTyGeoData;
var
  st: TTyDataStore;
  dimV, g, row, raw, k, fi, gi, cnt: Integer;
  nm: string;
  v: Double;
  encoded, sym: Boolean;
  node, data, item, es: TJSONData;
  opt: TJSONObject;
  si: Integer;
  o: TTyDataStore;
begin
  Result := Default(TTyGeoData);
  if (AGeo = nil) or (ASlot < 0) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  st := FStores[ASlot];
  si := FBindings[ASlot].SeriesIndex;
  Result.Active := True;
  Result.SeriesIndex := si;
  SetLength(Result.Groups, AGeo.GroupCount);
  dimV := st.DimIndexOf(TyPieValueDim);
  { isVisualEncodedByVisualMap: a visualMap wrote the data's visualMeta }
  encoded := (ASlot <= High(FVisualMetas)) and (Length(FVisualMetas[ASlot]) > 0);
  node := FOption.ComponentAt('series', si);
  data := nil;
  cnt := 0;
  if node is TJSONObject then data := TJSONObject(node).Find('data');
  if data is TJSONArray then cnt := data.Count;
  gi := -1;
  if ASlot <= High(FMapGroupOf) then gi := FMapGroupOf[ASlot];
  for g := 0 to High(Result.Groups) do
  begin
    Result.Groups[g] := Default(TTyGeoDataGroup);
    nm := AGeo.GroupName(g);
    { data.indexOfName: the first }
    raw := -1;
    for k := 0 to st.RawCount - 1 do
      if st.GetNameByRaw(k) = nm then
      begin
        raw := k;
        Break;
      end;
    if raw >= 0 then row := st.IndexOfRawIndex(raw) else row := -1;
    Result.Groups[g].Row := row;
    if (row >= 0) and (dimV >= 0) then v := st.GetByRaw(dimV, raw) else v := NaN;
    { the visual's fill: a visualMap's colour of a number }
    if encoded and (row >= 0) and not IsNan(v) and (ASlot <= High(FVisualRows))
      and (raw <= High(FVisualRows[ASlot])) and FVisualRows[ASlot][raw].ColorSet then
    begin
      Result.Groups[g].HasFill := True;
      Result.Groups[g].Fill := TyVisualToChart(FVisualRows[ASlot][raw].Color);
    end;
    if not AMap then Continue;
    { resetLabelForRegion: the value not a number, or no legend symbol on
      the name (mapSymbolLayout's showLabel) }
    sym := False;
    if (gi >= 0) and (gi <= High(FMapGroups)) then
      for fi := 0 to Min(High(FMapGroups[gi].F), High(FMapGroups[gi].SymOff)) do
      begin
        o := MapOrigStore(FMapGroups[gi].F[fi]);
        if o = nil then Continue;
        for k := 0 to Min(o.RawCount - 1, High(FMapGroups[gi].SymOff[fi])) do
          if (FMapGroups[gi].SymOff[fi][k] >= 0) and (o.GetNameByRaw(k) = nm) then
          begin
            sym := True;
            Break;
          end;
        if sym then Break;
      end;
    Result.Groups[g].LabelOn := (row < 0) or IsNan(v) or not sym;
    { the region model's option: the data item (an appended region's name
      alone) with the feature's echartsStyle merged in where it is silent }
    opt := nil;
    if raw >= 0 then
    begin
      item := nil;
      if raw < cnt then item := TJSONArray(data).Items[raw];
      if item is TJSONObject then opt := TJSONObject(item.Clone)
      else if raw >= cnt then opt := TJSONObject.Create(['name', nm]);
      if (opt <> nil) and (AGeo.Source <> nil) then
        for k := 0 to High(AGeo.Source.Regions) do
          if AGeo.Source.Regions[k].Name = nm then
          begin
            es := nil;
            if AGeo.Source.Regions[k].Properties is TJSONObject then
              es := TJSONObject(AGeo.Source.Regions[k].Properties).Find('echartsStyle');
            if es is TJSONObject then
            begin
              TyGeoMergeAbsent(opt, TJSONObject(es));
              Break;
            end;
          end;
    end;
    Result.Groups[g].Opt := opt;
    { getDataParams: the series', the row's; the value as String() prints it }
    if row >= 0 then
      Result.Groups[g].Params := TooltipParams(TyChartDatum(si, row))
    else
      Result.Groups[g].Params := TyChartBlankParams;
    Result.Groups[g].Params.ComponentType := 'series';
    Result.Groups[g].Params.SeriesType := TyMapSeriesTypeName;
    Result.Groups[g].Params.SeriesIndex := si;
    Result.Groups[g].Params.SeriesName := SeriesModelName(si);
    Result.Groups[g].Params.Name := nm;
    if IsNan(v) then Result.Groups[g].Params.ValueText := 'NaN'
    else Result.Groups[g].Params.ValueText := TyJsNumberToString(v);
  end;
end;

procedure TTyAdvanceChart.SolveMapGeos(APPI: Integer);
var
  gi, i, g, k, fi, raw, idx: Integer;
  ref: TTyXYWH;
  nameMap, nm2: TJSONObject;
  node, d: TJSONData;
  geo: TTyGeo;
  legend, showSym: Boolean;
  counts: TStringList;
  o: TTyDataStore;
  nm: string;
  dimV: Integer;
  data: TTyGeoData;
begin
  if Length(FSvgKeepMap) < Length(FMapGeos) then SetLength(FSvgKeepMap, Length(FMapGeos));
  for i := 0 to High(FMapGeos) do
    if FMapGeos[i] <> nil then FSvgKeepMap[i] := FMapGeos[i].SvgSaveFlags;
  for i := 0 to High(FMapGeos) do FreeAndNil(FMapGeos[i]);
  FMapGeos := nil;
  { a geo component draws with the data of the first map series naming it
    (MapDraw.draw's eachComponent over every map series) }
  for gi := 0 to High(FGeos) do
  begin
    if (FGeos[gi] = nil) or not FGeos[gi].Valid then Continue;
    for i := 0 to High(FBindings) do
      if (FBindings[i].SeriesType = TyMapSeriesTypeName) and FBindings[i].Resolved
        and (FBindings[i].GeoIndex = gi) then
      begin
        data := GeoDataOf(FGeos[gi], i, False);
        FGeos[gi].SetData(data);
        for k := 0 to High(data.Groups) do FreeAndNil(data.Groups[k].Opt);
        Break;
      end;
  end;
  SetLength(FMapGeos, Length(FMapGroups));
  legend := (FOption <> nil) and (FOption.ComponentCount('legend') > 0);
  for g := 0 to High(FMapGroups) do
  begin
    FMapGroups[g].SymOff := nil;
    if not FMapGroups[g].Own or (Length(FMapGroups[g].R) = 0) then Continue;
    { the group's nameMaps merged (zrUtil.mergeAll: the first's keys win;
      none on the first, none at all) }
    nameMap := nil;
    for k := 0 to High(FMapGroups[g].R) do
    begin
      node := FOption.ComponentAt('series', FBindings[FMapGroups[g].R[k]].SeriesIndex);
      d := nil;
      if node is TJSONObject then d := TJSONObject(node).Find('nameMap');
      if k = 0 then
      begin
        if d is TJSONObject then nameMap := TJSONObject(d.Clone);
      end
      else if (nameMap <> nil) and (d is TJSONObject) then
        TyGeoMergeAbsent(nameMap, TJSONObject(d));
    end;
    try
      geo := TTyGeo.CreateForMap(FOption, FBindings[FMapGroups[g].R[0]].SeriesIndex, g, nameMap);
    finally
      nameMap.Free;
    end;
    FMapGeos[g] := geo;
    geo.SvgMeasure := @GeoSvgMeasure;
    for k := 0 to High(FMapRoam) do
      if (FMapRoam[k].Key = FMapGroups[g].Key) and FMapRoam[k].State.Valid then
        geo.SetRoamOption(FMapRoam[k].State.Centre, FMapRoam[k].State.Zoom);
    { resizeGeo(the first declared series): in its cell or its day when it
      is written with usage 'box' on a matrix or a calendar [Batch 154] }
    if MapSeriesBoxRef(FBindings[FMapGroups[g].R[0]].SeriesIndex, ref) then
      geo.ResizeXYWH(ref, APPI)
    else
      geo.Resize(FLastRect, APPI);
    if g <= High(FSvgKeepMap) then geo.SvgRestoreFlags(FSvgKeepMap[g]);
    geo.Gen := FGeoGen;
    if FMapGroups[g].Main < 0 then Continue;
    { mapSymbolLayout: the offsets of the legend symbols }
    SetLength(FMapGroups[g].SymOff, Length(FMapGroups[g].F));
    counts := TStringList.Create;
    try
      counts.CaseSensitive := True;
      { by bytes, as upstream keys a name: the locale compare took
        U+00C5 and U+212B for one letter, and whatever came after [P2] }
      counts.UseLocale := False;
      counts.Sorted := True;
      for fi := 0 to High(FMapGroups[g].F) do
      begin
        i := FMapGroups[g].F[fi];
        o := MapOrigStore(i);
        if o = nil then Continue;
        SetLength(FMapGroups[g].SymOff[fi], o.RawCount);
        for raw := 0 to o.RawCount - 1 do FMapGroups[g].SymOff[fi][raw] := -1;
        showSym := True;
        node := FOption.ComponentAt('series', FBindings[i].SeriesIndex);
        if node is TJSONObject then
        begin
          d := TJSONObject(node).Find('showLegendSymbol');
          if d <> nil then showSym := JsTruthy(d);
        end;
        if not (showSym and legend and geo.Valid) then Continue;
        dimV := o.DimIndexOf(TyPieValueDim);
        for raw := 0 to o.RawCount - 1 do
        begin
          nm := o.GetNameByRaw(raw);
          if geo.RegionByName(nm) = nil then Continue;
          if (dimV < 0) or IsNan(o.GetByRaw(dimV, raw)) then Continue;
          idx := counts.IndexOf(nm);
          if idx < 0 then
          begin
            FMapGroups[g].SymOff[fi][raw] := 0;
            counts.AddObject(nm, TObject(PtrInt(1)));
          end
          else
          begin
            FMapGroups[g].SymOff[fi][raw] := PtrInt(counts.Objects[idx]);
            counts.Objects[idx] := TObject(PtrInt(counts.Objects[idx]) + 1);
          end;
        end;
      end;
    finally
      counts.Free;
    end;
    { the main series' data drawn with it, its region models over the main
      series' option }
    nm2 := nil;
    node := FOption.ComponentAt('series', FBindings[FMapGroups[g].Main].SeriesIndex);
    if node is TJSONObject then nm2 := TJSONObject(node);
    data := GeoDataOf(geo, FMapGroups[g].Main, True);
    geo.SetData(data, nm2);
    for k := 0 to High(data.Groups) do FreeAndNil(data.Groups[k].Opt);
  end;
end;

function TTyAdvanceChart.GeoSyncFromRows(AGeo: TTyGeo): Boolean;
var
  data: TTyGeoData;
  g, row, raw, si, slot, hover: Integer;
  hbo: Cardinal;
  sel: Boolean;
begin
  Result := False;
  if AGeo = nil then Exit;
  data := AGeo.Data;
  if not data.Active then Exit;
  si := data.SeriesIndex;
  slot := SlotOfSeries(si);
  for g := 0 to High(data.Groups) do
  begin
    row := data.Groups[g].Row;
    hover := TyStHoverNormal;
    hbo := 0;
    sel := False;
    if (row >= 0) and (si >= 0) and (si <= High(FSt)) and (FSt[si].Kind = sskMap)
      and (slot >= 0) and (slot <= High(FStores)) and (FStores[slot] <> nil) then
    begin
      raw := FStores[slot].GetRawIndex(row);
      if (raw >= 0) and (raw <= High(FSt[si].Rows)) and FSt[si].Rows[raw].Host.Exists then
      begin
        hover := FSt[si].Rows[raw].Host.HoverState;
        hbo := FSt[si].Rows[raw].Host.HighByOuter;
        sel := FSt[si].Rows[raw].Host.Selected;
      end;
    end;
    if AGeo.SetFlags(g, hover, hbo, sel) then Result := True;
  end;
end;

procedure TTyAdvanceChart.MapRepatch(APPI: Integer; AForce: Boolean);
var
  k, i, n: Integer;
  geo: TTyGeo;
  tmp: TTyPaintList;
  ink: TTyGeoInk;
begin
  if FPaintList = nil then Exit;
  ink := GeoInk;
  for k := 0 to High(FGeoDraws) do
  begin
    geo := TTyGeo(FGeoDraws[k].Geo);
    if (geo = nil) or not geo.Data.Active then Continue;
    { forced by a state patch: the flags were synced already (MapApplyChanged),
      and the list was put back to the regions the last build drew [P2] }
    if not GeoSyncFromRows(geo) and not AForce then Continue;
    geo.ApplyStates(ink, APPI);
    tmp := TTyPaintList.Create;
    try
      n := TyBuildGeo(geo, ink, NewTextMeasurer(APPI), APPI, tmp, False);
      if n <> FGeoDraws[k].Count then Continue;
      { a state write: journaled [P2] }
      FPaintList.JournalRecord(True);
      try
        for i := 0 to n - 1 do
          FPaintList.SetElement(FGeoDraws[k].Start + i, tmp.Element(i));
      finally
        FPaintList.JournalRecord(False);
      end;
    finally
      tmp.Free;
    end;
  end;
end;

{ [R2-B] the element of a map series' SVG picture the pointer is over: the
  list element AIdx's node (-1, or no SVG element: none) on the geo that
  draws the series }
procedure TTyAdvanceChart.MapSvgPointer(ASeriesIndex, AIdx: Integer);
var k, node: Integer; geo: TTyGeo;
begin
  node := -1;
  if (FPaintList <> nil) and (AIdx >= 0) and (AIdx < FPaintList.Count) then
    node := FPaintList.Element(AIdx).ZrHit.SvgNode - 1;
  for k := 0 to High(FGeoDraws) do
  begin
    geo := TTyGeo(FGeoDraws[k].Geo);
    if (geo <> nil) and geo.Data.Active and (geo.Data.SeriesIndex = ASeriesIndex) then
      geo.SetSvgPointer(node);
  end;
end;

function TTyAdvanceChart.MapApplyChanged: Boolean;
var k, ppi: Integer; geo: TTyGeo; ink: TTyGeoInk;
begin
  Result := False;
  if Length(FGeoDraws) = 0 then Exit;
  ink := GeoInk;
  ppi := FPaintListPPI;
  if ppi <= 0 then ppi := FLastPPI;
  for k := 0 to High(FGeoDraws) do
  begin
    geo := TTyGeo(FGeoDraws[k].Geo);
    if (geo = nil) or not geo.Data.Active then Continue;
    GeoSyncFromRows(geo);
    if geo.ApplyStates(ink, ppi) then Result := True;
  end;
end;

function TTyAdvanceChart.BuildMapSeries(ASlot: Integer; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;
var g, n: Integer; geo: TTyGeo;
begin
  Result := 0;
  if (ASlot < 0) or (ASlot > High(FMapGroupOf)) then Exit;
  g := FMapGroupOf[ASlot];
  if (g < 0) or (g > High(FMapGroups)) or not FMapGroups[g].Own then Exit;
  if g > High(FMapGeos) then Exit;
  geo := FMapGeos[g];
  if (geo = nil) or not geo.Valid then Exit;
  { mapSeriesNeedsDrawMap: the main series of a group with no geo component }
  if FMapGroups[g].Main = ASlot then
  begin
    GeoSyncFromRows(geo);
    n := AList.Count;
    Inc(Result, TyBuildGeo(geo, GeoInk, AMeasurer, APPI, AList));
    SetLength(FGeoDraws, Length(FGeoDraws) + 1);
    FGeoDraws[High(FGeoDraws)].Geo := geo;
    FGeoDraws[High(FGeoDraws)].Series := FBindings[ASlot].SeriesIndex;
    FGeoDraws[High(FGeoDraws)].Start := n;
    FGeoDraws[High(FGeoDraws)].Count := AList.Count - n;
  end;
  Inc(Result, BuildMapSymbols(ASlot, AMeasurer, APPI, AList));
end;

{ MapView._renderSymbols: a circle of radius 3 at each region centre the
  series has a value for, nine pixels along per series before it there
  (the offset), silent, z2 8 -- 19 for the first, which carries the label
  (position bottom, its text the main series' getFormattedLabel of the
  name, its show and look the series' own item's, its state the region
  group's: onHoverStateChange) }
function TTyAdvanceChart.BuildMapSymbols(ASlot: Integer; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;
var
  g, fi, k, raw, off, gr, si, hover, start: Integer;
  geo: TTyGeo;
  o: TTyDataStore;
  nm, txt, fam: string;
  reg: TTyGeoRegion;
  c: TTyGeoPt;
  p: TTyPointF;
  scale, cx, cy, w, h, ax, ay: Double;
  el: TTyChartElement;
  colour, lc: TTyChartColor;
  z, fsz, fwt: Integer;
  ink: TTyGeoInk;
  dr: TTyGeoDraw;
  lbl: TTyGeoLabel;
  hasLbl, shown, nShow, sShow, has: Boolean;
  st: string;
  nodes: array[0..1] of TJSONObject;
  dd: TJSONData;

  { the item's label up its chain: the item, the series; nil where neither
    writes it }
  function LGet(const APath: array of string): TJSONData;
  var q, j: Integer; x: TJSONData;
  begin
    Result := nil;
    for q := 0 to 1 do
    begin
      if nodes[q] = nil then Continue;
      x := nodes[q];
      for j := 0 to High(APath) do
      begin
        if not (x is TJSONObject) then
        begin
          x := nil;
          Break;
        end;
        x := TJSONObject(x).Find(APath[j]);
        if x = nil then Break;
      end;
      if (x <> nil) and (x.JSONType <> jtNull) then Exit(x);
    end;
  end;

begin
  Result := 0;
  g := FMapGroupOf[ASlot];
  if (g < 0) or (g > High(FMapGroups)) then Exit;
  fi := -1;
  for k := 0 to High(FMapGroups[g].F) do
    if FMapGroups[g].F[k] = ASlot then fi := k;
  if (fi < 0) or (fi > High(FMapGroups[g].SymOff)) then Exit;
  geo := FMapGeos[g];
  o := MapOrigStore(ASlot);
  if (geo = nil) or (o = nil) then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  si := FBindings[ASlot].SeriesIndex;
  colour := TTyChartColor(SeriesColor(si));
  z := SeriesIntIn(si, 'z', 2);
  ink := GeoInk;
  dr := geo.LastDraw;
  start := AList.Count;
  nodes[1] := StSeriesNode(si);
  for raw := 0 to Min(o.RawCount - 1, High(FMapGroups[g].SymOff[fi])) do
  begin
    off := FMapGroups[g].SymOff[fi][raw];
    if off < 0 then Continue;
    nm := o.GetNameByRaw(raw);
    reg := geo.RegionByName(nm);
    if reg = nil then Continue;
    c := reg.GetCenter;
    if not geo.PointOf(c.X, c.Y, p) then Continue;
    cx := p.X + off * 9 * scale;
    cy := p.Y;
    el := TyChartElement(TyShapeCircle(cx, cy, 3 * scale));
    el.Style.HasFill := True;
    el.Style.FillColor := colour;
    el.Silent := True;
    el.Z := z;
    if off = 0 then el.Z2 := 8 + 11 else el.Z2 := 8;
    el.Datum := TyChartNoDatum;
    AList.Add(el);
    Inc(Result);
    if off <> 0 then Continue;
    { the label: the series' own item over the series, MapSeries' defaults
      under them }
    nodes[0] := StItemNode(si, raw);
    dd := LGet(['label', 'show']);
    nShow := (dd <> nil) and JsTruthy(dd);
    gr := geo.GroupIndexOf(nm);
    hover := TyStHoverNormal;
    if gr >= 0 then hover := geo.GroupFlags(gr).Hover;
    if hover = TyStHoverEmphasis then st := 'emphasis'
    else if hover = TyStHoverBlur then st := 'blur'
    else st := '';
    { getLabelStatesModels: a state's show over the normal's; emphasis and
      select show by default }
    dd := LGet(['emphasis', 'label', 'show']);
    if dd <> nil then has := JsTruthy(dd) else has := True;
    dd := LGet(['select', 'label', 'show']);
    if dd <> nil then sShow := JsTruthy(dd) else sShow := True;
    hasLbl := nShow or has or sShow;
    dd := LGet(['blur', 'label', 'show']);
    if (dd <> nil) and JsTruthy(dd) then hasLbl := True;
    if not hasLbl then Continue;
    if st = 'emphasis' then shown := has
    else if st = 'blur' then
    begin
      dd := LGet(['blur', 'label', 'show']);
      if dd <> nil then shown := JsTruthy(dd) else shown := nShow;
    end
    else shown := nShow;
    { the text: the main series' getFormattedLabel of the name, else the name }
    txt := nm;
    if (gr >= 0) and (gr <= High(dr.Groups)) and (Length(dr.Groups[gr].Paths) > 0) then
    begin
      lbl := dr.Groups[gr].Paths[0].Lbl;
      if st = 'emphasis' then txt := lbl.States[stnEmphasis].Text
      else if st = 'blur' then txt := lbl.States[stnBlur].Text
      else txt := lbl.Text;
    end;
    { the colour: the state's own, else the normal's, else the tokens }
    lc := ink.LabelColour;
    dd := LGet(['label', 'color']);
    if (dd <> nil) and (dd.JSONType = jtString) then TyTryParseChartColor(dd.AsString, lc);
    if st = 'emphasis' then
    begin
      dd := LGet(['emphasis', 'label', 'color']);
      if (dd <> nil) and (dd.JSONType = jtString) then TyTryParseChartColor(dd.AsString, lc)
      else lc := ink.LabelHighlight;
    end;
    fsz := ink.LabelFontSizeLogical;
    dd := LGet(['label', 'fontSize']);
    if dd <> nil then fsz := TyOptFontSize(dd, ink.LabelFontSizeLogical);
    fwt := ink.LabelFontWeight;
    fam := ink.LabelFontName;
    w := 0;
    h := 0;
    if (txt <> '') and (AMeasurer <> nil) then AMeasurer.MeasureLine(txt, fam, fsz, fwt, w, h);
    { position 'bottom': the box's bottom middle and the distance 5 below }
    ax := cx;
    ay := cy + 3 * scale + 5 * scale;
    el := TyChartElement(TyShapeRect(TyAnchorBox(ax, ay, w, h, tahCentre, tavTop)));
    el.Caption.Text := txt;
    el.Caption.FontName := fam;
    el.Caption.FontSizeLogical := fsz;
    el.Caption.FontWeight := fwt;
    el.Caption.Colour := lc;
    el.Caption.X := ax;
    el.Caption.Y := ay;
    el.Caption.AnchorH := tahCentre;
    el.Caption.AnchorV := tavTop;
    el.Caption.Truncate := False;
    el.Z := z;
    el.Z2 := 19;
    el.Silent := True;
    el.Ignore := not shown or (txt = '') or (w <= 0) or (h <= 0);
    el.Datum := TyChartNoDatum;
    AList.Add(el);
    Inc(Result);
  end;
  SetLength(FMapSyms, Length(FMapSyms) + 1);
  FMapSyms[High(FMapSyms)].Geo := nil;
  FMapSyms[High(FMapSyms)].Series := si;
  FMapSyms[High(FMapSyms)].Start := start;
  FMapSyms[High(FMapSyms)].Count := AList.Count - start;
end;

function TTyAdvanceChart.MapTooltip(const ADatum: TTyChartDatumRef;
  out ABlock: TTyTooltipBlock): Boolean;
var
  slot, g, k, f, raw, dimV, dimO: Integer;
  st, o: TTyDataStore;
  nm, header: string;
  v: Double;
begin
  Result := False;
  ABlock := nil;
  if ADatum.Kind <> ctkSeries then Exit;
  slot := SlotOfSeries(ADatum.SeriesIndex);
  if (slot < 0) or (slot > High(FBindings)) then Exit;
  if FBindings[slot].SeriesType <> TyMapSeriesTypeName then Exit;
  if (slot > High(FMapGroupOf)) or (FMapGroupOf[slot] < 0) then Exit;
  g := FMapGroupOf[slot];
  st := FStores[slot];
  if (st = nil) or (ADatum.DataIndex < 0) or (ADatum.DataIndex >= st.Count) then Exit;
  dimV := st.DimIndexOf(TyPieValueDim);
  nm := st.GetName(ADatum.DataIndex);
  if dimV >= 0 then v := st.Get(dimV, ADatum.DataIndex) else v := NaN;
  { the series of the group with a value under the name }
  header := '';
  for k := 0 to High(FMapGroups[g].F) do
  begin
    f := FMapGroups[g].F[k];
    o := MapOrigStore(f);
    if o = nil then Continue;
    dimO := o.DimIndexOf(TyPieValueDim);
    for raw := 0 to o.RawCount - 1 do
      if o.GetNameByRaw(raw) = nm then
      begin
        if (dimO >= 0) and not IsNan(o.GetByRaw(dimO, raw)) then
        begin
          if header <> '' then header := header + ', ';
          header := header + SeriesModelName(FBindings[f].SeriesIndex);
        end;
        Break;
      end;
  end;
  ABlock := TTyTooltipBlock.CreateSection(header, header = '');
  ABlock.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, nm, False,
    TyTooltipValueText(v), False));
  Result := True;
end;

procedure TTyAdvanceChart.DoLegacySelect(APayload: TJSONObject;
  const ASeriesType, AType: string);
var
  q: TJSONObject;
  arr: TJSONArray;
  idx: TTyIntegerArray;
  k, slot: Integer;
begin
  q := TJSONObject(APayload.Clone);
  try
    q.Strings['type'] := AType;
    arr := TJSONArray.Create;
    idx := MatchSeries(APayload);
    for k := 0 to High(idx) do
    begin
      slot := SlotOfSeries(idx[k]);
      if (slot >= 0) and (FBindings[slot].SeriesType = ASeriesType) then arr.Add(idx[k]);
    end;
    if q.IndexOfName('seriesIndex') >= 0 then q.Elements['seriesIndex'] := arr
    else q.Add('seriesIndex', arr);
    { the legacy action is registered with no update of its own: 'update',
      a render; the select it dispatches runs after -- [F4b] dispatched
      (api.dispatchAction) inside the action, so it waits; the action's
      own event (a copy of the payload, the type lowercased) goes first }
    DispatchActionObject(TJSONObject(q.Clone));
    FullUpdate;
    EmitPayloadEvent(LowerCase(APayload.Get('type', '')),
      CopyWithType(APayload, LowerCase(APayload.Get('type', ''))));
  finally
    q.Free;
  end;
end;

function TTyAdvanceChart.MapGeoOf(ASeriesIndex: Integer): TTyGeo;
begin
  Result := MapGeoOfSlot(SlotOfSeries(ASeriesIndex));
end;

function TTyAdvanceChart.GeoDrawRange(AGeo: TTyGeo; out AStart, ACount: Integer): Boolean;
var k: Integer;
begin
  AStart := -1;
  ACount := 0;
  for k := 0 to High(FGeoDraws) do
    if FGeoDraws[k].Geo = AGeo then
    begin
      AStart := FGeoDraws[k].Start;
      ACount := FGeoDraws[k].Count;
      Exit(True);
    end;
  Result := False;
end;

function TTyAdvanceChart.MapSymbolRange(ASeriesIndex: Integer; out AStart, ACount: Integer): Boolean;
var k: Integer;
begin
  AStart := -1;
  ACount := 0;
  for k := 0 to High(FMapSyms) do
    if FMapSyms[k].Series = ASeriesIndex then
    begin
      AStart := FMapSyms[k].Start;
      ACount := FMapSyms[k].Count;
      Exit(True);
    end;
  Result := False;
end;

procedure TTyAdvanceChart.MergeGeoRoam(var AState: TTyGraphRoamState; AIndex: Integer;
  ANew: TJSONObject);
var spec: TTyGeoSpec;
begin
  { upstream's roam wrote centre and zoom into the geo's option; a merge
    writing one of them overwrites that one and keeps the other }
  if (not AState.Valid) or (ANew = nil) then Exit;
  if (ANew.Find('center') = nil) and (ANew.Find('zoom') = nil) then Exit;
  spec := TyGeoSpecOf(FOption, AIndex);
  if ANew.Find('center') <> nil then AState.Centre := spec.Centre;
  if ANew.Find('zoom') <> nil then AState.Zoom := spec.Zoom;
end;

function TTyAdvanceChart.GeoRoam(AIndex: Integer; ADX, ADY: Double): Boolean;
var p: TJSONObject;
begin
  p := TJSONObject.Create;
  p.Add('type', 'geoRoam');
  if AIndex >= 0 then p.Add('geoIndex', AIndex) else p.Add('componentType', 'geo');
  p.Add('dx', ADX);
  p.Add('dy', ADY);
  DispatchActionObject(p);
  Result := FGeoRoamHits > 0;
end;

function TTyAdvanceChart.GeoZoom(AIndex: Integer; AScale, AOriginX, AOriginY: Double): Boolean;
var p: TJSONObject;
begin
  p := TJSONObject.Create;
  p.Add('type', 'geoRoam');
  if AIndex >= 0 then p.Add('geoIndex', AIndex) else p.Add('componentType', 'geo');
  p.Add('zoom', AScale);
  p.Add('originX', AOriginX);
  p.Add('originY', AOriginY);
  DispatchActionObject(p);
  Result := FGeoRoamHits > 0;
end;

function TTyAdvanceChart.GeoRoamState(AIndex: Integer; out ACentre: TTyGraphCentre;
  out AZoom: Double): Boolean;
var spec: TTyGeoSpec;
begin
  ACentre := Default(TTyGraphCentre);
  AZoom := 1;
  Result := (FOption <> nil) and (AIndex >= 0) and (AIndex < FOption.ComponentCount('geo'));
  if not Result then Exit;
  if (AIndex <= High(FGeoRoam)) and FGeoRoam[AIndex].Valid then
  begin
    ACentre := FGeoRoam[AIndex].Centre;
    AZoom := FGeoRoam[AIndex].Zoom;
    Exit;
  end;
  spec := TyGeoSpecOf(FOption, AIndex);
  ACentre := spec.Centre;
  AZoom := spec.Zoom;
end;

procedure TTyAdvanceChart.FreeGeoSel;
var i: Integer;
begin
  for i := 0 to High(FGeoSel) do FreeAndNil(FGeoSel[i]);
  FGeoSel := nil;
end;

{ GeoModel.optionUpdated: `if (!option.selectedMap) option.selectedMap =
  selectedMap` -- the regions (entries with their echartsStyle) whose name
  is truthy and that say `selected` -- made once, the model's after }
function TTyAdvanceChart.GeoSelMap(AIndex: Integer): TJSONObject;
var
  node, d, regions, nm: TJSONData;
  i, n: Integer;
  geo: TTyGeo;
  opt: TJSONObject;
begin
  Result := nil;
  if (AIndex < 0) or (FOption = nil) or (AIndex >= FOption.ComponentCount('geo')) then Exit;
  n := Length(FGeoSel);
  if AIndex >= n then
  begin
    SetLength(FGeoSel, AIndex + 1);
    for i := n to AIndex do FGeoSel[i] := nil;
  end;
  if FGeoSel[AIndex] <> nil then Exit(FGeoSel[AIndex]);
  Result := TJSONObject.Create;
  FGeoSel[AIndex] := Result;
  node := FOption.ComponentAt('geo', AIndex);
  if not (node is TJSONObject) then Exit;
  d := TJSONObject(node).Find('selectedMap');
  if JsTruthy(d) then
  begin
    { a written selectedMap (a truthy one that is no object selects nothing) }
    if d is TJSONObject then
      for i := 0 to d.Count - 1 do
        Result.Add(TJSONObject(d).Names[i], TJSONObject(d).Items[i].Clone);
    Exit;
  end;
  regions := TJSONObject(node).Find('regions');
  if regions is TJSONArray then
    for i := 0 to regions.Count - 1 do
    begin
      if not (regions.Items[i] is TJSONObject) then Continue;
      nm := TJSONObject(regions.Items[i]).Find('name');
      if not JsTruthy(nm) then Continue;
      if JsTruthy(TJSONObject(regions.Items[i]).Find('selected')) then
        Result.Booleans[TyJsonJsString(nm)] := True;
    end;
  { a fresh entry's `selected` comes from its echartsStyle }
  if AIndex <= High(FGeos) then
  begin
    geo := FGeos[AIndex];
    if geo <> nil then
      for i := 0 to geo.GroupCount - 1 do
      begin
        opt := geo.GroupOpt(i);
        if (opt <> nil) and JsTruthy(opt.Find('selected')) then
          Result.Booleans[geo.GroupName(i)] := True;
      end;
  end;
end;

function TTyAdvanceChart.GeoIsSelected(AIndex: Integer; const AName: string): Boolean;
var m: TJSONObject;
begin
  m := GeoSelMap(AIndex);
  Result := (m <> nil) and JsTruthy(m.Find(AName));
end;

function TTyAdvanceChart.GeoSelected(AIndex: Integer; const AName: string): Boolean;
begin
  Result := GeoIsSelected(AIndex, AName);
end;

{ updateSelectStatus: enterSelect / leaveSelect on every region group }
procedure TTyAdvanceChart.GeoSyncSelected(AIndex: Integer);
var g: Integer; geo: TTyGeo;
begin
  if (AIndex < 0) or (AIndex > High(FGeos)) or (FGeos[AIndex] = nil) then Exit;
  geo := FGeos[AIndex];
  for g := 0 to geo.GroupCount - 1 do
    if geo.SetSelected(g, GeoIsSelected(AIndex, geo.GroupName(g))) then FGeoDirty := True;
end;

{ eachComponent of mainType 'geo' with the payload as the query: the geos the payload's
  geoIndex / geoId / geoName names, every geo when it names none }
function TTyAdvanceChart.GeoMatch(APayload: TJSONObject): TTyIntegerArray;
var
  pf: TTyParsedFinder;
  i, n: Integer;
begin
  Result := nil;
  if FOption = nil then Exit;
  pf := TyParseFinder(APayload, FOption.Keys);
  for i := 0 to High(pf.Types) do
    if pf.Types[i].MainType = 'geo' then Exit(pf.Types[i].Models);
  n := FOption.ComponentCount('geo');
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := i;
end;

{ preParseFinder: the first key of the payload that is <mainType>Index /
  Id / Name names the highlight's main type }
function TTyAdvanceChart.GeoFinderFirst(APayload: TJSONObject): Boolean;
var pf: TTyParsedFinder;
begin
  Result := False;
  if FOption = nil then Exit;
  pf := TyParseFinder(APayload, FOption.Keys);
  Result := (Length(pf.Types) > 0) and (pf.Types[0].MainType = 'geo');
end;

{ the geo a target was found on, when its render is still the current one }
function TTyAdvanceChart.GeoOfTarget(const ATarget: TTyChartEventTarget): TTyGeo;
begin
  Result := nil;
  if ATarget.HdKind <> 14 then Exit;
  if (ATarget.HdSeries < 0) or (ATarget.HdSeries > High(FGeos)) then Exit;
  if (FGeos[ATarget.HdSeries] = nil) or (FGeos[ATarget.HdSeries].Gen <> ATarget.HdGen) then Exit;
  Result := FGeos[ATarget.HdSeries];
end;

function TTyAdvanceChart.IsGeoDatum(const ADatum: TTyChartDatumRef): Boolean;
begin
  Result := (ADatum.Kind = ctkGeo) and (ADatum.ComponentIndex >= 0)
    and (ADatum.ComponentIndex <= High(FGeos)) and (FGeos[ADatum.ComponentIndex] <> nil)
    and (ADatum.DataIndex >= 0)
    and (ADatum.DataIndex < FGeos[ADatum.ComponentIndex].GroupCount);
end;

{ handleGlobalMouseOverForHighDown: a group whose emphasis is disabled is
  no dispatcher at all; else a 'self' focus blurs the component, and the
  group enters emphasis unless an action holds it }
procedure TTyAdvanceChart.GeoHoverOver(const ATarget: TTyChartEventTarget);
var geo: TTyGeo; g: Integer;
begin
  geo := GeoOfTarget(ATarget);
  if geo = nil then Exit;
  g := ATarget.HdRow;
  { [F6b] an SVG element under no dispatcher (a named text) }
  if g < 0 then Exit;
  if geo.GroupEmphasisDisabled(g) then Exit;
  if geo.GroupFocusSelf(g) and geo.BlurAll then FGeoDirty := True;
  if geo.HoverEnter(g) then FGeoDirty := True;
  if FGeoDirty then InvalidateFrame;
end;

{ handleGlobalMouseOutForHighDown: allLeaveBlur, then the group leaves
  emphasis unless an action holds it }
procedure TTyAdvanceChart.GeoHoverOut(const ATarget: TTyChartEventTarget);
var geo: TTyGeo; g: Integer;
begin
  geo := GeoOfTarget(ATarget);
  if geo = nil then Exit;
  g := ATarget.HdRow;
  if g < 0 then Exit;
  if geo.GroupEmphasisDisabled(g) then Exit;
  StAllLeaveBlur;
  if geo.HoverLeave(g) then FGeoDirty := True;
  if FGeoDirty or FStDirty then InvalidateFrame;
end;

{ GeoView._handleRegionClick: geoToggleSelect for the clicked region's
  name, by the geo's id }
procedure TTyAdvanceChart.GeoRegionClick(const ATarget: TTyChartEventTarget);
var geo: TTyGeo; p: TJSONObject;
begin
  geo := GeoOfTarget(ATarget);
  if geo = nil then Exit;
  p := TJSONObject.Create(['type', 'geoToggleSelect',
    'geoIndex', ATarget.HdSeries, 'name', ATarget.HdName]);
  { DispatchActionObject owns and frees it }
  DispatchActionObject(p);
end;

{ makeAction (geo/install.ts): the method on every geo the query names,
  `selected` over every region of each -- one object across the geos --
  and allSelected per geo; the event: selected, allSelected, name, type }
procedure TTyAdvanceChart.DoGeoSelectAction(APayload: TJSONObject; const AType: string);
var
  geos: TTyIntegerArray;
  i, k, gi, j: Integer;
  nameD, mode: TJSONData;
  nm, evType, all, names, json: string;
  keys: TTyStringArray;
  vals: TTyBoolArray;
  keyOrder: TTyIntegerArray;
  node: TJSONData;
  m: TJSONObject;
  geo: TTyGeo;
  found: Boolean;

  procedure DoSelect(AIndex: Integer);
  begin
    node := FOption.ComponentAt('geo', AIndex);
    mode := nil;
    if node is TJSONObject then mode := TJSONObject(node).Find('selectedMode');
    { `if (!selectedMode) return`; anything but 'multiple' starts afresh }
    if not JsTruthy(mode) then Exit;
    m := GeoSelMap(AIndex);
    if m = nil then Exit;
    if not ((mode.JSONType = jtString) and (mode.AsString = 'multiple')) then m.Clear;
    m.Booleans[nm] := True;
  end;

  procedure DoUnSelect(AIndex: Integer);
  begin
    m := GeoSelMap(AIndex);
    if m <> nil then m.Booleans[nm] := False;
  end;

  procedure SetSel(const AKey: string; AValue: Boolean);
  var q: Integer;
  begin
    for q := 0 to High(keys) do
      if keys[q] = AKey then
      begin
        vals[q] := AValue;
        Exit;
      end;
    SetLength(keys, Length(keys) + 1);
    SetLength(vals, Length(vals) + 1);
    keys[High(keys)] := AKey;
    vals[High(vals)] := AValue;
  end;

  { JavaScript's own key order: array indices ascending, then the rest in
    insertion order }
  procedure SortKeys;
  var q, r, t: Integer;
  begin
    SetLength(keyOrder, Length(keys));
    for q := 0 to High(keys) do keyOrder[q] := q;
    for q := 1 to High(keyOrder) do
    begin
      t := keyOrder[q];
      r := q - 1;
      while (r >= 0) and TyJsIsIndexKey(keys[t])
        and (not TyJsIsIndexKey(keys[keyOrder[r]])
          or (StrToInt64(keys[keyOrder[r]]) > StrToInt64(keys[t]))) do
      begin
        keyOrder[r + 1] := keyOrder[r];
        Dec(r);
      end;
      keyOrder[r + 1] := t;
    end;
  end;

begin
  if AType = 'geoToggleSelect' then evType := 'geoselectchanged'
  else if AType = 'geoSelect' then evType := 'geoselected'
  else evType := 'geounselected';
  nameD := APayload.Find('name');
  nm := TyJsonJsString(nameD);
  geos := GeoMatch(APayload);
  keys := nil;
  vals := nil;
  all := '';
  for i := 0 to High(geos) do
  begin
    gi := geos[i];
    if AType = 'geoToggleSelect' then
    begin
      if GeoIsSelected(gi, nm) then DoUnSelect(gi) else DoSelect(gi);
    end
    else if AType = 'geoSelect' then DoSelect(gi)
    else DoUnSelect(gi);
    geo := nil;
    if gi <= High(FGeos) then geo := FGeos[gi];
    if (geo <> nil) and (geo.Source <> nil) then
      for k := 0 to High(geo.Source.Regions) do
        SetSel(geo.Source.Regions[k].Name, GeoIsSelected(gi, geo.Source.Regions[k].Name));
    SortKeys;
    names := '';
    found := False;
    for k := 0 to High(keyOrder) do
    begin
      j := keyOrder[k];
      if not vals[j] then Continue;
      if found then names := names + ',';
      names := names + TyJsonQuote(keys[j]);
      found := True;
    end;
    if all <> '' then all := all + ',';
    all := all + '{"geoIndex":' + IntToStr(gi) + ',"name":[' + names + ']}';
    { updateSelectStatus }
    GeoSyncSelected(gi);
  end;
  SortKeys;
  json := '{"selected":{';
  for k := 0 to High(keyOrder) do
  begin
    j := keyOrder[k];
    if k > 0 then json := json + ',';
    json := json + TyJsonQuote(keys[j]) + ':';
    if vals[j] then json := json + 'true' else json := json + 'false';
  end;
  json := json + '},"allSelected":[' + all + ']';
  if nameD <> nil then json := json + ',"name":' + TyGeoJsJson(nameD);
  json := json + ',"type":"' + evType + '"}';
  if FGeoDirty then InvalidateFrame;
  EmitPayloadEvent(evType, json);
end;

{ highlight / downplay on a geo: allLeaveBlur; per geo the dispatchers of
  the payload's name (a string naming a region group; none for no name),
  a highlight's 'self' focus blurring the component unless notBlur, then
  enterEmphasis / leaveEmphasis with bit 0 (a component's highlight takes
  no highlightKey); the event a copy of the payload }
procedure TTyAdvanceChart.DoGeoHighDown(APayload: TJSONObject);
var
  geos: TTyIntegerArray;
  i, g: Integer;
  geo: TTyGeo;
  nameD: TJSONData;
  isHigh: Boolean;
  t: string;
  ev: TJSONObject;
begin
  t := APayload.Strings['type'];
  isHigh := t = 'highlight';
  StAllLeaveBlur;
  nameD := APayload.Find('name');
  geos := GeoMatch(APayload);
  for i := 0 to High(geos) do
  begin
    if (geos[i] < 0) or (geos[i] > High(FGeos)) then Continue;
    geo := FGeos[geos[i]];
    if (geo = nil) or (nameD = nil) or (nameD.JSONType = jtNull) then Continue;
    if nameD.JSONType = jtString then g := geo.GroupIndexOf(nameD.AsString) else g := -1;
    if g < 0 then Continue;
    if isHigh and geo.GroupFocusSelf(g) and not JsTruthy(APayload.Find('notBlur')) then
      if geo.BlurAll then FGeoDirty := True;
    if isHigh then
    begin
      if geo.EnterEmphasisBy(g, 0) then FGeoDirty := True;
    end
    else if geo.LeaveEmphasisBy(g, 0) then FGeoDirty := True;
  end;
  if FGeoDirty or FStDirty then InvalidateFrame;
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := t;
    EmitPayloadEvent(t, ev.AsJSON);
  finally
    ev.Free;
  end;
end;

{ the frame's applyChangedStates over the geos' elements }
function TTyAdvanceChart.GeoApplyChanged: Boolean;
var i, ppi: Integer; ink: TTyGeoInk;
begin
  Result := False;
  if not FGeoDirty then Exit;
  FGeoDirty := False;
  if Length(FGeos) = 0 then Exit;
  ink := GeoInk;
  ppi := FPaintListPPI;
  if ppi <= 0 then ppi := FLastPPI;
  for i := 0 to High(FGeos) do
    if (FGeos[i] <> nil) and FGeos[i].ApplyStates(ink, ppi) then Result := True;
end;

function TTyAdvanceChart.GeoTipSpec(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
var geo: TTyGeo; opt: TJSONObject; tip: TJSONData;
begin
  geo := FGeos[ADatum.ComponentIndex];
  opt := geo.GroupOpt(ADatum.DataIndex);
  tip := nil;
  if opt <> nil then tip := opt.Find('tooltip');
  Result := TyTooltipSpecOfGeo(FOption, ADatum.ComponentIndex, tip,
    geo.GroupName(ADatum.DataIndex));
end;

{ setTooltipConfig's formatterParams: componentType, name, geoIndex }
function TTyAdvanceChart.GeoTipParams(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
begin
  Result := TyChartBlankParams;
  Result.ComponentType := 'geo';
  Result.ComponentIndex := ADatum.ComponentIndex;
  Result.Name := FGeos[ADatum.ComponentIndex].GroupName(ADatum.DataIndex);
end;

{ _showTooltipContent's text: a handler called with the params, a template
  through formatTpl -- $vars ['name']: the first a-placeholder becomes a0,
  the first a0 the name, encoded -- or the content (the name) where no formatter
  is in force }
function TTyAdvanceChart.GeoTipText(const ADatum: TTyChartDatumRef;
  const ASpec: TTyTooltipSpec): string;
var
  nm, tpl: string;
  params: TTyChartParams;
begin
  nm := FGeos[ADatum.ComponentIndex].GroupName(ADatum.DataIndex);
  if not ASpec.HasFormatter then Exit(nm);
  if TyChartIsHandlerRef(ASpec.Formatter) then
  begin
    SetLength(params, 1);
    params[0] := GeoTipParams(ADatum);
    TyChartResolveText(ASpec.Formatter, params, Result);
    Exit;
  end;
  tpl := TyJsReplaceFirst(ASpec.Formatter, '{a}', '{a0}');
  Result := TyJsReplaceFirst(tpl, '{a0}', GeoEncodeHtml(nm));
end;

procedure TTyAdvanceChart.SolveCalendars(APPI: Integer);
var i, n: Integer;
begin
  FreeCalendars;
  n := 0;
  if FOption <> nil then n := FOption.ComponentCount('calendar');
  if n = 0 then Exit;
  SetLength(FCalendars, n);
  for i := 0 to n - 1 do
  begin
    FCalendars[i] := TTyCalendar.Create(TyCalendarSpecOf(FOption, i));
    FCalendars[i].Resize(FLastRect, APPI);
  end;
end;

{ THE CALENDAR'S INK, from keys the chart already has: a day cell is the
  ground an empty symbol is filled with, its border an axis split line; the
  month lines are an axis line, the day and month names axis labels, and the
  year the subtitle's quieter ink. Upstream's own tokens for them are the
  same neutrals those keys default to. }
function TTyAdvanceChart.CalendarInk: TTyCalendarInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  Result := Default(TTyCalendarInk);
  model := ActiveController.Model;
  Result.CellFill := TTyChartColor(
    model.ResolveStyle('TyAdvChartEmptyCircle', '', []).Background.Color);
  Result.CellBorder := TTyChartColor(
    model.ResolveStyle('TyAdvChartSplitLine', '', []).BorderColor);
  Result.SplitLine := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisLine', '', []).BorderColor);
  st := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  Result.LabelColour := TTyChartColor(st.TextColor);
  Result.LabelFontName := st.FontName;
  Result.LabelFontSizeLogical := ResolveFontSize(st);
  Result.LabelFontWeight := st.FontWeight;
  st := model.ResolveStyle('TyAdvChartSubtitle', '', []);
  Result.YearColour := TTyChartColor(st.TextColor);
  Result.YearFontName := st.FontName;
end;

procedure TTyAdvanceChart.FreeMatrices;
var i: Integer;
begin
  for i := 0 to High(FMatrices) do FreeAndNil(FMatrices[i]);
  FMatrices := nil;
end;

{ THE MATRICES, one per component, from the option [Batch 145] }
procedure TTyAdvanceChart.BuildMatrices;
var i, n: Integer;
begin
  FreeMatrices;
  n := 0;
  if FOption <> nil then n := FOption.ComponentCount(TyMatrixCoordSysName);
  SetLength(FMatrices, n);
  for i := 0 to n - 1 do
    FMatrices[i] := TTyMatrix.Create(FOption, i);
end;

{ each laid out on the whole canvas, as upstream's is: getLayoutRect
  against the chart's width and height [Batch 145] }
procedure TTyAdvanceChart.SolveMatrices(APPI: Integer);
var i: Integer;
begin
  for i := 0 to High(FMatrices) do
    if FMatrices[i] <> nil then FMatrices[i].Resize(FLastRect, APPI);
end;

{ THE MATRIX'S INK, from keys the chart already has: a cell border is an
  axis split line, a divider and the outer border an axis line, a label an
  axis label's ink. Upstream's tokens for them (borderTint, border,
  axisLine, secondary) are the same neutrals. [Batch 145] }
function TTyAdvanceChart.MatrixInk: TTyMatrixInk;
var model: TTyStyleModel;
begin
  Result := Default(TTyMatrixInk);
  model := ActiveController.Model;
  Result.CellBorder := TTyChartColor(
    model.ResolveStyle('TyAdvChartSplitLine', '', []).BorderColor);
  Result.Divider := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisLine', '', []).BorderColor);
  Result.OuterBorder := Result.Divider;
  Result.LabelColour := TTyChartColor(
    model.ResolveStyle('TyAdvChartAxisLabel', '', []).TextColor);
end;

function TTyAdvanceChart.CalendarLayout(AIndex: Integer): TTyCalendar;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FCalendars)) then
    Result := FCalendars[AIndex];
end;

function TTyAdvanceChart.MatrixLayout(AIndex: Integer): TTyMatrix;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FMatrices)) then
    Result := FMatrices[AIndex];
end;

function TTyAdvanceChart.GeoCount: Integer;
begin
  Result := Length(FGeos);
end;

function TTyAdvanceChart.GeoLayout(AIndex: Integer): TTyGeo;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FGeos)) then
    Result := FGeos[AIndex];
end;

function TTyAdvanceChart.GeoLinesPoint(const AX, AY: TTyLinesValue): TTyPointF;
var
  geo: TTyGeo;
  x, y: Double;

  function JsNum(const AV: TTyLinesValue): Double;
  begin
    case AV.Kind of
      lvkNumber: Result := AV.Num;
      lvkString: Result := TyJsToNumber(AV.Str);
      lvkNull: Result := 0;
    else
      Result := NaN;
    end;
  end;

begin
  Result := TyPointF(NaN, NaN);
  geo := GeoOfSlot(FLnSlot);
  if geo = nil then Exit;
  x := JsNum(AX);
  y := JsNum(AY);
  if not geo.PointOf(x, y, Result) then Result := TyPointF(NaN, NaN);
end;

{ WHERE A GRAPH'S NODES GO ON A CALENDAR, by raw index.

  UPSTREAM BUILDS A GRAPH'S DATA WITH PLAIN DIMENSION NAMES, so the node's
  date is not a time dimension: its type is GUESSED from the first node
  that decides it (guessOrdinal -- a finite number or numeric string says
  float, any other string but '-' says ordinal). An ordinal column keeps
  each date as written; a float one turns a date string into NaN.
  simpleLayout then places a node when ANY of its stored dimensions is a
  number -- and isNaN of a date string is true -- at the calendar's
  dataToPoint of the stored date, which the calendar parses itself. So a
  string-dated node with no numeric value is not placed at all, and after
  a first node dated by a timestamp every string-dated node is lost.
  [Batch 72] }
function TTyAdvanceChart.CalendarGraphPoints(ASeriesIndex: Integer;
  ACal: TTyCalendar): TTyPointFArray;
var
  node, d, it, arr, t0, v0: TJSONData;
  k, decided: Integer;
  floatTime, hasValue: Boolean;
  tNum, vNum, ms: Double;
  dv: TTyDataValue;

  function DateOf(AItem: TJSONData): TJSONData;
  begin
    Result := nil;
    arr := AItem;
    if (arr <> nil) and (arr.JSONType = jtObject) then arr := TJSONObject(arr).Find('value');
    if (arr <> nil) and (arr.JSONType = jtArray) and (arr.Count > 0) then
      Result := arr.Items[0];
  end;

  function NumOf(AData: TJSONData): Double;
  begin
    Result := NaN;
    if AData = nil then Exit;
    case AData.JSONType of
      jtNumber: Result := AData.AsFloat;
      jtString:
        if (AData.AsString <> '') and (AData.AsString <> '-') then
          Result := TyJsToNumber(AData.AsString);
    end;
  end;

begin
  Result := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then d := TJSONObject(node).Find('nodes');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  { the guess: the first decisive date among the first five }
  floatTime := True;
  decided := 0;
  for k := 0 to Min(d.Count, 5) - 1 do
  begin
    t0 := DateOf(d.Items[k]);
    if (t0 = nil) or (t0.JSONType = jtNull) then Continue;
    if (t0.JSONType = jtString) and ((t0.AsString = '-') or (t0.AsString = '')) then Continue;
    if (t0.JSONType = jtNumber) or ((t0.JSONType = jtString)
      and not IsNan(TyJsToNumber(t0.AsString)) and not IsInfinite(TyJsToNumber(t0.AsString))) then
      floatTime := True
    else
      floatTime := False;
    decided := 1;
    Break;
  end;
  if decided = 0 then floatTime := True;
  SetLength(Result, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    Result[k] := TyPointF(NaN, NaN);
    it := d.Items[k];
    t0 := DateOf(it);
    v0 := nil;
    if (arr <> nil) and (arr.JSONType = jtArray) and (arr.Count > 1) then v0 := arr.Items[1];
    vNum := NumOf(v0);
    { the stored date: a number either way; a string kept (ordinal) or not a
      number (float) }
    tNum := NaN;
    ms := NaN;
    if t0 <> nil then
    begin
      if t0.JSONType = jtNumber then
      begin
        tNum := t0.AsFloat;
        ms := tNum;
      end
      else if t0.JSONType = jtString then
      begin
        if floatTime then
        begin
          tNum := NumOf(t0);
          ms := tNum;
        end
        else
        begin
          dv := Default(TTyDataValue);
          dv.Kind := dvkText;
          dv.Text := t0.AsString;
          ms := ACal.ParseDate(dv);
        end;
      end;
    end;
    hasValue := not IsNan(tNum) or not IsNan(vNum);
    if not hasValue then Continue;
    Result[k] := ACal.DatePoint(ms, True);
  end;
end;

{ A GRAPH ON A MATRIX [Batch 147]: createSeriesData with the matrix's
  dimensions -- x and y ordinal on the trees' category lists (a name its
  ordinal or nothing, a number as it is), the value a number -- and
  graphSimpleLayout: a node with any of the three a number is placed at
  dataToPoint([x, y]), the others nowhere. }
function TTyAdvanceChart.MatrixGraphPoints(ASeriesIndex: Integer;
  AMatrix: TTyMatrix): TTyPointFArray;
var
  node, d, it, arr: TJSONData;
  k: Integer;
  x, y, v: Double;

  function Part(AIndex: Integer): TJSONData;
  begin
    Result := nil;
    if (arr is TJSONArray) and (AIndex < arr.Count) then Result := arr.Items[AIndex]
    else if (AIndex = 0) and (arr <> nil) and not (arr is TJSONArray)
      and not (arr is TJSONObject) then Result := arr;
  end;

  function Ord_(ADim: Integer; A: TJSONData): Double;
  var o: Integer;
  begin
    Result := NaN;
    if A = nil then Exit;
    case A.JSONType of
      jtNumber: Result := A.AsFloat;
      jtString:
        begin
          o := AMatrix.Dims[ADim].Meta.GetOrdinal(A.AsString);
          if o >= 0 then Result := o;
        end;
    end;
  end;

  function Num(A: TJSONData): Double;
  begin
    Result := NaN;
    if A = nil then Exit;
    case A.JSONType of
      jtNumber: Result := A.AsFloat;
      jtString:
        if (A.AsString <> '') and (A.AsString <> '-') then Result := TyJsToNumber(A.AsString);
    end;
  end;

begin
  Result := nil;
  node := FOption.ComponentAt('series', ASeriesIndex);
  if (node = nil) or (node.JSONType <> jtObject) then Exit;
  d := TJSONObject(node).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then d := TJSONObject(node).Find('nodes');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  SetLength(Result, d.Count);
  for k := 0 to d.Count - 1 do
  begin
    Result[k] := TyPointF(NaN, NaN);
    it := d.Items[k];
    arr := it;
    if it is TJSONObject then arr := TJSONObject(it).Find('value');
    x := Ord_(0, Part(0));
    y := Ord_(1, Part(1));
    v := Num(Part(2));
    if IsNan(x) and IsNan(y) and IsNan(v) then Continue;
    Result[k] := AMatrix.DataToPoint([x, y]);
  end;
end;

function TTyAdvanceChart.GeoSvgMeasure(const AText: string; const AFont: TTyGsFont): Double;
var fam: string; p, wt: Integer; w, h, v: Double;
begin
  if FGeoSvgMeas = nil then FGeoSvgMeas := NewTextMeasurer(96);
  fam := AFont.Family;
  p := Pos(',', fam);
  if p > 0 then fam := Copy(fam, 1, p - 1);
  fam := Trim(fam);
  if (Length(fam) >= 2) and (fam[1] in ['''', '"']) then fam := Copy(fam, 2, Length(fam) - 2);
  wt := 400;
  if (AFont.Weight = 'bold') or (AFont.Weight = 'bolder') then wt := 700
  else if AFont.Weight = 'lighter' then wt := 300
  else
  begin
    v := TyJsToNumber(AFont.Weight);
    if not IsNan(v) and (v > 0) then wt := Round(v);
  end;
  w := 0;
  h := 0;
  FGeoSvgMeas.MeasureLine(AText, fam, TyFontSizeFromPx(AFont.SizePx), wt, w, h);
  Result := w;
end;
