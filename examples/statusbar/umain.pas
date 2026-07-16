unit umain;

{ TTyStatusBar demo:
  - Bottom status bar (Align=alBottom) with multiple Panels (each panel has Text/Width/Alignment)
  - A panel with Width <=0 auto-fills the remaining space (fill panel)
  - SizeGrip -- bottom-right resize handle
  - SimplePanel/SimpleText: switch to a single full-width text mode
  - Clicking a button updates a panel's text (multi-panel mode) or the whole-bar text (simple mode)
  The window, the status bar (panels included) and the live theme switcher are designed in
  umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.StatusBar, tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    HintLbl: TTyLabel;
    BtnUpdate: TTyButton;
    BtnSimple: TTyButton;
    StatusBar: TTyStatusBar;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure UpdatePanel(Sender: TObject);       // update the left panel's text
    procedure ToggleSimple(Sender: TObject);      // toggle SimplePanel mode
  private
    FClicks: Integer;
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

procedure TMainForm.UpdatePanel(Sender: TObject);
begin
  Inc(FClicks);
  if StatusBar.SimplePanel then
    // simple mode: update the whole-bar text (SetSimpleText triggers a repaint)
    StatusBar.SimpleText := Format('SimplePanel 模式 · 已点击 %d 次', [FClicks])
  else
  begin
    // multi-panel mode: update the fill panel and the count panel separately
    StatusBar.Panels[0].Text := Format('已更新 · %s', [FormatDateTime('hh:nn:ss', Now)]);
    StatusBar.Panels[1].Text := Format('点击:%d', [FClicks]);
  end;
end;

procedure TMainForm.ToggleSimple(Sender: TObject);
begin
  StatusBar.SimplePanel := not StatusBar.SimplePanel;   // switch between multi-panel and whole-bar text
  if StatusBar.SimplePanel then
    StatusBar.SimpleText := 'SimplePanel:单一整条状态文本'
  else
    StatusBar.Panels[0].Text := '就绪';
end;

end.
