unit test.parity.datetime;
{ LCL parity for TTyCalendar and TTyDateTimePicker.

  Every guard here was watched RED against the pre-fix source before the fix landed;
  the failure message each one produced is recorded above it. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, DateUtils, Controls, Forms, Graphics, LCLType,
  fpcunit, testregistry, BGRABitmap,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.Calendar, tyControls.DateTimePicker;

type
  TCalProbe = class(TTyCalendar)
  public
    procedure ProbeMouseDown(X, Y: Integer);
    procedure ProbeKey(K: Word);
  end;

  TDtProbe = class(TTyDateTimePicker)
  public
    procedure ProbeChar(C: Char);
    procedure ProbeKey(K: Word);
    procedure ProbeMouseDown(X, Y: Integer);
    procedure ProbeEnter;
    { The style the control renders with -- so a test can measure the same string with
      the same font and click a pixel it can name, instead of guessing one. }
    function  ProbeStyle: TTyStyleSet;
    function  ProbeFontSize: Integer;
  end;

  TDateTimeParityTest = class(TTestCase)
  private
    FChanges: Integer;
    FDays, FMonths, FYears: Integer;
    FOrder: string;
    FChecks: Integer;
    FSavedLocaleFirst: TTyWeekDay;
    procedure CountChange(Sender: TObject);
    procedure CountDay(Sender: TObject);
    procedure CountMonth(Sender: TObject);
    procedure CountYear(Sender: TObject);
    procedure CountCheck(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Calendar }
    procedure CalendarSpillDayClickMovesToThatMonth;
    procedure CalendarNoMonthChangeRestoresTheRefusal;
    procedure CalendarWeekNumbersIsOneStorageWithTheSet;
    procedure CalendarHidingHeadingsGivesTheGridTheSpace;
    procedure CalendarHidingDayNamesGivesTheGridTheSpace;
    procedure CalendarFirstDayOfWeekFollowsTheLocale;
    procedure CalendarAcceptsLclWeekdayNames;
    procedure CalendarSelectionFiresThePerComponentEvents;
    procedure CalendarPagingAnnouncesTheMonthAndYear;
    procedure CalendarHitTestNamesEachRegion;
    procedure CalendarViewIsReportedAtLclsLevel;
    procedure CalendarLoadsAnLfmThatStillSaysWeekNumbers;
    procedure CalendarStreamingStillSurvivesAnOutOfRangeDate;
    { Picker }
    procedure PickerProgrammaticWriteIsSilentByDefault;
    procedure PickerTwoDigitYearExpandsToThisCentury;
    procedure PickerCenturyFromMovesThePivot;
    procedure PickerExplicitFourDigitYearIsLeftAlone;
    procedure PickerEscapeRevertsTheWholeEdit;
    procedure PickerEscapeAfterAProgrammaticWriteKeepsIt;
    procedure PickerMonthNameDoesNotShiftTheLaterFields;
    procedure PickerLeadingZerosOffDropsThePadding;
    procedure PickerLeadingZerosOffKeepsTheClickOnTheRightField;
    procedure PickerAlignmentMovesTheTextAndTheHitTest;
    procedure PickerMillisecondFieldIsEditable;
    procedure PickerTypedHourStaysInTheMeridiem;
    procedure PickerOnCheckBoxChangeIsTheSameEvent;
    procedure PickerTf24AndTf12AreUsablePatterns;
    procedure PickerEnabledIfUncheckedKeepsEditing;
    procedure PickerAutoCheckTicksTheBoxOnAnEdit;
    procedure PickerResetSelectionLandsOnTheFirstField;
    procedure PickerDateModeNoneGivesTheButtonColumnBack;
    procedure PickerDateModeUpDownSpinsInsteadOfDropping;
    procedure PickerAutoSizeGrowsToFitTheText;
    procedure PickerAbsoluteLimitsHoldAnUnboundedField;
    procedure PickerHalfTypedFieldDoesNotStrandTheOnesAfterIt;
  end;

implementation

procedure TCalProbe.ProbeMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TCalProbe.ProbeKey(K: Word);
var W: Word;
begin
  W := K;
  KeyDown(W, []);
end;

procedure TDtProbe.ProbeChar(C: Char);
var S: TUTF8Char;
begin
  S := C;
  UTF8KeyPress(S);
end;

procedure TDtProbe.ProbeKey(K: Word);
var W: Word;
begin
  W := K;
  KeyDown(W, []);
end;

procedure TDtProbe.ProbeMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TDtProbe.ProbeEnter;
begin
  DoEnter;
end;

{ The first y at which the calendar reports a day cell in column AX. Scanned rather
  than computed from constants: the band heights come from density tokens and the
  control's PPI, so a hardcoded row number is a test of the machine, not the control. }
function FirstDateY(C: TCalProbe; AX: Integer): Integer;
var
  y: Integer;
begin
  Result := -1;
  for y := 0 to C.Height - 1 do
    if C.HitTest(Point(AX, y)) = cpDate then Exit(y);
end;

function TDtProbe.ProbeStyle: TTyStyleSet;
begin
  Result := CurrentStyle;
end;

function TDtProbe.ProbeFontSize: Integer;
begin
  Result := ResolveFontSize(CurrentStyle);
end;

{ Pixel x, relative to the text rect's left edge, just inside the LAST character of
  AText -- measured with the control's own font so the answer is the control's. }
function RightmostTextX(P: TDtProbe; const AText: string): Integer;
var
  S: TTyStyleSet;
  Bmp: TBGRABitmap;
begin
  S := P.ProbeStyle;
  Bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(Bmp, S.FontName, P.ProbeFontSize, S.FontWeight,
      P.Font.PixelsPerInch);
    Result := MulDiv(S.Padding.Left, P.Font.PixelsPerInch, 96)
            + Bmp.TextSize(AText).cx - 1;
  finally
    Bmp.Free;
  end;
end;

{ 0..23 hour of a TDateTime -- the meridiem assertions are about the stored hour, not
  about what the field happens to render. }
function HourOf(AValue: TDateTime): Integer;
var h, m, s, ms: Word;
begin
  DecodeTime(AValue, h, m, s, ms);
  Result := h;
end;

procedure TDateTimeParityTest.CountChange(Sender: TObject);
begin
  Inc(FChanges);
  FOrder := FOrder + 'C';
end;

procedure TDateTimeParityTest.CountDay(Sender: TObject);
begin
  Inc(FDays);
  FOrder := FOrder + 'd';
end;

procedure TDateTimeParityTest.CountMonth(Sender: TObject);
begin
  Inc(FMonths);
  FOrder := FOrder + 'm';
end;

procedure TDateTimeParityTest.CountYear(Sender: TObject);
begin
  Inc(FYears);
  FOrder := FOrder + 'y';
end;

procedure TDateTimeParityTest.CountCheck(Sender: TObject);
begin
  Inc(FChecks);
end;

procedure TDateTimeParityTest.SetUp;
begin
  FChanges := 0; FDays := 0; FMonths := 0; FYears := 0; FChecks := 0;
  FOrder := '';
  { The locale answer is machine state; a test that changes it must put it back or the
    next suite inherits a calendar starting on a different day. }
  FSavedLocaleFirst := TyLocaleFirstDayOfWeek;
end;

procedure TDateTimeParityTest.TearDown;
begin
  TyLocaleFirstDayOfWeek := FSavedLocaleFirst;
end;

{ ── Calendar ─────────────────────────────────────────────────────────────── }

{ LCL's default is to JUMP to the month of a clicked spill-over day (dsNoMonthChange
  is absent from DefaultDisplaySettings, calendar.pp:46). Ours dropped the click on
  the floor -- a grey day was simply dead. }
procedure TDateTimeParityTest.CalendarSpillDayClickMovesToThatMonth;
{ June 2026, Sun-first, 240x220 @96: HeaderH=28 WeekdayH=20 ColW=34 RowH=28,
  grid top = 48, grid[0] = 31 May 2026 (row 0, col 0) -> centre (17, 62). }
var
  C: TCalProbe;
begin
  C := TCalProbe.Create(nil);
  try
    C.SetBounds(0, 0, 240, 220);
    C.FirstDayOfWeek := wdSunday;
    C.Date := EncodeDate(2026, 6, 15);
    C.ProbeMouseDown(17, 62);
    AssertEquals('clicking the spill-over day selects it',
      DateOf(EncodeDate(2026, 5, 31)), DateOf(C.Date));
    AssertEquals('and the view follows it to May', 5, C.ViewMonth);
  finally
    C.Free;
  end;
end;

{ dsNoMonthChange is LCL's opt-in refusal (calendar.pp:40). It was our unconditional
  behaviour; now it is a flag, and setting it must bring the old behaviour back exactly
  -- otherwise the "breaking change" has no migration. }
procedure TDateTimeParityTest.CalendarNoMonthChangeRestoresTheRefusal;
var
  C: TCalProbe;
begin
  C := TCalProbe.Create(nil);
  try
    C.SetBounds(0, 0, 240, 220);
    C.FirstDayOfWeek := wdSunday;
    C.DisplaySettings := C.DisplaySettings + [dsNoMonthChange];
    C.Date := EncodeDate(2026, 6, 15);
    C.ProbeMouseDown(17, 62);            { the 31 May spill cell }
    AssertEquals('the spill click is refused again',
      DateOf(EncodeDate(2026, 6, 15)), DateOf(C.Date));
    AssertEquals('and the view did not move', 6, C.ViewMonth);
  finally
    C.Free;
  end;
end;

{ WeekNumbers is now a VIEW onto DisplaySettings, not a second copy. Two fields holding
  one fact is how they end up disagreeing. }
procedure TDateTimeParityTest.CalendarWeekNumbersIsOneStorageWithTheSet;
var
  C: TTyCalendar;
begin
  C := TTyCalendar.Create(nil);
  try
    AssertFalse('off by default', C.WeekNumbers);
    AssertFalse('and the flag is out of the set',
      dsShowWeekNumbers in C.DisplaySettings);
    C.WeekNumbers := True;
    AssertTrue('the Boolean puts the flag in', dsShowWeekNumbers in C.DisplaySettings);
    C.DisplaySettings := C.DisplaySettings - [dsShowWeekNumbers];
    AssertFalse('and taking the flag out clears the Boolean', C.WeekNumbers);
  finally
    C.Free;
  end;
  { The out-of-the-box set is LCL's DefaultDisplaySettings, member for member. }
  C := TTyCalendar.Create(nil);
  try
    AssertTrue('headings on by default',  dsShowHeadings  in C.DisplaySettings);
    AssertTrue('day names on by default', dsShowDayNames  in C.DisplaySettings);
    AssertFalse('month change allowed by default',
      dsNoMonthChange in C.DisplaySettings);
    AssertFalse('week numbers off by default',
      dsShowWeekNumbers in C.DisplaySettings);
    AssertTrue('and that IS TyDefaultDisplaySettings',
      C.DisplaySettings = TyDefaultDisplaySettings);
  finally
    C.Free;
  end;
end;

{ Suppressing chrome must give the space to the grid, not leave a hole: a bare day grid
  is the whole point of dsShowHeadings being optional. }
procedure TDateTimeParityTest.CalendarHidingHeadingsGivesTheGridTheSpace;
var
  C: TCalProbe;
  WithBand, WithoutBand: Integer;
begin
  C := TCalProbe.Create(nil);
  try
    C.SetBounds(0, 0, 240, 220);
    C.FirstDayOfWeek := wdSunday;
    AssertEquals('with the band, the top-left corner is a navigation arrow',
      Ord(cpTitleBtn), Ord(C.HitTest(Point(5, 5))));
    WithBand := FirstDateY(C, 17);
    AssertTrue('the grid exists', WithBand > 0);

    C.DisplaySettings := C.DisplaySettings - [dsShowHeadings];
    AssertEquals('without it, nothing up there is a button',
      Ord(cpNoWhere), Ord(C.HitTest(Point(5, 5))));
    WithoutBand := FirstDateY(C, 17);
    AssertTrue('and the grid takes the band''s space rather than leaving a hole',
      WithoutBand < WithBand);
  finally
    C.Free;
  end;
end;

procedure TDateTimeParityTest.CalendarHidingDayNamesGivesTheGridTheSpace;
var
  C: TCalProbe;
  WithRow, WithoutRow: Integer;
begin
  C := TCalProbe.Create(nil);
  try
    C.SetBounds(0, 0, 240, 220);
    C.FirstDayOfWeek := wdSunday;
    WithRow := FirstDateY(C, 17);
    AssertTrue('the grid exists', WithRow > 0);
    { The pixel row directly above the first day cell is the day-name row -- chrome,
      not a cell, and not a title button either. }
    AssertEquals('the day-name row is not a cell',
      Ord(cpNoWhere), Ord(C.HitTest(Point(17, WithRow - 1))));

    C.DisplaySettings := C.DisplaySettings - [dsShowDayNames];
    WithoutRow := FirstDateY(C, 17);
    AssertTrue('with the row gone the grid starts higher', WithoutRow < WithRow);
  finally
    C.Free;
  end;
end;

{ The default used to be a hardcoded wdSunday, so a Monday-first locale shipped with a
  US week layout and no value meant "follow the system". }
procedure TDateTimeParityTest.CalendarFirstDayOfWeekFollowsTheLocale;
var
  C: TTyCalendar;
  Order: TTyWeekdayOrderArray;
begin
  TyLocaleFirstDayOfWeek := wdMonday;
  C := TTyCalendar.Create(nil);
  try
    AssertEquals('the default is "ask the OS"',
      Ord(wdLocaleDefault), Ord(C.FirstDayOfWeek));
    Order := TyWeekdayOrder(C.FirstDayOfWeek);
    AssertEquals('column 0 is Monday on a Monday-first machine',
      Ord(wdMonday), Order[0]);
    TyLocaleFirstDayOfWeek := wdSunday;
    Order := TyWeekdayOrder(C.FirstDayOfWeek);
    AssertEquals('and Sunday on a Sunday-first one', Ord(wdSunday), Order[0]);
    { An explicit value still wins over the locale -- otherwise the property is a lie. }
    C.FirstDayOfWeek := wdMonday;
    TyLocaleFirstDayOfWeek := wdSunday;
    Order := TyWeekdayOrder(C.FirstDayOfWeek);
    AssertEquals('an explicit value is not overridden', Ord(wdMonday), Order[0]);
  finally
    C.Free;
  end;
end;

{ `Cal.FirstDayOfWeek := dowMonday` is what a ported unit says. }
procedure TDateTimeParityTest.CalendarAcceptsLclWeekdayNames;
var
  C: TTyCalendar;
begin
  C := TTyCalendar.Create(nil);
  try
    C.FirstDayOfWeek := dowMonday;
    AssertEquals('dowMonday is wdMonday', Ord(wdMonday), Ord(C.FirstDayOfWeek));
    C.FirstDayOfWeek := dowSunday;
    AssertEquals('dowSunday is wdSunday', Ord(wdSunday), Ord(C.FirstDayOfWeek));
    C.FirstDayOfWeek := dowDefault;
    AssertEquals('dowDefault is the locale member',
      Ord(wdLocaleDefault), Ord(C.FirstDayOfWeek));
  finally
    C.Free;
  end;
end;

{ LCL fires year, month, day, then OnChange (calendar.pp LMChanged :443-453). Order is
  load-bearing: a handler that reloads on OnMonthChanged and reads Date in OnChange
  depends on it. }
procedure TDateTimeParityTest.CalendarSelectionFiresThePerComponentEvents;
var
  C: TCalProbe;
begin
  C := TCalProbe.Create(nil);
  try
    C.FirstDayOfWeek := wdSunday;
    C.Date := EncodeDate(2026, 6, 15);
    C.OnDayChanged   := @CountDay;
    C.OnMonthChanged := @CountMonth;
    C.OnYearChanged  := @CountYear;
    C.OnChange       := @CountChange;

    C.ProbeKey(VK_RIGHT);                  { 15 -> 16 June: day only }
    AssertEquals('day moved', 1, FDays);
    AssertEquals('month did not', 0, FMonths);
    AssertEquals('year did not', 0, FYears);
    AssertEquals('and OnChange followed it', 'dC', FOrder);

    FOrder := ''; FDays := 0;
    C.Date := EncodeDate(2026, 12, 31);    { a code write must not fire anything }
    AssertEquals('a programmatic Date write is not a selection event', '', FOrder);

    C.ProbeKey(VK_RIGHT);                  { 31 Dec 2026 -> 1 Jan 2027 }
    AssertEquals('all three moved, in LCL''s order, then OnChange', 'ymdC', FOrder);
  finally
    C.Free;
  end;
end;

{ Paging the header arrows used to raise nothing at all, so "load this month's
  appointments" had no hook. }
procedure TDateTimeParityTest.CalendarPagingAnnouncesTheMonthAndYear;
var
  C: TCalProbe;
begin
  C := TCalProbe.Create(nil);
  try
    C.SetBounds(0, 0, 240, 220);
    C.FirstDayOfWeek := wdSunday;
    C.Date := EncodeDate(2026, 6, 15);
    C.OnMonthChanged := @CountMonth;
    C.OnYearChanged  := @CountYear;
    C.OnChange       := @CountChange;

    C.ProbeMouseDown(226, 14);              { right arrow: June -> July }
    AssertEquals('the view moved', 7, C.ViewMonth);
    AssertEquals('the month announced itself', 1, FMonths);
    AssertEquals('the year did not', 0, FYears);
    AssertEquals('and paging is not a value change', 0, FChanges);

    C.Date := EncodeDate(2026, 12, 15);
    FMonths := 0; FYears := 0;
    C.ProbeMouseDown(226, 14);              { December -> January of the next year }
    AssertEquals('rolling the year announces the year', 1, FYears);
    AssertEquals('and the month', 1, FMonths);
  finally
    C.Free;
  end;
end;

{ The private layout maths was the only thing that could classify a point, so a host
  wanting a per-region context menu had to reimplement it -- and could not. }
procedure TDateTimeParityTest.CalendarHitTestNamesEachRegion;
var
  C: TCalProbe;
  GridY, MonthX, YearX, i: Integer;
begin
  C := TCalProbe.Create(nil);
  try
    C.SetBounds(0, 0, 240, 220);
    C.FirstDayOfWeek := wdSunday;
    C.WeekNumbers := True;
    C.Date := EncodeDate(2026, 6, 15);
    GridY := FirstDateY(C, 120);
    AssertTrue('the grid exists', GridY > 0);
    AssertEquals('left arrow',  Ord(cpTitleBtn), Ord(C.HitTest(Point(5, 14))));
    AssertEquals('right arrow', Ord(cpTitleBtn), Ord(C.HitTest(Point(235, 14))));
    AssertEquals('a day cell',  Ord(cpDate),     Ord(C.HitTest(Point(120, GridY + 2))));
    AssertEquals('the week-number column',
      Ord(cpWeekNumber), Ord(C.HitTest(Point(5, GridY + 2))));
    AssertEquals('the day-name row is chrome',
      Ord(cpNoWhere), Ord(C.HitTest(Point(120, GridY - 1))));
    { The title is 'mmmm yyyy' drawn CENTRED, so where the month ends and the year
      begins depends on the resolved font and on the locale's month names -- scan for
      them instead of naming pixels. Both must be reachable, or cpTitleMonth and
      cpTitleYear are enum members nothing ever returns. }
    MonthX := -1; YearX := -1;
    for i := 0 to 239 do
    begin
      if (MonthX < 0) and (C.HitTest(Point(i, 14)) = cpTitleMonth) then MonthX := i;
      if (YearX  < 0) and (C.HitTest(Point(i, 14)) = cpTitleYear)  then YearX  := i;
    end;
    AssertTrue('the month name in the title is namable', MonthX >= 0);
    AssertTrue('the year in the title is namable', YearX >= 0);
    AssertTrue('and the month sits left of the year', MonthX < YearX);
    AssertEquals('the gap either side of the centred text is just "the title"',
      Ord(cpTitle), Ord(C.HitTest(Point(MonthX - 1, 14))));
  finally
    C.Free;
  end;
end;

{ LCL names the level after the PAGE, we name it after the CELL, and they are one level
  apart -- cvMonth is cvmDays, not cvmMonths. A cast would answer one level out. }
procedure TDateTimeParityTest.CalendarViewIsReportedAtLclsLevel;
var
  C: TCalProbe;
begin
  C := TCalProbe.Create(nil);
  try
    C.SetBounds(0, 0, 240, 220);
    AssertEquals('a day grid is LCL''s cvMonth',
      Ord(cvMonth), Ord(C.GetCalendarView));
    C.ProbeMouseDown(120, 14);        { title click: zoom out to the months grid }
    AssertEquals('a months grid is cvYear', Ord(cvYear), Ord(C.GetCalendarView));
    C.ProbeMouseDown(120, 14);
    AssertEquals('a years grid is cvDecade', Ord(cvDecade), Ord(C.GetCalendarView));
    C.ProbeMouseDown(120, 14);
    AssertEquals('a decades grid is cvCentury', Ord(cvCentury), Ord(C.GetCalendarView));
  finally
    C.Free;
  end;
end;

{ Streams ALfm into a fresh calendar. }
function LoadCalendarLfm(const ALfm: string): TTyCalendar;
var
  Txt, Bin: TMemoryStream;
begin
  Result := TTyCalendar.Create(nil);
  Txt := TMemoryStream.Create;
  Bin := TMemoryStream.Create;
  try
    Txt.Write(ALfm[1], Length(ALfm));
    Txt.Position := 0;
    ObjectTextToBinary(Txt, Bin);
    Bin.Position := 0;
    Bin.ReadComponent(Result);
  finally
    Txt.Free;
    Bin.Free;
  end;
end;

{ WeekNumbers became a view onto DisplaySettings. Forms out there still carry the old
  Boolean line, and a property that stops streaming takes the whole form down with it. }
procedure TDateTimeParityTest.CalendarLoadsAnLfmThatStillSaysWeekNumbers;
var
  C: TTyCalendar;
begin
  C := LoadCalendarLfm(
    'object Cal1: TTyCalendar'#13#10 +
    '  WeekNumbers = True'#13#10 +
    'end'#13#10);
  try
    AssertTrue('the old Boolean line still loads', C.WeekNumbers);
    AssertTrue('and lands in the set', dsShowWeekNumbers in C.DisplaySettings);
  finally
    C.Free;
  end;
end;

{ The raising Date setter must stay carved out under csLoading. A .lfm that lists Date
  before MinDate would otherwise abort ReadComponent and the whole form would refuse to
  open -- a far worse failure than the silent clamp the raise replaced. Pinned again
  here because this pass added properties to the same published block, and declaration
  order is what decides the order the IDE writes them in. }
procedure TDateTimeParityTest.CalendarStreamingStillSurvivesAnOutOfRangeDate;
var
  C: TTyCalendar;
begin
  { BOUNDS FIRST is the ordering that actually exercises the carve-out: the date
    arrives while the range is already narrower than it, so without the csLoading
    branch SetDate raises inside ReadComponent and the whole form fails to open.
    (Date-first is harmless either way -- the calendar is still unbounded when the
    date lands -- which is why a Date-first-only guard passes a broken build.) }
  C := LoadCalendarLfm(
    'object Cal2: TTyCalendar'#13#10 +
    '  MinDate = 46200'#13#10 +
    '  MaxDate = 46300'#13#10 +
    '  Date = 46000'#13#10 +          { well outside the bounds above }
    '  DisplaySettings = [dsShowHeadings, dsShowDayNames, dsShowWeekNumbers]'#13#10 +
    'end'#13#10);
  try
    AssertTrue('the form loaded rather than raising', C <> nil);
    AssertTrue('the date was clamped into the streamed range',
      (DateOf(C.Date) >= DateOf(46200.0)) and (DateOf(C.Date) <= DateOf(46300.0)));
    AssertTrue('and the set property streamed alongside it', C.WeekNumbers);
  finally
    C.Free;
  end;

  { And the other ordering -- the one the IDE actually writes -- still loads too. }
  C := LoadCalendarLfm(
    'object Cal3: TTyCalendar'#13#10 +
    '  Date = 46000'#13#10 +
    '  MinDate = 46200'#13#10 +
    '  MaxDate = 46300'#13#10 +
    'end'#13#10);
  try
    AssertTrue('date-before-bounds loads as well', C <> nil);
    AssertTrue('and the bounds clamped it on arrival',
      DateOf(C.Date) >= DateOf(46200.0));
  finally
    C.Free;
  end;
end;

{ ── Picker ───────────────────────────────────────────────────────────────── }

{ LCL fires OnChange for USER edits only unless dtpoDoChangeOnSetDateTime is in
  Options (datetimepicker.pas:1210, :2746; cDefOptions = []). Ours fired on every
  programmatic write, so `DTP.DateTime := Rec.Due` re-entered the app's own handler. }
procedure TDateTimeParityTest.PickerProgrammaticWriteIsSilentByDefault;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    D.DateTime := EncodeDate(2026, 1, 1);
    FChanges := 0;
    D.OnChange := @CountChange;
    D.DateTime := EncodeDate(2026, 2, 2);
    AssertEquals('a code write must not call the user''s OnChange', 0, FChanges);
  finally
    D.Free;
  end;
end;

{ Typing 2 digits into the year and tabbing away stored the year 0026. LCL expands
  a short year against CenturyFrom (datetimepicker.pas:1690-1697). }
procedure TDateTimeParityTest.PickerTwoDigitYearExpandsToThisCentury;
var
  D: TDtProbe;
  Y, M, Dy: Word;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind       := dtkDate;
    D.DateFormat := 'dd/mm/yyyy';
    D.DateTime   := EncodeDate(2000, 3, 4);
    D.ProbeKey(VK_END);                 { park on the year }
    D.ProbeChar('2');
    D.ProbeChar('6');
    D.ProbeKey(VK_RETURN);              { finalize }
    DecodeDate(D.DateTime, Y, M, Dy);
    AssertEquals('two typed digits mean 2026, not the year 26', 2026, Y);
  finally
    D.Free;
  end;
end;

{ LCL snapshots the value on focus-in and Escape restores the whole snapshot
  (datetimepicker.pas:3725-3730, UndoChanges :1985-1997). Ours only dropped the
  digit buffer, so an arrow-stepped month survived the Escape. }
procedure TDateTimeParityTest.PickerEscapeRevertsTheWholeEdit;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind       := dtkDate;
    D.DateFormat := 'dd/mm/yyyy';
    D.DateTime   := EncodeDate(2026, 6, 15);
    D.ProbeEnter;                       { focus-in snapshot }
    D.ProbeKey(VK_HOME);
    D.ProbeKey(VK_UP);                  { step the day }
    AssertEquals('the step landed', DateOf(EncodeDate(2026, 6, 16)), DateOf(D.DateTime));
    D.ProbeKey(VK_ESCAPE);
    AssertEquals('Escape restores the value held at focus-in',
      DateOf(EncodeDate(2026, 6, 15)), DateOf(D.DateTime));
  finally
    D.Free;
  end;
end;

{ Segment offsets were taken from the FORMAT string, which only equals the rendered
  offsets while every field is fixed-width. 'mmmm' renders a month NAME, so every
  field after it sat at the wrong pixel: clicking the year selected the month. }
procedure TDateTimeParityTest.PickerMonthNameDoesNotShiftTheLaterFields;
var
  D: TDtProbe;
  i, Yr: Integer;
  Spans: TTySegmentArray;
  Txt: string;
begin
  D := TDtProbe.Create(nil);
  try
    D.SetBounds(0, 0, 300, 24);
    D.Kind       := dtkDate;
    D.DateFormat := 'dd mmmm yyyy';     { 'September' is 9 chars for 4 format chars }
    D.DateTime   := EncodeDate(2026, 9, 15);
    Yr := -1;
    for i := 0 to High(D.Segments) do
      if D.Segments[i].Kind = skYear then Yr := i;
    AssertTrue('the format has a year field', Yr >= 0);
    D.ProbeKey(VK_HOME);                { park on the day, so a hit must MOVE it }
    Txt := TyRenderDateTime(D.DateTime, 'dd mmmm yyyy', DefaultFormatSettings,
             True, Spans);
    { Month names are the machine's, so name the expectation the same way rather than
      pinning English -- but check the premise the test rests on: the rendered month is
      NOT four bytes wide, so rendered offsets and format offsets cannot agree. }
    AssertEquals('the month renders as a name',
      '15 ' + DefaultFormatSettings.LongMonthNames[9] + ' 2026', Txt);
    AssertTrue('premise: the month name is not 4 bytes, so the two offset models differ',
      Length(DefaultFormatSettings.LongMonthNames[9]) <> 4);
    { The last character of the rendered string is the '6' of 2026. Under the old
      format-indexed model no segment reached that far at all -- the year "span" sat
      inside the word September -- so the click resolved to nothing or to the month. }
    D.ProbeMouseDown(RightmostTextX(D, Txt), 12);
    AssertEquals('a click on the last character lands on the year', Yr, D.ActiveSeg);
  finally
    D.Free;
  end;
end;

{ The pivot has to be readable, or CenturyFrom is a property nothing consults. }
procedure TDateTimeParityTest.PickerCenturyFromMovesThePivot;

  function TypedYear(APivot: Word; const ADigits: string): Integer;
  var
    D: TDtProbe;
    i: Integer;
    Y, M, Dy: Word;
  begin
    D := TDtProbe.Create(nil);
    try
      D.Kind        := dtkDate;
      D.DateFormat  := 'dd/mm/yyyy';
      D.CenturyFrom := APivot;
      D.DateTime    := EncodeDate(2000, 3, 4);
      D.ProbeKey(VK_END);
      for i := 1 to Length(ADigits) do D.ProbeChar(ADigits[i]);
      D.ProbeKey(VK_RETURN);
      DecodeDate(D.DateTime, Y, M, Dy);
      Result := Y;
    finally
      D.Free;
    end;
  end;

begin
  AssertEquals('41 is at the 1941 pivot, so it stays in the 1900s',
    1941, TypedYear(1941, '41'));
  AssertEquals('40 is below it, so it rolls to the next century',
    2040, TypedYear(1941, '40'));
  AssertEquals('moving the pivot moves the answer', 1926, TypedYear(1900, '26'));
  AssertEquals('a single digit is short input too', 2005, TypedYear(1941, '5'));
end;

{ Three or four digits is an explicit year and must survive untouched -- expansion that
  also rewrote 1999 would be a new silent-wrong-answer in place of the old one. }
procedure TDateTimeParityTest.PickerExplicitFourDigitYearIsLeftAlone;
var
  D: TDtProbe;
  Y, M, Dy: Word;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.DateTime := EncodeDate(2000, 3, 4);
    D.ProbeKey(VK_END);
    D.ProbeChar('1'); D.ProbeChar('9'); D.ProbeChar('9'); D.ProbeChar('9');
    D.ProbeKey(VK_RETURN);
    DecodeDate(D.DateTime, Y, M, Dy);
    AssertEquals('1999 means 1999', 1999, Y);
  finally
    D.Free;
  end;
end;

{ The snapshot is retaken on a programmatic write, so Escape undoes what the USER did
  since -- not the record the host just loaded. }
procedure TDateTimeParityTest.PickerEscapeAfterAProgrammaticWriteKeepsIt;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.DateTime := EncodeDate(2026, 6, 15);
    D.ProbeEnter;
    D.DateTime := EncodeDate(2020, 1, 2);      { the host loads a record }
    D.ProbeKey(VK_ESCAPE);
    AssertEquals('Escape must not undo the host''s own write',
      DateOf(EncodeDate(2020, 1, 2)), DateOf(D.DateTime));
  finally
    D.Free;
  end;
end;

{ 'd/m/yyyy' used to be rewritten to 'dd/mm/yyyy' -- a format string that appeared to
  be ignored -- because the padding was structural rather than a choice. }
procedure TDateTimeParityTest.PickerLeadingZerosOffDropsThePadding;
var
  D: TDtProbe;
  Spans: TTySegmentArray;
  Sep: string;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.DateTime := EncodeDate(2026, 7, 5);
    Sep := DefaultFormatSettings.DateSeparator;
    AssertEquals('padded by default',
      '05' + Sep + '07' + Sep + '2026',
      TyRenderDateTime(D.DateTime, 'dd/mm/yyyy', DefaultFormatSettings, True, Spans));
    AssertEquals('and unpadded when asked',
      '5' + Sep + '7' + Sep + '2026',
      TyRenderDateTime(D.DateTime, 'dd/mm/yyyy', DefaultFormatSettings, False, Spans));
    AssertEquals('minutes and seconds stay padded -- 9:5 is not a time',
      '09:05:03',
      TyRenderDateTime(EncodeTime(9, 5, 3, 0), 'hh":"nn":"ss',
        DefaultFormatSettings, True, Spans));
  finally
    D.Free;
  end;
end;

procedure TDateTimeParityTest.PickerLeadingZerosOffKeepsTheClickOnTheRightField;
var
  D: TDtProbe;
  Spans: TTySegmentArray;
  Txt: string;
  Yr, i: Integer;
begin
  D := TDtProbe.Create(nil);
  try
    D.SetBounds(0, 0, 200, 24);
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.LeadingZeros := False;
    D.DateTime := EncodeDate(2026, 7, 5);
    Yr := -1;
    for i := 0 to High(D.Segments) do
      if D.Segments[i].Kind = skYear then Yr := i;
    D.ProbeKey(VK_HOME);
    Txt := TyRenderDateTime(D.DateTime, 'dd/mm/yyyy', DefaultFormatSettings, False, Spans);
    D.ProbeMouseDown(RightmostTextX(D, Txt), 12);
    AssertEquals('the year is still where the click says it is', Yr, D.ActiveSeg);
  finally
    D.Free;
  end;
end;

{ An alignment the mouse does not follow is worse than no alignment. }
procedure TDateTimeParityTest.PickerAlignmentMovesTheTextAndTheHitTest;
var
  D: TDtProbe;
  Spans: TTySegmentArray;
  Txt: string;
  X: Integer;
begin
  D := TDtProbe.Create(nil);
  try
    D.SetBounds(0, 0, 260, 24);          { deliberately much wider than the text }
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.DateTime := EncodeDate(2026, 7, 5);
    Txt := TyRenderDateTime(D.DateTime, 'dd/mm/yyyy', DefaultFormatSettings, True, Spans);
    { Left-justified, this X is past the end of the text and hits nothing. }
    X := 260 - MulDiv(TyFieldButtonWidth, D.Font.PixelsPerInch, 96) - 4;
    D.ProbeKey(VK_HOME);
    D.ProbeMouseDown(X, 12);
    AssertEquals('left-justified, a click at the right edge is past the text',
      0, D.ActiveSeg);
    D.Alignment := taRightJustify;
    D.ProbeMouseDown(X, 12);
    AssertEquals('right-justified, the same pixel is the last field',
      High(D.Segments), D.ActiveSeg);
  finally
    D.Free;
  end;
end;

{ The value always carried a millisecond and no UI could show or clear it. }
procedure TDateTimeParityTest.PickerMillisecondFieldIsEditable;
var
  D: TDtProbe;
  h, m, s, ms: Word;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkTime;
    D.TimeFormat := 'hh":"nn":"ss"."zzz';
    D.DateTime := EncodeTime(10, 20, 30, 400);
    D.ProbeKey(VK_END);
    AssertEquals('the last field is the millisecond',
      Ord(skMilliSec), Ord(D.Segments[D.ActiveSeg].Kind));
    D.ProbeChar('1'); D.ProbeChar('2'); D.ProbeChar('3');
    DecodeTime(D.DateTime, h, m, s, ms);
    AssertEquals('and it takes three typed digits', 123, Integer(ms));
    D.ProbeKey(VK_UP);
    DecodeTime(D.DateTime, h, m, s, ms);
    AssertEquals('and it steps', 124, Integer(ms));
  finally
    D.Free;
  end;
end;

{ In a 12-hour format the field SHOWS 1..12, so typed digits are a 12-hour reading.
  Storing them raw put the value twelve hours out with the display still agreeing. }
procedure TDateTimeParityTest.PickerTypedHourStaysInTheMeridiem;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkTime;
    D.TimeFormat := 'hh":"nn AM/PM';
    D.DateTime := EncodeTime(15, 0, 0, 0);        { 03 PM }
    D.ProbeKey(VK_HOME);
    D.ProbeChar('0'); D.ProbeChar('4');
    AssertEquals('typing 04 in the afternoon means 16:00', 16, HourOf(D.DateTime));
    D.DateTime := EncodeTime(9, 0, 0, 0);         { 09 AM }
    D.ProbeKey(VK_HOME);
    D.ProbeChar('1'); D.ProbeChar('2');
    AssertEquals('and 12 in the morning is midnight', 0, HourOf(D.DateTime));
  finally
    D.Free;
  end;
end;

procedure TDateTimeParityTest.PickerOnCheckBoxChangeIsTheSameEvent;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    D.ShowCheckBox := True;
    D.OnCheckBoxChange := @CountCheck;     { LCL's spelling }
    AssertTrue('one storage: OnChecked reads back what OnCheckBoxChange wrote',
      D.OnChecked = TNotifyEvent(@CountCheck));
    D.ProbeKey(VK_SPACE);
    AssertEquals('and it fires', 1, FChecks);
  finally
    D.Free;
  end;
end;

{ `TimeFormat := tf24` is what a ported unit says; ours is a pattern, so the names are
  the patterns that enum selects. }
procedure TDateTimeParityTest.PickerTf24AndTf12AreUsablePatterns;
var
  D: TDtProbe;
  Spans: TTySegmentArray;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkTime;
    D.DateTime := EncodeTime(15, 4, 5, 0);
    D.TimeFormat := tf24;
    AssertEquals('tf24 is a 24-hour pattern', '15:04:05',
      TyRenderDateTime(D.DateTime, tf24, DefaultFormatSettings, True, Spans));
    D.TimeFormat := tf12;
    AssertEquals('tf12 carries the meridiem', '03:04:05 PM',
      TyRenderDateTime(D.DateTime, tf12, DefaultFormatSettings, True, Spans));
  finally
    D.Free;
  end;
end;

procedure TDateTimeParityTest.PickerEnabledIfUncheckedKeepsEditing;
var
  D: TDtProbe;
  Before: TDateTime;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.DateTime := EncodeDate(2026, 6, 15);
    D.ShowCheckBox := True;
    D.Checked := False;
    Before := D.DateTime;
    D.ProbeKey(VK_HOME); D.ProbeKey(VK_UP);
    AssertEquals('unchecked is inert by default', Before, D.DateTime);
    D.Options := [dtpoEnabledIfUnchecked];
    D.ProbeKey(VK_HOME); D.ProbeKey(VK_UP);
    AssertEquals('with the option it edits anyway',
      DateOf(EncodeDate(2026, 6, 16)), DateOf(D.DateTime));
  finally
    D.Free;
  end;
end;

procedure TDateTimeParityTest.PickerAutoCheckTicksTheBoxOnAnEdit;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.DateTime := EncodeDate(2026, 6, 15);
    D.ShowCheckBox := True;
    D.Checked := False;
    D.Options := [dtpoEnabledIfUnchecked, dtpoAutoCheck];
    D.OnChecked := @CountCheck;
    D.ProbeKey(VK_HOME); D.ProbeKey(VK_UP);
    AssertTrue('editing the value ticks the box', D.Checked);
    AssertEquals('and says so once', 1, FChecks);
  finally
    D.Free;
  end;
end;

procedure TDateTimeParityTest.PickerResetSelectionLandsOnTheFirstField;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.ProbeKey(VK_END);
    D.ProbeEnter;
    AssertEquals('by default focus keeps the caret where it was',
      High(D.Segments), D.ActiveSeg);
    D.Options := [dtpoResetSelection];
    D.ProbeEnter;
    AssertEquals('with the option it goes home', 0, D.ActiveSeg);
  finally
    D.Free;
  end;
end;

{ dmNone is for a grid cell or a compact toolbar: no button AND no reserved column.
  Reserving the space anyway was the visible half of the defect. }
procedure TDateTimeParityTest.PickerDateModeNoneGivesTheButtonColumnBack;
var
  D: TDtProbe;
  X: Integer;
begin
  D := TDtProbe.Create(nil);
  try
    D.SetBounds(0, 0, 130, 24);
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.Alignment := taRightJustify;
    D.DateTime := EncodeDate(2026, 7, 5);
    X := 129;                                { the rightmost pixel of the field }
    D.ProbeKey(VK_HOME);
    D.ProbeMouseDown(X, 12);
    AssertEquals('with a button there, that pixel belongs to the button',
      0, D.ActiveSeg);
    D.DateMode := dmNone;
    D.ProbeMouseDown(X, 12);
    AssertEquals('with dmNone the text reaches the edge and the click is a field',
      High(D.Segments), D.ActiveSeg);
    D.ProbeKey(VK_F4);
    AssertFalse('and there is no calendar to drop', D.DroppedDown);
  finally
    D.Free;
  end;
end;

procedure TDateTimeParityTest.PickerDateModeUpDownSpinsInsteadOfDropping;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    D.SetBounds(0, 0, 130, 24);
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.DateTime := EncodeDate(2026, 6, 15);
    D.DateMode := dmUpDown;
    D.ProbeKey(VK_HOME);
    D.ProbeMouseDown(124, 4);                { top half of the button column }
    AssertEquals('the top half steps up',
      DateOf(EncodeDate(2026, 6, 16)), DateOf(D.DateTime));
    D.ProbeMouseDown(124, 20);               { bottom half }
    AssertEquals('the bottom half steps down',
      DateOf(EncodeDate(2026, 6, 15)), DateOf(D.DateTime));
    D.ProbeKey(VK_F4);
    AssertFalse('and a spinning date field never drops a calendar', D.DroppedDown);
  finally
    D.Free;
  end;
end;

{ The logged skin-variance failure: a roomier font overflows a fixed 130px field.
  Asserted through GetPreferredSize rather than through Width: LCL's autosize engine
  does not run for a control that was never shown (AutoSizeDelayedHandle), so a Width
  assertion here would be green whether or not anything was measured. }
procedure TDateTimeParityTest.PickerAutoSizeGrowsToFitTheText;
var
  D: TDtProbe;
  W1, H1, W2, H2, W3, H3: Integer;
begin
  D := TDtProbe.Create(nil);
  try
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.GetPreferredSize(W1, H1);
    AssertTrue('a date field asks for a real width', W1 > 0);

    D.DateFormat := 'dddd, dd mmmm yyyy';
    D.GetPreferredSize(W2, H2);
    AssertTrue('a much longer format asks for a much wider field', W2 > W1);

    D.DateFormat := 'dd/mm/yyyy';
    D.GetPreferredSize(W3, H3);
    AssertEquals('and it asks for the narrow width again', W1, W3);

    { The checkbox is content too -- it was reserved space nothing measured. }
    D.ShowCheckBox := True;
    D.GetPreferredSize(W2, H2);
    AssertTrue('the checkbox is counted', W2 > W3);
  finally
    D.Free;
  end;
end;

{ A 4-digit year field let an unbounded picker hold a year no calendar can draw. }
procedure TDateTimeParityTest.PickerAbsoluteLimitsHoldAnUnboundedField;
var
  D: TDtProbe;
begin
  D := TDtProbe.Create(nil);
  try
    AssertEquals('MinDate is still 0 = unbounded', 0.0, Double(D.MinDate), 0.0);
    D.DateTime := EncodeDate(1000, 1, 1);
    AssertEquals('a pre-1752 date is held at the floor LCL uses',
      Double(TyTheSmallestDate), Double(D.DateTime), 0.5);
    D.DateTime := EncodeDate(2026, 6, 15);
    AssertEquals('and an ordinary date is untouched',
      DateOf(EncodeDate(2026, 6, 15)), DateOf(D.DateTime));

    { The TYPED path needs the same floor, and it is a different code path from the
      setter: a 4-digit year field happily accepts 0001, and the segment clamp only
      keeps the YEAR in 1..9999 -- it knows nothing about the control's own limits. }
    D.Kind := dtkDate; D.DateFormat := 'dd/mm/yyyy';
    D.ProbeKey(VK_END);
    D.ProbeChar('0'); D.ProbeChar('0'); D.ProbeChar('0'); D.ProbeChar('1');
    D.ProbeKey(VK_RETURN);
    AssertEquals('a typed year 0001 is held at the floor too',
      Double(TyTheSmallestDate), Double(D.DateTime), 0.5);
  finally
    D.Free;
  end;
end;

{ While a digit buffer is open the field being typed is a different WIDTH from the one
  that was rendered -- most visibly when it replaces a month NAME with one digit. Every
  field after it moves, and if the spans are not moved with the text then the highlight
  and the mouse are reading a string that no longer exists. }
procedure TDateTimeParityTest.PickerHalfTypedFieldDoesNotStrandTheOnesAfterIt;
var
  D: TDtProbe;
  Spans: TTySegmentArray;
  Txt: string;
  DayIdx, i: Integer;
begin
  D := TDtProbe.Create(nil);
  try
    D.SetBounds(0, 0, 300, 24);
    D.Kind := dtkDate;
    D.DateFormat := 'mmmm dd';       { a name, then a number }
    D.DateTime   := EncodeDate(2026, 9, 15);
    DayIdx := -1;
    for i := 0 to High(D.Segments) do
      if D.Segments[i].Kind = skDay then DayIdx := i;
    AssertTrue('the format has a day field', DayIdx >= 0);

    D.ProbeKey(VK_HOME);             { park on the month }
    D.ProbeChar('1');                { one digit: buffer open, month now 1 char wide }
    AssertEquals('the buffer is open on the month', '1', D.DigitBuffer);

    { What the control now draws is '1 15' (or the locale's equivalent), so the day sits
      far left of where the full month name had put it. }
    Txt := TyRenderDateTime(D.DateTime, 'mmmm dd', DefaultFormatSettings, True, Spans);
    AssertTrue('premise: the untyped month is much wider than one digit',
      Spans[0].LenCh > 1);

    D.ProbeMouseDown(RightmostTextX(D, '1 15'), 12);
    AssertEquals('a click on the shifted text still finds the day', DayIdx, D.ActiveSeg);
  finally
    D.Free;
  end;
end;

initialization
  RegisterTest(TDateTimeParityTest);
end.
