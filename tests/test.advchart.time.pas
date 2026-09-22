unit test.advchart.time;
{$mode objfpc}{$H+}
{ What a time axis puts its ticks on, and what it writes under them.

  Two halves, and they fail in completely different ways.

  THE CALENDAR HALF is arithmetic, and the arithmetic is not the arithmetic of
  numbers: a month is 28, 29, 30 or 31 days, a day across a daylight-saving
  boundary is 23 or 25 hours, and stepping either by adding a constant is wrong
  in a way that shows up once a year in one time zone. The tests below step
  across a month end, across a leap day, and across the epoch, because those
  are the three places a floating-point shortcut survives ordinary use.

  THE LEVEL HALF is about what an axis READS like. Upstream does not pick one
  unit and step it -- it collects a set at each unit from years down and tags
  every tick with how coarse it is -- and the result is an axis that says

      12   13   14   Feb   2   3   4

  where `Feb` is the same kind of thing as `13`, only coarser and in bold. Get
  the levels wrong and you get fourteen identical dates, which still passes any
  test that only asks where the ticks are. So these ask what the ticks SAY. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Time, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Layout, tyControls.AdvanceChart, tyControls.StrConsts,
     test.advancechart;
type
  { The calendar and the formatter, with no chart anywhere near them. }
  TAdvChartTimeTest = class(TTestCase)
  private
    FSavedSource: TTyDateTimeNameSource;
    { PINNED TO THE RESOURCESTRINGS for the duration. A chart takes its month
      names from the same three-tier rule the calendar does, whose default
      tier is the MACHINE's locale -- so an unpinned `Mar` assertion passes in
      London and fails in Shanghai, where it reads 3月. Pinning names the one
      tier whose answer is compiled in. }
    procedure SetUp; override;
    procedure TearDown; override;
    { A UTC instant from its civil fields. }
    function Ms(AY, AMo, AD: Integer; AH: Integer = 0; AMi: Integer = 0;
      ASec: Integer = 0; AMilli: Integer = 0): Double;
    { Every tick's label for a span, joined with '|'. One string is what makes
      a level test readable: the whole axis in one assertion. }
    function Reading(AFrom, ATo: Double; ASplit: Integer = 6): string;
    { The same, with each tick's level appended -- `Mar@1|06:00@0`. }
    function Levels(AFrom, ATo: Double; ASplit: Integer = 6): string;
    function Ticks(AFrom, ATo: Double; ASplit: Integer = 6): TTyTimeTickArray;
    { fpcunit has no enum overload and would bind the pair to TClass. Naming
      them also makes a failure say `expected day but was hour` rather than
      `expected 2 but was 3`. }
    procedure AssertUnit(AExpected, AActual: TTyTimeUnit);
  published
    { ---- the calendar ---- }
    procedure TestAMonthIsNotAFixedNumberOfMilliseconds;
    procedure TestSteppingAMonthOverflowsRatherThanClamps;
    procedure TestSteppingADayCarriesOutOfItsMonth;
    procedure TestAMonthFloorsToTheFirstNotTheZeroth;
    procedure TestTheFinestFieldNotAtItsFloorNamesTheUnit;
    procedure TestMidnightIsADayAndNotAnHour;
    procedure TestTheDayFloorWorksBeforeTheEpoch;
    procedure TestALeapDayIsADayLikeAnyOther;
    { ---- the formatter ---- }
    procedure TestEveryTokenTheDefaultTemplatesUse;
    procedure TestTheFourDigitYearIsNotPadded;
    procedure TestAnUnknownTokenIsLeftAlone;
    procedure TestLiteralTextBetweenTokensSurvives;
    procedure TestTheWeekdayStartsAtSundayLikeJavaScript;
    { ---- the ticks ---- }
    procedure TestTwoDaysReadAsDaysAndSixHourMarks;
    procedure TestTheCoarsestLevelHasTheHighestNumber;
    procedure TestOneSurvivingLevelIsAllLevelZero;
    procedure TestTheRaggedEndsComeBackAsNotNice;
    procedure TestAnEndAnIntervalLandsOnIsNotAddedTwice;
    procedure TestDaysCountFromTheFirstOfTheMonth;
    procedure TestTheHourStepClimbsItsLadder;
    procedure TestTheDayStepClimbsItsLadder;
    procedure TestTheMonthStepClimbsItsLadder;
    procedure TestTheMinuteAndSecondStepClimbsItsLadder;
    procedure TestAYearStepIsNeverSnappedToANiceNumber;
    procedure TestTheBottomUnitIsOneRowFinerThanTheSizeSaid;
    procedure TestSeventyYearsShowsYearsAndNotMonths;
    procedure TestAYearLevelCountsFromJanuaryAndNotFromTheData;
    procedure TestACoarseTickBeatsAFineOneOnTheSameInstant;
    procedure TestADegenerateExtentOpensOutByADay;
    procedure TestAskingForMoreTicksGivesAFinerUnit;
    procedure TestAHugeSpanTerminates;
    procedure TestAnInvertedRangeIsReadTheRightWayRound;
  end;

  { The same scale, reached through an option tree. }
  { Wider for a heavier weight, which is the only thing this measurer models
    -- and the only thing the rule under test depends on. A real font is no
    use here: the difference between 400 and 700 is a couple of pixels that
    would be a different couple of pixels on GTK. }
  TWeightedMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  { The measure-what-you-draw rule, asked of the layout unit directly.

    Through a CHART it is invisible: a bottom axis reserves label HEIGHT,
    which bold does not change, and the widest label on a time axis is
    usually one of the plain ones. It shows on a vertical axis whose widest
    label is an emphasised one -- a year marker among month names. }
  TAdvChartTimeMeasureTest = class(TTestCase)
  private
    function YearAmongMonths(AEmphasisWeight: Integer): TTyAxisLayoutSpec;
  published
    procedure TestAnEmphasisedLabelIsMeasuredInItsOwnWeight;
  end;

  TAdvChartTimeAxisTest = class(TTestCase)
  private
    FSavedSource: TTyDateTimeNameSource;
    FSavedFmt: TFormatSettings;
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string;
                   AW: Integer = 500; AH: Integer = 300; APPI: Integer = 96);
    function XAxis: TTyAxis;
    function XSpec: PTyAxisLayoutSpec;
    function YAxis: TTyAxis;
    { Every label the x axis would draw, joined with '|'; hidden ones skipped. }
    function ShownLabels: string;
    { The first label the x axis draws. }
    function FirstLabel: string;
  published
    procedure TestATimeAxisGetsATimeScale;
    procedure TestATimeAxisWorksDownTheSideToo;
    procedure TestATimeAxisDoesNotStretchBackToNineteenSeventy;
    procedure TestATimeAxisIsNotNiciedToRoundNumbers;
    procedure TestItsLabelsAreDatesAndNotNumbers;
    procedure TestTheSplitNumberDefaultsToSixNotFive;
    procedure TestATimeAxisDrawsNoSplitLinesByDefault;
    procedure TestTheRaggedEndKeepsItsTickAndLosesItsLabel;
    procedure TestTimeLabelsAreNeverThinnedByIndex;
    procedure TestTheCoarseTicksAreEmphasised;
    procedure TestTheEmphasisStyleIsWhatGetsDrawn;
    procedure TestADateStringIsAValidMinAndMax;
    procedure TestUseUtcReachesTheScale;
    procedure TestABareDateStringIsReadOnTheLocalClock;
    procedure TestATimeTickIsNeverAMinorTick;
    procedure TestTheMonthNamesFollowTheLibrarysOwnRule;
    procedure TestAnEmptyTimeAxisShowsTodayNotTheEpoch;
  end;

implementation

const
  { One day, as a flat count of milliseconds. Used only where a flat count is
    the right thing -- never as a step. }
  cDayMs = 86400000.0;

{ ======================= the calendar and the formatter ==================== }

function TAdvChartTimeTest.Ms(AY, AMo, AD, AH, AMi, ASec,
  AMilli: Integer): Double;
begin
  Result := TyDateTimeToMs(EncodeDate(AY, AMo, AD), True)
            + AH * 3600000 + AMi * 60000 + ASec * 1000 + AMilli;
end;

function TAdvChartTimeTest.Ticks(AFrom, ATo: Double;
  ASplit: Integer): TTyTimeTickArray;
begin
  Result := TyTimeTicks(AFrom, ATo, ASplit, True);
end;

function TAdvChartTimeTest.Reading(AFrom, ATo: Double; ASplit: Integer): string;
var t: TTyTimeTickArray; i: Integer;
begin
  Result := '';
  t := Ticks(AFrom, ATo, ASplit);
  for i := 0 to High(t) do
  begin
    if i > 0 then Result := Result + '|';
    Result := Result + TyTimeLabel(t[i], True);
  end;
end;

function TAdvChartTimeTest.Levels(AFrom, ATo: Double; ASplit: Integer): string;
var t: TTyTimeTickArray; i: Integer;
begin
  Result := '';
  t := Ticks(AFrom, ATo, ASplit);
  for i := 0 to High(t) do
  begin
    if i > 0 then Result := Result + '|';
    Result := Result + TyTimeLabel(t[i], True) + '@' + IntToStr(t[i].Level);
  end;
end;

procedure TAdvChartTimeTest.SetUp;
begin
  inherited SetUp;
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
end;

procedure TAdvChartTimeTest.TearDown;
begin
  TyDateTimeNameSource := FSavedSource;
  inherited TearDown;
end;

function TimeUnitName(AUnit: TTyTimeUnit): string;
const cNames: array[TTyTimeUnit] of string = (
  'year', 'month', 'day', 'hour', 'minute', 'second', 'millisecond');
begin
  Result := cNames[AUnit];
end;

procedure TAdvChartTimeTest.AssertUnit(AExpected, AActual: TTyTimeUnit);
begin
  AssertEquals(TimeUnitName(AExpected), TimeUnitName(AActual));
end;

procedure TAdvChartTimeTest.TestAMonthIsNotAFixedNumberOfMilliseconds;
var jan, feb, mar: Double;
begin
  { THE WHOLE REASON THE STEPPING IS CALENDAR ARITHMETIC. January is 31 days
    and February 2024 is 29, so a month-stepper that adds a constant is wrong
    by two days after two steps and by a fortnight after a year. }
  jan := Ms(2024, 1, 1);
  feb := Ms(2024, 2, 1);
  mar := Ms(2024, 3, 1);
  AssertEquals('January is 31 days', 31.0, (feb - jan) / cDayMs, 0.0001);
  AssertEquals('February 2024 is 29', 29.0, (mar - feb) / cDayMs, 0.0001);
end;

procedure TAdvChartTimeTest.TestSteppingAMonthOverflowsRatherThanClamps;
var t: TTyTimeTickArray;
begin
  { FPC's IncMonth CLAMPS: the 31st of January plus a month is the 28th or 29th
    of February. JavaScript's setMonth OVERFLOWS: it is the 2nd or 3rd of
    March. The difference is not cosmetic -- a clamping step never leaves the
    month it started in, so a sixteen-day ladder spins until the fail-safe.

    Asked of the ticks rather than of a private routine: a month level whose
    first span starts on a 31st only exists because the step overflowed. }
  t := Ticks(Ms(2024, 1, 31), Ms(2024, 1, 31) + 3 * cDayMs);
  AssertTrue('the ladder terminated', Length(t) > 0);
  AssertTrue('and stayed inside three days',
             t[High(t)].Value - t[0].Value <= 3 * cDayMs + 1);
end;

procedure TAdvChartTimeTest.TestSteppingADayCarriesOutOfItsMonth;
begin
  { A day level started on the 25th steps 27, 29, 31 and then -- because the
    day field carries -- the 2nd of the next month. Upstream relies on that
    carry to end the span; a clamped step would sit on the 31st forever. }
  AssertEquals('25|27|29|31|Feb|2|3|5|7|8',
    Reading(Ms(2024, 1, 25), Ms(2024, 2, 8)));
end;

procedure TAdvChartTimeTest.TestAMonthFloorsToTheFirstNotTheZeroth;
begin
  { EVERY OTHER FIELD FLOORS TO NOUGHT AND THE DAY OF THE MONTH FLOORS TO ONE.
    Read the other way, the first of a month becomes the zeroth, which is the
    last day of the month before -- so a chart of March would open its month
    level on the 29th of February. }
  AssertUnit(ttuMonth, TyTimeUnitOf(Ms(2024, 3, 1), True));
  AssertUnit(ttuDay, TyTimeUnitOf(Ms(2024, 3, 2), True));
end;

procedure TAdvChartTimeTest.TestTheFinestFieldNotAtItsFloorNamesTheUnit;
begin
  AssertUnit(ttuYear, TyTimeUnitOf(Ms(2024, 1, 1), True));
  AssertUnit(ttuMonth, TyTimeUnitOf(Ms(2024, 5, 1), True));
  AssertUnit(ttuDay, TyTimeUnitOf(Ms(2024, 5, 6), True));
  AssertUnit(ttuHour, TyTimeUnitOf(Ms(2024, 5, 6, 7), True));
  AssertUnit(ttuMinute, TyTimeUnitOf(Ms(2024, 5, 6, 7, 8), True));
  AssertUnit(ttuSecond, TyTimeUnitOf(Ms(2024, 5, 6, 7, 8, 9), True));
  AssertUnit(ttuMillisecond, TyTimeUnitOf(Ms(2024, 5, 6, 7, 8, 9, 10), True));
end;

procedure TAdvChartTimeTest.TestMidnightIsADayAndNotAnHour;
begin
  { The single most visible consequence of reading the cascade backwards. If
    the COARSEST field at its floor named the unit, every midnight would be an
    `hour` and every day label on every time axis would read `00:00`. }
  AssertUnit(ttuDay, TyTimeUnitOf(Ms(2024, 5, 6, 0, 0, 0, 0), True));
  AssertEquals('6', TyTimeLabel(Ticks(Ms(2024, 5, 6), Ms(2024, 5, 10))[0], True));
end;

procedure TAdvChartTimeTest.TestTheDayFloorWorksBeforeTheEpoch;
var t: TTyTimeTickArray;
begin
  { A stamp before 1970 is NEGATIVE, and integer division rounds towards zero:
    without a floored division the last hours of 1969 are filed under 1970 and
    come out with a negative time of day. }
  AssertUnit(ttuDay, TyTimeUnitOf(Ms(1969, 12, 31), True));
  AssertUnit(ttuHour, TyTimeUnitOf(Ms(1969, 12, 31, 23), True));
  AssertEquals('1970', TyFormatTime(0, '{yyyy}', True));
  AssertEquals('1969-12-31 23:00', TyFormatTime(-3600000,
    '{yyyy}-{MM}-{dd} {HH}:{mm}', True));
  t := Ticks(Ms(1969, 12, 30), Ms(1970, 1, 3));
  AssertTrue('the ticks cross the epoch in order',
             t[0].Value < 0);
  AssertTrue('and reach the far side', t[High(t)].Value > 0);
end;

procedure TAdvChartTimeTest.TestALeapDayIsADayLikeAnyOther;
begin
  AssertEquals('27|28|29|Mar|2|3',
    Reading(Ms(2024, 2, 27), Ms(2024, 3, 3)));
  { And 2023 has no 29th to show. }
  AssertEquals('27|28|Mar|2|3',
    Reading(Ms(2023, 2, 27), Ms(2023, 3, 3)));
end;

procedure TAdvChartTimeTest.TestEveryTokenTheDefaultTemplatesUse;
var v: Double;
begin
  { 2024-03-09 is a Saturday, which gives every weekday token something to say
    other than its zero. }
  v := Ms(2024, 3, 9, 14, 5, 7, 42);
  AssertEquals('2024', TyFormatTime(v, '{yyyy}', True));
  AssertEquals('24', TyFormatTime(v, '{yy}', True));
  AssertEquals('1', TyFormatTime(v, '{Q}', True));
  AssertEquals('March', TyFormatTime(v, '{MMMM}', True));
  AssertEquals('Mar', TyFormatTime(v, '{MMM}', True));
  AssertEquals('03', TyFormatTime(v, '{MM}', True));
  AssertEquals('3', TyFormatTime(v, '{M}', True));
  AssertEquals('09', TyFormatTime(v, '{dd}', True));
  AssertEquals('9', TyFormatTime(v, '{d}', True));
  AssertEquals('Saturday', TyFormatTime(v, '{eeee}', True));
  AssertEquals('Sat', TyFormatTime(v, '{ee}', True));
  AssertEquals('6', TyFormatTime(v, '{e}', True));
  AssertEquals('14', TyFormatTime(v, '{HH}', True));
  AssertEquals('14', TyFormatTime(v, '{H}', True));
  AssertEquals('02', TyFormatTime(v, '{hh}', True));
  AssertEquals('2', TyFormatTime(v, '{h}', True));
  AssertEquals('05', TyFormatTime(v, '{mm}', True));
  AssertEquals('5', TyFormatTime(v, '{m}', True));
  AssertEquals('07', TyFormatTime(v, '{ss}', True));
  AssertEquals('7', TyFormatTime(v, '{s}', True));
  AssertEquals('042', TyFormatTime(v, '{SSS}', True));
  AssertEquals('42', TyFormatTime(v, '{S}', True));
  AssertEquals('pm', TyFormatTime(v, '{a}', True));
  AssertEquals('PM', TyFormatTime(v, '{A}', True));
  { AND MIDNIGHT IS NOUGHT ON THE TWELVE-HOUR CLOCK, not twelve. Upstream
    writes `(H - 1) % 12 + 1` and JavaScript's remainder keeps the sign, so
    hour nought comes out nought. It looks like a bug and it is upstream's
    answer; a port that `fixed` it would disagree with every ECharts chart
    in the world at exactly one hour of the day. }
  AssertEquals('00', TyFormatTime(Ms(2024, 3, 9), '{hh}', True));
  AssertEquals('0', TyFormatTime(Ms(2024, 3, 9), '{h}', True));
  AssertEquals('am', TyFormatTime(Ms(2024, 3, 9), '{a}', True));
end;

procedure TAdvChartTimeTest.TestTheFourDigitYearIsNotPadded;
begin
  { Upstream pads the four-digit year to NOTHING -- `{yyyy}` is the raw number
    -- and pads only where a fixed width matters. A pad that truncated would
    lose the leading digit of a five-figure year instead. }
  AssertEquals('999', TyFormatTime(Ms(999, 6, 1), '{yyyy}', True));
  AssertEquals('99', TyFormatTime(Ms(999, 6, 1), '{yy}', True));
end;

procedure TAdvChartTimeTest.TestAnUnknownTokenIsLeftAlone;
begin
  { Swallowing it would turn a typo into silence. Left whole, the author can
    see what they wrote. }
  AssertEquals('{nope}', TyFormatTime(Ms(2024, 3, 9), '{nope}', True));
  AssertEquals('2024 {zz}', TyFormatTime(Ms(2024, 3, 9), '{yyyy} {zz}', True));
  { An unclosed brace is text, not the start of a token that eats the rest. }
  AssertEquals('2024 {yy', TyFormatTime(Ms(2024, 3, 9), '{yyyy} {yy', True));
end;

procedure TAdvChartTimeTest.TestLiteralTextBetweenTokensSurvives;
begin
  AssertEquals('on 9 March 2024 at 14:05',
    TyFormatTime(Ms(2024, 3, 9, 14, 5),
                 'on {d} {MMMM} {yyyy} at {HH}:{mm}', True));
end;

procedure TAdvChartTimeTest.TestTheWeekdayStartsAtSundayLikeJavaScript;
begin
  { JavaScript numbers Sunday nought; the RTL numbers it one. `{e}` is the
    JavaScript number, and the names have to agree with it. }
  AssertEquals('0', TyFormatTime(Ms(2024, 3, 10), '{e}', True));
  AssertEquals('Sun', TyFormatTime(Ms(2024, 3, 10), '{ee}', True));
  AssertEquals('1', TyFormatTime(Ms(2024, 3, 11), '{e}', True));
  AssertEquals('Mon', TyFormatTime(Ms(2024, 3, 11), '{ee}', True));
end;

procedure TAdvChartTimeTest.TestTwoDaysReadAsDaysAndSixHourMarks;
begin
  { The shape everybody recognises. Two levels: the days, and the quarter-day
    marks between them. }
  AssertEquals('Mar|06:00|12:00|18:00|2|06:00|12:00|18:00|3',
    Reading(Ms(2024, 3, 1), Ms(2024, 3, 3)));
end;

procedure TAdvChartTimeTest.TestTheCoarsestLevelHasTheHighestNumber;
begin
  { BACKWARDS FROM WHAT A READER EXPECTS, and load-bearing: the renderer marks
    everything above level nought for emphasis, so numbering them the other way
    round would bold the hours and leave the day markers plain. }
  AssertEquals('Mar@1|06:00@0|12:00@0|18:00@0|2@1|06:00@0|12:00@0|18:00@0|3@1',
    Levels(Ms(2024, 3, 1), Ms(2024, 3, 3)));
end;

procedure TAdvChartTimeTest.TestOneSurvivingLevelIsAllLevelZero;
begin
  { The number counts SURVIVING LEVELS and not units. Seventy years has only a
    year level, so its ticks are level nought -- not level six because years
    are the sixth unit down. }
  AssertEquals('1955@0|1967@0|1979@0|1991@0|2003@0|2015@0|2025@0',
    Levels(Ms(1955, 1, 1), Ms(2025, 1, 1)));
end;

procedure TAdvChartTimeTest.TestTheRaggedEndsComeBackAsNotNice;
var t: TTyTimeTickArray;
begin
  { A time axis' extent is never rounded outwards, so a chart of data from
    07:13 to 19:48 keeps both ends -- and the ticks have to reach them, or the
    grid stops short of the data. The LABEL is another matter. }
  t := Ticks(Ms(2024, 3, 1, 7, 13), Ms(2024, 3, 1, 19, 48));
  AssertTrue('the first tick is the extent', t[0].NotNice);
  AssertTrue('so is the last', t[High(t)].NotNice);
  AssertEquals('07:13', TyTimeLabel(t[0], True));
  AssertEquals('19:48', TyTimeLabel(t[High(t)], True));
  { And nothing in between is. }
  AssertFalse('the round hours are not ragged', t[1].NotNice);
end;

procedure TAdvChartTimeTest.TestAnEndAnIntervalLandsOnIsNotAddedTwice;
var t: TTyTimeTickArray; i, n: Integer;
begin
  { Both ends of this span ARE round, so neither needs putting back -- and
    pushing them regardless would double the first and last tick. }
  t := Ticks(Ms(2024, 3, 1), Ms(2024, 3, 3));
  n := 0;
  for i := 0 to High(t) do
    if t[i].NotNice then Inc(n);
  AssertEquals('nothing was forced back in', 0, n);
  for i := 1 to High(t) do
    AssertTrue('and no two ticks share an instant',
               t[i].Value > t[i - 1].Value);
end;

procedure TAdvChartTimeTest.TestDaysCountFromTheFirstOfTheMonth;
begin
  { A level starts at the beginning of the NEXT COARSER unit, not at the
    extent. Counting from the extent would give the 25th, 27th, 29th, 31st and
    then the 2nd, 4th, 6th -- a cadence that changes parity at every month end
    for no reason a reader can see. Counting from the 1st gives odd days in
    January and odd days in February, which is why the 31st and the 1st are
    both there. }
  AssertEquals('25|27|29|31|Feb|2|3|5|7|8',
    Reading(Ms(2024, 1, 25), Ms(2024, 2, 8)));
end;

procedure TAdvChartTimeTest.TestTheHourStepClimbsItsLadder;
var base: Double;
begin
  { 12 / 6 / 4 / 2 / 1, and every comparison is STRICTLY greater. Each span
    below is chosen so the hour level's approximate interval sits one notch up
    from the last. }
  base := Ms(2024, 3, 4);
  { Six hours over six ticks is one hour each: the bottom rung. }
  AssertEquals('4|01:00|02:00|03:00|04:00|05:00|06:00',
    Reading(base, base + 6 * 3600000.0));
  { Eighteen hours is three each, which is the first value STRICTLY above
    two -- and two is the rung below, so this lands on two. }
  AssertEquals('4|02:00|04:00|06:00|08:00|10:00|12:00|14:00|16:00|18:00',
    Reading(base, base + 18 * 3600000.0));
  { Thirty hours is five each, above 3.5, so four. The day level appears
    underneath it at the same time, which is why the two midnights are
    day markers and the rest are hours. }
  AssertEquals('4|04:00|08:00|12:00|16:00|20:00|5|04:00|06:00',
    Reading(base, base + 30 * 3600000.0));
  { And the top rung, twelve, which the default six ticks reaches only
    just: any wider and the day level below has enough ticks of its own
    and the hour level is thrown away. }
  AssertEquals('4|12:00|5|12:00|6|12:00|7|01:00',
    Reading(base, base + 73 * 3600000.0));
end;

procedure TAdvChartTimeTest.TestTheDayStepClimbsItsLadder;
var base: Double;
begin
  { 16 / 7 / 4 / 2 / 1. The seven is a week in all but name. }
  base := Ms(2024, 3, 1);
  AssertEquals('Mar|2|3|4|5|6',
    Reading(base, base + 5 * cDayMs));
  AssertEquals('Mar|3|5|7|9|11|13',
    Reading(base, base + 12 * cDayMs));
  { The ragged end is a tick too: twenty-five days from the 1st is the
    26th, and no four-day interval lands there. }
  AssertEquals('Mar|5|9|13|17|21|25|26',
    Reading(base, base + 25 * cDayMs));
end;

procedure TAdvChartTimeTest.TestTheMonthStepClimbsItsLadder;
begin
  { 6 / 3 / 2 / 1, off an approximate interval divided by THIRTY days --
    while the size table one function up calls a month THIRTY-ONE. Both
    numbers are upstream's and neither is a slip: the table decides when an
    axis stops counting days, this decides how many months it then steps.

    A year over six ticks is 60.8 days, which is just above two thirtieths
    -- so it steps two months, and the same span measured against 31 days
    would step one and print all twelve. }
  AssertEquals('2024|Mar|May|Jul|Sep|Nov|2025',
    Reading(Ms(2024, 1, 1), Ms(2025, 1, 1)));
  { Three hundred days is 50 a tick: below two thirtieths, so every month.
    The YEAR level is skipped here -- both ends are inside 2024 -- which is
    why the first of January is the only tick that says a year. }
  AssertEquals('2024|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|27',
    Reading(Ms(2024, 1, 1), Ms(2024, 10, 27)));
end;

procedure TAdvChartTimeTest.TestTheMinuteAndSecondStepClimbsItsLadder;
var base: Double;
begin
  { 30 / 20 / 15 / 10 / 5 / 2 / 1, shared by minutes and seconds. The rungs
    below the top three are the only ones a default six-tick axis can
    actually reach: above them the level before has enough ticks of its own
    and this one is discarded. }
  base := Ms(2024, 3, 4, 10);
  { Three minutes over six ticks is thirty seconds each, which is not
    STRICTLY above thirty -- so it lands on the rung below, twenty. }
  AssertEquals('10:00|10:00:20|10:00:40|10:01|10:01:20|10:01:40'
    + '|10:02|10:02:20|10:02:40|10:03',
    Reading(base, base + 3 * 60000.0));
  { Two minutes is twenty seconds each: above fifteen, not above twenty. }
  AssertEquals('10:00|10:00:15|10:00:30|10:00:45|10:01|10:01:15'
    + '|10:01:30|10:01:45|10:02',
    Reading(base, base + 2 * 60000.0));
  { Forty-eight seconds is eight each. The MINUTE level is skipped entirely
    -- both ends are inside one minute -- so the seconds are the only level
    and the ragged end keeps its own value. }
  AssertEquals('10:00|10:00:05|10:00:10|10:00:15|10:00:20|10:00:25'
    + '|10:00:30|10:00:35|10:00:40|10:00:45|10:00:48',
    Reading(base, base + 48000.0));
end;

procedure TAdvChartTimeTest.TestAYearStepIsNeverSnappedToANiceNumber;
begin
  { Every other unit picks its step off a ladder. The year takes the plain
    rounded count, so whatever that count is, is what it draws.

    Thirty-five years over six ticks is 5.83 a tick, which rounds to SIX --
    and six is not on the nice ladder at all, which would have said five.
    Deliberately a different span from the seventy-year test above: two
    tests asserting one string is one test. }
  AssertEquals('1990|1996|2002|2008|2014|2020|2025',
    Reading(Ms(1990, 1, 1), Ms(2025, 1, 1)));
end;

procedure TAdvChartTimeTest.TestTheBottomUnitIsOneRowFinerThanTheSizeSaid;
var t: TTyTimeTickArray;
begin
  { The size table is searched for the first row at least as big as the
    approximate interval, and then the row BEFORE it is taken. One notch
    finer, deliberately: landing on the row itself gives an axis four ticks
    when it asked for six. Three seconds over six ticks wants a second-sized
    interval, and seconds are what it gets -- not the minute the bisect lands
    on. }
  t := Ticks(Ms(2024, 3, 1, 10), Ms(2024, 3, 1, 10, 0, 3));
  AssertEquals('10:00|10:00:01|10:00:02|10:00:03',
    Reading(Ms(2024, 3, 1, 10), Ms(2024, 3, 1, 10, 0, 3)));
  AssertUnit(ttuSecond, t[1].Unit_);
end;

procedure TAdvChartTimeTest.TestSeventyYearsShowsYearsAndNotMonths;
var t: TTyTimeTickArray;
begin
  { THE DISCARD RULE. After the year level the walk goes on to months, finds it
    has added a hundred and forty of them, and throws the whole level away
    rather than keeping it -- because the level before it already had enough.
    Without the rule this axis carries eight hundred and forty ticks. }
  t := Ticks(Ms(1955, 1, 1), Ms(2025, 1, 1));
  AssertTrue('a handful of ticks, not hundreds', Length(t) < 12);
  AssertUnit(ttuYear, t[1].Unit_);
end;

procedure TAdvChartTimeTest.TestAYearLevelCountsFromJanuaryAndNotFromTheData;
begin
  { EVERY FIXTURE ABOVE STARTS ON A 1 JANUARY, which makes the year level's
    snap-to-the-start-of-the-year invisible: it has nothing to move. This one
    starts in June, so a year floor that forgot to zero the MONTH would count
    from the 1st of June and label every tick `Jun`.

    Both ends are ragged -- no twelve-year interval lands on a 15th of June --
    so they come back as the day they are. }
  AssertEquals('15|1967|1979|1991|2003|2015|15',
    Reading(Ms(1955, 6, 15), Ms(2025, 6, 15)));
end;

procedure TAdvChartTimeTest.TestACoarseTickBeatsAFineOneOnTheSameInstant;
var t: TTyTimeTickArray; i: Integer;
begin
  { The 1st of March is produced twice -- once by the month level and once by
    the day level that restarts at it -- and the copy that survives has to be
    the month's, or the marker loses the level that sets it apart. }
  t := Ticks(Ms(2024, 2, 20), Ms(2024, 3, 20));
  for i := 0 to High(t) do
    if t[i].Unit_ = ttuMonth then
    begin
      AssertTrue('the month marker kept its level', t[i].Level >= 1);
      Exit;
    end;
  Fail('no month marker in a span that crosses a month end');
end;

procedure TAdvChartTimeTest.TestADegenerateExtentOpensOutByADay;
var t: TTyTimeTickArray;
begin
  { A single point has no span, so there is no interval to pick and the walk
    would never terminate. Upstream opens it by a flat day either side. }
  t := Ticks(Ms(2024, 3, 1), Ms(2024, 3, 1));
  AssertTrue('it produced ticks', Length(t) >= 2);
  AssertEquals('two days across', 2 * cDayMs,
               t[High(t)].Value - t[0].Value, 1);
end;

procedure TAdvChartTimeTest.TestAskingForMoreTicksGivesAFinerUnit;
begin
  { The split number is the only knob, and it works by making the approximate
    interval smaller, which walks the size table further down. }
  AssertEquals('Mar|06:00|12:00|18:00|2|06:00|12:00|18:00|3',
    Reading(Ms(2024, 3, 1), Ms(2024, 3, 3), 6));
  AssertEquals(
    'Mar|04:00|08:00|12:00|16:00|20:00|2|04:00|08:00|12:00|16:00|20:00|3',
    Reading(Ms(2024, 3, 1), Ms(2024, 3, 3), 12));
end;

procedure TAdvChartTimeTest.TestAHugeSpanTerminates;
var t: TTyTimeTickArray;
begin
  { The fail-safe, and the reason it is there: a step that failed to advance
    would spin, and the calendar has more than one way to produce one. Two
    thousand years at a stretch is the cheapest way to ask. }
  t := Ticks(Ms(20, 1, 1), Ms(2024, 1, 1));
  AssertTrue('it came back', Length(t) > 0);
  AssertTrue('and not with three thousand ticks', Length(t) < 3100);
end;

procedure TAdvChartTimeTest.TestAnInvertedRangeIsReadTheRightWayRound;
begin
  AssertEquals(Reading(Ms(2024, 3, 1), Ms(2024, 3, 3)),
               Reading(Ms(2024, 3, 3), Ms(2024, 3, 1)));
end;

{ =========================== through an option ============================= }

procedure TAdvChartTimeAxisTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
  FSavedSource := TyDateTimeNameSource;
  FSavedFmt := DefaultFormatSettings;
  TyDateTimeNameSource := dnTranslation;
end;

procedure TAdvChartTimeAxisTest.TearDown;
begin
  TyDateTimeNameSource := FSavedSource;
  DefaultFormatSettings := FSavedFmt;
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartTimeAxisTest.Draw(const AOption: string;
  AW, AH, APPI: Integer);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 0, 255, 255));
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, AW, AH), APPI);
end;

