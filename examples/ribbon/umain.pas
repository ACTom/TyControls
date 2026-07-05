unit umain;

{ Ribbon 综合示例(Phase-3):标题栏(内含 File 应用菜单 + 快速访问栏)→ Ribbon(标签 → 分组 →
  命令按钮 + 画廊)→ 内容区。点 File 弹出铺满窗口的 backstage(Office「文件」视图)。还有上下文
  标签 + 最小化开关。主窗体 TTyForm + TTyTitleBar,纯代码创建(无 .lfm)。
  glyph 用系统符号字体渲染星形(★),真机换成图标 .ttf 更佳。

  ⚠ LCL 布局坑:同为 alTop/alLeft 的兄弟控件,后添加的排到近边(顶/左)。所以本例按反序创建
  带状控件(先建 Ribbon→在底,标题栏最后建→在顶),每页分组也从右往左加。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus,
  tyControls.Controller, tyControls.Form,
  tyControls.Panel, tyControls.Button, tyControls.IconFont, tyControls.GlyphButtons,
  tyControls.Ribbon, tyControls.RibbonAppMenu, tyControls.RibbonQuickAccess,
  tyControls.RibbonGallery, tyControls.RibbonBackstage;

const
  CTitleH = 34;

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
  Result.Parent := APage;      // Align=alLeft (add right-to-left, see header)
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
  AppMenu: TTyRibbonAppMenu;
  QAT: TTyRibbonQuickAccess;
  Backstage: TTyRibbonBackstage;
  PgHome, PgInsert, PgTable: TTyRibbonPage;
  g: TTyRibbonGroup;
  Gallery: TTyRibbonGallery;
  BottomBar: TTyPanel;
  BtnCtx, BtnMin: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Ribbon 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 760, 480);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  FIcons := TTyIconFont.Create(Self);
  FIcons.MapGlyph('star', $2605);
  FIcons.FontFamily := 'Segoe UI Symbol';

  // The full-window backstage (Office "File" view), shown on the File click.
  Backstage := TTyRibbonBackstage.Create(Self);
  Backstage.Controller := TyDefaultController;
  Backstage.Commands.Add('开始');
  Backstage.Commands.Add('新建');
  Backstage.Commands.Add('打开');
  Backstage.Commands.Add('保存');
  Backstage.Commands.Add('另存为');
  Backstage.Commands.Add('打印');
  Backstage.Commands.Add('导出');
  Backstage.Commands.Add('选项');
  Backstage.ItemIndex := 0;

  // Bottom control bar (alBottom — independent of the alTop stack).
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

  // ── alTop stack, created BOTTOM-first (LCL puts the last-added alTop on top) ──

  // 1) The ribbon — directly BELOW the title bar.
  FRibbon := TTyRibbon.Create(Self);
  FRibbon.Parent := Self;    // Align=alTop

  PgHome := FRibbon.AddPage('开始');
  // Add groups RIGHT-to-LEFT so they flow 剪贴板 | 字体 left->right.
  g := NewGroup(PgHome, '字体', 100);
  SmallButton(g, '加粗', 6, 4, 88);
  SmallButton(g, '斜体', 6, 34, 88);
  g := NewGroup(PgHome, '剪贴板', 150);
  BigButton(g, '粘贴', 6, 56);
  SmallButton(g, '剪切', 66, 4, 78);
  SmallButton(g, '复制', 66, 34, 78);

  PgInsert := FRibbon.AddPage('插入');
  g := NewGroup(PgInsert, '样式', 220);
  Gallery := TTyRibbonGallery.Create(Self);
  Gallery.Parent := g;
  Gallery.SetBounds(6, 6, 206, 60);
  Gallery.Items.Add('样式 1'); Gallery.Items.Add('样式 2');
  Gallery.Items.Add('样式 3'); Gallery.Items.Add('样式 4');
  Gallery.ItemIndex := 0;

  // A contextual tab: hidden until the 'table' context is shown.
  PgTable := FRibbon.AddPage('表格工具');
  PgTable.Context := 'table';
  g := NewGroup(PgTable, '表格', 120);
  BigButton(g, '选择', 6, 56);

  // 2) The title bar LAST → topmost. It hosts the File app-menu + the QAT.
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := CTitleH;
  Bar.Caption := '';         // File + QAT occupy the left; keep the caption clear

  AppMenu := TTyRibbonAppMenu.Create(Self);
  AppMenu.Parent := Bar;     // in the title bar
  AppMenu.SetBounds(6, 4, 56, 26);
  AppMenu.Backstage := Backstage;    // click File -> full-window backstage
  AppMenu.BackstageTopInset := CTitleH;

  QAT := TTyRibbonQuickAccess.Create(Self);
  QAT.Parent := Bar;
  QAT.SetBounds(70, 4, 120, 26);
  QAT.AddButton('保存').GlyphName := '';
  QAT.AddButton('撤销').GlyphName := '';

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
