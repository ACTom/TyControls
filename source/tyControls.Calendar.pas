unit tyControls.Calendar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, DateUtils, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  TTyWeekDay = (wdSunday, wdMonday, wdTuesday, wdWednesday, wdThursday,
                wdFriday, wdSaturday);
  TTyCalView  = (cvmDays, cvmMonths, cvmYears, cvmDecades);
  TTyDateGrid = array[0..41] of TDateTime;   // 6 rows x 7 cols

  { Array of 7 day-of-week indices (0=Sunday .. 6=Saturday) in display order
    starting at AFirst. }
  TTyWeekdayOrderArray = array[0..6] of Integer;

{ Returns the 7 day-of-week indices in display order starting at AFirst.
  Result[i] = (Ord(AFirst) + i) mod 7. }
function TyWeekdayOrder(AFirst: TTyWeekDay): TTyWeekdayOrderArray;

{ Builds a 42-cell (6x7) month grid for AYear/AMonth, column 0 = AFirst weekday.
  Cells before the 1st and after the last day are filled with dates from the
  adjacent months so the grid is always exactly 42 consecutive days. }
function TyCalendarMonthGrid(AYear, AMonth: Word;
  AFirst: TTyWeekDay): TTyDateGrid;

{ Returns True when DateOf(ADate) is within [AMin, AMax].
  AMin=0 means no lower bound; AMax=0 means no upper bound. }
function TyCalendarInRange(ADate, AMin, AMax: TDateTime): Boolean;

{ Clamps ADate into [AMin, AMax].
  AMin=0 / AMax=0 mean unbounded on that side. }
function TyCalendarClampDate(ADate, AMin, AMax: TDateTime): TDateTime;

{ Returns the start year of the decade containing AYear. }
function TyDecadeStart(AYear: Integer): Integer;

{ Returns the ISO 8601 week number of ADate. }
function TyISOWeekNumber(ADate: TDateTime): Integer;

implementation

{ TyWeekdayOrder }

function TyWeekdayOrder(AFirst: TTyWeekDay): TTyWeekdayOrderArray;
var
  i: Integer;
begin
  for i := 0 to 6 do
    Result[i] := (Ord(AFirst) + i) mod 7;
end;

{ TyCalendarMonthGrid }

function TyCalendarMonthGrid(AYear, AMonth: Word;
  AFirst: TTyWeekDay): TTyDateGrid;
var
  FirstOfMonth: TDateTime;
  // DayOfWeek returns 1=Sunday..7=Saturday; convert to 0..6
  DowFirst: Integer;   // 0-based day-of-week of the 1st of the month
  LeadCells: Integer;  // blank cells before the 1st
  StartDate: TDateTime;
  i: Integer;
begin
  FirstOfMonth := EncodeDate(AYear, AMonth, 1);
  // DayOfWeek: 1=Sun..7=Sat  →  0=Sun..6=Sat
  DowFirst := DayOfWeek(FirstOfMonth) - 1;
  // How many cells precede the 1st in the grid?
  // We want column 0 to land on AFirst weekday.
  LeadCells := (DowFirst - Ord(AFirst) + 7) mod 7;
  StartDate := IncDay(FirstOfMonth, -LeadCells);
  for i := 0 to 41 do
    Result[i] := IncDay(StartDate, i);
end;

{ TyCalendarInRange }

function TyCalendarInRange(ADate, AMin, AMax: TDateTime): Boolean;
var
  D: TDateTime;
begin
  D := DateOf(ADate);
  Result :=
    ((AMin = 0) or (D >= DateOf(AMin))) and
    ((AMax = 0) or (D <= DateOf(AMax)));
end;

{ TyCalendarClampDate }

function TyCalendarClampDate(ADate, AMin, AMax: TDateTime): TDateTime;
begin
  Result := ADate;
  if (AMin <> 0) and (DateOf(Result) < DateOf(AMin)) then
    Result := AMin;
  if (AMax <> 0) and (DateOf(Result) > DateOf(AMax)) then
    Result := AMax;
end;

{ TyDecadeStart }

function TyDecadeStart(AYear: Integer): Integer;
begin
  Result := (AYear div 10) * 10;
end;

{ TyISOWeekNumber }

function TyISOWeekNumber(ADate: TDateTime): Integer;
begin
  Result := WeekOfTheYear(ADate);
end;

end.
