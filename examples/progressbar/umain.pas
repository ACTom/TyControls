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
  tyControls.TyLabel, tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    LblDesc: TTyLabel;
    ProgBar: TTyProgressBar;
    LblReadout: TTyLabel;
    AnimChk: TTyCheckBox;
    BtnStart: TTyButton;
    BtnStep: TTyButton;
    BtnReset: TTyButton;
    Timer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure BarChange(Sender: TObject);
    procedure StartClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure StepClick(Sender: TObject);
    procedure AnimToggle(Sender: TObject);
    procedure TimerTick(Sender: TObject);
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

  ProgBar.StyleClass := '';   // use the base style (demonstrates the StyleClass API)
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
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
  LblReadout.Caption := Format('进度：%d / %d  (%d%%)',
    [ProgBar.Position, ProgBar.Max, Pct]);
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
end;

procedure TMainForm.TimerTick(Sender: TObject);
begin
  if ProgBar.Position >= ProgBar.Max then
    ProgBar.Position := 0
  else
    ProgBar.Position := ProgBar.Position + 5;
end;

end.
