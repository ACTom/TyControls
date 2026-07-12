unit umain;

{ TTyTrackBar demo:
  - Horizontal track bar (0..100), OnChange updates the status label live
  - Custom-range track bar (-50..50, shows a negative range)
  - Vertical track bar (Orientation = toVertical)
  - Fine-stepping track bar (PageSize / Frequency demo, its own range and readout)
  The main form (a TTyForm + TTyTitleBar), every track bar and the live theme switcher are
  designed in umain.lfm; the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TrackBar, tyControls.TyLabel, tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    LblVolume: TTyLabel;
    Track1: TTyTrackBar;
    LblBalance: TTyLabel;
    Track2: TTyTrackBar;
    LblBrightness: TTyLabel;
    Track4: TTyTrackBar;
    LblVertical: TTyLabel;
    Track3: TTyTrackBar;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure Track1Change(Sender: TObject);
    procedure Track2Change(Sender: TObject);
    procedure Track3Change(Sender: TObject);
    procedure Track4Change(Sender: TObject);
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

procedure TMainForm.Track1Change(Sender: TObject);
begin
  LblStatus.Caption := Format('音量：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track2Change(Sender: TObject);
begin
  LblStatus.Caption := Format('平衡：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track3Change(Sender: TObject);
begin
  LblStatus.Caption := Format('垂直：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track4Change(Sender: TObject);
begin
  LblStatus.Caption := Format('亮度：%d', [(Sender as TTyTrackBar).Position]);
end;

end.
