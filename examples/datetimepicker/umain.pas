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
  tyControls.DateTimePicker, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar:         TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo:  TTyComboBox;
    LblDate:     TTyLabel;
    DatePicker:  TTyDateTimePicker;   // dtkDate + drop-down calendar
    LblTime:     TTyLabel;
    TimePicker:  TTyDateTimePicker;   // dtkTime + up/down stepping
    LblCheck:    TTyLabel;
    CheckPicker: TTyDateTimePicker;   // ShowCheckBox nullable date
    LblStatus:   TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
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

  RefreshStatus;
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
    CheckState := '(空)';
  LblStatus.Caption :=
    '日期：' + FormatDateTime('yyyy-mm-dd', DatePicker.DateTime) + sLineBreak +
    '时间：' + FormatDateTime('hh:nn:ss',   TimePicker.DateTime) + sLineBreak +
    '可空：' + CheckState + sLineBreak +
    '提示：←/→ 切换字段，↑/↓ 或滚轮步进，直接键入数字，chevron 打开日历。';
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
  LblStatus.Caption := '日历已打开：点击日期或回车确认，Esc 取消。';
end;

procedure TMainForm.DropDownClosed(Sender: TObject);
begin
  RefreshStatus;
end;

end.
