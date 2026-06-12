unit umain;

{ TTyRadioButton 最小示例：
  - 两个 TTyPanel 容器，各含 3 个 TTyRadioButton
  - 互斥只在同一 Parent（同一 Panel）内生效
    —— 点击某选项只会取消同组其他选项，跨组不受影响
  - TTyLabel 实时显示当前选中状态
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.CheckBox, tyControls.Panel, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FStatus: TTyLabel;
    procedure RadioClicked(Sender: TObject);
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

{ 在指定 Panel 内创建一个 TTyRadioButton }
function AddRadio(APanel: TTyPanel; const ACaption: string; ATop: Integer;
  AHandler: TNotifyEvent): TTyRadioButton;
begin
  Result := TTyRadioButton.Create(APanel);
  Result.Parent := APanel;
  Result.SetBounds(8, ATop, 160, 28);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  PanelA, PanelB: TTyPanel;
  R: TTyRadioButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyRadioButton 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 280);

  { 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController }
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { --- 组 A：水果 --- }
  PanelA := TTyPanel.Create(Self);
  PanelA.Parent := Self;
  PanelA.Caption := '水果';
  PanelA.SetBounds(16, 16, 176, 140);

  R := AddRadio(PanelA, '苹果', 28, @RadioClicked);
  R.Checked := True;   // 默认选中第一项
  AddRadio(PanelA, '香蕉', 64, @RadioClicked);
  AddRadio(PanelA, '芒果', 100, @RadioClicked);

  { --- 组 B：颜色 --- }
  PanelB := TTyPanel.Create(Self);
  PanelB.Parent := Self;
  PanelB.Caption := '颜色';
  PanelB.SetBounds(212, 16, 176, 140);

  AddRadio(PanelB, '红色', 28, @RadioClicked);
  R := AddRadio(PanelB, '绿色', 64, @RadioClicked);
  R.Checked := True;   // 默认选中第二项
  AddRadio(PanelB, '蓝色', 100, @RadioClicked);

  { --- 状态标签 --- }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 172, 388, 24);
  FStatus.Caption := '当前选中：苹果 / 绿色';
end;

procedure TMainForm.RadioClicked(Sender: TObject);
var
  RB: TTyRadioButton;
  GroupName: string;
begin
  RB := Sender as TTyRadioButton;
  { 通过 Parent 的 Caption 判断所属组 }
  if RB.Parent is TTyPanel then
    GroupName := TTyPanel(RB.Parent).Caption
  else
    GroupName := '?';
  FStatus.Caption := Format('当前点击：%s（组：%s）', [RB.Caption, GroupName]);
end;

end.
