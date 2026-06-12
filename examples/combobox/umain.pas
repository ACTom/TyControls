unit umain;

{ TTyComboBox 最小示例：
  - Items 填充（AddStrings）、SelectItem/ItemIndex 初始选中
  - OnChange 事件更新 TTyLabel 显示选中文本
  - Text 属性只读显示当前选中项
  *** v1 限制说明 ***
  TTyComboBox 目前尚无真正的下拉弹出层（popup）。
  点击控件会循环切换到下一项（Click cycles items）：
    第 0 项 → 第 1 项 → … → 最后一项 → 第 0 项。
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.ComboBox, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FCombo: TTyComboBox;
    FStatus: TTyLabel;
    procedure ComboChanged(Sender: TObject);
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
  Lbl: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyComboBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 320, 200);

  { 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController }
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { 静态标签：说明 v1 限制 }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(16, 16, 288, 20);
  Lbl.Caption := '点击下拉框循环切换选项（v1 无弹层）';

  { TTyComboBox：填充 Items，设置初始选中项 }
  FCombo := TTyComboBox.Create(Self);
  FCombo.Parent := Self;
  FCombo.SetBounds(16, 48, 200, 28);

  { 填充选项 }
  FCombo.Items.Add('北京');
  FCombo.Items.Add('上海');
  FCombo.Items.Add('广州');
  FCombo.Items.Add('深圳');
  FCombo.Items.Add('成都');

  { OnChange：选中项变化时更新状态标签 }
  FCombo.OnChange := @ComboChanged;

  { 初始选中第 0 项；SelectItem 会触发 OnChange }
  FCombo.SelectItem(0);

  { 状态标签：显示当前 ItemIndex 与 Text }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 96, 288, 24);
  { 初始文字由 ComboChanged 在 SelectItem(0) 时设置 }
end;

procedure TMainForm.ComboChanged(Sender: TObject);
begin
  { FCombo.Text 等于 FCombo.Items[FCombo.ItemIndex]（只读） }
  FStatus.Caption := Format('当前选中：%s（ItemIndex = %d）',
    [FCombo.Text, FCombo.ItemIndex]);
end;

end.
