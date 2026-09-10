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

  VALUES THAT STACK ARRIVE ALREADY ACCUMULATED. AdvChart.Stack writes two
  calculated columns per participating series, and this unit is told which:
  the cumulative one is what gets plotted, and the one below it is where a
  stacked bar's floor is. Working out what a value adds up to is not a
  rendering question, which is why it is not answered here.

  WHAT IS STILL NOT HERE: symbols on a line, the filled area under one, and the
  four-corner form of borderRadius. Each is its own Tier 1 row. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Data, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Series,
  tyControls.AdvChart.BarLayout, tyControls.AdvChart.Symbol;

type
  { Where a stepped line turns. ECharts spells `step: true` as 'start'. }
  TTyLineStep = (lstNone, lstStart, lstMiddle, lstEnd);

  { showAllSymbol: 'auto' | true | false. 'auto' is the default and means
    "all of them unless they would crowd", which upstream decides from the
    symbol's size against the space one category gets. }
  TTyShowAllSymbol = (sasAuto, sasYes, sasNo);

  { How the area under a line finds its lower edge when nothing is stacked
    beneath it. ECharts' areaStyle.origin. }
  TTyAreaOrigin = (laoAuto, laoStart, laoEnd, laoValue);

  { The line-shaped options of one series, read off its option node.

    Read here rather than resolved by the control because none of them needs
    the theme or the other series -- unlike a bar's width, which cannot be
    known without its neighbours. }
  TTyLineSpec = record
    HasArea: Boolean;
    AreaOrigin: TTyAreaOrigin;
    AreaOriginValue: Double;
    { 0..1. Upstream has no default here: an areaStyle with no opacity is
      opaque, in the series' own colour. }
    AreaOpacity: Double;
    Step: TTyLineStep;
    ConnectNulls: Boolean;
    { showSymbol, default TRUE: an ECharts line has a marker on every point. }
    ShowSymbol: Boolean;
    ShowAllSymbol: TTyShowAllSymbol;
    { The thinning the AXIS settled on -- 1 when it draws every label. When the
      markers would crowd, upstream falls back to "follow the label interval
      strategy on the category axis", and this is that interval, computed once
      by the layout pass rather than guessed at again here. }
    LabelStep: Integer;
  end;

  { Everything about ONE series that was decided somewhere else.

    It began as "how it looks, resolved from the theme", and it is no longer
    only that: a bar's column comes from a solver that had to see every other
    bar on the axis, and the line spec is read straight off the option. What
    they have in common is that this unit does not work any of them out -- it
    draws what it is handed. }
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
    { The line-shaped options, ignored by every other renderer. }
    Line: TTyLineSpec;
    { The symbol a datum is drawn as. Scatter draws nothing else; a line will
      draw these on top of itself once showSymbol lands. }
    Symbol: TTySymbolSpec;
    { What an `empty` symbol is filled with -- the theme's own background,
      resolved by the control, because this unit never asks what colour
      anything is. Upstream fills them with a token too. }
    EmptyFill: TTyChartColor;
  end;

{ A visual with the defaults: a filled mark, no stroke, upstream's bar gap. }
function TySeriesVisual(AFill: TTyChartColor): TTySeriesVisual;

{ The line-shaped options of the series in slot ASlot.

  Every default is upstream's: `step: false`, `connectNulls: false`, and no
  areaStyle at all -- its mere PRESENCE turns the area on, which is why an
  empty `areaStyle: {}` is a real instruction and not a no-op. }
function TyLineSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyLineSpec;

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
  AStore: TTyDataStore; const AStack: TTySeriesStack;
  const AVisual: TTySeriesVisual; AList: TTyPaintList): Integer;

implementation

function TyLineSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyLineSpec;
var
  node, area: TJSONObject;
  d: TJSONData;
  sv: string;
begin
  Result.HasArea := False;
  Result.AreaOrigin := laoAuto;
  Result.AreaOriginValue := 0;
  Result.AreaOpacity := 1;
  Result.Step := lstNone;
  Result.ConnectNulls := False;
  Result.ShowSymbol := True;
  Result.ShowAllSymbol := sasAuto;
  Result.LabelStep := 1;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);

  { `step` is false | true | 'start' | 'middle' | 'end', and true means
    'start' -- upstream's own comment says so beside the default. }
  d := node.Find('step');
  if d <> nil then
  begin
    if (d.JSONType = jtBoolean) and d.AsBoolean then Result.Step := lstStart
    else if d.JSONType = jtString then
    begin
      sv := d.AsString;
      if sv = 'start' then Result.Step := lstStart
      else if sv = 'middle' then Result.Step := lstMiddle
      else if sv = 'end' then Result.Step := lstEnd;
    end;
  end;

  d := node.Find('connectNulls');
  if (d <> nil) and (d.JSONType = jtBoolean) then
    Result.ConnectNulls := d.AsBoolean;

  d := node.Find('showSymbol');
  if (d <> nil) and (d.JSONType = jtBoolean) then
    Result.ShowSymbol := d.AsBoolean;

  d := node.Find('showAllSymbol');
  if d <> nil then
  begin
    if d.JSONType = jtBoolean then
    begin
      if d.AsBoolean then Result.ShowAllSymbol := sasYes
      else Result.ShowAllSymbol := sasNo;
    end
    else if (d.JSONType = jtString) and (d.AsString = 'auto') then
      Result.ShowAllSymbol := sasAuto;
  end;

  { PRESENCE IS THE SWITCH. `areaStyle: {}` fills the area; there is no
    `show` and no default block to inherit. }
  d := node.Find('areaStyle');
  if (d = nil) or not (d is TJSONObject) then Exit;
  Result.HasArea := True;
  area := TJSONObject(d);

  d := area.Find('opacity');
  if (d <> nil) and (d.JSONType = jtNumber) then
    { Double(0)/Double(1), NOT 0/1: an integer beside a Double picks Math's
      SINGLE overload and quietly rounds the result to a 24-bit mantissa. It
      would not matter for an alpha; the shape is what matters, because the
      next thing clamped this way might be a coordinate. }
    Result.AreaOpacity := Min(Double(1), Max(Double(0), d.AsFloat));

  d := area.Find('origin');
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    Result.AreaOrigin := laoValue;
    Result.AreaOriginValue := d.AsFloat;
  end
  else if d.JSONType = jtString then
  begin
    sv := d.AsString;
    if sv = 'start' then Result.AreaOrigin := laoStart
    else if sv = 'end' then Result.AreaOrigin := laoEnd;
  end;
end;

function TySeriesVisual(AFill: TTyChartColor): TTySeriesVisual;
begin
  Result.Fill := AFill;
  Result.Stroke := 0;
  Result.StrokeWidthLogical := 0;
  Result.Bar := Default(TTyBarColumn);
  Result.Z := 0;
  Result.Z2 := 0;
  Result.Line.HasArea := False;
  Result.Line.AreaOrigin := laoAuto;
  Result.Line.AreaOriginValue := 0;
  Result.Line.AreaOpacity := 1;
  Result.Line.Step := lstNone;
  Result.Line.ConnectNulls := False;
  { TRUE, because that is upstream's default and this record is "the
    defaults".

    It was tempting to make a hand-built visual quiet so the existing polyline
    tests would not have to change -- but two different defaults for one field
    is precisely the invisible-wrong-default this port keeps being bitten by,
    and the surprise here is visible (extra elements) rather than silent
    (missing ones). The geometry tests turn it off and say why. }
  Result.Line.ShowSymbol := True;
  Result.Line.ShowAllSymbol := sasAuto;
  Result.Line.LabelStep := 1;
  Result.Symbol := TySymbolDefault('');
  Result.EmptyFill := 0;
end;

{ The value the area falls back to where nothing is stacked underneath.

  ECharts' getValueStart. 'auto' is NOT simply zero: an axis whose whole range
  is above zero starts the area at the bottom of the range, and one entirely
  below zero starts it at the top -- otherwise the fill would reach off the
  plot towards a zero that is not on the axis. }
function AreaStartValue(AValueAxis: TTyAxis;
  const ASpec: TTyLineSpec): Double;
var e: TTyRange;
begin
  if AValueAxis = nil then Exit(0);
  e := AValueAxis.Scale.GetExtent;
  case ASpec.AreaOrigin of
    laoStart: Result := e.Start;
    laoEnd:   Result := e.Stop;
    laoValue: Result := ASpec.AreaOriginValue;
  else
    if e.Start > 0 then Result := e.Start
    else if e.Stop < 0 then Result := e.Stop
    else Result := 0;
  end;
end;

{ Upstream's turnPointsIntoStep, transcribed.

  For every consecutive pair it emits the current point and then ONE corner
  ('start' and 'end') or TWO ('middle'), and finally the last point. Which
  coordinate the corner keeps is decided by the BASE axis, not by x: turned
  sideways, a step turns vertically. }
function StepPoints(const APts: array of TTyPointF; ABaseHoriz: Boolean;
  AStep: TTyLineStep): TTyPointFArray;
var
  i, n: Integer;
  pt, nextPt, a, b: TTyPointF;
  mid: Double;

  procedure Push(const AP: TTyPointF);
  begin
    if n > High(Result) then SetLength(Result, Max(8, n * 2));
    Result[n] := AP;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  if (AStep = lstNone) or (Length(APts) < 2) then
  begin
    SetLength(Result, Length(APts));
    for i := 0 to High(APts) do Result[i] := APts[i];
    Exit;
  end;
  SetLength(Result, Length(APts) * 3);
  for i := 0 to Length(APts) - 2 do
  begin
    pt := APts[i];
    nextPt := APts[i + 1];
    Push(pt);
    case AStep of
      lstEnd:
        begin
          { Along the base to the next station, still at this value. }
          if ABaseHoriz then a := TyPointF(nextPt.X, pt.Y)
                        else a := TyPointF(pt.X, nextPt.Y);
          Push(a);
        end;
      lstMiddle:
        begin
          if ABaseHoriz then
          begin
            mid := (pt.X + nextPt.X) / 2;
            a := TyPointF(mid, pt.Y);
            b := TyPointF(mid, nextPt.Y);
          end
          else
          begin
            mid := (pt.Y + nextPt.Y) / 2;
            a := TyPointF(pt.X, mid);
            b := TyPointF(nextPt.X, mid);
          end;
          Push(a);
          Push(b);
        end;
    else
      { lstStart: change value first, then move along the base. }
      if ABaseHoriz then a := TyPointF(pt.X, nextPt.Y)
                    else a := TyPointF(nextPt.X, pt.Y);
      Push(a);
    end;
  end;
  Push(APts[High(APts)]);
  SetLength(Result, n);
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
    AStore: TTyDataStore; const AStack: TTySeriesStack;
    const AVisual: TTySeriesVisual; AList: TTyPaintList;
    AColX, AColY: Integer): Integer;

function BuildBars(const ABinding: TTySeriesBinding; AStore: TTyDataStore;
  const AStack: TTySeriesStack; const AVisual: TTySeriesVisual;
  AList: TTyPaintList; AColX, AColY: Integer): Integer;
var
  i, valCol: Integer;
  x, y, baseline, anchor, own, floorV: Double;
  lay: TTyCoordLayout;
  r: TTyRectF;
  p, hiPt, loPt: TTyPointF;
  col: TTyBarColumn;
  baseHoriz, haveCol, stacked: Boolean;
  shape: TTyChartShape;
begin
  Result := 0;
  baseHoriz := (ABinding.BaseAxis = nil) or ABinding.BaseAxis.Horizontal;
  { THE VALUE IS ON WHICHEVER AXIS IS NOT THE BASE. On a horizontal bar chart
    that is X, so substituting the cumulative into y would stack the wrong axis
    and leave horizontal stacked bars looking unstacked. }
  stacked := AStack.Stacked and (AStack.ResultCol >= 0);
  if baseHoriz then valCol := AColY else valCol := AColX;
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
    own := AStore.Get(valCol, i);
    { A stacked series plots its cumulative total. That is the whole of
      stacking as far as drawing is concerned. }
    if stacked then
    begin
      if baseHoriz then y := AStore.Get(AStack.ResultCol, i)
                   else x := AStore.Get(AStack.ResultCol, i);
    end;
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
    { A STACKED BAR STANDS ON THE ONE BELOW IT, not on the axis baseline.

      Its floor is recomputed as (cumulative - own) rather than read out of the
      stacked-over column, which is what upstream does and for a stated reason:
      barMinHeight can move the drawn END, so the value a bar was stacked over
      is not necessarily where its own segment begins.

      THE BOTTOM MEMBER IS EXCLUDED. It accumulates onto nothing, so its floor
      is the axis' own baseline and DataToLayout has already put it there;
      forcing it to (cumulative - own) = 0 would move it on any axis that does
      not start at zero. }
    if stacked and AStack.HasBelow and not IsNan(own) then
    begin
      if baseHoriz then floorV := y - own else floorV := x - own;
      if baseHoriz then
      begin
        hiPt := ABinding.Cart.DataToPoint([x, y]);
        loPt := ABinding.Cart.DataToPoint([x, floorV]);
        lay.Rect.Top := Min(hiPt.Y, loPt.Y);
        lay.Rect.Bottom := Max(hiPt.Y, loPt.Y);
      end
      else
      begin
        hiPt := ABinding.Cart.DataToPoint([x, y]);
        loPt := ABinding.Cart.DataToPoint([floorV, y]);
        lay.Rect.Left := Min(hiPt.X, loPt.X);
        lay.Rect.Right := Max(hiPt.X, loPt.X);
      end;
      if not TyRectFIsValid(lay.Rect) then Continue;
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
  const AStack: TTySeriesStack; const AVisual: TTySeriesVisual;
  AList: TTyPaintList; AColX, AColY: Integer): Integer;
var
  i, n, step: Integer;
  x, y, lowV, startV: Double;
  p, q: TTyPointF;
  pts, lows: TTyPointFArray;
  rows: array of Integer;
  baseHoriz, stacked, gap: Boolean;
  spec: TTyLineSpec;

  { One marker, answering for its own row. False when the symbol draws
    nothing. }
  function EmitSymbol(const AP: TTyPointF; ARow: Integer): Boolean;
  var
    sh: TTyChartShape;
    sv: TTySeriesVisual;
  begin
    Result := False;
    sh := TyBuildSymbol(AVisual.Symbol, AP.X, AP.Y);
    if (sh.Kind = cskRect) and not TyRectFIsValid(sh.Bounds) then Exit;
    sv := AVisual;
    { An `empty` marker is a RING: the series colour becomes the pen and the
      hole is the theme's own ground. A line's default symbol is emptyCircle,
      so this is the ordinary case rather than the exception. }
    if AVisual.Symbol.Empty or (AVisual.Symbol.Kind = tsyLine) then
    begin
      sv.Stroke := AVisual.Fill;
      if sv.StrokeWidthLogical <= 0 then sv.StrokeWidthLogical := 2;
      if AVisual.Symbol.Kind = tsyLine then sv.Fill := 0
      else sv.Fill := AVisual.EmptyFill;
    end;
    AList.Add(MarkElement(sh, sv, ABinding.SeriesIndex, ARow));
    Result := True;
  end;

  { showAllSymbol. Upstream: 'auto' shows every marker unless one would crowd
    its neighbour -- it compares the symbol's size against the space a single
    category gets, with an empirical 1.5 margin -- and when they would crowd it
    "follows the label interval strategy on the category axis", which is the
    step the axis layout already worked out. }
  function SymbolStep: Integer;
  var
    avail, sz: Double;
    cats: Integer;
  begin
    Result := 1;
    if AVisual.Line.ShowAllSymbol = sasYes then Exit;
    if ABinding.BaseAxis = nil then Exit;
    if not (ABinding.BaseAxis.Scale is TTyOrdinalScale) then Exit;
    cats := TTyOrdinalScale(ABinding.BaseAxis.Scale).Count;
    if cats <= 0 then Exit;
    avail := Abs(ABinding.BaseAxis.PxStop - ABinding.BaseAxis.PxStart) / cats;
    { The ACROSS size, which is upstream's own index choice: it reads
      symbolSize[1] for a horizontal category axis. Only visible with an
      oblong symbolSize, and transcribed rather than corrected. }
    if baseHoriz then sz := AVisual.Symbol.HeightPx
                 else sz := AVisual.Symbol.WidthPx;
    if sz * 1.5 <= avail then Exit;
    Result := Max(1, AVisual.Line.LabelStep);
  end;

  { Upstream's isPointIllegal: NOT only NaN. Any non-finite coordinate is a
    hole, and an Infinity that reached the paint list would stretch a polyline
    across the whole surface.

    THE IsInfinite HALF IS UNREACHABLE TODAY, and its mutant survives -- worth
    recording rather than hiding behind a contrived test. Upstream needs it
    because ITS log scale answers -Infinity for a non-positive value; ours
    answers NaN (TTyLogScaleMapper.TransformIn exits NaN for AValue <= 0), so
    the NaN half already catches the one case that reaches here. The check
    stays because "a hole is any coordinate that is not finite" is the rule,
    and the next mapper to divide by a zero span will produce one. }
  function Illegal(const AP: TTyPointF): Boolean;
  begin
    Result := IsNan(AP.X) or IsNan(AP.Y)
           or IsInfinite(AP.X) or IsInfinite(AP.Y);
  end;

  { One run, from the points gathered so far. The AREA goes in FIRST so the
    line is drawn over its own fill rather than under it -- the paint list
    breaks ties by insertion order, so first in is furthest back. }
  procedure Flush;
  var
    k, m: Integer;
    up, dn: TTyPointFArray;
    poly: TTyPointFArray;
    v: TTySeriesVisual;
    el: TTyChartElement;
  begin
    if n < 2 then Exit;
    SetLength(up, n);
    for k := 0 to n - 1 do up[k] := pts[k];
    up := StepPoints(up, baseHoriz, spec.Step);

    if spec.HasArea then
    begin
      SetLength(dn, n);
      for k := 0 to n - 1 do dn[k] := lows[k];
      { The lower edge is stepped the same way, or the belt would not follow
        the line it belongs to. }
      dn := StepPoints(dn, baseHoriz, spec.Step);
      SetLength(poly, Length(up) + Length(dn));
      for k := 0 to High(up) do poly[k] := up[k];
      { Backwards, so the ring closes along the bottom instead of crossing. }
      m := Length(up);
      for k := High(dn) downto 0 do
      begin
        poly[m] := dn[k];
        Inc(m);
      end;
      v := AVisual;
      v.Stroke := 0;
      v.StrokeWidthLogical := 0;
      el := MarkElement(TyShapePolygon(poly), v, ABinding.SeriesIndex, -1);
      el.Style.Alpha := spec.AreaOpacity;
      { SILENT: the fill is decoration behind the line, and a pointer landing
        on it should find the line, not the shading. }
      el.Silent := True;
      AList.Add(el);
      Inc(Result);
    end;

    { A LINE IS A STROKE, not a fill. The series colour arrives in Fill because
      that is what a mark's colour is called; for this shape it is the pen. }
    v := AVisual;
    v.Fill := 0;
    if v.StrokeWidthLogical <= 0 then v.StrokeWidthLogical := 2;
    if v.Stroke = 0 then v.Stroke := AVisual.Fill;
    el := MarkElement(TyShapePolyline(up), v, ABinding.SeriesIndex, -1);
    AList.Add(el);
    Inc(Result);

    { THE MARKERS GO ON LAST, so they sit over the line they belong to -- and
      they carry the DATUM, which the polyline cannot: one polyline is a whole
      run, so a pointer over a marker can name its row and a pointer over the
      line between two markers cannot. }
    if spec.ShowSymbol then
      for k := 0 to n - 1 do
        if ((k mod step) = 0) and EmitSymbol(pts[k], rows[k]) then
          Inc(Result);
  end;

begin
  Result := 0;
  baseHoriz := (ABinding.BaseAxis = nil) or ABinding.BaseAxis.Horizontal;
  stacked := AStack.Stacked and (AStack.ResultCol >= 0);
  spec := AVisual.Line;
  startV := AreaStartValue(ABinding.ValueAxis, spec);
  step := SymbolStep;
  SetLength(pts, AStore.Count);
  SetLength(lows, AStore.Count);
  SetLength(rows, AStore.Count);
  n := 0;
  for i := 0 to AStore.Count - 1 do
  begin
    x := AStore.Get(AColX, i);
    y := AStore.Get(AColY, i);
    if stacked then
    begin
      if baseHoriz then y := AStore.Get(AStack.ResultCol, i)
                   else x := AStore.Get(AStack.ResultCol, i);
    end;
    { ONE GAP RULE, NOT THREE. A datum that is NaN, a point that will not map,
      and an area baseline that will not map are the same thing to the reader
      of the chart: a hole. The first version broke the run for the first and
      silently DROPPED the other two -- which closes the line straight over the
      hole, the very join that connectNulls being false exists to prevent. }
    gap := IsNan(x) or IsNan(y);
    p := TyPointF(NaN, NaN);
    q := TyPointF(NaN, NaN);
    if not gap then
    begin
      p := ABinding.Cart.DataToPoint([x, y]);
      gap := Illegal(p);
    end;

    if (not gap) and spec.HasArea then
    begin
      { WHERE THE BELT'S LOWER EDGE IS: the value stacked underneath, and where
        there is none, the origin. Upstream's getStackedOnPoint reads exactly
        this way round, and the NaN test is what makes an unstacked area fall
        to the axis rather than to nothing. }
      lowV := NaN;
      if AStack.Stacked and (AStack.OverCol >= 0) then
        lowV := AStore.Get(AStack.OverCol, i);
      if IsNan(lowV) then lowV := startV;
      if baseHoriz then q := ABinding.Cart.DataToPoint([x, lowV])
                   else q := ABinding.Cart.DataToPoint([lowV, y]);
      gap := Illegal(q);
    end;

    { A GAP BREAKS THE LINE unless connectNulls says otherwise. ECharts
      defaults it to false, because joining by default draws a segment through
      data that does not exist; with it on, the missing points are dropped and
      the run simply continues. }
    if gap then
    begin
      if spec.ConnectNulls then Continue;
      Flush;
      n := 0;
      Continue;
    end;

    if spec.HasArea then lows[n] := q;
    pts[n] := p;
    rows[n] := i;
    Inc(n);
  end;
  Flush;
end;

{ One symbol per datum, and nothing else -- which is the whole of a scatter.

  THE SIZE CAN COME FROM THE DATA. ECharts lets symbolSize be a callback over
  the datum, and a callback cannot survive the trip to JSON; what CAN is a
  third number on the point, which is how a bubble chart is written when the
  option is static. So a row with more columns than the two axes need has its
  next value read as the diameter. }
function BuildScatter(const ABinding: TTySeriesBinding; AStore: TTyDataStore;
  const AStack: TTySeriesStack; const AVisual: TTySeriesVisual;
  AList: TTyPaintList; AColX, AColY: Integer): Integer;
var
  i, sizeCol, valCol: Integer;
  x, y, sz: Double;
  p: TTyPointF;
  spec: TTySymbolSpec;
  shape: TTyChartShape;
  v: TTySeriesVisual;
  el: TTyChartElement;
  baseHoriz, stacked: Boolean;
begin
  Result := 0;
  spec := AVisual.Symbol;
  if spec.Kind = tsyNone then Exit;
  baseHoriz := (ABinding.BaseAxis = nil) or ABinding.BaseAxis.Horizontal;
  stacked := AStack.Stacked and (AStack.ResultCol >= 0);

  { A third column is a size only when it is not one of the two the axes use.
    Asking the store rather than assuming index 2 keeps this right for a series
    bound to the second y axis. }
  sizeCol := -1;
  for i := 0 to AStore.DimCount - 1 do
    if (i <> AColX) and (i <> AColY) and (AStore.DimType(i) = ddtFloat) then
    begin
      sizeCol := i;
      Break;
    end;

  for i := 0 to AStore.Count - 1 do
  begin
    x := AStore.Get(AColX, i);
    y := AStore.Get(AColY, i);
    if stacked then
    begin
      if baseHoriz then y := AStore.Get(AStack.ResultCol, i)
                   else x := AStore.Get(AStack.ResultCol, i);
    end;
    if IsNan(x) or IsNan(y) then Continue;
    p := ABinding.Cart.DataToPoint([x, y]);
    if IsNan(p.X) or IsNan(p.Y)
      or IsInfinite(p.X) or IsInfinite(p.Y) then Continue;

    if sizeCol >= 0 then
    begin
      sz := AStore.Get(sizeCol, i);
      if not IsNan(sz) and (sz > 0) then
      begin
        spec.WidthPx := sz;
        spec.HeightPx := sz;
      end;
    end;

    shape := TyBuildSymbol(spec, p.X, p.Y);
    if (shape.Kind = cskRect) and not TyRectFIsValid(shape.Bounds) then Continue;

    v := AVisual;
    { AN `empty` SYMBOL IS STROKED, NOT FILLED -- upstream strokes it in the
      series colour and fills it with the theme's background, and a line symbol
      is stroked too. Both are the same rule: the colour is the pen. }
    if spec.Empty or (spec.Kind = tsyLine) then
    begin
      v.Stroke := AVisual.Fill;
      if v.StrokeWidthLogical <= 0 then v.StrokeWidthLogical := 2;
      if spec.Kind = tsyLine then v.Fill := 0
      else v.Fill := AVisual.EmptyFill;
    end;
    el := MarkElement(shape, v, ABinding.SeriesIndex, i);
    AList.Add(el);
    Inc(Result);
  end;
  { The unused local keeps the compiler quiet about valCol in a future edit. }
  valCol := 0;
  if valCol > 0 then ;
end;

const
  { THE ONE LIST. Three of the twenty-three types draw; a renderer arrives as
    a row here and both the drawing and the published answer follow from it.

    Type names are compared EXACTLY, the way TySeriesFindType compares them --
    ECharts' names are case-sensitive, so a series typed 'Bar' never resolves
    and never reaches this unit. A lenient match here would answer yes for a
    chart that draws nothing. }
  cRenderers: array[0..2] of record
    Name: string;
    Build: TTyMarkBuilder;
  end = (
    (Name: 'bar';     Build: @BuildBars),
    (Name: 'line';    Build: @BuildLine),
    (Name: 'scatter'; Build: @BuildScatter));

  { AND THE ONES DRAWN SOMEWHERE ELSE. A pie is not on a coordinate system,
    so its geometry is solved in AdvChart.Pie and never reaches this unit --
    but the question the editor asks is `will this series appear`, and an
    answer that covered only one of the two passes would tell the author a
    pie chart paints nothing while the pie sits there on the canvas.

    A SECOND LIST IS A SECOND THING THAT CAN DRIFT, and the loop in
    TestThePublishedAnswerMatchesTheDrawing cannot check this half -- it
    drives TyBuildSeriesMarks, which a pie deliberately never enters. What
    guards it is TestAPieIsDrawnOffItsOwnCentreWithAColourPerSector, which
    counts the control's own pixels. }
  cElsewhere: array[0..0] of string = ('pie');

function RendererFor(const AType: string): TTyMarkBuilder;
var i: Integer;
begin
  for i := 0 to High(cRenderers) do
    if cRenderers[i].Name = AType then Exit(cRenderers[i].Build);
  Result := nil;
end;

function TySeriesTypeHasRenderer(const AType: string): Boolean;
var i: Integer;
begin
  if RendererFor(AType) <> nil then Exit(True);
  for i := 0 to High(cElsewhere) do
    if cElsewhere[i] = AType then Exit(True);
  Result := False;
end;

function TyBuildSeriesMarks(const ABinding: TTySeriesBinding;
  AStore: TTyDataStore; const AStack: TTySeriesStack;
  const AVisual: TTySeriesVisual; AList: TTyPaintList): Integer;
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
    Result := build(ABinding, AStore, AStack, AVisual, AList, colX, colY);
end;

end.