function TAdvChartTimeAxisTest.XAxis: TTyAxis;
begin
  Result := FChart.Build.Grid(0).XAxis(0);
end;

function TAdvChartTimeAxisTest.XSpec: PTyAxisLayoutSpec;
begin
  Result := FChart.Build.Grid(0).SpecFor(XAxis);
end;

function TAdvChartTimeAxisTest.YAxis: TTyAxis;
begin
  Result := FChart.Build.Grid(0).YAxis(0);
end;

function TAdvChartTimeAxisTest.ShownLabels: string;
var p: PTyAxisLayoutSpec; i: Integer;
begin
  Result := '';
  p := XSpec;
  if p = nil then Exit;
  for i := 0 to High(p^.Placements) do
  begin
    if not p^.Placements[i].Shown then Continue;
    if Result <> '' then Result := Result + '|';
    Result := Result + p^.Placements[i].Text;
  end;
end;

function TAdvChartTimeAxisTest.FirstLabel: string;
var s: string; p: Integer;
begin
  s := ShownLabels;
  p := Pos('|', s);
  if p > 0 then Result := Copy(s, 1, p - 1) else Result := s;
end;

const
  { Four days of data on a time axis. Written as date strings because that is
    how everybody writes a time series, and pinned to UTC at BOTH ends -- the
    `Z` on the data and `useUTC` on the chart -- so that the labels these
    tests assert are the same on a machine in Shanghai and one in Reykjavik.
    What the zone does when it is NOT pinned has a test of its own. }
  cFourDays =
    '{"useUTC":true,"xAxis":{"type":"time"},"yAxis":{},'
    + '"series":[{"type":"line","data":['
    + '["2024-03-01T00:00:00Z",1],["2024-03-02T00:00:00Z",2],'
    + '["2024-03-03T00:00:00Z",3],["2024-03-05T00:00:00Z",4]]}]}';

  { Two days, which is the span that grows a SECOND level -- days above,
    six-hour marks below. Four days does not: the day level alone already
    has enough ticks, so the hour level is discarded. }
  cTwoDays =
    '{"useUTC":true,"xAxis":{"type":"time"},"yAxis":{},'
    + '"series":[{"type":"line","data":['
    + '["2024-03-01T00:00:00Z",1],["2024-03-03T00:00:00Z",2]]}]}';

