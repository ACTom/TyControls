unit tyControls.AdvChart.Stack;
{$mode objfpc}{$H+}
{ Values that accumulate: `stack`, `stackStrategy`, `stackOrder`.

  A PORT OF src/processor/dataStack.ts, read off the ECharts 6.1.0 source.

  TWO GROUPINGS WEAR THE SAME KEY, and confusing them is the obvious mistake.
  AdvChart.BarLayout groups bar COLUMNS by stack id PER BASE AXIS, so that
  series sharing a stack share one width and one offset. This unit groups
  VALUES by the stack string across the WHOLE CHART -- upstream's `dataStack`
  builds one hashmap over `ecModel.eachSeries` keyed on nothing but the string:
  no coordinate system test, no base axis test, no series type test. The only
  rejection is the per-series capability gate. They are different questions
  that happen to be asked with the same word.

  THE LOOP BREAKS AT THE NEAREST ELIGIBLE MEMBER. It does not sum everything
  below. Each series adds the already-accumulated result of the first member
  beneath it that its strategy admits, and stops. Two consequences that a
  reasonable-looking port gets wrong:
    - `sum` in the strategy predicate is always the series' OWN raw value,
      never a running total, because it is assigned once and then broken out of.
    - a negative point in a mixed stack skips every positive member below it and
      lands on the nearest negative one, so positive and negative grow away from
      the baseline as two independent piles.

  WHAT IS NOT HERE. Legend filtering changes stack membership upstream (which
  is why it writes to calculated columns and never to raw data); there is no
  legend yet, so the membership is simply every declared series. Polar bars
  stack by a third mechanism entirely -- a running pixel accumulator, not these
  columns -- and there is no polar coordinate system here either.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface

uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
  tyControls.AdvChart.Series;

{ TTySeriesStack and TTySeriesStackArray live in AdvChart.Types: three units
  need the vocabulary and they cannot all depend on each other. }

{ Accumulate every stack in the chart, writing two calculated columns into each
  participating series' store.

  One entry per series slot, index-parallel to ABindings. MUST RUN AFTER THE
  STORES ARE FILLED AND BEFORE THE AXIS EXTENTS ARE APPLIED: the value axis has
  to span the accumulated totals, not the raw values, or a stacked chart draws
  off the top of its plot with nothing raising. }
function TySolveStacks(AOption: TTyChartOption;
  const ABindings: TTySeriesBindingArray;
  const AStores: array of TTyDataStore): TTySeriesStackArray;

{ ECharts' addSafe: add, then re-round to the decimal precision of the more
  precise operand.

  Exported because it is worth testing on its own. It is not fussiness: 0.1 +
  0.2 is 0.30000000000000004, and the axis' min/max is computed from these
  sums, so the noise escapes into the tick labels and the range. }
function TyAddSafe(A, B: Double): Double;

{ How many decimal places AValue is written with, ECharts' getPrecision. }
function TyDecimalPrecision(AValue: Double): Integer;

implementation

const
  { getPrecision gives up past 15 places, and round() clamps at 20. Both
    numbers are upstream's. }
  cMaxProbedPrecision = 15;
  cMaxFixedPrecision = 20;

  { 10^0 .. 10^15, every one exactly representable in a Double (10^15 is well
    under 2^53), so the probe below divides by an exact power and a value that
    really does have i decimals round-trips exactly. }
  cPow10: array[0..15] of Double = (
    1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000,
    1000000000, 10000000000, 100000000000, 1000000000000,
    10000000000000, 100000000000000, 1000000000000000);

function TyDecimalPrecision(AValue: Double): Integer;
var
  i, dot, ePos, expv: Integer;
  v: Double;
  s: string;
  fs: TFormatSettings;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit(0);
  v := Abs(AValue);
  { Upstream's own guard: below 1e-14 the round-trip probe stops being
    trustworthy, so it falls through to reading the printed form instead. }
  if v > 1e-14 then
    for i := 0 to cMaxProbedPrecision - 1 do
      if Round(AValue * cPow10[i]) / cPow10[i] = AValue then
        Exit(i);

  { The slow, safe route: count the decimals of the shortest text that reads
    back as this number, exponent included -- 3.4e-12 has fourteen. }
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  s := LowerCase(FloatToStr(AValue, fs));
  expv := 0;
  ePos := Pos('e', s);
  if ePos > 0 then
  begin
    expv := StrToIntDef(Copy(s, ePos + 1, Length(s) - ePos), 0);
    s := Copy(s, 1, ePos - 1);
  end;
  Result := 0;
  dot := Pos('.', s);
  if dot > 0 then Result := Length(s) - dot;
  Result := Result - expv;
  if Result < 0 then Result := 0;
end;

function TyAddSafe(A, B: Double): Double;
var
  p: Integer;
  e: Double;
begin
  Result := A + B;
  if IsNan(Result) or IsInfinite(Result) then Exit;
  p := Max(TyDecimalPrecision(A), TyDecimalPrecision(B));
  { Past the clamp there is nothing sensible to round to, and upstream returns
    the raw sum rather than inventing a precision. }
  if (p > cMaxFixedPrecision) or (p > cMaxProbedPrecision) then Exit;
  e := cPow10[p];
  Result := Round(Result * e) / e;
end;

{ The four types that carry `stack` in ECharts 6.1: BarSeries, PictorialBar,
  LineSeries and ScatterSeries all mix in SeriesStackOptionMixin.

  Deliberately NOT the same list as AdvChart.Marks' renderer table, and not a
  second copy of it either: "can these values accumulate" and "can this be
  drawn yet" are different questions. Stacking a scatter today computes two
  columns nobody reads, which is exactly what upstream does and costs one pass
  over the rows. }
function TypeCanStack(const AType: string): Boolean;
begin
  Result := (AType = 'bar') or (AType = 'line')
         or (AType = 'scatter') or (AType = 'pictorialBar');
end;

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

{ Does this lower member's cumulative value qualify to be stacked onto?

  ASum is the TARGET's own raw value -- see the header: the loop assigns it
  once and breaks, so it is never a running total, and the samesign tests are
  about the two values' signs rather than about any accumulation. }
function Admits(const AStrategy: string; ASum, AVal: Double): Boolean;
begin
  if IsNan(AVal) then Exit(False);
  if AStrategy = 'all' then Exit(True);
  if AStrategy = 'positive' then Exit(AVal > 0);
  if AStrategy = 'negative' then Exit(AVal < 0);
  { 'samesign', the default, and anything unrecognised falls here: two piles
    growing away from the baseline. }
  Result := ((ASum >= 0) and (AVal > 0)) or ((ASum <= 0) and (AVal < 0));
end;

type
  TStackMember = record
    Slot: Integer;         { index into ABindings / AStores }
    Store: TTyDataStore;
    ValueCol: Integer;
    ByCol: Integer;        { -1 when stacking by index }
    ResultCol: Integer;
    OverCol: Integer;
    Strategy: string;
  end;
  TStackMembers = array of TStackMember;

function TySolveStacks(AOption: TTyChartOption;
  const ABindings: TTySeriesBindingArray;
  const AStores: array of TTyDataStore): TTySeriesStackArray;
var
  answer: TTySeriesStackArray;
  names: array of string;
  groups: array of TStackMembers;
  i, g, k: Integer;

  function GroupOf(const AName: string): Integer;
  var m: Integer;
  begin
    for m := 0 to High(names) do
      if names[m] = AName then Exit(m);
    Result := Length(names);
    SetLength(names, Result + 1);
    SetLength(groups, Result + 1);
    names[Result] := AName;
  end;

  procedure Accumulate(var AMembers: TStackMembers);
  var
    idx, j, r, srcRaw: Integer;
    own, val, sum, over: Double;
    me: TStackMember;
    below: TStackMember;
    byVal: Double;
  begin
    for idx := 0 to High(AMembers) do
    begin
      me := AMembers[idx];
      for r := 0 to me.Store.RawCount - 1 do
      begin
        own := me.Store.GetByRaw(me.ValueCol, r);
        { A GAP STAYS A GAP IN BOTH COLUMNS. Upstream returns [NaN, NaN] and
          says why: a filled line needs stackedOver to be NaN as well, or the
          belt is drawn across a hole. }
        if IsNan(own) then
        begin
          me.Store.SetCalculated(me.ResultCol, r, NaN);
          me.Store.SetCalculated(me.OverCol, r, NaN);
          Continue;
        end;

        sum := own;
        over := NaN;
        if me.ByCol >= 0 then
          byVal := me.Store.GetByRaw(me.ByCol, r)
        else
          byVal := NaN;

        for j := idx - 1 downto 0 do
        begin
          below := AMembers[j];
          if me.ByCol >= 0 then
          begin
            { STACK BY CATEGORY: find the row in the lower series that carries
              the same category, not the row at the same position. Two series
              may list their categories in different orders, or list different
              subsets of them. }
            if IsNan(byVal) then Continue;
            if below.ByCol < 0 then Continue;
            srcRaw := below.Store.RawIndexOfOrdinal(below.ByCol, Trunc(byVal));
          end
          else
            { STACK BY INDEX, which is all a non-category axis can do: upstream
              says outright that stack-by-value is unsupported there. }
            srcRaw := r;
          if (srcRaw < 0) or (srcRaw >= below.Store.RawCount) then Continue;

          val := below.Store.GetByRaw(below.ResultCol, srcRaw);
          if Admits(me.Strategy, sum, val) then
          begin
            sum := TyAddSafe(sum, val);
            over := val;
            { THE FIRST ONE THAT QUALIFIES, AND STOP. }
            Break;
          end;
        end;

        me.Store.SetCalculated(me.ResultCol, r, sum);
        me.Store.SetCalculated(me.OverCol, r, over);
      end;
      answer[me.Slot].HasBelow := idx > 0;
    end;
  end;

var
  node: TJSONObject;
  stackName, order: string;
  b: TTySeriesBinding;
  st: TTyDataStore;
  mem: TStackMember;
  n, half, a: Integer;
  tmp: TStackMember;
begin
  SetLength(answer, Length(ABindings));
  for i := 0 to High(answer) do
  begin
    answer[i].Stacked := False;
    answer[i].HasBelow := False;
    answer[i].ResultCol := -1;
    answer[i].OverCol := -1;
  end;
  Result := answer;
  if AOption = nil then Exit;

  for i := 0 to High(ABindings) do
  begin
    if i > High(AStores) then Break;
    b := ABindings[i];
    st := AStores[i];
    if (st = nil) or (not b.Resolved) or (not b.HasAxes) then Continue;
    if (b.ValueAxis = nil) or (b.BaseAxis = nil) then Continue;
    if not TypeCanStack(b.SeriesType) then Continue;

    node := SeriesNode(AOption, i);
    { `stack: ''` is not a stack. Upstream notes the compatibility reason for
      spelling that out rather than treating any string as a group. }
    stackName := StringIn(node, 'stack');
    if stackName = '' then Continue;

    { THE CAPABILITY GATE. Upstream refuses a series with no stackable
      dimension; here the value axis IS the stacked dimension, so the question
      is whether it holds numbers that may be added.

      ORDINAL AND TIME ARE BOTH REFUSED, and time is the one that is easy to
      miss: `dimTypeIsNotOrdinalAndTime` gates the pick on
      `type !== 'ordinal' && type !== 'time'`, so a time-valued dimension is no
      more addable than a category is. Adding two dates is not a date. }
    if (b.ValueAxis.AxisType = atCategory)
      or (b.ValueAxis.AxisType = atTime) then Continue;
    mem.ValueCol := st.DimIndexOf(b.ValueAxis.Dim);
    if mem.ValueCol < 0 then Continue;

    mem.Slot := i;
    mem.Store := st;
    { Stack by category when the base axis has categories, by row index
      otherwise. }
    if b.BaseAxis.AxisType = atCategory then
      mem.ByCol := st.DimIndexOf(b.BaseAxis.Dim)
    else
      mem.ByCol := -1;
    if (mem.ByCol >= 0) and (st.DimType(mem.ByCol) <> ddtOrdinal) then
      mem.ByCol := -1;
    mem.Strategy := StringIn(node, 'stackStrategy');
    if mem.Strategy = '' then mem.Strategy := 'samesign';

    { The two calculated columns, in upstream's append order: result first,
      stacked-over second. Named after the slot so two series that ever came to
      share a store could not collide -- upstream postfixes with the series id
      for exactly that reason. }
    mem.ResultCol := st.AddDimension('__ty_stackresult_' + IntToStr(i), ddtFloat);
    mem.OverCol := st.AddDimension('__ty_stackedover_' + IntToStr(i), ddtFloat);

    g := GroupOf(stackName);
    n := Length(groups[g]);
    SetLength(groups[g], n + 1);
    groups[g][n] := mem;

    answer[i].Stacked := True;
    answer[i].ResultCol := mem.ResultCol;
    answer[i].OverCol := mem.OverCol;
  end;

  for g := 0 to High(groups) do
  begin
    if Length(groups[g]) = 0 then Continue;
    { stackOrder IS READ FROM THE FIRST MEMBER ONLY. Setting it on a later
      series of the same stack does nothing at all upstream, and copying that
      is the only way two charts of one option agree. }
    order := StringIn(SeriesNode(AOption, groups[g][0].Slot), 'stackOrder');
    if order = 'seriesDesc' then
    begin
      n := Length(groups[g]);
      half := n div 2;
      for a := 0 to half - 1 do
      begin
        tmp := groups[g][a];
        groups[g][a] := groups[g][n - 1 - a];
        groups[g][n - 1 - a] := tmp;
      end;
    end;
    Accumulate(groups[g]);
  end;

  for k := 0 to High(answer) do
    if answer[k].Stacked and (answer[k].ResultCol < 0) then
      answer[k].Stacked := False;
  Result := answer;
end;

end.
