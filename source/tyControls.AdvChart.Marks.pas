unit tyControls.AdvChart.Marks;
{$mode objfpc}{$H+}
{ A bound series plus its store, turned into paint-list elements.

  THIS IS WHERE THE TIER 0 SUBSTRATE FINALLY HAS A CONSUMER. Every piece it
  uses was built and tested with nothing calling it: the columnar store holds
  the rows, the coordinate system turns a datum into a point or a cell, the
  shape record is the one description that paint and hit-test share, and the
  paint list orders and hit-tests them. Until now the control drew axes and
  nothing else, and its own diagnostics said so in as many words.

  PURE, like everything upstream of AdvChart.Measure: SysUtils, Math and the
  AdvChart units. No painter, no LCL. A colour arrives as a number because
  resolving a theme is the control's job -- the same reason the layout layer
  takes an ITyTextMeasurer instead of reaching for the painter.

  ONE RECT PER BAR, FROM DataToLayout. That function is contract (1) of the
  spec, and a bar is the shape it was designed to return: one band wide, from
  the value axis' baseline to the datum. A renderer that computed the rect
  itself would be the second producer of a number the coordinate system already
  owns -- and would get horizontal bars wrong, which is exactly the defect
  DataToLayout carried until it was made to ask which axis is the spine.

  THE WIDTH IS NOT DECIDED HERE. It cannot be: how wide a bar is depends on
  every OTHER bar series sharing the base axis, which one series cannot see.
  AdvChart.BarLayout solves that per axis and the answer arrives in the visual.
  This unit's job is to put the rect where the answer says.

  WHAT IS STILL NOT HERE. Value stacking -- several series naming one `stack`
  accumulating along the value axis -- is its own Tier 1 row; the solver
  already groups them into one COLUMN, which is the layout half of it, so they
  share a width and an offset and draw over each other. Symbols on a line, and
  the four-corner form of borderRadius, are likewise their own rows. }
interface
uses
  SysUtils, Math,
  tyControls.AdvChart.Types, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Data, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Series,
  tyControls.AdvChart.BarLayout;

