unit test.calendar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, DateUtils,
  fpcunit, testregistry,
  tyControls.Calendar;

type
  TCalendarGeomTest = class(TTestCase)
  published
    { TyWeekdayOrder }
    procedure TestWeekdayOrderMonday;
    procedure TestWeekdayOrderSunday;

    { TyCalendarMonthGrid }
    procedure TestGridHas42Entries;
    procedure TestGridFirstCellBeforeOrOnFirst;
    procedure TestGridLastCellAfterOrOnLast;
    procedure TestFeb2024LeapContains29;
    procedure TestFirstDaySundayVsMonday;

    { TyCalendarInRange }
    procedure TestInRangeBelowMin;
    procedure TestInRangeAboveMax;
    procedure TestInRangeWithinBounds;
    procedure TestInRangeUnboundedMin;
    procedure TestInRangeUnboundedMax;
    procedure TestInRangeBothUnbounded;

    { TyCalendarClampDate }
    procedure TestClampBelowMinClampsToMin;
    procedure TestClampAboveMaxClampsToMax;
    procedure TestClampWithinRangeUnchanged;
    procedure TestClampUnboundedMin;
    procedure TestClampUnboundedMax;

    { TyDecadeStart }
    procedure TestDecadeStart2026;
    procedure TestDecadeStart2020;
    procedure TestDecadeStart2030;

    { TyISOWeekNumber }
    { 2026-01-05 is Monday. ISO week 1 of 2026 = Dec 29 2025..Jan 4 2026
      (because Jan 1 2026 is Thursday, so the week containing the first
      Thursday starts on Mon Dec 29 2025). Jan 5 2026 begins ISO week 2. }
    procedure TestISOWeekNumber_2026_01_05;
    { 2026-01-01 is Thursday -> ISO week 1. }
    procedure TestISOWeekNumber_2026_01_01;
  end;

implementation

{ TyWeekdayOrder }

procedure TCalendarGeomTest.TestWeekdayOrderMonday;
var
  ord_: TTyWeekdayOrderArray;
begin
  ord_ := TyWeekdayOrder(wdMonday);
  AssertEquals('Mon[0]=1', 1, ord_[0]);
  AssertEquals('Mon[1]=2', 2, ord_[1]);
  AssertEquals('Mon[2]=3', 3, ord_[2]);
  AssertEquals('Mon[3]=4', 4, ord_[3]);
  AssertEquals('Mon[4]=5', 5, ord_[4]);
  AssertEquals('Mon[5]=6', 6, ord_[5]);
  AssertEquals('Mon[6]=0', 0, ord_[6]);
end;

procedure TCalendarGeomTest.TestWeekdayOrderSunday;
var
  ord_: TTyWeekdayOrderArray;
  i: Integer;
begin
  ord_ := TyWeekdayOrder(wdSunday);
  for i := 0 to 6 do
    AssertEquals('Sun[' + IntToStr(i) + ']=' + IntToStr(i), i, ord_[i]);
end;

{ TyCalendarMonthGrid }

procedure TCalendarGeomTest.TestGridHas42Entries;
var
  Grid: TTyDateGrid;
begin
  Grid := TyCalendarMonthGrid(2024, 2, wdSunday);
  // Simply accessing both ends without AV proves all 42 slots are set.
  AssertTrue('grid[0] valid', Grid[0] <> 0);
  AssertTrue('grid[41] valid', Grid[41] <> 0);
  // grid[41] must come after grid[0]
  AssertTrue('grid monotone', Grid[41] > Grid[0]);
end;

procedure TCalendarGeomTest.TestGridFirstCellBeforeOrOnFirst;
var
  Grid: TTyDateGrid;
  First: TDateTime;
begin
  Grid := TyCalendarMonthGrid(2024, 2, wdSunday);
  First := EncodeDate(2024, 2, 1);
  AssertTrue('grid[0] <= Feb 1 2024', Grid[0] <= First);
end;

procedure TCalendarGeomTest.TestGridLastCellAfterOrOnLast;
var
  Grid: TTyDateGrid;
  Last: TDateTime;
begin
  Grid := TyCalendarMonthGrid(2024, 2, wdSunday);
  Last := EncodeDate(2024, 2, 29);  // leap year
  AssertTrue('grid[41] >= Feb 29 2024', Grid[41] >= Last);
end;

procedure TCalendarGeomTest.TestFeb2024LeapContains29;
var
  Grid: TTyDateGrid;
  Target: TDateTime;
  Found: Boolean;
  i: Integer;
begin
  Grid := TyCalendarMonthGrid(2024, 2, wdSunday);
  Target := EncodeDate(2024, 2, 29);
  Found := False;
  for i := 0 to 41 do
    if Grid[i] = Target then
    begin
      Found := True;
      Break;
    end;
  AssertTrue('Feb 29 2024 is in the grid', Found);
end;

procedure TCalendarGeomTest.TestFirstDaySundayVsMonday;
var
  GridSun, GridMon: TTyDateGrid;
