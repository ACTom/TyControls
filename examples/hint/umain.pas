unit umain;

{ Hint demo: TTyHint (themed tooltip, applies app-wide) + TTyBalloonHint (balloon with a pointer).
  The window, the app-wide hint installer, both hinted buttons, every balloon and the live theme
  switcher are all designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event
  handlers + theme setup only.
  Hover a button to see the themed tooltip; click the show-balloon button to see the pointed callout.
  What each row demonstrates:
    - TTyHint.Active               the app-wide install switch; off restores the OS tooltip
    - TTyBalloonHint.Icon          all four values: biInfo / biWarning / biError / biNone
    - TTyBalloonHint.HideInterval  2000 ms auto-hide, and 0 = stay until dismissed
    - TTyBalloonHint.HideHint      the only way to close a HideInterval = 0 balloon
    - TTyBalloonHint.ShowAt        point a balloon at a bare screen rectangle (and see the
                                   body flip ABOVE the target when there is no room below) }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Button, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Hint, tyControls.BalloonHint;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    AppHint: TTyHint;
    LblIntro: TTyLabel;
    BtnSave: TTyButton;
    BtnDel: TTyButton;
    HintSwitch: TTyToggleSwitch;
    LblHintNote: TTyLabel;
    LblBalloons: TTyLabel;
    BtnBalloon: TTyButton;
    BtnWarn: TTyButton;
    BtnErr: TTyButton;
    BtnPlain: TTyButton;
    LblSticky: TTyLabel;
    BtnSticky: TTyButton;
    BtnHide: TTyButton;
    LblScreen: TTyLabel;
    BtnScreen: TTyButton;
    Balloon: TTyBalloonHint;
    BalloonWarn: TTyBalloonHint;
    BalloonErr: TTyBalloonHint;
    BalloonPlain: TTyBalloonHint;
    BalloonSticky: TTyBalloonHint;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure HintSwitchChange(Sender: TObject);
    procedure ShowBalloon(Sender: TObject);
    procedure ShowWarnBalloon(Sender: TObject);
    procedure ShowErrBalloon(Sender: TObject);
    procedure ShowPlainBalloon(Sender: TObject);
    procedure ShowStickyBalloon(Sender: TObject);
    procedure HideStickyBalloon(Sender: TObject);
    procedure ShowScreenBalloon(Sender: TObject);
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

procedure TMainForm.HintSwitchChange(Sender: TObject);
begin
  // TTyHint.Active swaps TTyHintWindow in and out of LCL's global HintWindowClass,
  // so flipping it here changes EVERY tooltip in the application at once.
  AppHint.Active := HintSwitch.Checked;
end;

procedure TMainForm.ShowBalloon(Sender: TObject);
begin
  Balloon.ShowFor(BtnBalloon);
end;

procedure TMainForm.ShowWarnBalloon(Sender: TObject);
begin
  BalloonWarn.ShowFor(BtnWarn);      // Icon = biWarning
end;

procedure TMainForm.ShowErrBalloon(Sender: TObject);
begin
  BalloonErr.ShowFor(BtnErr);        // Icon = biError paints the danger-accent disc
end;

procedure TMainForm.ShowPlainBalloon(Sender: TObject);
begin
  BalloonPlain.ShowFor(BtnPlain);    // Icon = biNone drops the disc entirely
end;

procedure TMainForm.ShowStickyBalloon(Sender: TObject);
begin
  // HideInterval = 0, so no timer is armed and this one waits for HideHint.
  BalloonSticky.ShowFor(BtnSticky);
end;

procedure TMainForm.HideStickyBalloon(Sender: TObject);
begin
  BalloonSticky.HideHint;
end;

procedure TMainForm.ShowScreenBalloon(Sender: TObject);
begin
  // ShowAt takes a bare SCREEN rectangle -- no target control needed. Aimed at the
  // bottom of the screen there is no room below, so the body flips above the target
  // and the pointer moves to the body's bottom edge.
  Balloon.ShowAt(Rect(Screen.Width div 2 - 40, Screen.Height - 60,
                      Screen.Width div 2 + 40, Screen.Height - 20));
end;

end.
