unit test.calendar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, DateUtils, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Calendar;

type

  { Probe: exposes RenderTo and synthetic key/mouse dispatch }
  TTyCalendarProbe = class(TTyCalendar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SimulateKeyDown(var Key: Word);
    procedure SimulateMouseDown(X, Y: Integer);
  end;

  TCalendarChangeCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  TCalendarAcceptCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  { B1: pure math tests (unchanged from the previous task) }

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
    procedure TestISOWeekNumber_2026_01_05;
    procedure TestISOWeekNumber_2026_01_01;

    { TyCalendarHitCell }
    procedure TestHitCellCenter;
    procedure TestHitCellTopLeft;
    procedure TestHitCellBottomRight;
    procedure TestHitCellOutsideLeft;
    procedure TestHitCellOutsideTop;
    procedure TestHitCellOutsideRight;
    procedure TestHitCellOutsideBottom;
    procedure TestHitCellExactFirstPixel;
  end;

  { B2: control behaviour tests }

  TCalendarControlTest = class(TTestCase)
  private
    FForm: TForm;
    FCal: TTyCalendarProbe;
    FCounter: TCalendarChangeCounter;
    FAccept: TCalendarAcceptCounter;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestArrowRightThenEnterSelectsAndFires;
    procedure TestArrowLeftAcrossMonthBoundary;
    procedure TestOutOfRangeDateNotSelectable;
    procedure TestMaxDateClampsSelection;
    procedure TestPageDownAdvancesViewMonth;
    procedure TestPageUpRetreatsViewMonth;
    procedure TestHomeSelectsFirstDay;
    procedure TestEndSelectsLastDay;
    procedure TestReadOnlyBlocksKeyboard;
    procedure TestOnChangeOnlyOnRealChange;
    procedure TestMouseClickSelectsDay;
    procedure TestMouseClickPrevArrow;
    procedure TestMouseClickNextArrow;
    procedure TestMaxDateTightenReClampsDate;
    procedure TestMinDateTightenReClampsDate;
    procedure TestMouseClickFiresOnAccept;
    procedure TestEnterFiresOnAcceptNotOnChange;
  end;

  { B2: pixel rendering test }

  TCalendarPixelTest = class(TTestCase)
  published
    procedure TestSelectedCellIsBlue;
  end;

  { B3: zoom pure-function tests }

  TCalendarZoomTest = class(TTestCase)
  published
    { TyCalendarZoomOut chain: Days→Months→Years→Decades→Decades (cap) }
    procedure TestZoomOutDaysToMonths;
    procedure TestZoomOutMonthsToYears;
    procedure TestZoomOutYearsToDecades;
    procedure TestZoomOutDecadesCapped;
    { TyCalendarZoomIn chain: Decades→Years→Months→Days→Days (cap) }
    procedure TestZoomInDecadesToYears;
    procedure TestZoomInYearsToMonths;
    procedure TestZoomInMonthsToDays;
    procedure TestZoomInDaysCapped;
    { Full round-trips }
    procedure TestZoomOutFullChain;
    procedure TestZoomInFullChain;
  end;

  { B3: behaviour tests (probe-based) }

  TCalendarDrillDownTest = class(TTestCase)
  private
    FForm: TForm;
    FCal: TTyCalendarProbe;
    FViewChangeCount: Integer;
    procedure HandleViewChange(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Title click in Days view zooms to Months }
    procedure TestTitleClickDaysToMonths;
    { Title click in Months zooms to Years }
    procedure TestTitleClickMonthsToYears;
    { Title click in Years zooms to Decades }
    procedure TestTitleClickYearsToDecades;
    { Title click in Decades stays at Decades (cap) }
    procedure TestTitleClickDecadesCapped;
    { OnViewChange fires on each zoom }
    procedure TestOnViewChangeFires;
    { Clicking a month cell in Months view zooms to Days of that month;
      Date does NOT change }
    procedure TestMonthCellClickZoomsToDays;
    { Render smoke tests: no exception for non-Days views }
    procedure TestRenderMonthsNoException;
    procedure TestRenderYearsNoException;
    procedure TestRenderDecadesNoException;
  end;

implementation

{ TCalendarChangeCounter }

procedure TCalendarChangeCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

procedure TCalendarAcceptCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

{ TTyCalendarProbe }

procedure TTyCalendarProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyCalendarProbe.SimulateKeyDown(var Key: Word);
begin
  KeyDown(Key, []);
end;

procedure TTyCalendarProbe.SimulateMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

{ TCalendarGeomTest — B1 pure math tests }

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

procedure TCalendarGeomTest.TestGridHas42Entries;
var
  Grid: TTyDateGrid;
begin
  Grid := TyCalendarMonthGrid(2024, 2, wdSunday);
  AssertTrue('grid[0] valid', Grid[0] <> 0);
  AssertTrue('grid[41] valid', Grid[41] <> 0);
  AssertTrue('grid monotone', Grid[41] > Grid[0]);
end;

procedure TCalendarGeomTest.TestGridFirstCellBeforeOrOnFirst;
var
  Grid: TTyDateGrid;
  First: TDateTime;
begin
  Grid  := TyCalendarMonthGrid(2024, 2, wdSunday);
  First := EncodeDate(2024, 2, 1);
  AssertTrue('grid[0] <= Feb 1 2024', Grid[0] <= First);
end;

procedure TCalendarGeomTest.TestGridLastCellAfterOrOnLast;
var
  Grid: TTyDateGrid;
  Last: TDateTime;
begin
  Grid := TyCalendarMonthGrid(2024, 2, wdSunday);
  Last := EncodeDate(2024, 2, 29);
  AssertTrue('grid[41] >= Feb 29 2024', Grid[41] >= Last);
end;

procedure TCalendarGeomTest.TestFeb2024LeapContains29;
var
  Grid: TTyDateGrid;
  Target: TDateTime;
  Found: Boolean;
  i: Integer;
begin
  Grid   := TyCalendarMonthGrid(2024, 2, wdSunday);
  Target := EncodeDate(2024, 2, 29);
  Found  := False;
  for i := 0 to 41 do
    if Grid[i] = Target then begin Found := True; Break; end;
  AssertTrue('Feb 29 2024 is in the grid', Found);
end;

procedure TCalendarGeomTest.TestFirstDaySundayVsMonday;
var
  GridSun, GridMon: TTyDateGrid;
begin
  GridSun := TyCalendarMonthGrid(2024, 2, wdSunday);
  GridMon := TyCalendarMonthGrid(2024, 2, wdMonday);
  AssertEquals('Sunday-first grid[0] = Jan 28 2024',
    EncodeDate(2024, 1, 28), GridSun[0]);
  AssertEquals('Monday-first grid[0] = Jan 29 2024',
    EncodeDate(2024, 1, 29), GridMon[0]);
  AssertTrue('grids differ at [0]', GridSun[0] <> GridMon[0]);
end;

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
  AssertTrue('unbounded min: any lower date accepted',
    TyCalendarInRange(EncodeDate(1900, 1, 1), 0, EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestInRangeUnboundedMax;
begin
  AssertTrue('unbounded max: any higher date accepted',
    TyCalendarInRange(EncodeDate(9999, 12, 31), EncodeDate(2024, 1, 1), 0));
end;

procedure TCalendarGeomTest.TestInRangeBothUnbounded;
begin
  AssertTrue('both unbound: always in range',
    TyCalendarInRange(EncodeDate(2024, 6, 15), 0, 0));
end;

procedure TCalendarGeomTest.TestClampBelowMinClampsToMin;
var
  AMin: TDateTime;
begin
  AMin := EncodeDate(2024, 1, 2);
  AssertEquals('below min clamps to min', AMin,
    TyCalendarClampDate(EncodeDate(2024, 1, 1), AMin, EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestClampAboveMaxClampsToMax;
var
  AMax: TDateTime;
begin
  AMax := EncodeDate(2024, 12, 31);
  AssertEquals('above max clamps to max', AMax,
    TyCalendarClampDate(EncodeDate(2025, 1, 1), EncodeDate(2024, 1, 1), AMax));
end;

procedure TCalendarGeomTest.TestClampWithinRangeUnchanged;
var
  ADate: TDateTime;
begin
  ADate := EncodeDate(2024, 6, 15);
  AssertEquals('within range is unchanged', ADate,
    TyCalendarClampDate(ADate, EncodeDate(2024, 1, 1), EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestClampUnboundedMin;
var
  ADate: TDateTime;
begin
  ADate := EncodeDate(1900, 1, 1);
  AssertEquals('unbounded min: no lower clamp', ADate,
    TyCalendarClampDate(ADate, 0, EncodeDate(2024, 12, 31)));
end;

procedure TCalendarGeomTest.TestClampUnboundedMax;
var
  ADate: TDateTime;
begin
  ADate := EncodeDate(9999, 12, 31);
  AssertEquals('unbounded max: no upper clamp', ADate,
    TyCalendarClampDate(ADate, EncodeDate(2024, 1, 1), 0));
end;

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

procedure TCalendarGeomTest.TestISOWeekNumber_2026_01_05;
begin
  AssertEquals('2026-01-05 is ISO week 2', 2,
    TyISOWeekNumber(EncodeDate(2026, 1, 5)));
end;

procedure TCalendarGeomTest.TestISOWeekNumber_2026_01_01;
begin
  AssertEquals('2026-01-01 is ISO week 1', 1,
    TyISOWeekNumber(EncodeDate(2026, 1, 1)));
end;

{ TyCalendarHitCell tests.
  Test grid: Rect(10, 20, 10+7*30, 20+6*25) = Rect(10,20,220,170).
  ColW=30, RowH=25, 7 cols, 6 rows.
  Cell (col, row) -> index = row*7+col.
}
const
  HIT_W  = 30;
  HIT_H  = 25;
  HIT_OX = 10;
  HIT_OY = 20;

function MakeHitGrid: TRect;
begin
  Result := Rect(HIT_OX, HIT_OY, HIT_OX + 7 * HIT_W, HIT_OY + 6 * HIT_H);
end;

procedure TCalendarGeomTest.TestHitCellCenter;
{ Centre of grid -> cell(3,3) = index 24. }
var
  gr: TRect;
  cx, cy: Integer;
begin
  gr := MakeHitGrid;
  cx := HIT_OX + 3 * HIT_W + HIT_W div 2;  // 10+90+15 = 115
  cy := HIT_OY + 3 * HIT_H + HIT_H div 2;  // 20+75+12 = 107
  AssertEquals('hit grid centre -> index 24', 24, TyCalendarHitCell(gr, 7, 6, cx, cy));
end;

procedure TCalendarGeomTest.TestHitCellTopLeft;
var gr: TRect;
begin
  gr := MakeHitGrid;
  AssertEquals('top-left pixel -> index 0', 0, TyCalendarHitCell(gr, 7, 6, HIT_OX, HIT_OY));
end;

procedure TCalendarGeomTest.TestHitCellBottomRight;
var gr: TRect;
begin
  gr := MakeHitGrid;
  AssertEquals('bottom-right pixel -> index 41',
    41, TyCalendarHitCell(gr, 7, 6, gr.Right - 1, gr.Bottom - 1));
end;

procedure TCalendarGeomTest.TestHitCellOutsideLeft;
var gr: TRect;
begin
  gr := MakeHitGrid;
  AssertEquals('left of grid -> -1',
    -1, TyCalendarHitCell(gr, 7, 6, HIT_OX - 1, HIT_OY + 10));
end;

procedure TCalendarGeomTest.TestHitCellOutsideTop;
var gr: TRect;
begin
  gr := MakeHitGrid;
  AssertEquals('above grid -> -1',
    -1, TyCalendarHitCell(gr, 7, 6, HIT_OX + 10, HIT_OY - 1));
end;

procedure TCalendarGeomTest.TestHitCellOutsideRight;
var gr: TRect;
begin
  gr := MakeHitGrid;
  AssertEquals('right of grid -> -1',
    -1, TyCalendarHitCell(gr, 7, 6, gr.Right, HIT_OY + 10));
end;

procedure TCalendarGeomTest.TestHitCellOutsideBottom;
var gr: TRect;
begin
  gr := MakeHitGrid;
  AssertEquals('below grid -> -1',
    -1, TyCalendarHitCell(gr, 7, 6, HIT_OX + 10, gr.Bottom));
end;

procedure TCalendarGeomTest.TestHitCellExactFirstPixel;
{ Top-left pixel of cell(col=2,row=1) -> index 9. }
var
  gr: TRect;
  cx, cy: Integer;
begin
  gr := MakeHitGrid;
  cx := HIT_OX + 2 * HIT_W;  // 10+60 = 70
  cy := HIT_OY + 1 * HIT_H;  // 20+25 = 45
  AssertEquals('first pixel of cell(2,1) -> index 9',
    9, TyCalendarHitCell(gr, 7, 6, cx, cy));
end;

{ TCalendarControlTest }

procedure TCalendarControlTest.SetUp;
begin
  FCounter := TCalendarChangeCounter.Create;
  FAccept  := TCalendarAcceptCounter.Create;
  FForm    := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 400);
  FCal := TTyCalendarProbe.Create(FForm);
  FCal.Parent := FForm;
  FCal.SetBounds(0, 0, 240, 220);
  FCal.Font.PixelsPerInch := 96;
  FCal.OnChange := @FCounter.Handle;
  FCal.OnAccept := @FAccept.Handle;
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;
  FAccept.Count  := 0;
end;

procedure TCalendarControlTest.TearDown;
begin
  FForm.Free;
  FCounter.Free;
  FAccept.Free;
end;

procedure TCalendarControlTest.TestArrowRightThenEnterSelectsAndFires;
{ VK_RIGHT advances by 1 day and fires OnChange exactly once.
  VK_RETURN then fires OnAccept (accept/commit) but must NOT re-fire OnChange. }
var
  key: Word;
  startDate: TDateTime;
begin
  startDate := DateOf(FCal.Date);
  FCounter.Count := 0;
  FAccept.Count  := 0;

  key := VK_RIGHT;
  FCal.SimulateKeyDown(key);
  AssertEquals('date advanced by 1 day', DateOf(startDate + 1), DateOf(FCal.Date));
  AssertEquals('OnChange fired once after Right', 1, FCounter.Count);
  AssertEquals('OnAccept NOT fired on arrow', 0, FAccept.Count);

  key := VK_RETURN;
  FCal.SimulateKeyDown(key);
  AssertEquals('OnChange must NOT re-fire on Enter', 1, FCounter.Count);
  AssertEquals('OnAccept fired once on Enter', 1, FAccept.Count);
end;

procedure TCalendarControlTest.TestArrowLeftAcrossMonthBoundary;
var
  key: Word;
begin
  FCal.Date := EncodeDate(2026, 6, 1);
  FCounter.Count := 0;

  key := VK_LEFT;
  FCal.SimulateKeyDown(key);

  AssertEquals('date is May 31', DateOf(EncodeDate(2026, 5, 31)), DateOf(FCal.Date));
  AssertEquals('OnChange fired once', 1, FCounter.Count);
end;

procedure TCalendarControlTest.TestOutOfRangeDateNotSelectable;
{ MaxDate = June 20; starting at June 20, Right arrow should be a no-op. }
var
  key: Word;
begin
  FCal.MaxDate := EncodeDate(2026, 6, 20);
  FCal.Date    := EncodeDate(2026, 6, 20);
  FCounter.Count := 0;

  key := VK_RIGHT;
  FCal.SimulateKeyDown(key);

  AssertEquals('date unchanged at MaxDate', DateOf(EncodeDate(2026, 6, 20)), DateOf(FCal.Date));
  AssertEquals('OnChange NOT fired', 0, FCounter.Count);
end;

procedure TCalendarControlTest.TestMaxDateClampsSelection;
{ Setting Date to a value beyond MaxDate should clamp. }
begin
  FCal.MaxDate := EncodeDate(2026, 6, 10);
  FCounter.Count := 0;
  FCal.Date := EncodeDate(2026, 6, 25);
  AssertEquals('date clamped to MaxDate', DateOf(EncodeDate(2026, 6, 10)), DateOf(FCal.Date));
end;

procedure TCalendarControlTest.TestPageDownAdvancesViewMonth;
{ PageDown should advance the view month and also move the date by 1 month. }
var
  key: Word;
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;

  key := VK_NEXT;
  FCal.SimulateKeyDown(key);

  AssertEquals('date moved to July', 7, MonthOf(FCal.Date));
  AssertEquals('day preserved', 15, DayOf(FCal.Date));
end;

procedure TCalendarControlTest.TestPageUpRetreatsViewMonth;
var
  key: Word;
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;

  key := VK_PRIOR;
  FCal.SimulateKeyDown(key);

  AssertEquals('date moved to May', 5, MonthOf(FCal.Date));
  AssertEquals('day preserved', 15, DayOf(FCal.Date));
end;

procedure TCalendarControlTest.TestHomeSelectsFirstDay;
var
  key: Word;
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;

  key := VK_HOME;
  FCal.SimulateKeyDown(key);

  AssertEquals('Home: day = 1', 1, DayOf(FCal.Date));
  AssertEquals('Home: month = 6', 6, MonthOf(FCal.Date));
  AssertEquals('OnChange fired exactly once', 1, FCounter.Count);
end;

procedure TCalendarControlTest.TestEndSelectsLastDay;
var
  key: Word;
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;

  key := VK_END;
  FCal.SimulateKeyDown(key);

  AssertEquals('End: day = 30 (June has 30 days)', 30, DayOf(FCal.Date));
  AssertEquals('End: month = 6', 6, MonthOf(FCal.Date));
  AssertEquals('OnChange fired exactly once', 1, FCounter.Count);
end;

procedure TCalendarControlTest.TestReadOnlyBlocksKeyboard;
var
  key: Word;
begin
  FCal.ReadOnly := True;
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;

  key := VK_RIGHT;
  FCal.SimulateKeyDown(key);

  AssertEquals('ReadOnly: date unchanged', DateOf(EncodeDate(2026, 6, 15)), DateOf(FCal.Date));
  AssertEquals('ReadOnly: OnChange NOT fired', 0, FCounter.Count);
end;

procedure TCalendarControlTest.TestOnChangeOnlyOnRealChange;
{ Each arrow press that actually changes the date fires exactly once. }
var
  key: Word;
begin
  FCal.Date := EncodeDate(2026, 6, 14);
  FCounter.Count := 0;

  key := VK_RIGHT;
  FCal.SimulateKeyDown(key);
  AssertEquals('1 change after first Right', 1, FCounter.Count);

  key := VK_RIGHT;
  FCal.SimulateKeyDown(key);
  AssertEquals('2 changes after second Right', 2, FCounter.Count);
end;

procedure TCalendarControlTest.TestMouseClickSelectsDay;
{ June 2026, Sun-first, 240x220 at 96ppi:
    HeaderH=28, WeekdayH=20, WkNumW=0, ColW=34, RowH=28.
    GridTop=48. GridLeft=0.
  June 20 2026: grid[20] (grid[0]=May31, +20days=June20).
    row=2, col=6.
    CellLeft=6*34=204, CellTop=48+2*28=104.
    Centre: x=204+17=221, y=104+14=118.
  Note: 7*34=238 < 240, so col 6 runs [204..238). x=221 is valid.
}
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;

  FCal.SimulateMouseDown(221, 118);

  AssertEquals('click selected June 20', DateOf(EncodeDate(2026, 6, 20)), DateOf(FCal.Date));
  AssertEquals('OnChange fired once', 1, FCounter.Count);
  AssertEquals('OnAccept fired once on click', 1, FAccept.Count);
end;

procedure TCalendarControlTest.TestMouseClickPrevArrow;
{ Left arrow occupies x in [0, HeaderH) = [0,28), y in [0,28). Click (14,14). }
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;

  FCal.SimulateMouseDown(14, 14);

  { View should retreat to May but date remains June 15 until a cell is clicked. }
  AssertEquals('date unchanged', DateOf(EncodeDate(2026, 6, 15)), DateOf(FCal.Date));
  AssertEquals('OnChange NOT fired', 0, FCounter.Count);
end;

procedure TCalendarControlTest.TestMouseClickNextArrow;
{ Right arrow: x in [Width-HeaderH, Width) = [212,240), y in [0,28). Click (226,14). }
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;

  FCal.SimulateMouseDown(226, 14);

  AssertEquals('date unchanged', DateOf(EncodeDate(2026, 6, 15)), DateOf(FCal.Date));
  AssertEquals('OnChange NOT fired', 0, FCounter.Count);
end;

procedure TCalendarControlTest.TestMaxDateTightenReClampsDate;
{ Setting MaxDate below the current Date must re-clamp Date to MaxDate. }
begin
  FCal.Date    := EncodeDate(2026, 6, 25);
  FCounter.Count := 0;
  FCal.MaxDate := EncodeDate(2026, 6, 10);
  AssertEquals('Date clamped to new MaxDate',
    DateOf(EncodeDate(2026, 6, 10)), DateOf(FCal.Date));
end;

procedure TCalendarControlTest.TestMinDateTightenReClampsDate;
{ Setting MinDate above the current Date must re-clamp Date to MinDate. }
begin
  FCal.Date    := EncodeDate(2026, 6, 5);
  FCounter.Count := 0;
  FCal.MinDate := EncodeDate(2026, 6, 15);
  AssertEquals('Date clamped to new MinDate',
    DateOf(EncodeDate(2026, 6, 15)), DateOf(FCal.Date));
end;

procedure TCalendarControlTest.TestMouseClickFiresOnAccept;
{ Clicking a day-cell fires OnAccept (as well as OnChange if date changed). }
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;
  FAccept.Count  := 0;

  { Click June 20 (x=221, y=118 — same geometry as TestMouseClickSelectsDay). }
  FCal.SimulateMouseDown(221, 118);

  AssertEquals('click selected June 20', DateOf(EncodeDate(2026, 6, 20)), DateOf(FCal.Date));
  AssertEquals('OnChange fired once on click', 1, FCounter.Count);
  AssertEquals('OnAccept fired once on click', 1, FAccept.Count);
end;

procedure TCalendarControlTest.TestEnterFiresOnAcceptNotOnChange;
{ Enter on an already-selected date fires OnAccept but NOT OnChange. }
var
  key: Word;
begin
  FCal.Date := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;
  FAccept.Count  := 0;

  key := VK_RETURN;
  FCal.SimulateKeyDown(key);

  AssertEquals('OnChange NOT fired on Enter (no date change)', 0, FCounter.Count);
  AssertEquals('OnAccept fired once on Enter', 1, FAccept.Count);
end;

{ TCalendarPixelTest }

procedure TCalendarPixelTest.TestSelectedCellIsBlue;
{ June 15 2026, Sun-first, 240x220 at 96ppi.
  Layout: HeaderH=28, WeekdayH=20, WkNumW=0, ColW=34, RowH=28. GridTop=48, GridLeft=0.
  June 15 = grid[15] (grid[0]=May31, +15=June15). row=2, col=1.
  CellLeft=34, CellTop=48+56=104, CellRight=68, CellBottom=132.
  Scan x in [34..67], y in [104..131].
  #3B82F6 = R=59 G=130 B=246; blue >> red by a large margin.
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  Cal: TTyCalendarProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
  FoundBlue: Boolean;
const
  BMP_W = 240; BMP_H = 220; APPI = 96;
  SEL_L = 34; SEL_T = 104; SEL_R = 68; SEL_B = 132;
begin
  Ctl  := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp  := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCalendar { background: #FFFFFF; color: #111111; }' +
      'TyCalendarCell:selected { background: #3B82F6; color: #FFFFFF; }');

    Cal := TTyCalendarProbe.Create(Form);
    Cal.Parent     := Form;
    Cal.Controller := Ctl;
    Cal.SetBounds(0, 0, BMP_W, BMP_H);
    Cal.Font.PixelsPerInch := APPI;
    Cal.Date := EncodeDate(2026, 6, 15);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(BMP_W, BMP_H);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, BMP_W, BMP_H);

    Cal.RenderTo(Bmp.Canvas, Rect(0, 0, BMP_W, BMP_H), APPI);

    Reread := TBGRABitmap.Create(Bmp);
    try
      FoundBlue := False;
      for x := SEL_L to SEL_R - 1 do
      begin
        for y := SEL_T to SEL_B - 1 do
        begin
          px := Reread.GetPixel(x, y);
          { #3B82F6: B=246, R=59. Threshold: blue > red+50 AND blue > 150. }
          if (px.blue > px.red + 50) and (px.blue > 150) then
          begin
            FoundBlue := True;
            Break;
          end;
        end;
        if FoundBlue then Break;
      end;
      AssertTrue(
        Format('expected blue pixel (B>R+50, B>150) in selected cell [x=%d..%d, y=%d..%d]',
               [SEL_L, SEL_R - 1, SEL_T, SEL_B - 1]),
        FoundBlue);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ TCalendarZoomTest — B3 pure-function tests }

procedure TCalendarZoomTest.TestZoomOutDaysToMonths;
begin
  AssertEquals('Days -> Months', Ord(cvmMonths), Ord(TyCalendarZoomOut(cvmDays)));
end;

procedure TCalendarZoomTest.TestZoomOutMonthsToYears;
begin
  AssertEquals('Months -> Years', Ord(cvmYears), Ord(TyCalendarZoomOut(cvmMonths)));
end;

procedure TCalendarZoomTest.TestZoomOutYearsToDecades;
begin
  AssertEquals('Years -> Decades', Ord(cvmDecades), Ord(TyCalendarZoomOut(cvmYears)));
end;

procedure TCalendarZoomTest.TestZoomOutDecadesCapped;
begin
  AssertEquals('Decades capped at Decades', Ord(cvmDecades), Ord(TyCalendarZoomOut(cvmDecades)));
end;

procedure TCalendarZoomTest.TestZoomInDecadesToYears;
begin
  AssertEquals('Decades -> Years', Ord(cvmYears), Ord(TyCalendarZoomIn(cvmDecades)));
end;

procedure TCalendarZoomTest.TestZoomInYearsToMonths;
begin
  AssertEquals('Years -> Months', Ord(cvmMonths), Ord(TyCalendarZoomIn(cvmYears)));
end;

procedure TCalendarZoomTest.TestZoomInMonthsToDays;
begin
  AssertEquals('Months -> Days', Ord(cvmDays), Ord(TyCalendarZoomIn(cvmMonths)));
end;

procedure TCalendarZoomTest.TestZoomInDaysCapped;
begin
  AssertEquals('Days capped at Days', Ord(cvmDays), Ord(TyCalendarZoomIn(cvmDays)));
end;

procedure TCalendarZoomTest.TestZoomOutFullChain;
{ Days → 3 zooms out → Decades, 4th stays at Decades }
var v: TTyCalView;
begin
  v := cvmDays;
  v := TyCalendarZoomOut(v); AssertEquals('step1=Months',  Ord(cvmMonths),  Ord(v));
  v := TyCalendarZoomOut(v); AssertEquals('step2=Years',   Ord(cvmYears),   Ord(v));
  v := TyCalendarZoomOut(v); AssertEquals('step3=Decades', Ord(cvmDecades), Ord(v));
  v := TyCalendarZoomOut(v); AssertEquals('step4=Decades', Ord(cvmDecades), Ord(v));
end;

procedure TCalendarZoomTest.TestZoomInFullChain;
{ Decades → 3 zooms in → Days, 4th stays at Days }
var v: TTyCalView;
begin
  v := cvmDecades;
  v := TyCalendarZoomIn(v); AssertEquals('step1=Years',  Ord(cvmYears),  Ord(v));
  v := TyCalendarZoomIn(v); AssertEquals('step2=Months', Ord(cvmMonths), Ord(v));
  v := TyCalendarZoomIn(v); AssertEquals('step3=Days',   Ord(cvmDays),   Ord(v));
  v := TyCalendarZoomIn(v); AssertEquals('step4=Days',   Ord(cvmDays),   Ord(v));
end;

{ TCalendarDrillDownTest — B3 behaviour tests }

procedure TCalendarDrillDownTest.HandleViewChange(Sender: TObject);
begin
  Inc(FViewChangeCount);
end;

procedure TCalendarDrillDownTest.SetUp;
begin
  FViewChangeCount := 0;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 400);
  FCal := TTyCalendarProbe.Create(FForm);
  FCal.Parent := FForm;
  FCal.SetBounds(0, 0, 240, 220);
  FCal.Font.PixelsPerInch := 96;
  FCal.OnViewChange := @HandleViewChange;
  FCal.Date := EncodeDate(2026, 6, 15);
end;

procedure TCalendarDrillDownTest.TearDown;
begin
  FForm.Free;
end;

procedure TCalendarDrillDownTest.TestTitleClickDaysToMonths;
{ In Days view, clicking the title area (centre of header) should zoom to Months.
  Layout at 96ppi, 240x220: HeaderH=28, ArrowW=28, TitleRect=[28, 0, 212, 28].
  Click at (120, 14) = centre of title. }
begin
  AssertEquals('start at Days', Ord(cvmDays), Ord(FCal.ViewMode));
  FCal.SimulateMouseDown(120, 14);
  AssertEquals('after title click: Months', Ord(cvmMonths), Ord(FCal.ViewMode));
end;

procedure TCalendarDrillDownTest.TestTitleClickMonthsToYears;
begin
  FCal.SimulateMouseDown(120, 14);  // Days -> Months
  FViewChangeCount := 0;
  FCal.SimulateMouseDown(120, 14);  // Months -> Years
  AssertEquals('after 2nd title click: Years', Ord(cvmYears), Ord(FCal.ViewMode));
end;

procedure TCalendarDrillDownTest.TestTitleClickYearsToDecades;
begin
  FCal.SimulateMouseDown(120, 14);  // Days -> Months
  FCal.SimulateMouseDown(120, 14);  // Months -> Years
  FViewChangeCount := 0;
  FCal.SimulateMouseDown(120, 14);  // Years -> Decades
  AssertEquals('after 3rd title click: Decades', Ord(cvmDecades), Ord(FCal.ViewMode));
end;

procedure TCalendarDrillDownTest.TestTitleClickDecadesCapped;
{ 4th title click stays at Decades (no further zoom). }
begin
  FCal.SimulateMouseDown(120, 14);
  FCal.SimulateMouseDown(120, 14);
  FCal.SimulateMouseDown(120, 14);
  FViewChangeCount := 0;
  FCal.SimulateMouseDown(120, 14);  // Decades -> Decades (capped)
  AssertEquals('stays at Decades', Ord(cvmDecades), Ord(FCal.ViewMode));
  AssertEquals('OnViewChange NOT fired when capped', 0, FViewChangeCount);
end;

procedure TCalendarDrillDownTest.TestOnViewChangeFires;
{ Each actual zoom step fires OnViewChange exactly once. }
begin
  FViewChangeCount := 0;
  FCal.SimulateMouseDown(120, 14);  // Days -> Months (+1)
  FCal.SimulateMouseDown(120, 14);  // Months -> Years (+1)
  FCal.SimulateMouseDown(120, 14);  // Years -> Decades (+1)
  AssertEquals('OnViewChange fired 3 times', 3, FViewChangeCount);
end;

procedure TCalendarDrillDownTest.TestMonthCellClickZoomsToDays;
{ In Months view, clicking on a month cell should:
  - zoom ViewMode back to Days
  - set FViewMonth to the picked month
  - NOT change FDate
  Layout at 240x220, 96ppi in 4x3 mode:
    HeaderH=28, ColW=240 div 4=60, RowH=(220-28) div 3=64.
    GridRect=[0,28,240,220].
  Cell (col=0, row=0) = month 1 (January):
    centre x=30, y=28+32=60. }
var
  savedDate: TDateTime;
begin
  savedDate := FCal.Date;
  FCal.SimulateMouseDown(120, 14);  // Days -> Months
  AssertEquals('in Months', Ord(cvmMonths), Ord(FCal.ViewMode));

  // Click first cell (col=0, row=0) -> month 1 = January
  FCal.SimulateMouseDown(30, 60);

  AssertEquals('zoomed back to Days', Ord(cvmDays), Ord(FCal.ViewMode));
  AssertEquals('ViewMonth set to January', 1, Integer(FCal.ViewMonth));
  AssertEquals('Date NOT changed', DateOf(savedDate), DateOf(FCal.Date));
end;

procedure TCalendarDrillDownTest.TestRenderMonthsNoException;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 220);
    FCal.SimulateMouseDown(120, 14);  // Days -> Months
    AssertEquals('in Months view', Ord(cvmMonths), Ord(FCal.ViewMode));
    // Must not raise
    FCal.RenderTo(Bmp.Canvas, Rect(0, 0, 240, 220), 96);
    AssertTrue('render Months did not raise', True);
  finally
    Bmp.Free;
  end;
end;

procedure TCalendarDrillDownTest.TestRenderYearsNoException;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 220);
    FCal.SimulateMouseDown(120, 14);
    FCal.SimulateMouseDown(120, 14);  // -> Years
    AssertEquals('in Years view', Ord(cvmYears), Ord(FCal.ViewMode));
    FCal.RenderTo(Bmp.Canvas, Rect(0, 0, 240, 220), 96);
    AssertTrue('render Years did not raise', True);
  finally
    Bmp.Free;
  end;
end;

procedure TCalendarDrillDownTest.TestRenderDecadesNoException;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 220);
    FCal.SimulateMouseDown(120, 14);
    FCal.SimulateMouseDown(120, 14);
    FCal.SimulateMouseDown(120, 14);  // -> Decades
    AssertEquals('in Decades view', Ord(cvmDecades), Ord(FCal.ViewMode));
    FCal.RenderTo(Bmp.Canvas, Rect(0, 0, 240, 220), 96);
    AssertTrue('render Decades did not raise', True);
  finally
    Bmp.Free;
  end;
end;

initialization
  RegisterTest(TCalendarGeomTest);
  RegisterTest(TCalendarControlTest);
  RegisterTest(TCalendarPixelTest);
  RegisterTest(TCalendarZoomTest);
  RegisterTest(TCalendarDrillDownTest);
end.
