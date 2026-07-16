unit umain;

{ TTyEdit demo (TTyForm custom-drawn window frame + TTyTitleBar):
    Showcases TTyEdit's core published properties, one mode per input box:
      - TextHint      placeholder hint (shown dimmed when the text is empty)
      - PasswordChar  password mask character
      - CharCase      case forcing (ecUppercase)
      - MaxLength     maximum character-count limit
      - NumbersOnly   digits only
      - ReadOnly      read-only
      - Alignment     text alignment (taRightJustify)
    The first input box hooks OnChange to echo its content live into the
    bottom status-bar TTyLabel.
  The window, every input box and the live theme switcher are designed in
  umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers +
  theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Edit, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblHint: TTyLabel;
    EdHint: TTyEdit;
    LblPassword: TTyLabel;
    EdPassword: TTyEdit;
    LblUpper: TTyLabel;
    EdUpper: TTyEdit;
    LblMaxLen: TTyLabel;
    EdMaxLen: TTyEdit;
    LblNumbers: TTyLabel;
    EdNumbers: TTyEdit;
    LblReadOnly: TTyLabel;
    EdReadOnly: TTyEdit;
    LblRight: TTyLabel;
    EdRight: TTyEdit;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure EditChanged(Sender: TObject);   // OnChange -> status bar
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

procedure TMainForm.EditChanged(Sender: TObject);
begin
  // read TTyEdit.Text live
  LblStatus.Caption := '当前输入：' + (Sender as TTyEdit).Text;
end;

end.
