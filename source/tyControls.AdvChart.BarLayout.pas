unit tyControls.AdvChart.BarLayout;
{$mode objfpc}{$H+}
{ How wide a bar is, and where in its band it sits.

  A PORT OF calcBarWidthAndOffset, read off the ECharts 6.1.0 source rather
  than off anybody's description of it. That distinction earned its keep here:
  the published option reference, this repo's generated catalog, and the first
  version of AdvChart.Marks all said the default barGap is '20%' and that a
  lone bar takes 0.8 of its band. The source says otherwise, in two places --
  BaseBarSeries.defaultOption carries a private `defaultBarGap: '10%'`, and
  barGrid.ts computes barCategoryGap as `max(35 - columns*4, 15) + '%'` when
  nobody set one. A single bar is 0.69 of its band, not 0.8.

  WHY THIS IS NOT IN Marks.pas. A bar's width is not a property of its series;
  it is a property of every bar series sharing a base axis. One series cannot
  answer it, which is why Marks has to be GIVEN the answer rather than compute
  it. The grouping input already existed and was waiting: TTyAxisSeriesIndex's
  keyed population is admitted only when the axis is the series' BASE axis, and
  its own header says it exists so bars can share a band.

  COLUMNS, NOT SERIES. Upstream works in columns keyed by stack id, so several
  series naming the same `stack` share one column -- one width, one offset.

  THIS GROUPING IS PER BASE AXIS, and it is not the same question as the one
  AdvChart.Stack answers. That unit accumulates VALUES, keyed on the stack
  string across the whole chart with no axis test at all. Two groupings, one
  word; confusing them is the obvious mistake.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface

uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Series;

type
  { What the solver has to say about one series.

    Offset is measured from the BAND CENTRE to the column's leading edge, the
    convention upstream uses, because the band centre is the point DataToPoint
    hands back for a category. A lone default bar has Offset = -Width/2. }
  TTyBarColumn = record
    Solved: Boolean;
    BandWidth: Double;
    Offset: Double;
    Width: Double;
    { itemStyle.borderRadius in pixels, scalar form. }
    RadiusPx: Double;
    { barMinHeight, in pixels along the VALUE axis. }
    MinHeightPx: Double;
  end;
  TTyBarColumnArray = array of TTyBarColumn;

{ Solve every cartesian bar series on every axis of ABuild.

  One entry per series slot, index-parallel to ABindings, so a hole or a
  non-bar series is simply left unsolved. AStores is wanted only for the
  value-axis case, where there is no band and one has to be derived from how
  close together the data actually is.

  MUST RUN AFTER THE FINAL PIXEL EXTENTS ARE WRITTEN. Band width is derived
  from the axis' pixel span, and that span is written twice per build -- once
  approximately in phase A and once for real in phase C, after the plot rect
  has been shrunk to fit the labels. Solving before phase C answers with the
  approximate band and every bar comes out slightly wrong, silently. }
function TySolveBarLayout(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  AIndex: TTyAxisSeriesIndex): TTyBarColumnArray;

{ The answer for ONE default bar series in a band of ABandWidth.

  Exported so nothing has to hard-code 0.69: it runs the same solve with one
  column and no options, which is the only honest way to state a default whose
  real definition is `max(35 - 1*4, 15)%` of the band. }
function TyBarColumnForOneSeries(ABandWidth: Double): TTyBarColumn;

{ The band width for a base axis that has no bands.

  ECharts' heuristic: the smallest strictly positive gap between adjacent
  values, scaled into pixels. Exported because it is testable on its own and
  because a wrong answer here is invisible -- nothing raises, the bars are
  merely the wrong width. AValues may be in any order and may contain NaN.
  Answers NaN when the axis is degenerate. }
function TyDerivedBandWidth(APxSpan, AScaleSpan: Double;
  const AValues: array of Double): Double;

implementation

const
  { barGrid.ts FALLBACK_BAND_WIDTH_RATIO, used when every value is the same and
    there is therefore no gap to measure. }
  cFallbackBandWidthRatio = 0.8;
  { barGrid.ts calls calcBandWidth with `min: 1`, so no solve ever sees a zero
    or NaN band. Without it a value axis with one datum divides by nothing and
    every bar comes out invisible -- and still hit-testable, which is worse
    than invisible. }
  cMinBandWidth = 1.0;
  { BaseBarSeries.defaultOption.defaultBarGap. NOT the '20%' that the option
    reference and this repo's generated catalog both state: the catalog is
    transcribed from the documentation, and the documentation is stale. }
  cDefaultBarGap = 0.10;
  { barMinWidth's own default, which is never unset upstream: barGrid.ts passes
    `get('barMinWidth') || 1`, so every auto column is floored at 1px even when
    that makes columns overlap. On a value axis that is the point. }
  cDefaultBarMinWidth = 1.0;

type
  { An option value in ECharts' three spellings plus "absent", which has to be
    a fourth state rather than a magic number: barCategoryGap is tested with
    `!= null`, so a gap of 0 IS honoured, while barWidth is tested with `&&`,
    so a width of 0 is NOT. Collapsing the two into "is it zero" gets one of
    them wrong. }
  TBarSize = record
    Present: Boolean;
    Percent: Boolean;
    Value: Double;
  end;

  TBarColumnState = record
    StackId: string;
    { NaN means "nobody said", mirroring the JS falsy-means-unset the source
      relies on. }
    Width: Double;
    MaxWidth: Double;
    MinWidth: Double;
    Offset: Double;
  end;
  TBarColumnStates = array of TBarColumnState;

function NoSize: TBarSize;
begin
  Result.Present := False;
  Result.Percent := False;
  Result.Value := 0;
end;

{ parsePositionSizeOption: a string ending in '%' is a percentage of ABase, any
  other string is an absolute number, a number is itself, and absent is NaN.
  NaN is not an error here -- it is how upstream spells "nobody said". }
function Resolve(const ASize: TBarSize; ABase: Double): Double;
begin
  if not ASize.Present then Exit(NaN);
  if ASize.Percent then
    Result := ASize.Value / 100 * ABase
  else
    Result := ASize.Value;
end;

{ JS truthiness, which is what the source's `if (barWidth && ...)` tests: NaN
  and 0 are both falsy, and both mean "ignore this knob". }
function Truthy(AValue: Double): Boolean;
begin
  Result := (not IsNan(AValue)) and (AValue <> 0);
end;

{ NOT Math.Max(0, x).

  `Max(0, <Double>)` resolves to the SINGLE overload -- the integer literal
  makes Single the cheaper conversion -- and quietly rounds every width to a
  24-bit mantissa. It is invisible: the bars are still in the right places, and
  the only symptom is that a test comparing against the formula disagrees in
  the eighth significant digit, which reads like a tolerance problem rather
  than a precision one. Written out so no overload can be chosen. }
function AtLeast(AValue, AFloor: Double): Double;
begin
  if AValue < AFloor then Result := AFloor else Result := AValue;
end;

function SizeIn(ANode: TJSONObject; const AKey: string): TBarSize;
var
  d: TJSONData;
  s: string;
  v: Double;
  fs: TFormatSettings;
begin
  Result := NoSize;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d.JSONType = jtNumber then
  begin
    Result.Present := True;
    Result.Value := d.AsFloat;
    Exit;
  end;
  if d.JSONType <> jtString then Exit;
  s := Trim(d.AsString);
  if s = '' then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if s[Length(s)] = '%' then
  begin
    if TryStrToFloat(Copy(s, 1, Length(s) - 1), v, fs) then
    begin
      Result.Present := True;
      Result.Percent := True;
      Result.Value := v;
    end;
    Exit;
  end;
  if TryStrToFloat(s, v, fs) then
  begin
    Result.Present := True;
    Result.Value := v;
  end;
end;

function FloatIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

{ The series node at ASlot, or nil. Series.pas has one of these too, private
  to its implementation; duplicating three lines beats exporting a helper whose
  name says nothing about which unit owns it. }
function SeriesNode(AOption: TTyChartOption; ASlot: Integer): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if (d <> nil) and (d is TJSONObject) then Result := TJSONObject(d);
end;

function StringIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

{ itemStyle.borderRadius, scalar form only.

  ECharts also takes a four-element array clockwise from the top-left, and a
  per-datum override. Neither is here: the shape record carries ONE radius, so
  four corners is a shape change rather than a bar change, and a per-datum
  radius has to be read where the data is read. Both are named as not-done
  rather than left half-done. }
function RadiusIn(ANode: TJSONObject): Double;
var d: TJSONData;
begin
  Result := 0;
  if ANode = nil then Exit;
  d := ANode.Find('itemStyle');
  if (d = nil) or not (d is TJSONObject) then Exit;
  Result := AtLeast(FloatIn(TJSONObject(d), 'borderRadius', 0), 0);
end;

function TyDerivedBandWidth(APxSpan, AScaleSpan: Double;
  const AValues: array of Double): Double;
var
  vals: array of Double;
  i, j, n: Integer;
  tmp, gap, minGap: Double;
begin
  Result := NaN;
  if (AScaleSpan <= 0) or (APxSpan <= 0) then Exit;

  n := 0;
  SetLength(vals, Length(AValues));
  for i := 0 to High(AValues) do
    if not IsNan(AValues[i]) then
    begin
      vals[n] := AValues[i];
      Inc(n);
    end;
  SetLength(vals, n);
  if n = 0 then Exit;

  { Insertion sort: this is one chart's bar data on one axis, already close to
    sorted, and a sort that is obviously correct beats a clever one nobody will
    re-read. }
  for i := 1 to n - 1 do
  begin
    tmp := vals[i];
    j := i - 1;
    while (j >= 0) and (vals[j] > tmp) do
    begin
      vals[j + 1] := vals[j];
      Dec(j);
    end;
    vals[j + 1] := tmp;
  end;

  minGap := Infinity;
  for i := 1 to n - 1 do
  begin
    gap := vals[i] - vals[i - 1];
    { STRICTLY positive. Duplicates are ordinary -- two series both reporting
      the same x -- and a zero gap would collapse every bar to nothing. }
    if (gap > 0) and (gap < minGap) then minGap := gap;
  end;

  { One value, or every value identical: there is no gap to measure, so
    upstream falls back to a fixed share of the whole span. }
  if IsInfinite(minGap) then
    Result := APxSpan * cFallbackBandWidthRatio
  else
    Result := APxSpan / AScaleSpan * minGap;
end;

{ The solve, over one axis' columns.

  Deliberately a transcription of barGrid.ts rather than a tidied-up
  equivalent -- including the quirk where a column with an explicit barWidth
  has its width taken out of the remainder TWICE. That is upstream behaviour,
  unchanged since 5.x, and a port that "fixes" it draws different bars from the
  chart it is copying. }
procedure SolveColumns(var ACols: TBarColumnStates; ABandWidth: Double;
  const ABarGap, ABarCategoryGap: TBarSize; AAutoCount: Integer);
var
  i, autoCount: Integer;
  remained, gapNum, gapPercent, autoWidth, finalWidth, widthSum, offset,
  lastWidth: Double;
  catGap: TBarSize;
begin
  if Length(ACols) = 0 then Exit;
  remained := ABandWidth;
  autoCount := AAutoCount;

  { Pass 1's remainder. The option reading itself happens in the caller, which
    is where the series nodes are; this is the part of pass 1 that belongs with
    the arithmetic. }
  for i := 0 to High(ACols) do
    if Truthy(ACols[i].Width) then
      remained := remained - Min(remained, ACols[i].Width);

  catGap := ABarCategoryGap;
  if not catGap.Present then
  begin
    { `max(35 - columns*4, 15) + '%'`: more columns in a group means a smaller
      gap between groups, or the columns get too thin. One column gives 31%,
      which is where a lone bar's 0.69 of the band comes from. }
    catGap.Present := True;
    catGap.Percent := True;
    catGap.Value := Max(35 - Length(ACols) * 4, 15);
  end;
  gapNum := Resolve(catGap, ABandWidth);
  if IsNan(gapNum) then gapNum := 0;

  { barGap resolves against 1, not against the band: '10%' is 0.1, and a bare
    number is already a ratio. '-100%' is -1, which is not special-cased
    anywhere -- it simply makes the arithmetic below collapse every column onto
    one offset at full width. }
  if ABarGap.Present then
    gapPercent := Resolve(ABarGap, 1)
  else
    gapPercent := cDefaultBarGap;
  if IsNan(gapPercent) then gapPercent := 0;

  autoWidth := 0;
  if autoCount > 0 then
    autoWidth := AtLeast((remained - gapNum)
      / (autoCount + (autoCount - 1) * gapPercent), 0);

  for i := 0 to High(ACols) do
  begin
    if not Truthy(ACols[i].Width) then
    begin
      finalWidth := autoWidth;
      if Truthy(ACols[i].MaxWidth) and (ACols[i].MaxWidth < finalWidth) then
        finalWidth := Min(ACols[i].MaxWidth, remained);
      { minWidth outranks everything, and the source says why in as many words:
        it decides whether the bar is VISIBLE at all, so it is clamped by
        neither maxWidth nor the band. Bars are allowed to overlap. }
      if Truthy(ACols[i].MinWidth) and (ACols[i].MinWidth > finalWidth) then
        finalWidth := ACols[i].MinWidth;
      { Only a column that actually MOVED is pinned; one that landed on
        autoWidth stays auto and is re-solved below. }
      if finalWidth <> autoWidth then
      begin
        ACols[i].Width := finalWidth;
        remained := remained - (finalWidth + gapPercent * finalWidth);
        Dec(autoCount);
      end;
    end
    else
    begin
      { An explicit barWidth is outranked by barMinWidth and barMaxWidth, the
        way CSS width is outranked by min-width and max-width. }
      finalWidth := ACols[i].Width;
      if Truthy(ACols[i].MaxWidth) and (ACols[i].MaxWidth < finalWidth) then
        finalWidth := ACols[i].MaxWidth;
      if Truthy(ACols[i].MinWidth) then
        finalWidth := AtLeast(finalWidth, ACols[i].MinWidth);
      ACols[i].Width := finalWidth;
      remained := remained - (finalWidth + gapPercent * finalWidth);
      Dec(autoCount);
    end;
  end;

  { Recomputed over what is left. That is the whole point of two passes: a
    column pinned by min/max width hands its slack back to the others. }
  autoWidth := 0;
  if autoCount > 0 then
    autoWidth := AtLeast((remained - gapNum)
      / (autoCount + (autoCount - 1) * gapPercent), 0);

  widthSum := 0;
  lastWidth := 0;
  for i := 0 to High(ACols) do
  begin
    if not Truthy(ACols[i].Width) then ACols[i].Width := autoWidth;
    lastWidth := ACols[i].Width;
    widthSum := widthSum + ACols[i].Width * (1 + gapPercent);
  end;
  { The trailing gap after the final column is not part of the group. }
  widthSum := widthSum - lastWidth * gapPercent;

  offset := -widthSum / 2;
  for i := 0 to High(ACols) do
  begin
    ACols[i].Offset := offset;
    offset := offset + ACols[i].Width * (1 + gapPercent);
  end;
end;

function TyBarColumnForOneSeries(ABandWidth: Double): TTyBarColumn;
var
  cols: TBarColumnStates;
  band: Double;
begin
  band := AtLeast(ABandWidth, cMinBandWidth);
  SetLength(cols, 1);
  cols[0].StackId := '';
  cols[0].Width := NaN;
  cols[0].MaxWidth := NaN;
  cols[0].MinWidth := cDefaultBarMinWidth;
  cols[0].Offset := 0;
  SolveColumns(cols, band, NoSize, NoSize, 1);
  Result.Solved := True;
  Result.BandWidth := band;
  Result.Offset := cols[0].Offset;
  Result.Width := cols[0].Width;
  Result.RadiusPx := 0;
  Result.MinHeightPx := 0;
end;

{ Every base-dimension value of every bar series on this axis, which is what
  the value-axis band heuristic measures the gaps between. }
function BaseValuesOnAxis(const AStores: array of TTyDataStore;
  const ASeries: TTyIntegerArray; AAxis: TTyAxis): TTyDoubleArray;
var
  k, si, col, r, n: Integer;
begin
  Result := nil;
  n := 0;
  for k := 0 to High(ASeries) do
  begin
    si := ASeries[k];
    if (si < 0) or (si > High(AStores)) then Continue;
    if AStores[si] = nil then Continue;
    col := AStores[si].DimIndexOf(AAxis.Dim);
    if col < 0 then Continue;
    for r := 0 to AStores[si].Count - 1 do
    begin
      if n > High(Result) then SetLength(Result, Max(16, n * 2));
      Result[n] := AStores[si].Get(col, r);
      Inc(n);
    end;
  end;
  SetLength(Result, n);
end;

function TySolveBarLayout(AOption: TTyChartOption; ABuild: TTyChartBuild;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  AIndex: TTyAxisSeriesIndex): TTyBarColumnArray;
var
  g, a, i: Integer;
  gb: TTyGridBuild;
  key: string;
  answer: TTyBarColumnArray;

  procedure DoAxis(AAxis: TTyAxis);
  var
    onIt: TTyIntegerArray;
    cols: TBarColumnStates;
    slotOf: array of Integer;
    stackId: string;
    node: TJSONObject;
    band, span: Double;
    autoCount, k, m, si: Integer;
    barGap, catGap, v: TBarSize;
    found: Boolean;
  begin
    if AAxis = nil then Exit;
    onIt := AIndex.SeriesOnAxisOfKey(AAxis, key);
    if Length(onIt) = 0 then Exit;

    { THE BAND. A category axis has one; anything else has to have one derived
      from the data, because a bar still has to be SOME width. Without this a
      bar on a value axis got a zero-width rect: it drew nothing and was still
      hit-testable, which is invisible and in the way at once. }
    band := AAxis.BandWidth;
    if band <= 0 then
    begin
      span := TyRangeSpan(AAxis.Scale.GetExtent);
      band := TyDerivedBandWidth(Abs(AAxis.PxStop - AAxis.PxStart), span,
        BaseValuesOnAxis(AStores, onIt, AAxis));
    end;
    if IsNan(band) then band := cMinBandWidth;
    band := AtLeast(band, cMinBandWidth);

    barGap := NoSize;
    catGap := NoSize;
    SetLength(cols, 0);
    SetLength(slotOf, Length(onIt));
    autoCount := 0;

    for k := 0 to High(onIt) do
    begin
      si := onIt[k];
      node := SeriesNode(AOption, si);

      { defaultBarGap is seeded from the FIRST series only, while barGap and
        barCategoryGap are LAST-wins across the axis. That inconsistency is
        upstream's and is kept deliberately: these read as per-series in the
        option tree but act per-axis, and copying the tie-break is the only way
        two charts of the same option agree. }
      if k = 0 then
      begin
        barGap.Present := True;
        barGap.Percent := False;
        barGap.Value := cDefaultBarGap;
      end;

      stackId := StringIn(node, 'stack');
      if stackId = '' then stackId := '__ty_stack_' + IntToStr(si);

      found := False;
      m := 0;
      while m <= High(cols) do
      begin
        if cols[m].StackId = stackId then
        begin
          found := True;
          Break;
        end;
        Inc(m);
      end;
      if not found then
      begin
        m := Length(cols);
        SetLength(cols, m + 1);
        cols[m].StackId := stackId;
        cols[m].Width := NaN;
        cols[m].MaxWidth := NaN;
        cols[m].MinWidth := NaN;
        cols[m].Offset := 0;
        Inc(autoCount);
      end;
      slotOf[k] := m;

      { barWidth is FIRST-wins within a column: only the first series of a
        stack that supplies one is heard. }
      v := SizeIn(node, 'barWidth');
      if v.Present and not Truthy(cols[m].Width) then
        cols[m].Width := Resolve(v, band);

      v := SizeIn(node, 'barMaxWidth');
      if v.Present then cols[m].MaxWidth := Resolve(v, band);

      { LAST-WINS, INCLUDING THE DEFAULT, which is not obvious and matters. The
        source reads `parsePercent(get('barMinWidth') || 1, band)`, so the value
        is never null and the assignment always fires -- meaning a later series
        in the same column that says nothing OVERWRITES an earlier one's
        explicit barMinWidth with the default 1. Treating the default as
        "leave what is there" would keep the earlier value and quietly draw a
        wider bar than the chart being copied. }
      v := SizeIn(node, 'barMinWidth');
      if v.Present then
        cols[m].MinWidth := Resolve(v, band)
      else
        cols[m].MinWidth := cDefaultBarMinWidth;

      v := SizeIn(node, 'barGap');
      if v.Present then barGap := v;
      v := SizeIn(node, 'barCategoryGap');
      if v.Present then catGap := v;
    end;

    SolveColumns(cols, band, barGap, catGap, autoCount);

    for k := 0 to High(onIt) do
    begin
      si := onIt[k];
      if (si < 0) or (si > High(answer)) then Continue;
      node := SeriesNode(AOption, si);
      m := slotOf[k];
      answer[si].Solved := True;
      answer[si].BandWidth := band;
      answer[si].Offset := cols[m].Offset;
      answer[si].Width := cols[m].Width;
      answer[si].RadiusPx := RadiusIn(node);
      answer[si].MinHeightPx := AtLeast(FloatIn(node, 'barMinHeight', 0), 0);
    end;
  end;

begin
  SetLength(answer, Length(ABindings));
  for i := 0 to High(answer) do
  begin
    answer[i].Solved := False;
    answer[i].BandWidth := 0;
    answer[i].Offset := 0;
    answer[i].Width := 0;
    answer[i].RadiusPx := 0;
    answer[i].MinHeightPx := 0;
  end;
  Result := answer;
  if (AOption = nil) or (ABuild = nil) or (AIndex = nil) then Exit;

  { The one key the index buckets bars under. Asking for it by name rather than
    counting series here is what stops a line series sharing the axis from
    being counted as a bar -- which would make every bar half as wide on a
    chart that looks otherwise right. }
  key := TySeriesStatKey('bar', 'cartesian2d');

  for g := 0 to ABuild.GridCount - 1 do
  begin
    gb := ABuild.Grid(g);
    for a := 0 to gb.XAxisCount - 1 do DoAxis(gb.XAxis(a));
    for a := 0 to gb.YAxisCount - 1 do DoAxis(gb.YAxis(a));
  end;
  Result := answer;
end;

end.
