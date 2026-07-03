unit umain;

{ TTyPageControl + TTyTabSheet 示例：
  - 一个 TTyPageControl，内含三个 TTyTabSheet 页面（常规 / 外观 / 关于）
  - 每个页面承载不同内容：标签、按钮、输入框
  - 通过底部按钮切换 ActivePage（写 TabIndex / ActivePageIndex / ActivePage）
  - “新增页面”按钮演示运行期 AddPage 动态添加标签页
  - OnChange 事件：状态栏实时显示当前页标题与索引
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.PageControl, tyControls.TabSheet,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit;

type
  TMainForm = class(TTyForm)
  private
    FPageCtrl: TTyPageControl;
    FStatus:   TTyLabel;
    FExtraCount: Integer;
    procedure PageChanged(Sender: TObject);
    procedure GotoGeneral(Sender: TObject);   { 用 TabIndex 切换 }
    procedure GotoAppearance(Sender: TObject); { 用 ActivePageIndex 切换 }
    procedure GotoAbout(Sender: TObject);      { 用 ActivePage 切换 }
    procedure AddNewPage(Sender: TObject);     { 运行期 AddPage }
    procedure BuildGeneralPage(APage: TTyTabSheet);
    procedure BuildAppearancePage(APage: TTyTabSheet);
    procedure BuildAboutPage(APage: TTyTabSheet);
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
  Bar: TTyTitleBar;
  P1, P2, P3: TTyTabSheet;
begin
  inherited CreateNew(AOwner, 0);          { TTyForm：无边框 + 常驻主题引擎 }
  Caption  := 'TTyPageControl 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 560, 420);

  { 先加载亮色主题；未指定 Controller 的控件自动使用全局 TyDefaultController }
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { ── 标题栏（Owner=Self 自动关联为 TTyForm.TitleBar） ─────────────────── }
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent  := Self;
  Bar.Align   := alTop;
  Bar.Height  := 34;
  Bar.Caption := 'TTyPageControl  · TyControls';

  { ── 页控件 ───────────────────────────────────────────────────────────── }
  FPageCtrl := TTyPageControl.Create(Self);
  FPageCtrl.Parent    := Self;
  FPageCtrl.SetBounds(16, 48, 528, 296);
  FPageCtrl.TabHeight := 32;             { 页签头高度（逻辑像素） }
  FPageCtrl.OnChange  := @PageChanged;   { 页切换时更新状态栏 }

  { 三个页面：AddPage 返回 TTyTabSheet；Caption 即页签标签 }
  P1 := FPageCtrl.AddPage('常规');
  P2 := FPageCtrl.AddPage('外观');
  P3 := FPageCtrl.AddPage('关于');

  BuildGeneralPage(P1);
  BuildAppearancePage(P2);
  BuildAboutPage(P3);

  { ── 底部切换按钮：分别演示三种切换 API ───────────────────────────────── }
  with TTyButton.Create(Self) do
  begin
    Parent  := Self;
    Caption := '常规';
    SetBounds(16, 356, 84, 30);
    OnClick := @GotoGeneral;
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := Self;
    Caption := '外观';
    SetBounds(108, 356, 84, 30);
    OnClick := @GotoAppearance;
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := Self;
    Caption := '关于';
    SetBounds(200, 356, 84, 30);
    OnClick := @GotoAbout;
  end;

  with TTyButton.Create(Self) do
  begin
    Parent     := Self;
    Caption    := '＋ 新增页面';
    SetBounds(300, 356, 120, 30);
    StyleClass := 'primary';
    OnClick    := @AddNewPage;
  end;

  { ── 状态栏 ───────────────────────────────────────────────────────────── }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 394, 528, 20);
  FStatus.Caption := Format('当前页：%s（索引 %d，共 %d 页）',
    [FPageCtrl.ActivePage.Caption, FPageCtrl.ActivePageIndex, FPageCtrl.PageCount]);

  ApplyChromeTheme(TyDefaultController);  { 最后统一为整窗 chrome + 背景着色 }
