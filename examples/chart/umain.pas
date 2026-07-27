unit umain;

{ TTyChart demo -- switch between line / bar / pie / donut charts over the same data.
  The whole data model (Title, Categories, the Series collection and each series' Values /
  Color) is authored in umain.lfm, so the code here is only the toggles, the tooltip hook
  and the click-to-drill hit-test. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.CheckBox, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.TyLabel, tyControls.Chart;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    BtnLine: TTyButton;
    BtnBar:  TTyButton;
    BtnPie:  TTyButton;
    BtnDonut: TTyButton;
    ChkLegend: TTyCheckBox;
    ChkValues: TTyCheckBox;
    ChkGrid: TTyCheckBox;
    ChkTooltip: TTyCheckBox;
    Chart: TTyChart;
    LblPalette: TTyLabel;
    LblNegative: TTyLabel;
    LblHit: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure BtnLineClick(Sender: TObject);
    procedure BtnBarClick(Sender: TObject);
    procedure BtnPieClick(Sender: TObject);
    procedure BtnDonutClick(Sender: TObject);
    procedure ChkLegendChange(Sender: TObject);
    procedure ChkValuesChange(Sender: TObject);
    procedure ChkGridChange(Sender: TObject);
    procedure ChkTooltipChange(Sender: TObject);
    procedure ChartGetTooltip(Sender: TObject; ASeries, APoint: Integer; var AText: string);
    procedure ChartMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
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
procedure TMainForm.BtnDonutClick(Sender: TObject); begin Chart.ChartType := ctDonut; end;

procedure TMainForm.ChkLegendChange(Sender: TObject); begin Chart.ShowLegend := ChkLegend.Checked; end;
procedure TMainForm.ChkValuesChange(Sender: TObject); begin Chart.ShowValues := ChkValues.Checked; end;
procedure TMainForm.ChkGridChange(Sender: TObject); begin Chart.ShowGrid := ChkGrid.Checked; end;
procedure TMainForm.ChkTooltipChange(Sender: TObject); begin Chart.ShowTooltip := ChkTooltip.Checked; end;

procedure TMainForm.ChartGetTooltip(Sender: TObject; ASeries, APoint: Integer;
  var AText: string);
begin
  // AText arrives holding the chart's own default text; append rather than replace, so the
  // reader can see both the built-in wording and the app's addition.
  AText := AText + LineEnding + Format('(series %d, point %d)', [ASeries, APoint]);
end;

procedure TMainForm.ChartMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Hit: TTyChartHit;
begin
  // HitTestAt answers the SAME datum the tooltip reads, so click-to-drill needs no geometry.
  Hit := Chart.HitTestAt(X, Y);
  if TyChartHitValid(Hit) then
    LblHit.Caption := Format('Hit: series %d, point %d', [Hit.SeriesIndex, Hit.PointIndex])
  else
    LblHit.Caption := 'Hit: nothing there';
end;

end.
