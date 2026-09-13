unit tyControls.AdvChart.Time;
{$mode objfpc}{$H+}
{ Where a time axis' ticks fall, and what its labels say.

  A time axis was already MAPPED correctly -- epoch milliseconds are numbers and
  a linear scale places them perfectly. What it had no idea about was where a
  tick BELONGS: the linear nicer put them every 200,000,000 ms, and the labels
  read 1709251200000.

  THE WHOLE JOB IS CALENDAR ARITHMETIC. A month is not a number of milliseconds
  -- it is 744, 720, 696 or 743 hours depending on which one and where you are
  standing -- so a tick is stepped by adding ONE to a FIELD of a decoded date
  and encoding it again, never by adding a constant. The same goes for a day
  across a daylight-saving boundary, which is 23 or 25 hours.

  AND THE TICKS COME IN LEVELS. Upstream does not pick one unit and step it: it
  walks from years down through months to days (and on to hours, minutes,
  seconds) collecting a set at each, stops when it has enough, and tags every
  tick with how coarse it is. That is what makes an axis read

      12   13   14   Feb   2   3   4

  rather than as fourteen identical dates. The level is not a major/minor
  distinction -- every one of those is a real tick with a real label.

  PURE. No LCL and no painter: it is handed a range in milliseconds and hands
  back numbers and strings, which is what makes the calendar arithmetic
  testable at all. The month and weekday NAMES come from the one rule the
  whole library uses -- the app's explicit choice, else a loaded translation,
  else the machine's locale -- so a chart and the calendar beside it cannot
  disagree about what to call March. }
interface
uses SysUtils, Math;

type
  { The seven units a tick can be ON, coarsest first. A tick's unit is a
    property of the tick ALONE: how round its own timestamp is. There is no
    comparison with its neighbours anywhere. }
  TTyTimeUnit = (ttuYear, ttuMonth, ttuDay, ttuHour, ttuMinute, ttuSecond,
                 ttuMillisecond);

  { The thirteen names the interval table draws on. Six of them are composite
    -- half a year, a quarter, a week -- and they exist only to make the table
    of approximate sizes finer-grained than the seven real units. They are
    never stepped: the generator maps each back to a primary unit. }
  TTyTimeSpan = (ttsYear, ttsHalfYear, ttsQuarter, ttsMonth, ttsWeek,
                 ttsHalfWeek, ttsDay, ttsHalfDay, ttsQuarterDay, ttsHour,
                 ttsMinute, ttsSecond, ttsMillisecond);

  TTyTimeTick = record
    { Epoch milliseconds. }
    Value: Double;
    { How round this timestamp is, which decides the template its label uses. }
    Unit_: TTyTimeUnit;
    { 0 is the FINEST level and the largest number the coarsest. Assigned after
      empty levels are dropped, so it counts surviving levels and not units. }
    Level: Integer;
    { An extent endpoint that no interval landed on, put back so the axis'
      geometry covers its whole range. Its LABEL is hidden by default -- a
      ragged `07:13` jammed against the first round hour is the most visible
      difference between a careless port and upstream. }
    NotNice: Boolean;
  end;
  TTyTimeTickArray = array of TTyTimeTick;

{ The ticks for [AMinMs, AMaxMs], at roughly ASplitNumber of them.

  AUTC decides whether the calendar arithmetic runs in UTC or in the machine's
  local time. Upstream's `useUTC` is a single option at the root of the tree
  and defaults to FALSE -- server data is UTC but people read their own clock,
  and `'2011-01-02'` has to come back as `2011-01-02` rather than shifted. }
function TyTimeTicks(AMinMs, AMaxMs: Double; ASplitNumber: Integer;
  AUTC: Boolean): TTyTimeTickArray;

{ How round this timestamp is. }
function TyTimeUnitOf(AMs: Double; AUTC: Boolean): TTyTimeUnit;

{ The label for one tick, in the default templates.

  Seven templates, one per unit, and they are SHORT: a day says `3`, a month
  says `Mar` (or 3月, or `mars` -- see the unit header), an hour says `14:00`.
  The axis reads as a sequence because each tick says only as much as it has
  to. }
function TyTimeLabel(const ATick: TTyTimeTick; AUTC: Boolean): string;

