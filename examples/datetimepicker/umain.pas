unit umain;

{ TTyDateTimePicker 示例：
  - dtkDate 日期选择器：右侧 chevron 打开下拉日历（TTyCalendar），支持
    分段编辑（←/→ 切换字段、↑/↓ 或滚轮步进、直接键入数字）、DateFormat 自定义格式
  - dtkTime 时间选择器：右侧上/下箭头步进当前字段，TimeFormat 自定义格式
  - DateTime 属性统一读写日期与时间；MinDate/MaxDate 限定范围
  - ShowCheckBox：勾选框为空时字段置灰（inert），OnChecked 事件反馈
  - OnChange 事件将当前值实时回显到 TTyLabel 状态栏
  纯代码创建 UI（无 .lfm），主窗体为 TTyForm + TTyTitleBar，
  主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.DateTimePicker, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FDatePicker:  TTyDateTimePicker;   // dtkDate + 下拉日历
    FTimePicker:  TTyDateTimePicker;   // dtkTime + 上/下步进
    FCheckPicker: TTyDateTimePicker;   // ShowCheckBox 可空日期
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

{ 从 exe 所在目录向上查找仓库的 themes/ 目录 }
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
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 持久引擎
  Caption := 'TTyDateTimePicker 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 320);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 34;
  Bar.Caption := 'DateTimePicker  · TyControls';

  { ── 日期选择器（下拉日历）── }
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

  { ── 时间选择器（上/下步进）── }
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

  { ── 可空日期（ShowCheckBox）── }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self; Lbl.SetBounds(20, 136, 120, 22);
  Lbl.Caption := '可空日期：';

  FCheckPicker := TTyDateTimePicker.Create(Self);
  FCheckPicker.Parent := Self;
  FCheckPicker.SetBounds(150, 134, 180, 26);
  FCheckPicker.Kind := dtkDate;
  FCheckPicker.DateFormat := 'yyyy/mm/dd';
  FCheckPicker.ShowCheckBox := True;
  FCheckPicker.Checked := False;           // 初始为空（字段置灰）
  FCheckPicker.DateTime := Now;
  FCheckPicker.OnChange := @CheckPickerChanged;
  FCheckPicker.OnChecked := @CheckPickerChecked;

  { ── 状态栏 ── }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(20, 180, 380, 110);
  FStatus.WordWrap := True;
  RefreshStatus;

  ApplyChromeTheme(TyDefaultController);   // 最后统一给窗体铬饰与背景应用主题
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
