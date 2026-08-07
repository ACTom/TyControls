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
    LblKnobs: TTyLabel;
    LblRowA: TTyLabel;
    BarV: TTyGauge;
    LevelV: TTyLevelMeter;
    HalfArc: TTyGauge;
    ClockStatic: TTyAnalogClock;
    LblBusySw: TTyLabel;
    BusySwitch: TTyToggleSwitch;
    LblRowB: TTyLabel;
    SparkBar: TTySparkline;
    RatingRO: TTyRating;
    UpDownH: TTyUpDown;
    LblUpDownH: TTyLabel;
    Timer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure UpDownChange(Sender: TObject);
    procedure UpDownHChange(Sender: TObject);
    procedure KnobChange(Sender: TObject);
    procedure BusyChange(Sender: TObject);
  private
    FTick: Integer;
  end;

var
  MainForm: TMainForm;

implementation

uses Math;

{$R *.lfm}

resourcestring
  rsGaugesFmt   = 'Arc=%.0f%%  Ring=%.0f  Linear=%.0f%%';
  rsSpinnerFmt  = 'Spinner (TTyUpDown) = %d';
  rsSpinnerHFmt = 'Horizontal spinner: Increment 5, Wrap 20 -> 0 (Position = %d)';
  rsKnobsFmt    = 'Dial = %.0f   Gear = %.0f   Rating = %.1f';

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
  // Same samples, ssBar style on a FIXED 0..20 range: the bars sit low and flat where
  // the auto-ranged line above fills the whole box — that is what AutoRange buys you.
  SparkBar.SetValues([3, 5, 4, 8, 6, 9, 7, 11, 9, 13, 10, 14]);
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
  HalfArc.Value := a;             // same value, StartAngle/SweepAngle 180 instead of 135/270
  Ring.Value := r;
  BarH.Value := b;
  BarV.Value := b;                // same value, gsLinearV instead of gsLinearH
  Meter.Value := b / 100 * 220;   // map 0..100 -> 0..220
  Level.Value := a;
  LevelV.Value := a;              // same value, loVertical instead of loHorizontal
  Circ.Position := Round(r / 100 * 250);   // map 0..100 -> the ring's 0..250 scale
  LblStatus.Caption := Format(rsGaugesFmt, [a, r, b]);
end;

procedure TMainForm.UpDownChange(Sender: TObject);
begin
  UpDownLbl.Caption := Format(rsSpinnerFmt, [UpDown.Position]);
end;

procedure TMainForm.UpDownHChange(Sender: TObject);
begin
  // Increment = 5 with Wrap = True: 5, 10, 15, 20, then straight back to 0.
  LblUpDownH.Caption := Format(rsSpinnerHFmt, [UpDownH.Position]);
end;

procedure TMainForm.KnobChange(Sender: TObject);
begin
  // One handler for all three interactive instruments (Dial / GearDial / Rating).
  LblKnobs.Caption := Format(rsKnobsFmt, [Dial.Value, Gear.Value, Rating.Value]);
end;

procedure TMainForm.BusyChange(Sender: TObject);
begin
  // Active is the only thing you ever do to an indeterminate indicator — stop all three.
  Spin.Active := BusySwitch.Checked;
  GearSpin.Active := BusySwitch.Checked;
  Busy.Active := BusySwitch.Checked;
end;

end.
