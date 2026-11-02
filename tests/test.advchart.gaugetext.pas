unit test.advchart.gaugetext;
{$mode objfpc}{$H+}
{ A GAUGE'S READING THAT COUNTS IN ITS BLOCK [R7-B].

  GaugeView's animateLabelValue sets the reading's whole text at every frame,
  rich or not, a formatter function's words included. The reading is laid
  out in its block whenever its style asks for one -- always, by its
  defaults (padding [5, 10], width 100, lineHeight 30) -- so a frame of the
  count must word it at the interpolated value and lay the block out again.
  tests/fixtures/advchart-animation-an4.json's `gauge.rich-count` holds the
  words against upstream (test.advchart.animenter); this holds that the
  frame draws them: the pieces of the drawn block are the proxy's words, and
  a named formatter's words are the handler's at the interpolated value. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.AnimView,
     tyControls.AdvanceChart.Handlers, tyControls.AdvanceChart.Gauge,
     tyControls.AdvanceChart.Series, tyControls.AdvanceChart.Layout,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax, test.advchart.richwiring;
type
  TGtProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAdvChartGaugeTextTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGtProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    procedure Draw;
    function Reading(AList: TTyPaintList; out AEl: TTyChartElement): Boolean;
    function Words(const AEl: TTyChartElement): string;
    function HFmt(const AParams: TTyChartParams): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestACountingBlockIsLaidOutAgain;
    procedure TestANamedFormatterCountsInItsBlock;
    procedure TestAnAutoLabelWithNoBandsTakesTheTrack;
    procedure TestAReadingIsLaidOutInCssPxAtAnyPpi;
  end;

implementation

const
  cT0 = 1700000000000.0;

function TGtProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer = nil then Exit(inherited NewTextMeasurer(APPI));
  Result := Measurer;
end;

procedure TGtProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGtProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TGtProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-rich-text.json';
end;

procedure TAdvChartGaugeTextTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  TyChartRegisterFormatter('gaugeR7b', @HFmt);
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := TGtProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FRoot).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FRoot).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetBounds(0, 0, 400, 300);
end;

procedure TAdvChartGaugeTextTest.TearDown;
begin
  TyChartUnregisterFormatter('gaugeR7b');
  FreeAndNil(FChart);
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartGaugeTextTest.HFmt(const AParams: TTyChartParams): string;
begin
  Result := 'v' + IntToStr(Round(AParams[0].Values[0]));
end;

procedure TAdvChartGaugeTextTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
end;

function TAdvChartGaugeTextTest.Reading(AList: TTyPaintList;
  out AEl: TTyChartElement): Boolean;
var k: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  if AList = nil then Exit;
  for k := 0 to AList.Count - 1 do
    if AList.Element(k).Anim.Role = carGaugeDetail then
    begin
      AEl := AList.Element(k);
      Exit(True);
    end;
end;

{ the words a block's text pieces draw, in order }
function TAdvChartGaugeTextTest.Words(const AEl: TTyChartElement): string;
var k: Integer;
begin
  Result := '';
  for k := 0 to High(AEl.Caption.RtPieces) do
    if AEl.Caption.RtPieces[k].Kind = rpkText then
      Result := Result + AEl.Caption.RtPieces[k].Text;
end;

{ A RICH READING THAT COUNTS: at 500 ms its proxy holds the interpolated
  words, markup and all (upstream's style.text), and the frame draws them --
  the block laid out again, its plate kept; at rest it is the final value. }
procedure TAdvChartGaugeTextTest.TestACountingBlockIsLaidOutAgain;
var
  p: TTyChartAnimProxy;
  el, rest: TTyChartElement;
  shown: string;
  k, rects: Integer;
begin
  FChart.Option := '{"series":[{"type":"gauge","detail":{"valueAnimation":true,'
    + '"formatter":"{a|{value}}%","backgroundColor":"#eeeeee","rich":{"a":'
    + '{"color":"#c23531","fontSize":24}}},"data":[{"value":62,"name":"rate"}]}]}';
  AssertEquals('the option parses', '', FChart.OptionError);
  Draw;
  AssertTrue('the reading is drawn', Reading(FChart.List, rest));
  AssertEquals('at rest, the final words', '62%', Words(rest));
  FChart.AnimTick(cT0 + 500);
  p := FChart.AnimFindProxy(0, 0, 'gaugeDetail');
  AssertNotNull('the reading counts', p);
  AssertTrue('the count has words', p.HasText);
  AssertEquals('the markup is kept in the words', '{a|', Copy(p.Text, 1, 3));
  AssertTrue('the reading is in the frame', Reading(FChart.Frame, el));
  shown := StringReplace(StringReplace(p.Text, '{a|', '', []), '}', '', []);
  AssertTrue('mid-count, not the final value: ' + shown, shown <> '62%');
  AssertEquals('the frame draws the counted words', shown, Words(el));
  AssertEquals('the caption''s words are the count''s', p.Text, el.Caption.Text);
  rects := 0;
  for k := 0 to High(el.Caption.RtPieces) do
    if el.Caption.RtPieces[k].Kind = rpkRect then Inc(rects);
  AssertTrue('the plate is laid out with it', rects >= 1);
  FChart.AnimTick(cT0 + 5000);
  AssertTrue(Reading(FChart.Frame, el));
  AssertEquals('landed on the final words', '62%', Words(el));
end;

{ A NAMED FORMATTER COUNTS TOO (formatLabel(interpolatedValue, formatter)):
  its words at the frame's value [was: a handler's reading did not count] }
procedure TAdvChartGaugeTextTest.TestANamedFormatterCountsInItsBlock;
var
  p: TTyChartAnimProxy;
  el: TTyChartElement;
  v: Double;
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  FChart.Option := '{"series":[{"type":"gauge","detail":{"valueAnimation":true,'
    + '"formatter":"@gaugeR7b"},"data":[{"value":80,"name":"rate"}]}]}';
  AssertEquals('the option parses', '', FChart.OptionError);
  Draw;
  AssertTrue(Reading(FChart.List, el));
  AssertEquals('at rest, the handler''s words', 'v80', Words(el));
  FChart.AnimTick(cT0 + 500);
  p := FChart.AnimFindProxy(0, 0, 'gaugeDetail');
  AssertNotNull('the reading counts', p);
  AssertTrue(Reading(FChart.Frame, el));
  v := StrToFloat(p.Text, fs);
  AssertTrue('mid-count', (v > 0) and (v < 80));
  AssertEquals('the handler''s words at the frame''s value',
    'v' + IntToStr(Round(v)), Words(el));
end;

{ AN 'auto' AXIS LABEL ON A DIAL WITH NO BANDS OF ITS OWN: getColor runs over
  the default axisLine colour, one band at 1 -- the track's colour, which a
  skin decides here -- not the label's own [was: the label's colour] }
