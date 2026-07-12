unit umain;

{ Runtime theme hot-swap demo (TTyForm + TTyTitleBar edition):
  - the ThemeCombo in the title bar switches between the 12 compiled-in built-in themes live;
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
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox,
  tyControls.Edit, tyControls.CheckBox, tyControls.ProgressBar,
  tyControls.Types, tyControls.Css.Values, tyControls.Dialogs.Color;

type
  TMainForm = class(TTyForm)
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
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure SwitchLight(Sender: TObject);
    procedure SwitchDark(Sender: TObject);
    procedure SwitchGreen(Sender: TObject);
    procedure PickAccent(Sender: TObject);
    procedure ResetAccentClick(Sender: TObject);
  private
    { Apply a built-in theme (optionally forcing a light/dark mode) and update the status label. }
    procedure ApplyPreset(const AThemeName, AMode, AStatus: string);
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

{ LoadTheme's Changed() walks every registered control and Invalidates them, so the sample
  controls reskin live; ApplyChromeTheme makes the title bar + form background follow along. }
procedure TMainForm.ApplyPreset(const AThemeName, AMode, AStatus: string);
begin
  TyDefaultController.ThemeName := AThemeName;
  if AMode <> '' then
    TyDefaultController.Mode := AMode;    // dual-mode themes: force the light/dark block
  ApplyChromeTheme(TyDefaultController);
  LblStatus.Caption := AStatus;
  UpdateAccentBtn;
end;

procedure TMainForm.SwitchLight(Sender: TObject);
begin
  ApplyPreset('default', 'light', '当前主题：default（亮色）');
end;

procedure TMainForm.SwitchDark(Sender: TObject);
begin
  ApplyPreset('default', 'dark', '当前主题：default（暗色）');
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
