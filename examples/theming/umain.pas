unit umain;

{ Runtime theme hot-swap demo (TTyForm + TTyTitleBar edition):
  - the ThemeCombo in the title bar switches between the 12 compiled-in built-in themes live;
  - the three preset buttons jump straight to a light / dark / distinct look, updating the status label;
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
  tyControls.Edit, tyControls.CheckBox, tyControls.ProgressBar;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    BtnLight: TTyButton;
    BtnDark: TTyButton;
    BtnGreen: TTyButton;
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
  private
    { Apply a built-in theme (optionally forcing a light/dark mode) and update the status label. }
    procedure ApplyPreset(const AThemeName, AMode, AStatus: string);
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
  LblStatus.Caption := '当前主题：' + ThemeCombo.Items[ThemeCombo.ItemIndex];
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
  ApplyPreset('nord', 'light', '当前主题：nord');
end;

end.
