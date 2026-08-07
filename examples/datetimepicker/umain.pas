unit umain;

{ TTyDateTimePicker example:
  - dtkDate date picker: chevron on the right opens a drop-down calendar
    (TTyCalendar); supports segmented editing (Left/Right to switch fields,
    Up/Down or wheel to step, direct numeric entry) and a custom DateFormat
  - dtkTime time picker: up/down arrows on the right step the current field,
    with a custom TimeFormat
  - the DateTime property reads/writes both date and time; MinDate/MaxDate
    constrain the range
  - ShowCheckBox: when the check box is cleared the fields are greyed out
    (inert); the OnChecked event reports the change
  - the OnChange event echoes the current value live into a TTyLabel status bar
  The window, every picker and the live theme switcher are designed in
  umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers, the
  runtime initial DateTime/range and theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.DateTimePicker, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Button;

type
  TMainForm = class(TTyForm)
    Bar:         TTyTitleBar;
    Surface:     TTyFormSurface;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo:  TTyComboBox;
    LblDate:     TTyLabel;
    DatePicker:  TTyDateTimePicker;   // dtkDate + drop-down calendar
    BtnOpen:     TTyButton;           // opens the calendar via DroppedDown := True
    LblTime:     TTyLabel;
    TimePicker:  TTyDateTimePicker;   // dtkTime + up/down stepping
    LblCheck:    TTyLabel;
    CheckPicker: TTyDateTimePicker;   // ShowCheckBox nullable date
    LblReadOnly: TTyLabel;
    ReadOnlyPicker: TTyDateTimePicker;   // ReadOnly = True
    LblReadOnlyHint: TTyLabel;
    LblRange:    TTyLabel;
    RangePicker: TTyDateTimePicker;   // MinDate/MaxDate = today +/-3 days
    LblRangeHint: TTyLabel;
    LblAmPm:     TTyLabel;
    AmPmPicker:  TTyDateTimePicker;   // 12-hour TimeFormat with an am/pm segment
    LblAmPmHint: TTyLabel;
    LblLocale:   TTyLabel;
    LocalePicker: TTyDateTimePicker;  // DateFormat left empty -> OS short date
    LblLocaleHint: TTyLabel;
    LblDropHint: TTyLabel;
    LblStatus:   TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure DateChanged(Sender: TObject);
    procedure TimeChanged(Sender: TObject);
    procedure CheckPickerChanged(Sender: TObject);
    procedure CheckPickerChecked(Sender: TObject);
    procedure DropDownOpened(Sender: TObject);
    procedure DropDownClosed(Sender: TObject);
  private
    procedure RefreshStatus;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { Status texts composed at run time (FormatDateTime patterns are data). }
  rsEmpty     = '(empty)';
  rsStatusFmt = 'Date:%s' + sLineBreak + 'Time:%s' + sLineBreak + 'Nullable:%s'
    + sLineBreak
    + 'Tip: ←/→ switch field, ↑/↓ or wheel to step, type a digit directly, chevron opens the calendar.';
  rsCalOpened = 'Calendar opened: click a date or press Enter to confirm, Esc to cancel.';
  rsDroppedFmt = 'DroppedDown = %s';

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // Runtime-only initial values (Now is not a fixed design value; MinDate/MaxDate
  // are TDateTime so they are set here rather than streamed as float literals).
  DatePicker.DateTime := Now;
  DatePicker.MinDate  := EncodeDate(2000, 1, 1);
  DatePicker.MaxDate  := EncodeDate(2099, 12, 31);

  TimePicker.DateTime := Now;

  CheckPicker.DateTime := Now;

  ReadOnlyPicker.DateTime := Now;

  // A range the user can actually walk into: three days either side of today, so
  // Up/Down on the day field (and the calendar) visibly stop at the edge.
  RangePicker.DateTime := Now;
  RangePicker.MinDate  := Date - 3;
  RangePicker.MaxDate  := Date + 3;

  AmPmPicker.DateTime := Now;

  LocalePicker.DateTime := Now;

  RefreshStatus;
end;

procedure TMainForm.BtnOpenClick(Sender: TObject);
begin
  // DroppedDown is read/write: the calendar opens from code, not only from a
  // click on the chevron.
  if DatePicker.CanFocus then DatePicker.SetFocus;
  DatePicker.DroppedDown := True;
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

procedure TMainForm.RefreshStatus;
var
  CheckState: string;
begin
  if CheckPicker.Checked then
    CheckState := FormatDateTime('yyyy/mm/dd', CheckPicker.DateTime)
  else
    CheckState := rsEmpty;
  LblStatus.Caption := Format(rsStatusFmt,
    [FormatDateTime('yyyy-mm-dd', DatePicker.DateTime),
     FormatDateTime('hh:nn:ss',   TimePicker.DateTime), CheckState]);
end;

procedure TMainForm.DateChanged(Sender: TObject);
begin
  RefreshStatus;
end;

procedure TMainForm.TimeChanged(Sender: TObject);
begin
  RefreshStatus;
end;

procedure TMainForm.CheckPickerChanged(Sender: TObject);
begin
  RefreshStatus;
end;

procedure TMainForm.CheckPickerChecked(Sender: TObject);
begin
  RefreshStatus;
end;

procedure TMainForm.DropDownOpened(Sender: TObject);
begin
  LblStatus.Caption := rsCalOpened;
end;

procedure TMainForm.DropDownClosed(Sender: TObject);
begin
  RefreshStatus;
  // Read the state back: by the time OnCloseUp fires the popup is already shut.
  LblStatus.Caption := LblStatus.Caption + sLineBreak +
    Format(rsDroppedFmt, [BoolToStr(DatePicker.DroppedDown, True)]);
end;

end.
