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
  tyControls.ToolBar, tyControls.Button, tyControls.TyLabel, tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    ToolBar: TTyToolBar;
    BtnNew: TTyButton;
    BtnOpen: TTyButton;
    BtnSave: TTyButton;
    Sep1: TTyToolSeparator;
    BtnCut: TTyButton;
    BtnCopy: TTyButton;
    BtnPaste: TTyButton;
    Sep2: TTyToolSeparator;
    BtnFind: TTyButton;
    BtnReplace: TTyButton;
    BtnSelectAll: TTyButton;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ToolClicked(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
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

procedure TMainForm.ToolClicked(Sender: TObject);
begin
  LblStatus.Caption := Format('已触发工具:%s', [(Sender as TTyButton).Caption]);
end;

end.
