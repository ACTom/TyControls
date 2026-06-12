unit umain;

{ TTyPanel 最小示例：
  - 外层 TTyPanel（带 Caption）作为容器，内含 TTyLabel、TTyEdit、TTyButton
  - 外层 Panel 内再嵌套一个内层 TTyPanel，证明 Panel 是真正的容器控件
  - Panel 的背景色、边框、圆角均来自主题 TyPanel 规则（.tycss 中的 TyPanel 选择器），
    不需要在代码里手动设置颜色或尺寸
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Panel, tyControls.Button,
  tyControls.TyLabel, tyControls.Edit;

type
  TMainForm = class(TForm)
  private
    FNameEdit: TTyEdit;
    FResultLabel: TTyLabel;
    procedure GreetClicked(Sender: TObject);
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
  OuterPanel, InnerPanel: TTyPanel;
  Lbl: TTyLabel;
  Btn: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyPanel 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 400, 320);

  { 加载主题：背景、边框、圆角均由 TyPanel 规则决定，无需手写颜色 }
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { --- 外层容器 Panel --- }
  OuterPanel := TTyPanel.Create(Self);
  OuterPanel.Parent := Self;
  OuterPanel.Caption := '用户信息';
  OuterPanel.SetBounds(16, 16, 368, 180);

  { 外层 Panel 内的标签 }
  Lbl := TTyLabel.Create(OuterPanel);
  Lbl.Parent := OuterPanel;
  Lbl.SetBounds(8, 28, 80, 24);
  Lbl.Caption := '姓名：';

  { 外层 Panel 内的编辑框 }
  FNameEdit := TTyEdit.Create(OuterPanel);
  FNameEdit.Parent := OuterPanel;
  FNameEdit.SetBounds(96, 28, 200, 26);
  FNameEdit.Text := '';

  { 外层 Panel 内的按钮 }
  Btn := TTyButton.Create(OuterPanel);
  Btn.Parent := OuterPanel;
  Btn.SetBounds(96, 68, 120, 32);
  Btn.Caption := '打招呼';
  Btn.StyleClass := 'primary';
  Btn.OnClick := @GreetClicked;

  { --- 内层嵌套 Panel（证明 Panel 是真正的容器） --- }
  { 内层 Panel 的背景/边框/圆角同样来自主题 TyPanel 规则 }
  InnerPanel := TTyPanel.Create(OuterPanel);
  InnerPanel.Parent := OuterPanel;
  InnerPanel.Caption := '嵌套子面板';
  InnerPanel.SetBounds(8, 116, 200, 48);

  { --- 结果标签（位于外层 Panel 之外，显示问候语） --- }
  FResultLabel := TTyLabel.Create(Self);
  FResultLabel.Parent := Self;
  FResultLabel.SetBounds(16, 210, 368, 24);
  FResultLabel.Caption := '点击"打招呼"按钮试试…';
end;

procedure TMainForm.GreetClicked(Sender: TObject);
var
  UserName: string;
begin
  UserName := FNameEdit.Text;
  if UserName = '' then
    FResultLabel.Caption := '请先输入姓名！'
  else
    FResultLabel.Caption := Format('你好，%s！欢迎使用 TyControls。', [UserName]);
end;

end.
