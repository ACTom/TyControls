unit umain;

{ TTySpinEdit demo:
  Showcases the main published properties and events of this integer spin box
  (the implementation is integer-only; decimals are not supported):
    - Value / MinValue / MaxValue / Increment, with OnChange writing live to the status bar
    - Negative range (-50..50, step 5)
    - Alignment: right-justified (Year) and centred (the taCenter box; the caret tracks the centre)
    - MaxLength (limits the number of digits entered)
    - ReadOnly (locked: no editing/stepping/wheel)
    - The Value setter CLAMPS into MinValue..MaxValue and only fires OnChange on a real change:
      the 'Value := 999 in code' button writes 999 and the status line reports 100
  Interaction: up/down arrow buttons, keyboard ↑/↓, mouse wheel, or typing then Enter to commit
  (Esc abandons the typed digits and puts Value back). OnClick fires on the field and on the
  +/- buttons alike, and has its own readout so it never hides the OnChange one.
  The UI (window, every spin box, labels and the live theme switcher) is designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is theme setup + event handlers only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.SpinEdit, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Button;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblQty: TTyLabel;
    SpinQty: TTySpinEdit;      // 0..100 step 1
    LblOfs: TTyLabel;
    SpinOfs: TTySpinEdit;      // -50..50 step 5 (negative range)
    LblYear: TTyLabel;
    SpinYear: TTySpinEdit;     // right-justified + MaxLength
    LblLock: TTyLabel;
    SpinLock: TTySpinEdit;     // ReadOnly locked
    LblStatusCap: TTyLabel;
    LblStatus: TTyLabel;       // OnChange status output
    BtnPoke: TTyButton;        // programmatic out-of-range write (clamp demo)
    LblCentre: TTyLabel;
    SpinCentre: TTySpinEdit;   // Alignment = taCenter
    LblCommit: TTyLabel;
    LblClickCap: TTyLabel;
    LblClick: TTyLabel;        // OnClick output
    procedure FormCreate(Sender: TObject);
    procedure SpinChange(Sender: TObject);
    procedure SpinClick(Sender: TObject);
    procedure PokeClick(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  private
    procedure UpdateStatus(const ATag: string; ASpin: TTySpinEdit);
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

procedure TMainForm.UpdateStatus(const ATag: string; ASpin: TTySpinEdit);
begin
  LblStatus.Caption := Format('%s → %d', [ATag, ASpin.Value]);
end;

procedure TMainForm.SpinChange(Sender: TObject);
begin
  if Sender = SpinQty then
    UpdateStatus('Quantity', SpinQty)
  else if Sender = SpinOfs then
    UpdateStatus('Offset', SpinOfs)
  else if Sender = SpinYear then
    UpdateStatus('Year', SpinYear)
  else if Sender = SpinLock then
    UpdateStatus('Locked', SpinLock)
  else if Sender = SpinCentre then
    UpdateStatus('Centred', SpinCentre);
end;

procedure TMainForm.SpinClick(Sender: TObject);
begin
  // The only published event besides OnChange. It fires on a click anywhere in the
  // control, including the +/- buttons (which step the value first, so the status
  // line above shows the new value and this line shows the click).
  LblClick.Caption := 'Quantity clicked (field or +/- button)';
end;

procedure TMainForm.PokeClick(Sender: TObject);
begin
  // 999 is far outside 0..100: the setter CLAMPS instead of rejecting, so Value
  // lands on 100 and OnChange fires exactly once (and not at all on a second click,
  // because 100 is no longer a change).
  SpinQty.Value := 999;
end;

end.