procedure TAdvChartTimeAxisTest.TestATimeAxisGetsATimeScale;
begin
  Draw(cFourDays);
  AssertTrue('a time axis is a time scale', XAxis.Scale is TTyTimeScale);
end;

procedure TAdvChartTimeAxisTest.TestATimeAxisWorksDownTheSideToo;
var p: PTyAxisLayoutSpec; i: Integer; s: string;
begin
  { EVERY OTHER TEST HERE PUTS THE TIME ON THE X AXIS, which is where it
    nearly always goes -- and that is exactly what makes it worth asking
    once on the other family. A port that reached for the x axis' extent, or
    for a horizontal label band, would pass all of them. }
  Draw('{"useUTC":true,"xAxis":{"type":"value"},"yAxis":{"type":"time"},'
    + '"series":[{"type":"line","data":['
    + '[1,"2024-03-01T00:00:00Z"],[2,"2024-03-03T00:00:00Z"]]}]}');
  AssertTrue('the y axis is a time scale', YAxis.Scale is TTyTimeScale);
  p := FChart.Build.Grid(0).SpecFor(YAxis);
  s := '';
  for i := 0 to High(p^.Labels) do
  begin
    if s <> '' then s := s + '|';
    s := s + p^.Labels[i];
  end;
  AssertEquals('and it reads as dates down the side',
    'Mar|06:00|12:00|18:00|2|06:00|12:00|18:00|3', s);
