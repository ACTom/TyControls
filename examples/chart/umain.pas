unit umain;

{ TTyChart demo -- switch between line / bar / pie charts over the same data. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.CheckBox, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Chart;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    BtnLine: TTyButton;
    BtnBar:  TTyButton;
    BtnPie:  TTyButton;
    ChkLegend: TTyCheckBox;
    ChkValues: TTyCheckBox;
    Chart: TTyChart;

    procedure FormCreate(Sender: TObject);
    procedure BtnLineClick(Sender: TObject);
    procedure BtnBarClick(Sender: TObject);
    procedure BtnPieClick(Sender: TObject);
    procedure ChkLegendChange(Sender: TObject);
    procedure ChkValuesChange(Sender: TObject);
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
  Chart.Title := 'Quarterly sales';
  Chart.Categories.Text := 'Q1' + LineEnding + 'Q2' + LineEnding + 'Q3' + LineEnding + 'Q4';
  with Chart.Series.Add do begin Name := 'East China'; Values := '12, 19, 15, 22'; end;
  with Chart.Series.Add do begin Name := 'South China'; Values := '9, 14, 18, 16'; end;
  with Chart.Series.Add do begin Name := 'North China'; Values := '7, 11, 13, 20'; end;
  Chart.ChartType := ctBar;

  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);
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

procedure TMainForm.BtnLineClick(Sender: TObject); begin Chart.ChartType := ctLine; end;
procedure TMainForm.BtnBarClick(Sender: TObject);  begin Chart.ChartType := ctBar;  end;
procedure TMainForm.BtnPieClick(Sender: TObject);  begin Chart.ChartType := ctPie;  end;

procedure TMainForm.ChkLegendChange(Sender: TObject); begin Chart.ShowLegend := ChkLegend.Checked; end;
procedure TMainForm.ChkValuesChange(Sender: TObject); begin Chart.ShowValues := ChkValues.Checked; end;

end.
