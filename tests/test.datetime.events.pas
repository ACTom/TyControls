unit test.datetime.events;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, TypInfo, fpcunit, testregistry,
  tyControls.Calendar, tyControls.DateTimePicker;
type
  TDateTimeEventsTest = class(TTestCase)
  private
    procedure AssertPub(AClass: TClass; const AName: string);
  published
    procedure TestCalendarEvents;
    procedure TestDateTimePickerEvents;
  end;
implementation
procedure TDateTimeEventsTest.AssertPub(AClass: TClass; const AName: string);
begin
  AssertNotNull(AClass.ClassName + ' must publish ' + AName, GetPropInfo(AClass, AName));
end;
procedure TDateTimeEventsTest.TestCalendarEvents;
begin
  { inherited standard set }
  AssertPub(TTyCalendar, 'OnClick');
  AssertPub(TTyCalendar, 'OnMouseDown');
  AssertPub(TTyCalendar, 'OnKeyDown');
  { calendar-specific events }
  AssertPub(TTyCalendar, 'OnChange');
  AssertPub(TTyCalendar, 'OnViewChange');
  AssertPub(TTyCalendar, 'OnAccept');
end;
procedure TDateTimeEventsTest.TestDateTimePickerEvents;
begin
  { inherited standard set }
  AssertPub(TTyDateTimePicker, 'OnClick');
  AssertPub(TTyDateTimePicker, 'OnMouseDown');
  AssertPub(TTyDateTimePicker, 'OnKeyDown');
  { picker-specific events }
  AssertPub(TTyDateTimePicker, 'OnChange');
  AssertPub(TTyDateTimePicker, 'OnDropDown');
  AssertPub(TTyDateTimePicker, 'OnCloseUp');
  AssertPub(TTyDateTimePicker, 'OnChecked');
end;
initialization
  RegisterTest(TDateTimeEventsTest);
end.
