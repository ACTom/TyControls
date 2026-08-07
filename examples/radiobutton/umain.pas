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
    LblGroupIdxHead: TTyLabel;
    GroupC: TTyGroupBox;
    SizeSmall: TTyRadioButton;
    SizeMedium: TTyRadioButton;
    SizeLarge: TTyRadioButton;
    ShipStandard: TTyRadioButton;
    ShipExpress: TTyRadioButton;
    LblGroupIdxStatus: TTyLabel;
    LblMnemonic: TTyLabel;
    LblStyle: TTyLabel;
    StyleRadioA: TTyRadioButton;
    StyleRadioB: TTyRadioButton;
    LblEvents: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure RadioChanged(Sender: TObject);
    procedure StyleRadioChanged(Sender: TObject);
    procedure StyleRadioClick(Sender: TObject);
  private
    FChangeCount: Integer;
    FClickCount: Integer;
    procedure UpdateStatus;
    procedure UpdateEventCounts;
    function PlainCaption(const AText: string): string;
    function SelectedIn(A, B, C: TTyRadioButton): string;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { Status texts composed at run time, so they live here rather than in the .lfm. }
  rsNone         = '(none)';
  rsSelectedFmt  = 'Currently selected  →  Fruit: %s     Colour: %s';
  rsGroupIdxFmt  = 'GroupIndex 0: %s     GroupIndex 1: %s';
  rsEventCountFmt = 'OnChange x%d, OnClick x%d - one pick fires OnChange twice';

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
  SizeMedium.Checked := True;               // GroupIndex 0 inside the shared box
  ShipStandard.Checked := True;             // GroupIndex 1 inside the SAME box
  StyleRadioA.Checked := True;              // grouped by Parent (both sit on Surface)
  { Those defaults each fired OnChange; zero the tallies so the on-screen counters
    only count what the USER does. }
  FChangeCount := 0;
  FClickCount := 0;
  UpdateStatus;                             // all radios built, refresh the final readout once
  UpdateEventCounts;
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

{ Drop the '&' mnemonic markers so a caption reads naturally in the status line }
function TMainForm.PlainCaption(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '', [rfReplaceAll]);
end;

{ Return the Caption of the currently selected item in a group }
function TMainForm.SelectedIn(A, B, C: TTyRadioButton): string;
begin
  if A.Checked then Result := A.Caption
  else if B.Checked then Result := B.Caption
  else if C.Checked then Result := C.Caption
  else Result := rsNone;
end;

procedure TMainForm.UpdateStatus;
var
  Delivery: string;
begin
  LblStatus.Caption := Format(rsSelectedFmt,
    [SelectedIn(FFruitApple, FFruitBanana, FFruitMango),
     SelectedIn(FColorRed, FColorGreen, FColorBlue)]);
  { GroupC holds all five of these, so the ONLY thing keeping the two columns apart
    is GroupIndex -- UncheckSiblings ignores a sibling with a different index. }
  if ShipStandard.Checked then Delivery := ShipStandard.Caption
  else if ShipExpress.Checked then Delivery := ShipExpress.Caption
  else Delivery := rsNone;
  LblGroupIdxStatus.Caption := Format(rsGroupIdxFmt,
    [PlainCaption(SelectedIn(SizeSmall, SizeMedium, SizeLarge)),
     PlainCaption(Delivery)]);
end;

procedure TMainForm.UpdateEventCounts;
begin
  LblEvents.Caption := Format(rsEventCountFmt, [FChangeCount, FClickCount]);
end;

procedure TMainForm.RadioChanged(Sender: TObject);
begin
  { Any button's Checked change (including one cleared by UncheckSiblings) lands here }
  UpdateStatus;
end;

procedure TMainForm.StyleRadioChanged(Sender: TObject);
begin
  { Fires for the button that got checked AND for the sibling UncheckSiblings cleared,
    which is why this counter climbs by two per pick. }
  Inc(FChangeCount);
  UpdateEventCounts;
end;

procedure TMainForm.StyleRadioClick(Sender: TObject);
begin
  { OnClick only reaches the button the user actually pressed. }
  Inc(FClickCount);
  UpdateEventCounts;
end;

end.
