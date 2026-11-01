unit test.advchart.imageshadow;
{$mode objfpc}{$H+}
{ A PICTURE CASTS ITS SHADOW, held to ECharts 6.1. [R5-F, spec 243]

  tools/advchart-oracle/image-shadow.js runs the real dist: scatter, line and
  pictorial-bar symbols written 'image://...' with an itemStyle shadow (an
  item's own over the series'), and pictures with none; every Image
  element's shadow keys.

  The control renders each option: every picture of the list carries the
  shadow upstream's style holds (series, row), and the painter casts one
  for each picture that has one (zrender's canvas draws an Image with the
  context's shadow bound) and none for those that have none. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel, tyControls.Painter,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TIsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartImageShadowOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TIsProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FImages: Integer;
    FReport: string;
    procedure NewChart;
    procedure Miss(const AWhat: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePicturesCastAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TIsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TIsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TIsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-image-shadow.json';
end;

procedure TAdvChartImageShadowOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FImages := 0;
  FReport := '';
end;

procedure TAdvChartImageShadowOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TIsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartImageShadowOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartImageShadowOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + AWhat;
end;

procedure TAdvChartImageShadowOracleTest.TestThePicturesCastAsUpstream;
var
  cases, imgs: TJSONArray;
  c, i, k, n, casting, before: Integer;
  cs, im: TJSONObject;
  el: TTyChartElement;
  got: Boolean;
  col: TTyChartColor;
  blur: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    NewChart;
    FChart.Option := cs.Objects['option'].AsJSON;
    AssertEquals(cs.Strings['id'] + ': the option parses', '', FChart.OptionError);
    before := TyPainterShadowsCastForTest;
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
    imgs := cs.Arrays['images'];
    { as many pictures }
    n := 0;
    for k := 0 to FChart.List.Count - 1 do
      if (FChart.List.Element(k).Shape.Image <> '') and not FChart.List.Element(k).Ignore then Inc(n);
    Inc(FCompared);
    if n <> imgs.Count then
      Miss(Format('%s: %d pictures upstream, %d here', [cs.Strings['id'], imgs.Count, n]));
    casting := 0;
    for i := 0 to imgs.Count - 1 do
    begin
      im := imgs.Objects[i];
      blur := 0;
      if im.Find('shadowBlur').JSONType = jtNumber then blur := im.Floats['shadowBlur'];
      if blur > 0 then Inc(casting);
      { a picture of its row carrying that shadow }
      got := False;
      for k := 0 to FChart.List.Count - 1 do
      begin
        el := FChart.List.Element(k);
        if (el.Shape.Image = '') or (el.Datum.SeriesIndex <> im.Integers['s'])
          or (el.Datum.DataIndex <> im.Integers['d']) then Continue;
        got := True;
        Break;
      end;
      Inc(FCompared);
      if not got then
      begin
        Miss(Format('%s s%d d%d: no picture', [cs.Strings['id'], im.Integers['s'], im.Integers['d']]));
        Continue;
      end;
      Inc(FImages);
      Inc(FCompared);
      if (el.Style.ShadowBlur <> blur)
        or ((blur > 0) and ((el.Style.ShadowOffsetX <> im.Floats['shadowOffsetX'])
          or (el.Style.ShadowOffsetY <> im.Floats['shadowOffsetY']))) then
        Miss(Format('%s s%d d%d: shadow %g at (%g, %g), upstream %g', [cs.Strings['id'],
          im.Integers['s'], im.Integers['d'], el.Style.ShadowBlur, el.Style.ShadowOffsetX,
          el.Style.ShadowOffsetY, blur]));
      if (blur > 0) and TyTryParseChartColor(im.Strings['shadowColor'], col) then
      begin
        Inc(FCompared);
        if col <> el.Style.ShadowColor then
          Miss(Format('%s d%d: shadow colour $%.8x, upstream %s', [cs.Strings['id'],
            im.Integers['d'], el.Style.ShadowColor, im.Strings['shadowColor']]));
      end;
    end;
    { THE PAINTER CAST THEM: at least one shadow per picture that has one,
      none where none has }
    Inc(FCompared);
    if (casting > 0) and (TyPainterShadowsCastForTest - before < casting) then
      Miss(Format('%s: %d pictures cast upstream, %d shadows here', [cs.Strings['id'], casting,
        TyPainterShadowsCastForTest - before]))
    else if (casting = 0) and (TyPainterShadowsCastForTest <> before) then
      Miss(Format('%s: no shadow upstream, %d here', [cs.Strings['id'], TyPainterShadowsCastForTest - before]));
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('pictures compared (%d)', [FImages]), FImages >= 40);
end;

initialization
  RegisterTest(TAdvChartImageShadowOracleTest);
end.
