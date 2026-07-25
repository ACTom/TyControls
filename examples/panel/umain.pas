unit umain;

{ TTyPanel demo (TTyForm custom-drawn window frame + title bar):
    - Caption: the panel's title text (note: TTyPanel.Caption is always drawn centered)
    - Alignment: horizontal alignment reference for the child controls (used here as a layout note)
    - As a container: place TTyLabel / TTyEdit / TTyButton inside the panel, and nest a sub-panel
    - Align: alBottom docking demo, width auto-stretch with the form
  The panel's background, border and rounded corners all come from the theme's TyPanel rules;
  no need to hand-code colors here.
  The window, every panel and the live theme switcher are designed in umain.lfm (a TTyForm +
  TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Panel, tyControls.Button, tyControls.TyLabel, tyControls.Edit,
  tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    OuterPanel: TTyPanel;
    NameLabel: TTyLabel;
    NameEdit: TTyEdit;
    GreetBtn: TTyButton;
    InnerPanel: TTyPanel;
    RightPanel: TTyPanel;
    DescLabel: TTyLabel;
    ResultLabel: TTyLabel;
    BottomPanel: TTyPanel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure GreetClicked(Sender: TObject);
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

procedure TMainForm.GreetClicked(Sender: TObject);
var
  UserName: string;
begin
  UserName := NameEdit.Text;
  if UserName = '' then
    ResultLabel.Caption := 'Please enter a name first!'
  else
    ResultLabel.Caption := Format('Hello, %s! Welcome to TyControls.', [UserName]);
end;

end.
