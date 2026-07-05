unit umain;

{ Ribbon 综合示例(Phase-3 R1-R4):标签 → 分组 → 命令按钮,+ 应用菜单 / 快速访问栏 /
  画廊 / 上下文标签 / 最小化。主窗体 TTyForm + TTyTitleBar,纯代码创建(无 .lfm)。
  glyph 用系统符号字体渲染一个星形(★),真机换成图标 .ttf 更佳。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus,
  tyControls.Controller, tyControls.Form,
  tyControls.Panel, tyControls.Button, tyControls.IconFont, tyControls.GlyphButtons,
  tyControls.Menu, tyControls.Ribbon, tyControls.RibbonAppMenu,
  tyControls.RibbonQuickAccess, tyControls.RibbonGallery;

type
  TMainForm = class(TTyForm)
  private
    FRibbon: TTyRibbon;
    FIcons: TTyIconFont;
    FTableShown: Boolean;
    procedure ToggleContext(Sender: TObject);
    procedure ToggleMinimize(Sender: TObject);
    function NewGroup(APage: TTyRibbonPage; const ACaption: string; AWidth: Integer): TTyRibbonGroup;
    function BigButton(AGroup: TTyRibbonGroup; const ACap: string; AX, AW: Integer): TTyGlyphContainerButton;
    function SmallButton(AGroup: TTyRibbonGroup; const ACap: string; AX, AY, AW: Integer): TTyGlyphButton;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

function ThemesDir: string;
var Dir: string; i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

function TMainForm.NewGroup(APage: TTyRibbonPage; const ACaption: string; AWidth: Integer): TTyRibbonGroup;
begin
  Result := TTyRibbonGroup.Create(Self);
  Result.Parent := APage;      // Align=alLeft flows left->right
  Result.Caption := ACaption;
  Result.Width := AWidth;
end;

function TMainForm.BigButton(AGroup: TTyRibbonGroup; const ACap: string; AX, AW: Integer): TTyGlyphContainerButton;
begin
  Result := TTyGlyphContainerButton.Create(Self);
  Result.Parent := AGroup;
  Result.SetBounds(AX, 4, AW, 64);
  Result.Caption := ACap;
  Result.IconFont := FIcons;
  Result.GlyphName := 'star';
end;

function TMainForm.SmallButton(AGroup: TTyRibbonGroup; const ACap: string; AX, AY, AW: Integer): TTyGlyphButton;
begin
  Result := TTyGlyphButton.Create(Self);
  Result.Parent := AGroup;
  Result.SetBounds(AX, AY, AW, 26);
  Result.Caption := ACap;
  Result.IconFont := FIcons;
  Result.GlyphName := 'star';
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  TopStrip: TTyPanel;
  AppMenu: TTyRibbonAppMenu;
  QAT: TTyRibbonQuickAccess;
  CmdMenu: TTyPopupMenu;
  mi: TMenuItem;
  PgHome, PgInsert, PgTable: TTyRibbonPage;
  g: TTyRibbonGroup;
  Gallery: TTyRibbonGallery;
  BottomBar: TTyPanel;
  BtnCtx, BtnMin: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Ribbon 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 720, 460);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'Ribbon  · TyControls';

  FIcons := TTyIconFont.Create(Self);
  FIcons.MapGlyph('star', $2605);
  FIcons.FontFamily := 'Segoe UI Symbol';

  // Top strip: application menu + quick-access toolbar.
  TopStrip := TTyPanel.Create(Self);
  TopStrip.Parent := Self;
  TopStrip.Align := alTop;
  TopStrip.Height := 30;

  CmdMenu := TTyPopupMenu.Create(Self);
  CmdMenu.Controller := TyDefaultController;
  mi := TMenuItem.Create(CmdMenu); mi.Caption := '新建'; CmdMenu.Items.Add(mi);
  mi := TMenuItem.Create(CmdMenu); mi.Caption := '打开'; CmdMenu.Items.Add(mi);
  mi := TMenuItem.Create(CmdMenu); mi.Caption := '保存'; CmdMenu.Items.Add(mi);

  AppMenu := TTyRibbonAppMenu.Create(Self);
  AppMenu.Parent := TopStrip;
  AppMenu.SetBounds(6, 2, 64, 26);
  AppMenu.Commands := CmdMenu;
  AppMenu.RecentItems.Add('report.docx');
  AppMenu.RecentItems.Add('budget.xlsx');

  QAT := TTyRibbonQuickAccess.Create(Self);
  QAT.Parent := TopStrip;
  QAT.SetBounds(80, 2, 120, 26);
  QAT.AddButton('保存').GlyphName := '';
  QAT.AddButton('撤销').GlyphName := '';

  // The ribbon itself.
  FRibbon := TTyRibbon.Create(Self);
  FRibbon.Parent := Self;    // Align=alTop

  PgHome := FRibbon.AddPage('开始');
  g := NewGroup(PgHome, '剪贴板', 150);
  BigButton(g, '粘贴', 6, 56);
  SmallButton(g, '剪切', 66, 4, 78);
  SmallButton(g, '复制', 66, 34, 78);
  g := NewGroup(PgHome, '字体', 100);
  SmallButton(g, '加粗', 6, 4, 88);
  SmallButton(g, '斜体', 6, 34, 88);

  PgInsert := FRibbon.AddPage('插入');
  g := NewGroup(PgInsert, '样式', 220);
  Gallery := TTyRibbonGallery.Create(Self);
  Gallery.Parent := g;
  Gallery.SetBounds(6, 6, 206, 60);
  Gallery.Items.Add('样式 1');
  Gallery.Items.Add('样式 2');
  Gallery.Items.Add('样式 3');
  Gallery.Items.Add('样式 4');
  Gallery.ItemIndex := 0;

  // A contextual tab: hidden until the 'table' context is shown.
  PgTable := FRibbon.AddPage('表格工具');
  PgTable.Context := 'table';
  g := NewGroup(PgTable, '表格', 120);
  BigButton(g, '选择', 6, 56);

  // Bottom bar: toggles for the contextual tab + minimize.
  BottomBar := TTyPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 44;

  BtnCtx := TTyButton.Create(Self);
  BtnCtx.Parent := BottomBar;
  BtnCtx.SetBounds(16, 8, 160, 30);
  BtnCtx.Caption := '显示/隐藏 表格工具';
  BtnCtx.OnClick := @ToggleContext;

  BtnMin := TTyButton.Create(Self);
  BtnMin.Parent := BottomBar;
  BtnMin.SetBounds(190, 8, 120, 30);
  BtnMin.Caption := '最小化 Ribbon';
  BtnMin.OnClick := @ToggleMinimize;

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.ToggleContext(Sender: TObject);
begin
  FTableShown := not FTableShown;
  if FTableShown then
    FRibbon.ShowContext('table')
  else
    FRibbon.HideContext('table');
end;

procedure TMainForm.ToggleMinimize(Sender: TObject);
begin
  FRibbon.Minimized := not FRibbon.Minimized;
end;

end.
