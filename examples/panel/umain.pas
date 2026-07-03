unit umain;

{ TTyPanel 示例（TTyForm 自绘窗框 + 标题栏）：
    - Caption：面板标题文字（注意：TTyPanel.Caption 始终居中绘制）
    - Alignment：内部子控件的水平对齐参考（这里用作布局说明）
    - 作为容器：面板内放置 TTyLabel / TTyEdit / TTyButton，并嵌套子面板
    - Align：alBottom / alLeft 停靠演示，宽高随窗体自动拉伸
  面板的背景、边框、圆角均来自主题 TyPanel 规则，无需在代码里手写颜色。
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Panel, tyControls.Button, tyControls.TyLabel, tyControls.Edit;

type
  TMainForm = class(TTyForm)
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
  OuterPanel, InnerPanel, RightPanel, BottomPanel: TTyPanel;
  Lbl: TTyLabel;
  Btn: TTyButton;
begin
  // TTyForm.CreateNew → 无边框 + 持久引擎，但默认无标题栏
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyPanel 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 560, 400);

  // 主题须先加载
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 标题栏：Owner=Self 即自动关联为 TTyForm.TitleBar
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyPanel  · TyControls';

  { --- 外层容器 Panel：Caption 居左对齐 --- }
  OuterPanel := TTyPanel.Create(Self);
  OuterPanel.Parent := Self;
  OuterPanel.Caption := '用户信息（Caption 左对齐）';
  OuterPanel.Alignment := taLeftJustify;   // 标题文字左对齐
  OuterPanel.SetBounds(16, 50, 340, 190);

  { 容器内：标签 }
  Lbl := TTyLabel.Create(OuterPanel);
  Lbl.Parent := OuterPanel;
  Lbl.SetBounds(12, 40, 64, 24);
  Lbl.Caption := '姓名：';

  { 容器内：编辑框 }
  FNameEdit := TTyEdit.Create(OuterPanel);
  FNameEdit.Parent := OuterPanel;
  FNameEdit.SetBounds(80, 40, 240, 26);
  FNameEdit.Text := '';

  { 容器内：按钮 }
  Btn := TTyButton.Create(OuterPanel);
  Btn.Parent := OuterPanel;
  Btn.SetBounds(80, 80, 120, 32);
  Btn.Caption := '打招呼';
  Btn.StyleClass := 'primary';
  Btn.OnClick := @GreetClicked;

  { 容器内：嵌套子面板（证明 Panel 是真正的容器控件），Caption 居中（默认） }
  InnerPanel := TTyPanel.Create(OuterPanel);
  InnerPanel.Parent := OuterPanel;
  InnerPanel.Caption := '嵌套子面板（居中）';
  InnerPanel.Alignment := taCenter;        // 默认即 taCenter，这里显式演示
  InnerPanel.SetBounds(12, 124, 316, 52);

  { --- 右列 Panel：真正的主题化容器，Caption（居中绘制）+ 内嵌子控件 --- }
  RightPanel := TTyPanel.Create(Self);
  RightPanel.Parent := Self;
  RightPanel.Caption := '说明';               // Caption 由主题居中绘制在面板顶部区
  RightPanel.SetBounds(372, 50, 172, 190);

  { 右列容器内的说明标签（证明面板是真正承载子控件的容器） }
  Lbl := TTyLabel.Create(RightPanel);
  Lbl.Parent := RightPanel;
  Lbl.SetBounds(12, 40, 148, 140);
  Lbl.Caption := '面板的背景、边框与圆角均来自主题 TyPanel 规则，无需手写颜色。';

  { --- 结果标签 --- }
  FResultLabel := TTyLabel.Create(Self);
  FResultLabel.Parent := Self;
  FResultLabel.SetBounds(16, 252, 528, 24);
  FResultLabel.Caption := '点击“打招呼”按钮试试…';

  { --- 底部停靠 Panel：演示 Align=alBottom（宽度随窗体自动拉伸） --- }
  BottomPanel := TTyPanel.Create(Self);
  BottomPanel.Parent := Self;
  BottomPanel.Caption := 'Align = alBottom';   // Caption 居中绘制
  BottomPanel.Align := alBottom;
  BottomPanel.Height := 44;

  // 整套窗框 + 背景色随主题
  ApplyChromeTheme(TyDefaultController);
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