end;

procedure TAdvChartTimeAxisTest.TestATimeAxisDoesNotStretchBackToNineteenSeventy;
var e: TTyRange;
begin
  { Every other axis is pulled to include zero, which is how a bar chart gets
    its baseline. Zero on a time axis is the first instant of 1970: applying
    the same rule to four days in March would draw them all in the last pixel
    of a fifty-six year span. }
  Draw(cFourDays);
  e := XAxis.Scale.GetExtent;
  AssertTrue('the extent starts in 2024, not 1970',
             e.Start > TyDateTimeToMs(EncodeDate(2020, 1, 1), True));
end;

procedure TAdvChartTimeAxisTest.TestATimeAxisIsNotNiciedToRoundNumbers;
var e: TTyRange; lo, hi: Double;
begin
  { Niceify opens an extent out to round numbers before choosing a step. The
    round number nearest a week in March 2024 is somewhere in 1973, so a time
    scale keeps the data's own ends -- exactly. }
  Draw(cFourDays);
  e := XAxis.Scale.GetExtent;
  lo := TyDateTimeToMs(EncodeDate(2024, 3, 1), True);
  hi := TyDateTimeToMs(EncodeDate(2024, 3, 5), True);
  AssertEquals('the low end is the data''s', lo, e.Start, 1);
  AssertEquals('and so is the high end', hi, e.Stop, 1);
end;

procedure TAdvChartTimeAxisTest.TestItsLabelsAreDatesAndNotNumbers;
begin
  Draw(cFourDays);
  AssertEquals('Mar|2|3|4|5', ShownLabels);
end;

procedure TAdvChartTimeAxisTest.TestTheSplitNumberDefaultsToSixNotFive;
begin
  { Upstream gives a time axis six where every other axis gets five, because a
    date is a wider label than a number. Asked of the scale rather than counted
    off the axis: the tick count is only ROUGHLY the split number, so counting
    ticks would pass at five as well. }
  Draw(cFourDays);
  AssertEquals(6, TTyTimeScale(XAxis.Scale).SplitNumber);
end;

procedure TAdvChartTimeAxisTest.TestATimeAxisDrawsNoSplitLinesByDefault;
var f: TTyAxisFurniture;
begin
  { A value axis grids by default and a time axis does not -- upstream says so
    outright in its per-type defaults, and a time chart with vertical lines
    every six hours is a very different-looking thing. }
  Draw(cFourDays);
  f := FChart.Build.Grid(0).FurnitureFor(XAxis);
  AssertFalse('no split lines unless asked', f.ShowSplitLine);
end;

procedure TAdvChartTimeAxisTest.TestTheRaggedEndKeepsItsTickAndLosesItsLabel;
var p: PTyAxisLayoutSpec; i, hidden: Integer;
begin
  { Data that starts at 07:13 keeps 07:13 as its first tick -- the grid has to
    reach the data -- but labelling it puts a ragged number hard against the
    first round hour. Upstream hides the label and keeps the tick. }
  Draw('{"useUTC":true,"xAxis":{"type":"time"},"yAxis":{},'
    + '"series":[{"type":"line","data":['
    + '["2024-03-01T07:13:00Z",1],["2024-03-01T19:48:00Z",2]]}]}');
  p := XSpec;
  AssertTrue('the axis has labels', Length(p^.Labels) > 2);
  AssertEquals('the ragged start is still a tick', '07:13', p^.Labels[0]);
  hidden := 0;
  for i := 0 to High(p^.LabelNotNice) do
    if p^.LabelNotNice[i] then Inc(hidden);
  AssertEquals('both ends ragged', 2, hidden);
  AssertTrue('the first is one of them', p^.LabelNotNice[0]);
  AssertTrue('and so is the last', p^.LabelNotNice[High(p^.LabelNotNice)]);
  AssertEquals('and neither is drawn', '08:00|10:00|12:00|14:00|16:00|18:00',
    ShownLabels);
end;

procedure TAdvChartTimeAxisTest.TestTimeLabelsAreNeverThinnedByIndex;
var p: PTyAxisLayoutSpec;
begin
  { The uniform every-Nth step is right for a category axis, where the labels
    are interchangeable. On a time axis it takes the month markers with it and
    leaves a run of day numbers that restarts for no visible reason. Asked on a
    NARROW chart, because a wide one would not thin anything anyway. }
  Draw(cFourDays, 150, 120);
  p := XSpec;
  AssertEquals('every label kept', 1, p^.LabelStep);
end;

procedure TAdvChartTimeAxisTest.TestTheCoarseTicksAreEmphasised;
var p: PTyAxisLayoutSpec; i: Integer; any: Boolean;
begin
  { `Mar` among a run of day numbers is drawn heavier, which is upstream's
    `rich: { primary: { fontWeight: 'bold' } }` on the time axis' defaults --
    and it is what makes the levels legible rather than merely present. }
  Draw(cTwoDays);
  p := XSpec;
  AssertTrue('there is a weight to give them', p^.EmphasisFontWeight > 400);
  any := False;
  for i := 0 to High(p^.Placements) do
    if p^.Placements[i].Emphasis then
    begin
      any := True;
      AssertTrue('an emphasised label is a day marker and not an hour',
                 Pos(':', p^.Placements[i].Text) = 0);
    end
    else
      AssertTrue('a plain label is one of the hours',
                 Pos(':', p^.Placements[i].Text) > 0);
  AssertTrue('something was emphasised', any);
end;

procedure TAdvChartTimeAxisTest.TestTheEmphasisStyleIsWhatGetsDrawn;
var x, y, red, plain: Integer; p: TBGRAPixel;
begin
  { The spec says WHICH labels are emphasised; this says the emphasis reaches
    the glyphs -- and through the THEME, which is where every visual value in
    this library comes from. A skin that paints the level markers red gets red
    level markers, and the plain hour labels stay grey.

    Colour and not weight, because a bold `Mar` and a light `Mar` differ by a
    handful of pixels that antialiasing can supply on its own. }
  FCtl.StyleOverride :=
    'TyAdvChartAxisLabelPrimary { color: #FF0000; font-weight: 700; }';
  Draw(cTwoDays);
  red := 0;
  plain := 0;
  { The bottom of the control, which on a chart this size is the axis and its
    labels and nothing else. }
  for y := 200 to 298 do
    for x := 1 to 498 do
    begin
      p := FBmp.GetPixel(x, y);
      if p.alpha = 0 then Continue;
      if (p.red > p.green + 60) and (p.red > p.blue + 60) then Inc(red)
      else if p.red + p.green + p.blue < 600 then Inc(plain);
    end;
  AssertTrue('the level markers were drawn in the emphasis colour', red > 0);
  AssertTrue('and the plain labels were not', plain > 0);
end;

procedure TAdvChartTimeAxisTest.TestADateStringIsAValidMinAndMax;
var e: TTyRange;
begin
  { `min: '2024-01-01'` is how the bound is written in every example anybody
    has ever read. Accepting only numbers made the two most-used axis options
    do nothing at all on the one axis type that needs them most. }
  Draw('{"xAxis":{"type":"time","min":"2024-02-01","max":"2024-02-05"},'
    + '"yAxis":{},"series":[{"type":"line","data":['
    + '["2024-02-02T00:00:00Z",1],["2024-02-03T00:00:00Z",2]]}]}');
  e := XAxis.Scale.GetExtent;
  { LOCAL midnight, because the bound carries no zone designator and a bare
    date string is local -- ECharts' documented choice, and deliberately
    unlike JavaScript's own parser. }
  AssertEquals('the author''s low end',
    TyDateTimeToMs(EncodeDate(2024, 2, 1), False), e.Start, 1);
  AssertEquals('the author''s high end',
    TyDateTimeToMs(EncodeDate(2024, 2, 5), False), e.Stop, 1);
end;

procedure TAdvChartTimeAxisTest.TestUseUtcReachesTheScale;
begin
  { ONE option at the root of the tree, not an axis one. }
  Draw('{"xAxis":{"type":"time"},"yAxis":{},"series":[]}');
  AssertFalse('local by default', TTyTimeScale(XAxis.Scale).UTC);
  Draw(cFourDays);
  AssertTrue('and the root option reaches it',
             TTyTimeScale(XAxis.Scale).UTC);
end;

procedure TAdvChartTimeAxisTest.TestABareDateStringIsReadOnTheLocalClock;
var e: TTyRange;
begin
  { `'2011-01-02'` comes back as the 2nd of January wherever it is read,
    which is ECharts' documented choice and deliberately unlike JavaScript's
    own parser -- a date somebody typed is a date, not an instant. The
    assertion is written against the local clock rather than against a fixed
    number, so it says the same thing in every zone including UTC. }
  Draw('{"xAxis":{"type":"time"},"yAxis":{},"series":[{"type":"line",'
    + '"data":[["2024-03-01",1],["2024-03-05",2]]}]}');
  e := XAxis.Scale.GetExtent;
  AssertEquals('local midnight, not UTC midnight',
    TyDateTimeToMs(EncodeDate(2024, 3, 1), False), e.Start, 1);
end;

procedure TAdvChartTimeAxisTest.TestATimeTickIsNeverAMinorTick;
var t: TTyScaleTickArray; i, coarse: Integer;
begin
  { A year marker among days is not a subdivision of anything -- it is the
    COARSEST tick there is. Level means major-or-minor everywhere else in the
    port, so a time tick's coarseness lives in a field of its own; writing it
    into Level would draw every month marker short and unlabelled. }
  Draw(cTwoDays);
  t := XAxis.Scale.GetTicks;
  AssertTrue('there are ticks', Length(t) > 0);
  coarse := 0;
  for i := 0 to High(t) do
  begin
    AssertEquals('every time tick is a major', 0, t[i].Level);
    if t[i].TimeLevel > 0 then Inc(coarse);
  end;
  AssertTrue('and the coarseness went somewhere', coarse > 0);
end;

procedure TAdvChartTimeAxisTest.TestTheMonthNamesFollowTheLibrarysOwnRule;
begin
  { A chart with a TTyCalendar beside it must not say `Mar` while the calendar
    says 三月. The library has one rule for that -- the app's explicit choice,
    else a loaded translation, else the machine's locale -- and the chart's
    month names go through it rather than through a table of their own.

    Written against the rule rather than against a literal, so it says the
    same thing on every machine. }
  { A SENTINEL IN THE LOCALE TIER, so that the two tiers cannot accidentally
    give the same answer and let a chart with its own hardcoded table pass
    both halves of this. On an English machine they otherwise would. }
  { THREE LETTERS, like the real one: a first label much wider than its
    neighbour crowds it and gives way, as upstream's does }
  DefaultFormatSettings.ShortMonthNames[3] := 'MaR';
  TyDateTimeNameSource := dnLocale;
  Draw(cTwoDays);
  AssertEquals('the machine''s own name for March',
    'MaR', FirstLabel);
  { CLEARED IN BETWEEN, because writing the same option text twice is a
    deliberate no-op and the labels would otherwise be the previous pass'.
    That is also the limit of this: a chart already built does not relabel
    itself when the app switches language -- it has to be rebuilt. }
  Draw('{}');
  TyDateTimeNameSource := dnTranslation;
  Draw(cTwoDays);
  AssertEquals('and the resourcestrings when those are chosen',
    TyDateTimeNames.ShortMonthNames[3], FirstLabel);
end;

procedure TAdvChartTimeAxisTest.TestAnEmptyTimeAxisShowsTodayNotTheEpoch;
var e: TTyRange;
begin
  { An axis with no data spans 0..1 on every other type, which on a time axis
    is the first second of 1970. A chart that lost its data should not look
    like a chart about the Apollo programme. }
  Draw('{"xAxis":{"type":"time"},"yAxis":{},"series":[]}');
  e := XAxis.Scale.GetExtent;
  AssertEquals('a day wide', 86400000.0, e.Stop - e.Start, 1);
  AssertTrue('and it ends today',
             Abs(e.Stop - TyDateTimeToMs(Date, False)) < 1000);
end;

procedure TWeightedMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := Length(AText) * (6 + (AWeight - 400) / 100);
  AH := AFontSizeLogical;
end;

function TWeightedMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

function TAdvChartTimeMeasureTest.YearAmongMonths(
  AEmphasisWeight: Integer): TTyAxisLayoutSpec;
begin
  Result := Default(TTyAxisLayoutSpec);
  Result.Side := asLeft;
  Result.ShowLabels := True;
  { `2024` is both the WIDEST label and the emphasised one, which is what
    makes the weight decide the axis' thickness. }
  Result.Labels := TTyStringArray.Create('2024', 'Mar');
  Result.Positions := TTyDoubleArray.Create(0, 1);
  Result.LabelEmphasis := TTyBoolArray.Create(True, False);
  Result.FontSizeLogical := 12;
  Result.FontWeight := 400;
  Result.EmphasisFontWeight := AEmphasisWeight;
end;

procedure TAdvChartTimeMeasureTest.TestAnEmphasisedLabelIsMeasuredInItsOwnWeight;
var m: ITyTextMeasurer; plain, bold: Double;
begin
  { Bold is wider, and a label measured light and drawn bold is how an axis
    comes to overlap the one thing the measuring was for. }
  m := TWeightedMeasurer.Create;
  plain := TyAxisThickness(YearAmongMonths(0), m, 96, obcAxisLabel);
  bold := TyAxisThickness(YearAmongMonths(700), m, 96, obcAxisLabel);
  AssertTrue('an emphasised axis reserves more room', bold > plain + 1);
end;

initialization
  RegisterTest(TAdvChartTimeTest);
  RegisterTest(TAdvChartTimeMeasureTest);
  RegisterTest(TAdvChartTimeAxisTest);
end.
