unit umain;

{ TTyGauge demo: a small instrument panel.
  - arc gauge (gsArc, speedometer style)
  - ring progress (gsRing)
  - horizontal bar (gsLinearH) and vertical bar (gsLinearV)
  A TTimer periodically changes each gauge's Value to show the value-easing animation.
  The window, every instrument and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Gauge, tyControls.CircularProgress, tyControls.ActivityIndicator,
  tyControls.Meter, tyControls.LevelMeter, tyControls.Dial, tyControls.AnalogClock,
  tyControls.Sparkline, tyControls.Rating, tyControls.GearDial,
  tyControls.ActivityBar, tyControls.GearActivityIndicator, tyControls.UpDown,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblArc: TTyLabel;
    Arc: TTyGauge;
    LblRing: TTyLabel;
    Ring: TTyGauge;
    LblCirc: TTyLabel;
    Circ: TTyCircularProgress;
    Spin: TTyActivityIndicator;
    GearSpin: TTyGearActivityIndicator;
    LblBars: TTyLabel;
    BarH: TTyGauge;
    LblBusy: TTyLabel;
    Busy: TTyActivityBar;
    UpDown: TTyUpDown;
    UpDownLbl: TTyLabel;
    Meter: TTyMeter;
    Level: TTyLevelMeter;
    Dial: TTyDial;
    Clock: TTyAnalogClock;
    Spark: TTySparkline;
    Rating: TTyRating;
    Gear: TTyGearDial;
    LblStatus: TTyLabel;
    Timer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure UpDownChange(Sender: TObject);
  private
    FTick: Integer;
  end;

var
  MainForm: TMainForm;

implementation

uses Math;

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

  // Sparkline data can't be a .lfm property (SetValues is a method).
  Spark.SetValues([3, 5, 4, 8, 6, 9, 7, 11, 9, 13, 10, 14]);
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

procedure TMainForm.Tick(Sender: TObject);
var a, r, b: Double;
begin
  Inc(FTick);
  // Smooth pseudo-random values (three sines with different periods)
  a := 50 + 45 * Sin(FTick * 0.7);
  r := 50 + 45 * Sin(FTick * 0.41 + 1.3);
  b := 50 + 45 * Sin(FTick * 0.9 + 2.1);
  Arc.Value := a;
  Ring.Value := r;
  BarH.Value := b;
  Meter.Value := b / 100 * 220;   // map 0..100 -> 0..220
  Level.Value := a;
  Circ.Position := Round(r);
  LblStatus.Caption := Format('弧=%.0f%%  环=%.0f  线=%.0f%%', [a, r, b]);
end;

procedure TMainForm.UpDownChange(Sender: TObject);
begin
  UpDownLbl.Caption := Format('微调(TTyUpDown) = %d', [UpDown.Position]);
end;

end.
