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
  UI is built purely in code (no .lfm); the main form is a TTyForm +
  TTyTitleBar, and the theme is loaded through the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.DateTimePicker, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FDatePicker:  TTyDateTimePicker;   // dtkDate + drop-down calendar
    FTimePicker:  TTyDateTimePicker;   // dtkTime + up/down stepping
    FCheckPicker: TTyDateTimePicker;   // ShowCheckBox nullable date
    FStatus:      TTyLabel;
    procedure DateChanged(Sender: TObject);
    procedure TimeChanged(Sender: TObject);
    procedure CheckPickerChanged(Sender: TObject);
    procedure CheckPickerChecked(Sender: TObject);
    procedure DropDownOpened(Sender: TObject);
    procedure DropDownClosed(Sender: TObject);
    procedure RefreshStatus;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to locate the repo's themes/ directory }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  Lbl: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent engine
  Caption := 'TTyDateTimePicker 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 320);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 34;
  Bar.Caption := 'DateTimePicker  · TyControls';

  { ── Date picker (drop-down calendar) ── }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self; Lbl.SetBounds(20, 56, 120, 22);
  Lbl.Caption := '日期 (dtkDate)：';

  FDatePicker := TTyDateTimePicker.Create(Self);
  FDatePicker.Parent := Self;
  FDatePicker.SetBounds(150, 54, 180, 26);
  FDatePicker.Kind := dtkDate;
  FDatePicker.DateFormat := 'yyyy-mm-dd';
  FDatePicker.DateTime := Now;
  FDatePicker.MinDate := EncodeDate(2000, 1, 1);
  FDatePicker.MaxDate := EncodeDate(2099, 12, 31);
  FDatePicker.OnChange := @DateChanged;
  FDatePicker.OnDropDown := @DropDownOpened;
  FDatePicker.OnCloseUp := @DropDownClosed;

  { ── Time picker (up/down stepping) ── }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self; Lbl.SetBounds(20, 96, 120, 22);
  Lbl.Caption := '时间 (dtkTime)：';

  FTimePicker := TTyDateTimePicker.Create(Self);
  FTimePicker.Parent := Self;
  FTimePicker.SetBounds(150, 94, 180, 26);
  FTimePicker.Kind := dtkTime;
  FTimePicker.TimeFormat := 'hh:nn:ss';
  FTimePicker.DateTime := Now;
  FTimePicker.OnChange := @TimeChanged;

  { ── Nullable date (ShowCheckBox) ── }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self; Lbl.SetBounds(20, 136, 120, 22);
  Lbl.Caption := '可空日期：';

  FCheckPicker := TTyDateTimePicker.Create(Self);
  FCheckPicker.Parent := Self;
  FCheckPicker.SetBounds(150, 134, 180, 26);
  FCheckPicker.Kind := dtkDate;
  FCheckPicker.DateFormat := 'yyyy/mm/dd';
  FCheckPicker.ShowCheckBox := True;
  FCheckPicker.Checked := False;           // initially empty (fields greyed out)
  FCheckPicker.DateTime := Now;
  FCheckPicker.OnChange := @CheckPickerChanged;
  FCheckPicker.OnChecked := @CheckPickerChecked;

  { ── Status bar ── }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(20, 180, 380, 110);
  FStatus.WordWrap := True;
  RefreshStatus;

  ApplyChromeTheme(TyDefaultController);   // finally apply the theme to the form chrome and background
end;

procedure TMainForm.RefreshStatus;
var
  CheckState: string;
begin
  if FCheckPicker.Checked then
    CheckState := FormatDateTime('yyyy/mm/dd', FCheckPicker.DateTime)
  else
    CheckState := '(空)';
  FStatus.Caption :=
    '日期：' + FormatDateTime('yyyy-mm-dd', FDatePicker.DateTime) + sLineBreak +
    '时间：' + FormatDateTime('hh:nn:ss',   FTimePicker.DateTime) + sLineBreak +
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
  FStatus.Caption := '日历已打开：点击日期或回车确认，Esc 取消。';
end;

procedure TMainForm.DropDownClosed(Sender: TObject);
begin
  RefreshStatus;
end;

end.
