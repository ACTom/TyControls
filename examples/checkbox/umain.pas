unit umain;
{$mode objfpc}{$H+}

{ TTyCheckBox demo: a TTyForm + TTyTitleBar shell showcasing the key checkbox features:
  - Tri-state: AllowGrayed=True, clicking cycles through unchecked/checked/grayed, OnChange echoes State
  - Plain two-state checkbox, OnChange echoes Checked
  - Pre-checked (Checked:=True)
  - Disabled (Enabled:=False)
  - OnClick vs OnChange: OnChange also fires when code writes Checked/State, OnClick only on a
    real activation (mouse, Space, Alt+mnemonic) -- the two counters make the difference visible
  The window, every checkbox, the labels and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

interface

uses
  Classes, SysUtils, StdCtrls, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.CheckBox, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Button;

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
    LblEventsHdr: TTyLabel;
    CbEvents: TTyCheckBox;
    BtnToggle: TTyButton;
    LblEvents: TTyLabel;
    LblKeys: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure TriChange(Sender: TObject);
    procedure PlainChange(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure EventsChange(Sender: TObject);
    procedure EventsClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
  private
    { How often each of the two events has fired so far. Counting (rather than showing
      the last one) is what makes the difference readable: a code-driven write bumps
      OnChange only, a real click bumps both. }
    FChangeCount: Integer;
    FClickCount: Integer;
    procedure ShowEventCounts;
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

procedure TMainForm.ShowEventCounts;
begin
  LblEvents.Caption := Format('OnChange fired %d time(s), OnClick %d time(s)',
    [FChangeCount, FClickCount]);
end;

procedure TMainForm.EventsChange(Sender: TObject);
begin
  // Fires on EVERY state change, including the button's programmatic write below.
  Inc(FChangeCount);
  ShowEventCounts;
end;

procedure TMainForm.EventsClick(Sender: TObject);
begin
  // Fires only when the box is really activated: mouse, Space, or Alt+mnemonic.
  Inc(FClickCount);
  ShowEventCounts;
end;

procedure TMainForm.ToggleClick(Sender: TObject);
begin
  // A code-driven write: watch only the OnChange counter move.
  CbEvents.Checked := not CbEvents.Checked;
end;

end.
