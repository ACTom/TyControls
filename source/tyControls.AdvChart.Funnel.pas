unit tyControls.AdvChart.Funnel;
{$mode objfpc}{$H+}
{ The funnel: a stack of trapezoids whose widths are the data.

  IT IS NOT A PIE WITH STRAIGHT EDGES, and the difference is where the values
  go. A pie turns each value into an ANGLE and the whole disc is the total; a
  funnel turns each value into a WIDTH against a shared scale, and the stack's
  height has nothing to do with the data at all -- it is the view divided by
  the number of rows. So a funnel with one huge value and four small ones is
  five equally tall bands, four of them nearly invisible, which is exactly what
  upstream draws and exactly what a reader of a pie would not expect.

  EACH BAND IS A TRAPEZOID BETWEEN TWO EDGES: its own value's edge and the NEXT
  row's. The last row has no next, and upstream reaches that case by indexing
  one past the end of a JavaScript array -- which answers `undefined`, which
  `data.get` turns into NaN, which `|| 0` turns into zero. The tip is therefore
  the width of value ZERO, which with the default `minSize: '0%'` is a point.
  A Pascal port has to synthesise that phantom edge on purpose: indexing past
  the end here is a range error, and clamping to the last row would draw a
  rectangle where upstream draws a triangle.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL --
  colours arrive as numbers and the measuring goes through ITyTextMeasurer,
  the same rule the pie and the marks layer follow. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Series,
  tyControls.AdvChart.Measure, tyControls.AdvChart.LabelOpt,
  tyControls.AdvChart.Labels;

const
  TyFunnelSeriesTypeName = 'funnel';

type
  { `descending` is the default -- widest at the top. `none` is the ONLY value
    that leaves the data in its own order: upstream's guard is
    `sort !== 'none'`, so every other string, including a misspelling, sorts
    descending. }
  TTyFunnelSort = (fsDescending, fsAscending, fsNone);

  { ONE ENUM FOR BOTH ORIENTATIONS, because upstream has one option with two
    disjoint vocabularies -- left/center/right when vertical, top/center/bottom
    when horizontal -- and each switch handles only its own three. The other
    three are type-legal upstream and fall through to an UNINITIALISED local,
    which JavaScript renders as NaN geometry and Pascal would render as stack
    garbage. Collapsing them to start/centre/end is what makes that
    unrepresentable. }
  TTyFunnelAlign = (faStart, faCentre, faEnd);

  TTyFunnelSpec = record
    { left/top/right/bottom/width/height. The defaults are 80/60/80/65 with no
      size -- a real inset, unlike the pie's zero box, so a funnel does not
      reach the edges of the control. }
    Box: TTyBoxSpec;
    MinSize, MaxSize: TTyBoxValue;
    { `min` and `max` are ABSENT from upstream's defaultOption, and the absence
      is load-bearing: min falls back to Min(dataMin, 0) and max to dataMax,
      with no Max(..., 0) on the second. The two are asymmetric on purpose. A
      sentinel cannot express this -- `min: 0` is a real instruction. }
    HasMin: Boolean;
    Min_: Double;
    HasMax: Boolean;
    Max_: Double;
    Sort: TTyFunnelSort;
    Horizontal: Boolean;
    GapPx: Double;
    Align: TTyFunnelAlign;
  end;

  { One band, and the four corners it was given.

    THE CORNER ORDER DIFFERS BETWEEN ORIENTATIONS, and the label pass depends
    on it: vertically the points run top-left, top-right, bottom-right,
    bottom-left; horizontally left-top, left-bottom, right-bottom, right-top.
    Normalising them to one winding would silently move every label. }
  TTyFunnelItem = record
    RawIndex: Integer;
    Index: Integer;
    Value: Double;
    Points: array[0..3] of TTyPointF;
  end;
  TTyFunnelItemArray = array of TTyFunnelItem;

  TTyFunnelLayout = record
    { False when there was no store, no value column, or no room. }
    Valid: Boolean;
    ViewRect: TTyRectF;
    Horizontal: Boolean;
    Items: TTyFunnelItemArray;
  end;

  { What a band is painted with. The colours arrive per RAW row because a
    funnel colours by datum, exactly as a pie does. }
  TTyFunnelVisual = record
    Fills: array of TTyChartColor;
    Stroke: TTyChartColor;
    StrokeWidthLogical: Double;
    Alpha: Double;
    Z, Z2: Integer;
  end;

  { Where a band's words go.

    FIVE OF THESE ARE "INSIDE" and the rest are not -- upstream's test is a
    literal list of five, so zrender's own `insideTop`, `insideBottomRight`
    and the rest are type-legal, fall through to the outside path and land on
    the fallback. Dead options, and the enum says so by not having them.

    `outer` IS THE DEFAULT AND IT IS NOT A PLACE OF ITS OWN: it reaches the
    same branch as `right` on a vertical funnel and as `bottom` on a
    horizontal one, because that branch is the `else`. }
  TTyFunnelLabelPosition = (
    flpOuter, flpLeft, flpRight, flpTop, flpBottom,
    flpInside, flpInsideLeft, flpInsideRight);

  TTyFunnelLabelSpec = record
    Show: Boolean;
    Position: TTyFunnelLabelPosition;
    { labelLine. `show` is ANDed with the label's own at option-normalisation
      time upstream, not at draw time -- a series that hides its labels has
      already had its guide lines switched off in the resolved option, and
      reading the two separately at draw time makes the emphasis state
      disagree with the normal one. }
    LineShow: Boolean;
    LineLengthLogical: Double;
    LineWidthLogical: Double;
    { The words. Empty means the datum's name, which is upstream's default. }
    Formatter: string;
    HasFormatter: Boolean;
  end;

  { What the words are drawn with. Resolved by the control, like every other
    ink record in this family. }
  TTyFunnelLabelInk = record
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    { Three luminance bands for a label over its own band, and the theme's own
      ink for one outside. }
    InsideColour: array[0..2] of TTyChartColor;
    OutsideColour: TTyChartColor;
  end;

function TyFunnelLabelSpecDefault: TTyFunnelLabelSpec;
function TyFunnelLabelSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ABase: TTyFunnelLabelSpec): TTyFunnelLabelSpec;