type
  { How one series looks. Resolved by the control from the theme and passed in;
    this unit never asks what colour anything is. }
  TTySeriesVisual = record
    Fill: TTyChartColor;
    Stroke: TTyChartColor;
    { <= 0 means no stroke, the same rule the element style and
      TTyPainter.StrokePath both follow. }
    StrokeWidthLogical: Double;
    { Where this bar sits in its band, solved across every bar series sharing
      the base axis -- which is why it arrives rather than being computed here.
      Unsolved means no solver ran (a pure-unit caller with one series), and
      the default for exactly that case is asked of the solver too, so there is
      no second definition of what a lone bar's width is. }
    Bar: TTyBarColumn;
    { Painted front-to-back by (Z, Z2, insertion). Marks sit above the grid;
      Z2 keeps two series in a stable order relative to each other. }
    Z, Z2: Integer;
  end;

{ A visual with the defaults: a filled mark, no stroke, upstream's bar gap. }
function TySeriesVisual(AFill: TTyChartColor): TTySeriesVisual;

{ Whether this series type draws anything yet.

  EXPORTED SO THE EDITOR CAN STOP GUESSING. Its all-clear row has to tell the
  author which of their series will appear, and a second list of type names
  kept over there would be wrong the day a renderer lands here. Asking the
  renderer is the same rule that keeps the bar rect coming from DataToLayout
  instead of from arithmetic repeated at the call site.

  Case-sensitive, like TySeriesFindType: ECharts' type names are, so a series
  typed 'Bar' does not resolve and never draws. }
function TySeriesTypeHasRenderer(const AType: string): Boolean;

{ Append this series' marks to AList and answer how many were added.

  Zero is a legitimate answer and not a failure: a series whose type has no
  renderer yet, an empty store, a series bound to no axes. The control's
  diagnostics are what tell the reader why nothing was drawn -- returning a
  count rather than a boolean is so a caller can say "nothing at all was
  drawn" without inspecting the list. }
function TyBuildSeriesMarks(const ABinding: TTySeriesBinding;
  AStore: TTyDataStore; const AVisual: TTySeriesVisual;
  AList: TTyPaintList): Integer;

implementation

function TySeriesVisual(AFill: TTyChartColor): TTySeriesVisual;
begin
  Result.Fill := AFill;
  Result.Stroke := 0;
  Result.StrokeWidthLogical := 0;
  Result.Bar := Default(TTyBarColumn);
  Result.Z := 0;
  Result.Z2 := 0;
end;

{ The element every mark starts from: this series' colours, and a datum
  reference so the hit test can answer with the row the pointer is over. }
function MarkElement(const AShape: TTyChartShape; const AVisual: TTySeriesVisual;
  ASeries, ARow: Integer): TTyChartElement;
begin
  Result := TyChartElement(AShape);
  Result.Style.HasFill := AVisual.Fill <> 0;
  Result.Style.FillColor := AVisual.Fill;
  Result.Style.StrokeColor := AVisual.Stroke;
  Result.Style.StrokeWidthLogical := AVisual.StrokeWidthLogical;
  Result.Z := AVisual.Z;
  Result.Z2 := AVisual.Z2;
  Result.Silent := False;
  Result.Datum := TyChartDatum(ASeries, ARow);
end;

{ ABounds' band replaced by the solved column, ALONG the base axis.

  Along the base axis, not along x: on a horizontal bar chart the band runs
  vertically, and touching the wrong axis would change the bar's LENGTH, which
  is the value it is drawing.

  The offset is measured from the band CENTRE, upstream's convention, because
  that is the point the coordinate system hands back for a category. A lone
  default bar has Offset = -Width/2 and so stays centred. }
function PlaceInBand(const ABounds: TTyRectF; ABaseHorizontal: Boolean;
  const ACol: TTyBarColumn): TTyRectF;
var
  centre: Double;
begin
  Result := ABounds;
  { A COLUMN OF NO WIDTH COLLAPSES; it does not fall back to the band. Leaving
    ABounds alone looks like the safe branch and is the opposite: ABounds is
    the whole cell, so `barCategoryGap: '100%'` -- which solves every column to
    zero -- drew bars filling their entire band. The caller drops a collapsed
    rect, and it can only do that if one actually arrives. }
  if ABaseHorizontal then
  begin
    centre := (ABounds.Left + ABounds.Right) / 2;
    Result.Left := centre + ACol.Offset;
    Result.Right := Result.Left + ACol.Width;
  end
  else
  begin
    centre := (ABounds.Top + ABounds.Bottom) / 2;
    Result.Top := centre + ACol.Offset;
    Result.Bottom := Result.Top + ACol.Width;
  end;
end;

{ barMinHeight, applied ACROSS the base axis so a value too small to see still
  shows as something.

  Anchored on the baseline, not on the cell, because which end of the cell is
  the baseline is exactly what the Min/Max that built it threw away. The sign
  rule is upstream's and differs between the two orientations by one boundary:
  a vertical bar of value zero points in the positive direction (`<= 0`), and
  so does a horizontal one (`< 0`), which is the same answer reached from
  opposite sides of the comparison. }
function ApplyMinHeight(const ABounds: TTyRectF; ABaseHorizontal: Boolean;
  AAnchor, ABaseline, AMinHeight: Double): TTyRectF;
var
  span, sign: Double;
begin
  Result := ABounds;
  if AMinHeight <= 0 then Exit;
  span := AAnchor - ABaseline;
  if Abs(span) >= AMinHeight then Exit;
  if ABaseHorizontal then
  begin
    if span <= 0 then sign := -1 else sign := 1;
    Result.Top := Min(ABaseline, ABaseline + sign * AMinHeight);
    Result.Bottom := Max(ABaseline, ABaseline + sign * AMinHeight);
  end
  else
  begin
    if span < 0 then sign := -1 else sign := 1;
    Result.Left := Min(ABaseline, ABaseline + sign * AMinHeight);
    Result.Right := Max(ABaseline, ABaseline + sign * AMinHeight);
  end;
end;

{ The column this series draws with. Solved by the layout pass in production;
  for a caller that has not run one, the SAME solver answers for a single
  default series, so a lone bar is 0.69 of its band either way and the number
  is written down in exactly one place. }
function ColumnFor(const AVisual: TTySeriesVisual; const ABounds: TTyRectF;
  ABaseHorizontal: Boolean): TTyBarColumn;
var
  band: Double;
begin
  if AVisual.Bar.Solved then Exit(AVisual.Bar);
  if ABaseHorizontal then
    band := ABounds.Right - ABounds.Left
  else
    band := ABounds.Bottom - ABounds.Top;
  Result := TyBarColumnForOneSeries(band);
end;

type
  { What every mark builder looks like. Named so the table below can hold them,
    which is what makes the table the only list of renderers there is. }
  TTyMarkBuilder = function(const ABinding: TTySeriesBinding;
    AStore: TTyDataStore; const AVisual: TTySeriesVisual; AList: TTyPaintList;
    AColX, AColY: Integer): Integer;

function BuildBars(const ABinding: TTySeriesBinding; AStore: TTyDataStore;
  const AVisual: TTySeriesVisual; AList: TTyPaintList;
  AColX, AColY: Integer): Integer;
var
  i: Integer;
  x, y, baseline, anchor: Double;
  lay: TTyCoordLayout;
  r: TTyRectF;
  p: TTyPointF;
  col: TTyBarColumn;
  baseHoriz, haveCol: Boolean;
  shape: TTyChartShape;
begin
  Result := 0;
  baseHoriz := (ABinding.BaseAxis = nil) or ABinding.BaseAxis.Horizontal;
  haveCol := False;
  col := Default(TTyBarColumn);
  { The baseline the value axis measures from -- the same one DataToLayout used
    to build the cell, asked again because the cell's Min/Max lost which end it
    was. Only barMinHeight needs it. }
  baseline := 0;
  if ABinding.ValueAxis <> nil then
    baseline := ABinding.ValueAxis.DataToCoord(
      ABinding.ValueAxis.Scale.GetExtent.Start);
  for i := 0 to AStore.Count - 1 do
  begin
    x := AStore.Get(AColX, i);
    y := AStore.Get(AColY, i);
    { NaN IS THE SINGLE SPELLING OF NO DATA, which the store's header says for
      all four dimension types. A gap draws no bar; it does not draw a bar of
      height zero, which would read as a real measurement of nothing.

      A MUTANT OF THIS LINE SURVIVES, and it is worth writing down why rather
      than inventing a test to hide it: the rect that comes back for a NaN
      datum fails TyRectFIsValid two lines down, so the gap is caught either
      way. The check stays because it states the rule at the point the rule
      applies -- but it is not, today, the thing enforcing it. }
    if IsNan(x) or IsNan(y) then Continue;
    lay := ABinding.Cart.DataToLayout([x, y]);
    if not TyRectFIsValid(lay.Rect) then Continue;
    if not haveCol then
    begin
      col := ColumnFor(AVisual, lay.Rect, baseHoriz);
      haveCol := True;
    end;
    r := PlaceInBand(lay.Rect, baseHoriz, col);
    if col.MinHeightPx > 0 then
    begin
      p := ABinding.Cart.DataToPoint([x, y]);
      if baseHoriz then anchor := p.Y else anchor := p.X;
      r := ApplyMinHeight(r, baseHoriz, anchor, baseline, col.MinHeightPx);
    end;
    { A zero-width column draws nothing rather than an invisible rect that is
      still hit-testable -- which is what a bar on a value axis used to be. }
    if (r.Right - r.Left <= 0) or (r.Bottom - r.Top <= 0) then Continue;
    if col.RadiusPx > 0 then
      shape := TyShapeRoundRect(r, col.RadiusPx)
    else
      shape := TyShapeRect(r);
    AList.Add(MarkElement(shape, AVisual, ABinding.SeriesIndex, i));
    Inc(Result);
  end;
end;

function BuildLine(const ABinding: TTySeriesBinding; AStore: TTyDataStore;
  const AVisual: TTySeriesVisual; AList: TTyPaintList;
  AColX, AColY: Integer): Integer;
var
  i, n: Integer;
  x, y: Double;
  p: TTyPointF;
  pts: array of TTyPointF;
  el: TTyChartElement;
  v: TTySeriesVisual;
begin
  Result := 0;
  SetLength(pts, AStore.Count);
  n := 0;
  for i := 0 to AStore.Count - 1 do
  begin
    x := AStore.Get(AColX, i);
    y := AStore.Get(AColY, i);
    { A GAP BREAKS THE LINE, it does not get joined across. ECharts calls that
      connectNulls and defaults it to false, and joining by default would draw
      a segment through data that does not exist. Splitting into runs is what
      connectNulls will switch off later; today every run is its own polyline. }
    if IsNan(x) or IsNan(y) then
    begin
      if n > 1 then
      begin
        SetLength(pts, n);
        v := AVisual;
        v.Fill := 0;
        if v.StrokeWidthLogical <= 0 then v.StrokeWidthLogical := 2;
        if v.Stroke = 0 then v.Stroke := AVisual.Fill;
        el := MarkElement(TyShapePolyline(pts), v, ABinding.SeriesIndex, -1);
        AList.Add(el);
        Inc(Result);
      end;
      SetLength(pts, AStore.Count);
      n := 0;
      Continue;
    end;
    p := ABinding.Cart.DataToPoint([x, y]);
    if IsNan(p.X) or IsNan(p.Y) then Continue;
    pts[n] := p;
    Inc(n);
  end;

  if n > 1 then
  begin
    SetLength(pts, n);
    { A LINE IS A STROKE, not a fill. The series colour arrives in Fill because
      that is what a mark's colour is called; for this shape it is the pen. }
    v := AVisual;
    v.Fill := 0;
    if v.StrokeWidthLogical <= 0 then v.StrokeWidthLogical := 2;
    if v.Stroke = 0 then v.Stroke := AVisual.Fill;
    el := MarkElement(TyShapePolyline(pts), v, ABinding.SeriesIndex, -1);
    AList.Add(el);
    Inc(Result);
  end;
end;

const
  { THE ONE LIST. Two of the twenty-three types draw; a renderer arrives as a
    row here and both the drawing and the published answer follow from it.

    Type names are compared EXACTLY, the way TySeriesFindType compares them --
    ECharts' names are case-sensitive, so a series typed 'Bar' never resolves
    and never reaches this unit. A lenient match here would answer yes for a
    chart that draws nothing. }
  cRenderers: array[0..1] of record
    Name: string;
    Build: TTyMarkBuilder;
  end = (
    (Name: 'bar';  Build: @BuildBars),
    (Name: 'line'; Build: @BuildLine));

function RendererFor(const AType: string): TTyMarkBuilder;
var i: Integer;
begin
  for i := 0 to High(cRenderers) do
    if cRenderers[i].Name = AType then Exit(cRenderers[i].Build);
  Result := nil;
end;

function TySeriesTypeHasRenderer(const AType: string): Boolean;
begin
  Result := RendererFor(AType) <> nil;
end;

function TyBuildSeriesMarks(const ABinding: TTySeriesBinding;
  AStore: TTyDataStore; const AVisual: TTySeriesVisual;
  AList: TTyPaintList): Integer;
var
  colX, colY: Integer;
  build: TTyMarkBuilder;
begin
  Result := 0;
  if (AList = nil) or (AStore = nil) then Exit;
  if not ABinding.Resolved then Exit;
  { No axes is a legitimate resolved state -- a pie is not on any -- and this
    unit only knows how to draw on a cartesian. }
  if (not ABinding.HasAxes) or (ABinding.Cart = nil) then Exit;
  if (ABinding.XAxis = nil) or (ABinding.YAxis = nil) then Exit;

  { The store's columns are the coordinate dimensions in axis order, so an axis
    names its own column. Asking the store rather than assuming 0 and 1 is what
    keeps this correct for a series on the second y axis. }
  colX := AStore.DimIndexOf(ABinding.XAxis.Dim);
  colY := AStore.DimIndexOf(ABinding.YAxis.Dim);
  if (colX < 0) or (colY < 0) then Exit;

  { Anything not in the table draws nothing, on purpose: twenty-one of the
    twenty-three series types have no renderer yet, and the control's
    diagnostics are what say so. Drawing an approximation would be worse than
    drawing nothing. }
  build := RendererFor(ABinding.SeriesType);
  if build <> nil then
    Result := build(ABinding, AStore, AVisual, AList, colX, colY);
end;

end.
