unit test.db.datetime;
{$mode objfpc}{$H+}

{ The data-aware date controls (issue #34, plan Task 8): TTyDBDateTimePicker and TTyDBCalendar,
  through the shared C1-C8 run of test.db.edits plus what only dates have.

  Every change is the user's: keys (KeyDown), the wheel, a click on a calendar day where the
  calendar draws it, a key inside the picker's dropdown calendar -- never a write to DateTime or
  Date, which is exactly what a control must not take for the user.

  The picker shows its value as 'yyyy-mm-dd hh:nn' here, whatever it draws, so the time of day a
  date column must not get is visible in every comparison. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, DB, DateUtils, TypInfo,
  fpcunit, testregistry,
  dbfixtures, test.db.edits, tyControls.DateTimePicker, tyControls.Calendar,
  tyControls.DB.DateTime;

type
  TProbeDBPicker = class(TTyDBDateTimePicker)
  public
    Changes: Integer;
    procedure CountChange(Sender: TObject);
    { The dropdown calendar, created and seeded as OpenDropDown does, without a window. }
    function OpenCalendar: TTyCalendar;
    { A key pressed inside the dropdown calendar. }
    procedure PressCalendarKey(AKey: Word);
  end;

  TDBDateTimePickerTest = class(TDBControlTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    { Home (the year), Up: a year on. }
    procedure UserEdit; override;
    { The wheel: a year on again, by the other road to a step. }
    procedure UserEditUnguarded; override;
    procedure Commit; override;
    procedure AssertFieldHoldsEdit; override;
    function Picker: TProbeDBPicker;
  published
    procedure TestNullRowShowsEmptyAndNWritesNull;
    procedure TestNoNullKeysWithoutNullInputAllowed;
    procedure TestReadOnlyFieldGetsNoDayFromTheCalendar;
    procedure TestReadOnlyPickerOpensNoCalendar;
    procedure TestEscapeBringsBackTheFieldNotTheFocusSnapshot;
    procedure TestDateFieldIsWrittenWithoutTheTimeOfDay;
    procedure TestDateTimeFieldKeepsTheTimeOfDay;
    procedure TestDropDownCalendarPickIsAnEdit;
    procedure TestRefusedEditReachesNoOnChange;
  end;

  TDBCalendarTest = class(TDBControlTestBase)
  protected
    FChanges: Integer;
    procedure SetUp; override;
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function ExpectedUnbound: string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    { Right: the next day. }
    procedure UserEdit; override;
    { A click on another day. }
    procedure UserEditUnguarded; override;
    { Enter: the calendar's accept key. }
    procedure Commit; override;
    procedure AssertFieldHoldsEdit; override;
    function Cal: TTyDBCalendar;
    { Press and release the left button on the middle of ADay's cell, found where the
      calendar's own hit test puts the grid. }
    procedure ClickDay(ADay: TDateTime);
    procedure CountChange(Sender: TObject);
  published
    procedure TestFieldOutsideTheRangeIsClampedNotRaised;
    procedure TestPickedDayIsWrittenByAPostElsewhere;
    procedure TestClickOnADayEditsAndWritesIt;
    procedure TestNullRowKeepsTheDayAndAPickFillsIt;
    procedure TestDateTimeFieldKeepsItsTimeOfDay;
    procedure TestPagingTheMonthIsNoEdit;
    procedure TestReadOnlyFieldPicksNothing;
  end;

implementation

type
  TDTInput = class(TWinControl);
  TCalendarKeys = class(TTyCalendar);

function PickerText(AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', AValue);
end;

function DayText(AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd', AValue);
end;

{ ==================================================================== TProbeDBPicker ====== }

procedure TProbeDBPicker.CountChange(Sender: TObject);
begin
  Inc(Changes);
end;

function TProbeDBPicker.OpenCalendar: TTyCalendar;
begin
  EnsurePopup;
  SeedPopupCalendar;
  Result := Calendar;
end;

procedure TProbeDBPicker.PressCalendarKey(AKey: Word);
begin
  TCalendarKeys(Calendar).KeyDown(AKey, []);
end;

{ ============================================================ TDBDateTimePickerTest ======= }

function TDBDateTimePickerTest.NewControl: TControl;
begin
  Result := TProbeDBPicker.Create(FForm);
  TProbeDBPicker(Result).DateFormat := 'yyyy-mm-dd';
end;

function TDBDateTimePickerTest.Picker: TProbeDBPicker;
begin
  Result := TProbeDBPicker(FCtl);
end;

function TDBDateTimePickerTest.FieldName: string;
begin
  Result := 'Born';
end;

function TDBDateTimePickerTest.Shown: string;
begin
  if Picker.DateIsNull then Result := '' else Result := PickerText(Picker.DateTime);
end;

function TDBDateTimePickerTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := PickerText(FixBorn(ARow)) else Result := '';   // NULL: empty (D5)
end;

function TDBDateTimePickerTest.OtherFieldName: string;
begin
  Result := 'At';
end;

function TDBDateTimePickerTest.OtherShown: string;
begin
  Result := PickerText(FixAt(1));
end;

procedure TDBDateTimePickerTest.UserEdit;
begin
  EnterControl;
  Key(VK_HOME);
  Key(VK_UP);
end;

procedure TDBDateTimePickerTest.UserEditUnguarded;
begin
  TDTInput(FCtl).DoMouseWheel([], 120, Point(10, 10));
end;

procedure TDBDateTimePickerTest.Commit;
begin
  Key(VK_RETURN);
end;

procedure TDBDateTimePickerTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field, a year on', EncodeDate(1991, 5, 17), BoundField.AsDateTime, 0);
end;

{ D5 }
procedure TDBDateTimePickerTest.TestNullRowShowsEmptyAndNWritesNull;
begin
  Bind('Born');
  GoRow(3);
  AssertTrue('NULL: empty', Picker.DateIsNull);
  GoRow(1);
  EnterControl;
  Key(VK_N);
  AssertTrue('N empties it', Picker.DateIsNull);
  AssertTrue('an edit', FFix.DS.State = dsEdit);
  Commit;
  AssertTrue('NULL written', BoundField.IsNull);
  FFix.DS.Post;
  AssertTrue('NULL posted', BoundField.IsNull);
end;

procedure TDBDateTimePickerTest.TestNoNullKeysWithoutNullInputAllowed;
begin
  Picker.NullInputAllowed := False;
  Bind('Born');
  EnterControl;
  Key(VK_N);
  Key(VK_DELETE);
  AssertEquals('still the field', ExpectedShown(1), Shown);
  AssertBrowsing('N and Delete refused');
end;

{ V10 under the data link: a field that cannot be changed makes the picker read-only, and a
  read-only picker takes no day from its calendar -- here opened as OpenDropDown opens it,
  without a window, and moved and accepted with keys as the user would. }
procedure TDBDateTimePickerTest.TestReadOnlyFieldGetsNoDayFromTheCalendar;
begin
  BoundField.ReadOnly := True;
  Bind('Born');
  EnterControl;
  Picker.OpenCalendar;
  Picker.PressCalendarKey(VK_RIGHT);
  Picker.PressCalendarKey(VK_RETURN);
  AssertEquals('the field''s day still', ExpectedShown(1), Shown);
  AssertBrowsing('picking a day over a read-only field');
end;

{ The base control is read-only, not merely reset afterwards: the wheel is not taken (so it
  can scroll what holds the picker), and the dropdown does not open (F4) -- the other half of
  V10, checked on a picker whose popup exists already, so "not open" is not merely "never
  created". The wheel comes first: a picker that is not read-only would open a real window. }
procedure TDBDateTimePickerTest.TestReadOnlyPickerOpensNoCalendar;
begin
  Bind('Born');
  Picker.ReadOnly := True;
  AssertFalse('the wheel is not taken',
    TDTInput(FCtl).DoMouseWheel([], 120, Point(10, 10)));
  Picker.OpenCalendar;
  AssertNotNull('the popup exists', Picker.Popup);
  AssertFalse('and is closed', Picker.Popup.IsOpen);
  Picker.PressCalendarKey(VK_RIGHT);
  AssertEquals('no day from it', ExpectedShown(1), Shown);
  EnterControl;
  Key(VK_F4);
  AssertFalse('F4 opens nothing', Picker.Popup.IsOpen);
  AssertBrowsing('a read-only picker');
end;

{ Enter wrote a year on; a second step, then Escape: the field's value comes back (a year on),
  not the value focus arrived with -- the base control's own undo would go back to that. }
procedure TDBDateTimePickerTest.TestEscapeBringsBackTheFieldNotTheFocusSnapshot;
begin
  Bind('Born');
  UserEdit;
  Commit;
  AssertFieldHoldsEdit;
  Key(VK_UP);
  AssertEquals('two years on', PickerText(EncodeDate(1992, 5, 17)), Shown);
  Key(VK_ESCAPE);
  AssertEquals('the field''s value, not the one focus came with',
    PickerText(EncodeDate(1991, 5, 17)), Shown);
  FFix.DS.Post;
  AssertFieldHoldsEdit;
end;

{ A date column gets the date alone, whatever time of day the picker holds. }
procedure TDBDateTimePickerTest.TestDateFieldIsWrittenWithoutTheTimeOfDay;
begin
  Picker.DateFormat := 'yyyy-mm-dd hh:nn';
  Bind('Born');
  EnterControl;
  Key(VK_END);   // the minutes
  Key(VK_UP);
  AssertEquals('the picker holds a time', PickerText(FixBorn(1) + EncodeTime(0, 1, 0, 0)), Shown);
  Commit;
  AssertEquals('the date alone', FixBorn(1), BoundField.AsDateTime, 0);
end;

procedure TDBDateTimePickerTest.TestDateTimeFieldKeepsTheTimeOfDay;
begin
  Picker.DateFormat := 'yyyy-mm-dd hh:nn';
  Bind('At');
  EnterControl;
  Key(VK_END);
  Key(VK_UP);
  Commit;
  AssertEquals('a minute on', PickerText(IncMinute(FixAt(1))),
    PickerText(FFix.DS.FieldByName('At').AsDateTime));
end;

{ The dropdown calendar's edits never pass through the picker's key and mouse code; the base
  control's Change is where they arrive. }
procedure TDBDateTimePickerTest.TestDropDownCalendarPickIsAnEdit;
begin
  Bind('Born');
  EnterControl;
  Picker.OpenCalendar;
  Picker.PressCalendarKey(VK_RIGHT);
  AssertTrue('a move in the calendar edits', FFix.DS.State = dsEdit);
  Picker.PressCalendarKey(VK_RETURN);
  Commit;
  AssertEquals('the next day', IncDay(FixBorn(1)), BoundField.AsDateTime, 0);
end;

{ AutoEdit off: the step happens (the picker is not read-only) and is undone by the reset --
  without telling the application a value changed that never did. }
procedure TDBDateTimePickerTest.TestRefusedEditReachesNoOnChange;
begin
  FFix.Src.AutoEdit := False;
  Bind('Born');
  Picker.OnChange := @Picker.CountChange;
  UserEdit;
  AssertEquals('the field', ExpectedShown(1), Shown);
  AssertEquals('no OnChange', 0, Picker.Changes);
  AssertBrowsing('a refused step');
  FFix.Src.AutoEdit := True;
  Key(VK_UP);
  AssertEquals('allowed, OnChange once', 1, Picker.Changes);
end;

{ ================================================================== TDBCalendarTest ======= }

procedure TDBCalendarTest.SetUp;
begin
  inherited SetUp;
  FCtl.SetBounds(8, 8, 240, 220);   // room for the day grid
end;

function TDBCalendarTest.NewControl: TControl;
begin
  Result := TTyDBCalendar.Create(FForm);
  TTyDBCalendar(Result).FirstDayOfWeek := wdSunday;
end;

function TDBCalendarTest.Cal: TTyDBCalendar;
begin
  Result := TTyDBCalendar(FCtl);
end;

function TDBCalendarTest.FieldName: string;
begin
  Result := 'Born';
end;

function TDBCalendarTest.Shown: string;
begin
  Result := DayText(Cal.Date);
end;

{ A calendar has no empty state: on the NULL row it keeps the day it showed, which in the
  shared runs is row 2's (they visit row 3 from row 2). }
function TDBCalendarTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := DayText(FixBorn(ARow)) else Result := DayText(FixBorn(2));
end;

{ Unbound, likewise: the day it showed, row 1's in the runs that unbind it. }
function TDBCalendarTest.ExpectedUnbound: string;
begin
  Result := DayText(FixBorn(1));
end;

function TDBCalendarTest.OtherFieldName: string;
begin
  Result := 'At';
end;

function TDBCalendarTest.OtherShown: string;
begin
  Result := DayText(FixAt(1));
end;

procedure TDBCalendarTest.UserEdit;
begin
  EnterControl;
  Key(VK_RIGHT);
end;

procedure TDBCalendarTest.UserEditUnguarded;
begin
  ClickDay(EncodeDate(1990, 5, 22));
end;

procedure TDBCalendarTest.Commit;
begin
  Key(VK_RETURN);
end;

procedure TDBCalendarTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field, the next day', IncDay(FixBorn(1)), BoundField.AsDateTime, 0);
end;

procedure TDBCalendarTest.ClickDay(ADay: TDateTime);
var
  grid: TTyDateGrid;
  r: TRect;
  x, y, idx, cx, cy, gw, gh: Integer;
begin
  { The grid's extent, where the calendar's own hit test says the day cells are: across the
    middle row and down the middle column. }
  r := Rect(MaxInt, MaxInt, -1, -1);
  for x := 0 to Cal.ClientWidth - 1 do
    if Cal.HitTest(Point(x, Cal.ClientHeight * 2 div 3)) = cpDate then
    begin
      if x < r.Left then r.Left := x;
      r.Right := x + 1;
    end;
  for y := 0 to Cal.ClientHeight - 1 do
    if Cal.HitTest(Point(Cal.ClientWidth div 2, y)) = cpDate then
    begin
      if y < r.Top then r.Top := y;
      r.Bottom := y + 1;
    end;
  AssertTrue('the calendar shows a day grid', (r.Right > r.Left) and (r.Bottom > r.Top));
  grid := TyCalendarMonthGrid(Cal.ViewYear, Cal.ViewMonth, Cal.FirstDayOfWeek);
  idx := -1;
  for x := 0 to 41 do
    if DateOf(grid[x]) = DateOf(ADay) then idx := x;
  AssertTrue('the day is on the page shown', idx >= 0);
  gw := r.Right - r.Left;
  gh := r.Bottom - r.Top;
  cx := r.Left + (2 * (idx mod 7) + 1) * gw div 14;
  cy := r.Top + (2 * (idx div 7) + 1) * gh div 12;
  AssertEquals('the point is that day''s cell', idx, TyCalendarHitCell(r, 7, 6, cx, cy));
  TDTInput(FCtl).MouseDown(mbLeft, [ssLeft], cx, cy);
  TDTInput(FCtl).MouseUp(mbLeft, [], cx, cy);
end;

{ V9: Date := raises outside MinDate..MaxDate; a field there must not raise out of the load
  (the scroll that brought it would abort). Shown clamped, not written. }
procedure TDBCalendarTest.TestFieldOutsideTheRangeIsClampedNotRaised;
begin
  Cal.MinDate := EncodeDate(2000, 1, 1);
  Cal.MaxDate := EncodeDate(2010, 12, 31);
  Bind('Born');
  AssertEquals('row 1 (1990), clamped', '2000-01-01', Shown);
  AssertBrowsing('loading a day out of range');
  FFix.DS.Edit;
  FFix.DS.Post;
  AssertEquals('not written', FixBorn(1), BoundField.AsDateTime, 0);
end;

{ M14. LCL's TDBCalendar never marks its link modified, so a Post made elsewhere -- a
  navigator's, say -- writes nothing. Here it writes the picked day. }
procedure TDBCalendarTest.TestPickedDayIsWrittenByAPostElsewhere;
begin
  Bind('Born');
  EnterControl;
  Key(VK_RIGHT);
  Key(VK_RIGHT);
  AssertTrue('editing', FFix.DS.State = dsEdit);
  FFix.DS.Post;
  AssertEquals('two days on, posted', IncDay(FixBorn(1), 2), BoundField.AsDateTime, 0);
end;

{ A click on a day picks it and accepts it: in the record at once. }
procedure TDBCalendarTest.TestClickOnADayEditsAndWritesIt;
begin
  Bind('Born');
  ClickDay(EncodeDate(1990, 5, 22));
  AssertEquals('picked', '1990-05-22', Shown);
  AssertTrue('editing', FFix.DS.State = dsEdit);
  AssertEquals('accepted: in the record', EncodeDate(1990, 5, 22), BoundField.AsDateTime, 0);
end;

{ D5: NULL leaves the day shown; picking one fills the field. }
procedure TDBCalendarTest.TestNullRowKeepsTheDayAndAPickFillsIt;
begin
  Bind('Born');
  GoRow(3);
  AssertEquals('row 1''s day still', DayText(FixBorn(1)), Shown);
  AssertBrowsing('the NULL row');
  EnterControl;
  Key(VK_RIGHT);
  Commit;
  AssertEquals('filled', IncDay(FixBorn(1)), BoundField.AsDateTime, 0);
end;

procedure TDBCalendarTest.TestDateTimeFieldKeepsItsTimeOfDay;
begin
  Bind('At');
  EnterControl;
  Key(VK_RIGHT);
  Commit;
  AssertEquals('the next day, the same hour', PickerText(IncDay(FixAt(1))),
    PickerText(FFix.DS.FieldByName('At').AsDateTime));
end;

{ The header arrow pages the view; the day does not move, so nothing is edited. }
procedure TDBCalendarTest.TestPagingTheMonthIsNoEdit;
var
  m: Word;
  x: Integer;
begin
  Bind('Born');
  m := Cal.ViewMonth;
  x := 2;
  AssertTrue('the left header arrow', Cal.HitTest(Point(x, 4)) = cpTitleBtn);
  TDTInput(FCtl).MouseDown(mbLeft, [ssLeft], x, 4);
  TDTInput(FCtl).MouseUp(mbLeft, [], x, 4);
  AssertTrue('the view moved', Cal.ViewMonth <> m);
  AssertEquals('the day did not', DayText(FixBorn(1)), Shown);
  AssertBrowsing('paging the month');
end;

procedure TDBCalendarTest.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

{ D4: refused before the day moves, not moved and put back -- the base calendar is read-only
  while the field cannot be changed, so no OnChange announces a pick that never happens. }
procedure TDBCalendarTest.TestReadOnlyFieldPicksNothing;
begin
  BoundField.ReadOnly := True;
  Bind('Born');
  Cal.OnChange := @CountChange;
  EnterControl;
  Key(VK_RIGHT);
  ClickDay(EncodeDate(1990, 5, 22));
  AssertEquals('the field''s day', DayText(FixBorn(1)), Shown);
  AssertEquals('no OnChange', 0, FChanges);
  AssertBrowsing('picks on a read-only field');
end;

initialization
  RegisterTest(TDBDateTimePickerTest);
  RegisterTest(TDBCalendarTest);
end.
