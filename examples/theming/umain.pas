unit umain;

{ Runtime theme hot-swap demo (TTyForm + TTyTitleBar edition):
  - the ThemeCombo in the title bar switches between all the compiled-in built-in themes live;
  - the three preset buttons jump to light / dark (built-in) and green (a FILE image-theme shipped
    in this example's own folder, so it is self-contained), updating the status label;
  - switching internally re-Invalidates every registered control, so the sample buttons / edit /
    checkbox / progress bar recolor "live", and ApplyChromeTheme reskins the window chrome + background;
  - the status label shows the current theme in real time.
  The window, every control and the theme switcher are designed in umain.lfm (a TTyForm + TTyTitleBar);
  the code here is theme setup + the switch handlers only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.ThemeRegistry,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox,
  tyControls.Edit, tyControls.CheckBox, tyControls.ProgressBar,
  tyControls.Types, tyControls.Css.Values, tyControls.Dialogs.Color;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    BtnLight: TTyButton;
    BtnDark: TTyButton;
    BtnClassic, BtnModern: TTyButton;
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
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure SwitchLight(Sender: TObject);
    procedure SwitchDark(Sender: TObject);
    procedure SwitchClassic(Sender: TObject);
    procedure SwitchModern(Sender: TObject);
    procedure SwitchGreen(Sender: TObject);
    procedure PickAccent(Sender: TObject);
    procedure ResetAccentClick(Sender: TObject);
  private
    { Enable the "复位默认" button only while a user accent override is active (it clears on a
      theme switch, so this keeps the button in sync with AccentOverride). }
    procedure UpdateAccentBtn;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

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
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
  LblStatus.Caption := '当前主题：' + ThemeCombo.Items[ThemeCombo.ItemIndex];
  UpdateAccentBtn;   // a theme switch clears any accent override (D2)
end;

{ Light/Dark toggle the mode of the CURRENTLY-active theme (NOT a switch to the default theme),
  so the picked skin stays and a custom accent survives (a mode change keeps the override). }
procedure TMainForm.SwitchLight(Sender: TObject);
begin
  TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := '模式：浅色';
end;

procedure TMainForm.SwitchDark(Sender: TObject);
begin
  TyDefaultController.Mode := 'dark';
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := '模式：深色';
end;

{ 密度轴与配色/皮肤正交:切它不动主题、不动明暗,只改整套尺度 ——
  字号、行高、内边距、圆角、控件高一起走。经典 = Win32 尺度,现代 = Web 尺度。 }
procedure TMainForm.SwitchClassic(Sender: TObject);
begin
  TyDefaultController.Density := tdClassic;
  LblStatus.Caption := '密度:经典(Win32 尺度)';
end;

procedure TMainForm.SwitchModern(Sender: TObject);
begin
  TyDefaultController.Density := tdModern;
  LblStatus.Caption := '密度:现代(Web 尺度)—— 与当前皮肤叠加,只改疏密不改观感';
end;

procedure TMainForm.SwitchGreen(Sender: TObject);
begin
  { The green theme is an IMAGE theme (photo background). A private copy lives in this example's
    own folder (green.tycss + assets/background.jpg) so it survives future edits to the repo's
    themes/. Loading it as a FILE resolves its url(assets/background.jpg) relative to that copy. }
  TyDefaultController.ThemeFile := LocalThemeFile('green.tycss');
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := '当前主题：green（图片背景）';
  UpdateAccentBtn;
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
    dlg.Caption := '选择主题色';
    // Seed the picker with the current override, if any.
    if TyDefaultController.AccentOverride <> '' then
      dlg.Color := TyParseColor(TyDefaultController.AccentOverride);
    if dlg.Execute then
    begin
      hex := '#' + IntToHex(TyRedOf(dlg.Color), 2) + IntToHex(TyGreenOf(dlg.Color), 2)
                 + IntToHex(TyBlueOf(dlg.Color), 2);
      TyDefaultController.SetAccent(hex);          // recolours every registered control + chrome
      ApplyChromeTheme(TyDefaultController);
      LblStatus.Caption := '主题色：' + hex + '（叠加在当前主题上）';
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
  LblStatus.Caption := '主题色：已恢复主题默认';
  UpdateAccentBtn;
end;

end.
