unit umain;

{ TTyPageControl + TTyTabSheet demo:
  - One TTyPageControl hosting three TTyTabSheet pages (General / Appearance / About)
  - Each page carries different content: labels, buttons, edits
  - Switch ActivePage via the bottom buttons (writing TabIndex / ActivePageIndex / ActivePage)
  - The "Add page" button demonstrates adding a tab at run time via AddPage
  - OnChange event: the status bar shows the current page's title and index live
  - The interactive tab-header side of the control: TabsClosable + OnTabClose (close x with a
    veto), RemovePage, the OnChanging pre-switch veto, OnReorder (drag a header sideways),
    TabHeight = 0 (no strip at all) and the '&' mnemonic captions behind Alt+letter
  The window, the page control, its three pages and every child control (plus the live theme
  switcher) are designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event
  handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Accel,
  tyControls.PageControl, tyControls.TabSheet,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
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
    BtnRemovePage: TTyButton;
    LblStatus: TTyLabel;
    LblHeaderSection: TTyLabel;
    BtnToggleStrip: TTyButton;
    LblStripHint: TTyLabel;
    LblCloseHint: TTyLabel;
    LblReorderHint: TTyLabel;
    LblKeysHint: TTyLabel;
    LblOverflowHint: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure PageChanged(Sender: TObject);
    procedure PageChanging(Sender: TObject; ANewIndex: Integer;
      var AllowChange: Boolean);                                  { pre-switch veto }
    procedure PageClosing(Sender: TObject; AIndex: Integer;
      var AllowClose: Boolean);                                   { close (x) veto }
    procedure PagesReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
    procedure GotoGeneral(Sender: TObject);    { switch via TabIndex }
    procedure GotoAppearance(Sender: TObject); { switch via ActivePageIndex }
    procedure GotoAbout(Sender: TObject);      { switch via ActivePage }
    procedure AddNewPage(Sender: TObject);     { AddPage at run time }
    procedure RemoveCurrentPage(Sender: TObject); { RemovePage at run time }
    procedure ToggleStrip(Sender: TObject);       { TabHeight 32 <-> 0 }
  private
    FExtraCount: Integer;
    function PageTitle(APage: TTyTabSheet): string;
    function IsFixedPage(APage: TTyTabSheet): Boolean;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { Status texts and run-time page captions composed in code, so they live here
    rather than in the .lfm. }
  rsCurPageFmt   = 'Current page: %s (index %d of %d pages)';
  rsNoPage       = '(none)';
  rsNeedUsername = 'Enter a username before leaving this page (blocked by OnChanging).';
  rsClosingFmt   = 'Closing page: %s';
  rsCloseVetoFmt = '"%s" is a designed page - OnTabClose vetoed the close.';
  rsReorderedFmt = 'Pages reordered: %d -> %d (current: %s)';
  rsNewPageFmt   = 'New page %d';
  rsNewPageBody  = 'This is the %dth page added at runtime.';
  rsOnlyRuntime  = 'Only a page added at run time can be removed - add one first.';
  rsRemovedFmt   = 'RemovePage removed "%s"; %d pages left.';
  rsHideStrip    = 'Hide tab strip';
  rsStripBack    = 'TabHeight = 32: the header strip is back.';
  rsShowStrip    = 'Show tab strip';
  rsStripGone    = 'TabHeight = 0: no strip - the buttons above are the only pager.';

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
  LblStatus.Caption := Format(rsCurPageFmt,
    [PageTitle(PageCtrl.ActivePage), PageCtrl.ActivePageIndex, PageCtrl.PageCount]);
end;

{ ── Small helpers ────────────────────────────────────────────────────────── }

{ The tab caption with its '&' mnemonic marker removed, for status-bar display
  (the header itself draws the marked letter underlined while Alt is held). }
function TMainForm.PageTitle(APage: TTyTabSheet): string;
var
  Display: string;
  MnemonicPos: Integer;
begin
  if APage = nil then
    Exit(rsNoPage);
  TyParseMnemonic(APage.Caption, Display, MnemonicPos);
  Result := Display;
end;

{ True for the three pages designed in umain.lfm. Closing a page FREES it, and
  those three are form fields, so a demo that let them go would leave PgGeneral /
  PgAppearance / PgAbout dangling -- the close veto below refuses them instead. }
function TMainForm.IsFixedPage(APage: TTyTabSheet): Boolean;
begin
  Result := (APage = PgGeneral) or (APage = PgAppearance) or (APage = PgAbout);
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
  LblStatus.Caption := Format(rsCurPageFmt,
    [PageTitle(PageCtrl.ActivePage), PageCtrl.ActivePageIndex, PageCtrl.PageCount]);
end;

{ Pre-switch veto (OnChanging). Fired BEFORE the selection moves; clearing
  AllowChange aborts the whole switch -- no page change, no OnChange, no header
  fade. Here the Normal page refuses to be left while its username is blank, so
  clear the edit and every tab / nav button stops working until you refill it. }
procedure TMainForm.PageChanging(Sender: TObject; ANewIndex: Integer;
  var AllowChange: Boolean);
begin
  if (LblStatus = nil) or (EdUser = nil) then Exit;
  if (PageCtrl.ActivePage = PgGeneral) and (Trim(EdUser.Text) = '') then
  begin
    AllowChange := False;
    LblStatus.Caption := rsNeedUsername;
  end;
end;

{ Close (x) veto (OnTabClose). TabsClosable = True draws the glyph; this handler
  decides whether the click is honoured. Leaving AllowClose True lets the control
  free the page and fix up ActivePageIndex itself. }
procedure TMainForm.PageClosing(Sender: TObject; AIndex: Integer;
  var AllowClose: Boolean);
var
  Page: TTyTabSheet;
begin
  Page := PageCtrl.Pages[AIndex];
  AllowClose := not IsFixedPage(Page);
  if LblStatus = nil then Exit;
  if AllowClose then
    LblStatus.Caption := Format(rsClosingFmt, [PageTitle(Page)])
  else
    LblStatus.Caption := Format(rsCloseVetoFmt, [PageTitle(Page)]);
end;

{ Drag-reorder notification (OnReorder): fired once per committed gesture with the
  net from -> to move after the header has been dragged sideways. }
procedure TMainForm.PagesReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
begin
  if LblStatus = nil then Exit;
  LblStatus.Caption := Format(rsReorderedFmt,
    [AFromIndex, AToIndex, PageTitle(PageCtrl.ActivePage)]);
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
  NewPage := PageCtrl.AddPage(Format(rsNewPageFmt, [FExtraCount]));
  with TTyLabel.Create(Self) do
  begin
    Parent  := NewPage;
    Caption := Format(rsNewPageBody, [FExtraCount]);
    SetBounds(16, 20, 460, 22);
  end;
  { switch to the page just added (it's the last one) }
  PageCtrl.ActivePageIndex := PageCtrl.PageCount - 1;
end;

{ RemovePage is the programmatic twin of the close (x): it frees the page and fixes
  up ActivePageIndex, firing OnChange when the active page had to move. Same rule as
  the close veto -- only a run-time page may go. }
procedure TMainForm.RemoveCurrentPage(Sender: TObject);
var
  Page: TTyTabSheet;
  Gone: string;
begin
  Page := PageCtrl.ActivePage;
  if Page = nil then Exit;
  if IsFixedPage(Page) then
  begin
    LblStatus.Caption := rsOnlyRuntime;
    Exit;
  end;
  Gone := PageTitle(Page);
  PageCtrl.RemovePage(PageCtrl.ActivePageIndex);
  LblStatus.Caption := Format(rsRemovedFmt, [Gone, PageCtrl.PageCount]);
end;

{ TabHeight = 0 means NO header strip: the pages fill the whole control and the host
  drives paging itself (the sider / segmented-control scenario). With the strip gone
  the Normal / Appearance / About buttons are the only way to change page. }
procedure TMainForm.ToggleStrip(Sender: TObject);
begin
  if PageCtrl.TabHeight = 0 then
  begin
    PageCtrl.TabHeight := 32;
    BtnToggleStrip.Caption := rsHideStrip;
    LblStatus.Caption := rsStripBack;
  end
  else
  begin
    PageCtrl.TabHeight := 0;
    BtnToggleStrip.Caption := rsShowStrip;
    LblStatus.Caption := rsStripGone;
  end;
end;

end.
