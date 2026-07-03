unit umain;

{ TTyMenuBar + TTyPopupMenu 示例（TTyForm 自绘窗框 + 标题栏）：
    - TTyMenuBar：顶部菜单栏，绑定标准 LCL 的 TMainMenu 数据模型
        · Menu：关联的 TMainMenu（文件 / 编辑 / 视图 三个顶层项 + 子项）
        · Align=alTop：停靠在标题栏下方，随窗体宽度自动拉伸
        · 顶层项 Alt+助记符（&文件 → Alt+F）打开下拉，子项 OnClick → 状态标签
    - TTyPopupMenu：主题化右键菜单（继承 TPopupMenu）
        · 挂到面板的 PopupMenu 属性上，右键面板即弹出themed菜单
        · 子项 OnClick → 状态标签
  菜单的背景、边框、圆角、悬停高亮均来自主题规则，无需在代码里手写颜色。
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus,
  tyControls.Controller, tyControls.Form,
  tyControls.Menu, tyControls.Panel, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FMainMenu: TMainMenu;
    FMenuBar: TTyMenuBar;
    FPopup: TTyPopupMenu;
    FHintPanel: TTyPanel;
    FStatusLabel: TTyLabel;
    { 通用菜单项点击：把项的 Caption 回显到状态标签 }
    procedure MenuItemClicked(Sender: TObject);
    { 构建顶层菜单栏的数据模型 }
    procedure BuildMainMenu;
    { 构建右键弹出菜单的数据模型 }
    procedure BuildPopupMenu;
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

{ 新建一个 TMenuItem：设 Caption + OnClick，Owner 决定生命周期 }
function NewLeaf(AOwner: TComponent; const ACaption: string;
  AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AOwner);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
end;

function NewSep(AOwner: TComponent): TMenuItem;
begin
  Result := TMenuItem.Create(AOwner);
  Result.Caption := '-';   // LCL 约定：Caption='-' 即分隔线
end;

procedure TMainForm.BuildMainMenu;
var
  TopItem: TMenuItem;
begin
  FMainMenu := TMainMenu.Create(Self);

  { ---- 文件（Alt+F） ---- }
  TopItem := TMenuItem.Create(FMainMenu);
  TopItem.Caption := '文件(&F)';
  FMainMenu.Items.Add(TopItem);
  TopItem.Add(NewLeaf(FMainMenu, '新建(&N)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '打开…(&O)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '保存(&S)', @MenuItemClicked));
  TopItem.Add(NewSep(FMainMenu));
  TopItem.Add(NewLeaf(FMainMenu, '退出(&X)', @MenuItemClicked));

  { ---- 编辑（Alt+E） ---- }
  TopItem := TMenuItem.Create(FMainMenu);
  TopItem.Caption := '编辑(&E)';
  FMainMenu.Items.Add(TopItem);
  TopItem.Add(NewLeaf(FMainMenu, '撤销(&U)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '重做(&R)', @MenuItemClicked));
  TopItem.Add(NewSep(FMainMenu));
  TopItem.Add(NewLeaf(FMainMenu, '剪切(&T)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '复制(&C)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '粘贴(&P)', @MenuItemClicked));

  { ---- 视图（Alt+V） ---- }
  TopItem := TMenuItem.Create(FMainMenu);
  TopItem.Caption := '视图(&V)';
  FMainMenu.Items.Add(TopItem);
  TopItem.Add(NewLeaf(FMainMenu, '放大(&I)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '缩小(&O)', @MenuItemClicked));
  TopItem.Add(NewSep(FMainMenu));
  TopItem.Add(NewLeaf(FMainMenu, '全屏(&F)', @MenuItemClicked));
end;

procedure TMainForm.BuildPopupMenu;
begin
  FPopup := TTyPopupMenu.Create(Self);
  FPopup.Items.Add(NewLeaf(FPopup, '刷新(&R)', @MenuItemClicked));
  FPopup.Items.Add(NewLeaf(FPopup, '重命名(&M)', @MenuItemClicked));
  FPopup.Items.Add(NewSep(FPopup));
  FPopup.Items.Add(NewLeaf(FPopup, '属性(&P)', @MenuItemClicked));
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
begin
  // TTyForm.CreateNew → 无边框 + 持久引擎，但默认无标题栏
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyMenuBar / TTyPopupMenu 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 560, 380);

  // 主题须先加载
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 标题栏：Owner=Self 即自动关联为 TTyForm.TitleBar
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyMenuBar / TTyPopupMenu  · TyControls';

  { ---- 顶部菜单栏 ---- }
  BuildMainMenu;
  FMenuBar := TTyMenuBar.Create(Self);
  FMenuBar.Parent := Self;
  FMenuBar.Align := alTop;      // 紧贴标题栏下方，宽度随窗体拉伸
  FMenuBar.Height := 30;
  FMenuBar.Menu := FMainMenu;   // 绑定数据模型；点顶层项 / Alt+助记符打开下拉
  MenuBar := FMenuBar;          // 关联为窗体主菜单栏：启用 TTyForm.IsShortcut 快捷键派发

  { ---- 右键菜单目标面板 ---- }
  BuildPopupMenu;
  FHintPanel := TTyPanel.Create(Self);
  FHintPanel.Parent := Self;
  FHintPanel.Caption := '在此面板上点击鼠标右键 → 弹出主题化右键菜单';
  FHintPanel.SetBounds(16, 80, 528, 200);
  FHintPanel.PopupMenu := FPopup;   // 挂到面板：右键即弹themed菜单

  { ---- 状态标签：菜单项点击回显 ---- }
  FStatusLabel := TTyLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.SetBounds(16, 296, 528, 24);
  FStatusLabel.Caption := '就绪：从上方菜单栏选择命令，或右键面板试试…';

  // 整套窗框 + 背景色随主题
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.MenuItemClicked(Sender: TObject);
var
  Item: TMenuItem;
begin
  if not (Sender is TMenuItem) then Exit;
  Item := TMenuItem(Sender);
  // 去掉助记符 '&' 后回显（StripHotkey 由 Menus 单元提供）
  FStatusLabel.Caption := Format('已选择菜单命令：%s', [StripHotkey(Item.Caption)]);
end;

end.
