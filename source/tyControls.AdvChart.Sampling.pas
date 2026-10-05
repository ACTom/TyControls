unit tyControls.AdvChart.Sampling;
{$mode objfpc}{$H+}
{ `series.sampling`: a line's or a bar's rows thinned to about one per pixel
  of the base axis. A PORT OF src/processor/dataSample.ts and of DataStore.ts
  lttbDownSample / minmaxDownSample / downSample, read off the ECharts 6.1.0
  source and held to the real dist by tools/advchart-oracle/sampling.js.
  [Batch 102, roadmap B10]

  WHEN. A cartesian2d line or bar with a truthy `sampling` and MORE THAN TEN
  rows in view -- the count after the dataZoom filter, because the stage runs
  at PRIORITY.PROCESSOR.STATISTIC (5000), after the stack (900) and the filter
  (1000). The rate is Math.round(count / size), size being the base axis'
  pixel length times the device pixel ratio as the grid stood BEFORE the data
  processing (Grid.create's resize, ahead of containLabel and outerBounds);
  sampled when that rate is finite and above 1. The methods are handed
  1 / rate and take Math.floor(1 / that) as the frame size -- kept in that
  shape, because 1 / (1 / r) is not always r.

  WHAT. lttb and minmax pick rows and leave the values alone. average, sum,
  max, min and nearest pick ONE row per frame -- frame start plus
  Math.round(frame / 2), clamped to the last row -- and write the frame's
  value into it: upstream writes into a cloned value column, so the parsed
  value is still what getRawData() reads (labels and tooltips print the raw
  item, the position is the sampled value). Only the value column is
  touched -- data.mapDimension(valueAxis.dim), the ORIGINAL one for a stacked
  series, whose stack was summed from the unsampled values already.

  UPSTREAM'S lttb, NOT THE TEXTBOOK ONE, in four places, all kept:
    - the next frame runs to `len`, not `len - 1`, so the last row is averaged
      into the final bucket's mean and the last frame can take the last row,
      which is then appended a second time;
    - the next frame's mean divides by the frame's length, NaN rows included
      (they add nothing);
    - a frame that has a NaN row and a number keeps BOTH the first NaN row and
      the pick, in raw order, so the line breaks where the data does;
    - a frame where nothing could be scored (all NaN, or point A itself NaN)
      keeps `frameStart`, a VIEW index, as if it were a raw one -- behind a
      dataZoom that is a row outside the window.
  Its index array has min((ceil(len / frame) + 2) * 2, len) slots. Only
  alternating nulls at rate 2 over an odd count write one more; upstream drops
  the extra index while its count still counts it, and the render throws
  (`Invalid typed array length`). Here the count stops at the slots -- the
  rows upstream's array actually holds.

  NaN follows upstream line by line: minmax seeds a frame from its first row
  even when that is NaN (every comparison then fails and the frame keeps that
  row twice); average skips NaN and answers NaN for none; sum takes NaN as 0;
  max and min answer NaN for an infinite result as well as for none; nearest
  is the frame's first value, NaN or not. The arithmetic runs with the FPU
  traps masked so Infinity and NaN behave as in JavaScript.

  NOT HERE: `sampling` as a function (no JS here; a handler registry could
  carry it later), and the names Object.prototype lends upstream's sampler
  table (`'toString'` and its kind are samplers there by accident) -- both
  read as no sampling.

  PURE: SysUtils, Math, fpjson and the AdvChart data layer. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Data;

type
  TTySamplingMode = (tsmNone, tsmLttb, tsmMinmax, tsmAverage, tsmSum, tsmMax,
    tsmMin, tsmNearest);

  { What a sampler made of a view: the raw rows kept, in order, and the value
    column (by raw row) after its writes. Wrote: a value sampler ran. }
  TTySampleResult = record
    Indices: TTyIntegerArray;
    Column: TTyDoubleArray;
    Wrote: Boolean;
  end;

{ `sampling` as the series wrote it: one of the seven names, case and all;
  anything else -- 'none', an unknown name, a boolean, a number, nil -- is
  tsmNone. }
function TySamplingModeOf(AValue: TJSONData): TTySamplingMode;
function TySamplingModeName(AMode: TTySamplingMode): string;

{ Math.round(count / size): NaN for a NaN size, +Infinity for a zero one. }
function TySamplingRate(ACount: Integer; ASize: Double): Double;

{ dataSample's gate on the count and the rate: count > 10, rate finite and
  above 1. }
function TySamplingApplies(ACount: Integer; ARate: Double): Boolean;

{ One sampler over a view. AView holds the raw row of every view row,
  AColumn the value column by RAW row (read where lttb's view-index slip
  points too). ARateArg is what upstream hands the method: 1 / rate. A frame
  size below 1 samples nothing (Indices is the view). }
function TySampleView(AMode: TTySamplingMode; const AView: TTyIntegerArray;
  const AColumn: TTyDoubleArray; ARateArg: Double): TTySampleResult;

{ dataSample's reset over a store: the gate, the rate from ASizePx (the base
  axis' length in device pixels -- css px times the pixel ratio), the sampler
  on ACol, and the view and values written back. True when it sampled. }
function TySampleStore(AMode: TTySamplingMode; AStore: TTyDataStore;
  ACol: Integer; ASizePx: Double): Boolean;

implementation

uses tyControls.AdvChart.Scale;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  { the SSE flags too: ClearExceptions clears only the x87 status word here,
    and a sticky invalid-operation flag would make the host's next division
    by zero report as an invalid operation }
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

const
  cModeNames: array[TTySamplingMode] of string = ('none', 'lttb', 'minmax',
    'average', 'sum', 'max', 'min', 'nearest');

function TySamplingModeOf(AValue: TJSONData): TTySamplingMode;
var
  m: TTySamplingMode;
  s: string;
begin
  Result := tsmNone;
  if (AValue = nil) or (AValue.JSONType <> jtString) then Exit;
  s := AValue.AsString;
  for m := Succ(tsmNone) to High(TTySamplingMode) do
    if cModeNames[m] = s then Exit(m);
end;

function TySamplingModeName(AMode: TTySamplingMode): string;
begin
  Result := cModeNames[AMode];
end;

function TySamplingRate(ACount: Integer; ASize: Double): Double;
begin
  if IsNan(ASize) then Exit(NaN);
  if ASize = 0 then
  begin
    if ACount = 0 then Exit(NaN);
    Exit(Infinity);
  end;
  Result := TyJsRound(ACount / ASize);
end;

function TySamplingApplies(ACount: Integer; ARate: Double): Boolean;
begin
  Result := (ACount > 10) and not IsNan(ARate) and not IsInfinite(ARate)
    and (ARate > 1);
end;

{ ---------------- the samplers (dataSample.ts) ---------------- }

function SampleValue(AMode: TTySamplingMode; const AFrame: TTyDoubleArray;
  ALen: Integer): Double;
var
  i, n: Integer;
  s, v: Double;
begin
  case AMode of
    tsmAverage:
      begin
        s := 0;
        n := 0;
        for i := 0 to ALen - 1 do
          if not IsNan(AFrame[i]) then
          begin
            s := s + AFrame[i];
            Inc(n);
          end;
        if n = 0 then Result := NaN else Result := s / n;
      end;
    tsmSum:
      begin
        { `sum += frame[i] || 0`: a NaN adds 0 }
        s := 0;
        for i := 0 to ALen - 1 do
          if not IsNan(AFrame[i]) then s := s + AFrame[i];
        Result := s;
      end;
    tsmMax:
      begin
        v := NegInfinity;
        for i := 0 to ALen - 1 do
          if AFrame[i] > v then v := AFrame[i];
        { "NaN will cause illegal axis extent": +Infinity goes too }
        if IsNan(v) or IsInfinite(v) then Result := NaN else Result := v;
      end;
    tsmMin:
      begin
        v := Infinity;
        for i := 0 to ALen - 1 do
          if AFrame[i] < v then v := AFrame[i];
        if IsNan(v) or IsInfinite(v) then Result := NaN else Result := v;
      end;
    tsmNearest:
      Result := AFrame[0];
  else
    Result := NaN;
  end;
end;

{ ---------------- DataStore.ts ---------------- }

function Lttb(const AView: TTyIntegerArray; const ACol: TTyDoubleArray;
  AFrame: Integer): TTyIntegerArray;
var
  len, cap, sampled, i, idx, raw, cur, next, firstNaN, countNaN: Integer;
  nfs, nfe, frameStart, frameEnd: Integer;
  avgX, avgY, pointAX, pointAY, y, area, maxArea: Double;
  kept: TTyIntegerArray;

  procedure Put(AValue: Integer);
  begin
    { the typed array's length caps what is kept -- see the header }
    if sampled < cap then kept[sampled] := AValue;
    Inc(sampled);
  end;

begin
  len := Length(AView);
  cap := Min(((len + AFrame - 1) div AFrame + 2) * 2, len);
  SetLength(kept, cap);
  sampled := 0;
  cur := AView[0];
  { the first frame is the first row }
  Put(cur);
  i := 1;
  while i < len - 1 do
  begin
    nfs := Min(i + AFrame, len - 1);
    { to `len`: the last row is in the last bucket's mean }
    nfe := Min(Int64(i) + Int64(AFrame) * 2, len);
    avgX := (nfe + nfs) / 2;
    avgY := 0;
    for idx := nfs to nfe - 1 do
    begin
      y := ACol[AView[idx]];
      if IsNan(y) then Continue;
      avgY := avgY + y;
    end;
    { NaN rows count in the divisor }
    avgY := avgY / (nfe - nfs);
    frameStart := i;
    frameEnd := Min(Int64(i) + AFrame, len);
    pointAX := i - 1;
    pointAY := ACol[cur];
    maxArea := -1;
    { A VIEW INDEX, used below as a raw one when nothing scores }
    next := frameStart;
    firstNaN := -1;
    countNaN := 0;
    for idx := frameStart to frameEnd - 1 do
    begin
      raw := AView[idx];
      y := ACol[raw];
      if IsNan(y) then
      begin
        Inc(countNaN);
        if firstNaN < 0 then firstNaN := raw;
        Continue;
      end;
      area := Abs((pointAX - avgX) * (y - pointAY)
        - (pointAX - idx) * (avgY - pointAY));
      if area > maxArea then
      begin
        maxArea := area;
        next := raw;
      end;
    end;
    if (countNaN > 0) and (countNaN < frameEnd - frameStart) then
    begin
      { the first NaN row too, in raw order }
      Put(Min(firstNaN, next));
      next := Max(firstNaN, next);
    end;
    Put(next);
    cur := next;
    i := i + AFrame;
  end;
  { the last frame is the last row }
  Put(AView[len - 1]);
  SetLength(kept, Min(sampled, cap));
  Result := kept;
end;

function MinMax(const AView: TTyIntegerArray; const ACol: TTyDoubleArray;
  AFrame: Integer): TTyIntegerArray;
var
  len, n, i, k, minIdx, maxIdx, thisFrame: Integer;
  minV, maxV, v: Double;
begin
  len := Length(AView);
  SetLength(Result, ((len + AFrame - 1) div AFrame) * 2);
  n := 0;
  i := 0;
  while i < len do
  begin
    { seeded from the frame's first row, NaN or not }
    minIdx := i;
    minV := ACol[AView[minIdx]];
    maxIdx := i;
    maxV := ACol[AView[maxIdx]];
    thisFrame := AFrame;
    if Int64(i) + AFrame > len then thisFrame := len - i;
    for k := 0 to thisFrame - 1 do
    begin
      v := ACol[AView[i + k]];
      if v < minV then
      begin
        minV := v;
        minIdx := i + k;
      end;
      if v > maxV then
      begin
        maxV := v;
        maxIdx := i + k;
      end;
    end;
    { in the frame's own order; a frame whose min and max are one row keeps
      it twice, the max's copy first }
    if minIdx < maxIdx then
    begin
      Result[n] := AView[minIdx];
      Result[n + 1] := AView[maxIdx];
    end
    else
    begin
      Result[n] := AView[maxIdx];
      Result[n + 1] := AView[minIdx];
    end;
    Inc(n, 2);
    i := i + AFrame;
  end;
  SetLength(Result, n);
end;

function DownSample(AMode: TTySamplingMode; const AView: TTyIntegerArray;
  var ACol: TTyDoubleArray; AFrame: Integer): TTyIntegerArray;
var
  len, n, i, k, at, raw, frame: Integer;
  values: TTyDoubleArray;
  v: Double;
begin
  len := Length(AView);
  SetLength(Result, (len + AFrame - 1) div AFrame);
  SetLength(values, AFrame);
  frame := AFrame;
  n := 0;
  i := 0;
  while i < len do
  begin
    { the last frame is shorter, and stays so }
    if frame > len - i then frame := len - i;
    { read from the column as written so far, as upstream does }
    for k := 0 to frame - 1 do
      values[k] := ACol[AView[i + k]];
    v := SampleValue(AMode, values, frame);
    { indexSampler: Math.round(frame / 2), clamped to the last row }
    at := Min(Int64(i) + Trunc(TyJsRound(frame / 2)), len - 1);
    raw := AView[at];
    ACol[raw] := v;
    Result[n] := raw;
    Inc(n);
    i := i + frame;
  end;
  SetLength(Result, n);
end;

function TySampleView(AMode: TTySamplingMode; const AView: TTyIntegerArray;
  const AColumn: TTyDoubleArray; ARateArg: Double): TTySampleResult;
var
  mask: TFPUExceptionMask;
  fs: Double;
  frame, len: Integer;
begin
  Result.Indices := Copy(AView);
  Result.Column := Copy(AColumn);
  Result.Wrote := False;
  len := Length(AView);
  if (AMode = tsmNone) or (len = 0) then Exit;
  mask := MaskFP;
  try
    { Math.floor(1 / rate), as upstream computes it from what it is handed }
    fs := JsFloor(1 / ARateArg);
    if IsNan(fs) or (fs < 1) then Exit;
    { a frame wider than the view samples exactly as one the view's width:
      every bound is min'ed against the length }
    if fs > len then frame := len else frame := Trunc(fs);
    case AMode of
      tsmLttb: Result.Indices := Lttb(AView, Result.Column, frame);
      tsmMinmax: Result.Indices := MinMax(AView, Result.Column, frame);
    else
      Result.Indices := DownSample(AMode, AView, Result.Column, frame);
      Result.Wrote := True;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TySampleStore(AMode: TTySamplingMode; AStore: TTyDataStore;
  ACol: Integer; ASizePx: Double): Boolean;
var
  view, idx: TTyIntegerArray;
  col: TTyDoubleArray;
  rate: Double;
  i, n: Integer;
  res: TTySampleResult;
begin
  Result := False;
  if (AMode = tsmNone) or (AStore = nil) then Exit;
  if (ACol < 0) or (ACol >= AStore.DimCount) then Exit;
  n := AStore.Count;
  rate := TySamplingRate(n, ASizePx);
  if not TySamplingApplies(n, rate) then Exit;
  SetLength(view, n);
  for i := 0 to n - 1 do view[i] := AStore.GetRawIndex(i);
  SetLength(col, AStore.RawCount);
  for i := 0 to High(col) do col[i] := AStore.GetByRaw(ACol, i);
  res := TySampleView(AMode, view, col, 1 / rate);
  idx := res.Indices;
  if res.Wrote then
    for i := 0 to High(idx) do
      AStore.SetSampledValue(ACol, idx[i], res.Column[idx[i]]);
  AStore.SetSampledView(idx, Length(idx));
  Result := True;
end;

end.
