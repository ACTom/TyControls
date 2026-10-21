unit tyControls.AdvanceChart.AxisBreak;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- AXIS BREAKS, the option and the view (batch 132).

  UPSTREAM'S scale/breakImpl.ts (the parsing) and
  component/axis/axisBreakHelperImpl.ts (the view), transcribed operation
  for operation. The scale's side -- the elapsed mapping, the gaps, the
  pruning and the break ends as ticks -- lives with the scale
  (TTyBreakScaleMapper, TyUpdateBreakGapReal); this unit holds what reads
  the option and what is drawn:

    - `breaks` parsed as upstream parses them: start and end through the
      scale's parse, a percent gap or an absolute one in data units, an
      expanded break left out, a backwards one turned round, then sorted
      by start with any break that overlaps the one before dropped;
    - breakArea's options, and each break's ZIGZAG: two polylines across
      the grid at the break's two ends, their points walked from the grid's
      edge by random steps that the axis keeps per break -- so a render
      draws only the numbers it has not drawn before -- and alternately
      pushed out by the amplitude;
    - the axis line cut at the breaks (axisLine.breakLine);
    - a break's two labels moved apart when they overlap
      (breakLabelLayout.moveOverlap): adjustBreakLabelPair.

  THE RANDOM NUMBERS are the xorshift32 of the force layout and the jitter
  (TyJitterRandom), one state per chart, never reset by a render: upstream
  draws from Math.random, which the oracle replaces with this generator
  seeded once per chart.

  PURE: SysUtils, Math, fcl-json and the AdvanceChart units. }
interface
uses SysUtils, Math, fpjson, tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Scale,
  tyControls.AdvanceChart.Layout, tyControls.AdvanceChart.AxisLabels;

type
  { breakArea as an axis option writes it over axisDefault's. A colour the
    option does not write is the skin's (HasColor / HasBorderColor False);
    a border width not written likewise (NaN). }
  TTyBreakAreaOpt = record
    Show: Boolean;
    HasColor, HasBorderColor: Boolean;
    Color, BorderColor: string;
    BorderWidth: Double;
    { itemStyle.borderType as the line dash: [3, 3] unless written; empty
      for 'solid' }
    Dash: TTyDoubleArray;
    { itemStyle.opacity, NaN when not written }
    Opacity: Double;
    Amplitude, MinSpan, MaxSpan, Z: Double;
    ExpandOnClick: Boolean;
  end;

{ `breaks` of an axis, parsed (parseAxisBreakOption). AIsTime picks the
  time scale's parse (a number rounded, a string a date) over the interval
  scale's (Number()). ANoNegative: a log axis' `noNegative` -- an end
  below nought is nought [F4a]. }
function TyParseAxisBreaks(AData: TJSONData; AIsTime: Boolean;
  ANoNegative: Boolean = False): TTyAxisBreakArray;
{ retrieveAxisBreaksOption on a cartesian axis: the `breaks` key written
  (anything but null), on an axis that is not a category one }