{ Append this funnel's labels, and the lines that point at them, to AList.

  AFills is indexed by RAW ROW -- an inside label's contrast comes from the
  band's own colour, and so does the guide line's ink. }
function TyBuildFunnelLabels(const ABinding: TTySeriesBinding;
  const ALayout: TTyFunnelLayout; const ASpec: TTyFunnelLabelSpec;
  const AInk: TTyFunnelLabelInk; const AFills: array of TTyChartColor;
  AStore: TTyDataStore; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;

function TyFunnelSpecDefault: TTyFunnelSpec;
function TyFunnelSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyFunnelSpec;
function TyFunnelVisual: TTyFunnelVisual;

{ The whole geometry, from the viewport the control hands over.

  AViewport is the CONTROL's rect and not a grid's: a funnel is laid out
  against the canvas, and its own left/top/right/bottom shrink that. }
function TyFunnelLayoutOf(const ASpec: TTyFunnelSpec; const AViewport: TTyRectF;
  AStore: TTyDataStore; ADim: Integer): TTyFunnelLayout;

{ The bands, into the paint list. }
function TyBuildFunnelMarks(const ABinding: TTySeriesBinding;
  const ALayout: TTyFunnelLayout; const AVisual: TTyFunnelVisual;
  AList: TTyPaintList): Integer;

{ ---- the arithmetic, exported because each is worth testing alone ---- }

{ upstream's linearMap with clamp, INCLUDING its degenerate-domain rule.

  When the domain has no width the answer is the MIDPOINT of the range, not
  its start and not zero -- and that case is the common one, because every
  value being equal is what a funnel of equal steps looks like. A port that
  guarded "denominator is zero, answer zero" draws nothing exactly when
  upstream draws half-width bands. }
function TyFunnelMap(AValue, ADomainLo, ADomainHi, ARangeLo,
  ARangeHi: Double): Double;

{ The order the bands are laid out in. Answers view-space row indices.

  STABLE. JavaScript's Array#sort is, so upstream's ties keep data order, and
  an unstable sort would shuffle equal values differently on every render of
  one chart. }
function TyFunnelOrder(AStore: TTyDataStore; ADim: Integer;
  ASort: TTyFunnelSort): TTyIntegerArray;

implementation

function TyFunnelSpecDefault: TTyFunnelSpec;
begin
  Result := Default(TTyFunnelSpec);
  { 80 / 60 / 80 / 65 -- FunnelSeries.ts:161-164. A real inset, and the reason
    a default funnel leaves room for its own labels. }
  Result.Box := TyBoxSpec;
  Result.Box.Left := TyBoxPx(80);
  Result.Box.Top := TyBoxPx(60);
  Result.Box.Right := TyBoxPx(80);
  Result.Box.Bottom := TyBoxPx(65);
  Result.MinSize := TyBoxPercent(0);
  Result.MaxSize := TyBoxPercent(100);
  Result.HasMin := False;
  Result.HasMax := False;
  Result.Sort := fsDescending;
  Result.Horizontal := False;
  Result.GapPx := 0;
  Result.Align := faCentre;
end;

function TyFunnelVisual: TTyFunnelVisual;
begin
  Result := Default(TTyFunnelVisual);
  Result.Alpha := 1;
  Result.StrokeWidthLogical := 1;
  Result.Z := 2;
  Result.Z2 := 0;
end;

{ A box value out of one option key, or ADefault. }
function BoxValueOf(ANode: TJSONObject; const AKey: string;
  const ADefault: TTyBoxValue): TTyBoxValue;
var
  d: TJSONData;
  s: string;
  v: Double;
  fs: TFormatSettings;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  if d.JSONType = jtNumber then Exit(TyBoxPx(d.AsFloat));
  if d.JSONType <> jtString then Exit;
  s := Trim(d.AsString);
  if s = '' then Exit;
  { The presets upstream's parsePositionOption accepts, and they reach a
    funnel's minSize as readily as a grid's left. `center` and `middle` are
    half, the near words are nothing, the far words are all of it. }
  if (s = 'center') or (s = 'middle') then Exit(TyBoxPercent(50));
  if (s = 'left') or (s = 'top') then Exit(TyBoxPercent(0));
  if (s = 'right') or (s = 'bottom') then Exit(TyBoxPercent(100));
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if s[Length(s)] = '%' then
  begin
    if TryStrToFloat(Copy(s, 1, Length(s) - 1), v, fs) then
      Result := TyBoxPercent(v);
    Exit;
  end;
  if TryStrToFloat(s, v, fs) then Result := TyBoxPx(v);
end;

function TyFunnelSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyFunnelSpec;
var
  node: TJSONObject;
  d: TJSONData;
  s: string;
begin
  Result := TyFunnelSpecDefault;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);

  Result.Box.Left := BoxValueOf(node, 'left', Result.Box.Left);
  Result.Box.Top := BoxValueOf(node, 'top', Result.Box.Top);
  Result.Box.Right := BoxValueOf(node, 'right', Result.Box.Right);
  Result.Box.Bottom := BoxValueOf(node, 'bottom', Result.Box.Bottom);
  Result.Box.Width := BoxValueOf(node, 'width', Result.Box.Width);
  Result.Box.Height := BoxValueOf(node, 'height', Result.Box.Height);
  Result.MinSize := BoxValueOf(node, 'minSize', Result.MinSize);
  Result.MaxSize := BoxValueOf(node, 'maxSize', Result.MaxSize);

  d := node.Find('min');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasMin := True;
    Result.Min_ := d.AsFloat;
  end;
  d := node.Find('max');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasMax := True;
    Result.Max_ := d.AsFloat;
  end;

  d := node.Find('sort');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    s := d.AsString;
    { `none` IS THE ONLY WORD THAT TURNS SORTING OFF. Upstream's guard is
      `sort !== 'none'`, so `ascending` sorts ascending and everything else --
      including a typo -- sorts descending. Reproduced rather than tightened:
      a whitelist here would make a misspelling draw data order, which is a
      different chart from the one ECharts draws. }
    if s = 'ascending' then Result.Sort := fsAscending
    else if s = 'none' then Result.Sort := fsNone
    else Result.Sort := fsDescending;
  end;

  d := node.Find('orient');
  { STRICT EQUALITY AGAINST 'horizontal', upstream's own test -- anything else,
    garbage included, is vertical. }
  Result.Horizontal := (d <> nil) and (d.JSONType = jtString)
    and (d.AsString = 'horizontal');

  d := node.Find('gap');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.GapPx := d.AsFloat;
    if IsNan(Result.GapPx) or IsInfinite(Result.GapPx) then Result.GapPx := 0;
  end;

  d := node.Find('funnelAlign');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    s := d.AsString;
    { THE TWO VOCABULARIES COLLAPSE ONTO ONE AXIS. Upstream's switch handles
      only the three words belonging to the current orientation and leaves the
      local UNSET for the other three -- NaN geometry there, stack garbage
      here. Accepting both spellings is a deliberate divergence, and the
      better answer: `funnelAlign: 'top'` on a vertical funnel means the same
      thing as `left`, and drawing nothing for it helps nobody. }
    if (s = 'left') or (s = 'top') then Result.Align := faStart
    else if (s = 'right') or (s = 'bottom') then Result.Align := faEnd
    else Result.Align := faCentre;
  end;
