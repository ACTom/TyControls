unit test.advchart.axistooltip;
{$mode objfpc}{$H+}
{ An axis' name and labels as tooltip targets -- held to upstream [F4c].

  tools/advchart-oracle/axis-tooltip.js runs ECharts 6.1 at 600 x 400 with
  TooltipView running, moves the pointer to the centre of an axis' name or
  of one of its labels, and records the tooltip shown: the text when the
  axis says tooltip.show (the content is the text; the axis' formatter
  through formatTpl, {a} the text, a label's {c} its rawLabel and {d} its
  tick index, HTML-encoded), and none when the text is silent (neither
  triggerEvent nor tooltip.show, or silent), when triggerEvent alone leaves
  the axis' default `tooltip.show: false`, or when there is no tooltip
  component. The control measures with zrender's width table, so the texts
  sit where upstream's do. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Layout,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TAxTipProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
  end;

  TAdvChartAxisTooltipOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAxTipProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheAxisTextsShowUpstreamsTooltip;
  end;

implementation

const
  cW = 600;
  cH = 400;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-axis-tooltip.json';
end;

function LoadJson(const APath: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

function TAxTipProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TAxTipProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TAxTipProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TAdvChartAxisTooltipOracleTest.SetUp;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart := nil;
end;

procedure TAdvChartAxisTooltipOracleTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartAxisTooltipOracleTest.TestTheAxisTextsShowUpstreamsTooltip;
var
  cases: TJSONArray;
  cs, m: TJSONObject;
  c, bad, compared: Integer;
  report, id, want: string;
  pt: TJSONArray;
  tip: TJSONData;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  m := TJSONObject(FRoot).Objects['measure'];
  bad := 0;
  compared := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    id := cs.Strings['id'];
    FreeAndNil(FChart);
    FChart := TAxTipProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
      m.Integers['firstCode']));
    FChart.TooltipNow := 0;
    FChart.Option := cs.Objects['option'].AsJSON;
    FChart.SetBounds(0, 0, cW, cH);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    pt := cs.Arrays['point'];
    FChart.Move(pt.Integers[0], pt.Integers[1]);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    tip := cs.Find('tip');
    Inc(compared);
    if (tip = nil) or (tip.JSONType = jtNull) then
    begin
      if FChart.TooltipShown then
      begin
        Inc(bad);
        report := report + LineEnding + Format('  %s: a tooltip "%s"; upstream none',
          [id, FChart.TooltipFormatterText]);
      end;
    end
    else
    begin
      want := TJSONObject(tip).Strings['text'];
      if not FChart.TooltipShown or (FChart.TooltipFormatterText <> want) then
      begin
        Inc(bad);
        report := report + LineEnding + Format('  %s: shown %s "%s"; upstream "%s"',
          [id, BoolToStr(FChart.TooltipShown, True), FChart.TooltipFormatterText, want]);
      end;
    end;
  end;
  FreeAndNil(FChart);
  AssertTrue(Format('enough was compared (%d)', [compared]), compared >= 11);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared) + ' differ:' + report, 0, bad);
end;

initialization
  RegisterTest(TAdvChartAxisTooltipOracleTest);
end.
