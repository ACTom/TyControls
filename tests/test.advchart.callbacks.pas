unit test.advchart.callbacks;
{$mode objfpc}{$H+}
{ [R2-J2] THE FUNCTIONS AN OPTION HOLDS, AS NAMED HANDLERS, WHERE THE
  GALLERY'S ORACLE DOES NOT REACH -- the rules rather than the gallery's
  numbers:

    a series' symbolSize / symbol as '@Name' (visual/symbol.ts' callback):
      called per item with its rawValue, the item's own symbolSize over it,
      an unregistered name the series' default;
    a series' itemStyle.color as '@Name' (visual/style.ts' colorCallback):
      the item's own colour and a visualMap over it;
    a custom series' api.style / styleEmphasis label: getFormattedLabel
      (the emphasis formatter, else the normal one, else the default);
    a boxplot transform's itemNameFormatter as '@Name';
    a labelLayout handler is handed the chart's size;
    OnResolveImage: a picture an option names by URL, asked once. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.AdvanceChart,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Data,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Handlers,
     tyControls.AdvChart.Custom, tyControls.AdvChart.Dataset,
     test.advchart.customseries;
type
  TAdvChartCallbacksTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCuProbe;
    FCalls: Integer;
    FAsked: TStringList;
    FChartW: Double;
    { row 0's api.style / api.styleEmphasis text, as the renderItem got it }
    FNormText, FEmphText: string;
    function Size(const AParams: TTyChartCallbackParams): TJSONData;
    function Colour(const AParams: TTyChartCallbackParams): TJSONData;
    function Name(const AParams: TTyChartParams): string;
    function EmphName(const AParams: TTyChartParams): string;
    function Lay(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function Cell(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    procedure Resolve(Sender: TObject; const AUrl: string; var AImage: TBGRABitmap);
    procedure Show(const AOption: string; AW: Integer = 400; AH: Integer = 300);
    function SymbolWidth(ARow: Integer): Double;
    function FillOf(ARow: Integer): TTyChartColor;
    function PixelAt(AX, AY: Integer): TBGRAPixel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestASymbolSizeCallbackSizesEachItem;
    procedure TestTheItemsOwnSymbolSizeGoesOverTheCallback;
    procedure TestAnUnregisteredSymbolSizeIsTheDefault;
    procedure TestAColourCallbackColoursEachItem;
    procedure TestTheItemsOwnColourGoesOverTheCallback;
    procedure TestACustomLabelTakesItsFormatter;
    procedure TestACustomEmphasisLabelFallsBackToTheNormalFormatter;
    procedure TestABoxplotNamesItsBoxesByHandler;
    procedure TestALabelLayoutHandlerIsHandedTheChartSize;
    procedure TestAUrlImageIsAskedOnce;
    procedure TestAUrlImageWithoutAnAnswerDrawsNothing;
  end;

implementation

procedure TAdvChartCallbacksTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FAsked := TStringList.Create;
  FCalls := 0;
  FChart := TCuProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  TyChartRegisterVisualHandler('cbSize', @Size);
  TyChartRegisterVisualHandler('cbColour', @Colour);
  TyChartRegisterFormatter('cbName', @Name);
  TyChartRegisterFormatter('cbEmph', @EmphName);
  TyChartRegisterLabelLayoutHandler('cbLay', @Lay);
  TyChartRegisterRenderItem('cbCell', @Cell);
end;

procedure TAdvChartCallbacksTest.TearDown;
begin
  TyChartUnregisterVisualHandler('cbSize');
  TyChartUnregisterVisualHandler('cbColour');
  TyChartUnregisterFormatter('cbName');
  TyChartUnregisterFormatter('cbEmph');
  TyChartUnregisterLabelLayoutHandler('cbLay');
  TyChartUnregisterRenderItem('cbCell');
  FreeAndNil(FChart);
  FAsked.Free;
  FCtl.Free;
  FForm.Free;
  inherited TearDown;
end;

{ value[2] * 2: the raw item's third number }
function TAdvChartCallbacksTest.Size(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Inc(FCalls);
  if (AParams.Raw.Shape = rshArray) and (Length(AParams.Raw.Cells) > 2) then
    Result := TJSONFloatNumber.Create(AParams.Raw.Cells[2].Num * 2)
  else
    Result := nil;
end;

{ red for the first row, blue for the rest }
function TAdvChartCallbacksTest.Colour(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Inc(FCalls);
  if AParams.DataIndex = 0 then Result := TJSONString.Create('#ff0000')
  else Result := TJSONString.Create('#0000ff');
end;

function TAdvChartCallbacksTest.Name(const AParams: TTyChartParams): string;
begin
  Inc(FCalls);
  Result := 'N' + AParams[0].Status;
  if Length(AParams[0].Values) > 0 then
    Result := Result + FloatToStr(AParams[0].Values[0]);
end;

function TAdvChartCallbacksTest.EmphName(const AParams: TTyChartParams): string;
begin
  Result := 'E' + AParams[0].Status;
end;

function TAdvChartCallbacksTest.Lay(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  FChartW := AArgs.ChartWidth;
  Result := Default(TTyChartLabelLayout);
end;

{ a rect with the series' style, its label shown; row 0's two texts kept }
function TAdvChartCallbacksTest.Cell(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  p: TTyDoubleArray;
  st, se: TJSONObject;

  function TextOf(AStyle: TJSONObject): string;
  var d: TJSONData;
  begin
    d := AStyle.Find('text');
    if (d = nil) or (d.JSONType <> jtString) then Result := '<none>'
    else Result := d.AsString;
  end;

begin
  p := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  st := AApi.Style(nil);
  se := AApi.StyleEmphasis(nil);
  if AParams.DataIndexInside = 0 then
  begin
    FNormText := TextOf(st);
    FEmphText := TextOf(se);
  end;
  Result := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', p[0] - 10, 'y', p[1] - 10, 'width', 20, 'height', 20]),
    'style', st, 'styleEmphasis', se]);
end;

procedure TAdvChartCallbacksTest.Resolve(Sender: TObject; const AUrl: string;
  var AImage: TBGRABitmap);
begin
  FAsked.Add(AUrl);
  if AUrl = 'http://example.invalid/red.png' then
    AImage := TBGRABitmap.Create(10, 10, BGRA(255, 0, 0, 255));
end;

procedure TAdvChartCallbacksTest.Show(const AOption: string; AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartCallbacksTest.SymbolWidth(ARow: Integer): Double;
var i: Integer; r: TTyRectF;
begin
  i := FChart.List.IndexOfDatumInk(0, ARow);
  AssertTrue('row ' + IntToStr(ARow) + ' is drawn', i >= 0);
  r := TyShapeBounds(FChart.List.Element(i).Shape);
  Result := r.Right - r.Left;
end;

function TAdvChartCallbacksTest.FillOf(ARow: Integer): TTyChartColor;
var i: Integer;
begin
  i := FChart.List.IndexOfDatumInk(0, ARow);
  AssertTrue('row ' + IntToStr(ARow) + ' is drawn', i >= 0);
  Result := FChart.List.Element(i).Style.FillColor;
end;

function TAdvChartCallbacksTest.PixelAt(AX, AY: Integer): TBGRAPixel;
var bmp: TBGRABitmap;
begin
  bmp := FChart.RenderToBitmap('');
  try
    Result := bmp.GetPixel(AX, AY);
  finally
    bmp.Free;
  end;
end;

const
  cScatter = '{"animation": false, "xAxis": {"type": "value", "min": 0, "max": 10},'
    + ' "yAxis": {"type": "value", "min": 0, "max": 10}, "series": [{"type": "scatter",'
    + ' %s "data": [[2, 2, 5], [5, 5, 12], %s]}]}';

procedure TAdvChartCallbacksTest.TestASymbolSizeCallbackSizesEachItem;
begin
  Show(Format(cScatter, ['"symbolSize": "@cbSize",', '[8, 8, 3]']));
  AssertEquals('row 0: 5 * 2', 10, SymbolWidth(0), 1e-9);
  AssertEquals('row 1: 12 * 2', 24, SymbolWidth(1), 1e-9);
  AssertEquals('row 2: 3 * 2', 6, SymbolWidth(2), 1e-9);
  AssertTrue('called per item', FCalls >= 3);
end;

procedure TAdvChartCallbacksTest.TestTheItemsOwnSymbolSizeGoesOverTheCallback;
begin
  Show(Format(cScatter, ['"symbolSize": "@cbSize",',
    '{"value": [8, 8, 3], "symbolSize": 30}']));
  { 12 * 2: not the scatter's default 10 }
  AssertEquals('row 1 the callback''s', 24, SymbolWidth(1), 1e-9);
  AssertEquals('row 2 its own', 30, SymbolWidth(2), 1e-9);
end;

procedure TAdvChartCallbacksTest.TestAnUnregisteredSymbolSizeIsTheDefault;
begin
  { an undefined item visual falls back to the series' -- the scatter's
    circle of 10, not a symbol named '@...' (an unknown name is a rect) }
  Show(Format(cScatter, ['"symbolSize": "@nobodyRegisteredThis", "symbol": "@norThis",',
    '[8, 8, 3]']));
  AssertEquals('the scatter''s default 10', 10, SymbolWidth(1), 1e-9);
  AssertTrue('a circle, not a rect named "@..."',
    FChart.List.Element(FChart.List.IndexOfDatumInk(0, 1)).Shape.Kind <> cskRect);
end;

procedure TAdvChartCallbacksTest.TestAColourCallbackColoursEachItem;
begin
  Show(Format(cScatter, ['"itemStyle": {"color": "@cbColour"},', '[8, 8, 3]']));
  AssertEquals('row 0 red', TTyChartColor($FFFF0000), FillOf(0));
  AssertEquals('row 1 blue', TTyChartColor($FF0000FF), FillOf(1));
end;

procedure TAdvChartCallbacksTest.TestTheItemsOwnColourGoesOverTheCallback;
begin
  Show(Format(cScatter, ['"itemStyle": {"color": "@cbColour"},',
    '{"value": [8, 8, 3], "itemStyle": {"color": "#00ff00"}}']));
  AssertEquals('row 1 the callback''s', TTyChartColor($FF0000FF), FillOf(1));
  AssertEquals('row 2 its own', TTyChartColor($FF00FF00), FillOf(2));
end;

const
  cCustom = '{"animation": false, "xAxis": {"type": "value", "min": 0, "max": 10},'
    + ' "yAxis": {"type": "value", "min": 0, "max": 10}, "series": [{"type": "custom",'
    + ' "renderItem": "@cbCell", "label": {"show": true, "formatter": "@cbName"},'
    + ' %s "data": [[2, 2], [5, 5]]}]}';

procedure TAdvChartCallbacksTest.TestACustomLabelTakesItsFormatter;
begin
  { getFormattedLabel: the handler's answer, params.status 'normal'; a
    custom series' params carry no single value }
  Show(Format(cCustom, ['']));
  AssertEquals('api.style text', 'Nnormal', FNormText);
end;

procedure TAdvChartCallbacksTest.TestACustomEmphasisLabelFallsBackToTheNormalFormatter;
begin
  { styleEmphasis: retrieve3(the emphasis formatter, the normal one, the
    default) }
  Show(Format(cCustom, ['"emphasis": {"label": {"show": true}},']));
  AssertEquals('no emphasis formatter: the normal one, status normal', 'Nnormal', FEmphText);
  Show(Format(cCustom, ['"emphasis": {"label": {"show": true, "formatter": "@cbEmph"}},']));
  AssertEquals('its own, status emphasis', 'Eemphasis', FEmphText);
  AssertEquals('the normal text unchanged', 'Nnormal', FNormText);
end;

procedure TAdvChartCallbacksTest.TestABoxplotNamesItsBoxesByHandler;
var
  boxes, outs: TJSONArray;
  raw, cfg: TJSONData;
begin
  raw := GetJSON('[[1, 2, 3, 4, 5], [2, 3, 4, 5, 60]]');
  cfg := GetJSON('{"itemNameFormatter": "@cbName"}');
  try
    AssertTrue(TyPrepareBoxplotData(TJSONArray(raw), TJSONObject(cfg), boxes, outs));
    try
      AssertEquals('box 0 named by the handler, value 0', 'N0',
        TJSONArray(boxes.Items[0]).Strings[0]);
      AssertEquals('box 1', 'N1', TJSONArray(boxes.Items[1]).Strings[0]);
      AssertEquals('the outlier carries its box''s name', 'N1',
        TJSONArray(outs.Items[0]).Strings[0]);
    finally
      boxes.Free;
      outs.Free;
    end;
  finally
    raw.Free;
    cfg.Free;
  end;
end;

procedure TAdvChartCallbacksTest.TestALabelLayoutHandlerIsHandedTheChartSize;
begin
  FChartW := -1;
  Show('{"animation": false, "series": [{"type": "pie", "labelLayout": "@cbLay",'
    + ' "data": [{"value": 1, "name": "a"}, {"value": 2, "name": "b"}]}]}', 360, 240);
  AssertEquals('myChart.getWidth()', 360, FChartW, 1e-9);
end;

const
  cImage = '{"animation": false, "graphic": [{"type": "image", "left": 20, "top": 20,'
    + ' "style": {"image": "%s", "width": 40, "height": 40}}]}';

procedure TAdvChartCallbacksTest.TestAUrlImageIsAskedOnce;
var px: TBGRAPixel;
begin
  FChart.OnResolveImage := @Resolve;
  Show(Format(cImage, ['http://example.invalid/red.png']));
  px := PixelAt(40, 40);
  AssertEquals('drawn red', 255, Integer(px.red));
  AssertEquals('drawn red, not green', 0, Integer(px.green));
  AssertEquals('asked once over two draws', 1, FAsked.Count);
  AssertEquals('asked by its URL', 'http://example.invalid/red.png', FAsked[0]);
  FChart.ForgetResolvedImages;
  px := PixelAt(40, 40);
  AssertEquals('asked again after ForgetResolvedImages', 2, FAsked.Count);
  { image:// in front is not part of the URL }
  FAsked.Clear;
  FChart.ForgetResolvedImages;
  Show(Format(cImage, ['image://http://example.invalid/red.png']));
  AssertEquals('asked without the image:// prefix', 'http://example.invalid/red.png', FAsked[0]);
end;

procedure TAdvChartCallbacksTest.TestAUrlImageWithoutAnAnswerDrawsNothing;
var px: TBGRAPixel;
begin
  Show(Format(cImage, ['http://example.invalid/red.png']));
  px := PixelAt(40, 40);
  AssertTrue('nothing red without a handler', not ((px.red = 255) and (px.green = 0)));
  FChart.OnResolveImage := @Resolve;
  FChart.ForgetResolvedImages;
  Show(Format(cImage, ['http://example.invalid/other.png']));
  px := PixelAt(40, 40);
  AssertTrue('nothing red when the handler leaves it nil', not ((px.red = 255) and (px.green = 0)));
  AssertEquals('it was asked', 1, FAsked.Count);
end;

initialization
  RegisterTest(TAdvChartCallbacksTest);
end.
