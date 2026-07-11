unit umain;

{ TTyProgressBar feature demo (pure code, no .lfm):
  - Min / Max / Position: value range and current value
  - AnimationsEnabled: turn the fill easing animation on/off (toggled by a checkbox)
  - StyleClass: assign a style class to the bar (demonstrates the API)
  - Timer + buttons drive Position forward / back to zero
  - OnChange event drives a deterministic numeric readout (TTyLabel)
  The main form is a TTyForm + TTyTitleBar; the theme is loaded via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.ProgressBar, tyControls.Button, tyControls.CheckBox,
  tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FBar: TTyProgressBar;
    FReadout: TTyLabel;
    FAnimChk: TTyCheckBox;
    FTimer: TTimer;
    procedure BarChange(Sender: TObject);
    procedure StartClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure StepClick(Sender: TObject);
    procedure AnimToggle(Sender: TObject);
    procedure TimerTick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ directory }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  Lbl: TTyLabel;
  BtnStart, BtnStep, BtnReset: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyProgressBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 300);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'ProgressBar  · TyControls';

  // Caption / description
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(20, 50, 380, 20);
  Lbl.Caption := '进度条：Min=0  Max=100，按钮 / 定时器驱动 Position';

  // Progress bar: set Min / Max / Position / StyleClass
  FBar := TTyProgressBar.Create(Self);
  FBar.Parent := Self;
  FBar.SetBounds(20, 78, 380, 22);
  FBar.Min := 0;
  FBar.Max := 100;
  FBar.Position := 0;
  FBar.StyleClass := '';            // use the base style (demonstrates the StyleClass API)
  FBar.AnimationsEnabled := True;   // fill easing on by default
  FBar.OnChange := @BarChange;      // value change -> update the readout

  // Deterministic numeric readout (driven by OnChange)
  FReadout := TTyLabel.Create(Self);
  FReadout.Parent := Self;
  FReadout.SetBounds(20, 108, 380, 20);
  FReadout.Caption := '进度：0 / 100  (0%)';

  // Animation toggle
  FAnimChk := TTyCheckBox.Create(Self);
  FAnimChk.Parent := Self;
  FAnimChk.SetBounds(20, 140, 260, 22);
  FAnimChk.Caption := '启用填充动画 (AnimationsEnabled)';
  FAnimChk.Checked := True;
  FAnimChk.OnClick := @AnimToggle;

  // Button: start/pause automatic advance
  BtnStart := TTyButton.Create(Self);
  BtnStart.Parent := Self;
  BtnStart.SetBounds(20, 180, 110, 34);
  BtnStart.Caption := '开始 / 暂停';
  BtnStart.OnClick := @StartClick;

  // Button: step +10
  BtnStep := TTyButton.Create(Self);
  BtnStep.Parent := Self;
  BtnStep.SetBounds(145, 180, 110, 34);
  BtnStep.Caption := '前进 +10';
  BtnStep.OnClick := @StepClick;

  // Button: reset to zero
  BtnReset := TTyButton.Create(Self);
  BtnReset.Parent := Self;
  BtnReset.SetBounds(270, 180, 110, 34);
  BtnReset.Caption := '归零';
  BtnReset.OnClick := @ResetClick;

  // Timer that drives the progress forward (disabled by default)
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.BarChange(Sender: TObject);
var
  Span, Pct: Integer;
begin
  Span := FBar.Max - FBar.Min;
  if Span > 0 then
    Pct := Round((FBar.Position - FBar.Min) * 100 / Span)
  else
    Pct := 0;
  FReadout.Caption := Format('进度：%d / %d  (%d%%)',
    [FBar.Position, FBar.Max, Pct]);
end;

procedure TMainForm.StartClick(Sender: TObject);
begin
  FTimer.Enabled := not FTimer.Enabled;
end;

procedure TMainForm.StepClick(Sender: TObject);
begin
  FBar.Position := FBar.Position + 10;
end;

procedure TMainForm.ResetClick(Sender: TObject);
begin
  FTimer.Enabled := False;
  FBar.Position := 0;
end;

procedure TMainForm.AnimToggle(Sender: TObject);
begin
  FBar.AnimationsEnabled := FAnimChk.Checked;
end;

procedure TMainForm.TimerTick(Sender: TObject);
begin
  if FBar.Position >= FBar.Max then
    FBar.Position := 0
  else
    FBar.Position := FBar.Position + 5;
end;

end.
