unit umain;

{ Runtime theme hot-swap demo (TTyForm + TTyTitleBar edition):
  - the ThemeCombo in the title bar switches between all the compiled-in built-in themes live;
  - the three preset buttons jump to light / dark (built-in) and green (a FILE image-theme shipped
    in this example's own folder, so it is self-contained), updating the status label;
  - switching internally re-Invalidates every registered control, so the sample buttons / edit /
    checkbox / progress bar recolor "live", and ApplyChromeTheme reskins the window chrome + background;
  - the status label shows the current theme in real time.
  Below the sample strip the OTHER four layers of the same system are exercised:
  - Follow: 'Auto' sets Follow := tfFollowSystem so the controller tracks the OS light/dark scheme
    and accent (TTyForm arms a 750 ms poll); Light/Dark set Follow := tfManual back;
  - Density: the toggle flips Density between tdClassic and tdModern -- orthogonal to the skin, it
    re-resolves the geometry tokens (radius / padding / control heights) only;
  - HotReload: the checkbox arms the ThemeFile watch (it loads green.tycss first, since HotReload
    only watches a FILE theme) -- edit and save that file and the window re-themes within ~750 ms;
  - LoadThemeCssAdditive: 'Overlay a tweak' composes a small CSS layer ON TOP of the live theme,
    and 'Custom file' loads this example's own custom.tycss;
  - StyleOverride: BtnOverride carries its own per-instance CSS block (the last cascade layer),
    written in the .lfm -- it still uses var(--accent), so it recolours with the theme;
  - AddChangeListener: FormCreate hooks ThemeChanged, which is what re-skins the window chrome
    for changes NOTHING in this file triggers directly (a hot-reload save, an OS scheme flip).
  The window, every control and the theme switcher are designed in umain.lfm (a TTyForm + TTyTitleBar);
  the code here is theme setup + the switch handlers only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.ThemeRegistry,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox,
  tyControls.Edit, tyControls.CheckBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.Types, tyControls.Css.Values, tyControls.Dialogs.Color;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    BtnLight: TTyButton;
    BtnDark: TTyButton;
    BtnGreen: TTyButton;
    BtnAccent: TTyButton;
    BtnAccentReset: TTyButton;
    LblStatus: TTyLabel;
    LblSample: TTyLabel;
    BtnSample: TTyButton;
    BtnGhost: TTyButton;
    BtnDisabled: TTyButton;
    EdSample: TTyEdit;
    ChkSample: TTyCheckBox;
    ProgSample: TTyProgressBar;
    LblAdvanced: TTyLabel;
    BtnAuto: TTyButton;
    LblFollowHint: TTyLabel;
    SwitchDensity: TTyToggleSwitch;
    LblDensityHint: TTyLabel;
    ChkHotReload: TTyCheckBox;
    LblHotHint: TTyLabel;
    BtnOverlay: TTyButton;
    LblLayerHint: TTyLabel;
    BtnCustom: TTyButton;
    LblCustomHint: TTyLabel;
    BtnOverride: TTyButton;
    LblOvrHint: TTyLabel;
    LblListener: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure SwitchLight(Sender: TObject);
    procedure SwitchDark(Sender: TObject);
    procedure SwitchGreen(Sender: TObject);
    procedure SwitchAuto(Sender: TObject);
    procedure SwitchCustom(Sender: TObject);
    procedure DensityChange(Sender: TObject);
    procedure HotReloadChange(Sender: TObject);
    procedure OverlayClick(Sender: TObject);
    procedure PickAccent(Sender: TObject);
    procedure ResetAccentClick(Sender: TObject);
  private
    { Enable the "复位默认" button only while a user accent override is active (it clears on a
      theme switch, so this keeps the button in sync with AccentOverride). }
    procedure UpdateAccentBtn;
    { Registered with TyDefaultController.AddChangeListener: every theme / mode / accent /
      density / hot-reload change funnels through the controller's Changed, which repaints the
      registered CONTROLS but knows nothing about this window's chrome. Hooking it here is what
      re-skins the title bar + background for the changes no handler in this unit triggers
      directly -- a hot-reload save on disk, or the OS flipping to dark while Follow is on. }
    procedure ThemeChanged(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { Status-line texts composed at run time, so they live here rather than in the .lfm.
    Theme names, file names and the CSS overlay snippet are data -- they stay literals. }
  rsCurThemeFmt   = 'Current theme: %s';
  rsModeLight     = 'Mode: Light (manual)';
  rsModeDark      = 'Mode: Dark (manual)';
  rsFollowsOS     = 'Appearance: follows the OS light/dark setting';
  rsThemeGreen    = 'Current theme: green (image background)';
  rsThemeCustom   = 'Current theme: custom.tycss (hand-written, partial by design)';
  rsDensityModern = 'Density: modern (Web scale) - same skin, roomier geometry';
  rsDensityClassic = 'Density: classic';
  rsHotOnFmt      = 'Hot-reload ON - save an edit to %s and the window re-themes';
  rsHotOff        = 'Hot-reload OFF';
  rsOverlayDone   = 'Additive layer applied - skin kept, two tokens overridden';
  rsPickAccent    = 'Choose accent colour';
  rsAccentFmt     = 'Accent colour: %s (overlaid on the current theme)';
  rsAccentReset   = 'Accent colour: restored to theme default';

{ Find a file shipped alongside this example (its own green.tycss) by walking up from the exe --
  the built binary sits in examples/theming/lib/<cpu>-<os>/, the theme + its assets/ two levels up. }
function LocalThemeFile(const AName: string): string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if FileExists(Dir + AName) then Exit(Dir + AName);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := AName;
end;

{ Locate the repo themes/ folder by walking up from the exe until themes/auto.tycss is found. }
function LocalThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if FileExists(Dir + 'themes' + PathDelim + 'auto.tycss') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := '';
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  base: string;
begin
  // The whole compiled-in pack — the 'default'+'system' pair AND every structural skin (all
  // compiled IN via TyRegisterBuiltinThemes) — plus any extra theme FILE dropped in themes/
  // during development (the curated palettes, the green image demo): all pickable from one combo.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;                // default, system, classic, office, xp, win11, … (compiled in)
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  names := TyRegisterThemeDir(LocalThemesDir);  // extra local theme files, if any
  for i := 0 to High(names) do
  begin
    base := LowerCase(names[i]);
    // auto == default; light/dark are the default's single-mode halves; default/system already added.
    if (base = 'auto') or (base = 'light') or (base = 'dark')
       or (base = 'default') or (base = 'system') then Continue;
    if ThemeCombo.Items.IndexOf(names[i]) < 0 then
      ThemeCombo.Items.Add(names[i]);
  end;
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background
  UpdateAccentBtn;
  { Last, so the initial setup above stays a single explicit apply: from here on EVERY change to
    the controller (whoever makes it) re-skins this window through the listener. }
  TyDefaultController.AddChangeListener(@ThemeChanged);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { The default controller outlives this form, so unhook before the method pointer dangles --
    and disarm the two watch timers this example may have armed on it. }
  TyDefaultController.RemoveChangeListener(@ThemeChanged);
  TyDefaultController.HotReload := False;
  TyDefaultController.Follow := tfManual;
end;

procedure TMainForm.ThemeChanged(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
  UpdateAccentBtn;
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
  LblStatus.Caption := Format(rsCurThemeFmt, [ThemeCombo.Items[ThemeCombo.ItemIndex]]);
  UpdateAccentBtn;   // a theme switch clears any accent override (D2)
end;

{ Light/Dark toggle the mode of the CURRENTLY-active theme (NOT a switch to the default theme),
  so the picked skin stays and a custom accent survives (a mode change keeps the override).
  Picking a mode by hand is also what leaves OS-follow: Follow goes back to tfManual FIRST, so
  the next poll tick cannot pull the OS scheme back over the choice just made. The explicit
  ApplyChromeTheme is what disarms TTyForm's follow timer (UpdateFollowWatch runs inside it) --
  the change listener alone would not, because a no-op Mode set fires no Changed. }
procedure TMainForm.SwitchLight(Sender: TObject);
begin
  TyDefaultController.Follow := tfManual;
  TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := rsModeLight;
end;

procedure TMainForm.SwitchDark(Sender: TObject);
begin
  TyDefaultController.Follow := tfManual;
  TyDefaultController.Mode := 'dark';
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := rsModeDark;
end;

{ The third appearance state: hand the light/dark axis back to the OS. Setting Follow immediately
  pulls the current OS scheme + accent in (SetFollow -> RefreshFromSystem), and ApplyChromeTheme
  arms TTyForm's 750 ms poll so a LATER change to the OS setting is picked up too. }
procedure TMainForm.SwitchAuto(Sender: TObject);
begin
  TyDefaultController.Follow := tfFollowSystem;
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := rsFollowsOS;
end;

procedure TMainForm.SwitchGreen(Sender: TObject);
begin
  { The green theme is an IMAGE theme (photo background). A private copy lives in this example's
    own folder (green.tycss + assets/background.jpg) so it survives future edits to the repo's
    themes/. Loading it as a FILE resolves its url(assets/background.jpg) relative to that copy. }
  TyDefaultController.ThemeFile := LocalThemeFile('green.tycss');
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := rsThemeGreen;
  UpdateAccentBtn;
end;

{ The "write your own theme file" path the README promises: custom.tycss ships beside this
  example and only restyles a handful of typeKeys -- everything it leaves out keeps rendering,
  because the built-in base layer sits under every user theme. }
procedure TMainForm.SwitchCustom(Sender: TObject);
begin
  TyDefaultController.ThemeFile := LocalThemeFile('custom.tycss');
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := rsThemeCustom;
  UpdateAccentBtn;
end;

{ The density axis is ORTHOGONAL to the skin: whatever theme is loaded keeps its colours, and
  only the geometry tokens (radius, padding, control heights, icon and row sizes) re-resolve.
  Switching it re-loads layer-1 and re-appends the modern pack, so it composes with any theme. }
procedure TMainForm.DensityChange(Sender: TObject);
begin
  if SwitchDensity.Checked then
  begin
    TyDefaultController.Density := tdModern;
    LblStatus.Caption := rsDensityModern;
  end
  else
  begin
    TyDefaultController.Density := tdClassic;
    LblStatus.Caption := rsDensityClassic;
  end;
  ApplyChromeTheme(TyDefaultController);
end;

{ HotReload watches the theme FILE, so a compiled-in ThemeName has nothing to watch: arming it
  switches to the file theme shipped here first. From then on the controller polls green.tycss
  every 750 ms and reloads it on any save -- the chrome follows because ThemeChanged is hooked. }
procedure TMainForm.HotReloadChange(Sender: TObject);
begin
  if ChkHotReload.Checked then
  begin
    if TyDefaultController.ThemeFile = '' then
      TyDefaultController.ThemeFile := LocalThemeFile('green.tycss');
    TyDefaultController.HotReload := True;
    LblStatus.Caption := Format(rsHotOnFmt,
      [ExtractFileName(TyDefaultController.ThemeFile)]);
  end
  else
  begin
    TyDefaultController.HotReload := False;
    LblStatus.Caption := rsHotOff;
  end;
  ApplyChromeTheme(TyDefaultController);
  UpdateAccentBtn;
end;

{ The additive layer (A6). LoadThemeCss REPLACES layer-1; LoadThemeCssAdditive composes ON TOP
  of it, so the skin, its images and every rule it defines survive and only the declarations
  written here win. Pick another theme in the combo to drop the layer (a switch REPLACEs). }
procedure TMainForm.OverlayClick(Sender: TObject);
begin
  TyDefaultController.LoadThemeCssAdditive(':root { --accent: #7C3AED; --radius: 12px; }');
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := rsOverlayDone;
end;

procedure TMainForm.UpdateAccentBtn;
begin
  BtnAccentReset.Enabled := TyDefaultController.AccentOverride <> '';
end;

{ Pick a runtime accent colour: any theme can be recoloured on the fly (independent of its
  light/dark mode) — the whole interactive palette re-derives from the one --accent seed. }
procedure TMainForm.PickAccent(Sender: TObject);
var
  dlg: TTyColorDialog;
  hex: string;
begin
  dlg := TTyColorDialog.Create(nil);
  try
    dlg.Caption := rsPickAccent;
    // Seed the picker with the current override, if any.
    if TyDefaultController.AccentOverride <> '' then
      dlg.Color := TyParseColor(TyDefaultController.AccentOverride);
    if dlg.Execute then
    begin
      hex := '#' + IntToHex(TyRedOf(dlg.Color), 2) + IntToHex(TyGreenOf(dlg.Color), 2)
                 + IntToHex(TyBlueOf(dlg.Color), 2);
      TyDefaultController.SetAccent(hex);          // recolours every registered control + chrome
      ApplyChromeTheme(TyDefaultController);
      LblStatus.Caption := Format(rsAccentFmt, [hex]);
    end;
  finally
    dlg.Free;
  end;
  UpdateAccentBtn;
end;

procedure TMainForm.ResetAccentClick(Sender: TObject);
begin
  TyDefaultController.ResetAccent;                 // back to the theme's own accent
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := rsAccentReset;
  UpdateAccentBtn;
end;

end.
