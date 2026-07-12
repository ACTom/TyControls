unit umain;

{ TTyScrollBar example:
  - a vertical scroll bar (Kind=sbVertical) and a horizontal one (Kind=sbHorizontal)
  - demonstrates Min / Max / Position / PageSize / SmallChange
  - OnChange live-aggregates both bars' Position into a TTyLabel status line
  The window, both scroll bars, the hint/status labels and the live theme switcher are
  designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ScrollBar, tyControls.TyLabel, tyControls.ComboBox;
type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    LblTip: TTyLabel;
    VBar: TTyScrollBar;
    HBar: TTyScrollBar;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure BarChange(Sender: TObject);
  private
    procedure UpdateStatus;
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

  UpdateStatus;                            // initial readout
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.UpdateStatus;
begin
  LblStatus.Caption := Format(
    '垂直:  Position = %d   (Min %d / Max %d / PageSize %d / SmallChange %d)' + LineEnding +
    LineEnding +
    '水平:  Position = %d   (Min %d / Max %d / PageSize %d / SmallChange %d)',
    [VBar.Position, VBar.Min, VBar.Max, VBar.PageSize, VBar.SmallChange,
     HBar.Position, HBar.Min, HBar.Max, HBar.PageSize, HBar.SmallChange]);
end;

procedure TMainForm.BarChange(Sender: TObject);
begin
  UpdateStatus;   // refresh the status line whenever either bar changes
end;

end.