end;

function TyFunnelMap(AValue, ADomainLo, ADomainHi, ARangeLo,
  ARangeHi: Double): Double;
begin
  { THE RULE MOVED to the unit where TTyBoxValue lives, because a gauge wanted
    it too and a gauge asking a FUNNEL how to carry a value across an interval
    is the borrowed-name mistake again. Only the name is here, and only because
    this unit's own tests call it. }
  Result := TyLinearMap(AValue, ADomainLo, ADomainHi, ARangeLo, ARangeHi, True);
end;

function TyFunnelOrder(AStore: TTyDataStore; ADim: Integer;
  ASort: TTyFunnelSort): TTyIntegerArray;
var
  i, j, n: Integer;
  key: Integer;
  vals: TTyDoubleArray;

  { Does A belong before B? NaN compares as equal to everything, which is what
    a JavaScript comparator returning NaN comes to -- the sort treats it as a
    tie and a stable sort then leaves it where it was. }
  function Before(A, B: Integer): Boolean;
  begin
    if IsNan(vals[A]) or IsNan(vals[B]) then Exit(False);
    if ASort = fsAscending then Result := vals[A] < vals[B]
    else Result := vals[A] > vals[B];
  end;

begin
  Result := nil;
  if AStore = nil then Exit;
  n := AStore.Count;
  SetLength(Result, n);
  SetLength(vals, n);
  for i := 0 to n - 1 do
  begin
    Result[i] := i;
    if ADim >= 0 then vals[i] := AStore.Get(ADim, i) else vals[i] := NaN;
  end;
  if ASort = fsNone then Exit;
  { INSERTION SORT, stable by construction. A funnel has as many rows as a
    person is willing to read, so the shape of the sort is what matters and
    its complexity is not. }
  for i := 1 to n - 1 do
  begin
    key := Result[i];
    j := i - 1;
    while (j >= 0) and Before(key, Result[j]) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := key;
  end;
end;

function TyFunnelLayoutOf(const ASpec: TTyFunnelSpec; const AViewport: TTyRectF;
  AStore: TTyDataStore; ADim: Integer): TTyFunnelLayout;
var
  order: TTyIntegerArray;
  n, i, k: Integer;
  viewW, viewH, viewSize, crossSize: Double;
  sizeLo, sizeHi, lo, hi, v: Double;
  itemSize, gap, cursor, extent: Double;
  x, y: Double;
  haveAny: Boolean;

  { One edge -- TWO POINTS, not a band. AOrder is an index into `order`, and
    one past the end is the phantom tip. }
  procedure EdgeAt(AOrderIndex: Integer; AOffset: Double;
    out AP0, AP1: TTyPointF);
  var
    val, size, base: Double;
  begin
    { THE PHANTOM EDGE. Upstream reaches it by indexing one past the end of an
      array, getting undefined, getting NaN out of the store and then zero out
      of `|| 0`. Said here on purpose, because indexing past the end in Pascal
      is a range error and clamping to the last row would draw a rectangle
      where upstream draws a tip. }
    if (AOrderIndex < 0) or (AOrderIndex > High(order)) then val := 0
    else
    begin
      val := AStore.Get(ADim, order[AOrderIndex]);
      if IsNan(val) then val := 0;
    end;
    size := TyFunnelMap(val, lo, hi, sizeLo, sizeHi);
    if ASpec.Horizontal then
    begin
      case ASpec.Align of
        faStart: base := y;
        faEnd: base := y + (viewH - size);
      else
        base := y + (viewH - size) / 2;
      end;
      AP0 := TyPointF(AOffset, base);
      AP1 := TyPointF(AOffset, base + size);
    end
    else
    begin
      case ASpec.Align of
        faStart: base := x;
        faEnd: base := x + (viewW - size);
      else
        base := x + (viewW - size) / 2;
      end;
      AP0 := TyPointF(base, AOffset);
      AP1 := TyPointF(base + size, AOffset);
    end;
  end;

var
  s0, s1, e0, e1: TTyPointF;
begin
  Result := Default(TTyFunnelLayout);
  Result.Horizontal := ASpec.Horizontal;
  Result.ViewRect := TySolveBox(ASpec.Box, TyFixedContainer(AViewport));
  if not TyRectFIsValid(Result.ViewRect) then Exit;
  if AStore = nil then Exit;
  if (ADim < 0) or (ADim >= AStore.DimCount) then Exit;
  n := AStore.Count;
  { ZERO ROWS IS A DIVISION BY ZERO BELOW. JavaScript answers NaN and runs the
    loop no times; Pascal raises. }
  if n = 0 then Exit;

  viewW := TyRectFWidth(Result.ViewRect);
  viewH := TyRectFHeight(Result.ViewRect);
  if ASpec.Horizontal then
  begin
    viewSize := viewW;
    crossSize := viewH;
  end
  else
  begin
    viewSize := viewH;
    crossSize := viewW;
  end;

  { THE PERCENT BASE IS THE CROSS AXIS, never the canvas and never the along
    axis: a value becomes a WIDTH on a vertical funnel. }
  sizeLo := TyBoxResolve(ASpec.MinSize, crossSize);
  sizeHi := TyBoxResolve(ASpec.MaxSize, crossSize);

  { THE TWO FALLBACKS ARE ASYMMETRIC and upstream means them to be: min is
    pulled down to at most zero, max is taken raw with no floor. So
    all-positive data spans 0..largest and the smallest band is not zero-width
    by construction -- it is whatever its share of the range is. }
  lo := Infinity;
  hi := NegInfinity;
  haveAny := False;
  for i := 0 to n - 1 do
  begin
    v := AStore.Get(ADim, i);
    if IsNan(v) or IsInfinite(v) then Continue;
    if v < lo then lo := v;
    if v > hi then hi := v;
    haveAny := True;
  end;
  if not haveAny then
  begin
    lo := 0;
    hi := 0;
  end;
  if ASpec.HasMin then lo := ASpec.Min_ else lo := Min(lo, Double(0));
  if ASpec.HasMax then hi := ASpec.Max_;

  order := TyFunnelOrder(AStore, ADim, ASpec.Sort);
  itemSize := (viewSize - ASpec.GapPx * (n - 1)) / n;
  gap := ASpec.GapPx;
  x := Result.ViewRect.Left;
  y := Result.ViewRect.Top;

  { ASCENDING IS FOUR COUPLED CHANGES, not one. The step and the gap flip
    sign, the cursor starts at the FAR edge, and the order is reversed -- so
    the widest band ends up at the bottom and the funnel points the other way.
    Doing three of the four draws a funnel off the edge of its own box. }
  if ASpec.Sort = fsAscending then
  begin
    itemSize := -itemSize;
    gap := -gap;
    if ASpec.Horizontal then x := Result.ViewRect.Right
    else y := Result.ViewRect.Bottom;
    for i := 0 to Length(order) div 2 - 1 do
    begin
      k := order[i];
      order[i] := order[High(order) - i];
      order[High(order) - i] := k;
    end;
  end;

  if ASpec.Horizontal then cursor := x else cursor := y;
  SetLength(Result.Items, Length(order));
  for i := 0 to High(order) do
  begin
    extent := itemSize;
    EdgeAt(i, cursor, s0, s1);
    EdgeAt(i + 1, cursor + extent, e0, e1);
    Result.Items[i].Index := order[i];
    Result.Items[i].RawIndex := AStore.GetRawIndex(order[i]);
    Result.Items[i].Value := AStore.Get(ADim, order[i]);
    { start ++ reverse(end). The winding differs between orientations and the
      label pass reads the corners by index, so this order is contract. }
    Result.Items[i].Points[0] := s0;
    Result.Items[i].Points[1] := s1;
    Result.Items[i].Points[2] := e1;
    Result.Items[i].Points[3] := e0;
    cursor := cursor + extent + gap;
  end;
  Result.Valid := True;
end;

function TyBuildFunnelMarks(const ABinding: TTySeriesBinding;
  const ALayout: TTyFunnelLayout; const AVisual: TTyFunnelVisual;
  AList: TTyPaintList): Integer;
var
  i, k: Integer;
  poly: array of TTyPointF;
  el: TTyChartElement;
begin
  Result := 0;
  if (AList = nil) or not ALayout.Valid then Exit;
  SetLength(poly, 4);
  for i := 0 to High(ALayout.Items) do
  begin
    for k := 0 to 3 do poly[k] := ALayout.Items[i].Points[k];
    { A BAND WITH NO AREA IS NOT DRAWN, rather than drawn as an invisible
      shape that is still hittable -- which is what a zero-value row with
      `minSize: '0%'` would otherwise leave behind. }
    if (Abs(poly[0].X - poly[2].X) < 1e-9)
      and (Abs(poly[0].Y - poly[2].Y) < 1e-9) then Continue;
    el := TyChartElement(TyShapePolygon(poly));
    el.Style.HasFill := True;
    { KEYED ON THE RAW ROW, not on the band's place in the stack. A funnel is
      SORTED, so the two are different numbers for almost every chart -- and a
      colour keyed on position would recolour the whole funnel the moment one
      value changed enough to move. }
    if (Length(AVisual.Fills) > 0) and (ALayout.Items[i].RawIndex >= 0)
      and (ALayout.Items[i].RawIndex <= High(AVisual.Fills)) then
      el.Style.FillColor := AVisual.Fills[ALayout.Items[i].RawIndex]
    else
      el.Style.FillColor := 0;
    el.Style.StrokeColor := AVisual.Stroke;
    el.Style.StrokeWidthLogical := AVisual.StrokeWidthLogical;
    el.Style.Alpha := AVisual.Alpha;
    el.Z := AVisual.Z;
    el.Z2 := AVisual.Z2;
    el.Silent := False;
    { BOTH ROW SPACES. A funnel's bands are laid out in sorted order, so the
      band's position in the layout is neither the view row nor the raw one --
      the same reason a pie carries both. }
    el.Datum := TyChartDatum(ABinding.SeriesIndex, ALayout.Items[i].Index,
      ALayout.Items[i].RawIndex);
    AList.Add(el);
    Inc(Result);
  end;
end;

{ ==================== labels ==================== }

function TyFunnelLabelSpecDefault: TTyFunnelLabelSpec;
begin
  Result := Default(TTyFunnelLabelSpec);
  Result.Show := True;
  Result.Position := flpOuter;
  Result.LineShow := True;
  Result.LineLengthLogical := 20;
  Result.LineWidthLogical := 1;
end;

function TyFunnelLabelSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ABase: TTyFunnelLabelSpec): TTyFunnelLabelSpec;
var
  node, lbl, line, ls: TJSONObject;
  d: TJSONData;
  s: string;
