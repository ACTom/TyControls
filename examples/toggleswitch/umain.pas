unit umain;

{ TTyToggleSwitch demo:
  - Checked: two initial states, off/on by default (ON maps through CurrentStates to :active, and the theme renders a highlighted track)
  - Caption: built-in text label to the right of the switch
  - Enabled: a disabled switch cannot be clicked/toggled
  - OnChange: refreshes the status label at the bottom on toggle
  - OnChange vs OnClick: OnChange fires for EVERY state change (a click, the keyboard,
    or a Checked/Toggle assignment from code); OnClick only for a real mouse click. The
    "Toggle from code" button proves it — it flips three switches and only OnChange runs.
  - Toggle: the public one-liner that flips Checked from code.
  - AnimationsEnabled: PUBLIC, not published, so it is the one setting that cannot live in
    umain.lfm — SwitchNoAnim gets it in FormCreate, and its ~120 ms eased knob slide is off.
  - Keyboard: TabStop is on by default, and Space / Enter toggle the focused switch.
  The window, every switch and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ToggleSwitch, tyControls.TyLabel, tyControls.ComboBox,
  tyControls.Button;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblDark: TTyLabel;
    SwitchDark: TTyToggleSwitch;
    LblNotify: TTyLabel;
    SwitchNotify: TTyToggleSwitch;
    SwitchCaption: TTyToggleSwitch;
    SwitchDisabled: TTyToggleSwitch;
    LblSecEvents: TTyLabel;
    SwitchEvents: TTyToggleSwitch;
    BtnToggleAll: TTyButton;
    LblEvents: TTyLabel;
    LblSecAnim: TTyLabel;
    SwitchNoAnim: TTyToggleSwitch;
    LblHint: TTyLabel;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure SwitchChange(Sender: TObject);
    procedure SwitchEventsChange(Sender: TObject);
    procedure SwitchEventsClick(Sender: TObject);
    procedure BtnToggleAllClick(Sender: TObject);
  private
    FEventTrace: string;   // which of OnChange / OnClick the last gesture fired
    procedure UpdateStatus;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { Composed at run time, so they live here rather than in the .lfm. }
  rsGesture     = 'Last gesture: %s';
  rsEvtChange   = 'OnChange';
  rsEvtAndClick = ' + OnClick';

function OnOff(B: Boolean): string;
begin
  if B then Result := 'On' else Result := 'Off';
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

  // AnimationsEnabled is PUBLIC, not published, so the IDE cannot stream it and this is the
  // only setting in this example that is not in umain.lfm. With it off the knob jumps to the
  // far end instead of easing across in ~120 ms -- compare it with any other switch here.
  SwitchNoAnim.AnimationsEnabled := False;

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

{ OnChange runs for EVERY state change, whatever caused it: a mouse click, Space/Enter on the
  focused switch, or a Checked/Toggle assignment from code. It is the first of the pair. }
procedure TMainForm.SwitchEventsChange(Sender: TObject);
begin
  FEventTrace := rsEvtChange;
  LblEvents.Caption := Format(rsGesture, [FEventTrace]);
end;

{ OnClick runs only for a real mouse click, and always AFTER OnChange (the control's Click
  toggles first, then dispatches OnClick). Toggle from code -- or the keyboard -- never gets
  here, which is exactly what the "Toggle from code" button demonstrates. }
procedure TMainForm.SwitchEventsClick(Sender: TObject);
begin
  FEventTrace := FEventTrace + rsEvtAndClick;
  LblEvents.Caption := Format(rsGesture, [FEventTrace]);
end;

{ Toggle is the public one-liner for flipping a switch from code. All three switches change
  state and fire OnChange; none of them fires OnClick. }
procedure TMainForm.BtnToggleAllClick(Sender: TObject);
begin
  SwitchEvents.Toggle;
  SwitchCaption.Toggle;
  SwitchNotify.Toggle;
end;

procedure TMainForm.UpdateStatus;
begin
  LblStatus.Caption := Format('Dark mode: %s   Receive notifications: %s   Auto-save: %s',
    [OnOff(SwitchDark.Checked), OnOff(SwitchNotify.Checked),
     OnOff(SwitchCaption.Checked)]);
end;

end.
