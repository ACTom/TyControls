unit umain;

{ TTyToolBar + TTyToolSeparator demo:
  - alTop top toolbar holding several TTyButton tool buttons (the toolbar rewrites Flat buttons into the ghost variant)
  - TTyToolSeparator inserts a vertical divider between button groups
  - ButtonHeight / ButtonSpacing / Indent control button size and layout
  - Flat (flat/ghost) . Wrapable (auto-wrap when too wide; toolbar grows taller as the row count changes)
  - each tool button's OnClick reports to the bottom TTyLabel status label
  The window, the toolbar, every tool button and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ToolBar, tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.GlyphButtons, tyControls.IconFont;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    Icons: TTyIconFont;
    ToolBar: TTyToolBar;
    BtnNew: TTyGlyphButton;
    BtnOpen: TTyGlyphButton;
    BtnSave: TTyGlyphButton;
    Sep1: TTyToolSeparator;
    BtnCut: TTyButton;
    BtnCopy: TTyButton;
    BtnPaste: TTyButton;
    Sep2: TTyToolSeparator;
    BtnFind: TTyButton;
    BtnReplace: TTyButton;
    BtnSelectAll: TTyButton;
    Sep3: TTyToolSeparator;
    { Toggling tools: Down is the resting :selected state (TyButton.ghost:selected). }
    BtnBold: TTyButton;
    BtnItalic: TTyButton;
    BtnUnderline: TTyButton;
    { Second bar: Flat = False, Wrapable = False, ButtonHeight left unset. }
    ToolBarFramed: TTyToolBar;
    BtnAlignLeft: TTyButton;
    BtnAlignCenter: TTyButton;
    BtnAlignRight: TTyButton;
    BtnJustify: TTyButton;
    Sep4: TTyToolSeparator;
    BtnBullets: TTyButton;
    BtnNumbers: TTyButton;
    BtnQuote: TTyButton;
    LblWrapHint: TTyLabel;
    LblDownHint: TTyLabel;
    LblGlyphHint: TTyLabel;
    LblFramedHint: TTyLabel;
    LblReserved: TTyLabel;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ToolClicked(Sender: TObject);
    procedure ToolToggle(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsFiredFmt  = 'Fired tool: %s';
  rsToggleFmt = '%s: Down = %s';

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

procedure TMainForm.ToolClicked(Sender: TObject);
begin
  LblStatus.Caption := Format(rsFiredFmt, [(Sender as TTyButton).Caption]);
end;

procedure TMainForm.ToolToggle(Sender: TObject);
var
  B: TTyButton;
begin
  // A toggling tool: Down is the resting :selected state, so the tool keeps the
  // pressed look after the mouse leaves. There is no built-in grouping — the app
  // owns the state, which is why this flips it by hand.
  B := Sender as TTyButton;
  B.Down := not B.Down;
  LblStatus.Caption := Format(rsToggleFmt, [B.Caption, BoolToStr(B.Down, True)]);
end;

end.
