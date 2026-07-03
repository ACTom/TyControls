unit umain;

{ TTyListBox 示例（TTyForm + TTyTitleBar 无边框窗体）：
  演示要点：
    - Items / ItemIndex：填充大量列表项（30 项城市），内容高度超过可视区域 →
      自动出现内置滚动条；键盘上下键 / PageUp/PageDown / Home/End、鼠标滚轮均可滚动
    - OnChange：选择变化时更新底部 TTyLabel 状态栏（单选显示项文本+序号，
      多选显示已选数量）
    - MultiSelect：复选框切换单选 / 多选模式（多选下 Ctrl 点选、Shift 连选、
      空格切换）
    - Sorted：复选框切换升序排序（选中项按文本重新定位后保持选中）
    - ItemHeight：按钮在 24 / 32 之间切换行高
    - SelectAll / ClearSelection：多选模式下全选 / 清空
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.ListBox, tyControls.TyLabel, tyControls.Button,
  tyControls.CheckBox;

type
  TMainForm = class(TTyForm)
  private
    FListBox: TTyListBox;
    FStatus: TTyLabel;
    FChkMulti: TTyCheckBox;
    FChkSorted: TTyCheckBox;
    FBtnHeight: TTyButton;
    FBtnSelAll: TTyButton;
    FBtnClear: TTyButton;
    procedure ListBoxChange(Sender: TObject);
    procedure MultiChange(Sender: TObject);
    procedure SortedChange(Sender: TObject);
    procedure ToggleHeight(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoClear(Sender: TObject);
    procedure UpdateStatus;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找仓库的 themes/ 目录（兼容 lib/<cpu>-<os>/ 与 .app 包） }
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
  LblTitle: TTyLabel;
  Cities: array[0..29] of string = (
    '北京', '上海', '广州', '深圳', '成都', '杭州', '武汉', '西安',
    '南京', '天津', '重庆', '苏州', '长沙', '郑州', '青岛', '大连',
    '厦门', '宁波', '无锡', '合肥', '福州', '济南', '昆明', '南昌',
    '贵阳', '哈尔滨', '沈阳', '石家庄', '太原', '兰州');
  i: Integer;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 持久化引擎
  Caption := 'TTyListBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 420);

  // 先加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'ListBox  · TyControls';

  LblTitle := TTyLabel.Create(Self);
  LblTitle.Parent := Self;
  LblTitle.SetBounds(16, 46, 388, 20);
  LblTitle.Caption := '城市列表（上下键 / PageUp/Down / 滚轮可滚动）：';

  // 底部状态栏：必须在 FListBox.OnChange 接线 / ItemIndex 赋值之前创建，
  // 否则设置 ItemIndex 触发 OnChange → UpdateStatus 访问尚未创建的 FStatus → 崩溃
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 376, 388, 20);

  // 列表框：30 项，高度不足以显示全部 → 自动出现内置滚动条
  FListBox := TTyListBox.Create(Self);
  FListBox.Parent := Self;
  FListBox.SetBounds(16, 70, 388, 220);
  FListBox.ItemHeight := 24;
  FListBox.OnChange := @ListBoxChange;
  for i := Low(Cities) to High(Cities) do
    FListBox.Items.Add(Cities[i]);
  FListBox.ItemIndex := 0;                  // 默认选中第一项

  // 多选 / 排序 复选框
  FChkMulti := TTyCheckBox.Create(Self);
  FChkMulti.Parent := Self;
  FChkMulti.SetBounds(16, 300, 130, 24);
  FChkMulti.Caption := '多选模式';
  FChkMulti.OnChange := @MultiChange;

  FChkSorted := TTyCheckBox.Create(Self);
  FChkSorted.Parent := Self;
  FChkSorted.SetBounds(150, 300, 130, 24);
  FChkSorted.Caption := '升序排序';
  FChkSorted.OnChange := @SortedChange;

  // 行高切换 / 全选 / 清空 按钮
  FBtnHeight := TTyButton.Create(Self);
  FBtnHeight.Parent := Self;
  FBtnHeight.SetBounds(16, 332, 120, 30);
  FBtnHeight.Caption := '行高 24 / 32';
  FBtnHeight.OnClick := @ToggleHeight;

  FBtnSelAll := TTyButton.Create(Self);
  FBtnSelAll.Parent := Self;
  FBtnSelAll.SetBounds(146, 332, 120, 30);
  FBtnSelAll.Caption := '全选';
  FBtnSelAll.OnClick := @DoSelectAll;

  FBtnClear := TTyButton.Create(Self);
  FBtnClear.Parent := Self;
  FBtnClear.SetBounds(276, 332, 120, 30);
  FBtnClear.Caption := '清空选择';
  FBtnClear.OnClick := @DoClear;

  // 所有控件就绪后刷新状态栏文本（FStatus 已在前面创建）
  UpdateStatus;

  ApplyChromeTheme(TyDefaultController);    // 最后统一给窗体 chrome + 背景上主题
end;

procedure TMainForm.UpdateStatus;
begin
  if FListBox.MultiSelect then
    FStatus.Caption := Format('多选模式：已选 %d 项（Ctrl 点选 / Shift 连选 / 空格切换）',
      [FListBox.SelCount])
  else if FListBox.ItemIndex >= 0 then
    FStatus.Caption := Format('当前选中：%s（第 %d 项，共 %d 项）',
      [FListBox.Items[FListBox.ItemIndex], FListBox.ItemIndex + 1,
       FListBox.Items.Count])
  else
    FStatus.Caption := '当前选中：（无）';
end;

procedure TMainForm.ListBoxChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.MultiChange(Sender: TObject);
begin
  FListBox.MultiSelect := FChkMulti.Checked;
  UpdateStatus;
end;

procedure TMainForm.SortedChange(Sender: TObject);
begin
  FListBox.Sorted := FChkSorted.Checked;
  UpdateStatus;
end;

procedure TMainForm.ToggleHeight(Sender: TObject);
begin
  if FListBox.ItemHeight = 24 then
    FListBox.ItemHeight := 32
  else
    FListBox.ItemHeight := 24;
end;

procedure TMainForm.DoSelectAll(Sender: TObject);
begin
  FListBox.SelectAll;   // 仅多选模式生效
  UpdateStatus;
end;

procedure TMainForm.DoClear(Sender: TObject);
begin
  FListBox.ClearSelection;   // 仅多选模式生效
  UpdateStatus;
end;

end.
