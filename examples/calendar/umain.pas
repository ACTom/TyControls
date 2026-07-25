unit umain;
{$mode objfpc}{$H+}

{ TTyCalendar demo showcasing the calendar's key features:
  - Date: initially selected date; OnChange echoes the picked date
  - OnAccept: confirmed on clicking a day cell / pressing Enter (echoes "confirmed")
  - OnViewChange: click the header to drill down day->month->year->decade, echoing the current view level
  - MinDate/MaxDate: constrain the selectable date range; out-of-range dates are greyed out and unselectable
  - FirstDayOfWeek: first day of the week (here wdMonday, Monday start)
  - WeekNumbers: show the ISO week-number column
  - ShowToday: outline highlight on today
  - Second calendar: ReadOnly=True, read-only display
  The window, both calendars, the labels and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + runtime setup only. }

interface

uses
  Classes, SysUtils, DateUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Calendar, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblMainHdr: TTyLabel;
    Cal: TTyCalendar;
    LblPicked: TTyLabel;
    LblAccepted: TTyLabel;
    LblView: TTyLabel;
    LblRange: TTyLabel;
    LblReadOnlyHdr: TTyLabel;
    ROCal: TTyCalendar;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure CalChange(Sender: TObject);
    procedure CalAccept(Sender: TObject);
    procedure CalViewChange(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function ViewName(AView: TTyCalView): string;
begin
  case AView of
    cvmMonths:  Result := 'Month view (cvmMonths)';
    cvmYears:   Result := 'Year view (cvmYears)';
    cvmDecades: Result := 'Decade view (cvmDecades)';
  else
    Result := 'Day view (cvmDays)';
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  Today: TDateTime;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  Today := DateOf(Now);

  { Main calendar: initial date, range constraint, and range echo — these depend on
    the runtime "today", so they can't be baked into the .lfm. }
  Cal.Date := Today;                        // initially select today
  { Constrain the selectable range: 20 days either side of today; out-of-range dates are greyed out and unselectable }
  Cal.MinDate := IncDay(Today, -20);
  Cal.MaxDate := IncDay(Today, 20);

  LblRange.Caption := 'Range available:' +
    FormatDateTime('yyyy-mm-dd', Cal.MinDate) + ' ~ ' +
    FormatDateTime('yyyy-mm-dd', Cal.MaxDate) + sLineBreak +
    'Keyboard: arrow keys move, PageUp/Down change month, Home/End go to month start/end.';

  { Read-only calendar: show today, selection disabled }
  ROCal.Date := Today;

  // initialize the status echo
  CalChange(nil);
  CalViewChange(nil);
  LblAccepted.Caption := 'Not confirmed yet (click a date cell or press Enter)';
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.CalChange(Sender: TObject);
begin
  LblPicked.Caption := 'Selected date:' + FormatDateTime('yyyy-mm-dd', Cal.Date);
end;

procedure TMainForm.CalAccept(Sender: TObject);
begin
  LblAccepted.Caption := 'Confirmed:' + FormatDateTime('yyyy-mm-dd', Cal.Date) +
    '(click a date cell / Enter fires OnAccept)';
end;

procedure TMainForm.CalViewChange(Sender: TObject);
begin
  LblView.Caption := 'Current view:' + ViewName(Cal.ViewMode) +
    '(click a header to drill down, click a date cell to drill up)';
end;

end.
