unit umain;

{ TTyButton demo -- StyleClass variants (default / primary / danger / ghost), Down (sticky
  :selected state), numeric badges (>99 shows 99+), Default (Enter) / Cancel (Esc) / ModalResult,
  & mnemonics, and the disabled state. The window, every button and the live theme switcher are
  designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type

  { TMainForm }

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    BtnDefault: TTyButton;
    BtnPrimary: TTyButton;
    BtnDanger: TTyButton;
    BtnDisabled: TTyButton;
    BtnGhost: TTyButton;
    BtnMsg: TTyButton;
    BtnNotify: TTyButton;
    BtnOK: TTyButton;
    BtnCancel: TTyButton;
    BtnInbox: TTyButton;       // OnBadgeDisplay policy + the bpTopLeft badge corner
    BtnInboxAdd: TTyButton;
    BtnNoAnim: TTyButton;      // AnimationsEnabled = False
    BtnAuto: TTyButton;        // AutoSize = True
    LblAnimBadgeHint: TTyLabel;
    LblAutoHint: TTyLabel;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ButtonClicked(Sender: TObject);
    procedure GhostToggle(Sender: TObject);
    procedure DefaultClicked(Sender: TObject);
    procedure CancelClicked(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    { Badge display policy for BtnInbox: hide the badge entirely while the count is 0
      (the built-in default shows a '0' badge). }
    procedure InboxBadgeDisplay(Sender: TObject; AValue: Integer;
      var AText: string; var AVisible: Boolean);
    { Bump BtnInbox.BadgeValue so the hidden-at-0 badge is watched appearing at 1. }
    procedure AddInbox(Sender: TObject);
  private
    FCount: Integer;
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

procedure TMainForm.ButtonClicked(Sender: TObject);
begin
  Inc(FCount);
  LblStatus.Caption := Format('Click count: %d (%s)',
    [FCount, (Sender as TTyButton).Caption]);
end;

procedure TMainForm.GhostToggle(Sender: TObject);
begin
  with Sender as TTyButton do
    Down := not Down;   // toggle the sticky checked state
  ButtonClicked(Sender);
end;

procedure TMainForm.DefaultClicked(Sender: TObject);
begin
  Inc(FCount);
  LblStatus.Caption := Format('Click count: %d (Default button · Enter/ModalResult=mrOk)', [FCount]);
end;

procedure TMainForm.CancelClicked(Sender: TObject);
begin
  Inc(FCount);
  LblStatus.Caption := Format('Click count: %d (Cancel button · Esc/ModalResult=mrCancel)', [FCount]);
end;

procedure TMainForm.InboxBadgeDisplay(Sender: TObject; AValue: Integer;
  var AText: string; var AVisible: Boolean);
begin
  // The default policy shows the badge even for 0; this one suppresses an empty inbox.
  // (AText could be rewritten here too -- the badge text is not forced to be the number.)
  AVisible := AValue > 0;
end;

procedure TMainForm.AddInbox(Sender: TObject);
begin
  BtnInbox.BadgeValue := BtnInbox.BadgeValue + 1;   // 0 -> 1 makes the badge appear
  Inc(FCount);
  LblStatus.Caption := Format('Click count: %d (Inbox badge value = %d)',
    [FCount, BtnInbox.BadgeValue]);
end;

end.