// Expand a template. The tokens are upstream's, brace-delimited at both ends:
//   {yyyy} {yy} {Q} {MMMM} {MMM} {MM} {M} {dd} {d} {eeee} {ee} {e}
//   {HH} {H} {hh} {h} {mm} {m} {ss} {s} {SSS} {S} {a} {A}
// Padding follows upstream exactly: the four-digit year is NOT padded, the
// millisecond pads to three, everything else that pads pads to two.
//
// Line comments rather than a brace block, here and wherever else a token is
// quoted: FPC nests brace comments, so one of these inside one would swallow
// the rest of the unit.
function TyFormatTime(AMs: Double; const ATemplate: string;
  AUTC: Boolean): string;

implementation

uses tyControls.AdvChart.Data, tyControls.StrConsts;

const
  cOneSecond = 1000.0;
  cOneMinute = 60.0 * cOneSecond;
  cOneHour = 60.0 * cOneMinute;
  cOneDay = 24.0 * cOneHour;
  { UPSTREAM'S YEAR IS 365 DAYS FLAT. It is a sizing constant and never a step,
    so the leap year it ignores costs nothing. }
  cOneYear = 365.0 * cOneDay;

type
  TTyTimeInterval = record
    Span: TTyTimeSpan;
    Ms: Double;
  end;

const
  { UPSTREAM'S `scaleIntervals`, ascending. TWELVE rows -- there is no
    millisecond row, which is why a millisecond can never be the bottom unit.

    The day row is 1.2 DAYS and not one, and the month row is 31 days while the
    step chooser below divides by 30. Both look like slips and both are load
    bearing: they are the thresholds that decide when an axis stops counting
    days and starts counting months. }
  cIntervals: array[0..11] of TTyTimeInterval = (
    (Span: ttsSecond;     Ms: cOneSecond),
    (Span: ttsMinute;     Ms: cOneMinute),
    (Span: ttsHour;       Ms: cOneHour),
    (Span: ttsQuarterDay; Ms: 6.0 * cOneHour),
    (Span: ttsHalfDay;    Ms: 12.0 * cOneHour),
    (Span: ttsDay;        Ms: 1.2 * cOneDay),
    (Span: ttsHalfWeek;   Ms: 3.5 * cOneDay),
    (Span: ttsWeek;       Ms: 7.0 * cOneDay),
    (Span: ttsMonth;      Ms: 31.0 * cOneDay),
    (Span: ttsQuarter;    Ms: 95.0 * cOneDay),
    (Span: ttsHalfYear;   Ms: cOneYear / 2),
    (Span: ttsYear;       Ms: cOneYear));

  cSafeLimit = 3000;

  { THE WALL CLOCK IS COUNTED IN WHOLE MILLISECONDS, on INTEGER constants,
    and every product taken below is taken in Int64.

    Not a preference. FPC evaluates an integer times an untyped REAL constant
    in SINGLE -- `days * cOneDay` is a Single expression however wide the
    variable it lands in -- and a 24-bit mantissa cannot hold 1,709,251,200,000
    to the millisecond. The first version of this unit was out by 31,744 ms,
    which is not a rounding error anybody spots as one: it made every label
    read `00:00:-31 -744` and every 'are these in the same month' test lie. }
  cMsSecond = 1000;
  cMsMinute = 60 * cMsSecond;
  cMsHour = 60 * cMsMinute;
  cMsDay = 24 * cMsHour;

  { 1970-01-01 as a TDateTime -- TYPED, so that adding a day count to it is a
    Double sum and not a Single one -- and the day numbers either side of it
    that EncodeDate will still accept.

    THE LOW BOUND IS YEAR ONE, not TDateTime zero. TDateTime counts from the
    30th of December 1899 and goes NEGATIVE before it; clamping at zero looks
    like a floor and is really a wall in the middle of the range, which turns
    every date before 1900 into the 30th of December 1899. }
  cEpochDT: Double = 25569.0;
  cMinDay = -693593 - 25569;
  cMaxDay = 2958465 - 25569;

{ ==================== decoding and encoding ==================== }

type
  TTyTimeParts = record
    Year, Month, Day, Hour, Minute, Second, Milli: Integer;
  end;

{ THE WALL CLOCK, as milliseconds since the epoch.

  Everything below works on this and not on the instant, which is what lets the
  whole unit be integer arithmetic: a wall clock has no zone, so a day on it is
  always 86,400,000 and a month is always a whole number of days. The zone is
  asked about exactly twice -- here, and in the inverse -- and never inside a
  loop, which also keeps FPC 3.2.2's offset-for-NOW approximation from
  compounding: it is applied once per value, not once per step. }
