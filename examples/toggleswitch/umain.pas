unit umain;

{ TTyToggleSwitch demo:
  - Checked: two initial states, off/on by default (ON maps through CurrentStates to :active, and the theme renders a highlighted track)
  - Caption: built-in text label to the right of the switch
  - Enabled: a disabled switch cannot be clicked/toggled
  - OnChange: refreshes the status label at the bottom on toggle
  The window, every switch and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ToggleSwitch, tyControls.TyLabel, tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    LblDark: TTyLabel;
    SwitchDark: TTyToggleSwitch;
    LblNotify: TTyLabel;
    SwitchNotify: TTyToggleSwitch;
    SwitchCaption: TTyToggleSwitch;
    SwitchDisabled: TTyToggleSwitch;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure SwitchChange(Sender: TObject);
  private
    procedure UpdateStatus;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function OnOff(B: Boolean): string;
begin
  if B then Result := '开' else Result := '关';
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

  UpdateStatus;                            // initial status label (LblStatus is computed, not a .lfm literal)
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

procedure TMainForm.SwitchChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
begin
  LblStatus.Caption := Format('深色模式：%s   接收通知：%s   自动保存：%s',
    [OnOff(SwitchDark.Checked), OnOff(SwitchNotify.Checked),
     OnOff(SwitchCaption.Checked)]);
end;

end.