procedure TAdvChartGaugeTextTest.TestAnAutoLabelWithNoBandsTakesTheTrack;
var
  spec: TTyGaugeSpec;
  vis: TTyGaugeVisual;
  lst: TTyPaintList;
  b: TTySeriesBinding;
  k, n: Integer;
begin
  spec := TyGaugeSpecDefault;
  spec.AxisLabel.Auto := True;
  vis := TyGaugeVisual;
  vis.Track := TTyChartColor($FF112233);
  vis.LabelColour := TTyChartColor($FF445566);
  b := Default(TTySeriesBinding);
  b.SeriesType := TyGaugeSeriesTypeName;
  b.Resolved := True;
  lst := TTyPaintList.Create;
  try
    TyBuildGaugeAxis(b, TyGaugeLayoutOf(spec, TyRectF(0, 0, 400, 300), 96), spec,
      vis, TTyPainterTextMeasurer.Create(96), 96, lst);
    n := 0;
    for k := 0 to lst.Count - 1 do
      if lst.Element(k).Caption.FontSizeLogical > 0 then
      begin
        Inc(n);
        AssertEquals('label ' + lst.Element(k).Caption.Text + ' in the track''s colour',
          IntToHex($FF112233, 8), IntToHex(lst.Element(k).Caption.Colour, 8));
      end;
    AssertEquals('the eleven labels', 11, n);
  finally
    lst.Free;
  end;
end;

{ THE READING'S BLOCK IN CSS px WHATEVER THE PPI: width '60%' and height
  '20%' are parsePercent of the radius in CSS px (150 here: 90 x 30), so a
  dial twice as many device px across lays out the same block }
procedure TAdvChartGaugeTextTest.TestAReadingIsLaidOutInCssPxAtAnyPpi;
var
  opt: TTyChartOption;
  spec: TTyGaugeSpec;
  ssr: ITyTextMeasurer;
  a, b: TTyRtPieceArray;
  k: Integer;
begin
  opt := TTyChartOption.Create;
  try
    AssertTrue(opt.SetOptionText('{"series":[{"type":"gauge","detail":{"width":"60%",'
      + '"height":"20%","backgroundColor":"#dddddd","fontSize":20}}]}'));
    spec := TyGaugeSpecOf(opt, 0);
  finally
    opt.Free;
  end;
  ssr := TZrSsrMeasurer.Create(
    TJSONObject(FRoot).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FRoot).Objects['ratios'].Integers['firstCode']);
  a := TyGaugeTextPieces(spec.Detail, '37', 150, 0, 0, 'sans-serif', 0, 400,
    TPtToPxMeasurer.Create(ssr), 96);
  b := TyGaugeTextPieces(spec.Detail, '37', 300, 0, 0, 'sans-serif', 0, 400,
    TRwDpiMeasurer.Create(TPtToPxMeasurer.Create(ssr), 2), 192);
  AssertEquals('as many pieces', Length(a), Length(b));
  AssertTrue('a plate and the words', Length(a) >= 2);
  AssertEquals('the plate, padding in: 90 + 20 wide', 110.0, a[0].W, 1e-9);
  AssertEquals('30 + 10 tall', 40.0, a[0].H, 1e-9);
  for k := 0 to High(a) do
  begin
    AssertEquals(Format('piece %d x', [k]), a[k].X, b[k].X, 1e-9);
    AssertEquals(Format('piece %d y', [k]), a[k].Y, b[k].Y, 1e-9);
    AssertEquals(Format('piece %d w', [k]), a[k].W, b[k].W, 1e-9);
    AssertEquals(Format('piece %d h', [k]), a[k].H, b[k].H, 1e-9);
  end;
end;

initialization
  RegisterTest(TAdvChartGaugeTextTest);
end.
