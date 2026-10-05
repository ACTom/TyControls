unit tyControls.AdvChart.WhiskerBox;
{$mode objfpc}{$H+}
{ The candlestick's and the boxplot's shared geometry -- upstream's
  whiskerBoxCommon, candlestickLayout and boxplotLayout. [Batch 108, C1]

  WHICH AXIS IS THE BASE is the binding's (TySeriesWhiskerBaseIsX): a
  category x forces 'horizontal' (the boxes side by side along x) whatever
  `layout` says, a category y 'vertical'; with neither, `layout` decides,
  and failing that a time y makes it vertical and anything else
  horizontal. Not the cartesian's own base-axis rule: that one prefers a
  TIME x, and so disagrees on two time axes and on a layout the series
  wrote.

  HOW WIDE. A candle is `barWidth` when written, else half a band held
  between `barMinWidth` (1) and `barMaxWidth` (the band) -- the floor
  outermost, so a candle never vanishes even where candles overlap. A box
  shares the band with every boxplot series on its axis: four fifths of the
  band less two pixels, divided among them with three tenths of a share
  between neighbours, each width then held inside its own `boxWidth` bounds
  ([7, 50] px, or percentages of the band). The band is the category's,
  or -- on a value or time axis -- the smallest gap between the series'
  base values in pixels, four fifths of the axis for a single value, and
  never under a pixel.

  WHERE IT LANDS. Every point is the cartesian's dataToPoint of (base,
  value), the whole point not-a-number when either is. A candle's body
  sides are snapped outward-and-inward to the half pixel and its spine to
  the half pixel (subPixelOptimize, a pen of 1); a box is not snapped.

  THE CLIP. A shape with no point inside the plot (edges included) is not
  drawn; one with some points out is drawn through the plot's rectangle --
  createGridClipPath with no pen, its width rounded up and a fractional left
  edge floored with a pixel given back. `clip: false` draws everything
  whole.

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Data, tyControls.AdvChart.Series,
  tyControls.AdvChart.Paint;