end;

{ ── 各页内容：控件父级为 TTyTabSheet（页面为 alClient，坐标相对页面） ───── }

procedure TMainForm.BuildGeneralPage(APage: TTyTabSheet);
begin
  with TTyLabel.Create(Self) do
  begin
    Parent  := APage;
    Caption := '用户名：';
    SetBounds(16, 20, 80, 22);
  end;

  with TTyEdit.Create(Self) do
  begin
    Parent   := APage;
    Text     := 'admin';
    SetBounds(100, 16, 200, 30);
  end;

  with TTyButton.Create(Self) do
  begin
    Parent     := APage;
    Caption    := '确定';
    SetBounds(16, 60, 90, 30);
    StyleClass := 'primary';
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := APage;
    Caption := '取消';
    SetBounds(116, 60, 90, 30);
  end;
end;

procedure TMainForm.BuildAppearancePage(APage: TTyTabSheet);
begin
  with TTyLabel.Create(Self) do
  begin
    Parent  := APage;
    Caption := '这里是「外观」页，可放置主题相关选项。';
    SetBounds(16, 20, 460, 22);
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := APage;
    Caption := '浅色';
    SetBounds(16, 56, 90, 30);
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := APage;
    Caption := '深色';
    SetBounds(116, 56, 90, 30);
  end;
end;

procedure TMainForm.BuildAboutPage(APage: TTyTabSheet);
begin
  with TTyLabel.Create(Self) do
  begin
    Parent  := APage;
    Caption := 'TyControls 页控件示例';
    SetBounds(16, 20, 300, 22);
  end;

  with TTyLabel.Create(Self) do
  begin
    Parent  := APage;
    Caption := '版权所有 © 2026 TyControls';
    SetBounds(16, 48, 300, 22);
  end;

  with TTyButton.Create(Self) do
  begin
    Parent  := APage;
    Caption := '查看许可证';
    SetBounds(16, 84, 120, 30);
  end;
end;

{ ── 事件处理 ─────────────────────────────────────────────────────────────── }

{ 页切换回调：更新状态栏显示当前页标题与索引 }
procedure TMainForm.PageChanged(Sender: TObject);
begin
  if FStatus = nil then Exit;   { 首次自动选页时状态栏尚未创建 }
  FStatus.Caption := Format('当前页：%s（索引 %d，共 %d 页）',
    [FPageCtrl.ActivePage.Caption, FPageCtrl.ActivePageIndex, FPageCtrl.PageCount]);
end;

{ 方式一：直接写 TabIndex（基类选择索引） }
procedure TMainForm.GotoGeneral(Sender: TObject);
begin
  FPageCtrl.TabIndex := 0;
end;

{ 方式二：写 ActivePageIndex（TTyPageControl 发布的别名） }
procedure TMainForm.GotoAppearance(Sender: TObject);
begin
  FPageCtrl.ActivePageIndex := 1;
end;

{ 方式三：写 ActivePage（按页面对象切换） }
procedure TMainForm.GotoAbout(Sender: TObject);
begin
  FPageCtrl.ActivePage := FPageCtrl.Pages[2];
end;

{ 运行期动态新增一页，并立即切换过去 }
procedure TMainForm.AddNewPage(Sender: TObject);
var
  NewPage: TTyTabSheet;
begin
  Inc(FExtraCount);
  NewPage := FPageCtrl.AddPage(Format('新页 %d', [FExtraCount]));
  with TTyLabel.Create(Self) do
  begin
    Parent  := NewPage;
    Caption := Format('这是运行期第 %d 次新增的页面。', [FExtraCount]);
    SetBounds(16, 20, 460, 22);
  end;
  { 切换到刚新增的页（它是最后一页） }
  FPageCtrl.ActivePageIndex := FPageCtrl.PageCount - 1;
end;

end.
