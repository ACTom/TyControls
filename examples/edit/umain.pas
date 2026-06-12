unit umain;

{ TTyEdit 最小示例：
  - TTyEdit 是单行文本输入控件，支持 UTF-8 安全退格
    （退格按字符删除，不会截断多字节 UTF-8 序列）
  - 启用态与禁用态（Enabled:=False）对比
  - TTyButton + TTyLabel：点击后把 Edit.Text 读入 label
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel,
  tyControls.Edit;

type
  TMainForm = class(TForm)
  private
    FEdit: TTyEdit;
    FResultLabel: TTyLabel;
    procedure ReadClicked(Sender: TObject);
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
  LHint: TTyLabel;
  EditDisabled: TTyEdit;
  Btn: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyEdit 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 360, 280);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 提示文字
  LHint := TTyLabel.Create(Self);
  LHint.Parent := Self;
  LHint.SetBounds(24, 20, 300, 22);
  LHint.Caption := '可编辑输入框（支持中文，退格 UTF-8 安全）：';

  // 可编辑的 TTyEdit
  FEdit := TTyEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.SetBounds(24, 48, 300, 32);
  FEdit.Text := '你好，世界！';   // 初始文本

  // 禁用态 TTyEdit
  EditDisabled := TTyEdit.Create(Self);
  EditDisabled.Parent := Self;
  EditDisabled.SetBounds(24, 100, 300, 32);
  EditDisabled.Text := '已禁用，无法编辑';
  EditDisabled.Enabled := False;

  // 按钮：读取 FEdit.Text 并显示到 label
  Btn := TTyButton.Create(Self);
  Btn.Parent := Self;
  Btn.SetBounds(24, 152, 140, 32);
  Btn.Caption := '读取输入内容';
  Btn.StyleClass := 'primary';
  Btn.OnClick := @ReadClicked;

  // 结果显示 label
  FResultLabel := TTyLabel.Create(Self);
  FResultLabel.Parent := Self;
  FResultLabel.SetBounds(24, 200, 300, 24);
  FResultLabel.Caption := '（尚未读取）';
end;

procedure TMainForm.ReadClicked(Sender: TObject);
begin
  // 读取 TTyEdit 的 Text 属性并显示
  FResultLabel.Caption := '输入内容：' + FEdit.Text;
end;

end.
