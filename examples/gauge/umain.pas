unit umain;

{ TTyGauge 示例:一个小仪表盘。
  - 弧形仪表(gsArc,速度表样式)
  - 环形进度(gsRing)
  - 线性横条(gsLinearH)与竖条(gsLinearV)
  一个 TTimer 周期性改变各仪表的 Value,展示数值缓动动画。
  主窗体为 TTyForm + TTyTitleBar;纯代码创建 UI(无 .lfm),
  主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.Gauge, tyControls.CircularProgress, tyControls.ActivityIndicator,
  tyControls.Meter, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FArc, FRing, FBarH: TTyGauge;
    FCirc: TTyCircularProgress;
    FSpin: TTyActivityIndicator;
    FMeter: TTyMeter;
    FStatus: TTyLabel;
    FTimer: TTimer;
    FTick: Integer;
    procedure Tick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

uses Math;

{ 从 exe 所在目录向上查找仓库的 themes/ 目录 }
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
  LblArc, LblRing, LblBars, LblCirc: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Gauge 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 540, 380);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'Gauge  · TyControls';

  // 弧形仪表(速度表)
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

  // 环形进度
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

  // 环形进度(TTyCircularProgress,复用仪表主题)
  LblCirc := TTyLabel.Create(Self);
  LblCirc.Parent := Self;
  LblCirc.SetBounds(392, 46, 140, 20);
  LblCirc.Caption := '环形进度:';

  FCirc := TTyCircularProgress.Create(Self);
  FCirc.Parent := Self;
  FCirc.SetBounds(400, 72, 110, 110);
  FCirc.Thickness := 12;
  FCirc.Position := 68;

  // 忙碌指示器(不确定态,自转)
  FSpin := TTyActivityIndicator.Create(Self);
  FSpin.Parent := Self;
  FSpin.SetBounds(430, 196, 40, 40);
  FSpin.Thickness := 5;

  // 线性横 / 竖条
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

  // 模拟指针仪表
  FMeter := TTyMeter.Create(Self);
  FMeter.Parent := Self;
  FMeter.SetBounds(348, 232, 180, 140);
  FMeter.Min := 0;
  FMeter.Max := 220;
  FMeter.Ticks := 12;
  FMeter.Value := 88;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 300, 300, 20);
  FStatus.Caption := '每 1.2s 随机改变数值,观察缓动动画。';

  // 定时改值,演示缓动
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
  // 平滑的伪随机值(用三个不同周期的正弦)
  a := 50 + 45 * Sin(FTick * 0.7);
  r := 50 + 45 * Sin(FTick * 0.41 + 1.3);
  b := 50 + 45 * Sin(FTick * 0.9 + 2.1);
  FArc.Value := a;
  FRing.Value := r;
  FBarH.Value := b;
  FMeter.Value := b / 100 * 220;   // map 0..100 -> 0..220
  FCirc.Position := Round(r);
  FStatus.Caption := Format('弧=%.0f%%  环=%.0f  线=%.0f%%', [a, r, b]);
end;

end.
