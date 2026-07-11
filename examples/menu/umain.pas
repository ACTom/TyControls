unit umain;

{ TTyMenuBar + TTyMenuEx + window roll-up demo (TTyForm custom-drawn frame + title bar):
    - TTyMenuBar: top menu bar, bound to a standard LCL TMainMenu (File / Edit / View)
        · Align=alTop docks it below the title bar; Alt+mnemonic (&File -> Alt+F) opens the dropdown
    - TTyMenuEx: enhanced context menu (descends from TTyPopupMenu), attached to the panel's PopupMenu, popped up on right-click
        · Section header: Caption='-Clipboard' -> rendered as a non-clickable "Clipboard" section header (a bare '-' is still a separator)
        · Icon column: an item's ImageIndex draws an icon in the left slot from Images (TTyVirtualImageList, here backed by a TTyImageCollection
          that draws three rounded squares on the fly); checked items show a check mark (the check mark takes priority over the icon)
    - Window roll-up: CaptionAction=tcaRollUp -> double-clicking the title bar collapses the window down to just the title bar, double-click again restores
  All colors/borders/corners/highlights come from theme rules; the UI is built purely in code (no .lfm), themed via the global TyDefaultController. }

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
    FPopup: TTyMenuEx;              // enhanced context menu: section headers + icon column
    FImgColl: TTyImageCollection;   // icon bitmap source
    FImages: TTyVirtualImageList;   // Images for the menu's icon column
    FHintPanel: TTyPanel;
    FStatusLabel: TTyLabel;
    { Generic menu-item click: echo the item's Caption to the status label }
    procedure MenuItemClicked(Sender: TObject);
    { Build the top-level menu bar's data model }
    procedure BuildMainMenu;
    { Build the icon source for the enhanced context menu (TTyImageCollection + TTyVirtualImageList) }
    procedure BuildImages;
    { Build the enhanced popup menu (TTyMenuEx: section headers + icon column + checked items) }
    procedure BuildPopupMenu;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Search upward from the exe's directory for the repo's themes/ folder }
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

{ Create a new TMenuItem: set Caption + OnClick, Owner governs its lifetime }
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
  Result.Caption := '-';   // LCL convention: Caption='-' means a separator
end;

{ Section header: Caption='-text' -> TTyMenuEx renders a non-clickable section header (a bare '-' is still a separator) }
function NewHeader(AOwner: TComponent; const AText: string): TMenuItem;
begin
  Result := TMenuItem.Create(AOwner);
  Result.Caption := '-' + AText;
end;

{ Menu item with an icon: ImageIndex points to an icon in the menu's Images }
function NewIconLeaf(AOwner: TComponent; const ACaption: string;
  AImageIndex: Integer; AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := NewLeaf(AOwner, ACaption, AOnClick);
  Result.ImageIndex := AImageIndex;
end;

{ Checked item: shows a check mark when checked (the check mark takes priority over the icon) }
function NewCheckLeaf(AOwner: TComponent; const ACaption: string;
  AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := NewLeaf(AOwner, ACaption, AOnClick);
  Result.AutoCheck := True;
  Result.Checked := True;
end;

{ Draw a 16px rounded-square icon (in the given color) and add it to the collection; AddBitmap stores a copy, the caller keeps ownership }
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

  { ---- File (Alt+F) ---- }
  TopItem := TMenuItem.Create(FMainMenu);
  TopItem.Caption := '文件(&F)';
  FMainMenu.Items.Add(TopItem);
  TopItem.Add(NewLeaf(FMainMenu, '新建(&N)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '打开…(&O)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '保存(&S)', @MenuItemClicked));
  TopItem.Add(NewSep(FMainMenu));
  TopItem.Add(NewLeaf(FMainMenu, '退出(&X)', @MenuItemClicked));

  { ---- Edit (Alt+E) ---- }
  TopItem := TMenuItem.Create(FMainMenu);
  TopItem.Caption := '编辑(&E)';
  FMainMenu.Items.Add(TopItem);
  TopItem.Add(NewLeaf(FMainMenu, '撤销(&U)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '重做(&R)', @MenuItemClicked));
  TopItem.Add(NewSep(FMainMenu));
  TopItem.Add(NewLeaf(FMainMenu, '剪切(&T)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '复制(&C)', @MenuItemClicked));
  TopItem.Add(NewLeaf(FMainMenu, '粘贴(&P)', @MenuItemClicked));

  { ---- View (Alt+V) ---- }
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
  AddIcon(FImgColl, 'cut',   BGRA(220, 70, 70));    // red
  AddIcon(FImgColl, 'copy',  BGRA(80, 170, 90));    // green
  AddIcon(FImgColl, 'paste', BGRA(70, 120, 220));   // blue
  FImages := TTyVirtualImageList.Create(Self);
  FImages.Collection := FImgColl;
  FImages.Names.Text := 'cut' + LineEnding + 'copy' + LineEnding + 'paste';   // indices 0/1/2
end;

procedure TMainForm.BuildPopupMenu;
begin
  BuildImages;
  FPopup := TTyMenuEx.Create(Self);
  FPopup.Images := FImages;              // icon column
  FPopup.BannerWidth := 26;              // decorative banner on the left (accent-color vertical bar)
  FPopup.BannerCaption := 'TyControls';  // vertical text on the banner
  // section headers ('-text') + items with icons + checked items
  FPopup.Items.Add(NewHeader(FPopup, '剪贴板'));
  FPopup.Items.Add(NewIconLeaf(FPopup, '剪切(&T)', 0, @MenuItemClicked));
  FPopup.Items.Add(NewIconLeaf(FPopup, '复制(&C)', 1, @MenuItemClicked));
  FPopup.Items.Add(NewIconLeaf(FPopup, '粘贴(&P)', 2, @MenuItemClicked));
  FPopup.Items.Add(NewSep(FPopup));
  FPopup.Items.Add(NewHeader(FPopup, '视图'));
  FPopup.Items.Add(NewCheckLeaf(FPopup, '显示网格', @MenuItemClicked));   // shows a check mark when checked
  FPopup.Items.Add(NewLeaf(FPopup, '刷新(&R)', @MenuItemClicked));
  FPopup.Items.Add(NewSep(FPopup));
  FPopup.Items.Add(NewLeaf(FPopup, '属性(&P)', @MenuItemClicked));
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
begin
  // TTyForm.CreateNew -> borderless + persistent engine, but no title bar by default
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyMenuEx / 窗口卷起 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 560, 380);
  CaptionAction := tcaRollUp;   // double-click the title bar -> roll up to the title bar (double-click again restores)

  // the theme must be loaded first
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { ---- top menu bar (built first) ---- }
  // Mind the order: code-created same-direction alTop siblings display in [reverse creation order] -- the last built ends up on top.
  // So the menu bar is built first and the title bar second, so the title bar sits at the very top with the menu bar below it.
  BuildMainMenu;
  FMenuBar := TTyMenuBar.Create(Self);
  FMenuBar.Parent := Self;
  FMenuBar.Align := alTop;
  FMenuBar.Height := 30;
  FMenuBar.Menu := FMainMenu;   // bind the data model; click a top-level item / Alt+mnemonic opens the dropdown
  MenuBar := FMenuBar;          // associate as the form's main menu bar: enables TTyForm.IsShortcut key dispatch

  // title bar (built last -> ends up on top; Owner=Self auto-associates it as TTyForm.TitleBar)
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := '增强菜单 + 双击标题栏卷起  · TyControls';

  { ---- target panel for the context menu ---- }
  BuildPopupMenu;
  FHintPanel := TTyPanel.Create(Self);
  FHintPanel.Parent := Self;
  FHintPanel.Caption := '右键此面板 → 增强菜单(分节标题 + 图标列 + 勾选项)';
  FHintPanel.SetBounds(16, 80, 528, 200);
  FHintPanel.PopupMenu := FPopup;   // attach to the panel: right-click pops the enhanced themed menu

  { ---- status label: echoes menu-item clicks ---- }
  FStatusLabel := TTyLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.SetBounds(16, 296, 528, 24);
  FStatusLabel.Caption := '就绪：右键面板试增强菜单；双击标题栏可卷起窗口（再双击还原）';

  // whole window frame + background color follow the theme
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.MenuItemClicked(Sender: TObject);
var
  Item: TMenuItem;
begin
  if not (Sender is TMenuItem) then Exit;
  Item := TMenuItem(Sender);
  // echo with the mnemonic '&' stripped (StripHotkey is provided by the Menus unit)
  FStatusLabel.Caption := Format('已选择菜单命令：%s', [StripHotkey(Item.Caption)]);
end;

end.
