{ Part of tyControls.AdvanceChart (included, not a unit): the legend -- its data, the
  filter, layout, paint and actions. Moved out of the unit only to keep it readable; what
  the control is and why it is built the way it is, see the unit header. }

function TTyAdvanceChart.LegendDecalOf(ALegend: Integer; const AName: string;
  const ASeries: TTyChartDecal): TTyChartDecal;
var
  lg, d, own: TJSONData;
  i: Integer;
  skin: TTyChartColor;
begin
  Result := ASeries;
  if FOption = nil then Exit;
  lg := FOption.ComponentAt('legend', ALegend);
  if not (lg is TJSONObject) then Exit;
  { legendItemModel.getModel('itemStyle').getShallow('decal'): the data
    item's own, else the legend's }
  own := nil;
  d := TJSONObject(lg).Find('data');
  if d is TJSONArray then
    for i := 0 to d.Count - 1 do
      if (TJSONArray(d).Items[i] is TJSONObject)
        and (TJSONObject(TJSONArray(d).Items[i]).Get('name', '') = AName) then
      begin
        own := TJSONObject(TJSONArray(d).Items[i]).Find('itemStyle');
        if own is TJSONObject then own := TJSONObject(own).Find('decal')
        else own := nil;
        Break;
      end;
  if (own = nil) or (own.JSONType = jtNull) then
  begin
    own := TJSONObject(lg).Find('itemStyle');
    if own is TJSONObject then own := TJSONObject(own).Find('decal')
    else own := nil;
  end;
  { falsy or 'inherit': the series' }
  if not TyDecalTruthy(own) then Exit;
  if (own.JSONType = jtString) and (own.AsString = 'inherit') then Exit;
  { 'none' is no pattern; any other primitive is none here (upstream throws
    on a WeakMap key) }
  if not ((own is TJSONObject) or (own is TJSONArray)) then
    Exit(Default(TTyChartDecal));
  skin := TTyChartColor(ActiveController.Model.ResolveStyle(TyDecalSkin, '',
    []).TextColor);
  Result := TyDecalResolve(TyDecalRawOf(own), skin);
end;

function TTyAdvanceChart.LegendLayoutCount: Integer;
begin
  Result := Length(FLegends);
end;

function TTyAdvanceChart.LegendLayout(AIndex: Integer): TTyLegendLayout;
begin
  Result := Default(TTyLegendLayout);
  if (AIndex >= 0) and (AIndex <= High(FLegends)) then
  begin
    Result := FLegends[AIndex];
    { A dynamic array is shared, not copied, and a caller writing into it
      would be writing into the control's own layout. }
    Result.Items := Copy(FLegends[AIndex].Items);
  end;
end;

{ ==================== legend ==================== }

{ TWO LISTS, and they are deliberately different.

  POTENTIAL is what a legend with no `data` of its own falls back to: a pie
  contributes its SLICE names and everything else contributes its own, and an
  unnamed series contributes NOTHING -- upstream gives it a private dummy name
  that no legend entry can be written to match, so the effect is the same and
  an empty string is the honest way to say it here.

  AVAILABLE is what a name is allowed to match. Every name the chart can
  produce is in it, and an entry that is NOT in it reads as switched off
  however `legend.selected` is written -- which is what greys out a
  `legend.data` entry naming a series nobody declared. }
procedure TTyAdvanceChart.LegendNames(out APotential, AAvailable: TTyLegendNames);
var
  i, k, np, na: Integer;
  nm: string;
  cats: TTyGraphCategoryArray;

  { AKeepEmpty is a graph category's: a nameless category IS a name upstream,
    `''`, which the legend draws as a line break and single mode can pick. }
  procedure PushP(const AName: string; AKeepEmpty: Boolean = False);
  begin
    if (AName = '') and not AKeepEmpty then Exit;
    if np >= Length(APotential) then SetLength(APotential, np * 2 + 8);
    APotential[np] := AName;
    Inc(np);
  end;

  procedure PushA(const AName: string; AKeepEmpty: Boolean = False);
  begin
    if (AName = '') and not AKeepEmpty then Exit;
    if na >= Length(AAvailable) then SetLength(AAvailable, na * 2 + 8);
    AAvailable[na] := AName;
    Inc(na);
  end;

begin
  APotential := nil;
  AAvailable := nil;
  np := 0;
  na := 0;
  for i := 0 to High(FBindings) do
  begin
    { A GRAPH OFFERS ITS CATEGORIES, and its own name only as AVAILABLE --
      the same shape as a pie's slices. With no categories at all it is an
      ordinary series and offers its name. The categories come from the
      OPTION, never from a solved graph: this runs in Rebuild, before any
      graph is solved. }
    if FBindings[i].SeriesType = TyGraphSeriesTypeName then
    begin
      cats := TyGraphCategoriesOf(FOption, FBindings[i].SeriesIndex);
      if Length(cats) > 0 then
      begin
        PushA(SeriesNameOf(FBindings[i].SeriesIndex));
        for k := 0 to High(cats) do
        begin
          PushP(cats[k].Name_, True);
          PushA(cats[k].Name_, True);
        end;
        Continue;
      end;
    end;
    if TySeriesLegendByDatum(FBindings[i].SeriesType)
      and (i <= High(FStores)) and (FStores[i] <> nil) then
    begin
      { ITS ROW NAMES ARE WHAT THE LEGEND OFFERS, but its own name is still
        AVAILABLE -- upstream pushes every raw series' name into that list
        unconditionally, before it ever looks at a provider. The difference
        shows when an author writes the pie's own name into `legend.data`:
        with the name available the entry is live, and without it the entry
        would grey out for a reason that has nothing to do with the option. }
      PushA(SeriesNameOf(FBindings[i].SeriesIndex));
      for k := 0 to FStores[i].Count - 1 do
      begin
        nm := FStores[i].GetName(k);
        PushP(nm);
        PushA(nm);
      end;
      Continue;
    end;
    nm := SeriesNameOf(FBindings[i].SeriesIndex);
    PushP(nm);
    PushA(nm);
  end;
  SetLength(APotential, np);
  SetLength(AAvailable, na);
end;

function TTyAdvanceChart.SeriesSymbolWord(ASlot: Integer): string;
var
  d: TJSONData;
  node: TJSONObject;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('symbol');
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function TTyAdvanceChart.LegendSources(const AEntries: TTyLegendEntryArray;
  ALegend: Integer): TTyLegendSourceArray;
var
  i, j, k, si: Integer;
  found: Boolean;
  perRaw: TTyChartColorArray;
  cats: TTyGraphCategoryArray;
begin
  SetLength(Result, Length(AEntries));
  for i := 0 to High(AEntries) do
  begin
    Result[i] := Default(TTyLegendSource);
    if AEntries[i].Newline then Continue;
    found := False;
    { A SERIES NAME WINS OVER A SLICE NAME, because upstream asks
      getSeriesByName first and only falls to the per-datum providers when
      nothing answered. }
    { [Batch 100] EVERY SERIES, a pie's and a funnel's included: upstream's
      getSeriesByName knows no provider, so `legend.data` naming a pie's own
      name draws an item in the series' colour (the 6.1 build: MyPie gets
      the palette's first). It used to skip them, which drew that item greyed
      -- and, now that a name nothing answers to is not drawn, would have
      dropped it. }
    for j := 0 to High(FBindings) do
    begin
      if SeriesNameOf(FBindings[j].SeriesIndex) <> AEntries[i].Name then
        Continue;
      Result[i].Found := True;
      Result[i].SeriesType := FBindings[j].SeriesType;
      Result[i].Colour := TTyChartColor(SeriesColor(FBindings[j].SeriesIndex));
      Result[i].Obj := SeriesObjectFill(j);
      Result[i].DefaultIcon := TyLegendDefaultIcon(FBindings[j].SeriesType,
        SeriesSymbolWord(j));
      Result[i].OwnIcon := TyLegendDrawsOwnIcon(FBindings[j].SeriesType);
      { the series' style decal under the legend's own [Batch 131]; an icon
        the series draws itself (a line's) takes it too: getLegendIcon sets
        the legend style on its symbol, decal and all [F4a] }
      begin
        if j <= High(FSeriesDecals) then
          Result[i].Decal := LegendDecalOf(ALegend, AEntries[i].Name, FSeriesDecals[j])
        else
          Result[i].Decal := LegendDecalOf(ALegend, AEntries[i].Name, Default(TTyChartDecal));
      end;
      Result[i].LineColour := Result[i].Colour;
      { THE SAME 2 THE LINE ITSELF FALLS BACK TO in BuildLine, which is also
        what `lineStyle.width: 'auto'` resolves to upstream. When series line
        widths become an option the two will read it from one place; until
        then they agree by saying the same thing. }
      if Result[i].OwnIcon then
        Result[i].LineWidthLogical := 2
      else
        LegendBorderOf(j, -1, Result[i]);
      found := True;
      Break;
    end;
    if found then Continue;
    for j := 0 to High(FBindings) do
    begin
      { A GRAPH'S CATEGORY, AT THE GRAPH'S PLACE IN SERIES ORDER -- so a name
        that is both a pie slice and a category is drawn by whichever series
        comes first, and a name two categories share by the FIRST of them. A
        rounded rectangle in the category's colour: the category provider
        publishes no icon, and the category's `symbol` is its nodes', not its
        chip's. }
      if FBindings[j].SeriesType = TyGraphSeriesTypeName then
      begin
        si := FBindings[j].SeriesIndex;
        cats := TyGraphCategoriesOf(FOption, si);
        for k := 0 to High(cats) do
          if cats[k].Name_ = AEntries[i].Name then
          begin
            Result[i].Found := True;
            Result[i].SeriesType := FBindings[j].SeriesType;
            Result[i].DefaultIcon := '';
            Result[i].OwnIcon := False;
            if FBindings[j].Hidden then
              Result[i].Greyed := True
            else if (si <= High(FGraphCatColours))
              and (k <= High(FGraphCatColours[si].Known))
              and FGraphCatColours[si].Known[k] then
            begin
              Result[i].Colour := FGraphCatColours[si].Colours[k];
              { A TRANSPARENT CATEGORY IS SHOWN AT A FIFTH, not as nothing --
                upstream's legend rescues an alpha of zero to 0.2 so the item
                can still be found. The nodes stay transparent. }
              if (LongWord(Result[i].Colour) shr 24) = 0 then
                Result[i].Colour := TTyChartColor(
                  (LongWord(Result[i].Colour) and $00FFFFFF) or $33000000);
            end
            else if (si <= High(FGraphCatColours))
              and (k <= High(FGraphCatColours[si].Base))
              and FGraphCatColours[si].Base[k] then
              { A colour nobody can paint: the chip wears the series colour,
                as the nodes do. }
              Result[i].Colour := TTyChartColor(SeriesColor(si));
            Result[i].LineColour := Result[i].Colour;
            found := True;
            Break;
          end;
        if found then Break;
        Continue;
      end;
      if not TySeriesLegendByDatum(FBindings[j].SeriesType) then Continue;
      if (j > High(FStores)) or (FStores[j] = nil) then Continue;
      { THE RAW ROWS, NOT THE VIEW. This runs in Relayout, which is to say
        AFTER the filter has already taken the switched-off slices out of
        the store -- and those are exactly the slices whose legend items we
        are here to describe. Walking the view would find every item except
        the ones that were switched off.

        AN EQUIVALENT MUTANT LIVES HERE and is recorded rather than chased:
        walking the view instead draws the same picture TODAY, because the
        only items it would fail to find are the switched-off ones, and a
        switched-off item takes the inactive ink and the roundRect floor --
        neither of which comes from here. It stops being equivalent the
        moment a greyed item keeps anything of its own, and being wrong for
        an invisible reason is still being wrong.

        colorBy: 'data' -- a slice's colour is the same eight-slot ramp,
        keyed on the same RAW row PieVisual keys on, so the swatch and the
        wedge cannot disagree. }
      perRaw := PerDatumColours(j);
      for k := 0 to FStores[j].RawCount - 1 do
        if FStores[j].GetNameByRaw(k) = AEntries[i].Name then
        begin
          Result[i].Found := True;
          Result[i].SeriesType := FBindings[j].SeriesType;
          { THE SAME PALETTE THE MARKS USE, asked the same way. It read the
            ramp directly by row while the marks went through the shared
            per-datum rule, so an authored `color` list or a datum's own
            itemStyle moved the wedge and left the swatch behind. }
          if k <= High(perRaw) then
            Result[i].Colour := perRaw[k]
          else
            Result[i].Colour := TTyChartColor(SeriesColor(k));
          Result[i].Obj := DatumObjectFill(j, k);
          { the datum's decal -- a slice the legend filtered reads the
            series' -- under the legend's own [Batch 131] }
          Result[i].Decal := LegendDecalOf(ALegend, AEntries[i].Name, RowDecalOf(j, k));
          { A TRANSPARENT DATUM IS SHOWN AT A FIFTH, as the category chip
            above is -- but the swatch still carries the datum's own opacity,
            so a slice a visualMap put out of range (colour and opacity both
            nought) stays invisible there too. }
          if (LongWord(Result[i].Colour) shr 24) = 0 then
            Result[i].Colour := TTyChartColor(
              (LongWord(Result[i].Colour) and $00FFFFFF) or $33000000);
          if (j <= High(FVisualRows)) and (k <= High(FVisualRows[j]))
            and FVisualRows[j][k].OpacitySet
            and not IsNan(FVisualRows[j][k].Opacity) then
          begin
            Result[i].HasOpacity := True;
            Result[i].Opacity := FVisualRows[j][k].Opacity;
          end;
          Result[i].LineColour := Result[i].Colour;
          Result[i].DefaultIcon := TyLegendDefaultIcon(
            FBindings[j].SeriesType, SeriesSymbolWord(j));
          Result[i].OwnIcon := TyLegendDrawsOwnIcon(FBindings[j].SeriesType);
          if Result[i].OwnIcon then Result[i].LineWidthLogical := 2
          else LegendBorderOf(j, k, Result[i]);
          found := True;
          Break;
        end;
      if found then Break;
    end;
  end;
end;

procedure TTyAdvanceChart.SolveLegendData;
var
  i, n: Integer;
  potential, available: TTyLegendNames;
begin
  n := TyLegendCount(FOption);
  SetLength(FLegendSpecs, n);
  SetLength(FLegendEntries, n);
  SetLength(FLegendFlags, n);
  SetLength(FLegends, n);
  FLegendAvailable := nil;
  if n = 0 then Exit;
  LegendNames(potential, available);
  FLegendAvailable := available;
  for i := 0 to n - 1 do
  begin
    FLegendSpecs[i] := TyLegendSpecOf(FOption, i);
    FLegendEntries[i] := TyLegendEntries(FOption, i, potential);
    { an index hole is no legend: no items, and it filters nothing [Batch 97] }
    if not (FOption.ComponentAt('legend', i) is TJSONObject) then
      FLegendEntries[i] := nil;
    { THE MODEL, ONCE PER OPTION [Batch 93]: init makes `selected`,
      optionUpdated forces single mode's one item ON INTO THE MAP -- an
      update afterwards (a legend action) does not run it again, so what the
      actions leave in the map is what is shown }
    if not FLegendLoaded then
    begin
      TyLegendSelectedNode(FOption, i);
      if FLegendSpecs[i].SelectedMode = tlsSingle then
        TyLegendResolveSingle(FOption, i, FLegendEntries[i], available);
    end;
    FLegendFlags[i] := TyLegendSelected(FOption, i, FLegendEntries[i],
      available, tlsMultiple);
    FLegends[i] := Default(TTyLegendLayout);
  end;
  FLegendLoaded := True;
end;

{ A name is switched off when ANY legend says so -- legendFilter.ts:36-41.
  Nothing is switched off when there is no legend at all, which is why a
  chart without one is untouched by any of this. }
function TTyAdvanceChart.LegendHides(const AName: string): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(FLegendSpecs) do
    if TyLegendHides(FOption, i, FLegendEntries[i], FLegendFlags[i], AName) then
      Exit(True);
end;

function TTyAdvanceChart.KeepSlice(ARawIndex: Integer): Boolean;
begin
  Result := True;
  if FFilterStore = nil then Exit;
  Result := not LegendHides(FFilterStore.GetNameByRaw(ARawIndex));
end;

function TTyAdvanceChart.KeepGraphNode(ARawIndex: Integer): Boolean;
var
  v: TTyDataValue;
  i: Integer;
  nm: string;
begin
  Result := True;
  if FFilterStore = nil then Exit;
  { `category == null` KEEPS THE NODE -- absent and null alike. }
  if not FFilterStore.HasOverrideByRaw(ARawIndex, TyOverrideKey('category')) then
    Exit;
  v := FFilterStore.GetOverrideByRaw(ARawIndex, TyOverrideKey('category'));
  case v.Kind of
    dvkNone: Exit;
    dvkNumber:
      { `categoryNames[n]`: a JavaScript array indexed by the number, so an
        index out of range -- or negative, or fractional -- finds `undefined`,
        a name no legend offers. }
      { The range first: Frac of an infinity raises, and `1e999` parses as
        one. }
      if (v.Num >= 0) and (v.Num <= High(FFilterCats)) and (Frac(v.Num) = 0) then
        nm := FFilterCats[Trunc(v.Num)].Name_
      else
        Exit(False);
    dvkText:
      { A STRING IS ASKED ABOUT EXACTLY AS WRITTEN -- '1' is the name '1',
        not index one -- and against every name the CHART offers, so a node
        naming a series or another graph's category is kept, and goes when
        that name is switched off. }
      nm := v.Text;
  else
    { A boolean is never a name anything offers. }
    Exit(False);
  end;
  for i := 0 to High(FLegendSpecs) do
    if not TyLegendNameSelected(FOption, i, FLegendEntries[i], FLegendFlags[i],
      FLegendAvailable, nm) then
      Exit(False);
end;

procedure TTyAdvanceChart.ApplyLegendFilter;
var
  i, k: Integer;
  st: TTyDataStore;
  any: Boolean;
begin
  if Length(FLegendSpecs) = 0 then Exit;
  for i := 0 to High(FBindings) do
  begin
    { A GRAPH IS FILTERED TWICE: WHOLE, by its series name -- upstream's
      legendFilter runs on every series first -- and then, if it survived,
      node by node by CATEGORY. The second is upstream's categoryFilter, and
      its rule is not the series rule: it asks isSelected of every legend for
      every node that names a category, so a category switched off only in
      `selected` goes, and a node whose category the chart does not offer --
      an index past the end, a name nobody declared -- goes too, whenever any
      legend exists. With no legend at all nothing is filtered: this whole
      procedure has already returned. }
    if FBindings[i].SeriesType = TyGraphSeriesTypeName then
    begin
      FBindings[i].Hidden :=
        LegendHides(SeriesNameOf(FBindings[i].SeriesIndex));
      if FBindings[i].Hidden then Continue;
      if (i > High(FStores)) or (FStores[i] = nil) then Continue;
      st := FStores[i];
      FFilterCats := TyGraphCategoriesOf(FOption, FBindings[i].SeriesIndex);
      FFilterStore := st;
      try
        { ASKED BEFORE IT IS DONE, and with the graph's OWN rule: with a
          legend present a node can go even when every item is switched on,
          so the question is not "is anything off" but "does any node fail". }
        any := False;
        for k := 0 to st.RawCount - 1 do
          if not KeepGraphNode(k) then
          begin
            any := True;
            Break;
          end;
        if any then st.FilterSelf(@KeepGraphNode);
      finally
        FFilterStore := nil;
        FFilterCats := nil;
      end;
      Continue;
    end;
    if not TySeriesLegendByDatum(FBindings[i].SeriesType) then
    begin
      FBindings[i].Hidden :=
        LegendHides(SeriesNameOf(FBindings[i].SeriesIndex));
      Continue;
    end;
    { SUCH A SERIES IS FILTERED ONE ROW AT A TIME, because its legend names rows
      rather than series -- upstream's processor/dataFilter against this
      port's own TTyDataStore.FilterSelf, which is the same mechanism and
      has been sitting here unused since the store was written.

      It COMPOSES with the negative-value filter the pie layout applies
      later, and in upstream's order: the legend's filter is registered
      first and negativeDataFilter second (chart/pie/install.ts:35-37). }
    if (i > High(FStores)) or (FStores[i] = nil) then Continue;
    st := FStores[i];
    { ASKED BEFORE IT IS DONE, so a pie nobody switched anything off on
      keeps an UNFILTERED store -- which is not only cheaper but visible:
      a filtered store takes the slow path through its index vector in
      every extent and every read. }
    any := False;
    for k := 0 to st.RawCount - 1 do
      if LegendHides(st.GetNameByRaw(k)) then
      begin
        any := True;
        Break;
      end;
    if not any then Continue;
    FFilterStore := st;
    try
      st.FilterSelf(@KeepSlice);
    finally
      FFilterStore := nil;
    end;
  end;
end;

function TTyAdvanceChart.LegendFont: TTyLegendFont;
var st: TTyStyleSet;
begin
  st := ActiveController.Model.ResolveStyle('TyAdvChartLegend', '', []);
  Result.Name := st.FontName;
  Result.SizeLogical := ResolveFontSize(st);
  Result.Weight := st.FontWeight;
end;

{ ONE LEGEND'S FONT AND TEXT COLOUR: the theme's, the root textStyle over
  it, the legend's own textStyle over that [Batch 83] }
procedure TTyAdvanceChart.LegendTextOf(AIndex: Integer; var AFont: TTyLegendFont;
  var AInk: TTyLegendInk);
var
  node, st, d: TJSONData;
  col: TTyChartColor;
  hasCol: Boolean;
  gcol: Cardinal;
begin
  hasCol := False;
  gcol := 0;
  { a legend's colour is its own default; its font is not }
  GlobalTextOver(AFont.Name, AFont.SizeLogical, AFont.Weight, hasCol, gcol, [ttpSize, ttpWeight, ttpFamily]);
  if hasCol then AInk.Text := TTyChartColor(gcol);
  AFont.RtGlobal := RtGlobal;
  AFont.Rt := Default(TTyRtBlockStyle);
  node := FOption.ComponentAt('legend', AIndex);
  if not (node is TJSONObject) then Exit;
  { AN UNSELECTED ITEM'S COLOURS: inactiveColor (its words and its icon),
    inactiveBorderColor (its pen) and the rule's lineStyle.inactiveColor /
    inactiveWidth, over the theme's inactive ink [Batch 93] }
  d := TJSONObject(node).Find('inactiveColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.Inactive := col;
  d := TJSONObject(node).Find('inactiveBorderColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.InactiveBorder := col;
  { the pager's colours [Batch 98] }
  d := TJSONObject(node).Find('pageIconColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.PageIcon := col;
  d := TJSONObject(node).Find('pageIconInactiveColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.PageIconInactive := col;
  st := TJSONObject(node).Find('pageTextStyle');
  if st is TJSONObject then
  begin
    d := TJSONObject(st).Find('color');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
      AInk.PageText := col;
  end;
  st := TJSONObject(node).Find('lineStyle');
  if st is TJSONObject then
  begin
    d := TJSONObject(st).Find('inactiveColor');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
      AInk.LineInactive := col;
    d := TJSONObject(st).Find('inactiveWidth');
    if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat >= 0) then
      AInk.LineInactiveWidth := d.AsFloat;
  end;
  st := TJSONObject(node).Find('textStyle');
  if not (st is TJSONObject) then Exit;
  { the items' text block: free text [Batch 86] }
  if TyRtNodeWantsBlock(TJSONObject(st)) then
    AFont.Rt := TyRtResolve([TJSONObject(st)], AFont.RtGlobal,
      TyRtResolveOpt(False));
  d := TJSONObject(st).Find('fontFamily');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
    AFont.Name := d.AsString;
  AFont.SizeLogical := TyOptFontSize(TJSONObject(st).Find('fontSize'),
    AFont.SizeLogical);
  AFont.Weight := TyFontWeightOf(TJSONObject(st).Find('fontWeight'), AFont.Weight);
  d := TJSONObject(st).Find('color');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
    AInk.Text := col;
end;

function TTyAdvanceChart.LegendInk: TTyLegendInk;
var model: TTyStyleModel;
begin
  model := ActiveController.Model;
  Result.Text := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegend', '', []).TextColor);
  Result.Inactive := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendInactive', '', []).TextColor);
  Result.Border := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendBorder', '', []).BorderColor);
  Result.Background := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendBackground', '', []).Background.Color);
  { upstream's three inactive defaults are the one disabled token; the rule
    is 2 wide [Batch 93] }
  Result.InactiveBorder := Result.Inactive;
  Result.LineInactive := Result.Inactive;
  Result.LineInactiveWidth := 2;
  { the pager [Batch 98] }
  Result.PageIcon := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendPageIcon', '', []).TextColor);
  Result.PageIconInactive := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendPageIconInactive', '', []).TextColor);
  Result.PageText := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendPageText', '', []).TextColor);
  { The hole in a ring is the chart's own ground, the same substitution the
    mark builders make for a datum's `empty` marker. }
  Result.EmptyFill := TTyChartColor(
    model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
end;

function TTyAdvanceChart.LegendDeco(AIndex: Integer;
  const AMeasurer: ITyTextMeasurer): TTyLegendDeco;
var
  model: TTyStyleModel;
  st, stH, stP: TTyStyleSet;
  node, d: TJSONData;
  sel, em, pts, defs: TJSONObject;
  g: TTyRtGlobal;
  fam: string;
  size, weight: Integer;
  ink, inkH, col: TTyChartColor;
  hasCol: Boolean;
  gcol: Cardinal;
begin
  Result := Default(TTyLegendDeco);
  Result.Measurer := AMeasurer;
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartLegendSelector', '', []);
  stH := model.ResolveStyle('TyAdvChartLegendSelector', '', [tysHover]);
  stP := model.ResolveStyle('TyAdvChartLegendPageText', '', []);
  sel := nil;
  em := nil;
  pts := nil;
  node := FOption.ComponentAt('legend', AIndex);
  if node is TJSONObject then
  begin
    d := TJSONObject(node).Find('selectorLabel');
    if d is TJSONObject then sel := TJSONObject(d);
    d := TJSONObject(node).Find('emphasis');
    if d is TJSONObject then
    begin
      d := TJSONObject(d).Find('selectorLabel');
      if d is TJSONObject then em := TJSONObject(d);
    end;
    d := TJSONObject(node).Find('pageTextStyle');
    if d is TJSONObject then pts := TJSONObject(d);
  end;

  { THE SELECTOR BUTTONS: selectorLabel over its defaults -- the box
    (padding [3, 5, 3, 5], a 1 px border, radius 10) as upstream writes it,
    the font and the inks the skin's. Its own fontSize and family are
    defaults upstream, so the root textStyle's never reach it. }
  fam := st.FontName;
  size := ResolveFontSize(st);
  weight := st.FontWeight;
  if sel <> nil then
  begin
    d := sel.Find('fontFamily');
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
      fam := d.AsString;
    size := TyOptFontSize(sel.Find('fontSize'), size);
    weight := TyFontWeightOf(sel.Find('fontWeight'), weight);
  end;
  ink := TTyChartColor(st.TextColor);
  inkH := TTyChartColor(stH.TextColor);
  if em <> nil then
  begin
    d := em.Find('color');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, col) then
      inkH := col;
  end;
  g := RtGlobal;
  { no root colour: an unwritten one is the skin's, bound below }
  g.HasColour := False;
  defs := TJSONObject(GetJSON('{"padding":[3,5,3,5],"borderWidth":1,"borderRadius":10}'));
  try
    Result.SelBlock := TyRtResolve([sel, defs], g, TyRtResolveOpt(False));
  finally
    defs.Free;
  end;
  if not (Result.SelBlock.Style.HasBorderColor or Result.SelBlock.Style.BorderColorInherit) then
  begin
    Result.SelBlock.Style.HasBorderColor := True;
    Result.SelBlock.Style.BorderColor := TTyChartColor(st.BorderColor);
  end;
  Result.SelBlock.Needed := True;
  Result.SelEmphBlock := Result.SelBlock;
  TyRtFinish(Result.SelBlock, fam, size, weight, g, True, ink);
  TyRtFinish(Result.SelEmphBlock, fam, size, weight, g, True, inkH);
  { emphasis.selectorLabel is only a colour: the state changes the fill }
  Result.SelEmphBlock.Style.HasFill := True;
  Result.SelEmphBlock.Style.FillNone := False;
  Result.SelEmphBlock.Style.Fill := inkH;

  { THE PAGE TEXT: getFont -- pageTextStyle, else the root textStyle, else
    the skin's }
  Result.PageFontName := stP.FontName;
  Result.PageFontSize := ResolveFontSize(stP);
  Result.PageFontWeight := stP.FontWeight;
  hasCol := False;
  gcol := 0;
  GlobalTextOver(Result.PageFontName, Result.PageFontSize, Result.PageFontWeight,
    hasCol, gcol, [ttpSize, ttpWeight, ttpFamily]);
  if pts <> nil then
  begin
    d := pts.Find('fontFamily');
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
      Result.PageFontName := d.AsString;
    Result.PageFontSize := TyOptFontSize(pts.Find('fontSize'), Result.PageFontSize);
    Result.PageFontWeight := TyFontWeightOf(pts.Find('fontWeight'), Result.PageFontWeight);
  end;
end;

procedure TTyAdvanceChart.SolveLegends(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i: Integer;
  fnt: TTyLegendFont;
  ink: TTyLegendInk;
  ref: TTyXYWH;
begin
  if Length(FLegendSpecs) = 0 then Exit;
  for i := 0 to High(FLegendSpecs) do
  begin
    fnt := LegendFont;
    ink := LegendInk;
    LegendTextOf(i, fnt, ink);
    { a block is measured as the block it is drawn as [Batch 86]; the
      selector and the pager measure their own [Batch 98] }
    { IN A MATRIX CELL OR A CALENDAR DAY when it names one [Batch 151] }
    if ComponentBoxRef('legend', i, ref) then
      FLegends[i] := TyLayoutLegend(FLegendSpecs[i], FLegendEntries[i],
        FLegendFlags[i], LegendSources(FLegendEntries[i], i), ref,
        TyRtBlockMeasurer(AMeasurer, fnt.Rt, fnt.RtGlobal, APPI / 96), fnt, APPI,
        LegendDeco(i, AMeasurer))
    else
      FLegends[i] := TyLayoutLegend(FLegendSpecs[i], FLegendEntries[i],
        FLegendFlags[i], LegendSources(FLegendEntries[i], i), FLastRect,
        TyRtBlockMeasurer(AMeasurer, fnt.Rt, fnt.RtGlobal, APPI / 96), fnt, APPI,
        LegendDeco(i, AMeasurer));
  end;
  LegAnimSync;
end;

function TTyAdvanceChart.BuildLegends(APPI: Integer;
  AList: TTyPaintList; const AMeasurer: ITyTextMeasurer): Integer;
var
  i, hov, k: Integer;
  lay: TTyLegendLayout;
  dx, dy: Double;
  ink: TTyLegendInk;
  fnt: TTyLegendFont;
begin
  Result := 0;
  if Length(FLegends) = 0 then Exit;
  for i := 0 to High(FLegends) do
  begin
    ink := LegendInk;
    fnt := LegendFont;
    LegendTextOf(i, fnt, ink);
    if FLegendSelHoverLegend = i then hov := FLegendSelHoverIdx else hov := -1;
    lay := FLegends[i];
    { [Batch 98] THE SCROLL IN FLIGHT: the items where the content group is
      now, not where the page will leave it }
    if lay.IsScroll and (i <= High(FLegProxies)) and (FLegProxies[i] <> nil) then
    begin
      dx := FLegProxies[i].Num('x') - lay.ContentPosX;
      dy := FLegProxies[i].Num('y') - lay.ContentPosY;
      if IsNan(dx) then dx := 0;
      if IsNan(dy) then dy := 0;
      if (dx <> 0) or (dy <> 0) then
      begin
        lay.Items := Copy(lay.Items);
        for k := 0 to High(lay.Items) do
        begin
          if not TyRectFIsValid(lay.Items[k].Bounds) then Continue;
          lay.Items[k].IconBox := TyRectF(lay.Items[k].IconBox.Left + dx,
            lay.Items[k].IconBox.Top + dy, lay.Items[k].IconBox.Right + dx,
            lay.Items[k].IconBox.Bottom + dy);
          lay.Items[k].Bounds := TyRectF(lay.Items[k].Bounds.Left + dx,
            lay.Items[k].Bounds.Top + dy, lay.Items[k].Bounds.Right + dx,
            lay.Items[k].Bounds.Bottom + dy);
          lay.Items[k].TextX := lay.Items[k].TextX + dx;
          lay.Items[k].TextY := lay.Items[k].TextY + dy;
        end;
      end;
    end;
    Inc(Result, TyBuildLegendMarks(FLegendSpecs[i], lay, ink, fnt,
      APPI, AList, i, AMeasurer, hov));
  end;
end;

function TTyAdvanceChart.LegendSelectedText(AIndex: Integer): string;
begin
  Result := TyLegendSelectedJson(FOption, AIndex);
end;

{ ==================== the legend's actions [Batch 93] ==================== }

function TTyAdvanceChart.LegendQuery(APayload: TJSONObject): TTyIntegerArray;
var
  d, x: TJSONData;
  i, k, n, cnt: Integer;
  byId: Boolean;
  v: string;
  node: TJSONObject;

  procedure Add(AIndex: Integer);
  var j: Integer;
  begin
    for j := 0 to High(Result) do
      if Result[j] = AIndex then Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AIndex;
  end;

  function Wanted(AValue: string): Boolean;
  var j: Integer;
  begin
    Result := False;
    if d is TJSONArray then
    begin
      for j := 0 to TJSONArray(d).Count - 1 do
        if (TJSONArray(d).Items[j].JSONType in [jtString, jtNumber])
          and (TJSONArray(d).Items[j].AsString = AValue) then Exit(True);
    end
    else if d.JSONType in [jtString, jtNumber] then
      Result := d.AsString = AValue;
  end;

begin
  Result := nil;
  cnt := Length(FLegendSpecs);
  { the index (a number or a list), else the id, else the name -- in
    component order for the last two }
  d := APayload.Find('legendIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
    begin
      for k := 0 to TJSONArray(d).Count - 1 do
        if TJSONArray(d).Items[k].JSONType = jtNumber then
        begin
          n := Trunc(TJSONArray(d).Items[k].AsFloat);
          if (n >= 0) and (n < cnt) then Add(n);
        end;
    end
    else if d.JSONType = jtNumber then
    begin
      n := Trunc(d.AsFloat);
      if (n >= 0) and (n < cnt) then Add(n);
    end;
    Exit;
  end;
  byId := True;
  d := APayload.Find('legendId');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    byId := False;
    d := APayload.Find('legendName');
  end;
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    for i := 0 to cnt - 1 do Add(i);
    Exit;
  end;
  for i := 0 to cnt - 1 do
  begin
    node := nil;
    if FOption.ComponentAt('legend', i) is TJSONObject then
      node := TJSONObject(FOption.ComponentAt('legend', i));
    if node = nil then Continue;
    { the MODEL's id -- the generated one when the option wrote none, which
      is what the selector and the pager dispatch with [Batch 98] }
    v := '';
    if byId then v := ComponentModelId('legend', i);
    if v = '' then
    begin
      if byId then x := node.Find('id') else x := node.Find('name');
      if (x = nil) or not (x.JSONType in [jtString, jtNumber]) then Continue;
      v := x.AsString;
    end;
    if Wanted(v) then Add(i);
  end;
end;

procedure TTyAdvanceChart.LegendSelectedMapInto(AIndex: Integer; AMap: TJSONObject);
var
  i, k: Integer;
  nm: string;
  on_: Boolean;
begin
  if (AIndex < 0) or (AIndex > High(FLegendEntries)) then Exit;
  for i := 0 to High(FLegendEntries[AIndex]) do
  begin
    nm := FLegendEntries[AIndex][i].Name;
    { a wrap element is no item }
    if (nm = '') or (nm = #10) then Continue;
    on_ := TyLegendIsSelected(FOption, AIndex, FLegendAvailable, nm);
    { unselected if any legend is unselected }
    k := AMap.IndexOfName(nm);
    if k >= 0 then AMap.Booleans[nm] := AMap.Booleans[nm] and on_
    else AMap.Booleans[nm] := on_;
  end;
end;

{ the map as JSON in JavaScript's key order }
function JsMapJson(AMap: TJSONObject): string;
var keys: TTyLegendNames; i: Integer;
begin
  keys := TyJsKeyOrder(AMap);
  Result := '{';
  for i := 0 to High(keys) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '"' + StringToJSONString(keys[i]) + '":'
      + AMap.Find(keys[i]).AsJSON;
  end;
  Result := Result + '}';
end;

procedure TTyAdvanceChart.DoLegendAction(APayload: TJSONObject);
var
  ev, js: string;
begin
  js := LegendActionApply(APayload, APayload.Strings['type'], ev);
  { the update runs before the event is published }
  FullUpdate;
  EmitPayloadEvent(ev, js);
end;

function TTyAdvanceChart.LegendActionApply(APayload: TJSONObject;
  const AType: string; out AEvent: string): string;
var
  t, ev, nm, nameJson, idx: string;
  isAll: Boolean;
  legends: TTyIntegerArray;
  i, k: Integer;
  map, all_: TJSONObject;
  keys: TTyLegendNames;
  d: TJSONData;
begin
  { the ACTION's type: a batch item keeps whatever type it came with }
  t := AType;
  if t = 'legendToggleSelect' then ev := 'legendselectchanged'
  else if t = 'legendSelect' then ev := 'legendselected'
  else if t = 'legendUnSelect' then ev := 'legendunselected'
  else if t = 'legendAllSelect' then ev := 'legendselectall'
  else ev := 'legendinverseselect';
  isAll := (t = 'legendAllSelect') or (t = 'legendInverseSelect');
  { payload.name as JavaScript keys it: a missing name is the key
    'undefined' and leaves the event's name out }
  d := APayload.Find('name');
  if d = nil then
  begin
    nm := 'undefined';
    nameJson := '';
  end
  else
  begin
    case d.JSONType of
      jtString, jtNumber: nm := d.AsString;
      jtNull: nm := 'null';
      jtBoolean: if d.AsBoolean then nm := 'true' else nm := 'false';
    else
      nm := d.AsString;
    end;
    nameJson := d.AsJSON;
  end;
  map := TJSONObject.Create;
  all_ := TJSONObject.Create;
  try
    { the method on every legend the payload names, and their map }
    legends := LegendQuery(APayload);
    for i := 0 to High(legends) do
    begin
      k := legends[i];
      if t = 'legendToggleSelect' then
        TyLegendToggleName(FOption, k, FLegendEntries[k], FLegendSpecs[k].SelectedMode, nm)
      else if t = 'legendSelect' then
        TyLegendSelectName(FOption, k, FLegendEntries[k], FLegendSpecs[k].SelectedMode, nm)
      else if t = 'legendUnSelect' then
        TyLegendUnSelectName(FOption, k, FLegendSpecs[k].SelectedMode, nm)
      else if t = 'legendAllSelect' then
        TyLegendAllSelect(FOption, k, FLegendEntries[k])
      else
        TyLegendInverseSelect(FOption, k, FLegendEntries[k]);
      LegendSelectedMapInto(k, map);
    end;
    { EVERY LEGEND IS FORCED TO THE SAME STATUSES -- which writes every name
      of the map into every legend's `selected`, and re-enforces single
      mode (legendAction.ts:52-64) }
    keys := TyJsKeyOrder(map);
    for k := 0 to High(FLegendSpecs) do
    begin
      for i := 0 to High(keys) do
        if map.Booleans[keys[i]] then
          TyLegendSelectName(FOption, k, FLegendEntries[k], FLegendSpecs[k].SelectedMode, keys[i])
        else
          TyLegendUnSelectName(FOption, k, FLegendSpecs[k].SelectedMode, keys[i]);
      LegendSelectedMapInto(k, all_);
    end;
    { the action's return: the event object, its type set [Batch 141:
      the update and the publishing are the caller's] }
    AEvent := ev;
    if isAll then
    begin
      idx := '';
      for i := 0 to High(legends) do
      begin
        if i > 0 then idx := idx + ',';
        idx := idx + IntToStr(legends[i]);
      end;
      Result := '{"selected":' + JsMapJson(all_) + ',"legendIndex":['
        + idx + '],"type":"' + ev + '"}';
    end
    else if nameJson <> '' then
      Result := '{"name":' + nameJson + ',"selected":' + JsMapJson(all_)
        + ',"type":"' + ev + '"}'
    else
      Result := '{"selected":' + JsMapJson(all_) + ',"type":"' + ev + '"}';
  finally
    map.Free;
    all_.Free;
  end;
end;

{ every raw series whose legendHoverLink is falsy: the option's value, else
  the type's default -- true where a type's defaultOption says so, undefined
  (falsy) elsewhere (a heatmap, a sunburst, a treemap, a tree, a sankey) }
function TTyAdvanceChart.LegendExcludeIds: string;
const
  cLinked: array[0..14] of string = ('bar', 'pictorialBar', 'line', 'scatter',
    'effectScatter', 'pie', 'funnel', 'gauge', 'graph', 'radar', 'candlestick',
    'boxplot', 'lines', 'custom', 'chord');
var
  i, k: Integer;
  n, d: TJSONData;
  linked: Boolean;
  tp: string;
begin
  Result := '[';
  for i := 0 to FOption.ComponentCount('series') - 1 do
  begin
    n := FOption.ComponentAt('series', i);
    { eachRawSeries never meets an index hole [Batch 97] }
    if not (n is TJSONObject) then Continue;
    d := nil;
    tp := '';
    if n is TJSONObject then
    begin
      d := TJSONObject(n).Find('legendHoverLink');
      tp := TJSONObject(n).Get('type', '');
    end;
    if (d <> nil) and (d.JSONType <> jtNull) then
      linked := JsTruthy(d)
    else
    begin
      linked := False;
      for k := 0 to High(cLinked) do
        if cLinked[k] = tp then linked := True;
    end;
    if linked then Continue;
    if Result <> '[' then Result := Result + ',';
    Result := Result + '"' + StringToJSONString(SeriesModelId(i)) + '"';
  end;
  Result := Result + ']';
end;

procedure TTyAdvanceChart.LegendHighDown(const ATarget: TTyChartEventTarget;
  const AType: string);
var p: string;
begin
  p := '{"type":"' + AType + '","seriesName":';
  if ATarget.HdLegendSeries then
    p := p + '"' + StringToJSONString(ATarget.HdName) + '","name":null'
  else
    p := p + 'null,"name":"' + StringToJSONString(ATarget.HdName) + '"';
  DispatchAction(p + ',"excludeSeriesId":' + LegendExcludeIds + '}');
end;

procedure TTyAdvanceChart.LegendClick(const ATarget: TTyChartEventTarget);
begin
  { downplay before unselect, highlight after select (LegendView.ts:709-724) }
  LegendHighDown(ATarget, 'downplay');
  DispatchAction('{"type":"legendToggleSelect","name":"'
    + StringToJSONString(ATarget.HdName) + '"}');
  LegendHighDown(ATarget, 'highlight');
end;

procedure TTyAdvanceChart.LegendSelectorClick(const ATarget: TTyChartEventTarget);
var k, b: Integer; p: string;
begin
  k := ATarget.HdSeries;
  b := ATarget.HdRow;
  if (k < 0) or (k > High(FLegends)) or (b < 0) or (b > High(FLegends[k].Selector)) then Exit;
  if FLegends[k].Selector[b].IsAll then p := '{"type":"legendAllSelect"'
  else p := '{"type":"legendInverseSelect"';
  DispatchAction(p + ',"legendId":"' + StringToJSONString(ComponentModelId('legend', k))
    + '"}');
end;

procedure TTyAdvanceChart.LegendPagerClick(const ATarget: TTyChartEventTarget);
var k, toIdx: Integer;
begin
  k := ATarget.HdSeries;
  if (k < 0) or (k > High(FLegends)) or not FLegends[k].IsScroll then Exit;
  if ATarget.HdRow = 0 then toIdx := FLegends[k].PagePrevIndex
  else toIdx := FLegends[k].PageNextIndex;
  { `scrollDataIndex != null && dispatchAction(...)` }
  if toIdx < 0 then Exit;
  DispatchAction('{"type":"legendScroll","scrollDataIndex":' + IntToStr(toIdx)
    + ',"legendId":"' + StringToJSONString(ComponentModelId('legend', k)) + '"}');
end;

procedure TTyAdvanceChart.DoLegendScroll(APayload: TJSONObject);
var
  d: TJSONData;
  legends: TTyIntegerArray;
  i, k: Integer;
  ev: TJSONObject;
begin
  d := APayload.Find('scrollDataIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    { eachComponent over the legends of subType 'scroll' the query names }
    legends := LegendQuery(APayload);
    for i := 0 to High(legends) do
    begin
      k := legends[i];
      if (k <= High(FLegendSpecs)) and FLegendSpecs[k].IsScroll then
        TyLegendSetScrollDataIndex(FOption, k, d);
    end;
  end;
  { the default update, then the event: the payload with its type renamed }
  FullUpdate;
  ev := TJSONObject(APayload.Clone);
  try
    ev.Strings['type'] := 'legendscroll';
    EmitPayloadEvent('legendscroll', ev.AsJSON);
  finally
    ev.Free;
  end;
end;

function TTyAdvanceChart.LegLive: Boolean;
begin
  Result := (FLegAnim <> nil) and (FLegAnim.ClipCount > 0);
end;

procedure TTyAdvanceChart.LegAnimDrop;
var i: Integer;
begin
  { the proxies before the driver: freeing one takes its clips off it }
  for i := 0 to High(FLegProxies) do FreeAndNil(FLegProxies[i]);
  FLegProxies := nil;
end;

procedure TTyAdvanceChart.LegAnimSync;
var
  i: Integer;
  lay: TTyLegendLayout;
  p: TTyChartAnimProxy;
  props: TTyAnimProps;
  model: TTyAnimModel;
begin
  for i := Length(FLegends) to High(FLegProxies) do FreeAndNil(FLegProxies[i]);
  SetLength(FLegProxies, Length(FLegends));
  for i := 0 to High(FLegends) do
  begin
    lay := FLegends[i];
    if not (lay.Valid and lay.IsScroll) then
    begin
      FreeAndNil(FLegProxies[i]);
      Continue;
    end;
    props := TyAnimProps([TyAnimProp('x', TyAnimNum(lay.ContentPosX)),
      TyAnimProp('y', TyAnimNum(lay.ContentPosY))]);
    p := FLegProxies[i];
    if p = nil then
    begin
      if FLegAnim = nil then FLegAnim := NewAnimDriver;
      p := TTyChartAnimProxy.Create(-1, i, 'legend.scroll');
      p.Animation := FLegAnim;
      { THE FIRST RENDER: the content group stands unscrolled }
      p.Attr(TyAnimProps([TyAnimProp('x', TyAnimNum(lay.ContentFromX)),
        TyAnimProp('y', TyAnimNum(lay.ContentFromY))]));
      FLegProxies[i] := p;
    end;
    { the cross axis is setPosition's, at once: only the scroll moves }
    if FLegendSpecs[i].Orient = tloVertical then
      p.Attr(TyAnimProps([TyAnimProp('x', TyAnimNum(lay.ContentPosX))]))
    else
      p.Attr(TyAnimProps([TyAnimProp('y', TyAnimNum(lay.ContentPosY))]));
    p.SetFinal(props);
    { `showController ? legendModel : null`: a hidden pager snaps }
    if lay.ShowController and AnimAllowed then
      model := TyAnimComponentModel(FOption.ComponentAt('legend', i), FOption.Root,
        'legend.scroll')
    else
      model := TyAnimNoModel;
    TyUpdateProps(p, props, model, TyAnimCallNoIndex);
  end;
  AnimArmTimer;
end;

procedure TTyAdvanceChart.LegendSelHover(ALegend, AIndex: Integer);
begin
  if (FLegendSelHoverLegend = ALegend) and (FLegendSelHoverIdx = AIndex) then Exit;
  FLegendSelHoverLegend := ALegend;
  FLegendSelHoverIdx := AIndex;
  { the button is drawn in the static layer: a new ink is a new picture }
  StaticDrop;
  InvalidateFrame;
end;

procedure TTyAdvanceChart.LegendBorderOf(ASlot, ARaw: Integer;
  var ASrc: TTyLegendSource);
var
  s, k: Integer;
  t: string;
  nodes: array[0..1] of TJSONObject;
  st, d: TJSONData;
  col: TTyChartColor;
begin
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  s := FBindings[ASlot].SeriesIndex;
  t := FBindings[ASlot].SeriesType;
  ASrc.HasStroke := False;
  ASrc.Stroke := 0;
  ASrc.VisualLineWidth := 0;
  { the types' own defaults: a pie's borderWidth 1 (no colour), a funnel's
    1 in the chart's ground colour (tokens.color.neutral00) }
  if t = TyPieSeriesTypeName then ASrc.VisualLineWidth := 1
  else if t = TyFunnelSeriesTypeName then
  begin
    ASrc.VisualLineWidth := 1;
    ASrc.HasStroke := True;
    ASrc.Stroke := TTyChartColor(ActiveController.Model.ResolveStyle(
      GetStyleTypeKey, StyleClass, [tysNormal]).Background.Color);
  end;
  { the series' itemStyle, then the datum's }
  nodes[0] := StSeriesNode(s);
  nodes[1] := nil;
  if ARaw >= 0 then nodes[1] := StItemNode(s, ARaw);
  for k := 0 to 1 do
  begin
    if nodes[k] = nil then Continue;
    st := nodes[k].Find('itemStyle');
    if not (st is TJSONObject) then Continue;
    d := TJSONObject(st).Find('borderColor');
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      if TyTryParseChartColor(d.AsString, col) then
      begin
        ASrc.HasStroke := True;
        ASrc.Stroke := col;
      end
      else
        ASrc.HasStroke := False;
    end;
    d := TJSONObject(st).Find('borderWidth');
    if (d <> nil) and (d.JSONType = jtNumber) then ASrc.VisualLineWidth := d.AsFloat;
  end;
  { MapSeries.getLegendIcon: the border is no border [Batch 152] }
  if t = TyMapSeriesTypeName then ASrc.HasStroke := False;
end;
