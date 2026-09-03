unit umain;

{ TTyAdvanceChart demo -- the option tree IS the API, so this form is mostly a
  text box and a chart.

  Type an ECharts-shaped option on the left and it draws on the right. That is
  the whole point of the control: an option pasted from ECharts' own gallery
  parses as it stands, unquoted keys and trailing commas and all.

  The theme switcher is here for the same reason it is in every other example,
  and it earns its place twice over for a chart: the axis domain resolves eight
  theme keys, so switching a skin is what proves the chart is drawn IN the theme
  rather than pasted on top of one. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.TyLabel, tyControls.Memo, tyControls.AdvanceChart;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    OptionMemo: TTyMemo;
    Chart: TTyAdvanceChart;
    BtnBars: TTyButton;
    BtnTwoAxes: TTyButton;
    BtnApply: TTyButton;
    LblError: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure BtnBarsClick(Sender: TObject);
    procedure BtnTwoAxesClick(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
  private
    procedure Apply;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsOptionOk = 'The option parsed.';
  rsDiagnostics = '%d thing(s) the chart could not honour — see below.';

const
  { A plain category chart. Written the way ECharts' own documentation writes
    it, unquoted keys and all, because parsing that is the reason the API is an
    option tree rather than a set of published properties. }
  cBars =
    '{' + LineEnding +
    '  xAxis: { data: [''Mon'', ''Tue'', ''Wed'', ''Thu'', ''Fri''] },' + LineEnding +
    '  yAxis: {},' + LineEnding +
    '  series: [{ type: ''bar'', data: [120, 200, 150, 80, 170] }]' + LineEnding +
    '}';

  { The one this whole layer exists for: two series of different types sharing a
    category axis, the second one on its OWN value axis. Switch to it and the
    right-hand axis gets its own numbers -- if it showed the left-hand axis'
    numbers instead, everything would still be drawn and the chart would be
    lying. }
  cTwoAxes =
    '{' + LineEnding +
    '  xAxis: [{ type: ''category'', data: [''Mon'', ''Tue'', ''Wed'', ''Thu'', ''Fri''] }],' + LineEnding +
    '  yAxis: [{ type: ''value'' }, { type: ''value'' }],' + LineEnding +
    '  series: [' + LineEnding +
    '    { type: ''bar'',  data: [1, 2, 3, 2, 4] },' + LineEnding +
    '    { type: ''line'', yAxisIndex: 1, data: [100, 200, 300, 250, 400] }' + LineEnding +
    '  ]' + LineEnding +
    '}';

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);
  OptionMemo.Text := cTwoAxes;
  Apply;
  { --shot <file> [theme] [dark]: draw once and quit. That is how a real-machine
    render gets captured on a desktop that will not let a background process take
    the foreground -- the pixels come from the running control with a real handle,
    not from a screen grab of whatever happened to be in front. The optional theme
    and mode are what make "the axis follows the skin" checkable rather than
    merely asserted. }
  if (ParamCount >= 2) and (ParamStr(1) = '--shot') then
  begin
    if ParamCount >= 3 then
    begin
      TyDefaultController.ThemeName := ParamStr(3);
      if ParamCount >= 4 then TyDefaultController.Mode := ParamStr(4);
      ApplyChromeTheme(TyDefaultController);
    end;
    Chart.SaveToPng(ParamStr(2));
    Application.Terminate;
  end;
end;

procedure TMainForm.Apply;
var i: Integer;
begin
  Chart.Option := OptionMemo.Text;
  if Chart.OptionError <> '' then
  begin
    LblError.Caption := Chart.OptionError;
    Exit;
  end;
  if Chart.DiagnosticCount = 0 then
  begin
    LblError.Caption := rsOptionOk;
    Exit;
  end;
  { A chart that silently drops what it cannot draw is a chart that lies, so
    the diagnostics are on screen rather than in a log nobody opens. }
  LblError.Caption := Format(rsDiagnostics, [Chart.DiagnosticCount]);
  for i := 0 to Chart.DiagnosticCount - 1 do
    LblError.Caption := LblError.Caption + LineEnding + '• ' + Chart.Diagnostic(i);
end;

procedure TMainForm.BtnApplyClick(Sender: TObject);
begin
  Apply;
end;

procedure TMainForm.BtnBarsClick(Sender: TObject);
begin
  OptionMemo.Text := cBars;
  Apply;
end;

procedure TMainForm.BtnTwoAxesClick(Sender: TObject);
begin
  OptionMemo.Text := cTwoAxes;
  Apply;
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

end.
