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
    cvmMonths:  Result := '月视图 (cvmMonths)';
    cvmYears:   Result := '年视图 (cvmYears)';
    cvmDecades: Result := '十年视图 (cvmDecades)';
  else
    Result := '日视图 (cvmDays)';
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

  LblRange.Caption := '可选区间：' +
    FormatDateTime('yyyy-mm-dd', Cal.MinDate) + ' ~ ' +
    FormatDateTime('yyyy-mm-dd', Cal.MaxDate) + sLineBreak +
    '键盘：方向键移动，PageUp/Down 换月，Home/End 月首末。';

  { Read-only calendar: show today, selection disabled }
  ROCal.Date := Today;

  // initialize the status echo
  CalChange(nil);
  CalViewChange(nil);
  LblAccepted.Caption := '尚未确认（点击一个日期格或按回车）';
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
  LblPicked.Caption := '已选日期：' + FormatDateTime('yyyy-mm-dd', Cal.Date);
end;

procedure TMainForm.CalAccept(Sender: TObject);
begin
  LblAccepted.Caption := '已确认：' + FormatDateTime('yyyy-mm-dd', Cal.Date) +
    '（点击日期格 / 回车触发 OnAccept）';
end;

procedure TMainForm.CalViewChange(Sender: TObject);
begin
  LblView.Caption := '当前视图：' + ViewName(Cal.ViewMode) +
    '（点标题下钻，点日期格上钻）';
end;

end.
