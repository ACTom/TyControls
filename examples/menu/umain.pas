unit umain;

{ TTyMenuBar + TTyMenuEx + 窗口卷起 示例（TTyForm 自绘窗框 + 标题栏）：
    - TTyMenuBar：顶部菜单栏，绑定标准 LCL 的 TMainMenu（文件 / 编辑 / 视图）
        · Align=alTop 停靠在标题栏下方；Alt+助记符（&文件 → Alt+F）打开下拉
    - TTyMenuEx：增强右键菜单（继承 TTyPopupMenu），挂在面板的 PopupMenu 上，右键弹出
        · 分节标题：Caption='-剪贴板' → 渲染成不可点的“剪贴板”分节标题（纯 '-' 仍是分隔线）
        · 图标列：项的 ImageIndex 从 Images（TTyVirtualImageList，本例用 TTyImageCollection
          现画三个圆角方块）在左槽画图标；勾选项显示对勾（对勾优先于图标）
    - 窗口卷起：CaptionAction=tcaRollUp → 双击标题栏把窗口收起到只剩标题栏，再双击还原
  所有颜色/边框/圆角/高亮均来自主题规则；纯代码创建 UI（无 .lfm），主题走全局 TyDefaultController。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus, BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Form, tyControls.ImageCollection,
  tyControls.Menu, tyControls.Panel, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FMainMenu: TMainMenu;
    FMenuBar: TTyMenuBar;
    FPopup: TTyMenuEx;              // 增强右键菜单:分节标题 + 图标列
    FImgColl: TTyImageCollection;   // 图标位图源
    FImages: TTyVirtualImageList;   // 菜单图标列的 Images
    FHintPanel: TTyPanel;
    FStatusLabel: TTyLabel;
    { 通用菜单项点击：把项的 Caption 回显到状态标签 }
    procedure MenuItemClicked(Sender: TObject);
    { 构建顶层菜单栏的数据模型 }
    procedure BuildMainMenu;
    { 构建增强右键菜单的图标源(TTyImageCollection + TTyVirtualImageList) }
    procedure BuildImages;
    { 构建增强右键弹出菜单(TTyMenuEx:分节标题 + 图标列 + 勾选项) }
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

{ 分节标题：Caption='-文本' → TTyMenuEx 渲染成不可点的分节标题（纯 '-' 仍是分隔线） }
function NewHeader(AOwner: TComponent; const AText: string): TMenuItem;
begin
  Result := TMenuItem.Create(AOwner);
  Result.Caption := '-' + AText;
end;

{ 带图标的菜单项：ImageIndex 指向菜单 Images 里的图标 }
function NewIconLeaf(AOwner: TComponent; const ACaption: string;
  AImageIndex: Integer; AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := NewLeaf(AOwner, ACaption, AOnClick);
  Result.ImageIndex := AImageIndex;
end;

{ 勾选项：勾选态显示对勾（对勾优先于图标） }
function NewCheckLeaf(AOwner: TComponent; const ACaption: string;
  AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := NewLeaf(AOwner, ACaption, AOnClick);
  Result.AutoCheck := True;
  Result.Checked := True;
end;

{ 画一个 16px 圆角方块图标（指定颜色）加进集合；AddBitmap 复制存储，调用方保留所有权 }
procedure AddIcon(AColl: TTyImageCollection; const AName: string; AColor: TBGRAPixel);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(16, 16, BGRAPixelTransparent);
  try
    bmp.FillRoundRectAntialias(1.5, 1.5, 14.5, 14.5, 4, 4, AColor);
    AColl.AddBitmap(AName, bmp);
  finally
    bmp.Free;
  end;
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

procedure TMainForm.BuildImages;
begin
  FImgColl := TTyImageCollection.Create(Self);
  AddIcon(FImgColl, 'cut',   BGRA(220, 70, 70));    // 红
  AddIcon(FImgColl, 'copy',  BGRA(80, 170, 90));    // 绿
  AddIcon(FImgColl, 'paste', BGRA(70, 120, 220));   // 蓝
  FImages := TTyVirtualImageList.Create(Self);
  FImages.Collection := FImgColl;
  FImages.Names.Text := 'cut' + LineEnding + 'copy' + LineEnding + 'paste';   // 索引 0/1/2
end;

procedure TMainForm.BuildPopupMenu;
begin
  BuildImages;
  FPopup := TTyMenuEx.Create(Self);
  FPopup.Images := FImages;              // 图标列
  FPopup.BannerWidth := 26;              // 左侧装饰 banner(强调色竖条)
  FPopup.BannerCaption := 'TyControls';  // banner 上竖排文字
  // 分节标题（'-文本'）+ 带图标的项 + 勾选项
  FPopup.Items.Add(NewHeader(FPopup, '剪贴板'));
  FPopup.Items.Add(NewIconLeaf(FPopup, '剪切(&T)', 0, @MenuItemClicked));
  FPopup.Items.Add(NewIconLeaf(FPopup, '复制(&C)', 1, @MenuItemClicked));
  FPopup.Items.Add(NewIconLeaf(FPopup, '粘贴(&P)', 2, @MenuItemClicked));
  FPopup.Items.Add(NewSep(FPopup));
  FPopup.Items.Add(NewHeader(FPopup, '视图'));
  FPopup.Items.Add(NewCheckLeaf(FPopup, '显示网格', @MenuItemClicked));   // 勾选态显示对勾
  FPopup.Items.Add(NewLeaf(FPopup, '刷新(&R)', @MenuItemClicked));
  FPopup.Items.Add(NewSep(FPopup));
  FPopup.Items.Add(NewLeaf(FPopup, '属性(&P)', @MenuItemClicked));
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
begin
  // TTyForm.CreateNew → 无边框 + 持久引擎，但默认无标题栏
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyMenuEx / 窗口卷起 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 560, 380);
  CaptionAction := tcaRollUp;   // 双击标题栏 → 卷起到标题栏(再双击还原)

  // 主题须先加载
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { ---- 顶部菜单栏（先建）---- }
  // 注意顺序：代码建的同向 alTop 兄弟按【反创建序】显示——后建的排到最上方。
  // 所以菜单栏先建、标题栏后建，标题栏才会压在最顶、菜单栏在其下方。
  BuildMainMenu;
  FMenuBar := TTyMenuBar.Create(Self);
  FMenuBar.Parent := Self;
  FMenuBar.Align := alTop;
  FMenuBar.Height := 30;
  FMenuBar.Menu := FMainMenu;   // 绑定数据模型；点顶层项 / Alt+助记符打开下拉
  MenuBar := FMenuBar;          // 关联为窗体主菜单栏：启用 TTyForm.IsShortcut 快捷键派发

  // 标题栏（后建 → 排到最上方；Owner=Self 即自动关联为 TTyForm.TitleBar）
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := '增强菜单 + 双击标题栏卷起  · TyControls';

  { ---- 右键菜单目标面板 ---- }
  BuildPopupMenu;
  FHintPanel := TTyPanel.Create(Self);
  FHintPanel.Parent := Self;
  FHintPanel.Caption := '右键此面板 → 增强菜单(分节标题 + 图标列 + 勾选项)';
  FHintPanel.SetBounds(16, 80, 528, 200);
  FHintPanel.PopupMenu := FPopup;   // 挂到面板：右键即弹增强 themed 菜单

  { ---- 状态标签：菜单项点击回显 ---- }
  FStatusLabel := TTyLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.SetBounds(16, 296, 528, 24);
  FStatusLabel.Caption := '就绪：右键面板试增强菜单；双击标题栏可卷起窗口（再双击还原）';

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