begin
  Result := ABase;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);

  d := node.Find('label');
  if d is TJSONObject then
  begin
    lbl := TJSONObject(d);
    d := lbl.Find('show');
    if (d <> nil) and (d.JSONType = jtBoolean) then Result.Show := d.AsBoolean;
    d := lbl.Find('position');
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      s := d.AsString;
      if (s = 'inner') or (s = 'inside') or (s = 'center') then
        Result.Position := flpInside
      else if s = 'insideLeft' then Result.Position := flpInsideLeft
      else if s = 'insideRight' then Result.Position := flpInsideRight
      else if s = 'left' then Result.Position := flpLeft
      else if s = 'right' then Result.Position := flpRight
      else if s = 'top' then Result.Position := flpTop
      else if s = 'bottom' then Result.Position := flpBottom
      else
        { EVERYTHING ELSE IS THE FALLBACK, which is what `outer` itself is.
          The four corner positions -- rightTop, leftBottom and the rest --
          land here too; they are not built yet and reaching the fallback is
          the same picture upstream draws for a misspelling. }
        Result.Position := flpOuter;
    end;
    d := lbl.Find('formatter');
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
    begin
      Result.Formatter := d.AsString;
      Result.HasFormatter := True;
    end;
  end;

  d := node.Find('labelLine');
  if d is TJSONObject then
  begin
    line := TJSONObject(d);
    d := line.Find('show');
    if (d <> nil) and (d.JSONType = jtBoolean) then
      Result.LineShow := d.AsBoolean;
    d := line.Find('length');
    if (d <> nil) and (d.JSONType = jtNumber) then
      Result.LineLengthLogical := Max(Double(0), Min(Double(4096), d.AsFloat));
    d := line.Find('lineStyle');
    if d is TJSONObject then
    begin
      ls := TJSONObject(d);
      d := ls.Find('width');
      if (d <> nil) and (d.JSONType = jtNumber) then
        Result.LineWidthLogical := Max(Double(0), Min(Double(64), d.AsFloat));
    end;
  end;

  { THE AND HAPPENS HERE, at option time, not at draw time. Upstream bakes
    `labelLine.show := labelLine.show and label.show` into the resolved series
    option during init, so a series that hid its labels has already had its
    guide lines switched off everywhere that reads them. Applying it at the
    draw site instead leaves the two able to disagree. }
  Result.LineShow := Result.LineShow and Result.Show;
