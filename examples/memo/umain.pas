unit umain;

{ TTyMemo demo (borderless self-drawn TTyForm chrome + TTyTitleBar):
  - Lines: multi-line text model (Enter for new line, Backspace/Delete merge across lines, arrow/Home/End navigation)
  - ScrollBars: defaults to ssAutoVertical; a vertical scrollbar appears on the right when content overflows; mouse wheel supported
  - ReadOnly: when checked, all user edits are ignored (navigation/selection/copy still work)
  - WordWrap: when checked, long logical lines soft-wrap at word boundaries into multiple visual lines
  - OnChange: fires whenever the text model changes; updates the line/character count labels live
  The window, the memo, both toggles and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Memo, tyControls.TyLabel, tyControls.CheckBox, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblPrompt: TTyLabel;
    Memo: TTyMemo;
    ChkReadOnly: TTyCheckBox;
    ChkWordWrap: TTyCheckBox;
    LblInfo: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure ReadOnlyClick(Sender: TObject);
    procedure WordWrapClick(Sender: TObject);
  private
    procedure UpdateInfo;
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

  // The seed lines come from the .lfm; compute the initial line/char stats.
  UpdateInfo;
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

procedure TMainForm.UpdateInfo;
begin
  LblInfo.Caption := Format('行数：%d    字符数：%d',
    [Memo.Lines.Count, Length(Memo.Text)]);
end;

procedure TMainForm.MemoChange(Sender: TObject);
begin
  // OnChange: refresh the stats whenever the text model changes
  UpdateInfo;
end;

procedure TMainForm.ReadOnlyClick(Sender: TObject);
begin
  Memo.ReadOnly := ChkReadOnly.Checked;
end;

procedure TMainForm.WordWrapClick(Sender: TObject);
begin
  Memo.WordWrap := ChkWordWrap.Checked;
end;

end.
