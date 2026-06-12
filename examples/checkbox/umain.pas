unit umain;

{ TTyCheckBox 最小示例：
  - 两个 TTyCheckBox，OnClick 事件更新状态标签
  - Checked 属性反映勾选状态（Toggle 在 Click 内自动完成）
  - 一个禁用的 TTyCheckBox（Enabled:=False）
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.TyLabel,
  tyControls.CheckBox;

type
  TMainForm = class(TForm)
  private
    FCB1: TTyCheckBox;
    FCB2: TTyCheckBox;
    FStatusLabel: TTyLabel;
    procedure CheckBoxClicked(Sender: TObject);
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

{ 把布尔值转为中文"是"/"否" }
function BoolToZh(B: Boolean): string;
begin
  if B then Result := '已勾选' else Result := '未勾选';
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  CBDisabled: TTyCheckBox;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyCheckBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 360, 260);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 第一个复选框（初始未勾选）
  FCB1 := TTyCheckBox.Create(Self);
  FCB1.Parent := Self;
  FCB1.SetBounds(24, 24, 280, 28);
  FCB1.Caption := '选项 A（初始未勾选）';
  FCB1.Checked := False;
  FCB1.OnClick := @CheckBoxClicked;

  // 第二个复选框（初始已勾选）
  FCB2 := TTyCheckBox.Create(Self);
  FCB2.Parent := Self;
  FCB2.SetBounds(24, 64, 280, 28);
  FCB2.Caption := '选项 B（初始已勾选）';
  FCB2.Checked := True;
  FCB2.OnClick := @CheckBoxClicked;

  // 禁用态复选框：Enabled:=False，触发 :disabled 主题样式
  CBDisabled := TTyCheckBox.Create(Self);
  CBDisabled.Parent := Self;
  CBDisabled.SetBounds(24, 104, 280, 28);
  CBDisabled.Caption := '已禁用选项（无法交互）';
  CBDisabled.Checked := True;
  CBDisabled.Enabled := False;

  // 状态标签：显示两个复选框当前的 Checked 状态
  FStatusLabel := TTyLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.SetBounds(24, 156, 300, 24);
  FStatusLabel.Caption := Format('A：%s  B：%s', [BoolToZh(FCB1.Checked), BoolToZh(FCB2.Checked)]);
end;

procedure TMainForm.CheckBoxClicked(Sender: TObject);
begin
  // OnClick 在 TTyCheckBox.Click 内、Checked 翻转之后触发，直接读取最新值
  FStatusLabel.Caption := Format('A：%s  B：%s',
    [BoolToZh(FCB1.Checked), BoolToZh(FCB2.Checked)]);
end;

end.
