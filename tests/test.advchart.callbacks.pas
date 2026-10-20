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
    OnResolveImage: a picture an option names by URL, asked once.

  [R2-J3] WHAT AN ANIMATION TIMING FUNCTION IS HANDED
  (tools/advchart-oracle/anim-timing-args.js): the root's animationDelay,
  animationDuration and their Update twins as '@Name', on fifteen charts
  of most series types, on the first set and on an update -- per key, the
  set of (dataIndex, extraDelayParams) every call is handed, upstream's.

  [R2-J3] THE PER-ITEM VISUAL CALLBACKS ON EVERY SERIES
  (tools/advchart-oracle/visual-callbacks.js): symbol, symbolSize,
  symbolRotate and symbolOffset on a line, a scatter, an effectScatter, a
  graph, a radar, a tree, a pictorial bar and a markPoint; the colour
  callback on those and on a bar, a pie, a funnel, a boxplot (borderColor),
  lines and parallel (lineStyle.color) -- the calls' arguments, and what
  every item's element draws. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.AdvanceChart,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Handlers,
     tyControls.AdvanceChart.Custom, tyControls.AdvanceChart.Dataset,
     tyControls.AdvanceChart.AnimOpt, tyControls.AdvanceChart.Symbol,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Tooltip,
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
    { [R2-J3] the markers a tooltip formatter was handed, '|'-joined }
    FMarkers: string;
    function Tip(const AParams: TTyChartParams): string;
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
    { [R2-J3] }
    procedure TestATooltipFormatterIsHandedItsMarker;
    procedure TestAFormattersMarkerIsADot;
    procedure TestARowAZoomBringsInIsAskedToo;
  end;

  { [R2-J3] the visual callbacks of every series, upstream's }
  TAdvChartVisualCallbacksOracleTest = class(TCuOracleBase)
  private
    FLog: TStringList;
    procedure Note(const AKey: string; const AParams: TTyChartCallbackParams);
    function HSym(const AParams: TTyChartCallbackParams): TJSONData;
    function HSize(const AParams: TTyChartCallbackParams): TJSONData;
    function HRot(const AParams: TTyChartCallbackParams): TJSONData;
    function HOff(const AParams: TTyChartCallbackParams): TJSONData;
    function HCol(const AParams: TTyChartCallbackParams): TJSONData;
    function ElementsOf(ASeries, ARaw: Integer): TTyIntegerArray;
    procedure CheckItem(AItem: TJSONObject);
    procedure RunIds(const AIds: array of string);
  protected
    function FixtureName: string; override;
    function NewMirror: TCuMirror; override;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLineAndScatterSymbolsAreUpstreams;
    procedure TestTheGraphRadarAndTreeSymbolsAreUpstreams;
    procedure TestThePictorialBarIsUpstreams;
    procedure TestTheColourCallbacksAreUpstreams;
    procedure TestTheMarkPointSymbolsAreUpstreams;
  end;

  { [R2-J3] the arguments of every timing function call, upstream's }
  TAdvChartAnimTimingArgsTest = class(TCuOracleBase)
  private
    FLog: array[0..3] of TStringList;
    { [R2-I7] every call in order }
    FSeq: TStringList;
    FSeqOn: Boolean;
    procedure Note(AKey: Integer; ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams);
    procedure CompareSeq(const APhase: string; AWant: TJSONData);
    function HDelay(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
    function HDuration(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
    function HDelayUpdate(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
    function HDurationUpdate(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
    procedure Compare(const APhase: string; AWant: TJSONObject);
    procedure RunIds(const AIds: array of string);
  protected
    function FixtureName: string; override;
    function NewMirror: TCuMirror; override;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCartesianSeriesAreUpstreams;
    procedure TestThePictorialBarHandsItsGlyphsPlace;
    procedure TestTheOtherSeriesAreUpstreams;
    { [R2-I7] the line's calls in upstream's order: the series' duration
      and delay with null once, then each symbol's }
    procedure TestTheLineCallsInUpstreamsOrder;
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

{ [R2-J3] writes down every params.marker it is handed; answers the first
  one before the series' name, as flame-graph's formatter does }
function TAdvChartCallbacksTest.Tip(const AParams: TTyChartParams): string;
var i: Integer;
begin
  FMarkers := '';
  for i := 0 to High(AParams) do FMarkers := FMarkers + '|' + AParams[i].Marker;
  Result := '';
  if Length(AParams) > 0 then Result := AParams[0].Marker + ' ' + AParams[0].SeriesName;
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

{ ==================== [R2-J3] visual callbacks ==================== }

const
  cVcSyms: array[0..3] of string = ('circle', 'rect', 'triangle', 'diamond');
  cVcCols: array[0..3] of string = ('#c23531', '#2f4554', '#61a0a8', '#d48265');

function TAdvChartVisualCallbacksOracleTest.FixtureName: string;
begin
  Result := 'advchart-visual-callbacks.json';
end;

function TAdvChartVisualCallbacksOracleTest.NewMirror: TCuMirror;
begin
  Result := TCuMirror.Create;
end;

procedure TAdvChartVisualCallbacksOracleTest.SetUp;
begin
  inherited SetUp;
  FLog := TStringList.Create;
  FLog.Sorted := True;
  FLog.Duplicates := dupIgnore;
  FLog.CaseSensitive := True;
  FLog.UseLocale := False;
  TyChartRegisterVisualHandler('vsym', @HSym);
  TyChartRegisterVisualHandler('vsize', @HSize);
  TyChartRegisterVisualHandler('vrot', @HRot);
  TyChartRegisterVisualHandler('voff', @HOff);
  TyChartRegisterVisualHandler('vcol', @HCol);
end;

procedure TAdvChartVisualCallbacksOracleTest.TearDown;
begin
  TyChartUnregisterVisualHandler('vsym');
  TyChartUnregisterVisualHandler('vsize');
  TyChartUnregisterVisualHandler('vrot');
  TyChartUnregisterVisualHandler('voff');
  TyChartUnregisterVisualHandler('vcol');
  FreeAndNil(FLog);
  inherited TearDown;
end;

function ColourKey(AColour: TTyChartColor): string;
begin
  Result := LowerCase(IntToHex(AColour, 8));
end;

{ a call as the oracle writes it, the colour as a number: 'v:<String(raw)>
  i:<dataIndex> s:<seriesIndex> t:<dataType> n:<name> c:<colour>' }
procedure TAdvChartVisualCallbacksOracleTest.Note(const AKey: string;
  const AParams: TTyChartCallbackParams);
begin
  FLog.Add(AKey + ' v:' + AParams.ValueText + ' i:' + IntToStr(AParams.DataIndex)
    + ' s:' + IntToStr(AParams.SeriesIndex) + ' t:' + AParams.DataType
    + ' n:' + AParams.Name + ' c:' + ColourKey(AParams.Color));
end;

function TAdvChartVisualCallbacksOracleTest.HSym(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Note('vsym', AParams);
  Result := TJSONString.Create(cVcSyms[AParams.DataIndex mod 4]);
end;

function TAdvChartVisualCallbacksOracleTest.HSize(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Note('vsize', AParams);
  Result := TJSONIntegerNumber.Create(8 + 3 * AParams.DataIndex);
end;

function TAdvChartVisualCallbacksOracleTest.HRot(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Note('vrot', AParams);
  Result := TJSONIntegerNumber.Create(30 * AParams.DataIndex);
end;

function TAdvChartVisualCallbacksOracleTest.HOff(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Note('voff', AParams);
  Result := TJSONArray.Create([2 * AParams.DataIndex, -AParams.DataIndex]);
end;

function TAdvChartVisualCallbacksOracleTest.HCol(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Note('vcol', AParams);
  Result := TJSONString.Create(cVcCols[AParams.DataIndex mod 4]);
end;

{ the elements of a series' item, a markPoint's when ASeries < 0 (its host
  -ASeries - 1), in paint order, its text left out }
function TAdvChartVisualCallbacksOracleTest.ElementsOf(ASeries, ARaw: Integer): TTyIntegerArray;
var
  lst: TTyPaintList;
  i: Integer;
  el: TTyChartElement;
  ok: Boolean;
begin
  Result := nil;
  lst := FChart.List;
  if lst = nil then Exit;
  for i := 0 to lst.Count - 1 do
  begin
    el := lst.Element(i);
    if el.Anim.Role in [carLabel, carGuide, carMarkPointLabel, carEndLabel] then Continue;
    if ASeries >= 0 then
      ok := (el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex = ASeries)
        and (el.Datum.RawDataIndex = ARaw) and not el.Datum.IsEdge
    else
      ok := (el.Anim.Role = carMarkPoint) and (el.Anim.Series = -ASeries - 1)
        and (el.Anim.Index = ARaw);
    if not ok then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := i;
  end;
end;

{ '|a|b' with its parts sorted }
function SortedBars(const S: string): string;
var sl: TStringList; i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Delimiter := '|';
    sl.StrictDelimiter := True;
    sl.DelimitedText := Copy(S, 2, MaxInt);
    sl.UseLocale := False;
    sl.CaseSensitive := True;
    sl.Sort;
    Result := '';
    if S = '' then Exit;
    for i := 0 to sl.Count - 1 do Result := Result + '|' + sl[i];
  finally
    sl.Free;
  end;
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AData.AsString);
  Move(q, Result, SizeOf(Result));
end;

procedure TAdvChartVisualCallbacksOracleTest.CheckItem(AItem: TJSONObject);
var
  els: TTyIntegerArray;
  s, i, k, n, j: Integer;
  el: TTyChartElement;
  spec: TTySymbolSpec;
  want: TTyChartShape;
  c: TTyChartColor;
  what, sym, path: string;
  empty: Boolean;
  isMark: Boolean;

  function Near(A, B: Double): Boolean;
  begin
    if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
    if IsInfinite(A) or IsInfinite(B) then Exit(A = B);
    Result := Abs(A - B) <= 1e-9 * Max(Double(1), Abs(B));
  end;

  procedure Colour(const AWhat: string; AHas: Boolean; AGot: TTyChartColor; AWant: TJSONData);
  begin
    if (AWant = nil) or (AWant.JSONType <> jtString) or (AWant.AsString = 'none') then Exit;
    Inc(FCompared);
    if not TyTryParseChartColor(AWant.AsString, c) then Exit;
    if not AHas or (ColourKey(AGot) <> ColourKey(c)) then
      Bad(Format('%s %s: %s, upstream %s', [what, AWhat, ColourKey(AGot), AWant.AsString]));
  end;

begin
  s := AItem.Integers['s'];
  i := AItem.Integers['i'];
  isMark := AItem.Find('mark') <> nil;
  what := Format('%s s%d i%d', [FWhere, s, i]);
  if AItem.Find('none') <> nil then Exit;
  if isMark then els := ElementsOf(-s - 1, i) else els := ElementsOf(s, i);
  if AItem.Find('n') <> nil then
  begin
    { a pictorial bar: its glyphs, the first one's scale and turn }
    n := 0;
    for j := 0 to High(els) do
      if FChart.List.Element(els[j]).Anim.Role = carPictorialGlyph then Inc(n);
    SameInt(what + ' glyphs', n, AItem.Integers['n']);
    for j := 0 to High(els) do
    begin
      el := FChart.List.Element(els[j]);
      if (el.Anim.Role <> carPictorialGlyph) or (el.Anim.Sub <> 0) then Continue;
      if (AItem.Find('gsym') <> nil) and (AItem.Find('gsym').JSONType = jtString) then
        SameStr(what + ' glyph symbol', el.Caption.LgSymbol, AItem.Strings['gsym']);
      Same(what + ' glyph sx', el.Anim.G[2], AItem.Find('sx'));
      Same(what + ' glyph sy', el.Anim.G[3], AItem.Find('sy'));
      Same(what + ' glyph rot', el.Anim.G[5], AItem.Find('rot'));
      Colour('glyph fill', el.Style.HasFill, el.Style.FillColor, AItem.Find('fill'));
    end;
    Exit;
  end;
  if isMark then
  begin
    { a markPoint's symbol is zrender's path: where its origin lands and its
      scale there (the pop-in's tag), and its colours }
    Inc(FCompared);
    if Length(els) = 0 then
    begin
      Bad(what + ': no markPoint element');
      Exit;
    end;
    el := FChart.List.Element(els[0]);
    Same(what + ' mark x', el.Anim.G[0], AItem.Find('cx'));
    Same(what + ' mark y', el.Anim.G[1], AItem.Find('cy'));
    Same(what + ' mark sx', el.Anim.G[2], AItem.Find('gsx'));
    Same(what + ' mark sy', el.Anim.G[3], AItem.Find('gsy'));
    Colour('fill', el.Style.HasFill, el.Style.FillColor, AItem.Find('fill'));
    Colour('stroke', el.Style.StrokeWidthLogical > 0, el.Style.StrokeColor, AItem.Find('stroke'));
    Exit;
  end;
  if AItem.Find('sym') <> nil then
  begin
    { a symbol: the k-th symbol element of the item (a radar's vertex k), the
      shape the port builds for the spec upstream drew, and its colours }
    k := 0;
    if AItem.Find('k') <> nil then k := AItem.Integers['k'];
    n := -1;
    for j := 0 to High(els) do
    begin
      el := FChart.List.Element(els[j]);
      if el.Shape.Kind in [cskPolyline, cskSector] then Continue;
      if (el.Anim.Role in [carRadarLine, carRadarArea]) then Continue;
      Dec(k);
      if k < 0 then
      begin
        n := els[j];
        Break;
      end;
    end;
    Inc(FCompared);
    if n < 0 then
    begin
      Bad(what + ': no symbol element');
      Exit;
    end;
    el := FChart.List.Element(n);
    sym := AItem.Strings['sym'];
    spec := TySymbolDefault('scatter');
    spec.Kind := TySymbolKindOf(sym, empty, path);
    spec.Empty := empty;
    spec.WidthPx := 2 * HexNum(AItem.Find('gsx'));
    spec.HeightPx := 2 * HexNum(AItem.Find('gsy'));
    spec.RotateDeg := HexNum(AItem.Find('rot')) * 180 / Pi;
    want := TyBuildSymbol(spec, HexNum(AItem.Find('cx')), HexNum(AItem.Find('cy')));
    Inc(FCompared);
    if (el.Shape.Kind <> want.Kind) or not Near(el.Shape.Bounds.Left, want.Bounds.Left)
      or not Near(el.Shape.Bounds.Top, want.Bounds.Top)
      or not Near(el.Shape.Bounds.Right, want.Bounds.Right)
      or not Near(el.Shape.Bounds.Bottom, want.Bounds.Bottom)
      or not Near(el.Shape.CX, want.CX) or not Near(el.Shape.CY, want.CY)
      or not Near(el.Shape.R1, want.R1)
      or (Length(el.Shape.Points) <> Length(want.Points)) then
      Bad(Format('%s %s: shape %d [%g %g %g %g], upstream''s %d [%g %g %g %g]',
        [what, sym, Ord(el.Shape.Kind), el.Shape.Bounds.Left, el.Shape.Bounds.Top,
         el.Shape.Bounds.Right, el.Shape.Bounds.Bottom, Ord(want.Kind),
         want.Bounds.Left, want.Bounds.Top, want.Bounds.Right, want.Bounds.Bottom]))
    else
      for j := 0 to High(want.Points) do
        if not (Near(el.Shape.Points[j].X, want.Points[j].X)
          and Near(el.Shape.Points[j].Y, want.Points[j].Y)) then
        begin
          Bad(Format('%s %s: point %d (%g, %g), upstream''s (%g, %g)', [what, sym, j,
            el.Shape.Points[j].X, el.Shape.Points[j].Y, want.Points[j].X, want.Points[j].Y]));
          Break;
        end;
    if empty then
      Colour('stroke', el.Style.StrokeWidthLogical > 0, el.Style.StrokeColor, AItem.Find('stroke'))
    else
      Colour('fill', el.Style.HasFill, el.Style.FillColor, AItem.Find('fill'));
    Exit;
  end;
  { anything else: the item's first element's colours }
  Inc(FCompared);
  if Length(els) = 0 then
  begin
    Bad(what + ': no element');
    Exit;
  end;
  el := FChart.List.Element(els[0]);
  Colour('fill', el.Style.HasFill, el.Style.FillColor, AItem.Find('fill'));
  Colour('stroke', el.Style.StrokeWidthLogical > 0, el.Style.StrokeColor, AItem.Find('stroke'));
end;

procedure TAdvChartVisualCallbacksOracleTest.RunIds(const AIds: array of string);
var
  all, items, want: TJSONArray;
  c, calls: TJSONObject;
  i, j, k, p: Integer;
  exp, got, s, key, cs: string;
  cc: TTyChartColor;
begin
  all := TJSONObject(FRoot).Arrays['cases'];
  for j := 0 to High(AIds) do
  begin
    c := nil;
    for i := 0 to all.Count - 1 do
      if all.Objects[i].Strings['id'] = AIds[j] then c := all.Objects[i];
    AssertTrue(AIds[j] + ' is in the fixture', c <> nil);
    FWhere := AIds[j];
    FLog.Clear;
    NewChart(TJSONObject(FRoot).Integers['W'], TJSONObject(FRoot).Integers['H']);
    s := c.Objects['option'].AsJSON;
    FChart.SetOption('{"animation":false,' + Copy(s, 2, MaxInt), True);
    RenderNow;
    { the calls: per callback, the set -- a colour as a number }
    calls := c.Objects['calls'];
    for k := 0 to 4 do
    begin
      case k of
        0: key := 'vsym';
        1: key := 'vsize';
        2: key := 'vrot';
        3: key := 'voff';
      else
        key := 'vcol';
      end;
      exp := '';
      if calls.IndexOfName(key) >= 0 then
      begin
        want := calls.Arrays[key];
        for i := 0 to want.Count - 1 do
        begin
          s := want.Strings[i];
          p := Pos(' c:', s);
          cs := Copy(s, p + 3, MaxInt);
          if (cs <> '') and TyTryParseChartColor(cs, cc) then
            cs := ColourKey(cc)
          else
            cs := '?';
          exp := exp + '|' + key + ' ' + Copy(s, 1, Pos(' c:', s) - 1) + ' c:' + cs;
        end;
      end;
      got := '';
      for i := 0 to FLog.Count - 1 do
        if Copy(FLog[i], 1, Length(key) + 1) = key + ' ' then
        begin
          s := FLog[i];
          { upstream hands no colour (a marker's params): not compared }
          if Pos(' c:?', exp) > 0 then s := Copy(s, 1, Pos(' c:', s) - 1) + ' c:?';
          got := got + '|' + s;
        end;
      SameStr(AIds[j] + ' ' + key + ' calls', SortedBars(got), SortedBars(exp));
    end;
    items := c.Arrays['items'];
    for i := 0 to items.Count - 1 do CheckItem(items.Objects[i]);
    FChart.Measurer := nil;
    FreeAndNil(FChart);
  end;
end;

procedure TAdvChartVisualCallbacksOracleTest.TestTheLineAndScatterSymbolsAreUpstreams;
begin
  RunIds(['line', 'scatter']);
  Finish('line and scatter', 30);
end;

procedure TAdvChartVisualCallbacksOracleTest.TestTheGraphRadarAndTreeSymbolsAreUpstreams;
begin
  RunIds(['graph', 'radar', 'tree']);
  Finish('graph, radar, tree', 30);
end;

procedure TAdvChartVisualCallbacksOracleTest.TestThePictorialBarIsUpstreams;
begin
  RunIds(['pictorial']);
  Finish('pictorial', 10);
end;

procedure TAdvChartVisualCallbacksOracleTest.TestTheColourCallbacksAreUpstreams;
begin
  RunIds(['bar-pie-funnel', 'stroke-series']);
  Finish('colour', 20);
end;

procedure TAdvChartVisualCallbacksOracleTest.TestTheMarkPointSymbolsAreUpstreams;
begin
  RunIds(['markpoint']);
  Finish('markPoint', 5);
end;

{ ==================== [R2-J3] timing arguments ==================== }

const
  cTimingKeys: array[0..3] of string = ('animationDelay', 'animationDuration',
    'animationDelayUpdate', 'animationDurationUpdate');

function TAdvChartAnimTimingArgsTest.FixtureName: string;
begin
  Result := 'advchart-anim-timing-args.json';
end;

function TAdvChartAnimTimingArgsTest.NewMirror: TCuMirror;
begin
  Result := TCuMirror.Create;
end;

procedure TAdvChartAnimTimingArgsTest.SetUp;
var k: Integer;
begin
  inherited SetUp;
  for k := 0 to 3 do
  begin
    FLog[k] := TStringList.Create;
    FLog[k].Sorted := True;
    FLog[k].Duplicates := dupIgnore;
    FLog[k].CaseSensitive := True;
    FLog[k].UseLocale := False;
  end;
  FSeq := TStringList.Create;
  TyChartRegisterAnimDelay('ad', @HDelay);
  TyChartRegisterAnimDelay('aD', @HDuration);
  TyChartRegisterAnimDelay('adu', @HDelayUpdate);
  TyChartRegisterAnimDelay('aDu', @HDurationUpdate);
end;

procedure TAdvChartAnimTimingArgsTest.TearDown;
var k: Integer;
begin
  TyChartUnregisterAnimDelay('ad');
  TyChartUnregisterAnimDelay('aD');
  TyChartUnregisterAnimDelay('adu');
  TyChartUnregisterAnimDelay('aDu');
  for k := 0 to 3 do FreeAndNil(FLog[k]);
  FreeAndNil(FSeq);
  inherited TearDown;
end;

{ a call as the oracle writes it: 'i:<index> p:<params>' }
procedure TAdvChartAnimTimingArgsTest.Note(AKey: Integer; ADataIndex: Integer;
  AHasIndex: Boolean; const AParams: TTyAnimDelayParams);
var a, p: string;
begin
  { [R2-I7] null 'z', undefined 'u' }
  if AHasIndex then a := 'i:n:' + IntToStr(ADataIndex)
  else if AParams.IndexNull then a := 'i:z'
  else a := 'i:u';
  if not AParams.Present then p := 'u'
  else
  begin
    p := '';
    if AParams.HasCount then p := '"count":"' + HexOf(AParams.Count) + '"';
    if AParams.HasIndex then
    begin
      if p <> '' then p := p + ',';
      p := p + '"index":"' + HexOf(AParams.Index) + '"';
    end;
    p := 'j:{' + p + '}';
  end;
  FLog[AKey].Add(a + ' p:' + p);
  FSeq.Add(cTimingKeys[AKey] + ' ' + a + ' p:' + p);
end;

procedure TAdvChartAnimTimingArgsTest.CompareSeq(const APhase: string; AWant: TJSONData);
var
  j: Integer;
  got, exp: string;
begin
  if not FSeqOn or (AWant = nil) or not (AWant is TJSONArray) then Exit;
  exp := '';
  for j := 0 to AWant.Count - 1 do exp := exp + '|' + TJSONArray(AWant).Strings[j];
  got := '';
  for j := 0 to FSeq.Count - 1 do got := got + '|' + FSeq[j];
  SameStr(APhase + ' in order', got, exp);
end;

function TAdvChartAnimTimingArgsTest.HDelay(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  Note(0, ADataIndex, AHasIndex, AParams);
  Result := 0;
end;

function TAdvChartAnimTimingArgsTest.HDuration(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  Note(1, ADataIndex, AHasIndex, AParams);
  Result := 300;
end;

function TAdvChartAnimTimingArgsTest.HDelayUpdate(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  Note(2, ADataIndex, AHasIndex, AParams);
  Result := 0;
end;

function TAdvChartAnimTimingArgsTest.HDurationUpdate(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  Note(3, ADataIndex, AHasIndex, AParams);
  Result := 300;
end;

{ NOT COMPARED -- nothing since R2-I7 (spec §229f), which animated what
  R2-J3 listed here: the markPoint a merge moves to another category (paired
  by its mpData id), a pictorial bar's update, a removed tree node's label
  and a treemap's kept labels (LabelManager's pass). The list stays, empty,
  for the next one. }
function TimingSkipped(const AWhat: string): Boolean;
const
  cSkip: array[0..7] of string = ('', '', '', '', '', '', '', '');
var i: Integer;
begin
  for i := 0 to High(cSkip) do
    if (cSkip[i] <> '') and (AWhat = cSkip[i]) then Exit(True);
  Result := False;
end;

procedure TAdvChartAnimTimingArgsTest.Compare(const APhase: string; AWant: TJSONObject);
var
  k, j: Integer;
  want: TJSONArray;
  got, exp: string;
begin
  for k := 0 to 3 do
  begin
    if TimingSkipped(APhase + ' ' + cTimingKeys[k]) then
    begin
      FLog[k].Clear;
      Continue;
    end;
    exp := '';
    if AWant.IndexOfName(cTimingKeys[k]) >= 0 then
    begin
      want := AWant.Arrays[cTimingKeys[k]];
      for j := 0 to want.Count - 1 do exp := exp + '|' + want.Strings[j];
    end;
    got := '';
    for j := 0 to FLog[k].Count - 1 do got := got + '|' + FLog[k][j];
    SameStr(APhase + ' ' + cTimingKeys[k], got, exp);
    FLog[k].Clear;
  end;
end;

procedure TAdvChartAnimTimingArgsTest.RunIds(const AIds: array of string);
var
  all: TJSONArray;
  c: TJSONObject;
  i, j, k: Integer;
begin
  all := TJSONObject(FRoot).Arrays['cases'];
  for j := 0 to High(AIds) do
  begin
    c := nil;
    for i := 0 to all.Count - 1 do
      if all.Objects[i].Strings['id'] = AIds[j] then c := all.Objects[i];
    AssertTrue(AIds[j] + ' is in the fixture', c <> nil);
    FWhere := AIds[j];
    for k := 0 to 3 do FLog[k].Clear;
    FSeq.Clear;
    NewChart(TJSONObject(FRoot).Integers['W'], TJSONObject(FRoot).Integers['H']);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := 1700000000000;
    FChart.SetOption(c.Objects['option'].AsJSON);
    RenderNow;
    Compare(AIds[j] + ' enter', c.Objects['enter']);
    CompareSeq(AIds[j] + ' enter', c.Find('enterSeq'));
    FSeq.Clear;
    FChart.AnimNow := 1700000000050;
    FChart.SetOption(c.Objects['update'].AsJSON);
    RenderNow;
    Compare(AIds[j] + ' update', c.Objects['updated']);
    { NOT the update's order: the same calls, but the port arms the line's
      clip (enter timing) at its polyline, before the axes' and the
      symbols' updates, where upstream makes it after them -- the spec's
      deviation (R2-I7) }
    FSeq.Clear;
    FChart.Measurer := nil;
    FreeAndNil(FChart);
  end;
end;

procedure TAdvChartAnimTimingArgsTest.TestTheCartesianSeriesAreUpstreams;
begin
  RunIds(['line', 'bar', 'scatter', 'candle-box', 'heatmap', 'markers']);
  Finish('cartesian', 24);
end;

procedure TAdvChartAnimTimingArgsTest.TestThePictorialBarHandsItsGlyphsPlace;
begin
  RunIds(['pictorial']);
  Finish('pictorial', 6);
end;

procedure TAdvChartAnimTimingArgsTest.TestTheLineCallsInUpstreamsOrder;
begin
  FSeqOn := True;
  RunIds(['line']);
  Finish('line in order', 5);
end;

procedure TAdvChartAnimTimingArgsTest.TestTheOtherSeriesAreUpstreams;
begin
  RunIds(['pie', 'funnel', 'gauge', 'radar', 'graph', 'tree', 'treemap', 'sunburst']);
  Finish('the others', 32);
end;

{ [R2-J3] params.marker: the richText dot a tooltip formatter is handed,
  the empty rich token of style __EC_aUTo_<n> and two spaces, one per
  series' params in order (an item tooltip's one, an axis tooltip's each)
  [R2-I8: in richText mode -- written here; html mode's is the span] }
procedure TAdvChartCallbacksTest.TestATooltipFormatterIsHandedItsMarker;
const
  cItem = '{"animation":false,"tooltip":{"formatter":"@cbTip","renderMode":"richText"},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"s","data":[3,5,2]}]}';
  cAxis = '{"animation":false,"tooltip":{"trigger":"axis","formatter":"@cbTip","renderMode":"richText"},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"s","data":[3,5,2]},'
    + '{"type":"line","name":"t","data":[1,4,6]}]}';
  procedure Again;
  var bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    finally
      bmp.Free;
    end;
  end;
begin
  TyChartRegisterFormatter('cbTip', @Tip);
  try
    Show(cItem);
    FMarkers := '';
    FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":1}');
    Again;
    AssertEquals('an item tooltip: one marker', '|{__EC_aUTo_0|}  ', FMarkers);
    Show(cAxis);
    FMarkers := '';
    FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":1}');
    Again;
    AssertEquals('an axis tooltip: one per series, numbered in order',
      '|{__EC_aUTo_0|}  |{__EC_aUTo_1|}  ', FMarkers);
  finally
    TyChartUnregisterFormatter('cbTip');
  end;
end;

{ [R2-J3] the formatter's text: a marker it names becomes that params'
  dot, split out of the text; a token of no marker stays text }
procedure TAdvChartCallbacksTest.TestAFormattersMarkerIsADot;
var
  lines: TTyTooltipLineArray;
  ink: TTyTooltipInk;
begin
  ink := Default(TTyTooltipInk);
  ink.MarkerSizeLogical := 10;
  SetLength(lines, 1);
  SetLength(lines[0].Runs, 1);
  lines[0].Runs[0].Kind := ttrText;
  lines[0].Runs[0].Text := 'a{__EC_aUTo_1|}b {x|}c{__EC_aUTo_0|}';
  lines[0].Runs[0].Colour := $FF123456;
  TyTooltipSplitMarkers(lines, ['__EC_aUTo_0', '__EC_aUTo_1'],
    [TTyChartColor($FFFF0000), TTyChartColor($FF00FF00)], ink);
  AssertEquals('four runs', 4, Length(lines[0].Runs));
  AssertEquals('text first', 'a', lines[0].Runs[0].Text);
  AssertTrue('then the second marker''s dot', lines[0].Runs[1].Kind = ttrMarker);
  AssertEquals('in its colour', IntToHex($FF00FF00, 8), IntToHex(lines[0].Runs[1].Colour, 8));
  AssertEquals('the dot''s size', 10.0, lines[0].Runs[1].MarkerSizeLogical, 0);
  AssertEquals('the rest, a name of no marker kept', 'b {x|}c', lines[0].Runs[2].Text);
  AssertEquals('the text keeps its ink', IntToHex($FF123456, 8), IntToHex(lines[0].Runs[2].Colour, 8));
  AssertTrue('the first marker''s dot last', lines[0].Runs[3].Kind = ttrMarker);
  AssertEquals('in its colour', IntToHex($FFFF0000, 8), IntToHex(lines[0].Runs[3].Colour, 8));
end;

{ [R2-J3] the callbacks are asked once per update for the rows in view: a
  row a dataZoom window brings in afterwards is asked then, not left at the
  series' default }
procedure TAdvChartCallbacksTest.TestARowAZoomBringsInIsAskedToo;
var bmp: TBGRABitmap;
begin
  Show('{"animation": false, "xAxis": {"type": "value", "min": 0, "max": 10},'
    + ' "yAxis": {"type": "value", "min": 0, "max": 10},'
    + ' "dataZoom": [{"type": "inside", "xAxisIndex": 0, "filterMode": "filter",'
    + ' "startValue": 0, "endValue": 4}],'
    + ' "series": [{"type": "scatter", "symbolSize": "@cbSize",'
    + ' "data": [[2, 2, 5], [5, 5, 12], [8, 8, 3]]}]}');
  AssertEquals('the one row in view: 5 * 2', 10, SymbolWidth(0), 1e-9);
  FChart.DispatchAction('{"type": "dataZoom", "startValue": 4, "endValue": 10}');
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  finally
    bmp.Free;
  end;
  AssertEquals('the row brought in: 12 * 2', 24, SymbolWidth(0), 1e-9);
  AssertEquals('and the next: 3 * 2', 6, SymbolWidth(1), 1e-9);
end;

initialization
  RegisterTest(TAdvChartCallbacksTest);
  RegisterTest(TAdvChartAnimTimingArgsTest);
  RegisterTest(TAdvChartVisualCallbacksOracleTest);
end.
