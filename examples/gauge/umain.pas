unit umain;

{ TTyGauge demo: a small instrument panel.
  - arc gauge (gsArc, speedometer style)
  - ring progress (gsRing)
  - horizontal bar (gsLinearH) and vertical bar (gsLinearV)
  A TTimer periodically changes each gauge's Value to show the value-easing animation.
  The main form is a TTyForm + TTyTitleBar; the UI is built purely in code (no .lfm),
  and the theme is loaded via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.Gauge, tyControls.CircularProgress, tyControls.ActivityIndicator,
  tyControls.Meter, tyControls.LevelMeter, tyControls.Dial, tyControls.AnalogClock,
  tyControls.Sparkline, tyControls.Rating, tyControls.GearDial,
  tyControls.ActivityBar, tyControls.GearActivityIndicator, tyControls.UpDown,
  tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FArc, FRing, FBarH: TTyGauge;
    FBusy: TTyActivityBar;
    FCirc: TTyCircularProgress;
    FSpin: TTyActivityIndicator;
    FGearSpin: TTyGearActivityIndicator;
    FUpDown: TTyUpDown;
    FUpDownLbl: TTyLabel;
    FMeter: TTyMeter;
    FLevel: TTyLevelMeter;
    FDial: TTyDial;
    FClock: TTyAnalogClock;
    FSpark: TTySparkline;
    FRating: TTyRating;
    FGear: TTyGearDial;
    FStatus: TTyLabel;
    FTimer: TTimer;
    FTick: Integer;
    procedure Tick(Sender: TObject);
    procedure UpDownChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

uses Math;

{ Search upward from the exe's directory for the repo's themes/ folder }
function ThemesDir: string;
var Dir: string; i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  LblArc, LblRing, LblBars, LblCirc, LblBusy: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Gauge 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 540, 660);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'Gauge  · TyControls';

  // Arc gauge (speedometer)
  LblArc := TTyLabel.Create(Self);
  LblArc.Parent := Self;
  LblArc.SetBounds(24, 46, 160, 20);
  LblArc.Caption := '弧形(gsArc):';

  FArc := TTyGauge.Create(Self);
  FArc.Parent := Self;
  FArc.SetBounds(24, 68, 160, 160);
  FArc.Style := gsArc;
  FArc.ValueFormat := '%.0f%%';
  FArc.Value := 62;

  // Ring progress
  LblRing := TTyLabel.Create(Self);
  LblRing.Parent := Self;
  LblRing.SetBounds(210, 46, 160, 20);
  LblRing.Caption := '环形(gsRing):';

  FRing := TTyGauge.Create(Self);
  FRing.Parent := Self;
  FRing.SetBounds(230, 68, 140, 140);
  FRing.Style := gsRing;
  FRing.Thickness := 14;
  FRing.ValueFormat := '%.0f';
  FRing.Value := 35;

  // Ring progress (TTyCircularProgress, reuses the gauge theme)
  LblCirc := TTyLabel.Create(Self);
  LblCirc.Parent := Self;
  LblCirc.SetBounds(392, 46, 140, 20);
  LblCirc.Caption := '环形进度:';

  FCirc := TTyCircularProgress.Create(Self);
  FCirc.Parent := Self;
  FCirc.SetBounds(400, 72, 110, 110);
  FCirc.Thickness := 12;
  FCirc.Position := 68;

  // Busy indicator (indeterminate, self-spinning)
  FSpin := TTyActivityIndicator.Create(Self);
  FSpin.Parent := Self;
  FSpin.SetBounds(430, 196, 40, 40);
  FSpin.Thickness := 5;

  // Gear busy indicator (mechanical variant of ActivityIndicator), next to the spinning arc
  FGearSpin := TTyGearActivityIndicator.Create(Self);
  FGearSpin.Parent := Self;
  FGearSpin.SetBounds(480, 196, 40, 40);

  // Linear horizontal / vertical bars
  LblBars := TTyLabel.Create(Self);
  LblBars.Parent := Self;
  LblBars.SetBounds(24, 244, 200, 20);
  LblBars.Caption := '线性(gsLinearH / gsLinearV):';

  FBarH := TTyGauge.Create(Self);
  FBarH.Parent := Self;
  FBarH.SetBounds(24, 268, 300, 24);
  FBarH.Style := gsLinearH;
  FBarH.Thickness := 1;
  FBarH.ShowValue := False;
  FBarH.Value := 62;

  // Indeterminate linear progress (marching band, animates continuously on its own, no timed value changes needed)
  LblBusy := TTyLabel.Create(Self);
  LblBusy.Parent := Self;
  LblBusy.SetBounds(24, 306, 320, 20);
  LblBusy.Caption := '不确定态(TTyActivityBar):';

  FBusy := TTyActivityBar.Create(Self);
  FBusy.Parent := Self;
  FBusy.SetBounds(24, 330, 300, 8);

  // Standalone up/down spin button pair (auto-repeat on hold), bound to the label on the right to show the current value
  FUpDown := TTyUpDown.Create(Self);
  FUpDown.Parent := Self;
  FUpDown.SetBounds(24, 348, 22, 34);
  FUpDown.Min := 0;
  FUpDown.Max := 20;
  FUpDown.Position := 5;
  FUpDown.OnChange := @UpDownChange;

  FUpDownLbl := TTyLabel.Create(Self);
  FUpDownLbl.Parent := Self;
  FUpDownLbl.SetBounds(54, 356, 260, 20);
  FUpDownLbl.Caption := '微调(TTyUpDown) = 5';

  // Analog needle meter
  FMeter := TTyMeter.Create(Self);
  FMeter.Parent := Self;
  FMeter.SetBounds(348, 232, 180, 140);
  FMeter.Min := 0;
  FMeter.Max := 220;
  FMeter.Ticks := 12;
  FMeter.Value := 88;

  // Bottom row: level meter / dial / clock
  FLevel := TTyLevelMeter.Create(Self);
  FLevel.Parent := Self;
  FLevel.SetBounds(24, 396, 300, 26);
  FLevel.Min := 0;
  FLevel.Max := 100;
  FLevel.Segments := 20;
  FLevel.PeakHold := True;
  FLevel.Value := 62;

  FDial := TTyDial.Create(Self);
  FDial.Parent := Self;
  FDial.SetBounds(348, 388, 76, 76);
  FDial.Min := 0;
  FDial.Max := 100;
  FDial.Value := 40;

  FClock := TTyAnalogClock.Create(Self);
  FClock.Parent := Self;
  FClock.SetBounds(436, 388, 90, 90);
  FClock.Running := True;

  // Another row: sparkline / rating / gear dial
  FSpark := TTySparkline.Create(Self);
  FSpark.Parent := Self;
  FSpark.SetBounds(24, 500, 220, 40);
  FSpark.SetValues([3, 5, 4, 8, 6, 9, 7, 11, 9, 13, 10, 14]);

  FRating := TTyRating.Create(Self);
  FRating.Parent := Self;
  FRating.SetBounds(24, 552, 160, 28);
  FRating.AllowHalf := True;
  FRating.Value := 3.5;

  FGear := TTyGearDial.Create(Self);
  FGear.Parent := Self;
  FGear.SetBounds(260, 500, 84, 84);
  FGear.Min := 0;
  FGear.Max := 100;
  FGear.Value := 55;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 596, 460, 20);
  FStatus.Caption := '每 1.2s 随机改变数值(旋钮 / 齿轮可拖动 / 滚轮,星星可点),观察缓动动画。';

  // Change values on a timer to demonstrate easing
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1200;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := True;

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.Tick(Sender: TObject);
var a, r, b: Double;
begin
  Inc(FTick);
  // Smooth pseudo-random values (three sines with different periods)
  a := 50 + 45 * Sin(FTick * 0.7);
  r := 50 + 45 * Sin(FTick * 0.41 + 1.3);
  b := 50 + 45 * Sin(FTick * 0.9 + 2.1);
  FArc.Value := a;
  FRing.Value := r;
  FBarH.Value := b;
  FMeter.Value := b / 100 * 220;   // map 0..100 -> 0..220
  FLevel.Value := a;
  FCirc.Position := Round(r);
  FStatus.Caption := Format('弧=%.0f%%  环=%.0f  线=%.0f%%', [a, r, b]);
end;

procedure TMainForm.UpDownChange(Sender: TObject);
begin
  FUpDownLbl.Caption := Format('微调(TTyUpDown) = %d', [FUpDown.Position]);
end;

end.
