unit test.advchart.graphictip;
{$mode objfpc}{$H+}
{ A graphic element as a tooltip target -- held to upstream [spec 242].
  tools/advchart-oracle/graphic-tooltip.js runs ECharts 6.1 at 600 x 400
  with TooltipView running, moves the pointer to the centre of a graphic
  element (or a point it names) and records the tooltip shown: GraphicView
  gives every element a tooltip config (setTooltipConfig), so the content
  is the element's name -- an empty box without one -- under the element's
  tooltip (a string a formatter), the graphic component's, and the global
  component; {a} is the name, HTML-encoded. None where the element says
  show false, is silent, or there is no tooltip component, nor on a move
  under triggerOn 'click'. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Layout,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TGfxTipProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
  end;

  TAdvChartGraphicTooltipOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxTipProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheElementsShowUpstreamsTooltip;
  end;

implementation

const
  cW = 600;
  cH = 400;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-graphic-tooltip.json';
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

function TGfxTipProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TGfxTipProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TGfxTipProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TAdvChartGraphicTooltipOracleTest.SetUp;
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

procedure TAdvChartGraphicTooltipOracleTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartGraphicTooltipOracleTest.TestTheElementsShowUpstreamsTooltip;
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
    FChart := TGfxTipProbe.Create(FForm);
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
  AssertTrue(Format('enough was compared (%d)', [compared]), compared >= 16);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared) + ' differ:' + report, 0, bad);
end;

initialization
  RegisterTest(TAdvChartGraphicTooltipOracleTest);
end.