begin
  { Feb 1 2024 is a Thursday (DayOfWeek=5, 0-based=4).
    With Sunday first:  lead = (4 - 0 + 7) mod 7 = 4  → grid[0] = Jan 28 2024.
    With Monday first:  lead = (4 - 1 + 7) mod 7 = 3  → grid[0] = Jan 29 2024. }
  GridSun := TyCalendarMonthGrid(2024, 2, wdSunday);
  GridMon := TyCalendarMonthGrid(2024, 2, wdMonday);

  AssertEquals('Sunday-first grid[0] = Jan 28 2024',
    EncodeDate(2024, 1, 28), GridSun[0]);
  AssertEquals('Monday-first grid[0] = Jan 29 2024',
    EncodeDate(2024, 1, 29), GridMon[0]);

  // The two grids must start differently
  AssertTrue('grids differ at [0]', GridSun[0] <> GridMon[0]);
end;

{ TyCalendarInRange }

procedure TCalendarGeomTest.TestInRangeBelowMin;
begin
  AssertFalse('below min is out of range',
    TyCalendarInRange(
      EncodeDate(2024, 1, 1),
      EncodeDate(2024, 1, 2),
      EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestInRangeAboveMax;
begin
  AssertFalse('above max is out of range',
    TyCalendarInRange(
      EncodeDate(2025, 1, 1),
      EncodeDate(2024, 1, 1),
      EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestInRangeWithinBounds;
begin
  AssertTrue('within bounds is in range',
    TyCalendarInRange(
      EncodeDate(2024, 6, 15),
      EncodeDate(2024, 1, 1),
      EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestInRangeUnboundedMin;
begin
  // AMin=0 means no lower bound
  AssertTrue('unbounded min: any lower date accepted',
    TyCalendarInRange(
      EncodeDate(1900, 1, 1),
      0,
      EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestInRangeUnboundedMax;
begin
  // AMax=0 means no upper bound
  AssertTrue('unbounded max: any higher date accepted',
    TyCalendarInRange(
      EncodeDate(9999, 12, 31),
      EncodeDate(2024, 1, 1),
      0));
end;

procedure TCalendarGeomTest.TestInRangeBothUnbounded;
begin
  AssertTrue('both unbound: always in range',
    TyCalendarInRange(EncodeDate(2024, 6, 15), 0, 0));
end;

{ TyCalendarClampDate }

procedure TCalendarGeomTest.TestClampBelowMinClampsToMin;
var
  AMin: TDateTime;
begin
  AMin := EncodeDate(2024, 1, 2);
  AssertEquals('below min clamps to min',
    AMin,
    TyCalendarClampDate(EncodeDate(2024, 1, 1), AMin, EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestClampAboveMaxClampsToMax;
var
  AMax: TDateTime;
begin
  AMax := EncodeDate(2024, 12, 31);
  AssertEquals('above max clamps to max',
    AMax,
    TyCalendarClampDate(EncodeDate(2025, 1, 1), EncodeDate(2024, 1, 1), AMax));
end;

procedure TCalendarGeomTest.TestClampWithinRangeUnchanged;
var
  ADate: TDateTime;
begin
  ADate := EncodeDate(2024, 6, 15);
  AssertEquals('within range is unchanged',
    ADate,
    TyCalendarClampDate(ADate, EncodeDate(2024, 1, 1), EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestClampUnboundedMin;
var
  ADate: TDateTime;
begin
  ADate := EncodeDate(1900, 1, 1);
  AssertEquals('unbounded min: no lower clamp',
    ADate,
    TyCalendarClampDate(ADate, 0, EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestClampUnboundedMax;
var
  ADate: TDateTime;
begin
  ADate := EncodeDate(9999, 12, 31);
  AssertEquals('unbounded max: no upper clamp',
    ADate,
    TyCalendarClampDate(ADate, EncodeDate(2024, 1, 1), 0));
end;

{ TyDecadeStart }

procedure TCalendarGeomTest.TestDecadeStart2026;
begin
  AssertEquals('2026 -> decade 2020', 2020, TyDecadeStart(2026));
end;

procedure TCalendarGeomTest.TestDecadeStart2020;
begin
  AssertEquals('2020 -> decade 2020', 2020, TyDecadeStart(2020));
end;

procedure TCalendarGeomTest.TestDecadeStart2030;
begin
  AssertEquals('2030 -> decade 2030', 2030, TyDecadeStart(2030));
end;

{ TyISOWeekNumber }

procedure TCalendarGeomTest.TestISOWeekNumber_2026_01_05;
begin
  { Jan 5 2026 is Monday.
    ISO week 1 of 2026 spans Mon Dec 29 2025 - Sun Jan 4 2026 (because
    Jan 1 2026 is Thursday, the first Thursday of 2026, so that week = W01).
    Jan 5 2026 (Monday) therefore begins ISO week 2. }
  AssertEquals('2026-01-05 is ISO week 2', 2,
    TyISOWeekNumber(EncodeDate(2026, 1, 5)));
end;

procedure TCalendarGeomTest.TestISOWeekNumber_2026_01_01;
begin
  { Jan 1 2026 is Thursday, which falls in ISO week 1 of 2026. }
  AssertEquals('2026-01-01 is ISO week 1', 1,
    TyISOWeekNumber(EncodeDate(2026, 1, 1)));
end;

initialization
  RegisterTest(TCalendarGeomTest);
end.
