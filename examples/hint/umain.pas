unit umain;

{ Hint demo: TTyHint (themed tooltip, applies app-wide) + TTyBalloonHint (balloon with a pointer).
  The window, the app-wide hint installer, both hinted buttons, the balloon and the live theme
  switcher are all designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event
  handlers + theme setup only.
  Hover a button to see the themed tooltip; click "显示气泡" to see the pointed balloon callout. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Button, tyControls.ComboBox,
  tyControls.Hint, tyControls.BalloonHint;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    AppHint: TTyHint;
    LblIntro: TTyLabel;
    BtnSave: TTyButton;
    BtnDel: TTyButton;
    BtnBalloon: TTyButton;
    Balloon: TTyBalloonHint;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure ShowBalloon(Sender: TObject);
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

procedure TMainForm.ShowBalloon(Sender: TObject);
begin
  Balloon.ShowFor(BtnBalloon);
end;

end.
