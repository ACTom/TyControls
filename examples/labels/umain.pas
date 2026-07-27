unit umain;

{ Label family demo: plain label / hyperlink label / shadow label / glow label.

  Each class is shown in more than one mode, so the properties read as a range and not as a
  fixed decoration: TTyLinkLabel appears with AutoOpen = True (the click opens a browser) and
  with AutoOpen = False (the click is the app's, handled in OnClick); TTyShadowLabel appears
  with the shadow falling down-right and up-left; TTyGlowLabel appears at GlowRadius 5, 0
  (the documented no-blur mode) and 14. The three specialised labels also carry three
  different Alignment values, so the way each one re-lays its content is visible at a glance.

  The window, every label and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is theme setup, the TTyColor values
  (constructed via TyRGBA -- they are $AARRGGBB Cardinals and cannot live in a .lfm)
  and the one in-app link handler. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.LinkLabel, tyControls.ShadowLabel, tyControls.GlowLabel,
  tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblPlain: TTyLabel;
    LblHdrLink: TTyLabel;
    LblLink: TTyLinkLabel;
    LblAction: TTyLinkLabel;
    LblHdrShadow: TTyLabel;
    LblShadow: TTyShadowLabel;
    LblShadowUp: TTyShadowLabel;
    LblHdrGlow: TTyLabel;
    LblGlow: TTyGlowLabel;
    LblGlow0: TTyGlowLabel;
    LblGlow14: TTyGlowLabel;
    procedure FormCreate(Sender: TObject);
    procedure LblActionClick(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
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

  // TTyColor values are $AARRGGBB Cardinals; set them via TyRGBA (not the .lfm).
  // Both shadows share one colour so only the OFFSET differs between them, and all
  // three glows share one colour so only the RADIUS differs.
  LblShadow.ShadowColor := TyRGBA(0, 0, 0, 150);
  LblShadowUp.ShadowColor := TyRGBA(0, 0, 0, 150);
  LblGlow.GlowColor := TyRGBA($3B, $82, $F6, 200);
  LblGlow0.GlowColor := TyRGBA($3B, $82, $F6, 200);
  LblGlow14.GlowColor := TyRGBA($3B, $82, $F6, 200);
end;

procedure TMainForm.LblActionClick(Sender: TObject);
begin
  // AutoOpen = False, so the click never reaches OpenURL: the app decides what the link does.
  // This is the mode you want for "next step", "show details", "undo" and friends.
  LblAction.Caption := 'OnClick fired — AutoOpen = False lets the app decide';
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

end.
