{ Part of tyControls.AdvanceChart (included, not a unit): construction and destruction,
  the option API (setOption, the merge, media queries, the diagnostics) and invalidation.
  Moved out of the unit only to keep it readable; what the control is and why it is built
  the way it is, see the unit header. }

{ ==================== construction ==================== }

constructor TTyAdvanceChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOption := TTyChartOption.Create;
  FLegendSelHoverLegend := -1;
  FLegendSelHoverIdx := -1;
  FIndex := TTyAxisSeriesIndex.Create;
  FAxisMemory := TTyAxisMemoryStore.Create;
  FDirty := True;
  FTipDatum := TyChartNoDatum;
  FTipElement := -1;
  FTipNow := NaN;
  FTipShowAt := NaN;
  FTipHideAt := NaN;
  FTipLastX := NaN;
  FTipLastY := NaN;
  FTipKeepAt := NaN;
  FTipBox := TyInvalidRectF;
  FTipRect := TyInvalidRectF;
  { what upstream's canvas starts as [F6a] }
  FCursorName := 'default';
  Width := 320;
  Height := 200;
  TabStop := False;   { see the published declaration }
  { the keyboard and the accessible tree [Batch 144] }
  FKbSeries := -1;
  FKbRow := -1;
  FKbStop := TyKbStop(ksItems, 0, 0);
  FKbPart := -1;
  FKbGeoIndex := -1;
  FAccGen := -1;
  FAccLink := TTyAccessibleLink.Create(Self);
  AccessibleRole := larChart;
  AccessibleName := rsTyChartTypeChart;
  FRoamSeries := -1;
  FRoamGeo := -1;
  FGraphDragSlot := -1;
  FSankeyDragSlot := -1;
  FCrumbPressSeries := -1;
  FTmCrumbHoverS := -1;
  FTmCrumbHoverK := -1;
  FDzFrom := -1;
  FDzPanGrid := -1;
  FDzNow := NaN;
  FAnimNow := NaN;
  FAnimMode := camAuto;
  FProgStepCost := NaN;
  FPauseClock := TTyAnimation.Create;
  FLineHist := TStringList.Create;
  FLineHist.NameValueSeparator := #1;
  FGfxAnim := NewAnimDriver;
  FGfxView := TTyGfxView.Create;
  FGfxView.Animation := FGfxAnim;
  FGfxUnder := TTyPaintList.Create;
  FCuAnim := NewAnimDriver;
  FGfxW := NaN;
  FGfxH := NaN;
  FTbStatus := TStringList.Create;
  FTbBrushGrid := -1;
  FBrushNow := NaN;
  FParBrushSkip := -1;
  FBrushTickPrev := NaN;
  FTlNow := NaN;
  FTlDue := NaN;
  { [Batch 140] }
  FParExpNow := NaN;
  FThumbOwner := -1;
  FThumbDrag := -1;
  { an instance from now on [Batch 141] }
  FConnectStatus := -1;
  { the init options' defaults [Batch 142] }
  FCoarsePointer := ccpAuto;
  FPointerSize := cTyDefaultPointerSize;
  Inc(GTyChartSeq);
  FInstanceNo := GTyChartSeq;
  FPressEl := -1;
  if GTyCharts = nil then GTyCharts := TFPList.Create;
  GTyCharts.Add(Self);
end;

destructor TTyAdvanceChart.Destroy;
var i: Integer;
begin
  { dispose: no longer an instance [Batch 141] }
  if GTyCharts <> nil then GTyCharts.Remove(Self);
  { an action still waiting [Batch 153] }
  ActDropPending;
  { THE PLATFORM LINK FIRST: the window is still there to unhook, and a
    node a client holds stops reaching this control [Batch 144] }
  FreeAndNil(FAccLink);
  { Order is a contract, not a habit: a store BORROWS its category list from an
    axis the build owns, so every store goes first. }
  DropBuild;
  FreeAndNil(FPaintList);
  FreeGeoSel;
  FreeAndNil(FIndex);
  FreeAndNil(FAxisMemory);
  FSources := nil;
  FreeAndNil(FDatasetCache);
  FreeAndNil(FJitter);
  FreeAndNil(FOption);
  FreeAndNil(FTbStatus);
  FreeAndNil(FResolvedImages);
  { The static layer owns a TBitmap. TTyPaintCache.Drop only marks it stale --
    it keeps the surface deliberately, for reuse -- so dropping is not freeing. }
  FreeAndNil(FStatic);
  { the dirty-rect path's surfaces, and a flush still queued [Batch 142] }
  if FDrQueued and (Application <> nil) then Application.RemoveAsyncCalls(Self);
  FreeAndNil(FDrWork);
  FreeAndNil(FDrBase);
  FreeAndNil(FDrDyn);
  FreeAndNil(FProgLayer);
  FreeAndNil(FTrailLayer);
  FreeAndNil(FDzTimer);
  BrushReset;
  BrushFreeCtl(FTbBrushCtl);
  ParBrushFree;
  FreeAndNil(FBrushTimer);
  FreeAndNil(FParExpTimer);
  FreeAndNil(FTipTimer);
  { THE PROXIES BEFORE THE DRIVER: freeing one takes its clips off it }
  FreeAndNil(FAnimTimer);
  AxisAnimDrop;
  TmAnimDropAll;
  FreeAndNil(FAxisProxies);
  FreeAndNil(FAxisList);
  FreeAndNil(FAnimSet);
  FreeAndNil(FParSeen);
  FreeAndNil(FAnim);
  FreeAndNil(FAnimFrame);
  FreeAndNil(FAnimSplit);
  PtrAnimDrop;
  FreeAndNil(FPtrProxies);
  FreeAndNil(FPtrAnim);
  LegAnimDrop;
  FreeAndNil(FLegAnim);
  { the indicator's bags before their driver [Batch 116] }
  VmEnsure(0);
  FreeAndNil(FVmAnim);
  { THE ARC BEFORE ITS DRIVER, as every proxy [Batch 106] }
  LoadDrop;
  FreeAndNil(FLoadAnim);
  FreeAndNil(FAnimOldBuild);
  { THE ELEMENTS BEFORE THEIR DRIVER [Batch 122] }
  FGfxPaintEl := nil;
  FreeAndNil(FGfxView);
  { the timeline's too [Batch 129] }
  FreeAndNil(FTlTimer);
  FreeAndNil(FTlView);
  FreeAndNil(FTlAnim);
  for i := 0 to High(FCustomViews) do FreeAndNil(FCustomViews[i]);
  FCustomViews := nil;
  FCustomPaintEls := nil;
  FreeAndNil(FGfxModel);
  FreeAndNil(FGfxAnim);
  { after the custom views, whose elements' animators it drives [Batch 124] }
  FreeAndNil(FCuAnim);
  FreeAndNil(FPauseClock);
  FreeAndNil(FLineHist);
  FreeAndNil(FGfxUnder);
  inherited Destroy;
end;

procedure TTyAdvanceChart.FreeStores;
var i: Integer;
begin
  for i := 0 to High(FStores) do
    FStores[i].Free;
  FStores := nil;
  { [Batch 152] a map series' own data, its store the statistic }
  for i := 0 to High(FMapOrig) do FMapOrig[i].Free;
  FMapOrig := nil;
  FBarCols := nil;
  FPolarBars := nil;
  FRivers := nil;
  FWhiskers := nil;
  FStacks := nil;
end;

procedure TTyAdvanceChart.DropBuild;
begin
  { THE AXIS HOVER GOES FIRST, because it holds TTyAxis POINTERS into the build
    about to be freed. Invalidate clears it too, but Resize sets FDirty without
    going through Invalidate -- so the one place that can be trusted to clear
    it is the one that does the freeing. }
  { [F4b] the axisPointer model keeps its status, value and rows across
    the update: kept as values, put back by the next build }
  TipKeepPointer;
  FTipHits := nil;
  { and the box's snapshots, which hold the same pointers [Batch 100] --
    turned into values: the box stays up across the re-render [F4b] }
  TipFreeze;
  { the hits an action waiting carries hold them too: it falls back on its
    dataByCoordSys [Batch 153] }
  ActForgetHits;
  { the pointer's slide goes with the axes [Batch 92] }
  PtrAnimDrop;
  { AND THE RADARS WITH THEM, for the same reason: a binding holds a radar's
    INDEX, and the spoke objects a paint list was built against are about to
    stop existing. }
  FreeRadars;
  FreeCalendars;
  FreeGeos;
  FreeGraphs;
  FreeTreeViews;
  FreePolars;
  FreeSingles;
  FreeParallels;
  FParSolved := nil;
  FTrees := nil;
  FSunbursts := nil;
  FTreemaps := nil;
  FTreemapInks := nil;
  FSankeys := nil;
  FSankeyInks := nil;
  FChords := nil;
  FChordInks := nil;
  FRadarDims := nil;
  FreeStores;
  { the matrices after the stores, which borrow their category lists
    [Batch 145] }
  FreeMatrices;
  FBindings := nil;
  if FIndex <> nil then FIndex.Clear;
  FreeAndNil(FBuild);
end;

{ ==================== the option ==================== }

{ WHAT WAS WRITTEN, not what parsed. The PROPERTY has to read back what the
  host set, or a half-typed option in the Object Inspector reverts on every
  keystroke that does not yet parse, and a .lfm cannot round-trip work in
  progress.

  The TREE is emptied when the text does not parse -- there is no last-good-one
  kept, deliberately: a control whose property says A while the picture shows B
  has no way to tell anyone which is which. OptionError says what went wrong. }
function TTyAdvanceChart.GetOptionText: string;
begin
  Result := FOptionText;
end;

{ THE PROPERTY IS A DECLARATION, not a setOption: the text it already holds
  is no change. LCL streaming, the Object Inspector and the option editor
  all assign unchanged text, and a legend toggled by a click must not reset
  because of it [Batch 93]. Upstream's notMerge with the same option DOES
  reset everything -- that is SetOption(AJson, True). After a merge the
  property holds the merged option, so assigning the text set before the
  merge is a real change. [Batch 95] }
function TySetOptionOptsOf(const AJson: string; out AOpts: TTySetOptionOpts): Boolean;
var
  d, r: TJSONData;
  o: TJSONObject;
  k, nLine, nCol: Integer;

  function Truthy(A: TJSONData): Boolean;
  begin
    if (A = nil) or (A.JSONType = jtNull) then Exit(False);
    case A.JSONType of
      jtBoolean: Result := A.AsBoolean;
      jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
      jtString: Result := A.AsString <> '';
    else
      Result := True;
    end;
  end;

  procedure AddType(A: TJSONData);
  var n: Integer;
  begin
    { normalizeToArray, each entry a main type as it is named -- anything
      but a string is named by its text, and so is refused }
    n := Length(AOpts.ReplaceMerge);
    SetLength(AOpts.ReplaceMerge, n + 1);
    if A.JSONType = jtString then AOpts.ReplaceMerge[n] := A.AsString
    else AOpts.ReplaceMerge[n] := A.AsJSON;
  end;

begin
  AOpts := Default(TTySetOptionOpts);
  if Trim(AJson) = '' then Exit(True);
  { too deep is refused before fpjson can recurse into it }
  if TyJsonNestingExceeds(AJson, TyOptionMaxNesting, nLine, nCol) then Exit(False);
  try
    d := GetJSON(AJson);
  except
    d := nil;
  end;
  if not (d is TJSONObject) then
  begin
    d.Free;
    Exit(False);
  end;
  o := TJSONObject(d);
  try
    AOpts.NotMerge := Truthy(o.Find('notMerge'));
    AOpts.LazyUpdate := Truthy(o.Find('lazyUpdate'));
    AOpts.Silent := Truthy(o.Find('silent'));
    { [F3c] the universal transition's series }
    TyUtParseTransition(o.Find('transition'), AOpts.HasTransition, AOpts.Transition);
    r := o.Find('replaceMerge');
    if r <> nil then
    begin
      if r.JSONType = jtArray then
      begin
        for k := 0 to r.Count - 1 do AddType(r.Items[k]);
      end
      else
        AddType(r);
    end;
  finally
    o.Free;
  end;
  Result := True;
end;

procedure TTyAdvanceChart.SetOptionText(const AValue: string);
begin
  if FOptionText = AValue then Exit;
  { [F3c] a setOption with no transition option }
  FAnimUtHas := False;
  FAnimUtTrans := nil;
  ApplyNotMerge(AValue);
  AfterSetOption(False, False);
end;

procedure TTyAdvanceChart.ApplyNotMerge(const AValue: string);
begin
  ApplyNotMerge(AValue, []);
end;

procedure TTyAdvanceChart.ApplyNotMerge(const AValue: string;
  const AReplace: array of string);
var i: Integer;
begin
  FOptionText := AValue;
  { [F4b] new models, a new tooltip view: the old one's box, last point and
    the axisPointer models' state go with it }
  TipForget;
  { [R2-E] and every axis' own status 'show' holds again }
  FOptPtrGone := False;
  FOptPtrBack := nil;
  { EVERY visualMap VIEW GOES with its model [Batch 116] }
  VmDisposeAll;
  { THE OLD OPTION'S SERIES VIEWS, before the text goes: an update keeps a
    series whose view id and type are the same -- unless an update already
    waits, whose old render is still the one before it [Batch 90] -- or a
    lazy one does [Batch 97] }
  if not FAnimPrev.Valid and not FLazyPending then
  begin
    FAnimOldViewKeys := AnimViewKeys;
    FAnimOldUtKeys := AnimUtKeys;
  end;
  { new models: none asks for a new view (initBase ignores replaceMerge) }
  FAnimFresh := nil;
  { new thumbnail models: their optionUpdated (in the merge pass) decides
    the bridge afresh; no drag survives [Batch 140] }
  FThumbs := nil;
  FThumbOwner := -1;
  FThumbDrag := -1;
  FThumbFresh := True;
  { the state records the reused elements keep, while the old option and
    its stores are still there [Batch 96] }
  StCarryTake(AnimViewKeys);
  { a full update or a merge still waiting: its models are the option's
    about to go, and what it arms now is a notMerge update [Batch 96] }
  if FAnimPrev.FullUpdate or FAnimPrev.Merge then
  begin
    FAnimPrev.FullUpdate := False;
    FAnimPrev.Merge := False;
    for i := 0 to High(FAnimPrev.Series) do
      FAnimPrev.Series[i].Model := TyAnimNoModel;
  end;
  FAnimFull := False;
  { new models: every component view is new, no axis transitions [Batch 99] }
  FAnimMerge := False;
  FAnimFreshAxes := nil;
  FAnimHasPayload := False;
  { the media are asked at the control's size [Batch 107] }
  MediaViewSize;
  { a new graphic model, from the fresh tree [Batch 122] }
  FGfxFresh := True;
  FOption.SetOptionText(AValue, AReplace, @NotMergePass);
  { no media merge reached the thumbnails: their init's optionUpdated
    [Batch 140] }
  if FThumbFresh then ThumbInitAll;
  if FGfxFresh then GfxInitFromTree;
  { A NEW GlobalModel: a new decal scope, and aria on where the option
    wrote an aria object [Batch 131] }
  FDecalScope := Default(TTyDecalScope);
  AriaTakeEnabled(FOption.Root, True);
  { new axis models and views: nothing kept from the last render
    [Batch 101] }
  FAxisMemory.Clear;
  { new dataset models: their transforms run again, drawing from where the
    chart's stream stands now [Batch 134] }
  FTransformSeedTaken := False;
  { new parallelAxis models: no active intervals [Batch 128]; new views,
    new controllers [Batch 130] }
  FParIntervals := nil;
  ParBrushFree;
  FGraphForce := nil;
  { notMerge: new series models, so no roam survives either, nor a toggle. }
  FGraphRoam := nil;
  FTreeToggled := nil;
  { [R2-C] new series models, new data: the next update's trees are new }
  FAnimDataFresh := True;
  FTreeRoam := nil;
  FTreeBox := nil;
  FTreeBoxHas := nil;
  { new series models: new trees, so no view root [Batch 115] }
  HierDrillReset;
  FPressArmed := False;
  FRoamSeries := -1;
  FGraphDragSlot := -1;
  FSankeyDragSlot := -1;
  { a sankey's dragNode positions and its roam are written into its series
    option upstream: a new series model has neither [Batch 114] }
  FSankeyLocal := nil;
  FSankeyRoam := nil;
  { nor a zoom: the dataZooms are new models, read from what was written }
  FDzRawHas := nil;
  FDzRawStart := nil;
  FDzRawStop := nil;
  FDzRawValue := nil;
  FDzState := nil;
  { THE TOOLBOX'S STATE goes with the option: the iconStatus and the titles
    written into it, the select dataZooms' windows, the GlobalModel's
    history, and the view [Batch 125] }
  FTbBackup := AValue;
  { new models ask for new views (__requireNewView): the toolbox's view
    starts where a first render does, with new features -- the zoom off }
  FTbPrev := nil;
  FTbZoomActive := False;
  if FTbStatus <> nil then FTbStatus.Clear;
  FTbMagicTitle := nil;
  FTbSel := nil;
  FTbHistory := nil;
  { the feature's view is new: its select brush too [Batch 127] }
  BrushFreeCtl(FTbBrushCtl);
  FTbBfSnap := False;
  FDzRoamThrottle := nil;
  FDzRoamBatch := nil;
  FDzHover := Default(TTyDzTarget);
  FDzDrag := Default(TTyDzTarget);
  FDzHasDown := False;
  FDzPanGrid := -1;
  { THE BRUSH COMPONENTS: new models (no areas, no painting option) and new
    views (no covers) [Batch 126] }
  BrushReset;
  { THE TIMELINE'S VIEW goes with its model: its timer and its checkpoint
    with it [Batch 129] }
  FreeAndNil(FTlView);
  FTlDue := NaN;
  FTlDragging := False;
  FTlStatesDirty := False;
  TlArmTimer;
  { new series models: no selection [Batch 88]. AN ELEMENT SURVIVES where
    the view and the row do: upstream diffs the new data against the old
    and keeps its hoverState and __highByOuter bits [Batch 96] }
  FSel := nil;
  { new geo models: optionUpdated makes their selectedMap again [Batch 148] }
  FreeGeoSel;
  { and hold no written-back roam; a drag ends [Batch 150] -- the map
    series' too [Batch 152] }
  FGeoRoam := nil;
  FMapRoam := nil;
  FRoamGeo := -1;
  { AND WHAT THE POINTER IS OVER IS A REMOVED ELEMENT: the next move finds a
    new one there -- an out to the old, an over to the new, as zrender's
    hover meets elements a notMerge setOption replaced. Its identity is
    made one no element answers. }
  if FEvHover.Id <> 0 then FEvHover.Id := Low(Int64);
  FSelInit := nil;
  FSt := nil;
  FStDirty := False;
  { new legend models: init and optionUpdated run again [Batch 93] }
  FLegendLoaded := False;
  { and new legend views: a first render again [Batch 98] }
  LegAnimDrop;
  { A NEW OPTION ENTERS: the next render that may animate plays it }
  FAnimPending := True;
  FDirty := True;
  Invalidate;
end;

function TTyAdvanceChart.GetErrorText: string;
begin
  Result := FOption.Error.Message;
end;

procedure TTyAdvanceChart.SetOption(const AJson: string; ANotMerge: Boolean);
var o: TTySetOptionOpts;
begin
  o := Default(TTySetOptionOpts);
  o.NotMerge := ANotMerge;
  SetOption(AJson, o);
end;

function TTyAdvanceChart.SetOption(const AJson: string;
  const AOpts: TTySetOptionOpts): Boolean;
begin
  TbFrame;
  { normalizeSetOptionInput asserts before anything is touched }
  if not FOption.CheckReplaceMerge(AOpts.ReplaceMerge) then Exit(False);
  { THE FIRST OPTION is an init whatever the flag says (echarts.ts:768),
    and an init ignores replaceMerge (initBase merges with no opts) }
  if AOpts.NotMerge or not (FOption.Root is TJSONObject) then
  begin
    ApplyNotMerge(AJson, AOpts.ReplaceMerge);
    Result := not FOption.Error.Failed;
  end
  else
    Result := DoMerge(AJson, AOpts.ReplaceMerge);
  if Result then
  begin
    { [F3c] the update's transition option: this setOption's }
    FAnimUtHas := AOpts.HasTransition;
    FAnimUtTrans := AOpts.Transition;
    AfterSetOption(AOpts.LazyUpdate, AOpts.Silent);
  end;
end;

function TTyAdvanceChart.SetOption(const AJson, AOptsJson: string): Boolean;
var
  o: TTySetOptionOpts;
  nLine, nCol: Integer;
begin
  if TyJsonNestingExceeds(AOptsJson, TyOptionMaxNesting, nLine, nCol) then
  begin
    FOption.Refuse(Format(rsTyOptTooDeep, [TyOptionMaxNesting]));
    Exit(False);
  end;
  if not TySetOptionOptsOf(AOptsJson, o) then
  begin
    FOption.Refuse(rsTyOptSetOptsNotObject);
    Exit(False);
  end;
  Result := SetOption(AJson, o);
end;

function TTyAdvanceChart.MergeOption(const AJson: string): Boolean;
begin
  Result := SetOption(AJson, Default(TTySetOptionOpts));
end;

function TTyAdvanceChart.DoMerge(const AJson: string;
  const AReplace: array of string): Boolean;
var
  rep: TTyMergeReport;
begin
  { the old views, before the merge renames anything }
  FMergeOldKeys := AnimViewKeys;
  FMergeOldUtKeys := AnimUtKeys;
  FMergeOldAxes := AxisViewKeys;
  FMergeFirst := True;
  FMergeResize := False;
  { the media are asked at the control's size [Batch 107] }
  MediaViewSize;
  { THE MERGES: the base, then every media unit that applies, each
    reported to MergePass [Batch 107] }
  if not FOption.MergeOptionText(AJson, AReplace, @MergeBefore, @MergePass, rep) then
    Exit(False);
  { the preprocessor runs on the piece: a `show` or an `enabled` it wrote
    [Batch 131] }
  AriaTakeEnabled(FOption.MergedPiece, False);
  { A PIECE THAT CARRIES `dataset` marks every dataset dirty: their
    transforms run again from where the chart's stream stands [Batch 134] }
  if (FOption.MergedPiece is TJSONObject)
    and (TJSONObject(FOption.MergedPiece).Find('dataset') <> nil) then
    FTransformSeedTaken := False;
  { [R2-E] the axes whose status the piece writes again }
  OptPtrTakePiece(FOption.MergedPiece);
  FOptionText := FOption.OptionJson;
  { AN UPDATE: the series keep their views where their ids and types do }
  FAnimPending := True;
  FDirty := True;
  Invalidate;
  Result := True;
end;

procedure TTyAdvanceChart.MergePass(const AReport: TTyMergeReport);
var si, s, t: Integer;
begin
  if FMergeFirst then
  begin
    FMergeFirst := False;
    if not FMergeResize then
    begin
      { the views the next update pairs with: the last render's -- unless an
        update already waits (an old render kept) or a lazy one does }
      if not FAnimPrev.Valid and not FLazyPending then
      begin
        FAnimOldViewKeys := FMergeOldKeys;
        FAnimOldUtKeys := FMergeOldUtKeys;
        FAnimFresh := nil;
        FAnimOldAxisKeys := FMergeOldAxes;
        FAnimFreshAxes := nil;
      end;
      { A MERGE KEEPS ITS MODELS, and their views [Batch 99] -- unless a
        notMerge waits: then the models are new against the render it starts
        from, and so is every component view }
      if not FAnimPending or FAnimFull or FAnimMerge then FAnimMerge := True;
    end;
    { THE STATE RECORDS a reused element keeps: its hoverState, its
      __highByOuter bits, its select (the model keeps its selectedMap)
      [Batch 99] -- by the old view keys, read before the merge }
    StCarryTake(FMergeOldKeys);
  end;
  { an axis brought in by index is brand new: a new view }
  for t := 0 to 1 do
  begin
    if t = 0 then si := TyMergeSlotsIndex(AReport, 'xAxis')
    else si := TyMergeSlotsIndex(AReport, 'yAxis');
    if si < 0 then Continue;
    for s := 0 to High(AReport.Slots[si].Brand) do
      if AReport.Slots[si].Brand[s] then
      begin
        { a new model in the slot: its memory starts over [Batch 101] }
        if t = 0 then FAxisMemory.Forget('xAxis' + IntToStr(s))
        else FAxisMemory.Forget('yAxis' + IntToStr(s));
        SetLength(FAnimFreshAxes, Length(FAnimFreshAxes) + 1);
        if t = 0 then FAnimFreshAxes[High(FAnimFreshAxes)] := 'xAxis' + IntToStr(s)
        else FAnimFreshAxes[High(FAnimFreshAxes)] := 'yAxis' + IntToStr(s);
      end;
  end;
  { a polar axis brought in new starts its memory over too [Batch 111] }
  for t := 0 to 1 do
  begin
    if t = 0 then si := TyMergeSlotsIndex(AReport, 'angleAxis')
    else si := TyMergeSlotsIndex(AReport, 'radiusAxis');
    if si < 0 then Continue;
    for s := 0 to High(AReport.Slots[si].Brand) do
      if AReport.Slots[si].Brand[s] then
      begin
        if t = 0 then FAxisMemory.Forget('angleAxis' + IntToStr(s))
        else FAxisMemory.Forget('radiusAxis' + IntToStr(s));
      end;
  end;
  { and a single axis [Batch 118] }
  si := TyMergeSlotsIndex(AReport, TySingleCoordSysName);
  if si >= 0 then
    for s := 0 to High(AReport.Slots[si].Brand) do
      if AReport.Slots[si].Brand[s] then
        FAxisMemory.Forget(TySingleCoordSysName + IntToStr(s));
  { a parallelAxis brought in new: a new model, no active intervals, its
    memory over [Batch 128] }
  si := TyMergeSlotsIndex(AReport, 'parallelAxis');
  if si >= 0 then
    for s := 0 to High(AReport.Slots[si].Brand) do
      if AReport.Slots[si].Brand[s] then
      begin
        FAxisMemory.Forget('parallelAxis' + IntToStr(s));
        if s <= High(FParIntervals) then FParIntervals[s] := nil;
        { its view is new: a new controller [Batch 130] }
        if s <= High(FParBrushCtls) then FreeAndNil(FParBrushCtls[s]);
      end;
  { A BRAND NEW MODEL ASKS FOR A NEW VIEW, whatever id it made (a removed
    model's, often) -- until the update that pairs the views [Batch 97] }
  NotMergePass(AReport);
  MergeKeepStates(AReport);
end;

procedure TTyAdvanceChart.NotMergePass(const AReport: TTyMergeReport);
var si, s, n, k: Integer;
begin
  { the graphic model's optionUpdated [Batch 122] }
  GfxPass(AReport);
  { EVERY THUMBNAIL MODEL THE MERGE REACHED, in index order: its
    optionUpdated clears every series' bridge and injects its own (the last
    one that shows and finds a graph keeps it) -- a merge that writes the
    series reaches them too, as dependents [Batch 140] }
  { a new option's models first: their init's optionUpdated }
  if FThumbFresh then ThumbInitAll;
  si := TyMergeSlotsIndex(AReport, TyThumbnailComponent);
  if si >= 0 then
  begin
    n := FOption.ComponentCount(TyThumbnailComponent);
    k := Length(FThumbs);
    SetLength(FThumbs, n);
    for s := k to n - 1 do
    begin
      FThumbs[s] := Default(TTyThumbState);
      FThumbs[s].Target := -1;
    end;
    if (FThumbOwner >= n) then FThumbOwner := -1;
    for s := 0 to High(AReport.Slots[si].Fate) do
      if (s < n) and TyMergeHasModel(AReport.Slots[si].Fate[s]) then
        ThumbOptionUpdated(s);
  end;
  si := TyMergeSlotsIndex(AReport, 'series');
  if si >= 0 then
    for s := 0 to High(AReport.Slots[si].Brand) do
      if AReport.Slots[si].Brand[s] then
      begin
        if s > High(FAnimFresh) then SetLength(FAnimFresh, s + 1);
        FAnimFresh[s] := True;
      end;
end;

procedure TTyAdvanceChart.MediaViewSize;
var ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  FOption.SetViewSize(ClientWidth * 96 / ppi, ClientHeight * 96 / ppi);
end;

function TTyAdvanceChart.MediaRecheck: Boolean;
begin
  Result := False;
  if (FOption = nil) or (csDestroying in ComponentState) then Exit;
  { nothing to ask: no media, or nothing parsed }
  if (FOption.Media.UnitCount = 0) and not FOption.Media.HasDefault then Exit;
  MediaViewSize;
  FMergeOldKeys := AnimViewKeys;
  FMergeOldUtKeys := AnimUtKeys;
  FMergeOldAxes := AxisViewKeys;
  FMergeFirst := True;
  FMergeResize := True;
  try
    Result := FOption.MediaRecheck(@MergeBefore, @MergePass);
  finally
    FMergeResize := False;
  end;
  if not Result then Exit;
  { A RESIZE'S UPDATE: the models kept, merged; nothing armed -- upstream
    runs it with duration 0 -- and the Option property keeps the text
    the host wrote (its media with it) }
  FDirty := True;
  Invalidate;
end;

function TTyAdvanceChart.MediaIndices: TTyMediaIndices;
begin
  Result := Copy(FOption.Media.Current);
end;

procedure TTyAdvanceChart.AfterSetOption(ALazy, ASilent: Boolean);
begin
  { the update renders every parallelAxis view [Batch 130] }
  FParBrushSkip := -1;
  { restorePipelines: the next update's pipelines have no context yet; rows
    appended are in the option the update reads [Batch 119] }
  FProgFresh := True;
  FStreamPending := False;
  { an axis' `axisPointer.status: 'show'` holds again until a pointer moves
    [Batch 100] -- [R2-E] not after any setOption: a merge keeps the
    status a pointer event wrote but where its piece writes one
    (OptPtrTakePiece, DoMerge); new models (ApplyNotMerge) take the
    option's again }
  if ALazy then
  begin
    { the next frame does the update: one pending at a time, its silent the
      last lazy call's }
    FLazyPending := True;
    FLazySilent := ASilent;
    Exit;
  end;
  { a synchronous update takes a pending lazy one with it }
  FLazyPending := False;
  { [R2-E] setOption ends with zr.flush() before its updated: the layout
    now (ConvertReady, as a convertToPixel would) and the flush's
    `rendered` -- and `finished` when nothing is left -- with the paint
    that follows owing nothing. Only where a listener hears them, and only
    once the chart has been laid out at a size. }
  if (FLastPPI > 0) and not (csDesigning in ComponentState)
    and (HasChartHandler('rendered') or HasChartHandler('finished')) then
  begin
    FPaintT0 := AnimClock;
    ConvertReady;
    FFlushDue := True;
    EmitFlush;
  end;
  if not ASilent then EmitUpdated;
end;

procedure TTyAdvanceChart.LazyUpdateDone;
begin
  if not FLazyPending then Exit;
  FLazyPending := False;
  if not FLazySilent then EmitUpdated;
end;

{ `updated`: triggerUpdatedEvent, no params. Only to a handler registered
  for it -- the catch-all OnChartEvent does not count as asking, as with
  the legacy select events [Batch 97] }
procedure TTyAdvanceChart.EmitUpdated;
var
  ev: TTyChartEvent;
  regs: array of TTyChartEventReg;
  i, saved: Integer;
begin
  if FEvSilent > 0 then Exit;
  if not HasChartHandler('updated') then Exit;
  ev := Default(TTyChartEvent);
  ev.EventType := 'updated';
  ev.Params := TyChartBlankParams;
  regs := Copy(FEventRegs);
  { [F4b] outside the cycle }
  saved := FActCycle;
  FActCycle := 0;
  try
    for i := 0 to High(regs) do
      if regs[i].EventType = 'updated' then regs[i].Handler(Self, ev);
  finally
    FActCycle := saved;
  end;
end;

function TTyAdvanceChart.SeriesViewKey(ASeries: Integer): string;
var keys: TTyStringArray;
begin
  keys := AnimViewKeys;
  Result := '';
  if (ASeries < 0) or (ASeries > High(keys)) then Exit;
  Result := keys[ASeries];
  if (ASeries <= High(FAnimFresh)) and FAnimFresh[ASeries] then Result := 'n:' + Result;
end;

function TTyAdvanceChart.SeriesOldViewKey(ASeries: Integer): string;
begin
  Result := '';
  if (ASeries >= 0) and (ASeries <= High(FAnimOldViewKeys)) then
    Result := FAnimOldViewKeys[ASeries];
end;

function TTyAdvanceChart.GetOptionJson: string;
begin
  Result := FOption.OptionJson;
end;

function TTyAdvanceChart.ComponentModelId(const AMainType: string; AIndex: Integer): string;
begin
  Result := FOption.ComponentId(AMainType, AIndex);
end;

function TTyAdvanceChart.ComponentModelName(const AMainType: string; AIndex: Integer): string;
begin
  Result := FOption.ComponentModelName(AMainType, AIndex);
end;

function TTyAdvanceChart.ComponentModelSubType(const AMainType: string; AIndex: Integer): string;
begin
  Result := FOption.ComponentSubType(AMainType, AIndex);
end;

procedure TTyAdvanceChart.MergeBefore(const AMainType: string; AIndex: Integer;
  ANode, ANew: TJSONObject);

  function HasKeys(AData: TJSONData): Boolean;
  begin
    Result := (AData <> nil) and (AData.JSONType in [jtObject, jtArray]) and (AData.Count > 0);
  end;

begin
  { replaceVisualOption [Batch 127]: a merge that writes inBrush or
    outOfBrush with any key replaces both -- the one it does not write goes
    (and optionUpdated's defaults come back) }
  if AMainType = 'brush' then
  begin
    if HasKeys(ANew.Find('inBrush')) or HasKeys(ANew.Find('outOfBrush')) then
    begin
      if ANode.IndexOfName('inBrush') >= 0 then ANode.Delete('inBrush');
      if ANode.IndexOfName('outOfBrush') >= 0 then ANode.Delete('outOfBrush');
    end;
    Exit;
  end;
  if AMainType = 'visualMap' then
  begin
    { setSelected wrote `range` into the model's option: it goes into the
      tree before the merge lands on it [Batch 116] }
    if (AIndex >= 0) and (AIndex <= High(FVmRangeHas)) and FVmRangeHas[AIndex]
      and not (IsNan(FVmRange0[AIndex]) or IsInfinite(FVmRange0[AIndex])
        or IsNan(FVmRange1[AIndex]) or IsInfinite(FVmRange1[AIndex])) then
    begin
      ANode.Arrays['range'] := TJSONArray.Create([FVmRange0[AIndex], FVmRange1[AIndex]]);
      FVmRangeHas[AIndex] := False;
    end;
    { _resetSelected: a piecewise one's `selected` is the new option's own,
      not merged into the old }
    if ANode.Find('selected') <> nil then ANode.Delete('selected');
    if (AIndex >= 0) and (AIndex <= High(FVmSel)) then FVmSel[AIndex] := '';
    Exit;
  end;
  { AN ACTION'S WINDOW is setRawRange's write into the model's option: start
    and end, their values cleared. A merge that writes this dataZoom's range
    lands on it, so it goes into the tree first and leaves the side state. }
  if AMainType <> 'dataZoom' then Exit;
  if (AIndex < 0) or (AIndex > High(FDzRawHas)) or not FDzRawHas[AIndex] then Exit;
  if (ANew.Find('start') = nil) and (ANew.Find('end') = nil)
    and (ANew.Find('startValue') = nil) and (ANew.Find('endValue') = nil)
    and (ANew.Find('rangeMode') = nil) then Exit;
  if (AIndex <= High(FDzRawValue)) and FDzRawValue[AIndex] then
  begin
    { a value action wrote the values and cleared the percents [Batch 125] }
    ANode.Elements['start'] := TJSONNull.Create;
    ANode.Floats['startValue'] := FDzRawStart[AIndex];
    ANode.Elements['end'] := TJSONNull.Create;
    ANode.Floats['endValue'] := FDzRawStop[AIndex];
    FDzRawValue[AIndex] := False;
  end
  else
  begin
    ANode.Floats['start'] := FDzRawStart[AIndex];
    ANode.Elements['startValue'] := TJSONNull.Create;
    ANode.Floats['end'] := FDzRawStop[AIndex];
    ANode.Elements['endValue'] := TJSONNull.Create;
  end;
  FDzRawHas[AIndex] := False;
end;

procedure TTyAdvanceChart.MergeRoamOverride(var AState: TTyGraphRoamState;
  ASeries: Integer; ANew: TJSONObject);
var
  spec: TTyGraphSpec;
  node: TJSONData;
  root: TJSONObject;
begin
  { upstream's roam wrote centre and zoom into the series' option; a merge
    writing one of them overwrites that one and keeps the other }
  if (not AState.Valid) or (ANew = nil) then Exit;
  if (ANew.Find('center') = nil) and (ANew.Find('zoom') = nil) then Exit;
  spec := TyGraphSpecDefault;
  node := FOption.ComponentAt('series', ASeries);
  root := nil;
  if FOption.Root is TJSONObject then root := TJSONObject(FOption.Root);
  if node is TJSONObject then TyGraphReadRoamOptions(TJSONObject(node), root, spec);
  if ANew.Find('center') <> nil then AState.Centre := spec.Centre;
  if ANew.Find('zoom') <> nil then AState.Zoom := spec.Zoom;
end;

procedure TTyAdvanceChart.MergeKeepStates(const AReport: TTyMergeReport);
var
  si, s, n, i: Integer;
  fate: TTyMergeFate;
  live: Boolean;
  opt, sm: TJSONObject;
begin
  { ---- by series: a model that survived keeps what upstream keeps on it ---- }
  si := TyMergeSlotsIndex(AReport, 'series');
  if si >= 0 then
  begin
    n := Length(AReport.Slots[si].Fate);
    for s := 0 to n - 1 do
    begin
      fate := AReport.Slots[si].Fate[s];
      live := fate in [mfKept, mfMerged];
      opt := AReport.Slots[si].NewOpt[s];
      { the force layout's preservedPoints, the roam's write-back, the
        selection's selectedMap and the tree view's last box are the
        model's, and go with it }
      if not live then
      begin
        if s <= High(FGraphForce) then FGraphForce[s] := Default(TTyGraphForceState);
        if s <= High(FGraphRoam) then FGraphRoam[s] := Default(TTyGraphRoamState);
        if s <= High(FTreeRoam) then FTreeRoam[s] := Default(TTyGraphRoamState);
        if s <= High(FTreeBoxHas) then FTreeBoxHas[s] := False;
        if s <= High(FSelInit) then FSelInit[s] := False;
        if s <= High(FSankeyRoam) then FSankeyRoam[s] := Default(TTyGraphRoamState);
        if s <= High(FSankeyLocal) then FSankeyLocal[s] := nil;
        Continue;
      end;
      if fate = mfMerged then
      begin
        if s <= High(FGraphRoam) then MergeRoamOverride(FGraphRoam[s], s, opt);
        { a sankey's roam as a graph's; its dragNode positions live in the
          node items, which a merge that writes the node list replaces
          [Batch 114] }
        if s <= High(FSankeyRoam) then MergeRoamOverride(FSankeyRoam[s], s, opt);
        if (s <= High(FSankeyLocal)) and (opt <> nil)
          and ((opt.Find('data') <> nil) or (opt.Find('nodes') <> nil)) then
          FSankeyLocal[s] := nil;
        if s <= High(FTreeRoam) then MergeRoamOverride(FTreeRoam[s], s, opt);
      end;
    end;
  end;
  { EVERY SERIES IS VISITED (backwardCompat writes `series` into every
    option) and re-creates its data: a tree's expand state is the data's --
    every option the preprocessors saw; the media default they never see
    visits the series only where it writes them [Batch 107] }
  if si >= 0 then FTreeToggled := nil;
  { [R2-C] and the next update's trees are new ones }
  if si >= 0 then FAnimDataFresh := True;
  { and resetViewRoot finds its node in no new tree [Batch 115] }
  if si >= 0 then HierDrillReset;

  { ---- by dataZoom: an action's window stays unless the merge wrote over
    it (MergeBefore); a new model has none ---- }
  si := TyMergeSlotsIndex(AReport, 'dataZoom');
  if si >= 0 then
  begin
    n := Length(AReport.Slots[si].Fate);
    i := Length(FDzRawHas);
    SetLength(FDzRawHas, n);
    SetLength(FDzRawStart, n);
    SetLength(FDzRawStop, n);
    for s := i to n - 1 do FDzRawHas[s] := False;
    i := Length(FDzRawValue);
    SetLength(FDzRawValue, n);
    for s := i to n - 1 do FDzRawValue[s] := False;
    for s := 0 to n - 1 do
      if not (AReport.Slots[si].Fate[s] in [mfKept, mfMerged]) then FDzRawHas[s] := False;
  end;

  { ---- by visualMap [Batch 116]: every merge visits it (it follows the
    series), and optionUpdated resets a piecewise one's selection to the new
    option's `selected` -- or to every piece; a model that went takes its
    view with it ---- }
  si := TyMergeSlotsIndex(AReport, 'visualMap');
  if si >= 0 then
    for s := 0 to High(AReport.Slots[si].Fate) do
    begin
      fate := AReport.Slots[si].Fate[s];
      if fate in [mfKept, mfMerged] then
      begin
        if s <= High(FVmSel) then FVmSel[s] := '';
        if fate = mfKept then
        begin
          opt := nil;
          if FOption.ComponentAt('visualMap', s) is TJSONObject then
            opt := TJSONObject(FOption.ComponentAt('visualMap', s));
          if (opt <> nil) and (opt.Find('selected') <> nil) then opt.Delete('selected');
        end;
      end
      else
      begin
        VmDispose(s);
        if s <= High(FVmRangeHas) then FVmRangeHas[s] := False;
        if s <= High(FVmSel) then FVmSel[s] := '';
      end;
    end
  else
    for s := 0 to FOption.ComponentCount('visualMap') - 1 do
    begin
      if s <= High(FVmSel) then FVmSel[s] := '';
      if FOption.ComponentAt('visualMap', s) is TJSONObject then
      begin
        opt := TJSONObject(FOption.ComponentAt('visualMap', s));
        if opt.Find('selected') <> nil then opt.Delete('selected');
      end;
    end;
  FVmDragVm := -1;

  { ---- what a re-render rebuilds anyway, reset as a notMerge resets it ---- }
  FPressArmed := False;
  FRoamSeries := -1;
  FRoamGeo := -1;
  FGraphDragSlot := -1;
  FSankeyDragSlot := -1;
  FDzState := nil;
  FDzRoamThrottle := nil;
  FDzRoamBatch := nil;
  FDzHover := Default(TTyDzTarget);
  FDzDrag := Default(TTyDzTarget);
  FDzHasDown := False;
  FDzPanGrid := -1;
  { the hovered element, a removed one until the carry finds it reused
    (StCarryTake has the records) [Batch 99] }
  if FEvHover.Id <> 0 then FEvHover.Id := Low(Int64);
  FSt := nil;
  FStDirty := False;
  { THE LEGEND IS VISITED (it depends on the series): optionUpdated
    resolves single mode again; `selected` itself is in the tree, merged }
  if TyMergeSlotsIndex(AReport, 'legend') >= 0 then FLegendLoaded := False;
  { ---- by geo [Batch 148]: option.selectedMap is the model's -- a model
    that went takes it; a merge that writes an object merges it in
    (zrUtil.merge with overwrite), a falsy one has optionUpdated make it
    again ---- }
  si := TyMergeSlotsIndex(AReport, 'geo');
  if si >= 0 then
    for s := 0 to High(AReport.Slots[si].Fate) do
    begin
      if s > High(FGeoSel) then Break;
      fate := AReport.Slots[si].Fate[s];
      if not (fate in [mfKept, mfMerged]) then
      begin
        FreeAndNil(FGeoSel[s]);
        Continue;
      end;
      opt := AReport.Slots[si].NewOpt[s];
      if (fate <> mfMerged) or (opt = nil) or (FGeoSel[s] = nil)
        or (opt.IndexOfName('selectedMap') < 0) then Continue;
      if opt.Find('selectedMap') is TJSONObject then
      begin
        sm := TJSONObject(opt.Find('selectedMap'));
        for i := 0 to sm.Count - 1 do
        begin
          if FGeoSel[s].IndexOfName(sm.Names[i]) >= 0 then FGeoSel[s].Delete(sm.Names[i]);
          FGeoSel[s].Add(sm.Names[i], sm.Items[i].Clone);
        end;
      end
      else if not JsTruthy(opt.Find('selectedMap')) then
        FreeAndNil(FGeoSel[s])
      else
        FGeoSel[s].Clear;
    end;
  { [Batch 150] the centre and zoom a roam wrote into the model's option:
    a model that went takes them; a merge that writes one of them
    overwrites that one }
  if si >= 0 then
    for s := 0 to High(AReport.Slots[si].Fate) do
    begin
      if s > High(FGeoRoam) then Break;
      fate := AReport.Slots[si].Fate[s];
      if not (fate in [mfKept, mfMerged]) then FGeoRoam[s] := Default(TTyGraphRoamState)
      else if fate = mfMerged then MergeGeoRoam(FGeoRoam[s], s, AReport.Slots[si].NewOpt[s]);
    end;
end;

function TTyAdvanceChart.DiagnosticCount: Integer;
begin
  if FBuild = nil then Exit(0);
  Result := FBuild.DiagnosticCount;
end;

function TTyAdvanceChart.Diagnostic(AIndex: Integer): string;
begin
  if FBuild = nil then Exit('');
  Result := FBuild.Diagnostic(AIndex);
end;

{ ==================== style ==================== }

function TTyAdvanceChart.GetStyleTypeKey: string;
begin
  { Its own key, never borrowed. A control that answers another control's key
    can never be reached by a theme that wants to restyle only this one. }
  Result := 'TyAdvChart';
end;

procedure TTyAdvanceChart.Invalidate;
begin
  { A theme change arrives as a plain Invalidate broadcast and nothing else --
    the controller says so in as many words, and there is no StyleChanged hook
    to override. So every invalidate is treated as a relayout: the axis extents
    would not move, but the label FONT may have, and the plot rect is measured
    from the labels. Cheaper to redo than to be wrong about, and a chart is not
    invalidated on mouse movement. }
  FDirty := True;
  { AND THE HOVER GOES WITH IT. Invalidate means the model may have moved, and
    a hovered datum is a pair of subscripts into a build that is about to be
    thrown away -- the row it names may not exist in the next one. Upstream
    re-shows the tooltip after a setOption while the pointer is still there;
    here the next movement re-establishes it, which is a real difference and a
    small one, and the alternative is a box describing a bar nobody can see.
    [Batch 100] The box shown goes with it, whatever alwaysShowContent says
    -- upstream keeps it and re-shows at the last pointer.
    [F4b: no longer -- the box stays up and TooltipView's _keepShow shows it
    again at the last point; TipReset says how.] }
  TipReset;
  { THE AXIS HOVER IS NOT CLEARED HERE, and deliberately not: every Invalidate
    sets FDirty, every FDirty relayouts, and every relayout rebuilds -- so
    DropBuild has already been reached by the time anything could read the
    hits again, and it clears them because it is the thing that frees what
    they point at. A second clear here would be a line no test could fail
    against, which is a line that gets deleted by somebody who cannot tell
    whether it matters. }
  { AND THE STATIC LAYER GOES. It holds a picture drawn in the theme's font at
    the theme's colours; the whole reason this method treats every invalidate
    as a relayout is that a theme change arrives as a bare Invalidate, and a
    kept cache would blit the old theme over the new one. }
  DropStatic;
  { a dirty-rect window prepares at its next paint [Batch 142] }
  FDrPending := True;
  { [F4b] zrender is dirty }
  FZrDirty := True;
  inherited Invalidate;
end;

procedure TTyAdvanceChart.InvalidateFrame;
begin
  { [F4b] zrender is dirty: the next flush says `rendered` }
  FZrDirty := True;
  InvalidateFrameQuiet;
end;

procedure TTyAdvanceChart.HoverInvalidate;
begin
  { zrender marks what changed: a state the hover moved, a box or a
    pointer that is somewhere else; the frame is asked for regardless }
  if FStDirty or (TipStateKey <> FTipPaintedKey) then FZrDirty := True;
  InvalidateFrameQuiet;
end;

procedure TTyAdvanceChart.InvalidateFrameQuiet;
begin
  { A DIRTY-RECT WINDOW FLUSHES FIRST [Batch 142]: the frame is prepared
    when the queue next runs -- once, however many asked -- and only the
    rects it changed are invalidated; zrender likewise renders at its next
    animation frame, not when it is asked. }
  if FUseDirtyRect and HandleAllocated and not (csDesigning in ComponentState) then
  begin
    FDrPending := True;
    if not FDrQueued and (Application <> nil) then
    begin
      FDrQueued := True;
      Application.QueueAsyncCall(@DrFlushAsync, 0);
    end;
    Exit;
  end;
  { The static layer is KEPT -- see the declaration. This is the repaint an
    animation tick asks for: same model, same layout, same axes, one frame on.
    [F4b] Quiet: whoever asked marks zrender dirty, or not. }
  inherited Invalidate;
end;

procedure TTyAdvanceChart.Resize;
begin
  inherited Resize;
  FDirty := True;
  { upstream's resize: resetOption('media') [Batch 107] }
  MediaRecheck;
end;

procedure TTyAdvanceChart.Loaded;
begin
  inherited Loaded;
  { the option streamed in before the size may have: asked again at the
    size loaded [Batch 107] }
  MediaRecheck;
end;

function TTyAdvanceChart.OptionComponent(const AMainType: string;
  AIndex: Integer): TJSONData;
begin
  Result := nil;
  if FOption <> nil then Result := FOption.ComponentAt(AMainType, AIndex);
end;