function WallOf(AMs: Double; AUTC: Boolean): Int64;
begin
  if AUTC then Exit(Round(AMs));
  { Shift to local, then read the shifted stamp AS IF it were UTC. }
  Result := Round(TyDateTimeToMs(TyMsToDateTime(AMs, False), True));
end;

function InstantOf(AWall: Int64; AUTC: Boolean): Double;
begin
  if AUTC then Exit(AWall);
  Result := Round(TyDateTimeToMs(TyMsToDateTime(AWall, True), False));
end;

{ Epoch milliseconds to civil fields, in the chosen zone.

  EVERYTHING IS DONE ON THE FIELDS and converted back once at the end, by
  division rather than through TDateTime: a TDateTime is a count of DAYS, and a
  millisecond is the 86-millionth part of one, so a stamp that goes out through
  a day fraction and comes back can land on 13:59:59.999. }
function PartsOf(AMs: Double; AUTC: Boolean): TTyTimeParts;
var w, rem, days: Int64; y, mo, dy: Word;
begin
  w := WallOf(AMs, AUTC);
  days := w div cMsDay;
  rem := w - days * cMsDay;
  { FLOORED, not truncated. Before 1970 the stamp is negative and `div`
    rounds towards zero, which files the last second of 1969 under 1970 and
    gives it a negative time of day. }
  if rem < 0 then
  begin
    Dec(days);
    Inc(rem, cMsDay);
  end;
  { Clamped because EncodeDate/DecodeDate raise outside year 1..9999, and a
    range that wide is a bad extent rather than a chart anyone is drawing. }
  if days < cMinDay then days := cMinDay
  else if days > cMaxDay then days := cMaxDay;
  DecodeDate(cEpochDT + days, y, mo, dy);
  Result.Year := y;
  Result.Month := mo;
  Result.Day := dy;
  Result.Hour := rem div cMsHour;
  rem := rem mod cMsHour;
  Result.Minute := rem div cMsMinute;
  rem := rem mod cMsMinute;
  Result.Second := rem div cMsSecond;
  Result.Milli := rem mod cMsSecond;
end;

{ Civil fields back to epoch milliseconds, NORMALISING out-of-range ones.

  A month of 13 is January of the next year and a day of 36 is the fifth of the
  next month. That rollover is not tolerance, it is the mechanism: the tick
  loop adds to one field and lets it carry, and the day level RELIES on the
  carry to walk out of a month and terminate. FPC's IncMonth clamps instead --
  the 31st of January plus a month is the 28th of February, not the 3rd of
  March -- and a clamping step never leaves the month it started in, so the
  sixteen-day ladder would spin until the safe limit. }
function MsOf(const AParts: TTyTimeParts; AUTC: Boolean): Double;
var
  p: TTyTimeParts;
  idx, days: Integer;
begin
  p := AParts;
  { MONTHS CARRY FIRST, through a running month number, so that the day can
    then be added as a plain count of days and carry by itself. }
  idx := p.Year * 12 + (p.Month - 1);
  p.Year := idx div 12;
  p.Month := idx - p.Year * 12 + 1;
  { NO BORROW FOR A NEGATIVE MONTH, deliberately. `div` truncates towards
    zero, so a running month number below zero would leave Month at or below
    nought -- but that needs a year of nought or less, and the clamp below
    turns every one of those into 1 January year 1 anyway. A borrow here was
    written first and mutation-tested as equivalent: it cannot change an
    answer the clamp does not already decide. }
  if p.Year < 1 then begin p.Year := 1; p.Month := 1; end
  else if p.Year > 9999 then begin p.Year := 9999; p.Month := 12; end;
  days := Round(EncodeDate(Word(p.Year), Word(p.Month), 1) - cEpochDT);
  Result := InstantOf(Int64(days + p.Day - 1) * cMsDay
                      + Int64(p.Hour) * cMsHour
                      + Int64(p.Minute) * cMsMinute
                      + Int64(p.Second) * cMsSecond
                      + p.Milli, AUTC);
end;

{ Truncate to the start of AUnit -- a CASCADE, because upstream's switch falls
  through: rounding to a year zeroes the month AND the date AND the time. }
