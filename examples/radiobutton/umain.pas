unit umain;

{ TTyRadioButton demo (TTyForm + TitleBar + live theme switcher):
  - Two TTyGroupBox containers (title band reserved at the top of each GroupBox), each holding 3 TTyRadioButtons
  - Mutual exclusion (UncheckSiblings) is grouped by Parent: exclusive within a GroupBox, independent across groups
  - Checked: each group has one item selected by default
  - OnChange: any button state change refreshes the status readout in the bottom TTyLabel
  - Demonstrates one disabled item (Enabled=False)
  The window, both groups, every radio button and the theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.GroupBox, tyControls.CheckBox, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    GroupA: TTyGroupBox;
    GroupB: TTyGroupBox;
    FFruitApple: TTyRadioButton;
    FFruitBanana: TTyRadioButton;
    FFruitMango: TTyRadioButton;
    FColorRed: TTyRadioButton;
    FColorGreen: TTyRadioButton;
    FColorBlue: TTyRadioButton;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure RadioChanged(Sender: TObject);
  private
    procedure UpdateStatus;
    function SelectedIn(A, B, C: TTyRadioButton): string;
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

  { Default selection is applied here (not in the .lfm): setting Checked fires OnChange
    immediately -> RadioChanged -> UpdateStatus, which reads all 6 radios + LblStatus.
    During .lfm streaming those siblings don't all exist yet (the color group and the
    status label stream after the fruit group), so doing it here -- after the whole form
    is streamed -- is the only safe point. }
  FFruitApple.Checked := True;              // fruit: first item by default
  FColorGreen.Checked := True;              // color: second item by default
  UpdateStatus;                             // all radios built, refresh the final readout once
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

{ Return the Caption of the currently selected item in a group }
function TMainForm.SelectedIn(A, B, C: TTyRadioButton): string;
begin
  if A.Checked then Result := A.Caption
  else if B.Checked then Result := B.Caption
  else if C.Checked then Result := C.Caption
  else Result := '(none)';
end;

procedure TMainForm.UpdateStatus;
begin
  LblStatus.Caption := Format('Currently selected  →  Fruit: %s     Colour: %s',
    [SelectedIn(FFruitApple, FFruitBanana, FFruitMango),
     SelectedIn(FColorRed, FColorGreen, FColorBlue)]);
end;

procedure TMainForm.RadioChanged(Sender: TObject);
begin
  { Any button's Checked change (including one cleared by UncheckSiblings) lands here }
  UpdateStatus;
end;

end.