function TyAxisBreaksWritten(ANode: TJSONObject): Boolean;
{ String() of an option value as the break identity takes it }
function TyBreakJsText(AData: TJSONData): string;
{ breakArea over axisDefault's }
function TyBreakAreaOptOf(ANode: TJSONObject): TTyBreakAreaOpt; overload;
{ ... of an axis' option node, whatever it is }
function TyBreakAreaOptOf(AData: TJSONData): TTyBreakAreaOpt; overload;
{ breakLabelLayout.moveOverlap: true or 'auto' (the default) }
function TyBreakMoveOverlap(ANode: TJSONObject): Boolean;
{ axisLine.breakLine, true unless written falsy }
function TyAxisBreakLineOn(ANode: TJSONObject): Boolean;

{ ONE BREAK'S ZIGZAG (addZigzagShapes). AC0, AC1: the break's two ends
  along the axis, global px, in either order; AHorizontal: the axis runs
  along x, so the zigzag runs down the grid from AZMin to AZMax. ARandoms
  is the break's cache, extended from AState as the walk needs more. }
procedure TyBreakZigzag(AC0, AC1: Double; AHorizontal: Boolean;
  AZMin, AZMax, AAmplitude, AMinSpan, AMaxSpan: Double;
  var ARandoms: TTyDoubleArray; var AState: LongWord;
  out AA, AB: TTyBreakPointArray);

{ THE AXIS LINE CUT AT THE BREAKS (buildAxisBreakLine). AFrame is the
  axis group's frame; APairs the breaks' two ends in the axis' own frame
  (axis.dataToCoord, clamped), AIds their identities, both in the breaks'
  order; ALineWidth the axis line's width. }
function TyAxisBreakLineSegs(const AFrame: TTyAxisNameFrame;
  const APairs: array of TTyRange; const AIds: array of string;
  ALineWidth: Double): TTyAxisLineSegArray;

{ adjustBreakLabelPair: AP0 / AP1 the labels of a break's start and end,
  ABox0 / ABox1 their boxes (the margin box for the overlap, the bare
  local rect for the share each moves). When they overlap along the
  axis' direction the two move apart by the minimal translation, shared so
  the gap between them stays at the break's middle. Turned labels whose
  boxes overlap off the axes are not moved (the oriented test is not
  ported). }
procedure TyAdjustBreakLabelPair(AInverse: Boolean; AAxisRotation: Double;
  var AP0, AP1: TTyAxisLabelPlacement; const ABox0, ABox1: TTyLabelBox;
  const ABareLocal0, ABareLocal1: TTyXYWH);

implementation

uses tyControls.AdvanceChart.Data, tyControls.AdvanceChart.JsMath,
  tyControls.AdvanceChart.AxisName, tyControls.AdvanceChart.AnimAxis,
  tyControls.AdvanceChart.Jitter;

{ ==================== the option ==================== }

function TyBreakJsText(AData: TJSONData): string;
begin
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtString: Result := AData.AsString;
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtArray: Result := '';
  else
    Result := '[object Object]';
  end;
end;

{ IntervalScale.parse: null and '' are not numbers, anything else Number() }
function ParseInterval(AData: TJSONData): Double;
begin
  Result := NaN;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtString:
      if AData.AsString <> '' then Result := TyJsToNumber(AData.AsString);
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
  end;
end;

{ TimeScale.parse: a number rounded, anything else parseDate }
function ParseTime(AData: TJSONData): Double;
var ms: Double;
begin
  Result := NaN;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := TyJsRound(AData.AsFloat);
    jtString: if TyParseDateMs(AData.AsString, ms) then Result := ms;
  end;
end;

function TyParseAxisBreaks(AData: TJSONData; AIsTime: Boolean;
  ANoNegative: Boolean): TTyAxisBreakArray;
var
  i, j, n: Integer;
  o: TJSONObject;
  b, tmp: TTyAxisBreak;
  d, ds, de: TJSONData;
  s: string;
  isPrct: Boolean;
  pct, abs_, lastEnd: Double;
  keep: array of Boolean;

  function Parse(AValue: TJSONData): Double;
  begin
    if AIsTime then Result := ParseTime(AValue) else Result := ParseInterval(AValue);
  end;

var mask: TFPUExceptionMask;
begin
  Result := nil;
  if not (AData is TJSONArray) then Exit;
  { JavaScript's comparisons: a not-a-number end answers false, FPC would
    raise }
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide]);
  try
  n := 0;
  for i := 0 to AData.Count - 1 do
  begin
    if not (TJSONArray(AData).Items[i] is TJSONObject) then Continue;
    o := TJSONObject(TJSONArray(AData).Items[i]);
    ds := o.Find('start');
    de := o.Find('end');
    if (ds = nil) or (ds.JSONType = jtNull) or (de = nil) or (de.JSONType = jtNull) then
      Continue;
    { an expanded break is no break }
    d := o.Find('isExpanded');
    if (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
      or ((d.JSONType = jtNumber) and (d.AsFloat <> 0) and not IsNan(d.AsFloat))
      or ((d.JSONType = jtString) and (d.AsString <> ''))
      or (d.JSONType in [jtArray, jtObject])) then Continue;
    b := Default(TTyAxisBreak);
    b.VMin := Parse(ds);
    b.VMax := Parse(de);
    b.GapKind := bgkAbs;
    b.GapVal := 0;
    b.Id := TyBreakJsText(ds) + '_'#0'_' + TyBreakJsText(de);
    b.StartJson := ds.AsJSON;
    b.EndJson := de.AsJSON;
    d := o.Find('gap');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      isPrct := False;
      if d.JSONType = jtString then
      begin
        s := TyJsTrim(d.AsString);
        if (s <> '') and (s[Length(s)] = '%') then
        begin
          pct := TyJsParseFloat(s) / 100;
          { >= 0 and < 1 - 1e-5, or nought }
          if not ((pct >= 0) and (pct < 1 - 1e-5)) then pct := 0;
          b.GapKind := bgkPrct;
          b.GapVal := pct;
          isPrct := True;
        end;
      end;
      if not isPrct then
      begin
        abs_ := Parse(d);
        if IsNan(abs_) or IsInfinite(abs_) or (abs_ < 0) then abs_ := 0;
        b.GapKind := bgkAbs;
        b.GapVal := abs_;
      end;
    end;
    if b.VMin = b.VMax then
    begin
      b.GapKind := bgkAbs;
      b.GapVal := 0;
    end;
    { noNegative: an end below nought is nought [F4a] }
    if ANoNegative then
    begin
      if b.VMin < 0 then b.VMin := 0;
      if b.VMax < 0 then b.VMax := 0;
    end;
    { written backwards: turned round }
    if b.VMin > b.VMax then
    begin
      abs_ := b.VMax;
      b.VMax := b.VMin;
      b.VMin := abs_;
    end;
    SetLength(Result, n + 1);
    Result[n] := b;
    Inc(n);
  end;
  { sorted by start, stable (V8's sort; a not-a-number start compares as
    nothing and stays where it is) }
  for i := 1 to n - 1 do
  begin
    tmp := Result[i];
    j := i - 1;
    while (j >= 0) and (Result[j].VMin - tmp.VMin > 0) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := tmp;
  end;
  { a break overlapping the one before is dropped -- and the one after is
    checked against the dropped one's end, as upstream's loop does }
  SetLength(keep, n);
  lastEnd := NegInfinity;
  for i := 0 to n - 1 do
  begin
    keep[i] := not (lastEnd > Result[i].VMin);
    lastEnd := Result[i].VMax;
  end;
  j := 0;
  for i := 0 to n - 1 do
    if keep[i] then
    begin
      Result[j] := Result[i];
      Inc(j);
    end;
  SetLength(Result, j);
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

function TyAxisBreaksWritten(ANode: TJSONObject): Boolean;
var d: TJSONData;
begin
  Result := False;
  if ANode = nil then Exit;
  d := ANode.Find('breaks');
  Result := (d <> nil) and (d.JSONType <> jtNull);
end;

function JsTruthy(AData: TJSONData): Boolean;
begin
  Result := False;
  if AData = nil then Exit;
  case AData.JSONType of
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
    jtArray, jtObject: Result := True;
  end;
end;

function NumOr(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function TyBreakAreaOptOf(ANode: TJSONObject): TTyBreakAreaOpt;
var
  ba, st: TJSONObject;
  d: TJSONData;
  i: Integer;
begin
  Result := Default(TTyBreakAreaOpt);
  Result.Show := True;
  Result.BorderWidth := NaN;
  Result.Opacity := NaN;
  SetLength(Result.Dash, 2);
  Result.Dash[0] := 3;
  Result.Dash[1] := 3;
  Result.Amplitude := 4;
  Result.MinSpan := 4;
  Result.MaxSpan := 20;
  Result.Z := 100;
  Result.ExpandOnClick := True;
  ba := nil;
  if ANode <> nil then
  begin
    d := ANode.Find('breakArea');
    if d is TJSONObject then ba := TJSONObject(d);
  end;
  if ba = nil then Exit;
  d := ba.Find('show');
  if d <> nil then Result.Show := JsTruthy(d);
  d := ba.Find('expandOnClick');
  if d <> nil then Result.ExpandOnClick := JsTruthy(d);
  Result.Amplitude := NumOr(ba, 'zigzagAmplitude', 4);
  Result.MinSpan := NumOr(ba, 'zigzagMinSpan', 4);
  Result.MaxSpan := NumOr(ba, 'zigzagMaxSpan', 20);
  Result.Z := NumOr(ba, 'zigzagZ', 100);
  d := ba.Find('itemStyle');
  if not (d is TJSONObject) then Exit;
  st := TJSONObject(d);
  d := st.Find('color');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.HasColor := True;
    Result.Color := d.AsString;
  end;
  d := st.Find('borderColor');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.HasBorderColor := True;
    Result.BorderColor := d.AsString;
  end;
  d := st.Find('borderWidth');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.BorderWidth := d.AsFloat;
  d := st.Find('opacity');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Opacity := d.AsFloat;
  d := st.Find('borderType');
  if d <> nil then
  begin
    { getLineDash: 'solid' (or nothing usable) none, 'dashed' [4, 4]... as
      the line style reads it; a list as written }
    if d.JSONType = jtString then
    begin
      if d.AsString = 'dashed' then
      begin
        SetLength(Result.Dash, 2);
        Result.Dash[0] := 4;
        Result.Dash[1] := 4;
      end
      else if d.AsString = 'dotted' then
      begin
        SetLength(Result.Dash, 2);
        Result.Dash[0] := 1;
        Result.Dash[1] := 1;
      end
      else
        Result.Dash := nil;
    end
    else if d is TJSONArray then
    begin
      SetLength(Result.Dash, d.Count);
      for i := 0 to d.Count - 1 do
        if TJSONArray(d).Items[i].JSONType = jtNumber then
          Result.Dash[i] := TJSONArray(d).Items[i].AsFloat
        else
          Result.Dash[i] := 0;
    end;
  end;
end;

function TyBreakAreaOptOf(AData: TJSONData): TTyBreakAreaOpt;
begin
  if AData is TJSONObject then Result := TyBreakAreaOptOf(TJSONObject(AData))
  else Result := TyBreakAreaOptOf(TJSONObject(nil));
end;

function TyBreakMoveOverlap(ANode: TJSONObject): Boolean;
var d: TJSONData;
begin
  Result := True;
  if ANode = nil then Exit;
  d := ANode.Find('breakLabelLayout');
  if not (d is TJSONObject) then Exit;
  d := TJSONObject(d).Find('moveOverlap');
  if d = nil then Exit;
  Result := ((d.JSONType = jtBoolean) and d.AsBoolean)
    or ((d.JSONType = jtString) and (d.AsString = 'auto'));
end;

function TyAxisBreakLineOn(ANode: TJSONObject): Boolean;
var d: TJSONData;
begin
  Result := True;
  if ANode = nil then Exit;
  d := ANode.Find('axisLine');
  if not (d is TJSONObject) then Exit;
  d := TJSONObject(d).Find('breakLine');
  if d <> nil then Result := JsTruthy(d);
end;

{ ==================== the zigzag ==================== }

procedure TyBreakZigzag(AC0, AC1: Double; AHorizontal: Boolean;
  AZMin, AZMax, AAmplitude, AMinSpan, AMaxSpan: Double;
  var ARandoms: TTyDoubleArray; var AState: LongWord;
  out AA, AB: TTyBreakPointArray);
var
  t, cur, pa, pb, rv, minS, maxS: Double;
  isSwap, first, last: Boolean;
  idx, n: Integer;
begin
  AA := nil;
  AB := nil;
  if AC1 < AC0 then
  begin
    t := AC0;
    AC0 := AC1;
    AC1 := t;
  end;
  { subPixelOptimizeLine with a width of one, on a line across the grid at
    each end: only the end along the axis is snapped }
  AC0 := TySubPixelOptimize(AC0, 1, True);
  AC1 := TySubPixelOptimize(AC1, 1, True);
  { arbitrary floors against a dead loop }
  minS := Max(Double(2), AMinSpan);
  if IsNan(AMinSpan) or (AMinSpan = 0) then minS := 2;
  maxS := Max(minS, AMaxSpan);
  if IsNan(AMaxSpan) or (AMaxSpan = 0) then maxS := minS;
  isSwap := True;
  cur := AZMin;
  n := 0;
  idx := 0;
  while True do
  begin
    { the first and the last point exactly on the grid's edges, so the
      zigzag meets the axis where its tick is }
    first := cur = AZMin;
    last := cur >= AZMax;
    if last then cur := AZMax;
    pa := AC0;
    pb := AC1;
    if not first and not last then
    begin
      if isSwap then pa := pa + -AAmplitude else pa := pa + AAmplitude;
      if not isSwap then pb := pb - -AAmplitude else pb := pb - AAmplitude;
    end;
    SetLength(AA, n + 1);
    SetLength(AB, n + 1);
    if AHorizontal then
    begin
      AA[n].X := pa;
      AA[n].Y := cur;
      AB[n].X := pb;
      AB[n].Y := cur;
    end
    else
    begin
      AA[n].X := cur;
      AA[n].Y := pa;
      AB[n].X := cur;
      AB[n].Y := pb;
    end;
    Inc(n);
    if idx < Length(ARandoms) then
      rv := ARandoms[idx]
    else
    begin
      rv := TyJitterRandom(AState);
      SetLength(ARandoms, Length(ARandoms) + 1);
      ARandoms[High(ARandoms)] := rv;
    end;
    cur := cur + (rv * (maxS - minS) + minS);
    isSwap := not isSwap;
    Inc(idx);
    if last then Break;
    { a fail-safe: a span of nothing cannot get anywhere }
    if n > 100000 then Break;
  end;
end;

{ ==================== the axis line ==================== }

procedure ApplyM(const M: TTyMat2D; var AX, AY: Double);
var x, y: Double;
begin
  x := AX;
  y := AY;
  AX := M[0] * x + M[2] * y + M[4];
  AY := M[1] * x + M[3] * y + M[5];
end;

function TyAxisBreakLineSegs(const AFrame: TTyAxisNameFrame;
  const APairs: array of TTyRange; const AIds: array of string;
  ALineWidth: Double): TTyAxisLineSegArray;
var
  ext0, ext1, segMin, tMin, tMax, t: Double;
  order: array of Integer;
  c0, c1: TTyDoubleArray;
  i, j, k, n, last: Integer;
  m: TTyMat2D;

  procedure AddSeg(AMin, AMax: Double; A1, A2: Integer);
  var
    p1x, p1y, p2x, p2y, d1x, d1y, d2x, d2y: Double;
    s1, s2: string;
  begin
    p1x := AMin; p1y := 0;
    p2x := AMax; p2y := 0;
    d1x := AMin; d1y := 5;
    d2x := AMax; d2y := 5;
    { each end through the group's transform beside a dummy tick, snapped
      with it; then the two ends snapped as the axis line is }
    ApplyM(m, p1x, p1y);
    ApplyM(m, d1x, d1y);
    TySubPixelOptimizeLine(p1x, p1y, d1x, d1y, ALineWidth);
    ApplyM(m, p2x, p2y);
    ApplyM(m, d2x, d2y);
    TySubPixelOptimizeLine(p2x, p2y, d2x, d2y, ALineWidth);
    TySubPixelOptimizeLine(p1x, p1y, p2x, p2y, ALineWidth);
    if A1 >= 0 then s1 := AIds[A1] else s1 := #0;
    if A2 >= 0 then s2 := AIds[A2] else s2 := #0;
    SetLength(Result, n + 1);
    Result[n].Anid := 'breakLine_' + s1 + '_'#0'_' + s2;
    Result[n].X1 := p1x;
    Result[n].Y1 := p1y;
    Result[n].X2 := p2x;
    Result[n].Y2 := p2y;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  m := TyMatLocal(AFrame.PosX, AFrame.PosY, AFrame.Rotation);
  ext0 := AFrame.Ext0;
  ext1 := AFrame.Ext1;
  { an inverse axis' extent turned round }
  if AFrame.Inverse then
  begin
    t := ext0;
    ext0 := ext1;
    ext1 := t;
  end;
  k := Length(APairs);
  SetLength(order, k);
  SetLength(c0, k);
  SetLength(c1, k);
  for i := 0 to k - 1 do
  begin
    c0[i] := APairs[i].Start;
    c1[i] := APairs[i].Stop;
    if c0[i] > c1[i] then
    begin
      t := c0[i];
      c0[i] := c1[i];
      c1[i] := t;
    end;
    order[i] := i;
  end;
  { sorted by the first end, stable }
  for i := 1 to k - 1 do
  begin
    t := c0[order[i]];
    last := order[i];
    j := i - 1;
    while (j >= 0) and (c0[order[j]] - t > 0) do
    begin
      order[j + 1] := order[j];
      Dec(j);
    end;
    order[j + 1] := last;
  end;
  segMin := ext0;
  last := -1;
  for i := 0 to k - 1 do
  begin
    j := order[i];
    tMin := Max(c0[j], ext0);
    tMax := Min(c1[j], ext1);
    if segMin <= tMin then AddSeg(segMin, tMin, last, j);
    segMin := tMax;
    last := j;
  end;
  if segMin <= ext1 then AddSeg(segMin, ext1, last, -1);
end;

{ ==================== a break's two labels ==================== }

{ zrender's matrix.mul }
function MulM(const A, B: TTyMat2D): TTyMat2D;
begin
  Result[0] := A[0] * B[0] + A[2] * B[1];
  Result[1] := A[1] * B[0] + A[3] * B[1];
  Result[2] := A[0] * B[2] + A[2] * B[3];
  Result[3] := A[1] * B[2] + A[3] * B[3];
  Result[4] := A[0] * B[4] + A[2] * B[5] + A[4];
  Result[5] := A[1] * B[4] + A[3] * B[5] + A[5];
end;

{ BoundingRect.applyTransform }
function RectApply(const R: TTyXYWH; const M: TTyMat2D): TTyXYWH;
var
  xs, ys: array[0..3] of Double;
  i: Integer;
  mx, my: Double;
begin
  if (M[1] < 1e-5) and (M[1] > -1e-5) and (M[2] < 1e-5) and (M[2] > -1e-5) then
  begin
    Result.X := R.X * M[0] + M[4];
    Result.Y := R.Y * M[3] + M[5];
    Result.W := R.W * M[0];
    Result.H := R.H * M[3];
    if Result.W < 0 then
    begin
      Result.X := Result.X + Result.W;
      Result.W := -Result.W;
    end;
    if Result.H < 0 then
    begin
      Result.Y := Result.Y + Result.H;
      Result.H := -Result.H;
    end;
    Exit;
  end;
  { lt, rt, rb, lb }
  xs[0] := R.X; ys[0] := R.Y;
  xs[1] := R.X + R.W; ys[1] := R.Y;
  xs[2] := R.X + R.W; ys[2] := R.Y + R.H;
  xs[3] := R.X; ys[3] := R.Y + R.H;
  for i := 0 to 3 do ApplyM(M, xs[i], ys[i]);
  { mathMin(lt, rb, lb, rt) }
  Result.X := Min(Min(Min(xs[0], xs[2]), xs[3]), xs[1]);
  Result.Y := Min(Min(Min(ys[0], ys[2]), ys[3]), ys[1]);
  mx := Max(Max(Max(xs[0], xs[2]), xs[3]), xs[1]);
  my := Max(Max(Max(ys[0], ys[2]), ys[3]), ys[1]);
  Result.W := mx - Result.X;
  Result.H := my - Result.Y;
end;

{ ==================== zrender's OrientedBoundingRect.intersect ====================

  [F4a] With an MTV, a direction and bidirectional false -- what
  adjustBreakLabelPair hands labelIntersect for two labels that are not both
  axis aligned. The intersect context (BoundingRect.ts createIntersectContext):
  minTv starts at (Infinity, Infinity), maxTv at (0, 0), dirMinTv at minTv;
  every overlapping projection offers its two ways out to calcDirMTV, which
  keeps the shortest translation ALONG the direction (one way only). }
type
  TObbM = record
    CX, CY: array[0..3] of Double;
    AX, AY: array[0..1] of Double;
    Origin: array[0..1] of Double;
  end;
  TObbCtx = record
    MinX, MinY, MaxX, MaxY, DirX, DirY: Double;
    Touch: Double;
    NegativeSize: Boolean;
    Direction, CheckX, CheckY: Double;
  end;

function ObbOf(const ABox: TTyLabelBox): TObbM;
var
  x, y, x2, y2, px, py, len: Double;
  i: Integer;
  m: TTyMat2D;
begin
  m := ABox.M;
  x := ABox.LocalRect.X;
  y := ABox.LocalRect.Y;
  x2 := x + ABox.LocalRect.W;
  y2 := y + ABox.LocalRect.H;
  Result.CX[0] := x;  Result.CY[0] := y;
  Result.CX[1] := x2; Result.CY[1] := y;
  Result.CX[2] := x2; Result.CY[2] := y2;
  Result.CX[3] := x;  Result.CY[3] := y2;
  for i := 0 to 3 do
  begin
    px := Result.CX[i];
    py := Result.CY[i];
    Result.CX[i] := m[0] * px + m[2] * py + m[4];
    Result.CY[i] := m[1] * px + m[3] * py + m[5];
  end;
  Result.AX[0] := Result.CX[1] - Result.CX[0];
  Result.AY[0] := Result.CY[1] - Result.CY[0];
  Result.AX[1] := Result.CX[3] - Result.CX[0];
  Result.AY[1] := Result.CY[3] - Result.CY[0];
  for i := 0 to 1 do
  begin
    { Point.normalize: a nought vector stays nought }
    len := Sqrt(Result.AX[i] * Result.AX[i] + Result.AY[i] * Result.AY[i]);
    if len <> 0 then
    begin
      Result.AX[i] := Result.AX[i] / len;
      Result.AY[i] := Result.AY[i] / len;
    end;
  end;
  for i := 0 to 1 do
    Result.Origin[i] := Result.AX[i] * Result.CX[0] + Result.AY[i] * Result.CY[0];
end;

{ _getProjMinMaxOnAxis: the corners on the self box' axis ADim }
procedure ObbProj(var C: TObbCtx; const ASelf, ACorners: TObbM; ADim: Integer;
  out ALo, AHi: Double);
var
  proj, mn, mx: Double;
  k: Integer;
begin
  proj := ACorners.CX[0] * ASelf.AX[ADim] + ACorners.CY[0] * ASelf.AY[ADim]
    + ASelf.Origin[ADim];
  mn := proj;
  mx := proj;
  for k := 1 to 3 do
  begin
    proj := ACorners.CX[k] * ASelf.AX[ADim] + ACorners.CY[k] * ASelf.AY[ADim]
      + ASelf.Origin[ADim];
    mn := Min(proj, mn);
    mx := Max(proj, mx);
  end;
  ALo := mn + C.Touch;
  AHi := mx - C.Touch;
  C.NegativeSize := AHi < ALo;
end;

function ObbNearZero(V: Double): Boolean;
begin
  Result := Abs(V) < 1e-10;
end;

{ calcDirMTV, bidirectional false }
procedure ObbDirMtv(var C: TObbCtx);
var sq, s, co, dot, tx, ty: Double;
begin
  sq := C.MinY * C.MinY + C.MinX * C.MinX;
  s := TyJsSin(C.Direction);
  co := TyJsCos(C.Direction);
  dot := s * C.MinY + co * C.MinX;
  if ObbNearZero(dot) then
  begin
    if ObbNearZero(C.MinX) and ObbNearZero(C.MinY) then
    begin
      C.DirX := 0;
      C.DirY := 0;
    end;
    Exit;
  end;
  tx := sq * co / dot;
  ty := sq * s / dot;
  if ObbNearZero(tx) and ObbNearZero(ty) then
  begin
    C.DirX := 0;
    C.DirY := 0;
    Exit;
  end;
  if (C.CheckX * tx + C.CheckY * ty > 0)
    and (Sqrt(tx * tx + ty * ty) < Sqrt(C.DirX * C.DirX + C.DirY * C.DirY)) then
  begin
    C.DirX := tx;
    C.DirY := ty;
  end;
end;

{ _intersectCheckOneSide with an MTV }
function ObbOneSide(var C: TObbCtx; const ASelf, AOther: TObbM; AInverse: Double): Boolean;
var
  i: Integer;
  lo1, hi1, lo2, hi2, d0, d1, ax, ay: Double;
begin
  Result := True;
  for i := 0 to 1 do
  begin
    ax := ASelf.AX[i];
    ay := ASelf.AY[i];
    ObbProj(C, ASelf, ASelf, i, lo1, hi1);
    ObbProj(C, ASelf, AOther, i, lo2, hi2);
    if C.NegativeSize or (hi1 < lo2) or (lo1 > hi2) then
    begin
      Result := False;
      if C.NegativeSize then Exit;
      d0 := Abs(lo2 - hi1);
      d1 := Abs(lo1 - hi2);
      if Min(d0, d1) > Sqrt(C.MaxX * C.MaxX + C.MaxY * C.MaxY) then
      begin
        if d0 < d1 then
        begin
          C.MaxX := ax * (-d0 * AInverse);
          C.MaxY := ay * (-d0 * AInverse);
        end
        else
        begin
          C.MaxX := ax * (d1 * AInverse);
          C.MaxY := ay * (d1 * AInverse);
        end;
      end;
    end
    else
    begin
      d0 := Abs(lo2 - hi1);
      d1 := Abs(lo1 - hi2);
      { useDir: both ways, one at a time (bidirectional false) }
      C.MinX := ax * (d0 * AInverse);
      C.MinY := ay * (d0 * AInverse);
      ObbDirMtv(C);
      C.MinX := ax * (-d1 * AInverse);
      C.MinY := ay * (-d1 * AInverse);
      ObbDirMtv(C);
    end;
  end;
end;

function TyObbIntersectDir(const A, B: TTyLabelBox; ADirection, ATouch: Double;
  out AMtvX, AMtvY: Double): Boolean;
var
  C: TObbCtx;
  oa, ob: TObbM;
begin
  AMtvX := 0;
  AMtvY := 0;
  C.Touch := Max(Double(0), ATouch);
  C.NegativeSize := False;
  C.MinX := Infinity;
  C.MinY := Infinity;
  C.MaxX := 0;
  C.MaxY := 0;
  C.DirX := Infinity;
  C.DirY := Infinity;
  C.Direction := ADirection;
  C.CheckX := TyJsCos(ADirection);
  C.CheckY := TyJsSin(ADirection);
  oa := ObbOf(A);
  ob := ObbOf(B);
  Result := True;
  if not ObbOneSide(C, oa, ob, 1) then Result := False;
  if not ObbOneSide(C, ob, oa, -1) then Result := False;
  if not C.NegativeSize then
  begin
    if Result then
    begin
      AMtvX := C.DirX;
      AMtvY := C.DirY;
    end
    else
    begin
      AMtvX := C.MaxX;
      AMtvY := C.MaxY;
    end;
  end;
end;

procedure TyAdjustBreakLabelPair(AInverse: Boolean; AAxisRotation: Double;
  var AP0, AP1: TTyAxisLabelPlacement; const ABox0, ABox1: TTyLabelBox;
  const ABareLocal0, ABareLocal1: TTyXYWH);
var
  dir, k, st, ct, cx, cy, mx, my, insidePtSum, qval, uval, uMin, uMax: Double;
  mtvX, mtvY, mstX, d0x, d0y, d1x, d1y: Double;
  axisSt, t0, t1: TTyMat2D;
  r0, r1: TTyXYWH;

  function Parallel(const AT: TTyMat2D; ALen: Double): Boolean;
  begin
    Result := Abs(ALen * AT[1]) < 1e-5;
  end;

begin
  if AInverse then dir := -(AAxisRotation + Pi) else dir := -AAxisRotation;
  { labelIntersect: the rects first (a fast rejection); both boxes axis
    aligned is that test alone, any other goes on to the oriented boxes,
    whose MTV replaces the rects' [F4a] }
  if not TyRectIntersectDir(ABox0.Rect, ABox1.Rect, dir, 0, mtvX, mtvY) then Exit;
  if not (ABox0.AxisAligned and ABox1.AxisAligned) then
    if not TyObbIntersectDir(ABox0, ABox1, dir, 0, mtvX, mtvY) then Exit;
  { rotate the axis back to (1, 0) }
  st := TyJsSin(-AAxisRotation);
  ct := TyJsCos(-AAxisRotation);
  axisSt[0] := 1 * ct + 0 * st;
  axisSt[1] := -1 * st + 0 * ct;
  axisSt[2] := 0 * ct + 1 * st;
  axisSt[3] := -0 * st + ct * 1;
  axisSt[4] := ct * (0 - 0) + st * (0 - 0) + 0;
  axisSt[5] := ct * (0 - 0) - st * (0 - 0) + 0;
  if AP0.HasM then t0 := MulM(axisSt, ABox0.M) else t0 := axisSt;
  if AP1.HasM then t1 := MulM(axisSt, ABox1.M) else t1 := axisSt;
  k := 0.5;
  { parallel to the axis: the widths decide the share, so the gap between
    the two stays nearest the break's middle }
  if Parallel(t0, ABareLocal0.W) or Parallel(t0, ABareLocal0.H) then
  begin
    r0 := RectApply(ABareLocal0, t0);
    r1 := RectApply(ABareLocal1, t1);
    cx := (AP0.X + AP1.X) * 0.5;
    cy := (AP0.Y + AP1.Y) * 0.5;
    mx := axisSt[0] * cx + axisSt[2] * cy + axisSt[4];
    mstX := axisSt[0] * mtvX + axisSt[2] * mtvY + axisSt[4];
    insidePtSum := r0.X + r1.X;
    if mstX >= 0 then insidePtSum := insidePtSum + r0.W
    else insidePtSum := insidePtSum + r1.W;
    qval := (insidePtSum + mstX) / 2 - mx;
    uMin := Min(qval, qval - mstX);
    uMax := Max(qval, qval - mstX);
    if uMax < 0 then uval := uMax
    else if uMin > 0 then uval := uMin
    else uval := 0;
    k := (qval - uval) / mstX;
  end;
  d0x := mtvX * -k;
  d0y := mtvY * -k;
  d1x := mtvX * (1 - k);
  d1y := mtvY * (1 - k);
  AP0.X := AP0.X + d0x;
  AP0.Y := AP0.Y + d0y;
  AP1.X := AP1.X + d1x;
  AP1.Y := AP1.Y + d1y;
  if AP0.HasM then
  begin
    AP0.M[4] := AP0.M[4] + d0x;
    AP0.M[5] := AP0.M[5] + d0y;
  end;
  if AP1.HasM then
  begin
    AP1.M[4] := AP1.M[4] + d1x;
    AP1.M[5] := AP1.M[5] + d1y;
  end;
end;

end.