end;

function TyBuildFunnelLabels(const ABinding: TTySeriesBinding;
  const ALayout: TTyFunnelLayout; const ASpec: TTyFunnelLabelSpec;
  const AInk: TTyFunnelLabelInk; const AFills: array of TTyChartColor;
  AStore: TTyDataStore; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;
var
  i, raw: Integer;
  pos: TTyFunnelLabelPosition;
  p: array[0..3] of TTyPointF;
  words: string;
  fill: TTyChartColor;
  inside: Boolean;
  x1, y1, x2, y2, textX, textY, lineLen, w, h, lum: Double;
  anchorH: TTyTextAnchorH;
  el: TTyChartElement;
  box: TTyRectF;
  auto: TTyLabelSpec;
begin
  Result := 0;
  if (AList = nil) or (AStore = nil) or not ALayout.Valid then Exit;
  if not ASpec.Show then Exit;
  lineLen := ASpec.LineLengthLogical * APPI / 96;

  for i := 0 to High(ALayout.Items) do
  begin
    raw := ALayout.Items[i].RawIndex;
    words := AStore.GetName(ALayout.Items[i].Index);
    if ASpec.HasFormatter then words := ASpec.Formatter;
    if words = '' then Continue;
    p[0] := ALayout.Items[i].Points[0];
    p[1] := ALayout.Items[i].Points[1];
    p[2] := ALayout.Items[i].Points[2];
    p[3] := ALayout.Items[i].Points[3];

    fill := 0;
    if (raw >= 0) and (raw <= High(AFills)) then fill := AFills[raw];

    { THE TWO REJECTIONS, per orientation. A vertical funnel rewrites `top`
      and `bottom` to `left` -- BOTH of them, onto the same branch -- and a
      horizontal one rewrites `left` and `right` to `bottom`. Upstream warns
      only in a development build; in production the rewrite is silent. }
    pos := ASpec.Position;
    if not ALayout.Horizontal then
    begin
      if pos in [flpTop, flpBottom] then pos := flpLeft;
    end
    else
      if pos in [flpLeft, flpRight] then pos := flpBottom;

    inside := pos in [flpInside, flpInsideLeft, flpInsideRight];
    x1 := 0; y1 := 0; x2 := 0; y2 := 0;
    anchorH := tahLeft;

    case pos of
      flpInsideLeft:
        begin
          textX := (p[0].X + p[3].X) / 2 + 5 * APPI / 96;
          textY := (p[0].Y + p[3].Y) / 2;
          anchorH := tahLeft;
        end;
      flpInsideRight:
        begin
          textX := (p[1].X + p[2].X) / 2 - 5 * APPI / 96;
          textY := (p[1].Y + p[2].Y) / 2;
          anchorH := tahRight;
        end;
      flpInside:
        begin
          textX := (p[0].X + p[1].X + p[2].X + p[3].X) / 4;
          textY := (p[0].Y + p[1].Y + p[2].Y + p[3].Y) / 4;
          anchorH := tahCentre;
        end;
      flpLeft:
        begin
          x1 := (p[3].X + p[0].X) / 2;
          y1 := (p[3].Y + p[0].Y) / 2;
          x2 := x1 - lineLen;
          textX := x2 - 5 * APPI / 96;
          textY := y1;
          anchorH := tahRight;
        end;
      flpTop:
        begin
          x1 := (p[3].X + p[0].X) / 2;
          y1 := (p[3].Y + p[0].Y) / 2;
          y2 := y1 - lineLen;
          textY := y2 - 5 * APPI / 96;
          textX := x1;
          anchorH := tahCentre;
        end;
      flpBottom:
        begin
          x1 := (p[1].X + p[2].X) / 2;
          y1 := (p[1].Y + p[2].Y) / 2;
          y2 := y1 + lineLen;
          textY := y2 + 5 * APPI / 96;
          textX := x1;
          anchorH := tahCentre;
        end;
    else
      { `right`, and `outer` with it -- the fallback branch, whose own comment
        upstream reads "Right side or Bottom side". On a horizontal funnel the
        collapse below turns it into the bottom. }
      begin
        x1 := (p[1].X + p[2].X) / 2;
        y1 := (p[1].Y + p[2].Y) / 2;
        if ALayout.Horizontal then
        begin
          y2 := y1 + lineLen;
          textY := y2 + 5 * APPI / 96;
          textX := x1;
          anchorH := tahCentre;
        end
        else
        begin
          x2 := x1 + lineLen;
          textX := x2 + 5 * APPI / 96;
          textY := y1;
          anchorH := tahLeft;
        end;
      end;
    end;

    if not inside then
    begin
      { THE AXIS COLLAPSE, which overwrites whatever the branch put in the
        cross-axis coordinate. A vertical funnel's guide line is ALWAYS
        horizontal and the words sit at the anchor's own y; a horizontal
        funnel's is always vertical. Any textX a corner branch set under
        horizontal orient is discarded here, upstream included. }
      if ALayout.Horizontal then
      begin
        x2 := x1;
        textX := x2;
      end
      else
      begin
        y2 := y1;
        textY := y2;
      end;

      if ASpec.LineShow and (ASpec.LineWidthLogical > 0) then
      begin
        el := TyChartElement(TyShapePolyline([TyPointF(x1, y1),
          TyPointF(x2, y2)]));
        el.Style.StrokeColor := fill;
        el.Style.StrokeWidthLogical := ASpec.LineWidthLogical;
        { UNDER THE BANDS. Upstream's updateZ puts a label line at
          `maxZ2 - 1` while the bands sit at 0, so the line disappears where it
          crosses its own band and only its outside half is seen. }
        el.Z := 2;
        el.Z2 := -1;
        { SILENT: a guide line is a pointer at a band, not a target of its
          own, and a hit on it would report the datum twice over. }
        el.Silent := True;
        AList.Add(el);
        Inc(Result);
      end;
    end;

    AMeasurer.MeasureLine(words, AInk.FontName, AInk.FontSizeLogical,
      AInk.FontWeight, w, h);
    if (w <= 0) or (h <= 0) then Continue;
    case anchorH of
      tahCentre: box.Left := textX - w / 2;
      tahRight: box.Left := textX - w;
    else
      box.Left := textX;
    end;
    box.Right := box.Left + w;
    { ALWAYS THE MIDDLE. Upstream writes verticalAlign 'middle' for every
      position, `top` and `bottom` included -- so the words' centre sits five
      pixels past the end of the line rather than their edge. }
    box.Top := textY - h / 2;
    box.Bottom := box.Top + h;

    el := TyChartElement(TyShapeRect(box));
    el.Caption.Text := words;
    el.Caption.FontName := AInk.FontName;
    el.Caption.FontSizeLogical := AInk.FontSizeLogical;
    el.Caption.FontWeight := AInk.FontWeight;
    { INSIDE IS THREE BANDS BY LUMINANCE, not a light/dark pair -- and the
      order reads backwards until you see why: on a mid-dark band you want
      maximum contrast, but on a nearly black one the brightest ink glares.
      Outside is the theme's own ink and never looks at what it labels. }
    { THE SHARED CHOOSER, not a second table. This unit carried its own copy
      of the three bands for one batch, and it disagreed with the original in
      one place: it tested `fill = 0` where the real rule asks whether the host
      has a fill at all, so an opaque BLACK band ($FF000000, which is not zero)
      took the light ground's ink. }
    auto := TyLabelSpecNone;
    auto.AutoColour := True;
    auto.OutsideColour := AInk.OutsideColour;
    auto.InsideColour[0] := AInk.InsideColour[0];
    auto.InsideColour[1] := AInk.InsideColour[1];
    auto.InsideColour[2] := AInk.InsideColour[2];
    el.Caption.Colour := TyLabelAutoColour(auto, fill, fill <> 0, inside);
    el.Caption.X := textX;
    el.Caption.Y := textY;
    el.Caption.AnchorH := anchorH;
    el.Caption.AnchorV := tavMiddle;
    el.Caption.RotationRad := 0;
    el.Caption.Truncate := False;
    el.Z := 2;
    el.Z2 := 2;
    el.Silent := False;
    el.Datum := TyChartDatum(ABinding.SeriesIndex, ALayout.Items[i].Index,
      raw);
    AList.Add(el);
    Inc(Result);
  end;
end;

end.
