unit umain;

{ TTyChart 示例 —— 折线 / 柱 / 饼三种图切换,同一份数据。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.Button, tyControls.CheckBox,
  tyControls.Chart;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
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
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Chart.Title := '季度销量';
  Chart.Categories.Text := 'Q1' + LineEnding + 'Q2' + LineEnding + 'Q3' + LineEnding + 'Q4';
  with Chart.Series.Add do begin Name := '华东'; Values := '12, 19, 15, 22'; end;
  with Chart.Series.Add do begin Name := '华南'; Values := '9, 14, 18, 16'; end;
  with Chart.Series.Add do begin Name := '华北'; Values := '7, 11, 13, 20'; end;
  Chart.ChartType := ctBar;

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.BtnLineClick(Sender: TObject); begin Chart.ChartType := ctLine; end;
procedure TMainForm.BtnBarClick(Sender: TObject);  begin Chart.ChartType := ctBar;  end;
procedure TMainForm.BtnPieClick(Sender: TObject);  begin Chart.ChartType := ctPie;  end;

procedure TMainForm.ChkLegendChange(Sender: TObject); begin Chart.ShowLegend := ChkLegend.Checked; end;
procedure TMainForm.ChkValuesChange(Sender: TObject); begin Chart.ShowValues := ChkValues.Checked; end;

end.
