unit umain;

{ TTySplitter demo -- nested docking: a vertical splitter (Align=alLeft) resizes the left
  column, a horizontal splitter (Align=alTop) nested in the right container resizes the top
  pane, and a third one (Align=alRight) resizes the Inspector from the TRAILING edge, where
  the delta inverts: dragging left GROWS the pane. MinSize clamps every one of them.

  The two ResizeStyles sit side by side: VSplit is rsUpdate, so the pane follows the mouse
  live; HSplit is rsLine, so nothing moves until the button comes up and the whole resize
  lands at once. OnCanResize vetoes any pane past 400 px, and OnMoved reports the result.

  The window, panels, splitters and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Panel, tyControls.Splitter, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblStatus: TTyLabel;
    ClientHost: TTyPanel;
    LeftPanel: TTyPanel;
    VSplit: TTySplitter;
    RightHost: TTyPanel;
    TopPanel: TTyPanel;
    HSplit: TTySplitter;
    BottomPanel: TTyPanel;
    InspectorPanel: TTyPanel;
    RSplit: TTySplitter;
    procedure FormCreate(Sender: TObject);
    procedure HandleMoved(Sender: TObject);
    procedure HandleCanResize(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
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

procedure TMainForm.HandleMoved(Sender: TObject);
begin
  // Fires once per drag, and only when the target's size actually changed. All three
  // splitters share it -- the readout simply reports every pane.
  LblStatus.Caption := Format('Drag complete · left column %d px · top band %d px · inspector %d px',
    [LeftPanel.Width, TopPanel.Height, InspectorPanel.Width]);
end;

procedure TMainForm.HandleCanResize(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
begin
  // OnCanResize is the veto: clear AAccept and the resize simply does not land -- the pane
  // stops dead at 400 px however far the mouse keeps going. (ANewSize is a var parameter
  // too, so writing to it instead would move the edge somewhere of your choosing.)
  if ANewSize > 400 then
  begin
    AAccept := False;
    LblStatus.Caption := Format('Rejected · %d px exceeds the 400 px cap', [ANewSize]);
    Exit;
  end;
  // All three splitters share this handler, but they reach it very differently: VSplit and
  // RSplit are rsUpdate, so this runs on every mouse move and the caption reads as a live
  // preview; HSplit is rsLine, so the whole drag is deferred and this runs exactly once,
  // on mouse-up.
  LblStatus.Caption := Format('Dragging · target size %d px', [ANewSize]);
end;

end.