function FloorTo(AMs: Double; AUnit: TTyTimeUnit; AUTC: Boolean): Double;
var p: TTyTimeParts;
begin
  if AUnit = ttuMillisecond then Exit(AMs);
  p := PartsOf(AMs, AUTC);
  if AUnit <= ttuSecond then p.Milli := 0;
  if AUnit <= ttuMinute then p.Second := 0;
  if AUnit <= ttuHour then p.Minute := 0;
  if AUnit <= ttuDay then p.Hour := 0;
  { The DATE floor is one, not nought -- a month starts on its first day. }
  if AUnit <= ttuMonth then p.Day := 1;
  if AUnit <= ttuYear then p.Month := 1;
  Result := MsOf(p, AUTC);
end;

{ Add ACount to AUnit's field and re-encode. }
function StepBy(AMs: Double; AUnit: TTyTimeUnit; ACount: Integer;
  AUTC: Boolean): Double;
var p: TTyTimeParts;
begin
  p := PartsOf(AMs, AUTC);
  case AUnit of
    ttuYear: Inc(p.Year, ACount);
    ttuMonth: Inc(p.Month, ACount);
    ttuDay: Inc(p.Day, ACount);
    ttuHour: Inc(p.Hour, ACount);
    ttuMinute: Inc(p.Minute, ACount);
    ttuSecond: Inc(p.Second, ACount);
    ttuMillisecond: Inc(p.Milli, ACount);
  end;
  Result := MsOf(p, AUTC);
end;

function TyTimeUnitOf(AMs: Double; AUTC: Boolean): TTyTimeUnit;
var p: TTyTimeParts;
begin
  p := PartsOf(AMs, AUTC);
  { THE FINEST FIELD THAT IS NOT AT ITS FLOOR NAMES THE UNIT -- and the floor
    is nought for the time fields but ONE for the day of the month and for the
    month. Read the other way round ("the coarsest field at its floor") a
    midnight becomes an `hour` and every day label turns into `00:00`. }
  if p.Milli <> 0 then Exit(ttuMillisecond);
  if p.Second <> 0 then Exit(ttuSecond);
  if p.Minute <> 0 then Exit(ttuMinute);
  if p.Hour <> 0 then Exit(ttuHour);
  if p.Day <> 1 then Exit(ttuDay);
  if p.Month <> 1 then Exit(ttuMonth);
  Result := ttuYear;
end;

{ ==================== choosing a unit and a step ==================== }

function PrimaryOf(ASpan: TTyTimeSpan): TTyTimeUnit;
begin
  case ASpan of
    ttsYear: Result := ttuYear;
    ttsHalfYear, ttsQuarter, ttsMonth: Result := ttuMonth;
    ttsWeek, ttsHalfWeek, ttsDay: Result := ttuDay;
    ttsHalfDay, ttsQuarterDay, ttsHour: Result := ttuHour;
    ttsMinute: Result := ttuMinute;
    ttsSecond: Result := ttuSecond;
  else
    Result := ttuMillisecond;
  end;
end;

{ Upstream's `nice(v, true)`: the set 1, 2, 3, 5, 10 times a power of ten. }
function NiceRound(AValue: Double): Double;
var exp_, f: Double;
begin
  if AValue <= 0 then Exit(1);
  exp_ := Floor(Log10(AValue));
  f := AValue / Power(10, exp_);
  if f < 1.5 then f := 1
  else if f < 2.5 then f := 2
  else if f < 4 then f := 3
  else if f < 7 then f := 5
  else f := 10;
  Result := f * Power(10, exp_);
end;

{ How many of AUnit one step spans, from the SAME unmodified approximate
  interval every level is given -- a level is never a subdivision of its
  parent's step. Every comparison is strictly greater. }
function StepFor(AUnit: TTyTimeUnit; AApprox: Double): Integer;
var v: Double;
begin
  case AUnit of
    ttuYear:
      { NO NICE SNAPPING AT ALL: a seven-year or thirteen-year step is what
        upstream draws, and rounding it to five or ten would be a kindness
        nobody asked for. }
      Exit(Max(1, Floor(AApprox / cOneDay / 365 + 0.5)));
    ttuMonth:
      begin
        { THIRTY DAYS HERE and thirty-one in the table above. }
        v := AApprox / (30.0 * cOneDay);
        if v > 6 then Exit(6);
        if v > 3 then Exit(3);
        if v > 2 then Exit(2);
        Exit(1);
      end;
    ttuDay:
      begin
        v := AApprox / cOneDay;
        if v > 16 then Exit(16);
        if v > 7.5 then Exit(7);
        if v > 3.5 then Exit(4);
        if v > 1.5 then Exit(2);
        Exit(1);
      end;
    ttuHour:
      begin
        v := AApprox / cOneHour;
        if v > 12 then Exit(12);
        if v > 6 then Exit(6);
        if v > 3.5 then Exit(4);
        if v > 2 then Exit(2);
        Exit(1);
      end;
    ttuMinute, ttuSecond:
      begin
        if AUnit = ttuMinute then v := AApprox / cOneMinute
        else v := AApprox / cOneSecond;
        if v > 30 then Exit(30);
        if v > 20 then Exit(20);
        if v > 15 then Exit(15);
        if v > 10 then Exit(10);
        if v > 5 then Exit(5);
        if v > 2 then Exit(2);
        Exit(1);
      end;
  else
    Exit(Max(1, Trunc(NiceRound(AApprox))));
  end;
end;

{ The bottom unit for this approximate interval: a lower-bound search over the
  table, then ONE ROW FINER. The step back is deliberate -- it is what keeps an
  axis from showing four ticks when it was asked for ten. }
function BottomSpanFor(AApprox: Double): TTyTimeSpan;
var i, idx: Integer;
begin
  idx := High(cIntervals);
  for i := 0 to High(cIntervals) do
    if cIntervals[i].Ms >= AApprox then
    begin
      idx := i;
      Break;
    end;
  Result := cIntervals[Max(0, idx - 1)].Span;
end;

{ ==================== generating the ticks ==================== }

type
  TTyMsArray = array of Double;

procedure SortMs(var A: TTyMsArray);
var i, j: Integer; t: Double;
begin
  for i := 1 to High(A) do
  begin
    t := A[i];
    j := i - 1;
    while (j >= 0) and (A[j] > t) do
    begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
end;

procedure SortTicks(var A: TTyTimeTickArray);
var i, j: Integer; t: TTyTimeTick;
begin
  for i := 1 to High(A) do
  begin
    t := A[i];
    j := i - 1;
    while (j >= 0) and (A[j].Value > t.Value) do
    begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
end;

function TyTimeTicks(AMinMs, AMaxMs: Double; ASplitNumber: Integer;
  AUTC: Boolean): TTyTimeTickArray;
var
  lo, hi, approx, target: Double;
  bottomSpan: TTyTimeSpan;
  bottomUnit: TTyTimeUnit;
  bottomStops: Boolean;
  levels, emitted: array of TTyMsArray;
  parent, cur, seen: TTyMsArray;
  u: TTyTimeUnit;
  iter, tickCount, lastCount, i, k, n, step, maxLevel: Integer;
  dup: Boolean;

  { One run of ticks, from AFrom forward until it reaches ATo. }
  procedure AddSpan(AFrom, ATo: Double; AUnit: TTyTimeUnit; AStep: Integer;
    var AOut: TTyMsArray);
  var t: Double;
  begin
    t := AFrom;
    while (t < ATo) and (t <= hi) do
    begin
      SetLength(AOut, Length(AOut) + 1);
      AOut[High(AOut)] := t;
      Inc(iter);
      { A FAIL-SAFE AND NOT A LIMIT. Nothing here should reach three thousand
        ticks; a step that fails to advance would otherwise spin forever, and
        the calendar has more than one way to produce one. }
      if iter > cSafeLimit then Break;
      t := StepBy(t, AUnit, AStep, AUTC);
    end;
    { THE CLOSING BOUNDARY, pushed whether or not it is in range: the next
      finer level restarts at each of these, so it needs a span to end on. Out
      of range it is dropped later, in range it is a real tick. }
    SetLength(AOut, Length(AOut) + 1);
    AOut[High(AOut)] := t;
  end;

  { Where a level starts counting: the beginning of the NEXT COARSER unit. Days
    count from the first of the month and hours from midnight, which is what
    stops an axis reading 3rd, 10th, 17th, 24th, 31st, 7th, 14th across a month
    boundary. }
  function FirstOf(AMs: Double; AUnit: TTyTimeUnit): Double;
  begin
    if AUnit = ttuYear then Result := FloorTo(AMs, ttuYear, AUTC)
    else Result := FloorTo(AMs, Pred(AUnit), AUTC);
  end;

begin
  Result := nil;
  lo := Min(AMinMs, AMaxMs);
  hi := Max(AMinMs, AMaxMs);
  if IsNan(lo) or IsNan(hi) or IsInfinite(lo) or IsInfinite(hi) then Exit;
  { A degenerate range is opened out by a day either side -- a flat 86,400,000
    and not a calendar day, so it needs no zone. Without it the approximate
    interval is nought and there is no interval to pick. }
  if hi - lo <= 0 then
  begin
    lo := lo - cOneDay;
    hi := hi + cOneDay;
  end;
  if ASplitNumber < 1 then ASplitNumber := 6;
  approx := (hi - lo) / ASplitNumber;
  if approx <= 0 then Exit;
  target := ASplitNumber;

  bottomSpan := BottomSpanFor(approx);
  bottomUnit := PrimaryOf(bottomSpan);
  { THE BOTTOM UNIT ONLY STOPS THE WALK WHEN IT NAMES A REAL UNIT. Upstream
    compares the chosen interval's name against the unit it is about to draw,
    and the composite names -- half-week, quarter-day, half-year -- never match
    one, so choosing `half-week` does not stop the walk at days: it runs on
    until the tick count is enough. That reads like a slip and is not: those
    rows exist to make the SIZE table finer, and their sizes sit between two
    real units, so neither of them is the right place to stop. }
  bottomStops := bottomSpan in [ttsYear, ttsMonth, ttsDay, ttsHour, ttsMinute,
                                ttsSecond, ttsMillisecond];

  iter := 0;
  tickCount := 0;
  levels := nil;
  parent := nil;

  for u := ttuYear to ttuMillisecond do
  begin
    { A LEVEL WHOSE WHOLE EXTENT IS ONE UNIT CONTRIBUTES NOTHING -- a chart of
      three days in March sits inside one year and one month, and neither is
      worth a tick. The level is skipped without becoming anyone's parent, so
      the next unit down still gets the whole extent to work with. }
    if FloorTo(lo, u, AUTC) = FloorTo(hi, u, AUTC) then Continue;
    step := StepFor(u, approx);
    cur := nil;
    if Length(levels) = 0 then
      AddSpan(FirstOf(lo, u), hi, u, step, cur)
    else
      { EVERY LATER LEVEL RESTARTS AT EACH OF ITS PARENT'S BOUNDARIES, which is
        what puts ticks on the 1st, 8th, 15th and 22nd of every month rather
        than on a uniform seven-day cadence that drifts through the year. }
      for i := 0 to High(parent) - 1 do
      begin
        if parent[i] = parent[i + 1] then Continue;
        { A span with no overlap at all is skipped -- without this, a level
          that snapped back to January would walk the whole year one day at a
          time to reach a three-day extent in December. }
        if (parent[i + 1] < lo) or (parent[i] > hi) then Continue;
        AddSpan(FirstOf(parent[i], u), parent[i + 1], u, step, cur);
      end;
    if Length(cur) = 0 then Continue;

    SortMs(cur);
    { The count carried forward is the one from BEFORE this level. }
    lastCount := tickCount;
    n := 0;
    for i := 0 to High(cur) do
    begin
      if (i > 0) and (cur[i] = cur[i - 1]) then Continue;
      cur[n] := cur[i];
      Inc(n);
      if (cur[i] >= lo) and (cur[i] <= hi) then Inc(tickCount);
    end;
    SetLength(cur, n);

    { TOO MANY NOW AND ENOUGH ALREADY: this level is DISCARDED rather than
      kept. It is the rule that makes a seventy-year chart show years and not
      eight hundred months. }
    if (tickCount > target * 1.5) and (lastCount > target / 1.5) then Break;

    SetLength(levels, Length(levels) + 1);
    levels[High(levels)] := cur;
    parent := cur;
    if (tickCount > target) or (bottomStops and (u = bottomUnit)) then Break;
  end;

  { Keep what is inside the extent, and drop levels left with nothing. }
  emitted := nil;
  for i := 0 to High(levels) do
  begin
    cur := nil;
    for k := 0 to High(levels[i]) do
      if (levels[i][k] >= lo) and (levels[i][k] <= hi) then
      begin
        SetLength(cur, Length(cur) + 1);
        cur[High(cur)] := levels[i][k];
      end;
    if Length(cur) = 0 then Continue;
    SetLength(emitted, Length(emitted) + 1);
    emitted[High(emitted)] := cur;
  end;

  { LEVEL NUMBERING RUNS BACKWARDS: the coarsest surviving level gets the
    highest number and the finest gets nought. It counts SURVIVING LEVELS and
    not units, so on a chart whose year level was dropped the months are the
    top level and carry the emphasis. }
  maxLevel := Length(emitted) - 1;
  seen := nil;
  for i := 0 to High(emitted) do
    for k := 0 to High(emitted[i]) do
    begin
      { COARSE WINS A COLLISION. Every level restarts at its parent's
        boundaries, so the 1st of a month is produced by the month level AND by
        the day level; the copy that survives has to be the coarser one, or the
        month marker loses the level that sets it apart. }
      dup := False;
      for n := 0 to High(seen) do
        if seen[n] = emitted[i][k] then
        begin
          dup := True;
          Break;
        end;
      if dup then Continue;
      SetLength(seen, Length(seen) + 1);
      seen[High(seen)] := emitted[i][k];

      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Value := emitted[i][k];
      Result[High(Result)].Unit_ := TyTimeUnitOf(emitted[i][k], AUTC);
      Result[High(Result)].Level := maxLevel - i;
      Result[High(Result)].NotNice := False;
    end;

  SortTicks(Result);

  { THE TWO ENDS, when no interval landed on them. A time axis' extent is never
    rounded outwards -- data from 07:13 to 19:48 keeps both -- so without these
    the first and last ticks would sit inside the axis' own range and the grid
    would stop short of the data. Their LABELS are hidden by default: a ragged
    `07:13` jammed against the first round hour is the most visible difference
    between a careless port and upstream. }
  if (Length(Result) = 0) or (Result[0].Value > lo) then
  begin
    SetLength(Result, Length(Result) + 1);
    for i := High(Result) downto 1 do Result[i] := Result[i - 1];
    Result[0].Value := lo;
    Result[0].Unit_ := TyTimeUnitOf(lo, AUTC);
    Result[0].Level := 0;
    Result[0].NotNice := True;
  end;
  if Result[High(Result)].Value < hi then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Value := hi;
    Result[High(Result)].Unit_ := TyTimeUnitOf(hi, AUTC);
    Result[High(Result)].Level := 0;
    Result[High(Result)].NotNice := True;
  end;
end;

{ ==================== labels ==================== }

{ The floored day number, which is the day-of-week's whole input. }
function DayNumberOf(AMs: Double; AUTC: Boolean): Int64;
var w: Int64;
begin
  w := WallOf(AMs, AUTC);
  Result := w div cMsDay;
  if w - Result * cMsDay < 0 then Dec(Result);
  if Result < cMinDay then Result := cMinDay
  else if Result > cMaxDay then Result := cMaxDay;
end;

{ THE NAMES COME FROM THE ONE PLACE THE WHOLE LIBRARY GETS THEM, which is a
  three-tier rule and not a table: the app's explicit choice, else a loaded
  translation, else the machine's own locale. A chart on a French machine
  therefore says `mars` with nothing configured, and a chart in an app
  translated to Chinese says 3月 while the calendar beside it says 3月 too.

  Read on every call rather than cached, because a catalogue loads from the
  program body long after this unit initialised. }
function MonthFull(AMonth: Integer): string;
begin
  Result := TyDateTimeNames.LongMonthNames[AMonth];
end;

function MonthAbbr(AMonth: Integer): string;
begin
  Result := TyDateTimeNames.ShortMonthNames[AMonth];
end;

{ AIndex is JavaScript's day number, nought for Sunday; the RTL's arrays are
  one-based from Sunday. }
function DowFull(AIndex: Integer): string;
begin
  Result := TyDateTimeNames.LongDayNames[AIndex + 1];
end;

function DowAbbr(AIndex: Integer): string;
begin
  Result := TyDateTimeNames.ShortDayNames[AIndex + 1];
end;

{ Left zero-fill that NEVER truncates -- upstream's pad prepends at most four
  zeroes and returns a longer string untouched, so a five-digit year comes out
  whole rather than clipped. }
function Pad(const AText: string; ALen: Integer): string;
begin
  Result := AText;
  while Length(Result) < ALen do Result := '0' + Result;
end;

function TyFormatTime(AMs: Double; const ATemplate: string;
  AUTC: Boolean): string;
var
  p: TTyTimeParts;
  i, j: Integer;
  tok, rep: string;
  dow, h12: Integer;
begin
  Result := '';
  if IsNan(AMs) or IsInfinite(AMs) then Exit(ATemplate);
  p := PartsOf(AMs, AUTC);
  { Sunday is NOUGHT, which is JS' reckoning and one less than the RTL's. }
  dow := (DayOfWeek(cEpochDT + DayNumberOf(AMs, AUTC)) - 1) mod 7;
  h12 := (p.Hour - 1) mod 12 + 1;

  i := 1;
  { ONE LEFT-TO-RIGHT SCAN, not a chain of replacements: a chain re-reads what
    it has already written, so a month name containing a brace would be
    rewritten by a later token. }
  while i <= Length(ATemplate) do
  begin
    if ATemplate[i] <> '{' then
    begin
      Result := Result + ATemplate[i];
      Inc(i);
      Continue;
    end;
    j := i + 1;
    while (j <= Length(ATemplate)) and (ATemplate[j] <> '}') do Inc(j);
    if j > Length(ATemplate) then
    begin
      Result := Result + Copy(ATemplate, i, MaxInt);
      Break;
    end;
    tok := Copy(ATemplate, i + 1, j - i - 1);
    rep := '';
    if tok = 'yyyy' then rep := IntToStr(p.Year)
    else if tok = 'yy' then rep := Pad(IntToStr(p.Year mod 100), 2)
    else if tok = 'Q' then rep := IntToStr((p.Month - 1) div 3 + 1)
    else if tok = 'MMMM' then rep := MonthFull(p.Month)
    else if tok = 'MMM' then rep := MonthAbbr(p.Month)
    else if tok = 'MM' then rep := Pad(IntToStr(p.Month), 2)
    else if tok = 'M' then rep := IntToStr(p.Month)
    else if tok = 'dd' then rep := Pad(IntToStr(p.Day), 2)
    else if tok = 'd' then rep := IntToStr(p.Day)
    else if tok = 'eeee' then rep := DowFull(dow)
    else if tok = 'ee' then rep := DowAbbr(dow)
    else if tok = 'e' then rep := IntToStr(dow)
    else if tok = 'HH' then rep := Pad(IntToStr(p.Hour), 2)
    else if tok = 'H' then rep := IntToStr(p.Hour)
    else if tok = 'hh' then rep := Pad(IntToStr(h12), 2)
    else if tok = 'h' then rep := IntToStr(h12)
    else if tok = 'mm' then rep := Pad(IntToStr(p.Minute), 2)
    else if tok = 'm' then rep := IntToStr(p.Minute)
    else if tok = 'ss' then rep := Pad(IntToStr(p.Second), 2)
    else if tok = 's' then rep := IntToStr(p.Second)
    else if tok = 'SSS' then rep := Pad(IntToStr(p.Milli), 3)
    else if tok = 'S' then rep := IntToStr(p.Milli)
    else if tok = 'a' then begin if p.Hour >= 12 then rep := 'pm' else rep := 'am'; end
    else if tok = 'A' then begin if p.Hour >= 12 then rep := 'PM' else rep := 'AM'; end
    else
      { Not a token this understands -- left alone, braces and all, rather than
        swallowed. }
      rep := '{' + tok + '}';
    Result := Result + rep;
    i := j + 1;
  end;
end;

function TyTimeLabel(const ATick: TTyTimeTick; AUTC: Boolean): string;
const
  { UPSTREAM'S SHORT SEEDS, one per unit. They are short on purpose: an axis
    reads as a sequence because each tick says only what its neighbours do not.
    Hour and minute share a template, which is upstream's and not a slip. }
  cSeed: array[TTyTimeUnit] of string = (
    '{yyyy}',              // year
    '{MMM}',               // month
    '{d}',                 // day
    '{HH}:{mm}',           // hour
    '{HH}:{mm}',           // minute
    '{HH}:{mm}:{ss}',      // second
    '{HH}:{mm}:{ss} {SSS}' // millisecond
  );
begin
  Result := TyFormatTime(ATick.Value, cSeed[ATick.Unit_], AUTC);
end;

end.
