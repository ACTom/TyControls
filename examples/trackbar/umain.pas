unit umain;

{ TTyTrackBar demo:
  - Horizontal track bar (0..100), OnChange updates the status label live
  - Custom-range track bar (-50..50, shows a negative range)
  - Vertical track bar (Orientation = toVertical) with ticks and its own readout
  - Fine-stepping track bar (PageSize / Frequency demo, its own range and readout)
  - ShowValue: the bar paints its own number (right end horizontal, under the track vertical)
  - LineSize: a bar whose arrow-key / wheel step is 5 instead of 1
  - AnimationsEnabled toggled from code (it is public, not published, so no .lfm can set it)
  The main form (a TTyForm + TTyTitleBar), every track bar and the live theme switcher are
  designed in umain.lfm; the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TrackBar, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblVolume: TTyLabel;
    Track1: TTyTrackBar;
    LblBalance: TTyLabel;
    Track2: TTyTrackBar;
    LblBrightness: TTyLabel;
    Track4: TTyTrackBar;
    LblVertical: TTyLabel;
    Track3: TTyTrackBar;
    LblStatus: TTyLabel;
    LblShowValueHint: TTyLabel;
    LblVerticalHint: TTyLabel;
    LblLineSize: TTyLabel;
    Track5: TTyTrackBar;
    AnimSwitch: TTyToggleSwitch;
    LblAnimHint: TTyLabel;
    LblKeysTitle: TTyLabel;
    LblKeys1: TTyLabel;
    LblKeys2: TTyLabel;
    LblKeys3: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure Track1Change(Sender: TObject);
    procedure Track2Change(Sender: TObject);
    procedure Track3Change(Sender: TObject);
    procedure Track4Change(Sender: TObject);
    procedure Track5Change(Sender: TObject);
    procedure AnimSwitchChange(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { Status texts composed at run time, so they live here rather than in the .lfm. }
  rsVolumeFmt     = 'Volume: %d';
  rsBalanceFmt    = 'Balance: %d';
  rsVerticalFmt   = 'Vertical: %d';
  rsBrightnessFmt = 'Brightness: %d';
  rsFineFmt       = 'Fine: %d';
  rsAnimOn  = 'AnimationsEnabled = True (thumb eases)';
  rsAnimOff = 'AnimationsEnabled = False (thumb jumps)';

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

procedure TMainForm.Track1Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsVolumeFmt, [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track2Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsBalanceFmt, [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track3Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsVerticalFmt, [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track4Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsBrightnessFmt, [(Sender as TTyTrackBar).Position]);
end;

{ LineSize = 5: every arrow key and every wheel notch moves this bar by 5, while
  PageUp/PageDown still move by PageSize (25). }
procedure TMainForm.Track5Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsFineFmt, [(Sender as TTyTrackBar).Position]);
end;

{ AnimationsEnabled is PUBLIC, not published, so no .lfm can reach it -- only code.
  On (the default) the thumb eases ~120 ms to a keyboard/wheel change; off it jumps.
  A live drag always tracks the mouse exactly, either way. }
procedure TMainForm.AnimSwitchChange(Sender: TObject);
begin
  Track1.AnimationsEnabled := AnimSwitch.Checked;
  Track2.AnimationsEnabled := AnimSwitch.Checked;
  Track3.AnimationsEnabled := AnimSwitch.Checked;
  Track4.AnimationsEnabled := AnimSwitch.Checked;
  Track5.AnimationsEnabled := AnimSwitch.Checked;
  if AnimSwitch.Checked then
    LblStatus.Caption := rsAnimOn
  else
    LblStatus.Caption := rsAnimOff;
end;

end.
