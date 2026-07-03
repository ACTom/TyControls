unit umain;

{ TTyProgressBar 特性示例（纯代码，无 .lfm）：
  - Min / Max / Position：进度区间与当前值
  - AnimationsEnabled：开/关填充缓动动画（复选框切换）
  - StyleClass：为进度条设置样式类（演示 API）
  - 定时器 + 按钮驱动 Position 前进 / 归零
  - OnChange 事件驱动确定性数值读出（TTyLabel）
  主窗体为 TTyForm + TTyTitleBar；主题经全局 TyDefaultController 加载。 }

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

{ 从 exe 所在目录向上查找仓库的 themes/ 目录 }
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

  // 说明标题
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(20, 50, 380, 20);
  Lbl.Caption := '进度条：Min=0  Max=100，按钮 / 定时器驱动 Position';

  // 进度条：设置 Min / Max / Position / StyleClass
  FBar := TTyProgressBar.Create(Self);
  FBar.Parent := Self;
  FBar.SetBounds(20, 78, 380, 22);
  FBar.Min := 0;
  FBar.Max := 100;
  FBar.Position := 0;
  FBar.StyleClass := '';            // 使用基础样式（演示 StyleClass API）
  FBar.AnimationsEnabled := True;   // 默认开启填充缓动
  FBar.OnChange := @BarChange;      // 数值变化 → 更新读出

  // 确定性数值读出（由 OnChange 驱动）
  FReadout := TTyLabel.Create(Self);
  FReadout.Parent := Self;
  FReadout.SetBounds(20, 108, 380, 20);
  FReadout.Caption := '进度：0 / 100  (0%)';

  // 动画开关
  FAnimChk := TTyCheckBox.Create(Self);
  FAnimChk.Parent := Self;
  FAnimChk.SetBounds(20, 140, 260, 22);
  FAnimChk.Caption := '启用填充动画 (AnimationsEnabled)';
  FAnimChk.Checked := True;
  FAnimChk.OnClick := @AnimToggle;

  // 按钮：开始/暂停自动前进
  BtnStart := TTyButton.Create(Self);
  BtnStart.Parent := Self;
  BtnStart.SetBounds(20, 180, 110, 34);
  BtnStart.Caption := '开始 / 暂停';
  BtnStart.OnClick := @StartClick;

  // 按钮：单步 +10
  BtnStep := TTyButton.Create(Self);
  BtnStep.Parent := Self;
  BtnStep.SetBounds(145, 180, 110, 34);
  BtnStep.Caption := '前进 +10';
  BtnStep.OnClick := @StepClick;

  // 按钮：归零
  BtnReset := TTyButton.Create(Self);
  BtnReset.Parent := Self;
  BtnReset.SetBounds(270, 180, 110, 34);
  BtnReset.Caption := '归零';
  BtnReset.OnClick := @ResetClick;

  // 驱动进度前进的定时器（默认不启用）
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
