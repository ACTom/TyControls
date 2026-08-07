unit umain;

{ TTyStatusBar demo:
  - Bottom status bar (Align=alBottom) with multiple Panels (each panel has Text/Width/Alignment)
  - A panel with Width <=0 auto-fills the remaining space (fill panel)
  - SizeGrip -- bottom-right resize handle
  - SimplePanel/SimpleText: switch to a single full-width text mode
  - PanelAtPos: the bar's only hit-test -- there is no OnPanelClick, so a click on one specific
    panel is resolved from OnMouseDown
  - SizeGrip can be switched off at run time (the corner dots go, and so does the OS resize drag)
  - Panels is a live collection: Add/Delete it while the app runs and the bar re-lays out
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
    BtnGrip: TTyButton;
    LblPanels: TTyLabel;
    BtnAddPanel: TTyButton;
    BtnRemovePanel: TTyButton;
    StatusBar: TTyStatusBar;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure UpdatePanel(Sender: TObject);       // update the left panel's text
    procedure ToggleSimple(Sender: TObject);      // toggle SimplePanel mode
    procedure ToggleGrip(Sender: TObject);        // toggle the size grip on/off
    procedure AddPanel(Sender: TObject);          // Panels.Add at run time
    procedure RemovePanel(Sender: TObject);       // Panels.Delete at run time
    procedure StatusBarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);         // hit-test the click with PanelAtPos
  private
    FClicks: Integer;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsSimpleClicksFmt = 'SimplePanel mode · clicked %d time(s)';
  rsUpdatedFmt      = 'Updated · %s';
  rsClicksFmt       = 'Clicks: %d';
  rsSimpleText      = 'SimplePanel: a single full-width status text';
  rsReady           = 'Ready';
  rsGripFmt         = 'SizeGrip = %s';
  rsNewPanelFmt     = 'New %d';
  rsClickedPanelFmt = 'You clicked panel %d';

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
    StatusBar.SimpleText := Format(rsSimpleClicksFmt, [FClicks])
  else
  begin
    // multi-panel mode: update the fill panel and the count panel separately
    StatusBar.Panels[0].Text := Format(rsUpdatedFmt, [FormatDateTime('hh:nn:ss', Now)]);
    StatusBar.Panels[1].Text := Format(rsClicksFmt, [FClicks]);
  end;
end;

procedure TMainForm.ToggleSimple(Sender: TObject);
begin
  StatusBar.SimplePanel := not StatusBar.SimplePanel;   // switch between multi-panel and whole-bar text
  if StatusBar.SimplePanel then
    StatusBar.SimpleText := rsSimpleText
  else
    StatusBar.Panels[0].Text := rsReady;
end;

procedure TMainForm.ToggleGrip(Sender: TObject);
begin
  // With the grip off the three corner dots disappear AND the bottom-right corner stops
  // handing the drag to the OS window resize -- the bar is then purely informational.
  StatusBar.SizeGrip := not StatusBar.SizeGrip;
  if StatusBar.SimplePanel then
    StatusBar.SimpleText := Format(rsGripFmt, [BoolToStr(StatusBar.SizeGrip, True)])
  else
    StatusBar.Panels[0].Text := Format(rsGripFmt, [BoolToStr(StatusBar.SizeGrip, True)]);
end;

procedure TMainForm.AddPanel(Sender: TObject);
begin
  // Panels is a plain TCollection, live at run time: TTyStatusPanels.Update repaints the
  // owner on any change, so a new item shows up without touching the bar itself. The first
  // panel has Width = 0 (the fill panel), so it simply shrinks to make room.
  with StatusBar.Panels.Add do
  begin
    Text := Format(rsNewPanelFmt, [StatusBar.Panels.Count - 1]);
    Width := 80;
    Alignment := taCenter;
  end;
end;

procedure TMainForm.RemovePanel(Sender: TObject);
begin
  // Delete is just as live. Stop at the three designed panels so the other buttons -- which
  // address Panels[0] and Panels[1] by index -- always have a target.
  if StatusBar.Panels.Count > 3 then
    StatusBar.Panels.Delete(StatusBar.Panels.Count - 1);
end;

procedure TMainForm.StatusBarMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  // PanelAtPos is the bar's only public API method: there is no OnPanelClick, so this is how
  // a click is attributed to one panel. It answers -1 outside every panel and in SimplePanel
  // mode (where there are no panel rectangles to hit).
  i := StatusBar.PanelAtPos(X, Y);
  if i >= 0 then
    StatusBar.Panels[0].Text := Format(rsClickedPanelFmt, [i]);
end;

end.
