unit umain;

{ TTyTabControl 最小示例：
  - 三个标签页：常规 / 外观 / 关于
  - 每个页面放置若干控件（标签、按钮、复选框）
  - OnChange 事件：底部状态栏实时显示当前标签页
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.TabControl, tyControls.Panel,
  tyControls.Button, tyControls.TyLabel, tyControls.CheckBox;

type
  TMainForm = class(TForm)
  private
    FTabCtrl: TTyTabControl;
    FStatus:  TTyLabel;
    procedure TabChanged(Sender: TObject);
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
  Result := 'themes' + PathDelim; { 兜底：相对当前目录 }
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Page: TTyPanel;  { AddTab 返回的页面面板 }
begin
  inherited CreateNew(AOwner, 0);
  Caption  := 'TTyTabControl 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 320);

  { 加载亮色主题；未指定 Controller 的控件自动使用全局 TyDefaultController }
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { ── 标签控件 ─────────────────────────────────────────────────────────── }
  FTabCtrl := TTyTabControl.Create(Self);
  FTabCtrl.Parent   := Self;
  FTabCtrl.SetBounds(16, 16, 448, 240);
  FTabCtrl.OnChange := @TabChanged;

  { ── 第一页：常规 ─────────────────────────────────────────────────────── }
  Page := FTabCtrl.AddTab('常规');

  with TTyLabel.Create(Self) do
  begin
    Parent  := Page;
    Caption := '用户名：';
    SetBounds(12, 12, 80, 22);
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := Page;
    Caption := '确定';
    SetBounds(12, 44, 90, 30);
    StyleClass := 'primary';
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := Page;
    Caption := '取消';
    SetBounds(112, 44, 90, 30);
  end;

  { ── 第二页：外观 ─────────────────────────────────────────────────────── }
  Page := FTabCtrl.AddTab('外观');

  with TTyLabel.Create(Self) do
  begin
    Parent  := Page;
    Caption := '主题设置';
    SetBounds(12, 12, 120, 22);
  end;

  with TTyCheckBox.Create(Self) do
  begin
    Parent  := Page;
    Caption := '启用动画效果';
    SetBounds(12, 44, 160, 24);
    Checked := True;
  end;

  with TTyCheckBox.Create(Self) do
  begin
    Parent  := Page;
    Caption := '高对比度模式';
    SetBounds(12, 76, 160, 24);
  end;

  { ── 第三页：关于 ─────────────────────────────────────────────────────── }
  Page := FTabCtrl.AddTab('关于');

  with TTyLabel.Create(Self) do
  begin
    Parent  := Page;
    Caption := 'TyControls v1.2';
    SetBounds(12, 12, 200, 22);
  end;

  with TTyLabel.Create(Self) do
  begin
    Parent  := Page;
    Caption := '版权所有 © 2026 TyControls';
    SetBounds(12, 44, 260, 22);
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := Page;
    Caption := '查看许可证';
    SetBounds(12, 76, 120, 30);
  end;

  { ── 状态栏 ───────────────────────────────────────────────────────────── }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent  := Self;
  FStatus.SetBounds(16, 268, 448, 22);
  FStatus.Caption := '当前标签页：常规';
end;

{ 标签切换回调：更新状态栏显示当前标签页名称 }
procedure TMainForm.TabChanged(Sender: TObject);
begin
  FStatus.Caption := Format('当前标签页：%s',
    [FTabCtrl.TabCaption(FTabCtrl.TabIndex)]);
end;

end.
