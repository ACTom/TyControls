unit umain;
{$mode objfpc}{$H+}

{ TTyCheckBox demo: a TTyForm + TTyTitleBar shell showcasing the key checkbox features:
  - Tri-state: AllowGrayed=True, clicking cycles through unchecked/checked/grayed, OnChange echoes State
  - Plain two-state checkbox, OnChange echoes Checked
  - Pre-checked (Checked:=True)
  - Disabled (Enabled:=False)
  The window, every checkbox, the labels and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

interface

uses
  Classes, SysUtils, StdCtrls, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.CheckBox, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblTri: TTyLabel;
    CbTri: TTyCheckBox;
    LblTriStatus: TTyLabel;
    LblPlain: TTyLabel;
    CbPlain: TTyCheckBox;
    LblStatus: TTyLabel;
    CbChecked: TTyCheckBox;
    CbDisabledChecked: TTyCheckBox;
    CbDisabled: TTyCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure TriChange(Sender: TObject);
    procedure PlainChange(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function StateName(AState: TCheckBoxState): string;
begin
  case AState of
    cbChecked: Result := 'Checked (cbChecked)';
    cbGrayed:  Result := 'Grayed (cbGrayed)';
  else
    Result := 'Unchecked (cbUnchecked)';
  end;
end;

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

  // prime the status echoes from the checkboxes' designed initial state
  TriChange(nil);
  PlainChange(nil);
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

procedure TMainForm.TriChange(Sender: TObject);
begin
  LblTriStatus.Caption := 'Tri-state:' + StateName(CbTri.State);
end;

procedure TMainForm.PlainChange(Sender: TObject);
begin
  if CbPlain.Checked then
    LblStatus.Caption := 'Two-state: checked'
  else
    LblStatus.Caption := 'Two-state: unchecked';
end;

end.
