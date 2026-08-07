unit umain;

{ TTyProgressBar feature demo:
  - Min / Max / Position: value range and current value
  - AnimationsEnabled: turn the fill easing animation on/off (toggled by a checkbox)
  - StyleClass: assign a style class to the bar (demonstrates the API)
  - Timer + buttons drive Position forward / back to zero
  - OnChange event drives a deterministic numeric readout (TTyLabel)
  The window, the progress bar, every control and the live theme switcher are designed
  in umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ProgressBar, tyControls.Button, tyControls.CheckBox,
  tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblDesc: TTyLabel;
    ProgBar: TTyProgressBar;
    LblReadout: TTyLabel;
    AnimChk: TTyCheckBox;
    BtnStart: TTyButton;
    BtnStep: TTyButton;
    BtnReset: TTyButton;
    LblOrient: TTyLabel;
    VertBar: TTyProgressBar;
    LblRange: TTyLabel;
    RangeBar: TTyProgressBar;
    LblRangeReadout: TTyLabel;
    LblOverride: TTyLabel;
    OverrideBar: TTyProgressBar;
    LblDisabled: TTyLabel;
    DisabledBar: TTyProgressBar;
    LblDock: TTyLabel;
    DockBar: TTyProgressBar;
    Timer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure BarChange(Sender: TObject);
    procedure StartClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure StepClick(Sender: TObject);
    procedure AnimToggle(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure OverrideBarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsProgressFmt = 'Progress: %d / %d  (%d%%)';
  rsRangeFmt    = 'Position %d in %d..%d  (%d%%)';

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

  ProgBar.StyleClass := '';   // use the base style (demonstrates the StyleClass API)
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

procedure TMainForm.BarChange(Sender: TObject);
var
  Span, Pct: Integer;
begin
  Span := ProgBar.Max - ProgBar.Min;
  if Span > 0 then
    Pct := Round((ProgBar.Position - ProgBar.Min) * 100 / Span)
  else
    Pct := 0;
  LblReadout.Caption := Format(rsProgressFmt, [ProgBar.Position, ProgBar.Max, Pct]);
  // The vertical bar and the docked strip share this bar's Position outright, so the
  // only difference on screen is Orientation / Align. RangeBar re-maps the same PERCENT
  // onto its own 20..60 range, which is what Min/Max actually do.
  VertBar.Position := ProgBar.Position;
  DockBar.Position := ProgBar.Position;
  RangeBar.Position := RangeBar.Min +
    Round((RangeBar.Max - RangeBar.Min) * Pct / 100);
  LblRangeReadout.Caption := Format(rsRangeFmt,
    [RangeBar.Position, RangeBar.Min, RangeBar.Max, Pct]);
end;

procedure TMainForm.StartClick(Sender: TObject);
begin
  Timer.Enabled := not Timer.Enabled;
end;

procedure TMainForm.StepClick(Sender: TObject);
begin
  ProgBar.Position := ProgBar.Position + 10;
end;

procedure TMainForm.ResetClick(Sender: TObject);
begin
  Timer.Enabled := False;
  ProgBar.Position := 0;
end;

procedure TMainForm.AnimToggle(Sender: TObject);
begin
  ProgBar.AnimationsEnabled := AnimChk.Checked;
  // Every bar rides the same switch, so the whole set snaps or eases together.
  VertBar.AnimationsEnabled := AnimChk.Checked;
  RangeBar.AnimationsEnabled := AnimChk.Checked;
  OverrideBar.AnimationsEnabled := AnimChk.Checked;
  DockBar.AnimationsEnabled := AnimChk.Checked;
end;

procedure TMainForm.TimerTick(Sender: TObject);
begin
  if ProgBar.Position >= ProgBar.Max then
    ProgBar.Position := 0
  else
    ProgBar.Position := ProgBar.Position + 5;
end;

procedure TMainForm.OverrideBarMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Span: Integer;
begin
  // A progress bar is a graphic control, so it still gets the full mouse event set:
  // seek by clicking, and watch AnimationsEnabled ease the fill to the new spot.
  Span := OverrideBar.Width;
  if Span <= 0 then Exit;
  OverrideBar.Position := OverrideBar.Min +
    Round((OverrideBar.Max - OverrideBar.Min) * X / Span);
end;

end.
