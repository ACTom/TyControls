unit umain;

{ TTyPageControl + TTyTabSheet demo:
  - One TTyPageControl hosting three TTyTabSheet pages (General / Appearance / About)
  - Each page carries different content: labels, buttons, edits
  - Switch ActivePage via the bottom buttons (writing TabIndex / ActivePageIndex / ActivePage)
  - The "Add page" button demonstrates adding a tab at run time via AddPage
  - OnChange event: the status bar shows the current page's title and index live
  The window, the page control, its three pages and every child control (plus the live theme
  switcher) are designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event
  handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.PageControl, tyControls.TabSheet,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    PageCtrl: TTyPageControl;
    PgGeneral: TTyTabSheet;
    LblUser: TTyLabel;
    EdUser: TTyEdit;
    BtnOK1: TTyButton;
    BtnCancel1: TTyButton;
    PgAppearance: TTyTabSheet;
    LblAppearance: TTyLabel;
    BtnLight: TTyButton;
    BtnDark: TTyButton;
    PgAbout: TTyTabSheet;
    LblAboutTitle: TTyLabel;
    LblAboutCopy: TTyLabel;
    BtnLicense: TTyButton;
    BtnGeneral: TTyButton;
    BtnAppearance: TTyButton;
    BtnAbout: TTyButton;
    BtnAddPage: TTyButton;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure PageChanged(Sender: TObject);
    procedure GotoGeneral(Sender: TObject);    { switch via TabIndex }
    procedure GotoAppearance(Sender: TObject); { switch via ActivePageIndex }
    procedure GotoAbout(Sender: TObject);      { switch via ActivePage }
    procedure AddNewPage(Sender: TObject);     { AddPage at run time }
  private
    FExtraCount: Integer;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  { Reflect the initially active page in the status bar (OnChange is not fired during load) }
  LblStatus.Caption := Format('当前页：%s（索引 %d，共 %d 页）',
    [PageCtrl.ActivePage.Caption, PageCtrl.ActivePageIndex, PageCtrl.PageCount]);
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

{ ── Event handlers ───────────────────────────────────────────────────────── }

{ Page-switch callback: update the status bar with the current page's title and index }
procedure TMainForm.PageChanged(Sender: TObject);
begin
  if LblStatus = nil then Exit;   { the status bar isn't streamed yet during the initial auto-select }
  LblStatus.Caption := Format('当前页：%s（索引 %d，共 %d 页）',
    [PageCtrl.ActivePage.Caption, PageCtrl.ActivePageIndex, PageCtrl.PageCount]);
end;

{ Approach 1: write TabIndex directly (the base class's selected index) }
procedure TMainForm.GotoGeneral(Sender: TObject);
begin
  PageCtrl.TabIndex := 0;
end;

{ Approach 2: write ActivePageIndex (the alias published by TTyPageControl) }
procedure TMainForm.GotoAppearance(Sender: TObject);
begin
  PageCtrl.ActivePageIndex := 1;
end;

{ Approach 3: write ActivePage (switch by page object) }
procedure TMainForm.GotoAbout(Sender: TObject);
begin
  PageCtrl.ActivePage := PageCtrl.Pages[2];
end;

{ Add a page dynamically at run time and switch to it immediately }
procedure TMainForm.AddNewPage(Sender: TObject);
var
  NewPage: TTyTabSheet;
begin
  Inc(FExtraCount);
  NewPage := PageCtrl.AddPage(Format('新页 %d', [FExtraCount]));
  with TTyLabel.Create(Self) do
  begin
    Parent  := NewPage;
    Caption := Format('这是运行期第 %d 次新增的页面。', [FExtraCount]);
    SetBounds(16, 20, 460, 22);
  end;
  { switch to the page just added (it's the last one) }
  PageCtrl.ActivePageIndex := PageCtrl.PageCount - 1;
end;

end.