type
  { What one candlestick or boxplot series was solved to. Index-parallel to
    the bindings; Solved False for every other series and for one the solve
    could not reach (hidden, unbound). }
  TTyWhiskerLayout = record
    Solved: Boolean;
    { a candlestick's body width, device px }
    CandleWidth: Double;
    { a boxplot's box width and its centre's offset from the base point,
      device px }
    BoxWidth: Double;
    BoxOffset: Double;
    { `clip`, JavaScript-truthy; true unless written }
    Clip: Boolean;
    { A BOXPLOT'S STYLE, settled by the control: the fill (itemStyle.color,
      else the theme's surface -- upstream's tokens.color.neutral00), the
      pen (itemStyle.borderColor, else the series colour) and its width
      (itemStyle.borderWidth, else 1, logical px) }
    BoxFill: TTyChartColor;
    BoxStroke: TTyChartColor;
    BoxLineWidthLogical: Double;
  end;
  TTyWhiskerLayoutArray = array of TTyWhiskerLayout;

  { resolveNormalBoxClipping's three answers }
  TTyWhiskerClip = (wcNone, wcPartial, wcFull);

  { The candlestick's layout of one row, as candlestickLayout makes it:
    Ends[0..3] the body (high end left, right; low end right, left -- on a
    horizontal layout), Ends[4..7] the two wicks (highest to the body's top,
    lowest to the body's bottom), and the open price's value coordinate the
    enter animation grows from. }
  TTyCandleEnds = record
    Ends: array[0..7] of TTyPointF;
    InitBaseline: Double;
  end;

  { The boxplot's: Ends[0..3] the box (Q1's end, Q3's end), Ends[4..7] the
    two whiskers (min to Q1, max to Q3), Ends[8..13] the three caps (min,
    max, median); InitBaseline the median's value coordinate. }
  TTyBoxEnds = record
    Ends: array[0..13] of TTyPointF;
    InitBaseline: Double;
  end;

{ parsePercent (util/number.ts parsePositionOption): a string ending in '%'
  is that share of ABase, another string its parseFloat, the position words
  their percentages, a number itself, null or absent not-a-number, a boolean
  0 or 1. }
function TyWhiskerParsePercent(AData: TJSONData; ABase: Double): Double;

{ calculateCandleWidth over a band already measured. }
function TyCandleWidthOf(ABand: Double; ABarWidth, ABarMaxWidth,
  ABarMinWidth: TJSONData): Double;

{ calculateBase for ACount series sharing ABand: each one's width held in
  [ALo[k], AHi[k]] and its offset from the base point. }
procedure TyBoxplotBase(ABand: Double; const ALo, AHi: array of Double;
  out AWidths, AOffsets: TTyDoubleArray);

{ One box's bounds from its `boxWidth` option (nil: the default [7, 50]):
  parsePercent against the band, a nought or not-a-number taken as 0. }
procedure TyBoxWidthBounds(ABoxWidth: TJSONData; ABand: Double;
  out ALo, AHi: Double);

{ The band a whisker series is laid out in on AAxis: calcBandWidth with the
  statistics of ASeries (the series of one type on that axis), at least a
  pixel. }
function TyWhiskerBand(AAxis: TTyAxis; const AStores: array of TTyDataStore;
  const ASeries: TTyIntegerArray): Double;

{ One candle's points. ABaseIsX: the layout is horizontal. }
function TyCandleEndsOf(ACart: TTyCartesian2D; ABaseIsX: Boolean;
  AAxisVal, AOpen, AClose, ALowest, AHighest, AWidth: Double): TTyCandleEnds;

{ One box's points: AValues the five, min to max. }
function TyBoxEndsOf(ACart: TTyCartesian2D; ABaseIsX: Boolean;
  AAxisVal: Double; const AValues: array of Double;
  AOffset, AWidth: Double): TTyBoxEnds;

{ resolveNormalBoxClipping: how many of the points the plot contains. }
function TyWhiskerClipOf(const AArea: TTyXYWH;
  const APoints: array of TTyPointF): TTyWhiskerClip;

{ createGridClipPath's rect for a series with no line width. }
function TyWhiskerClipRect(const AArea: TTyXYWH): TTyRectF;

{ Every candlestick's and boxplot's width, offset and clip, after the axes
  have their final pixel extents. }
function TySolveWhiskerLayouts(AOption: TTyChartOption;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  AIndex: TTyAxisSeriesIndex): TTyWhiskerLayoutArray;

implementation

uses tyControls.AdvChart.BarLayout, tyControls.AdvChart.AnimAxis;

const
  { boxplotLayout.calculateBase }
  cBoxShare: Double = 0.8;
  cBoxGap: Double = 0.3;
  { BoxplotSeries.defaultOption.boxWidth }
  cBoxMin: Double = 7;
  cBoxMax: Double = 50;
  { calcBandWidth's `min: 1` }
  cMinBand: Double = 1;

{ Math.max / Math.min, as JavaScript has them: a not-a-number wins }
function JsMax2(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B > A then Result := B else Result := A;
end;

function JsMin2(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B < A then Result := B else Result := A;
end;

function Absent(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function TyWhiskerParsePercent(AData: TJSONData; ABase: Double): Double;
var s, t: string;
    v: Double;
begin
  Result := NaN;
  if Absent(AData) then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtString:
      begin
        s := AData.AsString;
        if (s = 'center') or (s = 'middle') then s := '50%'
        else if (s = 'left') or (s = 'top') then s := '0%'
        else if (s = 'right') or (s = 'bottom') then s := '100%';
        t := Trim(s);
        v := TyJsParseFloat(s);
        if (t <> '') and (t[Length(t)] = '%') then
          Result := v / 100 * ABase
        else
          Result := v;
      end;
  end;
end;

function TyCandleWidthOf(ABand: Double; ABarWidth, ABarMaxWidth,
  ABarMinWidth: TJSONData): Double;
const
  cHalf: Double = 2;
var maxW, minW: Double;
begin
  { retrieve2(get('barMaxWidth'), band), retrieve2(get('barMinWidth'), 1) }
  if Absent(ABarMaxWidth) then maxW := ABand
  else maxW := TyWhiskerParsePercent(ABarMaxWidth, ABand);
  if Absent(ABarMinWidth) then minW := 1
  else minW := TyWhiskerParsePercent(ABarMinWidth, ABand);
  if not Absent(ABarWidth) then
    Exit(TyWhiskerParsePercent(ABarWidth, ABand));
  { the floor outermost: a candle stays visible where candles overlap }
  Result := JsMax2(JsMin2(ABand / cHalf, maxW), minW);
end;

procedure TyBoxWidthBounds(ABoxWidth: TJSONData; ABand: Double;
  out ALo, AHi: Double);

  function Bound(AData: TJSONData): Double;
  begin
    { `parsePercent(v, band) || 0` }
    Result := TyWhiskerParsePercent(AData, ABand);
    if IsNan(Result) then Result := 0;
  end;

begin
  if ABoxWidth = nil then
  begin
    ALo := cBoxMin;
    AHi := cBoxMax;
    Exit;
  end;
  if ABoxWidth is TJSONArray then
  begin
    { an index past the end reads undefined: 0 }
    if TJSONArray(ABoxWidth).Count > 0 then ALo := Bound(TJSONArray(ABoxWidth).Items[0])
    else ALo := 0;
    if TJSONArray(ABoxWidth).Count > 1 then AHi := Bound(TJSONArray(ABoxWidth).Items[1])
    else AHi := 0;
  end
  else
  begin
    { `[boxWidthBound, boxWidthBound]` }
    ALo := Bound(ABoxWidth);
    AHi := ALo;
  end;
end;

procedure TyBoxplotBase(ABand: Double; const ALo, AHi: array of Double;
  out AWidths, AOffsets: TTyDoubleArray);
const
  cTwo: Double = 2;
var
  n, k: Integer;
  avail, gap, w, base: Double;
begin
  n := Length(ALo);
  SetLength(AWidths, n);
  SetLength(AOffsets, n);
  if n = 0 then Exit;
  avail := ABand * cBoxShare - cTwo;
  gap := avail / n * cBoxGap;
  w := (avail - gap * (n - 1)) / n;
  base := w / cTwo - avail / cTwo;
  for k := 0 to n - 1 do
  begin
    AOffsets[k] := base;
    { `base += boxGap + boxWidth`: the two summed first }
    base := base + (gap + w);
    AWidths[k] := JsMin2(JsMax2(w, ALo[k]), AHi[k]);
  end;
end;

function TyWhiskerBand(AAxis: TTyAxis; const AStores: array of TTyDataStore;
  const ASeries: TTyIntegerArray): Double;
var
  ext: TTyRange;
  span, w: Double;
begin
  Result := cMinBand;
  if (AAxis = nil) or (AAxis.Scale = nil) then Exit;
  if AAxis.Scale is TTyOrdinalScale then
  begin
    w := AAxis.BandWidth;
    { a blank category axis has no span: upstream's NaN, the minimum }
    if TTyOrdinalScale(AAxis.Scale).Blank then w := NaN;
  end
  else
  begin
    ext := AAxis.Scale.LinearExtent2(sekMapping);
    span := ext.Stop - ext.Start;
    w := TyBandFromMinGap(AAxis.PxLength, span,
      TyLiPosMinGap(AStores, ASeries, AAxis));
  end;
  { `isNullableNumberFinite(w) ? mathMax(min, w) : min` }
  if IsNan(w) or IsInfinite(w) then Result := cMinBand
  else Result := JsMax2(cMinBand, w);
end;

{ one point, or both coordinates not-a-number when either value is }
function PointOf(ACart: TTyCartesian2D; ABaseIsX: Boolean;
  AAxisVal, AVal: Double): TTyPointF;
begin
  if IsNan(AAxisVal) or IsNan(AVal) then Exit(TyPointF(NaN, NaN));
  if ABaseIsX then Result := ACart.DataToPoint([AAxisVal, AVal])
  else Result := ACart.DataToPoint([AVal, AAxisVal]);
end;

function TyCandleEndsOf(ACart: TTyCartesian2D; ABaseIsX: Boolean;
  AAxisVal, AOpen, AClose, ALowest, AHighest, AWidth: Double): TTyCandleEnds;
const
  cHalf: Double = 2;
var
  ocLow, ocHigh, lowest, highest: TTyPointF;

  { addBodyEnd: the point moved half a candle each way along the base, each
    side snapped to the half pixel -- the far side back, the near side on }
  procedure Body(const P: TTyPointF; AStart: Boolean; AAt: Integer);
  var p1, p2: TTyPointF;
  begin
    p1 := P;
    p2 := P;
    if ABaseIsX then
    begin
      p1.X := TySubPixelOptimize(p1.X + AWidth / cHalf, 1, False);
      p2.X := TySubPixelOptimize(p2.X - AWidth / cHalf, 1, True);
    end
    else
    begin
      p1.Y := TySubPixelOptimize(p1.Y + AWidth / cHalf, 1, False);
      p2.Y := TySubPixelOptimize(p2.Y - AWidth / cHalf, 1, True);
    end;
    if AStart then
    begin
      Result.Ends[AAt] := p1;
      Result.Ends[AAt + 1] := p2;
    end
    else
    begin
      Result.Ends[AAt] := p2;
      Result.Ends[AAt + 1] := p1;
    end;
  end;

  { subPixelOptimizePoint: the base coordinate on the half pixel, the
    flag left undefined (the near side) }
  function Spine(const P: TTyPointF): TTyPointF;
  begin
    Result := P;
    if ABaseIsX then Result.X := TySubPixelOptimize(Result.X, 1, False)
    else Result.Y := TySubPixelOptimize(Result.Y, 1, False);
  end;

begin
  Result := Default(TTyCandleEnds);
  ocLow := PointOf(ACart, ABaseIsX, AAxisVal, JsMin2(AOpen, AClose));
  ocHigh := PointOf(ACart, ABaseIsX, AAxisVal, JsMax2(AOpen, AClose));
  lowest := PointOf(ACart, ABaseIsX, AAxisVal, ALowest);
  highest := PointOf(ACart, ABaseIsX, AAxisVal, AHighest);
  Body(ocHigh, False, 0);
  Body(ocLow, True, 2);
  Result.Ends[4] := Spine(highest);
  Result.Ends[5] := Spine(ocHigh);
  Result.Ends[6] := Spine(lowest);
  Result.Ends[7] := Spine(ocLow);
  { the open price's: `openVal > closeVal ? ocHigh : ocLow` }
  if AOpen > AClose then
  begin
    if ABaseIsX then Result.InitBaseline := ocHigh.Y else Result.InitBaseline := ocHigh.X;
  end
  else if ABaseIsX then Result.InitBaseline := ocLow.Y
  else Result.InitBaseline := ocLow.X;
end;

function TyBoxEndsOf(ACart: TTyCartesian2D; ABaseIsX: Boolean;
  AAxisVal: Double; const AValues: array of Double;
  AOffset, AWidth: Double): TTyBoxEnds;
const
  cHalf: Double = 2;
var
  half: Double;
  median, e1, e2, e4, e5: TTyPointF;

  function P(AVal: Double): TTyPointF;
  begin
    Result := PointOf(ACart, ABaseIsX, AAxisVal, AVal);
    { getPoint: the offset added only to a point that is there }
    if IsNan(AAxisVal) or IsNan(AVal) then Exit;
    if ABaseIsX then Result.X := Result.X + AOffset
    else Result.Y := Result.Y + AOffset;
  end;

  function Shift(const APt: TTyPointF; ADelta: Double): TTyPointF;
  begin
    Result := APt;
    if ABaseIsX then Result.X := Result.X + ADelta
    else Result.Y := Result.Y + ADelta;
  end;

begin
  Result := Default(TTyBoxEnds);
  half := AWidth / cHalf;
  median := P(AValues[2]);
  e1 := P(AValues[0]);
  e2 := P(AValues[1]);
  e4 := P(AValues[3]);
  e5 := P(AValues[4]);
  { addBodyEnd(end2, false): minus side, plus side; (end4, true): plus,
    minus -- point1 is += half, point2 -= half }
  Result.Ends[0] := Shift(e2, -half);
  Result.Ends[1] := Shift(e2, half);
  Result.Ends[2] := Shift(e4, half);
  Result.Ends[3] := Shift(e4, -half);
  Result.Ends[4] := e1;
  Result.Ends[5] := e2;
  Result.Ends[6] := e5;
  Result.Ends[7] := e4;
  { layEndLine: from -= half, to += half }
  Result.Ends[8] := Shift(e1, -half);
  Result.Ends[9] := Shift(e1, half);
  Result.Ends[10] := Shift(e5, -half);
  Result.Ends[11] := Shift(e5, half);
  Result.Ends[12] := Shift(median, -half);
  Result.Ends[13] := Shift(median, half);
  if ABaseIsX then Result.InitBaseline := median.Y else Result.InitBaseline := median.X;
end;

function TyWhiskerClipOf(const AArea: TTyXYWH;
  const APoints: array of TTyPointF): TTyWhiskerClip;
var k, n: Integer;
begin
  n := 0;
  for k := 0 to High(APoints) do
    { BoundingRect.contain: the edges included, not-a-number nowhere (and
      not compared: an ordered comparison with it raises here) }
    if not (IsNan(APoints[k].X) or IsNan(APoints[k].Y))
      and (APoints[k].X >= AArea.X) and (APoints[k].X <= AArea.X + AArea.W)
      and (APoints[k].Y >= AArea.Y) and (APoints[k].Y <= AArea.Y + AArea.H) then
      Inc(n);
  if n = 0 then Result := wcFull
  else if n < Length(APoints) then Result := wcPartial
  else Result := wcNone;
end;

function TyWhiskerClipRect(const AArea: TTyXYWH): TTyRectF;
var x, w: Double;
begin
  x := AArea.X;
  w := Ceil(AArea.W);
  if x <> Floor(x) then
  begin
    x := Floor(x);
    w := w + 1;
  end;
  Result := TyRectF(x, AArea.Y, x + w, AArea.Y + AArea.H);
end;

function TySolveWhiskerLayouts(AOption: TTyChartOption;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  AIndex: TTyAxisSeriesIndex): TTyWhiskerLayoutArray;
var
  i, k: Integer;
  node: TJSONObject;
  d: TJSONData;
  onIt: TTyIntegerArray;
  band: Double;
  lo, hi, widths, offsets: TTyDoubleArray;
  done: array of Boolean;

  function NodeOf(ASlot: Integer): TJSONObject;
  var dd: TJSONData;
  begin
    Result := nil;
    dd := AOption.ComponentAt('series', ABindings[ASlot].SeriesIndex);
    if dd is TJSONObject then Result := TJSONObject(dd);
  end;

  function ClipOf(ANode: TJSONObject): Boolean;
  var c: TJSONData;
  begin
    Result := True;
    if ANode = nil then Exit;
    c := ANode.Find('clip');
    if (c = nil) then Exit;
    case c.JSONType of
      jtNull: Result := False;
      jtBoolean: Result := c.AsBoolean;
      jtNumber: Result := (c.AsFloat <> 0) and not IsNan(c.AsFloat);
      jtString: Result := c.AsString <> '';
    else
      Result := True;
    end;
  end;

begin
  Result := nil;
  SetLength(Result, Length(ABindings));
  for i := 0 to High(Result) do Result[i] := Default(TTyWhiskerLayout);
  if (AOption = nil) or (AIndex = nil) then Exit;
  SetLength(done, Length(ABindings));
  for i := 0 to High(ABindings) do
  begin
    if done[i] then Continue;
    if not ABindings[i].Resolved or ABindings[i].Hidden
      or not ABindings[i].HasAxes or (ABindings[i].BaseAxis = nil) then Continue;
    if ABindings[i].SeriesType = 'candlestick' then
    begin
      onIt := AIndex.SeriesOnAxisOfKey(ABindings[i].BaseAxis,
        TySeriesStatKey('candlestick', ABindings[i].CoordSysName));
      band := TyWhiskerBand(ABindings[i].BaseAxis, AStores, onIt);
      node := NodeOf(i);
      Result[i].Solved := True;
      Result[i].Clip := ClipOf(node);
      if node <> nil then
        Result[i].CandleWidth := TyCandleWidthOf(band, node.Find('barWidth'),
          node.Find('barMaxWidth'), node.Find('barMinWidth'))
      else
        Result[i].CandleWidth := TyCandleWidthOf(band, nil, nil, nil);
      done[i] := True;
    end
    else if ABindings[i].SeriesType = 'boxplot' then
    begin
      { THE WHOLE AXIS AT ONCE: every boxplot series on it, in series order }
      onIt := AIndex.SeriesOnAxisOfKey(ABindings[i].BaseAxis,
        TySeriesStatKey('boxplot', ABindings[i].CoordSysName));
      if Length(onIt) = 0 then Continue;
      band := TyWhiskerBand(ABindings[i].BaseAxis, AStores, onIt);
      SetLength(lo, Length(onIt));
      SetLength(hi, Length(onIt));
      for k := 0 to High(onIt) do
      begin
        node := NodeOf(onIt[k]);
        d := nil;
        if node <> nil then d := node.Find('boxWidth');
        TyBoxWidthBounds(d, band, lo[k], hi[k]);
      end;
      TyBoxplotBase(band, lo, hi, widths, offsets);
      for k := 0 to High(onIt) do
      begin
        if (onIt[k] < 0) or (onIt[k] > High(Result)) then Continue;
        Result[onIt[k]].Solved := True;
        Result[onIt[k]].BoxWidth := widths[k];
        Result[onIt[k]].BoxOffset := offsets[k];
        Result[onIt[k]].Clip := ClipOf(NodeOf(onIt[k]));
        done[onIt[k]] := True;
      end;
    end;
  end;
end;

end.
