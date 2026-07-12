unit umain;

{ TTySpinEdit demo:
  Showcases the main published properties and events of this integer spin box
  (the implementation is integer-only; decimals are not supported):
    - Value / MinValue / MaxValue / Increment, with OnChange writing live to the status bar
    - Negative range (-50..50, step 5)
    - Alignment (right-justified), MaxLength (limits the number of digits entered)
    - ReadOnly (locked: no editing/stepping/wheel)
  Interaction: up/down arrow buttons, keyboard ↑/↓, mouse wheel, or typing then Enter to commit.
  The UI (window, every spin box, labels and the live theme switcher) is designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is theme setup + event handlers only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.SpinEdit, tyControls.TyLabel, tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    LblQty: TTyLabel;
    SpinQty: TTySpinEdit;      // 0..100 step 1
    LblOfs: TTyLabel;
    SpinOfs: TTySpinEdit;      // -50..50 step 5 (negative range)
    LblYear: TTyLabel;
    SpinYear: TTySpinEdit;     // right-justified + MaxLength
    LblLock: TTyLabel;
    SpinLock: TTySpinEdit;     // ReadOnly locked
    LblStatusCap: TTyLabel;
    LblStatus: TTyLabel;       // OnChange status output
    procedure FormCreate(Sender: TObject);
    procedure SpinChange(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
  private
    procedure UpdateStatus(const ATag: string; ASpin: TTySpinEdit);
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

procedure TMainForm.UpdateStatus(const ATag: string; ASpin: TTySpinEdit);
begin
  LblStatus.Caption := Format('%s → %d', [ATag, ASpin.Value]);
end;

procedure TMainForm.SpinChange(Sender: TObject);
begin
  if Sender = SpinQty then
    UpdateStatus('数量', SpinQty)
  else if Sender = SpinOfs then
    UpdateStatus('偏移', SpinOfs)
  else if Sender = SpinYear then
    UpdateStatus('年份', SpinYear)
  else if Sender = SpinLock then
    UpdateStatus('锁定', SpinLock);
end;

end.
