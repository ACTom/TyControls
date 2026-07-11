unit umain;

{ TTyPageControl + TTyTabSheet demo:
  - One TTyPageControl hosting three TTyTabSheet pages (General / Appearance / About)
  - Each page carries different content: labels, buttons, edits
  - Switch ActivePage via the bottom buttons (writing TabIndex / ActivePageIndex / ActivePage)
  - The "Add page" button demonstrates adding a tab at run time via AddPage
  - OnChange event: the status bar shows the current page's title and index live
  UI is built entirely in code (no .lfm); the theme is loaded through the global TyDefaultController. }

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
    procedure GotoGeneral(Sender: TObject);   { switch via TabIndex }
    procedure GotoAppearance(Sender: TObject); { switch via ActivePageIndex }
    procedure GotoAbout(Sender: TObject);      { switch via ActivePage }
    procedure AddNewPage(Sender: TObject);     { AddPage at run time }
    procedure BuildGeneralPage(APage: TTyTabSheet);
    procedure BuildAppearancePage(APage: TTyTabSheet);
    procedure BuildAboutPage(APage: TTyTabSheet);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ directory (handles lib/<cpu>-<os>/ and .app bundles) }
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
  Result := 'themes' + PathDelim; { fallback: relative to the current directory }
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  P1, P2, P3: TTyTabSheet;
begin
  inherited CreateNew(AOwner, 0);          { TTyForm: borderless + resident theme engine }
  Caption  := 'TTyPageControl 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 560, 420);

  { Load the light theme first; controls without an explicit Controller fall back to the global TyDefaultController }
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { ── Title bar (Owner=Self auto-associates it as TTyForm.TitleBar) ─────── }
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent  := Self;
  Bar.Align   := alTop;
  Bar.Height  := 34;
  Bar.Caption := 'TTyPageControl  · TyControls';

  { ── Page control ─────────────────────────────────────────────────────── }
  FPageCtrl := TTyPageControl.Create(Self);
  FPageCtrl.Parent    := Self;
  FPageCtrl.SetBounds(16, 48, 528, 296);
  FPageCtrl.TabHeight := 32;             { tab header height (logical pixels) }
  FPageCtrl.OnChange  := @PageChanged;   { update the status bar on page switch }

  { Three pages: AddPage returns a TTyTabSheet; its Caption is the tab label }
  P1 := FPageCtrl.AddPage('常规');
  P2 := FPageCtrl.AddPage('外观');
  P3 := FPageCtrl.AddPage('关于');

  BuildGeneralPage(P1);
  BuildAppearancePage(P2);
  BuildAboutPage(P3);

  { ── Bottom switch buttons: each demonstrates one of the three switch APIs ─ }
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

  { ── Status bar ───────────────────────────────────────────────────────── }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 394, 528, 20);
  FStatus.Caption := Format('当前页：%s（索引 %d，共 %d 页）',
    [FPageCtrl.ActivePage.Caption, FPageCtrl.ActivePageIndex, FPageCtrl.PageCount]);

  ApplyChromeTheme(TyDefaultController);  { finally, apply window chrome + background tint uniformly }
end;

{ ── Per-page content: child controls parent to the TTyTabSheet (page is alClient, coords relative to the page) ─ }

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

{ ── Event handlers ───────────────────────────────────────────────────────── }

{ Page-switch callback: update the status bar with the current page's title and index }
procedure TMainForm.PageChanged(Sender: TObject);
begin
  if FStatus = nil then Exit;   { the status bar isn't built yet during the initial auto-select }
  FStatus.Caption := Format('当前页：%s（索引 %d，共 %d 页）',
    [FPageCtrl.ActivePage.Caption, FPageCtrl.ActivePageIndex, FPageCtrl.PageCount]);
end;

{ Approach 1: write TabIndex directly (the base class's selected index) }
procedure TMainForm.GotoGeneral(Sender: TObject);
begin
  FPageCtrl.TabIndex := 0;
end;

{ Approach 2: write ActivePageIndex (the alias published by TTyPageControl) }
procedure TMainForm.GotoAppearance(Sender: TObject);
begin
  FPageCtrl.ActivePageIndex := 1;
end;

{ Approach 3: write ActivePage (switch by page object) }
procedure TMainForm.GotoAbout(Sender: TObject);
begin
  FPageCtrl.ActivePage := FPageCtrl.Pages[2];
end;

{ Add a page dynamically at run time and switch to it immediately }
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
  { switch to the page just added (it's the last one) }
  FPageCtrl.ActivePageIndex := FPageCtrl.PageCount - 1;
end;

end.
