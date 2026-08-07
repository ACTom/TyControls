unit umain;
{$mode objfpc}{$H+}

{ TTyCalendar demo showcasing the calendar's key features:
  - Date: initially selected date; OnChange echoes the picked date
  - OnAccept: confirmed on clicking a day cell / pressing Enter (echoes "confirmed")
  - OnViewChange: click the header to drill down day->month->year->decade, echoing the current view level
  - MinDate/MaxDate: constrain the selectable date range; out-of-range dates are greyed out and unselectable
    (the "Limit the range" switch flips both bounds to 0 - the documented no-bound sentinel - so the SAME
     calendar shows the constrained and the unconstrained state)
  - FirstDayOfWeek: first day of the week (here wdMonday, Monday start)
  - WeekNumbers: show the ISO week-number column
  - ShowToday: outline highlight on today (True on the left calendar, False on the read-only
    one, so the outline reads as an on/off feature rather than as chrome)
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
    LblLimitHdr: TTyLabel;
    SwLimit: TTyToggleSwitch;
    LblLimitHint: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure CalChange(Sender: TObject);
    procedure CalAccept(Sender: TObject);
    procedure CalViewChange(Sender: TObject);
    procedure SwLimitChange(Sender: TObject);
  private
    { Push SwLimit's state onto Cal.MinDate/MaxDate and re-echo the range label. }
    procedure ApplyRangeLimit;
    procedure UpdateRangeLabel;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { View names and status texts (FormatDateTime patterns are data). }
  rsViewMonths  = 'Month view (cvmMonths)';
  rsViewYears   = 'Year view (cvmYears)';
  rsViewDecades = 'Decade view (cvmDecades)';
  rsViewDays    = 'Day view (cvmDays)';
  rsNotConfirmed = 'Not confirmed yet (click a date cell or press Enter)';
  rsPickedFmt    = 'Selected date:%s';
  rsAcceptedFmt  = 'Confirmed:%s(click a date cell / Enter fires OnAccept)';
  rsCurViewFmt   = 'Current view:%s(click a header to drill down, click a date cell to drill up)';
  rsRangeFree    = 'Range available: unbounded (MinDate = MaxDate = 0)';
  rsRangeFmt     = 'Range available: %s ~ %s';
  rsKeysHint     = 'Keyboard: arrow keys move, PageUp/PageDown change month,'
    + sLineBreak + 'Home/End go to the start/end of the month.';

function ViewName(AView: TTyCalView): string;
begin
  case AView of
    cvmMonths:  Result := rsViewMonths;
    cvmYears:   Result := rsViewYears;
    cvmDecades: Result := rsViewDecades;
  else
    Result := rsViewDays;
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
  { Constrain the selectable range from the switch's streamed state (Checked=True -> the
    3 months either side of today). Every out-of-range day is greyed out and unselectable. }
  ApplyRangeLimit;

  { Read-only calendar: selection disabled, and ShowToday=False (.lfm) so today has no outline }
  ROCal.Date := Today;

  // initialize the status echo
  CalChange(nil);
  CalViewChange(nil);
  LblAccepted.Caption := rsNotConfirmed;
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
  LblPicked.Caption := Format(rsPickedFmt, [FormatDateTime('yyyy-mm-dd', Cal.Date)]);
end;

procedure TMainForm.CalAccept(Sender: TObject);
begin
  LblAccepted.Caption := Format(rsAcceptedFmt, [FormatDateTime('yyyy-mm-dd', Cal.Date)]);
end;

procedure TMainForm.CalViewChange(Sender: TObject);
begin
  LblView.Caption := Format(rsCurViewFmt, [ViewName(Cal.ViewMode)]);
end;

{ The range switch: ON constrains the calendar to the 3 months either side of today, OFF
  sets BOTH bounds to 0 — the documented "unbounded on that side" sentinel TyCalendarInRange
  understands — so no date is out of range and PageUp/PageDown really walk to another month. }
procedure TMainForm.SwLimitChange(Sender: TObject);
begin
  if csLoading in ComponentState then Exit;   // the .lfm streams Checked before OnChange
  ApplyRangeLimit;
end;

procedure TMainForm.ApplyRangeLimit;
var
  Today: TDateTime;
begin
  Today := DateOf(Now);
  if SwLimit.Checked then
  begin
    Cal.MinDate := IncMonth(Today, -3);
    Cal.MaxDate := IncMonth(Today, 3);
  end
  else
  begin
    Cal.MinDate := 0;                         // 0 = no lower bound
    Cal.MaxDate := 0;                         // 0 = no upper bound
  end;
  UpdateRangeLabel;
  { Tightening the bounds can silently re-clamp Cal.Date (SetMinDate re-runs SetDate),
    and that path does not fire OnChange — so re-echo the selection by hand. }
  CalChange(nil);
end;

procedure TMainForm.UpdateRangeLabel;
var
  s: string;
begin
  if Cal.MinDate = 0 then
    s := rsRangeFree
  else
    s := Format(rsRangeFmt, [FormatDateTime('yyyy-mm-dd', Cal.MinDate),
         FormatDateTime('yyyy-mm-dd', Cal.MaxDate)]);
  LblRange.Caption := s + sLineBreak + rsKeysHint;
end;

end.
