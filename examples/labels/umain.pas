unit umain;

{ Label family demo: plain label / hyperlink label / shadow label / glow label.
  The window, every label and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is theme setup + the two TTyColor
  values (constructed via TyRGBA) only. }

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
    ThemeCombo: TTyComboBox;
    LblPlain: TTyLabel;
    LblLink: TTyLinkLabel;
    LblShadow: TTyShadowLabel;
    LblGlow: TTyGlowLabel;
    procedure FormCreate(Sender: TObject);
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
  LblShadow.ShadowColor := TyRGBA(0, 0, 0, 150);
  LblGlow.GlowColor := TyRGBA($3B, $82, $F6, 200);
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
